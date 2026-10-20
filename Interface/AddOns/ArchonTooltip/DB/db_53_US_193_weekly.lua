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

local lookup = {'Priest-Holy','DeathKnight-Blood','Unknown-Unknown','Priest-Shadow','Mage-Arcane','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Druid-Restoration','Monk-Brewmaster','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Warrior-Arms','Hunter-Survival','Shaman-Enhancement','Warrior-Fury','Evoker-Augmentation','Rogue-Assassination','Warlock-Affliction','Druid-Balance',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abelladanger:BAAANQAECgUICAAAAA==.',
Ad='Addilyn:BAABNQAECn8XAAIBAAgK4xkaHACZAQABAAgK4xkaHACZAQAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAABNQAECn8XAAICAAgKPg4VIQD2AAACAAgKPg4VIQD2AAAAAA==.Ahroo:BAAANQAECggIEwAAAQ==.Ahrue:BAAANQAECggIAgABNQAECggIEwADAAAAAQ==.',
Ai='Aikanaro:BAAANQAECgQIDgAAAA==.Airc:BAAANQAECgUIEwAAAA==.Aiurman:BAAANQADCgYIBgAAAA==.',
Aj='Ajanti:BAAANQAECgQIAwAAAA==.',
Al='Alfster:BAAANQAECgQIBQABNQAECgUIEAADAAAAAA==.Allanor:BAAANQADCgEIAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAABNQAECn8aAAMBAAgKWBXycADKAQABAAYK1hbycADKAQAEAAYKkw7aPwAwAQAAAA==.',
Ar='Argeikeranos:BAABNQAECn85AAMFAAoKRB+GIwCGAQAFAAoK/h2GIwCGAQAGAAMKkSJJDADEAAAAAA==.',
As='Asystole:BAAANQAECgEIAgAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAFFAQICwAHAKkTAA==.Atomicrednax:BAACNQAFFH8dAAMIAAgKqSBNAwBcAgAIAAcKvSBNAwBcAgAJAAEKRSAWLwBiAAA1AAQKf1AAAwgACgocJlUAAEwDAAgACgoIJlUAAEwDAAkAAQrwJIhJAUwAAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Ay='Ayisen:BAAANQAECgEIAQAAAA==.',
Ba='Ballsmonk:BAAANQAECgUIBQAAAA==.Ballsofury:BAACNQAFFH8IAAIKAAMKQSVGAABEAQAKAAMKQSVGAABEAQA1AAQKfyEAAgoACgp8JiEAABIEAAoACgp8JiEAABIEAAAA.Ballspally:BAAANQAECgcIBwAAAA==.Baptism:BAAANQAECgMIBQAAAA==.Battousaiha:BAABNQAECn8ZAAILAAgKgxWVRQA6AQALAAgKgxWVRQA6AQAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggICAABNQAFFAcIGgAMAPwkAA==.',
Bl='Blackcoffee:BAAANQAECgQIBwAAAA==.Blippi:BAAANQAECgEIAQABNQABCgQIBAADAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAwAAAA==.Bortikus:BAAANQADCgYIBwABNQAECggIJQACAOsbAA==.',
Bu='Burney:BAABNQAECn8tAAMNAAkK+h9HDADfAgANAAgK8B9HDADfAgAOAAgK/BqEEwAXAgAAAA==.Burnnotice:BAAANQADCgQIBQAAAA==.Busadinn:BAAANQAECggIEwAAAA==.',
['Bò']='Bònesaw:BAACNQAFFH8HAAIPAAMKEBstAgCPAAAPAAMKEBstAgCPAAA1AAQKfzQAAg8ACgpyIgMBAIQCAA8ACgpyIgMBAIQCAAAA.',
Ca='Calibrium:BAAANQAECgcIDgAAAA==.Carll:BAABNQAECn8wAAIQAAkK2B23HgD2AgAQAAkK2B23HgD2AgAAAA==.',
Ch='Chipmonk:BAAANQAECgEIAQAAAA==.Chister:BAABNQAECn8XAAIRAAgKuwzMMQCMAQARAAgKuwzMMQCMAQAAAA==.Cholomonga:BAAANQAECgYICwABNQAFFAcIGgAHAAMXAA==.Chotterboy:BAAANQABCgUIAwAAAA==.Churchill:BAAANQADCgUIBQABNQAFFAYIFAALAFMcAA==.',
Cl='Clonk:BAAANQADCgUIBQAAAA==.',
Co='Colisto:BAAANQADCgQIBAAAAA==.',
Cr='Crazedx:BAABNQAECn8XAAMSAAgKciMxBQASAwASAAgKNyMxBQASAwATAAMKAhqFSQDXAAABNQAFFAcIFgACAGccAA==.Cream:BAAANQAECgUIBQAAAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgQIBgAAAA==.',
Da='Daddy:BAABNQAECn8vAAMUAAoKRSFnAgA7AwAUAAoKTB1nAgA7AwAVAAgKmhXrWgBGAgAAAA==.Daito:BAAANQADCgQIBwAAAA==.Darig:BAAANQAECgMIBAAAAA==.Daryun:BAAANQAECgMIBAABNQAECgQIDgADAAAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimas:BAAANQAECgUICwAAAA==.Decimez:BAABNQAECn8YAAIHAAgK4RiuIQA1AQAHAAgK4RiuIQA1AQAAAA==.Decimock:BAABNQAECn8XAAIUAAgK6h60BgCeAgAUAAgK6h60BgCeAgAAAA==.Demonslunt:BAAANQADCgcIBwABNQAFFAYIFgAWAOMZAA==.',
Di='Digerati:BAAANQADCgYIBgAAAA==.Dingiswayo:BAABNQAECn8iAAITAAkKqBVbHgA/AgATAAkKqBVbHgA/AgAAAA==.Dingybing:BAAANQAECgUIDAAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.Dizan:BAAANQAECgMICgABNQAECgQIDgADAAAAAA==.',
Dp='Dpitis:BAABNQAECn8wAAMEAAoK6xzHDwD5AgAEAAoK6xzHDwD5AgABAAUKWxwogwCNAQAAAA==.',
Dr='Dragonflyy:BAAANQADCgQICQAAAA==.Draks:BAAANQAECgEIAgAAAA==.Drinkyds:BAABNQAECn8bAAIWAAkKLiGBJADUAgAWAAkKLiGBJADUAgAAAA==.',
Er='Eriebus:BAABNQAECn8WAAMXAAcKkhYiLgDQAQAXAAcKkhYiLgDQAQAYAAEK7QaylwAuAAAAAA==.Erona:BAABNQAECn8iAAIWAAgKix3fBQB5AgAWAAgKix3fBQB5AgAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ev='Evenstar:BAAANQAECgcIBwAAAA==.',
Ex='Extendo:BAABNQAECn8bAAIZAAkKvxMmBgDQAQAZAAkKvxMmBgDQAQAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAECgoKMAAEAOscAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAABNQAECn8WAAIUAAkKnwuhEgDfAQAUAAkKnwuhEgDfAQAAAA==.Feech:BAAANQADCgIIAgABNQAFFAcIDQALAAIXAA==.Felagain:BAAANQAECgQIBgAAAA==.Ferdinane:BAABNQAECn8ZAAIMAAcKahE4JwCkAQAMAAcKahE4JwCkAQAAAA==.',
Fi='Fidgety:BAAANQADCggIEQAAAA==.',
Fl='Flankshot:BAACNQAFFH8IAAIGAAMK6geTAQDHAAAGAAMK6geTAQDHAAA1AAQKfzMAAgYACgriFzoBACMCAAYACgriFzoBACMCAAAA.',
Fo='Foops:BAACNQAFFH8PAAMGAAUKkBfVAACqAQAGAAUKkBfVAACqAQAFAAEKAADwZwA3AAA1AAQKfx4AAgYACgpYHFMHAHwCAAYACgpYHFMHAHwCAAAA.Foopsadin:BAAANQAECgMICAABNQAFFAUIDwAGAJAXAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Fr='Freaky:BAAANQAECgEIAQAAAA==.',
Fu='Fumìn:BAAANQAECgUIDAAAAA==.',
Ga='Gallena:BAAANQAECgEIAQAAAA==.Gassommelier:BAAANQAECgEIAwAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAABNQAECn8YAAMQAAcKTxOaKwA0AQAQAAYKCBCaKwA0AQALAAUKCxJMNAHLAAAAAA==.Getrkt:BAABNQAECn8ZAAILAAgKvwmCxgCPAQALAAgKvwmCxgCPAQAAAA==.',
Gi='Gimblie:BAABNQAECn8cAAIBAAgK/xk+XQAKAgABAAgK/xk+XQAKAgAAAA==.Gimermonty:BAABNQAECn8cAAIJAAkK4Q40EgDfAQAJAAkK4Q40EgDfAQAAAA==.Gimixx:BAAANQAECggIEgAAAA==.',
Gl='Gladrielle:BAAANQAECgEIAgAAAA==.Glatzkaus:BAAANQAECgcICgAAAA==.Glockcena:BAAANQAECgEIBAAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAwAAAA==.',
Go='Gothegg:BAAANQAECgEIAQAAAA==.',
Gr='Greenline:BAAANQAECgEIAQABNQAECgcIGAAQAE8TAA==.Gripen:BAAANQAECgEIAgAAAA==.Gronk:BAAANQADCggICwAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQAECgEIAgAAAA==.',
Ha='Hakal:BAABNQAECn8yAAIaAAkKUiMWAQC+AgAaAAkKUiMWAQC+AgAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAABNQAECn8YAAMbAAgKZhCNGgAPAQAXAAcKFRDOOgBwAQAbAAYKsAuNGgAPAQAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAABNQAECn8dAAMcAAcKswnjNADLAAAcAAcKswnjNADLAAAZAAIKEgKi4wAwAAAAAA==.Hattshepsut:BAAANQADCgQIBAAAAA==.',
He='Healinghands:BAABNQAECn8UAAQdAAcKbRkLCgCtAQAdAAUKfyALCgCtAQABAAQK0Qwc0wCtAAAEAAMK6gGbaABfAAAAAA==.Hellz:BAABNQAECn8zAAIPAAoKhhm/CQCtAgAPAAoKhhm/CQCtAgAAAA==.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAABNQAECn8XAAIbAAgKcBplBQA1AQAbAAgKcBplBQA1AQAAAA==.',
Ic='Iceandfire:BAAANQAECgMIBAAAAA==.',
Ig='Igneel:BAABNQAECn8dAAIeAAkKzxY/BwBQAgAeAAkKzxY/BwBQAgABNQAECgoKMAAEAOscAA==.',
In='Inviteme:BAAANQAECgMIBAAAAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQAECgEIAQABNQAECgQIAwADAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAFFAMIBwAPABAbAA==.',
Jh='Jhamin:BAACNQAFFH8LAAIHAAQKqRMQBgDyAAAHAAQKqRMQBgDyAAA1AAQKfy4AAwcACgrJG+0EACoCAAcACgrJG+0EACoCABYAAwroBjj3AHwAAAAA.',
Jo='Joss:BAAANQAECgUICQAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Jubeiskyfang:BAAANQAECggICAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Jy='Jynken:BAAANQAECgQIBgABNQAECgQIDgADAAAAAA==.',
Ka='Kaedrelyn:BAAANQAECgYIEQAAAA==.Kageyuki:BAEANQAECgEIAQABNQAECggIFgAcAH4MAA==.',
Ke='Kennyman:BAAANQAECgEIAQAAAA==.Ketheric:BAAANQADCgMIAwAAAA==.',
Ki='Kindinos:BAAANQAECgEIAgAAAA==.',
Kl='Klickyy:BAAANQAECgQICwABNQAFFAcIDQALAAIXAA==.Kllcky:BAACNQAFFH8NAAILAAcKAhfKBAAVAgALAAcKAhfKBAAVAgA1AAQKfzMAAwsACgoiJhQDAOUDAAsACgoiJhQDAOUDABAAAQrMCKggATUAAAAA.',
Kr='Kraun:BAABNQAECn8kAAIJAAgKbiQoMQDZAgAJAAgKbiQoMQDZAgAAAA==.Kroo:BAABNQAECn8oAAITAAoKbBJMIgAXAgATAAoKbBJMIgAXAgAAAA==.',
Ku='Kurnon:BAAANQAECgQICAABNQAECgUIBgADAAAAAA==.',
Ky='Kyi:BAACNQAFFH8HAAITAAMKVRWjAwDqAAATAAMKVRWjAwDqAAA1AAQKfy8AAhMACgqQGLIBAHUCABMACgqQGLIBAHUCAAAA.',
La='Lammlock:BAAANQAECgYICAAAAA==.Landar:BAABNQAECn8rAAIRAAoKCRUPDwBTAQARAAoKCRUPDwBTAQAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECn8gAAIfAAkKHhMtBQB1AgAfAAkKHhMtBQB1AgAAAA==.',
Lo='Lockonyou:BAABNQAECn8VAAIVAAcK6gcWwgBHAQAVAAcK6gcWwgBHAQAAAA==.Losthack:BAABNQAECn8cAAMQAAcKRSQnJADaAgAQAAcKRSQnJADaAgALAAUKVgn7nwCeAAAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgcIEgAAAA==.',
Ma='Mahra:BAAANQAECgYIEQAAAA==.Manchasone:BAABNQAECn8VAAILAAcKKiXwOwDjAgALAAcKKiXwOwDjAgAAAA==.Mangreese:BAABNQAECn8YAAMgAAgKOwokHQCRAQAgAAgKOwokHQCRAQAHAAEKxwNFmwAqAAAAAA==.',
Me='Meekseek:BAAANQAECggIDAAAAA==.',
Mi='Miahealifa:BAABNQAECn8XAAMBAAcKNhU1cwDCAQABAAcKNhU1cwDCAQAEAAEKtgNsggAnAAAAAA==.Miasma:BAAANQAECgUIEgAAAA==.Micaiah:BAAANQAECgQICQAAAA==.Mistabubbles:BAAANQAECgcIDwAAAA==.Mistyjp:BAAANQAECgMIAwABNQAFFAcIGgAHAAMXAA==.',
Mk='Mk:BAAANQAECgcICgAAAA==.',
Mo='Mochi:BAAANQAECgEIAgAAAA==.Mograinez:BAACNQAFFH8dAAMZAAgKAyYlAADvAgAZAAgKAyYlAADvAgACAAEKAADjNQAnAAA1AAQKfx8AAhkACgrZJgMOAEkDABkACgrZJgMOAEkDAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.',
Ne='Necrussy:BAAANQAECgEIAQAAAA==.Nekrohealia:BAAANQAECggIEQAAAA==.Neteyam:BAAANQAECgQIBQAAAA==.',
No='Nogitsune:BAAANQAECgQIBAAAAA==.Noluck:BAAANQAECgEIAgAAAA==.Norolock:BAABNQAECn8XAAIVAAgK+BRuNwAkAQAVAAgK+BRuNwAkAQAAAA==.',
Nu='Nuovis:BAAANQAECgEIAQAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgQICwABNQAFFAcIDQALAAIXAA==.',
Og='Oghlin:BAABNQAECn8ZAAITAAkKZhxKFwCRAgATAAkKZhxKFwCRAgAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBgAAAA==.',
Ol='Oldshotz:BAABNQAECn8aAAIJAAYKURMhvACLAQAJAAYKURMhvACLAQAAAA==.',
Om='Omgsteak:BAAANQAECgYIEgAAAA==.',
On='Onlybusa:BAAANQAECgUICwAAAA==.',
Or='Orcofwar:BAAANQADCgYIBgAAAA==.',
Pa='Palidan:BAAANQAECgcIDgAAAA==.Panzerwolf:BAECNQAFFH8VAAIPAAcKyiMYAADqAgAPAAcKyiMYAADqAgA1AAQKf0gABA8ACgrMJc4BAKoDAA8ACgrMJc4BAKoDACEACQooH4IDAB0DAB4ACAqMG1RmAFwCAAAA.Papilock:BAAANQAECgEIAQAAAA==.Parsnip:BAAANQAECgQICgAAAA==.',
Pr='Pray:BAAANQAECgUICgAAAA==.Prayforme:BAABNQAECn83AAMdAAoKiySZAQAxAwAdAAgKMCOZAQAxAwABAAcKViByCQBOAgAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECn8kAAMWAAkKHA3haADSAQAWAAkKHA3haADSAQAHAAIKtAQ9lwAxAAAAAA==.Psychopompos:BAAANQADCggICAABNQAECgoKOQAFAEQfAA==.',
Qr='Qreigns:BAAANQAECgcICgAAAA==.',
Qw='Qweh:BAAANQAECgYIDAAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAABNQAECn8iAAMOAAkKvRZZEABSAgAOAAkKpBJZEABSAgAiAAYK2he+CgC/AQAAAA==.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECn8oAAIjAAcKZx4DJwBWAgAjAAcKZx4DJwBWAgAAAA==.Razkal:BAABNQAECn8XAAIJAAgKIBW0egAZAgAJAAgKIBW0egAZAgAAAA==.Razpal:BAAANQAECgYIBgAAAA==.',
Re='Revirginator:BAAANQAECgQIBwAAAA==.',
Ri='Rimreaper:BAAANQAECgUIDQAAAA==.',
Rn='Rngesus:BAACNQAFFH8GAAIVAAQKXQYYKADGAAAVAAQKXQYYKADGAAA1AAQKfy0AAxUACgr0HX0UAKUBABUACgomHH0UAKUBACQAAgorEVEfAH4AAAE1AAUUBAgLAAcAqRMA.',
Ru='Ruffle:BAAANQAECgYIBQABNQAECgcIDgADAAAAAA==.Runie:BAEANQADCgQIBAABNQAFFAcIGgAeAGUWAA==.Rushem:BAAANQAECggIEgAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAACNQAFFH8FAAIVAAMKGxemBgD+AAAVAAMKGxemBgD+AAA1AAQKfyQAAxUACgr/Gs4MAOQBABUACgr/Gs4MAOQBABQAAQr+GMYSAEgAAAAA.Ràyà:BAAANQADCgQIBAAAAA==.',
Sa='Saenen:BAABNQAECn8cAAIKAAcK/w1DFwCFAQAKAAcK/w1DFwCFAQAAAA==.',
Sc='Scorchi:BAAANQAECgQJCAAAAA==.',
Se='Serenity:BAAANQAECgEIAQAAAA==.Seseria:BAABNQAECn8tAAIQAAoKRRvzBACOAgAQAAoKRRvzBACOAgAAAA==.Sevinofnine:BAAANQAECgUIDQAAAA==.',
Sh='Shadowsong:BAAANQAECgcIDwAAAA==.Shaithis:BAAANQAECgEIAQAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwADAAAAAA==.Shanic:BAABNQAECn8WAAIlAAcKvhFaJADVAAAlAAcKvhFaJADVAAAAAA==.Shavedcat:BAAANQADCgMIAwAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shinokami:BAAANQAECggIAQAAAA==.Shocktart:BAAANQAECgIIAgAAAA==.',
Si='Siheal:BAAANQAECgMIBQAAAA==.',
Sl='Sleeping:BAAANQAECgEIAQAAAA==.Sliceanddice:BAAANQAECgQIBAAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAcIGgAHAAMXAA==.Snipyterror:BAACNQAFFH8aAAMHAAcKAxcqCgDJAQAHAAUKJBkqCgDJAQAWAAMKDBCWFwDmAAA1AAQKfykAAwcACgo/I5YNAHwDAAcACQpDI5YNAHwDABYAAwqyBskFAV0AAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.',
Sp='Spacejam:BAAANQADCgYIGQAAAA==.Specimenb:BAAANQAECggIDQAAAA==.Spirallidan:BAABNQAECn8lAAMYAAkKyxeFIgCHAgAYAAkKyxeFIgCHAgAXAAQKZwrAVQC5AAAAAA==.',
St='Staticsrexar:BAABNQAECn8gAAQJAAcK/xMxRAAtAQAJAAcK/xMxRAAtAQAfAAEKJQa0EgA9AAAIAAEKAABEmQAnAAAAAA==.Stayk:BAAANQADCggIDQAAAA==.Stepbro:BAAANQAECgIIAgABNQAECgMIBAADAAAAAA==.Stinksauce:BAABNQAECn8hAAQNAAkKNxdoEgCGAgANAAkKNxdoEgCGAgAiAAUK8xv5CwCbAQAOAAQKyA5zJwD3AAAAAA==.Strokntotem:BAAANQAECgQICgAAAA==.',
Su='Superchunk:BAAANQAECgIIBAAAAA==.Sutra:BAABNQAECn8VAAIBAAkKwhBwawDcAQABAAkKwhBwawDcAQAAAA==.',
Sy='Sylmarillion:BAAANQAECgUIBgAAAA==.',
Ta='Talgulen:BAABNQAECn8rAAIOAAkKkhqIAQD5AQAOAAkKkhqIAQD5AQAAAA==.Tarquinius:BAAANQAECgUJDwAAAA==.Tasahof:BAAANQAECggIAQAAAA==.Taxii:BAAANQAECgUIDAABNQAECgoKLAAeACklAA==.Taynte:BAAANQAECgcIDgAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAABNQAECn8WAAIVAAcK4QnfqwB7AQAVAAcK4QnfqwB7AQABNQAFFAMIBwATAFUVAA==.Thrag:BAAANQAECgIIAwABNQAECgQIDgADAAAAAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.Tiffèrny:BAAANQAECgEIAQAAAA==.',
To='Tone:BAAANQAECggIDAAAAA==.Torokai:BAAANQAECggICwAAAA==.Torokami:BAAANQAECggIAwAAAA==.Torokuma:BAAANQAECggIBwAAAA==.Toroshinu:BAAANQAECggIAwAAAA==.Torotatsu:BAAANQAECgIIAwAAAA==.Totemlycool:BAAANQAECgUIBwABNQAECgoKKAATAGwSAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAABNQAECn8nAAMJAAkKURYYRACfAgAJAAkKURYYRACfAgAfAAEKAAAqCwAAAAAAAA==.Treehuggër:BAABNQAECn8ZAAMRAAcKHhQHLwCiAQARAAcKHhQHLwCiAQAlAAIKnQj0pQBNAAAAAA==.Trelia:BAAANQAECgEIAQAAAA==.Trogkin:BAABNQAECn8fAAIlAAoKPxcrLQBzAgAlAAoKPxcrLQBzAgABNQAFFAgIGAAIAD4YAA==.',
Ty='Tyrith:BAABNQAECn8gAAIeAAoKoB7/KQATAwAeAAoKoB7/KQATAwAAAA==.',
Ug='Ugotgotpal:BAABNQAECn8XAAILAAgKDAhU0gB3AQALAAgKDAhU0gB3AQAAAA==.',
Ul='Ulazain:BAABNQAECn8rAAIhAAkKyBnGAQDkAQAhAAkKyBnGAQDkAQAAAA==.',
Um='Umadcuzbad:BAAANQADCgcICQAAAA==.',
Us='Usdaprime:BAABNQAECn8UAAIKAAkKMQl6GwBLAQAKAAkKMQl6GwBLAQAAAA==.',
Va='Vaas:BAAANQAECgYICwAAAA==.Vaporeön:BAAANQAECgcIDQAAAA==.Varrasha:BAAANQABCgIIAgAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAABNQAECn8cAAILAAcKcw28zQCAAQALAAcKcw28zQCAAQAAAA==.',
Vo='Vodilent:BAAANQAECgUIBQAAAA==.Voidarella:BAAANQABCgMIAwABNQAECgoKLgALANMZAA==.',
['Vè']='Vèx:BAABNQAECn8wAAIeAAkKfB+YMwDyAgAeAAkKfB+YMwDyAgAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgcIFQAVAOoHAA==.Watlas:BAAANQAECgcIDgABNQAFFAMIBgAZAN4TAA==.',
Xa='Xavia:BAABNQAECn8YAAIVAAcKERJySgD0AAAVAAcKERJySgD0AAAAAA==.',
Yu='Yunaraa:BAAANQAECgIJAwABNQAECgkJJwAJAFEWAA==.',
Yv='Yvana:BAAANQAECgEIAQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMICAABNQAFFAgIGwAlAOEhAA==.',
Zo='Zombies:BAABNQAECn8WAAIZAAgKMBerFAA5AQAZAAgKMBerFAA5AQAAAA==.',
Zu='Zugmaster:BAABNQAECn8xAAIjAAoKARi0BADeAQAjAAoKARi0BADeAQAAAA==.Zugszy:BAAANQAECgMIAwAAAA==.Zulureus:BAAANQAECgEIAQAAAA==.',
Zy='Zynn:BAAANQAECgEJAgABNQABCgQIBAADAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFH8bAAIlAAgK4SHYAQDUAgAlAAgK4SHYAQDUAgA1AAQKfx0AAiUACgo4JKgSADMDACUACgo4JKgSADMDAAAA.Zzephyrmage:BAAANQAECgUICAABNQAFFAgIGwAlAOEhAA==.',
['Çä']='Çärvé:BAAANQADCgIIAgAAAA==.',
['Ôä']='Ôäk:BAAANQADCgUIBQABNQAECgUIFAARAMsMAA==.',
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
