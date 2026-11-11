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

local lookup = {'Warlock-Demonology','Warrior-Arms','DeathKnight-Blood','Unknown-Unknown','Shaman-Enhancement','DemonHunter-Havoc','Druid-Feral','Evoker-Preservation','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Shaman-Restoration','Mage-Arcane','Mage-Frost','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Warrior-Protection','Paladin-Protection','Priest-Holy','Priest-Shadow','Shaman-Elemental','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Frost','Warrior-Fury','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Vengeance','Rogue-Assassination','Paladin-Holy','Hunter-Marksmanship','DeathKnight-Unholy',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=53,date='2026-11-10',data={Ae='Aethrion:BAAANQAECgEIAgABNQAECgoKLgABAFEcAA==.',
Ai='Aitharlis:BAAANQADCgEIAQAAAA==.',
Al='Alexya:BAAANQADCgYIBgAAAA==.Alphahawk:BAABNQAECn81AAICAAoKrxFFdQA1AgACAAoKrxFFdQA1AgAAAA==.',
Ap='Applepie:BAAANQAECgIIBwABNQAECgoKJwADAFcfAA==.',
Ar='Aralia:BAAANQAECgUIBQABNQABCgIIAgAEAAAAAA==.Aramis:BAAANQAECgQIBAABNQABCgIIAgAEAAAAAA==.Arathram:BAABNQAECn8fAAIFAAoKZhMBFAApAgAFAAoKZhMBFAApAgABNQABCgIIAgAEAAAAAA==.',
As='Askaria:BAAANQAECgMIAwABNQAFFAUICQAGAOoGAA==.Asmoday:BAAANQADCgYIDAABNQAECgUICgAEAAAAAA==.Asunawa:BAAANQAECgQICAAAAA==.',
Au='Aundarr:BAAANQAECgIJAwABNQAECgUICgAEAAAAAA==.',
Ba='Balvos:BAAANQAFFAMIBAAAAA==.Bat:BAABNQAECn8uAAIHAAoKpySyAQBJAwAHAAoKpySyAQBJAwAAAA==.',
Be='Beradok:BAAANQAECgQIBAAAAA==.',
Bl='Bladerazor:BAAANQADCgEIAQAAAA==.',
Bo='Boomster:BAAANQAFFAgIBAABNQAFFAgIBQAIAIgjAA==.',
Br='Bri:BAAANQAECgYIEQAAAA==.',
Ca='Calixta:BAABNQAECn80AAIJAAoK8CJKIwA3AwAJAAoK8CJKIwA3AwAAAA==.Camel:BAAANQADCgQIAgAAAA==.',
Ce='Ceolen:BAAANQAECgYIDwAAAA==.',
Ch='Cherrypie:BAAANQAECgQIBAABNQAECgoKJwADAFcfAA==.Chiffonpie:BAAANQADCgYIBgAAAA==.',
Co='Coquette:BAABNQAECn8dAAICAAgKAA5LtACaAQACAAgKAA5LtACaAQAAAA==.',
Cp='Cptbarnacles:BAABNQAECn8XAAQBAAkKOQ0MfgBRAQABAAkKwgwMfgBRAQAKAAIKmRJiHAB/AAALAAEKAAB+PgAAAAAAAA==.',
Cr='Crab:BAAANQADCgMIAwABNQAECgoKVQAMAFEgAA==.Cranberrypie:BAABNQAECn8dAAINAAoKdxUFdQCxAQANAAoKdxUFdQCxAQABNQAECgoKJwADAFcfAA==.Criscomaster:BAABNQAECn8zAAILAAkK5BNxBQCIAQALAAkK5BNxBQCIAQAAAA==.Crit:BAAANQABCgQICAAAAA==.',
Cy='Cylla:BAACNQAFFH8JAAIOAAMKhB3gBQCpAAAOAAMKhB3gBQCpAAA1AAQKf0kAAg4ACgrVIhcCAFoDAA4ACgrVIhcCAFoDAAAA.',
Da='Dazãr:BAAANQADCgUIBgAAAA==.',
De='Dethbycrisco:BAAANQADCgMIBQAAAA==.',
Di='Dilfdormu:BAACNQAFFH8LAAIIAAQKUQfcDwD6AAAIAAQKUQfcDwD6AAA1AAQKf0IABAgACgpJHzYGAPcCAAgACgpJHzYGAPcCAA8AAQoAAOBBACYAABAAAQpaBmkoACAAAAAA.',
Do='Donkey:BAAANQAECgIIAQAAAA==.Doson:BAABNQAECn8vAAIRAAoKrxuSDwBpAgARAAoKrxuSDwBpAgAAAA==.',
Dr='Dratak:BAACNQAFFH8+AAISAAgKsiIdAABnAgASAAgKsiIdAABnAgA1AAQKf2kAAhIACgrxJgwAAKQDABIACgrxJgwAAKQDAAAA.Dratalt:BAABNQAFFH8gAAISAAYKahx1AADZAQASAAYKahx1AADZAQABNQAFFAgIPgASALIiAA==.Dreadfang:BAAANQADCgQIBAAAAA==.',
Ei='Eisdrameir:BAAANQADCgYICQAAAA==.',
El='Elitzai:BAAANQAECgUIDQAAAA==.Elspethstorm:BAABNQAECn8UAAITAAUK/BOZPQAIAQATAAUK/BOZPQAIAQAAAA==.',
Em='Emeralda:BAAANQAECgQIEAAAAA==.',
Ev='Evalueate:BAAANQAECgUJBQAAAA==.',
Fe='Feets:BAAANQAECgUIBgABNQAFFAIIBQAMAHEcAA==.',
Fr='Frocknor:BAAANQAECgQIBwAAAA==.',
Fu='Fuki:BAAANQADCggIIQAAAA==.',
Ga='Galumian:BAACNQAFFH82AAIUAAgKsSPwAADqAgAUAAgKsSPwAADqAgA1AAQKf0wAAxQACgpTJBsFAKADABQACgpTJBsFAKADABUAAQpWIelNAGAAAAAA.',
Ge='Gergo:BAAANQADCgUICgAAAA==.Geron:BAAANQADCgYIBgABNQAECgoKNAAJAPAiAA==.Geronimô:BAAANQABCgQIBgAAAA==.',
Gr='Grasswonder:BAAANQADCgYIBgAAAA==.',
Gu='Guy:BAACNQAFFH8hAAIIAAgK8xH9BAAdAgAIAAgK8xH9BAAdAgA1AAQKfygAAggACgppHkIPALQCAAgACgppHkIPALQCAAE1AAEKAwgDAAQAAAAA.',
Ha='Hailren:BAAANQAECgcIDQAAAA==.Haradali:BAABNQAECn8cAAIWAAoKFRHXcgDIAQAWAAoKFRHXcgDIAQAAAA==.',
Ho='Hondoe:BAAANQAECgUICwAAAA==.Hordehound:BAAANQADCgQIBAAAAA==.',
Ja='Jasminetea:BAABNQAECn83AAMUAAoKjBssNwCLAgAUAAoKjBssNwCLAgAVAAEKAADbcwA+AAAAAA==.',
Ju='Judgment:BAAANQAECgUIBAABNQAECggIFQAXAMIhAA==.',
Ka='Kairne:BAAANQAECgQIBAAAAA==.',
Ki='Kittybutt:BAAANQAECgYICQABNQAFFAIIBQAMAHEcAA==.',
Kr='Krizara:BAAANQAECgEIAQABNQAECgQIBwAEAAAAAA==.Kroth:BAABNQAECn84AAIYAAoKJg1cKwDDAQAYAAoKJg1cKwDDAQAAAA==.',
Ku='Kubfury:BAAANQAECgcICQAAAA==.',
Le='Lediah:BAAANQAECgUIBwAAAA==.',
Li='Liilith:BAAANQADCgQIBAAAAA==.Lillia:BAABNQAECn8xAAMDAAoKBRp3HAALAgADAAoKBBl3HAALAgAZAAcKZRj8RwBgAQAAAA==.Lily:BAABNQAECn8hAAQCAAkKKBrtmADeAQACAAgKcxftmADeAQAaAAIK9h+XGwC+AAASAAIKlA0wOgBhAAABNQAECgoKMQADAAUaAA==.Limparrow:BAAANQADCgUIDwAAAA==.',
Ln='Lnav:BAAANQADCgUIBgAAAA==.',
Lu='Lunaci:BAABNQAECn8nAAIPAAgKsxvrCgCkAQAPAAgKsxvrCgCkAQAAAA==.',
['Lø']='Løop:BAAANQADCggICAAAAA==.',
Ma='Madyn:BAAANQADCgYIFQAAAA==.Magnusson:BAABNQAECn8fAAISAAgKBxjtEQAIAgASAAgKBxjtEQAIAgAAAA==.Masutado:BAABNQAECn8pAAIOAAoKPRo1CgAoAgAOAAoKPRo1CgAoAgAAAA==.Maven:BAAANQAECgYICQAAAA==.Mayernnaise:BAAANQAECgEIAQAAAA==.',
Me='Mellitha:BAAANQAECgQIBgAAAA==.',
Mi='Mirror:BAABNQAFFH8FAAIIAAUKiCMLBgAJAgAIAAUKiCMLBgAJAgAAAA==.Misfortune:BAAANQAECgIIAgABNQAECgoKNAAJAPAiAA==.Mitsy:BAAANQAECggICAABNQAECgoKMQADAAUaAA==.',
Mo='Montipython:BAAANQAECggICwAAAA==.Moons:BAABNQAECn88AAMbAAkKfSTQHAAkAwAbAAkKfSTQHAAkAwAcAAYKMhoCCQC0AQABNQAFFAUICQAGAOoGAA==.',
Mu='Munco:BAABNQAECn9CAAIGAAoKvSEnDABKAwAGAAoKvSEnDABKAwAAAA==.Muncola:BAAANQAECgEIAQABNQAECgoKQgAGAL0hAA==.Muncolito:BAAANQADCgEIAQABNQAECgoKQgAGAL0hAA==.',
No='Notker:BAABNQAECn8fAAIUAAgKAxGLeQCuAQAUAAgKAxGLeQCuAQAAAA==.',
Os='Osrs:BAAANQAECgYICAAAAA==.',
Pa='Pandorra:BAAANQADCgYICwAAAA==.Papaj:BAAANQABCggIEQAAAA==.Pasteurmoon:BAAANQAECgQIDwAAAA==.',
Pe='Peepingpanda:BAAANQADCgYIDQAAAA==.Penne:BAAANQADCgcIFwAAAA==.',
Pi='Pizzapie:BAABNQAECn8nAAMDAAoKVx83HADNAgADAAoKVx83HADNAgAZAAEKAABrsQAvAAAAAA==.',
Ra='Raffine:BAAANQAECgUICgAAAA==.Rango:BAAANQADCgQIBQAAAA==.',
Re='Rennik:BAACNQAFFH8JAAQBAAMKjR0NHAC4AAABAAIKjR0NHAC4AAALAAEKaBbfEABKAAAKAAEKAABtFwAAAAA1AAQKf0gABAEACgpiJZsPAFQDAAEACgriI5sPAFQDAAsABArKJIQaAJgBAAoAAQoAAFwnAE4AAAAA.Revenant:BAAANQADCgYIBgAAAA==.',
['Rú']='Rúnil:BAAANQADCggIGgAAAA==.',
Sa='Saeris:BAAANQADCgUIBQAAAA==.Salsajenny:BAAANQAECgMIAwAAAA==.Sanise:BAAANQADCggIGAAAAA==.',
Sc='Scorewin:BAEBNQAECn8sAAIdAAkKViICAwBAAwAdAAkKViICAwBAAwAAAA==.',
Se='Seral:BAAANQADCgcIBwAAAA==.',
Sh='Shankdela:BAABNQAECn8XAAIeAAkKYwwnPwDRAQAeAAkKYwwnPwDRAQAAAA==.',
Si='Sinappi:BAABNQAECn8iAAIRAAoKdRkeFQAWAgARAAoKdRkeFQAWAgAAAA==.Siñ:BAABNQAECn86AAIeAAkKLxJODAD7AQAeAAkKLxJODAD7AQAAAA==.',
Sk='Skeetshootah:BAAANQAECgUICAAAAA==.Skunkstomper:BAAANQADCgIIAgABNQADCgUIBQAEAAAAAA==.Skunkstömper:BAAANQABCgUIBQAAAA==.Skúnkstomper:BAAANQADCgUIBQAAAA==.Skûnkstomper:BAAANQABCgIIAgABNQADCgUIBQAEAAAAAA==.',
Sl='Slowbadon:BAABNQAECn8aAAMfAAgKfRAKigB+AQAfAAgKfRAKigB+AQAJAAQKpQziMgHOAAAAAA==.',
Sp='Spáceballs:BAAANQADCgIIAgABNQADCgUIBQAEAAAAAA==.',
St='Stakkzy:BAAANQAECgQIBwABNQAECggIFAAcAN8PAA==.Stay:BAABNQAFFH8FAAIfAAUKCxVcCwB+AQAfAAUKCxVcCwB+AQABNQAFFAgIBQAIAIgjAA==.Streetdruid:BAAANQADCgYIBgABNQADCggIDgAEAAAAAA==.Streetlight:BAABNQAECn8VAAMbAAcKKhBzxQB3AQAbAAYKvA1zxQB3AQAgAAMKyQ0tYgCgAAABNQADCggIDgAEAAAAAA==.Streetlizard:BAAANQADCgYIBgABNQADCggIDgAEAAAAAA==.Streetpriest:BAAANQADCggIDgAAAA==.Streets:BAAANQADCgYIBgABNQADCggIDgAEAAAAAA==.',
Ta='Tank:BAACNQAFFH8HAAISAAMKdRa8BACOAAASAAMKdRa8BACOAAA1AAQKf0EAAhIACgqsIbgCAIMDABIACgqsIbgCAIMDAAAA.',
Te='Teafayd:BAAANQADCgYIEwAAAA==.',
Th='Thunderdot:BAABNQAECn8lAAIVAAkKyiEBDQAbAwAVAAkKyiEBDQAbAwAAAA==.',
Ti='Tigolock:BAAANQAECgMIAwABNQAECgQIBAAEAAAAAA==.Tilvayne:BAACNQAFFH8RAAMhAAUKnRdNBgDwAAAhAAUKnRdNBgDwAAAZAAMKZgYuEgC6AAA1AAQKf00AAyEACgrQIAEKAMsCACEACgryHgEKAMsCABkACQq3HM0jAHICAAAA.',
To='Tomayter:BAABNQAECn8dAAIUAAgKGxefagDfAQAUAAgKGxefagDfAQAAAA==.',
Tr='Trinitee:BAAANQADCgUIBwAAAA==.Trist:BAABNQAECn8lAAMJAAkK9Rg6ZABuAgAJAAkK9Rg6ZABuAgAfAAMKSxIT5gC1AAAAAA==.',
Tu='Turbogoat:BAABNQAECn8lAAIhAAgKNx9aPQAqAgAhAAgKNx9aPQAqAgAAAA==.',
Tw='Twowolves:BAABNQAECn8lAAQLAAkK1x16LgARAQABAAYKjRyShADbAQALAAMKkB96LgARAQAKAAMKVRMPHACgAAAAAA==.',
Va='Valthir:BAAANQADCgYIBgAAAA==.',
Xe='Xevic:BAAANQAECgEIAQABNQAECgUICgAEAAAAAA==.',
Za='Zalar:BAAANQAECgEIAgABNQAFFAMICQABAI0dAA==.',
Ze='Zerene:BAABNQAECn8eAAILAAgKSBF+FQDBAQALAAgKSBF+FQDBAQAAAA==.',
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
