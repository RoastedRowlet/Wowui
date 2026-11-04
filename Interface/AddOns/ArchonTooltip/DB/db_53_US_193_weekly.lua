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
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abelladanger:BAAANQAECgUIBwAAAA==.',
Ad='Addilyn:BAABNQAECn8jAAIBAAgKlBpdSwDRAQABAAgKlBpdSwDRAQAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAABNQAECn8jAAICAAgKOxDtNgA/AQACAAgKOxDtNgA/AQAAAA==.Ahroo:BAAANQAECggIHAABNQAFFAIIAgADAAAAAQ==.Ahrue:BAAANQAFFAIIAgAAAQ==.',
Ai='Aikanaro:BAAANQAECgUIDwAAAA==.Airc:BAABNQAECn8cAAIEAAgK5AnzuwAbAQAEAAgK5AnzuwAbAQAAAA==.Aiurman:BAAANQADCgcICQAAAA==.',
Aj='Ajanti:BAAANQAECgQIAwAAAA==.',
Al='Aleric:BAAANQAECgUIBwAAAA==.Alfster:BAAANQAECgQIBAABNQAECgUIEAADAAAAAA==.Allanor:BAAANQADCgEIAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAABNQAECn8iAAMBAAoKbxTycADKAQABAAgKUxXycADKAQAFAAYKkw7aPwAwAQAAAA==.',
Ar='Argeikeranos:BAABNQAECn86AAMGAAoKkR9gSgDtAgAGAAoKSh5gSgDtAgAHAAMKkSKeKACwAAAAAA==.',
As='Asystole:BAAANQADCgEIAQAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAFFAQIDQAIAE0WAA==.Atomicrednax:BAACNQAFFH8fAAMJAAkKsCBNAwBcAgAJAAgKwiBNAwBcAgAKAAEKRSAWLwBiAAA1AAQKf38AAwkACgpBJu4AAGgDAAkACgpBJu4AAGgDAAoAAQrwJKQIAWUAAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Ay='Ayisen:BAAANQADCgYICgAAAA==.',
Ba='Ballsmonk:BAAANQAECgYIBgAAAA==.Ballsofury:BAACNQAFFH8KAAILAAMKXSWVAAA6AQALAAMKXSWVAAA6AQA1AAQKfyMAAgsACgrvJiEAABIEAAsACgrvJiEAABIEAAAA.Ballspally:BAAANQAECggICQAAAA==.Baptism:BAAANQAECgUIBwAAAA==.Battousaiha:BAABNQAECn8mAAIEAAkKlRhyXwDaAQAEAAkKlRhyXwDaAQAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggICAABNQAFFAgIHQAMAI0jAA==.',
Bl='Blackcoffee:BAAANQAECgUIBwAAAA==.Blippi:BAAANQADCgQIBgABNQABCgQIBAADAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAQAAAA==.Bortikus:BAAANQADCgYIBwABNQAFFAEIAQADAAAAAA==.',
Bu='Burney:BAABNQAECn9AAAMNAAoKoB+ABAAdAwANAAoKoB+ABAAdAwAOAAgK/BqEEwAXAgAAAA==.Burnnotice:BAAANQADCgYICwAAAA==.Busadinn:BAABNQAECn8cAAIEAAkKAR2wdwA9AgAEAAkKAR2wdwA9AgAAAA==.',
['Bò']='Bònesaw:BAACNQAFFH8JAAIPAAMKEBvYAgDEAAAPAAMKEBvYAgDEAAA1AAQKfz4AAw8ACgpfI1MCAJQDAA8ACgpfI1MCAJQDABAAAgrcDLohAGMAAAAA.',
Ca='Calibrium:BAAANQAECgcIDQAAAA==.Carll:BAACNQAFFH8FAAIRAAIK2hIAGgCGAAARAAIK2hIAGgCGAAA1AAQKfzsAAhEACgquHbceAPYCABEACgquHbceAPYCAAAA.',
Ch='Chipmonk:BAAANQAECgIIAQAAAA==.Chister:BAABNQAECn8XAAISAAgKuwzMMQCMAQASAAgKuwzMMQCMAQAAAA==.Cholomonga:BAAANQAECgYIDAABNQAFFAcIGgAIAAMXAA==.Chotterboy:BAAANQABCgUIAwAAAA==.Churchill:BAAANQADCgUIBQABNQAFFAYIFQAEAFMcAA==.',
Cl='Clonk:BAAANQADCgUIBQAAAA==.',
Cr='Crazedx:BAABNQAECn8qAAMTAAoKxyMOAgDqAgATAAoKySIOAgDqAgAUAAQKqyDDJAA7AQABNQAFFAcIFgACAGccAA==.Cream:BAAANQAECgUIBQAAAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgQIBgAAAA==.',
Da='Daddy:BAACNQAFFH8FAAIVAAMKAAbJKQC4AAAVAAMKAAbJKQC4AAA1AAQKfzYAAxYACgpFIWcCADsDABYACgpMHWcCADsDABUACAqaFetaAEYCAAAA.Daito:BAAANQADCgQIBwAAAA==.Darig:BAAANQAECgIIAgAAAA==.Daryun:BAAANQAECgMIBwABNQAECgUIDwADAAAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimas:BAAANQAECgQIDQAAAA==.Decimez:BAABNQAECn8mAAIIAAgKRxs4VAApAgAIAAgKRxs4VAApAgAAAA==.Decimock:BAABNQAECn8hAAIWAAgK6h60BgCeAgAWAAgK6h60BgCeAgAAAA==.Demonslunt:BAAANQADCgcIBwABNQAFFAcIFwAXAPQaAA==.',
Di='Digerati:BAAANQADCggIDAAAAA==.Dingiswayo:BAABNQAECn8iAAIUAAkKqBVbHgA/AgAUAAkKqBVbHgA/AgAAAA==.Dingybing:BAAANQAECgUICgAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.Dizan:BAAANQAECgQIDAABNQAECgUIDwADAAAAAA==.',
Dp='Dpitis:BAABNQAECn81AAMFAAoKpR3HDwD5AgAFAAoKpR3HDwD5AgABAAUK2h0ogwCNAQABNQAFFAMIBQAYAJ0QAA==.',
Dr='Dragonflyy:BAAANQADCgQICQAAAA==.Draks:BAAANQAECgEIAgAAAA==.Drinkyds:BAABNQAECn8bAAIXAAkKLiGBJADUAgAXAAkKLiGBJADUAgAAAA==.',
Er='Eriebus:BAABNQAECn8dAAMZAAgKJRV6HwBwAQAZAAgKJRV6HwBwAQAaAAEK7QaylwAuAAAAAA==.Erona:BAABNQAECn8xAAIXAAoKjhuUFgDWAgAXAAoKjhuUFgDWAgAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ev='Evenstar:BAAANQAECgcIBwAAAA==.',
Ex='Extendo:BAABNQAECn8kAAIbAAkKrhtnEgA7AgAbAAkKrhtnEgA7AgAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAFFAMIBQAYAJ0QAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAABNQAECn8jAAIWAAoKyBEABQB4AQAWAAoKyBEABQB4AQAAAA==.Feech:BAAANQAECgQIBAABNQAFFAcIDQAEAAIXAA==.Felagain:BAAANQAECgQIBAAAAA==.Ferdinane:BAABNQAECn8iAAIMAAgKnxE4JwCkAQAMAAgKnxE4JwCkAQAAAA==.',
Fi='Fidgety:BAAANQADCggIEQAAAA==.',
Fl='Flankshot:BAACNQAFFH8IAAIHAAMK6gdwBAC0AAAHAAMK6gdwBAC0AAA1AAQKfzsAAgcACgrqHLIFALICAAcACgrqHLIFALICAAAA.',
Fo='Foops:BAACNQAFFH8QAAMHAAUKkBfVAACqAQAHAAUKkBfVAACqAQAGAAEKAADwZwA3AAA1AAQKfy8AAgcACgpTIjoDAKcCAAcACgpTIjoDAKcCAAAA.Foopsadin:BAAANQAECgMIBgABNQAFFAUIEAAHAJAXAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Fr='Freaky:BAAANQADCggICAAAAA==.',
Fu='Fumìn:BAABNQAECn8ZAAIcAAcK4RFlKAANAQAcAAcK4RFlKAANAQAAAA==.',
Ga='Gassommelier:BAAANQADCggICAAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAABNQAECn8jAAMRAAcK1xqONwAIAgARAAcK1xqONwAIAgAEAAUKCxJMNAHLAAAAAA==.Getrkt:BAABNQAECn8ZAAIEAAgKvwmCxgCPAQAEAAgKvwmCxgCPAQAAAA==.',
Gi='Gimblie:BAABNQAECn8rAAIBAAkKhiA1DwA5AwABAAkKhiA1DwA5AwAAAA==.Gimermonty:BAACNQAFFH8FAAIKAAMKhwiuEwDQAAAKAAMKhwiuEwDQAAA1AAQKfyQAAgoACQrwFKJTAOQBAAoACQrwFKJTAOQBAAAA.Gimixx:BAAANQAECggIEAAAAA==.',
Gl='Gladrielle:BAAANQAECgEIAQAAAA==.Glatzkaus:BAAANQAECgcICAAAAA==.Glockcena:BAAANQAECgQICAAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAQAAAA==.',
Gr='Greenline:BAAANQAECgUIDAABNQAECgcIIwARANcaAA==.Gripen:BAAANQABCggICwAAAA==.Gronk:BAAANQADCggICwAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQABCgQIBAAAAA==.',
Ha='Hakal:BAABNQAECn9AAAIcAAoK/iJKAwAnAwAcAAoK/iJKAwAnAwAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAABNQAECn8bAAMdAAkK4BCNGgAPAQAZAAgKsRDOOgBwAQAdAAYKsAuNGgAPAQAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAABNQAECn8fAAMeAAcKswlXYgAbAQAeAAcKswlXYgAbAQAbAAIKEgKi4wAwAAAAAA==.Hattshepsut:BAAANQADCgQIBgAAAA==.',
He='Healinghands:BAABNQAECn8cAAQfAAgKYx6WAgBWAgAfAAgKYx6WAgBWAgABAAQK0Qwc0wCtAAAFAAMK6gGbaABfAAAAAA==.Hellz:BAACNQAFFH8IAAIPAAQKwQxgAwCvAAAPAAQKwQxgAwCvAAA1AAQKf0EAAg8ACgrgGr8JAK0CAA8ACgrgGr8JAK0CAAAA.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAABNQAECn8jAAIdAAgKERxhCAC2AQAdAAgKERxhCAC2AQAAAA==.',
Ic='Iceandfire:BAAANQAECgMIBQAAAA==.',
Ig='Igneel:BAACNQAFFH8FAAIYAAMKnRD0FADbAAAYAAMKnRD0FADbAAA1AAQKfyUAAhgACQqAHQ4pAHkCABgACQqAHQ4pAHkCAAAA.',
In='Inviteme:BAAANQAECgMIAwAAAA==.',
Io='Ionisa:BAAANQADCggICAAAAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQADCggICAABNQAECgQIAwADAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAFFAMICQAPABAbAA==.',
Jh='Jhamin:BAACNQAFFH8NAAIIAAQKTRbSCwD0AAAIAAQKTRbSCwD0AAA1AAQKfzMAAwgACgrSH68dAFYCAAgACgrSH68dAFYCABcAAwroBjj3AHwAAAAA.',
Jo='Joss:BAAANQAECgUICwAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Jubeiskyfang:BAAANQAECggICAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Jy='Jynken:BAAANQAECgQIBAABNQAECgUIDwADAAAAAA==.',
Ka='Kaedrelyn:BAABNQAECn8WAAMgAAYK8QRHdgDxAAAgAAYK8QRHdgDxAAASAAIKIwY7bgAmAAAAAA==.Kageyuki:BAEANQAECgEIAQABNQAFFAEIBgAeAAAAAA==.',
Ke='Kennyman:BAAANQADCgQIBAAAAA==.Ketheric:BAAANQADCgMIAwAAAA==.',
Ki='Kindinos:BAAANQADCggIHgAAAA==.',
Kl='Klickyy:BAAANQAFFAEIAQABNQAFFAcIDQAEAAIXAA==.Kllcky:BAACNQAFFH8NAAIEAAcKAhfKBAAVAgAEAAcKAhfKBAAVAgA1AAQKf0EAAwQACgr+JhQDAOUDAAQACgr+JhQDAOUDABEAAQrMCKggATUAAAAA.',
Kr='Kraun:BAABNQAECn8tAAIKAAgKoSQoMQDZAgAKAAgKoSQoMQDZAgAAAA==.Kroo:BAABNQAECn8sAAIUAAoKbBJMIgAXAgAUAAoKbBJMIgAXAgAAAA==.',
Ku='Kurnon:BAAANQAECgQICAABNQAECgUIBgADAAAAAA==.',
Kv='Kvothè:BAAANQADCgcIBwABNQAECgUICwADAAAAAA==.',
Ky='Kyi:BAACNQAFFH8JAAIUAAMKVRXkBwDVAAAUAAMKVRXkBwDVAAA1AAQKfzsAAhQACgrUG4UMAGwCABQACgrUG4UMAGwCAAAA.',
La='Lammlock:BAAANQAECgcIDgAAAA==.Landar:BAABNQAECn86AAISAAoKXRWGHABQAgASAAoKXRWGHABQAgAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECn8gAAIhAAkKHhMtBQB1AgAhAAkKHhMtBQB1AgAAAA==.',
Lo='Lockonyou:BAABNQAECn8VAAIVAAcK6gcWwgBHAQAVAAcK6gcWwgBHAQAAAA==.Losthack:BAABNQAECn8qAAMRAAoKsSITBgCgAwARAAoKsSITBgCgAwAEAAUKVgnUGAGNAAAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgcIEQAAAA==.',
Ma='Mahra:BAAANQAECgYIEQAAAA==.Manchasone:BAABNQAECn8fAAIEAAoKPh/wOwDjAgAEAAoKPh/wOwDjAgAAAA==.Mangreese:BAABNQAECn8lAAMiAAoK1w6sDQAFAgAiAAoK1w6sDQAFAgAIAAEKxwMF8wAgAAAAAA==.',
Me='Meekseek:BAAANQAECgcICgAAAA==.',
Mi='Miahealifa:BAABNQAECn8aAAMBAAgKhRQ1cwDCAQABAAgKhRQ1cwDCAQAFAAEKtgPvWwAmAAAAAA==.Miasma:BAAANQAECgUIDQAAAA==.Micaiah:BAAANQAECgQIBQAAAA==.Milkmë:BAAANQADCgYICgAAAA==.Mistabubbles:BAAANQAECgcIDwAAAA==.Mistyjp:BAAANQAECgMIBAABNQAFFAcIGgAIAAMXAA==.',
Mk='Mk:BAAANQAECgcIDQAAAA==.',
Mo='Mochi:BAAANQAECgMIAwAAAA==.Mograinez:BAACNQAFFH8fAAMbAAkKgSUlAADvAgAbAAkKgSUlAADvAgACAAEKAADjNQAnAAA1AAQKfyEAAhsACgr3JgMOAEkDABsACgr3JgMOAEkDAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.',
Ne='Necrussy:BAAANQADCgIIAgAAAA==.Nekrohealia:BAAANQAECgcIDwAAAA==.Neteyam:BAAANQAECggIDQAAAA==.',
No='Nogitsune:BAAANQAECgQIBAAAAA==.Norolock:BAABNQAECn8eAAIVAAgKJxYxWACSAQAVAAgKJxYxWACSAQAAAA==.',
Nu='Nuovis:BAAANQADCgYIBgAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgQICgABNQAFFAcIDQAEAAIXAA==.',
Og='Oghlin:BAABNQAECn8lAAIUAAoKfh5KFwCRAgAUAAoKfh5KFwCRAgAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBAAAAA==.',
Ol='Oldshotz:BAABNQAECn8gAAIKAAcK/BAhvACLAQAKAAcK/BAhvACLAQAAAA==.',
Om='Omgsteak:BAABNQAECn8hAAMPAAgKlAGQJwCNAAAPAAgKlAGQJwCNAAAYAAEKAAD8bQEUAAAAAA==.',
On='Onlybusa:BAAANQAECgQIBwAAAA==.',
Or='Orcofwar:BAAANQADCgYIBgAAAA==.',
Pa='Palidan:BAAANQAECgcIEAAAAA==.Panzerwolf:BAECNQAFFH8VAAIPAAcKyiMYAADqAgAPAAcKyiMYAADqAgA1AAQKf2QABA8ACgp1JlUAAIkDAA8ACgp1JlUAAIkDABAACQooH4IDAB0DABgACQodHuFJAPIBAAAA.Parsnip:BAAANQAECgQICgAAAA==.',
Pr='Pray:BAABNQAECn8aAAIaAAoKHQ6gIgC6AQAaAAoKHQ6gIgC6AQAAAA==.Prayforme:BAABNQAECn9GAAMfAAoK8SSZAQAxAwABAAoKrh48CgB1AwAfAAgKMCOZAQAxAwAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECn8uAAMXAAoKpQ/haADSAQAXAAoKpQ/haADSAQAIAAIKtAQi6QAuAAAAAA==.Psychopompos:BAAANQADCggICAABNQAECgoKOgAGAJEfAA==.',
Qr='Qreigns:BAAANQAECgYICgAAAA==.',
Qw='Qweh:BAAANQAECgUIDgAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAACNQAFFH8KAAMjAAUKMA3GBgDIAAAjAAUKMA3GBgDIAAAOAAEKJQjvBwA5AAA1AAQKfykAAw4ACgolF1kQAFICAA4ACQqkElkQAFICACMABwo1GL4KAL8BAAAA.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECn8oAAIkAAcKZx4DJwBWAgAkAAcKZx4DJwBWAgAAAA==.Razkal:BAABNQAECn8iAAIKAAoK/hWvUgDmAQAKAAoK/hWvUgDmAQAAAA==.Razpal:BAAANQAECgUIBQAAAA==.',
Re='Revirginator:BAAANQAECgQIBwAAAA==.',
Ri='Rimreaper:BAAANQAECgUICwAAAA==.',
Rn='Rngesus:BAACNQAFFH8GAAIVAAQKXQYYKADGAAAVAAQKXQYYKADGAAA1AAQKf0MAAxUACgpjIAcXAKICABUACgqaHwcXAKICACUAAgorEVEfAH4AAAE1AAUUBAgNAAgATRYA.',
Ru='Ruffle:BAAANQAECgUIBQABNQAECgoKIQAIAIgTAA==.Runie:BAEANQADCgQIBAABNQAFFAcIGwAYAGUWAA==.Rushem:BAABNQAECn8XAAIYAAgKVhB6kwAjAQAYAAgKVhB6kwAjAQAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAACNQAFFH8FAAIVAAMKGxdEEQDvAAAVAAMKGxdEEQDvAAA1AAQKfy4AAxUACgoJHoAhAP4CABUACgoJHoAhAP4CABYAAQr+GCYuAD4AAAAA.Ràyà:BAAANQADCgQIBAAAAA==.',
Sa='Saenen:BAABNQAECn8fAAILAAgKMw5DFwCFAQALAAgKMw5DFwCFAQAAAA==.',
Sc='Scorchi:BAAANQAECgQJBwAAAA==.',
Se='Seseria:BAACNQAFFH8FAAIRAAIKVwjaIgCBAAARAAIKVwjaIgCBAAA1AAQKfzUAAhEACgqCHOciAHsCABEACgqCHOciAHsCAAAA.Sevinofnine:BAAANQAECgQICwAAAA==.',
Sh='Shadowsong:BAAANQAECgcICgAAAA==.Shaithis:BAAANQADCgQIBgAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwADAAAAAA==.Shanic:BAABNQAECn8iAAIgAAgK0hK+KgBxAQAgAAgK0hK+KgBxAQAAAA==.Shavedcat:BAAANQADCgMIAwAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shinokami:BAAANQAECggIAQAAAA==.Shocktart:BAAANQAECgMIBAAAAA==.',
Si='Siheal:BAAANQAECgUICQAAAA==.',
Sl='Sleeping:BAAANQAECgEIAQAAAA==.Sliceanddice:BAAANQAECgQICwAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAcIGgAIAAMXAA==.Snipyterror:BAACNQAFFH8aAAMIAAcKAxcqCgDJAQAIAAUKJBkqCgDJAQAXAAMKDBCWFwDmAAA1AAQKfykAAwgACgo/I5YNAHwDAAgACQpDI5YNAHwDABcAAwqyBskFAV0AAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.',
Sp='Spacejam:BAAANQADCgcIJQAAAA==.Specimenb:BAAANQAECggIEQAAAA==.Spirallidan:BAABNQAECn8qAAMaAAoKNheFIgCHAgAaAAoKNheFIgCHAgAZAAQKZwrAVQC5AAAAAA==.',
St='Staticprot:BAAANQAECgIIAgABNQAECgoKKAAKAKIRAA==.Staticsrexar:BAABNQAECn8oAAQKAAoKohEwWQDTAQAKAAoKohEwWQDTAQAhAAEKJQa0EgA9AAAJAAEKAABEmQAnAAAAAA==.Stayk:BAAANQADCggIDQAAAA==.Stepbro:BAAANQAECgIIAgABNQAECgMIAwADAAAAAA==.Stinksauce:BAABNQAECn8hAAQNAAkKNxdoEgCGAgANAAkKNxdoEgCGAgAjAAUK8xv5CwCbAQAOAAQKyA5zJwD3AAAAAA==.Strokntotem:BAAANQAECgUIEwAAAA==.',
Su='Superchunk:BAAANQAECgMIBgAAAA==.Sutra:BAABNQAECn8ZAAIBAAkKChFwawDcAQABAAkKChFwawDcAQAAAA==.',
Sy='Sylmarillion:BAAANQAECgUIBgAAAA==.',
Ta='Talgulen:BAABNQAECn85AAIOAAoKqBhoBgAUAgAOAAoKqBhoBgAUAgAAAA==.Tarquinius:BAAANQAECgUJDwAAAA==.Taxii:BAAANQAECgYIEwABNQAECgoKNAAYAOklAA==.Taynte:BAAANQAECgcIDQAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAABNQAECn8YAAIVAAcK4QnfqwB7AQAVAAcK4QnfqwB7AQABNQAFFAMICQAUAFUVAA==.Theoshun:BAAANQAECgcIDAAAAA==.Thrag:BAAANQAECgIIAgABNQAECgUIDwADAAAAAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.',
To='Tone:BAAANQAECggICgAAAA==.Torokai:BAAANQAECggICgAAAA==.Torokami:BAAANQAECggIAgAAAA==.Torokuma:BAAANQAECggIBQAAAA==.Toroshinu:BAAANQAECggIAQAAAA==.Torotatsu:BAAANQAECgIIAgAAAA==.Totemlycool:BAAANQAECgUIBwABNQAECgoKLAAUAGwSAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAABNQAECn80AAMKAAoKsxQYRACfAgAKAAoKsxQYRACfAgAhAAEKAABFEwAAAAAAAA==.Treehuggër:BAABNQAECn8gAAMSAAgKTBMHLwCiAQASAAgKTBMHLwCiAQAgAAMKDwb0pQBNAAAAAA==.Trelia:BAAANQADCgQIBAAAAA==.Trogkin:BAABNQAECn8fAAIgAAoKPxcrLQBzAgAgAAoKPxcrLQBzAgABNQAFFAkJGwAJAPYVAA==.',
Tw='Twîsty:BAAANQADCgQIBgAAAA==.',
Ty='Tyrith:BAABNQAECn8qAAIYAAoKyCD/KQATAwAYAAoKyCD/KQATAwAAAA==.',
Ug='Ugotgotpal:BAABNQAECn8XAAIEAAgKDAhU0gB3AQAEAAgKDAhU0gB3AQAAAA==.',
Ul='Ulazain:BAABNQAECn87AAIQAAoKKxnJBgCXAgAQAAoKKxnJBgCXAgAAAA==.',
Um='Umadcuzbad:BAAANQADCgcICQAAAA==.',
Us='Usdaprime:BAABNQAECn8UAAILAAkKMQl6GwBLAQALAAkKMQl6GwBLAQAAAA==.',
Va='Vaas:BAAANQAECgYICwAAAA==.Vaporeön:BAAANQAECgcIDQAAAA==.Varrasha:BAAANQABCgIIAgAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAABNQAECn8fAAIEAAgK1wy8zQCAAQAEAAgK1wy8zQCAAQAAAA==.',
Vo='Vodilent:BAAANQAECgUIBQAAAA==.Voidarella:BAAANQABCgMIAwABNQAECgoKQQAEAHgdAA==.',
['Vè']='Vèx:BAABNQAECn8xAAIYAAoKkR6YMwDyAgAYAAoKkR6YMwDyAgAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgcIFQAVAOoHAA==.Watlas:BAAANQAECgcIDgABNQAFFAUICAAbAPoSAA==.',
Xa='Xavia:BAABNQAECn8aAAIVAAcKERJTpgCHAQAVAAcKERJTpgCHAQAAAA==.',
Yu='Yunaraa:BAAANQAECgIIAwABNQAECgoKNAAKALMUAA==.',
Yv='Yvana:BAAANQADCgYIEQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMIBgABNQAFFAkJHQAgAL0hAA==.',
Zo='Zombies:BAABNQAECn8WAAIbAAgKMBf9SADzAQAbAAgKMBf9SADzAQAAAA==.',
Zu='Zugmaster:BAABNQAECn87AAIkAAoKWxtCCQAjAgAkAAoKWxtCCQAjAgAAAA==.Zugszy:BAAANQAECgMIAwAAAA==.',
Zy='Zynn:BAAANQAECgEJAQABNQABCgQIBAADAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFH8dAAIgAAkKvSHYAQDUAgAgAAkKvSHYAQDUAgA1AAQKfyEAAiAACgoDJqgSADMDACAACgoDJqgSADMDAAAA.Zzephyrmage:BAAANQAECgQICAABNQAFFAkJHQAgAL0hAA==.',
['Çä']='Çärvé:BAAANQADCgUIBQAAAA==.',
['Ôä']='Ôäk:BAAANQAECgQICAABNQAECgcIHgASAD0RAA==.',
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
