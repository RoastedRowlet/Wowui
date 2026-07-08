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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Priest-Shadow','Priest-Holy','Warlock-Destruction','DeathKnight-Unholy','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Preservation','DeathKnight-Frost','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Shaman-Enhancement','Priest-Discipline','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Balance','Warlock-Affliction','Rogue-Subtlety','Druid-Feral','Warrior-Arms','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Outlaw','Druid-Guardian','Rogue-Assassination','Mage-Arcane','Mage-Fire','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aalduin:BAAALgAECgMJBAABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCQAAAA==.',
Ab='Abaldorc:BAAALgAECgMJBAAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.Adhin:BAAALgADCgUJBQAAAA==.',
Ae='Aephiona:BAAALgAECgQJBAAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAgJFAACANsXAQ==.',
Af='Affli:BAACLgAFFH8XAAIDAAYJyBXKLQCOAQADAAYJyBXKLQCOAQAuAAQKfysAAgMACQkUIEIbALECAAMACQkUIEIbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8pAAIFAAgJHhabFgCPAQAFAAgJHhabFgCPAQAAAA==.Aiupriesty:BAABLgAECn8nAAMGAAgJDQyOMQBWAQAGAAgJDQyOMQBWAQAHAAYJcBMeSwC3AAABLgAECggJKQAFAB4WAA==.',
Ak='Aka:BAAALgAECgEJAQAAAA==.Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAABLgAECn8hAAIIAAgJYg2cAgAWAQAIAAgJYg2cAgAWAQAAAA==.Alastor:BAAALgADCgIJAgAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAABLgAECn8ZAAIJAAYJ0gyfvQABAQAJAAYJ0gyfvQABAQAAAA==.Aleinara:BAABLgAECn8iAAIKAAkJKRDFCQBNAQAKAAkJKRDFCQBNAQAAAA==.Aleridin:BAABLgAECn8rAAILAAkJHiUXAgBCAwALAAkJHiUXAgBCAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAACLgAFFH8bAAIMAAYJlx4IFgDQAQAMAAYJlx4IFgDQAQAuAAQKfyQABAwACQmIGxQOALwCAAwACQmIGxQOALwCAA0ABwm7IEEBAA8CAAsAAQlAIWBxAGIAAAAA.Alraa:BAAALgAECggJDwAAAA==.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Androgynous:BAAALgAECgMJAwAAAA==.Andsey:BAAALgAECgQJCAAAAA==.Annore:BAABLgAECn8dAAIJAAkJdxLMUwDJAQAJAAkJdxLMUwDJAQAAAA==.Antihero:BAABLgAECn8hAAIJAAkJeiN5DgAnAwAJAAkJeiN5DgAnAwAAAA==.',
Ap='Aphelse:BAAALgADCgMJAwABLgAFFAYJGwAMAJceAA==.',
Aq='Aquiell:BAABLgAECn8kAAIOAAkJqxAjWQDSAQAOAAkJqxAjWQDSAQAAAA==.Aqular:BAABLgAECn8oAAIPAAgJ8hclBwCVAQAPAAgJ8hclBwCVAQAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8gAAIFAAYJtSRDBgDqAQAFAAYJtSRDBgDqAQAuAAQKf0oAAwUACQkkJe8BADUDAAUACQkkJe8BADUDAAQABQnNECFiAM8AAAAA.Arkenomu:BAABLgAECn8lAAMQAAgJNRH1MgBoAQAQAAgJNRH1MgBoAQARAAcJagx1GgAzAQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8vAAMSAAkJwgl+EgBRAQASAAkJwgl+EgBRAQAJAAYJsAHP7AClAAAAAA==.Asclepius:BAABLgAECn8jAAIRAAkJnQ+vDwDQAQARAAkJnQ+vDwDQAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Askmelic:BAAALgAECgEJAQAAAA==.Aslo:BAAALgADCgEJAQAAAA==.Asmira:BAAALgADCgYJCQAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn85AAMTAAgJcyHqEAAlAgATAAcJWSHqEAAlAgAPAAYJVx2/TQC5AQAAAA==.Asza:BAAALgADCgYJBgAAAA==.',
At='Atsunvhi:BAAALgAECgUJEwAAAA==.',
Av='Avadakedevra:BAABLgAECn8jAAMTAAcJKBNjJgBqAQATAAcJKBNjJgBqAQAPAAEJKwpFzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azareth:BAAALgADCgkJCQAAAA==.Azreal:BAAALgAECgcJDQAAAA==.Azumok:BAAALgAECgQJBAAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bairn:BAAALgADCggJCwAAAA==.Bakedbean:BAAALgAFFAEJAQABLgAFFAEJBgAUAJwkAA==.Barackobooma:BAAALgAECgIJAgAAAA==.Bazerker:BAAALgAECgUJDwAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8lAAIOAAgJnA+jfAB/AQAOAAgJnA+jfAB/AQAAAA==.',
Be='Beastcode:BAAALgAECggJCAAAAA==.Belgaria:BAABLgAECn8pAAMVAAgJJxTIEwCPAQAVAAgJJxTIEwCPAQAKAAcJgg1ilQBSAQAAAA==.Berryknight:BAACLgAFFH8FAAIJAAIJ3hODygCYAAAJAAIJ3hODygCYAAAuAAQKfy4AAwkACQlxG5gxADgCAAkACQlxG5gxADgCABIAAgnYD/4vAF8AAAAA.Berryqt:BAAALgAECgQJCQAAAA==.Bewlzeye:BAAALgAECgUJBwAAAA==.',
Bi='Bigjonmachne:BAACLgAFFH8PAAIJAAUJSh40IgAVAQAJAAUJSh40IgAVAQAuAAQKfxgAAgkACAlAG58vAEECAAkACAlAG58vAEECAAAA.Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8kAAIHAAcJGCP/AgBbAgAHAAcJGCP/AgBbAgAuAAQKfx8AAgcACQnOJIkDACIDAAcACQnOJIkDACIDAAAA.Blessmoo:BAABLgAECn8eAAIKAAkJeBfpAwAAAgAKAAkJeBfpAwAAAgAAAA==.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodsail:BAAALgAECgUJBQAAAA==.Bloodydk:BAAALgAECgEJAQAAAA==.Bluestripee:BAAALgAECgEJAQAAAA==.Bluezugzug:BAAALgAECgMJBQAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8yAAIWAAkJ2hdmCQAmAgAWAAkJ2hdmCQAmAgAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn80AAMGAAkJ9yANCQC9AgAGAAkJ9yANCQC9AgAXAAEJaBblVgA0AAAAAA==.Bonnieanne:BAAALgADCgEJAQAAAA==.Bonsaichi:BAAALgAECgkJEQAAAA==.Bownyxia:BAACLgAFFH8JAAIQAAMJQBaVEQD1AAAQAAMJQBaVEQD1AAAuAAQKfzYAAxAACQnIIpMFAAYDABAACQnIIpMFAAYDABgABAlGDvspAM4AAAEuAAUUCQkxAAkA3hsA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAkJMQAJAN4bAA==.Bowties:BAACLgAFFH8xAAMJAAkJ3htPCgCSAgAJAAkJ3htPCgCSAgAZAAEJAAC9WwAAAAAuAAQKf0MAAwkACQmUJjgCAHsDAAkACQmUJjgCAHsDABkACQk3GHkKAHECAAAA.',
Br='Braxchud:BAABLgAECn8/AAIaAAkJJhzDDwB3AgAaAAkJJhzDDwB3AgAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAIOAAkJixukMABWAgAOAAkJixukMABWAgAAAA==.Brewnwings:BAAALgAECgUJCgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8RAAIUAAQJGROQFAAuAQAUAAQJGROQFAAuAQAuAAQKfx0AAhQACQm9Hf4YAH8CABQACQm9Hf4YAH8CAAEuAAUUCQkxAAkA3hsA.',
Bu='Bubbles:BAAALgAECgUJBQABLgAECgkJRAAEAOwkAA==.Bubsy:BAAALgADCgEJAQAAAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burial:BAAALgADCgcJCAAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgQJEgAAAA==.',
Ca='Caarrl:BAAALgAECgYJEAAAAA==.Caedo:BAAALgAECgQJBAAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBQAAAA==.Caliet:BAAALgADCgUJBQAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgAECgYJCAAAAA==.Calistra:BAAALgADCgYJBgAAAA==.Calistriaa:BAAALgADCgQJBAAAAA==.Caplock:BAAALgAECgQJBQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAABLgAECn8YAAITAAcJ+gZCBADgAAATAAcJ+gZCBADgAAAAAA==.Carlistria:BAAALgADCgEJAQAAAA==.Cartime:BAAALgAECgMJBAAAAA==.Cayllia:BAABLgAECn8jAAMbAAkJDCSOBABFAwAbAAkJDCSOBABFAwAcAAgJDCLaFQAgAgAAAA==.',
Ce='Celaris:BAABLgAECn8ZAAICAAcJdRxAAQA9AgACAAcJdRxAAQA9AgAAAA==.',
Ch='Chaolang:BAAALgAFFAEJAQAAAA==.Chataykay:BAAALgAECgcJEwAAAA==.Cheon:BAAALgAECgYJCAAAAA==.Cherrypepsï:BAABLgAECn8dAAMHAAkJOQ/aKwCYAQAHAAkJOQ/aKwCYAQAXAAUJdgbwOADgAAAAAA==.Chinlen:BAAALgAECgEJAQAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chivies:BAAALgAECggJDgABLgAECgkJNQAKAIgiAA==.Chronosdormi:BAAALgAECgUJBQAAAA==.',
Ci='Circë:BAABLgAECn8kAAIdAAkJKxhBBQA5AgAdAAkJKxhBBQA5AgAAAA==.Citrus:BAABLgAECn85AAITAAkJtBWCFAAAAgATAAkJtBWCFAAAAgAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBwAAAA==.Cliqmonk:BAAALgAECgcJCAAAAA==.',
Cn='Cn:BAABLgAECn81AAIKAAkJiCJGFQDDAgAKAAkJiCJGFQDDAgAAAA==.',
Co='Cocoabutter:BAABLgAECn8cAAIOAAYJmBG2tgAXAQAOAAYJmBG2tgAXAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAAOAIsbAA==.Codeman:BAABLgAECn89AAMZAAkJSyMdBAD2AgAZAAkJSyMdBAD2AgAJAAEJEwv2dAEyAAAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJPQAZAEsjAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8hAAMMAAgJoxeeCgCAAQAMAAcJpBWeCgCAAQANAAUJsBWeFgALAQAuAAQKf2QAAwwACQl2I78DAHwDAAwACQl2I78DAHwDAA0ABgloIXEbANQBAAAA.Contemplate:BAAALgAECgMJCAAAAA==.Cordine:BAAALgAFFAEJAQAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corran:BAAALgADCgcJBwAAAA==.Corruptz:BAAALgAECgkJGwABLgAECgkJJQAeAKMZAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.Crimofc:BAAALgAECgEJAQAAAA==.Crúsh:BAAALgAECgEJAQAAAA==.',
Ct='Ctk:BAAALgAECgEJAQAAAA==.',
Cu='Culluh:BAAALgAECgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAABLgAECn8cAAIfAAYJFhxwGABNAQAfAAYJFhxwGABNAQAAAA==.Cyrae:BAAALgAECgQJBAABLgAECgkJRAAEAOwkAA==.',
Cz='Czin:BAABLgAECn9EAAQEAAkJ7CT4AQBaAwAEAAkJ7CT4AQBaAwAgAAMJciAtBQDAAAAFAAEJkQnBSwAlAAAAAA==.',
['Cï']='Cïel:BAAALgAECgUJBQAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgYJEwAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Daniele:BAAALgAECgEJAQAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJCQAAAA==.Deathverses:BAACLgAFFH85AAIhAAgJsCZdAAAPAwAhAAgJsCZdAAAPAwAuAAQKfy4AAiEACQnjJikCAJYDACEACQnjJikCAJYDAAAA.Deerslayer:BAAALgAECgcJEAAAAA==.Deezknights:BAAALgAECgUJCAABLgAECgYJDgABAAAAAA==.Delter:BAABLgAECn8UAAIhAAgJuxyFHwAqAgAhAAgJuxyFHwAqAgABLgAECggJFAAhALscAA==.Deltritus:BAACLgAFFH8dAAIOAAgJIRpEEQBiAgAOAAgJIRpEEQBiAgAuAAQKfzQAAg4ACQnnI0EJADADAA4ACQnnI0EJADADAAEuAAQKCAkUACEAuxwA.Demaedra:BAAALgAECgMJAwAAAA==.Demoan:BAABLgAECn89AAIiAAkJKSOcAQALAwAiAAkJKSOcAQALAwAAAA==.Demonbiscuit:BAACLgAFFH8GAAIjAAQJ6x2hCAB9AQAjAAQJ6x2hCAB9AQAuAAQKfx8AAiMACAmlJsAEAPoCACMACAmlJsAEAPoCAAAA.Derpydawg:BAAALgAECgEJAQABLgAFFAUJGgAJAOwgAA==.Dethh:BAAALgADCgMJAwAAAA==.Deviancy:BAABLgAECn8XAAMCAAkJdxmNEgB9AgACAAkJdxmNEgB9AgAKAAEJpAU/xAEiAAABLgAECggJKAAMAPgfAA==.',
Dh='Dhruven:BAAALgADCggJCAAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAABLgAECn8UAAIQAAYJ0A/ZWADQAAAQAAYJ0A/ZWADQAAAAAA==.Diese:BAAALgAECgYJCQAAAA==.Dikslapp:BAABLgAECn84AAIjAAkJbiKOBAD/AgAjAAkJbiKOBAD/AgAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Dipperton:BAAALgAECgEJAQABLgAECgcJFAAYAOkaAA==.Discrespect:BAACLgAFFH8LAAMXAAUJ4xEIKAALAQAXAAQJYBQIKAALAQAHAAEJ8Qc4NQBBAAAuAAQKfyEABBcACQmaGoETAEUCABcACQmaGoETAEUCAAcABAkiCMhcAMAAAAYAAQkfAyCZAB8AAAAA.Distinct:BAAALgAECgkJCQABLgAECgkJPQAiACkjAA==.Ditto:BAACLgAFFH8KAAIZAAMJ/xD/KwCbAAAZAAMJ/xD/KwCbAAAuAAQKfzwABBkACAmpHOsMAEECABkACAmpHOsMAEECAAkABwkpCzKrABsBABIAAwlBDt4PAJ4AAAAA.',
Dl='Dlitinaro:BAABLgAECn80AAMJAAkJIyG8IgB8AgAJAAkJBx+8IgB8AgAZAAkJcx70CQBzAgAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMRAAMJoxd9DQAHAQARAAMJoxd9DQAHAQAQAAEJHAktZwA3AAAuAAQKfxkAAxEACAlwJLYDACADABEACAlwJLYDACADABAAAwlpGjBOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Dollette:BAAALgAECggJBQAAAA==.Donoph:BAABLgAECn89AAMCAAkJ/yPOAgB5AwACAAkJ/yPOAgB5AwAKAAEJQwwKoQEtAAAAAA==.Doomar:BAABLgAECn83AAMDAAkJjSG2GACPAgADAAkJTiG2GACPAgAIAAYJfR91CADGAQAAAA==.Doomsamdi:BAAALgAECgcJCAABLgAECgkJNwADAI0hAA==.Doomseph:BAAALgAECgEJAQABLgAECgkJNwADAI0hAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.Dotzilla:BAAALgAECgQJBAAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8fAAMDAAkJ6An/dABQAQADAAkJMAn/dABQAQAIAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgAECgUJDgAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8hAAMYAAgJSQu+HwAwAQAYAAcJZwq+HwAwAQAQAAYJ9AoAUwDjAAAAAA==.Dreav:BAAALgAECgIJAgAAAA==.Drugar:BAABLgAECn8rAAIOAAkJog82ewCCAQAOAAkJog82ewCCAQAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEx8IFQDCAAAEAAIJEx8IFQDCAAAuAAQKfxYAAgQACAneHbASALkCAAQACAneHbASALkCAAEuAAUUCQk/ABYA1yUA.',
Du='Duloc:BAAALgAECgUJCAAAAA==.Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgUJEwAAAA==.Duskbane:BAAALgAECggJEgABLgAECgkJJQAeAKMZAA==.',
Dw='Dwiddly:BAAALgADCgYJBgAAAA==.',
Dy='Dynabol:BAACLgAFFH8GAAIUAAEJnCQhNABjAAAUAAEJnCQhNABjAAAuAAQKfzUAAxQACQkOJpICAF8DABQACQl8JZICAF8DACIACAkhJYYCANQCAAAA.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAUJGgAJAOwgAA==.',
Eb='Eborsisk:BAAALgADCgYJBgAAAA==.',
Ee='Eelane:BAAALgAECgQJEAAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgAECgQJBgAAAA==.Eltain:BAAALgADCgEJAQAAAA==.',
Em='Eminnazen:BAAALgADCgkJDgAAAA==.',
En='Endurall:BAAALgAECgkJEQABLgAECgkJQAAkAAEeAA==.',
Er='Eradication:BAAALgAECgEJAQABLgAECgkJJQAeAKMZAQ==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Eu='Eurydicee:BAAALgAECgQJBAAAAA==.',
Ev='Eveleigh:BAAALgAECgEJAQAAAA==.Everfale:BAAALgAECgIJAwABLgAECgkJJQAeAKMZAQ==.Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn81AAIEAAkJIhs6GwAUAgAEAAkJIhs6GwAUAgAAAA==.Fallyandor:BAAALgAECgQJBAAAAA==.Faolsabre:BAABLgAECn8oAAIJAAkJSQxSZACfAQAJAAkJSQxSZACfAQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgATAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn9GAAQfAAkJFRVfCwAGAgAfAAkJBBVfCwAGAgAlAAYJVxGELAD9AAAbAAcJHQaodQDUAAAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8xAAIbAAkJdBm1GACAAgAbAAkJdBm1GACAAgAAAA==.',
Fo='Folid:BAAALgAECgEJAgAAAA==.Forne:BAAALgAFFAEJAQAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB51CgDOAgACAAkJbB51CgDOAgAAAA==.Frostedphyre:BAAALgAECgkJDQAAAA==.',
Fu='Furrywhaco:BAABLgAECn8VAAIlAAkJ+RqJCABlAgAlAAkJ+RqJCABlAgAAAA==.Fuzzyspells:BAABLgAECn8UAAIXAAcJXxAlBABoAQAXAAcJXxAlBABoAQAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMKAAgJLxv2SwD/AQAKAAYJsB72SwD/AQAVAAYJ7xJ2IQAJAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galadrîel:BAAALgAECgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.Gargamell:BAAALgAECgYJBgAAAA==.Garruond:BAAALgAECgEJAQAAAA==.',
Ge='Genndra:BAAALgADCgMJAwAAAA==.Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn8/AAMeAAgJKQrIKQBJAQAeAAgJAQjIKQBJAQAmAAYJVAkSFgDNAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBgAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQOAAgJsyQ4HwD4AgAOAAgJniQ4HwD4AgAnAAEJnCZFFQBzAAAoAAEJiSQ/DABrAAABLgAFFAEJBgAUAJwkAA==.',
Gr='Gravez:BAABLgAECn8aAAQZAAgJGCESAQBjAgAZAAgJIh8SAQBjAgAJAAYJRBqgTQDZAQASAAQJwh5SGAASAQABLgAECgkJJQAeAKMZAA==.Grawler:BAAALgAECgcJDAAAAA==.Greeny:BAAALgAFFAEJAQAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgQJCgABLgAECgcJDQABAAAAAA==.Grumpyhunter:BAAALgAECgcJEAABLgAECgkJOAAOAOsfAA==.',
Gu='Guesswhos:BAAALgADCgUJBQAAAA==.Gumgumfury:BAAALgAECgUJEAAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haehi:BAAALgAECgEJAQAAAA==.Haidies:BAAALgAECgUJDgABLgAFFAQJDQAbALkPAA==.Halzlok:BAABLgAECn8mAAIaAAgJlhczAgDTAQAaAAgJlhczAgDTAQAAAA==.Hammergold:BAAALgAECgEJAQAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Harandy:BAAALgAECgIJAgAAAA==.Harvester:BAAALgAECgMJAgAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAYJIAAFALUkAA==.Herøn:BAAALgAECgYJBgAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJKAAbAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAFFAQJBgAjAOsdAA==.Hondacivic:BAAALgAECgEJAQABLgAECgkJJAAeAH0kAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.Hurrysundown:BAAALgADCgEJAQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ia='Iandis:BAAALgADCgYJDwABLgAECgcJHAAFAHwSAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgUJCgAAAA==.',
Ik='Ikayhaimahn:BAACLgAFFH8TAAIlAAQJByDYAgBxAQAlAAQJByDYAgBxAQAuAAQKfxsAAiUACQkEGu0JAEkCACUACQkEGu0JAEkCAAAA.',
Im='Imysteriöus:BAABLgAECn8oAAMbAAgJBiXzBgBJAwAbAAgJBiXzBgBJAwAfAAYJHhSJEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAACLgAFFH8XAAICAAUJoR/bFACDAQACAAUJoR/bFACDAQAuAAQKfxcAAgIACAlAHJ0bADcCAAIACAlAHJ0bADcCAAAA.Indishaman:BAAALgAECgYJDAAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJNQAKAIgiAA==.',
Is='Ishamael:BAABLgAECn80AAIGAAkJUxIxIgC2AQAGAAkJUxIxIgC2AQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8LAAIYAAQJBhiwAwA4AQAYAAQJBhiwAwA4AQAuAAQKfywAAhgACQkHIngBAOACABgACQkHIngBAOACAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jarnroz:BAAALgAECgQJBAABLgAECgUJCgABAAAAAA==.Jaythirian:BAABLgAECn8YAAMgAAcJrQ6JEACUAQAgAAcJrQ6JEACUAQAEAAQJ1gQVgQC5AAAAAA==.',
Je='Jeatalena:BAAALgADCgMJAwAAAA==.Jerg:BAACLgAFFH8NAAIbAAQJuQ8+MwDgAAAbAAQJuQ8+MwDgAAAuAAQKfzkAAxsACQlUHtgWAH8CABsACAmfHdgWAH8CABwABwk3Fl0uAGgBAAAA.Jessup:BAACLgAFFH8NAAMkAAQJkiGBCAD3AAAkAAQJHh+BCAD3AAAeAAIJuxuIMwCTAAAuAAQKfyoAAx4ACQmKIn8EAFADAB4ACQn8IX8EAFADACQABQl9IRkKAIIBAAAA.',
Jh='Jhara:BAABLgAECn8eAAIOAAgJXA/BgAB2AQAOAAgJXA/BgAB2AQAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAACLgAFFH8FAAQGAAMJ6g7OJQDKAAAGAAMJ6g7OJQDKAAAXAAEJiwYXUAA2AAAHAAEJzAj1OQAuAAAuAAQKfywABBcACQkQJJ4GAN4CABcACQlNI54GAN4CAAcABQm3IXceANEBAAYABQnQHGQ1AEABAAEuAAUUBgkbAAwAlx4A.Junnai:BAAALgADCgcJBwAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECggJEAAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kagamie:BAAALgADCgYJCQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgUJBgAAAA==.Kamekazi:BAAALgAECgMJAwAAAA==.Kariva:BAACLgAFFH8NAAIHAAMJ9RSaCQDKAAAHAAMJ9RSaCQDKAAAuAAQKf0kAAgcACQlVG3gKAL8CAAcACQlVG3gKAL8CAAAA.Katacemic:BAABLgAECn8qAAIZAAkJcRX8EAD7AQAZAAkJcRX8EAD7AQAAAA==.Katastrophic:BAAALgADCggJEAABLgAECgkJKgAZAHEVAA==.Katazul:BAABLgAECn8iAAMIAAkJXwqrJgArAQADAAkJewe/cABZAQAIAAYJzgqrJgArAQABLgAECgkJKgAZAHEVAA==.Kaulike:BAAALgADCgIJAgAAAA==.Kayssa:BAAALgAECgUJBQAAAA==.',
Ke='Keelanllan:BAABLgAECn8cAAIjAAkJTAh+KgArAQAjAAkJTAh+KgArAQAAAA==.Kega:BAAALgAECgEJAQAAAA==.Keilun:BAEALgAECgcJDAAAAA==.Kertzz:BAAALgAECgYJBwABLgAECgMJAwABAAAAAA==.Kew:BAABLgAECn8bAAIOAAcJLxjuWQDQAQAOAAcJLxjuWQDQAQAAAA==.Kewkew:BAAALgADCgcJDAAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECgkJIwARAJ0PAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJJQAQADURAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Kn='Kneecromance:BAABLgAFFH8FAAMZAAIJpAmkRwAWAAAJAAIJpAkK7AB+AAAZAAEJXQCkRwAWAAAAAA==.Knightxl:BAAALgAECggJCAAAAA==.',
Ko='Koggmaw:BAAALgAECgcJEAABLgAFFAQJDQAbALkPAA==.Kokuten:BAAALgAECgEJAQABLgAECgkJIAApANgbAA==.Koral:BAAALgAECgYJCgAAAA==.',
Kr='Kralj:BAAALgAECgUJCAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJPQAZAEsjAA==.Kungfuhealya:BAABLgAECn8hAAMMAAgJcgiLWgAJAQAMAAgJcgiLWgAJAQANAAEJwQE+wAAYAAAAAA==.Kuraj:BAAALgAECgEJAQAAAA==.Kurisatroll:BAAALgAECgcJBQAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAAKAPkbAA==.Larrydale:BAABLgAECn8fAAMPAAgJTxwTGQByAgAPAAgJTxwTGQByAgATAAEJqQMDMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAAKAPkbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn81AAQJAAkJ/RGHYwChAQAJAAcJfBCHYwChAQAZAAkJow2jHQBrAQASAAEJAABsRwAAAAAAAA==.',
Le='Lea:BAAALgAECgIJAgABLgAECgkJKQAOAFwaAA==.Lefica:BAAALgADCgEJAQAAAA==.Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgMJBQAAAA==.Leondis:BAACLgAFFH8HAAIPAAIJcRbJggCVAAAPAAIJcRbJggCVAAAuAAQKfzUAAg8ACQm3IjQIAA0DAA8ACQm3IjQIAA0DAAAA.Leviosa:BAAALgAECgMJAgAAAA==.Lexipriest:BAACLgAFFH8hAAMHAAgJgBZhAgB5AgAHAAgJgBZhAgB5AgAXAAMJiQtgEADHAAAuAAQKf1EAAwcACQlrIVgEAD4DAAcACQlrIVgEAD4DABcACAkzHYcIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Liez:BAAALgAECgMJAQAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.Lilpp:BAAALgAECgIJAgABLgAECgYJDgABAAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Lloydak:BAAALgAECgkJCgAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgcJHAAFAHwSAA==.Lockmonster:BAAALgAECgIJAwAAAA==.Locksteady:BAAALgAECgcJCAAAAA==.Lokii:BAAALgAECgEJAwAAAA==.Lokì:BAAALgAECgYJBwABLgAECgkJOwAUAGUfAA==.Lookalock:BAAALgAECgQJBQAAAA==.Lorp:BAAALgAECgYJBwAAAA==.',
Lu='Luciffer:BAABLgAECn8nAAIUAAkJOhyEKQBcAgAUAAkJOhyEKQBcAgAAAA==.Lumosmaxiima:BAAALgAECgcJCwAAAA==.Lunadesangre:BAAALgAECgEJBAAAAA==.Lunarette:BAAALgAECgMJBQAAAA==.',
Ly='Lydax:BAABLgAECn8UAAIKAAcJ+RtqVwDcAQAKAAcJ+RtqVwDcAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
['Lö']='Lökï:BAAALgAECgEJAQAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAABLgAECn8aAAIpAAgJyBO7QACrAQApAAgJyBO7QACrAQAAAA==.Madcowsmash:BAAALgAECgEJAQAAAA==.Madkingzack:BAABLgAECn8gAAMEAAkJQSRpAwA0AwAEAAkJQSRpAwA0AwAgAAEJywZ/gQAoAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Maevea:BAAALgAECgYJBwAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAABLgAECn8iAAMDAAkJZRGJBwAvAQADAAkJAg+JBwAvAQAIAAYJHxX+EQApAQAAAA==.Mallikii:BAABLgAECn8dAAMbAAkJ0hu9MADoAQAbAAkJ0hu9MADoAQAcAAQJrSMBOABZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8gAAIOAAkJ9w3OcwCSAQAOAAkJ9w3OcwCSAQAAAA==.Marigosa:BAABLgAECn8bAAIOAAkJPAZioAA6AQAOAAkJPAZioAA6AQAAAA==.Marnolkas:BAAALgAECgEJAQABLgAECgcJGwAYAHMaAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAACLgAFFH8KAAMCAAMJBCHGCQANAQACAAMJBCHGCQANAQAKAAEJyhYGTgBJAAAuAAQKfyoAAwoACQkLHkkaAKYCAAoACQkLHkkaAKYCAAIABwkuISMWAFoCAAAA.Mattdemon:BAAALgAECgcJDQAAAA==.Maudib:BAABLgAECn8ZAAIlAAgJSRVPBgDYAAAlAAgJSRVPBgDYAAAAAA==.Mawile:BAABLgAECn8UAAMfAAcJmhaOFgBjAQAfAAYJmhaOFgBjAQAlAAQJAg5WCgB8AAAAAA==.',
Me='Meautiful:BAAALgAECgQJBAAAAA==.Medusa:BAAALgAECgUJEwAAAA==.Meesha:BAAALgAECgcJDgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAABLgAECn8ZAAICAAYJ2RPxNwBuAQACAAYJ2RPxNwBuAQAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQIAAgJBA97HABqAQAIAAcJYw57HABqAQADAAUJ/wrlxQDNAAAdAAEJ2hVmLgBBAAAAAA==.Merkxi:BAABLgAECn8tAAITAAkJBiJTAgAnAwATAAkJBiJTAgAnAwAAAA==.Messe:BAABLgAECn9AAAIkAAkJAR41AgCqAgAkAAkJAR41AgCqAgAAAA==.Mestre:BAAALgAECgYJDgAAAA==.Methious:BAABLgAECn8WAAIKAAkJnRg3agCqAQAKAAkJnRg3agCqAQAAAA==.',
Mi='Mikethepally:BAAALgAECgQJBwAAAA==.Milicious:BAAALgADCgQJBAAAAA==.Minigoober:BAAALgAECgQJBAAAAA==.Misskitty:BAAALgAECgEJAQAAAA==.',
Mo='Mogli:BAAALgAECgQJBAABLgAECgkJOwAUAGUfAA==.Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8aAAILAAgJVglcDwCtAQALAAgJVglcDwCtAQAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECggJDgAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonrivr:BAAALgAECgYJEgABLgAECgkJNQAJAP0RAA==.Moonsguard:BAAALgAECgMJAwABLgAECgYJGAARAJQVAA==.Moosewillis:BAAALgAECgcJBwAAAA==.Moovit:BAABLgAECn8nAAMZAAcJTwygBAD2AAAZAAcJTwygBAD2AAAJAAEJugF2pgEZAAAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgMJAgAAAA==.Morgannahkay:BAAALgAECgkJCQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Munkee:BAAALgADCgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.Musui:BAAALgADCgIJAgAAAA==.',
My='Myströnghand:BAAALgAECgcJBwAAAA==.',
['Må']='Mådd:BAAALgADCgMJAwAAAA==.',
Na='Nagumo:BAABLgAECn8mAAMIAAgJFQTyOQDMAAADAAgJ4wOurADqAAAIAAYJYAPyOQDMAAAAAA==.Nahual:BAAALgADCgQJBQAAAA==.Nala:BAABLgAECn8WAAMcAAgJqhE/NwA4AQAcAAcJvw4/NwA4AQAbAAQJWBdtbgAJAQABLgAFFAQJDQAbALkPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAACLgAFFH8GAAIQAAMJ9AurSACoAAAQAAMJ9AurSACoAAAuAAQKfy4AAxAACAklGF86AEIBABAABwkgF186AEIBABEABwllEksaADUBAAEuAAUUBAkTACUAByAA.Nastylock:BAAALgAECgEJAQAAAA==.',
Ne='Nekoya:BAAALgADCgMJAwABLgAECgUJBwABAAAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwABLgAECgQJBAABAAAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8MAAIUAAUJZR2INgBKAQAUAAUJZR2INgBKAQAuAAQKfzQAAxQACQnAJfMAANgDABQACQnAJfMAANgDACIAAQk3FKszADUAAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgAECgcJBwAAAA==.Nivan:BAABLgAECn8hAAMKAAgJCQkVFQDHAAAKAAgJ+wYVFQDHAAAVAAIJPw5pCwBKAAAAAA==.Niço:BAACLgAFFH8IAAIPAAMJTxoxWAD1AAAPAAMJTxoxWAD1AAAuAAQKfxUAAg8ACQnPHKkfAEcCAA8ACQnPHKkfAEcCAAAA.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIbAAkJJhs5HgBNAgAbAAkJJhs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAABLgAECn8lAAIeAAkJoxnODgA+AgAeAAkJoxnODgA+AgAAAA==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.Novaeii:BAAALgADCgEJAQAAAA==.',
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
Oy='Oysterkid:BAAALgAECgIJAgAAAA==.',
Pa='Paboo:BAAALgAECgcJDAAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Papasmurff:BAAALgAECgEJAQAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8pAAMOAAkJXBqANgA/AgAOAAkJXBqANgA/AgAoAAEJZQnLFQAoAAAAAA==.Perturabo:BAAALgAECgEJAgAAAA==.',
Ph='Phoenyx:BAABLgAECn8ZAAMIAAYJbApCHgC3AAAIAAYJbApCHgC3AAADAAUJjQGvFAFTAAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMPAAcJDx2zJAAqAgAPAAcJDx2zJAAqAgAhAAMJdQuDawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJIAAOAPcNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.Prism:BAAALgAECgcJBwAAAA==.',
Pu='Purrs:BAAALgADCgIJAgAAAA==.',
Pv='Pve:BAAALgAECgcJCQAAAA==.',
['Põ']='Põ:BAAALgAECgMJAwABLgAFFAMJCgACAAQhAA==.',
Qu='Quorra:BAAALgAECgMJBAAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8rAAIEAAkJcB7DEwCwAgAEAAkJcB7DEwCwAgAAAA==.Rakagar:BAABLgAECn8yAAIKAAkJOh6zIgB7AgAKAAkJOh6zIgB7AgAAAA==.Rakor:BAAALgADCgkJCQAAAA==.Raktot:BAAALgAECgEJAQAAAA==.Ranko:BAAALgAECgkJBAAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.Razluz:BAAALgAECgEJAgAAAA==.',
Re='Reia:BAAALgAFFAMJAwAAAA==.Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8oAAIMAAgJ3BrQCAB9AgAMAAgJ3BrQCAB9AgAuAAQKfy8AAgwACQkQIDsRAJcCAAwACQkQIDsRAJcCAAAA.Reyz:BAABLgAECn8ZAAIMAAgJHBWGIQCnAQAMAAgJHBWGIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQABLgAECgUJBwABAAAAAA==.',
Rh='Rhaegos:BAABLgAECn8bAAMYAAcJcxqAAADGAQAYAAcJcxqAAADGAQARAAMJuRSNJwCvAAAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Robinavitch:BAAALgADCgYJCQAAAA==.Roblox:BAAALgAECgUJBgAAAA==.Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8mAAIEAAcJPyI6BgAXAQAEAAcJPyI6BgAXAQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
Ru='Runswithu:BAAALgADCgUJBQAAAA==.',
Ry='Rythmias:BAAALgAFFAEJAQAAAA==.Ryvive:BAAALgADCgkJEQAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAFFAUJEgAPAE0eAA==.',
['Rë']='Rëz:BAAALgAECgUJBwAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAECgcJFAAEACMbAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8xAAMjAAkJ1yJWBgDSAgAjAAkJ1yJWBgDSAgAUAAYJUhnLaABUAQABLgAECgkJNAAJACMhAA==.Scripts:BAABLgAECn8UAAIDAAYJDRfcDQC+AAADAAYJDRfcDQC+AAAAAA==.Scubasham:BAAALgAECgEJAQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJIAAOAPcNAA==.Serket:BAAALgAECgEJAQABLgAECgkJOAAPAKoiAA==.',
Sh='Shadowyarrow:BAAALgAECgYJCAAAAA==.Shakker:BAAALgADCgQJBAAAAA==.Shale:BAACLgAFFH8LAAIRAAMJrg6+CwCNAAARAAMJrg6+CwCNAAAuAAQKf1gABBEACQmOGVAIAGoCABEACQmOGVAIAGoCABAACQlBDJgvAHoBABgAAQmNA5srAB8AAAAA.Shamboo:BAAALgADCgkJEgAAAA==.Shames:BAAALgADCgEJAQAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAACLgAFFH8FAAIaAAMJ3RZ1MgDGAAAaAAMJ3RZ1MgDGAAAuAAQKfxkAAxoABwkKHIssAJMBABoABwkKHIssAJMBACkABAnmDFF0AL8AAAAA.Shamyhagar:BAAALgAECggJEAAAAA==.Sharaiya:BAABLgAECn8sAAIbAAkJvgX1awDwAAAbAAkJvgX1awDwAAAAAA==.Sharkmanfive:BAAALgAECgUJBQAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Sherp:BAAALgAECgUJBgAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAABLgAECn84AAMPAAkJqiJjBgAuAwAPAAkJqiJjBgAuAwAhAAEJJRGYhgA2AAAAAA==.Sioux:BAAALgAECgUJEAAAAA==.',
Sk='Skippybmm:BAAALgAECgYJEQABLgAECgcJHAAFAHwSAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgUJBgABLgAECgkJQAAkAAEeAA==.',
Sl='Slappydappy:BAAALgAFFAIJAgABLgAFFAgJFAACANsXAA==.Sledgehammer:BAAALgAECgIJAgAAAA==.Slid:BAAALgAECgQJBAAAAA==.',
Sm='Smexyshâmmy:BAAALgAECggJEAAAAA==.',
So='Soferus:BAAALgADCggJCAABLgAECgcJGwAYAHMaAA==.Sohc:BAAALgAECgEJAQAAAA==.Solaire:BAACLgAFFH8NAAIVAAUJSRpxBgAYAQAVAAUJSRpxBgAYAQAuAAQKfy4AAhUACQn+ILkBADMDABUACQn+ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJuR6RFQCkAgADAAkJuR6RFQCkAgABLgAFFAgJJgAUAPoYAA==.Soulful:BAAALgAECgYJBgAAAA==.Souljaz:BAAALgAECgMJBgAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAbALkPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spaghettios:BAAALgAECgIJAgAAAA==.Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAABLgAECn8cAAIFAAcJfBJuHwA3AQAFAAcJfBJuHwA3AQAAAA==.Spyy:BAAALgAECgYJCwAAAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgQJCgAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn9JAAMTAAkJgyITAgAzAwATAAkJgyITAgAzAwAhAAcJKBXiFgD+AAAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECgkJRQAiAN0RAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8hAAMIAAkJ3ReDBQAWAgAIAAkJ3ReDBQAWAgADAAEJlQGuZQEaAAAAAA==.Tankinit:BAAALgAECgUJEwAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgAECgEJAQABLgAECgUJCgABAAAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.Tattered:BAAALgADCgEJAQABLgAECgMJAwABAAAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIVAAMJswgGBACcAAAVAAMJswgGBACcAAAuAAQKfyUAAhUACAkJHX0GAIACABUACAkJHX0GAIACAAAA.Tenzink:BAABLgAECn8vAAIMAAkJJhy9AQBFAgAMAAkJJhy9AQBFAgAAAA==.',
Tf='Tflow:BAAALgAECgUJBAABLgAECgkJOwAUAGUfAA==.',
Th='Thalon:BAAALgAFFAEJAQABLgAFFAQJFQAJANscAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgAECgEJAgAAAA==.Thedru:BAABLgAECn9AAAIbAAgJTBA+RQB8AQAbAAgJTBA+RQB8AQAAAA==.Therodron:BAAALgAECgEJAQAAAA==.Thrastus:BAAALgAECgEJAQAAAA==.Thrus:BAABLgAECn8XAAMNAAgJjBAoKgBrAQANAAgJjBAoKgBrAQAMAAYJqQ54WQANAQABLgAECgkJQAAkAAEeAA==.Théworld:BAABLgAECn8YAAIRAAYJlBXhAgDRAAARAAYJlBXhAgDRAAAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgYJBwABLgAECgkJKQAOAFwaAA==.',
Tl='Tlnks:BAAALgADCgQJBwAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Tokeon:BAAALgAECgEJAQAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAACLgAFFH8HAAITAAMJ7g4AIADYAAATAAMJ7g4AIADYAAAuAAQKfyUAAhMACQktIGcEAOcCABMACQktIGcEAOcCAAAA.',
Tr='Traddles:BAAALgAECgEJAQAAAA==.Traler:BAAALgAECgIJAgABLgAECgkJRgAfABUVAA==.Tralzitashan:BAABLgAECn88AAMnAAkJMhMQAwAEAgAnAAkJMhMQAwAEAgAOAAQJzAMXIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAIOAAcJWhq0ZQAMAgAOAAcJWhq0ZQAMAgAAAA==.Tren:BAAALgAECgEJAgAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.Tuonetar:BAAALgADCgEJAQAAAA==.',
Tw='Twohammabray:BAAALgAECgYJCAAAAA==.',
Ty='Tyrdonut:BAAALgAECgEJAQABLgAECggJIQAYAEkLAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Ub='Ubie:BAAALgADCgQJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAABLgAECn8YAAMZAAcJ2BItLAD5AAAZAAYJZhMtLAD5AAASAAIJDRQgLQBuAAAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAACLgAFFH8JAAIKAAMJpR0UVwACAQAKAAMJpR0UVwACAQAuAAQKfxkAAgoACQnlJNkIACMDAAoACQnlJNkIACMDAAAA.Unglausp:BAACLgAFFH8IAAIGAAMJMxehIwDYAAAGAAMJMxehIwDYAAAuAAQKfycAAgYACAn9HtINAKYCAAYACAn9HtINAKYCAAEuAAUUAwkJAAoApR0A.Unholychild:BAAALgADCgMJAwAAAA==.',
Uz='Uzington:BAACLgAFFH8bAAIFAAUJyxU7FQD2AAAFAAUJyxU7FQD2AAAuAAQKfyYAAgUACQmyHPQIAI8CAAUACQmyHPQIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgIJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAABLgAECn8fAAIDAAkJ4gcfFAB0AAADAAkJ4gcfFAB0AAAAAA==.Valorien:BAACLgAFFH8TAAIKAAUJ8xx8MABRAQAKAAUJ8xx8MABRAQAuAAQKfyIAAgoACQnhG+FAAAQCAAoACQnhG+FAAAQCAAAA.Valzlok:BAAALgAECgMJAwAAAA==.Vanillacream:BAAALgADCgEJAQAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgATAC0jAA==.Velinieron:BAABLgAECn8eAAITAAkJLSNPBQC8AgATAAkJLSNPBQC8AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgATAC0jAA==.Vellash:BAABLgAECn8cAAIjAAYJxQoPOQDVAAAjAAYJxQoPOQDVAAAAAA==.Vendétta:BAABLgAECn85AAIPAAkJmxPTCQBaAQAPAAkJmxPTCQBaAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8hAAIOAAkJkQn1ewCAAQAOAAkJkQn1ewCAAQAAAA==.Vilencia:BAAALgADCgcJBwAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgAECgEJAQAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8zAAIPAAkJ/RcIJABTAgAPAAkJ/RcIJABTAgAAAA==.',
Vy='Vylon:BAAALgAECgQJBgABLgAECgcJCgABAAAAAA==.Vynlandis:BAACLgAFFH8GAAIJAAMJyQi2NwDFAAAJAAMJyQi2NwDFAAAuAAQKfz4AAwkACQnnGIkwAD0CAAkACQnnGIkwAD0CABIAAwmBBA0vAGMAAAAA.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAbALkPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Wargg:BAAALgAECgYJBgABLgAECgkJHQAjAFsbAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAABLgAECn8gAAIGAAcJghWDAwBqAQAGAAcJghWDAwBqAQAAAA==.Weenbean:BAABLgAFFH8FAAIQAAMJ8hEVOgDeAAAQAAMJ8hEVOgDeAAAAAA==.Werebray:BAAALgAFFAMJAwAAAA==.',
Wh='Whaco:BAABLgAECn8fAAIVAAgJmBt5DQDuAQAVAAgJmBt5DQDuAQAAAA==.Whatisaggro:BAABLgAECn8aAAIEAAgJTBo4JgDGAQAEAAgJTBo4JgDGAQAAAA==.Whispertree:BAABLgAECn8xAAIcAAkJZiIvCADRAgAcAAkJZiIvCADRAgAAAA==.White:BAAALgAECggJDQABLgAFFAYJDAATAJQSAA==.Whosoevers:BAAALgADCgEJAgAAAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECggJIQAYAEkLAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8aAAMJAAUJ7CBJQAB2AQAJAAUJ7CBJQAB2AQASAAIJwRCKHgCRAAAuAAQKfysAAwkACQkrIWINAC8DAAkACQkrIWINAC8DABIAAQl9HV8yAFMAAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8uAAQZAAcJNxnqFADDAQAZAAYJmx3qFADDAQAJAAcJoxIGkABGAQASAAIJcxhNEgBsAAAAAA==.Wixypoo:BAACLgAFFH8IAAILAAMJOBSONQDQAAALAAMJOBSONQDQAAAuAAQKfzQAAwsACQnoHcILAHkCAAsACQnoHcILAHkCAAwAAQnpAUfXABsAAAAA.',
Wo='Wockyslush:BAABLgAECn8kAAIeAAkJfSTpCAADAwAeAAkJfSTpCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.Woodnzhood:BAAALgAECgIJAwAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMQAAkJWhjTGAAQAgAQAAkJWhjTGAAQAgAYAAYJwAMuKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8gAAIpAAkJ2BsGGQCCAgApAAkJ2BsGGQCCAgAAAA==.',
Wy='Wyyn:BAABLgAECn85AAIOAAkJ1woNcACaAQAOAAkJ1woNcACaAQAAAA==.',
['Wâ']='Wâññabépàllý:BAAALgAECgEJAQAAAA==.',
Xa='Xanboi:BAABLgAECn9EAAMTAAkJ7yQtAgAuAwATAAkJ7yQtAgAuAwAPAAIJ6iK1iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Xy='Xyooj:BAAALgAECgIJAwAAAA==.',
Ya='Yaga:BAACLgAFFH8QAAIEAAUJQSDSFwBUAQAEAAUJQSDSFwBUAQAuAAQKfycAAgQACQndIRINAO0CAAQACQndIRINAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Yo='Yona:BAAALgADCgIJAgABLgAECgkJIAAOAPcNAA==.',
Ys='Ysar:BAABLgAECn8eAAIQAAkJAA+6KQCaAQAQAAkJAA+6KQCaAQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMYAAcJ6RqJDgDyAQAYAAYJkB+JDgDyAQAQAAYJGxdJIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECggJKQAVACcUAA==.',
Ze='Zeebu:BAABLgAECn8zAAITAAkJ5gpsGwDCAQATAAkJ5gpsGwDCAQAAAA==.Zenboi:BAABLgAECn8cAAIUAAgJ1RUcQwDnAQAUAAgJ1RUcQwDnAQAAAA==.Zephryyn:BAABLgAECn8gAAMpAAcJ3gT4fwDhAAApAAcJ3gT4fwDhAAAaAAcJggWPCQC6AAAAAA==.',
Zh='Zhakareth:BAAALgAECgMJAwABLgAECgkJJQAeAKMZAQ==.Zhilan:BAABLgAECn8gAAIbAAcJbxvCAQApAgAbAAcJbxvCAQApAgAAAA==.',
Zi='Ziet:BAAALgAECgQJBAAAAA==.Zinako:BAAALgAECgcJBAAAAA==.Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoda:BAAALgAECgUJBQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAUJDQAkAJIhAA==.Zoko:BAAALgAFFAEJAQAAAA==.Zophos:BAAALgAECggJDwABLgAECggJFgAIAAQPAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgIJAwAAAA==.Zuzuk:BAAALgAECggJEwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAABLgAECn8UAAIJAAcJ8Q5OkwBAAQAJAAcJ8Q5OkwBAAQAAAA==.Zuzuzi:BAAALgADCgUJBQAAAA==.',
['Zú']='Zúz:BAABLgAECn8XAAMHAAcJnBmzHgDPAQAHAAcJnBmzHgDPAQAGAAYJ8xJ/CgCoAAAAAA==.',
['Áß']='Áßomination:BAAALgAECgUJCAAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAACLgAFFH8FAAIpAAIJMAKCdwBQAAApAAIJMAKCdwBQAAAuAAQKfywAAikACQkgDY9OAHcBACkACQkgDY9OAHcBAAAA.',
['Ði']='Ðittø:BAABLgAECn8XAAIOAAkJtwhcgQB1AQAOAAkJtwhcgQB1AQABLgAFFAMJCgAZAP8QAA==.',
['Öd']='Ödorodun:BAAALgAECgIJBQAAAA==.',
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
