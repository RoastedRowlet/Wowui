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

local lookup = {'Unknown-Unknown','Warrior-Arms','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Hunter-BeastMastery','Shaman-Elemental','DeathKnight-Blood','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Warrior-Protection','Paladin-Holy','Mage-Frost','Mage-Fire','Monk-Mistweaver','Evoker-Devastation','Paladin-Retribution','Shaman-Restoration','Warrior-Fury','Druid-Balance','Priest-Holy','Priest-Discipline','Druid-Restoration','DemonHunter-Vengeance','Hunter-Survival','Shaman-Enhancement','Monk-Brewmaster',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aahnna:BAAANQADCggJCAABNQAECgUICgABAAAAAA==.',
Ab='Ababear:BAAANQAECgQJBwAAAA==.',
Ad='Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQADCggIDgAAAA==.',
Al='Alarrius:BAABNQAECoEbAAICAAgKThCwdQDlAQACAAgKThCwdQDlAQAAAA==.Albedö:BAAANQADCgIIAgABNQAECgkJLAADAO0dAA==.Algo:BAAANQAECgIIAgAAAA==.Algrubeley:BAAANQABCgUIBQABNQAECgQIEAABAAAAAA==.Alithirae:BAAANQADCgUIBgAAAA==.Allionys:BAAANQAECgUIBwAAAA==.Aloris:BAAANQAECgUIDAAAAA==.',
Am='Amanises:BAABNQAECoEUAAMEAAYKphpwOgDWAQAEAAYKphpwOgDWAQAFAAIKJgv4cABoAAABNQAECggIDgABAAAAAA==.Amilara:BAAANQAECgEIAQAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Ananaya:BAAANQAECgMIAwAAAA==.Anania:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Andinestiri:BAAANQAECgYICwAAAA==.Andolastrasz:BAAANQAECgQICAAAAA==.Angelic:BAAANQAECgYICQAAAA==.',
Ao='Ao:BAABNQAECoEbAAIGAAgKFCHwCgD4AgAGAAgKFCHwCgD4AgAAAA==.',
Ap='Apotic:BAABNQAECoEaAAIFAAcKOAPNUADpAAAFAAcKOAPNUADpAAAAAA==.Apuntar:BAAANQADCggIDgAAAA==.',
Aq='Aquamaree:BAAANQAECgEIAQAAAA==.Aquilla:BAACNQAFFIEJAAIHAAUKeQlQBwB1AQAHAAUKeQlQBwB1AQA1AAQKgSEAAgcACQo1HhwrAK8CAAcACQo1HhwrAK8CAAAA.',
Ar='Archenea:BAAANQAECgUIBgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAAANQAECgUIEAAAAA==.Arhianrod:BAAANQADCgIIAgAAAA==.Ariisa:BAAANQAECgEIAQAAAA==.Around:BAAANQAECgQICwABNQAECggIGQAIAHsRAA==.Artty:BAEANQAECgQIBAABNQAECggIGQAJAL0lAA==.',
As='Askip:BAAANQADCgQIBgAAAA==.Astrud:BAAANQAECgMIAwAAAA==.Asukka:BAAANQAECgQICAAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAACNQAFFIEMAAIKAAQKtgNbCwD9AAAKAAQKtgNbCwD9AAA1AAQKgSQAAgoACAqOHS0KAOACAAoACAqOHS0KAOACAAAA.Attenborough:BAAANQADCgYJBgAAAA==.',
Au='Audiamer:BAAANQADCgUIBQAAAA==.',
Av='Avesa:BAAANQADCgcIGQAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Az='Azazell:BAAANQADCggIEQAAAA==.Azenea:BAAANQAECgUICgAAAA==.',
Ba='Baculum:BAAANQAECgUIDAAAAA==.Badmoonrisin:BAAANQADCgYJCQAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Bandolero:BAAANQADCggIEAAAAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Beefstewed:BAAANQADCggIDwAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAAANQAECgYICwAAAA==.',
Bi='Bigbutter:BAAANQAECgEIAQAAAA==.Bittybow:BAAANQABCgcICgAAAA==.Bittydrood:BAAANQADCggIGgAAAA==.Bittylexis:BAAANQAECgUIDAAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Bleu:BAAANQADCgEIAQABNQAECgUIDgABAAAAAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAABNQAECoEWAAMLAAgKrBQaJwATAgALAAgK9xEaJwATAgAMAAcKnhNpJgDUAQAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgkKIQANAK4eAA==.Blèu:BAAANQAECgUIDgAAAA==.',
Bo='Boggrog:BAAANQAECgIIAgABNQAECgMIAwABAAAAAQ==.Bokan:BAAANQAECgEIAQAAAA==.Box:BAAANQAECgYIBgAAAA==.',
Br='Braggs:BAAANQADCggIEwAAAA==.Breathe:BAAANQAECgQIBAAAAA==.Brewballs:BAAANQAECgYIEgAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCggIFwAAAA==.Bucket:BAAANQAECgQIBgAAAA==.Bunnicula:BAABNQAECoEYAAQOAAcKaRUmCADDAQAOAAYKYRYmCADDAQAPAAMKSAsg4QCZAAAQAAEKnA+UaQA6AAAAAA==.',
['Bö']='Böömer:BAAANQAECgIIBAAAAA==.',
Ca='Caelphia:BAAANQAECgQIBwAAAA==.Caimage:BAAANQAECgcIEwAAAA==.Cainnaszun:BAAANQADCgMIBAABNQADCggIGwABAAAAAA==.Cainnaszunn:BAAANQADCggIGwAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Caythus:BAACNQAFFIEbAAQQAAcKBSCCAgDkAAAPAAUKKhwNBQDGAQAQAAIKHCaCAgDkAAAOAAEKpiTMAwBtAAA1AAQKgSYABBAACQq5JjwBAHUDABAACQpeJDwBAHUDAA8ACApxJp8IAGQDAA4AAQoXJl8bAGgAAAAA.Caythuz:BAABNQAECoEOAAMQAAcKmiANJAA9AQAPAAYKRyD4fQCNAQAQAAUKGhoNJAA9AQABNQAFFAcIGwAQAAUgAA==.',
Ce='Celeana:BAAANQAECgEIAQAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgYICAAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgIIAgAAAA==.Chakabad:BAAANQADCggJFQAAAA==.Chalgah:BAAANQAECgEIAgAAAA==.Chenahala:BAAANQADCggIHgAAAA==.Chloe:BAAANQADCggICAAAAA==.Chåni:BAABNQAECoEqAAIMAAkK6BjPDwDQAgAMAAkK6BjPDwDQAgAAAA==.',
Ci='Cimerone:BAAANQABCgMIAwAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAAANQAECgYICgAAAA==.Claw:BAAANQAECgcICAABNQAECgkJIQAEALkkAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECgQIBgAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Collette:BAAANQADCgcIBwAAAA==.Conanascus:BAAANQADCgcIDgABNQAECggIGgARAAcQAA==.Corrupteded:BAAANQAECgEIAQAAAA==.',
Cr='Crimsonmana:BAAANQADCgMIAwAAAA==.Crispysock:BAAANQAECgUICwAAAA==.Crowe:BAAANQAECgIIAgAAAA==.',
Cy='Cynderr:BAAANQAECgQICAAAAA==.',
Da='Daisymayhem:BAAANQABCgcICAAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQADCgcIEQAAAA==.Darkisis:BAAANQAECgIIAgAAAA==.Darknara:BAABNQAECoEaAAMJAAgKrBl0KABEAgAJAAgKrBl0KABEAgAEAAMKPBAxiwCMAAAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQAECgIIAgAAAA==.Dasubertakem:BAAANQADCgYIBwAAAA==.Dawni:BAAANQAECgcIEQAAAA==.',
De='Deathjeff:BAAANQAECgcIEAAAAA==.Deathsgates:BAAANQAECgQIBAABNQAECgkJIgARAI4bAA==.',
Di='Didymus:BAAANQADCgUIBQAAAA==.Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgQICAAAAA==.Dinoll:BAAANQAECgQIBAAAAA==.Dirtwhistle:BAABNQAECoEeAAISAAkKLCMeAgB1AwASAAkKLCMeAgB1AwAAAA==.',
Dr='Dragondh:BAABNQAECoEbAAILAAkK+RWUIQBDAgALAAkK+RWUIQBDAgAAAA==.Drazsi:BAAANQAECgUIBgAAAA==.Drosi:BAAANQAECgYIEwAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIJAgAAAA==.',
Ea='Earthesance:BAAANQAECgIIAwAAAA==.',
Eb='Ebeb:BAAANQAECgUICAAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAAANQAECgQJBQAAAA==.Electricfury:BAAANQADCggIFgAAAA==.Ellebasi:BAAANQAECgEIAQAAAA==.Ellebazy:BAAANQAECgUIDQAAAA==.',
Em='Emmri:BAAANQAECgQICAAAAA==.',
En='Enazen:BAAANQAECgUIDAAAAA==.Enlighthyn:BAABNQAECoEaAAITAAkK0R5oFQACAwATAAkK0R5oFQACAwAAAA==.',
Er='Erlas:BAAANQADCggIFwAAAA==.Erui:BAAANQADCggJEAAAAA==.',
Es='Esmeluz:BAAANQADCgMIAwAAAA==.',
Et='Etorion:BAAANQADCgcIBwAAAA==.Etrexxig:BAAANQADCgcJCwAAAA==.',
Ev='Evilrayne:BAABNQAECoEiAAINAAgKkxbzhQA2AgANAAgKkxbzhQA2AgAAAA==.',
Fa='Fanfiction:BAAANQAECgYIDwAAAA==.Fatherfingur:BAAANQADCgMIBAAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Feather:BAAANQAECgUICwAAAA==.Felmonger:BAAANQAECgMIAwAAAA==.Feloak:BAAANQAECgYIDwAAAA==.Feredir:BAAANQAECgEIAQAAAA==.',
Fi='Fires:BAABNQAECoEWAAQUAAcKvBz0EQBEAQANAAYKLhvIrQDcAQAUAAQKJx30EQBEAQAVAAEKrA3gCQA9AAAAAA==.Fistandilius:BAAANQAECgUIBwAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAABNQAECoEaAAMJAAcKfiB1HACZAgAJAAcKAyB1HACZAgAFAAEKoiRXdgBXAAAAAA==.',
Fu='Furryfury:BAABNQAECoEgAAMWAAgK4xqTDQBnAgAWAAgK4xqTDQBnAgAGAAEKDRGRUwAzAAAAAA==.Fusrodah:BAAANQAECgYIEgAAAA==.Fuzzyewok:BAAANQAECgYIEwAAAA==.',
Ga='Gabaghoul:BAABNQAECoEaAAIJAAgKvRekLQAiAgAJAAgKvRekLQAiAgAAAA==.Gameshark:BAAANQAECgUIBwAAAA==.Gawdzirra:BAAANQAECgYICwAAAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAECgcIFwAAAQ==.',
Ge='Geauxaway:BAAANQADCgQIAgAAAA==.George:BAAANQADCggIGQAAAA==.',
Gh='Ghazghküll:BAAANQAECgQIBAAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQADCgUIBQAAAA==.',
Go='Gohibasi:BAAANQAECgEIAQAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAAANQAECgcICQAAAA==.',
Gr='Graceosilver:BAAANQAECgIIAgAAAA==.Gregnor:BAAANQAECgYIEwAAAA==.Gremöry:BAAANQAECgYIDgAAAA==.Grippysock:BAAANQADCgEIAQAAAA==.Grover:BAAANQAECgYIEAAAAA==.Grumpybunbun:BAAANQAECgcIEwAAAA==.Grüm:BAAANQAECgEIAQAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAAANQAECgUJCwAAAA==.',
Ha='Haarl:BAAANQADCgcJBwAAAA==.Hairypotter:BAAANQADCgUIDQABNQADCggJEAABAAAAAA==.Halazzi:BAAANQAECgEIAQAAAA==.Haldar:BAAANQADCggIFAAAAA==.Hallie:BAAANQAECgIIAgAAAA==.Harlu:BAAANQAECgYIDgAAAA==.Hartbroke:BAAANQAECgYIDgAAAA==.Haunter:BAAANQAECgQIBwABNQAECgYIEAABAAAAAA==.Hayeon:BAAANQAECgEIAQAAAA==.',
He='Helbourne:BAAANQAECgUIBwAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Ho='Holybunbun:BAAANQAECgIIAgAAAA==.Holyrollerz:BAAANQADCgYIBgAAAA==.Homeydagreat:BAAANQAECgEIAQAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgQIEwABAAAAAA==.Hunsx:BAAANQAECgQIBAAAAA==.',
Hw='Hwanwok:BAAANQAECgUICQAAAA==.',
['Hâ']='Hânzö:BAAANQADCgMIAwAAAA==.',
Ic='Icemage:BAAANQAECgMIBgAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQAECgEIAQAAAA==.',
Im='Imadragon:BAABNQAECoEbAAIXAAcK2Q/FFgCcAQAXAAcK2Q/FFgCcAQAAAA==.Imbac:BAAANQADCgUIEgAAAA==.Imdeadguy:BAABNQAECoEXAAISAAcKaRxkCwAzAgASAAcKaRxkCwAzAgAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCgcIFwAAAA==.Ironhelmhtr:BAAANQADCgcIGQAAAA==.Ironscythe:BAAANQADCgYJCAAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jace:BAAANQAECgEIAQAAAA==.Jazlee:BAAANQAECgYIDgAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Jezmund:BAAANQAECgQIEAAAAA==.',
Ji='Jinathy:BAABNQAECoEaAAIYAAgK2hBUdQDjAQAYAAgK2hBUdQDjAQAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Jo='Jolyñ:BAAANQAECgEIAQABNQAECgcIBwABAAAAAA==.',
Ju='Juaranir:BAAANQAECgYIEAAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Juicébòx:BAAANQAECgIIAgAAAA==.Justac:BAAANQADCgYJEgABNQAECgUICAABAAAAAA==.Justdrood:BAAANQAECgUICAAAAA==.',
Jw='Jwst:BAAANQABCgYIAgAAAA==.',
['Jà']='Jàß:BAAANQAECgYICgAAAA==.',
['Já']='Jáß:BAAANQAECgcIDgAAAA==.',
['Jä']='Jäb:BAAANQADCgUIBgAAAA==.',
Ka='Kahleah:BAAANQADCgcIBAAAAA==.Kaldonor:BAABNQAECoEaAAIFAAgKvg1kMQCzAQAFAAgKvg1kMQCzAQAAAA==.Kalenia:BAABNQAECoEeAAIZAAgKRiDDGQDZAgAZAAgKRiDDGQDZAgAAAA==.Kalvayre:BAAANQAECgIIBAAAAA==.Kanzoorb:BAABNQAECoEhAAINAAkK+xzCMgAJAwANAAkK+xzCMgAJAwAAAA==.Kareshka:BAAANQAFFAIIAgAAAA==.Karinea:BAEANQAECgUIDAAAAA==.Karpana:BAEANQAECgUIEAAAAA==.Karworg:BAAANQADCggIFQAAAA==.Kashir:BAAANQAECgMIBAAAAA==.Kashira:BAAANQADCggIEgABNQAECgMIBAABAAAAAA==.Kathelee:BAAANQAECgcIDQAAAA==.Kazimirah:BAAANQAECgEIAQAAAA==.Kazrael:BAAANQAECgEIAgAAAA==.',
Ke='Keekat:BAAANQADCggIEAAAAA==.Kevinbeacon:BAEANQAECgYIBwAAAA==.',
Kh='Kharnij:BAAANQADCggIEAAAAA==.Khaíbit:BAAANQADCgYIBgAAAA==.Khonsu:BAAANQAECgYIEgAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.',
Ki='Kiamei:BAAANQAECgEJAQAAAA==.Kikora:BAAANQADCgcIDQAAAA==.Kittykitty:BAABNQAECoEaAAMZAAgK1xtjLQBsAgAZAAgK1xtjLQBsAgAIAAUKrBVHfQBVAQAAAA==.',
Ko='Kolzane:BAECNQAFFIEPAAIHAAUKHiLaAgDuAQAHAAUKHiLaAgDuAQA1AAQKgRwAAgcACQpFJpcFAJwDAAcACQpFJpcFAJwDAAAA.',
Kr='Krezz:BAAANQAECgUIBwAAAA==.',
Ku='Kumojo:BAAANQADCggICAAAAA==.Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAACNQAFFIEIAAIHAAUKawsaBwB7AQAHAAUKawsaBwB7AQA1AAQKgRsAAgcACQrlHPggANwCAAcACQrlHPggANwCAAAA.',
Ky='Kynlyn:BAAANQADCgQIBAAAAA==.Kyth:BAAANQAECgYIEAAAAA==.Kythtok:BAAANQADCgYICAABNQAECgYIEAABAAAAAA==.',
La='Lanx:BAAANQAECgIIAgAAAA==.Laquatas:BAAANQAECgYIDAAAAA==.Laylanduin:BAAANQADCgEIAQABNQAECgcIEAABAAAAAA==.',
Le='Lenash:BAAANQAECgIIAgABNQABCgIIBAABAAAAAA==.',
Li='Lifebloomer:BAAANQAECgEIAQABNQAFFAYIEQAJAL0hAA==.Lightguard:BAAANQAECgcICwAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgQIDAAAAA==.Littlehell:BAAANQAECggICQAAAA==.',
Lo='Lothrik:BAAANQADCggICAAAAA==.',
Lu='Lucaafer:BAAANQADCgYIFwABNQAECggIEgABAAAAAA==.Luda:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.Ludaa:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.Ludahealz:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Lunamoonclaw:BAAANQAECgYJEAAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgQIBgAAAA==.Lyssandria:BAAANQAECgMIAwAAAA==.Lyzoldas:BAAANQAECgYIDAAAAA==.',
['Lá']='Lárry:BAAANQADCgMIAwAAAA==.',
['Lö']='Löwryder:BAAANQAECgIIBAAAAA==.',
Ma='Madness:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Mae:BAAANQAECgcIDgABNQABCgIIAgABAAAAAA==.Maemura:BAAANQAECgEIAQAAAA==.Magdalaiina:BAAANQAECgYIDgAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magîkarp:BAAANQAECgUICwAAAA==.Malchromatus:BAABNQAECoEWAAMXAAYKzgaUHwAXAQAXAAYKzgaUHwAXAQAKAAYKJgV1KwD+AAAAAA==.Marcosio:BAAANQADCggIFAAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAAANQAECggIEQAAAA==.Maylater:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Me='Mearkman:BAAANQAECgQIBgAAAA==.Meatyfajita:BAABNQAECoEXAAITAAgKAibCBwByAwATAAgKAibCBwByAwAAAA==.Meinfurion:BAAANQAECgUIBwAAAA==.Meladie:BAAANQADCgcICQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAABNQAECoEdAAMEAAgK6B+lGQCzAgAEAAgK6B+lGQCzAgAFAAcKXBM6MgCsAQAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECggIHQAEAOgfAA==.Merit:BAAANQADCggICAABNQAECggIFgALAKwUAA==.Merlinthos:BAAANQAECgUICAABNQAECggIGgARAAcQAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAAANQAECgYIEwAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Minecraft:BAABNQAECoEZAAIaAAkK2Rj4BACKAgAaAAkK2Rj4BACKAgAAAA==.Mingyue:BAAANQADCgYICQABNQAECgcIGwAbADUWAA==.Mirajåne:BAABNQAECoEsAAQDAAkK7R2kCQAiAwADAAkK7R2kCQAiAwAcAAMKZg37rACVAAAdAAEKugKDJAAuAAAAAA==.Mishaweha:BAAANQAECgYICwAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mitos:BAAANQADCgQIBwAAAA==.',
Mo='Modar:BAAANQAECgcIDgAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQADCgYJDAAAAA==.',
Mu='Musterd:BAAANQADCgYJDQAAAA==.',
['Må']='Måddløck:BAAANQADCgYIDAAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.',
Ne='Neiidra:BAAANQAECgIIAwAAAA==.Nepheleah:BAABNQAECoEfAAIYAAkKrR9ZHQAhAwAYAAkKrR9ZHQAhAwAAAA==.Nesca:BAAANQAECgUICAAAAA==.Nesmoth:BAAANQAECgIIBAAAAA==.Ness:BAAANQAECgUIDQAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQABCgIIBAAAAA==.Niiborracho:BAAANQAECgYIEAAAAA==.Niiko:BAAANQAECgMIBAAAAA==.',
No='No:BAAANQADCgUJBQABNQAECggIGAACAK8eAA==.Nobullsheep:BAAANQABCggIBgAAAA==.Nommy:BAAANQAECgUICAABNQAECggIHgAHAIAYAA==.Norntrox:BAAANQAECgYICgAAAA==.Nothannah:BAABNQAECoEYAAIeAAgKcg94IgC0AQAeAAgKcg94IgC0AQAAAA==.',
Ns='Nsshaman:BAAANQADCgUIBQAAAA==.',
Od='Odyssey:BAAANQADCggJCAABNQAECggIFgALAKwUAA==.',
Og='Ogreatsxtra:BAAANQAECgEIAQAAAA==.',
Ol='Ol:BAAANQAECgUIBQAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgEIAgABNQAECgYIEAABAAAAAA==.',
Or='Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgUIBwAAAA==.',
Oz='Ozhawk:BAAANQAECgEIAgAAAA==.',
Pa='Padreburrito:BAEANQADCgYICwABNQAFFAUICgAeALIiAA==.Pakno:BAAANQAECgUIBQAAAA==.Pamely:BAABNQAECoEmAAIYAAkKihtBLADbAgAYAAkKihtBLADbAgAAAA==.',
Ph='Pharmit:BAABNQAECoEWAAMOAAYKGSU4AwCQAgAOAAYK4yQ4AwCQAgAPAAEKXSGV9ABhAAAAAA==.Phiarce:BAAANQAECgEIAQAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Porterhouse:BAAANQADCgMIAwAAAA==.Potatoad:BAAANQAECgIIBAAAAA==.',
Pw='Pwags:BAAANQADCgUJBQAAAA==.',
Py='Pyragosa:BAAANQAECgYIDwAAAA==.Pyramys:BAAANQABCgQIAwABNQAECgUIDAABAAAAAA==.',
['Pà']='Pàt:BAAANQAECgcIDgAAAA==.',
['Pâ']='Pândâmoníum:BAAANQAECgIIBAAAAA==.',
['På']='Påimon:BAAANQADCggJEAAAAA==.',
Qu='Quintin:BAEANQADCgIJAgABNQAECggIGQAJAL0lAA==.',
Ra='Racavis:BAAANQADCgMIAwAAAA==.',
Re='Reach:BAAANQADCgYICgABNQAECggIGQAIAHsRAA==.Real:BAAANQAECgYIEQAAAA==.Realia:BAAANQAECgcICAAAAA==.Reda:BAAANQADCgIIAwAAAA==.Redangus:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Reikio:BAAANQADCgIIAgAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAUIEAAbAN0dAA==.Revoke:BAAANQAECgUJCQAAAA==.',
Ro='Rocknrolln:BAAANQADCgYJBgAAAA==.Rokubora:BAABNQAECoEYAAIIAAgKGxaIOwA/AgAIAAgKGxaIOwA/AgAAAA==.Rongyi:BAAANQAECgEIAQABNQAECgcIGwAbADUWAA==.Roronoa:BAAANQADCgYIBwAAAA==.Roßyn:BAAANQAECgQIDQAAAA==.',
Ru='Rubah:BAAANQAECgYIDAAAAA==.Ruroni:BAAANQAECgUIDAAAAA==.',
Ry='Ryniel:BAAANQADCggJHQAAAA==.',
['Ré']='Rédundant:BAAANQAECgQIBQABNQAECggIGQAIAHsRAA==.',
['Rì']='Rìzz:BAABNQAECoEeAAIIAAgKNR9MIQDOAgAIAAgKNR9MIQDOAgAAAA==.',
Sa='Sabrinalee:BAAANQADCgEJAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQAECgIIAwABNQAECgMIAwABAAAAAA==.Sannaggi:BAAANQAECgYICwAAAA==.Sarahnox:BAAANQAECgcIDQAAAA==.Saramoon:BAAANQAECgYIEAAAAA==.Sarayana:BAAANQABCgIIAwAAAA==.Sargent:BAAANQADCggIEQAAAA==.Saryaa:BAAANQAECgYICgAAAA==.Sashchi:BAAANQAECgQICwAAAA==.Sassenach:BAAANQAECgEIAQAAAA==.Saudelber:BAAANQAECgIIAwAAAA==.',
Sc='Schanks:BAAANQAECgYICQAAAA==.Scrotius:BAAANQABCgQIBQAAAA==.',
Se='Sedaelina:BAAANQADCgYIBgABNQAECggIGAAeAHIPAA==.Sehmet:BAAANQAECgMIBAAAAA==.Seliria:BAAANQAECgYIEwAAAA==.Seoulmate:BAABNQAECoEbAAIbAAcKNRYZOQDXAQAbAAcKNRYZOQDXAQAAAA==.Sera:BAAANQAECgYIEgAAAA==.',
Sh='Shadowk:BAAANQABCgIIAgAAAA==.Shaye:BAAANQAECgIIBAAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Sherai:BAAANQADCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECgcIDgABAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shotfoot:BAABNQAECoEaAAIHAAgKShgbPABwAgAHAAgKShgbPABwAgAAAA==.Shwang:BAAANQAECgUIDAAAAA==.',
Si='Sihåya:BAAANQAECgYIBgAAAA==.Silbergrad:BAAANQADCggIDgAAAA==.Silentio:BAABNQAECoEaAAIRAAgKBxBmIwAKAgARAAgKBxBmIwAKAgAAAA==.Silihunt:BAABNQAECoEaAAMLAAgKuA38LgDSAQALAAgK8Az8LgDSAQAMAAQKyw1iQADxAAAAAA==.Sinofwrath:BAAANQAECgcICwAAAA==.Sinsidious:BAAANQADCggIDgAAAA==.Siwin:BAECNQAFFIEKAAIeAAUKsiIoAgD0AQAeAAUKsiIoAgD0AQA1AAQKgSEAAx4ACQoSJpYBAK4DAB4ACQoSJpYBAK4DABsAAgrJFV9/AHAAAAAA.',
Sk='Skribb:BAAANQAECgYIEwAAAA==.',
Sl='Slapchóp:BAAANQAECgYIDAAAAA==.',
Sm='Smiley:BAABNQAECoEaAAIcAAkK+xR8OwA0AgAcAAkK+xR8OwA0AgABNQAECgkKGgAcAPsUAA==.Smoko:BAAANQAECgMJBAAAAA==.',
Sn='Sneakyboi:BAAANQAECgcIDgAAAA==.Snorlax:BAAANQAECgYIEAAAAA==.Snowsu:BAACNQAFFIETAAMPAAYK1SLeAgALAgAPAAUK4iLeAgALAgAQAAIKUCBhBQDAAAA1AAQKgSYAAw8ACQoYJpcHAG4DAA8ACAoiJpcHAG4DABAABwoVHiIJAFgCAAAA.Snowxstorm:BAAANQAECgYIDgAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAAANQAECgUIDAAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAAANQAECgYIEAAAAA==.',
Sp='Splashzone:BAAANQAECgUIDAAAAA==.Splits:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
St='Staqua:BAAANQAECgEIAgAAAA==.Stateomatter:BAAANQAECgYIDAAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgcIGwAbADUWAA==.Summdari:BAABNQAECoEYAAIfAAcK8xbZCQDmAQAfAAcK8xbZCQDmAQAAAA==.Summrot:BAAANQAECgYIDAAAAA==.Sunfrostt:BAAANQADCggIFAAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAAANQAECgEIAgAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgUIBgAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAAANQAECgUIBwAAAA==.',
Td='Tdogx:BAAANQAECgQIBAAAAA==.',
Te='Teal:BAAANQAECgEIAQAAAA==.Tekeeladin:BAAANQADCggICgABNQAECgkJJAAHAP8eAA==.Tekeelà:BAAANQAECgUIDAABNQAECgkJJAAHAP8eAA==.Tekelemental:BAAANQAECgQIDAAAAA==.Tempestra:BAAANQAECgUIBwAAAA==.Tenebria:BAABNQAECoEgAAIgAAkKhSAoAQBUAwAgAAkKhSAoAQBUAwAAAA==.Terrorhungry:BAAANQAECgMIAwAAAA==.',
Th='Thalstrasza:BAAANQAECgUIEQAAAA==.The:BAAANQAECgIIBAAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAAANQAECgYIEAAAAA==.Thugrodent:BAAANQAECggJAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tietus:BAAANQAECgIIAwAAAA==.',
Tl='Tlanimass:BAAANQAECgYIDgAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAFFAUICAAQAIIRAA==.',
Ts='Tsu:BAAANQAECgUICgAAAA==.Tsyubaki:BAAANQAECgQIBAAAAA==.',
Tu='Tulisse:BAAANQADCgYICgAAAA==.',
Tw='Twerkngherkn:BAAANQAECgQIBwAAAA==.',
Ty='Tybalt:BAABNQAECoEWAAIhAAkKYRjnCAC4AgAhAAkKYRjnCAC4AgAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.Tyrandaz:BAAANQAECgQIBAAAAA==.',
Ul='Uldric:BAAANQAECgUIBwAAAA==.',
Un='Undeaddude:BAAANQABCgYIBgAAAA==.Unslayable:BAAANQADCggIFQAAAA==.',
Uz='Uzzy:BAAANQADCggIHwAAAA==.',
Va='Valandir:BAAANQAECgQICQAAAA==.Valyst:BAAANQADCggIIgAAAA==.Varya:BAAANQABCgQIBQAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAACNQAFFIEGAAIeAAMKox7VBgATAQAeAAMKox7VBgATAQA1AAQKgSMAAx4ACQqLFJETAGsCAB4ACQqLFJETAGsCABsABgqYBZFkAOUAAAAA.',
Vi='Viduus:BAAANQADCggIGwAAAA==.Vigol:BAAANQADCgQJBAAAAA==.Vivec:BAAANQADCgMIAwAAAA==.',
Vm='Vmaoh:BAAANQADCggIEAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQJBgAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECgcIEAABAAAAAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgUIBgAAAA==.Warwickk:BAAANQABCgIIAgABNQADCgUIBQABAAAAAA==.',
Wi='Wickedholi:BAAANQADCgcIBwABNQAFFAUICAAQAIIRAA==.Wickedsmaht:BAACNQAFFIEIAAMQAAUKghEWCgCqAAAPAAMKTRHEFADqAAAQAAIK0BEWCgCqAAA1AAQKgSoAAw8ACQpwIosfANMCAA8ACAogIosfANMCABAAAwrBISMrAA8BAAAA.Widowghast:BAAANQAECgYIDwAAAA==.Willowísp:BAABNQAECoEeAAIiAAgKkh/VBQC9AgAiAAgKkh/VBQC9AgAAAA==.Witerally:BAAANQAECgEIAgAAAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEANQAECgQICQAAAA==.',
Xa='Xalthea:BAABNQAECoEbAAQMAAkKWAk5MAB+AQAMAAcK+ws5MAB+AQAfAAEKwQgoKAAnAAALAAcKHAApfwASAAAAAA==.Xandapriest:BAAANQADCgYICwABNQAECgkJIgARAI4bAA==.Xanlock:BAAANQADCgUIBwAAAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECgcIGwAbADUWAA==.',
Xp='Xpddevour:BAABNQAECoEcAAILAAgKEhbBJAAnAgALAAgKEhbBJAAnAgAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAABNQAECoEjAAIYAAkKXhzyLQDUAgAYAAkKXhzyLQDUAgAAAA==.',
Xu='Xuxo:BAAANQADCgEIAQAAAA==.',
Ya='Yashoda:BAAANQABCggJCAAAAA==.',
Ye='Yegarmiester:BAAANQAECgIIAwAAAA==.Yenti:BAAANQAECgMIBQAAAA==.',
Yu='Yuexi:BAAANQADCgYIBgABNQAECgcIGwAbADUWAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAAANQAECgQIEwAAAA==.Zamochy:BAAANQAECgUIBQAAAA==.Zap:BAAANQADCgYICgABNQAECgYIEAABAAAAAA==.',
Ze='Zerality:BAAANQAECgIIAgAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAAANQAECgYIEQAAAA==.',
Zo='Zoltan:BAAANQADCgMIAwAAAA==.Zookee:BAAANQAECgYIEAAAAA==.',
Zu='Zulizek:BAAANQAECgUIEQAAAA==.',
Zy='Zynister:BAAANQAECgcICQAAAA==.',
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
