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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Evoker-Augmentation','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Rogue-Assassination','Unknown-Unknown','Druid-Feral','Hunter-Marksmanship','Shaman-Restoration','Hunter-Survival','Mage-Arcane','Paladin-Protection','Shaman-Elemental','Priest-Holy','Priest-Shadow','DeathKnight-Frost','Mage-Fire','Warrior-Fury','Evoker-Preservation','Priest-Discipline','Warlock-Affliction','Warlock-Destruction','Shaman-Enhancement',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaron:BAAANQAECgIIAgABNQAECgoKNwABAOcgAA==.Aaronfreeze:BAABNQAECn80AAICAAoKaiELHwAbAwACAAoKaiELHwAbAwAAAA==.',
Ab='Abnar:BAABNQAECn8ZAAIDAAcKthbgDADoAQADAAcKthbgDADoAQAAAA==.',
Ad='Adversaryq:BAAANQADCgYIBwAAAA==.',
Ai='Aid:BAAANQADCgMIBQAAAA==.',
Al='Alanii:BAAANQAECgUICQAAAA==.Alaula:BAAANQAECgQIBAAAAA==.Albedô:BAAANQADCgIIBAABNQAECgoKPQAEALshAA==.Allformarc:BAAANQAECgUJBgAAAA==.Allmaick:BAAANQADCggIDAAAAA==.Alucard:BAABNQAECn8qAAIFAAgKLxaYUwAfAgAFAAgKLxaYUwAfAgAAAA==.Alystrasza:BAABNQAECn8rAAMGAAoKiBwgDQD9AgAGAAoKiBwgDQD9AgAHAAcKLg26WABxAQAAAA==.',
Am='Ambivalent:BAAANQAECgUIBwABNQAECgcIJwAIANIVAA==.',
An='Animan:BAAANQABCgIIAgAAAA==.Antimovsky:BAAANQAECgQICgAAAA==.',
Ap='Aphroditê:BAAANQADCgQIBAABNQAECgcIKwACAGAhAA==.',
Ar='Arrowsmïth:BAAANQADCgUIBwAAAA==.',
As='Ashenfate:BAAANQAECgQIBQABNQAFFAQIDwAJAA4WAA==.',
Au='Auroras:BAAANQAECgIIAgAAAA==.',
Av='Aviaria:BAAANQAECgEIAQAAAA==.',
Ax='Axsenaea:BAAANQADCgEIAQAAAA==.',
['Aì']='Aìnzooalgown:BAABNQAECn8hAAMKAAoKdB07IADKAgAKAAoKdB07IADKAgALAAEK1QU80AAtAAABNQAECgoKPQAEALshAA==.',
['Aü']='Aütöpsy:BAABNQAECn8rAAIMAAoKjhnTAgBCAgAMAAoKjhnTAgBCAgAAAA==.',
Ba='Baarda:BAAANQADCgQIBAABNQAECggIHgANAL8QAA==.Babylonfive:BAABNQAECn9CAAIOAAoKsCQDBQDSAwAOAAoKsCQDBQDSAwAAAA==.Backstabbath:BAAANQADCgQIBQAAAA==.Banger:BAAANQAECgMIBgAAAA==.',
Be='Belleta:BAAANQAECgEIAgAAAA==.Belligerente:BAABNQAECn8nAAIIAAcK0hWzCwBcAQAIAAcK0hWzCwBcAQAAAA==.Berserk:BAEBNQAECn8aAAMPAAgKYRaWdAA3AgAPAAgK5BSWdAA3AgAQAAYKIBPAHgBdAQABNQAFFAQIBgARAHICAA==.Bertringer:BAAANQAECgMIAwABNQAECgQIBQASAAAAAA==.',
Bi='Bigthiccboi:BAAANQAECgQIBQAAAA==.Bigwave:BAAANQADCggIEQAAAA==.Bigwilli:BAAANQADCgYIDQAAAA==.Bilefiend:BAAANQADCgMIAwAAAA==.Birds:BAACNQAFFH8PAAIJAAQKDhbDAQDQAAAJAAQKDhbDAQDQAAA1AAQKfyoABAkACgrJIE0GAC0DAAkACgrJIE0GAC0DABMABwoRExoSAN4BAAcAAQoAANK2ACsAAAAA.Biscuit:BAACNQAFFH8UAAMCAAYKtx7sCwCRAQACAAYKNxzsCwCRAQAUAAQKIwsnFAD+AAA1AAQKfygAAwIACQoDI+83AMICAAIACQoDI+83AMICABQABwptITwnABECAAAA.Bisha:BAABNQAECn9GAAIPAAoKdx6SFQBkAwAPAAoKdx6SFQBkAwAAAA==.Bizcocho:BAAANQAECgYIEQAAAA==.',
Bo='Bonesofdoom:BAAANQADCgEIAQAAAA==.Boomkingobrr:BAAANQAECgYICQAAAA==.Boops:BAABNQAFFH8LAAIVAAMKkQrEGQDNAAAVAAMKkQrEGQDNAAABNQAFFAQIBAASAAAAAA==.Bootysweatt:BAAANQADCggICAAAAA==.Boss:BAABNQAECn8iAAIQAAgKGB6kCwB/AgAQAAgKGB6kCwB/AgAAAA==.',
Bu='Buckayou:BAAANQADCgUIBwAAAA==.Burnsx:BAAANQADCggIGAABNQAFFAcIFwAIAC8eAA==.',
Bw='Bwoar:BAABNQAECn8YAAIMAAoKWBIUFQAxAQAMAAoKWBIUFQAxAQAAAA==.',
Ca='Caiandol:BAAANQADCgQIAwAAAA==.Candydreams:BAAANQABCgQIBAAAAA==.Captinfeo:BAAANQADCggICAAAAA==.Captnmurloc:BAABNQAECn8iAAMWAAoKwhlzBACdAgAWAAoKwhlzBACdAgACAAEKNBYdSwFJAAAAAA==.Catara:BAAANQADCgcICwAAAA==.',
Ce='Cedar:BAAANQAECgQIBwAAAA==.',
Ch='Cheetos:BAAANQADCggICAAAAA==.Cherga:BAABNQAECn8bAAICAAgKHxKMQQAzAQACAAgKHxKMQQAzAQAAAA==.Chrinn:BAAANQABCgUIBQAAAA==.Church:BAABNQAECn8hAAIFAAoKWhcuBQCIAgAFAAoKWhcuBQCIAgAAAA==.',
Ci='Cirxe:BAABNQAECn8qAAIXAAkKQwUCeQDMAAAXAAkKQwUCeQDMAAAAAA==.',
Cl='Clarkent:BAAANQAECgUICAAAAA==.',
Co='Coms:BAABNQAECn8UAAIOAAgKVAvnxACSAQAOAAgKVAvnxACSAQAAAA==.',
Cr='Crayze:BAAANQAECgIIBgAAAA==.Creatinepowa:BAAANQADCgEIAQAAAA==.',
Cu='Curuni:BAAANQADCgYIBgAAAA==.',
['Cø']='Cønstance:BAABNQAECn8cAAIJAAkKUBtzBgCeAQAJAAkKUBtzBgCeAQAAAA==.',
Da='Dabai:BAABNQAECn8uAAIOAAoKyRQPbABZAgAOAAoKyRQPbABZAgAAAA==.Dahliaa:BAAANQADCgMIAwAAAA==.Daipailaotie:BAABNQAECn8kAAMOAAkKdQcs1ABzAQAOAAkK+QYs1ABzAQAYAAUKVQZQVgCIAAAAAA==.Dalight:BAAANQAECgUICAAAAA==.Dankins:BAABNQAFFH8PAAIVAAUK4B1eCADNAQAVAAUK4B1eCADNAQAAAA==.Darealfarmer:BAAANQADCgcIBwAAAA==.Darkzoomies:BAAANQAECgMIAwAAAA==.Darthravens:BAAANQABCgQIBAAAAA==.',
De='Deathmager:BAAANQADCggIEAAAAA==.Depar:BAAANQAECgMIAwAAAA==.Dethsent:BAAANQAECgIIAgAAAA==.Dette:BAAANQAECgYIDgAAAA==.Devourer:BAABNQAECn9SAAIIAAoKmiQ4AABnAwAIAAoKmiQ4AABnAwAAAA==.',
Dk='Dkboss:BAAANQADCgYIEQABNQAECggIIgAQABgeAA==.',
Do='Doctrdoom:BAAANQADCggIFQABNQAECgoKNwABAOcgAA==.',
Dr='Drafted:BAAANQAECgYIDQAAAA==.Dragondank:BAAANQAFFAEIAgABNQAFFAUIDwAVAOAdAA==.Drukah:BAAANQAECgIIAgAAAA==.',
Dt='Dtrike:BAAANQAECgIIBAAAAA==.',
Ed='Edstark:BAABNQAECn8gAAIEAAcK0wLqZwDZAAAEAAcK0wLqZwDZAAAAAA==.Edwinranger:BAAANQAECggIAQAAAA==.',
El='Elabernathy:BAABNQAECn8ZAAICAAgKjAr5LwBhAQACAAgKjAr5LwBhAQAAAA==.Elenay:BAABNQAECn8cAAIHAAkK8R5MFQAdAwAHAAkK8R5MFQAdAwAAAA==.Eliarssande:BAAANQAECgYIDAAAAA==.Elliemental:BAAANQADCgQIBAAAAA==.Elpatron:BAABNQAECn8uAAIGAAkKEyKABQBqAwAGAAkKEyKABQBqAwAAAA==.Elylanea:BAAANQADCggICAAAAA==.',
Em='Emulsdeath:BAABNQAECn8mAAIKAAgKTiEkLgB5AgAKAAgKTiEkLgB5AgABNQAECgoKRgAOAAglAA==.Emulsifier:BAABNQAECn9GAAIOAAoKCCUNAgDxAwAOAAoKCCUNAgDxAwAAAA==.Emulslash:BAAANQADCgYIDAABNQAECgoKRgAOAAglAA==.',
Ev='Evideia:BAAANQADCgQJBAABNQAECgcIKwACAGAhAA==.',
Ex='Expiatory:BAAANQADCgEIAQAAAA==.Expiredbeef:BAAANQADCgYIBgAAAA==.',
Fa='Farcha:BAAANQAECgQICAAAAA==.',
Fi='Fidge:BAAANQADCgYIBgAAAA==.Finester:BAABNQAECn8ZAAMRAAoKMx5aDgAQAwARAAoKMx5aDgAQAwAMAAUKZhT+MwAbAQAAAA==.',
Fl='Flatline:BAABNQAECn8VAAIBAAgKPxBvrwByAQABAAgKPxBvrwByAQAAAA==.',
Fu='Funslinger:BAAANQADCggICgAAAA==.',
Ga='Gagners:BAABNQAECn8UAAIRAAcK+hpDLQAxAgARAAcK+hpDLQAxAgABNQAECgoKRgAOAAglAA==.',
Go='Gorska:BAABNQAECn8kAAIZAAkKuhtcNgCeAgAZAAkKuhtcNgCeAgAAAA==.',
Gr='Grawm:BAAANQAECgYIDgAAAA==.Gritshaman:BAAANQAECgcICAABNQAECgoKNwABAOcgAA==.',
['Gä']='Gämbit:BAAANQAECgUIBQAAAA==.',
Ha='Hangman:BAAANQAECgYIDQAAAA==.Hanni:BAAANQAECgUIBQAAAA==.Harakutoo:BAAANQADCgcIBwAAAA==.Hawktoetem:BAAANQADCgQIBAAAAA==.Hawktoouh:BAABNQAECn8qAAMaAAkK4hyhCgA6AgAaAAkK4hyhCgA6AgAbAAIKqQSuMgA3AAAAAA==.',
He='Hellshand:BAAANQAECgUICQAAAA==.Helmhammer:BAAANQAECgEIAQAAAA==.',
Hi='Hinxx:BAAANQAECgMIAwAAAA==.',
Ho='Holychaser:BAAANQAECgMJBwAAAA==.Holycrack:BAABNQAECn8XAAIYAAcK1SIiAwD8AQAYAAcK1SIiAwD8AQABNQAECgoKKQABAAwiAA==.Holycøw:BAAANQAECgEIAQAAAA==.Holydefender:BAAANQADCgMIAwAAAA==.Holyfyree:BAAANQADCgcICAABNQAECggIHgANAL8QAA==.Holypawk:BAABNQAECn8ZAAIYAAkKdhf1GwANAgAYAAkKdhf1GwANAgAAAA==.Holyrock:BAABNQAECn8aAAIOAAgKQRGpTgAnAQAOAAgKQRGpTgAnAQAAAA==.Honorheart:BAAANQADCgMIBgAAAA==.',
['Hó']='Hóly:BAAANQADCgEJAQABNQAECgYICQASAAAAAA==.',
Ih='Ihureciv:BAABNQAECn8iAAIUAAoKERfDIgA3AgAUAAoKERfDIgA3AgABNQAECgoKVQAbAKgjAA==.',
Ik='Ikur:BAABNQAECn8wAAIFAAkKlR0+EQDLAQAFAAkKlR0+EQDLAQAAAA==.',
In='Infoxicated:BAAANQAECgYIBgABNQAECgoKHAAFAMAdAA==.',
Ip='Ipopkidneys:BAACNQAFFH8bAAMMAAcK0SK+BADdAQAMAAUK8CO+BADdAQARAAIKISFRBACxAAA1AAQKfycAAwwACgp/Jb4MAKkCAAwACQqOJb4MAKkCABEABAo3JO1QAHoBAAAA.',
Ir='Iroi:BAAANQAECgIJAgAAAA==.',
Is='Iskur:BAAANQAECgYIEQABNQAECgkJMAAFAJUdAA==.Isurr:BAAANQAECgUIDQABNQAECgkJMAAFAJUdAA==.',
Iv='Ivanapump:BAAANQAECgQIBAAAAA==.',
Ja='Jadhar:BAAANQAECgIIBAAAAA==.Jametrok:BAABNQAECn8aAAIOAAgK4BW+lAD6AQAOAAgK4BW+lAD6AQAAAA==.Jastra:BAAANQADCgcIDgAAAA==.',
Je='Jennyanydots:BAAANQADCggIDAABNQAFFAcIFwAbABESAA==.',
Ji='Jiraîya:BAABNQAECn8ZAAIZAAkKUg/cIQA0AQAZAAkKUg/cIQA0AQAAAA==.',
Jo='Jordak:BAABNQAECn8jAAIGAAkKDhxBEwCzAgAGAAkKDhxBEwCzAgAAAA==.Joshua:BAAANQADCgQIBAAAAA==.',
Ju='Jumbok:BAABNQAECn8cAAIXAAcK6hPv4wDBAQAXAAcK6hPv4wDBAQAAAA==.Just:BAABNQAECn8eAAMKAAkKhg90FwAnAQAKAAkKQg90FwAnAQAcAAQKFAvJdwDEAAAAAA==.',
Ka='Kaddiya:BAAANQADCgYIBgAAAA==.Kaine:BAAANQADCgUIBQAAAA==.Kallistos:BAABNQAECn8sAAIVAAkKtBUwEADXAQAVAAkKtBUwEADXAQAAAA==.Kangaroo:BAAANQADCgQIBAAAAA==.Kaste:BAAANQAECgQIBgAAAA==.Katalaana:BAAANQAECgEIAQAAAA==.',
Ke='Kevdogg:BAABNQAECn8iAAMXAAgK4gWQYgD4AAAXAAgKRAWQYgD4AAAdAAEKlQV/DgAuAAAAAA==.Key:BAACNQAFFH8LAAMOAAQKNCDUDgBfAQAOAAQKNCDUDgBfAQAFAAEKbwusJwBOAAA1AAQKfyoAAw4ACgowJTQvAAwDAA4ACgowJTQvAAwDAAUABwr/FOR2ALMBAAAA.',
Kh='Khione:BAAANQADCgcIFQAAAA==.',
Ki='Kindsöul:BAAANQAECgQICAABNQAFFAQIDwAJAA4WAA==.',
Ko='Kobol:BAAANQAECgQIBAAAAA==.Koluvan:BAAANQADCggIGQAAAA==.Koopa:BAABNQAECn8mAAIeAAkKmiBFAADfAgAeAAkKmiBFAADfAgAAAA==.',
Kr='Krieg:BAAANQAECgYIBgABNQAFFAUIDQAHAJkjAA==.Kromdar:BAAANQADCgMIAwAAAA==.',
Ky='Kyuketsuki:BAAANQADCgEIAQAAAA==.',
Le='Leahan:BAAANQABCgMIAwAAAA==.',
Lh='Lhureciv:BAABNQAECn9VAAMbAAoKqCPXAgCuAwAbAAoKqCPXAgCuAwAaAAQKWhaBqAAcAQAAAA==.',
Li='Lilkaren:BAAANQABCgMIAwABNQAECggIFQARAKcNAA==.Lillianna:BAABNQAECn8WAAIMAAcKYw5nIgC3AQAMAAcKYw5nIgC3AQAAAA==.Lilsensual:BAABNQAECn8eAAIVAAgKahMFZADhAQAVAAgKahMFZADhAQABNQAECgoKOAAYAA8aAA==.',
Lo='Loads:BAAANQAECgQIAwAAAA==.Loenhart:BAAANQADCgIIAgAAAA==.Logically:BAAANQADCgUIBQAAAA==.Lolkurtone:BAAANQAECgQIBAAAAA==.',
Lu='Luceus:BAABNQAECn8iAAIYAAoK/A+eCgBQAQAYAAoK/A+eCgBQAQAAAA==.Lucário:BAABNQAECn8mAAIPAAkKaCSxFwBaAwAPAAkKaCSxFwBaAwAAAA==.Lugia:BAAANQADCgYJCwAAAA==.Lunadawn:BAAANQAECgYIEAAAAA==.Lunastorm:BAABNQAECn9DAAIfAAoKcxxjDgDCAgAfAAoKcxxjDgDCAgAAAA==.Luponero:BAACNQAFFH8gAAMUAAcKqRiBAgBAAQAUAAYKxhiBAgBAAQACAAEKNhg0FQBeAAA1AAQKfyUAAxQACgrrILsYAJECABQACgqNILsYAJECAAIAAQoCJOhGAVEAAAAA.',
Ma='Macmn:BAACNQAFFH8LAAIZAAUKmB2/CQDRAQAZAAUKmB2/CQDRAQA1AAQKfycAAhkACQoUJvcFALoDABkACQoUJvcFALoDAAAA.Magej:BAAANQADCgQIBAAAAA==.Mageyouacake:BAAANQADCgQIBAAAAA==.Mamaheals:BAABNQAECn8nAAIaAAoKSSBVCgA/AgAaAAoKSSBVCgA/AgAAAA==.Mandos:BAABNQAECn8wAAILAAoKeSKvAQDFAgALAAoKeSKvAQDFAgAAAA==.Mantistabogn:BAAANQAECgcICgAAAA==.Manzoholy:BAAANQADCgMIAwAAAA==.Maor:BAAANQAECgEIAQAAAA==.',
Me='Merlerk:BAAANQAECgIIAgABNQAFFAUIEwAZALUXAA==.Merlini:BAABNQAECn8kAAMbAAoKYA9wJgD6AQAbAAoKYA9wJgD6AQAgAAUKTBWeEgD9AAAAAA==.Metrohexual:BAABNQAECn8mAAIVAAoK6BetLgAoAQAVAAoK6BetLgAoAQAAAA==.Mets:BAAANQAECggIDwABNQAECgoKHQABAHEZAA==.',
Mi='Mikasa:BAAANQAECgQIBAABNQAECgYICQASAAAAAA==.Mitzis:BAABNQAECn8iAAICAAoKiRyaMwDRAgACAAoKiRyaMwDRAgAAAA==.',
Mn='Mnm:BAAANQAECgQIBAAAAA==.',
Mo='Moltiy:BAAANQADCgEIAQAAAA==.Moltten:BAAANQAECgUIBQAAAA==.Moondo:BAECNQAFFH8eAAIHAAcKpiIqAwCVAgAHAAcKpiIqAwCVAgA1AAQKfywAAwcACgq3IlYPAE4DAAcACQrNJFYPAE4DAAYABQpFC4lZAKEAAAE1AAUUAggCABIAAAAA.',
['Mè']='Mètis:BAABNQAECn8rAAICAAcKYCHpUAB9AgACAAcKYCHpUAB9AgAAAA==.',
Na='Naahx:BAAANQAECgcICgABNQAECgkJIQARAB0kAA==.Nall:BAAANQAECgQIBAAAAA==.',
Ne='Nefarius:BAACNQAFFH8GAAIbAAIKVxFaBwCZAAAbAAIKVxFaBwCZAAA1AAQKfygAAhsACgp7HYILAC0DABsACgp7HYILAC0DAAAA.Neuropolis:BAAANQADCgYIBgAAAA==.Neurotics:BAABNQAECn8qAAQBAAgKeiRRHAAUAwABAAgKOiNRHAAUAwAhAAQKhCXBDQB7AQAiAAUKviGIBQDPAAAAAA==.',
Ni='Nighthigh:BAAANQAECgEIAQAAAA==.Nineoneone:BAABNQAECn8tAAIaAAgKRxsxEwDaAQAaAAgKRxsxEwDaAQAAAA==.',
No='Noperr:BAAANQAECggICAAAAA==.',
Nu='Nurmally:BAAANQAECgcICwABNQAFFAUIBgACAAwPAA==.Nuuot:BAAANQAECgcIDQAAAA==.',
Oc='Ocra:BAABNQAECn8hAAIjAAgKhBHzCABlAQAjAAgKhBHzCABlAQABNQAECgoKPgACAIMeAA==.',
Of='Offspeck:BAAANQAECgQIBQABNQAECgoKNwABAOcgAA==.',
Ol='Oldirtycasta:BAAANQAECgEIAgABNQAECgcIJwAIANIVAA==.',
On='Onayhawe:BAAANQAECgQIBgAAAA==.',
Or='Origen:BAAANQADCgcIBwABNQAECgoKQgAOALAkAA==.',
Ou='Outbreak:BAAANQADCggICAAAAA==.',
Pa='Paladio:BAABNQAECn8kAAIOAAgKNQbVfQDPAAAOAAgKNQbVfQDPAAAAAA==.Pallysmack:BAAANQADCgEIAQAAAA==.Pandapwr:BAAANQADCgcIDwABNQAECgoKGAAMAFgSAA==.Pandemul:BAAANQADCggICAABNQAECgoKRgAOAAglAA==.Patrio:BAAANQADCgYICwABNQAECgkJLgAGABMiAA==.Pawkler:BAAANQAECgQIBAABNQAECgkJGQAYAHYXAA==.Pawshira:BAAANQADCgUIBQABNQAECgkJGQAYAHYXAA==.',
Pe='Peachie:BAAANQADCgcIBwAAAA==.Peetree:BAABNQAECn8mAAIVAAoK4SAlFgAfAwAVAAoK4SAlFgAfAwAAAA==.Perfectcell:BAAANQADCgYICwAAAA==.Petures:BAAANQAECgMIAwAAAA==.',
Ph='Phosphorus:BAABNQAECn90AAMPAAoKrBzBLQAGAwAPAAoKohvBLQAGAwAQAAkKKBm6BQBoAQAAAA==.',
Pl='Plagüë:BAABNQAECn9AAAMKAAoKux4OEgAnAwAKAAoKYh0OEgAnAwALAAkK+B4dFwD0AgAAAA==.',
Po='Polor:BAAANQADCgQIBAAAAA==.',
Pr='Precious:BAAANQAECgUICQAAAA==.Primalistic:BAAANQAECgQIBQAAAA==.',
Pu='Pullnprey:BAAANQADCgMIBAAAAA==.Purgedoctor:BAABNQAFFH8IAAIVAAMK8h0nFQAIAQAVAAMK8h0nFQAIAQAAAA==.',
['Pà']='Pàladin:BAAANQADCgYIBgAAAA==.',
Qt='Qtptt:BAACNQAFFH8YAAIBAAcKNiCXAQCTAgABAAcKNiCXAQCTAgA1AAQKfysAAgEACgpRJZMLAHADAAEACgpRJZMLAHADAAAA.',
Ra='Ravenofchaos:BAAANQADCggICAAAAA==.Ravenoflight:BAAANQAECgIIAwAAAA==.Ravenshatred:BAAANQAECgQICAAAAA==.Ravenswrath:BAAANQADCgYIBgAAAA==.Rawrsaur:BAAANQAECgYIDgAAAA==.',
Re='Reallyhpal:BAAANQAECggICwAAAA==.Recon:BAAANQADCgMIAwABNQAECgoKGAAHALAFAA==.Redpocket:BAAANQAECgEIAQAAAA==.Rein:BAABNQAECn8YAAIQAAYKbQgdDQDeAAAQAAYKbQgdDQDeAAAAAA==.Remin:BAAANQAECgUIBAAAAA==.Retaliator:BAAANQAECgEIAQAAAA==.Reuuín:BAAANQADCggIDAABNQAECgYIEAASAAAAAA==.Revan:BAAANQADCggIDgAAAA==.',
Ri='Rimooru:BAAANQAECgQICAABNQAECgoKPQAEALshAA==.Risquae:BAAANQAECgEIAQAAAA==.',
Ro='Romulis:BAAANQAECgIIAwAAAA==.Rosè:BAABNQAECn8hAAIGAAoKDxfRAwBJAgAGAAoKDxfRAwBJAgABNQAECgoKMAALAHkiAA==.',
Ru='Ruka:BAAANQAECgQIBQAAAA==.',
Ry='Ryguyro:BAAANQADCgIJAgAAAA==.Ryhia:BAAANQAECgIIAgABNQAECgoKMAALAHkiAA==.Ryzee:BAABNQAECn8cAAIXAAkKIhN3sAAiAgAXAAkKIhN3sAAiAgABNQAECgoKKQAZAK4YAA==.',
['Rí']='Ríco:BAAANQADCgYIDgAAAA==.',
Sa='Sajaboy:BAAANQADCgIIAgAAAA==.Salena:BAAANQAECgQIBwAAAA==.Sartha:BAABNQAECn8mAAIOAAgKQxXvJQCOAQAOAAgKQxXvJQCOAQAAAA==.Sasuka:BAAANQAECgUICwABNQAECgYIDAASAAAAAA==.Savagesoso:BAAANQADCgQJBAAAAA==.',
Sc='Schy:BAAANQAECgIIAgAAAA==.Scrumpheals:BAAANQAECgEIAQAAAA==.',
Se='Sedda:BAACNQAFFH8JAAIOAAUKDx/BCQCsAQAOAAUKDx/BCQCsAQA1AAQKfygAAg4ACQqCJWIXAGcDAA4ACQqCJWIXAGcDAAAA.Sensual:BAABNQAECn84AAIYAAoKDxpBDwCpAgAYAAoKDxpBDwCpAgAAAA==.Sesshomaru:BAABNQAECn89AAIEAAoKuyG6BACnAwAEAAoKuyG6BACnAwAAAA==.',
Sh='Shampain:BAABNQAECn8aAAMjAAgKKQpZHACeAQAjAAgKKQpZHACeAQAVAAUKtw6VawB6AAABNQAECgoKTgAFAMYfAA==.Shampooh:BAAANQADCggICAAAAA==.Shang:BAACNQAFFH8NAAIHAAUKmSPIBwAMAgAHAAUKmSPIBwAMAgA1AAQKfysAAgcACgpeJY4FAKoDAAcACgpeJY4FAKoDAAAA.Shanzo:BAAANQAECggIAwAAAA==.Shiftshot:BAAANQAECgUIBQAAAA==.Shirona:BAABNQAECn8qAAMEAAoKlx9RAQDtAgAEAAoKlx9RAQDtAgAIAAcKCgmJOwBqAQAAAA==.Shloomish:BAAANQAECgYIBgAAAA==.Shmized:BAAANQAECgEIAQAAAA==.Shãde:BAAANQADCgIIAgAAAA==.Shïnwolford:BAABNQAECn8xAAIXAAoKzh8IBgBxAgAXAAoKzh8IBgBxAgABNQAECgoKPQAEALshAA==.',
Si='Siare:BAABNQAECn8dAAIBAAoKcRmXCAAcAgABAAoKcRmXCAAcAgAAAA==.',
Sk='Skeeter:BAABNQAECn8kAAQiAAgKPRqGFADLAQABAAYKcxVYhADbAQAiAAYKtBiGFADLAQAhAAQK+Q37EwALAQAAAA==.Skroncer:BAAANQADCgYIEgAAAA==.',
Sm='Smokinjawn:BAAANQADCgMIAwAAAA==.Smòtts:BAABNQAECn8gAAIJAAgKcxqmDwBnAgAJAAgKcxqmDwBnAgAAAA==.Smótts:BAAANQADCggJEwAAAA==.',
Sn='Sneekee:BAAANQAECgIIBAABNQAECgQIBAASAAAAAA==.Snizard:BAABNQAECn8XAAICAAYKIRNXswCdAQACAAYKIRNXswCdAQAAAA==.Snuggiepoo:BAAANQADCgIIAgABNQAECgoKHAAFAMAdAA==.',
So='Soawesome:BAAANQAECgQICAABNQAECgcIJwAIANIVAA==.Solenoid:BAAANQAECgcIDgAAAA==.',
Sp='Spicymustard:BAAANQADCgYICgAAAA==.Springrollz:BAAANQAECgEIAQAAAA==.Spàdes:BAAANQAECgIIAgAAAA==.',
Sq='Squírtlé:BAAANQADCgEIAQAAAA==.',
St='Stellanoova:BAAANQAECgYIDgABNQAECggIHgANAL8QAA==.Stormbeards:BAAANQADCgcIBwAAAA==.Stuwu:BAAANQABCgQIBAAAAA==.',
Su='Sugarcube:BAAANQAECgUICAABNQAFFAQIDwAJAA4WAA==.Sugarhigh:BAAANQABCgQIBAAAAA==.Sunlight:BAAANQADCggICQAAAA==.Sushirollz:BAAANQAECgIIAwAAAA==.',
Ta='Taazdingo:BAAANQADCggIEwAAAA==.Takin:BAAANQADCggICAAAAA==.Taxxwomann:BAACNQAFFH8HAAMiAAMKkxg2CACxAAAiAAIKsh02CACxAAABAAEKVg6KHABLAAA1AAQKfy8AAwEACgrVIvo4AKkCAAEACAp9Ivo4AKkCACIAAwrPHVUFANMAAAAA.',
Te='Teabear:BAAANQAECggIBgAAAA==.',
Th='Thisishard:BAABNQAECn8wAAIXAAoKFBbHCwATAgAXAAoKFBbHCwATAgAAAA==.Thryen:BAAANQAECgQICQAAAA==.Thundergrasp:BAABNQAECn8pAAIZAAoKrhjEAwBRAgAZAAoKrhjEAwBRAgAAAA==.',
To='Toe:BAAANQAFFAEIAgAAAA==.Toobestake:BAAANQAECgEIAgABNQAFFAcIIAAUAKkYAA==.Topenga:BAABNQAECn8+AAICAAoKgx7/GgAsAwACAAoKgx7/GgAsAwAAAA==.',
Tr='Trunnks:BAAANQAECgYIBQAAAA==.',
Ts='Tsargock:BAAANQADCgUIBAAAAA==.',
Tu='Tuoldforthis:BAAANQADCgcICQAAAA==.',
Tw='Twicelife:BAAANQAECgYICQABNQAECgoKdAAPAKwcAA==.',
Ty='Typhoid:BAAANQAECgYICgAAAA==.',
['Tñ']='Tñt:BAAANQAECgUIBAABNQAECgoKNwABAOcgAA==.',
Um='Umei:BAAANQAECgEIAQAAAA==.',
Ur='Urbek:BAABNQAECn8VAAIHAAcKGyDhLgBoAgAHAAcKGyDhLgBoAgAAAA==.Urthstripe:BAABNQAECn8hAAIGAAgK+ha0DgBXAQAGAAgK+ha0DgBXAQAAAA==.',
Uw='Uwu:BAAANQAECgUIBQABNQAFFAcIFwAbABESAA==.',
Va='Valle:BAAANQADCggIDgABNQAFFAcIFwAbABESAA==.Valoria:BAAANQAECggICAABNQAFFAcIFwAbABESAA==.',
Ve='Velgabrine:BAAANQAECgQICAABNQAECgoKRgAOAAglAA==.Veraani:BAAANQADCggICAAAAA==.Verlaria:BAAANQADCgEIAQAAAA==.',
Vi='Viserion:BAABNQAECn8eAAMNAAgKvxDeDACEAQANAAcK0xLeDACEAQAfAAUKkApxMwD7AAAAAA==.',
Vu='Vue:BAABNQAECn9OAAIFAAoKxh+rGwAGAwAFAAoKxh+rGwAGAwAAAA==.Vulkun:BAAANQAECgMIAwAAAA==.',
Wa='Wakasham:BAACNQAFFH8LAAIjAAQK0SSvAAAyAQAjAAQK0SSvAAAyAQA1AAQKfyYAAiMACQqzJqcAANQDACMACQqzJqcAANQDAAAA.Warwick:BAAANQABCgIIAgAAAA==.',
We='Wehonoryou:BAABNQAECn8ZAAMEAAkKtSAiFAD9AgAEAAkKtSAiFAD9AgAIAAIKUgjsYwBbAAABNQAFFAcIFwAIAC8eAA==.',
Wi='Wickedmisery:BAAANQADCgYIBgAAAA==.',
Wo='Wolfpacked:BAABNQAECn8bAAIVAAYKFhnpdgCnAQAVAAYKFhnpdgCnAQABNQAECgoKKQABAAwiAA==.',
Wr='Wrbringer:BAAANQADCgEIAQAAAA==.',
Wu='Wunderlust:BAABNQAECn85AAIXAAoK+x1gJwBEAwAXAAoK+x1gJwBEAwAAAA==.',
Xe='Xeroidz:BAAANQADCgcICgAAAA==.',
Xs='Xscrats:BAAANQAECggIAQAAAA==.',
Ye='Yellowshaman:BAACNQAFFH8JAAIZAAMKpA20GwDkAAAZAAMKpA20GwDkAAA1AAQKfykAAxkACQoqHs0mAOgCABkACQoqHs0mAOgCABUAAQoTDgiXADcAAAAA.Yerac:BAAANQAFFAQIBAAAAA==.',
Za='Zandelussy:BAABNQAECn8cAAIFAAoKwB14DAD/AQAFAAoKwB14DAD/AQAAAA==.',
Zu='Zugg:BAAANQAECgYIBgABNQAFFAcIFwAbABESAA==.Zuriznikov:BAAANQAECgUIEAABNQAECggIHgANAL8QAA==.',
['Øf']='Øffspeck:BAABNQAECn83AAQBAAoK5yAMFwAsAwABAAoKTSAMFwAsAwAhAAgK4RoABQB+AgAiAAYKyiKbDwADAgAAAA==.',
['ßo']='ßoss:BAAANQADCgQIBAABNQAECggIIgAQABgeAA==.',
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
