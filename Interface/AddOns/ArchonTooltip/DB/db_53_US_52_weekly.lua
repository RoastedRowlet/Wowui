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

local lookup = {'Warlock-Demonology','Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Paladin-Protection','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Retribution','Monk-Windwalker','Druid-Guardian','Mage-Fire','Mage-Frost','Druid-Feral','Unknown-Unknown','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warrior-Arms','Warlock-Destruction','Shaman-Enhancement','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction','Druid-Restoration','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acidsword:BAACNQAFFH8FAAIBAAIKEhGFIQCNAAABAAIKEhGFIQCNAAA1AAQKfysAAgEACQrfHG81ALUCAAEACQrfHG81ALUCAAE1AAUUBggNAAIAcxkA.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQAECgUIBQABNQAFFAQICwADALofAA==.Adrua:BAAANQAECgYIBwAAAA==.Adym:BAABNQAECn8kAAIEAAoK7BM7fQATAgAEAAoK7BM7fQATAgAAAA==.',
Ag='Agave:BAABNQAECn9JAAIFAAoKRhTDMQAmAgAFAAoKRhTDMQAmAgAAAA==.',
Ai='Aiyah:BAAANQAECgQICAAAAA==.',
Al='Altarboi:BAABNQAECn8jAAMGAAgKMSNDEwATAwAGAAgKMSNDEwATAwAHAAEKKgXZeQA0AAAAAA==.Alüçard:BAABNQAECn8rAAIIAAcK2w7toQA0AQAIAAcK2w7toQA0AQAAAA==.',
Am='Amoraniel:BAABNQAECn8rAAIIAAoKgxrwbwCeAgAIAAoKgxrwbwCeAgAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAABNQAECn8bAAMJAAkKnhuLIgByAgAJAAkKMBuLIgByAgAKAAMKsBgCcgD7AAAAAA==.Andresra:BAABNQAECn8rAAIIAAkKuiBrZwCvAgAIAAkKuiBrZwCvAgABNQAECgkJGwAJAJ4bAA==.Anie:BAAANQADCgQIBAAAAA==.Annaluna:BAAANQAECgEIAQAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAABNQAECn8hAAMGAAoK0xZGKwBmAgAGAAoKvxVGKwBmAgALAAQKGwqKFwC5AAAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
As='Asrael:BAAANQAECggIEAABNQAECgoKNwAMAFsaAA==.Asterin:BAAANQADCggIDgAAAA==.',
Au='Audersi:BAAANQADCgQIBQAAAA==.Augtism:BAAANQAECgIIAgABNQAECgoKGwADANgbAA==.Aunumator:BAAANQADCgYIBgAAAA==.',
Av='Avâtre:BAABNQAECn8jAAINAAkKnxh6WwAQAgANAAkKnxh6WwAQAgAAAA==.',
Az='Azlea:BAAANQAECgcIBwAAAA==.',
Ba='Baguette:BAAANQAECgYIDQAAAA==.Bajingobomb:BAABNQAECn9AAAMOAAoK/B/VDQB3AgAOAAoKxR/VDQB3AgAPAAYKER19SwDJAQAAAA==.Bajisil:BAAANQAECgUICAABNQAECgoKQAAOAPwfAA==.Bakblood:BAAANQABCgYICgAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEIAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgYIDQAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAAANQAECgYIEgAAAA==.',
Be='Be:BAABNQAECn8wAAIGAAcKfx5JOAAkAgAGAAcKfx5JOAAkAgAAAA==.Beckyoncé:BAABNQAECn8/AAIQAAoKwSKJBACMAwAQAAoKwSKJBACMAwAAAA==.Bedris:BAABNQAECn8qAAQMAAoKJBOLIwDFAQAMAAcKFReLIwDFAQARAAoKEwzPoABLAQADAAEKXQK/NwEfAAAAAA==.Beerticus:BAABNQAECn8yAAISAAcKvhxGHQBMAgASAAcKvhxGHQBMAgAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECn8cAAITAAkKthkAEABgAgATAAkKthkAEABgAgAAAA==.Binggles:BAACNQAFFH8vAAQIAAgKgyEIAgDcAgAIAAgKvh8IAgDcAgAUAAQK4RdBAAADAQAVAAIKiyXlAwDaAAA1AAQKfzQAAxQACgpNJoMAAO0CAAgACgqdJdIgAFcDABQACAr9JIMAAO0CAAAA.',
Bl='Blacksheep:BAAANQAECgMIAgAAAA==.Blazze:BAAANQAECgUIDgABNQAECgoKLAAEAEMfAA==.Blôôðhôôf:BAAANQADCgQIBAABNQAECgoKHgAWAHAOAA==.',
Bo='Boaj:BAAANQAECgYIDAAAAA==.Bokinar:BAAANQAECggICwAAAA==.Bomboclaat:BAAANQAECgUIDQABNQAECgoKMQASALokAA==.Boolay:BAABNQAECn8jAAMMAAoKyhxhHwDqAQAMAAcKNx1hHwDqAQARAAcKwBGOwwAOAQABNQABCgUIBQAXAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQAECgYICwAAAA==.Bootyshotz:BAAANQAECgIIAgABNQAECgoKGAARAD4RAA==.Boozing:BAAANQADCggICgABNQAECgoKNQAEAGkiAA==.Bopstds:BAAANQAECgUIBgAAAA==.Bosmina:BAABNQAECn9GAAIGAAoKUhyVKwBkAgAGAAoKUhyVKwBkAgAAAA==.',
Br='Braei:BAABNQAECn8yAAIDAAgKMRKQcQDDAQADAAgKMRKQcQDDAQAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Breelynn:BAAANQADCggICAAAAA==.Brenhunt:BAAANQAECggIEQAAAA==.Brenmonk:BAABNQAECn8fAAISAAcK8gofNgBkAQASAAcK8gofNgBkAQAAAA==.Brenpriest:BAAANQADCggIDgAAAA==.Brenshammy:BAAANQADCgcIDAAAAA==.Bruenor:BAAANQAECgMIAwAAAA==.Bruucey:BAAANQAECgcIEQAAAA==.',
Bu='Bubblebaddie:BAAANQAECgQIBQAAAA==.Bubblicous:BAAANQAECgcIDAAAAA==.Bugenhagen:BAABNQAECn9EAAIFAAoKrCRfBwCHAwAFAAoKrCRfBwCHAwAAAA==.Butchers:BAAANQAECgUICQAAAA==.Buttpaladin:BAABNQAECn8nAAIRAAgK2BaNkgD/AQARAAgK2BaNkgD/AQAAAA==.',
Ca='Caliden:BAAANQABCgYICwAAAA==.Cardib:BAACNQAFFH8QAAMOAAcKUxssBwCoAQAOAAUKeSIsBwCoAQAYAAMKmhAFDwDqAAA1AAQKfz8AAw4ACgrJJfoGAI4DAA4ACgqrJfoGAI4DABgABArVI+40AJMBAAAA.Cavos:BAABNQAECn8dAAIQAAcKgRuLJwAIAgAQAAcKgRuLJwAIAgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAABNQAECn9BAAIPAAoK4hghFgAxAgAPAAoK4hghFgAxAgAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Cheesen:BAAANQAECgUIBwAAAA==.Chiri:BAECNQAFFH8KAAQZAAUKxAWZBACLAAAZAAMKxAWZBACLAAAaAAMKUgH6FACEAAAbAAEKAABtDQAAAAA1AAQKfyoABBkACgouEwUUAA4CABkACgqxEQUUAA4CABsABArJDo4OAMoAABoAAwoSAyRFAHkAAAAA.Chvngus:BAABNQAECn82AAMRAAoKHB+XLQARAwARAAoKEh+XLQARAwAMAAYK4xifGwBeAQAAAA==.',
Ci='Citizencain:BAABNQAECn8UAAIIAAUKixs9CAF/AQAIAAUKixs9CAF/AQAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMIBwAAAA==.',
Co='Cocheeze:BAAANQAECgcIDQABNQAECgoKJAAOANAXAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEBNQAECn8YAAIcAAoKUA/WNAAwAQAcAAoKUA/WNAAwAQAAAA==.Conmammoth:BAABNQAECn8cAAIRAAgKax7WVwDwAQARAAgKax7WVwDwAQAAAA==.Conquest:BAAANQAECgIIAgAAAA==.Coohwhip:BAAANQAECgIIAQAAAA==.Cornorgan:BAAANQAECggIEwAAAA==.Corèl:BAAANQADCgUIBwAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAABNQAECn8rAAIcAAoKXBMMNQBAAgAcAAoKXBMMNQBAAgAAAA==.Cristobal:BAAANQAECgYIDAAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.Crykthiria:BAAANQAECgEIAQAAAA==.',
Cu='Curaga:BAAANQAECgMIAwAAAA==.Curnsarn:BAAANQAECgYICQABNQAECgoKQQAPAOIYAA==.',
Cy='Cydea:BAAANQAECgQICwAAAA==.',
Da='Dagidan:BAABNQAECn9CAAIdAAoKrRF7DAD/AQAdAAoKrRF7DAD/AQAAAA==.Darktide:BAAANQAECggIEwAAAA==.Dashawmon:BAAANQADCggICAABNQADCgYICQAXAAAAAA==.Dashel:BAAANQAECggIEAABNQAECgoKQwAHAKAUAA==.',
De='Dead:BAAANQADCggICAAAAA==.Deathtoxi:BAAANQAECgIIAQAAAA==.Degey:BAAANQAECggICQAAAA==.Demonsoul:BAAANQADCgQIBAAAAA==.Demontotems:BAAANQAECgIIAgAAAA==.Demotoxi:BAACNQAFFH8GAAIQAAQK2w6DCADBAAAQAAQK2w6DCADBAAA1AAQKfz0ABBAACgpiHt0SANQCABAACgpiHt0SANQCAB4ABApQGWRhAPUAAB0AAgrNCqcsAFEAAAAA.Deriso:BAABNQAECn8fAAMEAAoKjiGILgDiAgAEAAoKeSCILgDiAgACAAMKBhkZYwCdAAAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAXAAAAAA==.Destrozinth:BAABNQAECn8UAAIbAAoKgA3tEAAoAQAbAAoKgA3tEAAoAQAAAA==.Dethorok:BAABNQAECn9IAAIEAAoKFibxAgBwAwAEAAoKFibxAgBwAwAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQADCgYIDQABNQAECgEIAQAXAAAAAA==.',
Dh='Dhedge:BAAANQAECgIIAwAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgoKRAAFAKwkAA==.Dib:BAAANQAECgcIEwAAAA==.Digey:BAABNQAECn8wAAMfAAoKqiHBBAA1AwAfAAoKqiHBBAA1AwAgAAIKoQ8kBAFCAAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAABNQAECn8nAAIhAAoKnwZ7CgDvAAAhAAoKnwZ7CgDvAAAAAA==.',
Do='Dontlookatme:BAAANQAECgEIAQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCggIEwABNQAECgEIAQAXAAAAAA==.',
Dr='Drakbek:BAABNQAECn8eAAITAAcKuht5EwAsAgATAAcKuht5EwAsAgAAAA==.Dreadshot:BAAANQADCgYIBwAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dremaster:BAAANQAECgEIAQAAAA==.Dronebot:BAABNQAECn9rAAMHAAoK2BzMDgAEAwAHAAoK2BzMDgAEAwAGAAEK8wvN2QA8AAAAAA==.Drucifer:BAAANQADCggIFwAAAA==.',
Du='Dud:BAAANQAECgYICAABNQAECgkJGAAFAHodAA==.Dumbrouge:BAAANQAECgIIAgABNQAECgoKNwAMAFsaAA==.Durros:BAABNQAECn8oAAIFAAoKrBjXMgAhAgAFAAoKrBjXMgAhAgAAAA==.Durto:BAAANQABCgEIAQAAAA==.Dustyshotz:BAAANQAECgYICQAAAA==.',
Dy='Dyhanna:BAAANQAECggIBwAAAA==.',
Eb='Eboger:BAAANQAECgMIAgAAAA==.',
Eg='Egam:BAAANQAECgUIBQAAAA==.',
El='Elunelphie:BAAANQAECgYIBwAAAA==.',
Em='Embody:BAABNQAECn8iAAIcAAkKIQweVwB6AQAcAAkKIQweVwB6AQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECn8nAAIRAAoKDBxIWQCLAgARAAoKDBxIWQCLAgAAAA==.',
Er='Erasmas:BAACNQAFFH8LAAIDAAQKuh8GCgB2AQADAAQKuh8GCgB2AQA1AAQKf1gABAMACgrsJGYGAJkDAAMACgrsJGYGAJkDABEACQpwHwQyAG8CAAwAAgoVIJE2AKkAAAAA.Erasmos:BAAANQAECgYIBgABNQAFFAQICwADALofAA==.Erzascarlét:BAABNQAECn9CAAIMAAoKux1CCwDlAgAMAAoKux1CCwDlAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAABNQAECn8kAAIOAAoK0BcMEQBLAgAOAAoK0BcMEQBLAgAAAA==.Eviltotems:BAABNQAECn8fAAINAAoKBBb5KQACAgANAAoKBBb5KQACAgABNQAECgoKJAAOANAXAA==.Eviscration:BAAANQADCgIIAgABNQADCgcICAAXAAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Ez='Ezyy:BAAANQAECgQICAAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECn9GAAQNAAoKVB9bGwAlAwANAAoKVB9bGwAlAwAFAAYKxA2DeAAWAQAiAAMKRwnbIwCzAAAAAA==.Fantasma:BAAANQAECgEIAQAAAA==.',
Fe='Fear:BAAANQAECgIIBAAAAA==.',
Fi='Findal:BAAANQAECgUIBQABNQABCgUIBwAXAAAAAA==.Fistymoo:BAEANQAECgIIAgABNQAFFAUICgAZAMQFAA==.Fivemagics:BAABNQAECn82AAMBAAoK4BYeZAAtAgABAAkKEhceZAAtAgAhAAIKERUjHABtAAAAAA==.',
Fl='Flayvour:BAAANQAECgIIAgABNQAECgoKMwAjALMcAA==.Fleaboy:BAABNQAECn8XAAMkAAgKHhG2CQDqAQAkAAgKHhG2CQDqAQAKAAEKSwShUQA6AAAAAA==.Flist:BAABNQAECn8xAAISAAoKuiSKAwCeAwASAAoKuiSKAwCeAwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAABNQAECn8mAAMIAAoKNRU6egCIAQAIAAoKiBI6egCIAQAVAAIKFh27KwCdAAAAAA==.Foote:BAAANQAECggICAABNQAFFAUIEAAaAJsHAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAABNQAECn8jAAIHAAkKnBTKJwDsAQAHAAkKnBTKJwDsAQAAAA==.Freesia:BAAANQAECgIIAgAAAA==.Fruitjuice:BAABNQAECn8aAAIhAAgKWA7UCAAQAQAhAAgKWA7UCAAQAQAAAA==.',
Fu='Furrios:BAAANQADCggIDgAAAA==.',
Fx='Fxce:BAACNQAFFH8HAAIKAAQKdAOPFACwAAAKAAQKdAOPFACwAAA1AAQKfy0AAgoACgpZFAMrABwCAAoACgpZFAMrABwCAAAA.',
['Fâ']='Fâmine:BAAANQAECgcIDgABNQAECgoKJQAOAJsTAA==.',
Ga='Gaothan:BAAANQAECgcICgAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECn82AAIeAAoKPxUtGwD+AQAeAAoKPxUtGwD+AQAAAA==.',
Gl='Glaiven:BAABNQAECn8hAAIQAAkKaRNbKwDnAQAQAAkKaRNbKwDnAQAAAA==.Glasscleaner:BAABNQAECn8cAAIDAAoKFSL+CgBwAwADAAoKFSL+CgBwAwABNQAFFAcIGgAaAPccAA==.Glenmorangie:BAABNQAECn8rAAMLAAoKEx+yBAB4AgALAAgKkB2yBAB4AgAHAAgKXh8HFgDDAQAAAA==.',
Gn='Gnartusk:BAABNQAECn82AAIPAAgKayBtIACwAgAPAAgKayBtIACwAgAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgUICgAXAAAAAA==.',
Gr='Grawlso:BAAANQADCgYIBgAAAA==.Greens:BAABNQAECn9EAAIcAAoK+R4nDQCxAgAcAAoK+R4nDQCxAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAXAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgQIBwABNQAECgYIDQAXAAAAAA==.Grïma:BAACNQAFFH8GAAMlAAQKLAlJAgDKAAAlAAMKLAlJAgDKAAABAAIKWgWQNAAAAAA1AAQKfzoAAyUACgqQGkgEAJwCACUACgqQGkgEAJwCAAEABApPEkDPAIQAAAAA.',
Gs='Gsus:BAAANQADCggICAABNQAECgoKMwAjALMcAA==.',
Gu='Gueritestje:BAABNQAECn89AAIMAAoKfiBaBwCxAgAMAAoKfiBaBwCxAgAAAA==.Guzzlord:BAABNQAECn8hAAQaAAkKJwibJwB7AQAaAAkKJwibJwB7AQAZAAQKQQZFLQC2AAAbAAQKbQdeGQCnAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAQABNQAECgoKIwAEAKMSAA==.Handsomejack:BAAANQAECgEIAgABNQAECgoKQAAOAPwfAA==.Hanekawa:BAAANQAECggIAwABNQAFFAMICAAEAAIVAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAXAAAAAA==.',
Hb='Hboozing:BAABNQAECn81AAMEAAoKaSJ4EwBRAwAEAAoKaSJ4EwBRAwACAAEKkxI+gwA8AAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Healynn:BAAANQAECgIIAgAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAXAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Himootation:BAAANQADCgQIBAAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitodh:BAAANQAECgUIBQABNQAECgoKMAAYABUlAA==.Hitoshura:BAABNQAECn8wAAMYAAoKFSXZBgB2AwAYAAoK3STZBgB2AwAOAAcK+iQjGwDpAgAAAA==.Hittnrunn:BAAANQAECgEIAQAAAA==.',
Hk='Hkia:BAAANQAECgEIAgAAAA==.',
Ho='Holyginger:BAABNQAECn8VAAMRAAcKIhUjvAClAQARAAYKUBgjvAClAQADAAEKfhQt1wA8AAAAAA==.Holyglizzy:BAABNQAECn8kAAIRAAoKuBX2lQD3AQARAAoKuBX2lQD3AQAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.Holytoxi:BAAANQADCgEIAQABNQAFFAQIBgAQANsOAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcJEgABNQAFFAcIGgAaAPccAA==.',
Ic='Ichtaca:BAAANQADCgEIAQAAAA==.',
Ik='Ikiryo:BAEANQAECgIIBgAAAA==.',
Im='Imtuggdup:BAABNQAECn8yAAMIAAoKiSGxNwAZAwAIAAoKiSGxNwAZAwAVAAMKtxjQIAChAAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Indra:BAAANQAECgEIAQAAAA==.Infidel:BAABNQAECn8wAAIcAAkKeyRcBgCiAwAcAAkKeyRcBgCiAwAAAA==.Invert:BAAANQAFFAEIAQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgMIBQAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irayne:BAAANQADCgQIBAAAAA==.Irisharcher:BAAANQAECggICwAAAA==.Irishbeauty:BAAANQAECgQIBAAAAA==.Irishfury:BAAANQADCgcICQAAAA==.Irishman:BAAANQAECggIDgAAAA==.',
Is='Isengardd:BAAANQAECgEIAQAAAA==.',
It='Itazki:BAABNQAECn9AAAMWAAoKYSMfAgAfAwAWAAoKYSMfAgAfAwAcAAEKHQw7gwAoAAAAAA==.',
Ja='Jackpot:BAAANQAECgIIBAAAAA==.Jaft:BAAANQADCgYIEAAAAA==.Jalter:BAACNQAFFH8aAAIaAAcK9xxoBAAyAgAaAAcK9xxoBAAyAgA1AAQKfzEAAhoACgpgIhEEAHIDABoACgpgIhEEAHIDAAAA.Janha:BAAANQADCggIDwAAAA==.',
Je='Jediknight:BAAANQAECgQIBAAAAA==.Jenga:BAAANQAECgcIDAAAAA==.Jergal:BAABNQAECn8fAAIgAAoK5AtVhQBEAQAgAAoK5AtVhQBEAQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAACNQAFFH8IAAMRAAQKfgWZFgCxAAARAAMKfgWZFgCxAAADAAIK1QT/GwBvAAA1AAQKf0MAAxEACgpTFg18ADICABEACgpTFg18ADICAAMACgp8DcJAAN4BAAAA.',
Ji='Ji:BAAANQADCgYIBgAAAA==.Jibbage:BAAANQAECgQIBAABNQAECgkJMAAcAHskAA==.Jimjones:BAAANQAECgEIAQAAAA==.Jinkala:BAAANQABCgYICgAAAA==.Jitzakkal:BAACNQAFFH8aAAMBAAcKXSXMBAAoAgABAAUKaSTMBAAoAgAhAAIKyyb+AgDmAAA1AAQKfyUAAyEACQoMJrcKAEwCAAEABwp7JS46AKUCACEABgpkJLcKAEwCAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECn8uAAMRAAoK4SPNBwC8AwARAAoK4SPNBwC8AwADAAEKFhr+zgBNAAAAAA==.Joshswims:BAABNQAECn80AAIYAAkKdxmRGwA6AgAYAAkKdxmRGwA6AgAAAA==.',
Js='Js:BAAANQAECgQIBgAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgoKTAAIAPMjAA==.Juleita:BAAANQABCgQIBAAAAA==.Jumbojoe:BAAANQAECgIIAgAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kalgard:BAAANQAECgMIAwABNQAECgoKQAADAGYaAA==.Kapena:BAAANQAECggIDwAAAA==.Kardinal:BAABNQAECn9KAAQBAAoKeSXLAwBNAwABAAoKeSXLAwBNAwAhAAUKuhyPHwBzAQAlAAMKMR9TFACtAAAAAA==.Kargan:BAAANQAECgMIAwABNQAECgYIEwAXAAAAAA==.Karliee:BAAANQADCggICAABNQAECgIIAgAXAAAAAA==.Karpathous:BAAANQAECggIBwAAAA==.',
Ke='Keladorn:BAABNQAECn85AAIRAAkK8x9TSAC8AgARAAkK8x9TSAC8AgAAAA==.Kernsarn:BAAANQAECgIIAgABNQAECgoKQQAPAOIYAA==.',
Kh='Khanyiso:BAABNQAECn83AAIMAAoKWxpCDAA4AgAMAAoKWxpCDAA4AgAAAA==.Kharak:BAABNQAECn8qAAIIAAoKZxxUQgAhAgAIAAoKZxxUQgAhAgABNQABCgUIBwAXAAAAAA==.Khârnxoxo:BAAANQAECggIBgAAAA==.',
Ki='Kichi:BAAANQAECgEIAQAAAA==.Kichii:BAAANQAECgYIDgAAAA==.Kiellan:BAAANQADCgUIBQAAAA==.Kieran:BAABNQAECn9DAAMHAAoKoBQ2HgBeAQAHAAgKvg82HgBeAQAGAAUKzwf2vADjAAAAAA==.Kilsaurys:BAACNQAFFH8KAAMcAAQKlA0tFgCFAAAcAAMKlA0tFgCFAAAmAAEK+gLZFQA3AAA1AAQKfzEABBwACgqXG+QkAKoCABwACgqXG+QkAKoCACYABwqvEoksALgBABMABQqzDds7ANEAAAAA.Kirakishou:BAAANQAECggIBwABNQAFFAMICAAEAAIVAA==.Kismetard:BAAANQAECggICwABNQAECgoKJAAbAMYNAA==.Kismete:BAABNQAECn8kAAMbAAoKxg2PCwCkAQAbAAoKxg2PCwCkAQAZAAEKAAAPQgAmAAAAAA==.',
Ko='Konstantine:BAABNQAECn8hAAMRAAkK6htXZwBlAgARAAkK6htXZwBlAgAMAAUKuBSjPAAOAQAAAA==.',
Kr='Kravnoc:BAAANQADCgcIDQAAAA==.Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgAXAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAABNQAECn8hAAIEAAkKIgZnggBsAQAEAAkKIgZnggBsAQAAAA==.',
La='Laprimera:BAAANQAECgEIAgAAAA==.Lasticon:BAABNQAECn8ZAAIEAAYKBwgJ3QBHAQAEAAYKBwgJ3QBHAQABNQAECggICwAXAAAAAA==.Lazyjade:BAABNQAECn83AAIHAAoKjhroDwAlAgAHAAoKjhroDwAlAgAAAA==.',
Le='Lenarius:BAAANQABCgYIBgAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leprechauñ:BAAANQADCgQIBAAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQAECggIAgAAAA==.Lilsnot:BAAANQAECgMIAwAAAA==.',
Lo='Lockofdirish:BAAANQADCgcIEAAAAA==.Lorfirandor:BAAANQADCgYIDAAAAA==.Lorynn:BAABNQAECn9AAAIIAAoK1h+fIwCVAgAIAAoK1h+fIwCVAgAAAA==.',
Ma='Maches:BAABNQAECn8WAAMBAAYK3QdctwCxAAABAAYK3QdctwCxAAAhAAEKWgeKNgAiAAAAAA==.Macready:BAAANQAECgMIAQAAAA==.Madwe:BAABNQAECn8pAAMOAAoKERCzIQCgAQAOAAkKTBCzIQCgAQAYAAMKOA37bwCnAAAAAA==.Magdalari:BAAANQAECgIIAwAAAA==.Magturri:BAABNQAECn88AAMEAAoKeByfQwCgAgAEAAkKhh6fQwCgAgACAAMKogryegBWAAAAAA==.Magvara:BAAANQAECggIDQAAAA==.Mamameatmode:BAAANQAECgUICAAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCggIJwAAAA==.Maxfrogpower:BAAANQADCggIFAAAAA==.Maxsunward:BAABNQAECn8dAAIMAAYKux4EJQC4AQAMAAYKux4EJQC4AQAAAA==.',
Me='Meepasaurus:BAABNQAECn86AAIfAAoKMyIlBQCWAgAfAAoKMyIlBQCWAgAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAABNQAECn87AAInAAoK9SP+AgCHAwAnAAoK9SP+AgCHAwAAAA==.Metanoia:BAABNQAECn8wAAMKAAkKRiKdCgALAwAKAAkKCCCdCgALAwAJAAkKoB8lDwCyAQABNQAECgoKSgABAHklAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEBNQAECn8oAAMOAAoK3xwAFgASAgAOAAoK3xwAFgASAgAPAAEKKRYZhABKAAABNQAECgoKGAAcAFAPAA==.Mibb:BAEBNQAECn8nAAIIAAkKECHSPwAGAwAIAAkKECHSPwAGAwABNQAECgoKGAAcAFAPAA==.Midnitetrvlr:BAABNQAECn8bAAIOAAkKNw33YwCBAQAOAAkKNw33YwCBAQAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAABNQAECn8jAAIVAAkKMhThCwAAAgAVAAkKMhThCwAAAgAAAA==.Missmoans:BAAANQAECgQIBAABNQAECgoKGAARAD4RAA==.Mizeeri:BAAANQADCgQIBAAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAABNQAECn8lAAIhAAkKohrkAgAjAwAhAAkKohrkAgAjAwAAAA==.Monre:BAAANQAECgMIBQABNQAECggIEwAXAAAAAA==.Moojito:BAAANQAECgUIBQAAAA==.Moonflame:BAACNQAFFH8GAAIGAAIK6xhNIgCaAAAGAAIK6xhNIgCaAAA1AAQKfzAAAgYACgrYG7MxAKECAAYACgrYG7MxAKECAAAA.Mooriah:BAABNQAECn8vAAIcAAoKIwUXYABPAQAcAAoKIwUXYABPAQAAAA==.Mordekhuul:BAABNQAECn81AAIBAAoK2B1hJgDrAgABAAoK2B1hJgDrAgAAAA==.Moserr:BAAANQAECgEIAQAAAA==.Motowa:BAAANQAECgIIBAAAAA==.Mournhide:BAAANQAECggIEQAAAA==.',
Mp='Mpkshaman:BAACNQAFFH8FAAQiAAMKgBanBACeAAAiAAMKgBanBACeAAANAAEKvgeqMQBHAAAFAAEKHBPOKAA7AAA1AAQKfygABCIACgp1HSwIAHcCACIACQpBGywIAHcCAA0ACApDGQFCAG0CAAUAAQo+C3cVAT8AAAAA.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECggIHQAiANUGAA==.Mynchus:BAABNQAECn8dAAMiAAgK1QbtHgBxAQAiAAgKCgbtHgBxAQANAAUK/AORrAB8AAAAAA==.Mysterydh:BAABNQAECn8kAAIdAAkKKSBkBABnAgAdAAkKKSBkBABnAgAAAA==.Mysterypala:BAAANQAECgcIEAAAAA==.Mysteryvoke:BAABNQAECn8kAAIaAAgKuSOuCwDpAgAaAAgKuSOuCwDpAgAAAA==.Mystodin:BAAANQAECggIDwAAAA==.Myztic:BAAANQADCgEIAQAAAA==.',
['Mä']='Mälförmïtÿ:BAAANQAECgcIBgAAAA==.',
Na='Naneko:BAABNQAECn8YAAMIAAcKpQSpSwERAQAIAAYKOQSpSwERAQAVAAEKwAbgOAAsAAAAAA==.Naughtea:BAAANQAECgEIAQABNQAECggIDgAXAAAAAA==.',
Ne='Neelix:BAABNQAECn8oAAMEAAoK/AjgkgDjAQAEAAoK/AjgkgDjAQACAAUK+gHaZgCQAAAAAA==.Nehi:BAAANQAECggICQAAAA==.Neotahr:BAABNQAECn8/AAICAAoKsg/cFgCeAQACAAoKsg/cFgCeAQAAAA==.Nestli:BAAANQAECgYIBgAAAA==.Neuron:BAEANQABCgUICgABNQAECgIIBgAXAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECn8/AAIEAAoK6RTmTgDxAQAEAAoK6RTmTgDxAQAAAA==.Nitehunter:BAABNQAECn8gAAIEAAkKlwsDhgBkAQAEAAkKlwsDhgBkAQAAAA==.Niu:BAAANQAECgEIAwABNQAECgkJMAAcAHskAA==.',
No='Noobert:BAABNQAECn8yAAITAAoKnhYFEAD7AQATAAoKnhYFEAD7AQAAAA==.Novademic:BAAANQAECgUIDwAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAQAAAA==.',
Of='Offseason:BAAANQADCgYIBgAAAA==.',
Og='Ognikkay:BAACNQAFFH8GAAIWAAQKugygAQDGAAAWAAQKugygAQDGAAA1AAQKf0AAAhYACgppISoEAMECABYACgppISoEAMECAAAA.',
Ok='Okboomer:BAAANQAECgEIAQABNQAECgkJMAAcAHskAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.Orcpriest:BAAANQAECgMIBQABNQAECgoKJAAOANAXAA==.',
Oy='Oyakev:BAAANQAECgEIBAAAAA==.Oyea:BAAANQAECgcICAABNQAECgoKNwAHAI4aAA==.',
Pa='Pabiloneta:BAAANQAECgYIDwABNQAECgkJGwAJAJ4bAA==.Pakami:BAAANQAECgYIBgAAAA==.Pallyana:BAABNQAECn86AAIRAAoKUx60LgB9AgARAAoKUx60LgB9AgAAAA==.Palm:BAAANQAECgEIAwAAAA==.Palosdin:BAABNQAECn8WAAIRAAcKKwcj4QDeAAARAAcKKwcj4QDeAAAAAA==.Papadoble:BAAANQAECgEIAQABNQAECgoKMwAjALMcAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQAECgQICQABNQAECgYIDQAXAAAAAA==.Pass:BAAANQAECggIEwABNQAECgoKMQASALokAA==.',
Pe='Perridan:BAAANQAECgcIBwAAAA==.',
Ph='Phalandrel:BAABNQAECn8cAAIEAAoKBRaqcgAsAgAEAAoKBRaqcgAsAgAAAA==.Phewphew:BAAANQAECgMICAAAAA==.Phiora:BAAANQAECgEIAgABNQAECgUICgAXAAAAAA==.',
Pi='Pinkponyclub:BAABNQAECn9GAAIDAAoKxhyCIQDnAgADAAoKxhyCIQDnAgAAAA==.Pinkyshock:BAABNQAECn9nAAIMAAoKWB79CQD8AgAMAAoKWB79CQD8AgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICAAXAAAAAA==.Portholes:BAABNQAECn8dAAIIAAgKoRccagCwAQAIAAgKoRccagCwAQAAAA==.',
Pr='Praystatiøn:BAAANQAECggIDgAAAA==.',
Ps='Psyop:BAABNQAECn8dAAIFAAkK+BzmHgDvAgAFAAkK+BzmHgDvAgAAAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAABNQAECn8cAAIlAAkKzxuzBQBhAgAlAAkKzxuzBQBhAgABNQAFFAcIGAASAA0fAA==.Purplod:BAABNQAECn8jAAMYAAkKgQpXTQCCAQAYAAkK2wlXTQCCAQAPAAUKXAhfjwDHAAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
['Pò']='Pòpemz:BAAANQADCgUIBAAAAA==.',
Qi='Qing:BAABNQAECn8zAAIjAAoKsxxjCACmAgAjAAoKsxxjCACmAgAAAA==.',
Qy='Qybxboogied:BAAANQAECggIEwAAAA==.Qybxboogies:BAABNQAECn8cAAMGAAkKHhdfMwA9AgAGAAgKhRlfMwA9AgAHAAIKzQWUaABfAAAAAA==.Qybxboogyy:BAAANQAECggIDwAAAA==.',
Ra='Raensong:BAABNQAECn8dAAMRAAoKShA8cACvAQARAAoKShA8cACvAQAMAAEK2AfXXwAnAAAAAA==.Rafterman:BAAANQAECgQIBQAAAA==.Rainingarrow:BAAANQAECggIDAAAAA==.Raisa:BAABNQAECn9LAAMBAAoKniPsFQCpAgABAAoKgiPsFQCpAgAhAAMK3xqIEwCjAAAAAA==.Rakarum:BAAANQAECgEIAQAAAA==.Rasar:BAABNQAECn8pAAIIAAoKoRVsSQAMAgAIAAoKoRVsSQAMAgAAAA==.Rathew:BAABNQAECn8YAAMFAAkKeh0YTQAvAgAFAAgKKR4YTQAvAgANAAMK7AaAuQBnAAAAAA==.Rawnext:BAABNQAECn8ZAAIIAAgKNxiicACfAQAIAAgKNxiicACfAQABNQAFFAQIBgAQANsOAA==.',
Re='Renaitiaalaa:BAAANQAECgUICAAAAA==.Renei:BAABNQAECn8cAAMKAAcK1xtpNgDiAQAKAAcK1xtpNgDiAQAJAAMK2wnEPwB9AAABNQAECggIKAAFAGglAA==.Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECn9OAAQEAAkKxxNmVAB0AgAEAAkKIhNmVAB0AgACAAcKUA6UPQBmAQAoAAIK6g8KEAB/AAAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAACNQAFFH8GAAIGAAQKNxRlEwA3AQAGAAQKNxRlEwA3AQA1AAQKfzYAAwYACgp9JHgEAKkDAAYACgp9JHgEAKkDAAsABQqwIo0IANsBAAAA.Riott:BAAANQAECgEIAgAAAA==.',
Ro='Rollo:BAAANQAECgEIAQABNQAECgkJMAAcAHskAA==.Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECggIDAAAAA==.Rox:BAAANQAECgcIEwAAAA==.Royal:BAAANQADCgcIDAAAAA==.Royle:BAAANQAECgMIAwAAAA==.Roysham:BAAANQAECgQICQAAAA==.Roywar:BAAANQAECgEIAgAAAA==.',
Ru='Rubiks:BAAANQAECggIAgAAAA==.',
['Ré']='Réîgn:BAABNQAECn8lAAIOAAoKmxMKGQDxAQAOAAoKmxMKGQDxAQAAAA==.',
Sa='Sacrus:BAAANQAECgYIEwAAAA==.Samael:BAAANQAECgEIAQAAAA==.Santoss:BAAANQADCgQIBAAAAA==.Sarah:BAABNQAECn8YAAMCAAkKZyFlFAC8AgACAAkKZyFlFAC8AgAEAAEKcxB0UgFAAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAXAAAAAA==.Scksattankin:BAAANQADCgEIAQAAAA==.Scoobear:BAAANQAECggIEgABNQAECgoKJAARALgVAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQAECgQIBgAAAA==.Senjougahara:BAACNQAFFH8aAAIYAAcKnxysAgAYAgAYAAcKnxysAgAYAgA1AAQKf0YAAhgACgqNJUQDAFgDABgACgqNJUQDAFgDAAAA.Seriyah:BAACNQAFFH8OAAIWAAQK6xB4AQDUAAAWAAQK6xB4AQDUAAA1AAQKfzoAAhYACgqoHbYHAOICABYACgqoHbYHAOICAAAA.Serph:BAABNQAECn8YAAQRAAoKPhHdlQBgAQARAAkKKBHdlQBgAQAMAAYKMBGSSADLAAADAAMKQA04vwBrAAAAAA==.',
Sh='Shabane:BAABNQAECn81AAIjAAgKZR7PBQD+AQAjAAgKZR7PBQD+AQAAAA==.Shadomajik:BAAANQAECgEIAQAAAA==.Shadowguy:BAAANQAECgEIAQAAAA==.Shame:BAABNQAECn8xAAIHAAkKeRf4FwCVAgAHAAkKeRf4FwCVAgAAAA==.Shankey:BAAANQAECgYIAQAAAA==.Shasta:BAAANQADCgQIBAAAAA==.Shiminy:BAAANQAECgMIBAAAAA==.Shinobi:BAABNQAECn8hAAISAAkKixR8LQCtAQASAAkKixR8LQCtAQAAAA==.Shiol:BAAANQAECgMIAwABNQAECgcIEwAXAAAAAA==.Shirls:BAABNQAECn8iAAIDAAkK3hrsNQCMAgADAAkK3hrsNQCMAgAAAA==.Shivak:BAABNQAECn9DAAIbAAoKLhXOBACuAgAbAAoKLhXOBACuAgAAAA==.Shivanie:BAABNQAECn8gAAIDAAoKchjqGgCzAgADAAoKchjqGgCzAgAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAABNQAECn8jAAIJAAkKTh2WJABkAgAJAAkKTh2WJABkAgAAAA==.Shrug:BAABNQAECn8gAAIgAAkK+BSOfgAeAgAgAAkK+BSOfgAeAgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAXAAAAAA==.',
Si='Siccem:BAAANQAECgIIAgAAAA==.Sicwiddit:BAABNQAECn8ZAAIEAAkKWg2siQBbAQAEAAkKWg2siQBbAQAAAA==.Sinadin:BAAANQAECgEIAQABNQAECgkJMAAcAHskAA==.Sinsha:BAAANQAECgEIAQABNQAECgkJMAAcAHskAA==.',
Sk='Skeeda:BAAANQAECgUIEwAAAA==.Skylinex:BAABNQAECn8mAAIKAAoK1BfcFABAAgAKAAoK1BfcFABAAgAAAA==.Skylinez:BAAANQAECgUIBwAAAA==.Skïttles:BAABNQAECn8jAAQmAAgKJxdHKgDMAQAmAAgKJxdHKgDMAQAcAAMKpQS3tAAuAAATAAIKzwMrbAAfAAABNQAECgoKGAARAD4RAA==.',
Sl='Sleezball:BAABNQAECn8gAAIRAAoKJhJukQACAgARAAoKJhJukQACAgAAAA==.',
So='Softie:BAAANQAECgIIAgABNQAECgkJJwAgAGAbAA==.Sonictide:BAAANQAECgYIDgAAAA==.Soulscream:BAABNQAECn8nAAIGAAkKyB9vFwAaAwAGAAkKyB9vFwAaAwAAAA==.',
Sp='Spaghetto:BAABNQAECn82AAIcAAoKGRjwIADGAgAcAAoKGRjwIADGAgAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECggIDwAAAA==.',
Su='Suzel:BAAANQAECgUIBQAAAA==.',
Sw='Sweetlips:BAAANQAECgIIAgAAAA==.Swiftyninja:BAABNQAECn8gAAIJAAkKcBMaDQDVAQAJAAkKcBMaDQDVAQABNQAECgoKQgAMALsdAA==.',
Sy='Sydaria:BAAANQAECgEIAQAAAA==.Synder:BAABNQAECn8wAAIbAAoKWQY5DgBkAQAbAAoKWQY5DgBkAQAAAA==.',
Ta='Tainin:BAABNQAECn8oAAIFAAgKaCXHHwDrAgAFAAgKaCXHHwDrAgAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAABNQAECn8yAAIBAAgK1RCzZABtAQABAAgK1RCzZABtAQAAAA==.Tazdingobomb:BAABNQAECn8XAAINAAoK3hBzLwDlAQANAAoK3hBzLwDlAQAAAA==.Tazerface:BAABNQAECn84AAMVAAoKrQ/0DgC7AQAVAAoKrQ/0DgC7AQAIAAYK7gPiWwH5AAAAAA==.',
Te='Tekin:BAABNQAECn9AAAIDAAoKZhrkIwB1AgADAAoKZhrkIwB1AgAAAA==.Teleprompter:BAAANQAECgYIDQAAAA==.Telrissan:BAABNQAECn8nAAIIAAoKxB6YZQCzAgAIAAoKxB6YZQCzAgAAAA==.Tenkawnor:BAABNQAECn8UAAIcAAkK4Qm9RgDWAAAcAAkK4Qm9RgDWAAAAAA==.Tenyroldemon:BAABNQAECn81AAQdAAoKVB6oBAD3AgAdAAkKnyGoBAD3AgAQAAMKvwhqPACNAAAeAAIK9hEAAAAAAAAAAA==.Tenzingyatso:BAAANQADCgYICgAAAA==.Tero:BAAANQADCgIIAgAAAA==.',
Th='Thald:BAABNQAECn82AAIjAAoK2xpUBABPAgAjAAoK2xpUBABPAgAAAA==.Thaznotmilk:BAAANQAECgYIBgAAAA==.Thxowlbama:BAAANQAECgMIAwABNQAECgoKGwADANgbAA==.',
Ti='Timzilla:BAAANQAECgUIBQABNQAECgoKOgAPANEeAA==.Tinylight:BAAANQADCgQIBAAAAA==.Tinytip:BAAANQADCggIDgAAAA==.Tisakna:BAABNQAECn9MAAQIAAoK8yNVRAD7AgAIAAkKnCJVRAD7AgAVAAMKiiP7GgAbAQAUAAEKeR+0BwBeAAAAAA==.',
To='Togon:BAAANQAECggICQAAAA==.Tooezy:BAAANQAECgMICgAAAA==.Tool:BAAANQAECgUICgAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAABNQAECn8aAAIJAAkKpheIOgDpAQAJAAkKpheIOgDpAQAAAA==.Trask:BAABNQAECn8jAAIIAAkKZRYcuQARAgAIAAkKZRYcuQARAgAAAA==.Trishalle:BAAANQADCgQIBAABNQAECgoKKwAcAFwTAA==.Trogdoor:BAAANQAECgUIBQAAAA==.Trokom:BAACNQAFFH8RAAMIAAcKUyZCCQA0AgAIAAYKQyZCCQA0AgAVAAEKkibmBwB1AAA1AAQKfzkAAggACgrjJmUCAOgDAAgACgrjJmUCAOgDAAE1AAUUBwoRAAgAUyYA.Trokopally:BAAANQAECgYIBgABNQAFFAcKEQAIAFMmAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECn8xAAMBAAoKkgtQYAB6AQABAAoKkgtQYAB6AQAhAAMK6wcwUgCIAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggIEAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECn8gAAMSAAkKwRzHGQB0AgASAAkKwRzHGQB0AgAjAAEKyARwMwAoAAAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgoKTAAmAJMTAA==.Vandermark:BAABNQAECn9MAAUmAAoKkxMJHQBLAgAmAAkKjhMJHQBLAgATAAoK/RKWEQDhAQAWAAUKohQYHgArAQAcAAQK1QsDggDIAAAAAA==.Varuna:BAAANQAECgcIEwABNQAECgoKMAAYABUlAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIDwAAAA==.Victus:BAAANQAECgYIBwAAAA==.Vidrus:BAAANQAECggICQAAAA==.Vilkas:BAACNQAFFH8IAAIHAAUKxh73BwCRAQAHAAUKxh73BwCRAQA1AAQKfx4AAgcACgotIc8JAEQDAAcACgotIc8JAEQDAAE1AAQKCgosABAAaiQA.Viserion:BAAANQADCgYIEgAAAA==.',
Wa='Waddledoo:BAABNQAECn8gAAIFAAgKkx+rLgCnAgAFAAgKkx+rLgCnAgAAAA==.Warmaku:BAABNQAECn8dAAImAAgKNh48HABUAgAmAAgKNh48HABUAgAAAA==.',
We='Webz:BAAANQAECgIIBAAAAA==.Weezybaby:BAAANQAECgQIBAAAAA==.',
Wh='Whïteoak:BAACNQAFFH8JAAImAAQKIwfZCQDsAAAmAAQKIwfZCQDsAAA1AAQKfy0AAiYACgpcHJsQANECACYACgpcHJsQANECAAAA.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECn8dAAIPAAkKxx/8GADlAgAPAAkKxx/8GADlAgAAAA==.Xanyp:BAAANQAECgEJAwABNQAECgkJHQAPAMcfAA==.',
Xe='Xeletath:BAAANQAECgYICwAAAA==.Xerg:BAAANQADCgUIBQABNQAECgoKMwAjALMcAA==.',
Xi='Xinaveruk:BAAANQAECggIEAAAAA==.',
Xo='Xoro:BAAANQAECgQIDAAAAA==.',
Xr='Xrxyz:BAABNQAECn8XAAMRAAkKJgoE3wDhAAARAAkKFgoE3wDhAAAMAAIKtwNoZgAYAAAAAA==.',
Xs='Xshamster:BAABNQAECn9PAAMFAAoKCBkUKwC2AgAFAAoKCBkUKwC2AgANAAEKAAD3MQE3AAAAAA==.',
Ye='Yen:BAAANQAECgEIAQAAAA==.Yewna:BAABNQAECn8UAAIGAAkK8xnlJQCGAgAGAAkK8xnlJQCGAgABNQAECgoKRAAFAKwkAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAQAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAPAMcfAA==.Zau:BAABNQAECn8iAAQlAAgKwh3DBgA7AgAlAAcKXiDDBgA7AgABAAQKexND8ADqAAAhAAIK1g8KGgB0AAAAAA==.',
Ze='Zed:BAABNQAECn8aAAIQAAoKPxi6DwAyAgAQAAoKPxi6DwAyAgABNQAECgoKMQASALokAA==.',
Zi='Zintar:BAAANQAECgEIAQAAAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAFFAQIDAAIAGMfAA==.Zolja:BAABNQAECn8VAAMhAAgKvwcAGgB0AAABAAUK7AX/BQHAAAAhAAQKkwkAGgB0AAAAAA==.Zoney:BAAANQAECgIIBQAAAA==.Zordlon:BAAANQAECgYIEwAAAA==.',
Zu='Zukem:BAABNQAECn8nAAIEAAoKNB6vNADNAgAEAAoKNB6vNADNAgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgYIDAABNQAECgcIEwAXAAAAAA==.',
Zy='Zyariah:BAAANQADCggIFQAAAA==.Zyvea:BAABNQAECn8wAAIgAAoKlBi0SwCmAgAgAAoKlBi0SwCmAgAAAA==.',
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
