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

local lookup = {'Mage-Arcane','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Warlock-Demonology','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Shaman-Elemental','Druid-Feral','Priest-Holy','Priest-Shadow','Paladin-Protection','Monk-Windwalker','Druid-Restoration','Druid-Balance','Mage-Frost','Warlock-Affliction','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc','Rogue-Outlaw',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abeblinkin:BAABNQAECn8aAAIBAAcK8BHM6AC4AQABAAcK8BHM6AC4AQAAAA==.Aborlight:BAAANQAECgQICAAAAA==.',
Ad='Adit:BAAANQAECggICgAAAA==.',
Af='Afrit:BAAANQAECgUIDwAAAA==.',
Ai='Aiwass:BAABNQAECn8dAAICAAkKIgR2JgBCAQACAAkKIgR2JgBCAQAAAA==.',
Al='Alieah:BAAANQAECgYIEgAAAA==.Alorum:BAAANQADCggICAABNQAECgcIGgADAB4MAA==.Alpharius:BAAANQAECgUIEwAAAA==.',
Am='Amacoozy:BAABNQAECn81AAIEAAkK0xg4KwBcAQAEAAkK0xg4KwBcAQAAAA==.Amathricus:BAABNQAECn8lAAIFAAcKggkV4gBXAQAFAAcKggkV4gBXAQAAAA==.',
Ar='Arms:BAACNQAFFH8VAAMGAAcK8xQmAgBKAQAGAAcK8xQmAgBKAQAHAAEKAACUJgAtAAA1AAQKfx0AAgYACgowIbYfAI4CAAYACgowIbYfAI4CAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQAECgQIBAAAAA==.',
At='Athena:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAEANQADCgIIAgABNQAECgQIBwAIAAAAAA==.Auralei:BAAANQADCgUIBQABNQAECgUIEAAIAAAAAA==.',
Az='Azelia:BAAANQAECgIJAgABNQAECgcICgAIAAAAAA==.Azzy:BAAANQAECgcICgAAAA==.',
Be='Bellestri:BAABNQAECn8gAAIJAAkKfwTwZgC1AAAJAAkKfwTwZgC1AAAAAA==.',
Bi='Bigb:BAABNQAECn8UAAQDAAYKtiG6LABrAQADAAYKux+6LABrAQAKAAQKCiPpDAD/AAALAAEKAAB3lwApAAAAAA==.Bigface:BAAANQAECgYIBgAAAA==.Bigrod:BAACNQAFFH8HAAIMAAIKfQaXJwBbAAAMAAIKfQaXJwBbAAA1AAQKfx0AAgwACQpuD6tHANoBAAwACQpuD6tHANoBAAAA.Binks:BAAANQAECgEIAwAAAA==.',
Bl='Black:BAAANQAECgYIEQAAAA==.Blasfoomous:BAACNQAFFH8MAAIMAAQK8A/LFgD2AAAMAAQK8A/LFgD2AAA1AAQKfy8AAgwACgrqHBEgALICAAwACgrqHBEgALICAAAA.Blu:BAACNQAFFH8SAAINAAUKRx7sCQCwAQANAAUKRx7sCQCwAQA1AAQKfyMAAg0ACgokI9gOAEwDAA0ACgokI9gOAEwDAAAA.',
Bo='Bochese:BAAANQAECgMIBAABNQAECggIIwAOAPwdAA==.',
Br='Brochese:BAAANQAECgQIBAABNQAECggIIwAOAPwdAA==.',
Bu='Bubblewrap:BAAANQAECgIIAwABNQAFFAQIDAAPAPsVAA==.Budfoster:BAAANQADCggIDwAAAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQADCggIDgABNQAECgcIGgABAPARAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Ch='Cheyeon:BAAANQAECgEIAQAAAA==.',
Cl='Classcarry:BAABNQAECn8UAAMFAAcKQxt3fwAqAgAFAAcKQxt3fwAqAgAOAAQKcxTvvAACAQABNQAECgoKGwAQAJYdAA==.Claybigsby:BAACNQAFFH8MAAMCAAQKpRrbCwChAAACAAIKIRbbCwChAAAJAAIKriPHMQCTAAA1AAQKfy0AAwkACgqhH20eAHUBAAkACAqeH20eAHUBAAIABArXGv4vAAkBAAAA.Clif:BAAANQAFFAEIAQAAAA==.',
Co='Collie:BAEBNQAECn8YAAIRAAoKrCK7BQAbAwARAAoKrCK7BQAbAwAAAA==.Constantina:BAABNQAECn85AAISAAkKbxYBLQBJAQASAAkKbxYBLQBJAQAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQAECgMIAwAAAA==.',
Cy='Cyleste:BAABNQAECn8hAAMTAAoKBwspEgD8AAATAAoKBwspEgD8AAASAAQK0Q3yxADPAAAAAA==.',
De='Demonifrita:BAAANQADCggICAAAAA==.Demonlady:BAAANQADCggIDQAAAA==.Deo:BAABNQAECn8VAAMUAAkK/Rd2HwDpAQAUAAgK/Rd2HwDpAQAOAAEKsxLPkwA5AAAAAA==.Derpy:BAABNQAECn8ZAAMPAAYK3gmbCgCvAAAVAAYKsQPqTQC/AAAPAAYK3gmbCgCvAAAAAA==.',
Dh='Dheevix:BAAANQAECgMIBAABNQAECgoKLQABAKEaAA==.',
Dj='Djheals:BAAANQAECgMIBQABNQAECgYIEgAIAAAAAA==.Djmuphasa:BAAANQAECgYIEgAAAA==.Djthrasher:BAAANQAECgQICAABNQAECgYIEgAIAAAAAA==.',
Dr='Drachese:BAAANQAECgUICgABNQAECggIIwAOAPwdAA==.Dripps:BAAANQAECgMIAwAAAA==.Druchese:BAABNQAECn8fAAMWAAcKNRuCCgCPAQAWAAcKNRuCCgCPAQAXAAYKMg5sYwBAAQABNQAECggIIwAOAPwdAA==.',
Ea='Eagleeye:BAABNQAECn8VAAIFAAcKHQp12gBmAQAFAAcKHQp12gBmAQAAAA==.',
Em='Emsley:BAABNQAECn9HAAIQAAoKXhKoRQBfAgAQAAoKXhKoRQBfAgAAAA==.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQADCgYICgAAAA==.',
Ev='Ev:BAABNQAECn8WAAMPAAgKeRuYDQAgAgAPAAUKSCaYDQAgAgAVAAcK7hCWOQBHAQAAAA==.',
Ex='Exo:BAACNQAFFH8HAAIBAAQKlAycLgAbAQABAAQKlAycLgAbAQA1AAQKfyIAAwEACgrYH40tAGgBAAEACgrDHY0tAGgBABgAAgrQIQwwAH8AAAAA.',
Fa='Falorin:BAAANQAECgEIAQAAAA==.',
Fl='Floudwing:BAAANQAECgEIAQAAAA==.',
Fn='Fnwarriors:BAAANQADCgcICAAAAA==.',
Fo='Focalors:BAAANQAECgcIDwABNQAFFAUIDwABAGUVAA==.Foobear:BAAANQAECgcIEAABNQAFFAQIDAAMAPAPAA==.',
Fr='Franchescold:BAAANQAECgcIDAAAAA==.',
Fu='Furlock:BAABNQAECn8VAAIZAAcKsBlEBwAsAgAZAAcKsBlEBwAsAgAAAA==.',
Ga='Gabriel:BAACNQAFFH8GAAIUAAIK0QBcCQAqAAAUAAIK0QBcCQAqAAA1AAQKf1YAAxQACgpIFsgYADACABQACgpIFsgYADACAAUAAgoAAGzAASgAAAAA.Galicia:BAAANQAECgQIDgAAAA==.Gantaris:BAAANQAECgUIDQAAAA==.Garbagevoker:BAAANQAECgIIAgAAAA==.Gaymer:BAAANQAECgQIBwABNQAECgUIDwAIAAAAAA==.',
Gi='Gir:BAAANQAECgcIEAAAAA==.',
Gl='Glochese:BAAANQADCggICAABNQAECggIIwAOAPwdAA==.Glurp:BAAANQAECgMIAQAAAA==.',
Go='Gochese:BAABNQAECn8jAAMOAAgK/B1oKwC6AgAOAAgK/B1oKwC6AgAFAAIK7AhJ+QA2AAAAAA==.Gorgeous:BAAANQAECgYIBgABNQAECgYIBgAIAAAAAA==.Gothel:BAAANQADCgcIDgAAAA==.',
Gr='Grace:BAAANQAECgcICwAAAA==.Greenseer:BAAANQAECgcIDwAAAA==.',
Gt='Gtoffmyd:BAAANQADCgIIAgABNQAECgEIAwAIAAAAAA==.Gtoffmydruid:BAAANQAECgEIAwAAAA==.Gtoffmyface:BAAANQADCgUIBQABNQAECgEIAwAIAAAAAA==.',
Gw='Gwaralmighty:BAABNQAECn8xAAIaAAkK8B5IBgCpAgAaAAkK8B5IBgCpAgAAAA==.',
Gy='Gypo:BAAANQAECgEIAgAAAA==.',
Ha='Haagen:BAABNQAECn8lAAIDAAkKPA9RQQAzAQADAAkKPA9RQQAzAQAAAA==.Hamsup:BAABNQAECn8pAAIEAAoKdxQThAARAgAEAAoKdxQThAARAgAAAA==.Hatch:BAAANQADCgcICAABNQAECggIFgAPAHkbAA==.',
['Hô']='Hôldem:BAEBNQAECn8lAAIXAAgK4Q4gFAA6AQAXAAgK4Q4gFAA6AQAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAABNQAECn8nAAIBAAcKZBUxygDxAQABAAcKZBUxygDxAQAAAA==.Ifrite:BAAANQAECgEIAQAAAA==.',
Ik='Ikur:BAAANQAECgYIDQABNQAECgkJMAAOAJUdAA==.',
Im='Imyerchese:BAAANQAECgEIAgABNQAECggIIwAOAPwdAA==.',
Jo='Jontalo:BAAANQADCgcIDgAAAA==.Jormi:BAABNQAECn8cAAIEAAcK1B9+XAB2AgAEAAcK1B9+XAB2AgAAAA==.',
Ju='Justthetipp:BAAANQABCgQIBgABNQAECgcIFQAQADcPAA==.',
Ka='Kalthael:BAAANQAECgEIAQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECn8sAAMRAAoKSRz+CAC+AgARAAoKSRz+CAC+AgAWAAMKPhlRTADdAAAAAA==.Katakuri:BAAANQAECgEIAQAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECn8YAAITAAgKLBzqHQBRAgATAAgKLBzqHQBRAgABNQAFFAcIGgAVACkdAA==.',
Ko='Kochese:BAAANQAECgUIBgABNQAECggIIwAOAPwdAA==.',
Ku='Kutar:BAAANQAECgQIBgAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lochese:BAAANQADCgYIDAABNQAECggIIwAOAPwdAA==.Lockme:BAAANQAECgcICgABNQAFFAcIHwABAJ0aAA==.Lotei:BAAANQADCgMIAwAAAA==.',
['Ló']='Lóvecandy:BAAANQAECgEIBQAAAA==.',
Ma='Magicdro:BAAANQADCgQIBAAAAA==.Magorrak:BAAANQAECgIIBAAAAA==.Mal:BAACNQAFFH8WAAIbAAYKqCLpAAB2AQAbAAYKqCLpAAB2AQA1AAQKfxsAAxwACgrJIbodAOUBABwABwp0HbodAOUBABsABApLJpNaAE4BAAAA.Marxwomun:BAAANQAECgUIBAAAAA==.Mary:BAACNQAFFH8XAAIbAAYKYh9rAADsAQAbAAYKYh9rAADsAQA1AAQKfykAAhsACgpoI4EHAFsDABsACgpoI4EHAFsDAAAA.',
Mc='Mcshammer:BAAANQAECgQIDwAAAA==.',
Me='Mero:BAAANQAECgQICAAAAA==.Metal:BAABNQAECn8dAAIdAAYKAB1UAQCbAQAdAAYKAB1UAQCbAQAAAA==.',
Mi='Minervajt:BAAANQAECgUICAAAAA==.Miorine:BAACNQAFFH8PAAMBAAUKZRVNIACFAQABAAUKZRVNIACFAQAYAAEKzwKuFgA4AAA1AAQKfy0AAgEACgpHHtM1AB4DAAEACgpHHtM1AB4DAAAA.Mistbehavin:BAACNQAFFH8MAAIPAAQK+xXLBQAVAQAPAAQK+xXLBQAVAQA1AAQKfzwAAg8ACgplHeAFAPcCAA8ACgplHeAFAPcCAAAA.',
Mo='Moginndar:BAABNQAECn8nAAMUAAkKDg8DKQCVAQAUAAkKUg4DKQCVAQAFAAUKhg95AwEZAQAAAA==.Mok:BAAANQABCgUIAwAAAA==.Moochese:BAABNQAECn8UAAMSAAYKfxfLdgC3AQASAAYKfxfLdgC3AQATAAUKfQSiUwC/AAABNQAECggIIwAOAPwdAA==.',
Mu='Muggsy:BAAANQAECgEJAQAAAA==.Munidar:BAABNQAECn8VAAIeAAcK1wYIHwBvAQAeAAcK1wYIHwBvAQAAAA==.',
My='Mytz:BAAANQAECgMIAwAAAA==.',
['Mï']='Mïnna:BAABNQAECn8nAAMHAAoKxiD/EAAvAwAHAAoKvSD/EAAvAwAGAAcKsxtqMwARAgAAAA==.',
Ne='Nemisai:BAAANQADCggIEwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAABNQAECn8ZAAMfAAgKbge7DwBCAQAfAAgKbge7DwBCAQAgAAQKrAJyEABhAAAAAA==.',
Or='Orionbtch:BAAANQADCgYIDgAAAA==.',
Ov='Overheat:BAAANQAECgcIEgAAAA==.',
Po='Poppy:BAAANQAECgYIDgAAAA==.Portinglol:BAAANQAECgEIAQABNQAECgoKGwAQAJYdAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAABNQAECn8fAAMFAAoKaRe3QwA+AQAFAAoKaRe3QwA+AQAOAAEKXwuskwA5AAAAAA==.',
Ra='Ratidari:BAABNQAECn8UAAIhAAYKthl9MwCmAQAhAAYKthl9MwCmAQAAAA==.Ratshifter:BAABNQAECn8VAAMRAAcK3Bh4EgDWAQARAAcK3Bh4EgDWAQAXAAIKwwFxqABHAAABNQAECgYIFAAhALYZAA==.Ravenstorm:BAAANQAECgQIBAAAAA==.',
Re='Red:BAAANQAECgIIAwABNQAECgoKIgAXAEETAA==.Remmîngton:BAAANQAECgUIDgAAAA==.Retbulls:BAABNQAECn8mAAIFAAoKtyBZEwDhAQAFAAoKtyBZEwDhAQAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAACNQAFFH8FAAINAAIKlg6PEACEAAANAAIKlg6PEACEAAA1AAQKfyoAAg0ACgqQHFwaAAcDAA0ACgqQHFwaAAcDAAAA.',
Ru='Runslikedeer:BAABNQAECn8XAAIWAAcKQRqjIgARAgAWAAcKQRqjIgARAgAAAA==.Runé:BAAANQAECgEIAQABNQAECgQICQAIAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAACNQAFFH8MAAMBAAQK7wwvLQAmAQABAAQK7wwvLQAmAQAYAAEK1wMtFQBCAAA1AAQKfzkAAwEACgqRHixGAPcCAAEACgqRHixGAPcCABgAAQrJFhhJADIAAAAA.Serah:BAACNQAFFH8KAAIiAAQKLQ4mDwAWAQAiAAQKLQ4mDwAWAQA1AAQKfysAAyIACgrCE7sTAE0BACEACArWB/M5AHYBACIACQrCE7sTAE0BAAAA.Sevia:BAAANQAECgIIBQAAAA==.',
Sh='Sheppy:BAAANQAECgMIAgAAAA==.Shimakaze:BAABNQAECn8UAAMHAAgK9B1IHADiAgAHAAgK9B1IHADiAgAMAAQKZBXVggDxAAABNQAFFAUIDwABAGUVAA==.Shizaam:BAACNQAFFH8MAAMNAAQK6hDcEgAkAQANAAQK6hDcEgAkAQAQAAMKtAkCHQDXAAA1AAQKfzAAAxAACgp9IXcgAAkDABAACQoJIncgAAkDAA0ACQp6HP8uAKUCAAAA.Shlommy:BAABNQAECn8bAAMJAAcKmQ/okQC6AQAJAAcKmQ/okQC6AQACAAEKmwCFigAOAAAAAA==.',
Si='Silvaran:BAAANQAECgEIAQAAAA==.Silvermage:BAACNQAFFH8fAAIBAAcKnRqSBABoAQABAAcKnRqSBABoAQA1AAQKfycAAgEACgo2JWEvAC4DAAEACgo2JWEvAC4DAAAA.Sinfxl:BAAANQAECgQICQAAAA==.Sinheph:BAAANQAECgQIBAAAAA==.Sippinsizurp:BAABNQAECn8hAAIBAAkKLB9lSwDrAgABAAkKLB9lSwDrAgAAAA==.',
Sk='Skullmages:BAABNQAECn8fAAIFAAoKqB5RJAA0AwAFAAoKqB5RJAA0AwAAAA==.',
Sl='Slayur:BAAANQAECgcICwAAAA==.Sloppydro:BAABNQAECn8vAAMOAAoKUBFIIgBcAQAOAAoKUBFIIgBcAQAFAAIKdwWAhQFSAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAwAAAA==.',
So='Socksimus:BAAANQAECgEIAQAAAA==.Sockssham:BAAANQADCggICAAAAA==.Sotari:BAAANQADCgEIAQAAAA==.',
St='Stabberz:BAABNQAECn9HAAIbAAoKUx+YCgA2AwAbAAoKUx+YCgA2AwAAAA==.Stannane:BAAANQADCgUICQABNQAECgIIAgAIAAAAAA==.Stellaloona:BAAANQADCgYIFgAAAA==.Sticks:BAAANQADCgcICQAAAA==.Stinkyhooves:BAEANQADCgQIBgABNQAECgQIBwAIAAAAAA==.Stromboli:BAAANQADCgUIBQABNQAECgQIBAAIAAAAAA==.',
Su='Sushiroll:BAABNQAECn8bAAMQAAoKlh3GngBZAQAQAAUKERfGngBZAQANAAkKqhj0JQBLAQAAAA==.',
Sw='Sweetsourrex:BAAANQAECgUIBQABNQAECgoKOgAcAKUfAA==.',
Ta='Tamaqua:BAABNQAECn8WAAINAAcK0w9FhACAAQANAAcK0w9FhACAAQAAAA==.',
Te='Telissa:BAAANQAECgEIAQAAAA==.Temoin:BAAANQAECgMIBgAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAABNQAECn8UAAIYAAkKThFPCgAlAgAYAAkKThFPCgAlAgAAAA==.',
To='Toobrunner:BAAANQAECgcIBwAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAFFAQIDAANAOoQAA==.',
Va='Vampress:BAAANQAECgMIBAAAAA==.Variam:BAABNQAECn8cAAIDAAcKMBgFdwAhAgADAAcKMBgFdwAhAgAAAA==.',
Ve='Velannis:BAABNQAECn8oAAQjAAkKlBztBACvAgAjAAgKOh/tBACvAgAbAAYKuBtQSQCeAQAcAAYKchWdFQAuAQAAAA==.',
Vo='Voidangel:BAAANQAECgEIAgAAAA==.Vonder:BAAANQAECgQIBAAAAA==.Voodooki:BAAANQAECgEIAwAAAA==.',
Vu='Vuo:BAABNQAECn8aAAIDAAcKHgwrpwC3AQADAAcKHgwrpwC3AQAAAA==.',
Wa='Wayside:BAAANQAECgEIAQAAAA==.',
Wi='Winze:BAAANQAECgEIAQAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQAECgUIBQABNQAECggIIwAOAPwdAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIDwAIAAAAAA==.',
Wu='Wuchese:BAAANQAECgMIAwABNQAECggIIwAOAPwdAA==.',
Xf='Xfreshh:BAAANQAECgYIDAAAAA==.',
Ya='Yamaa:BAAANQAECgUIBwABNQAFFAMIBwABALsKAA==.Yamadono:BAAANQAECgcICwABNQAFFAMIBwABALsKAA==.Yamá:BAAANQADCgcIBwABNQAFFAMIBwABALsKAA==.Yamå:BAACNQAFFH8HAAIBAAMKuwpOHACLAAABAAMKuwpOHACLAAA1AAQKfysAAgEACgpmH8dKAOwCAAEACgpmH8dKAOwCAAAA.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAABNQAECn8WAAMNAAYK+hvnYADrAQANAAYK+hvnYADrAQAQAAYKBQ8FkQB6AQABNQAECggIIwAOAPwdAA==.',
Zo='Zortok:BAAANQAECgcIDAAAAA==.',
Zu='Zumoknight:BAAANQAECgEIAQABNQAECggICgAIAAAAAA==.',
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
