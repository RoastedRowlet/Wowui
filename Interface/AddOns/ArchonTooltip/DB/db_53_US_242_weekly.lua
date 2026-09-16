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

local lookup = {'Priest-Shadow','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Priest-Holy','Priest-Discipline','Druid-Balance','Druid-Restoration','Hunter-Survival','Paladin-Retribution',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Ababear:BAAANQAECgQIBAAAAA==.',
Ad='Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQADCgQIBQAAAA==.',
Al='Alarrius:BAAANQAECgYICgAAAA==.Albedö:BAAANQADCgIIAgABNQAECggIGgABADsWAA==.Algo:BAAANQADCgYIBgAAAA==.Allionys:BAAANQAECgEIAgAAAA==.Aloris:BAAANQAECgIIAwAAAA==.',
Am='Amanises:BAAANQADCgYICQABNQAECgIIAgACAAAAAA==.Amilara:BAAANQADCgYIFQAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Anania:BAAANQADCggIEwABNQADCggIFgACAAAAAA==.Andinestiri:BAAANQAECgQIBAAAAA==.Andolastrasz:BAAANQAECgEIAgAAAA==.Angelic:BAAANQAECgYIBgAAAA==.',
Ao='Ao:BAAANQAECgUICQAAAA==.',
Ap='Apotic:BAAANQAECgQICQAAAA==.Apuntar:BAAANQADCggICAAAAA==.',
Aq='Aquamaree:BAAANQADCgYICgAAAA==.Aquilla:BAABNQAECoEcAAIDAAkJ2RxdEgDkAgADAAkJ2RxdEgDkAgAAAA==.',
Ar='Archenea:BAAANQAECgIIAgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAAANQAECgEIAQAAAA==.Arhianrod:BAAANQADCgIIAgAAAA==.Ariisa:BAAANQADCgYIEwAAAA==.Around:BAAANQAECgQIBAABNQAECgUICQACAAAAAA==.Artty:BAEANQAECgQIBAABNQAECgcICwACAAAAAA==.',
As='Askip:BAAANQADCgIIAgAAAA==.Astrud:BAAANQADCggIFgAAAA==.Asukka:BAAANQADCggICwAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAAANQAECgUIDgABNQAECgkJHQAEAOEcAA==.Attenborough:BAAANQADCgYIBgAAAA==.',
Av='Avesa:BAAANQADCgYIEgAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Az='Azazell:BAAANQADCggIEAAAAA==.Azenea:BAAANQAECgEIAQAAAA==.',
Ba='Baculum:BAAANQAECgIIAgAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Bandolero:BAAANQADCggIEAAAAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Beefstewed:BAAANQADCgIIAgAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgEIAQACAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAAANQAECgMIAwAAAA==.',
Bi='Bigbutter:BAAANQAECgEIAQAAAA==.Bittybow:BAAANQABCgYIBgAAAA==.Bittydrood:BAAANQADCgcIFAAAAA==.Bittylexis:BAAANQAECgIIAgAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAAANQAECgUIBwAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgcIEgACAAAAAA==.Blèu:BAAANQAECgUICQAAAA==.',
Bo='Boggrog:BAAANQADCgMIAwABNQADCgcIFgACAAAAAQ==.Bokan:BAAANQADCgIIAgAAAA==.Box:BAAANQADCggICAAAAA==.',
Br='Braggs:BAAANQADCgcICwAAAA==.Brewballs:BAAANQAECgIIAwAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCgYIBwAAAA==.Bucket:BAAANQAECgEIAgAAAA==.Bunnicula:BAAANQAECgUICgAAAA==.',
['Bö']='Böömer:BAAANQADCggIJQAAAA==.',
Ca='Caelphia:BAAANQAECgQIBAAAAA==.Caimage:BAAANQAECgcIEwAAAA==.Cainnaszun:BAAANQADCgEIAQABNQADCgYIEgACAAAAAA==.Cainnaszunn:BAAANQADCgYIEgAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Caythus:BAACNQAFFIENAAQFAAYJfR4OAwBnAQAFAAQJTxoOAwBnAQAGAAIJgiM4AgDSAAAHAAEJOySfAQBrAAA1AAQKgR8ABAYACQlFJsIAAJkDAAYACQleJMIAAJkDAAUACAnuJXAEAGUDAAcAAQkXJpUSAGsAAAAA.Caythuz:BAABNQAECoEOAAMGAAcJmiCHHQBPAQAFAAYJRyA2RwCuAQAGAAUJGhqHHQBPAQABNQAFFAYIDQAFAH0eAA==.',
Ce='Celeana:BAAANQADCgYIDAAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgIIAgAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chakabad:BAAANQADCgcIDgAAAA==.Chalgah:BAAANQADCgcICQAAAA==.Chenahala:BAAANQADCgcIFAAAAA==.Chåni:BAABNQAECoEaAAIIAAgJpBOiFwAxAgAIAAgJpBOiFwAxAgAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAAANQADCggIDwAAAA==.Claw:BAAANQAECgQIBAAAAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECgIIAgAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Collette:BAAANQABCgcICQAAAA==.Conanascus:BAAANQADCgcIDgABNQAECgUICQACAAAAAA==.Corrupteded:BAAANQADCgYICwAAAA==.',
Cr='Crispysock:BAAANQAECgIIAgAAAA==.Crowe:BAAANQADCgYIEQAAAA==.',
Cy='Cynderr:BAAANQAECgMIBAAAAA==.',
Da='Daisymayhem:BAAANQABCgUIBgAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQADCgYIBgAAAA==.Darkisis:BAAANQADCgcIFAAAAA==.Darknara:BAAANQAECgYIEQAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQADCgYIFAAAAA==.Dasubertakem:BAAANQADCgEIAQAAAA==.Dawni:BAAANQAECgUICAAAAA==.',
De='Deathjeff:BAAANQAECgYIBwAAAA==.',
Di='Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgMIBAAAAA==.Dirtwhistle:BAABNQAECoEVAAIJAAgJwiGrAgAFAwAJAAgJwiGrAgAFAwAAAA==.',
Dr='Dragondh:BAAANQAECgcIEwAAAA==.Drazsi:BAAANQADCggIDQAAAA==.Drosi:BAAANQAECgUIBwAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIIAgAAAA==.',
Ea='Earthesance:BAAANQADCgUIBgAAAA==.',
Eb='Ebeb:BAAANQAECgIIAgAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAAANQAECgEIAQAAAA==.Electricfury:BAAANQADCggIDgAAAA==.Ellebasi:BAAANQADCgYIFQAAAA==.Ellebazy:BAAANQAECgMIAwAAAA==.',
Em='Emmri:BAAANQADCgYICAAAAA==.',
En='Enazen:BAAANQAECgIIAwAAAA==.Enlighthyn:BAABNQAECoEZAAIEAAkJSx7jCgAcAwAEAAkJSx7jCgAcAwAAAA==.',
Er='Erlas:BAAANQADCgYICAAAAA==.Erui:BAAANQADCgcIDwAAAA==.',
Et='Etorion:BAAANQABCgUIBgAAAA==.Etrexxig:BAAANQADCgcICwAAAA==.',
Ev='Evilrayne:BAAANQAECgYIEQAAAA==.',
Fa='Fanfiction:BAAANQAECgUICgAAAA==.Fatherfingur:BAAANQADCgMIAwAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Feather:BAAANQAECgEIAgAAAA==.Felmonger:BAAANQADCggIGgAAAA==.Feloak:BAAANQAECgIIAwAAAA==.Feredir:BAAANQADCgYIFQAAAA==.',
Fi='Fires:BAAANQAECgQICQAAAA==.Fistandilius:BAAANQAECgEIAgAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAAANQAECgUICgAAAA==.',
Fu='Furryfury:BAAANQAECgcIEAAAAA==.Fusrodah:BAAANQAECgUICgAAAA==.Fuzzyewok:BAAANQAECgUIBwAAAA==.',
Ga='Gabaghoul:BAAANQAECgYICgAAAA==.Gameshark:BAAANQADCggIGwAAAA==.Gawdzirra:BAAANQAECgUIBQAAAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAECgUICgAAAQ==.',
Ge='George:BAAANQADCggIEQAAAA==.',
Gh='Ghazghküll:BAAANQADCgcIDgAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQADCgUIBQAAAA==.',
Go='Gohibasi:BAAANQADCgYIEAAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAAANQAECgEIAQAAAA==.',
Gr='Graceosilver:BAAANQADCggIFQAAAA==.Gregnor:BAAANQAECgUIBwAAAA==.Gremöry:BAAANQAECgUICQAAAA==.Grover:BAAANQAECgUICgAAAA==.Grumpybunbun:BAAANQAECgUICAAAAA==.Grüm:BAAANQADCgYIFQAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAAANQAECgQIBgAAAA==.',
Ha='Hairypotter:BAAANQADCgUIDQABNQADCgcIDwACAAAAAA==.Haldar:BAAANQADCgYIBgAAAA==.Hallie:BAAANQADCggIFgAAAA==.Harlu:BAAANQAECgIIAwAAAA==.Hartbroke:BAAANQAECgIIAwAAAA==.Haunter:BAAANQABCgQIBQABNQAECgUICgACAAAAAA==.Hayeon:BAAANQAECgEIAQAAAA==.',
He='Helbourne:BAAANQAECgEIAgAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgQICAACAAAAAA==.',
Hw='Hwanwok:BAAANQAECgEIBAAAAA==.',
Ic='Icemage:BAAANQAECgEIAQAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQADCgYIFQAAAA==.',
Im='Imadragon:BAAANQAECgQICwAAAA==.Imbac:BAAANQADCgQICQAAAA==.Imdeadguy:BAAANQAECgUICgAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCggIFwAAAA==.Ironhelmhtr:BAAANQADCgYIDwAAAA==.Ironscythe:BAAANQADCgIIAgAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jazlee:BAAANQAECgIIAwAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Jezmund:BAAANQAECgQICAAAAA==.',
Ji='Jinathy:BAAANQAECgYICQAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Ju='Juaranir:BAAANQAECgQIBQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Justac:BAAANQADCgYIDAABNQAECgIIAwACAAAAAA==.Justdrood:BAAANQAECgIIAwAAAA==.',
Jw='Jwst:BAAANQABCgYIAgAAAA==.',
['Jà']='Jàß:BAAANQAECgYICQAAAA==.',
['Já']='Jáß:BAAANQAECgYICgAAAA==.',
Ka='Kahleah:BAAANQADCgEIAQAAAA==.Kaldonor:BAAANQAECgUICgAAAA==.Kalenia:BAAANQAECgYIDAAAAA==.Kalvayre:BAAANQAECgEIAQAAAA==.Kanzoorb:BAAANQAECgcIEQAAAA==.Kareshka:BAAANQAECggICQAAAA==.Karinea:BAEANQAECgIIAgAAAA==.Karpana:BAEANQAECgUIDQAAAA==.Karworg:BAAANQADCggIDwAAAA==.Kashir:BAAANQADCggIGQAAAA==.Kashira:BAAANQADCgYICgABNQADCggIGQACAAAAAA==.Kathelee:BAAANQAECgUIBgAAAA==.Kazimirah:BAAANQADCgYIEgAAAA==.Kazrael:BAAANQADCgcIEwAAAA==.',
Ke='Kevinbeacon:BAEANQAECgYIAgAAAA==.',
Kh='Khonsu:BAAANQAECgUIBwAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQACAAAAAA==.',
Ki='Kikora:BAAANQADCgcIDQAAAA==.Kittykitty:BAAANQAECgUICgAAAA==.',
Ko='Kolzane:BAECNQAFFIEGAAIDAAQJrBrBAQCCAQADAAQJrBrBAQCCAQA1AAQKgRgAAgMACQkXJsgBAMkDAAMACQkXJsgBAMkDAAAA.',
Kr='Krezz:BAAANQAECgEIAgAAAA==.',
Ku='Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAAANQAFFAIIAgAAAA==.',
Ky='Kyth:BAAANQAECgQIBQAAAA==.Kythtok:BAAANQADCgYIBgABNQAECgQIBQACAAAAAA==.',
La='Lanx:BAAANQADCgIIAgAAAA==.Laquatas:BAAANQAECgQIBAAAAA==.Laylanduin:BAAANQADCgEIAQABNQAECgYIBwACAAAAAA==.',
Li='Lifebloomer:BAAANQAECgEIAQABNQAECgkJHAAKAG4kAA==.Lightguard:BAAANQABCgYIDwAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgMIAwAAAA==.Littlehell:BAAANQAECggICQAAAA==.',
Lo='Lothrik:BAAANQADCggICAAAAA==.',
Lu='Lucaafer:BAAANQADCgYIEQABNQAECgYICQACAAAAAA==.Ludahealz:BAAANQADCgEIAQABNQAECgUIBQACAAAAAA==.Lunamoonclaw:BAAANQAECgYICgAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgIIAgAAAA==.Lyzoldas:BAAANQAECgQIBAAAAA==.',
['Lö']='Löwryder:BAAANQADCggIFwAAAA==.',
Ma='Mae:BAAANQAECgIIBQAAAA==.Maemura:BAAANQADCgYIFQAAAA==.Magdalaiina:BAAANQAECgIIAwAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magîkarp:BAAANQAECgIIAgAAAA==.Malchromatus:BAAANQAECgUICgAAAA==.Marcosio:BAAANQADCgcIDAAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAAANQAECgYIDgAAAA==.',
Me='Mearkman:BAAANQAECgEIAQAAAA==.Meatyfajita:BAAANQAECgYIDAAAAA==.Meinfurion:BAAANQAECgEIAgAAAA==.Meladie:BAAANQADCgcICQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAAANQAECgUICwAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECgUICwACAAAAAA==.Merlinthos:BAAANQAECgMIAwABNQAECgUICQACAAAAAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAAANQAECgUIBwAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Minecraft:BAABNQAECoEVAAILAAcJQxUXBgDeAQALAAcJQxUXBgDeAQAAAA==.Mingyue:BAAANQADCgYICQABNQAECgYIDQACAAAAAA==.Mirajåne:BAABNQAECoEaAAQBAAgJOxYjEABnAgABAAgJOxYjEABnAgAMAAMJMQpVdwCHAAANAAEJugJmGgAyAAAAAA==.Mishaweha:BAAANQAECgQIBAAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.',
Mo='Modar:BAAANQAECgYICQAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQADCgYIBgAAAA==.',
Mu='Musterd:BAAANQADCgUICQAAAA==.',
['Må']='Måddløck:BAAANQADCgUICwAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.',
Ne='Neiidra:BAAANQADCgcIDgAAAA==.Nepheleah:BAAANQAECgcIEwAAAA==.Nesca:BAAANQAECgQIBQAAAA==.Nesmoth:BAAANQADCggIHAAAAA==.Ness:BAAANQAECgUIBwAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQABCgIIBAAAAA==.Niiborracho:BAAANQAECgQIBQAAAA==.Niiko:BAAANQADCgYIFwAAAA==.',
No='No:BAAANQADCgUIBQAAAA==.Nobullsheep:BAAANQABCgcIBQAAAA==.Norntrox:BAAANQAECgEIAQAAAA==.Nothannah:BAAANQAECgcIEwAAAA==.',
Ns='Nsshaman:BAAANQADCgUIBQAAAA==.',
Og='Ogreatsxtra:BAAANQADCgcIEgAAAA==.',
Ol='Ol:BAAANQAECgUIBQAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgEIAQABNQAECgUICgACAAAAAA==.',
Or='Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgEIAQAAAA==.',
Oz='Ozhawk:BAAANQAECgEIAgAAAA==.',
Pa='Padreburrito:BAAANQADCgYICwAAAA==.Pakno:BAAANQADCgUIBQAAAA==.Pamely:BAAANQAECgUIDQAAAA==.',
Ph='Pharmit:BAAANQAECgUICgAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Potatoad:BAAANQAECgIIAgAAAA==.',
Py='Pyragosa:BAAANQAECgQIBAAAAA==.Pyramys:BAAANQABCgQIAwABNQAECgMIAwACAAAAAA==.',
['Pà']='Pàt:BAAANQAECgIIBAAAAA==.',
['Pâ']='Pândâmoníum:BAAANQADCggIGAAAAA==.',
['På']='Påimon:BAAANQADCggIEAAAAA==.',
Qu='Quintin:BAEANQABCggIDgABNQAECgcICwACAAAAAA==.',
Ra='Racavis:BAAANQADCgMIAwAAAA==.',
Re='Reach:BAAANQADCgQIBAABNQAECgUICQACAAAAAA==.Real:BAAANQAECgUICgAAAA==.Realia:BAAANQAECgcICAAAAA==.Redangus:BAAANQADCgIIAgABNQADCggIDQACAAAAAA==.Reikio:BAAANQADCgIIAgAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAMIBgAOADYWAA==.Revoke:BAAANQAECgQIBAAAAA==.',
Ro='Roronoa:BAAANQADCgQIBQAAAA==.Roßyn:BAAANQAECgQIBQAAAA==.',
Ru='Rubah:BAAANQAECgQIBAAAAA==.Ruroni:BAAANQAECgIIAgAAAA==.',
Ry='Ryniel:BAAANQADCggIFgAAAA==.',
['Ré']='Rédundant:BAAANQADCggICwABNQAECgUICQACAAAAAA==.',
['Rì']='Rìzz:BAAANQAECgYIDAAAAA==.',
Sa='Sabrinalee:BAAANQADCgEIAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQADCggIFgAAAA==.Sannaggi:BAAANQAECgEIAQAAAA==.Sarahnox:BAAANQAECgQIBAAAAA==.Saramoon:BAAANQAECgUICAAAAA==.Sargent:BAAANQADCgUICQAAAA==.Saryaa:BAAANQAECgQIBAAAAA==.Sashchi:BAAANQAECgIIAwAAAA==.Sassenach:BAAANQAECgEIAQAAAA==.Saudelber:BAAANQADCgcIDgAAAA==.',
Sc='Schanks:BAAANQADCgcIBwAAAA==.Scrotius:BAAANQABCgQIAwAAAA==.',
Se='Sedaelina:BAAANQADCgYIBgABNQAECgcIEwACAAAAAA==.Sehmet:BAAANQADCgcIEgAAAA==.Seliria:BAAANQAECgUIBwAAAA==.Seoulmate:BAAANQAECgYIDQAAAA==.Sera:BAAANQAECgQIBgAAAA==.',
Sh='Shadowk:BAAANQABCgIIAgAAAA==.Shaye:BAAANQADCgYICwAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECgYICQACAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shotfoot:BAAANQAECgQIBwAAAA==.Shwang:BAAANQAECgIIAgAAAA==.',
Si='Silbergrad:BAAANQADCggICAAAAA==.Silentio:BAAANQAECgUICQAAAA==.Silihunt:BAAANQAECgQIBwAAAA==.Sinofwrath:BAAANQAECgQIBgAAAA==.Sinsidious:BAAANQADCggIDgAAAA==.Siwin:BAEBNQAECoEcAAMPAAkJ6SV7AADKAwAPAAkJ6SV7AADKAwAOAAIJyRXTXwB1AAAAAA==.',
Sk='Skribb:BAAANQAECgQIBgAAAA==.',
Sm='Smiley:BAABNQAECoEYAAIMAAkJgRTrHwBLAgAMAAkJgRTrHwBLAgABNQAECgkJGAAMAIEUAA==.Smoko:BAAANQAECgEIAQAAAA==.',
Sn='Sneakyboi:BAAANQAECgYICQAAAA==.Snorlax:BAAANQAECgUICgAAAA==.Snowsu:BAACNQAFFIEIAAMFAAUJ/x0hAgCPAQAFAAQJ/R4hAgCPAQAGAAIJChvdAwC8AAA1AAQKgRcAAwUACQnPJAcIADADAAUACAkfJAcIADADAAYABwnnHfwHAFoCAAAA.Snowxstorm:BAAANQAECgIIAgAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAAANQAECgIIAwAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAAANQAECgUIBwAAAA==.',
Sp='Splashzone:BAAANQAECgIIAgAAAA==.',
St='Staqua:BAAANQADCgcIEwAAAA==.Stateomatter:BAAANQAECgQIBAAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgYIDQACAAAAAA==.Summdari:BAAANQAECgUICgAAAA==.Summrot:BAAANQAECgQIBAAAAA==.Sunfrostt:BAAANQADCggIFAAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAAANQADCgcIEwAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgEIAQAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAAANQADCggICAAAAA==.',
Te='Tekeeladin:BAAANQADCggICgABNQAECgcIDwACAAAAAA==.Tekeelà:BAAANQAECgQIBQABNQAECgcIDwACAAAAAA==.Tekelemental:BAAANQAECgQICwAAAA==.Tempestra:BAAANQAECgIIAgAAAA==.Tenebria:BAABNQAECoEWAAIQAAgJLiHWAAA1AwAQAAgJLiHWAAA1AwAAAA==.Terrorhungry:BAAANQADCggIGQAAAA==.',
Th='Thalstrasza:BAAANQAECgUICgAAAA==.The:BAAANQADCggIGAAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAAANQAECgUICgAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tietus:BAAANQADCgcIDgAAAA==.',
Tl='Tlanimass:BAAANQAECgIIAwAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAECgkJHwAFAPsfAA==.',
Ts='Tsu:BAAANQAECgEIAQAAAA==.Tsyubaki:BAAANQAECgQIBAAAAA==.',
Tw='Twerkngherkn:BAAANQADCgUIDwAAAA==.',
Ty='Tybalt:BAAANQAECggICgAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.',
Ul='Uldric:BAAANQAECgEIAgAAAA==.',
Un='Undeaddude:BAAANQABCgYIBgAAAA==.Unslayable:BAAANQADCggIFQAAAA==.',
Uz='Uzzy:BAAANQADCgcIFAAAAA==.',
Va='Valandir:BAAANQAECgIIAgAAAA==.Valyst:BAAANQADCgYIEgAAAA==.Varya:BAAANQABCgQIAwAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAAANQAFFAEIAQAAAA==.Verrenth:BAAANQADCgcIDAABNQAECgYICQACAAAAAA==.',
Vi='Viduus:BAAANQADCggIFAAAAA==.',
Vm='Vmaoh:BAAANQADCggICAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQIBgAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECgYICQACAAAAAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgEIAQAAAA==.Warwickk:BAAANQABCgIIAgABNQADCgUIBQACAAAAAA==.',
Wi='Wickedholi:BAAANQADCgcIBwABNQAECgkJHwAFAPsfAA==.Wickedsmaht:BAABNQAECoEfAAMFAAkJ+x/mEADYAgAFAAgJXB/mEADYAgAGAAMJ8hv3KQDxAAAAAA==.Widowghast:BAAANQAECgQIBgAAAA==.Willowísp:BAAANQAECgYIDQAAAA==.Witerally:BAAANQADCgYIDwAAAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEANQAECgEIAgAAAA==.',
Xa='Xalthea:BAAANQAECggIDwAAAA==.Xandapriest:BAAANQADCgYICwABNQAECgcIEwACAAAAAA==.Xanlock:BAAANQADCgUIBwAAAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECgYIDQACAAAAAA==.',
Xp='Xpddevour:BAAANQAECgYIDAAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAABNQAECoEZAAIRAAgJPxdWMgA9AgARAAgJPxdWMgA9AgAAAA==.',
Ya='Yashoda:BAAANQABCgQIBAAAAA==.',
Ye='Yegarmiester:BAAANQADCggICAAAAA==.Yenti:BAAANQADCggIHQAAAA==.',
Yu='Yuexi:BAAANQADCgYIBgABNQAECgYIDQACAAAAAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAAANQAECgQICAAAAA==.Zap:BAAANQADCgYICgABNQAECgUICgACAAAAAA==.',
Ze='Zerality:BAAANQADCgMIAwAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAAANQAECgQIBgAAAA==.',
Zo='Zookee:BAAANQAECgUIBQAAAA==.',
Zu='Zulizek:BAAANQAECgQIBwAAAA==.',
['Ûr']='Ûrta:BAAANQADCgEIAQAAAA==.',
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
