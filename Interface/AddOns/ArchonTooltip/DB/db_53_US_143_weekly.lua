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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Warlock-Affliction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warrior-Protection','Unknown-Unknown','DeathKnight-Blood','Hunter-Marksmanship','Druid-Guardian','Shaman-Enhancement','DemonHunter-Havoc','Warrior-Arms','Warlock-Destruction','DeathKnight-Frost','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Holy','Druid-Restoration','Priest-Discipline','Rogue-Assassination','Warlock-Demonology','Warrior-Fury','DemonHunter-Vengeance','Hunter-Survival','DemonHunter-Devourer','Monk-Windwalker',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abukuma:BAAANQAECgUIBgAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAFFAcIEAABAG0OAA==.',
Ae='Aenstalash:BAABNQAECn9AAAMCAAoKHyBJEgAqAwACAAoKHyBJEgAqAwADAAcKEQw3FgHIAAAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAABNQAECn8rAAIEAAoKOREvUADTAQAEAAoKOREvUADTAQAAAA==.',
Al='Aleeah:BAAANQABCgIIAgAAAA==.Alfonsoo:BAAANQAECgEIAQAAAA==.Alistur:BAABNQAECn8aAAMFAAcKEgPZLwBtAAABAAcK1QGLcwHXAAAFAAUKTwTZLwBtAAAAAA==.',
Am='Ameena:BAABNQAECn8pAAMGAAoKPhYxTwAoAgAGAAoKPhYxTwAoAgAHAAEKGwhUAQEzAAAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Anamura:BAAANQADCgMIAwAAAA==.Angus:BAAANQAECgUIDAAAAA==.',
Ar='Arcomedes:BAAANQAECgYICAAAAA==.Arthrasz:BAABNQAECn8ZAAIDAAoKgxOmmQDwAQADAAoKgxOmmQDwAQAAAA==.Arthraz:BAABNQAECn8rAAIIAAoKMxjSDgAGAgAIAAoKMxjSDgAGAgABNQAECgoKLAAJANgeAA==.',
As='Asondralyn:BAAANQABCgUIBgAAAA==.Astara:BAACNQAFFH8JAAIKAAUKWQZjCADsAAAKAAUKWQZjCADsAAA1AAQKfysAAgoACgqeE+oGAEgCAAoACgqeE+oGAEgCAAAA.Astrex:BAABNQAECn8vAAQLAAcKgxnjEAD4AQALAAcKgxnjEAD4AQAMAAEKAgKWQwAgAAAKAAEKYAJMIAAeAAAAAA==.',
Au='Aurali:BAAANQAECgUIEAAAAA==.Aureliá:BAABNQAECn8lAAINAAcKugjj5wAxAQANAAcKugjj5wAxAQAAAA==.',
Ay='Ayixi:BAAANQAECgYIBwAAAA==.',
Az='Azureth:BAAANQAECgcIBwAAAA==.',
['Aü']='Aütobot:BAAANQAECgUICQAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQAECgQIBgABNQAECgoKQAAOAO0eAA==.',
Be='Bega:BAAANQAECgIIAgABNQAFFAQIBwAPAIIEAA==.',
Bl='Bloodlustplz:BAABNQAECn8oAAIQAAkKYA/rGgCJAQAQAAkKYA/rGgCJAQAAAA==.',
Bo='Bobster:BAABNQAECn8gAAIBAAoKbxJRuwANAgABAAoKbxJRuwANAgAAAA==.Bonepaw:BAAANQADCgUICAABNQAECgYIBwARAAAAAA==.Booyea:BAABNQAECn9IAAISAAoKnRiNGQA3AgASAAoKnRiNGQA3AgAAAA==.',
Br='Brew:BAAANQABCgIIAgAAAA==.Brewwnor:BAABNQAECn8YAAINAAkKbBO0iwCgAQANAAkKbBO0iwCgAQAAAA==.Brewwnôr:BAAANQADCgEIAQAAAA==.Brewwtus:BAAANQADCgMIAwAAAA==.Brisfloggnaw:BAAANQADCgcIBwAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.Bubbleplop:BAAANQAECgYICwABNQAECggIHgAJADwWAA==.',
Ca='Calamuelis:BAACNQAFFH8SAAMNAAkKshe+BAANAgANAAYKYxm+BAANAgATAAQKcBUvFgChAAA1AAQKfzgAAw0ACgosJmkOAG4DAA0ACgr6JWkOAG4DABMACAqfJNsIALQCAAAA.Caliope:BAAANQAECgUIDQAAAA==.Carnage:BAAANQAECggIAgAAAA==.Cathbad:BAABNQAECn9GAAIUAAoKWBY4FAD5AQAUAAoKWBY4FAD5AQAAAA==.Cazlek:BAAANQADCggIIAAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECgoKLAAJANgeAA==.Cerelus:BAABNQAECn89AAIFAAoKQBh5BwBGAgAFAAoKQBh5BwBGAgAAAA==.',
Ch='Chaac:BAABNQAECn8vAAIVAAoKax93CQCJAgAVAAoKax93CQCJAgAAAA==.Chediah:BAAANQAECgQIDwAAAA==.Cheesûs:BAAANQAECgUICwAAAA==.Chéwtoy:BAABNQAECn8cAAIWAAoKmQprMQCNAQAWAAoKmQprMQCNAQAAAA==.',
Ci='Cilantro:BAAANQAECgQIBAABNQAECgoKLAAJANgeAA==.',
Co='Cowmus:BAABNQAECn8hAAMCAAoK3RePTADhAQACAAoK3RePTADhAQADAAcK2Amy6wBFAQABNQAECgoKPwAGAC0fAA==.',
['Cã']='Cãrloy:BAABNQAECn+VAAIXAAoKNCAFIwAsAwAXAAoKNCAFIwAsAwAAAA==.',
Da='Daedalas:BAABNQAECn8nAAIPAAoKaBhiGgDJAQAPAAoKaBhiGgDJAQAAAA==.Daenari:BAAANQADCgYIBgAAAA==.Darkxsoul:BAABNQAECn9AAAIOAAoK7R7kBwDMAgAOAAoK7R7kBwDMAgAAAA==.Darthgrogu:BAABNQAECn8WAAIYAAgKegZ+JQBIAQAYAAgKegZ+JQBIAQABNQAFFAcIDQADAEEKAA==.Darthknull:BAACNQAFFH8NAAIDAAcKQQqUDwBTAQADAAcKQQqUDwBTAQA1AAQKfzEAAgMACgrwHvtEAFsCAAMACgrwHvtEAFsCAAAA.Darthputska:BAAANQAECggIDgABNQAFFAcIDQADAEEKAA==.Darthreven:BAABNQAECn8ZAAIBAAcKDwVZ7ADWAAABAAcKDwVZ7ADWAAABNQAFFAcIDQADAEEKAA==.Darthtalon:BAABNQAECn8ZAAIZAAoKNAnqRQCpAQAZAAoKNAnqRQCpAQABNQAFFAcIDQADAEEKAA==.Dayla:BAAANQADCgMIAwAAAA==.',
De='Deathshocks:BAAANQADCgMIAwABNQAECgkJJwAQABsXAA==.Deathwood:BAABNQAECn8nAAIQAAkKGxdmCgAoAgAQAAkKGxdmCgAoAgAAAA==.Deatthdecay:BAAANQAECggIAQAAAA==.Degloved:BAEANQAECgQIBgABNQAECgoKNgAGABwcAA==.Deitrichx:BAAANQAECgMIAwAAAA==.Deminestrea:BAAANQADCgcICAAAAA==.Demonslayere:BAAANQAECggIEAABNQAFFAgIHAAaADUgAA==.',
Di='Discodeitx:BAAANQADCgIIAgAAAA==.Disshammy:BAAANQAECgIIAwABNQAECggIDAARAAAAAA==.Divinedebra:BAAANQADCggICAAAAA==.',
Do='Donkform:BAAANQAECgIIAgABNQAECgYIDwARAAAAAA==.Donkulle:BAAANQAECgYIDwAAAA==.',
Dr='Draconith:BAABNQAECn9FAAILAAoK4x1ABABSAwALAAoK4x1ABABSAwAAAA==.Dragorlian:BAAANQADCgMIAwAAAA==.Draqkmar:BAAANQADCgcICAAAAA==.',
Du='Dunsparrow:BAABNQAECn8/AAIGAAoKLR9LIgDeAgAGAAoKLR9LIgDeAgAAAA==.Durgruk:BAAANQAECgUIBQABNQAECgoKRQALAOMdAA==.Durzul:BAAANQADCgcICwAAAA==.',
Ei='Eindraken:BAABNQAECn9HAAMLAAoK+xOwEAD8AQALAAoK+xOwEAD8AQAMAAIKrQUbJwAvAAAAAA==.Eisis:BAABNQAECn89AAIbAAoK7xNbDgDlAQAbAAoK7xNbDgDlAQAAAA==.',
El='Elanalué:BAAANQADCggIGAABNQAECgUIDQARAAAAAA==.',
Em='Empoleonn:BAABNQAECn8VAAIPAAgK7w5NJgD8AQAPAAgK7w5NJgD8AQAAAA==.',
En='Engos:BAAANQADCgYIBwAAAA==.',
Ep='Epsolone:BAAANQABCgMIAwAAAA==.',
Er='Erroz:BAAANQADCggIEwAAAA==.Erukani:BAABNQAECn8UAAIcAAcKPAhEXgBXAQAcAAcKPAhEXgBXAQAAAA==.',
Es='Espriesso:BAABNQAECn8/AAMdAAoK8RQtLQCSAgAdAAoK8RQtLQCSAgAPAAIK0AOkaAAsAAABNQAECgoKPQACAGkXAA==.',
Ex='Exemplar:BAAANQAECgcIEQAAAA==.',
Fe='Fearwatermac:BAAANQAECgYIDQAAAA==.Feider:BAAANQABCgQJBwAAAA==.Felais:BAACNQAFFH8KAAIeAAUKTRhWBwB7AQAeAAUKTRhWBwB7AQA1AAQKfzEAAh4ACgpLGskdAEICAB4ACgpLGskdAEICAAAA.Felin:BAAANQABCggIKgAAAA==.Femmefatale:BAACNQAFFH8GAAIdAAIKkx5gKACjAAAdAAIKkx5gKACjAAA1AAQKf2EABB0ACgoEIJkQAFUDAB0ACgoEIJkQAFUDAA8ABwqLDlo1AHkBAB8ABgouCokRAA8BAAAA.',
Fl='Flamecube:BAAANQADCgMIAwAAAA==.Flashx:BAABNQAECn8uAAICAAoKQyHYCACSAwACAAoKQyHYCACSAwAAAA==.Flass:BAAANQADCggIDgAAAA==.',
Fr='Freerin:BAAANQADCgcICAAAAA==.Frevpl:BAAANQAECgIIAgAAAA==.Frofrohunter:BAAANQAECgYIEgAAAA==.Froggie:BAAANQAECgYIBwAAAA==.Frostme:BAAANQAECgIIAQAAAA==.',
Fu='Fuzywuuzy:BAAANQAECgYIBwAAAA==.',
Ga='Gattsu:BAAANQAECgYICQABNQAECgoKMwACAM4QAA==.Gazdorn:BAABNQAECn8WAAIQAAcKZgzeHgBcAQAQAAcKZgzeHgBcAQAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgcIEAAAAA==.',
Ge='Genghis:BAAANQADCgQICAAAAA==.',
Gh='Ghost:BAABNQAECn8xAAIgAAoK8xz3CgAmAgAgAAoK8xz3CgAmAgAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAABNQAECn8nAAIHAAkKThekTgCdAQAHAAkKThekTgCdAQAAAA==.Gimmighoul:BAAANQAECgMIAwAAAA==.',
Gl='Glissa:BAABNQAECn8kAAQYAAoKMhwAHQCGAQAhAAcKrBnjgADkAQAYAAQKrCEAHQCGAQAJAAUKfhaBDgBqAQAAAA==.Gloomidge:BAABNQAECn8kAAIDAAkK4wcyrAB3AQADAAkK4wcyrAB3AQAAAA==.',
Go='Gorditt:BAAANQAECgIIAgAAAA==.',
Gr='Graphene:BAAANQAECgQIBAABNQAECgoKMwACAM4QAA==.',
Gt='Gt:BAABNQAECn8zAAMCAAoKzhCAaQDbAQACAAkKMxKAaQDbAQAOAAcKQAu+OAAmAQAAAA==.',
Ha='Habanero:BAAANQAECgcIDAABNQAECgoKLAAJANgeAA==.Hadense:BAAANQADCggICAABNQAFFAYIFgAHAK8bAA==.Hadory:BAABNQAECn8dAAMCAAoKDRgnVQAaAgACAAoKDRgnVQAaAgADAAUKGwcRQwGLAAAAAA==.',
He='Hellzzdemon:BAAANQAECggIEAAAAA==.Hercow:BAAANQAECgUIEwAAAA==.Herrvoller:BAAANQADCgUIBgAAAA==.Hexinverter:BAAANQADCggIEgAAAA==.',
Ho='Holycannoli:BAABNQAECn83AAIDAAoKOyA6KQC9AgADAAoKOyA6KQC9AgAAAA==.Holydeborah:BAAANQADCgUIBQAAAA==.Horiffic:BAABNQAECn8lAAIiAAoKTyBhBACvAgAiAAoKTyBhBACvAgAAAA==.Horok:BAAANQAECgQIBAAAAA==.Hotfuzz:BAABNQAECn8pAAIBAAoKXh2tOgBeAgABAAoKXh2tOgBeAgAAAA==.Hotsforthots:BAABNQAECn84AAIdAAoKzRvjJgC1AgAdAAoKzRvjJgC1AgAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.Hurricaneg:BAAANQADCgMIAwAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ic='Ichaerus:BAAANQAECgIIAgABNQAECgoKJwAPAGgYAA==.',
Ii='Iilli:BAAANQADCgYIBgAAAA==.',
In='Inari:BAAANQAECgMIAwAAAA==.Inkkubus:BAACNQAFFH8XAAQYAAcK1Q/iBgCOAAAhAAQKlw7rJwDIAAAYAAIKNxLiBgCOAAAJAAIKdxKZCQBaAAA1AAQKf1QABAkACgqrIUMDAIgCACEACQp8IB1BAI8CAAkACQpqGkMDAIgCABgAAwqvEvwaAIwAAAAA.',
Ir='Ironfur:BAAANQAECgYIBQABNQAFFAYIEAACAMQQAA==.',
Je='Jeffpwnros:BAAANQAECgQIBgAAAA==.',
Jh='Jhohn:BAAANQAECgQICAAAAA==.',
Ji='Jintan:BAAANQAECgQIBwAAAA==.',
Ju='Judgmentjudy:BAACNQAFFH8QAAICAAYKxBCTDACVAQACAAYKxBCTDACVAQA1AAQKf8cABAIACgrHI08EAN0DAAIACgrHI08EAN0DAA4AAgrWA2pfAD8AAAMAAQqDAGrlAQoAAAAA.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAABNQAECn89AAIFAAoKzAvfDgCkAQAFAAoKzAvfDgCkAQAAAA==.Kandikkiss:BAAANQAECgIIAwAAAA==.Kariatyda:BAABNQAECn8tAAINAAoKqBR5bAA6AgANAAoKqBR5bAA6AgAAAA==.Kasaí:BAABNQAECn8cAAIHAAcKWQ2ThQADAQAHAAcKWQ2ThQADAQAAAA==.Kassandra:BAAANQADCggICAAAAA==.',
Ke='Kekio:BAAANQAECgQICAAAAA==.',
Ki='Kiloton:BAABNQAECn84AAIUAAoKgxO0GQC5AQAUAAoKgxO0GQC5AQAAAA==.Kinari:BAAANQAECgQIBgABNQAECgcIDwARAAAAAA==.Kitzy:BAAANQAECgUICQAAAA==.',
Kl='Klippertdk:BAABNQAECn9LAAIEAAoKPBdJFQBGAgAEAAoKPBdJFQBGAgAAAA==.Klutz:BAABNQAECn8lAAIeAAkK0hMOJgDyAQAeAAkK0hMOJgDyAQAAAA==.',
Kn='Kniwt:BAAANQABCgQIBAABNQAECgoKMwACAM4QAA==.',
Ku='Kurzo:BAABNQAECn8bAAIXAAgKTxosfQAiAgAXAAgKTxosfQAiAgABNQAFFAUICgAjAA4NAA==.',
Ky='Kylarian:BAAANQAECgEIAQAAAA==.Kyntara:BAAANQAECgQIBgAAAA==.Kyronian:BAAANQAECgYIEAAAAA==.',
La='Lachancea:BAABNQAECn8nAAIGAAoKaRfNOAA1AgAGAAoKaRfNOAA1AgABNQAECgoKPQAhAKEeAA==.Laeleirri:BAAANQAECggIDQAAAA==.Lakshmee:BAABNQAECn8WAAIGAAcKwgW8rgASAQAGAAcKwgW8rgASAQAAAA==.Landwar:BAAANQADCgYIBgAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAABNQAECn8fAAINAAoK3gMO7wAjAQANAAoK3gMO7wAjAQAAAA==.Leonah:BAAANQAECgQIBAABNQAECgUIDQARAAAAAA==.Lexxi:BAAANQAECgMIBQAAAA==.',
Lh='Lhuru:BAAANQADCggIHAABNQAECgoKPQAFAEAYAA==.',
Li='Lightbehunt:BAAANQAECgYIDgAAAA==.Lightdeborah:BAAANQADCggIEQAAAA==.Lilly:BAAANQADCgYIBgAAAA==.Linestra:BAACNQAFFH8KAAIjAAUKDg1SAgDOAAAjAAUKDg1SAgDOAAA1AAQKfx0AAyMACgqEFj0IAPoBACMACgqEFj0IAPoBABYAAQoAAEmbAAAAAAAA.Livaless:BAAANQAECgMIAwABNQAECgoKKQAhAEIhAA==.',
Lo='Lorstus:BAAANQABCgYIBgAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAFFAUIBQACANgJAA==.Lux:BAAANQAECgEIAQAAAA==.',
Ly='Lyceum:BAAANQAECgMIAwABNQAECgoKMwACAM4QAA==.',
Ma='Mahidevran:BAAANQADCggIAgABNQAECgUIDQARAAAAAA==.Maitotoxin:BAAANQADCggIEgAAAA==.Majikarp:BAAANQAECgUIBQAAAA==.Mal:BAAANQADCggIFAABNQAECggIHwACAI0cAA==.Malthaius:BAAANQADCgUIBQAAAA==.Marble:BAAANQADCgYIBgABNQAECgYIBwARAAAAAA==.Mardoc:BAAANQAECggIDwAAAA==.Mastablasta:BAAANQAECgQICgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAABNQAECn8aAAIeAAoKBgxrMwB/AQAeAAoKBgxrMwB/AQAAAA==.Mawks:BAABNQAECn9LAAMkAAoKESDNAgD9AgAkAAoKmh3NAgD9AgANAAYKzB1dhQCuAQAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.',
Mi='Migzeviltwin:BAAANQAECgMIBAAAAA==.Milk:BAAANQAECgEIAQAAAA==.Miza:BAAANQAECgIIAgAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwARAAAAAA==.Monkent:BAAANQAECggIDQAAAA==.Monkeydluffy:BAAANQAECgMIAwABNQAFFAgIGQAWAFgVAA==.Monstabull:BAAANQADCgUIBQAAAA==.Moomoomonkey:BAAANQADCgUIBQAAAA==.Morhgana:BAAANQADCgIIAgAAAA==.',
Na='Nallaa:BAAANQAECgcIDwAAAA==.Naranak:BAABNQAECn81AAIOAAoKeRBRGQCqAQAOAAoKeRBRGQCqAQAAAA==.',
Ne='Neremian:BAAANQADCgQIBAAAAA==.',
No='Noodles:BAAANQAECgQIBAABNQAECgYIFAADAHUVAA==.',
Ny='Nymara:BAABNQAECn8mAAIOAAkKnw/jKwB+AQAOAAkKnw/jKwB+AQAAAA==.',
['Nü']='Nüguns:BAAANQAECgYICwAAAA==.',
Ob='Obolus:BAAANQADCgEIAQAAAA==.',
Oc='Occan:BAAANQADCgMIAwAAAA==.',
Ol='Oldenglish:BAABNQAECn8mAAIDAAkKPAdZzQCBAQADAAkKPAdZzQCBAQAAAA==.',
On='Ontos:BAABNQAECn8/AAMeAAoKOBfnEgCbAgAeAAoKOBfnEgCbAgAcAAYK/A3RVgDEAAABNQAFFAIIBgAdAJMeAA==.',
Or='Orrok:BAAANQADCgEIAQAAAA==.',
Os='Osita:BAAANQAECgIIAgAAAA==.',
Pa='Painnkiller:BAABNQAECn9JAAINAAoKLhcnRgBGAgANAAoKLhcnRgBGAgAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAABNQAECn8sAAIJAAoK2B6NAgC0AgAJAAoK2B6NAgC0AgAAAA==.',
Pe='Perriwinkle:BAABNQAECn88AAMbAAoK9xp4CQBNAgAbAAoK9xp4CQBNAgAeAAQKDQ7DUAC3AAAAAA==.',
Ph='Phylloxeras:BAABNQAECn9FAAMEAAoKdiXKAwBCAwAEAAoKdiXKAwBCAwAZAAEKAAAurAA2AAAAAA==.',
Po='Popecannoli:BAAANQAECgQICAABNQAECgoKNwADADsgAA==.Powders:BAAANQAECgQICQAAAA==.',
Pr='Priopopo:BAAANQABCgIIBAAAAA==.Prophecyrose:BAAANQADCggIDQAAAA==.Proshot:BAABNQAECn8oAAIkAAkKihiiBQABAgAkAAkKihiiBQABAgAAAA==.',
Pu='Puddles:BAAANQAECgEIAQAAAA==.',
Py='Pyrasi:BAABNQAECn8iAAINAAgKHROJaQBBAgANAAgKHROJaQBBAgAAAA==.',
Ra='Raccoon:BAABNQAECn8vAAMJAAoKBAq7DQBdAQAhAAkKAgomogCRAQAJAAgKhgi7DQBdAQAAAA==.Ralor:BAAANQADCgQIBAAAAA==.Razza:BAAANQADCggIEgAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgcICAABNQAECgoKKAAWAH0fAA==.',
Ro='Roa:BAAANQADCggIFQAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAACNQAFFH8ZAAMWAAgKWBUeBwDNAQAWAAgKWBUeBwDNAQAlAAIKMRHiEQCAAAA1AAQKfzwAAxYACgqhIu8PAK8CABYACQpAI+8PAK8CACUACQo0G1MfAFQCAAAA.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECggICQAAAA==.',
Sa='Saffron:BAAANQAECgMIAwABNQAECgoKLAAJANgeAA==.Samidrac:BAABNQAECn8aAAMLAAUKkQFfNABdAAALAAUKkQFfNABdAAAMAAIKjwBcKQAhAAAAAA==.Sammidormu:BAABNQAECn8XAAIMAAYKaw7lGACuAAAMAAYKaw7lGACuAAAAAA==.Saphiragosa:BAAANQAECgMIAwAAAA==.Saräha:BAAANQADCggJCwAAAA==.Satoshie:BAAANQAECgYIBgAAAA==.Satòshí:BAAANQADCgQICAABNQAECgYIBgARAAAAAA==.Sayang:BAAANQADCgMIAwABNQAECgkJGgAeAJchAA==.',
Sc='Scerevisiae:BAABNQAECn89AAMhAAoKoR6vFgDGAgAhAAoKoR6vFgDGAgAYAAEKgBVTbwBAAAAAAA==.',
Se='Sedelis:BAAANQAECgUIDgAAAA==.Selaya:BAAANQAECgQICwAAAA==.Serafín:BAABNQAECn9WAAIIAAoKZBKVCADMAQAIAAoKZBKVCADMAQAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQAECgIIAQAAAA==.Shadownutt:BAAANQAECgQIDAAAAA==.Sharur:BAABNQAECn8mAAINAAkKfRdsUAAsAgANAAkKfRdsUAAsAgAAAA==.Shazzam:BAAANQAECggIBwAAAA==.Shieldwall:BAAANQAECgIIAwAAAA==.',
Si='Signir:BAABNQAECn8cAAINAAoK3QKW4QDuAAANAAoK3QKW4QDuAAAAAA==.Silanah:BAAANQAECgUICgABNQAECgoKPwAGAC0fAA==.Silveroaks:BAAANQADCgQIBAABNQAECggIDQARAAAAAA==.',
So='Somavra:BAAANQAECggIDgAAAA==.Sopidia:BAAANQAECgYIDwAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAABNQAECn8iAAMdAAkKZBP5aADkAQAdAAkKZBP5aADkAQAfAAEK8hBMKQAxAAAAAA==.Spiritomb:BAAANQAECgYICQAAAA==.Spúdd:BAABNQAECn9DAAIXAAoKdxx3LACNAgAXAAoKdxx3LACNAgAAAA==.',
St='Stamavan:BAABNQAECn8gAAIUAAoKnhu0CgDEAgAUAAoKnhu0CgDEAgAAAA==.Starflayer:BAAANQAECggIDgABNQAFFAcIEAABAG0OAA==.Strykerius:BAAANQAECgEIAQABNQAECgUICgARAAAAAA==.',
Su='Sunari:BAAANQAECgQIBAAAAA==.Supermelon:BAABNQAECn8VAAIgAAcKpRRHPQDaAQAgAAcKpRRHPQDaAQAAAA==.',
Sy='Syena:BAAANQADCgIIAgAAAA==.Sylvanaria:BAABNQAECn9IAAIGAAoK7R/pFAAQAwAGAAoK7R/pFAAQAwAAAA==.Systyx:BAAANQADCgUICQABNQAECgQIBgARAAAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.Tarot:BAAANQAECggIBwAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAABNQAECn9OAAIEAAoKHiTZBQAaAwAEAAoKHiTZBQAaAwAAAA==.',
Th='Thalaresh:BAABNQAECn8yAAIhAAkKrw2waQCbAQAhAAkKrw2waQCbAQAAAA==.Thaneer:BAAANQADCgQICAAAAA==.Throstmok:BAACNQAFFH8KAAISAAUK/xM7EAADAQASAAUK/xM7EAADAQA1AAQKfycAAhIACgrMHGITAHYCABIACgrMHGITAHYCAAAA.Thumbalina:BAAANQADCgYIBgABNQAECgoKJwACAPsSAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tideus:BAAANQADCgcIBwAAAA==.Tilingo:BAAANQAECgUIBgAAAA==.',
To='Tongra:BAAANQADCggIJAABNQAECgoKPQAFAEAYAA==.Torg:BAABNQAECn8VAAISAAgKew1oXgB4AQASAAgKew1oXgB4AQAAAA==.Torgin:BAAANQAECgUIDAAAAA==.',
Tu='Turgies:BAABNQAECn8yAAMBAAoKBBRbVwANAgABAAoKBBRbVwANAgAFAAIKqQ6AMwBtAAAAAA==.Turgroka:BAAANQAECgcIDgAAAA==.',
['Tí']='Tíffanny:BAAANQAECgQIBQAAAA==.',
Ub='Ubaubadead:BAAANQAECgUIDAAAAA==.Ubaubajuana:BAABNQAECn9QAAMGAAoKwx+YCgB2AwAGAAoKwx+YCgB2AwAHAAEKBQOOCgEqAAAAAA==.',
Ul='Ulfast:BAABNQAECn9EAAIHAAoKvhonNgCeAgAHAAoKvhonNgCeAgAAAA==.',
Va='Vannhellsing:BAABNQAECn8/AAMZAAoKTwceTQBjAQAZAAoKlQYeTQBjAQAEAAgKrga2dABFAQAAAA==.Vanyel:BAABNQAECn9QAAIFAAoK4RZXCgAkAgAFAAoK4RZXCgAkAgAAAA==.Vardant:BAAANQADCgUIBgABNQAECgYIBgARAAAAAA==.',
Ve='Veliena:BAAANQADCgYIBgABNQAECgUIFQANADwJAA==.Vemal:BAABNQAECn9GAAINAAoKuxRkRABKAgANAAoKuxRkRABKAgAAAA==.',
Vi='Vidula:BAAANQADCgcICAAAAA==.Vigorous:BAABNQAECn8hAAIQAAgK6wmJIgA1AQAQAAgK6wmJIgA1AQAAAA==.',
Vo='Vociferoy:BAABNQAECn9RAAMNAAoKtxsjNQB0AgANAAoKtxsjNQB0AgATAAEKpAGZdQAlAAAAAA==.Voidsteffan:BAABNQAECn8zAAIYAAkKCBCmBgBzAQAYAAkKCBCmBgBzAQAAAA==.Vosina:BAAANQAECgUIBQAAAA==.',
Vv='Vv:BAACNQAFFH8wAAMlAAkKYCMIAAB3AwAlAAgKWyYIAAB3AwAWAAYKlRfTCgB2AQA1AAQKf0cAAxYACgrDJpIBAHcDACUACQq5JnYFAHsDABYACgo5JpIBAHcDAAAA.',
Wa='Waterworks:BAAANQAECgcICQABNQAECgoKMwACAM4QAA==.',
Wi='Willowmoon:BAAANQAECgcIDQAAAA==.',
Wo='Worgenlina:BAAANQAECgYIBgAAAA==.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAFFAgIGQAcAFMUAA==.',
['Wá']='Wárranpeace:BAAANQADCgIIAgAAAA==.',
Xa='Xalmo:BAAANQADCgQIBAABNQAECggIJAAKABAVAA==.Xalzi:BAAANQAECgQIBgABNQAECgYIBwARAAAAAA==.',
Xu='Xul:BAAANQABCggICgAAAA==.',
Xy='Xyphër:BAAANQADCgQIBAABNQAECgUICgARAAAAAA==.',
Yo='Yotie:BAAANQADCgMIBAAAAA==.',
Za='Zalknight:BAAANQADCggICAABNQAECggIJAAKABAVAA==.Zannytoes:BAABNQAECn8cAAMmAAoKuQxiMQCNAQAmAAoKuQxiMQCNAQAaAAcKSAzELAAGAQAAAA==.',
Zi='Zie:BAABNQAECn9KAAIPAAoKwxJAFgD+AQAPAAoKwxJAFgD+AQAAAA==.',
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
