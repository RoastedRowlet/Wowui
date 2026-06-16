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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Druid-Restoration','Druid-Balance','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Hunter-Survival','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abones:BAAALgAECggJCwAAAA==.Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBQAAAA==.',
Af='Affae:BAABLgAFFH8KAAMBAAMJFBPLMAB6AAACAAIJ6RYURgCBAAABAAIJPg7LMAB6AAAAAA==.',
Ag='Agrios:BAAALgAECgYJCgAAAA==.',
Ak='Ak:BAABLgAECn8qAAIDAAkJRSIHFgDTAgADAAkJRSIHFgDTAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKgAEAFMZAA==.Allister:BAAALgAECgYJBgABLgAECgkJHQAFAL8eAA==.Altahari:BAAALgAFFAEJAQAAAA==.',
Am='Amare:BAAALgAECgcJCgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgAECggJDwAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8mAAMGAAcJthtBWgC1AQAGAAcJlhpBWgC1AQAEAAQJoxaeKgAAAQAAAA==.Arroyo:BAABLgAECn8uAAMGAAkJNyHYEgDWAgAGAAkJNyHYEgDWAgAEAAQJyRufHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgUJBQAAAA==.Askadar:BAACLgAFFH8XAAIHAAYJfya0AwAyAgAHAAYJfya0AwAyAgAuAAQKfy8AAgcACQlyJggBAF0DAAcACQlyJggBAF0DAAAA.',
At='Atinyhorse:BAABLgAECn8ZAAIIAAcJ3At+iwAFAQAIAAcJ3At+iwAFAQAAAA==.Atrax:BAABLgAECn8aAAIJAAcJdA8cOABqAQAJAAcJdA8cOABqAQAAAA==.Atrexx:BAAALgAECgQJBAAAAA==.Atryx:BAABLgAFFH8NAAIKAAMJNBixGQDiAAAKAAMJNBixGQDiAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDgALAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Baheem:BAABLgAECn8VAAIDAAYJgAIdCAGbAAADAAYJgAIdCAGbAAAAAA==.Bams:BAABLgAECn8fAAMMAAkJYh11HgDrAQAMAAcJ4h51HgDrAQANAAgJzAvpUQBnAQAAAA==.Bamsx:BAAALgAECgcJBwAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIOAAkJcCBJGwByAgAOAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAABLgAECn8XAAIMAAgJTQjzSQAIAQAMAAgJTQjzSQAIAQAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAIPAAkJtxZqLwAaAgAPAAkJtxZqLwAaAgAAAA==.Blappin:BAAALgADCgcJFAAAAA==.Bloodmyst:BAAALgAECgcJEQABLgAECgkJIQAQAFMdAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJBQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8eAAIJAAkJxBjHGgAsAgAJAAkJxBjHGgAsAgAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBQAAAA==.Bookwyrm:BAAALgADCgkJDQAAAA==.Boolil:BAAALgAECgQJCQABLgAECgkJMAARAIYRAA==.Boolove:BAAALgAECgMJAwABLgAECgkJMAARAIYRAA==.Booqt:BAAALgAECggJCQABLgAECgkJMAARAIYRAA==.Boriel:BAAALgAECgYJBgAAAA==.',
Br='Breake:BAACLgAFFH8MAAISAAMJnwuQMwC4AAASAAMJnwuQMwC4AAAuAAQKfyIAAxIACAmlFzUXABkCABIACAmlFzUXABkCABMAAwl0DyRqAG8AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8dAAMUAAgJ+hH5LgB7AQAUAAgJ0BH5LgB7AQAVAAQJ0w5wEwDPAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwACAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJNQAPAGMeAA==.',
Ce='Cerealmilk:BAABLgAECn8XAAIWAAgJkBlxCQBNAgAWAAgJkBlxCQBNAgABLgAECggJHAAHAKEaAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgALAAAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAALAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIDAAUJAB8TRgBeAQADAAUJAB8TRgBeAQAuAAQKfxsAAgMACQn2IJwtALsCAAMACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAECgYJEQALAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8oAAIHAAgJ/CTeAADZAgAHAAgJ/CTeAADZAgAuAAQKfyUAAgcACAkAIiEEAAoDAAcACAkAIiEEAAoDAAAA.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECgkJSAAGAD0IAA==.Creepydemise:BAABLgAECn9IAAIGAAkJPQiNbgCFAQAGAAkJPQiNbgCFAQAAAA==.Creepydrunk:BAAALgADCgEJAQABLgAECgkJSAAGAD0IAA==.Creepyfoxxy:BAAALgADCgkJGwAAAA==.Croixsmash:BAABLgAECn8gAAIOAAkJZB5GIgBDAgAOAAkJZB5GIgBDAgAAAA==.Croixtemplar:BAAALgAECgYJCwAAAA==.',
Cu='Cuculain:BAAALgAECgEJBAAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Dagdelythy:BAAALgAECgUJBQAAAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8lAAQXAAgJmQiWfgA7AQAXAAgJHQiWfgA7AQAYAAUJ9QYBIQCzAAAZAAYJtAVaIgCZAAAAAA==.Darthzai:BAAALgAECgMJAwAAAA==.Davennial:BAABLgAECn88AAIRAAkJ5BE8VgDGAQARAAkJ5BE8VgDGAQAAAA==.Dawnn:BAABLgAECn8bAAIEAAkJ/wkcIgA/AQAEAAkJ/wkcIgA/AQAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8oAAIDAAgJ8AlOjwBWAQADAAgJ8AlOjwBWAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIEAAMJbBidJADHAAAEAAMJbBidJADHAAAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQABAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQABAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECggJDwAAAA==.',
Do='Dogeatdog:BAAALgADCgcJEgAAAA==.Dohaeriz:BAAALgAECgEJAgAAAA==.Doregoran:BAABLgAECn8oAAIZAAgJGhO1CgCTAQAZAAgJGhO1CgCTAQAAAA==.Dovairous:BAABLgAECn8dAAIaAAgJrQpFVwAxAQAaAAgJrQpFVwAxAQAAAA==.',
Dr='Draakell:BAAALgAECgQJBAAAAA==.Dracopeet:BAABLgAECn8ZAAQUAAcJvwRjbgCLAAAUAAUJ4wRjbgCLAAAWAAQJGwMdNQBOAAAVAAMJwQIWKQAnAAAAAA==.Dragonator:BAAALgAECgMJAwAAAA==.Drausella:BAAALgAECgEJAQAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgQJCwAAAA==.',
Du='Dudè:BAAALgAECgMJAwAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgYJEQAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8dAAIXAAcJKAoCnAAFAQAXAAcJKAoCnAAFAQAAAA==.',
Ed='Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJCQAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8lAAMbAAYJFxymDADEAQAbAAYJFxymDADEAQAaAAIJ+gAeaQBEAAAuAAQKfyUAAxsACQmmHi0QAF0CABsACQmmHi0QAF0CABoABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAIOAAgJgQ66NQBwAQAOAAgJgQ66NQBwAQAAAA==.Erodoria:BAABLgAECn8dAAMFAAkJvx6OCgB8AgAFAAgJZiGOCgB8AgAcAAUJ/hC4FAAFAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgkJHQAbANwXAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAUJGwANAOgYAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAABLgAECn8yAAIKAAkJpx0IAwCqAgAKAAkJpx0IAwCqAgAAAA==.',
Fa='Falkor:BAABLgAECn8tAAMWAAkJqBbcCwAXAgAWAAkJqBbcCwAXAgAVAAEJ6QKAKwAaAAAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatino:BAAALgAECgQJBAAAAA==.Fatkid:BAABLgAECn8UAAIIAAcJng/AdgAvAQAIAAcJng/AdgAvAQAAAA==.Fayway:BAABLgAECn9DAAIaAAkJviFiBgBPAwAaAAkJviFiBgBPAwAAAA==.',
Fe='Ferral:BAABLgAECn8hAAIQAAkJUx3jBACoAgAQAAkJUx3jBACoAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAABLgAECn8UAAIRAAgJARHoqgAkAQARAAgJARHoqgAkAQAAAA==.Firepower:BAABLgAECn8hAAIDAAkJxhdxOgAtAgADAAkJxhdxOgAtAgABLgAECggJIAAQAJcTAA==.Fistatoosh:BAABLgAECn8iAAICAAgJUCRuBgDRAgACAAgJUCRuBgDRAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAAQAJcTAA==.',
Fo='Forevershy:BAAALgADCgkJEgAAAA==.',
Fr='Fries:BAECLgAFFH8HAAIdAAMJjh/4EACwAAAdAAMJjh/4EACwAAAuAAQKfxwAAx0ACQkBIn0CAPACAB0ACQkBIn0CAPACAA0ABQkGDFmBANcAAAEuAAUUBAkHABcApg8A.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIRAAgJnBqgKQB+AgARAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgALAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgALAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAABLgAECn8UAAMOAAcJLhvyPQBMAQAOAAcJxhnyPQBMAQAeAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAABLgAECn8mAAIMAAgJDhN3LACPAQAMAAgJDhN3LACPAQAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJDQABLgAECgUJBQALAAAAAA==.',
Go='Gonzo:BAAALgAFFAEJAQABLgAFFAUJGwANAOgYAA==.Goysoldier:BAAALgAFFAMJBAAAAA==.',
Gr='Greenbean:BAABLgAFFH8ZAAIIAAUJNBVKQQAdAQAIAAUJNBVKQQAdAQABLgAFFAYJJQAbABccAA==.Grelleth:BAAALgAECgQJBAAAAA==.Groddz:BAABLgAECn8WAAIIAAkJvgbvgwAUAQAIAAkJvgbvgwAUAQAAAA==.Groto:BAAALgAECgYJBgAAAA==.Grrum:BAABLgAECn8fAAQSAAcJXgs9NgA6AQASAAcJkQk9NgA6AQATAAQJaQhzWQCrAAAfAAEJQBFEfgA0AAAAAA==.',
Gu='Gurînkaida:BAAALgADCgEJAQAAAA==.',
Ha='Haell:BAAALgAECgYJCgAAAA==.Hanjo:BAABLgAECn8uAAIHAAkJzyHDBADRAgAHAAkJzyHDBADRAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAINAAcJixUvNgCqAQANAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA31JACvAQABAAgJzA31JACvAQAAAA==.Hatookorr:BAAALgAECgUJBQABLgAECggJIAAQAJcTAA==.Hayali:BAABLgAECn8iAAIIAAgJXRZCPADTAQAIAAgJXRZCPADTAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAAALgAECggJDQABLgAECgkJHgAcAFggAA==.Hypatia:BAABLgAECn8dAAIBAAgJqiFmDQBsAgABAAgJqiFmDQBsAgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8iAAICAAkJ3x+PEQApAgACAAkJ3x+PEQApAgAAAA==.',
In='Incite:BAABLgAECn8gAAMgAAkJaA9ICgCRAQAgAAkJZQ9ICgCRAQAhAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jackpad:BAAALgAECgEJAgAAAA==.Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAABLgAECn85AAMbAAkJyxWBFwAOAgAbAAkJyxWBFwAOAgAiAAcJqQhAPQCrAAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8xAAIfAAkJWhwqCQDTAgAfAAkJWhwqCQDTAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kagamire:BAAALgADCgQJAwAAAA==.Kamine:BAAALgAECgUJEAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Karnen:BAAALgAECgMJAwAAAA==.Kateblue:BAABLgAECn8tAAIbAAkJhRrTDwBiAgAbAAkJhRrTDwBiAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8VAAMYAAcJ2B7FBAApAgAYAAcJ2B7FBAApAgAXAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIgAAgJdggDDgBDAQAgAAgJdggDDgBDAQAAAA==.Kethry:BAAALgADCgcJBwAAAA==.',
Ki='Kiku:BAABLgAECn8iAAIUAAkJYiPLBQD/AgAUAAkJYiPLBQD/AgAAAA==.Kikyou:BAAALgAECgYJBgABLgAECgkJIgAUAGIjAA==.Kim:BAABLgAECn8fAAIjAAkJRhDjFQD0AQAjAAkJRhDjFQD0AQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQXAAkJAB4vNAA8AgAXAAgJGR0vNAA8AgAZAAEJAACvbAA7AAAYAAEJPRewOwA4AAAAAA==.',
Kr='Kreepywife:BAABLgAECn8UAAITAAcJghPrLQBpAQATAAcJghPrLQBpAQAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8mAAINAAkJtA9lMgDmAQANAAkJtA9lMgDmAQAAAA==.',
Ku='Kurast:BAAALgAECgMJAwABLgAECgkJLQAWAKgWAA==.Kuzan:BAACLgAFFH8TAAIDAAUJEB+qSgBRAQADAAUJEB+qSgBRAQAuAAQKfx8AAgMABwl3IfQ2AJgCAAMABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAFFAMJCgAYABkfAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJNQAPAGMeAA==.Ladýshinobu:BAABLgAECn8nAAIJAAgJQBDGKADDAQAJAAgJQBDGKADDAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn88AAIkAAkJBhh+CgAgAgAkAAkJBhh+CgAgAgAAAA==.Lediaa:BAAALgAECgMJBAAAAA==.',
Li='Lifekiller:BAAALgAECgYJDgAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgkJDAAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Lisavia:BAAALgADCgMJAwAAAA==.Littlespyone:BAABLgAECn8WAAIPAAQJyg1u2QCTAAAPAAQJyg1u2QCTAAABLgAECgUJBQALAAAAAA==.Lizardman:BAAALgAFFAEJAQAAAA==.',
Lo='Locholovis:BAABLgAECn8wAAIZAAkJOhREBwDdAQAZAAkJOhREBwDdAQAAAA==.Locklicous:BAABLgAECn8WAAMXAAkJ2xfuOwDqAQAXAAkJ2BPuOwDqAQAYAAYJWxX2EQBCAQAAAA==.Longhorse:BAACLgAFFH8fAAIEAAUJZCKzEQBlAQAEAAUJZCKzEQBlAQAuAAQKfzEAAwQACQn4JMgFAOACAAQACQmpIsgFAOACAAYABgnhJcZeAKoBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8XAAIIAAgJJhJWVQCDAQAIAAgJJhJWVQCDAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAXAAAeAA==.',
Lu='Lumi:BAABLgAECn8WAAIDAAkJchhEUADoAQADAAkJchhEUADoAQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8NAAINAAYJ8xT6EwC5AQANAAYJ8xT6EwC5AQABLgAFFAMJBgASAOcUAA==.Lumpia:BAABLgAFFH8IAAIIAAUJGBn/PwAhAQAIAAUJGBn/PwAhAQAAAA==.',
Ly='Lyrinir:BAABLgAECn8dAAMHAAkJ/hkjEQD2AQAHAAkJ/hkjEQD2AQAeAAEJigS6hwAbAAAAAA==.Lyrium:BAABLgAECn8ZAAMcAAgJtRm8CgC4AQAcAAUJDR+8CgC4AQAFAAcJ+RBnKQAtAQABLgAECgkJHQAHAP4ZAA==.',
Ma='Madar:BAABLgAECn8fAAIXAAcJvAa4qwDrAAAXAAcJvAa4qwDrAAAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECggJDQAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn8yAAIEAAgJcRGDHgBgAQAEAAgJcRGDHgBgAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJDAABLgAECgkJLQAWAKgWAA==.Marrock:BAAALgAECgYJEQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.',
Mc='Mcmuffin:BAAALgAECgYJEAAAAA==.',
Me='Mechacattie:BAABLgAECn81AAIPAAkJYx5vEwCyAgAPAAkJYx5vEwCyAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8oAAMTAAgJcQzqNABCAQATAAgJcQzqNABCAQAfAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAiAKMaAA==.Metacallae:BAAALgADCgcJBwAAAA==.Mezi:BAABLgAECn8/AAIfAAkJkyA7BwD5AgAfAAkJkyA7BwD5AgAAAA==.Mezmera:BAAALgADCgUJBgABLgAECgIJAwALAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJBgABLgAECgcJCAALAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAISAAMJ5xS4LgDTAAASAAMJ5xS4LgDTAAAuAAQKfxkAAx8ACQlbGXQoAK0BAB8ABgn7GXQoAK0BABIABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAALAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwARABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwARABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8sAAIMAAkJIA54LgCEAQAMAAkJIA54LgCEAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgMJCQALAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCR7CwBlAQABAAQJbCR7CwBlAQAuAAQKfxYAAgEABwntJAkKANcCAAEABwntJAkKANcCAAAA.Mulron:BAABLgAECn8jAAIkAAkJmhH2EQCjAQAkAAkJmhH2EQCjAQAAAA==.',
My='Myrica:BAAALgAECggJDQAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQALAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8SAAIIAAUJ8ghTVQDoAAAIAAUJ8ghTVQDoAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAABLgAECgYJCgALAAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8VAAIbAAYJ4BHmGABKAQAbAAYJ4BHmGABKAQAuAAQKfzsAAhsACQlCF9AUAGsCABsACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAAALgAECgkJDAABLgAECgkJLQAWAKgWAA==.',
Ol='Olkwon:BAAALgAFFAIJAwAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Oo='Oozwoz:BAAALgAECgYJCwAAAA==.',
Or='Orileluu:BAAALgADCgkJJgAAAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBAAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Pawmuck:BAABLgAECn8tAAIRAAgJ9Rk7OwAUAgARAAgJ9Rk7OwAUAgAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgUJCQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMGAAcJBx9/PABFAgAGAAcJBx9/PABFAgAEAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8qAAMEAAkJUxk1EgDoAQAEAAkJOhg1EgDoAQAGAAEJ3RrvTQFOAAAAAA==.',
Po='Podtinder:BAAALgAECgcJDAABLgAECgkJLQAWAKgWAA==.Poof:BAAALgAECgYJCgABLgAECggJHAAHAKEaAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAABLgAECn8XAAMlAAgJ+Am0XgD0AAAlAAcJ1Am0XgD0AAABAAcJvQhCRADrAAAAAA==.Progression:BAAALgAECgEJBgAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8jAAIkAAgJVxlwDAD6AQAkAAgJVxlwDAD6AQAAAA==.Rainsshammy:BAAALgAECgQJBwAAAA==.Rainthefire:BAABLgAECn8/AAIPAAkJZRqBKwArAgAPAAkJZRqBKwArAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Ramalama:BAAALgAECgEJAgAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgUJCQAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8bAAINAAUJ6BggIQBkAQANAAUJ6BggIQBkAQAuAAQKfyMAAg0ACQmJG0UXAFsCAA0ACQmJG0UXAFsCAAAA.',
Rh='Rhagnor:BAAALgAECgQJBAAAAA==.',
Ri='Rianon:BAAALgADCgkJEgABLgAECgkJLAAIABobAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8mAAIfAAcJRRxYGAAGAgAfAAcJRRxYGAAGAgAAAA==.Rizzy:BAABLgAECn8gAAMEAAkJERdSDwATAgAEAAkJERdSDwATAgAGAAkJ7gi5awCLAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8SAAMPAAYJuxHXIAB4AQAPAAYJuxHXIAB4AQAjAAIJbgMeLAB6AAAuAAQKfygAAw8ACQlsIWUWAIUCAA8ACAmTImUWAIUCACMACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn9EAAIaAAgJQxUCLgDsAQAaAAgJQxUCLgDsAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIfAAgJlBW8FgAmAgAfAAgJlBW8FgAmAgABLgAECgkJOgAXAAEbAA==.Saeris:BAAALgADCggJCAABLgAECgcJDgALAAAAAA==.Sagordez:BAABLgAECn8lAAQlAAgJSBtnIwD+AQAlAAcJrBpnIwD+AQACAAcJcRUJJgB7AQABAAEJ4Q+GoAAtAAABLgAECgkJHgAcAFggAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJCgABLgAECggJIAAQAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgAECgQJCgAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJBAAAAA==.',
Se='Seabush:BAAALgAECgEJAQAAAA==.Seastorm:BAAALgAECgkJCAAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAABLgAECn8bAAMjAAgJbxISGgDOAQAjAAgJbxISGgDOAQAKAAIJmQc6MwBMAAAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sendor:BAAALgAECgYJBgAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgQJBgABLgAECgkJKgAEAFMZAA==.Serom:BAABLgAECn8hAAIaAAgJdRkSHwBLAgAaAAgJdRkSHwBLAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAICAAkJSyFnCgCLAgACAAkJSyFnCgCLAgAAAA==.Shadowoak:BAAALgAECgIJAgAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAALAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgAECgEJAQAAAA==.Sharkyo:BAAALgADCgIJAgAAAA==.Sharpshôôter:BAAALgAECgEJAQAAAA==.Sherunn:BAABLgAECn8iAAIbAAcJpQ1LOQAqAQAbAAcJpQ1LOQAqAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQQAAkJ0RDwDwCyAQAQAAkJ0RDwDwCyAQAaAAIJ+Q35qQBeAAAiAAEJMguMfAAhAAAAAA==.Shimakaze:BAABLgAECn85AAIPAAkJoA4zRADQAQAPAAkJoA4zRADQAQAAAA==.Shirvana:BAAALgAECgQJBwABLgAECgcJCQALAAAAAA==.Shooters:BAABLgAECn8YAAIjAAkJOx26DQDuAQAjAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgALAAAAAA==.Shyminx:BAAALgADCgkJEgAAAA==.Shymistress:BAABLgAECn85AAIPAAkJEyI9DADvAgAPAAkJEyI9DADvAgAAAA==.Shåmmy:BAABLgAECn8/AAINAAkJ7hMiKAAaAgANAAkJ7hMiKAAaAgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8nAAIbAAkJVR82CQC+AgAbAAkJVR82CQC+AgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn9UAAIQAAkJuyHhAQAWAwAQAAkJuyHhAQAWAwAAAA==.Skodoosh:BAAALgAECgYJDwAAAA==.Skrinkles:BAAALgAECgYJDgAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIJAAYJ/BzeBwBUAQAJAAYJ/BzeBwBUAQAuAAQKfycAAwkACQk7IOwOAJ4CAAkACQk7IOwOAJ4CABEABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIGAAMJNBYqmwDYAAAGAAMJNBYqmwDYAAAuAAQKfyIAAgYACAkYGn5KABMCAAYACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgAECgEJAQAAAA==.',
Sn='Snizzlaki:BAABLgAECn8+AAICAAkJQg9jIAChAQACAAkJQg9jIAChAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAECgcJCAAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Sparkleglory:BAAALgAECgMJAwAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQALAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8bAAQNAAkJ3x8aBgAQAwANAAkJ3x8aBgAQAwAMAAUJpRUGZAC1AAAdAAIJRg10MQBlAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAABLgAECn8mAAITAAgJkgFsZACFAAATAAgJkgFsZACFAAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgMJCQAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Taana:BAAALgAECgUJCgAAAA==.Takbez:BAABLgAECn8gAAIQAAgJlxOSCwAGAgAQAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgYJCwAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgADCgIJAgABLgAECgkJJQADAFQfAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8fAAMaAAgJRRldIQA6AgAaAAgJRRldIQA6AgAbAAEJphEriQA1AAAAAA==.Tazale:BAAALgAECgYJBgABLgAECgYJBgALAAAAAA==.',
Te='Teakaachu:BAABLgAECn8XAAIlAAgJPBO0KwDLAQAlAAgJPBO0KwDLAQAAAA==.Terdanator:BAABLgAECn8fAAMdAAgJFhb6DADdAQAdAAgJFhb6DADdAQAMAAEJLQa6tQAjAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQXAAkJARuYIABfAgAXAAkJARuYIABfAgAYAAQJyRDpHwC8AAAZAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8rAAMJAAkJ8xuhDADDAgAJAAkJ8xuhDADDAgARAAYJ0AMDEAGhAAAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAYAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAABLgAECn8XAAQTAAgJkxYaGwDrAQATAAgJkxYaGwDrAQASAAYJpBhNOAAwAQAfAAIJfB56TACsAAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.Truda:BAAALgAECgIJAgAAAA==.',
Tu='Turdanator:BAABLgAECn9NAAMTAAkJDhnPEgA8AgATAAkJDhnPEgA8AgAfAAcJ/gtsQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgAECgQJBAAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQALAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn8nAAIPAAkJPxXLMQARAgAPAAkJPxXLMQARAgAAAA==.Ursúla:BAABLgAFFH8KAAIXAAQJ7QrUXQAHAQAXAAQJ7QrUXQAHAQABLgAFFAYJJQAbABccAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgAECgYJDAABLgAECgkJJwAPAD8VAA==.',
Ut='Utherr:BAABLgAFFH8FAAIRAAMJ6Bo/ZQDdAAARAAMJ6Bo/ZQDdAAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJBwAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAEALgAECgIJAwABLgAECggJDAALAAAAAA==.Violinmax:BAEALgAECgYJDQABLgAECggJDAALAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIcAAkJWCABAwC6AgAcAAkJWCABAwC6AgAAAA==.',
['Vé']='Végeta:BAAALgAECgIJAgABLgAECgkJLQAWAKgWAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8cAAIHAAgJoRrCDgD6AQAHAAgJoRrCDgD6AQAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAICAAkJuR/dEwAOAgACAAkJuR/dEwAOAgAAAA==.Wildmist:BAAALgAECgMJAwAAAA==.Winniedapoo:BAABLgAECn80AAIXAAgJ2BsGNgAAAgAXAAgJ2BsGNgAAAgAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKgAEAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8cAAQXAAkJHiA2CAB6AgAXAAgJ4yE2CAB6AgAZAAQJ+xgfAwBvAQAYAAEJAADKBABZAAAuAAQKfygAAxcACQmzJSUPANECABcACQmzJSUPANECABkABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Wy='Wynona:BAAALgAECgUJBQAAAA==.',
Xa='Xanagore:BAABLgAECn8nAAMOAAgJfSKADgCIAgAOAAgJACKADgCIAgAHAAEJ0RZXUQA0AAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAABLgAECn8VAAIKAAcJyRIDDwBoAQAKAAcJyRIDDwBoAQABLgAECggJJwAOAH0iAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8XAAImAAQJ3hqGBABLAQAmAAQJ3hqGBABLAQAuAAQKfzsAAiYACAkbItICAIUCACYACAkbItICAIUCAAAA.',
Xu='Xunie:BAABLgAECn8oAAIGAAkJHBWAMwAuAgAGAAkJHBWAMwAuAgAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgADAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8ZAAIIAAgJPRIbdQAzAQAIAAgJPRIbdQAzAQAAAA==.Zaretan:BAAALgADCgkJFgAAAA==.',
Zb='Zbrute:BAABLgAECn8pAAIPAAkJXxwhFwCZAgAPAAkJXxwhFwCZAgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECgcJHwAXALwGAA==.Zefphenn:BAAALgAECgQJBgABLgAECgcJHwAXALwGAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zildroghar:BAAALgADCgcJCAAAAA==.Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8lAAMGAAkJWBxwLQBIAgAGAAkJWBxwLQBIAgAEAAIJ+xd7QACKAAAAAA==.',
Zu='Zulgar:BAAALgAFFAIJAgABLgAFFAgJFgADAFgZAA==.Zulpher:BAAALgADCgYJEgAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJBQAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIDAAMJGBWOOQC3AAADAAMJGBWOOQC3AAAuAAQKfzsAAwMACAkRHyJKAFkCAAMACAn4HiJKAFkCACcABAnvIagHACoBAAAA.',
['ße']='ßeorn:BAAALgAECgEJAQAAAA==.',
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
