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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Priest-Shadow','Priest-Holy','Monk-Brewmaster','DeathKnight-Unholy','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','DeathKnight-Frost','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Priest-Discipline','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Balance','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','Druid-Feral','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Mage-Fire','Warrior-Arms','Rogue-Outlaw','Druid-Guardian','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aalduin:BAAALgAECgMJBAABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCAAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgADCggJEQAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAQJCgACAIgZAQ==.',
Af='Affli:BAACLgAFFH8LAAIDAAQJ9xDHNgAhAQADAAQJ9xDHNgAhAQAuAAQKfysAAgMACQkUIEIbALECAAMACQkUIEIbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8mAAIFAAgJEhWeDgCvAQAFAAgJEhWeDgCvAQAAAA==.Aiupriesty:BAABLgAECn8YAAMGAAcJ2Qc8MgD+AAAGAAcJ2Qc8MgD+AAAHAAMJ/xFwYQCrAAABLgAECggJJgAFABIVAA==.',
Ak='Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAAALgAECgEJAQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAAALgAECgQJCwAAAA==.Aleinara:BAAALgAECgUJDgAAAA==.Aleridin:BAABLgAECn8rAAIIAAkJHiXxAABRAwAIAAkJHiXxAABRAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAAALgAFFAIJBAAAAA==.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Andsey:BAAALgAECgMJAwAAAA==.Annore:BAABLgAECn8aAAIJAAkJPhDJRQCqAQAJAAkJPhDJRQCqAQAAAA==.Antihero:BAABLgAECn8hAAIJAAkJeiN5DgAnAwAJAAkJeiN5DgAnAwAAAA==.',
Aq='Aquiell:BAABLgAECn8bAAIKAAYJcRKuiAArAQAKAAYJcRKuiAArAQAAAA==.Aqular:BAAALgADCgYJBgAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8OAAIFAAQJciJbBQCFAQAFAAQJciJbBQCFAQAuAAQKfzgAAwUACAnzI1wEAJ8CAAUACAnzI1wEAJ8CAAQABQnNECxFAN0AAAAA.Arkenomu:BAABLgAECn8iAAMLAAgJMxF0IwBuAQALAAgJMxF0IwBuAQAMAAcJaQzBEwBBAQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8pAAMNAAgJ3AhFDQAhAQANAAgJ3AhFDQAhAQAJAAYJsAHP7AClAAAAAA==.Asclepius:BAABLgAECn8eAAIMAAgJKhFYDQCwAQAMAAgJKhFYDQCwAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Aslo:BAAALgADCgEJAQAAAA==.Asmira:BAAALgADCgYJCAAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn8gAAMOAAcJqCA/DQAPAgAOAAcJZCA/DQAPAgAPAAQJwRrsagAnAQAAAA==.',
At='Atsunvhi:BAAALgAECgQJCQAAAA==.',
Av='Avadakedevra:BAABLgAECn8fAAMOAAYJJhXQEwCIAQAOAAYJJhXQEwCIAQAPAAEJKwpFzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azreal:BAAALgAECgYJBgAAAA==.Azumok:BAAALgADCgEJAQAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bakedbean:BAAALgAECgEJAgABLgAECgkJJQAQAOolAA==.Barackobooma:BAAALgADCgcJBwAAAA==.Bazerker:BAAALgADCgIJAgAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8eAAIKAAgJjQ3/bABhAQAKAAgJjQ3/bABhAQAAAA==.',
Be='Belgaria:BAABLgAECn8jAAMRAAYJhBa3EwA4AQASAAYJNQ9ilQBSAQARAAYJhBa3EwA4AQAAAA==.Berryknight:BAABLgAECn8qAAMJAAgJjBreOQDTAQAJAAgJjBreOQDTAQANAAIJ3g+eGgBmAAAAAA==.Berryqt:BAAALgAECgQJCAAAAA==.Bewlzeye:BAAALgAECgUJBwAAAA==.',
Bi='Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8TAAIHAAUJKSZhAQAoAgAHAAUJKSZhAQAoAgAuAAQKfx8AAgcACQnOJIkDACIDAAcACQnOJIkDACIDAAAA.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodydk:BAAALgADCgMJAwAAAA==.Bluestripee:BAAALgAECgEJAQAAAA==.Bluezugzug:BAAALgAECgMJBAAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8qAAITAAkJnBU0BwD8AQATAAkJnBU0BwD8AQAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn8xAAMGAAgJkyKgBwCSAgAGAAgJkyKgBwCSAgAUAAEJaBblVgA0AAAAAA==.Bonsaichi:BAAALgAECgIJAgAAAA==.Bownyxia:BAACLgAFFH8JAAILAAMJQBaVEQD1AAALAAMJQBaVEQD1AAAuAAQKfzYAAwsACQnGImADAA8DAAsACQnGImADAA8DABUABAlHDvspAM4AAAEuAAUUCAkkAAkAjxoA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAgJJAAJAI8aAA==.Bowties:BAACLgAFFH8kAAMJAAgJjxqBAQCcAgAJAAcJjxqBAQCcAgAWAAEJAACiNgAAAAAuAAQKf0MAAwkACQmTJoIAAIwDAAkACQmTJoIAAIwDABYACQk3GHkKAHECAAAA.',
Br='Braxchud:BAABLgAECn8mAAIXAAgJ3hfQFgDbAQAXAAgJ3hfQFgDbAQAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAIKAAkJixvsHABzAgAKAAkJixvsHABzAgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8RAAIQAAQJGROQFAAuAQAQAAQJGROQFAAuAQAuAAQKfx0AAhAACQmtHY0OAJACABAACQmtHY0OAJACAAEuAAUUCAkkAAkAjxoA.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgADCgcJBwABLgAECgcJGwAEACwkAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgMJCgAAAA==.',
Ca='Caarrl:BAAALgAECgMJBQAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBQAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgADCgcJCwAAAA==.Caplock:BAAALgAECgEJAQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAAALgADCgUJBQAAAA==.Cartime:BAAALgADCgEJAQAAAA==.Cayllia:BAABLgAECn8iAAMYAAkJ+COOBABFAwAYAAkJ+COOBABFAwAZAAgJDCJfDQAzAgAAAA==.',
Ce='Celaris:BAAALgAECgMJCAAAAA==.',
Ch='Chaolang:BAAALgAECgIJAgAAAA==.Chataykay:BAAALgAECgYJCQAAAA==.Cherrypepsï:BAABLgAECn8cAAMHAAkJOQ/aKwCYAQAHAAkJOQ/aKwCYAQAUAAUJdgbwOADgAAAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chivies:BAAALgAECgcJBwABLgAECgkJKQASADMhAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAABLgAECn8WAAIaAAgJMxNjCAB3AQAaAAgJMxNjCAB3AQAAAA==.Citrus:BAABLgAECn8xAAIOAAkJLxXnDAAUAgAOAAkJLxXnDAAUAgAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBQAAAA==.Cliqmonk:BAAALgAECgcJBgAAAA==.',
Cn='Cn:BAABLgAECn8pAAISAAkJMyFPCwDXAgASAAkJMyFPCwDXAgAAAA==.',
Co='Cocoabutter:BAABLgAECn8ZAAIKAAYJWBChiwAlAQAKAAYJWBChiwAlAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAAKAIsbAA==.Codeman:BAABLgAECn8yAAMWAAkJYiI9AgAEAwAWAAkJYiI9AgAEAwAJAAEJEwvYCwE4AAAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJMgAWAGIiAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8UAAMbAAUJsBVZCgAzAQAbAAUJsBVZCgAzAQAcAAQJhBVMFgAVAQAuAAQKf1kAAxwACQlGIygCAHQDABwACQlGIygCAHQDABsABgkdH/kVALQBAAAA.Contemplate:BAAALgAECgMJCAABLgAECgYJBgABAAAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECgkJGwABLgAECggJHQABAAAAAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.',
Ct='Ctk:BAAALgAECgEJAQAAAA==.',
Cu='Culluh:BAAALgADCgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAABLgAECn8cAAIdAAYJFhyRDwBYAQAdAAYJFhyRDwBYAQAAAA==.',
Cz='Czin:BAABLgAECn8bAAMEAAcJLCTgDQBLAgAEAAcJLCTgDQBLAgAFAAEJkQnBSwAlAAAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgEJAgAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJBwAAAA==.Deathverses:BAACLgAFFH8nAAIeAAYJ4CZOAQA/AgAeAAYJ4CZOAQA/AgAuAAQKfy4AAh4ACQniJikCAJYDAB4ACQniJikCAJYDAAAA.Deerslayer:BAAALgAECgcJDgAAAA==.Deezknights:BAAALgAECgUJCAABLgAECgYJCgABAAAAAA==.Delter:BAABLgAECn8UAAIeAAgJuxyFHwAqAgAeAAgJuxyFHwAqAgABLgAECggJFAAeALscAA==.Deltritus:BAACLgAFFH8QAAIKAAUJ4Rn7KwBeAQAKAAUJ4Rn7KwBeAQAuAAQKfysAAgoACQllIDMNAN8CAAoACQllIDMNAN8CAAEuAAQKCAkUAB4AuxwA.Demoan:BAABLgAECn8tAAIfAAkJBiO7AAAWAwAfAAkJBiO7AAAWAwAAAA==.Demonbiscuit:BAABLgAECn8YAAIgAAcJoyZpBQCeAgAgAAcJoyZpBQCeAgAAAA==.Derpydawg:BAAALgAECgEJAQABLgAFFAQJCQAJAH4aAA==.Deviancy:BAABLgAECn8UAAMCAAgJNRmTEQA+AgACAAgJNRmTEQA+AgASAAEJpAViTgEnAAAAAA==.',
Dh='Dhruven:BAAALgADCggJCAAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAABLgAECn8UAAILAAYJ0A9mPwDXAAALAAYJ0A9mPwDXAAAAAA==.Dikslapp:BAABLgAECn8mAAIgAAkJHSEnAwDiAgAgAAkJHSEnAwDiAgAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Dipperton:BAAALgAECgEJAQABLgAECgcJFAAVAOkaAA==.Discrespect:BAACLgAFFH8JAAIUAAQJYBTyFQA0AQAUAAQJYBTyFQA0AQAuAAQKfx8ABBQACAlYGnERAC0CABQACAlYGnERAC0CAAcABAkiCMhcAMAAAAYAAQkfA8ZsACIAAAAA.Distinct:BAAALgAECggJCAABLgAECgkJLQAfAAYjAA==.Distress:BAAALgAECgYJBgAAAA==.Ditto:BAACLgAFFH8FAAIWAAMJ4QsNHACXAAAWAAMJ4QsNHACXAAAuAAQKfzQABBYACAmfHOsMAEECABYACAmfHOsMAEECAA0AAwlBDt4PAJ4AAAkAAQmTCqMVAS8AAAAA.',
Dl='Dlitinaro:BAABLgAECn80AAMWAAkJIyHdBACkAgAWAAkJch7dBACkAgAJAAkJBR8WEwCWAgAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMMAAMJoxd9DQAHAQAMAAMJoxd9DQAHAQALAAEJHAlcRQBDAAAuAAQKfxkAAwwACAlvJLYDACADAAwACAlvJLYDACADAAsAAwljGjBOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Dollette:BAAALgAECgcJAgAAAA==.Donoph:BAABLgAECn8yAAICAAkJxSMzAQCIAwACAAkJxSMzAQCIAwAAAA==.Doomar:BAABLgAECn8uAAIDAAkJNCFiDQCvAgADAAkJNCFiDQCvAgAAAA==.Doomsamdi:BAAALgAECgEJAQABLgAECgkJLgADADQhAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8cAAMhAAkJqgfvMQDxAAADAAkJ4wURbwAgAQAhAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgADCgcJFgAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8gAAMVAAcJlAy+HwAwAQAVAAYJyAu+HwAwAQALAAYJ8wrIPgDZAAAAAA==.Dreav:BAAALgAECgIJAgAAAA==.Drugar:BAABLgAECn8UAAIKAAYJtwtMqQDxAAAKAAYJtwtMqQDxAAAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEx8IFQDCAAAEAAIJEx8IFQDCAAAuAAQKfxYAAgQACAneHbASALkCAAQACAneHbASALkCAAEuAAUUCQkrABMAJyAA.',
Du='Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgQJCQAAAA==.',
Dy='Dynabol:BAABLgAECn8lAAMQAAkJ6iXVAQBTAwAQAAkJWCXVAQBTAwAfAAgJICUoAQDsAgAAAA==.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAQJCQAJAH4aAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgADCgEJAQAAAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Ev='Everfale:BAAALgAECgIJAgABLgAECggJHQABAAAAAQ==.Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn8yAAIEAAkJIhsBDwA8AgAEAAkJIhsBDwA8AgAAAA==.Faolsabre:BAABLgAECn8iAAIJAAcJ8Qy6cgA1AQAJAAcJ8Qy6cgA1AQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgAOAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn82AAIdAAkJyBJgBwAEAgAdAAkJyBJgBwAEAgAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8dAAIYAAgJAxZfMACXAQAYAAgJAxZfMACXAQAAAA==.',
Fo='Folid:BAAALgAECgEJAQAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJax51CgDOAgACAAkJax51CgDOAgAAAA==.Frostedphyre:BAAALgAECgUJCwAAAA==.',
Fu='Furrywhaco:BAAALgAECggJEgAAAA==.Fuzzyspells:BAAALgAECgIJAgAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMSAAgJLhv2SwD/AQASAAYJsB72SwD/AQARAAYJ7hI5FwASAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.',
Ge='Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn8yAAMiAAgJsAaOIAAyAQAiAAgJsAaOIAAyAQAjAAYJkgOQEQDuAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBAAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQKAAgJsyQ4HwD4AgAKAAgJniQ4HwD4AgAkAAEJnCZFFQBzAAAlAAEJiSQ/DABrAAABLgAECgkJJQAQAOolAA==.',
Gr='Grawler:BAAALgADCgkJJwAAAA==.Greeny:BAAALgAECgQJDAAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgQJBgABLgAECgcJAgABAAAAAA==.Grumpyhunter:BAAALgAECgQJBAABLgAECgkJMQAKAKcfAA==.',
Gu='Gumgumfury:BAAALgAECgMJBwAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haidies:BAAALgAECgUJDgABLgAFFAQJDQAYALkPAA==.Halzlok:BAABLgAECn8VAAIXAAYJNA+hOwDtAAAXAAYJNA+hOwDtAAAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAQJDgAFAHIiAA==.Herøn:BAAALgAECgUJAQAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJKAAYAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAECgcJGAAgAKMmAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgIJAgAAAA==.',
Im='Imysteriöus:BAABLgAECn8oAAMYAAgJBiUKBABQAwAYAAgJBiUKBABQAwAdAAYJHhSJEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAACLgAFFH8KAAICAAQJsRNxFwAcAQACAAQJsRNxFwAcAQAuAAQKfxcAAgIACAlAHJ0bADcCAAIACAlAHJ0bADcCAAAA.Indishaman:BAAALgAECgYJBwAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJKQASADMhAA==.',
Is='Ishamael:BAABLgAECn8mAAIGAAkJVBLcFgDAAQAGAAkJVBLcFgDAAQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8IAAIVAAQJ8xQwAgBOAQAVAAQJ8xQwAgBOAQAuAAQKfywAAhUACQkIIsEAAP4CABUACQkIIsEAAP4CAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jaythirian:BAABLgAECn8YAAMmAAcJrQ6JEACUAQAmAAcJrQ6JEACUAQAEAAQJ1gQVgQC5AAAAAA==.',
Je='Jerg:BAACLgAFFH8NAAIYAAQJuQ+CHgAQAQAYAAQJuQ+CHgAQAQAuAAQKfzIAAxgACAm6HNgWAH8CABgACAm6HNgWAH8CABkABgngFwMoADMBAAAA.Jessup:BAACLgAFFH8LAAMnAAMJkiE3BAATAQAnAAMJMR03BAATAQAiAAIJuxuOHgCrAAAuAAQKfyoAAyIACQmJIn8EAFADACIACQn8IX8EAFADACcABQl9IfoGAIgBAAAA.',
Jh='Jhara:BAABLgAECn8VAAIKAAYJDBCUkAAdAQAKAAYJDBCUkAAdAQAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAABLgAECn8qAAQUAAkJXCOeBgDeAgAUAAkJmSKeBgDeAgAHAAUJtyGGFADnAQAGAAQJPRxkNQBAAQABLgAFFAIJBAABAAAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECgUJCAAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgQJBQAAAA==.Kamekazi:BAAALgADCgYJBgAAAA==.Kariva:BAABLgAECn8pAAIHAAkJOhZzCwBkAgAHAAkJOhZzCwBkAgAAAA==.Katacemic:BAAALgAECgYJEQAAAA==.Katastrophic:BAAALgADCggJEAAAAA==.Katazul:BAABLgAECn8hAAMhAAgJhQqrJgArAQAhAAYJzgqrJgArAQADAAgJNgd2agAqAQAAAA==.Kaulike:BAAALgADCgIJAgAAAA==.',
Ke='Keelanllan:BAABLgAECn8XAAIgAAcJNgemJQDkAAAgAAcJNgemJQDkAAAAAA==.Keilun:BAEALgAECgYJCQAAAA==.Kew:BAAALgAECgQJCgAAAA==.Kewkew:BAAALgADCgcJBwAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECggJHgAMACoRAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJIgALADMRAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Ko='Koggmaw:BAAALgAECgcJDwABLgAFFAQJDQAYALkPAA==.Koral:BAAALgADCgkJEAAAAA==.Korengall:BAAALgADCgkJCQAAAA==.',
Kr='Kralj:BAAALgAECgQJBAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJMgAWAGIiAA==.Kungfuhealya:BAABLgAECn8eAAMcAAgJxwXxOgDqAAAcAAgJxwXxOgDqAAAbAAEJwQEDhwAaAAAAAA==.Kuraj:BAAALgAECgEJAQAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAASAPkbAA==.Larrydale:BAABLgAECn8ZAAMPAAgJTxwTGQByAgAPAAgJTxwTGQByAgAOAAEJqQMDMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAASAPkbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn8eAAMWAAYJJwtCJgDLAAAWAAYJ7QpCJgDLAAAJAAQJIQVv1wB+AAAAAA==.',
Le='Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgMJBAAAAA==.Leondis:BAABLgAECn8pAAIPAAkJih80CAANAwAPAAkJih80CAANAwAAAA==.Leviosa:BAAALgAECgMJAgAAAA==.Lexipriest:BAACLgAFFH8UAAMHAAUJzBMqBwB5AQAHAAUJYBMqBwB5AQAUAAMJiQtgEADHAAAuAAQKf0IAAwcACQmYIKcCAEADAAcACQmYIKcCAEADABQACAkzHYcIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.Lilpp:BAAALgAECgIJAgABLgAECgYJCgABAAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgYJFAAFACQTAA==.Lockmonster:BAAALgAECgIJAwAAAA==.Locksteady:BAAALgAECgUJBgAAAA==.Lookalock:BAAALgAECgQJBAAAAA==.Lorp:BAAALgAECgYJBwAAAA==.Lotglock:BAAALgAECgkJCgAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAIQAAgJeB2EKQBcAgAQAAgJeB2EKQBcAgAAAA==.Lumosmaxiima:BAAALgAECgcJCgAAAA==.Lunadesangre:BAAALgAECgEJAQAAAA==.Lunarette:BAAALgAECgMJBAAAAA==.',
Ly='Lydax:BAABLgAECn8UAAISAAcJ+RtqVwDcAQASAAcJ+RtqVwDcAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAAALgAECgYJCwAAAA==.Madkingzack:BAABLgAECn8VAAMEAAkJbx5nCACYAgAEAAkJbx5nCACYAgAmAAEJywaHVQApAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAAALgAECgUJDgAAAA==.Mallikii:BAABLgAECn8dAAMYAAkJ0hu9MADoAQAYAAkJ0hu9MADoAQAZAAQJrSMBOABZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8dAAIKAAkJyg0jfABCAQAKAAkJyg0jfABCAQAAAA==.Marigosa:BAAALgAECgcJCwAAAA==.Marnolkas:BAAALgADCggJCAABLgAECgMJAwABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAABLgAECn8dAAMSAAgJjhhkMwDrAQASAAgJjhhkMwDrAQACAAUJrSC8HADRAQAAAA==.Mattdemon:BAAALgAECgcJAgAAAA==.Maudib:BAABLgAECn8VAAIoAAgJSRVWFgAmAQAoAAgJSRVWFgAmAQAAAA==.Mawile:BAAALgAECgQJBAAAAA==.',
Me='Meautiful:BAAALgADCgQJBAAAAA==.Medusa:BAAALgAECgQJCQAAAA==.Meesha:BAAALgAECgIJAgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAAALgAECgQJCwAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQhAAgJBA97HABqAQAhAAcJYw57HABqAQADAAUJ/wrlxQDNAAAaAAEJ2hVmLgBBAAAAAA==.Merkxi:BAABLgAECn8kAAIOAAgJWyF3CABcAgAOAAgJWyF3CABcAgAAAA==.Messe:BAABLgAECn84AAInAAkJvB1zAQCiAgAnAAkJvB1zAQCiAgAAAA==.Methious:BAAALgAECggJEwAAAA==.',
Mi='Minigoober:BAAALgAECgQJBAAAAA==.',
Mo='Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8VAAIIAAUJuAjFIAD3AAAIAAUJuAjFIAD3AAAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECgUJCQAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonsguard:BAAALgADCgcJCgABLgAECgMJBQABAAAAAA==.Moovit:BAAALgAECgMJCAAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgIJAQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.',
My='Myströnghand:BAAALgAECgcJBwAAAA==.',
Na='Nagumo:BAABLgAECn8fAAMhAAgJbAPyOQDMAAADAAgJNwOmiwDlAAAhAAYJYAPyOQDMAAAAAA==.Nala:BAABLgAECn8WAAMZAAgJqhGJJwA2AQAZAAcJvw6JJwA2AQAYAAQJWBdtbgAJAQABLgAFFAQJDQAYALkPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAABLgAECn8uAAMMAAgJGxSbEwBEAQAMAAcJZRKbEwBEAQALAAcJGxdRKQBDAQAAAA==.',
Ne='Nekoya:BAAALgADCgMJAwAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8KAAIQAAQJUB2+GQBlAQAQAAQJUB2+GQBlAQAuAAQKfykAAxAACQmiJfMAANgDABAACQmiJfMAANgDAB8AAQk3FMgjADkAAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgADCgkJCQAAAA==.Nivan:BAAALgAECgEJAQAAAA==.Niço:BAABLgAECn8UAAIPAAkJzxypHwBHAgAPAAkJzxypHwBHAgAAAA==.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIYAAkJJhs5HgBNAgAYAAkJJhs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAAALgAECggJHQAAAQ==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
['Nï']='Nï:BAAALgADCgUJBQAAAA==.',
Oa='Oakmoss:BAAALgADCgcJBgAAAA==.',
Of='Offlyne:BAAALgAECgEJAQAAAA==.',
Oh='Ohntakae:BAAALgAECgUJAgAAAA==.',
Ok='Oksana:BAAALgAECgcJCAAAAA==.',
Ol='Ollamh:BAAALgAECgEJAQAAAA==.',
Om='Ombravuota:BAAALgAECgcJEQAAAA==.',
Oo='Oom:BAAALgAECgIJAgAAAA==.',
Or='Oralian:BAABLgAECn8hAAMhAAkJwSMrCwANAgAhAAUJrCMrCwANAgADAAUJhCMLRQD8AQAAAA==.Orcleave:BAAALgAFFAEJAQAAAA==.Orflap:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Ov='Ovee:BAAALgADCgcJBgAAAA==.',
Pa='Paboo:BAAALgAECgUJCAAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8iAAMKAAgJlxj6PADkAQAKAAgJlxj6PADkAQAlAAEJZQnCDQAvAAAAAA==.Perturabo:BAAALgAECgEJAgAAAA==.',
Ph='Phoenyx:BAABLgAECn8VAAMhAAYJpAkBFQDDAAAhAAYJpAkBFQDDAAADAAUJjQHs0QBfAAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMPAAcJDx2zJAAqAgAPAAcJDx2zJAAqAgAeAAMJdQuDawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJHQAKAMoNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgAECgIJAgAAAA==.',
Qu='Quorra:BAAALgAECgEJAQAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8qAAIEAAkJcB48CgB6AgAEAAkJcB48CgB6AgAAAA==.Rakagar:BAABLgAECn8xAAISAAkJOh5LEQCiAgASAAkJOh5LEQCiAgAAAA==.Ranko:BAAALgAECgkJAQAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8XAAIcAAUJwxzhCQC9AQAcAAUJwxzhCQC9AQAuAAQKfysAAhwACQkbHV0OAHECABwACQkbHV0OAHECAAAA.Reyz:BAABLgAECn8ZAAIcAAgJGxWGIQCnAQAcAAgJGxWGIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQAAAA==.',
Rh='Rhaegos:BAAALgAECgMJAwAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8dAAIEAAYJTCEYHwCnAQAEAAYJTCEYHwCnAQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
Ry='Ryvive:BAAALgADCggJCAAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAFFAQJCAAPAE0eAA==.',
['Rë']='Rëz:BAAALgADCgYJBgAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8xAAMgAAkJ2CJ+AgD7AgAgAAkJ2CJ+AgD7AgAQAAYJTBkySgBYAQABLgAECgkJNAAWACMhAA==.Scripts:BAAALgAECgYJEQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJHQAKAMoNAA==.',
Sh='Shale:BAABLgAECn8+AAMMAAkJkRmABQB3AgAMAAkJkRmABQB3AgALAAcJAwmoRQDGAAAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAABLgAECn8ZAAMXAAcJChzvHACkAQAXAAcJChzvHACkAQApAAQJ5gxRdAC/AAAAAA==.Sharaiya:BAABLgAECn8jAAIYAAgJnASZZwC5AAAYAAgJnASZZwC5AAAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAABLgAECn8VAAMPAAYJ2R76OgCeAQAPAAYJ2R76OgCeAQAeAAEJJRGYhgA2AAAAAA==.Sioux:BAAALgAECgQJBgAAAA==.',
Sk='Skippybmm:BAAALgAECgQJBwABLgAECgYJFAAFACQTAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgEJAQABLgAECgkJOAAnALwdAA==.',
Sm='Smexyshâmmy:BAAALgAECgQJBQAAAA==.',
So='Soferus:BAAALgADCggJCAABLgAECgMJAwABAAAAAA==.Solaire:BAACLgAFFH8LAAIRAAQJ7BkbAwAsAQARAAQJ7BkbAwAsAQAuAAQKfywAAhEACQn9ILkBADMDABEACQn9ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJth5qCwDDAgADAAkJth5qCwDDAgABLgAFFAYJFQAQAOQaAA==.Soulful:BAAALgAECgYJBgAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAYALkPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAABLgAECn8UAAIFAAYJJBOzHQD3AAAFAAYJJBOzHQD3AAAAAA==.Spot:BAAALgAECgUJBgABLgAECgkJHQAKAMoNAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgQJBAAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn8pAAMOAAgJSRvYDAAVAgAOAAgJSRvYDAAVAgAeAAcJKBV9EAAKAQAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECggJKAAfAJoNAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8bAAMhAAcJ/xa9BwCGAQAhAAcJ/xa9BwCGAQADAAEJlQE4GQEaAAAAAA==.Tankinit:BAAALgAECgMJCgAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgAECgEJAQAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIRAAMJswgGBACcAAARAAMJswgGBACcAAAuAAQKfyUAAhEACAkJHX0GAIACABEACAkJHX0GAIACAAAA.Tenzink:BAABLgAECn8mAAIcAAkJGRxnCQCjAgAcAAkJGRxnCQCjAgAAAA==.',
Th='Thalon:BAAALgAECgMJAwABLgAECggJNwAJACQkAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgADCgIJAgAAAA==.Thedkfreak:BAAALgAFFAEJAgABLgAECgcJFAASAAgeAA==.Thedru:BAABLgAECn8tAAIYAAgJdAx4QgA+AQAYAAgJdAx4QgA+AQAAAA==.Thrastus:BAAALgADCgIJAgAAAA==.Thrus:BAAALgAECgQJBAABLgAECgkJOAAnALwdAA==.Théworld:BAAALgAECgMJBQAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgEJAQABLgAECggJIgAKAJcYAA==.',
Tl='Tlnks:BAAALgADCgQJBwAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAABLgAECn8UAAIOAAkJuhfuBwBmAgAOAAkJuhfuBwBmAgAAAA==.',
Tr='Traler:BAAALgAECgEJAQABLgAECgkJNgAdAMgSAA==.Tralzitashan:BAABLgAECn8vAAMkAAkJyA7OAgDUAQAkAAkJyA7OAgDUAQAKAAQJzAMXIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAIKAAcJWhq0ZQAMAgAKAAcJWhq0ZQAMAgAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgADCgMJAwAAAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgADCgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAAALgAECgUJCwAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAACLgAFFH8FAAISAAMJzxnzMAAVAQASAAMJzxnzMAAVAQAuAAQKfxcAAhIACQnkJDoDAEMDABIACQnkJDoDAEMDAAAA.Unglausp:BAACLgAFFH8FAAIGAAMJFhaWFQD6AAAGAAMJFhaWFQD6AAAuAAQKfyIAAgYACAn9HtINAKYCAAYACAn9HtINAKYCAAEuAAUUAwkFABIAzxkA.',
Uz='Uzington:BAACLgAFFH8VAAIFAAUJDBFSDQAFAQAFAAUJDBFSDQAFAQAuAAQKfyYAAgUACQmyHPQIAI8CAAUACQmyHPQIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgEJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAAALgAECgUJCQAAAA==.Valorien:BAABLgAECn8ZAAISAAgJGhnxOADWAQASAAgJGhnxOADWAQAAAA==.Valzlok:BAAALgAECgMJAwAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgAOAC0jAA==.Velinieron:BAABLgAECn8eAAIOAAkJLSPOBgB8AgAOAAkJLSPOBgB8AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgAOAC0jAA==.Vellash:BAABLgAECn8XAAIgAAYJEgrIJQDjAAAgAAYJEgrIJQDjAAAAAA==.Vendétta:BAABLgAECn8iAAIPAAgJHBAmVABMAQAPAAgJHBAmVABMAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8dAAIKAAgJIAoxbQBhAQAKAAgJIAoxbQBhAQAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgADCggJCQAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8bAAIPAAcJWQ3XVABKAQAPAAcJWQ3XVABKAQAAAA==.',
Vy='Vynlandis:BAABLgAECn8xAAIJAAkJqxisIgA1AgAJAAkJqxisIgA1AgAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAYALkPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAAALgAECgYJCAAAAA==.Weenbean:BAAALgAECgEJAgAAAA==.Werebray:BAAALgAECgcJEAABLgAECgcJFwAOAEIaAA==.',
Wh='Whaco:BAABLgAECn8fAAIRAAgJmBssCAD9AQARAAgJmBssCAD9AQAAAA==.Whatisaggro:BAABLgAECn8YAAIEAAYJbR7jNADWAQAEAAYJbR7jNADWAQAAAA==.Whispertree:BAABLgAECn8hAAIZAAgJsSEuCgBmAgAZAAgJsSEuCgBmAgAAAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECgcJIAAVAJQMAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8JAAIJAAQJfhoIKABiAQAJAAQJfhoIKABiAQAuAAQKfyUAAgkACQkXIWINAC8DAAkACQkXIWINAC8DAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8nAAQWAAcJNxnqFADDAQAWAAYJmx3qFADDAQAJAAcJtwZesADEAAANAAIJcxhNEgBsAAAAAA==.Wixypoo:BAACLgAFFH8HAAIIAAMJjxE0KADSAAAIAAMJjxE0KADSAAAuAAQKfykAAwgACQm+GFcQAP0BAAgACQm+GFcQAP0BABwAAQnpAfh9ABsAAAAA.',
Wo='Wockyslush:BAABLgAECn8kAAIiAAkJfSTpCAADAwAiAAkJfSTpCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMLAAkJWRgQEAAfAgALAAkJWRgQEAAfAgAVAAYJwAMuKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8XAAIpAAcJ9x70HwAfAgApAAcJ9x70HwAfAgAAAA==.',
Wy='Wyyn:BAABLgAECn8vAAIKAAgJwQrccABZAQAKAAgJwQrccABZAQAAAA==.',
Xa='Xanboi:BAABLgAECn8yAAMOAAkJ7CERAgAAAwAOAAkJ7CERAgAAAwAPAAIJ6iK1iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAACLgAFFH8KAAIEAAQJfR44CAB3AQAEAAQJfR44CAB3AQAuAAQKfyUAAgQACAmwIBINAO0CAAQACAmwIBINAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Ys='Ysar:BAABLgAECn8WAAILAAgJ0g1rJwBQAQALAAgJ0g1rJwBQAQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMVAAcJ6RqJDgDyAQAVAAYJkB+JDgDyAQALAAYJGxdJIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECgYJIwARAIQWAA==.',
Ze='Zeebu:BAABLgAECn8jAAIOAAgJtwmkGgB+AQAOAAgJtwmkGgB+AQAAAA==.Zenboi:BAABLgAECn8cAAIQAAgJ1RUcQwDnAQAQAAgJ1RUcQwDnAQAAAA==.Zephryyn:BAAALgAECgcJDQAAAA==.',
Zh='Zhilan:BAAALgAECgQJBQAAAA==.',
Zi='Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAQJCwAnAJIhAA==.Zophos:BAAALgAECggJDwABLgAECggJFgAhAAQPAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgEJAgAAAA==.Zuzuk:BAAALgAECggJEAAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAAALgAECgcJCAAAAA==.',
['Zú']='Zúz:BAAALgAECgcJCQAAAA==.',
['Áß']='Áßomination:BAAALgAECgIJAwAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAABLgAECn8nAAIpAAgJbwxKSAApAQApAAgJbwxKSAApAQAAAA==.',
['Ði']='Ðittø:BAAALgAECggJEAABLgAFFAMJBQAWAOELAA==.',
['Öd']='Ödorodun:BAAALgAECgIJAwAAAA==.',
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
