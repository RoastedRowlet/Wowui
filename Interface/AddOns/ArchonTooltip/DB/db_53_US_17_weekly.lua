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

local lookup = {'Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Paladin-Retribution','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Devourer','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Restoration','Monk-Windwalker','Priest-Shadow','Monk-Mistweaver','Warlock-Affliction','Paladin-Protection','Evoker-Augmentation','Rogue-Subtlety','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECn8rAAQBAAoKwx6GNADvAgABAAoKwx6GNADvAgACAAEK2BrEPQBMAAADAAIK+ARJLwBDAAAAAA==.Adellon:BAABNQAECn8aAAIEAAkKzhtJNQCjAgAEAAkKzhtJNQCjAgAAAA==.Adhar:BAAANQAECgMIBQAAAA==.Adrielle:BAAANQAECgYIBwAAAA==.',
Ak='Akakage:BAABNQAECn8YAAIFAAgK/hxTKwA8AgAFAAgK/hxTKwA8AgAAAA==.Akakaji:BAAANQAECgYIBwABNQAECggIGAAFAP4cAA==.Akutoku:BAABNQAECn8iAAIGAAoKfBebXwBYAgAGAAoKfBebXwBYAgAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAABNQAECn8vAAQHAAkKShA/MgChAQAHAAkKShA/MgChAQAIAAUKngp/kQDjAAAJAAIKUAMPwABIAAAAAA==.Anomander:BAAANQAECggIDgAAAA==.',
Ar='Ar:BAABNQAECn8jAAIKAAkKNBYmTwA3AgAKAAkKNBYmTwA3AgABNQAECgoKKwABAMMeAA==.Archon:BAABNQAECn9GAAMBAAkKhCTrCgAsAwABAAkKhCTrCgAsAwADAAEKJR1xLABSAAAAAA==.Arienca:BAABNQAECn8oAAMLAAkKnQ7HEwDSAQALAAkKnQ7HEwDSAQAMAAUKzAM7BAHDAAAAAA==.',
As='Aspir:BAEBNQAECn8gAAINAAkKDRkhXgDeAQANAAkKDRkhXgDeAQABNQAFFAUIEQAHAPMWAA==.',
At='At:BAAANQAECgYIBwABNQAECgoKKwABAMMeAA==.',
Au='Auddio:BAAANQAECggIAQAAAA==.',
Ba='Baidoogh:BAAANQAECgIIAwAAAA==.Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCggIDwAAAA==.Bepis:BAABNQAECn8jAAIOAAkK7SAHAwA/AwAOAAkK7SAHAwA/AwAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgYIDAAAAA==.',
Bl='Blazerunner:BAABNQAECn88AAIPAAoK1w5cWQDfAQAPAAoK1w5cWQDfAQAAAA==.Blazesmasher:BAAANQAECgMIAQABNQAECgoKPAAPANcOAA==.Blitzkreig:BAAANQAECgYICgAAAA==.Blured:BAABNQAECn81AAIQAAoKmyP9AgCqAwAQAAoKmyP9AgCqAwAAAA==.',
Bo='Booty:BAABNQAECn8qAAICAAoKxh7uBQANAwACAAoKxh7uBQANAwAAAA==.Bort:BAABNQAECn8cAAIRAAkKZwfFGQCsAQARAAkKZwfFGQCsAQAAAA==.',
Br='Brevyn:BAABNQAECn8bAAIPAAkKiQgg5gC9AQAPAAkKiQgg5gC9AQAAAA==.Brightblayde:BAAANQAECgIIAgAAAA==.',
Bu='Bubblebutt:BAAANQAECgQICAABNQAECggIDAASAAAAAA==.Bulla:BAAANQAECgcICAAAAA==.Bung:BAABNQAECn8jAAITAAkKXBd3QQBfAgATAAkKXBd3QQBfAgAAAA==.Buum:BAAANQAECgQIBwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECggIIQAUADYNAA==.',
Ca='Cali:BAACNQAFFH8WAAMVAAcKBgpMCQCYAQAVAAYKhAhMCQCYAQAQAAQKFQsFCwAbAQA1AAQKf0kAAxUACgq/JBQDAFADABUACgq/JBQDAFADABAACgqqHo4UAMICAAAA.Calipari:BAAANQADCgQIBAABNQAFFAcIFgAVAAYKAA==.Carafe:BAAANQAECgUIBQABNQAECgcIFgAWAKkZAA==.Catamara:BAAANQAECgIIBAAAAA==.',
Ce='Cephus:BAACNQAFFH8WAAIXAAYKrBCQBQCCAQAXAAYKrBCQBQCCAQA1AAQKfzYAAxcACgqLFd0jAAYCABcACgqLFd0jAAYCABgAAQrHF85zAEIAAAAA.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFH8bAAIGAAcKLhS9BQD3AQAGAAcKLhS9BQD3AQA1AAQKfz0AAgYACgrYJBcHAEEDAAYACgrYJBcHAEEDAAAA.Chimeira:BAAANQAECgEIAQAAAA==.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFH8UAAMVAAYKshhwBACYAQAVAAYKshhwBACYAQAQAAEKxQpoFgBAAAA1AAQKfzEAAxAACgrvIacWAKsCABAACQoNHKcWAKsCABUABQoII7s5AB0BAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECn80AAMZAAoKHRxPFgAeAwAZAAoKHRxPFgAeAwAEAAUK9A0GxAAKAQAAAA==.',
Cr='Critlee:BAAANQADCgMIAwAAAA==.',
Cy='Cyclondike:BAAANQAECgQIBAAAAA==.Cynestra:BAAANQAECgUICQAAAA==.Cyni:BAAANQAECgEIAQABNQAFFAUIBwATAJgQAA==.Cytheris:BAAANQADCgIIAgABNQAECgoKNAAZAB0cAA==.',
Da='Dadudadu:BAACNQAFFH8OAAINAAUK1wecDwBSAQANAAUK1wecDwBSAQA1AAQKf0MAAg0ACgorHTwzAGoCAA0ACgorHTwzAGoCAAAA.Daftmonk:BAACNQAFFH8UAAIaAAYKcR0AAwCSAQAaAAYKcR0AAwCSAQA1AAQKf1AAAhoACgrZJVYCALkDABoACgrZJVYCALkDAAAA.Darj:BAABNQAECn8hAAIBAAoKoxMiYwBlAgABAAoKoxMiYwBlAgAAAA==.Darmonevil:BAAANQAECgUIDQAAAA==.Dasarus:BAAANQAECgYIDAAAAA==.Dauntless:BAAANQAECgUICwAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgYIDwASAAAAAA==.Dethblades:BAAANQAECgEIAQABNQAECgYIDwASAAAAAA==.Dethblow:BAAANQAECgYIDwAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgYIDwASAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECn89AAMZAAoK5QnfVACNAQAZAAoK5QnfVACNAQAEAAcK0AIQxAAKAQAAAA==.',
Dk='Dklot:BAABNQAECn87AAMIAAoKJx+5CADOAgAIAAoKJx+5CADOAgAJAAUKSQ5mRAADAQAAAA==.',
Do='Doomkin:BAAANQAECgUIBgAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECn87AAIGAAoKvxwrNwDFAgAGAAoKvxwrNwDFAgAAAA==.Dreadgrave:BAABNQAECn8jAAIIAAoKUxfMKgBcAQAIAAoKUxfMKgBcAQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAFFAUIBwATAJgQAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
Eg='Egoh:BAAANQAECgcIDQABNQAFFAcIHAAbAAQlAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.Eleshkigal:BAAANQAECgQIBQABNQAECgoKKAAaAPIiAA==.',
En='Enkeke:BAABNQAECn82AAIIAAoK5BklLgB5AgAIAAoK5BklLgB5AgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgASAAAAAA==.Eresanna:BAABNQAECn8ZAAIPAAgKiA9M0wDgAQAPAAgKiA9M0wDgAQAAAA==.Erf:BAABNQAECn8oAAIcAAoK8Q4XGwDQAQAcAAoK8Q4XGwDQAQAAAA==.Erinis:BAAANQAECgcICwABNQAECgkJLQAVAKcdAA==.',
Es='Esdeath:BAAANQAECggIDQABNQAECgkJLQAVAKcdAA==.',
Ex='Extremefear:BAABNQAECn8cAAMMAAkKjA5c1gAdAQAMAAcKdQxc1gAdAQALAAIKxBPJVgB6AAAAAA==.',
Fe='Fearious:BAACNQAFFH8SAAQdAAcKwCTnBQB1AAAMAAUKwySgFADWAAAdAAEKAADnBQB1AAALAAEKsiSNFABmAAA1AAQKfycABAwACgrZJbM4AP4BAAwABwq5JbM4AP4BAB0AAgocJjogAHUAAAsAAgryI5wbAG8AAAAA.Feroond:BAABNQAECn8iAAMJAAoK8B4hEAB+AgAJAAoKlR4hEAB+AgAHAAUKpRMQagD3AAAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fo='Forfoxsake:BAAANQAECgQIBAAAAA==.',
Fr='Freyja:BAAANQAECgIIAQABNQAECgYICgASAAAAAA==.Frogteeth:BAABNQAECn8UAAIEAAYKfRO1mgBiAQAEAAYKfRO1mgBiAQAAAA==.Frozath:BAAANQAECgUICQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgASAAAAAA==.Fussypants:BAABNQAECn8YAAIeAAgKmgjEPwD7AAAeAAgKmgjEPwD7AAAAAA==.',
Ga='Gallindral:BAABNQAECn8tAAIQAAoKNBhIGwB9AgAQAAoKNBhIGwB9AgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAABNQAECn8WAAICAAcK5Q42IwAvAQACAAcK5Q42IwAvAQAAAA==.Geobrando:BAABNQAECn8xAAMZAAoKrxk6PQBrAgAZAAoKrxk6PQBrAgAEAAUK/xR/swArAQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQAECgUICQAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQASAAAAAA==.',
Gr='Grippindeez:BAABNQAECn8tAAMHAAkKmg9wOgB3AQAHAAkK1wxwOgB3AQAJAAIKNBxKtgBbAAAAAA==.Grêêd:BAAANQADCgQICAAAAA==.',
Gu='Guidosarduci:BAABNQAECn8nAAMZAAcKthElfgCSAQAZAAcKthElfgCSAQAEAAIKrwNHHQFVAAAAAA==.Guiseppe:BAABNQAECn8bAAMRAAcK6Q9oGwCUAQARAAcKKA9oGwCUAQAfAAMKQA6yHACAAAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQAECgQICQAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECn9aAAIBAAkK6hcgTgCfAgABAAkK6hcgTgCfAgAAAA==.',
Ho='Holyshortguy:BAACNQAFFH8RAAIKAAcKsw44CwCvAQAKAAcKsw44CwCvAQA1AAQKfyMAAwoACgqDGuIpAMECAAoACgqDGuIpAMECABsAAQoAAHOBACkAAAAA.',
Hu='Hustlermag:BAABNQAECn9BAAQMAAoK3BjnRQDOAQAMAAoK0RXnRQDOAQAdAAQKnhZDFAAGAQALAAUK5xk/DwDCAAAAAA==.Huñter:BAAANQABCgIIAgABNQAECggIDAASAAAAAA==.',
Hy='Hyperion:BAAANQAECgEIAgABNQAECgcIBQASAAAAAA==.',
Ic='Icelmo:BAACNQAFFH8JAAIBAAMK+RAbFQDaAAABAAMK+RAbFQDaAAA1AAQKfy8AAgEACgpyHNdRAJQCAAEACgpyHNdRAJQCAAAA.',
Im='Impact:BAAANQADCgIJAgABNQAFFAYIEQAEAAsSAA==.',
In='Infinit:BAABNQAECn8VAAINAAkKUhm1PABFAgANAAkKUhm1PABFAgAAAA==.',
Is='Isuck:BAAANQAECgUIDAAAAA==.',
Ja='Jaskow:BAABNQAECn8hAAIXAAkK5BqIFAClAgAXAAkK5BqIFAClAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Jo='Jobewright:BAAANQADCgMIAwAAAA==.',
Ju='Jusdatip:BAABNQAECn8cAAIgAAcKPQ51IQDBAQAgAAcKPQ51IQDBAQABNQAECgcIJwAZALYRAA==.',
Ka='Kalessandra:BAABNQAECn8gAAIPAAkKeQ+3aACzAQAPAAkKeQ+3aACzAQAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgQICAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.Kimlin:BAAANQADCgMIAwAAAA==.',
Kr='Krag:BAAANQAECgQIBAABNQAECgoKKwAhAMIkAA==.Krasis:BAABNQAECn8kAAINAAoKUyItFwDtAgANAAoKUyItFwDtAgAAAA==.Krazermonk:BAABNQAECn84AAIaAAoKWBzlDABkAgAaAAoKWBzlDABkAgAAAA==.Kristysavage:BAABNQAECn9KAAIGAAoKDCUMBQC8AwAGAAoKDCUMBQC8AwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgYIDQABNQAFFAcIHgAXADwbAA==.',
Li='Lichdawg:BAACNQAFFH8RAAIHAAYKWhSLBADSAQAHAAYKWhSLBADSAQA1AAQKfzoAAgcACgoGJLMMANQCAAcACgoGJLMMANQCAAAA.Lilthorn:BAAANQADCggICQAAAA==.Lithlia:BAAANQADCgQIBQAAAA==.',
Lo='Lofometa:BAAANQADCggICgAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAcIEQAKALMOAA==.',
Lu='Lubu:BAABNQAECn8tAAIVAAkKpx2sIwB+AgAVAAkKpx2sIwB+AgAAAA==.Luell:BAAANQAECgIIAgAAAA==.Lumen:BAAANQAECgYICwAAAA==.Lumiette:BAABNQAECn8fAAICAAkKyBBqFwC1AQACAAkKyBBqFwC1AQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgASAAAAAA==.',
Ly='Lynai:BAABNQAECn8fAAIUAAgK/A4WEgCEAQAUAAgK/A4WEgCEAQAAAA==.',
['Lá']='Lándwhale:BAABNQAECn9BAAMgAAoK8SU3AQC/AwAgAAoKziU3AQC/AwAFAAUKyx+LJgDsAAAAAA==.',
['Læ']='Lægolas:BAAANQAECgQICQAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQASAAAAAA==.',
Ma='Macktimus:BAABNQAECn8cAAILAAkKQRpgCAB4AgALAAkKQRpgCAB4AgAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECgoKKwAhAMIkAA==.Makili:BAABNQAECn9LAAMPAAkK5SEgOwARAwAPAAkK5SEgOwARAwAUAAEKeAxXUAAnAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAABNQAECn8WAAIWAAcKqRk8JwAUAQAWAAcKqRk8JwAUAQAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgYIFAAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.Mornedelth:BAAANQAECgUIBQABNQAECgcIFgAWAKkZAA==.',
Mu='Murad:BAAANQAECggIEAAAAA==.',
My='Mylodon:BAAANQABCgQIBgAAAA==.Mysternia:BAAANQAECgUICQAAAA==.',
Ni='Niade:BAACNQAFFH8HAAITAAUKmBDlEQBDAQATAAUKmBDlEQBDAQA1AAQKfygAAxMACgoDH7kgAOsCABMACgoDH7kgAOsCAA0ABQpiCIMoAd0AAAAA.Nitpo:BAAANQADCgYIBgAAAA==.',
No='Notorckrag:BAABNQAECn8rAAIhAAoKwiR1AQCzAwAhAAoKwiR1AQCzAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQAFFAIIAgABNQAFFAcIHAAbAAQlAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Ob='Obtutas:BAAANQADCggICAABNQAECgUICAASAAAAAA==.',
Od='Odimeer:BAAANQAECggIDAAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAABNQAECn8YAAIeAAcKrRV8HgBFAQAeAAcKrRV8HgBFAQABNQAECgkJLQAVAKcdAA==.',
Ol='Oldrecipe:BAABNQAECn8rAAITAAoKGhchLgA5AgATAAoKGhchLgA5AgAAAA==.Oliange:BAABNQAECn8hAAMUAAgKNg0mFABnAQAUAAgKNg0mFABnAQAPAAYKEAWJRgEYAQAAAA==.',
Oo='Oopsrofl:BAABNQAECn8eAAITAAoKfR44CgBfAwATAAoKfR44CgBfAwAAAA==.',
Op='Optimuze:BAAANQAFFAEIAQAAAA==.',
Or='Originalgank:BAACNQAFFH8JAAMPAAQKBxGZOADjAAAPAAQKpAuZOADjAAAUAAEKUxdPEABMAAA1AAQKfzMAAw8ACgqcIBIxACkDAA8ACgqcIBIxACkDABQAAQpCHScuAFMAAAAA.Orthox:BAAANQADCgUIBQAAAA==.',
Ot='Otoha:BAAANQADCgYIBwAAAA==.',
Pe='Peachcobbler:BAABNQAECn8jAAIbAAoKjwi+MQCVAQAbAAoKjwi+MQCVAQAAAA==.Peachcrumpet:BAAANQADCgEIAQAAAA==.Peppermint:BAABNQAECn8ZAAIKAAcKnxtWRADvAQAKAAcKnxtWRADvAQAAAA==.Pewpsmadness:BAAANQAECgQIBAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAABNQAECn8fAAIGAAoKLhdELwBXAgAGAAoKLhdELwBXAgAAAA==.',
Pl='Plaguerism:BAABNQAECn8kAAMIAAoKtiDvDABSAwAIAAoKTSDvDABSAwAJAAMKghg5jwDHAAABNQAFFAcIEgAdAMAkAA==.',
Po='Poo:BAACNQAFFH8SAAMFAAUKMRWhBgCyAQAFAAUKMRWhBgCyAQAgAAQKnwbSEgDIAAA1AAQKf0MAAwUACgpMIhMJAEgDAAUACgp9IRMJAEgDACAACgp2HRoRANICAAAA.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgASAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
Pu='Puck:BAAANQAECgQIBQABNQAECgkJLQAVAKcdAA==.',
['Pâ']='Pâiñ:BAAANQAECgQIBAAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAABNQAECn8pAAMYAAoKLiFGHADmAgAYAAoKLiFGHADmAgAXAAQK3g3gTwDKAAAAAA==.Rahor:BAABNQAECn8jAAQNAAgKhxFwtwCvAQANAAgKeRFwtwCvAQAeAAIKLB1rUwCWAAATAAIKxwae0QBIAAABNQAECgoKQQAMANwYAA==.Rainesage:BAABNQAECn8dAAIbAAkKoRj0JQD/AQAbAAkKoRj0JQD/AQAAAA==.Ralphel:BAABNQAECn8VAAINAAYK7ANzKQHbAAANAAYK7ANzKQHbAAAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQAECgYIBgAAAA==.',
Rh='Rhubarb:BAABNQAECn8tAAIBAAoKUCTOEwBsAwABAAoKUCTOEwBsAwAAAA==.',
Ri='Riptidepods:BAAANQAECgQIBAAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ru='Rugob:BAAANQADCggICAAAAA==.Rukawa:BAAANQADCgcICAAAAA==.',
Ry='Rylosh:BAACNQAFFH8eAAIXAAYK6gnoBgCVAQAXAAYK6gnoBgCVAQA1AAQKf0sAAhcACgo6GucNAKYCABcACgo6GucNAKYCAAAA.',
Sa='Sabornator:BAAANQAECgcIBQAAAA==.Sabot:BAAANQAECgUICQABNQAECgcIBQASAAAAAA==.Samaximilan:BAAANQAECgUIBQAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgASAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECgoKLwAHAGgdAA==.',
Sh='Shamantics:BAAANQAECgEIAQABNQAFFAcIEgAdAMAkAA==.Shamerica:BAACNQAFFH8aAAIEAAcKsB0vAwC7AQAEAAcKsB0vAwC7AQA1AAQKf0gAAgQACgoaJVIEAFUDAAQACgoaJVIEAFUDAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAACNQAFFH8HAAIJAAUKKh9BEABSAQAJAAUKKh9BEABSAQA1AAQKfyIAAgkACgowIeQPAC4DAAkACgowIeQPAC4DAAAA.',
Sl='Slagothor:BAABNQAECn8aAAIIAAgKJAbYdQBBAQAIAAgKJAbYdQBBAQAAAA==.',
So='Soultax:BAAANQAECgQICQAAAA==.',
Sp='Spekaleks:BAAANQAECgIIAwAAAA==.Spinfat:BAACNQAFFH8PAAIaAAcK7hcnBABMAQAaAAcK7hcnBABMAQA1AAQKfywAAhoACgpSI80KACcDABoACgpSI80KACcDAAAA.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgcIEQAAAA==.Starbux:BAAANQAECgYIDwABNQAECgoKJAAKAMkNAA==.Starbúcks:BAAANQAECgEIAQABNQAECgoKJAAKAMkNAA==.Stockgodx:BAAANQAECgYICQAAAA==.',
Su='Sugarr:BAAANQAECgEIAQABNQAECgoKHwAGAC4XAA==.',
Sy='Syb:BAAANQAECgUICQAAAA==.',
Ta='Taeyang:BAABNQAECn8vAAQMAAoKDiTsGgAaAwAMAAkK0CPsGgAaAwALAAEKgiQYHwBkAAAdAAEKFiG6JgBRAAAAAA==.Tankadin:BAAANQADCgcIBwABNQAECggIIgAGAOUVAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Telafar:BAAANQAECggIEAAAAA==.Terraform:BAAANQADCgEIAQAAAA==.',
Th='Thavus:BAAANQADCgMIAwAAAA==.Theinsider:BAABNQAECn8WAAIMAAoKghXEcQALAgAMAAoKghXEcQALAgABNQAECgoKLwAHAGgdAA==.Theoutsider:BAABNQAECn8vAAMHAAoKaB2IHACmAgAHAAkKJx2IHACmAgAIAAgKFRxEQwAOAgAAAA==.',
Ti='Timhair:BAAANQADCgYIGgAAAA==.Tindril:BAAANQADCgYIBgAAAA==.Tinkerstorm:BAAANQADCgUIBQABNQAFFAQIDwATACgYAA==.',
To='Toekneess:BAABNQAECn8sAAIKAAoKuiX3AwCwAwAKAAoKuiX3AwCwAwAAAA==.Toekneez:BAAANQAECgcIEgABNQAECgoKLAAKALolAA==.Toekneezz:BAABNQAECn8nAAIcAAkKdSPBAwBzAwAcAAkKdSPBAwBzAwABNQAECgoKLAAKALolAA==.Totemmalotes:BAAANQADCgMIAwAAAA==.Totemofbear:BAABNQAECn8qAAIiAAoKjRTjCgDdAQAiAAoKjRTjCgDdAQAAAA==.',
Tr='Trandis:BAABNQAECn8oAAMaAAoK8iL+CABBAwAaAAoK8iL+CABBAwAcAAEKEQbeOwAjAAAAAA==.Tranza:BAABNQAECn8iAAIGAAgK5RUhgAAMAgAGAAgK5RUhgAAMAgAAAA==.Trash:BAAANQAECgEIAQABNQAECgUIDAASAAAAAA==.',
Tx='Tx:BAACNQAFFH8RAAIEAAYKCxLCCADlAQAEAAYKCxLCCADlAQA1AAQKfyUAAgQACQpMH9oeABIDAAQACQpMH9oeABIDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Um='Umei:BAAANQADCgIIAgAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgoKIwAIAFMXAA==.Utterchaos:BAABNQAECn8XAAIeAAUKSx0oKwCEAQAeAAUKSx0oKwCEAQABNQAECgcIJwAZALYRAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQAECgQIBAAAAA==.',
Wa='Wazupp:BAAANQAECggICAAAAA==.',
We='Wematanye:BAAANQADCgYIHAABNQAECgkJKgAhAIYOAA==.Wetheals:BAAANQAECgcIDQAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQASAAAAAA==.',
Wo='Worgnfreeman:BAABNQAECn8WAAQJAAkK3AM3cQBtAAAJAAUKFQY3cQBtAAAHAAIKawKsvAAhAAAIAAgKQQHG+QAeAAAAAA==.',
Wt='Wtfmate:BAAANQAECgYIBgABNQAFFAcIEQAKALMOAA==.Wtfmonk:BAABNQAECn8pAAIcAAoKUBc+EAB7AgAcAAoKUBc+EAB7AgABNQAFFAcIEQAKALMOAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQAECgUICQAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAASAAAAAA==.',
Xs='Xsaber:BAAANQAECgEIAQAAAA==.',
Ya='Yangyin:BAAANQAECggIDgAAAA==.Yazmo:BAACNQAFFH8cAAIbAAcKBCWMAQAcAgAbAAcKBCWMAQAcAgA1AAQKfzsAAhsACgoZJncFAIEDABsACgoZJncFAIEDAAAA.',
Yu='Yushe:BAAANQAECgIIAgAAAA==.Yuuky:BAABNQAECn85AAIXAAoK7xtUEQDJAgAXAAoK7xtUEQDJAgAAAA==.',
Za='Zarivia:BAAANQADCgQIBAAAAA==.',
['Ða']='Ðaholyßeef:BAAANQAECgIIAQABNQAECgoKOwAMAJwfAA==.',
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
