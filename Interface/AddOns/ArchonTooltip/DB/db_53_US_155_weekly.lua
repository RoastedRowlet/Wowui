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

local lookup = {'DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Hunter-Survival','Unknown-Unknown','Priest-Discipline','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Paladin-Holy','Mage-Frost','Mage-Arcane','Paladin-Retribution','Druid-Guardian','Paladin-Protection','Rogue-Subtlety','Priest-Holy','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Evoker-Preservation','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Mage-Fire','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Frost','Evoker-Augmentation','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abashai:BAAANQAECgYIEAAAAA==.',
Ae='Aellyria:BAAANQADCgEIAQAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECgcIGAABAMMcAA==.',
Ai='Ainsworth:BAEANQAECgMIAwABNQAECgcIIAACAMQMAA==.',
Ak='Akaili:BAAANQAECgQIBwAAAA==.',
Al='Alexiya:BAABNQAECn8gAAIDAAgKHBJ1EQDoAQADAAgKHBJ1EQDoAQAAAA==.Allacari:BAABNQAECn8WAAIEAAYKAheXCADCAQAEAAYKAheXCADCAQAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQADCgYICgABNQAECgQJBgAFAAAAAA==.Alstadin:BAAANQADCgMJAwAAAA==.Alucardd:BAAANQAECgIIAwAAAA==.',
Am='Amanda:BAABNQAECn8dAAIGAAgK6w/LCQCyAQAGAAgK6w/LCQCyAQAAAA==.Amonamarth:BAAANQAECgYIEAAAAA==.',
An='Anabelleigh:BAAANQABCggIEQAAAA==.Andrise:BAABNQAECn8gAAQHAAcKWBkzXQD0AQAHAAcKWBkzXQD0AQAIAAYKiBPzGgCwAQAJAAUKyRhKiACLAQAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAABNQAECn8bAAMBAAcKGhjxRQD9AQABAAcKGhjxRQD9AQAKAAMKohE9nACfAAAAAA==.',
Ap='Apol:BAABNQAECn8dAAILAAgK/w6mcgC8AQALAAgK/w6mcgC8AQAAAA==.',
Ar='Arachne:BAABNQAECn8oAAMMAAkK1xmRBADeAgAMAAkK1xmRBADeAgANAAUKxwy+PgEgAQAAAA==.Arafina:BAAANQABCgUICQABNQAECgkJJQALADMNAA==.Arakar:BAABNQAECn8lAAILAAkKMw1GYwDrAQALAAkKMw1GYwDrAQAAAA==.Aralynne:BAAANQAECgUIDgAAAA==.Arcee:BAAANQADCgIIAgAAAA==.Arch:BAAANQAECgQIBgAAAA==.Ardori:BAAANQAECgYICgABNQAECggIEwAFAAAAAA==.Arlïnn:BAAANQAECgQIBgABNQAECgcICwAFAAAAAA==.Armorya:BAABNQAECn8qAAIOAAkK2xiPZABpAgAOAAkK2xiPZABpAgAAAA==.Armyofone:BAAANQAECgQICAAAAA==.Artaius:BAABNQAECn8bAAIPAAcKOiVnCADyAgAPAAcKOiVnCADyAgAAAA==.Arthonius:BAAANQADCgQIBAAAAA==.Arthuun:BAAANQAECggIEAAAAA==.Artom:BAAANQADCgUJBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggICAABNQAECgcIEgAFAAAAAA==.Astarog:BAAANQAECgUIDwAAAA==.',
At='Atafloosy:BAEBNQAECn8bAAIHAAcK/h+KOgByAgAHAAcK/h+KOgByAgAAAA==.Athelf:BAABNQAECn8cAAIOAAkKOhVWfwAmAgAOAAkKOhVWfwAmAgAAAA==.Attina:BAAANQADCggICAAAAA==.',
Au='Aubriell:BAAANQAECgQIBwAAAA==.',
Ay='Ayrnerdam:BAAANQAECgUICQAAAA==.',
Az='Azureas:BAAANQAECgEIAQAAAA==.',
Ba='Babelfish:BAABNQAECn8bAAIQAAgKORY3HgD0AQAQAAgKORY3HgD0AQAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQJBgAAAA==.Batarang:BAABNQAECn8bAAIRAAcKDwggKQB4AQARAAcKDwggKQB4AQAAAA==.',
Be='Bealzulbub:BAAANQABCgQIBwAAAA==.Bearbarian:BAABNQAECn8mAAIPAAkK1wq9IQCEAQAPAAkK1wq9IQCEAQAAAA==.Beastkael:BAAANQAECgQIBgAAAA==.Beg:BAABNQAECn8hAAISAAkKBBCDXgACAgASAAkKBBCDXgACAgAAAA==.Belfalas:BAAANQABCgQICAAAAA==.Beliir:BAAANQADCggICAABNQAECgcIIwAQAIQeAA==.Berghain:BAAANQADCgQIAgAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAABNQAECn8cAAISAAgKYBNDXAAJAgASAAgKYBNDXAAJAgAAAA==.Beytryx:BAAANQAECgIJAwAAAA==.',
Bi='Bittycakes:BAAANQADCgUIBQAAAA==.',
Bl='Blackstar:BAAANQAECgIIAgAAAA==.Bladeoftruth:BAABNQAECn8bAAIKAAkK7B9JFwDxAgAKAAkK7B9JFwDxAgAAAA==.Blaize:BAAANQADCgYICQAAAA==.Blitzwing:BAAANQAECgQIBQAAAA==.Bloodyaggro:BAAANQAECgQIBwAAAA==.',
Bo='Bobapstab:BAAANQADCgIIAgAAAA==.Bodin:BAAANQADCgcIBwAAAA==.Bonnabelle:BAABNQAECn8oAAISAAkK2AYEeACuAQASAAkK2AYEeACuAQAAAA==.Boombawks:BAAANQAECgEIAQAAAA==.Bor:BAAANQAECgUIBQABNQAECggIGwAPADolAA==.Bos:BAAANQAECgcIEgAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgYIEgAFAAAAAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECggIGgATAHgZAA==.Briest:BAAANQAECgQIBAABNQAECggIGgATAHgZAA==.Brownbar:BAAANQAECgYICQAAAA==.Bruid:BAABNQAECn8aAAMTAAgKeBl/JgDqAQATAAcKzBd/JgDqAQAUAAcKvhJtTgCiAQAAAA==.Bruneigin:BAAANQAECgYICAAAAA==.',
Ca='Cailey:BAAANQAECgIIBAAAAA==.Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwAFAAAAAA==.Cantliquor:BAAANQABCgQIBAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgQIAwAAAA==.Carrin:BAABNQAECn89AAIOAAgKOCLnOgDjAgAOAAgKOCLnOgDjAgAAAA==.Catalyia:BAABNQAECn8mAAIVAAkK4xfqTACFAgAVAAkK4xfqTACFAgAAAA==.Catris:BAAANQAECgQIBgAAAA==.Catset:BAABNQAECn8aAAIUAAgK9weJWgBlAQAUAAgK9weJWgBlAQAAAA==.',
Ce='Cecea:BAAANQADCgEIAQAAAA==.',
Ch='Chaahk:BAAANQAECgQIBAABNQAECggIGwAPADolAA==.Charades:BAAANQADCgYIDAAAAA==.Charlton:BAAANQAECggICwABNQAECgkJFwAWADsLAA==.Chazzo:BAABNQAECn8bAAIXAAkK2hEbfQAeAgAXAAkK2hEbfQAeAgAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQAECgYIDQAAAA==.',
Co='Commy:BAABNQAECn8bAAMNAAgKXxAqywDtAQANAAgKXxAqywDtAQAMAAEKng0UQgA+AAAAAA==.Concorde:BAAANQAECgQJCAAAAA==.Copiousconns:BAABNQAECn8jAAIYAAcKAAk/JQBIAQAYAAcKAAk/JQBIAQAAAA==.Corlock:BAAANQADCgYIDAAAAA==.',
Cr='Craitos:BAAANQABCgYIDQAAAA==.Cranjis:BAAANQAECgYIBgAAAA==.Crimsonfury:BAAANQAECgUIBgAAAA==.',
Cu='Cubos:BAABNQAECn8rAAIZAAkKFyYxAgDWAwAZAAkKFyYxAgDWAwAAAA==.Cutlash:BAAANQAECgQIBAAAAA==.Cutslash:BAAANQAECgIIAgABNQAECgQIBAAFAAAAAA==.',
Cy='Cynaea:BAAANQADCgQJBAABNQAECgkJFwAWADsLAA==.',
Da='Daemona:BAABNQAECn8hAAIaAAgKbhaZMgARAgAaAAgKbhaZMgARAgAAAA==.Daieniceis:BAAANQAECgYIEgAAAA==.Dalkurn:BAACNQAFFH8RAAITAAYKOiLUAQBYAgATAAYKOiLUAQBYAgA1AAQKfygAAhMACQrrI9cHAEQDABMACQrrI9cHAEQDAAAA.',
De='Decayy:BAACNQAFFH8LAAIKAAUKlRg3DgBrAQAKAAUKlRg3DgBrAQA1AAQKfyMAAgoACQqIIgMWAPsCAAoACQqIIgMWAPsCAAAA.Deceptakahn:BAABNQAECn8iAAIPAAcKGwYpNQD0AAAPAAcKGwYpNQD0AAAAAA==.Derailedbeef:BAABNQAECn8rAAMXAAkKaRogRwCxAgAXAAkKTBkgRwCxAgAbAAQKwxrqFgAsAQAAAA==.Deydoralia:BAABNQAECn80AAILAAkKMSEZDgBYAwALAAkKMSEZDgBYAwAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.',
Dl='Dlwlrma:BAAANQAECgUIBQAAAA==.',
Dn='Dnme:BAABNQAECn8eAAIcAAgK+RJNKQD1AQAcAAgK+RJNKQD1AQAAAA==.',
Do='Doieha:BAAANQADCggIDwABNQAECggIEwAFAAAAAA==.Doneldus:BAAANQAECgQIBgAAAA==.Dool:BAAANQAECgQIBwAAAA==.Dorfdragon:BAABNQAECn8dAAIdAAcKfgh6IABNAQAdAAcKfgh6IABNAQAAAA==.Dorfe:BAABNQAECn8oAAIeAAgKMRQjLQAsAgAeAAgKMRQjLQAsAgAAAA==.Dorflock:BAAANQADCggIDwAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgcIGQAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Drewgarymore:BAABNQAECn8mAAMPAAgK3xRuHgCmAQAUAAgK2BHPQQDtAQAPAAcKDhduHgCmAQAAAA==.Drough:BAAANQAECgQICAABNQAECgkJFgAfAMsMAA==.Drzeal:BAAANQADCgYIBgAAAA==.',
Du='Dukker:BAAANQABCgIIAgAAAA==.Dumblêdorê:BAAANQADCgMIAwABNQAFFAYICwAOAPEPAA==.Durandall:BAACNQAFFH8LAAIOAAYK8Q8PCADIAQAOAAYK8Q8PCADIAQA1AAQKfyIAAg4ACQq8HFJqAFoCAA4ACQq8HFJqAFoCAAAA.Durleap:BAAANQAECgQIBwAAAA==.Durthmaul:BAAANQAECgcIEAABNQAFFAYICwAOAPEPAA==.',
Dw='Dwarflock:BAABNQAECn8bAAIZAAgKGhVFZgAkAgAZAAgKGhVFZgAkAgAAAA==.',
Dy='Dylpickl:BAAANQAFFAIIAgAAAA==.Dylán:BAAANQAECgQIBAAAAA==.Dymàs:BAAANQAECgYIEgAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQAECgEIAQAAAA==.Elow:BAAANQADCgIIAgAAAA==.',
Er='Erazminash:BAAANQAECgMJBAAAAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQAECgQIBwAAAA==.Ess:BAAANQAECgQIBgAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgYIBwAFAAAAAA==.Evvie:BAAANQAECgYIDQAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAABNQAECn8dAAIOAAcKsxtffAAtAgAOAAcKsxtffAAtAgAAAA==.Falcondor:BAAANQADCgMIAwAAAA==.Fallin:BAAANQAECgUIBQAAAA==.Fantarius:BAACNQAFFH8MAAISAAUKZRH1DwCQAQASAAUKZRH1DwCQAQA1AAQKfysAAxIACQotIm4lANMCABIACQotIm4lANMCAAYAAQqIBQAuACgAAAAA.Fantazee:BAAANQADCgUIBQABNQAFFAUIDAASAGURAA==.Fatdono:BAAANQAECgYIEQAAAA==.',
Fi='Fibbs:BAABNQAECn8ZAAIPAAcKvBrqEQA+AgAPAAcKvBrqEQA+AgAAAA==.Fikti:BAABNQAECn8rAAMgAAgKqBzeBACDAgAgAAgKuxveBACDAgAZAAUKKRgpqAB+AQAAAA==.Firetongue:BAAANQADCgUIBQAAAA==.Firocios:BAABNQAECn8YAAILAAYKZRPfgQCRAQALAAYKZRPfgQCRAQAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.',
Fo='Fossilz:BAAANQADCggJCAAAAA==.Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAABNQAECn8XAAIEAAYKhRE2CQCoAQAEAAYKhRE2CQCoAQABNQAECggIHAAEAP8UAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQAECgQIBQAAAA==.Frostyfella:BAACNQAFFH8MAAINAAUK6R0KFwC6AQANAAUK6R0KFwC6AQA1AAQKfy4AAg0ACQpnItYZAG4DAA0ACQpnItYZAG4DAAE1AAEKAggCAAUAAAAA.',
Fu='Furman:BAAANQADCgMIAwAAAA==.Fuzzycakes:BAAANQADCggICAAAAA==.',
['Fá']='Fáith:BAAANQAECgUICQAAAA==.',
Ga='Garypotter:BAABNQAECn8lAAIcAAgKciJEDAAbAwAcAAgKciJEDAAbAwAAAA==.Gazooks:BAAANQADCgYIEQAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gi='Gillacs:BAAANQADCgMJAwAAAA==.',
Gl='Gleave:BAABNQAECn8pAAIVAAgKpSKDHQAgAwAVAAgKpSKDHQAgAwAAAA==.Glâdiátor:BAAANQADCgMIAwAAAA==.',
Go='Goodbrew:BAAANQAECgUIDQAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIIBQAAAA==.Grindelbald:BAABNQAECn8aAAMNAAkK0hJ1kQBcAgANAAkK0hJ1kQBcAgAhAAIK4ghQCQByAAAAAA==.',
Gt='Gtfofupá:BAAANQAECgMIBgAAAA==.',
Gu='Gushee:BAABNQAECn8aAAIbAAYK0hmxDgDBAQAbAAYK0hmxDgDBAQAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgIIAgAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Hae:BAAANQADCgIIAgAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgUIDAAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Hanamari:BAACNQAFFH8OAAIiAAYKRAaMBwB0AQAiAAYKRAaMBwB0AQA1AAQKfx8AAyIACQrgFgMhACACACIACQrgFgMhACACACMAAQrrAedUAB0AAAAA.Hanoe:BAAANQADCggICAAAAA==.Harakrron:BAAANQAECgEIAQAAAA==.Harleyquìnn:BAAANQAECgEIAQAAAA==.Harydresden:BAABNQAECn8XAAINAAcKAQPYOAEqAQANAAcKAQPYOAEqAQAAAA==.Hawkesmage:BAAANQAECgIIAgAAAA==.Hawkslayer:BAAANQAECgQIBgAAAA==.Hazule:BAAANQAECgIIAwABNQAECggIGwAHAGwXAA==.',
He='Healadín:BAAANQADCggICAAAAA==.Hedgelord:BAACNQAFFH8KAAIUAAUKUQ1aEQBQAQAUAAUKUQ1aEQBQAQA1AAQKfyAAAhQACApzHs0oAI0CABQACApzHs0oAI0CAAAA.Heyboyy:BAAANQAECgYIBgABNQAECgkJLwAVAIYkAA==.',
Hi='Hisky:BAAANQAECgQIBgAAAA==.',
Ho='Hobe:BAABNQAECn8YAAIZAAcKsh8xWwBCAgAZAAcKsh8xWwBCAgAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgkJHQAZADMVAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQAECgQIBgAAAA==.Huntaredead:BAAANQAECgQIBgABNQAECgkJIgAZALggAA==.',
Ic='Icyblades:BAABNQAECn8aAAIBAAgKZwqYZgBzAQABAAgKZwqYZgBzAQAAAA==.',
Il='Ilidania:BAAANQAECgYIBwAAAA==.Ilyna:BAABNQAECn8eAAIZAAcKgQoZsABrAQAZAAcKgQoZsABrAQAAAA==.',
Im='Immortalnut:BAAANQAECgcIEAAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.Ittyycakes:BAAANQADCgcIBwAAAA==.',
Ja='Jackypan:BAAANQADCgUIBQAAAA==.Jaedis:BAAANQAECgUICQAAAA==.Jaktar:BAAANQAECggIEgAAAA==.Jane:BAAANQADCgMIAgAAAA==.Janet:BAABNQAECn8bAAIfAAkKrhAEFADjAQAfAAkKrhAEFADjAQAAAA==.Jani:BAAANQADCgQIBAABNQAECgkJGwAfAK4QAA==.Janiina:BAAANQADCgYIDQAAAA==.',
Je='Jezak:BAAANQADCgIIAgABNQAECgQJBgAFAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQAECgQIBwAAAA==.Joobs:BAAANQAECgcIEgAAAA==.Joosh:BAAANQAECgUIBQAAAA==.',
Js='Jslice:BAACNQAFFH8LAAIXAAUKmg8xFQB6AQAXAAUKmg8xFQB6AQA1AAQKfx4AAhcACQrHINpFALUCABcACQrHINpFALUCAAAA.',
Ju='Juda:BAAANQAECgUICAAAAA==.Jurant:BAAANQABCgQJAwAAAA==.Jurucil:BAAANQAECgEIAQAAAA==.',
Ka='Kaelys:BAABNQAECn8aAAMLAAYKrQ8noABBAQALAAYKrQ8noABBAQAOAAEKAAB5zAEdAAAAAA==.Kahliea:BAAANQAECgQIBgAAAA==.Kaidance:BAAANQAECgcICQAAAA==.Kaisaze:BAAANQAECgcIDgAAAA==.Kamiga:BAAANQADCgEIAQABNQAECggIEwAFAAAAAA==.Kapachka:BAAANQAECgUICQAAAA==.Karbide:BAAANQAECgIIAgAAAA==.Kardisa:BAAANQABCgIIAgAAAA==.Kateri:BAAANQAECgEIAQAAAA==.Katmarie:BAAANQAECgIIAwAAAA==.Kazothor:BAAANQAECgQIBgAAAA==.',
Ke='Kelborne:BAAANQAECgIIAgAAAA==.Keria:BAACNQAFFH8TAAIaAAcKsB4JAgCNAgAaAAcKsB4JAgCNAgA1AAQKfzgAAhoACQrvJc8CAMYDABoACQrvJc8CAMYDAAAA.Keyz:BAAANQAECgYICwAAAA==.',
Ki='Kibbwarrior:BAAANQADCggICAAAAA==.Kiretsu:BAABNQAECn8cAAMMAAkK0BAmGAA2AQANAAgKlw7X3wDFAQAMAAUK/w8mGAA2AQAAAA==.',
Kn='Knowén:BAAANQADCgYIBgAAAA==.',
Ko='Koder:BAAANQADCgYIBgAAAA==.Kovus:BAAANQAECgYIDQAAAA==.',
Kr='Kragami:BAAANQAECgQIBwAAAA==.Krelien:BAAANQAECgUICgAAAA==.Krispee:BAAANQAECgcIEQAAAA==.Kristanya:BAABNQAECn8mAAIWAAgKfwejKABsAQAWAAgKfwejKABsAQAAAA==.Kristina:BAEANQAECggICAAAAA==.',
Ks='Ks:BAAANQAECgQIBAAAAA==.',
Ku='Kulaidmage:BAABNQAECn8bAAINAAgKKBXxsAAfAgANAAgKKBXxsAAfAgAAAA==.Kurtcowbain:BAAANQAECgYIEgAAAA==.Kushies:BAAANQADCgUIBQAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAFFAUIDAAJAOoDAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAABNQAECn8wAAIkAAkKUCN1AQCRAwAkAAkKUCN1AQCRAwAAAA==.Lamashtu:BAABNQAECn8hAAIlAAgKpBWlHgBGAgAlAAgKpBWlHgBGAgAAAA==.Lasciel:BAAANQADCgcIBwAAAA==.Lashar:BAAANQADCgYIBgAAAA==.Layli:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.Layssar:BAAANQADCgYICwAAAA==.',
Le='Leddy:BAAANQAECggIEQAAAA==.Leiman:BAAANQABCgQIBQAAAA==.Lemmy:BAAANQAECgcIBwAAAA==.Lenabug:BAAANQABCgIIAgAAAA==.Lexiê:BAAANQAECgYIEwAAAA==.',
Li='Lightninjack:BAAANQAECgEIAQAAAA==.Lightsworn:BAAANQADCgEIAQAAAA==.Lilifa:BAABNQAECn8eAAIjAAcK+SCBDgCXAgAjAAcK+SCBDgCXAgAAAA==.Lilillidari:BAABNQAECn8eAAIaAAkKPBwkHQCsAgAaAAkKPBwkHQCsAgABNQAFFAYIFQABAIwZAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAACNQAFFH8VAAQBAAYKjBndBgCsAQABAAUKABndBgCsAQAmAAMK5xYFDwDlAAAKAAEKAAA8OAAgAAA1AAQKfzgAAyYACQo0Jl8KAEYDACYACQpyJF8KAEYDAAEACQoLIAQSACYDAAAA.Lilunholy:BAAANQAECgcIEwABNQAFFAYIFQABAIwZAA==.Linali:BAAANQAECgIIAgAAAA==.Lirianna:BAAANQADCgMIAwAAAA==.Lisey:BAAANQAECgEIAgAAAA==.Listari:BAAANQADCgQIBAAAAA==.Lisyao:BAAANQAECgQICAAAAA==.Littany:BAABNQAECn8bAAMLAAkKMQsYaADcAQALAAkKMQsYaADcAQAOAAcKUA7uxgCIAQAAAA==.Livane:BAAANQAECgMIBQAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Looneytoones:BAAANQAECgUIBQAAAA==.Lowground:BAAANQAECgEIAQAAAA==.',
Lu='Lucïna:BAABNQAECn8YAAIaAAcK6AsCSQB9AQAaAAcK6AsCSQB9AQAAAA==.Ludk:BAABNQAECn8mAAIKAAgKjiJFFAAIAwAKAAgKjiJFFAAIAwAAAA==.Luk:BAABNQAECn8yAAMcAAgK5xUPKwDlAQAcAAgK5xUPKwDlAQAkAAUKqxJSGQAaAQABNQAECgkJFgAOAGwOAA==.Lumiela:BAAANQAECgQIBwAAAA==.Luminah:BAAANQAECgIJAgAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQAECgEIAQAAAA==.Lunì:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.Luxshot:BAAANQADCggIDwAAAA==.',
['Lê']='Lêxie:BAAANQADCgcIBwAAAA==.',
['Ló']='Lóner:BAABNQAECn8kAAMeAAkKYQ+zKwA1AgAeAAkKYQ+zKwA1AgARAAEKtghOUAA6AAAAAA==.',
['Lü']='Lüni:BAAANQADCgMIAwABNQAECgEIAQAFAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAABNQAECn8hAAIXAAgKHhFSkQDsAQAXAAgKHhFSkQDsAQAAAA==.Magicg:BAACNQAFFH8GAAIlAAUKuQVgCgBMAQAlAAUKuQVgCgBMAQA1AAQKfx8AAyUACQpdG1oVALMCACUACQpdG1oVALMCABIAAQqmChr1ADwAAAAA.Magordito:BAABNQAECn8bAAINAAgK3gec8ACmAQANAAgK3gec8ACmAQABNQAECgkJJAAeAGEPAA==.Mairek:BAACNQAFFH8GAAINAAMKPQ8dOwDRAAANAAMKPQ8dOwDRAAA1AAQKfzMAAg0ACQrAHbdDAPwCAA0ACQrAHbdDAPwCAAAA.Maleigoron:BAABNQAECn8aAAIZAAkK1QnfjADCAQAZAAkK1QnfjADCAQAAAA==.Malkuri:BAABNQAECn8lAAMCAAgKTBhLKgD2AQAVAAcK5BfafgAMAgACAAgKlxFLKgD2AQAAAA==.Malorysera:BAACNQAFFH8KAAMdAAQKliEoCgC7AAAdAAIK7SEoCgC7AAAnAAIK5yAsCAC1AAA1AAQKfyYABB0ACQqCIK4IAOoCAB0ACQp2Ha4IAOoCABYABgpZF2skAJ0BACcAAwo+HiESAA0BAAAA.Martrion:BAAANQABCgUIBQAAAA==.Matsuma:BAAANQAECgMIAwAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAAANQAECgYIEwAAAA==.Menirva:BAAANQAECgcIEQABNQAECggIJQACAEwYAA==.Merv:BAAANQAECgUIBgAAAA==.Metapal:BAAANQAECggIEgABNQAFFAUIDAAJAOoDAA==.Metasham:BAACNQAFFH8MAAIJAAUK6gNsEgBDAQAJAAUK6gNsEgBDAQA1AAQKfy4AAgkACQqXGwEmAOkCAAkACQqXGwEmAOkCAAAA.',
Mi='Miiaa:BAAANQAECgcIEgAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQAECgEIAQAAAA==.',
Mo='Moirasha:BAAANQAECgYIEQAAAA==.Monkeydluffy:BAAANQAECgEIAQAAAA==.Monran:BAAANQAECgYIEAAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgQJBgAAAA==.Morphingtime:BAABNQAECn8YAAQDAAcKBxg4GAB0AQAUAAcK1w8lUQCUAQADAAUKDBs4GAB0AQATAAUKwhUwPAA7AQAAAA==.Mortivus:BAAANQAECgYIDQAAAA==.',
Mu='Mudsworn:BAAANQAECgIIAgAAAA==.Muggs:BAAANQADCggIDgAAAA==.Mulvane:BAAANQAECgYIDQAAAA==.Mustachio:BAABNQAECn8aAAINAAcKQxsHqwArAgANAAcKQxsHqwArAgAAAA==.',
Mw='Mwc:BAACNQAFFH8MAAMRAAYKQhazBgCjAQARAAUK5hGzBgCjAQAeAAIKVCNGFQCcAAA1AAQKfxYAAxEACQqDJEAFADYDABEACQqDJEAFADYDAB4ABAp3FgpoAAoBAAAA.',
Mz='Mziao:BAAANQADCggIFQAAAA==.',
Na='Nashia:BAAANQADCgMIAwAAAA==.Nazureshal:BAAANQADCggICAABNQAECgUIDQAFAAAAAA==.',
Ne='Neall:BAAANQAECgYIEgAAAA==.Negaryu:BAAANQAECgUIBQAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nethryx:BAAANQADCgMIAwAAAA==.Nevets:BAAANQAECgYIEgAAAA==.',
Ni='Nightbird:BAAANQAECgMIAwAAAA==.Nightheals:BAAANQADCgYIBgABNQAECgcIIAAHAFgZAA==.',
No='Nonna:BAABNQAECn8mAAIJAAgKHQmXhgCQAQAJAAgKHQmXhgCQAQAAAA==.Noslrac:BAAANQAECgUICgAAAA==.Notamonk:BAAANQAECgIIAgAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECggIMAAAAQ==.',
Ny='Nyxjr:BAAANQADCgIJAgAAAA==.',
Ob='Oblast:BAABNQAECn82AAINAAkK6yToCgCrAwANAAkK6yToCgCrAwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAABNQAECn8WAAImAAcKMA9ESwCFAQAmAAcKMA9ESwCFAQAAAA==.',
On='Onlydks:BAABNQAECn8YAAQmAAgKUw5fRgCfAQAmAAgKUw5fRgCfAQABAAMKjAuUsgCHAAAKAAEKAAAi2wAhAAABNQAFFAQICgAbANwMAA==.Onlyslams:BAACNQAFFH8KAAMbAAQK3AxfAQAyAQAbAAQK3AxfAQAyAQAXAAIKggWfNwBaAAA1AAQKfyAAAxsACApTIBUFANUCABsACApfHhUFANUCABcABwpiGFmoALMBAAAA.Onlytrolling:BAAANQAECgQIBAAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orter:BAABNQAECn8YAAIBAAcKwxwKPAAuAgABAAcKwxwKPAAuAgAAAA==.',
Ot='Ottan:BAAANQADCgYICwAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.Ovo:BAAANQADCgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQADCgcICAAAAA==.Papsfear:BAAANQAECgYIEgAAAA==.Parceh:BAABNQAECn8fAAMHAAgKzCAiOgB0AgAHAAcK8B8iOgB0AgAJAAYKeiMxTABCAgAAAA==.',
Ph='Phydaux:BAAANQAECgIIBAAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgYIDQAAAA==.',
Pr='Priestialitÿ:BAAANQADCgIIAgABNQAECgcIHgAjAPkgAA==.Pringle:BAAANQADCgYIEgABNQAECgQIBQAFAAAAAA==.Prosciutto:BAABNQAECn8fAAIlAAkKRxfuEwDEAgAlAAkKRxfuEwDEAgAAAA==.Proxima:BAAANQAECgEIAQAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAACNQAFFH8KAAISAAQK7wOPGgASAQASAAQK7wOPGgASAQA1AAQKfyYAAxIACQp3DSBxAMUBABIACQp3DSBxAMUBAAYAAQq8AZkwACIAAAAA.Punn:BAAANQAECgcIDAABNQAECgkJIgAZALggAA==.Punnisher:BAABNQAECn8iAAMZAAkKuCDRGQAdAwAZAAkKuCDRGQAdAwAYAAEKvhsSbQBDAAAAAA==.Pureflow:BAAANQAECgcIDgAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAAANQAECggIEwAAAA==.Quicks:BAABNQAECn8kAAIOAAkKsxvVTwCiAgAOAAkKsxvVTwCiAgAAAA==.Quáckys:BAAANQAECggICAAAAA==.',
Ra='Radünz:BAAANQABCgQIBwABNQAECggIJwADAE0dAA==.Raelianna:BAAANQAECgQIDAABNQAECggIMgANAKklAA==.Raewyna:BAAANQAECgYIEAAAAA==.Rahruhai:BAAANQAECggIEwAAAA==.Rain:BAAANQAECgQIBwAAAA==.Raine:BAABNQAECn8VAAMJAAkKKRgObADYAQAJAAcK+hUObADYAQAHAAcKLxsLZgDXAQAAAA==.Rainingblood:BAABNQAECn8WAAIOAAcKEwb6+AAmAQAOAAcKEwb6+AAmAQAAAA==.Rainjar:BAAANQAECgYIEwAAAA==.Rancîd:BAABNQAECn8cAAQBAAcKihSfWgChAQABAAcKihSfWgChAQAKAAUKtwiWhQDjAAAmAAMKtAdTjAB7AAABNQAECgkJFgAfAMsMAA==.Ranron:BAABNQAECn8WAAMfAAkKywyIJQASAQAXAAcKwgnLyABgAQAfAAYK/guIJQASAQAAAA==.Raphael:BAABNQAECn8eAAMBAAcKiRYdXQCXAQABAAcKWxIdXQCXAQAKAAUK2hiRXAB9AQAAAA==.Rasik:BAABNQAECn8mAAIXAAgKmh2XRQC2AgAXAAgKmh2XRQC2AgAAAA==.Ravenblood:BAAANQAECgUICQAAAA==.Rayel:BAAANQAECgYIEAAAAA==.Raylyn:BAAANQAECgMIBQAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBQAAAA==.Rheanon:BAAANQAECgEIAQAAAA==.Rhodrage:BAAANQADCgEIAQAAAA==.Rhome:BAABNQAECn8qAAISAAkKSiQSBQCgAwASAAkKSiQSBQCgAwAAAA==.Rhox:BAAANQADCggJEQAAAA==.',
Ri='Rialu:BAABNQAECn8mAAISAAgKEBI/bQDSAQASAAgKEBI/bQDSAQAAAA==.Ribald:BAAANQAECgUICQAAAA==.Rickgrimes:BAABNQAECn8xAAMmAAgKWyWEDwARAwAmAAgKTSGEDwARAwABAAcK4CGTKACVAgAAAA==.Risandra:BAAANQAECgcIBwAAAA==.',
Ro='Roid:BAABNQAECn8gAAMLAAkKLw7IWwACAgALAAkKLw7IWwACAgAOAAIKawKpkAE9AAAAAA==.Rotcorpse:BAAANQAECggIDwAAAA==.',
Ru='Ruddam:BAAANQAECgQIBwAAAA==.',
['Rä']='Räveñz:BAABNQAECn8gAAIPAAgKrRIcGwDGAQAPAAgKrRIcGwDGAQAAAA==.',
Sa='Saintabes:BAACNQAFFH8OAAISAAUKARsoDQC0AQASAAUKARsoDQC0AQA1AAQKfx0AAhIACQovIAQ8AHYCABIACQovIAQ8AHYCAAAA.Sakurah:BAABNQAECn8cAAMHAAgK+BWBUwAVAgAHAAgK+BWBUwAVAgAJAAEKAABqTgEkAAAAAA==.Samelan:BAAANQADCgUIBQAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanicor:BAAANQAECgQIBAAAAA==.Sanrinn:BAABNQAECn8VAAIVAAcKVBdcbwAwAgAVAAcKVBdcbwAwAgAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAACNQAFFH8RAAINAAUKAw1bIgBtAQANAAUKAw1bIgBtAQA1AAQKfyYAAg0ACQqeFJKGAHECAA0ACQqeFJKGAHECAAAA.Sarahjupiter:BAAANQAECgcIDAABNQAFFAUIEQANAAMNAA==.Sargarach:BAAANQADCgEIAQAAAA==.Sarrin:BAAANQADCgQIBAABNQAECggIJQAaAPIZAA==.',
Sc='Scapegoat:BAEANQAECgcIHwAAAQ==.Scraime:BAAANQAECgIIAgAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seilah:BAABNQAECn8ZAAITAAcKniO1EADNAgATAAcKniO1EADNAgAAAA==.Seliah:BAAANQAECgUIDQAAAA==.Senuya:BAAANQADCgQIBAABNQAECgYIEgAFAAAAAA==.Seräph:BAAANQAECgQICwAAAA==.',
Sh='Shadowglade:BAABNQAECn8oAAIUAAgK3xaXNQA6AgAUAAgK3xaXNQA6AgAAAA==.Shadowmourne:BAAANQABCgIIAgAAAA==.Shalltear:BAAANQAECgQIBgAAAA==.Shamizzle:BAAANQAECgcIEQAAAA==.Shammydavis:BAABNQAECn8YAAIHAAYKiiJ+RgBEAgAHAAYKiiJ+RgBEAgAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shocknorris:BAAANQADCgYIBgAAAA==.Shrapnel:BAABNQAECn8YAAIVAAYKTgTO6QAoAQAVAAYKTgTO6QAoAQAAAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAABNQAECn8gAAIaAAgKJA1zPgDCAQAaAAgKJA1zPgDCAQAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sk='Skullchopper:BAAANQADCggICAABNQAECgcIIwAcAIUQAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAABNQAECn8bAAQZAAgKlx74iQDJAQAZAAUKvRz4iQDJAQAYAAIKWh+rQgC4AAAgAAEKnSIsIgBoAAAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAABNQAECn8mAAIoAAgK5QNPEAAZAQAoAAgK5QNPEAAZAQAAAA==.',
So='Solarica:BAAANQABCgIIAgAAAA==.Solómon:BAAANQAECgQIBQAAAA==.Sorabjr:BAAANQAECgQIBgAAAA==.Sorin:BAAANQADCgYIBgABNQAECgcICwAFAAAAAA==.Soulbreaker:BAABNQAECn8jAAIcAAcKhRDZMwCfAQAcAAcKhRDZMwCfAQAAAA==.Southy:BAAANQAECgYIEgAAAA==.',
Sp='Sparxs:BAAANQAECgQIBAAAAA==.Spookz:BAAANQAECgEIAQAAAA==.',
St='Starblunder:BAAANQAECgIIAgAAAA==.Storglen:BAAANQADCgUIBQAAAA==.Stormdeth:BAAANQADCgUICAAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stormwild:BAAANQADCgUJBQABNQAECgIIAgAFAAAAAA==.Stylemonk:BAACNQAFFH8WAAIiAAYKXCbrAQB7AgAiAAYKXCbrAQB7AgA1AAQKfyQAAiIACQoGItkFAHEDACIACQoGItkFAHEDAAAA.',
Su='Sulfalloway:BAAANQAECgcIDAAAAA==.Sumawfulot:BAABNQAECn8bAAIXAAgKjRvOYgBjAgAXAAgKjRvOYgBjAgAAAA==.Sunsparrow:BAAANQAECgQIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcICQAAAA==.Sweetheal:BAAANQADCgUIBQAAAA==.Swiftysarah:BAAANQADCggICAABNQAFFAUIEQANAAMNAA==.',
Sy='Syraelia:BAAANQADCggICAAAAA==.Syvarris:BAABNQAECn8pAAQEAAkKlx/yAgDyAgAEAAgK9B/yAgDyAgACAAUKWQj2TgDtAAAVAAEKah35PwFXAAAAAA==.',
['Sî']='Sîpher:BAAANQAECgQIBAABNQAECgQICwAFAAAAAA==.',
Ta='Taeveren:BAAANQADCgYICQAAAA==.Tamesßond:BAAANQAECgQIBwAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanguo:BAAANQADCgcIFQAAAA==.Tanksnotanks:BAAANQADCgYJFAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAABNQAECn8jAAIQAAcKhB5EFQBVAgAQAAcKhB5EFQBVAgAAAA==.',
Te='Teagan:BAAANQADCgcIEwAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEBNQAECn8gAAMCAAcKxAwrOQCCAQACAAcKxAwrOQCCAQAEAAEKBgyBEwAyAAAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thalimus:BAAANQADCgYICgAAAA==.Thelle:BAAANQAECgYICwABNQAFFAcIEwAaALAeAA==.Thewhitelion:BAAANQAECgQIBQAAAA==.',
Ti='Tigg:BAACNQAFFH8OAAMmAAYKTBC3BADEAQAmAAYKTBC3BADEAQAKAAEKAAA6PgAVAAA1AAQKfycAAyYACQrRIdQXAMgCACYACQrRIdQXAMgCAAEAAQoAAG7WAD0AAAAA.Tikifiki:BAAANQAECgYIEAAAAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toodoo:BAAANQADCgIIAgABNQAECgkJFgAfAMsMAA==.Toshidot:BAACNQAFFH8QAAIZAAYKLxL2CADcAQAZAAYKLxL2CADcAQA1AAQKfyYAAhkACQqFIZYeAAcDABkACQqFIZYeAAcDAAAA.Totemtila:BAAANQAECgEIBAABNQAECgkJIwAZADQjAA==.Totendead:BAAANQABCgMIBQAAAA==.',
Tr='Translucent:BAABNQAECn8pAAIHAAcKyBB1hgB2AQAHAAcKyBB1hgB2AQAAAA==.Trazatra:BAABNQAECn8XAAMWAAkKOwtIKgBZAQAWAAcKWwpIKgBZAQAdAAUKWA3hIgAtAQAAAA==.Truckah:BAAANQAECgYIEgAAAA==.Tràvdog:BAABNQAECn8UAAIXAAgKTRAhmADbAQAXAAgKTRAhmADbAQAAAA==.',
Tu='Tunalongarms:BAAANQAECgQICAABNQAECgYIBwAFAAAAAA==.Tuonadari:BAAANQADCgUIDQAAAA==.Tuonai:BAABNQAECn8YAAMiAAYKGw63OgA5AQAiAAYKGw63OgA5AQApAAMK/AF0LABWAAAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.Tustone:BAAANQADCgYICgAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQAECgIIAgAAAA==.',
Ul='Ularin:BAAANQAECgQIBAAAAA==.Ultimatum:BAAANQAECgUICgAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwAFAAAAAA==.Vaelena:BAAANQADCgUIBQAAAA==.Vahla:BAAANQAECgEIAQABNQAECggIJQAaAPIZAA==.Valkuridk:BAACNQAFFH8YAAMmAAYKqCb7AACCAgAmAAYKgSb7AACCAgABAAUKJSbxAgARAgA1AAQKfykAAyYACQqOJmoDAKsDACYACQp7JmoDAKsDAAEACArtJbEkAKwCAAAA.Valorlight:BAAANQADCggICAAAAA==.Vandellor:BAAANQADCgQIBAABNQAECggIGwAPADolAA==.Vandy:BAABNQAECn8gAAMSAAkK4xbjSQBEAgASAAkKARXjSQBEAgAGAAQKqRamEgD7AAAAAA==.',
Ve='Vedo:BAACNQAFFH8JAAICAAQKMQ9eEQAiAQACAAQKMQ9eEQAiAQA1AAQKfxkAAgIACQqlG6QUALcCAAIACQqlG6QUALcCAAAA.Vedora:BAAANQAECgcIEgAAAA==.Velf:BAAANQADCgEIAQAAAA==.Veradis:BAAANQADCgYIEgAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.',
Vi='Vinland:BAAANQADCgYIEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virelith:BAAANQAECgEIAQAAAA==.Virulent:BAAANQAECgEIAQABNQAECgcIEgAFAAAAAA==.',
Vl='Vladak:BAAANQAECgcIDgAAAA==.',
Vo='Voc:BAAANQAECggIEgAAAA==.Voz:BAAANQAECgIIAgABNQAECgcIEgAFAAAAAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAABNQAECn8mAAIVAAkKjSH9EQBXAwAVAAkKjSH9EQBXAwAAAA==.',
Vy='Vyridiondk:BAAANQAECgIIAwAAAA==.Vyx:BAAANQAECgQIBgAAAA==.',
Wa='Waggi:BAAANQAECgQIBQAAAA==.Waymán:BAAANQADCggIJgAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Weelilcurse:BAAANQADCggIDgAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wh='Whuh:BAAANQAECgUIBQAAAA==.',
Wu='Wumply:BAACNQAFFH8OAAIlAAUKyQoTCQBwAQAlAAUKyQoTCQBwAQA1AAQKfyMAAiUACQqAFNggAC4CACUACQqAFNggAC4CAAAA.',
['Wà']='Wàyman:BAAANQADCgUIEgAAAA==.',
['Wä']='Wäyman:BAABNQAECn8lAAIIAAgKQhV+EgA+AgAIAAgKQhV+EgA+AgAAAA==.',
Xa='Xaranthia:BAAANQAECggIEgAAAA==.',
Xm='Xmcdizzle:BAABNQAECn8aAAINAAcKQhhFxQD4AQANAAcKQhhFxQD4AQAAAA==.',
Xy='Xylarra:BAABNQAECn8lAAMaAAgK8hnKIgCBAgAaAAgK8hnKIgCBAgAcAAIK/BepXQB1AAAAAA==.',
Ya='Yautja:BAABNQAECn8mAAICAAcK8xXtKwDoAQACAAcK8xXtKwDoAQAAAA==.Yazule:BAABNQAECn8bAAIHAAgKbBfIVQANAgAHAAgKbBfIVQANAgAAAA==.',
Yo='Yodawg:BAABNQAECn8bAAIKAAcK8BiZPQAJAgAKAAcK8BiZPQAJAgABNQAECgkJIgAQAE4dAA==.Yoruba:BAAANQADCgMIAwABNQAECgUIDwAFAAAAAA==.',
Yu='Yuenna:BAAANQADCggICAABNQAECggIEwAFAAAAAA==.',
Za='Zairroth:BAAANQADCgYIBwAAAA==.Zamali:BAABNQAECn8hAAIKAAgKLAvYYQBnAQAKAAgKLAvYYQBnAQAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBQAFAAAAAA==.Zartella:BAAANQAECgUIBwABNQAECgYICwAFAAAAAA==.Zaxon:BAAANQAECgIIAgAAAA==.',
Ze='Zendraza:BAABNQAECn8XAAIdAAcKRwNDJwD2AAAdAAcKRwNDJwD2AAAAAA==.Zephyrion:BAACNQAFFH8MAAIKAAQKJRDoFQD8AAAKAAQKJRDoFQD8AAA1AAQKfy0AAgoACQrFGiYhAKkCAAoACQrFGiYhAKkCAAE1AAQKBggTAAUAAAAA.Zepplin:BAAANQAECgcIEAAAAA==.Zerenity:BAAANQAECgQIBgAAAA==.Zetro:BAABNQAECn8tAAIQAAkKDQwrJgCqAQAQAAkKDQwrJgCqAQAAAA==.',
Zr='Zreydyn:BAAANQADCgcIFQAAAA==.',
Zu='Zuma:BAABNQAECn8fAAIMAAgKPBYpCQBBAgAMAAgKPBYpCQBBAgAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
