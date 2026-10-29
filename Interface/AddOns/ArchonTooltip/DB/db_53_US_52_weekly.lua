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

local lookup = {'Warlock-Demonology','Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Paladin-Protection','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Retribution','Monk-Windwalker','Druid-Guardian','Mage-Fire','Mage-Frost','Unknown-Unknown','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warrior-Arms','Warlock-Destruction','Shaman-Enhancement','Rogue-Outlaw','Warlock-Affliction','Monk-Brewmaster','Druid-Feral','Druid-Restoration','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acidsword:BAACNQAFFH8FAAIBAAIKEhGdGgCPAAABAAIKEhGdGgCPAAA1AAQKfyMAAgEACQqnHG81ALUCAAEACQqnHG81ALUCAAE1AAUUAwgHAAIAhw4A.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQAECgUIBQABNQAFFAQICAADALofAA==.Adrua:BAAANQAECgYIBgAAAA==.Adym:BAABNQAECn8kAAIEAAoK7BM7fQATAgAEAAoK7BM7fQATAgAAAA==.',
Ag='Agave:BAABNQAECn8/AAIFAAoK3xPWJAAlAgAFAAoK3xPWJAAlAgAAAA==.',
Ai='Aiyah:BAAANQAECgQICAAAAA==.',
Al='Altarboi:BAABNQAECn8bAAMGAAcKNiCfGgCLAgAGAAcKNiCfGgCLAgAHAAEKKgXZeQA0AAAAAA==.Alüçard:BAABNQAECn8jAAIIAAcKOg1WrgDqAAAIAAcKOg1WrgDqAAAAAA==.',
Am='Amoraniel:BAABNQAECn8rAAIIAAoKgxrwbwCeAgAIAAoKgxrwbwCeAgAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAABNQAECn8YAAMJAAkKMBuLIgByAgAJAAkKMBuLIgByAgAKAAIK+Bf7dgCNAAAAAA==.Andresra:BAABNQAECn8qAAIIAAkKuiBrZwCvAgAIAAkKuiBrZwCvAgABNQAECgkJGAAJADAbAA==.Anie:BAAANQADCgQIBAAAAA==.Annaluna:BAAANQAECgEIAQAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAABNQAECn8eAAMGAAoK7RPoJgA1AgAGAAoK2RLoJgA1AgALAAQKGwqKFwC5AAAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
As='Asrael:BAAANQAECggIDAABNQAECgoKMAAMACEaAA==.Asterin:BAAANQADCgcIDQAAAA==.',
Au='Audersi:BAAANQADCgEIAQAAAA==.Augtism:BAAANQAECgIIAgABNQAECgoKGwADANgbAA==.Aunumator:BAAANQADCgYIBgAAAA==.',
Av='Avâtre:BAABNQAECn8gAAINAAgKMBZ6WwAQAgANAAgKMBZ6WwAQAgAAAA==.',
Az='Azlea:BAAANQAECgcIBgAAAA==.',
Ba='Baguette:BAAANQAECgYIDQAAAA==.Bajingobomb:BAABNQAECn89AAMOAAoKWx8kCgB/AgAOAAoKJB8kCgB/AgAPAAYKER19SwDJAQAAAA==.Bajisil:BAAANQAECgMIAwABNQAECgoKPQAOAFsfAA==.Bakblood:BAAANQABCgYICgAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEIAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgYICgAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAAANQAECgUIDQAAAA==.',
Be='Be:BAABNQAECn8uAAIGAAcKfh6hJgA2AgAGAAcKfh6hJgA2AgAAAA==.Beckyoncé:BAABNQAECn86AAIQAAoKwSKJBACMAwAQAAoKwSKJBACMAwAAAA==.Bedris:BAABNQAECn8iAAQMAAgKfhWLIwDFAQAMAAcKFReLIwDFAQARAAcKFgvB/AAlAQADAAEKXQK/NwEfAAAAAA==.Beerticus:BAABNQAECn8wAAISAAcKvhxGHQBMAgASAAcKvhxGHQBMAgAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECn8cAAITAAkKthkAEABgAgATAAkKthkAEABgAgAAAA==.Binggles:BAACNQAFFH8vAAQIAAgKgyEIAgDcAgAIAAgKvh8IAgDcAgAUAAQK4RccAAAdAQAVAAIKiyXlAwDaAAA1AAQKfysAAggACgqdJdIgAFcDAAgACgqdJdIgAFcDAAAA.',
Bl='Blacksheep:BAAANQAECgMIAgAAAA==.Blazze:BAAANQAECgUICgABNQAECgoKJAAEAGsdAA==.Blôôðhôôf:BAAANQADCgQIBAAAAA==.',
Bo='Boaj:BAAANQAECgQIBAAAAA==.Bokinar:BAAANQAECggICAAAAA==.Bomboclaat:BAAANQAECgQIBwABNQAECgoKLQASAPYjAA==.Boolay:BAABNQAECn8bAAMMAAoKUxxhHwDqAQAMAAYKnR9hHwDqAQARAAcKwBFclgAmAQABNQABCgUIBQAWAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQAECgYICgAAAA==.Boozing:BAAANQADCggICgABNQAECgoKLwAEAAwiAA==.Bosmina:BAABNQAECn89AAIGAAoK0Rv+NQCQAgAGAAoK0Rv+NQCQAgAAAA==.',
Br='Braei:BAABNQAECn8rAAIDAAgKFhKQcQDDAQADAAgKFhKQcQDDAQAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Breelynn:BAAANQADCggICAAAAA==.Brenhunt:BAAANQAECgUIBgAAAA==.Brenmonk:BAABNQAECn8fAAISAAcK8gofNgBkAQASAAcK8gofNgBkAQAAAA==.Brenpriest:BAAANQADCggIDgAAAA==.Brenshammy:BAAANQADCgcIDAAAAA==.Bruenor:BAAANQAECgMIAwAAAA==.Bruucey:BAAANQAECgcICwAAAA==.',
Bu='Bubblebaddie:BAAANQAECgQIBQAAAA==.Bubblicous:BAAANQAECgYIBgAAAA==.Bugenhagen:BAABNQAECn9BAAIFAAoKrCRfBwCHAwAFAAoKrCRfBwCHAwAAAA==.Butchers:BAAANQAECgUICAAAAA==.Buttpaladin:BAABNQAECn8nAAIRAAgK2BaNkgD/AQARAAgK2BaNkgD/AQAAAA==.',
Ca='Caliden:BAAANQABCgYICwAAAA==.Cardib:BAACNQAFFH8QAAMOAAcKUxssBwCoAQAOAAUKeSIsBwCoAQAXAAMKmhAFDwDqAAA1AAQKfzUAAw4ACgrJJfoGAI4DAA4ACgqrJfoGAI4DABcAAwoVJOJbADoBAAAA.Cavos:BAABNQAECn8dAAIQAAcKgRuLJwAIAgAQAAcKgRuLJwAIAgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAABNQAECn88AAIPAAoK6hftEgAZAgAPAAoK6hftEgAZAgAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Cheesen:BAAANQABCgQIBAAAAA==.Chiri:BAECNQAFFH8KAAQYAAUKxAWzAwCQAAAYAAMKxAWzAwCQAAAZAAMKUgH6FACEAAAaAAEKAACmCgAAAAA1AAQKfykABBgACgouEwUUAA4CABgACgqxEQUUAA4CABoABArJDh4LANUAABkAAwoSAyRFAHkAAAAA.Chvngus:BAABNQAECn82AAMRAAoKHB+XLQARAwARAAoKEh+XLQARAwAMAAYK4xgBFABqAQAAAA==.',
Ci='Citizencain:BAABNQAECn8UAAIIAAUKixs9CAF/AQAIAAUKixs9CAF/AQAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMIBwAAAA==.',
Co='Cocheeze:BAAANQAECgcIDAABNQAECgoKHwAOAHMXAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEBNQAECn8XAAIbAAoKUA9TKQA9AQAbAAoKUA9TKQA9AQAAAA==.Conmammoth:BAABNQAECn8VAAIRAAcKRx8fYwCSAQARAAcKRx8fYwCSAQAAAA==.Conquest:BAAANQADCgUIBQAAAA==.Coohwhip:BAAANQAECgIIAQAAAA==.Cornorgan:BAAANQAECggIEwAAAA==.Corèl:BAAANQADCgUIBwAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAABNQAECn8qAAIbAAoKGBMMNQBAAgAbAAoKGBMMNQBAAgAAAA==.Cristobal:BAAANQAECgYICgAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.',
Cu='Curaga:BAAANQAECgMIAwAAAA==.Curnsarn:BAAANQAECgQIBAABNQAECgoKPAAPAOoXAA==.',
Cy='Cydea:BAAANQAECgQICwAAAA==.',
Da='Dagidan:BAABNQAECn85AAIcAAoKPxF7DAD/AQAcAAoKPxF7DAD/AQAAAA==.Darktide:BAAANQAECggIEAAAAA==.Dashawmon:BAAANQADCggICAABNQADCgYICQAWAAAAAA==.Dashel:BAAANQAECgcIDQABNQAECgoKOgAHAFYWAA==.',
De='Dead:BAAANQADCggICAAAAA==.Deathtoxi:BAAANQAECgIIAQAAAA==.Degey:BAAANQADCgIIAgAAAA==.Demonsoul:BAAANQADCgQIBAAAAA==.Demotoxi:BAACNQAFFH8GAAIQAAQK2w7aBgDHAAAQAAQK2w7aBgDHAAA1AAQKfzUABBAACgpJHt0SANQCABAACgpJHt0SANQCAB0ABApQGWRhAPUAABwAAgrNCqcsAFEAAAAA.Deriso:BAABNQAECn8dAAMEAAoKtx+ILgDiAgAEAAoKtx+ILgDiAgACAAMKAhQZYwCdAAAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAWAAAAAA==.Destrozinth:BAAANQAECggIEQAAAA==.Dethorok:BAABNQAECn8+AAIEAAoKoSV0BQC3AwAEAAoKoSV0BQC3AwAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQADCgYIDQABNQADCggIEwAWAAAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgoKQQAFAKwkAA==.Dib:BAAANQAECgQIDAAAAA==.Digey:BAABNQAECn8sAAMeAAoKKCEbAwC9AgAeAAoKKCEbAwC9AgAfAAEKAAB4UQE1AAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAABNQAECn8fAAIgAAkKFwXZDQCwAAAgAAkKFwXZDQCwAAAAAA==.',
Do='Dontlookatme:BAAANQABCgUIBQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCggIEwAAAA==.',
Dr='Drakbek:BAABNQAECn8aAAITAAcKuht5EwAsAgATAAcKuht5EwAsAgAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dremaster:BAAANQADCgQIBAAAAA==.Dronebot:BAABNQAECn9jAAMHAAoKjxzMDgAEAwAHAAoKjxzMDgAEAwAGAAEK8wu8vwA/AAAAAA==.Drucifer:BAAANQADCggIFwAAAA==.',
Du='Dud:BAAANQAECgYICAABNQAECgkJGAAFAHodAA==.Dumbrouge:BAAANQAECgIIAgABNQAECgoKMAAMACEaAA==.Durros:BAABNQAECn8hAAIFAAkKxBhgSgA5AgAFAAkKxBhgSgA5AgAAAA==.Dustyshotz:BAAANQAECgYICAAAAA==.',
Dy='Dyhanna:BAAANQAECggIBwAAAA==.',
Eb='Eboger:BAAANQAECgMIAgAAAA==.',
Eg='Egam:BAAANQAECgUIBQAAAA==.',
El='Elunelphie:BAAANQADCgYICAAAAA==.',
Em='Embody:BAABNQAECn8fAAIbAAcKKw4eVwB6AQAbAAcKKw4eVwB6AQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECn8lAAIRAAoKDBxIWQCLAgARAAoKDBxIWQCLAgAAAA==.',
Er='Erasmas:BAACNQAFFH8IAAIDAAQKuh+2BwB9AQADAAQKuh+2BwB9AQA1AAQKf0YABAMACgq2JGYGAJkDAAMACgq2JGYGAJkDABEABwqYG+WUAPoBAAwAAgoVIMQrAK8AAAAA.Erzascarlét:BAABNQAECn9CAAIMAAoKux1CCwDlAgAMAAoKux1CCwDlAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAABNQAECn8fAAIOAAoKcxdnDgA1AgAOAAoKcxdnDgA1AgAAAA==.Eviltotems:BAABNQAECn8dAAINAAoKVhVGKADEAQANAAoKVhVGKADEAQABNQAECgoKHwAOAHMXAA==.Eviscration:BAAANQADCgIIAgABNQADCgcICAAWAAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Ez='Ezyy:BAAANQABCgIIAgAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECn89AAQNAAoKVB9bGwAlAwANAAoKVB9bGwAlAwAFAAUKyw/jawD6AAAhAAIKkAq7IgCAAAAAAA==.Fantasma:BAAANQAECgEIAQAAAA==.',
Fe='Fear:BAAANQAECgIIAgAAAA==.',
Fi='Fistymoo:BAEANQAECgEIAQABNQAFFAUICgAYAMQFAA==.Fivemagics:BAABNQAECn81AAMBAAoKXhUeZAAtAgABAAkKWRUeZAAtAgAgAAIKERWmFQBwAAAAAA==.',
Fl='Fleaboy:BAABNQAECn8XAAMiAAgKHhG2CQDqAQAiAAgKHhG2CQDqAQAKAAEKSwShUQA6AAAAAA==.Flist:BAABNQAECn8tAAISAAoK9iOKAwCeAwASAAoK9iOKAwCeAwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAABNQAECn8mAAMIAAoKNRUYXACZAQAIAAoKiBIYXACZAQAVAAIKFh1BGgCfAAAAAA==.Foote:BAAANQAECggIBwABNQAFFAUIDAAZAJsHAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAABNQAECn8gAAIHAAgKUBXKJwDsAQAHAAgKUBXKJwDsAQAAAA==.Freesia:BAAANQAECgIIAgAAAA==.Fruitjuice:BAAANQAECgYIEQAAAA==.',
Fu='Furrios:BAAANQADCggICAAAAA==.',
Fx='Fxce:BAABNQAECn8jAAIKAAoKbBPmIgALAgAKAAoKbBPmIgALAgAAAA==.',
['Fâ']='Fâmine:BAAANQAECgUIBgAAAA==.',
Ga='Gaothan:BAAANQAECgcICAAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECn82AAIdAAoKPxVuEwAcAgAdAAoKPxVuEwAcAgAAAA==.',
Gl='Glaiven:BAABNQAECn8hAAIQAAkKaRNbKwDnAQAQAAkKaRNbKwDnAQAAAA==.Glasscleaner:BAABNQAECn8cAAIDAAoKFSL+CgBwAwADAAoKFSL+CgBwAwABNQAFFAcIGgAZAPccAA==.Glenmorangie:BAABNQAECn8nAAMLAAoKbh6yBAB4AgALAAgKkB2yBAB4AgAHAAgKexw6JgD9AQAAAA==.',
Gn='Gnartusk:BAABNQAECn8vAAIPAAgKaR9tIACwAgAPAAgKaR9tIACwAgAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgUICQAWAAAAAA==.',
Gr='Grawlso:BAAANQADCgYIBgAAAA==.Greens:BAABNQAECn9EAAIbAAoK+R6+CADKAgAbAAoK+R6+CADKAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAWAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgIIAwABNQAECgUICgAWAAAAAA==.Grïma:BAABNQAECn80AAMjAAoKkBpIBACcAgAjAAoKkBpIBACcAgABAAQKTxI+sgCNAAAAAA==.',
Gs='Gsus:BAAANQADCggICAABNQAECgoKMQAkALMcAA==.',
Gu='Gueritestje:BAABNQAECn83AAIMAAkKnCDjCgDsAgAMAAkKnCDjCgDsAgAAAA==.Guzzlord:BAABNQAECn8hAAQZAAkKJwibJwB7AQAZAAkKJwibJwB7AQAYAAQKQQZFLQC2AAAaAAQKbQdeGQCnAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAQABNQAECgoKIwAEAKMSAA==.Handsomejack:BAAANQAECgEIAgABNQAECgoKPQAOAFsfAA==.Hanekawa:BAAANQAECggIAQABNQAFFAIIBgAEAIMSAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAWAAAAAA==.',
Hb='Hboozing:BAABNQAECn8vAAMEAAoKDCJ4EwBRAwAEAAoKDCJ4EwBRAwACAAEKkxI+gwA8AAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Healynn:BAAANQAECgIIAQAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAWAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Himootation:BAAANQADCgQIBAAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitoshura:BAABNQAECn8qAAMXAAoKFSUVBQAbAwAXAAoK3SQVBQAbAwAOAAcK+iQjGwDpAgAAAA==.Hittnrunn:BAAANQAECgEIAQAAAA==.',
Ho='Holyginger:BAABNQAECn8VAAMRAAcKIhUjvAClAQARAAYKUBgjvAClAQADAAEKfhTqvAA/AAAAAA==.Holyglizzy:BAABNQAECn8gAAIRAAoKoxX2lQD3AQARAAoKoxX2lQD3AQAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.Holytoxi:BAAANQADCgEIAQABNQAFFAQIBgAQANsOAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcJEgABNQAFFAcIGgAZAPccAA==.',
Ic='Ichtaca:BAAANQADCgEIAQAAAA==.',
Ik='Ikiryo:BAEANQAECgIIBgAAAA==.',
Im='Imtuggdup:BAABNQAECn8qAAMIAAoKiSGxNwAZAwAIAAoKiSGxNwAZAwAVAAEKAABCRQA4AAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Indra:BAAANQAECgEIAQAAAA==.Infidel:BAABNQAECn8wAAIbAAkKeyRcBgCiAwAbAAkKeyRcBgCiAwAAAA==.Invert:BAAANQAFFAEIAQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgMIBQAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irayne:BAAANQADCgQIBAAAAA==.Irisharcher:BAAANQAECgUICAAAAA==.Irishbeauty:BAAANQADCggIDQAAAA==.Irishfury:BAAANQADCgcICQAAAA==.Irishman:BAAANQAECgUICgAAAA==.',
Is='Isengardd:BAAANQAECgEIAQAAAA==.',
It='Itazki:BAABNQAECn8wAAMlAAoKDyIiAgD1AgAlAAoKDyIiAgD1AgAbAAEKHQyhtAAuAAAAAA==.',
Ja='Jackpot:BAAANQAECgEIAQAAAA==.Jaft:BAAANQADCgYIEAAAAA==.Jalter:BAACNQAFFH8aAAIZAAcK9xz8AgAfAgAZAAcK9xz8AgAfAgA1AAQKfzAAAhkACgpgIhEEAHIDABkACgpgIhEEAHIDAAAA.Janha:BAAANQADCggICQAAAA==.',
Je='Jediknight:BAAANQAECgQIBAAAAA==.Jenga:BAAANQAECgcIDAAAAA==.Jergal:BAABNQAECn8fAAIfAAoK5AtIaQBKAQAfAAoK5AtIaQBKAQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAABNQAECn87AAMRAAoKxRcNfAAyAgARAAkKqxUNfAAyAgADAAoKfA3mLQDwAQAAAA==.',
Ji='Jibbage:BAAANQAECgQIBAABNQAECgkJMAAbAHskAA==.Jinkala:BAAANQABCgYICQAAAA==.Jitzakkal:BAACNQAFFH8aAAMBAAcKXSXMBAAoAgABAAUKaSTMBAAoAgAgAAIKyyb+AgDmAAA1AAQKfyEAAyAACQoMJrcKAEwCAAEABwp7JS46AKUCACAABgpkJLcKAEwCAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECn8qAAMRAAkKBybNBwC8AwARAAkKBybNBwC8AwADAAEKFhqUtQBPAAAAAA==.Joshswims:BAABNQAECn8oAAIXAAkKaRjTGQAAAgAXAAkKaRjTGQAAAgAAAA==.',
Js='Js:BAAANQAECgQIBQAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgoKQwAIAHsjAA==.Juleita:BAAANQABCgQIBAAAAA==.Jumbojoe:BAAANQAECgIIAgAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kapena:BAAANQAECggIDwAAAA==.Kardinal:BAABNQAECn9BAAQBAAoKYiXNBQChAwABAAoKYiXNBQChAwAgAAUKuhyPHwBzAQAjAAEKAAC+KgBCAAAAAA==.Kargan:BAAANQAECgMIAwABNQAECgYIEAAWAAAAAA==.Karliee:BAAANQADCggICAABNQAECgIIAgAWAAAAAA==.Karpathous:BAAANQAECggIBAAAAA==.',
Ke='Keladorn:BAABNQAECn8xAAIRAAkKsR8HOAAZAgARAAkKsR8HOAAZAgAAAA==.',
Kh='Khanyiso:BAABNQAECn8wAAIMAAoKIRrhCAA2AgAMAAoKIRrhCAA2AgAAAA==.Kharak:BAABNQAECn8nAAIIAAoKeRlDSADZAQAIAAoKeRlDSADZAQABNQABCgUIBwAWAAAAAA==.Khârnxoxo:BAAANQAECggIBgAAAA==.',
Ki='Kichi:BAAANQAECgEIAQAAAA==.Kichii:BAAANQAECgUICQAAAA==.Kiellan:BAAANQADCgUIBQAAAA==.Kieran:BAABNQAECn86AAMHAAoKVhZyLQC6AQAHAAcKVg9yLQC6AQAGAAUKzwf2vADjAAAAAA==.Kilsaurys:BAACNQAFFH8KAAMbAAQKlA3jEQCMAAAbAAMKlA3jEQCMAAAmAAEK+gLsEQA6AAA1AAQKfzEABBsACgqXG+QkAKoCABsACgqXG+QkAKoCACYABwqvEoksALgBABMABQqzDds7ANEAAAAA.Kirakishou:BAAANQAECggIBgABNQAFFAIIBgAEAIMSAA==.Kismetard:BAAANQADCggIEgABNQAECgoKIAAaAOgMAA==.Kismete:BAABNQAECn8gAAMaAAoK6AyPCwCkAQAaAAoK6AyPCwCkAQAYAAEKAAAPQgAmAAAAAA==.',
Ko='Konstantine:BAABNQAECn8fAAMRAAkKsBtXZwBlAgARAAkKsBtXZwBlAgAMAAUKuBSjPAAOAQAAAA==.',
Kr='Kravnoc:BAAANQADCgcIDQAAAA==.Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgAWAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAABNQAECn8VAAIEAAcKuARepADlAAAEAAcKuARepADlAAAAAA==.',
La='Laprimera:BAAANQAECgEIAgAAAA==.Lasticon:BAABNQAECn8ZAAIEAAYKBwgJ3QBHAQAEAAYKBwgJ3QBHAQABNQAECggICwAWAAAAAA==.Lazyjade:BAABNQAECn8zAAIHAAoKMBmLDQACAgAHAAoKMBmLDQACAgAAAA==.',
Le='Lenarius:BAAANQABCgYIBgAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leprechauñ:BAAANQADCgQIBAAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQAECgEIAQAAAA==.Lilsnot:BAAANQAECgMIAwAAAA==.',
Lo='Lockofdirish:BAAANQADCgcIEAAAAA==.Lorfirandor:BAAANQADCgYIDAAAAA==.Lorynn:BAABNQAECn85AAIIAAoKnR4DSQDwAgAIAAoKnR4DSQDwAgAAAA==.',
Ma='Maches:BAAANQAECgUIEAAAAA==.Madwe:BAABNQAECn8nAAMOAAoKERD5GACwAQAOAAkKTBD5GACwAQAXAAEKcg4ShwA6AAAAAA==.Magturri:BAABNQAECn85AAMEAAoK4xuPMwARAgAEAAkK3B2PMwARAgACAAMKogryegBWAAAAAA==.Magvara:BAAANQAECgIIAgAAAA==.Mamameatmode:BAAANQAECgYIBwAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCggIJwAAAA==.Maxfrogpower:BAAANQADCgcIDAAAAA==.Maxsunward:BAABNQAECn8aAAIMAAYKux7wGAA4AQAMAAYKux7wGAA4AQAAAA==.',
Me='Meepasaurus:BAABNQAECn82AAIeAAoKoiG8AwCWAgAeAAoKoiG8AwCWAgAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAABNQAECn83AAInAAoK5CP+AgCHAwAnAAoK5CP+AgCHAwAAAA==.Metanoia:BAABNQAECn8rAAMKAAkK9yFjCAABAwAKAAkKCCBjCAABAwAJAAkKPh9dGQCyAgABNQAECgoKQQABAGIlAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEBNQAECn8nAAMOAAoK3xybDwAlAgAOAAoK3xybDwAlAgAPAAEKKRZucgBOAAABNQAECgoKFwAbAFAPAA==.Mibb:BAEBNQAECn8nAAIIAAkKECHSPwAGAwAIAAkKECHSPwAGAwABNQAECgoKFwAbAFAPAA==.Midnitetrvlr:BAABNQAECn8aAAIOAAgK0gz3YwCBAQAOAAgK0gz3YwCBAQAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAABNQAECn8jAAIVAAkKMhThCwAAAgAVAAkKMhThCwAAAgAAAA==.Missmoans:BAAANQAECgQIBAABNQAECggIIAAmAKkWAA==.Mizeeri:BAAANQADCgQIBAAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAABNQAECn8lAAIgAAkKohrkAgAjAwAgAAkKohrkAgAjAwAAAA==.Monre:BAAANQAECgMIBQABNQAECggIEwAWAAAAAA==.Moonflame:BAACNQAFFH8FAAIGAAIK6xiWGwCdAAAGAAIK6xiWGwCdAAA1AAQKfywAAgYACgo8G7MxAKECAAYACgo8G7MxAKECAAAA.Mooriah:BAABNQAECn8rAAIbAAoK+wQXYABPAQAbAAoK+wQXYABPAQAAAA==.Mordekhuul:BAABNQAECn81AAIBAAoK2B2gGQBlAgABAAoK2B2gGQBlAgAAAA==.Moserr:BAAANQAECgEIAQAAAA==.Motowa:BAAANQAECgIIBAAAAA==.Mournhide:BAAANQAECggIDgAAAA==.',
Mp='Mpkshaman:BAABNQAECn8kAAQhAAoKdR1lBQCNAgAhAAkKIxtlBQCNAgANAAgKQxkBQgBtAgAFAAEKPgt3FQE/AAAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECggIHQAhANUGAA==.Mynchus:BAABNQAECn8dAAMhAAgK1QbtHgBxAQAhAAgKCgbtHgBxAQANAAUK/AO1kAB8AAAAAA==.Mysterydh:BAABNQAECn8eAAIcAAkKDh6FBQDVAgAcAAkKDh6FBQDVAgAAAA==.Mysterypala:BAAANQAECgcIEAAAAA==.Mysteryvoke:BAABNQAECn8iAAIZAAgKuSOuCwDpAgAZAAgKuSOuCwDpAgAAAA==.Mystodin:BAAANQAECgcICgAAAA==.Myztic:BAAANQADCgEIAQAAAA==.',
Na='Naneko:BAAANQAECgYIEgAAAA==.',
Ne='Neelix:BAABNQAECn8iAAMEAAgK1AngkgDjAQAEAAgK1AngkgDjAQACAAUK+gHaZgCQAAAAAA==.Nehi:BAAANQAECggICQAAAA==.Neotahr:BAABNQAECn8/AAICAAoKsg/QEAC4AQACAAoKsg/QEAC4AQAAAA==.Nestli:BAAANQAECgYIBgAAAA==.Neuron:BAEANQABCgUICgABNQAECgIIBgAWAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECn88AAIEAAoK6RQVNgAHAgAEAAoK6RQVNgAHAgAAAA==.Nitehunter:BAABNQAECn8aAAIEAAkKIAqatACbAQAEAAkKIAqatACbAQAAAA==.Niu:BAAANQADCgYICQABNQAECgkJMAAbAHskAA==.',
No='Noobert:BAABNQAECn8vAAITAAoK2hQdDAD1AQATAAoK2hQdDAD1AQAAAA==.Novademic:BAAANQAECgUIDwAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAQAAAA==.',
Of='Offseason:BAAANQADCgYIBgAAAA==.',
Og='Ognikkay:BAABNQAECn88AAIlAAoK7SCkAgDSAgAlAAoK7SCkAgDSAgAAAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.Orcpriest:BAAANQAECgMIBQABNQAECgoKHwAOAHMXAA==.',
Oy='Oyakev:BAAANQADCgcIDQAAAA==.Oyea:BAAANQABCgIIAgABNQAECgoKMwAHADAZAA==.',
Pa='Pabiloneta:BAAANQAECgYIDAABNQAECgkJGAAJADAbAA==.Pakami:BAAANQAECgYIBgAAAA==.Pallyana:BAABNQAECn8yAAIRAAoKQh7sHwCNAgARAAoKQh7sHwCNAgAAAA==.Palm:BAAANQADCgYICQAAAA==.Palosdin:BAAANQAECgYIDwAAAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQAECgQICAABNQAECgUICgAWAAAAAA==.Pass:BAAANQAECgYICgABNQAECgoKLQASAPYjAA==.',
Pe='Perridan:BAAANQAECgcIBwAAAA==.',
Ph='Phalandrel:BAABNQAECn8WAAIEAAoKZxKqcgAsAgAEAAoKZxKqcgAsAgAAAA==.Phewphew:BAAANQAECgIIBAAAAA==.Phiora:BAAANQAECgEIAQABNQAECgUICQAWAAAAAA==.',
Pi='Pinkponyclub:BAABNQAECn88AAIDAAoKohuCIQDnAgADAAoKohuCIQDnAgAAAA==.Pinkyshock:BAABNQAECn9fAAIMAAoKWB79CQD8AgAMAAoKWB79CQD8AgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICAAWAAAAAA==.Portholes:BAABNQAECn8WAAIIAAgK6BOjXwCPAQAIAAgK6BOjXwCPAQAAAA==.',
Pr='Praystatiøn:BAAANQAECgcICwAAAA==.',
Ps='Psyop:BAABNQAECn8cAAIFAAkK+BzmHgDvAgAFAAkK+BzmHgDvAgAAAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAABNQAECn8bAAIjAAkKyBuzBQBhAgAjAAkKyBuzBQBhAgABNQAFFAcIGAASAA0fAA==.Purplod:BAABNQAECn8jAAMXAAkKgQpXTQCCAQAXAAkK2wlXTQCCAQAPAAUKXAhfjwDHAAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAABNQAECn8xAAIkAAoKsxxjCACmAgAkAAoKsxxjCACmAgAAAA==.',
Qy='Qybxboogied:BAAANQAECggIEAAAAA==.Qybxboogies:BAABNQAECn8cAAMGAAkKHhcIIwBPAgAGAAgKhRkIIwBPAgAHAAIKzQWUaABfAAAAAA==.Qybxboogyy:BAAANQAECggICwAAAA==.',
Ra='Raensong:BAABNQAECn8YAAMRAAkKkA/TVAC3AQARAAkKkA/TVAC3AQAMAAEK2Af+UAApAAAAAA==.Rafterman:BAAANQAECgQIBAAAAA==.Rainingarrow:BAAANQAECgIIAgAAAA==.Raisa:BAABNQAECn8/AAMBAAoKjSJrFACHAgABAAoKcSJrFACHAgAgAAMK3xpTLwAMAQAAAA==.Rakarum:BAAANQAECgIIAQAAAA==.Rasar:BAABNQAECn8pAAIIAAoKoRUXNAAhAgAIAAoKoRUXNAAhAgAAAA==.Rathew:BAABNQAECn8YAAMFAAkKeh0YTQAvAgAFAAgKKR4YTQAvAgANAAMK7AYPnQBoAAAAAA==.Rawnext:BAABNQAECn8ZAAIIAAgKNxhZVwCmAQAIAAgKNxhZVwCmAQABNQAFFAQIBgAQANsOAA==.',
Re='Renaitiaalaa:BAAANQAECgUICAAAAA==.Renei:BAABNQAECn8VAAMKAAcK1xufKQDdAQAKAAcK1xufKQDdAQAJAAMK2wmfOgCCAAABNQAECggIJwAFAOokAA==.Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECn9OAAQEAAkKxxNmVAB0AgAEAAkKIhNmVAB0AgACAAcKUA6UPQBmAQAoAAIK6g8KEAB/AAAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAABNQAECn8wAAMGAAoKiSJ4BACpAwAGAAoKiSJ4BACpAwALAAUKsCKNCADbAQAAAA==.Riott:BAAANQADCggICQAAAA==.',
Ro='Rollo:BAAANQADCgQIBAABNQAECgkJMAAbAHskAA==.Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECggICwAAAA==.Rox:BAAANQAECgYIDQAAAA==.Royal:BAAANQADCgcIDAAAAA==.Royle:BAAANQAECgEIAQAAAA==.Roysham:BAAANQAECgQICAAAAA==.Roywar:BAAANQAECgEIAQAAAA==.',
['Ré']='Réîgn:BAABNQAECn8bAAIOAAkK5hPrHgB9AQAOAAkK5hPrHgB9AQAAAA==.',
Sa='Sacrus:BAAANQAECgYIEAAAAA==.Santoss:BAAANQADCgQIBAAAAA==.Sarah:BAABNQAECn8YAAMCAAkKZyFlFAC8AgACAAkKZyFlFAC8AgAEAAEKcxB0UgFAAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAWAAAAAA==.Scksattankin:BAAANQADCgEIAQAAAA==.Scoobear:BAAANQAECgcIDgABNQAECgoKIAARAKMVAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQAECgQIBgAAAA==.Senjougahara:BAACNQAFFH8aAAIXAAcKnxysAgAYAgAXAAcKnxysAgAYAgA1AAQKfz0AAhcACgqnJKkJAM0CABcACgqnJKkJAM0CAAAA.Seriyah:BAACNQAFFH8KAAIlAAIKiwozAgB3AAAlAAIKiwozAgB3AAA1AAQKfzgAAiUACgqCG/QFAB0CACUACgqCG/QFAB0CAAAA.Serph:BAAANQAECggIEwABNQAECggIIAAmAKkWAA==.',
Sh='Shabane:BAABNQAECn8uAAIkAAgKyx28BADoAQAkAAgKyx28BADoAQAAAA==.Shame:BAABNQAECn8xAAIHAAkKeRf4FwCVAgAHAAkKeRf4FwCVAgAAAA==.Shankey:BAAANQAECgYIAQAAAA==.Shasta:BAAANQADCgQIBAAAAA==.Shiminy:BAAANQAECgIIAwAAAA==.Shinobi:BAABNQAECn8eAAISAAgK5RR8LQCtAQASAAgK5RR8LQCtAQAAAA==.Shirls:BAABNQAECn8iAAIDAAkK3hrsNQCMAgADAAkK3hrsNQCMAgAAAA==.Shivak:BAABNQAECn86AAIaAAoK3hTOBACuAgAaAAoK3hTOBACuAgAAAA==.Shivanie:BAABNQAECn8gAAIDAAoKchjVEADKAgADAAoKchjVEADKAgAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAABNQAECn8jAAIJAAkKTh2WJABkAgAJAAkKTh2WJABkAgAAAA==.Shrug:BAABNQAECn8gAAIfAAkK+BSOfgAeAgAfAAkK+BSOfgAeAgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAWAAAAAA==.',
Si='Siccem:BAAANQAECgIIAgAAAA==.Sicwiddit:BAABNQAECn8WAAIEAAkKlAyKqADdAAAEAAkKlAyKqADdAAAAAA==.Sinadin:BAAANQADCgQIBAABNQAECgkJMAAbAHskAA==.',
Sk='Skeeda:BAAANQAECgYIDwAAAA==.Skylinex:BAABNQAECn8jAAIKAAoK1BfcFABAAgAKAAoK1BfcFABAAgAAAA==.Skylinez:BAAANQAECgQIBwAAAA==.Skïttles:BAABNQAECn8gAAQmAAgKqRZHKgDMAQAmAAgKqRZHKgDMAQAbAAMKpQS3tAAuAAATAAEKAACTcQAbAAAAAA==.',
Sl='Sleezball:BAABNQAECn8eAAIRAAoKJhJukQACAgARAAoKJhJukQACAgAAAA==.',
So='Softie:BAAANQAECgIIAgABNQAECgkJJwAfAGAbAA==.Sonictide:BAAANQAECgYIDgAAAA==.Soulscream:BAABNQAECn8nAAIGAAkKyB9vFwAaAwAGAAkKyB9vFwAaAwAAAA==.',
Sp='Spaghetto:BAABNQAECn82AAIbAAoKGRjwIADGAgAbAAoKGRjwIADGAgAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECgIIBQAAAA==.',
Su='Suzel:BAAANQADCggIFgAAAA==.',
Sw='Sweetlips:BAAANQADCgIIAgAAAA==.Swiftyninja:BAABNQAECn8YAAIJAAkKoxKKCgDbAQAJAAkKoxKKCgDbAQABNQAECgoKQgAMALsdAA==.',
Sy='Sydaria:BAAANQABCgMIAwAAAA==.Synder:BAABNQAECn8uAAIaAAoKMQY5DgBkAQAaAAoKMQY5DgBkAQAAAA==.',
Ta='Tainin:BAABNQAECn8nAAIFAAgK6iTHHwDrAgAFAAgK6iTHHwDrAgAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAABNQAECn8rAAIBAAgKJQ/aWQBVAQABAAgKJQ/aWQBVAQAAAA==.Tazdingobomb:BAAANQAECgcICwAAAA==.Tazerface:BAABNQAECn8wAAMVAAoKsg30DgC7AQAVAAoKsg30DgC7AQAIAAYK7gPiWwH5AAAAAA==.',
Te='Tekin:BAABNQAECn82AAIDAAoKdRQBLAD6AQADAAoKdRQBLAD6AQAAAA==.Teleprompter:BAAANQAECgUICgAAAA==.Telrissan:BAABNQAECn8jAAIIAAoKoB6YZQCzAgAIAAoKoB6YZQCzAgAAAA==.Tenkawnor:BAABNQAECn8UAAIbAAkK4QkbOgDfAAAbAAkK4QkbOgDfAAAAAA==.Tenyroldemon:BAABNQAECn8yAAQcAAoKYxuoBAD3AgAcAAgKoCGoBAD3AgAQAAMKvwh9MwCRAAAdAAIK9hHLYwA/AAAAAA==.Tenzingyatso:BAAANQADCgYICgAAAA==.',
Th='Thald:BAABNQAECn82AAIkAAoK2xr8AgBiAgAkAAoK2xr8AgBiAgAAAA==.Thaznotmilk:BAAANQAECgQIBAAAAA==.Thxowlbama:BAAANQAECgIIAQABNQAECgoKGwADANgbAA==.',
Ti='Timzilla:BAAANQAECgUIBQABNQAECgoKMwAPANEeAA==.Tinytip:BAAANQADCggIDgAAAA==.Tisakna:BAABNQAECn9DAAMIAAoKeyNVRAD7AgAIAAkKEyJVRAD7AgAVAAMKiiP7GgAbAQAAAA==.',
To='Togon:BAAANQAECggICAAAAA==.Tooezy:BAAANQAECgMIBgAAAA==.Tool:BAAANQAECgUICQAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAABNQAECn8YAAIJAAkKyxaIOgDpAQAJAAkKyxaIOgDpAQABNQAECgoKPQAMANUeAA==.Trask:BAABNQAECn8jAAIIAAkKZRYcuQARAgAIAAkKZRYcuQARAgAAAA==.Trishalle:BAAANQADCgQIBAABNQAECgoKKgAbABgTAA==.Trogdoor:BAAANQAECgUIBQAAAA==.Trokom:BAACNQAFFH8QAAIIAAYKQyYcBgCMAQAIAAYKQyYcBgCMAQA1AAQKfzYAAggACgrjJmUCAOgDAAgACgrjJmUCAOgDAAE1AAUUBgoQAAgAQyYA.Trokopally:BAAANQAECgYIBgABNQAFFAYKEAAIAEMmAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECn8tAAMBAAkKKgwDVgBhAQABAAkKKgwDVgBhAQAgAAMK6wcwUgCIAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggIEAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECn8gAAMSAAkKwRzHGQB0AgASAAkKwRzHGQB0AgAkAAEKyARwMwAoAAAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgoKQwAmAIESAA==.Vandermark:BAABNQAECn9DAAUmAAoKgRIJHQBLAgAmAAkKjhMJHQBLAgATAAoK6A5AEACqAQAlAAUKohQYHgArAQAbAAQK1QsDggDIAAAAAA==.Varuna:BAAANQAECgYICwABNQAECgoKKgAXABUlAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIDwAAAA==.Victus:BAAANQAECgQIAwAAAA==.Vidrus:BAAANQAECgcIBwAAAA==.Vilkas:BAACNQAFFH8IAAIHAAUKxh73BwCRAQAHAAUKxh73BwCRAQA1AAQKfx4AAgcACgotIc8JAEQDAAcACgotIc8JAEQDAAE1AAQKCgofABAAax8A.Viserion:BAAANQADCgYIEgAAAA==.',
Wa='Waddledoo:BAABNQAECn8gAAIFAAgKkx+rLgCnAgAFAAgKkx+rLgCnAgAAAA==.Warmaku:BAABNQAECn8dAAImAAgKNh48HABUAgAmAAgKNh48HABUAgAAAA==.',
We='Webz:BAAANQAECgIIAgAAAA==.Weezybaby:BAAANQAECgQIBAAAAA==.',
Wh='Whïteoak:BAACNQAFFH8FAAImAAIKpAtaDAB5AAAmAAIKpAtaDAB5AAA1AAQKfykAAiYACgpcHJsQANECACYACgpcHJsQANECAAAA.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECn8dAAIPAAkKxx/8GADlAgAPAAkKxx/8GADlAgAAAA==.Xanyp:BAAANQAECgEJAwABNQAECgkJHQAPAMcfAA==.',
Xe='Xeletath:BAAANQAECgUICQAAAA==.Xerg:BAAANQADCgUIBQABNQAECgoKMQAkALMcAA==.',
Xi='Xinaveruk:BAAANQAECggIDwAAAA==.',
Xo='Xoro:BAAANQAECgYICQAAAA==.',
Xr='Xrxyz:BAAANQAECggIEQAAAA==.',
Xs='Xshamster:BAABNQAECn9GAAMFAAoKOBgUKwC2AgAFAAoKOBgUKwC2AgANAAEKAAD3MQE3AAAAAA==.',
Ye='Yen:BAAANQADCgMIAwAAAA==.Yewna:BAAANQAECggIDAABNQAECgoKQQAFAKwkAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAQAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAPAMcfAA==.Zau:BAABNQAECn8iAAQjAAgKwh3DBgA7AgAjAAcKXiDDBgA7AgABAAQKexND8ADqAAAgAAIK1g98FAB1AAAAAA==.',
Ze='Zed:BAAANQAECgcIDwABNQAECgoKLQASAPYjAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAFFAQICAAIAGMfAA==.Zolja:BAABNQAECn8UAAMgAAcK7wg1FAB2AAABAAQK+Qf/BQHAAAAgAAQKkwk1FAB2AAAAAA==.Zoney:BAAANQAECgMIAwAAAA==.Zordlon:BAAANQAECgYIEwAAAA==.',
Zu='Zukem:BAABNQAECn8nAAIEAAoKNB6vNADNAgAEAAoKNB6vNADNAgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgQIBQABNQAECgQIDAAWAAAAAA==.',
Zy='Zyariah:BAAANQADCggIDwAAAA==.Zyvea:BAABNQAECn8oAAIfAAoKlBgtMQATAgAfAAoKlBgtMQATAgAAAA==.',
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
