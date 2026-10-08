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

local lookup = {'Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','DemonHunter-Havoc','DeathKnight-Blood','Mage-Frost','Mage-Arcane','Warrior-Protection','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Shaman-Enhancement','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','DeathKnight-Unholy','DemonHunter-Devourer','Druid-Feral','Monk-Brewmaster','Paladin-Holy','Priest-Discipline','Rogue-Outlaw','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Monk-Mistweaver','Druid-Guardian','Warrior-Fury','Hunter-Survival','Druid-Balance','Hunter-Marksmanship','Druid-Restoration',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaragon:BAAANQAECggICAABNQAFFAgIGAABABAfAA==.',
Ab='Abysmal:BAABNQAECoEaAAMCAAYKHBJRfQBlAQACAAYKHBJRfQBlAQADAAEK9AjzJQEqAAAAAA==.',
Ad='Adame:BAAANQADCgcICQAAAA==.Adjudicator:BAAANQAECgQIBAABNQAECgQIBQAEAAAAAA==.',
Ae='Aeriona:BAABNQAECoEiAAIFAAgKox2IPgC0AgAFAAgKox2IPgC0AgAAAA==.Aerobear:BAAANQADCgYIBgABNQAECggIGAAGAP8QAA==.Aerolock:BAAANQAECgUIBgABNQAECggIGAAGAP8QAA==.Aerosong:BAABNQAECoEYAAIGAAgK/xCFMwDdAQAGAAgK/xCFMwDdAQAAAA==.',
Af='Affalon:BAAANQAECgQICAAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.Agemo:BAAANQABCgIIAgAAAA==.',
Ai='Aine:BAAANQAECggIDAAAAA==.Ainkor:BAAANQAECgQIBQABNQAECgkJGgAHAHoaAA==.',
Ak='Akyospirit:BAABNQAECoEjAAICAAgKbAsOdQB9AQACAAgKbAsOdQB9AQAAAA==.',
Al='Alchemised:BAAANQAECggICgAAAA==.Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAAANQAECgQIEwAAAA==.Allumin:BAAANQADCggIEAAAAA==.Alpha:BAABNQAECoEmAAMIAAgKkhmNBgBrAgAIAAgKLBmNBgBrAgAJAAgKExI9sQD+AQAAAA==.',
Am='Amamonk:BAABNQAECoEWAAIBAAgKjhYgHAAtAgABAAgKjhYgHAAtAgAAAA==.Ammert:BAAANQADCggIFQAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAcIFgAKANsVAA==.Angliko:BAAANQADCgMJAwABNQAECggIHwALAPwWAA==.Annei:BAABNQAECoEoAAMMAAkKCyHCDgA6AwAMAAgKIiPCDgA6AwANAAYKIhDJNABVAQAAAA==.Anomandaris:BAAANQAECgUICgAAAA==.Anquan:BAAANQAECgQIDAAAAA==.Anya:BAAANQAECgYIDgAAAA==.',
Ap='Apedemak:BAAANQADCgIIAgAAAA==.Apothica:BAABNQAECoEWAAIJAAcKlguk4QCfAQAJAAcKlguk4QCfAQAAAA==.Apothicc:BAAANQAECgMIBAABNQAECgcIFgAJAJYLAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgUJDAAAAA==.',
Aq='Aquae:BAAANQAECgYICAABNQAECgYIEQAEAAAAAA==.',
Ar='Arcohunt:BAAANQADCgcJBwABNQAECgUJDAAEAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argodin:BAAANQAECggIEQAAAA==.',
As='Asheritâ:BAAANQAECgQICQAAAA==.Ashvalis:BAAANQAECgUIEgAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECgYIDgAAAA==.Askr:BAAANQAECgQICQAAAA==.Asphar:BAABNQAECoEaAAIOAAgKAiLVGwAPAwAOAAgKAiLVGwAPAwAAAA==.Asynic:BAAANQADCgYIEAABNQAECgUICAAEAAAAAA==.',
Au='Aung:BAABNQAECoExAAIGAAgKmyV3CgBKAwAGAAgKmyV3CgBKAwAAAA==.Auri:BAAANQAECgEIAQAAAA==.',
Av='Avitarkorra:BAAANQAECgQIBAAAAA==.',
Ax='Axex:BAAANQAECgYIDQAAAA==.',
Az='Azamii:BAABNQAECoEaAAMCAAgK+RhCVwDeAQACAAcKCRdCVwDeAQADAAQK9RrVowAeAQABNQAECggIIgAMAD0gAA==.Azarion:BAABNQAECoEcAAMPAAcKGhUtMgDyAAAQAAUKdxI6uwAnAQAPAAQKlBAtMgDyAAAAAA==.Azill:BAACNQAFFIEIAAIBAAQKRg88CAAhAQABAAQKRg88CAAhAQA1AAQKgSIAAgEACQoOH1QNAOwCAAEACQoOH1QNAOwCAAAA.Azreial:BAAANQABCgYICgAAAA==.Azrëiäl:BAAANQADCgIIAgAAAA==.Azulon:BAAANQAECgIIAwAAAA==.Azurefury:BAABNQAECoEYAAIRAAcKJAY8GwB7AQARAAcKJAY8GwB7AQAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.',
Ba='Bandi:BAAANQAECgYIDwAAAA==.Bartrak:BAAANQADCgIJAgABNQAECgIIAwAEAAAAAA==.Battôsai:BAAANQAECgQICwAAAA==.',
Be='Bearfucius:BAAANQAECgYIEwAAAA==.Bearrific:BAABNQAECoEXAAMSAAcKBBDoHgDEAQASAAcKBBDoHgDEAQATAAEKXwW6jAAvAAAAAA==.Behomadra:BAAANQADCgMIAwAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAAANQAECggIEQAAAA==.Beyond:BAAANQADCgcIBwAAAA==.',
Bi='Billthekid:BAAANQADCgcIBwAAAA==.Binksy:BAABNQAECoEyAAIUAAkKqR3cMADnAgAUAAkKqR3cMADnAgAAAA==.Biscuit:BAACNQAFFIEWAAMKAAcK2xXgAADmAQAKAAYKWBngAADmAQAUAAEK7gBTMwBJAAA1AAQKgTIAAwoACQobJt0AAMoDAAoACQrmJd0AAMoDABQABArPHrizAGwBAAAA.',
Bl='Blaam:BAAANQAECgEIAQAAAA==.Blazin:BAACNQAFFIEKAAMJAAQK7A/lIQA3AQAJAAQKQQ3lIQA3AQAIAAEKnBB0DwBJAAA1AAQKgSoAAwkACQqiIfc2AA4DAAkACQpDIfc2AA4DAAgABQpqG1UQAHgBAAAA.Blinkzy:BAAANQADCgUICQABNQAECgkJMgAUAKkdAA==.Blitzoria:BAAANQADCgYIBgABNQAECgcIDgAEAAAAAA==.Bloui:BAAANQADCgYIFwAAAA==.Blueknight:BAABNQAECoEZAAMHAAcK/QWebQAZAQAHAAcK/QWebQAZAQAVAAIK/QWwuwBSAAAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Bobinsky:BAAANQADCgIIAwAAAA==.Borlok:BAAANQAECgYIHAAAAQ==.',
Br='Brannigan:BAABNQAECoEoAAIUAAkKjBskSQCVAgAUAAkKjBskSQCVAgAAAA==.Brannigandh:BAABNQAECoEaAAQLAAcKshgCCwD0AQALAAcKMhgCCwD0AQAWAAYKpw57OABZAQAGAAEKzRTNfQBAAAABNQAECgkJKAAUAIwbAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQADCgYIDAAAAA==.Briantu:BAAANQADCggJCAAAAA==.Brickfelt:BAAANQABCgYICgAAAA==.Brickitphil:BAAANQAECgcIEgAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Brustomp:BAAANQADCgYIBgABNQAECgIJAgAEAAAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAAANQAECgYIEQAAAA==.Bulldan:BAAANQADCgYIEQAAAA==.Bullvi:BAAANQAECgQIBQAAAA==.',
['Bä']='Bärkler:BAAANQAECgUJBgAAAA==.',
['Bé']='Béckléy:BAABNQAECoEXAAIXAAkKLSKvAwBFAwAXAAkKLSKvAwBFAwAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Cali:BAAANQADCgYIBgAAAA==.Cannïbal:BAAANQAECgUIBQAAAA==.Cara:BAAANQADCgMIBAAAAA==.Carra:BAABNQAECoEfAAIOAAgKmRHqYgAlAgAOAAgKmRHqYgAlAgAAAA==.Cassiopeía:BAEANQAECgQIBQABNQAECggICAAEAAAAAA==.Catriona:BAABNQAECoEZAAIOAAYKIwrSsQBsAQAOAAYKIwrSsQBsAQAAAA==.',
Ch='Charcuterie:BAACNQAFFIEWAAIYAAcKexBPAQDyAQAYAAcKexBPAQDyAQA1AAQKgR4AAhgACQqSIJ4FAOkCABgACQqSIJ4FAOkCAAAA.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheeze:BAAANQABCgUIBQABNQAECgUIEAAEAAAAAA==.Cheezeburg:BAAANQAECgUIEAAAAA==.Chicken:BAAANQAECgcICAABNQAFFAcIFgAKANsVAA==.Chikindalf:BAAANQADCgEJAQAAAA==.Chillidán:BAABNQAECoEcAAIWAAcKOgTlPAA1AQAWAAcKOgTlPAA1AQAAAA==.Choggie:BAABNQAECoEdAAIZAAgKgxSsUAAJAgAZAAgKgxSsUAAJAgAAAA==.Chulainn:BAAANQAECgUIBgAAAA==.',
Co='Cons:BAABNQAECoEtAAMMAAkKzyA8EAAwAwAMAAkKzyA8EAAwAwAaAAEKBAsnKAAuAAAAAA==.Corellon:BAABNQAECoEbAAIOAAgK2B9tKgDOAgAOAAgK2B9tKgDOAgAAAA==.',
Cr='Cranee:BAABNQAECoE4AAMQAAkKnBPGRgBhAgAQAAkKnBPGRgBhAgAPAAIKqQKSZABOAAAAAA==.Cranium:BAAANQAECggIEwAAAA==.Crazytasty:BAABNQAECoElAAIOAAgKlSNDGgAXAwAOAAgKlSNDGgAXAwAAAA==.Critcomander:BAAANQADCgYIBgAAAA==.',
Da='Dabora:BAABNQAECoErAAMTAAkKUyEPBgBdAwATAAkKUyEPBgBdAwAbAAIKEg50FgBkAAAAAA==.Damassan:BAAANQABCgYIBgAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYICwABNQAECgcIGQAOAD0JAA==.Darige:BAAANQAECgUIDwAAAA==.Darim:BAABNQAECoEiAAIFAAgKXSG7MADoAgAFAAgKXSG7MADoAgABNQADCgYIBgAEAAAAAA==.Darthspawn:BAAANQAECgUIDQAAAA==.Daryn:BAAANQAECgEIAQAAAA==.Davidbowy:BAAANQADCgQIBQABNQAECgIIAgAEAAAAAA==.',
De='Deadchops:BAAANQAECgIIAgABNQAECgUIBgAEAAAAAA==.Deathollow:BAAANQADCgYIBgAAAA==.Demonainkor:BAAANQAECgUIBgABNQAECgkJGgAHAHoaAA==.Demonicfury:BAAANQAECgIIAgAAAA==.Dencity:BAABNQAECoEsAAMMAAkKFh0GIQDPAgAMAAkKFh0GIQDPAgAaAAEK3wM4LAAjAAAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQADCgcICwABNQAECggIHQAZAAEYAA==.Devitodevour:BAABNQAECoEkAAMQAAgKwB0ZcADnAQAQAAYKhR0ZcADnAQAPAAIKcR7NQQCyAAAAAA==.Devwarr:BAAANQAECgUIDAABNQAECggIHQAZAAEYAA==.Dezard:BAAANQABCgIIAgAAAA==.',
Dh='Dhbert:BAAANQAECgIJAgAAAA==.Dhomeli:BAAANQAECgIIAwAAAA==.Dhometri:BAAANQADCgIIAgAAAA==.',
Di='Dirtchez:BAAANQAECgQIBAAAAA==.Disastrophy:BAAANQAECgUIBgAAAA==.Disturbed:BAABNQAECoEqAAQQAAkKJRiiQgBuAgAQAAgKKheiQgBuAgAPAAMKxRU7OQDRAAAcAAEKkwSrLwAoAAAAAA==.',
Dk='Dkson:BAACNQAFFIEMAAIHAAQKjh5SDABgAQAHAAQKjh5SDABgAQA1AAQKgSUAAgcACQp2IdgNADADAAcACQp2IdgNADADAAAA.',
Do='Docen:BAAANQAECgQIBwAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.Download:BAAANQADCggICAAAAA==.',
Dr='Dragonfist:BAAANQAECgQIBQAAAA==.Dragthyr:BAAANQADCgYIEgAAAA==.Druiaier:BAAANQAECgIIAgAAAA==.Druknatsu:BAAANQAECgQICQAAAA==.',
Du='Dustyknight:BAAANQAECgYIDQAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgcIEAAAAA==.',
Ec='Ecthan:BAAANQADCgQIBAAAAA==.',
Ed='Edge:BAABNQAECoEXAAICAAcKXh65NgBdAgACAAcKXh65NgBdAgAAAA==.',
El='Eleathe:BAAANQADCgYIBgAAAA==.Elgimpster:BAAANQADCgIIAgAAAA==.Elidoria:BAEBNQAECoEqAAIJAAkKLhlgVQDFAgAJAAkKLhlgVQDFAgAAAA==.Elphinia:BAAANQADCgYJBgABNQAECgkJKQADACkcAA==.',
En='Enoki:BAABNQAECoEVAAMDAAkK2R2AHQD/AgADAAkK2R2AHQD/AgACAAIKvArW5QBvAAABNQAFFAcIFAAZAOoSAA==.',
Ep='Ephodess:BAAANQAECgUICAAAAA==.',
Er='Eraduckated:BAABNQAECoEaAAMTAAgKdR3DGACOAgATAAcKQSDDGACOAgAbAAUKdREhDwAjAQAAAA==.',
Es='Esco:BAAANQAECgEIAQAAAA==.Esile:BAABNQAECoEfAAIdAAcKagtrHABqAQAdAAcKagtrHABqAQAAAA==.Esoryn:BAABNQAECoEmAAIFAAgKvSSgGABOAwAFAAgKvSSgGABOAwAAAA==.',
Ev='Everlife:BAAANQAECgEIBAAAAA==.Evilainkor:BAABNQAECoEaAAIHAAkKehqVHwCdAgAHAAkKehqVHwCdAgAAAA==.',
Ex='Exia:BAACNQAFFIEMAAIUAAUKdw4LEACHAQAUAAUKdw4LEACHAQA1AAQKgRcAAhQACQrjE8prAC4CABQACQrjE8prAC4CAAAA.',
Fa='Fauzzie:BAAANQAECgQICQAAAA==.Fayrel:BAAANQAECgYIEgAAAA==.',
Fe='Fedders:BAABNQAECoEoAAIFAAkKoCOzCACsAwAFAAkKoCOzCACsAwAAAA==.Felaids:BAABNQAECoElAAQQAAgKphiubwDoAQAQAAcKkxeubwDoAQAPAAIKvxWTUQB+AAAcAAIKDQnLHgBnAAAAAA==.Felnyx:BAAANQADCgYJCgAAAA==.Felstone:BAAANQABCgIIAgABNQADCgYIBgAEAAAAAA==.Feor:BAAANQAECgYICQAAAA==.Feralyn:BAAANQADCgYJCgAAAA==.Fero:BAAANQADCgUICAAAAA==.',
Fi='Fillon:BAACNQAFFIENAAIFAAQKcB1MCwBhAQAFAAQKcB1MCwBhAQA1AAQKgSIAAgUACQoWITooAAoDAAUACQoWITooAAoDAAAA.Fionas:BAAANQAECgUIDAAAAA==.Firexcracker:BAAANQADCgQJBAAAAA==.Fishfood:BAABNQAECoEhAAIVAAgKtBpRLABgAgAVAAgKtBpRLABgAgAAAA==.Fixer:BAAANQAECgEIAQAAAA==.',
Fl='Flappysnail:BAAANQADCgYICwAAAA==.Flatine:BAAANQADCgEIAQAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frazzle:BAAANQADCgMIAwABNQADCgcIBwAEAAAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAABNQAECoEfAAIJAAkKvBUOdACAAgAJAAkKvBUOdACAAgAAAA==.',
Fu='Fujitora:BAAANQAECgMIBQAAAA==.Funbunz:BAAANQAECgEIAQAAAA==.',
['Fø']='Førd:BAABNQAECoEtAAQdAAkKoByaCwCWAgAdAAkK/BiaCwCWAgAeAAgK/hd6BwAMAgAfAAUKKgXQNQDHAAAAAA==.',
Ga='Gahv:BAAANQADCgcIBwAAAA==.Galyte:BAAANQADCgMIAwAAAA==.Gangrene:BAABNQAECoEfAAIVAAgKsxD6SgDCAQAVAAgKsxD6SgDCAQAAAA==.Gaspasser:BAAANQAECgUIDQAAAA==.Gaviin:BAAANQAECgcIEwAAAA==.Gazamiseh:BAAANQABCgIIAgAAAA==.',
Ge='Gearador:BAAANQADCgMIBAAAAA==.Genovia:BAAANQADCgQIBAABNQAECggIBAAEAAAAAA==.Gerhart:BAABNQAECoEkAAMGAAgKUh45GAC4AgAGAAgKUh45GAC4AgALAAYKhBMpEwBIAQAAAA==.',
Gi='Gigarius:BAABNQAECoEZAAIgAAYKSiDLFQAqAgAgAAYKSiDLFQAqAgAAAA==.Gizelia:BAAANQADCgMIBAAAAA==.',
Gl='Gleya:BAAANQADCgYIBwAAAA==.Gloomy:BAAANQADCgYIBgAAAA==.',
Gn='Gnomestomper:BAAANQABCgIIAQAAAA==.',
Go='Goblinsrhot:BAAANQADCgcIFgAAAA==.Goncor:BAAANQAECgUIBgABNQAECgkJKAAMAAshAA==.Gorrelord:BAAANQADCgIIAgABNQAFFAQICgAJAOwPAA==.',
Gr='Gracze:BAAANQAECgUIBQAAAA==.Gramadingg:BAAANQADCgEIAQAAAA==.Granolah:BAAANQAECgQICwABNQAECgkJKwATAFMhAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgQIBwAAAA==.Greyback:BAAANQADCgMIAwAAAA==.Griffmonk:BAABNQAECoEdAAIhAAgKSBzWDQCBAgAhAAgKSBzWDQCBAgAAAA==.Grimoire:BAAANQAECgQIBAABNQAECgUIBgAEAAAAAA==.Grumpymage:BAABNQAECoElAAIIAAgKjSEWAwD+AgAIAAgKjSEWAwD+AgAAAA==.',
Gu='Gunjamomma:BAAANQADCgMIAwABNQAECgIIAgAEAAAAAA==.',
Ha='Hafsac:BAAANQAECgUICAAAAA==.Hamasakura:BAAANQADCggIDwAAAA==.Hardord:BAAANQAECgQIBgAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Haryle:BAAANQADCggICAAAAA==.Hayanne:BAABNQAECoEfAAIKAAgKHhg+DQAzAgAKAAgKHhg+DQAzAgAAAA==.',
He='Healchucky:BAAANQAECgIIAgAAAA==.Healzjoogewd:BAAANQADCgYIBgABNQADCgcIBwAEAAAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.Hexflex:BAAANQAECgEIAQAAAA==.',
Hi='Hikary:BAAANQABCgIIAgAAAA==.',
Ho='Hochunk:BAABNQAECoEcAAIMAAgKhRBUXwDSAQAMAAgKhRBUXwDSAQAAAA==.Holikow:BAAANQAECgUICgAAAA==.Holyherpies:BAAANQAECgIIAgAAAA==.Holyness:BAAANQAECgUIEQAAAA==.Honeybunz:BAAANQADCgMIBAAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAABNQAECoEaAAMgAAgKohMZIAC4AQAgAAgKcBMZIAC4AQAFAAcKrAthyABRAQABNQAFFAMIBwAfAEIeAA==.',
Hu='Hurano:BAAANQAECgYICQAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIDgAAAA==.',
Ic='Icekel:BAAANQADCgUIBQAAAA==.',
Id='Idyllwild:BAAANQADCggIGwAAAA==.',
Ih='Ihsan:BAAANQAECgYIBgAAAA==.',
Il='Ilharess:BAAANQADCggICAAAAA==.Illusiõn:BAAANQAECgQIBAAAAA==.',
In='Inducktive:BAAANQAECgEIAQABNQAECggIGgATAHUdAA==.Inkdot:BAABNQAECoEjAAMZAAgKGiBbHwDcAgAZAAgKGiBbHwDcAgAFAAYKZBPEvgBmAQAAAA==.Inkshield:BAAANQADCgYIBgABNQAECggICgAEAAAAAA==.Inkwell:BAAANQADCgYIBgABNQAECggIIwAZABogAA==.Innerlight:BAAANQAECgEIAQAAAA==.',
Io='Iomedáe:BAAANQADCgMIAwAAAA==.',
Ir='Irishnight:BAAANQADCgQICgABNQAECggIIwAiANUSAA==.Ironlightnin:BAAANQADCgUIBQAAAA==.Irritate:BAAANQAECgEIAQAAAA==.',
Ja='Jakobo:BAAANQAECggIEgAAAA==.Jandreyn:BAAANQADCgEIAQAAAA==.Jarkus:BAAANQADCgIIAgAAAA==.Jarthas:BAAANQADCgYIDQAAAA==.Jazlynel:BAAANQADCgYIBgAAAA==.',
Je='Jelly:BAACNQAFFIEUAAIZAAcK6hL5AgBNAgAZAAcK6hL5AgBNAgA1AAQKgSYAAxkACQoiIY8LAF0DABkACQoiIY8LAF0DAAUAAQrdH6BfAUYAAAAA.Jenivira:BAAANQADCgMIAwAAAA==.',
Ji='Jimbostein:BAAANQADCgMIAwAAAA==.',
Jo='Johnnyblaze:BAAANQADCgIIAgAAAA==.Jozalin:BAAANQADCgQIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgMIBgAAAA==.Junknthtrunk:BAAANQADCgYJCAAAAA==.',
Ka='Kaelana:BAAANQABCgQJBQAAAA==.Kamahl:BAABNQAECoEVAAIUAAgKXxNZdgARAgAUAAgKXxNZdgARAgAAAA==.',
Ke='Keanew:BAABNQAECoEbAAMGAAYKShNwQgB2AQAGAAYKShNwQgB2AQALAAEK6Q6eLAAtAAAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIIgAAAA==.Keonna:BAAANQADCgYIEwAAAA==.Keppra:BAAANQAECgEIAQAAAA==.Kerlin:BAAANQAECggIEwAAAA==.',
Kh='Kheilah:BAAANQADCgEIAQAAAA==.Khurst:BAAANQAECgQIBAAAAA==.',
Ki='Kilaben:BAAANQAECgQIBwAAAA==.Kimmex:BAAANQADCgMIBAAAAA==.Kinoxo:BAACNQAFFIEUAAIUAAcKox28AgCgAgAUAAcKox28AgCgAgA1AAQKgS4AAxQACQpyJPkQAHMDABQACQpyJPkQAHMDACMAAQpIIQMmAFsAAAAA.Kinozo:BAAANQAECgMIAwAAAA==.Kitsunë:BAAANQADCgYIBgAAAA==.Kittyclysm:BAAANQADCgcIDQAAAA==.',
Ko='Kossuth:BAAANQABCgEIAQAAAA==.Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQADCgYICgAAAA==.Krampusnacht:BAAANQADCgYIBgAAAA==.Krissycat:BAAANQAECgQIBAAAAA==.',
La='Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgYIDgABNQAECgkJMgAUAKkdAA==.Leditoo:BAAANQADCggICAAAAA==.Legnase:BAABNQAECoEiAAIMAAgKPSD+HwDUAgAMAAgKPSD+HwDUAgAAAA==.Leiche:BAAANQAECgIIBQAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Liferia:BAAANQAECgYICAABNQAECgcIDAAEAAAAAA==.Ligmabonez:BAAANQADCgcIFgAAAA==.Lilchloe:BAAANQADCgMIBAAAAA==.Lilnasty:BAAANQADCgMIAwABNQAECgYIGgACABwSAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Littlefry:BAAANQABCgEIAQAAAA==.Livesey:BAAANQAECgYIDgAAAA==.',
Lo='Lockpie:BAAANQADCgQIBAAAAA==.Longshañk:BAABNQAECoEYAAIkAAkKWBdmAwC2AgAkAAkKWBdmAwC2AgAAAA==.',
Lu='Lucibrew:BAABNQAECoEcAAMBAAkKrR/FDwDMAgABAAkKJxzFDwDMAgAYAAcKLyB9CgBPAgAAAA==.Luto:BAAANQAECggIDAAAAA==.Luuko:BAAANQADCgMIAwAAAA==.',
Ma='Mackaveli:BAAANQADCgUIBQAAAA==.Macpreizy:BAAANQADCgQIEQAAAA==.Mattydruid:BAAANQAECgMIBwAAAA==.Mavramune:BAABNQAECoEnAAIOAAkKsRfgQQCAAgAOAAkKsRfgQQCAAgAAAA==.',
Mc='Mcfizzertz:BAAANQAECggIBAAAAA==.Mcfürry:BAAANQAECgIIAgAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECggIIwARACgfAA==.Mendinna:BAAANQADCggIHQABNQAECgUIEQAEAAAAAA==.Mendool:BAAANQADCgcIBwABNQAECgUIEQAEAAAAAA==.Mendoon:BAAANQAECgUIEQAAAA==.Methir:BAAANQADCggIEgABNQAECgYIHAAEAAAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAACNQAFFIEQAAIOAAUKjxgoBwCyAQAOAAUKjxgoBwCyAQA1AAQKgTIAAg4ACQoDJqQCANQDAA4ACQoDJqQCANQDAAAA.Mistborn:BAAANQAECggIBwABNQAECggICgAEAAAAAA==.',
Mo='Moistmaker:BAAANQAECgQIBQAAAA==.Moneygame:BAAANQAECgUICgABNQAECggIMQAGAJslAA==.Montebrew:BAAANQADCgYIBgABNQADCgcIDAAEAAAAAA==.Montecane:BAAANQADCgcIDAAAAA==.Mooferrigno:BAAANQAECgcIBwABNQAECgkJGgALAFYeAA==.Mooky:BAABNQAECoEZAAIlAAgKYgnFSgCQAQAlAAgKYgnFSgCQAQAAAA==.Moonfire:BAAANQAECggJCAAAAA==.Moriang:BAAANQADCgEIAQAAAA==.Moshicat:BAAANQAECgUIBwAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAABNQAECoEWAAMcAAYKxhPoDQBQAQAcAAUK4RPoDQBQAQAQAAQKiw3k2gDnAAAAAA==.Mythallas:BAAANQADCgIIAgAAAA==.',
Na='Nakir:BAAANQAECgQIDgAAAA==.Naraku:BAABNQAECoEyAAMQAAkKoB8iTABQAgAQAAcKax0iTABQAgAPAAQKyxzGIABgAQAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neebiter:BAABNQAECoEYAAIQAAgKIBA+agD3AQAQAAgKIBA+agD3AQAAAA==.Nehemez:BAAANQADCggICAABNQAECgEIAQAEAAAAAA==.Neshock:BAAANQAECgIIAgABNQAECggIDQAEAAAAAA==.Nettie:BAAANQAECgQICQAAAA==.Netty:BAAANQAECgQIBgABNQAECgQICQAEAAAAAA==.',
No='Noctyra:BAAANQADCgMIAwAAAA==.Novakayne:BAAANQADCgMIBAAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.',
Ny='Nymphetamine:BAAANQAECgYIEQAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAABNQAECoEjAAImAAgKUg9mKQDdAQAmAAgKUg9mKQDdAQAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ou='Ouinur:BAAANQABCggICAABNQAECgUIEAAEAAAAAA==.',
Ow='Owenwilson:BAAANQAECgEIAQAAAA==.',
Pa='Pandaloco:BAAANQAECgMIAwAAAA==.Pandalôc:BAAANQAECgQICQAAAA==.Pandoe:BAACNQAFFIEaAAIiAAYKACNDAABuAgAiAAYKACNDAABuAgA1AAQKgTEAAiIACQqlJlsAAP8DACIACQqlJlsAAP8DAAAA.',
Pe='Penelopea:BAAANQAECgYIEQAAAA==.Perun:BAAANQAECgYIEQAAAA==.',
Ph='Phaithfulnes:BAAANQADCgUIBQABNQAECgUIEQAEAAAAAA==.Phenomenal:BAAANQAECgUIDgAAAA==.Pheonyx:BAAANQADCggIEwAAAA==.',
Pi='Picarus:BAAANQADCgYIBgAAAA==.Picklerìck:BAAANQAECgYICwAAAA==.',
Pl='Planb:BAAANQAECgUJCwABNQAECgkJOAAQAJwTAA==.',
Pn='Pneumonya:BAAANQAECgMIAwAAAA==.',
Po='Porteagarder:BAAANQAECgQIBAABNQAECgcIDgAEAAAAAA==.',
Pr='Preparedpie:BAACNQAFFIEPAAMGAAUKHxAtCQBpAQAGAAUKswotCQBpAQAWAAQKERDGCAA1AQA1AAQKgTQAAxYACQowIloHAFQDABYACQphIVoHAFQDAAYABgoRGi41ANEBAAAA.Priarace:BAAANQAECgQIBQABNQAECgYICAAEAAAAAA==.Pringler:BAAANQAECgYICgABNQAFFAcIFgAKANsVAA==.Producktive:BAAANQAECgIIAgABNQAECggIGgATAHUdAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQADCggIHAABNQAECgcIHwAdAGoLAA==.Príestly:BAAANQAECgYIDAAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQAECgQIBAAAAA==.',
Py='Pyatt:BAABNQAECoEeAAIcAAgKhRjtBABbAgAcAAgKhRjtBABbAgAAAA==.Pyromaniacal:BAAANQAECgQIBQAAAA==.',
['Pä']='Pändaloc:BAAANQADCgQIBAAAAA==.',
Qe='Qe:BAAANQADCgQIBAAAAA==.',
Qu='Quack:BAABNQAECoENAAIUAAcKCxI5mwCuAQAUAAcKCxI5mwCuAQAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECggIDQAUAAsSAA==.Quesoblanco:BAAANQADCgUICQAAAA==.Quilae:BAAANQADCggIJQABNQAECgcIDgAEAAAAAA==.',
Qy='Qyburn:BAABNQAECoEYAAMTAAgKJx7sGgB9AgATAAgKJx7sGgB9AgASAAMKeBbgNwDVAAAAAA==.',
Ra='Radioface:BAAANQADCggICgAAAA==.Raerlynn:BAEANQADCgcJBwABNQAECgUIEAAEAAAAAA==.Ragecage:BAAANQAECgIIAgABNQAECgkJFwAQAFcXAA==.Randivh:BAAANQADCgYIDAAAAA==.Rassputin:BAAANQAECgUIDQAAAA==.',
Re='Recipes:BAAANQAECgcIDQABNQAECggICgAEAAAAAA==.Redbeardd:BAAANQADCgcIDwAAAA==.Reigwend:BAAANQADCgMIBQAAAA==.Remish:BAAANQABCgQIBgABNQAECgUICAAEAAAAAA==.Rendezvous:BAAANQAECgEIAQAAAA==.Renkà:BAABNQAECoEpAAIDAAkKKRzgIQDkAgADAAkKKRzgIQDkAgAAAA==.Resmondo:BAAANQADCgcICQAAAA==.Revaerlous:BAABNQAECoEsAAIVAAkKNh/qFgDsAgAVAAkKNh/qFgDsAgAAAA==.Reyanne:BAAANQAECgMIAwABNQAECgQIBgAEAAAAAA==.',
Rh='Rheas:BAAANQADCgYIDAABNQAECggIBAAEAAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAcIFgAKANsVAA==.',
Rn='Rn:BAAANQADCgQIBAAAAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roereker:BAAANQADCggICAAAAA==.Roflsummon:BAAANQADCgEJAQABNQAECggIBAAEAAAAAA==.Roflthump:BAAANQADCgcJBwAAAA==.Roketraccoon:BAAANQADCggIFgAAAA==.Rootbreaker:BAAANQAECgEIAQABNQAECgUIBgAEAAAAAA==.Rosamyna:BAEANQADCgMIAwABNQAECgUIEAAEAAAAAA==.Roshamandes:BAABNQAECoEfAAILAAgK/Bb0CQASAgALAAgK/Bb0CQASAgAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAgABNQAECgcIGQAHAP0FAA==.Runep:BAAANQAECgEIAQAAAA==.',
['Rè']='Rèi:BAAANQAECgEIAwABNQAECggIJQAOAJUjAA==.',
Sa='Sabermage:BAAANQAECgYICQAAAA==.Sacredchikín:BAABNQAECoEdAAMQAAgKSR5rMQCoAgAQAAgKSR5rMQCoAgAPAAEKuBRabwA6AAAAAA==.Samuel:BAAANQAECgIIAwAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Sasukie:BAAANQAECgQICAAAAA==.Saxa:BAABNQAECoEjAAIWAAgKSiPtCQAuAwAWAAgKSiPtCQAuAwAAAA==.',
Sc='Screamsoda:BAAANQAECgUICAABNQAECggICgAEAAAAAA==.Scrubzz:BAAANQAECgUJCwAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekobrew:BAAANQADCgYIBgAAAA==.Seyekolock:BAAANQAECgQIDgAAAA==.Seyekosis:BAAANQAECgYIEAAAAA==.',
Sg='Sgathaich:BAEANQAECgUIBwAAAA==.',
Sh='Shadowzform:BAAANQABCgYIBAABNQAECgQICAAEAAAAAA==.Shallistiah:BAABNQAECoEiAAMlAAgKBA3yRACwAQAlAAgKBA3yRACwAQAnAAYKwQw4OgAXAQAAAA==.Shamadin:BAAANQAECgMIAwAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgUICgAAAA==.Shamdh:BAAANQAECgYIDAAAAA==.Shamdwarf:BAAANQAECgQIBAAAAA==.Shamuel:BAAANQADCgYIBgAAAA==.Shiftnfard:BAAANQADCggIDgAAAA==.Shobadon:BAAANQAECggICAAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgQICAAAAA==.',
Si='Siatral:BAACNQAFFIEHAAIfAAMKQh4CDQAPAQAfAAMKQh4CDQAPAQA1AAQKgScAAx8ACQqsImQEAGIDAB8ACQqsImQEAGIDAB4AAQruEg0fADoAAAAA.Siete:BAAANQAECgQICQAAAA==.Siggopotomus:BAAANQAECgMIBAABNQAECggIBAAEAAAAAA==.Sigvolden:BAAANQAECgEJAQABNQAECggIBAAEAAAAAA==.Silchar:BAAANQADCgEIAQAAAA==.Silicon:BAABNQAECoEbAAMIAAgK5Q0/DQCtAQAIAAgKew0/DQCtAQAJAAYKHwPNOAEKAQAAAA==.Silver:BAAANQAECgIIAgABNQAECggIGwAIAOUNAA==.Siona:BAABNQAECoEfAAIOAAgKtgYmkQC1AQAOAAgKtgYmkQC1AQAAAA==.Sixpaths:BAAANQAECgYIEwABNQAECggICgAEAAAAAA==.Siyunkai:BAEANQAECgIIAwAAAA==.Siyunzu:BAEANQAECgIIAgABNQAECgIIAwAEAAAAAA==.',
Sk='Skadie:BAABNQAECoEfAAIOAAgKHBMBXQA0AgAOAAgKHBMBXQA0AgAAAA==.Skittellz:BAAANQABCgMIAwAAAA==.Skiye:BAAANQADCgcIBwAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgAEAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgAEAAAAAA==.Skwup:BAABNQAECoEmAAMZAAkKQBq9JQC7AgAZAAkKQBq9JQC7AgAFAAQKKRaW8wD9AAAAAA==.',
Sl='Slackness:BAAANQAECgEIAQAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slappygilmor:BAAANQADCgcIBwAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggJCQABNQAFFAQICgAJAOwPAA==.Sleepybeard:BAAANQAECgQICAAAAA==.Slubadub:BAABNQAECoEaAAQLAAkKVh7MCgD6AQAWAAgK7RpcGQB1AgALAAUKzSLMCgD6AQAGAAUK8BLeSwA3AQAAAA==.',
Sm='Smiteslay:BAAANQAECgUJCgABNQAFFAQICgAJAOwPAA==.',
Sn='Snivels:BAAANQAECgUIDQAAAA==.Snïpe:BAAANQABCgQIBAAAAA==.',
So='So:BAAANQAECgUIDgAAAA==.Soggycat:BAEANQADCgEIAQAAAA==.Soil:BAABNQAECoEeAAIcAAgK4CHPAQAGAwAcAAgK4CHPAQAGAwAAAA==.Somna:BAAANQAECgUJCwAAAA==.',
Sp='Sparrkle:BAABNQAECoEjAAIPAAgKdgX6IgBOAQAPAAgKdgX6IgBOAQAAAA==.Spayme:BAAANQAECgEIAQAAAA==.Spinecrawler:BAABNQAECoEXAAIQAAkKVxdpTQBMAgAQAAkKVxdpTQBMAgAAAA==.Spyro:BAAANQAECgEIAQAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Staryknight:BAAANQAECgIIAgAAAA==.Steelrat:BAAANQADCgMIBAAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stickshamm:BAAANQAECgEIAQAAAA==.Stiick:BAABNQAECoEfAAIgAAgKDhihFQAsAgAgAAgKDhihFQAsAgAAAA==.Stonecracker:BAAANQADCgMIBAAAAA==.Stìmpak:BAAANQADCgYIDwABNQAECgUIBgAEAAAAAA==.Stöut:BAAANQABCgIIAgABNQAECgUIBgAEAAAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.Sudsy:BAAANQADCgUICAABNQAECgYIEQAEAAAAAA==.Supadupaman:BAAANQAECggICAAAAA==.Supaman:BAAANQABCgUIBQAAAA==.',
Sw='Sweetbippy:BAAANQAECgUIBQAAAA==.Swifthealss:BAAANQAECgYIEgAAAA==.Swirls:BAAANQADCggICQAAAA==.',
Sy='Sylunae:BAAANQADCgcIGQABNQAECgcIDgAEAAAAAA==.Syluné:BAAANQAECgcIDgAAAA==.',
Ta='Tacoshaman:BAAANQADCgIJAgABNQAECgIIAgAEAAAAAA==.Tacozpriest:BAAANQAECgIIAgAAAA==.Taelyx:BAAANQAECgYIEwAAAA==.Tambot:BAAANQAECgYICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgYIEQAAAA==.Tazmina:BAABNQAECoEhAAIGAAYKEh+COAC5AQAGAAYKEh+COAC5AQAAAA==.',
Te='Teddykgb:BAAANQAECgEIAgAAAA==.Tequilàrose:BAAANQADCgIIAwABNQADCgcIBwAEAAAAAA==.Tessa:BAABNQAECoEfAAIDAAgKAxOwUwD9AQADAAgKAxOwUwD9AQAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAABNQAECoEgAAMMAAkKYR3SJgCyAgAMAAgKnR7SJgCyAgANAAcKJhM7JwDKAQAAAA==.Thalooze:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinkey:BAAANQAECgMIAwAAAA==.Tinyjapeto:BAAANQAECgQICAAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAABNQAECoEfAAIOAAgKeB3mKgDMAgAOAAgKeB3mKgDMAgAAAA==.Tortapounder:BAAANQAECgQICQAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgUICwAAAA==.',
Tu='Turin:BAABNQAECoEjAAIKAAgKnQzSFwCBAQAKAAgKnQzSFwCBAQAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twiggysmalls:BAAANQADCgUIBAAAAA==.Twilghtdawn:BAAANQADCgUIBQAAAA==.Twotone:BAAANQAECggICAAAAA==.',
Ty='Tybo:BAAANQAECgUIDgAAAA==.Tycho:BAAANQADCgYIDQAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.Tydros:BAAANQADCggICAAAAA==.',
Un='Uncás:BAABNQAECoEVAAIOAAUKeQnMzAA0AQAOAAUKeQnMzAA0AQAAAA==.Undyinggnome:BAAANQADCggIGQAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Va='Vaelock:BAAANQAECgYIEgAAAA==.Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQAECgQIBAAAAA==.Valoryan:BAABNQAECoEfAAInAAgKzRjaGABPAgAnAAgKzRjaGABPAgAAAA==.Valy:BAAANQADCgcIBwAAAA==.Valyteilssra:BAAANQADCgcICwAAAA==.Vasoline:BAAANQAECgYIBwABNQAECggIEQAEAAAAAA==.Vaxtur:BAAANQAECggJCAAAAA==.',
Ve='Vegà:BAABNQAECoEbAAMYAAYKwxB5FwBIAQAYAAYKwxB5FwBIAQABAAQKrgfUSwCUAAAAAA==.Vendettis:BAAANQAECgEIAQAAAA==.Vextaerin:BAAANQAECgUIBwAAAA==.Vextarin:BAAANQADCgYJBgABNQAECgUIBwAEAAAAAA==.Veylyn:BAABNQAECoEaAAIFAAYKdwnx3gAjAQAFAAYKdwnx3gAjAQAAAA==.Veztaroth:BAABNQAECoEbAAIVAAcKTxDDVwCKAQAVAAcKTxDDVwCKAQAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQAECgIIAgAAAA==.Voidyo:BAABNQAECoEqAAMWAAkKzCN6CQA1AwAWAAgKfSV6CQA1AwAGAAgKlR7IGACzAgAAAA==.',
['Vë']='Vëngeåncelöt:BAAANQADCgQIBAAAAA==.',
We='Weißenacht:BAAANQABCgUIBQAAAA==.',
Wh='Whiskeyjak:BAABNQAECoEZAAMUAAgKLBHXlADAAQAUAAgKPgvXlADAAQAKAAMKlxpXJgDdAAAAAA==.Whycatihealu:BAAANQADCgQIBAAAAA==.',
Wi='Willowbark:BAAANQADCgYIEwAAAA==.Willowest:BAABNQAECoEtAAIOAAkK6SFjEQBHAwAOAAkK6SFjEQBHAwAAAA==.Wizbizzler:BAAANQAECgYJDgAAAA==.',
Wr='Wrathstorm:BAABNQAECoEjAAIRAAgKKB9lCADiAgARAAgKKB9lCADiAgAAAA==.',
Xa='Xalatoes:BAAANQABCgYICAAAAA==.Xanier:BAAANQADCgYIGAABNQAECgUIDgAEAAAAAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAAANQAECgYIEAAAAA==.Xithia:BAEANQAECgYIDAAAAA==.',
Xo='Xorm:BAAANQAECggICAAAAA==.',
Xx='Xxcor:BAAANQADCggIEwAAAA==.',
Xy='Xyndylyne:BAAANQADCgcIBwAAAA==.',
Ya='Yahtze:BAAANQADCgYIBgAAAA==.Yanella:BAABNQAECoEZAAIMAAgKxhdjTAAXAgAMAAgKxhdjTAAXAgAAAA==.',
Yi='Yisdk:BAAANQAECgUICQAAAA==.Yisshaman:BAAANQAECgcIEQAAAA==.',
Yo='Yogibearz:BAAANQAECgEIAQABNQAECgQICQAEAAAAAA==.',
Yu='Yunbao:BAAANQADCgMIBAAAAA==.',
Za='Zaijr:BAAANQAECgMIAwAAAA==.Zanax:BAAANQAECgUICgAAAA==.Zandarbribbs:BAAANQAECgIIAwAAAA==.Zarrah:BAAANQABCgYICgAAAA==.',
Ze='Zennya:BAABNQAECoEWAAInAAgKsx4aEgChAgAnAAgKsx4aEgChAgAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.Zenthora:BAAANQADCgIIAgAAAA==.',
Zo='Zoldyck:BAAANQADCggIHgAAAA==.',
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
