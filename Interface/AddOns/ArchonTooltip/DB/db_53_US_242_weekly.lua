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

local lookup = {'Unknown-Unknown','Priest-Shadow','Hunter-BeastMastery','Evoker-Preservation','Paladin-Holy','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Assassination','Warrior-Protection','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Blood','Warrior-Fury','Priest-Holy','Priest-Discipline','Paladin-Retribution','Druid-Restoration','Druid-Balance','Hunter-Survival','Monk-Brewmaster','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aahnna:BAAANQADCggJCAABNQAECgQIBQABAAAAAA==.',
Ab='Ababear:BAAANQAECgQJBwAAAA==.',
Ad='Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQADCgUJBgAAAA==.',
Al='Alarrius:BAAANQAECgYJEAAAAA==.Albedö:BAAANQADCgIIAgABNQAECgkJIQACAA8YAA==.Algo:BAAANQAECgIJAgAAAA==.Algrubeley:BAAANQABCgUJBQABNQAECgQIDAABAAAAAA==.Alithirae:BAAANQADCgIIAgAAAA==.Allionys:BAAANQAECgEIAgAAAA==.Aloris:BAAANQAECgQIBwAAAA==.',
Am='Amanises:BAAANQAECgQICAABNQAECgcICAABAAAAAA==.Amilara:BAAANQADCggJHQAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Ananaya:BAAANQADCgcIBwABNQAECgIJAgABAAAAAA==.Anania:BAAANQADCggIEwABNQAECgIJAgABAAAAAA==.Andinestiri:BAAANQAECgYJBQAAAA==.Andolastrasz:BAAANQAECgIIBAAAAA==.Angelic:BAAANQAECgYIBgAAAA==.',
Ao='Ao:BAAANQAECgYIDwAAAA==.',
Ap='Apotic:BAAANQAECgYJDwAAAA==.Apuntar:BAAANQADCggJDgAAAA==.',
Aq='Aquamaree:BAAANQAECgEIAQAAAA==.Aquilla:BAACNQAFFIEHAAIDAAQK9gnuBQBDAQADAAQK9gnuBQBDAQA1AAQKgR8AAgMACQo1HsocAM4CAAMACQo1HsocAM4CAAAA.',
Ar='Archenea:BAAANQAECgUIBgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAAANQAECgUJCwAAAA==.Arhianrod:BAAANQADCgIIAgAAAA==.Ariisa:BAAANQADCggJGwAAAA==.Around:BAAANQAECgQICAABNQAECgcIEAABAAAAAA==.Artty:BAEANQAECgQIBAABNQAECgcIEgABAAAAAA==.',
As='Askip:BAAANQADCgIIAgAAAA==.Astrud:BAAANQADCggIHQAAAA==.Asukka:BAAANQAECgIIAgAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAABNQAECoEcAAIEAAgKUBw3CgDDAgAEAAgKUBw3CgDDAgABNQAECgkJHQAFAOEcAA==.Attenborough:BAAANQADCgYJBgAAAA==.',
Au='Audiamer:BAAANQADCgUIBQAAAA==.',
Av='Avesa:BAAANQADCgcIGQAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Az='Azazell:BAAANQADCggJEQAAAA==.Azenea:BAAANQAECgQIBQAAAA==.',
Ba='Baculum:BAAANQAECgUJBwAAAA==.Badmoonrisin:BAAANQADCgYJCQAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Bandolero:BAAANQADCggIEAAAAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Beefstewed:BAAANQADCgUJBwAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgQIBAABAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAAANQAECgUIBQAAAA==.',
Bi='Bigbutter:BAAANQAECgEIAQAAAA==.Bittybow:BAAANQABCgcICgAAAA==.Bittydrood:BAAANQADCggIFgAAAA==.Bittylexis:BAAANQAECgUJBwAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Bleu:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAAANQAECgYJDQAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgkKGgAGAFYeAA==.Blèu:BAAANQAECgUICQAAAA==.',
Bo='Boggrog:BAAANQAECgEJAQAAAQ==.Bokan:BAAANQAECgEJAQAAAA==.Box:BAAANQADCggICAAAAA==.',
Br='Braggs:BAAANQADCgcIEgAAAA==.Breathe:BAAANQAECgQIBAAAAA==.Brewballs:BAAANQAECgUJDAAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCggIDwAAAA==.Bucket:BAAANQAECgMJBQAAAA==.Bunnicula:BAAANQAECgYJEAAAAA==.',
['Bö']='Böömer:BAAANQAECgIJAgAAAA==.',
Ca='Caelphia:BAAANQAECgQIBgAAAA==.Caimage:BAAANQAECgcIEwAAAA==.Cainnaszun:BAAANQADCgEIAQABNQADCgcJCwABAAAAAA==.Cainnaszunn:BAAANQADCgYIEwABNQADCgcJCwABAAAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Caythus:BAACNQAFFIEUAAQHAAcKjh7wAgDFAQAHAAUKfBrwAgDFAQAIAAIKaCVgAgDeAAAJAAEKOyT0AgBoAAA1AAQKgSMABAgACQq5JgIBAIQDAAgACQpeJAIBAIQDAAcACApxJrQFAHADAAkAAQoXJg4XAGoAAAAA.Caythuz:BAABNQAECoEOAAMIAAcKmiDbIABGAQAHAAYKRyBdZACaAQAIAAUKGhrbIABGAQABNQAFFAcIFAAHAI4eAA==.',
Ce='Celeana:BAAANQADCgcJDQAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgIIAgAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgIIAgAAAA==.Chakabad:BAAANQADCggJFQAAAA==.Chalgah:BAAANQAECgEIAQAAAA==.Chenahala:BAAANQADCggJGwAAAA==.Chåni:BAABNQAECoEiAAIKAAgKmBbLFwBUAgAKAAgKmBbLFwBUAgAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAAANQAECgQJBAAAAA==.Claw:BAAANQAECgYICAABNQAECgkJHgALAEMjAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECgQJBAAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Collette:BAAANQABCgcICQAAAA==.Conanascus:BAAANQADCgcIDgABNQAECgYIDwABAAAAAA==.Corrupteded:BAAANQADCggJEwAAAA==.',
Cr='Crispysock:BAAANQAECgQIBgAAAA==.Crowe:BAAANQADCgYIEQAAAA==.',
Cy='Cynderr:BAAANQAECgMJBwAAAA==.',
Da='Daisymayhem:BAAANQABCgUJBgAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQADCgcJDQAAAA==.Darkisis:BAAANQADCggJGwAAAA==.Darknara:BAAANQAECgYIEQAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQADCgYIFAAAAA==.Dasubertakem:BAAANQADCgYJBwAAAA==.Dawni:BAAANQAECgYJDgAAAA==.',
De='Deathjeff:BAAANQAECgcICQAAAA==.Deathsgates:BAAANQAECgQIBAABNQAECgkJHgAMACMbAA==.',
Di='Didymus:BAAANQADCgUIBQAAAA==.Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgQICAAAAA==.Dirtwhistle:BAABNQAECoEWAAINAAgKLSLCAwD5AgANAAgKLSLCAwD5AgAAAA==.',
Dr='Dragondh:BAABNQAECoEYAAIOAAkK7RUeGQBjAgAOAAkK7RUeGQBjAgAAAA==.Drazsi:BAAANQAECgEJAQAAAA==.Drosi:BAAANQAECgYJDQAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIJAgAAAA==.',
Ea='Earthesance:BAAANQAECgIJAgAAAA==.',
Eb='Ebeb:BAAANQAECgUJBwAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAAANQAECgQJBQAAAA==.Electricfury:BAAANQADCggIFgAAAA==.Ellebasi:BAAANQADCggJHQAAAA==.Ellebazy:BAAANQAECgUICAAAAA==.',
Em='Emmri:BAAANQAECgQIBAAAAA==.',
En='Enazen:BAAANQAECgQIBwAAAA==.Enlighthyn:BAABNQAECoEaAAIFAAkK0R7JDwANAwAFAAkK0R7JDwANAwAAAA==.',
Er='Erlas:BAAANQADCgcIDwAAAA==.Erui:BAAANQADCggJEAAAAA==.',
Es='Esmeluz:BAAANQADCgMIAwAAAA==.',
Et='Etorion:BAAANQABCgUIBgAAAA==.Etrexxig:BAAANQADCgcJCwAAAA==.',
Ev='Evilrayne:BAABNQAECoEaAAIGAAcKFBd4iQD/AQAGAAcKFBd4iQD/AQAAAA==.',
Fa='Fanfiction:BAAANQAECgUICgAAAA==.Fatherfingur:BAAANQADCgMIAwAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Feather:BAAANQAECgUIBwAAAA==.Felmonger:BAAANQADCggIHgAAAA==.Feloak:BAAANQAECgYJCQAAAA==.Feredir:BAAANQADCggJHQAAAA==.',
Fi='Fires:BAAANQAECgUJDgAAAA==.Fistandilius:BAAANQAECgEIAgAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAAANQAECgYIEAAAAA==.',
Fu='Furryfury:BAABNQAECoEbAAIPAAgK1Rq0CgB7AgAPAAgK1Rq0CgB7AgAAAA==.Fusrodah:BAAANQAECgYIDQAAAA==.Fuzzyewok:BAAANQAECgYJDQAAAA==.',
Ga='Gabaghoul:BAAANQAECgYJEAAAAA==.Gameshark:BAAANQAECgIIAgAAAA==.Gawdzirra:BAAANQAECgYICwAAAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAECgYIEAAAAQ==.',
Ge='Geauxaway:BAAANQADCgQIAgAAAA==.George:BAAANQADCggIGQAAAA==.',
Gh='Ghazghküll:BAAANQADCgcIFAAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQADCgUIBQAAAA==.',
Go='Gohibasi:BAAANQADCggJGAAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAAANQAECgIJAgAAAA==.',
Gr='Graceosilver:BAAANQADCggIHAAAAA==.Gregnor:BAAANQAECgYJDQAAAA==.Gremöry:BAAANQAECgYIDgAAAA==.Grover:BAAANQAECgYJEAAAAA==.Grumpybunbun:BAAANQAECgYJDgAAAA==.Grüm:BAAANQADCggJHQAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAAANQAECgUJCwAAAA==.',
Ha='Haarl:BAAANQADCgcJBwAAAA==.Hairypotter:BAAANQADCgUJDQABNQADCggJEAABAAAAAA==.Haldar:BAAANQADCgcJDAAAAA==.Hallie:BAAANQADCggJHQAAAA==.Harlu:BAAANQAECgUJCAAAAA==.Hartbroke:BAAANQAECgUJCAAAAA==.Haunter:BAAANQAECgMIAwABNQAECgYJEAABAAAAAA==.Hayeon:BAAANQAECgEIAQAAAA==.',
He='Helbourne:BAAANQAECgEIAgAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Ho='Holyrollerz:BAAANQADCgYIBgAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgQIDwABAAAAAA==.',
Hw='Hwanwok:BAAANQAECgEIBAAAAA==.',
Ic='Icemage:BAAANQAECgEIBAAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQADCggJHQAAAA==.',
Im='Imadragon:BAAANQAECgYIEQAAAA==.Imbac:BAAANQADCgQJDQAAAA==.Imdeadguy:BAAANQAECgYJEAAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCggIFwAAAA==.Ironhelmhtr:BAAANQADCgYIEwAAAA==.Ironscythe:BAAANQADCgYJCAAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jace:BAAANQADCggIDgAAAA==.Jazlee:BAAANQAECgUJCAAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Jezmund:BAAANQAECgQJDAAAAA==.',
Ji='Jinathy:BAAANQAECgYJDwAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Ju='Juaranir:BAAANQAECgUJCgAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Justac:BAAANQADCgYJEgABNQAECgUJCAABAAAAAA==.Justdrood:BAAANQAECgUJCAAAAA==.',
Jw='Jwst:BAAANQABCgYIAgAAAA==.',
['Jà']='Jàß:BAAANQAECgYICQAAAA==.',
['Já']='Jáß:BAAANQAECgYIDAAAAA==.',
Ka='Kahleah:BAAANQADCgcIBAAAAA==.Kaldonor:BAAANQAECgUIDwAAAA==.Kalenia:BAAANQAECgYIEgAAAA==.Kalvayre:BAAANQAECgEIAgAAAA==.Kanzoorb:BAABNQAECoEbAAIGAAkKcRpHRgC4AgAGAAkKcRpHRgC4AgAAAA==.Kareshka:BAAANQAECggICQAAAA==.Karinea:BAEANQAECgUJBwAAAA==.Karpana:BAEANQAECgUIDwAAAA==.Karworg:BAAANQADCggIDwAAAA==.Kashir:BAAANQAECgIJAgAAAA==.Kashira:BAAANQADCgYICgABNQAECgIJAgABAAAAAA==.Kathelee:BAAANQAECgYIDAAAAA==.Kazimirah:BAAANQADCgYJEgAAAA==.Kazrael:BAAANQAECgEJAQAAAA==.',
Ke='Keekat:BAAANQADCggJCAAAAA==.Kevinbeacon:BAEANQAECgYIAgAAAA==.',
Kh='Kharnij:BAAANQADCggICAAAAA==.Khonsu:BAAANQAECgYJDQAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.',
Ki='Kiamei:BAAANQAECgEJAQAAAA==.Kikora:BAAANQADCgcIDQAAAA==.Kittykitty:BAAANQAECgYJEAAAAA==.',
Ko='Kolzane:BAECNQAFFIELAAIDAAUK6R59AQDuAQADAAUK6R59AQDuAQA1AAQKgRoAAgMACQpFJvUCALkDAAMACQpFJvUCALkDAAAA.',
Kr='Krezz:BAAANQAECgEIAgAAAA==.',
Ku='Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAABNQAECoEYAAIDAAkKyBs6HQDLAgADAAkKyBs6HQDLAgAAAA==.',
Ky='Kynlyn:BAAANQADCgQIBAAAAA==.Kyth:BAAANQAECgUICgAAAA==.Kythtok:BAAANQADCgYICAABNQAECgUICgABAAAAAA==.',
La='Lanx:BAAANQADCgIIAgAAAA==.Laquatas:BAAANQAECgYJBgAAAA==.Laylanduin:BAAANQADCgEIAQABNQAECgcICQABAAAAAA==.',
Le='Lenash:BAAANQADCgQIBAABNQABCgIIBAABAAAAAA==.',
Li='Lifebloomer:BAAANQAECgEIAQABNQAFFAUICwAQAGYfAA==.Lightguard:BAAANQAECgQIBAAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgMJBQAAAA==.Littlehell:BAAANQAECggICQAAAA==.',
Lo='Lothrik:BAAANQADCggICAAAAA==.',
Lu='Lucaafer:BAAANQADCgYIFwABNQAECgYJCgABAAAAAA==.Ludaa:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.Ludahealz:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Lunamoonclaw:BAAANQAECgYJEAAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgQIBgAAAA==.Lyzoldas:BAAANQAECgYJBgAAAA==.',
['Lá']='Lárry:BAAANQADCgIJAgAAAA==.',
['Lö']='Löwryder:BAAANQAECgIIAgAAAA==.',
Ma='Mae:BAAANQAECgMIBwAAAA==.Maemura:BAAANQADCggJHQAAAA==.Magdalaiina:BAAANQAECgUJCAAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magîkarp:BAAANQAECgUIBwAAAA==.Malchromatus:BAAANQAECgUJDwAAAA==.Marcosio:BAAANQADCggIEgAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAAANQAECgcJDwAAAA==.Mavik:BAAANQADCggICAAAAA==.',
Me='Mearkman:BAAANQAECgIJAwAAAA==.Meatyfajita:BAAANQAECgYIEQAAAA==.Meinfurion:BAAANQAECgEIAgAAAA==.Meladie:BAAANQADCgcICQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAAANQAECgYIEQAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECgYIEQABAAAAAA==.Merlinthos:BAAANQAECgMIAwABNQAECgYIDwABAAAAAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAAANQAECgYJDQAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Minecraft:BAABNQAECoEXAAIRAAgKtRl1BABtAgARAAgKtRl1BABtAgAAAA==.Mingyue:BAAANQADCgYICQABNQAECgYJEwABAAAAAA==.Mirajåne:BAABNQAECoEhAAQCAAkKDxjmDQDBAgACAAkKDxjmDQDBAgASAAMKZg3OjwCfAAATAAEKugLTHgAuAAAAAA==.Mishaweha:BAAANQAECgYJBQAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mitos:BAAANQADCgMJAwAAAA==.',
Mo='Modar:BAAANQAECgcJDQAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQADCgYJDAAAAA==.',
Mu='Musterd:BAAANQADCgYJDQAAAA==.',
['Må']='Måddløck:BAAANQADCgYJDAAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.',
Ne='Neiidra:BAAANQAECgEJAQAAAA==.Nepheleah:BAABNQAECoEbAAIUAAkKrR95EwA7AwAUAAkKrR95EwA7AwAAAA==.Nesca:BAAANQAECgQJBQAAAA==.Nesmoth:BAAANQAECgIJAgAAAA==.Ness:BAAANQAECgUICwAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQABCgIIBAAAAA==.Niiborracho:BAAANQAECgUJCgAAAA==.Niiko:BAAANQADCggIHgAAAA==.',
No='No:BAAANQADCgUJBQABNQAECgcIDQABAAAAAA==.Nobullsheep:BAAANQABCgcJBQAAAA==.Nommy:BAAANQAECgUICAABNQAECggIHAADAIAYAA==.Norntrox:BAAANQAECgMJBAAAAA==.Nothannah:BAABNQAECoEYAAIVAAgKcg9ZGwDGAQAVAAgKcg9ZGwDGAQAAAA==.',
Ns='Nsshaman:BAAANQADCgUJBQAAAA==.',
Od='Odyssey:BAAANQADCggJCAABNQAECgYJDQABAAAAAA==.',
Og='Ogreatsxtra:BAAANQAECgEIAQAAAA==.',
Ol='Ol:BAAANQAECgUIBQAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgEJAQABNQAECgYJEAABAAAAAA==.',
Or='Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgIJAgAAAA==.',
Oz='Ozhawk:BAAANQAECgEIAgAAAA==.',
Pa='Padreburrito:BAAANQADCgYICwAAAA==.Pakno:BAAANQADCgUIBQAAAA==.Pamely:BAABNQAECoEXAAIUAAgK9hPTUwAIAgAUAAgK9hPTUwAIAgAAAA==.',
Ph='Pharmit:BAAANQAECgYJEAAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Potatoad:BAAANQAECgIIBAAAAA==.',
Pw='Pwags:BAAANQADCgUJBQAAAA==.',
Py='Pyragosa:BAAANQAECgYJCgAAAA==.Pyramys:BAAANQABCgQIAwABNQAECgQIBwABAAAAAA==.',
['Pà']='Pàt:BAAANQAECgUIBwAAAA==.',
['Pâ']='Pândâmoníum:BAAANQAECgIJAgAAAA==.',
['På']='Påimon:BAAANQADCggJEAAAAA==.',
Qu='Quintin:BAEANQADCgIJAgABNQAECgcIEgABAAAAAA==.',
Ra='Racavis:BAAANQADCgMIAwAAAA==.',
Re='Reach:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Real:BAAANQAECgYICwAAAA==.Realia:BAAANQAECgcICAAAAA==.Reda:BAAANQADCgEIAQAAAA==.Redangus:BAAANQADCgIIAgABNQADCggIDQABAAAAAA==.Reikio:BAAANQADCgIIAgAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAUICwAWADkYAA==.Revoke:BAAANQAECgUJCQAAAA==.',
Ro='Rocknrolln:BAAANQADCgYJBgAAAA==.Roronoa:BAAANQADCgQIBQAAAA==.Roßyn:BAAANQAECgQIDAAAAA==.',
Ru='Rubah:BAAANQAECgYIBgAAAA==.Ruroni:BAAANQAECgUJBwAAAA==.',
Ry='Ryniel:BAAANQADCggJHQAAAA==.',
['Ré']='Rédundant:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.',
['Rì']='Rìzz:BAAANQAECgcJEwAAAA==.',
Sa='Sabrinalee:BAAANQADCgEJAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQAECgIJAgAAAA==.Sannaggi:BAAANQAECgQIBQAAAA==.Sarahnox:BAAANQAECgYJBgAAAA==.Saramoon:BAAANQAECgUJCgAAAA==.Sarayana:BAAANQABCgIIAwAAAA==.Sargent:BAAANQADCgYIDwAAAA==.Saryaa:BAAANQAECgUIBAAAAA==.Sashchi:BAAANQAECgQIBwAAAA==.Sassenach:BAAANQAECgEIAQAAAA==.Saudelber:BAAANQAECgEJAQAAAA==.',
Sc='Schanks:BAAANQAECgUIBwAAAA==.Scrotius:BAAANQABCgQJAwAAAA==.',
Se='Sedaelina:BAAANQADCgYIBgABNQAECggIGAAVAHIPAA==.Sehmet:BAAANQAECgMJAwAAAA==.Seliria:BAAANQAECgYJDQAAAA==.Seoulmate:BAAANQAECgYJEwAAAA==.Sera:BAAANQAECgYJDAAAAA==.',
Sh='Shadowk:BAAANQABCgIIAgAAAA==.Shaye:BAAANQAECgIJAgAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Sherai:BAAANQADCgIJAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shotfoot:BAAANQAECgcJEQAAAA==.Shwang:BAAANQAECgUJBwAAAA==.',
Si='Sihåya:BAAANQADCgIIAgAAAA==.Silbergrad:BAAANQADCggIDgAAAA==.Silentio:BAAANQAECgYIDwAAAA==.Silihunt:BAAANQAECgYIDwAAAA==.Sinofwrath:BAAANQAECgYICQAAAA==.Sinsidious:BAAANQADCggIDgAAAA==.Siwin:BAECNQAFFIEHAAIVAAQKfiNHAgChAQAVAAQKfiNHAgChAQA1AAQKgR8AAxUACQoSJtAAAMIDABUACQoSJtAAAMIDABYAAgrJFWVwAHIAAAAA.',
Sk='Skribb:BAAANQAECgYJDAAAAA==.',
Sl='Slapchóp:BAAANQAECgYJBgAAAA==.',
Sm='Smiley:BAABNQAECoEYAAISAAkKgRSZLQBDAgASAAkKgRSZLQBDAgABNQAECgkKGAASAIEUAA==.Smoko:BAAANQAECgMJBAAAAA==.',
Sn='Sneakyboi:BAAANQAECgYICQAAAA==.Snorlax:BAAANQAECgYJEAAAAA==.Snowsu:BAACNQAFFIENAAMHAAUKXSOCAwCuAQAHAAQKjyOCAwCuAQAIAAIKUR8bBADEAAA1AAQKgSEAAwcACQrLJdEFAG4DAAcACArMJdEFAG4DAAgABwoWHpkIAFcCAAAA.Snowxstorm:BAAANQAECgYJCAAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAAANQAECgQIBwAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAAANQAECgYJCgAAAA==.',
Sp='Splashzone:BAAANQAECgUJBwAAAA==.Splits:BAAANQADCgYIBgAAAA==.',
St='Staqua:BAAANQAECgEJAQAAAA==.Stateomatter:BAAANQAECgUJBgAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgYJEwABAAAAAA==.Summdari:BAAANQAECgUIDwAAAA==.Summrot:BAAANQAECgYJBgAAAA==.Sunfrostt:BAAANQADCggIFAAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAAANQAECgEJAQAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgEIAQAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAAANQAECgIIAgAAAA==.',
Td='Tdogx:BAAANQADCgcICAAAAA==.',
Te='Tekeeladin:BAAANQADCggICgABNQAECggJGwADAP0fAA==.Tekeelà:BAAANQAECgQIBwABNQAECggJGwADAP0fAA==.Tekelemental:BAAANQAECgQICwAAAA==.Tempestra:BAAANQAECgIJAgAAAA==.Tenebria:BAABNQAECoEcAAIXAAkKhSCoAAB3AwAXAAkKhSCoAAB3AwAAAA==.Terrorhungry:BAAANQADCggIIAAAAA==.',
Th='Thalstrasza:BAAANQAECgUIDgAAAA==.The:BAAANQAECgIJAgAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAAANQAECgYIEAAAAA==.Thugrodent:BAAANQAECggJAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tietus:BAAANQAECgEJAQAAAA==.',
Tl='Tlanimass:BAAANQAECgUJCAAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAECgkJJwAHAAIhAA==.',
Ts='Tsu:BAAANQAECgQJBQAAAA==.Tsyubaki:BAAANQAECgQIBAAAAA==.',
Tu='Tulisse:BAAANQADCgYJBgAAAA==.',
Tw='Twerkngherkn:BAAANQAECgQIBAAAAA==.',
Ty='Tybalt:BAAANQAECggIDwAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.',
Ul='Uldric:BAAANQAECgEIAgAAAA==.',
Un='Undeaddude:BAAANQABCgYIBgAAAA==.Unslayable:BAAANQADCggIFQAAAA==.',
Uz='Uzzy:BAAANQADCggJGwAAAA==.',
Va='Valandir:BAAANQAECgMIBQAAAA==.Valyst:BAAANQADCggJGgAAAA==.Varya:BAAANQABCgQIAwAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAABNQAECoEgAAMVAAkKBBT/EABaAgAVAAkKBBT/EABaAgAWAAYKmAWpVwDvAAAAAA==.Verrenth:BAAANQADCgcIDAABNQAECgYICQABAAAAAA==.',
Vi='Viduus:BAAANQADCggIGwAAAA==.Vigol:BAAANQADCgQJBAAAAA==.',
Vm='Vmaoh:BAAANQADCggIEAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQJBgAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECgYICQABAAAAAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgQIBQAAAA==.Warwickk:BAAANQABCgIIAgABNQADCgUIBQABAAAAAA==.',
Wi='Wickedholi:BAAANQADCgcIBwABNQAECgkJJwAHAAIhAA==.Wickedsmaht:BAABNQAECoEnAAMHAAkKAiEuGADXAgAHAAgKhCAuGADXAgAIAAMKwSE4JwAXAQAAAA==.Widowghast:BAAANQAECgUJCwAAAA==.Willowísp:BAABNQAECoEXAAIYAAgKkh+4BADIAgAYAAgKkh+4BADIAgAAAA==.Witerally:BAAANQAECgEJAQAAAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEANQAECgMIBQAAAA==.',
Xa='Xalthea:BAABNQAECoEWAAQKAAkKRgnRKgCRAQAKAAcK4wvRKgCRAQAZAAEKwQiFIAAnAAAOAAcKHABnawASAAAAAA==.Xandapriest:BAAANQADCgYICwABNQAECgkJHgAMACMbAA==.Xanlock:BAAANQADCgUIBwAAAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECgYJEwABAAAAAA==.',
Xp='Xpddevour:BAAANQAECgYIEgAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAABNQAECoEhAAIUAAkK0BrNJQDMAgAUAAkK0BrNJQDMAgAAAA==.',
Ya='Yashoda:BAAANQABCggJCAAAAA==.',
Ye='Yegarmiester:BAAANQAECgEJAQAAAA==.Yenti:BAAANQAECgIJAgAAAA==.',
Yu='Yuexi:BAAANQADCgYIBgABNQAECgYJEwABAAAAAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAAANQAECgQIDwAAAA==.Zamochy:BAAANQAECgUIBQAAAA==.Zap:BAAANQADCgYICgABNQAECgYJEAABAAAAAA==.',
Ze='Zerality:BAAANQAECgIIAgAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAAANQAECgUJCwAAAA==.',
Zo='Zookee:BAAANQAECgYJCwAAAA==.',
Zu='Zulizek:BAAANQAECgQJCwAAAA==.',
Zy='Zynister:BAAANQAECgEJAQABNQAECgYIEQABAAAAAA==.',
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
