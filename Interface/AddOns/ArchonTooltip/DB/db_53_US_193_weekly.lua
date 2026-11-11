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

local lookup = {'Priest-Holy','DeathKnight-Blood','Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Mage-Arcane','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Warrior-Fury','Paladin-Holy','Druid-Restoration','Monk-Brewmaster','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Druid-Balance','Hunter-Survival','Shaman-Enhancement','Evoker-Augmentation','Rogue-Assassination','Warlock-Affliction','Rogue-Subtlety',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abelladanger:BAAANQAECgYIBwAAAA==.',
Ad='Addilyn:BAABNQAECn8lAAIBAAkKTBugPgAqAgABAAkKTBugPgAqAgAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAABNQAECn8lAAICAAkKsxA3MgB0AQACAAkKsxA3MgB0AQAAAA==.Ahroo:BAAANQAECggIIwABNQAFFAIIAgADAAAAAQ==.Ahrue:BAAANQAFFAIIAgAAAQ==.',
Ai='Aikanaro:BAAANQAECgUIEAAAAA==.Airc:BAABNQAECn8cAAIEAAgK5AnQywApAQAEAAgK5AnQywApAQAAAA==.Aiurman:BAAANQADCgcICQAAAA==.',
Aj='Ajanti:BAAANQAECgQIBgAAAA==.',
Al='Aleric:BAAANQAECgUIBwAAAA==.Alfster:BAAANQAECgQIBQABNQAECgUIEAADAAAAAA==.Allanor:BAAANQADCgEIAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAABNQAECn8iAAMBAAoKbxTycADKAQABAAgKUxXycADKAQAFAAYKkw7aPwAwAQAAAA==.',
Ar='Argeikeranos:BAABNQAECn87AAMGAAoKkR9gSgDtAgAGAAoKSh5gSgDtAgAHAAMKkSKeKACwAAAAAA==.',
As='Asystole:BAAANQADCgEIAQAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAFFAQIDQAIAE0WAA==.Atomicrednax:BAACNQAFFH8mAAMJAAkKAyFhAgA6AgAJAAgKwiBhAgA6AgAKAAEKhiJhJgBoAAA1AAQKf38AAwkACgpBJlgBAGIDAAkACgpBJlgBAGIDAAoAAQrwJPEcAWIAAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Ay='Ayisen:BAAANQADCgYICgAAAA==.',
Ba='Baileyboy:BAAANQAECgQIBAAAAA==.Ballsmonk:BAAANQAECgYIBwAAAA==.Ballsofury:BAACNQAFFH8KAAILAAMKXSXHAAA2AQALAAMKXSXHAAA2AQA1AAQKfyMAAgsACgrvJiEAABIEAAsACgrvJiEAABIEAAAA.Ballspally:BAAANQAECggICgAAAA==.Baptism:BAAANQAECgYIDQAAAA==.Battousaiha:BAABNQAECn8pAAIEAAoKERhQVgAaAgAEAAoKERhQVgAaAgAAAA==.Bayboy:BAAANQADCgEIAQAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggICAABNQAFFAgIHQAMAI0jAA==.',
Bl='Blackcoffee:BAAANQAECgUIBwAAAA==.Blippi:BAAANQADCgQIBgABNQABCgQIBAADAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAQAAAA==.Bortikus:BAAANQADCgYIBwABNQAFFAEIAgADAAAAAA==.',
Bu='Burney:BAABNQAECn9HAAMNAAoKoB8+BQAaAwANAAoKoB8+BQAaAwAOAAgK/BqEEwAXAgAAAA==.Burnnotice:BAAANQADCgYICwAAAA==.Busadinn:BAABNQAECn8jAAIEAAkKTR4nYQD/AQAEAAkKTR4nYQD/AQAAAA==.',
['Bò']='Bònesaw:BAACNQAFFH8JAAIPAAMKEBt0AwC/AAAPAAMKEBt0AwC/AAA1AAQKf0IAAw8ACgpfI1MCAJQDAA8ACgpfI1MCAJQDABAAAgrcDKEmAGIAAAAA.',
Ca='Calibrium:BAAANQAECgcIDQAAAA==.Carll:BAACNQAFFH8GAAIRAAMKNw5zFgDKAAARAAMKNw5zFgDKAAA1AAQKfzsAAhEACgquHbceAPYCABEACgquHbceAPYCAAAA.',
Ch='Chipmonk:BAAANQAECgIIAwAAAA==.Chister:BAABNQAECn8XAAISAAgKuwzMMQCMAQASAAgKuwzMMQCMAQAAAA==.Cholomonga:BAAANQAECgYIDQABNQAFFAcIGgAIAAMXAA==.Chotterboy:BAAANQABCgUIAwAAAA==.Churchill:BAAANQADCgUIBQABNQAFFAYIFQAEAFMcAA==.',
Cl='Clonk:BAAANQADCgUIBQAAAA==.',
Co='Colisto:BAAANQAECgEIAQAAAA==.',
Cr='Crazedx:BAABNQAECn8sAAMTAAoKxyNnAgDmAgATAAoKySJnAgDmAgAUAAQKqyD5KAA5AQABNQAFFAgIFwACAMIcAA==.Cream:BAAANQAECgUIBgAAAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgQIBgAAAA==.',
Da='Daddy:BAACNQAFFH8FAAIVAAMKAAbJKQC4AAAVAAMKAAbJKQC4AAA1AAQKfzgAAxYACgrAIWcCADsDABYACgrHHWcCADsDABUACAqaFetaAEYCAAAA.Daito:BAAANQADCgQIBwAAAA==.Dameter:BAAANQABCgEIAQAAAA==.Darig:BAAANQAECgQIBgAAAA==.Daryun:BAAANQAECgMICgABNQAECgUIEAADAAAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimas:BAAANQAECgUIEAAAAA==.Decimez:BAABNQAECn8pAAIIAAkKQBtXNgDnAQAIAAkKQBtXNgDnAQAAAA==.Decimock:BAABNQAECn8mAAIWAAoKXx20BgCeAgAWAAoKXx20BgCeAgAAAA==.Demonslunt:BAAANQADCgcIBwABNQAFFAcIFwAXAPQaAA==.',
Di='Digerati:BAAANQADCggIDAAAAA==.Dingiswayo:BAABNQAECn8iAAIUAAkKqBVbHgA/AgAUAAkKqBVbHgA/AgAAAA==.Dingybing:BAAANQAECgUICgAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.Dizan:BAAANQAECgQIDQABNQAECgUIEAADAAAAAA==.',
Dp='Dpitis:BAABNQAECn81AAMFAAoKpR3HDwD5AgAFAAoKpR3HDwD5AgABAAUK2h0ogwCNAQABNQAFFAMIBQAYAJ0QAA==.',
Dr='Dragonflyy:BAAANQADCgQICQAAAA==.Draks:BAAANQAECgEIAgAAAA==.Drinkyds:BAABNQAECn8bAAIXAAkKLiGBJADUAgAXAAkKLiGBJADUAgAAAA==.',
Er='Eriebus:BAABNQAECn8eAAMZAAgKJRWpIwBqAQAZAAgKJRWpIwBqAQAaAAEK7QaylwAuAAAAAA==.Erona:BAABNQAECn8xAAIXAAoKjhuKGwDHAgAXAAoKjhuKGwDHAgAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ev='Evenstar:BAAANQAECgcIBwAAAA==.',
Ex='Extendo:BAABNQAECn8kAAIbAAkKrhu2FQAxAgAbAAkKrhu2FQAxAgAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAFFAMIBQAYAJ0QAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAABNQAECn8oAAIWAAoKaxJ3BQCGAQAWAAoKaxJ3BQCGAQAAAA==.Feech:BAAANQAECgQIBQABNQAFFAcIDQAEAAIXAA==.Felagain:BAAANQAECgQIBAAAAA==.Ferdinane:BAABNQAECn8oAAIMAAoK5BAkGgCLAQAMAAoK5BAkGgCLAQAAAA==.',
Fi='Fidgety:BAAANQADCggIEQAAAA==.',
Fl='Flankshot:BAACNQAFFH8IAAIHAAMK6gdWBQCxAAAHAAMK6gdWBQCxAAA1AAQKfz8AAgcACgrUHbIFALICAAcACgrUHbIFALICAAAA.',
Fo='Foops:BAACNQAFFH8UAAMHAAYKkBfVAACqAQAHAAYKkBfVAACqAQAGAAEKAADwZwA3AAA1AAQKfzAAAgcACgpTIjcEAJwCAAcACgpTIjcEAJwCAAAA.Foopsadin:BAAANQAECgMIBgABNQAFFAYIFAAHAJAXAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Fr='Freaky:BAAANQADCggICAAAAA==.',
Fu='Fumin:BAAANQAECgEIAgAAAA==.Fumìn:BAABNQAECn8fAAIcAAgKKRSgHQCAAQAcAAgKKRSgHQCAAQAAAA==.',
Ga='Gassommelier:BAAANQADCggICAAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAABNQAECn8pAAMRAAkKqhuXHgC3AgARAAkKqhuXHgC3AgAEAAUKlBJMNAHLAAAAAA==.Getrkt:BAABNQAECn8ZAAIEAAgKvwmCxgCPAQAEAAgKvwmCxgCPAQAAAA==.',
Gi='Gimblie:BAABNQAECn8wAAIBAAkKhiBeEwAtAwABAAkKhiBeEwAtAwAAAA==.Gimermonty:BAACNQAFFH8FAAIKAAMKhwiyFgDMAAAKAAMKhwiyFgDMAAA1AAQKfygAAgoACQpKFTtgAO4BAAoACQpKFTtgAO4BAAAA.Gimixx:BAAANQAECggIEAAAAA==.',
Gl='Gladrielle:BAAANQAECgEIAgAAAA==.Glatzkaus:BAAANQAECgcICAAAAA==.Glockcena:BAAANQAECgYIDgAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAQAAAA==.',
Gr='Greenline:BAABNQAECn8YAAIKAAcKfiJmYQDrAQAKAAcKfiJmYQDrAQABNQAECgkJKQARAKobAA==.Gripen:BAAANQABCggICwAAAA==.Gronk:BAAANQADCggICwAAAA==.Grukk:BAAANQAECggIAQAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQABCgQIBAAAAA==.',
Ha='Hakal:BAABNQAECn9IAAIcAAoKhyNMAwA2AwAcAAoKhyNMAwA2AwAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAABNQAECn8bAAMdAAkK4BCNGgAPAQAZAAgKsRDOOgBwAQAdAAYKsAuNGgAPAQAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAABNQAECn8fAAMeAAcKswlXYgAbAQAeAAcKswlXYgAbAQAbAAIKEgKi4wAwAAAAAA==.Hattshepsut:BAAANQADCgQIBgAAAA==.',
He='Healinghands:BAABNQAECn8lAAQfAAoKfB9eAQAMAwAfAAkKTCFeAQAMAwABAAUKSw0c0wCtAAAFAAMK6gGbaABfAAAAAA==.Hellz:BAACNQAFFH8IAAIPAAQKwQwHBACqAAAPAAQKwQwHBACqAAA1AAQKf0EAAg8ACgrgGr8JAK0CAA8ACgrgGr8JAK0CAAAA.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAABNQAECn8lAAIdAAkK1xrrBwDrAQAdAAkK1xrrBwDrAQAAAA==.',
Ic='Iceandfire:BAAANQAECgMICAAAAA==.',
Ig='Igneel:BAACNQAFFH8FAAIYAAMKnRDsGADVAAAYAAMKnRDsGADVAAA1AAQKfykAAhgACQqSHjcnAJgCABgACQqSHjcnAJgCAAAA.',
In='Inviteme:BAAANQAECgMIBAAAAA==.',
Io='Ionisa:BAAANQADCggICAAAAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQADCggICAABNQAECgQIBgADAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAFFAMICQAPABAbAA==.',
Jh='Jhamin:BAACNQAFFH8NAAIIAAQKTRYiDgDtAAAIAAQKTRYiDgDtAAA1AAQKfzMAAwgACgrSHxojAE4CAAgACgrSHxojAE4CABcAAwroBjj3AHwAAAAA.',
Jo='Joss:BAAANQAECgUIEAAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Jubeiskyfang:BAAANQAECggICAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Jy='Jynken:BAAANQAECgQIBAABNQAECgUIEAADAAAAAA==.',
Ka='Kaedrelyn:BAABNQAECn8XAAMgAAcKfgW3VgCzAAAgAAcKfgW3VgCzAAASAAIKIwb6dwAmAAAAAA==.Kageyuki:BAEANQAECgEIAQABNQAFFAEIBgAeAAAAAA==.',
Ke='Kennyman:BAAANQADCgQIBAAAAA==.Ketheric:BAAANQADCgMIAwAAAA==.',
Ki='Kindinos:BAAANQADCggIHgAAAA==.',
Kl='Klickyy:BAAANQAECgYIDwABNQAFFAcIDQAEAAIXAA==.Kllcky:BAACNQAFFH8NAAIEAAcKAhfKBAAVAgAEAAcKAhfKBAAVAgA1AAQKf0EAAwQACgr+JhQDAOUDAAQACgr+JhQDAOUDABEAAQrMCKggATUAAAAA.',
Kr='Kraun:BAABNQAECn8vAAIKAAkK0yIoMQDZAgAKAAkK0yIoMQDZAgAAAA==.Kroo:BAABNQAECn8sAAIUAAoKbBJMIgAXAgAUAAoKbBJMIgAXAgAAAA==.',
Ku='Kurnon:BAAANQAECgQICAABNQAECgUIBgADAAAAAA==.',
Kv='Kvothè:BAAANQADCgcIBwABNQAECgUIDgADAAAAAA==.',
Ky='Kyi:BAACNQAFFH8JAAIUAAMKVRUvCQDUAAAUAAMKVRUvCQDUAAA1AAQKfz8AAhQACgpgHNwMAIACABQACgpgHNwMAIACAAAA.',
La='Lammlock:BAAANQAECgcIEQAAAA==.Landar:BAABNQAECn8+AAISAAoKKxaGHABQAgASAAoKKxaGHABQAgAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECn8gAAIhAAkKHhMtBQB1AgAhAAkKHhMtBQB1AgAAAA==.',
Lo='Lockonyou:BAABNQAECn8VAAIVAAcK6gcWwgBHAQAVAAcK6gcWwgBHAQAAAA==.Losthack:BAABNQAECn8vAAMRAAoKCCM8BwCfAwARAAoKCCM8BwCfAwAEAAUKVglFNAGLAAAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgcIEQAAAA==.',
Ma='Mahra:BAAANQAECgYIEQAAAA==.Manchasone:BAABNQAECn8fAAIEAAoKPh/wOwDjAgAEAAoKPh/wOwDjAgAAAA==.Mangreese:BAABNQAECn8pAAMiAAoKuhPzDAA0AgAiAAoKuhPzDAA0AgAIAAEKxwM9BQEgAAAAAA==.Masheen:BAAANQAECgEIAgAAAA==.',
Me='Meekseek:BAAANQAECgcICgAAAA==.',
Mi='Miahealifa:BAABNQAECn8aAAMBAAgKhRQ1cwDCAQABAAgKhRQ1cwDCAQAFAAEKtgO2ZAAmAAAAAA==.Miasma:BAAANQAECgUIDQAAAA==.Micaiah:BAAANQAECgQIBgAAAA==.Milkmë:BAAANQAECgYIBwAAAA==.Mistabubbles:BAAANQAECgcIDwAAAA==.Mistyjp:BAAANQAECgMIBAABNQAFFAcIGgAIAAMXAA==.',
Mk='Mk:BAAANQAECgcIDQAAAA==.',
Mo='Mochi:BAAANQAECgMIAwAAAA==.Mogarian:BAAANQAECgMIAwAAAA==.Mograinez:BAACNQAFFH8oAAMbAAkKEyYVAAAnAwAbAAkKEyYVAAAnAwACAAEKAADjNQAnAAA1AAQKfyEAAhsACgr3JgMOAEkDABsACgr3JgMOAEkDAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.Moráthi:BAAANQAECgEIAQAAAA==.',
Ne='Necrussy:BAAANQADCgIIAgAAAA==.Nekrohealia:BAAANQAECgcIDwAAAA==.Neteyam:BAAANQAECggIDQAAAA==.',
No='Nogitsune:BAAANQAECgQIBAAAAA==.Norolock:BAABNQAECn8fAAIVAAkKmxVlUADQAQAVAAkKmxVlUADQAQAAAA==.',
Nu='Nuovis:BAAANQAECgEIAQAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgQICgABNQAFFAcIDQAEAAIXAA==.',
Og='Oghlin:BAABNQAECn8tAAIUAAoKaB9JEABEAgAUAAoKaB9JEABEAgAAAA==.Oghorn:BAAANQAECgQIBAAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBAAAAA==.',
Ol='Oldshotz:BAABNQAECn8gAAIKAAcK/BAhvACLAQAKAAcK/BAhvACLAQAAAA==.',
Om='Omgsteak:BAABNQAECn8oAAMPAAkKNwLIKACiAAAPAAkKNwLIKACiAAAYAAEKAAD8bQEUAAAAAA==.',
On='Onlybusa:BAAANQAECgQICAAAAA==.',
Or='Orcofwar:BAAANQADCgYIBgAAAA==.',
Pa='Palidan:BAABNQAECn8XAAIYAAoKXw3gjgD3AQAYAAoKXw3gjgD3AQAAAA==.Panzerwolf:BAECNQAFFH8VAAIPAAcKyiMYAADqAgAPAAcKyiMYAADqAgA1AAQKf24ABA8ACgp1JnkAAIQDAA8ACgp1JnkAAIQDABAACQooH4IDAB0DABgACgrVHPAuAHUCAAAA.Parsnip:BAAANQAECgQICgAAAA==.',
Po='Poole:BAAANQAECgEIAgAAAA==.',
Pr='Pray:BAABNQAECn8aAAIaAAoKHQ5WJwC8AQAaAAoKHQ5WJwC8AQAAAA==.Prayforme:BAABNQAECn9GAAMfAAoK8SSZAQAxAwABAAoKrh4+DQBnAwAfAAgKMCOZAQAxAwAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECn8uAAMXAAoKpQ/haADSAQAXAAoKpQ/haADSAQAIAAIKtAS9+gAuAAAAAA==.Psychopompos:BAAANQADCggICAABNQAECgoKOwAGAJEfAA==.',
Qr='Qreigns:BAAANQAECgYIDAAAAA==.',
Qw='Qweh:BAAANQAECgUIEQAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAACNQAFFH8KAAMjAAUKMA1NCAC8AAAjAAUKMA1NCAC8AAAOAAEKJQjPCAA1AAA1AAQKfykAAw4ACgolF1kQAFICAA4ACQqkElkQAFICACMABwo1GL4KAL8BAAAA.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECn8oAAIkAAcKZx4DJwBWAgAkAAcKZx4DJwBWAgAAAA==.Razkal:BAABNQAECn8iAAIKAAoK/hWOYADtAQAKAAoK/hWOYADtAQAAAA==.Razpal:BAAANQAECgUIBgAAAA==.Razza:BAAANQAECgEIAQABNQAECgoKIgAKAP4VAA==.',
Re='Revirginator:BAAANQAECgQIBwAAAA==.',
Ri='Rimreaper:BAAANQAECgUICwAAAA==.',
Rn='Rngesus:BAACNQAFFH8KAAIVAAQKjxAiFgDkAAAVAAQKjxAiFgDkAAA1AAQKf0QAAxUACgpjIMscAJcCABUACgqaH8scAJcCACUAAgorEVEfAH4AAAE1AAUUBAgNAAgATRYA.',
Ru='Ruffle:BAAANQAECgUIBgABNQAECgoKIgAIAIgTAA==.Runie:BAEANQADCgQIBAABNQAFFAgIHQAYABYUAA==.Rushem:BAABNQAECn8ZAAIYAAkKsBDhhgBhAQAYAAkKsBDhhgBhAQAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAACNQAFFH8FAAIVAAMKGxdnFQDoAAAVAAMKGxdnFQDoAAA1AAQKfzAAAxUACgooHoAhAP4CABUACgooHoAhAP4CABYAAQr+GPYxAD4AAAAA.Ràyà:BAAANQADCgQIBAABNQAECgMIAwADAAAAAA==.',
Sa='Saenen:BAABNQAECn8fAAILAAgKMw5DFwCFAQALAAgKMw5DFwCFAQAAAA==.',
Sc='Scorchi:BAAANQAECgQJBwAAAA==.',
Se='Seseria:BAACNQAFFH8FAAIRAAIKVwjaIgCBAAARAAIKVwjaIgCBAAA1AAQKfzkAAhEACgqCHBsqAHACABEACgqCHBsqAHACAAAA.Sevinofnine:BAAANQAECgQICwAAAA==.',
Sh='Shadowsong:BAAANQAECgcICgAAAA==.Shaithis:BAAANQADCgQIBgAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwADAAAAAA==.Shanic:BAABNQAECn8kAAIgAAkKexHYKQCbAQAgAAkKexHYKQCbAQAAAA==.Shavedcat:BAAANQADCgMIAwAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shinokami:BAAANQAECggIAQAAAA==.Shocktart:BAAANQAECgMIBwAAAA==.',
Si='Siheal:BAAANQAECgUIEAAAAA==.',
Sl='Sleeping:BAAANQAECgEIAQAAAA==.Sliceanddice:BAAANQAECgQICwAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAcIGgAIAAMXAA==.Snipyterror:BAACNQAFFH8aAAMIAAcKAxcqCgDJAQAIAAUKJBkqCgDJAQAXAAMKDBCWFwDmAAA1AAQKfykAAwgACgo/I5YNAHwDAAgACQpDI5YNAHwDABcAAwqyBskFAV0AAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.',
Sp='Spacejam:BAAANQADCgcIJQAAAA==.Specimenb:BAABNQAECn8XAAMSAAkK0wtWOgASAQASAAgKbAtWOgASAQAgAAMKLQUboABeAAAAAA==.Spirallidan:BAABNQAECn8uAAMaAAoKNheFIgCHAgAaAAoKNheFIgCHAgAZAAQKZwrAVQC5AAAAAA==.',
St='Staticprot:BAAANQAECgIIAgABNQAECgoKKwAKAK0RAA==.Staticsrexar:BAABNQAECn8rAAQKAAoKrRGPZgDeAQAKAAoKrRGPZgDeAQAhAAEKJQa0EgA9AAAJAAEKAABEmQAnAAAAAA==.Stayk:BAAANQADCggIDQAAAA==.Stepbro:BAAANQAECgIIAgABNQAECgMIBAADAAAAAA==.Stinksauce:BAABNQAECn8hAAQNAAkKNxdoEgCGAgANAAkKNxdoEgCGAgAjAAUK8xv5CwCbAQAOAAQKyA5zJwD3AAAAAA==.Strokntotem:BAABNQAECn8UAAIXAAYKNhpNUwCuAQAXAAYKNhpNUwCuAQAAAA==.',
Su='Superchunk:BAAANQAECgMIBgAAAA==.Sutra:BAABNQAECn8dAAIBAAkKChFwawDcAQABAAkKChFwawDcAQAAAA==.',
Sy='Sylmarillion:BAAANQAECgUIBgAAAA==.',
Ta='Talgulen:BAABNQAECn8/AAIOAAoKSRuCBQBVAgAOAAoKSRuCBQBVAgAAAA==.Tarquinius:BAAANQAECgUIEgAAAA==.Tasahof:BAAANQAECggIAgAAAA==.Taxii:BAABNQAECn8ZAAIBAAgKhBJMWQDCAQABAAgKhBJMWQDCAQABNQAECgoKOQAYABwmAA==.Taynte:BAAANQAECgcIDQAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAABNQAECn8YAAIVAAcK4QnfqwB7AQAVAAcK4QnfqwB7AQABNQAFFAMICQAUAFUVAA==.Theoshun:BAAANQAECggIDgAAAA==.Thrag:BAAANQAECgIIAgABNQAECgUIEAADAAAAAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.',
To='Tone:BAAANQAECggICgAAAA==.Torokai:BAAANQAECggIDAAAAA==.Torokami:BAAANQAECggIBwAAAA==.Torokuma:BAAANQAECggIBwAAAA==.Toroshinu:BAAANQAECggIAgAAAA==.Torotatsu:BAAANQAECgIIAgAAAA==.Totemlycool:BAAANQAECgUIBwABNQAECgoKLAAUAGwSAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAABNQAECn88AAMKAAoKtBQYRACfAgAKAAoKtBQYRACfAgAhAAEKAACBFQAAAAAAAA==.Treehuggër:BAABNQAECn8gAAMSAAgKTBMHLwCiAQASAAgKTBMHLwCiAQAgAAMKDwb0pQBNAAAAAA==.Trelia:BAAANQAECgEIAgAAAA==.Trogkin:BAABNQAECn8jAAIgAAoK+BsrLQBzAgAgAAoK+BsrLQBzAgABNQAFFAkJIwAJAMcZAA==.',
Tw='Twîsty:BAAANQADCgQIBgAAAA==.',
Ty='Tyrith:BAABNQAECn8qAAIYAAoKyCD/KQATAwAYAAoKyCD/KQATAwAAAA==.',
Ug='Ugotgotpal:BAABNQAECn8ZAAIEAAoKRAhU0gB3AQAEAAoKRAhU0gB3AQAAAA==.',
Ul='Ulazain:BAABNQAECn9EAAIQAAoKLhyWBQBmAgAQAAoKLhyWBQBmAgAAAA==.',
Um='Umadcuzbad:BAAANQADCgcICQAAAA==.',
Us='Usdaprime:BAABNQAECn8UAAILAAkKMQl6GwBLAQALAAkKMQl6GwBLAQAAAA==.',
Va='Vaas:BAAANQAECgYICwAAAA==.Vaporeön:BAAANQAECgcIDQAAAA==.Varrasha:BAAANQAECgEIAQAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAABNQAECn8fAAIEAAgK1wy8zQCAAQAEAAgK1wy8zQCAAQAAAA==.',
Vo='Vodilent:BAAANQAECgUIBwAAAA==.Voidarella:BAAANQABCgMIAwABNQAECgoKQQAEAHgdAA==.',
['Vè']='Vèx:BAABNQAECn8xAAIYAAoKkR6YMwDyAgAYAAoKkR6YMwDyAgAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgcIFQAVAOoHAA==.Watlas:BAAANQAECgcIDwABNQAFFAUICQAbAPoSAA==.',
Xa='Xavia:BAABNQAECn8hAAIVAAgKKhLycgBtAQAVAAgKKhLycgBtAQAAAA==.',
Yu='Yunaraa:BAAANQAECgIIAwABNQAECgoKPAAKALQUAA==.',
Yv='Yvana:BAAANQADCgYIEQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMIBgABNQAFFAkJJgAgAG0kAA==.',
Zo='Zombies:BAABNQAECn8WAAIbAAgKMBf9SADzAQAbAAgKMBf9SADzAQAAAA==.',
Zu='Zugmaster:BAABNQAECn9BAAMkAAoKWxuyCgAcAgAkAAoKWxuyCgAcAgAmAAQK8BD6fwAGAQAAAA==.Zugszy:BAAANQAECgQIBwAAAA==.',
Zy='Zynn:BAAANQAECgEJAQABNQABCgQIBAADAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFH8mAAIgAAkKbSTtAADdAgAgAAkKbSTtAADdAgA1AAQKfyEAAiAACgoDJqgSADMDACAACgoDJqgSADMDAAAA.Zzephyrmage:BAAANQAECgQICQABNQAFFAkJJgAgAG0kAA==.',
['Çä']='Çärvé:BAAANQAECgEIAQAAAA==.',
['Ôä']='Ôäk:BAAANQAECgUICQABNQAECgcIIgASAD0RAA==.',
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
