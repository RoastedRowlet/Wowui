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

local lookup = {'Priest-Holy','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Shadow','Shaman-Elemental','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Preservation','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Protection','Monk-Mistweaver','Mage-Arcane','Hunter-Survival','Warrior-Arms','DeathKnight-Blood','Mage-Frost','Rogue-Outlaw','Priest-Discipline','Shaman-Restoration','Paladin-Protection',}
local provider = {region='US',realm='Aegwynn',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aarista:BAAANQADCgUIEAAAAA==.',
Ab='Abhorrere:BAAANQABCgMIAwAAAA==.Abindi:BAAANQABCgYIBgAAAA==.Abruegark:BAAANQADCgcIBwAAAA==.',
Ac='Acedririd:BAAANQAECgUIDgAAAA==.Actuallyy:BAAANQADCgEIAQAAAA==.',
Ad='Ad:BAAANQAECgUJBQAAAA==.Adönis:BAAANQADCgcJBwAAAA==.',
Ae='Aeladrine:BAAANQADCgMIAwAAAA==.Aellerr:BAAANQAECgUIBQAAAA==.',
Af='Affyou:BAAANQAECgUICgAAAA==.Afuapril:BAAANQABCgIIAgAAAA==.',
Ah='Ahriaballs:BAAANQADCgEIAQAAAA==.Ahzidal:BAABNQAECoEbAAIBAAkKyR9mDgApAwABAAkKyR9mDgApAwAAAA==.',
Ai='Ailbhe:BAAANQADCgYIBQAAAA==.Airbinwl:BAABNQAECoEYAAMCAAkKCSIfIQDNAgACAAgKkCEfIQDNAgADAAIKPSQNOQDIAAAAAA==.Aisperria:BAAANQAECgMIAwAAAA==.Aitchbar:BAAANQADCgEIAQAAAA==.',
Ak='Akanaar:BAAANQADCgUICwAAAA==.Akilleess:BAAANQAECgUIBwABNQAECgUIEgAEAAAAAA==.',
Al='Alaw:BAAANQAECgYIEAAAAA==.Alexdd:BAAANQADCgEIAQAAAA==.Alexiathorne:BAAANQADCgEIAQABNQAECgcIDQAEAAAAAA==.Alextros:BAEBNQAECoEaAAMFAAgKFiHABADsAgAFAAgKFiHABADsAgAGAAEKTAW6XAAfAAAAAA==.Alivana:BAAANQAECgUIBQAAAA==.Almaris:BAABNQAECoEsAAMHAAkKiCOcDwBvAwAHAAkKiCOcDwBvAwAIAAEKmQVk7QA2AAAAAA==.Aloreilina:BAAANQADCgMIAwAAAA==.Alèx:BAABNQAECoEbAAMJAAkKTxhmKQA+AgAJAAkKTxhmKQA+AgAKAAEK+Q0KggA3AAAAAA==.',
Am='Amarielle:BAAANQAECgUIEQAAAA==.Amire:BAAANQAECgEIAQAAAA==.Ammastolamor:BAAANQADCgIIAgAAAA==.',
An='Anags:BAAANQADCgMIAwAAAA==.Anahanu:BAABNQAECoEwAAILAAkKUSGGDABLAwALAAkKUSGGDABLAwAAAA==.Andent:BAAANQADCgUIBQAAAA==.Andrin:BAAANQAECgUICAAAAA==.Androidfine:BAEANQAECgcIBwABNQAECggIAwAEAAAAAA==.Angelawitch:BAAANQAFFAEIAQAAAA==.Angienursey:BAABNQAECoEfAAIMAAkK5B6NDADzAgAMAAkK5B6NDADzAgABNQAFFAEIAQAEAAAAAA==.Annakelly:BAAANQADCgQIBAAAAA==.Annamolly:BAAANQAECgEIAQAAAA==.Ansitris:BAAANQADCgQIBAAAAA==.Antibiotix:BAABNQAECoEgAAIJAAgKQxhgLQAkAgAJAAgKQxhgLQAkAgAAAA==.',
Ap='Apocrithon:BAAANQAECgQICAAAAA==.Apros:BAABNQAECoEhAAIHAAkKXBrxNgCuAgAHAAkKXBrxNgCuAgAAAA==.',
Aq='Aqdk:BAAANQAECgcICAABNQAECgkJHwANAEMhAA==.Aqss:BAABNQAECoEfAAINAAkKQyFHFAAsAwANAAkKQyFHFAAsAwAAAA==.',
Ar='Arakhana:BAAANQAECgEJAQAAAA==.Aralleah:BAAANQAECgcICgAAAA==.Aratoreii:BAAANQADCgIIAgAAAA==.Arbinshaman:BAAANQAECgQICAAAAA==.Archide:BAAANQAECggIDAAAAA==.Archidus:BAAANQADCgcIBwAAAA==.Arctose:BAAANQAECgcJEQAAAA==.Ardoniak:BAAANQADCggIDgAAAA==.Argenoth:BAAANQADCgUICwAAAA==.Arkaeon:BAAANQAECgUIDgAAAA==.Arlon:BAAANQABCgEIAQAAAA==.Arthar:BAAANQADCgEIAQAAAA==.Arunas:BAAANQADCgUJBQAAAA==.',
As='Asdsfe:BAAANQAECgUIEAAAAA==.Ashandrei:BAAANQAECgYIEAAAAA==.Ashletil:BAAANQADCgIJAwAAAA==.Assaelle:BAAANQADCgcIBwABNQAECgQIBAAEAAAAAA==.Astraeadawn:BAAANQADCgMIAwAAAA==.Aszkme:BAAANQADCgUIBwAAAA==.',
At='Atheniyama:BAAANQADCggICAAAAA==.Atraxia:BAAANQAECgIIAgAAAA==.Atri:BAAANQADCgUIBQABNQAECgcICgAEAAAAAA==.',
Au='Auran:BAAANQAECgQJBAAAAA==.Authority:BAABNQAECoEfAAIOAAgKfx7TJwC9AgAOAAgKfx7TJwC9AgAAAA==.Autismosteve:BAAANQAECgcIEAAAAA==.',
Av='Avanlythia:BAAANQADCgYIBgABNQAECgUIBQAEAAAAAA==.Averdeen:BAAANQADCgEIAQABNQADCgEJAQAEAAAAAA==.Avlee:BAAANQADCgQIBAAAAA==.',
Aw='Aware:BAABNQAECoEUAAMPAAgKDSEGEwCdAgAPAAgKDSEGEwCdAgAQAAYKhxumIAChAQAAAA==.Awarri:BAAANQADCgYIBgAAAA==.',
Ax='Axeron:BAAANQAECgIIAgAAAA==.',
Ay='Ayrdrek:BAAANQAECgQIBAABNQAECggIFwARAOsTAA==.',
Az='Azathox:BAAANQABCgEIAQAAAA==.Azzuhpala:BAACNQAFFIEGAAIIAAYKmwLXCQBoAQAIAAYKmwLXCQBoAQA1AAQKgR0AAggACQqfEoA2AE0CAAgACQqfEoA2AE0CAAAA.',
['Aë']='Aëlin:BAAANQADCgYIBgAAAA==.',
Ba='Baboonki:BAAANQADCgcIBwAAAA==.Baddracthyr:BAABNQAECoEoAAMSAAkK6BT8BQAnAgASAAkK6BT8BQAnAgARAAEKXgXGNQAuAAAAAA==.Balderus:BAAANQAECggIEAAAAA==.Balekrog:BAAANQADCgEJAQAAAA==.Banjophd:BAAANQAECgEIAQAAAA==.Baracus:BAAANQADCggICAAAAA==.Batareva:BAABNQAECoEkAAMLAAgKGQ/sOQDSAQALAAgKGQ/sOQDSAQATAAYKIAtsNAANAQAAAA==.Batavira:BAAANQAECgQIBAABNQAECggIJAALABkPAA==.Battlepass:BAAANQADCggICAABNQAECgYIBgAEAAAAAA==.Bayrock:BAAANQABCgIIAgAAAA==.',
Be='Beamnord:BAAANQAECgQIBgAAAA==.Beanie:BAAANQAECgUICAAAAA==.Beardlylegal:BAAANQADCgMIBQAAAA==.Bearlyere:BAAANQAECgYIDAAAAA==.Beastshine:BAAANQADCgcIFwAAAA==.Beeflight:BAAANQADCgEIAQAAAA==.Bendemus:BAABNQAECoESAAQDAAcKIQ88GgCNAQADAAcKGg48GgCNAQAUAAIKOw5pHQBbAAACAAEKhgEcIAETAAAAAA==.Bentléy:BAAANQADCgEIAQAAAA==.Berserkguts:BAAANQAECgYIEQAAAA==.Bersk:BAAANQADCgQIBAAAAA==.',
Bi='Bigdeez:BAAANQAECgEIAQABNQAECgYIEgAEAAAAAA==.Bigelroy:BAAANQADCgEJAQAAAA==.Bighippo:BAAANQADCgMIBgAAAA==.Bigker:BAAANQADCgIIAwAAAA==.Bigzaddy:BAAANQADCgYJBgAAAA==.Bigzas:BAAANQAECgIIBAABNQAECgQIDAAEAAAAAA==.Billï:BAAANQAECgUIBwAAAA==.Bitrot:BAABNQAECoEWAAMCAAkKthwvQQBPAgACAAcKYBwvQQBPAgADAAIK4x1TQQCpAAAAAA==.',
Bl='Blameray:BAAANQADCggICAAAAA==.Blindbuns:BAAANQAECgEIAQAAAA==.Blokejr:BAAANQADCggIDwABNQAECgcIEwAEAAAAAA==.Blooddagger:BAABNQAECoEhAAMQAAkKRSUBAwBqAwAQAAgKVyUBAwBqAwAPAAMKCiOwQwArAQAAAA==.Bloodeater:BAAANQADCgYIBgAAAA==.Bloodnyte:BAAANQAECgEIAQAAAA==.',
Bo='Bodhmal:BAACNQAFFIEHAAILAAMKWQaVEwC9AAALAAMKWQaVEwC9AAA1AAQKgSQAAgsACQrvGIQaAMUCAAsACQrvGIQaAMUCAAE1AAQKCQkkAAcA7CMA.Bohkspunch:BAAANQAECgUJBQAAAA==.',
Br='Braass:BAAANQADCgYIDAABNQAECggIJAALABkPAA==.Braassra:BAAANQAECgYIBgABNQAECggIJAALABkPAA==.Brahe:BAAANQADCgYICgAAAA==.Brandun:BAAANQADCgYIBgAAAA==.Brethe:BAAANQADCgUIBQAAAA==.Brokíìnn:BAABNQAECoElAAIOAAkKyhshHgDpAgAOAAkKyhshHgDpAgAAAA==.Broncas:BAAANQADCgEIAQAAAA==.Brootal:BAAANQAECgIIAgABNQAECgkJIQAHAH8gAA==.Brothadane:BAAANQADCgMIAwAAAA==.Brucebearner:BAABNQAECoEYAAMVAAkKwQ/HGABfAQAVAAgK9A/HGABfAQAWAAkKgALsIwB2AAABNQAECgkKGAAVAMEPAA==.Bruff:BAAANQAECgcIDAAAAA==.Brufknight:BAAANQAECgEIAQAAAA==.Brufwar:BAAANQADCggICwAAAA==.Brókiinn:BAAANQADCggIDAAAAA==.',
Bu='Bukhanee:BAAANQAECgMIBAAAAA==.Burmtron:BAAANQAECgUIBwABNQAECgUICAAEAAAAAA==.Burmtronn:BAAANQAECgUICAAAAA==.Bustabolt:BAAANQAECgYIDQAAAA==.Buterfinger:BAAANQADCgUIBQABNQAECgUIBQAEAAAAAA==.',
Bw='Bwansamdeez:BAAANQABCgIIAgABNQADCgUIBQAEAAAAAA==.',
['Bò']='Bòoty:BAAANQAECgUIDAAAAA==.',
Ca='Caceynn:BAAANQAECgIJAgAAAA==.Cache:BAAANQAECgMIAwAAAA==.Calamatous:BAAANQADCgMIAwAAAA==.Caldrath:BAAANQABCgIIAgAAAA==.Caliham:BAAANQAECgIIAgAAAA==.Candyditto:BAAANQAECgIIAgABNQAFFAIIAgAEAAAAAA==.Caoinlean:BAAANQADCgcIDQAAAA==.Carebearcare:BAACNQAFFIEKAAIVAAMKBQ7kAgDFAAAVAAMKBQ7kAgDFAAA1AAQKgTAAAxUACQpPIdwCAFgDABUACQpPIdwCAFgDABYAAQpPAPAzAB0AAAAA.Cattledecap:BAAANQABCgIIAgAAAA==.',
Ce='Celiaisake:BAAANQAECgUICwAAAA==.Celorleran:BAAANQADCgUICQAAAA==.Ceruibas:BAAANQAECgUIDAAAAA==.Cev:BAAANQADCgIJAgABNQAECgkJJQAIAOQeAA==.',
Ch='Chaoscat:BAAANQAECgcIEQAAAA==.Chaossparkie:BAAANQAECgUIDQAAAA==.Charlight:BAAANQAECgUICwAAAA==.Cheddarclaps:BAAANQABCgEIAQAAAA==.Cheeksdemon:BAAANQAECgMIAwAAAA==.Cheesefriess:BAAANQAECggIEgAAAA==.Chetan:BAAANQADCgEIAQAAAA==.Chickle:BAAANQADCgQIBQAAAA==.Chillpills:BAAANQAECgUIBQAAAA==.Chuckknight:BAAANQADCgYICQABNQAECgEIAQAEAAAAAA==.Chuttbeeks:BAAANQAECgUIDQABNQAECgYIEQAEAAAAAA==.',
Ci='Cisnei:BAAANQAECgIIBAABNQAECgMICAAEAAAAAA==.',
Co='Codisbest:BAAANQADCgUIBQAAAA==.Coggwalker:BAAANQADCgcICAAAAA==.Colbyjax:BAAANQADCggICAABNQAECggIFwARAOsTAA==.Coldiloks:BAAANQAECgYIEgAAAA==.Corgruumn:BAAANQADCggIBQAAAA==.',
Cr='Crastak:BAAANQAECgYIEgAAAA==.Crazyliquer:BAAANQADCggIHQAAAA==.Creamz:BAAANQADCgEIAQAAAA==.Crisy:BAABNQAECoEfAAIHAAgK6SLBHgAaAwAHAAgK6SLBHgAaAwAAAA==.',
Cu='Curseflop:BAAANQADCgYIBgABNQAECgQIBgAEAAAAAA==.Cutabetch:BAAANQADCgYIBgAAAA==.',
Cy='Cyndk:BAEANQAECgQIBAABNQAECgIJAgAEAAAAAA==.Cyniel:BAEANQAECgIJAgAAAA==.',
Da='Dabbz:BAAANQAECgEIAQAAAA==.Daez:BAAANQADCgYJCAABNQAECggIIAAXAAEgAA==.Dahampster:BAAANQAECgQIBAAAAA==.Dahleya:BAAANQADCgUIAgAAAA==.Dailna:BAAANQAECgIIBgAAAA==.Dalamri:BAAANQAECgUICQAAAA==.Dalarrorn:BAAANQAECgUIBQAAAA==.Dalitha:BAAANQAECgUIDQAAAA==.Dallart:BAAANQAECggIBgAAAA==.Dalonar:BAAANQADCgYIBgAAAA==.Damrath:BAAANQADCgQIBAAAAA==.Danhunter:BAACNQAFFIERAAMYAAYKxxHTBwCCAQAYAAUKjxPTBwCCAQAOAAEK3QhcIABeAAA1AAQKgRsAAxgACQrsIn0XAG4CABgACQoUIH0XAG4CAA4AAwqAJem5ACMBAAAA.Danoriye:BAAANQAECgcIDAAAAA==.Darazana:BAAANQADCgUIBQAAAA==.Darkclawfox:BAAANQADCgQIBAAAAA==.Darknarsin:BAAANQAECgUICQAAAA==.Darkswrd:BAAANQADCgMIAwAAAA==.Daryanne:BAAANQADCgEJAQAAAA==.Dauglhas:BAABNQAECoE6AAMCAAgKZSVeIwDCAgACAAcKLiVeIwDCAgADAAYK4STyHAB3AQAAAA==.Davbarx:BAAANQABCgQIBgAAAA==.Days:BAAANQAECgEIAQABNQAECggIIAAXAAEgAA==.Daysha:BAAANQADCgQIBAAAAA==.Daze:BAABNQAECoEgAAMXAAgKASCuBwANAwAXAAgKASCuBwANAwARAAYKyRkcFADJAQAAAA==.Dazuiio:BAAANQAECgMIAwAAAA==.Dazzboomie:BAAANQABCgQIBAAAAA==.',
De='Deadrice:BAAANQAFFAIIAgAAAA==.Declines:BAAANQAECgUIBQAAAA==.Delfriet:BAAANQADCgcJEgAAAA==.Delso:BAAANQADCggIDQAAAA==.Deltagorou:BAAANQAECgIIAgAAAA==.Deltasara:BAAANQAECgIIAQAAAA==.Demonarbin:BAAANQAECgcIBwAAAA==.Demonkcorb:BAAANQAECgQIBAAAAA==.Demorah:BAAANQADCgEJAQAAAA==.Deviljin:BAAANQADCgYIBgAAAA==.Deysonis:BAAANQAECgUIDwAAAA==.',
Dh='Dhbear:BAACNQAFFIEPAAIZAAUK3A2XBgCAAQAZAAUK3A2XBgCAAQA1AAQKgSUAAxkACQr6HDIQAOsCABkACQr6HDIQAOsCABoACApUA+g1AEsBAAAA.',
Di='Diabolicgear:BAAANQADCgQIBAAAAA==.Diligence:BAAANQADCgEIAgAAAA==.Dingberry:BAABNQAECoEeAAIbAAkKQiJJAgBsAwAbAAkKQiJJAgBsAwAAAA==.Dioghaltair:BAAANQADCgUIBQAAAA==.Diphyidae:BAABNQAECoEhAAIcAAcKqiGkCgCoAgAcAAcKqiGkCgCoAgAAAA==.Diyatea:BAAANQAECgYIDQAAAA==.Dizzle:BAAANQAECgIIAgAAAA==.',
Dm='Dmininstries:BAAANQAECggIDQAAAA==.',
Do='Dodgeypoo:BAEANQAECgUIBQAAAA==.Dominants:BAAANQAECgQJBAABNQAECgYIBgAEAAAAAA==.Domit:BAAANQAECgEIAQAAAA==.Dommag:BAAANQAECgEIAQAAAA==.Doofensmirtz:BAAANQADCgUIBQAAAA==.Doostfraba:BAAANQADCgQIBQAAAA==.Doots:BAAANQADCggIEAAAAA==.Dopey:BAABNQAECoEeAAIOAAgKThD+UwAkAgAOAAgKThD+UwAkAgAAAA==.Dorkplatypus:BAABNQAECoEiAAMMAAkKJRdjEgCcAgAMAAkKJRdjEgCcAgABAAIKBgZWuQBjAAAAAA==.Doski:BAAANQAECgMIAwABNQAECggIDQAEAAAAAA==.',
Dr='Dracoarbatel:BAAANQADCgcICwAAAA==.Dragindeezz:BAAANQAECgEJAQABNQAFFAUICwAaACQVAA==.Dragindemons:BAACNQAFFIELAAIaAAUKJBWBBAC1AQAaAAUKJBWBBAC1AQA1AAQKgScAAhoACQoVJAEFAHUDABoACQoVJAEFAHUDAAAA.Dragness:BAAANQADCgcIBwAAAA==.Dragonbox:BAAANQAECgcIDQAAAA==.Dragonfroot:BAAANQAECgYIEAAAAA==.Drakgo:BAAANQAECgcIDwAAAA==.Dravenuz:BAACNQAFFIEHAAITAAQKKRn7BABqAQATAAQKKRn7BABqAQA1AAQKgSEAAhMACQpqIKYHAB0DABMACQpqIKYHAB0DAAAA.Dreadarc:BAAANQADCgUIBQABNQAECgQICAAEAAAAAA==.Drespirit:BAAANQAECgUIDQAAAA==.Drewscylla:BAABNQAECoEXAAIPAAgKAhFLIgATAgAPAAgKAhFLIgATAgAAAA==.Drgparkbench:BAAANQAECgEIAQAAAA==.Dripsyfist:BAABNQAECoEjAAMFAAkKFBtjBwCHAgAFAAgKVxtjBwCHAgAGAAkKxA+vHwDYAQAAAA==.Drixor:BAAANQAECgEIAQAAAA==.Drone:BAAANQAECgYIBgABNQAECgkJFQAbAOMmAA==.Druiden:BAAANQAECgYICgABNQAFFAQIDAAKAN8RAA==.Drumall:BAAANQADCgQIBAAAAA==.Drumok:BAAANQAECgQIDAAAAA==.Dríxx:BAAANQADCgYIEQAAAA==.',
Du='Dumbledoof:BAAANQAECgIIAgAAAA==.',
['Dâ']='Dâthomir:BAAANQAECgQIBwAAAA==.',
['Dî']='Dîsfoo:BAAANQABCgYICAAAAA==.',
Ea='Earlragnarl:BAAANQADCgEIAQAAAA==.',
Eb='Ebonyeti:BAAANQADCgEIAQAAAA==.',
Ec='Echarge:BAABNQAECoEcAAINAAgKsBOzQgAeAgANAAgKsBOzQgAeAgAAAA==.',
Ed='Edandith:BAABNQAECoEbAAICAAgKPwy8ZwDQAQACAAgKPwy8ZwDQAQAAAA==.Edsilencek:BAAANQAECgUICgAAAA==.Edyrm:BAAANQABCgQIBAAAAA==.',
Ei='Eizenhorn:BAABNQAECoEcAAMBAAgKAxumKACKAgABAAgKAxumKACKAgAMAAUKZQ6aNwATAQAAAA==.',
El='Elasthanan:BAAANQADCgEIAQAAAA==.Eldnahc:BAAANQAECgEIAQAAAA==.Eleinna:BAAANQAECgQIBgABNQAECgcICgAEAAAAAA==.Elioot:BAAANQAECgEIAQABNQAECgQIBAAEAAAAAA==.Ellodie:BAAANQAECgQJCgAAAA==.Ellíe:BAAANQAECgQICAABNQAFFAEIAQAEAAAAAA==.Elmyndreda:BAAANQAECgQIBwAAAA==.Elrion:BAAANQAFFAEIAQAAAA==.Elwynyssa:BAABNQAECoEaAAIVAAkKNiJFAgB6AwAVAAkKNiJFAgB6AwAAAA==.',
Em='Emardo:BAAANQADCgQIBAAAAA==.Emberly:BAAANQADCggICAAAAA==.Embiix:BAAANQADCgEIAQAAAA==.Emelia:BAAANQADCgUICwAAAA==.Emptythreats:BAAANQADCgYIEQAAAA==.',
En='Enelyancalim:BAAANQADCgYICgAAAA==.',
Er='Eraliela:BAAANQADCgEIAQAAAA==.Erebosian:BAAANQAECgYICgAAAA==.Erlinn:BAAANQADCgEJAQAAAA==.Erudite:BAABNQAECoEoAAIaAAgKkxN5LACdAQAaAAgKkxN5LACdAQAAAA==.',
Et='Eteru:BAAANQADCggIGAAAAA==.',
Eu='Euna:BAAANQAECgQJBgAAAA==.',
Ev='Evilneohuan:BAAANQAECgMIBAABNQAECgcIDQAEAAAAAA==.',
Ex='Exonight:BAAANQABCgYIBwAAAA==.Exosix:BAAANQADCgcIBwAAAA==.',
Ey='Eyko:BAABNQAECoEeAAINAAgK6R5MHgDjAgANAAgK6R5MHgDjAgAAAA==.',
['Eä']='Eädgyth:BAABNQAECoE5AAIJAAgKERhiMAASAgAJAAgKERhiMAASAgAAAA==.',
Fa='Fafader:BAAANQADCgYIBwAAAA==.Farbauti:BAABNQAECoEhAAIKAAgK8yGTDgDnAgAKAAgK8yGTDgDnAgAAAA==.Fascinus:BAAANQAECgEIAQAAAA==.',
Fe='Fedrk:BAAANQAECgUICgAAAA==.Fedu:BAAANQAFFAEIAQAAAA==.Feldesk:BAABNQAECoEbAAIaAAcKshPmKAC+AQAaAAcKshPmKAC+AQAAAA==.Feldraken:BAAANQAECgUIBQAAAA==.Fellich:BAAANQAECgQIBQAAAA==.Felspike:BAAANQADCgMIAwAAAA==.Fenrii:BAAANQADCgIIAgAAAA==.Ferp:BAAANQAECgUJCgAAAA==.Festered:BAABNQAECoEaAAMJAAcKSRukMwD+AQAJAAcKSRukMwD+AQAKAAQKCwzHWQDBAAAAAA==.',
Fi='Fincaman:BAAANQAECgEJAQAAAA==.Fireworkoreo:BAAANQADCgYIBgAAAA==.Fisholdrick:BAAANQAECgcIBwABNQAECggIGgAdANwbAA==.Fizzcopper:BAABNQAECoExAAIeAAkKhx+HAQAzAwAeAAkKhx+HAQAzAwAAAA==.',
Fk='Fkwalmart:BAAANQADCggIDgABNQAECgkJMAAfAKAjAA==.',
Fl='Flavortheman:BAAANQABCgMIAgAAAA==.Flit:BAAANQAECgQICgAAAA==.Flitmg:BAAANQADCgQIBwAAAA==.Flowersnight:BAAANQAECgUIDQAAAA==.Flowerx:BAAANQADCggICAABNQAECgEIAwAEAAAAAA==.Flowerxx:BAAANQAECgEIAwAAAA==.',
Fo='Fontanie:BAAANQADCgIIAgAAAA==.Fontaniebear:BAAANQABCgIIAgABNQADCgIIAgAEAAAAAA==.Formroll:BAAANQAECgEIAQAAAA==.Foxyashammy:BAAANQAECgEIAgAAAA==.',
Fr='Freakdawg:BAAANQAECgUIBgAAAA==.Freetime:BAAANQAECgQICgAAAA==.Freyabloom:BAAANQAECgIIAwAAAA==.Froozxcdk:BAAANQAECgEIAQABNQAFFAEIAQAEAAAAAA==.Froozxchunt:BAAANQAFFAEIAQAAAA==.Froozxcpal:BAAANQAECgMIAwABNQAFFAEIAQAEAAAAAA==.Froozxcwarr:BAAANQAECgYIBgAAAA==.Fruitloops:BAAANQADCgIIAgAAAA==.',
Ga='Gabbiani:BAAANQAECgIIAgAAAA==.Galectrae:BAAANQADCgcICwAAAA==.Galondrake:BAAANQADCgIIAgABNQAECgQIBwAEAAAAAA==.Galonrage:BAAANQADCgYIBgABNQAECgQIBwAEAAAAAA==.Galonzenith:BAAANQAECgQIBwAAAA==.Garamor:BAAANQADCgUICQAAAA==.Garm:BAAANQADCgEIAQAAAA==.Gartahuuliya:BAAANQAECgEIAQAAAA==.Garyboldman:BAAANQADCgUICAAAAA==.Gazlowe:BAAANQADCgUIBQAAAA==.',
Ge='Geldrath:BAAANQADCgEIAQAAAA==.Geldrin:BAAANQAECgIIAgAAAA==.Genoddhunter:BAABNQAECoEfAAMaAAkKiRhgEwCjAgAaAAkKiRhgEwCjAgAZAAcKLxTYLgDUAQAAAA==.Gerfbert:BAABNQAECoEcAAIWAAkK0iBBAgBqAwAWAAkK0iBBAgBqAwAAAA==.Geø:BAAANQADCgYJDwAAAA==.',
Gi='Giantess:BAABNQAECoEgAAIRAAgKnyRhBAA3AwARAAgKnyRhBAA3AwAAAA==.Gibbygibby:BAAANQAECgYIEQAAAA==.Gigadepressd:BAAANQADCgEIAQAAAA==.Giggityz:BAAANQADCgcIDwAAAA==.Gigidygoo:BAAANQADCgMIAwAAAA==.Gilreth:BAABNQAECoElAAIgAAkK5BuKFgDKAgAgAAkK5BuKFgDKAgAAAA==.Gilzaur:BAABNQAECoEYAAMXAAgKSgnQJQBBAQAXAAcK2gfQJQBBAQARAAYKsQX4IQD4AAAAAA==.Gimlad:BAAANQADCgQICAAAAA==.Gimrr:BAAANQAECgIICAAAAA==.Gimurr:BAAANQADCgMIAwABNQAECgIICAAEAAAAAA==.Gixrdano:BAAANQAECgQIBQAAAA==.',
Gj='Gjeoff:BAAANQAECgUICQAAAA==.',
Gl='Glasshealing:BAAANQAECgYIDgAAAA==.',
Gn='Gnomepunzel:BAAANQADCgcIEgAAAA==.',
Go='Goldplated:BAAANQADCgcIBwABNQADCgcICAAEAAAAAA==.Goodys:BAAANQADCggICQAAAA==.Goopstick:BAAANQAECgQIBAAAAA==.Goratrix:BAAANQADCgEIAQAAAA==.Gorewood:BAAANQAECgIIAwAAAA==.Gorgamel:BAAANQADCgIIAgAAAA==.Gorillamage:BAAANQAECgIIAgAAAA==.Gortu:BAAANQAECggICAAAAA==.Gotag:BAABNQAECoEaAAIHAAgKhAbqqQBbAQAHAAgKhAbqqQBbAQAAAA==.Gothoss:BAAANQADCggJCAAAAA==.',
Gr='Gravefang:BAAANQAECggICAAAAA==.Greatdeku:BAAANQADCgMIBAAAAA==.Gribochkov:BAAANQAECgcJBwAAAA==.Grimmby:BAAANQAECgUICAAAAA==.Grumpyangie:BAAANQAECgcIBgABNQAFFAEIAQAEAAAAAA==.Grung:BAABNQAECoEfAAIHAAgKhR9hOQCkAgAHAAgKhR9hOQCkAgAAAA==.',
Gu='Guldum:BAAANQADCgQIBAAAAA==.Gumbynutte:BAAANQAECgYIEQAAAA==.',
Gw='Gwenita:BAAANQAECgYIEwAAAA==.Gwiontotems:BAEANQAECgUIBgAAAA==.',
Gy='Gyarados:BAAANQADCgUICAAAAA==.Gyokuro:BAAANQAECgQIBQABNQADCgUJBQAEAAAAAA==.',
['Gí']='Gízy:BAABNQAECoEmAAMcAAcK0x3mDQBgAgAcAAcK0x3mDQBgAgAGAAUKQATiQQCcAAAAAA==.',
Ha='Habdearn:BAAANQADCgcIDgAAAA==.Haeheia:BAAANQAECgMIAwAAAA==.Hailey:BAACNQAFFIEIAAMLAAQKjRt5DgATAQALAAMK0B55DgATAQATAAEK6w1ODQBVAAA1AAQKgSIAAwsACQq9JYoFAJsDAAsACQq9JYoFAJsDABMABgryHl8WAEYCAAAA.Hakunapotato:BAAANQAECgQIBAAAAA==.Halfe:BAAANQADCgcICgAAAA==.Hamchowder:BAAANQADCgIJAgAAAA==.Hameey:BAAANQAECgQIBgAAAA==.Handjive:BAAANQABCgEIAQAAAA==.Hanuiria:BAAANQAECgIIAwAAAA==.Haranitony:BAABNQAECoEZAAIbAAgKtw9JEgCkAQAbAAgKtw9JEgCkAQAAAA==.Haruharu:BAABNQAECoEWAAICAAcK5xcRUQAYAgACAAcK5xcRUQAYAgAAAA==.Havreth:BAAANQADCggICQAAAA==.Hazzardd:BAAANQAECgYIEwAAAA==.',
He='Heallium:BAAANQADCggIAgAAAA==.Heelie:BAAANQADCgYICgAAAA==.Heleris:BAAANQADCggIDQAAAA==.Helgalila:BAAANQAECgQIBQABNQAECgUIBQAEAAAAAA==.Hellsdemon:BAAANQADCggICAAAAA==.Hellslord:BAAANQADCggICAAAAA==.Helmia:BAAANQADCggICQAAAA==.Hemoglobe:BAAANQADCgEIAQABNQAECgUICQAEAAAAAA==.Heughjanus:BAABNQAECoEVAAIbAAcKWRewDwDQAQAbAAcKWRewDwDQAQAAAA==.Hexonna:BAAANQAECgEIAQAAAA==.Hexshade:BAAANQADCgEIAQAAAA==.',
Hi='Hidere:BAAANQADCgEIAQAAAA==.Hiranoo:BAAANQAECgIIAgABNQAECgYIDAAEAAAAAA==.',
Hl='Hlyparkbench:BAABNQAECoEfAAMIAAkKVRlwHgDIAgAIAAkKVRlwHgDIAgAHAAQKjhmBvAAxAQABNQAECgEIAQAEAAAAAA==.',
Ho='Hodge:BAAANQAECgQIBAABNQAECgYIEQAEAAAAAA==.Hodgey:BAAANQAECgYIEQAAAA==.Holycrapola:BAAANQAECgQICAAAAA==.Holyhero:BAEANQAECgQIBgABNQAECgUIBQAEAAAAAA==.Holykcorb:BAAANQAECgUIBQAAAA==.Holymat:BAAANQADCgEIAQAAAA==.Holystone:BAAANQADCgMIBQAAAA==.Holytweak:BAAANQAECgQIBAAAAA==.Hoovion:BAAANQADCgMIAwAAAA==.',
Hs='Hsmshaaring:BAAANQAECggICQAAAA==.',
Hu='Hudimm:BAAANQAECgUIDAAAAA==.Huggsnkisses:BAAANQAECgMIBQAAAA==.Hughughugh:BAAANQADCgYIBwAAAA==.Hunglownewb:BAAANQADCgYIDAAAAA==.Hunglownub:BAAANQADCggICgAAAA==.Hunho:BAAANQAECggICAAAAA==.Hunterjohn:BAAANQADCgEIAQAAAA==.',
Hy='Hynarillan:BAAANQADCgIIAQAAAA==.Hyorin:BAAANQAECgYICAAAAA==.',
Ic='Icken:BAAANQADCgcIDAAAAA==.',
Id='Idefkanymore:BAAANQAECgIIAwAAAA==.Idomage:BAAANQAECgQIBAAAAA==.',
Ii='Iinning:BAAANQADCgIIAQABNQAECgcIEQAEAAAAAA==.',
Il='Illidhanae:BAAANQAECgEIAQABNQAECgYIEAAEAAAAAA==.Iludron:BAAANQAECgIIAwAAAA==.',
Im='Immaculates:BAAANQABCgIIAgAAAA==.Immunized:BAEANQADCgQIBgABNQADCgYIFwAEAAAAAA==.Imoquai:BAAANQADCggIFwAAAA==.Impedance:BAAANQAECgUIBgAAAA==.Imyaboi:BAAANQAECgYICgAAAA==.Imzáiah:BAAANQAECgUIBwAAAA==.',
In='Infiernito:BAAANQAECgUICQAAAA==.Inforgame:BAAANQADCgUIBQAAAA==.Ining:BAAANQADCggJCAABNQAECgcIEQAEAAAAAA==.Inkhunter:BAAANQADCgMIAwAAAA==.Inkmoon:BAAANQAECgMIAwAAAA==.Inningg:BAAANQAECgcIEQAAAA==.Insânity:BAAANQAECgIIBQAAAA==.Invictus:BAAANQAECgMIBAAAAA==.Invoided:BAAANQAECggICAAAAA==.',
Io='Ioweyouheals:BAAANQAECgQIBQAAAA==.',
Ip='Ipakti:BAAANQADCgEIAQAAAA==.',
Ir='Ironaimorc:BAAANQADCgcIBwAAAA==.',
Is='Ishara:BAAANQADCgcIBwAAAA==.Isharian:BAABNQAECoEbAAIhAAcKmRyIBgBOAgAhAAcKmRyIBgBOAgAAAA==.Islandponder:BAAANQADCgMIBwABNQAECgcIGwAaALITAA==.',
It='Ithrowscars:BAAANQAECgcIEQAAAA==.',
Iv='Ivera:BAAANQAECgQIBgAAAA==.',
Ja='Jaliardys:BAABNQAECoEaAAIdAAgK3BvwYwCHAgAdAAgK3BvwYwCHAgAAAA==.Jareth:BAAANQADCggIHQAAAA==.Jax:BAAANQADCgYIBgAAAA==.Jaxius:BAAANQAECgQICgAAAA==.Jayia:BAACNQAFFIEGAAIdAAYKhAenDgC0AQAdAAYKhAenDgC0AQA1AAQKgSsAAh0ACQpHJKYdAE0DAB0ACQpHJKYdAE0DAAAA.Jayie:BAAANQAECgcIEwABNQAFFAYIBgAdAIQHAA==.',
Je='Jedazar:BAAANQADCgUIBQAAAA==.Jefeli:BAAANQABCgEIAQAAAA==.',
Ji='Jijidruid:BAAANQADCgQIBAAAAA==.Jimf:BAAANQADCgUIBQAAAA==.Jimmyjones:BAAANQAECgEIAQAAAA==.Jinzi:BAAANQAECgcIDQAAAA==.',
Jj='Jjbang:BAAANQAECgUICgAAAA==.',
Jm='Jmel:BAAANQADCgIIAgAAAA==.',
Jo='Joberthom:BAAANQAECgIIAwAAAA==.Jojomars:BAAANQADCgcICgAAAA==.Joosseri:BAAANQADCgYIFgAAAA==.Jorkho:BAAANQADCgQIBAAAAA==.Josespala:BAAANQAECgEIAgAAAA==.Journeydd:BAAANQADCgcIGwAAAA==.',
Ju='Judhar:BAAANQABCgIIAgAAAA==.Juggernutz:BAAANQADCggICAAAAA==.',
['Jí']='Jíjì:BAAANQABCgUIAwAAAA==.',
Ka='Kaelish:BAAANQADCgUICwAAAA==.Kafeene:BAAANQABCgQIBAAAAA==.Kagargo:BAAANQAECgYICgAAAA==.Kahlel:BAAANQADCgEIAQAAAA==.Kaldareth:BAAANQAECggJBwAAAA==.Kalnamos:BAABNQAECoEiAAIGAAkK3RzFDADbAgAGAAkK3RzFDADbAgAAAA==.Kaorinite:BAABNQAECoEZAAIMAAcKwhoVGgAzAgAMAAcKwhoVGgAzAgAAAA==.Karismâ:BAAANQAECgUICwAAAA==.Kataela:BAAANQAECggICgAAAA==.Katanovich:BAAANQAECgQICgAAAA==.Katixx:BAAANQADCgcIEQAAAA==.Katparkbench:BAAANQAFFAIIAgABNQAECgEIAQAEAAAAAA==.Katyperryfan:BAAANQADCgUIBQAAAA==.Kauketkenna:BAAANQADCgcJCQAAAA==.Kaynfel:BAAANQADCgUIBQAAAA==.',
Ke='Kegan:BAAANQAECgUIBgAAAA==.Kek:BAAANQADCgIJAgABNQAECgkJKwATAFMcAA==.Kela:BAACNQAFFIERAAMQAAYKUBfFAwDMAQAQAAUKeRXFAwDMAQAPAAEKgyAuEABfAAA1AAQKgSIAAxAACQrsI7sCAHUDABAACQoUIrsCAHUDAA8AAwqpHzFKAAcBAAAA.Kelezekan:BAAANQAECgYIEQAAAA==.Kelilina:BAAANQAECgcIDQAAAA==.Keyelements:BAAANQAECgMIAwAAAA==.',
Kh='Khafie:BAACNQAFFIEIAAIXAAQK/Qd6CgAfAQAXAAQK/Qd6CgAfAQA1AAQKgSIAAhcACQpQEUQUAD0CABcACQpQEUQUAD0CAAAA.',
Ki='Killtech:BAAANQAECgQICgAAAA==.Kimanip:BAAANQAECgMIBgAAAA==.Kimdeath:BAAANQAECgYIBgAAAA==.Kiraredclaw:BAAANQAECgQIBAAAAA==.Kirolor:BAAANQADCgIIAgAAAA==.Kitsukko:BAAANQAECgYIDQABNQAFFAIIAwAEAAAAAA==.',
Kj='Kjarten:BAAANQAECgUIBwABNQAECgcIEQAEAAAAAA==.',
Kl='Klngbonez:BAAANQADCgUIBQAAAA==.',
Ko='Kolu:BAABNQAECoEcAAIKAAgKnhcLIwAgAgAKAAgKnhcLIwAgAgAAAA==.Korgara:BAAANQAECgUICgAAAA==.Kowalski:BAAANQADCgQIBAABNQAECgQIBAAEAAAAAA==.Kozma:BAAANQADCgIIAgAAAA==.',
Kr='Kraedeyn:BAABNQAECoEfAAIaAAgK7RyWEQC6AgAaAAgK7RyWEQC6AgABNQADCgYIBgAEAAAAAA==.Kraethas:BAAANQADCgEIAQAAAA==.Kraseva:BAAANQAECgEIAQAAAA==.Krell:BAAANQAECgIIBAAAAA==.Krestfallen:BAAANQAECgEIAQAAAA==.Kreyath:BAAANQADCgEIAQAAAA==.Kriek:BAABNQAECoESAAICAAYKKyUdLwCRAgACAAYKKyUdLwCRAgAAAA==.Krissiis:BAAANQADCgMIBAABNQAECgIIAwAEAAAAAA==.Krixor:BAAANQADCgcICgABNQAECgEIAQAEAAAAAA==.Kronikgrowth:BAAANQAECgcIDQAAAA==.Krowtattoo:BAAANQADCgUJBQAAAA==.Kråft:BAAANQAECgEIAgABNQAECgMIAwAEAAAAAA==.',
Ku='Kurolola:BAAANQABCgMIAwAAAA==.Kurome:BAAANQAECgcIEQAAAA==.Kuthuman:BAAANQADCgIIAgAAAA==.',
Ky='Kyah:BAAANQADCgMIAwAAAA==.Kynam:BAAANQAECgUIEAAAAA==.',
La='Lace:BAAANQADCgQIBAAAAA==.Landazanso:BAAANQADCgcICgAAAA==.Lastbow:BAAANQADCgQIBAAAAA==.Latina:BAABNQAECoEYAAIiAAkKqBoKAwDmAgAiAAkKqBoKAwDmAgAAAA==.Laynna:BAAANQAECgQIBQAAAA==.',
Le='Leelcid:BAAANQADCgMIAwAAAA==.Leguiz:BAABNQAECoElAAIiAAkKEyHEAQBCAwAiAAkKEyHEAQBCAwAAAA==.Lemondreams:BAABNQAECoEVAAMOAAkKcB6JSgBBAgAOAAgKlSGJSgBBAgAYAAcKyRmJJQDXAQAAAA==.Lemontree:BAAANQAECgUICgABNQAECggIDQAEAAAAAA==.Leorihk:BAAANQADCgUICQAAAA==.Lerius:BAAANQADCgYIDAAAAA==.Leroyak:BAAANQAECgQIBQAAAA==.',
Li='Lightshadows:BAAANQAECgQICAAAAA==.Lilpikky:BAAANQAECgYIEwAAAA==.Lionfish:BAAANQAECgUICgABNQAECgYIBAAEAAAAAA==.Lirael:BAAANQAECgEIAQAAAA==.Lizardup:BAAANQABCgUIBAAAAA==.Lizzborden:BAAANQADCgUICwAAAA==.Lièrén:BAABNQAECoElAAIOAAkKLRUPNgCFAgAOAAkKLRUPNgCFAgAAAA==.',
Lo='Lokjikju:BAAANQABCgcIDgAAAA==.Lolada:BAAANQADCgEIAQAAAA==.Lonemadness:BAAANQADCgQIBQAAAA==.Longthorne:BAAANQADCgYIBgABNQAECgkJGwABAMkfAA==.Lookitzmee:BAAANQAECgEJAQAAAA==.Lostagro:BAAANQADCgIIAgAAAA==.',
Lu='Lucixn:BAAANQADCggIEQAAAA==.Luckyduck:BAAANQADCgcICAAAAA==.Lughbelenus:BAAANQAECgUICQAAAA==.Luminitz:BAABNQAECoEbAAIjAAkKPR8IAQBCAwAjAAkKPR8IAQBCAwAAAA==.Lummytumkins:BAAANQAECgUIDQAAAA==.Luxdk:BAAANQADCgYIBgABNQAECgUICgAEAAAAAA==.Luxmage:BAAANQAECgUICgAAAA==.',
Ly='Lyoko:BAAANQADCggIFwAAAA==.Lyssandris:BAAANQAFFAEIAQAAAA==.Lythany:BAAANQAECgQIBgAAAA==.',
['Lö']='Löckrocks:BAAANQAECgEIAgAAAA==.',
['Lø']='Løkira:BAAANQADCgYIBwABNQAECgQICAAEAAAAAA==.',
Ma='Mackncheese:BAAANQAECgYIEAAAAA==.Madigan:BAAANQADCgMIAwAAAA==.Maehwa:BAAANQADCgQIBAAAAA==.Maghhard:BAAANQAECgcIDwAAAA==.Magyst:BAABNQAECoEaAAMCAAgKrhtsVgAHAgACAAcK2xpsVgAHAgADAAEKdiH2WABiAAAAAA==.Maicyclone:BAAANQADCgYIBgAAAA==.Malanas:BAAANQAECgEIAQAAAA==.Malishine:BAAANQADCgMIAwAAAA==.Manabender:BAAANQAECgIIAgAAAA==.Mannethal:BAAANQADCgYJBgAAAA==.Marrylou:BAAANQADCgYIDQAAAA==.Martels:BAAANQADCggIDgAAAA==.Martelstorm:BAAANQAECgUICgAAAA==.Materus:BAABNQAECoEfAAILAAgKlhHJMwD9AQALAAgKlhHJMwD9AQAAAA==.Mateusdruid:BAAANQAECgIJAgAAAA==.Mato:BAAANQADCgYIBgAAAA==.Matxhias:BAAANQADCggIEAAAAA==.Mavvick:BAAANQADCgQIBwAAAA==.Maxasoul:BAAANQADCgYJCwAAAA==.Mazzakeene:BAAANQAECgEIAQAAAA==.',
Mc='Mcedgelord:BAAANQADCgUIBQAAAA==.Mcgreezy:BAAANQAECgUIBQABNQAECgUIEgAEAAAAAA==.Mcgrizzy:BAAANQAECgUIEgAAAA==.Mcthor:BAAANQAECgUIDAAAAA==.',
Me='Megasham:BAACNQAFFIEGAAIkAAMKNRgVDgD7AAAkAAMKNRgVDgD7AAA1AAQKgScAAyQACQpiH7sVAPMCACQACQpiH7sVAPMCAA0AAQrBCs0FAS0AAAAA.Meion:BAEANQAECgQIBAAAAA==.Melcam:BAAANQADCgYICAAAAA==.Metalspike:BAAANQADCgUIAwAAAA==.',
Mg='Mgdk:BAAANQAECgQIBAAAAA==.',
Mh='Mhorea:BAAANQAECgUJCgAAAA==.',
Mi='Miniash:BAAANQAECgUIDAAAAA==.Minox:BAAANQAECgEIAwAAAA==.Mismage:BAAANQAECgYIEgAAAA==.Mistlore:BAAANQAECgcIEwAAAA==.Mistyfist:BAAANQAECgUIBQAAAA==.Misérié:BAAANQADCgUIBQAAAA==.Miyamotosaki:BAAANQADCggIDgAAAA==.Mizuree:BAAANQADCgMIAwAAAA==.',
Mo='Moldywater:BAAANQAECgEJAQAAAA==.Monjax:BAAANQAECgcICAAAAA==.Monkyblooms:BAABNQAECoEZAAMFAAcKKQhRFgAxAQAFAAcKKQhRFgAxAQAGAAYKfADwVwApAAAAAA==.Monmook:BAABNQAECoEbAAIFAAgKFRfrCwAGAgAFAAgKFRfrCwAGAgAAAA==.Moofa:BAAANQADCgIIAgAAAA==.Moonfir:BAAANQADCgQIBgAAAA==.Moonlith:BAAANQADCgMIBQAAAA==.Moosah:BAABNQAECoEXAAIaAAgKiReVGwBDAgAaAAgKiReVGwBDAgABNQAECgUICwAEAAAAAA==.Moosetafa:BAAANQAECgYIEwAAAA==.Moosubi:BAAANQAECgUICwAAAA==.Moozifer:BAAANQADCgEIAQAAAA==.Morgoonis:BAAANQAECgYICwAAAA==.Mornth:BAAANQAECgEIAQAAAA==.Morphyus:BAABNQAECoErAAITAAkKUxzkBwAZAwATAAkKUxzkBwAZAwAAAA==.Mostlynotgay:BAAANQAECgUIDwAAAA==.Moxxz:BAAANQADCggIDQAAAA==.',
Mu='Mudmuncher:BAAANQAECgUICQAAAA==.Muffinmaker:BAAANQADCgUIBQAAAA==.Muggernaut:BAAANQADCgYIBgABNQAECgIIAwAEAAAAAA==.Mugma:BAAANQADCgEIAQABNQAECgIIAwAEAAAAAA==.Mundergy:BAAANQADCggICAABNQAECgcIEQAEAAAAAA==.Murazor:BAABNQAECoEVAAIgAAcKaBq6MAAOAgAgAAcKaBq6MAAOAgAAAA==.Murdersinc:BAAANQAECggICAAAAA==.Mutilager:BAAANQAECgcIEwAAAA==.Mutilass:BAAANQABCggICgAAAA==.',
My='Myeaasee:BAAANQAECgQIBgAAAA==.',
['Mà']='Màsnart:BAAANQADCgQJBQABNQAECgYIDAAEAAAAAA==.',
['Má']='Mágaidh:BAAANQAECgcICwAAAA==.',
['Mî']='Mîko:BAABNQAECoEZAAIiAAkKsiB8AQBYAwAiAAkKsiB8AQBYAwAAAA==.',
Na='Nachteule:BAAANQADCgYIBAABNQAECggIJAALABkPAA==.Naeyty:BAAANQAECgIIAwAAAA==.Nahid:BAAANQADCgcIDgAAAA==.Nahtikalelle:BAAANQAECgMIBwABNQAECggIJAALABkPAA==.Najmuldeen:BAAANQAECgEJAQAAAA==.Namewee:BAAANQABCgYIBwAAAA==.Narcana:BAABNQAECoEaAAMRAAgKKxpWDABtAgARAAgKKxpWDABtAgAXAAYKTxM1IgByAQABNQAECgMICAAEAAAAAA==.Narradrex:BAAANQADCgMIAwAAAA==.Narusa:BAAANQAECgMIBAAAAA==.Nastyysham:BAAANQAECgMIAwAAAA==.Naturescienc:BAAANQAECgIIAwAAAA==.',
Nd='Ndh:BAAANQAECgcIEgAAAA==.',
Ne='Neblissa:BAAANQAECgIIAwAAAA==.Neertzul:BAAANQAECgEIAQAAAA==.Nefeli:BAAANQADCgcICAAAAA==.Negu:BAAANQAECgcIEgAAAA==.Nejedi:BAAANQAECgEIAQAAAA==.Neodknight:BAABNQAECoEYAAIJAAcK+x8tJgBVAgAJAAcK+x8tJgBVAgAAAA==.Neohuan:BAAANQAECgcIDQAAAA==.Neomourne:BAAANQADCgcIDQABNQAECgcIDQAEAAAAAA==.Neoplasm:BAAANQADCgYIBgABNQAECggIGAAJAPsfAA==.Neoshield:BAAANQADCgcIBwABNQAECggIGAAJAPsfAA==.Nephran:BAAANQADCgEIAQAAAA==.Nephylxm:BAAANQADCggIDQAAAA==.Nerdibird:BAAANQADCggIEwAAAA==.Nerek:BAABNQAECoEaAAIfAAcKSQtKmgB6AQAfAAcKSQtKmgB6AQAAAA==.Nesthraxa:BAAANQAECgUIDQAAAA==.',
Ni='Nialen:BAAANQADCgIIAgAAAA==.Nialiaa:BAAANQAECgIIAwAAAA==.Nightvader:BAAANQAECggIDwABNQAECgkKGAAVAMEPAA==.Nightwarrior:BAAANQADCgYIBgAAAA==.Nikomach:BAAANQADCgUICAAAAA==.Nirwë:BAAANQAECgIJAgAAAA==.Niviene:BAEANQADCggIFwABNQAECgUIBgAEAAAAAA==.',
No='Nochainpull:BAAANQAECggIDwAAAA==.Nokolutrearn:BAAANQADCgQIBAAAAA==.Noodlebender:BAABNQAECoEbAAIcAAgKzxsvDACHAgAcAAgKzxsvDACHAgAAAA==.Noopsnoop:BAABNQAECoEYAAIQAAgKlRcpDwBoAgAQAAgKlRcpDwBoAgAAAA==.Noopy:BAAANQAECgYIEwAAAA==.Noriannera:BAAANQAECgEIAQAAAA==.Novaomi:BAAANQADCgYIBwAAAA==.Nowhackingu:BAAANQADCgYJBgAAAA==.Noxxah:BAAANQADCgMIAwAAAA==.',
Nu='Nuggets:BAAANQADCgQIBAAAAA==.Nulight:BAABNQAECoEeAAIlAAgKsBYNFQAIAgAlAAgKsBYNFQAIAgAAAA==.Nutrients:BAAANQADCgIIAgAAAA==.',
Ny='Nytesdarkend:BAAANQADCgYIBgAAAA==.Nyteshyft:BAAANQADCgQIAQAAAA==.Nyucka:BAAANQADCgMIAwAAAA==.Nyvrix:BAAANQADCgQICgAAAA==.Nyxnala:BAAANQADCgQIBgAAAA==.',
Oa='Oakenak:BAAANQADCgYIDQAAAA==.',
Oc='Octane:BAAANQAECgEIAQABNQAECgYIEgACACslAA==.',
Od='Odiwen:BAAANQADCgUIBQAAAA==.Odyssa:BAAANQAECggICQABNQAFFAYIDQAOAJ4cAA==.',
Oh='Ohdan:BAAANQADCgUIBQABNQAECgYIDwAEAAAAAA==.',
Ol='Olfdu:BAAANQADCgUIBQAAAA==.',
Om='Omegasoaker:BAAANQAECgMIBAAAAA==.Omitokun:BAAANQAECgIIAgAAAA==.',
Oo='Oolong:BAAANQADCgUJBQAAAA==.',
Or='Orindal:BAAANQAECgUIEAAAAA==.',
Ou='Ouluo:BAAANQADCggIGgAAAA==.',
Pa='Palared:BAABNQAECoEpAAIHAAkKVRtdKQDoAgAHAAkKVRtdKQDoAgAAAA==.Palei:BAAANQAECgEIAQAAAA==.Palladiyne:BAAANQAECgIJAgAAAA==.Palliearth:BAAANQAECgUICAAAAA==.Pallytony:BAAANQADCgYIBgAAAA==.Palmex:BAAANQAECgYIEQAAAA==.Pandaheal:BAAANQADCgYIBgAAAA==.Pandö:BAAANQAECgQICAABNQAECgUJBQAEAAAAAA==.Papacooldwn:BAAANQADCgUIBQAAAA==.Pappacooldwn:BAAANQAECggIBwAAAA==.Parict:BAAANQAECggIAgAAAA==.Pascaal:BAAANQAECgEIAgAAAA==.',
Pe='Pecansandies:BAAANQADCggIGgAAAA==.Pennÿ:BAAANQAECgQIBAAAAA==.Penthe:BAAANQADCgYIDgAAAA==.Penumbruh:BAABNQAECoEbAAIMAAgKRButFQBvAgAMAAgKRButFQBvAgAAAA==.Peruvianvil:BAAANQADCgQIBAABNQAECgIIAgAEAAAAAA==.',
Pf='Pfunk:BAAANQAECgcIDwABNQAECgkJIgAMACUXAA==.',
Ph='Pheebegeobe:BAAANQAECgYIEwAAAA==.Phyzal:BAAANQAECgQIBQAAAA==.Phåze:BAAANQADCgIIAgAAAA==.',
Pi='Piddlebom:BAABNQAECoEUAAIBAAcK5RyBNABTAgABAAcK5RyBNABTAgAAAA==.Pirani:BAAANQADCgUIDAAAAA==.Pistöph:BAAANQADCgEIAQAAAA==.Pitts:BAAANQAECgUICgAAAA==.',
Pl='Platanito:BAAANQADCgYICAAAAA==.Plethura:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.',
Po='Ponyytail:BAAANQAECgIIBQAAAA==.Poodis:BAAANQAECgYIEAABNQADCgUJBQAEAAAAAA==.Porkpay:BAAANQADCgEJAQAAAA==.Poshanka:BAAANQAECgUICgAAAA==.Poulsao:BAAANQAECgQIBAAAAA==.Powgun:BAAANQADCgYIEQAAAA==.',
Pr='Promyvïon:BAAANQAECgYIBwABNQAECggIFwARAOsTAA==.',
Pu='Pulpgorillaz:BAAANQADCgYIBwAAAA==.Punchtruly:BAAANQAECgYIEQAAAA==.Purgemedaddy:BAAANQAECgEIAQAAAA==.',
Qd='Qdb:BAAANQAECgQJBQAAAA==.',
Qi='Qiaosheng:BAAANQADCgcICQAAAA==.Qiuqila:BAAANQAECgEIAQAAAA==.',
Ra='Rabbitruid:BAAANQADCgQJBAAAAA==.Rabbitunter:BAAANQAECgQIBQAAAA==.Rabbitus:BAAANQABCgQIBAAAAA==.Rachejagerin:BAAANQAECgQIBgABNQAECggIJAALABkPAA==.Rackharrow:BAAANQADCgQIBAAAAA==.Raedammil:BAAANQAECgUICQAAAA==.Raellé:BAAANQAECgUICwAAAA==.Ragnarss:BAAANQADCgMIAwAAAA==.Raiddaddy:BAAANQAECgEIAQABNQAECgIIAwAEAAAAAA==.Rainmow:BAAANQAECgYIDgAAAA==.Rainnir:BAAANQAECgYIBwAAAA==.Ramlethal:BAAANQADCgEIAQAAAA==.Rapháèl:BAAANQAECgUJCgABNQAECgcICAAEAAAAAA==.Rapticon:BAAANQADCgUICgAAAA==.Rashelyn:BAABNQAECoEXAAIdAAgKuQ9PogD1AQAdAAgKuQ9PogD1AQAAAA==.Rat:BAAANQAECggICAAAAA==.Rathgart:BAAANQAECggIBgAAAA==.Ravnsong:BAAANQAECgUICgAAAA==.Ravun:BAAANQABCgIIAgAAAA==.Raylea:BAAANQADCggIFAAAAA==.Raynevanity:BAAANQADCgIIAgAAAA==.Rayrim:BAAANQADCgIIAgAAAA==.Razenothen:BAAANQAECgIIAgAAAA==.',
Re='Reagan:BAAANQADCgMIAwABNQAECgIJAgAEAAAAAA==.Recktyou:BAAANQADCgYIBgAAAA==.Reco:BAABNQAECoEeAAIHAAgKlxB9fwDGAQAHAAgKlxB9fwDGAQAAAA==.Rednazm:BAAANQAECgYIDwABNQAECgkJHQAfAHIeAA==.Redragondeez:BAAANQADCgQJBAABNQAECgkJKQAHAFUbAA==.Redsdh:BAAANQADCgEIAQABNQAECgkJKQAHAFUbAA==.Redsmasher:BAAANQADCgUIBwAAAA==.Reindridaen:BAAANQADCgYICAABNQAECgkJJwAUAAUYAA==.Rekkaz:BAAANQABCgMIAwAAAA==.Relapse:BAAANQADCggICAAAAA==.Rem:BAAANQADCgUIBQAAAA==.Remimousy:BAAANQADCgQJCgAAAA==.Rendqt:BAAANQADCgQIAQAAAA==.Revdrax:BAAANQAECgYIDwAAAA==.Revosham:BAAANQAECgUIDgAAAA==.Rexxywaffles:BAAANQAECgUIBgAAAA==.',
Rh='Rhaanall:BAAANQAECgUIBgAAAA==.Rhaizu:BAAANQAECgEIAQAAAA==.',
Ri='Rickamy:BAAANQAECgEIAwAAAA==.Riedreni:BAAANQAECgQIBQAAAA==.',
Ro='Rockytotems:BAAANQAECgcIEwAAAA==.Rogued:BAACNQAFFIEJAAMQAAMKLh4gCgC2AAAQAAIKzhogCgC2AAAPAAEK7SRkDwBrAAA1AAQKgSYAAxAACQpEIkAHAPMCABAACAqWIUAHAPMCAA8ABAquII04AHIBAAAA.Rokii:BAAANQADCgQIBAAAAA==.Roldius:BAAANQADCgYIDAAAAA==.Roliatorc:BAAANQAECgIIAgABNQAECggIDQAEAAAAAA==.Rorochaman:BAAANQAECgUIBgABNQAECggIHQATAFEQAA==.Rorodrac:BAAANQAECgUICQABNQAECggIHQATAFEQAA==.Rorodruida:BAABNQAECoEdAAMTAAgKURDpHwDSAQATAAgKURDpHwDSAQALAAUK9gQlbQDCAAAAAA==.Roropaladin:BAAANQAECgIIAgABNQAECggIHQATAFEQAA==.Rorrk:BAAANQADCgYIDQAAAA==.Rosedemon:BAAANQABCgIIAgAAAA==.Rothanos:BAAANQAECgQIBwAAAA==.Rouland:BAAANQAECgcIDgAAAA==.Rowdawg:BAAANQAECgEJAQAAAA==.Rowkitty:BAAANQADCgMIAwABNQAECgEJAQAEAAAAAA==.',
Ru='Rumplegold:BAAANQAECgEIAQABNQAECgUIDgAEAAAAAA==.',
Ry='Rykthar:BAAANQADCgcIDAAAAA==.Ryvennah:BAAANQADCgYIBgAAAA==.',
['Rê']='Rêhm:BAAANQAECgEIAQAAAA==.',
['Rò']='Ròbert:BAAANQADCgYIBgAAAA==.',
Sa='Sabelyn:BAAANQADCgcICQAAAA==.Sacrofficial:BAAANQAECgUICAAAAA==.Saioxenth:BAAANQAECgYIDQAAAA==.Sakmage:BAAANQAECgQIEwAAAA==.Salchypapa:BAABNQAECoEZAAMHAAgK3Bi5bAD8AQAHAAcKjxe5bAD8AQAIAAcKRgjudABnAQAAAA==.Sallykin:BAAANQAECgIJAgAAAA==.Salsbm:BAAANQADCggICAAAAA==.Samais:BAAANQADCgYIBgAAAA==.Samalia:BAABNQAECoEeAAIlAAkKTCDpBgAHAwAlAAkKTCDpBgAHAwABNQAFFAYIFQAgACciAA==.Samon:BAAANQAECgUIDAAAAA==.Sanches:BAABNQAECoEWAAIYAAkKUgjrLQCEAQAYAAkKUgjrLQCEAQABNQAECgYIBgAEAAAAAA==.Sanctius:BAAANQAECgYICAAAAA==.Sandycheekz:BAAANQADCgIIAgAAAA==.Sanguineclaw:BAAANQAECgQIBgAAAA==.Sanindon:BAAANQADCgcICgAAAA==.Saranii:BAEANQAECgUICgAAAA==.Sarcosis:BAAANQADCggICAAAAA==.Sariì:BAAANQADCggIGAAAAA==.Sathlinda:BAAANQADCgUICAAAAA==.Sauloth:BAAANQADCgMIAwAAAA==.',
Sc='Scaled:BAAANQADCgEIAQAAAA==.Scarletpain:BAAANQADCgEIAQABNQAECgQICwAEAAAAAA==.Scarletpaws:BAAANQADCgUIBQABNQAECgQICwAEAAAAAA==.Scarletrains:BAAANQADCgQIBAABNQAECgQICwAEAAAAAA==.Scarlettanuk:BAAANQAECgQICwAAAA==.Scarlitjoham:BAAANQAECgYIBgAAAA==.Scava:BAAANQAECgIIAgABNQAECgcIEAAEAAAAAA==.Scragglum:BAAANQAECgIIAgAAAA==.Scromo:BAAANQADCggIGgAAAA==.Scv:BAABNQAECoEVAAIbAAkK4yYqAAD+AwAbAAkK4yYqAAD+AwAAAA==.',
Se='Senjougahara:BAAANQAECgEIAQAAAA==.Sento:BAAANQADCgYIBgAAAA==.Serejh:BAABNQAECoEkAAIZAAgKECBzEQDeAgAZAAgKECBzEQDeAgAAAA==.Serejhs:BAAANQADCgUIBQAAAA==.',
Sh='Shadowbrnger:BAAANQAECgcIEQAAAA==.Shadowsnipes:BAAANQAECgEIAgABNQAECggIDwAEAAAAAA==.Shadowsongg:BAAANQAECggIDwAAAA==.Shaggyd:BAAANQABCgIIAwAAAA==.Shammirr:BAAANQADCgcIDQABNQAECgUICgAEAAAAAA==.Shammygaga:BAAANQADCgUJCAABNQAECgQIBwAEAAAAAA==.Shamspam:BAABNQAECoEWAAIkAAcK2B+1LQBqAgAkAAcK2B+1LQBqAgAAAA==.Shanatova:BAAANQAECgEIAQAAAA==.Sharinknight:BAAANQAECgQIBwAAAA==.Shauriand:BAAANQAECgcIBwAAAA==.Shawman:BAAANQAECgEIAgABNQAECgYIBgAEAAAAAA==.Shayminidru:BAAANQAECggIEQAAAA==.Shayminilock:BAAANQAECgUIBgAAAA==.Shehealfu:BAAANQADCggIDgAAAA==.Shigli:BAAANQADCgUIBQABNQAECgYIDgAEAAAAAA==.Shishras:BAACNQAFFIENAAMYAAUKmRG5DwDfAAAYAAMKphC5DwDfAAAOAAIKBhMsGQCeAAA1AAQKgScAAw4ACQoMJVkgAN4CAA4ACAqFJVkgAN4CABgABgq2IfMcADECAAAA.Shnid:BAAANQAECgUIBwAAAA==.Shâdowcâst:BAAANQAECgEJAQAAAA==.',
Si='Siardre:BAAANQADCgcIEAAAAA==.Sigwen:BAAANQAECggICAABNQADCgUIBQAEAAAAAA==.Silentbozo:BAAANQADCgMIAwAAAA==.Silentkiler:BAAANQADCgUIBQAAAA==.Sillydruid:BAAANQADCggIFAAAAA==.Sillyrat:BAAANQAECgYJEwAAAA==.Sincados:BAAANQAECgYICgAAAA==.Sionfaust:BAAANQAECgQIBwAAAA==.Sipper:BAABNQAECoEeAAIlAAgKqB/yCQDAAgAlAAgKqB/yCQDAAgAAAA==.Sipter:BAAANQAECggIDQABNQAECggIHgAlAKgfAA==.',
Sk='Skandelóus:BAAANQAECgMIAwAAAA==.',
Sl='Slicky:BAAANQADCgQIBgABNQAFFAEIAQAEAAAAAA==.',
Sm='Smashingface:BAAANQAECgIIAwAAAA==.',
Sn='Sniffmybubbl:BAAANQADCgMJAwAAAA==.',
So='Sodio:BAAANQAECgEIAQABNQAFFAUIEAACAP8TAA==.Sodypop:BAAANQADCggIFwABNQAECgYIEAAEAAAAAA==.Sokra:BAAANQADCgYICAAAAA==.Soldmyeggs:BAAANQAECgUIBQAAAA==.Somonia:BAAANQAECgEIAQABNQAFFAYIFQAgACciAA==.Sordamac:BAAANQAECggIDQAAAA==.',
Sp='Spartacuspal:BAAANQAECgYIBgAAAA==.Spicymustard:BAAANQADCgYIBgAAAA==.Spidda:BAAANQAECgEIAgAAAA==.Spktodamangr:BAAANQADCggICgAAAA==.Spleezor:BAAANQADCggICwAAAA==.',
St='Stasismom:BAAANQAECgUICQABNQAECgYIBgAEAAAAAA==.Stealthspike:BAAANQADCgcIBQAAAA==.Stellalemon:BAAANQAECgUICAAAAA==.Stevvee:BAAANQAECgcIEgAAAA==.Stompalittle:BAAANQADCggIEAABNQAECggIFAAPAA0hAA==.Stoneboy:BAAANQABCgIIBAAAAA==.Stonesboyw:BAAANQAECgUIDgAAAA==.Stoppulling:BAAANQADCgYIBgABNQADCgcIEwAEAAAAAA==.Stormtox:BAAANQAECgEIAQAAAA==.Stormydniels:BAACNQAFFIEPAAINAAYK0hjeAgAjAgANAAYK0hjeAgAjAgA1AAQKgSYAAg0ACQr3JOcFAKsDAA0ACQr3JOcFAKsDAAAA.Strahz:BAABNQAECoEfAAINAAkKpBoIJQC4AgANAAkKpBoIJQC4AgAAAA==.Stunurazz:BAAANQAECgYIDwAAAA==.Sturtur:BAAANQAECgIIAwAAAA==.Stârbow:BAAANQADCgMIAwAAAA==.',
Su='Suddenstorm:BAABNQAECoEeAAMkAAkKgRMhPgAdAgAkAAkKgRMhPgAdAgANAAEKEQSEBgEtAAAAAA==.Sudormrf:BAAANQADCggIEgABNQAECgUIDgAEAAAAAA==.Sullywaffles:BAAANQAECgUICQAAAA==.Sunryze:BAAANQADCgcIDQAAAA==.Sunspotted:BAAANQADCgIIAgAAAA==.Suralias:BAABNQAECoEiAAIdAAkKWhznOAD4AgAdAAkKWhznOAD4AgAAAA==.Surashaman:BAABNQAECoEYAAIkAAkKQyFVCgBOAwAkAAkKQyFVCgBOAwABNQAECgkJIgAdAFocAA==.',
Sw='Swankkie:BAAANQAECgQIBAABNQAECgkJHwAOADgjAA==.Sweetdev:BAAANQADCgMIAwAAAA==.',
Sy='Syraen:BAAANQADCggIEgAAAA==.',
Sz='Szylph:BAAANQADCgYIDAAAAA==.',
['Sä']='Säel:BAAANQAECgYICgAAAA==.',
['Sç']='Sçàr:BAAANQADCggICgAAAA==.',
Ta='Taebaek:BAAANQADCgUIBQAAAA==.Takomaho:BAAANQADCggIDwAAAA==.Talahnoa:BAAANQADCgcIBwAAAA==.Talantheron:BAABNQAECoEdAAIHAAgKWR9AOgChAgAHAAgKWR9AOgChAgABNQAFFAUIDQAYAJkRAA==.Talhearn:BAAANQAECggICwAAAA==.Taminek:BAAANQAECggIEQABNQAFFAUIDQAYAJkRAA==.Tanarcarissa:BAAANQAECgEIAQAAAA==.Tankboy:BAAANQAECgUICgAAAA==.Tankiemctank:BAEANQADCgYICQAAAA==.Taqui:BAAANQADCggICAAAAA==.Tathea:BAAANQAECgYIDwAAAA==.Tatsuya:BAAANQAECgEIAQAAAA==.Tayded:BAAANQADCgEJAQAAAA==.Tayzar:BAAANQADCgEIAQAAAA==.',
Te='Tehrah:BAAANQADCgIIAgAAAA==.Telisaria:BAAANQADCgcIBwAAAA==.Tellanll:BAAANQABCgUIBgAAAA==.Telocurdle:BAAANQAECgEIAQAAAA==.Temnotal:BAAANQAECgQIBQAAAA==.Tendag:BAAANQAECgYIDwABNQAECgkJMAALAFEhAA==.Teorem:BAABNQAECoEXAAIRAAgK6xNQDwArAgARAAgK6xNQDwArAgAAAA==.Tevulamezruj:BAAANQADCgUIBQAAAA==.Teyem:BAAANQADCgMIAwAAAA==.',
Th='Thalyon:BAAANQADCgQIBAAAAA==.Thanaphos:BAAANQADCgcIFAAAAA==.Thatguyoquai:BAAANQADCgQJBwAAAA==.Thconsequenc:BAAANQADCgYIBgAAAA==.Theadore:BAAANQADCgEIAQAAAA==.Thecbt:BAAANQADCgQIBAAAAA==.Thellara:BAAANQADCgYIBgAAAA==.Thelmor:BAAANQADCgEIAQAAAA==.Theprincer:BAAANQAECgQICgAAAA==.Therrai:BAAANQADCgYIGwAAAA==.Thibodeaux:BAAANQADCgEIAQABNQAECgcIJgAcANMdAA==.Thirtyfloor:BAAANQADCgYIBgAAAA==.Thisguyelroy:BAAANQAECgYICAAAAA==.Thlsbro:BAAANQAECgYICwAAAA==.Thoromyr:BAAANQAECgMICAAAAA==.Thuato:BAAANQADCgYICgAAAA==.Thundercats:BAAANQAECgQIBgAAAA==.Thúndrstruck:BAAANQAECgYIEQABNQAECgkJGwABAMkfAA==.',
Ti='Tiffërny:BAAANQADCgIIAgAAAA==.Timadin:BAAANQADCgYJBgABNQAECggIIwAgAF8hAA==.Timinator:BAAANQADCgYIBwABNQAECggIIwAgAF8hAA==.Tinylemon:BAAANQAECggIDQAAAA==.Tivaan:BAAANQAECgQICgAAAA==.Tizmprince:BAAANQADCgEIAQAAAA==.',
To='Torq:BAABNQAECoEiAAIkAAkKjCIECwBHAwAkAAkKjCIECwBHAwABNQAECgkJGwABAMkfAA==.Totemful:BAAANQAECggICwABNQAFFAcIFAAaADQeAA==.',
Tr='Traesera:BAAANQADCgYIBgAAAA==.Traewynn:BAAANQAECgQIBgAAAA==.Transkitty:BAAANQADCgYIBgAAAA==.Trexy:BAAANQADCgcICwAAAA==.Triredgy:BAABNQAECoEeAAQSAAgK3BfrBQAqAgASAAgK3BfrBQAqAgARAAMKWwwaKAClAAAXAAIKLgXDOwBmAAAAAA==.',
Ts='Tsilhqot:BAAANQADCgMIAwAAAA==.',
Tt='Tthatguyy:BAAANQADCgYICAAAAA==.',
Tu='Tummyblaster:BAAANQADCgEIAQABNQADCggIGAAEAAAAAA==.Tummysnake:BAAANQADCgQIBgAAAA==.Turalya:BAAANQAECgIIAwAAAA==.Tuychm:BAAANQAECgUIDQAAAA==.',
Tw='Twareded:BAAANQADCgIIAgAAAA==.Twocansam:BAAANQAECgYIBgAAAA==.Twofocks:BAAANQAECgUIBQAAAA==.Twohandsome:BAACNQAFFIEVAAIgAAYKJyJUAQBtAgAgAAYKJyJUAQBtAgA1AAQKgR0AAiAACQoyJoQBANUDACAACQoyJoQBANUDAAAA.Twøføx:BAAANQAECgUICwAAAA==.',
Ty='Tyinaa:BAAANQAECgUICgAAAA==.Tyinthael:BAAANQADCgUIBwAAAA==.Tylenoldk:BAAANQADCgMIAwABNQAECgIIBAAEAAAAAA==.Typherin:BAABNQAECoEcAAIZAAgKxBFVKAAJAgAZAAgKxBFVKAAJAgAAAA==.Tyrallas:BAAANQAECgEIAQAAAA==.Tyrven:BAAANQADCgYIDAAAAA==.',
['Tï']='Tïms:BAAANQAECgIIAgAAAA==.',
Ub='Ubba:BAAANQAECgcIEQAAAA==.',
Ul='Ulannya:BAAANQAECgUIBgAAAA==.Ulddon:BAAANQADCgYIBgAAAA==.Ullria:BAAANQADCgYIBgABNQAECgQICAAEAAAAAA==.',
Un='Undercovrmoo:BAAANQAECgUIEQAAAA==.',
Ur='Urdragon:BAAANQAECgUJDwAAAA==.Urving:BAAANQAECgUIDAAAAA==.',
Uw='Uwugnar:BAAANQADCgYIBgABNQAECgYIDwAEAAAAAA==.',
Va='Vaeltheris:BAAANQADCgYICQAAAA==.Vampiresses:BAAANQAECgEIAQAAAA==.Vantelantien:BAAANQABCgcICwAAAA==.Vargasbarbas:BAAANQADCgMIAwAAAA==.',
Ve='Vecxlolz:BAAANQABCgUIBQAAAA==.Vecxous:BAAANQABCgYICQAAAA==.Veladar:BAAANQAECgUJCAAAAA==.Velaradraena:BAAANQADCgMIAwAAAA==.Velhunter:BAACNQAFFIEHAAIYAAQKexO8CgBAAQAYAAQKexO8CgBAAQA1AAQKgR8AAhgACQqJIDMKABIDABgACQqJIDMKABIDAAAA.Velush:BAACNQAFFIEOAAIJAAUKjCDOAgC8AQAJAAUKjCDOAgC8AQA1AAQKgSkAAgkACQqmJrACALgDAAkACQqmJrACALgDAAAA.Venttress:BAAANQADCgUIBgABNQAECgYIEAAEAAAAAA==.Verdelene:BAABNQAECoEeAAILAAgKOQOgVgAqAQALAAgKOQOgVgAqAQAAAA==.Veressta:BAAANQAECgYJCAABNQABCggICAAEAAAAAA==.Verkk:BAAANQADCgQJBQAAAA==.',
Vi='Vienarissa:BAAANQADCgUICgAAAA==.Vifekoygua:BAAANQAECgQIBAAAAA==.Viralson:BAAANQAECgIIBQAAAA==.Virulnekron:BAABNQAECoEmAAIJAAgK9iLcEwDlAgAJAAgK9iLcEwDlAgAAAA==.Viserysll:BAAANQAECgEJAQABNQAECgUIDgAEAAAAAA==.Vitaemors:BAAANQADCgQIBAAAAA==.Vitaminbee:BAABNQAECoEkAAIaAAkK0BxECwAOAwAaAAkK0BxECwAOAwABNQAECgkJIwAdAD8cAA==.',
Vl='Vlnar:BAABNQAECoEmAAIZAAkKcyJnCABQAwAZAAkKcyJnCABQAwAAAA==.',
Vo='Voeros:BAAANQADCgEIAQAAAA==.Voidplay:BAAANQAECgEIAwAAAA==.Voyagerebaca:BAAANQAECgEIAQAAAA==.Voyagesoul:BAAANQADCgEIAgAAAA==.',
['Vê']='Vêspera:BAAANQADCgIIAgAAAA==.',
Wa='Wadeboggs:BAAANQAECgcIDAABNQAFFAYIDwANANIYAA==.Warrod:BAAANQAECgYIEgAAAA==.Washabilly:BAABNQAECoElAAIIAAkK5B7sDwApAwAIAAkK5B7sDwApAwAAAA==.Waterbear:BAAANQAECggIEQAAAA==.',
We='Welbiner:BAAANQAFFAIIAwAAAA==.',
Wh='Whackem:BAAANQADCgYICwAAAA==.Whookies:BAAANQAECgYIBgAAAA==.Whö:BAAANQADCgIIAgABNQADCgUIBQAEAAAAAA==.',
Wi='Wileyy:BAAANQAECgQIBgAAAA==.Windbinder:BAAANQAECgUIDgAAAA==.Wizfla:BAABNQAECoEnAAMCAAkKkRzVLgCSAgACAAgKKBvVLgCSAgADAAIKYBiwSgCJAAAAAA==.',
Wo='Wolfluna:BAAANQAECgQICgAAAA==.Woljin:BAAANQAECgIIAgAAAA==.Woobzk:BAAANQADCggIEwAAAA==.Woolala:BAAANQAECgUICAABNQAECgkJIwAdAD8cAA==.Woosiv:BAABNQAECoEbAAMOAAkKaSEIFAAjAwAOAAkKTR4IFAAjAwAYAAgKih+nDgDVAgAAAA==.Woouid:BAAANQAECgEIAQABNQAECgkJGwAOAGkhAA==.Woovoke:BAAANQAECgYIBwABNQAECgkJGwAOAGkhAA==.Workmoose:BAAANQAECgQIBAAAAA==.Wouldisure:BAAANQADCggIFAAAAA==.',
Ww='Wwiilloow:BAAANQABCgQICAAAAA==.',
Xa='Xanderblass:BAAANQADCgQIBAAAAA==.Xanelos:BAAANQADCgYJDgAAAA==.',
Xo='Xoilbiss:BAAANQAECgEIAQAAAA==.',
Ya='Yakia:BAAANQAECggIEwABNQAFFAQIBwAMAC8eAA==.Yanika:BAAANQAECgEIAQAAAA==.Yarellezi:BAAANQABCgUIDgAAAA==.',
Ye='Yehwe:BAAANQAECgEIAQAAAA==.',
Yi='Yiwan:BAAANQAECgcIEAAAAA==.',
Yu='Yuismi:BAAANQAECgQJBgAAAA==.',
Za='Zahrya:BAAANQADCgYIBgAAAA==.Zappd:BAAANQAECgYIDAAAAA==.Zartoga:BAAANQADCgEIAQAAAA==.Zasman:BAAANQAECgQIDAAAAA==.Zayabella:BAAANQAECgEIAQAAAA==.',
Ze='Zedrick:BAAANQAECgEIAQAAAA==.Zenchantress:BAAANQAECgEIAQAAAA==.Zerimah:BAAANQAECgMIAwAAAA==.Zerx:BAAANQADCgYIBgAAAA==.Zetrathion:BAABNQAECoEcAAMXAAYKYQOBLgDdAAAXAAYKYQOBLgDdAAARAAUKsQA5LwBUAAAAAA==.',
Zh='Zhakloskar:BAAANQADCgYIBgAAAA==.Zheuz:BAAANQAECgcIDQABNQAECgcIGgAfAEkLAA==.',
Zi='Ziaet:BAAANQADCgMIBAAAAA==.Zingerdk:BAEBNQAECoEYAAIJAAgKTiQSCQBUAwAJAAgKTiQSCQBUAwAAAA==.Zinng:BAABNQAECoEmAAQMAAkKzhSrFgBhAgAMAAkKzhSrFgBhAgABAAEKuQqFygAuAAAjAAEKtwHqJgAmAAAAAA==.',
Zo='Zoalara:BAABNQAECoEYAAIdAAgKYQ8LnwD8AQAdAAgKYQ8LnwD8AQAAAA==.Zodiakmage:BAAANQAECgIJAgABNQAFFAIIAgAEAAAAAA==.Zoroph:BAAANQADCgQIBAAAAA==.',
Zs='Zsixfiddy:BAAANQADCgUIBQAAAA==.',
Zz='Zzaq:BAAANQAECgYICgABNQAECgkJHwANAEMhAA==.',
['Zá']='Záhr:BAAANQADCggIDQAAAA==.',
['Zí']='Zíngerdh:BAEANQAECgEIAQABNQAECggIGAAJAE4kAA==.',
['Æë']='Æëgwynn:BAAANQADCgUIBQAAAA==.',
['Éo']='Éowyn:BAAANQADCgUIFAABNQAECgMIAwAEAAAAAA==.',
['Ød']='Øddy:BAAANQADCgUIBQAAAA==.',
['ßr']='ßrutal:BAABNQAECoEhAAIHAAkKfyDLFQBLAwAHAAkKfyDLFQBLAwAAAA==.',
['ßt']='ßteel:BAAANQAECgEIAQAAAA==.',
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
