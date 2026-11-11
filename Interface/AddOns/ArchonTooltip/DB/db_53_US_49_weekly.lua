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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Monk-Windwalker','Warrior-Arms','Priest-Holy','Priest-Discipline','Druid-Guardian','Rogue-Subtlety','Shaman-Elemental','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','DemonHunter-Havoc','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','Druid-Feral','Druid-Restoration','Warlock-Destruction','DemonHunter-Devourer','Hunter-Marksmanship','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Evoker-Augmentation','DeathKnight-Frost','Mage-Fire','DeathKnight-Unholy','DemonHunter-Vengeance','Hunter-Survival','Druid-Balance','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Warrior-Protection',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aahhotep:BAAANQADCgUICQAAAA==.',
Ag='Agnestachyon:BAAANQAECgYIBwAAAA==.',
Ai='Aitwa:BAAANQADCggICAAAAA==.',
Ak='Aksnowman:BAAANQADCgYICAAAAA==.',
Al='Alanbrito:BAAANQAECgMIAwAAAA==.Albus:BAAANQAECgYIDwABNQAECgkJKwABAEAfAA==.Aliane:BAAANQAECgUICgAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAABNQAECn8YAAMCAAgKwAfeNgDCAAABAAcK4wZ9CQEPAQACAAcKiAfeNgDCAAAAAA==.Alísea:BAAANQAECgMIAQAAAA==.',
Am='Amoonday:BAAANQAECgUICgAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.Andrewsmom:BAEANQAECgQIBAABNQAECgoKNwADAL8kAA==.',
Ar='Aramoonsong:BAABNQAECn9SAAIEAAoK9yMMAwCpAwAEAAoK9yMMAwCpAwAAAA==.Aranrùth:BAABNQAECn86AAIFAAkK0SLgDwATAwAFAAkK0SLgDwATAwAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Arcani:BAAANQADCgIIAgAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arnoldd:BAAANQAECggICAAAAA==.Arthin:BAAANQABCgQIBAAAAA==.',
As='Ashbowbaby:BAAANQAECgYIDAAAAA==.',
Au='Auraborealis:BAABNQAECn8kAAMGAAgKNhTRTADwAQAGAAgKNhTRTADwAQAHAAQKPwW5GQCeAAAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAABNQAECn8fAAIIAAgKAB/yFADYAQAIAAgKAB/yFADYAQAAAA==.',
Az='Azuael:BAAANQAECggIBwAAAA==.',
Ba='Baberaham:BAAANQAECgEIAQAAAA==.Baki:BAABNQAECn8WAAIJAAkK7A4tPQDxAQAJAAkK7A4tPQDxAQAAAA==.Ballzdragon:BAAANQAECgcICwABNQAFFAUIBwAKAAYIAA==.Balzamon:BAABNQAECn88AAIFAAoKNQrNeQCCAQAFAAoKNQrNeQCCAQAAAA==.Bamabill:BAAANQAECggICAAAAA==.Bandgeek:BAABNQAECn82AAMLAAoKfiF7GADbAgALAAoKfiF7GADbAgAMAAQKwhOAIgDXAAAAAA==.Bantôt:BAAANQADCggIHAAAAA==.',
Be='Beegood:BAABNQAECn85AAINAAoKjgeDrwA4AQANAAoKjgeDrwA4AQAAAA==.Beweaver:BAEANQADCggICAABNQAECgkJFwALAK0JAA==.',
Bi='Biebert:BAABNQAECn8rAAIFAAoKiRIpiAAIAgAFAAoKiRIpiAAIAgAAAA==.Bizzy:BAAANQADCgcICgAAAA==.',
Bl='Blooddemon:BAAANQAECgIIAwABNQAECgoKOwAOAEEWAA==.Bloodegg:BAABNQAECn84AAINAAoKFAz5cwC7AQANAAoKFAz5cwC7AQAAAA==.',
Bo='Boinkadin:BAAANQAECgQIBAAAAA==.Boinkydk:BAAANQAECgYICQAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQAECgQICwAAAA==.Bredarra:BAAANQADCgYIBgAAAA==.Brewzlee:BAAANQAECgQIBgABNQAECgoKIQABABQWAA==.Broomphondle:BAABNQAECn8iAAILAAcKeQ2GFwFlAQALAAcKeQ2GFwFlAQAAAA==.Brootis:BAAANQADCgYIBQAAAA==.Brothetucker:BAAANQAECgEIAQAAAA==.',
Bs='Bshoottu:BAABNQAECn8kAAINAAUKWQdO3wDXAAANAAUKWQdO3wDXAAAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQAPAAAAAA==.',
Ce='Celestìa:BAAANQAECgcIDAAAAA==.Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQABCgYIBwAAAA==.Chrisswamy:BAAANQABCgYIBwAAAA==.Chromesatan:BAAANQAECggIBgABNQAECgoKIQABABQWAA==.Chubtubs:BAAANQAECgcIDAABNQAFFAUIEwAGAHsYAA==.Chuglee:BAAANQAECggIDAAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQADCggIJwAAAA==.',
Cr='Crankypal:BAAANQAECgQICgAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
['Cá']='Cárl:BAAANQABCgIIAgAAAA==.',
Da='Daemage:BAAANQAECggIDAAAAA==.Dagara:BAAANQADCgIIAgAAAA==.Daredevill:BAAANQADCgEIAQAAAA==.Darkdrittz:BAABNQAECn8hAAIQAAgKSQn2QgAQAQAQAAgKSQn2QgAQAQAAAA==.Darkjazz:BAAANQAECgYIBgAAAA==.',
De='Deadash:BAAANQAECgEIAQABNQAECgYIDAAPAAAAAA==.Deathclaw:BAABNQAECn8wAAIRAAoKWQxFYgCbAQARAAoKWQxFYgCbAQAAAA==.Deceptiõn:BAAANQABCgYIBgAAAA==.Deldúwath:BAABNQAECn8tAAMSAAoK1BBsDQDmAQASAAkK1BBsDQDmAQATAAgK7AkLDACdAQAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dinklage:BAAANQAECgMIAwAAAA==.Dionus:BAABNQAECn84AAIBAAoKJgmrqQBlAQABAAoKJgmrqQBlAQAAAA==.',
Do='Dolorquedura:BAAANQAECgEIAQAAAA==.Domenic:BAAANQADCgIIAgAAAA==.Domoarigato:BAEANQAECgQICAABNQAECgkJFwALAK0JAA==.',
Dr='Drakuluh:BAAANQAECgUIBwAAAA==.Draucan:BAABNQAECn82AAMHAAoKVCAMAgC+AgAHAAgK5iAMAgC+AgAGAAMKsBuAmwDxAAAAAA==.Dreadmoor:BAAANQADCggIFwABNQAECgcIKQARAFELAA==.Dribblesnot:BAABNQAECn8pAAIRAAcKUQs7vQBSAQARAAcKUQs7vQBSAQAAAA==.Driden:BAAANQAECggIEQAAAA==.',
Dy='Dya:BAAANQAECgMIAQAAAA==.',
Ec='Echolock:BAAANQAECgUIDAAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgAPAAAAAA==.Elemetzy:BAABNQAECn8iAAQUAAoKFhjAEQDjAQAUAAkKRhfAEQDjAQAKAAUK9RcQngBbAQAOAAQKGQqsqQC2AAAAAA==.Elkul:BAAANQAECgQICQAAAA==.Elsoned:BAABNQAECn8kAAIBAAcKSA/T1QAYAQABAAcKSA/T1QAYAQAAAA==.',
Er='Errob:BAAANQADCgUIBQAAAA==.',
Eu='Euclid:BAAANQAFFAEIAQAAAA==.',
Ev='Evokyn:BAAANQADCgIIAgAAAA==.',
Fa='Falafel:BAABNQAECn8wAAIBAAgKRhPcdgDNAQABAAgKRhPcdgDNAQAAAA==.Fattaco:BAABNQAECn87AAIOAAoKQRZ1PAAOAgAOAAoKQRZ1PAAOAgAAAA==.',
Fi='Fizzlestix:BAEBNQAECn8XAAILAAkKrQkMjgB3AQALAAkKrQkMjgB3AQAAAA==.',
Fl='Floss:BAABNQAECn8gAAIBAAcKngnH8QA5AQABAAcKngnH8QA5AQAAAA==.Flubb:BAABNQAECn88AAMVAAoKLyQUAgCeAwAVAAoKLyQUAgCeAwAWAAEKhQODegApAAAAAA==.Flubber:BAAANQAECgMIAgABNQAECgoKPAAVAC8kAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQAECggIDAABNQAECggIMAAPAAAAAA==.Followmenot:BAABNQAECn8vAAIMAAoKDhEIDQCqAQAMAAoKDhEIDQCqAQAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frëyæ:BAAANQADCgQIBAABNQAFFAUIBwAKAAYIAA==.',
Fu='Furgus:BAAANQAECgEIAgABNQAECggIIgAXAAkIAA==.',
Fy='Fyerflise:BAAANQADCgUICQAAAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Go='Gobblegobble:BAABNQAECn8mAAIYAAcKGxl6KgDuAQAYAAcKGxl6KgDuAQAAAA==.Gosudizzle:BAACNQAFFH8IAAINAAMKbREYEgDtAAANAAMKbREYEgDtAAA1AAQKfzIAAw0ACgrzIYMVAEYDAA0ACgrzIYMVAEYDABkAAQoAADF8AAAAAAE1AAQKCgojABAAoRMA.',
Gr='Griffith:BAAANQADCggICAAAAA==.Grippingtaco:BAAANQAECgQICAABNQAECgoKOwAOAEEWAA==.',
Gu='Gulldarilynn:BAABNQAECn8XAAIMAAgKkQ1+EwA9AQAMAAgKkQ1+EwA9AQAAAA==.',
Gw='Gwendolyn:BAABNQAECn9JAAMVAAoKOibCAAB3AwAVAAoKOibCAAB3AwAWAAIKJBAEZwBpAAABNQAECgoKUgAEAPcjAA==.Gweniveere:BAAANQADCgcIBwAAAA==.',
Ha='Hakubell:BAACNQAFFH8NAAIaAAcK/RuSCQDHAQAaAAcK/RuSCQDHAQA1AAQKfz8AAxoACgrOJHIEAK8DABoACgrOJHIEAK8DAAEABQpdIHe/AJ4BAAAA.Hammershock:BAABNQAECn8wAAIOAAgKrxdYOgAYAgAOAAgKrxdYOgAYAgAAAA==.Hasdiel:BAAANQAECgYIDgAAAA==.',
He='Heartim:BAAANQAECgMIAwAAAA==.Heädaches:BAAANQAECgMIBQAAAA==.',
Ho='Holynuke:BAAANQAECgUICgABNQAFFAcIDgAbAEsOAA==.Hontar:BAAANQAECgUIBQAAAA==.',
Hu='Hussie:BAAANQADCgIIAgAAAA==.',
Il='Illimommy:BAACNQAFFH8WAAIYAAgK4xEdAwAxAgAYAAgK4xEdAwAxAgA1AAQKfygAAhgACgoNIycKAKcCABgACgoNIycKAKcCAAAA.',
In='Inkarok:BAABNQAECn8zAAIQAAkKqhSkKQCqAQAQAAkKqhSkKQCqAQAAAA==.',
Is='Ishkode:BAABNQAECn82AAIcAAoKNwwPCQCtAQAcAAoKNwwPCQCtAQAAAA==.',
It='Itachi:BAABNQAECn8ZAAIRAAgKUBELVgC+AQARAAgKUBELVgC+AQAAAA==.',
Iz='Izzyrael:BAAANQAECgcICQAAAA==.',
Ja='Jalapeno:BAABNQAECn8bAAIdAAgKWwfODgDkAAAdAAgKWwfODgDkAAAAAA==.Jami:BAEBNQAECn8kAAIeAAkKWg8LQwC4AQAeAAkKWg8LQwC4AQABNQAECgkJFwALAK0JAA==.',
Je='Jellybean:BAAANQADCggIFwAAAA==.',
Ji='Jitlo:BAACNQAFFH8RAAIKAAYKfgsqCADxAQAKAAYKfgsqCADxAQA1AAQKf08AAgoACgqwJHUGAEYDAAoACgqwJHUGAEYDAAAA.Jitsham:BAAANQAECggIDAAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Jt='Jtclear:BAAANQADCgcICgAAAA==.',
Ju='Juanillo:BAAANQADCgcICgAAAA==.',
Ka='Kalanrahl:BAABNQAECn8zAAQMAAoKWRQcCQAAAgAMAAoKWRQcCQAAAgALAAcKVwoQLAFCAQAfAAIKAACuDgAAAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.Kashanden:BAABNQAECn8eAAMDAAoKYyDSDADBAgADAAkKYyDSDADBAgAgAAQKdwZQewBAAAAAAA==.',
Ke='Kemaneral:BAEANQADCgIJAgABNQAECgkJFwALAK0JAA==.',
Kh='Khaiduus:BAABNQAECn8tAAIKAAoK3RltJgA5AgAKAAoK3RltJgA5AgAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAABNQAECn9EAAIhAAoKUB8NAwDMAgAhAAoKUB8NAwDMAgAAAA==.Kittsune:BAAANQADCggIDgAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggINwAAAA==.',
Ko='Kottenmouth:BAACNQAFFH8UAAIiAAYKzhdXAABhAQAiAAYKzhdXAABhAQA1AAQKfz8AAiIACgrpIqYBAEoDACIACgrpIqYBAEoDAAAA.',
Kr='Kreyall:BAAANQADCgUIEwAAAA==.Kritea:BAAANQAECgQIBQAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECn8oAAIFAAoK+gwbogDHAQAFAAoK+gwbogDHAQAAAA==.Kyta:BAABNQAECn8gAAIRAAYKCgrwuADMAAARAAYKCgrwuADMAAAAAA==.',
La='Laupess:BAAANQABCgIIAgAAAA==.',
Le='Lebron:BAAANQAECgUICQAAAA==.',
Li='Lightbrew:BAABNQAECn8hAAIBAAoKFBYoTQAzAgABAAoKFBYoTQAzAgAAAA==.Litmus:BAAANQADCgUIBQAAAA==.',
Lo='Locura:BAAANQADCggICQABNQAECgoKUgAEAPcjAA==.',
Lu='Lululyn:BAAANQABCgMIAwAAAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAABNQAECn89AAIgAAkKYRoHDwCAAgAgAAkKYRoHDwCAAgAAAA==.Magra:BAAANQABCgIIAgAAAA==.Makersmartun:BAAANQAECgMIBAAAAA==.Malthira:BAAANQAECgEIAQAAAA==.Matterdaddy:BAAANQADCgcIBwABNQAECgoKLQAiAFEhAA==.',
Mi='Milbi:BAAANQADCgYIDwAAAA==.Minadette:BAAANQAECgQIBAAAAA==.',
Ml='Mljr:BAABNQAECn8mAAILAAgKPQ2ojgB2AQALAAgKPQ2ojgB2AQAAAA==.Mljrone:BAAANQAECgQIBAAAAA==.',
Mo='Moira:BAAANQAECgIIAgAAAA==.Mollicogs:BAAANQADCggIEAAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAACNQAFFH8HAAIRAAcKCRMuEQB3AQARAAcKCRMuEQB3AQA1AAQKf0IAAhEACgpVIgkSANcCABEACgpVIgkSANcCAAAA.',
Mu='Munchkins:BAAANQABCggIEAAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Naleen:BAEANQADCgIIAgABNQAECgoKNwADAL8kAA==.Nativelock:BAABNQAECn8wAAMcAAkKagaSEAAUAQAcAAgKZAaSEAAUAQAXAAMKywRNIQBmAAAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECggIEQAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.Nilrim:BAAANQABCgIIAgAAAA==.',
No='Norabelle:BAAANQADCggIDQAAAA==.Nozomila:BAABNQAECn8VAAMVAAYKwx/YGABvAQAVAAUKJCDYGABvAQAjAAUKOA5wdQD1AAAAAA==.',
Ny='Nynnaeve:BAABNQAECn8dAAMGAAgKCxTrUgDYAQAGAAgKCxTrUgDYAQAkAAMKlgM0ZABvAAAAAA==.',
['Nú']='Núrnen:BAAANQAECgMIAwAAAA==.',
On='Onthecoda:BAABNQAECn8xAAIWAAkKTSE1CABDAwAWAAkKTSE1CABDAwAAAA==.',
Oo='Oomgad:BAAANQADCgQICAAAAA==.',
Op='Opadden:BAAANQABCgIIAgAAAA==.Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgIIAQAAAA==.',
Pa='Paeus:BAAANQABCgUICgAAAA==.Paigeturner:BAABNQAECn81AAILAAkKSAX7owBKAQALAAkKSAX7owBKAQAAAA==.Palapets:BAAANQAECgIIAgABNQAECggICgAPAAAAAA==.Pantherarosa:BAAANQAECgUIDgABNQAECggIIgAXAAkIAA==.Papalock:BAABNQAECn8dAAIRAAgKlhlRiwDKAQARAAgKlhlRiwDKAQABNQAECgkJKwABAEAfAA==.Parenthi:BAAANQADCgEIAQAAAA==.Pazerp:BAAANQADCggIEQAAAA==.',
Pe='Peaches:BAAANQADCgEIAQAAAA==.Persymphony:BAABNQAECn8+AAIRAAoKVh/HFgC5AgARAAoKVh/HFgC5AgAAAA==.',
Ph='Phabio:BAAANQAECggIDgAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAgIDgAOADQKAA==.',
Pi='Pineappletea:BAABNQAECn8dAAIXAAYKyhFmGwCSAQAXAAYKyhFmGwCSAQAAAA==.Pinepally:BAAANQADCgQIBQAAAA==.Pinkee:BAAANQADCggICAAAAA==.Pinklock:BAABNQAECn8iAAIXAAgKCQhnDwDOAAAXAAgKCQhnDwDOAAAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.Pootsii:BAAANQADCgYIBgAAAA==.',
['Pø']='Pøøts:BAAANQAECgIIAgAAAA==.Pøøtsi:BAAANQAECgEIAQAAAA==.',
Qu='Quesy:BAACNQAFFH8NAAMgAAYKHRdRBwClAQAgAAUKbhNRBwClAQAeAAUKHRcqDADtAAA1AAQKfxwABCAACgrHJBAQADYDACAACAqKJBAQADYDAB4ABQoeI3Y+AIwBAAMAAQoAAAAAAAAAAAE1AAUUBwgOABsASw4A.',
Ra='Ragnapall:BAAANQAECgQIBQABNQAFFAUIBwAKAAYIAA==.Ragnatotemzz:BAACNQAFFH8HAAIKAAUKBgj2FAApAQAKAAUKBgj2FAApAQA1AAQKfx0AAgoACgoHHz88AIQCAAoACgoHHz88AIQCAAAA.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgMIAwAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgQICQAPAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgQICQAPAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Rellock:BAAANQADCgcIBwABNQAECgMIBAAPAAAAAA==.Renalla:BAAANQAECgQIBAAAAA==.Renkari:BAAANQAECgcIDAAAAA==.Rennl:BAABNQAECn8cAAIBAAYKYwghGwHyAAABAAYKYwghGwHyAAAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICAABNQAECggIIgAXAAkIAA==.Ripsets:BAABNQAECn9EAAMNAAoKhCK6KQDxAgANAAkKnCK6KQDxAgAZAAgKbh/3HQBhAgAAAA==.',
Ro='Rogueloki:BAABNQAECn82AAMSAAoK1RcKPADhAQASAAcKERMKPADhAQAJAAgKRxgtJACnAQAAAA==.Roonrangi:BAAANQAECgUIBQAAAA==.Rowscaris:BAAANQAECgUIBwAAAA==.',
Ry='Rylerza:BAAANQADCgYIBgAAAA==.Rynna:BAABNQAECn8rAAIBAAkKQB+oQwBPAgABAAkKQB+oQwBPAgAAAA==.Rynya:BAAANQAECgMIAwAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAFFAUIBwAKAAYIAA==.',
Sa='Sailee:BAAANQADCgcICQAAAA==.Samelthund:BAAANQABCgUICQAAAA==.Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgcILQAAAA==.Sarigos:BAABNQAECn83AAMlAAoK2RNBDQAwAgAlAAkK/RJBDQAwAgAmAAQKywj5LAC5AAAAAA==.',
Sc='Schieldemon:BAACNQAFFH8HAAMYAAIKpQxJEQBDAAAYAAIKpQxJEQBDAAAQAAIKuQaFGgA9AAA1AAQKf1sAAxgACgqwG/oNAAgDABgACQqUHfoNAAgDABAACgoRFjUbACICAAAA.Scrythe:BAABNQAECn9AAAIDAAoK2xy8DwCaAgADAAoK2xy8DwCaAgAAAA==.Scynline:BAAANQADCgcICQAAAA==.Scynrine:BAAANQABCgIIAgAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQAECggIEgAAAA==.Sharrin:BAAANQADCgYJBgAAAA==.Shoran:BAAANQADCgYIBgAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgUIBQAAAA==.Slime:BAAANQADCgYICwAAAA==.',
So='Solomoon:BAABNQAECn8VAAIGAAYKZByFaQDiAQAGAAYKZByFaQDiAQABNQAFFAcIDQAaAP0bAA==.Souleatr:BAABNQAECn8VAAIQAAkKYxHKMwBnAQAQAAkKYxHKMwBnAQAAAA==.',
Sp='Speisgote:BAABNQAECn8dAAMBAAgKmAw+wwA3AQABAAgKmAw+wwA3AQACAAQKgQXqSgBqAAAAAA==.Spieros:BAAANQAECgYIBQABNQAECgoKNgAHAFQgAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECgoKNwAlANkTAA==.Starforge:BAAANQAECgIIAgAAAA==.Stealthpets:BAAANQADCggICQABNQAECggICgAPAAAAAA==.Stealthragg:BAABNQAECn8YAAIJAAkKVRe4MAAmAgAJAAkKVRe4MAAmAgABNQAFFAUIBwAKAAYIAA==.Steelehorn:BAAANQADCgUIBQAAAA==.Stewpot:BAAANQADCggIDAAAAA==.Stigmã:BAAANQADCgYICwAAAA==.Stylish:BAABNQAECn8gAAQFAAoKYhJ2jwD2AQAFAAoKCBB2jwD2AQAnAAMKyRZANQCLAAAbAAEKHhEjMgA5AAAAAA==.',
Su='Suisui:BAAANQADCgcIGAAAAA==.Suling:BAAANQABCgIIAwAAAA==.Suunde:BAAANQADCgQIBAAAAA==.',
Sy='Sylathra:BAAANQABCgQIBAAAAA==.Syryn:BAABNQAECn8mAAINAAcKbAqvuwAgAQANAAcKbAqvuwAgAQAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQAECgMIAwABNQAECggIEQAPAAAAAA==.Thorgrum:BAABNQAECn8+AAMgAAoKlyaeAQBuAwAgAAoKlyaeAQBuAwAeAAIK6R/7fgCuAAAAAA==.Thûnderize:BAABNQAECn9JAAIKAAoK1B8dFgCtAgAKAAoK1B8dFgCtAgAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAABNQAECn8aAAIGAAgKChMhWQDCAQAGAAgKChMhWQDCAQAAAA==.Tirea:BAABNQAECn8aAAIUAAcKPgzCGgC3AQAUAAcKPgzCGgC3AQABNQAECgkJFQAQAGMRAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgcIKwAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Trashedpanda:BAAANQAECgYIDwAAAA==.Trastuzumab:BAAANQADCgIIAgAAAA==.Tripoloski:BAABNQAECn8nAAMTAAoKViMtBADTAgATAAcK5CMtBADTAgAJAAkKFx8qEQBuAgAAAA==.',
Tu='Tugamuhpud:BAABNQAECn9EAAMRAAoKmgTEhQA+AQARAAoKmgTEhQA+AQAcAAUKxAHSHACYAAAAAA==.',
Ty='Tyllas:BAAANQADCgYIBQAAAA==.',
Tz='Tzzird:BAABNQAECn9HAAMBAAoKUSCIIgDNAgABAAoKUSCIIgDNAgAaAAUKXBvrWgCYAQAAAA==.',
Ug='Ugrah:BAABNQAECn8iAAIFAAkKZgzkqAC2AQAFAAkKZgzkqAC2AQAAAA==.',
Uk='Ukyomsi:BAAANQABCgIIAgABNQAECgkJFQAQAGMRAA==.',
Un='Undeadheals:BAAANQAECgQICQAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgcICQAAAA==.Varod:BAAANQAECggICgAAAA==.Vawdkuh:BAABNQAECn83AAIjAAoKWxK0KQCcAQAjAAoKWxK0KQCcAQAAAA==.',
Ve='Velddor:BAABNQAECn8tAAIiAAoKUSGjAgCSAgAiAAoKUSGjAgCSAgAAAA==.Vellea:BAAANQADCgUIBQAAAA==.',
Vi='Vice:BAABNQAECn8bAAIBAAoKBwpkmwCBAQABAAoKBwpkmwCBAQAAAA==.Vignette:BAAANQABCgcICAAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAgAAAA==.',
['Vô']='Vôx:BAAANQAECgQIBAABNQAECgcIDAAPAAAAAA==.',
['Vö']='Vöx:BAAANQAECgcIDAAAAA==.',
Wa='Wartrick:BAABNQAECn8fAAINAAoKtAijnADOAQANAAoKtAijnADOAQAAAA==.',
Wh='Whoudini:BAABNQAECn8lAAIXAAgKUwukCgAGAQAXAAgKUwukCgAGAQAAAA==.',
Xe='Xerãth:BAABNQAECn9AAAILAAoKiwj8gwCNAQALAAoKiwj8gwCNAQAAAA==.',
Xi='Xiya:BAABNQAECn8cAAIGAAoKShqxJQCoAgAGAAoKShqxJQCoAgAAAA==.',
Ya='Yarndog:BAAANQAECgcIDQAAAA==.Yarnell:BAABNQAECn8hAAIFAAcKdxGzlABCAQAFAAcKdxGzlABCAQAAAA==.Yaviel:BAABNQAECn8ZAAINAAoKww2qkADoAQANAAoKww2qkADoAQAAAA==.',
Yu='Yushis:BAABNQAECn8/AAIYAAoK2hmhEwAWAgAYAAoK2hmhEwAWAgAAAA==.',
Za='Zarrgon:BAEBNQAECn83AAMDAAoKvyQiBACvAwADAAoKqiQiBACvAwAgAAkKqRs5KwCJAgAAAA==.',
Ze='Zelderk:BAACNQAFFH8OAAMbAAcKSw4XAwCgAAAFAAUKzA3yHAAqAQAbAAQK6A0XAwCgAAA1AAQKfzEAAwUACgr/I6ckACYDAAUACQprI6ckACYDABsABApQIG0TACgBAAAA.Zeromus:BAAANQADCgcICwAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQAECgIIAgABNQAECgoKRwABAFEgAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
Zz='Zzeb:BAAANQADCgQIBAAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQAECgMIAQAAAA==.',
['Âl']='Âlpally:BAAANQAECgQIBAAAAA==.',
['Ðr']='Ðrizzt:BAAANQADCggICAABNQAECgkJFQAQAGMRAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgkJFQAQAGMRAA==.',
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
