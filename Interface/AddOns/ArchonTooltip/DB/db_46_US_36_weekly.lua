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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Preservation','DeathKnight-Frost','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Shaman-Enhancement','Priest-Discipline','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Balance','Warlock-Affliction','Druid-Feral','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','Rogue-Outlaw','Druid-Guardian','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Mage-Fire','Warrior-Arms','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aalduin:BAAALgAECgMJBAABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCQAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgAECgQJBAAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAYJEgACAKIZAQ==.',
Af='Affli:BAACLgAFFH8WAAIDAAUJlBnlOwBGAQADAAUJlBnlOwBGAQAuAAQKfysAAgMACQkUIEIbALECAAMACQkUIEIbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8nAAIFAAgJwRU0FQCTAQAFAAgJwRU0FQCTAQAAAA==.Aiupriesty:BAABLgAECn8mAAMGAAgJ8gqALwBaAQAGAAgJ8gqALwBaAQAHAAYJcBNkRwC5AAABLgAECggJJwAFAMEVAA==.',
Ak='Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAAALgAECgYJEQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAABLgAECn8ZAAIIAAYJ0gxSswAGAQAIAAYJ0gxSswAGAQAAAA==.Aleinara:BAABLgAECn8bAAIJAAkJzwzHagCOAQAJAAkJzwzHagCOAQAAAA==.Aleridin:BAABLgAECn8rAAIKAAkJHiXbAQBFAwAKAAkJHiXbAQBFAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAACLgAFFH8OAAILAAUJuB13FACwAQALAAUJuB13FACwAQAuAAQKfxwABAsACQlwGxANALoCAAsACQlwGxANALoCAAwABwkoGAoeALABAAoAAQlAIaltAGIAAAAA.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Andsey:BAAALgAECgQJCAAAAA==.Annore:BAABLgAECn8dAAIIAAkJdxKKTQDTAQAIAAkJdxKKTQDTAQAAAA==.Antihero:BAABLgAECn8hAAIIAAkJeiN5DgAnAwAIAAkJeiN5DgAnAwAAAA==.',
Ap='Aphelse:BAAALgADCgMJAwABLgAFFAUJDgALALgdAA==.',
Aq='Aquiell:BAABLgAECn8gAAINAAcJiBK7iQBeAQANAAcJiBK7iQBeAQAAAA==.Aqular:BAABLgAECn8VAAIOAAcJNBN6XQCBAQAOAAcJNBN6XQCBAQAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8eAAIFAAUJbyTUCACKAQAFAAUJbyTUCACKAQAuAAQKf0UAAwUACQkkJaABADsDAAUACQkkJaABADsDAAQABQnNEMJcANQAAAAA.Arkenomu:BAABLgAECn8iAAMPAAgJNRFsMABrAQAPAAgJNRFsMABrAQAQAAcJagzmGAA9AQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8tAAMRAAgJIwo7FAAsAQARAAgJIwo7FAAsAQAIAAYJsAHP7AClAAAAAA==.Asclepius:BAABLgAECn8jAAIQAAkJnQ/aDgDWAQAQAAkJnQ/aDgDWAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Aslo:BAAALgADCgEJAQAAAA==.Asmira:BAAALgADCgYJCQAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn80AAMSAAgJEiEXEAArAgASAAcJWSEXEAArAgAOAAYJ0xujlgAFAQAAAA==.',
At='Atsunvhi:BAAALgAECgUJEwAAAA==.',
Av='Avadakedevra:BAABLgAECn8jAAMSAAcJKBN3JAB0AQASAAcJKBN3JAB0AQAOAAEJKwpFzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azareth:BAAALgADCgkJCQAAAA==.Azreal:BAAALgAECgcJDQAAAA==.Azumok:BAAALgAECgQJBAAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bairn:BAAALgADCggJCAAAAA==.Bakedbean:BAAALgAECgYJCQABLgAFFAEJBQATABQkAA==.Barackobooma:BAAALgAECgIJAgAAAA==.Bazerker:BAAALgAECgQJBQAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8lAAINAAgJnA/ydACJAQANAAgJnA/ydACJAQAAAA==.',
Be='Beastcode:BAAALgAECggJCAAAAA==.Belgaria:BAABLgAECn8oAAMUAAcJ9hQZFwBbAQAUAAcJ9hQZFwBbAQAJAAcJgg1ilQBSAQAAAA==.Berryknight:BAACLgAFFH8FAAIIAAIJ3hOEtwCcAAAIAAIJ3hOEtwCcAAAuAAQKfy4AAwgACQlxG4IuADwCAAgACQlxG4IuADwCABEAAgnZD7srAGAAAAAA.Berryqt:BAAALgAECgQJCQAAAA==.Bewlzeye:BAAALgAECgUJBwAAAA==.',
Bi='Bigjonmachne:BAACLgAFFH8LAAIIAAUJthqmRwBSAQAIAAUJthqmRwBSAQAuAAQKfxgAAggACAlAG4EsAEUCAAgACAlAG4EsAEUCAAAA.Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8iAAIHAAYJ8CMZAgBmAgAHAAYJ8CMZAgBmAgAuAAQKfx8AAgcACQnOJIkDACIDAAcACQnOJIkDACIDAAAA.Blessmoo:BAAALgAFFAEJAQAAAA==.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodsail:BAAALgAECgUJBQAAAA==.Bloodydk:BAAALgAECgEJAQAAAA==.Bluestripee:BAAALgAECgEJAQAAAA==.Bluezugzug:BAAALgAECgMJBQAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8yAAIVAAkJ2helCAAqAgAVAAkJ2helCAAqAgAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn8zAAMGAAkJ9yAuCADHAgAGAAkJ9yAuCADHAgAWAAEJaBblVgA0AAAAAA==.Bonnieanne:BAAALgADCgEJAQAAAA==.Bonsaichi:BAAALgAECgkJEQAAAA==.Bownyxia:BAACLgAFFH8JAAIPAAMJQBaVEQD1AAAPAAMJQBaVEQD1AAAuAAQKfzYAAw8ACQnIIjgFAAgDAA8ACQnIIjgFAAgDABcABAlHDvspAM4AAAEuAAUUCAkqAAgA4BwA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAgJKgAIAOAcAA==.Bowties:BAACLgAFFH8qAAMIAAgJ4Bx4BQCoAgAIAAgJ4Bx4BQCoAgAYAAEJAABQUgAAAAAuAAQKf0MAAwgACQmUJsgBAIADAAgACQmUJsgBAIADABgACQk3GHkKAHECAAAA.',
Br='Braxchud:BAABLgAECn8/AAIZAAkJJhyFDgB6AgAZAAkJJhyFDgB6AgAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAINAAkJixvnLQBbAgANAAkJixvnLQBbAgAAAA==.Brewnwings:BAAALgAECgUJCgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8RAAITAAQJGROQFAAuAQATAAQJGROQFAAuAQAuAAQKfx0AAhMACQm9HZQXAH8CABMACQm9HZQXAH8CAAEuAAUUCAkqAAgA4BwA.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgADCgkJDwABLgAECggJLQAEAHwiAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burial:BAAALgADCgcJCAAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgQJEgAAAA==.',
Ca='Caarrl:BAAALgAECgQJCAAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBQAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgAECgYJCAAAAA==.Calistra:BAAALgADCgYJBgAAAA==.Calistriaa:BAAALgADCgQJBAAAAA==.Caplock:BAAALgAECgQJBQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAAALgAECgYJCQAAAA==.Cartime:BAAALgAECgMJBAAAAA==.Cayllia:BAABLgAECn8jAAMaAAkJDCSOBABFAwAaAAkJDCSOBABFAwAbAAgJDCKPFAAiAgAAAA==.',
Ce='Celaris:BAAALgAECgUJDQAAAA==.',
Ch='Chaolang:BAAALgAFFAEJAQAAAA==.Chataykay:BAAALgAECgcJDgAAAA==.Cherrypepsï:BAABLgAECn8cAAMHAAkJOQ/aKwCYAQAHAAkJOQ/aKwCYAQAWAAUJdgbwOADgAAAAAA==.Chinlen:BAAALgAECgEJAQAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chivies:BAAALgAECggJDQABLgAECgkJMgAJADMhAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAABLgAECn8kAAIcAAkJKxipBAA9AgAcAAkJKxipBAA9AgAAAA==.Citrus:BAABLgAECn85AAISAAkJtBUZEwALAgASAAkJtBUZEwALAgAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBwAAAA==.Cliqmonk:BAAALgAECgcJCAAAAA==.',
Cn='Cn:BAABLgAECn8yAAIJAAkJMyHeEgDJAgAJAAkJMyHeEgDJAgAAAA==.',
Co='Cocoabutter:BAABLgAECn8cAAINAAYJmBFErgAgAQANAAYJmBFErgAgAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAANAIsbAA==.Codeman:BAABLgAECn88AAMYAAkJ7CKnAwD+AgAYAAkJ7CKnAwD+AgAIAAEJEwveXAE1AAAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJPAAYAOwiAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8YAAMLAAYJUhqRGwBoAQALAAUJixiRGwBoAQAMAAUJsBXCEwAYAQAuAAQKf2MAAwsACQl2I1QDAHwDAAsACQl2I1QDAHwDAAwABgloIdMZANYBAAAA.Contemplate:BAAALgAECgMJCAABLgAFFAIJBAABAAAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECgkJGwABLgAFFAEJAQABAAAAAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.Crúsh:BAAALgAECgEJAQAAAA==.',
Ct='Ctk:BAAALgAECgEJAQAAAA==.',
Cu='Culluh:BAAALgAECgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAABLgAECn8cAAIdAAYJFhyQFgBOAQAdAAYJFhyQFgBOAQAAAA==.',
Cz='Czin:BAABLgAECn8tAAMEAAgJfCKRCADPAgAEAAgJfCKRCADPAgAFAAEJkQnBSwAlAAAAAA==.',
['Cï']='Cïel:BAAALgAECgUJBQAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgYJEgAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJCQAAAA==.Deathverses:BAACLgAFFH84AAIeAAgJsCYzAAAOAwAeAAgJsCYzAAAOAwAuAAQKfy4AAh4ACQnjJikCAJYDAB4ACQnjJikCAJYDAAAA.Deerslayer:BAAALgAECgcJEAAAAA==.Deezknights:BAAALgAECgUJCAABLgAECgYJDgABAAAAAA==.Delter:BAABLgAECn8UAAIeAAgJuxyFHwAqAgAeAAgJuxyFHwAqAgABLgAECggJFAAeALscAA==.Deltritus:BAACLgAFFH8aAAINAAcJ8RiPGgAEAgANAAcJ8RiPGgAEAgAuAAQKfzQAAg0ACQnnIy4IADcDAA0ACQnnIy4IADcDAAEuAAQKCAkUAB4AuxwA.Demaedra:BAAALgAECgMJAwAAAA==.Demoan:BAABLgAECn86AAIfAAkJKSNqAQANAwAfAAkJKSNqAQANAwAAAA==.Demonbiscuit:BAACLgAFFH8GAAIgAAQJ6x1sBgCHAQAgAAQJ6x1sBgCHAQAuAAQKfxkAAiAACAmlJioEAP4CACAACAmlJioEAP4CAAAA.Derpydawg:BAAALgAECgEJAQABLgAFFAQJEQAIAHcfAA==.Dethh:BAAALgADCgMJAwAAAA==.Deviancy:BAABLgAECn8XAAMCAAkJdxlfEQCAAgACAAkJdxlfEQCAAgAJAAEJpAUwqAEkAAAAAA==.',
Dh='Dhruven:BAAALgADCggJCAAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAABLgAECn8UAAIPAAYJ0A9ZVADSAAAPAAYJ0A9ZVADSAAAAAA==.Diese:BAAALgAECgYJCQAAAA==.Dikslapp:BAABLgAECn83AAIgAAkJRiLrAwAFAwAgAAkJRiLrAwAFAwAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Dipperton:BAAALgAECgEJAQABLgAECgcJFAAXAOkaAA==.Discrespect:BAACLgAFFH8LAAMWAAUJ4xGCIwAPAQAWAAQJYBSCIwAPAQAHAAEJ8QfoMABBAAAuAAQKfx8ABBYACAlYGnERAC0CABYACAlYGnERAC0CAAcABAkiCMhcAMAAAAYAAQkfAxuOACIAAAAA.Distinct:BAAALgAECgkJCQABLgAECgkJOgAfACkjAA==.Distress:BAAALgAFFAIJBAAAAA==.Ditto:BAACLgAFFH8KAAIYAAMJ/xCZJgCqAAAYAAMJ/xCZJgCqAAAuAAQKfzsABBgACAmpHOsMAEECABgACAmpHOsMAEECAAgABwkpC4yfACMBABEAAwlBDt4PAJ4AAAAA.',
Dl='Dlitinaro:BAABLgAECn80AAMIAAkJIyFuIAB/AgAIAAkJBx9uIAB/AgAYAAkJcx4ECQB8AgAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMQAAMJoxd9DQAHAQAQAAMJoxd9DQAHAQAPAAEJHAnrXgA8AAAuAAQKfxkAAxAACAlwJLYDACADABAACAlwJLYDACADAA8AAwlpGjBOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Dollette:BAAALgAECggJBQAAAA==.Donoph:BAABLgAECn88AAMCAAkJ/yNvAgB9AwACAAkJ/yNvAgB9AwAJAAEJQwxGjAEtAAAAAA==.Doomar:BAABLgAECn80AAMDAAkJjSEFFwCUAgADAAkJNCEFFwCUAgAhAAYJfR+rBwDKAQAAAA==.Doomsamdi:BAAALgAECgcJCAABLgAECgkJNAADAI0hAA==.Doomseph:BAAALgAECgEJAQABLgAECgkJNAADAI0hAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.Dotzilla:BAAALgAECgQJBAAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8fAAMDAAkJ6AkybgBZAQADAAkJMAkybgBZAQAhAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgAECgMJBQAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8hAAMXAAgJSQu+HwAwAQAXAAcJZwq+HwAwAQAPAAYJ9Ao1TgDoAAAAAA==.Dreav:BAAALgAECgIJAgAAAA==.Drugar:BAABLgAECn8pAAINAAgJ/Q6KdgCFAQANAAgJ/Q6KdgCFAQAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEx8IFQDCAAAEAAIJEx8IFQDCAAAuAAQKfxYAAgQACAneHbASALkCAAQACAneHbASALkCAAEuAAUUCQk4ABUAySUA.',
Du='Duloc:BAAALgAECgUJCAAAAA==.Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgUJEwAAAA==.',
Dy='Dynabol:BAACLgAFFH8FAAITAAEJFCQWgwBpAAATAAEJFCQWgwBpAAAuAAQKfzUAAxMACQkOJjcCAGADABMACQl8JTcCAGADAB8ACAkhJUMCANcCAAAA.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAQJEQAIAHcfAA==.',
Eb='Eborsisk:BAAALgADCgYJBgAAAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgAECgQJBQAAAA==.',
Em='Eminnazen:BAAALgADCgkJDgAAAA==.',
En='Endurall:BAAALgAECggJCAABLgAECgkJQAAiAAEeAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Ev='Eveleigh:BAAALgAECgEJAQAAAA==.Everfale:BAAALgAECgIJAwABLgAFFAEJAQABAAAAAQ==.Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn8yAAIEAAkJIhvFGAAhAgAEAAkJIhvFGAAhAgAAAA==.Faolsabre:BAABLgAECn8nAAIIAAgJpQxOewBkAQAIAAgJpQxOewBkAQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgASAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn9FAAQdAAkJpxRqCgAKAgAdAAkJlhRqCgAKAgAjAAYJVxEBKQD+AAAaAAcJHQZacQDXAAAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8vAAIaAAkJdBmiFwCAAgAaAAkJdBmiFwCAAgAAAA==.',
Fo='Folid:BAAALgAECgEJAgAAAA==.Forne:BAAALgAFFAEJAQAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB51CgDOAgACAAkJbB51CgDOAgAAAA==.Frostedphyre:BAAALgAECgkJDQAAAA==.',
Fu='Furrywhaco:BAABLgAECn8UAAIjAAkJ+RrnBwBlAgAjAAkJ+RrnBwBlAgAAAA==.Fuzzyspells:BAAALgAECgUJCQAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMJAAgJLxv2SwD/AQAJAAYJsB72SwD/AQAUAAYJ7xKyHwAKAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.',
Ge='Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn86AAMkAAgJMgmcJwBJAQAkAAgJAQicJwBJAQAlAAYJuwWQEQDuAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBgAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQNAAgJsyQ4HwD4AgANAAgJniQ4HwD4AgAmAAEJnCZFFQBzAAAnAAEJiSQ/DABrAAABLgAFFAEJBQATABQkAA==.',
Gr='Gravez:BAAALgAECgYJCAABLgAFFAEJAQABAAAAAA==.Grawler:BAAALgAECgcJCwAAAA==.Greeny:BAAALgAFFAEJAQAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgQJCgABLgAECgcJCQABAAAAAA==.Grumpyhunter:BAAALgAECgcJEAABLgAECgkJNQANAOsfAA==.',
Gu='Gumgumfury:BAAALgAECgQJDwAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haidies:BAAALgAECgUJDgABLgAFFAQJDQAaALkPAA==.Halzlok:BAABLgAECn8cAAIZAAcJ6Q+iQQAdAQAZAAcJ6Q+iQQAdAQAAAA==.Hammergold:BAAALgAECgEJAQAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Harandy:BAAALgAECgIJAgAAAA==.Harvester:BAAALgADCgEJAQAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAUJHgAFAG8kAA==.Herøn:BAAALgAECgUJAQAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJKAAaAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAFFAQJBgAgAOsdAA==.Hondacivic:BAAALgAECgEJAQABLgAECgkJJAAkAH0kAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ia='Iandis:BAAALgADCgYJCwABLgAECgcJHAAFAHwSAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgIJAgAAAA==.',
Ik='Ikayhaimahn:BAAALgAFFAMJAwABLgAFFAMJBgAPAPQLAA==.',
Im='Imysteriöus:BAABLgAECn8oAAMaAAgJBiVVBgBLAwAaAAgJBiVVBgBLAwAdAAYJHhSJEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAACLgAFFH8UAAICAAUJQx3iEQCVAQACAAUJQx3iEQCVAQAuAAQKfxcAAgIACAlAHJ0bADcCAAIACAlAHJ0bADcCAAAA.Indishaman:BAAALgAECgYJCQAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJMgAJADMhAA==.',
Is='Ishamael:BAABLgAECn80AAIGAAkJUxJlHgDKAQAGAAkJUxJlHgDKAQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8LAAIXAAQJBhgLAwBFAQAXAAQJBhgLAwBFAQAuAAQKfywAAhcACQkHIlkBAOMCABcACQkHIlkBAOMCAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jarnroz:BAAALgAECgQJBAABLgAECgUJCgABAAAAAA==.Jaythirian:BAABLgAECn8YAAMoAAcJrQ6JEACUAQAoAAcJrQ6JEACUAQAEAAQJ1gQVgQC5AAAAAA==.',
Je='Jerg:BAACLgAFFH8NAAIaAAQJuQ9ZLgDyAAAaAAQJuQ9ZLgDyAAAuAAQKfzkAAxoACQlUHtgWAH8CABoACAmfHdgWAH8CABsABwk3FnArAGwBAAAA.Jessup:BAACLgAFFH8NAAMiAAQJkiGdBwD4AAAiAAQJHh+dBwD4AAAkAAIJuxt7LgCZAAAuAAQKfyoAAyQACQmKIn8EAFADACQACQn8IX8EAFADACIABQl9IasJAIMBAAAA.',
Jh='Jhara:BAABLgAECn8dAAINAAcJeBArkABSAQANAAcJeBArkABSAQAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAABLgAECn8sAAQWAAkJECSeBgDeAgAWAAkJTSOeBgDeAgAHAAUJtyGUHADUAQAGAAUJ0BxkNQBAAQABLgAFFAUJDgALALgdAA==.Junnai:BAAALgADCgcJBwAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECgcJDQAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kagamie:BAAALgADCgQJBAAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgUJBgAAAA==.Kamekazi:BAAALgAECgMJAwAAAA==.Kariva:BAABLgAECn85AAIHAAkJ6xhcDgByAgAHAAkJ6xhcDgByAgAAAA==.Katacemic:BAABLgAECn8mAAIYAAgJiBb6EwDIAQAYAAgJiBb6EwDIAQABLgAECgkJIgAhAF8KAA==.Katastrophic:BAAALgADCggJEAABLgAECgkJIgAhAF8KAA==.Katazul:BAABLgAECn8iAAMhAAkJXwqrJgArAQADAAkJewesagBiAQAhAAYJzgqrJgArAQAAAA==.Kaulike:BAAALgADCgIJAgAAAA==.Kayssa:BAAALgAECgUJBQAAAA==.',
Ke='Keelanllan:BAABLgAECn8bAAIgAAgJcgj/LAAHAQAgAAgJcgj/LAAHAQAAAA==.Keilun:BAEALgAECgcJCwAAAA==.Kertzz:BAAALgADCgcJCAABLgAECgMJAwABAAAAAA==.Kew:BAABLgAECn8YAAINAAcJMxcgXADEAQANAAcJMxcgXADEAQAAAA==.Kewkew:BAAALgADCgcJDAAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECgkJIwAQAJ0PAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJIgAPADURAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Kn='Kneecromance:BAAALgAFFAEJAQAAAA==.Knightxl:BAAALgAECgYJBgAAAA==.',
Ko='Koggmaw:BAAALgAECgcJEAABLgAFFAQJDQAaALkPAA==.Kokuten:BAAALgAECgEJAQABLgAECggJHwApAL0dAA==.Koral:BAAALgAECgYJBgAAAA==.',
Kr='Kralj:BAAALgAECgUJCAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJPAAYAOwiAA==.Kungfuhealya:BAABLgAECn8hAAMLAAgJcgioUgAIAQALAAgJcgioUgAIAQAMAAEJwQH2swAYAAAAAA==.Kuraj:BAAALgAECgEJAQAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAAJAPkbAA==.Larrydale:BAABLgAECn8fAAMOAAgJTxwTGQByAgAOAAgJTxwTGQByAgASAAEJqQMDMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAAJAPkbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn8pAAMYAAgJtQ6yIgAyAQAYAAgJPA2yIgAyAQAIAAQJ7Q2G0gDbAAAAAA==.',
Le='Lea:BAAALgAECgIJAgABLgAECgkJKQANAFwaAA==.Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgMJBQAAAA==.Leondis:BAACLgAFFH8GAAIOAAIJsxT1ewCMAAAOAAIJsxT1ewCMAAAuAAQKfzMAAg4ACQl0ImwLAO8CAA4ACQl0ImwLAO8CAAAA.Leviosa:BAAALgAECgMJAgAAAA==.Lexipriest:BAACLgAFFH8eAAMHAAcJTRjyAgA3AgAHAAcJTRjyAgA3AgAWAAMJiQtgEADHAAAuAAQKf1EAAwcACQlrIe8DAEEDAAcACQlrIe8DAEEDABYACAkzHYcIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.Lilpp:BAAALgAECgIJAgABLgAECgYJDgABAAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Lloydak:BAAALgAECgkJCgAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgcJHAAFAHwSAA==.Lockmonster:BAAALgAECgIJAwAAAA==.Locksteady:BAAALgAECgcJCAAAAA==.Lokii:BAAALgAECgEJAgAAAA==.Lookalock:BAAALgAECgQJBQAAAA==.Lorp:BAAALgAECgYJBwAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAITAAgJeB2EKQBcAgATAAgJeB2EKQBcAgAAAA==.Lumosmaxiima:BAAALgAECgcJCwAAAA==.Lunadesangre:BAAALgAECgEJBAAAAA==.Lunarette:BAAALgAECgMJBQAAAA==.',
Ly='Lydax:BAABLgAECn8UAAIJAAcJ+RtqVwDcAQAJAAcJ+RtqVwDcAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
['Lö']='Lökï:BAAALgAECgEJAQAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAABLgAECn8XAAIpAAYJ9xghPQCrAQApAAYJ9xghPQCrAQAAAA==.Madkingzack:BAABLgAECn8fAAMEAAkJQSTfAgA8AwAEAAkJQSTfAgA8AwAoAAEJywZweAAoAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAABLgAECn8bAAMhAAkJZBCxEAArAQADAAkJywvwUgCeAQAhAAYJHxWxEAArAQAAAA==.Mallikii:BAABLgAECn8dAAMaAAkJ0hu9MADoAQAaAAkJ0hu9MADoAQAbAAQJrSMBOABZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8gAAINAAkJ9w0ibQCaAQANAAkJ9w0ibQCaAQAAAA==.Marigosa:BAABLgAECn8XAAINAAgJJgbKowAwAQANAAgJJgbKowAwAQAAAA==.Marnolkas:BAAALgAECgEJAQABLgAECgUJDAABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAABLgAECn8oAAMJAAkJCx7bFwCqAgAJAAkJCx7bFwCqAgACAAcJ1h68FABdAgAAAA==.Mattdemon:BAAALgAECgcJCQAAAA==.Maudib:BAABLgAECn8VAAIjAAgJSRVRJAAcAQAjAAgJSRVRJAAcAQAAAA==.Mawile:BAAALgAECgUJCwAAAA==.',
Me='Meautiful:BAAALgAECgQJBAAAAA==.Medusa:BAAALgAECgUJEwAAAA==.Meesha:BAAALgAECgIJAwAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAABLgAECn8ZAAICAAYJ2RMjNQByAQACAAYJ2RMjNQByAQAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQhAAgJBA97HABqAQAhAAcJYw57HABqAQADAAUJ/wrlxQDNAAAcAAEJ2hVmLgBBAAAAAA==.Merkxi:BAABLgAECn8tAAISAAkJBiL2AQAvAwASAAkJBiL2AQAvAwAAAA==.Messe:BAABLgAECn9AAAIiAAkJAR4SAgCnAgAiAAkJAR4SAgCnAgAAAA==.Mestre:BAAALgAECgYJCwAAAA==.Methious:BAABLgAECn8WAAIJAAkJnRg3agCqAQAJAAkJnRg3agCqAQAAAA==.',
Mi='Mikethepally:BAAALgAECgQJBwAAAA==.Minigoober:BAAALgAECgQJBAAAAA==.',
Mo='Mogli:BAAALgAECgQJAwABLgAECgkJNgATAGUfAA==.Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8ZAAIKAAcJuQh6FQBiAQAKAAcJuQh6FQBiAQAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECggJDgAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonrivr:BAAALgAECgUJCAABLgAECggJKQAYALUOAA==.Moonsguard:BAAALgADCgcJCgABLgAECgUJEQABAAAAAA==.Moosewillis:BAAALgAECgcJBwAAAA==.Moovit:BAABLgAECn8YAAMYAAYJvQftOAClAAAYAAYJvQftOAClAAAIAAEJugEqjAEZAAAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgIJAQAAAA==.Morgannahkay:BAAALgAECgkJCQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.Musui:BAAALgADCgIJAgAAAA==.',
My='Myströnghand:BAAALgAECgcJBwAAAA==.',
Na='Nagumo:BAABLgAECn8mAAMhAAgJFQTyOQDMAAADAAgJ4wNqpQDxAAAhAAYJYAPyOQDMAAAAAA==.Nahual:BAAALgADCgQJBQAAAA==.Nala:BAABLgAECn8WAAMbAAgJqhFqNAA4AQAbAAcJvw5qNAA4AQAaAAQJWBdtbgAJAQABLgAFFAQJDQAaALkPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAACLgAFFH8GAAIPAAMJ9As8QQCzAAAPAAMJ9As8QQCzAAAuAAQKfy4AAw8ACAklGPY3AEIBAA8ABwkgF/Y3AEIBABAABwllEv8YADwBAAAA.Nastylock:BAAALgAECgEJAQAAAA==.',
Ne='Nekoya:BAAALgADCgMJAwABLgAECgUJBwABAAAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwABLgAECgQJBAABAAAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8MAAITAAUJZR1kLgBTAQATAAUJZR1kLgBTAQAuAAQKfzQAAxMACQnAJfMAANgDABMACQnAJfMAANgDAB8AAQk3FGEwADUAAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgAECgcJBwAAAA==.Nivan:BAAALgAECgYJEQAAAA==.Niço:BAACLgAFFH8HAAIOAAMJTxrlSwD/AAAOAAMJTxrlSwD/AAAuAAQKfxUAAg4ACQnPHKkfAEcCAA4ACQnPHKkfAEcCAAAA.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIaAAkJJhs5HgBNAgAaAAkJJhs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAAALgAFFAEJAQAAAQ==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
Nu='Nutz:BAAALgAECgkJAgAAAA==.',
['Nï']='Nï:BAAALgAECgEJAQAAAA==.',
Of='Offlyne:BAAALgAECgEJAQAAAA==.',
Oh='Ohntakae:BAAALgAECgUJAgAAAA==.',
Ok='Oksana:BAAALgAECggJEAAAAA==.',
Ol='Ollamh:BAAALgAECgEJAwAAAA==.',
Om='Ombravuota:BAAALgAECgcJEQAAAA==.',
Oo='Oom:BAAALgAECgIJAgAAAA==.',
Or='Oralian:BAABLgAECn8hAAMhAAkJwSMrCwANAgAhAAUJrCMrCwANAgADAAUJhCMLRQD8AQAAAA==.Orcleave:BAABLgAECn8UAAMEAAcJIxuIQwCXAQAEAAYJ3xSIQwCXAQAFAAUJsR6YHgBQAQAAAA==.Orflap:BAAALgAECgEJAgABLgAECgcJFAAEACMbAA==.',
Ov='Ovee:BAAALgADCgcJBgAAAA==.',
Pa='Paboo:BAAALgAECgcJDAAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8pAAMNAAkJXBo2MwBFAgANAAkJXBo2MwBFAgAnAAEJZQndEwApAAAAAA==.Perturabo:BAAALgAECgEJAgAAAA==.',
Ph='Phoenyx:BAABLgAECn8YAAMhAAYJOAonHAC7AAAhAAYJOAonHAC7AAADAAUJjQGKBQFZAAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMOAAcJDx2zJAAqAgAOAAcJDx2zJAAqAgAeAAMJdQuDawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJIAANAPcNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgAECgIJAgAAAA==.',
['Põ']='Põ:BAAALgAECgMJAwABLgAECgkJKAAJAAseAA==.',
Qu='Quorra:BAAALgAECgEJAQAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8rAAIEAAkJcB4TEwBTAgAEAAkJcB4TEwBTAgAAAA==.Rakagar:BAABLgAECn8yAAIJAAkJOh69HwB/AgAJAAkJOh69HwB/AgAAAA==.Raktot:BAAALgAECgEJAQAAAA==.Ranko:BAAALgAECgkJBAAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reia:BAAALgAFFAMJAwAAAA==.Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8cAAILAAcJ9hr8CQA5AgALAAcJ9hr8CQA5AgAuAAQKfy8AAgsACQkQIKQPAJcCAAsACQkQIKQPAJcCAAAA.Reyz:BAABLgAECn8ZAAILAAgJHBWGIQCnAQALAAgJHBWGIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQABLgAECgUJBwABAAAAAA==.',
Rh='Rhaegos:BAAALgAECgUJDAAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8iAAIEAAYJTCFSKgCmAQAEAAYJTCFSKgCmAQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
Ry='Rythmias:BAAALgAECgUJBgAAAA==.Ryvive:BAAALgADCgkJEQAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAFFAQJDAAOAE0eAA==.',
['Rë']='Rëz:BAAALgAECgUJBwAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAECgcJFAAEACMbAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8xAAMgAAkJ1yKdBQDYAgAgAAkJ1yKdBQDYAgATAAYJUhkWZABTAQABLgAECgkJNAAIACMhAA==.Scripts:BAAALgAECgYJEQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJIAANAPcNAA==.',
Sh='Shadowyarrow:BAAALgAECgQJBAAAAA==.Shale:BAABLgAECn9IAAMQAAkJjhmqBwBzAgAQAAkJjhmqBwBzAgAPAAgJqgg9YgCmAAAAAA==.Shamboo:BAAALgADCgkJEgAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAACLgAFFH8FAAIZAAMJ3RYzLADVAAAZAAMJ3RYzLADVAAAuAAQKfxkAAxkABwkKHL4pAJQBABkABwkKHL4pAJQBACkABAnmDFF0AL8AAAAA.Shamyhagar:BAAALgAECggJCAAAAA==.Sharaiya:BAABLgAECn8sAAIaAAkJvgUHaADzAAAaAAkJvgUHaADzAAAAAA==.Sharkmanfive:BAAALgAECgUJBQAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Sherp:BAAALgAECgUJBgAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAABLgAECn8vAAMOAAgJDSIqEgC1AgAOAAgJDSIqEgC1AgAeAAEJJRGYhgA2AAAAAA==.Sioux:BAAALgAECgUJEAAAAA==.',
Sk='Skippybmm:BAAALgAECgQJDQABLgAECgcJHAAFAHwSAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgUJBgABLgAECgkJQAAiAAEeAA==.',
Sl='Sledgehammer:BAAALgADCgUJBQAAAA==.',
Sm='Smexyshâmmy:BAAALgAECggJDgAAAA==.',
So='Soferus:BAAALgADCggJCAABLgAECgUJDAABAAAAAA==.Solaire:BAACLgAFFH8NAAIUAAUJSRqlBQAfAQAUAAUJSRqlBQAfAQAuAAQKfywAAhQACQn+ILkBADMDABQACQn+ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJuR7jEwCpAgADAAkJuR7jEwCpAgABLgAFFAgJIgATAPgYAA==.Soulful:BAAALgAECgYJBgAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAaALkPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAABLgAECn8cAAIFAAcJfBJiHQA8AQAFAAcJfBJiHQA8AQAAAA==.Spot:BAAALgAECgYJCAABLgAECgkJIAANAPcNAA==.Spyy:BAAALgAECgYJCwAAAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgQJCQAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn9CAAMSAAkJgyLDAQA5AwASAAkJgyLDAQA5AwAeAAcJKBWVFQAAAQAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECgkJOQAfAD0QAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8gAAMhAAgJmBdzBwDOAQAhAAgJmBdzBwDOAQADAAEJlQFnVgEaAAAAAA==.Tankinit:BAAALgAECgQJEgAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgAECgEJAQABLgAECgUJCgABAAAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.Tattered:BAAALgADCgEJAQABLgAECgMJAwABAAAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIUAAMJswgGBACcAAAUAAMJswgGBACcAAAuAAQKfyUAAhQACAkJHX0GAIACABQACAkJHX0GAIACAAAA.Tenzink:BAABLgAECn8mAAILAAkJGRynDgCkAgALAAkJGRynDgCkAgAAAA==.',
Th='Thalon:BAAALgAFFAEJAQABLgAFFAMJCwAIAIIfAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgAECgEJAgAAAA==.Thedru:BAABLgAECn84AAIaAAgJXg+TRQBvAQAaAAgJXg+TRQBvAQAAAA==.Therodron:BAAALgADCgIJAgAAAA==.Thrastus:BAAALgAECgEJAQAAAA==.Thrus:BAABLgAECn8XAAMMAAgJjBAtJwBxAQAMAAgJjBAtJwBxAQALAAYJqQ4WUgAKAQABLgAECgkJQAAiAAEeAA==.Théworld:BAAALgAECgUJEQAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgYJBwABLgAECgkJKQANAFwaAA==.',
Tl='Tlnks:BAAALgADCgQJBwAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Tokeon:BAAALgAECgEJAQAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAACLgAFFH8GAAISAAMJyQ4uHQDZAAASAAMJyQ4uHQDZAAAuAAQKfyMAAhIACQlGH9oEANkCABIACQlGH9oEANkCAAAA.',
Tr='Traler:BAAALgAECgEJAQABLgAECgkJRQAdAKcUAA==.Tralzitashan:BAABLgAECn88AAMmAAkJMhPRAgAJAgAmAAkJMhPRAgAJAgANAAQJzAMXIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAINAAcJWhq0ZQAMAgANAAcJWhq0ZQAMAgAAAA==.Tren:BAAALgADCgMJAwAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgAECgYJCAAAAA==.',
Ty='Tyrdonut:BAAALgAECgEJAQABLgAECggJIQAXAEkLAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Ub='Ubie:BAAALgADCgQJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAABLgAECn8WAAMYAAcJLRKnKQD/AAAYAAYJmRGnKQD/AAARAAIJDRLHKAByAAAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAACLgAFFH8JAAIJAAMJpR09SwAIAQAJAAMJpR09SwAIAQAuAAQKfxkAAgkACQnlJJkHACgDAAkACQnlJJkHACgDAAAA.Unglausp:BAACLgAFFH8IAAIGAAMJMxccIADaAAAGAAMJMxccIADaAAAuAAQKfyYAAgYACAn9HtINAKYCAAYACAn9HtINAKYCAAEuAAUUAwkJAAkApR0A.',
Uz='Uzington:BAACLgAFFH8bAAIFAAUJyxUhEgAHAQAFAAUJyxUhEgAHAQAuAAQKfyYAAgUACQmyHPQIAI8CAAUACQmyHPQIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgIJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAABLgAECn8cAAIDAAcJ9Qd5oQD4AAADAAcJ9Qd5oQD4AAAAAA==.Valorien:BAACLgAFFH8PAAIJAAUJ8xzzJgBaAQAJAAUJ8xzzJgBaAQAuAAQKfyEAAgkACAkgG208AAcCAAkACAkgG208AAcCAAAA.Valzlok:BAAALgAECgMJAwAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgASAC0jAA==.Velinieron:BAABLgAECn8eAAISAAkJLSNPBQC8AgASAAkJLSNPBQC8AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgASAC0jAA==.Vellash:BAABLgAECn8cAAIgAAYJxQoPNQDWAAAgAAYJxQoPNQDWAAAAAA==.Vendétta:BAABLgAECn8nAAIOAAkJcxAAQwDNAQAOAAkJcxAAQwDNAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8eAAINAAgJIQrJjABYAQANAAgJIQrJjABYAQAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgADCggJCQAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8wAAIOAAkJ1RZ+JABFAgAOAAkJ1RZ+JABFAgAAAA==.',
Vy='Vynlandis:BAABLgAECn8+AAMIAAkJ5xhWLQBCAgAIAAkJ5xhWLQBCAgARAAMJgQSLKgBnAAAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAaALkPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Wargg:BAAALgAECgYJBgABLgAECgkJHQAgAFsbAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAABLgAECn8ZAAIGAAcJdRDuMABRAQAGAAcJdRDuMABRAQAAAA==.Weenbean:BAAALgAFFAMJBAAAAA==.Werebray:BAAALgAFFAMJAwAAAA==.',
Wh='Whaco:BAABLgAECn8fAAIUAAgJmBuXDADvAQAUAAgJmBuXDADvAQAAAA==.Whatisaggro:BAABLgAECn8ZAAIEAAcJ4Bs4LwCLAQAEAAcJ4Bs4LwCLAQAAAA==.Whispertree:BAABLgAECn8vAAIbAAkJ0CF/BwDTAgAbAAkJ0CF/BwDTAgAAAA==.White:BAAALgAECgUJBQABLgAFFAMJBgASACMRAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECggJIQAXAEkLAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8RAAMIAAQJdx+OQABhAQAIAAQJdx+OQABhAQARAAIJwRBaGQCRAAAuAAQKfysAAwgACQkrIWINAC8DAAgACQkrIWINAC8DABEAAQl9HfItAFQAAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8uAAQYAAcJNxnqFADDAQAYAAYJmx3qFADDAQAIAAcJoxLAhwBMAQARAAIJcxhNEgBsAAAAAA==.Wixypoo:BAACLgAFFH8IAAIKAAMJOBTBMQDVAAAKAAMJOBTBMQDVAAAuAAQKfzQAAwoACQnoHQQLAHsCAAoACQnoHQQLAHsCAAsAAQnpAfTBABsAAAAA.',
Wo='Wockyslush:BAABLgAECn8kAAIkAAkJfSTpCAADAwAkAAkJfSTpCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.Woodnzhood:BAAALgADCgYJCAAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMPAAkJWhijFwATAgAPAAkJWhijFwATAgAXAAYJwAMuKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8fAAIpAAgJvR0SHgBQAgApAAgJvR0SHgBQAgAAAA==.',
Wy='Wyyn:BAABLgAECn82AAINAAkJ1wovaQCjAQANAAkJ1wovaQCjAQAAAA==.',
Xa='Xanboi:BAABLgAECn9DAAMSAAkJ7yTVAQA2AwASAAkJ7yTVAQA2AwAOAAIJ6iK1iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAACLgAFFH8QAAIEAAUJQSAcFABYAQAEAAUJQSAcFABYAQAuAAQKfycAAgQACQndIRINAO0CAAQACQndIRINAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Yo='Yona:BAAALgADCgIJAgABLgAECgkJIAANAPcNAA==.',
Ys='Ysar:BAABLgAECn8dAAIPAAkJag7iJgCiAQAPAAkJag7iJgCiAQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMXAAcJ6RqJDgDyAQAXAAYJkB+JDgDyAQAPAAYJGxdJIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECgcJKAAUAPYUAA==.',
Ze='Zeebu:BAABLgAECn8yAAISAAkJlQqmGQDNAQASAAkJlQqmGQDNAQAAAA==.Zenboi:BAABLgAECn8cAAITAAgJ1RUcQwDnAQATAAgJ1RUcQwDnAQAAAA==.Zephryyn:BAABLgAECn8ZAAIpAAcJ3gSreADjAAApAAcJ3gSreADjAAAAAA==.',
Zh='Zhilan:BAAALgAECgUJDwAAAA==.',
Zi='Ziet:BAAALgADCgIJAgAAAA==.Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoda:BAAALgAECgEJAQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAUJDQAiAJIhAA==.Zoko:BAAALgAFFAEJAQAAAA==.Zophos:BAAALgAECggJDwABLgAECggJFgAhAAQPAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgIJAwAAAA==.Zuzuk:BAAALgAECggJEwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAABLgAECn8UAAIIAAcJ8Q65iQBIAQAIAAcJ8Q65iQBIAQAAAA==.',
['Zú']='Zúz:BAABLgAECn8UAAMHAAcJNRnGHADSAQAHAAYJpxvGHADSAQAGAAYJ7gx2QQABAQAAAA==.',
['Áß']='Áßomination:BAAALgAECgUJCAAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAACLgAFFH8FAAIpAAIJMAJhbQBQAAApAAIJMAJhbQBQAAAuAAQKfysAAikACQmiC4VWAEwBACkACQmiC4VWAEwBAAAA.',
['Ði']='Ðittø:BAAALgAECgkJEgABLgAFFAMJCgAYAP8QAA==.',
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
