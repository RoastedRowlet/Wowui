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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Priest-Shadow','Priest-Holy','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','DeathKnight-Frost','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Protection','Shaman-Enhancement','Priest-Discipline','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Balance','Warlock-Affliction','Druid-Feral','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','Druid-Guardian','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Mage-Fire','Warrior-Arms','Rogue-Outlaw','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aalduin:BAAALgAECgMJBAABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCQAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgADCgkJIwAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAUJEQACACYcAQ==.',
Af='Affli:BAACLgAFFH8UAAIDAAUJlBlEMgBVAQADAAUJlBlEMgBVAQAuAAQKfysAAgMACQkUIEIbALECAAMACQkUIEIbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8nAAIFAAgJwRXDEwCaAQAFAAgJwRXDEwCaAQAAAA==.Aiupriesty:BAABLgAECn8mAAMGAAgJ8gpXLQBMAQAGAAgJ8gpXLQBMAQAHAAYJcBM2RQC8AAABLgAECggJJwAFAMEVAA==.',
Ak='Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAAALgAECgQJBQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAAALgAECgYJEwAAAA==.Aleinara:BAABLgAECn8aAAIIAAgJmA1wfgBXAQAIAAgJmA1wfgBXAQAAAA==.Aleridin:BAABLgAECn8rAAIJAAkJHiWfAQBHAwAJAAkJHiWfAQBHAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAACLgAFFH8JAAIKAAUJZBjZFACGAQAKAAUJZBjZFACGAQAuAAQKfxsAAwoACQlwG/sLALoCAAoACQlwG/sLALoCAAsABwkoGCIcALUBAAAA.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Andsey:BAAALgAECgQJCAAAAA==.Annore:BAABLgAECn8cAAIMAAkJdxIFTwDDAQAMAAkJdxIFTwDDAQAAAA==.Antihero:BAABLgAECn8hAAIMAAkJeiN5DgAnAwAMAAkJeiN5DgAnAwAAAA==.',
Ap='Aphelse:BAAALgADCgMJAwABLgAFFAUJCQAKAGQYAA==.',
Aq='Aquiell:BAABLgAECn8eAAINAAYJKhPDoQAdAQANAAYJKhPDoQAdAQAAAA==.Aqular:BAAALgAECgYJCQAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8cAAIFAAUJbyQUBwCcAQAFAAUJbyQUBwCcAQAuAAQKf0MAAwUACQnpJH8BADsDAAUACQnpJH8BADsDAAQABQnNEFFYANQAAAAA.Arkenomu:BAABLgAECn8iAAMOAAgJNRHzLgBfAQAOAAgJNRHzLgBfAQAPAAcJagwMGAA9AQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8tAAMQAAgJIwo1EwAZAQAQAAgJIwo1EwAZAQAMAAYJsAHP7AClAAAAAA==.Asclepius:BAABLgAECn8jAAIPAAkJnQ9iDgDVAQAPAAkJnQ9iDgDVAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Aslo:BAAALgADCgEJAQAAAA==.Asmira:BAAALgADCgYJCQAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn8vAAMRAAcJBiHpEAAZAgARAAcJBiHpEAAZAgASAAQJwRrsagAnAQAAAA==.',
At='Atsunvhi:BAAALgAECgUJDgAAAA==.',
Av='Avadakedevra:BAABLgAECn8jAAMRAAcJKBPuIgB2AQARAAcJKBPuIgB2AQASAAEJKwpFzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azareth:BAAALgADCgkJCQAAAA==.Azreal:BAAALgAECgcJDQAAAA==.Azumok:BAAALgAECgQJBAAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bairn:BAAALgADCggJCAAAAA==.Bakedbean:BAAALgAECgYJCQABLgAFFAEJBQATABQkAA==.Barackobooma:BAAALgAECgIJAgAAAA==.Bazerker:BAAALgAECgIJAgAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8lAAINAAgJnA8QcgB7AQANAAgJnA8QcgB7AQAAAA==.',
Be='Beastcode:BAAALgAECggJCAAAAA==.Belgaria:BAABLgAECn8oAAMUAAcJ9hS9FQBdAQAUAAcJ9hS9FQBdAQAIAAcJgg1ilQBSAQAAAA==.Berryknight:BAABLgAECn8uAAMMAAkJcRtjKwA+AgAMAAkJcRtjKwA+AgAQAAIJ2Q8MKABZAAAAAA==.Berryqt:BAAALgAECgQJCQAAAA==.Bewlzeye:BAAALgAECgUJBwAAAA==.',
Bi='Bigjonmachne:BAACLgAFFH8KAAIMAAQJthrjOwBaAQAMAAQJthrjOwBaAQAuAAQKfxgAAgwACAlAGzYpAEkCAAwACAlAGzYpAEkCAAAA.Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8dAAIHAAUJKSYjAwAZAgAHAAUJKSYjAwAZAgAuAAQKfx8AAgcACQnOJIkDACIDAAcACQnOJIkDACIDAAAA.Blessmoo:BAAALgAFFAEJAQAAAA==.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodsail:BAAALgAECgUJBQAAAA==.Bloodydk:BAAALgADCgMJAwAAAA==.Bluestripee:BAAALgAECgEJAQAAAA==.Bluezugzug:BAAALgAECgMJBQAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8qAAIVAAkJnhUpCwDmAQAVAAkJnhUpCwDmAQAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn8zAAMGAAkJ9yBSBwDCAgAGAAkJ9yBSBwDCAgAWAAEJaBblVgA0AAAAAA==.Bonnieanne:BAAALgADCgEJAQAAAA==.Bonsaichi:BAAALgAECgkJEQAAAA==.Bownyxia:BAACLgAFFH8JAAIOAAMJQBaVEQD1AAAOAAMJQBaVEQD1AAAuAAQKfzYAAw4ACQnIItQEAAADAA4ACQnIItQEAAADABcABAlHDvspAM4AAAEuAAUUCAkkAAwAkBoA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAgJJAAMAJAaAA==.Bowties:BAACLgAFFH8kAAMMAAgJkBpaBgB3AgAMAAcJkBpaBgB3AgAYAAEJAADMSgAAAAAuAAQKf0MAAwwACQmUJl4BAIMDAAwACQmUJl4BAIMDABgACQk3GHkKAHECAAAA.',
Br='Braxchud:BAABLgAECn84AAIZAAkJJhxRDQB+AgAZAAkJJhxRDQB+AgAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAINAAkJixvuKgBYAgANAAkJixvuKgBYAgAAAA==.Brewnwings:BAAALgAECgUJCgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8RAAITAAQJGROQFAAuAQATAAQJGROQFAAuAQAuAAQKfx0AAhMACQm9HcIVAIICABMACQm9HcIVAIICAAEuAAUUCAkkAAwAkBoA.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgADCgkJDwABLgAECggJKgAEAPkhAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burial:BAAALgADCgcJCAAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgQJDgAAAA==.',
Ca='Caarrl:BAAALgAECgQJCAAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBQAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgAECgYJBgAAAA==.Calistra:BAAALgADCgYJBgAAAA==.Caplock:BAAALgAECgQJBQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAAALgAECgUJBwAAAA==.Cartime:BAAALgAECgMJBAAAAA==.Cayllia:BAABLgAECn8jAAMaAAkJDCSOBABFAwAaAAkJDCSOBABFAwAbAAgJDCJOEwAkAgAAAA==.',
Ce='Celaris:BAAALgAECgUJDQAAAA==.',
Ch='Chaolang:BAAALgAFFAEJAQAAAA==.Chataykay:BAAALgAECgcJDgAAAA==.Cherrypepsï:BAABLgAECn8cAAMHAAkJOQ/aKwCYAQAHAAkJOQ/aKwCYAQAWAAUJdgbwOADgAAAAAA==.Chinlen:BAAALgAECgEJAQAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chivies:BAAALgAECggJDQABLgAECgkJMgAIADMhAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAABLgAECn8kAAIcAAkJKxj6AwBGAgAcAAkJKxj6AwBGAgAAAA==.Citrus:BAABLgAECn85AAIRAAkJtBXvEQAOAgARAAkJtBXvEQAOAgAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBwAAAA==.Cliqmonk:BAAALgAECgcJCAAAAA==.',
Cn='Cn:BAABLgAECn8yAAIIAAkJMyHXEADLAgAIAAkJMyHXEADLAgAAAA==.',
Co='Cocoabutter:BAABLgAECn8bAAINAAYJmBFkqwANAQANAAYJmBFkqwANAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAANAIsbAA==.Codeman:BAABLgAECn88AAMYAAkJ7CItAwADAwAYAAkJ7CItAwADAwAMAAEJEwsGSwE1AAAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJPAAYAOwiAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8XAAMKAAYJUhrCFgByAQAKAAUJixjCFgByAQALAAUJsBUgEQAgAQAuAAQKf18AAwoACQl2I+8CAH0DAAoACQl2I+8CAH0DAAsABgmNILoZAMwBAAAA.Contemplate:BAAALgAECgMJCAABLgAFFAIJBAABAAAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECgkJGwABLgAFFAEJAQABAAAAAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.',
Ct='Ctk:BAAALgAECgEJAQAAAA==.',
Cu='Culluh:BAAALgADCgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAABLgAECn8cAAIdAAYJFhzSFABPAQAdAAYJFhzSFABPAQAAAA==.',
Cz='Czin:BAABLgAECn8qAAMEAAgJ+SG+CADCAgAEAAgJ+SG+CADCAgAFAAEJkQnBSwAlAAAAAA==.',
['Cï']='Cïel:BAAALgAECgUJBQAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgYJEgAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJCQAAAA==.Deathverses:BAACLgAFFH82AAIeAAcJtybMAACiAgAeAAcJtybMAACiAgAuAAQKfy4AAh4ACQnjJikCAJYDAB4ACQnjJikCAJYDAAAA.Deerslayer:BAAALgAECgcJDwAAAA==.Deezknights:BAAALgAECgUJCAABLgAECgYJDgABAAAAAA==.Delter:BAABLgAECn8UAAIeAAgJuxyFHwAqAgAeAAgJuxyFHwAqAgABLgAECggJFAAeALscAA==.Deltritus:BAACLgAFFH8YAAINAAYJJBriJQCiAQANAAYJJBriJQCiAQAuAAQKfzQAAg0ACQnnIzMHADMDAA0ACQnnIzMHADMDAAEuAAQKCAkUAB4AuxwA.Demaedra:BAAALgAECgMJAwAAAA==.Demoan:BAABLgAECn86AAIfAAkJKSM2AQAXAwAfAAkJKSM2AQAXAwAAAA==.Demonbiscuit:BAACLgAFFH8GAAIgAAQJ6x3wBACOAQAgAAQJ6x3wBACOAQAuAAQKfxkAAiAACAmlJoUDAAQDACAACAmlJoUDAAQDAAAA.Derpydawg:BAAALgAECgEJAQABLgAFFAQJDQAMAKIbAA==.Dethh:BAAALgADCgMJAwAAAA==.Deviancy:BAABLgAECn8XAAMCAAkJdxkyEACDAgACAAkJdxkyEACDAgAIAAEJpAXhlQEjAAAAAA==.',
Dh='Dhruven:BAAALgADCggJCAAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAABLgAECn8UAAIOAAYJ0A8cTwDLAAAOAAYJ0A8cTwDLAAAAAA==.Diese:BAAALgAECgYJCAAAAA==.Dikslapp:BAABLgAECn83AAIgAAkJRiJAAwAMAwAgAAkJRiJAAwAMAwAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Dipperton:BAAALgAECgEJAQABLgAECgcJFAAXAOkaAA==.Discrespect:BAACLgAFFH8LAAMWAAUJ4xGLHwAcAQAWAAQJYBSLHwAcAQAHAAEJ8QcOLQBDAAAuAAQKfx8ABBYACAlYGnERAC0CABYACAlYGnERAC0CAAcABAkiCMhcAMAAAAYAAQkfAy+FACIAAAAA.Distinct:BAAALgAECgkJCQABLgAECgkJOgAfACkjAA==.Distress:BAAALgAFFAIJBAAAAA==.Ditto:BAACLgAFFH8IAAIYAAMJ/xCOIgCtAAAYAAMJ/xCOIgCtAAAuAAQKfzsABBgACAmpHOsMAEECABgACAmpHOsMAEECAAwABwkpCxeYACMBABAAAwlBDt4PAJ4AAAAA.',
Dl='Dlitinaro:BAABLgAECn80AAMMAAkJIyHpHQCBAgAYAAkJcx4qCACCAgAMAAkJBx/pHQCBAgAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMPAAMJoxd9DQAHAQAPAAMJoxd9DQAHAQAOAAEJHAlmWQA8AAAuAAQKfxkAAw8ACAlwJLYDACADAA8ACAlwJLYDACADAA4AAwlpGjBOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Dollette:BAAALgAECggJBQAAAA==.Donoph:BAABLgAECn88AAMCAAkJ/yMaAgCBAwACAAkJ/yMaAgCBAwAIAAEJQwy7dAEwAAAAAA==.Doomar:BAABLgAECn80AAMDAAkJjSFPFQCZAgADAAkJNCFPFQCZAgAhAAYJfR/9BgDMAQAAAA==.Doomsamdi:BAAALgAECgcJCAABLgAECgkJNAADAI0hAA==.Doomseph:BAAALgAECgEJAQABLgAECgkJNAADAI0hAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8fAAMDAAkJ6AmNaQBeAQADAAkJMAmNaQBeAQAhAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgAECgMJAwAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8hAAMXAAgJSQu+HwAwAQAXAAcJZwq+HwAwAQAOAAYJ9AqTSgDdAAAAAA==.Dreav:BAAALgAECgIJAgAAAA==.Drugar:BAABLgAECn8iAAINAAgJzg4GcwB5AQANAAgJzg4GcwB5AQAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEx8IFQDCAAAEAAIJEx8IFQDCAAAuAAQKfxYAAgQACAneHbASALkCAAQACAneHbASALkCAAEuAAUUCQk4ABUAySUA.',
Du='Duloc:BAAALgAECgUJCAAAAA==.Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgUJDgAAAA==.',
Dy='Dynabol:BAACLgAFFH8FAAITAAEJFCTveQBrAAATAAEJFCTveQBrAAAuAAQKfzUAAxMACQkOJvUBAGEDABMACQl8JfUBAGEDAB8ACAkhJQgCAN0CAAAA.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAQJDQAMAKIbAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgAECgQJBQAAAA==.',
Em='Eminnazen:BAAALgADCgkJCQAAAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Ev='Eveleigh:BAAALgAECgEJAQAAAA==.Everfale:BAAALgAECgIJAwABLgAFFAEJAQABAAAAAQ==.Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn8yAAIEAAkJIhvXFgAjAgAEAAkJIhvXFgAjAgAAAA==.Faolsabre:BAABLgAECn8nAAIMAAgJpQx6dQBkAQAMAAgJpQx6dQBkAQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgARAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn89AAMdAAkJNxSeCQAKAgAdAAkJJxSeCQAKAgAiAAYJVxF3JQAAAQAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8vAAIaAAkJdBlgFgCBAgAaAAkJdBlgFgCBAgAAAA==.',
Fo='Folid:BAAALgAECgEJAgAAAA==.Forne:BAAALgAFFAEJAQAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB51CgDOAgACAAkJbB51CgDOAgAAAA==.Frostedphyre:BAAALgAECgkJDQAAAA==.',
Fu='Furrywhaco:BAABLgAECn8UAAIiAAkJ+RoiBwBpAgAiAAkJ+RoiBwBpAgAAAA==.Fuzzyspells:BAAALgAECgUJCAAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMIAAgJLxv2SwD/AQAIAAYJsB72SwD/AQAUAAYJ7xLyHQALAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.',
Ge='Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn86AAMjAAgJMgl4JQBOAQAjAAgJAQh4JQBOAQAkAAYJuwWQEQDuAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBgAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQNAAgJsyQ4HwD4AgANAAgJniQ4HwD4AgAlAAEJnCZFFQBzAAAmAAEJiSQ/DABrAAABLgAFFAEJBQATABQkAA==.',
Gr='Gravez:BAAALgAECgYJBwABLgAFFAEJAQABAAAAAA==.Grawler:BAAALgAECgYJBgAAAA==.Greeny:BAAALgAECgQJDAAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgQJCgABLgAECgcJCQABAAAAAA==.Grumpyhunter:BAAALgAECgcJEAABLgAECgkJNQANAOsfAA==.',
Gu='Gumgumfury:BAAALgAECgQJCwAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haidies:BAAALgAECgUJDgABLgAFFAQJDQAaALkPAA==.Halzlok:BAABLgAECn8cAAIZAAcJ6Q9NPQAjAQAZAAcJ6Q9NPQAjAQAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Harandy:BAAALgAECgEJAQAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAUJHAAFAG8kAA==.Herøn:BAAALgAECgUJAQAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJKAAaAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAFFAQJBgAgAOsdAA==.Hondacivic:BAAALgAECgEJAQABLgAECgkJJAAjAH0kAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ia='Iandis:BAAALgADCgUJBQABLgAECgcJHAAFAHwSAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgIJAgAAAA==.',
Ik='Ikayhaimahn:BAAALgAECgMJAwABLgAFFAMJBgAOAPQLAA==.',
Im='Imysteriöus:BAABLgAECn8oAAMaAAgJBiXoBQBNAwAaAAgJBiXoBQBNAwAdAAYJHhSJEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAACLgAFFH8SAAICAAUJQx1aDwCkAQACAAUJQx1aDwCkAQAuAAQKfxcAAgIACAlAHJ0bADcCAAIACAlAHJ0bADcCAAAA.Indishaman:BAAALgAECgYJCQAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJMgAIADMhAA==.',
Is='Ishamael:BAABLgAECn80AAIGAAkJUxJKHQC9AQAGAAkJUxJKHQC9AQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8LAAIXAAQJBhisAgBTAQAXAAQJBhisAgBTAQAuAAQKfywAAhcACQkHIjYBAOcCABcACQkHIjYBAOcCAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jarnroz:BAAALgAECgQJBAABLgAECgUJCgABAAAAAA==.Jaythirian:BAABLgAECn8YAAMnAAcJrQ6JEACUAQAnAAcJrQ6JEACUAQAEAAQJ1gQVgQC5AAAAAA==.',
Je='Jerg:BAACLgAFFH8NAAIaAAQJuQ/bKQAAAQAaAAQJuQ/bKQAAAQAuAAQKfzkAAxoACQlUHtgWAH8CABoACAmfHdgWAH8CABsABwk3FtUoAHABAAAA.Jessup:BAACLgAFFH8NAAMoAAQJkiGhBgD8AAAoAAQJHh+hBgD8AAAjAAIJuxuJKgCbAAAuAAQKfyoAAyMACQmKIn8EAFADACMACQn8IX8EAFADACgABQl9ITkJAIMBAAAA.',
Jh='Jhara:BAABLgAECn8dAAINAAcJeBDYiABKAQANAAcJeBDYiABKAQAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAABLgAECn8sAAQWAAkJECSeBgDeAgAWAAkJTSOeBgDeAgAHAAUJtyH0GgDZAQAGAAUJ0BxkNQBAAQABLgAFFAUJCQAKAGQYAA==.Junnai:BAAALgADCgcJBwAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECgcJDQAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgUJBgAAAA==.Kamekazi:BAAALgAECgMJAwAAAA==.Kariva:BAABLgAECn85AAIHAAkJ6xgaDQB8AgAHAAkJ6xgaDQB8AgAAAA==.Katacemic:BAABLgAECn8eAAIYAAcJ8hAzIgAmAQAYAAcJ8hAzIgAmAQABLgAECgkJIgAhAF8KAA==.Katastrophic:BAAALgADCggJEAABLgAECgkJIgAhAF8KAA==.Katazul:BAABLgAECn8iAAMhAAkJXwqrJgArAQADAAkJewfUZQBnAQAhAAYJzgqrJgArAQAAAA==.Kaulike:BAAALgADCgIJAgAAAA==.',
Ke='Keelanllan:BAABLgAECn8bAAIgAAgJcgjhKQAJAQAgAAgJcgjhKQAJAQAAAA==.Keilun:BAEALgAECgcJCwAAAA==.Kertzz:BAAALgADCgQJBAABLgAECgMJAwABAAAAAA==.Kew:BAABLgAECn8UAAINAAcJzBYPXgCsAQANAAcJzBYPXgCsAQAAAA==.Kewkew:BAAALgADCgcJDAAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECgkJIwAPAJ0PAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJIgAOADURAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Ko='Koggmaw:BAAALgAECgcJEAABLgAFFAQJDQAaALkPAA==.Kokuten:BAAALgAECgEJAQABLgAECggJHwApAL0dAA==.Koral:BAAALgAECgYJBgAAAA==.',
Kr='Kralj:BAAALgAECgUJCAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJPAAYAOwiAA==.Kungfuhealya:BAABLgAECn8hAAMKAAgJcgifSwAIAQAKAAgJcgifSwAIAQALAAEJwQGRqQAZAAAAAA==.Kuraj:BAAALgAECgEJAQAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAAIAPkbAA==.Larrydale:BAABLgAECn8fAAMSAAgJTxwTGQByAgASAAgJTxwTGQByAgARAAEJqQMDMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAAIAPkbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn8nAAMYAAgJtQ6iIAA0AQAYAAgJPA2iIAA0AQAMAAQJ7Q0jyADbAAAAAA==.',
Le='Lea:BAAALgAECgIJAgABLgAECgkJKQANAFwaAA==.Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgMJBQAAAA==.Leondis:BAACLgAFFH8GAAISAAIJsxQObwCQAAASAAIJsxQObwCQAAAuAAQKfzMAAhIACQl0IggKAPMCABIACQl0IggKAPMCAAAA.Leviosa:BAAALgAECgMJAgAAAA==.Lexipriest:BAACLgAFFH8cAAMHAAYJ3hvsAwACAgAHAAYJ3hvsAwACAgAWAAMJiQtgEADHAAAuAAQKf1EAAwcACQlrIX4DAEkDAAcACQlrIX4DAEkDABYACAkzHYcIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.Lilpp:BAAALgAECgIJAgABLgAECgYJDgABAAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Lloydak:BAAALgAECgkJCgAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgcJHAAFAHwSAA==.Lockmonster:BAAALgAECgIJAwAAAA==.Locksteady:BAAALgAECgcJCAAAAA==.Lokii:BAAALgAECgEJAQAAAA==.Lookalock:BAAALgAECgQJBQAAAA==.Lorp:BAAALgAECgYJBwAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAITAAgJeB2EKQBcAgATAAgJeB2EKQBcAgAAAA==.Lumosmaxiima:BAAALgAECgcJCgAAAA==.Lunadesangre:BAAALgAECgEJAwAAAA==.Lunarette:BAAALgAECgMJBQAAAA==.',
Ly='Lydax:BAABLgAECn8UAAIIAAcJ+RtqVwDcAQAIAAcJ+RtqVwDcAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAABLgAECn8XAAIpAAYJ9xiNOQCtAQApAAYJ9xiNOQCtAQAAAA==.Madkingzack:BAABLgAECn8fAAMEAAkJQSRpAgBAAwAEAAkJQSRpAgBAAwAnAAEJywYncQApAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAABLgAECn8aAAMhAAgJnxGlDwAsAQADAAgJXgwPZQBpAQAhAAYJHxWlDwAsAQAAAA==.Mallikii:BAABLgAECn8dAAMaAAkJ0hu9MADoAQAaAAkJ0hu9MADoAQAbAAQJrSMBOABZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8gAAINAAkJ9w0JawCMAQANAAkJ9w0JawCMAQAAAA==.Marigosa:BAAALgAECgcJDwAAAA==.Marnolkas:BAAALgADCggJCAABLgAECgUJDAABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAABLgAECn8oAAMIAAkJCx6AFQCsAgAIAAkJCx6AFQCsAgACAAcJ1h5qEwBgAgAAAA==.Mattdemon:BAAALgAECgcJCQAAAA==.Maudib:BAABLgAECn8VAAIiAAgJSRVJIQAeAQAiAAgJSRVJIQAeAQAAAA==.Mawile:BAAALgAECgQJCAAAAA==.',
Me='Meautiful:BAAALgADCgQJBAAAAA==.Medusa:BAAALgAECgUJDgAAAA==.Meesha:BAAALgAECgIJAgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAAALgAECgYJEwAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQhAAgJBA97HABqAQAhAAcJYw57HABqAQADAAUJ/wrlxQDNAAAcAAEJ2hVmLgBBAAAAAA==.Merkxi:BAABLgAECn8tAAIRAAkJBiKhAQA1AwARAAkJBiKhAQA1AwAAAA==.Messe:BAABLgAECn9AAAIoAAkJAR7fAQCpAgAoAAkJAR7fAQCpAgAAAA==.Mestre:BAAALgAECgYJCgAAAA==.Methious:BAABLgAECn8WAAIIAAkJnRg3agCqAQAIAAkJnRg3agCqAQAAAA==.',
Mi='Mikethepally:BAAALgAECgMJAwAAAA==.Minigoober:BAAALgAECgQJBAAAAA==.',
Mo='Mogli:BAAALgAECgQJAgABLgAECggJLwATAPUfAA==.Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8XAAIJAAYJqgiDGwAuAQAJAAYJqgiDGwAuAQAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECgUJCQAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonrivr:BAAALgAECgUJCAABLgAECggJJwAYALUOAA==.Moonsguard:BAAALgADCgcJCgABLgAECgUJDQABAAAAAA==.Moosewillis:BAAALgAECgcJBwAAAA==.Moovit:BAABLgAECn8XAAMYAAYJHwe+NgCiAAAYAAYJHwe+NgCiAAAMAAEJugHvdwEZAAAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgIJAQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.Musui:BAAALgADCgIJAgAAAA==.',
My='Myströnghand:BAAALgAECgcJBwAAAA==.',
Na='Nagumo:BAABLgAECn8mAAMhAAgJFQTyOQDMAAADAAgJ4wNDnwD2AAAhAAYJYAPyOQDMAAAAAA==.Nahual:BAAALgADCgQJBQAAAA==.Nala:BAABLgAECn8WAAMbAAgJqhGmMQA6AQAbAAcJvw6mMQA6AQAaAAQJWBdtbgAJAQABLgAFFAQJDQAaALkPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAACLgAFFH8GAAIOAAMJ9AtNOwC4AAAOAAMJ9AtNOwC4AAAuAAQKfy4AAw8ACAkaFBAYAD0BAA8ABwllEhAYAD0BAA4ABwkgF8E2ADMBAAAA.',
Ne='Nekoya:BAAALgADCgMJAwABLgAECgMJAwABAAAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwABLgABCgMJAwABAAAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8MAAITAAUJZR3kJwBbAQATAAUJZR3kJwBbAQAuAAQKfy8AAxMACQnAJfMAANgDABMACQnAJfMAANgDAB8AAQk3FKYtADYAAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgAECgcJBwAAAA==.Nivan:BAAALgAECgQJBQAAAA==.Niço:BAACLgAFFH8HAAISAAMJTxoAQgAGAQASAAMJTxoAQgAGAQAuAAQKfxUAAhIACQnPHKkfAEcCABIACQnPHKkfAEcCAAAA.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIaAAkJJhs5HgBNAgAaAAkJJhs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAAALgAFFAEJAQAAAQ==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
Nu='Nutz:BAAALgAECgkJAgAAAA==.',
['Nï']='Nï:BAAALgAECgEJAQAAAA==.',
Of='Offlyne:BAAALgAECgEJAQAAAA==.',
Oh='Ohntakae:BAAALgAECgUJAgAAAA==.',
Ok='Oksana:BAAALgAECggJEAAAAA==.',
Ol='Ollamh:BAAALgAECgEJAwAAAA==.',
Om='Ombravuota:BAAALgAECgcJEQAAAA==.',
Oo='Oom:BAAALgAECgIJAgAAAA==.',
Or='Oralian:BAABLgAECn8hAAMhAAkJwSMrCwANAgAhAAUJrCMrCwANAgADAAUJhCMLRQD8AQAAAA==.Orcleave:BAABLgAECn8UAAMEAAcJIxuIQwCXAQAEAAYJ3xSIQwCXAQAFAAUJsR6YHgBQAQAAAA==.Orflap:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.',
Ov='Ovee:BAAALgADCgcJBgAAAA==.',
Pa='Paboo:BAAALgAECgcJDAAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8pAAMNAAkJXBoLMABBAgANAAkJXBoLMABBAgAmAAEJZQkcEgApAAAAAA==.Perturabo:BAAALgAECgEJAgAAAA==.',
Ph='Phoenyx:BAABLgAECn8VAAMhAAYJpAkcGwC4AAAhAAYJpAkcGwC4AAADAAUJjQHR+wBbAAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMSAAcJDx2zJAAqAgASAAcJDx2zJAAqAgAeAAMJdQuDawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJIAANAPcNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgAECgIJAgAAAA==.',
['Põ']='Põ:BAAALgAECgMJAwABLgAECgkJKAAIAAseAA==.',
Qu='Quorra:BAAALgAECgEJAQAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8rAAIEAAkJcB58EQBWAgAEAAkJcB58EQBWAgAAAA==.Rakagar:BAABLgAECn8yAAIIAAkJOh6zHACBAgAIAAkJOh6zHACBAgAAAA==.Raktot:BAAALgAECgEJAQAAAA==.Ranko:BAAALgAECgkJBAAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reia:BAAALgAECgMJBAAAAA==.Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8ZAAIKAAYJSRw0DADyAQAKAAYJSRw0DADyAQAuAAQKfy8AAgoACQkQIGwOAJcCAAoACQkQIGwOAJcCAAAA.Reyz:BAABLgAECn8ZAAIKAAgJHBWGIQCnAQAKAAgJHBWGIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQABLgAECgMJAwABAAAAAA==.',
Rh='Rhaegos:BAAALgAECgUJDAAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8hAAIEAAYJTCESKACmAQAEAAYJTCESKACmAQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
Ry='Rythmias:BAAALgAECgUJBQAAAA==.Ryvive:BAAALgADCgkJEQAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAFFAQJDAASAE0eAA==.',
['Rë']='Rëz:BAAALgAECgMJAwAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAECgcJFAAEACMbAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8xAAMgAAkJ1yLRBADfAgAgAAkJ1yLRBADfAgATAAYJUhn6XwBRAQABLgAECgkJNAAMACMhAA==.Scripts:BAAALgAECgYJEQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJIAANAPcNAA==.',
Sh='Shale:BAABLgAECn9IAAMPAAkJjhlJBwByAgAPAAkJjhlJBwByAgAOAAgJqgjtWACpAAAAAA==.Shamboo:BAAALgADCggJCQAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAACLgAFFH8FAAIZAAMJ3Ra1JwDaAAAZAAMJ3Ra1JwDaAAAuAAQKfxkAAxkABwkKHH8nAJcBABkABwkKHH8nAJcBACkABAnmDFF0AL8AAAAA.Sharaiya:BAABLgAECn8sAAIaAAkJvgUfZAD3AAAaAAkJvgUfZAD3AAAAAA==.Sharkmanfive:BAAALgAECgUJBQAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Sherp:BAAALgAECgUJBQAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAABLgAECn8hAAMSAAYJciCAQADJAQASAAYJciCAQADJAQAeAAEJJRGYhgA2AAAAAA==.Sioux:BAAALgAECgUJCwAAAA==.',
Sk='Skippybmm:BAAALgAECgQJDAABLgAECgcJHAAFAHwSAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgEJAQABLgAECgkJQAAoAAEeAA==.',
Sm='Smexyshâmmy:BAAALgAECggJDQAAAA==.',
So='Soferus:BAAALgADCggJCAABLgAECgUJDAABAAAAAA==.Solaire:BAACLgAFFH8NAAIUAAUJSRrbBAAoAQAUAAUJSRrbBAAoAQAuAAQKfywAAhQACQn+ILkBADMDABQACQn+ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJuR5OEgCuAgADAAkJuR5OEgCuAgABLgAFFAcJGwATAEobAA==.Soulful:BAAALgAECgYJBgAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAaALkPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAABLgAECn8cAAIFAAcJfBKpGwBBAQAFAAcJfBKpGwBBAQAAAA==.Spot:BAAALgAECgYJBwABLgAECgkJIAANAPcNAA==.Spyy:BAAALgAECgYJCwAAAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgQJCAAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn85AAMRAAkJgR1SBgCxAgARAAkJgR1SBgCxAgAeAAcJKBUDFAAJAQAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECgkJOQAfAD0QAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8gAAMhAAgJmBfWBgDRAQAhAAgJmBfWBgDRAQADAAEJlQHJSQEaAAAAAA==.Tankinit:BAAALgAECgQJDgAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgAECgEJAQABLgAECgUJCgABAAAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIUAAMJswgGBACcAAAUAAMJswgGBACcAAAuAAQKfyUAAhQACAkJHX0GAIACABQACAkJHX0GAIACAAAA.Tenzink:BAABLgAECn8mAAIKAAkJGRyNDQCkAgAKAAkJGRyNDQCkAgAAAA==.',
Th='Thalon:BAAALgAECgMJAwABLgAFFAMJCQAMAJoYAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgAECgEJAgAAAA==.Thedru:BAABLgAECn8xAAIaAAgJiw3zSgBQAQAaAAgJiw3zSgBQAQAAAA==.Thrastus:BAAALgAECgEJAQAAAA==.Thrus:BAABLgAECn8UAAMLAAcJSxAMLQA/AQALAAcJSxAMLQA/AQAKAAYJqQ5hSwAJAQABLgAECgkJQAAoAAEeAA==.Théworld:BAAALgAECgUJDQAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgYJBwABLgAECgkJKQANAFwaAA==.',
Tl='Tlnks:BAAALgADCgQJBwAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Tokeon:BAAALgAECgEJAQAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAABLgAECn8iAAIRAAkJRh9VBADeAgARAAkJRh9VBADeAgAAAA==.',
Tr='Traler:BAAALgAECgEJAQABLgAECgkJPQAdADcUAA==.Tralzitashan:BAABLgAECn88AAMlAAkJMhOGAgAUAgAlAAkJMhOGAgAUAgANAAQJzAMXIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAINAAcJWhq0ZQAMAgANAAcJWhq0ZQAMAgAAAA==.Tren:BAAALgADCgMJAwAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgAECgYJBgAAAA==.',
Ty='Tyrdonut:BAAALgAECgEJAQABLgAECggJIQAXAEkLAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Ub='Ubie:BAAALgADCgQJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAAALgAECgUJDwAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAACLgAFFH8JAAIIAAMJpR0YQQASAQAIAAMJpR0YQQASAQAuAAQKfxkAAggACQnlJG0GACoDAAgACQnlJG0GACoDAAAA.Unglausp:BAACLgAFFH8IAAIGAAMJMxdTHQDjAAAGAAMJMxdTHQDjAAAuAAQKfyIAAgYACAn9HtINAKYCAAYACAn9HtINAKYCAAEuAAUUAwkJAAgApR0A.',
Uz='Uzington:BAACLgAFFH8aAAIFAAUJ3RLHEgD0AAAFAAUJ3RLHEgD0AAAuAAQKfyYAAgUACQmyHPQIAI8CAAUACQmyHPQIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgIJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAABLgAECn8UAAIDAAYJ6AjXrQDdAAADAAYJ6AjXrQDdAAAAAA==.Valorien:BAACLgAFFH8KAAIIAAQJ8xwJIABjAQAIAAQJ8xwJIABjAQAuAAQKfyEAAggACAkgG/E3AAkCAAgACAkgG/E3AAkCAAAA.Valzlok:BAAALgAECgMJAwAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgARAC0jAA==.Velinieron:BAABLgAECn8eAAIRAAkJLSNPBQC8AgARAAkJLSNPBQC8AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgARAC0jAA==.Vellash:BAABLgAECn8cAAIgAAYJxQp3MQDZAAAgAAYJxQp3MQDZAAAAAA==.Vendétta:BAABLgAECn8jAAISAAkJSQ+9VQCJAQASAAkJSQ+9VQCJAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8eAAINAAgJIQo1igBIAQANAAgJIQo1igBIAQAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgADCggJCQAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8rAAISAAgJORU4PgDQAQASAAgJORU4PgDQAQAAAA==.',
Vy='Vynlandis:BAABLgAECn85AAMMAAkJ5xhXLAA6AgAMAAkJ5xhXLAA6AgAQAAMJgQS2KABVAAAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAaALkPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Wargg:BAAALgAECgYJBQABLgAECgkJHQAgAFsbAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAAALgAECgYJEQAAAA==.Weenbean:BAAALgAFFAMJAwAAAA==.Werebray:BAAALgAECgcJEQABLgAFFAMJBgARAMETAA==.',
Wh='Whaco:BAABLgAECn8fAAIUAAgJmBt9CwD2AQAUAAgJmBt9CwD2AQAAAA==.Whatisaggro:BAABLgAECn8ZAAIEAAcJ4BuNLACNAQAEAAcJ4BuNLACNAQAAAA==.Whispertree:BAABLgAECn8vAAIbAAkJ0CHkBgDWAgAbAAkJ0CHkBgDWAgAAAA==.White:BAAALgAECgUJBQABLgAFFAMJBgARACMRAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECggJIQAXAEkLAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8NAAMMAAQJohvMQABPAQAMAAQJohvMQABPAQAQAAEJiQXyHwA/AAAuAAQKfysAAwwACQkrIWINAC8DAAwACQkrIWINAC8DABAAAQl9HeEoAFQAAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8uAAQYAAcJNxnqFADDAQAYAAYJmx3qFADDAQAMAAcJoxLjgABMAQAQAAIJcxhNEgBsAAAAAA==.Wixypoo:BAACLgAFFH8IAAIJAAMJOBTJLgDXAAAJAAMJOBTJLgDXAAAuAAQKfzQAAwkACQnoHUcKAH0CAAkACQnoHUcKAH0CAAoAAQnpAWGxABsAAAAA.',
Wo='Wockyslush:BAABLgAECn8kAAIjAAkJfSTpCAADAwAjAAkJfSTpCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.Woodnzhood:BAAALgADCgEJAgAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMOAAkJWhgyFgAPAgAOAAkJWhgyFgAPAgAXAAYJwAMuKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8fAAIpAAgJvR3YGwBSAgApAAgJvR3YGwBSAgAAAA==.',
Wy='Wyyn:BAABLgAECn8vAAINAAgJwQojiABMAQANAAgJwQojiABMAQAAAA==.',
Xa='Xanboi:BAABLgAECn9DAAMRAAkJ7yR/AQA8AwARAAkJ7yR/AQA8AwASAAIJ6iK1iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAACLgAFFH8QAAIEAAUJQSCMEABhAQAEAAUJQSCMEABhAQAuAAQKfycAAgQACQndIRINAO0CAAQACQndIRINAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Yo='Yona:BAAALgADCgIJAgABLgAECgkJIAANAPcNAA==.',
Ys='Ysar:BAABLgAECn8dAAIOAAkJag5CJQCZAQAOAAkJag5CJQCZAQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMXAAcJ6RqJDgDyAQAXAAYJkB+JDgDyAQAOAAYJGxdJIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECgcJKAAUAPYUAA==.',
Ze='Zeebu:BAABLgAECn8uAAIRAAgJTQvrHwCPAQARAAgJTQvrHwCPAQAAAA==.Zenboi:BAABLgAECn8cAAITAAgJ1RUcQwDnAQATAAgJ1RUcQwDnAQAAAA==.Zephryyn:BAAALgAECgcJEgAAAA==.',
Zh='Zhilan:BAAALgAECgQJDAAAAA==.',
Zi='Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoda:BAAALgAECgEJAQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAUJDQAoAJIhAA==.Zophos:BAAALgAECggJDwABLgAECggJFgAhAAQPAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgEJAgAAAA==.Zuzuk:BAAALgAECggJEwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAABLgAECn8UAAIMAAcJ8Q4mgwBIAQAMAAcJ8Q4mgwBIAQAAAA==.',
['Zú']='Zúz:BAAALgAECgcJEgAAAA==.',
['Áß']='Áßomination:BAAALgAECgUJCAAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAABLgAECn8rAAIpAAkJogvLUQBNAQApAAkJogvLUQBNAQAAAA==.',
['Ði']='Ðittø:BAAALgAECggJEQABLgAFFAMJCAAYAP8QAA==.',
['Öd']='Ödorodun:BAAALgAECgIJAwAAAA==.',
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
