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

local lookup = {'Mage-Arcane','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Outlaw','DemonHunter-Devourer','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Druid-Feral','Priest-Holy','Priest-Shadow','Paladin-Protection','Monk-Windwalker','Druid-Balance','Druid-Restoration','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abeblinkin:BAABNQAECn8aAAIBAAcK8BHM6AC4AQABAAcK8BHM6AC4AQAAAA==.Aborlight:BAAANQAECgUIEQAAAA==.Abstract:BAAANQAECgYICwAAAA==.',
Ad='Adit:BAABNQAECn8iAAMCAAoK0wd+bgCOAQACAAoK0wd+bgCOAQADAAEKkAUAMgAmAAAAAA==.',
Af='Afrit:BAABNQAECn8hAAMBAAoKdhR/SQAxAgABAAoKdhR/SQAxAgAEAAEKPgSGUwAeAAAAAA==.',
Ai='Aiwass:BAABNQAECn8mAAIFAAoK4gVzDAD5AAAFAAoK4gVzDAD5AAAAAA==.',
Al='Alieah:BAAANQAECgYIEAAAAA==.Alorum:BAAANQADCggIEQABNQAECgoKLQAGAKEOAA==.Alphaomegaa:BAAANQAECgEIAQAAAA==.Alpharius:BAAANQAECgUIEwAAAA==.',
Am='Amacoozy:BAABNQAECn9MAAMHAAoKixghSwCoAgAHAAoKhxghSwCoAgAIAAMKmBmeGQDuAAAAAA==.Amathricus:BAABNQAECn8yAAIJAAoKaAqlpgCBAQAJAAoKaAqlpgCBAQAAAA==.',
Ar='Arms:BAACNQAFFH8WAAMKAAgKnxL7BADDAQAKAAgKnxL7BADDAQALAAEKAACUJgAtAAA1AAQKfygAAgoACgqAIbwZAHsCAAoACgqAIbwZAHsCAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQAECgQIBAAAAA==.',
At='Athena:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAEANQADCgIIAgABNQAECgcICgAMAAAAAA==.Auralei:BAAANQADCgUIBQABNQAECgUIFQADAJ0NAA==.',
Az='Azelia:BAAANQAECgQIBQABNQAECggIDwAMAAAAAA==.Azzy:BAAANQAECggIDwAAAA==.',
Be='Bellestri:BAABNQAECn80AAICAAkKVwWWoAAWAQACAAkKVwWWoAAWAQAAAA==.',
Bi='Bigb:BAABNQAECn8YAAQGAAYKtiHlsgBMAQAGAAYKLSDlsgBMAQANAAQKCiPpDAD/AAAOAAEKAAB3lwApAAABNQAECgcIBwAMAAAAAA==.Bigface:BAAANQAECggIEQAAAA==.Bigrod:BAACNQAFFH8JAAIPAAQKzwetIQBkAAAPAAQKzwetIQBkAAA1AAQKfysAAg8ACQo9FxIlANIBAA8ACQo9FxIlANIBAAAA.Binks:BAAANQAECgEIAgAAAA==.',
Bl='Black:BAABNQAECn8hAAIQAAgKFhizAgD1AQAQAAgKFhizAgD1AQAAAA==.Blasfoomous:BAACNQAFFH8OAAIPAAYKxRHLFgD2AAAPAAYKxRHLFgD2AAA1AAQKfzoAAg8ACgpAIE8RAI8CAA8ACgpAIE8RAI8CAAAA.Blazeitt:BAAANQAECgIIAgABNQAECgkJFQARALcgAA==.Blu:BAACNQAFFH8SAAISAAUKRx7sCQCwAQASAAUKRx7sCQCwAQA1AAQKfy4AAhIACgoSJNgOAEwDABIACgoSJNgOAEwDAAAA.',
Bo='Bochese:BAAANQAECgUICwABNQAECgoKNAATABUfAA==.',
Br='Brochese:BAAANQAECgYIDwABNQAECgoKNAATABUfAA==.',
Bu='Bubblewrap:BAAANQAECgIIAwABNQAFFAYIDgAUAI8TAA==.Budfoster:BAAANQADCggIEAAAAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQAECgQICgABNQAECgcIGgABAPARAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Ch='Cheyeon:BAAANQAECgEIAQAAAA==.',
Cl='Classcarry:BAABNQAECn8bAAMJAAkKah93fwAqAgAJAAkKah93fwAqAgATAAUKkhPvvAACAQABNQAECgoKJAASACIdAA==.Claybigsby:BAACNQAFFH8OAAMFAAYKPRnbCwChAAACAAQKUBsWIgCoAAAFAAIKIRbbCwChAAA1AAQKfy8AAwIACgr+H2tuABMCAAIACAoZIGtuABMCAAUABArXGv4vAAkBAAAA.Clif:BAAANQAFFAEIAQAAAA==.',
Co='Collie:BAEBNQAECn8vAAIVAAoKdiXzAABzAwAVAAoKdiXzAABzAwAAAA==.Constantina:BAABNQAECn8+AAIWAAkKbxYBSwBEAgAWAAkKbxYBSwBEAgAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQAECgMIAwAAAA==.',
Cy='Cyleste:BAABNQAECn8iAAMXAAoKBwtxLADCAQAXAAoKBwtxLADCAQAWAAUK0wzyxADPAAAAAA==.',
De='Deadlylady:BAAANQADCgUICAAAAA==.Demonifrita:BAAANQADCggICwAAAA==.Demonlady:BAAANQADCggIEAAAAA==.Deo:BAABNQAECn8qAAMTAAoKFxQXMABhAgATAAoKFxQXMABhAgAYAAkKZxbzGQCkAQAAAA==.Derpy:BAABNQAECn8dAAMUAAoKgQm+DQBOAQAUAAoKgQm+DQBOAQAZAAYKsQPqTQC/AAAAAA==.',
Dh='Dheevix:BAAANQAECgcIDwABNQAECgoKNAABACYbAA==.',
Dj='Djheals:BAAANQAECgMIAwABNQAECgoKHwAaACwLAA==.Djmuphasa:BAABNQAECn8fAAMaAAoKLAvfMwBuAQAaAAoKLAvfMwBuAQAbAAUKbgW3VQCiAAAAAA==.Djthrasher:BAAANQAECgQIBgABNQAECgoKHwAaACwLAA==.',
Dr='Drachese:BAAANQAECgcIBwABNQAECgoKNAATABUfAA==.Dripps:BAAANQAECgQIAwABNQAECgUICAAMAAAAAA==.Druchese:BAABNQAECn8pAAMbAAkKIhvqGABMAgAbAAkKIhvqGABMAgAaAAcKjQ1sYwBAAQABNQAECgoKNAATABUfAA==.',
Dv='Dvorak:BAAANQAECgEIAQAAAA==.',
Ea='Eagleeye:BAABNQAECn8dAAIJAAgK/Ql12gBmAQAJAAgK/Ql12gBmAQAAAA==.',
Em='Emsley:BAACNQAFFH8FAAIcAAMKoAXeIQByAAAcAAMKoAXeIQByAAA1AAQKf1MAAhwACgp0F6hFAF8CABwACgp0F6hFAF8CAAAA.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQAECgQICAAAAA==.',
Ev='Ev:BAABNQAECn8XAAMUAAgKeRuYDQAgAgAUAAUKSCaYDQAgAgAZAAcK7hCWOQBHAQAAAA==.',
Ex='Exo:BAACNQAFFH8HAAIBAAQKlAycLgAbAQABAAQKlAycLgAbAQA1AAQKfyIAAwEACgrYH0d3AI8CAAEACgrDHUd3AI8CAAQAAgrQIQwwAH8AAAAA.',
Fa='Falorin:BAAANQAECgEIAQAAAA==.',
Fl='Floudwing:BAAANQABCgYIDAAAAA==.',
Fn='Fnwarriors:BAAANQADCgcICAAAAA==.',
Fo='Focalors:BAAANQAECgcIDwABNQAFFAUIDwABAGUVAA==.Foobear:BAAANQAECgcIEAABNQAFFAYIDgAPAMURAA==.',
Fr='Franchescold:BAAANQAECggIDQAAAA==.Frozenfoo:BAAANQADCgIIAgAAAA==.',
Fu='Furlock:BAABNQAECn8dAAIDAAgKpRlEBwAsAgADAAgKpRlEBwAsAgAAAA==.',
Ga='Gabriel:BAACNQAFFH8JAAIYAAMKwwXQDABiAAAYAAMKwwXQDABiAAA1AAQKf3EAAxgACgobGRgSAAoCABgACgobGRgSAAoCAAkAAgoAAGzAASgAAAAA.Galicia:BAABNQAECn8VAAIUAAgKdgvXEQAJAQAUAAgKdgvXEQAJAQAAAA==.Gantaris:BAABNQAECn8qAAMbAAoKQhFHHAAlAgAbAAoKQhFHHAAlAgAaAAEKAAAuqQAAAAAAAA==.Garbagevoker:BAAANQAECgIIAgAAAA==.Gaymer:BAAANQAECgQIBwABNQAECgUIDwAMAAAAAA==.',
Ge='Gethan:BAAANQABCgQIBAAAAA==.',
Gi='Gir:BAABNQAECn8mAAINAAkKSRwFBABUAgANAAkKSRwFBABUAgAAAA==.',
Gl='Glochese:BAAANQADCggIDwABNQAECgoKNAATABUfAA==.Glurp:BAAANQAECgYIDAAAAA==.',
Go='Gochese:BAABNQAECn80AAMTAAoKFR85FQAPAwATAAoKFR85FQAPAwAJAAcKjgm19gD4AAAAAA==.Gorgeous:BAAANQAECgYIBgABNQAECggIEQAMAAAAAA==.Gothel:BAAANQAECgUIBQAAAA==.',
Gr='Grace:BAAANQAECgcIDAAAAA==.Greenseer:BAAANQAECgcIDwAAAA==.',
Gt='Gtoffmyd:BAAANQADCgIIAgABNQAECgYIBwAMAAAAAA==.Gtoffmydruid:BAAANQAECgYIBwAAAA==.Gtoffmyface:BAAANQADCgUIBQABNQAECgYIBwAMAAAAAA==.',
Gw='Gwaralmighty:BAACNQAFFH8FAAIIAAIKwhduAgCTAAAIAAIKwhduAgCTAAA1AAQKf1UAAggACgppIn4CAAEDAAgACgppIn4CAAEDAAAA.',
Gy='Gypo:BAAANQADCggIFgAAAA==.',
Ha='Haagen:BAABNQAECn84AAIGAAoK7hD2aQDvAQAGAAoK7hD2aQDvAQAAAA==.Hamsup:BAABNQAECn8qAAIHAAoKdxQThAARAgAHAAoKdxQThAARAgAAAA==.Hatch:BAAANQAECgQIBAABNQAECggIFwAUAHkbAA==.',
Ho='Horsdoeuvres:BAAANQAECgUIBQAAAA==.',
['Hô']='Hôldem:BAEBNQAECn8rAAIaAAgKVw91RwDOAQAaAAgKVw91RwDOAQAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAABNQAECn85AAIBAAoKYBWmXAAAAgABAAoKYBWmXAAAAgAAAA==.Ifrite:BAAANQAECgcIBwAAAA==.',
Ik='Ikur:BAAANQAECgYICwABNQAECgoKPQATAFggAA==.',
Im='Imbasoul:BAAANQADCgMIAwAAAA==.Imsoprotty:BAAANQAECggIAgAAAA==.Imyerchese:BAAANQAECgEIAQABNQAECgoKNAATABUfAA==.',
Ji='Jillidan:BAAANQAECgEIAQAAAA==.',
Jo='Jontalo:BAAANQADCgcIDgAAAA==.Jormi:BAABNQAECn8cAAIHAAcK1B9+XAB2AgAHAAcK1B9+XAB2AgAAAA==.',
Ju='Justthetipp:BAABNQAECn8UAAIdAAkK2wgqbwBcAQAdAAkK2wgqbwBcAQAAAA==.',
Ka='Kaerlyn:BAAANQADCgYIDgAAAA==.Kaihu:BAAANQAECgQIBAAAAA==.Kalthael:BAAANQABCgYICQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECn8wAAMVAAoK+x3+CAC+AgAVAAoK+x3+CAC+AgAbAAQKNRhRTADdAAAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECn8YAAIXAAgKLBzqHQBRAgAXAAgKLBzqHQBRAgABNQAFFAcIGgAZACkdAA==.',
Ko='Kochese:BAAANQAECgUIBQABNQAECgoKNAATABUfAA==.',
Ku='Kutar:BAAANQAECgQIBgAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lochese:BAAANQADCgYIEgABNQAECgoKNAATABUfAA==.Lockme:BAAANQAECgcICgABNQAFFAgIIAABAF0cAA==.Lotei:BAAANQADCgMIAwAAAA==.',
Ma='Magicdro:BAAANQADCgQIBAAAAA==.Magorrak:BAAANQAECgUICQAAAA==.Mal:BAACNQAFFH8aAAMeAAgKOB1KAgCiAQAeAAcKEyBKAgCiAQAdAAIK8Q4SJABYAAA1AAQKfywAAx0ACgoMJO8IADIDAB0ACgpdIu8IADIDAB4ABAp7JmARALMBAAAA.Marxwomun:BAAANQAECgUIBgAAAA==.Mary:BAACNQAFFH8XAAIeAAYKYh8xAgCuAQAeAAYKYh8xAgCuAQA1AAQKfywAAh4ACgpCJIEHAFsDAB4ACgpCJIEHAFsDAAAA.',
Mc='Mcshammer:BAAANQAECgQIDAAAAA==.',
Me='Medis:BAAANQADCggIHAAAAA==.Mero:BAAANQAECgQIDAAAAA==.Metal:BAABNQAECn8wAAIfAAgKWB0xAwBhAgAfAAgKWB0xAwBhAgAAAA==.',
Mi='Minervajt:BAABNQAECn8xAAIBAAoKbBmDMgB3AgABAAoKbBmDMgB3AgAAAA==.Miorine:BAACNQAFFH8PAAMBAAUKZRVNIACFAQABAAUKZRVNIACFAQAEAAEKzwKuFgA4AAA1AAQKfz4AAwEACgqLIw0MACgDAAEACgqLIw0MACgDAAQAAQp8H4czAF0AAAAA.Mistbehavin:BAACNQAFFH8OAAIUAAYKjxPLBQAVAQAUAAYKjxPLBQAVAQA1AAQKf0cAAhQACgq3H74EAGgCABQACgq3H74EAGgCAAAA.',
Mo='Moginndar:BAABNQAECn8nAAMYAAkKDg8DKQCVAQAYAAkKUg4DKQCVAQAJAAUKhg95AwEZAQAAAA==.Mok:BAABNQAFFH8GAAISAAMKlgwmHADCAAASAAMKlgwmHADCAAAAAA==.Moochese:BAABNQAECn8hAAMWAAgKKRsxRgAfAgAWAAgKKRsxRgAfAgAXAAYKbwVMRQCXAAABNQAECgoKNAATABUfAA==.',
Mu='Muggsy:BAAANQAECgIIAgAAAA==.Munidar:BAABNQAECn8dAAIgAAgKPQj2GgBqAQAgAAgKPQj2GgBqAQAAAA==.',
My='Mytz:BAAANQAECgcICgAAAA==.',
['Mï']='Mïnna:BAABNQAECn82AAMLAAoKaSL/EAAvAwALAAoKvSD/EAAvAwAKAAgKYB++NADRAQABNQAFFAQICgAaAM8QAA==.',
Ne='Nemisai:BAAANQADCggIEwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAABNQAECn8sAAMhAAoKewlSCwBJAQAhAAoKWglSCwBJAQAiAAYKCQPZGgCWAAAAAA==.',
Or='Orionbtch:BAAANQADCgYIDwAAAA==.',
Ov='Overheat:BAABNQAECn8bAAIBAAkKsBbmqQBQAQABAAkKsBbmqQBQAQAAAA==.',
Pa='Papi:BAAANQADCgcIBwAAAA==.',
Po='Poppy:BAABNQAECn8ZAAIEAAoKkQqrEACEAQAEAAoKkQqrEACEAQAAAA==.Portinglol:BAAANQAECgEIAQABNQAECgoKJAASACIdAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAACNQAFFH8FAAMJAAIKxRC0JACJAAAJAAIKxRC0JACJAAATAAEKZAGBLAAtAAA1AAQKfyoAAwkACgrdG8tDAF4CAAkACgrdG8tDAF4CABMAAQpfCyf4ADMAAAAA.',
Qu='Qué:BAAANQABCgUIBQAAAA==.',
Ra='Ratidari:BAABNQAECn8UAAIRAAYKthl9MwCmAQARAAYKthl9MwCmAQAAAA==.Ratshifter:BAABNQAECn8hAAMVAAoK2RiCDAAKAgAVAAoK2RiCDAAKAgAaAAcKtgp2VADNAAABNQAECgYIFAARALYZAA==.Ravenstorm:BAAANQAECgQIBAAAAA==.',
Re='Red:BAAANQAECgQIBQABNQAECgoKKAAaALMUAA==.Remmîngton:BAAANQAECgUICwAAAA==.Retbulls:BAABNQAECn8yAAIJAAoKBSN7KgC4AgAJAAoKBSN7KgC4AgAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAACNQAFFH8OAAISAAQKGRF/FQAOAQASAAQKGRF/FQAOAQA1AAQKfz0AAxIACgooHlwaAAcDABIACgooHlwaAAcDABwAAgqlEhnwAEAAAAAA.',
Ru='Runslikedeer:BAABNQAECn9BAAIbAAkKEx2aDAAAAwAbAAkKEx2aDAAAAwAAAA==.Runé:BAAANQAECgEIAQABNQAECgQICQAMAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAACNQAFFH8OAAMBAAYK2w4vLQAmAQABAAUKVw4vLQAmAQAEAAIKYQoMEQBRAAA1AAQKf0QAAwEACgqpHyxGAPcCAAEACgqpHyxGAPcCAAQAAgr6E9c6AEQAAAAA.Serah:BAACNQAFFH8MAAIjAAYKtwsmDwAWAQAjAAYKtwsmDwAWAQA1AAQKfy8AAyMACgq5FzQtAKkBACMACQq5FzQtAKkBABEACArWB/M5AHYBAAAA.Sevia:BAAANQAECgIIBAAAAA==.',
Sh='Sheppy:BAAANQAECgYIDwAAAA==.Shimakaze:BAABNQAECn8XAAMLAAkK9B1IHADiAgALAAkK9B1IHADiAgAPAAQKZBXVggDxAAABNQAFFAUIDwABAGUVAA==.Shizaam:BAACNQAFFH8OAAMSAAYKkhHcEgAkAQASAAYKkhHcEgAkAQAcAAMKtAkCHQDXAAA1AAQKfzoAAxwACgr6IncgAAkDABwACQpsIncgAAkDABIACQp+HP8uAKUCAAAA.Shlommy:BAABNQAECn8bAAMCAAcKmQ/okQC6AQACAAcKmQ/okQC6AQAFAAEKmwCFigAOAAAAAA==.Shmorc:BAAANQAECgIIAQABNQAFFAgIIAABAF0cAA==.',
Si='Silvaran:BAAANQABCgIIAgAAAA==.Silvermage:BAACNQAFFH8gAAIBAAgKXRxyCQAyAgABAAgKXRxyCQAyAgA1AAQKfzEAAgEACgo2JbQWAO0CAAEACgo2JbQWAO0CAAAA.Sinfxl:BAAANQAECgQICQAAAA==.Sinheph:BAAANQAECgUIBwAAAA==.Sippinsizurp:BAABNQAECn8hAAIBAAkKLB9lSwDrAgABAAkKLB9lSwDrAgAAAA==.',
Sk='Skullmages:BAABNQAECn8qAAIJAAoK3h9RJAA0AwAJAAoK3h9RJAA0AwAAAA==.',
Sl='Slayur:BAAANQAECgcICAAAAA==.Sloppydro:BAABNQAECn9DAAMTAAoKCBWSNwA9AgATAAoKCBWSNwA9AgAJAAIKdwWAhQFSAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAgAAAA==.',
So='Socksimus:BAAANQADCgcIGAAAAA==.Sockssham:BAAANQADCggICAAAAA==.Sotari:BAAANQADCggICAAAAA==.',
St='Stabberz:BAACNQAFFH8IAAIeAAUKsRHMBgDgAAAeAAUKsRHMBgDgAAA1AAQKf1YAAh4ACgpnIZgKADYDAB4ACgpnIZgKADYDAAAA.Stannane:BAAANQADCgUICQABNQAECgYIDwAMAAAAAA==.Stellaloona:BAAANQAECgIIAgAAAA==.Sticks:BAAANQADCgcICQAAAA==.Stinkyhooves:BAEANQADCgQIBgABNQAECgcICgAMAAAAAA==.Stromboli:BAAANQADCgUIBQABNQAECgUIBwAMAAAAAA==.',
Su='Sushiroll:BAABNQAECn8kAAMSAAoKIh1lFwD7AgASAAoKIh1lFwD7AgAcAAUKERfGngBZAQAAAA==.',
Sw='Sweetsourrex:BAAANQAECgUIBAABNQAECgoKUAAdAOkhAA==.',
Ta='Tamaqua:BAABNQAECn8iAAISAAoKAxefWwCnAQASAAoKAxefWwCnAQAAAA==.Tatisjr:BAAANQAECgUICAAAAA==.',
Te='Telissa:BAAANQAECgcIDAAAAA==.Temoin:BAAANQAECgQIBQAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAABNQAECn8eAAIEAAoK7hJPCgAlAgAEAAoK7hJPCgAlAgAAAA==.Throngler:BAABNQAECn8bAAIJAAoK7BFdZgAEAgAJAAoK7BFdZgAEAgAAAA==.',
To='Toobrunner:BAAANQAECgcIDAAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAFFAYIDgASAJIRAA==.',
Va='Vampress:BAAANQAECgQICAAAAA==.Variam:BAABNQAECn8kAAIGAAkKihd2bQDnAQAGAAkKihd2bQDnAQAAAA==.',
Ve='Velannis:BAABNQAECn8uAAQQAAoKUiDtBACvAgAQAAgKOh/tBACvAgAdAAkK9xr6RwDgAQAeAAcKSRxQSQCeAQAAAA==.Verycheap:BAAANQAECgQICAAAAA==.',
Vo='Voidangel:BAAANQAECgQIBwAAAA==.Vonder:BAAANQAECgQIDAAAAA==.Voodooki:BAAANQAECgMIBQAAAA==.',
Vu='Vuo:BAABNQAECn8tAAIGAAoKoQ5DYQAEAgAGAAoKoQ5DYQAEAgAAAA==.',
We='Werewolf:BAAANQADCgEIAQABNQAECgoKLQALAN4MAA==.',
Wi='Winze:BAAANQADCggIDgAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQAECgYICgABNQAECgoKNAATABUfAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIDwAMAAAAAA==.',
Wu='Wuchese:BAAANQAECgYIBQABNQAECgoKNAATABUfAA==.',
Xf='Xfreshh:BAAANQAECgYICQAAAA==.',
Ya='Yamaa:BAAANQAECgcIDQABNQAFFAYIDgABAJwRAA==.Yamadin:BAAANQAECgQIBQABNQAFFAYIDgABAJwRAA==.Yamadono:BAABNQAECn8cAAMdAAoKzh40EgDmAgAdAAkKnh40EgDmAgAeAAUKxxxzOwCeAAABNQAFFAYIDgABAJwRAA==.Yamaknight:BAAANQAECgEIAQABNQAFFAYIDgABAJwRAA==.Yamalock:BAAANQAECgYIBgABNQAFFAYIDgABAJwRAA==.Yamá:BAAANQADCgcIBwABNQAFFAYIDgABAJwRAA==.Yamå:BAACNQAFFH8OAAIBAAYKnBFNGgAiAQABAAYKnBFNGgAiAQA1AAQKfy8ABAEACgrRIMdKAOwCAAEACgpXIMdKAOwCAAQAAQpsHiQ0AFsAACQAAQoZBBgPACAAAAAA.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAABNQAECn8YAAMSAAgK0BznYADrAQASAAgK0BznYADrAQAcAAYKBQ8FkQB6AQABNQAECgoKNAATABUfAA==.',
Zo='Zortok:BAAANQAECggIDQAAAA==.',
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
