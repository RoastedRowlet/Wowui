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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Mage-Frost','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Druid-Restoration','Druid-Balance','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','Hunter-Survival','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abones:BAAALgAECgcJCQAAAA==.Absolon:BAAALgAECgQJBAAAAA==.Absólon:BAAALgADCgcJBwAAAA==.',
Ae='Aendia:BAAALgADCgIJAwAAAA==.Aeolos:BAAALgAECgUJBQAAAA==.',
Af='Affae:BAABLgAFFH8KAAMBAAMJFBNPLQCEAAABAAIJPg5PLQCEAAACAAIJ6RZnQwCDAAAAAA==.',
Ag='Agrios:BAAALgAECgYJCAAAAA==.',
Ak='Ak:BAABLgAECn8qAAIDAAkJRSKrFADYAgADAAkJRSKrFADYAgAAAA==.',
Al='Alanas:BAAALgADCgEJAQAAAA==.Alcohlol:BAAALgADCgEJAQAAAA==.Allendril:BAAALgADCgIJAgABLgAECgkJKgAEAFMZAA==.Allister:BAAALgAECgYJBgABLgAECgkJHAAFAFseAA==.',
Am='Amare:BAAALgAECgcJCgAAAA==.',
An='Ancalagon:BAAALgAECgQJCQAAAA==.Andros:BAAALgAECgYJDAAAAA==.Anekaatwo:BAAALgADCgEJAQAAAA==.Antigone:BAAALgAECgYJCwAAAA==.',
Ar='Araxe:BAABLgAECn8mAAMGAAcJtxtmVwC3AQAGAAcJlxpmVwC3AQAEAAQJoxYsKQADAQAAAA==.Arroyo:BAABLgAECn8oAAMGAAkJ2x+3GACqAgAGAAkJwx+3GACqAgAEAAQJyRufHgBSAQAAAA==.Artax:BAAALgADCgYJDAAAAA==.',
As='Asalohir:BAAALgAECgEJAQAAAA==.Askadar:BAACLgAFFH8SAAIHAAUJpSYOBwCvAQAHAAUJpSYOBwCvAQAuAAQKfy8AAgcACQlyJuQAAGEDAAcACQlyJuQAAGEDAAAA.',
At='Atinyhorse:BAABLgAECn8ZAAIIAAcJ3AvbhgAFAQAIAAcJ3AvbhgAFAQAAAA==.Atrax:BAABLgAECn8YAAIJAAcJdA9jNgBrAQAJAAcJdA9jNgBrAQAAAA==.Atryx:BAABLgAFFH8KAAIKAAMJBhWIGADbAAAKAAMJBhWIGADbAAAAAA==.',
Au='Auronralius:BAAALgADCgIJAgAAAA==.',
Ax='Ax:BAAALgADCgcJCgABLgAECgYJDQALAAAAAA==.',
Az='Azazél:BAAALgAECgIJAgAAAA==.Azuleja:BAAALgADCgEJAQAAAA==.Azzura:BAAALgADCgYJBwAAAA==.',
Ba='Baheem:BAAALgAECgUJEAAAAA==.Bams:BAABLgAECn8eAAMMAAkJYh3uHADtAQAMAAcJ4h7uHADtAQANAAgJzAtjTgBpAQAAAA==.Bamsx:BAAALgAECgYJBgAAAA==.Baneofdemons:BAAALgADCgEJAQAAAA==.Barrillon:BAAALgADCgEJAQAAAA==.Bastile:BAAALgAECgYJDwAAAA==.Bauer:BAAALgAECgQJBAAAAA==.',
Be='Benel:BAAALgAECggJEgAAAA==.',
Bi='Bifrons:BAAALgADCgMJAwAAAA==.Bigblkengery:BAAALgADCgcJCAAAAA==.Bigdill:BAAALgAECgEJAQAAAA==.Biggrippa:BAABLgAECn8lAAIOAAkJcCBJGwByAgAOAAkJcCBJGwByAgAAAA==.Bighoofprint:BAAALgAECgkJAQAAAA==.Bigtotempole:BAAALgAECggJEgAAAA==.',
Bj='Bjornar:BAAALgADCgEJAQAAAA==.',
Bl='Blahwithpets:BAABLgAECn8sAAIPAAkJtxZfLAAgAgAPAAkJtxZfLAAgAgAAAA==.Blappin:BAAALgADCgYJDgAAAA==.Bloodmyst:BAAALgAECgcJEAABLgAECgkJIAAQAEQcAA==.Bloodymaw:BAAALgAECgQJBAAAAA==.Bloomer:BAAALgADCgEJAQAAAA==.Blooshield:BAAALgAECgUJBQAAAA==.Bluemchen:BAAALgADCgMJAwAAAA==.Blurt:BAAALgAECgEJAQAAAA==.',
Bo='Bobble:BAABLgAECn8dAAIJAAgJYRkrIQDvAQAJAAgJYRkrIQDvAQAAAA==.Bohelranus:BAAALgADCgkJFwAAAA==.Boneman:BAAALgAECgUJBQAAAA==.Bookwyrm:BAAALgADCgkJDAAAAA==.Boolil:BAAALgAECgQJCQABLgAECggJCAALAAAAAA==.Boolove:BAAALgAECgMJAwABLgAECggJCAALAAAAAA==.Booqt:BAAALgAECggJCAAAAA==.Boriel:BAAALgAECgUJBQAAAA==.',
Br='Breake:BAACLgAFFH8LAAIRAAMJnwveLwC4AAARAAMJnwveLwC4AAAuAAQKfyEAAxEACAmlFzgWABkCABEACAmlFzgWABkCABIAAwl0D1BmAG8AAAAA.',
Bu='Bubblebreath:BAAALgAECgEJAQAAAA==.',
By='Byssrak:BAABLgAECn8bAAMTAAcJ9hHfNgBIAQATAAcJxRHfNgBIAQAUAAQJ0w6TEgDUAAAAAA==.',
Ca='Caladiir:BAAALgAECgUJBQABLgAECgkJHwACAEshAA==.Cattiebuzz:BAAALgAECgIJAwABLgAECgkJNAAPAGMeAA==.',
Ce='Cerealmilk:BAABLgAECn8XAAIVAAgJkBk5CQBOAgAVAAgJkBk5CQBOAgABLgAECggJHAAHAKEaAA==.',
Ch='Chadd:BAAALgADCgYJBgABLgAECgQJBgALAAAAAA==.Childishbro:BAAALgAECgEJAQAAAA==.Chilla:BAAALgAECgMJAwAAAA==.Chitung:BAAALgADCgQJBAABLgAECgQJBAALAAAAAA==.Chopshop:BAAALgAECgEJAQAAAA==.Christopher:BAACLgAFFH8SAAIDAAUJAB9yPwBhAQADAAUJAB9yPwBhAQAuAAQKfxsAAgMACQn2IJwtALsCAAMACQn2IJwtALsCAAAA.',
Ci='Cialismaxing:BAAALgAECggJDQABLgAECggJGQABAMwNAA==.Cindragos:BAAALgAECgQJBQABLgAECgUJEAALAAAAAA==.',
Co='Cocofluff:BAACLgAFFH8oAAIHAAgJ/CSUAADnAgAHAAgJ/CSUAADnAgAuAAQKfyUAAgcACAkAIiEEAAoDAAcACAkAIiEEAAoDAAAA.',
Cr='Creed:BAAALgAECgEJAQAAAA==.Creepychaos:BAAALgADCgkJKwABLgAECggJPwAGAD4IAA==.Creepydemise:BAABLgAECn8/AAIGAAgJPghvhgBOAQAGAAgJPghvhgBOAQAAAA==.Creepydrunk:BAAALgADCgEJAQABLgAECggJPwAGAD4IAA==.Creepyfoxxy:BAAALgADCgkJEgAAAA==.Croixsmash:BAABLgAECn8eAAIOAAgJzRhGIgBDAgAOAAgJzRhGIgBDAgAAAA==.Croixtemplar:BAAALgAECgYJCwAAAA==.',
Cu='Cuculain:BAAALgAECgEJBAAAAA==.Custodian:BAAALgAECgQJBAAAAA==.Cuttinglass:BAAALgADCgcJBwAAAA==.',
Cy='Cytherea:BAAALgADCgcJDAAAAA==.',
Da='Daedra:BAAALgAECgQJBgAAAA==.Danoa:BAAALgAECgQJCgAAAA==.Daraellea:BAAALgAECgUJBQAAAA==.Darkcross:BAAALgADCgUJCAAAAA==.Darthorak:BAABLgAECn8jAAQWAAgJ0AevIACcAAAXAAYJ2AfLrwDfAAAYAAUJ9QYlHwCzAAAWAAYJtAWvIACcAAAAAA==.Darthzai:BAAALgAECgMJAwAAAA==.Davennial:BAABLgAECn86AAIZAAkJ4BFdUgDHAQAZAAkJ4BFdUgDHAQAAAA==.Dawnn:BAABLgAECn8ZAAIEAAgJLwkWJgAYAQAEAAgJLwkWJgAYAQAAAA==.Dayman:BAAALgAFFAEJAgAAAA==.',
De='Deanwnchestr:BAABLgAECn8gAAIDAAgJcQharAAiAQADAAgJcQharAAiAQAAAA==.Deathmamba:BAAALgADCgMJAwAAAA==.Deatnshadow:BAABLgAFFH8FAAIEAAMJbBgnIQDQAAAEAAMJbBgnIQDQAAAAAA==.Demise:BAAALgAECgQJCAAAAA==.Demonberry:BAAALgADCgEJAgAAAA==.Demonnutcase:BAAALgADCgYJEAAAAA==.Derogatory:BAAALgADCgYJDQAAAA==.Desylla:BAAALgADCgQJBAAAAA==.Devildograh:BAAALgAECgQJBwAAAA==.',
Di='Diah:BAAALgAECgQJBwAAAA==.Dibinator:BAAALgADCgEJAQAAAA==.Dio:BAAALgADCgYJDQAAAA==.Diodata:BAAALgAECgEJAgABLgAECggJHQABAKohAA==.Diophantus:BAAALgAECgIJBQABLgAECggJHQABAKohAA==.Divinity:BAAALgAECgEJAQAAAA==.',
Dm='Dmncgdss:BAAALgAECgYJDQAAAA==.',
Do='Dogeatdog:BAAALgADCgcJDgAAAA==.Dohaeriz:BAAALgAECgEJAQAAAA==.Doregoran:BAABLgAECn8oAAIWAAgJGhP3CQCWAQAWAAgJGhP3CQCWAQAAAA==.Dovairous:BAABLgAECn8dAAIaAAgJrQoCVQAxAQAaAAgJrQoCVQAxAQAAAA==.',
Dr='Draakell:BAAALgAECgQJBAAAAA==.Dracopeet:BAABLgAECn8ZAAQTAAcJvwRFagCNAAATAAUJ4wRFagCNAAAVAAQJGwMoMwBQAAAUAAMJwQIJJwArAAAAAA==.Drausella:BAAALgADCgUJCAAAAA==.Dregomalfoy:BAAALgAECgQJBAAAAA==.Drexor:BAAALgAECgQJBwAAAA==.',
Du='Dudè:BAAALgAECgMJAwAAAA==.',
Dv='Dvlzadvocate:BAAALgAECgYJEgAAAA==.',
['Dâ']='Dâggèr:BAAALgAECgUJEAAAAA==.',
['Dü']='Dürin:BAAALgAECgEJAgAAAA==.',
Ec='Echidna:BAABLgAECn8cAAIXAAYJXgoJsADfAAAXAAYJXgoJsADfAAAAAA==.',
Ed='Edict:BAAALgAECgEJAQAAAA==.',
El='Elawen:BAAALgAECgYJCAAAAA==.Elder:BAAALgAECgEJAgAAAA==.Eleblah:BAAALgADCgcJBwAAAA==.Elfkinn:BAACLgAFFH8gAAMbAAYJ/BuLCwC9AQAbAAYJ/BuLCwC9AQAaAAIJ+gAFYwBJAAAuAAQKfyUAAxsACQmmHlQPAF8CABsACQmmHlQPAF8CABoABAlrBY+sAG0AAAAA.Elgund:BAAALgADCgQJBAAAAA==.Elivaniel:BAAALgAECgcJEAAAAA==.',
En='Enlargdcrit:BAAALgAECgMJAwAAAA==.',
Eq='Equinox:BAAALgADCgQJBAAAAA==.',
Er='Ericcdraven:BAABLgAECn8iAAIOAAgJgQ4/MwB1AQAOAAgJgQ4/MwB1AQAAAA==.Erodoria:BAABLgAECn8cAAMFAAkJWx43CgB1AgAFAAgJ9CA3CgB1AgAcAAUJ/hC/EwAFAQAAAA==.',
Et='Eternalfire:BAAALgADCgcJDgABLgAECgkJHQAbANwXAA==.',
Ev='Eve:BAAALgAECgEJAQAAAA==.Eveliong:BAAALgADCgEJAQAAAA==.Evilobama:BAAALgAECgUJBgAAAA==.Evoke:BAAALgAFFAEJAQABLgAFFAUJFgANAMgWAA==.',
Ex='Exzanthia:BAAALgAECgEJAwAAAA==.',
Ey='Eyln:BAABLgAECn8yAAIKAAkJpx3OAgCuAgAKAAkJpx3OAgCuAgAAAA==.',
Fa='Falkor:BAABLgAECn8rAAMVAAkJqBZ/CwAaAgAVAAkJqBZ/CwAaAgAUAAEJ6QKxKQAdAAAAAA==.Fanir:BAAALgAECgcJBwAAAA==.Fatkid:BAAALgAECgcJDwAAAA==.Fayway:BAABLgAECn9DAAIaAAkJviEPBgBPAwAaAAkJviEPBgBPAwAAAA==.',
Fe='Ferral:BAABLgAECn8gAAIQAAkJRBzbBACeAgAQAAkJRBzbBACeAgAAAA==.Festukar:BAAALgAECgUJBwAAAA==.',
Fi='Filthypirate:BAABLgAECn8UAAIZAAgJARGpowAmAQAZAAgJARGpowAmAQAAAA==.Firepower:BAABLgAECn8fAAIDAAgJ5RdZUADkAQADAAgJ5RdZUADkAQABLgAECggJIAAQAJcTAA==.Fistatoosh:BAABLgAECn8iAAICAAgJUCQdBgDTAgACAAgJUCQdBgDTAgAAAA==.',
Fl='Florane:BAAALgAECgUJDAAAAA==.Flyingbotato:BAAALgADCgkJFQABLgAECggJIAAQAJcTAA==.',
Fo='Forevershy:BAAALgADCgkJCQAAAA==.',
Fr='Fries:BAECLgAFFH8HAAIdAAMJjh/5DgC0AAAdAAMJjh/5DgC0AAAuAAQKfxwAAx0ACQkBIkcCAPQCAB0ACQkBIkcCAPQCAA0ABQkGDDd8ANoAAAEuAAUUBAkHABcApg8A.Fruits:BAAALgAECgYJBwAAAA==.',
Ga='Galdavin:BAABLgAECn8XAAIZAAgJnBqgKQB+AgAZAAgJnBqgKQB+AgAAAA==.Galenhaihi:BAAALgADCgUJBQAAAA==.Galexstrasza:BAAALgADCgYJBgABLgAECgUJDgALAAAAAA==.Gallandia:BAAALgADCgEJAQABLgAECgUJDgALAAAAAA==.Gallielynne:BAAALgAECgUJDgAAAA==.Gankdd:BAABLgAECn8UAAMOAAcJLhuSOwBPAQAOAAcJxhmSOwBPAQAeAAMJnRvCHgD4AAAAAA==.Garnnt:BAAALgADCgkJEQAAAA==.',
Gi='Giggles:BAABLgAECn8lAAIMAAgJ+hL1KgCNAQAMAAgJ+hL1KgCNAQAAAA==.Gigglez:BAAALgADCggJCAAAAA==.Gimmothyjr:BAAALgAECgUJBgAAAA==.',
Gl='Glennspyder:BAAALgAECgQJDQABLgAECgQJEgALAAAAAA==.',
Go='Gonzo:BAAALgAFFAEJAQABLgAFFAUJFgANAMgWAA==.Goysoldier:BAAALgAFFAIJAgAAAA==.',
Gr='Greenbean:BAABLgAFFH8UAAIIAAUJ7BGSPwAYAQAIAAUJ7BGSPwAYAQABLgAFFAYJIAAbAPwbAA==.Grelleth:BAAALgAECgQJBAAAAA==.Groddz:BAABLgAECn8WAAIIAAkJvgZ0fwAUAQAIAAkJvgZ0fwAUAQAAAA==.Groto:BAAALgAECgYJBgAAAA==.Grrum:BAABLgAECn8dAAQRAAcJXguJMwA8AQARAAcJkQmJMwA8AQASAAQJDwdxVwCqAAAfAAEJQBFEfgA0AAAAAA==.',
Gu='Gurînkaida:BAAALgADCgEJAQAAAA==.',
Ha='Haell:BAAALgAECgQJBQAAAA==.Hanjo:BAABLgAECn8uAAIHAAkJzyFMBADYAgAHAAkJzyFMBADYAgAAAA==.Hanoa:BAAALgAECgYJCgAAAA==.Harakiri:BAABLgAECn8UAAINAAcJixUvNgCqAQANAAcJixUvNgCqAQAAAA==.Hardare:BAABLgAECn8ZAAIBAAgJzA31JACvAQABAAgJzA31JACvAQAAAA==.Hatookorr:BAAALgAECgUJBQABLgAECggJIAAQAJcTAA==.Hayali:BAABLgAECn8iAAIIAAgJXRYVOgDSAQAIAAgJXRYVOgDSAQAAAA==.',
He='Helledrians:BAAALgAECgQJBgAAAA==.',
Hi='Hiawatha:BAAALgADCgcJAwAAAA==.',
Hm='Hmccrnglbery:BAAALgAECgMJBAABLgAECggJGQABAMwNAA==.',
Ho='Hottogo:BAAALgADCgcJBwAAAA==.',
Hw='Hwei:BAAALgADCgEJAQAAAA==.',
Hy='Hydé:BAAALgAECgcJBwABLgAECgkJHgAcAFggAA==.Hypatia:BAABLgAECn8dAAIBAAgJqiG0DABvAgABAAgJqiG0DABvAgAAAA==.',
['Hä']='Häxan:BAAALgAECgQJBAAAAA==.',
Ia='Iame:BAAALgADCgMJAwAAAA==.Iapetus:BAAALgADCgIJAgAAAA==.',
Ic='Icedchi:BAEBLgAECn8eAAICAAkJ3x9kFgBWAgACAAkJ3x9kFgBWAgAAAA==.',
In='Incite:BAABLgAECn8gAAMgAAkJaA/yCQCTAQAgAAkJZQ/yCQCTAQAhAAUJ+g2QQQAUAQAAAA==.',
Is='Ishvala:BAAALgADCgMJAwAAAA==.',
Ja='Jackpad:BAAALgAECgEJAQAAAA==.Jaland:BAAALgADCgMJAwAAAA==.Jarrel:BAAALgAECgIJBAAAAA==.',
Je='Jellybreak:BAABLgAECn85AAMbAAkJyxVkFgAPAgAbAAkJyxVkFgAPAgAiAAcJqQiEOQCrAAAAAA==.',
Jo='Joeewee:BAAALgAECgYJBgAAAA==.Jonjud:BAAALgAECgYJDAAAAA==.',
Js='Jskimonkpo:BAAALgADCgUJCQAAAA==.',
Ju='Julius:BAAALgAFFAEJAQAAAA==.',
Jy='Jyrian:BAAALgADCgMJAwAAAA==.',
Ka='Kaanâ:BAABLgAECn8xAAIfAAkJWhyCCADWAgAfAAkJWhyCCADWAgAAAA==.Kaelei:BAAALgADCgkJKwAAAA==.Kamine:BAAALgAECgUJEAAAAA==.Kanyeeast:BAAALgAECgYJCgAAAA==.Karnen:BAAALgAECgMJAwAAAA==.Kateblue:BAABLgAECn8tAAIbAAkJhRoMDwBjAgAbAAkJhRoMDwBjAgAAAA==.',
Ke='Kelcier:BAAALgADCgYJBgAAAA==.Kelser:BAABLgAECn8VAAMYAAcJ2B7FBAApAgAYAAcJ2B7FBAApAgAXAAMJoBXuxgDLAAAAAA==.Kensington:BAABLgAECn8hAAIgAAgJdgh9DQBEAQAgAAgJdgh9DQBEAQAAAA==.',
Ki='Kiku:BAABLgAECn8iAAITAAkJYiONBQAAAwATAAkJYiONBQAAAwAAAA==.Kikyou:BAAALgAECgYJBgABLgAECgkJIgATAGIjAA==.Kim:BAABLgAECn8dAAIjAAkJ4QwNGADdAQAjAAkJ4QwNGADdAQAAAA==.Kinrah:BAAALgADCgMJAwAAAA==.Kirandra:BAAALgADCgMJAwAAAA==.Kirëë:BAAALgAECggJCAAAAA==.Kissofdeáth:BAAALgAECgIJAwAAAA==.',
Ko='Korlock:BAABLgAECn8mAAQXAAkJAB4vNAA8AgAXAAgJGR0vNAA8AgAWAAEJAACvbAA7AAAYAAEJPRdZOAA4AAAAAA==.',
Kr='Kreepywife:BAAALgAECgcJDgAAAA==.Krelbelorll:BAAALgAECgEJAQAAAA==.Krowley:BAABLgAECn8lAAINAAkJZg8aMQDiAQANAAkJZg8aMQDiAQAAAA==.',
Ku='Kurast:BAAALgAECgMJAwABLgAECgkJKwAVAKgWAA==.Kuzan:BAACLgAFFH8TAAIDAAUJEB9SQwBVAQADAAUJEB9SQwBVAQAuAAQKfx8AAgMABwl3IfQ2AJgCAAMABwl3IfQ2AJgCAAAA.',
Kx='Kxwono:BAAALgAECgcJBwAAAA==.',
Ky='Kyoyama:BAAALgAECgMJBwABLgAFFAMJBwAYAEceAA==.',
La='Lacious:BAAALgADCgEJAQABLgAECgkJNAAPAGMeAA==.Ladýshinobu:BAABLgAECn8nAAIJAAgJQBB3JwDEAQAJAAgJQBB3JwDEAQAAAA==.Lananar:BAAALgADCgUJBQAAAA==.Layssaenna:BAAALgAECgYJCAAAAA==.',
Le='Leahu:BAABLgAECn84AAIkAAkJBRcQDAD5AQAkAAkJBRcQDAD5AQAAAA==.Lediaa:BAAALgAECgMJAwAAAA==.',
Li='Lifekiller:BAAALgAECgQJCAAAAA==.Lightark:BAAALgAECgEJAgAAAA==.Linekingz:BAAALgADCgEJAQAAAA==.Linetheshamy:BAAALgADCgYJBwAAAA==.Lineurathrot:BAAALgADCgYJCAAAAA==.Littlespyone:BAAALgAECgQJEgAAAA==.Lizardman:BAAALgAFFAEJAQAAAA==.',
Lo='Locholovis:BAABLgAECn8uAAIWAAgJsBLRCgCGAQAWAAgJsBLRCgCGAQAAAA==.Locklicous:BAABLgAECn8WAAMXAAkJ2xcEOgDtAQAXAAkJ2BMEOgDtAQAYAAYJWxW0EABEAQAAAA==.Longhorse:BAACLgAFFH8fAAIEAAUJZCJsDwBsAQAEAAUJZCJsDwBsAQAuAAQKfzEAAwQACQn4JMgFAOACAAQACQmpIsgFAOACAAYABgnhJehbAKwBAAAA.Longknight:BAAALgAECgEJAQAAAA==.Longr:BAAALgAECgYJCwAAAA==.Lorna:BAABLgAECn8VAAIIAAcJYxGVaQBFAQAIAAcJYxGVaQBFAQAAAA==.Lorthimar:BAAALgAECgUJCgABLgAECgkJJgAXAAAeAA==.',
Lu='Lumi:BAABLgAECn8WAAIDAAkJchjOTQDrAQADAAkJchjOTQDrAQAAAA==.Luminarae:BAAALgADCgEJAQAAAA==.Luminouss:BAABLgAFFH8LAAINAAUJThd1HABuAQANAAUJThd1HABuAQABLgAFFAMJBgARAOcUAA==.Lumpia:BAABLgAFFH8IAAIIAAUJGBn+OAAsAQAIAAUJGBn+OAAsAQAAAA==.',
Ly='Lyrinir:BAABLgAECn8dAAMHAAkJ/hkjEQD2AQAHAAkJ/hkjEQD2AQAeAAEJigRlgAAcAAAAAA==.Lyrium:BAABLgAECn8ZAAMcAAgJtRm8CgC4AQAcAAUJDR+8CgC4AQAFAAcJ+RAwJwAuAQABLgAECgkJHQAHAP4ZAA==.',
Ma='Madar:BAABLgAECn8ZAAIXAAYJTgfCuwDMAAAXAAYJTgfCuwDMAAAAAA==.Maggus:BAAALgADCgQJBAAAAA==.Magicgal:BAAALgAECgUJCAAAAA==.Maiden:BAAALgAECgUJBQAAAA==.Maiklytzwhet:BAAALgAECgUJBQAAAA==.Mairon:BAAALgAECgMJBgAAAA==.Malvorak:BAABLgAECn8oAAIEAAgJHhC1IwAqAQAEAAgJHhC1IwAqAQAAAA==.Mande:BAAALgADCgQJBAAAAA==.Mantis:BAAALgAECgkJDAABLgAECgkJKwAVAKgWAA==.Marrock:BAAALgAECgYJEQAAAA==.Marzipain:BAAALgAECgEJAQAAAA==.Mavarasie:BAAALgAECgUJDgAAAA==.Mavaressy:BAAALgAECgMJAwAAAA==.',
Mc='Mcmuffin:BAAALgAECgUJDgAAAA==.',
Me='Mechacattie:BAABLgAECn80AAIPAAkJYx6sEgCxAgAPAAkJYx6sEgCxAgAAAA==.Mediator:BAAALgAECgEJAQAAAA==.Meekerz:BAAALgAECgIJAgAAAA==.Mega:BAAALgAFFAIJAwAAAA==.Melganis:BAAALgADCgMJBAAAAA==.Melissandra:BAABLgAECn8oAAMSAAgJcQy4MQBMAQASAAgJcQy4MQBMAQAfAAIJiAb1dABVAAAAAA==.Mercas:BAAALgAECgcJDwABLgAECgkJJgAiAKMaAA==.Metacallae:BAAALgADCgcJBwAAAA==.Mezi:BAABLgAECn8/AAIfAAkJkyCmBgD9AgAfAAkJkyCmBgD9AgAAAA==.Mezmera:BAAALgADCgUJBgABLgAECgIJAwALAAAAAA==.',
Mh='Mhonster:BAAALgAECgYJBgABLgAECgcJBwALAAAAAA==.',
Mi='Missed:BAAALgAECgQJBQAAAA==.Mittens:BAACLgAFFH8GAAIRAAMJ5xQYKwDVAAARAAMJ5xQYKwDVAAAuAAQKfxkAAx8ACQlbGXQoAK0BAB8ABgn7GXQoAK0BABEABwlvE8ohAIUBAAAA.',
Mo='Mofro:BAAALgADCgQJBAABLgAECgQJBAALAAAAAA==.Mokgunal:BAAALgADCgQJBAAAAA==.Money:BAAALgADCgIJAgABLgAECggJIwAZABghAA==.Moneyshotinc:BAAALgAECgkJCgABLgAECggJIwAZABghAA==.Moraine:BAAALgAECgQJBAAAAA==.Moreki:BAAALgAECgMJAwAAAA==.Morro:BAABLgAECn8sAAIMAAkJIA57LACEAQAMAAkJIA57LACEAQAAAA==.',
Ms='Msvelvet:BAAALgADCgkJGgABLgAECgMJBwALAAAAAA==.',
Mu='Mugiwara:BAACLgAFFH8LAAIBAAQJbCQeCgBtAQABAAQJbCQeCgBtAQAuAAQKfxYAAgEABwntJAkKANcCAAEABwntJAkKANcCAAAA.Mulron:BAABLgAECn8hAAIkAAkJ9w+vEgCQAQAkAAkJ9w+vEgCQAQAAAA==.',
My='Myrica:BAAALgAECggJDQAAAA==.',
['Mö']='Mööve:BAAALgAECgMJAwAAAA==.',
Na='Nallos:BAAALgADCgEJAQAAAA==.Natajapar:BAAALgAECgEJAQABLgAECgcJCQALAAAAAA==.',
Ne='Nefesh:BAABLgAFFH8NAAIIAAUJCwhGUADsAAAIAAUJCwhGUADsAAAAAA==.Neff:BAAALgADCgMJAwAAAA==.',
Ni='Nightingales:BAAALgAECgMJAwAAAA==.',
Ny='Nyomie:BAAALgADCgEJAgAAAA==.Nyyx:BAAALgAECgQJBAABLgAECgQJBQALAAAAAA==.',
Oa='Oakenshíeld:BAACLgAFFH8VAAIbAAYJ4BHHFgBMAQAbAAYJ4BHHFgBMAQAuAAQKfzsAAhsACQlCF9AUAGsCABsACQlCF9AUAGsCAAAA.',
Ob='Obama:BAAALgADCgQJBAAAAA==.',
Og='Oggy:BAAALgAECgkJDAABLgAECgkJKwAVAKgWAA==.',
Ol='Olkwon:BAAALgAFFAIJAwAAAA==.',
On='Onlyfeigns:BAAALgAECgIJAgAAAA==.',
Oo='Oozwoz:BAAALgAECgYJCwAAAA==.',
Or='Orileluu:BAAALgADCggJHQAAAA==.',
Ox='Oxwon:BAAALgAECgYJCwAAAA==.',
Pa='Paisho:BAAALgAECgQJBQAAAA==.Palliera:BAAALgAECgQJBAAAAA==.Pallirot:BAAALgAECggJCAAAAA==.Pallynomial:BAAALgADCgcJCgAAAA==.Pawmuck:BAABLgAECn8lAAIZAAgJ3BftWAC3AQAZAAgJ3BftWAC3AQAAAA==.',
Pe='Peer:BAAALgAECgEJAgAAAA==.Pewpewtazarz:BAAALgAECgUJCQAAAA==.',
Ph='Phancy:BAAALgADCggJDgAAAA==.Phrizzle:BAAALgADCgMJAwAAAA==.',
Pl='Plaguebeard:BAABLgAECn8XAAMGAAcJBx9/PABFAgAGAAcJBx9/PABFAgAEAAUJCRiiJwABAQAAAA==.Plagueblade:BAABLgAECn8qAAMEAAkJUxkmEQDuAQAEAAkJOhgmEQDuAQAGAAEJ3RrwPwFPAAAAAA==.',
Po='Podtinder:BAAALgAECgcJDAABLgAECgkJKwAVAKgWAA==.Poof:BAAALgAECgYJCgABLgAECggJHAAHAKEaAA==.Poseidon:BAAALgAECgIJAgAAAA==.',
Pr='Prescription:BAABLgAECn8WAAMlAAgJ+An0WADyAAAlAAcJ1An0WADyAAABAAcJvQiUQQDrAAAAAA==.Progression:BAAALgAECgEJBgAAAA==.',
Pu='Punish:BAAALgAECgEJAQAAAA==.',
Py='Pyrolord:BAAALgADCgYJCAAAAA==.',
Ra='Ragingrain:BAABLgAECn8fAAIkAAgJSxd/DgDOAQAkAAgJSxd/DgDOAQAAAA==.Rainsshammy:BAAALgAECgEJAQAAAA==.Rainthefire:BAABLgAECn8/AAIPAAkJZRqmKAAxAgAPAAkJZRqmKAAxAgAAAA==.Ralthor:BAAALgADCgMJAwAAAA==.Ramalama:BAAALgAECgEJAQAAAA==.Rassarudk:BAAALgAECgYJCwAAAA==.Ravinfire:BAAALgAECgQJBwAAAA==.Rawktuah:BAAALgAECgMJAwAAAA==.',
Re='Realhelz:BAAALgAECgQJBQAAAA==.Redcross:BAAALgAECgUJCQAAAA==.Redoxx:BAAALgAECgYJDQAAAA==.Restofarian:BAACLgAFFH8WAAINAAUJyBaeIABTAQANAAUJyBaeIABTAQAuAAQKfyMAAg0ACQmJG0UXAFsCAA0ACQmJG0UXAFsCAAAA.',
Rh='Rhagnor:BAAALgAECgMJAwAAAA==.',
Ri='Rianon:BAAALgADCgkJEgABLgAECgkJKQAIAEsaAA==.Rift:BAAALgAECgEJAwAAAA==.Righteous:BAABLgAECn8iAAIfAAcJRRz/FgAJAgAfAAcJRRz/FgAJAgAAAA==.Rizzy:BAABLgAECn8gAAMEAAkJERdRDgAZAgAEAAkJERdRDgAZAgAGAAkJ7ghdZgCSAQAAAA==.',
Ro='Rollinsinc:BAAALgAECgkJAwAAAA==.Roshin:BAAALgAECgEJAgAAAA==.Rotinlock:BAAALgADCgYJDAAAAA==.Rotinshot:BAACLgAFFH8RAAMPAAUJwBJpOwArAQAPAAUJwBJpOwArAQAjAAIJbgPCKQB6AAAuAAQKfygAAw8ACQlsIWUWAIUCAA8ACAmTImUWAIUCACMACAl0GuEQALYBAAAA.',
Ru='Ruin:BAAALgAECgMJBAAAAA==.Rutikee:BAABLgAECn8+AAIaAAgJJhSOMADWAQAaAAgJJhSOMADWAQAAAA==.',
Sa='Sacerdos:BAABLgAECn8VAAIfAAgJlBW8FgAmAgAfAAgJlBW8FgAmAgABLgAECgkJOgAXAAEbAA==.Saeris:BAAALgADCggJCAABLgAECgcJDgALAAAAAA==.Sagordez:BAABLgAECn8gAAQlAAgJSBtgIQD+AQAlAAcJrBpgIQD+AQACAAcJOBW1JQB4AQABAAEJ4Q85mQAtAAABLgAECgkJHgAcAFggAA==.Salima:BAAALgADCgMJAwAAAA==.Saltybrew:BAAALgADCgMJAwAAAA==.Sandrill:BAAALgAECgYJCgABLgAECggJIAAQAJcTAA==.Satorugojo:BAAALgAECgUJBgAAAA==.Savior:BAAALgAECgQJCgAAAA==.Sazed:BAAALgAECggJDgAAAA==.',
Sc='Scrom:BAAALgAECgIJAwAAAA==.',
Se='Seabush:BAAALgAECgEJAQAAAA==.Seastorm:BAAALgAECgEJAgAAAA==.Seeker:BAAALgAECgEJAQAAAA==.Seizon:BAAALgAECggJEwAAAA==.Semila:BAAALgAECgcJCQAAAA==.Sendor:BAAALgAECgYJBgAAAA==.Sepulchure:BAAALgADCgMJAwAAAA==.Serina:BAAALgAECgQJBgABLgAECgkJKgAEAFMZAA==.Serom:BAABLgAECn8ZAAIaAAgJxhdQKAAGAgAaAAgJxhdQKAAGAgAAAA==.Sesshomaaru:BAAALgADCggJEQAAAA==.',
Sh='Shaazrah:BAABLgAECn8fAAICAAkJSyHUCQCNAgACAAkJSyHUCQCNAgAAAA==.Shadowoak:BAAALgAECgEJAQAAAA==.Shadows:BAAALgADCgcJBwAAAA==.Shammyhagär:BAAALgADCgMJAwABLgAECgQJBAALAAAAAA==.Sharalvia:BAAALgADCgUJCAAAAA==.Sharkn:BAAALgAECgEJAQAAAA==.Sharkyo:BAAALgADCgIJAgAAAA==.Sharpshôôter:BAAALgADCgYJAQAAAA==.Sherunn:BAABLgAECn8gAAIbAAcJXAuePAAPAQAbAAcJXAuePAAPAQAAAA==.Shifty:BAAALgAECgEJAgAAAA==.Shiftydon:BAABLgAECn8eAAQQAAkJ0RC0DgC4AQAQAAkJ0RC0DgC4AQAaAAIJ+Q1YpgBeAAAiAAEJMgspdAAhAAAAAA==.Shimakaze:BAABLgAECn85AAIPAAkJoA6PPwDYAQAPAAkJoA6PPwDYAQAAAA==.Shirvana:BAAALgAECgQJBwABLgAECgcJCQALAAAAAA==.Shooters:BAABLgAECn8YAAIjAAkJOx26DQDuAQAjAAkJOx26DQDuAQAAAA==.Shortbow:BAAALgADCgQJBgABLgAECgEJAgALAAAAAA==.Shyminx:BAAALgADCgkJEgAAAA==.Shymistress:BAABLgAECn82AAIPAAkJEiKCCwDuAgAPAAkJEiKCCwDuAgAAAA==.Shåmmy:BAABLgAECn88AAINAAkJ7hNuJgAaAgANAAkJ7hNuJgAaAgAAAA==.',
Si='Simonezer:BAAALgAECgkJAwAAAA==.Sins:BAABLgAECn8nAAIbAAkJVR+qCADAAgAbAAkJVR+qCADAAgAAAA==.Sionell:BAAALgADCgQJBAAAAA==.',
Sk='Skiá:BAABLgAECn9LAAIQAAkJ9B6KAwDPAgAQAAkJ9B6KAwDPAgAAAA==.Skodoosh:BAAALgAECgYJCAAAAA==.Skrinkles:BAAALgAECgYJDgAAAA==.Skyrocket:BAAALgAECgIJAwAAAA==.',
Sl='Slashpoison:BAAALgADCgcJDgAAAA==.Slicedbread:BAACLgAFFH8UAAIJAAYJ/BxqEQCbAQAJAAYJ/BxqEQCbAQAuAAQKfycAAwkACQk7IOwOAJ4CAAkACQk7IOwOAJ4CABkABwkKG6BBACACAAAA.Slorth:BAACLgAFFH8GAAIGAAMJNBb9kADbAAAGAAMJNBb9kADbAAAuAAQKfyIAAgYACAkYGn5KABMCAAYACAkYGn5KABMCAAAA.',
Sm='Smallfrye:BAAALgAECgEJAQAAAA==.',
Sn='Snizzlaki:BAABLgAECn8+AAICAAkJQg9uHwCiAQACAAkJQg9uHwCiAQAAAA==.',
So='Sofa:BAAALgADCgkJDAAAAA==.Solaene:BAAALgAECgcJBwAAAA==.Soundsmystic:BAAALgADCgUJBQAAAA==.',
Sp='Sparkilies:BAAALgADCgYJBgAAAA==.Sparkleglory:BAAALgAECgMJAwAAAA==.Spicybreath:BAAALgAECgQJBAABLgAECgcJEQALAAAAAA==.Spicydemon:BAAALgAECgcJEQAAAA==.Spicydrood:BAAALgAECgEJAQAAAA==.Spicytotems:BAAALgAECgEJAQAAAA==.Splaash:BAAALgAECgMJAwAAAA==.Splàsh:BAABLgAECn8aAAQNAAkJ3x8aBgAQAwANAAkJ3x8aBgAQAwAMAAUJrRNOagCYAAAdAAIJRg2iLgBnAAAAAA==.',
St='Starwolfy:BAAALgAECgUJBQAAAA==.Steakman:BAAALgADCgIJAgAAAA==.Stoneboot:BAAALgAECggJEwAAAA==.',
Su='Sumaria:BAABLgAECn8iAAISAAgJiAFPZAB3AAASAAgJiAFPZAB3AAAAAA==.',
Sw='Sweatycrits:BAAALgAECggJDQAAAA==.Sweetvixen:BAAALgAECgMJBwAAAA==.',
Sy='Sylvanasthot:BAAALgADCgYJDAAAAA==.',
Ta='Taana:BAAALgAECgUJBQAAAA==.Takbez:BAABLgAECn8gAAIQAAgJlxOSCwAGAgAQAAgJlxOSCwAGAgAAAA==.Tandria:BAAALgAECgUJBQAAAA==.Tarot:BAAALgADCgEJAQAAAA==.Taterhops:BAAALgADCgIJAgABLgAECgkJJQADAFQfAA==.Tattered:BAAALgADCgEJAQAAAA==.Tauru:BAABLgAECn8fAAMaAAgJRRl6IAA6AgAaAAgJRRl6IAA6AgAbAAEJphEwhAA1AAAAAA==.Tazale:BAAALgAECgYJBgABLgAECgYJBgALAAAAAA==.',
Te='Teakaachu:BAAALgAECggJEgAAAA==.Terdanator:BAABLgAECn8eAAMdAAgJFhZRDADfAQAdAAgJFhZRDADfAQAMAAEJLQZUrQAjAAAAAA==.Tetranis:BAAALgADCgQJBgAAAA==.',
Th='Thanathot:BAAALgADCgMJAwAAAA==.Thanatus:BAABLgAECn86AAQXAAkJARs9HwBjAgAXAAkJARs9HwBjAgAYAAQJyRAgHgC8AAAWAAEJzgf2eAAqAAAAAA==.Themia:BAAALgADCgMJAwAAAA==.',
Ti='Tiari:BAABLgAECn8oAAMJAAkJCRs8DQCzAgAJAAkJCRs8DQCzAgAZAAYJ0APKBgGhAAAAAA==.Timesink:BAAALgAECgQJBQAAAA==.Tisane:BAAALgAECgMJAwAAAA==.',
Tn='Tntclepriest:BAAALgAECgcJDQABLgAECgYJFAAYAGkVAA==.',
Tr='Tralline:BAAALgADCgMJAgAAAA==.Tranzig:BAAALgADCgUJBQAAAA==.Tridius:BAABLgAECn8XAAQSAAgJkxYhGgDtAQASAAgJkxYhGgDtAQARAAYJpBjINQAwAQAfAAIJfB4NSgCtAAAAAA==.Trollins:BAAALgAECgIJAgAAAA==.',
Tu='Turdanator:BAABLgAECn9NAAMSAAkJDhnqEQA+AgASAAkJDhnqEQA+AgAfAAcJ/gtsQQAzAQAAAA==.',
Tw='Twizzlers:BAAALgADCgEJAQAAAA==.',
Up='Upgraydd:BAAALgAECgIJBAABLgAECgcJEQALAAAAAA==.',
Ur='Uraenus:BAAALgAECgcJEwAAAA==.Urahrotar:BAAALgADCgUJBgAAAA==.Uriah:BAABLgAECn8lAAIPAAkJPxVULgAYAgAPAAkJPxVULgAYAgAAAA==.Ursúla:BAABLgAFFH8IAAIXAAMJ6QzNeADDAAAXAAMJ6QzNeADDAAABLgAFFAYJIAAbAPwbAA==.Uryu:BAAALgAECgQJBAAAAA==.Urïah:BAAALgAECgYJBgABLgAECgkJJQAPAD8VAA==.',
Ut='Utherr:BAABLgAFFH8FAAIZAAMJ6Br8WwDiAAAZAAMJ6Br8WwDiAAAAAA==.',
Va='Valaravaus:BAAALgAECgEJAwAAAA==.Valionandros:BAAALgAECgYJBwAAAA==.Vanaril:BAAALgAECgMJAwAAAA==.Vashirr:BAAALgAECgMJAwAAAA==.',
Ve='Veldonir:BAAALgAECgEJAQAAAA==.Vergus:BAAALgAECgQJBAAAAA==.',
Vi='Violin:BAAALgAECgIJAwABLgAECggJDAALAAAAAA==.Violinmax:BAAALgAECgYJDQABLgAECggJDAALAAAAAA==.Viral:BAAALgAFFAEJAQAAAA==.',
Vo='Voidnova:BAAALgAECgEJAQAAAA==.Vonnie:BAAALgAECgUJBQAAAA==.',
Vy='Vynlerinis:BAABLgAECn8eAAIcAAkJWCDDAgC7AgAcAAkJWCDDAgC7AgAAAA==.',
['Vé']='Végeta:BAAALgAECgIJAgABLgAECgkJKwAVAKgWAA==.',
Wa='Wardestroyer:BAAALgAECggJEQAAAA==.Wardwhelp:BAABLgAECn8cAAIHAAgJoRrzDQD/AQAHAAgJoRrzDQD/AQAAAA==.',
Wi='Wifehaver:BAABLgAECn8oAAICAAkJuR8HEwAQAgACAAkJuR8HEwAQAgAAAA==.Wildmist:BAAALgAECgMJAwAAAA==.Winniedapoo:BAABLgAECn80AAIXAAgJ2BuwMwAFAgAXAAgJ2BuwMwAFAgAAAA==.Winterpaw:BAAALgAECgEJAQABLgAECgkJKgAEAFMZAA==.',
Wo='Wooloo:BAACLgAFFH8ZAAQWAAgJbxsfAwBvAQAXAAcJtxySHgCxAQAWAAQJ+xgfAwBvAQAYAAEJAADKBABZAAAuAAQKfygAAxcACQmzJSYOANUCABcACQmzJSYOANUCABYABAlPHXogAE8BAAAA.',
Wu='Wurm:BAAALgAECgIJAgAAAA==.',
Wy='Wynona:BAAALgAECgUJBQAAAA==.',
Xa='Xanagore:BAABLgAECn8mAAMOAAgJfSK+DQCMAgAOAAgJACK+DQCMAgAHAAEJ0RYlTgA1AAAAAA==.Xanllan:BAAALgAECgQJBgAAAA==.Xanthecat:BAAALgAECgQJBAAAAA==.Xanzul:BAAALgAECgcJDwABLgAECggJJgAOAH0iAA==.',
Xk='Xkwon:BAAALgAFFAEJAQAAAA==.Xkwøn:BAACLgAFFH8XAAImAAQJ3hr2AwBRAQAmAAQJ3hr2AwBRAQAuAAQKfzsAAiYACAkbIqkCAIQCACYACAkbIqkCAIQCAAAA.',
Xu='Xunie:BAABLgAECn8eAAIGAAgJmxFYYQCeAQAGAAgJmxFYYQCeAQAAAA==.',
Xx='Xximage:BAABLgAECn8dAAMnAAkJ1CRfAQDIAgAnAAkJ1CRfAQDIAgADAAEJAACeWgFLAAAAAA==.',
Yu='Yulìe:BAAALgADCgcJBwAAAA==.',
Za='Zaibloom:BAAALgADCggJFgAAAA==.Zana:BAABLgAECn8ZAAIIAAgJPRJpcQAzAQAIAAgJPRJpcQAzAQAAAA==.Zaretan:BAAALgADCggJEAAAAA==.',
Zb='Zbrute:BAABLgAECn8nAAIPAAkJ9xgrIABbAgAPAAkJ9xgrIABbAgAAAA==.',
Ze='Zeffen:BAAALgAECgIJBAABLgAECgYJGQAXAE4HAA==.Zefphenn:BAAALgAECgQJBgABLgAECgYJGQAXAE4HAA==.Zenny:BAAALgADCggJEwAAAA==.',
Zi='Zildroghar:BAAALgADCgcJBwAAAA==.Zivz:BAAALgADCgUJBQAAAA==.',
Zo='Zokohjin:BAABLgAECn8lAAMGAAkJWByFKgBOAgAGAAkJWByFKgBOAgAEAAIJ+xcNPgCNAAAAAA==.',
Zu='Zulgar:BAAALgAFFAEJAQABLgAFFAgJFgADAFgZAA==.Zulpher:BAAALgADCgYJEgAAAA==.',
['Ðo']='Ðondon:BAAALgADCgQJBQAAAA==.Ðoppelgänger:BAAALgAECgEJBQAAAA==.',
['Øk']='Økwøn:BAACLgAFFH8PAAIDAAMJGBWOOQC3AAADAAMJGBWOOQC3AAAuAAQKfzsAAwMACAkRHyJKAFkCAAMACAn4HiJKAFkCACcABAnvIUkHACwBAAAA.',
['ße']='ßeorn:BAAALgADCgMJAwAAAA==.',
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
