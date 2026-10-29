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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','Mage-Arcane','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Unknown-Unknown','Druid-Feral','Hunter-Marksmanship','Priest-Holy','Shaman-Restoration','Hunter-Survival','Paladin-Protection','Shaman-Elemental','Priest-Shadow','DeathKnight-Frost','Mage-Fire','Warrior-Fury','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgoKPAABAHUiAA==.Aaronfreeze:BAACNQAFFH8FAAICAAIKtxGdKQCSAAACAAIKtxGdKQCSAAA1AAQKfzQAAgIACgpqIQsfABsDAAIACgpqIQsfABsDAAAA.',
Ab='Abnar:BAABNQAECn8bAAIDAAgKqRXgDADoAQADAAgKqRXgDADoAQAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUICQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAFFAIIBQAEAOcbAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggIDAAAAA==.Alucard:BAABNQAECn8zAAIFAAoKyRRpMADiAQAFAAoKyRRpMADiAQAAAA==.Alystrasza:BAABNQAECn8uAAMGAAoK3B4gDQD9AgAGAAoK3B4gDQD9AgAHAAcKLg26WABxAQAAAA==.',
Am='Ambivalent:BAABNQAECn8UAAIIAAgK0AbPlgAWAQAIAAgK0AbPlgAWAQAAAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICgAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgcIKwACAGAhAA==.',
Ar='Arrowsmïth:BAAANQADCgUIBwAAAA==.',
As='Ashenfate:BAAANQAECgQIBQABNQAFFAUIFAAJAP0XAA==.',
Au='Auroras:BAAANQAECgIIAgAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAABNQAECn8mAAMKAAoK7B87IADKAgAKAAoK7B87IADKAgALAAEK1QU80AAtAAABNQAFFAIIBQAEAOcbAA==.',
['Aü']='Aütöpsy:BAABNQAECn80AAIMAAoKUBtgHgAqAgAMAAoKUBtgHgAqAgAAAA==.',
Ba='Baarda:BAAANQADCgQIBAABNQAECggIIQANAL8QAA==.Babylonfive:BAABNQAECn9DAAIOAAoKsCQDBQDSAwAOAAoKsCQDBQDSAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgMIBgAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAABNQAECn8vAAIPAAcKJhaZHABIAQAPAAcKJhaZHABIAQABNQAECggIFAAIANAGAA==.Berserk:BAEBNQAECn8aAAMQAAgKYRaWdAA3AgAQAAgK5BSWdAA3AgARAAYKIBPAHgBdAQABNQAFFAUIBwASABwDAA==.Bertringer:BAAANQAECgMIAwABNQAECgQIBQATAAAAAA==.',
Bi='Bigthiccboi:BAAANQAECgQIBQAAAA==.Bigwave:BAAANQADCggIEQAAAA==.Bigwilli:BAAANQADCgYIDgAAAA==.Bilefiend:BAAANQADCgMIAwAAAA==.Birds:BAACNQAFFH8UAAIJAAUK/RcUAQAyAQAJAAUK/RcUAQAyAQA1AAQKfzMABAkACgrcIPIDAOUCAAkACgrcIPIDAOUCABQABwoRExoSAN4BAAcAAQoAANK2ACsAAAAA.Biscuit:BAACNQAFFH8VAAMCAAcKzx7sCwCRAQACAAcKzxzsCwCRAQAVAAQKIwsnFAD+AAA1AAQKfzEAAwIACQrIJeMEAEADAAIACQrIJeMEAEADABUABwptITwnABECAAAA.Bisha:BAABNQAECn9KAAIQAAoKwCGSFQBkAwAQAAoKwCGSFQBkAwAAAA==.Bizcocho:BAAANQAECgYIEQAAAA==.',
Bl='Bloodfern:BAAANQABCgEIAQAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boogsta:BAAANQAECgMIAwABNQAECgoKMQAWAJ0dAA==.Boomkingobrr:BAAANQAECgYICQAAAA==.Boops:BAABNQAFFH8LAAIXAAMKkQrEGQDNAAAXAAMKkQrEGQDNAAABNQAFFAUICQAGAD4HAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAABNQAECn8lAAIRAAgKGB6kCwB/AgARAAgKGB6kCwB/AgAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Bunnycakez:BAAANQADCgIIAgAAAA==.Burnsx:BAAANQADCggIGAABNQAFFAcIFwAPAC8eAA==.',
Bw='Bwoar:BAABNQAECn8oAAIMAAoKDBsGFwBmAgAMAAoKDBsGFwBmAgAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAABNQAECn8iAAMYAAoKwhlzBACdAgAYAAoKwhlzBACdAgACAAEKNBYdSwFJAAAAAA==.Carriedomb:BAAANQADCgIIAwAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQAECgQIBwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAABNQAECn8iAAICAAgKtxSXVgCZAQACAAgKtxSXVgCZAQAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAABNQAECn8rAAIFAAoKMxoWDQD6AgAFAAoKMxoWDQD6AgAAAA==.',
Ci='Cirxe:BAABNQAECn8qAAIIAAkKQwWiDgF0AQAIAAkKQwWiDgF0AQAAAA==.',
Cl='Clarkent:BAAANQAECgUICAAAAA==.',
Co='Coms:BAABNQAECn8UAAIOAAgKVAvnxACSAQAOAAgKVAvnxACSAQAAAA==.Cowmoorem:BAAANQADCgEIAQAAAA==.',
Cr='Crayze:BAAANQAECgIIBgAAAA==.Creatinepowa:BAAANQADCgEIAQAAAA==.',
Cu='Curuni:BAAANQAECgQIBAAAAA==.',
['Cø']='Cønstance:BAABNQAECn8tAAIJAAoKeyH5BQCaAgAJAAoKeyH5BQCaAgAAAA==.',
Da='Dabai:BAABNQAECn81AAIOAAoKBhYPbABZAgAOAAoKBhYPbABZAgAAAA==.Dahliaa:BAAANQADCgMIAwAAAA==.Daipailaotie:BAABNQAECn8qAAMOAAoKoAcs1ABzAQAOAAoKNAcs1ABzAQAZAAUKVQZQVgCIAAAAAA==.Dalight:BAAANQAECgUICAAAAA==.Dankins:BAABNQAFFH8PAAIXAAUK4B1eCADNAQAXAAUK4B1eCADNAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMIAwAAAA==.Darthravens:BAAANQABCgQIBAAAAA==.',
De='Deathmager:BAAANQAECgQIBAAAAA==.Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIIAgAAAA==.Dette:BAABNQAECn8VAAICAAcK1wvA0wBZAQACAAcK1wvA0wBZAQAAAA==.Devourer:BAABNQAECn9fAAIPAAoK9SQ0AQBcAwAPAAoK9SQ0AQBcAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECggIJQARABgeAA==.',
Do='Doctrdoom:BAAANQADCggIFQABNQAECgoKPAABAHUiAA==.',
Dr='Drafted:BAAANQAECgYIDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIDwAXAOAdAA==.Drukah:BAAANQAECgIIAgAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAABNQAECn8gAAIEAAcK0wLqZwDZAAAEAAcK0wLqZwDZAAAAAA==.Edwinranger:BAAANQAECggIAQAAAA==.',
El='Elabernathy:BAABNQAECn8hAAICAAkKwQ3hSQDAAQACAAkKwQ3hSQDAAQAAAA==.Elenay:BAABNQAECn8gAAIHAAkKaCFMFQAdAwAHAAkKaCFMFQAdAwAAAA==.Eliarssande:BAAANQAECgYIDAAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECn8uAAIGAAkKEyKABQBqAwAGAAkKEyKABQBqAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECn8xAAIKAAkK2iEkLgB5AgAKAAkK2iEkLgB5AgABNQAFFAMIBQAOALIhAA==.Emulsifier:BAACNQAFFH8FAAIOAAMKsiECEADFAAAOAAMKsiECEADFAAA1AAQKf0oAAg4ACgrfJQ0CAPEDAA4ACgrfJQ0CAPEDAAAA.Emulslash:BAAANQADCgYIDAABNQAFFAMIBQAOALIhAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgcIKwACAGAhAA==.',
Ex='Expiatory:BAAANQADCgEIAQAAAA==.Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQAECgUICQAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAABNQAECn8dAAMSAAoK5R9aDgAQAwASAAoKMx5aDgAQAwAMAAgKYhh2SQA4AQAAAA==.',
Fl='Flatline:BAABNQAECn8cAAIBAAkK5hFvrwByAQABAAkK5hFvrwByAQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAABNQAECn8YAAMSAAgKBBpDLQAxAgASAAcK+hpDLQAxAgAMAAIKJhPvdgCOAAABNQAFFAMIBQAOALIhAA==.',
Go='Gorska:BAABNQAECn8kAAIaAAkKuhtcNgCeAgAaAAkKuhtcNgCeAgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECgcICAABNQAECgoKPAABAHUiAA==.',
['Gä']='Gämbit:BAAANQAECgUICAAAAA==.',
Ha='Hangman:BAAANQAECgYIDQAAAA==.Hanni:BAAANQAECgUIBQAAAA==.Harakutoo:BAAANQAECgEIAQAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAABNQAECn8xAAMWAAoKnR3aEwDHAgAWAAoKnR3aEwDHAgAbAAIKqQTvSAAzAAAAAA==.',
He='Hellshand:BAAANQAECgUICQAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Hi='Hinxx:BAAANQAECgMIAwAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAABNQAECn8dAAIZAAcKSiX7BgB0AgAZAAcKSiX7BgB0AgABNQAECgoKMgABAAwiAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgcICAABNQAECggIIQANAL8QAA==.Holypawk:BAABNQAECn8aAAIZAAkKdhf1GwANAgAZAAkKdhf1GwANAgAAAA==.Holyrock:BAABNQAECn8iAAIOAAkK/BUlSQDcAQAOAAkK/BUlSQDcAQAAAA==.Honorheart:BAAANQADCgMIBgAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYICQATAAAAAA==.',
Ih='Ihureciv:BAABNQAECn8lAAIVAAoKeRfDIgA3AgAVAAoKeRfDIgA3AgABNQAFFAMIBgAbAGEYAA==.',
Ik='Ikur:BAABNQAECn82AAIFAAoKaBw7KADHAgAFAAoKaBw7KADHAgAAAA==.',
In='Infoxicated:BAAANQAECgYIBgABNQAECgoKJgAFAJMeAA==.',
Ip='Ipopkidneys:BAACNQAFFH8bAAMMAAcK0SK+BADdAQAMAAUK8CO+BADdAQASAAIKISHWBQCvAAA1AAQKfy4AAwwACgp/JSMXAGUCAAwACgpPJSMXAGUCABIABAo3JO1QAHoBAAAA.',
Ir='Iroi:BAAANQAECgIJAgAAAA==.',
Is='Iskur:BAAANQAECgYIEQABNQAECgoKNgAFAGgcAA==.Isurr:BAAANQAECgUIDQABNQAECgoKNgAFAGgcAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgUICgAAAA==.Jametrok:BAABNQAECn8aAAIOAAgK4BW+lAD6AQAOAAgK4BW+lAD6AQAAAA==.Jastra:BAAANQADCgcIDgAAAA==.',
Je='Jennyanydots:BAAANQADCggIDAABNQAFFAcIFwAbABESAA==.',
Ji='Jiraîya:BAABNQAECn8dAAIaAAkKehJ3LgChAQAaAAkKehJ3LgChAQAAAA==.',
Jo='Jordak:BAABNQAECn8jAAIGAAkKDhxBEwCzAgAGAAkKDhxBEwCzAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAABNQAECn8cAAIIAAcK6hPv4wDBAQAIAAcK6hPv4wDBAQAAAA==.Just:BAABNQAECn8hAAMKAAoK2Q3/VwCxAQAKAAoKng3/VwCxAQAcAAQKFAvJdwDEAAAAAA==.',
Ka='Kaddiya:BAAANQAECgEIAQAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAABNQAECn8sAAIXAAkKtBV8TwAnAgAXAAkKtBV8TwAnAgAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.Katalaana:BAAANQAECgEIAQAAAA==.',
Ke='Kevdogg:BAABNQAECn8jAAMIAAgK4gWFsgDiAAAIAAgKRAWFsgDiAAAdAAEKlQV/DgAuAAAAAA==.Key:BAACNQAFFH8MAAMOAAUKJh/UDgBfAQAOAAUKJh/UDgBfAQAFAAEKbwusJwBOAAA1AAQKfysAAw4ACgowJTQvAAwDAA4ACgowJTQvAAwDAAUABwr/FOR2ALMBAAAA.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQICAABNQAFFAUIFAAJAP0XAA==.',
Ko='Kobol:BAAANQAECggIDAAAAA==.Koluvan:BAAANQADCggIGQAAAA==.Koopa:BAABNQAECn8vAAIeAAoKnCAOAgDJAgAeAAoKnCAOAgDJAgAAAA==.',
Kr='Krianii:BAAANQADCgEIAQAAAA==.Krieg:BAAANQAECgYIBgABNQAFFAYIEgAHAH0hAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAACNQAFFH8GAAIbAAMKYRjJCQCqAAAbAAMKYRjJCQCqAAA1AAQKf1wAAxsACgq9JNcCAK4DABsACgq9JNcCAK4DABYABApaFoGoABwBAAAA.',
Li='Lilkaren:BAAANQABCgMIAwABNQAECgoKHwASAE4PAA==.Lillianna:BAABNQAECn8WAAIMAAcKYw5nIgC3AQAMAAcKYw5nIgC3AQAAAA==.Lilsensual:BAABNQAECn8eAAIXAAgKahMFZADhAQAXAAgKahMFZADhAQABNQAFFAMIBgAZAD0GAA==.',
Lo='Loads:BAAANQAECgYICQAAAA==.Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAABNQAECn8qAAIZAAoKwxDHEQCJAQAZAAoKwxDHEQCJAQAAAA==.Lucário:BAABNQAECn8yAAIQAAkK+SToCgAQAwAQAAkK+SToCgAQAwAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAABNQAECn8ZAAIFAAkKkh4IDQD7AgAFAAkKkh4IDQD7AgAAAA==.Lunastorm:BAACNQAFFH8GAAIfAAMKVQhbCwCwAAAfAAMKVQhbCwCwAAA1AAQKf00AAh8ACgqXHmMOAMICAB8ACgqXHmMOAMICAAAA.Luponero:BAACNQAFFH8gAAMVAAcKqRj6BAAxAQAVAAYKxhj6BAAxAQACAAEKNhi4HwBdAAA1AAQKfycAAxUACgrrILsYAJECABUACgqNILsYAJECAAIAAQoCJOhGAVEAAAAA.',
Ma='Macmn:BAACNQAFFH8LAAIaAAUKmB2/CQDRAQAaAAUKmB2/CQDRAQA1AAQKfykAAhoACgr/JfcFALoDABoACgr/JfcFALoDAAAA.Magej:BAAANQADCgQIBAAAAA==.Mageyouacake:BAAANQADCgQIBgAAAA==.Mamaheals:BAABNQAECn8wAAIWAAoKbiDvFwAXAwAWAAoKbiDvFwAXAwAAAA==.Mandos:BAABNQAECn86AAILAAoKZSPSBgDqAgALAAoKZSPSBgDqAgAAAA==.Mantistabogn:BAAANQAECgcICgAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAUIEwAaALUXAA==.Merlini:BAABNQAECn8lAAMbAAoKYA9wJgD6AQAbAAoKYA9wJgD6AQAgAAUKTBWeEgD9AAAAAA==.Metrohexual:BAABNQAECn8vAAIXAAoKth3TCgAWAwAXAAoKth3TCgAWAwAAAA==.Mets:BAABNQAECn8bAAICAAoKAh30FQCkAgACAAoKAh30FQCkAgABNQAECgoKIgABADIaAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYICQATAAAAAA==.Mitzis:BAACNQAFFH8FAAICAAIKjQuWKwCGAAACAAIKjQuWKwCGAAA1AAQKfyMAAgIACgoOHZozANECAAIACgoOHZozANECAAAA.',
Mn='Mnm:BAAANQAECgUIBwAAAA==.',
Mo='Moltiy:BAAANQADCgcICAAAAA==.Moltten:BAAANQAECgUIBwAAAA==.Moondo:BAECNQAFFH8eAAIHAAcKpiIqAwCVAgAHAAcKpiIqAwCVAgA1AAQKfzcAAwcACgqxJFYPAE4DAAcACgqxJFYPAE4DAAYABgqvD8MzANEAAAE1AAUUAggCABMAAAAA.',
['Mè']='Mètis:BAABNQAECn8rAAICAAcKYCHpUAB9AgACAAcKYCHpUAB9AgAAAA==.',
Na='Naahx:BAAANQAECgcICgABNQAECgoKJgASAG4iAA==.Nall:BAAANQAECgQIBAAAAA==.Narmer:BAAANQABCgMIAwAAAA==.',
Ne='Nefarius:BAACNQAFFH8GAAIbAAIKVxENCwCUAAAbAAIKVxENCwCUAAA1AAQKfy8AAhsACgrZHYILAC0DABsACgrZHYILAC0DAAAA.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECn8xAAQBAAgKeiRRHAAUAwABAAgKOiNRHAAUAwAhAAQKhCXBDQB7AQAiAAUKviHMBgARAQAAAA==.',
Ni='Nighthigh:BAAANQAECgEIAQAAAA==.Nineoneone:BAABNQAECn80AAIWAAgKRxtkMwDvAQAWAAgKRxtkMwDvAQAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.',
Nu='Nurmally:BAAANQAECgcICwABNQAFFAUIBgACAAwPAA==.Nutmilk:BAAANQAECgIIAgAAAA==.Nuuot:BAAANQAECgcIDQAAAA==.',
Oc='Ocra:BAABNQAECn8lAAIjAAoKNg+1DQC1AQAjAAoKNg+1DQC1AQABNQAFFAIIBQACAF8UAA==.',
Of='Offspeck:BAAANQAECgQIBQABNQAECgoKPAABAHUiAA==.',
Ol='Oldirtycasta:BAAANQAECgEIAgABNQAECggIFAAIANAGAA==.',
On='Onayhawe:BAAANQAECgUIBgAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgoKQwAOALAkAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAABNQAECn8oAAIOAAoKRAbyqgABAQAOAAoKRAbyqgABAQAAAA==.Pallysmack:BAAANQADCgEIAQAAAA==.Pandapwr:BAAANQADCgcIDwABNQAECgoKKAAMAAwbAA==.Pandemul:BAAANQADCggICAABNQAFFAMIBQAOALIhAA==.Patrio:BAAANQADCgYICwABNQAECgkJLgAGABMiAA==.Pawkler:BAAANQAECgQIBAABNQAECgkJGgAZAHYXAA==.Pawshira:BAAANQADCgUIBQABNQAECgkJGgAZAHYXAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECn8qAAIXAAoKCyIlFgAfAwAXAAoKCyIlFgAfAwAAAA==.Perfectcell:BAAANQADCgYICwAAAA==.Petures:BAAANQAECgMIAwAAAA==.',
Ph='Phosphorus:BAACNQAFFH8GAAIQAAMKJQmXHQB9AAAQAAMKJQmXHQB9AAA1AAQKf34AAxAACgrOHsEtAAYDABAACgrEHcEtAAYDABEACQooGWcLAIkBAAAA.',
Pl='Plagüë:BAACNQAFFH8GAAMKAAMKpgtSCQCAAAAKAAIKpgtSCQCAAAALAAIKaQy6MAA1AAA1AAQKf0QAAwoACgoQIw4SACcDAAoACgpUIg4SACcDAAsACQr4Hh0XAPQCAAAA.Pluckedchkn:BAAANQAECgIIBAABNQAFFAMIBgAZAD0GAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQAECgUIDgAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgYICAAAAA==.Purgedoctor:BAABNQAFFH8IAAIXAAMK8h0nFQAIAQAXAAMK8h0nFQAIAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFH8YAAIBAAcKNiCXAQCTAgABAAcKNiCXAQCTAgA1AAQKfy8AAgEACgpDJpMLAHADAAEACgpDJpMLAHADAAAA.',
Ra='Ravenofchaos:BAAANQADCggICAAAAA==.Ravenoflight:BAAANQAECgIIAwAAAA==.Ravenshatred:BAAANQAECgQICAAAAA==.Ravenswrath:BAAANQADCgYIBgAAAA==.Ravenuchiha:BAAANQADCgcIBwAAAA==.Rawrsaur:BAAANQAECgYIDgAAAA==.',
Re='Reallyhpal:BAAANQAECgcIEAAAAA==.Recon:BAAANQADCgMIAwABNQAECgoKGAAHALAFAA==.Redpocket:BAAANQAECgIIAgAAAA==.Rein:BAABNQAECn8cAAIRAAYKbQg7GADTAAARAAYKbQg7GADTAAAAAA==.Remin:BAAANQAECgUIBQAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCggIDAABNQAECgkJHAASAOkaAA==.Revan:BAAANQADCggIDgAAAA==.',
Ri='Rimooru:BAAANQAECgQICAABNQAFFAIIBQAEAOcbAA==.Risquae:BAAANQAECgEIAQAAAA==.',
Ro='Romulis:BAAANQAECgQIBgAAAA==.Rosè:BAABNQAECn8rAAIGAAoKzhtKBgAFAwAGAAoKzhtKBgAFAwABNQAECgoKOgALAGUjAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgoKOgALAGUjAA==.Ryzee:BAABNQAECn8cAAIIAAkKIhN3sAAiAgAIAAkKIhN3sAAiAgABNQAECgoKKQAaAK4YAA==.',
['Rí']='Ríco:BAAANQADCgYIDgAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgQIBwAAAA==.Sans:BAAANQAECggICAABNQAECgoKQQAaALwSAA==.Sartha:BAABNQAECn8uAAIOAAoKshMZQwDwAQAOAAoKshMZQwDwAQAAAA==.Sasuka:BAAANQAECgUIEAABNQAECgYIDAATAAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scrumpheals:BAAANQAECgEIAQAAAA==.',
Se='Sedda:BAACNQAFFH8JAAIOAAUKDx/BCQCsAQAOAAUKDx/BCQCsAQA1AAQKfygAAg4ACQqCJWIXAGcDAA4ACQqCJWIXAGcDAAAA.Sensual:BAACNQAFFH8GAAIZAAMKPQZTCABiAAAZAAMKPQZTCABiAAA1AAQKfz0AAhkACgojHUEPAKkCABkACgojHUEPAKkCAAAA.Sesshomaru:BAACNQAFFH8FAAIEAAIK5xuPDACVAAAEAAIK5xuPDACVAAA1AAQKf0QAAgQACgogI7oEAKcDAAQACgogI7oEAKcDAAAA.',
Sh='Shampain:BAABNQAECn8gAAMjAAoKHAqfFAA9AQAjAAoKHAqfFAA9AQAXAAUKug6B3wCqAAABNQAECgoKUgAFAMYfAA==.Shampooh:BAAANQADCggICAAAAA==.Shang:BAACNQAFFH8SAAIHAAYKfSEEBACZAQAHAAYKfSEEBACZAQA1AAQKfy8AAgcACgrtJY4FAKoDAAcACgrtJY4FAKoDAAAA.Shanzo:BAAANQAECggIAwAAAA==.Shiftshot:BAAANQAECgUIBQAAAA==.Shirona:BAABNQAECn80AAMEAAoKWyHpBQD+AgAEAAoKWyHpBQD+AgAPAAcKCgmJOwBqAQAAAA==.Shloomish:BAAANQAECgYIBgAAAA==.Shmized:BAAANQAECgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECn87AAIIAAoKLyDmGwCPAgAIAAoKLyDmGwCPAgABNQAFFAIIBQAEAOcbAA==.',
Si='Siare:BAABNQAECn8iAAIBAAoKMhr9NwCsAgABAAoKMhr9NwCsAgAAAA==.',
Sk='Skeeter:BAABNQAECn8pAAQiAAgKPRqGFADLAQABAAYKcxVYhADbAQAiAAYKtBiGFADLAQAhAAUKvw77EwALAQAAAA==.Skroncer:BAAANQADCgYIEgAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECn8gAAIJAAgKcxqmDwBnAgAJAAgKcxqmDwBnAgAAAA==.Smótts:BAAANQADCggJEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAATAAAAAA==.Snizard:BAABNQAECn8XAAICAAYKIRNXswCdAQACAAYKIRNXswCdAQAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgoKJgAFAJMeAA==.',
So='Soawesome:BAAANQAECgQICAABNQAECggIFAAIANAGAA==.Solenoid:BAAANQAECgcIEwAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Springrollz:BAAANQAECgEIAQAAAA==.Spàdes:BAAANQAECgQIBgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgYIEgABNQAECggIIQANAL8QAA==.Stonecolld:BAAANQADCgIIAgAAAA==.Stormbeards:BAAANQADCgcIBwAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgUICAABNQAFFAUIFAAJAP0XAA==.Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECgcICgAAAA==.',
Ta='Taazdingo:BAAANQADCggIEwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAACNQAFFH8LAAMiAAQK0xhUAwCjAAAiAAIKEh5UAwCjAAABAAIKVg6LKABIAAA1AAQKfzgAAwEACgoKJPo4AKkCAAEACAoaJPo4AKkCACIAAwrPHRELAMkAAAAA.',
Te='Teabear:BAAANQAECggIBgAAAA==.',
Th='Thisishard:BAABNQAECn85AAIIAAoKgxfBMQArAgAIAAoKgxfBMQArAgAAAA==.Thryen:BAAANQAECgQICQAAAA==.Thundergrasp:BAABNQAECn8pAAIaAAoKrhg+KgDXAgAaAAoKrhg+KgDXAgAAAA==.',
To='Toe:BAAANQAFFAIIBAAAAA==.Toobestake:BAAANQAECgEIAgABNQAFFAcIIAAVAKkYAA==.Topenga:BAACNQAFFH8FAAICAAIKXxRbIwBRAAACAAIKXxRbIwBRAAA1AAQKf0UAAgIACgreIP8aACwDAAIACgreIP8aACwDAAAA.',
Tr='Trunnks:BAAANQAECgYIBQAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQADCgcICQAAAA==.',
Tw='Twicelife:BAAANQAECgUICgABNQAFFAMIBgAQACUJAA==.',
Ty='Typhoid:BAAANQAECgcIDAAAAA==.',
['Tñ']='Tñt:BAAANQAECgYICQABNQAECgoKPAABAHUiAA==.',
Um='Umei:BAAANQAECgEIAQAAAA==.',
Ur='Urbek:BAABNQAECn8VAAIHAAcKGyDhLgBoAgAHAAcKGyDhLgBoAgAAAA==.Urthstripe:BAABNQAECn8lAAIGAAoKKBbdEgD5AQAGAAoKKBbdEgD5AQAAAA==.',
Uw='Uwu:BAAANQAECgUIBQABNQAFFAcIFwAbABESAA==.',
Va='Valle:BAAANQADCggIDgABNQAFFAcIFwAbABESAA==.Valoria:BAAANQAECggICAABNQAFFAcIFwAbABESAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAFFAMIBQAOALIhAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAABNQAECn8hAAMNAAgKvxDeDACEAQANAAcK0xLeDACEAQAfAAUKkApxMwD7AAAAAA==.',
Vu='Vue:BAABNQAECn9SAAIFAAoKxh+rGwAGAwAFAAoKxh+rGwAGAwAAAA==.Vulkun:BAAANQAECgMIAwAAAA==.',
Wa='Wakasham:BAACNQAFFH8PAAIjAAUK0SRbAQAYAQAjAAUK0SRbAQAYAQA1AAQKfy0AAiMACgqrJqcAANQDACMACgqrJqcAANQDAAAA.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAABNQAECn8ZAAMEAAkKtSAiFAD9AgAEAAkKtSAiFAD9AgAPAAIKUgjsYwBbAAABNQAFFAcIFwAPAC8eAA==.',
Wi='Wickedmisery:BAAANQADCgYIBgAAAA==.',
Wo='Wolfpacked:BAABNQAECn8bAAIXAAYKFhnpdgCnAQAXAAYKFhnpdgCnAQABNQAECgoKMgABAAwiAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAACNQAFFH8FAAIIAAMKCg5IJwCVAAAIAAMKCg5IJwCVAAA1AAQKfz0AAggACgpZIWAnAEQDAAgACgpZIWAnAEQDAAAA.',
Xe='Xeroidz:BAAANQADCgcICgAAAA==.',
Xs='Xscrats:BAAANQAECggIBQAAAA==.',
Ye='Yellowshaman:BAACNQAFFH8JAAIaAAMKpA20GwDkAAAaAAMKpA20GwDkAAA1AAQKfyoAAxoACQrpHs0mAOgCABoACQrpHs0mAOgCABcAAQoTDk7FADYAAAAA.Yerac:BAABNQAFFH8JAAMGAAUKPgfABQA5AQAGAAUKPgfABQA5AQAHAAEK4QHIGgA1AAAAAA==.',
Za='Zandelussy:BAABNQAECn8mAAIFAAoKkx53FACiAgAFAAoKkx53FACiAgAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAcIFwAbABESAA==.Zuriznikov:BAABNQAECn8WAAUGAAYKQA5QJgAqAQAGAAYKQA5QJgAqAQAHAAQKCQXAjQCfAAAJAAQKqgc+RgCZAAAUAAEKhAm3RQAuAAABNQAECggIIQANAL8QAA==.',
['Øf']='Øffspeck:BAABNQAECn88AAQBAAoKdSIMFwAsAwABAAoKTSAMFwAsAwAhAAgK4RoABQB+AgAiAAcKrCKbDwADAgAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECggIJQARABgeAA==.',
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
