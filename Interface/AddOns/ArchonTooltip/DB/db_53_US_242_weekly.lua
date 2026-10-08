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

local lookup = {'Unknown-Unknown','Warrior-Arms','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Hunter-BeastMastery','Paladin-Holy','Evoker-Preservation','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','DeathKnight-Blood','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Paladin-Retribution','Priest-Holy','DemonHunter-Vengeance','Mage-Frost','Mage-Fire','Druid-Feral','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Warrior-Fury','Shaman-Restoration','Paladin-Protection','Priest-Shadow','Priest-Discipline','Hunter-Survival','Shaman-Enhancement','Monk-Brewmaster',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aahnna:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.',
Ab='Ababear:BAAANQAECgQIBwAAAA==.',
Ad='Adeki:BAAANQADCgYIBgAAAA==.Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQADCggIDgAAAA==.',
Al='Alarrius:BAABNQAECoEjAAICAAgKMRJqfgD8AQACAAgKMRJqfgD8AQAAAA==.Albedö:BAAANQADCgIIAgABNQAECgkJJQADALIZAA==.Algo:BAAANQAECgIIAgAAAA==.Algrubeley:BAAANQABCgUIBQABNQAECgQIEAABAAAAAA==.Alithirae:BAAANQADCgUIBgAAAA==.Allionys:BAAANQAECgUICgAAAA==.Aloris:BAAANQAECgUIDgAAAA==.',
Am='Amanises:BAABNQAECoEaAAMEAAYKSB4pPgABAgAEAAYKSB4pPgABAgAFAAIKJgtAgABlAAABNQAECggIEgABAAAAAA==.Amilara:BAAANQAECgEIAQAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Ananaya:BAAANQAECgMIBgAAAA==.Anania:BAAANQAECgIIAwABNQAECgMIBgABAAAAAA==.Andinestiri:BAAANQAECgYIEQAAAA==.Andolastrasz:BAAANQAECgQICAAAAA==.Angelic:BAAANQAECgYIDQAAAA==.',
Ao='Ao:BAABNQAECoEiAAIGAAgKFCEUDgDiAgAGAAgKFCEUDgDiAgAAAA==.',
Ap='Apotic:BAABNQAECoEhAAIFAAcKeQPUWQDyAAAFAAcKeQPUWQDyAAAAAA==.Apuntar:BAAANQADCggIDgAAAA==.',
Aq='Aquamaree:BAAANQAECgEIAQAAAA==.Aquilla:BAACNQAFFIELAAIHAAYK8wgTBgDHAQAHAAYK8wgTBgDHAQA1AAQKgSMAAgcACQqtHuMzAK4CAAcACQqtHuMzAK4CAAAA.',
Ar='Archenea:BAAANQAECgUIBgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAABNQAECoEXAAIIAAcK9gQGlwAxAQAIAAcK9gQGlwAxAQAAAA==.Arhianrod:BAAANQADCggICgAAAA==.Ariisa:BAAANQAECgEIAQAAAA==.Around:BAAANQAECgYIEAAAAA==.Artty:BAEANQAECgQIBAABNQAECggIHAACAAUeAA==.',
As='Askip:BAAANQADCgQICgAAAA==.Astrud:BAAANQAECgMIBgAAAA==.Asukka:BAAANQAECgUIDwAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAACNQAFFIEPAAIJAAUKyQQcCwBDAQAJAAUKyQQcCwBDAQA1AAQKgSsAAgkACQpoHqwFAEQDAAkACQpoHqwFAEQDAAAA.Attenborough:BAAANQADCgYJBgAAAA==.',
Au='Audiamer:BAAANQADCgUIBQABNQAECgcIEwABAAAAAA==.',
Av='Avesa:BAAANQADCgcIJAAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Ay='Ayyahuasca:BAAANQABCgIIAgABNQAECgUICgABAAAAAA==.',
Az='Azazell:BAAANQADCggIEQAAAA==.Azenea:BAAANQAECgYIEAAAAA==.',
Ba='Baculum:BAAANQAECgUIDgAAAA==.Badmoonrisin:BAAANQADCgYJCQAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Bandolero:BAAANQADCggIEAAAAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Beefstewed:BAAANQADCggIDwAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgQIBQABAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAAANQAECgcIDAAAAA==.Ben:BAAANQAECggICAAAAQ==.',
Bi='Bigbutter:BAAANQAECgMIBAAAAA==.Bittybow:BAAANQABCgcICgAAAA==.Bittydrood:BAAANQAECgEIAQAAAA==.Bittylexis:BAAANQAECgUIDgAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blarcedeliu:BAAANQADCggICAABNQAECgUIDgABAAAAAA==.Bleu:BAAANQADCgEIAQABNQAECggIGAAKAGUQAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAABNQAECoEdAAMLAAgKNRYHKwAeAgALAAgKIxUHKwAeAgAMAAcKnhM8KwDHAQAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgkKJAANAJIfAA==.Blèu:BAABNQAECoEYAAIKAAgKZRDuGADBAQAKAAgKZRDuGADBAQAAAA==.',
Bo='Boggrog:BAAANQAECgMIBAAAAQ==.Bokan:BAAANQAECgIIAgAAAA==.Boneappetit:BAAANQADCgYIBgABNQAECggIIAADAOsVAA==.Box:BAAANQAECgcIBwAAAA==.',
Br='Braggs:BAAANQAECgEIAQAAAA==.Breathe:BAAANQAECgQIBAAAAA==.Brewballs:BAABNQAECoEZAAIKAAcKAwqhIwA4AQAKAAcKAwqhIwA4AQAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCggIHgAAAA==.Bucket:BAAANQAECgQICAAAAA==.Bunnicula:BAABNQAECoEfAAQOAAgKYRnvBQA2AgAOAAcKOxrvBQA2AgAPAAMKSAue/ACaAAAQAAEKbBNAagBBAAAAAA==.',
['Bö']='Böömer:BAAANQAECgIIBAAAAA==.',
Ca='Caelphia:BAAANQAECgUIDAAAAA==.Caimage:BAAANQAECgcIEwAAAA==.Cainnaszun:BAAANQAECgEIAQAAAA==.Cainnaszunn:BAAANQADCggIGwABNQAECgEIAQABAAAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Catara:BAAANQAECgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Caythus:BAACNQAFFIEiAAQPAAcKhSGCAgBBAgAPAAYKQh+CAgBBAgAQAAIKJibxAgDiAAAOAAEKpiQ3BQBrAAA1AAQKgSkABBAACQq5JoEBAGgDABAACQpeJIEBAGgDAA8ACApxJsMLAFsDAA4AAQoXJsoeAGcAAAAA.Caythuz:BAABNQAECoEOAAMQAAcKmiCNJgA3AQAPAAYKRyBTlQCBAQAQAAUKGhqNJgA3AQABNQAFFAcIIgAPAIUhAA==.',
Ce='Celeana:BAAANQAECgEIAQAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgYICAAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgIIAgAAAA==.Chakabad:BAAANQAECgEIAQAAAA==.Chalgah:BAAANQAECgIIBAAAAA==.Chenahala:BAAANQAECgEIAQAAAA==.Chloe:BAAANQADCggICAAAAA==.Chåni:BAABNQAECoEyAAIMAAkKXhr1DQD5AgAMAAkKXhr1DQD5AgAAAA==.',
Ci='Cimerone:BAAANQABCgYICQAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAAANQAECgYIEAAAAA==.Claw:BAAANQAECgcICQABNQAFFAUICQAEAEMTAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECgQICAAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Collette:BAAANQADCggICQAAAA==.Conanascus:BAAANQADCgcIDgABNQAECggIIgARABAQAA==.Confessorr:BAAANQADCgYIBQABNQAECgUICgABAAAAAA==.Corrupteded:BAAANQAECgEIAQAAAA==.',
Cr='Crimsonmana:BAAANQADCgMIAwAAAA==.Crispysock:BAAANQAECgUIDQAAAA==.Crowe:BAAANQAECgMIBAAAAA==.',
Cy='Cynderr:BAAANQAECgYIDgAAAA==.',
Da='Daisymayhem:BAAANQABCgcICAAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQADCggIGQAAAA==.Darkisis:BAAANQAECgUIBwAAAA==.Darknara:BAABNQAECoEhAAMSAAgKjxw3JQB3AgASAAgKjxw3JQB3AgAEAAMKPBCXowCLAAAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQAECgMIBAAAAA==.Dasubertakem:BAAANQADCgYIBwAAAA==.Dawni:BAABNQAECoEVAAQJAAcK1A7jLgADAQAJAAUKJwvjLgADAQATAAIKdhAlLwB6AAAUAAEKiASXIQAsAAAAAA==.',
Dd='Ddz:BAAANQADCgUIBQAAAA==.',
De='Deathjeff:BAAANQAFFAEIAQAAAA==.Deathsgates:BAAANQAECgQIBAABNQAECgkJKgARAHYhAA==.Detala:BAAANQADCgYIBgAAAA==.',
Di='Didymus:BAAANQADCgUIBQAAAA==.Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgUIDQAAAA==.Dinoll:BAAANQAECgQIBgAAAA==.Dirtwhistle:BAABNQAECoEmAAIVAAkKViSYAQClAwAVAAkKViSYAQClAwAAAA==.',
Dr='Dragondh:BAABNQAECoEfAAILAAkK8BlBIwBbAgALAAkK8BlBIwBbAgAAAA==.Dranlu:BAAANQADCgYIBgAAAA==.Drazsi:BAAANQAECgUICwAAAA==.Drosi:BAABNQAECoEaAAIWAAcKmRGQnwCrAQAWAAcKmRGQnwCrAQAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIJAgAAAA==.',
['Då']='Dåmmn:BAAANQAECgEIAQAAAA==.',
Ea='Earthesance:BAAANQAECgIIAwAAAA==.',
Eb='Ebeb:BAAANQAECgUICgAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAAANQAECgYIEAAAAA==.Electricfury:BAAANQADCggIFgAAAA==.Ellebasi:BAAANQAECgEIAQAAAA==.Ellebazy:BAAANQAECgYIEwAAAA==.',
Em='Emmri:BAAANQAECgQIDAAAAA==.',
En='Enazen:BAAANQAECgUIDgAAAA==.Enlighthyn:BAABNQAECoEaAAIIAAkK0R6mGgD4AgAIAAkK0R6mGgD4AgABNQAECggIFwAXAEESAA==.',
Er='Erlas:BAAANQAECgMIAwAAAA==.Erui:BAAANQAECgEIAQAAAA==.',
Es='Esmeluz:BAAANQADCgMIAwAAAA==.',
Et='Etorion:BAAANQADCggIDQAAAA==.Etrexxig:BAAANQADCgcJCwAAAA==.',
Ev='Evilrayne:BAABNQAECoEqAAINAAgKpRdnjQBJAgANAAgKpRdnjQBJAgAAAA==.',
Fa='Fanfiction:BAAANQAECgYIDwAAAA==.Fatherfingur:BAAANQADCgMIBAAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Feather:BAAANQAECgYIEQAAAA==.Felmonger:BAAANQAECgMIAwAAAA==.Feloak:BAABNQAECoEWAAIYAAcK1QsqEwBIAQAYAAcK1QsqEwBIAQAAAA==.Feredir:BAAANQAECgEIAQAAAA==.',
Fi='Fires:BAABNQAECoEdAAQNAAcKhB8adAB/AgANAAcKMh8adAB/AgAZAAQKJx2EFQAxAQAaAAEKrA2mCwA4AAAAAA==.Fistandilius:BAAANQAECgUIDAAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAABNQAECoEhAAMSAAgKMCMMEAAaAwASAAgKxCIMEAAaAwAFAAEKoiSthQBVAAAAAA==.',
Fu='Furryfury:BAABNQAECoEpAAMKAAkKuxnODACUAgAKAAkKuxnODACUAgAGAAEKDRH5XgAyAAAAAA==.Fusrodah:BAABNQAECoEfAAMJAAcKZRhGGwD2AQAJAAcKZRhGGwD2AQATAAEK5hdSNQBCAAAAAA==.Fuzzyewok:BAABNQAECoEaAAIIAAcKgx5jNwBqAgAIAAcKgx5jNwBqAgAAAA==.',
Ga='Gabaghoul:BAABNQAECoEiAAISAAgK3xnXLQBCAgASAAgK3xnXLQBCAgAAAA==.Gameshark:BAAANQAECgYIDQAAAA==.Gawdzirra:BAAANQAECgcIDAAAAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAECgcIHgAAAQ==.',
Ge='Geauxaway:BAAANQADCgQIAgAAAA==.George:BAAANQADCggIGQAAAA==.',
Gh='Ghazghküll:BAAANQAECgQIBAAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQADCgYICwAAAA==.',
Go='Gohibasi:BAAANQAECgEIAQAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAAANQAECggIDgAAAA==.',
Gr='Graceosilver:BAAANQAECgIIBAAAAA==.Gregnor:BAABNQAECoEaAAUbAAcKaxNWDwDfAQAbAAcKaxNWDwDfAQADAAYKHQinYQAeAQAcAAQKMAnENwCgAAAdAAMKuAPhWABwAAAAAA==.Gremöry:BAAANQAECgYIDgAAAA==.Grippysock:BAAANQADCgYIBgAAAA==.Grover:BAABNQAECoEZAAIWAAgKwhWKdwAOAgAWAAgKwhWKdwAOAgAAAA==.Grumpybunbun:BAABNQAECoEbAAIXAAgKPxE0WwDgAQAXAAgKPxE0WwDgAQAAAA==.Grüm:BAAANQAECgEIAQAAAA==.',
Gu='Guldangraham:BAAANQAECggIAgABNQAECggIBgABAAAAAA==.Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAAANQAECgYIEAAAAA==.',
Ha='Haarl:BAAANQADCgcJBwAAAA==.Hairypotter:BAAANQADCgUIDQABNQAECgEIAQABAAAAAA==.Halazzi:BAAANQAECgEIAgAAAA==.Haldar:BAAANQAECgQIBQAAAA==.Hallie:BAAANQAECgIIBAAAAA==.Harlu:BAABNQAECoEUAAIeAAYKKQaeogAgAQAeAAYKKQaeogAgAQAAAA==.Hartbroke:BAABNQAECoEUAAIWAAYKURpUkQDNAQAWAAYKURpUkQDNAQAAAA==.Haunter:BAAANQAECgQICwABNQAECgcIEwABAAAAAA==.Hayeon:BAAANQAECgEIAQAAAA==.',
He='Helbourne:BAAANQAECgUIDAAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Ho='Holybunbun:BAAANQAECgIIAwAAAA==.Holyrollerz:BAAANQADCgYIBgAAAA==.Homeydagreat:BAAANQAECgEIAQAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgQIFQAfAKgaAA==.Hunsx:BAAANQAECgUICAAAAA==.',
Hw='Hwanwok:BAAANQAECgUIDgAAAA==.',
['Hâ']='Hânzö:BAAANQADCgMIAwAAAA==.',
Ic='Icemage:BAAANQAECgMIBgAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQAECgEIAQAAAA==.',
Im='Imadragon:BAABNQAECoEcAAITAAgKSg6IFgDCAQATAAgKSg6IFgDCAQAAAA==.Imbac:BAAANQADCgUIFwAAAA==.Imdeadguy:BAABNQAECoEcAAIVAAgKqRzMCQCAAgAVAAgKqRzMCQCAAgAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCgcIFwAAAA==.Ironhelmhtr:BAAANQADCgcIGQAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jaayk:BAAANQAECgcIBwAAAA==.Jace:BAAANQAECgEIAQAAAA==.Jazlee:BAABNQAECoEUAAIVAAYKrRxyEQDhAQAVAAYKrRxyEQDhAQAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Jefflock:BAAANQADCgEIAQABNQAECgUIDgABAAAAAA==.Jezmund:BAAANQAECgQIEwAAAA==.',
Ji='Jinathy:BAABNQAECoEcAAIWAAgKuhHUigDdAQAWAAgKuhHUigDdAQAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Jo='Jolyñ:BAAANQAECgYIBwABNQAECgcIDgABAAAAAA==.',
Ju='Juaranir:BAABNQAECoEWAAIcAAYKcRKPIQBGAQAcAAYKcRKPIQBGAQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Juicébòx:BAAANQAECgIIAgAAAA==.Justac:BAAANQADCgYJEgABNQAECgUICAABAAAAAA==.Justdrood:BAAANQAECgUICAAAAA==.',
Jw='Jwst:BAAANQAECgMIAwAAAA==.',
['Jà']='Jàß:BAAANQAECgYIDAAAAA==.',
['Já']='Jáß:BAAANQAECggIEQAAAA==.',
['Jä']='Jäb:BAAANQAECgIIAgAAAA==.',
Ka='Kahleah:BAAANQADCgcIBAAAAA==.Kaldonor:BAABNQAECoEiAAIFAAgKIxEVMgDdAQAFAAgKIxEVMgDdAQAAAA==.Kalenia:BAABNQAECoEkAAIgAAgKRiAcIADLAgAgAAgKRiAcIADLAgAAAA==.Kalvayre:BAAANQAECgMIBwAAAA==.Kanzoorb:BAABNQAECoEiAAINAAkKXR1rQQDzAgANAAkKXR1rQQDzAgAAAA==.Kareshka:BAAANQAFFAIIAgAAAA==.Karinea:BAEANQAECgUIDgAAAA==.Karpana:BAEBNQAECoEaAAMWAAYKlxhuzgBEAQAWAAYKDxBuzgBEAQAhAAMK4hu2QQDFAAAAAA==.Karworg:BAAANQADCggIFQAAAA==.Kashir:BAAANQAECgMIBgAAAA==.Kashira:BAAANQADCggIEgABNQAECgMIBgABAAAAAA==.Kathelee:BAAANQAECgcIDQAAAA==.Kazimirah:BAAANQAECgEIAQAAAA==.Kazrael:BAAANQAECgIIBAAAAA==.',
Ke='Keekat:BAAANQADCggIGAAAAA==.Kevinbeacon:BAEANQAECgYIDAAAAA==.',
Kh='Kharnij:BAAANQAECgIIAgAAAA==.Khaíbit:BAAANQADCgYIBgAAAA==.Khonsu:BAABNQAECoEZAAQPAAcKVBL5jwCPAQAPAAYKDxT5jwCPAQAQAAEKSBLcawA/AAAOAAEK9QeNKAA9AAAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.',
Ki='Kiamei:BAAANQAECgEJAQAAAA==.Kikora:BAAANQADCgcIDQAAAA==.Kittykitty:BAABNQAECoEhAAMgAAgKpx6AIgC/AgAgAAgKpx6AIgC/AgAeAAUKrBVikQBIAQAAAA==.',
Ko='Kolzane:BAECNQAFFIEQAAIHAAYK6iJtAQBYAgAHAAYK6iJtAQBYAgA1AAQKgR4AAgcACQpFJjoJAIQDAAcACQpFJjoJAIQDAAAA.',
Kr='Krezz:BAAANQAECgUIDAAAAA==.',
Ku='Kumojo:BAAANQADCggICAAAAA==.Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAACNQAFFIEMAAIHAAUKmQs3CgB5AQAHAAUKmQs3CgB5AQA1AAQKgR4AAgcACQokHREkAOkCAAcACQokHREkAOkCAAAA.',
Ky='Kynlyn:BAAANQADCgQIBAAAAA==.Kyth:BAABNQAECoEYAAMhAAcKJxrOGAAFAgAhAAcKJxrOGAAFAgAWAAEKugwMegExAAAAAA==.Kythlock:BAAANQADCgYIBQABNQAECgcIGAAhACcaAA==.Kythtok:BAAANQADCgYICAABNQAECgcIGAAhACcaAA==.',
La='Lanx:BAAANQAECgIIAgAAAA==.Laquatas:BAAANQAECgYIEgAAAA==.Laylanduin:BAAANQADCgEIAQABNQAFFAEIAQABAAAAAA==.',
Le='Lenash:BAAANQAECgIIAgABNQABCgIIBAABAAAAAA==.',
Li='Lifebloomer:BAAANQAECgEIAQABNQAFFAYIFwASALckAA==.Lightguard:BAAANQAECgcIEgAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgUIEAAAAA==.Littlehell:BAAANQAECggICQAAAA==.',
Lo='Lothrik:BAAANQAECgUIBQAAAA==.',
Lu='Lucaafer:BAAANQADCgYIFwABNQAECgkJFgALAGgTAA==.Luda:BAAANQAECgQICAABNQAECgcIDAABAAAAAA==.Ludaa:BAAANQAECgQIBwABNQAECgcIDAABAAAAAA==.Ludahealz:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Lunamoonclaw:BAAANQAECgYJEAAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgQIBgAAAA==.Lyssandria:BAAANQAECgUIBgAAAA==.Lyzoldas:BAAANQAECgcIEwAAAA==.',
['Lá']='Lárry:BAAANQADCgQIBAAAAA==.',
['Lö']='Löwryder:BAAANQAECgIIBgAAAA==.',
Ma='Madness:BAAANQADCgYIBwABNQAECgYIDwABAAAAAA==.Mae:BAAANQAECgcIDwABNQABCgIIAgABAAAAAA==.Maemura:BAAANQAECgEIAQAAAA==.Magdalaiina:BAABNQAECoEVAAIIAAYK/x6BSQAiAgAIAAYK/x6BSQAiAgAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magusman:BAAANQAECgUIBQABNQAECggIIQASADAjAA==.Magîkarp:BAAANQAECgUIDQAAAA==.Malchromatus:BAABNQAECoEdAAMJAAgKAglkIwCKAQAJAAgKAglkIwCKAQATAAYKzgbGIgASAQAAAA==.Marcosio:BAAANQAECgIIAgAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAAANQAECggIEwAAAA==.Maylater:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Me='Mearkman:BAAANQAECgQICAAAAA==.Meatyfajita:BAABNQAECoEdAAIIAAgKAibnCQBsAwAIAAgKAibnCQBsAwAAAA==.Meinfurion:BAAANQAECgUIDAAAAA==.Meladie:BAAANQADCgcICQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAABNQAECoEjAAMEAAgKwCEdHADHAgAEAAgKwCEdHADHAgAFAAcKXBNPOwChAQAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECggIIwAEAMAhAA==.Merit:BAAANQADCggIEAABNQAECggIHQALADUWAA==.Merlinthos:BAAANQAECgYIDgABNQAECggIIgARABAQAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAABNQAECoEaAAMNAAcKwyD0cgCCAgANAAcKSh/0cgCCAgAZAAMK5hxoHADiAAAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Minecraft:BAABNQAECoEbAAIfAAkK2hhmBgB+AgAfAAkK2hhmBgB+AgAAAA==.Mingyue:BAAANQAECgQIBAABNQAECggIIAADAOsVAA==.Mirajåne:BAABNQAECoEzAAQiAAkKAR6KDAALAwAiAAkKAR6KDAALAwAXAAUKshHFjwAsAQAjAAEKugIoKQAsAAABNQAECgkJJQADALIZAA==.Mishaweha:BAAANQAECgYIEQAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mitos:BAAANQADCgQICQAAAA==.',
Mo='Modar:BAABNQAECoEbAAMgAAkKHQ9UUgDwAQAgAAkKHQ9UUgDwAQAeAAMKwBPqygDOAAAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQAECgQIBAAAAA==.',
Mu='Musterd:BAAANQADCgYJDQAAAA==.',
['Må']='Måddløck:BAAANQADCgYIDAAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.Navatath:BAAANQAECgMIAwABNQAFFAcIGAANADYjAA==.',
Ne='Neiidra:BAAANQAECgQIBQAAAA==.Nepheleah:BAABNQAECoEnAAIWAAkK8yKkCwCXAwAWAAkK8yKkCwCXAwAAAA==.Nesca:BAAANQAECgUIDAAAAA==.Nesmoth:BAAANQAECgIIBgAAAA==.Ness:BAAANQAECgUIEAAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQADCggICAAAAA==.Niiborracho:BAABNQAECoEWAAMGAAYKxw6BMwBDAQAGAAYKxw6BMwBDAQAKAAUKsg7cKQD2AAAAAA==.Niiko:BAAANQAECgMICQAAAA==.',
No='No:BAAANQADCgUJBQABNQAECggIIgACAJMiAA==.Nobullsheep:BAAANQABCggIBwAAAA==.Nommy:BAAANQAECgcIDwABNQAECggIKAAHAHkZAA==.Norntrox:BAAANQAECgYIEAAAAA==.Nothannah:BAABNQAECoEcAAIdAAkKlA6qIQDtAQAdAAkKlA6qIQDtAQAAAA==.',
Ns='Nsshaman:BAAANQADCgUIBQAAAA==.',
Od='Odyssey:BAAANQADCggJCAABNQAECggIHQALADUWAA==.',
Og='Ogreatsxtra:BAAANQAECgIIAwAAAA==.',
Ol='Ol:BAAANQAECgYICwAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgcIBwABNQAECgcIEwABAAAAAA==.',
Or='Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgUIBwAAAA==.',
Oz='Ozhawk:BAAANQAECgUIBwAAAA==.',
Pa='Padreburrito:BAEANQADCgYICwABNQAFFAYIDAAdAMceAA==.Pakno:BAAANQAECgUIBQAAAA==.Pamely:BAABNQAECoEuAAIWAAkKxR2RKgAAAwAWAAkKxR2RKgAAAwAAAA==.',
Ph='Pharmit:BAABNQAECoEdAAMOAAcKAyaYAQAYAwAOAAcKAyaYAQAYAwAPAAEKXSFNEgFeAAAAAA==.Phiarce:BAAANQAECgcIDQAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Porterhouse:BAAANQADCgUIBwAAAA==.Potatoad:BAAANQAECgIIBAAAAA==.',
Pw='Pwags:BAAANQADCgUJBQAAAA==.',
Py='Pyragosa:BAABNQAECoEaAAINAAgKlRH2pwARAgANAAgKlRH2pwARAgAAAA==.Pyramys:BAAANQABCgQIAwABNQAECgYIEgABAAAAAA==.',
['Pà']='Pàt:BAABNQAECoEYAAIiAAgK/RiVGABqAgAiAAgK/RiVGABqAgAAAA==.',
['Pâ']='Pândâmoníum:BAAANQAECgIIBAAAAA==.',
['På']='Påimon:BAAANQADCggJEAAAAA==.',
Qu='Quintin:BAEANQADCgIJAgABNQAECggIHAACAAUeAA==.',
Ra='Racavis:BAAANQADCgMIAwAAAA==.',
Re='Reach:BAAANQADCgYICgABNQAECgYIEAABAAAAAA==.Real:BAABNQAECoEaAAINAAgKRxtvcgCDAgANAAgKRxtvcgCDAgABNQABCgIIAgABAAAAAA==.Realia:BAAANQAECgcICAAAAA==.Reda:BAAANQADCgUICAAAAA==.Redangus:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Reikio:BAAANQADCgIIAgAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAYIFQADAHEaAA==.Revoke:BAAANQAECgYIDwAAAA==.',
Ro='Rocknrolln:BAAANQADCgYIBgAAAA==.Rokubora:BAABNQAECoEgAAMeAAgK1hZ6QwA8AgAeAAgK1hZ6QwA8AgAgAAYKFAsCmQAbAQAAAA==.Rongyi:BAAANQAECgEIAQABNQAECggIIAADAOsVAA==.Roronoa:BAAANQADCgYIBwAAAA==.Roßyn:BAABNQAECoEVAAMiAAgKVBH7JgDMAQAiAAgKVBH7JgDMAQAXAAMKjgbcyACFAAAAAA==.',
Ru='Rubah:BAAANQAECgYIEgAAAA==.Ruroni:BAAANQAECgUIDgAAAA==.',
Ry='Ryniel:BAAANQAECgIIAgAAAA==.',
['Ré']='Rédundant:BAAANQAECgYIDAABNQAECgYIEAABAAAAAA==.',
['Rì']='Rìzz:BAABNQAECoElAAIeAAgKNR/mKQC2AgAeAAgKNR/mKQC2AgAAAA==.',
Sa='Sabrinalee:BAAANQADCgEJAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQAECgIIAwABNQAECgMIBgABAAAAAA==.Sannaggi:BAAANQAECgYIDgAAAA==.Sarahnox:BAABNQAECoEYAAIdAAgKGxogFwBjAgAdAAgKGxogFwBjAgAAAA==.Saramoon:BAAANQAECgYIEAAAAA==.Sarayana:BAAANQABCgIIAwAAAA==.Sargent:BAAANQADCggIGAAAAA==.Saryaa:BAAANQAECgYICgAAAA==.Sashchi:BAAANQAECgYIEQAAAA==.Sassenach:BAAANQAECgEIAgAAAA==.Saudelber:BAAANQAECgQIBQAAAA==.',
Sc='Schanks:BAAANQAECgYIDgAAAA==.Scrotius:BAAANQABCgQIBQAAAA==.',
Se='Sedaelina:BAAANQAECgEIAQABNQAECgkJHAAdAJQOAA==.Sehmet:BAAANQAECgMIBgAAAA==.Seliria:BAABNQAECoEaAAIWAAcKcBAFowCjAQAWAAcKcBAFowCjAQAAAA==.Seoulmate:BAABNQAECoEgAAIDAAgK6xX2MgAnAgADAAgK6xX2MgAnAgAAAA==.Sera:BAAANQAECgcIEwAAAA==.',
Sh='Shadoezz:BAAANQADCgQIBAAAAA==.Shadowk:BAAANQABCgIIAgAAAA==.Shamsicle:BAAANQADCgMIAwAAAA==.Shaye:BAAANQAECgIIBgAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Sherai:BAAANQADCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECggIBgABAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shiryo:BAAANQAECgQIBAAAAA==.Shotfoot:BAABNQAECoEgAAIHAAgKbBn3RgBxAgAHAAgKbBn3RgBxAgAAAA==.Shwang:BAAANQAECgUIDgAAAA==.',
Si='Sihåya:BAAANQAECgcICgAAAA==.Silbergrad:BAAANQADCggIDgAAAA==.Silentio:BAABNQAECoEiAAIRAAgKEBDlKwAFAgARAAgKEBDlKwAFAgAAAA==.Silihunt:BAABNQAECoEhAAMLAAgKEhLzMgDiAQALAAgKfRDzMgDiAQAMAAQKGREfRAD7AAAAAA==.Sinofwrath:BAAANQAECgcIDQAAAA==.Sinsidious:BAAANQAECgUIBQAAAA==.Siwin:BAECNQAFFIEMAAIdAAYKxx61AQA9AgAdAAYKxx61AQA9AgA1AAQKgSMAAx0ACQoSJlcCAJ8DAB0ACQoSJlcCAJ8DAAMAAgrJFWWMAG4AAAAA.',
Sk='Skribb:BAABNQAECoEdAAIIAAcKuiMaIgDNAgAIAAcKuiMaIgDNAgAAAA==.',
Sl='Slapchóp:BAAANQAECgcIEgAAAA==.',
Sm='Smiley:BAACNQAFFIELAAIXAAUKnhLSCwCmAQAXAAUKnhLSCwCmAQA1AAQKgR0AAhcACQrMFUpHACoCABcACQrMFUpHACoCAAE1AAUUBQoLABcAnhIA.Smoko:BAAANQAECgMJBAAAAA==.',
Sn='Sneakyboi:BAAANQAECgcIDgABNQAECggIBgABAAAAAA==.Snorlax:BAAANQAECgcIEwAAAA==.Snowsu:BAACNQAFFIEaAAMPAAcK1CKuAQBmAgAPAAYKmCKuAQBmAgAQAAIKJiGyBADIAAA1AAQKgSoAAw8ACQpPJoEIAHgDAA8ACApgJoEIAHgDABAABwoVHvoJAE4CAAAA.Snowxstorm:BAABNQAECoEVAAISAAcKcRp7MQAsAgASAAcKcRp7MQAsAgAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAAANQAECgUIDgAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAABNQAECoEXAAIEAAcKmwsxYwBdAQAEAAcKmwsxYwBdAQAAAA==.',
Sp='Splashzone:BAAANQAECgUIEAAAAA==.Splits:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.',
St='Staqua:BAAANQAECgIIBAAAAA==.Stateomatter:BAAANQAECgYIEgAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECggIIAADAOsVAA==.Summdari:BAABNQAECoEeAAIYAAcKUBfpCwDdAQAYAAcKUBfpCwDdAQAAAA==.Summrot:BAAANQAECgYIEgAAAA==.Sunfrostt:BAAANQAECgIIAgAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAAANQAECgIIBAAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgUIBgAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAAANQAECgYIDAAAAA==.',
Td='Tdogx:BAAANQAECgQIBAAAAA==.',
Te='Teal:BAAANQAECgEIAQAAAA==.Tekeeladin:BAAANQAECgMIAwABNQAECgkJJwAHAA4fAA==.Tekeelà:BAAANQAECgYIEQABNQAECgkJJwAHAA4fAA==.Tekelemental:BAAANQAECgUIEAAAAA==.Tempestra:BAAANQAECgUICQAAAA==.Tenebria:BAABNQAECoEoAAIkAAkKqSFAAQBdAwAkAAkKqSFAAQBdAwAAAA==.Terrorhungry:BAAANQAECgMIBgAAAA==.',
Th='Thalstrasza:BAABNQAECoEYAAIPAAYKuAywpgBWAQAPAAYKuAywpgBWAQAAAA==.The:BAAANQAECgIIBgAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAABNQAECoEaAAMNAAgKqRaTxQDVAQANAAcKcBWTxQDVAQAZAAIKzxt1KQCEAAAAAA==.Theodiseus:BAAANQADCgUIBQAAAA==.Thugrodent:BAAANQAECggJAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tietus:BAAANQAECgQIBQAAAA==.',
Tl='Tlanimass:BAABNQAECoEUAAIVAAYKHRPkGgBdAQAVAAYKHRPkGgBdAQAAAA==.',
To='Tolac:BAAANQADCgEIAQAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAFFAYICgAPAJMQAA==.',
Ts='Tsu:BAAANQAECgcICwAAAA==.Tsyubaki:BAAANQAECgQICAAAAA==.',
Tu='Tulisse:BAAANQAECgEIAQAAAA==.',
Tw='Twerkngherkn:BAAANQAECgUICAAAAA==.',
Ty='Tybalt:BAABNQAECoEfAAIlAAkKLB5HCADlAgAlAAkKLB5HCADlAgAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.Tyrandaz:BAAANQAECgYICQAAAA==.',
Ul='Uldric:BAAANQAECgUIDAAAAA==.',
Un='Undeaddude:BAAANQAECgQIBAAAAA==.Unslayable:BAAANQAECgQIBAAAAA==.',
Uz='Uzzy:BAAANQAECgEIAQAAAA==.',
Va='Valandir:BAAANQAECgUIDgAAAA==.Valyst:BAAANQAECgEIAQAAAA==.Varya:BAAANQABCgQIBQAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAACNQAFFIEKAAIdAAUKKRR7BQCZAQAdAAUKKRR7BQCZAQA1AAQKgSMAAx0ACQqLFOcXAFoCAB0ACQqLFOcXAFoCAAMABgqYBfRvAN8AAAAA.Verrenth:BAAANQAECggIBgAAAA==.',
Vi='Viduus:BAAANQADCggIGwAAAA==.Vigol:BAAANQADCgQJBAAAAA==.Vivec:BAAANQADCgMIAwAAAA==.',
Vm='Vmaoh:BAAANQADCggIEAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQJBgAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECgcIFwAXAJIXAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgUICgAAAA==.Warwickk:BAAANQABCgIIAgABNQADCgUIBQABAAAAAA==.',
Wi='Wickedholi:BAAANQADCgcIBwABNQAFFAYICgAPAJMQAA==.Wickedsmaht:BAACNQAFFIEKAAMPAAYKkxAMEgA9AQAPAAQK9A8MEgA9AQAQAAIK0BEWDACiAAA1AAQKgTIABA8ACQryIwkYABMDAA8ACArEIwkYABMDABAAAwrcIXkqAB0BAA4AAQquIUQfAGUAAAAA.Widowghast:BAABNQAECoEVAAINAAYKwhSe3QCmAQANAAYKwhSe3QCmAQAAAA==.Willowísp:BAABNQAECoElAAImAAgKkh9GBwCrAgAmAAgKkh9GBwCrAgAAAA==.Witerally:BAAANQAECgEIAwAAAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEANQAECgQIDQAAAA==.',
Xa='Xalthea:BAABNQAECoEiAAQMAAkKaApALQC1AQAMAAgKsgtALQC1AQAYAAEKwQjILwAhAAALAAcKHACOkAATAAAAAA==.Xandapriest:BAAANQADCgYICwABNQAECgkJKgARAHYhAA==.Xanlock:BAAANQADCgUIBwABNQAECggIGgAcAKgZAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECggIIAADAOsVAA==.',
Xp='Xpddevour:BAABNQAECoEjAAILAAgKUBdaKgAkAgALAAgKUBdaKgAkAgAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAABNQAECoEmAAIWAAkKwxxlNwDPAgAWAAkKwxxlNwDPAgAAAA==.',
Xu='Xuxo:BAAANQADCgEIAQAAAA==.',
Ya='Yashoda:BAAANQABCggJCAAAAA==.Yawning:BAAANQADCgcIBwABNQAECgYIEAABAAAAAA==.',
Ye='Yegarmiester:BAAANQAECgIIAwAAAA==.Yenti:BAAANQAECgMIBwAAAA==.',
Yu='Yuexi:BAAANQADCgYIBgABNQAECggIIAADAOsVAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAABNQAECoEVAAIfAAQKqBqQFQAgAQAfAAQKqBqQFQAgAQAAAA==.Zamochy:BAAANQAECgUIBQAAAA==.Zap:BAAANQADCgYICgABNQAECgcIEwABAAAAAA==.',
Ze='Zerality:BAAANQAECgYICAAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAABNQAECoEXAAIMAAYKYCURFwCPAgAMAAYKYCURFwCPAgAAAA==.',
Zo='Zoltan:BAAANQADCgUICAAAAA==.Zookee:BAABNQAECoEXAAIKAAcKDwgKJQAoAQAKAAcKDwgKJQAoAQAAAA==.',
Zu='Zulizek:BAABNQAECoEYAAIgAAcKmwbclQAjAQAgAAcKmwbclQAjAQAAAA==.',
Zy='Zynister:BAAANQAECgcIEAAAAA==.',
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
