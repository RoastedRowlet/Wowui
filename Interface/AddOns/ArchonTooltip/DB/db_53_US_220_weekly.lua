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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','Mage-Arcane','Mage-Frost','Warrior-Protection','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Warrior-Arms','Druid-Feral','Hunter-BeastMastery','Monk-Brewmaster','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','Warlock-Affliction','DeathKnight-Blood','Shaman-Elemental','Paladin-Holy','Evoker-Devastation','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Paladin-Protection','Druid-Guardian','Warrior-Fury','Hunter-Survival','Shaman-Enhancement','Druid-Balance','Hunter-Marksmanship','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaragon:BAAANQAECgYIBgABNQAFFAgIFwABABAfAA==.',
Ab='Abysmal:BAAANQAECgUIEQAAAA==.',
Ad='Adame:BAAANQADCgMIAwAAAA==.Adjudicator:BAAANQAECgQIBAABNQAECgQIBQACAAAAAA==.',
Ae='Aeriona:BAABNQAECoEbAAIDAAgKRBgCVABIAgADAAgKRBgCVABIAgAAAA==.Aerolock:BAAANQAECgUIBgABNQAECgcIEAACAAAAAA==.Aerosong:BAAANQAECgcIEAAAAA==.',
Af='Affalon:BAAANQAECgQICAAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.Agemo:BAAANQABCgIIAgAAAA==.',
Ai='Aine:BAAANQAECggICQAAAA==.Ainkor:BAAANQAECgQIBQABNQAECgcIEQACAAAAAA==.',
Ak='Akyospirit:BAABNQAECoEbAAIEAAgKbAuNZQCFAQAEAAgKbAuNZQCFAQAAAA==.',
Al='Alchemised:BAAANQAECggICAAAAA==.Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAAANQAECgQICwAAAA==.Allumin:BAAANQADCggIDAAAAA==.Alpha:BAABNQAECoEeAAMFAAgKNhKSmwAEAgAFAAgKExKSmwAEAgAGAAMKrwvuIgCTAAAAAA==.',
Am='Amamonk:BAAANQAECgcIDQAAAA==.Ammert:BAAANQADCggIFAAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAYIFAAHAB0XAA==.Angliko:BAAANQADCgMJAwABNQAECggIFwAIAEIWAA==.Annei:BAABNQAECoEgAAMJAAgKvCF3FwDrAgAJAAcKOSR3FwDrAgAKAAYKIhAdLgBiAQAAAA==.Anomandaris:BAAANQAECgIJBQAAAA==.Anquan:BAAANQAECgQICAAAAA==.Anya:BAAANQAECgUICAAAAA==.',
Ap='Apothica:BAAANQAECgYJCgAAAA==.Apothicc:BAAANQAECgMIBAABNQAECgYJCgACAAAAAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgUJDAAAAA==.',
Aq='Aquae:BAAANQAECgUIBgABNQAECgYIDAACAAAAAA==.',
Ar='Arcohunt:BAAANQADCgcJBwABNQAECgUJDAACAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argodin:BAAANQAECggIDAAAAA==.',
As='Asheritâ:BAAANQAECgQIBQAAAA==.Ashvalis:BAAANQAECgUIDgAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECgUJCAAAAA==.Askr:BAAANQAECgQICQAAAA==.Asphar:BAAANQAECgcIEgAAAA==.Asynic:BAAANQADCgYIEAABNQAECgMIAwACAAAAAA==.',
Au='Aung:BAABNQAECoEoAAILAAgK2yS0CgAyAwALAAgK2yS0CgAyAwAAAA==.Auri:BAAANQADCggIFAAAAA==.',
Av='Avitarkorra:BAAANQADCgcJBwAAAA==.',
Ax='Axex:BAAANQAECgUIBwAAAA==.',
Az='Azamii:BAAANQAECgYIEQABNQAECggIGgAJANMeAA==.Azarion:BAAANQAECgUIEAAAAA==.Azill:BAACNQAFFIEHAAIBAAQKRg9vBgAxAQABAAQKRg9vBgAxAQA1AAQKgR8AAgEACQrCHt0KAPkCAAEACQrCHt0KAPkCAAAA.Azreial:BAAANQABCgYICgAAAA==.Azrëiäl:BAAANQADCgIIAgAAAA==.Azulon:BAAANQAECgIIAwAAAA==.Azurefury:BAAANQAECgYIDgAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.',
Ba='Baalalmerat:BAAANQADCgQIBAAAAA==.Bandi:BAAANQAECgQICgAAAA==.Bartrak:BAAANQADCgIJAgABNQAECgIIAwACAAAAAA==.Battôsai:BAAANQAECgQIBwAAAA==.',
Be='Bearfucius:BAAANQAECgUIDQAAAA==.Bearrific:BAAANQAECgYIDwAAAA==.Behomadra:BAAANQADCgMIAwAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAAANQAECgcIDwAAAA==.',
Bi='Billthekid:BAAANQADCgcIBwAAAA==.Binksy:BAABNQAECoEtAAIMAAkKshwUKgDnAgAMAAkKshwUKgDnAgAAAA==.Biscuit:BAACNQAFFIEUAAIHAAYKHRenAADlAQAHAAYKHRenAADlAQA1AAQKgS8AAwcACQoDJpsAANIDAAcACQrOJZsAANIDAAwAAwp5Hry7ABcBAAAA.',
Bl='Blaam:BAAANQADCgYIEgAAAA==.Blazin:BAACNQAFFIEGAAMFAAMKHQxDNACcAAAFAAIK3glDNACcAAAGAAEKnBAZCwBRAAA1AAQKgSoAAwUACQqiIZYqACIDAAUACQpDIZYqACIDAAYABQpqGyQNAJYBAAAA.Blinkzy:BAAANQADCgUICQABNQAECgkJLQAMALIcAA==.Blitzoria:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Bloui:BAAANQADCgYIEgAAAA==.Blueknight:BAAANQAECgYIDwAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Bobinsky:BAAANQADCgEIAQAAAA==.Borlok:BAAANQAECgYIFgAAAQ==.',
Br='Brannigan:BAABNQAECoEjAAIMAAgKlxxJTQBjAgAMAAgKlxxJTQBjAgAAAA==.Brannigandh:BAAANQAECgUIDwABNQAECggIIwAMAJccAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQADCgYIDAAAAA==.Briantu:BAAANQADCggJCAAAAA==.Brickfelt:BAAANQABCgYICgAAAA==.Brickitphil:BAAANQAECgUICwAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Brustomp:BAAANQADCgYIBgABNQAECgIJAgACAAAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAAANQAECgYIDAAAAA==.Bulldan:BAAANQADCgYIDQAAAA==.Bullvi:BAAANQAECgMJAwAAAA==.',
['Bä']='Bärkler:BAAANQAECgUJBgAAAA==.',
['Bé']='Béckléy:BAABNQAECoEXAAINAAkKLSLHAgBSAwANAAkKLSLHAgBSAwAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Cali:BAAANQADCgYIBgAAAA==.Cannïbal:BAAANQADCggIDwAAAA==.Cara:BAAANQADCgMIBAAAAA==.Carra:BAABNQAECoEaAAIOAAcKwRKsZwDtAQAOAAcKwRKsZwDtAQAAAA==.Cassiopeía:BAEANQAECgQIBQABNQAECggICAACAAAAAA==.Catriona:BAAANQAECgUIDwAAAA==.',
Ch='Charcuterie:BAACNQAFFIEUAAIPAAYKbRJ4AQC1AQAPAAYKbRJ4AQC1AQA1AAQKgR4AAg8ACQqSIHcEAPwCAA8ACQqSIHcEAPwCAAAA.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheezeburg:BAAANQAECgQICwAAAA==.Chicken:BAAANQAECgcIBwABNQAFFAYIFAAHAB0XAA==.Chikindalf:BAAANQADCgEJAQAAAA==.Chillidán:BAAANQAECgUIEgAAAA==.Choggie:BAAANQAECgcIEgAAAA==.',
Co='Cons:BAABNQAECoEkAAMJAAgKAiPOFQD1AgAJAAgKAiPOFQD1AgAQAAEKBAuzIgAyAAAAAA==.Corellon:BAAANQAECgYIEAAAAA==.',
Cr='Cranee:BAABNQAECoEqAAMRAAgKWRItUgAVAgARAAgKWRItUgAVAgASAAIKqQICXwBQAAAAAA==.Cranium:BAAANQAECggIDAAAAA==.Crazytasty:BAABNQAECoEdAAIOAAcK/SPxJwC9AgAOAAcK/SPxJwC9AgAAAA==.Critcomander:BAAANQADCgYIBgAAAA==.',
Da='Dabora:BAABNQAECoEiAAMTAAkKNR9WCQAUAwATAAkKNR9WCQAUAwAUAAIKEg7CFABpAAAAAA==.Damassan:BAAANQABCgYIBgAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYICwABNQAECgUIDgACAAAAAA==.Darige:BAAANQAECgQJCgAAAA==.Darim:BAABNQAECoEaAAIDAAgKlB44NAC5AgADAAgKlB44NAC5AgABNQADCgYIBgACAAAAAA==.Darthspawn:BAAANQAECgQICAAAAA==.Daryn:BAAANQAECgEIAQAAAA==.Davidbowy:BAAANQADCgQIBQABNQAECgIIAgACAAAAAA==.',
De='Deathollow:BAAANQADCgYIBgAAAA==.Demonainkor:BAAANQAECgQIBAABNQAECgcIEQACAAAAAA==.Demonicfury:BAAANQAECgIIAgAAAA==.Dencity:BAABNQAECoElAAMJAAgKwBwTLgBwAgAJAAgKwBwTLgBwAgAQAAEK3wPOJgAmAAAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQADCgcICwABNQAECgcIEwACAAAAAA==.Devitodevour:BAABNQAECoEcAAMRAAgK7xvGXwDpAQARAAYKuBvGXwDpAQASAAIKlhwUQgCmAAAAAA==.Devwarr:BAAANQAECgQIBwABNQAECgcIEwACAAAAAA==.Dezard:BAAANQABCgIIAgAAAA==.',
Dh='Dhbert:BAAANQAECgIJAgAAAA==.Dhomeli:BAAANQAECgIIAwAAAA==.',
Di='Dirtchez:BAAANQAECgQJBAAAAA==.Disastrophy:BAAANQAECgUIBgAAAA==.Disturbed:BAABNQAECoEkAAQRAAgKSxiWTQAkAgARAAcKMReWTQAkAgASAAMKxRUhNQDZAAAVAAEKkwRYKgAsAAAAAA==.',
Dk='Dkson:BAACNQAFFIEIAAIWAAQKRx6fCQBmAQAWAAQKRx6fCQBmAQA1AAQKgSIAAhYACQqsIEwNACQDABYACQqsIEwNACQDAAAA.',
Do='Docen:BAAANQAECgMIAwAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.Download:BAAANQADCggICAAAAA==.',
Dr='Dragonfist:BAAANQAECgIIAgAAAA==.Dragthyr:BAAANQADCgYIEgAAAA==.Druiaier:BAAANQADCggIEwAAAA==.Druknatsu:BAAANQAECgQICQAAAA==.',
Du='Dustyknight:BAAANQAECgUIBwAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgcIEAAAAA==.',
Ed='Edge:BAAANQAECgYIDgAAAA==.',
El='Eleathe:BAAANQADCgYIBgAAAA==.Elgimpster:BAAANQADCgIIAgAAAA==.Elidoria:BAEBNQAECoEiAAIFAAgKvxYbcwBiAgAFAAgKvxYbcwBiAgAAAA==.Elphinia:BAAANQADCgYJBgABNQAECgkJIQAXALAYAA==.',
En='Enoki:BAAANQAECggIEwABNQAFFAYIEgAYAIMTAA==.',
Ep='Ephodess:BAAANQAECgQIBAAAAA==.',
Er='Eraduckated:BAABNQAECoEWAAMTAAgKXR3rEgCeAgATAAcKJiDrEgCeAgAUAAUKdRH0DQArAQAAAA==.',
Es='Esile:BAABNQAECoEZAAIZAAcKfQozGgBoAQAZAAcKfQozGgBoAQAAAA==.Esoryn:BAABNQAECoEeAAIDAAgKSCMKGwAtAwADAAgKSCMKGwAtAwAAAA==.',
Ev='Everlife:BAAANQAECgEIBAAAAA==.Evilainkor:BAAANQAECgcIEQAAAA==.',
Ex='Exia:BAABNQAFFIEIAAIMAAUKbgnLDgBXAQAMAAUKbgnLDgBXAQAAAA==.',
Fa='Fauzzie:BAAANQAECgQIBQAAAA==.Fayrel:BAAANQAECgUIDAAAAA==.',
Fe='Fedders:BAABNQAECoEfAAIDAAgKlCOMFwBBAwADAAgKlCOMFwBBAwAAAA==.Felaids:BAABNQAECoEfAAQRAAgKWhYvbQC/AQARAAcKgRQvbQC/AQASAAIKvxWJTQCAAAAVAAIKDQmIGwBnAAAAAA==.Felnyx:BAAANQADCgYJCgAAAA==.Feor:BAAANQAECgUIBQAAAA==.Feralyn:BAAANQADCgYJCgAAAA==.Fero:BAAANQADCgUICAAAAA==.',
Fi='Fillon:BAACNQAFFIEMAAIDAAQKcB2mBwBzAQADAAQKcB2mBwBzAQA1AAQKgR8AAgMACQrOIKcfABYDAAMACQrOIKcfABYDAAAA.Fionas:BAAANQAECgUIDAAAAA==.Firexcracker:BAAANQADCgQJBAAAAA==.Fishfood:BAABNQAECoEZAAIaAAgK1RcELQAmAgAaAAgK1RcELQAmAgAAAA==.Fixer:BAAANQAECgEIAQAAAA==.',
Fl='Flappysnail:BAAANQADCgYICwAAAA==.Flatine:BAAANQADCgEIAQAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frazzle:BAAANQADCgMIAwABNQADCgcIBwACAAAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAABNQAECoEbAAIFAAkKURUZZgCCAgAFAAkKURUZZgCCAgAAAA==.',
Fu='Fujitora:BAAANQAECgIIAgAAAA==.Funbunz:BAAANQAECgEIAQAAAA==.',
['Fø']='Førd:BAABNQAECoEpAAQZAAkKDxxBCgCeAgAZAAkKaxhBCgCeAgAbAAcK9RiDBwDYAQAcAAUKKgXoMADJAAAAAA==.',
Ga='Gangrene:BAABNQAECoEYAAIaAAcKkA/SSwB/AQAaAAcKkA/SSwB/AQAAAA==.Gaspasser:BAAANQAECgUICAAAAA==.Gaviin:BAAANQAECgcIDQAAAA==.Gazamiseh:BAAANQABCgIIAgAAAA==.',
Ge='Gearador:BAAANQADCgMIBAAAAA==.Genovia:BAAANQADCgQIBAABNQAECggICAACAAAAAA==.Gerhart:BAABNQAECoEcAAMLAAgKThnEHABtAgALAAgKThnEHABtAgAIAAYKhBPYDwBTAQAAAA==.',
Gi='Gigarius:BAAANQAECgUIDwAAAA==.Gizelia:BAAANQADCgMIBAAAAA==.',
Gl='Gleya:BAAANQADCgYIBwAAAA==.Gloomy:BAAANQADCgYIBgAAAA==.',
Go='Goblinsrhot:BAAANQADCgcIDQAAAA==.Goncor:BAAANQAECgUIBgABNQAECggIIAAJALwhAA==.Gorrelord:BAAANQADCgIIAgABNQAFFAMIBgAFAB0MAA==.',
Gr='Gracze:BAAANQAECgUIBQAAAA==.Gramadingg:BAAANQADCgEIAQAAAA==.Granolah:BAAANQAECgQICAABNQAECgkJIgATADUfAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgQIBQAAAA==.Greyback:BAAANQADCgIIAgAAAA==.Griffmonk:BAABNQAECoEXAAIdAAcK9htnEAAsAgAdAAcK9htnEAAsAgAAAA==.Grumpymage:BAABNQAECoEdAAIGAAgKCR5ZAwDXAgAGAAgKCR5ZAwDXAgAAAA==.',
Gu='Gunjamomma:BAAANQADCgMIAwABNQADCgcIEwACAAAAAA==.',
Ha='Hafsac:BAAANQAECgMIAwAAAA==.Hamasakura:BAAANQADCggIDwAAAA==.Hardord:BAAANQAECgIIAgAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Haryle:BAAANQADCggICAAAAA==.Hayanne:BAABNQAECoEYAAIHAAcKUhenDgDnAQAHAAcKUhenDgDnAQAAAA==.',
He='Healchucky:BAAANQAECgIIAgAAAA==.Healzjoogewd:BAAANQADCgYIBgABNQADCgcIBwACAAAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.',
Hi='Hikary:BAAANQABCgIIAgAAAA==.',
Ho='Hochunk:BAAANQAECgcIEgAAAA==.Holikow:BAAANQAECgIJBQAAAA==.Holyherpies:BAAANQAECgIIAgAAAA==.Holyness:BAAANQAECgUIDQAAAA==.Honeybunz:BAAANQADCgMIBAAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAABNQAECoEaAAMeAAgKohPDGQDNAQAeAAgKcBPDGQDNAQADAAcKrAtJqQBcAQABNQAECgkJIgAcAMQhAA==.',
Hu='Hurano:BAAANQAECgYICQAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIDgAAAA==.',
Id='Idyllwild:BAAANQADCggIGwAAAA==.',
Il='Illusiõn:BAAANQAECgQIBAAAAA==.',
In='Inducktive:BAAANQADCgIIAgABNQAECggIFgATAF0dAA==.Inkdot:BAABNQAECoEbAAMYAAgKwR6MKQCLAgAYAAcKiCCMKQCLAgADAAYKZBMXngB3AQAAAA==.Inkshield:BAAANQADCgYIBgABNQAECggICAACAAAAAA==.Inkwell:BAAANQADCgYIBgABNQAECggIGwAYAMEeAA==.Innerlight:BAAANQAECgEIAQAAAA==.',
Io='Iomedáe:BAAANQADCgMIAwAAAA==.',
Ir='Irishnight:BAAANQADCgQICgABNQAECggIIQAfAMIRAA==.Ironlightnin:BAAANQADCgUIBQAAAA==.Irritate:BAAANQAECgEIAQAAAA==.',
Ja='Jakobo:BAAANQAECggIDwAAAA==.Jandreyn:BAAANQADCgEIAQAAAA==.Jarkus:BAAANQADCgEIAQAAAA==.Jarthas:BAAANQADCgYIDQAAAA==.Jazlynel:BAAANQADCgYIBgAAAA==.',
Je='Jelly:BAACNQAFFIESAAIYAAYKgxPdAwD4AQAYAAYKgxPdAwD4AQA1AAQKgSQAAxgACQrpIPMJAFwDABgACQrpIPMJAFwDAAMAAQrdH2E0AUsAAAAA.Jenivira:BAAANQADCgMIAwAAAA==.',
Ji='Jimbostein:BAAANQADCgMIAwAAAA==.',
Jo='Johnnyblaze:BAAANQADCgIIAgAAAA==.Jozalin:BAAANQADCgQIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgMIBQAAAA==.Junknthtrunk:BAAANQADCgYJCAAAAA==.',
Ka='Kaelana:BAAANQABCgQJBQAAAA==.Kamahl:BAAANQAECggIEgAAAA==.',
Ke='Keanew:BAABNQAECoEWAAMLAAYKShOOOQB/AQALAAYKShOOOQB/AQAIAAEK6Q59JgAtAAAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIHQAAAA==.Keonna:BAAANQADCgYIEwAAAA==.Keppra:BAAANQADCggIGgAAAA==.Kerlin:BAAANQAECggIDgAAAA==.',
Kh='Kheilah:BAAANQADCgEIAQAAAA==.Khurst:BAAANQAECgQIBAAAAA==.',
Ki='Kilaben:BAAANQAECgQIBwAAAA==.Kimmex:BAAANQADCgMIBAAAAA==.Kinoxo:BAACNQAFFIEOAAIMAAYKnh9aBAA2AgAMAAYKnh9aBAA2AgA1AAQKgSwAAwwACQpiJCEMAIQDAAwACQpiJCEMAIQDACAAAQpIIdcgAF4AAAAA.Kinozo:BAAANQAECgMIAwAAAA==.Kitsunë:BAAANQADCgYIBgAAAA==.Kittyclysm:BAAANQADCgcIDQAAAA==.',
Ko='Kossuth:BAAANQABCgEIAQAAAA==.Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQADCgYICgAAAA==.',
La='Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgUICQABNQAECgkJLQAMALIcAA==.Leditoo:BAAANQADCggICAAAAA==.Legnase:BAABNQAECoEaAAIJAAgK0x6MIwClAgAJAAgK0x6MIwClAgAAAA==.Leiche:BAAANQAECgIIBQAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Liferia:BAAANQAECgYIBwAAAA==.Ligmabonez:BAAANQADCgcIFgAAAA==.Lilchloe:BAAANQADCgMIBAAAAA==.Lilnasty:BAAANQADCgMIAwABNQAECgUIEQACAAAAAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Littlefry:BAAANQABCgEIAQAAAA==.Livesey:BAAANQAECgYICwAAAA==.',
Lo='Lockpie:BAAANQADCgQIBAAAAA==.Longshañk:BAABNQAECoEVAAIhAAkKBhe7AgDLAgAhAAkKBhe7AgDLAgAAAA==.',
Lu='Lucibrew:BAABNQAECoEbAAMBAAgKASCuEQCPAgABAAgKCxyuEQCPAgAPAAcKLyDWCABcAgAAAA==.Luto:BAAANQAECggIBAAAAA==.Luuko:BAAANQADCgMIAwAAAA==.',
Ma='Macpreizy:BAAANQADCgQIDAAAAA==.Mattydruid:BAAANQAECgMIBQAAAA==.Mavramune:BAABNQAECoEnAAIOAAkKsRcJNACNAgAOAAkKsRcJNACNAgAAAA==.',
Mc='Mcfizzertz:BAAANQAECggICAAAAA==.Mcfürry:BAAANQAECgIIAgAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECggIGwAiAJYaAA==.Mendinna:BAAANQADCggIHQABNQAECgUIDAACAAAAAA==.Mendoon:BAAANQAECgUIDAAAAA==.Methir:BAAANQADCgcICwABNQAECgYIFgACAAAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAACNQAFFIEMAAIOAAUKWRbhBACvAQAOAAUKWRbhBACvAQA1AAQKgS4AAg4ACQoDJpYBAOEDAA4ACQoDJpYBAOEDAAAA.Mistborn:BAAANQAECggIAQABNQAECggICAACAAAAAA==.',
Mo='Moistmaker:BAAANQAECgEIAQAAAA==.Montebrew:BAAANQADCgYIBgABNQADCgcIDAACAAAAAA==.Montecane:BAAANQADCgcIDAAAAA==.Mooky:BAABNQAECoEZAAIjAAgKYgn1QQCeAQAjAAgKYgn1QQCeAQAAAA==.Moonfire:BAAANQAECggJCAAAAA==.Moriang:BAAANQADCgEIAQAAAA==.Moshicat:BAAANQAECgUIBwAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAAANQAECgUIDwAAAA==.Mythallas:BAAANQADCgIIAgAAAA==.',
Na='Nakir:BAAANQAECgQIDAAAAA==.Naraku:BAABNQAECoEsAAMSAAkKfR/XHgBnAQARAAYKFB4dVQALAgASAAQKyxzXHgBnAQAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neebiter:BAAANQAECgcIDgAAAA==.Nehemez:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Neshock:BAAANQAECgIIAgABNQAECggIHgAhAEMbAA==.Nettie:BAAANQAECgQIBQABNQAECgQIBgACAAAAAA==.Netty:BAAANQAECgQIBgAAAA==.',
No='Noctyra:BAAANQADCgMIAwAAAA==.Novakayne:BAAANQADCgMIBAAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.',
Ny='Nymphetamine:BAAANQAECgYICwAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAABNQAECoEbAAIkAAgK+QvWJwDAAQAkAAgK+QvWJwDAAQAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ou='Ouinur:BAAANQABCggICAABNQAECgQICwACAAAAAA==.',
Ow='Owenwilson:BAAANQADCgUIBQAAAA==.',
Pa='Pandaloco:BAAANQAECgMIAwAAAA==.Pandalôc:BAAANQAECgQIBQAAAA==.Pandoe:BAACNQAFFIEUAAIfAAYKliIrAABqAgAfAAYKliIrAABqAgA1AAQKgS8AAh8ACQqGJkgAAP8DAB8ACQqGJkgAAP8DAAAA.',
Pe='Penelopea:BAAANQAECgYICwAAAA==.Perun:BAAANQAECgYIDQAAAA==.',
Ph='Phenomenal:BAAANQAECgUICQAAAA==.Pheonyx:BAAANQADCggIEwAAAA==.',
Pi='Picarus:BAAANQADCgYIBgAAAA==.Picklerìck:BAAANQAECgMIBQAAAA==.',
Pl='Planb:BAAANQAECgUJCwABNQAECggIKgARAFkSAA==.',
Po='Porteagarder:BAAANQADCggIIwABNQAECgYIDQACAAAAAA==.',
Pr='Preparedpie:BAACNQAFFIEKAAMlAAUKhg0rBwA5AQAlAAQKERArBwA5AQALAAEKWgPtFABIAAA1AAQKgTAAAyUACQphIXgFAGwDACUACQphIXgFAGwDAAsABAp+DzdYALYAAAAA.Priarace:BAAANQAECgEIAQABNQAECgYICAACAAAAAA==.Pringler:BAAANQAECgYICgABNQAFFAYIFAAHAB0XAA==.Producktive:BAAANQAECgIIAgABNQAECggIFgATAF0dAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQADCggIHAABNQAECgcIGQAZAH0KAA==.Príestly:BAAANQAECgYIDAAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQAECgQIBAAAAA==.',
Py='Pyatt:BAABNQAECoEXAAIVAAgK7hYuBABdAgAVAAgK7hYuBABdAgAAAA==.Pyromaniacal:BAAANQAECgQIBQAAAA==.',
['Pä']='Pändaloc:BAAANQADCgQIBAAAAA==.',
Qe='Qe:BAAANQADCgQIBAAAAA==.',
Qu='Quack:BAAANQAECggIDAAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECggIDAACAAAAAA==.Quesoblanco:BAAANQADCgUICQAAAA==.Quilae:BAAANQADCggIHQABNQAECgYIDQACAAAAAA==.',
Qy='Qyburn:BAABNQAECoEYAAMTAAgKJx7MEwCVAgATAAgKJx7MEwCVAgAmAAMKeBZgNADXAAAAAA==.',
Ra='Radioface:BAAANQADCggICgAAAA==.Raerlynn:BAEANQADCgcJBwABNQAECgUICwACAAAAAA==.Ragecage:BAAANQADCggICAABNQAECggIFgARADEYAA==.Randivh:BAAANQADCgYJDAAAAA==.Rassputin:BAAANQAECgUICQAAAA==.',
Re='Recipes:BAAANQAECgUIBgABNQAECggICAACAAAAAA==.Redbeardd:BAAANQADCgUICQAAAA==.Reigwend:BAAANQADCgMIBQAAAA==.Remish:BAAANQABCgQIBgABNQAECgMIAwACAAAAAA==.Rendezvous:BAAANQADCgUIBQAAAA==.Renkà:BAABNQAECoEhAAIXAAkKsBi6JAC5AgAXAAkKsBi6JAC5AgAAAA==.Resmondo:BAAANQADCgcICQAAAA==.Revaerlous:BAABNQAECoEmAAIaAAkKFB8TDwATAwAaAAkKFB8TDwATAwAAAA==.',
Rh='Rheas:BAAANQADCgYIDAABNQAECggICAACAAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAYIFAAHAB0XAA==.',
Rn='Rn:BAAANQADCgQIBAAAAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roereker:BAAANQADCggICAAAAA==.Roflsummon:BAAANQADCgEJAQABNQAECggICAACAAAAAA==.Roflthump:BAAANQADCgcJBwAAAA==.Roketraccoon:BAAANQADCggIFgAAAA==.Rootbreaker:BAAANQAECgEIAQABNQAECgUIBgACAAAAAA==.Roshamandes:BAABNQAECoEXAAIIAAgKQhZNCAAZAgAIAAgKQhZNCAAZAgAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAgABNQAECgYIDwACAAAAAA==.Runep:BAAANQAECgEIAQAAAA==.',
['Rè']='Rèi:BAAANQAECgEIAgABNQAECgcIHQAOAP0jAA==.',
Sa='Sabermage:BAAANQAECgIIAwAAAA==.Sacredchikín:BAAANQAECgcJEwAAAA==.Samuel:BAAANQAECgIIAgAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Sasukie:BAAANQAECgQICAAAAA==.Saxa:BAABNQAECoEbAAIlAAgK+SIaCQAsAwAlAAgK+SIaCQAsAwAAAA==.',
Sc='Screamsoda:BAAANQAECgUICAABNQAECggICAACAAAAAA==.Scrubzz:BAAANQAECgUJCwAAAA==.',
Se='Serkis:BAAANQAECgIIAgAAAA==.Sev:BAAANQADCgYIBQAAAA==.Seyekolock:BAAANQAECgQICgAAAA==.Seyekosis:BAAANQAECgYJCgAAAA==.',
Sg='Sgathaich:BAEANQAECgQIBgABNQAECgUIBgACAAAAAA==.',
Sh='Shadowzform:BAAANQABCgYIBAABNQAECgQICAACAAAAAA==.Shallistiah:BAABNQAECoEaAAMnAAgK9BC9MQAkAQAnAAYKwQy9MQAkAQAjAAQKMwn2aADTAAAAAA==.Shamadin:BAAANQADCgEJAQAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgUICgAAAA==.Shamdh:BAAANQAECgYIDAAAAA==.Shamdwarf:BAAANQAECgEIAQAAAA==.Shamuel:BAAANQADCgYIBgAAAA==.Shiftnfard:BAAANQADCggIDgAAAA==.Shobadon:BAAANQAECggICAAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgQICAAAAA==.',
Si='Siatral:BAABNQAECoEiAAIcAAkKxCEzBABbAwAcAAkKxCEzBABbAwAAAA==.Siete:BAAANQAECgQICQAAAA==.Siggopotomus:BAAANQAECgMIBAABNQAECggICAACAAAAAA==.Sigvolden:BAAANQAECgEJAQABNQAECggICAACAAAAAA==.Silchar:BAAANQADCgEIAQAAAA==.Silicon:BAAANQAECgYIEgAAAA==.Silver:BAAANQAECgIIAgABNQAECgYIEgACAAAAAA==.Siona:BAABNQAECoEYAAIOAAcKDwWAmgBqAQAOAAcKDwWAmgBqAQAAAA==.Sixpaths:BAAANQAECgYIEwABNQAECggICAACAAAAAA==.Siyunkai:BAEANQAECgIIAwAAAA==.',
Sk='Skadie:BAAANQAECgcIEwAAAA==.Skittellz:BAAANQABCgMIAwAAAA==.Skiye:BAAANQADCgEIAQAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgACAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgACAAAAAA==.Skwup:BAABNQAECoEkAAMYAAkKQBqzHgDHAgAYAAkKQBqzHgDHAgADAAQKKRbJ0AAGAQAAAA==.',
Sl='Slackness:BAAANQADCgUICAAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slappygilmor:BAAANQADCgcIBwAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggJCQABNQAFFAMIBgAFAB0MAA==.Sleepybeard:BAAANQAECgQICAAAAA==.Slubadub:BAAANQAFFAIIAwAAAA==.',
Sm='Smiteslay:BAAANQAECgUJCgABNQAFFAMIBgAFAB0MAA==.',
Sn='Snivels:BAAANQAECgUIDQAAAA==.',
So='So:BAAANQAECgUICgAAAA==.Soggycat:BAEANQADCgEIAQAAAA==.Soil:BAAANQAECgcJEwAAAA==.Somna:BAAANQAECgUJCwAAAA==.',
Sp='Sparrkle:BAABNQAECoEbAAISAAgKBwXbIgBGAQASAAgKBwXbIgBGAQAAAA==.Spinecrawler:BAABNQAECoEWAAIRAAgKMRjZTgAgAgARAAgKMRjZTgAgAgAAAA==.Spyro:BAAANQADCggIKgAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Staryknight:BAAANQAECgIIAgAAAA==.Steelrat:BAAANQADCgMIBAAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stickshamm:BAAANQAECgEIAQAAAA==.Stiick:BAABNQAECoEYAAIeAAcKTxddGQDSAQAeAAcKTxddGQDSAQAAAA==.Stonecracker:BAAANQADCgMIBAAAAA==.Stìmpak:BAAANQADCgYIDwABNQAECgUIBgACAAAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.Sudsy:BAAANQADCgQIBAABNQAECgYIDAACAAAAAA==.Supadupaman:BAAANQABCgYIBwAAAA==.Supaman:BAAANQABCgUIBQAAAA==.',
Sw='Sweetbippy:BAAANQADCggIIgAAAA==.Swifthealss:BAAANQAECgUIDAAAAA==.Swirls:BAAANQADCggICQAAAA==.',
Sy='Sylunae:BAAANQADCgcIGQABNQAECgYIDQACAAAAAA==.Syluné:BAAANQAECgYIDQAAAA==.',
Ta='Tacoshaman:BAAANQADCgIJAgABNQADCgcIEwACAAAAAA==.Tacozpriest:BAAANQADCgcIEwAAAA==.Taelyx:BAAANQAECgYIEwAAAA==.Tambot:BAAANQAECgYICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgYIDAAAAA==.Tazmina:BAABNQAECoEhAAILAAYKEh/pLgDTAQALAAYKEh/pLgDTAQAAAA==.',
Te='Teddykgb:BAAANQAECgEIAgAAAA==.Tequilàrose:BAAANQADCgEIAQABNQADCgcIBwACAAAAAA==.Tessa:BAABNQAECoEYAAIXAAcKgxGOXgC0AQAXAAcKgxGOXgC0AQAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAAANQAECggIEwAAAA==.Thalooze:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinyjapeto:BAAANQAECgQIBwAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAABNQAECoEYAAIOAAcKEhuwRwBKAgAOAAcKEhuwRwBKAgAAAA==.Tortapounder:BAAANQAECgQICQAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgQIBgAAAA==.',
Tu='Turin:BAABNQAECoEbAAIHAAgKywmbFgBhAQAHAAgKywmbFgBhAQAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twiggysmalls:BAAANQADCgUIBAAAAA==.Twilghtdawn:BAAANQADCgUIBQAAAA==.',
Ty='Tybo:BAAANQAECgUIDQAAAA==.Tycho:BAAANQADCgYIDQAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.Tydros:BAAANQADCgUIBAAAAA==.',
Un='Uncás:BAAANQAECgQIDwAAAA==.Undyinggnome:BAAANQADCggIGQAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Va='Vaelock:BAAANQAECgYIDQAAAA==.Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQADCggIFgAAAA==.Valoryan:BAABNQAECoEYAAInAAcKWxpjGgAUAgAnAAcKWxpjGgAUAgAAAA==.Valy:BAAANQADCgcIBwAAAA==.Valyteilssra:BAAANQADCgQIBAAAAA==.Vasoline:BAAANQAECgYIBwABNQAECgcIDwACAAAAAA==.Vaxtur:BAAANQAECggJCAAAAA==.',
Ve='Vegà:BAAANQAECgUIDgAAAA==.Vendettis:BAAANQAECgEIAQAAAA==.Vextaerin:BAAANQAECgUIBwAAAA==.Vextarin:BAAANQADCgYJBgABNQAECgUIBwACAAAAAA==.Veylyn:BAAANQAECgUIEAAAAA==.Veztaroth:BAAANQAECgYIEQAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQAECgIIAgAAAA==.Voidyo:BAABNQAECoEjAAMlAAgKfSV4BwBHAwAlAAgKfSV4BwBHAwALAAQKBR7qQgA4AQAAAA==.',
We='Weißenacht:BAAANQABCgUIBQAAAA==.',
Wh='Whiskeyjak:BAAANQAECgYIDwAAAA==.',
Wi='Willowbark:BAAANQADCgYIDgAAAA==.Willowest:BAABNQAECoElAAIOAAgK5iH/HADvAgAOAAgK5iH/HADvAgAAAA==.Wizbizzler:BAAANQAECgYJDgAAAA==.',
Wr='Wrathstorm:BAABNQAECoEbAAIiAAgKlhqqCQCoAgAiAAgKlhqqCQCoAgAAAA==.',
Xa='Xalatoes:BAAANQABCgYICAAAAA==.Xanatose:BAAANQAECgYIDAABNQAECggICwACAAAAAA==.Xanier:BAAANQADCgYIEwAAAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAAANQAECgYIEAAAAA==.Xithia:BAEANQAECgUIBgAAAA==.',
Xx='Xxcor:BAAANQADCggIEAAAAA==.',
Xy='Xyndylyne:BAAANQADCgcIBwAAAA==.',
Ya='Yahtze:BAAANQADCgYIBgAAAA==.Yanella:BAABNQAECoEXAAIJAAgKxhfmPQApAgAJAAgKxhfmPQApAgAAAA==.',
Yi='Yisdk:BAAANQAECgUICQAAAA==.Yisshaman:BAAANQAECgcIEQAAAA==.',
Yo='Yogibearz:BAAANQAECgEIAQABNQAECgQICQACAAAAAA==.',
Yu='Yunbao:BAAANQADCgIIAgAAAA==.',
Za='Zanax:BAAANQAECgMIBQAAAA==.Zandarbribbs:BAAANQAECgIIAwAAAA==.Zarrah:BAAANQABCgYICgAAAA==.',
Ze='Zennya:BAAANQAECgYIDgAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.Zenthora:BAAANQADCgIIAgAAAA==.',
Zo='Zoldyck:BAAANQADCggIEAAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.Zyrx:BAAANQADCggIDwAAAA==.',
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
