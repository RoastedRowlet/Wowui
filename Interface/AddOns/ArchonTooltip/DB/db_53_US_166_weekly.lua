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

local lookup = {'Priest-Shadow','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Holy','Hunter-BeastMastery','Shaman-Elemental','Mage-Frost','Paladin-Retribution','Mage-Fire','Druid-Balance','Shaman-Restoration','Priest-Holy','Druid-Restoration','Druid-Feral','Monk-Windwalker','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Mage-Arcane','Paladin-Protection','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost',}
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abyssdk:BAAANQAECgEJAQABNQAECgkJLQABACEmAA==.Abyssfurry:BAAANQADCggJCAABNQAECgkJLQABACEmAA==.',
Ac='Acadêmica:BAAANQAECgQICAAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adcosmos:BAAANQADCggJCgABNQAECgUICgACAAAAAA==.Adebaio:BAABNQAECoEjAAIDAAkK8yJ6BQCLAwADAAkK8yJ6BQCLAwAAAA==.',
Ae='Aeghlise:BAAANQADCgcIBwAAAA==.Aegislashh:BAAANQAECgUICgAAAA==.Aerlath:BAACNQAFFIEEAAIEAAIKXheiCACxAAAEAAIKXheiCACxAAA1AAQKgSAAAgQACQpDI+kDAIYDAAQACQpDI+kDAIYDAAAA.Aetulia:BAAANQAECgYJCwAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQADCggIFgACAAAAAA==.',
Ag='Aggroster:BAAANQAECgIIAgAAAA==.Agnestesia:BAAANQAECgQIBwAAAA==.',
Ah='Ahrathor:BAAANQAECgQJBgAAAA==.',
Ak='Akasta:BAAANQAECgYJEQAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.Akâme:BAAANQADCgYIBgABNQAECgkJGwAFAFEYAA==.',
Al='Alascayoung:BAAANQADCggIEAAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Aldrathion:BAAANQAECgEIAQABNQAECgkJKQAGACwjAA==.Aledk:BAAANQADCgYJEAAAAA==.Alessan:BAAANQADCgYJCgAAAA==.Alessary:BAAANQADCgYIBwAAAA==.Alfurieb:BAAANQAECgQIBAAAAA==.Alianar:BAAANQADCgMIAwAAAA==.Alicel:BAABNQAECoEYAAIDAAgKHCBpGAClAgADAAgKHCBpGAClAgAAAA==.Altreir:BAAANQADCgYIDQABNQADCggIFgACAAAAAA==.Aluny:BAAANQAECgUIBQABNQAFFAUIBAACAAAAAA==.Aluxxious:BAAANQAECgQICQAAAA==.Alëcream:BAAANQAECgYJCgAAAA==.Alíne:BAAANQAECgUICAAAAA==.',
Am='Amøm:BAAANQAECgUICQAAAA==.',
An='Anduinwill:BAAANQAECgEIAQAAAA==.Andärilho:BAAANQADCgYICwAAAA==.Ankados:BAAANQAECgYJEQABNQAECgkJIAAHAK4fAA==.Ankapos:BAAANQAECgQICQAAAA==.Annish:BAAANQADCgYJCwAAAA==.Anthorforged:BAAANQAECgYJCwAAAA==.',
Ap='Apocalipse:BAABNQAECoEgAAIIAAkKbhmJAgDaAgAIAAkKbhmJAgDaAgAAAA==.',
Aq='Aquillez:BAAANQAECgQJBAAAAA==.',
Ar='Araurz:BAAANQAECgQJBAABNQAECgUICwACAAAAAA==.Arinn:BAAANQAECgYJCgAAAA==.Arkcirce:BAAANQAECgMIAwABNQAECgYJDAACAAAAAA==.Arkw:BAAANQADCgMIAwAAAA==.Artradian:BAAANQAECgQIBAAAAA==.Arucàrd:BAAANQADCgYJCgAAAA==.Aryethi:BAABNQAECoEWAAIJAAUKjw3QpwAaAQAJAAUKjw3QpwAaAQAAAA==.',
As='Ashabellanar:BAAANQAECgMIBgAAAA==.Ashenna:BAAANQAECgQIBQAAAA==.Aslatiel:BAAANQADCgYIBgABNQAECgYJCwACAAAAAA==.',
Au='Aurdraen:BAAANQAECgEIAQAAAA==.',
Av='Avanthara:BAAANQAECgQICQAAAA==.',
Aw='Awk:BAAANQAECgYICQAAAA==.',
Az='Azuros:BAAANQABCgIIAgAAAA==.',
['Aø']='Aøc:BAABNQAECoEgAAIJAAgKLhTdUQAPAgAJAAgKLhTdUQAPAgAAAA==.',
Ba='Babara:BAAANQABCgYIBwAAAA==.Babyfart:BAAANQAECgQIDgAAAA==.Bakushiterra:BAAANQAECgYJCQAAAA==.Barao:BAAANQAECgYJCgAAAA==.Barriguinha:BAAANQAECgIIAgAAAA==.Batlemage:BAAANQABCgQIBgAAAA==.Batmano:BAAANQADCggIGAAAAA==.',
Be='Beornin:BAAANQADCgMIAwAAAA==.',
Bh='Bhast:BAAANQADCggICAABNQAECggJEgACAAAAAA==.Bherg:BAAANQAECgIIAgAAAA==.',
Bi='Biskademon:BAABNQAECoEcAAIEAAgKCRobFQB1AgAEAAgKCRobFQB1AgAAAA==.Bizum:BAAANQADCgcIDAAAAA==.Bizumgãoo:BAAANQAECgQIBAAAAA==.',
Bj='Bjørn:BAAANQADCgQIBAAAAA==.',
Bl='Blackee:BAAANQAECgIIAwAAAA==.Blackwatch:BAAANQAECgEJAgAAAA==.Blecktk:BAAANQAECgMIBAAAAA==.Blitzkrig:BAACNQAFFIEFAAIKAAIKMws5AACkAAAKAAIKMws5AACkAAA1AAQKgSAAAgoACQoRHncAABcDAAoACQoRHncAABcDAAAA.Bloodlioness:BAAANQAECgEIAQAAAA==.Bloodyclaw:BAAANQADCggIHAAAAA==.',
Bo='Boomgoesyou:BAABNQAECoEWAAILAAgK1Q2xNgC3AQALAAgK1Q2xNgC3AQAAAA==.Bourdriel:BAAANQAECgUJCQAAAA==.',
Br='Bradoki:BAAANQAECgMIBgAAAA==.Brancalleone:BAAANQAECgIJAgAAAA==.Brazukmaiden:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Brisawave:BAABNQAECoEmAAIMAAkKhiLSBwBZAwAMAAkKhiLSBwBZAwAAAA==.Brizagato:BAAANQAECgYJCwAAAA==.Broke:BAAANQAECgQIBQAAAA==.Brujaria:BAAANQAECgQIBAAAAA==.Bruxxaum:BAAANQADCgEIAQAAAA==.Brád:BAAANQAECgQICwAAAA==.',
Bu='Bushido:BAAANQADCgYIEgAAAA==.Bustgril:BAAANQAECgIJAwAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQADCgMIAwAAAA==.',
Ca='Caiquebmq:BAAANQAECgEIAQAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgYIDQACAAAAAA==.Calanguinhe:BAAANQAECgEIAQAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAAANQAECgQJCAAAAA==.Canard:BAAANQADCgUJCAABNQAECggJCQACAAAAAA==.Cannibal:BAAANQABCgcICwAAAA==.Carinha:BAAANQADCggJAgAAAA==.Carloxamã:BAAANQAECgYJEAABNQAECgcJEgACAAAAAA==.Cassisus:BAAANQADCggICAAAAA==.Catarnaldo:BAAANQADCgYICQABNQAECgUICQACAAAAAA==.Cathiseev:BAAANQAECgYJEAAAAA==.Cathury:BAAANQAECgMJCAAAAA==.Catÿ:BAAANQAECgUIDgABNQAECgkJIwANAAwlAA==.Cavernozo:BAAANQAECgQIBAABNQAECgcIBAACAAAAAA==.Caxola:BAAANQADCgIIAgAAAA==.',
Ce='Cerino:BAAANQADCgQIBAAAAA==.Cevadão:BAAANQAECgcJDQABNQAECggJEgACAAAAAA==.',
Ch='Chaleira:BAAANQADCgUICQAAAA==.Changjin:BAAANQADCgMIAwAAAA==.Cheweir:BAAANQAECgIIAgAAAA==.Chiclete:BAABNQAECoEZAAMOAAgKmxONGwDDAQAOAAcK6BGNGwDDAQAPAAcK6xBuCwDBAQAAAA==.Chopz:BAAANQAECgIIAgAAAA==.Chovor:BAAANQAECgUJBQAAAA==.Chrizantm:BAAANQAECgIIAgABNQAECgUICwACAAAAAA==.Chucknòórris:BAAANQAECgEIAQAAAA==.',
Cl='Clairë:BAAANQAECgUIDAAAAA==.Claude:BAAANQADCgQIBQAAAA==.Clbalena:BAAANQADCgEIAQAAAA==.Clio:BAAANQAECgQIDwAAAA==.',
Co='Cockcroft:BAAANQADCgQIBgABNQAECggIHAAQADwOAA==.Coionir:BAAANQAECgYJBwAAAA==.Coiovoker:BAAANQADCgEIAQABNQAECgYJBwACAAAAAA==.Coldblooded:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.Comunistaa:BAABNQAECoEbAAIHAAkKfiAyDABYAwAHAAkKfiAyDABYAwAAAA==.Corruptionz:BAAANQAECgQIBAAAAA==.Corstine:BAAANQAECgQIBgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.Couldovisk:BAAANQADCgIJAgAAAA==.',
Cr='Cronosxdm:BAAANQAFFAEJAQAAAA==.Crucyatus:BAAANQAECgcIEQAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
['Cá']='Cássia:BAAANQADCggICAAAAA==.',
['Cå']='Cåssio:BAAANQAECgYIDwAAAA==.',
['Cÿ']='Cÿgnus:BAAANQAECggIBwABNQAECggIHQARAKklAA==.',
Da='Dadashi:BAAANQADCggICAAAAA==.Danadinn:BAAANQADCgcIBwAAAA==.Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAABNQAECoEbAAMSAAgKgA/UCgCRAQATAAgKrw55ZADiAQASAAcKOw7UCgCRAQAAAA==.Darklendio:BAAANQADCgUICgAAAA==.Daroncosp:BAAANQADCgIJAgAAAA==.Dashuman:BAAANQAECgcJDgAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadguth:BAAANQAECggJBwAAAA==.Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUICAABNQAECgYIDQACAAAAAA==.Deceive:BAAANQAECgQJCQAAAA==.Defroque:BAAANQAECgUJBQAAAA==.Deis:BAAANQADCgUIBAAAAA==.Delarÿn:BAAANQADCggJHQABNQADCggJHwACAAAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Demzumilde:BAAANQAECgMIBAAAAA==.Denevy:BAAANQAECgcJDgAAAA==.Deraelda:BAAANQADCgMIBAAAAA==.Derbster:BAAANQAECgcICgAAAA==.Destructiom:BAAANQAECgYIDwABNQAECgYJEgACAAAAAA==.',
Dh='Dhamburguer:BAAANQAECgcJEQAAAA==.Dhanadrai:BAAANQAECgYJDwAAAA==.',
Di='Diamath:BAAANQADCgUJBQAAAA==.Diggop:BAAANQAECgIJAgAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQACAAAAAA==.Dima:BAABNQAECoEdAAIMAAkK6R54CgA7AwAMAAkK6R54CgA7AwAAAA==.',
Do='Dornaa:BAAANQADCgYICgAAAA==.Dosmagos:BAAANQABCgUIBwAAAA==.Doulce:BAAANQAECgMIBQAAAA==.',
Dr='Dracarysz:BAAANQADCgUJBQAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Dragonbaby:BAAANQADCgUIBQAAAA==.Drainetty:BAAANQAECgEIAQAAAA==.Dranacs:BAAANQAECggJCQAAAA==.Dreamremix:BAAANQAFFAEIAQAAAA==.Dreyol:BAAANQADCgYICQAAAA==.Drts:BAABNQAECoEeAAIUAAgKaR6jRgC3AgAUAAgKaR6jRgC3AgAAAA==.',
Du='Dumar:BAAANQAECgMJBAAAAA==.Duromargh:BAAANQADCgMIAwAAAA==.',
Ed='Eduarthas:BAAANQAECgUJCQAAAA==.',
Eg='Egoist:BAAANQADCggJDwAAAA==.',
El='Elementys:BAAANQAECgEJBAABNQAECgQICAACAAAAAA==.Elemëntum:BAAANQADCgcIBwAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECgkJKQAGACwjAA==.Elinaara:BAABNQAECoEVAAIVAAYKBgx1JAAoAQAVAAYKBgx1JAAoAQAAAA==.Elizabeth:BAAANQADCggJCAAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Ellithyx:BAAANQAECgIIAgAAAA==.Elmagoprior:BAAANQAECgIIAgAAAA==.Elricky:BAAANQADCgIIBAAAAA==.Eluna:BAAANQAECgQJBwAAAA==.Eluric:BAAANQADCggICAABNQAECgkJKQAGACwjAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.',
Er='Ermooke:BAAANQAECgEIAQAAAA==.',
Es='Escanorzão:BAAANQADCgcJDAABNQADCggIFgACAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Executepowa:BAAANQADCggICAAAAA==.Exo:BAAANQAECgYIEwAAAA==.Exorciseur:BAABNQAECoElAAIRAAkKxSI8BACLAwARAAkKxSI8BACLAwAAAA==.',
Fa='Fabercästell:BAAANQAECgcICgAAAA==.Fabers:BAAANQAECgMIAwAAAA==.Fargunn:BAAANQAECgYIDAAAAA==.',
Fe='Feanori:BAAANQAECgYJEQAAAA==.Feanør:BAAANQADCggIFQAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgcJCgACAAAAAA==.Fennris:BAAANQAECgEJAgAAAA==.Feyrin:BAAANQADCggIHQAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBwABNQAECgEIAQACAAAAAA==.Flodfelblood:BAAANQAECgEIAQAAAA==.',
['Fí']='Fíli:BAAANQAECgEIAQAAAA==.',
['Fï']='Fïrestorm:BAAANQADCgYIBgAAAA==.',
Ga='Gabela:BAAANQAECgIIAwAAAA==.Gabrael:BAAANQABCgQJBAAAAA==.Gaiataur:BAAANQADCgUJBgAAAA==.Galandiel:BAAANQADCggIDgAAAA==.Galinni:BAAANQADCggICAAAAA==.Gallon:BAAANQAECgUJCgAAAA==.Garfall:BAAANQAECgUJBQAAAA==.',
Gl='Glacyale:BAAANQAECgIIAgAAAA==.Glisa:BAAANQAECgYIBgAAAA==.',
Gn='Gnomepink:BAAANQADCggIEwAAAA==.',
Go='Godadrian:BAAANQAECgUIDAAAAA==.Gordãobtm:BAAANQAECgYICQAAAA==.Gosu:BAAANQAECggIEQAAAA==.',
Gr='Gralfor:BAAANQAECgIJAgAAAA==.Grekorio:BAAANQADCggIFAAAAA==.Greylord:BAAANQAECgIIAgABNQAECgYJDQACAAAAAA==.Greylorddrak:BAAANQAECgYJDQAAAA==.Greylordp:BAAANQAECgEIAQABNQAECgYJDQACAAAAAA==.Gromitak:BAAANQADCgIIAgAAAA==.Gronak:BAAANQAECgQJBAAAAA==.',
Gu='Guhtz:BAAANQADCgMIAwAAAA==.Guillyn:BAAANQADCggIDAAAAA==.Gults:BAAANQADCgQIBAAAAA==.Gultsz:BAAANQADCgUIBwAAAA==.Gunpowter:BAAANQABCgIIAwAAAA==.Guxrock:BAAANQAECgIIAwAAAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYJBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hafo:BAAANQADCgYJDQAAAA==.Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQAECgQIBAAAAA==.Hamiister:BAAANQADCgQIBAAAAA==.Hancalimon:BAAANQAECgQIEAAAAA==.Haokö:BAAANQAECgEIAQAAAA==.Hasanzi:BAAANQADCgUIBQAAAA==.Hastterix:BAAANQAECgQICQAAAA==.Hatezon:BAAANQAECgMIBQAAAA==.',
He='Heavyking:BAAANQAECgUJCgAAAA==.Heishoo:BAAANQADCgIIAgAAAA==.Helitox:BAAANQAECgQJBwAAAA==.Hellhoundish:BAAANQADCgYIBgABNQAECgkJHgATAC0hAA==.Hellreaper:BAAANQAECgYJEgAAAA==.Heloisaa:BAAANQAECgYJDQAAAA==.Helwen:BAAANQAECgEIAQAAAA==.Heracranosx:BAAANQAECgIJAwAAAA==.Herdy:BAAANQADCgMJBAAAAA==.Herta:BAAANQAECgMIBgAAAA==.Hess:BAAANQAECgMICQAAAA==.',
Hi='Hireque:BAAANQAFFAEIAQAAAA==.Hitkilled:BAAANQAECgUIBAAAAA==.Hitkins:BAAANQADCgYJCQAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgUIDAAAAA==.Holycel:BAAANQADCggIDQABNQAECggIGAADABwgAA==.Holyscrim:BAAANQADCgMJAwAAAA==.Hoolylight:BAAANQADCgcIBwAAAA==.',
Hu='Hunterpica:BAAANQAECgYJDQAAAA==.Huntmon:BAAANQAECgYIEQAAAA==.Huskat:BAAANQAECgYIDAAAAA==.',
Hy='Hysillens:BAAANQAECgIJAgAAAA==.',
['Hã']='Hãn:BAAANQADCgEIAQAAAA==.',
['Hä']='Härü:BAAANQADCgUIAwAAAA==.',
Ig='Igno:BAAANQAECgUICAABNQAECgkJLAAHAGIlAA==.',
Il='Ilane:BAAANQABCggIDAAAAA==.Illidatrix:BAAANQAECgYIDQAAAA==.Illïndão:BAAANQADCggICAAAAA==.Ilovealtgirl:BAAANQADCggJFAAAAA==.',
In='Inot:BAAANQAECgYICAAAAA==.',
Ir='Irmãsafada:BAAANQADCgEIAQAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQAECgUICgAAAA==.',
It='Italodpz:BAAANQAECgUIBQAAAA==.Itsälasca:BAAANQADCgUICwAAAA==.',
Iu='Iuri:BAAANQAECgUJBQAAAA==.',
Ix='Ixlzvaxtylxl:BAAANQADCgYIBgAAAA==.',
Iz='Izanna:BAAANQADCgcJCwAAAA==.',
Ja='Jalinrabeidh:BAAANQAECgEIAQAAAA==.Jampack:BAABNQAECoEfAAMMAAkKkiJIFQDcAgAMAAgKKCJIFQDcAgAHAAEKugmN2AA2AAAAAA==.',
Je='Jeevas:BAAANQAECgYJDQAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeguinha:BAAANQABCggJDgAAAA==.Jeu:BAAANQADCgcICQAAAA==.Jeyla:BAAANQADCgEIAQAAAA==.',
Jh='Jhasperr:BAAANQADCggIGQAAAA==.',
Jo='Jocabiroca:BAABNQAECoEZAAMUAAgKWRYUbABNAgAUAAgKWRYUbABNAgAKAAEKlwJWCQAvAAAAAA==.Johnez:BAAANQADCgIIAgAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAAANQAECgYJDgAAAA==.',
Jr='Jrxamã:BAAANQAECgQJBwAAAA==.',
Ju='Juliia:BAAANQAECgMJBgAAAA==.Jusgu:BAAANQAECgIIBQAAAA==.',
['Jö']='Jönah:BAAANQADCgMIAwAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaiev:BAAANQADCgYICgAAAA==.Kaju:BAABNQAECoEVAAIIAAkK8B6SAwCVAgAIAAkK8B6SAwCVAgAAAA==.Kalinis:BAAANQAECgEJAQAAAA==.Kalliiope:BAAANQAECgQIEgAAAA==.Kamesenin:BAAANQADCgEIAQAAAA==.Kamïlla:BAAANQAECgQIBwAAAA==.Karak:BAAANQADCgIJAgAAAA==.Karamatsu:BAAANQAECgIIAgAAAA==.Karollus:BAAANQABCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCggIDAAAAA==.Katona:BAAANQAECgYIBgAAAA==.Kauss:BAAANQADCggJCAAAAA==.',
Kd='Kdposa:BAAANQABCgQIBAAAAA==.',
Ke='Keior:BAAANQAECgEIAQAAAA==.Kenai:BAAANQAECgYJDAAAAA==.Kewenz:BAABNQAECoEWAAIGAAkKUiMoBQCUAwAGAAkKUiMoBQCUAwAAAA==.Keylaa:BAAANQAECgUIBQAAAA==.',
Kh='Khasin:BAAANQAECgUJCQAAAA==.',
Ki='Kierke:BAAANQADCgYJCAABNQAECgQJBwACAAAAAA==.Kindz:BAAANQADCgQIBAABNQAECgkJFgAGAFIjAA==.Kiregeth:BAAANQAECgUIBwAAAA==.Kitrel:BAAANQAECgMIAwAAAA==.',
Kl='Kllauzz:BAAANQAECgQJBgABNQAECgUJDQACAAAAAA==.Kllauzzmage:BAAANQAECgIIAgABNQAECgUJDQACAAAAAA==.Kllauzzpalla:BAAANQAECgUJDQAAAA==.',
Kn='Knufolgado:BAAANQADCgYIBgAAAA==.',
Ko='Kolyn:BAABNQAECoEpAAIGAAkKLCP0BQCKAwAGAAkKLCP0BQCKAwAAAA==.Komamurasou:BAAANQAECgQIBAAAAA==.',
Kr='Krastian:BAAANQAECgQJDAAAAA==.Kreegh:BAAANQAECgEIAQAAAA==.Krupper:BAAANQAECgMIAwABNQAECgYIDAACAAAAAA==.Krynesa:BAAANQADCggICwAAAA==.',
Ku='Kuhaku:BAAANQADCgQIBAAAAA==.Kukuatzo:BAAANQAECgQIBAAAAA==.',
Ky='Kyary:BAAANQADCgUIBQABNQAECggIGgASAIEbAA==.Kyndin:BAAANQADCgEIAQABNQAECgkJFgAGAFIjAA==.',
['Kä']='Kälini:BAAANQADCgcIDAABNQADCggJHwACAAAAAA==.Käyros:BAAANQADCgUJCgAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAAANQAECgYIDgAAAA==.Köri:BAABNQAECoEZAAMUAAkKvh20MwDzAgAUAAkKbB20MwDzAgAIAAEKMx3SJgBSAAAAAA==.',
La='Lakaioo:BAAANQAECgYJDQAAAA==.Lamont:BAAANQAECgUIDQAAAA==.Lampiião:BAABNQAECoEVAAIGAAYKgRQ0ZgC7AQAGAAYKgRQ0ZgC7AQAAAA==.Lanllaniel:BAAANQAECgUIBwAAAA==.Largartixa:BAAANQADCgQJBAABNQAECgQJBAACAAAAAA==.Larslion:BAAANQABCgYJBgAAAA==.',
Le='Lebelisco:BAAANQAECgYICgAAAA==.Leehyori:BAAANQAECgEIAgAAAA==.Lennorien:BAAANQAECgYIEgAAAA==.Lestard:BAAANQABCgQIBAAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Lifestrream:BAAANQAECgUIDQABNQAECgkJFgAWABQUAA==.Liftshertail:BAABNQAECoEhAAQXAAcKEx6eDgBxAgAXAAcKEx6eDgBxAgAYAAUKBxHzGwAmAQAZAAIKxQwMFABmAAAAAA==.Ligiaf:BAAANQAECgIJAwAAAA==.Liilum:BAAANQADCgcIBwAAAA==.Linë:BAAANQADCggJHwAAAA==.Linëa:BAAANQADCgIJBQAAAA==.Linüss:BAAANQAECgEIAQAAAA==.Lionarot:BAAANQAECgQIDAAAAA==.Littleshelby:BAAANQADCgYJDwAAAA==.',
Lo='Lobinox:BAAANQADCggICgAAAA==.Longaim:BAAANQAECgYJEAAAAA==.Lorthaeron:BAAANQAECgYJDwAAAA==.Losdor:BAAANQADCgcIBwAAAA==.Lostminder:BAAANQAECgIIAgAAAA==.Lothbrok:BAAANQAECgUJEAAAAA==.',
Lu='Lucanor:BAAANQADCgUIBQAAAA==.Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAACNQAFFIEMAAITAAUKnRT5BwCRAQATAAUKnRT5BwCRAQA1AAQKgR8AAxMACQrZIcgbABIDABMACQo+IcgbABIDABIAAQrQIascAFoAAAAA.Lukanelas:BAAANQADCgcJDQAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luminosos:BAAANQAECgEJAQAAAA==.Luna:BAAANQAECgcIEQAAAA==.Lunes:BAAANQAECgYIEgAAAA==.Lusther:BAAANQAECgIIAgAAAA==.Luzdacelesc:BAABNQAECoEtAAMBAAkKISZvAADwAwABAAkKISZvAADwAwANAAIKeA2IlQCHAAAAAA==.',
Ly='Lyaah:BAAANQADCggIEQAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYJBgAAAA==.',
['Lø']='Lølzhê:BAABNQAECoEmAAIaAAcKjxy2DgAaAgAaAAcKjxy2DgAaAgAAAA==.Løvizinha:BAAANQAECgQIBQAAAA==.',
['Lú']='Lúaprata:BAAANQADCggJDgAAAA==.',
Ma='Maagnuss:BAAANQADCgIIAgAAAA==.Madbuddha:BAAANQADCgQJBAAAAA==.Mageli:BAAANQAECgEIAQAAAA==.Magodanilo:BAAANQADCgYJBgAAAA==.Magodavida:BAAANQAECgQIDAAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maheena:BAAANQAECgQIBgAAAA==.Mai:BAAANQAECgUJDwAAAA==.Mairon:BAAANQADCgcICQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAAANQAECgYJDQAAAA==.Malborion:BAAANQAECgQIBgAAAA==.Malevolent:BAAANQADCgYIBgAAAA==.Malignõ:BAABNQAECoEsAAIHAAkKYiUVAgDXAwAHAAkKYiUVAgDXAwAAAA==.Maltozo:BAAANQAECgYJEAAAAA==.Mandrakson:BAAANQAECgcIEAAAAA==.Mandubim:BAAANQADCgEIAQAAAA==.Mariiamil:BAAANQAECgEJAQAAAA==.Marvelos:BAAANQABCggJCgAAAA==.Marvvila:BAAANQAECgUICgAAAA==.Marycristiny:BAAANQAECgcJEAAAAA==.Mauwolf:BAAANQAECgIJAgAAAA==.Mazaky:BAAANQAECgYIDAAAAA==.',
Me='Medivi:BAAANQADCgMIAwAAAA==.Megumi:BAAANQAECgMIAwAAAA==.Memphis:BAAANQADCgcIBwAAAA==.Menorxidil:BAABNQAECoEfAAIaAAgKchnkCwBbAgAaAAgKchnkCwBbAgAAAA==.Merigold:BAAANQADCggIEwAAAA==.Mestreløck:BAAANQADCgMIBgAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.',
Mh='Mhenb:BAAANQAECgYICgAAAA==.Mhorgothh:BAAANQADCgQIBAAAAA==.',
Mi='Micherouc:BAAANQADCgYIBwAAAA==.Mikal:BAAANQAECgQJBQAAAA==.Minort:BAAANQAECgIJAwAAAA==.Minör:BAAANQAECgQJBgAAAA==.Missmarvel:BAAANQABCgYICgAAAA==.Mithrael:BAAANQADCgUIBQAAAA==.Mizukagesou:BAAANQAECgIJBAAAAA==.',
Mo='Monkbest:BAAANQADCgcICwAAAA==.Montej:BAAANQAECgEIAQAAAA==.Montäna:BAAANQABCgMIAwAAAA==.Mooncap:BAAANQAECgUICgAAAA==.Moondragoon:BAAANQADCgcICQAAAA==.Morakhir:BAAANQADCgQIBAAAAA==.Moranguinhö:BAAANQADCgEJAQAAAA==.Mordiidinha:BAAANQAECgQJBwABNQAECgkJLAAHAGIlAA==.Morganviolet:BAAANQAECgQJCAAAAA==.',
Mu='Mugidinhaa:BAAANQABCgcIBQAAAA==.Murdoky:BAAANQADCgEIAQABNQAECgIIAwACAAAAAA==.Musleira:BAAANQAECgQIBQAAAA==.',
My='Myrzin:BAAANQADCggIDAAAAA==.Mythariel:BAAANQAECgEIAQAAAA==.Mythcut:BAAANQAECgQICwAAAA==.Mythjegue:BAAANQADCgYIBgAAAA==.',
['Mä']='Mällü:BAAANQAECgUJCQAAAA==.Mälthazar:BAAANQAECgYIEQAAAA==.Määt:BAAANQADCggICAABNQAFFAUJCgAbANcSAA==.',
['Må']='Mågus:BAAANQAECgYJDAAAAA==.',
['Mò']='Mòrgan:BAAANQADCgQIBQAAAA==.',
['Mø']='Mørgåna:BAAANQAECgQICQAAAA==.',
Na='Naamt:BAAANQADCgYIBgAAAA==.Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQADCgYICgABNQADCggJEAACAAAAAA==.Nagashina:BAAANQADCggIFgAAAA==.Naizow:BAAANQAECgUICQAAAA==.Namisan:BAAANQAECgEIAQAAAA==.Namuhß:BAAANQAECgQICgAAAA==.Namøøh:BAAANQAECgUIBQAAAA==.Naomiy:BAAANQADCgYIEAAAAA==.Naoto:BAAANQAECgQIDQAAAA==.Napru:BAAANQADCgEIAQAAAA==.Nardalan:BAAANQADCgQJBAABNQAECgUICgACAAAAAA==.Narjes:BAAANQAECgUIBgAAAA==.Nathrezim:BAAANQADCgcIDAAAAA==.',
Ne='Necrogélido:BAAANQADCgYIEQAAAA==.Nefariio:BAAANQADCgQIBAAAAA==.Neninhaa:BAAANQADCgcJBQAAAA==.Neopaladino:BAAANQAECgMIAwAAAA==.Nerlock:BAAANQAECgIJAwAAAA==.',
Ni='Nicom:BAAANQADCgYIBgAAAA==.Nightforms:BAAANQADCggIEAAAAA==.Nikity:BAAANQAECgcIEgAAAA==.',
No='Noahwallker:BAAANQADCgYIBgAAAA==.Noazard:BAAANQAECgEJAQAAAA==.Nopainnogain:BAAANQAECgEIAQAAAA==.Nortênho:BAAANQAECgYJEQAAAA==.Nosferüs:BAAANQAECgQIBAAAAA==.Nossilat:BAABNQAECoEdAAIRAAgKqSUVBgBiAwARAAgKqSUVBgBiAwAAAA==.',
Nu='Nuit:BAAANQAECgEJBAAAAA==.Nunhöly:BAAANQAECgUICAAAAA==.',
Ny='Nysthiael:BAAANQAECgYJEwAAAA==.Nyxicel:BAAANQAECgQIBwABNQAECggIGAADABwgAA==.',
['Nä']='Nästÿ:BAAANQADCgYIBwAAAA==.',
['Nö']='Nöturnö:BAAANQABCgYICgAAAA==.',
['Ný']='Nýmm:BAAANQAECgUJCwAAAA==.',
Oc='Ocon:BAAANQABCgIIAgAAAA==.',
Od='Odigo:BAAANQADCgIIAgAAAA==.Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCggIGQAAAA==.',
Ol='Oldcook:BAAANQABCgYIBQAAAA==.Oliele:BAAANQAECgIIAwAAAA==.',
On='Onixpala:BAAANQAECgQJBAABNQAECgUJBQACAAAAAA==.Onlydruix:BAAANQADCgIIAgAAAA==.',
Op='Opsdesculpa:BAAANQAECgUJEQAAAA==.',
Or='Organ:BAAANQAECgQIBQAAAA==.Orinoldo:BAABNQAECoEgAAIUAAkKNh5HJAAnAwAUAAkKNh5HJAAnAwAAAA==.',
Os='Osiria:BAAANQABCgYICAAAAA==.',
Ot='Otacki:BAAANQADCgIIAgAAAA==.Otherside:BAAANQAECgMIBAABNQAECgkJJQAcAAYWAA==.Otávio:BAAANQADCggJFQAAAA==.',
Ow='Owlcapøne:BAAANQADCggICAAAAA==.',
Ox='Oxentedragon:BAAANQADCgMIAwAAAA==.',
Oz='Ozyi:BAAANQAECgUJBQAAAA==.',
Pa='Pachiinko:BAAANQAECgYJAgAAAA==.Painkke:BAAANQAECgEIAQAAAA==.Palluz:BAAANQAECgMIAwABNQAECgkJJQAdAF8eAA==.Panicdeath:BAAANQAECgEIAQAAAA==.Parafinaisis:BAAANQAECgQJBQAAAA==.Parafinared:BAAANQADCgcIEwAAAA==.Parrot:BAAANQADCgEIAQAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.',
Pe='Peltrow:BAAANQAFFAEIAQAAAA==.Penndrive:BAAANQADCgIIAgAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgUIBwACAAAAAA==.Pesaa:BAAANQAECgYIEgAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Phesti:BAAANQABCgEIAQAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Picklerick:BAAANQAECgIIAQAAAA==.Pirizin:BAABNQAECoEiAAIJAAgKCxvoPgBXAgAJAAgKCxvoPgBXAgAAAA==.',
Po='Popopeka:BAAANQADCgcIBwAAAA==.Porcaleta:BAAANQAECgUIDAAAAA==.Portal:BAAANQAECgUJCgAAAA==.Portelamage:BAABNQAECoEkAAIUAAkKWR4DKgATAwAUAAkKWR4DKgATAwAAAA==.Portheus:BAAANQADCggIFwAAAA==.',
Pr='Praeglacius:BAABNQAECoEYAAMHAAgKcQ2ZRQDdAQAHAAgKcQ2ZRQDdAQAMAAIK/ACp0wAzAAAAAA==.Priapista:BAAANQADCgUIBQAAAA==.Priyla:BAAANQABCgcICgAAAA==.Prosaic:BAAANQADCggICAABNQADCggJDwACAAAAAA==.Pråhå:BAAANQAECgQICAAAAA==.',
Ps='Psicopanda:BAAANQAECgUICQAAAA==.Psychiclink:BAAANQADCgMIAwABNQAECgkJLQABACEmAA==.',
Pu='Puffys:BAAANQAECgEIAQAAAA==.',
Pw='Pwcca:BAAANQAECgEJAQAAAA==.',
['Pó']='Pórthosrox:BAAANQADCgYICAAAAA==.',
['Pú']='Púh:BAAANQADCgQIBAABNQAECggJGAAeANEdAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAAANQAECgYIEgAAAA==.Raewyn:BAAANQAECggIEAAAAA==.Rafaelgame:BAAANQAECgQICAAAAA==.Ragdead:BAACNQAFFIEFAAIfAAIKRgkzFABvAAAfAAIKRgkzFABvAAA1AAQKgRkAAh8ACAobG2UiAEMCAB8ACAobG2UiAEMCAAAA.Ragdöll:BAAANQADCgcJCQAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAFFAIIBQAfAEYJAA==.Rairone:BAAANQAECgQJBwAAAA==.Raparigaloka:BAAANQAECgUICQAAAA==.Rapunxel:BAABNQAECoElAAMcAAkKBhbjBAC3AgAcAAkKBhbjBAC3AgAbAAUKZAgNlQALAQAAAA==.Rarkion:BAAANQAECgYIDAAAAA==.Raulthalas:BAAANQADCgYIBgAAAA==.Rawrii:BAAANQADCgUIBQAAAA==.Raynmake:BAAANQAECgEIAQABNQAECgcIBwACAAAAAA==.',
Rb='Rbchama:BAAANQAECgQJDgAAAA==.',
Re='Redvil:BAAANQADCgUJBwAAAA==.Revoltedhunt:BAAANQAECggICgABNQAFFAYIEAAGAJARAA==.Revolthed:BAACNQAFFIEQAAMGAAYKkBGOBwAWAQAdAAQKnBnjBwBJAQAGAAQKuAaOBwAWAQA1AAQKgSIAAx0ACQpYIiEJABMDAB0ACQqsISEJABMDAAYABQqUGntsAKgBAAAA.',
Rh='Rhaadora:BAAANQAECgQIBAAAAA==.Rhoghar:BAAANQAECgcJDAAAAA==.Rhoghardruid:BAAANQAECgIJAgABNQAECgcJDAACAAAAAA==.',
Ri='Riachu:BAAANQADCgcIBwAAAA==.Riluyu:BAAANQADCgQIBQAAAA==.',
Ro='Rokalf:BAAANQAECgcIDgAAAA==.Rossiten:BAAANQAECgUJCwAAAA==.Roöf:BAAANQAECgUIEQAAAA==.',
Ru='Rubya:BAAANQAECgEJAQABNQAECgMJAwACAAAAAA==.Runavento:BAAANQADCgIIAgAAAA==.Ruélatórta:BAAANQAECgQJBwAAAA==.',
['Rä']='Räidela:BAABNQAECoEYAAMbAAgKjBs8JQCQAgAbAAgKjBs8JQCQAgAcAAEK2hLqXwBAAAAAAA==.',
Sa='Sagman:BAAANQABCgIIAgAAAA==.Sagädegemeos:BAAANQAECgQIDAAAAA==.Salasär:BAAANQAECgYJEgAAAA==.Saleyi:BAAANQAECgEJAgAAAA==.Saluton:BAAANQAECgEIAgAAAA==.Samidemon:BAAANQAECgEIAQAAAA==.Sarashi:BAAANQADCgUJDAAAAA==.Sarte:BAAANQADCggIDQAAAA==.Sarzlok:BAAANQAECgEIAQAAAA==.',
Sc='Schiabellee:BAAANQADCggJEQAAAA==.Scoobydruida:BAAANQAECgYIDQAAAA==.Screan:BAAANQAECgYIEgAAAA==.Scrøøge:BAAANQAECgQJCAAAAA==.',
Se='Seelyvorey:BAABNQAECoEWAAQgAAgKMRywHAAZAgAgAAcKNBywHAAZAgAfAAUKFxZ8SwBSAQADAAMKARcEaQDNAAAAAA==.Selph:BAAANQAECgcIBAAAAA==.Sengos:BAAANQAECgQIBAAAAA==.Sephhiroth:BAAANQADCgcICgAAAA==.Serrase:BAAANQAECgcJEAAAAA==.',
Sh='Shalquoir:BAAANQAECgcIBwABNQAECgcIIQAXABMeAA==.Sharckaron:BAAANQAECgIIAwAAAA==.Shedleass:BAAANQAECgUICgAAAA==.Shendalar:BAAANQAECgYIEAAAAA==.Shigami:BAAANQADCgcJBwAAAA==.Shywa:BAAANQADCgQIBgAAAA==.Shîvas:BAAANQAECgEIAgAAAA==.Shøtinha:BAAANQAECgcJEwAAAA==.Shøwtime:BAAANQAECgEIAQABNQAECgUICwACAAAAAA==.',
Si='Sianus:BAAANQAECgIJBAAAAA==.Sicarious:BAAANQADCgYICwAAAA==.Sicariuz:BAABNQAECoEYAAIJAAcKDBTAZQDLAQAJAAcKDBTAZQDLAQAAAA==.Silara:BAAANQADCgYICQAAAA==.Silves:BAAANQABCgYICgAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sl='Slickdaddy:BAAANQADCgQIBAABNQAECgcJEgACAAAAAA==.',
Sm='Smarcão:BAAANQABCgEIAQAAAA==.',
Sn='Snipinho:BAAANQAECgcICgAAAA==.Snowtail:BAAANQAECgIIBgABNQAECgQIBwACAAAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Sokun:BAAANQAECgEIAQAAAA==.Solaryel:BAAANQAECgcICgAAAA==.Solidheals:BAAANQAECgIIBgAAAA==.Sougigante:BAAANQAECgMICAAAAA==.Soulbinder:BAAANQADCgIJAgAAAA==.Soupombagira:BAAANQAECgMIAwAAAA==.',
Sp='Spellshadown:BAAANQAECgUIEQAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQAECgMIAwAAAA==.',
St='Stelluna:BAAANQAECgEIAQAAAA==.Stormimrage:BAAANQAECgEIAQAAAA==.Strexx:BAAANQAECgQIBQAAAA==.Stronoffgard:BAAANQAECgcJDAAAAA==.Stronq:BAAANQADCgYICAAAAA==.',
Su='Sulfur:BAAANQAECgIIBAAAAA==.',
Sy='Syberdal:BAAANQAECgQIDwAAAA==.',
['Sà']='Sàgadegemeos:BAAANQAECgUIEAAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIBAABNQADCggIDgACAAAAAA==.',
Ta='Tacka:BAAANQADCggJHgAAAA==.Tafoki:BAABNQAECoEYAAMeAAgK0R2dBgDSAgAeAAgKMB2dBgDSAgAHAAEKaiGXwgBgAAAAAA==.Tanakin:BAAANQADCgIIAgABNQAECggIGgASAIEbAA==.Tangdebanana:BAAANQADCgUJBQABNQAECgYIDQACAAAAAA==.Tankairotty:BAAANQAECgEIAQAAAA==.Tanrity:BAAANQAECgMJAwAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAAANQAECgMIAwAAAA==.',
Te='Temeloorego:BAAANQAECgMIAwAAAA==.Temkutemmedo:BAAANQAECgIIBQABNQADCggIFgACAAAAAA==.Tennkkar:BAAANQAECgEIAQAAAA==.Texugojogatv:BAAANQAECgMIBgAAAA==.Texugosa:BAAANQAECgEJAQAAAA==.',
Th='Thamihime:BAAANQAECgYIEAAAAA==.Tharizdum:BAAANQAECgQICgAAAA==.Thlrall:BAAANQAECgEIAQAAAA==.Thontonas:BAAANQADCgIIAgAAAA==.Thornus:BAABNQAECoEWAAISAAgKeCFQAgDqAgASAAgKeCFQAgDqAgAAAA==.Thorudos:BAAANQADCgQIAgAAAA==.Thrandu:BAAANQADCgYIBgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.Thuzalduum:BAAANQADCgIIAgAAAA==.',
To='Toni:BAAANQAECgMIBQAAAA==.Toshyo:BAAANQAECgYJBgAAAA==.Tostão:BAAANQADCgQIBgAAAA==.Touchhme:BAAANQAECgIIAgAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQACAAAAAA==.',
Tp='Tprdmage:BAAANQAECgEIAQAAAA==.Tprdtank:BAAANQABCgQIBAAAAA==.',
Tr='Trighit:BAAANQADCgYICQAAAA==.Trolhöl:BAAANQAECgcJEwAAAA==.Trollrogue:BAAANQAECgUJDQAAAA==.Troyana:BAAANQADCggICAABNQAFFAUJCgATABMYAA==.',
Tu='Tukiel:BAAANQAECgEJAwAAAA==.Tunkav:BAAANQABCgYJCQAAAA==.Tuska:BAAANQADCgUIBAAAAA==.',
Ty='Tyde:BAAANQAECgQIBgABNQAECgYIEAACAAAAAA==.Typol:BAAANQAECgQICQAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAAANQAECgYJDAAAAA==.',
['Tø']='Tøtemhubby:BAAANQAECgEJAQAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQACAAAAAA==.Umehara:BAABNQAECoEiAAIdAAkKDR/ZBwArAwAdAAkKDR/ZBwArAwAAAA==.Umokh:BAABNQAECoEaAAISAAgKgRtUAwCoAgASAAgKgRtUAwCoAgAAAA==.',
Un='Unbrøken:BAAANQAECgEIAgAAAA==.Unclearnaldo:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.',
Uo='Uolokoelfo:BAABNQAECoEmAAITAAgKsh/KKQDHAgATAAgKsh/KKQDHAgAAAA==.',
Ur='Urannia:BAABNQAECoEdAAIGAAcKehLlUAD/AQAGAAcKehLlUAD/AQAAAA==.Urgath:BAAANQAECgQJCQAAAA==.',
Ut='Uther:BAAANQAECgQIBwAAAA==.',
Va='Valan:BAAANQAECgEIAgAAAA==.Valdeco:BAAANQADCggJCwAAAA==.Valdevino:BAAANQAECgUIBgAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAAANQAECgYIDQAAAA==.Venonpoison:BAAANQADCgMIAgAAAA==.Vermeryn:BAAANQAECgMJAwAAAA==.Vermithór:BAAANQAECgIIAgAAAA==.',
Vi='Viciadø:BAAANQADCggICAABNQAECgkJHAAdAFAfAA==.Villalobos:BAAANQAECgIIBQAAAA==.Vits:BAAANQAECgUIDwAAAA==.',
Vo='Voidsurge:BAAANQAECgEJAgAAAA==.Voidwar:BAAANQAECgEJAQABNQAECgEJAgACAAAAAA==.Vollin:BAAANQAECgUJBQAAAA==.Volrun:BAAANQADCggIDAAAAA==.Voragem:BAAANQAECgUIDAAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.',
Wa='Warlockdoido:BAAANQAECgQIBQAAAA==.Warlôka:BAAANQADCgUIBQAAAA==.',
Wi='Wiillord:BAAANQAECgMIBAAAAA==.Willbm:BAABNQAECoEcAAMJAAcKkAyhgwB0AQAJAAcKMwuhgwB0AQAVAAUKxQzRKgD1AAAAAA==.Winnettou:BAAANQAECgUICAAAAA==.Wipalogo:BAAANQADCggIFgAAAA==.Wise:BAABNQAECoEaAAIJAAgKNyDbKgCxAgAJAAgKNyDbKgCxAgAAAA==.',
Wm='Wmana:BAAANQAECgQICQAAAA==.',
Wr='Wrathi:BAAANQAECgIJAgAAAA==.',
Wu='Wuan:BAAANQAECgcIDwAAAA==.',
Xa='Xamanico:BAAANQAECgQIBQAAAA==.Xanasmanas:BAAANQAECgYIDwAAAA==.Xazon:BAAANQADCgQIBAAAAA==.',
Xh='Xharlios:BAAANQAECgEIAQAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQAECgUICAAAAA==.',
Xy='Xymor:BAACNQAFFIEFAAIYAAIKeA/RBwCSAAAYAAIKeA/RBwCSAAA1AAQKgR8AAhgACQoaIL8EACEDABgACQoaIL8EACEDAAE1AAQKBAgEAAIAAAAA.Xyuwan:BAAANQADCgUIBQAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Ye='Yenniferxd:BAAANQABCgUIBQAAAA==.',
Yl='Ylanna:BAAANQAECgYJDwAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoodoo:BAAANQABCgUJBQAAAA==.Yoriko:BAAANQAECgQIBAAAAA==.Yorú:BAAANQAECgUJCwAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQAECgEIAQAAAA==.',
Za='Zamii:BAAANQADCgQIBQABNQAECgQICgACAAAAAA==.Zarik:BAAANQADCgcIBwAAAA==.',
Ze='Zenolis:BAAANQADCgcJFAAAAA==.Zerathir:BAAANQADCggICgAAAA==.',
Zh='Zhalazar:BAAANQAECgQJBwAAAA==.Zhenb:BAAANQADCgEIAQAAAA==.',
Zi='Zigosmar:BAAANQAECgEJAQAAAA==.',
Zo='Zolet:BAAANQAECgIIAwAAAA==.Zones:BAAANQAECgMIAwABNQAECgYJDAACAAAAAA==.',
Zu='Zumbix:BAAANQADCgcIBwAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Än']='Ängron:BAAANQAECgQIBwAAAA==.Änä:BAAANQADCggIDgAAAA==.',
['Är']='Ärthås:BAAANQADCgMJBQAAAA==.',
['Äz']='Äzra:BAAANQAECgEIAQAAAA==.',
['Ær']='Ærikão:BAAANQAECgQICgAAAA==.',
['Æt']='Ætherfel:BAAANQAECgIIAgAAAA==.',
['Ét']='Étel:BAAANQADCgYIGAAAAA==.',
['Ðr']='Ðrakko:BAAANQADCgQICAAAAA==.',
['Ök']='Ökamì:BAAANQADCgIIAgAAAA==.',
['Ör']='Örigem:BAAANQAECgIIAwAAAA==.',
['ßl']='ßlåkehunter:BAAANQADCgEIAQAAAA==.',
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
