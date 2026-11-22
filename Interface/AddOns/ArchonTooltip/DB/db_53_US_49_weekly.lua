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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Monk-Windwalker','Warrior-Arms','Priest-Holy','Priest-Discipline','Druid-Guardian','Rogue-Subtlety','Shaman-Elemental','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','Monk-Mistweaver','DemonHunter-Havoc','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Druid-Balance','Shaman-Enhancement','Druid-Feral','Druid-Restoration','Warlock-Destruction','DemonHunter-Devourer','Hunter-Marksmanship','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Evoker-Augmentation','DeathKnight-Frost','Mage-Fire','DeathKnight-Unholy','DemonHunter-Vengeance','Hunter-Survival','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Warrior-Protection',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aahhotep:BAAANQADCgUICQAAAA==.',
Ag='Agnestachyon:BAAANQAECgYIBwAAAA==.',
Ai='Aitwa:BAAANQADCggICAAAAA==.',
Ak='Aksnowman:BAAANQADCgYICAAAAA==.',
Al='Alanbrito:BAAANQAECgMIAwAAAA==.Albus:BAAANQAECgYIEAABNQAECgkJLAABAEAfAA==.Aliane:BAAANQAECgUICgAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAABNQAECn8YAAMCAAgKwAexOgDCAAABAAcK4wZ9CQEPAQACAAcKiAexOgDCAAAAAA==.Alísea:BAAANQAECgUIBQAAAA==.',
Am='Amoonday:BAAANQAECgQICgAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.Andrewsmom:BAEANQAECgQIBAABNQAECgoKNwADAL8kAA==.',
Ar='Aramoonsong:BAABNQAECn9SAAIEAAoK9yMMAwCpAwAEAAoK9yMMAwCpAwAAAA==.Aranrùth:BAABNQAECn9BAAIFAAkKMyM6EAAXAwAFAAkKMyM6EAAXAwAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Arcani:BAAANQADCgIIAgAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arnoldd:BAAANQAECggICAAAAA==.Arthin:BAAANQABCgQIBAAAAA==.',
As='Ashbowbaby:BAAANQAECgYIDAAAAA==.',
Au='Auraborealis:BAABNQAECn8lAAMGAAkK/RLfRgAcAgAGAAkK/RLfRgAcAgAHAAQKPwW5GQCeAAAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAABNQAECn8gAAIIAAkKMx3rEgALAgAIAAkKMx3rEgALAgAAAA==.',
Az='Azuael:BAAANQAECggIBwAAAA==.',
Ba='Baberaham:BAAANQAECgEIAQAAAA==.Baki:BAABNQAECn8cAAIJAAkKIREUPQAIAgAJAAkKIREUPQAIAgAAAA==.Ballzdragon:BAAANQAECgcICwABNQAFFAYICAAKAI0JAA==.Balzamon:BAABNQAECn88AAIFAAoKNQoUgwCAAQAFAAoKNQoUgwCAAQAAAA==.Bamabill:BAAANQAECggICAAAAA==.Bandgeek:BAABNQAECn85AAMLAAoKhyFLGgDbAgALAAoKhyFLGgDbAgAMAAQKwhOAIgDXAAAAAA==.Bantôt:BAAANQADCggIIwAAAA==.',
Be='Beegood:BAABNQAECn9DAAINAAoK3wdLiwChAQANAAoK3wdLiwChAQAAAA==.Beweaver:BAEANQADCggICAABNQAECgkJGgALAPwKAA==.',
Bi='Biebert:BAABNQAECn8rAAIFAAoKiRIpiAAIAgAFAAoKiRIpiAAIAgAAAA==.Bizzy:BAAANQADCgcICgAAAA==.',
Bl='Blooddemon:BAAANQAECgIIAwABNQAECgoKOwAOAEEWAA==.Bloodegg:BAABNQAECn86AAINAAoKeAyifQC/AQANAAoKeAyifQC/AQAAAA==.',
Bo='Boinkadin:BAAANQAECgQIBAAAAA==.Boinkydk:BAAANQAECgYICQAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQAECgQICwAAAA==.Bredarra:BAAANQADCgYIBgAAAA==.Brewzlee:BAAANQAECgQIBgABNQAECgoKJAABAHEWAA==.Broomphondle:BAABNQAECn8mAAILAAgKpQyGFwFlAQALAAgKpQyGFwFlAQAAAA==.Brootis:BAAANQADCgYIBQAAAA==.Brothetucker:BAAANQAECgEIAQAAAA==.',
Bs='Bshoottu:BAABNQAECn8oAAINAAUKWQdH6QDdAAANAAUKWQdH6QDdAAAAAA==.',
Bu='Bubblina:BAAANQADCgUIBgAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQAPAAAAAA==.',
Ce='Celestìa:BAAANQAECgYIEQAAAA==.Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQABCgYIBwAAAA==.Chrisswamy:BAAANQABCgYIBwAAAA==.Chromesatan:BAAANQAECggIDgABNQAECgoKJAABAHEWAA==.Chubtubs:BAAANQAECgcIEAABNQAFFAUIEwAGAHsYAA==.Chuglee:BAABNQAECn8YAAMEAAkKuBDkGADqAQAEAAkKuBDkGADqAQAQAAEKYwGISAAOAAAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQAECgQIBAAAAA==.',
Cr='Crankypal:BAAANQAECgQICgAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
Cw='Cwdcannabull:BAAANQADCggIEQAAAA==.',
['Cá']='Cárl:BAAANQABCgIIAgAAAA==.',
Da='Daemage:BAAANQAECggIDAAAAA==.Dagara:BAAANQADCgIIAgAAAA==.Daredevill:BAAANQADCgEIAQAAAA==.Darkdrittz:BAABNQAECn8hAAIRAAgKSQkWSAANAQARAAgKSQkWSAANAQAAAA==.Darkjazz:BAAANQAECgYIBgAAAA==.',
De='Deadash:BAAANQAECgEIAQABNQAECgYIDAAPAAAAAA==.Deathclaw:BAABNQAECn83AAISAAoKzgwaZQCnAQASAAoKzgwaZQCnAQAAAA==.Deceptiõn:BAAANQABCgYIBgAAAA==.Deldúwath:BAABNQAECn8tAAMTAAoK1BBuDgDiAQATAAkK1BBuDgDiAQAUAAgK7AkLDACdAQAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dinklage:BAAANQAECgMIAwAAAA==.Dionus:BAABNQAECn84AAIBAAoKJgkVuABhAQABAAoKJgkVuABhAQAAAA==.',
Do='Dolorquedura:BAAANQAECgEIAQAAAA==.Domenic:BAAANQADCgIIAgAAAA==.Domoarigato:BAEANQAECgQICAABNQAECgkJGgALAPwKAA==.',
Dr='Drakuluh:BAAANQAECgUIBwAAAA==.Draucan:BAABNQAECn8+AAMHAAoKVCDrAQDgAgAHAAgK5iDrAQDgAgAGAAMKsBs4pQDuAAAAAA==.Dreadmoor:BAAANQADCggIFwABNQAECggIKgASACwLAA==.Dribblesnot:BAABNQAECn8qAAISAAgKLAsRmgAkAQASAAgKLAsRmgAkAQAAAA==.Driden:BAABNQAECn8XAAIVAAoKbQmJRgAJAQAVAAoKbQmJRgAJAQAAAA==.',
Dy='Dya:BAAANQAECgIIAgAAAA==.',
Ec='Echolock:BAAANQAECgUIDAAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgAPAAAAAA==.Elemetzy:BAABNQAECn8jAAQWAAoKFhhoEwDgAQAWAAkKRhdoEwDgAQAKAAUK9RcQngBbAQAOAAQKGQpwsgC1AAAAAA==.Elkul:BAAANQAECgQICQAAAA==.Elsoned:BAABNQAECn8qAAIBAAcKHxFd2QAoAQABAAcKHxFd2QAoAQAAAA==.',
Er='Errob:BAAANQADCgUIBQAAAA==.',
Eu='Euclid:BAAANQAFFAEIAQAAAA==.',
Ev='Evokyn:BAAANQADCgIIAgAAAA==.',
Fa='Falafel:BAABNQAECn8wAAIBAAgKRhNUhQDCAQABAAgKRhNUhQDCAQAAAA==.Fattaco:BAABNQAECn87AAIOAAoKQRZgSQA9AgAOAAoKQRZgSQA9AgAAAA==.',
Fi='Fizzlestix:BAEBNQAECn8aAAILAAkK/Aq0jwCHAQALAAkK/Aq0jwCHAQAAAA==.',
Fl='Floss:BAABNQAECn8gAAIBAAcKngnH8QA5AQABAAcKngnH8QA5AQAAAA==.Flubb:BAABNQAECn9AAAMXAAoKPiQUAgCeAwAXAAoKPiQUAgCeAwAYAAEKhQODegApAAAAAA==.Flubber:BAAANQAECgMIBAABNQAECgoKQAAXAD4kAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQAFFAEIAQABNQAECggINgAPAAAAAA==.Followmenot:BAABNQAECn81AAIMAAoKaxEnDQDGAQAMAAoKaxEnDQDGAQAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frëyæ:BAAANQADCgQIBAABNQAFFAYICAAKAI0JAA==.',
Fu='Furgus:BAAANQAECgEIAgABNQAECgoKJgAZANoHAA==.',
Fy='Fyerflise:BAAANQADCgUICQAAAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Go='Gobblegobble:BAABNQAECn8mAAIaAAcKGxl6KgDuAQAaAAcKGxl6KgDuAQAAAA==.Gohan:BAAANQADCgUIBQAAAA==.Gosudizzle:BAACNQAFFH8IAAINAAMKbRF5FADqAAANAAMKbRF5FADqAAA1AAQKfzUAAw0ACgrzIYMVAEYDAA0ACgrzIYMVAEYDABsAAQoAAJiBAAAAAAE1AAQKCgojABEAoRMA.',
Gr='Griffith:BAAANQADCggICAAAAA==.Grippingtaco:BAAANQAECgQICAABNQAECgoKOwAOAEEWAA==.',
Gu='Gulldarilynn:BAABNQAECn8ZAAIMAAoKcw2FDgCqAQAMAAoKcw2FDgCqAQAAAA==.',
Gw='Gwendolyn:BAABNQAECn9PAAMXAAoKOibRAAB5AwAXAAoKOibRAAB5AwAYAAIKJBAEZwBpAAABNQAECgoKUgAEAPcjAA==.Gweniveere:BAAANQADCggIEQAAAA==.',
Ha='Hakubell:BAACNQAFFH8NAAIcAAcK/RuSCQDHAQAcAAcK/RuSCQDHAQA1AAQKfz8AAxwACgrOJHIEAK8DABwACgrOJHIEAK8DAAEABQpdIHe/AJ4BAAAA.Hammershock:BAABNQAECn84AAIOAAkKjBZFNQBGAgAOAAkKjBZFNQBGAgAAAA==.Hasdiel:BAAANQAECgYIDgAAAA==.',
He='Heartim:BAAANQAECgMIAwAAAA==.Heädaches:BAAANQAECgMIBQAAAA==.',
Ho='Holynuke:BAAANQAECgUICgABNQAFFAcIDgAdAEsOAA==.Hontar:BAAANQAECgUIBQAAAA==.',
Hu='Hussie:BAAANQADCgIIAgAAAA==.',
Il='Illimommy:BAACNQAFFH8WAAIaAAgK4xEdAwAxAgAaAAgK4xEdAwAxAgA1AAQKfygAAhoACgoNI0oLAJ8CABoACgoNI0oLAJ8CAAAA.',
In='Inkarok:BAABNQAECn83AAIRAAoKvBRoIwDvAQARAAoKvBRoIwDvAQAAAA==.',
Is='Ishkode:BAABNQAECn8+AAIeAAoKbQxWCQC9AQAeAAoKbQxWCQC9AQAAAA==.',
It='Itachi:BAABNQAECn8hAAISAAgKRxYCWwDDAQASAAgKRxYCWwDDAQAAAA==.',
Iz='Izzyrael:BAAANQAECgcICQAAAA==.',
Ja='Jalapeno:BAABNQAECn8dAAIfAAoKvwaaDAApAQAfAAoKvwaaDAApAQAAAA==.Jami:BAEBNQAECn8lAAIgAAkKWg8LQwC4AQAgAAkKWg8LQwC4AQABNQAECgkJGgALAPwKAA==.',
Je='Jellybean:BAAANQADCggIFwAAAA==.',
Ji='Jitlo:BAACNQAFFH8WAAIKAAgKixcCBQDEAQAKAAgKixcCBQDEAQA1AAQKf08AAgoACgqwJDMHAEMDAAoACgqwJDMHAEMDAAAA.Jitsham:BAAANQAECggIDAAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Jt='Jtclear:BAAANQADCgcICgAAAA==.',
Ju='Juanillo:BAAANQADCgcICgAAAA==.',
Ka='Kalanrahl:BAABNQAECn8zAAQMAAoKWRR0CgD9AQAMAAoKWRR0CgD9AQALAAcKVwoQLAFCAQAhAAIKAABeEAAAAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.Kashanden:BAABNQAECn8eAAMDAAoKYyDWDQC8AgADAAkKYyDWDQC8AgAiAAQKdwatgABAAAAAAA==.',
Ke='Kemaneral:BAEANQADCgIJAgABNQAECgkJGgALAPwKAA==.',
Kh='Khaiduus:BAABNQAECn8uAAIKAAoK3RkcKgA3AgAKAAoK3RkcKgA3AgAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAABNQAECn9IAAIjAAoKYB9UAwDNAgAjAAoKYB9UAwDNAgAAAA==.Kittsune:BAAANQADCggIDgAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggINwAAAA==.',
Ko='Kottenmouth:BAACNQAFFH8UAAIkAAYKzhdrAABYAQAkAAYKzhdrAABYAQA1AAQKf0AAAiQACgrpIqYBAEoDACQACgrpIqYBAEoDAAAA.',
Kr='Kreyall:BAAANQADCgcIFgAAAA==.Kritea:BAAANQAECgQIBQAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECn8oAAIFAAoK+gwbogDHAQAFAAoK+gwbogDHAQAAAA==.Kyta:BAABNQAECn8hAAISAAcKFQnVsgDuAAASAAcKFQnVsgDuAAAAAA==.',
La='Laupess:BAAANQABCgIIAgAAAA==.',
Le='Lebron:BAAANQAECgUICQAAAA==.Lellsa:BAAANQAECgYIBgABNQAECgoKJQADAJgJAA==.',
Li='Lightbrew:BAABNQAECn8kAAIBAAoKcRahVAAwAgABAAoKcRahVAAwAgAAAA==.Litmus:BAAANQADCgUIBgAAAA==.',
Lo='Locura:BAAANQADCggICQABNQAECgoKUgAEAPcjAA==.',
Lu='Lululyn:BAAANQABCgMIAwAAAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAABNQAECn9GAAIiAAkKLh1TDACzAgAiAAkKLh1TDACzAgAAAA==.Magra:BAAANQABCgIIAgAAAA==.Makersmartun:BAAANQAECgMIBAAAAA==.Malthira:BAAANQAECgEIAQAAAA==.Matterdaddy:BAAANQADCgcIBwABNQAECgoKLQAkAFEhAA==.',
Mi='Milbi:BAAANQADCgcIEgAAAA==.Minadette:BAAANQAECgQIBAAAAA==.',
Ml='Mljr:BAABNQAECn8uAAILAAkKYQ05ewC2AQALAAkKYQ05ewC2AQAAAA==.Mljrone:BAAANQAECgQIBAAAAA==.',
Mo='Moira:BAAANQAECgIIAgAAAA==.Mollicogs:BAAANQADCggIEAAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAACNQAFFH8HAAISAAcKCRMuEQB3AQASAAcKCRMuEQB3AQA1AAQKf0IAAhIACgpVIhUVAM8CABIACgpVIhUVAM8CAAAA.',
Mu='Munchkins:BAAANQABCggIEAAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Naleen:BAEANQADCgIIAgABNQAECgoKNwADAL8kAA==.Nativelock:BAABNQAECn82AAMeAAoKWgexDgBMAQAeAAkKdwexDgBMAQAZAAQKywThIwBlAAAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECggIEQAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.Nilrim:BAAANQABCgIIAgAAAA==.',
No='Norabelle:BAAANQADCggIEgAAAA==.Nozomila:BAABNQAECn8VAAMXAAYKwx/YGABvAQAXAAUKJCDYGABvAQAVAAUKOA5wdQD1AAAAAA==.',
Ny='Nynnaeve:BAABNQAECn8fAAMGAAoKexEWPwA+AgAGAAoKexEWPwA+AgAlAAMKlgM0ZABvAAAAAA==.',
['Nú']='Núrnen:BAAANQAECgMIAwAAAA==.',
On='Onthecoda:BAABNQAECn8xAAIYAAkKTSEyCQBBAwAYAAkKTSEyCQBBAwAAAA==.',
Oo='Oomgad:BAAANQADCgQICAAAAA==.',
Op='Opadden:BAAANQABCgIIAgAAAA==.Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgIIAQAAAA==.',
Pa='Paeus:BAAANQABCgUICgAAAA==.Paigeturner:BAABNQAECn82AAILAAoKogWulgB4AQALAAoKogWulgB4AQAAAA==.Palapets:BAAANQAECgIIAgABNQAECggICgAPAAAAAA==.Pantherarosa:BAAANQAECgUIDgABNQAECgoKJgAZANoHAA==.Papalock:BAABNQAECn8dAAISAAgKlhlRiwDKAQASAAgKlhlRiwDKAQABNQAECgkJLAABAEAfAA==.Parenthi:BAAANQADCgEIAQAAAA==.Pazerp:BAAANQADCggIFAAAAA==.',
Pe='Peaches:BAAANQADCgEIAQAAAA==.Persymphony:BAABNQAECn9GAAISAAoK9CHsCwALAwASAAoK9CHsCwALAwAAAA==.',
Ph='Phabio:BAAANQAECgcIEwAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAgIDgAOADQKAA==.',
Pi='Pineappletea:BAABNQAECn8dAAIZAAYKyhFmGwCSAQAZAAYKyhFmGwCSAQAAAA==.Pinepally:BAAANQADCgQIBQAAAA==.Pinkee:BAAANQADCggICAAAAA==.Pinklock:BAABNQAECn8mAAIZAAoK2geJCwAJAQAZAAoK2geJCwAJAQAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.Pootsii:BAAANQADCgYIBgAAAA==.',
['Pø']='Pøøts:BAAANQAECgIIAgAAAA==.Pøøtsi:BAAANQAECgEIAQAAAA==.',
Qu='Quesy:BAACNQAFFH8NAAMiAAYKHRdRBwClAQAiAAUKbhNRBwClAQAgAAUKHRf4DQDtAAA1AAQKfx0ABCIACgrHJBAQADYDACIACAqKJBAQADYDACAABQoeI6JEAIcBAAMAAQoAAAAAAAAAAAE1AAUUBwgOAB0ASw4A.',
Ra='Ragnapall:BAAANQAECgQIBQABNQAFFAYICAAKAI0JAA==.Ragnatotemzz:BAACNQAFFH8IAAIKAAYKjQn2FAApAQAKAAYKjQn2FAApAQA1AAQKfx0AAgoACgoHHz88AIQCAAoACgoHHz88AIQCAAAA.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgIIAwAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgUIDQAPAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgUIDQAPAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Rellock:BAAANQADCgcIBwABNQAECgMIBAAPAAAAAA==.Renalla:BAAANQAECgQIBAAAAA==.Renkari:BAAANQAECgcIDAAAAA==.Rennl:BAABNQAECn8iAAIBAAcK+QgT+AD2AAABAAcK+QgT+AD2AAAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICAABNQAECgoKJgAZANoHAA==.Ripsets:BAABNQAECn9EAAMNAAoKhCK6KQDxAgANAAkKnCK6KQDxAgAbAAgKbh/3HQBhAgAAAA==.',
Ro='Rogueloki:BAABNQAECn82AAMTAAoK1RcKPADhAQATAAcKERMKPADhAQAJAAgKRxgtJACnAQAAAA==.Roonrangi:BAAANQAECgUIBQAAAA==.Rowscaris:BAAANQAECgUIBwAAAA==.',
Ry='Rylerza:BAAANQAECgUIBgAAAA==.Rynna:BAABNQAECn8sAAIBAAkKQB8GTABGAgABAAkKQB8GTABGAgAAAA==.Rynya:BAAANQAECgMIAwAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAFFAYICAAKAI0JAA==.',
Sa='Sailee:BAAANQADCgcICQAAAA==.Samelthund:BAAANQABCgUICQAAAA==.Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgcIMQAAAA==.Sarigos:BAABNQAECn89AAMmAAoK7BNRDgAuAgAmAAkKEhNRDgAuAgAnAAUK2Aj5LAC5AAAAAA==.',
Sc='Schieldemon:BAACNQAFFH8HAAMaAAIKpQwaEgBDAAAaAAIKpQwaEgBDAAARAAIKuQaKHAA8AAA1AAQKf18AAxoACgptHPoNAAgDABoACgoLHPoNAAgDABEACgoRFpAdACECAAAA.Scrythe:BAABNQAECn9IAAIDAAoK2xxoEACbAgADAAoK2xxoEACbAgAAAA==.Scynline:BAAANQADCgcICQAAAA==.Scynrine:BAAANQABCgIIAgAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQAECggIEgAAAA==.Sharrin:BAAANQADCgYJBgABNQAECgoKNAAcAOcaAA==.Sherem:BAAANQABCgIIAQAAAA==.Shoran:BAAANQADCgYIBgAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgUIBQAAAA==.Slime:BAAANQADCgYICwAAAA==.',
So='Solomoon:BAABNQAECn8VAAIGAAYKZByFaQDiAQAGAAYKZByFaQDiAQABNQAFFAcIDQAcAP0bAA==.Souleatr:BAABNQAECn8YAAIRAAkKMxKlMACSAQARAAkKMxKlMACSAQAAAA==.',
Sp='Speisgote:BAABNQAECn8fAAMBAAoK7A5sigC3AQABAAoK7A5sigC3AQACAAQKgQVWTwBqAAAAAA==.Spieros:BAAANQAECgYIBQABNQAECgoKPgAHAFQgAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECgoKPQAmAOwTAA==.Starforge:BAAANQAECgIIAgAAAA==.Stealthpets:BAAANQADCggICQABNQAECggICgAPAAAAAA==.Stealthragg:BAABNQAECn8YAAIJAAkKVRerNQAlAgAJAAkKVRerNQAlAgABNQAFFAYICAAKAI0JAA==.Steelehorn:BAAANQADCgUIBQAAAA==.Stewpot:BAAANQADCggIDAAAAA==.Stigmã:BAAANQADCgYIEQAAAA==.Stylish:BAABNQAECn8gAAQFAAoKYhJ2jwD2AQAFAAoKCBB2jwD2AQAoAAMKyRZANQCLAAAdAAEKHhEjMgA5AAAAAA==.',
Su='Suisui:BAAANQADCgcIGAAAAA==.Suling:BAAANQABCgIIAwAAAA==.Suunde:BAAANQADCgQIBAAAAA==.',
Sy='Sylathra:BAAANQABCgQIBAAAAA==.Syryn:BAABNQAECn8rAAINAAgKFgqjpwBjAQANAAgKFgqjpwBjAQAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQAECgMIAwABNQAECggIEQAPAAAAAA==.Thorgrum:BAABNQAECn9GAAMiAAoKlyYKAQCAAwAiAAoKlyYKAQCAAwAgAAIK6R/7fgCuAAAAAA==.Thûnderize:BAABNQAECn9SAAIKAAoKiyDOEgDVAgAKAAoKiyDOEgDVAgAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAABNQAECn8cAAIGAAkK9hMPSgAPAgAGAAkK9hMPSgAPAgAAAA==.Tirea:BAABNQAECn8aAAIWAAcKPgzCGgC3AQAWAAcKPgzCGgC3AQABNQAECgkJGAARADMSAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgcIKwAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Trashedpanda:BAAANQAECgYIDwAAAA==.Trastuzumab:BAAANQADCgYIBwAAAA==.Tripoloski:BAABNQAECn8nAAMUAAoKViMtBADTAgAUAAcK5CMtBADTAgAJAAkKFx8qEQBuAgAAAA==.',
Tu='Tugamuhpud:BAABNQAECn9KAAMSAAoK8wSQjwA8AQASAAoKmgSQjwA8AQAeAAUKXwPSHACYAAAAAA==.',
Ty='Tyllas:BAAANQADCgYIBQAAAA==.',
Tz='Tzzird:BAABNQAECn9KAAMBAAoKVyDxJgDFAgABAAoKVyDxJgDFAgAcAAYKORnyUgDJAQAAAA==.',
Ug='Ugrah:BAABNQAECn8iAAIFAAkKZgzkqAC2AQAFAAkKZgzkqAC2AQAAAA==.',
Uk='Ukyomsi:BAAANQABCgIIAgABNQAECgkJGAARADMSAA==.',
Un='Undeadheals:BAAANQAECgUIDQAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgcICQAAAA==.Varod:BAAANQAECggICgAAAA==.Vawdkuh:BAABNQAECn84AAIVAAoK/hICLACiAQAVAAoK/hICLACiAQAAAA==.',
Ve='Velddor:BAABNQAECn8tAAIkAAoKUSEKAwCMAgAkAAoKUSEKAwCMAgAAAA==.Vellea:BAAANQADCgUIBQAAAA==.',
Vi='Vice:BAABNQAECn8bAAIBAAoKBwpDqQB8AQABAAoKBwpDqQB8AQAAAA==.Vignette:BAAANQABCgcICAAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAgAAAA==.',
['Vô']='Vôx:BAAANQAECgQICAABNQAECgcIDAAPAAAAAA==.',
['Vö']='Vöx:BAAANQAECgcIDAAAAA==.',
Wa='Wartrick:BAABNQAECn8fAAINAAoKtAijnADOAQANAAoKtAijnADOAQAAAA==.',
Wh='Whoudini:BAABNQAECn8qAAIZAAgKIQxyCwAKAQAZAAgKIQxyCwAKAQAAAA==.',
Xe='Xerãth:BAABNQAECn9IAAILAAoKsgllgwCiAQALAAoKsgllgwCiAQAAAA==.',
Xi='Xiya:BAABNQAECn8cAAIGAAoKShoVKgCjAgAGAAoKShoVKgCjAgAAAA==.',
Ya='Yarndog:BAAANQAECgcIDQAAAA==.Yarnell:BAABNQAECn8nAAIFAAcKjRJXmgBKAQAFAAcKjRJXmgBKAQAAAA==.Yaviel:BAABNQAECn8ZAAINAAoKww2qkADoAQANAAoKww2qkADoAQAAAA==.',
Yu='Yushis:BAABNQAECn9HAAIaAAoKUhs7EgA6AgAaAAoKUhs7EgA6AgAAAA==.',
Za='Zarrgon:BAEBNQAECn83AAMDAAoKvyQiBACvAwADAAoKqiQiBACvAwAiAAkKqRs5KwCJAgAAAA==.',
Ze='Zelderk:BAACNQAFFH8OAAMdAAcKSw4XAwCgAAAFAAUKzA3yHAAqAQAdAAQK6A0XAwCgAAA1AAQKfzEAAwUACgr/I6ckACYDAAUACQprI6ckACYDAB0ABApQIEsVACUBAAAA.Zeromus:BAAANQADCgcICwAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQAECgQIBQABNQAECgoKSgABAFcgAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
Zz='Zzeb:BAAANQADCgQIBAAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQAECgMIAQAAAA==.',
['Âl']='Âlpally:BAAANQAECgQIBAAAAA==.',
['Ðr']='Ðrizzt:BAAANQADCggICAABNQAECgkJGAARADMSAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgkJGAARADMSAA==.',
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
