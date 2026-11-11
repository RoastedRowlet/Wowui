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

local lookup = {'Warlock-Demonology','Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Paladin-Protection','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','DemonHunter-Devourer','Paladin-Retribution','Druid-Guardian','Mage-Fire','Mage-Frost','Druid-Feral','Unknown-Unknown','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warrior-Arms','Warlock-Destruction','Shaman-Enhancement','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Monk-Mistweaver','Druid-Restoration','Hunter-Survival',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acidsword:BAACNQAFFH8FAAIBAAIKEhEjJgCMAAABAAIKEhEjJgCMAAA1AAQKfzIAAgEACQptHk8cAJkCAAEACQptHk8cAJkCAAE1AAUUBwgOAAIAShkA.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQAECgUIBQABNQAFFAQICwADALofAA==.Adrua:BAAANQAECgYICAAAAA==.Adym:BAABNQAECn8kAAIEAAoK7BM7fQATAgAEAAoK7BM7fQATAgAAAA==.',
Ag='Agave:BAABNQAECn9JAAIFAAoKRhR2PAAOAgAFAAoKRhR2PAAOAgAAAA==.',
Ai='Aiyah:BAAANQAECgQICQAAAA==.',
Al='Altarboi:BAABNQAECn8pAAMGAAgKOSM1FwALAwAGAAgKOSM1FwALAwAHAAEKKgXZeQA0AAAAAA==.Alüçard:BAABNQAECn8wAAIIAAcK2w7/sQAvAQAIAAcK2w7/sQAvAQAAAA==.',
Am='Amoraniel:BAABNQAECn8rAAIIAAoKgxrwbwCeAgAIAAoKgxrwbwCeAgAAAA==.',
An='Anavar:BAAANQAECgYIBwAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAABNQAECn8dAAMJAAkKnhuLIgByAgAJAAkKMBuLIgByAgAKAAQKsBh/ggD9AAAAAA==.Andresra:BAABNQAECn8tAAIIAAkKuiBrZwCvAgAIAAkKuiBrZwCvAgABNQAECgkJHQAJAJ4bAA==.Anie:BAAANQADCgQIBAAAAA==.Annaluna:BAAANQAECgUIBgAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAABNQAECn8hAAMGAAoK0xYGNABaAgAGAAoKvxUGNABaAgALAAQKGwqKFwC5AAAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
As='Asrael:BAAANQAECggIDgABNQAECgoKOAAMAFsaAA==.Asterin:BAAANQADCggIDgAAAA==.',
At='Athená:BAAANQAECgEIAgAAAA==.',
Au='Audersi:BAAANQADCgQIBQAAAA==.Augtism:BAAANQAECgIIAgABNQAECgoKHAADANgbAA==.Aunumator:BAAANQADCgYIBgAAAA==.',
Av='Avâtre:BAABNQAECn8lAAINAAoKURZ6WwAQAgANAAoKURZ6WwAQAgAAAA==.',
Az='Azlea:BAAANQAECgcIBgAAAA==.',
Ba='Baguette:BAAANQAECgYIDwAAAA==.Bajingobomb:BAABNQAECn9CAAMOAAoKACGYDgCGAgAOAAoKySCYDgCGAgAPAAYKER19SwDJAQAAAA==.Bajisil:BAAANQAECgUIBwABNQAECgoKQgAOAAAhAA==.Bakblood:BAAANQABCgYICgAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEIAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgYICgAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAABNQAECn8VAAIQAAYKJRkbJgBRAQAQAAYKJRkbJgBRAQAAAA==.',
Be='Be:BAABNQAECn8yAAIGAAgKMxvONwBJAgAGAAgKMxvONwBJAgAAAA==.Beckyoncé:BAABNQAECn8/AAIRAAoKwSKJBACMAwARAAoKwSKJBACMAwAAAA==.Bedris:BAABNQAECn8sAAQMAAoKJBOLIwDFAQAMAAcKFReLIwDFAQASAAoKEwwCsABaAQADAAEKXQK/NwEfAAAAAA==.Beerticus:BAABNQAECn80AAIQAAgKzRuDFwDkAQAQAAgKzRuDFwDkAQAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECn8cAAITAAkKthkAEABgAgATAAkKthkAEABgAgAAAA==.Binggles:BAACNQAFFH8xAAQIAAkKAR4IAgDcAgAIAAkKfBwIAgDcAgAUAAQK4RdcAAD0AAAVAAIKiyXlAwDaAAA1AAQKfzQAAxQACgpNJrUAAOECAAgACgqdJdIgAFcDABQACAr9JLUAAOECAAAA.',
Bl='Blacksheep:BAAANQAECgMIBAAAAA==.Blazze:BAAANQAECgUICwABNQAECgoKLAAEAEMfAA==.Blôôðhôôf:BAAANQADCgQIBAABNQAECgoKJwAWAD0RAA==.',
Bo='Boaj:BAAANQAECgYIEAAAAA==.Bokinar:BAAANQAECggICgAAAA==.Bomboclaat:BAAANQAECgQIDAABNQAECgoKMgAQALokAA==.Boolay:BAABNQAECn8kAAMMAAoKGR1hHwDqAQAMAAcKNx1hHwDqAQASAAcKPxKq0wAbAQABNQABCgUIBQAXAAAAAA==.Boomcommand:BAAANQAECgEIAwAAAA==.Boosteyboy:BAAANQAECgYICwAAAA==.Bootyshotz:BAAANQAECgEIAQABNQAECgoKIQASAD4RAA==.Boozing:BAAANQADCggICgABNQAECgoKNQAEAGkiAA==.Bopstds:BAAANQAECgUICAAAAA==.Bosmina:BAABNQAECn9GAAIGAAoKUhz+NQCQAgAGAAoKUhz+NQCQAgAAAA==.',
Br='Braei:BAABNQAECn86AAIDAAkKkxFzXQCPAQADAAkKkxFzXQCPAQAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Breelynn:BAAANQADCggICAAAAA==.Brenhunt:BAABNQAECn8aAAIEAAoK9RZ+NgBfAgAEAAoK9RZ+NgBfAgAAAA==.Brenmonk:BAABNQAECn8fAAIQAAcK8gofNgBkAQAQAAcK8gofNgBkAQAAAA==.Brenpriest:BAAANQADCggIDgAAAA==.Brenshammy:BAAANQADCgcIDAAAAA==.Bruenor:BAAANQAECgMIAwAAAA==.Bruucey:BAAANQAECgcIEwAAAA==.',
Bu='Bubblebaddie:BAAANQAECgQIBwAAAA==.Bubblicous:BAAANQAECgcICgAAAA==.Bugenhagen:BAABNQAECn9EAAIFAAoKrCRfBwCHAwAFAAoKrCRfBwCHAwAAAA==.Butchers:BAAANQAECgYICwAAAA==.Buttpaladin:BAABNQAECn8nAAISAAgK2BaNkgD/AQASAAgK2BaNkgD/AQAAAA==.',
Ca='Caliden:BAAANQAECgEIAQAAAA==.Capelady:BAAANQADCgMIAwAAAA==.Cardib:BAACNQAFFH8SAAQOAAgKPRwsBwCoAQAOAAUKeSIsBwCoAQAYAAMKmhAFDwDqAAAPAAEK0SARHwBiAAA1AAQKf0kAAw4ACgoiJvoGAI4DAA4ACgqxJfoGAI4DABgACAoUJYYLAPYCAAAA.Cavos:BAABNQAECn8dAAIRAAcKgRuLJwAIAgARAAcKgRuLJwAIAgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAABNQAECn9BAAIPAAoK4hgLGQAqAgAPAAoK4hgLGQAqAgAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Cheesen:BAAANQAECgQIBgAAAA==.Chiri:BAECNQAFFH8PAAQZAAYKyQG6DAADAQAZAAYKyQG6DAADAQAaAAMKxAVKBQCHAAAbAAEKAACCDwAAAAA1AAQKfysABBoACgouEwUUAA4CABoACgqxEQUUAA4CABsABArJDlYQAMcAABkAAwoSAyRFAHkAAAAA.Chvngus:BAABNQAECn82AAMSAAoKHB+XLQARAwASAAoKEh+XLQARAwAMAAYK4xhHIABVAQAAAA==.',
Ci='Citizencain:BAABNQAECn8UAAIIAAUKixs9CAF/AQAIAAUKixs9CAF/AQAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMICQAAAA==.',
Co='Cocheeze:BAAANQAECgcIDAABNQAECgoKJAAOANAXAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEBNQAECn8YAAIcAAoKUA/cSgC6AQAcAAoKUA/cSgC6AQAAAA==.Conmammoth:BAABNQAECn8gAAISAAgK0h94VwAXAgASAAgK0h94VwAXAgAAAA==.Conquest:BAAANQAECgIIAgAAAA==.Coohwhip:BAAANQAECgIIBAAAAA==.Cornorgan:BAAANQAECggIEwAAAA==.Corèl:BAAANQADCgUIBwAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAABNQAECn8rAAIcAAoKXBMMNQBAAgAcAAoKXBMMNQBAAgAAAA==.Cristobal:BAAANQAECgYIDAAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.Crykthiria:BAAANQADCgEIAQAAAA==.',
Cu='Curaga:BAAANQAECgMIAwAAAA==.Curnsarn:BAAANQAECgYICQABNQAECgoKQQAPAOIYAA==.',
Cy='Cydea:BAAANQAECgQICwAAAA==.',
Da='Dagidan:BAABNQAECn9CAAIdAAoKrRF7DAD/AQAdAAoKrRF7DAD/AQAAAA==.Darktide:BAAANQAECggIEAAAAA==.Dashawmon:BAAANQADCggICAABNQADCgYICQAXAAAAAA==.Dashel:BAAANQAECggIDwABNQAECgoKQwAHAKAUAA==.Dayveni:BAAANQAECgEIAQAAAA==.',
De='Dead:BAAANQAECgEIAgAAAA==.Deathtoxi:BAAANQAECgIIAgAAAA==.Degey:BAAANQAECggICgAAAA==.Demonsoul:BAAANQADCgQIBAAAAA==.Demontotems:BAAANQAECgcIDAAAAA==.Demotoxi:BAACNQAFFH8GAAIRAAQK2w6RCQC9AAARAAQK2w6RCQC9AAA1AAQKf0EABBEACgorIAgKAKkCABEACgorIAgKAKkCAB4ABApQGWRhAPUAAB0AAgrNCqcsAFEAAAAA.Deriso:BAABNQAECn8fAAMEAAoKjiGILgDiAgAEAAoKeSCILgDiAgACAAMKBhkZYwCdAAAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAXAAAAAA==.Destrozinth:BAABNQAECn8UAAIbAAoKgA3tEAAoAQAbAAoKgA3tEAAoAQAAAA==.Dethorok:BAABNQAECn9JAAIEAAoKFiZUBABrAwAEAAoKFiZUBABrAwAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQAECgEIAwAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgoKRAAFAKwkAA==.Dib:BAAANQAECgcIEgAAAA==.Digey:BAABNQAECn8yAAMfAAoKAyPBBAA1AwAfAAoKAyPBBAA1AwAgAAMKoQyB9AB4AAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAABNQAECn8nAAIhAAoKnwb8CwDsAAAhAAoKnwb8CwDsAAAAAA==.',
Do='Dontlookatme:BAAANQAECgEIBAAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCggIEwABNQAECgEIAwAXAAAAAA==.',
Dr='Drakbek:BAABNQAECn8kAAITAAcKuht5EwAsAgATAAcKuht5EwAsAgAAAA==.Dreadshot:BAAANQADCgYIBwAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dremaster:BAAANQADCggIDgAAAA==.Dronebot:BAABNQAECn9tAAMHAAoK2BzMDgAEAwAHAAoK2BzMDgAEAwAGAAEK8wsO5gA8AAAAAA==.Drucifer:BAAANQADCggIFwAAAA==.',
Du='Dud:BAAANQAECgYICQABNQAECgkJGAAFAHodAA==.Dumbrouge:BAAANQAECgIIAgABNQAECgoKOAAMAFsaAA==.Durros:BAABNQAECn8sAAIFAAoKMxk7MABJAgAFAAoKMxk7MABJAgAAAA==.Durto:BAAANQABCgEIAQAAAA==.Dustyshotz:BAAANQAECgYICQAAAA==.',
Dy='Dyhanna:BAAANQAECggIBwAAAA==.',
Eb='Eboger:BAAANQAECgMIAwAAAA==.',
Eg='Egam:BAAANQAECgUIBQAAAA==.',
El='Elunelphie:BAAANQAECgcIDAAAAA==.',
Em='Embody:BAABNQAECn8jAAIcAAoK8AoeVwB6AQAcAAoK8AoeVwB6AQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECn8oAAISAAoKixxIWQCLAgASAAoKixxIWQCLAgAAAA==.',
Er='Erasmas:BAACNQAFFH8LAAIDAAQKuh/3CwByAQADAAQKuh/3CwByAQA1AAQKf1oABAMACgrsJGYGAJkDAAMACgrsJGYGAJkDABIACQpwHyA9AGUCAAwAAgoVILs8AKYAAAAA.Erasmos:BAAANQAECgYIBgABNQAFFAQICwADALofAA==.Erzascarlét:BAABNQAECn9CAAIMAAoKux1CCwDlAgAMAAoKux1CCwDlAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYIDgAAAA==.',
Ev='Evildeader:BAABNQAECn8kAAIOAAoK0BfVEwBFAgAOAAoK0BfVEwBFAgAAAA==.Eviltotems:BAABNQAECn8jAAINAAoKyRaNKgAhAgANAAoKyRaNKgAhAgABNQAECgoKJAAOANAXAA==.Eviscration:BAAANQADCgIIAgABNQADCgcICAAXAAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Ez='Ezyy:BAAANQAECgQIBwAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECn9GAAQNAAoKVB9bGwAlAwANAAoKVB9bGwAlAwAFAAYKxA1ZgwAUAQAiAAMKRwk1JwCzAAAAAA==.Fantasma:BAAANQAECgEIAgAAAA==.',
Fe='Fear:BAAANQAECgIIBAAAAA==.',
Fi='Findal:BAAANQAECgUIBAABNQABCgUIBwAXAAAAAA==.Fistymoo:BAEANQAECgIIAgABNQAFFAYIDwAZAMkBAA==.Fivemagics:BAABNQAECn82AAMBAAoK4BYeZAAtAgABAAkKEhceZAAtAgAhAAIKERUXHwBtAAAAAA==.',
Fl='Flayvour:BAAANQABCgQIBAABNQAECgoKNAAjADgdAA==.Fleaboy:BAABNQAECn8XAAMkAAgKHhG2CQDqAQAkAAgKHhG2CQDqAQAKAAEKSwShUQA6AAAAAA==.Flist:BAABNQAECn8yAAIQAAoKuiSKAwCeAwAQAAoKuiSKAwCeAwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAABNQAECn8mAAMIAAoKNRUFhwCHAQAIAAoKiBIFhwCHAQAVAAIKFh27KwCdAAAAAA==.Foote:BAAANQAECggIBwABNQAFFAYIEwAZAGUGAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAABNQAECn8kAAIHAAoKIhTKJwDsAQAHAAoKIhTKJwDsAQAAAA==.Freesia:BAAANQAECgIIBgAAAA==.Fruitjuice:BAABNQAECn8bAAIhAAgKWA5QCgAMAQAhAAgKWA5QCgAMAQAAAA==.',
Fu='Furrios:BAAANQADCggIDgAAAA==.',
Fx='Fxce:BAACNQAFFH8MAAIKAAUKWQSjFgC5AAAKAAUKWQSjFgC5AAA1AAQKf1sAAgoACgqaHH8XALYCAAoACgqaHH8XALYCAAAA.',
['Fâ']='Fâmine:BAABNQAECn8XAAIBAAoK0AtbVgC9AQABAAoK0AtbVgC9AQABNQAECgoKKQAOANMUAA==.',
Ga='Gaothan:BAAANQAECggIDgAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECn82AAIeAAoKPxWkHwD5AQAeAAoKPxWkHwD5AQAAAA==.',
Gl='Glaiven:BAABNQAECn8hAAIRAAkKaRNbKwDnAQARAAkKaRNbKwDnAQAAAA==.Glasscleaner:BAABNQAECn8cAAIDAAoKFSL+CgBwAwADAAoKFSL+CgBwAwABNQAFFAcIGgAZAPccAA==.Glenmorangie:BAABNQAECn8vAAMLAAoKEx+yBAB4AgALAAgKkB2yBAB4AgAHAAgKox8DFgDrAQAAAA==.',
Gn='Gnartusk:BAABNQAECn8+AAIPAAkK7iHiDgClAgAPAAkK7iHiDgClAgAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgUICwAXAAAAAA==.Gordrack:BAAANQAECgEIAQAAAA==.',
Gr='Grawlso:BAAANQADCgYIBgAAAA==.Greens:BAABNQAECn9TAAIcAAoKzh9rCwDfAgAcAAoKzh9rCwDfAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAXAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgMIBwABNQAECgYIDwAXAAAAAA==.Grïma:BAACNQAFFH8GAAMlAAQKLAlAAwDJAAAlAAMKLAlAAwDJAAABAAIKWgW7OQAAAAA1AAQKfzoAAyUACgqQGkgEAJwCACUACgqQGkgEAJwCAAEABApPEp7bAIgAAAAA.',
Gs='Gsus:BAAANQADCggICAABNQAECgoKNAAjADgdAA==.',
Gu='Gueritestje:BAABNQAECn8/AAIMAAoKESE2CAC1AgAMAAoKESE2CAC1AgAAAA==.Guzzlord:BAABNQAECn8hAAQZAAkKJwibJwB7AQAZAAkKJwibJwB7AQAaAAQKQQZFLQC2AAAbAAQKbQdeGQCnAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAgABNQAECgoKIwAEAKMSAA==.Handsomejack:BAAANQAECgEIBQABNQAECgoKQgAOAAAhAA==.Hanekawa:BAAANQAECggIAQABNQAECggIBwAXAAAAAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAXAAAAAA==.',
Hb='Hboozing:BAABNQAECn81AAMEAAoKaSJ4EwBRAwAEAAoKaSJ4EwBRAwACAAEKkxI+gwA8AAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Healynn:BAAANQAECgIIAgAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAXAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Himootation:BAAANQADCgQIBAAAAA==.Hipdrop:BAAANQAECgMIBAAAAA==.Hitodh:BAAANQAECgUIBQABNQAECgoKNgAYABUlAA==.Hitoshura:BAABNQAECn82AAMYAAoKFSUXBgA6AwAYAAoK6SQXBgA6AwAOAAcK+iQjGwDpAgAAAA==.Hittnrunn:BAAANQAECgEIAQAAAA==.',
Ho='Holyginger:BAABNQAECn8VAAMSAAcKIhUjvAClAQASAAYKUBgjvAClAQADAAEKfhT05QA8AAAAAA==.Holyglizzy:BAABNQAECn8tAAISAAoKWBZRVwAXAgASAAoKWBZRVwAXAgAAAA==.Holymajìk:BAAANQAECgEIAQAAAA==.Holytoxi:BAAANQADCgEIAQABNQAFFAQIBgARANsOAA==.',
Hy='Hypérîon:BAAANQAECgQIBwAAAA==.',
Ia='Iagging:BAABNQAECn8VAAImAAgK0iFeCwDPAgAmAAgK0iFeCwDPAgABNQAFFAcIGgAZAPccAA==.',
Ic='Ichtaca:BAAANQADCgEIAQAAAA==.',
Ik='Ikiryo:BAEANQAECgIICwAAAA==.',
Im='Imtuggdup:BAABNQAECn80AAMIAAoKiSGxNwAZAwAIAAoKiSGxNwAZAwAVAAMKtxhAJQCgAAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Indra:BAAANQAECgEIAQAAAA==.Infidel:BAABNQAECn8wAAIcAAkKeyRcBgCiAwAcAAkKeyRcBgCiAwAAAA==.Invert:BAAANQAFFAEIAQAAAA==.Invincibúll:BAAANQADCgYIBgAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgMIBgAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irayne:BAAANQADCgQIBAAAAA==.Irisharcher:BAAANQAECggIDQAAAA==.Irishbeauty:BAAANQAECgUIBQAAAA==.Irishfury:BAAANQADCgcICQAAAA==.Irishman:BAAANQAECggIEQAAAA==.',
Is='Isengardd:BAAANQAECgEIAQAAAA==.',
It='Itazki:BAABNQAECn9EAAMWAAoKwCM3AgAwAwAWAAoKwCM3AgAwAwAcAAEKHQzZjAAnAAAAAA==.',
Ja='Jackpot:BAAANQAECgIIAgAAAA==.Jaft:BAAANQADCgYIEAAAAA==.Jalter:BAACNQAFFH8aAAIZAAcK9xxoBAAyAgAZAAcK9xxoBAAyAgA1AAQKfzkAAhkACgowIxEEAHIDABkACgowIxEEAHIDAAAA.Janha:BAAANQADCggIDwAAAA==.',
Je='Jediknight:BAAANQAECgQIBQAAAA==.Jefe:BAAANQADCggICAAAAA==.Jelial:BAAANQAECgEIAQAAAA==.Jenga:BAAANQAECgcIDwAAAA==.Jergal:BAABNQAECn8fAAIgAAoK5AtolABDAQAgAAoK5AtolABDAQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAACNQAFFH8IAAMSAAQKfgVoGgCuAAASAAMKfgVoGgCuAAADAAIK1QRCHwBuAAA1AAQKf0MAAxIACgpTFg18ADICABIACgpTFg18ADICAAMACgp8DTlMANABAAAA.',
Ji='Ji:BAAANQADCgYIBgAAAA==.Jibbage:BAAANQAECgQIBAABNQAECgkJMAAcAHskAA==.Jinkala:BAAANQABCgYICgAAAA==.Jitzakkal:BAACNQAFFH8aAAMBAAcKXSXMBAAoAgABAAUKaSTMBAAoAgAhAAIKyyb+AgDmAAA1AAQKfyUAAyEACQoMJrcKAEwCAAEABwp7JS46AKUCACEABgpkJLcKAEwCAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECn8uAAMSAAoK4SPNBwC8AwASAAoK4SPNBwC8AwADAAEKFhry3ABNAAAAAA==.Joshswims:BAABNQAECn87AAIYAAkK+hnPHABTAgAYAAkK+hnPHABTAgAAAA==.',
Js='Js:BAAANQAECgQIBgAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgoKTQAIACckAA==.Juleita:BAAANQABCgQIBAAAAA==.Jumbojoe:BAAANQAECgIIAgAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kalgard:BAAANQAECgIIAwABNQAECgoKQAADAGYaAA==.Kapena:BAAANQAECggIDwAAAA==.Kardinal:BAABNQAECn9KAAQBAAoKeSXNBQChAwABAAoKeSXNBQChAwAhAAUKuhyPHwBzAQAlAAMKMR9YGACrAAAAAA==.Kargan:BAAANQAECgMIAwABNQAECgYIHAASAIwQAA==.Karliee:BAAANQAECgEIAQABNQAECgIIBgAXAAAAAA==.Karpathous:BAAANQAECggIBwAAAA==.',
Ke='Keladorn:BAABNQAECn89AAISAAoKAiAgMwCJAgASAAoKAiAgMwCJAgAAAA==.Kernsarn:BAAANQAECgcICgABNQAECgoKQQAPAOIYAA==.',
Kh='Khanyiso:BAABNQAECn84AAIMAAoKWxqrDgArAgAMAAoKWxqrDgArAgAAAA==.Kharak:BAABNQAECn8qAAIIAAoKZxyISwAdAgAIAAoKZxyISwAdAgABNQABCgUIBwAXAAAAAA==.Khârnxoxo:BAAANQAECggIBgAAAA==.',
Ki='Kichi:BAAANQAECgEIAQAAAA==.Kichii:BAAANQAECgYIEwAAAA==.Kiellan:BAAANQADCggIDQAAAA==.Kieran:BAABNQAECn9DAAMHAAoKoBQhIgBdAQAHAAgKvg8hIgBdAQAGAAUKzwf2vADjAAAAAA==.Kilsaurys:BAACNQAFFH8KAAMcAAQKlA3CGQCEAAAcAAMKlA3CGQCEAAAnAAEK+gLuFwA2AAA1AAQKfzEABBwACgqXG+QkAKoCABwACgqXG+QkAKoCACcABwqvEoksALgBABMABQqzDds7ANEAAAAA.Kirakishou:BAAANQAECggIBwAAAA==.Kismetard:BAABNQAECn8UAAIEAAoKJA9SVQAKAgAEAAoKJA9SVQAKAgABNQAECgoKKAAbAP0OAA==.Kismete:BAABNQAECn8oAAMbAAoK/Q6PCwCkAQAbAAoK/Q6PCwCkAQAaAAEKAAAPQgAmAAAAAA==.',
Ko='Konstantine:BAABNQAECn8kAAMSAAoKnBpXZwBlAgASAAoKnBpXZwBlAgAMAAUKuBSjPAAOAQAAAA==.',
Kr='Kravnoc:BAAANQADCgcIDQAAAA==.Krittykitkat:BAAANQAECgIIAgABNQAECgYIBwAXAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAABNQAECn8hAAIEAAkKIgaEkwByAQAEAAkKIgaEkwByAQAAAA==.',
La='Lanashamjama:BAAANQAECgIIAgABNQAECgoKLQAnAKEYAA==.Laprimera:BAAANQAECgIIBQAAAA==.Lasticon:BAABNQAECn8aAAIEAAYKBwgJ3QBHAQAEAAYKBwgJ3QBHAQAAAA==.Lazyjade:BAABNQAECn87AAIHAAoKsRuiDwBMAgAHAAoKsRuiDwBMAgAAAA==.',
Le='Lenarius:BAAANQABCgYIBgAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leprechauñ:BAAANQADCgQIBAAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQAECggIAQAAAA==.Lilsnot:BAAANQAECgMIAwAAAA==.',
Lo='Lockofdirish:BAAANQAECgEIAgAAAA==.Lorfirandor:BAAANQADCgYIDAAAAA==.Lorynn:BAABNQAECn9AAAIIAAoK1h/8KgCIAgAIAAoK1h/8KgCIAgAAAA==.',
Ma='Maches:BAABNQAECn8ZAAMBAAYK3QeLwwC3AAABAAYK3QeLwwC3AAAhAAEKWgfvOgAiAAAAAA==.Macready:BAAANQAECgQIAgAAAA==.Madwe:BAABNQAECn8qAAMOAAoK0BAdJgCbAQAOAAkKTBAdJgCbAQAYAAMKNg/VeACvAAAAAA==.Magturri:BAABNQAECn89AAMEAAoKLB2fQwCgAgAEAAkKhh6fQwCgAgACAAMKcw3yegBWAAAAAA==.Magvara:BAAANQAECggIDwAAAA==.Majìkstik:BAAANQAECgEIAQAAAA==.Mamameatmode:BAAANQAECgYICgAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCggIKgAAAA==.Maxfrogpower:BAAANQADCggIFAAAAA==.Maxsunward:BAABNQAECn8dAAIMAAYKux4EJQC4AQAMAAYKux4EJQC4AQAAAA==.',
Me='Meepasaurus:BAABNQAECn86AAIfAAoKMyJNBgCMAgAfAAoKMyJNBgCMAgAAAA==.Megaforce:BAAANQAECgEIAwAAAA==.Mellky:BAABNQAECn87AAImAAoK9SP+AgCHAwAmAAoK9SP+AgCHAwAAAA==.Metanoia:BAABNQAECn8wAAMKAAkKRiI8DAANAwAKAAkKCCA8DAANAwAJAAkKoB9dGQCyAgABNQAECgoKSgABAHklAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEBNQAECn8oAAMOAAoK3xzAJwCbAgAOAAoK3xzAJwCbAgAPAAEKKRYIjgBHAAABNQAECgoKGAAcAFAPAA==.Mibb:BAEBNQAECn8nAAIIAAkKECHSPwAGAwAIAAkKECHSPwAGAwABNQAECgoKGAAcAFAPAA==.Midnitetrvlr:BAABNQAECn8bAAIOAAkKNw33YwCBAQAOAAkKNw33YwCBAQAAAA==.Migothedruid:BAAANQAECgEIAQAAAA==.Minmew:BAAANQADCgQIBAAAAA==.Mirren:BAABNQAECn8jAAIVAAkKMhThCwAAAgAVAAkKMhThCwAAAgAAAA==.Missmoans:BAAANQAECgQIBQABNQAECgoKIQASAD4RAA==.Mizeeri:BAAANQADCgQIBAAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Molyporph:BAAANQAECgEIAQAAAA==.Momojojo:BAABNQAECn8lAAIhAAkKohrkAgAjAwAhAAkKohrkAgAjAwAAAA==.Monre:BAAANQAECgMIBgABNQAECggIEwAXAAAAAA==.Moojito:BAAANQAECgUIBQAAAA==.Moonflame:BAACNQAFFH8GAAIGAAIK6xgEJwCUAAAGAAIK6xgEJwCUAAA1AAQKfzAAAgYACgrYG7MxAKECAAYACgrYG7MxAKECAAAA.Mooriah:BAABNQAECn8vAAIcAAoKIwUXYABPAQAcAAoKIwUXYABPAQAAAA==.Mordekhuul:BAABNQAECn81AAIBAAoK2B1hJgDrAgABAAoK2B1hJgDrAgAAAA==.Moserr:BAAANQAECgEIAQAAAA==.Motowa:BAAANQAECgIIBgAAAA==.Mournhide:BAAANQAECggIEAAAAA==.',
Mp='Mpkshaman:BAACNQAFFH8FAAQiAAMKgBZWBQCdAAAiAAMKgBZWBQCdAAANAAEKvgeqMQBHAAAFAAEKHBMeLQA7AAA1AAQKfygABCIACgp1HfgJAG4CACIACQpBG/gJAG4CAA0ACApDGQFCAG0CAAUAAQo+C3cVAT8AAAAA.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECgkJHgAiANoGAA==.Mynchus:BAABNQAECn8eAAMiAAkK2gbtHgBxAQAiAAkKLAbtHgBxAQANAAUK/ANUvQB8AAAAAA==.Myrtne:BAAANQAECgIIAQAAAA==.Mysterydh:BAABNQAECn8tAAIdAAoK4x8bAwDKAgAdAAoK4x8bAwDKAgAAAA==.Mysterypala:BAAANQAECgcIEwAAAA==.Mysteryvoke:BAABNQAECn8oAAIZAAoKdCOuCwDpAgAZAAoKdCOuCwDpAgAAAA==.Mystodin:BAAANQAECggIEQAAAA==.Myztic:BAAANQADCgEIAQAAAA==.',
['Mä']='Mälförmïtÿ:BAAANQAECgcIBgAAAA==.',
Na='Naneko:BAABNQAECn8YAAMIAAcKpQSpSwERAQAIAAYKOQSpSwERAQAVAAEKwAaQPgAsAAAAAA==.',
Ne='Neelix:BAABNQAECn8qAAMEAAoKDQngkgDjAQAEAAoKDQngkgDjAQACAAUK+gHaZgCQAAAAAA==.Nehi:BAAANQAECggICgAAAA==.Neotahr:BAABNQAECn8/AAICAAoKsg/gGQCiAQACAAoKsg/gGQCiAQAAAA==.Nestli:BAAANQAECgYIBgAAAA==.Neuron:BAEANQABCgUICgABNQAECgIICwAXAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECn8/AAIEAAoK6RQWWwD7AQAEAAoK6RQWWwD7AQAAAA==.Nitehunter:BAABNQAECn8pAAIEAAoKDA0jWQAAAgAEAAoKDA0jWQAAAgAAAA==.',
No='Noobert:BAABNQAECn80AAITAAoKTBdtEQAMAgATAAoKTBdtEQAMAgAAAA==.Novademic:BAAANQAECgUIEQAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAgAAAA==.',
Of='Offseason:BAAANQADCgYIBgAAAA==.',
Og='Ognikkay:BAACNQAFFH8GAAIWAAQKugziAQDGAAAWAAQKugziAQDGAAA1AAQKf0AAAhYACgppIUQFALYCABYACgppIUQFALYCAAAA.',
Ok='Okboomer:BAAANQADCgUIBQABNQAECgkJMAAcAHskAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.Orcpriest:BAAANQAECgQICQABNQAECgoKJAAOANAXAA==.',
Oy='Oyakev:BAAANQAECgEIAQAAAA==.Oyea:BAABNQAECn8UAAMTAAgKWxSJIQBfAQATAAcKKROJIQBfAQAcAAQKbAr6XQCZAAABNQAECgoKOwAHALEbAA==.',
Pa='Pabiloneta:BAAANQAECgYIDwABNQAECgkJHQAJAJ4bAA==.Pakami:BAAANQAECgYIBgAAAA==.Pallyana:BAABNQAECn9AAAISAAoKUx7ENwB3AgASAAoKUx7ENwB3AgAAAA==.Palosdin:BAABNQAECn8WAAISAAcKKwdj+wDbAAASAAcKKwdj+wDbAAAAAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQAECgQICAABNQAECgYIDwAXAAAAAA==.Pass:BAAANQAECggIDwABNQAECgoKMgAQALokAA==.',
Pe='Perridan:BAAANQAECggICAAAAA==.',
Ph='Phalandrel:BAABNQAECn8cAAIEAAoKBRaqcgAsAgAEAAoKBRaqcgAsAgAAAA==.Phewphew:BAAANQAECgMIBgAAAA==.Phiora:BAAANQAECgEIAQABNQAECgUICwAXAAAAAA==.',
Pi='Pinkponyclub:BAABNQAECn9GAAIDAAoKxhyCIQDnAgADAAoKxhyCIQDnAgAAAA==.Pinkyshock:BAABNQAECn9nAAIMAAoKWB79CQD8AgAMAAoKWB79CQD8AgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICQAXAAAAAA==.Portholes:BAABNQAECn8eAAIIAAgKJRlidACzAQAIAAgKJRlidACzAQAAAA==.',
Pr='Praystatiøn:BAAANQAECgcIDAAAAA==.',
Ps='Psyop:BAABNQAECn8dAAIFAAkK+BzmHgDvAgAFAAkK+BzmHgDvAgAAAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAABNQAECn8cAAIlAAkKzxuzBQBhAgAlAAkKzxuzBQBhAgABNQAFFAcIGAAQAA0fAA==.Purplod:BAABNQAECn8jAAMYAAkKgQpXTQCCAQAYAAkK2wlXTQCCAQAPAAUKXAhfjwDHAAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
['Pò']='Pòpemz:BAAANQADCgUIBAAAAA==.',
Qi='Qing:BAABNQAECn80AAIjAAoKOB1jCACmAgAjAAoKOB1jCACmAgAAAA==.',
Qy='Qybxboogied:BAABNQAECn8VAAIcAAkKiBB3OwAsAQAcAAkKiBB3OwAsAQAAAA==.Qybxboogies:BAABNQAECn8cAAMGAAkKHhcrPQAxAgAGAAgKhRkrPQAxAgAHAAIKzQWUaABfAAAAAA==.Qybxboogyy:BAAANQAECggIDQAAAA==.',
Ra='Raensong:BAABNQAECn8fAAMSAAoKShD3fQC8AQASAAoKShD3fQC8AQAMAAMKawdqRwB1AAAAAA==.Rafterman:BAAANQAECgQIBAAAAA==.Rainingarrow:BAAANQAECgYICwAAAA==.Raisa:BAABNQAECn9MAAMBAAoKniMsGwCgAgABAAoKgiMsGwCgAgAhAAMK3xpTLwAMAQAAAA==.Rakarum:BAAANQAECgEIAgAAAA==.Rasar:BAABNQAECn8pAAIIAAoKoRV5UQANAgAIAAoKoRV5UQANAgAAAA==.Rathew:BAABNQAECn8YAAMFAAkKeh0YTQAvAgAFAAgKKR4YTQAvAgANAAMK7AZPygBnAAAAAA==.Rawnext:BAABNQAECn8ZAAIIAAgKNxgbfwCZAQAIAAgKNxgbfwCZAQABNQAFFAQIBgARANsOAA==.',
Re='Renaitiaalaa:BAAANQAECgUICAAAAA==.Renei:BAABNQAECn8cAAMKAAcK1xv5QADhAQAKAAcK1xv5QADhAQAJAAMK2wk5QwB6AAABNQAECgkJMAAFAMwiAA==.Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECn9OAAQEAAkKxxNmVAB0AgAEAAkKIhNmVAB0AgACAAcKUA6UPQBmAQAoAAIK6g8KEAB/AAAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAACNQAFFH8GAAIGAAQKNxSxFgAwAQAGAAQKNxSxFgAwAQA1AAQKfzYAAwYACgp9JHgEAKkDAAYACgp9JHgEAKkDAAsABQqwIo0IANsBAAAA.',
Ro='Rollo:BAAANQADCgQIBAABNQAECgkJMAAcAHskAA==.Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECggICwAAAA==.Rox:BAAANQAECgcIEgAAAA==.Royal:BAAANQADCgcIDAAAAA==.Royle:BAAANQAECgMIAgAAAA==.Roysham:BAAANQAECgQICQAAAA==.Roywar:BAAANQAECgEIAgAAAA==.',
Ru='Rubiks:BAAANQAECggIAQAAAA==.',
['Ré']='Réîgn:BAABNQAECn8pAAIOAAoK0xTjGgD8AQAOAAoK0xTjGgD8AQAAAA==.',
Sa='Sacrus:BAABNQAECn8cAAISAAYKjBD02AATAQASAAYKjBD02AATAQAAAA==.Santoss:BAAANQADCgQIBAAAAA==.Sarah:BAABNQAECn8YAAMCAAkKZyFlFAC8AgACAAkKZyFlFAC8AgAEAAEKcxB0UgFAAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAXAAAAAA==.Scksattankin:BAAANQADCgEIAQAAAA==.Scoobear:BAAANQAECggIEQABNQAECgoKLQASAFgWAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQAECgQIBgAAAA==.Senjougahara:BAACNQAFFH8aAAIYAAcKnxysAgAYAgAYAAcKnxysAgAYAgA1AAQKf0wAAhgACgqNJaMEAE0DABgACgqNJaMEAE0DAAAA.Seriyah:BAACNQAFFH8TAAIWAAQKVhaCAQDkAAAWAAQKVhaCAQDkAAA1AAQKfzoAAhYACgqoHbYHAOICABYACgqoHbYHAOICAAAA.Serph:BAABNQAECn8hAAQSAAoKPhGfqQBlAQASAAkKKBGfqQBlAQAMAAYKMBGSSADLAAADAAQKUA9VrgCuAAAAAA==.',
Sh='Shabane:BAABNQAECn89AAIjAAkK9B3xBABMAgAjAAkK9B3xBABMAgAAAA==.Shame:BAABNQAECn8yAAIHAAkKxRf4FwCVAgAHAAkKxRf4FwCVAgAAAA==.Shankey:BAAANQAECgYIAQAAAA==.Shiminy:BAAANQAECgMIBAAAAA==.Shinobi:BAABNQAECn8iAAIQAAoKaBN8LQCtAQAQAAoKaBN8LQCtAQAAAA==.Shiol:BAAANQAECgMIAwABNQAECgcIEgAXAAAAAA==.Shirls:BAABNQAECn8iAAIDAAkK3hrsNQCMAgADAAkK3hrsNQCMAgAAAA==.Shivak:BAABNQAECn9DAAIbAAoKLhXOBACuAgAbAAoKLhXOBACuAgAAAA==.Shivanie:BAABNQAECn8gAAIDAAoKchg/IACsAgADAAoKchg/IACsAgAAAA==.Shock:BAAANQAECgQIDAAAAA==.Shredderella:BAABNQAECn8jAAIJAAkKTh2WJABkAgAJAAkKTh2WJABkAgAAAA==.Shrug:BAABNQAECn8gAAIgAAkK+BSOfgAeAgAgAAkK+BSOfgAeAgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAXAAAAAA==.',
Si='Siccem:BAAANQAECgIIAgAAAA==.Sicwiddit:BAABNQAECn8iAAIEAAkKJxCPbwDGAQAEAAkKJxCPbwDGAQAAAA==.Sinadin:BAAANQADCgQIBAABNQAECgkJMAAcAHskAA==.Sinsha:BAAANQADCgUIBQABNQAECgkJMAAcAHskAA==.',
Sk='Skeeda:BAABNQAECn8VAAInAAYK8RM8OQAZAQAnAAYK8RM8OQAZAQAAAA==.Skylinex:BAABNQAECn8nAAIKAAoK1BfcFABAAgAKAAoK1BfcFABAAgAAAA==.Skylinez:BAAANQAECgUICwAAAA==.Skïttles:BAABNQAECn8sAAQnAAgKJxdHKgDMAQAnAAgKJxdHKgDMAQAcAAMKpQS3tAAuAAATAAIKzwNhdgAfAAABNQAECgoKIQASAD4RAA==.',
Sl='Sleezball:BAABNQAECn8hAAISAAoKJhJukQACAgASAAoKJhJukQACAgAAAA==.Sloppyslice:BAAANQAECgEIAQAAAA==.',
So='Softie:BAAANQAECgIIAgABNQAECgkJJwAgAGAbAA==.Sonictide:BAAANQAECgYIEAAAAA==.Soulscream:BAABNQAECn8nAAIGAAkKyB9vFwAaAwAGAAkKyB9vFwAaAwAAAA==.',
Sp='Spaghetto:BAABNQAECn82AAIcAAoKGRjwIADGAgAcAAoKGRjwIADGAgAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECggIEAAAAA==.',
Su='Suzel:BAAANQAECgUIBAAAAA==.',
Sw='Sweetlips:BAAANQAECgMIAQAAAA==.Swiftyninja:BAABNQAECn8hAAIJAAoKGxXUCQAxAgAJAAoKGxXUCQAxAgABNQAECgoKQgAMALsdAA==.',
Sy='Sydaria:BAAANQABCgMIAwAAAA==.Synder:BAABNQAECn8wAAIbAAoKWQY5DgBkAQAbAAoKWQY5DgBkAQAAAA==.',
Ta='Tainin:BAABNQAECn8wAAIFAAkKzCIsGADhAgAFAAkKzCIsGADhAgAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAgAAAA==.Tarynna:BAABNQAECn86AAIBAAkK0hBgWgCxAQABAAkK0hBgWgCxAQAAAA==.Tazdingobomb:BAABNQAECn8XAAINAAoK3hA2NwDjAQANAAoK3hA2NwDjAQAAAA==.Tazerface:BAABNQAECn84AAMVAAoKrQ/0DgC7AQAVAAoKrQ/0DgC7AQAIAAYK7gPiWwH5AAAAAA==.',
Te='Techjacket:BAAANQADCgQIBAAAAA==.Tekin:BAABNQAECn9AAAIDAAoKZhpgKwBpAgADAAoKZhpgKwBpAgAAAA==.Teleprompter:BAAANQAECgYIDwAAAA==.Telrissan:BAABNQAECn8nAAIIAAoKxB6YZQCzAgAIAAoKxB6YZQCzAgAAAA==.Tenkawnor:BAABNQAECn8UAAIcAAkK4QltTQDWAAAcAAkK4QltTQDWAAAAAA==.Tenyroldemon:BAABNQAECn82AAQdAAoKeiGoBAD3AgAdAAoKeiGoBAD3AgARAAMKvwioQQCLAAAeAAIK9hEAAAAAAAAAAA==.Tenzingyatso:BAAANQADCgYICgAAAA==.Tero:BAAANQADCgIIAgAAAA==.',
Th='Thald:BAABNQAECn82AAIjAAoK2xrwBABMAgAjAAoK2xrwBABMAgAAAA==.Thaznotmilk:BAAANQAECgYIBgAAAA==.Thxowlbama:BAAANQAECgMIAQABNQAECgoKHAADANgbAA==.',
Ti='Timzilla:BAAANQAECgUIBQABNQAECggICQAXAAAAAA==.Tinylight:BAAANQADCgQIBAAAAA==.Tinytip:BAAANQADCggIDgAAAA==.Tisakna:BAABNQAECn9NAAQIAAoKJyRVRAD7AgAIAAkK1yJVRAD7AgAVAAMKiiP7GgAbAQAUAAEKeR9iCQBbAAAAAA==.Titanus:BAAANQAECgEIAQAAAA==.',
To='Togon:BAAANQAECggICAAAAA==.Tooezy:BAAANQAECgQICQAAAA==.Tool:BAAANQAECgUICwAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAABNQAECn8aAAIJAAkKpheIOgDpAQAJAAkKpheIOgDpAQABNQAECgoKQQAMAPMeAA==.Trask:BAABNQAECn8jAAIIAAkKZRYcuQARAgAIAAkKZRYcuQARAgAAAA==.Trishalle:BAAANQADCgQIBAABNQAECgoKKwAcAFwTAA==.Trogdoor:BAAANQAECgUIBgAAAA==.Trokom:BAACNQAFFH8RAAMIAAcKUyZCCQA0AgAIAAYKQyZCCQA0AgAVAAEKkiZZCQBzAAA1AAQKfzsAAggACgr5JmUCAOgDAAgACgr5JmUCAOgDAAE1AAUUBwoRAAgAUyYA.Trokopally:BAAANQAECgYIBgABNQAFFAcKEQAIAFMmAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECn8xAAMBAAoKkguFawCBAQABAAoKkguFawCBAQAhAAMK6wcwUgCIAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggIEAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECn8gAAMQAAkKwRzHGQB0AgAQAAkKwRzHGQB0AgAjAAEKyARwMwAoAAAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgoKTAAnAJMTAA==.Vandermark:BAABNQAECn9MAAUnAAoKkxMJHQBLAgAnAAkKjhMJHQBLAgATAAoK/RKxFADbAQAWAAUKohQYHgArAQAcAAQK1QsDggDIAAAAAA==.Varuna:BAAANQAECgcIDwABNQAECgoKNgAYABUlAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIEAAAAA==.Victus:BAAANQAECgYIBwAAAA==.Vidrus:BAAANQAECggICgAAAA==.Vilkas:BAACNQAFFH8IAAIHAAUKxh73BwCRAQAHAAUKxh73BwCRAQA1AAQKfx4AAgcACgotIc8JAEQDAAcACgotIc8JAEQDAAE1AAQKCgotABEAyCQA.Viserion:BAAANQADCgYIEgAAAA==.',
Vu='Vulpinor:BAAANQAECgEIAQAAAA==.',
Wa='Waddledoo:BAABNQAECn8gAAIFAAgKkx+rLgCnAgAFAAgKkx+rLgCnAgAAAA==.Warmaku:BAABNQAECn8dAAInAAgKNh48HABUAgAnAAgKNh48HABUAgAAAA==.',
We='Webz:BAAANQAECgIIBAAAAA==.Weezybaby:BAAANQAECgQIBAAAAA==.',
Wh='Whïteoak:BAACNQAFFH8JAAInAAQKIwekCwDdAAAnAAQKIwekCwDdAAA1AAQKfy0AAicACgpcHJsQANECACcACgpcHJsQANECAAAA.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECn8dAAIPAAkKxx/8GADlAgAPAAkKxx/8GADlAgAAAA==.Xanyp:BAAANQAECgEJBQABNQAECgkJHQAPAMcfAA==.',
Xe='Xeletath:BAAANQAECgYIDAAAAA==.Xerg:BAAANQAECgEIAQABNQAECgoKNAAjADgdAA==.',
Xi='Xinaveruk:BAAANQAECggIEQAAAA==.',
Xo='Xoro:BAAANQAECgQICgAAAA==.',
Xr='Xrxyz:BAABNQAECn8bAAMSAAkKNAqN+ADgAAASAAkKJAqN+ADgAAAMAAIKtwPmbgAYAAAAAA==.',
Xs='Xshamster:BAACNQAFFH8HAAIFAAIKExH0IQB9AAAFAAIKExH0IQB9AAA1AAQKf1gAAwUACgoIGRQrALYCAAUACgoIGRQrALYCAA0AAQoAAPcxATcAAAAA.',
Ye='Yen:BAAANQADCgMIAwAAAA==.Yewna:BAABNQAECn8WAAIGAAkK8xmRLQB7AgAGAAkK8xmRLQB7AgABNQAECgoKRAAFAKwkAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAgAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAPAMcfAA==.Zau:BAABNQAECn8iAAQlAAgKwh3DBgA7AgAlAAcKXiDDBgA7AgABAAQKexND8ADqAAAhAAIK1g/dHQBxAAAAAA==.',
Ze='Zed:BAABNQAECn8cAAIRAAoKPxjkEQAuAgARAAoKPxjkEQAuAgABNQAECgoKMgAQALokAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAFFAQIDgAIAGMfAA==.Zolja:BAABNQAECn8VAAMhAAgKvwdoHQByAAABAAUK7AX/BQHAAAAhAAQKkwloHQByAAAAAA==.Zoney:BAAANQAECgIIAwAAAA==.Zordlon:BAAANQAECgYIEwAAAA==.',
Zu='Zukem:BAABNQAECn8nAAIEAAoKNB6vNADNAgAEAAoKNB6vNADNAgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgYIDAABNQAECgcIEgAXAAAAAA==.',
Zy='Zyariah:BAAANQADCggIFQAAAA==.Zyvea:BAABNQAECn83AAIgAAoKlBi0SwCmAgAgAAoKlBi0SwCmAgAAAA==.',
['Çr']='Çrossblesser:BAAANQAECgEIAQAAAA==.',
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
