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

local lookup = {'Warlock-Demonology','Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane','Rogue-Assassination','Priest-Holy','Priest-Discipline','Paladin-Protection','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Retribution','Monk-Windwalker','Druid-Guardian','Mage-Fire','Mage-Frost','Druid-Feral','Unknown-Unknown','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','Druid-Balance','DemonHunter-Vengeance','Priest-Shadow','DemonHunter-Havoc','Warrior-Protection','Warrior-Arms','Warlock-Destruction','Rogue-Outlaw','Rogue-Subtlety','Warlock-Affliction','Monk-Brewmaster','Evoker-Augmentation','Druid-Restoration','Monk-Mistweaver','Shaman-Enhancement','Hunter-Survival',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acidsword:BAACNQAFFH8FAAIBAAIKEhEQEQCVAAABAAIKEhEQEQCVAAA1AAQKfx4AAgEACQq4G281ALUCAAEACQq4G281ALUCAAE1AAUUAggGAAIAHBQA.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQAECgUIBQABNQAECgoKQAADAJokAA==.Adrua:BAAANQAECgYIBwAAAA==.Adym:BAABNQAECn8kAAIEAAoK7BN2PQA9AQAEAAoK7BN2PQA9AQAAAA==.',
Ag='Agave:BAABNQAECn81AAIFAAoKexADEADZAQAFAAoKexADEADZAQAAAA==.',
Ai='Aiyah:BAAANQAECgQICAAAAA==.',
Al='Altarboi:BAAANQAECgcIEQAAAA==.Alüçard:BAABNQAECn8fAAIGAAcKOg3FXQACAQAGAAcKOg3FXQACAQAAAA==.',
Am='Amoraniel:BAABNQAECn8rAAIGAAoKgxrwbwCeAgAGAAoKgxrwbwCeAgAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAABNQAECn8WAAIHAAkKMBuLIgByAgAHAAkKMBuLIgByAgAAAA==.Andresra:BAABNQAECn8pAAIGAAkKuiBrZwCvAgAGAAkKuiBrZwCvAgABNQAECgkJFgAHADAbAA==.Anie:BAAANQADCgQIBAAAAA==.Annaluna:BAAANQAECgEIAQAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAABNQAECn8UAAMIAAcKORYKGACyAQAIAAcKrxQKGACyAQAJAAQKGwqKFwC5AAAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.Arthusxoxo:BAAANQAECggIBgAAAA==.',
As='Asrael:BAAANQAECggIDQABNQAECgoKJgAKAMoTAA==.Asterin:BAAANQADCgYIDAAAAA==.',
Au='Augtism:BAAANQAECgIIAgABNQAECgoKGQADAJQbAA==.',
Av='Avâtre:BAABNQAECn8fAAILAAcK9Bd6WwAQAgALAAcK9Bd6WwAQAgAAAA==.',
Az='Azlea:BAAANQAECgcIBwAAAA==.',
Ba='Baguette:BAAANQAECgYIDQAAAA==.Bajingobomb:BAABNQAECn8zAAMMAAoKCx97AQCUAgAMAAoK1B57AQCUAgANAAYKER19SwDJAQAAAA==.Bakblood:BAAANQABCgYICgAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEIAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgcICQAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAAANQAECgUICwAAAA==.',
Be='Be:BAABNQAECn8nAAIIAAcKVxndFgC6AQAIAAcKVxndFgC6AQAAAA==.Beckyoncé:BAABNQAECn80AAIOAAoKqyJwAQCSAgAOAAoKqyJwAQCSAgAAAA==.Bedris:BAABNQAECn8fAAQKAAcKFReLIwDFAQAKAAcKFReLIwDFAQAPAAYK4gnB/AAlAQADAAEKXQK/NwEfAAAAAA==.Beerticus:BAABNQAECn8pAAIQAAcKvhyfBADOAQAQAAcKvhyfBADOAQAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECn8cAAIRAAkKthkAEABgAgARAAkKthkAEABgAgAAAA==.Binggles:BAACNQAFFH8vAAQGAAgKgyEIAgDcAgAGAAgKvh8IAgDcAgASAAQK4RcSAAAmAQATAAIKiyXlAwDaAAA1AAQKfyQAAgYACgrMJNIgAFcDAAYACgrMJNIgAFcDAAAA.',
Bl='Blacksheep:BAAANQAECgIIAgAAAA==.Blazze:BAAANQAECgUIDAABNQAECgoKHQAEACcbAA==.Blôôðhôôf:BAAANQADCgQIBAABNQAECgkJGAAUAKYOAA==.',
Bo='Bokinar:BAAANQAECggICQAAAA==.Bomboclaat:BAAANQAECgMIBwABNQAECgoKKQAQAHojAA==.Boolay:BAABNQAECn8XAAMKAAoKCxxhHwDqAQAKAAYKnR9hHwDqAQAPAAUKTxUVWgAQAQABNQABCgUIBQAVAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQAECgYICwAAAA==.Boozing:BAAANQADCgMIAwABNQAECgoKKwAEAJogAA==.Bosmina:BAABNQAECn81AAIIAAoKhhj+NQCQAgAIAAoKhhj+NQCQAgAAAA==.',
Br='Braei:BAABNQAECn8kAAIDAAcKlhOQcQDDAQADAAcKlhOQcQDDAQAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Breelynn:BAAANQADCggICAAAAA==.Brenhunt:BAAANQAECgIIAgAAAA==.Brenmonk:BAABNQAECn8fAAIQAAcK8gofNgBkAQAQAAcK8gofNgBkAQAAAA==.Brenpriest:BAAANQADCgYIBgAAAA==.Brenshammy:BAAANQADCgcIDAAAAA==.Bruenor:BAAANQAECgMIAwAAAA==.Bruucey:BAAANQAECgQIBQAAAA==.',
Bu='Bubblebaddie:BAAANQAECgMIBQAAAA==.Bubblicous:BAAANQADCgYIBgAAAA==.Bugenhagen:BAABNQAECn84AAIFAAoKGCNfBwCHAwAFAAoKGCNfBwCHAwAAAA==.Butchers:BAAANQAECgUIBgAAAA==.Buttpaladin:BAABNQAECn8nAAIPAAgK2BaNkgD/AQAPAAgK2BaNkgD/AQAAAA==.',
Ca='Caliden:BAAANQABCgYICwAAAA==.Cardib:BAACNQAFFH8QAAMMAAcKUxssBwCoAQAMAAUKeSIsBwCoAQAWAAMKmhAFDwDqAAA1AAQKfysAAwwACQrTJfoGAI4DAAwACQqxJfoGAI4DABYAAwoVJOJbADoBAAAA.Cavos:BAABNQAECn8dAAIOAAcKgRuLJwAIAgAOAAcKgRuLJwAIAgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAABNQAECn8yAAINAAoKfxZFBQD3AQANAAoKfxZFBQD3AQAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Chiri:BAECNQAFFH8JAAMXAAUKxAVTAgCSAAAXAAMKxAVTAgCSAAAYAAMKUgH6FACEAAA1AAQKfyUAAxcACgqxEQUUAA4CABcACgqxEQUUAA4CABgAAwoSAyRFAHkAAAAA.Chvngus:BAABNQAECn8wAAIPAAoKEh+XLQARAwAPAAoKEh+XLQARAwAAAA==.',
Ci='Citizencain:BAABNQAECn8UAAIGAAUKixs9CAF/AQAGAAUKixs9CAF/AQAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMIBwAAAA==.',
Co='Cocheeze:BAAANQAECggIDAABNQAECgoKGQAMAOoSAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEBNQAECn8XAAIZAAoKUA+SDwBdAQAZAAoKUA+SDwBdAQAAAA==.Conmammoth:BAAANQAECgcIDwAAAA==.Conquest:BAAANQADCgMIAwAAAA==.Coohwhip:BAAANQAECgIIAQAAAA==.Cornorgan:BAAANQAECggIEwAAAA==.Corèl:BAAANQADCgUIBwAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAABNQAECn8kAAIZAAoKJxIMNQBAAgAZAAoKJxIMNQBAAgAAAA==.Cristobal:BAAANQAECgYICgAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.',
Cu='Curaga:BAAANQAECgMIAwAAAA==.Curnsarn:BAAANQAECgQIBAABNQAECgoKMgANAH8WAA==.',
Cy='Cydea:BAAANQAECgQICQAAAA==.',
Da='Dagidan:BAABNQAECn8xAAIaAAkKGxJ7DAD/AQAaAAkKGxJ7DAD/AQAAAA==.Darktide:BAAANQAECggIEQAAAA==.Dashawmon:BAAANQADCggICAABNQADCgYICQAVAAAAAA==.Dashel:BAAANQAECgYIDAABNQAECgoKMAAbALIUAA==.',
De='Dead:BAAANQADCggICAAAAA==.Deathtoxi:BAAANQAECgIIAQAAAA==.Degey:BAAANQADCgIIAgAAAA==.Demonsoul:BAAANQADCgQIBAAAAA==.Demontotems:BAAANQADCgYIBgAAAA==.Demotoxi:BAACNQAFFH8FAAIOAAMK2w5+BADPAAAOAAMK2w5+BADPAAA1AAQKfy4ABA4ACgptGpADAPcBAA4ACgptGpADAPcBABwABApQGWRhAPUAABoAAgrNCqcsAFEAAAAA.Deriso:BAABNQAECn8ZAAMEAAoKhx+ILgDiAgAEAAoKhx+ILgDiAgACAAMK6hAZYwCdAAAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAVAAAAAA==.Destrozinth:BAAANQAECggIEQAAAA==.Dethorok:BAABNQAECn80AAIEAAoKQSV0BQC3AwAEAAoKQSV0BQC3AwAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQADCgYIDQABNQAECgEIAQAVAAAAAA==.',
Dh='Dhedge:BAAANQAECgIIAgAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgoKOAAFABgjAA==.Dib:BAAANQAECgQICgAAAA==.Digey:BAABNQAECn8oAAMdAAgKPSO4AQAlAgAdAAgKPSO4AQAlAgAeAAEKAAB4UQE1AAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAABNQAECn8YAAIfAAkK2QS8BgC3AAAfAAkK2QS8BgC3AAAAAA==.',
Do='Dontlookatme:BAAANQABCgUIBQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCggIEwABNQAECgEIAQAVAAAAAA==.',
Dr='Drakbek:BAABNQAECn8WAAIRAAcKexvDCwBBAQARAAcKexvDCwBBAQAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dronebot:BAABNQAECn9bAAMbAAoKjxzMDgAEAwAbAAoKjxzMDgAEAwAIAAEK8wsZkQA/AAAAAA==.Drucifer:BAAANQADCggIDwAAAA==.',
Du='Dud:BAAANQAECgcIBwABNQAECgkJGAAFAHodAA==.Dumbrouge:BAAANQAECgEIAQABNQAECgoKJgAKAMoTAA==.Durros:BAABNQAECn8hAAIFAAkKxBj6GACRAQAFAAkKxBj6GACRAQAAAA==.Dustyshotz:BAAANQAECgQIBAAAAA==.',
Dy='Dyhanna:BAAANQAECggIBwAAAA==.',
Eb='Eboger:BAAANQAECgIIAgAAAA==.',
Eg='Egam:BAAANQAECgUIBQAAAA==.',
El='Elunelphie:BAAANQADCgYICAAAAA==.',
Em='Embody:BAABNQAECn8fAAIZAAcKKw4eVwB6AQAZAAcKKw4eVwB6AQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECn8iAAIPAAoKAhpxJACSAQAPAAoKAhpxJACSAQAAAA==.',
Er='Erasmas:BAABNQAECn9AAAQDAAoKmiRmBgCZAwADAAoKmiRmBgCZAwAPAAcKlBrllAD6AQAKAAIKFSAVGgC9AAAAAA==.Erzascarlét:BAABNQAECn86AAIKAAoKrxtCCwDlAgAKAAoKrxtCCwDlAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAABNQAECn8ZAAIMAAoK6hLyBQDVAQAMAAoK6hLyBQDVAQAAAA==.Eviltotems:BAABNQAECn8WAAILAAoKIRGlawDdAQALAAoKIRGlawDdAQABNQAECgoKGQAMAOoSAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Ez='Ezyy:BAAANQAECgEIAQAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECn81AAMLAAoKcR1bGwAlAwALAAoKcR1bGwAlAwAFAAUKyw91NgALAQAAAA==.Fantasma:BAAANQAECgEIAQAAAA==.',
Fe='Fear:BAAANQAECgIIAgAAAA==.',
Fi='Findal:BAAANQAECgEIAQABNQABCgUIBwAVAAAAAA==.Fistymoo:BAEANQAECgEIAQABNQAFFAUICQAXAMQFAA==.Fivemagics:BAABNQAECn8rAAMBAAoKjxT1OQAdAQABAAkKbBT1OQAdAQAfAAIKERVQVgB8AAAAAA==.',
Fl='Fleaboy:BAABNQAECn8XAAMgAAgKHhG2CQDqAQAgAAgKHhG2CQDqAQAhAAEKSwShUQA6AAAAAA==.Flist:BAABNQAECn8pAAIQAAoKeiOKAwCeAwAQAAoKeiOKAwCeAwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAABNQAECn8eAAMGAAoKsBA8LQBpAQAGAAoKPw48LQBpAQATAAIKJRzwDgCcAAAAAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAABNQAECn8fAAIbAAcKSBfKJwDsAQAbAAcKSBfKJwDsAQAAAA==.Freesia:BAAANQAECgIIAgAAAA==.Fruitjuice:BAAANQAECgYIEQAAAA==.',
Fu='Furrios:BAAANQADCggICAAAAA==.',
Fx='Fxce:BAABNQAECn8aAAIhAAoKPAu5CwCCAQAhAAoKPAu5CwCCAQAAAA==.',
['Fâ']='Fâmine:BAAANQADCggICAAAAA==.',
Ga='Gaothan:BAAANQAECgEIAQAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECn8yAAIcAAoKOhLnBAATAgAcAAoKOhLnBAATAgAAAA==.',
Gl='Glaiven:BAABNQAECn8hAAIOAAkKaRNbKwDnAQAOAAkKaRNbKwDnAQAAAA==.Glasscleaner:BAABNQAECn8YAAIDAAoKpCH+CgBwAwADAAoKpCH+CgBwAwABNQAFFAYIGAAYAOscAA==.Glenmorangie:BAABNQAECn8jAAMJAAoKLB6yBAB4AgAJAAgKkB2yBAB4AgAbAAcKexw6JgD9AQAAAA==.',
Gn='Gnartusk:BAABNQAECn8oAAINAAcK8iFtIACwAgANAAcK8iFtIACwAgAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgUICQAVAAAAAA==.',
Gr='Grawlso:BAAANQADCgYIBgAAAA==.Greens:BAABNQAECn80AAIZAAoKXh5RBAAZAgAZAAoKXh5RBAAZAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAVAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgIIAwABNQAECgQICQAVAAAAAA==.Grïma:BAABNQAECn8wAAMiAAoKkBpIBACcAgAiAAoKkBpIBACcAgABAAMKTxIyBwG9AAAAAA==.',
Gs='Gsus:BAAANQADCggICAABNQAECgkJLQAjAPQaAA==.',
Gu='Gueritestje:BAABNQAECn8uAAIKAAgKLiD5AwDTAQAKAAgKLiD5AwDTAQAAAA==.Guzzlord:BAABNQAECn8hAAQYAAkKJwibJwB7AQAYAAkKJwibJwB7AQAXAAQKQQZFLQC2AAAkAAQKbQdeGQCnAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAQABNQAECggIHwAEAPETAA==.Handsomejack:BAAANQAECgEIAgABNQAECgoKMwAMAAsfAA==.Hanekawa:BAAANQAECggIAwABNQAECgoKLgAbALshAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAVAAAAAA==.',
Hb='Hboozing:BAABNQAECn8rAAMEAAoKmiDtAgDCAgAEAAoKmiDtAgDCAgACAAEKkxI+gwA8AAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Healynn:BAAANQAECgIIAgAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAVAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitoshura:BAABNQAECn8iAAMWAAoKFSXZBgB2AwAWAAoKcyTZBgB2AwAMAAcK+iQjGwDpAgAAAA==.Hittnrunn:BAAANQAECgEIAQAAAA==.',
Hk='Hkia:BAAANQAECgEIAQAAAA==.',
Ho='Holyginger:BAAANQAECgcIDAAAAA==.Holyglizzy:BAABNQAECn8cAAIPAAoKdRL2lQD3AQAPAAoKdRL2lQD3AQAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.Holytoxi:BAAANQADCgEIAQABNQAFFAMIBQAOANsOAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcJEgABNQAFFAYIGAAYAOscAA==.',
Ic='Ichtaca:BAAANQADCgEIAQAAAA==.',
Ik='Ikiryo:BAEANQAECgIIBgAAAA==.',
Im='Imtuggdup:BAABNQAECn8mAAMGAAoKmRzYGgCkAQAGAAoKmRzYGgCkAQATAAEKAABCRQA4AAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Indra:BAAANQAECgEIAQAAAA==.Infidel:BAABNQAECn8wAAIZAAkKeyRcBgCiAwAZAAkKeyRcBgCiAwAAAA==.Invert:BAAANQAFFAEIAQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgEIAwAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irayne:BAAANQADCgQIBAAAAA==.Irisharcher:BAAANQAECgIIAwAAAA==.Irishbeauty:BAAANQADCggICQAAAA==.Irishfury:BAAANQADCgcICQAAAA==.Irishman:BAAANQAECgQICAAAAA==.',
Is='Isengardd:BAAANQAECgEIAQAAAA==.',
It='Itazki:BAABNQAECn8mAAMUAAoKOR9iBABIAwAUAAoKOR9iBABIAwAZAAEKHQyhtAAuAAAAAA==.',
Ja='Jackpot:BAAANQAECgEIAQAAAA==.Jaft:BAAANQADCgYIEAAAAA==.Jalter:BAACNQAFFH8YAAIYAAYK6xxoBAAyAgAYAAYK6xxoBAAyAgA1AAQKfycAAhgACgpgIgwBAMcCABgACgpgIgwBAMcCAAAA.Janha:BAAANQADCggICQAAAA==.',
Je='Jediknight:BAAANQAECgMIBAAAAA==.Jenga:BAAANQAECgcIDAAAAA==.Jergal:BAABNQAECn8ZAAIeAAoKTQoYsgCfAQAeAAoKTQoYsgCfAQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAABNQAECn8xAAMPAAoKxRcNfAAyAgAPAAkKqxUNfAAyAgADAAkKswquawDUAQAAAA==.',
Ji='Jibbage:BAAANQAECgQIBAABNQAECgkJMAAZAHskAA==.Jinkala:BAAANQABCgYICQAAAA==.Jitzakkal:BAACNQAFFH8aAAMBAAcKXSXMBAAoAgABAAUKaSTMBAAoAgAfAAIKyyb+AgDmAAA1AAQKfyEAAx8ACQoMJrcKAEwCAAEABwp7JS46AKUCAB8ABgpkJLcKAEwCAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECn8qAAMPAAkKBybNBwC8AwAPAAkKBybNBwC8AwADAAEKFhoEgQBSAAAAAA==.Joshswims:BAABNQAECn8eAAIWAAkKuRdUBQAMAgAWAAkKuRdUBQAMAgAAAA==.',
Js='Js:BAAANQAECgEIAQAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgoKOwAGAHsjAA==.Juleita:BAAANQABCgQIBAAAAA==.Jumbojoe:BAAANQAECgIIAgAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kapena:BAAANQAECggIDwAAAA==.Kardinal:BAABNQAECn84AAQBAAoKDSXNBQChAwABAAoKDSXNBQChAwAfAAUKSBqPHwBzAQAiAAEKAAC+KgBCAAAAAA==.Kargan:BAAANQAECgMIAwABNQAECgUIDwAVAAAAAA==.Karliee:BAAANQADCggICAABNQAECgIIAgAVAAAAAA==.Karpathous:BAAANQAECggIBQAAAA==.',
Ke='Keladorn:BAABNQAECn8oAAIPAAgKcyFmEAD4AQAPAAgKcyFmEAD4AQAAAA==.',
Kh='Khanyiso:BAABNQAECn8mAAIKAAoKyhPAFABcAgAKAAoKyhPAFABcAgAAAA==.Kharak:BAABNQAECn8nAAIGAAoKeRkCDAAQAgAGAAoKeRkCDAAQAgABNQABCgUIBwAVAAAAAA==.',
Ki='Kichi:BAAANQADCgQIBAAAAA==.Kichii:BAAANQAECgUICQAAAA==.Kieran:BAABNQAECn8wAAMbAAoKshRyLQC6AQAbAAcKdw5yLQC6AQAIAAUKswdFZQCkAAAAAA==.Kilsaurys:BAACNQAFFH8IAAIZAAMKlA3HDACMAAAZAAMKlA3HDACMAAA1AAQKfy0ABBkACgrGGuQkAKoCABkACgrGGuQkAKoCACUABwqvEoksALgBABEABQqzDds7ANEAAAAA.Kirakishou:BAAANQAECggIBAABNQAECgoKLgAbALshAA==.Kismetard:BAAANQADCggICQABNQAECgkJHAAkAN0NAA==.Kismete:BAABNQAECn8cAAMkAAkK3Q2PCwCkAQAkAAkK3Q2PCwCkAQAXAAEKAAAPQgAmAAAAAA==.',
Ko='Konstantine:BAABNQAECn8bAAMPAAgKfRtXZwBlAgAPAAgKfRtXZwBlAgAKAAUKuBSjPAAOAQAAAA==.',
Kr='Kravnoc:BAAANQADCgcIDQAAAA==.Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgAVAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAAANQAECgYIDQAAAA==.',
La='Laprimera:BAAANQAECgEIAQAAAA==.Lasticon:BAABNQAECn8ZAAIEAAYKBwgJ3QBHAQAEAAYKBwgJ3QBHAQABNQAECggICwAVAAAAAA==.Lazyjade:BAABNQAECn8pAAIbAAoKHBe6GQCAAgAbAAoKHBe6GQCAAgAAAA==.',
Le='Lenarius:BAAANQABCgUJBQABNQABCgYIBgAVAAAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leprechauñ:BAAANQADCgQIBAAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQAECgEIAQAAAA==.Lilsnot:BAAANQAECgMIAwAAAA==.',
Lo='Lockofdirish:BAAANQADCgcIEAAAAA==.Lorfirandor:BAAANQADCgYIDAAAAA==.Lorynn:BAABNQAECn8uAAIGAAoKix1YGgCmAQAGAAoKix1YGgCmAQAAAA==.',
Ma='Maches:BAAANQAECgQIBgAAAA==.Madwe:BAABNQAECn8jAAIMAAkKYg1ZCgCVAQAMAAkKYg1ZCgCVAQAAAA==.Magturri:BAABNQAECn8yAAMEAAkK3B03CgAnAgAEAAkK3B03CgAnAgACAAIKLwfyegBWAAAAAA==.Magvara:BAAANQAECgEIAQAAAA==.Mamameatmode:BAAANQAECgUIBwAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCggIJAAAAA==.Maxfrogpower:BAAANQADCgcIDAAAAA==.Maxsunward:BAABNQAECn8VAAIKAAYKux6VCwBDAQAKAAYKux6VCwBDAQAAAA==.',
Me='Meepasaurus:BAABNQAECn8yAAIdAAoKox4OAQB9AgAdAAoKox4OAQB9AgAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAABNQAECn8wAAImAAoK3iL+AgCHAwAmAAoK3iL+AgCHAwAAAA==.Metanoia:BAABNQAECn8gAAMHAAkKPh9dGQCyAgAHAAkKPh9dGQCyAgAhAAEKAAAbYAAAAAABNQAECgoKOAABAA0lAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEBNQAECn8fAAMMAAoKkRtODgBsAQAMAAkKVhxODgBsAQANAAEKKRaFUQBVAAABNQAECgoKFwAZAFAPAA==.Mibb:BAEBNQAECn8nAAIGAAkKECHSPwAGAwAGAAkKECHSPwAGAwABNQAECgoKFwAZAFAPAA==.Midnitetrvlr:BAABNQAECn8aAAIMAAgK0gz3YwCBAQAMAAgK0gz3YwCBAQAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAABNQAECn8jAAITAAkKMhThCwAAAgATAAkKMhThCwAAAgAAAA==.Missmoans:BAAANQAECgQIAwABNQAECggIHwAlANEUAA==.Mizeeri:BAAANQADCgQIBAAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAABNQAECn8lAAIfAAkKohrkAgAjAwAfAAkKohrkAgAjAwAAAA==.Monre:BAAANQAECgMIBQABNQAECggIEwAVAAAAAA==.Moonflame:BAABNQAECn8mAAIIAAoKTBqzMQChAgAIAAoKTBqzMQChAgAAAA==.Mooriah:BAABNQAECn8rAAIZAAoK+wQXYABPAQAZAAoK+wQXYABPAQAAAA==.Mordekhuul:BAABNQAECn8tAAIBAAoKmBzTDgDNAQABAAoKmBzTDgDNAQAAAA==.Motowa:BAAANQAECgIIBAAAAA==.Mournhide:BAAANQAECggICgAAAA==.',
Mp='Mpkshaman:BAABNQAECn8aAAQLAAoKQRsBQgBtAgALAAgKQxkBQgBtAgAnAAQKnxz2BwB1AQAFAAEKPgt3FQE/AAAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECggIGwAnAC8GAA==.Mynchus:BAABNQAECn8bAAMnAAgKLwbtHgBxAQAnAAgKCgbtHgBxAQALAAQKJAPVdgBVAAAAAA==.Mysterydh:BAABNQAECn8eAAIaAAkKDh4AAQBVAgAaAAkKDh4AAQBVAgAAAA==.Mysterypala:BAAANQAECgUICgAAAA==.Mysteryvoke:BAABNQAECn8gAAIYAAgKuSOuCwDpAgAYAAgKuSOuCwDpAgAAAA==.Mystodin:BAAANQAECgcICAAAAA==.Myztic:BAAANQADCgEIAQAAAA==.',
Na='Naneko:BAAANQAECgYIEgAAAA==.',
Ne='Neelix:BAABNQAECn8iAAMEAAgK1AlGVAAIAQAEAAgK1AlGVAAIAQACAAUK+gHaZgCQAAAAAA==.Nehi:BAAANQAECggICQAAAA==.Neotahr:BAABNQAECn83AAICAAoKsg/pCQBHAQACAAoKsg/pCQBHAQAAAA==.Neuron:BAEANQABCgUICgABNQAECgIIBgAVAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECn8yAAIEAAoKQg/CZABLAgAEAAoKQg/CZABLAgAAAA==.Nitehunter:BAABNQAECn8UAAIEAAcKagmatACbAQAEAAcKagmatACbAQAAAA==.Niu:BAAANQAECgEIAQABNQAECgkJMAAZAHskAA==.',
No='Noobert:BAABNQAECn8hAAIRAAoK6BIyBwCOAQARAAoK6BIyBwCOAQAAAA==.Novademic:BAAANQAECgUIDwAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAQAAAA==.',
Of='Offseason:BAAANQADCgYIBgAAAA==.',
Og='Ognikkay:BAABNQAECn8yAAIUAAoKFR7CBQAbAwAUAAoKFR7CBQAbAwAAAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.Orcpriest:BAAANQAECgIIAgABNQAECgoKGQAMAOoSAA==.',
Oy='Oyakev:BAAANQAECgEIAQAAAA==.Oyea:BAAANQABCgIIAgABNQAECgoKKQAbABwXAA==.',
Pa='Pabiloneta:BAAANQAECgYICwABNQAECgkJFgAHADAbAA==.Pakami:BAAANQAECgYIBgAAAA==.Pallyana:BAABNQAECn8pAAIPAAoKrhtfJQCQAQAPAAoKrhtfJQCQAQAAAA==.Palm:BAAANQAECgEIAQAAAA==.Palosdin:BAAANQAECgYICgAAAA==.Papadoble:BAAANQAECgEIAQABNQAECgkJLQAjAPQaAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQAECgQIBwABNQAECgQICQAVAAAAAA==.Pass:BAAANQAECgYIBwABNQAECgoKKQAQAHojAA==.',
Pe='Perridan:BAAANQAECgcIBwAAAA==.',
Ph='Phalandrel:BAABNQAECn8VAAIEAAkKaxSqcgAsAgAEAAkKaxSqcgAsAgAAAA==.Phewphew:BAAANQAECgIIAgAAAA==.Phiora:BAAANQAECgEIAgABNQAECgUICQAVAAAAAA==.',
Pi='Pinkponyclub:BAABNQAECn8yAAIDAAoKxhoSBgBuAgADAAoKxhoSBgBuAgAAAA==.Pinkyshock:BAABNQAECn9XAAIKAAoK6Bz9CQD8AgAKAAoK6Bz9CQD8AgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICAAVAAAAAA==.Portholes:BAABNQAECn8VAAIGAAgK6BNpFgC4AQAGAAgK6BNpFgC4AQAAAA==.',
Pr='Praystatiøn:BAAANQAECgYICgAAAA==.',
Ps='Psyop:BAABNQAECn8cAAIFAAkK+BzmHgDvAgAFAAkK+BzmHgDvAgAAAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAABNQAECn8YAAIiAAkKAhp+AQClAQAiAAkKAhp+AQClAQABNQAFFAYIFgAQAFAfAA==.Purplod:BAABNQAECn8jAAMWAAkKgQpXTQCCAQAWAAkK2wlXTQCCAQANAAUKXAhfjwDHAAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAABNQAECn8tAAIjAAkK9BpjCACmAgAjAAkK9BpjCACmAgAAAA==.',
Qy='Qybxboogied:BAAANQAECggIDgAAAA==.Qybxboogies:BAABNQAECn8XAAMIAAkKqQ1HNQArAQAIAAgK4g5HNQArAQAbAAIKzQWUaABfAAAAAA==.Qybxboogyy:BAAANQAECggIDAAAAA==.',
Ra='Raensong:BAAANQAECgcIDgAAAA==.Rafterman:BAAANQAECgQIBAAAAA==.Rainingarrow:BAAANQABCgIIAwAAAA==.Raisa:BAABNQAECn81AAMBAAoKnSHjDgDMAQABAAkKUCHjDgDMAQAfAAMK3xpTLwAMAQAAAA==.Rakarum:BAAANQAECgIIAQAAAA==.Rasar:BAABNQAECn8lAAIGAAkKvRVyDAALAgAGAAkKvRVyDAALAgAAAA==.Rathew:BAABNQAECn8YAAMFAAkKeh0YTQAvAgAFAAgKKR4YTQAvAgALAAMK7AYbZwBtAAAAAA==.Rawnext:BAABNQAECn8ZAAIGAAgKNxj/EADfAQAGAAgKNxj/EADfAQABNQAFFAMIBQAOANsOAA==.',
Re='Renaitiaalaa:BAAANQAECgUIAwAAAA==.Renei:BAAANQAECgMIBAABNQAECgcIJgAFAGElAA==.Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECn9OAAQEAAkKxxNmVAB0AgAEAAkKIhNmVAB0AgACAAcKUA6UPQBmAQAoAAIK6g8KEAB/AAAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAABNQAECn8wAAMIAAoKiSJ4BACpAwAIAAoKiSJ4BACpAwAJAAUKsCKNCADbAQAAAA==.Riott:BAAANQAECgEIAgAAAA==.',
Ro='Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECgcICQAAAA==.Rox:BAAANQAECgYIDQAAAA==.Royal:BAAANQADCgcIDAAAAA==.Royle:BAAANQAECgEIAQAAAA==.Roysham:BAAANQAECgQICAAAAA==.Roywar:BAAANQAECgEIAQAAAA==.',
['Ré']='Réîgn:BAABNQAECn8VAAIMAAcKZBXaXQCYAQAMAAcKZBXaXQCYAQAAAA==.',
Sa='Sacrus:BAAANQAECgUIDwAAAA==.Samael:BAAANQADCgYICAAAAA==.Santoss:BAAANQADCgQIBAAAAA==.Sarah:BAABNQAECn8YAAMCAAkKZyFlFAC8AgACAAkKZyFlFAC8AgAEAAEKcxB0UgFAAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAVAAAAAA==.Scoobear:BAAANQAECgUICAABNQAECgoKHAAPAHUSAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQAECgQIBAAAAA==.Senjougahara:BAACNQAFFH8aAAIWAAcKnxysAgAYAgAWAAcKnxysAgAYAgA1AAQKfzQAAhYACgoxILsMAC8DABYACgoxILsMAC8DAAAA.Seriyah:BAACNQAFFH8IAAIUAAIKiwrSAwCFAAAUAAIKiwrSAwCFAAA1AAQKfysAAhQACgoTGLYHAOICABQACgoTGLYHAOICAAAA.Serph:BAAANQAECgcIEAABNQAECggIHwAlANEUAA==.',
Sh='Shabane:BAABNQAECn8nAAIjAAcKNB6bCgBqAgAjAAcKNB6bCgBqAgAAAA==.Shame:BAABNQAECn8xAAIbAAkKeRf4FwCVAgAbAAkKeRf4FwCVAgAAAA==.Shankey:BAAANQADCgYIBgAAAA==.Shasta:BAAANQADCgQIBAAAAA==.Shiminy:BAAANQAECgIIBAAAAA==.Shinobi:BAABNQAECn8dAAIQAAcKBhd8LQCtAQAQAAcKBhd8LQCtAQAAAA==.Shirls:BAABNQAECn8iAAIDAAkK3hrsNQCMAgADAAkK3hrsNQCMAgAAAA==.Shivak:BAABNQAECn8yAAIkAAoKrRTOBACuAgAkAAoKrRTOBACuAgAAAA==.Shivanie:BAABNQAECn8XAAIDAAgKcxZaGACVAQADAAgKcxZaGACVAQAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAABNQAECn8jAAIHAAkKTh2WJABkAgAHAAkKTh2WJABkAgAAAA==.Shrug:BAABNQAECn8gAAIeAAkK+BSOfgAeAgAeAAkK+BSOfgAeAgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAVAAAAAA==.',
Si='Sicwiddit:BAABNQAECn8UAAIEAAgKPwmc5AA3AQAEAAgKPwmc5AA3AQAAAA==.',
Sk='Skeeda:BAAANQAECgUICwAAAA==.Skylinex:BAABNQAECn8gAAIhAAoKFxXgBgDEAQAhAAoKFxXgBgDEAQAAAA==.Skylinez:BAAANQAECgQIBwAAAA==.Skïttles:BAABNQAECn8fAAQlAAgK0RRHKgDMAQAlAAgK0RRHKgDMAQAZAAMKpQS3tAAuAAARAAEKAACTcQAbAAAAAA==.',
Sl='Sleezball:BAABNQAECn8aAAIPAAkKAhBukQACAgAPAAkKAhBukQACAgAAAA==.',
So='Softie:BAAANQAECgEIAQABNQAECgkJJQAeAKwZAA==.Sonictide:BAAANQAECgYIDgAAAA==.Soulscream:BAABNQAECn8nAAIIAAkKyB9vFwAaAwAIAAkKyB9vFwAaAwAAAA==.',
Sp='Spaghetto:BAABNQAECn8wAAIZAAoKGRh3DAB+AQAZAAoKGRh3DAB+AQAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECgIIAgAAAA==.',
Su='Suzel:BAAANQADCggIFgAAAA==.',
Sw='Swiftyninja:BAAANQAECggIDwABNQAECgoKOgAKAK8bAA==.',
Sy='Sydaria:BAAANQABCgMIAwAAAA==.Synder:BAABNQAECn8rAAIkAAoKBgY5DgBkAQAkAAoKBgY5DgBkAQAAAA==.',
Ta='Tainin:BAABNQAECn8mAAIFAAcKYSXHHwDrAgAFAAcKYSXHHwDrAgAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAABNQAECn8kAAIBAAcKGRBmmgClAQABAAcKGRBmmgClAQAAAA==.Tazdingobomb:BAAANQAECgYIBgAAAA==.Tazerface:BAABNQAECn8oAAMTAAkKcA70DgC7AQATAAkKcA70DgC7AQAGAAYK7gPiWwH5AAAAAA==.',
Te='Tekin:BAABNQAECn8yAAIDAAkKnBQaEADXAQADAAkKnBQaEADXAQAAAA==.Teleprompter:BAAANQAECgQICQAAAA==.Telrissan:BAABNQAECn8dAAIGAAoKlR2YZQCzAgAGAAoKlR2YZQCzAgAAAA==.Tenkawnor:BAAANQAECgYICwAAAA==.Tenyroldemon:BAABNQAECn8wAAMaAAoKYxuoBAD3AgAaAAgKoCGoBAD3AgAOAAMKvwjhIgCcAAAAAA==.Tenzingyatso:BAAANQADCgYICgAAAA==.',
Th='Thald:BAABNQAECn8yAAIjAAkKaBr6AAA1AgAjAAkKaBr6AAA1AgAAAA==.Thaznotmilk:BAAANQAECgMIAwAAAA==.Thxowlbama:BAAANQAECgIIAgABNQAECgoKGQADAJQbAA==.',
Ti='Timzilla:BAAANQAECgUIBQABNQAECgoKKgANAMgcAA==.Tinytip:BAAANQADCggIDgAAAA==.Tisakna:BAABNQAECn87AAMGAAoKeyPfEwDIAQAGAAkKEyLfEwDIAQATAAMKiiP7GgAbAQAAAA==.',
To='Togon:BAAANQAECggICQAAAA==.Tooezy:BAAANQAECgMIBgAAAA==.Tool:BAAANQAECgUICQAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAABNQAECn8WAAIHAAkKnRaIOgDpAQAHAAkKnRaIOgDpAQAAAA==.Trask:BAABNQAECn8jAAIGAAkKZRYcuQARAgAGAAkKZRYcuQARAgAAAA==.Trishalle:BAAANQADCgQIBAABNQAECgoKJAAZACcSAA==.Trogdoor:BAAANQAECgIIAgAAAA==.Trokom:BAACNQAFFH8OAAIGAAUKTyZCCQA0AgAGAAUKTyZCCQA0AgA1AAQKfzMAAgYACgrjJmUCAOgDAAYACgrjJmUCAOgDAAE1AAUUBQoOAAYATyYA.Trokopally:BAAANQAECgYIBgABNQAFFAUKDgAGAE8mAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECn8lAAMBAAgKsAzrlgCtAQABAAgKsAzrlgCtAQAfAAMK6wcwUgCIAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggIEAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECn8gAAMQAAkKwRzHGQB0AgAQAAkKwRzHGQB0AgAjAAEKyARwMwAoAAAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgoKOwAlAGgSAA==.Vandermark:BAABNQAECn87AAUlAAoKaBIJHQBLAgAlAAkKjhMJHQBLAgARAAcKEA5BCwBHAQAUAAQKIBYYHgArAQAZAAQK1QsDggDIAAAAAA==.Varuna:BAAANQAECgYIBwABNQAECgoKIgAWABUlAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIDwAAAA==.Victus:BAAANQAECgQIAwAAAA==.Vidrus:BAAANQADCgcIDQAAAA==.Vilkas:BAABNQAECn8bAAMOAAoKUB6ECACHAQAOAAoKUB6ECACHAQAaAAEKAABzKwBZAAAAAA==.Viserion:BAAANQADCgYIEgAAAA==.',
Wa='Waddledoo:BAABNQAECn8gAAIFAAgKkx+rLgCnAgAFAAgKkx+rLgCnAgAAAA==.Warmaku:BAABNQAECn8bAAIlAAcK4B48HABUAgAlAAcK4B48HABUAgAAAA==.',
We='Webz:BAAANQAECgIIAgAAAA==.Weezybaby:BAAANQAECgQIBAAAAA==.',
Wh='Whïteoak:BAABNQAECn8fAAIlAAoKlBmbEADRAgAlAAoKlBmbEADRAgAAAA==.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECn8dAAINAAkKxx/8GADlAgANAAkKxx/8GADlAgAAAA==.Xanyp:BAAANQAECgEJAwABNQAECgkJHQANAMcfAA==.',
Xe='Xeletath:BAAANQAECgUIBQAAAA==.Xerg:BAAANQADCgUIBQABNQAECgkJLQAjAPQaAA==.',
Xi='Xinaveruk:BAAANQAECggIDgAAAA==.',
Xo='Xoro:BAAANQAECgQICQAAAA==.',
Xr='Xrxyz:BAAANQAECggICgAAAA==.',
Xs='Xshamster:BAABNQAECn88AAMFAAoKGhi/DwDbAQAFAAoKGhi/DwDbAQALAAEKAAD3MQE3AAAAAA==.',
Ye='Yen:BAAANQAECgEIAQAAAA==.Yewna:BAAANQAECgQIBgABNQAECgoKOAAFABgjAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAQAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQANAMcfAA==.Zau:BAABNQAECn8iAAQiAAgKwh3DBgA7AgAiAAcKXiDDBgA7AgABAAQKexND8ADqAAAfAAIK1g8WCgB8AAAAAA==.',
Ze='Zed:BAAANQAECggICwABNQAECgoKKQAQAHojAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAFFAMIBgAGAGMfAA==.Zolja:BAABNQAECn8UAAMfAAcK7whtCQCHAAAfAAQKkwltCQCHAAABAAQK+QeFkQBnAAAAAA==.Zoney:BAAANQAECgMIBAAAAA==.Zordlon:BAAANQAECgYIDwAAAA==.',
Zu='Zukem:BAABNQAECn8jAAIEAAoKtByvNADNAgAEAAoKtByvNADNAgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgQIBQABNQAECgQICgAVAAAAAA==.',
Zy='Zyariah:BAAANQADCggIDwAAAA==.Zyvea:BAABNQAECn8jAAIeAAoKlBgCKABmAQAeAAoKlBgCKABmAQAAAA==.',
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
