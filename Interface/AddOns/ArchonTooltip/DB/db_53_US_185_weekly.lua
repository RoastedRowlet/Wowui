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

local lookup = {'Mage-Arcane','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Warlock-Destruction','Hunter-BeastMastery','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Outlaw','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Druid-Feral','Priest-Holy','Priest-Shadow','Paladin-Protection','Monk-Windwalker','Druid-Balance','Druid-Restoration','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abeblinkin:BAABNQAECn8aAAIBAAcK8BHM6AC4AQABAAcK8BHM6AC4AQAAAA==.Aborlight:BAAANQAECgUIEQAAAA==.Abstract:BAAANQAECgcIDQAAAA==.',
Ad='Adit:BAABNQAECn8cAAMCAAoKageFaQCGAQACAAoKageFaQCGAQADAAEKkAWMLgAmAAAAAA==.',
Af='Afrit:BAABNQAECn8gAAMBAAkK+BKwZQDZAQABAAkK+BKwZQDZAQAEAAEKPgSGUwAeAAAAAA==.',
Ai='Aiwass:BAABNQAECn8mAAIFAAoK4gUgCwD9AAAFAAoK4gUgCwD9AAAAAA==.',
Al='Alieah:BAAANQAECgYIEQAAAA==.Alorum:BAAANQAECgEIAQABNQAECgoKKAAGAH8OAA==.Alphaomegaa:BAAANQAECgEIAQAAAA==.Alpharius:BAABNQAECn8UAAIHAAYKSBNyGgA6AQAHAAYKSBNyGgA6AQAAAA==.',
Am='Amacoozy:BAABNQAECn9IAAMIAAkK7RkhSwCoAgAIAAkK6RkhSwCoAgAJAAMKmBlEFwDwAAAAAA==.Amathricus:BAABNQAECn8uAAIKAAkKvgk3xgAyAQAKAAkKvgk3xgAyAQAAAA==.',
Ar='Arms:BAACNQAFFH8VAAMLAAcK8xT7BADDAQALAAcK8xT7BADDAQAMAAEKAACUJgAtAAA1AAQKfygAAgsACgqAISwXAIICAAsACgqAISwXAIICAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQAECgQIBAAAAA==.',
At='Athena:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAEANQADCgIIAgABNQAECggICQANAAAAAA==.Auralei:BAAANQADCgUIBQABNQAECgUIFQADAJ0NAA==.Austin:BAAANQAECgEIAQAAAA==.',
Az='Azelia:BAAANQAECgQIBQABNQAECggIEAANAAAAAA==.Azzy:BAAANQAECggIEAAAAA==.',
Be='Bellestri:BAABNQAECn80AAICAAkKVwWklgAXAQACAAkKVwWklgAXAQAAAA==.',
Bi='Bigb:BAABNQAECn8YAAQGAAYKtiHrogBRAQAGAAYKLSDrogBRAQAOAAQKCiPpDAD/AAAPAAEKAAB3lwApAAABNQAECgcIBwANAAAAAA==.Bigface:BAAANQAECggIEwAAAA==.Bigrod:BAACNQAFFH8JAAIQAAQKzwfzHQBqAAAQAAQKzwfzHQBqAAA1AAQKfysAAhAACQo9F10iANgBABAACQo9F10iANgBAAAA.Binks:BAAANQAECgEIBAAAAA==.',
Bl='Black:BAABNQAECn8hAAIRAAgKFhh4AgD3AQARAAgKFhh4AgD3AQAAAA==.Blasfoomous:BAACNQAFFH8OAAIQAAYKxRHLFgD2AAAQAAYKxRHLFgD2AAA1AAQKfzoAAhAACgpAIAgQAJYCABAACgpAIAgQAJYCAAAA.Blazeitt:BAAANQAECgIIAgABNQAECgcIEwANAAAAAA==.Blu:BAACNQAFFH8SAAISAAUKRx7sCQCwAQASAAUKRx7sCQCwAQA1AAQKfy4AAhIACgoSJNgOAEwDABIACgoSJNgOAEwDAAAA.',
Bo='Bochese:BAAANQAECgUICQABNQAECgoKMAATAKAeAA==.',
Br='Brochese:BAAANQAECgYIEAABNQAECgoKMAATAKAeAA==.',
Bu='Bubblewrap:BAAANQAECgIIAwABNQAFFAYIDgAUAI8TAA==.Budfoster:BAAANQADCggIEAAAAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQAECgQIDQABNQAECgcIGgABAPARAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Ch='Cheyeon:BAAANQAECgEIAQAAAA==.',
Cl='Classcarry:BAABNQAECn8bAAMKAAkKah93fwAqAgAKAAkKah93fwAqAgATAAUKkhPvvAACAQABNQAECgoKJAASACIdAA==.Claybigsby:BAACNQAFFH8OAAMFAAYKPRnbCwChAAACAAQKUBvpHQCtAAAFAAIKIRbbCwChAAA1AAQKfy8AAwIACgr+H2tuABMCAAIACAoZIGtuABMCAAUABArXGv4vAAkBAAAA.Clif:BAAANQAFFAEIAQAAAA==.',
Co='Collie:BAEBNQAECn8mAAIVAAoKJSQtAwAGAwAVAAoKJSQtAwAGAwAAAA==.Constantina:BAABNQAECn8+AAIWAAkKbxYBSwBEAgAWAAkKbxYBSwBEAgAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQAECgMIAwAAAA==.',
Cy='Cyleste:BAABNQAECn8hAAMXAAoKBwtxLADCAQAXAAoKBwtxLADCAQAWAAQK0Q3yxADPAAAAAA==.',
De='Deadlylady:BAAANQADCgUICAAAAA==.Demonifrita:BAAANQADCggICgAAAA==.Demonlady:BAAANQADCggIEAAAAA==.Deo:BAABNQAECn8hAAMYAAoKZxZSFwCpAQAYAAkKZxZSFwCpAQATAAQKWgyMoQDMAAAAAA==.Derpy:BAABNQAECn8cAAMUAAkKnQnhDgAkAQAUAAkKnQnhDgAkAQAZAAYKsQPqTQC/AAAAAA==.Devilsho:BAAANQAECggIAgAAAA==.',
Dh='Dheevix:BAAANQAECgYIDgABNQAECgoKNAABACYbAA==.',
Dj='Djheals:BAAANQAECgMIAwABNQAECgkJGwAaAOgMAA==.Djmuphasa:BAABNQAECn8bAAMaAAkK6AwTQAAUAQAaAAgK6QsTQAAUAQAbAAUKbgWPUACjAAAAAA==.Djthrasher:BAAANQAECgQIBgABNQAECgkJGwAaAOgMAA==.',
Dr='Drachese:BAAANQAECgUIBwABNQAECgoKMAATAKAeAA==.Dripps:BAAANQAECgQIAwABNQAECgQIBwANAAAAAA==.Druchese:BAABNQAECn8nAAMbAAgKhRswHAAIAgAbAAgKhRswHAAIAgAaAAYKMg5sYwBAAQABNQAECgoKMAATAKAeAA==.',
Dv='Dvorak:BAAANQAECgEIAQAAAA==.',
Ea='Eagleeye:BAABNQAECn8dAAIKAAgK/QkmyQAtAQAKAAgK/QkmyQAtAQAAAA==.',
Em='Emsley:BAACNQAFFH8FAAIcAAMKoAUPHwBzAAAcAAMKoAUPHwBzAAA1AAQKf1IAAhwACgp0F6hFAF8CABwACgp0F6hFAF8CAAAA.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQAECgQIBAAAAA==.',
Ev='Ev:BAABNQAECn8XAAMUAAgKeRuYDQAgAgAUAAUKSCaYDQAgAgAZAAcK7hCWOQBHAQAAAA==.',
Ex='Exo:BAACNQAFFH8HAAIBAAQKlAycLgAbAQABAAQKlAycLgAbAQA1AAQKfyIAAwEACgrYH0d3AI8CAAEACgrDHUd3AI8CAAQAAgrQIQwwAH8AAAAA.',
Fa='Falorin:BAAANQAECgEIAQAAAA==.',
Fl='Floudwing:BAAANQABCgYIDAAAAA==.',
Fn='Fnwarriors:BAAANQADCgcICAAAAA==.',
Fo='Focalors:BAAANQAECgcIDwABNQAFFAUIDwABAGUVAA==.Foobear:BAAANQAECgcIEAABNQAFFAYIDgAQAMURAA==.',
Fr='Franchescold:BAAANQAECggIDgAAAA==.Frozenfoo:BAAANQADCgIIAgAAAA==.',
Fu='Furlock:BAABNQAECn8dAAIDAAgKpRlEBwAsAgADAAgKpRlEBwAsAgAAAA==.',
Ga='Gabriel:BAACNQAFFH8JAAIYAAMKwwWnCwBiAAAYAAMKwwWnCwBiAAA1AAQKf3AAAxgACgodGakQAAoCABgACgodGakQAAoCAAoAAgoAAGzAASgAAAAA.Galicia:BAABNQAECn8VAAIUAAgKdguBEAAKAQAUAAgKdguBEAAKAQAAAA==.Gantaris:BAABNQAECn8qAAMbAAoKQhGAGQAoAgAbAAoKQhGAGQAoAgAaAAEKAACUoQAAAAAAAA==.Garbagevoker:BAAANQAECgIIAgAAAA==.Gaymer:BAAANQAECgQIBwABNQAECgUIDwANAAAAAA==.',
Gi='Gir:BAABNQAECn8kAAIOAAgKqBs1BQD8AQAOAAgKqBs1BQD8AQAAAA==.',
Gl='Glochese:BAAANQADCggIDwABNQAECgoKMAATAKAeAA==.Glurp:BAAANQAECgYIEQAAAA==.',
Go='Gochese:BAABNQAECn8wAAMTAAoKoB4iIgCfAgATAAoKoB4iIgCfAgAKAAcKjgm65wD7AAAAAA==.Gorgeous:BAAANQAECgYIBgABNQAECggIEwANAAAAAA==.Gothel:BAAANQAECgUIBwAAAA==.',
Gr='Grace:BAAANQAECgcIDAAAAA==.Greenseer:BAAANQAECgcIDwAAAA==.',
Gt='Gtoffmyd:BAAANQADCgIIAgABNQAECgYIBwANAAAAAA==.Gtoffmydruid:BAAANQAECgYIBwAAAA==.Gtoffmyface:BAAANQADCgUIBQABNQAECgYIBwANAAAAAA==.',
Gw='Gwaralmighty:BAABNQAECn9QAAIJAAoKsCGoAgDwAgAJAAoKsCGoAgDwAgAAAA==.',
Gy='Gypo:BAAANQADCggIFgAAAA==.',
Ha='Haagen:BAABNQAECn8vAAIGAAoKxRDFZgDeAQAGAAoKxRDFZgDeAQAAAA==.Hamsup:BAABNQAECn8qAAIIAAoKdxQThAARAgAIAAoKdxQThAARAgAAAA==.Hatch:BAAANQAECgQIBAABNQAECggIFwAUAHkbAA==.',
Ho='Horsdoeuvres:BAAANQAECgEIAQAAAA==.',
['Hô']='Hôldem:BAEBNQAECn8rAAIaAAgKVw91RwDOAQAaAAgKVw91RwDOAQAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAABNQAECn80AAIBAAoKYBWUWQD4AQABAAoKYBWUWQD4AQAAAA==.Ifrite:BAAANQAECgYIBwAAAA==.',
Ik='Ikur:BAAANQAECgYICwABNQAECgoKPQATAFggAA==.',
Im='Imbasoul:BAAANQADCgMIAwAAAA==.Imyerchese:BAAANQADCggIDgABNQAECgoKMAATAKAeAA==.',
Ji='Jillidan:BAAANQAECgIIAgAAAA==.',
Jo='Jontalo:BAAANQADCgcIDgAAAA==.Jormi:BAABNQAECn8cAAIIAAcK1B9+XAB2AgAIAAcK1B9+XAB2AgAAAA==.',
Ju='Justthetipp:BAAANQAECgcIEAAAAA==.',
Ka='Kaerlyn:BAAANQADCgYIDQAAAA==.Kaihu:BAAANQAECgQIBAAAAA==.Kalthael:BAAANQABCgYICQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECn8vAAMVAAoK9Bz+CAC+AgAVAAoK9Bz+CAC+AgAbAAQKNRhRTADdAAAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECn8YAAIXAAgKLBzqHQBRAgAXAAgKLBzqHQBRAgABNQAFFAcIGgAZACkdAA==.',
Ko='Kochese:BAAANQAECgUIBQABNQAECgoKMAATAKAeAA==.',
Ku='Kutar:BAAANQAECgQIBgAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lochese:BAAANQADCgYIEgABNQAECgoKMAATAKAeAA==.Lockme:BAAANQAECgcICgABNQAFFAcIHwABAJ0aAA==.Lotei:BAAANQADCgMIAwAAAA==.',
Ma='Magicdro:BAAANQADCgQIBAAAAA==.Magorrak:BAAANQAECgUICQAAAA==.Mal:BAACNQAFFH8aAAMdAAgKOB3QAQCnAQAdAAcKEyDQAQCnAQAeAAIK8Q4JIQBYAAA1AAQKfywAAx4ACgoMJD4IADMDAB4ACgpdIj4IADMDAB0ABAp7JmAQALUBAAAA.Marxwomun:BAAANQAECgUICAAAAA==.Mary:BAACNQAFFH8XAAIdAAYKYh+oAQC6AQAdAAYKYh+oAQC6AQA1AAQKfywAAh0ACgpCJIEHAFsDAB0ACgpCJIEHAFsDAAAA.',
Mc='Mcshammer:BAAANQAECgQIDAAAAA==.',
Me='Medis:BAAANQADCgcIEQAAAA==.Mero:BAAANQAECgQICAAAAA==.Metal:BAABNQAECn8wAAIfAAgKWB3kAgBmAgAfAAgKWB3kAgBmAgAAAA==.',
Mi='Minervajt:BAABNQAECn8pAAIBAAoKVBUVRAAzAgABAAoKVBUVRAAzAgAAAA==.Miorine:BAACNQAFFH8PAAMBAAUKZRVNIACFAQABAAUKZRVNIACFAQAEAAEKzwKuFgA4AAA1AAQKfzcAAgEACgppIDwYANwCAAEACgppIDwYANwCAAAA.Mistbehavin:BAACNQAFFH8OAAIUAAYKjxPLBQAVAQAUAAYKjxPLBQAVAQA1AAQKf0cAAhQACgq3H08EAGoCABQACgq3H08EAGoCAAAA.',
Mo='Moginndar:BAABNQAECn8nAAMYAAkKDg8DKQCVAQAYAAkKUg4DKQCVAQAKAAUKhg95AwEZAQAAAA==.Mok:BAABNQAFFH8GAAISAAMKlgx3GQDCAAASAAMKlgx3GQDCAAAAAA==.Moochese:BAABNQAECn8aAAMWAAYKfxfLdgC3AQAWAAYKfxfLdgC3AQAXAAYKbwXcQACXAAABNQAECgoKMAATAKAeAA==.',
Mu='Muggsy:BAAANQAECgIIAwAAAA==.Munidar:BAABNQAECn8dAAIgAAgKPQjjGABsAQAgAAgKPQjjGABsAQAAAA==.',
My='Mytz:BAAANQAECgcICgAAAA==.',
['Mï']='Mïnna:BAABNQAECn82AAMMAAoKaSL/EAAvAwAMAAoKvSD/EAAvAwALAAgKYB+vLwDWAQAAAA==.',
Ne='Nemisai:BAAANQADCggIEwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAABNQAECn8oAAMhAAkKnAosCwA2AQAhAAkKdgosCwA2AQAiAAYKCQN8GQCXAAAAAA==.',
Or='Orionbtch:BAAANQADCgYIDgAAAA==.',
Ov='Overheat:BAABNQAECn8bAAIBAAkKsBZaoABRAQABAAkKsBZaoABRAQAAAA==.',
Pa='Papi:BAAANQADCgcIBwAAAA==.',
Po='Poppy:BAABNQAECn8WAAIEAAoKAApBDwB/AQAEAAoKAApBDwB/AQAAAA==.Portinglol:BAAANQAECgEIAQABNQAECgoKJAASACIdAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAACNQAFFH8FAAMKAAIKxRAcIQCLAAAKAAIKxRAcIQCLAAATAAEKZAHQKQAtAAA1AAQKfyoAAwoACgrdG/w7AGkCAAoACgrdG/w7AGkCABMAAQpfCwbvADMAAAAA.',
Qu='Qué:BAAANQAECgEIBAAAAA==.',
Ra='Ratidari:BAABNQAECn8UAAIjAAYKthl9MwCmAQAjAAYKthl9MwCmAQAAAA==.Ratshifter:BAABNQAECn8dAAMVAAkKrRfhEQCIAQAVAAgKLRrhEQCIAQAaAAcKtgp/TwDOAAABNQAECgYIFAAjALYZAA==.Ravenstorm:BAAANQAECgQIBAAAAA==.',
Re='Red:BAAANQAECgQIBQABNQAECgoKKAAaALMUAA==.Remmîngton:BAAANQAECgUICwAAAA==.Retbulls:BAABNQAECn8yAAIKAAoKBSN2JQDBAgAKAAoKBSN2JQDBAgAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAACNQAFFH8KAAISAAMKTRH+GADHAAASAAMKTRH+GADHAAA1AAQKfzsAAxIACgooHlwaAAcDABIACgooHlwaAAcDABwAAgqlEnXkAEEAAAAA.',
Ru='Runslikedeer:BAABNQAECn81AAIbAAgKMBzSEgCCAgAbAAgKMBzSEgCCAgAAAA==.Runé:BAAANQAECgEIAQABNQAECgQICQANAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAACNQAFFH8OAAMBAAYK2w4vLQAmAQABAAUKVw4vLQAmAQAEAAIKYQpZDwBRAAA1AAQKf0QAAwEACgqpHyxGAPcCAAEACgqpHyxGAPcCAAQAAgr6E1Y2AEcAAAAA.Serah:BAACNQAFFH8MAAIkAAYKtwsmDwAWAQAkAAYKtwsmDwAWAQA1AAQKfy8AAyQACgq7Fy84APABACQACQq7Fy84APABACMACArWB/M5AHYBAAAA.Sevia:BAAANQAECgIIBAAAAA==.',
Sh='Sheppy:BAAANQAECgcIDwAAAA==.Shimakaze:BAABNQAECn8VAAMMAAgK9B1IHADiAgAMAAgK9B1IHADiAgAQAAQKZBXVggDxAAABNQAFFAUIDwABAGUVAA==.Shizaam:BAACNQAFFH8OAAMSAAYKkhHcEgAkAQASAAYKkhHcEgAkAQAcAAMKtAkCHQDXAAA1AAQKfzoAAxwACgr6IncgAAkDABwACQpsIncgAAkDABIACQp+HP8uAKUCAAAA.Shlommy:BAABNQAECn8bAAMCAAcKmQ/okQC6AQACAAcKmQ/okQC6AQAFAAEKmwCFigAOAAAAAA==.Shmorc:BAAANQAECgIIAgABNQAFFAcIHwABAJ0aAA==.',
Si='Silvaran:BAAANQAECgEIAQAAAA==.Silvermage:BAACNQAFFH8fAAIBAAcKnRpyCQAyAgABAAcKnRpyCQAyAgA1AAQKfzEAAgEACgo2JR8UAPICAAEACgo2JR8UAPICAAAA.Sinfxl:BAAANQAECgQICQAAAA==.Sinheph:BAAANQAECgUICgAAAA==.Sippinsizurp:BAABNQAECn8hAAIBAAkKLB9lSwDrAgABAAkKLB9lSwDrAgAAAA==.',
Sk='Skullmages:BAABNQAECn8qAAIKAAoK3h9RJAA0AwAKAAoK3h9RJAA0AwAAAA==.',
Sl='Slayur:BAAANQAECgcICAAAAA==.Sloppydro:BAABNQAECn9AAAMTAAoKCBXOMQBHAgATAAoKCBXOMQBHAgAKAAIKdwWAhQFSAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAgAAAA==.',
So='Socksimus:BAAANQADCgcIGAAAAA==.Sockssham:BAAANQADCggICAAAAA==.Sotari:BAAANQADCggICAAAAA==.',
St='Stabberz:BAACNQAFFH8IAAIdAAUKsRGgBQDhAAAdAAUKsRGgBQDhAAA1AAQKf1IAAh0ACgpnIZgKADYDAB0ACgpnIZgKADYDAAAA.Stannane:BAAANQADCgUICQABNQAECgUICwANAAAAAA==.Stellaloona:BAAANQAECgIIBgAAAA==.Sticks:BAAANQADCgcICQAAAA==.Stinkyhooves:BAEANQADCgQIBgABNQAECggICQANAAAAAA==.Stromboli:BAAANQADCgUIBQABNQAECgUICgANAAAAAA==.',
Su='Sushiroll:BAABNQAECn8kAAMSAAoKIh2TFAAAAwASAAoKIh2TFAAAAwAcAAUKERfGngBZAQAAAA==.',
Sw='Sweetsourrex:BAAANQAECgUIBAABNQAECgoKUAAeAOkhAA==.',
Ta='Tamaqua:BAABNQAECn8eAAISAAoKGhYvXACOAQASAAoKGhYvXACOAQAAAA==.Tatisjr:BAAANQAECgQIBwAAAA==.',
Te='Telissa:BAAANQAECgcICQAAAA==.Temoin:BAAANQAECgQIBQAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAABNQAECn8dAAIEAAoKhhJPCgAlAgAEAAoKhhJPCgAlAgAAAA==.Throngler:BAAANQAECggIEQAAAA==.',
To='Toobrunner:BAAANQAECgcIDAAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAFFAYIDgASAJIRAA==.',
Va='Vampress:BAAANQAECgMIBQAAAA==.Variam:BAABNQAECn8kAAIGAAkKihdGYQDrAQAGAAkKihdGYQDrAQAAAA==.',
Ve='Velannis:BAABNQAECn8uAAQRAAoKUiDtBACvAgARAAgKOh/tBACvAgAeAAkK9xotQQDhAQAdAAcKSRxQSQCeAQAAAA==.Verycheap:BAAANQAECgQIBAAAAA==.',
Vo='Voidangel:BAAANQAECgQICAAAAA==.Vonder:BAAANQAECgQICAAAAA==.Voodooki:BAAANQAECgIIBAAAAA==.',
Vu='Vuo:BAABNQAECn8oAAIGAAoKfw6wVwAEAgAGAAoKfw6wVwAEAgAAAA==.',
Wi='Winze:BAAANQADCggIDgAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQAECgQIBQABNQAECgoKMAATAKAeAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIDwANAAAAAA==.',
Wu='Wuchese:BAAANQAECgMIBAABNQAECgoKMAATAKAeAA==.',
Xf='Xfreshh:BAAANQAECgYICQAAAA==.',
Ya='Yamaa:BAAANQAECgcIDQABNQAFFAYIDgABAJwRAA==.Yamadin:BAAANQAFFAEIAQABNQAFFAYIDgABAJwRAA==.Yamadono:BAABNQAECn8cAAMeAAoKzh69EADoAgAeAAkKnh69EADoAgAdAAUKxxyBOQCgAAABNQAFFAYIDgABAJwRAA==.Yamaknight:BAAANQAECgEIAQABNQAFFAYIDgABAJwRAA==.Yamalock:BAAANQAECgUIBQABNQAFFAYIDgABAJwRAA==.Yamá:BAAANQADCgcIBwABNQAFFAYIDgABAJwRAA==.Yamå:BAACNQAFFH8OAAIBAAYKnBG1FQAtAQABAAYKnBG1FQAtAQA1AAQKfy4AAwEACgpXIMdKAOwCAAEACgpXIMdKAOwCACUAAQoZBJMNACAAAAAA.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAABNQAECn8WAAMSAAYK+hvnYADrAQASAAYK+hvnYADrAQAcAAYKBQ8FkQB6AQABNQAECgoKMAATAKAeAA==.',
Zo='Zortok:BAAANQAECggIDgAAAA==.',
Zu='Zumoknight:BAAANQAECgIIAgABNQAECggIAgANAAAAAA==.',
Zv='Zvlana:BAAANQAECggIAgAAAA==.',
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
