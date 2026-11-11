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
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECn8rAAQBAAoKwx6GNADvAgABAAoKwx6GNADvAgACAAEK2BrEPQBMAAADAAIK+ARJLwBDAAAAAA==.Adellon:BAABNQAECn8aAAIEAAkKzhtJNQCjAgAEAAkKzhtJNQCjAgAAAA==.Adhar:BAAANQAECgMIBQAAAA==.Adrielle:BAAANQAECgYIBwAAAA==.',
Ak='Akakage:BAABNQAECn8YAAIFAAgK/hxTKwA8AgAFAAgK/hxTKwA8AgAAAA==.Akakaji:BAAANQAECgYIBwABNQAECggIGAAFAP4cAA==.Akutoku:BAABNQAECn8pAAIGAAoKQhubXwBYAgAGAAoKQhubXwBYAgAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAABNQAECn8yAAQHAAoKVhD+LQDgAQAHAAoKVhD+LQDgAQAIAAUKngp/kQDjAAAJAAIKUAMPwABIAAAAAA==.Anomander:BAABNQAECn8VAAIKAAoKDgrWIQB6AQAKAAoKDgrWIQB6AQAAAA==.',
Ar='Ar:BAABNQAECn8jAAILAAkKNBYmTwA3AgALAAkKNBYmTwA3AgABNQAECgoKKwABAMMeAA==.Archon:BAABNQAECn9LAAMBAAkKiiQNDQAmAwABAAkKiiQNDQAmAwADAAQKKCDWEwAiAQAAAA==.Arienca:BAABNQAECn8oAAMMAAkKnQ7HEwDSAQAMAAkKnQ7HEwDSAQANAAUKzAM7BAHDAAAAAA==.',
As='Aspir:BAEBNQAECn8gAAIOAAkKDRkubwDeAQAOAAkKDRkubwDeAQABNQAFFAYIEgAHAAUWAA==.',
At='At:BAAANQAECgYIBwABNQAECgoKKwABAMMeAA==.',
Au='Auddio:BAAANQAECggIAQAAAA==.',
Ba='Baidoogh:BAAANQAECgIIAwAAAA==.Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCggIDwAAAA==.Bepis:BAABNQAECn8jAAIPAAkK7SAHAwA/AwAPAAkK7SAHAwA/AwAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgYIDAAAAA==.',
Bl='Blazerunner:BAABNQAECn9FAAIQAAoKdhDLVgD/AQAQAAoKdhDLVgD/AQAAAA==.Blazesmasher:BAAANQAECgMIAQABNQAECgoKRQAQAHYQAA==.Blitzkreig:BAAANQAECggIDAAAAA==.Blured:BAABNQAECn81AAIKAAoKmyP9AgCqAwAKAAoKmyP9AgCqAwAAAA==.',
Bo='Bombshock:BAAANQAECgEIAQAAAA==.Booty:BAABNQAECn8qAAICAAoKxh7uBQANAwACAAoKxh7uBQANAwAAAA==.Bort:BAABNQAECn8cAAIRAAkKZwfFGQCsAQARAAkKZwfFGQCsAQAAAA==.',
Br='Brevyn:BAABNQAECn8bAAIQAAkKiQgg5gC9AQAQAAkKiQgg5gC9AQAAAA==.Brightblayde:BAAANQAECgYICAAAAA==.',
Bu='Bubblebutt:BAAANQAECgQICAABNQAECggIDAASAAAAAA==.Bulla:BAAANQAECgcICgAAAA==.Bung:BAABNQAECn8jAAITAAkKXBd3QQBfAgATAAkKXBd3QQBfAgAAAA==.Buum:BAAANQAECgcIDQAAAA==.',
['Bä']='Bämba:BAAANQADCggIFQABNQAECggIIQAUADYNAA==.',
Ca='Cali:BAACNQAFFH8WAAMVAAcKBgpMCQCYAQAVAAYKhAhMCQCYAQAKAAQKFQsFCwAbAQA1AAQKf0oAAxUACgq/JMoDAE0DABUACgq/JMoDAE0DAAoACgqqHo4UAMICAAAA.Calipari:BAAANQADCgQIBAABNQAFFAcIFgAVAAYKAA==.Carafe:BAAANQAECgUIBQABNQAECggIGAAWAA8cAA==.Catamara:BAAANQAECgIIBAAAAA==.',
Ce='Cephus:BAACNQAFFH8WAAIXAAYKrBDqBgBvAQAXAAYKrBDqBgBvAQA1AAQKfzkAAxcACgqLFd0jAAYCABcACgqLFd0jAAYCABgAAQrHF+F7AEIAAAAA.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFH8bAAIGAAcKLhS9BQD3AQAGAAcKLhS9BQD3AQA1AAQKf0YAAgYACgr8JPwHAEYDAAYACgr8JPwHAEYDAAAA.Chimeira:BAAANQAECgEIAQAAAA==.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFH8UAAMVAAYKshg/BgCIAQAVAAYKshg/BgCIAQAKAAEKxQpoFgBAAAA1AAQKfzIAAwoACgrvIacWAKsCAAoACQoNHKcWAKsCABUABQoII8hHAIsBAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECn80AAMZAAoKHRxPFgAeAwAZAAoKHRxPFgAeAwAEAAUK9A0GxAAKAQAAAA==.',
Cr='Critlee:BAAANQADCgMIAwAAAA==.',
Cy='Cyclondike:BAAANQAECgQIBAAAAA==.Cynestra:BAAANQAECgcIDwAAAA==.Cyni:BAAANQAECgEIAQABNQAFFAUIBwATAJgQAA==.Cytheris:BAAANQADCgIIAgABNQAECgoKNAAZAB0cAA==.',
Da='Dadudadu:BAACNQAFFH8OAAIOAAUK1wecDwBSAQAOAAUK1wecDwBSAQA1AAQKf0gAAg4ACgqSHsA6AG0CAA4ACgqSHsA6AG0CAAAA.Daftmonk:BAACNQAFFH8UAAIaAAYKcR3qAwCMAQAaAAYKcR3qAwCMAQA1AAQKf1EAAhoACgrZJVYCALkDABoACgrZJVYCALkDAAAA.Darj:BAABNQAECn8hAAIBAAoKoxMiYwBlAgABAAoKoxMiYwBlAgAAAA==.Darmonevil:BAAANQAECgUIDQAAAA==.Dasarus:BAAANQAECgcIDgAAAA==.Dauntless:BAAANQAECgUIDwAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgUIEAASAAAAAA==.Dethblades:BAAANQAECgEIAQABNQAECgUIEAASAAAAAA==.Dethblow:BAAANQAECgUIEAAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgUIEAASAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECn9GAAMZAAoK5QngYAB+AQAZAAoK5QngYAB+AQAEAAcK0AIQxAAKAQAAAA==.',
Dk='Dklot:BAACNQAFFH8FAAMIAAQKigoZDACGAAAIAAMKigoZDACGAAAJAAEKAABQMgAAAAA1AAQKfzsAAwgACgonH5MKAMECAAgACgonH5MKAMECAAkABQpJDqZLAAABAAAA.',
Do='Doomkin:BAAANQAECgUIBgAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECn9AAAIGAAoK4RwrNwDFAgAGAAoK4RwrNwDFAgAAAA==.Dreadgrave:BAABNQAECn8jAAIIAAoKUxfyLwBZAQAIAAoKUxfyLwBZAQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAFFAUIBwATAJgQAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
Eg='Egoh:BAABNQAECn8XAAIWAAkKvhgXEAAhAgAWAAkKvhgXEAAhAgABNQAFFAcIHAAbAAQlAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.Eleshkigal:BAAANQAECgQIBQABNQAECgoKKAAaAPIiAA==.',
En='Enkeke:BAABNQAECn82AAIIAAoK5BklLgB5AgAIAAoK5BklLgB5AgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgASAAAAAA==.Eresanna:BAABNQAECn8ZAAIQAAgKiA9M0wDgAQAQAAgKiA9M0wDgAQAAAA==.Erf:BAABNQAECn8oAAIcAAoK8Q4XGwDQAQAcAAoK8Q4XGwDQAQAAAA==.Erinis:BAAANQAECgYIEAABNQAECgoKFQAPAN8NAA==.',
Es='Esdeath:BAABNQAECn8VAAMPAAoK3w0VHQCRAAAVAAgKjwsATgDYAAAPAAMK0Q4VHQCRAAAAAA==.',
Ex='Extremefear:BAABNQAECn8cAAMNAAkKjA5c1gAdAQANAAcKdQxc1gAdAQAMAAIKxBPJVgB6AAAAAA==.',
Fe='Fearious:BAACNQAFFH8SAAQdAAcKwCTnBQB1AAANAAUKwyQhGwAeAQAdAAEKAADnBQB1AAAMAAEKsiSNFABmAAA1AAQKfygABA0ACgrZJRFDAPoBAA0ABwq5JRFDAPoBAB0AAwqXFCMcAIIAAAwAAgryI84eAG4AAAAA.Feroond:BAABNQAECn8qAAMJAAoKih9HDADIAgAJAAoKih9HDADIAgAHAAUKpRMQagD3AAAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fl='Flackjacket:BAAANQADCgEIAQAAAA==.',
Fo='Fools:BAAANQADCggICQABNQAECgoKQQAeANAeAA==.Forfoxsake:BAAANQAECgQIBAAAAA==.',
Fr='Freyja:BAAANQAECgIIAQABNQAECggIDAASAAAAAA==.Frogteeth:BAABNQAECn8UAAIEAAYKfRO1mgBiAQAEAAYKfRO1mgBiAQAAAA==.Frozath:BAAANQAECgUICQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgASAAAAAA==.Fussypants:BAABNQAECn8YAAIeAAgKngjEPwD7AAAeAAgKngjEPwD7AAAAAA==.',
Ga='Gallindral:BAABNQAECn8tAAIKAAoKNBhIGwB9AgAKAAoKNBhIGwB9AgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAABNQAECn8WAAICAAcK5Q42IwAvAQACAAcK5Q42IwAvAQAAAA==.Geobrando:BAABNQAECn8xAAMZAAoKrxk6PQBrAgAZAAoKrxk6PQBrAgAEAAUK/xR/swArAQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gh='Ghuldini:BAAANQADCgcIBwAAAA==.',
Gn='Gnosh:BAAANQAECgcIDwAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQASAAAAAA==.',
Gr='Grippindeez:BAABNQAECn8yAAMJAAkKUxY2LACWAQAJAAUKnhw2LACWAQAHAAkK1wwuQwB3AQAAAA==.Grêêd:BAAANQADCgQICAAAAA==.',
Gu='Guidosarduci:BAABNQAECn8nAAMZAAcKthElfgCSAQAZAAcKthElfgCSAQAEAAIKrwNHHQFVAAAAAA==.Guiseppe:BAABNQAECn8bAAMRAAcK6Q9oGwCUAQARAAcKKA9oGwCUAQAfAAMKQA6yHACAAAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQAECgcIDwAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECn9eAAIBAAkK6hcgTgCfAgABAAkK6hcgTgCfAgAAAA==.',
Ho='Holyshortguy:BAACNQAFFH8RAAILAAcKsw4bDgCmAQALAAcKsw4bDgCmAQA1AAQKfykAAwsACgqnG+IpAMECAAsACgqnG+IpAMECABsAAQoAAHOBACkAAAAA.',
Hu='Hustlermag:BAABNQAECn9KAAQNAAoKQR5UIACFAgANAAoKEh1UIACFAgAdAAQKeBdDFAAGAQAMAAUKkhtmDgDWAAAAAA==.Huñter:BAAANQABCgIIAgABNQAECggIDAASAAAAAA==.',
Hy='Hyperion:BAAANQAECgEIAgABNQAECgcIDwASAAAAAA==.',
Ic='Icelmo:BAACNQAFFH8JAAIBAAMK+RDNGADWAAABAAMK+RDNGADWAAA1AAQKfy8AAgEACgpyHNdRAJQCAAEACgpyHNdRAJQCAAAA.',
Im='Impact:BAAANQADCgIJAgABNQAFFAYIEQAEAAsSAA==.',
In='Infinit:BAABNQAECn8dAAIOAAoKHBr6PgBeAgAOAAoKHBr6PgBeAgAAAA==.',
Is='Isuck:BAAANQAECgYIEgAAAA==.',
Ja='Jaskow:BAABNQAECn8hAAIXAAkK5BqIFAClAgAXAAkK5BqIFAClAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Jo='Jobewright:BAAANQADCgMIAwAAAA==.',
Ju='Jusdatip:BAABNQAECn8cAAIgAAcKPQ51IQDBAQAgAAcKPQ51IQDBAQABNQAECgcIJwAZALYRAA==.',
Ka='Kalessandra:BAABNQAECn8nAAIQAAkKpxMyYwDfAQAQAAkKpxMyYwDfAQAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgQICAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.Kimlin:BAAANQADCgMIAwAAAA==.',
Kr='Krag:BAAANQAECgQIBAABNQAECgoKKwAhAMIkAA==.Krasis:BAABNQAECn8lAAIOAAoKhCJXGwDsAgAOAAoKhCJXGwDsAgAAAA==.Krazermonk:BAACNQAFFH8FAAIaAAQK4gyODQCIAAAaAAQK4gyODQCIAAA1AAQKfzgAAhoACgpYHKsOAF4CABoACgpYHKsOAF4CAAAA.Kristysavage:BAABNQAECn9NAAIGAAoKsCUMBQC8AwAGAAoKsCUMBQC8AwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgcIDgABNQAFFAcIHwAXADwbAA==.',
Li='Lichdawg:BAACNQAFFH8RAAIHAAYKWhSLBADSAQAHAAYKWhSLBADSAQA1AAQKfzoAAgcACgoGJAsQAMUCAAcACgoGJAsQAMUCAAAA.Lilthorn:BAAANQADCggICQAAAA==.Lithlia:BAAANQADCgQIBQAAAA==.',
Lo='Lofometa:BAAANQADCggICgAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAcIEQALALMOAA==.',
Lu='Lubu:BAABNQAECn8zAAIVAAkKQh5xEwB2AgAVAAkKQh5xEwB2AgABNQAECgoKFQAPAN8NAA==.Luell:BAAANQAECgIIAgAAAA==.Lumen:BAAANQAECgYICwAAAA==.Lumiette:BAABNQAECn8fAAICAAkKyBBqFwC1AQACAAkKyBBqFwC1AQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgASAAAAAA==.',
Ly='Lynai:BAABNQAECn8fAAIUAAgK/A4WEgCEAQAUAAgK/A4WEgCEAQAAAA==.',
['Lá']='Lándwhale:BAABNQAECn9BAAMgAAoK8SU3AQC/AwAgAAoKziU3AQC/AwAFAAUKyx/DKADrAAAAAA==.',
['Læ']='Lægolas:BAAANQAECgQICQAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQASAAAAAA==.',
Ma='Macktimus:BAABNQAECn8cAAIMAAkKQRpgCAB4AgAMAAkKQRpgCAB4AgAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECgoKKwAhAMIkAA==.Makili:BAABNQAECn9LAAMQAAkK5SEgOwARAwAQAAkK5SEgOwARAwAUAAEKeAxXUAAnAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAABNQAECn8YAAIWAAgKDxyNHQCAAQAWAAgKDxyNHQCAAQAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgYIFAAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.Mornedelth:BAAANQAECgUIBQABNQAECggIGAAWAA8cAA==.',
Mu='Murad:BAAANQAECggIEwAAAA==.',
My='Mylodon:BAAANQABCgQIBgAAAA==.Mysternia:BAAANQAECgcIDwAAAA==.',
Ni='Niade:BAACNQAFFH8HAAITAAUKmBDlEQBDAQATAAUKmBDlEQBDAQA1AAQKfygAAxMACgoDH7kgAOsCABMACgoDH7kgAOsCAA4ABQpiCIMoAd0AAAAA.Nitpo:BAAANQADCgYIBgAAAA==.',
No='Notorckrag:BAABNQAECn8rAAIhAAoKwiR1AQCzAwAhAAoKwiR1AQCzAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQAFFAIIAgABNQAFFAcIHAAbAAQlAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Ob='Obtutas:BAAANQADCggICQABNQAECgQICAASAAAAAA==.',
Od='Odimeer:BAAANQAECggIDAAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAABNQAECn8bAAIeAAcKrRWQIABTAQAeAAcKrRWQIABTAQABNQAECgoKFQAPAN8NAA==.',
Ol='Oldrecipe:BAACNQAFFH8FAAITAAQKwQXEGQChAAATAAQKwQXEGQChAAA1AAQKfysAAhMACgoaFy42ADACABMACgoaFy42ADACAAAA.Oliange:BAABNQAECn8hAAMUAAgKNg0mFABnAQAUAAgKNg0mFABnAQAQAAYKEAWJRgEYAQAAAA==.',
Oo='Oopsrofl:BAABNQAECn8jAAITAAoKjh6JDABXAwATAAoKjh6JDABXAwAAAA==.',
Op='Optimuze:BAAANQAFFAEIAQAAAA==.',
Or='Originalgank:BAACNQAFFH8JAAMQAAQKBxGZOADjAAAQAAQKpAuZOADjAAAUAAEKUxd9EgBKAAA1AAQKfzcAAxAACgpGIhIxACkDABAACgpGIhIxACkDABQAAQpCHYEzAFEAAAAA.Orthox:BAAANQADCgUIBQAAAA==.',
Ot='Otoha:BAAANQADCgYIBwAAAA==.',
Pe='Peachcobbler:BAABNQAECn8jAAIbAAoKjwi+MQCVAQAbAAoKjwi+MQCVAQAAAA==.Peachcrumpet:BAAANQADCgEIAQAAAA==.Peppermint:BAABNQAECn8ZAAILAAcKnxvZUADgAQALAAcKnxvZUADgAQAAAA==.Pewpsmadness:BAAANQAECgQIBAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAABNQAECn8fAAIGAAoKLhcfPQBMAgAGAAoKLhcfPQBMAgAAAA==.',
Pl='Plaguerism:BAABNQAECn8kAAMIAAoKtiDvDABSAwAIAAoKTSDvDABSAwAJAAMKghg5jwDHAAABNQAFFAcIEgAdAMAkAA==.',
Po='Poo:BAACNQAFFH8SAAMFAAUKMRWhBgCyAQAFAAUKMRWhBgCyAQAgAAQKnwaQFQDIAAA1AAQKf0sAAwUACgqZIhMJAEgDAAUACgp9IRMJAEgDACAACgqTHtgQAOgCAAAA.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgASAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
Pu='Puck:BAAANQAECgUICQABNQAECgoKFQAPAN8NAA==.',
['Pâ']='Pâiñ:BAAANQAECgQIBAAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAABNQAECn8wAAMYAAoKpCFGHADmAgAYAAoKpCFGHADmAgAXAAQK3g3gTwDKAAAAAA==.Rahor:BAABNQAECn8jAAQOAAgKhxFwtwCvAQAOAAgKeRFwtwCvAQAeAAIKLB1rUwCWAAATAAIKxwZf4ABGAAABNQAECgoKSgANAEEeAA==.Rainesage:BAABNQAECn8dAAIbAAkKoRj0JQD/AQAbAAkKoRj0JQD/AQAAAA==.Ralphel:BAABNQAECn8VAAIOAAYK7ANzKQHbAAAOAAYK7ANzKQHbAAAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQAECggICgAAAA==.',
Rh='Rhubarb:BAABNQAECn8vAAIBAAoKUCTOEwBsAwABAAoKUCTOEwBsAwAAAA==.',
Ri='Riptidepods:BAAANQAECgQIBAAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ru='Rugob:BAAANQADCggICAAAAA==.Rukawa:BAAANQADCggICQAAAA==.',
Ry='Rylorthas:BAAANQAECgcIBwABNQAFFAYIHgAXAOoJAA==.Rylosh:BAACNQAFFH8eAAIXAAYK6gnoBgCVAQAXAAYK6gnoBgCVAQA1AAQKf0wAAhcACgqwGhAQAK4CABcACgqwGhAQAK4CAAAA.',
Sa='Sabornator:BAAANQAECgYIBgABNQAECgcIDwASAAAAAA==.Sabot:BAAANQAECgcIDwAAAA==.Samaximilan:BAAANQAECgUIBQAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgASAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECgoKLwAHAGgdAA==.',
Sh='Shamantics:BAAANQAECgEIAQABNQAFFAcIEgAdAMAkAA==.Shamerica:BAACNQAFFH8bAAIEAAcKDB8qBAC4AQAEAAcKDB8qBAC4AQA1AAQKf0kAAgQACgoaJT4FAFMDAAQACgoaJT4FAFMDAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAACNQAFFH8HAAIJAAUKKh9BEABSAQAJAAUKKh9BEABSAQA1AAQKfyIAAgkACgowIeQPAC4DAAkACgowIeQPAC4DAAAA.',
Sl='Slagothor:BAABNQAECn8aAAIIAAgKJAbYdQBBAQAIAAgKJAbYdQBBAQAAAA==.',
So='Soultax:BAAANQAECgcIDwAAAA==.',
Sp='Spekaleks:BAAANQAECgUIBQAAAA==.Spinfat:BAACNQAFFH8PAAIaAAcK7hdSBQBJAQAaAAcK7hdSBQBJAQA1AAQKfzYAAhoACgrGJfIAAHwDABoACgrGJfIAAHwDAAAA.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgcIEQAAAA==.Starbux:BAAANQAECgUIEwABNQAECgoKJQALANQOAA==.Starbúcks:BAAANQAECgEIAQABNQAECgoKJQALANQOAA==.Stockgodx:BAAANQAECgQICQAAAA==.',
Su='Sugarr:BAAANQAECgEIAQABNQAECgoKHwAGAC4XAA==.',
Sy='Syb:BAAANQAECgcIDwAAAA==.',
Ta='Taeyang:BAABNQAECn8wAAQNAAoKDiTsGgAaAwANAAkK0CPsGgAaAwAMAAEKgiSaIgBjAAAdAAEKFiG6JgBRAAAAAA==.Tankadin:BAAANQADCgcIBwABNQAECggIIgAGAOUVAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Telafar:BAAANQAECggIEAAAAA==.Terraform:BAAANQADCgEIAQAAAA==.',
Th='Thavus:BAAANQADCgMIAwAAAA==.Theinsider:BAABNQAECn8WAAINAAoKghXEcQALAgANAAoKghXEcQALAgABNQAECgoKLwAHAGgdAA==.Theoutsider:BAABNQAECn8vAAMHAAoKaB2IHACmAgAHAAkKJx2IHACmAgAIAAgKFRxEQwAOAgAAAA==.',
Ti='Timhair:BAAANQADCgYIHgAAAA==.Tindril:BAAANQADCgYIBgAAAA==.Tinkerstorm:BAAANQADCgUIBQABNQAFFAUIEAATAJcXAA==.',
To='Toekneess:BAABNQAECn8vAAILAAoKuiX3AwCwAwALAAoKuiX3AwCwAwAAAA==.Toekneez:BAAANQAECggIEgABNQAECgoKLwALALolAA==.Toekneezz:BAABNQAECn8nAAIcAAkKdSPBAwBzAwAcAAkKdSPBAwBzAwABNQAECgoKLwALALolAA==.Totemmalotes:BAAANQADCgMIAwAAAA==.Totemofbear:BAABNQAECn8qAAIiAAoKjRRzDQDVAQAiAAoKjRRzDQDVAQAAAA==.',
Tr='Trandis:BAABNQAECn8oAAMaAAoK8iL+CABBAwAaAAoK8iL+CABBAwAcAAEKEQZYQAAjAAAAAA==.Tranza:BAABNQAECn8iAAIGAAgK5RUhgAAMAgAGAAgK5RUhgAAMAgAAAA==.Trash:BAAANQAECgEIAQABNQAECgYIEgASAAAAAA==.',
Tx='Tx:BAACNQAFFH8RAAIEAAYKCxLCCADlAQAEAAYKCxLCCADlAQA1AAQKfyUAAgQACQpMH9oeABIDAAQACQpMH9oeABIDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Um='Umei:BAAANQADCgIIAgAAAA==.',
Un='Unheilige:BAAANQAECgMIAwAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgoKIwAIAFMXAA==.Utterchaos:BAABNQAECn8XAAIeAAUKSx0oKwCEAQAeAAUKSx0oKwCEAQABNQAECgcIJwAZALYRAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQAECgQIBAAAAA==.',
Wa='Wazupp:BAAANQAECggICAAAAA==.',
We='Wematanye:BAAANQADCgYIHAABNQAECgkJLQAhAIcPAA==.Wetheals:BAAANQAECgcIDQAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQASAAAAAA==.',
Wo='Worgnfreeman:BAABNQAECn8ZAAQJAAkKJgQDdwBxAAAJAAUKwAYDdwBxAAAHAAIKawKsvAAhAAAIAAgKQQHG+QAeAAAAAA==.',
Wt='Wtfmate:BAAANQAECgUIBgABNQAFFAcIEQALALMOAA==.Wtfmonk:BAABNQAECn8sAAIcAAoKfBc+EAB7AgAcAAoKfBc+EAB7AgABNQAFFAcIEQALALMOAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQAECgcIDwAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAASAAAAAA==.',
Xs='Xsaber:BAAANQAECgQIAwAAAA==.',
Ya='Yangyin:BAAANQAECggIDgAAAA==.Yazmo:BAACNQAFFH8cAAIbAAcKBCU9AgAPAgAbAAcKBCU9AgAPAgA1AAQKfzsAAhsACgoZJncFAIEDABsACgoZJncFAIEDAAAA.',
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
