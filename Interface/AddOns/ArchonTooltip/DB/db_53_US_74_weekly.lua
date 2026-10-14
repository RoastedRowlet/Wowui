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

local lookup = {'Druid-Restoration','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Blood','Mage-Arcane','Warrior-Fury','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Rogue-Assassination','Mage-Fire','Druid-Feral','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adarlaliiana:BAAANQAECgQIDgAAAA==.',
Ar='Arcadius:BAAANQADCgUICQAAAA==.',
At='Athenia:BAAANQADCgIIAgAAAA==.',
Ax='Axél:BAAANQADCgcIDQAAAA==.',
Az='Azarathia:BAAANQADCgEIAQAAAA==.',
Ba='Barbaria:BAAANQAECgUIDAAAAA==.Bastas:BAABNQAECn8fAAIBAAkKAAr/LQCnAQABAAkKAAr/LQCnAQAAAA==.',
Be='Beekro:BAACNQAFFH8IAAICAAMKiQ15BwDUAAACAAMKiQ15BwDUAAA1AAQKfyYAAgIACQqDG58DAO0CAAIACQqDG58DAO0CAAAA.Beladentata:BAAANQAECgYIDAABNQAFFAMICAADAK8QAA==.Belarina:BAAANQAECgcICgABNQAFFAMICAADAK8QAA==.Belatink:BAACNQAFFH8IAAIDAAMKrxD5HgDiAAADAAMKrxD5HgDiAAA1AAQKf0AAAwMACQo9ImgKAG4DAAMACQo9ImgKAG4DAAQAAwonC3YbAIkAAAAA.Bernocke:BAAANQADCgYIBgAAAA==.',
Bi='Bilando:BAAANQAECggIEgAAAA==.',
Bl='Bludlust:BAAANQAECgQIBAAAAA==.Blueberry:BAACNQAFFH8IAAIDAAMKYCCDGQAdAQADAAMKYCCDGQAdAQA1AAQKfx8AAwQACQpLIv0DAJgCAAQABwqsIf0DAJgCAAMABgpSIHxYABUCAAAA.',
Bo='Bonezthug:BAABNQAECn8cAAMEAAgK7xVACgClAQADAAcK6A6pdwCwAQAEAAYKlhZACgClAQAAAA==.Borden:BAAANQAECgYIDAAAAA==.',
Ch='Chainer:BAABNQAECn8kAAIFAAkKyBaJSwCJAgAFAAkKyBaJSwCJAgAAAA==.',
Cl='Clubsandwich:BAAANQAECgEIAQAAAA==.',
Da='Dacker:BAAANQABCgEIAQAAAA==.Darthvolo:BAAANQAECgEIAQAAAA==.',
De='Demonveil:BAAANQADCgYIBgABNQAECgkJFwAGAOgcAA==.',
Do='Dolt:BAAANQAECgQIBwAAAA==.',
Dr='Drezzarnbez:BAAANQAECgEIAQAAAA==.Drvoidberg:BAAANQAECgYICwAAAA==.',
Du='Durgrim:BAAANQAECgYIEAAAAA==.',
Ee='Eeèva:BAAANQADCgYJCgAAAA==.',
El='Ellanaras:BAAANQAECgcIBwAAAA==.',
Em='Emi:BAAANQADCggIGAAAAA==.',
Ep='Epoxxy:BAAANQADCgYIBgAAAA==.',
Er='Erzkal:BAABNQAFFH8JAAMHAAUKdgloEgATAQAHAAUKiwRoEgATAQAFAAMK4QwhHwC0AAABNQAECggIFwAIAJEiAA==.',
Es='Espresso:BAACNQAFFH8TAAIJAAYKbxnyAwATAgAJAAYKbxnyAwATAgA1AAQKfygAAgkACQrzI30GAG8DAAkACQrzI30GAG8DAAAA.',
Fo='Foxme:BAAANQADCgIIAgAAAA==.',
Ga='Gaartak:BAACNQAFFH8IAAIKAAQKZiSJCwCYAQAKAAQKZiSJCwCYAQA1AAQKfzcAAgoACQpYJpUAAPQDAAoACQpYJpUAAPQDAAAA.Garren:BAABNQAECn8aAAILAAYKzwx3HQFXAQALAAYKzwx3HQFXAQAAAA==.',
Gi='Giantcow:BAAANQAECgMIAwAAAA==.Gith:BAACNQAFFH8HAAIFAAMKPQ5LGAD0AAAFAAMKPQ5LGAD0AAA1AAQKfxwAAgUACQoFGes+AKwCAAUACQoFGes+AKwCAAAA.Githlock:BAAANQAECgMIBAABNQAFFAMIBwAFAD0OAA==.Githon:BAAANQAFFAEIAQABNQAFFAMIBwAFAD0OAA==.',
Gl='Glittercakes:BAAANQAECgEIAQAAAA==.',
Gr='Grogrin:BAACNQAFFH8IAAIMAAQKJA1zAQAmAQAMAAQKJA1zAQAmAQA1AAQKfy8AAgwACQqIHKMEAOkCAAwACQqIHKMEAOkCAAAA.',
Ha='Halordric:BAAANQAECgEIAQABNQAECgUIBgANAAAAAA==.',
He='Hekate:BAAANQADCggICgAAAA==.Heyblinkin:BAAANQAECgQIBQAAAA==.',
Hi='Hitmonlee:BAAANQADCggICAABNQAFFAcIIAACAEAkAA==.',
Ho='Hocus:BAAANQAECgUIBgABNQAFFAMICAAOAJAPAA==.Houtoku:BAAANQAECgYIDAAAAQ==.Hozi:BAAANQADCgYIBgABNQAECgkJFgAJAOUUAA==.Hozina:BAABNQAECn8WAAQJAAkK5RTvNgBpAQAJAAYKqhDvNgBpAQADAAIKtwV65ABvAAAEAAIKwAWgIQBVAAAAAA==.',
Hu='Huck:BAAANQADCggIDgAAAA==.Hultron:BAAANQADCgIIAgAAAA==.Huntington:BAAANQAECgYIEwAAAA==.',
Im='Imcrying:BAAANQAECgQIBAABNQAFFAMICAAOAJAPAA==.Imtrying:BAACNQAFFH8IAAIOAAMKkA8NGQDOAAAOAAMKkA8NGQDOAAA1AAQKfykAAw4ACQq8IJAZAAkDAA4ACQq8IJAZAAkDAA8AAQp/B/csATgAAAAA.',
Iz='Izuna:BAABNQAECn8iAAIQAAkKTCB6GQC8AgAQAAkKTCB6GQC8AgAAAA==.',
Ja='Jayaesir:BAACNQAFFH8HAAIRAAMKChcNFwDrAAARAAMKChcNFwDrAAA1AAQKfzAAAhEACQr/JCcIALkDABEACQr/JCcIALkDAAAA.Jayal:BAACNQAFFH8HAAIRAAUKswhtDwBOAQARAAUKswhtDwBOAQA1AAQKfyYAAhEACQr0HvNKALACABEACQr0HvNKALACAAAA.',
Jo='Johndurgrim:BAACNQAFFH8IAAISAAQKqBthBgAiAQASAAQKqBthBgAiAQA1AAQKfzEABBIACQpSHxUMANcCABIACQpSHxUMANcCABMABQrwDBm8AAABABEAAQoAAC6CAU8AAAE1AAQKBggQAA0AAAAA.Joja:BAAANQADCgMIBgABNQAECggIHAAEAO8VAA==.Jooja:BAABNQAECn8eAAIUAAcKRA8LRgCoAQAUAAcKRA8LRgCoAQABNQAECggIHAAEAO8VAA==.',
Ka='Katbelle:BAACNQAFFH8IAAIVAAMKgghjAADZAAAVAAMKgghjAADZAAA1AAQKfysAAhUACQoYGHoBAKICABUACQoYGHoBAKICAAAA.',
Ke='Keyi:BAAANQADCggICAABNQAECgkJMAADAPYaAA==.Keynallan:BAAANQADCggIEQAAAA==.',
Ki='Kinkykelly:BAAANQAECggICQABNQAFFAYIEwAKAC0gAA==.Kinkyknight:BAACNQAFFH8TAAIKAAYKLSAhBQAfAgAKAAYKLSAhBQAfAgA1AAQKfxwAAgoACQrmHTgYAOkCAAoACQrmHTgYAOkCAAAA.Kinkypal:BAAANQAFFAEIAQABNQAFFAYIEwAKAC0gAA==.',
Kr='Kreslin:BAAANQAECgQIBAABNQAECgYIEAANAAAAAA==.Krixxus:BAAANQADCgQIBAAAAA==.',
Ku='Kuroishi:BAAANQAECgQIBAAAAA==.',
['Kø']='Kø:BAAANQAECgQIAwABNQAECggIFwAWAD4VAA==.',
La='Lahar:BAAANQAECgcICwABNQAECgkJLgADAOojAA==.Lancer:BAAANQAECgMIAwAAAA==.',
Li='Limptriscuit:BAAANQAECgEIAQAAAA==.Littlelam:BAACNQAFFH8GAAMXAAIKxRllIABJAAAXAAEKxRllIABJAAAKAAEKAAAsPQAXAAA1AAQKfxcAAhcACQp2IPQiALcCABcACQp2IPQiALcCAAAA.',
Lo='Locrock:BAAANQAECgYICAAAAA==.Lorkhan:BAAANQAECgYIDAAAAA==.Lotti:BAAANQADCgcIDQAAAA==.',
Lt='Ltcclover:BAAANQADCgYIFwAAAA==.',
Lu='Lugren:BAAANQAECgIIAwAAAA==.',
Ly='Lyssandra:BAAANQADCgEIAQAAAA==.',
Ma='Madclaw:BAAANQADCgYIBgAAAA==.Magith:BAAANQAECgcIDAAAAA==.Manhattan:BAAANQAECgQICAABNQAFFAYIEwAJAG8ZAA==.Martini:BAABNQAECn8aAAMUAAgKnx1AGAC2AgAUAAgK1RxAGAC2AgAGAAYKGxFNJwCIAQABNQAFFAYIEwAJAG8ZAA==.Mayalaran:BAAANQAECgQIBwABNQAECgYIDQANAAAAAA==.',
Mc='Mccavity:BAABNQAECn8vAAIYAAgK9RUvBwAsAgAYAAgK9RUvBwAsAgABNQABCgQIBAANAAAAAA==.',
Me='Mekabruti:BAAANQAECgQIBAABNQAECgcIDwANAAAAAA==.',
Mi='Misticphii:BAAANQADCgYIBgAAAA==.',
Mo='Moocelee:BAAANQADCgYIDAAAAA==.',
Mu='Murc:BAABNQAECn8sAAMXAAkKaxudMABpAgAXAAkKaxudMABpAgAQAAMK4g3YgACfAAAAAA==.Murdoch:BAAANQADCggICAAAAA==.',
Na='Na:BAAANQABCgQIBAAAAA==.',
Ne='Nevoir:BAAANQADCgQIBAAAAA==.',
Nh='Nhasgul:BAAANQAECgYIBgABNQABCgIIAgANAAAAAA==.Nhasraxion:BAACNQAFFH8IAAISAAMKTRqkBwDvAAASAAMKTRqkBwDvAAA1AAQKfyYAAxIACQoFIKYOAK8CABIACQq+HqYOAK8CABEABQrdGboMAQMBAAE1AAEKAggCAA0AAAAA.Nhasrezim:BAAANQAECgYIBgABNQABCgIIAgANAAAAAA==.',
Ni='Niceneasy:BAAANQADCgcIDAABNQAECgkJLAAXAGsbAA==.',
No='Nocturnal:BAAANQAECgMIBAAAAA==.Nowaifu:BAAANQAECgUICAAAAA==.',
Or='Ornithogalum:BAAANQADCgUIBgAAAA==.',
Ow='Owlbread:BAAANQAECgYIDAAAAA==.',
Oz='Ozwin:BAAANQAECgIIAQABNQAFFAQICAAKAGYkAA==.',
Pa='Palarin:BAACNQAFFH8YAAMTAAYKsCFYAwBfAgATAAYKsCFYAwBfAgARAAMK2B/4FAADAQA1AAQKfywAAxMACQr/JB0HAJEDABMACQr/JB0HAJEDABEAAwrhHl0aAewAAAAA.Pawmi:BAAANQAECgIIBAABNQAECgUICAANAAAAAA==.',
Pe='Peccator:BAABNQAECn8uAAIDAAkK6iPmAgC9AwADAAkK6iPmAgC9AwAAAA==.Persess:BAAANQAECgMIAwAAAA==.',
Pl='Plat:BAABNQAECn8aAAIWAAcKEA0NGAB2AQAWAAcKEA0NGAB2AQAAAA==.Ploo:BAABNQAECn8oAAIZAAkKGSOPBwBTAwAZAAkKGSOPBwBTAwAAAA==.',
Pu='Punkinhed:BAAANQADCggIDwAAAA==.',
Ra='Rahkor:BAAANQADCgUIBwABNQAECgkJLAAXAGsbAA==.Raveheart:BAAANQAECgYICgAAAA==.',
Re='Refr:BAABNQAECn8oAAIPAAkK/CFpGQAvAwAPAAkK/CFpGQAvAwAAAA==.Renzo:BAAANQAECgYICQABNQAFFAQICAAKAGYkAA==.',
Rh='Rhaegon:BAAANQADCgcICwAAAA==.',
Ri='Riskante:BAABNQAECn8qAAMTAAkKSBZ/RABRAgATAAkKSBZ/RABRAgARAAcKNRbOrgC8AQAAAA==.',
Ro='Roonrana:BAAANQADCgYIDAAAAA==.Rosecake:BAAANQAECgQICAAAAA==.Rosemari:BAAANQAECgQJBQABNQAFFAQICAAaAGsUAA==.Rosey:BAACNQAFFH8IAAIaAAQKaxR7AQA4AQAaAAQKaxR7AQA4AQA1AAQKfzkAAhoACQqAIjYBAIYDABoACQqAIjYBAIYDAAAA.Rouge:BAABNQAECn8XAAMGAAkK6BzeEABvAgAGAAcKOiDeEABvAgAUAAMKzBSWfQCzAAAAAA==.',
Sa='Sardor:BAAANQAECgUICQABNQAFFAQICAAKAGYkAA==.',
Sc='Scottyno:BAABNQAECn8kAAIRAAkKYBjSaQBbAgARAAkKYBjSaQBbAgAAAA==.',
Se='Senarria:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclaw:BAAANQADCgYICwAAAA==.Shanithell:BAAANQAECgQIAwAAAA==.Shanksz:BAAANQADCgIIAgAAAA==.Shellyd:BAAANQAECgEIAQAAAA==.',
Si='Siennaa:BAAANQADCgIIAgAAAA==.Sierra:BAAANQADCggJCAAAAA==.Sinfulsmite:BAAANQAECgcIDwAAAA==.',
Sk='Skark:BAAANQAECgIIAwAAAA==.',
Sl='Sleifer:BAAANQAECgQJCQAAAA==.Slothy:BAABNQAECn8lAAMbAAgK3RezVwBMAgAbAAgKiRazVwBMAgAcAAIKERtDUACNAAAAAA==.',
Sn='Sneakyhand:BAACNQAFFH8IAAIdAAMKEiUOGwA1AQAdAAMKEiUOGwA1AQA1AAQKfykAAx0ACQpiJk0JAKkDAB0ACQpiJk0JAKkDAB4AAQqhGUtAADoAAAAA.',
St='Starling:BAAANQAECgYIDQAAAA==.Stew:BAABNQAECn8WAAIfAAYKyQQQXgACAQAfAAYKyQQQXgACAQABNQAECggIHAAEAO8VAA==.',
Sy='Sylvi:BAAANQAECgYIDAAAAA==.',
Ta='Takitsu:BAAANQAECgEIAQAAAA==.',
Th='Tharion:BAAANQAECgYIDQAAAA==.',
Ti='Tinytoes:BAAANQAECgIIAgAAAA==.Tired:BAABNQAECn8XAAIWAAgKPhWyDgAmAgAWAAgKPhWyDgAmAgAAAA==.Tish:BAAANQAECggIEQABNQAECgYIEAANAAAAAA==.',
To='Tomn:BAAANQADCggICQAAAA==.Towa:BAACNQAFFH8IAAIfAAQKEA2JDwAHAQAfAAQKEA2JDwAHAQA1AAQKfzsAAwgACQqlGz8OANMBAB8ACQp7F7cnAFwCAAgABgooHT8OANMBAAAA.',
Tr='Trater:BAEANQADCgMIAwAAAA==.',
Va='Vaskie:BAECNQAFFH8MAAIdAAQKxhRPGQBIAQAdAAQKxhRPGQBIAQA1AAQKfzgAAh0ACQrBIgMTAG8DAB0ACQrBIgMTAG8DAAAA.',
Ve='Veil:BAAANQADCgYICAABNQAECgkJFwAGAOgcAA==.Vella:BAAANQAECggIEwAAAA==.',
Vo='Vooduel:BAAANQAECgcIBwAAAA==.',
Vy='Vyra:BAAANQAECgcIEQAAAA==.',
Wa='Wallê:BAAANQADCgYIBgAAAA==.',
We='Wetasscat:BAAANQAECgYIDQAAAA==.',
Wo='Wotardag:BAAANQADCgcJDQAAAA==.',
Ys='Ysayle:BAAANQAECgEJAgABNQAECgUICAANAAAAAA==.',
Yu='Yucky:BAAANQAECgUIBwAAAA==.',
Za='Zaht:BAAANQAECgUIBgAAAA==.Zargus:BAAANQAECgEIAQAAAA==.',
Ze='Zetsuon:BAABNQAECn8qAAIBAAgKER+OFAChAgABAAgKER+OFAChAgAAAA==.',
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
