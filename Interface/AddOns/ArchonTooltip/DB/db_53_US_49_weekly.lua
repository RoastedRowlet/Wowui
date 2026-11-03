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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','Monk-Windwalker','Warrior-Arms','Priest-Holy','Priest-Discipline','Druid-Guardian','Shaman-Elemental','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','DemonHunter-Havoc','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','Druid-Feral','Druid-Restoration','Warlock-Destruction','DemonHunter-Devourer','Hunter-Marksmanship','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Evoker-Augmentation','DeathKnight-Frost','Mage-Fire','DeathKnight-Unholy','DemonHunter-Vengeance','Hunter-Survival','Druid-Balance','Priest-Shadow','Rogue-Subtlety','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Warrior-Protection',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aahhotep:BAAANQADCgUICQAAAA==.',
Ag='Agnestachyon:BAAANQAECgYICAAAAA==.',
Ai='Aitwa:BAAANQADCggICAAAAA==.',
Ak='Aksnowman:BAAANQADCgYICAAAAA==.',
Al='Alanbrito:BAAANQAECgMIBAAAAA==.Albus:BAAANQAECgUIDgABNQAECgkJKgABAAUeAA==.Aliane:BAAANQAECgUICgAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAAANQAECgUIDwAAAA==.Alísea:BAAANQAECgEIAQAAAA==.',
Am='Amoonday:BAAANQAECgUICwAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.Andrewsmom:BAEANQAECgQIBAABNQAECgoKNwACAL8kAA==.',
Ar='Aramoonsong:BAABNQAECn9PAAIDAAoK9yMMAwCpAwADAAoK9yMMAwCpAwAAAA==.Aranrùth:BAABNQAECn8zAAIEAAkKJiGPGgDFAgAEAAkKJiGPGgDFAgAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Arcani:BAAANQAECgEIAgAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arnoldd:BAAANQAECggICAAAAA==.Arthin:BAAANQABCgQIBAAAAA==.',
As='Ashbowbaby:BAAANQAECggIDQAAAA==.',
Au='Auraborealis:BAABNQAECn8iAAMFAAcKSBVxUQC7AQAFAAcKSBVxUQC7AQAGAAQKPwW5GQCeAAAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAABNQAECn8dAAIHAAcKmR9DFAAhAgAHAAcKmR9DFAAhAgAAAA==.',
Az='Azuael:BAAANQAECggICAAAAA==.',
Ba='Baberaham:BAAANQAECgEIAQAAAA==.Baki:BAAANQAECggIDwAAAA==.Ballzdragon:BAAANQAECgcIDAABNQAFFAUIBwAIAAYIAA==.Balzamon:BAABNQAECn80AAIEAAoKNQpObACDAQAEAAoKNQpObACDAQAAAA==.Bamabill:BAAANQAECggICAAAAA==.Bandgeek:BAABNQAECn8uAAMJAAoKhh+iHAC2AgAJAAoKhh+iHAC2AgAKAAQKwhOAIgDXAAAAAA==.Bantôt:BAAANQADCggIFgAAAA==.',
Be='Beegood:BAABNQAECn8yAAILAAkKJwdzvgCGAQALAAkKJwdzvgCGAQAAAA==.Beweaver:BAEANQADCggICAABNQAECgkJFgAJAHcJAA==.',
Bi='Biebert:BAABNQAECn8nAAIEAAkKwRMpiAAIAgAEAAkKwRMpiAAIAgAAAA==.Bizzy:BAAANQADCgcICgAAAA==.',
Bl='Blooddemon:BAAANQAECgEIAQABNQAECgoKOQAMAEEWAA==.Bloodegg:BAABNQAECn8xAAILAAoKfAthigD2AQALAAoKfAthigD2AQAAAA==.',
Bo='Boinkadin:BAAANQAECgQIBQAAAA==.Boinkydk:BAAANQAECgYIDQAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQAECgQICwAAAA==.Bredarra:BAAANQADCgYIBgAAAA==.Brewzlee:BAAANQAECgQIBgABNQAECgoKHAABAFEVAA==.Broomphondle:BAABNQAECn8fAAIJAAcKeA2GFwFlAQAJAAcKeA2GFwFlAQAAAA==.Brootis:BAAANQADCgYIBQAAAA==.Brothetucker:BAAANQADCgcIEAAAAA==.',
Bs='Bshoottu:BAABNQAECn8gAAILAAUKWQfjygDXAAALAAUKWQfjygDXAAAAAA==.',
Bu='Bubblina:BAAANQAECgEIAwAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQANAAAAAA==.',
Ce='Celestìa:BAAANQAECgYICQAAAA==.Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQAECgIIBQAAAA==.Chrisswamy:BAAANQABCgYIBwAAAA==.Chromesatan:BAAANQAECggIBwABNQAECgoKHAABAFEVAA==.Chubtubs:BAAANQAECgYIBwABNQAFFAUIEwAFAHsYAA==.Chuglee:BAAANQAECggIDAAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQADCggIJwAAAA==.',
Cr='Crankypal:BAAANQAECgQICwAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
Cw='Cwdcannabull:BAAANQAECgEIAQAAAA==.',
['Cá']='Cárl:BAAANQABCgIIAgAAAA==.',
Da='Daemage:BAAANQAECggIDAAAAA==.Dagara:BAAANQADCgIIAgAAAA==.Daredevill:BAAANQADCgEIAQAAAA==.Darkdrittz:BAABNQAECn8fAAIOAAcKNwkVRADkAAAOAAcKNwkVRADkAAAAAA==.Darkjazz:BAAANQAECgYICAAAAA==.',
De='Deadash:BAAANQAECgEIAQABNQAECggIDQANAAAAAA==.Deathclaw:BAABNQAECn8tAAIPAAkKGAwLawBcAQAPAAkKGAwLawBcAQAAAA==.Deceptiõn:BAAANQABCgYIBgAAAA==.Deldúwath:BAABNQAECn8qAAMQAAoKQA+VDQDMAQAQAAkKQA+VDQDMAQARAAgK7AkLDACdAQAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dinklage:BAAANQAECgMIBAAAAA==.Dionus:BAABNQAECn80AAIBAAkKFAmBxwCNAQABAAkKFAmBxwCNAQAAAA==.',
Do='Doanh:BAAANQABCgYICAAAAA==.Dolorquedura:BAAANQAECgEIAQAAAA==.Domenic:BAAANQADCgIIAgAAAA==.Domoarigato:BAEANQAECgQICAABNQAECgkJFgAJAHcJAA==.',
Dr='Drakuluh:BAAANQAECgUICAAAAA==.Draucan:BAABNQAECn8yAAMGAAoKYx+tAQC8AgAGAAgKniCtAQC8AgAFAAMKTBm/mADaAAAAAA==.Dreadmoor:BAAANQADCggIFwABNQAECgYIIgAPAKcNAA==.Dribblesnot:BAABNQAECn8iAAIPAAYKpw07vQBSAQAPAAYKpw07vQBSAQAAAA==.Driden:BAAANQAECgYIDwAAAA==.',
Dy='Dya:BAAANQAECgMIBAAAAA==.',
Ec='Echolock:BAAANQAECgUIDAAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgANAAAAAA==.Elemetzy:BAABNQAECn8dAAQSAAoKFhh7DwDjAQASAAkKRhd7DwDjAQAIAAUK9RcQngBbAQAMAAQKUglDnQC4AAAAAA==.Elkul:BAAANQAECgQICQAAAA==.Elsoned:BAABNQAECn8fAAIBAAcKSA/auwAbAQABAAcKSA/auwAbAQAAAA==.',
Er='Errob:BAAANQAECgEIAQAAAA==.',
Eu='Euclid:BAAANQAFFAEIAQAAAA==.',
Ev='Evokyn:BAAANQADCgIIAgAAAA==.',
Fa='Falafel:BAABNQAECn8qAAIBAAgKwxB72ABqAQABAAgKwxB72ABqAQAAAA==.Fattaco:BAABNQAECn85AAIMAAoKQRbPNgAOAgAMAAoKQRbPNgAOAgAAAA==.',
Fi='Fizzlestix:BAEBNQAECn8WAAIJAAkKdwklgQB4AQAJAAkKdwklgQB4AQAAAA==.',
Fl='Floss:BAABNQAECn8aAAIBAAYK3AnH8QA5AQABAAYK3AnH8QA5AQAAAA==.Flubb:BAABNQAECn87AAMTAAoKLyQUAgCeAwATAAoKLyQUAgCeAwAUAAEKhQODegApAAAAAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQAECggIEAABNQAECggIMQANAAAAAA==.Followmenot:BAABNQAECn8nAAIKAAkKyBEpEACkAQAKAAkKyBEpEACkAQAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frëyæ:BAAANQADCgQIBAABNQAFFAUIBwAIAAYIAA==.',
Fu='Furgus:BAAANQAECgEIAgABNQAECggIIgAVAAkIAA==.',
Fy='Fyerflise:BAAANQADCgUICQAAAA==.Fyrakkobama:BAEANQAECgIIAQABNQAECgoKNwACAL8kAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Gn='Gnomesane:BAAANQAECgEIAQAAAA==.',
Go='Gobblegobble:BAABNQAECn8mAAIWAAcKGxl6KgDuAQAWAAcKGxl6KgDuAQAAAA==.Gosudizzle:BAACNQAFFH8FAAILAAIK0QdTIQByAAALAAIK0QdTIQByAAA1AAQKfy8AAwsACgpeIIMVAEYDAAsACgpeIIMVAEYDABcAAQoAAJpzAAAAAAE1AAQKCQkhAA4AXRIA.',
Gr='Griffith:BAAANQADCggICAAAAA==.Grippingtaco:BAAANQAECgQICQABNQAECgoKOQAMAEEWAA==.',
Gu='Gulldarilynn:BAAANQAECgUIDwAAAA==.',
Gw='Gwendolyn:BAABNQAECn9JAAMTAAoKOiaPAAB+AwATAAoKOiaPAAB+AwAUAAIKJBAEZwBpAAABNQAECgoKTwADAPcjAA==.Gweniveere:BAAANQADCgcIBwAAAA==.',
Ha='Hakubell:BAACNQAFFH8NAAIYAAcK/RuSCQDHAQAYAAcK/RuSCQDHAQA1AAQKfzwAAxgACgqIJHIEAK8DABgACgqIJHIEAK8DAAEABQpdIHe/AJ4BAAAA.Hammershock:BAABNQAECn8mAAIMAAgKEBWqRQDKAQAMAAgKEBWqRQDKAQAAAA==.Hasdiel:BAAANQAECgYIDgAAAA==.',
He='Heartim:BAAANQAECgMIAwAAAA==.Heädaches:BAAANQAECgMIBQAAAA==.',
Ho='Holynuke:BAAANQAECgcIDAABNQAFFAYICwAZAP0OAA==.Hontar:BAAANQADCgEIAQAAAA==.',
Hu='Hussie:BAAANQADCgIIAgAAAA==.',
Ic='Ichabel:BAAANQAECgEIAQAAAA==.',
Il='Illimommy:BAACNQAFFH8VAAIWAAcKHxQdAwAxAgAWAAcKHxQdAwAxAgA1AAQKfygAAhYACgoNIzwIALoCABYACgoNIzwIALoCAAAA.',
In='Inkarok:BAABNQAECn8rAAIOAAgKPRQDLQBsAQAOAAgKPRQDLQBsAQAAAA==.',
Is='Ishkode:BAABNQAECn8yAAIaAAoKNwwaBwC0AQAaAAoKNwwaBwC0AQAAAA==.',
It='Itachi:BAAANQAECgcIEQAAAA==.',
Iz='Izzyrael:BAAANQAECgcICQAAAA==.',
Ja='Jalapeno:BAABNQAECn8ZAAIbAAcKpAfVEwDxAAAbAAcKpAfVEwDxAAAAAA==.Jami:BAEBNQAECn8hAAIcAAgKuBALQwC4AQAcAAgKuBALQwC4AQABNQAECgkJFgAJAHcJAA==.',
Je='Jellybean:BAAANQADCggIFwAAAA==.',
Ji='Jitlo:BAACNQAFFH8QAAIIAAYKfgsqCADxAQAIAAYKfgsqCADxAQA1AAQKf0kAAggACgqwJDAFAEsDAAgACgqwJDAFAEsDAAAA.Jitsham:BAAANQAECggIDQAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Jt='Jtclear:BAAANQADCgcICgAAAA==.',
Ju='Juanillo:BAAANQADCgcICgAAAA==.',
Ka='Kadybear:BAAANQAECgEIAwAAAA==.Kaety:BAAANQAECgEIAwAAAA==.Kalanrahl:BAABNQAECn8rAAQKAAoKoBNADQDeAQAKAAoKoBNADQDeAQAJAAcKVwoQLAFCAQAdAAIKAAAqDAAAAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.Kashanden:BAABNQAECn8aAAMCAAoK9x1wDwCIAgACAAkK9x1wDwCIAgAeAAQKdwaacwBAAAAAAA==.',
Ke='Kemaneral:BAEANQADCgIJAgABNQAECgkJFgAJAHcJAA==.',
Kh='Khaiduus:BAABNQAECn8sAAIIAAoKYRh1IgAzAgAIAAoKYRh1IgAzAgAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAABNQAECn87AAIfAAoKeR2nAwCRAgAfAAoKeR2nAwCRAgAAAA==.Kittsune:BAAANQADCggIDgAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggILwAAAA==.',
Ko='Kottenmouth:BAACNQAFFH8TAAIgAAUKWxyPAAARAQAgAAUKWxyPAAARAQA1AAQKfz4AAiAACgosIqYBAEoDACAACgosIqYBAEoDAAAA.',
Kr='Kreyall:BAAANQADCgUIEgAAAA==.Kritea:BAAANQAECgMIBQAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECn8oAAIEAAoK+gwbogDHAQAEAAoK+gwbogDHAQAAAA==.Kyta:BAABNQAECn8gAAIPAAYKCgp6qADOAAAPAAYKCgp6qADOAAAAAA==.',
La='Laupess:BAAANQAECgEIAQAAAA==.',
Le='Lebron:BAAANQAECgUIDAAAAA==.',
Li='Lightbrew:BAABNQAECn8cAAIBAAoKURVOSgAXAgABAAoKURVOSgAXAgAAAA==.Litmus:BAAANQADCgUIBQAAAA==.',
Lo='Locura:BAAANQADCggICQABNQAECgoKTwADAPcjAA==.',
Lu='Lululyn:BAAANQAECgEIAQAAAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAABNQAECn8zAAIeAAgK3ReMFwABAgAeAAgK3ReMFwABAgAAAA==.Magra:BAAANQABCgIIAgAAAA==.Makersmartun:BAAANQAECgMIBAAAAA==.Malthira:BAAANQAECgEIAgAAAA==.Matterdaddy:BAAANQADCgcIBwABNQAECgoKJgAgAGcgAA==.',
Mi='Milbi:BAAANQAECgEIAgAAAA==.Minadette:BAAANQAECgUIBQAAAA==.',
Ml='Mljr:BAABNQAECn8fAAIJAAgKgAoAjwBaAQAJAAgKgAoAjwBaAQAAAA==.Mljrone:BAAANQAECgQIBQAAAA==.',
Mo='Moira:BAAANQAECgIIAgAAAA==.Mollicogs:BAAANQAECgEIAQAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAACNQAFFH8HAAIPAAcKCRMuEQB3AQAPAAcKCRMuEQB3AQA1AAQKf0EAAg8ACgpVIvsNAOICAA8ACgpVIvsNAOICAAAA.',
Mu='Munchkins:BAAANQAECgEIAgAAAA==.',
Mw='Mwesten:BAAANQAECgEIAwAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Naleen:BAEANQADCgIIAgABNQAECgoKNwACAL8kAA==.Nativelock:BAABNQAECn8pAAIaAAgKZAaNDQAWAQAaAAgKZAaNDQAWAQAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECggIEgAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.Nilrim:BAAANQABCgIIAgAAAA==.',
No='Norabelle:BAAANQAECgEIAQAAAA==.Nozomila:BAABNQAECn8UAAMTAAYKwx/YGABvAQATAAUKJCDYGABvAQAhAAUKOA5wdQD1AAAAAA==.',
Ny='Nynnaeve:BAABNQAECn8WAAMFAAYKJhjWXwCGAQAFAAYKJhjWXwCGAQAiAAMKlgM0ZABvAAAAAA==.',
['Nú']='Núrnen:BAAANQAECgMIAwAAAA==.',
On='Onthecoda:BAABNQAECn8wAAIUAAkKBiFZCQACAwAUAAkKBiFZCQACAwAAAA==.',
Oo='Oomgad:BAAANQADCgQICAAAAA==.',
Op='Opadden:BAAANQABCgIIAgAAAA==.Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgIIAQAAAA==.',
Pa='Paeus:BAAANQAECgEIAwAAAA==.Paigeturner:BAABNQAECn8tAAIJAAgKEASFvgAAAQAJAAgKEASFvgAAAQAAAA==.Palapets:BAAANQAECgIIAwABNQAECggICgANAAAAAA==.Pantherarosa:BAAANQAECgUIEAABNQAECggIIgAVAAkIAA==.Papalock:BAABNQAECn8cAAIPAAgKwxdRiwDKAQAPAAgKwxdRiwDKAQABNQAECgkJKgABAAUeAA==.Parenthi:BAAANQADCgEIAQAAAA==.Pazerp:BAAANQAECgEIAQAAAA==.',
Pe='Peaches:BAAANQADCgEIAQAAAA==.Persymphony:BAABNQAECn86AAIPAAoKCh2wHgB1AgAPAAoKCh2wHgB1AgAAAA==.',
Ph='Phabio:BAAANQAECggIEAAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAcIDQAMAD4LAA==.',
Pi='Pineappletea:BAABNQAECn8dAAIVAAYKyhFmGwCSAQAVAAYKyhFmGwCSAQAAAA==.Pinepally:BAAANQADCgQIBQAAAA==.Pinkee:BAAANQADCggICAAAAA==.Pinklock:BAABNQAECn8iAAIVAAgKCQgGDQDTAAAVAAgKCQgGDQDTAAAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.Pootsii:BAAANQADCgYIBgAAAA==.',
['Pø']='Pøøts:BAAANQAECgIIAgAAAA==.Pøøtsi:BAAANQAECgEIAQAAAA==.',
Qu='Quesy:BAACNQAFFH8MAAMeAAUKAxpRBwClAQAeAAUKbhNRBwClAQAcAAQKAxq+EACaAAA1AAQKfxsABB4ACgp8JBAQADYDAB4ACAqKJBAQADYDABwABQqIItg3AIQBAAIAAQoAAAAAAAAAAAE1AAUUBggLABkA/Q4A.',
Ra='Ragnapall:BAAANQAECgQICAABNQAFFAUIBwAIAAYIAA==.Ragnatotemzz:BAACNQAFFH8HAAIIAAUKBgj2FAApAQAIAAUKBgj2FAApAQA1AAQKfx0AAggACgoHHz88AIQCAAgACgoHHz88AIQCAAAA.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgMIAwAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgQIBgANAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgQIBgANAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Rellock:BAAANQADCgcIBwABNQAECgMIAwANAAAAAA==.Renalla:BAAANQAECgQIBAAAAA==.Renkari:BAAANQAECgcICgAAAA==.Rennl:BAABNQAECn8ZAAIBAAYKYwghGwHyAAABAAYKYwghGwHyAAAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICAABNQAECggIIgAVAAkIAA==.Ripsets:BAABNQAECn9AAAMLAAoKQyK6KQDxAgALAAkKUSK6KQDxAgAXAAgKbh/3HQBhAgAAAA==.',
Ro='Rogueloki:BAABNQAECn82AAMQAAoK1RcKPADhAQAQAAcKERMKPADhAQAjAAgKRxjxUgBpAQAAAA==.Roonrangi:BAAANQAECgUIBQAAAA==.Rowscaris:BAAANQAECgUICAAAAA==.',
Ru='Rufio:BAAANQAECgEIAQAAAA==.',
Ry='Rynna:BAABNQAECn8qAAIBAAkKBR6NPQBCAgABAAkKBR6NPQBCAgAAAA==.Rynya:BAAANQAECgMIAwAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAFFAUIBwAIAAYIAA==.',
Sa='Sailee:BAAANQAECgEIAQAAAA==.Samelthund:BAAANQABCgUICQAAAA==.Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgcILAAAAA==.Sarigos:BAABNQAECn8uAAMkAAgK7BWbDwDOAQAkAAcKHRWbDwDOAQAlAAQKywj5LAC5AAAAAA==.',
Sc='Schieldemon:BAACNQAFFH8HAAMWAAIKpQylDwBFAAAWAAIKpQylDwBFAAAOAAIKuQaeFwA/AAA1AAQKf1IAAxYACgpOG/oNAAgDABYACQqUHfoNAAgDAA4ACQr2ExUhAMcBAAAA.Scrythe:BAABNQAECn88AAICAAoKWxqxEgBcAgACAAoKWxqxEgBcAgAAAA==.Scynline:BAAANQADCgcICQAAAA==.Scynrine:BAAANQABCgIIAgAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQAECgYIDQAAAA==.Sharrin:BAAANQADCgYJBgAAAA==.Shoran:BAAANQADCgYIBgAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sk='Skkarrgh:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgUIBQAAAA==.Slime:BAAANQADCgYICwAAAA==.',
So='Solomoon:BAABNQAECn8VAAIFAAYKZByFaQDiAQAFAAYKZByFaQDiAQABNQAFFAcIDQAYAP0bAA==.Souleatr:BAABNQAECn8UAAIOAAkKxxB/LgBiAQAOAAkKxxB/LgBiAQAAAA==.',
Sp='Speisgote:BAABNQAECn8WAAMBAAYKvw1k7gA/AQABAAYKvw1k7gA/AQAmAAQKgQUqRABsAAAAAA==.Spieros:BAAANQAECgYIBgABNQAECgoKMgAGAGMfAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECggILgAkAOwVAA==.Starforge:BAAANQAECgIIAgAAAA==.Stealthpets:BAAANQADCggICQABNQAECggICgANAAAAAA==.Stealthragg:BAABNQAECn8YAAIjAAkKVRcgKwAcAgAjAAkKVRcgKwAcAgABNQAFFAUIBwAIAAYIAA==.Steelehorn:BAAANQADCgUIBQAAAA==.Stewpot:BAAANQADCggIDAAAAA==.Stigmã:BAAANQADCgYICwAAAA==.Stylish:BAABNQAECn8gAAQEAAoKYhJ2jwD2AQAEAAoKCBB2jwD2AQAnAAMKyRZANQCLAAAZAAEKHhEjMgA5AAAAAA==.',
Su='Suisui:BAAANQADCgcIGAAAAA==.Suling:BAAANQABCgIIAwAAAA==.Suunde:BAAANQADCgQIBAAAAA==.',
Sy='Sylathra:BAAANQABCgQIBAAAAA==.Syryn:BAABNQAECn8hAAILAAcKswncrQASAQALAAcKswncrQASAQAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQAECgMIAwABNQAECggIEgANAAAAAA==.Thorgrum:BAABNQAECn86AAMeAAoKOSZAAwBAAwAeAAoKOSZAAwBAAwAcAAIK6R/7fgCuAAAAAA==.Thûnderize:BAABNQAECn8+AAIIAAoKRB95HgBQAgAIAAoKRB95HgBQAgAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAABNQAECn8aAAIFAAgKChMmTADOAQAFAAgKChMmTADOAQAAAA==.Tirea:BAABNQAECn8aAAISAAcKPgzCGgC3AQASAAcKPgzCGgC3AQABNQAECgkJFAAOAMcQAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgcIKgAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Trashedpanda:BAAANQAECgcICwAAAA==.Trastuzumab:BAAANQADCgIIAgAAAA==.Tripoloski:BAABNQAECn8mAAMRAAoKxyItBADTAgARAAcK5CMtBADTAgAjAAkKiB4qEQBuAgAAAA==.',
Tu='Tugamuhpud:BAABNQAECn82AAMaAAkKoQPSHACYAAAPAAkKmQPdnADnAAAaAAUKxAHSHACYAAAAAA==.',
Ty='Tyllas:BAAANQADCgUIBAAAAA==.',
Tz='Tzzird:BAABNQAECn9AAAIBAAoK+x+QHADSAgABAAoK+x+QHADSAgAAAA==.',
Ug='Ugrah:BAABNQAECn8gAAIEAAkKQgzkqAC2AQAEAAkKQgzkqAC2AQAAAA==.',
Uk='Ukyomsi:BAAANQABCgIIAgABNQAECgkJFAAOAMcQAA==.',
Un='Undeadheals:BAAANQAECgQIBgAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgcICQAAAA==.Varod:BAAANQAECggIDQAAAA==.Vawdkuh:BAABNQAECn8xAAIhAAoKHBKZPQALAgAhAAoKHBKZPQALAgAAAA==.',
Ve='Velddor:BAABNQAECn8mAAIgAAoKZyBDAwDkAgAgAAoKZyBDAwDkAgAAAA==.Vellea:BAAANQAECgEIAQAAAA==.',
Vi='Vice:BAABNQAECn8XAAIBAAkKtAmorQA0AQABAAkKtAmorQA0AQAAAA==.Vignette:BAAANQAECgEIAwAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAgAAAA==.Vytux:BAAANQAECgEIAQAAAA==.',
['Vô']='Vôx:BAAANQAECgUIBgABNQAECgcIDQANAAAAAA==.',
['Vö']='Vöx:BAAANQAECgcIDQAAAA==.',
Wa='Wartrick:BAABNQAECn8fAAILAAoKtAijnADOAQALAAoKtAijnADOAQAAAA==.',
Wh='Whoudini:BAABNQAECn8dAAIVAAYKuAzbEAC2AAAVAAYKuAzbEAC2AAAAAA==.',
Xe='Xerãth:BAABNQAECn86AAIJAAoKSAh0egCHAQAJAAoKSAh0egCHAQAAAA==.',
Xi='Xiya:BAABNQAECn8aAAIFAAkK4xjhMQBFAgAFAAkK4xjhMQBFAgAAAA==.',
Ya='Yarndog:BAAANQAECgYICgAAAA==.Yarnell:BAABNQAECn8cAAIEAAcK+BDZiQA5AQAEAAcK+BDZiQA5AQAAAA==.Yaviel:BAABNQAECn8YAAILAAkKiw6qkADoAQALAAkKiw6qkADoAQAAAA==.',
Yu='Yushis:BAABNQAECn87AAIWAAoK1hiCEgAGAgAWAAoK1hiCEgAGAgAAAA==.',
Za='Zarrgon:BAEBNQAECn83AAMCAAoKvyQiBACvAwACAAoKqiQiBACvAwAeAAkKqRs5KwCJAgAAAA==.',
Ze='Zelderk:BAACNQAFFH8LAAMZAAYK/Q4XAwCgAAAEAAQKjw7yHAAqAQAZAAMK6A0XAwCgAAA1AAQKfzEAAwQACgr/I6ckACYDAAQACQprI6ckACYDABkABApQIKUQACwBAAAA.Zeromus:BAAANQADCgcICwAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQADCgEJAgABNQAECgoKQAABAPsfAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
Zz='Zzeb:BAAANQADCgQIBAAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQAECgMIAgAAAA==.',
['Âl']='Âlpally:BAAANQAECgQIBAAAAA==.',
['Ðr']='Ðrizzt:BAAANQADCggICAABNQAECgkJFAAOAMcQAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgkJFAAOAMcQAA==.',
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
