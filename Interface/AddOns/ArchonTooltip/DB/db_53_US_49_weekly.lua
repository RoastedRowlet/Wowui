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

local lookup = {'Monk-Windwalker','Warrior-Arms','Unknown-Unknown','Shaman-Elemental','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Shaman-Restoration','Warlock-Demonology','Paladin-Retribution','Priest-Discipline','Druid-Feral','Druid-Restoration','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Holy','Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Affliction','DeathKnight-Frost','Mage-Fire','DemonHunter-Vengeance','Hunter-Survival','Warlock-Destruction','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','Druid-Balance',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aahhotep:BAAANQADCgUICQAAAA==.',
Ag='Agnestachyon:BAAANQAECgUIBwAAAA==.',
Ai='Aitwa:BAAANQADCggICAAAAA==.',
Ak='Aksnowman:BAAANQADCgYICAAAAA==.',
Al='Alanbrito:BAAANQAECgMIAwAAAA==.Aliane:BAAANQAECgQICgAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAAANQAECgUICAAAAA==.',
Am='Amoonday:BAAANQAECgQIBwAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.',
Ar='Aramoonsong:BAABNQAECn81AAIBAAkKkiP5AgCpAwABAAkKkiP5AgCpAwAAAA==.Aranrùth:BAABNQAECn8cAAICAAgKEh31UACTAgACAAgKEh31UACTAgAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arthin:BAAANQABCgQIBAAAAA==.',
As='Ashbowbaby:BAAANQAECgQIBQABNQAECgYIDwADAAAAAA==.',
Au='Auraborealis:BAAANQAECgUIDgAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAAANQAECgUIDgAAAA==.',
Az='Azuael:BAAANQAECgcIBwAAAA==.',
Ba='Baberaham:BAAANQAECgEIAQAAAA==.Ballzdragon:BAAANQAECgQIBAABNQAFFAQIBgAEALYJAA==.Balzamon:BAABNQAECn8jAAICAAgKVwmTuwCDAQACAAgKVwmTuwCDAQAAAA==.Bandgeek:BAABNQAECn8aAAMFAAcKFSEVewCIAgAFAAcKdSAVewCIAgAGAAQKwhMLIgDXAAAAAA==.Bantôt:BAAANQADCgQIBAAAAA==.',
Be='Beegood:BAABNQAECn8jAAIHAAcKowfQuwCHAQAHAAcKowfQuwCHAQAAAA==.Beweaver:BAAANQADCggICAABNQAECgQICAADAAAAAA==.',
Bi='Biebert:BAABNQAECn8gAAICAAgKlhWEhgAIAgACAAgKlhWEhgAIAgAAAA==.Bizzy:BAAANQADCgcICgAAAA==.',
Bl='Blooddemon:BAAANQADCggIDAABNQAECggIJQAIAOkYAA==.Bloodegg:BAABNQAECn8oAAIHAAgKEwxdiAD2AQAHAAgKEwxdiAD2AQAAAA==.',
Bo='Boinkadin:BAAANQADCgQIAgAAAA==.Boinkydk:BAAANQADCgIIAgAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQADCgYICAAAAA==.Bredarra:BAAANQADCgYIBgAAAA==.Brewzlee:BAAANQAECgQIBgABNQAECggIDAADAAAAAA==.Broomphondle:BAAANQAECgUIEgAAAA==.Brootis:BAAANQADCgYIBQAAAA==.',
Bs='Bshoottu:BAABNQAECn8VAAIHAAUK5gXFDgHhAAAHAAUK5gXFDgHhAAAAAA==.',
Bu='Bubblina:BAAANQADCgMIBAAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQADAAAAAA==.',
Ce='Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQABCgYIBwAAAA==.Chrisswamy:BAAANQABCgYIBwAAAA==.Chromesatan:BAAANQAECggIBgABNQAECggIDAADAAAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQADCggIJwAAAA==.',
Cr='Crankypal:BAAANQAECgIIAgAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
Cw='Cwdcannabull:BAAANQADCgcIDgAAAA==.',
['Cá']='Cárl:BAAANQABCgIIAgAAAA==.',
Da='Daemage:BAAANQAECggICAAAAA==.Dagara:BAAANQADCgIIAgAAAA==.Daredevill:BAAANQADCgEIAQAAAA==.Darkdrittz:BAAANQAECgUIDwAAAA==.',
De='Deadash:BAAANQADCgcICwABNQAECgYIDwADAAAAAA==.Deathclaw:BAABNQAECn8YAAIJAAcK7A2+pwB/AQAJAAcK7A2+pwB/AQAAAA==.Deceptiõn:BAAANQABCgYIBgAAAA==.Deldúwath:BAAANQAECgcIEwAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dinklage:BAAANQADCgMIAwAAAA==.Dionus:BAABNQAECn8cAAIKAAgKlgmAxACNAQAKAAgKlgmAxACNAQAAAA==.',
Do='Doanh:BAAANQABCgYICAAAAA==.Dolorquedura:BAAANQAECgEIAQAAAA==.Domoarigato:BAAANQAECgQICAAAAA==.',
Dr='Drakuluh:BAAANQAECgMIAwAAAA==.Drapaco:BAAANQABCgMIAwAAAA==.Draucan:BAABNQAECn8cAAILAAgKJR2HAwCvAgALAAgKJR2HAwCvAgAAAA==.Dreadmoor:BAAANQADCgYIEAABNQAECgUIEwADAAAAAA==.Dribblesnot:BAAANQAECgUIEwAAAA==.Driden:BAAANQAECgYIDgAAAA==.',
Dy='Dya:BAAANQADCggIDgAAAA==.',
Ec='Echolock:BAAANQAECgUICAAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgADAAAAAA==.Elemetzy:BAAANQAECgQICAAAAA==.Elkul:BAAANQAECgUICQAAAA==.Elsoned:BAAANQAECgQICgAAAA==.',
Ev='Evokyn:BAAANQADCgIIAgAAAA==.',
Fa='Falafel:BAABNQAECn8cAAIKAAYKaxEH1QBrAQAKAAYKaxEH1QBrAQAAAA==.Fattaco:BAABNQAECn8lAAIIAAgK6RhvSAA9AgAIAAgK6RhvSAA9AgAAAA==.',
Fl='Floss:BAAANQAECgUIDQAAAA==.Flubb:BAABNQAECn8hAAMMAAkKMCMKAgCeAwAMAAkKMCMKAgCeAwANAAEKhQOBeAApAAAAAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQADCgEIAQABNQAECggIJwADAAAAAA==.Followmenot:BAABNQAECn8bAAIGAAcKJxL4DwClAQAGAAcKJxL4DwClAQAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frostyballz:BAAANQAECgMIBgABNQAECgcIFQAKAPgdAA==.Frëyæ:BAAANQADCgQIBAABNQAFFAQIBgAEALYJAA==.',
Fu='Furgus:BAAANQAECgEIAgABNQAECgUIDQADAAAAAA==.',
Fy='Fyerflise:BAAANQADCgUICQAAAA==.Fyrakkobama:BAEANQADCggIDAABNQAECgkJLQAOAJokAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Go='Gobblegobble:BAABNQAECn8gAAIPAAcKGxn7KQDvAQAPAAcKGxn7KQDvAQAAAA==.Gosudizzle:BAABNQAECn8mAAIHAAkK9CIBFQBHAwAHAAkK9CIBFQBHAwABNQAECggIEwADAAAAAA==.',
Gr='Grippingtaco:BAAANQAECgEIAQABNQAECggIJQAIAOkYAA==.',
Gu='Gulldarilynn:BAAANQAECgQIBQAAAA==.',
Gw='Gwendolyn:BAABNQAECn8rAAMMAAkKwyKUAgCIAwAMAAkKwyKUAgCIAwANAAIKJBBsZQBpAAABNQAECgkJNQABAJIjAA==.Gweniveere:BAAANQADCgcIBwAAAA==.',
Ha='Hakubell:BAACNQAFFH8LAAIQAAUK6h1QCQDHAQAQAAUK6h1QCQDHAQA1AAQKfy4AAxAACQoTJVQEAK8DABAACQoTJVQEAK8DAAoABQpdIOW7AJ8BAAE1AAQKBggUABEAZBwA.Hammershock:BAABNQAECn8ZAAIIAAYKfRBMmwA+AQAIAAYKfRBMmwA+AQAAAA==.Hasdiel:BAAANQAECgYIDgAAAA==.',
He='Heartim:BAAANQAECgMIAwAAAA==.Heädaches:BAAANQAECgMIBQAAAA==.',
Ho='Holynuke:BAAANQAECgQIBgABNQAFFAUICQASADgUAA==.',
Il='Illimommy:BAACNQAFFH8UAAIPAAcKHxQIAwAyAgAPAAcKHxQIAwAyAgA1AAQKfxsAAg8ACQrHIH8PAPUCAA8ACQrHIH8PAPUCAAAA.',
In='Inkarok:BAABNQAECn8ZAAITAAcKwxSkPQDHAQATAAcKwxSkPQDHAQAAAA==.',
Is='Ishkode:BAABNQAECn8bAAIUAAgKDAtqCgDQAQAUAAgKDAtqCgDQAQAAAA==.',
It='Itachi:BAAANQAECgEIAQAAAA==.',
Iz='Izzyrael:BAAANQAECgcIBwAAAA==.',
Ja='Jalapeno:BAAANQAECgUIEQAAAA==.Jami:BAABNQAECn8eAAIVAAgKuBDiQQC4AQAVAAgKuBDiQQC4AQABNQADCgIJAgADAAAAAA==.',
Je='Jellybean:BAAANQADCggIFwAAAA==.',
Ji='Jitlo:BAACNQAFFH8OAAIEAAYKfguwBwD0AQAEAAYKfguwBwD0AQA1AAQKfzUAAgQACQozJDIJAJwDAAQACQozJDIJAJwDAAAA.Jitsham:BAAANQAECgYICAAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Jt='Jtclear:BAAANQADCgMIAwAAAA==.',
Ka='Kalanrahl:BAABNQAECn8gAAQGAAgK7RIWDQDeAQAGAAgK7RIWDQDeAQAFAAYKjwuoKQFCAQAWAAEKAAD5DgAnAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.Kashanden:BAAANQAECggICAAAAA==.',
Ke='Kemaneral:BAAANQADCgIJAgAAAA==.',
Kh='Khaiduus:BAABNQAECn8ZAAIEAAgKRBMCTwA4AgAEAAgKRBMCTwA4AgAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAABNQAECn8mAAIXAAgKIRskCQBYAgAXAAgKIRskCQBYAgAAAA==.Kittsune:BAAANQADCgYIBwAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggIHQAAAA==.',
Ko='Kottenmouth:BAACNQAFFH8IAAIYAAUKzhHmAABZAQAYAAUKzhHmAABZAQA1AAQKfzAAAhgACQqmIZ0BAEsDABgACQqmIZ0BAEsDAAAA.',
Kr='Kreyall:BAAANQADCgUIDQAAAA==.Kritea:BAAANQADCggIDwAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECn8kAAICAAgKWA4+oADHAQACAAgKWA4+oADHAQAAAA==.Kyta:BAAANQAECgUIEQAAAA==.',
La='Laupess:BAAANQABCgIIAgAAAA==.',
Le='Lebron:BAAANQAECgIIBAAAAA==.',
Li='Lightbrew:BAAANQAECggIDAAAAA==.Litmus:BAAANQADCgUIBQAAAA==.',
Lo='Locura:BAAANQADCggICQABNQAECgkJNQABAJIjAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAABNQAECn8aAAISAAcK3xEVXQCXAQASAAcK3xEVXQCXAQAAAA==.Magra:BAAANQABCgIIAgAAAA==.Makersmartun:BAAANQAECgMIBAAAAA==.Malthira:BAAANQAECgEIAQAAAA==.Matterdaddy:BAAANQADCgYIBQABNQAECggIGAAYAP4dAA==.',
Mi='Milbi:BAAANQADCgYIDgAAAA==.Minadette:BAAANQADCgYIDwAAAA==.',
Ml='Mljr:BAAANQAECgQICgAAAA==.',
Mo='Moira:BAAANQADCgcIDQAAAA==.Mollicogs:BAAANQADCggICAAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAABNQAECn8mAAIJAAkKNyKEHgAIAwAJAAkKNyKEHgAIAwAAAA==.',
Mu='Munchkins:BAAANQABCggIEAAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Nativelock:BAAANQAECgYIEAAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECggIEQAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.Nilrim:BAAANQABCgIIAgAAAA==.',
No='Norabelle:BAAANQADCgUIBQAAAA==.Nozomila:BAAANQAECgUIDwAAAA==.',
Ny='Nynnaeve:BAAANQAECgUICQAAAA==.',
On='Onthecoda:BAABNQAECn8lAAINAAgKmyFYDAADAwANAAgKmyFYDAADAwAAAA==.',
Oo='Oomgad:BAAANQADCgQICAAAAA==.',
Op='Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgEIAQAAAA==.',
Pa='Paeus:BAAANQABCgUICgAAAA==.Paigeturner:BAABNQAECn8aAAIFAAYKzwPUTAELAQAFAAYKzwPUTAELAQAAAA==.Palapets:BAAANQADCggIEAABNQAECggICgADAAAAAA==.Pantherarosa:BAAANQADCgQIBAABNQAECgUIDQADAAAAAA==.Papalock:BAABNQAECn8VAAIJAAYKNxcOiQDLAQAJAAYKNxcOiQDLAQABNQAECgcIFQAKAPgdAA==.Paramità:BAAANQABCgYICQAAAA==.Parenthi:BAAANQADCgEIAQAAAA==.Pazerp:BAAANQADCgYIBgAAAA==.',
Pe='Peaches:BAAANQADCgEIAQAAAA==.Persymphony:BAABNQAECn8lAAIJAAgKWBymOwCdAgAJAAgKWBymOwCdAgAAAA==.',
Ph='Phabio:BAAANQAECgcIDAAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAcICAAIADULAA==.',
Pi='Pineappletea:BAABNQAECn8dAAIZAAYKyhE9GwCSAQAZAAYKyhE9GwCSAQAAAA==.Pinepally:BAAANQADCgQIBQAAAA==.Pinklock:BAAANQAECgUIDQAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.',
Pr='Priestìtùte:BAAANQADCgUIBQAAAA==.',
['Pø']='Pøøts:BAAANQAECgEIAgAAAA==.',
Qu='Quesy:BAABNQAFFH8JAAMSAAUKOBQ5BwCkAQASAAUKbhM5BwCkAQAVAAIKzxEjFQCRAAAAAA==.',
Ra='Ragnapall:BAAANQADCgUIEAABNQAFFAQIBgAEALYJAA==.Ragnatotemzz:BAACNQAFFH8GAAIEAAQKtgl3FAApAQAEAAQKtgl3FAApAQA1AAQKfxkAAgQACQprHaY7AIQCAAQACQprHaY7AIQCAAAA.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgEIAQAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgEIAQADAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgEIAQADAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Rellock:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.Renkari:BAAANQAECgIIAgAAAA==.Rennl:BAAANQAECgQICAAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICAABNQAECgUIDQADAAAAAA==.Ripsets:BAABNQAECn8vAAMHAAkK3iEBKQDzAgAHAAgKHiIBKQDzAgAaAAgKVh6bHQBiAgAAAA==.',
Ro='Rogueloki:BAABNQAECn8lAAMbAAkKrBTpOgDhAQAbAAcKERPpOgDhAQAcAAYKxxPEIwCnAQAAAA==.Rowscaris:BAAANQAECgUIBwAAAA==.',
Ry='Rynna:BAABNQAECn8VAAIKAAcK+B2ncwBDAgAKAAcK+B2ncwBDAgAAAA==.Rynya:BAAANQAECgMIAwAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAFFAQIBgAEALYJAA==.',
Sa='Sailee:BAAANQADCgYIBgAAAA==.Samelthund:BAAANQABCgUICQAAAA==.Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgcIHQAAAA==.Sarigos:BAABNQAECn8aAAMdAAcKtRG/KgBUAQAdAAYKEBC/KgBUAQAeAAQKywicLAC5AAAAAA==.',
Sc='Schieldemon:BAABNQAECn81AAMPAAkKfRy0DQAJAwAPAAkKfRy0DQAJAwATAAUKZA4zWQAcAQAAAA==.Scrythe:BAABNQAECn8lAAIOAAgKVhRwRwDYAQAOAAgKVhRwRwDYAQAAAA==.Scynline:BAAANQADCgcICQAAAA==.Scynrine:BAAANQABCgIIAgAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQADCgYIDAAAAA==.Sharrin:BAAANQADCgYJBgAAAA==.Shoran:BAAANQADCgYIBgAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgQIBAAAAA==.Slime:BAAANQADCgQIBwAAAA==.',
So='Solomoon:BAABNQAECn8UAAIRAAYKZBwUaADiAQARAAYKZBwUaADiAQAAAA==.Souleatr:BAAANQAECgIIAQABNQAECgYIEwADAAAAAA==.',
Sp='Speisgote:BAAANQAECgUICQAAAA==.Spieros:BAAANQADCggICAABNQAECggIHAALACUdAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECgcIGgAdALURAA==.Stealthpets:BAAANQADCggICQABNQAECggICgADAAAAAA==.Stealthragg:BAAANQADCgQIBAABNQAFFAQIBgAEALYJAA==.Steelehorn:BAAANQADCgUIBQAAAA==.Stewpot:BAAANQADCggIDAAAAA==.Stylish:BAABNQAECn8ZAAQCAAkKpxCxjQD2AQACAAkKkw6xjQD2AQAfAAIKqhiANACMAAAgAAEKHhF2MQA5AAAAAA==.',
Su='Suisui:BAAANQADCgcIGAAAAA==.Suling:BAAANQABCgIIAwAAAA==.Suunde:BAAANQADCgQIBAAAAA==.',
Sy='Sylathra:BAAANQABCgQIBAAAAA==.Syryn:BAAANQAECgUIDAAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQAECgMIAwABNQAECggIEQADAAAAAA==.Thorgrum:BAABNQAECn8lAAMSAAgKfiZ7CwBeAwASAAgKfiZ7CwBeAwAVAAIK6R8bfACvAAAAAA==.Thûnderize:BAABNQAECn8mAAIEAAgKMx7KNQCdAgAEAAgKMx7KNQCdAgAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAAANQAECgQICgAAAA==.Tirea:BAAANQAECgYIEwAAAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgcIHwAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Tripoloski:BAABNQAECn8YAAMhAAkKAh4fBADTAgAhAAcK5CMfBADTAgAcAAgKKBn+EABuAgAAAA==.',
Tu='Tugamuhpud:BAAANQAECgUIEgAAAA==.',
Ty='Tyllas:BAAANQADCgUIBAAAAA==.',
Tz='Tzzird:BAABNQAECn8iAAIKAAkK5hyeLAASAwAKAAkK5hyeLAASAwAAAA==.',
Ug='Ugrah:BAABNQAECn8XAAICAAgKlQoLpwC2AQACAAgKlQoLpwC2AQAAAA==.',
Uk='Ukyomsi:BAAANQABCgIIAgABNQAECgYIEwADAAAAAA==.',
Un='Undeadheals:BAAANQADCgYICgABNQAECgEIAQADAAAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgcICQAAAA==.Vawdkuh:BAABNQAECn8hAAIiAAgKwxH8PAALAgAiAAgKwxH8PAALAgAAAA==.',
Ve='Velddor:BAABNQAECn8YAAIYAAgK/h06AwDlAgAYAAgK/h06AwDlAgAAAA==.',
Vi='Vice:BAAANQAECgYICwAAAA==.Vignette:BAAANQABCgcICAAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAgAAAA==.Vytux:BAAANQABCgMIAwAAAA==.',
['Vö']='Vöx:BAAANQAECgUICQAAAA==.',
Wa='Wartrick:BAABNQAECn8YAAIHAAgKhwlXmgDOAQAHAAgKhwlXmgDOAQAAAA==.',
Wh='Whoudini:BAAANQAECgQICwAAAA==.',
Xe='Xerãth:BAABNQAECn8kAAIFAAgKqAgH7wCpAQAFAAgKqAgH7wCpAQAAAA==.',
Xi='Xiya:BAAANQAECggIDgAAAA==.',
Ya='Yarndog:BAAANQAECgQIBQAAAA==.Yarnell:BAAANQAECgQICQAAAA==.Yaviel:BAAANQAECgcIDAAAAA==.',
Yu='Yushis:BAABNQAECn8lAAIPAAgKUxrTHQBgAgAPAAgKUxrTHQBgAgAAAA==.',
Za='Zarrgon:BAEBNQAECn8tAAMOAAkKmiQWBACvAwAOAAkKgiQWBACvAwASAAgKkhrRKgCIAgAAAA==.',
Ze='Zelderk:BAACNQAFFH8JAAMgAAUK/Q4MAwCgAAACAAQKjw4/HAAqAQAgAAIK6A0MAwCgAAA1AAQKfywAAwIACQrqIQAkACYDAAIACQrqIQAkACYDACAAAgozH+MhAKYAAAE1AAUUBQgJABIAOBQA.Zeromus:BAAANQADCgcICwAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQADCgEJAgABNQAECgkJIgAKAOYcAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
Zz='Zzeb:BAAANQADCgQIBAAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQADCggIEgAAAA==.',
['Âl']='Âlpally:BAAANQAECgQIBAAAAA==.',
['Ðr']='Ðrizzt:BAAANQADCggICAABNQAECgYIEwADAAAAAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgYIEwADAAAAAA==.',
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
