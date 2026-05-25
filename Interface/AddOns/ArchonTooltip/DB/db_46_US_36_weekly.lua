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
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aalduin:BAAALgAECgMJBAABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCQAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgADCgkJGgAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAUJEAACACYcAQ==.',
Af='Affli:BAACLgAFFH8PAAIDAAQJoBGSOgAvAQADAAQJoBGSOgAvAQAuAAQKfysAAgMACQkUIEIbALECAAMACQkUIEIbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8mAAIFAAgJFRXrEQCiAQAFAAgJFRXrEQCiAQABLgAECggJJgAGAPIKAA==.Aiupriesty:BAABLgAECn8mAAMGAAgJ8gqTKABiAQAGAAgJ8gqTKABiAQAHAAYJcBN+QQDAAAAAAA==.',
Ak='Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAAALgAECgQJBQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAAALgAECgYJEwAAAA==.Aleinara:BAABLgAECn8UAAIIAAYJiQvmsQD6AAAIAAYJiQvmsQD6AAAAAA==.Aleridin:BAABLgAECn8rAAIJAAkJHiVUAQBLAwAJAAkJHiVUAQBLAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAABLgAECn8ZAAMKAAkJ4BrsCwCoAgAKAAkJ4BrsCwCoAgALAAYJ6hboJABhAQAAAA==.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Andsey:BAAALgAECgQJCAAAAA==.Annore:BAABLgAECn8aAAIMAAkJQBCfUwCmAQAMAAkJQBCfUwCmAQAAAA==.Antihero:BAABLgAECn8hAAIMAAkJeiN5DgAnAwAMAAkJeiN5DgAnAwAAAA==.',
Ap='Aphelse:BAAALgADCgMJAwABLgAECgkJGQAKAOAaAA==.',
Aq='Aquiell:BAABLgAECn8eAAINAAYJKhOJnAAmAQANAAYJKhOJnAAmAQAAAA==.Aqular:BAAALgAECgQJBwAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8XAAIFAAUJTCTCBQCgAQAFAAUJTCTCBQCgAQAuAAQKfz4AAwUACAn+I/wEAK8CAAUACAn+I/wEAK8CAAQABQnNECRSANcAAAAA.Arkenomu:BAABLgAECn8iAAMOAAgJNRHIKgBwAQAOAAgJNRHIKgBwAQAPAAcJagzNFgA9AQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8tAAMQAAgJIwo3EAApAQAQAAgJIwo3EAApAQAMAAYJsAHP7AClAAAAAA==.Asclepius:BAABLgAECn8gAAIPAAgJKhGbDwCuAQAPAAgJKhGbDwCuAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Aslo:BAAALgADCgEJAQAAAA==.Asmira:BAAALgADCgYJCQAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn8pAAMRAAcJqCAsEQAJAgARAAcJZCAsEQAJAgASAAQJwRrsagAnAQAAAA==.',
At='Atsunvhi:BAAALgAECgQJCgAAAA==.',
Av='Avadakedevra:BAABLgAECn8hAAMRAAcJKBNRIAB6AQARAAcJKBNRIAB6AQASAAEJKwpFzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azreal:BAAALgAECgYJBgAAAA==.Azumok:BAAALgAECgQJBAAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bakedbean:BAAALgAECgYJCQABLgAECgkJLgATAA4mAA==.Barackobooma:BAAALgAECgIJAgAAAA==.Bazerker:BAAALgADCgMJAwAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8lAAINAAgJnA+CZgCTAQANAAgJnA+CZgCTAQAAAA==.',
Be='Belgaria:BAABLgAECn8mAAMUAAcJ3RTtEwBfAQAUAAcJ3RTtEwBfAQAIAAcJgg1ilQBSAQAAAA==.Berryknight:BAABLgAECn8sAAMMAAkJsRlkLwAeAgAMAAkJsRlkLwAeAgAQAAIJ2Q+UIwBZAAAAAA==.Berryqt:BAAALgAECgQJCQAAAA==.Bewlzeye:BAAALgAECgUJBwAAAA==.',
Bi='Bigjonmachne:BAABLgAFFH8GAAIMAAMJ1hCnawDyAAAMAAMJ1hCnawDyAAABLgAECgcJFAAIAAgeAA==.Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8YAAIHAAUJKSYoAgAmAgAHAAUJKSYoAgAmAgAuAAQKfx8AAgcACQnOJIkDACIDAAcACQnOJIkDACIDAAAA.Blessmoo:BAAALgADCgkJCQAAAA==.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodsail:BAAALgAECgUJBQAAAA==.Bloodydk:BAAALgADCgMJAwAAAA==.Bluestripee:BAAALgAECgEJAQAAAA==.Bluezugzug:BAAALgAECgMJBQAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8qAAIVAAkJnhXXCQDpAQAVAAkJnhXXCQDpAQAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn8zAAMGAAkJ9yBFBgDRAgAGAAkJ9yBFBgDRAgAWAAEJaBblVgA0AAAAAA==.Bonsaichi:BAAALgAECggJCQAAAA==.Bownyxia:BAACLgAFFH8JAAIOAAMJQBaVEQD1AAAOAAMJQBaVEQD1AAAuAAQKfzYAAw4ACQnIIl0EAA0DAA4ACQnIIl0EAA0DABcABAlHDvspAM4AAAEuAAUUCAkkAAwAkBoA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAgJJAAMAJAaAA==.Bowties:BAACLgAFFH8kAAMMAAgJkBrEAwCCAgAMAAcJkBrEAwCCAgAYAAEJAADLQQAAAAAuAAQKf0MAAwwACQmUJu8AAIcDAAwACQmUJu8AAIcDABgACQk3GHkKAHECAAAA.',
Br='Braxchud:BAABLgAECn8uAAIZAAgJLRzfEwAgAgAZAAgJLRzfEwAgAgAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAINAAkJixuTJgBlAgANAAkJixuTJgBlAgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8RAAITAAQJGROQFAAuAQATAAQJGROQFAAuAQAuAAQKfx0AAhMACQm9HV0TAIoCABMACQm9HV0TAIoCAAEuAAUUCAkkAAwAkBoA.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgADCgcJBwABLgAECggJIgAEAAggAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgQJCwAAAA==.',
Ca='Caarrl:BAAALgAECgQJCAAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBQAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgAECgYJBgAAAA==.Caplock:BAAALgAECgEJAQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAAALgADCgUJBQAAAA==.Cartime:BAAALgADCgcJCAAAAA==.Cayllia:BAABLgAECn8jAAMaAAkJDCSOBABFAwAaAAkJDCSOBABFAwAbAAgJDCJnEQAnAgAAAA==.',
Ce='Celaris:BAAALgAECgMJCAAAAA==.',
Ch='Chaolang:BAAALgAECgIJAgAAAA==.Chataykay:BAAALgAECgcJDgAAAA==.Cherrypepsï:BAABLgAECn8cAAMHAAkJOQ/aKwCYAQAHAAkJOQ/aKwCYAQAWAAUJdgbwOADgAAAAAA==.Chinlen:BAAALgAECgEJAQAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chivies:BAAALgAECggJDAABLgAECgkJKwAIADMhAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAABLgAECn8cAAIcAAgJ3xcZBgDrAQAcAAgJ3xcZBgDrAQAAAA==.Citrus:BAABLgAECn84AAIRAAkJtBVoEAASAgARAAkJtBVoEAASAgAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBwAAAA==.Cliqmonk:BAAALgAECgcJCAAAAA==.',
Cn='Cn:BAABLgAECn8rAAIIAAkJMyFbEADKAgAIAAkJMyFbEADKAgAAAA==.',
Co='Cocoabutter:BAABLgAECn8bAAINAAYJmBE2nAAnAQANAAYJmBE2nAAnAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAANAIsbAA==.Codeman:BAABLgAECn88AAMYAAkJ7CKkAgALAwAYAAkJ7CKkAgALAwAMAAEJEwtVMAE3AAAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJPAAYAOwiAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8WAAMKAAYJwhjRFABhAQAKAAUJqxbRFABhAQALAAUJsBXKDQArAQAuAAQKf1wAAwoACQlsI6UCAHoDAAoACQlsI6UCAHoDAAsABgmpH2YaALIBAAAA.Contemplate:BAAALgAECgMJCAABLgAECgYJBgABAAAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECgkJGwABLgAFFAEJAQABAAAAAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.',
Ct='Ctk:BAAALgAECgEJAQAAAA==.',
Cu='Culluh:BAAALgADCgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAABLgAECn8cAAIdAAYJFhz9EgBTAQAdAAYJFhz9EgBTAQAAAA==.',
Cz='Czin:BAABLgAECn8iAAMEAAgJCCCfDQBxAgAEAAgJCCCfDQBxAgAFAAEJkQnBSwAlAAAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgYJCAAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJCQAAAA==.Deathverses:BAACLgAFFH8zAAIeAAYJ4iZdAgA3AgAeAAYJ4iZdAgA3AgAuAAQKfy4AAh4ACQnjJikCAJYDAB4ACQnjJikCAJYDAAAA.Deerslayer:BAAALgAECgcJDwAAAA==.Deezknights:BAAALgAECgUJCAABLgAECgYJDgABAAAAAA==.Delter:BAABLgAECn8UAAIeAAgJuxyFHwAqAgAeAAgJuxyFHwAqAgABLgAECggJFAAeALscAA==.Deltritus:BAACLgAFFH8XAAINAAYJJBqGGwC3AQANAAYJJBqGGwC3AQAuAAQKfzQAAg0ACQnnI/0FAEEDAA0ACQnnI/0FAEEDAAEuAAQKCAkUAB4AuxwA.Demaedra:BAAALgAECgMJAwAAAA==.Demoan:BAABLgAECn80AAIfAAkJKSP7AAAbAwAfAAkJKSP7AAAbAwAAAA==.Demonbiscuit:BAACLgAFFH8GAAIgAAQJ6x16AwCaAQAgAAQJ6x16AwCaAQAuAAQKfxgAAiAABwmlJhwHAJcCACAABwmlJhwHAJcCAAAA.Derpydawg:BAAALgAECgEJAQABLgAFFAQJDQAMAKIbAA==.Dethh:BAAALgADCgMJAwAAAA==.Deviancy:BAABLgAECn8XAAMCAAkJdxlpDgCIAgACAAkJdxlpDgCIAgAIAAEJpAUifgEjAAAAAA==.',
Dh='Dhruven:BAAALgADCggJCAAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAABLgAECn8UAAIOAAYJ0A+OSwDTAAAOAAYJ0A+OSwDTAAAAAA==.Diese:BAAALgAECgYJBgAAAA==.Dikslapp:BAABLgAECn8vAAIgAAkJYyFTBADbAgAgAAkJYyFTBADbAgAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Dipperton:BAAALgAECgEJAQABLgAECgcJFAAXAOkaAA==.Discrespect:BAACLgAFFH8JAAIWAAQJYBTfGgAyAQAWAAQJYBTfGgAyAQAuAAQKfx8ABBYACAlYGnERAC0CABYACAlYGnERAC0CAAcABAkiCMhcAMAAAAYAAQkfA8J7ACIAAAAA.Distinct:BAAALgAECggJCAABLgAECgkJNAAfACkjAA==.Distress:BAAALgAECgYJBgAAAA==.Ditto:BAACLgAFFH8HAAIYAAMJ/xCpHQC6AAAYAAMJ/xCpHQC6AAAuAAQKfzsABBgACAmpHOsMAEECABgACAmpHOsMAEECAAwABwkpCwiOACMBABAAAwlBDt4PAJ4AAAAA.',
Dl='Dlitinaro:BAABLgAECn80AAMMAAkJIyEvGgCHAgAYAAkJcx7zBgCKAgAMAAkJBx8vGgCHAgAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMPAAMJoxd9DQAHAQAPAAMJoxd9DQAHAQAOAAEJHAmrUAA/AAAuAAQKfxkAAw8ACAlwJLYDACADAA8ACAlwJLYDACADAA4AAwlpGjBOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Dollette:BAAALgAECgcJAgAAAA==.Donoph:BAABLgAECn84AAMCAAkJ/yO+AQCEAwACAAkJ/yO+AQCEAwAIAAEJQwzNWwE0AAAAAA==.Doomar:BAABLgAECn8uAAIDAAkJNCHFEgCgAgADAAkJNCHFEgCgAgAAAA==.Doomsamdi:BAAALgAECgcJCAABLgAECgkJLgADADQhAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8cAAMhAAkJqgfvMQDxAAADAAkJ4wWFfgAnAQAhAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgADCggJFgAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8hAAMXAAgJSQu+HwAwAQAXAAcJZwq+HwAwAQAOAAYJ9AowRgDpAAAAAA==.Dreav:BAAALgAECgIJAgAAAA==.Drugar:BAABLgAECn8aAAINAAYJqgwFuwD0AAANAAYJqgwFuwD0AAAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEx8IFQDCAAAEAAIJEx8IFQDCAAAuAAQKfxYAAgQACAneHbASALkCAAQACAneHbASALkCAAEuAAUUCQkvABUAJSIA.',
Du='Duloc:BAAALgAECgMJAwAAAA==.Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgQJCgAAAA==.',
Dy='Dynabol:BAABLgAECn8uAAMTAAkJDiYgAgBdAwATAAkJfCUgAgBdAwAfAAgJISW1AQDkAgAAAA==.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAQJDQAMAKIbAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgAECgEJAgAAAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Ev='Eveleigh:BAAALgAECgEJAQAAAA==.Everfale:BAAALgAECgIJAwABLgAFFAEJAQABAAAAAQ==.Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn8yAAIEAAkJIhvbEwAvAgAEAAkJIhvbEwAvAgAAAA==.Faolsabre:BAABLgAECn8lAAIMAAgJIQwRbgBjAQAMAAgJIQwRbgBjAQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgARAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn82AAIdAAkJyRI5CQAAAgAdAAkJyRI5CQAAAgAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8mAAIaAAkJERm3FgBvAgAaAAkJERm3FgBvAgAAAA==.',
Fo='Folid:BAAALgAECgEJAQAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB51CgDOAgACAAkJbB51CgDOAgAAAA==.Frostedphyre:BAAALgAECgkJDQAAAA==.',
Fu='Furrywhaco:BAABLgAECn8UAAIiAAkJ+RotBgBsAgAiAAkJ+RotBgBsAgAAAA==.Fuzzyspells:BAAALgAECgUJBwAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMIAAgJLxv2SwD/AQAIAAYJsB72SwD/AQAUAAYJ7xKDGwAOAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.',
Ge='Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn84AAMjAAgJ7wdsIgBTAQAjAAgJ7wdsIgBTAQAkAAYJkgOQEQDuAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBAAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQNAAgJsyQ4HwD4AgANAAgJniQ4HwD4AgAlAAEJnCZFFQBzAAAmAAEJiSQ/DABrAAABLgAECgkJLgATAA4mAA==.',
Gr='Gravez:BAAALgAECgQJBAABLgAFFAEJAQABAAAAAA==.Grawler:BAAALgAECgYJBgAAAA==.Greeny:BAAALgAECgQJDAAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgQJCgABLgAECgcJBwABAAAAAA==.Grumpyhunter:BAAALgAECgcJEAABLgAECgkJNQANAOsfAA==.',
Gu='Gumgumfury:BAAALgAECgQJCAAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haidies:BAAALgAECgUJDgABLgAFFAQJDQAaALkPAA==.Halzlok:BAABLgAECn8XAAIZAAYJMBBlRgDqAAAZAAYJMBBlRgDqAAAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAUJFwAFAEwkAA==.Herøn:BAAALgAECgUJAQAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJKAAaAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAFFAQJBgAgAOsdAA==.Hondacivic:BAAALgAECgEJAQABLgAECgkJJAAjAH0kAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ia='Iandis:BAAALgADCgUJBQABLgAECgYJGgAFAOcTAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgIJAgAAAA==.',
Im='Imysteriöus:BAABLgAECn8oAAMaAAgJBiUvBQBOAwAaAAgJBiUvBQBOAwAdAAYJHhSJEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAACLgAFFH8QAAICAAUJBxyvDACpAQACAAUJBxyvDACpAQAuAAQKfxcAAgIACAlAHJ0bADcCAAIACAlAHJ0bADcCAAAA.Indishaman:BAAALgAECgYJCQAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJKwAIADMhAA==.',
Is='Ishamael:BAABLgAECn8tAAIGAAkJUxKDGgDLAQAGAAkJUxKDGgDLAQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8LAAIXAAQJBhgdAgBYAQAXAAQJBhgdAgBYAQAuAAQKfywAAhcACQkHIhIBAO0CABcACQkHIhIBAO0CAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jarnroz:BAAALgAECgQJBAAAAA==.Jaythirian:BAABLgAECn8YAAMnAAcJrQ6JEACUAQAnAAcJrQ6JEACUAQAEAAQJ1gQVgQC5AAAAAA==.',
Je='Jerg:BAACLgAFFH8NAAIaAAQJuQ+hJAAMAQAaAAQJuQ+hJAAMAQAuAAQKfzkAAxoACQlUHtgWAH8CABoACAmfHdgWAH8CABsABwk3FnAlAHIBAAAA.Jessup:BAACLgAFFH8LAAMoAAMJkiG3BQAFAQAoAAMJMR23BQAFAQAjAAIJuxtdJQCiAAAuAAQKfyoAAyMACQmKIn8EAFADACMACQn8IX8EAFADACgABQl9IXQIAIQBAAAA.',
Jh='Jhara:BAABLgAECn8bAAINAAYJCRFQoQAfAQANAAYJCRFQoQAfAQAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAABLgAECn8sAAQWAAkJECSeBgDeAgAWAAkJTSOeBgDeAgAHAAUJtyG4GADfAQAGAAUJ0BxkNQBAAQABLgAECgkJGQAKAOAaAA==.Junnai:BAAALgADCgcJBwAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECgcJDQAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgUJBgAAAA==.Kamekazi:BAAALgADCgYJBgAAAA==.Kariva:BAABLgAECn8pAAIHAAkJORasDgBWAgAHAAkJORasDgBWAgAAAA==.Katacemic:BAABLgAECn8XAAIYAAYJ3g0QKwDPAAAYAAYJ3g0QKwDPAAABLgAECgkJIgAhAF8KAA==.Katastrophic:BAAALgADCggJEAABLgAECgkJIgAhAF8KAA==.Katazul:BAABLgAECn8iAAMhAAkJXwqrJgArAQADAAkJewfgXgBtAQAhAAYJzgqrJgArAQAAAA==.Kaulike:BAAALgADCgIJAgAAAA==.',
Ke='Keelanllan:BAABLgAECn8ZAAIgAAgJcgjnJQAPAQAgAAgJcgjnJQAPAQAAAA==.Keilun:BAEALgAECgYJCgAAAA==.Kew:BAAALgAECgUJDwAAAA==.Kewkew:BAAALgADCgcJBwAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECggJIAAPACoRAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJIgAOADURAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Ko='Koggmaw:BAAALgAECgcJEAABLgAFFAQJDQAaALkPAA==.Koral:BAAALgAECgYJBgAAAA==.',
Kr='Kralj:BAAALgAECgUJCAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJPAAYAOwiAA==.Kungfuhealya:BAABLgAECn8eAAMKAAgJxwULSgDoAAAKAAgJxwULSgDoAAALAAEJwQHAmgAaAAAAAA==.Kuraj:BAAALgAECgEJAQAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAAIAPkbAA==.Larrydale:BAABLgAECn8aAAMSAAgJTxwTGQByAgASAAgJTxwTGQByAgARAAEJqQMDMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAAIAPkbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn8mAAMYAAgJtQ7KHQA3AQAYAAgJPA3KHQA3AQAMAAQJPgx/vwDTAAAAAA==.',
Le='Lea:BAAALgAECgIJAgABLgAECgkJJQANADQZAA==.Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgMJBQAAAA==.Leondis:BAACLgAFFH8GAAISAAIJsxS3YACRAAASAAIJsxS3YACRAAAuAAQKfyoAAhIACQmLHzQIAA0DABIACQmLHzQIAA0DAAAA.Leviosa:BAAALgAECgMJAgAAAA==.Lexipriest:BAACLgAFFH8bAAMHAAYJ3huuAgARAgAHAAYJ3huuAgARAgAWAAMJiQtgEADHAAAuAAQKf1EAAwcACQlrIecCAFADAAcACQlrIecCAFADABYACAkzHYcIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.Lilpp:BAAALgAECgIJAgABLgAECgYJDgABAAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgYJGgAFAOcTAA==.Lockmonster:BAAALgAECgIJAwAAAA==.Locksteady:BAAALgAECgUJBgAAAA==.Lookalock:BAAALgAECgQJBQAAAA==.Lorp:BAAALgAECgYJBwAAAA==.Lotglock:BAAALgAECgkJCgAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAITAAgJeB2EKQBcAgATAAgJeB2EKQBcAgAAAA==.Lumosmaxiima:BAAALgAECgcJCgAAAA==.Lunadesangre:BAAALgAECgEJAQAAAA==.Lunarette:BAAALgAECgMJBQAAAA==.',
Ly='Lydax:BAABLgAECn8UAAIIAAcJ+RtqVwDcAQAIAAcJ+RtqVwDcAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAAALgAECgYJEQAAAA==.Madkingzack:BAABLgAECn8XAAMEAAkJbx4MDACFAgAEAAkJbx4MDACFAgAnAAEJywaRZgApAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAABLgAECn8UAAMhAAYJHxXpDQAyAQAhAAYJHxXpDQAyAQADAAQJWwzXrgDNAAAAAA==.Mallikii:BAABLgAECn8dAAMaAAkJ0hu9MADoAQAaAAkJ0hu9MADoAQAbAAQJrSMBOABZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8dAAINAAkJyg1HigBHAQANAAkJyg1HigBHAQAAAA==.Marigosa:BAAALgAECgcJCwAAAA==.Marnolkas:BAAALgADCggJCAABLgAECgQJBwABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAABLgAECn8kAAMIAAgJQx9CHwBtAgAIAAgJQx9CHwBtAgACAAUJrSB6IgDKAQAAAA==.Mattdemon:BAAALgAECgcJBwAAAA==.Maudib:BAABLgAECn8VAAIiAAgJSRUwHQAgAQAiAAgJSRUwHQAgAQAAAA==.Mawile:BAAALgAECgQJBwAAAA==.',
Me='Meautiful:BAAALgADCgQJBAAAAA==.Medusa:BAAALgAECgQJCgAAAA==.Meesha:BAAALgAECgIJAgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAAALgAECgYJEwAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQhAAgJBA97HABqAQAhAAcJYw57HABqAQADAAUJ/wrlxQDNAAAcAAEJ2hVmLgBBAAAAAA==.Merkxi:BAABLgAECn8tAAIRAAkJBiJWAQA8AwARAAkJBiJWAQA8AwAAAA==.Messe:BAABLgAECn8/AAIoAAkJAR6vAQCpAgAoAAkJAR6vAQCpAgAAAA==.Mestre:BAAALgAECgYJCgAAAA==.Methious:BAABLgAECn8WAAIIAAkJnRg3agCqAQAIAAkJnRg3agCqAQAAAA==.',
Mi='Minigoober:BAAALgAECgQJBAAAAA==.',
Mo='Mogli:BAAALgAECgQJAQABLgAECggJLwATAPUfAA==.Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8XAAIJAAYJqgieFwA2AQAJAAYJqgieFwA2AQAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECgUJCQAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonrivr:BAAALgAECgMJAwABLgAECggJJgAYALUOAA==.Moonsguard:BAAALgADCgcJCgABLgAECgQJCQABAAAAAA==.Moovit:BAAALgAECgYJEgAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgIJAQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.',
My='Myströnghand:BAAALgAECgcJBwAAAA==.',
Na='Nagumo:BAABLgAECn8mAAMhAAgJFQTyOQDMAAADAAgJ4wMglgD6AAAhAAYJYAPyOQDMAAAAAA==.Nala:BAABLgAECn8WAAMbAAgJqhHKLQA7AQAbAAcJvw7KLQA7AQAaAAQJWBdtbgAJAQABLgAFFAQJDQAaALkPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAACLgAFFH8GAAIOAAMJ9AslNADDAAAOAAMJ9AslNADDAAAuAAQKfy4AAw4ACAklGFQyAEEBAA4ABwkgF1QyAEEBAA8ABwllEs8WAD0BAAAA.',
Ne='Nekoya:BAAALgADCgMJAwAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8KAAITAAQJUB20IgBcAQATAAQJUB20IgBcAQAuAAQKfyoAAxMACQmiJfMAANgDABMACQmiJfMAANgDAB8AAQk3FOYpADcAAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgAECgcJBwAAAA==.Nivan:BAAALgAECgQJBQAAAA==.Niço:BAACLgAFFH8FAAISAAMJ2RICQgDnAAASAAMJ2RICQgDnAAAuAAQKfxQAAhIACQnPHKkfAEcCABIACQnPHKkfAEcCAAAA.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIaAAkJJhs5HgBNAgAaAAkJJhs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAAALgAFFAEJAQAAAQ==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
Nu='Nutz:BAAALgAECgkJAgAAAA==.',
['Nï']='Nï:BAAALgAECgEJAQAAAA==.',
Oa='Oakmoss:BAAALgADCgcJBgAAAA==.',
Of='Offlyne:BAAALgAECgEJAQAAAA==.',
Oh='Ohntakae:BAAALgAECgUJAgAAAA==.',
Ok='Oksana:BAAALgAECgcJCAAAAA==.',
Ol='Ollamh:BAAALgAECgEJAgAAAA==.',
Om='Ombravuota:BAAALgAECgcJEQAAAA==.',
Oo='Oom:BAAALgAECgIJAgAAAA==.',
Or='Oralian:BAABLgAECn8hAAMhAAkJwSMrCwANAgAhAAUJrCMrCwANAgADAAUJhCMLRQD8AQAAAA==.Orcleave:BAABLgAECn8UAAMEAAcJIxuIQwCXAQAEAAYJ3xSIQwCXAQAFAAUJsR6YHgBQAQAAAA==.Orflap:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.',
Ov='Ovee:BAAALgADCgcJBgAAAA==.',
Pa='Paboo:BAAALgAECgcJDAAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8lAAMNAAkJNBmJMAA4AgANAAkJNBmJMAA4AgAmAAEJZQm/DwAvAAAAAA==.Perturabo:BAAALgAECgEJAgAAAA==.',
Ph='Phoenyx:BAABLgAECn8VAAMhAAYJpAk4GQC6AAAhAAYJpAk4GQC6AAADAAUJjQGC7ABeAAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMSAAcJDx2zJAAqAgASAAcJDx2zJAAqAgAeAAMJdQuDawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJHQANAMoNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgAECgIJAgAAAA==.',
['Põ']='Põ:BAAALgAECgMJAwABLgAECggJJAAIAEMfAA==.',
Qu='Quorra:BAAALgAECgEJAQAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8rAAIEAAkJcB7kDgBjAgAEAAkJcB7kDgBjAgAAAA==.Rakagar:BAABLgAECn8yAAIIAAkJOh5rGACTAgAIAAkJOh5rGACTAgAAAA==.Ranko:BAAALgAECgkJBAAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8ZAAIKAAYJSRz0CAABAgAKAAYJSRz0CAABAgAuAAQKfy8AAgoACQkQIMsMAJkCAAoACQkQIMsMAJkCAAAA.Reyz:BAABLgAECn8ZAAIKAAgJHBWGIQCnAQAKAAgJHBWGIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQAAAA==.',
Rh='Rhaegos:BAAALgAECgQJBwAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8hAAIEAAYJTCGTJACsAQAEAAYJTCGTJACsAQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
Ry='Rythmias:BAAALgAECgEJAQAAAA==.Ryvive:BAAALgADCgkJEQAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAFFAQJDAASAE0eAA==.',
['Rë']='Rëz:BAAALgADCgYJBgAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAECgcJFAAEACMbAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8xAAMgAAkJ1yLgAwDpAgAgAAkJ1yLgAwDpAgATAAYJUhkwWgBVAQABLgAECgkJNAAMACMhAA==.Scripts:BAAALgAECgYJEQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJHQANAMoNAA==.',
Sh='Shale:BAABLgAECn8/AAMPAAkJjhm9BgBzAgAPAAkJjhm9BgBzAgAOAAgJqgjCVACzAAAAAA==.Shamboo:BAAALgADCggJCAAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAACLgAFFH8FAAIZAAMJ6BZ2IgDnAAAZAAMJ6BZ2IgDnAAAuAAQKfxkAAxkABwkKHCUkAJkBABkABwkKHCUkAJkBACkABAnmDFF0AL8AAAAA.Sharaiya:BAABLgAECn8sAAIaAAkJvgU2XwD4AAAaAAkJvgU2XwD4AAAAAA==.Sharkmanfive:BAAALgAECgUJBQAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Sherp:BAAALgAECgEJAQAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAABLgAECn8bAAMSAAYJciCTOQDNAQASAAYJciCTOQDNAQAeAAEJJRGYhgA2AAAAAA==.Sioux:BAAALgAECgQJBwAAAA==.',
Sk='Skippybmm:BAAALgAECgQJDAABLgAECgYJGgAFAOcTAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgEJAQABLgAECgkJPwAoAAEeAA==.',
Sm='Smexyshâmmy:BAAALgAECggJDQAAAA==.',
So='Soferus:BAAALgADCggJCAABLgAECgQJBwABAAAAAA==.Solaire:BAACLgAFFH8LAAIUAAQJ7BlSBAAhAQAUAAQJ7BlSBAAhAQAuAAQKfywAAhQACQn+ILkBADMDABQACQn+ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJuR4IEAC0AgADAAkJuR4IEAC0AgABLgAFFAYJGQATAOUdAA==.Soulful:BAAALgAECgYJBgAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAaALkPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAABLgAECn8aAAIFAAYJ5xNEHwAPAQAFAAYJ5xNEHwAPAQAAAA==.Spot:BAAALgAECgYJBgABLgAECgkJHQANAMoNAA==.Spyy:BAAALgAECgYJCwAAAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgQJBwAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn8yAAMRAAkJ8htOBwCRAgARAAkJ8htOBwCRAgAeAAcJKBXIEgAKAQAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECggJMAAfABoQAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8eAAMhAAgJeBa5BgC/AQAhAAgJeBa5BgC/AQADAAEJlQH7NwEaAAAAAA==.Tankinit:BAAALgAECgQJCwAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgAECgEJAQABLgAECgQJBAABAAAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIUAAMJswgGBACcAAAUAAMJswgGBACcAAAuAAQKfyUAAhQACAkJHX0GAIACABQACAkJHX0GAIACAAAA.Tenzink:BAABLgAECn8mAAIKAAkJGRw0DACjAgAKAAkJGRw0DACjAgAAAA==.',
Th='Thalon:BAAALgAECgMJAwABLgAFFAMJBQAMACsXAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgAECgEJAgAAAA==.Thedru:BAABLgAECn8xAAIaAAgJiw09RwBPAQAaAAgJiw09RwBPAQAAAA==.Thrastus:BAAALgADCgIJAgAAAA==.Thrus:BAAALgAECgYJEAABLgAECgkJPwAoAAEeAA==.Théworld:BAAALgAECgQJCQAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgYJBwABLgAECgkJJQANADQZAA==.',
Tl='Tlnks:BAAALgADCgQJBwAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Tokeon:BAAALgAECgEJAQAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAABLgAECn8dAAIRAAkJjxrgBgCYAgARAAkJjxrgBgCYAgAAAA==.',
Tr='Traler:BAAALgAECgEJAQABLgAECgkJNgAdAMkSAA==.Tralzitashan:BAABLgAECn8wAAMlAAkJDA9OAwDNAQAlAAkJDA9OAwDNAQANAAQJzAMXIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAINAAcJWhq0ZQAMAgANAAcJWhq0ZQAMAgAAAA==.Tren:BAAALgADCgMJAwAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgAECgYJBgAAAA==.',
Ty='Tyrdonut:BAAALgAECgEJAQABLgAECggJIQAXAEkLAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAAALgAECgUJCwAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAACLgAFFH8HAAIIAAMJpR1AOAAcAQAIAAMJpR1AOAAcAQAuAAQKfxgAAggACQnlJBUFADkDAAgACQnlJBUFADkDAAAA.Unglausp:BAACLgAFFH8GAAIGAAMJFhYjGgDyAAAGAAMJFhYjGgDyAAAuAAQKfyIAAgYACAn9HtINAKYCAAYACAn9HtINAKYCAAEuAAUUAwkHAAgApR0A.',
Uz='Uzington:BAACLgAFFH8aAAIFAAUJ3RKyDwAHAQAFAAUJ3RKyDwAHAQAuAAQKfyYAAgUACQmyHPQIAI8CAAUACQmyHPQIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgIJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAAALgAECgYJDwAAAA==.Valorien:BAACLgAFFH8GAAIIAAMJ0xNPSADyAAAIAAMJ0xNPSADyAAAuAAQKfyEAAggACAkgGwQyABcCAAgACAkgGwQyABcCAAAA.Valzlok:BAAALgAECgMJAwAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgARAC0jAA==.Velinieron:BAABLgAECn8eAAIRAAkJLSNPBQC8AgARAAkJLSNPBQC8AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgARAC0jAA==.Vellash:BAABLgAECn8ZAAIgAAYJMwrBLQDYAAAgAAYJMwrBLQDYAAAAAA==.Vendétta:BAABLgAECn8jAAISAAkJSQ8gTgCKAQASAAkJSQ8gTgCKAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8dAAINAAgJIQq8fABhAQANAAgJIQq8fABhAQAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgADCggJCQAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8jAAISAAgJCxA4RwCfAQASAAgJCxA4RwCfAQAAAA==.',
Vy='Vynlandis:BAABLgAECn84AAMMAAkJ0BiBKwAvAgAMAAkJ0BiBKwAvAgAQAAMJgQS0IQBoAAAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAaALkPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Wargg:BAAALgAECgUJBQABLgAECgkJHQAgAFsbAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAAALgAECgYJCwAAAA==.Weenbean:BAAALgAECgcJCQAAAA==.Werebray:BAAALgAECgcJEAABLgAFFAMJBgARAMETAA==.',
Wh='Whaco:BAABLgAECn8fAAIUAAgJmBsyCgD6AQAUAAgJmBsyCgD6AQAAAA==.Whatisaggro:BAABLgAECn8ZAAIEAAcJ4BupKACSAQAEAAcJ4BupKACSAQAAAA==.Whispertree:BAABLgAECn8pAAIbAAgJkSJWCwB6AgAbAAgJkSJWCwB6AgAAAA==.White:BAAALgAECgUJBQABLgAECgkJNgARAM8iAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECggJIQAXAEkLAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8NAAMMAAQJohviMwBcAQAMAAQJohviMwBcAQAQAAEJiQVlGgA/AAAuAAQKfycAAwwACQkXIWINAC8DAAwACQkXIWINAC8DABAAAQl9HTskAFUAAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8uAAQYAAcJNxnqFADDAQAYAAYJmx3qFADDAQAMAAcJoxL4dwBNAQAQAAIJcxhNEgBsAAAAAA==.Wixypoo:BAACLgAFFH8IAAIJAAMJOBTGKgDeAAAJAAMJOBTGKgDeAAAuAAQKfy4AAwkACQnoHWYJAIACAAkACQnoHWYJAIACAAoAAQnpAXiaABsAAAAA.',
Wo='Wockyslush:BAABLgAECn8kAAIjAAkJfSTpCAADAwAjAAkJfSTpCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMOAAkJWhgXFAAbAgAOAAkJWhgXFAAbAgAXAAYJwAMuKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8dAAIpAAgJvR3MGABWAgApAAgJvR3MGABWAgAAAA==.',
Wy='Wyyn:BAABLgAECn8vAAINAAgJwQrQgQBXAQANAAgJwQrQgQBXAQAAAA==.',
Xa='Xanboi:BAABLgAECn87AAMRAAkJ7ySLAQAvAwARAAkJ7ySLAQAvAwASAAIJ6iK1iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAACLgAFFH8LAAIEAAUJfR6pDQBiAQAEAAUJfR6pDQBiAQAuAAQKfycAAgQACQndIRINAO0CAAQACQndIRINAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Yo='Yona:BAAALgADCgIJAgABLgAECgkJHQANAMoNAA==.',
Ys='Ysar:BAABLgAECn8YAAIOAAgJ0w3iLQBdAQAOAAgJ0w3iLQBdAQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMXAAcJ6RqJDgDyAQAXAAYJkB+JDgDyAQAOAAYJGxdJIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECgcJJgAUAN0UAA==.',
Ze='Zeebu:BAABLgAECn8sAAIRAAgJhQpYHgCLAQARAAgJhQpYHgCLAQAAAA==.Zenboi:BAABLgAECn8cAAITAAgJ1RUcQwDnAQATAAgJ1RUcQwDnAQAAAA==.Zephryyn:BAAALgAECgcJEgAAAA==.',
Zh='Zhilan:BAAALgAECgQJCAAAAA==.',
Zi='Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAQJCwAoAJIhAA==.Zophos:BAAALgAECggJDwABLgAECggJFgAhAAQPAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgEJAgAAAA==.Zuzuk:BAAALgAECggJEwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAAALgAECgcJDgAAAA==.',
['Zú']='Zúz:BAAALgAECgcJEgAAAA==.',
['Áß']='Áßomination:BAAALgAECgUJCAAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAABLgAECn8pAAIpAAkJmgtXSwBOAQApAAkJmgtXSwBOAQAAAA==.',
['Ði']='Ðittø:BAAALgAECggJEQABLgAFFAMJBwAYAP8QAA==.',
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
