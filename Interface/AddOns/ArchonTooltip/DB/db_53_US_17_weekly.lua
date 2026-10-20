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

local lookup = {'Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Paladin-Retribution','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Devourer','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Druid-Restoration','Shaman-Restoration','Monk-Windwalker','Priest-Shadow','Monk-Mistweaver','Warlock-Affliction','Paladin-Protection','Evoker-Augmentation','Rogue-Subtlety','Monk-Brewmaster','Druid-Balance','Druid-Feral',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECn8qAAQBAAoKwx6GNADvAgABAAoKwx6GNADvAgACAAEK2BrEPQBMAAADAAIK+ARJLwBDAAAAAA==.Adellon:BAABNQAECn8aAAIEAAkKzhtJNQCjAgAEAAkKzhtJNQCjAgAAAA==.Adhar:BAAANQADCggIEwAAAA==.Adrielle:BAAANQAECgUIBwAAAA==.',
Ak='Akakage:BAABNQAECn8WAAIFAAgKlxxTKwA8AgAFAAgKlxxTKwA8AgAAAA==.Akakaji:BAAANQAECgYIBwABNQAECggIFgAFAJccAA==.Akutoku:BAABNQAECn8bAAIGAAkKRBebXwBYAgAGAAkKRBebXwBYAgAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAABNQAECn8iAAQHAAkK5Qy+HgArAQAHAAcKkg2+HgArAQAIAAUKngp/kQDjAAAJAAIKUAMPwABIAAAAAA==.Anomander:BAAANQAECgMIAwAAAA==.',
Ar='Ar:BAABNQAECn8hAAIKAAkK8RQmTwA3AgAKAAkK8RQmTwA3AgABNQAECgoKKgABAMMeAA==.Archon:BAABNQAECn82AAMBAAkK0x40GQChAQABAAkK0x40GQChAQADAAEKJR1xLABSAAAAAA==.Arienca:BAABNQAECn8lAAMLAAgKrw3HEwDSAQALAAgKrw3HEwDSAQAMAAUKzAM7BAHDAAAAAA==.',
As='Aspir:BAEBNQAECn8WAAINAAkKYRZ1GwC0AQANAAkKYRZ1GwC0AQABNQAFFAQIDgAHAD0YAA==.',
At='At:BAAANQAECgYIBwABNQAECgoKKgABAMMeAA==.',
Au='Auddio:BAAANQAECggIAQAAAA==.',
Ba='Baidoogh:BAAANQAECgEIAgAAAA==.Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCgYICQAAAA==.Bepis:BAABNQAECn8jAAIOAAkK7SAHAwA/AwAOAAkK7SAHAwA/AwAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgYIDAAAAA==.',
Bl='Blazerunner:BAABNQAECn8qAAIPAAkKpw3F0gDhAQAPAAkKpw3F0gDhAQAAAA==.Blazesmasher:BAAANQAECgEIAQABNQAECgkJKgAPAKcNAA==.Blitzkreig:BAAANQAECgQIBQAAAA==.Blured:BAABNQAECn81AAIQAAoKmyP9AgCqAwAQAAoKmyP9AgCqAwAAAA==.',
Bo='Booty:BAABNQAECn8qAAICAAoKxh7uBQANAwACAAoKxh7uBQANAwAAAA==.Bort:BAABNQAECn8cAAIRAAkKZwfFGQCsAQARAAkKZwfFGQCsAQAAAA==.',
Br='Brevyn:BAABNQAECn8aAAIPAAkKiQgg5gC9AQAPAAkKiQgg5gC9AQAAAA==.',
Bu='Bubblebutt:BAAANQAECgQICAABNQAECggIDAASAAAAAA==.Bulla:BAAANQAECgYICAAAAA==.Bung:BAABNQAECn8jAAITAAkKXBd3QQBfAgATAAkKXBd3QQBfAgAAAA==.Buum:BAAANQAECgMIAwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECgcIHwAUAGsNAA==.',
Ca='Cali:BAACNQAFFH8VAAMVAAcKBgpMCQCYAQAVAAYKhAhMCQCYAQAQAAQKFQsFCwAbAQA1AAQKfzcAAxUACgoGIQYKAKgBABAACgqqHo4UAMICABUABwo5IQYKAKgBAAAA.Calipari:BAAANQADCgQIBAABNQAFFAcIFQAVAAYKAA==.Catamara:BAAANQAECgIIBAAAAA==.',
Ce='Cephus:BAACNQAFFH8MAAIWAAUKKBM8BwCMAQAWAAUKKBM8BwCMAQA1AAQKfy4AAhYACgqoEt0jAAYCABYACgqoEt0jAAYCAAAA.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFH8aAAIGAAYKDRW9BQD3AQAGAAYKDRW9BQD3AQA1AAQKfzEAAgYACgrAIXYYADgDAAYACgrAIXYYADgDAAAA.Chimeira:BAAANQADCgUIBQAAAA==.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFH8SAAMVAAQK5BpXBAD4AAAVAAQK5BpXBAD4AAAQAAEKxQpoFgBAAAA1AAQKfy8AAxAACgqPIacWAKsCABAACQoNHKcWAKsCABUABQpwIi4YAC8BAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECn8yAAMXAAoKsBtPFgAeAwAXAAoKsBtPFgAeAwAEAAUK9A0GxAAKAQAAAA==.',
Cy='Cynestra:BAAANQAECgUIBQAAAA==.Cyni:BAAANQAECgEIAQABNQAFFAQIBgATAIoRAA==.Cytheris:BAAANQADCgIIAgABNQAECgoKMgAXALAbAA==.',
Da='Dadudadu:BAACNQAFFH8OAAINAAUK1wecDwBSAQANAAUK1wecDwBSAQA1AAQKfzoAAg0ACgoYHK9GAMACAA0ACgoYHK9GAMACAAAA.Daftmonk:BAACNQAFFH8SAAIYAAQKRSAnAwD8AAAYAAQKRSAnAwD8AAA1AAQKf0AAAhgACgpSJVYCALkDABgACgpSJVYCALkDAAAA.Darj:BAABNQAECn8fAAIBAAkKjBUiYwBlAgABAAkKjBUiYwBlAgAAAA==.Darmonevil:BAAANQAECgQICQAAAA==.Dasarus:BAAANQAECgUICwAAAA==.Dauntless:BAAANQAECgYIBgAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgQIBgASAAAAAA==.Dethblades:BAAANQAECgEIAQABNQAECgQIBgASAAAAAA==.Dethblow:BAAANQAECgQIBgAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgQIBgASAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECn8tAAMXAAkKCwgZfQCUAQAXAAkKCwgZfQCUAQAEAAcK0AIQxAAKAQAAAA==.',
Dk='Dklot:BAABNQAECn8oAAMIAAoKzhkKMQBqAgAIAAoKzhkKMQBqAgAJAAMKFg5xMwCpAAAAAA==.',
Do='Doomkin:BAAANQAECgUIBgAAAA==.',
Dr='Dragcon:BAAANQADCgQIBAABNQAECgoKMgAXALAbAA==.Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECn8xAAIGAAoKvxwrNwDFAgAGAAoKvxwrNwDFAgAAAA==.Dreadgrave:BAABNQAECn8eAAIIAAoK9hIbUgDKAQAIAAoK9hIbUgDKAQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAFFAQIBgATAIoRAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
Eg='Egoh:BAAANQAECgYIBgABNQAFFAUIFgAZAK8jAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.Eleshkigal:BAAANQADCgEIAQABNQAECgoKJgAYANgiAA==.',
En='Enkeke:BAABNQAECn8zAAIIAAoKChklLgB5AgAIAAoKChklLgB5AgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgASAAAAAA==.Eresanna:BAABNQAECn8ZAAIPAAgKiA9M0wDgAQAPAAgKiA9M0wDgAQAAAA==.Erf:BAABNQAECn8oAAIaAAoK8Q4XGwDQAQAaAAoK8Q4XGwDQAQAAAA==.Erinis:BAAANQAECgMIAgABNQAECgkJJQAVAGMbAA==.',
Es='Esdeath:BAAANQAECgcICwABNQAECgkJJQAVAGMbAA==.',
Ex='Extremefear:BAABNQAECn8aAAMMAAcK2g9c1gAdAQAMAAUKPg1c1gAdAQALAAIKxBPJVgB6AAAAAA==.',
Fe='Fearious:BAACNQAFFH8QAAQbAAUKICXnBQB1AAAMAAMKVyUhGwAeAQAbAAEKAADnBQB1AAALAAEKsiSNFABmAAA1AAQKfxkABAwACgqaJBlmACgCAAwABgrOJBlmACgCAAsAAgpYI11IAKcAABsAAgocJtUKAHMAAAAA.Feroond:BAABNQAECn8WAAMJAAgKrxeXOAAlAgAJAAgKmBWXOAAlAgAHAAUKpRMQagD3AAAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fr='Frogteeth:BAAANQAECgYIEgAAAA==.Frozath:BAAANQAECgIIBAAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgASAAAAAA==.Fussypants:BAABNQAECn8XAAIcAAcKoAjEPwD7AAAcAAcKoAjEPwD7AAAAAA==.',
Ga='Gallindral:BAABNQAECn8rAAIQAAoKCRhIGwB9AgAQAAoKCRhIGwB9AgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAABNQAECn8VAAICAAYKzg82IwAvAQACAAYKzg82IwAvAQAAAA==.Geobrando:BAABNQAECn8uAAMXAAoKrxk6PQBrAgAXAAoKrxk6PQBrAgAEAAUK/xR/swArAQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQAECgUIBQAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQASAAAAAA==.',
Gr='Grippindeez:BAABNQAECn8gAAMHAAcKkhEOTgB+AQAHAAcK8Q0OTgB+AQAJAAIKDxw9WABFAAAAAA==.Grêêd:BAAANQADCgQIBwAAAA==.',
Gu='Guidosarduci:BAABNQAECn8nAAMXAAcKthElfgCSAQAXAAcKthElfgCSAQAEAAIKrwNHHQFVAAAAAA==.Guiseppe:BAABNQAECn8bAAMRAAcK6Q9oGwCUAQARAAcKKA9oGwCUAQAdAAMKQA6yHACAAAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQAECgUIBQAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECn9XAAIBAAkK6hcgTgCfAgABAAkK6hcgTgCfAgAAAA==.',
Ho='Holyshortguy:BAACNQAFFH8LAAIKAAUKyQ2CEwBvAQAKAAUKyQ2CEwBvAQA1AAQKfxsAAwoACQriGeIpAMECAAoACQriGeIpAMECABkAAQoAAHOBACkAAAAA.',
Hu='Hustlermag:BAABNQAECn8zAAQMAAkKBBQRMwAwAQAMAAkKRRERMwAwAQAbAAQKBxRDFAAGAQALAAUK5xn/MAADAQAAAA==.',
Hy='Hyperion:BAAANQAECgEIAgABNQAECgYIBAASAAAAAA==.',
Ic='Icelmo:BAACNQAFFH8IAAIBAAIKKwmTEwCBAAABAAIKKwmTEwCBAAA1AAQKfygAAgEACgr5GNdRAJQCAAEACgr5GNdRAJQCAAAA.',
Im='Impact:BAAANQADCgIJAgABNQAFFAYIEQAEAAsSAA==.',
In='Infinit:BAAANQAECgUIBQAAAA==.',
Is='Isuck:BAAANQAECgQIBAAAAA==.',
Ja='Jaskow:BAABNQAECn8hAAIWAAkK5BqIFAClAgAWAAkK5BqIFAClAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Ju='Jusdatip:BAABNQAECn8cAAIeAAcKPQ51IQDBAQAeAAcKPQ51IQDBAQABNQAECgcIJwAXALYRAA==.',
Ka='Kalessandra:BAAANQAECgcIEQAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgQICAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.Kimlin:BAAANQADCgMIAwAAAA==.',
Kr='Krag:BAAANQAECgQIBAABNQAECgoKKAAfABQkAA==.Krasis:BAABNQAECn8VAAINAAoKtxcvdABGAgANAAoKtxcvdABGAgAAAA==.Krazermonk:BAABNQAECn8qAAIYAAkKVRwzFQCrAgAYAAkKVRwzFQCrAgAAAA==.Kristysavage:BAABNQAECn85AAIGAAoKtiMMBQC8AwAGAAoKtiMMBQC8AwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgYIDQABNQAFFAYIFgAWAMQaAA==.',
Li='Lichdawg:BAACNQAFFH8QAAIHAAYKWhSLBADSAQAHAAYKWhSLBADSAQA1AAQKfyMAAgcACQrqI7sWANUCAAcACQrqI7sWANUCAAAA.Lilthorn:BAAANQADCggICQAAAA==.Lithlia:BAAANQADCgMIAQAAAA==.',
Lo='Lofometa:BAAANQADCggICgAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAUICwAKAMkNAA==.',
Lu='Lubu:BAABNQAECn8lAAIVAAkKYxusIwB+AgAVAAkKYxusIwB+AgAAAA==.Luell:BAAANQAECgIIAgAAAA==.Lumen:BAAANQAECgYICwAAAA==.Lumiette:BAABNQAECn8dAAICAAkKyBBqFwC1AQACAAkKyBBqFwC1AQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgASAAAAAA==.',
Ly='Lynai:BAABNQAECn8YAAIUAAgKVQ4WEgCEAQAUAAgKVQ4WEgCEAQAAAA==.',
['Lá']='Lándwhale:BAABNQAECn89AAMeAAoKjyU3AQC/AwAeAAoK1yQ3AQC/AwAFAAUKyx9LGgD4AAAAAA==.',
['Læ']='Lægolas:BAAANQAECgMIBQAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQASAAAAAA==.',
Ma='Macktimus:BAABNQAECn8cAAILAAkKQRpgCAB4AgALAAkKQRpgCAB4AgAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECgoKKAAfABQkAA==.Makili:BAABNQAECn9LAAMPAAkK5SEgOwARAwAPAAkK5SEgOwARAwAUAAEKeAxXUAAnAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAAANQAECgUIEAAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgcIFAAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.Mornedelth:BAAANQAECgUIBQABNQAECgUIEAASAAAAAA==.',
Mu='Murad:BAAANQAECggIDQAAAA==.',
My='Mylodon:BAAANQABCgQIBgAAAA==.Mysternia:BAAANQAECgUIBQAAAA==.',
Ni='Niade:BAACNQAFFH8GAAITAAQKihHlEQBDAQATAAQKihHlEQBDAQA1AAQKfyQAAxMACgq6HbkgAOsCABMACgq6HbkgAOsCAA0ABQpiCIMoAd0AAAAA.Nitpo:BAAANQADCgYIBgAAAA==.',
No='Notorckrag:BAABNQAECn8oAAIfAAoKFCR1AQCzAwAfAAoKFCR1AQCzAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQAFFAIIAgABNQAFFAUIFgAZAK8jAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Od='Odimeer:BAAANQAECgYICgAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAAANQAECgQIEAABNQAECgkJJQAVAGMbAA==.',
Ol='Oldrecipe:BAABNQAECn8hAAITAAkKtxIqSABGAgATAAkKtxIqSABGAgAAAA==.Oliange:BAABNQAECn8fAAMUAAcKaw0mFABnAQAUAAcKaw0mFABnAQAPAAYKEAWJRgEYAQAAAA==.',
Oo='Oopsrofl:BAAANQAECgQICAAAAA==.',
Op='Optimuze:BAAANQAFFAEIAQAAAA==.',
Or='Originalgank:BAACNQAFFH8FAAIPAAQKpAtXGwCRAAAPAAQKpAtXGwCRAAA1AAQKfygAAw8ACgpgHhIxACkDAA8ACgpgHhIxACkDABQAAQr1EQ9LADAAAAAA.Orthox:BAAANQADCgUIBQAAAA==.',
Ot='Otoha:BAAANQADCgYIBgAAAA==.',
Pe='Peachcobbler:BAABNQAECn8bAAIZAAgKiAi+MQCVAQAZAAgKiAi+MQCVAQAAAA==.Peachcrumpet:BAAANQADCgEIAQAAAA==.Peppermint:BAAANQAECgUIDAAAAA==.Pewpsmadness:BAAANQAECgQIBAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAAANQAECgUIDgAAAA==.',
Pl='Plaguerism:BAABNQAECn8iAAMIAAoKNCDvDABSAwAIAAoKyx/vDABSAwAJAAMKghg5jwDHAAABNQAFFAUIEAAbACAlAA==.',
Po='Poo:BAACNQAFFH8MAAIFAAUKMRWhBgCyAQAFAAUKMRWhBgCyAQA1AAQKfzAAAgUACgp9IRMJAEgDAAUACgp9IRMJAEgDAAAA.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgASAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
['Pâ']='Pâiñ:BAAANQADCggIIAAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAABNQAECn8hAAMgAAkKSR9GHADmAgAgAAkKSR9GHADmAgAWAAQK3g3gTwDKAAAAAA==.Rahor:BAABNQAECn8bAAQNAAcKhRIbZQD7AAANAAcKcxIbZQD7AAAcAAIKLB1rUwCWAAATAAEKMAu4ngAuAAABNQAECgkJMwAMAAQUAA==.Rainesage:BAABNQAECn8bAAIZAAcKExr0JQD/AQAZAAcKExr0JQD/AQAAAA==.Ralphel:BAABNQAECn8VAAINAAYK7ANzKQHbAAANAAYK7ANzKQHbAAAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQAECgYIBgAAAA==.',
Rh='Rhubarb:BAABNQAECn8iAAIBAAoK2iPOEwBsAwABAAoK2iPOEwBsAwAAAA==.',
Ri='Riptidepods:BAAANQAECgQIBAAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ru='Rukawa:BAAANQADCgUIBQAAAA==.',
Ry='Rylosh:BAACNQAFFH8eAAIWAAYK4QniAgBrAQAWAAYK4QniAgBrAQA1AAQKfzgAAhYACgo6FAIgACsCABYACgo6FAIgACsCAAAA.',
Sa='Sabornator:BAAANQAECgYIBAAAAA==.Sabot:BAAANQAECgUIBQABNQAECgYIBAASAAAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgASAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECgoKLAAHAJUcAA==.',
Sh='Shamantics:BAAANQAECgEIAQABNQAFFAUIEAAbACAlAA==.Shamerica:BAACNQAFFH8VAAIEAAYK/R2aAgBRAQAEAAYK/R2aAgBRAQA1AAQKfzcAAgQACgq0JDsHAK8DAAQACgq0JDsHAK8DAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAACNQAFFH8GAAIJAAQKdx5BEABSAQAJAAQKdx5BEABSAQA1AAQKfyIAAgkACgowIeQPAC4DAAkACgowIeQPAC4DAAAA.',
Sl='Slagothor:BAABNQAECn8aAAIIAAgKJAbYdQBBAQAIAAgKJAbYdQBBAQAAAA==.',
So='Soultax:BAAANQAECgUIBQAAAA==.',
Sp='Specialedz:BAAANQABCgYICAAAAA==.Spekaleks:BAAANQAECgMIAwAAAA==.Spinfat:BAACNQAFFH8MAAIYAAYKLxYAAwADAQAYAAYKLxYAAwADAQA1AAQKfyoAAhgACgrHIs0KACcDABgACgrHIs0KACcDAAAA.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgYIEQAAAA==.Starbux:BAAANQAECgEIAgABNQAECgkJHAAKAC0MAA==.Stockgodx:BAAANQAECgEIAQAAAA==.',
Su='Sugarr:BAAANQAECgEIAQABNQAECgUIDgASAAAAAA==.',
Sy='Syb:BAAANQAECgUIBQAAAA==.',
Ta='Taeyang:BAABNQAECn8nAAQMAAoKoCPsGgAaAwAMAAkKcyPsGgAaAwALAAEKlyNlYQBiAAAbAAEKFiG6JgBRAAAAAA==.Tankadin:BAAANQADCgcIBwABNQAECgcIIQAGAFgYAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Telafar:BAAANQAECggICAAAAA==.Terraform:BAAANQADCgEIAQAAAA==.',
Th='Theinsider:BAABNQAECn8WAAIMAAoKexXVJgBVAQAMAAoKexXVJgBVAQABNQAECgoKLAAHAJUcAA==.Theoutsider:BAABNQAECn8sAAMHAAoKlRyIHACmAgAHAAkKVRyIHACmAgAIAAgKFRxEQwAOAgAAAA==.',
Ti='Timhair:BAAANQADCgYIFAAAAA==.Tindril:BAAANQADCgYIBgAAAA==.',
To='Toekneess:BAABNQAECn8kAAIKAAoKQyX3AwCwAwAKAAoKQyX3AwCwAwAAAA==.Toekneez:BAAANQAECgcIEAABNQAECgoKJAAKAEMlAA==.Toekneezz:BAABNQAECn8kAAIaAAkKdSPBAwBzAwAaAAkKdSPBAwBzAwABNQAECgoKJAAKAEMlAA==.Totemmalotes:BAAANQADCgMIAwAAAA==.Totemofbear:BAABNQAECn8gAAIhAAgKixKjBgBHAQAhAAgKixKjBgBHAQAAAA==.',
Tr='Trandis:BAABNQAECn8mAAIYAAoK2CL+CABBAwAYAAoK2CL+CABBAwAAAA==.Tranza:BAABNQAECn8hAAIGAAcKWBghgAAMAgAGAAcKWBghgAAMAgAAAA==.Trash:BAAANQAECgEIAQABNQAECgQIBAASAAAAAA==.',
Tx='Tx:BAACNQAFFH8RAAIEAAYKCxLCCADlAQAEAAYKCxLCCADlAQA1AAQKfyUAAgQACQpMH9oeABIDAAQACQpMH9oeABIDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Um='Umei:BAAANQADCgIIAgAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgoKHgAIAPYSAA==.Utterchaos:BAABNQAECn8XAAIcAAUKSx0oKwCEAQAcAAUKSx0oKwCEAQABNQAECgcIJwAXALYRAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQAECgQIBAAAAA==.',
Wa='Wazupp:BAAANQAECggICAAAAA==.',
We='Wematanye:BAAANQADCgYIEQABNQAECgcIHwAfABsRAA==.Wetheals:BAAANQAECgcIDQAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQASAAAAAA==.',
Wo='Worgnfreeman:BAAANQAECggIEAAAAA==.',
Wt='Wtfmonk:BAABNQAECn8iAAIaAAkKgxg+EAB7AgAaAAkKgxg+EAB7AgABNQAFFAUICwAKAMkNAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQAECgUIBQAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAASAAAAAA==.',
Xs='Xsaber:BAAANQADCggILgAAAA==.',
Ya='Yangyin:BAAANQAECgYIBgAAAA==.Yazmo:BAACNQAFFH8WAAIZAAUKryM9AgA5AQAZAAUKryM9AgA5AQA1AAQKfy4AAhkACgo2JXcFAIEDABkACgo2JXcFAIEDAAAA.',
Yu='Yushe:BAAANQAECgIIAgAAAA==.Yuuky:BAABNQAECn80AAIWAAoKChlUEQDJAgAWAAoKChlUEQDJAgAAAA==.',
Za='Zarivia:BAAANQADCgQIBAAAAA==.',
['Ör']='Ördög:BAAANQADCggICwAAAA==.',
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
