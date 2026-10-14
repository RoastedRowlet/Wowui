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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Shaman-Restoration','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Priest-Shadow','Warrior-Protection','Unknown-Unknown','DeathKnight-Blood','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Mage-Frost','Shaman-Enhancement','Priest-Holy','Druid-Restoration','Priest-Discipline','Rogue-Assassination','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Druid-Balance','Druid-Feral','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abukuma:BAAANQAECgUIBgAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAFFAUICwABAOgQAA==.',
Ae='Aenstalash:BAABNQAECn8cAAMCAAgKMx2/LQCtAgACAAgKMx2/LQCtAgADAAMKEwp+TgGbAAAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAABNQAECn8iAAIEAAgKRBJsTwDTAQAEAAgKRBJsTwDTAQAAAA==.',
Al='Alfonsoo:BAAANQAECgEIAQAAAA==.Alistur:BAAANQAECgYIDgAAAA==.',
Am='Ameena:BAABNQAECn8eAAIFAAcKBRskTgAoAgAFAAcKBRskTgAoAgAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Anamura:BAAANQADCgMIAwAAAA==.Angus:BAAANQAECgIIAwAAAA==.',
Ar='Arcomedes:BAAANQAECgEIAQAAAA==.Arthrasz:BAAANQAECgcIEwAAAA==.Arthraz:BAABNQAECn8iAAIGAAgKqxeoDgAHAgAGAAgKqxeoDgAHAgAAAA==.',
As='Asondralyn:BAAANQABCgUIBgAAAA==.Astara:BAABNQAECn8iAAIHAAkKYhTdBgBIAgAHAAkKYhTdBgBIAgAAAA==.Astrex:BAABNQAECn8bAAMIAAYKDBSuIwClAQAIAAYKDBSuIwClAQAJAAEKAgL+QgAgAAAAAA==.',
Au='Aurali:BAAANQAECgIIAwAAAA==.Aureliá:BAAANQAECgUIDwAAAA==.',
Az='Azureth:BAAANQAECgcIBwAAAA==.',
['Aü']='Aütobot:BAAANQAECgUICQAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQAECgQIBgABNQAECgYIGwAKAPwbAA==.',
Be='Bega:BAAANQAECgIIAgABNQAFFAQIBwALAIIEAA==.',
Bl='Bloodlustplz:BAABNQAECn8dAAIMAAgKaRCHGgCKAQAMAAgKaRCHGgCKAQAAAA==.',
Bo='Bobster:BAABNQAECn8dAAIBAAgKMhS+uQAPAgABAAgKMhS+uQAPAgAAAA==.Bonepaw:BAAANQADCgUICAABNQAECgYIBgANAAAAAA==.Booyea:BAABNQAECn8mAAIOAAgKqxX2OgAWAgAOAAgKqxX2OgAWAgAAAA==.',
Br='Brew:BAAANQABCgIJAgAAAA==.Brewwnor:BAAANQAECgUICQAAAA==.Brewwnôr:BAAANQADCgEIAQAAAA==.Brewwtus:BAAANQADCgMIAwAAAA==.Brisfloggnaw:BAAANQADCgcIBwAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.Bubbleplop:BAAANQAECgYICwABNQAECggIJwAPAO0UAA==.',
Ca='Calamuelis:BAACNQAFFH8OAAMQAAcKyxmSBAANAgAQAAYKYxmSBAANAgARAAEKbRtfIABdAAA1AAQKfycAAxAACQpLJhEOAG8DABAACQpLJhEOAG8DABEABAroImE8AGkBAAAA.Caliope:BAAANQAECgQIBQAAAA==.Carnage:BAAANQAECggIAgAAAA==.Cathbad:BAABNQAECn8iAAISAAgKYxEaGgDQAQASAAgKYxEaGgDQAQAAAA==.Cazlek:BAAANQADCggIIAAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECggIIgAGAKsXAA==.Cerelus:BAABNQAECn8eAAITAAgKYximCABPAgATAAgKYximCABPAgAAAA==.',
Ch='Chaac:BAABNQAECn8dAAIUAAgKEh6JCQDbAgAUAAgKEh6JCQDbAgAAAA==.Chediah:BAAANQAECgIIAgAAAA==.Cheesûs:BAAANQAECgUICwAAAA==.Chéwtoy:BAAANQADCggIHwAAAA==.',
Co='Cocana:BAAANQAECgQIBAAAAA==.Cowmus:BAAANQAECgcIDgABNQAECgkJJQAFAJkfAA==.',
['Cã']='Cãrloy:BAABNQAECn9jAAIPAAkKux5FIgAtAwAPAAkKux5FIgAtAwAAAA==.',
Da='Daedalas:BAAANQAECgcIEgAAAA==.Daenari:BAAANQADCgYIBgAAAA==.Darkxsoul:BAABNQAECn8bAAIKAAYK/BvvIgDHAQAKAAYK/BvvIgDHAQAAAA==.Darthgrogu:BAAANQAECgYIDgABNQAFFAUICQADAEgNAA==.Darthknull:BAACNQAFFH8JAAIDAAUKSA0eDwBTAQADAAUKSA0eDwBTAQA1AAQKfyIAAgMACQrzGeRlAGUCAAMACQrzGeRlAGUCAAAA.Darthputska:BAAANQAECgQIBAABNQAFFAUICQADAEgNAA==.Darthreven:BAAANQAECgUIDQABNQAFFAUICQADAEgNAA==.Darthtalon:BAAANQAECggIEwABNQAFFAUICQADAEgNAA==.Dayla:BAAANQADCgMIAwAAAA==.',
De='Deathwood:BAAANQAECgIIAgAAAA==.Deatthdecay:BAAANQAECggJAQAAAA==.Degloved:BAAANQAECgQIBAAAAA==.Deitrichx:BAAANQAECgMIAwAAAA==.Deminestrea:BAAANQADCgcICAAAAA==.',
Di='Discodeitx:BAAANQADCgIIAgAAAA==.Disshammy:BAAANQAECgEIAgABNQAECgcICwANAAAAAA==.',
Do='Donkform:BAAANQAECgIIAgABNQAECgYIDwANAAAAAA==.Donkulle:BAAANQAECgYIDwAAAA==.',
Dr='Draconith:BAABNQAECn8iAAIIAAgKaRbQGAAwAgAIAAgKaRbQGAAwAgAAAA==.Draqkmar:BAAANQADCgcICAAAAA==.',
Du='Dunsparrow:BAABNQAECn8lAAIFAAkKmR/VIQDfAgAFAAkKmR/VIQDfAgAAAA==.Durzul:BAAANQADCgcICwAAAA==.',
Ei='Eindraken:BAABNQAECn8kAAMIAAkKnw8GHAAHAgAIAAkKnw8GHAAHAgAJAAEKAAD/QQAkAAAAAA==.Eisis:BAAANQAECgUIDwAAAA==.',
El='Elanalué:BAAANQADCggIGAABNQAECgQIBQANAAAAAA==.',
Em='Empoleonn:BAABNQAECn8VAAILAAgK7w7uJQD8AQALAAgK7w7uJQD8AQAAAA==.',
En='Engos:BAAANQADCgYIBwAAAA==.',
Ep='Epsolone:BAAANQABCgMIAwAAAA==.',
Er='Erroz:BAAANQADCggIEwAAAA==.Erukani:BAAANQAECgYIEQAAAA==.',
Es='Espriesso:BAABNQAECn8fAAMVAAkKWAdAggCMAQAVAAgK0AdAggCMAQALAAEKAAByjQAbAAABNQAECgkJJQACAEsQAA==.',
Ex='Exemplar:BAAANQAECgEIAQAAAA==.',
Fe='Fearwatermac:BAAANQAECgYIDQAAAA==.Feider:BAAANQABCgQJBwAAAA==.Felais:BAABNQAECn8lAAIWAAkKnxZuHQBBAgAWAAkKnxZuHQBBAgAAAA==.Felin:BAAANQABCggIHgAAAA==.Femmefatale:BAABNQAECn8uAAQVAAkKARkAKgC+AgAVAAkKARkAKgC+AgALAAcKiw7WNAB5AQAXAAYKLgpoEQAPAQAAAA==.',
Fl='Flamecube:BAAANQADCgMIAwAAAA==.Flashx:BAAANQAECgUIDgAAAA==.Flass:BAAANQADCggIDgAAAA==.',
Fr='Freerin:BAAANQADCgcICAAAAA==.Frevpl:BAAANQAECgIIAgAAAA==.Frofrohunter:BAAANQAECgYIEgAAAA==.Froggie:BAAANQAECgYIBgAAAA==.',
Fu='Fuzywuuzy:BAAANQAECgUJBgAAAA==.',
Ga='Gattsu:BAAANQABCgEIAQABNQAECgkJKgACAHwPAA==.Gazdorn:BAAANQAECgYIEwAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgYIDwAAAA==.',
Ge='Genghis:BAAANQADCgQICAAAAA==.',
Gh='Ghost:BAABNQAECn8fAAIYAAkKRBqtGQCrAgAYAAkKRBqtGQCrAgAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAABNQAECn8aAAIZAAcK1BZ9dAC/AQAZAAcK1BZ9dAC/AQAAAA==.Gimmighoul:BAAANQAECgMIAwAAAA==.',
Gl='Gleoc:BAAANQAECgcIDwAAAA==.Glissa:BAABNQAECn8gAAQaAAkKJx3IHACGAQAbAAYKgRrafgDlAQAaAAQKrCHIHACGAQAcAAUKfhZXDgBqAQAAAA==.',
Go='Gorditt:BAAANQAECgIIAgAAAA==.',
Gt='Gt:BAABNQAECn8qAAMCAAkKfA8/aADcAQACAAgK4xA/aADcAQAKAAcKQAv5NwAmAQAAAA==.',
Ha='Habanero:BAAANQAECgQIBwABNQAECggIIgAGAKsXAA==.Hadense:BAAANQADCggICAABNQAFFAMICAAZAH8cAA==.Hadory:BAAANQAECgYICwAAAA==.',
He='Hellzzdemon:BAAANQAECgQIBQAAAA==.Hercow:BAAANQAECgIIAgAAAA==.Herrvoller:BAAANQADCgEIAQAAAA==.Hexinverter:BAAANQADCggIEgAAAA==.',
Ho='Holycannoli:BAAANQAECgYIEQAAAA==.Horiffic:BAABNQAECn8XAAIdAAcKERlnCgAiAgAdAAcKERlnCgAiAgAAAA==.Hotfuzz:BAABNQAECn8ZAAIBAAkKtxycVADXAgABAAkKtxycVADXAgAAAA==.Hotsforthots:BAABNQAECn8iAAIVAAkK8xc8MgCcAgAVAAkK8xc8MgCcAgAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.Hurricaneg:BAAANQADCgMIAwAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ic='Ichaerus:BAAANQAECgIIAgABNQAECgcIEgANAAAAAA==.',
Ii='Iilli:BAAANQADCgYIBgAAAA==.',
In='Inari:BAAANQAECgIIAQAAAA==.Inkkubus:BAACNQAFFH8PAAQaAAUKGxIFEQCRAAAbAAMKqRRuJgDSAAAaAAIKBwoFEQCRAAAcAAEKAABVCQBaAAA1AAQKfy4ABBsACQqqHu4/AI8CABsACAq5Hu4/AI8CABoAAwqgEdJCALgAABwAAgqJG9ccAJUAAAAA.',
Ir='Ironfur:BAAANQABCgQICgABNQAFFAUIDgACAAQRAA==.',
Je='Jeffpwnros:BAAANQAECgQIBgAAAA==.',
Jh='Jhohn:BAAANQAECgMIBAAAAA==.',
Ji='Jintan:BAAANQAECgQIBwAAAA==.',
Ju='Judgmentjudy:BAACNQAFFH8OAAICAAUKBBE6DACVAQACAAUKBBE6DACVAQA1AAQKf2MAAwIACQrdIm0IAIQDAAIACQrdIm0IAIQDAAMAAQqDABneAQoAAAAA.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAABNQAECn8dAAITAAgKQwoxEQCQAQATAAgKQwoxEQCQAQAAAA==.Kariatyda:BAABNQAECn8gAAIQAAgKFxbYagA7AgAQAAgKFxbYagA7AgAAAA==.Kasaí:BAAANQAECgUIDgAAAA==.Kassandra:BAAANQADCggICAAAAA==.',
Ke='Kekio:BAAANQADCgYICQAAAA==.',
Ki='Kiloton:BAAANQAECgYIEwAAAA==.Kinari:BAAANQAECgIIAgABNQAECgYIDgANAAAAAA==.Kitzy:BAAANQAECgUICQAAAA==.',
Kl='Klippertdk:BAABNQAECn8mAAIEAAgK1hMOTADhAQAEAAgK1hMOTADhAQAAAA==.Klutz:BAABNQAECn8eAAIWAAcKqBe0JQDyAQAWAAcKqBe0JQDyAQAAAA==.',
Kn='Kniwt:BAAANQABCgQIBAABNQAECgkJKgACAHwPAA==.',
Ku='Kurzo:BAABNQAECn8bAAIPAAgKTxqQewAiAgAPAAgKTxqQewAiAgAAAA==.',
Ky='Kylarian:BAAANQAECgEIAQAAAA==.Kyntara:BAAANQAECgQIBgAAAA==.Kyronian:BAAANQAECgUIBQAAAA==.',
La='Lachancea:BAAANQAECgUICwABNQAECggIEwANAAAAAA==.Laeleirri:BAAANQAECggIDQAAAA==.Lakshmee:BAABNQAECn8WAAIFAAcKwgX6rAASAQAFAAcKwgX6rAASAQAAAA==.Landwar:BAAANQADCgYIBgAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAABNQAECn8cAAIQAAgK5wIO7AAkAQAQAAgK5wIO7AAkAQAAAA==.Lexxi:BAAANQAECgMIBQAAAA==.',
Lh='Lhuru:BAAANQADCggIEwABNQAECggIHgATAGMYAA==.',
Li='Lightbehunt:BAAANQAECgQICgAAAA==.Lilly:BAAANQADCgYIBgAAAA==.Linestra:BAAANQAECgMICAABNQAECggJGwAPAE8aAA==.Livaless:BAAANQAECgMIAwABNQAECgkJJgAbADUiAA==.',
Lo='Lorstus:BAAANQABCgYIBgAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAECggIEQANAAAAAA==.Lux:BAAANQADCgcIBwAAAA==.',
Ma='Mahidevran:BAAANQADCggIAgABNQAECgQIBQANAAAAAA==.Maitotoxin:BAAANQADCggIEgAAAA==.Majikarp:BAAANQADCgYIBgAAAA==.Mal:BAAANQADCggIFAABNQAECgYIFAACALYgAA==.Malthaius:BAAANQADCgUIBQAAAA==.Marble:BAAANQADCgYIBgABNQAECgYIBgANAAAAAA==.Mastablasta:BAAANQAECgQICgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAABNQAECn8XAAIWAAgKWAvpMgB/AQAWAAgKWAvpMgB/AQAAAA==.Mawks:BAABNQAECn8lAAIeAAgKVx/EAgD+AgAeAAgKVx/EAgD+AgAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.',
Mi='Migzeviltwin:BAAANQADCggIDAAAAA==.Milk:BAAANQAECgEIAQAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwANAAAAAA==.Monkent:BAAANQAECgYIBgAAAA==.Monstabull:BAAANQADCgUIBQAAAA==.Morhgana:BAAANQADCgIIAgAAAA==.',
Na='Nallaa:BAAANQAECgYIDgAAAA==.Naranak:BAAANQAECgUIEwAAAA==.',
Ne='Neremian:BAAANQADCgQIBAAAAA==.',
No='Noodles:BAAANQAECgQIBAABNQAECgUIEQANAAAAAA==.',
Ny='Nymara:BAAANQAECgYIEAAAAA==.',
Oc='Occan:BAAANQADCgMIAwAAAA==.',
Ol='Oldenglish:BAABNQAECn8XAAIDAAgK4wdKygCBAQADAAgK4wdKygCBAQAAAA==.',
On='Ontos:BAABNQAECn8jAAMWAAgKLAjUNwBZAQAWAAgKLAjUNwBZAQAfAAUKzQ5xbgAMAQABNQAECgkJLgAVAAEZAA==.',
Or='Orrok:BAAANQADCgEIAQAAAA==.',
Os='Osita:BAAANQAECgIIAgAAAA==.',
Pa='Painnkiller:BAABNQAECn8iAAIQAAgKjxE4bgAzAgAQAAgKjxE4bgAzAgAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAAANQAECgUIDwABNQAECggIIgAGAKsXAA==.',
Pe='Perriwinkle:BAABNQAECn8lAAIgAAkKKRceCwB8AgAgAAkKKRceCwB8AgAAAA==.',
Ph='Phylloxeras:BAABNQAECn8nAAMEAAkKTSRVBwCJAwAEAAkKTSRVBwCJAwAhAAEKAAC0qAA2AAAAAA==.',
Po='Powders:BAAANQAECgQICQAAAA==.',
Pr='Priopopo:BAAANQABCgIIBAAAAA==.Prophecyrose:BAAANQADCgQIBQAAAA==.Proshot:BAAANQAECgQIEQAAAA==.',
Pu='Puddles:BAAANQAECgEIAQAAAA==.',
Py='Pyrasi:BAABNQAECn8iAAIQAAgKHRPiZwBCAgAQAAgKHRPiZwBCAgAAAA==.',
Ra='Raccoon:BAABNQAECn8cAAMbAAgKBgrwnwCRAQAbAAgKBgrwnwCRAQAcAAEKxw5NKwA/AAAAAA==.Ralor:BAAANQADCgQIBAAAAA==.Razza:BAAANQADCggIEgAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgcIBwABNQAECgkJGgAiADkZAA==.',
Ro='Roa:BAAANQADCggIFQAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAACNQAFFH8WAAMiAAYKvhfmBgDOAQAiAAYKvhfmBgDOAQAjAAIKMRGdEQCAAAA1AAQKfykAAyMACQpEIP8eAFQCACMACQo0G/8eAFQCACIABgpKIQstADcCAAAA.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECgYIBgAAAA==.',
Sa='Saffron:BAAANQAECgIIAwABNQAECggIIgAGAKsXAA==.Samidrac:BAAANQAECgIIBgAAAA==.Sammidormu:BAAANQAECgQIBwAAAA==.Saräha:BAAANQADCggJCwAAAA==.Satoshie:BAAANQAECgYIBgAAAA==.Satòshí:BAAANQADCgQIBAABNQAECgYIBgANAAAAAA==.Sayang:BAAANQADCgMIAwABNQAECgYIEAANAAAAAA==.',
Sc='Scerevisiae:BAAANQAECggIEwAAAA==.',
Se='Sedelis:BAAANQAECgUIDgAAAA==.Selaya:BAAANQADCgYIGwAAAA==.Serafín:BAABNQAECn8mAAIGAAgKOgooFQCOAQAGAAgKOgooFQCOAQAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQAECgEIAQAAAA==.Shadownutt:BAAANQAECgQICAAAAA==.Sharur:BAAANQAECgUIBQAAAA==.Shazzam:BAAANQAECggIAgAAAA==.Shieldwall:BAAANQAECgIIAwAAAA==.',
Si='Silanah:BAAANQAECgUICgABNQAECgkJJQAFAJkfAA==.Silveroaks:BAAANQADCgQIBAABNQAECgYIBgANAAAAAA==.',
So='Somavra:BAAANQAECgYIDAAAAA==.Sopidia:BAAANQAECgMIBgAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAAANQAECgYIEQAAAA==.Spiritomb:BAAANQAECgYICQAAAA==.Spúdd:BAABNQAECn8cAAIPAAcKVRYFlADmAQAPAAcKVRYFlADmAQAAAA==.',
St='Stamavan:BAABNQAECn8dAAISAAgKqh6KCgDDAgASAAgKqh6KCgDDAgAAAA==.Strykerius:BAAANQAECgEIAQABNQAECgUICgANAAAAAA==.',
Su='Sunari:BAAANQADCgcIBwAAAA==.Supermelon:BAAANQAECgYIDQAAAA==.',
Sy='Syena:BAAANQADCgIJAgAAAA==.Sylvanaria:BAABNQAECn8mAAIFAAgKtyCWIgDbAgAFAAgKtyCWIgDbAgAAAA==.Systyx:BAAANQADCgUICQABNQAECgQIBgANAAAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAABNQAECn8jAAIEAAgKSCODHADfAgAEAAgKSCODHADfAgAAAA==.',
Th='Thaneer:BAAANQADCgQICAAAAA==.Throstmok:BAAANQAECggIEwAAAA==.Thumbalina:BAAANQADCgYIBgABNQAECggIIQACACIRAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tideus:BAAANQADCgcIBwAAAA==.Tilingo:BAAANQAECgUIBgAAAA==.',
To='Tongra:BAAANQADCggIHwABNQAECggIHgATAGMYAA==.Torg:BAAANQAECgcIEAAAAA==.Torgin:BAAANQAECgQIBQAAAA==.',
Tr='Trinitea:BAAANQADCgcICAAAAA==.',
Tu='Turgies:BAABNQAECn8mAAMBAAcKZRQY/gCOAQABAAYKnBYY/gCOAQATAAIKqQ7pMgBtAAAAAA==.Turgroka:BAAANQAECgEIAwAAAA==.',
['Tí']='Tíffanny:BAAANQAECgEIAQAAAA==.',
Ub='Ubaubadead:BAAANQADCgIIAgAAAA==.Ubaubajuana:BAABNQAECn8mAAIFAAgKqhjkRwA/AgAFAAgKqhjkRwA/AgAAAA==.',
Ul='Ulfast:BAABNQAECn8jAAIZAAgKLBxXNQCfAgAZAAgKLBxXNQCfAgAAAA==.',
Va='Vannhellsing:BAAANQAECgcIEwAAAA==.Vanyel:BAABNQAECn8rAAITAAgKfBYrCgAlAgATAAgKfBYrCgAlAgAAAA==.Vardant:BAAANQADCgMIAwABNQAECgYIBgANAAAAAA==.',
Ve='Vemal:BAABNQAECn8oAAIQAAgKARKhcQArAgAQAAgKARKhcQArAgAAAA==.',
Vi='Vidula:BAAANQADCgcICAAAAA==.Vigorous:BAAANQAECgYIEAAAAA==.',
Vo='Vociferoy:BAABNQAECn8mAAIQAAgKWxjBPQCvAgAQAAgKWxjBPQCvAgAAAA==.Voidsteffan:BAABNQAECn8cAAIaAAcKSA4qGgCaAQAaAAcKSA4qGgCaAQAAAA==.',
Vv='Vv:BAACNQAFFH8sAAMjAAgKWyYGAAB5AwAjAAgKWyYGAAB5AwAiAAUKnBmPCgB2AQA1AAQKfycAAyMACQqLJloFAHwDACMACQqLJloFAHwDACIABQrjI7ZDAKABAAAA.',
Wa='Waterworks:BAAANQAECgQIBQABNQAECgkJKgACAHwPAA==.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAFFAcIFgAfAPUWAA==.',
['Wá']='Wárranpeace:BAAANQADCgIIAgAAAA==.',
Xa='Xalmo:BAAANQADCgQIBAABNQAECgcIIAAHAFMVAA==.Xalzi:BAAANQADCgEIAQABNQAECgYIBgANAAAAAA==.',
Xu='Xul:BAAANQABCggICgAAAA==.',
Xy='Xyphër:BAAANQADCgQIBAABNQAECgUICgANAAAAAA==.',
Za='Zannytoes:BAABNQAECn8YAAMkAAgKaAzQMACNAQAkAAgKaAzQMACNAQAlAAYKHwtBLAAGAQAAAA==.',
Zi='Zie:BAABNQAECn8pAAILAAgKkBKZKADgAQALAAgKkBKZKADgAQAAAA==.',
['Ñi']='Ñice:BAACNQAFFH8HAAMdAAQKaRyRAQAYAQAdAAMKqxuRAQAYAQAPAAEK5R0gOQBQAAA1AAQKfzUAAx0ACQoXJT4FANACAA8ACAqhJIMoABYDAB0ACArjID4FANACAAAA.',
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
