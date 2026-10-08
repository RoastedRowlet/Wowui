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

local lookup = {'Priest-Shadow','Mage-Arcane','Unknown-Unknown','DeathKnight-Unholy','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Druid-Restoration','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Frost','Shaman-Elemental','Druid-Balance','Druid-Guardian','Paladin-Holy','Mage-Frost','Warlock-Destruction','Paladin-Retribution','Priest-Holy','Warrior-Arms','Mage-Fire','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','Monk-Windwalker','Druid-Feral','Warrior-Fury','Warrior-Protection','DeathKnight-Blood','Monk-Mistweaver','Warlock-Demonology','Evoker-Devastation','Priest-Discipline','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abyssdk:BAAANQAECgEJAQABNQAFFAMIBgABAH0jAA==.Abyssfurry:BAAANQADCggJCAABNQAFFAMIBgABAH0jAA==.',
Ac='Acadêmica:BAABNQAECoEnAAICAAgKYhKjmwArAgACAAgKYhKjmwArAgAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adcosmos:BAAANQAECgUIBQABNQAECgYIEQADAAAAAA==.Adebaio:BAACNQAFFIEGAAIEAAMKrA/vDwDaAAAEAAMKrA/vDwDaAAA1AAQKgTEAAgQACQqiJHUHAHgDAAQACQqiJHUHAHgDAAAA.',
Ae='Aegislashh:BAABNQAECoEYAAIFAAYKbAeQOwDpAAAFAAYKbAeQOwDpAAAAAA==.Aerlath:BAACNQAFFIEQAAIGAAYKvhZmAwAMAgAGAAYKvhZmAwAMAgA1AAQKgSoAAgYACQrbJdoCAKoDAAYACQrbJdoCAKoDAAAA.Aetulia:BAABNQAECoEbAAMHAAcKxQ1HPwCLAQAHAAcKxQ1HPwCLAQAGAAEK0AFHaAAhAAAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQAECgMIAwADAAAAAA==.',
Ag='Aggroster:BAAANQAECgIIAgAAAA==.Agnestesia:BAAANQAECgQIBwAAAA==.',
Ah='Ahrathor:BAAANQAECgUICwAAAA==.Ahyeon:BAAANQAECgMIAwAAAA==.',
Ak='Akasta:BAABNQAECoEtAAIIAAcKYB3xDgBgAgAIAAcKYB3xDgBgAgAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.Akâme:BAAANQAECggIEQABNQAFFAQIBwAJAK8UAA==.',
Al='Alascayoung:BAAANQAECgEIAgAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Alatrëon:BAAANQAECgQIBAABNQAECgcIHAAKAGEZAA==.Aldrathion:BAAANQAECgEIAQABNQAECgkJOQALAEQkAA==.Aledk:BAAANQAECgYICAAAAA==.Alessan:BAAANQADCggIDwAAAA==.Alessary:BAAANQADCgYIBwAAAA==.Alfurieb:BAAANQAECgQIDAAAAA==.Alianar:BAAANQADCgMIAwAAAA==.Alicel:BAABNQAECoEdAAMEAAkKXiBCIgCdAgAEAAkKXiBCIgCdAgAMAAEKfhGdkgA1AAAAAA==.Altreir:BAAANQADCgcIFAABNQAECgMIAwADAAAAAA==.Aluny:BAAANQAECgYICAABNQAFFAUICAANADQIAA==.Aluxxious:BAAANQAECgQICQAAAA==.Alëcream:BAAANQAECgYICwAAAA==.Alíne:BAAANQAECgYIDgAAAA==.',
Am='Amrb:BAAANQADCgIIAgAAAA==.Amøm:BAAANQAECgcIDgAAAA==.',
An='Anadirtei:BAAANQAFFAUIAQAAAA==.Anduinwill:BAAANQAECgEIAQAAAA==.Andärilho:BAAANQADCgcIEgABNQAECgcICwADAAAAAA==.Ankados:BAABNQAECoEYAAQOAAkKWRJoRwCjAQAOAAYKmBZoRwCjAQAJAAUKZg5rOAAkAQAPAAEKAxRSTQA1AAABNQAECgkJIQANABggAA==.Ankapos:BAAANQAFFAEIAQAAAA==.Annish:BAAANQADCgYJCwAAAA==.Anrond:BAAANQAECgUIBQAAAA==.Anthorforged:BAABNQAECoEaAAIQAAcK8BNiZQDCAQAQAAcK8BNiZQDCAQAAAA==.Anwvar:BAAANQADCgIIAgAAAA==.',
Ap='Apocalipse:BAABNQAECoEsAAIRAAkKyBrcBACsAgARAAkKyBrcBACsAgAAAA==.',
Aq='Aquillez:BAAANQAECgQJBAAAAA==.',
Ar='Araurz:BAAANQAECgQIBQABNQAECggIGwACAFAPAA==.Arinn:BAABNQAECoEYAAISAAcKZA5pGQCYAQASAAcKZA5pGQCYAQAAAA==.Arkcirce:BAAANQAECgUICQABNQAECgYIEAADAAAAAA==.Arkdemias:BAAANQAECgMIAwABNQAECgUIDQADAAAAAA==.Arkw:BAAANQADCgMIAwAAAA==.Arnaldinho:BAAANQADCgQICAABNQAECgcIEAADAAAAAA==.Arthega:BAAANQAECgMIBAABNQAFFAYIEAAGAL4WAA==.Artradian:BAAANQAECgQIBgAAAA==.Arucàrd:BAAANQADCgYJCgAAAA==.Aryethi:BAABNQAECoElAAITAAgKPw+wjQDWAQATAAgKPw+wjQDWAQAAAA==.',
As='Asafe:BAAANQAECgIIAgABNQAECgUICgADAAAAAA==.Ashabellanar:BAAANQAECgQICAAAAA==.Ashenna:BAAANQAECgcIEQAAAA==.Aslatiel:BAAANQADCgYIBgABNQAECgcIGwAHAMUNAA==.',
Au='Aurdraen:BAAANQAECgEIAQAAAA==.Autonomo:BAAANQAECgEIAQAAAA==.',
Av='Avanthara:BAAANQAECgQIDgAAAA==.',
Aw='Awk:BAABNQAECoEXAAMUAAgKwBv3TQASAgAUAAYK/B33TQASAgABAAYKoB4PIQAIAgAAAA==.',
Az='Azuros:BAAANQABCgIIAgAAAA==.',
['Aø']='Aøc:BAABNQAECoErAAITAAkKNBZNXwBQAgATAAkKNBZNXwBQAgAAAA==.',
Ba='Babara:BAAANQABCgYIBwAAAA==.Babyfart:BAABNQAECoEjAAMFAAcK0RRsJACQAQAFAAcK0RRsJACQAQATAAIKvwYyTAFjAAAAAA==.Bakushiterra:BAAANQAECgYIEQAAAA==.Barao:BAABNQAECoEaAAIHAAgKqRLfLwD5AQAHAAgKqRLfLwD5AQAAAA==.Barriguinha:BAAANQAECgMIBAAAAA==.Baskervile:BAAANQADCgYIBgABNQAECgcICwADAAAAAA==.Batlemage:BAAANQABCgQIBgAAAA==.Batmano:BAAANQADCggIGAAAAA==.',
Be='Belezona:BAAANQADCgUIBQAAAA==.Benningtn:BAAANQADCgQIBAAAAA==.Beornin:BAAANQADCgMIAwAAAA==.Betawizard:BAAANQAECgYICQAAAA==.',
Bh='Bhast:BAAANQADCggICAABNQAECggIEgADAAAAAA==.Bherg:BAAANQAECgUIDAAAAA==.',
Bi='Biskademon:BAABNQAECoEiAAIGAAkKPBoJFQCmAgAGAAkKPBoJFQCmAgAAAA==.Bizum:BAAANQADCgcIDAAAAA==.Bizumgãoo:BAAANQAECgQIBgAAAA==.',
Bj='Bjørn:BAAANQADCgQIBAAAAA==.',
Bl='Blackee:BAAANQAECgIIBAAAAA==.Blackwatch:BAAANQAECgQIBQAAAA==.Blecktk:BAABNQAECoEUAAIVAAgKkxWKewADAgAVAAgKkxWKewADAgAAAA==.Blitzkrig:BAACNQAFFIEOAAMWAAUKjQ4/AAAGAQACAAUKjwnuGwBsAQAWAAMKAQ8/AAAGAQA1AAQKgSkAAxYACQr2ILkAABwDABYACQr2ILkAABwDAAIAAgp1Eg6BAYgAAAAA.Bloodlioness:BAAANQAECgEIAQAAAA==.Bloodswar:BAAANQAECgUIBQAAAA==.Bloodyclaw:BAAANQADCggIHgAAAA==.',
Bo='Bolkien:BAAANQAECgIIAwAAAA==.Boomgoesyou:BAABNQAECoEWAAIOAAgK1Q1ySQCXAQAOAAgK1Q1ySQCXAQAAAA==.Bourdriel:BAABNQAECoEZAAIOAAcK7QosUwBiAQAOAAcK7QosUwBiAQAAAA==.',
Br='Bradoki:BAAANQAECgMIBgAAAA==.Bradví:BAAANQAECgEIAQAAAA==.Brancalleone:BAAANQAECgIJAgAAAA==.Brazukmaiden:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.Brisawave:BAABNQAECoEpAAIKAAkKoyKZDQA/AwAKAAkKoyKZDQA/AwAAAA==.Brizagato:BAABNQAECoEaAAIOAAgKBhQEOAAEAgAOAAgKBhQEOAAEAgAAAA==.Brizzarda:BAAANQADCggICAAAAA==.Broke:BAAANQAECgQIBQAAAA==.Brujaria:BAAANQAECgQIDAAAAA==.Bruxxaum:BAAANQADCgEIAQAAAA==.Brád:BAABNQAECoEfAAITAAgKmBoIUgB2AgATAAgKmBoIUgB2AgAAAA==.',
Bu='Bushido:BAAANQADCgYIEgAAAA==.Bustgril:BAAANQAECgUIDAAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQAECgQIBAAAAA==.',
Ca='Caiquebmq:BAAANQAECgEIAQAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgkJHQAXAHIdAA==.Calanguinhe:BAAANQAECgEIAQAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAAANQAECgcIEwAAAA==.Canard:BAAANQADCgUICAABNQAECggIEwADAAAAAA==.Canards:BAAANQAECgIIAgABNQAECggIEwADAAAAAA==.Cannibal:BAAANQAECgEIAgAAAA==.Carinha:BAAANQADCggJAgAAAA==.Carloxamã:BAABNQAECoEnAAIIAAkKGiFSAgCIAwAIAAkKGiFSAgCIAwAAAA==.Cassisus:BAAANQADCggICAAAAA==.Catarnaldo:BAAANQADCgYICQABNQAECgcIEAADAAAAAA==.Cathiseev:BAABNQAECoEeAAMYAAgKUx8fDADSAgAYAAgKUx8fDADSAgAZAAUKdBG+DwAUAQAAAA==.Cathury:BAAANQAECgMJCAAAAA==.Catÿ:BAABNQAECoEZAAIKAAcKrB/jLwB8AgAKAAcKrB/jLwB8AgABNQAFFAQICgAUAA4lAA==.Cavernozo:BAAANQAECgcIDAABNQAECggIEgADAAAAAA==.Caxola:BAAANQADCgIIAgAAAA==.',
Ce='Ceifhador:BAAANQAECgUIBQAAAA==.Celfier:BAAANQAECgQIBAAAAA==.Cenarioss:BAAANQAECgQIBgAAAA==.Cerino:BAAANQADCgQIBAAAAA==.Cevadão:BAABNQAECoEaAAIaAAkK9hP7GQBFAgAaAAkK9hP7GQBFAgABNQAECggIEgADAAAAAA==.',
Ch='Chaleira:BAAANQAECgUIBQAAAA==.Changjin:BAAANQAECgUICQAAAA==.Chewbaka:BAAANQADCgYIBgAAAA==.Cheweir:BAAANQAECgQIBgAAAA==.Chiclete:BAABNQAECoEoAAQbAAkKmhX4DAAaAgAbAAgKnRP4DAAaAgAJAAgK6hAzIwDfAQAPAAEKORo4RgBMAAAAAA==.Chopz:BAAANQAECgIIAgABNQAFFAMIBgAEAKwPAA==.Chovor:BAAANQAECgUICAAAAA==.Chrizantm:BAAANQAECgQIBwABNQAECggIGwACAFAPAA==.Chucknòórris:BAAANQAECgYICQAAAA==.Chøcøballs:BAAANQABCgQIBAAAAA==.',
Cl='Clairë:BAAANQAECggIDwAAAA==.Claude:BAAANQADCgQIBQAAAA==.Clbalena:BAAANQADCgEIAgAAAA==.Clio:BAAANQAECgQIEwAAAA==.',
Co='Cockcroft:BAAANQADCgYIDAABNQAECgkJIQAaANIOAA==.Coionir:BAAANQAECgYIEwAAAA==.Coiovoker:BAAANQADCgEIAQABNQAECgYIEwADAAAAAA==.Coldblooded:BAAANQADCgcIBwABNQAECgQIBAADAAAAAA==.Comunistaa:BAABNQAECoEpAAINAAkKSiRuBgCsAwANAAkKSiRuBgCsAwAAAA==.Corruptionz:BAAANQAECgQIDAAAAA==.Corstine:BAAANQAECgYICgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.Couldovisk:BAAANQADCgIJAgAAAA==.',
Cr='Crawsing:BAAANQADCgEIAQAAAA==.Cronosxdm:BAAANQAFFAEJAQAAAA==.Crucyatus:BAABNQAECoEYAAMTAAkKuRe7UgB0AgATAAkKJhe7UgB0AgAFAAEKoR/aVABdAAAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
Cy='Cyrande:BAAANQAECgIIAgABNQAECgIIAwADAAAAAA==.',
['Cá']='Cássia:BAAANQADCggICAAAAA==.',
['Cå']='Cåssio:BAAANQAECgYIDwAAAA==.',
['Cÿ']='Cÿgnus:BAAANQAECggIEgABNQAECgkJKwAHAFglAA==.',
Da='Dadashi:BAAANQADCggICAAAAA==.Dago:BAAANQAECgEIAQAAAA==.Danadinn:BAAANQADCgcIBwAAAA==.Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAABNQAECoEiAAMcAAkKuRGGEAB4AQAVAAkK/xCMbgAnAgAcAAcKOw6GEAB4AQAAAA==.Darklendio:BAAANQADCgUICgAAAA==.Daroncosp:BAAANQADCgIJAgAAAA==.Darü:BAAANQAECgQIBQAAAA==.Dashuman:BAABNQAECoEdAAIQAAgKvR2DKACuAgAQAAgKvR2DKACuAgAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dayshine:BAAANQADCgUIBQAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadguth:BAAANQAECggJBwAAAA==.Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUICAABNQAECgcIFQAGAIsMAA==.Deceive:BAAANQAECgcIDwAAAA==.Defroque:BAAANQAECgUIBQAAAA==.Deimons:BAAANQADCgQIBAAAAA==.Deis:BAAANQADCgUIBAAAAA==.Delarÿn:BAAANQAECgQIBAAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Demzumilde:BAAANQAECgMIBAAAAA==.Denevy:BAABNQAECoEkAAIdAAgKzw8iFQCoAQAdAAgKzw8iFQCoAQAAAA==.Deraelda:BAAANQADCgMIBAAAAA==.Derbster:BAAANQAECgcICwAAAA==.Destructiom:BAABNQAECoEgAAILAAcKuB8LSABuAgALAAcKuB8LSABuAgAAAA==.',
Dh='Dhamburguer:BAABNQAECoEcAAIGAAgKEx2VFQCfAgAGAAgKEx2VFQCfAgAAAA==.Dhanadrai:BAABNQAECoEVAAMeAAYKOwhqcwADAQAeAAYKOwhqcwADAQAEAAEKTQJ73wAiAAAAAA==.',
Di='Diamalboy:BAAANQADCggICAAAAA==.Diamath:BAAANQADCgUJBQAAAA==.Diggop:BAAANQAECgIIAwAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQADAAAAAA==.Dima:BAABNQAECoEhAAIKAAkKJiHeBwBzAwAKAAkKJiHeBwBzAwAAAA==.',
Dk='Dktt:BAAANQAECgEIAwAAAA==.',
Do='Dornaa:BAAANQAECgUICgAAAA==.Dosmagos:BAAANQABCgUIBwAAAA==.Doulce:BAAANQAECgUIDQAAAA==.',
Dr='Dracarysz:BAAANQAECgIIAgAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Dragonbaby:BAAANQADCgUIBQAAAA==.Drainetty:BAAANQAECgEIAQAAAA==.Dranacs:BAAANQAECggIEwAAAA==.Dreampollys:BAAANQAECgEIAQABNQAFFAIIAgADAAAAAA==.Dreamremix:BAAANQAFFAIIAgAAAA==.Dreyol:BAAANQAECgIIAgAAAA==.Drts:BAABNQAECoErAAICAAkKOx9FOwADAwACAAkKOx9FOwADAwAAAA==.Drunkiechan:BAAANQAECgEIAQAAAA==.',
Du='Dudupokas:BAAANQAECgQIBAAAAA==.Dumar:BAAANQAECgYICgAAAA==.Duromargh:BAAANQADCgMIAwAAAA==.',
Ed='Eduarthas:BAAANQAECgYIDAAAAA==.Edyra:BAAANQADCggICAAAAA==.',
Eg='Egoist:BAAANQADCggJDwAAAA==.',
El='Elementys:BAAANQAECgQICAAAAA==.Elemëntum:BAAANQAECgEIAQAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECgkJOQALAEQkAA==.Elinaara:BAABNQAECoEbAAIFAAcKig4CKQBpAQAFAAcKig4CKQBpAQAAAA==.Elizabeth:BAAANQAECgMIAwAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Ellithyx:BAAANQAECgQIBgAAAA==.Elmagoprior:BAAANQAECgQICQAAAA==.Elricky:BAAANQAECgEIAQAAAA==.Eluna:BAAANQAECgYICgAAAA==.Eluric:BAAANQAECgcICgABNQAECgkJOQALAEQkAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.Entropye:BAAANQADCgYICwAAAA==.',
Er='Ercshadow:BAAANQAECgQIBgAAAA==.Ermooke:BAAANQAECgQIBgAAAA==.',
Es='Escanorzão:BAAANQADCgcJDAABNQAECgMIAwADAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Executepowa:BAAANQADCggICAAAAA==.Exo:BAABNQAECoEhAAILAAgKsh63KwDKAgALAAgKsh63KwDKAgAAAA==.Exorciseur:BAACNQAFFIEIAAIHAAUKsho3BgC5AQAHAAUKsho3BgC5AQA1AAQKgTAAAgcACQqJI/kGAHoDAAcACQqJI/kGAHoDAAAA.',
Fa='Fabercästell:BAAANQAECgcICgAAAA==.Fabers:BAAANQAECgMIAwAAAA==.Fargunn:BAAANQAECgYIEwAAAA==.',
Fe='Feanori:BAABNQAECoEeAAIHAAgKChbzLgAAAgAHAAgKChbzLgAAAgAAAA==.Feanør:BAAANQAECgYIEwAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgkJGAAGAPgfAA==.Fennris:BAAANQAECgEIAwAAAA==.Feyrin:BAAANQADCggIHQAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBwABNQAECgEIAQADAAAAAA==.Flodfelblood:BAAANQAECgEIAQAAAA==.',
['Fí']='Fíli:BAAANQAECgEIAQAAAA==.',
['Fï']='Fïrestorm:BAAANQADCgYIBgAAAA==.',
Ga='Gabela:BAAANQAECgIIAwAAAA==.Gabrael:BAAANQABCgQJBAAAAA==.Gaiataur:BAAANQADCgUIBgAAAA==.Galandiel:BAAANQADCggIDgAAAA==.Galinni:BAAANQADCggICgAAAA==.Gallon:BAABNQAECoEaAAIfAAcKnBlaFAAKAgAfAAcKnBlaFAAKAgAAAA==.Garcs:BAAANQADCgQIBAAAAA==.Garfall:BAAANQAECgYIEQAAAA==.',
Gl='Glacyale:BAAANQAECgYIDAAAAA==.Glisa:BAABNQAECoEaAAQTAAkKbBgVbQApAgATAAkKtxIVbQApAgAFAAcKMxmRIAC0AQAQAAEKagRECwEvAAAAAA==.Glorfindel:BAAANQAECgIIAwAAAA==.',
Gn='Gnomepink:BAAANQADCggIHAAAAA==.',
Go='Godadrian:BAABNQAECoEcAAMTAAgKwg2WnACyAQATAAgKwg2WnACyAQAFAAEKGgW1cQAdAAAAAA==.Gordãobtm:BAAANQAECgYIDwAAAA==.Gosu:BAABNQAECoEgAAIaAAgK3hx5EwCbAgAaAAgK3hx5EwCbAgAAAA==.',
Gr='Gralfor:BAAANQAECgUIBQAAAA==.Grekorio:BAAANQAECgMIBgAAAA==.Greylord:BAAANQAECgIIAgABNQAECggIGwAYAOcXAA==.Greylorddrak:BAABNQAECoEbAAIYAAgK5xc7FABYAgAYAAgK5xc7FABYAgAAAA==.Greylordp:BAAANQAECgEIAQABNQAECggIGwAYAOcXAA==.Gromitak:BAAANQADCgUIBgAAAA==.Gronak:BAAANQAECgQJBAAAAA==.',
Gu='Guhtz:BAAANQADCgMIAwAAAA==.Guillyn:BAAANQAECgcICwAAAA==.Gultai:BAAANQAECgUICQAAAA==.Gults:BAAANQADCgQIBAAAAA==.Gultsz:BAAANQADCgUIBwAAAA==.Gunpowter:BAAANQABCgIIAwAAAA==.Guxrock:BAAANQAECgIIBAAAAA==.',
Gw='Gwts:BAAANQAECgIIAgABNQAECggIIgAIAA0fAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYJBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hafo:BAAANQADCgYJDQAAAA==.Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQAECgQIBgAAAA==.Hamiister:BAAANQADCgQIBAAAAA==.Hancalimon:BAABNQAECoEZAAIOAAUKUBr4UgBjAQAOAAUKUBr4UgBjAQAAAA==.Haokö:BAAANQAECgEIAQAAAA==.Hasanzi:BAAANQADCgUIBQAAAA==.Hastterix:BAAANQAECgUIEAAAAA==.Hatezon:BAAANQAECgMIBQAAAA==.',
He='Heavyking:BAAANQAECgYIEAAAAA==.Heishoo:BAAANQADCgIIAgAAAA==.Helitox:BAAANQAECgQIBwAAAA==.Hellhoundish:BAAANQADCgYIBgABNQAFFAQIBwAVAFkQAA==.Hellreaper:BAABNQAECoEiAAIgAAkKQwsUbwDqAQAgAAkKQwsUbwDqAQAAAA==.Heloisaa:BAABNQAECoEbAAIdAAgKqhAOFAC4AQAdAAgKqhAOFAC4AQAAAA==.Helwen:BAAANQAECgEIAQAAAA==.Hemm:BAAANQADCgYIBgAAAA==.Heracranosd:BAAANQAECgQIBQAAAA==.Heracranosx:BAAANQAECgYIDQAAAA==.Herdy:BAAANQADCgMJBAAAAA==.Herta:BAAANQAECgMIBgAAAA==.Hess:BAAANQAECgQIDQAAAA==.',
Hi='Hireque:BAABNQAECoEXAAILAAgKiheXTgBbAgALAAgKiheXTgBbAgAAAA==.Hitkilled:BAAANQAECgYIDwAAAA==.Hitkins:BAAANQAECgEIAQAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgUIEAAAAA==.Holycel:BAAANQAECgMIBAABNQAECgkJHQAEAF4gAA==.Holyscrim:BAAANQAECgEIAQAAAA==.Hoolylight:BAAANQAECgEIAQAAAA==.',
Hu='Huelandita:BAAANQAECgcICQAAAA==.Hunterpica:BAABNQAECoEfAAILAAgKnR7JMgCxAgALAAgKnR7JMgCxAgAAAA==.Huntmon:BAAANQAECgYIEwAAAA==.Huriah:BAAANQAECgIIAgAAAA==.Huskat:BAAANQAECgYIDAAAAA==.',
Hy='Hysillens:BAAANQAECgUICwAAAA==.',
['Hã']='Hãn:BAAANQADCgEIAQAAAA==.',
['Hä']='Härü:BAAANQADCgUIAwAAAA==.',
Ic='Icebïg:BAAANQAECgEIAQAAAA==.',
Ig='Igno:BAAANQAECgUIDgABNQAECgkJLQANAGIlAA==.Igubigu:BAAANQADCgQIBAAAAA==.',
Il='Ilane:BAAANQABCggIDAAAAA==.Illidatrix:BAABNQAECoEVAAIGAAcKiwwsMACdAQAGAAcKiwwsMACdAQAAAA==.Illïndão:BAAANQADCggICAAAAA==.Ilovealtgirl:BAAANQADCggJFAAAAA==.',
In='Inladris:BAAANQADCgcIBwAAAA==.Inot:BAABNQAECoEYAAIUAAgKIBM9XADdAQAUAAgKIBM9XADdAQAAAA==.',
Ir='Irmãsafada:BAAANQADCgMIAwAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQAECgUICgAAAA==.',
It='Italodpz:BAAANQAECgUIBQABNQAECggIGAAeABIUAA==.Itsälasca:BAAANQAECgEIAQAAAA==.',
Iu='Iuri:BAAANQAECgcIDgAAAA==.',
Ix='Ixlzvaxtylxl:BAAANQADCgYIBgAAAA==.',
Iz='Izanna:BAAANQADCgcJCwAAAA==.',
Ja='Jalinrabeidh:BAAANQAECgEIAQAAAA==.Jampack:BAABNQAECoEgAAMKAAkKZiJUEgAeAwAKAAkKZiJUEgAeAwANAAEKugmzHAEvAAAAAA==.',
Je='Jeevas:BAABNQAECoEbAAIQAAgKgB4yJgC5AgAQAAgKgB4yJgC5AgAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeguinha:BAAANQABCggIDgAAAA==.Jeu:BAAANQADCgcICQAAAA==.Jeyla:BAAANQADCgEIAQAAAA==.',
Jh='Jhasperr:BAAANQADCggIIAAAAA==.',
Jo='Jocabiroca:BAABNQAECoEhAAMCAAgKXBqofwBnAgACAAgKXBqofwBnAgAWAAEKlwIMDQAqAAAAAA==.Johnez:BAAANQADCgcIBwAAAA==.Joral:BAAANQABCggICwAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAABNQAECoEeAAIXAAgKxxCIJwDuAQAXAAgKxxCIJwDuAQAAAA==.',
Jr='Jrxamã:BAABNQAECoETAAINAAUKkRxCbgClAQANAAUKkRxCbgClAQAAAA==.',
Ju='Juliia:BAAANQAECgQICQAAAA==.Jusgu:BAAANQAECgYICQABNQAECggIDgADAAAAAA==.',
['Jö']='Jönah:BAAANQADCgMIAwAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaiev:BAAANQADCgYICgAAAA==.Kaju:BAABNQAECoEYAAIRAAkKOyGlAwDkAgARAAkKOyGlAwDkAgAAAA==.Kalinis:BAAANQAECgEJAQAAAA==.Kalliiope:BAABNQAECoEdAAMRAAcKcwgVGAASAQARAAcKcAgVGAASAQACAAUKFANFVgHdAAAAAA==.Kamesenin:BAAANQADCgUIBQAAAA==.Kamïlla:BAAANQAECgUIEAAAAA==.Karak:BAAANQADCgIJAgAAAA==.Karamatsu:BAAANQAECgIIAgAAAA==.Karollus:BAAANQABCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCggIDAAAAA==.Katona:BAABNQAECoEXAAIRAAgKthW7CAAgAgARAAgKthW7CAAgAgAAAA==.Kauss:BAAANQAECgUIBQAAAA==.',
Kd='Kdposa:BAAANQABCgQIBAAAAA==.',
Ke='Keior:BAAANQAECgEIAQAAAA==.Kenai:BAAANQAECgcIEwAAAA==.Kewenz:BAABNQAECoEvAAILAAkK2SY9AAAQBAALAAkK2SY9AAAQBAABNQAFFAMIBQALAO8fAA==.Keylaa:BAAANQAECgYIEAAAAA==.',
Kh='Khasin:BAAANQAECgYIEwAAAA==.',
Ki='Kierke:BAAANQAECgUICQABNQAECgYIEQADAAAAAA==.Kimyx:BAAANQAECgUIBQABNQAFFAMIBQALAO8fAA==.Kindz:BAAANQADCgUIBgABNQAFFAMIBQALAO8fAA==.Kiregeth:BAAANQAECgYIDAAAAA==.Kitrel:BAAANQAECgMIAwAAAA==.',
Kl='Kleiio:BAAANQAECgEIAQAAAA==.Kllauzz:BAAANQAECgYIEAABNQAECggIHwATAMoMAA==.Kllauzzmage:BAAANQAECgIIAgABNQAECggIHwATAMoMAA==.Kllauzzpalla:BAABNQAECoEfAAITAAgKygyxmQC5AQATAAgKygyxmQC5AQAAAA==.',
Kn='Knufolgado:BAAANQADCgYIBgAAAA==.',
Ko='Kolyn:BAABNQAECoE5AAILAAkKRCQwCgB7AwALAAkKRCQwCgB7AwAAAA==.Komamurasou:BAAANQAECgQIBAAAAA==.',
Kr='Krastian:BAAANQAECgQIDwAAAA==.Kreegh:BAAANQAECgEIAQAAAA==.Krikixus:BAAANQADCgYIBgAAAA==.Krupper:BAAANQAECgMIAwABNQAECgYIDAADAAAAAA==.Krynesa:BAAANQADCggICwAAAA==.',
Ku='Kuhaku:BAAANQADCgQIBAAAAA==.Kukuatzo:BAAANQAECgQICQAAAA==.',
Ky='Kyary:BAAANQAECgQICAABNQAECggIKAAcAI4dAA==.Kyndin:BAAANQADCgEIAQABNQAFFAMIBQALAO8fAA==.',
['Kä']='Kälini:BAAANQADCgcIDAABNQAECgQIBAADAAAAAA==.Käyros:BAAANQADCgUJCgAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAAANQAECgYIDgAAAA==.Köri:BAABNQAECoEeAAMCAAkKZR70RQDpAgACAAkKEx70RQDpAgARAAEKMx0eNwBIAAAAAA==.',
La='Lakaioo:BAABNQAECoEeAAMVAAcKQwrIsgBvAQAVAAcKQwrIsgBvAQAdAAIK2gWlNwBCAAAAAA==.Lamont:BAABNQAECoEeAAIQAAcKJQ9tcQCcAQAQAAcKJQ9tcQCcAQAAAA==.Lampiião:BAABNQAECoEkAAILAAcKgBlGZwAaAgALAAcKgBlGZwAaAgAAAA==.Lanllaniel:BAAANQAECgcICwAAAA==.Largartixa:BAAANQADCgQJBAABNQAECgQJBAADAAAAAA==.Larslion:BAAANQABCgYJBgAAAA==.',
Le='Lebelisco:BAABNQAECoEWAAILAAgKmBlGQACFAgALAAgKmBlGQACFAgAAAA==.Leehyori:BAAANQAECgQICQAAAA==.Legëndaria:BAAANQAECgEIAQAAAA==.Lennorien:BAABNQAECoEhAAISAAcKTRlNDQAXAgASAAcKTRlNDQAXAgAAAA==.Lestard:BAAANQADCgUIBAAAAA==.Leturey:BAAANQADCgMIAwAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Lifestrream:BAABNQAECoEZAAMPAAgKwRDuGwB9AQAPAAgK5gzuGwB9AQAbAAYKyAwlFwBPAQABNQAECgkJIgAPACQYAA==.Liftshertail:BAABNQAECoEpAAQYAAkKvButCQD6AgAYAAkKvButCQD6AgAhAAUKBxG6IgASAQAZAAIKxQwWHABcAAAAAA==.Ligiaf:BAAANQAECgUIDAAAAA==.Liilum:BAAANQAECgMIAwAAAA==.Limeware:BAAANQADCgYICAAAAA==.Linë:BAAANQADCggJHwABNQAECgQIBAADAAAAAA==.Linëa:BAAANQADCgIJBQAAAA==.Linüss:BAAANQAECgEIAQAAAA==.Lionarot:BAAANQAECgQIDAAAAA==.Littleshelby:BAAANQADCgYJDwAAAA==.',
Lo='Lobinox:BAAANQADCggICgAAAA==.Lolzhe:BAAANQAECgYIBwABNQAECggIKAAfAFcaAA==.Longaim:BAABNQAECoEWAAILAAcK8BAhfwDgAQALAAcK8BAhfwDgAQAAAA==.Lorthaeron:BAABNQAECoEVAAIMAAgKkxEKNADQAQAMAAgKkxEKNADQAQAAAA==.Losdor:BAAANQAECgUIBQAAAA==.Lostminder:BAAANQAECgMIAwAAAA==.Lothbrok:BAABNQAECoEaAAILAAgKURHdggDXAQALAAgKURHdggDXAQAAAA==.',
Lu='Lucanor:BAAANQADCgUIBQAAAA==.Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAACNQAFFIEWAAIVAAYKvxhTCAACAgAVAAYKvxhTCAACAgA1AAQKgSQAAxUACQqTIt0lABEDABUACQr4Id0lABEDABwAAQrQIS8nAFMAAAAA.Lukanelas:BAAANQADCgcJDQAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luna:BAABNQAECoEbAAMUAAkK9huvGwDsAgAUAAkKkxqvGwDsAgAiAAQK/ROeEQD3AAAAAA==.Lunes:BAABNQAECoEoAAIKAAkK2RzfGgDoAgAKAAkK2RzfGgDoAgAAAA==.Luster:BAAANQADCggIDwAAAA==.Lusther:BAAANQAECgcIDAAAAA==.Luzdacelesc:BAACNQAFFIEGAAIBAAMKfSMzCQA5AQABAAMKfSMzCQA5AQA1AAQKgT4AAwEACQpiJm4AAPYDAAEACQpiJm4AAPYDABQAAgp4DfzIAIUAAAAA.',
Ly='Lyaah:BAAANQADCggIEQAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYICwABNQAECggIKAAfAFcaAA==.',
['Lø']='Lølzhê:BAABNQAECoEoAAIfAAgKVxrxEQAyAgAfAAgKVxrxEQAyAgAAAA==.Løvizinha:BAAANQAECgQIBQAAAA==.',
['Lú']='Lúaprata:BAAANQAECgQIBAAAAA==.',
Ma='Maagnuss:BAAANQADCgIIAgAAAA==.Madbuddha:BAAANQADCgQJBAAAAA==.Mageli:BAAANQAECgYIDQAAAA==.Magodanilo:BAAANQAECgIIAgAAAA==.Magodavida:BAAANQAECgQIEQAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maguinax:BAAANQAECgEIAwABNQAFFAMIBgAEAKwPAA==.Maheena:BAAANQAECgYIDQAAAA==.Mai:BAABNQAECoEWAAMWAAcKEg4gAwC0AQAWAAcKEg4gAwC0AQACAAQKSQaXYwHHAAAAAA==.Mairon:BAAANQADCgcICQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAABNQAECoEcAAIeAAgKRw5lUgCJAQAeAAgKRw5lUgCJAQAAAA==.Malborion:BAAANQAECgUIEAAAAA==.Malevolent:BAAANQAECgcIDAAAAA==.Malignõ:BAABNQAECoEtAAINAAkKYiUDBgCwAwANAAkKYiUDBgCwAwAAAA==.Maltozo:BAABNQAECoEYAAIMAAgKOgy5QQB6AQAMAAgKOgy5QQB6AQAAAA==.Mandrakson:BAABNQAECoEbAAIMAAgKzwxCOwChAQAMAAgKzwxCOwChAQAAAA==.Mandubim:BAAANQADCgEIAQAAAA==.Mariiamil:BAAANQAECgUICwAAAA==.Marvelos:BAAANQABCggJCgAAAA==.Marvvila:BAABNQAECoEbAAILAAgK8xZ8TgBcAgALAAgK8xZ8TgBcAgAAAA==.Marycristiny:BAABNQAECoEbAAMSAAkKchkKBgCnAgASAAgKvxsKBgCnAgAgAAEKDgcYLQEsAAAAAA==.Mauwolf:BAAANQAECgQIBQAAAA==.Mazaky:BAAANQAECgYIEwAAAA==.',
Me='Medivi:BAAANQADCgMIAwAAAA==.Megumi:BAAANQAECgMIAwAAAA==.Meisterz:BAAANQADCgQIBAABNQAECggIIgAIAA0fAA==.Memphis:BAAANQADCgcIBwAAAA==.Menorxidil:BAABNQAECoElAAIfAAkKLxoGDQCQAgAfAAkKLxoGDQCQAgAAAA==.Mestredoido:BAAANQAECgQIBQAAAA==.Mestreløck:BAAANQADCgMIBwAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.',
Mh='Mhenb:BAAANQAECgcIEQAAAA==.Mhorgothh:BAAANQADCgQIBAAAAA==.',
Mi='Micherouc:BAAANQADCggIDgAAAA==.Midnights:BAAANQADCgUIBQAAAA==.Mikal:BAAANQAECgUIDwAAAA==.Minort:BAAANQAECgUIDAAAAA==.Minör:BAAANQAECgQIBwAAAA==.Missmarvel:BAAANQABCgYICgAAAA==.Mistogunn:BAAANQAECgIIBQAAAA==.Mithrael:BAAANQADCgUIBQAAAA==.Mizukagesou:BAAANQAECgQICwAAAA==.',
Mo='Monkbest:BAAANQADCggIEwAAAA==.Montedruids:BAAANQADCgEIAQAAAA==.Montej:BAAANQAECgMIBAAAAA==.Montäna:BAAANQABCgMIAwAAAA==.Mooncap:BAAANQAECgcIEwAAAA==.Moondragoon:BAAANQADCgcICQAAAA==.Morakhir:BAAANQADCgQIBAABNQAECgYIFQAFAH8KAA==.Moranguinhö:BAAANQADCgEJAQAAAA==.Mordiidinha:BAAANQAECgQIBwABNQAECgkJLQANAGIlAA==.Morganviolet:BAAANQAECgUIEgAAAA==.',
Mu='Mugidinhaa:BAAANQABCgcIBQAAAA==.Murdoky:BAAANQADCgEIAQABNQAECgMIBAADAAAAAA==.Musleira:BAAANQAECgUIDgAAAA==.',
My='Myranor:BAAANQAECgEIAgAAAA==.Myrzin:BAAANQADCggIDAAAAA==.Mythariel:BAAANQAECgQIBgAAAA==.Mythcut:BAAANQAECgQIDAAAAA==.Mythjegue:BAAANQAECgEIAQAAAA==.Myø:BAAANQAECgYIBgABNQAFFAMIBQALAIYTAA==.',
['Mä']='Mällü:BAAANQAECgYIDwAAAA==.Mälthazar:BAABNQAECoEiAAMFAAkKOB8HCgDdAgAFAAgKySAHCgDdAgATAAEKshLZbAE4AAAAAA==.Määt:BAAANQADCggICAABNQAFFAUIEgASALYYAA==.',
['Må']='Mågus:BAABNQAECoEdAAIRAAcKVhopCQATAgARAAcKVhopCQATAgAAAA==.',
['Mò']='Mòrgan:BAAANQAECgEIAQAAAA==.',
['Mø']='Mørgåna:BAAANQAECgYIEQAAAA==.',
Na='Naamt:BAAANQADCgYIBgAAAA==.Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQADCgYICgABNQAECgMIBAADAAAAAA==.Nagashina:BAAANQADCggIFgAAAA==.Naizow:BAAANQAECgYIDwAAAA==.Namisan:BAAANQAECgIIAwAAAA==.Namuhß:BAAANQAECgQIDgABNQAECgcIEgADAAAAAA==.Namøøh:BAAANQAECgcIEgAAAA==.Naomiy:BAAANQADCgYIEAAAAA==.Naoto:BAAANQAECgQIDQAAAA==.Napru:BAAANQADCgEIAQAAAA==.Nardalan:BAAANQADCgQJBAABNQAECgUICgADAAAAAA==.Narjes:BAAANQAECgYICQAAAA==.Nathrezim:BAAANQADCgcIEAAAAA==.',
Ne='Necrogélido:BAAANQADCgYIEQAAAA==.Nefariio:BAAANQADCgQIBAAAAA==.Neninhaa:BAAANQADCgcJBQAAAA==.Neopaladino:BAAANQAECgQICQAAAA==.Nerlock:BAAANQAECgUIDAAAAA==.',
Ni='Nicom:BAAANQADCgYIBgAAAA==.Nightforms:BAAANQADCggIEAAAAA==.Nikity:BAABNQAECoEfAAIHAAgK0RpqIQBpAgAHAAgK0RpqIQBpAgAAAA==.',
No='Noahwallker:BAAANQADCgYIBgAAAA==.Noazard:BAAANQAECgQICAAAAA==.Nopainnogain:BAAANQAECgEIAQAAAA==.Normalin:BAAANQADCgEIAQAAAA==.Nortênho:BAABNQAECoEeAAIOAAgKrx8qHADNAgAOAAgKrx8qHADNAgAAAA==.Nosferüs:BAAANQAECgQIBwAAAA==.Nossilat:BAABNQAECoErAAIHAAkKWCUoAwC4AwAHAAkKWCUoAwC4AwAAAA==.',
Nu='Nuit:BAAANQAECgIIBwAAAA==.Nunhöly:BAAANQAECgYIDQAAAA==.',
Ny='Nysthiael:BAABNQAECoEmAAMgAAgKexVMWAAsAgAgAAgKexVMWAAsAgAjAAEKuwXuLgAsAAAAAA==.Nyxicel:BAAANQAECgUICgABNQAECgkJHQAEAF4gAA==.',
['Nã']='Nãoseicurar:BAAANQAECgIIAgAAAA==.',
['Nä']='Närem:BAAANQAECggIAQAAAA==.Nästÿ:BAAANQAECgEIAQAAAA==.',
['Nö']='Nöturnö:BAAANQABCgYICgAAAA==.',
['Ný']='Nýmm:BAAANQAECgUIEAAAAA==.',
Oc='Ocon:BAAANQABCgIIBAAAAA==.',
Od='Odigo:BAAANQADCgIIAgAAAA==.Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCggIJgAAAA==.',
Ol='Oldcook:BAAANQABCgYIBQAAAA==.Oliele:BAAANQAECgUICwAAAA==.',
On='Onixpala:BAAANQAECgQIBwABNQAECgUIDgADAAAAAA==.Onlydruix:BAAANQADCgIIAgAAAA==.',
Oo='Oorun:BAAANQADCgcIBwAAAA==.',
Op='Opsdesculpa:BAABNQAECoEbAAMkAAcKpBbELgDyAQAkAAcKpBbELgDyAQAlAAEKEBFPSQA9AAAAAA==.',
Or='Organ:BAAANQAECgQIBQAAAA==.Orinoldo:BAABNQAECoEkAAICAAkKECAZNAAWAwACAAkKECAZNAAWAwAAAA==.',
Os='Osiria:BAAANQABCgYICAAAAA==.',
Ot='Otacki:BAAANQADCgIIAgAAAA==.Otherside:BAAANQAECgYICwABNQAECgkJMAASAEoaAA==.Otávio:BAAANQAECgQIBwAAAA==.',
Ow='Owlcapøne:BAAANQAECgUIBQAAAA==.',
Ox='Oxentedragon:BAAANQADCgUIBAAAAA==.',
Oz='Ozyi:BAAANQAECgUIEQAAAA==.',
Pa='Pachiinko:BAAANQAECgYJAgAAAA==.Pain:BAAANQADCgQIBAAAAA==.Painkke:BAAANQAECggIEAAAAA==.Pajeh:BAAANQADCgQIBAAAAA==.Palluz:BAAANQAECgUICAABNQAFFAIIBgALAMUSAA==.Palyz:BAAANQADCggIDQAAAA==.Pandaphorte:BAAANQADCgIIAgABNQAECgIIBAADAAAAAA==.Panicdeath:BAAANQAECgEIAQAAAA==.Parafinaisis:BAAANQAECgUIEAAAAA==.Parafinared:BAAANQAECgQIBAAAAA==.Parrot:BAAANQADCgEIAQAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.',
Pe='Pedrosolock:BAAANQADCgYIBgAAAA==.Peltrow:BAAANQAFFAEIAQAAAA==.Penndrive:BAAANQAECgMIAwAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgYIDAADAAAAAA==.Pesaa:BAABNQAECoEhAAIVAAgKDSCKNgDSAgAVAAgKDSCKNgDSAgAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Phesti:BAAANQABCgEIAQAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Picklerick:BAAANQAECgIIAQAAAA==.Pirizin:BAABNQAECoEvAAITAAkKwxvvRQCdAgATAAkKwxvvRQCdAgAAAA==.',
Po='Popopeka:BAAANQADCgcIBwAAAA==.Porcaleta:BAABNQAECoEZAAIBAAcKURMDKgCvAQABAAcKURMDKgCvAQAAAA==.Portal:BAAANQAECgUJCgABNQAECgYIBgADAAAAAA==.Portelamage:BAABNQAECoEoAAICAAkK4B8fQAD3AgACAAkK4B8fQAD3AgAAAA==.Portheus:BAAANQADCggIFwAAAA==.',
Pr='Praeglacius:BAABNQAECoEnAAMNAAgKxxDwVwDuAQANAAgKxxDwVwDuAQAKAAIK/AB2BQExAAAAAA==.Pravuls:BAAANQADCgcIDgAAAA==.Priapista:BAAANQAECgQIBQAAAA==.Priyla:BAAANQABCgcICgAAAA==.Prosaic:BAAANQADCggICAABNQADCggJDwADAAAAAA==.Pråhå:BAAANQAECgQICQABNQAECgcIEgADAAAAAA==.',
Ps='Psicopanda:BAAANQAECgcIEAAAAA==.Psychiclink:BAAANQAFFAIIAgABNQAFFAMIBgABAH0jAA==.',
Pu='Puffys:BAAANQAECgEIAQABNQAECgUIBQADAAAAAA==.',
Pw='Pwcca:BAAANQAECgEJAQAAAA==.',
['Pó']='Pórthosrox:BAAANQAECgEIAgAAAA==.',
['Pú']='Púh:BAAANQADCgQIBAABNQAECggIIgAIAA0fAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAABNQAECoEfAAIcAAgKQx7oBAC2AgAcAAgKQx7oBAC2AgAAAA==.Raewyn:BAABNQAECoEbAAIMAAkKuRxoEwDRAgAMAAkKuRxoEwDRAgAAAA==.Rafaelgame:BAAANQAECgQICAAAAA==.Ragdead:BAACNQAFFIEHAAIeAAIKoA18HgB1AAAeAAIKoA18HgB1AAA1AAQKgSIAAh4ACQqDG9IsAEcCAB4ACQqDG9IsAEcCAAE1AAUUBAgIACYATgYA.Ragdöll:BAAANQAECgQIBAAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAFFAQICAAmAE4GAA==.Ragosan:BAABNQAFFIEIAAImAAQKTgaiBwB+AAAmAAQKTgaiBwB+AAAAAA==.Rairone:BAABNQAECoEVAAInAAcKMBB/BwDNAQAnAAcKMBB/BwDNAQAAAA==.Raparigaloka:BAAANQAECgUIDwAAAA==.Rapunxel:BAABNQAECoEwAAMSAAkKShryAwDnAgASAAkKShryAwDnAgAgAAUKZAj4zgD+AAAAAA==.Rarkion:BAABNQAECoEcAAMhAAgKQx1mCQDEAgAhAAgKQx1mCQDEAgAYAAIKShyTOgClAAAAAA==.Raulthalas:BAAANQADCgYIBgAAAA==.Rawrii:BAAANQADCgUIBQAAAA==.Raynmake:BAAANQAECgEIAQABNQAECgcIBwADAAAAAA==.',
Rb='Rbchama:BAABNQAECoEXAAMNAAUKIwU9wQDhAAANAAUKIwU9wQDhAAAKAAEKTwA2HgEVAAAAAA==.',
Re='Rebelk:BAAANQADCgYIBgAAAA==.Redvil:BAAANQADCgUJBwAAAA==.Revoltedhunt:BAAANQAECggICgABNQAFFAcIGQAXAE8VAA==.Revolthed:BAACNQAFFIEZAAMXAAcKTxVhBQDjAQAXAAYKBxhhBQDjAQALAAQK1AfaDwAcAQA1AAQKgSoAAxcACQrAImMKACADABcACQqkImMKACADAAsABQqVGk6cAJwBAAAA.',
Rh='Rhaadora:BAAANQAECgQIBAAAAA==.Rhoghar:BAABNQAECoEcAAMHAAkKyxqNGgCiAgAHAAkKyxqNGgCiAgAoAAUKUhfKEwA9AQAAAA==.Rhoghardruid:BAAANQAECgUIBgABNQAECgkJHAAHAMsaAA==.',
Ri='Riachu:BAAANQADCgcIBwAAAA==.Riluyu:BAAANQAECgUIBQAAAA==.Rimetail:BAAANQABCgQIBAAAAA==.',
Ro='Rokalf:BAABNQAECoEdAAIdAAgKjxHBEwC8AQAdAAgKjxHBEwC8AQAAAA==.Rossiten:BAAANQAECgUIEQAAAA==.Roverandom:BAAANQADCgEIAQAAAA==.Roöf:BAAANQAECgUIEQAAAA==.',
Ru='Rubya:BAAANQAECgEJAQABNQAECgcIEQADAAAAAA==.Runavento:BAAANQADCgIIAgAAAA==.Ruélatórta:BAAANQAECgQICAAAAA==.',
['Rä']='Räidela:BAABNQAECoEsAAMgAAgKOR98KADKAgAgAAgKOR98KADKAgASAAEK2hJGbgA7AAAAAA==.',
Sa='Sagman:BAAANQABCgIIAgAAAA==.Sagädegemeos:BAABNQAECoEWAAITAAYKrxq0jQDWAQATAAYKrxq0jQDWAQABNQAECggIHAALALMfAA==.Salasär:BAABNQAECoEeAAIVAAcKxB3uYABNAgAVAAcKxB3uYABNAgABNQAECgcIIAALALgfAA==.Saleyi:BAAANQAECgQICQAAAA==.Saluton:BAAANQAECgEIAgAAAA==.Samidemon:BAAANQAECgQIBwAAAA==.Sarashi:BAAANQADCgUJDAAAAA==.Sarte:BAAANQAECgEIAgAAAA==.Sarzlok:BAAANQAECgQIBQAAAA==.',
Sc='Schaeppi:BAAANQAECgEIAQAAAA==.Schiabelle:BAAANQADCgYIDAAAAA==.Schiabellee:BAAANQADCggJEQAAAA==.Scoobydruida:BAABNQAECoEWAAIOAAgKixAZPQDjAQAOAAgKixAZPQDjAQAAAA==.Screan:BAABNQAECoEgAAIBAAkK3ROQGgBTAgABAAkK3ROQGgBTAgAAAA==.Scrøøge:BAAANQAECgQICgAAAA==.',
Se='Sealgaire:BAAANQADCgYICAAAAA==.Seelyvorey:BAABNQAECoEqAAQMAAgKryNDEwDTAgAMAAgKWiJDEwDTAgAEAAYKkSB5NQAvAgAeAAUKFxYJZgA3AQAAAA==.Selph:BAAANQAECggIEgAAAA==.Sengos:BAAANQAECgQIBQAAAA==.Sephhiroth:BAAANQADCgcICgAAAA==.Serrase:BAABNQAECoEfAAICAAgK5xjwfQBqAgACAAgK5xjwfQBqAgAAAA==.',
Sh='Shaado:BAAANQAECgIIAgAAAA==.Shagy:BAAANQADCggICAAAAA==.Shalivane:BAAANQAECggIDQAAAA==.Shalquoir:BAAANQAECgcICAABNQAECgkJKQAYALwbAA==.Sharckaron:BAAANQAECgUIDAAAAA==.Shedleass:BAAANQAECgYIEQAAAA==.Shendalar:BAABNQAECoExAAMCAAgKzhU3jgBHAgACAAgKzhU3jgBHAgAWAAMKRQT/BwB4AAAAAA==.Shigami:BAAANQADCgcIBwAAAA==.Shigare:BAAANQAECgEIAQAAAA==.Shuräto:BAAANQAECgMIAwAAAA==.Shywa:BAAANQADCgQIBgAAAA==.Shërëkhan:BAAANQAECgEIAQAAAA==.Shîvas:BAAANQAECgYICQAAAA==.Shöstakövich:BAAANQABCgEIAQAAAA==.Shøtinha:BAABNQAECoEiAAMXAAkKzhy4FACjAgAXAAgKVRy4FACjAgALAAMKLxxn8wDoAAAAAA==.Shøwtime:BAAANQAECgEIAQABNQAECgYIGgAOAEEeAA==.',
Si='Sianus:BAAANQAECgIJBAAAAA==.Sicarious:BAAANQADCgYICwAAAA==.Sicariuz:BAABNQAECoEaAAITAAgKwRTlgwDuAQATAAgKwRTlgwDuAQAAAA==.Silara:BAAANQADCgYICQAAAA==.Silves:BAAANQABCgYICgAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sl='Slickdaddy:BAAANQADCgQIBAABNQAECgkJJwAIABohAA==.',
Sm='Smarcão:BAAANQAECgcIBwAAAA==.',
Sn='Snipinho:BAAANQAECgcIEQAAAA==.Snowtail:BAAANQAECgQIDQAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Sokun:BAAANQAECgEIAQAAAA==.Solaryel:BAAANQAECgcIEQAAAA==.Solidheals:BAAANQAECgIIBgAAAA==.Sougigante:BAAANQAECgQIDAAAAA==.Souillé:BAAANQAECgYIBgABNQAFFAUICAAHALIaAA==.Soulbinder:BAAANQADCgIJAgAAAA==.Soupombagira:BAAANQAECgMIAwAAAA==.Sovaco:BAAANQAECgUIBQAAAA==.',
Sp='Spellshadown:BAABNQAECoEoAAIgAAkKqBcVNwCUAgAgAAkKqBcVNwCUAgAAAA==.Spellshamy:BAAANQAECgYIBgAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQAECgMIAwAAAA==.',
St='Stalinbrs:BAAANQAECgEIAQABNQAECgcIFwAeAOIZAA==.Stalindinho:BAAANQAECgcIDQAAAA==.Stanyzz:BAAANQADCgUIBQABNQAECgkJGQAOAFkZAA==.Stelluna:BAAANQAECgMIAwAAAA==.Stormimrage:BAAANQAECgMIBQAAAA==.Strexx:BAAANQAECgQICQAAAA==.Stronoffgard:BAABNQAECoEZAAIVAAgKXx0OUAB+AgAVAAgKXx0OUAB+AgAAAA==.Stronq:BAAANQADCggIFgAAAA==.',
Su='Sulfur:BAAANQAECgIIBAAAAA==.Surionn:BAAANQADCgcIBwAAAA==.',
['Sà']='Sàgadegemeos:BAABNQAECoEcAAMLAAgKsx+VOwCUAgALAAcKfiCVOwCUAgAXAAEKJxoMbwBNAAAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIBAABNQAECggIGQAgABkaAA==.',
Ta='Tacka:BAAANQADCggJHgAAAA==.Tafoki:BAABNQAECoEiAAMIAAgKDR+0CgCyAgAIAAgKdB20CgCyAgANAAIKQBr+3QChAAAAAA==.Tanakin:BAAANQAECgUIBQABNQAECggIKAAcAI4dAA==.Tangdebanana:BAAANQAECgUICQABNQAECgkJHQAXAHIdAA==.Tankairotty:BAAANQAECgEIAgAAAA==.Tanrity:BAAANQAECgcIEQAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAAANQAECgQICwAAAA==.',
Te='Temeloorego:BAAANQAECgMIAwAAAA==.Temkutemmedo:BAAANQAECgIIBQABNQAECgMIAwADAAAAAA==.Tennkkar:BAAANQAECgEIAQAAAA==.Texugojogatv:BAAANQAECggIEQAAAA==.Texugosa:BAAANQAECgEJAQAAAA==.',
Th='Thaeeria:BAAANQAECggIAQAAAA==.Thamihime:BAABNQAECoEfAAILAAcKixIffQDkAQALAAcKixIffQDkAQAAAA==.Tharizdum:BAAANQAECgQICgAAAA==.Thlrall:BAAANQAECgEIAgABNQAECgEIBgADAAAAAA==.Thontonas:BAAANQADCgIIAgAAAA==.Thornus:BAACNQAFFIEGAAIcAAQKtRnAAAB7AQAcAAQKtRnAAAB7AQA1AAQKgRwAAhwACArQIYYEAMoCABwACArQIYYEAMoCAAAA.Thorudos:BAAANQADCgQIAgAAAA==.Thrandu:BAAANQADCgYIBgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.Thunderburp:BAAANQAECgUIBQABNQAECggIJQASAL8kAA==.Thuzalduum:BAAANQADCgIIAgAAAA==.Thânatos:BAAANQADCgIIAgAAAA==.',
Ti='Tiadobil:BAAANQAECggICAAAAA==.',
To='Toni:BAAANQAECgUIDwAAAA==.Toshyo:BAAANQAECggIDQAAAA==.Tostão:BAAANQADCgUICwAAAA==.Touchhme:BAAANQAECgIIAgAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQADAAAAAA==.Toykiller:BAAANQADCgYICgAAAA==.',
Tp='Tprdmage:BAAANQAECgQIEQAAAA==.Tprdtank:BAAANQABCgQIBAAAAA==.',
Tr='Trighit:BAAANQADCgYICQAAAA==.Trolhöl:BAAANQAECgcJEwAAAA==.Trollrogue:BAAANQAECgUIEQAAAA==.Trosobado:BAAANQAECgQIBAAAAA==.Troyana:BAAANQADCggICAABNQAFFAUIEwAVANgbAA==.',
Tu='Tukiel:BAAANQAECgcICAAAAA==.Tunkav:BAAANQABCgYJCQAAAA==.Tuska:BAAANQADCgUIBAAAAA==.',
Ty='Tyde:BAAANQAECgYIEgABNQAECggIHQAYAAwUAA==.Typol:BAABNQAECoEfAAIRAAYKDhBMFAA/AQARAAYKDhBMFAA/AQAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAABNQAECoEcAAIKAAcKYRlaTQACAgAKAAcKYRlaTQACAgAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQADAAAAAA==.Umehara:BAACNQAFFIEKAAMXAAUKxBEzDgAuAQAXAAQKoBIzDgAuAQALAAEKVQ4KLQBRAAA1AAQKgTMAAhcACQr/IRwGAGUDABcACQr/IRwGAGUDAAAA.Umokh:BAABNQAECoEoAAIcAAgKjh3mBAC3AgAcAAgKjh3mBAC3AgAAAA==.Umterço:BAAANQADCgQIBAAAAA==.',
Un='Unbrøken:BAAANQAECgIIBAAAAA==.Unclearnaldo:BAAANQADCgYIBgABNQAECgcIEAADAAAAAA==.',
Uo='Uolokoelfo:BAABNQAECoErAAIVAAgKviApPAC/AgAVAAgKviApPAC/AgAAAA==.',
Ur='Urannia:BAABNQAECoEmAAILAAcKsxU+cgD/AQALAAcKsxU+cgD/AQAAAA==.Urgath:BAAANQAECgYIEAAAAA==.',
Ut='Uther:BAAANQAECgQICQAAAA==.',
Va='Valan:BAAANQAECgEIAgAAAA==.Valdeco:BAAANQADCggIDAAAAA==.Valdevino:BAAANQAECgcIEgAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAABNQAECoEdAAQXAAkKch2KGgBnAgAXAAkKwxeKGgBnAgALAAUKeiKdgwDVAQAnAAMKxyAVCwAWAQAAAA==.Venonpoison:BAAANQADCgMIAgAAAA==.Vermeryn:BAAANQAECgQICAAAAA==.Vermithór:BAAANQAECgMIBQAAAA==.',
Vi='Viciadø:BAAANQADCggICAABNQAFFAMIBQALAIYTAA==.Villalobos:BAAANQAECgcIDQAAAA==.Vits:BAAANQAECgcIEwAAAA==.',
Vo='Voidsurge:BAAANQAECgUICgAAAA==.Voidwar:BAAANQAECgIIAgABNQAECgUICgADAAAAAA==.Vollin:BAAANQAECgcIEwAAAA==.Volrun:BAAANQADCggIDAAAAA==.Voragem:BAAANQAECgcIDgAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.Vultures:BAAANQADCgQIBAAAAA==.',
Wa='Warlockdoido:BAAANQAECgQIBQAAAA==.Warlôka:BAAANQADCgUIBQAAAA==.Warriorbeso:BAAANQADCgIIAgAAAA==.',
Wi='Wiillord:BAAANQAECgQICAAAAA==.Willbm:BAABNQAECoEsAAMTAAgKAQ7PmQC5AQATAAgKgg3PmQC5AQAFAAYK/gvNNwAAAQAAAA==.Winnettou:BAAANQAECgcIDwAAAA==.Wipalogo:BAAANQAECgMIAwAAAA==.Wise:BAABNQAECoEnAAITAAgKySJsMADpAgATAAgKySJsMADpAgAAAA==.',
Wm='Wmana:BAAANQAECgQIEAAAAA==.',
Wr='Wrathi:BAAANQAECgIIAgAAAA==.',
Wu='Wuan:BAABNQAECoEeAAMaAAgKbxtAGgBCAgAaAAgKbxtAGgBCAgAfAAQK2wzpLwDCAAAAAA==.',
Xa='Xamanico:BAAANQAECgQIBwAAAA==.Xanasmanas:BAAANQAECgcIEgAAAA==.Xazon:BAAANQADCgUIBwAAAA==.',
Xh='Xharlios:BAAANQAECgQIBQAAAA==.',
Xi='Xingorila:BAAANQADCgQIBAAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQAECgUICAAAAA==.Xxnicoxx:BAAANQADCgcIBwAAAA==.',
Xy='Xymor:BAACNQAFFIEOAAMhAAUKHQ6gBABtAQAhAAUKHQ6gBABtAQAYAAEKHwI2FwA6AAA1AAQKgSUAAiEACQpzIcoGAAMDACEACQpzIcoGAAMDAAE1AAQKBQgFAAMAAAAA.Xyuwan:BAAANQADCgUIBQAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Ye='Yenniferxd:BAAANQABCgUIBQAAAA==.',
Yl='Ylanna:BAABNQAECoEXAAMiAAcKnhS+CQCgAQAiAAYK4xa+CQCgAQABAAIK0wX5XABiAAAAAA==.',
Yn='Ynit:BAAANQAECgQICAAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoodoo:BAAANQABCgUJBQAAAA==.Yoriko:BAAANQAECgUIBQAAAA==.Yorú:BAABNQAECoEgAAITAAgKQBoDVgBqAgATAAgKQBoDVgBqAgAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQAECgEIAQAAAA==.',
Za='Zambrotta:BAAANQADCgYIBgAAAA==.Zamii:BAAANQAECgQIBgAAAA==.Zarik:BAAANQADCgcIBwAAAA==.',
Ze='Zenolis:BAAANQADCgcJFAAAAA==.Zerathir:BAAANQAECgQICgAAAA==.',
Zh='Zhalazar:BAAANQAECgQICwAAAA==.Zhenb:BAAANQADCgEIAQAAAA==.',
Zi='Zigosmar:BAAANQAECgEJAQAAAA==.',
Zo='Zolet:BAAANQAECgMIBAAAAA==.Zones:BAAANQAECgQIBwABNQAECgcIHAAKAGEZAA==.',
Zu='Zumbix:BAAANQADCgcIBwAAAA==.',
['Ág']='Ágripa:BAAANQABCgYIBgAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Än']='Ängron:BAAANQAECgUIDgAAAA==.Änä:BAAANQADCggIDgAAAA==.',
['Är']='Ärthås:BAAANQAECgUICQAAAA==.',
['Äz']='Äzra:BAAANQAECgEIAgAAAA==.',
['Ær']='Ærikão:BAAANQAECgcIEQAAAA==.',
['Æt']='Ætherfel:BAAANQAECgIIAgAAAA==.',
['Ét']='Étel:BAAANQAECgEIAQAAAA==.',
['Ðr']='Ðrakko:BAAANQADCgQICAAAAA==.',
['Ök']='Ökamì:BAAANQADCgIIAgAAAA==.',
['Ör']='Örigem:BAAANQAECgUIDAAAAA==.',
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
