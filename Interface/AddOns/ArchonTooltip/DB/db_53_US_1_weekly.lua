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

local lookup = {'Priest-Holy','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Shadow','Shaman-Elemental','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Evoker-Augmentation','Druid-Restoration','Warlock-Affliction','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Protection','Monk-Windwalker','Monk-Brewmaster','Mage-Arcane','Hunter-Survival','Warrior-Arms','Evoker-Devastation','DeathKnight-Blood','Monk-Mistweaver','Evoker-Preservation','Rogue-Outlaw','Shaman-Restoration','Paladin-Protection','Priest-Discipline',}
local provider = {region='US',realm='Aegwynn',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aarista:BAAANQADCgUJCwAAAA==.',
Ab='Abhorrere:BAAANQABCgMIAwAAAA==.Abindi:BAAANQABCgYIBgAAAA==.Abruegark:BAAANQADCgcIBwAAAA==.',
Ac='Acedririd:BAAANQAECgUICQAAAA==.Actuallyy:BAAANQADCgEIAQAAAA==.',
Ad='Ad:BAAANQAECgUJBQAAAA==.Adönis:BAAANQADCgcJBwAAAA==.',
Ae='Aellerr:BAAANQAECgUIBQAAAA==.',
Af='Affyou:BAAANQAECgUJBwAAAA==.Afuapril:BAAANQABCgIIAwAAAA==.',
Ah='Ahriaballs:BAAANQADCgEIAQAAAA==.Ahzidal:BAABNQAECoEVAAIBAAkKyR++CQA6AwABAAkKyR++CQA6AwAAAA==.',
Ai='Ailbhe:BAAANQADCgYIBQAAAA==.Airbinwl:BAABNQAECoEYAAMCAAkKCSKpFADuAgACAAgKkCGpFADuAgADAAIKPSQ+NADOAAAAAA==.Aitchbar:BAAANQADCgEIAQAAAA==.',
Ak='Akanaar:BAAANQADCgMIBgAAAA==.Akhail:BAAANQAECgIJAgAAAA==.Akilleess:BAAANQAECgIIAgABNQAECgQICQAEAAAAAA==.',
Al='Alaw:BAAANQAECgYJCwAAAA==.Alexdd:BAAANQADCgEIAQAAAA==.Alexiathorne:BAAANQADCgEIAQABNQAECgUJCwAEAAAAAA==.Alextros:BAEANQAECgYJEAAAAA==.Alivana:BAAANQAECgUIBQAAAA==.Almaris:BAABNQAECoEjAAMFAAkKayJ6EwA7AwAFAAkKayJ6EwA7AwAGAAEKmQVG0gA2AAAAAA==.Aloreilina:BAAANQADCgMIAwAAAA==.Alèx:BAABNQAECoEYAAMHAAkKqxbmIQBVAgAHAAkKqxbmIQBVAgAIAAEK+Q3ragA6AAAAAA==.',
Am='Amarielle:BAAANQAECgUJEQAAAA==.Amire:BAAANQADCgYIGgAAAA==.Ammastolamor:BAAANQADCgIIAgAAAA==.',
An='Anahanu:BAABNQAECoEmAAIJAAkKxB04FADhAgAJAAkKxB04FADhAgAAAA==.Andrin:BAAANQAECgIIAwAAAA==.Angelawitch:BAAANQAECgUIBAABNQAECgkJHAAKAFUcAA==.Angienursey:BAABNQAECoEcAAIKAAkKVRyPCwDtAgAKAAkKVRyPCwDtAgAAAA==.Annamolly:BAAANQAECgEIAQAAAA==.Ansitris:BAAANQADCgQIBAAAAA==.Antibiotix:BAABNQAECoEYAAIHAAgK0RfTIQBVAgAHAAgK0RfTIQBVAgAAAA==.',
Ap='Apocrithon:BAAANQAECgQIBAAAAA==.Apros:BAABNQAECoEYAAIFAAgKYxVFSwAnAgAFAAgKYxVFSwAnAgAAAA==.',
Aq='Aqdk:BAAANQAECgEIAgABNQAECgkJHwALAEMhAA==.Aqss:BAABNQAECoEfAAILAAkKQyEfDgBFAwALAAkKQyEfDgBFAwAAAA==.',
Ar='Arakhana:BAAANQAECgEJAQAAAA==.Aralleah:BAAANQAECgQIBwAAAA==.Aratoreii:BAAANQADCgIIAgAAAA==.Arbinshaman:BAAANQAECgQICAAAAA==.Archide:BAAANQAECggIDAAAAA==.Archidus:BAAANQADCgcIBwAAAA==.Arctose:BAAANQAECgcJEQAAAA==.Ardoniak:BAAANQADCggIDgAAAA==.Argenoth:BAAANQADCgMIBgAAAA==.Arkaeon:BAAANQAECgUICQAAAA==.Arlon:BAAANQABCgEJAQAAAA==.Arthar:BAAANQADCgEIAQAAAA==.Arunas:BAAANQADCgUJBQAAAA==.',
As='Asdsfe:BAAANQAECgUJCwAAAA==.Ashandrei:BAAANQAECgUICgAAAA==.Ashletil:BAAANQADCgIJAwAAAA==.Astraeadawn:BAAANQADCgMIAwAAAA==.Aszkme:BAAANQADCgUIBwAAAA==.',
At='Atheniyama:BAAANQADCggICAAAAA==.Atraxia:BAAANQADCgMJAwAAAA==.Atri:BAAANQADCgUIBQABNQAECgQIBwAEAAAAAA==.',
Au='Auran:BAAANQAECgQJBAAAAA==.Autapsia:BAAANQABCgEIAQAAAA==.Authority:BAABNQAECoEaAAIMAAgKKB4YHADSAgAMAAgKKB4YHADSAgAAAA==.Autismosteve:BAAANQAECgYJCwAAAA==.',
Av='Avanlythia:BAAANQADCgYIBgABNQAECgUIBQAEAAAAAA==.Averdeen:BAAANQADCgEIAQABNQADCgEJAQAEAAAAAA==.Avlee:BAAANQADCgQIBAAAAA==.',
Aw='Aware:BAABNQAECoEUAAMNAAgKDSHTDAC9AgANAAgKDSHTDAC9AgAOAAYKhxvAHACvAQAAAA==.',
Ax='Axeron:BAAANQADCgEIAQAAAA==.',
Az='Azathox:BAAANQABCgEIAQAAAA==.Azzuhpala:BAABNQAECoEZAAIGAAkKOBE6LABTAgAGAAkKOBE6LABTAgAAAA==.',
Ba='Baboonki:BAAANQADCgcIBwAAAA==.Baddracthyr:BAABNQAECoElAAIPAAkKTxPPBAA5AgAPAAkKTxPPBAA5AgAAAA==.Balderus:BAAANQAECggJEAAAAA==.Balekrog:BAAANQADCgEJAQAAAA==.Banjophd:BAAANQAECgEIAQAAAA==.Baracus:BAAANQADCggICAAAAA==.Batareva:BAABNQAECoEcAAMJAAcKXQxAQwBjAQAJAAcKXQxAQwBjAQAQAAUKygyoLgD7AAAAAA==.Batavira:BAAANQADCgUJCAABNQAECgcIHAAJAF0MAA==.Bayrock:BAAANQABCgIIAgAAAA==.',
Be='Beamnord:BAAANQAECgQIBgAAAA==.Beanie:BAAANQAECgMIAwAAAA==.Bearlyere:BAAANQAECgYIDAAAAA==.Beastshine:BAAANQADCgYIEAAAAA==.Bendemus:BAABNQAECoESAAQDAAcKIQ/QFwCVAQADAAcKGg7QFwCVAQARAAIKOw6DGABfAAACAAEKhgGw+gAUAAAAAA==.Bentléy:BAAANQADCgEIAQAAAA==.Berserkguts:BAAANQAECgUICwAAAA==.Bersk:BAAANQADCgQIBAAAAA==.',
Bi='Bigdeez:BAAANQAECgEIAQABNQAECgYJDAAEAAAAAA==.Bigelroy:BAAANQADCgEJAQAAAA==.Bigker:BAAANQADCgIIAgAAAA==.Bigzaddy:BAAANQADCgYJBgAAAA==.Bigzas:BAAANQAECgEIAgABNQAECgQICwAEAAAAAA==.Billï:BAAANQAECgQJBAAAAA==.Bitrot:BAAANQAECggJDQAAAA==.',
Bl='Blameray:BAAANQADCggICAAAAA==.Blindbuns:BAAANQAECgEIAQAAAA==.Blokejr:BAAANQADCggIDwABNQAECgYIDAAEAAAAAA==.Blooddagger:BAABNQAECoEZAAMOAAkKsCRqBwDiAgAOAAcKtyRqBwDiAgANAAMKDCP9NAAyAQAAAA==.Bloodeater:BAAANQADCgYIBgAAAA==.Bloodnyte:BAAANQAECgEIAQAAAA==.',
Bo='Bodhmal:BAABNQAECoEfAAIJAAkKMBXdHQCBAgAJAAkKMBXdHQCBAgABNQAECggIHQAFAI8jAA==.Bohkspunch:BAAANQAECgUJBQAAAA==.',
Br='Braass:BAAANQADCgYIBgABNQAECgcIHAAJAF0MAA==.Braassra:BAAANQADCgIIAgABNQAECgcIHAAJAF0MAA==.Brahe:BAAANQADCgYICgAAAA==.Brandun:BAAANQADCgYIBgAAAA==.Brethe:BAAANQADCgUIBQAAAA==.Brokíìnn:BAABNQAECoEfAAIMAAkKaBvaFgDyAgAMAAkKaBvaFgDyAgAAAA==.Broncas:BAAANQADCgEIAQAAAA==.Brothadane:BAAANQADCgMIAwAAAA==.Brucebearner:BAAANQAECggJDQAAAA==.Bruff:BAAANQAECgYJCwAAAA==.Brufknight:BAAANQAECgEIAQAAAA==.Brufwar:BAAANQADCggICwAAAA==.Brókiinn:BAAANQADCggIDAAAAA==.',
Bu='Bukhanee:BAAANQAECgMIBAAAAA==.Burmtron:BAAANQAECgIIAgABNQAECgIIAwAEAAAAAA==.Burmtronn:BAAANQAECgIIAwAAAA==.Bustabolt:BAAANQAECgYIDQAAAA==.Buterfinger:BAAANQADCgUIBQABNQADCgcIEwAEAAAAAA==.',
Bw='Bwansamdeez:BAAANQABCgIIAgABNQADCgUIBQAEAAAAAA==.',
['Bò']='Bòoty:BAAANQAECgQJBwAAAA==.',
Ca='Caceynn:BAAANQAECgIJAgAAAA==.Cache:BAAANQAECgMIAwAAAA==.Calamatous:BAAANQADCgMIAwAAAA==.Caldrath:BAAANQABCgIIBAAAAA==.Candyditto:BAAANQAECgIIAgABNQAFFAcIEwAGADsYAA==.Caoinlean:BAAANQADCgcIDQAAAA==.Carebearcare:BAABNQAECoErAAMSAAkK1h+RAgBAAwASAAkK1h+RAgBAAwATAAEKTwDdKQAdAAAAAA==.Cattledecap:BAAANQABCgIIAwAAAA==.',
Ce='Celiaisake:BAAANQAECgQIBgAAAA==.Celorleran:BAAANQADCgUICAAAAA==.Ceruibas:BAAANQAECgQIBwAAAA==.Cev:BAAANQADCgIJAgABNQAECggIHAAGAJUeAA==.',
Ch='Chaoscat:BAAANQAECgYJCgAAAA==.Chaossparkie:BAAANQAECgUICQAAAA==.Charlight:BAAANQAECgQIBgAAAA==.Cheddarclaps:BAAANQABCgEIAwAAAA==.Cheeksdemon:BAAANQAECgMIAwAAAA==.Cheesefriess:BAAANQAECgYICwAAAA==.Chetan:BAAANQADCgEIAQAAAA==.Chillpills:BAAANQAECgQIAgAAAA==.Chuckknight:BAAANQADCgYICQAAAA==.Chuttbeeks:BAAANQAECgQICAABNQAECgUICwAEAAAAAA==.',
Ci='Cisnei:BAAANQAECgEJAgABNQAECgMJBwAEAAAAAA==.',
Co='Codisbest:BAAANQADCgUIBQAAAA==.Coggwalker:BAAANQADCgUIBgAAAA==.Colbyjax:BAAANQADCggICAABNQAECgUICwAEAAAAAA==.Coldiloks:BAAANQAECgYJDAAAAA==.Corgruumn:BAAANQADCgYJAwAAAA==.',
Cr='Crastak:BAAANQAECgQIDAAAAA==.Crazyliquer:BAAANQADCggJGAAAAA==.Crisy:BAABNQAECoEYAAIFAAgK1h7EJQDMAgAFAAgK1h7EJQDMAgAAAA==.',
Cu='Curseflop:BAAANQADCgYIBgABNQAECgIJAgAEAAAAAA==.',
Cy='Cyndk:BAEANQADCgcJBwABNQAECgIJAgAEAAAAAA==.Cyniel:BAEANQAECgIJAgAAAA==.',
Da='Dabbz:BAAANQAECgEIAQAAAA==.Daez:BAAANQADCgYJCAABNQAECgYIDwAEAAAAAA==.Dahampster:BAAANQAECgQJBAAAAA==.Dahleya:BAAANQADCgUIAgAAAA==.Dailna:BAAANQAECgIJBQAAAA==.Dalamri:BAAANQAECgQIBAAAAA==.Dalarrorn:BAAANQADCgQIBwAAAA==.Dalitha:BAAANQAECgQICAAAAA==.Dallart:BAAANQAECggIBgAAAA==.Dalonar:BAAANQADCgYIBgAAAA==.Damrath:BAAANQADCgQIBAAAAA==.Danhunter:BAACNQAFFIELAAIUAAUKzxD9BQCEAQAUAAUKzxD9BQCEAQA1AAQKgRkAAxQACQrsIh0SAI4CABQACQoUIB0SAI4CAAwAAwqAJQScACkBAAAA.Danoriye:BAAANQAECgcJCAAAAA==.Darazana:BAAANQADCgUIBQAAAA==.Darkclawfox:BAAANQADCgQIBAAAAA==.Darknarsin:BAAANQAECgQJBgAAAA==.Darkswrd:BAAANQADCgMIAwAAAA==.Daryanne:BAAANQADCgEJAQAAAA==.Davbarx:BAAANQABCgQJBwAAAA==.Days:BAAANQAECgEIAQABNQAECgYIDwAEAAAAAA==.Daysha:BAAANQADCgQIBAAAAA==.Daze:BAAANQAECgYIDwAAAA==.Dazuiio:BAAANQAECgIIAgAAAA==.Dazzboomie:BAAANQABCgQIBAAAAA==.',
De='Deadrice:BAAANQAFFAIIAgAAAA==.Declines:BAAANQADCgYICAAAAA==.Delfriet:BAAANQADCgcJEgAAAA==.Delso:BAAANQADCggIDQAAAA==.Deltasara:BAAANQAECgIIAQAAAA==.Demonarbin:BAAANQAECgcIBwAAAA==.Demonkcorb:BAAANQADCggICAAAAA==.Demorah:BAAANQADCgEJAQAAAA==.Deviljin:BAAANQADCgYIBgAAAA==.Deysonis:BAAANQAECgQJBgAAAA==.',
Dh='Dhbear:BAACNQAFFIEKAAIVAAUKSwtPBACCAQAVAAUKSwtPBACCAQA1AAQKgSIAAxUACQq5G48MAPoCABUACQq5G48MAPoCABYACApUAxUwAF8BAAAA.',
Di='Diligence:BAAANQADCgEIAgAAAA==.Dingberry:BAABNQAECoEXAAIXAAgKUSF6AwAHAwAXAAgKUSF6AwAHAwAAAA==.Dioghaltair:BAAANQADCgUIBQAAAA==.Diphyidae:BAAANQAECgQIDQAAAA==.Diyatea:BAAANQAECgYIDQAAAA==.Dizzle:BAAANQAECgIIAgAAAA==.',
Dm='Dmininstries:BAAANQAECggICAAAAA==.',
Do='Dodgeypoo:BAEANQADCggIFAABNQAECgIJAgAEAAAAAA==.Dominants:BAAANQAECgQJBAAAAA==.Domit:BAAANQAECgEIAQAAAA==.Dommag:BAAANQAECgEIAQAAAA==.Doostfraba:BAAANQADCgQIBQAAAA==.Doots:BAAANQADCggIEAAAAA==.Dopey:BAABNQAECoEXAAIMAAgKNgrXVgDrAQAMAAgKNgrXVgDrAQAAAA==.Dorkplatypus:BAABNQAECoEbAAIKAAgKxhVnFQBLAgAKAAgKxhVnFQBLAgAAAA==.Doski:BAAANQAECgIIAgABNQAECgcICgAEAAAAAA==.',
Dr='Dracoarbatel:BAAANQADCgcICwAAAA==.Dragindeezz:BAAANQAECgEJAQABNQAFFAQJBwAWANgVAA==.Dragindemons:BAACNQAFFIEHAAIWAAQK2BWkBABtAQAWAAQK2BWkBABtAQA1AAQKgSIAAhYACQoOJMoDAIkDABYACQoOJMoDAIkDAAAA.Dragness:BAAANQADCgcIBwAAAA==.Dragonbox:BAAANQAECgcIDQAAAA==.Dragonfroot:BAAANQAECgQICgAAAA==.Drakgo:BAAANQAECgcIDQAAAA==.Dravenuz:BAABNQAECoEeAAIQAAkKaiBRBQAyAwAQAAkKaiBRBQAyAwAAAA==.Dreadarc:BAAANQADCgUIBQABNQAECgQICAAEAAAAAA==.Drespirit:BAAANQAECgUJCAAAAA==.Drewscylla:BAAANQAECgYIDgAAAA==.Drgparkbench:BAAANQAECgEIAQAAAA==.Dripsyfist:BAABNQAECoEbAAMYAAkKRxKXGAD2AQAYAAkKxA+XGAD2AQAZAAgKqA63DADDAQAAAA==.Drixor:BAAANQAECgEIAQAAAA==.Drone:BAAANQAECgYIBgABNQAECgkJFQAXAOMmAA==.Druiden:BAAANQAECgYICgAAAA==.Drumall:BAAANQADCgEIAQAAAA==.Drumok:BAAANQAECgQICgAAAA==.Dríxx:BAAANQADCgYIEQAAAA==.',
Du='Dumbledoof:BAAANQAECgIIAgAAAA==.',
['Dâ']='Dâthomir:BAAANQAECgQIBwAAAA==.',
['Dî']='Dîsfoo:BAAANQABCgYICAAAAA==.',
Ea='Earlragnarl:BAAANQADCgEIAQAAAA==.',
Eb='Ebonyeti:BAAANQADCgEIAQAAAA==.',
Ec='Echarge:BAAANQAECgQIEgAAAA==.',
Ed='Edandith:BAAANQAECgYIEAAAAA==.Edsilencek:BAAANQAECgIJBQAAAA==.',
Ei='Eizenhorn:BAAANQAECgcIEQAAAA==.',
El='Elasthanan:BAAANQADCgEIAQAAAA==.Eldnahc:BAAANQADCgMJAgAAAA==.Eleinna:BAAANQAECgQIBQABNQAECgQIBwAEAAAAAA==.Elioot:BAAANQADCgIJAgAAAA==.Ellodie:BAAANQAECgQJCgAAAA==.Ellíe:BAAANQAECgMIBQABNQAFFAEJAQAEAAAAAA==.Elmyndreda:BAAANQAECgIJAwAAAA==.Elrion:BAAANQAFFAEIAQAAAA==.Elwynyssa:BAABNQAECoEaAAISAAkKNiKFAQCEAwASAAkKNiKFAQCEAwAAAA==.',
Em='Emardo:BAAANQADCgQIBAAAAA==.Emberly:BAAANQADCggICAAAAA==.Embiix:BAAANQADCgEIAQAAAA==.Emelia:BAAANQADCgMIBgAAAA==.Emptythreats:BAAANQADCgYIDwAAAA==.',
En='Enelyancalim:BAAANQADCgYICgAAAA==.',
Er='Eraliela:BAAANQADCgEIAQAAAA==.Erebosian:BAAANQAECgQIBAAAAA==.Erlinn:BAAANQADCgEJAQAAAA==.Erudite:BAABNQAECoEgAAIWAAgKtxHiGgAuAgAWAAgKtxHiGgAuAgAAAA==.',
Et='Eteru:BAAANQADCggIGAAAAA==.',
Eu='Euna:BAAANQAECgQJBgAAAA==.',
Ev='Evilneohuan:BAAANQADCgQIBAABNQAECgYICAAEAAAAAA==.',
Ex='Exosix:BAAANQADCgcIBwAAAA==.',
Ey='Eyko:BAABNQAECoEYAAILAAgKqB0FHADNAgALAAgKqB0FHADNAgAAAA==.',
['Eä']='Eädgyth:BAABNQAECoEtAAIHAAcKmhbNLwDxAQAHAAcKmhbNLwDxAQAAAA==.',
Fa='Fafader:BAAANQADCgYIBwAAAA==.Farbauti:BAABNQAECoEaAAIIAAcKCSCgFgBdAgAIAAcKCSCgFgBdAgAAAA==.Fascinus:BAAANQABCgQIBAAAAA==.',
Fe='Fedrk:BAAANQAECgUJBQAAAA==.Fedu:BAAANQAFFAEIAQAAAA==.Feldesk:BAAANQAECgQIEwAAAA==.Fellich:BAAANQAECgQIBQAAAA==.Felspike:BAAANQADCgMIAwAAAA==.Fenrii:BAAANQADCgIIAgAAAA==.Fernaban:BAAANQABCgEIAQAAAA==.Ferp:BAAANQAECgUJCgAAAA==.Festered:BAAANQAECgYJEQAAAA==.',
Fi='Fincaman:BAAANQAECgEJAQAAAA==.Fisholdrick:BAAANQADCggJCgABNQAECggIGgAaAN8bAA==.Fizzcopper:BAABNQAECoEhAAIbAAkKKx6NAQAEAwAbAAkKKx6NAQAEAwAAAA==.',
Fk='Fkwalmart:BAAANQADCggIDgABNQAECgkJJgAcABEjAA==.',
Fl='Flavortheman:BAAANQABCgMIAgAAAA==.Flit:BAAANQAECgMJBgAAAA==.Flitmg:BAAANQADCgQIBwAAAA==.Flowersnight:BAAANQAECgUICQAAAA==.Flowerx:BAAANQADCggICAABNQAECgEIAwAEAAAAAA==.Flowerxx:BAAANQAECgEIAwAAAA==.',
Fo='Fontanie:BAAANQADCgIIAgAAAA==.Fontaniebear:BAAANQABCgIIAgABNQADCgIIAgAEAAAAAA==.Formroll:BAAANQAECgEJAQAAAA==.Foxyashammy:BAAANQAECgEJAQAAAA==.',
Fr='Freakdawg:BAAANQAECgMIBAAAAA==.Freetime:BAAANQAECgQIBQAAAA==.Freyabloom:BAAANQAECgEJAQAAAA==.Froozxcdk:BAAANQAECgEIAQABNQAECggIDQAEAAAAAA==.Froozxchunt:BAAANQAECggIDQAAAA==.Froozxcwarr:BAAANQAECgYIBgAAAA==.Fruitloops:BAAANQADCgIIAgAAAA==.',
Ga='Gabbiani:BAAANQADCggIHgAAAA==.Galectrae:BAAANQADCgQJBAAAAA==.Galondrake:BAAANQADCgIIAgABNQAECgIIAwAEAAAAAA==.Galonzenith:BAAANQAECgIIAwAAAA==.Garamor:BAAANQADCgUICQAAAA==.Garm:BAAANQADCgEIAQAAAA==.Gartahuuliya:BAAANQABCgIIBAAAAA==.Garyboldman:BAAANQADCgIIAwAAAA==.Gazlowe:BAAANQADCgUIBQAAAA==.',
Ge='Geekynaxus:BAAANQABCgEIAQAAAA==.Geldrath:BAAANQADCgEIAQAAAA==.Geldrin:BAAANQAECgIIAgAAAA==.Genoddhunter:BAABNQAECoEYAAIWAAkKiRhHDwDDAgAWAAkKiRhHDwDDAgAAAA==.Gerfbert:BAAANQAECgcIEgAAAA==.Geø:BAAANQADCgYJDwAAAA==.',
Gi='Giantess:BAABNQAECoEYAAIdAAgKliRpAwBOAwAdAAgKliRpAwBOAwAAAA==.Gibbygibby:BAAANQAECgUICwAAAA==.Giggityz:BAAANQADCgcIDwAAAA==.Gigidygoo:BAAANQADCgMIAwAAAA==.Gilreth:BAABNQAECoEcAAIeAAgKxRWkKAAUAgAeAAgKxRWkKAAUAgAAAA==.Gilzaur:BAAANQAECgYJEAAAAA==.Gimlad:BAAANQADCgQIBAAAAA==.Gimrr:BAAANQAECgIIBgAAAA==.Gimurr:BAAANQADCgMIAwABNQAECgIIBgAEAAAAAA==.Gixrdano:BAAANQAECgQIBQAAAA==.',
Gj='Gjeoff:BAAANQAECgMIBAAAAA==.',
Gl='Glasshealing:BAAANQAECgQICAAAAA==.',
Gn='Gnomepunzel:BAAANQADCgcIEgAAAA==.',
Go='Goldplated:BAAANQADCgcIBwAAAA==.Goodys:BAAANQADCggICQAAAA==.Goopstick:BAAANQAECgQIBAAAAA==.Goratrix:BAAANQADCgEIAQAAAA==.Gorewood:BAAANQAECgEJAQAAAA==.Gorgamel:BAAANQADCgEIAQAAAA==.Gorillamage:BAAANQAECgIIAgAAAA==.Gortu:BAAANQADCgYIBgAAAA==.Gotag:BAAANQAECgYIEgAAAA==.Gothoss:BAAANQADCggJCAAAAA==.',
Gr='Gravefang:BAAANQAECggICAAAAA==.Greatdeku:BAAANQADCgMIBAAAAA==.Gribochkov:BAAANQAECgcJBwAAAA==.Grimmby:BAAANQAECgMIAwAAAA==.Grung:BAABNQAECoEYAAIFAAgK6R5/LwCbAgAFAAgK6R5/LwCbAgAAAA==.',
Gu='Guldum:BAAANQADCgMIAwAAAA==.Gumbynutte:BAAANQAECgUICwAAAA==.',
Gw='Gwenita:BAAANQAECgUIDQAAAA==.Gwiontotems:BAEANQAECgEIAQAAAA==.',
Gy='Gyarados:BAAANQADCgUICAAAAA==.Gyokuro:BAAANQAECgQIBQABNQADCgUJBQAEAAAAAA==.',
['Gí']='Gízy:BAABNQAECoEeAAMfAAcKQxxEDABSAgAfAAcKQxxEDABSAgAYAAUKbAM+OACeAAAAAA==.',
Ha='Habdearn:BAAANQADCgcIDgAAAA==.Hailey:BAEBNQAECoEaAAMJAAkKvSV6AwCwAwAJAAkKvSV6AwCwAwAQAAEKWRw5RgBTAAAAAA==.Hakunapotato:BAAANQAECgQIBAAAAA==.Halfe:BAAANQADCgcICgAAAA==.Hamchowder:BAAANQADCgIJAgAAAA==.Hameey:BAAANQAECgQIBgAAAA==.Handjive:BAAANQABCgEIAgAAAA==.Hanuiria:BAAANQAECgIJAQAAAA==.Haranitony:BAAANQAECgYIDwAAAA==.Harriesac:BAAANQABCgEIAQAAAA==.Haruharu:BAAANQAECgYIEQAAAA==.Havreth:BAAANQADCggICQAAAA==.Hazzardd:BAAANQAECgUIDQAAAA==.',
He='Heallium:BAAANQADCggIAgAAAA==.Heelie:BAAANQADCgYICgAAAA==.Heleris:BAAANQADCggIDQAAAA==.Helgalila:BAAANQAECgQIBQABNQAECgUIBQAEAAAAAA==.Hellsdemon:BAAANQADCggICAAAAA==.Helmia:BAAANQADCggICQAAAA==.Hemoglobe:BAAANQADCgEIAQABNQAECgUICQAEAAAAAA==.Heughjanus:BAAANQAECgYIDgAAAA==.Hexonna:BAAANQAECgEIAQAAAA==.Hexshade:BAAANQADCgEIAQAAAA==.',
Hi='Hidere:BAAANQADCgEIAQAAAA==.',
Hl='Hlyparkbench:BAABNQAECoEfAAMGAAkKVRlNFwDUAgAGAAkKVRlNFwDUAgAFAAQKjhmPlwBAAQABNQAECgEIAQAEAAAAAA==.',
Ho='Hodge:BAAANQAECgQIBAABNQAECgUICwAEAAAAAA==.Hodgey:BAAANQAECgUICwAAAA==.Holycrapola:BAAANQAECgIIAwAAAA==.Holyhero:BAEANQAECgIJAgAAAA==.Holykcorb:BAAANQAECgMIAwAAAA==.Holymat:BAAANQADCgEIAQAAAA==.Holytweak:BAAANQAECgQJBAAAAA==.Hoovion:BAAANQADCgMIAwAAAA==.',
Hs='Hsmshaaring:BAAANQAECgcIBwAAAA==.',
Hu='Hudimm:BAAANQAECgQJBwAAAA==.Huggsnkisses:BAAANQAECgMJBAAAAA==.Hunglownewb:BAAANQADCgYJCgAAAA==.Hunglownub:BAAANQADCggICQAAAA==.Hunho:BAAANQAECggICAAAAA==.Hunterjohn:BAAANQADCgEIAQAAAA==.',
Hy='Hynarillan:BAAANQADCgIIAQAAAA==.Hyorin:BAAANQAECgIIAgAAAA==.',
Ic='Icken:BAAANQADCgcIDAAAAA==.',
Id='Idefkanymore:BAAANQAECgEJAQAAAA==.Idomage:BAAANQAECgQIBAAAAA==.',
Ii='Iinning:BAAANQADCgIIAQABNQAECgYICgAEAAAAAA==.',
Il='Illidhanae:BAAANQAECgEIAQABNQAECgYICwAEAAAAAA==.Iludron:BAAANQAECgEJAQAAAA==.',
Im='Immaculates:BAAANQABCgIIAgAAAA==.Immunized:BAEANQADCgQIBgABNQADCgYJEQAEAAAAAA==.Imoquai:BAAANQADCggJEwAAAA==.Impedance:BAAANQAECgEIAQAAAA==.Imyaboi:BAAANQAECgUJBwAAAA==.Imzáiah:BAAANQAECgEJAgAAAA==.',
In='Inforgame:BAAANQADCgUIBQAAAA==.Ining:BAAANQADCggJCAABNQAECgYICgAEAAAAAA==.Inkhunter:BAAANQADCgMIAwAAAA==.Inkmoon:BAAANQAECgMIAwAAAA==.Inningg:BAAANQAECgYICgAAAA==.Insânity:BAAANQAECgIIAwAAAA==.Invictus:BAAANQAECgMIBAAAAA==.Invoided:BAAANQAECggICAAAAA==.',
Io='Ioweyouheals:BAAANQAECgEIAQAAAA==.',
Ir='Ironaimorc:BAAANQADCgcIBwAAAA==.',
Is='Ishara:BAAANQADCgcIBwAAAA==.Isharian:BAAANQAECgYIEwAAAA==.Islandponder:BAAANQADCgMIBwABNQAECgQIEwAEAAAAAA==.',
It='Ithrowscars:BAAANQAECgcICwAAAA==.',
Iv='Ivera:BAAANQAECgQIBgAAAA==.',
Ja='Jaliardys:BAABNQAECoEaAAIaAAgK3xveSwCnAgAaAAgK3xveSwCnAgAAAA==.Jareth:BAAANQADCggIFgAAAA==.Jax:BAAANQADCgYIBgAAAA==.Jaxius:BAAANQAECgMIBgAAAA==.Jayia:BAABNQAECoEoAAIaAAkKBSSIFwBaAwAaAAkKBSSIFwBaAwAAAA==.Jayie:BAAANQAECgcIDwABNQAECgkJKAAaAAUkAA==.',
Je='Jedazar:BAAANQADCgUIBQAAAA==.Jefeli:BAAANQABCgEIAQAAAA==.',
Ji='Jijidruid:BAAANQADCgQIBAAAAA==.Jimf:BAAANQADCgUJBQAAAA==.Jimmyjones:BAAANQAECgEIAQAAAA==.Jinzi:BAAANQAECgUJCwAAAA==.',
Jj='Jjbang:BAAANQAECgUICAAAAA==.',
Jm='Jmel:BAAANQADCgIIAgAAAA==.',
Jo='Joberthom:BAAANQAECgIIAgAAAA==.Jojomars:BAAANQADCgcICgAAAA==.Joosseri:BAAANQADCgYIEAAAAA==.Jorkho:BAAANQADCgQIBAAAAA==.Josespala:BAAANQAECgEJAgAAAA==.Journeydd:BAAANQADCgcIGwAAAA==.',
Ju='Judhar:BAAANQABCgIIAwAAAA==.Juggernutz:BAAANQADCggICAAAAA==.',
['Jí']='Jíjì:BAAANQABCgUIAwAAAA==.',
Ka='Kaelish:BAAANQADCgMIBgAAAA==.Kafeene:BAAANQABCgQIBAAAAA==.Kagargo:BAAANQAECgUICQAAAA==.Kahlel:BAAANQADCgEIAQAAAA==.Kaldareth:BAAANQAECggJBwAAAA==.Kalnamos:BAABNQAECoEgAAIYAAgKch7JCwDGAgAYAAgKch7JCwDGAgAAAA==.Kaorinite:BAAANQAECgYIEgAAAA==.Karismâ:BAAANQAECgQIBgAAAA==.Kataela:BAAANQAECgYJBgAAAA==.Katanovich:BAAANQAECgMJBgAAAA==.Katixx:BAAANQADCgcIEQAAAA==.Katparkbench:BAAANQAECgQJBwABNQAECgEIAQAEAAAAAA==.Katyperryfan:BAAANQADCgUIBQAAAA==.Kauketkenna:BAAANQADCgcJCQAAAA==.Kaynfel:BAAANQADCgUJBQAAAA==.',
Ke='Kegan:BAAANQAECgEIAQAAAA==.Kek:BAAANQADCgIJAgABNQAECgkJIQAQAIkXAA==.Kela:BAACNQAFFIELAAMOAAUKaRHwBABiAQAOAAQKiRHwBABiAQANAAEK5xB9DQBYAAA1AAQKgR8AAw4ACQrDIy8CAIQDAA4ACQrsIS8CAIQDAA0AAwqpHxQ6AA4BAAAA.Kelezekan:BAAANQAECgUICwAAAA==.Kelilina:BAAANQAECgUJCgAAAA==.Keyelements:BAAANQADCggIEAAAAA==.',
Kh='Khafie:BAABNQAECoEgAAIgAAkKRBEaEQBGAgAgAAkKRBEaEQBGAgAAAA==.',
Ki='Killtech:BAAANQAECgQICQAAAA==.Kimanip:BAAANQAECgMJBAAAAA==.Kimdeath:BAAANQAECgYIBgAAAA==.Kiraredclaw:BAAANQAECgQIBAAAAA==.Kirolor:BAAANQADCgIJAgAAAA==.Kitsukko:BAAANQAECgQIBgABNQAFFAEIAQAEAAAAAA==.',
Kj='Kjarten:BAAANQAECgIJAgABNQAECgcIEAAEAAAAAA==.',
Kl='Klngbonez:BAAANQADCgUIBQAAAA==.',
Ko='Kolu:BAAANQAECgcJEwAAAA==.Korgara:BAAANQAECgUIBwAAAA==.Kozma:BAAANQADCgIIAgAAAA==.',
Kr='Kraedeyn:BAAANQAECgcJEwABNQADCgYIBgAEAAAAAA==.Kraethas:BAAANQADCgEIAQAAAA==.Kraseva:BAAANQAECgEIAQAAAA==.Krell:BAAANQAECgEJAgAAAA==.Krestfallen:BAAANQAECgEIAQAAAA==.Kreyath:BAAANQADCgEIAQAAAA==.Kriek:BAAANQAECgYIDgAAAA==.Krissiis:BAAANQADCgMIBAABNQAECgEJAQAEAAAAAA==.Krixor:BAAANQADCgcICgABNQAECgEIAQAEAAAAAA==.Kronikgrowth:BAAANQAECgYIBgAAAA==.Krowtattoo:BAAANQADCgUJBQAAAA==.Kråft:BAAANQAECgEIAgABNQAECgIIAgAEAAAAAA==.',
Ku='Kurolola:BAAANQABCgMIAwAAAA==.Kurome:BAAANQAECgcIDwAAAA==.',
Ky='Kynam:BAAANQAECgUJCwAAAA==.',
La='Landazanso:BAAANQADCgcICgAAAA==.Latina:BAAANQAECggIDwAAAA==.Laynna:BAAANQAECgQIBQAAAA==.',
Le='Leelcid:BAAANQADCgMIAwAAAA==.Leguiz:BAABNQAECoEcAAIhAAgKLiAeAwDKAgAhAAgKLiAeAwDKAgAAAA==.Lemondreams:BAABNQAECoEVAAMMAAkKcB7PNgBZAgAMAAgKlSHPNgBZAgAUAAcKyRm8HgDzAQAAAA==.Lemontree:BAAANQAECgQIBgAAAA==.Leorihk:BAAANQADCgIIBAAAAA==.Lerius:BAAANQADCgYIDAAAAA==.Leroyak:BAAANQAECgIIAgAAAA==.',
Li='Lightshadows:BAAANQAECgQICAAAAA==.Lilpikky:BAAANQAECgYJDwAAAA==.Lionfish:BAAANQAECgUIBQAAAA==.Lirael:BAAANQAECgEIAQAAAA==.Lizzborden:BAAANQADCgMIBgAAAA==.Lièrén:BAABNQAECoEcAAIMAAgKpxNFPgA+AgAMAAgKpxNFPgA+AgAAAA==.',
Lo='Lokjikju:BAAANQABCgcJCgAAAA==.Lolada:BAAANQADCgEIAQAAAA==.Lonemadness:BAAANQADCgQIBQAAAA==.Longthorne:BAAANQADCgYJBgABNQAECgkJFQABAMkfAA==.Lookitzmee:BAAANQAECgEJAQAAAA==.Lostagro:BAAANQADCgIIAgAAAA==.',
Lu='Lucixn:BAAANQADCggIEQAAAA==.Lughbelenus:BAAANQAECgMJBAAAAA==.Luminitz:BAAANQAECggIDwAAAA==.Lummytumkins:BAAANQAECgUICQAAAA==.Luxdk:BAAANQADCgYIBgABNQAECgUIBwAEAAAAAA==.Luxmage:BAAANQAECgUIBwAAAA==.',
Ly='Lyoko:BAAANQADCggJFAAAAA==.Lyssandris:BAAANQAECgcIEQAAAA==.Lythany:BAAANQAECgIIAgAAAA==.',
['Lö']='Löckrocks:BAAANQAECgEIAgAAAA==.',
['Lø']='Løkira:BAAANQADCgYIBwABNQAECgIIAwAEAAAAAA==.',
Ma='Mackncheese:BAAANQAECgUJCgAAAA==.Madigan:BAAANQADCgMIAwAAAA==.Maehwa:BAAANQADCgQIBAAAAA==.Maghhard:BAAANQAECgYIDAAAAA==.Magyst:BAAANQAECgYIDwAAAA==.Maicyclone:BAAANQADCgYIBgAAAA==.Malanas:BAAANQAECgEIAQAAAA==.Malishine:BAAANQADCgMIAwAAAA==.Manabender:BAAANQAECgIJAgAAAA==.Mannersback:BAAANQAECggIEAAAAA==.Mannethal:BAAANQADCgYJBgAAAA==.Marrylou:BAAANQADCgYIDQAAAA==.Martels:BAAANQADCggICAAAAA==.Martelstorm:BAAANQAECgQIBQAAAA==.Materus:BAABNQAECoEYAAIJAAcKcw2BPwB6AQAJAAcKcw2BPwB6AQAAAA==.Mateusdruid:BAAANQAECgIJAgAAAA==.Mato:BAAANQADCgYIBgAAAA==.Matxhias:BAAANQADCggIEAAAAA==.Mavvick:BAAANQADCgQIBAAAAA==.Maxasoul:BAAANQADCgYJCwAAAA==.Mazzakeene:BAAANQAECgEIAQAAAA==.',
Mc='Mcedgelord:BAAANQADCgUIBQAAAA==.Mcgrizzy:BAAANQAECgQICQAAAA==.Mcthor:BAAANQAECgQIBwAAAA==.',
Me='Megasham:BAABNQAECoEkAAMiAAkKRh5aEwDrAgAiAAkKRh5aEwDrAgALAAEKwQoX5AAvAAAAAA==.Meion:BAEANQAECgMJAwAAAA==.Melcam:BAAANQADCgYJCAAAAA==.Metalspike:BAAANQADCgUIAwAAAA==.',
Mg='Mgdk:BAAANQAECgQIBAAAAA==.',
Mh='Mhorea:BAAANQAECgUJCgAAAA==.',
Mi='Miniash:BAAANQAECgQIBwAAAA==.Minox:BAAANQAECgEIAgAAAA==.Mismage:BAAANQAECgYIDQAAAA==.Mistlore:BAAANQAECgYIDAAAAA==.Mistyfist:BAAANQADCgYIBwAAAA==.Miyamotosaki:BAAANQADCgUJBgAAAA==.Mizuree:BAAANQADCgMIAwAAAA==.',
Mo='Moldywater:BAAANQAECgEJAQAAAA==.Monjax:BAAANQAECgMJAwABNQAECgUJCgAEAAAAAA==.Monkyblooms:BAAANQAECgYIEQAAAA==.Monmook:BAABNQAECoEZAAIZAAgKFRdnCQAcAgAZAAgKFRdnCQAcAgAAAA==.Moofa:BAAANQADCgIIAgAAAA==.Moonfir:BAAANQADCgQIBgAAAA==.Moosah:BAABNQAECoEXAAIWAAgKiRfOFgBgAgAWAAgKiRfOFgBgAgABNQAECgUICwAEAAAAAA==.Moosetafa:BAAANQAECgUIDQAAAA==.Moosubi:BAAANQAECgUICwAAAA==.Morgoonis:BAAANQAECgYICwAAAA==.Mornth:BAAANQADCggICAAAAA==.Morphyus:BAABNQAECoEhAAIQAAkKiRcPCwC8AgAQAAkKiRcPCwC8AgAAAA==.Mostlynotgay:BAAANQAECgUICgAAAA==.Moxxz:BAAANQADCgQICQAAAA==.',
Mu='Mudmuncher:BAAANQAECgUIBgAAAA==.Muggernaut:BAAANQADCgYIBgABNQAECgIIAwAEAAAAAA==.Mundergy:BAAANQADCggICAABNQAECgYICgAEAAAAAA==.Murazor:BAABNQAECoEUAAIeAAYKyhpgMgDYAQAeAAYKyhpgMgDYAQAAAA==.Mutilager:BAAANQAECgYJDAAAAA==.Mutilass:BAAANQABCggICgAAAA==.',
My='Myeaasee:BAAANQAECgQIBgAAAA==.Mykickthirty:BAAANQAECggICgAAAA==.',
['Mà']='Màsnart:BAAANQADCgQJBQABNQAECgYIBgAEAAAAAA==.',
['Má']='Mágaidh:BAAANQAECgQIBAAAAA==.',
['Mî']='Mîko:BAABNQAECoEZAAIhAAkKsiAFAQB1AwAhAAkKsiAFAQB1AwAAAA==.',
Na='Naeyty:BAAANQAECgIJAwAAAA==.Nahid:BAAANQADCgcIDgAAAA==.Nahtikalelle:BAAANQAECgMJBQABNQAECgcIHAAJAF0MAA==.Najmuldeen:BAAANQAECgEJAQAAAA==.Namewee:BAAANQABCgYIBwAAAA==.Narcana:BAAANQAECgYIDwABNQAECgMJBwAEAAAAAA==.Narradrex:BAAANQADCgMIAwAAAA==.Narusa:BAAANQAECgMIBAAAAA==.Nastyysham:BAAANQAECgMIAwAAAA==.Naturescienc:BAAANQAECgIIAwAAAA==.',
Nd='Ndh:BAAANQAECgcJCwAAAA==.',
Ne='Neblissa:BAAANQAECgEJAQAAAA==.Neertzul:BAAANQAECgEJAQAAAA==.Nefeli:BAAANQADCgcICAAAAA==.Negu:BAAANQAECgYICwAAAA==.Nejedi:BAAANQADCgEIAQABNQADCgYICQAEAAAAAA==.Neodknight:BAAANQAECggJEQAAAA==.Neohuan:BAAANQAECgYICAAAAA==.Neomourne:BAAANQADCgcIDQABNQAECgYICAAEAAAAAA==.Neoplasm:BAAANQADCgYIBgABNQAECggJEQAEAAAAAA==.Neoshield:BAAANQADCgcIBwABNQAECggJEQAEAAAAAA==.Nephran:BAAANQADCgEIAQAAAA==.Nephylxm:BAAANQADCggIDQAAAA==.Nerdibird:BAAANQADCgcIEQAAAA==.Nerek:BAAANQAECgYIEwAAAA==.Nesthraxa:BAAANQAECgUICQAAAA==.',
Ni='Nialen:BAAANQADCgIIAgAAAA==.Nialiaa:BAAANQAECgEJAQAAAA==.Nightvader:BAAANQAECggIBwABNQAECggJDQAEAAAAAA==.Nightwarrior:BAAANQADCgYJBgAAAA==.Nikomach:BAAANQADCgUICAAAAA==.Nirwë:BAAANQAECgIJAgAAAA==.Niviene:BAEANQADCggIFwABNQAECgEIAQAEAAAAAA==.',
No='Nokolutrearn:BAAANQADCgQIBAAAAA==.Noodlebender:BAAANQAECgcIEQAAAA==.Noopsnoop:BAAANQAECgcIEAAAAA==.Noopy:BAAANQAECgUIDQAAAA==.Noriannera:BAAANQAECgEIAQAAAA==.Novaomi:BAAANQADCgYIBwAAAA==.Nowhackingu:BAAANQADCgYJBgAAAA==.',
Nu='Nuggets:BAAANQADCgQIBAAAAA==.Nulight:BAAANQAECgYJEgAAAA==.Nutrients:BAAANQADCgIIAgAAAA==.',
Ny='Nytesdarkend:BAAANQADCgYIBgAAAA==.Nyteshyft:BAAANQADCgQIAQAAAA==.Nyvrix:BAAANQADCgQICgAAAA==.Nyxnala:BAAANQADCgQIBgAAAA==.',
Oa='Oakenak:BAAANQADCgYIDQAAAA==.',
Oc='Octane:BAAANQAECgEIAQABNQAECgYIDgAEAAAAAA==.',
Od='Odiwen:BAAANQADCgUJBQAAAA==.Odyssa:BAAANQAECgYIBgABNQAFFAUJCQAUAAgbAA==.',
Oh='Ohdan:BAAANQADCgUIBQABNQAECgYIDwAEAAAAAA==.',
Ol='Olfdu:BAAANQADCgUIBQAAAA==.',
Om='Omegasoaker:BAAANQAECgEIAQAAAA==.',
Oo='Oolong:BAAANQADCgUJBQAAAA==.',
Or='Orindal:BAAANQAECgUJCwAAAA==.',
Ou='Ouluo:BAAANQADCggJEwAAAA==.',
Pa='Palared:BAABNQAECoEhAAIFAAkKBhhoLACqAgAFAAkKBhhoLACqAgAAAA==.Palladiyne:BAAANQAECgIJAgAAAA==.Palliearth:BAAANQAECgMJAwAAAA==.Palmex:BAAANQAECgYIEQAAAA==.Pandaheal:BAAANQADCgYJBgAAAA==.Pandö:BAAANQAECgQIBQABNQAECgUJBQAEAAAAAA==.Papacooldwn:BAAANQADCgUIBQAAAA==.Pappacooldwn:BAAANQAECggIBwAAAA==.Parict:BAAANQAECggIAgAAAA==.Pascaal:BAAANQAECgEIAgAAAA==.',
Pe='Pecansandies:BAAANQADCggJEwAAAA==.Pennÿ:BAAANQADCggIGQAAAA==.Penthe:BAAANQADCgYIDgAAAA==.Penumbruh:BAABNQAECoEbAAIKAAgKRBukDwClAgAKAAgKRBukDwClAgAAAA==.Peruvianvil:BAAANQADCgQIBAABNQAECgcJEwAEAAAAAA==.',
Pf='Pfunk:BAAANQAECgUJCAABNQAECggJGwAKAMYVAA==.',
Ph='Pheebegeobe:BAAANQAECgUIEgAAAA==.Phyzal:BAAANQAECgQJBAAAAA==.Phåze:BAAANQADCgIIAgAAAA==.',
Pi='Piddlebom:BAAANQAECgYIDgAAAA==.Pirani:BAAANQADCgQJCwAAAA==.Pistöph:BAAANQADCgEJAQAAAA==.Pitts:BAAANQAECgMJBQAAAA==.',
Pl='Platanito:BAAANQADCgYICAAAAA==.Plethura:BAAANQADCgEIAQABNQAECgIJAgAEAAAAAA==.',
Po='Ponyytail:BAAANQAECgIJBAAAAA==.Poodis:BAAANQAECgUICwABNQADCgUJBQAEAAAAAA==.Porkpay:BAAANQADCgEJAQAAAA==.Poshanka:BAAANQAECgMJBQAAAA==.Poulsao:BAAANQADCgcIFwAAAA==.Powgun:BAAANQADCgQICwAAAA==.',
Pr='Promyvïon:BAAANQAECgEIAQABNQAECgUICwAEAAAAAA==.',
Pu='Pulpgorillaz:BAAANQADCgYIBwAAAA==.Punchtruly:BAAANQAECgUICwAAAA==.Purgemedaddy:BAAANQAECgEIAQAAAA==.',
Qd='Qdb:BAAANQAECgQJBQAAAA==.',
Qi='Qiaosheng:BAAANQADCgcICQAAAA==.',
Ra='Rabbitruid:BAAANQADCgQJBAAAAA==.Rabbitunter:BAAANQAECgEJAQAAAA==.Rabbitus:BAAANQABCgQJBAAAAA==.Rachejagerin:BAAANQAECgQIBAABNQAECgcIHAAJAF0MAA==.Rackharrow:BAAANQADCgQIBAAAAA==.Raedammil:BAAANQAECgUICQAAAA==.Raellé:BAAANQAECgQIBgAAAA==.Raiddaddy:BAAANQADCggIGgABNQAECgEJAQAEAAAAAA==.Rainmow:BAAANQAECgQJCAAAAA==.Rainnir:BAAANQAECgEJAQAAAA==.Ramlethal:BAAANQADCgEIAQAAAA==.Randulf:BAAANQABCgEIAQAAAA==.Rapháèl:BAAANQAECgUJCgAAAA==.Rapticon:BAAANQADCgMIBQAAAA==.Rashelyn:BAAANQAECgcJEwAAAA==.Rat:BAAANQAECggICAAAAA==.Rathgart:BAAANQAECggJBgAAAA==.Ravnsong:BAAANQAECgQJBQAAAA==.Ravun:BAAANQABCgIIAgAAAA==.Raylea:BAAANQADCggIFAAAAA==.Raynevanity:BAAANQADCgIIAgAAAA==.Rayrim:BAAANQADCgIIAgAAAA==.Razenothen:BAAANQADCggIFAAAAA==.',
Re='Reagan:BAAANQADCgMIAwABNQAECgIJAgAEAAAAAA==.Recktyou:BAAANQADCgYIBgAAAA==.Reco:BAABNQAECoEXAAIFAAgKkRAPYQDbAQAFAAgKkRAPYQDbAQAAAA==.Rednazm:BAAANQAECgYICgABNQAECgkJGwAcAHIeAA==.Redragondeez:BAAANQADCgQJBAABNQAECgkJIQAFAAYYAA==.Redsdh:BAAANQADCgEIAQABNQAECgkJIQAFAAYYAA==.Redsmasher:BAAANQADCgIJAgAAAA==.Reindridaen:BAAANQADCgYIBgAAAA==.Rekkaz:BAAANQABCgMIAwAAAA==.Relapse:BAAANQADCggICAAAAA==.Rem:BAAANQADCgUIBQAAAA==.Remimousy:BAAANQADCgQJCgAAAA==.Revdrax:BAAANQAECgYICgAAAA==.Revosham:BAAANQAECgQICQAAAA==.Rexxywaffles:BAAANQAECgMJBAAAAA==.',
Rh='Rhaanall:BAAANQAECgEIAQAAAA==.Rhaizu:BAAANQAECgEIAQAAAA==.',
Ri='Rickamy:BAAANQAECgEIAwAAAA==.Riedreni:BAAANQAECgQIBQAAAA==.',
Ro='Rockette:BAAANQABCgEIAQAAAA==.Rockytotems:BAAANQAECgYIDAAAAA==.Rogued:BAACNQAFFIEGAAMOAAMKJRryBwC4AAAOAAIK/RfyBwC4AAANAAEKdB6qCwBfAAA1AAQKgSAAAw4ACQqUIYAHAOACAA4ACArtH4AHAOACAA0ABArbH5EsAHEBAAAA.Roldius:BAAANQADCgYIDAAAAA==.Rorochaman:BAAANQADCgcIBwABNQAECgUIEAAEAAAAAA==.Rorodrac:BAAANQAECgUJBQABNQAECgUIEAAEAAAAAA==.Rorodruida:BAAANQAECgUIEAAAAA==.Roropaladin:BAAANQADCggICAABNQAECgUIEAAEAAAAAA==.Rorrk:BAAANQADCgYIDQAAAA==.Rosedemon:BAAANQABCgIIAgAAAA==.Rothanos:BAAANQAECgQIBwAAAA==.Rouland:BAAANQAECgcIDAAAAA==.Rowdawg:BAAANQAECgEJAQAAAA==.',
Ru='Rumplegold:BAAANQADCggICQABNQAECgUJCQAEAAAAAA==.',
Ry='Rykthar:BAAANQADCgcIDAAAAA==.Ryvennah:BAAANQADCgYIBgAAAA==.',
['Rê']='Rêhm:BAAANQAECgEIAQAAAA==.',
Sa='Sabelyn:BAAANQADCgcICQAAAA==.Sacrofficial:BAAANQAECgUICAAAAA==.Saioxenth:BAAANQAECgYIDQAAAA==.Sakmage:BAAANQAECgQJDwAAAA==.Salchypapa:BAAANQAECgcJDgAAAA==.Sallykin:BAAANQAECgIJAgAAAA==.Salsbm:BAAANQADCggICAAAAA==.Samais:BAAANQADCgYIBgAAAA==.Samalia:BAABNQAECoEWAAIjAAgKbh/lCQCRAgAjAAgKbh/lCQCRAgABNQAFFAYIEAAeAPIhAA==.Samon:BAAANQAECgUICAAAAA==.Sanches:BAAANQAECggIDgABNQAECgYIBgAEAAAAAA==.Sanctius:BAAANQAECgIIAgAAAA==.Sandycheekz:BAAANQADCgIIAgAAAA==.Sanguineclaw:BAAANQAECgIJBAAAAA==.Sanindon:BAAANQADCgcICgAAAA==.Saranii:BAEANQAECgQJBQAAAA==.Sarcosis:BAAANQADCggICAAAAA==.Sariì:BAAANQADCgcJFQAAAA==.Sathlinda:BAAANQADCgUICAAAAA==.Sauloth:BAAANQADCgMIAwAAAA==.',
Sc='Scaled:BAAANQADCgEIAQAAAA==.Scarletpain:BAAANQADCgEIAQABNQAECgUIBQAEAAAAAA==.Scarletpaws:BAAANQADCgUIBQABNQAECgUIBQAEAAAAAA==.Scarletrains:BAAANQADCgQIBAABNQAECgUIBQAEAAAAAA==.Scarlettanuk:BAAANQAECgQICwABNQAECgUIBQAEAAAAAA==.Scarlitjoham:BAAANQAECgYIBgAAAA==.Scava:BAAANQAECgEIAQAAAA==.Scragglum:BAAANQADCgYIDgAAAA==.Scromo:BAAANQADCggJGgAAAA==.Scv:BAABNQAECoEVAAIXAAkK4yYQAAAJBAAXAAkK4yYQAAAJBAAAAA==.',
Se='Senjougahara:BAAANQADCgcJHgAAAA==.Sento:BAAANQADCgYIBgAAAA==.Serejh:BAABNQAECoEYAAIVAAgKjhyyEQC4AgAVAAgKjhyyEQC4AgAAAA==.Serejhs:BAAANQADCgUIBQAAAA==.',
Sh='Shadowbrnger:BAAANQAECgYJDwAAAA==.Shadowsnipes:BAAANQAECgEIAgABNQAECggJDwAEAAAAAA==.Shadowsongg:BAAANQAECggJDwAAAA==.Shaggyd:BAAANQABCgIIAwAAAA==.Shammirr:BAAANQADCgYIBgABNQAECgQICAAEAAAAAA==.Shammygaga:BAAANQADCgUJCAABNQAECgIIAwAEAAAAAA==.Shamspam:BAAANQAECgUJDgAAAA==.Shanatova:BAAANQAECgEIAQAAAA==.Sharinknight:BAAANQAECgQIBwAAAA==.Shauriand:BAAANQAECgEIAQAAAA==.Shawman:BAAANQAECgEIAgABNQAECgYIBgAEAAAAAA==.Shayminidru:BAAANQAECggICgAAAA==.Shehealfu:BAAANQADCggIDgAAAA==.Shigli:BAAANQADCgUIBQABNQAECgYIDgAEAAAAAA==.Shishras:BAACNQAFFIEIAAMUAAUKmRF2CwDvAAAUAAMKphB2CwDvAAAMAAIKBhMfEgCjAAA1AAQKgSUAAwwACQoMJUcVAPsCAAwACAqFJUcVAPsCABQABQoNI1EeAPkBAAAA.Shnid:BAAANQAECgIJAgAAAA==.Shâdowcâst:BAAANQAECgEJAQAAAA==.',
Si='Siardre:BAAANQADCgYJCQAAAA==.Sigwen:BAAANQAECggICAABNQADCgUJBQAEAAAAAA==.Silentbozo:BAAANQADCgMIAwAAAA==.Sillydruid:BAAANQADCgcJEQAAAA==.Sillyrat:BAAANQAECgYJEwAAAA==.Sincados:BAAANQAECgQIBAAAAA==.Sionfaust:BAAANQAECgQJBAAAAA==.Sipper:BAAANQAECgYIEwAAAA==.',
Sk='Skandelóus:BAAANQAECgMIAwAAAA==.',
Sl='Slicky:BAAANQADCgQIBgABNQAFFAEIAQAEAAAAAA==.',
Sm='Smashingface:BAAANQAECgIIAwAAAA==.',
Sn='Sniffmybubbl:BAAANQADCgMJAwAAAA==.',
So='Sodio:BAAANQAECgEIAQABNQAFFAUJCwACAAwTAA==.Sodypop:BAAANQADCggJEgABNQAECgQICgAEAAAAAA==.Sokra:BAAANQADCgYICAAAAA==.Soldmyeggs:BAAANQADCggIFwAAAA==.Somonia:BAAANQAECgEIAQABNQAFFAYIEAAeAPIhAA==.Sordamac:BAAANQAECggIDAAAAA==.',
Sp='Spartacuspal:BAAANQADCgYIBgAAAA==.Spicymustard:BAAANQADCgYJBgAAAA==.Spidda:BAAANQAECgEIAgAAAA==.Spleezor:BAAANQADCgMIAwAAAA==.',
St='Stasismom:BAAANQAECgUICQABNQAECgYIBgAEAAAAAA==.Stealthspike:BAAANQADCgcIBQAAAA==.Stellalemon:BAAANQAECgQJBAAAAA==.Stevvee:BAAANQAECgcIDQAAAA==.Stompalittle:BAAANQADCggIEAABNQAECggIFAANAA0hAA==.Stoneboy:BAAANQABCgIIAgAAAA==.Stonesboyw:BAAANQAECgUJCQAAAA==.Stormtox:BAAANQAECgEIAQAAAA==.Stormydniels:BAACNQAFFIEJAAILAAUK3xmeAwDCAQALAAUK3xmeAwDCAQA1AAQKgSUAAgsACQr3JLQDAL0DAAsACQr3JLQDAL0DAAAA.Strahz:BAABNQAECoEbAAILAAkKNxh+IwCXAgALAAkKNxh+IwCXAgAAAA==.Stunurazz:BAAANQAECgUJCQAAAA==.Sturtur:BAAANQAECgEJAQAAAA==.Stârbow:BAAANQADCgMIAwAAAA==.',
Su='Suddenstorm:BAAANQAECggIEwAAAA==.Sudormrf:BAAANQADCggICgABNQAECgQJCgAEAAAAAA==.Sullywaffles:BAAANQAECgMJBAAAAA==.Sunryze:BAAANQADCgcIDQAAAA==.Sunspotted:BAAANQADCgIIAgAAAA==.Suralias:BAABNQAECoEeAAIaAAkKWxmGPQDTAgAaAAkKWxmGPQDTAgAAAA==.Surashaman:BAABNQAECoEXAAIiAAkKQyHyBgBkAwAiAAkKQyHyBgBkAwABNQAECgkJHgAaAFsZAA==.',
Sw='Swankkie:BAAANQAECgQIBAABNQAECgkJHgAMADgjAA==.Sweetdev:BAAANQADCgMIAwAAAA==.',
Sy='Syraen:BAAANQADCggIEgAAAA==.',
Sz='Szylph:BAAANQADCgYIDAAAAA==.',
['Sä']='Säel:BAAANQAECgYICQAAAA==.',
['Sç']='Sçàr:BAAANQADCggJCgAAAA==.',
Ta='Taebaek:BAAANQADCgUIBQAAAA==.Talahnoa:BAAANQADCgcIBwAAAA==.Talantheron:BAABNQAECoEXAAIFAAcKIiF2NgB7AgAFAAcKIiF2NgB7AgABNQAFFAUJCAAUAJkRAA==.Talhearn:BAAANQAECgMJAwAAAA==.Taminek:BAAANQAECgYICgABNQAFFAUJCAAUAJkRAA==.Tanarcarissa:BAAANQAECgEIAQAAAA==.Tankboy:BAAANQAECgUICgAAAA==.Tankiemctank:BAEANQADCgYICQAAAA==.Taqui:BAAANQADCggICAAAAA==.Tathea:BAAANQAECgYIDwAAAA==.Tatsuya:BAAANQAECgEIAQAAAA==.Tayded:BAAANQADCgEJAQAAAA==.Tayzar:BAAANQADCgEIAQAAAA==.',
Te='Tehrah:BAAANQADCgIIAgAAAA==.Telisaria:BAAANQADCgcIBwAAAA==.Tellanll:BAAANQABCgUIBgAAAA==.Telocurdle:BAAANQAECgEIAQAAAA==.Temnotal:BAAANQADCgcJCwAAAA==.Tendag:BAAANQAECgYICgABNQAECgkJJgAJAMQdAA==.Teorem:BAAANQAECgUICwAAAA==.Tevulamezruj:BAAANQADCgUIBQAAAA==.',
Th='Thalyon:BAAANQADCgQIBAAAAA==.Thanaphos:BAAANQADCgcIFAAAAA==.Thatguyoquai:BAAANQADCgQJBwAAAA==.Thconsequenc:BAAANQADCgYIBgAAAA==.Theadore:BAAANQADCgEIAQAAAA==.Thecbt:BAAANQADCgQIBAAAAA==.Thellara:BAAANQADCgYIBgAAAA==.Thelmor:BAAANQADCgEIAQAAAA==.Theprincer:BAAANQAECgQICgAAAA==.Therrai:BAAANQADCgYIGwAAAA==.Thirtyfloor:BAAANQADCgYIBgAAAA==.Thisguyelroy:BAAANQAECgQIBQAAAA==.Thlsbro:BAAANQAECgQIBgAAAA==.Thoromyr:BAAANQAECgMJBwAAAA==.Thuato:BAAANQADCgYICgAAAA==.Thundercats:BAAANQAECgIJAgAAAA==.Thúndrstruck:BAAANQAECgYJDgABNQAECgkJFQABAMkfAA==.',
Ti='Tiffërny:BAAANQADCgIIAgAAAA==.Timadin:BAAANQADCgYJBgABNQAECggJGwAeADwaAA==.Timinator:BAAANQADCgYIBwABNQAECggJGwAeADwaAA==.Tinylemon:BAAANQAECgQIBAABNQAECgQIBgAEAAAAAA==.Tivaan:BAAANQAECgMJBgAAAA==.Tizmprince:BAAANQADCgEIAQAAAA==.',
To='Torq:BAABNQAECoEhAAIiAAkKjCJUBwBfAwAiAAkKjCJUBwBfAwABNQAECgkJFQABAMkfAA==.Totemful:BAAANQAECggICgABNQAFFAYIDgAWAC4cAA==.',
Tr='Traewynn:BAAANQAECgIIAgAAAA==.Transkitty:BAAANQADCgYIBgAAAA==.Trexy:BAAANQADCgcICwAAAA==.Triredgy:BAABNQAECoEeAAQPAAgK3BejBABIAgAPAAgK3BejBABIAgAdAAMKWwxXIwCxAAAgAAIKLgU5NABoAAAAAA==.',
Ts='Tsilhqot:BAAANQADCgMIAwAAAA==.',
Tt='Tthatguyy:BAAANQADCgUJBwAAAA==.',
Tu='Tummyblaster:BAAANQADCgEIAQABNQADCggIGAAEAAAAAA==.Tummysnake:BAAANQADCgQIBgAAAA==.Turalya:BAAANQAECgIIAwAAAA==.Tuychm:BAAANQAECgQICAAAAA==.',
Tw='Twareded:BAAANQADCgIIAgAAAA==.Twinkiegisol:BAAANQABCgEIAQAAAA==.Twocansam:BAAANQAECgYIBgAAAA==.Twohandsome:BAACNQAFFIEQAAIeAAYK8iHHAABsAgAeAAYK8iHHAABsAgA1AAQKgRwAAh4ACQorJkABANkDAB4ACQorJkABANkDAAAA.Twøføx:BAAANQAECgUICwAAAA==.',
Ty='Tyinaa:BAAANQAECgMJBgAAAA==.Tyinthael:BAAANQADCgMIAwAAAA==.Tylenoldk:BAAANQADCgMIAwABNQAECgIIBAAEAAAAAA==.Typherin:BAAANQAECgcJEgAAAA==.Tyrallas:BAAANQAECgEIAQAAAA==.Tyrven:BAAANQADCgYIDAAAAA==.',
['Tï']='Tïms:BAAANQAECgIIAgAAAA==.',
Ub='Ubba:BAAANQAECgcIEAAAAA==.',
Ul='Ulannya:BAAANQAECgEIAQABNQAECgQJBAAEAAAAAA==.Ulddon:BAAANQADCgYIBgAAAA==.Ullria:BAAANQADCgYIBgABNQAECgIIAwAEAAAAAA==.',
Un='Undercovrmoo:BAAANQAECgUJDAAAAA==.',
Ur='Urdragon:BAAANQAECgUJDwAAAA==.Urving:BAAANQAECgUICgAAAA==.',
Uw='Uwugnar:BAAANQADCgYIBgABNQAECgUJCQAEAAAAAA==.',
Va='Vaeltheris:BAAANQADCgYICQAAAA==.Vantelantien:BAAANQABCgcICwAAAA==.Vargasbarbas:BAAANQADCgMIAwAAAA==.Varjaz:BAAANQADCggJCwABNQAECggJEwAEAAAAAA==.',
Ve='Vecxlolz:BAAANQABCgUIBQAAAA==.Vecxous:BAAANQABCgYICQAAAA==.Veladar:BAAANQAECgUJCAAAAA==.Velaradraena:BAAANQADCgMIAwAAAA==.Velhunter:BAABNQAECoEcAAIUAAkKiSAnBwA3AwAUAAkKiSAnBwA3AwAAAA==.Velush:BAACNQAFFIEJAAIHAAUKKh5EAQDmAQAHAAUKKh5EAQDmAQA1AAQKgSYAAgcACQoVJiUBAOgDAAcACQoVJiUBAOgDAAAA.Venttress:BAAANQADCgEJAQABNQAECgUJCgAEAAAAAA==.Verdelene:BAAANQAECgcIDgAAAA==.Veressta:BAAANQAECgYJCAAAAA==.Verkk:BAAANQADCgQJBQAAAA==.',
Vi='Vienarissa:BAAANQADCgUICQAAAA==.Vifekoygua:BAAANQAECgQIBAAAAA==.Viralson:BAAANQAECgIIBQAAAA==.Virulnekron:BAABNQAECoEfAAIHAAgKFh8rFQDFAgAHAAgKFh8rFQDFAgAAAA==.Viserysll:BAAANQAECgEJAQABNQAECgUICQAEAAAAAA==.Vitaemors:BAAANQADCgQIBAAAAA==.Vitaminbee:BAABNQAECoEeAAIWAAkKTBb9EQCdAgAWAAkKTBb9EQCdAgAAAA==.',
Vl='Vlnar:BAABNQAECoEfAAIVAAkKYSLCBwBHAwAVAAkKYSLCBwBHAwAAAA==.',
Vo='Voeros:BAAANQADCgEIAQAAAA==.Voidplay:BAAANQAECgEIAgAAAA==.Voyagerebaca:BAAANQADCgYIBwAAAA==.Voyagesoul:BAAANQADCgEIAgAAAA==.',
['Vê']='Vêspera:BAAANQADCgIIAgAAAA==.',
Wa='Wadeboggs:BAAANQAECgcICQABNQAFFAUICQALAN8ZAA==.Warrod:BAAANQAECgYJDAAAAA==.Washabilly:BAABNQAECoEcAAIGAAgKlR6HGADLAgAGAAgKlR6HGADLAgAAAA==.',
We='Welbiner:BAAANQAFFAEIAQAAAA==.',
Wh='Whackem:BAAANQADCgYICwAAAA==.Whookies:BAAANQAECgYIBgAAAA==.Whö:BAAANQADCgIIAgABNQADCgUIBQAEAAAAAA==.',
Wi='Wileyy:BAAANQAECgMIAwAAAA==.Windbinder:BAAANQAECgQJCgAAAA==.Wizfla:BAABNQAECoEhAAMCAAkKThl5MwBQAgACAAgKMRd5MwBQAgADAAIKYBgdRACQAAAAAA==.',
Wo='Wolfluna:BAAANQAECgQIBgAAAA==.Woljin:BAAANQAECgIIAgAAAA==.Woobzk:BAAANQADCgQJDwAAAA==.Woolala:BAAANQAECgUIBQABNQAECgkJHgAWAEwWAA==.Woosiv:BAAANQAECggIEAAAAA==.Woouid:BAAANQADCgYIBgABNQAECggIEAAEAAAAAA==.Woovoke:BAAANQAECgYIBwABNQAECggIEAAEAAAAAA==.Workmoose:BAAANQAECgQIBAAAAA==.Wouldisure:BAAANQADCggIFAAAAA==.',
Ww='Wwiilloow:BAAANQABCgQICgAAAA==.',
Xa='Xanelos:BAAANQADCgYJDgAAAA==.',
Xo='Xoilbiss:BAAANQAECgEIAQAAAA==.',
Ya='Yakia:BAAANQAECggIEAABNQAECgkJKgAKALklAA==.Yanika:BAAANQAECgEIAQAAAA==.Yarellezi:BAAANQABCgQIDQAAAA==.',
Ye='Yehwe:BAAANQAECgEIAQAAAA==.',
Yi='Yiwan:BAAANQAECgcJDwAAAA==.',
Yu='Yuismi:BAAANQAECgQJBgAAAA==.',
Za='Zappd:BAAANQAECgYIBgAAAA==.Zartoga:BAAANQADCgEIAQAAAA==.Zasman:BAAANQAECgQICwAAAA==.Zayabella:BAAANQAECgEIAQAAAA==.',
Ze='Zedrick:BAAANQADCgMIBAAAAA==.Zenchantress:BAAANQADCgEIAQAAAA==.Zephyrea:BAABNQAECoElAAIaAAkKwBttOQDfAgAaAAkKwBttOQDfAgAAAA==.Zerimah:BAAANQAECgMIAwAAAA==.Zerx:BAAANQADCgYIBgAAAA==.Zetrathion:BAABNQAECoEXAAMgAAYKcwnoKwDCAAAgAAUKkQPoKwDCAAAdAAUKsQANKgBXAAAAAA==.',
Zh='Zhakloskar:BAAANQADCgYIBgAAAA==.Zheuz:BAAANQAECgYIBgABNQAECgYIEwAEAAAAAA==.',
Zi='Ziaet:BAAANQADCgMIBAAAAA==.Zingerdk:BAEANQAECgcICgAAAA==.Zinng:BAABNQAECoEdAAQKAAgKPBU8FQBOAgAKAAgKPBU8FQBOAgABAAEKuQoCrAAxAAAkAAEKtwF5IAAnAAAAAA==.',
Zo='Zoalara:BAAANQAECgcJEAAAAA==.Zodiakmage:BAAANQAECgIJAgABNQAFFAIIAgAEAAAAAA==.Zoroph:BAAANQADCgQIBAAAAA==.',
Zs='Zsixfiddy:BAAANQADCgUIBQAAAA==.',
Zz='Zzaq:BAAANQAECgYICgABNQAECgkJHwALAEMhAA==.',
['Zá']='Záhr:BAAANQADCgMJBQAAAA==.',
['Zí']='Zíngerdh:BAEANQAECgEIAQABNQAECgcICgAEAAAAAA==.',
['Æë']='Æëgwynn:BAAANQADCgUIBQAAAA==.',
['Éo']='Éowyn:BAAANQADCgUIFAABNQAECgMIAwAEAAAAAA==.',
['ßt']='ßteel:BAAANQADCggJHQAAAA==.',
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
