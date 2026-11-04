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

local lookup = {'Mage-Arcane','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Outlaw','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Druid-Feral','Priest-Holy','Priest-Shadow','Paladin-Protection','Monk-Windwalker','Druid-Balance','Druid-Restoration','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abeblinkin:BAABNQAECn8aAAIBAAcK8BHM6AC4AQABAAcK8BHM6AC4AQAAAA==.Aborlight:BAAANQAECgUIEQAAAA==.Abstract:BAAANQAECgYIBgAAAA==.',
Ad='Adit:BAABNQAECn8bAAMCAAoKagc+XgCAAQACAAoKagc+XgCAAQADAAEKkAWlKAAoAAAAAA==.',
Af='Afrit:BAABNQAECn8cAAMBAAkKrxJpXQDTAQABAAkKrxJpXQDTAQAEAAEKPgSGUwAeAAAAAA==.',
Ai='Aiwass:BAABNQAECn8mAAIFAAoK4gWWCQABAQAFAAoK4gWWCQABAQAAAA==.',
Al='Alieah:BAAANQAECgYIEAAAAA==.Alorum:BAAANQADCggIEAABNQAECgkJJgAGAAoOAA==.Alphaomegaa:BAAANQAECgEIAQAAAA==.Alpharius:BAAANQAECgUIEwAAAA==.',
Am='Amacoozy:BAABNQAECn9DAAMHAAkK5xkhSwCoAgAHAAkK4xkhSwCoAgAIAAEKghnwJABRAAAAAA==.Amathricus:BAABNQAECn8sAAIJAAgKRwkV4gBXAQAJAAgKRwkV4gBXAQAAAA==.',
Ar='Arms:BAACNQAFFH8VAAMKAAcK8xT7BADDAQAKAAcK8xT7BADDAQALAAEKAACUJgAtAAA1AAQKfycAAgoACgqAIQcTAI0CAAoACgqAIQcTAI0CAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQAECgQIBAAAAA==.',
At='Athena:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAEANQADCgIIAgABNQAECggICAAMAAAAAA==.Auralei:BAAANQADCgUIBQABNQAECgUIFQADAJ0NAA==.',
Az='Azelia:BAAANQAECgQIBQABNQAECgcIDAAMAAAAAA==.Azzy:BAAANQAECgcIDAAAAA==.',
Be='Bellestri:BAABNQAECn8wAAICAAkKVwW8kQAAAQACAAkKVwW8kQAAAQAAAA==.',
Bi='Bigb:BAABNQAECn8YAAQGAAYKtiFsiQBcAQAGAAYKLSBsiQBcAQANAAQKCiPpDAD/AAAOAAEKAAB3lwApAAAAAA==.Bigface:BAAANQAECggIEQAAAA==.Bigrod:BAACNQAFFH8IAAIPAAMKzwciGgBqAAAPAAMKzwciGgBqAAA1AAQKfysAAg8ACQo9Fw0eAN8BAA8ACQo9Fw0eAN8BAAAA.Binks:BAAANQAECgIIAgAAAA==.',
Bl='Black:BAABNQAECn8hAAIQAAgKFhgnAgD5AQAQAAgKFhgnAgD5AQAAAA==.Blasfoomous:BAACNQAFFH8OAAIPAAYKxRHLFgD2AAAPAAYKxRHLFgD2AAA1AAQKfzkAAg8ACgohIL0OAJMCAA8ACgohIL0OAJMCAAAA.Blu:BAACNQAFFH8SAAIRAAUKRx7sCQCwAQARAAUKRx7sCQCwAQA1AAQKfy4AAhEACgoSJNgOAEwDABEACgoSJNgOAEwDAAAA.',
Bo='Bochese:BAAANQAECgMIAwABNQAECgkJKgASALEdAA==.',
Br='Brochese:BAAANQAECgUICQABNQAECgkJKgASALEdAA==.',
Bu='Bubblewrap:BAAANQAECgIIAwABNQAFFAYIDgATAI8TAA==.Budfoster:BAAANQADCggIEAAAAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQAECgQICgABNQAECgcIGgABAPARAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Ch='Cheyeon:BAAANQAECgEIAQAAAA==.',
Cl='Classcarry:BAABNQAECn8bAAMJAAkKah93fwAqAgAJAAkKah93fwAqAgASAAUKkhPvvAACAQABNQAECgoKJAARACIdAA==.Claybigsby:BAACNQAFFH8OAAMFAAYKPRnbCwChAAACAAQKUBtxGQCuAAAFAAIKIRbbCwChAAA1AAQKfy4AAwIACgqlH2tuABMCAAIACAqiH2tuABMCAAUABArXGv4vAAkBAAAA.Clif:BAAANQAFFAEIAQAAAA==.',
Co='Collie:BAEBNQAECn8kAAIUAAoK2iOwAgAEAwAUAAoK2iOwAgAEAwAAAA==.Constantina:BAABNQAECn8+AAIVAAkKbxYBSwBEAgAVAAkKbxYBSwBEAgAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQAECgMIAwAAAA==.',
Cy='Cyleste:BAABNQAECn8hAAMWAAoKBwtxLADCAQAWAAoKBwtxLADCAQAVAAQK0Q3yxADPAAAAAA==.',
De='Deadlylady:BAAANQADCgUICAAAAA==.Demonifrita:BAAANQADCggICgAAAA==.Demonlady:BAAANQADCggIEAAAAA==.Deo:BAABNQAECn8hAAMXAAoKZxZyEwC3AQAXAAkKZxZyEwC3AQASAAQKWgyclwDJAAAAAA==.Derpy:BAABNQAECn8cAAMTAAkKnQkcDQAoAQATAAkKnQkcDQAoAQAYAAYKsQPqTQC/AAAAAA==.',
Dh='Dheevix:BAAANQAECgYIDAABNQAECgoKNAABACYbAA==.',
Dj='Djheals:BAAANQAECgMIAwABNQAECggIGgAZAEANAA==.Djmuphasa:BAABNQAECn8aAAMZAAgKQA3JQwDkAAAZAAcKHwzJQwDkAAAaAAUKbgUrSQCgAAAAAA==.Djthrasher:BAAANQAECgQIBgABNQAECggIGgAZAEANAA==.',
Dr='Drachese:BAAANQAECgUIBwABNQAECgkJKgASALEdAA==.Dripps:BAAANQAECgMIAwAAAA==.Druchese:BAABNQAECn8lAAMaAAcK7hsWHgDAAQAaAAcK7hsWHgDAAQAZAAYKMg5sYwBAAQABNQAECgkJKgASALEdAA==.',
Dv='Dvorak:BAAANQAECgEIAQAAAA==.',
Ea='Eagleeye:BAABNQAECn8dAAIJAAgK/QkGuQAgAQAJAAgK/QkGuQAgAQAAAA==.',
Em='Emsley:BAACNQAFFH8FAAIbAAMKoAVvGwB1AAAbAAMKoAVvGwB1AAA1AAQKf08AAhsACgouF6hFAF8CABsACgouF6hFAF8CAAAA.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQAECgQIBAAAAA==.',
Ev='Ev:BAABNQAECn8XAAMTAAgKeRuYDQAgAgATAAUKSCaYDQAgAgAYAAcK7hCWOQBHAQAAAA==.',
Ex='Exo:BAACNQAFFH8HAAIBAAQKlAycLgAbAQABAAQKlAycLgAbAQA1AAQKfyIAAwEACgrYH0d3AI8CAAEACgrDHUd3AI8CAAQAAgrQIQwwAH8AAAAA.',
Fa='Falorin:BAAANQAECgEIAQAAAA==.',
Fl='Floudwing:BAAANQABCgYIDAAAAA==.',
Fn='Fnwarriors:BAAANQADCgcICAAAAA==.',
Fo='Focalors:BAAANQAECgcIDwABNQAFFAUIDwABAGUVAA==.Foobear:BAAANQAECgcIEAABNQAFFAYIDgAPAMURAA==.',
Fr='Franchescold:BAAANQAECggIDAAAAA==.Frozenfoo:BAAANQADCgIIAgAAAA==.',
Fu='Furlock:BAABNQAECn8dAAIDAAgKpRnJBQDgAQADAAgKpRnJBQDgAQAAAA==.',
Ga='Gabriel:BAACNQAFFH8JAAIXAAMKwwX6CQBiAAAXAAMKwwX6CQBiAAA1AAQKf2wAAxcACgqPF1oQAOgBABcACgqPF1oQAOgBAAkAAgoAAGzAASgAAAAA.Galicia:BAAANQAECgcIEwAAAA==.Gantaris:BAABNQAECn8mAAMaAAoKQhHAFQAnAgAaAAoKQhHAFQAnAgAZAAEKAADClgAAAAAAAA==.Garbagevoker:BAAANQAECgIIAgAAAA==.Gaymer:BAAANQAECgQIBwABNQAECgUIDwAMAAAAAA==.',
Gi='Gir:BAABNQAECn8gAAINAAgKUxueBAD3AQANAAgKUxueBAD3AQAAAA==.',
Gl='Glochese:BAAANQADCggIDwABNQAECgkJKgASALEdAA==.Glurp:BAAANQAECgYIDAAAAA==.',
Go='Gochese:BAABNQAECn8qAAMSAAkKsR1oKwC6AgASAAkKsR1oKwC6AgAJAAcKjgnc1gDuAAAAAA==.Gorgeous:BAAANQAECgYIBgABNQAECggIEQAMAAAAAA==.Gothel:BAAANQAECgUIBQAAAA==.',
Gr='Grace:BAAANQAECgcIDAAAAA==.Greenseer:BAAANQAECgcIDwAAAA==.',
Gt='Gtoffmyd:BAAANQADCgIIAgABNQAECgUIBgAMAAAAAA==.Gtoffmydruid:BAAANQAECgUIBgAAAA==.Gtoffmyface:BAAANQADCgUIBQABNQAECgUIBgAMAAAAAA==.',
Gw='Gwaralmighty:BAABNQAECn9HAAIIAAoK7x+bAwCgAgAIAAoK7x+bAwCgAgAAAA==.',
Gy='Gypo:BAAANQADCggIFgAAAA==.',
Ha='Haagen:BAABNQAECn8tAAIGAAoKzQ54YAC/AQAGAAoKzQ54YAC/AQAAAA==.Hamsup:BAABNQAECn8qAAIHAAoKdxQThAARAgAHAAoKdxQThAARAgAAAA==.Hatch:BAAANQADCgcICAABNQAECggIFwATAHkbAA==.',
['Hô']='Hôldem:BAEBNQAECn8rAAIZAAgKVw91RwDOAQAZAAgKVw91RwDOAQAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAABNQAECn8xAAIBAAoKFxTgVwDjAQABAAoKFxTgVwDjAQAAAA==.Ifrite:BAAANQAECgUIBQAAAA==.',
Ik='Ikur:BAAANQAECgYICwABNQAECgoKNwASAJ8cAA==.',
Im='Imbasoul:BAAANQADCgMIAwAAAA==.Imyerchese:BAAANQADCggIDgABNQAECgkJKgASALEdAA==.',
Jo='Jontalo:BAAANQADCgcIDgAAAA==.Jormi:BAABNQAECn8cAAIHAAcK1B9+XAB2AgAHAAcK1B9+XAB2AgAAAA==.',
Ju='Justthetipp:BAAANQAECgcICgAAAA==.',
Ka='Kaerlyn:BAAANQADCgYIDQAAAA==.Kaihu:BAAANQAECgQIBAAAAA==.Kalthael:BAAANQABCgYICQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECn8tAAMUAAoKSRz+CAC+AgAUAAoKSRz+CAC+AgAaAAQKNRhRTADdAAAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECn8YAAIWAAgKLBzqHQBRAgAWAAgKLBzqHQBRAgABNQAFFAcIGgAYACkdAA==.',
Ko='Kochese:BAAANQAECgUIBQABNQAECgkJKgASALEdAA==.',
Ku='Kutar:BAAANQAECgQIBgAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lochese:BAAANQADCgYIEgABNQAECgkJKgASALEdAA==.Lockme:BAAANQAECgcICgABNQAFFAcIHwABAJ0aAA==.Lotei:BAAANQADCgMIAwAAAA==.',
Ma='Magicdro:BAAANQADCgQIBAAAAA==.Magorrak:BAAANQAECgUICQAAAA==.Mal:BAACNQAFFH8YAAMcAAcKth4RAgBQAQAcAAYKqCIRAgBQAQAdAAIK8Q4+HQBYAAA1AAQKfygAAx0ACgoMJGMHAC4DAB0ACgpdImMHAC4DABwABAp7JtooAN8AAAAA.Marxwomun:BAAANQAECgUIBQAAAA==.Mary:BAACNQAFFH8XAAIcAAYKYh8kAQDIAQAcAAYKYh8kAQDIAQA1AAQKfysAAhwACgpCJIEHAFsDABwACgpCJIEHAFsDAAAA.',
Mc='Mcshammer:BAAANQAECgQIDAAAAA==.',
Me='Medis:BAAANQADCgcICwAAAA==.Mero:BAAANQAECgQICAAAAA==.Metal:BAABNQAECn8qAAIeAAgKrxkiAwAbAgAeAAgKrxkiAwAbAgAAAA==.',
Mi='Minervajt:BAABNQAECn8jAAIBAAoKXRJASwAGAgABAAoKXRJASwAGAgAAAA==.Miorine:BAACNQAFFH8PAAMBAAUKZRVNIACFAQABAAUKZRVNIACFAQAEAAEKzwKuFgA4AAA1AAQKfy4AAgEACgpHHtM1AB4DAAEACgpHHtM1AB4DAAAA.Mistbehavin:BAACNQAFFH8OAAITAAYKjxPLBQAVAQATAAYKjxPLBQAVAQA1AAQKf0YAAhMACgpOH88DAGwCABMACgpOH88DAGwCAAAA.',
Mo='Moginndar:BAABNQAECn8nAAMXAAkKDg8DKQCVAQAXAAkKUg4DKQCVAQAJAAUKhg95AwEZAQAAAA==.Mok:BAAANQAFFAIIBAAAAA==.Moochese:BAAANQAECgUIEgABNQAECgkJKgASALEdAA==.',
Mu='Muggsy:BAAANQAECgIIAgAAAA==.Munidar:BAABNQAECn8dAAIfAAgKPQgZFgBsAQAfAAgKPQgZFgBsAQAAAA==.',
My='Mytz:BAAANQAECgMIAwAAAA==.',
['Mï']='Mïnna:BAABNQAECn8wAAMLAAoKaSL/EAAvAwALAAoKvSD/EAAvAwAKAAcK4R1qMwARAgABNQAFFAMICAAZAB4PAA==.',
Ne='Nemisai:BAAANQADCggIEwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAABNQAECn8lAAMgAAkKZAkaCwAZAQAgAAkKPgkaCwAZAQAhAAYKCQNTFwCYAAAAAA==.',
Or='Orionbtch:BAAANQADCgYIDgAAAA==.',
Ov='Overheat:BAABNQAECn8YAAIBAAkKURRp3QDNAQABAAkKURRp3QDNAQAAAA==.',
Pa='Papi:BAAANQADCgcIBwAAAA==.',
Po='Poppy:BAAANQAECggIEQAAAA==.Portinglol:BAAANQAECgEIAQABNQAECgoKJAARACIdAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAABNQAECn8kAAMJAAoKNxgQiQAVAgAJAAoKNxgQiQAVAgASAAEKXwvh3wAzAAAAAA==.',
Qu='Qué:BAAANQABCgUIBQAAAA==.',
Ra='Ratidari:BAABNQAECn8UAAIiAAYKthl9MwCmAQAiAAYKthl9MwCmAQAAAA==.Ratshifter:BAABNQAECn8cAAMUAAgKKRZ4EgDWAQAUAAcK3Bh4EgDWAQAZAAcKtgonSADQAAABNQAECgYIFAAiALYZAA==.Ravenstorm:BAAANQAECgQIBAAAAA==.',
Re='Red:BAAANQAECgQIBQABNQAECgoKKAAZALMUAA==.Remmîngton:BAAANQAECgUICwAAAA==.Retbulls:BAABNQAECn8wAAIJAAoK1CJ9HwDDAgAJAAoK1CJ9HwDDAgAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAACNQAFFH8IAAIRAAMKTRHuFQDEAAARAAMKTRHuFQDEAAA1AAQKfzcAAxEACgqRHVwaAAcDABEACgqRHVwaAAcDABsAAQoAAKsGAQAAAAAA.',
Ru='Runslikedeer:BAABNQAECn8uAAIaAAgKdRrWFwAJAgAaAAgKdRrWFwAJAgAAAA==.Runé:BAAANQAECgEIAQABNQAECgQICQAMAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAACNQAFFH8OAAMBAAYK2w4vLQAmAQABAAUKVw4vLQAmAQAEAAIKYQqADABaAAA1AAQKf0MAAwEACgqpH0MvAGUCAAEACgqpH0MvAGUCAAQAAgr6Ez4xAEcAAAAA.Serah:BAACNQAFFH8MAAIjAAYKtwsmDwAWAQAjAAYKtwsmDwAWAQA1AAQKfy0AAyMACgoAFi84APABACMACQoAFi84APABACIACArWB/M5AHYBAAAA.Sevia:BAAANQAECgIIBAAAAA==.',
Sh='Sheppy:BAAANQAECgYIDQAAAA==.Shimakaze:BAABNQAECn8VAAMLAAgK9B1IHADiAgALAAgK9B1IHADiAgAPAAQKZBXVggDxAAABNQAFFAUIDwABAGUVAA==.Shizaam:BAACNQAFFH8OAAMRAAYKkhHcEgAkAQARAAYKkhHcEgAkAQAbAAMKtAkCHQDXAAA1AAQKfzkAAxsACgrfIncgAAkDABsACQpsIncgAAkDABEACQp+HP8uAKUCAAAA.Shlommy:BAABNQAECn8bAAMCAAcKmQ/okQC6AQACAAcKmQ/okQC6AQAFAAEKmwCFigAOAAAAAA==.',
Si='Silvaran:BAAANQABCgIIAgAAAA==.Silvermage:BAACNQAFFH8fAAIBAAcKnRpyCQAyAgABAAcKnRpyCQAyAgA1AAQKfzAAAgEACgo2JTURAPUCAAEACgo2JTURAPUCAAAA.Sinfxl:BAAANQAECgQICQAAAA==.Sinheph:BAAANQAECgUIBwAAAA==.Sippinsizurp:BAABNQAECn8hAAIBAAkKLB9lSwDrAgABAAkKLB9lSwDrAgAAAA==.',
Sk='Skullmages:BAABNQAECn8qAAIJAAoK3h9RJAA0AwAJAAoK3h9RJAA0AwAAAA==.',
Sl='Slayur:BAAANQAECgcICAAAAA==.Sloppydro:BAABNQAECn88AAMSAAoKVxR3LwAyAgASAAoKVxR3LwAyAgAJAAIKdwWAhQFSAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAgAAAA==.',
So='Socksimus:BAAANQADCgcIGAAAAA==.Sockssham:BAAANQADCggICAAAAA==.Sotari:BAAANQADCggICAAAAA==.',
St='Stabberz:BAACNQAFFH8HAAIcAAQKsRF0BADmAAAcAAQKsRF0BADmAAA1AAQKf08AAhwACgpUIZgKADYDABwACgpUIZgKADYDAAAA.Stannane:BAAANQADCgUICQABNQAECgUICgAMAAAAAA==.Stellaloona:BAAANQAECgIIAgAAAA==.Sticks:BAAANQADCgcICQAAAA==.Stinkyhooves:BAEANQADCgQIBgABNQAECggICAAMAAAAAA==.Stromboli:BAAANQADCgUIBQABNQAECgUIBwAMAAAAAA==.',
Su='Sushiroll:BAABNQAECn8kAAMRAAoKIh18EAAQAwARAAoKIh18EAAQAwAbAAUKERfGngBZAQAAAA==.',
Sw='Sweetsourrex:BAAANQAECgUIBAABNQAECgoKTQAdAOkhAA==.',
Ta='Tamaqua:BAABNQAECn8aAAIRAAgKlxJFhACAAQARAAgKlxJFhACAAQAAAA==.Tatisjr:BAAANQAECgIIAwABNQAECgMIAwAMAAAAAA==.',
Te='Telissa:BAAANQAECgUIBQAAAA==.Temoin:BAAANQAECgQIBQAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAABNQAECn8aAAIEAAoKjBJPCgAlAgAEAAoKjBJPCgAlAgAAAA==.Throngler:BAAANQAECgcICQABNQAECgkJGgAOAM8RAA==.',
To='Toobrunner:BAAANQAECgcIDAAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAFFAYIDgARAJIRAA==.',
Va='Vampress:BAAANQAECgMIBAAAAA==.Variam:BAABNQAECn8jAAIGAAgKjhYFdwAhAgAGAAgKjhYFdwAhAgAAAA==.',
Ve='Velannis:BAABNQAECn8uAAQQAAoKUiDtBACvAgAQAAgKOh/tBACvAgAdAAkK9xraNwDbAQAcAAcKSRxQSQCeAQAAAA==.Verycheap:BAAANQADCgMIAwAAAA==.',
Vo='Voidangel:BAAANQAECgQIBwAAAA==.Vonder:BAAANQAECgQICAAAAA==.Voodooki:BAAANQAECgIIAgAAAA==.',
Vu='Vuo:BAABNQAECn8mAAIGAAkKCg7hZwCsAQAGAAkKCg7hZwCsAQAAAA==.',
Wi='Winze:BAAANQADCggIDgAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQAECgQIBAABNQAECgkJKgASALEdAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIDwAMAAAAAA==.',
Wu='Wuchese:BAAANQAECgMIAwABNQAECgkJKgASALEdAA==.',
Xf='Xfreshh:BAAANQAECgYICQAAAA==.',
Ya='Yamaa:BAAANQAECgcIDQABNQAFFAUIDAABAA0OAA==.Yamadono:BAABNQAECn8aAAMdAAoKzh7gDgDlAgAdAAkKnh7gDgDlAgAcAAUKxxw5NgCkAAABNQAFFAUIDAABAA0OAA==.Yamaknight:BAAANQAECgEIAQABNQAFFAUIDAABAA0OAA==.Yamalock:BAAANQAECgUIBQABNQAFFAUIDAABAA0OAA==.Yamá:BAAANQADCgcIBwABNQAFFAUIDAABAA0OAA==.Yamå:BAACNQAFFH8MAAIBAAUKDQ6GIQDWAAABAAUKDQ6GIQDWAAA1AAQKfy0AAgEACgpXIMdKAOwCAAEACgpXIMdKAOwCAAAA.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAABNQAECn8WAAMRAAYK+hvnYADrAQARAAYK+hvnYADrAQAbAAYKBQ8FkQB6AQABNQAECgkJKgASALEdAA==.',
Zo='Zortok:BAAANQAECggIDAAAAA==.',
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
