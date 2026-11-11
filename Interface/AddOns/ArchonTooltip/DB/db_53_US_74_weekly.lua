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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','Priest-Discipline','Warrior-Protection','Warrior-Arms','Unknown-Unknown','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Blood','Mage-Arcane','Druid-Guardian','Druid-Balance','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Rogue-Assassination','Mage-Fire','DemonHunter-Devourer','Druid-Feral','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Adarlaliiana:BAAANQAECgQIDgAAAA==.',
Ap='Aphillion:BAAANQAECgEIAQAAAA==.',
Ar='Arator:BAAANQADCgMIAwAAAA==.Arcadius:BAAANQADCgUICQAAAA==.',
At='Athenia:BAAANQAECgEIAQAAAA==.',
Ax='Axél:BAAANQADCgcIDQAAAA==.',
Az='Azarathia:BAAANQADCgEIAQAAAA==.',
Ba='Barbaria:BAABNQAECn8WAAIBAAcKZBRcogBSAQABAAcKZBRcogBSAQAAAA==.Bastas:BAABNQAECn8fAAICAAkKAAp+LgCnAQACAAkKAAp+LgCnAQAAAA==.',
Be='Beekro:BAACNQAFFH8SAAIDAAYKyAuPBgAAAQADAAYKyAuPBgAAAQA1AAQKfzgAAwMACgqVHqkDAO0CAAMACgqVHqkDAO0CAAQAAQp8BLw7ACYAAAAA.Beladentata:BAAANQAECgYIDgABNQAFFAYIFgAFAEcXAA==.Belarina:BAAANQAECgcIDAABNQAFFAYIFgAFAEcXAA==.Belaspark:BAAANQAECgcIBwABNQAFFAYIFgAFAEcXAA==.Belated:BAAANQAECgcIBwAAAA==.Belatink:BAACNQAFFH8WAAIFAAYKRxesCgDjAQAFAAYKRxesCgDjAQA1AAQKf2MAAwUACgpVJO8EANcDAAUACgpVJO8EANcDAAYAAwonC7sbAIkAAAAA.Bernocke:BAAANQAECgUIBQAAAA==.',
Bi='Bilando:BAABNQAECn8XAAMHAAkKgRNbHAB3AQAIAAkKgw5CrwCnAQAHAAYK0hZbHAB3AQAAAA==.',
Bl='Bludlust:BAAANQAECgUIBQAAAA==.Blueberry:BAACNQAFFH8WAAIFAAYKdSGZBgBGAgAFAAYKdSGZBgBGAgA1AAQKfzQAAwUACgoBJBoNAGgDAAUACgp5IBoNAGgDAAYABwqsIQcEAJgCAAAA.',
Bo='Bonezthug:BAABNQAECn8cAAMGAAgK7xVSCgClAQAFAAcK6A4GeQCwAQAGAAYKlhZSCgClAQAAAA==.Borden:BAAANQAECgcIEAAAAA==.',
Ca='Calaart:BAAANQAECgEIAQAAAA==.',
Ch='Chainer:BAABNQAECn88AAIBAAoKDhf2TACHAgABAAoKDhf2TACHAgAAAA==.',
Cl='Clubsandwich:BAAANQAECgEIAgAAAA==.',
Da='Dacker:BAAANQABCgEIAQAAAA==.Daelen:BAAANQAECgIIAgABNQAECggIFQAJAAAAAQ==.Darthvolo:BAAANQAECgEIAQAAAA==.',
De='Deftones:BAAANQAECgQIBAAAAA==.Demonveil:BAAANQADCgYIBgABNQAECgkJFwAKAOgcAA==.Derina:BAAANQADCgYIAgAAAA==.',
Do='Dolt:BAAANQAECgQIBwAAAA==.Domiati:BAAANQADCgYIBgAAAA==.',
Dr='Drezzarnbez:BAAANQAECgEIAQAAAA==.Drvoidberg:BAAANQAECgYIDQAAAA==.',
Du='Durgrim:BAAANQAECgYIEgAAAA==.',
Ee='Eeèva:BAAANQADCgYJCgAAAA==.',
El='Electrabuzz:BAAANQAECgEIAQAAAA==.Ellanaras:BAAANQAECggIDwAAAA==.',
Em='Emi:BAAANQADCggIGAAAAA==.',
Ep='Epoxxy:BAAANQAECggIBQAAAA==.',
Er='Erzkal:BAABNQAFFH8JAAMLAAUKdgnKEgATAQALAAUKiwTKEgATAQABAAMK4QzdHwC0AAABNQAECggIFwAMAJEiAA==.',
Es='Espresso:BAACNQAFFH8WAAINAAgKmBcjBAASAgANAAgKmBcjBAASAgA1AAQKf0EAAg0ACgp7Jb8BAGsDAA0ACgp7Jb8BAGsDAAAA.',
Fi='Finkregh:BAAANQAECgEIAQAAAA==.',
Fo='Foxme:BAAANQADCgIIAgAAAA==.',
Ga='Gaartak:BAACNQAFFH8TAAIOAAYK3CQ8BwCYAQAOAAYK3CQ8BwCYAQA1AAQKf0UAAg4ACgo0JpUAAPQDAA4ACgo0JpUAAPQDAAAA.Garren:BAABNQAECn8aAAIPAAYKzwzQHwFXAQAPAAYKzwzQHwFXAQAAAA==.',
Gi='Giantcow:BAAANQAECgMIAwAAAA==.Gith:BAACNQAFFH8QAAIBAAUKDAxMCwAlAQABAAUKDAxMCwAlAQA1AAQKfyoAAgEACgoAGydAAKoCAAEACgoAGydAAKoCAAAA.Githlock:BAAANQAECgMIBQABNQAFFAUIEAABAAwMAA==.Githon:BAABNQAECn8jAAQCAAgK0A3dMgBAAQACAAgK0A3dMgBAAQAQAAYKaw+PMwAGAQARAAQKzwyOfwDQAAABNQAFFAUIEAABAAwMAA==.',
Gl='Glittercakes:BAAANQAECgEIAQAAAA==.',
Gr='Griselbrand:BAAANQAECgUIAQAAAA==.Grogrin:BAACNQAFFH8TAAISAAYKVA6rAAAfAQASAAYKVA6rAAAfAQA1AAQKf0YAAhIACgpxIVACAAIDABIACgpxIVACAAIDAAAA.',
Ha='Halordric:BAAANQAECgEIAgABNQAECgUIBwAJAAAAAA==.',
He='Hekate:BAAANQAECgEIAQAAAA==.Heyblinkin:BAAANQAECgUICAAAAA==.',
Hi='Hitmonlee:BAAANQAECgEIAQABNQAFFAkJJAADADUeAA==.',
Ho='Hocus:BAAANQAECgUICAABNQAFFAYIFgATANwTAA==.Houtoku:BAAANQAECggIFQAAAQ==.Hozi:BAAANQADCgYIBgABNQAECgkJFgANAOUUAA==.Hozina:BAABNQAECn8WAAQNAAkK5RR1NwBpAQANAAYKqhB1NwBpAQAFAAIKtwWz5wBvAAAGAAIKwAUDIgBVAAAAAA==.',
Hu='Huck:BAAANQADCggIDgAAAA==.Hultron:BAAANQADCgIIAgAAAA==.Huntington:BAABNQAECn8fAAMBAAkKBRBpeACxAQABAAkKBRBpeACxAQALAAEKygJAbgApAAAAAA==.',
Im='Imcrying:BAAANQAECgQIBAABNQAFFAYIFgATANwTAA==.Imtrying:BAACNQAFFH8WAAITAAYK3BNZCQC0AQATAAYK3BNZCQC0AQA1AAQKfzUAAxMACgqUIP8ZAAkDABMACgqUIP8ZAAkDABQAAQp/ByoxATgAAAAA.',
Iz='Izuna:BAABNQAECn8jAAIVAAkK5SAJGgC7AgAVAAkK5SAJGgC7AgAAAA==.',
Ja='Jaavere:BAAANQADCgcICwAAAA==.Jayaesir:BAACNQAFFH8HAAIWAAMKChevFwDrAAAWAAMKChevFwDrAAA1AAQKf00AAhYACgrXJXIIALgDABYACgrXJXIIALgDAAAA.Jayal:BAACNQAFFH8QAAIWAAYKgwzlDwBOAQAWAAYKgwzlDwBOAQA1AAQKfzkAAhYACgqKI58bAOsCABYACgqKI58bAOsCAAAA.',
Jo='Johndurgrim:BAACNQAFFH8OAAIXAAUKWRyeBQDWAAAXAAUKWRyeBQDWAAA1AAQKfzsABBcACgqtHzoMANYCABcACgppHzoMANYCABYABQp5G967AEQBABgABQrwDBq+AAABAAE1AAQKBggSAAkAAAAA.Joja:BAAANQAECgEIAgABNQAECggIHAAGAO8VAA==.Jooja:BAABNQAECn8eAAIZAAcKRA9MRwCoAQAZAAcKRA9MRwCoAQABNQAECggIHAAGAO8VAA==.',
Ka='Katbelle:BAACNQAFFH8WAAIaAAYKIQlLAAARAQAaAAYKIQlLAAARAQA1AAQKf0gAAhoACgonHCEBAHoCABoACgonHCEBAHoCAAAA.',
Ke='Keyi:BAAANQAECgEIAQABNQAECggIEgAJAAAAAA==.Keynallan:BAAANQAECgEIAQAAAA==.',
Kh='Khalur:BAAANQAECgIIAwABNQAECggIFQAJAAAAAQ==.',
Ki='Kilan:BAAANQAECgUIBQAAAA==.Kin:BAAANQAECgMIAwABNQAFFAcIHwAYAPckAA==.Kinkykelly:BAABNQAECn8jAAIbAAoKqiDcBgDnAgAbAAoKqiDcBgDnAgABNQAFFAcIFAAOAM0gAA==.Kinkyknight:BAACNQAFFH8UAAIOAAcKzSBoBQAfAgAOAAcKzSBoBQAfAgA1AAQKfy8AAg4ACgpbIncJAO4CAA4ACgpbIncJAO4CAAAA.Kinkypal:BAAANQAFFAEIAQABNQAFFAcIFAAOAM0gAA==.',
Kr='Kreslin:BAAANQAECgQIBQABNQAECgYIEgAJAAAAAA==.Kriista:BAAANQAECgEIAgAAAA==.Krixxus:BAAANQAECggIDQAAAA==.',
Ku='Kuroishi:BAAANQAECgQIBAAAAA==.',
['Kø']='Kø:BAAANQAECgQIAwABNQAECggIKAAcAAobAA==.',
La='Lahar:BAABNQAECn8XAAIBAAkK9xUjPQBMAgABAAkK9xUjPQBMAgABNQAECgoKPgAFAKwlAA==.Lancer:BAAANQAECgMIBAAAAA==.',
Le='Leof:BAACNQAFFH8FAAIOAAUK1RFdDgAAAQAOAAUK1RFdDgAAAQA1AAQKfxwAAg4ACQplFwMXAEACAA4ACQplFwMXAEACAAE1AAQKBggSAAkAAAAA.',
Li='Limptriscuit:BAAANQAECgEIAgAAAA==.Littlelam:BAACNQAFFH8GAAMdAAIKxRnEIABJAAAdAAEKxRnEIABJAAAOAAEKAAAGPgAXAAA1AAQKfxcAAh0ACQp2IFQjALcCAB0ACQp2IFQjALcCAAAA.',
Lo='Locrock:BAAANQAECgYICQAAAA==.Lorkhan:BAAANQAECggIEAAAAA==.Lotti:BAAANQADCgcIDQAAAA==.',
Lt='Ltcclover:BAAANQADCgYIFwAAAA==.',
Lu='Lugren:BAAANQAECgMIBQAAAA==.',
Ly='Lyssandra:BAABNQAECn8eAAIPAAoKvwXMjgB2AQAPAAoKvwXMjgB2AQAAAA==.',
Ma='Madclaw:BAAANQADCgYIBgAAAA==.Magith:BAAANQAECgcIDgAAAA==.Manhattan:BAAANQAECgUICQABNQAFFAgIFgANAJgXAA==.Martini:BAABNQAECn8nAAMKAAkKBSAMHQCRAgAZAAgK1RzEGAC3AgAKAAkK1BsMHQCRAgABNQAFFAgIFgANAJgXAA==.Mayalaran:BAAANQAECgUIDAABNQAECgYIEAAJAAAAAA==.',
Mc='Mccavity:BAABNQAECn9HAAIeAAoKTRWGBQAUAgAeAAoKTRWGBQAUAgABNQABCgQIBAAJAAAAAA==.',
Me='Mekabruti:BAAANQAECgQIBAABNQAECgcIDwAJAAAAAA==.',
Mi='Misticphii:BAAANQADCgYIBgAAAA==.',
Mo='Moocelee:BAAANQADCgYIDAAAAA==.',
Mu='Murc:BAABNQAECn8sAAMdAAkKaxsPMQBqAgAdAAkKaxsPMQBqAgAVAAMK4g2kgwCfAAAAAA==.Murdoch:BAAANQADCggICAAAAA==.',
Na='Na:BAAANQABCgQIBAAAAA==.',
Ne='Nevoir:BAAANQADCgQIBAAAAA==.',
Nh='Nhasgul:BAAANQAECgcIBwABNQABCgIIAgAJAAAAAA==.Nhasraxion:BAACNQAFFH8WAAIXAAYKxBhJAwA2AQAXAAYKxBhJAwA2AQA1AAQKfzIAAxcACgr+INQOAK8CABcACgrgH9QOAK8CABYABQrdGZoQAQMBAAE1AAEKAggCAAkAAAAA.Nhasrezim:BAABNQAECn8YAAIMAAkK+w8QDgBQAQAMAAkK+w8QDgBQAQABNQABCgIIAgAJAAAAAA==.',
Ni='Niceneasy:BAAANQADCgcIDAABNQAECgkJLAAdAGsbAA==.',
No='Nocturnal:BAAANQAECgQIBgAAAA==.Nowaifu:BAAANQAECgUIDQAAAA==.',
Nv='Nvii:BAAANQAECgMIAwAAAA==.',
Or='Ornithogalum:BAAANQADCgUIBgAAAA==.',
Ow='Owlbread:BAAANQAECgcIDwAAAA==.',
Oz='Ozwin:BAAANQAECgEIAgABNQAFFAYIEwAOANwkAA==.',
Pa='Palarin:BAACNQAFFH8fAAMYAAcK9yRDAgDCAgAYAAcK9yRDAgDCAgAWAAMK2B+VFQADAQA1AAQKfzsAAxgACgpTJT8HAJEDABgACgpTJT8HAJEDABYAAwrhHloeAewAAAAA.Pawmi:BAAANQAECgIIBgABNQAECgUIDQAJAAAAAA==.',
Pe='Peccator:BAABNQAECn8+AAIFAAoKrCX7AgC8AwAFAAoKrCX7AgC8AwAAAA==.Persess:BAAANQAECgMIAwAAAA==.',
Pl='Plat:BAABNQAECn8mAAIcAAgKaQ2EGABzAQAcAAgKaQ2EGABzAQAAAA==.Ploo:BAACNQAFFH8JAAIfAAQKNxmgCADfAAAfAAQKNxmgCADfAAA1AAQKfzAAAh8ACgqnIrsHAFMDAB8ACgqnIrsHAFMDAAAA.',
Pu='Punkinhed:BAAANQADCggIDwAAAA==.',
Ra='Rahkor:BAAANQADCgUIBwABNQAECgkJLAAdAGsbAA==.Raveheart:BAABNQAECn8dAAIFAAkKBiDwFgANAwAFAAkKBiDwFgANAwAAAA==.',
Re='Refr:BAACNQAFFH8JAAIUAAUKuhNfEADcAAAUAAUKuhNfEADcAAA1AAQKfzAAAhQACgpLILkZAC8DABQACgpLILkZAC8DAAAA.Renzo:BAAANQAECgYIDAABNQAFFAYIEwAOANwkAA==.',
Rh='Rhaegon:BAAANQADCgcICwAAAA==.',
Ri='Rinslock:BAAANQAECggICAABNQAFFAcIHwAYAPckAA==.Riskante:BAACNQAFFH8IAAMWAAQKVA/HFwDBAAAWAAMKVA/HFwDBAAAYAAIKswjbHgB0AAA1AAQKfzsAAxgACgq6FVZFAFECABgACgq6FVZFAFECABYACQphGbSxALsBAAAA.',
Ro='Roonrana:BAAANQADCgYIDAAAAA==.Rosecake:BAABNQAECn8VAAIEAAkKxgmFFQCEAQAEAAkKxgmFFQCEAQAAAA==.Rosemari:BAAANQAECgQJBwABNQAFFAYIEwAgAEsdAA==.Rosey:BAACNQAFFH8TAAIgAAYKSx1AAABTAQAgAAYKSx1AAABTAQA1AAQKf0wAAiAACgqgIjsBAIcDACAACgqgIjsBAIcDAAAA.Rouge:BAABNQAECn8XAAMKAAkK6BwWEQBuAgAKAAcKOiAWEQBuAgAZAAMKzBTufwC0AAAAAA==.',
Ru='Runebraker:BAAANQAECgcIEAAAAA==.',
Sa='Sardor:BAABNQAECn8aAAMCAAoKGxcADwC/AgACAAoKGxcADwC/AgAQAAYKrxzWGQDaAQABNQAFFAYIEwAOANwkAA==.',
Sc='Scottyno:BAACNQAFFH8GAAIWAAIKDQrzJgBtAAAWAAIKDQrzJgBtAAA1AAQKfzwAAhYACgqsGY1rAFsCABYACgqsGY1rAFsCAAAA.',
Se='Senarria:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclaw:BAAANQADCgYICwAAAA==.Shanithell:BAAANQAECgQIAwAAAA==.Shanksz:BAAANQADCgIIAgAAAA==.Shellyd:BAAANQAECgEIAQAAAA==.',
Si='Siennaa:BAAANQADCgIIAgAAAA==.Sierra:BAAANQAECgQIBAAAAA==.Sinfulsmite:BAAANQAECgcIDwAAAA==.',
Sk='Skark:BAAANQAECgIIAwAAAA==.',
Sl='Sleifer:BAAANQAECgQJCwAAAA==.Slothy:BAABNQAECn8pAAMhAAoK2hZHWQBLAgAhAAoK2xVHWQBLAgAiAAIKERu8UACNAAAAAA==.',
Sn='Sneakyhand:BAACNQAFFH8WAAIIAAYKeiERCgCPAQAIAAYKeiERCgCPAQA1AAQKfzUAAwgACgp/JpkJAKcDAAgACgp/JpkJAKcDAAcAAQqhGTVBADoAAAAA.',
Sp='Spicyretort:BAAANQADCgYIBgAAAA==.',
St='Starling:BAAANQAECgYIEAAAAA==.Stew:BAABNQAECn8YAAIjAAcKRwY1XwACAQAjAAcKRwY1XwACAQABNQAECggIHAAGAO8VAA==.',
Sy='Sylvi:BAAANQAECggIEAAAAA==.',
Ta='Takitsu:BAAANQAECgEIAQAAAA==.',
Th='Tharion:BAAANQAECgcIDwAAAA==.',
Ti='Tinytoes:BAAANQAECgIIAwAAAA==.Tired:BAABNQAECn8oAAIcAAgKChuFDADpAQAcAAgKChuFDADpAQAAAA==.Tish:BAAANQAECggIEwABNQAECgYIEgAJAAAAAA==.',
To='Tomn:BAAANQADCggIDgAAAA==.Towa:BAACNQAFFH8TAAIjAAYKtQvyCgD+AAAjAAYKtQvyCgD+AAA1AAQKf0kAAwwACgp+G3IOANMBACMACgqlFk4oAFwCAAwACApsHHIOANMBAAAA.',
Tr='Trater:BAEANQADCgMIAwAAAA==.',
Va='Vaskie:BAECNQAFFH8SAAIIAAYKexQ3DABmAQAIAAYKexQ3DABmAQA1AAQKf0wAAggACgr+IncTAG4DAAgACgr+IncTAG4DAAAA.',
Ve='Veil:BAAANQADCgYICAABNQAECgkJFwAKAOgcAA==.Velenar:BAAANQAECgQIBAABNQAFFAYIEwAOANwkAA==.Vella:BAABNQAECn8UAAIiAAkKTRbvBwCDAgAiAAkKTRbvBwCDAgAAAA==.',
Vo='Vooduel:BAAANQAECgcICAAAAA==.',
Vy='Vyra:BAABNQAECn8hAAIWAAkKeQlDtQBQAQAWAAkKeQlDtQBQAQAAAA==.',
Wa='Wallê:BAAANQADCgYIBgAAAA==.',
We='Wetasscat:BAABNQAECn8UAAMhAAkK1xjNYwAuAgAhAAkK1xjNYwAuAgAiAAEKkhetbQBDAAAAAA==.',
Wo='Wotardag:BAAANQADCgcJDQAAAA==.',
Xa='Xandris:BAAANQAECgEIAQAAAA==.Xavierr:BAAANQABCgIIAgAAAA==.',
Yo='Yorinn:BAABNQAECn8XAAIkAAgKQhbUDwADAgAkAAgKQhbUDwADAgABNQAFFAYIEwAOANwkAA==.',
Ys='Ysayle:BAAANQAECgEJBQABNQAECgUIDQAJAAAAAA==.',
Yu='Yucky:BAAANQAECgUICgABNQAECgYICwAJAAAAAA==.',
Za='Zaht:BAAANQAECgUIBwAAAA==.Zargus:BAAANQAECgEIAQAAAA==.',
Ze='Zetsuon:BAABNQAECn8/AAICAAoKPB1IEwB9AgACAAoKPB1IEwB9AgAAAA==.',
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
