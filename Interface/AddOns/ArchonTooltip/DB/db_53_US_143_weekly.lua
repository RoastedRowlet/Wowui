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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warrior-Protection','Unknown-Unknown','DeathKnight-Blood','Warlock-Affliction','Hunter-Marksmanship','Druid-Guardian','Shaman-Enhancement','DemonHunter-Havoc','Warrior-Arms','Warlock-Destruction','DeathKnight-Frost','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Holy','Druid-Restoration','Priest-Discipline','Rogue-Assassination','Warlock-Demonology','Warrior-Fury','DemonHunter-Vengeance','Hunter-Survival','DemonHunter-Devourer','Monk-Windwalker',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abukuma:BAAANQAECgUIBgAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAFFAcIEAABAG0OAA==.',
Ae='Aenstalash:BAABNQAECn85AAMCAAoK8x9LEgAaAwACAAoK8x9LEgAaAwADAAcKEQxfBwHJAAAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAABNQAECn8rAAIEAAoKOREvUADTAQAEAAoKOREvUADTAQAAAA==.',
Al='Aleeah:BAAANQABCgIIAgAAAA==.Alfonsoo:BAAANQAECgEIAQAAAA==.Alistur:BAABNQAECn8aAAMFAAcKEgOWLABtAAABAAcK1QGLcwHXAAAFAAUKTwSWLABtAAAAAA==.',
Am='Ameena:BAABNQAECn8pAAMGAAoKPhYxTwAoAgAGAAoKPhYxTwAoAgAHAAEKGwjg9QAzAAAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Anamura:BAAANQADCgMIAwAAAA==.Angus:BAAANQAECgUIDAAAAA==.',
Ar='Arcomedes:BAAANQAECgYICAAAAA==.Arthrasz:BAABNQAECn8ZAAIDAAoKgxOmmQDwAQADAAoKgxOmmQDwAQAAAA==.Arthraz:BAABNQAECn8rAAIIAAoKMxjSDgAGAgAIAAoKMxjSDgAGAgAAAA==.',
As='Asondralyn:BAAANQABCgUIBgAAAA==.Astara:BAACNQAFFH8IAAIJAAQKMgf8CACsAAAJAAQKMgf8CACsAAA1AAQKfyoAAgkACgpzE+oGAEgCAAkACgpzE+oGAEgCAAAA.Astrex:BAABNQAECn8tAAQKAAcKgxmqDwD5AQAKAAcKgxmqDwD5AQALAAEKAgKWQwAgAAAJAAEKYAKSHgAeAAAAAA==.',
Au='Aurali:BAAANQAECgUIEAAAAA==.Aureliá:BAABNQAECn8gAAIMAAYKtgfj5wAxAQAMAAYKtgfj5wAxAQAAAA==.',
Ay='Ayixi:BAAANQAECgYIBwAAAA==.',
Az='Azureth:BAAANQAECgcIBwAAAA==.',
['Aü']='Aütobot:BAAANQAECgUICQAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQAECgQIBgABNQAECgoKOgANAKgeAA==.',
Be='Bega:BAAANQAECgIIAgABNQAFFAQIBwAOAIIEAA==.',
Bl='Bloodlustplz:BAABNQAECn8oAAIPAAkKYA/rGgCJAQAPAAkKYA/rGgCJAQAAAA==.',
Bo='Bobster:BAABNQAECn8gAAIBAAoKbxJRuwANAgABAAoKbxJRuwANAgAAAA==.Bonepaw:BAAANQADCgUICAABNQAECgYIBwAQAAAAAA==.Booyea:BAABNQAECn9AAAIRAAoKThirFwA6AgARAAoKThirFwA6AgAAAA==.',
Br='Brew:BAAANQABCgIJAgAAAA==.Brewwnor:BAABNQAECn8WAAIMAAcKARWYqgCwAQAMAAcKARWYqgCwAQAAAA==.Brewwnôr:BAAANQADCgEIAQAAAA==.Brewwtus:BAAANQADCgMIAwAAAA==.Brisfloggnaw:BAAANQADCgcIBwAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.Bubbleplop:BAAANQAECgYICwABNQAECggIHgASADwWAA==.',
Ca='Calamuelis:BAACNQAFFH8QAAMMAAgKbBq+BAANAgAMAAYKYxm+BAANAgATAAMKfxwGGgBUAAA1AAQKfzUAAwwACgoeJmkOAG4DAAwACgr6JWkOAG4DABMACAqPJGoIALECAAAA.Caliope:BAAANQAECgUIDQAAAA==.Carnage:BAAANQAECggIAgAAAA==.Cathbad:BAABNQAECn8+AAIUAAoKYBVjFQDRAQAUAAoKYBVjFQDRAQAAAA==.Cazlek:BAAANQADCggIIQAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECgoKKwAIADMYAA==.Cerelus:BAABNQAECn81AAIFAAoKQBjNCABOAgAFAAoKQBjNCABOAgAAAA==.',
Ch='Chaac:BAABNQAECn8uAAIVAAoKax+FCACOAgAVAAoKax+FCACOAgAAAA==.Chediah:BAAANQAECgQICwAAAA==.Cheesûs:BAAANQAECgUICwAAAA==.Chéwtoy:BAABNQAECn8WAAIWAAoKMwpNLgCKAQAWAAoKMwpNLgCKAQAAAA==.',
Ci='Cilantro:BAAANQAECgQIBAABNQAECgoKKwAIADMYAA==.',
Co='Cowmus:BAABNQAECn8aAAMCAAkKcBj9VACuAQACAAkKcBj9VACuAQADAAcK2Amy6wBFAQABNQAECgoKPwAGAC0fAA==.',
['Cã']='Cãrloy:BAABNQAECn+NAAIXAAoKNCAFIwAsAwAXAAoKNCAFIwAsAwAAAA==.',
Da='Daedalas:BAABNQAECn8iAAIOAAoK0xfvGwCeAQAOAAoK0xfvGwCeAQAAAA==.Daenari:BAAANQADCgYIBgAAAA==.Darkxsoul:BAABNQAECn86AAINAAoKqB6qBwDCAgANAAoKqB6qBwDCAgAAAA==.Darthgrogu:BAABNQAECn8VAAIYAAcKyAV+JQBIAQAYAAcKyAV+JQBIAQABNQAFFAYIDAADAEELAA==.Darthknull:BAACNQAFFH8MAAIDAAYKQQuUDwBTAQADAAYKQQuUDwBTAQA1AAQKfzEAAgMACgrwHhM9AGUCAAMACgrwHhM9AGUCAAAA.Darthputska:BAAANQAECgYIBgABNQAFFAYIDAADAEELAA==.Darthreven:BAABNQAECn8YAAIBAAYK7QTS+ACwAAABAAYK7QTS+ACwAAABNQAFFAYIDAADAEELAA==.Darthtalon:BAABNQAECn8ZAAIZAAoKNAnqRQCpAQAZAAoKNAnqRQCpAQABNQAFFAYIDAADAEELAA==.Dayla:BAAANQADCgMIAwAAAA==.',
De='Deathchill:BAAANQADCgEIAQABNQAECgkJIgAPALEUAA==.Deathlylazy:BAAANQADCgEIAQAAAA==.Deathwood:BAABNQAECn8iAAIPAAkKsRTHCwDyAQAPAAkKsRTHCwDyAQAAAA==.Deatthdecay:BAAANQAECggIAQAAAA==.Degloved:BAEANQAECgQIBgABNQAECgoKNgAGABwcAA==.Deitrichx:BAAANQAECgMIAwAAAA==.Deminestrea:BAAANQADCgcICAAAAA==.Demonslayere:BAAANQAECggIEAABNQAFFAgIHAAaADUgAA==.',
Di='Discodeitx:BAAANQADCgIIAgAAAA==.Disshammy:BAAANQAECgIIAwABNQAECggIDAAQAAAAAA==.',
Do='Donkform:BAAANQAECgIIAgABNQAECgYIDwAQAAAAAA==.Donkulle:BAAANQAECgYIDwAAAA==.',
Dr='Draconith:BAABNQAECn9AAAIKAAoKGR08BABEAwAKAAoKGR08BABEAwAAAA==.Draqkmar:BAAANQADCgcICAAAAA==.',
Du='Dunsparrow:BAABNQAECn8/AAIGAAoKLR9LIgDeAgAGAAoKLR9LIgDeAgAAAA==.Durgruk:BAAANQADCggICAABNQAECgoKQAAKABkdAA==.Durzul:BAAANQADCgcICwAAAA==.',
Ei='Eindraken:BAABNQAECn9DAAMKAAoK+xNQDwAAAgAKAAoK+xNQDwAAAgALAAEKAACSQgAkAAAAAA==.Eisis:BAABNQAECn8zAAIbAAoKARK2EQCLAQAbAAoKARK2EQCLAQAAAA==.',
El='Elanalué:BAAANQADCggIGAABNQAECgUIDQAQAAAAAA==.',
Em='Empoleonn:BAABNQAECn8VAAIOAAgK7w5NJgD8AQAOAAgK7w5NJgD8AQAAAA==.',
En='Engos:BAAANQADCgYIBwAAAA==.',
Ep='Epsolone:BAAANQABCgMIAwAAAA==.',
Er='Erroz:BAAANQADCggIEwAAAA==.Erukani:BAABNQAECn8UAAIcAAcKPAhEXgBXAQAcAAcKPAhEXgBXAQAAAA==.',
Es='Espriesso:BAABNQAECn85AAMdAAoKZxQrKQCUAgAdAAoKZxQrKQCUAgAOAAIK0AOfYgAsAAABNQAECgoKNwACAGkXAA==.',
Ex='Exemplar:BAAANQAECgcIEQAAAA==.',
Fe='Fearwatermac:BAAANQAECgYIDQAAAA==.Feider:BAAANQABCgQJBwAAAA==.Felais:BAACNQAFFH8JAAIeAAQKBRifCAAvAQAeAAQKBRifCAAvAQA1AAQKfzAAAh4ACgpLGskdAEICAB4ACgpLGskdAEICAAAA.Felin:BAAANQABCggIKgAAAA==.Femmefatale:BAABNQAECn9ZAAQdAAoKBCBsEwAsAwAdAAoKBCBsEwAsAwAOAAcKiw5aNQB5AQAfAAYKLgqJEQAPAQAAAA==.',
Fl='Flamecube:BAAANQADCgMIAwAAAA==.Flashx:BAABNQAECn8qAAICAAgKGyLdFwDpAgACAAgKGyLdFwDpAgAAAA==.Flass:BAAANQADCggIDgAAAA==.',
Fr='Freerin:BAAANQADCgcICAAAAA==.Frevpl:BAAANQAECgIIAgAAAA==.Frofrohunter:BAAANQAECgYIEgAAAA==.Froggie:BAAANQAECgYIBwAAAA==.Frostme:BAAANQAECgIIAQAAAA==.',
Fu='Fuzywuuzy:BAAANQAECgYIBwAAAA==.',
Ga='Gattsu:BAAANQAECgYICQABNQAECgoKMwACAM4QAA==.Gazdorn:BAABNQAECn8WAAIPAAcKZgzeHgBcAQAPAAcKZgzeHgBcAQAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgcIEAAAAA==.',
Ge='Genghis:BAAANQADCgQICAAAAA==.',
Gh='Ghost:BAABNQAECn8xAAIgAAoK8xwoCgAqAgAgAAoK8xwoCgAqAgAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAABNQAECn8lAAIHAAkK7hZvSACcAQAHAAkK7hZvSACcAQAAAA==.Gimmighoul:BAAANQAECgMIAwAAAA==.',
Gl='Glissa:BAABNQAECn8kAAQYAAoKMhwAHQCGAQAhAAcKrBnjgADkAQAYAAQKrCEAHQCGAQASAAUKfhaBDgBqAQAAAA==.Gloomidge:BAABNQAECn8gAAIDAAkKvAfLoAB2AQADAAkKvAfLoAB2AQAAAA==.',
Go='Gorditt:BAAANQAECgIIAgAAAA==.',
Gr='Graphene:BAAANQAECgQIBAABNQAECgoKMwACAM4QAA==.',
Gt='Gt:BAABNQAECn8zAAMCAAoKzhCAaQDbAQACAAkKMxKAaQDbAQANAAcKQAu+OAAmAQAAAA==.',
Ha='Habanero:BAAANQAECgcIDAABNQAECgoKKwAIADMYAA==.Hadense:BAAANQADCggICAABNQAFFAUIFQAHAL0gAA==.Hadory:BAAANQAECggIEQAAAA==.',
He='Hellzzdemon:BAAANQAECggIEAAAAA==.Hercow:BAAANQAECgYIEQAAAA==.Herrvoller:BAAANQADCgEIAQAAAA==.Hexinverter:BAAANQADCggIEgAAAA==.',
Ho='Holycannoli:BAABNQAECn8yAAIDAAoKtx/9KgCpAgADAAoKtx/9KgCpAgAAAA==.Holydeborah:BAAANQADCgUIBQAAAA==.Horiffic:BAABNQAECn8lAAIiAAoKTyDfAwC3AgAiAAoKTyDfAwC3AgAAAA==.Horok:BAAANQAECgQIBAAAAA==.Hotfuzz:BAABNQAECn8pAAIBAAoKXh2CNQBiAgABAAoKXh2CNQBiAgAAAA==.Hotsforthots:BAABNQAECn84AAIdAAoKzRsRIgC/AgAdAAoKzRsRIgC/AgAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.Hurricaneg:BAAANQADCgMIAwAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ic='Ichaerus:BAAANQAECgIIAgABNQAECgoKIgAOANMXAA==.',
Ii='Iilli:BAAANQADCgYIBgAAAA==.',
In='Inari:BAAANQAECgMIAwAAAA==.Inkkubus:BAACNQAFFH8XAAQYAAcK1Q8xBgCQAAAhAAQKlw7rJwDIAAAYAAIKNxIxBgCQAAASAAIKdxKZCQBaAAA1AAQKf00ABCEACgqFIR1BAI8CACEACQp8IB1BAI8CABIABgqwF00LAHcBABgAAwqvEhwZAI0AAAAA.',
Ir='Ironfur:BAAANQAECgYIBQABNQAFFAYIEAACAMQQAA==.',
Je='Jeffpwnros:BAAANQAECgQIBgAAAA==.',
Jh='Jhohn:BAAANQAECgQICAAAAA==.',
Ji='Jintan:BAAANQAECgQIBwAAAA==.',
Ju='Judgmentjudy:BAACNQAFFH8QAAICAAYKxBCTDACVAQACAAYKxBCTDACVAQA1AAQKf6YABAIACgoII1kFAMEDAAIACgoII1kFAMEDAA0AAgrWA0taAD8AAAMAAQqDAGrlAQoAAAAA.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAABNQAECn83AAIFAAoKzAt5DQChAQAFAAoKzAt5DQChAQAAAA==.Kandikkiss:BAAANQAECgEIAQAAAA==.Kariatyda:BAABNQAECn8tAAIMAAoKqBS3ZADjAQAMAAoKqBS3ZADjAQAAAA==.Kasaí:BAABNQAECn8VAAIHAAYKMQ6DpQBJAQAHAAYKMQ6DpQBJAQAAAA==.Kassandra:BAAANQADCggICAAAAA==.',
Ke='Kekio:BAAANQAECgQICAAAAA==.',
Ki='Kiloton:BAABNQAECn8yAAIUAAoKvBLFGACrAQAUAAoKvBLFGACrAQAAAA==.Kinari:BAAANQAECgQIBgABNQAECgYIDgAQAAAAAA==.Kitzy:BAAANQAECgUICQAAAA==.',
Kl='Klippertdk:BAABNQAECn9CAAIEAAoKDRUHGQAOAgAEAAoKDRUHGQAOAgAAAA==.Klutz:BAABNQAECn8lAAIeAAkK0hMOJgDyAQAeAAkK0hMOJgDyAQAAAA==.',
Kn='Kniwt:BAAANQABCgQIBAABNQAECgoKMwACAM4QAA==.',
Ku='Kurzo:BAABNQAECn8bAAIXAAgKTxosfQAiAgAXAAgKTxosfQAiAgABNQAFFAQICQAjAH4MAA==.',
Ky='Kylarian:BAAANQAECgEIAQAAAA==.Kyntara:BAAANQAECgQIBgAAAA==.Kyronian:BAAANQAECgYIEAAAAA==.',
La='Lachancea:BAABNQAECn8nAAIGAAoKaRf4MgA8AgAGAAoKaRf4MgA8AgABNQAECgoKPQAhAKEeAA==.Laeleirri:BAAANQAECggIDQAAAA==.Lakshmee:BAABNQAECn8WAAIGAAcKwgW8rgASAQAGAAcKwgW8rgASAQAAAA==.Landwar:BAAANQADCgYIBgAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAABNQAECn8fAAIMAAoK3gMO7wAjAQAMAAoK3gMO7wAjAQAAAA==.Leonah:BAAANQAECgQIBAABNQAECgUIDQAQAAAAAA==.Lexxi:BAAANQAECgMIBQAAAA==.',
Lh='Lhuru:BAAANQADCggIHQABNQAECgoKNQAFAEAYAA==.',
Li='Lightbehunt:BAAANQAECgYIDgAAAA==.Lightdeborah:BAAANQADCgcIDgAAAA==.Lilly:BAAANQADCgYIBgAAAA==.Linestra:BAACNQAFFH8JAAIjAAQKfgxAAwCRAAAjAAQKfgxAAwCRAAA1AAQKfxwAAyMACgohFq4HAPMBACMACgohFq4HAPMBABYAAQoAAMuTAAAAAAAA.Livaless:BAAANQAECgMIAwABNQAECgoKKQAhAEIhAA==.',
Lo='Lorstus:BAAANQABCgYIBgAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAFFAUIBQACANgJAA==.Lux:BAAANQAECgEIAQAAAA==.',
Ly='Lyceum:BAAANQAECgMIAwABNQAECgoKMwACAM4QAA==.',
Ma='Mahidevran:BAAANQADCggIAgABNQAECgUIDQAQAAAAAA==.Maitotoxin:BAAANQADCggIEgAAAA==.Majikarp:BAAANQAECgUIBQAAAA==.Mal:BAAANQADCggIFAABNQAECggIGwACABQcAA==.Malthaius:BAAANQADCgUIBQAAAA==.Marble:BAAANQADCgYIBgABNQAECgYIBwAQAAAAAA==.Mardoc:BAAANQAECgYIBwAAAA==.Mastablasta:BAAANQAECgQICgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAABNQAECn8aAAIeAAoKBgxrMwB/AQAeAAoKBgxrMwB/AQAAAA==.Mawks:BAABNQAECn9JAAMkAAoKESDNAgD9AgAkAAoKLB3NAgD9AgAMAAYKzB3SdwCyAQAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.',
Mi='Migzeviltwin:BAAANQAECgMIBAAAAA==.Milk:BAAANQAECgEIAQAAAA==.Miza:BAAANQAECgIIAgAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwAQAAAAAA==.Monkent:BAAANQAECggIDQAAAA==.Monkeydluffy:BAAANQAECgMIAwABNQAFFAgIGQAWAFgVAA==.Monstabull:BAAANQADCgUIBQAAAA==.Moomoomonkey:BAAANQADCgUIBQAAAA==.Morhgana:BAAANQADCgIIAgAAAA==.',
Na='Nallaa:BAAANQAECgYIDgAAAA==.Naranak:BAABNQAECn8uAAINAAoK8A1MHAB4AQANAAoK8A1MHAB4AQAAAA==.',
Ne='Neremian:BAAANQADCgQIBAAAAA==.',
No='Noodles:BAAANQAECgQIBAABNQAECgYIFAADAHUVAA==.',
Ny='Nymara:BAABNQAECn8hAAINAAgKQxDjKwB+AQANAAgKQxDjKwB+AQAAAA==.',
['Nü']='Nüguns:BAAANQAECgUIBgAAAA==.',
Ob='Obolus:BAAANQADCgEIAQAAAA==.',
Oc='Occan:BAAANQADCgMIAwAAAA==.',
Ol='Oldenglish:BAABNQAECn8mAAIDAAkKPAdZzQCBAQADAAkKPAdZzQCBAQAAAA==.',
On='Ontos:BAABNQAECn8+AAMeAAoKOBf9EACeAgAeAAoKOBf9EACeAgAcAAYK/A3nUQDFAAABNQAECgoKWQAdAAQgAA==.',
Or='Orrok:BAAANQADCgEIAQAAAA==.',
Os='Osita:BAAANQAECgIIAgAAAA==.',
Pa='Painnkiller:BAABNQAECn9BAAIMAAoK/RXvRwAtAgAMAAoK/RXvRwAtAgAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAABNQAECn8pAAISAAkKFB/CAwBfAgASAAkKFB/CAwBfAgABNQAECgoKKwAIADMYAA==.',
Pe='Perriwinkle:BAABNQAECn83AAMbAAoK8xljCQA1AgAbAAoK8xljCQA1AgAeAAQKDQ6USwC4AAAAAA==.',
Ph='Phylloxeras:BAABNQAECn9FAAMEAAoKdiVHAwBHAwAEAAoKdiVHAwBHAwAZAAEKAAAurAA2AAAAAA==.',
Po='Popecannoli:BAAANQAECgQICAABNQAECgoKMgADALcfAA==.Powders:BAAANQAECgQICQAAAA==.',
Pr='Priopopo:BAAANQABCgIIBAAAAA==.Prophecyrose:BAAANQADCgQIBQAAAA==.Proshot:BAABNQAECn8oAAIkAAkKihgVBQADAgAkAAkKihgVBQADAgAAAA==.',
Pu='Puddles:BAAANQAECgEIAQAAAA==.',
Py='Pyrasi:BAABNQAECn8iAAIMAAgKHROJaQBBAgAMAAgKHROJaQBBAgAAAA==.',
Ra='Raccoon:BAABNQAECn8nAAMhAAoKbAl6hgA8AQAhAAkK8wl6hgA8AQASAAMKAAilIwBQAAAAAA==.Ralor:BAAANQADCgQIBAAAAA==.Razza:BAAANQADCggIEgAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgcICAABNQAECgoKKAAWAH0fAA==.',
Ro='Roa:BAAANQADCggIFQAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAACNQAFFH8ZAAMWAAgKWBUeBwDNAQAWAAgKWBUeBwDNAQAlAAIKMRHiEQCAAAA1AAQKfzwAAxYACgqhIoQOALECABYACQpAI4QOALECACUACQo0G1MfAFQCAAAA.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECggICQAAAA==.',
Sa='Saffron:BAAANQAECgMIAwABNQAECgoKKwAIADMYAA==.Samidrac:BAAANQAECgQIEQAAAA==.Sammidormu:BAABNQAECn8XAAILAAYKaw6fFwCvAAALAAYKaw6fFwCvAAAAAA==.Saphiragosa:BAAANQAECgMIAwAAAA==.Saräha:BAAANQADCggJCwAAAA==.Satoriel:BAAANQADCgEIAQABNQAECgYIBgAQAAAAAA==.Satoshie:BAAANQAECgYIBgAAAA==.Satòshí:BAAANQADCgQICgABNQAECgYIBgAQAAAAAA==.Sayang:BAAANQADCgMIAwABNQAECgkJGgAeAJchAA==.',
Sc='Scerevisiae:BAABNQAECn89AAMhAAoKoR6ZEwDNAgAhAAoKoR6ZEwDNAgAYAAEKgBVTbwBAAAAAAA==.',
Se='Sedelis:BAAANQAECgUIDgAAAA==.Selaya:BAAANQAECgQIBwAAAA==.Serafín:BAABNQAECn9OAAIIAAoKbRGGCAC5AQAIAAoKbRGGCAC5AQAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQAECgIIAQAAAA==.Shadownutt:BAAANQAECgQIDAAAAA==.Sharur:BAABNQAECn8dAAIMAAkKtxM/WwD7AQAMAAkKtxM/WwD7AQAAAA==.Shazzam:BAAANQAECggIBwAAAA==.Shieldwall:BAAANQAECgIIAwAAAA==.',
Si='Signir:BAABNQAECn8WAAIMAAoKzgHE+wCgAAAMAAoKzgHE+wCgAAAAAA==.Silanah:BAAANQAECgUICgABNQAECgoKPwAGAC0fAA==.Silveroaks:BAAANQADCgQIBAABNQAECggIDQAQAAAAAA==.',
So='Somavra:BAAANQAECggIDQAAAA==.Sopidia:BAAANQAECgYIDwAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAABNQAECn8eAAMdAAgKzxT5aADkAQAdAAgKzxT5aADkAQAfAAEK8hBMKQAxAAAAAA==.Spiritomb:BAAANQAECgYICQAAAA==.Spúdd:BAABNQAECn9DAAIXAAoKdxyZKACSAgAXAAoKdxyZKACSAgAAAA==.',
St='Stamavan:BAABNQAECn8gAAIUAAoKnhu0CgDEAgAUAAoKnhu0CgDEAgAAAA==.Starflayer:BAAANQAECggIDgABNQAFFAcIEAABAG0OAA==.Strykerius:BAAANQAECgEIAQABNQAECgUICgAQAAAAAA==.',
Su='Sunari:BAAANQADCgcIBwAAAA==.Supermelon:BAABNQAECn8VAAIgAAcKpRRHPQDaAQAgAAcKpRRHPQDaAQAAAA==.',
Sy='Syena:BAAANQADCgIIAgAAAA==.Sylvanaria:BAABNQAECn9AAAIGAAoK2B72GgDLAgAGAAoK2B72GgDLAgAAAA==.Systyx:BAAANQADCgUICQABNQAECgQIBgAQAAAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.Tarot:BAAANQAECggIBwAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAABNQAECn9FAAIEAAoKBSM6CADpAgAEAAoKBSM6CADpAgAAAA==.',
Th='Thalaresh:BAABNQAECn8rAAIhAAkKnAnecwBqAQAhAAkKnAnecwBqAQAAAA==.Thaneer:BAAANQADCgQICgAAAA==.Throstmok:BAACNQAFFH8JAAIRAAQKYRNBFAC5AAARAAQKYRNBFAC5AAA1AAQKfyYAAhEACgpoHI0TAGgCABEACgpoHI0TAGgCAAAA.Thumbalina:BAAANQADCgYIBgABNQAECgoKJwACAPsSAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tideus:BAAANQADCgcIBwAAAA==.Tilingo:BAAANQAECgUIBgAAAA==.',
To='Tongra:BAAANQADCggIJAABNQAECgoKNQAFAEAYAA==.Torg:BAABNQAECn8VAAIRAAgKew1oXgB4AQARAAgKew1oXgB4AQAAAA==.Torgin:BAAANQAECgUIDAAAAA==.',
Tu='Turgies:BAABNQAECn8yAAMBAAoKBBQ0UQAOAgABAAoKBBQ0UQAOAgAFAAIKqQ6AMwBtAAAAAA==.Turgroka:BAAANQAECgcIDgAAAA==.',
['Tí']='Tíffanny:BAAANQAECgQIBQAAAA==.',
Ub='Ubaubadead:BAAANQAECgUIDAAAAA==.Ubaubajuana:BAABNQAECn9HAAIGAAoKmB9cCQB3AwAGAAoKmB9cCQB3AwAAAA==.',
Ul='Ulfast:BAABNQAECn88AAIHAAoKvhqXKgAhAgAHAAoKvhqXKgAhAgAAAA==.',
Va='Vannhellsing:BAABNQAECn83AAMZAAoK+AZVUAA8AQAEAAgKrga2dABFAQAZAAoKJQVVUAA8AQAAAA==.Vanyel:BAABNQAECn9QAAIFAAoK4RaDCAAQAgAFAAoK4RaDCAAQAgAAAA==.Vardant:BAAANQADCgMIAwABNQAECgYIBgAQAAAAAA==.',
Ve='Veliena:BAAANQADCgYIBgABNQAECgUIFQAMADwJAA==.Vemal:BAABNQAECn8/AAIMAAoKGhFEcwAqAgAMAAoKGhFEcwAqAgAAAA==.',
Vi='Vidula:BAAANQADCgcICAAAAA==.Vigorous:BAABNQAECn8hAAIPAAgK6wmJIgA1AQAPAAgK6wmJIgA1AQAAAA==.',
Vo='Vociferoy:BAABNQAECn9JAAMMAAoKtxsiMgBtAgAMAAoKtxsiMgBtAgATAAEKpAHicAAlAAAAAA==.Voidsteffan:BAABNQAECn8qAAIYAAgKWhAiCAA4AQAYAAgKWhAiCAA4AQAAAA==.Vosina:BAAANQAECgUIBQAAAA==.',
Vv='Vv:BAACNQAFFH8wAAMlAAkKYCMIAAB3AwAlAAgKWyYIAAB3AwAWAAYKlRfTCgB2AQA1AAQKf0cAAxYACgrDJlQBAHoDACUACQq5JnYFAHsDABYACgo5JlQBAHoDAAAA.',
Wa='Waterworks:BAAANQAECgcICQABNQAECgoKMwACAM4QAA==.',
Wi='Willowmoon:BAAANQAECgcIDQAAAA==.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAFFAgIGQAcAFMUAA==.',
['Wá']='Wárranpeace:BAAANQADCgIIAgAAAA==.',
Xa='Xalmo:BAAANQADCgQIBAABNQAECggIJAAJABAVAA==.Xalzi:BAAANQAECgQIBgABNQAECgYIBwAQAAAAAA==.',
Xu='Xul:BAAANQABCggICgAAAA==.',
Xy='Xyphër:BAAANQADCgQIBAABNQAECgUICgAQAAAAAA==.',
Yo='Yotie:BAAANQADCgMIBQAAAA==.',
Za='Zalknight:BAAANQADCggICAABNQAECggIJAAJABAVAA==.Zannytoes:BAABNQAECn8cAAMmAAoKuQxiMQCNAQAmAAoKuQxiMQCNAQAaAAcKSAzELAAGAQAAAA==.',
Zi='Zie:BAABNQAECn9CAAIOAAoKwxIAFQD5AQAOAAoKwxIAFQD5AQAAAA==.',
Zn='Zneon:BAAANQAECgIIAgAAAA==.',
['Ñi']='Ñice:BAACNQAFFH8HAAMiAAQKaRyUAQAYAQAiAAMKqxuUAQAYAQAXAAEK5R0XOgBQAAA1AAQKfzUAAyIACQoXJVYFANACABcACAqhJFMpABUDACIACArjIFYFANACAAAA.',
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
