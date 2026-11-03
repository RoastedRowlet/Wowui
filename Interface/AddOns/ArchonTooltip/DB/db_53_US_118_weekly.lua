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

local lookup = {'Warlock-Demonology','Warrior-Arms','DeathKnight-Blood','Unknown-Unknown','Shaman-Enhancement','DemonHunter-Havoc','Druid-Feral','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Warrior-Protection','Paladin-Protection','Shaman-Restoration','Priest-Holy','Priest-Shadow','Shaman-Elemental','Druid-Restoration','DeathKnight-Frost','Warrior-Fury','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Vengeance','Rogue-Assassination','Paladin-Holy','Hunter-Marksmanship','DeathKnight-Unholy',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aethrion:BAAANQAECgIIBAABNQAECgoKLQABAFEcAA==.',
Ai='Aitharlis:BAAANQADCgEIAQAAAA==.',
Al='Alexya:BAAANQADCgYIBgAAAA==.Alphahawk:BAABNQAECn81AAICAAoKrxFFdQA1AgACAAoKrxFFdQA1AgAAAA==.',
Ap='Applepie:BAAANQAECgIICgABNQAECgoKJgADAFcfAA==.',
Ar='Aralia:BAAANQAECgUIBQABNQABCgIIAgAEAAAAAA==.Aramis:BAAANQAECgQIBAABNQABCgIIAgAEAAAAAA==.Arathram:BAABNQAECn8fAAIFAAoKZhMBFAApAgAFAAoKZhMBFAApAgABNQABCgIIAgAEAAAAAA==.',
As='Askaria:BAAANQAECgMIAwABNQAFFAUICQAGAOoGAA==.Asmoday:BAAANQADCgYIDAABNQAECgUICgAEAAAAAA==.Asunawa:BAAANQAECgQICgAAAA==.',
Au='Aundarr:BAAANQAECgIJAwABNQAECgUICgAEAAAAAA==.',
Ba='Balvos:BAAANQAFFAIIAgAAAA==.Bat:BAABNQAECn8mAAIHAAoK9COoAQA6AwAHAAoK9COoAQA6AwAAAA==.',
Be='Beradok:BAAANQAECgQIBAAAAA==.',
Bl='Bladerazor:BAAANQADCgEIAQAAAA==.',
Bo='Boomster:BAAANQAFFAgIBAAAAA==.',
Br='Bri:BAAANQAECgYIEQAAAA==.',
Ca='Calixta:BAABNQAECn8zAAIIAAoK8CJKIwA3AwAIAAoK8CJKIwA3AwAAAA==.Camel:BAAANQADCgQIAgAAAA==.',
Ce='Ceolen:BAAANQAECgYICwAAAA==.',
Ch='Cherrypie:BAAANQAECgQIBAABNQAECgoKJgADAFcfAA==.Chiffonpie:BAAANQADCgYIBgAAAA==.',
Co='Coquette:BAABNQAECn8cAAICAAcK2w5LtACaAQACAAcK2w5LtACaAQAAAA==.',
Cp='Cptbarnacles:BAABNQAECn8XAAQBAAkKOQ20cgBJAQABAAkKwgy0cgBJAQAJAAIKmRI6GAB/AAAKAAEKAACsOQAAAAAAAA==.',
Cr='Crab:BAAANQADCgMIAwAAAA==.Cranberrypie:BAABNQAECn8cAAILAAoKdxUHaQCyAQALAAoKdxUHaQCyAQABNQAECgoKJgADAFcfAA==.Criscomaster:BAABNQAECn8pAAIKAAgKShRABwAzAQAKAAgKShRABwAzAQAAAA==.Crit:BAAANQAECgEIAgAAAA==.',
Cy='Cylla:BAACNQAFFH8GAAIMAAIK1BmkBQChAAAMAAIK1BmkBQChAAA1AAQKf0UAAgwACgpeIhcCAFoDAAwACgpeIhcCAFoDAAAA.',
Da='Dazãr:BAAANQADCgUIBgAAAA==.',
De='Dethbycrisco:BAAANQADCgMIBQAAAA==.',
Di='Dilfdormu:BAACNQAFFH8LAAINAAQKUQfcDwD6AAANAAQKUQfcDwD6AAA1AAQKf0IABA0ACgpJH0gFAPwCAA0ACgpJH0gFAPwCAA4AAQoAAOBBACYAAA8AAQpaBmkoACAAAAAA.',
Do='Donkey:BAAANQAECgIIAgAAAA==.Doson:BAABNQAECn8vAAIQAAoKrxuSDwBpAgAQAAoKrxuSDwBpAgAAAA==.',
Dr='Dratak:BAACNQAFFH85AAIRAAgKsiIPAABsAgARAAgKsiIPAABsAgA1AAQKf18AAhEACgrwJg0AAKIDABEACgrwJg0AAKIDAAAA.Dratalt:BAABNQAFFH8cAAIRAAYKLBxLAADcAQARAAYKLBxLAADcAQABNQAFFAgIOQARALIiAA==.Dreadfang:BAAANQADCgQIBAAAAA==.',
Ei='Eisdrameir:BAAANQADCgYICQAAAA==.',
El='Elitzai:BAAANQAECgYIDwAAAA==.Elspethstorm:BAABNQAECn8UAAISAAUK/BOZPQAIAQASAAUK/BOZPQAIAQAAAA==.',
Em='Emeralda:BAAANQAECgQIEAAAAA==.',
Ev='Evalueate:BAAANQAECgUJBQAAAA==.',
Fe='Feets:BAAANQAECgUIBgABNQAECgoKIwATAPgbAA==.',
Fr='Frocknor:BAAANQAECgQIBgAAAA==.',
Fu='Fuki:BAAANQADCggIIQAAAA==.',
Ga='Galumian:BAACNQAFFH82AAIUAAgKsSPwAADqAgAUAAgKsSPwAADqAgA1AAQKf0gAAxQACgpTJBsFAKADABQACgpTJBsFAKADABUAAQpWIU9GAGIAAAAA.',
Ge='Gergo:BAAANQADCgUICgAAAA==.Geron:BAAANQADCgYIBgABNQAECgoKMwAIAPAiAA==.Geronimó:BAAANQAECgEIAQABNQAECgEIBAAEAAAAAA==.Geronimô:BAAANQAECgEIAQAAAA==.Gerønimo:BAAANQAECgEIAgAAAA==.',
Gr='Grasswonder:BAAANQADCgYIBgAAAA==.',
Gu='Guy:BAACNQAFFH8hAAINAAgK8xH9BAAdAgANAAgK8xH9BAAdAgA1AAQKfygAAg0ACgppHkIPALQCAA0ACgppHkIPALQCAAE1AAEKAwgDAAQAAAAA.',
Ha='Hailren:BAAANQAECgcIDQAAAA==.Haradali:BAABNQAECn8YAAIWAAgKGBDXcgDIAQAWAAgKGBDXcgDIAQAAAA==.',
Ho='Hondoe:BAAANQAECgUICwAAAA==.Hordehound:BAAANQADCgQIBAAAAA==.',
Ja='Jasminetea:BAABNQAECn83AAMUAAoKjBuDLgBVAgAUAAoKjBuDLgBVAgAVAAEKAADbcwA+AAAAAA==.',
Ji='Jim:BAAANQAECgEIAQAAAA==.',
Ju='Judgment:BAAANQAECgQIBgABNQAECggICgAEAAAAAA==.',
Ka='Kairne:BAAANQAECgQIBAAAAA==.',
Ki='Kittybutt:BAAANQAECgYICgABNQAECgoKIwATAPgbAA==.',
Kr='Krizara:BAAANQAECgEIAQABNQAECgQIBgAEAAAAAA==.Kroth:BAABNQAECn84AAIXAAoKJg1cKwDDAQAXAAoKJg1cKwDDAQAAAA==.',
Ku='Kubfury:BAAANQAECgIIAgAAAA==.',
Le='Lediah:BAAANQAECgEIAgAAAA==.',
Li='Liilith:BAAANQADCgQIBAAAAA==.Lillia:BAABNQAECn8xAAMDAAoKBRoGGQARAgADAAoKBBkGGQARAgAYAAcKZRhTPgBkAQAAAA==.Lily:BAABNQAECn8gAAQCAAkKKBoYdwBmAQACAAgKcxcYdwBmAQAZAAIK9h+9FwDCAAARAAIKlA0wOgBhAAABNQAECgoKMQADAAUaAA==.Limparrow:BAAANQADCgUIDwAAAA==.',
Ln='Lnav:BAAANQADCgUIBgAAAA==.',
Lu='Lunaci:BAABNQAECn8iAAIOAAcKlB2HEQA7AgAOAAcKlB2HEQA7AgAAAA==.',
['Lø']='Løop:BAAANQADCggICAAAAA==.',
Ma='Madyn:BAAANQADCgYIFQAAAA==.Magnusson:BAABNQAECn8eAAIRAAcKSBntEQAIAgARAAcKSBntEQAIAgAAAA==.Masutado:BAABNQAECn8lAAIMAAoKgxc1CgAoAgAMAAoKgxc1CgAoAgAAAA==.Maven:BAAANQAECgYICQAAAA==.Mayernnaise:BAAANQAECgEIAQAAAA==.',
Me='Mellitha:BAAANQAECgQIBgAAAA==.',
Mi='Mirror:BAABNQAFFH8FAAINAAUKiCOfBAAPAgANAAUKiCOfBAAPAgABNQAFFAgIBAAEAAAAAA==.Misfortune:BAAANQAECgIIAwABNQAECgoKMwAIAPAiAA==.Mitsy:BAAANQAECgYICgABNQAECgoKMQADAAUaAA==.',
Mo='Montipython:BAAANQAECggIDAAAAA==.Moons:BAABNQAECn88AAMaAAkKfSTQHAAkAwAaAAkKfSTQHAAkAwAbAAYKMhoCCQC0AQABNQAFFAUICQAGAOoGAA==.',
Mu='Munco:BAABNQAECn9AAAIGAAoKUSEnDABKAwAGAAoKUSEnDABKAwAAAA==.Muncola:BAAANQAECgEIAQABNQAECgoKQAAGAFEhAA==.Muncolito:BAAANQADCgEIAQABNQAECgoKQAAGAFEhAA==.',
No='Notker:BAABNQAECn8eAAIUAAcK5hGLeQCuAQAUAAcK5hGLeQCuAQAAAA==.',
Os='Osrs:BAAANQAECgYICAAAAA==.',
Pa='Pandorra:BAAANQADCgYICwAAAA==.Papaj:BAAANQABCggIEQAAAA==.Pasteurmoon:BAAANQAECgQIDwAAAA==.',
Pe='Peepingpanda:BAAANQADCgYIDQAAAA==.Penne:BAAANQADCgcIFwAAAA==.',
Pi='Pizzapie:BAABNQAECn8mAAMDAAoKVx83HADNAgADAAoKVx83HADNAgAYAAEKAABrsQAvAAAAAA==.',
Ra='Raffine:BAAANQAECgUIBQAAAA==.Rango:BAAANQADCgQIBQAAAA==.',
Re='Rennik:BAACNQAFFH8GAAMBAAIKZx3QJQBrAAABAAEKZiTQJQBrAAAKAAEKaBaTDwBKAAA1AAQKf0QABAEACgo/JZsPAFQDAAEACgrAI5sPAFQDAAoABArKJIQaAJgBAAkAAQoAAFwnAE4AAAAA.Revenant:BAAANQADCgYIBgAAAA==.',
['Rú']='Rúnil:BAAANQAECgEIAQAAAA==.',
Sa='Saeris:BAAANQADCgUIBQAAAA==.Salsajenny:BAAANQAECgIIBQAAAA==.Sanise:BAAANQADCggIGAAAAA==.',
Sc='Scorewin:BAEBNQAECn8sAAIcAAkKViICAwBAAwAcAAkKViICAwBAAwAAAA==.',
Se='Seral:BAAANQADCgcIBwAAAA==.',
Sh='Shankdela:BAABNQAECn8XAAIdAAkKYwwnPwDRAQAdAAkKYwwnPwDRAQAAAA==.',
Si='Simi:BAAANQAECgEIAQAAAA==.Sinappi:BAABNQAECn8eAAIQAAcKnRoeFQAWAgAQAAcKnRoeFQAWAgAAAA==.Siñ:BAABNQAECn8zAAIdAAgKPg9kEACfAQAdAAgKPg9kEACfAQAAAA==.',
Sk='Skeetshootah:BAAANQAECgQIBwAAAA==.Skunkstomper:BAAANQAECgEIAQABNQAECgEIBAAEAAAAAA==.Skunkstömper:BAAANQAECgEIAQAAAA==.Skùnkstomper:BAAANQAECgEIAgAAAA==.Skúnkstomper:BAAANQAECgEIAQABNQAECgEIBAAEAAAAAA==.Skûnkstomper:BAAANQAECgEIBAAAAA==.',
Sl='Slowbadon:BAABNQAECn8ZAAMeAAcKeQ4KigB+AQAeAAcKeQ4KigB+AQAIAAQKpQziMgHOAAAAAA==.',
Sp='Spáceballs:BAAANQADCgIIAgABNQAECgEIBAAEAAAAAA==.',
St='Stakkzy:BAAANQAECgQIBwABNQAECggIFAAbAN8PAA==.Stay:BAABNQAFFH8FAAIeAAUKCxVbCQCEAQAeAAUKCxVbCQCEAQABNQAFFAgIBAAEAAAAAA==.Streetdruid:BAAANQADCgYIBgABNQADCggIDgAEAAAAAA==.Streetlight:BAABNQAECn8VAAMaAAcKKhBzxQB3AQAaAAYKvA1zxQB3AQAfAAMKyQ0tYgCgAAABNQADCggIDgAEAAAAAA==.Streetlizard:BAAANQADCgYIBgABNQADCggIDgAEAAAAAA==.Streetpriest:BAAANQADCggIDgAAAA==.Streets:BAAANQADCgYIBgABNQADCggIDgAEAAAAAA==.',
Ta='Tank:BAABNQAECn89AAIRAAoK7h+4AgCDAwARAAoK7h+4AgCDAwAAAA==.',
Te='Teafayd:BAAANQADCgYIEwAAAA==.',
Th='Thunderdot:BAABNQAECn8lAAIVAAkKyiEBDQAbAwAVAAkKyiEBDQAbAwAAAA==.',
Ti='Tigolock:BAAANQAECgMICAABNQAECgQIBAAEAAAAAA==.Tilvayne:BAACNQAFFH8NAAMgAAUKyw1YCgCPAAAYAAMKZgYuEgC6AAAgAAUKIQxYCgCPAAA1AAQKf0sAAyAACgrQIEAIANYCACAACgryHkAIANYCABgACQq3HM0jAHICAAAA.',
To='Tomayter:BAABNQAECn8cAAIUAAcKEhmfagDfAQAUAAcKEhmfagDfAQAAAA==.',
Tr='Trinitee:BAAANQADCgUIBwAAAA==.Trist:BAABNQAECn8lAAMIAAkK9Rg6ZABuAgAIAAkK9Rg6ZABuAgAeAAMKSxIT5gC1AAAAAA==.',
Tu='Turbogoat:BAABNQAECn8kAAIgAAgKNx9aPQAqAgAgAAgKNx9aPQAqAgAAAA==.',
Tw='Twowolves:BAABNQAECn8lAAQKAAkK1x16LgARAQABAAYKjRyShADbAQAKAAMKkB96LgARAQAJAAMKVRMPHACgAAAAAA==.',
Va='Valthir:BAAANQADCgYIBgAAAA==.',
Xe='Xevic:BAAANQAECgEIAQABNQAECgUICgAEAAAAAA==.',
Za='Zalar:BAAANQAECgEIAgABNQAFFAIIBgABAGcdAA==.',
Ze='Zerene:BAABNQAECn8dAAIKAAcKCRF+FQDBAQAKAAcKCRF+FQDBAQAAAA==.',
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
