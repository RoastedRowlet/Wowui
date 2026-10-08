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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Priest-Holy','Druid-Feral','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Priest-Shadow','Mage-Arcane','Unknown-Unknown','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Paladin-Protection','Paladin-Retribution','Evoker-Devastation','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Guardian','Hunter-BeastMastery','Paladin-Holy','Hunter-Marksmanship','Evoker-Preservation','Hunter-Survival','Mage-Frost','Druid-Restoration','Rogue-Assassination','Monk-Mistweaver','Warrior-Fury','Priest-Discipline',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aamix:BAACNQAFFIEMAAQBAAUKtQiXHgDVAAABAAMK9AmXHgDVAAACAAEKVww4DQBEAAADAAEKVgHaIAA+AAA1AAQKgTsAAwEACQriGoY4AI8CAAEACAq9GYY4AI8CAAMABgoXD1AfAGwBAAAA.Aarom:BAACNQAFFIEWAAIEAAcKWBsZAgBLAgAEAAcKWBsZAgBLAgA1AAQKgSEAAgQACQqfIywLAAsDAAQACQqfIywLAAsDAAAA.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAAANQAECgcIEAAAAA==.Abrakastaba:BAAANQAECgcICAABNQAFFAQIDgAFAHgcAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aequitas:BAAANQADCgUIBQAAAA==.Aerius:BAAANQAECgQICwAAAA==.',
Af='Affliclock:BAACNQAFFIELAAICAAUKMRSSAACpAQACAAUKMRSSAACpAQA1AAQKgRwAAgIACQrRH/EBAPwCAAIACQrRH/EBAPwCAAAA.',
Ai='Aingerfal:BAAANQAECgUIBwAAAA==.',
Aj='Aj:BAAANQAECgUIBgAAAA==.',
Ak='Akasori:BAABNQAECoEuAAIGAAkKJCFfAwBRAwAGAAkKJCFfAwBRAwAAAA==.Akisori:BAAANQAECgQIBQABNQAECgkJLgAGACQhAA==.Akosori:BAAANQADCgYIDAABNQAECgkJLgAGACQhAA==.',
Al='Alistaier:BAAANQAECgEIAgABNQAECggIKQAHADUbAA==.Allnaturale:BAAANQADCgcICwAAAA==.Alterboyy:BAAANQAECgUIDgAAAA==.Alîsonshammy:BAACNQAFFIELAAMIAAQKxR4hDwAtAQAIAAMKKCMhDwAtAQAJAAMKtgZDGADMAAA1AAQKgR4AAwgACQqEIuUMAEUDAAgACQqEIuUMAEUDAAkACAqkGqhBAEQCAAAA.',
Am='Ambersulfr:BAABNQAECoEVAAIKAAcKhxfBEwAGAgAKAAcKhxfBEwAGAgAAAA==.Amrazz:BAABNQAECoEcAAMFAAkKbhliHwDXAgAFAAkKbhliHwDXAgALAAIKzwsHXgBeAAAAAA==.Amzey:BAEBNQAECoEsAAIMAAkKvR6FLgAlAwAMAAkKvR6FLgAlAwAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgcICwANAAAAAA==.Andromeda:BAABNQAECoEmAAIOAAgKjRm/CwBRAgAOAAgKjRm/CwBRAgAAAA==.Anneaux:BAAANQAECgIJAwAAAA==.Antimortem:BAAANQADCgYIFAAAAA==.',
Ar='Aridillo:BAAANQAECgEIAQAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgYIDwAAAA==.Astralus:BAAANQAECgQIDQAAAA==.Astramis:BAAANQAECgUIEQAAAA==.',
At='Athennaa:BAAANQADCgYIBgAAAA==.Atomicbarbie:BAABNQAECoEYAAIPAAgK4xi0XQBWAgAPAAgK4xi0XQBWAgABNQAFFAQICwAIAMUeAA==.Atriøx:BAAANQAECgIIAwAAAA==.Atziri:BAABNQAECoEnAAIJAAkK+Rc9MwCGAgAJAAkK+Rc9MwCGAgAAAA==.',
Av='Avalinia:BAAANQADCgIIAgAAAA==.',
Az='Azamia:BAAANQAECgQIDgABNQAECgEIAQANAAAAAA==.',
Ba='Babyknife:BAAANQAECgIIAgABNQAFFAcIFgAEAFgbAA==.Backlash:BAABNQAECoEXAAIQAAcKvxIQKgDSAQAQAAcKvxIQKgDSAQAAAA==.Balzhac:BAABNQAECoEWAAMRAAkK4h72EABpAgARAAcKZiD2EABpAgASAAMKrxu29QD5AAAAAA==.Bam:BAAANQADCggICAABNQAFFAYIEQAHAIYYAA==.Bamplify:BAABNQAECoEVAAIMAAkKnx15PQD9AgAMAAkKnx15PQD9AgABNQAFFAYIEQAHAIYYAA==.Barrierbobo:BAAANQAECgUIEQAAAA==.Barthold:BAAANQAECgEIAQAAAA==.',
Be='Beleaf:BAAANQAECgYIBwAAAA==.Bellmonte:BAAANQADCgYIDwABNQAECggIGwATAKIaAA==.Belmonk:BAAANQAECgQIBQAAAA==.Berdron:BAABNQAECoErAAQDAAgKMhN/DAAkAgADAAgKMhN/DAAkAgABAAIK0QcoCwFxAAACAAEKigUxLgAuAAAAAA==.',
Bi='Biden:BAAANQAECgMIBAAAAA==.',
Bl='Bladeliger:BAABNQAECoEmAAIUAAgK0xr5JwBzAgAUAAgK0xr5JwBzAgAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAABNQAECoEhAAIPAAkKyyRGFQBbAwAPAAkKyyRGFQBbAwAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAABNQAECoEUAAIVAAYKOR+wDAAVAgAVAAYKOR+wDAAVAgAAAA==.Bonemair:BAACNQAFFIEXAAIWAAYKRBdJBwDHAQAWAAYKRBdJBwDHAQA1AAQKgSwAAhYACQpbITkPACEDABYACQpbITkPACEDAAAA.Boomguy:BAAANQADCgQIBAABNQAECgUIDQANAAAAAA==.Boredasf:BAAANQADCgYIBgAAAA==.Boricuazo:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIFwAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQAECgYIAwANAAAAAA==.',
Bu='Bubblehooker:BAAANQAECgIJAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAFFAQIDgAFAHgcAA==.Bullteesta:BAAANQAECgQIBgAAAA==.Burkhard:BAAANQADCggIBwAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQAECgMIBgAAAA==.',
Ca='Caldec:BAACNQAFFIEWAAMXAAYKCB6zAgDTAQAXAAUKFSGzAgDTAQAYAAUKThQZBgCfAQA1AAQKgS0AAhcACQpEJrYDAJkDABcACQpEJrYDAJkDAAAA.',
Ch='Chainizard:BAAANQAECggIDgAAAA==.Chainpwn:BAAANQAECgUIBQABNQAECggIDgANAAAAAA==.Chaosofelune:BAAANQAECgIIAgAAAA==.Chaosoflife:BAAANQAECgIJBAAAAA==.Chaosoflight:BAAANQAECgUIBgAAAA==.Cheeno:BAABNQAECoEkAAMQAAkKKiPSAwCUAwAQAAkKKiPSAwCUAwAZAAEKPSJkJQBaAAAAAA==.Chihiro:BAAANQAECgUICAAAAA==.Chillyblinks:BAAANQAFFAIIAgAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chloris:BAAANQADCgMIAwABNQAECgQIBgANAAAAAA==.Chuffed:BAAANQAECgEIAQAAAA==.',
Ci='Cinderheart:BAAANQAECgEIAQAAAA==.Ciymi:BAAANQAECgcICQABNQAFFAYICAAMAKoSAA==.',
Cl='Clarabelle:BAACNQAFFIEIAAIMAAYKqhKfDADzAQAMAAYKqhKfDADzAQA1AAQKgSAAAgwACQqpIhAXAHADAAwACQqpIhAXAHADAAAA.Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMJAwABNQAECgYIAwANAAAAAA==.Computer:BAABNQAECoEjAAMDAAkK/yBTBADZAgADAAgK/yJTBADZAgABAAgKvB3rQABzAgAAAA==.Cootin:BAAANQAECggICwAAAA==.',
Cp='Cpteddie:BAABNQAECoEeAAMRAAkKKx1tDQCiAgARAAkKKx1tDQCiAgASAAMKahGUJwGjAAABNQAFFAYIEwAWAFoaAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQANAAAAAA==.Crelam:BAACNQAFFIEXAAIKAAYKbQ8nAQD+AQAKAAYKbQ8nAQD+AQA1AAQKgSwAAgoACQonGSkLAKkCAAoACQonGSkLAKkCAAAA.Critherine:BAAANQAECgQICgAAAA==.Cronatherus:BAAANQAECgEIAwAAAA==.Cruentis:BAABNQAECoEiAAIaAAgKThfZBgBAAgAaAAgKThfZBgBAAgAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgcIEwANAAAAAA==.Crysus:BAAANQAECgcIEwAAAA==.',
Da='Dabo:BAABNQAECoEcAAIUAAgK+R6rHwCxAgAUAAgK+R6rHwCxAgAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAECgkJIQAPAMskAA==.Darwin:BAAANQAECgUIEgAAAA==.Dasmoodhayn:BAAANQAECgIIBQAAAA==.Davalanch:BAABNQAECoEfAAIJAAkKWxnxNgB1AgAJAAkKWxnxNgB1AgAAAA==.Dazizejr:BAABNQAECoErAAIWAAkKJCWkBACfAwAWAAkKJCWkBACfAwAAAA==.',
De='Deathisbrew:BAAANQAECggICAAAAA==.Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICgAAAA==.Denïed:BAAANQADCgYICgAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQAECgEIAQAAAA==.',
Di='Dibstrum:BAAANQAECgQIDAAAAA==.Digduug:BAAANQAECgQIDwAAAA==.Dixqt:BAAANQAECgQIDAAAAA==.',
Do='Dogfight:BAACNQAFFIEWAAQYAAYKnhO3BwB7AQAYAAUKlxS3BwB7AQAXAAEKYQChGwAsAAAWAAEKxA56LgAqAAA1AAQKgSoABBgACQq9HgsiAJ8CABgACQosHQsiAJ8CABcAAgpHC5SEAFgAABYAAQqND3m9AC8AAAAA.Doilookfatou:BAABNQAECoEYAAMbAAgKBR/+CACzAgAbAAgKBR/+CACzAgAUAAUKMwiWcADdAAAAAA==.',
Dr='Draxus:BAAANQAECgUIEwAAAA==.Dresel:BAABNQAECoEaAAIcAAkKvxc0NQCpAgAcAAkKvxc0NQCpAgAAAA==.Drewpeebahlz:BAABNQAECoEUAAIdAAgKShk/MwB8AgAdAAgKShk/MwB8AgABNQABCgIIAgANAAAAAA==.Drshakaloo:BAAANQADCggIHQAAAA==.',
Du='Dunnome:BAAANQAECgIIAwAAAA==.Durto:BAAANQADCgcIDQAAAA==.',
Dy='Dyami:BAABNQAECoEgAAMcAAgKKyPCKgDNAgAcAAcK+yPCKgDNAgAeAAUKrRiPOABcAQAAAA==.Dynas:BAAANQAECgYIEgAAAA==.',
Ea='Earthcake:BAABNQAECoEoAAMJAAkKLCHeEQBNAwAJAAkKLCHeEQBNAwAIAAMKIwfA4gB2AAAAAA==.',
Ed='Eddielich:BAACNQAFFIETAAIWAAYKWhr7BAAHAgAWAAYKWhr7BAAHAgA1AAQKgSQAAhYACQrZJBUHAHwDABYACQrZJBUHAHwDAAAA.Eddieteddie:BAAANQAECgcIBwABNQAFFAYIEwAWAFoaAA==.',
Eg='Eggfumonk:BAAANQAECgYIAwAAAA==.',
Eh='Ehlo:BAAANQADCgEIAQAAAA==.',
El='Elasmon:BAABNQAECoEUAAIaAAgKlRMsCAALAgAaAAgKlRMsCAALAgAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elbonyt:BAAANQAECgEIAQAAAA==.Elfpen:BAAANQAECgEIAQAAAA==.Ellan:BAAANQAECgcIEAAAAA==.',
Em='Emongalkar:BAAANQADCgQIBAAAAA==.',
Er='Erragal:BAAANQAECgEIAQAAAA==.',
Es='Escanõr:BAABNQAECoEXAAISAAkK5RHYagAvAgASAAkK5RHYagAvAgAAAA==.',
Ez='Ezindrozar:BAAANQADCggICwAAAA==.',
Fa='Falek:BAAANQAECgEIBAAAAA==.Faustyne:BAAANQAECgcIEQABNQAECgkJMgAcAG4kAA==.',
Fe='Felurián:BAAANQAECgUICwABNQADCgcIGgANAAAAAA==.Fexli:BAAANQAECgEIAQAAAA==.',
Fi='Fireteeth:BAAANQADCggIEwAAAA==.Fiverunner:BAAANQADCgQIBAAAAA==.Fizc:BAAANQADCgcIBwAAAA==.',
Fl='Flurtty:BAAANQAECgEIAQAAAA==.',
Fo='Folklore:BAAANQAECgUIEAAAAA==.Forklift:BAAANQAECgIIAgABNQAECggIJAAfANcgAA==.Foxrocks:BAAANQAECgEIAQAAAA==.',
Fr='Frigomortis:BAAANQAECgMIAwABNQAECgUIDgANAAAAAA==.Frozown:BAABNQAECoEbAAIMAAcK9hTMwADfAQAMAAcK9hTMwADfAQAAAA==.Fruits:BAAANQAECgUIDgAAAA==.Fruitsack:BAAANQAECgYIBwABNQAECgUIDgANAAAAAA==.',
Ft='Ftfw:BAAANQAECgYIDgAAAA==.',
Fu='Funfanfare:BAAANQAECgMIBAAAAA==.Furrylife:BAAANQAECgIIAgAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQANAAAAAA==.Fuzzychin:BAAANQAECgYIEAABNQAFFAIIAgANAAAAAA==.',
['Fò']='Fòrlorn:BAAANQAECgEIAgAAAA==.',
Ga='Galram:BAABNQAECoEgAAIgAAgK9RJxBQA7AgAgAAgK9RJxBQA7AgABNQAFFAYIFwAKAG0PAA==.Gardettos:BAABNQAECoEkAAIfAAgK1yDWDADGAgAfAAgK1yDWDADGAgAAAA==.Gargingoyles:BAAANQADCgIJAgAAAA==.',
Gh='Gharghael:BAAANQAECgQICAAAAA==.Ghostthunter:BAAANQADCgQIBAABNQAECggIEwANAAAAAA==.',
Gi='Gip:BAAANQADCggICAAAAA==.',
Gl='Glimmair:BAABNQAECoEXAAIRAAcKOR1FEwBKAgARAAcKOR1FEwBKAgABNQAFFAYIFwAWAEQXAA==.Glimmer:BAAANQADCggIDQAAAQ==.',
Gn='Gnxrli:BAEANQADCgIIAgABNQAECgkJIwAEAF8kAA==.Gnxrr:BAEBNQAECoEjAAIEAAkKXyQgBACHAwAEAAkKXyQgBACHAwAAAA==.',
Go='Gooncaine:BAAANQAECgYICwAAAA==.Gorbstrasz:BAAANQAECgEIAgAAAA==.Gorpse:BAAANQAECgYIDgAAAA==.',
Gr='Gregorz:BAAANQAECgEIAQAAAA==.Greyanna:BAAANQAECgUIDgAAAA==.Gridon:BAAANQADCgYIBgAAAA==.Gripguy:BAAANQADCggICAABNQAECgUIDQANAAAAAA==.Gromthrall:BAAANQAECgYIDQAAAA==.',
Gw='Gworp:BAAANQAECgIJAwAAAA==.Gwynhwyfar:BAAANQADCgcIEQABNQAECggIGAAcAM4VAA==.',
['Gú']='Gúi:BAAANQAECgEIAQAAAA==.',
Ha='Hangsut:BAAANQAECgEIAQAAAA==.',
Hb='Hbhealthen:BAACNQAFFIEVAAIfAAYKIxgtBQDzAQAfAAYKIxgtBQDzAQA1AAQKgToAAx8ACQqRI80CAIkDAB8ACQqRI80CAIkDABMAAgrnENAvAHIAAAAA.',
He='Hellhore:BAAANQAECgMIDAAAAA==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECggIEwAAAA==.',
Ho='Holdenc:BAAANQAECgMIBwABNQAECgkJKQAIADgdAA==.Hoodz:BAABNQAECoEmAAIPAAgKciNLJAAYAwAPAAgKciNLJAAYAwAAAA==.Houseplant:BAAANQAECgUIBQAAAA==.Howard:BAAANQAECgQICwAAAA==.',
Hu='Huatli:BAAANQADCggIEgAAAA==.Huzzarr:BAAANQAECgEIAQAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQICwAAAA==.',
Ic='Icerod:BAAANQADCgUJBQABNQAECgUIDgANAAAAAA==.',
Id='Idtrapdat:BAABNQAECoEuAAMcAAkKpCMxCwByAwAcAAkKpCMxCwByAwAeAAIKPBT8XgCDAAAAAA==.',
Il='Illyana:BAAANQAECggIEAAAAA==.Ilse:BAABNQAECoEjAAIdAAkKdR02FwANAwAdAAkKdR02FwANAwAAAA==.',
Im='Imagined:BAACNQAFFIEXAAMMAAYKMhMODQDvAQAMAAYKMhMODQDvAQAhAAIK/QdEBwCEAAA1AAQKgSoAAgwACQphHndWAMICAAwACQphHndWAMICAAAA.',
In='Indihunter:BAAANQADCgEIAQAAAA==.Infernis:BAAANQADCgcIDAAAAA==.Infidelic:BAAANQADCgYICwABNQAECgQICwANAAAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAABNQAECoEXAAIBAAkKGA/jXQAcAgABAAkKGA/jXQAcAgAAAA==.Ivannalot:BAAANQAECgEIAQAAAA==.Ivracha:BAAANQAECgEJAQAAAA==.',
Ja='Jage:BAAANQAECgcICwAAAA==.Jarsham:BAAANQAECgUIDgAAAA==.Jaràdan:BAAANQAECgcJCQABNQAECgkJIwAMALsWAA==.Jawshua:BAAANQAECgEIAwAAAA==.',
Je='Jeff:BAABNQAECoEpAAIPAAkK9R45KwD9AgAPAAkK9R45KwD9AgAAAA==.Jezibelle:BAAANQAECgEIAgAAAA==.',
Jo='Joran:BAAANQAECgQICwAAAA==.Jordie:BAAANQADCgIIAgAAAA==.Jorlannee:BAAANQADCgEIAQABNQADCgcIGgANAAAAAA==.',
Jr='Jroc:BAAANQAFFAEIAQAAAA==.',
Jw='Jwrs:BAAANQAECgYIEgAAAA==.',
['Jï']='Jïbril:BAABNQAECoEdAAIWAAkKXRcjLgBAAgAWAAkKXRcjLgBAAgAAAA==.',
Ka='Kabbala:BAAANQAECgYIEAABNQAFFAYIFwAMADITAA==.Kahlani:BAABNQAECoEmAAIIAAgK2xHSXQDHAQAIAAgK2xHSXQDHAQAAAA==.Kahlua:BAAANQAECgQICAAAAA==.Kailan:BAAANQAECgUIEwABNQAECggIKAALAF0hAA==.Kalathios:BAAANQABCgIIAgABNQAECgQIBgANAAAAAA==.Kaldro:BAAANQAECgYIDQAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAABNQAECoEgAAIVAAgKyw2aEgCbAQAVAAgKyw2aEgCbAQAAAA==.Kano:BAAANQAECgMIBQAAAA==.Kariana:BAABNQAECoEnAAMJAAgKTxW7RwArAgAJAAgKTxW7RwArAgAIAAgKyQQukQAvAQAAAA==.Kathry:BAAANQADCgcIGQAAAA==.',
Ke='Keelzya:BAAANQAECggICAAAAA==.Keepdreaming:BAABNQAECoEgAAIiAAgKIBPZIAD2AQAiAAgKIBPZIAD2AQAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keybricker:BAAANQAECgYIBgABNQAFFAQIDgAFAHgcAA==.Keymebrah:BAABNQAECoEbAAMMAAkKvRGWqgAMAgAMAAkKWxGWqgAMAgAhAAMKnRGKKACLAAAAAA==.',
Ki='Killeh:BAAANQADCggIDgAAAA==.',
Ko='Korda:BAAANQAECgIIBwAAAA==.Korinä:BAABNQAECoEaAAIjAAgKkQtGMgDbAQAjAAgKkQtGMgDbAQAAAA==.Kosh:BAAANQAECgEIAQAAAA==.Koyra:BAACNQAFFIESAAITAAYKMSWVAACFAgATAAYKMSWVAACFAgA1AAQKgSoAAhMACQqpJS0CAIwDABMACQqpJS0CAIwDAAAA.',
Kr='Kreyden:BAAANQAECgMIAwAAAA==.Krump:BAAANQAECgEIAQAAAA==.',
Ku='Kubbles:BAAANQADCggICAAAAA==.Kubs:BAAANQADCgYIBgAAAA==.Kubwa:BAAANQABCgcIDwAAAA==.Kungfugimp:BAAANQAECgcIDwAAAA==.Kurral:BAACNQAFFIEWAAMUAAYKOg5CCgCeAQAUAAYKOg5CCgCeAQAiAAQK/AB8CwDGAAA1AAQKgSgAAxQACQqNHSscAM0CABQACQqNHSscAM0CACIABArrBHJOAKIAAAAA.Kurralium:BAABNQAECoEaAAIhAAgKxw79CwDGAQAhAAgKxw79CwDGAQABNQAFFAYIFgAUADoOAA==.Kurstina:BAAANQADCgYICQAAAA==.Kuzushi:BAAANQAECggICAAAAA==.',
Ky='Kyramus:BAAANQAECgUIEAAAAA==.',
La='Laconia:BAABNQAECoEbAAITAAgKoho3DQB0AgATAAgKoho3DQB0AgAAAA==.Lashstorm:BAAANQAECgcICAAAAA==.Lattsatnar:BAAANQAECgQIDQAAAA==.',
Le='Lebron:BAAANQAECgcIDQAAAA==.Lelesobi:BAAANQABCgQIBwAAAA==.Lennel:BAAANQAECgIIBgAAAA==.Lewd:BAAANQAECggIAgAAAA==.',
Lg='Lga:BAAANQAECgEIAQAAAA==.',
Li='Lilsnick:BAAANQAECgQICwAAAA==.Lisaluv:BAAANQAECggICAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQANAAAAAA==.',
Ll='Llanthyl:BAAANQAECgUIEgAAAA==.',
Lo='Lockbawx:BAAANQAECgEIAQABNQAECgEIAQANAAAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.',
Lu='Lucía:BAABNQAFFIEGAAIWAAUKqxWPCwBvAQAWAAUKqxWPCwBvAQAAAA==.Luecien:BAAANQADCgUIBQAAAA==.Lunafalia:BAABNQAECoEmAAIhAAgKchrBBgBkAgAhAAgKchrBBgBkAgAAAA==.Lupon:BAAANQAECggICAAAAA==.Lurosa:BAACNQAFFIEIAAIiAAUKVxp0BAC8AQAiAAUKVxp0BAC8AQA1AAQKgSYAAiIACQoPJlMAAOsDACIACQoPJlMAAOsDAAAA.Luxeria:BAAANQAECgcIDwAAAA==.Luxray:BAAANQABCggIFQAAAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lî']='Lîlydan:BAAANQADCgUIBwAAAA==.',
['Lï']='Lïchkinged:BAAANQAECgYIDAAAAA==.',
Ma='Macready:BAACNQAFFIEGAAIOAAIKjiOTAwDSAAAOAAIKjiOTAwDSAAA1AAQKgSgAAg4ACQomJSwJAJACAA4ACQomJSwJAJACAAAA.Magenin:BAAANQAECgIIAgAAAA==.Maggotgut:BAAANQAECgQICQAAAA==.Magoren:BAAANQADCgUIBgAAAA==.Mairbear:BAAANQAECgcICAABNQAFFAYIFwAWAEQXAA==.Mairiachi:BAAANQAECgEIAQABNQAFFAYIFwAWAEQXAA==.Maltessa:BAAANQADCgUICgABNQAECggIKAALAF0hAA==.Marload:BAACNQAFFIELAAMcAAUKoAl9DwAhAQAcAAQKTgt9DwAhAQAeAAQKvgrFEAACAQA1AAQKgTAAAx4ACQrVG4IVAJsCAB4ACQpLF4IVAJsCABwACApJHVRkACECAAAA.Mathy:BAAANQAECgcIEAAAAA==.',
Me='Melath:BAAANQADCggIFQAAAA==.Melreu:BAAANQADCgEIAQABNQAECgkJJAAQACojAA==.',
Mi='Midletons:BAAANQAECgUICgAAAA==.Minikub:BAABNQAECoEXAAIEAAcKKQp3MgBMAQAEAAcKKQp3MgBMAQAAAA==.Mixxy:BAAANQAECgQIBQABNQAFFAcIFwAEANIXAA==.',
Mn='Mnzn:BAAANQADCggIGgAAAA==.',
Mo='Moobubble:BAAANQAECgcIDgABNQAECgkJKAAJACwhAA==.Moodroo:BAAANQAECgQICAAAAA==.Moonanoke:BAAANQAECgUICwAAAA==.Moovoker:BAABNQAECoEnAAIfAAgK5CIuCAASAwAfAAgK5CIuCAASAwAAAA==.Morseques:BAABNQAECoElAAMYAAgKoCMfFAABAwAYAAgKoCMfFAABAwAWAAEKaCK2pQBiAAAAAA==.Mortimer:BAAANQAECgMIBQAAAA==.Mothra:BAAANQADCggICAAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAACNQAFFIEMAAMYAAYKYhx6BQCtAQAYAAUKnBp6BQCtAQAWAAEKPiW3HwBtAAA1AAQKgS0AAxgACQpxJkcDALcDABgACQpxJkcDALcDABcAAwp5F51mAL4AAAAA.Muguda:BAAANQADCgMIAwAAAA==.',
Mx='Mxkebfistin:BAACNQAFFIEXAAIEAAcK0hckAgBJAgAEAAcK0hckAgBJAgA1AAQKgSUAAgQACQppIRwLAAwDAAQACQppIRwLAAwDAAAA.Mxkebspinnin:BAAANQADCggICAABNQAFFAcIFwAEANIXAA==.',
Na='Narama:BAACNQAFFIERAAMBAAUK6QYhFgARAQABAAQKuQchFgARAQADAAIKngKTEAB/AAA1AAQKgSoABAMACQpWFAAjAE4BAAEACQpLE0FWADICAAMABgqODAAjAE4BAAIAAQoADdIvACcAAAAA.',
Ne='Nekka:BAABNQAECoEUAAIIAAYKbRMPgABeAQAIAAYKbRMPgABeAQAAAA==.Nethanos:BAAANQAECgQICQABNQAECgUICAANAAAAAA==.Neverrmore:BAAANQAECgEIAgAAAA==.',
Ni='Ninæ:BAACNQAFFIEMAAIfAAUK+BV1CACMAQAfAAUK+BV1CACMAQA1AAQKgSEAAh8ACQrVIO4EAFYDAB8ACQrVIO4EAFYDAAAA.Nitewïng:BAAANQAECgUIFAABNQADCggIDQANAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwABNQAECgIIBgANAAAAAA==.Nohomoh:BAAANQADCgUIBgAAAA==.Nootau:BAABNQAECoEYAAIMAAcKKx5UlgA2AgAMAAcKKx5UlgA2AgAAAA==.',
Ny='Nyoz:BAAANQAECgQIBwAAAA==.Nyxxadra:BAABNQAECoElAAIBAAgKEBC6bgDrAQABAAgKEBC6bgDrAQAAAA==.',
Oa='Oakshion:BAAANQAECgEIAQAAAA==.',
Om='Omegadeed:BAABNQAECoEjAAIBAAgKJRe9UABCAgABAAgKJRe9UABCAgAAAA==.',
On='Onne:BAAANQAECgEIAQAAAA==.',
Or='Orcinus:BAABNQAECoEiAAIfAAkKmg9YFwAsAgAfAAkKmg9YFwAsAgAAAA==.Orcishfist:BAAANQAECgcIDgAAAA==.Orvar:BAAANQAECgQIBgABNQABCgIIAgANAAAAAA==.',
Pa='Pakaru:BAABNQAECoEdAAISAAkKIBhcTgCCAgASAAkKIBhcTgCCAgAAAA==.Pam:BAACNQAFFIERAAIHAAYKhhg7BAD+AQAHAAYKhhg7BAD+AQA1AAQKgSYAAwcACQr/JEkMADMDAAcACQr/JEkMADMDABAAAgrTIVJNALQAAAAA.Parathin:BAAANQADCggIFAAAAA==.',
Pe='Peorä:BAABNQAECoEgAAMFAAgKhgujagCoAQAFAAgKhgujagCoAQALAAcK6AN4QgD1AAAAAA==.Perfectdark:BAACNQAFFIEXAAIQAAYKPSA/AgBLAgAQAAYKPSA/AgBLAgA1AAQKgS4AAxAACQrcJNMEAIADABAACQrcJNMEAIADAAcAAgrCIPZhAMAAAAAA.Perse:BAAANQAECgQIBQAAAA==.',
Ph='Phathottie:BAAANQABCgMIBAABNQAECgUIDgANAAAAAA==.Pheadas:BAAANQADCgUJBQAAAA==.Phleez:BAAANQADCggICwABNQAECgIIAwANAAAAAA==.',
Pi='Pieper:BAABNQAECoEYAAIcAAgKzhUIWgA8AgAcAAgKzhUIWgA8AgAAAA==.Pipa:BAABNQAECoErAAIIAAgKYCWrCwBPAwAIAAgKYCWrCwBPAwAAAA==.Pippit:BAABNQAECoEZAAIdAAgKfRKSVQD4AQAdAAgKfRKSVQD4AQABNQAECggIKwAIAGAlAA==.',
Pl='Plokane:BAABNQAECoEjAAMBAAgKuyDtPwB3AgABAAcKRx/tPwB3AgADAAIK9COOPADEAAAAAA==.',
Po='Poacher:BAAANQAECgEIAQAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQAECgQIBgABNQAECgcIDQANAAAAAA==.Powar:BAAANQAECggIDgAAAA==.',
Pr='Provence:BAAANQAECgEIAwAAAA==.',
Py='Pyreynna:BAAANQAECgUIEQAAAA==.',
['Pè']='Pèppèr:BAABNQAECoEVAAISAAcK3xTbnACyAQASAAcK3xTbnACyAQABNQAECggIJgAOAI0ZAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Ragarn:BAAANQAECgEIAgABNQAECgkJKQAIADgdAA==.Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAAANQAECgUIEwAAAA==.Rapsodia:BAAANQAECgQICAABNQAFFAYICAAMAKoSAA==.Raschild:BAAANQAECgUIDQAAAA==.',
Re='Realfrojd:BAABNQAECoEsAAIWAAgKHwldXQBbAQAWAAgKHwldXQBbAQAAAA==.Regginunchuk:BAABNQAECoEoAAIEAAkKMx5uCwAHAwAEAAkKMx5uCwAHAwAAAA==.Releronastus:BAAANQAECgIIBQAAAA==.Reliquary:BAAANQAECgEIAQAAAA==.Rextallion:BAABNQAECoExAAMRAAkKCh8FDgCXAgASAAkKchsNOgDFAgARAAgKxh4FDgCXAgAAAA==.Reyson:BAABNQAECoEmAAIMAAgKFg3JvADnAQAMAAgKFg3JvADnAQAAAA==.',
Rh='Rhunon:BAABNQAECoE2AAIWAAkK0BtqHQCsAgAWAAkK0BtqHQCsAgAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rimlaol:BAAANQADCgEIAQAAAA==.Rinchi:BAAANQADCgYIDAAAAA==.Rinthia:BAABNQAECoEoAAILAAgKXSGfDAAKAwALAAgKXSGfDAAKAwAAAA==.Ripyeet:BAABNQAECoEcAAISAAgKFxrPZwA3AgASAAgKFxrPZwA3AgAAAA==.Rivanarina:BAAANQAECgEIAQAAAA==.',
Ro='Rol:BAAANQAECgQICQAAAA==.Rolden:BAAANQAECgEIAgAAAA==.',
Ru='Rukaji:BAABNQAECoEZAAIPAAcKWBTxgwDtAQAPAAcKWBTxgwDtAQAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYIFQABNQADCgQIBQANAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAABNQAECoEgAAIPAAgKLRdAZQBAAgAPAAgKLRdAZQBAAgAAAA==.Samayel:BAAANQAECgIIAgAAAA==.Sarkang:BAABNQAECoEmAAMWAAcKOBqkQQDYAQAWAAUKdCCkQQDYAQAYAAcKABDPXAB2AQAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECggIJgAOAI0ZAA==.',
Sc='Schmeebie:BAAANQAECgIJAgABNQAECgUICgANAAAAAA==.Schutze:BAABNQAECoEdAAIgAAkKhyTHAQAzAwAgAAkKhyTHAQAzAwAAAA==.',
Sd='Sdadfeg:BAABNQAECoElAAIKAAgK1CW5AgB3AwAKAAgK1CW5AgB3AwAAAA==.',
Se='Sebastien:BAAANQADCggICAABNQAECgkJIAAcAIEZAA==.Senco:BAAANQAECgIIBgAAAA==.Sephroth:BAAANQAECgEIAQABNQAECgIIAgANAAAAAA==.',
Sh='Shabobado:BAABNQAECoEZAAIMAAgKVBjrggBfAgAMAAgKVBjrggBfAgAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shayder:BAAANQAFFAEIAQAAAA==.Shiipo:BAAANQADCggIEgAAAA==.Shura:BAAANQADCggICAAAAA==.Shuten:BAAANQAECgUIBwAAAA==.Shxdow:BAAANQADCgEJAQAAAA==.Shøck:BAAANQAECgMIBQAAAA==.',
Si='Sibble:BAAANQADCgYIDAAAAA==.Siegfried:BAAANQAECgEIAQAAAA==.Silbanuz:BAAANQAECgQIBwAAAA==.Silverie:BAAANQAECgQIBAABNQAECggIKwAIAGAlAA==.Simplejakk:BAAANQAECgcICAAAAA==.Sinill:BAAANQADCggIDwAAAA==.Sinterklaas:BAABNQAECoEaAAIIAAgKcBWhTQABAgAIAAgKcBWhTQABAgAAAA==.',
Sk='Skjald:BAAANQAECgMJAwABNQAFFAQIDgAFAHgcAA==.Skylee:BAABNQAECoEUAAMMAAgKWhSozQDFAQAMAAcKoRSozQDFAQAhAAEKahKLOgBAAAAAAA==.',
Sl='Slark:BAABNQAECoEWAAMVAAgKXgmSGQAmAQAVAAcKKwaSGQAmAQAkAAUKYQsCLQDYAAAAAA==.Slawth:BAABNQAECoEUAAMYAAgKeQ8HUQCmAQAYAAgKeQ8HUQCmAQAWAAEKEQT8uwAyAAAAAA==.Slayermonde:BAAANQAECgEIAQAAAA==.Sleepel:BAAANQADCgYICgAAAA==.',
Sm='Smexytimes:BAABNQAECoEaAAIPAAgKihoOXwBSAgAPAAgKihoOXwBSAgAAAA==.Smeyplus:BAACNQAFFIERAAMSAAYKJCIeBQDnAQASAAUKViEeBQDnAQARAAEKKyalCgByAAA1AAQKgScAAxIACQreJi0DAN4DABIACQq5Ji0DAN4DABEAAQrVJh5RAG8AAAAA.',
Sn='Snaccident:BAAANQAECgcICAAAAA==.Snickeris:BAAANQAECgQICwABNQAECgQICwANAAAAAA==.Snofawl:BAAANQAECgYIEAAAAA==.Snoranir:BAAANQAECgYIDwAAAA==.Snurchbasher:BAAANQAECgUIEgAAAA==.',
Sp='Sparrowhawk:BAAANQAECgEIAQAAAA==.Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAABNQAECoEpAAIIAAkKOB3gHgDSAgAIAAkKOB3gHgDSAgAAAA==.Spratticus:BAAANQADCgYICgAAAA==.',
Sq='Squidd:BAAANQAECgEIAQAAAA==.',
St='Stars:BAABNQAECoEVAAMHAAgK2BaGKQAqAgAHAAgK2BaGKQAqAgAQAAYKoAtaOgBKAQABNQAECgkJLgAcAKQjAA==.Stinkiepete:BAAANQAECgIIAgAAAA==.',
Su='Sureno:BAAANQAECgYIEwAAAA==.',
Sw='Swaglordxtqt:BAAANQAECgMIAgAAAA==.',
Sx='Sxyhealz:BAAANQAECgQIBwAAAA==.Sxyheålz:BAABNQAECoEqAAIFAAkKjxe+KQCkAgAFAAkKjxe+KQCkAgAAAA==.',
Ta='Taanis:BAAANQAECgEIAQAAAA==.Taliä:BAAANQADCgcIDAAAAA==.Tanndari:BAAANQAECgEIAgAAAA==.Tartare:BAAANQAECgcIDAAAAA==.Tashaman:BAACNQAFFIEJAAMIAAUKowyDCwBxAQAIAAUKowyDCwBxAQAJAAEKBwHHLgAzAAA1AAQKgTUAAwgACQqgFPZKAAsCAAgACQqgFPZKAAsCAAkABQqaBY3AAOIAAAAA.',
Te='Teajuan:BAAANQADCgcIBwAAAA==.Tenderheart:BAAANQABCgIIAgAAAA==.Tenzin:BAAANQAECgEIAQAAAA==.Teriheals:BAAANQAECgIIBgAAAA==.',
Th='Thejorlane:BAAANQADCgcIGgAAAA==.Thiccholy:BAACNQAFFIELAAMdAAQKqAwcDwAzAQAdAAQKqAwcDwAzAQARAAIKfwLzDABOAAA1AAQKgSYABB0ACQrpFpZGAC0CAB0ACArOFZZGAC0CABEACQqcDYIjAJgBABIABAohDH0aAbsAAAAA.Thiccshields:BAAANQADCgQIBAABNQAFFAQICwAdAKgMAA==.Thicctotemz:BAAANQAECgUIDAABNQAFFAQICwAdAKgMAA==.Thogo:BAABNQAECoEmAAIlAAgKAiDjAwDmAgAlAAgKAiDjAwDmAgAAAA==.',
Ti='Tikaa:BAAANQAECgQIBwAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAABNQAECoEkAAIRAAkK4iSmBABXAwARAAkK4iSmBABXAwABNQAFFAUIBgAWAKsVAA==.Tomerto:BAABNQAECoElAAMdAAgK1xrvMACHAgAdAAgK1xrvMACHAgASAAUKogqP+wDuAAAAAA==.Toobeastly:BAABNQAECoEeAAQJAAkKxh9tHgD5AgAJAAgKdiFtHgD5AgAKAAQKMRWCHgA+AQAIAAEKRhWMBAEyAAAAAA==.Toonerdin:BAAANQAECgUIEgAAAA==.Toymonkey:BAAANQADCggIDQAAAA==.',
Tr='Tril:BAAANQAECgIJBAAAAA==.Trolazo:BAAANQADCgIIAgAAAA==.Trox:BAAANQADCgcIEwAAAA==.Trydrodruid:BAAANQAECgYIDwABNQAECggIBwANAAAAAA==.Tryingmybest:BAACNQAFFIEOAAIFAAQKeByZDgCBAQAFAAQKeByZDgCBAQA1AAQKgSYABAUACQqNJJkGAIIDAAUACQqNJJkGAIIDACYABwpeGkAGABYCAAsAAQrVCOx2ACYAAAAA.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCgYIBgABNQAECgIIAwANAAAAAA==.',
Ty='Tydrodh:BAAANQAECggIBwAAAQ==.Tydroshaman:BAAANQADCgUIBQAAAA==.Tyestaumin:BAAANQADCgcIBwABNQAECgIIBQANAAAAAA==.Tyralen:BAABNQAECoEnAAIcAAgKwBegSQBqAgAcAAgKwBegSQBqAgAAAA==.Tyrandras:BAABNQAECoEgAAIbAAgKThJGFgDBAQAbAAgKThJGFgDBAQABNQAECggIJwAcAMAXAA==.Tyronnius:BAAANQAECgMJBgAAAA==.Tyrïon:BAABNQAECoEsAAIPAAkKMCOAEwBkAwAPAAkKMCOAEwBkAwAAAA==.',
Un='Unforgiven:BAAANQAECggIBgAAAA==.Unlyfe:BAAANQAECgQIBgAAAA==.Unnamed:BAAANQAECgEIAQABNQAFFAQIDgAFAHgcAA==.',
Va='Vaero:BAABNQAECoEcAAIQAAgKFR8MEQDUAgAQAAgKFR8MEQDUAgAAAA==.Vampirate:BAAANQADCgcIBwAAAA==.Vandenar:BAAANQAECgEIBAAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAFFAYIDQATAOUJAA==.Velyssa:BAAANQAECgUIEgAAAA==.',
Vi='Vibin:BAABNQAECoEkAAIfAAgKxBxNDwChAgAfAAgKxBxNDwChAgAAAA==.Vineeshewah:BAAANQAECgUIEgAAAA==.',
Vo='Voidguy:BAAANQAECgUIDQAAAA==.',
Vu='Vulsted:BAAANQADCggIFwAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
Wa='Wantedd:BAAANQAECgYIDgABNQAECgkJKQAIADgdAA==.',
Wh='Whalend:BAAANQADCgYIBgAAAA==.Whatapal:BAAANQAECgQICwAAAA==.',
Wi='Wilbo:BAABNQAECoEWAAIJAAkKDxaMPwBNAgAJAAkKDxaMPwBNAgABNQAFFAYIFgAYAJ4TAA==.Wily:BAAANQAECgMIBAAAAA==.Wisperwing:BAAANQAECgUIEwAAAA==.',
Wo='Wolfdrudu:BAAANQAECgUIEAAAAA==.Wordbet:BAAANQADCgcIBwAAAA==.Worldfire:BAAANQAECgYICQAAAA==.Wormadina:BAAANQAECgMICQAAAA==.Wormszer:BAAANQAECgQICQAAAA==.Wotan:BAAANQADCgIJAgAAAA==.Woth:BAAANQADCggIDgAAAA==.',
Wr='Wrâîth:BAAANQADCgYICwABNQAECgUIDgANAAAAAA==.',
Wy='Wynds:BAACNQAFFIEUAAIfAAYKESZIAQCqAgAfAAYKESZIAQCqAgA1AAQKgTEAAh8ACQr4JgkAABMEAB8ACQr4JgkAABMEAAAA.Wyngs:BAABNQAECoEUAAIdAAcKZCXrGgD2AgAdAAcKZCXrGgD2AgABNQAFFAYIFAAfABEmAA==.',
Xe='Xeres:BAAANQABCgIJBAAAAA==.',
Xi='Xi:BAABNQAECoEgAAIfAAgKmg0nHwDAAQAfAAgKmg0nHwDAAQAAAA==.Xiaozhi:BAEANQAECgUIEgAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAAANQAECgYIDwAAAA==.',
Yo='Yodda:BAAANQADCgUIBQAAAA==.Yoirr:BAAANQAECgMIBgAAAA==.',
['Yë']='Yëëter:BAAANQADCgUICQAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECgcIEAANAAAAAA==.Zanori:BAABNQAECoEjAAQXAAkKTA5JMgDcAQAXAAkKTA5JMgDcAQAYAAUKLgZvjwDFAAAWAAEKbhEovQAwAAAAAA==.Zansijo:BAAANQADCgUIBQABNQAECgkJIwAXAEwOAA==.',
Ze='Zellyne:BAAANQAECgcICwABNQAFFAUIDAAfAPgVAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAABNQAECoEyAAIcAAkKbiREDgBcAwAcAAkKbiREDgBcAwAAAA==.Zoyn:BAAANQAECgEIAgAAAA==.',
Zy='Zygo:BAAANQAECgIIAgAAAA==.',
['Ár']='Áries:BAAANQAECgMICQAAAA==.',
['Åm']='Åmnèsia:BAAANQADCgUIBQAAAA==.',
['Êv']='Êvelyn:BAAANQADCggIHAAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQANAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQANAAAAAA==.',
['Ýu']='Ýuno:BAAANQADCgYIDgAAAA==.',
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
