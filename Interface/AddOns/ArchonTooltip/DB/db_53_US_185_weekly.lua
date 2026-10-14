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

local lookup = {'Mage-Arcane','Warlock-Destruction','Warrior-Arms','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Druid-Feral','Priest-Holy','Priest-Shadow','Paladin-Protection','Druid-Restoration','Druid-Balance','Shaman-Elemental','Monk-Windwalker','Mage-Frost','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Rogue-Outlaw',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abeblinkin:BAABNQAECn8aAAIBAAcK8BFc5gC5AQABAAcK8BFc5gC5AQAAAA==.Aborlight:BAAANQAECgMIBAAAAA==.',
Ad='Adit:BAAANQAECgEIAwAAAA==.',
Af='Afrit:BAAANQAECgMIDAAAAA==.',
Ai='Aiwass:BAABNQAECn8cAAICAAgK5QNJJgBCAQACAAgK5QNJJgBCAQAAAA==.',
Al='Alieah:BAAANQAECgYIDgAAAA==.Alpharius:BAAANQAECgUIDwAAAA==.',
Am='Amacoozy:BAABNQAECn8uAAIDAAkK0xjUSQCpAgADAAkK0xjUSQCpAgAAAA==.Amathricus:BAABNQAECn8hAAIEAAcKggml3gBXAQAEAAcKggml3gBXAQAAAA==.',
Ar='Arms:BAACNQAFFH8QAAMFAAYK1RK8BADDAQAFAAYK1RK8BADDAQAGAAEKAAAuJgAtAAA1AAQKfxoAAgUACQrjIBgfAI8CAAUACQrjIBgfAI8CAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQAECgQIBAAAAA==.',
At='Athena:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAAANQADCgIIAgABNQAECgQIBwAHAAAAAA==.Auralei:BAAANQADCgUIBQABNQAECgQIDQAHAAAAAA==.',
Az='Azelia:BAAANQAECgIJAgABNQAECgcICgAHAAAAAA==.Azzy:BAAANQAECgcICgAAAA==.',
Be='Bellestri:BAABNQAECn8WAAIIAAgKZQQrygAxAQAIAAgKZQQrygAxAQAAAA==.',
Bi='Bigb:BAAANQAECgUIDwAAAA==.Bigface:BAAANQAECgYIBgAAAA==.Bigrod:BAACNQAFFH8GAAIJAAIKfQYEJwBbAAAJAAIKfQYEJwBbAAA1AAQKfxwAAgkACQriDgdHANoBAAkACQriDgdHANoBAAAA.Binks:BAAANQAECgIIAgAAAA==.',
Bl='Black:BAAANQAECgYIEQAAAA==.Blasfoomous:BAACNQAFFH8MAAIJAAQK8A9aFgD2AAAJAAQK8A9aFgD2AAA1AAQKfysAAgkACQruHqsfALMCAAkACQruHqsfALMCAAAA.Blu:BAACNQAFFH8PAAIKAAUKRx6tCQCwAQAKAAUKRx6tCQCwAQA1AAQKfyEAAgoACQo/IpcOAEwDAAoACQo/IpcOAEwDAAAA.',
Bo='Bochese:BAAANQAECgMIBAABNQAECggIHgALAJkdAA==.',
Br='Brochese:BAAANQAECgQIBAABNQAECggIHgALAJkdAA==.',
Bu='Bubblewrap:BAAANQAECgIIAgABNQAFFAQIDAAMAPsVAA==.Budfoster:BAAANQADCggICAAAAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQADCggIDgABNQAECgcIGgABAPARAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Ch='Cheyeon:BAAANQAECgEIAQAAAA==.',
Cl='Classcarry:BAABNQAECn8UAAMEAAcKQxtSfQArAgAEAAcKQxtSfQArAgALAAQKcxQQuwACAQABNQAECggIFwAKAF4XAA==.Claybigsby:BAACNQAFFH8MAAMCAAQKpRqTCwCkAAACAAIKIRaTCwCkAAAIAAIKriPoMACXAAA1AAQKfykAAwgACQoZHstsABQCAAgABwp3HctsABQCAAIABArXGsAvAAkBAAAA.Clif:BAAANQAFFAEIAQAAAA==.',
Co='Collie:BAEBNQAECn8UAAINAAgKdyOaBQAcAwANAAgKdyOaBQAcAwAAAA==.Constantina:BAABNQAECn80AAIOAAkKqRXbSQBEAgAOAAkKqRXbSQBEAgAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQAECgMIAwAAAA==.',
Cy='Cyleste:BAABNQAECn8dAAMPAAgKpwoFLADCAQAPAAgKpwoFLADCAQAOAAQK0Q2PwgDPAAAAAA==.',
De='Demonlady:BAAANQADCggICAAAAA==.Deo:BAABNQAECn8UAAIQAAgK/RcpHwDpAQAQAAgK/RcpHwDpAQAAAA==.Derpy:BAAANQAECgUIEQAAAA==.',
Dh='Dheevix:BAAANQADCgcIBwABNQAECgkJJgABALoZAA==.',
Dj='Djheals:BAAANQAECgMIBQABNQAECgYIDgAHAAAAAA==.Djmuphasa:BAAANQAECgYIDgAAAA==.Djthrasher:BAAANQAECgQICAABNQAECgYIDgAHAAAAAA==.',
Dr='Drachese:BAAANQAECgUICgABNQAECggIHgALAJkdAA==.Dripps:BAAANQAECgMIAwAAAA==.Druchese:BAABNQAECn8ZAAMRAAcKoxlaIgAPAgARAAcKoxlaIgAPAgASAAYKMg5/YgBAAQABNQAECggIHgALAJkdAA==.',
Ea='Eagleeye:BAAANQAECgcIEwAAAA==.',
Em='Emsley:BAABNQAECn9BAAITAAkKrhOmRABgAgATAAkKrhOmRABgAgAAAA==.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQADCgYJCgAAAA==.',
Ev='Ev:BAABNQAECn8WAAMMAAgKeRt2DQAhAgAMAAUKSCZ2DQAhAgAUAAcK7hD1OABHAQAAAA==.',
Ex='Exo:BAACNQAFFH8HAAIBAAQKlAyTLQAbAQABAAQKlAyTLQAbAQA1AAQKfx4AAwEACQrLHwJ1AJMCAAEACQppHQJ1AJMCABUAAgrQIYEvAH8AAAAA.',
Fa='Falorin:BAAANQADCgcIEgAAAA==.',
Fl='Floudwing:BAAANQAECgEIAQAAAA==.',
Fn='Fnwarriors:BAAANQADCgcICAAAAA==.',
Fo='Focalors:BAAANQAECgcIDwABNQAFFAUIDQABAGUVAA==.Foobear:BAAANQAECgcIDgABNQAFFAQIDAAJAPAPAA==.',
Fr='Franchescold:BAAANQAECgcIDAAAAA==.',
Fu='Furlock:BAAANQAECgcIEwAAAA==.',
Ga='Gabriel:BAABNQAECn9OAAMQAAkKlRZ3GAAxAgAQAAkKlRZ3GAAxAgAEAAEKAAAaugEoAAAAAA==.Galicia:BAAANQAECgQICgAAAA==.Gantaris:BAAANQAECgQIDQAAAA==.Gaymer:BAAANQAECgQIBwABNQAECgUIDwAHAAAAAA==.',
Gi='Gir:BAAANQAECgcIDgAAAA==.',
Go='Gochese:BAABNQAECn8eAAMLAAgKmR3hKgC6AgALAAgKmR3hKgC6AgAEAAEKAACjvQEmAAAAAA==.Gorgeous:BAAANQAECgYIBgABNQAECgYIBgAHAAAAAA==.Gothel:BAAANQADCgcIDgAAAA==.',
Gr='Grace:BAAANQAECgcICwAAAA==.Greenseer:BAAANQAECgcIDQAAAA==.',
Gt='Gtoffmyd:BAAANQADCgIIAgABNQAECgEIAgAHAAAAAA==.Gtoffmydruid:BAAANQAECgEIAgAAAA==.Gtoffmyface:BAAANQADCgUIBQABNQAECgEIAgAHAAAAAA==.',
Gw='Gwaralmighty:BAABNQAECn8uAAIWAAgKDyA3BgCpAgAWAAgKDyA3BgCpAgAAAA==.',
Gy='Gypo:BAAANQAECgEIAgAAAA==.',
Ha='Haagen:BAABNQAECn8fAAIXAAcKNBGJnADKAQAXAAcKNBGJnADKAQAAAA==.Hamsup:BAABNQAECn8lAAIDAAgKvBiYggARAgADAAgKvBiYggARAgAAAA==.Hatch:BAAANQADCgcICAABNQAECggIFgAMAHkbAA==.',
['Hô']='Hôldem:BAEBNQAECn8eAAISAAgK/w29RgDOAQASAAgK/w29RgDOAQAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAABNQAECn8iAAIBAAcKZBUhyADzAQABAAcKZBUhyADzAQAAAA==.Ifrite:BAAANQAECgEIAQAAAA==.',
Ik='Ikur:BAAANQAECgYIDQABNQAECgkJKgALAOYaAA==.',
Im='Imyerchese:BAAANQAECgEIAgABNQAECggIHgALAJkdAA==.',
Jo='Jontalo:BAAANQADCgcIDgAAAA==.Jormi:BAABNQAECn8cAAIDAAcK1B8RWwB3AgADAAcK1B8RWwB3AgAAAA==.',
Ju='Justthetipp:BAAANQABCgQIBgABNQAECgcIFQATADcPAA==.',
Ka='Kalthael:BAAANQAECgEIAQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECn8oAAMNAAgKnR7kCAC9AgANAAgKnR7kCAC9AgARAAMKPhltSwDdAAAAAA==.Katakuri:BAAANQAECgEIAQAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECn8YAAIPAAgKLBygHQBRAgAPAAgKLBygHQBRAgABNQAFFAcIGgAUACkdAA==.',
Ko='Kochese:BAAANQAECgUIBgABNQAECggIHgALAJkdAA==.',
Ku='Kutar:BAAANQAECgIIAgAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lochese:BAAANQADCgYIBgABNQAECggIHgALAJkdAA==.Lockme:BAAANQAECgcICgABNQAFFAYIGgABAP8dAA==.Lotei:BAAANQADCgMIAwAAAA==.',
['Ló']='Lóvecandy:BAAANQAECgEIBQAAAA==.',
Ma='Magorrak:BAAANQAECgIIBAAAAA==.Mal:BAACNQAFFH8RAAIYAAUKqSR1BAD3AQAYAAUKqSR1BAD3AQA1AAQKfxoAAxkACQoYIVUdAOUBABkABwp0HVUdAOUBABgAAwoxJgFZAE4BAAAA.Marxwomun:BAAANQAECgQIBAAAAA==.Mary:BAACNQAFFH8SAAIYAAUKaB+SBADyAQAYAAUKaB+SBADyAQA1AAQKfyUAAhgACQrzI1IHAFwDABgACQrzI1IHAFwDAAAA.',
Mc='Mcshammer:BAAANQAECgQIDwAAAA==.',
Me='Mero:BAAANQAECgQICAAAAA==.Metal:BAABNQAECn8YAAIaAAUKRxwwCwCOAQAaAAUKRxwwCwCOAQAAAA==.',
Mi='Miorine:BAACNQAFFH8NAAMBAAUKZRVyHwCEAQABAAUKZRVyHwCEAQAVAAEKzwJHFgA4AAA1AAQKfykAAgEACQooIvE0ACADAAEACQooIvE0ACADAAAA.Mistbehavin:BAACNQAFFH8MAAIMAAQK+xWfBQAXAQAMAAQK+xWfBQAXAQA1AAQKfzcAAgwACQrsHtYFAPgCAAwACQrsHtYFAPgCAAAA.',
Mo='Moginndar:BAABNQAECn8nAAMQAAkKDg+GKACVAQAQAAkKUg6GKACVAQAEAAUKhg+q/wAaAQAAAA==.Moochese:BAABNQAECn8UAAMOAAYKfxdDdQC3AQAOAAYKfxdDdQC3AQAPAAUKfQS0UgC/AAABNQAECggIHgALAJkdAA==.',
Mu='Muggsy:BAAANQAECgEJAQAAAA==.Munidar:BAAANQAECgcIEwAAAA==.',
My='Mytz:BAAANQAECgMIAwAAAA==.',
['Mï']='Mïnna:BAABNQAECn8hAAMGAAkKCCHiEAAvAwAGAAkK/SDiEAAvAwAFAAYKGh5jMgASAgABNQAECgkJIQASAFUhAA==.',
Ne='Nemisai:BAAANQADCggIEwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAABNQAECn8VAAIbAAgKbgeSDwBCAQAbAAgKbgeSDwBCAQAAAA==.',
Or='Orionbtch:BAAANQADCgYIDgAAAA==.',
Ov='Overheat:BAAANQAECgYIEQAAAA==.',
Po='Poppy:BAAANQAECgIICQAAAA==.Portinglol:BAAANQAECgEIAQABNQAECggIFwAKAF4XAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAABNQAECn8ZAAIEAAgKpxbbhgAVAgAEAAgKpxbbhgAVAgAAAA==.',
Ra='Ratidari:BAABNQAECn8UAAIcAAYKthnfMgCnAQAcAAYKthnfMgCnAQAAAA==.Ratshifter:BAAANQAECgYIEAABNQAECgYIFAAcALYZAA==.Ravenstorm:BAAANQAECgQIBAAAAA==.',
Re='Red:BAAANQAECgEIAQABNQAECgkJHgASADgUAA==.Remmîngton:BAAANQAECgUJDgAAAA==.Retbulls:BAABNQAECn8gAAIEAAgKTiCrRQDAAgAEAAgKTiCrRQDAAgAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAABNQAECn8jAAIKAAkKzB3qGQAHAwAKAAkKzB3qGQAHAwAAAA==.',
Ru='Runslikedeer:BAAANQAECgcIEgAAAA==.Runé:BAAANQAECgEIAQABNQAECgQICQAHAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAACNQAFFH8MAAMBAAQK7wwnLAAmAQABAAQK7wwnLAAmAQAVAAEK1wPDFABCAAA1AAQKfzMAAwEACQoAHk1FAPkCAAEACQoAHk1FAPkCABUAAQrJFjNIADIAAAAA.Serah:BAACNQAFFH8KAAIdAAQKLQ7MDgAWAQAdAAQKLQ7MDgAWAQA1AAQKfyYAAx0ACQpMFIQ3APABAB0ACApMFIQ3APABABwACArWB0I5AHYBAAAA.Sevia:BAAANQAECgIIBQAAAA==.',
Sh='Sheppy:BAAANQAECgIIAQAAAA==.Shimakaze:BAAANQAECggIEwABNQAFFAUIDQABAGUVAA==.Shizaam:BAACNQAFFH8MAAMKAAQK6hBoEgAkAQAKAAQK6hBoEgAkAQATAAMKtAl3HADXAAA1AAQKfywAAxMACQoJIgUgAAkDABMACQoJIgUgAAkDAAoACArmHGcuAKYCAAAA.Shlommy:BAABNQAECn8bAAMIAAcKmQ/VjwC6AQAIAAcKmQ/VjwC6AQACAAEKmwDIiQAOAAAAAA==.',
Si='Silvaran:BAAANQAECgEIAQAAAA==.Silvermage:BAACNQAFFH8aAAIBAAYK/x0ACQAyAgABAAYK/x0ACQAyAgA1AAQKfyQAAgEACQoBJYYuADADAAEACQoBJYYuADADAAAA.Sinfxl:BAAANQAECgQICQAAAA==.Sinheph:BAAANQAECgEIAQAAAA==.Sippinsizurp:BAABNQAECn8hAAIBAAkKLB9aSQDvAgABAAkKLB9aSQDvAgAAAA==.',
Sk='Skullmages:BAABNQAECn8ZAAIEAAkKCB+MIwA1AwAEAAkKCB+MIwA1AwAAAA==.',
Sl='Slayur:BAAANQAECgcICwAAAA==.Slinkeril:BAAANQADCggIJwAAAA==.Sloppydro:BAABNQAECn8oAAMLAAkK0xBMUgAhAgALAAkK0xBMUgAhAgAEAAIKdwXZfwFSAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAwAAAA==.',
So='Socksimus:BAAANQAECgEIAQAAAA==.Sockssham:BAAANQADCggICAAAAA==.Sotari:BAAANQADCgEIAQAAAA==.',
St='Stabberz:BAABNQAECn9BAAIYAAkK/x5zCgA1AwAYAAkK/x5zCgA1AwAAAA==.Stannane:BAAANQADCgUICQABNQADCggIJwAHAAAAAA==.Stellaloona:BAAANQADCgYIFgAAAA==.Sticks:BAAANQADCgcICQAAAA==.Stinkyhooves:BAAANQADCgQIBgABNQAECgQIBwAHAAAAAA==.Stromboli:BAAANQADCgUJBQAAAA==.',
Su='Sushiroll:BAABNQAECn8XAAMKAAgKXhf4eQCaAQAKAAYK4xb4eQCaAQATAAUKERetnABaAQAAAA==.',
Sw='Sweetsourrex:BAAANQAECgUIBQABNQAECgkJMwAZAL0eAA==.',
Ta='Tamaqua:BAABNQAECn8VAAIKAAcK0w/ZggCAAQAKAAcK0w/ZggCAAQAAAA==.',
Te='Telissa:BAAANQAECgEIAQAAAA==.Temoin:BAAANQAECgIIAwAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAAANQAECggIEQAAAA==.',
To='Toobrunner:BAAANQAECgUIBgAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAFFAQIDAAKAOoQAA==.',
Va='Vampress:BAAANQAECgMIBAAAAA==.Variam:BAABNQAECn8YAAIXAAcKMBgcdQAjAgAXAAcKMBgcdQAjAgAAAA==.',
Ve='Velannis:BAABNQAECn8kAAQeAAgKOiDkBACvAgAeAAgKOh/kBACvAgAYAAYKuBsZSACeAQAZAAMKKBcoOgDgAAAAAA==.',
Vo='Voidangel:BAAANQAECgEIAgAAAA==.Vonder:BAAANQAECgQIBAAAAA==.Voodooki:BAAANQAECgEIAwAAAA==.',
Vu='Vuo:BAABNQAECn8VAAIXAAcKHgzgpAC4AQAXAAcKHgzgpAC4AQAAAA==.',
Wa='Wayside:BAAANQAECgEIAQAAAA==.',
Wi='Winze:BAAANQAECgEIAQAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQAECgEIAQABNQAECggIHgALAJkdAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIDwAHAAAAAA==.',
Wu='Wuchese:BAAANQAECgMIAwABNQAECggIHgALAJkdAA==.',
Xf='Xfreshh:BAAANQAECgYIDAAAAA==.',
Ya='Yamaa:BAAANQAECgUIBwABNQAFFAMIBQABALsKAA==.Yamadono:BAAANQAECgQIBQABNQAFFAMIBQABALsKAA==.Yamá:BAAANQADCgcIBwABNQAFFAMIBQABALsKAA==.Yamå:BAACNQAFFH8FAAIBAAMKuwpXOADfAAABAAMKuwpXOADfAAA1AAQKfygAAgEACQopIeZJAO4CAAEACQopIeZJAO4CAAAA.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAAANQAECgUIEQABNQAECggIHgALAJkdAA==.',
Zo='Zortok:BAAANQAECgcIDAAAAA==.',
Zu='Zumoknight:BAAANQAECgEIAQABNQAECggICgAHAAAAAA==.',
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
