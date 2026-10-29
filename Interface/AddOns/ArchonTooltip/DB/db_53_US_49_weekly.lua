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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','Monk-Windwalker','Warrior-Arms','Warlock-Affliction','Priest-Holy','Priest-Discipline','Druid-Guardian','Shaman-Elemental','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','DemonHunter-Havoc','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','Druid-Feral','Druid-Restoration','Warlock-Destruction','DemonHunter-Devourer','Paladin-Holy','Warrior-Fury','Evoker-Augmentation','DeathKnight-Frost','Mage-Fire','DeathKnight-Unholy','DemonHunter-Vengeance','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Druid-Balance',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aahhotep:BAAANQADCgUICQAAAA==.',
Ag='Agnestachyon:BAAANQAECgUIBwAAAA==.',
Ai='Aitwa:BAAANQADCggICAAAAA==.',
Ak='Aksnowman:BAAANQADCgYICAAAAA==.',
Al='Alanbrito:BAAANQAECgMIAwAAAA==.Albus:BAAANQAECgUICgABNQAECgkJJAABAAUeAA==.Aliane:BAAANQAECgUICgAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAAANQAECgUIDQAAAA==.Alísea:BAAANQABCggIDwAAAA==.',
Am='Amoonday:BAAANQAECgQIBwAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.Andrewsmom:BAEANQADCgYIBgABNQAECgoKNQACAHAkAA==.',
Ar='Aramoonsong:BAABNQAECn9FAAIDAAoKMSMMAwCpAwADAAoKMSMMAwCpAwAAAA==.Aranrùth:BAABNQAECn8tAAIEAAkKTyA+FADDAgAEAAkKTyA+FADDAgAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Arcani:BAAANQADCgIIAgAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arthin:BAAANQABCgQIBAAAAA==.',
As='Ashbowbaby:BAAANQAECgYICwABNQAECgcIFgAFAPgMAA==.',
Au='Auraborealis:BAABNQAECn8bAAMGAAYK1xXDTQB6AQAGAAYK1xXDTQB6AQAHAAQKPwW5GQCeAAAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAABNQAECn8bAAIIAAYKfSBDFAAhAgAIAAYKfSBDFAAhAgAAAA==.',
Az='Azuael:BAAANQAECggIBwAAAA==.',
Ba='Baberaham:BAAANQAECgEIAQAAAA==.Baki:BAAANQAECggICQAAAA==.Ballzdragon:BAAANQAECgYIBwABNQAFFAUIBwAJAAYIAA==.Balzamon:BAABNQAECn8rAAIEAAoKoAmzvQCDAQAEAAoKoAmzvQCDAQAAAA==.Bandgeek:BAABNQAECn8kAAMKAAkKFR+CNQAcAgAKAAkK2h6CNQAcAgALAAQKwhOAIgDXAAAAAA==.Bantôt:BAAANQADCggIFAAAAA==.',
Be='Beegood:BAABNQAECn8sAAIMAAgKVgdzvgCGAQAMAAgKVgdzvgCGAQAAAA==.Beweaver:BAAANQADCggICAABNQAECgQICAANAAAAAA==.',
Bi='Biebert:BAABNQAECn8jAAIEAAkKQBMpiAAIAgAEAAkKQBMpiAAIAgAAAA==.Bizzy:BAAANQADCgcICgAAAA==.',
Bl='Blooddemon:BAAANQAECgEIAQABNQAECgoKNgAOAGsVAA==.Bloodegg:BAABNQAECn8qAAIMAAgKEwxhigD2AQAMAAgKEwxhigD2AQAAAA==.',
Bo='Boinkadin:BAAANQAECgQIBAAAAA==.Boinkydk:BAAANQAECgMIAwAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQAECgQICAAAAA==.Bredarra:BAAANQADCgYIBgAAAA==.Brewzlee:BAAANQAECgUIBgABNQAECgoKFgABAOgTAA==.Broomphondle:BAABNQAECn8dAAIKAAcKeA2GFwFlAQAKAAcKeA2GFwFlAQAAAA==.Brootis:BAAANQADCgYIBQAAAA==.Brothetucker:BAAANQADCgUICQAAAA==.',
Bs='Bshoottu:BAABNQAECn8cAAIMAAUKvQZPwACxAAAMAAUKvQZPwACxAAAAAA==.',
Bu='Bubblina:BAAANQADCgUIBgAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQANAAAAAA==.',
Ce='Celestìa:BAAANQAECgUIBQAAAA==.Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQABCgYIBwAAAA==.Chrisswamy:BAAANQABCgYIBwAAAA==.Chromesatan:BAAANQAECggIBgABNQAECgoKFgABAOgTAA==.Chubtubs:BAAANQADCggICQABNQAFFAUIEQAGAHsYAA==.Chuglee:BAAANQAECgYIBgAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQADCggIJwAAAA==.',
Cr='Crankypal:BAAANQAECgQICgAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
Cw='Cwdcannabull:BAAANQADCggIEQAAAA==.',
['Cá']='Cárl:BAAANQABCgIIAgAAAA==.',
Da='Daemage:BAAANQAECggICwAAAA==.Dagara:BAAANQADCgIIAgAAAA==.Daredevill:BAAANQADCgEIAQAAAA==.Darkdrittz:BAABNQAECn8ZAAIPAAYK+ghhVgAzAQAPAAYK+ghhVgAzAQAAAA==.Darkjazz:BAAANQAECgIIAgAAAA==.',
De='Deadash:BAAANQADCgcICwABNQAECgcIFgAFAPgMAA==.Deathclaw:BAABNQAECn8lAAIQAAgK8Ay0ZQA2AQAQAAgK8Ay0ZQA2AQAAAA==.Deceptiõn:BAAANQABCgYIBgAAAA==.Deldúwath:BAABNQAECn8mAAMRAAoKpwycDAC1AQARAAkKaQycDAC1AQASAAgK7AkLDACdAQAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dinklage:BAAANQADCgMIAwAAAA==.Dionus:BAABNQAECn8rAAIBAAkKCAnOhgBDAQABAAkKCAnOhgBDAQAAAA==.',
Do='Doanh:BAAANQABCgYICAAAAA==.Dolorquedura:BAAANQAECgEIAQAAAA==.Domenic:BAAANQADCgIIAgAAAA==.Domoarigato:BAAANQAECgQICAAAAA==.',
Dr='Drakuluh:BAAANQAECgMIBgAAAA==.Draucan:BAABNQAECn8oAAMHAAkKNR8lAQC3AgAHAAgKLyAlAQC3AgAGAAEKaRdmvgBBAAAAAA==.Dreadmoor:BAAANQADCggIFwABNQAECgYIIgAQAKcNAA==.Dribblesnot:BAABNQAECn8iAAIQAAYKpw30iADgAAAQAAYKpw30iADgAAAAAA==.Driden:BAAANQAECgYIDwAAAA==.',
Dy='Dya:BAAANQAECgEIAQAAAA==.',
Ec='Echolock:BAAANQAECgUICAAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgANAAAAAA==.Elemetzy:BAABNQAECn8bAAQTAAoKiRaACwDnAQATAAkKgBWACwDnAQAJAAUK9RcQngBbAQAOAAQKUgmbgwC7AAAAAA==.Elkul:BAAANQAECgQICQAAAA==.Elsoned:BAABNQAECn8YAAIBAAYK4As5zgDFAAABAAYK4As5zgDFAAAAAA==.',
Er='Errob:BAAANQADCgUIBQAAAA==.',
Eu='Euclid:BAAANQAECgQIBAAAAA==.',
Ev='Evokyn:BAAANQADCgIIAgAAAA==.',
Fa='Falafel:BAABNQAECn8jAAIBAAYKkxF72ABqAQABAAYKkxF72ABqAQAAAA==.Fattaco:BAABNQAECn82AAIOAAoKaxWaJwATAgAOAAoKaxWaJwATAgAAAA==.',
Fi='Fizzlestix:BAAANQAECgYICwAAAA==.',
Fl='Floss:BAABNQAECn8VAAIBAAYK3AnH8QA5AQABAAYK3AnH8QA5AQAAAA==.Flubb:BAABNQAECn8wAAMUAAoK8iIUAgCeAwAUAAoK8iIUAgCeAwAVAAEKhQODegApAAAAAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQAECgYIBgABNQAECggIKQANAAAAAA==.Followmenot:BAABNQAECn8lAAILAAgKMREpEACkAQALAAgKMREpEACkAQAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frëyæ:BAAANQADCgQIBAABNQAFFAUIBwAJAAYIAA==.',
Fu='Furgus:BAAANQAECgEIAgABNQAECgcIGwAWAEMIAA==.',
Fy='Fyerflise:BAAANQADCgUICQAAAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Go='Gobblegobble:BAABNQAECn8mAAIXAAcKGxl6KgDuAQAXAAcKGxl6KgDuAQAAAA==.Gosudizzle:BAACNQAFFH8FAAIMAAIK0Qc3GwB1AAAMAAIK0Qc3GwB1AAA1AAQKfywAAgwACgr5H4MVAEYDAAwACgr5H4MVAEYDAAE1AAQKCQkgAA8AXRIA.',
Gr='Griffith:BAAANQADCggICAAAAA==.Grippingtaco:BAAANQAECgQIAwABNQAECgoKNgAOAGsVAA==.',
Gu='Gulldarilynn:BAAANQAECgUICgAAAA==.',
Gw='Gwendolyn:BAABNQAECn8/AAMUAAoK7yPqAABQAwAUAAoK7yPqAABQAwAVAAIKJBAEZwBpAAABNQAECgoKRQADADEjAA==.Gweniveere:BAAANQADCgcIBwAAAA==.',
Ha='Hakubell:BAACNQAFFH8NAAIYAAcK/RuSCQDHAQAYAAcK/RuSCQDHAQA1AAQKfzMAAxgACgqIJHIEAK8DABgACgqIJHIEAK8DAAEABQpdIHe/AJ4BAAE1AAQKBggUAAYAZBwA.Hammershock:BAABNQAECn8iAAIOAAcKzhVmQgCNAQAOAAcKzhVmQgCNAQAAAA==.Hasdiel:BAAANQAECgYIDgAAAA==.',
He='Heartim:BAAANQAECgMIAwAAAA==.Heädaches:BAAANQAECgMIBQAAAA==.',
Ho='Holynuke:BAAANQAECgQIBgABNQAFFAYICwAZAP0OAA==.',
Ic='Ichabel:BAAANQADCgUIBQAAAA==.',
Il='Illimommy:BAACNQAFFH8VAAIXAAcKHxQdAwAxAgAXAAcKHxQdAwAxAgA1AAQKfycAAhcACgqoIlIFAMwCABcACgqoIlIFAMwCAAAA.',
In='Inkarok:BAABNQAECn8jAAIPAAcKbBVgPgDHAQAPAAcKbBVgPgDHAQAAAA==.',
Is='Ishkode:BAABNQAECn8nAAIFAAkKOAs+BQCNAQAFAAkKOAs+BQCNAQAAAA==.',
It='Itachi:BAAANQAECgUICgAAAA==.',
Iz='Izzyrael:BAAANQAECgcICQAAAA==.',
Ja='Jalapeno:BAABNQAECn8XAAIaAAYKBwjVEwDxAAAaAAYKBwjVEwDxAAAAAA==.Jami:BAABNQAECn8eAAIbAAgKuBALQwC4AQAbAAgKuBALQwC4AQABNQADCgIJAgANAAAAAA==.',
Je='Jellybean:BAAANQADCggIFwAAAA==.',
Ji='Jitlo:BAACNQAFFH8PAAIJAAYKfgsqCADxAQAJAAYKfgsqCADxAQA1AAQKfz8AAgkACgqAJGcJAJwDAAkACgqAJGcJAJwDAAAA.Jitsham:BAAANQAECggICgAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Jt='Jtclear:BAAANQADCgcICgAAAA==.',
Ju='Juanillo:BAAANQADCgcICgAAAA==.',
Ka='Kalanrahl:BAABNQAECn8jAAQLAAoKAhFADQDeAQALAAoKAhFADQDeAQAKAAcKVwoQLAFCAQAcAAEKAAAuDwAnAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.Kashanden:BAABNQAECn8ZAAMCAAoKPB1LCwCUAgACAAkKPB1LCwCUAgAdAAQKdwbdZABDAAAAAA==.',
Ke='Kemaneral:BAAANQADCgIJAgAAAA==.',
Kh='Khaiduus:BAABNQAECn8qAAIJAAoKnxeuGAA5AgAJAAoKnxeuGAA5AgAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAABNQAECn8xAAIeAAoKgxq8AwA9AgAeAAoKgxq8AwA9AgAAAA==.Kittsune:BAAANQADCgYIBwAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggIJwAAAA==.',
Ko='Kottenmouth:BAACNQAFFH8PAAIfAAUK/BXpAABZAQAfAAUK/BXpAABZAQA1AAQKfz0AAh8ACgp4HqYBAEoDAB8ACgp4HqYBAEoDAAAA.',
Kr='Kreyall:BAAANQADCgUIEAAAAA==.Kritea:BAAANQADCggIDwAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECn8oAAIEAAoK+gwbogDHAQAEAAoK+gwbogDHAQAAAA==.Kyta:BAABNQAECn8gAAIQAAYKCgoXkADQAAAQAAYKCgoXkADQAAAAAA==.',
La='Laupess:BAAANQABCgIIAgAAAA==.',
Le='Lebron:BAAANQAECgQICAAAAA==.',
Li='Lightbrew:BAABNQAECn8WAAIBAAoK6BP/OwAKAgABAAoK6BP/OwAKAgAAAA==.Litmus:BAAANQADCgUIBQAAAA==.',
Lo='Locura:BAAANQADCggICQABNQAECgoKRQADADEjAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAABNQAECn8qAAIdAAgKBhYnFADoAQAdAAgKBhYnFADoAQAAAA==.Magra:BAAANQABCgIIAgAAAA==.Makersmartun:BAAANQAECgMIBAAAAA==.Malthira:BAAANQAECgEIAQAAAA==.Matterdaddy:BAAANQADCgcIBwABNQAECgoKIAAfAKEfAA==.',
Mi='Milbi:BAAANQADCgYIDgAAAA==.Minadette:BAAANQADCgYIEwAAAA==.',
Ml='Mljr:BAABNQAECn8XAAIKAAgKygimmwAOAQAKAAgKygimmwAOAQAAAA==.Mljrone:BAAANQAECgQIBAAAAA==.',
Mo='Moira:BAAANQAECgEIAQAAAA==.Mollicogs:BAAANQADCggICgAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAACNQAFFH8GAAIQAAYKyhIuEQB3AQAQAAYKyhIuEQB3AQA1AAQKfzgAAhAACgpTIiIJAOsCABAACgpTIiIJAOsCAAAA.',
Mu='Munchkins:BAAANQABCggIEAAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Naleen:BAEANQADCgIIAgABNQAECgoKNQACAHAkAA==.Nativelock:BAABNQAECn8iAAIFAAgKmgQXCwDhAAAFAAgKmgQXCwDhAAAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECggIEQAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.Nilrim:BAAANQABCgIIAgAAAA==.',
No='Norabelle:BAAANQADCgUIBgAAAA==.Nozomila:BAAANQAECgUIEQAAAA==.',
Ny='Nynnaeve:BAAANQAECgUIDgAAAA==.',
['Nú']='Núrnen:BAAANQAECgMIAwAAAA==.',
On='Onthecoda:BAABNQAECn8pAAIVAAkK4yChDAADAwAVAAkK4yChDAADAwAAAA==.',
Oo='Oomgad:BAAANQADCgQICAAAAA==.',
Op='Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgIIAQAAAA==.',
Pa='Paeus:BAAANQABCgUICgAAAA==.Paigeturner:BAABNQAECn8lAAIKAAcKEwRavgDMAAAKAAcKEwRavgDMAAAAAA==.Palapets:BAAANQAECgIIAgABNQAECggICgANAAAAAA==.Pantherarosa:BAAANQAECgUIDgABNQAECgcIGwAWAEMIAA==.Papalock:BAABNQAECn8aAAIQAAgKwxdRiwDKAQAQAAgKwxdRiwDKAQABNQAECgkJJAABAAUeAA==.Parenthi:BAAANQADCgEIAQAAAA==.Pazerp:BAAANQADCggIDAAAAA==.',
Pe='Peaches:BAAANQADCgEIAQAAAA==.Persymphony:BAABNQAECn8xAAIQAAkK/B2MJgAbAgAQAAkK/B2MJgAbAgAAAA==.',
Ph='Phabio:BAAANQAECgcIDgAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAcIDQAOAD4LAA==.',
Pi='Pineappletea:BAABNQAECn8dAAIWAAYKyhFmGwCSAQAWAAYKyhFmGwCSAQAAAA==.Pinepally:BAAANQADCgQIBQAAAA==.Pinklock:BAABNQAECn8bAAIWAAcKQwjoCwDBAAAWAAcKQwjoCwDBAAAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.Pootsii:BAAANQADCgEIAQAAAA==.',
['Pø']='Pøøts:BAAANQAECgIIAgAAAA==.Pøøtsi:BAAANQAECgEIAQAAAA==.',
Qu='Quesy:BAACNQAFFH8MAAMdAAUKAxpRBwClAQAdAAUKbhNRBwClAQAbAAQKAxp4DACmAAA1AAQKfxsABB0ACgp8JBAQADYDAB0ACAqKJBAQADYDABsABQqIIg4oAJMBAAIAAQoAAAAAAAAAAAE1AAUUBggLABkA/Q4A.',
Ra='Ragnapall:BAAANQAECgIIAgABNQAFFAUIBwAJAAYIAA==.Ragnatotemzz:BAACNQAFFH8HAAIJAAUKBgj2FAApAQAJAAUKBgj2FAApAQA1AAQKfx0AAgkACgoHHz88AIQCAAkACgoHHz88AIQCAAAA.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgMIAwAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgQIBQANAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgQIBQANAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Rellock:BAAANQADCgcIBwABNQAECgEIAQANAAAAAA==.Renalla:BAAANQAECgQIBAAAAA==.Renkari:BAAANQAECgMIAwAAAA==.Rennl:BAAANQAECgUIDwAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICAABNQAECgcIGwAWAEMIAA==.Ripsets:BAABNQAECn85AAMMAAoKEyK6KQDxAgAMAAkKUSK6KQDxAgAgAAgKVh73HQBhAgAAAA==.',
Ro='Rogueloki:BAABNQAECn8xAAMRAAoK1RcKPADhAQARAAcKERMKPADhAQAhAAgKRxifPQBsAQAAAA==.Roonrangi:BAAANQAECgUIBQAAAA==.Rowscaris:BAAANQAECgUIBwAAAA==.',
Ry='Rynna:BAABNQAECn8kAAIBAAkKBR5+LgBCAgABAAkKBR5+LgBCAgAAAA==.Rynya:BAAANQAECgMIAwAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAFFAUIBwAJAAYIAA==.',
Sa='Sailee:BAAANQADCgYIBwAAAA==.Samelthund:BAAANQABCgUICQAAAA==.Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgcIJwAAAA==.Sarigos:BAABNQAECn8oAAMiAAgKYxU6DADHAQAiAAcKgBQ6DADHAQAjAAQKywj5LAC5AAAAAA==.',
Sc='Schieldemon:BAACNQAFFH8FAAMXAAIKpQxLDQBGAAAXAAIKpQxLDQBGAAAPAAIKkwI7FAA2AAA1AAQKf0kAAxcACgo3G/oNAAgDABcACQqLHfoNAAgDAA8ACQprEl0cALgBAAAA.Scrythe:BAABNQAECn8xAAICAAkKLhT3KABUAQACAAkKLhT3KABUAQAAAA==.Scynline:BAAANQADCgcICQAAAA==.Scynrine:BAAANQABCgIIAgAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQAECgUICQAAAA==.Sharrin:BAAANQADCgYJBgAAAA==.Shoran:BAAANQADCgYIBgAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgUIBQAAAA==.Slime:BAAANQADCgYICAAAAA==.',
So='Solomoon:BAABNQAECn8UAAIGAAYKZByFaQDiAQAGAAYKZByFaQDiAQAAAA==.Souleatr:BAAANQAECgUICQABNQAECgcIGgATAD4MAA==.',
Sp='Speisgote:BAAANQAECgUIDgAAAA==.Spieros:BAAANQAECgUIBQABNQAECgkJKAAHADUfAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECggIKAAiAGMVAA==.Starforge:BAAANQADCgIIAgAAAA==.Stealthpets:BAAANQADCggICQABNQAECggICgANAAAAAA==.Stealthragg:BAAANQAECggIEAABNQAFFAUIBwAJAAYIAA==.Steelehorn:BAAANQADCgUIBQAAAA==.Stewpot:BAAANQADCggIDAAAAA==.Stigmã:BAAANQADCgQIBQAAAA==.Stylish:BAABNQAECn8gAAQEAAoKYhJ2jwD2AQAEAAoKCBB2jwD2AQAkAAMKyRZANQCLAAAZAAEKHhEjMgA5AAAAAA==.',
Su='Suisui:BAAANQADCgcIGAAAAA==.Suling:BAAANQABCgIIAwAAAA==.Suunde:BAAANQADCgQIBAAAAA==.',
Sy='Sylathra:BAAANQABCgQIBAAAAA==.Syryn:BAABNQAECn8aAAIMAAcK6ghVzgBkAQAMAAcK6ghVzgBkAQAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQAECgMIAwABNQAECggIEQANAAAAAA==.Thorgrum:BAABNQAECn8xAAMdAAkKcSagCwBeAwAdAAkKcSagCwBeAwAbAAIK6R/7fgCuAAAAAA==.Thûnderize:BAABNQAECn83AAIJAAoKBR96HwAAAgAJAAoKBR96HwAAAgAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAABNQAECn8YAAIGAAcKSxTzQwCiAQAGAAcKSxTzQwCiAQAAAA==.Tirea:BAABNQAECn8aAAITAAcKPgzCGgC3AQATAAcKPgzCGgC3AQAAAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgcIJAAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Trashedpanda:BAAANQAECgYIBgAAAA==.Trastuzumab:BAAANQADCgIIAgAAAA==.Tripoloski:BAABNQAECn8gAAMSAAoKjCItBADTAgASAAcK5CMtBADTAgAhAAkKTR4qEQBuAgAAAA==.',
Tu='Tugamuhpud:BAABNQAECn8wAAMQAAkKgwMNhADsAAAQAAkKewMNhADsAAAFAAUKxAHSHACYAAAAAA==.',
Ty='Tyllas:BAAANQADCgUIBAAAAA==.',
Tz='Tzzird:BAABNQAECn82AAIBAAoKkR01IACMAgABAAoKkR01IACMAgAAAA==.',
Ug='Ugrah:BAABNQAECn8fAAIEAAkK5AvkqAC2AQAEAAkK5AvkqAC2AQAAAA==.',
Uk='Ukyomsi:BAAANQABCgIIAgABNQAECgcIGgATAD4MAA==.',
Un='Undeadheals:BAAANQAECgMIBQABNQAECgQIBQANAAAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgcICQAAAA==.Varod:BAAANQAECggICgAAAA==.Vawdkuh:BAABNQAECn8uAAIlAAoKlRFEJgBTAQAlAAoKlRFEJgBTAQAAAA==.',
Ve='Velddor:BAABNQAECn8gAAIfAAoKoR9DAwDkAgAfAAoKoR9DAwDkAgAAAA==.Vellea:BAAANQABCgIIAgAAAA==.',
Vi='Vice:BAABNQAECn8XAAIBAAkKtAlJgQBOAQABAAkKtAlJgQBOAQAAAA==.Vignette:BAAANQABCgcICAAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAgAAAA==.Vytux:BAAANQABCgMIAwAAAA==.',
['Vô']='Vôx:BAAANQAECgMIAwABNQAECgcIDAANAAAAAA==.',
['Vö']='Vöx:BAAANQAECgcIDAAAAA==.',
Wa='Wartrick:BAABNQAECn8eAAIMAAoKtAijnADOAQAMAAoKtAijnADOAQAAAA==.',
Wh='Whoudini:BAABNQAECn8YAAIWAAYKuAzdDAC4AAAWAAYKuAzdDAC4AAAAAA==.',
Xe='Xerãth:BAABNQAECn8vAAIKAAkKuAgYbwBoAQAKAAkKuAgYbwBoAQAAAA==.',
Xi='Xiya:BAAANQAECggIEgAAAA==.',
Ya='Yarndog:BAAANQAECgUICAAAAA==.Yarnell:BAABNQAECn8WAAIEAAYK+Q/ckwDlAAAEAAYK+Q/ckwDlAAAAAA==.Yaviel:BAABNQAECn8YAAIMAAkKiw6qkADoAQAMAAkKiw6qkADoAQAAAA==.',
Yu='Yushis:BAABNQAECn8xAAIXAAkKOxkXEwC5AQAXAAkKOxkXEwC5AQAAAA==.',
Za='Zarrgon:BAEBNQAECn81AAMCAAoKcCQiBACvAwACAAoK1yMiBACvAwAdAAkKqRs5KwCJAgAAAA==.',
Ze='Zelderk:BAACNQAFFH8LAAMZAAYK/Q4XAwCgAAAEAAQKjw7yHAAqAQAZAAMK6A0XAwCgAAA1AAQKfzEAAwQACgr/I6ckACYDAAQACQprI6ckACYDABkABApQIEAMADUBAAAA.Zeromus:BAAANQADCgcICwAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQADCgEJAgABNQAECgoKNgABAJEdAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
Zz='Zzeb:BAAANQADCgQIBAAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQAECgEIAQAAAA==.',
['Âl']='Âlpally:BAAANQAECgQIBAAAAA==.',
['Ðr']='Ðrizzt:BAAANQADCggICAABNQAECgcIGgATAD4MAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgcIGgATAD4MAA==.',
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
