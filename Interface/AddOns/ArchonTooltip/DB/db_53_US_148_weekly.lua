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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','Warrior-Arms','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Paladin-Holy','Warlock-Destruction','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Druid-Balance','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','Shaman-Elemental','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','DemonHunter-Vengeance','Evoker-Preservation','Druid-Guardian','Shaman-Enhancement','Warrior-Protection','Priest-Discipline','Hunter-Survival','Monk-Mistweaver',}
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acacia:BAAANQADCgcIDAAAAA==.',
Ae='Aeturnum:BAAANQAECgEIAQAAAA==.',
Ag='Agave:BAAANQAFFAEIAQAAAA==.',
Ai='Aizun:BAABNQAECoEWAAMBAAkKcSLBCABZAwABAAkKcSLBCABZAwACAAcKkBJYUgBiAQAAAA==.',
Ak='Akulagos:BAAANQAECgQJBgAAAA==.',
Al='Alakavahm:BAAANQADCgQIBAAAAA==.Aldenfire:BAAANQADCgYICQAAAA==.Alesce:BAABNQAECoEoAAIDAAkKXRPOYAAjAgADAAkKXRPOYAAjAgAAAA==.Alii:BAAANQAECgIIBAAAAA==.',
Am='Amaraukyou:BAAANQADCgYIBwAAAA==.Amenadiel:BAABNQAECoEYAAMEAAYKASFePgAoAgAEAAYKASFePgAoAgAFAAEKPBOBWgBDAAAAAA==.Amythistle:BAAANQAECgMIBAAAAA==.',
An='Ancksunamun:BAAANQAECgEIAQAAAA==.Andrü:BAABNQAECoEfAAIDAAgKShf7UgBQAgADAAgKShf7UgBQAgAAAA==.Antiquated:BAAANQAECgYICAAAAA==.',
Ap='Apsalar:BAAANQAECgQIBAAAAA==.',
Ar='Arcanetarts:BAAANQADCggICAABNQAECgkJJAAGAMIVAA==.Arnblass:BAAANQAECgYIEwAAAA==.',
As='Ascend:BAAANQAECgYIEQAAAA==.Ashtana:BAAANQAECgMIBAAAAA==.Ashtar:BAABNQAECoEhAAMHAAgK6BKSZAAUAgAHAAgK6BKSZAAUAgAIAAMKiQf2RgBzAAAAAA==.Ashwana:BAAANQADCgIIAgAAAA==.',
Au='Aurora:BAAANQADCgcIBwAAAA==.',
Av='Aviee:BAABNQAECoEjAAMJAAgKshykCAADAgAJAAUKICSkCAADAgAKAAYKThhptgDJAQAAAA==.',
Ax='Axidin:BAAANQAECgQIBQAAAA==.',
Az='Azgul:BAAANQADCgYIBwAAAA==.Azushi:BAAANQAECgMIAwABNQAFFAYIDQADAEkJAA==.',
Ba='Babyfox:BAAANQADCgMIAwAAAA==.Babymage:BAABNQAECoEoAAIKAAkKvBRYbABzAgAKAAkKvBRYbABzAgAAAA==.Badform:BAAANQAECgQICAAAAA==.Badkitteh:BAAANQADCggIFAAAAA==.Baelstrom:BAAANQADCgIIAgABNQAECgkJGgALAJodAA==.Baendron:BAABNQAECoEdAAIBAAgKmxbQLgAaAgABAAgKmxbQLgAaAgAAAA==.Bahcrypt:BAAANQADCgYIDAAAAA==.Bahnna:BAAANQAECgEIAQAAAA==.Bakaris:BAAANQADCgUIBQAAAA==.Barbarik:BAABNQAECoEcAAIMAAgKtQs9XgCxAQAMAAgKtQs9XgCxAQABNQAECgkJKwANAC8gAA==.Barberry:BAAANQADCgQJBAABNQAECgIIAgAOAAAAAA==.Baretwallace:BAAANQAFFAEIAQAAAA==.Battlereaddy:BAAANQAECgEIAQAAAA==.Bayesian:BAAANQABCgIIAgAAAA==.',
Be='Beefwildfire:BAAANQADCggIDQAAAA==.Beercheer:BAAANQADCgUIEAAAAA==.Beertholomew:BAAANQAECgYIDwAAAA==.Beestkyn:BAAANQAECgMIAwABNQAECgQIBAAOAAAAAA==.Behodakhtala:BAAANQADCgYIFQAAAA==.Bellanzo:BAAANQAECgcIEwAAAA==.Bellawaifu:BAAANQABCgQIBAAAAA==.',
Bi='Bigzee:BAEBNQAECoEpAAMPAAkK4xhIBABZAgAPAAgKehlIBABZAgAQAAYKog+yiQBqAQAAAA==.Bindanini:BAAANQADCgUICQABNQAECgMIBAAOAAAAAA==.',
Bl='Blargin:BAAANQADCgIJAgAAAA==.Blorgin:BAACNQAFFIEPAAMRAAYKZBt+AwDWAQARAAUKDxp+AwDWAQASAAIKGBvXCgCuAAA1AAQKgSoAAxEACQo0JSgDAGUDABEACAphJigDAGUDABIABQoMImopANsBAAAA.Bluntmàn:BAAANQAECgUIEQAAAA==.',
Bo='Boogieman:BAAANQADCgYIBgAAAA==.Boohwodoy:BAAANQADCgcIBwAAAA==.Bookers:BAAANQAECgcIEwAAAA==.Booplzs:BAAANQADCgUIBQAAAA==.Borgo:BAAANQADCgMIAwABNQAECgkJHAAKAMIOAA==.Boulangerie:BAACNQAFFIEQAAIFAAUKKiKTAgD9AQAFAAUKKiKTAgD9AQA1AAQKgSkAAgUACQqGJqQAAOMDAAUACQqGJqQAAOMDAAAA.Boulight:BAAANQAECgQIBwAAAA==.Boulior:BAAANQAECgIIBAAAAA==.Bowvice:BAEANQADCgUIBQABNQAECgkJMQAHAC0jAA==.Boyd:BAABNQAECoEsAAMTAAkKfh8bAgAtAwATAAkKfh8bAgAtAwADAAEKzwqpEwE7AAAAAA==.',
Br='Brewmungandr:BAAANQAECgYIBgAAAA==.Brodir:BAAANQADCgUIBQAAAA==.Bromayzo:BAAANQABCgIJAgAAAA==.',
['Bø']='Bøøgiêman:BAAANQAECgYIBwAAAA==.',
Ca='Cainpain:BAAANQADCgYICwAAAA==.Canadatrash:BAAANQAECgUIBwABNQAFFAEIAQAOAAAAAA==.Carraway:BAABNQAECoEkAAIUAAkKFBirHQCrAgAUAAkKFBirHQCrAgAAAA==.Cashewz:BAAANQADCgQIBAAAAA==.Casterella:BAAANQAECgUIBQAAAA==.',
Ce='Ceasarsalad:BAACNQAFFIEHAAMQAAQKtA/zEwDwAAAQAAMKfBTzEwDwAAANAAIKJAjbDQCUAAA1AAQKgTEAAxAACQrLH4MVAAgDABAACQpXHYMVAAgDAA0ABwoQFsQLACgCAAAA.Ceazitt:BAAANQAECgYIEAAAAA==.Ceazyweasley:BAAANQAECgMIBAABNQAECgYIEAAOAAAAAA==.Ceci:BAAANQABCgMJAwAAAA==.Celestriå:BAAANQAECgEIAQAAAA==.Cetana:BAABNQAECoEmAAMRAAkKJyLcEQBDAgARAAYK2iLcEQBDAgASAAQKZyGWOQBrAQABNQAFFAEIAQAOAAAAAA==.',
Ch='Chadlockb:BAACNQAFFIEOAAQNAAUK7h+5BADGAAAQAAIKfCSdFwDUAAANAAIKFyG5BADGAAAPAAEKfxQOCQBNAAA1AAQKgScAAxAACQr5JSAJAF8DABAACArrJSAJAF8DAA0ABQpFI2sSANIBAAAA.Cheesee:BAABNQAECoEgAAIVAAgKIR9iHQDDAgAVAAgKIR9iHQDDAgAAAA==.Chiko:BAAANQAECgUIDQAAAA==.Christlike:BAAANQADCgcIBwAAAA==.Chronite:BAABNQAECoEcAAMKAAkKwg5iiwApAgAKAAkKXA1iiwApAgAJAAUKEQsCGQDmAAAAAA==.Chucho:BAAANQADCgYIBgAAAA==.Chárgers:BAAANQAECgQIBAAAAA==.',
Ci='Cindr:BAACNQAFFIEIAAIWAAUKkBTxAgChAQAWAAUKkBTxAgChAQA1AAQKgSYAAxYACQobJDsCAH8DABYACQoBJDsCAH8DABcABQpLGQ4PAPAAAAAA.Circumstance:BAAANQAECgUIBQAAAA==.',
Cl='Cleattus:BAAANQAECgYIEwAAAA==.',
Co='Coconutsteve:BAAANQAECggICwAAAA==.Colddblooded:BAAANQAECgUIDwAAAA==.Cololol:BAACNQAFFIEPAAMGAAYKdB+SAQBYAgAGAAYKdB+SAQBYAgALAAEKSgVuFgA/AAA1AAQKgTsAAwYACQqSJkgAAAMEAAYACQqSJkgAAAMEAAsABArIJXYxAL4BAAAA.Compcomp:BAAANQAECgMIBAAAAA==.Compi:BAAANQAECgEIAQABNQAECgMIBAAOAAAAAA==.Cooper:BAABNQAECoEeAAIYAAgKfx9LDgDZAgAYAAgKfx9LDgDZAgAAAA==.Corlys:BAABNQAECoEaAAIKAAgKDBy1WwCcAgAKAAgKDBy1WwCcAgAAAA==.',
Cr='Crew:BAACNQAFFIEGAAILAAQKzBp7BwBcAQALAAQKzBp7BwBcAQA1AAQKgTsAAwsACQo/JZMCAMADAAsACQo/JZMCAMADAAYAAQqjDKJWADgAAAAA.Critflicker:BAAANQADCgYIDwAAAA==.Cronoz:BAABNQAECoEdAAIUAAgKWyNQEAAlAwAUAAgKWyNQEAAlAwAAAA==.',
Cu='Cucokai:BAAANQAECgUIDAAAAA==.Cuddles:BAAANQAECgUIDAAAAA==.Cuddlestomp:BAACNQAFFIEPAAMYAAYK9RjpBgCWAQAYAAUKrBnpBgCWAQAZAAMKLhRgDgD1AAA1AAQKgSgAAxgACQotI/sIACcDABgACArSJPsIACcDABkABgrCEb2aAGoBAAAA.',
Cy='Cynical:BAAANQAECgQIBAABNQAFFAcICQAIANMPAA==.',
Cz='Czernabog:BAAANQAECggIEgAAAA==.',
['Cä']='Cämulos:BAAANQAECgUIDAAAAA==.',
['Cí']='Círí:BAEANQAECgcICwABNQAECgcIFwADAIYiAA==.',
Da='Dabbosh:BAAANQAECgQICAAAAA==.Daedrec:BAAANQADCgQIBAABNQAFFAIIAgAOAAAAAA==.Dahl:BAAANQAECgQIDAABNQAECgkJGQAIAFkgAA==.Damnhammer:BAABNQAECoEhAAIMAAkK7x0sEgAYAwAMAAkK7x0sEgAYAwAAAA==.Dandalight:BAAANQABCgQIBAAAAA==.Dandie:BAAANQAECgYICAAAAA==.Darkstranger:BAAANQADCgQIBAAAAA==.Darthjinwoo:BAABNQAECoEeAAMRAAgKehJVEwAvAgARAAgKehJVEwAvAgASAAMKuAepXgCbAAAAAA==.Darthmerlin:BAAANQADCgQIBAABNQAECggIHgARAHoSAA==.Dasakko:BAAANQAECgMIAwABNQAECgkJIwAaAMwXAA==.Dasmonko:BAAANQAECgIIAgABNQAECgkJIwAaAMwXAA==.',
Db='Dbowzillaz:BAACNQAFFIEIAAIYAAQKMBz5CQBQAQAYAAQKMBz5CQBQAQA1AAQKgR4AAhgACQo0JOwGAEsDABgACQo0JOwGAEsDAAAA.',
De='Deathskeeper:BAAANQADCgYJDAAAAA==.Deathsled:BAAANQADCgEIAQAAAA==.Demithania:BAAANQAECgIIAgAAAA==.Demonhunterl:BAAANQAECgYIDAAAAA==.Demontim:BAAANQADCgcIBwAAAA==.Demungandr:BAAANQAECgYIBgAAAA==.Denden:BAAANQADCgUIBQAAAA==.',
Dh='Dhsil:BAAANQAECgQICgABNQAECgcIEQAOAAAAAA==.',
Di='Diabòlic:BAACNQAFFIEPAAMNAAYKZBA2BQDCAAAQAAQKXgx9DQA1AQANAAIKcBg2BQDCAAA1AAQKgSYABBAACQqiIBcrAKECABAACAqTHxcrAKECAA0ABApBGhYkAD0BAA8AAgpoDhoZAHoAAAAA.Dirtydiana:BAAANQAECgcIEgAAAA==.',
Dj='Djavol:BAABNQAECoEaAAILAAkKmh1XDQAOAwALAAkKmh1XDQAOAwAAAA==.',
Do='Doc:BAAANQADCgYIEAAAAA==.Doguntarth:BAACNQAFFIENAAIDAAYKSQl4CgCjAQADAAYKSQl4CgCjAQA1AAQKgSkAAgMACQp6Gw40AL4CAAMACQp6Gw40AL4CAAAA.',
Dr='Drafi:BAAANQADCgIIAgABNQAECgEIAgAOAAAAAA==.Drankincup:BAACNQAFFIEQAAIbAAUKsRccBwCjAQAbAAUKsRccBwCjAQA1AAQKgS4AAhsACQpjIZgNAGEDABsACQpjIZgNAGEDAAAA.Drankinkup:BAAANQAECgcICgABNQAFFAUIEAAbALEXAA==.Drstagger:BAEBNQAECoElAAIcAAgKmyaPAQCTAwAcAAgKmyaPAQCTAwABNQAECgkJKAAcAIwmAA==.',
Du='Dullahan:BAAANQADCgQIBAAAAA==.Durotann:BAABNQAECoEWAAIZAAYKJwgrpwBNAQAZAAYKJwgrpwBNAQAAAA==.Dusios:BAAANQADCggIHgAAAA==.Duskflower:BAACNQAFFIEGAAIdAAQKpAwtBgAzAQAdAAQKpAwtBgAzAQA1AAQKgS8AAh0ACQocIesCAIYDAB0ACQocIesCAIYDAAAA.',
Dy='Dyslexcia:BAAANQADCgEIAQAAAA==.',
Ed='Eddard:BAAANQAECgEIAQAAAA==.',
El='Elexandur:BAAANQAECggIEgAAAA==.Elissa:BAAANQADCgYIBgAAAA==.Eliänna:BAAANQADCgIIAgAAAA==.Elleri:BAAANQAECgYIEgAAAA==.',
Em='Emyi:BAAANQAECgQIBAAAAA==.',
Ep='Epnokicks:BAACNQAFFIEIAAIeAAQKCA2+BgAhAQAeAAQKCA2+BgAhAQA1AAQKgS0AAh4ACQrfIw0DAJYDAB4ACQrfIw0DAJYDAAAA.',
Er='Eroicel:BAACNQAFFIEHAAIfAAMKYgliAgCqAAAfAAMKYgliAgCqAAA1AAQKgTEAAh8ACQonHQoDAPkCAB8ACQonHQoDAPkCAAAA.',
Es='Esposr:BAAANQAECggICAAAAA==.',
Ev='Evarielle:BAAANQAECgYIEQABNQAFFAMIBwAfAGIJAA==.',
Fa='Faalindh:BAAANQAECgYIDwAAAA==.Fadedhalo:BAAANQAECgUIDwAAAA==.Fadë:BAAANQADCggICwAAAA==.Falaya:BAACNQAFFIEIAAMNAAQKdhqXBwCzAAANAAIKPRqXBwCzAAAQAAIKrxp5GwCvAAA1AAQKgTEABA0ACQqNJeMGAIgCAA0ABgpPJeMGAIgCABAABgpXI4o9AFsCAA8AAQqTI3weAFQAAAAA.Fallinorion:BAAANQADCgQIBAAAAA==.Falst:BAABNQAECoEcAAMbAAgKrRU6OwBAAgAbAAgKrRU6OwBAAgAVAAYKvR04TADiAQAAAA==.Farion:BAAANQAECgUIBQAAAA==.',
Fe='Feldoyle:BAAANQAECgUIBQAAAA==.Felyathas:BAAANQADCgQIBQABNQAECgQICwAOAAAAAA==.Fennlar:BAABNQAECoEbAAIKAAgK8BJGjgAiAgAKAAgK8BJGjgAiAgAAAA==.Fersos:BAAANQABCgMIAwAAAA==.',
Fl='Flakey:BAAANQABCgIJAgAAAA==.Flawlessxi:BAABNQAECoEfAAIKAAgKrySRHgBKAwAKAAgKrySRHgBKAwAAAA==.Flyntflosy:BAACNQAFFIEGAAIbAAQKpBR+CgBRAQAbAAQKpBR+CgBRAQA1AAQKgSgAAhsACQo2IeoNAF8DABsACQo2IeoNAF8DAAAA.',
Fo='Fowl:BAABNQAECoEZAAMGAAkKkw42KQC7AQAGAAgK8Ao2KQC7AQALAAcKiQ0SNwCTAQAAAA==.Fowlie:BAAANQADCgIIAgAAAA==.',
Fr='Fragment:BAAANQABCgIIAwAAAA==.',
Fu='Fuehriån:BAABNQAECoErAAIKAAkKwxPlbgBtAgAKAAkKwxPlbgBtAgAAAA==.Funstar:BAAANQADCgYIBgABNQAFFAQICAAgAAkUAA==.Furic:BAAANQADCgMJAwABNQAECgYIEQAOAAAAAA==.Furyess:BAABNQAECoEiAAIHAAcK1R9IRQB5AgAHAAcK1R9IRQB5AgAAAA==.',
Ga='Gaelsi:BAAANQAECggIEQAAAA==.Galactic:BAAANQAECgUICgABNQAECgkJGgAhAM4lAA==.Galgore:BAAANQAECgcJDgAAAA==.Garolok:BAABNQAECoEcAAIDAAgK2Rj8XQAsAgADAAgK2Rj8XQAsAgAAAA==.Gasandflames:BAAANQAECgYICwAAAA==.Gascans:BAAANQAECgUIDQAAAA==.Gazelle:BAEBNQAECoEeAAIcAAgKnRgdCgA3AgAcAAgKnRgdCgA3AgAAAA==.Gazerakhan:BAABNQAECoEVAAIbAAgKKxJdSAAGAgAbAAgKKxJdSAAGAgABNQAECgkJJAAGAMIVAA==.Gazerielle:BAABNQAECoEkAAMGAAkKwhXEGABjAgAGAAkK5xTEGABjAgALAAEKgQqucQA4AAAAAA==.',
Ge='Gerpsters:BAAANQABCgQIBAAAAA==.',
Gl='Glizzylizzy:BAABNQAECoEmAAIiAAkK8SPrAQCIAwAiAAkK8SPrAQCIAwAAAA==.',
Go='Gothgrippers:BAAANQAECgcIDwAAAA==.Gowownage:BAABNQAECoEaAAIhAAkKziW1AADdAwAhAAkKziW1AADdAwAAAA==.',
Gr='Gracebinder:BAAANQADCgYIBQABNQAECgQIBwAOAAAAAA==.Gradeus:BAACNQAFFIELAAIHAAUKqAqtBwByAQAHAAUKqAqtBwByAQA1AAQKgSgAAwcACQrjH40nAPACAAcACQrjH40nAPACAAwAAQq3B97qADoAAAAA.Granddh:BAACNQAFFIEHAAILAAMK4xv0CQAJAQALAAMK4xv0CQAJAQA1AAQKgTAAAwsACQqqJcgCALwDAAsACQqNJcgCALwDAB8ABgo/Hx4IAB8CAAAA.Graydius:BAAANQAECgYIBgAAAA==.Greenmango:BAAANQAECgIIAgAAAA==.Grimeclipse:BAAANQAECgUJCwAAAA==.Grimr:BAAANQAECgYIBgAAAA==.Grovehart:BAAANQAECgQIBAAAAA==.Grumpin:BAAANQADCgUJBQABNQAECgUIBQAOAAAAAA==.Grumpoo:BAAANQAECgUIBQAAAA==.',
Gu='Gurt:BAAANQADCgUIBQAAAA==.Gutz:BAAANQAECgUIBQAAAA==.',
Ha='Haku:BAAANQAECgYIDgAAAA==.Haldir:BAAANQADCgQIBAAAAA==.Halestorm:BAAANQAECgEJAQAAAA==.Hattori:BAAANQABCgYICgAAAA==.Havefun:BAABNQAECoEdAAMVAAgKGR9ZGgDVAgAVAAgKGR9ZGgDVAgAbAAUKPhQKgABOAQABNQAFFAQICAAgAAkUAA==.',
He='Hedonist:BAABNQAECoEVAAIjAAkKVxRlCwAzAgAjAAkKVxRlCwAzAgABNQAECgkJKwANAC8gAA==.Hellsbringer:BAAANQAECgQJCQAAAA==.Heretik:BAAANQAECgQIBwAAAA==.Hevnoraak:BAAANQAECgYIEAAAAA==.',
Ho='Hogun:BAAANQADCgQIBAAAAA==.Hold:BAABNQAECoEmAAMGAAkKHiNcBQBuAwAGAAkK0SJcBQBuAwALAAQKHxFFUwDPAAAAAA==.Holycandi:BAAANQAECgIIBgABNQAECgQIBQAOAAAAAA==.Holycaru:BAAANQADCgcIBwAAAA==.Holydoyle:BAAANQAECgcIEgAAAA==.Holyho:BAABNQAECoEYAAIHAAgKnxKCdADmAQAHAAgKnxKCdADmAQAAAA==.Holyjuice:BAAANQAECgQICAAAAA==.Holyraz:BAAANQAECgIIAgAAAA==.Hotpøcket:BAACNQAFFIEGAAIUAAMKjw7PEQDWAAAUAAMKjw7PEQDWAAA1AAQKgSgAAxQACQqFHSsaAMgCABQACAoHHisaAMgCAB0ACQpeEQAXAD0CAAAA.',
Hu='Huntlzs:BAABNQAECoEeAAIYAAgK3hPrHwASAgAYAAgK3hPrHwASAgAAAA==.',
Hy='Hyperìen:BAECNQAFFIEQAAIIAAYKUx8sAQAfAgAIAAYKUx8sAQAfAgA1AAQKgSoAAggACQpdJpsBALADAAgACQpdJpsBALADAAAA.',
['Hø']='Hølý:BAAANQAECgcIDgAAAA==.',
Ic='Icedoggi:BAABNQAECoEcAAIhAAgK2x0xBwCwAgAhAAgK2x0xBwCwAgAAAA==.',
Im='Immortalmage:BAAANQADCgYIBgAAAA==.Imsopro:BAAANQABCgIJAgAAAA==.',
In='Indeed:BAABNQAECoEiAAQFAAkKpSTwAgCdAwAFAAkKpSTwAgCdAwAkAAUKFCVLBgDyAQAEAAQKnhSogAAlAQABNQAFFAYIEQAMAIUeAA==.Inferna:BAAANQADCgUIBQAAAA==.Innerbeast:BAAANQAECgQIBAABNQAFFAcIGgAkAIAjAA==.Intiq:BAAANQADCgMIAwAAAA==.',
Ir='Irbaboon:BAABNQAECoEWAAIDAAgKAxz2SAByAgADAAgKAxz2SAByAgAAAA==.Irreletaur:BAABNQAECoExAAIDAAkKxyBiGQA2AwADAAkKxyBiGQA2AwAAAA==.',
It='Itisovernow:BAAANQADCgUICQABNQAECgEJAQAOAAAAAA==.Itsevokernow:BAAANQADCgUIBQABNQAECgEJAQAOAAAAAA==.Itsovernow:BAAANQAECgEJAQAAAA==.',
Iz='Izimir:BAAANQAECgYIEAAAAA==.',
Ja='Jamloo:BAAANQAECgUIBQAAAA==.Jampu:BAAANQAECgYIAQAAAA==.Jangokin:BAACNQAFFIEKAAIUAAUKRBJHCQCEAQAUAAUKRBJHCQCEAQA1AAQKgR4AAhQACQpNHuAaAMICABQACQpNHuAaAMICAAAA.Jayiasan:BAAANQAECgMIAwABNQAFFAYIBgAKAIwHAA==.Jazz:BAAANQADCgUICQAAAA==.',
Je='Jermz:BAAANQADCgUIBgAAAA==.',
Ji='Jimbaha:BAAANQAECgMIAwAAAA==.Jinks:BAAANQADCgYIFAAAAA==.',
Jo='Joytoy:BAAANQADCgMJAwAAAA==.',
['Jè']='Jèrmz:BAAANQADCgYICQAAAA==.',
Ka='Kabang:BAABNQAECoEUAAIKAAYKthfuuwC9AQAKAAYKthfuuwC9AQAAAA==.Kachoo:BAABNQAECoEhAAIiAAkKpBvwBgDsAgAiAAkKpBvwBgDsAgAAAA==.Kaige:BAAANQAECgQIBwAAAA==.Kalithor:BAAANQAECgQICwAAAA==.Kathoes:BAAANQAECgYJCwAAAA==.',
Ke='Keeky:BAAANQADCggICAAAAA==.Kelennin:BAAANQADCgIIAgAAAA==.Kellwildfire:BAABNQAECoEhAAITAAgKQhaRBgBKAgATAAgKQhaRBgBKAgAAAA==.',
Kf='Kfish:BAAANQAECgEIAQAAAA==.',
Kh='Khamael:BAAANQAECgYIEQAAAA==.Kheiron:BAABNQAECoEZAAIYAAgKuBPwKAC1AQAYAAgKuBPwKAC1AQAAAA==.',
Ki='Kinu:BAABNQAECoEoAAIVAAkKnyFYCgBOAwAVAAkKnyFYCgBOAwAAAA==.Kissmytotems:BAAANQADCgYICwABNQAECgIIBAAOAAAAAA==.Kitane:BAAANQAECgUIDQAAAA==.',
Kl='Klarina:BAABNQAECoEeAAIMAAgKexY5NwBLAgAMAAgKexY5NwBLAgAAAA==.',
Kn='Knox:BAAANQAECgEIAQAAAA==.',
Ko='Kobieta:BAAANQADCggJCAAAAA==.Koda:BAAANQADCgYICgAAAA==.Kosolapaya:BAAANQADCgIIAgAAAA==.Kotharsevant:BAAANQADCgcIBwAAAA==.',
Ku='Kurolion:BAABNQAECoEbAAMYAAkKyR/cCgAJAwAYAAkKyR/cCgAJAwAlAAEKNwIFEQAfAAAAAA==.Kurzon:BAAANQADCgEIAQAAAA==.',
Kw='Kwanrbless:BAAANQADCgIIAgAAAA==.',
Ky='Kyasuka:BAAANQADCgIJAgAAAA==.Kyblade:BAABNQAECoEcAAIFAAgKBiJlCwAHAwAFAAgKBiJlCwAHAwAAAA==.',
['Kø']='Køs:BAABNQAECoEWAAQPAAgKnQ3aBgDxAQAPAAgKnQ3aBgDxAQAQAAcK8Qd3kwBRAQANAAEK2w2baQA6AAAAAA==.',
La='Lampro:BAAANQAECgIIAgABNQAECgkJKAAQAGYeAA==.Lavajato:BAAANQADCgYICQABNQAECgIIBQAOAAAAAA==.',
Le='Leemius:BAAANQAECgQIBwAAAA==.Leggolass:BAAANQAECgYIBwABNQAECgkJGwADAH0dAA==.Leosbryn:BAAANQAECgcIEwAAAA==.Leviträ:BAAANQADCgUIBQAAAA==.',
Li='Liable:BAABNQAECoEYAAIFAAgKLhfnGQA2AgAFAAgKLhfnGQA2AgAAAA==.Ligmadeebliz:BAABNQAECoEcAAIFAAkKGR/lCQAeAwAFAAkKGR/lCQAeAwAAAA==.Lilfister:BAAANQAECgEIAQABNQAFFAYIEQAMAIUeAA==.Lilraz:BAAANQADCgYIBgAAAA==.Liltazzvert:BAABNQAECoEfAAIZAAgKFSWyDQBPAwAZAAgKFSWyDQBPAwAAAA==.Linksded:BAAANQAECgEJAQAAAA==.Littlepain:BAAANQADCgEIAQAAAA==.',
Lu='Lucero:BAAANQAECgUIDQAAAA==.',
Ly='Lyra:BAAANQADCgUIBgABNQAECgIIBAAOAAAAAA==.',
['Lû']='Lûpy:BAAANQADCgUIBQABNQABCgQIBgAOAAAAAA==.',
Ma='Mabey:BAAANQAECgEJAQAAAA==.Maerron:BAAANQAECgMIBQAAAA==.Mafi:BAAANQABCgUIBQAAAA==.Mageblprows:BAAANQADCgcIGgAAAA==.Mangemonpain:BAAANQAECgIIAgABNQAECgQICwAOAAAAAA==.Maraayla:BAAANQADCggICAAAAA==.Matikz:BAABNQAECoEwAAIRAAkKVSGiAwBWAwARAAkKVSGiAwBWAwAAAA==.Maximages:BAAANQADCggIDwAAAA==.Maximon:BAAANQAECgUIBwAAAA==.Maylla:BAAANQADCgcIDgAAAA==.',
Me='Meddle:BAACNQAFFIEIAAIEAAUK9hxdBwDOAQAEAAUK9hxdBwDOAQA1AAQKgSEAAgQACQqLIiEZAOECAAQACQqLIiEZAOECAAAA.Mehrunesd:BAAANQAECgUIBwAAAA==.Meowwmix:BAAANQABCgIIAgAAAA==.Merrydeath:BAAANQADCgYICQAAAA==.Meyea:BAACNQAFFIENAAMCAAYK8hwqAgDbAQACAAYKUBoqAgDbAQABAAUKzhSyCQBlAQA1AAQKgSkAAwIACQpnJiIFAIwDAAIACQpnJiIFAIwDAAEAAwr1Gs1wAOQAAAAA.',
Mi='Miller:BAABNQAECoEoAAMZAAkK+iDBGgD7AgAZAAkKiR7BGgD7AgAYAAgKrhS1HgAeAgAAAA==.Millyvoid:BAAANQADCgcJBwABNQAECgkJKAAZAPogAA==.Miru:BAAANQAECgEJAQAAAA==.Mitis:BAAANQADCgQIBAAAAA==.Mizdems:BAABNQAECoEaAAIGAAgK/xkNGQBgAgAGAAgK/xkNGQBgAgAAAA==.',
Mo='Moistjustice:BAAANQAECgIIAgAAAA==.Moonfun:BAAANQADCgcICgABNQAFFAQICAAgAAkUAA==.Motmot:BAAANQAECgMIBQABNQAECgkJGQAGAJMOAA==.Moufon:BAAANQADCgYIHAAAAA==.',
My='Myrodragon:BAAANQAECgYICgAAAA==.',
['Mé']='Mércy:BAABNQAECoEeAAIdAAgKRyE4CQACAwAdAAgKRyE4CQACAwAAAA==.',
Na='Navah:BAAANQAECgYIDQAAAA==.',
Ne='Neandratroll:BAAANQAECgUIDQAAAA==.Necrodis:BAAANQAECgEIAQABNQAECgkJHgAKAEYbAA==.Nezemzy:BAAANQADCgUIBQABNQAECgcIDwAOAAAAAA==.',
Ni='Nightlevels:BAACNQAFFIELAAIEAAYKbhoYBAAjAgAEAAYKbhoYBAAjAgA1AAQKgSEABAQACQoeGrEuAG0CAAQACQrSGbEuAG0CAAUAAwpyE8RFALAAACQAAQqTEX4dAEYAAAAA.Nivarr:BAAANQADCgMIAwAAAA==.',
No='No:BAABNQAECoEgAAIKAAcKthKYqwDgAQAKAAcKthKYqwDgAQAAAA==.Nodens:BAAANQAECgcIBwAAAA==.Nogardd:BAAANQAECgcIEwAAAA==.Notpetya:BAAANQAECgYIDgAAAA==.Nottills:BAAANQADCgYIDAAAAA==.',
Nu='Nudleboi:BAAANQADCgUIBQAAAA==.Nuulruk:BAAANQAECgMJBQAAAA==.',
Ny='Nylaehh:BAAANQAECgEIAQAAAA==.Nyxtro:BAAANQAECgYIDgAAAA==.',
Oi='Oilslick:BAAANQAECgUICwAAAA==.',
Om='Ombrure:BAAANQAECgQICwAAAA==.',
On='Onornu:BAACNQAFFIEIAAIVAAQKUxg5CQBhAQAVAAQKUxg5CQBhAQA1AAQKgTQAAhUACQokJYUCAK0DABUACQokJYUCAK0DAAAA.',
Or='Orlidan:BAABNQAECoEfAAIIAAgKdyFsCADiAgAIAAgKdyFsCADiAgAAAA==.',
Ot='Oth:BAACNQAFFIEKAAIEAAUKhCLuBAALAgAEAAUKhCLuBAALAgA1AAQKgRoAAgQACQpHJmEBAMoDAAQACQpHJmEBAMoDAAAA.',
Ox='Oxylock:BAABNQAECoExAAMQAAkKACNsBwBwAwAQAAkKACNsBwBwAwANAAcKKQeCJgAsAQAAAA==.',
Pa='Palgeron:BAAANQADCgIJAgAAAA==.Pathlon:BAAANQADCggJGgAAAA==.',
Pe='Peetypirate:BAAANQAECgEIAgAAAA==.Pekapow:BAACNQAFFIEIAAImAAQKbRMZBAA3AQAmAAQKbRMZBAA3AQA1AAQKgSoAAyYACQpvEpASAAECACYACQpvEpASAAECAB4AAQoLDRxRADsAAAAA.Peta:BAAANQAECgEIAQAAAA==.',
Ph='Phobius:BAABNQAECoEmAAICAAkKGxk3JABiAgACAAkKGxk3JABiAgAAAA==.',
Pi='Pilihp:BAAANQAECgUICgAAAA==.Pinkmango:BAABNQAECoEjAAMaAAkKzBcpIAA7AgAaAAkKXRQpIAA7AgACAAgKwhawNwDmAQAAAA==.Pireyne:BAAANQADCgYICgAAAA==.Pistachioz:BAAANQAECgYIEwAAAA==.',
Pl='Playfultouch:BAAANQAECgQIBwAAAA==.Plunkaplunk:BAAANQADCgcIEgAAAA==.',
Po='Polymorphine:BAAANQAECgMJBAAAAA==.Poonanypie:BAAANQAECgUICQAAAA==.Poonzer:BAEBNQAECoExAAIHAAkKLSNQDQB+AwAHAAkKLSNQDQB+AwAAAA==.Porosity:BAABNQAECoEdAAIVAAgK9Qu0aQB3AQAVAAgK9Qu0aQB3AQAAAA==.',
Pr='Pretreckless:BAAANQADCggICgAAAA==.Proudclod:BAAANQAECgUJBwAAAA==.',
Qe='Qetesh:BAAANQADCggIDwAAAA==.',
Ra='Rageflame:BAAANQAECgEIAQAAAA==.Ragnan:BAAANQADCgYIEAAAAA==.Rain:BAAANQADCgUIBQABNQAECggIHgAMAHsWAA==.Ralinis:BAAANQADCgYJDAABNQADCgUIBQAOAAAAAA==.Rathi:BAAANQAECgUIBwABNQAECggIFgADAAMcAA==.Ravicavasar:BAAANQADCgYICgAAAA==.Rawrschak:BAAANQADCgMIBQAAAA==.Razfu:BAABNQAECoEmAAImAAkKMyBmBQAhAwAmAAkKMyBmBQAhAwAAAA==.Razul:BAAANQADCggIFAAAAA==.Razzio:BAAANQADCgQIBAAAAA==.',
Re='Redharvest:BAABNQAECoEXAAIfAAgKrxe0BwAuAgAfAAgKrxe0BwAuAgAAAA==.Rekles:BAAANQADCgUIBQABNQAECgkJHAAWABAjAA==.Relentless:BAAANQAECgYICwAAAA==.Retribution:BAAANQAECgUICAAAAA==.Reznoop:BAEANQAECgYIEQABNQAECgkJMQAHAC0jAA==.',
Ri='Richardtwist:BAAANQAECgEJAQAAAA==.',
Rk='Rkoo:BAAANQAECgQICwAAAA==.',
Ro='Roobee:BAAANQABCgIIAwABNQADCgYICgAOAAAAAA==.Roxzor:BAAANQAECggIDQABNQAECggIFgADAAMcAA==.Royok:BAABNQAECoEgAAIjAAgKDhm9CgBCAgAjAAgKDhm9CgBCAgAAAA==.',
Ru='Ruwey:BAAANQABCgIIAgAAAA==.',
Sa='Saenys:BAAANQADCggIBwAAAA==.Sakardi:BAAANQAECgYIDQAAAA==.Sawedoff:BAABNQAECoEcAAIZAAkKBh2PHwDiAgAZAAkKBh2PHwDiAgAAAA==.',
Sc='Scalybum:BAAANQAECgQIBAAAAA==.Scamall:BAAANQAECgEJAQAAAA==.Schizophreni:BAAANQAECggIEgABNQAFFAUIEAAFACoiAA==.Scionoffury:BAAANQAECgQIBAAAAA==.Scotcolumbus:BAABNQAECoEZAAIIAAkKWSCfBgAOAwAIAAkKWSCfBgAOAwAAAA==.Scullcrusher:BAAANQABCggIDQAAAA==.',
Se='Secsysalad:BAAANQAECgUJDgABNQAFFAQIBwAQALQPAA==.Seefoo:BAAANQAECgIJAgABNQAECgQIBAAOAAAAAA==.Sekho:BAAANQAECgUICgAAAA==.Sekhy:BAAANQAECgEIAQABNQAECgUICgAOAAAAAA==.Sero:BAAANQAECgYIDAAAAA==.Serrafir:BAAANQADCgEIAQAAAA==.',
Sg='Sgsmagicman:BAAANQAFFAEIAQAAAA==.',
Sh='Shaamwow:BAAANQAECgQIDAAAAA==.Shackle:BAAANQADCgMIAwAAAA==.Shade:BAABNQAECoEoAAMRAAkKxhRxDQCDAgARAAkKoRRxDQCDAgASAAEKsQ67cwA7AAAAAA==.Shadoewolfe:BAAANQADCgYIEQAAAA==.Shageron:BAABNQAECoEnAAMYAAkKwSJDDwDNAgAYAAkKTCJDDwDNAgAZAAkK4A+vegC6AQAAAA==.Shalladin:BAAANQAECgQIBAAAAA==.Shallshock:BAABNQAECoEhAAMbAAkKnxKrTgDtAQAbAAgK7BCrTgDtAQAVAAgK1hE0SgDqAQAAAA==.Shandoe:BAAANQADCgQIBAAAAA==.Shankspec:BAABNQAECoEfAAISAAkKEyASCQAYAwASAAkKEyASCQAYAwAAAA==.Shaolinshamy:BAAANQAECgYIEAAAAA==.Shazlo:BAAANQAFFAEIAQAAAA==.Shifterxmag:BAABNQAECoEeAAIKAAgKdCE0QgDfAgAKAAgKdCE0QgDfAgAAAA==.Shikaca:BAAANQADCgYJEQAAAA==.Shinseina:BAABNQAECoEeAAIHAAgKfB16NAC4AgAHAAgKfB16NAC4AgAAAA==.Shockbite:BAAANQADCgYICwAAAA==.Shockdh:BAAANQAECgIIAgABNQAECgkJGgAUABIVAA==.Shockinawe:BAAANQADCgMIAwAAAA==.Short:BAAANQADCgIIAgAAAA==.Shämash:BAAANQAECgYIEgAAAA==.Shöck:BAAANQAECgIIBgAAAA==.',
Si='Sicastic:BAAANQAECgUICQABNQAECggIGgAZAHsVAA==.Sicc:BAAANQAECgQICAABNQAECggIGgAZAHsVAA==.Siccness:BAABNQAECoEaAAMZAAcKexWFZAD2AQAZAAcKexWFZAD2AQAYAAIKJwZPXQBiAAAAAA==.Sieben:BAAANQAECgEIAwAAAA==.Siic:BAAANQADCgYIBgABNQAECggIGgAZAHsVAA==.Sindrex:BAABNQAECoEoAAIgAAkKFyUEAQC/AwAgAAkKFyUEAQC/AwABNQAECgIIAgAOAAAAAA==.',
Sk='Skwerl:BAAANQADCgMJAwAAAA==.',
Sl='Slimshammy:BAAANQADCgMIAwABNQAECgkJGwADAH0dAA==.Slurmage:BAABNQAECoEcAAIKAAgKfiFVPQDsAgAKAAgKfiFVPQDsAgAAAA==.',
Sm='Smittywerben:BAABNQAECoEZAAIVAAgKrRpvMABdAgAVAAgKrRpvMABdAgAAAA==.Smokfun:BAACNQAFFIEIAAIgAAQKCRQsCQBKAQAgAAQKCRQsCQBKAQA1AAQKgRgAAyAACQpWHV8IAAADACAACQpWHV8IAAADABcABQq1CdAQAM0AAAAA.Smooshi:BAABNQAECoExAAMiAAkKLx4BDgBMAgAiAAcKqxsBDgBMAgAVAAkKxBY/QAAUAgAAAA==.',
Sn='Sneaktarts:BAAANQAECgQICgABNQAECgkJJAAGAMIVAA==.',
So='Sololeveling:BAABNQAECoEYAAIBAAYKwQacbQDxAAABAAYKwQacbQDxAAAAAA==.Sootor:BAAANQADCgYICwAAAA==.',
Sp='Spags:BAAANQAECgEJAQABNQAECgYIEQAOAAAAAA==.Sparklefarts:BAAANQADCgYIBgAAAA==.Spewky:BAAANQAECgIIAgABNQAECgkJHAAZAAYdAA==.Splydershot:BAAANQADCgYICQAAAA==.',
St='Starfun:BAAANQAECgYICAABNQAFFAQICAAgAAkUAA==.Steelheals:BAAANQADCgQIBQAAAA==.Stenzwar:BAAANQAECgEJAQABNQAFFAYIDQACAPIcAA==.Stepdaddyfun:BAAANQAECgYIBgABNQAFFAQICAAgAAkUAA==.Stevensiegal:BAAANQADCgIIAgAAAA==.Stormbless:BAABNQAECoEwAAIeAAkKwR7pCAAbAwAeAAkKwR7pCAAbAwAAAA==.Stormfallz:BAABNQAECoEeAAIKAAkKRhuuSADNAgAKAAkKRhuuSADNAgAAAA==.',
Su='Superfrenzy:BAAANQADCgMIAwAAAA==.Supertotemz:BAAANQAECgEJAQAAAA==.Supervoid:BAAANQAECgIIAgABNQAECgkJGgAhAM4lAA==.',
Sw='Swag:BAAANQAECgEIAQABNQAECgUIBQAOAAAAAA==.Sweegie:BAAANQAECgYIDgAAAA==.Sweegz:BAAANQADCggICQAAAA==.Sweetlou:BAAANQADCggICAAAAA==.',
Sy='Sydious:BAAANQADCgQIBAABNQAECgYIEQAOAAAAAA==.Syds:BAAANQAECgYIEQAAAA==.Synapticzion:BAAANQAECggICwAAAA==.',
['Sí']='Sílk:BAAANQADCggIIAAAAA==.',
Ta='Taara:BAABNQAECoEdAAMiAAkKOCQqCADKAgAiAAcK3yMqCADKAgAVAAcKLRSaYACVAQAAAA==.Takeshi:BAAANQABCgIIAgAAAA==.Takkana:BAABNQAECoEjAAMHAAkKUyYiAgDnAwAHAAkKUyYiAgDnAwAIAAIKbSKSOQDHAAAAAA==.Tamped:BAAANQADCgcICwAAAA==.Tatsuki:BAAANQABCgIIBAAAAA==.',
Tc='Tchaman:BAAANQAECgIIAgAAAA==.',
Te='Terk:BAACNQAFFIEOAAIiAAYK4xqPAAA/AgAiAAYK4xqPAAA/AgA1AAQKgSgABCIACQqEJQkBALUDACIACQqEJQkBALUDABsAAQoRJJXgAF8AABUAAQpkA8T6ACIAAAAA.',
Th='Thalrymere:BAAANQAECgcJEAAAAA==.Theory:BAAANQABCgEIAQAAAA==.Thiccerlegs:BAAANQAECgEJAQAAAA==.',
Ti='Tidebeard:BAACNQAFFIEKAAIVAAUKsxNoBwCVAQAVAAUKsxNoBwCVAQA1AAQKgSMAAhUACQruINIXAOUCABUACQruINIXAOUCAAAA.Tikz:BAABNQAECoEeAAIQAAgKgRAVWQD+AQAQAAgKgRAVWQD+AQAAAA==.',
To='Tock:BAABNQAECoE+AAMiAAkKryDOAwBFAwAiAAkKryDOAwBFAwAbAAYKZhHfegBcAQAAAA==.Tokenwarrior:BAAANQAECgUIDQAAAA==.Touchmychuby:BAAANQAECgIIAgAAAA==.',
Tr='Tralina:BAAANQADCgMIAwABNQAFFAYIBgAKAIwHAA==.Trapstâr:BAACNQAFFIEOAAIYAAcKuBU/AgBGAgAYAAcKuBU/AgBGAgA1AAQKgRsAAhgACQoOH10MAPICABgACQoOH10MAPICAAAA.',
Ts='Tsarfun:BAAANQADCgQIBAABNQAFFAQICAAgAAkUAA==.Tsireya:BAAANQAECgUIBQAAAA==.Tsunayoshii:BAAANQAECgYICAAAAA==.',
Tu='Turaco:BAAANQADCgUIBgABNQAECgkJGQAGAJMOAA==.Turf:BAAANQAECgQIBAAAAA==.',
Un='Undeadwaifu:BAAANQAECgQJBAAAAA==.Unkledeath:BAAANQAECgUIDQAAAA==.',
Va='Vaeryn:BAAANQADCggIHAAAAA==.Valesyrin:BAABNQAECoEeAAIQAAgKxQ8DWwD4AQAQAAgKxQ8DWwD4AQAAAA==.Valura:BAAANQAECgIIAgAAAA==.Vansapanda:BAAANQADCggIEAAAAA==.Vaughn:BAABNQAECoEkAAMTAAkKGhwWBACwAgATAAkKVBkWBACwAgADAAkKkRaGSABzAgAAAA==.',
Ve='Veggieboi:BAAANQAFFAIIAgAAAA==.Vellast:BAAANQAECgIIAgAAAA==.Vellinda:BAAANQAECgEIAQAAAA==.',
Vi='Viande:BAAANQADCgQIBAAAAA==.Victory:BAAANQAECgYICgAAAA==.Vigilo:BAABNQAECoEjAAIeAAkKLyFcCgABAwAeAAkKLyFcCgABAwAAAA==.Vilhelmina:BAABNQAECoEeAAMRAAcKmBlSIwCGAQARAAUKFBlSIwCGAQASAAIK4RqZXgCbAAAAAA==.Viruzdk:BAABNQAECoEkAAQBAAkKBCFEGAC7AgABAAgKvx9EGAC7AgACAAgKPx2dJwBLAgAaAAIKFhkbaACIAAAAAA==.',
Vl='Vlad:BAAANQAECgQICQAAAA==.Vladivostok:BAAANQADCgEIAgAAAA==.',
Vy='Vyera:BAAANQABCggIDgAAAA==.',
Wa='Wafi:BAAANQAECgEIAgAAAA==.Wamp:BAABNQAECoEoAAMQAAkKZh6dFgACAwAQAAkKZh6dFgACAwANAAEKcAxbbQA2AAAAAA==.Warcheif:BAAANQADCgYICgABNQAECgYIFgAZACcIAA==.Warlockl:BAAANQAECgEIAQAAAA==.Warwonka:BAABNQAECoEoAAIYAAkKwxv+EAC4AgAYAAkKwxv+EAC4AgAAAA==.Watchurbeard:BAABNQAECoEcAAIZAAgKZxIVVAAkAgAZAAgKZxIVVAAkAgAAAA==.',
We='Weenrgulpr:BAAANQADCgcIFQAAAA==.Wetnoodle:BAAANQAECgQIBAABNQAECgkJJAAGAMIVAA==.',
Wh='Whamass:BAAANQAECgYIDwAAAA==.Whiiplash:BAAANQAECgIIAgAAAA==.Whippy:BAAANQADCggIDwABNQAECgIIAgAOAAAAAA==.',
Wi='Windowlicker:BAABNQAECoEaAAMeAAgK4hakGQAfAgAeAAgK4hakGQAfAgAmAAgKlRC5FQDJAQAAAA==.Winnydafoo:BAAANQADCgQIBwAAAA==.',
Wr='Wrapfire:BAAANQAECgcIDgAAAA==.',
['Wí']='Wíldspirit:BAAANQADCgYIDwAAAA==.',
['Xè']='Xèra:BAAANQADCggIGAAAAA==.',
Ya='Yacob:BAACNQAFFIEQAAMKAAYK8SMtCQD2AQAKAAUKZSMtCQD2AQAJAAEKrSaiBQBuAAA1AAQKgSoAAwoACQrDJYkNAJIDAAoACQobJYkNAJIDAAkABQrmIsULALABAAAA.Yamarahj:BAABNQAECoErAAQNAAkKLyCACABkAgAQAAgKUx95HgDZAgANAAgKFhmACABkAgAPAAMKPBxfEQDkAAAAAA==.',
Yo='Yorikk:BAAANQAECgQIEwAAAA==.',
Yu='Yui:BAAANQABCgIIAgAAAA==.',
Za='Zaeo:BAAANQADCgcIBwAAAA==.Zafhir:BAAANQABCgUJCAAAAA==.Zankanotachi:BAAANQAECgQICQAAAA==.Zarmaku:BAABNQAECoEVAAMVAAcKUxU4UwDHAQAVAAcKUxU4UwDHAQAbAAYKCQeViwAvAQAAAA==.Zartath:BAAANQADCggIFwAAAA==.Zauber:BAACNQAFFIEOAAQPAAYK5B5kAACmAQAPAAQKyCNkAACmAQAQAAQKXRt/CQBtAQANAAIKUSDEBgC3AAA1AAQKgS0ABBAACQreJs0AAO0DABAACQq4Js0AAO0DAA8ACQqEJjUAAMsDAA0ABwpxJXIGAJMCAAAA.Zazie:BAABNQAECoEeAAIfAAgK8BxGBQCNAgAfAAgK8BxGBQCNAgAAAA==.Zazu:BAAANQADCgIIAgAAAA==.',
Ze='Zeetti:BAEANQAECgMIAwABNQAECgkJKQAPAOMYAA==.Zepian:BAAANQAECgYICAAAAA==.',
Zi='Zirraj:BAACNQAFFIEOAAMDAAYK0hXuCgCbAQADAAUKTRjuCgCbAQATAAEKagnlAgBeAAA1AAQKgSgAAwMACQr1JVsGALIDAAMACQr1JVsGALIDABMABQqVG+MPAFQBAAAA.',
Zy='Zygon:BAAANQADCggICAABNQAECgkJGgAhAM4lAA==.',
['Âr']='Ârthilasi:BAAANQAECgQIBAAAAA==.',
['Èó']='Èówyn:BAAANQAECgQICAAAAA==.',
['Év']='Évié:BAEBNQAECoEXAAIDAAcKhiJXPACeAgADAAcKhiJXPACeAgAAAA==.',
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
