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

local lookup = {'Warlock-Demonology','Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Paladin-Protection','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','DemonHunter-Devourer','Paladin-Retribution','Druid-Guardian','Mage-Fire','Mage-Frost','Druid-Feral','Warrior-Fury','Warrior-Arms','Unknown-Unknown','Druid-Restoration','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warlock-Destruction','Shaman-Enhancement','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acidsword:BAACNQAFFH8FAAIBAAIKEhEsKgCJAAABAAIKEhEsKgCJAAA1AAQKfzIAAgEACQptHpEgAJECAAEACQptHpEgAJECAAE1AAUUBwgOAAIAShkA.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQAECgUIBQABNQAFFAQICwADALofAA==.Adrua:BAAANQAECgYIBgAAAA==.Adym:BAABNQAECn8kAAIEAAoK7BM7fQATAgAEAAoK7BM7fQATAgAAAA==.',
Ag='Agave:BAABNQAECn9TAAIFAAoK8RWXLQBtAgAFAAoK8RWXLQBtAgAAAA==.',
Ai='Aiyah:BAAANQAECgQICAAAAA==.',
Al='Altarboi:BAABNQAECn8rAAMGAAkKfSFJEgBHAwAGAAkKfSFJEgBHAwAHAAEKKgXZeQA0AAAAAA==.Alüçard:BAABNQAECn8wAAIIAAcK2w6BuwAvAQAIAAcK2w6BuwAvAQAAAA==.',
Am='Amoraniel:BAABNQAECn8rAAIIAAoKgxrwbwCeAgAIAAoKgxrwbwCeAgAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAABNQAECn8eAAMJAAkKnhuLIgByAgAJAAkKMBuLIgByAgAKAAQKsBjjjQD9AAAAAA==.Andresra:BAABNQAECn8wAAIIAAkKuiBrZwCvAgAIAAkKuiBrZwCvAgABNQAECgkJHgAJAJ4bAA==.Anie:BAAANQADCgQIBAAAAA==.Annaluna:BAAANQAECgUIBgAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAABNQAECn8hAAMGAAoK0xZJOgBSAgAGAAoKvxVJOgBSAgALAAQKGwqKFwC5AAAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
As='Asrael:BAAANQAECggIDgABNQAECgoKOAAMAFsaAA==.Asterin:BAAANQADCggIDgAAAA==.',
Au='Audersi:BAAANQADCgQIBQAAAA==.Augtism:BAAANQAECgIIAgABNQAECgoKHAADANgbAA==.Aunumator:BAAANQADCgYIBgAAAA==.',
Av='Avâtre:BAABNQAECn8lAAINAAoKURZ6WwAQAgANAAoKURZ6WwAQAgAAAA==.',
Az='Azlea:BAAANQAECgcIBgAAAA==.',
Ba='Baguette:BAAANQAECgYIDQAAAA==.Bajingobomb:BAABNQAECn9CAAMOAAoKACHyDwCCAgAOAAoKySDyDwCCAgAPAAYKER19SwDJAQAAAA==.Bajisil:BAAANQAECgUIBwABNQAECgoKQgAOAAAhAA==.Bakblood:BAAANQABCgYICgAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEIAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgYICgAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAABNQAECn8VAAIQAAYKJRkvKQBQAQAQAAYKJRkvKQBQAQAAAA==.',
Be='Be:BAABNQAECn8zAAIGAAgKMxsmPwA+AgAGAAgKMxsmPwA+AgAAAA==.Beckyoncé:BAABNQAECn8/AAIRAAoKwSKJBACMAwARAAoKwSKJBACMAwAAAA==.Bedris:BAABNQAECn8wAAQMAAoKJBOLIwDFAQAMAAcKFReLIwDFAQASAAoKOQw+vABaAQADAAEKXQK/NwEfAAAAAA==.Beerticus:BAABNQAECn84AAIQAAgKHxxqGQDkAQAQAAgKHxxqGQDkAQAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECn8cAAITAAkKthkAEABgAgATAAkKthkAEABgAgAAAA==.Binggles:BAACNQAFFH80AAQIAAkKMCEIAgDcAgAIAAkKqx8IAgDcAgAUAAQK4Rd+AADuAAAVAAIKiyXlAwDaAAA1AAQKfzUAAxQACgpNJsoAAN0CAAgACgqdJdIgAFcDABQACAr9JMoAAN0CAAAA.',
Bl='Blacksheep:BAAANQAECgMIAgAAAA==.Blazze:BAAANQAECgUICgABNQAECgoKLAAEAEMfAA==.Blôôðhôôf:BAAANQADCgQIBAABNQAECgoKKwAWAIERAA==.',
Bo='Boaj:BAABNQAECn8bAAMXAAkKqRE3EgBVAQAYAAgKCxDuawC9AQAXAAcKUg83EgBVAQAAAA==.Bokinar:BAAANQAECggICgAAAA==.Bomboclaat:BAAANQAECgQIDwABNQAECgoKMwAQALokAA==.Boolay:BAABNQAECn8kAAMMAAoKGR1hHwDqAQAMAAcKNx1hHwDqAQASAAcKPxI75AAWAQABNQABCgUIBQAZAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQAECgYICgAAAA==.Bootyshotz:BAAANQAECgEIAQABNQAECgoKNQAaAE0UAA==.Boozing:BAAANQADCggICgABNQAECgoKNQAEAGkiAA==.Bopstds:BAAANQAECgUICAAAAA==.Bosmina:BAABNQAECn9KAAIGAAoKUhz+NQCQAgAGAAoKUhz+NQCQAgAAAA==.',
Br='Braei:BAABNQAECn9BAAIDAAoKihA3WAC1AQADAAoKihA3WAC1AQAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Breelynn:BAAANQADCggICAAAAA==.Brenhunt:BAABNQAECn8jAAIEAAoKQhsYKgCYAgAEAAoKQhsYKgCYAgAAAA==.Brenmonk:BAABNQAECn8fAAIQAAcK8gofNgBkAQAQAAcK8gofNgBkAQAAAA==.Brenpriest:BAAANQADCggIDgAAAA==.Brenshammy:BAAANQADCgcIDAAAAA==.Bruenor:BAAANQAECgMIAwAAAA==.Bruucey:BAABNQAECn8dAAIIAAoKcAxtcQDOAQAIAAoKcAxtcQDOAQAAAA==.',
Bu='Bubblebaddie:BAAANQAECgQIBQAAAA==.Bubblicous:BAAANQAECgcICgAAAA==.Bugenhagen:BAABNQAECn9IAAMFAAoKrCRfBwCHAwAFAAoKrCRfBwCHAwANAAMKSxO3nQDMAAAAAA==.Butchers:BAAANQAECgUICgAAAA==.Buttpaladin:BAABNQAECn8nAAISAAgK2BaNkgD/AQASAAgK2BaNkgD/AQAAAA==.',
Ca='Caliden:BAAANQABCgYICwAAAA==.Capelady:BAAANQADCgMIAwAAAA==.Cardib:BAACNQAFFH8SAAQOAAgKPRwsBwCoAQAOAAUKeSIsBwCoAQAbAAMKmhAFDwDqAAAPAAEK0SBXIgBfAAA1AAQKf0oAAw4ACgoiJvoGAI4DAA4ACgqxJfoGAI4DABsACAoUJd4MAPECAAAA.Cavos:BAABNQAECn8dAAIRAAcKgRuLJwAIAgARAAcKgRuLJwAIAgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAABNQAECn9BAAIPAAoK4hiPGwAiAgAPAAoK4hiPGwAiAgAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Cheesen:BAAANQAECgQICAAAAA==.Chiri:BAECNQAFFH8QAAQcAAcKSgRLDgD/AAAcAAYKyQFLDgD/AAAdAAQKdwTzAwC6AAAeAAEKAAAREQAAAAA1AAQKfysABB0ACgouEwUUAA4CAB0ACgqxEQUUAA4CAB4ABArJDm0RAMgAABwAAwoSAyRFAHkAAAAA.Chvngus:BAABNQAECn82AAMSAAoKHB+XLQARAwASAAoKEh+XLQARAwAMAAYK4xiSIwBRAQAAAA==.',
Ci='Citizencain:BAABNQAECn8UAAIIAAUKixs9CAF/AQAIAAUKixs9CAF/AQAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMIBwAAAA==.',
Co='Cocheeze:BAAANQAECgcIDAABNQAECgoKJAAOANAXAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEBNQAECn8YAAIfAAoKUA/cSgC6AQAfAAoKUA/cSgC6AQAAAA==.Conmammoth:BAABNQAECn8hAAISAAgKwSD5WgAfAgASAAgKwSD5WgAfAgAAAA==.Conquest:BAAANQAECgQIBAAAAA==.Coohwhip:BAAANQAECgIIAgAAAA==.Cornorgan:BAAANQAECggIEwAAAA==.Corèl:BAAANQADCgUIBwAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAABNQAECn8rAAIfAAoKXBMMNQBAAgAfAAoKXBMMNQBAAgAAAA==.Cristobal:BAAANQAECgYICgAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.Crykthiria:BAAANQADCgEIAQAAAA==.',
Cu='Curaga:BAAANQAECgMIAwAAAA==.Curnsarn:BAAANQAECgYIDgABNQAECgoKQQAPAOIYAA==.',
Cy='Cydea:BAAANQAECgQICwAAAA==.',
Da='Dagidan:BAABNQAECn9GAAIgAAoKrRF7DAD/AQAgAAoKrRF7DAD/AQAAAA==.Darktide:BAAANQAECggIEAAAAA==.Dashawmon:BAAANQADCggICAABNQADCgYICQAZAAAAAA==.Dashel:BAAANQAECggIDgABNQAECgoKQwAHAKAUAA==.',
De='Dead:BAAANQADCggICAAAAA==.Deathtoxi:BAAANQAECgIIAQAAAA==.Degey:BAAANQAECggICAAAAA==.Demonsoul:BAAANQADCgQIBAAAAA==.Demontotems:BAAANQAECggICAAAAA==.Demotoxi:BAACNQAFFH8GAAIRAAQK2w55CgC3AAARAAQK2w55CgC3AAA1AAQKf0EABBEACgorICcLAKECABEACgorICcLAKECACEABApQGWRhAPUAACAAAgrNCqcsAFEAAAAA.Deriso:BAABNQAECn8fAAMEAAoKjiGILgDiAgAEAAoKeSCILgDiAgACAAMKBhkZYwCdAAAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAZAAAAAA==.Destrozinth:BAABNQAECn8UAAIeAAoKgA3tEAAoAQAeAAoKgA3tEAAoAQAAAA==.Dethorok:BAABNQAECn9JAAIEAAoKFiZ0BQC3AwAEAAoKFiZ0BQC3AwAAAA==.Deuce:BAAANQABCgIIAQAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgoKSAAFAKwkAA==.Dib:BAAANQAECgcIEgAAAA==.Digey:BAABNQAECn8yAAMiAAoKAyPBBAA1AwAiAAoKAyPBBAA1AwAYAAMKoQwf/wB2AAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAABNQAECn8uAAIjAAoKlgd3DAD5AAAjAAoKlgd3DAD5AAAAAA==.',
Do='Dontlookatme:BAAANQABCgUIBQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottymcdots:BAAANQADCgMIAwAAAA==.Dottër:BAAANQADCggIEwABNQAECgEIAQAZAAAAAA==.',
Dr='Drakbek:BAABNQAECn8mAAITAAkKABvFEgAOAgATAAkKABvFEgAOAgAAAA==.Dreadshot:BAAANQADCgYIBwAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dremaster:BAAANQADCggIDgAAAA==.Dronebot:BAABNQAECn9uAAMHAAoK2BzMDgAEAwAHAAoK2BzMDgAEAwAGAAEK8wvi8QA5AAAAAA==.Drucifer:BAAANQADCggIFwAAAA==.',
Du='Dud:BAAANQAECgYICAABNQAECgkJGAAFAHodAA==.Dumbrouge:BAAANQAECgIIAgABNQAECgoKOAAMAFsaAA==.Durros:BAABNQAECn8sAAIFAAoKMxlyNQBFAgAFAAoKMxlyNQBFAgAAAA==.Durto:BAAANQABCgEIAQAAAA==.Dustyshotz:BAAANQAECgYICAAAAA==.',
Dy='Dyhanna:BAAANQAECggIBwAAAA==.',
Eb='Eboger:BAAANQAECgMIAgAAAA==.',
Eg='Egam:BAAANQAECgUIBQAAAA==.',
El='Elunelphie:BAABNQAECn8VAAIEAAkKWAg/jQCcAQAEAAkKWAg/jQCcAQAAAA==.',
Em='Embody:BAABNQAECn8jAAIfAAoK8AoeVwB6AQAfAAoK8AoeVwB6AQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECn8oAAISAAoKixxIWQCLAgASAAoKixxIWQCLAgAAAA==.',
Er='Erasmas:BAACNQAFFH8LAAIDAAQKuh+dDQBuAQADAAQKuh+dDQBuAQA1AAQKf1oABAMACgrsJGYGAJkDAAMACgrsJGYGAJkDABIACQpwHw1FAFsCAAwAAgoVIE1BAKMAAAAA.Erasmos:BAAANQAECgYIBgABNQAFFAQICwADALofAA==.Erzascarlét:BAABNQAECn9GAAIMAAoKux1CCwDlAgAMAAoKux1CCwDlAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAABNQAECn8kAAIOAAoK0Be5FQBBAgAOAAoK0Be5FQBBAgAAAA==.Eviltotems:BAABNQAECn8jAAINAAoKyRYTLwAdAgANAAoKyRYTLwAdAgABNQAECgoKJAAOANAXAA==.Eviscration:BAAANQADCgIIAgABNQADCggIDgAZAAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Ez='Ezyy:BAAANQAECgQICAAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECn9KAAQNAAoKVB9bGwAlAwANAAoKVB9bGwAlAwAFAAYKxA2tiwASAQAkAAMKRwnIKQCyAAAAAA==.Fantasma:BAAANQAECgEIAQAAAA==.',
Fe='Fear:BAAANQAECgIIBAAAAA==.',
Fi='Findal:BAAANQAECgUIBAABNQABCgUIBwAZAAAAAA==.Fistymoo:BAEANQAECgIIAgABNQAFFAcIEAAcAEoEAA==.Fivemagics:BAABNQAECn82AAMBAAoK4BYeZAAtAgABAAkKEhceZAAtAgAjAAIKERUTIQBtAAAAAA==.',
Fl='Flayvour:BAAANQABCgQIBAABNQAECgoKNAAlADgdAA==.Fleaboy:BAABNQAECn8XAAMmAAgKHhG2CQDqAQAmAAgKHhG2CQDqAQAKAAEKSwShUQA6AAAAAA==.Flist:BAABNQAECn8zAAIQAAoKuiSKAwCeAwAQAAoKuiSKAwCeAwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAABNQAECn8mAAMIAAoKNRUJkACGAQAIAAoKiBIJkACGAQAVAAIKFh27KwCdAAAAAA==.Foote:BAAANQAECggIBwABNQAFFAYIEwAcAGUGAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAABNQAECn8kAAIHAAoKIhTKJwDsAQAHAAoKIhTKJwDsAQAAAA==.Freesia:BAAANQAECgIIAgAAAA==.Fruitjuice:BAABNQAECn8bAAIjAAgKWA5iCwALAQAjAAgKWA5iCwALAQAAAA==.',
Fu='Furrios:BAAANQADCggIDgAAAA==.',
Fx='Fxce:BAACNQAFFH8QAAIKAAUKxwiyFgDTAAAKAAUKxwiyFgDTAAA1AAQKf2cAAgoACgoNHgkVANICAAoACgoNHgkVANICAAAA.',
['Fâ']='Fâmine:BAABNQAECn8XAAIBAAoK0AsBXgC7AQABAAoK0AsBXgC7AQABNQAECgoKKQAOANMUAA==.',
Ga='Gaothan:BAAANQAECggIDwAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECn82AAIhAAoKPxVHIgD4AQAhAAoKPxVHIgD4AQAAAA==.',
Gl='Glaiven:BAABNQAECn8hAAIRAAkKaRNbKwDnAQARAAkKaRNbKwDnAQAAAA==.Glasscleaner:BAABNQAECn8cAAIDAAoKFSL+CgBwAwADAAoKFSL+CgBwAwABNQAFFAcIGgAcAPccAA==.Glenmorangie:BAABNQAECn8vAAMLAAoKEx+yBAB4AgALAAgKkB2yBAB4AgAHAAgKox/KFwDqAQAAAA==.',
Gn='Gnartusk:BAABNQAECn9FAAIPAAoKiyOgBAA7AwAPAAoKiyOgBAA7AwAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgUICgAZAAAAAA==.',
Gr='Grawlso:BAAANQADCgYIBgAAAA==.Greens:BAABNQAECn9bAAIfAAoKzh9EDADfAgAfAAoKzh9EDADfAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAZAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgMIBQABNQAECgYIEAAZAAAAAA==.Grïma:BAACNQAFFH8GAAMnAAQKLAklBADHAAAnAAMKLAklBADHAAABAAIKWgULPgAAAAA1AAQKfzoAAycACgqQGkgEAJwCACcACgqQGkgEAJwCAAEABApPEojlAIcAAAAA.',
Gs='Gsus:BAAANQADCggICAABNQAECgoKNAAlADgdAA==.',
Gu='Gueritestje:BAABNQAECn9DAAIMAAoKPCHnBwDMAgAMAAoKPCHnBwDMAgAAAA==.Guzzlord:BAABNQAECn8hAAQcAAkKJwibJwB7AQAcAAkKJwibJwB7AQAdAAQKQQZFLQC2AAAeAAQKbQdeGQCnAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAQABNQAECgoKIwAEAKMSAA==.Handsomejack:BAAANQAECgEIAgABNQAECgoKQgAOAAAhAA==.Hanekawa:BAAANQAECggIAQABNQAFFAMICAAEAAIVAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAZAAAAAA==.',
Hb='Hboozing:BAABNQAECn81AAMEAAoKaSJ4EwBRAwAEAAoKaSJ4EwBRAwACAAEKkxI+gwA8AAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Healynn:BAAANQAECgIIAQAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAZAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Himootation:BAAANQADCgQIBAAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitodh:BAAANQAECgUIBQABNQAECgoKNgAbABUlAA==.Hitoshura:BAABNQAECn82AAMbAAoKFSXZBgB2AwAbAAoK6STZBgB2AwAOAAcK+iQjGwDpAgAAAA==.Hittnrunn:BAAANQAECgEIAQAAAA==.',
Ho='Holyginger:BAABNQAECn8VAAMSAAcKIhUjvAClAQASAAYKUBgjvAClAQADAAEKfhRP7wA7AAAAAA==.Holyglizzy:BAABNQAECn8uAAISAAoKUxdjWgAgAgASAAoKUxdjWgAgAgAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.Holytoxi:BAAANQADCgEIAQABNQAFFAQIBgARANsOAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcJEgABNQAFFAcIGgAcAPccAA==.',
Ic='Ichtaca:BAAANQADCgEIAQAAAA==.',
Ik='Ikiryo:BAEANQAECgIIBgAAAA==.',
Im='Imtuggdup:BAABNQAECn80AAMIAAoKiSGxNwAZAwAIAAoKiSGxNwAZAwAVAAMKtxi6KACcAAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Indra:BAAANQAECgEIAQAAAA==.Infidel:BAABNQAECn8wAAIfAAkKeyRcBgCiAwAfAAkKeyRcBgCiAwAAAA==.Invert:BAAANQAFFAEIAQAAAA==.Invincibúll:BAAANQAECgUIBQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgMIBQAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irayne:BAAANQADCgQIBAAAAA==.Irisharcher:BAAANQAECggIEAAAAA==.Irishbeauty:BAAANQAECgUIBQAAAA==.Irishfury:BAAANQADCgcICQAAAA==.Irishman:BAABNQAECn8VAAISAAkKUA9uiAC7AQASAAkKUA9uiAC7AQAAAA==.',
Is='Isengardd:BAAANQAECgEIAQAAAA==.',
It='Itazki:BAABNQAECn9EAAMWAAoKwCN+AgAtAwAWAAoKwCN+AgAtAwAfAAEKHQyikwAmAAAAAA==.',
Ja='Jackpot:BAAANQAECgIIAgAAAA==.Jaft:BAAANQADCgYIEAAAAA==.Jalter:BAACNQAFFH8aAAIcAAcK9xxoBAAyAgAcAAcK9xxoBAAyAgA1AAQKfzsAAhwACgowIxEEAHIDABwACgowIxEEAHIDAAAA.Janha:BAAANQADCggIDwAAAA==.',
Je='Jediknight:BAAANQAECgQIBAAAAA==.Jefe:BAAANQAECgEIAQAAAA==.Jenga:BAAANQAECgcIDAAAAA==.Jergal:BAABNQAECn8fAAIYAAoK5AsangBBAQAYAAoK5AsangBBAQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAACNQAFFH8IAAMSAAQKfgW0HQCrAAASAAMKfgW0HQCrAAADAAIK1QSuIQBuAAA1AAQKf0kAAxIACgobGA18ADICABIACgobGA18ADICAAMACgp8DcJSAMkBAAAA.',
Ji='Ji:BAAANQADCgYIBgAAAA==.Jibbage:BAAANQAECgQIBAABNQAECgkJMAAfAHskAA==.Jinkala:BAAANQABCgYICgAAAA==.Jitzakkal:BAACNQAFFH8aAAMBAAcKXSXMBAAoAgABAAUKaSTMBAAoAgAjAAIKyyb+AgDmAAA1AAQKfyUAAyMACQoMJrcKAEwCAAEABwp7JS46AKUCACMABgpkJLcKAEwCAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECn8uAAMSAAoK4SPNBwC8AwASAAoK4SPNBwC8AwADAAEKFhpS5gBMAAAAAA==.Joshswims:BAABNQAECn9BAAIbAAkKCBwgGgB5AgAbAAkKCBwgGgB5AgAAAA==.',
Js='Js:BAAANQAECgQICgAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgoKTQAIACckAA==.Juleita:BAAANQABCgQIBAAAAA==.Jumbojoe:BAAANQAECgIIAgAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kalgard:BAAANQAECgIIAwABNQAECgoKQAADAGYaAA==.Kapena:BAAANQAECggIDwAAAA==.Kardinal:BAABNQAECn9PAAQBAAoKeSXNBQChAwABAAoKeSXNBQChAwAjAAUKuhyPHwBzAQAnAAMKMR/gGgCmAAAAAA==.Kargan:BAAANQAECgMIAwABNQAECgYIHAASAIwQAA==.Karliee:BAAANQADCggICAABNQAECgIIAgAZAAAAAA==.',
Ke='Keladorn:BAABNQAECn9DAAISAAoKiCFNKwC0AgASAAoKiCFNKwC0AgAAAA==.Kernsarn:BAAANQAECgcICgABNQAECgoKQQAPAOIYAA==.',
Kh='Khanyiso:BAABNQAECn84AAIMAAoKWxpSEAAlAgAMAAoKWxpSEAAlAgAAAA==.Kharak:BAABNQAECn8xAAIIAAoKTR0FQABNAgAIAAoKTR0FQABNAgABNQABCgUIBwAZAAAAAA==.Khârnxoxo:BAAANQAECggIBgAAAA==.',
Ki='Kichi:BAAANQAECgEIAQAAAA==.Kichii:BAAANQAECgYIDgAAAA==.Kiellan:BAAANQADCggIDQAAAA==.Kieran:BAABNQAECn9DAAMHAAoKoBTvJABdAQAHAAgKvg/vJABdAQAGAAUKzwf2vADjAAAAAA==.Kilsaurys:BAACNQAFFH8KAAMfAAQKlA2vHACEAAAfAAMKlA2vHACEAAAaAAEK+gKaGQA2AAA1AAQKfzEABB8ACgqXG+QkAKoCAB8ACgqXG+QkAKoCABoABwqvEoksALgBABMABQqzDds7ANEAAAAA.Kirakishou:BAAANQAECggICAABNQAFFAMICAAEAAIVAA==.Kismetard:BAABNQAECn8UAAIEAAoKJA/xXwAIAgAEAAoKJA/xXwAIAgABNQAECgoKKAAeAP0OAA==.Kismete:BAABNQAECn8oAAMeAAoK/Q6PCwCkAQAeAAoK/Q6PCwCkAQAdAAEKAAAPQgAmAAAAAA==.',
Ko='Konstantine:BAABNQAECn8kAAMSAAoKnBpXZwBlAgASAAoKnBpXZwBlAgAMAAUKuBSjPAAOAQAAAA==.',
Kr='Kravnoc:BAAANQADCgcIDQAAAA==.Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgAZAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAABNQAECn8hAAIEAAkKIgZ0oQBxAQAEAAkKIgZ0oQBxAQAAAA==.',
La='Lanashamjama:BAAANQAECgQIBQABNQAECgoKLwAaAEEZAA==.Laprimera:BAAANQAECgIIBQAAAA==.Lasticon:BAABNQAECn8aAAIEAAYKBwgJ3QBHAQAEAAYKBwgJ3QBHAQAAAA==.Lazyjade:BAABNQAECn87AAIHAAoKsRvYEABMAgAHAAoKsRvYEABMAgAAAA==.',
Le='Lenarius:BAAANQABCgYIBgAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leprechauñ:BAAANQADCgQIBAAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQAECggIAQAAAA==.Lilsnot:BAAANQAECgMIAwAAAA==.',
Lo='Lorfirandor:BAAANQADCgYIDAAAAA==.Lorynn:BAABNQAECn9AAAIIAAoK1h/cLwCBAgAIAAoK1h/cLwCBAgAAAA==.',
Ma='Maches:BAABNQAECn8ZAAMBAAYK3QfszAC3AAABAAYK3QfszAC3AAAjAAEKWgfnPQAiAAAAAA==.Macready:BAAANQAECgQIAgAAAA==.Madwe:BAABNQAECn8qAAMOAAoK0BAkKQCaAQAOAAkKTBAkKQCaAQAbAAMKNg8OgQCsAAAAAA==.Magturri:BAABNQAECn89AAMEAAoKLB2fQwCgAgAEAAkKhh6fQwCgAgACAAMKcw3yegBWAAAAAA==.Magvara:BAAANQAECggICgAAAA==.Mamameatmode:BAAANQAECgYICQAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCggIKgAAAA==.Maxfrogpower:BAAANQADCggIFAAAAA==.Maxsunward:BAABNQAECn8dAAIMAAYKux4EJQC4AQAMAAYKux4EJQC4AQAAAA==.',
Me='Meepasaurus:BAABNQAECn86AAIiAAoKMyIbBwCHAgAiAAoKMyIbBwCHAgAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAABNQAECn87AAIoAAoK9SP+AgCHAwAoAAoK9SP+AgCHAwAAAA==.Metanoia:BAABNQAECn8wAAMKAAkKRiJKDQALAwAKAAkKCCBKDQALAwAJAAkKoB9dGQCyAgABNQAECgoKTwABAHklAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEBNQAECn8oAAMOAAoK3xzAJwCbAgAOAAoK3xzAJwCbAgAPAAEKKRb4kwBHAAABNQAECgoKGAAfAFAPAA==.Mibb:BAEBNQAECn8nAAIIAAkKECHSPwAGAwAIAAkKECHSPwAGAwABNQAECgoKGAAfAFAPAA==.Midnitetrvlr:BAABNQAECn8bAAIOAAkKNw33YwCBAQAOAAkKNw33YwCBAQAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Minmew:BAAANQADCgQIBAAAAA==.Mirren:BAABNQAECn8jAAIVAAkKMhThCwAAAgAVAAkKMhThCwAAAgAAAA==.Missmoans:BAAANQAECgQIBAABNQAECgoKNQAaAE0UAA==.Mizeeri:BAAANQADCgQIBAAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAABNQAECn8lAAIjAAkKohrkAgAjAwAjAAkKohrkAgAjAwAAAA==.Monre:BAAANQAECgMIBQABNQAECggIEwAZAAAAAA==.Moojito:BAAANQAECgUIBQAAAA==.Moonflame:BAACNQAFFH8GAAIGAAIK6xjRKgCPAAAGAAIK6xjRKgCPAAA1AAQKfzAAAgYACgrYG7MxAKECAAYACgrYG7MxAKECAAAA.Mooriah:BAABNQAECn80AAIfAAoKcAUXYABPAQAfAAoKcAUXYABPAQAAAA==.Mordekhuul:BAABNQAECn81AAIBAAoK2B1hJgDrAgABAAoK2B1hJgDrAgAAAA==.Moserr:BAAANQAECgEIAQAAAA==.Motowa:BAAANQAECgIIBAAAAA==.Mournhide:BAAANQAECggIEAAAAA==.',
Mp='Mpkshaman:BAACNQAFFH8FAAQkAAMKgBbxBQCZAAAkAAMKgBbxBQCZAAANAAEKvgeqMQBHAAAFAAEKHBP/LwA7AAA1AAQKfygABCQACgp1HSELAGkCAA0ACApDGQFCAG0CACQACQpBGyELAGkCAAUAAQo+C3cVAT8AAAAA.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECgkJHwAkABsHAA==.Mynchus:BAABNQAECn8fAAMkAAkKGwftHgBxAQAkAAkKbQbtHgBxAQANAAUK/APtxwB8AAAAAA==.Mysterydh:BAABNQAECn82AAIgAAoKdSFvAgD8AgAgAAoKdSFvAgD8AgAAAA==.Mysterypala:BAAANQAECgcIEAAAAA==.Mysteryvoke:BAABNQAECn8pAAIcAAoKdCOuCwDpAgAcAAoKdCOuCwDpAgAAAA==.Mystodin:BAAANQAECggIEQAAAA==.Myztic:BAAANQADCgEIAQAAAA==.',
['Mä']='Mälförmïtÿ:BAAANQAECgcIBQAAAA==.',
Na='Naneko:BAABNQAECn8YAAMIAAcKpQSpSwERAQAIAAYKOQSpSwERAQAVAAEKwAbbQgAsAAAAAA==.',
Ne='Neelix:BAABNQAECn8uAAMEAAoKhQngkgDjAQAEAAoKhQngkgDjAQACAAUK+gHaZgCQAAAAAA==.Nehi:BAAANQAECggICQAAAA==.Neotahr:BAABNQAECn9DAAICAAoKaRBeGQC8AQACAAoKaRBeGQC8AQAAAA==.Nestli:BAAANQAECgYIBgAAAA==.Neuron:BAEANQABCgUICgABNQAECgIIBgAZAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECn8/AAIEAAoK6RTCZABLAgAEAAoK6RTCZABLAgAAAA==.Nitehunter:BAABNQAECn8yAAIEAAoKkA1NXwAJAgAEAAoKkA1NXwAJAgAAAA==.',
No='Noobert:BAABNQAECn80AAITAAoKTBdTEwAGAgATAAoKTBdTEwAGAgAAAA==.Novademic:BAAANQAECgUIDwAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAQAAAA==.',
Of='Offseason:BAAANQADCgYIBgAAAA==.',
Og='Ognikkay:BAACNQAFFH8GAAIWAAQKugwOAgDFAAAWAAQKugwOAgDFAAA1AAQKf0AAAhYACgppIfIFALECABYACgppIfIFALECAAAA.',
Ok='Okboomer:BAAANQADCgUIBQABNQAECgkJMAAfAHskAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.Orcpriest:BAAANQAECgQICQABNQAECgoKJAAOANAXAA==.',
Oy='Oyea:BAABNQAECn8hAAMTAAoKCxzRCgCPAgATAAkKCxzRCgCPAgAfAAQKbArsYgCZAAABNQAECgoKOwAHALEbAA==.',
Pa='Pabiloneta:BAABNQAECn8VAAIEAAgKsRkWdADXAQAEAAgKsRkWdADXAQABNQAECgkJHgAJAJ4bAA==.Pakami:BAAANQAECgYIBgAAAA==.Pallyana:BAABNQAECn9JAAISAAoK0h5rNACSAgASAAoK0h5rNACSAgAAAA==.Palosdin:BAABNQAECn8WAAISAAcKKwd5CgHZAAASAAcKKwd5CgHZAAAAAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQAECgQICAABNQAECgYIEAAZAAAAAA==.Pass:BAAANQAECgcIEAABNQAECgoKMwAQALokAA==.',
Pe='Perridan:BAAANQAECggICwAAAA==.',
Ph='Phalandrel:BAABNQAECn8cAAIEAAoKBRaqcgAsAgAEAAoKBRaqcgAsAgAAAA==.Phewphew:BAAANQAECgMIBgAAAA==.Phiora:BAAANQAECgEIAQABNQAECgUICgAZAAAAAA==.',
Pi='Pinkponyclub:BAABNQAECn9LAAIDAAoKxhyCIQDnAgADAAoKxhyCIQDnAgAAAA==.Pinkyshock:BAABNQAECn9nAAIMAAoKWB79CQD8AgAMAAoKWB79CQD8AgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICAAZAAAAAA==.Portholes:BAABNQAECn8nAAIIAAoK6hkKOwBcAgAIAAoK6hkKOwBcAgAAAA==.',
Pr='Praystatiøn:BAAANQAECgcIDAAAAA==.',
Ps='Psyop:BAABNQAECn8dAAIFAAkK+BzmHgDvAgAFAAkK+BzmHgDvAgAAAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAABNQAECn8cAAInAAkKzxuzBQBhAgAnAAkKzxuzBQBhAgABNQAFFAgIGQAQAAwbAA==.Purplod:BAABNQAECn8jAAMbAAkKgQpXTQCCAQAbAAkK2wlXTQCCAQAPAAUKXAhfjwDHAAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
['Pò']='Pòpemz:BAAANQADCgUIBAAAAA==.',
Qi='Qing:BAABNQAECn80AAIlAAoKOB1jCACmAgAlAAoKOB1jCACmAgAAAA==.',
Qy='Qybxboogied:BAABNQAECn8VAAIfAAkKiBApTACzAQAfAAkKiBApTACzAQAAAA==.Qybxboogies:BAABNQAECn8cAAMGAAkKHhf8QwApAgAGAAgKhRn8QwApAgAHAAIKzQWUaABfAAAAAA==.Qybxboogyy:BAAANQAECggIDQAAAA==.',
Ra='Raensong:BAABNQAECn8gAAMSAAoKFBF/hQDBAQASAAoKFBF/hQDBAQAMAAMKawfVSwB1AAAAAA==.Rafterman:BAAANQAECgQIBAAAAA==.Rainingarrow:BAAANQAECgYICgAAAA==.Raisa:BAABNQAECn9MAAMBAAoKniPyHgCZAgABAAoKgiPyHgCZAgAjAAMK3xpTLwAMAQAAAA==.Rakarum:BAAANQAECgEIAQAAAA==.Rasar:BAABNQAECn8pAAIIAAoKoRVBWAALAgAIAAoKoRVBWAALAgAAAA==.Rathew:BAABNQAECn8YAAMFAAkKeh0YTQAvAgAFAAgKKR4YTQAvAgANAAMK7AYO1QBnAAAAAA==.Rawnext:BAABNQAECn8ZAAIIAAgKNxh5hwCZAQAIAAgKNxh5hwCZAQABNQAFFAQIBgARANsOAA==.',
Re='Renaitiaalaa:BAAANQAECgUICAAAAA==.Renei:BAABNQAECn8fAAMKAAcK1xvzRwDgAQAKAAcK1xvzRwDgAQAJAAMK2wm7RQB2AAABNQAECgoKNAAFADQiAA==.Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECn9OAAQEAAkKxxNmVAB0AgAEAAkKIhNmVAB0AgACAAcKUA6UPQBmAQApAAIK6g8KEAB/AAAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAACNQAFFH8GAAIGAAQKNxT/GQAmAQAGAAQKNxT/GQAmAQA1AAQKfz8ABAYACgqUJXgEAKkDAAYACgqUJXgEAKkDAAsABQqwIo0IANsBAAcAAgr7FXBIAIkAAAAA.Riott:BAAANQADCggICQAAAA==.',
Ro='Rollo:BAAANQADCgQIBAABNQAECgkJMAAfAHskAA==.Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECggICwAAAA==.Rox:BAAANQAECgcIEgAAAA==.Royal:BAAANQADCgcIDAAAAA==.Royle:BAAANQAECgMIAQAAAA==.Roysham:BAAANQAECgQICAAAAA==.Roywar:BAAANQAECgEIAQAAAA==.',
Ru='Rubiks:BAAANQAECggIAQAAAA==.',
['Ré']='Réîgn:BAABNQAECn8pAAIOAAoK0xQPHQD6AQAOAAoK0xQPHQD6AQAAAA==.',
Sa='Sacrus:BAABNQAECn8cAAISAAYKjBDP5wARAQASAAYKjBDP5wARAQAAAA==.Santoss:BAAANQADCgQIBAAAAA==.Sarah:BAABNQAECn8YAAMCAAkKZyFlFAC8AgACAAkKZyFlFAC8AgAEAAEKcxB0UgFAAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAZAAAAAA==.Scksattankin:BAAANQADCgEIAQAAAA==.Scoobear:BAAANQAECggIEAABNQAECgoKLgASAFMXAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQAECgQIBgAAAA==.Senjougahara:BAACNQAFFH8bAAIbAAgKeh2sAgAYAgAbAAgKeh2sAgAYAgA1AAQKf08AAhsACgqNJXQEAFIDABsACgqNJXQEAFIDAAAA.Seriyah:BAACNQAFFH8TAAIWAAQKVharAQDjAAAWAAQKVharAQDjAAA1AAQKfzoAAhYACgqoHbYHAOICABYACgqoHbYHAOICAAAA.Serph:BAABNQAECn8iAAQSAAoKPhErugBdAQASAAkKKBErugBdAQAMAAYKMBGSSADLAAADAAQKUA9HuACqAAABNQAECgoKNQAaAE0UAA==.',
Sh='Shabane:BAABNQAECn9EAAIlAAoKlx46AwC9AgAlAAoKlx46AwC9AgAAAA==.Shame:BAABNQAECn8yAAIHAAkKxRf4FwCVAgAHAAkKxRf4FwCVAgAAAA==.Shankey:BAAANQAECgYIAQAAAA==.Shiminy:BAAANQAECgMIAwAAAA==.Shinobi:BAABNQAECn8iAAIQAAoKaBN8LQCtAQAQAAoKaBN8LQCtAQAAAA==.Shiol:BAAANQAECgMIAwABNQAECgcIEgAZAAAAAA==.Shirls:BAABNQAECn8jAAIDAAoKnhrsNQCMAgADAAoKnhrsNQCMAgAAAA==.Shivak:BAABNQAECn9HAAIeAAoKLhXOBACuAgAeAAoKLhXOBACuAgAAAA==.Shivanie:BAABNQAECn8gAAIDAAoKchgCJQCeAgADAAoKchgCJQCeAgAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAABNQAECn8jAAIJAAkKTh2WJABkAgAJAAkKTh2WJABkAgAAAA==.Shrug:BAABNQAECn8gAAIYAAkK+BSOfgAeAgAYAAkK+BSOfgAeAgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAZAAAAAA==.',
Si='Siccem:BAAANQAECgIIAgAAAA==.Sicwiddit:BAABNQAECn8kAAIEAAkKlxNrWQAXAgAEAAkKlxNrWQAXAgAAAA==.Sinadin:BAAANQADCgQIBAABNQAECgkJMAAfAHskAA==.Sinsha:BAAANQADCgUIBQABNQAECgkJMAAfAHskAA==.',
Sk='Skeeda:BAAANQAECgUIEwAAAA==.Skylinex:BAABNQAECn8nAAIKAAoK1BfcFABAAgAKAAoK1BfcFABAAgAAAA==.Skylinez:BAAANQAECgUIBwAAAA==.Skïttles:BAABNQAECn81AAQaAAoKTRSLIgDjAQAaAAoKTRSLIgDjAQAfAAMKpQS3tAAuAAATAAIKzwPffAAfAAAAAA==.',
Sl='Sleezball:BAABNQAECn8hAAISAAoKJhJukQACAgASAAoKJhJukQACAgAAAA==.',
So='Softie:BAAANQAECgIIAgABNQAECgkJJwAYAGAbAA==.Sonictide:BAAANQAECgYIDgAAAA==.Soulscream:BAABNQAECn8nAAIGAAkKyB9vFwAaAwAGAAkKyB9vFwAaAwAAAA==.',
Sp='Spaghetto:BAABNQAECn82AAIfAAoKGRjwIADGAgAfAAoKGRjwIADGAgAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECggIDQAAAA==.',
Su='Suzel:BAAANQAECgQIBAAAAA==.',
Sw='Sweetlips:BAAANQAECgQIBAAAAA==.Swiftyninja:BAABNQAECn8iAAIJAAoKGxWwCgAsAgAJAAoKGxWwCgAsAgABNQAECgoKRgAMALsdAA==.',
Sy='Sydaria:BAAANQABCgMIAwAAAA==.Synder:BAABNQAECn8wAAIeAAoKWQY5DgBkAQAeAAoKWQY5DgBkAQAAAA==.',
Ta='Tainin:BAABNQAECn80AAIFAAoKNCK6EQAsAwAFAAoKNCK6EQAsAwAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAABNQAECn9BAAIBAAoK+Q+oTgDoAQABAAoK+Q+oTgDoAQAAAA==.Tazdingobomb:BAABNQAECn8XAAINAAoK3hDMPADhAQANAAoK3hDMPADhAQAAAA==.Tazerface:BAABNQAECn8/AAMVAAoKKhH0DgC7AQAVAAoKKhH0DgC7AQAIAAYK7gPiWwH5AAAAAA==.',
Te='Techjacket:BAAANQADCgQIBAAAAA==.Tekin:BAABNQAECn9AAAIDAAoKZhomMABhAgADAAoKZhomMABhAgAAAA==.Teleprompter:BAAANQAECgYIEAAAAA==.Telrissan:BAABNQAECn8nAAIIAAoKxB6YZQCzAgAIAAoKxB6YZQCzAgAAAA==.Tenkawnor:BAABNQAECn8UAAIfAAkK4QkcUgDWAAAfAAkK4QkcUgDWAAAAAA==.Tenyroldemon:BAABNQAECn82AAQgAAoKeiGoBAD3AgAgAAoKeiGoBAD3AgARAAMKvwg7RQCIAAAhAAIK9hEAAAAAAAAAAA==.Tenzingyatso:BAAANQADCgYICgAAAA==.Tero:BAAANQADCgIIAgAAAA==.',
Th='Thald:BAABNQAECn82AAIlAAoK2xpgBQBMAgAlAAoK2xpgBQBMAgAAAA==.Thaznotmilk:BAAANQAECgYIBgAAAA==.Thxowlbama:BAAANQAECgMIAQABNQAECgoKHAADANgbAA==.',
Ti='Timzilla:BAAANQAECgUIBQABNQAECgoKOgAPANEeAA==.Tinylight:BAAANQADCgQIBAAAAA==.Tinytip:BAAANQADCggIDgAAAA==.Tisakna:BAABNQAECn9NAAQIAAoKJyRVRAD7AgAIAAkK1yJVRAD7AgAVAAMKiiP7GgAbAQAUAAEKeR9/CgBaAAAAAA==.Titanus:BAAANQABCgIIAgAAAA==.',
To='Togon:BAAANQAECggICAAAAA==.Tooezy:BAAANQAECgQICQAAAA==.Tool:BAAANQAECgUICgAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAABNQAECn8aAAIJAAkKpheIOgDpAQAJAAkKpheIOgDpAQABNQAECgoKQQAMAPMeAA==.Trask:BAABNQAECn8jAAIIAAkKZRYcuQARAgAIAAkKZRYcuQARAgAAAA==.Trishalle:BAAANQADCgQIBAABNQAECgoKKwAfAFwTAA==.Trogdoor:BAAANQAECgQIBQAAAA==.Trokom:BAACNQAFFH8RAAMIAAcKUyZCCQA0AgAIAAYKQyZCCQA0AgAVAAEKkiauCgBzAAA1AAQKfz4AAggACgr6JmUCAOgDAAgACgr6JmUCAOgDAAE1AAUUBwoRAAgAUyYA.Trokopally:BAAANQAECgYIBgABNQAFFAcKEQAIAFMmAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECn8xAAMBAAoKkgt8dAB+AQABAAoKkgt8dAB+AQAjAAMK6wcwUgCIAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggIEAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECn8gAAMQAAkKwRzHGQB0AgAQAAkKwRzHGQB0AgAlAAEKyARwMwAoAAAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgoKTAAaAJMTAA==.Vandermark:BAABNQAECn9MAAUaAAoKkxMJHQBLAgAaAAkKjhMJHQBLAgATAAoK/RISFwDVAQAWAAUKohQYHgArAQAfAAQK1QsDggDIAAAAAA==.Varuna:BAAANQAECgcIDwABNQAECgoKNgAbABUlAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIDwAAAA==.Victus:BAAANQAECgYIBwAAAA==.Vidrus:BAAANQAECggICQAAAA==.Vilkas:BAACNQAFFH8IAAIHAAUKxh73BwCRAQAHAAUKxh73BwCRAQA1AAQKfx4AAgcACgotIc8JAEQDAAcACgotIc8JAEQDAAE1AAUUBAgFABEAMxIA.Viserion:BAAANQADCgYIEgAAAA==.',
Wa='Waddledoo:BAABNQAECn8gAAIFAAgKkx+rLgCnAgAFAAgKkx+rLgCnAgAAAA==.Warmaku:BAABNQAECn8gAAIaAAkKyR3KHAAfAgAaAAkKyR3KHAAfAgAAAA==.',
We='Webz:BAAANQAECgIIBAAAAA==.Weezybaby:BAAANQAECgQIBAAAAA==.',
Wh='Whïteoak:BAACNQAFFH8JAAIaAAQKIwcHDQDdAAAaAAQKIwcHDQDdAAA1AAQKfy0AAhoACgpcHJsQANECABoACgpcHJsQANECAAAA.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECn8dAAIPAAkKxx/8GADlAgAPAAkKxx/8GADlAgAAAA==.Xanyp:BAAANQAECgEJAwABNQAECgkJHQAPAMcfAA==.',
Xe='Xeletath:BAAANQAECgYICwAAAA==.',
Xi='Xinaveruk:BAAANQAECggIDwAAAA==.',
Xo='Xoro:BAAANQAECgQICgAAAA==.',
Xr='Xrxyz:BAABNQAECn8bAAMSAAkKNAoTBwHeAAASAAkKJAoTBwHeAAAMAAIKtwOpdAAYAAAAAA==.',
Xs='Xshamster:BAABNQAECn9cAAMFAAoKUBkUKwC2AgAFAAoKUBkUKwC2AgANAAEKAAD3MQE3AAAAAA==.',
Ye='Yen:BAAANQADCgMIAwAAAA==.Yewna:BAABNQAECn8WAAIGAAkK8xn+MwBwAgAGAAkK8xn+MwBwAgABNQAECgoKSAAFAKwkAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAQAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAPAMcfAA==.Zau:BAABNQAECn8iAAQnAAgKwh3DBgA7AgAnAAcKXiDDBgA7AgABAAQKexND8ADqAAAjAAIK1g9tIABuAAAAAA==.',
Ze='Zed:BAABNQAECn8iAAIRAAoKOxq4DwBcAgARAAoKOxq4DwBcAgABNQAECgoKMwAQALokAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAFFAQIDgAIAGMfAA==.Zolja:BAABNQAECn8VAAMjAAgKvwfFHwBxAAABAAUK7AX/BQHAAAAjAAQKkwnFHwBxAAAAAA==.Zoney:BAAANQAECgIIAwAAAA==.Zordlon:BAAANQAECgYIEwAAAA==.',
Zu='Zukem:BAABNQAECn8nAAIEAAoKNB6vNADNAgAEAAoKNB6vNADNAgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgYIDAABNQAECgcIEgAZAAAAAA==.',
Zy='Zyariah:BAAANQADCggIFQAAAA==.Zyvea:BAABNQAECn83AAIYAAoKlBi0SwCmAgAYAAoKlBi0SwCmAgAAAA==.',
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
