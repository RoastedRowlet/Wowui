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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','Warrior-Arms','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Mage-Frost','Mage-Arcane','Unknown-Unknown','Paladin-Holy','Warlock-Destruction','Evoker-Preservation','Rogue-Subtlety','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Druid-Balance','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Frost','Shaman-Elemental','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','DemonHunter-Vengeance','Druid-Guardian','Shaman-Enhancement','Priest-Discipline','Priest-Holy','Hunter-Survival','Monk-Mistweaver',}
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acacia:BAAANQADCgcIDAAAAA==.',
Ag='Agave:BAAANQAECgMIBAAAAA==.',
Ai='Aizun:BAABNQAECoEVAAMBAAkK0R9UCQA/AwABAAkK0R9UCQA/AwACAAcKkBIlPgCfAQAAAA==.',
Ak='Akulagos:BAAANQAECgQJBgAAAA==.',
Al='Alakavahm:BAAANQADCgQIBAAAAA==.Aldenfire:BAAANQADCgMJAwAAAA==.Alesce:BAABNQAECoElAAIDAAkKBRKrUwAeAgADAAkKBRKrUwAeAgAAAA==.Alii:BAAANQAECgEIAgAAAA==.',
Am='Amaraukyou:BAAANQADCgYJBwAAAA==.Amenadiel:BAAANQAECgUJEAAAAA==.Amythistle:BAAANQAECgEJAQAAAA==.',
An='Andrü:BAABNQAECoEXAAIDAAgKBBTtTQAyAgADAAgKBBTtTQAyAgAAAA==.Antiquated:BAAANQAECgIJAgAAAA==.',
Ap='Apsalar:BAAANQADCgQIBAAAAA==.',
Ar='Arcanetarts:BAAANQABCgMIBQABNQAECgkJHwAEAIgTAA==.Arnblass:BAAANQAECgUIDQAAAA==.',
As='Ascend:BAAANQAECgUJCwAAAA==.Ashtana:BAAANQAECgIIAgAAAA==.Ashtar:BAABNQAECoEZAAMFAAgKYg6aYgDWAQAFAAgKHQ6aYgDWAQAGAAMKiQfQOgB/AAAAAA==.',
Au='Aurora:BAAANQADCgcIBwAAAA==.',
Av='Aviee:BAABNQAECoEeAAMHAAgKJxxzCwCDAQAIAAYKThjdlwDcAQAHAAUKsyBzCwCDAQAAAA==.',
Ax='Axidin:BAAANQAECgMIBAAAAA==.',
Az='Azushi:BAAANQADCggJFQABNQAFFAUICQADALwHAA==.',
Ba='Babyfox:BAAANQADCgMIAwAAAA==.Babymage:BAABNQAECoElAAIIAAkKxROJVwCGAgAIAAkKxROJVwCGAgAAAA==.Badform:BAAANQAECgIIBAAAAA==.Badkitteh:BAAANQADCggIDwAAAA==.Baelstrom:BAAANQADCgIIAgABNQAECggIEwAJAAAAAA==.Baendron:BAAANQAECgcJEwAAAA==.Bahcrypt:BAAANQADCgYIDAAAAA==.Bahnna:BAAANQAECgEJAQAAAA==.Bakaris:BAAANQADCgUIBQAAAA==.Barbarik:BAABNQAECoEWAAIKAAgKsQmNUwCkAQAKAAgKsQmNUwCkAQABNQAECgkJJgALAPcfAA==.Barberry:BAAANQADCgQJBAABNQAECgkJJQAMAAwlAA==.Baretwallace:BAAANQAECgUJBQABNQAECgkJIgANACciAA==.Battlereaddy:BAAANQADCggICAAAAA==.Bayesian:BAAANQABCgIIAgAAAA==.',
Be='Beefwildfire:BAAANQADCggIDQAAAA==.Beercheer:BAAANQADCgUJEAAAAA==.Beertholomew:BAAANQAECgUICQAAAA==.Beestkyn:BAAANQAECgMIAwABNQAECgQIBAAJAAAAAA==.Behodakhtala:BAAANQADCgYIFQAAAA==.Bellanzo:BAAANQAECgcJEgAAAA==.Bellawaifu:BAAANQABCgQIBAAAAA==.',
Bi='Bigzee:BAEBNQAECoElAAMOAAkKGRhmBAAoAgAOAAcKOxtmBAAoAgAPAAYKog9JbgB5AQAAAA==.Bindanini:BAAANQADCgUICQABNQAECgEJAQAJAAAAAA==.',
Bl='Blargin:BAAANQADCgIJAgAAAA==.Blorgin:BAACNQAFFIELAAMNAAUKhR0gBACBAQANAAQKYxwgBACBAQAQAAEKDSI0CwBhAAA1AAQKgScAAw0ACQoOJYkDAFEDAA0ACApRJYkDAFEDABAABQpUH1QiAMYBAAAA.Bluntmàn:BAAANQAECgUIEQAAAA==.',
Bo='Boogieman:BAAANQADCgYIBgAAAA==.Boohwodoy:BAAANQADCgcIBwAAAA==.Bookers:BAAANQAECgcIDAAAAA==.Booplzs:BAAANQADCgUIBQAAAA==.Borgo:BAAANQADCgIIAgABNQAECgcIEgAJAAAAAA==.Boulangerie:BAACNQAFFIENAAIRAAUKsCGOAQD/AQARAAUKsCGOAQD/AQA1AAQKgSUAAhEACQoWJpQAAOgDABEACQoWJpQAAOgDAAAA.Boulight:BAAANQAECgMIAwAAAA==.Boulior:BAAANQAECgIIBAAAAA==.Bowvice:BAEANQADCgUIBQABNQAECgkJKAAFANoiAA==.Boyd:BAABNQAECoEjAAMSAAkKfRuAAwCgAgASAAgKkx2AAwCgAgADAAEKzwqk9AA8AAAAAA==.',
Br='Brewmungandr:BAAANQAECgUIBQAAAA==.Bromayzo:BAAANQABCgIJAgAAAA==.',
Ca='Canadatrash:BAAANQAECgEIAgABNQAECgkJIgANACciAA==.Carraway:BAABNQAECoEcAAITAAgKkxVwJwAtAgATAAgKkxVwJwAtAgAAAA==.Cashewz:BAAANQADCgQIBAAAAA==.',
Ce='Ceasarsalad:BAABNQAECoEoAAMPAAkKahxIFADwAgAPAAkKjhpIFADwAgALAAcKtRMQDgD6AQAAAA==.Ceazitt:BAAANQAECgUJCgAAAA==.Ceazyweasley:BAAANQAECgMIAwABNQAECgUJCgAJAAAAAA==.Ceci:BAAANQABCgMJAwAAAA==.Celestriå:BAAANQAECgEJAQAAAA==.Cetana:BAABNQAECoEiAAMNAAkKJyL5DgBXAgANAAYK2iL5DgBXAgAQAAQKZyG1KwB5AQAAAA==.',
Ch='Chadlockb:BAACNQAFFIEKAAQLAAUKtR2/BAC+AAAPAAIKFCFrEQDBAAALAAIK8h6/BAC+AAAOAAEKfxRoBgBRAAA1AAQKgSUAAw8ACQoEJagIAE0DAA8ACArXJKgIAE0DAAsABQpFI6AQANoBAAAA.Cheesee:BAABNQAECoEXAAIUAAcKex+OIQCLAgAUAAcKex+OIQCLAgAAAA==.Chiko:BAAANQAECgUJCAAAAA==.Christlike:BAAANQADCgcIBwAAAA==.Chronite:BAAANQAECgcIEgAAAA==.Chucho:BAAANQADCgYIBgAAAA==.Chárgers:BAAANQADCggJIgAAAA==.',
Ci='Cindr:BAABNQAECoEiAAMVAAkKkiNiAgB1AwAVAAkKeCNiAgB1AwAWAAUKSxlWDAD8AAAAAA==.Circumstance:BAAANQAECgUIBQAAAA==.',
Cl='Cleattus:BAAANQAECgUJDQAAAA==.',
Co='Coconutsteve:BAAANQAECggIBwAAAA==.Colddblooded:BAAANQAECgUJDQAAAA==.Cololol:BAACNQAFFIELAAIEAAUKgSMmAgAIAgAEAAUKgSMmAgAIAgA1AAQKgSYAAgQACQonJvkAANsDAAQACQonJvkAANsDAAAA.Compcomp:BAAANQAECgMIBAAAAA==.Compi:BAAANQAECgEIAQABNQAECgMIBAAJAAAAAA==.Cooper:BAAANQAECgcIEwAAAA==.Corlys:BAAANQAECgcJEgAAAA==.',
Cr='Crew:BAABNQAECoEyAAMXAAkK1SRzAgC5AwAXAAkK1SRzAgC5AwAEAAEKowx2TwA+AAAAAA==.Critflicker:BAAANQADCgYICwAAAA==.Cronoz:BAAANQAECgcIEwAAAA==.',
Cu='Cucokai:BAAANQAECgUJBwAAAA==.Cuddles:BAAANQAECgQJBwAAAA==.Cuddlestomp:BAACNQAFFIEMAAMYAAUKmRm+BACmAQAYAAUKxxe+BACmAQAZAAIKIBhvEgChAAA1AAQKgSUAAxgACQq0IlAIACEDABgACApKJFAIACEDABkABgrCETV8AHoBAAAA.',
Cz='Czernabog:BAAANQAECgYIDAAAAA==.',
['Cä']='Cämulos:BAAANQAECgUJDAAAAA==.',
['Cí']='Círí:BAEANQAECgYICAABNQAECgcIEwAJAAAAAA==.',
Da='Dabbosh:BAAANQAECgQICAAAAA==.Daedrec:BAAANQADCgQIBAABNQAECggJHwAaAEcmAA==.Dahl:BAAANQAECgQJCwABNQAECggIFwAGACEdAA==.Damnhammer:BAABNQAECoEeAAIKAAkKqBreEgD0AgAKAAkKqBreEgD0AgAAAA==.Dandalight:BAAANQABCgQIBAAAAA==.Dandie:BAAANQAECgIIAgAAAA==.Darkstranger:BAAANQADCgQIBAAAAA==.Darthjinwoo:BAABNQAECoEaAAMNAAgKwRDgEQAtAgANAAgKuRDgEQAtAgAQAAMKuAcqSwCgAAAAAA==.Darthmerlin:BAAANQADCgQIBAABNQAECggIGgANAMEQAA==.Dasakko:BAAANQAECgMIAwABNQAECgkJIgAbAJsXAA==.Dasmonko:BAAANQADCggIFAABNQAECgkJIgAbAJsXAA==.',
Db='Dbowzillaz:BAABNQAECoEcAAIYAAkKNCRFBABzAwAYAAkKNCRFBABzAwAAAA==.',
De='Deathskeeper:BAAANQADCgYJDAAAAA==.Demithania:BAAANQADCggIFAAAAA==.Demonhunterl:BAAANQAECgUICQAAAA==.Demontim:BAAANQADCgcJBwAAAA==.Denden:BAAANQADCgUIBQAAAA==.',
Dh='Dhsil:BAAANQAECgIIBAABNQAECgcJDgAJAAAAAA==.',
Di='Diabòlic:BAACNQAFFIELAAMLAAUKjw3DBwCvAAAPAAMKmgqZDwDcAAALAAIK/RHDBwCvAAA1AAQKgSMABA8ACQqiIDkeALQCAA8ACAqTHzkeALQCAAsABApBGg0hAEQBAA4AAgpoDqUUAIEAAAAA.Dirtydiana:BAAANQAECgYIDQAAAA==.',
Dj='Djavol:BAAANQAECggIEwAAAA==.',
Do='Doc:BAAANQADCgYIEAAAAA==.Doguntarth:BAACNQAFFIEJAAIDAAUKvAfQCQBkAQADAAUKvAfQCQBkAQA1AAQKgSYAAgMACQqlGqMqAMMCAAMACQqlGqMqAMMCAAAA.',
Dr='Drafi:BAAANQADCgIIAgABNQAECgEIAgAJAAAAAA==.Drankincup:BAACNQAFFIELAAIcAAUK7xS4BACbAQAcAAUK7xS4BACbAQA1AAQKgSwAAhwACQoKIYIJAHQDABwACQoKIYIJAHQDAAAA.Drankinkup:BAAANQAECgMJAwABNQAFFAUJCwAcAO8UAA==.Drstagger:BAEBNQAECoEdAAIdAAgKeyZyAQCOAwAdAAgKeyZyAQCOAwAAAA==.',
Du='Dullahan:BAAANQADCgQIBAAAAA==.Durotann:BAAANQAECgQIDwAAAA==.Dusios:BAAANQADCggJHgAAAA==.Duskflower:BAABNQAECoEgAAIeAAkKKxtzBwD/AgAeAAkKKxtzBwD/AgAAAA==.',
Ed='Eddard:BAAANQADCggICAAAAA==.',
El='Elexandur:BAAANQAECggJEAAAAA==.Elissa:BAAANQADCgYIBgAAAA==.Eliänna:BAAANQADCgIIAgAAAA==.Elleri:BAAANQAECgUJDAAAAA==.',
Ep='Epnokicks:BAABNQAECoEkAAIfAAkKnCCqBQBDAwAfAAkKnCCqBQBDAwAAAA==.',
Er='Eroicel:BAABNQAECoEoAAIgAAkKLhlpAwCyAgAgAAkKLhlpAwCyAgAAAA==.',
Ev='Evarielle:BAAANQAECgUICwABNQAECgkJKAAgAC4ZAA==.',
Fa='Faalindh:BAAANQAECgUJCQAAAA==.Fadedhalo:BAAANQAECgQICgAAAA==.Fadë:BAAANQADCgMJAwAAAA==.Falaya:BAABNQAECoEoAAQLAAkKtCQjBwB4AgALAAYKwiQjBwB4AgAPAAUKHyQSSQD6AQAOAAEKkyM7GQBaAAAAAA==.Falst:BAAANQAECgcIEQAAAA==.Farion:BAAANQADCgUJBQAAAA==.',
Fe='Feldoyle:BAAANQAECgUIBQAAAA==.Felyathas:BAAANQADCgMIAwABNQAECgQIBwAJAAAAAA==.Fennlar:BAAANQAECgcJEAAAAA==.Fersos:BAAANQABCgMIAwAAAA==.',
Fl='Flakey:BAAANQABCgIJAgAAAA==.Flawlessxi:BAABNQAECoEYAAIIAAgKGyIbLwABAwAIAAgKGyIbLwABAwAAAA==.Flyntflosy:BAABNQAECoEgAAIcAAkKgB+6DgA/AwAcAAkKgB+6DgA/AwAAAA==.',
Fo='Fowl:BAABNQAECoEVAAMEAAgKAQuqIwDUAQAEAAgK8AqqIwDUAQAXAAQKKAh/RwDLAAAAAA==.Fowlie:BAAANQADCgIIAgAAAA==.',
Fr='Fragment:BAAANQABCgIIAwAAAA==.',
Fu='Fuehriån:BAABNQAECoEiAAIIAAkKGBKrYgBnAgAIAAkKGBKrYgBnAgAAAA==.Funstar:BAAANQADCgYJBgABNQAECgkJFgAMAJccAA==.Furic:BAAANQADCgMJAwABNQAECgUJCwAJAAAAAA==.Furyess:BAABNQAECoEYAAIFAAcKeR0APQBfAgAFAAcKeR0APQBfAgAAAA==.',
Ga='Gaelsi:BAAANQAECgcICwAAAA==.Galactic:BAAANQAECgUICAABNQAECgkJGQAhAM4lAA==.Galgore:BAAANQAECgcJDgAAAA==.Garolok:BAAANQAECgcJEwAAAA==.Gasandflames:BAAANQAECgYICwAAAA==.Gascans:BAAANQAECgUIDQAAAA==.Gazelle:BAEANQAECgcIEwAAAA==.Gazerakhan:BAAANQAECgQIDQABNQAECgkJHwAEAIgTAA==.Gazerielle:BAABNQAECoEfAAIEAAkKiBOQFwBXAgAEAAkKiBOQFwBXAgAAAA==.',
Ge='Gerpsters:BAAANQABCgQIBAAAAA==.',
Gl='Glizzylizzy:BAABNQAECoEjAAIiAAkKUyNrAQCUAwAiAAkKUyNrAQCUAwAAAA==.',
Go='Gothgrippers:BAAANQAECgcICgAAAA==.Gowownage:BAABNQAECoEZAAIhAAkKziVwAADmAwAhAAkKziVwAADmAwAAAA==.',
Gr='Gradeus:BAACNQAFFIEIAAIFAAUKagqZBAB7AQAFAAUKagqZBAB7AQA1AAQKgSQAAgUACQrCHZAlAM0CAAUACQrCHZAlAM0CAAAA.Granddh:BAABNQAECoEmAAIXAAkKUiW5AQDNAwAXAAkKUiW5AQDNAwAAAA==.Graydius:BAAANQAECgEIAQAAAA==.Greenmango:BAAANQADCggIFAAAAA==.Grimeclipse:BAAANQAECgUJCwAAAA==.Grimr:BAAANQADCggICAAAAA==.Grovehart:BAAANQAECgQIBAAAAA==.Grumpin:BAAANQADCgUJBQABNQADCggJGAAJAAAAAA==.Grumpoo:BAAANQADCggJGAAAAA==.',
Gu='Gurt:BAAANQADCgUIBQAAAA==.Gutz:BAAANQAECgUIBQAAAA==.',
Ha='Haku:BAAANQAECgQJCAAAAA==.Halestorm:BAAANQAECgEJAQAAAA==.Hattori:BAAANQABCgUIBgAAAA==.Havefun:BAABNQAECoEYAAMUAAgKMRnlIACPAgAUAAgKMRnlIACPAgAcAAUKZBNTbABPAQABNQAECgkJFgAMAJccAA==.',
He='Hedonist:BAAANQAECgcJDgABNQAECgkJJgALAPcfAA==.Hellsbringer:BAAANQAECgQJCQAAAA==.Heretik:BAAANQAECgQIBwAAAA==.Hevnoraak:BAAANQAECgUJCgAAAA==.',
Ho='Hogun:BAAANQADCgQIBAAAAA==.Hold:BAABNQAECoEgAAMEAAkKqyLEBABzAwAEAAkKqyLEBABzAwAXAAIKSg/BVQBxAAAAAA==.Holycandi:BAAANQAECgIIBAAAAA==.Holycaru:BAAANQADCgcIBwAAAA==.Holydoyle:BAAANQAECgYICwAAAA==.Holyho:BAABNQAECoEWAAIFAAgKUhLsWAD2AQAFAAgKUhLsWAD2AQAAAA==.Holyjuice:BAAANQAECgQICAAAAA==.Hotpøcket:BAABNQAECoEfAAMeAAkKXhGvEQBPAgAeAAkKXhGvEQBPAgATAAgK/hMYKAAoAgAAAA==.',
Hu='Huntlzs:BAABNQAECoEXAAIYAAgKexAZHwDuAQAYAAgKexAZHwDuAQAAAA==.',
Hy='Hyperìen:BAECNQAFFIEMAAIGAAUKchrMAQChAQAGAAUKchrMAQChAQA1AAQKgScAAgYACQolJYMBALIDAAYACQolJYMBALIDAAAA.',
['Hø']='Hølý:BAAANQAECgcICAAAAA==.',
Ic='Icedoggi:BAAANQAECgYIEQAAAA==.',
Im='Immortalmage:BAAANQADCgYIBgAAAA==.Imsopro:BAAANQABCgIJAgAAAA==.',
In='Indeed:BAABNQAECoEeAAQRAAkKbyUtBQBpAwARAAgKRSUtBQBpAwAjAAUKFCVrBQD3AQAkAAMKZBvObwAXAQABNQAFFAUJCwAKAC8dAA==.Inferna:BAAANQADCgUIBQAAAA==.Innerbeast:BAAANQAECgQIBAABNQAFFAcIFAAjAIAjAA==.Intiq:BAAANQADCgIIAgAAAA==.',
Ir='Irbaboon:BAABNQAECoEUAAIDAAgKAhtmOwB5AgADAAgKAhtmOwB5AgAAAA==.Irreletaur:BAABNQAECoEqAAIDAAkKwyCgEwBDAwADAAkKwyCgEwBDAwAAAA==.',
It='Itisovernow:BAAANQADCgUICQABNQAECgEJAQAJAAAAAA==.Itsevokernow:BAAANQADCgUIBQABNQAECgEJAQAJAAAAAA==.Itsovernow:BAAANQAECgEJAQAAAA==.',
Iz='Izimir:BAAANQAECgUIDgAAAA==.',
Ja='Jamloo:BAAANQAECgUIBQAAAA==.Jampu:BAAANQAECgQJAQAAAA==.Jangokin:BAACNQAFFIEGAAITAAUKRwtVBwB2AQATAAUKRwtVBwB2AQA1AAQKgRsAAhMACQqRHasXAL0CABMACQqRHasXAL0CAAAA.Jayiasan:BAAANQAECgMIAwABNQAECgkJKAAIAAUkAA==.Jazz:BAAANQADCgUICQAAAA==.',
Je='Jermz:BAAANQADCgEIAQAAAA==.',
Ji='Jimbaha:BAAANQAECgMIAwAAAA==.Jinks:BAAANQADCgYJDwAAAA==.',
Jo='Joytoy:BAAANQADCgMJAwAAAA==.',
['Jè']='Jèrmz:BAAANQADCgYICQAAAA==.',
Ka='Kabang:BAAANQAECgUJEQAAAA==.Kachoo:BAABNQAECoEfAAIiAAkKQxt6BQD7AgAiAAkKQxt6BQD7AgAAAA==.Kaige:BAAANQAECgIIBAAAAA==.Kalithor:BAAANQAECgQJBwAAAA==.Kathoes:BAAANQAECgYJCwAAAA==.',
Ke='Keeky:BAAANQADCggICAAAAA==.Kelennin:BAAANQADCgIIAgAAAA==.Kellwildfire:BAABNQAECoEZAAISAAcKvRKnBwDvAQASAAcKvRKnBwDvAQAAAA==.',
Kf='Kfish:BAAANQAECgEIAQAAAA==.',
Kh='Khamael:BAAANQAECgUJCwAAAA==.Kheiron:BAABNQAECoEXAAIYAAYKDxrQIwC3AQAYAAYKDxrQIwC3AQAAAA==.',
Ki='Kinu:BAABNQAECoEgAAIUAAkKhSC3CQBCAwAUAAkKhSC3CQBCAwAAAA==.Kissmytotems:BAAANQADCgUIBQABNQAECgEIAgAJAAAAAA==.Kitane:BAAANQAECgUJCAAAAA==.',
Kl='Klarina:BAAANQAECgcIEwAAAA==.',
Kn='Knox:BAAANQAECgEIAQAAAA==.',
Ko='Kobieta:BAAANQADCggJCAAAAA==.Koda:BAAANQADCgYICgAAAA==.Kosolapaya:BAAANQADCgIIAgAAAA==.Kotharsevant:BAAANQADCgcIBwAAAA==.',
Ku='Kurolion:BAABNQAECoEYAAMYAAgKKh/6DgC5AgAYAAgKKh/6DgC5AgAlAAEKNwLMDgAhAAAAAA==.Kurzon:BAAANQADCgEIAQAAAA==.',
Kw='Kwanrbless:BAAANQADCgIIAgAAAA==.',
Ky='Kyasuka:BAAANQADCgIJAgAAAA==.Kyblade:BAAANQAECgcJEwAAAA==.',
['Kø']='Køs:BAABNQAECoEWAAQOAAgKnQ0cBQABAgAOAAgKnQ0cBQABAgAPAAcK8QdgdgBfAQALAAEK2w1aYwA6AAAAAA==.',
La='Lampro:BAAANQADCggIFAABNQAECgkJJQAPANYbAA==.Lavajato:BAAANQADCgYICQABNQAECgIIBQAJAAAAAA==.',
Le='Leemius:BAAANQAECgQIBgAAAA==.Leggolass:BAAANQADCgIIAgABNQAECgkJFQADAIYbAA==.Leosbryn:BAAANQAECgYIDAAAAA==.Leviträ:BAAANQADCgUIBQAAAA==.',
Li='Liable:BAAANQAECgYIDgAAAA==.Ligmadeebliz:BAABNQAECoEYAAIRAAcKGiDXEACSAgARAAcKGiDXEACSAgAAAA==.Lilfister:BAAANQAECgEIAQABNQAFFAUJCwAKAC8dAA==.Lilraz:BAAANQADCgYIBgAAAA==.Liltazzvert:BAABNQAECoEZAAIZAAgKFSXYCABnAwAZAAgKFSXYCABnAwAAAA==.Linksded:BAAANQAECgEJAQAAAA==.Littlepain:BAAANQADCgEIAQAAAA==.',
Lu='Lucero:BAAANQAECgUJCAAAAA==.',
Ly='Lyra:BAAANQADCgUIBgABNQAECgEIAgAJAAAAAA==.',
['Lû']='Lûpy:BAAANQADCgUJBQABNQABCgQJBgAJAAAAAA==.',
Ma='Mabey:BAAANQAECgEJAQAAAA==.Maerron:BAAANQAECgMIBQAAAA==.Mafi:BAAANQABCgUIBQAAAA==.Mageblprows:BAAANQADCgcJFAAAAA==.Mangemonpain:BAAANQADCgcJEwABNQAECgQIBwAJAAAAAA==.Maraayla:BAAANQADCggICAAAAA==.Matikz:BAABNQAECoEoAAINAAkKUh5FBgD+AgANAAkKUh5FBgD+AgAAAA==.Maximages:BAAANQADCggIDwAAAA==.Maximon:BAAANQAECgUIBwAAAA==.Maylla:BAAANQADCgcIDgAAAA==.',
Me='Meddle:BAACNQAFFIEIAAIkAAUK9hyXBADVAQAkAAUK9hyXBADVAQA1AAQKgSEAAiQACQqLImMRAPQCACQACQqLImMRAPQCAAAA.Mehrunesd:BAAANQAECgUIBwAAAA==.Meowwmix:BAAANQABCgIIAgAAAA==.Merrydeath:BAAANQADCgYICQAAAA==.Meyea:BAACNQAFFIEKAAMCAAUK5RgaAgCvAQACAAUK7BQaAgCvAQABAAUKzhR8BgBqAQA1AAQKgSUAAwIACQqsJfYCALoDAAIACQqsJfYCALoDAAEAAwr1GmBhAOsAAAAA.',
Mi='Miller:BAABNQAECoEfAAMZAAkKux7jFQD3AgAZAAkKHR3jFQD3AgAYAAcKlQ/qIwC2AQAAAA==.Millyvoid:BAAANQADCgcJBwABNQAECgkJHwAZALseAA==.Miru:BAAANQAECgEJAQAAAA==.Mitis:BAAANQADCgQIBAAAAA==.Mizdems:BAAANQAECgcJEgAAAA==.',
Mo='Moistjustice:BAAANQAECgIIAgAAAA==.Moonfun:BAAANQADCgcICgABNQAECgkJFgAMAJccAA==.Motmot:BAAANQAECgEIAQABNQAECggIFQAEAAELAA==.Moufon:BAAANQADCgYJFgAAAA==.',
My='Myrodragon:BAAANQAECgYICgAAAA==.',
['Mé']='Mércy:BAAANQAECgUIEQAAAA==.',
Na='Navah:BAAANQAECgUJBwAAAA==.',
Ne='Neandratroll:BAAANQAECgQJCAAAAA==.Necrodis:BAAANQAECgEIAQABNQAECgkJGwAIAAAbAA==.Nezemzy:BAAANQADCgUIBQABNQAECgcICgAJAAAAAA==.',
Ni='Nightlevels:BAACNQAFFIEHAAIkAAQKjBq+CABnAQAkAAQKjBq+CABnAQA1AAQKgR4ABCQACQoeGpMjAHkCACQACQrSGZMjAHkCABEAAwpyE/w7ALkAACMAAQqTEcUYAEcAAAAA.',
No='No:BAAANQADCgcIBwAAAA==.Nodens:BAAANQADCgQIBAAAAA==.Nogardd:BAAANQAECgcIEQAAAA==.Notpetya:BAAANQAECgUJCAAAAA==.Nottills:BAAANQADCgYIDAAAAA==.',
Nu='Nudleboi:BAAANQADCgUIBQAAAA==.Nuulruk:BAAANQAECgMJBQAAAA==.',
Ny='Nylaehh:BAAANQAECgEIAQAAAA==.Nyxtro:BAAANQAECgQJCAAAAA==.',
Oi='Oilslick:BAAANQAECgUICwAAAA==.',
Om='Ombrure:BAAANQAECgQJBwAAAA==.',
On='Onornu:BAABNQAECoErAAIUAAkKJCUAAgC1AwAUAAkKJCUAAgC1AwAAAA==.',
Or='Orlidan:BAABNQAECoEYAAIGAAgK+h9QBwDaAgAGAAgK+h9QBwDaAgAAAA==.',
Ot='Oth:BAACNQAFFIEIAAIkAAUKhCL3AgASAgAkAAUKhCL3AgASAgA1AAQKgRgAAiQACQpHJtYAANUDACQACQpHJtYAANUDAAAA.',
Ox='Oxylock:BAABNQAECoEpAAMPAAkKGyEQBwBgAwAPAAkKGyEQBwBgAwALAAcKKQckIwAzAQAAAA==.',
Pa='Palgeron:BAAANQADCgIJAgAAAA==.Pathlon:BAAANQADCggJGgAAAA==.',
Pe='Peetypirate:BAAANQAECgEJAQAAAA==.Pekapow:BAACNQAFFIEHAAImAAQK/BHlAgBAAQAmAAQK/BHlAgBAAQA1AAQKgScAAyYACQoSEtwOABgCACYACQoSEtwOABgCAB8AAQoLDdFDAEAAAAAA.Peta:BAAANQAECgEIAQAAAA==.',
Ph='Phobius:BAABNQAECoEjAAICAAkKRBhbGQCdAgACAAkKRBhbGQCdAgAAAA==.',
Pi='Pilihp:BAAANQAECgUJBQAAAA==.Pinkmango:BAABNQAECoEiAAMbAAkKmxfKFQBnAgAbAAkKLBTKFQBnAgACAAgKwhbaJQA1AgAAAA==.Pireyne:BAAANQADCgYICgAAAA==.Pistachioz:BAAANQAECgUIEAAAAA==.',
Pl='Playfultouch:BAAANQAECgMIAwAAAA==.Plunkaplunk:BAAANQADCgcIEgAAAA==.',
Po='Polymorphine:BAAANQAECgMJBAAAAA==.Poonanypie:BAAANQAECgUICQAAAA==.Poonzer:BAEBNQAECoEoAAIFAAkK2iLgDABtAwAFAAkK2iLgDABtAwAAAA==.Porosity:BAAANQAECgcJEwAAAA==.',
Pr='Pretreckless:BAAANQADCgMIAwAAAA==.Proudclod:BAAANQAECgUJBwAAAA==.',
Qe='Qetesh:BAAANQADCggIDwAAAA==.',
Ra='Rageflame:BAAANQADCgUIBQAAAA==.Ragnan:BAAANQADCgYJEAAAAA==.Rain:BAAANQADCgUIBQABNQAECgcIEwAJAAAAAA==.Ralinis:BAAANQADCgYJDAABNQADCgUIBQAJAAAAAA==.Rathi:BAAANQAECgIIAwABNQAECggIFAADAAIbAA==.Ravicavasar:BAAANQADCgYICgAAAA==.Rawrschak:BAAANQADCgIIAgAAAA==.Razfu:BAABNQAECoElAAImAAkKkh+2AwA7AwAmAAkKkh+2AwA7AwAAAA==.Razul:BAAANQADCggIFAAAAA==.Razzio:BAAANQADCgQIBAAAAA==.',
Re='Redharvest:BAAANQAECgYJEAAAAA==.Rekles:BAAANQADCgUIBQABNQAECgkJFwAVACIfAA==.Relentless:BAAANQAECgUJBQAAAA==.Retribution:BAAANQAECgUICAAAAA==.Reznoop:BAEANQAECgUICwABNQAECgkJKAAFANoiAA==.',
Ri='Richardtwist:BAAANQAECgEJAQAAAA==.',
Rk='Rkoo:BAAANQAECgQIBwAAAA==.',
Ro='Roobee:BAAANQABCgIJAgABNQADCgYICgAJAAAAAA==.Roxzor:BAAANQAECgYICAABNQAECggIFAADAAIbAA==.Royok:BAABNQAECoEYAAIaAAcK4RkRCgAXAgAaAAcK4RkRCgAXAgAAAA==.',
Ru='Ruwey:BAAANQABCgIIAgAAAA==.',
Sa='Saenys:BAAANQADCggIBwAAAA==.Sakardi:BAAANQAECgYIDQAAAA==.Sawedoff:BAABNQAECoEaAAIZAAgKIR4UHwDBAgAZAAgKIR4UHwDBAgAAAA==.',
Sc='Scalybum:BAAANQAECgQIBAAAAA==.Scamall:BAAANQAECgEJAQAAAA==.Schizophreni:BAAANQAECggIEgABNQAFFAUJDQARALAhAA==.Scionoffury:BAAANQAECgQIBAAAAA==.Scotcolumbus:BAABNQAECoEXAAIGAAgKIR3GCQCVAgAGAAgKIR3GCQCVAgAAAA==.Scullcrusher:BAAANQABCggICwAAAA==.',
Se='Secsysalad:BAAANQAECgUJDgABNQAECgkJKAAPAGocAA==.Seefoo:BAAANQAECgIJAgABNQAECgQIBAAJAAAAAA==.Sekho:BAAANQAECgUIBQAAAA==.Sekhy:BAAANQAECgEIAQABNQAECgUIBQAJAAAAAA==.Sero:BAAANQAECgQIBgAAAA==.Serrafir:BAAANQADCgEIAQAAAA==.',
Sg='Sgsmagicman:BAAANQAECgQIBQABNQAECgUJBgAJAAAAAA==.',
Sh='Shaamwow:BAAANQAECgQJCAAAAA==.Shade:BAABNQAECoElAAINAAkKKRPMCwCMAgANAAkKKRPMCwCMAgAAAA==.Shadoewolfe:BAAANQADCgYIDAAAAA==.Shageron:BAABNQAECoEkAAMYAAkK6iGuDADaAgAYAAkKWSGuDADaAgAZAAkK4A/PXgDRAQAAAA==.Shalladin:BAAANQADCgMIAwAAAA==.Shallshock:BAABNQAECoEZAAMcAAgK7BDJPgD9AQAcAAgK7BDJPgD9AQAUAAEKgQSP5AAeAAAAAA==.Shandoe:BAAANQADCgQIBAAAAA==.Shankspec:BAABNQAECoEcAAIQAAkK3R51BwAVAwAQAAkK3R51BwAVAwAAAA==.Shaolinshamy:BAAANQAECgUJCgAAAA==.Shazlo:BAAANQAECgIIAgAAAA==.Shifterxmag:BAABNQAECoEYAAIIAAgKjiDTNwDlAgAIAAgKjiDTNwDlAgAAAA==.Shikaca:BAAANQADCgYJEQAAAA==.Shinseina:BAAANQAECgcIEwAAAA==.Shockbite:BAAANQADCgUIBQAAAA==.Shockinawe:BAAANQADCgMIAwAAAA==.Short:BAAANQADCgIIAgAAAA==.Shämash:BAAANQAECgUJDQAAAA==.Shöck:BAAANQAECgIIBAAAAA==.',
Si='Sicastic:BAAANQAECgUJCQABNQAECgcJEQAJAAAAAA==.Sicc:BAAANQAECgIIAgABNQAECgcJEQAJAAAAAA==.Siccness:BAAANQAECgcJEQAAAA==.Sieben:BAAANQAECgEIAwAAAA==.Siic:BAAANQADCgYIBgABNQAECgcJEQAJAAAAAA==.Sindrex:BAABNQAECoElAAIMAAkKDCW1AADDAwAMAAkKDCW1AADDAwAAAA==.',
Sk='Skwerl:BAAANQADCgMJAwAAAA==.',
Sl='Slimshammy:BAAANQADCgMIAwABNQAECgkJFQADAIYbAA==.Slurmage:BAAANQAECgcIEwAAAA==.',
Sm='Smittywerben:BAAANQAECgcIDwAAAA==.Smokfun:BAABNQAECoEWAAMMAAkKlxwPBwAGAwAMAAkKlxwPBwAGAwAWAAUKtQnPDQDWAAAAAA==.Smooshi:BAABNQAECoEvAAMiAAkKLx7UCgBjAgAiAAcKqxvUCgBjAgAUAAkKxBZRMgAuAgAAAA==.',
Sn='Sneaktarts:BAAANQAECgQIBQABNQAECgkJHwAEAIgTAA==.',
So='Sololeveling:BAAANQAECgUIEAAAAA==.Sootor:BAAANQADCgYICwAAAA==.',
Sp='Spags:BAAANQAECgEJAQABNQAECgYIEQAJAAAAAA==.Sparklefarts:BAAANQADCgYIBgAAAA==.Spewky:BAAANQADCgEIAQAAAA==.Splydershot:BAAANQADCgYIBgAAAA==.',
St='Starfun:BAAANQAECgIIAgABNQAECgkJFgAMAJccAA==.Steelheals:BAAANQADCgQIBQAAAA==.Stenzwar:BAAANQAECgEJAQABNQAFFAUJCgACAOUYAA==.Stepdaddyfun:BAAANQAECgUIBQABNQAECgkJFgAMAJccAA==.Stevensiegal:BAAANQADCgIIAgAAAA==.Stormbless:BAABNQAECoEoAAIfAAkKyRueCQDwAgAfAAkKyRueCQDwAgAAAA==.Stormfallz:BAABNQAECoEbAAIIAAkKABtTNwDnAgAIAAkKABtTNwDnAgAAAA==.',
Su='Superfrenzy:BAAANQADCgMIAwAAAA==.Supertotemz:BAAANQAECgEJAQAAAA==.Supervoid:BAAANQAECgIIAgABNQAECgkJGQAhAM4lAA==.',
Sw='Swag:BAAANQADCggIDwABNQAECgUIBQAJAAAAAA==.Sweegie:BAAANQAECgUJDQAAAA==.Sweegz:BAAANQADCggJCQAAAA==.Sweetlou:BAAANQADCggICAAAAA==.',
Sy='Sydious:BAAANQADCgQJBAABNQAECgUJCwAJAAAAAA==.Syds:BAAANQAECgUJCwAAAA==.Synapticzion:BAAANQAECgcICAAAAA==.',
['Sí']='Sílk:BAAANQADCgcIGAAAAA==.',
Ta='Taara:BAABNQAECoEaAAMiAAgKRCRrCgBtAgAiAAYK4SNrCgBtAgAUAAcKLRTmTAC0AQAAAA==.Takeshi:BAAANQABCgIIAgAAAA==.Takkana:BAABNQAECoEhAAIFAAkKUybuAAD6AwAFAAkKUybuAAD6AwAAAA==.Tamped:BAAANQADCgQIBAAAAA==.Tatsuki:BAAANQABCgIIBAAAAA==.',
Tc='Tchaman:BAAANQAECgIIAgAAAA==.',
Te='Terk:BAACNQAFFIELAAIiAAUKjxudAADlAQAiAAUKjxudAADlAQA1AAQKgSUABCIACQrxJP8AALEDACIACQrxJP8AALEDABwAAQoRJEvCAGEAABQAAQpkA3/hACIAAAAA.',
Th='Thalrymere:BAAANQAECgcJEAAAAA==.Theory:BAAANQABCgEIAQAAAA==.Thiccerlegs:BAAANQAECgEJAQAAAA==.',
Ti='Tidebeard:BAACNQAFFIEFAAIUAAMK0BD4CQD5AAAUAAMK0BD4CQD5AAA1AAQKgSAAAhQACQruIAIRAAADABQACQruIAIRAAADAAAA.Tikz:BAAANQAECgcJEwAAAA==.',
To='Tock:BAABNQAECoEzAAMiAAkKNR89AwBEAwAiAAkKNR89AwBEAwAcAAYKZhEXZQBmAQAAAA==.Tokenwarrior:BAAANQAECgUJCAAAAA==.Touchmychuby:BAAANQAECgIIAgAAAA==.',
Tr='Tralina:BAAANQADCgMIAwABNQAECgkJKAAIAAUkAA==.Trapstâr:BAACNQAFFIENAAIYAAcKuBUUAQBuAgAYAAcKuBUUAQBuAgA1AAQKgRgAAhgACQq+HvcJAAQDABgACQq+HvcJAAQDAAAA.',
Ts='Tsarfun:BAAANQADCgQIBAABNQAECgkJFgAMAJccAA==.Tsireya:BAAANQAECgUIBQAAAA==.Tsunayoshii:BAAANQAECgYICAAAAA==.',
Tu='Turaco:BAAANQADCgUIBQABNQAECggIFQAEAAELAA==.Turf:BAAANQADCggJDQAAAA==.',
Un='Undeadwaifu:BAAANQAECgQJBAAAAA==.Unkledeath:BAAANQAECgUJCAAAAA==.',
Va='Vaeryn:BAAANQADCggIHAAAAA==.Valesyrin:BAAANQAECgcIEwAAAA==.Valura:BAAANQABCgYJBwAAAA==.Vansapanda:BAAANQADCggIEAAAAA==.Vaughn:BAABNQAECoEiAAMSAAkK1Bu9AgDOAgASAAkKVBm9AgDOAgADAAkKRhbcNgCLAgAAAA==.',
Ve='Veggieboi:BAAANQAECgcICwAAAA==.Vellast:BAAANQAECgIIAgAAAA==.',
Vi='Viande:BAAANQADCgQIBAAAAA==.Victory:BAAANQAECgUIBwAAAA==.Vigilo:BAABNQAECoEgAAIfAAkKwiDoBwASAwAfAAkKwiDoBwASAwAAAA==.Vilhelmina:BAABNQAECoEXAAMNAAcKURk8HwCTAQANAAUKsRg8HwCTAQAQAAIK4RrPSgCiAAAAAA==.Viruzdk:BAABNQAECoEgAAQBAAkKMiDPGwB4AgABAAcK2R/PGwB4AgACAAcK1x2UJwApAgAbAAIKFhlsVACRAAAAAA==.',
Vl='Vlad:BAAANQAECgMICAAAAA==.Vladivostok:BAAANQADCgEIAQAAAA==.',
Wa='Wafi:BAAANQAECgEIAgAAAA==.Wamp:BAABNQAECoElAAMPAAkK1hvQEQAAAwAPAAkK1hvQEQAAAwALAAEKcAymZgA2AAAAAA==.Warcheif:BAAANQADCgYICQABNQAECgQIDwAJAAAAAA==.Warlockl:BAAANQADCgUIBQAAAA==.Warwonka:BAABNQAECoElAAIYAAkKdBvMDQDKAgAYAAkKdBvMDQDKAgAAAA==.Watchurbeard:BAAANQAECgcJEwAAAA==.',
We='Weenrgulpr:BAAANQADCgcIFQAAAA==.',
Wh='Whamass:BAAANQAECgUIDAAAAA==.Whippy:BAAANQADCggIDwABNQAECgkJJQAMAAwlAA==.',
Wi='Windowlicker:BAAANQAECgcIEwAAAA==.Winnydafoo:BAAANQADCgQIBgAAAA==.',
Wr='Wrapfire:BAAANQAECgUIBwAAAA==.',
['Wí']='Wíldspirit:BAAANQADCgYICwAAAA==.',
['Xè']='Xèra:BAAANQADCggIEAAAAA==.',
Ya='Yacob:BAACNQAFFIEMAAMIAAUKZSNSDQCJAQAIAAQKkyJSDQCJAQAHAAEKrSYzAwBzAAA1AAQKgScAAwgACQrVJN8MAI4DAAgACQotJN8MAI4DAAcABQrmIgEJAL8BAAAA.Yamarahj:BAABNQAECoEmAAQLAAkK9x+PCABYAgAPAAgKox5YIQCjAgALAAgK1xiPCABYAgAOAAMKPBwIDgDtAAAAAA==.',
Yo='Yorikk:BAAANQAECgQIEQAAAA==.',
Yu='Yui:BAAANQABCgIIAgAAAA==.',
Za='Zaeo:BAAANQADCgcIBwAAAA==.Zafhir:BAAANQABCgUJCAAAAA==.Zankanotachi:BAAANQAECgQICQAAAA==.Zarmaku:BAAANQAECgYJDgAAAA==.Zartath:BAAANQADCggIDwAAAA==.Zauber:BAACNQAFFIEMAAQOAAUKex84AAClAQAOAAQK+iI4AAClAQAPAAMKPxwjCgAXAQALAAIKUSDWBAC+AAA1AAQKgSgABA4ACQqhJhgAANwDAA8ACQpRJp0AAOwDAA4ACQqEJhgAANwDAAsABwoAJZcGAIUCAAAA.Zazie:BAAANQAECgcIEwAAAA==.Zazu:BAAANQADCgIIAgAAAA==.',
Ze='Zepian:BAAANQAECgYICAAAAA==.',
Zi='Zirraj:BAACNQAFFIELAAIDAAUKNxhABwCgAQADAAUKNxhABwCgAQA1AAQKgSUAAwMACQrfJXoEAMADAAMACQrfJXoEAMADABIABQqVG4UMAGIBAAAA.',
Zy='Zygon:BAAANQADCggICAABNQAECgkJGQAhAM4lAA==.',
['Âr']='Ârthilasi:BAAANQAECgQIBAAAAA==.',
['Èó']='Èówyn:BAAANQAECgQICAAAAA==.',
['Év']='Évié:BAEANQAECgcIEwAAAA==.',
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
