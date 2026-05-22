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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Paladin-Holy','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Druid-Balance','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Priest-Holy','Hunter-Survival','Paladin-Protection','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgEJAQAAAA==.',
Af='Affae:BAABLgAFFH8GAAMBAAMJFBNFHQCOAAACAAIJ6RZFMwCSAAABAAIJPg5FHQCOAAAAAA==.',
Ag='Agrios:BAAALgAECgQJBAAAAA==.',
Ak='Ak:BAABLgAECn8oAAIDAAgJZSACIABjAgADAAgJZSACIABjAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECggJIwAEALYXAA==.',
Am='Amare:BAAALgAECgYJBgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgAECgQJBQAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8dAAIFAAYJARjCeAAoAQAFAAYJARjCeAAoAQAAAA==.Arroyo:BAABLgAECn8nAAMFAAgJ7CBaGABxAgAFAAgJ0CBaGABxAgAEAAQJyRufHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Askadar:BAACLgAFFH8MAAIGAAQJlCYcAwDDAQAGAAQJlCYcAwDDAQAuAAQKfy8AAgYACQlxJkwAAHgDAAYACQlxJkwAAHgDAAAA.',
At='Atinyhorse:BAABLgAECn8ZAAIHAAcJ2gsWawD7AAAHAAcJ2gsWawD7AAAAAA==.Atrax:BAAALgAECgQJBgAAAA==.Atryx:BAABLgAFFH8FAAIIAAMJBxBvEADiAAAIAAMJBxBvEADiAAAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDQAJAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azzura:BAAALgADCgMJAwAAAA==.',
Ba='Baheem:BAAALgAECgMJCAAAAA==.Bams:BAABLgAECn8YAAMKAAcJBhthIACLAQAKAAYJzB1hIACLAQALAAYJbwqOUgAAAQAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIMAAkJbSDzEQAbAgAMAAkJbSDzEQAbAgAAAA==.Bighoofprint:BAAALgADCgQJAwAAAA==.Bigtotempole:BAAALgAECgcJEQAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8jAAINAAgJ0xZkLQDWAQANAAgJ0xZkLQDWAQAAAA==.Blappin:BAAALgADCgYJDgAAAA==.Bloodmyst:BAAALgAECgMJBgABLgAECgkJIAAOAEEcAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgQJBAAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8bAAIPAAgJKBiuGQDsAQAPAAgJKBiuGQDsAQAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgADCgQJBAAAAA==.Bookwyrm:BAAALgADCgQJBAAAAA==.Boolil:BAAALgAECgQJCQABLgAECgkJJQAQAPMQAA==.Booqt:BAAALgAECggJCAABLgAECgkJJQAQAPMQAA==.',
Br='Breake:BAAALgAECgUJEAAAAA==.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8VAAMRAAYJRxLFMwALAQARAAYJqBHFMwALAQASAAQJkw1wEQCrAAAAAA==.',
Ca='Cailan:BAAALgADCgQJBQAAAA==.Caladiir:BAAALgAECgUJBQABLgAECgkJHwACAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJJwANAD0dAA==.',
Ce='Cerealmilk:BAAALgAECgYJCgAAAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgAJAAAAAA==.Childishbro:BAAALgADCgIJAgAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAAJAAAAAA==.Christopher:BAACLgAFFH8QAAIDAAUJAB9nJABwAQADAAUJAB9nJABwAQAuAAQKfxsAAgMACQn2IJwtALsCAAMACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAECgUJDQAJAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8fAAIGAAYJ5SSKAQAYAgAGAAYJ5SSKAQAYAgAuAAQKfyUAAgYACAkAIiEEAAoDAAYACAkAIiEEAAoDAAAA.',
Cr='Creepychaos:BAAALgADCgkJIwABLgAECggJMAAFAHUHAA==.Creepydemise:BAABLgAECn8wAAIFAAgJdQeoawBEAQAFAAgJdQeoawBEAQAAAA==.Creepyfoxxy:BAAALgADCgkJCQAAAA==.Croixsmash:BAABLgAECn8eAAIMAAgJzRhGIgBDAgAMAAgJzRhGIgBDAgAAAA==.Croixtemplar:BAAALgAECgUJBQAAAA==.',
Cu='Cuculain:BAAALgAECgEJAQAAAA==.Custodian:BAAALgAECgQJAwAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgEJAgAAAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8ZAAQTAAcJzQbxGACjAAAUAAYJ9QakkADbAAATAAYJ+QTxGACjAAAVAAEJAADFLQAAAAAAAA==.Davennial:BAABLgAECn8qAAIQAAgJSRJwTgCTAQAQAAgJSRJwTgCTAQAAAA==.Dawnn:BAAALgAECgYJDgAAAA==.Dayman:BAAALgAFFAEJAQAAAA==.',
De='Deanwnchestr:BAABLgAECn8UAAIDAAYJtQa1sADkAAADAAYJtQa1sADkAAAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAAALgAFFAMJAwAAAA==.Demise:BAAALgAECgQJBgAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHAABAB0hAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECgYJDQAAAA==.',
Do='Doregoran:BAAALgAECgcJEwAAAA==.Dovairous:BAAALgAECgYJEwAAAA==.',
Dr='Draakell:BAAALgAECgQJAwAAAA==.Dracopeet:BAABLgAECn8ZAAQRAAcJvwSuUQCOAAARAAUJ4wSuUQCOAAAWAAQJGwPDKQBTAAASAAMJwQKwHgAsAAAAAA==.Drausella:BAAALgADCgUJCAAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgMJAwAAAA==.',
Du='Dudè:BAAALgADCgkJCQAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgUJDQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8cAAIUAAYJXgoPigDoAAAUAAYJXgoPigDoAAAAAA==.',
Ed='Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgIJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8LAAMXAAQJuQ7RFwAUAQAXAAQJuQ7RFwAUAQAYAAEJTgDpWAAjAAAuAAQKfyAAAxcACQkwHlgVANABABcACQkwHlgVANABABgABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgQJCgAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8VAAIMAAcJ8AuwNQAhAQAMAAcJ8AuwNQAhAQAAAA==.Erodoria:BAABLgAECn8YAAMZAAgJAx6sCgAeAgAZAAcJ+yCsCgAeAgAaAAUJ/hCIDgASAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECggJGgAXADEUAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAECgMJAwABLgAFFAMJCQALAOcRAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAABLgAECn8dAAIIAAgJrhQeCQCZAQAIAAgJrhQeCQCZAQAAAA==.',
Fa='Falkor:BAABLgAECn8pAAIWAAkJqRZJCAAlAgAWAAkJqRZJCAAlAgAAAA==.Fanir:BAAALgADCgMJAwAAAA==.Fatkid:BAAALgAECgcJBgAAAA==.Fayway:BAABLgAECn8yAAIYAAkJsiEBBABRAwAYAAkJsiEBBABRAwAAAA==.',
Fe='Ferral:BAABLgAECn8gAAIOAAkJQRy1AgC0AgAOAAkJQRy1AgC0AgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAAALgAECgcJEgAAAA==.Firepower:BAABLgAECn8cAAIDAAgJOhYZPgDhAQADAAgJOhYZPgDhAQABLgAECggJIAAOAJcTAA==.Fistatoosh:BAABLgAECn8eAAICAAgJIiRTBADRAgACAAgJIiRTBADRAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAAOAJcTAA==.',
Fr='Fries:BAEBLgAECn8cAAMbAAkJACIAAQAPAwAbAAkJACIAAQAPAwALAAUJBgwfXADeAAABLgAFFAQJBwAUAKYPAA==.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIQAAgJnBqgKQB+AgAQAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgAJAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgAJAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAABLgAECn8UAAMMAAcJLhttKABqAQAMAAcJxhltKABqAQAcAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAAALgAECgcJEwAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgMJAwABLgAECgQJEgAJAAAAAA==.',
Gr='Greenbean:BAABLgAFFH8FAAIHAAQJKgQlPADpAAAHAAQJKgQlPADpAAABLgAFFAQJCwAXALkOAA==.Groddz:BAAALgAECggJEQAAAA==.Grrum:BAAALgAECgYJEwAAAA==.',
Ha='Hanjo:BAABLgAECn8kAAIGAAgJEyFnBQB+AgAGAAgJEyFnBQB+AgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAILAAcJixUvNgCqAQALAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA31JACvAQABAAgJzA31JACvAQAAAA==.Hatookorr:BAAALgAECgQJBAABLgAECggJIAAOAJcTAA==.Hayali:BAABLgAECn8aAAIHAAgJHRT1MwCrAQAHAAgJHRT1MwCrAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hypatia:BAABLgAECn8cAAIBAAgJHSHPDQAdAgABAAgJHSHPDQAdAgAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8dAAICAAkJ3x9kFgBWAgACAAkJ3x9kFgBWAgAAAA==.',
In='Incite:BAABLgAECn8gAAMdAAkJaA9nBgC0AQAdAAkJZQ9nBgC0AQAeAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAABLgAECn8pAAMXAAgJrBPaHgB2AQAXAAgJrBPaHgB2AQAfAAcJqAj4IgC0AAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8kAAIgAAgJ9h3MBwCrAgAgAAgJ9h3MBwCrAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kamine:BAAALgAECgUJDQAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Kateblue:BAABLgAECn8iAAIXAAgJmhWFFwC5AQAXAAgJmhWFFwC5AQAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8VAAMVAAcJ2B7FBAApAgAVAAcJ2B7FBAApAgAUAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8dAAIdAAgJdQgwCgBPAQAdAAgJdQgwCgBPAQAAAA==.',
Ki='Kiku:BAABLgAECn8iAAIRAAkJYCOMAwAJAwARAAkJYCOMAwAJAwAAAA==.Kikyou:BAAALgAECgYJBgABLgAECgkJIgARAGAjAA==.Kim:BAABLgAECn8bAAIhAAgJdw3rFgChAQAhAAgJdw3rFgChAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kissofdeáth:BAAALgAECgEJAQAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQUAAkJ7R0vNAA8AgAUAAgJGR0vNAA8AgAVAAEJoxa4IgBAAAATAAEJAACvbAA7AAAAAA==.',
Kr='Kreepywife:BAAALgAECgEJAQAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8bAAILAAgJNwmhQwA8AQALAAgJNwmhQwA8AQAAAA==.',
Ku='Kuzan:BAACLgAFFH8QAAIDAAUJWB4LLABeAQADAAUJWB4LLABeAQAuAAQKfx8AAgMABwl3IfQ2AJgCAAMABwl3IfQ2AJgCAAAA.',
Ky='Kyoyama:BAAALgAECgMJBQABLgAECggJGgAUAAggAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJJwANAD0dAA==.Ladýshinobu:BAABLgAECn8cAAIPAAcJwAshNgAmAQAPAAcJwAshNgAmAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn8uAAIiAAgJzBZhDACpAQAiAAgJzBZhDACpAQAAAA==.Lediaa:BAAALgADCgcJBwAAAA==.',
Li='Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgYJBwAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Littlespyone:BAAALgAECgQJEgAAAA==.',
Lo='Locholovis:BAABLgAECn8iAAITAAgJzxDLCABtAQATAAgJzxDLCABtAQAAAA==.Locklicous:BAAALgAECggJEQAAAA==.Longhorse:BAACLgAFFH8ZAAIEAAUJHCBqCABqAQAEAAUJHCBqCABqAQAuAAQKfzEAAwQACQn1JMgFAOACAAQACQmpIsgFAOACAAUABgndJWRAALwBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJBgAAAA==.Lorna:BAAALgAECgYJDgAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAUAO0dAA==.',
Lu='Lumi:BAAALgAECgcJEQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8LAAILAAUJThdNDACUAQALAAUJThdNDACUAQABLgAFFAMJBgAjAOcUAA==.Lumpia:BAABLgAFFH8IAAIHAAUJGBntHwBIAQAHAAUJGBntHwBIAQAAAA==.',
Ly='Lyrinir:BAABLgAECn8bAAIGAAkJ8xg0DwCmAQAGAAkJ8xg0DwCmAQAAAA==.Lyrium:BAABLgAECn8ZAAMaAAgJthm8CgC4AQAaAAUJDR+8CgC4AQAZAAcJ+hBIGwA7AQABLgAECgkJGwAGAPMYAA==.',
Ma='Madar:BAAALgAECgYJDwAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECgUJCAAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn8WAAIEAAYJqxDeIAD3AAAEAAYJqxDeIAD3AAAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJCgABLgAECgkJKQAWAKkWAA==.Marrock:BAAALgAECgQJBQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJCQAAAA==.',
Mc='Mcmuffin:BAAALgAECgUJCgAAAA==.',
Me='Mechacattie:BAABLgAECn8nAAINAAkJPR3TCgC9AgANAAkJPR3TCgC9AgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8jAAMkAAgJOgwbJQBLAQAkAAgJOgwbJQBLAQAgAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDgABLgAECgkJIwAfAKMaAA==.Mezi:BAABLgAECn8qAAIgAAgJ2h+zCQCEAgAgAAgJ2h+zCQCEAgAAAA==.Mezmera:BAAALgADCgUJBgABLgAECgEJAQAJAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIjAAMJ5xQEHAD0AAAjAAMJ5xQEHAD0AAAuAAQKfxkAAyAACQlbGXQoAK0BACAABgn7GXQoAK0BACMABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAAJAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAQABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAQABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8dAAIKAAgJHQ43KgBHAQAKAAgJHQ43KgBHAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgMJBQAJAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCQzBACJAQABAAQJbCQzBACJAQAuAAQKfxYAAgEABwntJAkKANcCAAEABwntJAkKANcCAAAA.Mulron:BAABLgAECn8cAAIiAAgJgxDJEABfAQAiAAgJgxDJEABfAQAAAA==.',
My='Myrica:BAAALgAECgQJBQAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQAJAAAAAA==.',
Ne='Nefesh:BAAALgAFFAQJBAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8PAAIXAAUJ2RSiEwAsAQAXAAUJ2RSiEwAsAQAuAAQKfzYAAhcACQkHFtAUAGsCABcACQkHFtAUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Ol='Olkwon:BAAALgAECgYJBgAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Oo='Oozwoz:BAAALgAECgQJBAAAAA==.',
Or='Orileluu:BAAALgADCgYJFQAAAA==.',
Ox='Oxwon:BAAALgAECgIJAgAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBAAAAA==.Pallynomial:BAAALgADCgcJCAAAAA==.Pawmuck:BAAALgAECgYJEwAAAA==.',
Pe='Peer:BAAALgAECgEJAQAAAA==.Pewpewtazarz:BAAALgADCgYJBgAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgIJAgAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMFAAcJBx9/PABFAgAFAAcJBx9/PABFAgAEAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8jAAIEAAgJthdYEACvAQAEAAgJthdYEACvAQAAAA==.',
Po='Poof:BAAALgAECgYJCgABLgAECgYJCgAJAAAAAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAAALgAECgcJBwAAAA==.Progression:BAAALgAECgEJAwAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8XAAIiAAcJ3RenDgCAAQAiAAcJ3RenDgCAAQAAAA==.Rainthefire:BAABLgAECn8/AAINAAkJZRqvFwBNAgANAAkJZRqvFwBNAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgQJBwAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8JAAILAAMJ5xFYMgC7AAALAAMJ5xFYMgC7AAAuAAQKfxUAAgsACAl4HUUXAFsCAAsACAl4HUUXAFsCAAAA.',
Ri='Rianon:BAAALgADCgkJCQABLgAECggJHgAHAIMXAA==.Rift:BAAALgAECgEJAQAAAA==.Righteous:BAABLgAECn8bAAIgAAYJKh6cEwDyAQAgAAYJKh6cEwDyAQAAAA==.Rizzy:BAAALgADCgQJBAAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAQAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8LAAMNAAQJtw8+JAAsAQANAAQJtw8+JAAsAQAhAAIJbgMJHgCJAAAuAAQKfygAAw0ACQltIWUWAIUCAA0ACAmTImUWAIUCACEACAl1GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJAwAAAA==.Rutikee:BAABLgAECn8wAAIYAAgJvhMDKwC3AQAYAAgJvhMDKwC3AQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIgAAgJlBW8FgAmAgAgAAgJlBW8FgAmAgABLgAECgkJKgAUAIwaAA==.Saeris:BAAALgADCggJCAABLgAECgEJAQAJAAAAAA==.Sagordez:BAABLgAECn8UAAQlAAgJQhpKFQD+AQAlAAcJrBpKFQD+AQACAAYJdhJFLgARAQABAAEJ4Q/CcQAxAAABLgAECgkJHgAaAEogAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgUJBQABLgAECggJIAAOAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgADCgkJMAAAAA==.Sazed:BAAALgAECgcJBwAAAA==.',
Sc='Scrom:BAAALgAECgEJAQAAAA==.',
Se='Seabush:BAAALgAECgEJAQAAAA==.Seastorm:BAAALgAECgEJAQAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAAALgADCgkJDwAAAA==.Semila:BAAALgAECgcJCQAAAA==.Senseicanz:BAAALgADCgIJAgAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgADCgIJAgABLgAECggJIwAEALYXAA==.Serom:BAAALgAECgYJEAAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAICAAkJSyFZBgCeAgACAAkJSyFZBgCeAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shamkazaam:BAAALgAECgEJAQAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAAJAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgADCgYJBgAAAA==.Sherunn:BAABLgAECn8WAAIXAAYJ1AqVNwDcAAAXAAYJ1AqVNwDcAAAAAA==.Shifty:BAAALgAECgEJAQAAAA==.Shiftydon:BAABLgAECn8VAAMOAAgJzRDWDACKAQAOAAgJzRDWDACKAQAYAAIJ+Q2LiwBeAAAAAA==.Shimakaze:BAABLgAECn8kAAINAAgJ3wmDTQBfAQANAAgJ3wmDTQBfAQAAAA==.Shirvana:BAAALgAECgQJBgABLgAECgcJCQAJAAAAAA==.Shooters:BAABLgAECn8YAAIhAAkJOx3XEwC/AQAhAAkJOx3XEwC/AQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgAJAAAAAA==.Shyminx:BAAALgADCgkJCQAAAA==.Shymistress:BAABLgAECn8xAAINAAgJwCCyDwCLAgANAAgJwCCyDwCLAgAAAA==.Shåmmy:BAABLgAECn8vAAILAAkJvw37MACTAQALAAkJvw37MACTAQAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8eAAIXAAgJqR4oDABFAgAXAAgJqR4oDABFAgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn8wAAIOAAgJWB/KAwCAAgAOAAgJWB/KAwCAAgAAAA==.Skodoosh:BAAALgAECgEJAQAAAA==.Skrinkles:BAAALgAECgUJBwAAAA==.Skyrocket:BAAALgAECgIJAgAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIPAAYJ/BxTBwDZAQAPAAYJ/BxTBwDZAQAuAAQKfycAAw8ACQk8IOwOAJ4CAA8ACQk8IOwOAJ4CABAABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIFAAMJNBbIWwD5AAAFAAMJNBbIWwD5AAAuAAQKfyIAAgUACAkSGn5KABMCAAUACAkSGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgADCgMJAwAAAA==.',
Sn='Snizzlaki:BAABLgAECn82AAICAAkJKg/HFwCsAQACAAkJKg/HFwCsAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQAJAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8aAAQLAAkJ3x8aBgAQAwALAAkJ3x8aBgAQAwAKAAUJrRMAUACfAAAbAAIJRg3PHwBnAAAAAA==.',
St='Starwolfy:BAAALgADCgQJBAAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAABLgAECn8WAAIkAAYJbAHfTwBoAAAkAAYJbAHfTwBoAAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgMJBQAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Takbez:BAABLgAECn8gAAIOAAgJlxOSCwAGAgAOAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgQJBAAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8ZAAIYAAgJVxcTHwAHAgAYAAgJVxcTHwAHAgAAAA==.',
Te='Teakaachu:BAAALgAECgcJEQAAAA==.Terdanator:BAAALgAECgYJEgAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn8qAAQUAAkJjBpxIAAlAgAUAAkJjBpxIAAlAgAVAAEJAAA+KABQAAATAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8aAAIPAAcJcx3KEwAmAgAPAAcJcx3KEwAmAgAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAVAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAAALgAECgYJDAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.',
Tu='Turdanator:BAABLgAECn9BAAMkAAkJDBnbCgBXAgAkAAkJDBnbCgBXAgAgAAYJGw1sQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgADCgEJAQAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQAJAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgMJAwAAAA==.Uriah:BAAALgAECgcJEwAAAA==.Ursúla:BAABLgAFFH8GAAIUAAMJNwtuVwDOAAAUAAMJNwtuVwDOAAABLgAFFAQJCwAXALkOAA==.Uryu:BAAALgAECgMJAwAAAA==.Urïah:BAAALgADCgkJGgABLgAECgcJEwAJAAAAAA==.',
Ut='Utherr:BAAALgAFFAMJAwAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAAALgAECgIJAwABLgAECgYJDQAJAAAAAA==.Violinmax:BAAALgAECgYJDQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIaAAkJSiBgAQDcAgAaAAkJSiBgAQDcAgAAAA==.',
Wa='Wardestroyer:BAAALgAECgcJDwAAAA==.Wardwhelp:BAAALgAECgQJDwABLgAECgYJCgAJAAAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAICAAkJuB/PDQAdAgACAAkJuB/PDQAdAgAAAA==.Winniedapoo:BAABLgAECn80AAIUAAgJ1hsHIwAYAgAUAAgJ1hsHIwAYAgAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECggJIwAEALYXAA==.',
Wo='Wooloo:BAACLgAFFH8YAAQTAAcJChwfAwBvAQAUAAYJsx2EFwB+AQATAAQJ+xgfAwBvAQAVAAEJAADKBABZAAAuAAQKfycAAxQACQmzJYsIAOMCABQACQmzJYsIAOMCABMABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Xa='Xanagore:BAABLgAECn8kAAMMAAgJRh80DABfAgAMAAgJyR40DABfAgAGAAEJ0RbdPAA7AAAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAAALgADCggJCAABLgAECggJJAAMAEYfAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8TAAImAAQJdhr4AQBmAQAmAAQJdhr4AQBmAQAuAAQKfzkAAiYACAluIf4BAHgCACYACAluIf4BAHgCAAAA.',
Xu='Xunie:BAAALgAECgcJDQAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgADAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8XAAIHAAcJ+xFCaQBnAQAHAAcJ+xFCaQBnAQAAAA==.Zaretan:BAAALgADCgYJBwAAAA==.',
Zb='Zbrute:BAABLgAECn8cAAINAAgJoRViNQC0AQANAAgJoRViNQC0AQAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECgYJDwAJAAAAAA==.Zefphenn:BAAALgAECgQJBgABLgAECgYJDwAJAAAAAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8fAAMFAAkJehtyJgAiAgAFAAkJehtyJgAiAgAEAAEJqRwtPABQAAAAAA==.',
Zu='Zulpher:BAAALgADCgQJBAAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJAwAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIDAAMJGBXbWQDwAAADAAMJGBXbWQDwAAAuAAQKfzAAAgMACAn3HnA7AOoBAAMACAn3HnA7AOoBAAAA.',
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
