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

local lookup = {'Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Paladin-Retribution','DemonHunter-Vengeance','Mage-Arcane','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Restoration','Monk-Windwalker','Priest-Shadow','Monk-Mistweaver','Warlock-Affliction','Paladin-Protection','Evoker-Augmentation','Rogue-Subtlety','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECn8rAAQBAAoKwx6GNADvAgABAAoKwx6GNADvAgACAAEK2BrEPQBMAAADAAIK+ARJLwBDAAAAAA==.Adellon:BAABNQAECn8aAAIEAAkKzhtJNQCjAgAEAAkKzhtJNQCjAgAAAA==.Adhar:BAAANQAECgMIBQAAAA==.Adrielle:BAAANQAECgYIBwAAAA==.',
Ak='Akakage:BAABNQAECn8YAAIFAAgK/hxTKwA8AgAFAAgK/hxTKwA8AgAAAA==.Akakaji:BAAANQAECgYIBwABNQAECggIGAAFAP4cAA==.Akutoku:BAABNQAECn8wAAIGAAoKexubXwBYAgAGAAoKexubXwBYAgAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAABNQAECn8yAAQHAAoKVhDcMgDbAQAHAAoKVhDcMgDbAQAIAAUKngp/kQDjAAAJAAIKUAMPwABIAAAAAA==.Anomander:BAABNQAECn8VAAIKAAoKDgqvJAB2AQAKAAoKDgqvJAB2AQAAAA==.',
Ar='Ar:BAABNQAECn8jAAILAAkKNBYmTwA3AgALAAkKNBYmTwA3AgABNQAECgoKKwABAMMeAA==.Archon:BAABNQAECn9PAAMBAAkKiiTtDgAfAwABAAkKiiTtDgAfAwADAAYKfR4ZDADGAQAAAA==.Arienca:BAABNQAECn8oAAMMAAkKnQ7HEwDSAQAMAAkKnQ7HEwDSAQANAAUKzAM7BAHDAAAAAA==.',
As='Aspir:BAEBNQAECn8gAAIOAAkKDRmtdwA9AgAOAAkKDRmtdwA9AgABNQAFFAYIEgAHAAUWAA==.',
At='At:BAAANQAECgYIBwABNQAECgoKKwABAMMeAA==.',
Au='Auddio:BAAANQAECggIAQAAAA==.',
Ba='Baidoogh:BAAANQAECgIIAwAAAA==.Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCggIDwAAAA==.Bepis:BAABNQAECn8jAAIPAAkK7SAHAwA/AwAPAAkK7SAHAwA/AwAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgYIDAAAAA==.',
Bl='Blazerunner:BAABNQAECn9PAAIQAAoKkRK9UQAcAgAQAAoKkRK9UQAcAgAAAA==.Blazesmasher:BAAANQAECgMIAQABNQAECgoKTwAQAJESAA==.Blitzkreig:BAAANQAECggIDQAAAA==.Blured:BAABNQAECn81AAIKAAoKmyP9AgCqAwAKAAoKmyP9AgCqAwAAAA==.',
Bo='Bombshock:BAAANQAECgEIAQAAAA==.Booty:BAABNQAECn8qAAICAAoKxh7uBQANAwACAAoKxh7uBQANAwAAAA==.Bort:BAABNQAECn8cAAIRAAkKZwfFGQCsAQARAAkKZwfFGQCsAQAAAA==.',
Br='Brevyn:BAABNQAECn8bAAIQAAkKiQgg5gC9AQAQAAkKiQgg5gC9AQAAAA==.Brightblayde:BAAANQAECgYICAAAAA==.',
Bu='Bubblebutt:BAAANQAECgQICAABNQAECggIDAASAAAAAA==.Bulla:BAAANQAECggICwAAAA==.Bung:BAABNQAECn8jAAITAAkKXBd3QQBfAgATAAkKXBd3QQBfAgAAAA==.Buum:BAAANQAECgcIDgAAAA==.',
['Bä']='Bämba:BAAANQADCggIFQABNQAECgkJJAAUANUMAA==.',
Ca='Cali:BAACNQAFFH8WAAMVAAcKBgpMCQCYAQAVAAYKhAhMCQCYAQAKAAQKFQsFCwAbAQA1AAQKf0oAAxUACgq/JDYEAEoDABUACgq/JDYEAEoDAAoACgqqHo4UAMICAAAA.Calipari:BAAANQADCgQIBAABNQAFFAcIFgAVAAYKAA==.Carafe:BAAANQAECgUIBQABNQAECggIGAAWAA8cAA==.Catamara:BAAANQAECgIIBAAAAA==.',
Ce='Cephus:BAACNQAFFH8WAAIXAAYKrBC+BwBvAQAXAAYKrBC+BwBvAQA1AAQKfzkAAxcACgqLFd0jAAYCABcACgqLFd0jAAYCABgAAQrHF7uBAEIAAAAA.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFH8bAAIGAAcKLhS9BQD3AQAGAAcKLhS9BQD3AQA1AAQKf0YAAgYACgr8JMYJAD0DAAYACgr8JMYJAD0DAAAA.Chimeira:BAAANQAECgEIAQAAAA==.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFH8UAAMVAAYKshjqBwCBAQAVAAYKshjqBwCBAQAKAAEKxQpoFgBAAAA1AAQKfzIAAwoACgrvIacWAKsCAAoACQoNHKcWAKsCABUABQoII8hHAIsBAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECn80AAMZAAoKHRxPFgAeAwAZAAoKHRxPFgAeAwAEAAUK9A0GxAAKAQAAAA==.',
Cr='Critlee:BAAANQADCgMIAwAAAA==.',
Cy='Cyclondike:BAAANQAECgQIBAAAAA==.Cynestra:BAAANQAECgcIEAAAAA==.Cyni:BAAANQAECgEIAQABNQAFFAYICAATAF8QAA==.Cytheris:BAAANQADCgIIAgABNQAECgoKNAAZAB0cAA==.',
Da='Dadudadu:BAACNQAFFH8OAAIOAAUK1wecDwBSAQAOAAUK1wecDwBSAQA1AAQKf0kAAg4ACgo5Hx8+AHACAA4ACgo5Hx8+AHACAAAA.Daftmonk:BAACNQAFFH8UAAIaAAYKcR30BACDAQAaAAYKcR30BACDAQA1AAQKf1EAAhoACgrZJVYCALkDABoACgrZJVYCALkDAAAA.Darj:BAABNQAECn8hAAIBAAoKoxMiYwBlAgABAAoKoxMiYwBlAgAAAA==.Darmonevil:BAAANQAECgUIDQAAAA==.Dasarus:BAAANQAECgYIEAAAAA==.Dauntless:BAAANQAECgUIEAAAAA==.',
De='Defknight:BAAANQADCggICAAAAA==.Deth:BAAANQADCgYIBgABNQAECgYIFAAOANgbAA==.Dethblades:BAAANQAECgEIAQABNQAECgYIFAAOANgbAA==.Dethblow:BAABNQAECn8UAAIOAAYK2BvPtABnAQAOAAYK2BvPtABnAQAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgYIFAAOANgbAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECn9GAAMZAAoK5QmdaAB7AQAZAAoK5QmdaAB7AQAEAAcK0AIQxAAKAQAAAA==.',
Dk='Dklot:BAACNQAFFH8FAAMIAAQKigpEDQCGAAAIAAMKigpEDQCGAAAJAAEKAADFNQAAAAA1AAQKfzsAAwgACgonH9gLALoCAAgACgonH9gLALoCAAkABQpJDtFQAPoAAAAA.',
Do='Doomkin:BAAANQAECgUIBgAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECn9EAAIGAAoKNh8rNwDFAgAGAAoKNh8rNwDFAgAAAA==.Dreadgrave:BAABNQAECn8jAAIIAAoKUxf2MgBZAQAIAAoKUxf2MgBZAQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAFFAYICAATAF8QAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
Eg='Egoh:BAABNQAECn8XAAIWAAkKvhjUEQAcAgAWAAkKvhjUEQAcAgABNQAFFAcIHAAbAAQlAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.Eleshkigal:BAAANQAECgQIBQABNQAECgoKKAAaAPIiAA==.',
En='Enkeke:BAABNQAECn82AAIIAAoK5BklLgB5AgAIAAoK5BklLgB5AgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgASAAAAAA==.Eresanna:BAABNQAECn8ZAAIQAAgKiA9M0wDgAQAQAAgKiA9M0wDgAQAAAA==.Erf:BAABNQAECn8oAAIcAAoK8Q4XGwDQAQAcAAoK8Q4XGwDQAQAAAA==.Erinis:BAAANQAECgcIEAABNQAECgoKFQAPAN8NAA==.',
Es='Esdeath:BAABNQAECn8VAAMPAAoK3w1gHwCRAAAVAAgKjwsQUwDXAAAPAAMK0Q5gHwCRAAAAAA==.',
Ex='Extremefear:BAABNQAECn8jAAMMAAoKyQ0ZIABwAAANAAgKywssngAbAQAMAAIKxBMZIABwAAAAAA==.',
Fe='Fearious:BAACNQAFFH8SAAQdAAcKwCTnBQB1AAANAAUKwyQhGwAeAQAdAAEKAADnBQB1AAAMAAEKsiSNFABmAAA1AAQKfygABA0ACgrZJaRJAPcBAA0ABwq5JaRJAPcBAB0AAwqXFKkeAIEAAAwAAgryI+kgAG0AAAAA.Feroond:BAABNQAECn8zAAQJAAoK0B+kCwDXAgAJAAoK0B+kCwDXAgAHAAUKpRMQagD3AAAIAAEKyB34cQBbAAAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fl='Flackjacket:BAAANQADCgUIBQAAAA==.',
Fo='Fools:BAAANQADCggICQABNQAECgoKQwAeANAeAA==.Forfoxsake:BAAANQAECgQIBAAAAA==.',
Fr='Freyja:BAAANQAECgIIAQABNQAECggIDQASAAAAAA==.Frogteeth:BAABNQAECn8UAAIEAAYKfRO1mgBiAQAEAAYKfRO1mgBiAQAAAA==.Frozath:BAAANQAECgUICQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgASAAAAAA==.Fussypants:BAABNQAECn8YAAIeAAgKngjEPwD7AAAeAAgKngjEPwD7AAAAAA==.',
Ga='Gallindral:BAABNQAECn8tAAIKAAoKNBhIGwB9AgAKAAoKNBhIGwB9AgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAABNQAECn8YAAICAAcK5Q42IwAvAQACAAcK5Q42IwAvAQAAAA==.Geobrando:BAABNQAECn8xAAMZAAoKrxk6PQBrAgAZAAoKrxk6PQBrAgAEAAUK/xR/swArAQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gh='Ghuldini:BAAANQADCgcIBwAAAA==.',
Gn='Gnosh:BAAANQAECgcIEAAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQASAAAAAA==.',
Gr='Grippindeez:BAABNQAECn8yAAMJAAkKUxZTLwCSAQAJAAUKnhxTLwCSAQAHAAkK1wyFSQByAQAAAA==.Grêêd:BAAANQADCgQICAAAAA==.',
Gu='Guidosarduci:BAABNQAECn8nAAMZAAcKthElfgCSAQAZAAcKthElfgCSAQAEAAIKrwNHHQFVAAAAAA==.Guiseppe:BAABNQAECn8bAAMRAAcK6Q9oGwCUAQARAAcKKA9oGwCUAQAfAAMKQA6yHACAAAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQAECgcIEAAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECn9eAAIBAAkK6hcgTgCfAgABAAkK6hcgTgCfAgAAAA==.',
Ho='Holyshortguy:BAACNQAFFH8RAAILAAcKsw6xEACcAQALAAcKsw6xEACcAQA1AAQKfykAAwsACgqlG+IpAMECAAsACgqlG+IpAMECABsAAQoAAHOBACkAAAAA.',
Hu='Hustlermag:BAACNQAFFH8GAAQdAAMKFxRjBgCjAAAdAAIK9xBjBgCjAAANAAIK1RZsIwCiAAAMAAEK4hUvDwBQAAA1AAQKf1IABA0ACgpTHykeAJ0CAA0ACgokHikeAJ0CAB0ABQoZGEMUAAYBAAwABQonHB4OAOIAAAAA.Huñter:BAAANQABCgIIAgABNQAECggIDAASAAAAAA==.',
Hy='Hyperion:BAAANQAECgEIAgABNQAECgcIEAASAAAAAA==.',
Ic='Icelmo:BAACNQAFFH8KAAIBAAQKbg0oFAASAQABAAQKbg0oFAASAQA1AAQKfy8AAgEACgpyHNdRAJQCAAEACgpyHNdRAJQCAAAA.',
Im='Impact:BAAANQADCgIJAgABNQAFFAYIEQAEAAsSAA==.',
In='Infinit:BAABNQAECn8lAAIOAAoK9hu0NgCKAgAOAAoK9hu0NgCKAgAAAA==.',
Is='Isuck:BAAANQAECgYIEgAAAA==.',
Ja='Jaskow:BAABNQAECn8hAAIXAAkK5BqIFAClAgAXAAkK5BqIFAClAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Jo='Jobewright:BAAANQADCgQIBwAAAA==.',
Ju='Jusdatip:BAABNQAECn8cAAIgAAcKPQ51IQDBAQAgAAcKPQ51IQDBAQABNQAECgcIJwAZALYRAA==.',
Ka='Kalessandra:BAABNQAECn8pAAIQAAkKHhdLWgAGAgAQAAkKHhdLWgAGAgAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgQICAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.Kimlin:BAAANQADCgMIAwAAAA==.',
Kr='Krag:BAAANQAECgQIBAABNQAECgoKKwAhAMIkAA==.Krasis:BAABNQAECn8lAAIOAAoKhCJ6HwDjAgAOAAoKhCJ6HwDjAgAAAA==.Krazermonk:BAACNQAFFH8FAAIaAAQK4gwDDwCHAAAaAAQK4gwDDwCHAAA1AAQKfzgAAhoACgpYHP8PAFwCABoACgpYHP8PAFwCAAAA.Kristysavage:BAABNQAECn9WAAIGAAoKuCUMBQC8AwAGAAoKuCUMBQC8AwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgcIDgABNQAFFAgIIQAXABcaAA==.',
Li='Lichdawg:BAACNQAFFH8RAAIHAAYKWhSLBADSAQAHAAYKWhSLBADSAQA1AAQKfzoAAgcACgoGJIISALsCAAcACgoGJIISALsCAAAA.Lilthorn:BAAANQADCggICQAAAA==.Lithlia:BAAANQADCgQIBgAAAA==.',
Lo='Lofometa:BAAANQADCggICgAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAcIEQALALMOAA==.',
Lu='Lubu:BAABNQAECn83AAIVAAkKYyCLDQDNAgAVAAkKYyCLDQDNAgABNQAECgoKFQAPAN8NAA==.Luell:BAAANQAECgIIAgAAAA==.Lumen:BAAANQAECgYICwAAAA==.Lumiette:BAABNQAECn8fAAICAAkKyBBqFwC1AQACAAkKyBBqFwC1AQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgASAAAAAA==.',
Ly='Lynai:BAABNQAECn8gAAIUAAkKOw4WEgCEAQAUAAkKOw4WEgCEAQAAAA==.',
['Lá']='Lándwhale:BAABNQAECn9BAAMgAAoK8SU3AQC/AwAgAAoKziU3AQC/AwAFAAUKyx+mKgDnAAAAAA==.',
['Læ']='Lægolas:BAAANQAECgQICQAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQASAAAAAA==.',
Ma='Macktimus:BAABNQAECn8cAAIMAAkKQRpgCAB4AgAMAAkKQRpgCAB4AgAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECgoKKwAhAMIkAA==.Makili:BAABNQAECn9LAAMQAAkK5SEgOwARAwAQAAkK5SEgOwARAwAUAAEKeAxXUAAnAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAABNQAECn8YAAIWAAgKDxy3IAB9AQAWAAgKDxy3IAB9AQAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgYIFAAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.Mornedelth:BAAANQAECgUIBQABNQAECggIGAAWAA8cAA==.',
Mu='Murad:BAABNQAECn8ZAAIIAAkKghdcHgDvAQAIAAkKghdcHgDvAQAAAA==.',
My='Mylodon:BAAANQABCgQIBgAAAA==.Mysternia:BAAANQAECgcIEAAAAA==.',
Ni='Niade:BAACNQAFFH8IAAITAAYKXxDlEQBDAQATAAYKXxDlEQBDAQA1AAQKfygAAxMACgoDH7kgAOsCABMACgoDH7kgAOsCAA4ABQpiCIMoAd0AAAAA.Nitpo:BAAANQADCgYIBgAAAA==.',
No='Notorckrag:BAABNQAECn8rAAIhAAoKwiR1AQCzAwAhAAoKwiR1AQCzAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQAFFAIIAgABNQAFFAcIHAAbAAQlAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Ob='Obtutas:BAAANQADCggICQABNQAECgQICAASAAAAAA==.',
Od='Odimeer:BAAANQAECgYIDQAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAABNQAECn8dAAIeAAcK4BVjIwBTAQAeAAcK4BVjIwBTAQABNQAECgoKFQAPAN8NAA==.',
Ol='Oldrecipe:BAABNQAECn8rAAITAAoKGhdTPAAmAgATAAoKGhdTPAAmAgAAAA==.Oliange:BAABNQAECn8kAAMUAAkK1QwmFABnAQAUAAkK1QwmFABnAQAQAAYKEAWJRgEYAQAAAA==.',
Oo='Oopsrofl:BAABNQAECn8qAAITAAoKjyE+BgC6AwATAAoKjyE+BgC6AwAAAA==.',
Op='Optimuze:BAAANQAFFAEIAQAAAA==.',
Or='Originalgank:BAACNQAFFH8JAAMQAAQKBxGZOADjAAAQAAQKpAuZOADjAAAUAAEKUxdqFABKAAA1AAQKf0AAAxAACgpGIsgaANgCABAACgpGIsgaANgCABQAAQpCHQM3AFEAAAAA.Orthox:BAAANQADCgUIBQAAAA==.',
Ot='Otoha:BAAANQADCgYIBwAAAA==.',
Pe='Peachcobbler:BAABNQAECn8jAAIbAAoKjwi+MQCVAQAbAAoKjwi+MQCVAQAAAA==.Peachcrumpet:BAAANQADCgEIAQAAAA==.Peppermint:BAABNQAECn8bAAILAAkK7RzCKgCfAgALAAkK7RzCKgCfAgAAAA==.Pewpsmadness:BAAANQAECgQIBAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAABNQAECn8fAAIGAAoKLhcJRwBDAgAGAAoKLhcJRwBDAgAAAA==.',
Pl='Plaguerism:BAABNQAECn8kAAMIAAoKtiDvDABSAwAIAAoKTSDvDABSAwAJAAMKghg5jwDHAAABNQAFFAcIEgAdAMAkAA==.',
Po='Poo:BAACNQAFFH8SAAMFAAUKMRWhBgCyAQAFAAUKMRWhBgCyAQAgAAQKnwafFwDIAAA1AAQKf0sAAwUACgqZIhMJAEgDAAUACgp9IRMJAEgDACAACgqTHloSAOUCAAAA.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgASAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
Pu='Puck:BAAANQAECgcIDAABNQAECgoKFQAPAN8NAA==.',
['Pâ']='Pâiñ:BAAANQAECgQIBAAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAABNQAECn83AAMYAAoKpCFGHADmAgAYAAoKpCFGHADmAgAXAAQK3g3gTwDKAAAAAA==.Rahor:BAABNQAECn8jAAQOAAgKhxFwtwCvAQAOAAgKeRFwtwCvAQAeAAIKLB1rUwCWAAATAAIKxwaF6QBGAAABNQAFFAMIBgAdABcUAA==.Rainesage:BAABNQAECn8kAAMbAAoKPRf0JQD/AQAbAAoKPRf0JQD/AQALAAQKwg/SrQDYAAAAAA==.Ralphel:BAABNQAECn8VAAIOAAYK7ANzKQHbAAAOAAYK7ANzKQHbAAAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQAECgcIDgAAAA==.',
Rh='Rhubarb:BAABNQAECn8vAAIBAAoKUCTOEwBsAwABAAoKUCTOEwBsAwAAAA==.',
Ri='Riptidepods:BAAANQAECgQIBAAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ru='Rugob:BAAANQADCggICAAAAA==.Rukawa:BAAANQADCggICQAAAA==.',
Ry='Rylorthas:BAAANQAECgcIBwABNQAFFAcIHwAXAAQJAA==.Rylosh:BAACNQAFFH8fAAIXAAcKBAkIBwCFAQAXAAcKBAkIBwCFAQA1AAQKf0wAAhcACgqwGrwRAKwCABcACgqwGrwRAKwCAAAA.',
Sa='Sabornator:BAAANQAECgYIBgABNQAECgcIEAASAAAAAA==.Sabot:BAAANQAECgcIEAAAAA==.Samaximilan:BAAANQAECgUIBQAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgASAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECgoKLwAHAGgdAA==.',
Sh='Shamantics:BAAANQAECgEIAQABNQAFFAcIEgAdAMAkAA==.Shamerica:BAACNQAFFH8bAAIEAAcKDB8NBgAeAgAEAAcKDB8NBgAeAgA1AAQKf0kAAgQACgoaJdwFAFEDAAQACgoaJdwFAFEDAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAACNQAFFH8IAAIJAAYKmh9BEABSAQAJAAYKmh9BEABSAQA1AAQKfyIAAgkACgowIeQPAC4DAAkACgowIeQPAC4DAAAA.',
Sl='Slagothor:BAABNQAECn8aAAIIAAgKJAbYdQBBAQAIAAgKJAbYdQBBAQAAAA==.',
So='Soultax:BAAANQAECgcIEAAAAA==.',
Sp='Spekaleks:BAAANQAECgQIBwAAAA==.Spinfat:BAACNQAFFH8PAAIaAAcK7hdCBgBDAQAaAAcK7hdCBgBDAQA1AAQKfzcAAhoACgrGJRkBAHsDABoACgrGJRkBAHsDAAAA.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgcIEQAAAA==.Starbux:BAAANQAECgUIEwABNQAECgoKJgALANQOAA==.Starbúcks:BAAANQAECgEIAQABNQAECgoKJgALANQOAA==.Stockgodx:BAAANQAECgQICQAAAA==.',
Su='Sugarr:BAAANQAECgEIAQABNQAECgoKHwAGAC4XAA==.',
Sy='Syb:BAAANQAECgcIEAAAAA==.',
Ta='Taeyang:BAABNQAECn8wAAQNAAoKDiTsGgAaAwANAAkK0CPsGgAaAwAMAAEKgiTnJABiAAAdAAEKFiG6JgBRAAAAAA==.Tankadin:BAAANQADCgcIBwABNQAECggIIgAGAOUVAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Telafar:BAAANQAECggIEAAAAA==.Terraform:BAAANQADCgEIAQAAAA==.',
Th='Thavus:BAAANQADCgMIAwAAAA==.Theinsider:BAABNQAECn8WAAINAAoKghXEcQALAgANAAoKghXEcQALAgABNQAECgoKLwAHAGgdAA==.Theoutsider:BAABNQAECn8vAAMHAAoKaB2IHACmAgAHAAkKJx2IHACmAgAIAAgKFRxEQwAOAgAAAA==.',
Ti='Timhair:BAAANQADCgcIIwAAAA==.Tindril:BAAANQADCgYIBgAAAA==.Tinkerstorm:BAAANQADCgYICwABNQAFFAUIEAATAJcXAA==.',
To='Toekneess:BAABNQAECn8vAAILAAoKuiX3AwCwAwALAAoKuiX3AwCwAwAAAA==.Toekneez:BAAANQAECgcIEgABNQAECgoKLwALALolAA==.Toekneezz:BAABNQAECn8nAAIcAAkKdSPBAwBzAwAcAAkKdSPBAwBzAwABNQAECgoKLwALALolAA==.Totemmalotes:BAAANQADCgMIAwAAAA==.Totemofbear:BAABNQAECn8uAAIiAAoKQhVRDgDlAQAiAAoKQhVRDgDlAQAAAA==.',
Tr='Trandis:BAABNQAECn8oAAMaAAoK8iL+CABBAwAaAAoK8iL+CABBAwAcAAEKEQanQwAgAAAAAA==.Tranza:BAABNQAECn8iAAIGAAgK5RUhgAAMAgAGAAgK5RUhgAAMAgAAAA==.Trash:BAAANQAECgEIAQABNQAECgYIEgASAAAAAA==.',
Tx='Tx:BAACNQAFFH8RAAIEAAYKCxLCCADlAQAEAAYKCxLCCADlAQA1AAQKfyUAAgQACQpMH9oeABIDAAQACQpMH9oeABIDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Um='Umei:BAAANQADCgIIAgAAAA==.',
Un='Unheilige:BAAANQAECgMIAwAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgoKIwAIAFMXAA==.Utterchaos:BAABNQAECn8XAAIeAAUKSx0oKwCEAQAeAAUKSx0oKwCEAQABNQAECgcIJwAZALYRAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQAECgQIBAAAAA==.',
Wa='Wazupp:BAAANQAECggICAAAAA==.',
We='Wematanye:BAAANQADCgYIHAABNQAECgkJLwAhAIcPAA==.Wetheals:BAAANQAECgcIDQAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQASAAAAAA==.',
Wo='Wongfaihong:BAAANQABCgMIAwAAAA==.Worgnfreeman:BAABNQAECn8ZAAQJAAkKJgSCfQBtAAAJAAUKwAaCfQBtAAAHAAIKawKsvAAhAAAIAAgKQQHG+QAeAAAAAA==.',
Wt='Wtfmate:BAAANQAECgUIBgABNQAFFAcIEQALALMOAA==.Wtfmonk:BAABNQAECn8sAAIcAAoKfBc+EAB7AgAcAAoKfBc+EAB7AgABNQAFFAcIEQALALMOAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQAECgcIEAAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAASAAAAAA==.',
Xs='Xsaber:BAAANQAECgMIBQAAAA==.',
Ya='Yangyin:BAAANQAECggIDgAAAA==.Yazmo:BAACNQAFFH8cAAIbAAcKBCUGAwAGAgAbAAcKBCUGAwAGAgA1AAQKfzsAAhsACgoZJncFAIEDABsACgoZJncFAIEDAAAA.',
Yu='Yushe:BAAANQAECgIIAgAAAA==.Yuuky:BAABNQAECn89AAIXAAoKIhxUEQDJAgAXAAoKIhxUEQDJAgAAAA==.',
Za='Zarivia:BAAANQADCgQIBAAAAA==.',
['Ða']='Ðaholyßeef:BAAANQAECgIIAQABNQAECgoKPwANALwfAA==.',
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
