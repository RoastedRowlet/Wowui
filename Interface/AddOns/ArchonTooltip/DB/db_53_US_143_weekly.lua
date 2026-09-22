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

local lookup = {'Mage-Arcane','Evoker-Augmentation','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Warrior-Fury',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abukuma:BAAANQAECgEJAQAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAECgkJFwABAN8eAA==.',
Ae='Aenstalash:BAAANQAECgMJBAAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAAANQAECgYJDQAAAA==.',
Al='Alistur:BAAANQAECgQJCAAAAA==.',
Am='Ameena:BAAANQAECgUJCQAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Angus:BAAANQAECgEJAQAAAA==.',
Ar='Arcomedes:BAAANQADCgUIBQAAAA==.Arthrasz:BAAANQAECgYJDQAAAA==.Arthraz:BAAANQAECgYJDQAAAA==.',
As='Asondralyn:BAAANQABCgUIBgAAAA==.Astara:BAABNQAECoEbAAICAAgKoRVFBQAcAgACAAgKoRVFBQAcAgAAAA==.Astrex:BAAANQAECgUJCQAAAA==.',
Au='Aurali:BAAANQAECgEJAQAAAA==.Aureliá:BAAANQAECgQJCAAAAA==.',
Az='Azureth:BAAANQAECgcJBwAAAA==.',
['Aü']='Aütobot:BAAANQAECgUJBwAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQADCgIIAgABNQAECgUIDgADAAAAAA==.',
Bl='Bloodlustplz:BAAANQAECgYIDwAAAA==.',
Bo='Bobster:BAAANQAECgYJDQAAAA==.Bonepaw:BAAANQADCgUICAABNQAECgQIBAADAAAAAA==.Booyea:BAAANQAECgUJDAAAAA==.',
Br='Brew:BAAANQABCgIJAgAAAA==.Brewwnor:BAAANQAECgQJBgAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.Bubbleplop:BAAANQAECgIIAgABNQAECgcIEQADAAAAAA==.',
Ca='Calaestra:BAAANQAECgYIDgAAAA==.Calamuelis:BAACNQAFFIEKAAIEAAYKXRi5AAA2AgAEAAYKXRi5AAA2AgA1AAQKgR8AAwQACQoxJqECAL8DAAQACQoxJqECAL8DAAUAAgrkG4BJAH4AAAAA.Caliope:BAAANQADCggJHgAAAA==.Cathbad:BAAANQAECgQICAAAAA==.Cazlek:BAAANQADCggJHQAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECgYJDQADAAAAAA==.Cerelus:BAAANQAECgUICQAAAA==.',
Ch='Chaac:BAAANQAECgUICwAAAA==.Chediah:BAAANQADCgcJBwAAAA==.Cheesûs:BAAANQAECgUICwAAAA==.Chéwtoy:BAAANQADCgcIBwAAAA==.',
Co='Cowmus:BAAANQAECgIIAgABNQAECggIFwAGAI8gAA==.',
['Cã']='Cãrloy:BAABNQAECoEfAAIHAAgKkhamSQBCAgAHAAgKkhamSQBCAgAAAA==.',
Da='Daedalas:BAAANQAECgQJCAAAAA==.Darkxsoul:BAAANQAECgUIDgAAAA==.Darthgrogu:BAAANQAECgEIAQABNQAECgkJGwAIAI4YAA==.Darthknull:BAABNQAECoEbAAIIAAkKjhj1NACCAgAIAAkKjhj1NACCAgAAAA==.Darthputska:BAAANQADCgcIBwABNQAECgkJGwAIAI4YAA==.Darthreven:BAAANQADCgUIBQABNQAECgkJGwAIAI4YAA==.Darthtalon:BAAANQAECgUICAABNQAECgkJGwAIAI4YAA==.',
De='Deathwood:BAAANQADCgUJDgAAAA==.Deatthdecay:BAAANQAECggJAQAAAA==.Deitrichx:BAAANQADCgYIDAAAAA==.Deminestrea:BAAANQADCgEIAQAAAA==.',
Do='Donkform:BAAANQAECgIIAgABNQAECgYIBgADAAAAAA==.Donkulle:BAAANQAECgYIBgAAAA==.',
Dr='Draconith:BAAANQAECgYIEQAAAA==.Draqkmar:BAAANQADCgEIAQAAAA==.',
Du='Dunsparrow:BAABNQAECoEXAAIGAAgKjyDeFwDJAgAGAAgKjyDeFwDJAgAAAA==.Durzul:BAAANQADCgcICQAAAA==.',
Ei='Eindraken:BAAANQAECgUJDAAAAA==.Eisis:BAAANQAECgQICQAAAA==.',
Em='Empoleonn:BAAANQAECgQIBgAAAA==.',
En='Engos:BAAANQADCgYIBwAAAA==.',
Ep='Epsolone:BAAANQABCgMIAwAAAA==.',
Er='Erroz:BAAANQADCggIEwAAAA==.Erukani:BAAANQAECgUJBQAAAA==.',
Es='Espriesso:BAAANQAECgYICwABNQAECgkJGAAJAK4LAA==.',
Ex='Exemplar:BAAANQADCgEIAQAAAA==.',
Fe='Fearwatermac:BAAANQAECgYJCQAAAA==.Feider:BAAANQABCgQJBwAAAA==.Felais:BAABNQAECoEbAAIKAAgKBxf7FAAeAgAKAAgKBxf7FAAeAgAAAA==.Felin:BAAANQABCggIFAAAAA==.Femmefatale:BAAANQAECggIEgAAAA==.',
Fl='Flamecube:BAAANQADCgMIAwAAAA==.Flashx:BAAANQAECgIIAgAAAA==.Flass:BAAANQADCggIDgAAAA==.',
Fr='Freerin:BAAANQADCgEIAQAAAA==.Frevpl:BAAANQADCggIEAAAAA==.Frofrohunter:BAAANQAECgUIDAAAAA==.Froggie:BAAANQAECgQIBAAAAA==.',
Fu='Fuzywuuzy:BAAANQAECgUJBgAAAA==.',
Ga='Gazdorn:BAAANQAECgUJBwAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgYJCQAAAA==.',
Ge='Genghis:BAAANQADCgQICAAAAA==.',
Gh='Ghost:BAAANQAECgYIDwAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAAANQAECgQJBgAAAA==.Gimmighoul:BAAANQAECgMIAwAAAA==.',
Gl='Gleoc:BAAANQADCgUICAAAAA==.Glissa:BAAANQAECgYICgAAAA==.',
Gt='Gt:BAAANQAECgYIEwAAAA==.',
Ha='Habanero:BAAANQAECgEJAQABNQAECgYJDQADAAAAAA==.Hadory:BAAANQAECgQIBgAAAA==.',
He='Hellzzdemon:BAAANQADCggJIQAAAA==.Herrvoller:BAAANQADCgEIAQAAAA==.Hexinverter:BAAANQADCgcICgAAAA==.',
Ho='Holycannoli:BAAANQAECgQIBgAAAA==.Horiffic:BAAANQAECgQJCQAAAA==.Hotfuzz:BAAANQAECgYIDQAAAA==.Hotsforthots:BAAANQAECgUIDAAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ii='Iilli:BAAANQADCgYIBgAAAA==.',
In='Inari:BAAANQADCggIDQAAAA==.Inkkubus:BAABNQAECoEjAAQLAAkKsB/XGgDHAgALAAgK2x/XGgDHAgAMAAMKoBFNNQDJAAANAAEKIh7IGgBQAAAAAA==.',
Ir='Ironfur:BAAANQABCgQIBgABNQAFFAIIBQAJAKgTAA==.',
Je='Jeffpwnros:BAAANQAECgQIBgAAAA==.',
Ji='Jintan:BAAANQAECgQJBQAAAA==.',
Ju='Judgmentjudy:BAACNQAFFIEFAAIJAAIKqBMtEAChAAAJAAIKqBMtEAChAAA1AAQKgTcAAwkACQoNIakFAHoDAAkACQoNIakFAHoDAAgAAQqDADFGAQsAAAAA.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAAANQAECgUJBQAAAA==.Kariatyda:BAAANQAECgYJEQAAAA==.Kasaí:BAAANQAECgQJBQAAAA==.Kassandra:BAAANQADCggICAAAAA==.',
Ki='Kiloton:BAAANQAECgMIBAAAAA==.Kitzy:BAAANQAECgUJBwAAAA==.',
Kl='Klippertdk:BAAANQAECgUIDAAAAA==.Klutz:BAAANQAECgUJDAAAAA==.',
Ku='Kurzo:BAABNQAECoEbAAIHAAgK1xqRPwBoAgAHAAgK1xqRPwBoAgAAAA==.',
Ky='Kylarian:BAAANQAECgEIAQAAAA==.Kyntara:BAAANQAECgQIBAAAAA==.Kyronian:BAAANQADCgQJBAAAAA==.',
La='Lachancea:BAAANQADCgYJCgABNQAECgEIAgADAAAAAA==.Laeleirri:BAAANQAECgYJBgAAAA==.Lakshmee:BAAANQAECgUICQAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAAANQAECgYJDQAAAA==.Lexxi:BAAANQAECgMIBQAAAA==.',
Li='Lightbehunt:BAAANQAECgQIBgAAAA==.Livaless:BAAANQAECgMIAwABNQAECgcIEwADAAAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAECggICwADAAAAAA==.Lux:BAAANQABCgUJBwAAAA==.',
Ma='Mahidevran:BAAANQADCggIAgABNQADCggJHgADAAAAAA==.Maitotoxin:BAAANQADCggIEgAAAA==.Mal:BAAANQADCggJCAABNQAECgQIBgADAAAAAA==.Malthaius:BAAANQADCgUIBQAAAA==.Marble:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.Mastablasta:BAAANQAECgQICgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAAANQAECgYJDQAAAA==.Mawks:BAAANQAECgYICwAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.',
Mi='Migzeviltwin:BAAANQADCgQIBAAAAA==.Milk:BAAANQADCggICAAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwADAAAAAA==.Monkent:BAAANQAECgQIBAAAAA==.Morhgana:BAAANQADCgEIAQAAAA==.',
Na='Nallaa:BAAANQAECgQJCAAAAA==.Naranak:BAAANQAECgEIAQAAAA==.',
Ne='Neremian:BAAANQADCgQIBAAAAA==.',
No='Noodles:BAAANQADCggIFAAAAA==.',
Ny='Nymara:BAAANQAECgQJCAAAAA==.',
Oc='Occan:BAAANQADCgMIAwAAAA==.',
Ol='Oldenglish:BAAANQAECgMIBAAAAA==.',
On='Ontos:BAAANQAECgUIDwABNQAECggIEgADAAAAAA==.',
Or='Orrok:BAAANQADCgEIAQAAAA==.',
Os='Osita:BAAANQAECgIIAgAAAA==.',
Pa='Painnkiller:BAAANQAECgUJCwAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAAANQAECgMIAwABNQAECgYJDQADAAAAAA==.',
Pe='Perriwinkle:BAABNQAECoEZAAIOAAgKmRZ1BwBGAgAOAAgKmRZ1BwBGAgAAAA==.',
Ph='Phylloxeras:BAAANQAECgYIDQAAAA==.',
Po='Powders:BAAANQAECgQICQAAAA==.',
Pr='Priopopo:BAAANQABCgIIBAAAAA==.Prophecyrose:BAAANQADCgQIBQAAAA==.Proshot:BAAANQAECgQIBgAAAA==.',
Pu='Puddles:BAAANQADCgMIBQAAAA==.',
Py='Pyrasi:BAABNQAECoEaAAIEAAgKoxO8PABDAgAEAAgKoxO8PABDAgAAAA==.',
Ra='Raccoon:BAAANQAECgUJCQAAAA==.Ralor:BAAANQADCgMIAwAAAA==.Razza:BAAANQADCggIEgAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgcIBwABNQAECgcJDQADAAAAAA==.',
Ro='Roa:BAAANQADCggIFQAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAACNQAFFIEKAAMPAAQKQxZaBQBPAQAPAAQKQxZaBQBPAQAQAAIKMREgCgCcAAA1AAQKgR8AAxAACQqqHTERAKcCABAACQrzGjERAKcCAA8ABQolH+ImANgBAAAA.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECgEIAQAAAA==.',
Sa='Saffron:BAAANQADCgMIBAABNQAECgYJDQADAAAAAA==.Samidrac:BAAANQAECgIIAgAAAA==.Sammidormu:BAAANQAECgEJAQAAAA==.Saräha:BAAANQADCggJCwAAAA==.Satoshie:BAAANQAECgYJBgAAAA==.Satòshí:BAAANQADCgQIBAABNQAECgYJBgADAAAAAA==.Sayang:BAAANQADCgMIAwABNQAECgMIBQADAAAAAA==.',
Sc='Scerevisiae:BAAANQAECgEIAgAAAA==.',
Se='Sedelis:BAAANQAECgUJBwAAAA==.Selaya:BAAANQADCgUJCgAAAA==.Serafín:BAAANQAECgUJDAAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQADCgUICQAAAA==.Shadownutt:BAAANQAECgEJAQAAAA==.Shieldwall:BAAANQAECgIIAwAAAA==.',
Si='Silanah:BAAANQAECgEIAQABNQAECggIFwAGAI8gAA==.Silveroaks:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.',
So='Somavra:BAAANQAECgQJBgAAAA==.Sopidia:BAAANQAECgMJBAAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAAANQAECgQICQAAAA==.Spiritomb:BAAANQAECgUJBQAAAA==.Spúdd:BAAANQAECgUICQAAAA==.',
St='Stamavan:BAAANQAECgYJDQAAAA==.',
Su='Sunari:BAAANQADCgcIBwAAAA==.Supermelon:BAAANQAECgQJBQAAAA==.',
Sy='Syena:BAAANQADCgIJAgAAAA==.Sylvanaria:BAAANQAECgUJDAAAAA==.Systyx:BAAANQADCgQJBAABNQAECgQIBgADAAAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAAANQAECgYJDQAAAA==.',
Th='Thaneer:BAAANQADCgQIBAAAAA==.Throstmok:BAAANQAECgcIEAAAAA==.Thumbalina:BAAANQADCgYIBgABNQAECgYIDgADAAAAAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tilingo:BAAANQADCgYIBwAAAA==.',
To='Tongra:BAAANQADCgQJBAABNQAECgUICQADAAAAAA==.Torg:BAAANQAECgYJDgAAAA==.Torgin:BAAANQADCgYJBgAAAA==.',
Tr='Trinitea:BAAANQADCgEIAQAAAA==.',
Tu='Turgies:BAAANQAECgYIDgAAAA==.Turgroka:BAAANQAECgEJAgAAAA==.',
Ub='Ubaubajuana:BAAANQAECgcIEQAAAA==.',
Ul='Ulfast:BAAANQAECgUJDAAAAA==.',
Va='Vannhellsing:BAAANQAECgQJBQAAAA==.Vanyel:BAAANQAECgYJEQAAAA==.',
Ve='Vemal:BAAANQAECgYIDwAAAA==.',
Vi='Vidula:BAAANQADCgEIAQAAAA==.Vigorous:BAAANQAECgQJCAAAAA==.',
Vo='Vociferoy:BAAANQAECgUJDAAAAA==.Voidsteffan:BAAANQAECgUJCQAAAA==.',
Vv='Vv:BAACNQAFFIEWAAMQAAcKqSIaAADzAgAQAAcKTyIaAADzAgAPAAUKmhwjAwCzAQA1AAQKgSIAAxAACQqmJj8GAFUDABAACQqmJj8GAFUDAA8ABQpKJP4mANcBAAAA.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAECgkJJQARADMkAA==.',
Xa='Xalzi:BAAANQADCgEIAQABNQAECgQIBAADAAAAAA==.',
Xu='Xul:BAAANQABCggICgAAAA==.',
Xy='Xyphër:BAAANQADCgQIBAABNQAECgQJBAADAAAAAA==.',
Za='Zannytoes:BAAANQAECgYJDQAAAA==.',
Zi='Zie:BAAANQAECgYJEAAAAA==.',
['Ñi']='Ñice:BAABNQAECoErAAMSAAkKdST4AQAFAwAHAAgK3CMhFwAtAwASAAgK/CH4AQAFAwAAAA==.',
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
