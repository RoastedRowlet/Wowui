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

local lookup = {'Priest-Holy','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Mage-Arcane','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Warrior-Fury','Paladin-Holy','Druid-Restoration','Monk-Brewmaster','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Druid-Balance','Hunter-Survival','Shaman-Enhancement','Evoker-Augmentation','Rogue-Assassination','Warlock-Affliction',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abelladanger:BAAANQAECgUIBwAAAA==.',
Ad='Addilyn:BAABNQAECn8cAAIBAAgKlBpsPgC7AQABAAgKlBpsPgC7AQAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAABNQAECn8cAAICAAgKww9nOQD+AAACAAgKww9nOQD+AAAAAA==.Ahroo:BAAANQAECggIFAAAAQ==.Ahrue:BAAANQAECggIBAABNQAECggIFAADAAAAAQ==.',
Ai='Aikanaro:BAAANQAECgQIDwAAAA==.Airc:BAABNQAECn8aAAIEAAcK9wkorQD9AAAEAAcK9wkorQD9AAAAAA==.Aiurman:BAAANQADCgcICQAAAA==.',
Aj='Ajanti:BAAANQAECgQIAwAAAA==.',
Al='Aleric:BAAANQAECgMIAwAAAA==.Alfster:BAAANQAECgQIBAABNQAECgUIEAADAAAAAA==.Allanor:BAAANQADCgEIAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAABNQAECn8eAAMBAAoKbxTycADKAQABAAgKUxXycADKAQAFAAYKkw7aPwAwAQAAAA==.',
Ar='Argeikeranos:BAABNQAECn85AAMGAAoKRB9gSgDtAgAGAAoK/h1gSgDtAgAHAAMKkSKeKACwAAAAAA==.',
As='Asystole:BAAANQADCgEIAQAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAFFAQICwAIAKkTAA==.Atomicrednax:BAACNQAFFH8dAAMJAAgKqSBNAwBcAgAJAAcKvSBNAwBcAgAKAAEKRSAWLwBiAAA1AAQKf2wAAwkACgomJnAAAHQDAAkACgoSJnAAAHQDAAoAAQrwJKXmAGgAAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Ay='Ayisen:BAAANQADCgYICgAAAA==.',
Ba='Ballsmonk:BAAANQAECgYIBgAAAA==.Ballsofury:BAACNQAFFH8IAAILAAMKQSV9AAA5AQALAAMKQSV9AAA5AQA1AAQKfyMAAgsACgrvJiEAABIEAAsACgrvJiEAABIEAAAA.Ballspally:BAAANQAECggICQAAAA==.Baptism:BAAANQAECgQIBwAAAA==.Battousaiha:BAABNQAECn8fAAIEAAkKvxVAbwB2AQAEAAkKvxVAbwB2AQAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggICAABNQAFFAcIGwAMAPwkAA==.',
Bl='Blackcoffee:BAAANQAECgUIBwAAAA==.Blippi:BAAANQADCgQIBgABNQABCgQIBAADAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAQAAAA==.Bortikus:BAAANQADCgYIBwABNQAECgkJKgACAOAbAA==.',
Bu='Burney:BAABNQAECn82AAMNAAoKGB80BgCOAgANAAoKGB80BgCOAgAOAAgK/BqEEwAXAgAAAA==.Burnnotice:BAAANQADCgYICwAAAA==.Busadinn:BAABNQAECn8aAAIEAAkKARywdwA9AgAEAAkKARywdwA9AgAAAA==.',
['Bò']='Bònesaw:BAACNQAFFH8HAAIPAAMKEBsOBQC+AAAPAAMKEBsOBQC+AAA1AAQKfzoAAw8ACgqdIlMCAJQDAA8ACgqdIlMCAJQDABAAAgrcDC4aAGsAAAAA.',
Ca='Calibrium:BAAANQAECgcIDQAAAA==.Carll:BAABNQAECn83AAIRAAoKqh23HgD2AgARAAoKqh23HgD2AgAAAA==.',
Ch='Chipmonk:BAAANQAECgIIAQAAAA==.Chister:BAABNQAECn8XAAISAAgKuwzMMQCMAQASAAgKuwzMMQCMAQAAAA==.Cholomonga:BAAANQAECgYICwABNQAFFAcIGgAIAAMXAA==.Chotterboy:BAAANQABCgUIAwAAAA==.Churchill:BAAANQADCgUIBQABNQAFFAYIFQAEAFMcAA==.',
Cl='Clonk:BAAANQADCgUIBQAAAA==.',
Cr='Crazedx:BAABNQAECn8fAAMTAAoKViMxBQASAwATAAkKtCIxBQASAwAUAAQKGB2FSQDXAAABNQAFFAcIFgACAGccAA==.Cream:BAAANQAECgUIBQAAAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgQIBgAAAA==.',
Da='Daddy:BAACNQAFFH8FAAIVAAMKAAbJKQC4AAAVAAMKAAbJKQC4AAA1AAQKfzQAAxYACgpFIWcCADsDABYACgpMHWcCADsDABUACAqaFetaAEYCAAAA.Daito:BAAANQADCgQIBwAAAA==.Darig:BAAANQAECgMIAgAAAA==.Daryun:BAAANQAECgMIBwABNQAECgQIDwADAAAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimas:BAAANQAECgUICgAAAA==.Decimez:BAABNQAECn8eAAIIAAgK4Rg4VAApAgAIAAgK4Rg4VAApAgAAAA==.Decimock:BAABNQAECn8cAAIWAAgK6h60BgCeAgAWAAgK6h60BgCeAgAAAA==.Demonslunt:BAAANQADCgcIBwABNQAFFAYIFgAXAOMZAA==.',
Di='Digerati:BAAANQADCggIDAAAAA==.Dingiswayo:BAABNQAECn8iAAIUAAkKqBVbHgA/AgAUAAkKqBVbHgA/AgAAAA==.Dingybing:BAAANQAECgUICgAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.Dizan:BAAANQAECgQIDAABNQAECgQIDwADAAAAAA==.',
Dp='Dpitis:BAABNQAECn80AAMFAAoKCx3HDwD5AgAFAAoKCx3HDwD5AgABAAUK2h0ogwCNAQABNQAECgkJIQAYAMcbAA==.',
Dr='Dragonflyy:BAAANQADCgQICQAAAA==.Draks:BAAANQAECgEIAgAAAA==.Drinkyds:BAABNQAECn8bAAIXAAkKLiGBJADUAgAXAAkKLiGBJADUAgAAAA==.',
Er='Eriebus:BAABNQAECn8WAAMZAAcKkhYiLgDQAQAZAAcKkhYiLgDQAQAaAAEK7QaylwAuAAAAAA==.Erona:BAABNQAECn8oAAIXAAkKfRxwFQCcAgAXAAkKfRxwFQCcAgAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ev='Evenstar:BAAANQAECgcIBwAAAA==.',
Ex='Extendo:BAABNQAECn8hAAIbAAkKwxoNDwAsAgAbAAkKwxoNDwAsAgAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAECgkJIQAYAMcbAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAABNQAECn8dAAIWAAkKyQ6hEgDfAQAWAAkKyQ6hEgDfAQAAAA==.Feech:BAAANQADCgIIAgABNQAFFAcIDQAEAAIXAA==.Felagain:BAAANQAECgQIBAAAAA==.Ferdinane:BAABNQAECn8gAAIMAAcKHRI4JwCkAQAMAAcKHRI4JwCkAQAAAA==.',
Fi='Fidgety:BAAANQADCggIEQAAAA==.',
Fl='Flankshot:BAACNQAFFH8IAAIHAAMK6gfoAgC/AAAHAAMK6gfoAgC/AAA1AAQKfzcAAgcACgrqHH8DAFkCAAcACgrqHH8DAFkCAAAA.',
Fo='Foops:BAACNQAFFH8PAAMHAAUKkBfVAACqAQAHAAUKkBfVAACqAQAGAAEKAADwZwA3AAA1AAQKfygAAgcACgovIigCAKkCAAcACgovIigCAKkCAAAA.Foopsadin:BAAANQAECgMIBgABNQAFFAUIDwAHAJAXAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Fr='Freaky:BAAANQADCggICAAAAA==.',
Fu='Fumìn:BAAANQAECgYIEQAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAABNQAECn8dAAMRAAcKoxbLUQBRAQARAAYK6hPLUQBRAQAEAAUKCxJMNAHLAAAAAA==.Getrkt:BAABNQAECn8ZAAIEAAgKvwmCxgCPAQAEAAgKvwmCxgCPAQAAAA==.',
Gi='Gimblie:BAABNQAECn8nAAIBAAkKxh/vCgAxAwABAAkKxh/vCgAxAwAAAA==.Gimermonty:BAABNQAECn8gAAIKAAkKYRQCPADxAQAKAAkKYRQCPADxAQAAAA==.Gimixx:BAAANQAECggIEAAAAA==.',
Gl='Gladrielle:BAAANQAECgEIAQAAAA==.Glatzkaus:BAAANQAECgcICAAAAA==.Glockcena:BAAANQAECgIIBAAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAQAAAA==.',
Gr='Greenline:BAAANQAECgUIBwABNQAECgcIHQARAKMWAA==.Gripen:BAAANQABCggICwAAAA==.Gronk:BAAANQADCggICwAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQABCgQIBAAAAA==.',
Ha='Hakal:BAABNQAECn84AAIcAAkKiiMkBQC3AgAcAAkKiiMkBQC3AgAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAABNQAECn8bAAMdAAkK4BCNGgAPAQAZAAgKsRDOOgBwAQAdAAYKsAuNGgAPAQAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAABNQAECn8fAAMeAAcKswlXYgAbAQAeAAcKswlXYgAbAQAbAAIKEgKi4wAwAAAAAA==.Hattshepsut:BAAANQADCgQIBAAAAA==.',
He='Healinghands:BAABNQAECn8bAAQfAAgK4h3SAQBPAgAfAAgK4h3SAQBPAgABAAQK0Qwc0wCtAAAFAAMK6gGbaABfAAAAAA==.Hellz:BAABNQAECn89AAIPAAoK3xm/CQCtAgAPAAoK3xm/CQCtAgAAAA==.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAABNQAECn8cAAIdAAgKFRvICwAQAgAdAAgKFRvICwAQAgAAAA==.',
Ic='Iceandfire:BAAANQAECgMIBQAAAA==.',
Ig='Igneel:BAABNQAECn8hAAIYAAkKxxtfJABZAgAYAAkKxxtfJABZAgAAAA==.',
In='Inviteme:BAAANQAECgMIAwAAAA==.',
Io='Ionisa:BAAANQADCggICAAAAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQADCggICAABNQAECgQIAwADAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAFFAMIBwAPABAbAA==.',
Jh='Jhamin:BAACNQAFFH8LAAIIAAQKqROICgDiAAAIAAQKqROICgDiAAA1AAQKfzIAAwgACgrSH/oTAGoCAAgACgrSH/oTAGoCABcAAwroBjj3AHwAAAAA.',
Jo='Joss:BAAANQAECgUICgAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Jubeiskyfang:BAAANQAECggICAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Jy='Jynken:BAAANQAECgQIBAABNQAECgQIDwADAAAAAA==.',
Ka='Kaedrelyn:BAABNQAECn8WAAMgAAYK8QRHdgDxAAAgAAYK8QRHdgDxAAASAAIKIwZKXwAmAAAAAA==.Kageyuki:BAEANQAECgEIAQABNQAFFAEIBgAeAAAAAA==.',
Ke='Kennyman:BAAANQADCgQIBAAAAA==.Ketheric:BAAANQADCgMIAwAAAA==.',
Ki='Kindinos:BAAANQADCggIHgAAAA==.',
Kl='Klickyy:BAAANQAECgQICwABNQAFFAcIDQAEAAIXAA==.Kllcky:BAACNQAFFH8NAAIEAAcKAhfKBAAVAgAEAAcKAhfKBAAVAgA1AAQKfz0AAwQACgr+JhQDAOUDAAQACgr+JhQDAOUDABEAAQrMCKggATUAAAAA.',
Kr='Kraun:BAABNQAECn8pAAIKAAgKbiQoMQDZAgAKAAgKbiQoMQDZAgAAAA==.Kroo:BAABNQAECn8sAAIUAAoKbBJMIgAXAgAUAAoKbBJMIgAXAgAAAA==.',
Ku='Kurnon:BAAANQAECgQICAABNQAECgUIBgADAAAAAA==.',
Kv='Kvothè:BAAANQADCgcIBwABNQAECgcICwADAAAAAA==.',
Ky='Kyi:BAACNQAFFH8HAAIUAAMKVRUZBgDeAAAUAAMKVRUZBgDeAAA1AAQKfzYAAhQACgrVGv8JAGMCABQACgrVGv8JAGMCAAAA.',
La='Lammlock:BAAANQAECgYICQAAAA==.Landar:BAABNQAECn8xAAISAAoKVxWGHABQAgASAAoKVxWGHABQAgAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECn8gAAIhAAkKHhMtBQB1AgAhAAkKHhMtBQB1AgAAAA==.',
Lo='Lockonyou:BAABNQAECn8VAAIVAAcK6gcWwgBHAQAVAAcK6gcWwgBHAQAAAA==.Losthack:BAABNQAECn8hAAMRAAcKXSQnJADaAgARAAcKXSQnJADaAgAEAAUKVgnL8QCSAAAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgcIEQAAAA==.',
Ma='Mahra:BAAANQAECgYIEQAAAA==.Manchasone:BAABNQAECn8aAAIEAAgKTSPwOwDjAgAEAAgKTSPwOwDjAgAAAA==.Mangreese:BAABNQAECn8cAAMiAAkKLQwkHQCRAQAiAAkKLQwkHQCRAQAIAAEKxwMe0wAgAAAAAA==.',
Me='Meekseek:BAAANQAECggICgAAAA==.',
Mi='Miahealifa:BAABNQAECn8aAAMBAAgKhRQ1cwDCAQABAAgKhRQ1cwDCAQAFAAEKtgOlTAAoAAAAAA==.Miasma:BAAANQAECgUIDQAAAA==.Micaiah:BAAANQAECgQIBQAAAA==.Milkmë:BAAANQADCgMIAwAAAA==.Mistabubbles:BAAANQAECgcIDwAAAA==.Mistyjp:BAAANQAECgMIAwABNQAFFAcIGgAIAAMXAA==.',
Mk='Mk:BAAANQAECgcIDQAAAA==.',
Mo='Mochi:BAAANQABCgIIAgAAAA==.Mograinez:BAACNQAFFH8dAAMbAAgKAyYlAADvAgAbAAgKAyYlAADvAgACAAEKAADjNQAnAAA1AAQKfyAAAhsACgr3JgMOAEkDABsACgr3JgMOAEkDAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.',
Ne='Necrussy:BAAANQADCgIIAgAAAA==.Nekrohealia:BAAANQAECgcIDwAAAA==.Neteyam:BAAANQAECggIDQAAAA==.',
No='Nogitsune:BAAANQAECgQIBAAAAA==.Norolock:BAABNQAECn8XAAIVAAgK+BSRhwDTAQAVAAgK+BSRhwDTAQAAAA==.',
Nu='Nuovis:BAAANQADCgYIBgAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgQICgABNQAFFAcIDQAEAAIXAA==.',
Og='Oghlin:BAABNQAECn8eAAIUAAkKyx5KFwCRAgAUAAkKyx5KFwCRAgAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBAAAAA==.',
Ol='Oldshotz:BAABNQAECn8eAAIKAAcK/BAhvACLAQAKAAcK/BAhvACLAQAAAA==.',
Om='Omgsteak:BAABNQAECn8ZAAMPAAcKiwHUNACPAAAPAAcKiwHUNACPAAAYAAEKAAD8bQEUAAAAAA==.',
On='Onlybusa:BAAANQAECgUIBwAAAA==.',
Or='Orcofwar:BAAANQADCgYIBgAAAA==.',
Pa='Palidan:BAAANQAECgcIEAAAAA==.Panzerwolf:BAECNQAFFH8VAAIPAAcKyiMYAADqAgAPAAcKyiMYAADqAgA1AAQKf1MABA8ACgo1JmsAAHQDAA8ACgo1JmsAAHQDABAACQooH4IDAB0DABgACAqMG1RmAFwCAAAA.Parsnip:BAAANQAECgQICgAAAA==.',
Pr='Pray:BAAANQAECggIEQAAAA==.Prayforme:BAABNQAECn9AAAMfAAoKlySZAQAxAwABAAoKqh35CABNAwAfAAgKMCOZAQAxAwAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECn8pAAMXAAoK5w3haADSAQAXAAoK5w3haADSAQAIAAIKtASdygAuAAAAAA==.Psychopompos:BAAANQADCggICAABNQAECgoKOQAGAEQfAA==.',
Qr='Qreigns:BAAANQAECgYICgAAAA==.',
Qw='Qweh:BAAANQAECgUICwAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAACNQAFFH8FAAMjAAMKlgv0BADEAAAjAAMKlgv0BADEAAAOAAEKJQjHBgA7AAA1AAQKfyMAAw4ACgqqFVkQAFICAA4ACQqkElkQAFICACMABwo8Fr4KAL8BAAAA.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECn8oAAIkAAcKZx4DJwBWAgAkAAcKZx4DJwBWAgAAAA==.Razkal:BAABNQAECn8hAAIKAAoK/hXzNgAEAgAKAAoK/hXzNgAEAgAAAA==.Razpal:BAAANQAECgUIBQAAAA==.',
Re='Revirginator:BAAANQAECgQIBwAAAA==.',
Ri='Rimreaper:BAAANQAECgUICwAAAA==.',
Rn='Rngesus:BAACNQAFFH8GAAIVAAQKXQYYKADGAAAVAAQKXQYYKADGAAA1AAQKfzcAAxUACgp8H+ASAJICABUACgqzHuASAJICACUAAgorEVEfAH4AAAE1AAUUBAgLAAgAqRMA.',
Ru='Ruffle:BAAANQAECgUIBQABNQAECgoKGQAIAAgSAA==.Runie:BAEANQADCgQIBAABNQAFFAcIGwAYAGUWAA==.Rushem:BAABNQAECn8XAAIYAAgKVhCLdgAqAQAYAAgKVhCLdgAqAQAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAACNQAFFH8FAAIVAAMKGxdfDADxAAAVAAMKGxdfDADxAAA1AAQKfyoAAxUACgoJHoAhAP4CABUACgoJHoAhAP4CABYAAQr+GLklAEAAAAAA.Ràyà:BAAANQADCgQIBAAAAA==.',
Sa='Saenen:BAABNQAECn8fAAILAAgKMw5DFwCFAQALAAgKMw5DFwCFAQAAAA==.',
Sc='Scorchi:BAAANQAECgQJBwAAAA==.',
Se='Seseria:BAABNQAECn8xAAIRAAoKghy0FgCPAgARAAoKghy0FgCPAgAAAA==.Sevinofnine:BAAANQAECgQICgAAAA==.',
Sh='Shadowsong:BAAANQAECgcICgAAAA==.Shaithis:BAAANQADCgQIBgAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwADAAAAAA==.Shanic:BAABNQAECn8bAAIgAAcKChPBTQCpAQAgAAcKChPBTQCpAQAAAA==.Shavedcat:BAAANQADCgMIAwAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shinokami:BAAANQAECggIAQAAAA==.Shocktart:BAAANQAECgMIAwAAAA==.',
Si='Siheal:BAAANQAECgMIBAAAAA==.',
Sl='Sleeping:BAAANQAECgEIAQAAAA==.Sliceanddice:BAAANQAECgQIBwAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAcIGgAIAAMXAA==.Snipyterror:BAACNQAFFH8aAAMIAAcKAxcqCgDJAQAIAAUKJBkqCgDJAQAXAAMKDBCWFwDmAAA1AAQKfykAAwgACgo/I5YNAHwDAAgACQpDI5YNAHwDABcAAwqyBskFAV0AAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.',
Sp='Spacejam:BAAANQADCgYIHwAAAA==.Specimenb:BAAANQAECggIEQAAAA==.Spirallidan:BAABNQAECn8qAAMaAAoKNheFIgCHAgAaAAoKNheFIgCHAgAZAAQKZwrAVQC5AAAAAA==.',
St='Staticsrexar:BAABNQAECn8jAAQKAAkKOhFxVQCcAQAKAAkKOhFxVQCcAQAhAAEKJQa0EgA9AAAJAAEKAABEmQAnAAAAAA==.Stayk:BAAANQADCggIDQAAAA==.Stepbro:BAAANQAECgIIAgABNQAECgMIAwADAAAAAA==.Stinksauce:BAABNQAECn8hAAQNAAkKNxdoEgCGAgANAAkKNxdoEgCGAgAjAAUK8xv5CwCbAQAOAAQKyA5zJwD3AAAAAA==.Strokntotem:BAAANQAECgQIDgAAAA==.',
Su='Superchunk:BAAANQAECgIIAwAAAA==.Sutra:BAAANQAECgcIEwAAAA==.',
Sy='Sylmarillion:BAAANQAECgUIBgAAAA==.',
Ta='Talgulen:BAABNQAECn8yAAIOAAoKkhjNBAAWAgAOAAoKkhjNBAAWAgAAAA==.Tarquinius:BAAANQAECgUJDwAAAA==.Taxii:BAAANQAECgYIDwABNQAECgoKMAAYALAlAA==.Taynte:BAAANQAECgcIDQAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAABNQAECn8YAAIVAAcK4QnfqwB7AQAVAAcK4QnfqwB7AQABNQAFFAMIBwAUAFUVAA==.Theoshun:BAAANQAECgUIBQAAAA==.Thrag:BAAANQAECgIIAgABNQAECgQIDwADAAAAAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.',
To='Tone:BAAANQAECggICgAAAA==.Torokai:BAAANQAECggICgAAAA==.Torokami:BAAANQAECggIAgAAAA==.Torokuma:BAAANQAECggIBwAAAA==.Toroshinu:BAAANQAECggIAQAAAA==.Torotatsu:BAAANQAECgIIAgAAAA==.Totemlycool:BAAANQAECgUIBwABNQAECgoKLAAUAGwSAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAABNQAECn8oAAMKAAkKjhYYRACfAgAKAAkKjhYYRACfAgAhAAEKAACHDwAAAAAAAA==.Treehuggër:BAABNQAECn8aAAMSAAgKNhMHLwCiAQASAAcKHhQHLwCiAQAgAAMKDwb0pQBNAAAAAA==.Trelia:BAAANQADCgQIBAAAAA==.Trogkin:BAABNQAECn8fAAIgAAoKPxcrLQBzAgAgAAoKPxcrLQBzAgABNQAFFAgIGQAJAD4YAA==.',
Tw='Twîsty:BAAANQADCgQIBAAAAA==.',
Ty='Tyrith:BAABNQAECn8qAAIYAAoKyCAvGACnAgAYAAoKyCAvGACnAgAAAA==.',
Ug='Ugotgotpal:BAABNQAECn8XAAIEAAgKDAhU0gB3AQAEAAgKDAhU0gB3AQAAAA==.',
Ul='Ulazain:BAABNQAECn8yAAIQAAoKWxjJBgCXAgAQAAoKWxjJBgCXAgAAAA==.',
Um='Umadcuzbad:BAAANQADCgcICQAAAA==.',
Us='Usdaprime:BAABNQAECn8UAAILAAkKMQl6GwBLAQALAAkKMQl6GwBLAQAAAA==.',
Va='Vaas:BAAANQAECgYICwAAAA==.Vaporeön:BAAANQAECgcIDQAAAA==.Varrasha:BAAANQABCgIIAgAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAABNQAECn8fAAIEAAgK1wy8zQCAAQAEAAgK1wy8zQCAAQAAAA==.',
Vo='Vodilent:BAAANQAECgUIBQAAAA==.Voidarella:BAAANQABCgMIAwABNQAECgoKOAAEAOQaAA==.',
['Vè']='Vèx:BAABNQAECn8xAAIYAAoKkR6YMwDyAgAYAAoKkR6YMwDyAgAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgcIFQAVAOoHAA==.Watlas:BAAANQAECgcIDgABNQAFFAQIBwAbAPoSAA==.',
Xa='Xavia:BAABNQAECn8aAAIVAAcKERJTpgCHAQAVAAcKERJTpgCHAQAAAA==.',
Yu='Yunaraa:BAAANQAECgIJAwABNQAECgkJKAAKAI4WAA==.',
Yv='Yvana:BAAANQADCgYIEQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMIBgABNQAFFAgIGwAgAOEhAA==.',
Zo='Zombies:BAABNQAECn8WAAIbAAgKMBf9SADzAQAbAAgKMBf9SADzAQAAAA==.',
Zu='Zugmaster:BAABNQAECn83AAIkAAoKkxoPBwAvAgAkAAoKkxoPBwAvAgAAAA==.Zugszy:BAAANQAECgMIAwAAAA==.',
Zy='Zynn:BAAANQAECgEJAQABNQABCgQIBAADAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFH8bAAIgAAgK4SHYAQDUAgAgAAgK4SHYAQDUAgA1AAQKfyAAAiAACgoDJqgSADMDACAACgoDJqgSADMDAAAA.Zzephyrmage:BAAANQAECgUICAABNQAFFAgIGwAgAOEhAA==.',
['Çä']='Çärvé:BAAANQADCgUIBQAAAA==.',
['Ôä']='Ôäk:BAAANQAECgQIBAABNQAECgYIGgASAD0RAA==.',
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
