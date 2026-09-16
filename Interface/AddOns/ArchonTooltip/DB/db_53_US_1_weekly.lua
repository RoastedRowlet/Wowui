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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Shaman-Elemental','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Evoker-Augmentation','Warlock-Affliction','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Shadow','Druid-Restoration','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Hunter-Survival','Warrior-Arms','Mage-Arcane','Monk-Windwalker','Evoker-Preservation','Shaman-Restoration','Rogue-Outlaw','Paladin-Protection',}
local provider = {region='US',realm='Aegwynn',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aarista:BAAANQADCgMIBgAAAA==.',
Ab='Abhorrere:BAAANQABCgMIAwAAAA==.Abindi:BAAANQABCgYIBgAAAA==.Abruegark:BAAANQADCgcIBwAAAA==.',
Ac='Acedririd:BAAANQAECgMIBAAAAA==.Actuallyy:BAAANQADCgEIAQAAAA==.',
Ad='Ad:BAAANQAECgQIBAAAAA==.Adönis:BAAANQADCgIIAgAAAA==.',
Ae='Aellerr:BAAANQAECgUIBQAAAA==.',
Af='Affyou:BAAANQAECgEIAgAAAA==.Afuapril:BAAANQABCgIIAgAAAA==.',
Ah='Ahzidal:BAAANQAFFAEIAQAAAA==.',
Ai='Ailbhe:BAAANQADCgYIBQAAAA==.Airbinwl:BAABNQAECoEWAAMBAAkJvR/iDwDiAgABAAgJ+x7iDwDiAgACAAIJPSRDLwDTAAAAAA==.Aitchbar:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.',
Ak='Akanaar:BAAANQADCgIIAwAAAA==.Akilleess:BAAANQAECgIIAgABNQAECgMIAwADAAAAAA==.',
Al='Alaw:BAAANQAECgUIBgAAAA==.Alexdd:BAAANQADCgEIAQAAAA==.Alexiathorne:BAAANQADCgEIAQABNQAECgUIBgADAAAAAA==.Alextros:BAEANQAECgUICgAAAA==.Alivana:BAAANQADCgUICgABNQAECgQIBQADAAAAAA==.Almaris:BAABNQAECoEaAAIEAAgJByNCFQD3AgAEAAgJByNCFQD3AgAAAA==.Aloreilina:BAAANQADCgMIAwAAAA==.Alèx:BAAANQAFFAEIAQAAAA==.',
Am='Amarielle:BAAANQAECgUIDAAAAA==.Amire:BAAANQADCgYIFQAAAA==.Ammastolamor:BAAANQADCgIIAgAAAA==.',
An='Anahanu:BAABNQAECoEdAAIFAAkJbRyWDwDyAgAFAAkJbRyWDwDyAgAAAA==.Andrin:BAAANQADCgYICwAAAA==.Angelawitch:BAAANQAECgMIAQABNQAECgcIEgADAAAAAA==.Angienursey:BAAANQAECgcIEgAAAA==.Annamolly:BAAANQAECgEIAQAAAA==.Ansitris:BAAANQADCgQIBAAAAA==.Antibiotix:BAAANQAECgYIEgAAAA==.',
Ap='Apocrithon:BAAANQADCgQIBQABNQAECgEIAQADAAAAAA==.Apros:BAAANQAECgYICwAAAA==.',
Aq='Aqss:BAABNQAECoEdAAIGAAkJUx7BDwAKAwAGAAkJUx7BDwAKAwAAAA==.',
Ar='Arakhana:BAAANQADCggICgAAAA==.Aralleah:BAAANQAECgEIAwABNQAECgQIBQADAAAAAA==.Aratoreii:BAAANQADCgIIAgAAAA==.Arbinshaman:BAAANQAECgMIAwAAAA==.Archide:BAAANQAECgQIBwAAAA==.Archidus:BAAANQADCgcIBwAAAA==.Arctose:BAAANQAECgcIDAAAAA==.Ardoniak:BAAANQADCggIDgAAAA==.Argenoth:BAAANQADCgIIAwAAAA==.Arkaeon:BAAANQAECgIIBAAAAA==.Arthar:BAAANQADCgEIAQAAAA==.',
As='Asdsfe:BAAANQAECgUIBgAAAA==.Ashandrei:BAAANQAECgQIBgAAAA==.Ashletil:BAAANQADCgIIAwAAAA==.Astraeadawn:BAAANQADCgMIAwAAAA==.Aszkme:BAAANQADCgUIBwAAAA==.',
At='Atri:BAAANQADCgUIBQABNQAECgQIBQADAAAAAA==.',
Au='Auran:BAAANQAECgQIBAAAAA==.Authority:BAABNQAECoEWAAIHAAYJJhsaPwD8AQAHAAYJJhsaPwD8AQAAAA==.Autismosteve:BAAANQAECgUICgAAAA==.',
Av='Avanlythia:BAAANQADCgYIBgABNQAECgQIBQADAAAAAA==.Avlee:BAAANQADCgQIBAAAAA==.',
Aw='Aware:BAABNQAECoEUAAMIAAgJDSFdBwDeAgAIAAgJDSFdBwDeAgAJAAYJhxt0GAC+AQAAAA==.',
Az='Azathox:BAAANQABCgEIAQAAAA==.Azzuhpala:BAABNQAECoEZAAIKAAkJOBFQIABkAgAKAAkJOBFQIABkAgAAAA==.',
Ba='Baboonki:BAAANQADCgcIBwAAAA==.Baddracthyr:BAABNQAECoEdAAILAAkJoBEWBAAhAgALAAkJoBEWBAAhAgAAAA==.Balderus:BAAANQAECgQICAAAAA==.Banjophd:BAAANQAECgEIAQAAAA==.Baracus:BAAANQADCggICAAAAA==.Batareva:BAAANQAECgYIDwAAAA==.Batavira:BAAANQADCgUICAABNQAECgYIDwADAAAAAA==.Bayrock:BAAANQABCgIIAgAAAA==.',
Be='Beamnord:BAAANQAECgQIBgAAAA==.Beanie:BAAANQADCggIEQAAAA==.Bearlyere:BAAANQAECgYIDAAAAA==.Beastshine:BAAANQADCgYIEAAAAA==.Bendemus:BAABNQAECoESAAQCAAcJIQ81FQCgAQACAAcJGg41FQCgAQAMAAIJOw6KEwBjAAABAAEJhgEz0QAUAAAAAA==.Bentléy:BAAANQADCgEIAQAAAA==.Berserkguts:BAAANQAECgQIBgAAAA==.Bersk:BAAANQADCgQIBAAAAA==.',
Bi='Bigdeez:BAAANQADCgUIBQABNQAECgQIBgADAAAAAA==.Bigker:BAAANQADCgIIAgAAAA==.Bigzaddy:BAAANQADCgYIBgAAAA==.Bigzas:BAAANQAECgEIAQABNQAECgQIBwADAAAAAA==.Bitrot:BAAANQAECgcICQAAAA==.',
Bl='Blameray:BAAANQADCggICAAAAA==.Blindbuns:BAAANQADCgYIDAAAAA==.Blokejr:BAAANQADCggIDwABNQAECgQIBgADAAAAAA==.Blooddagger:BAAANQAECgcIDwAAAA==.Bloodeater:BAAANQADCgYIBgAAAA==.Bloodnyte:BAAANQAECgEIAQAAAA==.',
Bo='Bodhmal:BAABNQAECoEcAAIFAAkJTBQOFwCZAgAFAAkJTBQOFwCZAgABNQAECgcIEgADAAAAAA==.',
Br='Braass:BAAANQADCgYIBgABNQAECgYIDwADAAAAAA==.Braassra:BAAANQADCgIIAgABNQAECgYIDwADAAAAAA==.Brahe:BAAANQADCgYICgAAAA==.Brandun:BAAANQADCgYIBgAAAA==.Brethe:BAAANQADCgUIBQAAAA==.Brokíìnn:BAABNQAECoEXAAIHAAgJaBkCIgB/AgAHAAgJaBkCIgB/AgAAAA==.Broncas:BAAANQADCgEIAQAAAA==.Brucebearner:BAAANQAECggIDAAAAA==.Bruff:BAAANQAECgUIBQAAAA==.Brufknight:BAAANQAECgEIAQAAAA==.Brufwar:BAAANQADCgcIBwAAAA==.Brókiinn:BAAANQADCggIDAAAAA==.',
Bu='Bukhanee:BAAANQAECgMIBAAAAA==.Burmtron:BAAANQADCggIGwABNQAECgIIAgADAAAAAA==.Burmtronn:BAAANQAECgIIAgAAAA==.Bustabolt:BAAANQAECgYIDQAAAA==.Buterfinger:BAAANQADCgUIBQABNQADCgcIEwADAAAAAA==.',
Bw='Bwansamdeez:BAAANQABCgIIAgABNQADCgUIBQADAAAAAA==.',
['Bò']='Bòoty:BAAANQAECgMIAwAAAA==.',
Ca='Caceynn:BAAANQAECgIIAgAAAA==.Calamatous:BAAANQADCgMIAwAAAA==.Caldrath:BAAANQABCgIIAgAAAA==.Candyditto:BAAANQAECgIIAgABNQAFFAYIDQAKAP4XAA==.Caoinlean:BAAANQADCgcIDQAAAA==.Carebearcare:BAABNQAECoEfAAMNAAkJ8B1cAgAPAwANAAkJ8B1cAgAPAwAOAAEJTwCtHwAjAAAAAA==.Cattledecap:BAAANQABCgIIAgAAAA==.',
Ce='Celiaisake:BAAANQAECgIIAgAAAA==.Celorleran:BAAANQADCgMIAwAAAA==.Ceruibas:BAAANQAECgMIAwAAAA==.Cev:BAAANQADCgEIAQABNQAECgcIEQADAAAAAA==.',
Ch='Chaoscat:BAAANQAECgQIBAAAAA==.Chaossparkie:BAAANQAECgIIBAAAAA==.Charlight:BAAANQAECgQIBAAAAA==.Cheddarclaps:BAAANQABCgEIAQAAAA==.Cheeksdemon:BAAANQADCggIGwAAAA==.Cheesefriess:BAAANQAECgQIBQAAAA==.Chetan:BAAANQADCgEIAQAAAA==.Chuckknight:BAAANQADCgYICQAAAA==.Chuttbeeks:BAAANQAECgQICAAAAA==.',
Ci='Cisnei:BAAANQAECgEIAQABNQAECgMIBgADAAAAAA==.',
Co='Coggwalker:BAAANQADCgUIBgAAAA==.Colbyjax:BAAANQADCggICAABNQAECgQIBwADAAAAAA==.Coldiloks:BAAANQAECgQIBgAAAA==.Corgruumn:BAAANQADCgMIAwAAAA==.',
Cr='Crastak:BAAANQAECgQICQAAAA==.Crazyliquer:BAAANQADCgcIEwAAAA==.Crisy:BAAANQAECgYIDwAAAA==.Crotailor:BAAANQADCgQIBAAAAA==.',
Cy='Cyndk:BAEANQADCgcIBwABNQADCggICAADAAAAAA==.Cyniel:BAEANQADCggICAAAAA==.',
Da='Dabbz:BAAANQAECgEIAQAAAA==.Daez:BAAANQADCgYICAABNQAECgYICgADAAAAAA==.Dahampster:BAAANQADCgcICwAAAA==.Dahleya:BAAANQADCgUIAgAAAA==.Dailna:BAAANQAECgIIBAAAAA==.Dalamri:BAAANQADCgcIBwAAAA==.Dalarrorn:BAAANQADCgQIBwAAAA==.Dalitha:BAAANQAECgMIBAAAAA==.Dallart:BAAANQAECggIBgAAAA==.Dalonar:BAAANQADCgYIBgAAAA==.Damrath:BAAANQADCgQIBAAAAA==.Danhunter:BAACNQAFFIEGAAIPAAQJvREIBgAvAQAPAAQJvREIBgAvAQA1AAQKgRcAAw8ACQkhIkMOAKQCAA8ACQlJH0MOAKQCAAcAAwmAJYZ4ADQBAAAA.Danoriye:BAAANQAECgMIAwAAAA==.Darazana:BAAANQADCgUIBQAAAA==.Darkclawfox:BAAANQADCgQIBAAAAA==.Darknarsin:BAAANQAECgIIAgAAAA==.Davbarx:BAAANQABCgQIBgAAAA==.Days:BAAANQAECgEIAQABNQAECgYICgADAAAAAA==.Daysha:BAAANQADCgQIBAAAAA==.Daze:BAAANQAECgYICgAAAA==.Dazuiio:BAAANQAECgIIAgAAAA==.Dazzboomie:BAAANQABCgQIBAAAAA==.',
De='Deadrice:BAAANQAECgMIAwAAAA==.Declines:BAAANQADCgYICAAAAA==.Delfriet:BAAANQADCgYIDAAAAA==.Delso:BAAANQADCggIDQAAAA==.Deltasara:BAAANQADCggICwAAAA==.Demonarbin:BAAANQAECgcIBwAAAA==.Demonkcorb:BAAANQADCggICAAAAA==.Deviljin:BAAANQADCgYIBgAAAA==.Deysonis:BAAANQAECgIIBAAAAA==.',
Dh='Dhbear:BAACNQAFFIEFAAIQAAMJFAq2BAD3AAAQAAMJFAq2BAD3AAA1AAQKgR8AAxAACQnVGfYIAAUDABAACQnVGfYIAAUDABEACAlUAyUqAGwBAAAA.',
Di='Diligence:BAAANQADCgEIAgAAAA==.Dingberry:BAAANQAECgcIDwAAAA==.Dioghaltair:BAAANQADCgUIBQAAAA==.Diphyidae:BAAANQAECgEIBQAAAA==.Diyatea:BAAANQAECgQIBwAAAA==.Dizzle:BAAANQAECgEIAQAAAA==.',
Dm='Dmininstries:BAAANQAECggIBAAAAA==.',
Do='Dodgeypoo:BAEANQADCggIFAAAAA==.Domit:BAAANQADCgUICQAAAA==.Dommag:BAAANQAECgEIAQAAAA==.Doostfraba:BAAANQADCgQIBQAAAA==.Doots:BAAANQADCggIEAAAAA==.Dopey:BAAANQAECgUIDQAAAA==.Dorkplatypus:BAABNQAECoEYAAISAAgJixVyEABhAgASAAgJixVyEABhAgAAAA==.Doski:BAAANQAECgIIAgABNQAECgcICQADAAAAAA==.',
Dr='Dracoarbatel:BAAANQADCgUICAAAAA==.Dragindeezz:BAAANQAECgEIAQABNQAECgkJHwARAJIjAA==.Dragindemons:BAABNQAECoEfAAIRAAkJkiMBAwCTAwARAAkJkiMBAwCTAwAAAA==.Dragness:BAAANQADCgcIBwAAAA==.Dragonbox:BAAANQAECgYIBgAAAA==.Dragonfroot:BAAANQAECgQICAAAAA==.Drakgo:BAAANQAECgYICwAAAA==.Dravenuz:BAABNQAECoEbAAITAAkJex+WAwA7AwATAAkJex+WAwA7AwAAAA==.Dreadarc:BAAANQADCgUIBQABNQAECgQICAADAAAAAA==.Drespirit:BAAANQAECgIIAwAAAA==.Drewscylla:BAAANQAECgUICAAAAA==.Drgparkbench:BAAANQAECgEIAQAAAA==.Dripsyfist:BAAANQAECggIEAAAAA==.Drixor:BAAANQAECgEIAQAAAA==.Drone:BAAANQAECgYIBgABNQAECgkJFQAUAOMmAA==.Druiden:BAAANQAECgYICgABNQAFFAIIBQAVAAYRAA==.Drumok:BAAANQAECgQIBgAAAA==.Dríxx:BAAANQADCgYIEQAAAA==.',
Du='Dumbledoof:BAAANQADCgcIFAAAAA==.',
['Dâ']='Dâthomir:BAAANQAECgQIBwAAAA==.',
['Dî']='Dîsfoo:BAAANQABCgYICAAAAA==.',
Ea='Earlragnarl:BAAANQADCgEIAQAAAA==.',
Eb='Ebonyeti:BAAANQADCgEIAQAAAA==.',
Ec='Echarge:BAAANQAECgQIEAAAAA==.',
Ed='Edandith:BAAANQAECgYICgAAAA==.Edsilencek:BAAANQAECgIIAwAAAA==.',
Ei='Eizenhorn:BAAANQAECgYICgAAAA==.',
El='Elasthanan:BAAANQADCgEIAQAAAA==.Eleinna:BAAANQAECgQIBQAAAA==.Ellodie:BAAANQAECgQIBgAAAA==.Ellíe:BAAANQAECgMIBQABNQAECgkJGQAWAJoSAA==.Elmyndreda:BAAANQAECgEIAQAAAA==.Elrion:BAAANQAFFAEIAQAAAA==.Eludin:BAAANQADCgcIDQAAAA==.Elwynyssa:BAABNQAECoEaAAINAAkJNiLkAACWAwANAAkJNiLkAACWAwAAAA==.',
Em='Emardo:BAAANQADCgQIBAAAAA==.Emberly:BAAANQADCggICAAAAA==.Embiix:BAAANQADCgEIAQAAAA==.Emelia:BAAANQADCgIIAwAAAA==.Emptythreats:BAAANQADCgYIDwAAAA==.',
En='Enelyancalim:BAAANQADCgYICgAAAA==.',
Er='Eraliela:BAAANQADCgEIAQAAAA==.Erudite:BAABNQAECoEYAAIRAAcJHQ5jIQDEAQARAAcJHQ5jIQDEAQAAAA==.',
Et='Eteru:BAAANQADCggIFgAAAA==.',
Eu='Euna:BAAANQAECgIIAgAAAA==.',
Ev='Evilneohuan:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.',
Ex='Exosix:BAAANQABCgYIBgAAAA==.',
Ey='Eyko:BAAANQAECgcIDgAAAA==.',
['Eä']='Eädgyth:BAABNQAECoEhAAIXAAcJ/xNJKwDiAQAXAAcJ/xNJKwDiAQAAAA==.',
Fa='Fafader:BAAANQADCgYIBwAAAA==.Farbauti:BAAANQAECgYIEwAAAA==.Fascinus:BAAANQABCgQIBAAAAA==.',
Fe='Fedrk:BAAANQADCgUIDAABNQADCggIEwADAAAAAA==.Fedu:BAAANQAFFAEIAQAAAA==.Feldesk:BAAANQAECgQIEwAAAA==.Fellich:BAAANQAECgQIBQAAAA==.Felspike:BAAANQADCgMIAwAAAA==.Fenrii:BAAANQADCgIIAgAAAA==.Ferp:BAAANQAECgQIBQAAAA==.Festered:BAAANQAECgUICwAAAA==.',
Fi='Fizzcopper:BAABNQAECoEcAAIYAAkJKx7gAAAxAwAYAAkJKx7gAAAxAwAAAA==.',
Fk='Fkwalmart:BAAANQADCggIDgABNQAECgkJHQAZAFkiAA==.',
Fl='Flavortheman:BAAANQABCgMIAgAAAA==.Flit:BAAANQAECgMIBgAAAA==.Flitmg:BAAANQADCgQIBwAAAA==.Flowersnight:BAAANQAECgUICAAAAA==.Flowerx:BAAANQADCggICAABNQAECgEIAgADAAAAAA==.Flowerxx:BAAANQAECgEIAgAAAA==.',
Fo='Fontanie:BAAANQADCgIIAgAAAA==.Fontaniebear:BAAANQABCgIIAgABNQADCgIIAgADAAAAAA==.Formroll:BAAANQADCggIGgAAAA==.Foxyashammy:BAAANQADCgMIAwAAAA==.',
Fr='Freakdawg:BAAANQAECgMIBAAAAA==.Freetime:BAAANQAECgEIAQAAAA==.Freyabloom:BAAANQAECgEIAQAAAA==.Froozxcdk:BAAANQAECgEIAQABNQAECgcIBgADAAAAAA==.Froozxchunt:BAAANQAECgcIBgAAAA==.Froozxcwarr:BAAANQAECgYIBgAAAA==.Fruitloops:BAAANQADCgIIAgAAAA==.',
Ga='Gabbiani:BAAANQADCggIFwAAAA==.Galondrake:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.Galonzenith:BAAANQAECgEIAQAAAA==.Garamor:BAAANQADCgUIBQAAAA==.Gargaki:BAAANQADCgUIAwAAAA==.Garm:BAAANQADCgEIAQAAAA==.Gartahuuliya:BAAANQABCgIIAgAAAA==.Garyboldman:BAAANQADCgIIAwAAAA==.Gazlowe:BAAANQADCgUIBQAAAA==.',
Ge='Geldrath:BAAANQADCgEIAQAAAA==.Geldrin:BAAANQAECgIIAgAAAA==.Genoddhunter:BAAANQAECgcIDgAAAA==.Gerfbert:BAAANQAECgYIDQAAAA==.Geø:BAAANQADCgYIDwAAAA==.',
Gi='Giantess:BAAANQAECgYIDgABNQAECgcIBwADAAAAAA==.Gibbygibby:BAAANQAECgQIBgABNQAECgQICAADAAAAAA==.Giggityz:BAAANQADCgcIDwAAAA==.Gigidygoo:BAAANQADCgMIAwAAAA==.Gilreth:BAAANQAECgcIEQAAAA==.Gilzaur:BAAANQAECgUICgAAAA==.Gimlad:BAAANQADCgQIBAAAAA==.Gimrr:BAAANQAECgIIBAAAAA==.Gimurr:BAAANQADCgMIAwABNQAECgIIBAADAAAAAA==.Gixrdano:BAAANQADCgQIBAAAAA==.',
Gj='Gjeoff:BAAANQAECgEIAQAAAA==.',
Gl='Glasshealing:BAAANQAECgQICAAAAA==.',
Gn='Gnomepunzel:BAAANQADCgcIEgAAAA==.',
Go='Goldplated:BAAANQADCgcIBwAAAA==.Goodys:BAAANQADCggICQAAAA==.Goopstick:BAAANQAECgQIBAAAAA==.Goratrix:BAAANQADCgEIAQAAAA==.Gorewood:BAAANQADCgUICAAAAA==.Gorillamage:BAAANQAECgIIAgAAAA==.Gortu:BAAANQADCgYIBgAAAA==.Gotag:BAAANQAECgYIDAAAAA==.',
Gr='Gravefang:BAAANQAECggICAAAAA==.Greatdeku:BAAANQADCgMIBAAAAA==.Grimmby:BAAANQAECgMIAwAAAA==.Grung:BAAANQAECgYIDwAAAA==.',
Gu='Guldum:BAAANQADCgMIAwAAAA==.Gumbynutte:BAAANQAECgQIBgAAAA==.',
Gw='Gwenita:BAAANQAECgQICAAAAA==.Gwiontotems:BAEANQAECgEIAQABNQAECgIIAgADAAAAAA==.',
Gy='Gyarados:BAAANQADCgUICAAAAA==.Gyokuro:BAAANQAECgQIBQABNQADCgUIBQADAAAAAA==.',
['Gí']='Gízy:BAAANQAECgUIEAAAAA==.',
Ha='Habdearn:BAAANQADCgcIDgAAAA==.Hailey:BAEANQAFFAEIAgAAAA==.Hakunapotato:BAAANQAECgQIBAAAAA==.Halfe:BAAANQADCgUIBQAAAA==.Hamchowder:BAAANQADCgIIAgAAAA==.Hameey:BAAANQAECgQIBgAAAA==.Haranitony:BAAANQAECgYICgAAAA==.Havreth:BAAANQADCggICQAAAA==.Hazzardd:BAAANQAECgQICAAAAA==.',
He='Heallium:BAAANQADCggIAgAAAA==.Heelie:BAAANQADCgYICgAAAA==.Heleris:BAAANQADCggIDQAAAA==.Helgalila:BAAANQAECgQIBQAAAA==.Helmia:BAAANQADCggICQAAAA==.Hemoglobe:BAAANQADCgEIAQABNQAECgUICQADAAAAAA==.Heughjanus:BAAANQAECgYICgAAAA==.Hexonna:BAAANQAECgEIAQAAAA==.Hexshade:BAAANQADCgEIAQAAAA==.',
Hi='Hidere:BAAANQADCgEIAQAAAA==.',
Hl='Hlyparkbench:BAABNQAECoEZAAIKAAkJDhi2EADeAgAKAAkJDhi2EADeAgABNQAECgEIAQADAAAAAA==.',
Ho='Hodge:BAAANQAECgQIBAABNQAECgQIBgADAAAAAA==.Hodgey:BAAANQAECgQIBgAAAA==.Holycrapola:BAAANQAECgIIAgAAAA==.Holyhero:BAEANQADCgQIBAABNQADCggIFAADAAAAAA==.Holykcorb:BAAANQAECgMIAwAAAA==.Holymat:BAAANQADCgEIAQAAAA==.Holytweak:BAAANQAECgQIBAAAAA==.Hoovion:BAAANQADCgMIAwAAAA==.',
Hu='Hudimm:BAAANQAECgMIAwAAAA==.Huggsnkisses:BAAANQAECgEIAQAAAA==.Hunglownewb:BAAANQADCgQIBAAAAA==.Hunho:BAAANQAECggIBwAAAA==.Hunterjohn:BAAANQADCgEIAQAAAA==.',
Hy='Hynarillan:BAAANQADCgIIAQAAAA==.Hyorin:BAAANQADCggIHAAAAA==.',
Ic='Icken:BAAANQADCgcIDAAAAA==.',
Id='Idefkanymore:BAAANQADCggIGwAAAA==.Idomage:BAAANQADCgUIBQAAAA==.',
Ii='Iinning:BAAANQADCgIIAQABNQAECgQIBAADAAAAAA==.',
Il='Illidhanae:BAAANQAECgEIAQABNQAECgMIBQADAAAAAA==.Iludron:BAAANQADCgYICQAAAA==.',
Im='Immaculates:BAAANQABCgIIAgAAAA==.Immunized:BAEANQADCgQIBgABNQADCgYICwADAAAAAA==.Imoquai:BAAANQADCggIDQAAAA==.Impedance:BAAANQADCggIEAAAAA==.Imyaboi:BAAANQAECgIIAgAAAA==.Imzáiah:BAAANQAECgEIAQAAAA==.',
In='Inforgame:BAAANQADCgUIBQAAAA==.Inkhunter:BAAANQADCgMIAwAAAA==.Inkmoon:BAAANQAECgMIAwAAAA==.Inningg:BAAANQAECgQIBAAAAA==.Insânity:BAAANQAECgEIAQAAAA==.Invictus:BAAANQAECgIIAgAAAA==.Invoided:BAAANQAECggICAAAAA==.',
Io='Ioweyouheals:BAAANQADCgcICwAAAA==.',
Ir='Ironaimorc:BAAANQADCgcIBwAAAA==.',
Is='Ishara:BAAANQADCgcIBwAAAA==.Isharian:BAAANQAECgUIDQAAAA==.Islandponder:BAAANQADCgMIBwABNQAECgQIEwADAAAAAA==.',
It='Ithrowscars:BAAANQAECgYICgAAAA==.',
Iv='Ivera:BAAANQAECgIIAgAAAA==.',
Ja='Jaliardys:BAAANQAECgcIEwAAAA==.Jareth:BAAANQADCgcIEAAAAA==.Jax:BAAANQADCgcIDQAAAA==.Jaxius:BAAANQAECgMIBgAAAA==.Jayia:BAABNQAECoEjAAIaAAkJ/SN7EgBaAwAaAAkJ/SN7EgBaAwAAAA==.Jayie:BAAANQAECgcIDwABNQAECgkJIwAaAP0jAA==.',
Je='Jedazar:BAAANQADCgUIBQAAAA==.Jefeli:BAAANQABCgEIAQAAAA==.',
Ji='Jijidruid:BAAANQADCgQIBAAAAA==.Jimf:BAAANQADCgUIBQAAAA==.Jinzi:BAAANQAECgUIBgAAAA==.',
Jj='Jjbang:BAAANQAECgUIBgAAAA==.',
Jm='Jmel:BAAANQADCgIIAgAAAA==.',
Jo='Jojomars:BAAANQADCgcICgAAAA==.Joosseri:BAAANQADCgYIEAAAAA==.Jorkho:BAAANQADCgQIBAAAAA==.Josespala:BAAANQAECgEIAgAAAA==.Journeydd:BAAANQADCgcIFwAAAA==.',
Ju='Judhar:BAAANQABCgIIAgAAAA==.Juggernutz:BAAANQADCggICAAAAA==.',
['Jí']='Jíjì:BAAANQABCgUIAwAAAA==.',
Ka='Kaelish:BAAANQADCgIIAwAAAA==.Kafeene:BAAANQABCgQIBAAAAA==.Kagargo:BAAANQAECgQIBgAAAA==.Kahlel:BAAANQADCgEIAQAAAA==.Kaldareth:BAAANQAECggIBwAAAA==.Kalnamos:BAABNQAECoEZAAIbAAgJHR6iCADUAgAbAAgJHR6iCADUAgAAAA==.Kaorinite:BAAANQAECgUIDAAAAA==.Karismâ:BAAANQAECgIIAgAAAA==.Kataela:BAAANQADCggICAAAAA==.Katanovich:BAAANQAECgMIBAAAAA==.Katixx:BAAANQADCgYICgAAAA==.Katparkbench:BAAANQADCgYIEAABNQAECgEIAQADAAAAAA==.Katyperryfan:BAAANQADCgUIBQAAAA==.Kauketkenna:BAAANQADCgUIBgAAAA==.Kaynfel:BAAANQADCgUIBQAAAA==.',
Ke='Kegan:BAAANQAECgEIAQAAAA==.Kela:BAACNQAFFIEGAAMJAAQJsAq1BAD8AAAJAAMJoQ21BAD8AAAIAAEJ3AETCwBMAAA1AAQKgRoAAwkACQksIjUFAAkDAAkACAkOITUFAAkDAAgAAwmpH3MpABgBAAAA.Kelezekan:BAAANQAECgQIBgAAAA==.Kelilina:BAAANQAECgQIBQAAAA==.Keyelements:BAAANQADCgcIDQAAAA==.',
Kh='Khafie:BAABNQAECoEdAAIcAAkJuxA3DgBDAgAcAAkJuxA3DgBDAgAAAA==.',
Ki='Killtech:BAAANQAECgQIBgAAAA==.Kimanip:BAAANQAECgMIBAAAAA==.Kimdeath:BAAANQAECgYIBgAAAA==.Kiraredclaw:BAAANQAECgQIBAAAAA==.Kirolor:BAAANQABCgIIAgAAAA==.Kitsukko:BAAANQAECgIIAgABNQAECgcIBwADAAAAAA==.',
Kj='Kjarten:BAAANQADCgQIBQABNQAECgYIDgADAAAAAA==.',
Ko='Kolu:BAAANQAECgYIDAAAAA==.Korgara:BAAANQAECgIIAgAAAA==.Kozma:BAAANQADCgIIAgAAAA==.',
Kr='Kraedeyn:BAAANQAECgcIDQABNQADCgYIBgADAAAAAA==.Kraethas:BAAANQADCgEIAQAAAA==.Kraseva:BAAANQAECgEIAQAAAA==.Krell:BAAANQAECgEIAQAAAA==.Krestfallen:BAAANQAECgEIAQAAAA==.Kreyath:BAAANQADCgEIAQAAAA==.Kriek:BAAANQAECgYICQAAAA==.Krissiis:BAAANQADCgMIBAABNQADCgcIEgADAAAAAA==.Krixor:BAAANQADCgcICgABNQAECgEIAQADAAAAAA==.Kråft:BAAANQAECgEIAgABNQAECgIIAgADAAAAAA==.',
Ku='Kurolola:BAAANQABCgMIAwAAAA==.Kurome:BAAANQAECgQICAAAAA==.',
Ky='Kynam:BAAANQAECgUIBgAAAA==.',
La='Landazanso:BAAANQADCgcICgAAAA==.Latina:BAAANQAECgYICQAAAA==.Laynna:BAAANQAECgQIBQAAAA==.',
Le='Leguiz:BAAANQAECgcIEQAAAA==.Lemondreams:BAABNQAECoEVAAMHAAkJcB6DIgB8AgAHAAgJlSGDIgB8AgAPAAcJyRnwFwAPAgAAAA==.Lemontree:BAAANQAECgEIAgAAAA==.Leorihk:BAAANQADCgIIAwAAAA==.Lerius:BAAANQADCgYIDAAAAA==.Leroyak:BAAANQADCgUIBgAAAA==.',
Li='Lightshadows:BAAANQAECgQICAAAAA==.Lilpikky:BAAANQAECgUICQAAAA==.Lionfish:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.Lirael:BAAANQADCgYICAAAAA==.Lizzborden:BAAANQADCgIIAwAAAA==.Lièrén:BAAANQAECgcIEQAAAA==.',
Lo='Lokjikju:BAAANQABCgUIBgAAAA==.Lolada:BAAANQADCgEIAQAAAA==.Lonemadness:BAAANQADCgQIBQAAAA==.Longthorne:BAAANQADCgYIBgABNQAFFAEIAQADAAAAAA==.Lookitzmee:BAAANQADCggIDgAAAA==.Lostagro:BAAANQADCgIIAgAAAA==.',
Lu='Lucixn:BAAANQADCggIEQAAAA==.Lughbelenus:BAAANQAECgEIAQAAAA==.Luminitz:BAAANQAECgcIBwAAAA==.Lummytumkins:BAAANQAECgIIBAAAAA==.Luxdk:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.Luxmage:BAAANQAECgIIAgAAAA==.',
Ly='Lyoko:BAAANQADCgcIDgAAAA==.Lyssandris:BAAANQAECgcIDwAAAA==.Lythany:BAAANQADCgcIFAAAAA==.',
['Lö']='Löckrocks:BAAANQAECgEIAgAAAA==.',
['Lø']='Løkira:BAAANQADCgYIBwABNQAECgIIAgADAAAAAA==.',
Ma='Maandia:BAAANQAECggIAwAAAA==.Mackncheese:BAAANQAECgQIBQAAAA==.Madigan:BAAANQADCgMIAwAAAA==.Maghhard:BAAANQAECgYIDAAAAA==.Magyst:BAAANQAECgYICgAAAA==.Maicyclone:BAAANQADCgYIBgAAAA==.Malanas:BAAANQAECgEIAQAAAA==.Malishine:BAAANQADCgMIAwAAAA==.Manabender:BAAANQAECgIIAgAAAA==.Mannersback:BAAANQAECggIDgAAAA==.Mannethal:BAAANQADCgYIBgAAAA==.Marrylou:BAAANQADCgYIDQAAAA==.Martelstorm:BAAANQAECgEIAQAAAA==.Materus:BAAANQAECgQIDwAAAA==.Mato:BAAANQADCgYIBgAAAA==.Matxhias:BAAANQADCggIEAAAAA==.Mavvick:BAAANQADCgQIBAAAAA==.Maxasoul:BAAANQADCgYIBgAAAA==.Mazzakeene:BAAANQAECgEIAQAAAA==.',
Mc='Mcgrizzy:BAAANQAECgMIAwAAAA==.Mcthor:BAAANQAECgMIAwAAAA==.',
Me='Megasham:BAABNQAECoEdAAMdAAkJKh7ACwAKAwAdAAkJKh7ACwAKAwAGAAEJwQoWvwAvAAAAAA==.Meion:BAEANQAECgEIAQAAAA==.Melcam:BAAANQADCgYICAAAAA==.Metalspike:BAAANQADCgUIAwAAAA==.',
Mg='Mgdk:BAAANQAECgMIAwAAAA==.',
Mh='Mhorea:BAAANQAECgQIBQAAAA==.',
Mi='Miniash:BAAANQAECgMIAwAAAA==.Minox:BAAANQAECgEIAQAAAA==.Mismage:BAAANQAECgQIBwAAAA==.Mistlore:BAAANQAECgQIBgAAAA==.Mistyfist:BAAANQADCgYIBwAAAA==.Miyamotosaki:BAAANQADCgEIAQAAAA==.Mizuree:BAAANQADCgMIAwAAAA==.',
Mo='Moldywater:BAAANQADCgYIBgAAAA==.Monjax:BAAANQADCgYICQABNQAECgMICAADAAAAAA==.Monkyblooms:BAAANQAECgYIDAAAAA==.Monmook:BAAANQAECgYIEQAAAA==.Moonfir:BAAANQADCgQIBgAAAA==.Moosah:BAABNQAECoEXAAIRAAgJhReDEgB0AgARAAgJhReDEgB0AgABNQAECgIIAgADAAAAAA==.Moosetafa:BAAANQAECgUICAAAAA==.Moosubi:BAAANQAECgIIAgAAAA==.Morgoonis:BAAANQAECgYICwAAAA==.Morphyus:BAABNQAECoEYAAITAAkJYhK1DABiAgATAAkJYhK1DABiAgAAAA==.Mostlynotgay:BAAANQAECgQIBQAAAA==.Moxxz:BAAANQADCgQICQAAAA==.',
Mu='Mudmuncher:BAAANQAECgMIAwAAAA==.Muggernaut:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.Mundergy:BAAANQADCggICAABNQAECgQIBAADAAAAAA==.Murazor:BAAANQAECgYIDgAAAA==.Mutilager:BAAANQAECgQIBgAAAA==.Mutilass:BAAANQABCggICgAAAA==.',
My='Myeaasee:BAAANQAECgQIBgAAAA==.Mykickthirty:BAAANQAECgYIBQAAAA==.',
['Mà']='Màsnart:BAAANQADCgQIBQABNQAECgYIBgADAAAAAA==.',
['Má']='Mágaidh:BAAANQAECgQIBAAAAA==.',
['Mî']='Mîko:BAABNQAECoEYAAIeAAkJMSDBAAB9AwAeAAkJMSDBAAB9AwAAAA==.',
Na='Naeyty:BAAANQAECgIIAwAAAA==.Nahid:BAAANQADCgYIBwAAAA==.Nahtikalelle:BAAANQAECgMIBQABNQAECgYIDwADAAAAAA==.Najmuldeen:BAAANQAECgEIAQAAAA==.Namewee:BAAANQABCgYIBwAAAA==.Narcana:BAAANQAECgYICgABNQAECgMIBgADAAAAAA==.Narradrex:BAAANQADCgMIAwAAAA==.Narusa:BAAANQAECgMIBAAAAA==.Nastyysham:BAAANQADCggIGwAAAA==.Naturescienc:BAAANQAECgIIAgAAAA==.',
Nd='Ndh:BAAANQAECgQIBAAAAA==.',
Ne='Neblissa:BAAANQADCgYICQAAAA==.Nefeli:BAAANQADCgUIBQAAAA==.Negu:BAAANQAECgUIBgAAAA==.Nejedi:BAAANQADCgEIAQABNQADCgYICQADAAAAAA==.Neodknight:BAAANQAECgUICwAAAA==.Neohuan:BAAANQAECgEIAQAAAA==.Neomourne:BAAANQADCgcIDQABNQAECgEIAQADAAAAAA==.Neoplasm:BAAANQADCgYIBgABNQAECgUICwADAAAAAA==.Neoshield:BAAANQADCgcIBwABNQAECgUICwADAAAAAA==.Nephran:BAAANQADCgEIAQAAAA==.Nephylxm:BAAANQADCggICAAAAA==.Nerdibird:BAAANQADCgcIEQAAAA==.Nerek:BAAANQAECgUIDQAAAA==.Nesthraxa:BAAANQAECgIIBAAAAA==.',
Ni='Nialen:BAAANQADCgIIAgAAAA==.Nialiaa:BAAANQADCgcIEgAAAA==.Nightvader:BAAANQAECggIBwABNQAECggIDAADAAAAAA==.Nikomach:BAAANQADCgUICAAAAA==.Nirwë:BAAANQADCggIFwAAAA==.Niviene:BAEANQADCggIFwABNQAECgIIAgADAAAAAA==.',
No='Nokolutrearn:BAAANQADCgQIBAAAAA==.Noodlebender:BAAANQAECgYICgAAAA==.Noopsnoop:BAAANQAECgUICQAAAA==.Noopy:BAAANQAECgQICAAAAA==.Noriannera:BAAANQAECgEIAQAAAA==.Nowhackingu:BAAANQADCgYIBgAAAA==.',
Nu='Nuggets:BAAANQADCgQIBAAAAA==.Nulight:BAAANQAECgUIDAAAAA==.Nutrients:BAAANQADCgIIAgAAAA==.',
Ny='Nyteshyft:BAAANQADCgQIAQAAAA==.Nyvrix:BAAANQADCgQICgAAAA==.Nyxnala:BAAANQADCgQIBgAAAA==.',
Oa='Oakenak:BAAANQADCgYIDQAAAA==.',
Oc='Octane:BAAANQAECgEIAQABNQAECgYICQADAAAAAA==.',
Od='Odiwen:BAAANQADCgUIBQAAAA==.Odyssa:BAAANQADCggIGQABNQAFFAUIBgAPAMUXAA==.',
Oh='Ohdan:BAAANQADCgUIBQABNQAECgYICwADAAAAAA==.',
Ol='Olfdu:BAAANQADCgUIBQAAAA==.',
Om='Omegasoaker:BAAANQADCgcIBwAAAA==.',
Oo='Oolong:BAAANQADCgUIBQAAAA==.',
Or='Orindal:BAAANQAECgQIBgAAAA==.',
Ou='Ouluo:BAAANQADCggIDQAAAA==.',
Pa='Palared:BAABNQAECoEZAAIEAAkJpBOPJwB4AgAEAAkJpBOPJwB4AgAAAA==.Palladiyne:BAAANQADCgYIFgAAAA==.Palliearth:BAAANQAECgMIAwAAAA==.Pandö:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.Papacooldwn:BAAANQADCgUIBQAAAA==.Parict:BAAANQAECggIAgAAAA==.Pascaal:BAAANQAECgEIAgAAAA==.',
Pe='Pecansandies:BAAANQADCggIDQAAAA==.Pennÿ:BAAANQADCggIGQAAAA==.Penthe:BAAANQADCgYIDgAAAA==.Penumbruh:BAAANQAECgcIEQAAAA==.Peruvianvil:BAAANQADCgQIBAAAAA==.',
Pf='Pfunk:BAAANQAECgUIBgABNQAECggIGAASAIsVAA==.',
Ph='Pheebegeobe:BAAANQAECgQICAAAAA==.Phyzal:BAAANQAECgIIAgAAAA==.Phåze:BAAANQADCgIIAgAAAA==.',
Pi='Piddlebom:BAAANQAECgQIBgAAAA==.Pirani:BAAANQADCgQIBwAAAA==.Pitts:BAAANQAECgIIAgAAAA==.',
Pl='Platanito:BAAANQADCgYICAAAAA==.Plethura:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.',
Po='Ponyytail:BAAANQAECgEIAQAAAA==.Poodis:BAAANQAECgQIBgABNQADCgUIBQADAAAAAA==.Poshanka:BAAANQAECgIIAgAAAA==.Poulsao:BAAANQADCgcIFwAAAA==.Powgun:BAAANQADCgQICAAAAA==.',
Pr='Promyvïon:BAAANQADCgYIDAABNQAECgQIBwADAAAAAA==.',
Pu='Pulpgorillaz:BAAANQADCgYIBwAAAA==.Punchtruly:BAAANQAECgQIBgAAAA==.',
Qd='Qdb:BAAANQAECgQIBAAAAA==.',
Qi='Qiaosheng:BAAANQADCgcICQAAAA==.',
Ra='Rabbitunter:BAAANQADCgQIBQAAAA==.Rachejagerin:BAAANQADCgQIBAABNQAECgYIDwADAAAAAA==.Rackharrow:BAAANQADCgQIBAAAAA==.Raedammil:BAAANQAECgUICQAAAA==.Raellé:BAAANQAECgIIAgAAAA==.Raiddaddy:BAAANQADCgYIEgABNQADCggIGwADAAAAAA==.Rainmow:BAAANQAECgQIBAAAAA==.Rainnir:BAAANQADCgcIBwAAAA==.Ramlethal:BAAANQADCgEIAQAAAA==.Rapháèl:BAAANQAECgMICAAAAA==.Rapticon:BAAANQADCgIIAgAAAA==.Rashelyn:BAAANQAECgUIDAAAAA==.Rathgart:BAAANQAECggIBgAAAA==.Ravnsong:BAAANQAECgEIAQAAAA==.Ravun:BAAANQABCgIIAgAAAA==.Raylea:BAAANQADCggIFAAAAA==.Raynevanity:BAAANQADCgIIAgAAAA==.Rayrim:BAAANQADCgIIAgAAAA==.Razenothen:BAAANQADCggICwAAAA==.',
Re='Reagan:BAAANQADCgMIAwABNQAECgIIAgADAAAAAA==.Recktyou:BAAANQADCgYIBgAAAA==.Reco:BAAANQAECgYIDQAAAA==.Rednazm:BAAANQAECgUIBgAAAA==.Redsdh:BAAANQADCgEIAQABNQAECgkJGQAEAKQTAA==.Redsmasher:BAAANQADCgEIAQAAAA==.Reindridaen:BAAANQADCgYIBgABNQAECggIFgAMAPsSAA==.Relapse:BAAANQADCggICAAAAA==.Rem:BAAANQADCgUIBQAAAA==.Remimousy:BAAANQADCgQIBgAAAA==.Revdrax:BAAANQAECgYICQAAAA==.Revosham:BAAANQAECgMIBQAAAA==.Rexxywaffles:BAAANQAECgEIAQAAAA==.',
Rh='Rhaanall:BAAANQADCggIDgAAAA==.Rhaizu:BAAANQAECgEIAQAAAA==.',
Ri='Riedreni:BAAANQAECgQIBQAAAA==.',
Ro='Rockytotems:BAAANQAECgQIBgAAAA==.Rogued:BAABNQAECoEZAAMJAAkJpR5tCAC7AgAJAAgJ4B5tCAC7AgAIAAMJkhfpMADeAAAAAA==.Roldius:BAAANQADCgYIDAAAAA==.Rorochaman:BAAANQADCgcIBwABNQAECgUICwADAAAAAA==.Rorodruida:BAAANQAECgUICwAAAA==.Rorrk:BAAANQADCgYIDQAAAA==.Rosedemon:BAAANQABCgIIAgAAAA==.Rothanos:BAAANQAECgIIBAAAAA==.Rouland:BAAANQAECgQIBQAAAA==.Rowdawg:BAAANQAECgEIAQAAAA==.',
Ru='Rumplegold:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.',
Ry='Rykthar:BAAANQADCgcIDAAAAA==.Ryvennah:BAAANQADCgYIBgAAAA==.',
['Rê']='Rêhm:BAAANQAECgEIAQAAAA==.',
Sa='Sabelyn:BAAANQADCgcICQAAAA==.Sacrofficial:BAAANQAECgMIAwAAAA==.Saioxenth:BAAANQAECgYIDQAAAA==.Sakmage:BAAANQAECgQIDAAAAA==.Salchypapa:BAAANQAECgcIBwAAAA==.Sallykin:BAAANQAECgIIAgAAAA==.Salsbm:BAAANQADCggICAAAAA==.Samais:BAAANQADCgYIBgAAAA==.Samalia:BAABNQAECoEVAAIfAAgJRh7tBgCkAgAfAAgJRh7tBgCkAgABNQAFFAYICgAWAOYhAA==.Samon:BAAANQAECgMIAwAAAA==.Sanches:BAAANQAECgUIBgABNQADCgYIBgADAAAAAA==.Sanctius:BAAANQADCggICAAAAA==.Sandycheekz:BAAANQADCgIIAgAAAA==.Sanguineclaw:BAAANQAECgIIAgAAAA==.Sanindon:BAAANQADCgcICgAAAA==.Saranii:BAEANQAECgEIAQAAAA==.Sariì:BAAANQADCgcIDgAAAA==.Sathlinda:BAAANQADCgIIAwAAAA==.Sauloth:BAAANQADCgMIAwAAAA==.',
Sc='Scaled:BAAANQADCgEIAQAAAA==.Scarletpain:BAAANQADCgEIAQABNQAECgQIBwADAAAAAA==.Scarletpaws:BAAANQADCgUIBQABNQAECgQIBwADAAAAAA==.Scarletrains:BAAANQADCgQIBAABNQAECgQIBwADAAAAAA==.Scarlettanuk:BAAANQAECgQIBwAAAA==.Scarlitjoham:BAAANQAECgYIBgAAAA==.Scragglum:BAAANQADCgYICgAAAA==.Scromo:BAAANQADCggIGgAAAA==.Scv:BAABNQAECoEVAAIUAAkJ4yYIAAAUBAAUAAkJ4yYIAAAUBAAAAA==.',
Se='Senjougahara:BAAANQADCgYIFgAAAA==.Sento:BAAANQADCgYIBgAAAA==.Serejh:BAAANQAECgQICQAAAA==.Serejhs:BAAANQADCgUIBQAAAA==.',
Sh='Shadowbrnger:BAAANQAECgUICQAAAA==.Shadowsnipes:BAAANQAECgEIAgABNQAECggIDQADAAAAAA==.Shadowsongg:BAAANQAECggIDQAAAA==.Shaggyd:BAAANQABCgIIAwAAAA==.Shammygaga:BAAANQADCgUICAABNQAECgEIAQADAAAAAA==.Shamspam:BAAANQAECgQIBwAAAA==.Shanatova:BAAANQAECgEIAQAAAA==.Sharinknight:BAAANQAECgQIBwAAAA==.Shauriand:BAAANQAECgEIAQAAAA==.Shawman:BAAANQAECgEIAgABNQADCgYIBgADAAAAAA==.Shayminidru:BAAANQAECggIAQAAAA==.Shehealfu:BAAANQADCggIDgAAAA==.Shigli:BAAANQADCgUIBQABNQAECgYIDgADAAAAAA==.Shishras:BAABNQAECoEdAAMHAAkJHCQ/DQATAwAHAAgJQiU/DQATAwAPAAUJixuHIQCJAQAAAA==.Shnid:BAAANQADCgUIBgAAAA==.Shâdowcâst:BAAANQAECgEIAQAAAA==.',
Si='Siardre:BAAANQADCgYICQAAAA==.Silentbozo:BAAANQADCgMIAwAAAA==.Sillydruid:BAAANQADCgcICgAAAA==.Sillyrat:BAAANQAECgYIDQAAAA==.Sincados:BAAANQABCgQIBAAAAA==.Sionfaust:BAAANQADCgYIDQAAAA==.Sipper:BAAANQAECgUIDQAAAA==.',
Sk='Skandelóus:BAAANQAECgMIAwAAAA==.',
Sl='Slicky:BAAANQADCgQIBgABNQAECgcIEAADAAAAAA==.',
Sm='Smashingface:BAAANQAECgIIAwAAAA==.',
So='Sodypop:BAAANQADCggIDQABNQAECgQICAADAAAAAA==.Sokra:BAAANQADCgYICAAAAA==.Soldmyeggs:BAAANQADCggIFwAAAA==.Somonia:BAAANQAECgEIAQABNQAFFAYICgAWAOYhAA==.Sordamac:BAAANQAECgcIBQAAAA==.',
Sp='Spicymustard:BAAANQABCgIIAgAAAA==.Spidda:BAAANQAECgEIAgAAAA==.',
St='Stasismom:BAAANQAECgUICQABNQAECgYIBgADAAAAAA==.Stealthspike:BAAANQADCgcIBQAAAA==.Stellalemon:BAAANQAECgQIBAAAAA==.Stevvee:BAAANQAECgUIBQAAAA==.Stompalittle:BAAANQADCggIEAABNQAECggIFAAIAA0hAA==.Stonesboyw:BAAANQAECgMIBAAAAA==.Stormtox:BAAANQAECgEIAQAAAA==.Stormydniels:BAABNQAECoEhAAIGAAkJkSSmAgDCAwAGAAkJkSSmAgDCAwAAAA==.Strahz:BAAANQAECgcIEAAAAA==.Stunurazz:BAAANQAECgMIBAAAAA==.Sturtur:BAAANQADCgYICQAAAA==.Stârbow:BAAANQADCgMIAwAAAA==.',
Su='Suddenstorm:BAAANQAECggIEAAAAA==.Sudormrf:BAAANQADCggICgABNQAECgQIBQADAAAAAA==.Sullywaffles:BAAANQAECgEIAQAAAA==.Sunryze:BAAANQADCgcIDQAAAA==.Sunspotted:BAAANQADCgIIAgAAAA==.Suralias:BAABNQAECoEXAAIaAAkJiBIVTwBfAgAaAAkJiBIVTwBfAgAAAA==.Surashaman:BAAANQAECggIDwABNQAECgkJFwAaAIgSAA==.',
Sw='Swankkie:BAAANQAECgQIBAABNQAECgkJGQAHAOEiAA==.Sweetdev:BAAANQADCgMIAwAAAA==.',
Sy='Syraen:BAAANQADCggIEgAAAA==.',
Sz='Szylph:BAAANQADCgYIDAAAAA==.',
['Sä']='Säel:BAAANQAECgQIBAAAAA==.',
['Sç']='Sçàr:BAAANQADCggICgAAAA==.',
Ta='Taebaek:BAAANQADCgUIBQAAAA==.Talahnoa:BAAANQADCgcIBwAAAA==.Talantheron:BAAANQAECgcIEAABNQAECgkJHQAHABwkAA==.Talhearn:BAAANQAECgIIAgAAAA==.Taminek:BAAANQAECgQIBAABNQAECgkJHQAHABwkAA==.Tanarcarissa:BAAANQADCggIEgAAAA==.Tankboy:BAAANQAECgUICgAAAA==.Tankiemctank:BAEANQADCgYICQAAAA==.Taqui:BAAANQADCggICAAAAA==.Tathea:BAAANQAECgUICQAAAA==.Tatsuya:BAAANQAECgEIAQAAAA==.Tayded:BAAANQADCgEIAQAAAA==.Tayzar:BAAANQADCgEIAQAAAA==.',
Te='Tehrah:BAAANQADCgIIAgAAAA==.Telisaria:BAAANQADCgcIBwAAAA==.Tellanll:BAAANQABCgUIBQAAAA==.Telocurdle:BAAANQAECgEIAQAAAA==.Temnotal:BAAANQADCgcICwAAAA==.Tendag:BAAANQAECgQIBAABNQAECgkJHQAFAG0cAA==.Teorem:BAAANQAECgQIBwAAAA==.Tevulamezruj:BAAANQADCgUIBQAAAA==.',
Th='Thalyon:BAAANQADCgQIBAAAAA==.Thanaphos:BAAANQADCgcIFAAAAA==.Thatguyoquai:BAAANQADCgMIAwAAAA==.Thconsequenc:BAAANQADCgYIBgAAAA==.Theadore:BAAANQADCgEIAQAAAA==.Thecbt:BAAANQADCgQIBAAAAA==.Thellara:BAAANQADCgYIBgAAAA==.Thelmor:BAAANQADCgEIAQAAAA==.Theprincer:BAAANQAECgIIAgAAAA==.Therrai:BAAANQADCgYIFwAAAA==.Thirtyfloor:BAAANQADCgYIBgAAAA==.Thisguyelroy:BAAANQAECgEIAQAAAA==.Thlsbro:BAAANQAECgIIAgAAAA==.Thoromyr:BAAANQAECgMIBgAAAA==.Thuato:BAAANQADCgYICgAAAA==.Thundercats:BAAANQADCgcIEQAAAA==.Thúndrstruck:BAAANQAECgYIDAABNQAFFAEIAQADAAAAAA==.',
Ti='Tiffërny:BAAANQADCgIIAgAAAA==.Timinator:BAAANQADCgYIBwABNQAECggIFQAWAAoaAA==.Tinylemon:BAAANQADCggICAAAAA==.Tivaan:BAAANQAECgIIAwAAAA==.Tizmprince:BAAANQADCgEIAQAAAA==.',
To='Torq:BAABNQAECoEZAAIdAAkJViK1BgBLAwAdAAkJViK1BgBLAwABNQAFFAEIAQADAAAAAA==.Totemful:BAAANQAECggICAABNQAFFAUICAARAOsaAA==.',
Tr='Traewynn:BAAANQADCggIFgAAAA==.Transkitty:BAAANQADCgYIBgAAAA==.Trexy:BAAANQADCgcICwAAAA==.Triredgy:BAAANQAECgcIEwAAAA==.',
Ts='Tsilhqot:BAAANQADCgMIAwAAAA==.',
Tt='Tthatguyy:BAAANQADCgQIBQAAAA==.',
Tu='Tummyblaster:BAAANQADCgEIAQABNQADCggIFgADAAAAAA==.Tummysnake:BAAANQADCgQIBgAAAA==.Turalya:BAAANQAECgIIAwAAAA==.Tuychm:BAAANQAECgMIBAAAAA==.',
Tw='Twareded:BAAANQADCgIIAgAAAA==.Twocansam:BAAANQADCgYIBgAAAA==.Twohandsome:BAABNQAFFIEKAAIWAAYJ5iFIAAB8AgAWAAYJ5iFIAAB8AgAAAA==.Twøføx:BAAANQAECgUICwAAAA==.',
Ty='Tyinaa:BAAANQAECgIIAwAAAA==.Tylenoldk:BAAANQADCgMIAwABNQAECgIIAwADAAAAAA==.Typherin:BAAANQAECgYICwAAAA==.Tyrallas:BAAANQAECgEIAQAAAA==.Tyrven:BAAANQADCgYIBgAAAA==.',
Ub='Ubba:BAAANQAECgYIDgAAAA==.',
Ul='Ulannya:BAAANQAECgEIAQAAAA==.Ulddon:BAAANQADCgYIBgAAAA==.Ullria:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.',
Un='Undercovrmoo:BAAANQAECgQIBwAAAA==.',
Ur='Urdragon:BAAANQAECgUICgAAAA==.Urving:BAAANQAECgUIBQAAAA==.',
Uw='Uwugnar:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.',
Va='Vaeltheris:BAAANQADCgYICQAAAA==.Vantelantien:BAAANQABCgcICQAAAA==.Vargasbarbas:BAAANQADCgMIAwAAAA==.Varjaz:BAAANQADCggICQABNQAECgcIEAADAAAAAA==.',
Ve='Vecxlolz:BAAANQABCgUIBQAAAA==.Vecxous:BAAANQABCgYICQAAAA==.Veladar:BAAANQAECgIIAgAAAA==.Velaradraena:BAAANQADCgMIAwAAAA==.Velhunter:BAABNQAECoEZAAIPAAkJYx9ZBgAxAwAPAAkJYx9ZBgAxAwAAAA==.Velush:BAABNQAECoEiAAIXAAkJtCUFAQDmAwAXAAkJtCUFAQDmAwAAAA==.Veressta:BAAANQAECgQIBgAAAA==.Verkk:BAAANQADCgQIBQAAAA==.',
Vi='Vienarissa:BAAANQADCgUICQAAAA==.Vifekoygua:BAAANQAECgQIBAAAAA==.Viralson:BAAANQAECgEIAgAAAA==.Virulnekron:BAABNQAECoEZAAIXAAgJDBxCFACrAgAXAAgJDBxCFACrAgAAAA==.Viserysll:BAAANQAECgEIAQABNQAECgMIBAADAAAAAA==.Vitaemors:BAAANQADCgQIBAAAAA==.Vitaminbee:BAAANQAECgcIEwAAAA==.',
Vl='Vlnar:BAABNQAECoEXAAIQAAkJwSFZBgA8AwAQAAkJwSFZBgA8AwAAAA==.',
Vo='Voeros:BAAANQADCgEIAQAAAA==.Voidplay:BAAANQAECgEIAQAAAA==.Voyagerebaca:BAAANQADCgYIBwAAAA==.Voyagesoul:BAAANQADCgEIAgAAAA==.',
['Vê']='Vêspera:BAAANQADCgIIAgAAAA==.',
Wa='Wadeboggs:BAAANQAECgYIBwABNQAECgkJIQAGAJEkAA==.Warrod:BAAANQAECgQIBgAAAA==.Washabilly:BAAANQAECgcIEQAAAA==.',
We='Welbiner:BAAANQAECgcIBwAAAA==.',
Wh='Whackem:BAAANQADCgYICwAAAA==.Whookies:BAAANQAECgYIBgAAAA==.Whö:BAAANQADCgIIAgABNQADCgUIBQADAAAAAA==.',
Wi='Wileyy:BAAANQADCgEIAQAAAA==.Windbinder:BAAANQAECgQIBQAAAA==.Wizfla:BAABNQAECoEcAAMBAAkJCxgTLwAdAgABAAcJ8hcTLwAdAgACAAIJYBglPQCUAAAAAA==.',
Wo='Wolfluna:BAAANQADCgcIGAAAAA==.Woljin:BAAANQAECgIIAgAAAA==.Woobzk:BAAANQADCgQICwAAAA==.Woolala:BAAANQADCgUICQABNQAECgcIEwADAAAAAA==.Woosiv:BAAANQAECgcIBwAAAA==.Woouid:BAAANQADCgYIBgABNQAECgcIBwADAAAAAA==.Woovoke:BAAANQAECgYIBwABNQAECgcIBwADAAAAAA==.Workmoose:BAAANQAECgQIBAAAAA==.Wouldisure:BAAANQADCggIFAAAAA==.',
Ww='Wwiilloow:BAAANQABCgQICAAAAA==.',
Xa='Xanelos:BAAANQADCgYIDgAAAA==.',
Xo='Xoilbiss:BAAANQADCgYICQAAAA==.',
Ya='Yakia:BAAANQAECggICAABNQAECgkJJAASAFolAA==.Yanika:BAAANQAECgEIAQAAAA==.Yarellezi:BAAANQABCgQIDQAAAA==.',
Ye='Yehwe:BAAANQADCggIEwAAAA==.',
Yi='Yiwan:BAAANQAECgcIDwAAAA==.',
Yu='Yuismi:BAAANQAECgIIAgAAAA==.',
Za='Zappd:BAAANQAECgYIBgAAAA==.Zartoga:BAAANQADCgEIAQAAAA==.Zasman:BAAANQAECgQIBwAAAA==.Zayabella:BAAANQAECgEIAQAAAA==.',
Ze='Zedrick:BAAANQADCgMIBAAAAA==.Zenchantress:BAAANQADCgEIAQAAAA==.Zephyrea:BAABNQAECoEWAAIaAAkJcBfaPQCaAgAaAAkJcBfaPQCaAgAAAA==.Zerimah:BAAANQAECgMIAwAAAA==.Zerx:BAAANQADCgYIBgAAAA==.Zetrathion:BAAANQAECgUIEQAAAA==.',
Zh='Zhakloskar:BAAANQADCgYIBgAAAA==.',
Zi='Ziaet:BAAANQADCgMIBAAAAA==.Zingerdk:BAEANQAECgMIAwABNQAECgQIBAADAAAAAA==.Zinng:BAAANQAECgcIEQAAAA==.',
Zo='Zoalara:BAAANQAECgYICwAAAA==.Zodiakmage:BAAANQAECgIIAgABNQAFFAIIAgADAAAAAA==.Zoroph:BAAANQADCgQIBAAAAA==.',
Zs='Zsixfiddy:BAAANQADCgUIBQAAAA==.',
Zz='Zzaq:BAAANQAECgQICAABNQAECgkJHQAGAFMeAA==.',
['Zá']='Záhr:BAAANQADCgMIBQAAAA==.',
['Zí']='Zíngerdh:BAEANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
['Æë']='Æëgwynn:BAAANQADCgUIBQAAAA==.',
['Éo']='Éowyn:BAAANQADCgUIDwAAAA==.',
['ßr']='ßrutal:BAAANQAECgcIEQAAAQ==.',
['ßt']='ßteel:BAAANQADCggIFQAAAA==.',
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
