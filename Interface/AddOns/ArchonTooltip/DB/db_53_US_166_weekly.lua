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

local lookup = {'Priest-Shadow','Mage-Arcane','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Devourer','Shaman-Enhancement','Druid-Restoration','Hunter-BeastMastery','DeathKnight-Frost','Shaman-Elemental','Mage-Frost','Paladin-Retribution','Paladin-Protection','Mage-Fire','Druid-Balance','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Druid-Feral','Monk-Windwalker','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Paladin-Holy','Warrior-Protection','Warlock-Demonology','Hunter-Marksmanship','Warlock-Destruction','Druid-Guardian','Evoker-Devastation','Monk-Mistweaver','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','Priest-Discipline',}
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abyssdk:BAAANQAECgEJAQABNQAECgkJNQABAF4mAA==.Abyssfurry:BAAANQADCggJCAABNQAECgkJNQABAF4mAA==.',
Ac='Acadêmica:BAABNQAECoEaAAICAAcKvRCMrgDaAQACAAcKvRCMrgDaAQAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adcosmos:BAAANQADCggIEQABNQAECgYIEAADAAAAAA==.Adebaio:BAABNQAECoEsAAIEAAkKWyRaBgB5AwAEAAkKWyRaBgB5AwAAAA==.',
Ae='Aegislashh:BAAANQAECgUIDwAAAA==.Aerlath:BAACNQAFFIELAAIFAAUK+BX3BACjAQAFAAUK+BX3BACjAQA1AAQKgScAAgUACQrdJBsDAJsDAAUACQrdJBsDAJsDAAAA.Aetulia:BAAANQAECgYIEQAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQADCggIHgADAAAAAA==.',
Ag='Aggroster:BAAANQAECgIIAgAAAA==.Agnestesia:BAAANQAECgQIBwAAAA==.',
Ah='Ahrathor:BAAANQAECgUICwAAAA==.',
Ak='Akasta:BAABNQAECoEfAAIGAAcKCh2ADABrAgAGAAcKCh2ADABrAgAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.Akâme:BAAANQAECgcIBwABNQAECggIFQAHAMocAA==.',
Al='Alascayoung:BAAANQAECgEIAQAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Aldrathion:BAAANQAECgEIAQABNQAECgkJMQAIAO8jAA==.Aledk:BAAANQAECgYIBgAAAA==.Alessan:BAAANQADCggIDwAAAA==.Alessary:BAAANQADCgYIBwAAAA==.Alfurieb:BAAANQAECgQICAAAAA==.Alianar:BAAANQADCgMIAwAAAA==.Alicel:BAABNQAECoEaAAMEAAkKoB7TJABeAgAEAAgKRSDTJABeAgAJAAEKfhHJggA1AAAAAA==.Altreir:BAAANQADCgcIFAABNQADCggIHgADAAAAAA==.Aluny:BAAANQAECgUIBwABNQAFFAUICAAKADQIAA==.Aluxxious:BAAANQAECgQICQAAAA==.Alëcream:BAAANQAECgYICwAAAA==.Alíne:BAAANQAECgUIDQAAAA==.',
Am='Amrb:BAAANQADCgIIAgAAAA==.Amøm:BAAANQAECgUICwAAAA==.',
An='Anadirtei:BAAANQAFFAUIAQAAAA==.Anduinwill:BAAANQAECgEIAQAAAA==.Andärilho:BAAANQADCgcIEgABNQAECgUIBwADAAAAAA==.Ankados:BAAANQAFFAEIAQAAAA==.Ankapos:BAAANQAFFAEIAQAAAA==.Annish:BAAANQADCgYJCwAAAA==.Anrond:BAAANQAECgUIBQAAAA==.Anthorforged:BAAANQAECgYIEQAAAA==.',
Ap='Apocalipse:BAABNQAECoEpAAILAAkKvxppAwDTAgALAAkKvxppAwDTAgAAAA==.',
Aq='Aquillez:BAAANQAECgQJBAAAAA==.',
Ar='Araurz:BAAANQAECgQIBQABNQAECgYIEgADAAAAAA==.Arinn:BAAANQAECgYIEAAAAA==.Arkcirce:BAAANQAECgUICQABNQAECgYIEAADAAAAAA==.Arkw:BAAANQADCgMIAwAAAA==.Arnaldinho:BAAANQADCgQICAABNQAECgYIDAADAAAAAA==.Arthega:BAAANQAECgEIAQABNQAFFAUICwAFAPgVAA==.Artradian:BAAANQAECgQIBQAAAA==.Arucàrd:BAAANQADCgYJCgAAAA==.Aryethi:BAABNQAECoEeAAIMAAgKuA4AeQDZAQAMAAgKuA4AeQDZAQAAAA==.',
As='Asafe:BAAANQADCgMIBAABNQAECgUICgADAAAAAA==.Ashabellanar:BAAANQAECgQICAAAAA==.Ashenna:BAAANQAECgcIDAAAAA==.Aslatiel:BAAANQADCgYIBgABNQAECgYIEQADAAAAAA==.',
Au='Aurdraen:BAAANQAECgEIAQAAAA==.',
Av='Avanthara:BAAANQAECgQIDQAAAA==.',
Aw='Awk:BAAANQAECgYIDgAAAA==.',
Az='Azuros:BAAANQABCgIIAgAAAA==.',
['Aø']='Aøc:BAABNQAECoEoAAIMAAkKrRUtSwBlAgAMAAkKrRUtSwBlAgAAAA==.',
Ba='Babara:BAAANQABCgYIBwAAAA==.Babyfart:BAABNQAECoEeAAMNAAcK0hEUJgBSAQANAAYKGhQUJgBSAQAMAAIKvwZWJAFmAAAAAA==.Bakushiterra:BAAANQAECgYIDAAAAA==.Barao:BAAANQAECgcIEQAAAA==.Barriguinha:BAAANQAECgIIAgAAAA==.Baskervile:BAAANQADCgYIBgABNQAECgUIBwADAAAAAA==.Batlemage:BAAANQABCgQIBgAAAA==.Batmano:BAAANQADCggIGAAAAA==.',
Be='Belezona:BAAANQADCgQIBAAAAA==.Beornin:BAAANQADCgMIAwAAAA==.Betawizard:BAAANQAECgMIAwAAAA==.',
Bh='Bhast:BAAANQADCggICAABNQAECggIEgADAAAAAA==.Bherg:BAAANQAECgUIBwAAAA==.',
Bi='Biskademon:BAABNQAECoEfAAIFAAgKoRsfFwB2AgAFAAgKoRsfFwB2AgAAAA==.Bizum:BAAANQADCgcIDAAAAA==.Bizumgãoo:BAAANQAECgQIBgAAAA==.',
Bj='Bjørn:BAAANQADCgQIBAAAAA==.',
Bl='Blackee:BAAANQAECgIIBAAAAA==.Blackwatch:BAAANQAECgEJAgAAAA==.Blecktk:BAAANQAECgcIDgAAAA==.Blitzkrig:BAACNQAFFIEJAAMOAAQKahAvAAASAQAOAAMKAQ8vAAASAQACAAEKphRWPwBXAAA1AAQKgSYAAg4ACQr2IIcAADMDAA4ACQr2IIcAADMDAAAA.Bloodlioness:BAAANQAECgEIAQAAAA==.Bloodswar:BAAANQADCggICAAAAA==.Bloodyclaw:BAAANQADCggIHAAAAA==.',
Bo='Bolkien:BAAANQAECgEIAgAAAA==.Boomgoesyou:BAABNQAECoEWAAIPAAgK1Q3NQAClAQAPAAgK1Q3NQAClAQAAAA==.Bourdriel:BAAANQAECgYIDwAAAA==.',
Br='Bradoki:BAAANQAECgMIBgAAAA==.Brancalleone:BAAANQAECgIJAgAAAA==.Brazukmaiden:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.Brisawave:BAABNQAECoEnAAIQAAkKhiK/CwBBAwAQAAkKhiK/CwBBAwAAAA==.Brizagato:BAAANQAECgcIEgAAAA==.Brizzarda:BAAANQADCggICAAAAA==.Broke:BAAANQAECgQIBQAAAA==.Brujaria:BAAANQAECgQICAAAAA==.Bruxxaum:BAAANQADCgEIAQAAAA==.Brád:BAAANQAECggIEgAAAA==.',
Bu='Bushido:BAAANQADCgYIEgAAAA==.Bustgril:BAAANQAECgQIBwAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQAECgQIBAAAAA==.',
Ca='Caiquebmq:BAAANQAECgEIAQAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgYIEwADAAAAAA==.Calanguinhe:BAAANQAECgEIAQAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAAANQAECgQIDAAAAA==.Canard:BAAANQADCgUICAABNQAECggIDgADAAAAAA==.Canards:BAAANQAECgIIAQABNQAECggIDgADAAAAAA==.Cannibal:BAAANQAECgEIAQAAAA==.Carinha:BAAANQADCggJAgAAAA==.Carloxamã:BAABNQAECoEdAAIGAAkK/B00BAA6AwAGAAkK/B00BAA6AwAAAA==.Cassisus:BAAANQADCggICAAAAA==.Catarnaldo:BAAANQADCgYICQABNQAECgYIDAADAAAAAA==.Cathiseev:BAABNQAECoEbAAMRAAgKGB+GCgDYAgARAAgKGB+GCgDYAgASAAQKpA5qEQDDAAAAAA==.Cathury:BAAANQAECgMJCAAAAA==.Catÿ:BAAANQAECgUIEgABNQAFFAMIBgATABolAA==.Cavernozo:BAAANQAECgcICwAAAA==.Caxola:BAAANQADCgIIAgAAAA==.',
Ce='Celfier:BAAANQAECgQIBAAAAA==.Cenarioss:BAAANQAECgIIAgAAAA==.Cerino:BAAANQADCgQIBAAAAA==.Cevadão:BAAANQAECggIEwABNQAECggIEgADAAAAAA==.',
Ch='Chaleira:BAAANQADCgUICQAAAA==.Changjin:BAAANQAECgMIBAAAAA==.Cheweir:BAAANQAECgQIBgAAAA==.Chiclete:BAABNQAECoEfAAMUAAgKnROACgAkAgAUAAgKnROACgAkAgAHAAcK6BGdIgCzAQAAAA==.Chopz:BAAANQAECgIIAgAAAA==.Chovor:BAAANQAECgUIBQAAAA==.Chrizantm:BAAANQAECgQIBwABNQAECgYIEgADAAAAAA==.Chucknòórris:BAAANQAECgIIAwAAAA==.Chøcøballs:BAAANQABCgQIBAAAAA==.',
Cl='Clairë:BAAANQAECggIDwAAAA==.Claude:BAAANQADCgQIBQAAAA==.Clbalena:BAAANQADCgEIAQAAAA==.Clio:BAAANQAECgQIEgAAAA==.',
Co='Cockcroft:BAAANQADCgYIDAABNQAECgkJHgAVAJkOAA==.Coionir:BAAANQAECgYIDQAAAA==.Coiovoker:BAAANQADCgEIAQABNQAECgYIDQADAAAAAA==.Coldblooded:BAAANQADCgcIBwABNQADCggIDAADAAAAAA==.Comunistaa:BAABNQAECoEkAAIKAAkKKyRsBQCwAwAKAAkKKyRsBQCwAwAAAA==.Corruptionz:BAAANQAECgQICAAAAA==.Corstine:BAAANQAECgQIBgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.Couldovisk:BAAANQADCgIJAgAAAA==.',
Cr='Cronosxdm:BAAANQAFFAEJAQAAAA==.Crucyatus:BAAANQAECgcIEwAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
['Cá']='Cássia:BAAANQADCggICAAAAA==.',
['Cå']='Cåssio:BAAANQAECgYIDwAAAA==.',
['Cÿ']='Cÿgnus:BAAANQAECggIDAABNQAECggIJQAWAMolAA==.',
Da='Dadashi:BAAANQADCggICAAAAA==.Danadinn:BAAANQADCgcIBwABNQAECgIIAgADAAAAAA==.Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAABNQAECoEbAAMXAAgKgA/iDQCCAQAYAAgKrw5fewDUAQAXAAcKOw7iDQCCAQAAAA==.Darklendio:BAAANQADCgUICgAAAA==.Daroncosp:BAAANQADCgIJAgAAAA==.Darü:BAAANQAECgQIBAAAAA==.Dashuman:BAABNQAECoEWAAIZAAgKeBvJJwCUAgAZAAgKeBvJJwCUAgAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dayshine:BAAANQADCgUIBQAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadguth:BAAANQAECggJBwAAAA==.Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUICAABNQAECgYIEQADAAAAAA==.Deceive:BAAANQAECgcIDwAAAA==.Defroque:BAAANQAECgUJBQAAAA==.Deimons:BAAANQADCgMIAwAAAA==.Deis:BAAANQADCgUIBAAAAA==.Delarÿn:BAAANQAECgQIBAAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Demzumilde:BAAANQAECgMIBAAAAA==.Denevy:BAABNQAECoEaAAIaAAgK5AwRFACIAQAaAAgK5AwRFACIAQAAAA==.Deraelda:BAAANQADCgMIBAAAAA==.Derbster:BAAANQAECgcICwAAAA==.Destructiom:BAABNQAECoEZAAIIAAcKxx5wPgBoAgAIAAcKxx5wPgBoAgAAAA==.',
Dh='Dhamburguer:BAABNQAECoEaAAIFAAgKEx0YEgC0AgAFAAgKEx0YEgC0AgAAAA==.Dhanadrai:BAAANQAECgYIEwAAAA==.',
Di='Diamalboy:BAAANQADCgEIAQAAAA==.Diamath:BAAANQADCgUJBQAAAA==.Diggop:BAAANQAECgIIAwAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQADAAAAAA==.Dima:BAABNQAECoEdAAIQAAkK6R5LDwAhAwAQAAkK6R5LDwAhAwAAAA==.',
Do='Dornaa:BAAANQAECgUIBQAAAA==.Dosmagos:BAAANQABCgUIBwAAAA==.Doulce:BAAANQAECgMICAAAAA==.',
Dr='Dracarysz:BAAANQADCggIDQAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Dragonbaby:BAAANQADCgUIBQAAAA==.Drainetty:BAAANQAECgEIAQAAAA==.Dranacs:BAAANQAECggIDgAAAA==.Dreampollys:BAAANQAECgEIAQABNQAFFAIIAgADAAAAAA==.Dreamremix:BAAANQAFFAIIAgAAAA==.Dreyol:BAAANQADCgYICQAAAA==.Drts:BAABNQAECoEnAAICAAkKhh0xNQADAwACAAkKhh0xNQADAwAAAA==.',
Du='Dudupokas:BAAANQAECgQIBAAAAA==.Dumar:BAAANQAECgYICgAAAA==.Duromargh:BAAANQADCgMIAwAAAA==.',
Ed='Eduarthas:BAAANQAECgYICwAAAA==.',
Eg='Egoist:BAAANQADCggJDwAAAA==.',
El='Elementys:BAAANQAECgQICAAAAA==.Elemëntum:BAAANQAECgEIAQAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECgkJMQAIAO8jAA==.Elinaara:BAABNQAECoEXAAINAAcKFgyxJwBFAQANAAcKFgyxJwBFAQAAAA==.Elizabeth:BAAANQADCggJCAAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Ellithyx:BAAANQAECgQIBgAAAA==.Elmagoprior:BAAANQAECgQIBwAAAA==.Elricky:BAAANQADCgIIBAAAAA==.Eluna:BAAANQAECgYICgAAAA==.Eluric:BAAANQAECgMIAwABNQAECgkJMQAIAO8jAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.',
Er='Ermooke:BAAANQAECgEIAgAAAA==.',
Es='Escanorzão:BAAANQADCgcJDAABNQADCggIHgADAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Executepowa:BAAANQADCggICAAAAA==.Exo:BAABNQAECoEYAAIIAAgK4xzmKgCwAgAIAAgK4xzmKgCwAgAAAA==.Exorciseur:BAABNQAECoEuAAIWAAkKOyMQBQCKAwAWAAkKOyMQBQCKAwAAAA==.',
Fa='Fabercästell:BAAANQAECgcICgAAAA==.Fabers:BAAANQAECgMIAwAAAA==.Fargunn:BAAANQAECgYIEgAAAA==.',
Fe='Feanori:BAABNQAECoEcAAIWAAgKChbdJgAVAgAWAAgKChbdJgAVAgAAAA==.Feanør:BAAANQAECgUIDQAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgcICwADAAAAAA==.Felixus:BAAANQAECggIAwABNQAECggIAwADAAAAAA==.Fennris:BAAANQAECgEIAwAAAA==.Feyrin:BAAANQADCggIHQAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBwABNQAECgEIAQADAAAAAA==.Flodfelblood:BAAANQAECgEIAQAAAA==.',
['Fí']='Fíli:BAAANQAECgEIAQAAAA==.',
['Fï']='Fïrestorm:BAAANQADCgYIBgAAAA==.',
Ga='Gabela:BAAANQAECgIIAwAAAA==.Gabrael:BAAANQABCgQJBAAAAA==.Gaiataur:BAAANQADCgUIBgAAAA==.Galandiel:BAAANQADCggIDgAAAA==.Galinni:BAAANQADCggICgAAAA==.Gallon:BAAANQAECgYIEAAAAA==.Garcs:BAAANQADCgQIBAAAAA==.Garfall:BAAANQAECgYICwAAAA==.',
Gl='Glacyale:BAAANQAECgYIBwAAAA==.Glisa:BAAANQAECgcIDgAAAA==.Glorfindel:BAAANQADCgQIBAAAAA==.',
Gn='Gnomepink:BAAANQADCggIFAAAAA==.',
Go='Godadrian:BAAANQAECgUIEAAAAA==.Gordãobtm:BAAANQAECgYICwAAAA==.Gosu:BAABNQAECoEXAAIVAAgKVBupEgB/AgAVAAgKVBupEgB/AgAAAA==.',
Gr='Gralfor:BAAANQAECgQIBAAAAA==.Grekorio:BAAANQAECgMIBAAAAA==.Greylord:BAAANQAECgIIAgABNQAECggIGAARAC0VAA==.Greylorddrak:BAABNQAECoEYAAIRAAgKLRVIFQAtAgARAAgKLRVIFQAtAgAAAA==.Greylordp:BAAANQAECgEIAQABNQAECggIGAARAC0VAA==.Gromitak:BAAANQADCgIIAgAAAA==.Gronak:BAAANQAECgQJBAAAAA==.',
Gu='Guhtz:BAAANQADCgMIAwAAAA==.Guillyn:BAAANQAECgQIBAAAAA==.Gultai:BAAANQAECgQIBAAAAA==.Gults:BAAANQADCgQIBAAAAA==.Gultsz:BAAANQADCgUIBwAAAA==.Gunpowter:BAAANQABCgIIAwAAAA==.Guxrock:BAAANQAECgIIAwAAAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYJBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hafo:BAAANQADCgYJDQAAAA==.Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQAECgQIBAAAAA==.Hamiister:BAAANQADCgQIBAAAAA==.Hancalimon:BAAANQAECgQIEgAAAA==.Haokö:BAAANQAECgEIAQAAAA==.Hasanzi:BAAANQADCgUIBQAAAA==.Hastterix:BAAANQAECgUIEAAAAA==.Hatezon:BAAANQAECgMIBQAAAA==.',
He='Heavyking:BAAANQAECgYIEAAAAA==.Heishoo:BAAANQADCgIIAgAAAA==.Helitox:BAAANQAECgQIBwAAAA==.Hellhoundish:BAAANQADCgYIBgABNQAECgkJJgAYAC0hAA==.Hellreaper:BAABNQAECoEcAAIbAAcKYQuFgACFAQAbAAcKYQuFgACFAQAAAA==.Heloisaa:BAAANQAECgYIEwAAAA==.Helwen:BAAANQAECgEIAQAAAA==.Heracranosd:BAAANQAECgEIAQAAAA==.Heracranosx:BAAANQAECgUICAAAAA==.Herdy:BAAANQADCgMJBAAAAA==.Herta:BAAANQAECgMIBgAAAA==.Hess:BAAANQAECgQIDQAAAA==.',
Hi='Hireque:BAAANQAFFAEIAQAAAA==.Hitkilled:BAAANQAECgYICgAAAA==.Hitkins:BAAANQADCgYJCQAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgUIEAAAAA==.Holycel:BAAANQAECgIIAgABNQAECgkJGgAEAKAeAA==.Holyscrim:BAAANQADCgcICQAAAA==.Hoolylight:BAAANQAECgEIAQAAAA==.',
Hu='Huelandita:BAAANQAECgIIAgAAAA==.Hunterpica:BAABNQAECoEYAAIIAAgKPx1ILwCfAgAIAAgKPx1ILwCfAgAAAA==.Huntmon:BAAANQAECgYIEQAAAA==.Huriah:BAAANQAECgIIAgAAAA==.Huskat:BAAANQAECgYIDAAAAA==.',
Hy='Hysillens:BAAANQAECgQIBgAAAA==.',
['Hã']='Hãn:BAAANQADCgEIAQAAAA==.',
['Hä']='Härü:BAAANQADCgUIAwAAAA==.',
Ig='Igno:BAAANQAECgUICgABNQAECgkJLQAKAGIlAA==.',
Il='Ilane:BAAANQABCggIDAAAAA==.Illidatrix:BAAANQAECgYIEQAAAA==.Illïndão:BAAANQADCggICAAAAA==.Ilovealtgirl:BAAANQADCggJFAAAAA==.',
In='Inladris:BAAANQADCgcIBwAAAA==.Inot:BAAANQAECgYIDgAAAA==.',
Ir='Irmãsafada:BAAANQADCgEIAQAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQAECgUICgAAAA==.',
It='Italodpz:BAAANQAECgUIBQABNQAECgcIEAADAAAAAA==.Itsälasca:BAAANQADCgUICwAAAA==.',
Iu='Iuri:BAAANQAECgYIBwAAAA==.',
Ix='Ixlzvaxtylxl:BAAANQADCgYIBgAAAA==.',
Iz='Izanna:BAAANQADCgcJCwAAAA==.',
Ja='Jalinrabeidh:BAAANQAECgEIAQAAAA==.Jampack:BAABNQAECoEgAAMQAAkKZiKsDQAvAwAQAAkKZiKsDQAvAwAKAAEKugk0+gA0AAAAAA==.',
Je='Jeevas:BAAANQAECgYIEwAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeguinha:BAAANQABCggIDgAAAA==.Jeu:BAAANQADCgcICQAAAA==.Jeyla:BAAANQADCgEIAQAAAA==.',
Jh='Jhasperr:BAAANQADCggIGgAAAA==.',
Jo='Jocabiroca:BAABNQAECoEgAAMCAAgKXBpSagB4AgACAAgKXBpSagB4AgAOAAEKlwIRCwAvAAAAAA==.Johnez:BAAANQADCgcIBwAAAA==.Joral:BAAANQABCggICAAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAABNQAECoEYAAIcAAgKLBC7IgD1AQAcAAgKLBC7IgD1AQAAAA==.',
Jr='Jrxamã:BAAANQAECgQIDwAAAA==.',
Ju='Juliia:BAAANQAECgMJBgAAAA==.Jusgu:BAAANQAECgYICQAAAA==.',
['Jö']='Jönah:BAAANQADCgMIAwAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaiev:BAAANQADCgYICgAAAA==.Kaju:BAABNQAECoEWAAILAAkK7x+WAgAGAwALAAkK7x+WAgAGAwAAAA==.Kalinis:BAAANQAECgEJAQAAAA==.Kalliiope:BAABNQAECoEXAAMLAAUKHwmpHADHAAACAAUKpAJ3PwHVAAALAAQK7QqpHADHAAAAAA==.Kamesenin:BAAANQADCgUIBQAAAA==.Kamïlla:BAAANQAECgQICwAAAA==.Karak:BAAANQADCgIJAgAAAA==.Karamatsu:BAAANQAECgIIAgAAAA==.Karollus:BAAANQABCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCggIDAAAAA==.Katona:BAAANQAECgcIDQAAAA==.Kauss:BAAANQADCggJCAAAAA==.',
Kd='Kdposa:BAAANQABCgQIBAAAAA==.',
Ke='Keior:BAAANQAECgEIAQAAAA==.Kenai:BAAANQAECgcIEQAAAA==.Kewenz:BAABNQAECoEpAAIIAAkK2SYYAAAWBAAIAAkK2SYYAAAWBAABNQAECgkJKwAIALolAA==.Keylaa:BAAANQAECgUICgAAAA==.',
Kh='Khasin:BAAANQAECgYIDgAAAA==.',
Ki='Kierke:BAAANQAECgQIBAAAAA==.Kindz:BAAANQADCgUIBgABNQAECgkJKwAIALolAA==.Kiregeth:BAAANQAECgUICgAAAA==.Kitrel:BAAANQAECgMIAwAAAA==.',
Kl='Kleiio:BAAANQAECgEIAQAAAA==.Kllauzz:BAAANQAECgQICgABNQAECgcIGAAMABIMAA==.Kllauzzmage:BAAANQAECgIIAgABNQAECgcIGAAMABIMAA==.Kllauzzpalla:BAABNQAECoEYAAIMAAcKEgy8pgBiAQAMAAcKEgy8pgBiAQAAAA==.',
Kn='Knufolgado:BAAANQADCgYIBgAAAA==.',
Ko='Kolyn:BAABNQAECoExAAIIAAkK7yPlBwCCAwAIAAkK7yPlBwCCAwAAAA==.Komamurasou:BAAANQAECgQIBAAAAA==.',
Kr='Krastian:BAAANQAECgQIDQAAAA==.Kreegh:BAAANQAECgEIAQAAAA==.Krikixus:BAAANQADCgYIBgAAAA==.Krupper:BAAANQAECgMIAwABNQAECgYIDAADAAAAAA==.Krynesa:BAAANQADCggICwAAAA==.',
Ku='Kuhaku:BAAANQADCgQIBAAAAA==.Kukuatzo:BAAANQAECgQICAAAAA==.',
Ky='Kyary:BAAANQAECgQIBAABNQAECggIIgAXABocAA==.Kyndin:BAAANQADCgEIAQABNQAECgkJKwAIALolAA==.',
['Kä']='Kälini:BAAANQADCgcIDAABNQAECgQIBAADAAAAAA==.Käyros:BAAANQADCgUJCgAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAAANQAECgYIDgAAAA==.Köri:BAABNQAECoEcAAMCAAkKZR7ENwD7AgACAAkKEx7ENwD7AgALAAEKMx1bLwBOAAAAAA==.',
La='Lakaioo:BAAANQAECgYIEwAAAA==.Lamont:BAAANQAECgUIEgAAAA==.Lampiião:BAABNQAECoEeAAIIAAcKfBfQWAAXAgAIAAcKfBfQWAAXAgAAAA==.Lanllaniel:BAAANQAECgUIBwAAAA==.Largartixa:BAAANQADCgQJBAABNQAECgQJBAADAAAAAA==.Larslion:BAAANQABCgYJBgAAAA==.',
Le='Lebelisco:BAAANQAECgcIEAAAAA==.Leehyori:BAAANQAECgMIBQAAAA==.Legëndaria:BAAANQAECgEIAQAAAA==.Lennorien:BAABNQAECoEaAAIdAAcKYRc4DgAEAgAdAAcKYRc4DgAEAgAAAA==.Lestard:BAAANQABCgUIBwAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Lifestrream:BAABNQAECoEWAAMeAAgKeg33GQBPAQAeAAgKoAn3GQBPAQAUAAUK0gzZFgAYAQABNQAECgkJHwAeAN8XAA==.Liftshertail:BAABNQAECoEnAAQRAAgKuB3ICwDDAgARAAgKuB3ICwDDAgAfAAUKBxF5HwAZAQASAAIKxQwqGABgAAAAAA==.Ligiaf:BAAANQAECgQIBwAAAA==.Liilum:BAAANQADCgcIBwAAAA==.Limeware:BAAANQADCgYIBgAAAA==.Linë:BAAANQADCggJHwABNQAECgQIBAADAAAAAA==.Linëa:BAAANQADCgIJBQAAAA==.Linüss:BAAANQAECgEIAQAAAA==.Lionarot:BAAANQAECgQIDAAAAA==.Littleshelby:BAAANQADCgYJDwAAAA==.',
Lo='Lobinox:BAAANQADCggICgAAAA==.Lolzhe:BAAANQAECgYIBgAAAA==.Longaim:BAAANQAECgcIEwAAAA==.Lorthaeron:BAAANQAECgYIEwAAAA==.Losdor:BAAANQAECgUIBQAAAA==.Lostminder:BAAANQAECgMIAwAAAA==.Lothbrok:BAAANQAECggIEAAAAA==.',
Lu='Lucanor:BAAANQADCgUIBQAAAA==.Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAACNQAFFIEQAAIYAAUK/BifCQCwAQAYAAUK/BifCQCwAQA1AAQKgSIAAxgACQqTIrUdACADABgACQr4IbUdACADABcAAQrQIeQhAFYAAAAA.Lukanelas:BAAANQADCgcJDQAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luminosos:BAAANQAECgEIAQABNQAECggIAwADAAAAAA==.Luna:BAAANQAFFAEIAQAAAA==.Lunes:BAABNQAECoEfAAIQAAgK1hpgIgCmAgAQAAgK1hpgIgCmAgAAAA==.Luster:BAAANQADCgcIBwAAAA==.Lusther:BAAANQAECgUIBgAAAA==.Luzdacelesc:BAABNQAECoE1AAMBAAkKXiZRAAD3AwABAAkKXiZRAAD3AwATAAIKeA0WsQCGAAAAAA==.',
Ly='Lyaah:BAAANQADCggIEQAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYICwAAAA==.',
['Lø']='Lølzhê:BAABNQAECoEmAAIgAAcKjxxUEgAFAgAgAAcKjxxUEgAFAgAAAA==.Løvizinha:BAAANQAECgQIBQAAAA==.',
['Lú']='Lúaprata:BAAANQADCggIFQAAAA==.',
Ma='Maagnuss:BAAANQADCgIIAgAAAA==.Madbuddha:BAAANQADCgQJBAAAAA==.Mageli:BAAANQAECgYIBwAAAA==.Magodanilo:BAAANQAECgIIAgAAAA==.Magodavida:BAAANQAECgQIDgAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maguinax:BAAANQAECgEIAgAAAA==.Maheena:BAAANQAECgcIDAAAAA==.Mai:BAAANQAECgUJDwAAAA==.Mairon:BAAANQADCgcICQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAAANQAECgYIEwAAAA==.Malborion:BAAANQAECgUICwAAAA==.Malevolent:BAAANQAECgUIBQAAAA==.Malignõ:BAABNQAECoEtAAIKAAkKYiXAAwDEAwAKAAkKYiXAAwDEAwAAAA==.Maltozo:BAAANQAECgYIEwAAAA==.Mandrakson:BAABNQAECoEbAAIJAAgKzwywMgCqAQAJAAgKzwywMgCqAQAAAA==.Mandubim:BAAANQADCgEIAQAAAA==.Mariiamil:BAAANQAECgUIBgAAAA==.Marvelos:BAAANQABCggJCgAAAA==.Marvvila:BAAANQAFFAEIAQAAAA==.Marycristiny:BAAANQAECggIEgAAAA==.Mauwolf:BAAANQAECgQIBQAAAA==.Mazaky:BAAANQAECgYIDgAAAA==.',
Me='Medivi:BAAANQADCgMIAwAAAA==.Megumi:BAAANQAECgMIAwAAAA==.Memphis:BAAANQADCgcIBwAAAA==.Menorxidil:BAABNQAECoEiAAIgAAkKLxqxCgCnAgAgAAkKLxqxCgCnAgAAAA==.Mestredoido:BAAANQAECgEIAQAAAA==.Mestreløck:BAAANQADCgMIBwAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.',
Mh='Mhenb:BAAANQAECgcIDAAAAA==.Mhorgothh:BAAANQADCgQIBAAAAA==.',
Mi='Micherouc:BAAANQADCggIDgAAAA==.Midnights:BAAANQADCgUIBQAAAA==.Mikal:BAAANQAECgUICgAAAA==.Minort:BAAANQAECgQIBwAAAA==.Minör:BAAANQAECgQIBwAAAA==.Missmarvel:BAAANQABCgYICgAAAA==.Mithrael:BAAANQADCgUIBQAAAA==.Mizukagesou:BAAANQAECgQICAAAAA==.',
Mo='Monkbest:BAAANQADCggIEQAAAA==.Montej:BAAANQAECgEIAQAAAA==.Montäna:BAAANQABCgMIAwAAAA==.Mooncap:BAAANQAECgYIDgAAAA==.Moondragoon:BAAANQADCgcICQAAAA==.Morakhir:BAAANQADCgQIBAAAAA==.Moranguinhö:BAAANQADCgEJAQAAAA==.Mordiidinha:BAAANQAECgQJBwABNQAECgkJLQAKAGIlAA==.Morganviolet:BAAANQAECgUIDQAAAA==.',
Mu='Mugidinhaa:BAAANQABCgcIBQAAAA==.Murdoky:BAAANQADCgEIAQABNQAECgMIBAADAAAAAA==.Musleira:BAAANQAECgQICQAAAA==.',
My='Myrzin:BAAANQADCggIDAAAAA==.Mythariel:BAAANQAECgQIBQAAAA==.Mythcut:BAAANQAECgQIDAAAAA==.Mythjegue:BAAANQADCggIDgAAAA==.',
['Mä']='Mällü:BAAANQAECgUJCQAAAA==.Mälthazar:BAABNQAECoEZAAINAAgK7x6rCgCxAgANAAgK7x6rCgCxAgAAAA==.Määt:BAAANQADCggICAABNQAFFAUIDwAdAMcTAA==.',
['Må']='Mågus:BAAANQAECgYIEgAAAA==.',
['Mò']='Mòrgan:BAAANQADCgYICwAAAA==.',
['Mø']='Mørgåna:BAAANQAECgUIDgAAAA==.',
Na='Naamt:BAAANQADCgYIBgAAAA==.Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQADCgYICgABNQAECgMIAwADAAAAAA==.Nagashina:BAAANQADCggIFgAAAA==.Naizow:BAAANQAECgUICQAAAA==.Namisan:BAAANQAECgIIAgAAAA==.Namuhß:BAAANQAECgQICgABNQAECgYICwADAAAAAA==.Namøøh:BAAANQAECgYICwAAAA==.Naomiy:BAAANQADCgYIEAAAAA==.Naoto:BAAANQAECgQIDQAAAA==.Napru:BAAANQADCgEIAQAAAA==.Nardalan:BAAANQADCgQJBAABNQAECgUICgADAAAAAA==.Narjes:BAAANQAECgYICAAAAA==.Nathrezim:BAAANQADCgcIEAAAAA==.',
Ne='Necrogélido:BAAANQADCgYIEQAAAA==.Nefariio:BAAANQADCgQIBAAAAA==.Neninhaa:BAAANQADCgcJBQAAAA==.Neopaladino:BAAANQAECgMIBgAAAA==.Nerlock:BAAANQAECgQIBwAAAA==.',
Ni='Nicom:BAAANQADCgYIBgAAAA==.Nightforms:BAAANQADCggIEAAAAA==.Nikity:BAABNQAECoEdAAIWAAgKahppHABwAgAWAAgKahppHABwAgAAAA==.',
No='Noahwallker:BAAANQADCgYIBgAAAA==.Noazard:BAAANQAECgMIBAAAAA==.Nopainnogain:BAAANQAECgEIAQAAAA==.Normalin:BAAANQADCgEIAQAAAA==.Nortênho:BAABNQAECoEcAAIPAAgKox8JGADbAgAPAAgKox8JGADbAgAAAA==.Nosferüs:BAAANQAECgQIBwAAAA==.Nossilat:BAABNQAECoElAAIWAAgKyiWyBwBbAwAWAAgKyiWyBwBbAwAAAA==.',
Nu='Nuit:BAAANQAECgIIBwAAAA==.Nunhöly:BAAANQAECgYICgAAAA==.',
Ny='Nysthiael:BAABNQAECoEfAAMbAAgK9hMzUAAbAgAbAAgK9hMzUAAbAgAhAAEKuwVTKgAsAAAAAA==.Nyxicel:BAAANQAECgUICQABNQAECgkJGgAEAKAeAA==.',
['Nä']='Närem:BAAANQAECggIAQAAAA==.Nästÿ:BAAANQADCgYIBwAAAA==.',
['Nö']='Nöturnö:BAAANQABCgYICgAAAA==.',
['Ný']='Nýmm:BAAANQAECgUIEAAAAA==.',
Oc='Ocon:BAAANQABCgIIAgAAAA==.',
Od='Odigo:BAAANQADCgIIAgAAAA==.Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCggIIAAAAA==.',
Ol='Oldcook:BAAANQABCgYIBQAAAA==.Oliele:BAAANQAECgQICAAAAA==.',
On='Onixpala:BAAANQAECgQIBAABNQAECgUICQADAAAAAA==.Onlydruix:BAAANQADCgIIAgAAAA==.',
Op='Opsdesculpa:BAABNQAECoEVAAMiAAYKEBdMLgC3AQAiAAYKEBdMLgC3AQAjAAEKEBG0QwBBAAAAAA==.',
Or='Organ:BAAANQAECgQIBQAAAA==.Orinoldo:BAABNQAECoEhAAICAAkKvh6vLQAYAwACAAkKvh6vLQAYAwAAAA==.',
Os='Osiria:BAAANQABCgYICAAAAA==.',
Ot='Otacki:BAAANQADCgIIAgAAAA==.Otherside:BAAANQAECgMIBQABNQAECgkJLgAdANAZAA==.Otávio:BAAANQAECgMIAwAAAA==.',
Ow='Owlcapøne:BAAANQADCggIEAAAAA==.',
Ox='Oxentedragon:BAAANQADCgUIBAAAAA==.',
Oz='Ozyi:BAAANQAECgUIDQAAAA==.',
Pa='Pachiinko:BAAANQAECgYJAgAAAA==.Pain:BAAANQADCgQIBAAAAA==.Painkke:BAAANQAECgcIDAAAAA==.Palluz:BAAANQAECgMIAwABNQAECgkJKAAcAFUfAA==.Palyz:BAAANQADCggICAAAAA==.Pandaphorte:BAAANQADCgIIAgABNQAECgIIBAADAAAAAA==.Panicdeath:BAAANQAECgEIAQAAAA==.Parafinaisis:BAAANQAECgQICgAAAA==.Parafinared:BAAANQADCgcIFwAAAA==.Parrot:BAAANQADCgEIAQAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.',
Pe='Pedrosolock:BAAANQADCgYIBgAAAA==.Peltrow:BAAANQAFFAEIAQAAAA==.Penndrive:BAAANQADCgQIBQAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgUICgADAAAAAA==.Pesaa:BAABNQAECoEaAAIYAAgKSx/pLgDTAgAYAAgKSx/pLgDTAgAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Phesti:BAAANQABCgEIAQAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Picklerick:BAAANQAECgIIAQAAAA==.Pirizin:BAABNQAECoEoAAIMAAkKtxo2PwCOAgAMAAkKtxo2PwCOAgAAAA==.',
Po='Popopeka:BAAANQADCgcIBwAAAA==.Porcaleta:BAAANQAECgUIEQAAAA==.Portal:BAAANQAECgUJCgAAAA==.Portelamage:BAABNQAECoEmAAICAAkK4B+cLwASAwACAAkK4B+cLwASAwAAAA==.Portheus:BAAANQADCggIFwAAAA==.',
Pr='Praeglacius:BAABNQAECoEgAAMKAAgKjhCGSQABAgAKAAgKjhCGSQABAgAQAAIK/ABg7AAzAAAAAA==.Pravuls:BAAANQADCgYIBwAAAA==.Priapista:BAAANQAECgEIAQAAAA==.Priyla:BAAANQABCgcICgAAAA==.Prosaic:BAAANQADCggICAABNQADCggJDwADAAAAAA==.Pråhå:BAAANQAECgQICQABNQAECgYICwADAAAAAA==.',
Ps='Psicopanda:BAAANQAECgYIDAAAAA==.Psychiclink:BAAANQAECggICQABNQAECgkJNQABAF4mAA==.',
Pu='Puffys:BAAANQAECgEIAQABNQAECgUIBQADAAAAAA==.',
Pw='Pwcca:BAAANQAECgEJAQAAAA==.',
['Pó']='Pórthosrox:BAAANQAECgEIAgAAAA==.',
['Pú']='Púh:BAAANQADCgQIBAABNQAECggIIgAGAA0fAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAABNQAECoEdAAIXAAgKKx7DAwDEAgAXAAgKKx7DAwDEAgAAAA==.Raewyn:BAABNQAECoEYAAIJAAgKaR1nFQCdAgAJAAgKaR1nFQCdAgAAAA==.Rafaelgame:BAAANQAECgQICAAAAA==.Ragdead:BAACNQAFFIEHAAIkAAIKoA0XGQB4AAAkAAIKoA0XGQB4AAA1AAQKgR0AAiQACQoCG18eAIkCACQACQoCG18eAIkCAAAA.Ragdöll:BAAANQADCgcJCQAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAFFAIIBwAkAKANAA==.Ragosan:BAAANQADCgEIAQABNQAFFAIIBwAkAKANAA==.Rairone:BAAANQAECgcIDwAAAA==.Raparigaloka:BAAANQAECgUIDQAAAA==.Rapunxel:BAABNQAECoEuAAMdAAkK0BmDAwDwAgAdAAkK0BmDAwDwAgAbAAUKZAgEsgAHAQAAAA==.Rarkion:BAAANQAECgcIEQAAAA==.Raulthalas:BAAANQADCgYIBgAAAA==.Rawrii:BAAANQADCgUIBQAAAA==.Raynmake:BAAANQAECgEIAQABNQAECgcIBwADAAAAAA==.',
Rb='Rbchama:BAAANQAECgQIEAAAAA==.',
Re='Redvil:BAAANQADCgUJBwAAAA==.Revoltedhunt:BAAANQAECggICgABNQAFFAcIFAAcAJYRAA==.Revolthed:BAACNQAFFIEUAAMcAAcKlhFIBADhAQAcAAYKbhRIBADhAQAIAAQKuAaADAAJAQA1AAQKgScAAxwACQpaIg4KABUDABwACQrsIQ4KABUDAAgABQqVGiCDAKQBAAAA.',
Rh='Rhaadora:BAAANQAECgQIBAAAAA==.Rhoghar:BAAANQAECggIEwAAAA==.Rhoghardruid:BAAANQAECgMIAwABNQAECggIEwADAAAAAA==.',
Ri='Riachu:BAAANQADCgcIBwAAAA==.Riluyu:BAAANQADCggICgAAAA==.Rimetail:BAAANQABCgQIBAAAAA==.',
Ro='Rokalf:BAABNQAECoEWAAIaAAgKvA4JEwCYAQAaAAgKvA4JEwCYAQAAAA==.Rossiten:BAAANQAECgUIEAAAAA==.Roöf:BAAANQAECgUIEQAAAA==.',
Ru='Rubya:BAAANQAECgEJAQABNQAECgcICgADAAAAAA==.Runavento:BAAANQADCgIIAgAAAA==.Ruélatórta:BAAANQAECgQICAAAAA==.',
['Rä']='Räidela:BAABNQAECoEiAAMbAAgK5B35KACqAgAbAAgK5B35KACqAgAdAAEK2hITaQA7AAAAAA==.',
Sa='Sagman:BAAANQABCgIIAgAAAA==.Sagädegemeos:BAAANQAECgQIEAABNQAECggIFAAIANEcAA==.Salasär:BAABNQAECoEZAAIYAAcKIRpKbQD9AQAYAAcKIRpKbQD9AQABNQAECgcIGQAIAMceAA==.Saleyi:BAAANQAECgQIBgAAAA==.Saluton:BAAANQAECgEIAgAAAA==.Samidemon:BAAANQAECgQIBAAAAA==.Sarashi:BAAANQADCgUJDAAAAA==.Sarte:BAAANQAECgEIAgAAAA==.Sarzlok:BAAANQAECgQIBQAAAA==.',
Sc='Schiabelle:BAAANQADCgYIDAAAAA==.Schiabellee:BAAANQADCggJEQAAAA==.Scoobydruida:BAAANQAECgYIEQAAAA==.Screan:BAABNQAECoEZAAIBAAgKSxA8HwD1AQABAAgKSxA8HwD1AQAAAA==.Scrøøge:BAAANQAECgQICgAAAA==.',
Se='Sealgaire:BAAANQADCgIIAgAAAA==.Seelyvorey:BAABNQAECoEgAAQJAAgKPCKkDgDmAgAJAAgKPCKkDgDmAgAkAAUKFxZ1WgBBAQAEAAMKARc1gACxAAAAAA==.Selph:BAAANQAECgcICgABNQAECgcICwADAAAAAA==.Sengos:BAAANQAECgQIBQAAAA==.Sephhiroth:BAAANQADCgcICgAAAA==.Serrase:BAABNQAECoEbAAICAAgKPRSLhgA0AgACAAgKPRSLhgA0AgAAAA==.',
Sh='Shagy:BAAANQADCggICAAAAA==.Shalivane:BAAANQAECggIBwAAAA==.Shalquoir:BAAANQAECgcICAABNQAECggIJwARALgdAA==.Sharckaron:BAAANQAECgQIBwAAAA==.Shedleass:BAAANQAECgYIEAAAAA==.Shendalar:BAABNQAECoEjAAMCAAgK1hG9iQAtAgACAAgK1hG9iQAtAgAOAAMKRQT7BgCAAAAAAA==.Shigami:BAAANQADCgcJBwAAAA==.Shigare:BAAANQAECgEIAQAAAA==.Shuräto:BAAANQADCgYICQAAAA==.Shywa:BAAANQADCgQIBgAAAA==.Shîvas:BAAANQAECgYICQAAAA==.Shøtinha:BAABNQAECoEbAAMcAAgKMRtkIAAMAgAcAAcK3BhkIAAMAgAIAAMKLxzZ0gDwAAAAAA==.Shøwtime:BAAANQAECgEIAQABNQAECgYIEAADAAAAAA==.',
Si='Sianus:BAAANQAECgIJBAAAAA==.Sicarious:BAAANQADCgYICwAAAA==.Sicariuz:BAABNQAECoEZAAIMAAcKwRQQgwC8AQAMAAcKwRQQgwC8AQAAAA==.Silara:BAAANQADCgYICQAAAA==.Silves:BAAANQABCgYICgAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sl='Slickdaddy:BAAANQADCgQIBAABNQAECgkJHQAGAPwdAA==.',
Sm='Smarcão:BAAANQADCgMIAwAAAA==.',
Sn='Snipinho:BAAANQAECgcIEQAAAA==.Snowtail:BAAANQAECgQICQAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Sokun:BAAANQAECgEIAQAAAA==.Solaryel:BAAANQAECgcIDQAAAA==.Solidheals:BAAANQAECgIIBgAAAA==.Sougigante:BAAANQAECgMICAAAAA==.Souillé:BAAANQADCgYIBgABNQAECgkJLgAWADsjAA==.Soulbinder:BAAANQADCgIJAgAAAA==.Soupombagira:BAAANQAECgMIAwAAAA==.',
Sp='Spellshadown:BAABNQAECoEfAAIbAAkK2RXfMACLAgAbAAkK2RXfMACLAgAAAA==.Spellshamy:BAAANQADCggICAAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQAECgMIAwAAAA==.',
St='Stalinbrs:BAAANQAECgEIAQABNQAECgcIEAADAAAAAA==.Stalindinho:BAAANQAECgcICQAAAA==.Stelluna:BAAANQAECgMIAwAAAA==.Stormimrage:BAAANQAECgEIAgAAAA==.Strexx:BAAANQAECgQICQAAAA==.Stronoffgard:BAABNQAECoEYAAIYAAgKXx3SPgCVAgAYAAgKXx3SPgCVAgAAAA==.Stronq:BAAANQADCgYIDgAAAA==.',
Su='Sulfur:BAAANQAECgIIBAAAAA==.',
['Sà']='Sàgadegemeos:BAABNQAECoEUAAMIAAgK0RxeQABhAgAIAAcKtB1eQABhAgAcAAEKlhbzYgBIAAAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIBAABNQAECggIGQAbABkaAA==.',
Ta='Tacka:BAAANQADCggJHgAAAA==.Tafoki:BAABNQAECoEiAAMGAAgKDR87CADJAgAGAAgKdB07CADJAgAKAAIKQBrzxQCkAAAAAA==.Tanakin:BAAANQAECgMIAQABNQAECggIIgAXABocAA==.Tangdebanana:BAAANQAECgQIBAABNQAECgYIEwADAAAAAA==.Tankairotty:BAAANQAECgEIAgAAAA==.Tanrity:BAAANQAECgcICgAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAAANQAECgQIBwAAAA==.',
Te='Temeloorego:BAAANQAECgMIAwAAAA==.Temkutemmedo:BAAANQAECgIIBQABNQADCggIHgADAAAAAA==.Tennkkar:BAAANQAECgEIAQAAAA==.Texugojogatv:BAAANQAECgUICwAAAA==.Texugosa:BAAANQAECgEJAQAAAA==.',
Th='Thamihime:BAABNQAECoEaAAIIAAcK7hHXcwDMAQAIAAcK7hHXcwDMAQAAAA==.Tharizdum:BAAANQAECgQICgAAAA==.Thlrall:BAAANQAECgEIAgABNQAECgEIBgADAAAAAA==.Thontonas:BAAANQADCgIIAgAAAA==.Thornus:BAACNQAFFIEFAAIXAAMKohnHAAAnAQAXAAMKohnHAAAnAQA1AAQKgRkAAhcACAqCIYcDANICABcACAqCIYcDANICAAAA.Thorudos:BAAANQADCgQIAgAAAA==.Thrandu:BAAANQADCgYIBgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.Thunderburp:BAAANQAECgUIBQABNQAECggIBgADAAAAAA==.Thuzalduum:BAAANQADCgIIAgAAAA==.',
To='Toni:BAAANQAECgUICgAAAA==.Toshyo:BAAANQAECgcIBwAAAA==.Tostão:BAAANQADCgQIBgAAAA==.Touchhme:BAAANQAECgIIAgAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQADAAAAAA==.Toykiller:BAAANQADCgQIBAAAAA==.',
Tp='Tprdmage:BAAANQAECgQICAAAAA==.Tprdtank:BAAANQABCgQIBAAAAA==.',
Tr='Trighit:BAAANQADCgYICQAAAA==.Trolhöl:BAAANQAECgcJEwAAAA==.Trollrogue:BAAANQAECgUIEQAAAA==.Trosobado:BAAANQADCgEIAQAAAA==.Troyana:BAAANQADCggICAABNQAFFAUIDwAYAAcbAA==.',
Tu='Tukiel:BAAANQAECgUICAAAAA==.Tunkav:BAAANQABCgYJCQAAAA==.Tuska:BAAANQADCgUIBAAAAA==.',
Ty='Tyde:BAAANQAECgUIDAABNQAECgcIFgARAOYRAA==.Typol:BAAANQAECgUIEQAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAAANQAECgYIEgAAAA==.',
['Tø']='Tøtemhubby:BAAANQAECgEIAQABNQAECggIAwADAAAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQADAAAAAA==.Umehara:BAACNQAFFIEFAAIcAAMKERUlDwDnAAAcAAMKERUlDwDnAAA1AAQKgSsAAhwACQopIaYFAGIDABwACQopIaYFAGIDAAAA.Umokh:BAABNQAECoEiAAIXAAgKGhxaBACkAgAXAAgKGhxaBACkAgAAAA==.',
Un='Unbrøken:BAAANQAECgEIAgAAAA==.Unclearnaldo:BAAANQADCgYIBgABNQAECgYIDAADAAAAAA==.',
Uo='Uolokoelfo:BAABNQAECoErAAIYAAgKviBPLgDVAgAYAAgKviBPLgDVAgAAAA==.',
Ur='Urannia:BAABNQAECoEkAAIIAAcKsxWAXgAHAgAIAAcKsxWAXgAHAgAAAA==.Urgath:BAAANQAECgUIDAAAAA==.',
Ut='Uther:BAAANQAECgQICQAAAA==.',
Va='Valan:BAAANQAECgEIAgAAAA==.Valdeco:BAAANQADCggIDAAAAA==.Valdevino:BAAANQAECgcIDQAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAAANQAECgYIEwAAAA==.Venonpoison:BAAANQADCgMIAgAAAA==.Vermeryn:BAAANQAECgMIBAAAAA==.Vermithór:BAAANQAECgIIBAAAAA==.',
Vi='Viciadø:BAAANQADCggICAABNQAECgkJJAAcACggAA==.Villalobos:BAAANQAECgMIBgAAAA==.Vits:BAAANQAECgUIEAAAAA==.',
Vo='Voidsurge:BAAANQAECgQIBQAAAA==.Voidwar:BAAANQAECgIIAgABNQAECgQIBQADAAAAAA==.Vollin:BAAANQAECgcIDAAAAA==.Volrun:BAAANQADCggIDAAAAA==.Voragem:BAAANQAECgYIDQAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.',
Wa='Warlockdoido:BAAANQAECgQIBQAAAA==.Warlôka:BAAANQADCgUIBQAAAA==.',
Wi='Wiillord:BAAANQAECgQIBgAAAA==.Willbm:BAABNQAECoElAAMMAAgKcQ0ehAC5AQAMAAgKtAwehAC5AQANAAUKxQwLNgDdAAAAAA==.Winnettou:BAAANQAECgYIDgAAAA==.Wipalogo:BAAANQADCggIHgAAAA==.Wise:BAABNQAECoEeAAIMAAgKMCDONwCrAgAMAAgKMCDONwCrAgAAAA==.',
Wm='Wmana:BAAANQAECgQIDQAAAA==.',
Wr='Wrathi:BAAANQAECgIIAgAAAA==.',
Wu='Wuan:BAABNQAECoEXAAMVAAgKAB3pHAD3AQAVAAcKCBzpHAD3AQAgAAQK2wzHKQDNAAAAAA==.',
Xa='Xamanico:BAAANQAECgQIBwAAAA==.Xanasmanas:BAAANQAECgcIEgAAAA==.Xazon:BAAANQADCgUIBwAAAA==.',
Xh='Xharlios:BAAANQAECgEIAQAAAA==.',
Xi='Xingorila:BAAANQADCgQIBAAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQAECgUICAAAAA==.',
Xy='Xymor:BAACNQAFFIEJAAIfAAQKDA0yBQAsAQAfAAQKDA0yBQAsAQA1AAQKgSIAAh8ACQpWIFUGAAEDAB8ACQpWIFUGAAEDAAE1AAQKBAgEAAMAAAAA.Xyuwan:BAAANQADCgUIBQAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Ye='Yenniferxd:BAAANQABCgUIBQAAAA==.',
Yl='Ylanna:BAABNQAECoEXAAMlAAcKnhSJCACmAQAlAAYK4xaJCACmAQABAAIK0wV1UgBkAAAAAA==.',
Yn='Ynit:BAAANQADCgUIBQAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoodoo:BAAANQABCgUJBQAAAA==.Yoriko:BAAANQAECgQIBAAAAA==.Yorú:BAAANQAECgYIEQAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQAECgEIAQAAAA==.',
Za='Zamii:BAAANQAECgQIBAAAAA==.Zarik:BAAANQADCgcIBwAAAA==.',
Ze='Zenolis:BAAANQADCgcJFAAAAA==.Zerathir:BAAANQAECgQIBQAAAA==.',
Zh='Zhalazar:BAAANQAECgQICwAAAA==.Zhenb:BAAANQADCgEIAQAAAA==.',
Zi='Zigosmar:BAAANQAECgEJAQAAAA==.',
Zo='Zolet:BAAANQAECgMIBAAAAA==.Zones:BAAANQAECgQIBQABNQAECgYIEgADAAAAAA==.',
Zu='Zumbix:BAAANQADCgcIBwAAAA==.',
['Ág']='Ágripa:BAAANQABCgYIBgAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Än']='Ängron:BAAANQAECgQICAAAAA==.Änä:BAAANQADCggIDgAAAA==.',
['Är']='Ärthås:BAAANQAECgQIBAAAAA==.',
['Äz']='Äzra:BAAANQAECgEIAgAAAA==.',
['Ær']='Ærikão:BAAANQAECgYIDwAAAA==.',
['Æt']='Ætherfel:BAAANQAECgIIAgAAAA==.',
['Ét']='Étel:BAAANQAECgEIAQAAAA==.',
['Ðr']='Ðrakko:BAAANQADCgQICAAAAA==.',
['Ök']='Ökamì:BAAANQADCgIIAgAAAA==.',
['Ör']='Örigem:BAAANQAECgQIBwAAAA==.',
['ßl']='ßlåkehunter:BAAANQAECgEIAQAAAA==.',
['ßr']='ßradvi:BAAANQADCggIDAAAAA==.ßrutalßarbie:BAAANQADCgYIBgAAAA==.',
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
