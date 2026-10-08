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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','Priest-Holy','Unknown-Unknown','Evoker-Preservation','Paladin-Holy','Warrior-Arms','Druid-Balance','Shaman-Restoration','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Monk-Brewmaster','Warlock-Destruction','Shaman-Enhancement','Warlock-Demonology','Druid-Feral','Paladin-Retribution','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Shaman-Elemental','Priest-Shadow','Druid-Restoration','Priest-Discipline','DemonHunter-Devourer','Hunter-BeastMastery','Monk-Mistweaver','Druid-Guardian','Evoker-Devastation','Monk-Windwalker','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aairidari:BAABNQAECoEZAAMBAAcKowZ7SgBAAQABAAcKowZ7SgBAAQACAAEK3QSCMAAfAAAAAA==.',
Ab='Abruna:BAAANQAECgcIEAABNQAFFAUIDAADAFATAA==.Abruno:BAACNQAFFIEMAAIDAAUKUBM4FwCXAQADAAUKUBM4FwCXAQA1AAQKgScAAwMACQoNIwUxAB4DAAMACQo3IgUxAB4DAAQAAQpaHQAAAAAAAAAA.Abruto:BAAANQAECgQIBAABNQAFFAUIDAADAFATAA==.',
Ae='Aeown:BAAANQAECgIIAwABNQAECggILAAFACcOAA==.Aerdis:BAAANQADCggIFQABNQAECgUIDAAGAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Al='Alandrìas:BAABNQAECoEeAAICAAgKmgcDFAA5AQACAAgKmgcDFAA5AQAAAA==.Altera:BAABNQAECoEaAAIHAAcK6BE7IgCYAQAHAAcK6BE7IgCYAQAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgQIBAAAAA==.Androo:BAAANQAECgYIBgABNQAFFAUIDAAIAMwVAA==.Androonatorz:BAACNQAFFIEMAAIIAAUKzBWECACxAQAIAAUKzBWECACxAQA1AAQKgSMAAggACQrTICAeAOMCAAgACQrTICAeAOMCAAAA.Anfernay:BAABNQAECoEdAAIJAAkKfxLGZgA8AgAJAAkKfxLGZgA8AgAAAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAAANQAECgcICgABNQAFFAUICwAKAF0SAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQADCgYIBgAAAA==.Arveiturace:BAAANQAECgMIAwAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECoEiAAIJAAcKzRJWlADBAQAJAAcKzRJWlADBAQAAAA==.Asukajo:BAAANQADCgMIAwAAAA==.',
At='Attack:BAAANQAECgUICAAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICQAAAA==.Barrin:BAAANQAECgUIBQAAAA==.',
Be='Bearlyseen:BAAANQAECgcIEwABNQAFFAMIBwALAC4KAA==.Beltirra:BAAANQADCggIFwAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Biggums:BAAANQAECgMIAwAAAA==.Bigmobility:BAABNQAECoEjAAIMAAgKbSNmDgArAwAMAAgKbSNmDgArAwAAAA==.Bigwill:BAABNQAECoEmAAIEAAgKZSIkAwD9AgAEAAgKZSIkAwD9AgAAAA==.',
Bl='Blargy:BAABNQAECoEqAAIKAAkKBxjiIgCZAgAKAAkKBxjiIgCZAgAAAA==.Bleach:BAAANQAECgUICAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQADCgYIBgABNQADCgYIEQAGAAAAAA==.Brimara:BAAANQAECgUIDAAAAA==.Brothaagamor:BAAANQADCgIIAgAAAA==.',
Bu='Bucketojoy:BAAANQAECgcIEgAAAA==.',
['Bà']='Bàtman:BAAANQAECgQIBwAAAA==.',
Ca='Caliburne:BAABNQAECoEpAAQJAAgKEx5TTQCHAgAJAAgK9RxTTQCHAgANAAMKlh8FFgAZAQAOAAMK3R0+JQDpAAAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFIEVAAIJAAcKFCHYAgCcAgAJAAcKFCHYAgCcAgA1AAQKgSAAAgkACQqtJf0YAEkDAAkACQqtJf0YAEkDAAAA.',
Ce='Cedrin:BAAANQADCgcIFQAAAA==.Ceez:BAAANQAECgQIBgAAAA==.Ceezinator:BAAANQADCgQIBAAAAA==.',
Ch='Chichujongar:BAAANQAECgcICAABNQAFFAUICwAPABoIAA==.Chickenstwip:BAAANQADCgEIAgABNQAECgkJIwADAE4aAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgYIDgAAAA==.',
Ci='Cindrella:BAABNQAECoEnAAIEAAkKeCV6AADCAwAEAAkKeCV6AADCAwAAAA==.',
Cl='Clayre:BAACNQAFFIEGAAIQAAMK4w+rAgDnAAAQAAMK4w+rAgDnAAA1AAQKgToAAhAACQpHI6YAALADABAACQpHI6YAALADAAAA.Clow:BAAANQAECgQICQAAAA==.',
Co='Colossus:BAAANQAECgEIAgAAAA==.Coolcrush:BAAANQADCgMIBgABNQAECggIIAARAJokAA==.Corven:BAACNQAFFIEMAAISAAUKYxWSCQCkAQASAAUKYxWSCQCkAQA1AAQKgTQAAxIACQp1I9sIAHUDABIACQp1I9sIAHUDABAAAQpFBSx+ACUAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAACNQAFFIEKAAIJAAUKnxkKDQCvAQAJAAUKnxkKDQCvAQA1AAQKgR8AAgkACQrcIaokABcDAAkACQrcIaokABcDAAAA.Crönus:BAAANQADCggIEwAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAAANQAECgYIDwAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAGAAAAAA==.Darfur:BAAANQAECggIBAAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQADCgQJBwAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECoEkAAIJAAgKER9XRwCbAgAJAAgKER9XRwCbAgABNQAFFAEIAQAGAAAAAA==.Deadshot:BAAANQAECgQIBAAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgcICAABNQAECggIFgADAJUgAA==.Demonbulio:BAAANQAECgYICQAAAA==.Demonisthicc:BAABNQAECoEpAAITAAgKVx26BwCxAgATAAgKVx26BwCxAgAAAA==.Demonslayeer:BAAANQADCggJDQAAAA==.Devi:BAAANQAECgUICwAAAA==.',
Di='Diaravynn:BAAANQADCgIIAgAAAA==.Dithehealer:BAABNQAECoEcAAIUAAcKtBaskQDMAQAUAAcKtBaskQDMAQAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQADCggIFwAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQAECgMIBwAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECoEaAAIJAAgKXBYlagAzAgAJAAgKXBYlagAzAgAAAA==.Dunbroch:BAACNQAFFIESAAIVAAYKTBNgBQDjAQAVAAYKTBNgBQDjAQA1AAQKgSkAAhUACQqEHfYQAM0CABUACQqEHfYQAM0CAAAA.Duskforge:BAAANQABCgIJAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBAAAAA==.',
['Dé']='Démonicblood:BAABNQAECoEfAAIWAAkKyRoPGgCTAgAWAAkKyRoPGgCTAgAAAA==.',
Eg='Eggplantgodx:BAABNQAECoEkAAMCAAgKCyHkBQCdAgACAAcKuyDkBQCdAgABAAgK0xhfJwA5AgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAACNQAFFIELAAIXAAUKeQ6xBQCVAQAXAAUKeQ6xBQCVAQA1AAQKgSUAAxcACQouHYkTAL4CABcACQouHYkTAL4CABgACAr6DRAuADIBAAAA.',
Em='Emmy:BAAANQAECgQIDwAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAABNQAECoEjAAMDAAkKThqmXgCvAgADAAkKThqmXgCvAgAEAAMK8w42JgCdAAAAAA==.Emowrecky:BAABNQAECoEYAAMSAAcKLRuQVwAuAgASAAcKLRuQVwAuAgAQAAEKYwy3cAA4AAAAAA==.',
En='Endo:BAACNQAFFIEJAAMZAAUKQRjeCABiAQAZAAQKvRveCABiAQAWAAMKaQ8fDADTAAA1AAQKgS0AAxkACQr2JIUXAOcCABkACAoiJIUXAOcCABYABwr1IDMkAEECAAAA.Endorush:BAABNQAECoEZAAIBAAgKTB+vFQDQAgABAAgKTB+vFQDQAgABNQAFFAUICQAZAEEYAA==.Endrigosa:BAAANQAECgIIAgAAAA==.Eneldenes:BAAANQAECgQIBgAAAA==.Enjoyer:BAAANQAECgcIDAAAAA==.',
Er='Ereitherla:BAAANQAECgUIDQAAAA==.',
Es='Esmenet:BAAANQAECgYICwAAAA==.Espressð:BAAANQAECgYIDgABNQAECgkJIwADAE4aAA==.',
Ex='Excalibear:BAAANQAECgUIDQABNQAFFAMIBwALAC4KAA==.',
Ey='Eydis:BAAANQADCgcIDgAAAA==.',
Fe='Feironor:BAAANQAECgMIAwAAAA==.Fenrys:BAAANQAECgEIAQAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAGAAAAAA==.',
Fl='Flayre:BAABNQAECoEhAAMLAAgK8RyVOABVAgALAAcKFx2VOABVAgAaAAcKcBNNaAC3AQAAAA==.Fleredil:BAABNQAECoEhAAMbAAgKUyHnDQD4AgAbAAgKUyHnDQD4AgAFAAEKgQWe4wAuAAAAAA==.Flingernle:BAABNQAECoEWAAIaAAcK3x+SNgB2AgAaAAcK3x+SNgB2AgAAAA==.',
Fo='Forepray:BAACNQAFFIEKAAIbAAQK4A9wCQA0AQAbAAQK4A9wCQA0AQA1AAQKgSkAAhsACQp3H+ULABMDABsACQp3H+ULABMDAAAA.Forger:BAABNQAECoEdAAMOAAgKBwtRGgBjAQAOAAgKFQpRGgBjAQAJAAIKQQjEHQFhAAAAAA==.Forsakey:BAAANQADCggIFAABNQAFFAUICgAcABAbAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.Freshdk:BAAANQAECgQIBAAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIAQAAAA==.Furioustotem:BAAANQAECgUIDQAAAA==.Future:BAAANQADCgUIBgABNQAECgkJLAADADYkAA==.',
Ga='Galten:BAAANQABCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgkJIwADAE4aAA==.',
Gh='Ghettox:BAAANQADCgIIAgAAAA==.Ghostw:BAAANQAECgQICwAAAA==.',
Gi='Giovanni:BAAANQAECggICAAAAA==.Gizik:BAAANQADCgcICAABNQAFFAYIFQAbAJUVAA==.',
Gn='Gnasher:BAAANQABCgQIBAAAAA==.',
Go='Golgotterath:BAACNQAFFIEHAAILAAMKLgoNFADfAAALAAMKLgoNFADfAAA1AAQKgS0AAwsACQpyHMA7AEgCAAsACQpyHMA7AEgCABoAAQqNB5wUATQAAAAA.Gorm:BAABNQAECoEZAAIDAAgKyxofaACZAgADAAgKyxofaACZAgABNQAECgQIBQAGAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgkJGwABAMQgAA==.',
Ha='Halbruck:BAAANQAECgcIEQAAAA==.Haldane:BAABNQAECoEnAAIUAAgKUgrFsACEAQAUAAgKUgrFsACEAQABNQAFFAEIAQAGAAAAAA==.Harrydottur:BAAANQAECgYIBgABNQAECgkJLwASAMsfAA==.Havochunter:BAAANQAECgMIBQAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAACNQAFFIELAAIdAAUKfh+RAADgAQAdAAUKfh+RAADgAQA1AAQKgSgAAx0ACQqwJPwAAFIDAB0ACArgJPwAAFIDAAUACAotIjg8AFUCAAAA.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAAANQAECggIEwAAAA==.Hephsdh:BAAANQAECgIIAwAAAA==.Heraois:BAAANQAECgYIEgAAAA==.Heriod:BAAANQABCgEIAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQADCggIFQAAAA==.Holywráth:BAAANQADCgQICgAAAA==.',
Hu='Hunterdh:BAAANQAECgUICwAAAA==.',
Hy='Hynixx:BAABNQAECoEYAAMNAAgKgBlCBwBeAgANAAgK+xhCBwBeAgAJAAQKDhI+1gALAQABNQAFFAQICgAbAOAPAA==.',
Il='Illidope:BAABNQAECoEbAAQBAAkKxCAiEAAIAwABAAkKpiAiEAAIAwAeAAgKgBueHABTAgACAAEKFBkMKABHAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Innervatez:BAABNQAFFIELAAIcAAUKJCP0AgD6AQAcAAUKJCP0AgD6AQAAAA==.Inteaus:BAAANQADCggIGgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgMIBQAAAA==.',
Ja='Jaekir:BAABNQAECoEbAAIEAAgKHhb6CAAZAgAEAAgKHhb6CAAZAgAAAA==.Jakfrost:BAABNQAECoEWAAMDAAgKlSDyewBvAgADAAcKpiDyewBvAgAEAAEKHyDuMwBUAAAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAJAM4YAA==.Jarten:BAACNQAFFIEGAAIWAAMKGBgvCgD0AAAWAAMKGBgvCgD0AAA1AAQKgS4AAhYACQpPH1gNABEDABYACQpPH1gNABEDAAAA.Jayaah:BAAANQADCggIFwAAAA==.Jaylebate:BAAANQAECgQIBwAAAA==.',
Je='Jerrenn:BAAANQADCgIIAgAAAA==.Jesseatamer:BAACNQAFFIEGAAIfAAMKjhsvEAAXAQAfAAMKjhsvEAAXAQA1AAQKgSwAAh8ACQp5JKwGAJ0DAB8ACQp5JKwGAJ0DAAAA.',
Ji='Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgkJKwAJALcVAA==.Jstrawr:BAABNQAECoErAAIJAAkKtxWvVABwAgAJAAkKtxWvVABwAgAAAA==.',
Ka='Kalmek:BAAANQAECgcIBwAAAA==.Kaln:BAAANQAECgIIBAABNQAECgQIBQAGAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kastia:BAAANQAECgIIAgAAAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQADCggIKQAAAA==.',
Ke='Keliki:BAABNQAECoEeAAMaAAgK1hq9NAB/AgAaAAgK1hq9NAB/AgALAAMKdQ452ACOAAAAAA==.Kellenah:BAAANQADCgYICwAAAA==.Kettama:BAAANQADCggIEAABNQAECgkJIwADAE4aAA==.',
Kh='Khold:BAABNQAECoEXAAIWAAgKDh0kIABgAgAWAAgKDh0kIABgAgAAAA==.Khrogann:BAAANQAECgUICgAAAA==.',
Ki='Kijana:BAAANQADCggICAAAAA==.Killalltoday:BAABNQAECoEbAAILAAcKcRMqZwCoAQALAAcKcRMqZwCoAQAAAA==.Kirkk:BAAANQAECgEIAQAAAA==.',
Kl='Klaminus:BAAANQADCgQJBAABNQAECgIIAgAGAAAAAA==.',
Kn='Knixx:BAACNQAFFIEMAAIFAAUKsRAoDQCUAQAFAAUKsRAoDQCUAQA1AAQKgTcAAwUACQprJR8CAMADAAUACQprJR8CAMADAB0ABgrzEYoNAEUBAAAA.Knuppelus:BAAANQADCgYIDAAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECggIGgAJAFwWAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAAANQAECgYIDQAAAA==.',
Kr='Krathos:BAAANQAECgIIAgAAAA==.Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQAECgIIAgAAAA==.',
Ku='Kufoo:BAABNQAECoEcAAINAAgKQyQvAgBDAwANAAgKQyQvAgBDAwAAAA==.Kurao:BAAANQAECgEJAgAAAA==.Kurukai:BAAANQADCgIIAgAAAA==.',
Ky='Kyrian:BAACNQAFFIESAAMYAAUKoh1jBADWAQAYAAUKfB1jBADWAQAXAAMKvREQCwD5AAA1AAQKgSkAAxgACQreImQEAEYDABgACQreImQEAEYDABcAAwpZHLhaAP0AAAAA.',
La='Lagøless:BAABNQAECoEdAAIfAAkKYSFtDQBiAwAfAAkKYSFtDQBiAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Liatris:BAAANQAECgUIBQAAAA==.Likestoflash:BAEANQADCgYJBgABNQAECgkJLAAfAE0fAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECoEgAAISAAgKgxkZSwBUAgASAAgKgxkZSwBUAgAAAA==.Lohmi:BAAANQAECgQIDgAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQAECgIIAgAAAA==.',
Ly='Lyna:BAAANQADCggJDAAAAA==.Lyravega:BAAANQADCggICAAAAA==.Lyshkä:BAABNQAECoEmAAIgAAgKtRrgDgBtAgAgAAgKtRrgDgBtAgAAAA==.Lyzzardkng:BAAANQAECgcIEwAAAA==.',
['Lý']='Lýra:BAAANQAECgQIBwAAAA==.',
Ma='Maango:BAAANQAECggIEAAAAA==.Maemu:BAAANQABCgUIBQAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAAANQAECgcIEwAAAA==.Magiki:BAAANQADCgcICwAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgYIBAAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Mando:BAAANQAECgIIAgABNQAECgUIDQAGAAAAAA==.Manical:BAAANQAECgMIBQAAAA==.Marcel:BAAANQADCgYIEQAAAA==.Mashiach:BAACNQAFFIEGAAIFAAQK2xJXEgBDAQAFAAQK2xJXEgBDAQA1AAQKgSQAAwUACQpnI2ELAFUDAAUACQpnI2ELAFUDABsAAQpdEzxrADcAAAAA.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgQIBwABNQAECggIJwAUAC4jAA==.Melikefire:BAABNQAECoEbAAIDAAkKWRhNgQBjAgADAAkKWRhNgQBjAgAAAA==.Memecompdall:BAAANQADCggIDgAAAA==.Merek:BAAANQAECgYIEwAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgkJJwAEAHglAA==.Mistybdk:BAAANQAECgcIDAABNQAFFAYIFAAhAMQYAA==.Mistyd:BAACNQAFFIEUAAIhAAYKxBizAAD6AQAhAAYKxBizAAD6AQA1AAQKgTMAAiEACQpHJK4BALMDACEACQpHJK4BALMDAAAA.',
Mo='Mogfooyen:BAAANQABCgQIBgAAAA==.Moonbeam:BAAANQAECgIIAgAAAA==.Morgause:BAAANQAECgUICgAAAA==.Morllan:BAABNQAECoEZAAISAAgKwQ1zeADPAQASAAgKwQ1zeADPAQAAAA==.',
Mu='Muirdin:BAAANQADCgEJAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQADCgcICQAAAA==.',
['Mé']='Mélusine:BAABNQAECoEWAAMJAAgK4xJLhgDnAQAJAAgKkg9LhgDnAQANAAQKHRG7GQDjAAAAAA==.',
Na='Naanomage:BAAANQAECgIIAgAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECoEnAAIeAAkKmSLPBACAAwAeAAkKmSLPBACAAwAAAA==.Nirath:BAABNQAECoEbAAIiAAcK1AOtIgATAQAiAAcK1AOtIgATAQAAAA==.',
No='Noiire:BAAANQAECgcICQABNQAFFAUICwAXAHkOAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAABNQAECoEYAAIfAAgKbR4HMwCwAgAfAAgKbR4HMwCwAgAAAA==.',
Oi='Oio:BAAANQADCgQIBAAAAA==.',
Ok='Okami:BAAANQAECgQICwAAAA==.',
Oo='Ooyagoddess:BAAANQADCgIIAwAAAA==.',
Pa='Pacamonk:BAABNQAECoEhAAIjAAkKrh9GCgAYAwAjAAkKrh9GCgAYAwAAAA==.Palenar:BAAANQADCgIIAgAAAA==.Papatiny:BAAANQAECgUIBQAAAA==.Pawsa:BAAANQAECgQIBgABNQAECgkJIwADAE4aAA==.Pawthetic:BAACNQAFFIELAAMKAAUKXRLFDwA0AQAKAAQKexTFDwA0AQAcAAEKVw7REABOAAA1AAQKgS8AAwoACQokHmkZAOICAAoACQokHmkZAOICABwACAoPIPMNANUCAAAA.',
Pe='Peelforheals:BAABNQAECoEsAAMbAAkK9B4FDAARAwAbAAkK9B4FDAARAwAdAAQKuAv3FAC/AAAAAA==.Penguindemic:BAABNQAECoEYAAMSAAgK9ySbDgBIAwASAAgK9ySbDgBIAwAQAAEKoCIhZABPAAAAAA==.Pep:BAAANQAECgYIDQAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQIBgAAAA==.Petruccius:BAACNQAFFIELAAIKAAMK0hQZEwD4AAAKAAMK0hQZEwD4AAA1AAQKgTsAAgoACQoiIfwKAGcDAAoACQoiIfwKAGcDAAAA.Pewpewlepew:BAAANQAECgQICQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAGAAAAAA==.',
Pl='Plague:BAAANQAECgMIAwAAAA==.',
Po='Poptartsz:BAAANQAECgQICQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Prayre:BAAANQADCgYIBgAAAA==.Precht:BAAANQADCggIFAAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prumper:BAABNQAECoEYAAIDAAgKThO3qgALAgADAAgKThO3qgALAgAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
Qu='Quesoblanco:BAAANQAECgYIEgAAAA==.',
Qy='Qybxboogietk:BAABNQAECoEUAAIBAAcKXxNjNwDCAQABAAcKXxNjNwDCAQAAAA==.',
Ra='Rabid:BAAANQAECgQIBAAAAA==.Raeliana:BAAANQADCgIIAgAAAA==.Raghallov:BAAANQAECgIIBAAAAA==.Rampa:BAAANQADCgYIEQABNQAECgkJIwADAE4aAA==.',
Rd='Rdub:BAAANQADCgUIBQAAAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECoEsAAMFAAgKJw6LYgDGAQAFAAgKJw6LYgDGAQAbAAIKaAIuZgBCAAAAAA==.Remorse:BAACNQAFFIEMAAIOAAUKJxATAgBVAQAOAAUKJxATAgBVAQA1AAQKgTkAAg4ACQomIogFAPkCAA4ACQomIogFAPkCAAAA.Rendwick:BAAANQADCgYICQAAAA==.Required:BAAANQAECgUIBQABNQAFFAYIEQABAJceAA==.',
Ri='Riker:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.Rim:BAABNQAECoEgAAILAAgKvxywLACLAgALAAgKvxywLACLAgAAAA==.',
Ro='Ronfar:BAACNQAFFIEIAAIRAAMKSBgTAwAbAQARAAMKSBgTAwAbAQA1AAQKgTgAAhEACQoQIx4CAI4DABEACQoQIx4CAI4DAAAA.',
Ru='Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAAANQAECgcIDQAAAA==.Ryù:BAAANQADCggIIAAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgMIBQAAAA==.Saviorself:BAAANQADCgMIAwABNQAFFAUICwAKAF0SAA==.',
Sc='Scarscar:BAAANQAECgUICAAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAAANQAECgYIDAAAAA==.Selen:BAAANQAECgcIEQAAAA==.Semballin:BAAANQABCgMJAwAAAA==.Seswatha:BAAANQAECgUIBQABNQAFFAMIBwALAC4KAA==.',
Sh='Shamandroo:BAAANQAECggIEQABNQAFFAUIDAAIAMwVAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMJAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgcIDAAGAAAAAA==.Shortandold:BAAANQAECgYIDAAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAABNQAECoEjAAIcAAgKzRxvEAC1AgAcAAgKzRxvEAC1AgAAAA==.',
Si='Sightofhand:BAAANQADCgQIBAAAAA==.Sintram:BAAANQAECgMIAwAAAA==.',
Sl='Slighted:BAAANQAECgMIAwABNQAECgYIDQAGAAAAAA==.Slimydruid:BAAANQAECgQIBgAAAA==.Slow:BAABNQAECoEsAAIDAAkKNiR2EwB/AwADAAkKNiR2EwB/AwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgkJIwADAE4aAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAAANQAECgYIDgAAAA==.Sonicberger:BAAANQADCgYIGQABNQAECgYIEgAGAAAAAA==.Soniko:BAAANQAECgYIDQAAAA==.Sonícberger:BAAANQAECgYIEgAAAA==.Soulcaliber:BAAANQADCgQIBAAAAA==.',
St='Stain:BAAANQAECgQJCAAAAA==.Stealth:BAAANQAECgQIBAABNQAECgcIGwAkAK4dAA==.Stinkfist:BAAANQADCgcIEQAAAA==.Stonehenge:BAAANQAFFAEIAQAAAA==.Stonepalm:BAAANQADCgYIFAAAAA==.Stratan:BAAANQAECgIIAgAAAA==.Strawk:BAABNQAECoEUAAIaAAcKOw6SbwChAQAaAAcKOw6SbwChAQAAAA==.',
Su='Subbzero:BAAANQADCgEIAQAAAA==.Suffer:BAAANQADCggICQABNQAECgkJLAADADYkAA==.Sunlight:BAAANQADCgYIBgAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgQIBwAAAA==.',
Sw='Swankydranky:BAACNQAFFIELAAQPAAUKGgi1BAAQAQAPAAUKZAW1BAAQAQAjAAEKhhYuEQBHAAAgAAEKVgArDAArAAA1AAQKgSgABA8ACQrFFRQQAMcBAA8ACAqBExQQAMcBACMACQoGE60sAIEBACAAAQr2AuVMAB8AAAAA.Swankypally:BAAANQAECgcICgABNQAFFAUICwAPABoIAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQADCgYIDgABNQAECgcIEQAGAAAAAA==.',
Ta='Tabbz:BAABNQAECoEYAAIaAAcKmhk9VAD7AQAaAAcKmhk9VAD7AQAAAA==.Tallael:BAABNQAECoEXAAIRAAgKTw1mEwAMAgARAAgKTw1mEwAMAgAAAA==.Tallyhochick:BAABNQAECoEgAAIfAAgKmg8saAAYAgAfAAgKmg8saAAYAgAAAA==.Taman:BAABNQAECoEbAAILAAgKNx0MNABpAgALAAgKNx0MNABpAgAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAAANQAECgcIDQAAAA==.Thebigonion:BAAANQADCgcIFwAAAA==.Theexile:BAABNQAECoEhAAMXAAgKMhqoIgBEAgAXAAgKCxaoIgBEAgAYAAYKVRhqHgDJAQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECgUIBwABNQAECggIJgAZAOAkAA==.',
Ti='Tinydeath:BAABNQAECoEfAAIMAAgKARWWPwDhAQAMAAgKARWWPwDhAQAAAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAABNQAECoEYAAMfAAcKShoZZgAdAgAfAAcK5RkZZgAdAgAlAAIKJxAADgCOAAABNQAECggIHwAMAAEVAA==.',
Tm='Tmakrist:BAAANQAECgEIAwAAAA==.',
To='Toko:BAACNQAFFIEHAAIfAAMKzxiMEQAIAQAfAAMKzxiMEQAIAQA1AAQKgSYAAh8ACQrQI14WACoDAB8ACQrQI14WACoDAAAA.Tomblord:BAAANQAECgcIEQAAAA==.',
Tr='Trailblazah:BAAANQAECgUICAAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECgcIGwAkAK4dAA==.Truths:BAAANQADCgIJAgABNQAECgcIGwAkAK4dAA==.Truthsx:BAABNQAECoEbAAMkAAcKrh2ABABsAgAkAAcKrh2ABABsAgASAAUKqQ7rxgAPAQAAAA==.Truthy:BAAANQADCgYICAABNQAECgcIGwAkAK4dAA==.Truthz:BAAANQADCgYJBgABNQAECgcIGwAkAK4dAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIDAAAAA==.Tylaatape:BAAANQAECggIEAAAAA==.Tyraell:BAAANQAECgcIDQAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAMIBwAfAM8YAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgQICQAGAAAAAA==.',
Us='Usgasdanelv:BAABNQAECoEZAAIRAAkK5hg+CgC8AgARAAkK5hg+CgC8AgAAAA==.',
Uz='Uzala:BAAANQAECgQIBgAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAABNQAECoElAAMIAAgKlhNhVQD5AQAIAAgKlhNhVQD5AQAUAAYKMga67wADAQAAAA==.',
Ve='Vendiyre:BAAANQAECgYIBgAAAA==.Venthyl:BAACNQAFFIEGAAIKAAQKjxloDgBQAQAKAAQKjxloDgBQAQA1AAQKgSMAAgoACQoRJSwIAIMDAAoACQoRJSwIAIMDAAAA.Veyra:BAAANQABCgMIAwAAAA==.',
Vi='Vizan:BAAANQABCgcIBwABNQAECgcIGwAkAK4dAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQAECgEIAQAAAA==.Westerin:BAABNQAECoEZAAIQAAcKzxO8EgDTAQAQAAcKzxO8EgDTAQAAAA==.',
Wi='Wildnature:BAAANQADCggIDgAAAA==.Wimateeka:BAABNQAECoEcAAMUAAcKURWIkADPAQAUAAcKURWIkADPAQAIAAIKggWF+ABSAAAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJLAADADYkAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAFFAUICwAKAF0SAA==.',
Wo='Wooqles:BAAANQADCgUIBQABNQADCgYICAAGAAAAAA==.',
Wr='Wrastelas:BAAANQABCgEIAQABNQADCgQIBAAGAAAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.Wurkim:BAAANQADCgQIBAAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgQICQAGAAAAAA==.',
Ye='Yespaladin:BAACNQAFFIEGAAIMAAMKlRlWFADhAAAMAAMKlRlWFADhAAA1AAQKgS0AAgwACQrtH/UOACQDAAwACQrtH/UOACQDAAAA.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFIEKAAILAAQK/xPKDQBBAQALAAQK/xPKDQBBAQA1AAQKgSYAAgsACQodId8eANICAAsACQodId8eANICAAAA.Yozomoto:BAACNQAFFIELAAIfAAUK4RwKBgDIAQAfAAUK4RwKBgDIAQA1AAQKgSsAAx8ACQoCJMgbAA8DAB8ACQoCJMgbAA8DABUAAgoRDKtoAGUAAAAA.',
Za='Zalandria:BAAANQAECgUIDAAAAA==.',
Ze='Zeltemis:BAABNQAECoEXAAIfAAgKDQvwdgDzAQAfAAgKDQvwdgDzAQAAAA==.',
Zi='Zipsion:BAABNQAECoEhAAIfAAgKPCLEFwAjAwAfAAgKPCLEFwAjAwAAAA==.Zivver:BAABNQAECoEaAAIOAAcKQyJ2CACiAgAOAAcKQyJ2CACiAgAAAA==.Zizka:BAABNQAECoEbAAIbAAcKAwdBOAA8AQAbAAcKAwdBOAA8AQAAAA==.',
Zo='Zolandir:BAAANQAECgIIAgAAAA==.',
['Òh']='Òhká:BAAANQADCgMIAwAAAA==.',
['Üt']='Üther:BAABNQAECoEnAAIUAAgKLiM0IwAfAwAUAAgKLiM0IwAfAwAAAA==.',
['ßu']='ßubbleøseven:BAAANQAECgYIBwAAAA==.',
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
