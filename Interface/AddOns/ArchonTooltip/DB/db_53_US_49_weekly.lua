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

local lookup = {'Monk-Windwalker','Warrior-Arms','Warlock-Affliction','Priest-Holy','Priest-Discipline','Druid-Guardian','Shaman-Elemental','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','DemonHunter-Havoc','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Paladin-Retribution','Druid-Feral','Druid-Restoration','Warlock-Destruction','DemonHunter-Devourer','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Blood','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','Warrior-Protection','Warrior-Fury','Druid-Balance',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aahhotep:BAAANQADCgUICgAAAA==.',
Ag='Agnestachyon:BAAANQAECgUIBwAAAA==.',
Ai='Aingeal:BAAANQADCgEIAQAAAA==.Aitwa:BAAANQADCggICQAAAA==.',
Ak='Akarakua:BAAANQADCgEIAQAAAA==.Aksnowman:BAAANQADCgYICwAAAA==.',
Al='Alanbrito:BAAANQAECgMIAwAAAA==.Alayeka:BAAANQADCgEIAQAAAA==.Aliane:BAAANQAECgUICgAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAAANQAECgUICAAAAA==.Alísea:BAAANQAECgEIAQAAAA==.',
Am='Amoonday:BAAANQAECgQIBwAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.',
Ar='Aramoonsong:BAABNQAECn87AAIBAAoKMSMMAwCpAwABAAoKMSMMAwCpAwAAAA==.Aranrùth:BAABNQAECn8hAAICAAkKhx1fMABNAQACAAkKhx1fMABNAQAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Arcani:BAAANQAECgEIAQAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arthin:BAAANQADCgEIAQAAAA==.',
As='Ashbowbaby:BAAANQAECgUICwABNQAECgcIFgADAPgMAA==.',
Au='Auraborealis:BAABNQAECn8VAAMEAAYK6w0wMgA2AQAEAAYK6w0wMgA2AQAFAAQKPwW5GQCeAAAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAABNQAECn8VAAIGAAYKfSCSCQBhAQAGAAYKfSCSCQBhAQAAAA==.Aviya:BAAANQADCgEIAQAAAA==.',
Az='Azuael:BAAANQAECggICAAAAA==.',
Ba='Baberaham:BAAANQAECgEIAQAAAA==.Baki:BAAANQADCggICAAAAA==.Ballzdragon:BAAANQAECgQIBAABNQAFFAQIBgAHALYJAA==.Balzamon:BAABNQAECn8nAAICAAkKEQmzvQCDAQACAAkKEQmzvQCDAQAAAA==.Bandgeek:BAABNQAECn8bAAMIAAcKFSE0fACGAgAIAAcKdSA0fACGAgAJAAQKwhOAIgDXAAAAAA==.Bantôt:BAAANQADCggIDAAAAA==.',
Be='Beegood:BAABNQAECn8nAAIKAAcKowdzvgCGAQAKAAcKowdzvgCGAQAAAA==.Beweaver:BAAANQADCggICAABNQAECgQICAALAAAAAA==.',
Bi='Biebert:BAABNQAECn8jAAICAAkKQBMpiAAIAgACAAkKQBMpiAAIAgAAAA==.Bizzy:BAAANQADCgcICwAAAA==.',
Bl='Blooddemon:BAAANQAECgEIAQABNQAECgkJLQAMAHgWAA==.Bloodegg:BAABNQAECn8qAAIKAAgKEwxhigD2AQAKAAgKEwxhigD2AQAAAA==.',
Bo='Boinkadin:BAAANQADCggICgAAAA==.Boinkydk:BAAANQAECgMIBAAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQAECgQIBAAAAA==.Bredarra:BAAANQADCgYIBgAAAA==.Brewzlee:BAAANQAECgQIBgABNQAECggIDAALAAAAAA==.Broomphondle:BAABNQAECn8aAAIIAAYKKQ+GFwFlAQAIAAYKKQ+GFwFlAQAAAA==.Brootis:BAAANQADCgYIBgAAAA==.Brothetucker:BAAANQADCgUIBQAAAA==.',
Bs='Bshoottu:BAABNQAECn8XAAIKAAUK9gVwngBwAAAKAAUK9gVwngBwAAAAAA==.',
Bu='Bubblina:BAAANQAECgEIAQAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQALAAAAAA==.',
Ce='Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQAECgEIAQAAAA==.Chrisswamy:BAAANQADCgEIAQAAAA==.Chromesatan:BAAANQAECggIBgABNQAECggIDAALAAAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQADCggIJwAAAA==.',
Cr='Crankypal:BAAANQAECgQIBgAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
Cw='Cwdcannabull:BAAANQADCgcIEAAAAA==.',
['Cá']='Cárl:BAAANQADCgEIAQAAAA==.',
Da='Daemage:BAAANQAECggICQAAAA==.Dagara:BAAANQADCgIIAgAAAA==.Daredevill:BAAANQADCgEIAQAAAA==.Darkdrittz:BAABNQAECn8ZAAINAAYK+ghhVgAzAQANAAYK+ghhVgAzAQAAAA==.Darkjazz:BAAANQAECgIIAgAAAA==.',
De='Deadash:BAAANQADCgcICwABNQAECgcIFgADAPgMAA==.Deathclaw:BAABNQAECn8fAAIOAAgK2wwZMQA1AQAOAAgK2wwZMQA1AQAAAA==.Deceptiõn:BAAANQADCgEIAQAAAA==.Deldúwath:BAABNQAECn8fAAMPAAoKsAqqGQD9AAAQAAgK7AkLDACdAQAPAAUKlgqqGQD9AAAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dinklage:BAAANQADCgMIAwAAAA==.Dionus:BAABNQAECn8jAAIRAAgKogmCVgAYAQARAAgKogmCVgAYAQAAAA==.',
Do='Doanh:BAAANQABCgYICAAAAA==.Dolorquedura:BAAANQAECgEIAQAAAA==.Domenic:BAAANQADCgIIAgAAAA==.Domoarigato:BAAANQAECgQICAAAAA==.',
Dr='Drakuluh:BAAANQAECgMIBgAAAA==.Drapaco:BAAANQABCgMIBQAAAA==.Draucan:BAABNQAECn8fAAMFAAkK5ByPAwCvAgAFAAgKHR6PAwCvAgAEAAEKHROrkgA8AAAAAA==.Dreadmoor:BAAANQADCggIGAABNQAECgYIHAAOAKcNAA==.Dribblesnot:BAABNQAECn8cAAIOAAYKpw11TwDmAAAOAAYKpw11TwDmAAAAAA==.Driden:BAAANQAECgYIDgAAAA==.',
Dy='Dya:BAAANQADCggIEwAAAA==.',
Ec='Echolock:BAAANQAECgUICAAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgALAAAAAA==.Elemetzy:BAAANQAECgQIDAAAAA==.Elkul:BAAANQAECgUICQAAAA==.Elsoned:BAAANQAECgUIDQAAAA==.',
Er='Errob:BAAANQAECgEIAQAAAA==.',
Ev='Evokyn:BAAANQADCgIIAgAAAA==.',
Fa='Falafel:BAABNQAECn8fAAIRAAYKaxF72ABqAQARAAYKaxF72ABqAQAAAA==.Fattaco:BAABNQAECn8tAAIMAAkKeBZ+DQD0AQAMAAkKeBZ+DQD0AQAAAA==.',
Fi='Fizzlestix:BAAANQAECgUIBQAAAA==.',
Fl='Floss:BAAANQAECgUIDQAAAA==.Flubb:BAABNQAECn8lAAMSAAoK8CIUAgCeAwASAAoK8CIUAgCeAwATAAEKhQODegApAAAAAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQADCgEIAQABNQAECggIKAALAAAAAA==.Followmenot:BAABNQAECn8hAAIJAAgK2BApEACkAQAJAAgK2BApEACkAQAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frëyæ:BAAANQADCgQIBAABNQAFFAQIBgAHALYJAA==.',
Fu='Furgus:BAAANQAECgEIAgABNQAECgcIFwAUAEMIAA==.',
Fy='Fyerflise:BAAANQADCgUICgAAAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Go='Gobblegobble:BAABNQAECn8mAAIVAAcKGxl9EQAmAQAVAAcKGxl9EQAmAQAAAA==.Gosudizzle:BAABNQAECn8pAAIKAAoKtR6DFQBGAwAKAAoKtR6DFQBGAwABNQAECgkJHAANAOcRAA==.',
Gr='Griffith:BAAANQADCggICAAAAA==.Grippingtaco:BAAANQAECgMIBQABNQAECgkJLQAMAHgWAA==.',
Gu='Gulldarilynn:BAAANQAECgQIBQAAAA==.',
Gw='Gwendolyn:BAABNQAECn81AAMSAAoK9CIuAABLAwASAAoK9CIuAABLAwATAAIKJBAEZwBpAAABNQAECgoKOwABADEjAA==.Gweniveere:BAAANQADCgcIBwAAAA==.',
Ha='Hakubell:BAACNQAFFH8MAAIWAAYKJRySCQDHAQAWAAYKJRySCQDHAQA1AAQKfy4AAxYACQoTJXIEAK8DABYACQoTJXIEAK8DABEABQpdIHe/AJ4BAAE1AAQKBggUAAQAZBwA.Hammershock:BAABNQAECn8bAAIMAAcKvg/hnAA+AQAMAAcKvg/hnAA+AQAAAA==.Hasdiel:BAAANQAECgYIDgAAAA==.',
He='Heartim:BAAANQAECgMIAwAAAA==.Heädaches:BAAANQAECgMIBQAAAA==.',
Ho='Holynuke:BAAANQAECgQIBgABNQAFFAUIDAAXAAMaAA==.',
Il='Illimommy:BAACNQAFFH8VAAIVAAcKHxQdAwAxAgAVAAcKHxQdAwAxAgA1AAQKfx0AAhUACgo5H8IPAPUCABUACgo5H8IPAPUCAAAA.',
In='Inkarok:BAABNQAECn8eAAINAAcKbBXBHwD+AAANAAcKbBXBHwD+AAAAAA==.',
Is='Ishkode:BAABNQAECn8eAAIDAAkKOwp8CgDQAQADAAkKOwp8CgDQAQAAAA==.',
It='Itachi:BAAANQAECgQIBQAAAA==.',
Iz='Izzyrael:BAAANQAECgcICQAAAA==.',
Ja='Jalapeno:BAAANQAECgUIEQAAAA==.Jami:BAABNQAECn8eAAIYAAgKuBALQwC4AQAYAAgKuBALQwC4AQABNQADCgIJAgALAAAAAA==.',
Je='Jellybean:BAAANQADCggIGAAAAA==.',
Ji='Jitlo:BAACNQAFFH8PAAIHAAYKfgsqCADxAQAHAAYKfgsqCADxAQA1AAQKfzYAAgcACgriIWcJAJwDAAcACgriIWcJAJwDAAAA.Jitsham:BAAANQAECggICwAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Jt='Jtclear:BAAANQADCgMIAwAAAA==.',
Ju='Juanillo:BAAANQADCgcIBwAAAA==.',
Ka='Kadybear:BAAANQAECgEIAQAAAA==.Kaety:BAAANQAECgEIAQAAAA==.Kalanrahl:BAABNQAECn8iAAQJAAoK7g9ADQDeAQAJAAkKbRFADQDeAQAIAAcKVwoQLAFCAQAZAAEKAAAuDwAnAAAAAA==.Kaldaern:BAAANQADCgEIAQABNQADCgQJBAALAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.Kashanden:BAAANQAECggIDwAAAA==.',
Ke='Kemaneral:BAAANQADCgIJAgAAAA==.',
Kh='Khaiduus:BAABNQAECn8jAAIHAAoKEhRtBwDxAQAHAAoKEhRtBwDxAQAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAABNQAECn8tAAIaAAgK4BvMAQDZAQAaAAgK4BvMAQDZAQAAAA==.Kittsune:BAAANQADCgYICQAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggIIgAAAA==.',
Ko='Korgorn:BAAANQADCgEIAwAAAA==.Kottenmouth:BAACNQAFFH8MAAIbAAUKFxRwAADtAAAbAAUKFxRwAADtAAA1AAQKfzQAAhsACgqdHaYBAEoDABsACgqdHaYBAEoDAAAA.',
Kr='Kreyall:BAAANQADCgUIDQAAAA==.Kritea:BAAANQADCggIDwAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECn8kAAICAAgKWA4bogDHAQACAAgKWA4bogDHAQAAAA==.Kyta:BAABNQAECn8aAAIOAAYKhAgAXgDGAAAOAAYKhAgAXgDGAAAAAA==.',
La='Lanallea:BAAANQADCgEIAQAAAA==.Laupess:BAAANQABCgIIAgAAAA==.',
Le='Lebron:BAAANQAECgIIBQAAAA==.',
Li='Lightbrew:BAAANQAECggIDAAAAA==.Litmus:BAAANQADCgUIBQAAAA==.',
Lo='Locura:BAAANQADCggICgABNQAECgoKOwABADEjAA==.Louskunt:BAAANQAECgUICwABNQAECgkJIgARAPkdAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAABNQAECn8hAAIXAAcKdRI8DwBkAQAXAAcKdRI8DwBkAQAAAA==.Magra:BAAANQADCgEIAQAAAA==.Makersmartun:BAAANQAECgMIBAAAAA==.Malthira:BAAANQAECgEIAQAAAA==.Matterdaddy:BAAANQADCgYIBQABNQAECgkJGwAbAAccAA==.',
Mi='Milbi:BAAANQAECgEIAQAAAA==.Minadette:BAAANQAECgEIAQAAAA==.',
Ml='Mljr:BAAANQAECgUIDAAAAA==.',
Mo='Moira:BAAANQADCggIEQAAAA==.Mollicogs:BAAANQADCggICAAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAACNQAFFH8GAAIOAAYKyhIuEQB3AQAOAAYKyhIuEQB3AQA1AAQKfy8AAg4ACgqQIVkCANQCAA4ACgqQIVkCANQCAAAA.',
Mu='Munchkins:BAAANQABCggIEAAAAA==.',
Mw='Mwesten:BAAANQAECgEIAQAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Nativelock:BAABNQAECn8bAAIDAAcKDQTQEgAdAQADAAcKDQTQEgAdAQAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECggIEgAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.Nilrim:BAAANQABCgIIAgAAAA==.',
No='Norabelle:BAAANQADCgUIBwAAAA==.Nozomila:BAAANQAECgUIEAAAAA==.',
Ny='Nynnaeve:BAAANQAECgUICQAAAA==.',
On='Onthecoda:BAABNQAECn8lAAITAAgKmyGhDAADAwATAAgKmyGhDAADAwAAAA==.',
Oo='Oomgad:BAAANQADCgQICAAAAA==.',
Op='Opadden:BAAANQADCgEIAQAAAA==.Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgIIAQAAAA==.',
Pa='Paeus:BAAANQAECgEIAQAAAA==.Pagani:BAAANQADCgEIAQAAAA==.Paigeturner:BAABNQAECn8fAAIIAAYKEATOiQCxAAAIAAYKEATOiQCxAAAAAA==.Palapets:BAAANQADCggIEgABNQAECggICgALAAAAAA==.Pantherarosa:BAAANQAECgYIDAABNQAECgcIFwAUAEMIAA==.Papalock:BAABNQAECn8YAAIOAAgKwxdRiwDKAQAOAAgKwxdRiwDKAQABNQAECgkJIgARAPkdAA==.Paramità:BAAANQADCgEIAQAAAA==.Parenthi:BAAANQADCgEIAQAAAA==.Pazerp:BAAANQADCggICgAAAA==.',
Pe='Peaches:BAAANQADCgEIAQAAAA==.Persymphony:BAABNQAECn8oAAIOAAkKgxvyPACcAgAOAAkKgxvyPACcAgAAAA==.',
Ph='Phabio:BAAANQAECggIDAAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAcIDQAMAD4LAA==.',
Pi='Pineappletea:BAABNQAECn8dAAIUAAYKyhFmGwCSAQAUAAYKyhFmGwCSAQAAAA==.Pinepally:BAAANQADCgQIBwAAAA==.Pinklock:BAABNQAECn8XAAIUAAcKQwhCBQDVAAAUAAcKQwhCBQDVAAAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.Pootsii:BAAANQADCgEIAQAAAA==.',
Pr='Priestìtùte:BAAANQAECgQIBAAAAA==.',
['Pø']='Pøøts:BAAANQAECgIIAgAAAA==.',
Qu='Quesy:BAACNQAFFH8MAAMXAAUKAxpRBwClAQAXAAUKbhNRBwClAQAYAAQKAxrBBwCrAAA1AAQKfxYABBcACgr/IxAQADYDABcACAqKJBAQADYDABgABAqOHcsQAH8BABwAAQoAAAAAAAAAAAAA.',
Ra='Ragnapall:BAAANQADCgUIEAABNQAFFAQIBgAHALYJAA==.Ragnatotemzz:BAACNQAFFH8GAAIHAAQKtgn2FAApAQAHAAQKtgn2FAApAQA1AAQKfxsAAgcACQprHT88AIQCAAcACQprHT88AIQCAAAA.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgMIAwAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgMIAwALAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgMIAwALAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Rellock:BAAANQADCgcICQABNQAECgEIAQALAAAAAA==.Renkari:BAAANQAECgMIAwAAAA==.Rennl:BAAANQAECgUICgAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICgABNQAECgcIFwAUAEMIAA==.Ripsets:BAABNQAECn8zAAMKAAoKhx+6KQDxAgAKAAkKaB+6KQDxAgAdAAgKVh73HQBhAgAAAA==.',
Ro='Rogueloki:BAABNQAECn8rAAMPAAoKDRYKPADhAQAPAAcKERMKPADhAQAeAAcKKRYtJACnAQAAAA==.Roonrangi:BAAANQAECgUIBQAAAA==.Rousset:BAAANQADCgEIAQAAAA==.Rowscaris:BAAANQAECgUIBwAAAA==.',
Ry='Rynna:BAABNQAECn8iAAIRAAkK+R34BgB3AgARAAkK+R34BgB3AgAAAA==.Rynya:BAAANQAECgMIAwAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAFFAQIBgAHALYJAA==.',
Sa='Sailee:BAAANQADCgYIBgAAAA==.Samelthund:BAAANQADCgEIAgAAAA==.Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgcIJAAAAA==.Sarigos:BAABNQAECn8hAAMfAAgKixLwAwC8AQAfAAcKQRHwAwC8AQAgAAQKywj5LAC5AAAAAA==.',
Sc='Schieldemon:BAABNQAECn8/AAMNAAoKNxtBCgClAQAVAAkKix36DQAIAwANAAcK+RNBCgClAQAAAA==.Scrythe:BAABNQAECn8oAAIcAAkKKxQzSADXAQAcAAkKKxQzSADXAQAAAA==.Scynline:BAAANQADCgcICwAAAA==.Scynrine:BAAANQADCgEIAQAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQAECgUIBgAAAA==.Sharrin:BAAANQADCgYJBgAAAA==.Shoran:BAAANQADCgYIBgAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgQIBAAAAA==.Slime:BAAANQADCgYICAAAAA==.',
So='Solomoon:BAABNQAECn8UAAIEAAYKZByFaQDiAQAEAAYKZByFaQDiAQAAAA==.Souleatr:BAAANQAECgUIBQABNQAECgcIFgAhAD4MAA==.',
Sp='Speisgote:BAAANQAECgUICQAAAA==.Spieros:BAAANQAECgUIBQABNQAECgkJHwAFAOQcAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECggIIQAfAIsSAA==.Stealthpets:BAAANQADCggICgABNQAECggICgALAAAAAA==.Stealthragg:BAAANQAECgcICgABNQAFFAQIBgAHALYJAA==.Steelehorn:BAAANQADCgUIBgAAAA==.Stewpot:BAAANQADCggIDQAAAA==.Stylish:BAABNQAECn8bAAQCAAoKCRB2jwD2AQACAAoKOA52jwD2AQAiAAIKqhhANQCLAAAjAAEKHhEjMgA5AAAAAA==.',
Su='Suisui:BAAANQADCgcIGQAAAA==.Suling:BAAANQADCgEIAQAAAA==.Suunde:BAAANQADCgQIBQAAAA==.',
Sy='Sylathra:BAAANQADCgEIAQAAAA==.Syryn:BAABNQAECn8UAAIKAAYKvwpVzgBkAQAKAAYKvwpVzgBkAQAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQAECgMIAwABNQAECggIEgALAAAAAA==.Thorgrum:BAABNQAECn8oAAMXAAkKcSagCwBeAwAXAAkKcSagCwBeAwAYAAIK6R/7fgCuAAAAAA==.Thûnderize:BAABNQAECn8uAAIHAAkKrBzZBgD7AQAHAAkKrBzZBgD7AQAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAAANQAECgQIDwAAAA==.Tirea:BAABNQAECn8WAAIhAAcKPgzCGgC3AQAhAAcKPgzCGgC3AQAAAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgcIJAAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Trashedpanda:BAAANQADCgQIBAAAAA==.Tripoloski:BAABNQAECn8cAAMQAAoKryAtBADTAgAQAAcK5CMtBADTAgAeAAkKbxzsDgBfAQAAAA==.',
Tu='Tugamuhpud:BAABNQAECn8gAAMDAAcKvwLSHACYAAADAAUKxAHSHACYAAAOAAcKswL9egCNAAAAAA==.',
Ty='Tyllas:BAAANQADCgUIBAAAAA==.',
Tz='Tzzird:BAABNQAECn8sAAIRAAoKohxIBgCFAgARAAoKohxIBgCFAgAAAA==.',
Ug='Ugrah:BAABNQAECn8ZAAICAAgKlQrkqAC2AQACAAgKlQrkqAC2AQAAAA==.',
Uk='Ukyomsi:BAAANQADCgEIAQABNQAECgcIFgAhAD4MAA==.',
Un='Undeadheals:BAAANQAECgMIAwAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgcICwAAAA==.Varod:BAAANQAECgIIAwAAAA==.Vawdkuh:BAABNQAECn8oAAIkAAkKLhGjFgApAQAkAAkKLhGjFgApAQAAAA==.',
Ve='Velddor:BAABNQAECn8bAAIbAAkKBxxDAwDkAgAbAAkKBxxDAwDkAgAAAA==.',
Vi='Vice:BAAANQAECgYICwAAAA==.Vignette:BAAANQAECgEIAQAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAwAAAA==.Vytux:BAAANQADCgEIAQAAAA==.',
['Vö']='Vöx:BAAANQAECgcIDQAAAA==.',
Wa='Wartrick:BAABNQAECn8aAAIKAAgKkAmjnADOAQAKAAgKkAmjnADOAQAAAA==.',
Wh='Whoudini:BAAANQAECgUIEQAAAA==.',
Wu='Wumbo:BAAANQADCgEIAQAAAA==.',
Xe='Xerãth:BAABNQAECn8mAAIIAAgKqAhE8QCoAQAIAAgKqAhE8QCoAQAAAA==.',
Xi='Xiya:BAAANQAECggIEAAAAA==.',
Ya='Yarndog:BAAANQAECgQIBgAAAA==.Yarnell:BAAANQAECgQIDQAAAA==.Yaviel:BAAANQAECggIDAAAAA==.',
Yu='Yushis:BAABNQAECn8oAAIVAAkKOxkwHgBfAgAVAAkKOxkwHgBfAgAAAA==.',
Za='Zarrgon:BAEBNQAECn8wAAMcAAoK7SMiBACvAwAcAAoK1yMiBACvAwAXAAgKkho5KwCJAgAAAA==.',
Ze='Zelderk:BAACNQAFFH8KAAMjAAUK/Q4XAwCgAAACAAQKjw7yHAAqAQAjAAIK6A0XAwCgAAA1AAQKfzAAAwIACgrXIqckACYDAAIACQrqIackACYDACMABApQIDAGAD0BAAE1AAUUBQgMABcAAxoA.Zeromus:BAAANQADCgcIDAAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQADCgEJAgABNQAECgoKLAARAKIcAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
Zz='Zzeb:BAAANQADCgQIBAAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQADCggIEwAAAA==.',
['Âl']='Âlpally:BAAANQAECgQIBAAAAA==.',
['Ðr']='Ðrizzt:BAAANQADCggICAABNQAECgcIFgAhAD4MAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgcIFgAhAD4MAA==.',
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
