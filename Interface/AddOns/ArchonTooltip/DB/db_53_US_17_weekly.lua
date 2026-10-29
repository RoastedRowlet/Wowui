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

local lookup = {'Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Paladin-Retribution','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Devourer','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Shaman-Restoration','Monk-Windwalker','Priest-Shadow','Monk-Mistweaver','Warlock-Affliction','Paladin-Protection','Evoker-Augmentation','Rogue-Subtlety','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECn8rAAQBAAoKwx6GNADvAgABAAoKwx6GNADvAgACAAEK2BrEPQBMAAADAAIK+ARJLwBDAAAAAA==.Adellon:BAABNQAECn8aAAIEAAkKzhtJNQCjAgAEAAkKzhtJNQCjAgAAAA==.Adhar:BAAANQAECgMIAwAAAA==.Adrielle:BAAANQAECgUIBwAAAA==.',
Ak='Akakage:BAABNQAECn8YAAIFAAgK/hxTKwA8AgAFAAgK/hxTKwA8AgAAAA==.Akakaji:BAAANQAECgYIBwABNQAECggIGAAFAP4cAA==.Akutoku:BAABNQAECn8eAAIGAAkKGhmbXwBYAgAGAAkKGhmbXwBYAgAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAABNQAECn8oAAQHAAkK7Q69JgCcAQAHAAkKpg69JgCcAQAIAAUKngp/kQDjAAAJAAIKUAMPwABIAAAAAA==.Anomander:BAAANQAECgUICAAAAA==.',
Ar='Ar:BAABNQAECn8iAAIKAAkKHhYmTwA3AgAKAAkKHhYmTwA3AgABNQAECgoKKwABAMMeAA==.Archon:BAABNQAECn8/AAMBAAkKyyOJCAAoAwABAAkKyyOJCAAoAwADAAEKJR1xLABSAAAAAA==.Arienca:BAABNQAECn8oAAMLAAkKnQ7HEwDSAQALAAkKnQ7HEwDSAQAMAAUKzAM7BAHDAAAAAA==.',
As='Aspir:BAEBNQAECn8eAAINAAkKDRkxPgACAgANAAkKDRkxPgACAgABNQAFFAUIEQAHAPMWAA==.',
At='At:BAAANQAECgYIBwABNQAECgoKKwABAMMeAA==.',
Au='Auddio:BAAANQAECggIAQAAAA==.',
Ba='Baidoogh:BAAANQAECgIIAwAAAA==.Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCggIDwAAAA==.Bepis:BAABNQAECn8jAAIOAAkK7SAHAwA/AwAOAAkK7SAHAwA/AwAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgYIDAAAAA==.',
Bl='Blazerunner:BAABNQAECn8zAAIPAAoKtw1FRgDgAQAPAAoKtw1FRgDgAQAAAA==.Blazesmasher:BAAANQAECgEIAQABNQAECgoKMwAPALcNAA==.Blitzkreig:BAAANQAECgUICQAAAA==.Blured:BAABNQAECn81AAIQAAoKmyP9AgCqAwAQAAoKmyP9AgCqAwAAAA==.',
Bo='Booty:BAABNQAECn8qAAICAAoKxh7uBQANAwACAAoKxh7uBQANAwAAAA==.Bort:BAABNQAECn8cAAIRAAkKZwfFGQCsAQARAAkKZwfFGQCsAQAAAA==.',
Br='Brevyn:BAABNQAECn8bAAIPAAkKiQgg5gC9AQAPAAkKiQgg5gC9AQAAAA==.',
Bu='Bubblebutt:BAAANQAECgQICAABNQAECggIDAASAAAAAA==.Bulla:BAAANQAECgcICAAAAA==.Bung:BAABNQAECn8jAAITAAkKXBd3QQBfAgATAAkKXBd3QQBfAgAAAA==.Buum:BAAANQAECgQIBwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECggIIQAUADYNAA==.',
Ca='Cali:BAACNQAFFH8WAAMVAAcKBgpMCQCYAQAVAAYKhAhMCQCYAQAQAAQKFQsFCwAbAQA1AAQKf0IAAxUACgohI6gGAPACABUACgp4IKgGAPACABAACgqqHo4UAMICAAAA.Calipari:BAAANQADCgQIBAABNQAFFAcIFgAVAAYKAA==.Carafe:BAAANQAECgUIBQABNQAECgYIEQASAAAAAA==.Catamara:BAAANQAECgIIBAAAAA==.',
Ce='Cephus:BAACNQAFFH8RAAIWAAUKKBM8BwCMAQAWAAUKKBM8BwCMAQA1AAQKfzIAAxYACgqLFd0jAAYCABYACgqLFd0jAAYCABcAAQrHF+1jAEcAAAAA.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFH8bAAIGAAcKLhS9BQD3AQAGAAcKLhS9BQD3AQA1AAQKfzoAAgYACgrWI+kEAD8DAAYACgrWI+kEAD8DAAAA.Chimeira:BAAANQAECgEIAQAAAA==.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFH8TAAMVAAUKRBxxBABKAQAVAAUKRBxxBABKAQAQAAEKxQpoFgBAAAA1AAQKfzAAAxAACgqPIacWAKsCABAACQoNHKcWAKsCABUABQpwImgwACIBAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECn80AAMYAAoKHRxPFgAeAwAYAAoKHRxPFgAeAwAEAAUK9A0GxAAKAQAAAA==.',
Cy='Cynestra:BAAANQAECgUICQAAAA==.Cyni:BAAANQAECgEIAQABNQAFFAUIBwATAJgQAA==.Cytheris:BAAANQADCgIIAgABNQAECgoKNAAYAB0cAA==.',
Da='Dadudadu:BAACNQAFFH8OAAINAAUK1wecDwBSAQANAAUK1wecDwBSAQA1AAQKf0MAAg0ACgorHUMgAIsCAA0ACgorHUMgAIsCAAAA.Daftmonk:BAACNQAFFH8TAAIZAAUKBx8kAwBIAQAZAAUKBx8kAwBIAQA1AAQKf0gAAhkACgqMJVYCALkDABkACgqMJVYCALkDAAAA.Darj:BAABNQAECn8hAAIBAAoKoxMiYwBlAgABAAoKoxMiYwBlAgAAAA==.Darmonevil:BAAANQAECgUIDQAAAA==.Dasarus:BAAANQAECgcIDAAAAA==.Dauntless:BAAANQAECgcICgAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgYICgASAAAAAA==.Dethblades:BAAANQAECgEIAQABNQAECgYICgASAAAAAA==.Dethblow:BAAANQAECgYICgAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgYICgASAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECn8zAAMYAAkK+AgZfQCUAQAYAAkK+AgZfQCUAQAEAAcK0AIQxAAKAQAAAA==.',
Dk='Dklot:BAABNQAECn8xAAMIAAoK3BrXEQAGAgAIAAoK3BrXEQAGAgAJAAMKFg42UgCgAAAAAA==.',
Do='Doomkin:BAAANQAECgUIBgAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECn83AAIGAAoKvxwrNwDFAgAGAAoKvxwrNwDFAgAAAA==.Dreadgrave:BAABNQAECn8jAAIIAAoKUxd4IQBoAQAIAAoKUxd4IQBoAQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAFFAUIBwATAJgQAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
Eg='Egoh:BAAANQAECgYIBgABNQAFFAYIGwAaAPEkAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.Eleshkigal:BAAANQAECgQIAwABNQAECgoKJwAZAPIiAA==.',
En='Enkeke:BAABNQAECn82AAIIAAoK5BklLgB5AgAIAAoK5BklLgB5AgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgASAAAAAA==.Eresanna:BAABNQAECn8ZAAIPAAgKiA9M0wDgAQAPAAgKiA9M0wDgAQAAAA==.Erf:BAABNQAECn8oAAIbAAoK8Q4XGwDQAQAbAAoK8Q4XGwDQAQAAAA==.Erinis:BAAANQAECgQIBQABNQAECgkJJwAVAMUcAA==.',
Es='Esdeath:BAAANQAECgcIDAABNQAECgkJJwAVAMUcAA==.',
Ex='Extremefear:BAABNQAECn8bAAMMAAgKEg9c1gAdAQAMAAYKuQxc1gAdAQALAAIKxBPJVgB6AAAAAA==.',
Fe='Fearious:BAACNQAFFH8RAAQcAAYKPiXnBQB1AAAMAAQKbSUhGwAeAQAcAAEKAADnBQB1AAALAAEKsiSNFABmAAA1AAQKfyIABAwACgrZJS0rAAQCAAwABwq5JS0rAAQCAAsAAgryI3cVAHEAABwAAgocJiQSAHAAAAAA.Feroond:BAABNQAECn8fAAMJAAoKTR4oDACEAgAJAAoK8h0oDACEAgAHAAUKpRMQagD3AAAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fr='Frogteeth:BAABNQAECn8UAAIEAAYKfRO1mgBiAQAEAAYKfRO1mgBiAQAAAA==.Frozath:BAAANQAECgMIBQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgASAAAAAA==.Fussypants:BAABNQAECn8XAAIdAAcKoAjEPwD7AAAdAAcKoAjEPwD7AAAAAA==.',
Ga='Gallindral:BAABNQAECn8tAAIQAAoKNBhIGwB9AgAQAAoKNBhIGwB9AgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAABNQAECn8WAAICAAcK5Q42IwAvAQACAAcK5Q42IwAvAQAAAA==.Geobrando:BAABNQAECn8xAAMYAAoKrxk6PQBrAgAYAAoKrxk6PQBrAgAEAAUK/xR/swArAQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQAECgUICQAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQASAAAAAA==.',
Gr='Grippindeez:BAABNQAECn8kAAMHAAkKvQ4OTgB+AQAHAAkK+wsOTgB+AQAJAAIKNBxKtgBbAAAAAA==.Grêêd:BAAANQADCgQICAAAAA==.',
Gu='Guidosarduci:BAABNQAECn8nAAMYAAcKthElfgCSAQAYAAcKthElfgCSAQAEAAIKrwNHHQFVAAAAAA==.Guiseppe:BAABNQAECn8bAAMRAAcK6Q9oGwCUAQARAAcKKA9oGwCUAQAeAAMKQA6yHACAAAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQAECgQICQAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECn9YAAIBAAkK6hcgTgCfAgABAAkK6hcgTgCfAgAAAA==.',
Ho='Holyshortguy:BAACNQAFFH8QAAIKAAYKyAxhDQBVAQAKAAYKyAxhDQBVAQA1AAQKfx8AAwoACgqDGuIpAMECAAoACgqDGuIpAMECABoAAQoAAHOBACkAAAAA.',
Hu='Hustlermag:BAABNQAECn86AAQLAAkKghe5CwDCAAAMAAkKxhReTAB/AQAcAAQKBxRDFAAGAQALAAUK5xm5CwDCAAAAAA==.Huñter:BAAANQABCgIIAgABNQAECggIDAASAAAAAA==.',
Hy='Hyperion:BAAANQAECgEIAgABNQAECgYIBQASAAAAAA==.',
Ic='Icelmo:BAACNQAFFH8IAAIBAAIKKwmBHQB9AAABAAIKKwmBHQB9AAA1AAQKfy4AAgEACgpyHNdRAJQCAAEACgpyHNdRAJQCAAAA.',
Im='Impact:BAAANQADCgIJAgABNQAFFAYIEQAEAAsSAA==.',
In='Infinit:BAAANQAECggIDQAAAA==.',
Is='Isuck:BAAANQAECgQIBwAAAA==.',
Ja='Jaskow:BAABNQAECn8hAAIWAAkK5BqIFAClAgAWAAkK5BqIFAClAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Ju='Jusdatip:BAABNQAECn8cAAIfAAcKPQ51IQDBAQAfAAcKPQ51IQDBAQABNQAECgcIJwAYALYRAA==.',
Ka='Kalessandra:BAABNQAECn8aAAIPAAkKVQpIZwB6AQAPAAkKVQpIZwB6AQAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgQICAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.Kimlin:BAAANQADCgMIAwAAAA==.',
Kr='Krag:BAAANQAECgQIBAABNQAECgoKKwAgAMIkAA==.Krasis:BAABNQAECn8eAAINAAoKNCFXEAD0AgANAAoKNCFXEAD0AgAAAA==.Krazermonk:BAABNQAECn8tAAIZAAoK1RozFQCrAgAZAAoK1RozFQCrAgAAAA==.Kristysavage:BAABNQAECn9DAAIGAAoKCSUMBQC8AwAGAAoKCSUMBQC8AwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgYIDQABNQAFFAcIHQAWADwbAA==.',
Li='Lichdawg:BAACNQAFFH8RAAIHAAYKWhSLBADSAQAHAAYKWhSLBADSAQA1AAQKfzMAAgcACgr4IuIJAMoCAAcACgr4IuIJAMoCAAAA.Lilthorn:BAAANQADCggICQAAAA==.Lithlia:BAAANQADCgMIAQAAAA==.',
Lo='Lofometa:BAAANQADCggICgAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAYIEAAKAMgMAA==.',
Lu='Lubu:BAABNQAECn8nAAIVAAkKxRysIwB+AgAVAAkKxRysIwB+AgAAAA==.Luell:BAAANQAECgIIAgAAAA==.Lumen:BAAANQAECgYICwAAAA==.Lumiette:BAABNQAECn8fAAICAAkKyBBqFwC1AQACAAkKyBBqFwC1AQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgASAAAAAA==.',
Ly='Lynai:BAABNQAECn8fAAIUAAgK/A4WEgCEAQAUAAgK/A4WEgCEAQAAAA==.',
['Lá']='Lándwhale:BAABNQAECn9BAAMfAAoK8SU3AQC/AwAfAAoKziU3AQC/AwAFAAUKyx8iIgD1AAAAAA==.',
['Læ']='Lægolas:BAAANQAECgMIBQAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQASAAAAAA==.',
Ma='Macktimus:BAABNQAECn8cAAILAAkKQRpgCAB4AgALAAkKQRpgCAB4AgAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECgoKKwAgAMIkAA==.Makili:BAABNQAECn9LAAMPAAkK5SEgOwARAwAPAAkK5SEgOwARAwAUAAEKeAxXUAAnAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAAANQAECgYIEQAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgYIFAAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.Mornedelth:BAAANQAECgUIBQABNQAECgYIEQASAAAAAA==.',
Mu='Murad:BAAANQAECggIDwAAAA==.',
My='Mylodon:BAAANQABCgQIBgAAAA==.Mysternia:BAAANQAECgUICQAAAA==.',
Ni='Niade:BAACNQAFFH8HAAITAAUKmBDlEQBDAQATAAUKmBDlEQBDAQA1AAQKfygAAxMACgoDH7kgAOsCABMACgoDH7kgAOsCAA0ABQpiCIMoAd0AAAAA.Nitpo:BAAANQADCgYIBgAAAA==.',
No='Notorckrag:BAABNQAECn8rAAIgAAoKwiR1AQCzAwAgAAoKwiR1AQCzAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQAFFAIIAgABNQAFFAYIGwAaAPEkAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Ob='Obtutas:BAAANQADCggICAABNQAECgQIBAASAAAAAA==.',
Od='Odimeer:BAAANQAECgYICgAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAABNQAECn8XAAIdAAYKbRfXGwAeAQAdAAYKbRfXGwAeAQABNQAECgkJJwAVAMUcAA==.',
Ol='Oldrecipe:BAABNQAECn8qAAITAAoKGhcjHwBMAgATAAoKGhcjHwBMAgAAAA==.Oliange:BAABNQAECn8hAAMUAAgKNg0mFABnAQAUAAgKNg0mFABnAQAPAAYKEAWJRgEYAQAAAA==.',
Oo='Oopsrofl:BAAANQAECggIEgAAAA==.',
Op='Optimuze:BAAANQAFFAEIAQAAAA==.',
Or='Originalgank:BAACNQAFFH8IAAMPAAQKBxGZOADjAAAPAAQKpAuZOADjAAAUAAEKUxdpDABOAAA1AAQKfy8AAw8ACgqcIBIxACkDAA8ACgqcIBIxACkDABQAAQpCHackAFcAAAAA.Orthox:BAAANQADCgUIBQAAAA==.',
Ot='Otoha:BAAANQADCgYIBgAAAA==.',
Pe='Peachcobbler:BAABNQAECn8fAAIaAAoKxAe+MQCVAQAaAAoKxAe+MQCVAQAAAA==.Peachcrumpet:BAAANQADCgEIAQAAAA==.Peppermint:BAAANQAECgUIEQAAAA==.Pewpsmadness:BAAANQAECgQIBAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAABNQAECn8WAAIGAAkKLhfxNgAEAgAGAAkKLhfxNgAEAgAAAA==.',
Pl='Plaguerism:BAABNQAECn8jAAMIAAoKtiDvDABSAwAIAAoKTSDvDABSAwAJAAMKghg5jwDHAAABNQAFFAYIEQAcAD4lAA==.',
Po='Poo:BAACNQAFFH8OAAMFAAUKMRWhBgCyAQAFAAUKMRWhBgCyAQAfAAIKvghSGwA/AAA1AAQKfzoAAwUACgpMIhMJAEgDAAUACgp9IRMJAEgDAB8ACgqTF0gVAHYCAAAA.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgASAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
Pu='Puck:BAAANQAECgUIAwABNQAECgkJJwAVAMUcAA==.',
['Pâ']='Pâiñ:BAAANQADCggIIwAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAABNQAECn8lAAMXAAoKaiBGHADmAgAXAAoKaiBGHADmAgAWAAQK3g3gTwDKAAAAAA==.Rahor:BAABNQAECn8jAAQNAAgKhxFwtwCvAQANAAgKeRFwtwCvAQAdAAIKLB1rUwCWAAATAAIKxwajtgBNAAABNQAECgkJOgALAIIXAA==.Rainesage:BAABNQAECn8cAAIaAAgKERn0JQD/AQAaAAgKERn0JQD/AQAAAA==.Ralphel:BAABNQAECn8VAAINAAYK7ANzKQHbAAANAAYK7ANzKQHbAAAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQAECgYIBgAAAA==.',
Rh='Rhubarb:BAABNQAECn8pAAIBAAoKUCTOEwBsAwABAAoKUCTOEwBsAwAAAA==.',
Ri='Riptidepods:BAAANQAECgUIBAAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ru='Rugob:BAAANQADCggICAAAAA==.Rukawa:BAAANQADCgcICAAAAA==.',
Ry='Rylosh:BAACNQAFFH8eAAIWAAYK6gkWBQBZAQAWAAYK6gkWBQBZAQA1AAQKf0EAAhYACgqwGQUKAKECABYACgqwGQUKAKECAAAA.',
Sa='Sabornator:BAAANQAECgYIBQAAAA==.Sabot:BAAANQAECgUICQABNQAECgYIBQASAAAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgASAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECgoKLwAHAGgdAA==.',
Sh='Shamantics:BAAANQAECgEIAQABNQAFFAYIEQAcAD4lAA==.Shamerica:BAACNQAFFH8WAAIEAAcKdxzMAgCXAQAEAAcKdxzMAgCXAQA1AAQKf0EAAgQACgr3JDsHAK8DAAQACgr3JDsHAK8DAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAACNQAFFH8HAAIJAAUKKh9BEABSAQAJAAUKKh9BEABSAQA1AAQKfyIAAgkACgowIeQPAC4DAAkACgowIeQPAC4DAAAA.',
Sl='Slagothor:BAABNQAECn8aAAIIAAgKJAbYdQBBAQAIAAgKJAbYdQBBAQAAAA==.',
So='Soultax:BAAANQAECgUICQAAAA==.',
Sp='Spekaleks:BAAANQAECgMIAwAAAA==.Spinfat:BAACNQAFFH8OAAIZAAYKLxb6BgCOAQAZAAYKLxb6BgCOAQA1AAQKfysAAhkACgr7Is0KACcDABkACgr7Is0KACcDAAAA.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgYIEQAAAA==.Starbux:BAAANQAECgUIBwABNQAECgkJHQAKAK4NAA==.Starbúcks:BAAANQAECgEIAQABNQAECgkJHQAKAK4NAA==.Stockgodx:BAAANQAECgQIBQAAAA==.',
Su='Sugarr:BAAANQAECgEIAQABNQAECgkJFgAGAC4XAA==.',
Sy='Syb:BAAANQAECgUICQAAAA==.',
Ta='Taeyang:BAABNQAECn8uAAQMAAoKDiTsGgAaAwAMAAkK0CPsGgAaAwALAAEKgiQbGABoAAAcAAEKFiG6JgBRAAAAAA==.Tankadin:BAAANQADCgcIBwABNQAECgcIIQAGAFgYAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Telafar:BAAANQAECggIEAAAAA==.Terraform:BAAANQADCgEIAQAAAA==.',
Th='Theinsider:BAABNQAECn8WAAIMAAoKghXEcQALAgAMAAoKghXEcQALAgABNQAECgoKLwAHAGgdAA==.Theoutsider:BAABNQAECn8vAAMHAAoKaB2IHACmAgAHAAkKJx2IHACmAgAIAAgKFRxEQwAOAgAAAA==.',
Ti='Timhair:BAAANQADCgYIFAAAAA==.Tindril:BAAANQADCgYIBgAAAA==.',
To='Toekneess:BAABNQAECn8oAAIKAAoKdyX3AwCwAwAKAAoKdyX3AwCwAwAAAA==.Toekneez:BAAANQAECgcIEgABNQAECgoKKAAKAHclAA==.Toekneezz:BAABNQAECn8nAAIbAAkKdSPBAwBzAwAbAAkKdSPBAwBzAwABNQAECgoKKAAKAHclAA==.Totemmalotes:BAAANQADCgMIAwAAAA==.Totemofbear:BAABNQAECn8jAAIhAAkKCxM1DABvAQAhAAkKCxM1DABvAQAAAA==.',
Tr='Trandis:BAABNQAECn8nAAIZAAoK8iL+CABBAwAZAAoK8iL+CABBAwAAAA==.Tranza:BAABNQAECn8hAAIGAAcKWBghgAAMAgAGAAcKWBghgAAMAgAAAA==.Trash:BAAANQAECgEIAQABNQAECgQIBwASAAAAAA==.',
Tx='Tx:BAACNQAFFH8RAAIEAAYKCxLCCADlAQAEAAYKCxLCCADlAQA1AAQKfyUAAgQACQpMH9oeABIDAAQACQpMH9oeABIDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Um='Umei:BAAANQADCgIIAgAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgoKIwAIAFMXAA==.Utterchaos:BAABNQAECn8XAAIdAAUKSx0oKwCEAQAdAAUKSx0oKwCEAQABNQAECgcIJwAYALYRAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQAECgQIBAAAAA==.',
Wa='Wazupp:BAAANQAECggICAAAAA==.',
We='Wematanye:BAAANQADCgYIFwABNQAECgcIJQAgAG0RAA==.Wetheals:BAAANQAECgcIDQAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQASAAAAAA==.',
Wo='Worgnfreeman:BAABNQAECn8WAAQJAAkK3APMYABxAAAJAAUKFQbMYABxAAAHAAIKawKsvAAhAAAIAAgKQQHG+QAeAAAAAA==.',
Wt='Wtfmate:BAAANQADCgEIAQABNQAFFAYIEAAKAMgMAA==.Wtfmonk:BAABNQAECn8oAAIbAAoK0hY+EAB7AgAbAAoK0hY+EAB7AgABNQAFFAYIEAAKAMgMAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQAECgUICQAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAASAAAAAA==.',
Xs='Xsaber:BAAANQAECgEIAQAAAA==.',
Ya='Yangyin:BAAANQAECggICQAAAA==.Yazmo:BAACNQAFFH8bAAIaAAYK8ST4AQC5AQAaAAYK8ST4AQC5AQA1AAQKfzAAAhoACgo2JXcFAIEDABoACgo2JXcFAIEDAAAA.',
Yu='Yushe:BAAANQAECgIIAgAAAA==.Yuuky:BAABNQAECn83AAIWAAoK7xtUEQDJAgAWAAoK7xtUEQDJAgAAAA==.',
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
