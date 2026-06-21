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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Priest-Shadow','Priest-Holy','Warlock-Destruction','DeathKnight-Unholy','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Preservation','DeathKnight-Frost','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection','Shaman-Enhancement','Priest-Discipline','Evoker-Devastation','DeathKnight-Blood','Shaman-Elemental','Druid-Restoration','Druid-Balance','Warlock-Affliction','Rogue-Subtlety','Druid-Feral','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Outlaw','Druid-Guardian','Rogue-Assassination','Mage-Arcane','Mage-Fire','Warrior-Arms','Shaman-Restoration',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aalduin:BAAALgAECgMJBAABLgAECgYJBgABAAAAAA==.Aarrana:BAAALgADCgYJCQAAAA==.',
Ac='Acupuncher:BAAALgAECgMJAwAAAA==.',
Ad='Ademai:BAAALgAECgYJBgAAAA==.',
Ae='Aephiona:BAAALgAECgQJBAAAAA==.Aetna:BAAALgAECgYJBgABLgAFFAcJEwACALoXAQ==.',
Af='Affli:BAACLgAFFH8XAAIDAAYJyBX0LQCOAQADAAYJyBX0LQCOAQAuAAQKfysAAgMACQkUIEIbALECAAMACQkUIEIbALECAAAA.',
Ag='Agares:BAAALgAECgYJBgAAAA==.',
Ah='Ahzamir:BAABLgAECn8dAAIEAAgJ1h5DEQDGAgAEAAgJ1h5DEQDGAgAAAA==.',
Ai='Aiunar:BAABLgAECn8oAAIFAAgJHhadFgCPAQAFAAgJHhadFgCPAQAAAA==.Aiupriesty:BAABLgAECn8nAAMGAAgJDQyLMQBWAQAGAAgJDQyLMQBWAQAHAAYJcBMXSwC3AAABLgAECggJKAAFAB4WAA==.',
Ak='Aka:BAAALgAECgEJAQAAAA==.Akimo:BAAALgADCgEJAQAAAA==.',
Al='Alastiria:BAABLgAECn8YAAIIAAgJ8QlzFAALAQAIAAgJ8QlzFAALAQAAAA==.Aledrel:BAAALgADCgEJAQAAAA==.Aleiculous:BAABLgAECn8ZAAIJAAYJ0gyYvQABAQAJAAYJ0gyYvQABAQAAAA==.Aleinara:BAABLgAECn8bAAIKAAkJzwyBcgCJAQAKAAkJzwyBcgCJAQAAAA==.Aleridin:BAABLgAECn8rAAILAAkJHiUXAgBCAwALAAkJHiUXAgBCAwAAAA==.Alexsneaks:BAAALgAECgMJAwAAAA==.Alleriah:BAAALgADCgcJBwAAAA==.Allhanla:BAAALgAECgQJBgAAAA==.Allwynn:BAACLgAFFH8VAAIMAAYJRx4LFgDQAQAMAAYJRx4LFgDQAQAuAAQKfyMABAwACQlwGxYOALwCAAwACQlwGxYOALwCAA0ABwnhIEwAABUCAAsAAQlAIVxxAGIAAAAA.Alraa:BAAALgAECggJDwAAAA==.',
Am='Ammora:BAAALgADCgIJAgAAAA==.Amorianys:BAAALgAECgYJBgAAAA==.',
An='Androgynous:BAAALgAECgMJAwAAAA==.Andsey:BAAALgAECgQJCAAAAA==.Annore:BAABLgAECn8dAAIJAAkJdxLHUwDJAQAJAAkJdxLHUwDJAQAAAA==.Antihero:BAABLgAECn8hAAIJAAkJeiN5DgAnAwAJAAkJeiN5DgAnAwAAAA==.',
Ap='Aphelse:BAAALgADCgMJAwABLgAFFAYJFQAMAEceAA==.',
Aq='Aquiell:BAABLgAECn8kAAIOAAkJqxAkWQDSAQAOAAkJqxAkWQDSAQAAAA==.Aqular:BAABLgAECn8iAAIPAAgJzhUxAgB0AQAPAAgJzhUxAgB0AQAAAA==.',
Ar='Archile:BAAALgADCgYJBgAAAA==.Argyre:BAACLgAFFH8fAAIFAAYJtSRGBgDqAQAFAAYJtSRGBgDqAQAuAAQKf0cAAwUACQkkJe8BADUDAAUACQkkJe8BADUDAAQABQnNEBtiAM8AAAAA.Arkenomu:BAABLgAECn8lAAMQAAgJNRHzMgBoAQAQAAgJNRHzMgBoAQARAAcJagx1GgAzAQAAAA==.Arthûr:BAAALgAECgYJBgAAAA==.',
As='Asakaa:BAABLgAECn8vAAMSAAkJwgl+EgBRAQASAAkJwgl+EgBRAQAJAAYJsAHP7AClAAAAAA==.Asclepius:BAABLgAECn8jAAIRAAkJnQ+vDwDQAQARAAkJnQ+vDwDQAQAAAA==.Askmeific:BAAALgADCgUJBQAAAA==.Askmelic:BAAALgAECgEJAQAAAA==.Aslo:BAAALgADCgEJAQAAAA==.Asmira:BAAALgADCgYJCQAAAA==.Aspirin:BAAALgAECgYJEQAAAA==.Asynic:BAABLgAECn84AAMTAAgJcyHrEAAlAgATAAcJWSHrEAAlAgAPAAYJVx2/TQC5AQAAAA==.',
At='Atsunvhi:BAAALgAECgUJEwAAAA==.',
Av='Avadakedevra:BAABLgAECn8jAAMTAAcJKBNiJgBqAQATAAcJKBNiJgBqAQAPAAEJKwpFzQA5AAAAAA==.Aviana:BAAALgADCgUJBQAAAA==.',
Aw='Awooing:BAAALgAECgUJCQAAAA==.',
Az='Azareth:BAAALgADCgkJCQAAAA==.Azreal:BAAALgAECgcJDQAAAA==.Azumok:BAAALgAECgQJBAAAAA==.',
Ba='Babyfive:BAAALgADCgcJBwAAAA==.Bairn:BAAALgADCggJCwAAAA==.Bakedbean:BAAALgAFFAEJAQABLgAFFAEJBgAUAJwkAA==.Barackobooma:BAAALgAECgIJAgAAAA==.Bazerker:BAAALgAECgUJCQAAAA==.',
Bb='Bbqboom:BAAALgADCgEJAQAAAA==.',
Bd='Bday:BAABLgAECn8lAAIOAAgJnA+lfAB/AQAOAAgJnA+lfAB/AQAAAA==.',
Be='Beastcode:BAAALgAECggJCAAAAA==.Belgaria:BAABLgAECn8pAAMVAAgJJxTIEwCPAQAVAAgJJxTIEwCPAQAKAAcJgg1ilQBSAQAAAA==.Berryknight:BAACLgAFFH8FAAIJAAIJ3hOGygCYAAAJAAIJ3hOGygCYAAAuAAQKfy4AAwkACQlxG5cxADgCAAkACQlxG5cxADgCABIAAgnZD/8vAF8AAAAA.Berryqt:BAAALgAECgQJCQAAAA==.Bewlzeye:BAAALgAECgUJBwAAAA==.',
Bi='Bigjonmachne:BAACLgAFFH8LAAIJAAUJthrzVQBGAQAJAAUJthrzVQBGAQAuAAQKfxgAAgkACAlAG50vAEECAAkACAlAG50vAEECAAAA.Binky:BAAALgADCgEJAQAAAA==.',
Bl='Blackguyy:BAACLgAFFH8iAAIHAAYJ8CP/AgBbAgAHAAYJ8CP/AgBbAgAuAAQKfx8AAgcACQnOJIkDACIDAAcACQnOJIkDACIDAAAA.Blessmoo:BAABLgAECn8VAAIKAAgJwBflQgD+AQAKAAgJwBflQgD+AQAAAA==.Blinktodome:BAAALgAECgYJCgAAAA==.Bloodsail:BAAALgAECgUJBQAAAA==.Bloodydk:BAAALgAECgEJAQAAAA==.Bluestripee:BAAALgAECgEJAQAAAA==.Bluezugzug:BAAALgAECgMJBQAAAA==.',
Bo='Boababy:BAAALgADCgEJAQAAAA==.Bojakson:BAAALgADCgQJAwAAAA==.Bollux:BAABLgAECn8yAAIWAAkJ2hdmCQAmAgAWAAkJ2hdmCQAmAgAAAA==.Bomßer:BAAALgAECgMJBAAAAA==.Bonetatter:BAAALgAECgMJAwABLgAECgMJAwABAAAAAA==.Bongonnaink:BAABLgAECn80AAMGAAkJ9yANCQC9AgAGAAkJ9yANCQC9AgAXAAEJaBblVgA0AAAAAA==.Bonnieanne:BAAALgADCgEJAQAAAA==.Bonsaichi:BAAALgAECgkJEQAAAA==.Bownyxia:BAACLgAFFH8JAAIQAAMJQBaVEQD1AAAQAAMJQBaVEQD1AAAuAAQKfzYAAxAACQnIIpMFAAYDABAACQnIIpMFAAYDABgABAlHDvspAM4AAAEuAAUUCAkqAAkA4BwA.Bowtiekwondo:BAAALgADCgYJBgABLgAFFAgJKgAJAOAcAA==.Bowties:BAACLgAFFH8qAAMJAAgJ4BxZCgCSAgAJAAgJ4BxZCgCSAgAZAAEJAAC+WwAAAAAuAAQKf0MAAwkACQmUJjgCAHsDAAkACQmUJjgCAHsDABkACQk3GHkKAHECAAAA.',
Br='Braxchud:BAABLgAECn8/AAIaAAkJJhzEDwB3AgAaAAkJJhzEDwB3AgAAAA==.Braylith:BAAALgADCgUJBQAAAA==.Breezevape:BAABLgAECn8cAAIOAAkJixunMABWAgAOAAkJixunMABWAgAAAA==.Brewnwings:BAAALgAECgUJCgAAAA==.Brolance:BAAALgADCgMJBAAAAA==.Brotie:BAACLgAFFH8RAAIUAAQJGROQFAAuAQAUAAQJGROQFAAuAQAuAAQKfx0AAhQACQm9HQAZAH8CABQACQm9HQAZAH8CAAEuAAUUCAkqAAkA4BwA.',
Bu='Buahmdav:BAAALgADCgUJBQAAAA==.Bubbles:BAAALgAECgUJBQABLgAECgkJNwAEAHgkAA==.Bubsy:BAAALgADCgEJAQAAAA==.Buggybuzzy:BAAALgADCgYJDwAAAA==.Bulwark:BAAALgAECgEJAgAAAA==.Burial:BAAALgADCgcJCAAAAA==.Burntbiscuit:BAAALgADCgIJAgAAAA==.Buugada:BAAALgAECgQJEgAAAA==.',
Ca='Caarrl:BAAALgAECgQJCAAAAA==.Caedo:BAAALgAECgQJBAAAAA==.Cainblodhoof:BAAALgADCgEJAQAAAA==.Calas:BAAALgAECgMJBQAAAA==.Caliet:BAAALgADCgUJBQAAAA==.Calii:BAAALgADCgkJCwAAAA==.Calischism:BAAALgAECgYJCAAAAA==.Calistra:BAAALgADCgYJBgAAAA==.Calistriaa:BAAALgADCgQJBAAAAA==.Caplock:BAAALgAECgQJBQAAAA==.Capriestsun:BAAALgAECgQJBQAAAA==.Cardinova:BAABLgAECn8WAAITAAYJYQfTAQCZAAATAAYJYQfTAQCZAAAAAA==.Carlistria:BAAALgADCgEJAQAAAA==.Cartime:BAAALgAECgMJBAAAAA==.Cayllia:BAABLgAECn8jAAMbAAkJDCSOBABFAwAbAAkJDCSOBABFAwAcAAgJDCLZFQAgAgAAAA==.',
Ce='Celaris:BAAALgAECgUJDQAAAA==.',
Ch='Chaolang:BAAALgAFFAEJAQAAAA==.Chataykay:BAAALgAECgcJDgAAAA==.Cheon:BAAALgAECgYJCAAAAA==.Cherrypepsï:BAABLgAECn8cAAMHAAkJOQ/aKwCYAQAHAAkJOQ/aKwCYAQAXAAUJdgbwOADgAAAAAA==.Chinlen:BAAALgAECgEJAQAAAA==.Chipdip:BAAALgAECgUJBQAAAA==.Chivies:BAAALgAECggJDgABLgAECgkJNQAKAHoiAA==.Chronosdormi:BAAALgAECgQJBAAAAA==.',
Ci='Circë:BAABLgAECn8kAAIdAAkJKxhBBQA5AgAdAAkJKxhBBQA5AgAAAA==.Citrus:BAABLgAECn85AAITAAkJtBWFFAAAAgATAAkJtBWFFAAAAgAAAA==.',
Cl='Cliqdragon:BAAALgAECgkJAgAAAA==.Cliqdru:BAAALgAECgMJBwAAAA==.Cliqmonk:BAAALgAECgcJCAAAAA==.',
Cn='Cn:BAABLgAECn81AAIKAAkJeiJFFQDDAgAKAAkJeiJFFQDDAgAAAA==.',
Co='Cocoabutter:BAABLgAECn8cAAIOAAYJmBGxtgAXAQAOAAYJmBGxtgAXAQAAAA==.Cocochanel:BAAALgAECgQJBAABLgAECgkJHAAOAIsbAA==.Codeman:BAABLgAECn89AAMZAAkJSyMfBAD2AgAZAAkJSyMfBAD2AgAJAAEJEwvxdAEyAAAAAA==.Cody:BAAALgADCgcJBwABLgAECgkJPQAZAEsjAA==.Cogne:BAAALgAECgYJCQAAAA==.Cogni:BAAALgAECgYJDAAAAA==.Commiebear:BAACLgAFFH8aAAMMAAcJ+Be4GAC0AQAMAAYJGBa4GAC0AQANAAUJsBWhFgALAQAuAAQKf2MAAwwACQl2I8ADAHwDAAwACQl2I8ADAHwDAA0ABgloIXEbANQBAAAA.Contemplate:BAAALgAECgMJCAABLgAFFAIJBAABAAAAAA==.Cordine:BAAALgAFFAEJAQAAAA==.Corpsepoker:BAAALgAECgYJCgAAAA==.Corruptz:BAAALgAECgkJGwABLgAECgkJJQAeAKMZAQ==.',
Cr='Crashout:BAAALgAECgUJBQAAAA==.Crúsh:BAAALgAECgEJAQAAAA==.',
Ct='Ctk:BAAALgAECgEJAQAAAA==.',
Cu='Culluh:BAAALgAECgYJBgAAAA==.Cumbo:BAAALgAECgEJAQAAAA==.',
Cy='Cyers:BAABLgAECn8cAAIfAAYJFhxuGABNAQAfAAYJFhxuGABNAQAAAA==.',
Cz='Czin:BAABLgAECn83AAMEAAkJeCT4AQBaAwAEAAkJeCT4AQBaAwAFAAEJkQnBSwAlAAAAAA==.',
['Cï']='Cïel:BAAALgAECgUJBQAAAA==.',
Da='Daimao:BAAALgADCgMJAgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dalén:BAAALgAECgYJEwAAAA==.Damugly:BAAALgAECgIJAgAAAA==.Darcsides:BAAALgADCgQJCQAAAA==.Darthtater:BAAALgAECgEJAQAAAA==.Dasmuffenman:BAAALgADCgQJBAAAAA==.Dawtz:BAAALgAECgIJAgAAAA==.',
De='Deadasf:BAAALgADCgcJEAAAAA==.Deadstunz:BAAALgAECgYJCQAAAA==.Deathverses:BAACLgAFFH85AAIgAAgJsCZfAAAPAwAgAAgJsCZfAAAPAwAuAAQKfy4AAiAACQnjJikCAJYDACAACQnjJikCAJYDAAAA.Deerslayer:BAAALgAECgcJEAAAAA==.Deezknights:BAAALgAECgUJCAABLgAECgYJDgABAAAAAA==.Delter:BAABLgAECn8UAAIgAAgJuxyFHwAqAgAgAAgJuxyFHwAqAgABLgAECggJFAAgALscAA==.Deltritus:BAACLgAFFH8dAAIOAAgJIRpPEQBiAgAOAAgJIRpPEQBiAgAuAAQKfzQAAg4ACQnnI0QJADADAA4ACQnnI0QJADADAAEuAAQKCAkUACAAuxwA.Demaedra:BAAALgAECgMJAwAAAA==.Demoan:BAABLgAECn89AAIhAAkJKSOcAQALAwAhAAkJKSOcAQALAwAAAA==.Demonbiscuit:BAACLgAFFH8GAAIiAAQJ6x2gCAB9AQAiAAQJ6x2gCAB9AQAuAAQKfxoAAiIACAmlJsAEAPoCACIACAmlJsAEAPoCAAAA.Derpydawg:BAAALgAECgEJAQABLgAFFAUJGgAJAOwgAA==.Dethh:BAAALgADCgMJAwAAAA==.Deviancy:BAABLgAECn8XAAMCAAkJdxmOEgB9AgACAAkJdxmOEgB9AgAKAAEJpAU8xAEiAAABLgAECggJKAAMAPgfAA==.',
Dh='Dhruven:BAAALgADCggJCAAAAA==.',
Di='Dicoball:BAAALgADCgYJBgAAAA==.Diddyzbuizzy:BAABLgAECn8UAAIQAAYJ0A/ZWADQAAAQAAYJ0A/ZWADQAAAAAA==.Diese:BAAALgAECgYJCQAAAA==.Dikslapp:BAABLgAECn84AAIiAAkJbiKPBAD/AgAiAAkJbiKPBAD/AgAAAA==.Dinglebingle:BAAALgAECgEJAgAAAA==.Dipperton:BAAALgAECgEJAQABLgAECgcJFAAYAOkaAA==.Discrespect:BAACLgAFFH8LAAMXAAUJ4xENKAALAQAXAAQJYBQNKAALAQAHAAEJ8Qc3NQBBAAAuAAQKfyEABBcACQmaGoATAEUCABcACQmaGoATAEUCAAcABAkiCMhcAMAAAAYAAQkfAxmZAB8AAAAA.Distinct:BAAALgAECgkJCQABLgAECgkJPQAhACkjAA==.Distress:BAAALgAFFAIJBAAAAA==.Ditto:BAACLgAFFH8KAAIZAAMJ/xAELACbAAAZAAMJ/xAELACbAAAuAAQKfzwABBkACAmpHOsMAEECABkACAmpHOsMAEECAAkABwkpCyyrABsBABIAAwlBDt4PAJ4AAAAA.',
Dl='Dlitinaro:BAABLgAECn80AAMJAAkJIyG8IgB8AgAJAAkJBx+8IgB8AgAZAAkJcx72CQBzAgAAAA==.',
Do='Doesgriddy:BAACLgAFFH8JAAMRAAMJoxd9DQAHAQARAAMJoxd9DQAHAQAQAAEJHAkuZwA3AAAuAAQKfxkAAxEACAlwJLYDACADABEACAlwJLYDACADABAAAwlpGjBOAJcAAAAA.Dogecoinsz:BAAALgAECgQJBgABLgAECgcJDwABAAAAAA==.Dollette:BAAALgAECggJBQAAAA==.Donoph:BAABLgAECn89AAMCAAkJ/yPPAgB5AwACAAkJ/yPPAgB5AwAKAAEJQwwIoQEtAAAAAA==.Doomar:BAABLgAECn83AAMDAAkJjSG2GACPAgADAAkJTiG2GACPAgAIAAYJfR91CADGAQAAAA==.Doomsamdi:BAAALgAECgcJCAABLgAECgkJNwADAI0hAA==.Doomseph:BAAALgAECgEJAQABLgAECgkJNwADAI0hAA==.Dordire:BAAALgAECgYJBgAAAA==.Doreyn:BAAALgADCgQJBAABLgADCgEJAQABAAAAAA==.Dotudown:BAAALgAECgMJAwAAAA==.Dotzilla:BAAALgAECgQJBAAAAA==.',
Dr='Dradin:BAAALgAECgEJAQAAAA==.Dragindznuts:BAABLgAECn8fAAMDAAkJ6An9dABQAQADAAkJMAn9dABQAQAIAAYJ0AfvMQDxAAAAAA==.Dragoisua:BAAALgADCgEJAQAAAA==.Dragonssteel:BAAALgAECgUJDgAAAA==.Dragosh:BAAALgADCgIJAgAAAA==.Drakedonut:BAABLgAECn8hAAMYAAgJSQu+HwAwAQAYAAcJZwq+HwAwAQAQAAYJ9AoAUwDjAAAAAA==.Dreav:BAAALgAECgIJAgAAAA==.Drugar:BAABLgAECn8rAAIOAAkJnw83ewCCAQAOAAkJnw83ewCCAQAAAA==.Druidtyme:BAAALgAECgMJAwAAAA==.Drunkenkhan:BAAALgADCgEJAQAAAA==.Druv:BAACLgAFFH8FAAIEAAIJEx8IFQDCAAAEAAIJEx8IFQDCAAAuAAQKfxYAAgQACAneHbASALkCAAQACAneHbASALkCAAEuAAUUCQk/ABYA8iUA.',
Du='Duloc:BAAALgAECgUJCAAAAA==.Dumbledorc:BAAALgADCgEJAQAAAA==.Durandal:BAAALgAECgUJEwAAAA==.Duskbane:BAAALgAECggJEgABLgAECgkJJQAeAKMZAA==.',
Dy='Dynabol:BAACLgAFFH8GAAIUAAEJnCTFDABrAAAUAAEJnCTFDABrAAAuAAQKfzUAAxQACQkOJpICAF8DABQACQl8JZICAF8DACEACAkhJYYCANQCAAAA.',
['Dë']='Dëåth:BAAALgAECgYJBgAAAA==.',
['Dò']='Dòóm:BAAALgADCgcJDAABLgAFFAUJGgAJAOwgAA==.',
Eb='Eborsisk:BAAALgADCgYJBgAAAA==.',
Ee='Eelane:BAAALgAECgQJDQAAAA==.',
Ef='Effex:BAAALgAECgMJBAAAAA==.',
El='Ell:BAAALgAECgQJBgAAAA==.Eltain:BAAALgADCgEJAQAAAA==.',
Em='Eminnazen:BAAALgADCgkJDgAAAA==.',
En='Endurall:BAAALgAECgkJEQABLgAECgkJQAAjAAEeAA==.',
Es='Eshne:BAAALgADCgEJAQAAAA==.',
Eu='Eurydicee:BAAALgAECgQJBAAAAA==.',
Ev='Eveleigh:BAAALgAECgEJAQAAAA==.Everfale:BAAALgAECgIJAwABLgAECgkJJQAeAKMZAQ==.Eviny:BAAALgADCgcJCAAAAA==.',
Ex='Extratylenol:BAAALgADCgcJDgAAAA==.',
Fa='Facerollz:BAAALgAECgQJBwAAAA==.Fahlafflez:BAABLgAECn81AAIEAAkJIhs6GwAUAgAEAAkJIhs6GwAUAgAAAA==.Fallyandor:BAAALgADCgYJBgAAAA==.Faolsabre:BAABLgAECn8oAAIJAAkJSQxRZACfAQAJAAkJSQxRZACfAQAAAA==.Farkhaz:BAAALgADCgUJBQAAAA==.',
Fe='Felinieron:BAAALgADCgEJAQABLgAECgkJHgATAC0jAA==.Ferrous:BAAALgADCgYJBgAAAA==.',
Fi='Fishinfridge:BAABLgAECn9FAAQfAAkJpxRfCwAGAgAfAAkJlhRfCwAGAgAkAAYJVxGELAD9AAAbAAcJHQaodQDUAAAAAA==.Fizard:BAAALgADCgIJAgAAAA==.',
Fl='Flints:BAAALgADCgEJAQAAAA==.Flloyd:BAABLgAECn8vAAIbAAkJdBm2GACAAgAbAAkJdBm2GACAAgAAAA==.',
Fo='Folid:BAAALgAECgEJAgAAAA==.Forne:BAAALgAFFAEJAQAAAA==.Foxdk:BAAALgADCgYJBgAAAA==.',
Fr='Friede:BAABLgAECn8kAAICAAkJbB51CgDOAgACAAkJbB51CgDOAgAAAA==.Frostedphyre:BAAALgAECgkJDQAAAA==.',
Fu='Furrywhaco:BAABLgAECn8VAAIkAAkJ+RqICABlAgAkAAkJ+RqICABlAgAAAA==.Fuzzyspells:BAAALgAECgYJDAAAAA==.',
Ga='Gaft:BAABLgAECn8ZAAMKAAgJLxv2SwD/AQAKAAYJsB72SwD/AQAVAAYJ7xJ1IQAJAQAAAA==.Gaftard:BAAALgADCgEJAQAAAA==.Galdrys:BAAALgADCgEJAQAAAA==.Galvaldi:BAAALgAECgEJAQAAAA==.',
Ge='Genndra:BAAALgADCgMJAwAAAA==.Gero:BAAALgAECgIJAgAAAA==.',
Gh='Ghostbladez:BAABLgAECn8/AAMeAAgJKQrHKQBJAQAeAAgJAQjHKQBJAQAlAAYJVAkSFgDNAAAAAA==.',
Gi='Girthmaster:BAAALgADCgcJBwAAAA==.',
Gl='Gleebus:BAAALgADCgEJAQAAAA==.',
Gn='Gnight:BAAALgAECgkJBgAAAA==.',
Go='Gordez:BAAALgADCgYJDwAAAA==.Goththighs:BAABLgAECn8eAAQOAAgJsyQ4HwD4AgAOAAgJniQ4HwD4AgAmAAEJnCZFFQBzAAAnAAEJiSQ/DABrAAABLgAFFAEJBgAUAJwkAA==.',
Gr='Gravez:BAAALgAFFAMJAwABLgAECgkJJQAeAKMZAA==.Grawler:BAAALgAECgcJCwAAAA==.Greeny:BAAALgAFFAEJAQAAAA==.Grim:BAAALgAECgEJAQAAAA==.Grissa:BAAALgAECgQJCgABLgAECgcJCQABAAAAAA==.Grumpyhunter:BAAALgAECgcJEAABLgAECgkJOAAOAOsfAA==.',
Gu='Gumgumfury:BAAALgAECgQJDwAAAA==.Gus:BAAALgADCgMJAwAAAA==.',
Ha='Haehi:BAAALgADCgcJBwAAAA==.Haidies:BAAALgAECgUJDgABLgAFFAQJDQAbALkPAA==.Halzlok:BAABLgAECn8cAAIaAAcJ6Q8HRgAbAQAaAAcJ6Q8HRgAbAQAAAA==.Hammergold:BAAALgAECgEJAQAAAA==.Hammerplz:BAAALgADCgcJBwAAAA==.Hankdalton:BAAALgADCgEJAQAAAA==.Harandy:BAAALgAECgIJAgAAAA==.Harvester:BAAALgAECgMJAgAAAA==.Haylonor:BAAALgADCgIJAgAAAA==.',
He='Healmedaddy:BAAALgADCgUJBQAAAA==.Hebofan:BAAALgAECgQJBQAAAA==.Hellas:BAAALgAECgQJBgABLgAFFAYJHwAFALUkAA==.Herøn:BAAALgAECgUJAQAAAA==.',
Hi='Highglide:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Hitmonchan:BAAALgAECgUJBwABLgAECggJKAAbAAYlAA==.',
Ho='Holybiscuit:BAAALgADCgcJCQABLgAFFAQJBgAiAOsdAA==.Hondacivic:BAAALgAECgEJAQABLgAECgkJJAAeAH0kAA==.',
Hu='Hukowa:BAAALgADCgYJBgAAAA==.Hunterschmax:BAAALgAECggJCQAAAA==.',
Hy='Hycinadra:BAAALgADCgcJFgAAAA==.',
Ia='Iandis:BAAALgADCgYJDwABLgAECgcJHAAFAHwSAA==.',
Ib='Ibuprofen:BAAALgADCgIJAgAAAA==.',
Ic='Iciaalta:BAAALgAECgYJDgAAAA==.',
Ih='Ihot:BAAALgAECgQJBgAAAA==.',
Ik='Ikayhaimahn:BAACLgAFFH8LAAIkAAQJ1RsMDgAdAQAkAAQJ1RsMDgAdAQAuAAQKfxgAAiQACQkNGe0JAEkCACQACQkNGe0JAEkCAAAA.',
Im='Imysteriöus:BAABLgAECn8oAAMbAAgJBiXzBgBJAwAbAAgJBiXzBgBJAwAfAAYJHhSJEgCFAQAAAA==.Imæge:BAAALgAECgYJBgAAAA==.',
In='Indicajones:BAAALgAECgYJDwAAAA==.Indipally:BAACLgAFFH8WAAICAAUJQx3jFACDAQACAAUJQx3jFACDAQAuAAQKfxcAAgIACAlAHJ0bADcCAAIACAlAHJ0bADcCAAAA.Indishaman:BAAALgAECgYJDAAAAA==.',
Ip='Iphonepromax:BAAALgAECgcJBwABLgAECgkJNQAKAHoiAA==.',
Is='Ishamael:BAABLgAECn80AAIGAAkJUxIvIgC2AQAGAAkJUxIvIgC2AQAAAA==.',
Iw='Iwilleatu:BAAALgADCgcJBwAAAA==.Iwillknifeu:BAAALgADCgQJAwAAAA==.',
Ja='Jabronygos:BAACLgAFFH8LAAIYAAQJBhiyAwA4AQAYAAQJBhiyAwA4AQAuAAQKfywAAhgACQkHIngBAOACABgACQkHIngBAOACAAAA.Jakett:BAAALgADCgEJAQAAAA==.Jarnroz:BAAALgAECgQJBAABLgAECgUJCgABAAAAAA==.Jaythirian:BAABLgAECn8YAAMoAAcJrQ6JEACUAQAoAAcJrQ6JEACUAQAEAAQJ1gQVgQC5AAAAAA==.',
Je='Jeatalena:BAAALgADCgMJAwAAAA==.Jerg:BAACLgAFFH8NAAIbAAQJuQ9FMwDgAAAbAAQJuQ9FMwDgAAAuAAQKfzkAAxsACQlUHtgWAH8CABsACAmfHdgWAH8CABwABwk3FlouAGgBAAAA.Jessup:BAACLgAFFH8NAAMjAAQJkiGBCAD3AAAjAAQJHh+BCAD3AAAeAAIJuxuKMwCTAAAuAAQKfyoAAx4ACQmKIn8EAFADAB4ACQn8IX8EAFADACMABQl9IRkKAIIBAAAA.',
Jh='Jhara:BAABLgAECn8eAAIOAAgJXA/DgAB2AQAOAAgJXA/DgAB2AQAAAA==.',
Ju='Juicehead:BAAALgADCgYJBgAAAA==.Junior:BAACLgAFFH8FAAQGAAMJ6g7NJQDKAAAGAAMJ6g7NJQDKAAAXAAEJiwYZUAA2AAAHAAEJzAjzOQAuAAAuAAQKfywABBcACQkQJJ4GAN4CABcACQlNI54GAN4CAAcABQm3IXUeANEBAAYABQnQHGQ1AEABAAEuAAUUBgkVAAwARx4A.Junnai:BAAALgADCgcJBwAAAA==.Jutai:BAAALgADCgcJDgAAAA==.',
Ka='Kablinkiaa:BAAALgAECggJDgAAAA==.Kaeydun:BAAALgAECgEJAQAAAA==.Kagamie:BAAALgADCgYJCQAAAA==.Kaiola:BAAALgAECgYJCwAAAA==.Kalistria:BAAALgAECgUJBgAAAA==.Kamekazi:BAAALgAECgMJAwAAAA==.Kariva:BAACLgAFFH8IAAIHAAMJTA0RBABdAAAHAAMJTA0RBABdAAAuAAQKf0kAAgcACQlVG3gKAL8CAAcACQlVG3gKAL8CAAAA.Katacemic:BAABLgAECn8qAAIZAAkJcRX9EAD7AQAZAAkJcRX9EAD7AQAAAA==.Katastrophic:BAAALgADCggJEAABLgAECgkJKgAZAHEVAA==.Katazul:BAABLgAECn8iAAMIAAkJXwqrJgArAQADAAkJewe+cABZAQAIAAYJzgqrJgArAQABLgAECgkJKgAZAHEVAA==.Kaulike:BAAALgADCgIJAgAAAA==.Kayssa:BAAALgAECgUJBQAAAA==.',
Ke='Keelanllan:BAABLgAECn8cAAIiAAkJTAh6KgArAQAiAAkJTAh6KgArAQAAAA==.Keilun:BAEALgAECgcJDAAAAA==.Kertzz:BAAALgADCgcJCAABLgAECgMJAwABAAAAAA==.Kew:BAABLgAECn8bAAIOAAcJLxjvWQDQAQAOAAcJLxjvWQDQAQAAAA==.Kewkew:BAAALgADCgcJDAAAAA==.',
Ki='Kiarina:BAAALgADCgYJEQAAAA==.Killerboomy:BAAALgAECgQJBAABLgAECgkJIwARAJ0PAA==.Killinko:BAAALgADCgMJAwAAAA==.Kirsche:BAAALgADCgUJBQABLgAECggJJQAQADURAA==.Kizira:BAAALgADCgMJAwAAAA==.',
Kn='Kneecromance:BAABLgAFFH8FAAMZAAIJpAmnRwAWAAAJAAIJpAkN7AB+AAAZAAEJXQCnRwAWAAAAAA==.Knightxl:BAAALgAECgYJBgAAAA==.',
Ko='Koggmaw:BAAALgAECgcJEAABLgAFFAQJDQAbALkPAA==.Kokuten:BAAALgAECgEJAQABLgAECgkJIAApANgbAA==.Koral:BAAALgAECgYJBgAAAA==.',
Kr='Kralj:BAAALgAECgUJCAAAAA==.',
Ku='Kungfucode:BAAALgAECgEJAQABLgAECgkJPQAZAEsjAA==.Kungfuhealya:BAABLgAECn8hAAMMAAgJcgiJWgAJAQAMAAgJcgiJWgAJAQANAAEJwQE9wAAYAAAAAA==.Kuraj:BAAALgAECgEJAQAAAA==.Kurisatroll:BAAALgAECgcJAwAAAA==.',
La='Laeral:BAAALgAECgcJEQAAAA==.Landaxx:BAAALgAECgQJBQABLgAECgcJFAAKAPkbAA==.Larrydale:BAABLgAECn8fAAMPAAgJTxwTGQByAgAPAAgJTxwTGQByAgATAAEJqQMDMgAsAAAAAA==.Latex:BAAALgADCgUJBQAAAA==.Laxdan:BAAALgAECgQJBQABLgAECgcJFAAKAPkbAA==.Lazydaze:BAAALgAECgYJCgAAAA==.Lazyriver:BAABLgAECn81AAQJAAkJ/RGEYwChAQAJAAcJfBCEYwChAQAZAAkJow2hHQBrAQASAAEJAABqRwAAAAAAAA==.',
Le='Lea:BAAALgAECgIJAgABLgAECgkJKQAOAFwaAA==.Lemón:BAAALgAECgEJAQAAAA==.Leofrich:BAAALgAECgMJBQAAAA==.Leondis:BAACLgAFFH8HAAIPAAIJcRbIggCVAAAPAAIJcRbIggCVAAAuAAQKfzMAAg8ACQl0IjQIAA0DAA8ACQl0IjQIAA0DAAAA.Leviosa:BAAALgAECgMJAgAAAA==.Lexipriest:BAACLgAFFH8hAAMHAAgJgBZhAgB4AgAHAAgJgBZhAgB4AgAXAAMJiQtgEADHAAAuAAQKf1EAAwcACQlrIVkEAD4DAAcACQlrIVkEAD4DABcACAkzHYcIALUCAAAA.',
Li='Liberation:BAAALgADCgMJAwAAAA==.Lightful:BAAALgAECgQJBAAAAA==.Lildobby:BAAALgADCgQJBAAAAA==.Lilpp:BAAALgAECgIJAgABLgAECgYJDgABAAAAAA==.',
Ll='Llamamamma:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Lloydak:BAAALgAECgkJCgAAAA==.',
Lo='Lobais:BAAALgADCgEJAgABLgAECgcJHAAFAHwSAA==.Lockmonster:BAAALgAECgIJAwAAAA==.Locksteady:BAAALgAECgcJCAAAAA==.Lokii:BAAALgAECgEJAwAAAA==.Lokì:BAAALgAECgEJAQABLgAECgkJOwAUAGUfAA==.Lookalock:BAAALgAECgQJBQAAAA==.Lorp:BAAALgAECgYJBwAAAA==.',
Lu='Luciffer:BAABLgAECn8lAAIUAAgJeB2EKQBcAgAUAAgJeB2EKQBcAgAAAA==.Lumosmaxiima:BAAALgAECgcJCwAAAA==.Lunadesangre:BAAALgAECgEJBAAAAA==.Lunarette:BAAALgAECgMJBQAAAA==.',
Ly='Lydax:BAABLgAECn8UAAIKAAcJ+RtqVwDcAQAKAAcJ+RtqVwDcAQAAAA==.Lylen:BAAALgADCgYJBgAAAA==.',
['Lö']='Lökï:BAAALgAECgEJAQAAAA==.',
Ma='Macet:BAAALgADCgcJBQAAAA==.Madamme:BAABLgAECn8XAAIpAAYJ9xi2QACrAQApAAYJ9xi2QACrAQAAAA==.Madkingzack:BAABLgAECn8gAAMEAAkJQSRpAwA0AwAEAAkJQSRpAwA0AwAoAAEJywaBgQAoAAAAAA==.Madpriest:BAAALgAECgQJBQAAAA==.Maevea:BAAALgAECgYJBwAAAA==.Malgar:BAAALgAECgEJAQAAAA==.Malistavias:BAABLgAECn8bAAMIAAkJZBD+EQApAQADAAkJywuJVwCWAQAIAAYJHxX+EQApAQAAAA==.Mallikii:BAABLgAECn8dAAMbAAkJ0hu9MADoAQAbAAkJ0hu9MADoAQAcAAQJrSMBOABZAQAAAA==.Malnar:BAAALgADCgEJAQAAAA==.Maokui:BAAALgADCgMJAgAAAA==.Maples:BAABLgAECn8gAAIOAAkJ9w3OcwCSAQAOAAkJ9w3OcwCSAQAAAA==.Marigosa:BAABLgAECn8bAAIOAAkJPAZgoAA6AQAOAAkJPAZgoAA6AQAAAA==.Marnolkas:BAAALgAECgEJAQABLgAECgUJDwABAAAAAA==.Mash:BAAALgADCgYJBgAAAA==.Mathan:BAACLgAFFH8FAAICAAMJ2Bs7BQBjAAACAAMJ2Bs7BQBjAAAuAAQKfygAAwoACQkLHkgaAKYCAAoACQkLHkgaAKYCAAIABwnWHiUWAFoCAAAA.Mattdemon:BAAALgAECgcJCQAAAA==.Maudib:BAABLgAECn8VAAIkAAgJSRU6JwAcAQAkAAgJSRU6JwAcAQAAAA==.Mawile:BAAALgAECgUJDQAAAA==.',
Me='Meautiful:BAAALgAECgQJBAAAAA==.Medusa:BAAALgAECgUJEwAAAA==.Meesha:BAAALgAECgMJBgAAAA==.Melas:BAAALgADCgYJEgAAAA==.Melinarra:BAABLgAECn8ZAAICAAYJ2RPwNwBuAQACAAYJ2RPwNwBuAQAAAA==.Melmiresa:BAAALgAECgEJAQAAAA==.Mendavo:BAABLgAECn8WAAQIAAgJBA97HABqAQAIAAcJYw57HABqAQADAAUJ/wrlxQDNAAAdAAEJ2hVmLgBBAAAAAA==.Merkxi:BAABLgAECn8tAAITAAkJBiJUAgAnAwATAAkJBiJUAgAnAwAAAA==.Messe:BAABLgAECn9AAAIjAAkJAR41AgCqAgAjAAkJAR41AgCqAgAAAA==.Mestre:BAAALgAECgYJDgAAAA==.Methious:BAABLgAECn8WAAIKAAkJnRg3agCqAQAKAAkJnRg3agCqAQAAAA==.',
Mi='Mikethepally:BAAALgAECgQJBwAAAA==.Milicious:BAAALgADCgMJAwAAAA==.Minigoober:BAAALgAECgQJBAAAAA==.',
Mo='Mogli:BAAALgAECgQJBAABLgAECgkJOwAUAGUfAA==.Mojokitten:BAAALgADCgcJBgAAAA==.Monkssuck:BAABLgAFFH8aAAILAAgJVglqDwCtAQALAAgJVglqDwCtAQAAAA==.Monktero:BAAALgAECgIJAwAAAA==.Montu:BAAALgAECggJDgAAAA==.Mooawdeeb:BAAALgAECgUJCQAAAA==.Moogyver:BAAALgADCgEJAgAAAA==.Moonrivr:BAAALgAECgUJCgABLgAECgkJNQAJAP0RAA==.Moonsguard:BAAALgAECgMJAwABLgAECgUJFwARAMQUAA==.Moosewillis:BAAALgAECgcJBwAAAA==.Moovit:BAABLgAECn8bAAMZAAYJvQdjPACfAAAZAAYJvQdjPACfAAAJAAEJugFwpgEZAAAAAA==.Moox:BAAALgADCgkJAQAAAA==.Mordekaíser:BAAALgAECgMJAgAAAA==.Morgannahkay:BAAALgAECgkJCQAAAA==.Mortja:BAAALgAECgMJAwAAAA==.',
Mu='Mudcrab:BAAALgAECgEJAQAAAA==.Munkee:BAAALgADCgEJAQAAAA==.Mustards:BAAALgAECgEJAgAAAA==.Musui:BAAALgADCgIJAgAAAA==.',
My='Myströnghand:BAAALgAECgcJBwAAAA==.',
['Må']='Mådd:BAAALgADCgMJAwAAAA==.',
Na='Nagumo:BAABLgAECn8mAAMIAAgJFQTyOQDMAAADAAgJ4wOurADqAAAIAAYJYAPyOQDMAAAAAA==.Nahual:BAAALgADCgQJBQAAAA==.Nala:BAABLgAECn8WAAMcAAgJqhE7NwA4AQAcAAcJvw47NwA4AQAbAAQJWBdtbgAJAQABLgAFFAQJDQAbALkPAA==.Nametaken:BAAALgADCgkJEAAAAA==.Narialle:BAACLgAFFH8GAAIQAAMJ9AuhSACoAAAQAAMJ9AuhSACoAAAuAAQKfy4AAxAACAklGF06AEIBABAABwkgF106AEIBABEABwllEkwaADUBAAEuAAUUBAkLACQA1RsA.Nastylock:BAAALgAECgEJAQAAAA==.',
Ne='Nekoya:BAAALgADCgMJAwABLgAECgUJBwABAAAAAA==.Nesaiana:BAAALgAECgMJAwAAAA==.Netharius:BAAALgAECgMJBwABLgAECgQJBAABAAAAAA==.Nevenel:BAAALgADCgEJAQAAAA==.',
Ni='Nibutaguata:BAACLgAFFH8MAAIUAAUJZR2TNgBKAQAUAAUJZR2TNgBKAQAuAAQKfzQAAxQACQnAJfMAANgDABQACQnAJfMAANgDACEAAQk3FKgzADUAAAAA.Nikhammer:BAAALgAECgMJAwAAAA==.Nitza:BAAALgAECgcJBwAAAA==.Nivan:BAABLgAECn8YAAMKAAgJnAfavAANAQAKAAgJBQbavAANAQAVAAEJXxKdTQA4AAAAAA==.Niço:BAACLgAFFH8HAAIPAAMJTxowWAD2AAAPAAMJTxowWAD2AAAuAAQKfxUAAg8ACQnPHKkfAEcCAA8ACQnPHKkfAEcCAAAA.',
No='Nodalmu:BAAALgAECgYJCAAAAA==.Noicce:BAABLgAECn8jAAIbAAkJJhs5HgBNAgAbAAkJJhs5HgBNAgAAAA==.Noiceply:BAAALgADCgkJEAAAAA==.Nolifehenry:BAABLgAECn8lAAIeAAkJoxnMDgA+AgAeAAkJoxnMDgA+AgAAAA==.Nordel:BAAALgADCgcJBwAAAA==.Nosaj:BAAALgADCgYJBgAAAA==.Notabu:BAAALgAECgMJAwAAAA==.Notcrims:BAAALgAECgEJAgAAAA==.',
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
Pa='Paboo:BAAALgAECgcJDAAAAA==.Pacmans:BAAALgAECgMJAwAAAA==.Parts:BAAALgAECgYJBgAAAA==.',
Pe='Pea:BAABLgAECn8pAAMOAAkJXBqCNgA/AgAOAAkJXBqCNgA/AgAnAAEJZQnKFQAoAAAAAA==.Perturabo:BAAALgAECgEJAgAAAA==.',
Ph='Phoenyx:BAABLgAECn8ZAAMIAAYJbApAHgC3AAAIAAYJbApAHgC3AAADAAUJjQGuFAFTAAAAAA==.',
Pl='Pleb:BAABLgAECn8cAAMPAAcJDx2zJAAqAgAPAAcJDx2zJAAqAgAgAAMJdQuDawCQAAAAAA==.',
Po='Pony:BAAALgAECggJCAABLgAECgkJIAAOAPcNAA==.',
Pr='Prettyfun:BAAALgADCgMJAwAAAA==.',
Pv='Pve:BAAALgAECgcJCQAAAA==.',
['Põ']='Põ:BAAALgAECgMJAwABLgAFFAMJBQACANgbAA==.',
Qu='Quorra:BAAALgAECgMJBAAAAA==.',
Ra='Radnads:BAAALgAECgMJBAAAAA==.Rahzy:BAABLgAECn8rAAIEAAkJcB7DEwCwAgAEAAkJcB7DEwCwAgAAAA==.Rakagar:BAABLgAECn8yAAIKAAkJOh6yIgB7AgAKAAkJOh6yIgB7AgAAAA==.Raktot:BAAALgAECgEJAQAAAA==.Ranko:BAAALgAECgkJBAAAAA==.Rawsushi:BAAALgADCgYJBgAAAA==.',
Re='Reia:BAAALgAFFAMJAwAAAA==.Reignman:BAAALgADCgEJAQAAAA==.Reue:BAACLgAFFH8gAAIMAAgJWhnUCAB9AgAMAAgJWhnUCAB9AgAuAAQKfy8AAgwACQkQIDwRAJYCAAwACQkQIDwRAJYCAAAA.Reyz:BAABLgAECn8ZAAIMAAgJHBWGIQCnAQAMAAgJHBWGIQCnAQAAAA==.Rezyrial:BAAALgAECgEJAQABLgAECgUJBwABAAAAAA==.',
Rh='Rhaegos:BAAALgAECgUJDwAAAA==.Rhux:BAAALgAECgIJAwAAAA==.',
Ri='Rillao:BAAALgADCggJEgAAAA==.',
Ro='Robinavitch:BAAALgADCgIJAgAAAA==.Roblox:BAAALgAECgUJBgAAAA==.Rocketgrab:BAAALgAECgcJDwAAAA==.Rogaldorn:BAAALgADCgEJAQAAAA==.Roid:BAABLgAECn8jAAIEAAYJTCHDKAC3AQAEAAYJTCHDKAC3AQAAAA==.Rotblair:BAAALgADCgIJAgAAAA==.',
Ru='Runswithu:BAAALgADCgUJBQAAAA==.',
Ry='Rythmias:BAAALgAECgUJCgAAAA==.Ryvive:BAAALgADCgkJEQAAAA==.',
['Rè']='Rèd:BAAALgAECgMJBAABLgAFFAUJDgAPAE0eAA==.',
['Rë']='Rëz:BAAALgAECgUJBwAAAA==.',
Sa='Salla:BAAALgAECgQJBQAAAA==.Saltyy:BAAALgAECgIJAgABLgAECgcJFAAEACMbAA==.Sanguindeath:BAAALgADCgEJAQAAAA==.Santaclause:BAAALgADCggJCQAAAA==.',
Sc='Scrapyjack:BAABLgAECn8xAAMiAAkJ1yJVBgDSAgAiAAkJ1yJVBgDSAgAUAAYJUhnLaABUAQABLgAECgkJNAAJACMhAA==.Scripts:BAAALgAFFAEJAQAAAA==.',
Se='Seph:BAAALgAECgIJAgABLgAECgkJIAAOAPcNAA==.',
Sh='Shadowyarrow:BAAALgAECgQJBAAAAA==.Shakker:BAAALgADCgQJBAAAAA==.Shale:BAACLgAFFH8IAAIRAAMJ6gprIgCQAAARAAMJ6gprIgCQAAAuAAQKf1gABBEACQmOGVIIAGoCABEACQmOGVIIAGoCABAACQlBDJYvAHoBABgAAQmNA5srAB8AAAAA.Shamboo:BAAALgADCgkJEgAAAA==.Shammit:BAAALgADCggJBwAAAA==.Shammydale:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Shammytyme:BAACLgAFFH8FAAIaAAMJ3RZ2MgDGAAAaAAMJ3RZ2MgDGAAAuAAQKfxkAAxoABwkKHIssAJMBABoABwkKHIssAJMBACkABAnmDFF0AL8AAAAA.Shamyhagar:BAAALgAECggJEAAAAA==.Sharaiya:BAABLgAECn8sAAIbAAkJvgX2awDwAAAbAAkJvgX2awDwAAAAAA==.Sharkmanfive:BAAALgAECgUJBQAAAA==.Shaure:BAAALgAECgUJBQAAAA==.Shearwater:BAAALgAECgYJCQAAAA==.Sheerburst:BAAALgAECgEJAQABLgAECgcJFAAEACMbAA==.Sherp:BAAALgAECgUJBgAAAA==.',
Si='Siantu:BAAALgADCgcJCQAAAA==.Siastraza:BAAALgADCgkJCQAAAA==.Silmeriaa:BAAALgADCggJCAAAAA==.Silversesu:BAABLgAECn82AAMPAAkJqiJmBgAuAwAPAAkJqiJmBgAuAwAgAAEJJRGYhgA2AAAAAA==.Sioux:BAAALgAECgUJEAAAAA==.',
Sk='Skippybmm:BAAALgAECgUJDgABLgAECgcJHAAFAHwSAA==.Skittlezqt:BAAALgADCgMJAwAAAA==.Skra:BAAALgAECgUJBgABLgAECgkJQAAjAAEeAA==.',
Sl='Slappydappy:BAAALgAFFAIJAgABLgAFFAcJEwACALoXAA==.Sledgehammer:BAAALgADCgUJBQAAAA==.Slid:BAAALgAECgQJBAAAAA==.',
Sm='Smexyshâmmy:BAAALgAECggJDgAAAA==.',
So='Soferus:BAAALgADCggJCAABLgAECgUJDwABAAAAAA==.Solaire:BAACLgAFFH8NAAIVAAUJSRpwBgAYAQAVAAUJSRpwBgAYAQAuAAQKfy4AAhUACQn+ILkBADMDABUACQn+ILkBADMDAAAA.Sonofalich:BAAALgADCgEJAQAAAA==.Soulflurry:BAABLgAECn8VAAIDAAkJuR6RFQCkAgADAAkJuR6RFQCkAgABLgAFFAgJJgAUAPoYAA==.Soulful:BAAALgAECgYJBgAAAA==.Souljaz:BAAALgADCgUJBQAAAA==.Soulweaver:BAAALgAECgEJAQABLgAFFAQJDQAbALkPAA==.Sourtofu:BAAALgADCgYJCAAAAA==.',
Sp='Spaghettios:BAAALgADCgEJAQAAAA==.Spalduing:BAAALgADCgYJBgAAAA==.Spedboi:BAAALgADCgcJDgAAAA==.Spine:BAABLgAECn8cAAIFAAcJfBJuHwA3AQAFAAcJfBJuHwA3AQAAAA==.Spyy:BAAALgAECgYJCwAAAA==.',
St='Starcast:BAAALgAECgEJAQAAAA==.Starryfire:BAAALgADCgMJAwAAAA==.Starrysky:BAAALgADCgEJAQAAAA==.Starsha:BAAALgAECgEJAQAAAA==.Starßurst:BAAALgAECgEJAQAAAA==.Steezey:BAAALgAECgEJAgAAAA==.Stunny:BAAALgAECgIJAwAAAA==.',
Su='Subzone:BAAALgAECgcJEgAAAA==.Sukas:BAAALgADCgUJBQABLgADCgEJAQABAAAAAA==.Sunmaster:BAAALgAECgQJCgAAAA==.',
Sv='Svecenica:BAAALgADCgYJBgABLgAECgIJAwABAAAAAA==.Svetha:BAABLgAECn9JAAMTAAkJgyIUAgAzAwATAAkJgyIUAgAzAwAgAAcJKBXhFgD+AAAAAA==.',
Sy='Synic:BAAALgADCgYJDgAAAA==.Synora:BAAALgAECgEJAQAAAA==.Syreous:BAAALgADCgMJAwABLgAECgkJRQAhAN0RAA==.',
Ta='Takz:BAAALgAECgEJAgAAAA==.Tandria:BAABLgAECn8hAAMIAAkJ3ReCBQAWAgAIAAkJ3ReCBQAWAgADAAEJlQGuZQEaAAAAAA==.Tankinit:BAAALgAECgQJEgAAAA==.Tanolden:BAAALgAECgUJCQAAAA==.Tanuudrot:BAAALgAECgEJAQABLgAECgUJCgABAAAAAA==.Tatterbone:BAAALgAECgMJAwAAAA==.Tattered:BAAALgADCgEJAQABLgAECgMJAwABAAAAAA==.',
Te='Tenstusî:BAACLgAFFH8GAAIVAAMJswgGBACcAAAVAAMJswgGBACcAAAuAAQKfyUAAhUACAkJHX0GAIACABUACAkJHX0GAIACAAAA.Tenzink:BAABLgAECn8mAAIMAAkJGRz1DwCmAgAMAAkJGRz1DwCmAgAAAA==.',
Th='Thalon:BAAALgAFFAEJAQABLgAFFAQJDgAJANscAA==.Thathurts:BAAALgADCgcJBwAAAA==.Thatsmyball:BAAALgADCgQJBAAAAA==.Thecoolguy:BAAALgAECgEJAgAAAA==.Thedru:BAABLgAECn9AAAIbAAgJTBBARQB8AQAbAAgJTBBARQB8AQAAAA==.Therodron:BAAALgAECgEJAQAAAA==.Thrastus:BAAALgAECgEJAQAAAA==.Thrus:BAABLgAECn8XAAMNAAgJjBAnKgBrAQANAAgJjBAnKgBrAQAMAAYJqQ53WQANAQABLgAECgkJQAAjAAEeAA==.Théworld:BAABLgAECn8XAAIRAAUJxBQNAQCFAAARAAUJxBQNAQCFAAAAAA==.',
Ti='Tindranga:BAAALgAECgQJBAAAAA==.Tip:BAAALgAECgYJBwABLgAECgkJKQAOAFwaAA==.',
Tl='Tlnks:BAAALgADCgQJBwAAAA==.',
To='Toefungus:BAAALgAECgYJCwAAAA==.Tokeon:BAAALgAECgEJAQAAAA==.Touché:BAAALgADCgcJBwAAAA==.Towani:BAACLgAFFH8GAAITAAMJyQ7/HwDYAAATAAMJyQ7/HwDYAAAuAAQKfyUAAhMACQktIGgEAOcCABMACQktIGgEAOcCAAAA.',
Tr='Traddles:BAAALgAECgEJAQAAAA==.Traler:BAAALgAECgEJAQABLgAECgkJRQAfAKcUAA==.Tralzitashan:BAABLgAECn88AAMmAAkJMhMQAwAEAgAmAAkJMhMQAwAEAgAOAAQJzAMXIgG8AAAAAA==.Trammatize:BAABLgAECn8aAAIOAAcJWhq0ZQAMAgAOAAcJWhq0ZQAMAgAAAA==.Tren:BAAALgAECgEJAQAAAA==.',
Tu='Tubbymuffins:BAAALgAECgEJAQAAAA==.',
Tw='Twohammabray:BAAALgAECgYJCAAAAA==.',
Ty='Tyrdonut:BAAALgAECgEJAQABLgAECggJIQAYAEkLAA==.',
['Tæ']='Tæn:BAAALgADCgMJBAAAAA==.',
Ub='Ubie:BAAALgADCgQJBAAAAA==.',
Uk='Ukonvasara:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Um='Umbrà:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.',
Un='Undeadnite:BAABLgAECn8WAAMZAAcJLRIqLAD5AAAZAAYJmREqLAD5AAASAAIJDRIhLQBuAAAAAA==.Undertakerz:BAAALgAECgIJAwAAAA==.Unglaus:BAACLgAFFH8JAAIKAAMJpR0lVwACAQAKAAMJpR0lVwACAQAuAAQKfxkAAgoACQnlJNcIACMDAAoACQnlJNcIACMDAAAA.Unglausp:BAACLgAFFH8IAAIGAAMJMxehIwDYAAAGAAMJMxehIwDYAAAuAAQKfycAAgYACAn9HtINAKYCAAYACAn9HtINAKYCAAEuAAUUAwkJAAoApR0A.Unholychild:BAAALgADCgMJAwAAAA==.',
Uz='Uzington:BAACLgAFFH8bAAIFAAUJyxU3FQD2AAAFAAUJyxU3FQD2AAAuAAQKfyYAAgUACQmyHPQIAI8CAAUACQmyHPQIAI8CAAAA.',
Va='Vaanthelos:BAAALgAECgIJAgAAAA==.Valeta:BAAALgAECgEJAgAAAA==.Vali:BAABLgAECn8cAAIDAAcJ9QdAqADxAAADAAcJ9QdAqADxAAAAAA==.Valorien:BAACLgAFFH8RAAIKAAUJ8xyMMABRAQAKAAUJ8xyMMABRAQAuAAQKfyEAAgoACAkgG+JAAAQCAAoACAkgG+JAAAQCAAAA.Valzlok:BAAALgAECgMJAwAAAA==.',
Ve='Veilthorn:BAAALgAECgQJBAAAAA==.Velinhealion:BAAALgAECgMJAwABLgAECgkJHgATAC0jAA==.Velinieron:BAABLgAECn8eAAITAAkJLSNPBQC8AgATAAkJLSNPBQC8AgAAAA==.Velinvile:BAAALgAECgYJBgABLgAECgkJHgATAC0jAA==.Vellash:BAABLgAECn8cAAIiAAYJxQoMOQDVAAAiAAYJxQoMOQDVAAAAAA==.Vendétta:BAABLgAECn8uAAIPAAkJthEKBAAEAQAPAAkJthEKBAAEAQAAAA==.Vengything:BAAALgAECgEJAQAAAA==.',
Vi='Vilandrious:BAABLgAECn8hAAIOAAkJkQn2ewCAAQAOAAkJkQn2ewCAAQAAAA==.Vilencia:BAAALgADCgcJBwAAAA==.Vince:BAAALgAECgEJAgAAAA==.Virgïl:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
Vl='Vlper:BAAALgAECgYJEAAAAA==.',
Vo='Voidchild:BAAALgAECgEJAQAAAA==.Voidslock:BAAALgAECgEJAQAAAA==.Vonulter:BAABLgAECn8zAAIPAAkJ/RcJJABTAgAPAAkJ/RcJJABTAgAAAA==.',
Vy='Vynlandis:BAABLgAECn8+AAMJAAkJ5xiGMAA9AgAJAAkJ5xiGMAA9AgASAAMJgQQOLwBjAAAAAA==.',
Wa='Wakanda:BAAALgAECgYJDQABLgAFFAQJDQAbALkPAA==.Warbezerker:BAAALgAECgIJAgAAAA==.Wargg:BAAALgAECgYJBgABLgAECgkJHQAiAFsbAA==.Warrything:BAAALgAECgEJAgAAAA==.',
We='Weaknoodle:BAABLgAECn8bAAIGAAcJ+xFzMgBRAQAGAAcJ+xFzMgBRAQAAAA==.Weenbean:BAABLgAFFH8FAAIQAAMJ8hEKOgDeAAAQAAMJ8hEKOgDeAAAAAA==.Werebray:BAAALgAFFAMJAwAAAA==.',
Wh='Whaco:BAABLgAECn8fAAIVAAgJmBt5DQDuAQAVAAgJmBt5DQDuAQAAAA==.Whatisaggro:BAABLgAECn8aAAIEAAgJTBo2JgDGAQAEAAgJTBo2JgDGAQAAAA==.Whispertree:BAABLgAECn8vAAIcAAkJ0CEvCADRAgAcAAkJ0CEvCADRAgAAAA==.White:BAAALgAECggJDQABLgAFFAYJCwATAJQSAA==.',
Wi='Wilddonut:BAAALgADCgUJBQABLgAECggJIQAYAEkLAA==.Williamld:BAAALgAECgEJAQAAAA==.Wiseguys:BAACLgAFFH8aAAMJAAUJ7CBWQAB2AQAJAAUJ7CBWQAB2AQASAAIJwRCNHgCRAAAuAAQKfysAAwkACQkrIWINAC8DAAkACQkrIWINAC8DABIAAQl9HV4yAFMAAAAA.Wisenhiem:BAAALgADCgMJAwAAAA==.Wixdk:BAABLgAECn8uAAQZAAcJNxnqFADDAQAZAAYJmx3qFADDAQAJAAcJoxIGkABGAQASAAIJcxhNEgBsAAAAAA==.Wixypoo:BAACLgAFFH8IAAILAAMJOBSaNQDQAAALAAMJOBSaNQDQAAAuAAQKfzQAAwsACQnoHcELAHkCAAsACQnoHcELAHkCAAwAAQnpAUfXABsAAAAA.',
Wo='Wockyslush:BAABLgAECn8kAAIeAAkJfSTpCAADAwAeAAkJfSTpCAADAwAAAA==.Wolfed:BAAALgADCgEJAQAAAA==.Woodnzhood:BAAALgADCgYJFwAAAA==.',
Wr='Wrylah:BAABLgAECn8kAAMQAAkJWhjUGAAQAgAQAAkJWhjUGAAQAgAYAAYJwAMuKADfAAAAAA==.',
Wu='Wuxian:BAABLgAECn8gAAIpAAkJ2BsFGQCCAgApAAkJ2BsFGQCCAgAAAA==.',
Wy='Wyyn:BAABLgAECn82AAIOAAkJ1woNcACaAQAOAAkJ1woNcACaAQAAAA==.',
Xa='Xanboi:BAABLgAECn9EAAMTAAkJ7yQuAgAuAwATAAkJ7yQuAgAuAwAPAAIJ6iK1iwDGAAAAAA==.',
Xe='Xelago:BAAALgAECgMJAwAAAA==.Xexeed:BAAALgADCgcJDgAAAA==.',
Ya='Yaga:BAACLgAFFH8QAAIEAAUJQSDhFwBUAQAEAAUJQSDhFwBUAQAuAAQKfycAAgQACQndIRINAO0CAAQACQndIRINAO0CAAAA.',
Yi='Yikkle:BAAALgADCgIJAQAAAA==.',
Yo='Yona:BAAALgADCgIJAgABLgAECgkJIAAOAPcNAA==.',
Ys='Ysar:BAABLgAECn8dAAIQAAkJag65KQCaAQAQAAkJag65KQCaAQAAAA==.',
Yu='Yujirogojo:BAAALgADCgUJBQAAAA==.Yulan:BAAALgAECggJEAAAAA==.',
Za='Zaddymurph:BAABLgAECn8UAAMYAAcJ6RqJDgDyAQAYAAYJkB+JDgDyAQAQAAYJGxdJIAC/AQAAAA==.Zalter:BAAALgADCgEJAQAAAA==.Zamarched:BAAALgAECgUJCgAAAA==.Zandrama:BAAALgADCggJCAABLgAECggJKQAVACcUAA==.',
Ze='Zeebu:BAABLgAECn8yAAITAAkJlQptGwDCAQATAAkJlQptGwDCAQAAAA==.Zenboi:BAABLgAECn8cAAIUAAgJ1RUcQwDnAQAUAAgJ1RUcQwDnAQAAAA==.Zephryyn:BAABLgAECn8ZAAIpAAcJ3gTyfwDhAAApAAcJ3gTyfwDhAAAAAA==.',
Zh='Zhakareth:BAAALgAECgMJAwABLgAECgkJJQAeAKMZAQ==.Zhilan:BAAALgAECgUJEQAAAA==.',
Zi='Ziet:BAAALgADCgMJAwAAAA==.Zinkei:BAAALgAECgYJDQAAAA==.',
Zo='Zoca:BAAALgADCgYJCQAAAA==.Zoda:BAAALgAECgUJBQAAAA==.Zoey:BAAALgAECgYJBgABLgAFFAUJDQAjAJIhAA==.Zoko:BAAALgAFFAEJAQAAAA==.Zophos:BAAALgAECggJDwABLgAECggJFgAIAAQPAA==.',
Zu='Zurgadhunter:BAAALgAECgUJCAAAAA==.Zurgazen:BAAALgAECgIJAwAAAA==.Zuzuk:BAAALgAECggJEwAAAA==.Zuzuki:BAAALgAECgQJBwAAAA==.Zuzukì:BAABLgAECn8UAAIJAAcJ8Q5PkwBAAQAJAAcJ8Q5PkwBAAQAAAA==.',
['Zú']='Zúz:BAABLgAECn8UAAMHAAcJNRmxHgDPAQAHAAYJpxuxHgDPAQAGAAYJ7gxGRwDyAAAAAA==.',
['Áß']='Áßomination:BAAALgAECgUJCAAAAA==.',
['Ða']='Ðalinar:BAAALgAECgYJCgAAAA==.Ðalinor:BAAALgAECggJCAAAAA==.',
['Ðe']='Ðemaea:BAACLgAFFH8FAAIpAAIJMAKAdwBQAAApAAIJMAKAdwBQAAAuAAQKfywAAikACQkgDYpOAHcBACkACQkgDYpOAHcBAAAA.',
['Ði']='Ðittø:BAABLgAECn8WAAIOAAkJ3AdegQB1AQAOAAkJ3AdegQB1AQABLgAFFAMJCgAZAP8QAA==.',
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
