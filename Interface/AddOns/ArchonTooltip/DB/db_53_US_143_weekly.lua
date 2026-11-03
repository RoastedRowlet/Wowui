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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warrior-Protection','Unknown-Unknown','DeathKnight-Blood','Warrior-Arms','Hunter-Marksmanship','Druid-Guardian','Shaman-Enhancement','DeathKnight-Frost','Monk-Mistweaver','Druid-Feral','Druid-Balance','Priest-Holy','Druid-Restoration','Priest-Discipline','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-Survival','DemonHunter-Devourer','Monk-Windwalker',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abukuma:BAAANQAECgUIBgAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAFFAYIDgABAJYPAA==.',
Ae='Aenstalash:BAABNQAECn8wAAMCAAoK+B/iIwB2AgACAAkKNx/iIwB2AgADAAcKEQyF7ADMAAAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAABNQAECn8rAAIEAAoKOREvUADTAQAEAAoKOREvUADTAQAAAA==.',
Al='Aleeah:BAAANQAECgEIAQAAAA==.Alfonsoo:BAAANQAECgEIAQAAAA==.Alistur:BAABNQAECn8aAAMFAAcKEgPMJwBuAAABAAcK1QGLcwHXAAAFAAUKTwTMJwBuAAAAAA==.',
Am='Ameena:BAABNQAECn8pAAMGAAoKPhYxTwAoAgAGAAoKPhYxTwAoAgAHAAEKGwhk5AAzAAAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Anamura:BAAANQADCgMIBAAAAA==.Angnir:BAAANQADCgEIAQAAAA==.Angus:BAAANQAECgUIDgAAAA==.',
Ar='Arcomedes:BAAANQAECgYICwAAAA==.Arthrasz:BAABNQAECn8ZAAIDAAoKgxOmmQDwAQADAAoKgxOmmQDwAQAAAA==.Arthraz:BAABNQAECn8oAAIIAAoKrRfSDgAGAgAIAAoKrRfSDgAGAgAAAA==.',
As='Asondralyn:BAAANQADCgEIAQAAAA==.Astara:BAABNQAECn8qAAIJAAoKcxPqBgBIAgAJAAoKcxPqBgBIAgAAAA==.Astrex:BAABNQAECn8sAAMKAAcKgxm7DQD7AQAKAAcKgxm7DQD7AQALAAEKAgKWQwAgAAAAAA==.',
Au='Aurali:BAAANQAECgUIEQAAAA==.Aureliá:BAABNQAECn8gAAIMAAYKtgfj5wAxAQAMAAYKtgfj5wAxAQAAAA==.',
Ay='Ayixi:BAAANQAECgYIBwAAAA==.',
Az='Azureth:BAAANQAECgcIBwAAAA==.',
['Aü']='Aütobot:BAAANQAECgUICQAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQAECgQIBgABNQAECgoKMQANAIodAA==.',
Be='Bega:BAAANQAECgIIAgABNQAFFAQIBwAOAIIEAA==.',
Bl='Bloodchiefsr:BAAANQADCgEIAQAAAA==.Bloodlustplz:BAABNQAECn8oAAIPAAkKYA/rGgCJAQAPAAkKYA/rGgCJAQAAAA==.',
Bo='Bobster:BAABNQAECn8gAAIBAAoKbxJRuwANAgABAAoKbxJRuwANAgAAAA==.Bonepaw:BAAANQADCgUICAABNQAECgYICAAQAAAAAA==.Booyea:BAABNQAECn83AAIRAAkKOxanKgCFAQARAAkKOxanKgCFAQAAAA==.',
Br='Brew:BAAANQADCgEIAQAAAA==.Brewwnor:BAAANQAECgYIEQAAAA==.Brewwnôr:BAAANQADCgEIAQAAAA==.Brewwtus:BAAANQADCgMIAwAAAA==.Brisfloggnaw:BAAANQADCgcIBwAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.Bubbleplop:BAAANQAECgYICwABNQAECgoKPwASAAwaAA==.',
Ca='Calamuelis:BAACNQAFFH8QAAMMAAgKbBq+BAANAgAMAAYKYxm+BAANAgATAAMKfxxGFQBZAAA1AAQKfzUAAwwACgoeJmkOAG4DAAwACgr6JWkOAG4DABMACAqPJCgHALkCAAAA.Caliope:BAAANQAECgUICgAAAA==.Carnage:BAAANQAECggIBAAAAA==.Cathbad:BAABNQAECn83AAIUAAoK3BQtGACPAQAUAAoK3BQtGACPAQAAAA==.Cazlek:BAAANQADCggIIQAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECgoKKAAIAK0XAA==.Cerelus:BAABNQAECn8uAAIFAAkKsRfNCABOAgAFAAkKsRfNCABOAgAAAA==.',
Ch='Chaac:BAABNQAECn8uAAIVAAoKax8WBwCWAgAVAAoKax8WBwCWAgAAAA==.Chediah:BAAANQAECgQIDAAAAA==.Cheesûs:BAAANQAECgUICwAAAA==.Chéwtoy:BAAANQAECgcIDAAAAA==.',
Ci='Cilantro:BAAANQAECgMIAwABNQAECgoKKAAIAK0XAA==.',
Co='Cowmus:BAABNQAECn8VAAMCAAgKcRnUfgCdAQACAAgKcRnUfgCdAQADAAcK2Amy6wBFAQABNQAECgoKPQAGAC0fAA==.',
['Cã']='Cãrloy:BAABNQAECn+BAAISAAoKpx8FIwAsAwASAAoKpx8FIwAsAwAAAA==.',
Da='Daedalas:BAABNQAECn8gAAIOAAkKjRTAJQABAgAOAAkKjRTAJQABAgAAAA==.Daenari:BAAANQADCgYIBgAAAA==.Darkxsoul:BAABNQAECn8xAAINAAoKih2aBwCqAgANAAoKih2aBwCqAgAAAA==.Darthgrogu:BAAANQAECgYIEgABNQAFFAYIDAADAEELAA==.Darthknull:BAACNQAFFH8MAAIDAAYKQQuUDwBTAQADAAYKQQuUDwBTAQA1AAQKfzEAAgMACgrwHoIwAHUCAAMACgrwHoIwAHUCAAAA.Darthputska:BAAANQAECgYIBgABNQAFFAYIDAADAEELAA==.Darthreven:BAABNQAECn8YAAIBAAYK7QSr5gC2AAABAAYK7QSr5gC2AAABNQAFFAYIDAADAEELAA==.Darthtalon:BAABNQAECn8ZAAIWAAoKNAnqRQCpAQAWAAoKNAnqRQCpAQABNQAFFAYIDAADAEELAA==.Dayla:BAAANQADCgMIBAAAAA==.',
De='Deathchill:BAAANQAECgEIAQABNQAECggIFQAPABISAA==.Deathwood:BAABNQAECn8VAAIPAAgKEhK9DgCSAQAPAAgKEhK9DgCSAQAAAA==.Deatthdecay:BAAANQAECggIAQAAAA==.Degloved:BAEANQAECgQIBgABNQAECgoKNgAGABwcAA==.Deitrichx:BAAANQAECgMIAwAAAA==.Deminestrea:BAAANQADCgcICQAAAA==.Demonslayere:BAAANQAECggIEgABNQAFFAcIGgAXAJUiAA==.',
Di='Discodeitx:BAAANQADCgIIAgAAAA==.Disshammy:BAAANQAECgIIBAABNQAECggIDQAQAAAAAA==.',
Do='Donkform:BAAANQAECgIIAgABNQAECgYIDwAQAAAAAA==.Donkulle:BAAANQAECgYIDwAAAA==.',
Dr='Draconith:BAABNQAECn89AAIKAAoKDx2mAwBDAwAKAAoKDx2mAwBDAwAAAA==.Draqkmar:BAAANQADCgcICQAAAA==.',
Du='Dunsparrow:BAABNQAECn89AAIGAAoKLR9LIgDeAgAGAAoKLR9LIgDeAgAAAA==.Durgruk:BAAANQADCggICAABNQAECgoKPQAKAA8dAA==.Durzul:BAAANQADCgcICwAAAA==.',
Ei='Eindraken:BAABNQAECn89AAMKAAoKUhP7DQD1AQAKAAoKUhP7DQD1AQALAAEKAACSQgAkAAAAAA==.Eisis:BAABNQAECn8uAAIYAAoK9w8fEAB2AQAYAAoK9w8fEAB2AQAAAA==.',
El='Elanalué:BAAANQADCggIGAABNQAECgUICgAQAAAAAA==.',
Em='Empoleonn:BAABNQAECn8VAAIOAAgK7w5NJgD8AQAOAAgK7w5NJgD8AQAAAA==.',
En='Engos:BAAANQADCgYICQAAAA==.',
Ep='Epsolone:BAAANQADCgEIAQAAAA==.',
Er='Erroz:BAAANQADCggIEwAAAA==.Erukani:BAABNQAECn8UAAIZAAcKPAhEXgBXAQAZAAcKPAhEXgBXAQAAAA==.',
Es='Espriesso:BAABNQAECn8zAAMaAAoK/w+tNgAsAgAaAAoK/w+tNgAsAgAOAAIK0APvWQAsAAABNQAECgoKMAACAJUUAA==.',
Ex='Exemplar:BAAANQAECggIDQAAAA==.',
Fe='Fearwatermac:BAAANQAECgYIDQAAAA==.Feider:BAAANQADCgEIAQAAAA==.Felais:BAACNQAFFH8FAAIbAAMK9RZGCgDeAAAbAAMK9RZGCgDeAAA1AAQKfzAAAhsACgpLGskdAEICABsACgpLGskdAEICAAAA.Felin:BAAANQADCgEIAQAAAA==.Femmefatale:BAABNQAECn9MAAQaAAoKKB+qEgAYAwAaAAoKKB+qEgAYAwAOAAcKiw5aNQB5AQAcAAYKLgqJEQAPAQABNQAECgkJOAAbABITAA==.',
Fl='Flamecube:BAAANQADCgMIBAAAAA==.Flashx:BAABNQAECn8kAAICAAgKGyIQEwD2AgACAAgKGyIQEwD2AgAAAA==.Flass:BAAANQADCggIDgAAAA==.',
Fr='Freerin:BAAANQADCgcICgAAAA==.Frevpl:BAAANQAECgIIAgAAAA==.Frofrohunter:BAAANQAECgYIEgAAAA==.Froggie:BAAANQAECgYICAAAAA==.Frostme:BAAANQAECgIIAgAAAA==.',
Fu='Fuzywuuzy:BAAANQAECgYICAAAAA==.',
Ga='Gattsu:BAAANQAECgUICgABNQAECgoKMgACAM4QAA==.Gazdorn:BAABNQAECn8WAAIPAAcKZgzeHgBcAQAPAAcKZgzeHgBcAQAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgcIEAAAAA==.',
Ge='Genghis:BAAANQADCgQICAAAAA==.',
Gh='Ghost:BAABNQAECn8vAAIdAAoKARxyCQAdAgAdAAoKARxyCQAdAgAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAABNQAECn8kAAIHAAkK3xYbPgCgAQAHAAkK3xYbPgCgAQAAAA==.Gimmighoul:BAAANQAECgMIAwAAAA==.',
Gl='Glissa:BAABNQAECn8kAAQeAAoKMhwAHQCGAQAfAAcKrBnjgADkAQAeAAQKrCEAHQCGAQAgAAUKfhaBDgBqAQAAAA==.Gloomidge:BAABNQAECn8XAAIDAAgKXwftpwA+AQADAAgKXwftpwA+AQAAAA==.',
Go='Gorditt:BAAANQAECgIIAgAAAA==.',
Gr='Graphene:BAAANQAECgYIBgABNQAECgoKMgACAM4QAA==.',
Gt='Gt:BAABNQAECn8yAAMCAAoKzhCAaQDbAQACAAkKMxKAaQDbAQANAAcKQAu+OAAmAQAAAA==.',
Gu='Gulliveig:BAAANQADCgEIAQAAAA==.',
Ha='Habanero:BAAANQAECggIDQABNQAECgoKKAAIAK0XAA==.Hadense:BAAANQADCggICAABNQAFFAUIFQAHAL0gAA==.Hadory:BAAANQAECgcIEgAAAA==.',
He='Hellzzdemon:BAAANQAECgYIDQAAAA==.Hercow:BAAANQAECgUIEAAAAA==.Herrvoller:BAAANQADCgEIAQAAAA==.Hexinverter:BAAANQADCggIEwAAAA==.',
Ho='Holycannoli:BAABNQAECn8pAAIDAAkKdx77PwA5AgADAAkKdx77PwA5AgAAAA==.Holydeborah:BAAANQADCgUIBQAAAA==.Horiffic:BAABNQAECn8lAAIhAAoKTyAMAwDCAgAhAAoKTyAMAwDCAgAAAA==.Horok:BAAANQAECgQIBAAAAA==.Hotfuzz:BAABNQAECn8lAAIBAAoKXh0sVwDSAgABAAoKXh0sVwDSAgAAAA==.Hotsforthots:BAABNQAECn82AAIaAAoKzRvBGwDMAgAaAAoKzRvBGwDMAgAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.Hurricaneg:BAAANQADCgMIBAAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ic='Ichaerus:BAAANQAECgIIAgABNQAECgkJIAAOAI0UAA==.',
Ii='Iilli:BAAANQADCgYIBwAAAA==.',
In='Inari:BAAANQAECgMIAwAAAA==.Inkkubus:BAACNQAFFH8XAAQeAAcK1Q9dBQCRAAAfAAQKlw5sHwCWAAAeAAIKNxJdBQCRAAAgAAIKdxKZCQBaAAA1AAQKf0MABB8ACgp+Hx1BAI8CAB8ACQrPHh1BAI8CACAABQrVGM8MACQBAB4AAwqgETZDALgAAAAA.',
Ir='Ironfur:BAAANQAECgYIBgABNQAFFAYIEAACAMQQAA==.',
Je='Jeffpwnros:BAAANQAECgQIBgAAAA==.',
Jh='Jhohn:BAAANQAECgQICAAAAA==.',
Ji='Jintan:BAAANQAECgQIBwAAAA==.',
Ju='Judgmentjudy:BAACNQAFFH8QAAICAAYKxBCTDACVAQACAAYKxBCTDACVAQA1AAQKf50ABAIACgr1Ih0EAMgDAAIACgr1Ih0EAMgDAA0AAgrWA+VSAEAAAAMAAQqDAGrlAQoAAAAA.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAABNQAECn8uAAIFAAkKigtfEQCQAQAFAAkKigtfEQCQAQAAAA==.Kariatyda:BAABNQAECn8tAAIMAAoKqBQaVwDaAQAMAAoKqBQaVwDaAQAAAA==.Kasaí:BAABNQAECn8VAAIHAAYKMQ6DpQBJAQAHAAYKMQ6DpQBJAQAAAA==.Kassandra:BAAANQADCggICQAAAA==.',
Ke='Kekio:BAAANQAECgQICgAAAA==.',
Ki='Kiloton:BAABNQAECn8qAAIUAAgKQBEtIQCRAQAUAAgKQBEtIQCRAQAAAA==.Kinari:BAAANQAECgQIBwABNQAECgYIDgAQAAAAAA==.Kitzy:BAAANQAECgUICQAAAA==.',
Kl='Klippertdk:BAABNQAECn84AAIEAAgKbhbPIwCQAQAEAAgKbhbPIwCQAQAAAA==.Klugamonk:BAAANQADCgEIAgAAAA==.Klutz:BAABNQAECn8lAAIbAAkK0hMOJgDyAQAbAAkK0hMOJgDyAQAAAA==.',
Kn='Kniwt:BAAANQABCgQIBAABNQAECgoKMgACAM4QAA==.',
Ku='Kurzo:BAABNQAECn8bAAISAAgKTxosfQAiAgASAAgKTxosfQAiAgABNQAFFAMIBQAiACgLAA==.',
Ky='Kylarian:BAAANQAECgEIAQAAAA==.Kyntara:BAAANQAECgQIBgAAAA==.Kyronian:BAAANQAECgUIDQAAAA==.',
La='Lachancea:BAABNQAECn8eAAIGAAkKnBigOgD8AQAGAAkKnBigOgD8AQABNQAECgoKMgAfAFgbAA==.Laeleirri:BAAANQAECggIDQAAAA==.Lakshmee:BAABNQAECn8WAAIGAAcKwgW8rgASAQAGAAcKwgW8rgASAQAAAA==.Landwar:BAAANQADCgYIBgAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAABNQAECn8fAAIMAAoK3gMO7wAjAQAMAAoK3gMO7wAjAQAAAA==.Leonah:BAAANQAECgEIAQABNQAECgUICgAQAAAAAA==.Lexxi:BAAANQAECgMIBQAAAA==.',
Lh='Lhuru:BAAANQADCggIHAABNQAECgkJLgAFALEXAA==.',
Li='Lightbehunt:BAAANQAECgYIEgAAAA==.Lightdeborah:BAAANQADCgcIDgAAAA==.Lilly:BAAANQADCgYIBgAAAA==.Linestra:BAACNQAFFH8FAAIiAAMKKAvxAgCLAAAiAAMKKAvxAgCLAAA1AAQKfxoAAyIACgrHFCgHAOEBACIACgrHFCgHAOEBACMAAQoAAH6JAAAAAAAA.Livaless:BAAANQAECgMIAwABNQAECgoKKQAfAEIhAA==.',
Lo='Lorstus:BAAANQADCgEIAQAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAFFAUIBQACANgJAA==.Lux:BAAANQAECgEIAQAAAA==.',
Ly='Lyceum:BAAANQAECgQIBAABNQAECgoKMgACAM4QAA==.',
Ma='Mahidevran:BAAANQADCggIAgABNQAECgUICgAQAAAAAA==.Maitotoxin:BAAANQADCggIEwAAAA==.Majikarp:BAAANQAECgUIBQAAAA==.Mal:BAAANQADCggIFAAAAA==.Malthaius:BAAANQADCgUIBQAAAA==.Marble:BAAANQADCgYIBgABNQAECgYICAAQAAAAAA==.Marché:BAAANQAECgEIAgAAAA==.Mastablasta:BAAANQAECgQICgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAABNQAECn8aAAIbAAoKBgxrMwB/AQAbAAoKBgxrMwB/AQAAAA==.Mawks:BAABNQAECn9DAAMkAAoKESDNAgD9AgAkAAoKahzNAgD9AgAMAAYKzB2/ZACzAQAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.Mesoholy:BAAANQADCgEIAQABNQAECgYIBgAQAAAAAA==.',
Mi='Migzeviltwin:BAAANQAECgMIBAAAAA==.Milk:BAAANQAECgEIAQAAAA==.Miza:BAAANQAECgIIAgAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwAQAAAAAA==.Monkent:BAAANQAECgcIDAAAAA==.Monkeydluffy:BAAANQAECgMIBAABNQAFFAcIFwAjABMTAA==.Monstabull:BAAANQADCgUIBQAAAA==.Moomoomonkey:BAAANQADCgUIBQAAAA==.Morhgana:BAAANQADCgIIAwAAAA==.',
Na='Nallaa:BAAANQAECgYIDgAAAA==.Naranak:BAABNQAECn8oAAINAAkKgQ6VHABVAQANAAkKgQ6VHABVAQAAAA==.',
Ne='Neremian:BAAANQADCgQIBQAAAA==.',
No='Noodles:BAAANQAECgQIBAABNQAECgYIFAADAHUVAA==.',
Ny='Nymara:BAABNQAECn8hAAINAAgKQxDjKwB+AQANAAgKQxDjKwB+AQAAAA==.',
['Nü']='Nüguns:BAAANQAECgMIAwAAAA==.',
Ob='Obolus:BAAANQADCgEIAQAAAA==.',
Oc='Occan:BAAANQADCgMIAwAAAA==.',
Ol='Oldenglish:BAABNQAECn8mAAIDAAkKPAdZzQCBAQADAAkKPAdZzQCBAQAAAA==.',
On='Ontos:BAABNQAECn84AAMbAAkKEhNuGQD1AQAbAAkKEhNuGQD1AQAZAAYK/A3CSgDGAAAAAA==.',
Or='Orrok:BAAANQADCgEIAwAAAA==.',
Os='Osita:BAAANQAECgIIAgAAAA==.',
Pa='Painnkiller:BAABNQAECn84AAIMAAoK/RXQPwAeAgAMAAoK/RXQPwAeAgAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAABNQAECn8oAAIgAAkKFB+0AgBzAgAgAAkKFB+0AgBzAgABNQAECgoKKAAIAK0XAA==.',
Pe='Perriwinkle:BAABNQAECn82AAMYAAoK8xltBwA/AgAYAAoK8xltBwA/AgAbAAQKDQ7YQwC5AAAAAA==.',
Ph='Phylloxeras:BAABNQAECn9FAAMEAAoKdiVyAgBSAwAEAAoKdiVyAgBSAwAWAAEKAAAurAA2AAAAAA==.',
Po='Popecannoli:BAAANQAECgYIBgABNQAECgkJKQADAHceAA==.Powders:BAAANQAECgQICQAAAA==.',
Pr='Priopopo:BAAANQADCgEIAQAAAA==.Prophecyrose:BAAANQADCgQIBQAAAA==.Proshot:BAABNQAECn8nAAIkAAkKihg8BAASAgAkAAkKihg8BAASAgAAAA==.',
Pu='Puddles:BAAANQAECgEIAQAAAA==.',
Py='Pyrasi:BAABNQAECn8iAAIMAAgKHROJaQBBAgAMAAgKHROJaQBBAgAAAA==.',
Ra='Raccoon:BAABNQAECn8eAAMfAAgKBgomogCRAQAfAAgKBgomogCRAQAgAAIKIAm3KwA/AAAAAA==.Ralor:BAAANQADCgQIBAAAAA==.Razza:BAAANQADCggIEwAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgcICAABNQAECgoKKAAjAH0fAA==.',
Ro='Roa:BAAANQADCggIFQAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAACNQAFFH8XAAMjAAcKExMeBwDNAQAjAAcKExMeBwDNAQAlAAIKMRHiEQCAAAA1AAQKfzsAAyMACgqhIpIMALUCACMACQpAI5IMALUCACUACQo0G1MfAFQCAAAA.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECggIDAAAAA==.',
Sa='Saffron:BAAANQAECgMIBAABNQAECgoKKAAIAK0XAA==.Samidrac:BAAANQAECgQIEgAAAA==.Sammidormu:BAABNQAECn8XAAILAAYKaw59FQCxAAALAAYKaw59FQCxAAAAAA==.Saphiragosa:BAAANQAECgMIAwAAAA==.Saräha:BAAANQADCggJCwAAAA==.Satoriel:BAAANQADCgEIAQABNQAECgYIBgAQAAAAAA==.Satoshie:BAAANQAECgYIBgAAAA==.Satòshí:BAAANQADCgQICgABNQAECgYIBgAQAAAAAA==.Sayang:BAAANQADCgMIAwABNQAECggIGQAbAKkiAA==.',
Sc='Scerevisiae:BAABNQAECn8yAAMfAAoKWBumJgDpAgAfAAoKWBumJgDpAgAeAAEKgBVTbwBAAAAAAA==.',
Se='Sedelis:BAAANQAECgUIDgAAAA==.Selaya:BAAANQAECgMIBgAAAA==.Serafín:BAABNQAECn9DAAIIAAoKqhCbBwC2AQAIAAoKqhCbBwC2AQAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQAECgIIAwAAAA==.Shadownutt:BAAANQAECgQIDAAAAA==.Sharur:BAABNQAECn8ZAAIMAAkKbxD3XQDGAQAMAAkKbxD3XQDGAQAAAA==.Shazzam:BAAANQAECggICAAAAA==.Shieldwall:BAAANQAECgIIAwAAAA==.',
Si='Signir:BAABNQAECn8UAAIMAAoKrgGL7gCUAAAMAAoKrgGL7gCUAAAAAA==.Silanah:BAAANQAECgUICgABNQAECgoKPQAGAC0fAA==.Silveroaks:BAAANQADCgQIBAABNQAECgcIDAAQAAAAAA==.',
So='Sodapop:BAAANQAECgEIAQABNQAECgoKMgACAM4QAA==.Somavra:BAAANQAECggIDgAAAA==.Sopidia:BAAANQAECgYIEAAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAABNQAECn8dAAMaAAgKzxT5aADkAQAaAAgKzxT5aADkAQAcAAEK8hBMKQAxAAAAAA==.Spiritomb:BAAANQAECgYICgAAAA==.Spúdd:BAABNQAECn9AAAISAAoKFBxvJQCLAgASAAoKFBxvJQCLAgAAAA==.',
St='Stamavan:BAABNQAECn8gAAIUAAoKnhu0CgDEAgAUAAoKnhu0CgDEAgAAAA==.Starflayer:BAAANQAECggIEQABNQAFFAYIDgABAJYPAA==.Strykerius:BAAANQAECgEIAQABNQAECgUICgAQAAAAAA==.',
Su='Sunari:BAAANQADCgcIBwAAAA==.Supermelon:BAAANQAECgYIEAAAAA==.',
Sy='Syena:BAAANQAECgEIAQAAAA==.Sylvanaria:BAABNQAECn83AAIGAAkKhx8PIwDbAgAGAAkKhx8PIwDbAgAAAA==.Systyx:BAAANQADCgUICQABNQAECgQIBgAQAAAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.Tarot:BAAANQAECggICAAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAABNQAECn89AAIEAAoKBSOgBgD1AgAEAAoKBSOgBgD1AgAAAA==.',
Th='Thalaresh:BAABNQAECn8lAAIfAAkKbAgbiQAUAQAfAAkKbAgbiQAUAQAAAA==.Thaneer:BAAANQADCgQICAAAAA==.Throstmok:BAACNQAFFH8FAAIRAAMK4g6dEgCtAAARAAMK4g6dEgCtAAA1AAQKfyYAAhEACgpoHCcRAHECABEACgpoHCcRAHECAAAA.Thumbalina:BAAANQADCgYIBwABNQAECgkJIwACAF8RAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tideus:BAAANQADCgcIBwAAAA==.Tilingo:BAAANQAECgUIBgAAAA==.',
To='Tongra:BAAANQADCggIHwABNQAECgkJLgAFALEXAA==.Torg:BAABNQAECn8VAAIRAAgKew1oXgB4AQARAAgKew1oXgB4AQAAAA==.Torgin:BAAANQAECgQICQAAAA==.',
Tr='Trinitea:BAAANQAECgEIAQAAAA==.',
Tu='Turgies:BAABNQAECn8wAAMBAAoKVhLQTAACAgABAAoKVhLQTAACAgAFAAIKqQ6AMwBtAAAAAA==.Turgroka:BAAANQAECgcIDgAAAA==.',
['Tí']='Tíffanny:BAAANQAECgQIBQAAAA==.',
Ub='Ubaubadead:BAAANQAECgQICwAAAA==.Ubaubajuana:BAABNQAECn89AAIGAAoKTByTEAAPAwAGAAoKTByTEAAPAwAAAA==.',
Ul='Ulfast:BAABNQAECn8zAAIHAAgKmhwnNgCeAgAHAAgKmhwnNgCeAgAAAA==.',
Va='Vannhellsing:BAABNQAECn8uAAMEAAgKrga2dABFAQAEAAgKrga2dABFAQAWAAcKjgNlcACmAAAAAA==.Vanyel:BAABNQAECn9JAAIFAAoKjxYQBwARAgAFAAoKjxYQBwARAgAAAA==.Vardant:BAAANQADCgMIBQABNQAECgYIBgAQAAAAAA==.',
Ve='Veliena:BAAANQADCgYIBgABNQAECgUIFQAMADwJAA==.Vemal:BAABNQAECn84AAIMAAkK2BBEcwAqAgAMAAkK2BBEcwAqAgAAAA==.',
Vi='Vidula:BAAANQADCgcICgAAAA==.Vigorous:BAABNQAECn8hAAIPAAgK6wmJIgA1AQAPAAgK6wmJIgA1AQAAAA==.',
Vo='Vociferoy:BAABNQAECn9AAAMMAAoKFBt9LQBeAgAMAAoKFBt9LQBeAgATAAEKpAHwaQAlAAAAAA==.Voidsteffan:BAABNQAECn8pAAIeAAgKaQ/xBgA5AQAeAAgKaQ/xBgA5AQAAAA==.Vosina:BAAANQAECgUIBQAAAA==.',
Vv='Vv:BAACNQAFFH8wAAMlAAkKYCMIAAB3AwAlAAgKWyYIAAB3AwAjAAYKlRfTCgB2AQA1AAQKf0cAAyMACgrDJvYAAHwDACMACgo5JvYAAHwDACUACQq5JnYFAHsDAAAA.',
Wa='Waterworks:BAAANQAECgYICQABNQAECgoKMgACAM4QAA==.',
Wi='Willowmoon:BAAANQAECgcIDQAAAA==.',
Wo='Worgenlina:BAAANQAECgEIAQAAAA==.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAFFAcIFwAZAPUWAA==.',
['Wá']='Wárranpeace:BAAANQADCgIIAgAAAA==.',
Xa='Xalmo:BAAANQADCgQIBAABNQAECggIJAAJABAVAA==.Xalzi:BAAANQAECgQIAgABNQAECgYICAAQAAAAAA==.',
Xu='Xul:BAAANQADCgEIAQAAAA==.',
Xy='Xyphër:BAAANQADCgQIBAABNQAECgUICgAQAAAAAA==.',
Yo='Yotie:BAAANQADCgMIBAAAAA==.',
Za='Zannytoes:BAABNQAECn8cAAMmAAoKuQxiMQCNAQAmAAoKuQxiMQCNAQAXAAcKSAzELAAGAQAAAA==.',
Zi='Zie:BAABNQAECn87AAIOAAoKqRJDEwDtAQAOAAoKqRJDEwDtAQAAAA==.',
Zn='Zneon:BAAANQAECgIIAgAAAA==.',
['Ñi']='Ñice:BAACNQAFFH8HAAMhAAQKaRyUAQAYAQAhAAMKqxuUAQAYAQASAAEK5R0XOgBQAAA1AAQKfzUAAyEACQoXJVYFANACABIACAqhJFMpABUDACEACArjIFYFANACAAAA.',
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
