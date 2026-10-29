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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warrior-Protection','Unknown-Unknown','DeathKnight-Blood','Warlock-Demonology','Hunter-Marksmanship','Druid-Guardian','Shaman-Enhancement','Warrior-Arms','DeathKnight-Frost','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Holy','Druid-Restoration','Priest-Discipline','Rogue-Assassination','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abukuma:BAAANQAECgUIBwAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAFFAYIDgABAJYPAA==.',
Ae='Aenstalash:BAABNQAECn8uAAMCAAoK1x/gGgBtAgACAAkKEx/gGgBtAgADAAcKEQzcxgDRAAAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAABNQAECn8rAAIEAAoKORFUJQBNAQAEAAoKORFUJQBNAQAAAA==.',
Al='Alfonsoo:BAAANQAECgEIAQAAAA==.Alistur:BAABNQAECn8VAAMFAAcKagL+JABVAAABAAcK1QGLcwHXAAAFAAQK9QL+JABVAAAAAA==.',
Am='Ameena:BAABNQAECn8mAAMGAAoKVhUxTwAoAgAGAAoKVhUxTwAoAgAHAAEKGwh+xgAzAAAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Anamura:BAAANQADCgMIAwAAAA==.Angus:BAAANQAECgYIDgAAAA==.',
Ar='Arcomedes:BAAANQAECgYIDQAAAA==.Arthrasz:BAABNQAECn8ZAAIDAAoKgxOmmQDwAQADAAoKgxOmmQDwAQAAAA==.Arthraz:BAABNQAECn8lAAIIAAoKLBbSDgAGAgAIAAoKLBbSDgAGAgAAAA==.',
As='Asondralyn:BAAANQAECgEIAQAAAA==.Astara:BAABNQAECn8lAAIJAAoKcxPqBgBIAgAJAAoKcxPqBgBIAgAAAA==.Astrex:BAABNQAECn8oAAMKAAcKgxlGCgACAgAKAAcKgxlGCgACAgALAAEKAgKWQwAgAAAAAA==.',
Au='Aurali:BAAANQAECgYIEAAAAA==.Aureliá:BAABNQAECn8bAAIMAAYKpQbj5wAxAQAMAAYKpQbj5wAxAQAAAA==.',
Az='Azureth:BAAANQAECgcICQAAAA==.',
['Aü']='Aütobot:BAAANQAECgUIDAAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQAECgQIBwABNQAECgkJKAANAP4YAA==.',
Be='Bega:BAAANQAECgIIAgABNQAFFAQIBwAOAIIEAA==.Belatrixx:BAAANQAECgEIAQAAAA==.',
Bl='Bloodlustplz:BAABNQAECn8nAAIPAAgKaRDrGgCJAQAPAAgKaRDrGgCJAQAAAA==.',
Bo='Bobster:BAABNQAECn8gAAIBAAoKbxJRuwANAgABAAoKbxJRuwANAgAAAA==.Bonepaw:BAAANQADCgUICAABNQAECgcIBwAQAAAAAA==.Booyea:BAABNQAECn81AAIRAAkKzxVnIwB5AQARAAkKzxVnIwB5AQAAAA==.',
Br='Brew:BAAANQABCgIJAgAAAA==.Brewwnor:BAAANQAECgYIEgAAAA==.Brewwnôr:BAAANQADCgEIAQAAAA==.Brewwtus:BAAANQADCgMIAwAAAA==.Brisfloggnaw:BAAANQADCgcIBwAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.Bubbleplop:BAAANQAECgYIDAABNQAECggIFgASADESAA==.',
Ca='Calamuelis:BAACNQAFFH8QAAMMAAgKbBq+BAANAgAMAAYKYxm+BAANAgATAAMKfxyNEABbAAA1AAQKfzUAAwwACgoeJmkOAG4DAAwACgr6JWkOAG4DABMACAqPJDQEANwCAAAA.Caliope:BAAANQAECgUIDAAAAA==.Carnage:BAAANQAECggIBAAAAA==.Cathbad:BAABNQAECn8xAAIUAAoKeBKXGgDRAQAUAAoKeBKXGgDRAQAAAA==.Cazlek:BAAANQAECgEIAQAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECgoKJQAIACwWAA==.Cerelus:BAABNQAECn8sAAIFAAkKsRfNCABOAgAFAAkKsRfNCABOAgAAAA==.',
Ch='Chaac:BAABNQAECn8hAAIVAAgKEh67CQDZAgAVAAgKEh67CQDZAgAAAA==.Chediah:BAAANQAECgMICQAAAA==.Cheesûs:BAAANQAECgUIDgAAAA==.Chubbiesub:BAAANQAECggIDgAAAA==.Chéwtoy:BAAANQAECgUICAAAAA==.',
Ci='Cilantro:BAAANQAECgMIAwABNQAECgoKJQAIACwWAA==.',
Co='Cowmus:BAABNQAECn8VAAMCAAgKchnUfgCdAQACAAgKchnUfgCdAQADAAcK2Amy6wBFAQABNQAECgoKNAAGAC0fAA==.',
['Cã']='Cãrloy:BAABNQAECn94AAIWAAoKCR4FIwAsAwAWAAoKCR4FIwAsAwAAAA==.',
Da='Daedalas:BAABNQAECn8dAAIOAAkKjRTAJQABAgAOAAkKjRTAJQABAgAAAA==.Daenari:BAAANQADCgYIBgAAAA==.Darkxsoul:BAABNQAECn8oAAINAAkK/hisCwDzAQANAAkK/hisCwDzAQAAAA==.Darthgrogu:BAAANQAECgYIEQABNQAFFAYIDAADAEELAA==.Darthknull:BAACNQAFFH8MAAIDAAYKQQuUDwBTAQADAAYKQQuUDwBTAQA1AAQKfysAAgMACgrMHl0hAIUCAAMACgrMHl0hAIUCAAAA.Darthputska:BAAANQAECgQIBAABNQAFFAYIDAADAEELAA==.Darthreven:BAAANQAECgUIEwABNQAFFAYIDAADAEELAA==.Darthtalon:BAABNQAECn8ZAAIXAAoKNAnqRQCpAQAXAAoKNAnqRQCpAQABNQAFFAYIDAADAEELAA==.Dayla:BAAANQADCgMIAwAAAA==.',
De='Deathwood:BAAANQAECgMICgAAAA==.Deatthdecay:BAAANQAECggJAQAAAA==.Degloved:BAEANQAECgQIBgABNQAECgoKNgAGABwcAA==.Deitrichx:BAAANQAECgMIBAAAAA==.Deminestrea:BAAANQADCgcICAAAAA==.Demonslayere:BAAANQAECggICgABNQAFFAcIGQAYAEoiAA==.',
Di='Discodeitx:BAAANQADCgIIAgAAAA==.Disshammy:BAAANQAECgIIBAABNQAECggIDgAQAAAAAA==.',
Do='Donkform:BAAANQAECgIIBAABNQAECgYIEAAQAAAAAA==.Donkulle:BAAANQAECgYIEAAAAA==.',
Dr='Draconith:BAABNQAECn80AAIKAAoKCB0KAwAmAwAKAAoKCB0KAwAmAwAAAA==.Draqkmar:BAAANQADCgcICAAAAA==.',
Du='Dunsparrow:BAABNQAECn80AAIGAAoKLR9LIgDeAgAGAAoKLR9LIgDeAgAAAA==.Durzul:BAAANQADCgcICwAAAA==.',
Ei='Eindraken:BAABNQAECn8zAAMKAAoKVxL3CgDtAQAKAAoKVxL3CgDtAQALAAEKAACSQgAkAAAAAA==.Eisis:BAABNQAECn8jAAIZAAoKOg5yCgCUAQAZAAoKOg5yCgCUAQAAAA==.',
El='Elanalué:BAAANQAECgEIAQABNQAECgUIDAAQAAAAAA==.',
Em='Empoleonn:BAABNQAECn8VAAIOAAgK7w5NJgD8AQAOAAgK7w5NJgD8AQAAAA==.',
En='Engos:BAAANQADCgYIBwAAAA==.',
Ep='Epsolone:BAAANQABCgMIAwAAAA==.',
Er='Erroz:BAAANQADCggIEwAAAA==.Erukani:BAABNQAECn8UAAIaAAcKPAhEXgBXAQAaAAcKPAhEXgBXAQAAAA==.',
Es='Espriesso:BAABNQAECn8sAAMbAAoKegq7QwCjAQAbAAoKegq7QwCjAQAOAAIK0APSSgAuAAAAAA==.',
Ex='Exemplar:BAAANQAECgUIBgAAAA==.',
Fe='Fearwatermac:BAAANQAECgYIDgAAAA==.Feider:BAAANQABCgQJBwAAAA==.Felais:BAABNQAECn8sAAIcAAoK0hnJHQBCAgAcAAoK0hnJHQBCAgAAAA==.Felin:BAAANQABCggIJAAAAA==.Femmefatale:BAABNQAECn9CAAQbAAoKHx3rDgD9AgAbAAoKHx3rDgD9AgAOAAcKiw5aNQB5AQAdAAYKLgqJEQAPAQAAAA==.',
Fl='Flamecube:BAAANQAECgEIAgAAAA==.Flashx:BAABNQAECn8dAAICAAcKCR/TGgBtAgACAAcKCR/TGgBtAgAAAA==.Flass:BAAANQADCggIDgAAAA==.',
Fr='Freerin:BAAANQADCgcICAAAAA==.Frevpl:BAAANQAECgIIBAAAAA==.Frofrohunter:BAAANQAECgYIEwAAAA==.Froggie:BAAANQAECgcIBwAAAA==.',
Fu='Fuzywuuzy:BAAANQAECgYICQAAAA==.',
Ga='Gattsu:BAAANQAECgYIBgABNQAECgoKMAACAM4QAA==.Gazdorn:BAABNQAECn8WAAIPAAcKZgzeHgBcAQAPAAcKZgzeHgBcAQAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgcIEwAAAA==.',
Ge='Genghis:BAAANQADCgQICAAAAA==.',
Gh='Ghost:BAABNQAECn8rAAIeAAoKIRmPCwDHAQAeAAoKIRmPCwDHAQAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAABNQAECn8eAAIHAAkK6BU1dgC/AQAHAAkK6BU1dgC/AQAAAA==.Gimmighoul:BAAANQAECgMIAwAAAA==.',
Gl='Gleoc:BAABNQAECn8gAAISAAkKVAjLcwATAQASAAkKVAjLcwATAQAAAA==.Glissa:BAABNQAECn8kAAQfAAoKMhwAHQCGAQASAAcKrBnjgADkAQAfAAQKrCEAHQCGAQAgAAUKfhaBDgBqAQAAAA==.',
Go='Gorditt:BAAANQAECgIIAgAAAA==.',
Gt='Gt:BAABNQAECn8wAAMCAAoKzhCAaQDbAQACAAkKMxKAaQDbAQANAAcKQAu+OAAmAQAAAA==.',
Ha='Habanero:BAAANQAECggIDwABNQAECgoKJQAIACwWAA==.Hadense:BAAANQADCggICAABNQAFFAQIEAAHAH8cAA==.Hadory:BAAANQAECggIEQAAAA==.',
He='Hellzzdemon:BAAANQAECgQIDQAAAA==.Hercow:BAAANQAECgYIDQAAAA==.Herrvoller:BAAANQADCgEIAQAAAA==.Hexinverter:BAAANQADCggIEgAAAA==.',
Ho='Holycannoli:BAABNQAECn8gAAIDAAkKvR0MLQBJAgADAAkKvR0MLQBJAgAAAA==.Horiffic:BAABNQAECn8kAAIhAAoK8h/kAQDVAgAhAAoK8h/kAQDVAgAAAA==.Horok:BAAANQAECgQIBAAAAA==.Hotfuzz:BAABNQAECn8eAAIBAAoKDh0sVwDSAgABAAoKDh0sVwDSAgAAAA==.Hotsforthots:BAABNQAECn8zAAIbAAoKuRpBEgDYAgAbAAoKuRpBEgDYAgAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.Hurricaneg:BAAANQADCgMIAwAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ic='Ichaerus:BAAANQAECgIIBAABNQAECgkJHQAOAI0UAA==.',
Ii='Iilli:BAAANQADCgYIBgAAAA==.',
In='Inari:BAAANQAECgMIBAAAAA==.Inkkubus:BAACNQAFFH8VAAQfAAYKWxMIBACbAAASAAMKBBXrJwDIAAAfAAIKNxIIBACbAAAgAAIKdxKDBgBbAAA1AAQKfzwABBIACgrAHh1BAI8CABIACQrPHh1BAI8CACAABQpIF88LANQAAB8AAwqgETZDALgAAAAA.',
Ir='Ironfur:BAAANQAECgUIBgABNQAFFAYIEAACAMQQAA==.',
Je='Jeffpwnros:BAAANQAECgQIBgAAAA==.',
Jh='Jhohn:BAAANQAECgQICgAAAA==.',
Ji='Jintan:BAAANQAECgQICwAAAA==.',
Ju='Judgmentjudy:BAACNQAFFH8QAAICAAYKxBCTDACVAQACAAYKxBCTDACVAQA1AAQKf48ABAIACgrpIksCANYDAAIACgrpIksCANYDAA0AAgrWA/tFAEEAAAMAAQqDAGrlAQoAAAAA.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAABNQAECn8sAAIFAAkKigvbCQB0AQAFAAkKigvbCQB0AQAAAA==.Kariatyda:BAABNQAECn8tAAIMAAoKqBSGOwDyAQAMAAoKqBSGOwDyAQAAAA==.Kasaí:BAABNQAECn8VAAIHAAYKMQ6DpQBJAQAHAAYKMQ6DpQBJAQAAAA==.Kassandra:BAAANQADCggICAAAAA==.',
Ke='Kekio:BAAANQAECgUICQAAAA==.',
Ki='Kiloton:BAABNQAECn8kAAIUAAgKQBEtIQCRAQAUAAgKQBEtIQCRAQAAAA==.Kinari:BAAANQAECgIIAwABNQAECgYIEgAQAAAAAA==.Kitzy:BAAANQAECgUIDAAAAA==.',
Kl='Klippertdk:BAABNQAECn80AAIEAAgKOxXVGwCVAQAEAAgKOxXVGwCVAQAAAA==.Klutz:BAABNQAECn8iAAIcAAkK0hMOJgDyAQAcAAkK0hMOJgDyAQAAAA==.',
Kn='Kniwt:BAAANQAECgEIAQABNQAECgoKMAACAM4QAA==.',
Ku='Kurzo:BAABNQAECn8bAAIWAAgKTxosfQAiAgAWAAgKTxosfQAiAgABNQAFFAIIAgAQAAAAAA==.',
Ky='Kylarian:BAAANQAECgEIAgAAAA==.Kyntara:BAAANQAECgUIBwAAAA==.Kyronian:BAAANQAECgUIDQAAAA==.',
La='Lachancea:BAABNQAECn8cAAIGAAgK+BcIOQC3AQAGAAgK+BcIOQC3AQABNQAECgoKKQASAEUbAA==.Laeleirri:BAAANQAECggIEQAAAA==.Lakshmee:BAABNQAECn8WAAIGAAcKwgW8rgASAQAGAAcKwgW8rgASAQAAAA==.Landwar:BAAANQADCgYIBgAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAABNQAECn8fAAIMAAoK3gMO7wAjAQAMAAoK3gMO7wAjAQAAAA==.Leonah:BAAANQAECgEIAQABNQAECgUIDAAQAAAAAA==.Lexxi:BAAANQAECgMIBgAAAA==.',
Lh='Lhuru:BAAANQADCggIGwABNQAECgkJLAAFALEXAA==.',
Li='Lightbehunt:BAAANQAECgYIEgAAAA==.Lightdeborah:BAAANQADCgYIBgAAAA==.Lilly:BAAANQADCgYIBgAAAA==.Linestra:BAAANQAFFAIIAgAAAA==.Livaless:BAAANQAECgMIBAABNQAECgoKKQASAEIhAA==.',
Lo='Lorstus:BAAANQABCgYIBgAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAECggIEQAQAAAAAA==.Lux:BAAANQAECgEIBQAAAA==.',
Ma='Mahidevran:BAAANQADCggIAgABNQAECgUIDAAQAAAAAA==.Maitotoxin:BAAANQADCggIEgAAAA==.Majikarp:BAAANQAECgUIBQAAAA==.Mal:BAAANQADCggIFAABNQAECgYIGAACALYgAA==.Malthaius:BAAANQADCgUIBQAAAA==.Marble:BAAANQADCgYIBgABNQAECgcIBwAQAAAAAA==.Marché:BAAANQAECgEIAwAAAA==.Mastablasta:BAAANQAECgQICgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAABNQAECn8aAAIcAAoKBgxrMwB/AQAcAAoKBgxrMwB/AQAAAA==.Mawks:BAABNQAECn84AAMiAAoKhRzZAQB/AgAiAAoKORvZAQB/AgAMAAUKixreawBhAQAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.',
Mi='Migzeviltwin:BAAANQAECgMIBAAAAA==.Milk:BAAANQAECgEIAgAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwAQAAAAAA==.Monkent:BAAANQAECgcIDAAAAA==.Monstabull:BAAANQADCgUIBQAAAA==.Moomoomonkey:BAAANQADCgUIBQAAAA==.Morhgana:BAAANQADCgIIAgAAAA==.',
Na='Nallaa:BAAANQAECgYIEgAAAA==.Naranak:BAABNQAECn8iAAINAAcKdQ5aIgDpAAANAAcKdQ5aIgDpAAAAAA==.',
Ne='Neremian:BAAANQADCgQIBAAAAA==.',
No='Noodles:BAAANQAECgQIBQABNQAECgYIFAADAHUVAA==.',
Ny='Nymara:BAABNQAECn8cAAINAAgKAhDjKwB+AQANAAgKAhDjKwB+AQAAAA==.',
Ob='Obolus:BAAANQADCgEIAQAAAA==.',
Oc='Occan:BAAANQADCgMIAwAAAA==.',
Ol='Oldenglish:BAABNQAECn8iAAIDAAkKIwdZzQCBAQADAAkKIwdZzQCBAQAAAA==.',
On='Ontos:BAABNQAECn8wAAMcAAkKChFXGACvAQAcAAkKChFXGACvAQAaAAUKzQ6HbwAMAQABNQAECgoKQgAbAB8dAA==.',
Or='Orrok:BAAANQADCgEIAQAAAA==.',
Os='Osita:BAAANQAECgIIAwAAAA==.',
Pa='Painnkiller:BAABNQAECn8wAAIMAAoKmBXzKwAxAgAMAAoKmBXzKwAxAgAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAABNQAECn8gAAIgAAgKhBqxBgA+AgAgAAgKhBqxBgA+AgABNQAECgoKJQAIACwWAA==.',
Pe='Perriwinkle:BAABNQAECn80AAMZAAoKthjZBwDYAQAZAAoKthjZBwDYAQAcAAQKDQ6wNgDDAAAAAA==.',
Ph='Phylloxeras:BAABNQAECn87AAMEAAoKYSXCAQBUAwAEAAoKYSXCAQBUAwAXAAEKAAAurAA2AAAAAA==.',
Po='Popecannoli:BAAANQAECgQIBAABNQAECgkJIAADAL0dAA==.Powders:BAAANQAECgQICgAAAA==.',
Pr='Priopopo:BAAANQAECgEIAQAAAA==.Prophecyrose:BAAANQADCgQIBQAAAA==.Proshot:BAABNQAECn8eAAIiAAkKyhddAwD4AQAiAAkKyhddAwD4AQAAAA==.',
Pu='Puddles:BAAANQAECgEIAwAAAA==.',
Py='Pyrasi:BAABNQAECn8iAAIMAAgKHROJaQBBAgAMAAgKHROJaQBBAgAAAA==.',
Ra='Raccoon:BAABNQAECn8cAAMSAAgKBgomogCRAQASAAgKBgomogCRAQAgAAEKxw63KwA/AAAAAA==.Ralor:BAAANQADCgQIBAAAAA==.Razza:BAAANQADCggIEgAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgcIBwABNQAECgoKJAAjADocAA==.',
Ro='Roa:BAAANQADCggIFQAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAACNQAFFH8XAAMjAAcKExMeBwDNAQAjAAcKExMeBwDNAQAkAAIKMRHiEQCAAAA1AAQKfzQAAyMACgr2ICISAC0CACQACQo0G1MfAFQCACMACAoMIiISAC0CAAAA.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECggICwAAAA==.',
Sa='Saffron:BAAANQAECgMIBQABNQAECgoKJQAIACwWAA==.Samidrac:BAAANQAECgMIEQAAAA==.Sammidormu:BAAANQAECgYIEwAAAA==.Saphiragosa:BAAANQADCggIDAAAAA==.Saräha:BAAANQADCggJCwAAAA==.Satoshie:BAAANQAECgYIBgAAAA==.Satòshí:BAAANQADCgQIBgABNQAECgYIBgAQAAAAAA==.Sayang:BAAANQADCgMIAwABNQAECgcIFwAcAEkiAA==.',
Sc='Scacatrace:BAAANQAECgEIAQAAAA==.Scerevisiae:BAABNQAECn8pAAMSAAoKRRvDGQBkAgASAAoKRRvDGQBkAgAfAAEKgBVTbwBAAAAAAA==.',
Se='Sedelis:BAAANQAECgUIEQAAAA==.Selaya:BAAANQAECgMIAwAAAA==.Serafín:BAABNQAECn83AAIIAAoKQg4OBgCvAQAIAAoKQg4OBgCvAQAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQAECgIIAwAAAA==.Shadownutt:BAAANQAECgQICAAAAA==.Sharur:BAAANQAECggIEgAAAA==.Shazzam:BAAANQAECggICAAAAA==.Shieldwall:BAAANQAECgIIAwAAAA==.',
Si='Silanah:BAAANQAECgUICgABNQAECgoKNAAGAC0fAA==.Silveroaks:BAAANQADCgQIBAABNQAECgcIDAAQAAAAAA==.Silverphish:BAAANQAECgEIAgABNQAECgoKMAACAM4QAA==.',
So='Sodapop:BAAANQAECgEIAQABNQAECgoKMAACAM4QAA==.Somavra:BAAANQAECggIEAAAAA==.Sopidia:BAAANQAECgYIEwAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAABNQAECn8aAAMbAAgKzxT5aADkAQAbAAgKzxT5aADkAQAdAAEK8hBMKQAxAAAAAA==.Spiritomb:BAAANQAECgYICwAAAA==.Spúdd:BAABNQAECn8yAAIWAAoKLRryHQCBAgAWAAoKLRryHQCBAgAAAA==.',
St='Stamavan:BAABNQAECn8gAAIUAAoKnhu0CgDEAgAUAAoKnhu0CgDEAgAAAA==.Starflayer:BAAANQAECggICAABNQAFFAYIDgABAJYPAA==.Strykerius:BAAANQAECgEIAQABNQAECgUIDAAQAAAAAA==.',
Su='Sunari:BAAANQADCgcIBwAAAA==.Supermelon:BAAANQAECgYIEgAAAA==.',
Sy='Syena:BAAANQAECgEIAQAAAA==.Sylvanaria:BAABNQAECn81AAIGAAkKVR8PIwDbAgAGAAkKVR8PIwDbAgAAAA==.Systyx:BAAANQADCgUICQABNQAECgQIBgAQAAAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.Tarot:BAAANQAECggICAAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAABNQAECn80AAIEAAoKmSJ/CQCKAgAEAAoKmSJ/CQCKAgAAAA==.',
Th='Thaneer:BAAANQADCgQICAAAAA==.Throstmok:BAABNQAECn8dAAIRAAoK+xn+LQBdAgARAAoK+xn+LQBdAgAAAA==.Thumbalina:BAAANQADCgYIBgABNQAECgkJIwACAF8RAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tideus:BAAANQADCgcIBwAAAA==.Tilingo:BAAANQAECgUIBgAAAA==.',
To='Tongra:BAAANQADCggIHwABNQAECgkJLAAFALEXAA==.Torg:BAABNQAECn8VAAIRAAgKew1oXgB4AQARAAgKew1oXgB4AQAAAA==.Torgin:BAAANQAECgQIDAAAAA==.',
Tr='Trinitea:BAAANQAECgEIAQAAAA==.',
Tu='Turgies:BAABNQAECn8uAAMBAAgKgxVAWACkAQABAAgKgxVAWACkAQAFAAIKqQ6AMwBtAAAAAA==.Turgroka:BAAANQAECgcIDwAAAA==.',
['Tí']='Tíffanny:BAAANQAECgQIBQAAAA==.',
Ub='Ubaubadead:BAAANQAECgQIBwAAAA==.Ubaubajuana:BAABNQAECn8zAAIGAAkKkh0REgC+AgAGAAkKkh0REgC+AgAAAA==.',
Ul='Ulfast:BAABNQAECn8xAAIHAAgKmhwnNgCeAgAHAAgKmhwnNgCeAgAAAA==.',
Va='Vannhellsing:BAABNQAECn8jAAMEAAgKrgZnNwDgAAAEAAgKrgZnNwDgAAAXAAMKrAHfnQBVAAAAAA==.Vanyel:BAABNQAECn8/AAIFAAoKHBZXCgAkAgAFAAoKHBZXCgAkAgAAAA==.Vardant:BAAANQADCgMIAwABNQAECgYIBgAQAAAAAA==.',
Ve='Veliena:BAAANQADCgYIBgABNQAECgUIEQAQAAAAAA==.Vemal:BAABNQAECn8yAAIMAAgKHRJEcwAqAgAMAAgKHRJEcwAqAgAAAA==.',
Vi='Vidula:BAAANQADCgcICAAAAA==.Vigorous:BAABNQAECn8cAAIPAAgKhQiJIgA1AQAPAAgKhQiJIgA1AQAAAA==.',
Vo='Vociferoy:BAABNQAECn84AAMMAAoKvRmFJQBNAgAMAAoKvRmFJQBNAgATAAEKpAFaXQAlAAAAAA==.Voidsteffan:BAABNQAECn8pAAIfAAgKaQ9EBQA/AQAfAAgKaQ9EBQA/AQAAAA==.',
Vv='Vv:BAACNQAFFH8uAAMkAAgKWyYIAAB3AwAkAAgKWyYIAAB3AwAjAAUKnBnTCgB2AQA1AAQKfz0AAyMACgqmJmIBAGoDACQACQq5JnYFAHsDACMACgrDJWIBAGoDAAAA.',
Wa='Waterworks:BAAANQAECgUICQABNQAECgoKMAACAM4QAA==.',
Wi='Willowmoon:BAAANQAECgMIAwAAAA==.',
Wo='Worgenlina:BAAANQAECgEIAgAAAA==.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAFFAcIFwAaAPUWAA==.',
['Wá']='Wárranpeace:BAAANQADCgIIAgAAAA==.',
Xa='Xalmo:BAAANQADCgQIBAABNQAECggIJAAJABAVAA==.Xalzi:BAAANQADCgEIAQABNQAECgcIBwAQAAAAAA==.',
Xu='Xul:BAAANQABCggICgAAAA==.',
Xy='Xyphër:BAAANQAECgEIAQABNQAECgUIDAAQAAAAAA==.',
Yo='Yotie:BAAANQADCgIIAgAAAA==.',
Za='Zannytoes:BAABNQAECn8cAAMlAAoKuQxiMQCNAQAlAAoKuQxiMQCNAQAYAAcKSAzELAAGAQAAAA==.',
Zi='Zie:BAABNQAECn8xAAIOAAkK7hIpFgBtAQAOAAkK7hIpFgBtAQAAAA==.',
['Ñi']='Ñice:BAACNQAFFH8HAAMhAAQKaRyUAQAYAQAhAAMKqxuUAQAYAQAWAAEK5R0XOgBQAAA1AAQKfzUAAyEACQoXJVYFANACABYACAqhJFMpABUDACEACArjIFYFANACAAAA.',
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
