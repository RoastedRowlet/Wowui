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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Evoker-Augmentation','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Unknown-Unknown','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','Shaman-Restoration','Hunter-Survival','Mage-Arcane','Paladin-Protection','Shaman-Elemental','Priest-Holy','Priest-Shadow','DeathKnight-Frost','Mage-Fire','Warrior-Fury','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgkJMQABAKEhAA==.Aaronfreeze:BAABNQAECn8uAAICAAkKsiJqHgAcAwACAAkKsiJqHgAcAwAAAA==.',
Ab='Abnar:BAAANQAECgYIEQAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUIBQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAECgkJNwADAIsjAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggJDAAAAA==.Alucard:BAABNQAECn8oAAIEAAgKLxbBUgAfAgAEAAgKLxbBUgAfAgAAAA==.Alystrasza:BAABNQAECn8pAAMFAAkKFx3gDAD9AgAFAAkKFx3gDAD9AgAGAAcKLg3fVwBxAQAAAA==.',
Am='Ambivalent:BAAANQAECgQIBwABNQAECgYIGwAHAIQVAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICgAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgcIJwACAGAhAA==.',
Ar='Arrowsmïth:BAAANQADCgUIBwAAAA==.',
Au='Auroras:BAAANQAECgIIAgAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAABNQAECn8eAAMIAAkKZB7yHwDJAgAIAAkKZB7yHwDJAgAJAAEK1QVRzgAtAAABNQAECgkJNwADAIsjAA==.',
['Aü']='Aütöpsy:BAABNQAECn8hAAIKAAgK/BgEEgBhAgAKAAgK/BgEEgBhAgAAAA==.',
Ba='Baarda:BAAANQADCgQIBAABNQAECggIGwALAEsQAA==.Babylonfive:BAABNQAECn87AAIMAAkKQSXWBADSAwAMAAkKQSXWBADSAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgMIBgAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAABNQAECn8bAAIHAAYKhBUJMAC9AQAHAAYKhBUJMAC9AQAAAA==.Berserk:BAEBNQAECn8ZAAMNAAgKYRYkcwA3AgANAAgK5BQkcwA3AgAOAAYKIBNRHgBdAQABNQAFFAQIBgAPAHICAA==.Bertringer:BAAANQAECgMIAwABNQAECgQIBQAQAAAAAA==.',
Bi='Bigthiccboi:BAAANQAECgQIBQAAAA==.Bigwave:BAAANQADCggIDQAAAA==.Bigwilli:BAAANQADCgYIDQAAAA==.Bilefiend:BAAANQADCgMIAwAAAA==.Birds:BAACNQAFFH8LAAIRAAMKVBPXBADVAAARAAMKVBPXBADVAAA1AAQKfycABBEACQpCIDcGACwDABEACQpCIDcGACwDABIABwoRE+oRAN4BAAYAAQoAAM20ACsAAAAA.Biscuit:BAACNQAFFH8TAAMCAAUKLRyNCwCSAQACAAUK2BiNCwCSAQATAAQKIwvIEwD+AAA1AAQKfyQAAwIACAo6JSU3AMMCAAIACAowJSU3AMMCABMABwptIdMmABECAAAA.Bisha:BAABNQAECn9AAAINAAkKGSEVFQBkAwANAAkKGSEVFQBkAwAAAA==.Bizcocho:BAAANQAECgYIDQAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boomkingobrr:BAAANQAECgYJCQAAAA==.Boops:BAABNQAFFH8LAAIUAAMKkQoqGQDNAAAUAAMKkQoqGQDNAAAAAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAABNQAECn8cAAIOAAcK7CCACwCAAgAOAAcK7CCACwCAAgAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Burnsx:BAAANQADCggIGAABNQAFFAcIFwAHAC8eAA==.',
Bw='Bwoar:BAAANQAECgcIDwAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAABNQAECn8bAAMVAAgKOhxvBACeAgAVAAgKOhxvBACeAgACAAEKNBZrRgFKAAAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQAECgQIBwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAABNQAECn8VAAICAAcKtRPPngDFAQACAAcKtRPPngDFAQAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAABNQAECn8YAAIEAAgKZBW4WAAMAgAEAAgKZBW4WAAMAgAAAA==.',
Ci='Cirxe:BAABNQAECn8kAAIWAAgKMgUgDAF1AQAWAAgKMgUgDAF1AQAAAA==.',
Cl='Clarkent:BAAANQAECgUICAAAAA==.',
Co='Coms:BAAANQAECgcIEgAAAA==.',
Cr='Crayze:BAAANQAECgIIBgAAAA==.',
['Cø']='Cønstance:BAABNQAECn8WAAIRAAgKBxozDQCPAgARAAgKBxozDQCPAgAAAA==.',
Da='Dabai:BAABNQAECn8nAAIMAAkKfBRJagBaAgAMAAkKfBRJagBaAgAAAA==.Daipailaotie:BAABNQAECn8eAAMMAAgKQQfC0AB0AQAMAAgKsAbC0AB0AQAXAAQKVQZcVQCIAAAAAA==.Dalight:BAAANQAECgUICAAAAA==.Dankins:BAABNQAFFH8PAAIUAAUK4B0hCADNAQAUAAUK4B0hCADNAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMJAwAAAA==.',
De='Deathmager:BAAANQADCggIDAAAAA==.Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIIAgAAAA==.Dette:BAAANQAECgUIDQAAAA==.Devourer:BAABNQAECn9GAAIHAAkKpiIRAwCnAwAHAAkKpiIRAwCnAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECgcIHAAOAOwgAA==.',
Do='Doctrdoom:BAAANQADCggIEwABNQAECgkJMQABAKEhAA==.',
Dr='Drafted:BAAANQAECgYIDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIDwAUAOAdAA==.Drukah:BAAANQADCgcIGgAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAABNQAECn8gAAIDAAcK0wKnZgDZAAADAAcK0wKnZgDZAAAAAA==.',
El='Elabernathy:BAAANQAECgYIDgAAAA==.Elenay:BAABNQAECn8bAAIGAAgKbiH/FAAdAwAGAAgKbiH/FAAdAwAAAA==.Eliarssande:BAAANQAECgYIDAAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECn8tAAIFAAkKEyJrBQBqAwAFAAkKEyJrBQBqAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECn8jAAIIAAcKbiKmLQB5AgAIAAcKbiKmLQB5AgABNQAECgkJRAAMAGQmAA==.Emulsifier:BAABNQAECn9EAAIMAAkKZCYAAgDyAwAMAAkKZCYAAgDyAwAAAA==.Emulslash:BAAANQADCgYIDAABNQAECgkJRAAMAGQmAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgcIJwACAGAhAA==.',
Ex='Expiatory:BAAANQADCgEIAQAAAA==.Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQAECgQIBAAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAAANQAFFAEIAQAAAA==.',
Fl='Flatline:BAAANQAECgYIDwAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAAANQAECgYIDwABNQAECgkJRAAMAGQmAA==.',
Go='Gorska:BAABNQAECn8hAAIYAAgKBxtxNQCeAgAYAAgKBxtxNQCeAgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECgcIBwABNQAECgkJMQABAKEhAA==.',
['Gä']='Gämbit:BAAANQAECgUIBQAAAA==.',
Ha='Hangman:BAAANQAECgYIDQAAAA==.Hanni:BAAANQAECgUIBQAAAA==.Harakutoo:BAAANQADCgcIBwAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAABNQAECn8iAAMZAAcKrBxnQQBiAgAZAAcKrBxnQQBiAgAaAAEKAACNfgArAAAAAA==.',
He='Hellshand:BAAANQAECgUICQAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Hi='Hinxx:BAAANQAECgMIAwAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAAANQAECgYIEQABNQAECgkJIQABAE8hAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgcICAABNQAECggIGwALAEsQAA==.Holypawk:BAABNQAECn8WAAIXAAgK5BeOGwAOAgAXAAgK5BeOGwAOAgAAAA==.Holyrock:BAAANQAECgYIDgAAAA==.Honorheart:BAAANQADCgMIBgAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYJCQAQAAAAAA==.',
Ih='Ihureciv:BAABNQAECn8bAAITAAcKIBtFIgA4AgATAAcKIBtFIgA4AgABNQAECgkJTgAaACEkAA==.',
Ik='Ikur:BAABNQAECn8qAAIEAAkK5hqTJwDIAgAEAAkK5hqTJwDIAgAAAA==.',
Ip='Ipopkidneys:BAACNQAFFH8WAAMKAAYKMSSZBADdAQAKAAUK8COZBADdAQAPAAEK8iQXGgBiAAA1AAQKfyQAAwoACQpVJZUMAKoCAAoABwr+JZUMAKoCAA8ABAo3JKhPAHoBAAAA.',
Ir='Iroi:BAAANQAECgIJAgAAAA==.',
Is='Iskur:BAAANQAECgYIEQABNQAECgkJKgAEAOYaAA==.Isurr:BAAANQAECgUIDQABNQAECgkJKgAEAOYaAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgIIBAAAAA==.Jametrok:BAABNQAECn8aAAIMAAgK4BVbkgD7AQAMAAgK4BVbkgD7AQAAAA==.Jastra:BAAANQADCgcIDgAAAA==.',
Je='Jennyanydots:BAAANQADCggICwABNQAFFAcIFwAaABESAA==.',
Ji='Jiraîya:BAAANQAECggIEgAAAA==.',
Jo='Jordak:BAABNQAECn8gAAIFAAgKbx3zEgCzAgAFAAgKbx3zEgCzAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAABNQAECn8cAAIWAAcK6hOS4QDCAQAWAAcK6hOS4QDCAQAAAA==.Just:BAABNQAECn8YAAMIAAgKhhApVwCxAQAIAAgKNxApVwCxAQAbAAQKFAtSdQDEAAAAAA==.',
Ka='Kaddiya:BAAANQADCgMIAwAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAABNQAECn8jAAIUAAgK/hZ1TgAnAgAUAAgK/hZ1TgAnAgAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.Katalaana:BAAANQAECgEIAQAAAA==.',
Ke='Kevdogg:BAABNQAECn8cAAMWAAcKJwUbLQE9AQAWAAcKaQQbLQE9AQAcAAEKlQVNDgAuAAAAAA==.Key:BAACNQAFFH8LAAMMAAQKNCBoDgBgAQAMAAQKNCBoDgBgAQAEAAEKbwsFJwBOAAA1AAQKfyYAAwwACQpCJS8uAA0DAAwACQpCJS8uAA0DAAQABwr/FM91ALMBAAAA.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQICAABNQAFFAMICwARAFQTAA==.',
Ko='Koluvan:BAAANQADCggIGQAAAA==.Koopa:BAABNQAECn8cAAIdAAgKZCBNBQDOAgAdAAgKZCBNBQDOAgAAAA==.',
Kr='Krieg:BAAANQAECgYIBgABNQAFFAUICQAGAFAjAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAABNQAECn9OAAMaAAkKISTAAgCvAwAaAAkKISTAAgCvAwAZAAQKWhaKpgAcAQAAAA==.',
Li='Lillianna:BAAANQAECgYIEgAAAA==.Lilsensual:BAABNQAECn8eAAIUAAgKahPoYgDhAQAUAAgKahPoYgDhAQABNQAECgkJMgAXAE8cAA==.',
Lo='Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAABNQAECn8bAAIXAAgKjxHwJQCsAQAXAAgKjxHwJQCsAQAAAA==.Lucário:BAABNQAECn8fAAINAAgKcyRhFwBaAwANAAgKcyRhFwBaAwAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAAANQAECgYICwAAAA==.Lunastorm:BAABNQAECn89AAIeAAkKeBswDgDDAgAeAAkKeBswDgDDAgAAAA==.Luponero:BAACNQAFFH8aAAMTAAYKzBu5CgCPAQATAAUK/hy5CgCPAQACAAEKNhggLgBiAAA1AAQKfyMAAxMACQpNIGMYAJICABMACQrjH2MYAJICAAIAAQoCJEpCAVIAAAAA.',
Ma='Macmn:BAACNQAFFH8LAAIYAAUKmB10CQDRAQAYAAUKmB10CQDRAQA1AAQKfycAAhgACQoUJsQFALsDABgACQoUJsQFALsDAAAA.Magej:BAAANQADCgQIBAAAAA==.Mageyouacake:BAAANQADCgQIBAAAAA==.Mamaheals:BAABNQAECn8gAAIZAAgKLiODFwAYAwAZAAgKLiODFwAYAwAAAA==.Mandos:BAABNQAECn8mAAIJAAgKOSU6DABPAwAJAAgKOSU6DABPAwAAAA==.Mantistabogn:BAAANQAECgYICAAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAQIEgAYAHwZAA==.Merlini:BAABNQAECn8eAAMaAAgKIxETJgD6AQAaAAgKIxETJgD6AQAfAAQKERSEEgD8AAAAAA==.Metrohexual:BAABNQAECn8hAAIUAAgKRhXXVwAGAgAUAAgKRhXXVwAGAgAAAA==.Mets:BAAANQAECgYICQABNQAECggIEwAQAAAAAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYJCQAQAAAAAA==.Mitzis:BAABNQAECn8eAAICAAgKGSJdMgDTAgACAAgKGSJdMgDTAgAAAA==.',
Mo='Moltiy:BAAANQADCgEIAQAAAA==.Moltten:BAAANQADCgcIJgAAAA==.Moondo:BAECNQAFFH8eAAIGAAcKpiIEAwCVAgAGAAcKpiIEAwCVAgA1AAQKfyoAAwYACQrNJB8PAE4DAAYACQrNJB8PAE4DAAUABApaBVBYAKEAAAE1AAUUAggCABAAAAAA.',
['Mè']='Mètis:BAABNQAECn8nAAICAAcKYCF4TwB+AgACAAcKYCF4TwB+AgAAAA==.',
Na='Naahx:BAAANQAECgcICgABNQAECgkJIQAPAB0kAA==.Nall:BAAANQAECgQIBAAAAA==.',
Ne='Nefarius:BAABNQAECn8lAAIaAAkKrh9dCwAtAwAaAAkKrh9dCwAtAwAAAA==.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECn8lAAQBAAgKeiSDGwAVAwABAAgKOiODGwAVAwAgAAQKhCWfDQB8AQAhAAMKtyBGLAAcAQAAAA==.',
Ni='Nighthigh:BAAANQAECgEIAQAAAA==.Nineoneone:BAABNQAECn8nAAIZAAgK+xduRABXAgAZAAgK+xduRABXAgAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.',
Nu='Nurmally:BAAANQAECgYICgABNQAFFAUIBgACAAwPAA==.Nuuot:BAAANQAECgcIBwAAAA==.',
Oc='Ocra:BAABNQAECn8ZAAIiAAcKERIpGQDNAQAiAAcKERIpGQDNAQABNQAECgkJOAACAAUfAA==.',
Of='Offspeck:BAAANQAECgQIBQABNQAECgkJMQABAKEhAA==.',
Ol='Oldirtycasta:BAAANQAECgEIAgABNQAECgYIGwAHAIQVAA==.',
On='Onayhawe:BAAANQAECgQIBgAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgkJOwAMAEElAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAABNQAECn8dAAIMAAcKdgYj7wA3AQAMAAcKdgYj7wA3AQAAAA==.Pallysmack:BAAANQADCgEIAQAAAA==.Pandapwr:BAAANQADCgcIDwABNQAECgcIDwAQAAAAAA==.Pandemul:BAAANQADCggICAABNQAECgkJRAAMAGQmAA==.Patrio:BAAANQADCgYICwABNQAECgkJLQAFABMiAA==.Pawkler:BAAANQAECgQIBAABNQAECggIFgAXAOQXAA==.Pawshira:BAAANQADCgUIBQABNQAECggIFgAXAOQXAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECn8iAAIUAAgKNiPIFQAfAwAUAAgKNiPIFQAfAwAAAA==.Perfectcell:BAAANQADCgYICwAAAA==.Petures:BAAANQAECgMIAwAAAA==.',
Ph='Phosphorus:BAABNQAECn9lAAMNAAkKQR7ZLAAHAwANAAkK1BzZLAAHAwAOAAgKehrIDwApAgAAAA==.',
Pl='Plagüë:BAABNQAECn8+AAMIAAkKEiHsEQAnAwAIAAkKiB/sEQAnAwAJAAkK+B7KFgD1AgAAAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQAECgQICAAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgMIBAAAAA==.Purgedoctor:BAABNQAFFH8IAAIUAAMK8h2jFAAIAQAUAAMK8h2jFAAIAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFH8WAAIBAAcKNiCFAQCYAgABAAcKNiCFAQCYAgA1AAQKfyoAAgEACQpCJTgLAHEDAAEACQpCJTgLAHEDAAAA.',
Ra='Ravenofchaos:BAAANQADCggICAAAAA==.Ravenoflight:BAAANQAECgIIAwAAAA==.Ravenshatred:BAAANQAECgQIBAAAAA==.Ravenswrath:BAAANQADCgYIBgAAAA==.Rawrsaur:BAAANQAECgYIDgAAAA==.',
Re='Reallyhpal:BAAANQAECgQIBgAAAA==.Recon:BAAANQADCgMIAwABNQAECggIEgAQAAAAAA==.Redpocket:BAAANQAECgEIAQAAAA==.Rein:BAAANQAECgQIEgAAAA==.Remin:BAAANQADCggIFAAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCggIDAABNQAECgYIEAAQAAAAAA==.Revan:BAAANQADCggIDgAAAA==.',
Ri='Rimooru:BAAANQAECgQIBAABNQAECgkJNwADAIsjAA==.Risquae:BAAANQAECgEIAQAAAA==.',
Ro='Romulis:BAAANQAECgEIAQAAAA==.Rosè:BAABNQAECn8XAAIFAAgKcRavIgAMAgAFAAgKcRavIgAMAgABNQAECggIJgAJADklAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECggIJgAJADklAA==.Ryzee:BAABNQAECn8cAAIWAAkKIhOkrQAmAgAWAAkKIhOkrQAmAgABNQAECgkJIAAYAGUbAA==.',
['Rí']='Ríco:BAAANQADCgYIDgAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgQIBwAAAA==.Sartha:BAABNQAECn8fAAIMAAgKyxJmjwACAgAMAAgKyxJmjwACAgAAAA==.Sasuka:BAAANQAECgQICAABNQAECgYIDAAQAAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scrumpheals:BAAANQADCgcIDQAAAA==.',
Se='Sedda:BAACNQAFFH8JAAIMAAUKDx+ACQCsAQAMAAUKDx+ACQCsAQA1AAQKfygAAgwACQqCJcwWAGgDAAwACQqCJcwWAGgDAAAA.Sensual:BAABNQAECn8yAAIXAAkKTxwQDwCqAgAXAAkKTxwQDwCqAgAAAA==.Sesshomaru:BAABNQAECn83AAIDAAkKiyOoBACnAwADAAkKiyOoBACnAwAAAA==.',
Sh='Shampain:BAAANQAECgYIEQABNQAECgkJSAAEAA0eAA==.Shampooh:BAAANQADCggICAAAAA==.Shang:BAACNQAFFH8JAAIGAAUKUCOIBwANAgAGAAUKUCOIBwANAgA1AAQKfyoAAgYACQq6JXIFAKsDAAYACQq6JXIFAKsDAAAA.Shanzo:BAAANQAECggIAwAAAA==.Shiftshot:BAAANQAECgUIBQAAAA==.Shirona:BAABNQAECn8hAAMDAAkKgxw5FQDwAgADAAkKgxw5FQDwAgAHAAcKCgnPOgBqAQAAAA==.Shloomish:BAAANQADCgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECn8pAAIWAAkKZxw9QQACAwAWAAkKZxw9QQACAwABNQAECgkJNwADAIsjAA==.',
Si='Siare:BAAANQAECggIEwAAAA==.',
Sk='Skeeter:BAABNQAECn8kAAQhAAgKPRpZFADLAQABAAYKcxVDggDcAQAhAAYKtBhZFADLAQAgAAQK+Q3IEwALAQAAAA==.Skroncer:BAAANQADCgYIEgAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECn8gAAIRAAgKcxpgDwBnAgARAAgKcxpgDwBnAgAAAA==.Smótts:BAAANQADCggJEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAAQAAAAAA==.Snizard:BAABNQAECn8XAAICAAYKIROesACeAQACAAYKIROesACeAQAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgcIEwAQAAAAAA==.',
So='Soawesome:BAAANQAECgQICAABNQAECgYIGwAHAIQVAA==.Solenoid:BAAANQAECgcICwAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Springrollz:BAAANQAECgEIAQAAAA==.Spàdes:BAAANQAECgIJAgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgYIDgABNQAECggIGwALAEsQAA==.Stormbeards:BAAANQADCgcIBwAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgUIBwABNQAFFAMICwARAFQTAA==.Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECgIIAgAAAA==.',
Ta='Taazdingo:BAAANQADCggIEwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAACNQAFFH8FAAMhAAMKkxjZBwC0AAAhAAIKsh3ZBwC0AAABAAEKVg5RPgBNAAA1AAQKfykAAwEACQpFI9k3AKoCAAEABwoNI9k3AKoCACEAAwrJHXgxAAABAAAA.',
Te='Teabear:BAAANQAECggIBAAAAA==.',
Th='Thisishard:BAABNQAECn8nAAIWAAkK8BXljwBfAgAWAAkK8BXljwBfAgAAAA==.Thryen:BAAANQAECgQICQAAAA==.Thundergrasp:BAABNQAECn8gAAIYAAkKZRufKQDYAgAYAAkKZRufKQDYAgAAAA==.',
To='Toe:BAAANQAFFAEIAQAAAA==.Toobestake:BAAANQAECgEIAQABNQAFFAYIGgATAMwbAA==.Topenga:BAABNQAECn84AAICAAkKBR97GgAtAwACAAkKBR97GgAtAwAAAA==.',
Tr='Trunnks:BAAANQAECgIIAgAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQADCgcICQAAAA==.',
Tw='Twicelife:BAAANQAECgUICQABNQAECgkJZQANAEEeAA==.',
Ty='Typhoid:BAAANQAECgUICQAAAA==.',
['Tñ']='Tñt:BAAANQAECgQIBAABNQAECgkJMQABAKEhAA==.',
Um='Umei:BAAANQADCgYIBgAAAA==.',
Ur='Urbek:BAAANQAECgYIEwAAAA==.Urthstripe:BAABNQAECn8bAAIFAAgKARU5IwAIAgAFAAgKARU5IwAIAgAAAA==.',
Uw='Uwu:BAAANQADCgcIEQABNQAFFAcIFwAaABESAA==.',
Va='Valle:BAAANQADCggIDgABNQAFFAcIFwAaABESAA==.Valoria:BAAANQAECggICAABNQAFFAcIFwAaABESAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAECgkJRAAMAGQmAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAABNQAECn8bAAMLAAgKSxC9DACEAQALAAcKRxK9DACEAQAeAAUKkAoQMwD7AAAAAA==.',
Vu='Vue:BAABNQAECn9IAAIEAAkKDR5QGwAGAwAEAAkKDR5QGwAGAwAAAA==.Vulkun:BAAANQAECgMIAwAAAA==.',
Wa='Wakasham:BAACNQAFFH8IAAIiAAQKuSSYAgCfAQAiAAQKuSSYAgCfAQA1AAQKfyUAAiIACQqzJqAAANYDACIACQqzJqAAANYDAAAA.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAABNQAECn8YAAMDAAgKXiG/EwD9AgADAAgKXiG/EwD9AgAHAAIKUghsYgBbAAABNQAFFAcIFwAHAC8eAA==.',
Wi='Wickedmisery:BAAANQADCgYIBgAAAA==.',
Wo='Wolfpacked:BAABNQAECn8bAAIUAAYKFhl5dQCnAQAUAAYKFhl5dQCnAQABNQAECgkJIQABAE8hAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAABNQAECn8zAAIWAAkKNSGqJgBGAwAWAAkKNSGqJgBGAwAAAA==.',
Ye='Yellowshaman:BAACNQAFFH8JAAIYAAMKpA0kGwDkAAAYAAMKpA0kGwDkAAA1AAQKfyUAAhgACQoqHkYmAOgCABgACQoqHkYmAOgCAAAA.',
Za='Zandelussy:BAAANQAECgcIEwAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAcIFwAaABESAA==.Zuriznikov:BAAANQAECgUIEAABNQAECggIGwALAEsQAA==.',
['Øf']='Øffspeck:BAABNQAECn8xAAQBAAkKoSFoFgAuAwABAAkKeR9oFgAuAwAgAAgK4Rr0BAB+AgAhAAUKTiN+DwADAgAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECgcIHAAOAOwgAA==.',
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
