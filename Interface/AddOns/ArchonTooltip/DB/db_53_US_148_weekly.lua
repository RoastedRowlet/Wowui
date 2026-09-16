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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','Warrior-Arms','Mage-Frost','Mage-Arcane','Unknown-Unknown','Warlock-Destruction','Evoker-Preservation','Rogue-Subtlety','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Priest-Shadow','Paladin-Retribution','Warrior-Fury','Druid-Balance','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Elemental','Druid-Restoration','Monk-Windwalker','DemonHunter-Vengeance','Shaman-Enhancement','Paladin-Protection','Priest-Discipline','Shaman-Restoration','Priest-Holy','Monk-Mistweaver','DeathKnight-Frost',}
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acacia:BAAANQADCgcIDAAAAA==.',
Ag='Agave:BAAANQAECgMIBAAAAA==.',
Ai='Aizun:BAABNQAECoEUAAMBAAgJ8iBWCgARAwABAAgJ8iBWCgARAwACAAcJkBL1MgCxAQAAAA==.',
Ak='Akulagos:BAAANQAECgQIBQAAAA==.',
Al='Alakavahm:BAAANQADCgQIBAAAAA==.Aldenfire:BAAANQADCgMIAwAAAA==.Alesce:BAABNQAECoEiAAIDAAkJwxDxPQA/AgADAAkJwxDxPQA/AgAAAA==.Alii:BAAANQAECgEIAQAAAA==.',
Am='Amaraukyou:BAAANQADCgEIAQAAAA==.Amenadiel:BAAANQAECgUICwAAAA==.Amythistle:BAAANQADCgYIFgAAAA==.',
An='Andrü:BAAANQAECgcIDQAAAA==.',
Ap='Apsalar:BAAANQADCgQIBAAAAA==.',
Ar='Arnblass:BAAANQAECgQICAAAAA==.',
As='Ascend:BAAANQAECgQIBgAAAA==.Ashtana:BAAANQAECgIIAgAAAA==.Ashtar:BAAANQAECgYIDgAAAA==.',
Au='Aurora:BAAANQADCgcIBwAAAA==.',
Av='Aviee:BAABNQAECoEYAAMEAAgJwBssCACSAQAFAAYJxReVdgDkAQAEAAUJsyAsCACSAQAAAA==.',
Ax='Axidin:BAAANQAECgEIAQAAAA==.',
Az='Azushi:BAAANQADCggIEwABNQAECgkJIgADAHgZAA==.',
Ba='Babyfox:BAAANQADCgMIAwAAAA==.Babymage:BAABNQAECoEcAAIFAAgJAw6sbgD7AQAFAAgJAw6sbgD7AQAAAA==.Badform:BAAANQAECgIIAgAAAA==.Badkitteh:BAAANQADCgYIDAAAAA==.Baelstrom:BAAANQADCgIIAgABNQAECggIDgAGAAAAAA==.Baendron:BAAANQAECgYIDAAAAA==.Bahcrypt:BAAANQADCgYIDAAAAA==.Bahnna:BAAANQADCgQIBAAAAA==.Bakaris:BAAANQADCgUIBQAAAA==.Barbarik:BAAANQAECgcIDgABNQAECgkJIAAHAGkcAA==.Barberry:BAAANQADCgQIBAABNQAECggIHAAIAD0lAA==.Baretwallace:BAAANQADCggICQABNQAECgkJGQAJAJEhAA==.Battlereaddy:BAAANQADCggICAAAAA==.Bayesian:BAAANQABCgIIAgAAAA==.',
Be='Beefwildfire:BAAANQADCggIDQAAAA==.Beercheer:BAAANQADCgUIEAAAAA==.Beertholomew:BAAANQAECgMIBAAAAA==.Beestkyn:BAAANQADCgUIBQAAAA==.Behodakhtala:BAAANQADCgYIFQAAAA==.Bellanzo:BAAANQAECgYICwAAAA==.Bellawaifu:BAAANQABCgQIBAAAAA==.',
Bi='Bigzee:BAEBNQAECoEcAAMKAAgJwBnMAgA7AgAKAAcJOxvMAgA7AgALAAQJZgy6hQDgAAAAAA==.Bindanini:BAAANQADCgQIBAABNQADCgYIFgAGAAAAAA==.',
Bl='Blargin:BAAANQADCgIIAgAAAA==.Blorgin:BAACNQAFFIEGAAMJAAUJyhfcAgB7AQAJAAQJOhXcAgB7AQAMAAEJDSJYBgBnAAA1AAQKgSIAAwkACQkdJIcCAGkDAAkACAlRJYcCAGkDAAwAAwkHIGEpABgBAAAA.Bluntmàn:BAAANQAECgQICQAAAA==.',
Bo='Boogieman:BAAANQADCgYIBgAAAA==.Boohwodoy:BAAANQADCgcIBwAAAA==.Bookers:BAAANQAECgYICgAAAA==.Booplzs:BAAANQADCgUIBQAAAA==.Borgo:BAAANQADCgIIAgABNQAECgUICgAGAAAAAA==.Boulangerie:BAACNQAFFIEIAAINAAUJMhZpAQDGAQANAAUJMhZpAQDGAQA1AAQKgSIAAg0ACQlrJAgBAM0DAA0ACQlrJAgBAM0DAAAA.Boulior:BAAANQAECgIIBAAAAA==.Bowvice:BAEANQADCgUIBQABNQAECgkJHwAOAFEfAA==.Boyd:BAABNQAECoEaAAMPAAgJwxnbAwBBAgAPAAcJ5hvbAwBBAgADAAEJzwos0QA+AAAAAA==.',
Br='Brewmungandr:BAAANQADCggIEgAAAA==.Bromayzo:BAAANQABCgIIAgAAAA==.',
Ca='Canadatrash:BAAANQAECgEIAgABNQAECgkJGQAJAJEhAA==.Carraway:BAABNQAECoEYAAIQAAgJ+hTrHgBDAgAQAAgJ+hTrHgBDAgAAAA==.Cashewz:BAAANQADCgQIBAAAAA==.',
Ce='Ceasarsalad:BAABNQAECoEfAAMLAAkJThqqFgCuAgALAAkJlReqFgCuAgAHAAcJtRNKDAAIAgAAAA==.Ceazitt:BAAANQAECgQIBQAAAA==.Ceazyweasley:BAAANQAECgMIAwABNQAECgQIBQAGAAAAAA==.Ceci:BAAANQABCgMIAwAAAA==.Celestriå:BAAANQADCgYIEAAAAA==.Cetana:BAABNQAECoEZAAMJAAkJkSFnEAAoAgAJAAYJCiBnEAAoAgAMAAQJFyCVHwB0AQAAAA==.',
Ch='Chadlockb:BAACNQAFFIEGAAQHAAUJeRrDAwC9AAAHAAIJBBnDAwC9AAALAAIJ6h5vCgC8AAAKAAEJfxQMBABSAAA1AAQKgR0AAwsACQkHI94YAJ4CAAsABwknIt4YAJ4CAAcABQlFIwQPAOMBAAAA.Cheesee:BAAANQAECgUIDgAAAA==.Chiko:BAAANQAECgIIAwAAAA==.Christlike:BAAANQADCgcIBwAAAA==.Chronite:BAAANQAECgUICgAAAA==.Chucho:BAAANQADCgYIBgAAAA==.Chárgers:BAAANQADCggIGgAAAA==.',
Ci='Cindr:BAABNQAECoEgAAMRAAkJkiNMAQCYAwARAAkJeCNMAQCYAwASAAUJSxmgCQAEAQAAAA==.Circumstance:BAAANQAECgUIBQAAAA==.',
Cl='Cleattus:BAAANQAECgQICAAAAA==.',
Co='Coconutsteve:BAAANQADCggICAAAAA==.Colddblooded:BAAANQAECgQIDAAAAA==.Cololol:BAACNQAFFIEHAAITAAUJ+CAxAQAEAgATAAUJ+CAxAQAEAgA1AAQKgSEAAhMACQnPJcgAAN8DABMACQnPJcgAAN8DAAAA.Compcomp:BAAANQAECgMIBAAAAA==.Compi:BAAANQAECgEIAQABNQAECgMIBAAGAAAAAA==.Cooper:BAAANQAECgYIDAAAAA==.Corlys:BAAANQAECgYIDAAAAA==.',
Cr='Crew:BAABNQAECoEkAAMUAAkJHiOYBABnAwAUAAkJHiOYBABnAwATAAEJoww3SQA+AAAAAA==.Critflicker:BAAANQADCgYIBgAAAA==.Cronoz:BAAANQAECgUIDAAAAA==.',
Cu='Cucokai:BAAANQAECgIIAgAAAA==.Cuddles:BAAANQAECgMIAwAAAA==.Cuddlestomp:BAACNQAFFIEHAAMVAAUJsRbrAgClAQAVAAUJ3xTrAgClAQAWAAIJIBgOCgCnAAA1AAQKgSIAAxUACQmFIjUGADQDABUACAkVJDUGADQDABYABgnCEXNbAI0BAAAA.',
Cz='Czernabog:BAAANQAECgYIBwAAAA==.',
['Cä']='Cämulos:BAAANQAECgQIBwAAAA==.',
['Cí']='Círí:BAEANQAECgIIAgABNQAECgcIDQAGAAAAAA==.',
Da='Dabbosh:BAAANQAECgQIBAAAAA==.Dahl:BAAANQAECgQIBwABNQAECgcIDwAGAAAAAA==.Damnhammer:BAAANQAECgcIEgAAAA==.Dandie:BAAANQADCgYIBgAAAA==.Darthjinwoo:BAAANQAECggIEAAAAA==.Darthmerlin:BAAANQADCgQIBAABNQAECggIEAAGAAAAAA==.Dasakko:BAAANQAECgMIAwABNQAECggIGQACAMIWAA==.Dasmonko:BAAANQADCggIDAABNQAECggIGQACAMIWAA==.',
Db='Dbowzillaz:BAABNQAECoEZAAIVAAkJPiMQBABnAwAVAAkJPiMQBABnAwAAAA==.',
De='Deathskeeper:BAAANQADCgYIDAAAAA==.Demithania:BAAANQADCggIDAAAAA==.Demonhunterl:BAAANQAECgUICAAAAA==.Denden:BAAANQADCgUIBQAAAA==.',
Dh='Dhsil:BAAANQADCggIDgABNQAECgYICwAGAAAAAA==.',
Di='Diabòlic:BAACNQAFFIEGAAMLAAUJ/gcuCQDUAAALAAMJTwYuCQDUAAAHAAIJhAqqBgCoAAA1AAQKgSAABAsACQlPH0EUAL8CAAsACAk3HkEUAL8CAAcABAlBGtYdAE0BAAoAAQnjBkkeADMAAAAA.Dirtydiana:BAAANQAECgYIDQAAAA==.',
Dj='Djavol:BAAANQAECggIDgAAAA==.',
Do='Doc:BAAANQADCgYIEAAAAA==.Doguntarth:BAABNQAECoEiAAIDAAkJeBkvIgDKAgADAAkJeBkvIgDKAgAAAA==.',
Dr='Drafi:BAAANQADCgIIAgABNQAECgEIAgAGAAAAAA==.Drankincup:BAACNQAFFIEHAAIXAAUJEQ/PAgCZAQAXAAUJEQ/PAgCZAQA1AAQKgSUAAhcACQlHHq0KAEgDABcACQlHHq0KAEgDAAAA.Drankinkup:BAAANQADCgIIAgABNQAFFAUIBwAXABEPAA==.Drstagger:BAEANQAECgcIEgAAAA==.',
Du='Dullahan:BAAANQADCgQIBAAAAA==.Durotann:BAAANQAECgQIBgAAAA==.Dusios:BAAANQADCggIFgAAAA==.Duskflower:BAABNQAECoEaAAIYAAkJbxljBwDTAgAYAAkJbxljBwDTAgAAAA==.',
El='Elexandur:BAAANQAECgcIDgAAAA==.Elissa:BAAANQADCgYIBgAAAA==.Eliänna:BAAANQADCgIIAgAAAA==.Elleri:BAAANQAECgMIBwAAAA==.',
Ep='Epnokicks:BAABNQAECoEbAAIZAAkJGh9fBgANAwAZAAkJGh9fBgANAwAAAA==.',
Er='Eroicel:BAABNQAECoEfAAIaAAkJhRb4AgB/AgAaAAkJhRb4AgB/AgAAAA==.',
Ev='Evarielle:BAAANQAECgQIBgABNQAECgkJHwAaAIUWAA==.',
Fa='Faalindh:BAAANQAECgQIBAAAAA==.Fadedhalo:BAAANQAECgMIBgAAAA==.Falaya:BAABNQAECoEfAAQHAAkJliTOBgB3AgAHAAYJlSTOBgB3AgALAAUJkiHBNwDzAQAKAAEJkyPwEwBhAAAAAA==.Falst:BAAANQAECgQICgAAAA==.Farion:BAAANQADCgUIBQAAAA==.',
Fe='Felyathas:BAAANQADCgMIAwABNQAECgMIAwAGAAAAAA==.Fennlar:BAAANQAECgYICwAAAA==.Fersos:BAAANQABCgMIAwAAAA==.',
Fl='Flakey:BAAANQABCgIIAgAAAA==.Flawlessxi:BAAANQAECgYIDgAAAA==.Flyntflosy:BAABNQAECoEXAAIXAAkJ3hluEwDjAgAXAAkJ3hluEwDjAgAAAA==.',
Fo='Fowl:BAAANQAECgcIDgAAAA==.Fowlie:BAAANQADCgIIAgAAAA==.',
Fr='Fragment:BAAANQABCgIIAwAAAA==.',
Fu='Fuehriån:BAABNQAECoEZAAIFAAkJ/hBJTQBkAgAFAAkJ/hBJTQBkAgAAAA==.Funstar:BAAANQADCgYIBgABNQAECgkJEgAIAGwZAA==.Furyess:BAAANQAECgcIEQAAAA==.',
Ga='Gaelsi:BAAANQAECgYIBQAAAA==.Galactic:BAAANQAECgUICAABNQAECgcIDgAGAAAAAA==.Galgore:BAAANQAECgcIDAAAAA==.Garolok:BAAANQAECgYIDAAAAA==.Gasandflames:BAAANQAECgYICwAAAA==.Gascans:BAAANQAECgUIDQAAAA==.Gazelle:BAEANQAECgYIDAAAAA==.Gazerakhan:BAAANQAECgMIBQABNQAECggIFgATAKkRAA==.Gazerielle:BAABNQAECoEWAAITAAgJqREpGAApAgATAAgJqREpGAApAgAAAA==.',
Ge='Gerpsters:BAAANQABCgQIBAAAAA==.',
Gl='Glizzylizzy:BAABNQAECoEaAAIbAAgJtiJLAwAhAwAbAAgJtiJLAwAhAwAAAA==.',
Go='Gothgrippers:BAAANQAECgMIAwAAAA==.Gowownage:BAAANQAECgcIDgAAAA==.',
Gr='Gradeus:BAABNQAECoEhAAIOAAkJpx1iFQD2AgAOAAkJpx1iFQD2AgAAAA==.Granddh:BAABNQAECoEeAAIUAAkJuyQBAgC2AwAUAAkJuyQBAgC2AwAAAA==.Graydius:BAAANQADCgQIBAAAAA==.Greenmango:BAAANQADCggIDAAAAA==.Grimeclipse:BAAANQAECgQIBgAAAA==.Grovehart:BAAANQAECgQIBAAAAA==.Grumpin:BAAANQADCgUIBQABNQADCggIEAAGAAAAAA==.Grumpoo:BAAANQADCggIEAAAAA==.',
Gu='Gurt:BAAANQADCgUIBQAAAA==.Gutz:BAAANQAECgUIBQAAAA==.',
Ha='Haku:BAAANQAECgQIBAAAAA==.Halestorm:BAAANQADCggIDAAAAA==.Hattori:BAAANQABCgUIBgAAAA==.Havefun:BAAANQAECgcIEQABNQAECgkJEgAIAGwZAA==.',
He='Hedonist:BAAANQAECgcIBwABNQAECgkJIAAHAGkcAA==.Hellsbringer:BAAANQAECgQICAAAAA==.Heretik:BAAANQAECgQIBwAAAA==.Hevnoraak:BAAANQAECgQIBQAAAA==.',
Ho='Hogun:BAAANQADCgQIBAAAAA==.Hold:BAABNQAECoEcAAMTAAkJth+zBQBSAwATAAkJth+zBQBSAwAUAAIJSg8lQwB7AAAAAA==.Holycandi:BAAANQAECgIIBAAAAA==.Holycaru:BAAANQADCgcIBwAAAA==.Holydoyle:BAAANQAECgYICwAAAA==.Holyho:BAAANQAECgcIDQAAAA==.Holyjuice:BAAANQAECgQICAAAAA==.Hotpøcket:BAAANQAFFAEIAQAAAA==.',
Hu='Huntlzs:BAAANQAECgYIDgAAAA==.',
Hy='Hyperìen:BAECNQAFFIEHAAIcAAUJqxNPAQCDAQAcAAUJqxNPAQCDAQA1AAQKgSIAAhwACQlVJFMBAKEDABwACQlVJFMBAKEDAAAA.',
['Hø']='Hølý:BAAANQAECgcIBwAAAA==.',
Ic='Icedoggi:BAAANQAECgYICwAAAA==.',
Im='Immortalmage:BAAANQADCgYIBgAAAA==.Imsopro:BAAANQABCgIIAgAAAA==.',
In='Indeed:BAAANQAECgcIEgAAAA==.Inferna:BAAANQADCgUIBQAAAA==.Innerbeast:BAAANQAECgQIBAABNQAFFAYIDwAdAJgiAA==.Intiq:BAAANQADCgIIAgAAAA==.',
Ir='Irbaboon:BAAANQAECgcIDQAAAA==.Irreletaur:BAABNQAECoEhAAIDAAkJkBn6JQC0AgADAAkJkBn6JQC0AgAAAA==.',
It='Itisovernow:BAAANQADCgUICQABNQADCgYICQAGAAAAAA==.Itsevokernow:BAAANQADCgUIBQABNQADCgYICQAGAAAAAA==.Itsovernow:BAAANQADCgYICQAAAA==.',
Iz='Izimir:BAAANQAECgUICQAAAA==.',
Ja='Jamloo:BAAANQAECgUIBQAAAA==.Jangokin:BAABNQAECoEYAAIQAAkJ2hwyEwDEAgAQAAkJ2hwyEwDEAgAAAA==.Jayiasan:BAAANQAECgMIAwABNQAECgkJIwAFAP0jAA==.Jazz:BAAANQADCgUICQAAAA==.',
Je='Jermz:BAAANQADCgEIAQAAAA==.',
Ji='Jimbaha:BAAANQAECgMIAwAAAA==.Jinks:BAAANQADCgYIDAAAAA==.',
['Jè']='Jèrmz:BAAANQADCgYICQAAAA==.',
Ka='Kabang:BAAANQAECgUIDQAAAA==.Kachoo:BAABNQAECoEaAAIbAAkJAxkBBAAAAwAbAAkJAxkBBAAAAwAAAA==.Kaige:BAAANQAECgEIAwAAAA==.Kalithor:BAAANQAECgMIAwAAAA==.Kathoes:BAAANQAECgQIBQAAAA==.',
Ke='Kelennin:BAAANQADCgIIAgAAAA==.Kellwildfire:BAAANQAECgYIEAAAAA==.',
Kf='Kfish:BAAANQAECgEIAQAAAA==.',
Kh='Khamael:BAAANQAECgQIBgAAAA==.Kheiron:BAABNQAECoEUAAIVAAYJOhkrHgC2AQAVAAYJOhkrHgC2AQAAAA==.',
Ki='Kinu:BAABNQAECoEYAAIeAAkJTCDtBQBXAwAeAAkJTCDtBQBXAwAAAA==.Kissmytotems:BAAANQADCgUIBQABNQAECgEIAQAGAAAAAA==.Kitane:BAAANQAECgIIAwAAAA==.',
Kl='Klarina:BAAANQAECgYIDAAAAA==.',
Kn='Knox:BAAANQAECgEIAQAAAA==.',
Ko='Kobieta:BAAANQADCggICAAAAA==.Koda:BAAANQADCgYICgAAAA==.Kosolapaya:BAAANQADCgIIAgAAAA==.Kotharsevant:BAAANQADCgcIBwAAAA==.',
Ku='Kurolion:BAAANQAECgcIDwAAAA==.Kurzon:BAAANQADCgEIAQAAAA==.',
Kw='Kwanrbless:BAAANQADCgIIAgAAAA==.',
Ky='Kyblade:BAAANQAECgYIDAAAAA==.',
['Kø']='Køs:BAABNQAECoEOAAQLAAcJngmxWABqAQALAAcJ8QexWABqAQAKAAEJ1g2hGgA/AAAHAAEJ2w27WgA6AAAAAA==.',
La='Lampro:BAAANQADCggIDAABNQAECggIHAALAFMcAA==.Lavajato:BAAANQADCgYICQABNQAECgIIBQAGAAAAAA==.',
Le='Leemius:BAAANQAECgQIBgAAAA==.Leosbryn:BAAANQAECgYIDAAAAA==.Leviträ:BAAANQADCgUIBQAAAA==.',
Li='Liable:BAAANQAECgUICAAAAA==.Ligmadeebliz:BAAANQAECgYIDwAAAA==.Lilfister:BAAANQAECgEIAQABNQAECgcIEgAGAAAAAA==.Lilraz:BAAANQADCgYIBgAAAA==.Liltazzvert:BAAANQAECgYIDgAAAA==.Linksded:BAAANQADCgEIAQAAAA==.Listerfyne:BAAANQADCgcIAgAAAA==.Littlepain:BAAANQADCgEIAQAAAA==.',
Lu='Lucero:BAAANQAECgIIAwAAAA==.',
Ly='Lyra:BAAANQADCgUIBgABNQAECgEIAQAGAAAAAA==.',
['Lû']='Lûpy:BAAANQADCgUIBQABNQABCgQIBgAGAAAAAA==.',
Ma='Mabey:BAAANQAECgEIAQAAAA==.Maerron:BAAANQAECgMIBQAAAA==.Mafi:BAAANQABCgUIBQAAAA==.Mageblprows:BAAANQADCgcIFAAAAA==.Mangemonpain:BAAANQADCgcIDQABNQAECgMIAwAGAAAAAA==.Maraayla:BAAANQADCggICAAAAA==.Matikz:BAABNQAECoEfAAIJAAkJ9R1UBQAFAwAJAAkJ9R1UBQAFAwAAAA==.Maximages:BAAANQADCggIDwAAAA==.Maximon:BAAANQAECgUIBwAAAA==.Maylla:BAAANQADCgcIDgAAAA==.',
Me='Meddle:BAABNQAECoEeAAIfAAkJiyKJCgAGAwAfAAkJiyKJCgAGAwAAAA==.Mehrunesd:BAAANQAECgUIBwAAAA==.Meowwmix:BAAANQABCgIIAgAAAA==.Merrydeath:BAAANQADCgYICQAAAA==.Meyea:BAABNQAECoEiAAICAAkJrCWGAQDTAwACAAkJrCWGAQDTAwAAAA==.',
Mi='Miller:BAABNQAECoEYAAIWAAkJHR2nCwAjAwAWAAkJHR2nCwAjAwAAAA==.Millyvoid:BAAANQADCgcIBwABNQAECgkJGAAWAB0dAA==.Miru:BAAANQADCgYIFgAAAA==.Mitis:BAAANQADCgQIBAAAAA==.Mizdems:BAAANQAECgUICwAAAA==.',
Mo='Moistjustice:BAAANQAECgIIAgAAAA==.Moonfun:BAAANQADCgcICgABNQAECgkJEgAIAGwZAA==.Moufon:BAAANQADCgYIEAAAAA==.',
My='Myrodragon:BAAANQAECgQIBAAAAA==.',
['Mé']='Mércy:BAAANQAECgUIDAAAAA==.',
Na='Navah:BAAANQAECgIIAgAAAA==.',
Ne='Neandratroll:BAAANQAECgQICAAAAA==.Necrodis:BAAANQAECgEIAQABNQAECgcIDwAGAAAAAA==.Nezemzy:BAAANQADCgUIBQABNQAECgMIAwAGAAAAAA==.',
Ni='Nightlevels:BAABNQAECoEZAAMfAAkJ0hlzFwCJAgAfAAkJ0hlzFwCJAgANAAMJchORMQDEAAAAAA==.',
No='No:BAAANQADCgcIBwAAAA==.Nodens:BAAANQADCgQIBAAAAA==.Nogardd:BAAANQAECgYIDAAAAA==.Notpetya:BAAANQAECgIIAwAAAA==.Nottills:BAAANQADCgYIDAAAAA==.',
Nu='Nudleboi:BAAANQADCgUIBQAAAA==.Nuulruk:BAAANQAECgMIAwAAAA==.',
Ny='Nylaehh:BAAANQAECgEIAQAAAA==.Nyxtro:BAAANQAECgQIBAAAAA==.',
Oi='Oilslick:BAAANQAECgUICwAAAA==.',
Om='Ombrure:BAAANQAECgMIAwAAAA==.',
On='Onornu:BAABNQAECoEiAAIeAAkJEyTyAgCTAwAeAAkJEyTyAgCTAwAAAA==.',
Or='Orlidan:BAAANQAECgYIDgAAAA==.',
Ot='Oth:BAABNQAECoEWAAIfAAkJRyZ5AADcAwAfAAkJRyZ5AADcAwAAAA==.',
Ox='Oxylock:BAABNQAECoEiAAMLAAkJ4x9bBwA4AwALAAkJ4x9bBwA4AwAHAAcJKQeCHwA+AQAAAA==.',
Pa='Palgeron:BAAANQADCgIIAgAAAA==.Pathlon:BAAANQADCgcIFAAAAA==.',
Pe='Peetypirate:BAAANQADCgYIBwAAAA==.Pekapow:BAABNQAECoEiAAIgAAkJ9xGCCwAoAgAgAAkJ9xGCCwAoAgAAAA==.Peta:BAAANQAECgEIAQAAAA==.',
Ph='Phobius:BAABNQAECoEcAAICAAgJhBcEHgBLAgACAAgJhBcEHgBLAgAAAA==.',
Pi='Pinkmango:BAABNQAECoEZAAMCAAgJwhaeHQBPAgACAAgJwhaeHQBPAgAhAAEJJAaFUAA0AAAAAA==.Pireyne:BAAANQADCgYICgAAAA==.Pistachioz:BAAANQAECgUICwAAAA==.',
Pl='Playfultouch:BAAANQADCgcIEwAAAA==.Plunkaplunk:BAAANQADCgYICwAAAA==.',
Po='Polymorphine:BAAANQAECgIIAgAAAA==.Poonanypie:BAAANQAECgQIBAAAAA==.Poonzer:BAEBNQAECoEfAAIOAAkJUR8xEQAYAwAOAAkJUR8xEQAYAwAAAA==.Porosity:BAAANQAECgYIDAAAAA==.',
Pr='Pretreckless:BAAANQADCgEIAQAAAA==.Proudclod:BAAANQAECgEIAgAAAA==.',
Qe='Qetesh:BAAANQADCggIDwAAAA==.',
Ra='Ragnan:BAAANQADCgYICwAAAA==.Rain:BAAANQADCgUIBQABNQAECgYIDAAGAAAAAA==.Ralinis:BAAANQADCgYIDAABNQADCgUIBQAGAAAAAA==.Rathi:BAAANQAECgIIAwABNQAECgcIDQAGAAAAAA==.Ravicavasar:BAAANQADCgYICgAAAA==.Rawrschak:BAAANQADCgIIAgAAAA==.Razfu:BAABNQAECoEcAAIgAAgJTiGKBAABAwAgAAgJTiGKBAABAwAAAA==.Razul:BAAANQADCggIDAAAAA==.Razzio:BAAANQADCgQIBAAAAA==.',
Re='Redharvest:BAAANQAECgUICgAAAA==.Rekles:BAAANQADCgUIBQABNQAECgcIDgAGAAAAAA==.Relentless:BAAANQADCggIHAAAAA==.Retribution:BAAANQAECgUICAAAAA==.Reznoop:BAEANQAECgQIBgABNQAECgkJHwAOAFEfAA==.',
Ri='Richardtwist:BAAANQADCgYIFgAAAA==.',
Rk='Rkoo:BAAANQAECgMIAwAAAA==.',
Ro='Roobee:BAAANQABCgEIAQABNQADCgYICgAGAAAAAA==.Roxzor:BAAANQAECgQIBgABNQAECgcIDQAGAAAAAA==.Royok:BAAANQAECgYIDgAAAA==.',
Ru='Ruwey:BAAANQABCgIIAgAAAA==.',
Sa='Saenys:BAAANQADCggIBwAAAA==.Sakardi:BAAANQAECgUIBwAAAA==.Sawedoff:BAAANQAECgYIDwAAAA==.',
Sc='Scalybum:BAAANQAECgQIBAAAAA==.Scamall:BAAANQAECgEIAQAAAA==.Schizophreni:BAAANQAECgcIEAABNQAFFAUICAANADIWAA==.Scionoffury:BAAANQAECgQIBAAAAA==.Scotcolumbus:BAAANQAECgcIDwAAAA==.Scullcrusher:BAAANQABCggICwAAAA==.',
Se='Secsysalad:BAAANQAECgQICQABNQAECgkJHwALAE4aAA==.Seefoo:BAAANQAECgIIAgAAAA==.Sekhy:BAAANQAECgEIAQAAAA==.Sero:BAAANQAECgQIBgAAAA==.Serrafir:BAAANQADCgEIAQAAAA==.',
Sg='Sgsmagicman:BAAANQADCgcIEwABNQAECgEIAQAGAAAAAA==.',
Sh='Shaamwow:BAAANQAECgQIBgAAAA==.Shade:BAABNQAECoEcAAIJAAgJqRGRDgBEAgAJAAgJqRGRDgBEAgAAAA==.Shadoewolfe:BAAANQADCgYIDAAAAA==.Shageron:BAABNQAECoEhAAMVAAkJ6iF2CQD1AgAVAAkJWSF2CQD1AgAWAAkJ4A+uQwDoAQAAAA==.Shalladin:BAAANQADCgMIAwAAAA==.Shallshock:BAAANQAECgYIDQAAAA==.Shandoe:BAAANQADCgQIBAAAAA==.Shankspec:BAABNQAECoEZAAIMAAgJ8h9TBwDfAgAMAAgJ8h9TBwDfAgAAAA==.Shaolinshamy:BAAANQAECgQIBQAAAA==.Shifterxmag:BAAANQAECgYIDgAAAA==.Shikaca:BAAANQADCgYIDgAAAA==.Shinseina:BAAANQAECgYIDAAAAA==.Shockbite:BAAANQADCgUIBQAAAA==.Shockinawe:BAAANQADCgMIAwAAAA==.Short:BAAANQADCgIIAgAAAA==.Shämash:BAAANQAECgQICQAAAA==.Shöck:BAAANQAECgIIAwAAAA==.',
Si='Sicastic:BAAANQAECgQIBAABNQAECgUIDAAGAAAAAA==.Siccness:BAAANQAECgUIDAAAAA==.Sieben:BAAANQAECgEIAgAAAA==.Siic:BAAANQADCgYIBgABNQAECgUIDAAGAAAAAA==.Sindrex:BAABNQAECoEcAAIIAAgJPSWRAgBiAwAIAAgJPSWRAgBiAwAAAA==.',
Sk='Skwerl:BAAANQADCgMIAwAAAA==.',
Sl='Slurmage:BAAANQAECgYIDAAAAA==.',
Sm='Smittywerben:BAAANQAECgYICAAAAA==.Smokfun:BAABNQAECoESAAMIAAkJbBn4BgDjAgAIAAkJbBn4BgDjAgASAAUJtQnpCgDcAAAAAA==.Smooshi:BAABNQAECoEpAAMbAAkJLx70BwB0AgAbAAcJqxv0BwB0AgAeAAkJxBbDIQBQAgAAAA==.',
Sn='Sneaktarts:BAAANQADCggICAABNQAECggIFgATAKkRAA==.',
So='Sololeveling:BAAANQAECgUICwAAAA==.Sootor:BAAANQADCgYICwAAAA==.',
Sp='Spags:BAAANQAECgEIAQABNQAECgYICwAGAAAAAA==.Sparklefarts:BAAANQADCgYIBgAAAA==.Spewky:BAAANQADCgEIAQAAAA==.',
St='Starfun:BAAANQAECgIIAgABNQAECgkJEgAIAGwZAA==.Steelheals:BAAANQADCgQIBQAAAA==.Stenzwar:BAAANQAECgEIAQABNQAECgkJIgACAKwlAA==.Stevensiegal:BAAANQADCgIIAgAAAA==.Stormbless:BAABNQAECoEfAAIZAAkJTBRcDQBsAgAZAAkJTBRcDQBsAgAAAA==.Stormfallz:BAAANQAECgcIDwAAAA==.',
Su='Superfrenzy:BAAANQADCgMIAwAAAA==.Supertotemz:BAAANQAECgEIAQAAAA==.Supervoid:BAAANQAECgIIAgABNQAECgcIDgAGAAAAAA==.',
Sw='Swag:BAAANQADCggICgABNQAECgUIBQAGAAAAAA==.Sweegie:BAAANQAECgQICAAAAA==.Sweegz:BAAANQADCgYIBgAAAA==.Sweetlou:BAAANQADCggICAAAAA==.',
Sy='Syds:BAAANQAECgQIBgAAAA==.Synapticzion:BAAANQAECgcICAAAAA==.',
['Sí']='Sílk:BAAANQADCgcIEgAAAA==.',
Ta='Taara:BAAANQAECgcIEQAAAA==.Takeshi:BAAANQABCgIIAgAAAA==.Takkana:BAABNQAECoEYAAIOAAgJySVPCAB1AwAOAAgJySVPCAB1AwAAAA==.Tamped:BAAANQADCgQIBAAAAA==.Tatsuki:BAAANQABCgIIBAAAAA==.',
Te='Terk:BAACNQAFFIEHAAIbAAUJpxB3AADEAQAbAAUJpxB3AADEAQA1AAQKgSIABBsACQnwJKAAAMQDABsACQnwJKAAAMQDABcAAQkRJOGgAGMAAB4AAQlkA1y/ACkAAAAA.',
Th='Thalrymere:BAAANQAECgUICQAAAA==.Theory:BAAANQABCgEIAQAAAA==.Thiccerlegs:BAAANQADCgYIDgAAAA==.',
Ti='Tidebeard:BAABNQAECoEdAAIeAAkJzCBTCgAaAwAeAAkJzCBTCgAaAwAAAA==.Tikz:BAAANQAECgYIDAAAAA==.',
To='Tock:BAABNQAECoEnAAMbAAkJ3B0zAgBXAwAbAAkJtB0zAgBXAwAXAAYJZhHITQByAQAAAA==.Tokenwarrior:BAAANQAECgIIAwAAAA==.Touchmychuby:BAAANQAECgIIAgAAAA==.',
Tr='Tralina:BAAANQADCgMIAwABNQAECgkJIwAFAP0jAA==.Trapstâr:BAACNQAFFIEHAAIVAAYJPwhlAgC7AQAVAAYJPwhlAgC7AQA1AAQKgRUAAhUACQl2GbEKAOECABUACQl2GbEKAOECAAAA.',
Ts='Tsarfun:BAAANQADCgQIBAABNQAECgkJEgAIAGwZAA==.Tsireya:BAAANQAECgUIBQAAAA==.Tsunayoshii:BAAANQAECgYICAAAAA==.',
Tu='Turf:BAAANQADCgUIBQAAAA==.',
Un='Undeadwaifu:BAAANQAECgQIBAAAAA==.Unkledeath:BAAANQAECgIIAwAAAA==.',
Va='Vaeryn:BAAANQADCggIHAAAAA==.Valesyrin:BAAANQAECgYIDAAAAA==.Vansapanda:BAAANQADCggIEAAAAA==.Vaughn:BAABNQAECoEeAAMPAAkJuBuzAQDiAgAPAAkJVBmzAQDiAgADAAkJCxN/LACRAgAAAA==.',
Ve='Veggieboi:BAAANQAECgQIBAAAAA==.Vellast:BAAANQAECgIIAgAAAA==.',
Vi='Viande:BAAANQADCgQIBAAAAA==.Victory:BAAANQAECgIIAwAAAA==.Vigilo:BAABNQAECoEcAAIZAAkJ3R5pBwD1AgAZAAkJ3R5pBwD1AgAAAA==.Vilhelmina:BAAANQAECgUIEAAAAA==.Viruzdk:BAABNQAECoEYAAQBAAgJIB/EGgBMAgABAAcJbhzEGgBMAgACAAYJCh4eKgDpAQAhAAIJFhkeOwCaAAAAAA==.',
Vl='Vlad:BAAANQAECgMICAAAAA==.Vladivostok:BAAANQADCgEIAQAAAA==.',
Wa='Wafi:BAAANQAECgEIAgAAAA==.Wamp:BAABNQAECoEcAAMLAAgJUxyiEwDEAgALAAgJUxyiEwDEAgAHAAEJcAybXAA3AAAAAA==.Warcheif:BAAANQADCgMIAwAAAA==.Warwonka:BAABNQAECoEcAAIVAAgJpxrGEQBpAgAVAAgJpxrGEQBpAgAAAA==.Watchurbeard:BAAANQAECgYIDAAAAA==.',
We='Weenrgulpr:BAAANQADCgYIDgAAAA==.',
Wh='Whamass:BAAANQAECgQIBwAAAA==.Whippy:BAAANQADCggICAABNQAECggIHAAIAD0lAA==.',
Wi='Windowlicker:BAAANQAECgcIDAAAAA==.Winnydafoo:BAAANQADCgQIBgAAAA==.',
Wr='Wrapfire:BAAANQAECgUIBwAAAA==.',
['Wí']='Wíldspirit:BAAANQADCgYICwAAAA==.',
['Xè']='Xèra:BAAANQADCggICAAAAA==.',
Ya='Yacob:BAACNQAFFIEHAAMFAAUJRSDABwCGAQAFAAQJrB7ABwCGAQAEAAEJrSafAQB1AAA1AAQKgSIAAwUACQnnI2cKAIwDAAUACQk/I2cKAIwDAAQABQnmIqYGAMUBAAAA.Yamarahj:BAABNQAECoEgAAQHAAkJaRxDBwBsAgAHAAgJ1xhDBwBsAgALAAgJzBm8KAA+AgAKAAIJrByQDgCkAAAAAA==.',
Yo='Yorikk:BAAANQAECgQIDQAAAA==.',
Yu='Yui:BAAANQABCgIIAgAAAA==.',
Za='Zaeo:BAAANQADCgcIBwAAAA==.Zafhir:BAAANQABCgUICAAAAA==.Zankanotachi:BAAANQAECgQICQAAAA==.Zarmaku:BAAANQAECgUICAAAAA==.Zartath:BAAANQADCgcIDgAAAA==.Zauber:BAACNQAFFIEIAAQKAAUJ8R02AAA3AQAKAAMJYSI2AAA3AQAHAAIJUSATAwDDAAALAAEJOg6pGQBOAAA1AAQKgSIABAoACQlcJhIAANkDAAsACQnfJXQAAOgDAAoACQlBJhIAANkDAAcABgnmJJsKACQCAAAA.Zazie:BAAANQAECgYIDAAAAA==.Zazu:BAAANQADCgIIAgAAAA==.',
Ze='Zepian:BAAANQAECgYICAAAAA==.',
Zi='Zirraj:BAACNQAFFIEHAAIDAAUJShLJBAClAQADAAUJShLJBAClAQA1AAQKgSIAAwMACQnMJXkCANcDAAMACQnMJXkCANcDAA8ABQl0GwEKAFgBAAAA.',
Zy='Zygon:BAAANQADCggICAABNQAECgcIDgAGAAAAAA==.',
['Âr']='Ârthilasi:BAAANQAECgQIBAAAAA==.',
['Èó']='Èówyn:BAAANQAECgQICAAAAA==.',
['Év']='Évié:BAEANQAECgcIDQAAAA==.',
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
