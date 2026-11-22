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
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adarlaliiana:BAAANQAECgQIDgAAAA==.',
Ap='Aphillion:BAAANQAECgEIAQAAAA==.',
Ar='Arator:BAAANQADCgMIAwAAAA==.Arcadius:BAAANQADCgUICQAAAA==.',
At='Athenia:BAAANQAECgEIAQAAAA==.',
Ax='Axél:BAAANQADCgcIDQAAAA==.',
Az='Azarathia:BAAANQADCgEIAQAAAA==.',
Ba='Barbaria:BAABNQAECn8XAAIBAAgKARTZkQCSAQABAAgKARTZkQCSAQAAAA==.Bastas:BAABNQAECn8fAAICAAkKAAp+LgCnAQACAAkKAAp+LgCnAQAAAA==.',
Be='Beekro:BAACNQAFFH8TAAIDAAcKTQsGBgBNAQADAAcKTQsGBgBNAQA1AAQKfzkAAwMACgqVHqkDAO0CAAMACgqVHqkDAO0CAAQAAQp8BGw+ACYAAAAA.Beladentata:BAAANQAECgYIDAABNQAFFAcIFwAFANcVAA==.Belarina:BAAANQAECgcICgABNQAFFAcIFwAFANcVAA==.Belaspark:BAAANQAECgcIBwABNQAFFAcIFwAFANcVAA==.Belated:BAAANQAECgcIBwAAAA==.Belatink:BAACNQAFFH8XAAIFAAcK1xX1CAAyAgAFAAcK1xX1CAAyAgA1AAQKf24AAwUACgqLJAEFAOMDAAUACgqLJAEFAOMDAAYAAwonC7sbAIkAAAAA.Bernocke:BAAANQAECgUIBQAAAA==.',
Bi='Bilando:BAABNQAECn8XAAMHAAkKgRNbHAB3AQAIAAkKgw5CrwCnAQAHAAYK0hZbHAB3AQAAAA==.',
Bl='Bludlust:BAAANQAECgUIBQAAAA==.Blueberry:BAACNQAFFH8XAAIFAAcKTCC6BQCcAgAFAAcKTCC6BQCcAgA1AAQKfzUAAwUACgoBJIIPAF8DAAUACgp5IIIPAF8DAAYABwqsIQcEAJgCAAAA.',
Bo='Bonezthug:BAABNQAECn8cAAMGAAgK7xVSCgClAQAFAAcK6A4GeQCwAQAGAAYKlhZSCgClAQAAAA==.Borden:BAAANQAECggIDgAAAA==.',
Ca='Calaart:BAAANQAECgEIAQAAAA==.',
Ch='Chainer:BAABNQAECn9FAAIBAAoKdhiFPwBXAgABAAoKdhiFPwBXAgAAAA==.',
Cl='Clubsandwich:BAAANQAECgEIAgAAAA==.',
Da='Dacker:BAAANQABCgEIAQAAAA==.Daelen:BAAANQAECgYIBgABNQAECggIEAAJAAAAAQ==.Darthvolo:BAAANQAECgEIAQAAAA==.',
De='Deftones:BAAANQAECgQIBAAAAA==.Demonveil:BAAANQADCgYIBgABNQAECgkJFwAKAOgcAA==.Derina:BAAANQADCgcIBAAAAA==.',
Do='Dolt:BAAANQAECgQIBwAAAA==.Domiati:BAAANQADCgYIBgAAAA==.',
Dr='Drezzarnbez:BAAANQAECgEIAQAAAA==.Drvoidberg:BAAANQAECgYICwAAAA==.',
Du='Durgrim:BAAANQAECgcIEAAAAA==.',
Ee='Eeèva:BAAANQADCgYJCgAAAA==.',
El='Electrabuzz:BAAANQAECgEIAQAAAA==.Ellanaras:BAAANQAECggIDQAAAA==.',
Em='Emi:BAAANQADCggIGAAAAA==.',
Ep='Epoxxy:BAAANQAECggIBQAAAA==.',
Er='Erzkal:BAABNQAFFH8JAAMLAAUKdgnKEgATAQALAAUKiwTKEgATAQABAAMK4QzdHwC0AAABNQAECggIFwAMAJEiAA==.',
Es='Espresso:BAACNQAFFH8WAAINAAgKmBcjBAASAgANAAgKmBcjBAASAgA1AAQKf0IAAg0ACgp/Jd0BAG0DAA0ACgp/Jd0BAG0DAAAA.',
Fi='Finkregh:BAAANQAECgMIAwAAAA==.',
Fo='Foxme:BAAANQADCgIIAgAAAA==.',
Ga='Gaartak:BAACNQAFFH8TAAIOAAYK3CQtCQCQAQAOAAYK3CQtCQCQAQA1AAQKf0cAAg4ACgo0JpUAAPQDAA4ACgo0JpUAAPQDAAAA.Garren:BAABNQAECn8aAAIPAAYKzwzQHwFXAQAPAAYKzwzQHwFXAQAAAA==.',
Gi='Giantcow:BAAANQAECgMIAwAAAA==.Gith:BAACNQAFFH8QAAIBAAUKDAxMDQAjAQABAAUKDAxMDQAjAQA1AAQKfyoAAgEACgoAGydAAKoCAAEACgoAGydAAKoCAAAA.Githlock:BAAANQAECgMIBAABNQAFFAUIEAABAAwMAA==.Githon:BAABNQAECn8jAAQCAAgK0A1VNwA9AQACAAgK0A1VNwA9AQAQAAYKaw+PMwAGAQARAAQKzwyOfwDQAAABNQAFFAUIEAABAAwMAA==.',
Gl='Glittercakes:BAAANQAECgEIAQAAAA==.',
Gr='Grogrin:BAACNQAFFH8TAAISAAYKVA7WAAAaAQASAAYKVA7WAAAaAQA1AAQKf0YAAhIACgpxIaMCAPsCABIACgpxIaMCAPsCAAAA.',
Ha='Halordric:BAAANQAECgEIAQABNQAECgUIBgAJAAAAAA==.',
He='Hekate:BAAANQADCggICgAAAA==.Heyblinkin:BAAANQAECgUIBQAAAA==.',
Hi='Hitmonlee:BAAANQADCggICAABNQAFFAkJJAADADUeAA==.',
Ho='Hocus:BAAANQAECgUIBgABNQAFFAcIFwATAAcVAA==.Houtoku:BAAANQAECggIEAAAAQ==.Hozi:BAAANQADCgYIBgABNQAECgkJFgANAOUUAA==.Hozina:BAABNQAECn8WAAQNAAkK5RR1NwBpAQANAAYKqhB1NwBpAQAFAAIKtwWz5wBvAAAGAAIKwAUDIgBVAAAAAA==.',
Hu='Huck:BAAANQADCggIDgAAAA==.Hultron:BAAANQADCgIIAgAAAA==.Huntington:BAABNQAECn8fAAMBAAkKBRBBhQCuAQABAAkKBRBBhQCuAQALAAEKygLxcgApAAAAAA==.',
Im='Imcrying:BAAANQAECgQIBAABNQAFFAcIFwATAAcVAA==.Imtrying:BAACNQAFFH8XAAITAAcKBxXEBwAKAgATAAcKBxXEBwAKAgA1AAQKfzYAAxMACgqUIP8ZAAkDABMACgqUIP8ZAAkDABQAAQp/ByoxATgAAAAA.',
Iz='Izuna:BAABNQAECn8jAAIVAAkK5SAJGgC7AgAVAAkK5SAJGgC7AgAAAA==.',
Ja='Jaavere:BAAANQADCgcICwAAAA==.Jayaesir:BAACNQAFFH8HAAIWAAMKChevFwDrAAAWAAMKChevFwDrAAA1AAQKf04AAhYACgrXJXIIALgDABYACgrXJXIIALgDAAAA.Jayal:BAACNQAFFH8QAAIWAAYKgwzlDwBOAQAWAAYKgwzlDwBOAQA1AAQKfzkAAhYACgqKI4cgAN8CABYACgqKI4cgAN8CAAAA.',
Jo='Johndurgrim:BAACNQAFFH8OAAIXAAUKWRxtBgDTAAAXAAUKWRxtBgDTAAA1AAQKf0MABBcACgqtHzoMANYCABcACgppHzoMANYCABYABwrEF4+MALMBABgABgo1FKydAOcAAAE1AAQKBwgQAAkAAAAA.Jooja:BAABNQAECn8eAAIZAAcKRA9MRwCoAQAZAAcKRA9MRwCoAQABNQAECggIHAAGAO8VAA==.',
Ka='Katbelle:BAACNQAFFH8XAAIaAAcKUAhAAABMAQAaAAcKUAhAAABMAQA1AAQKf0kAAhoACgonHEMBAHkCABoACgonHEMBAHkCAAAA.',
Ke='Keyi:BAAANQADCggICAABNQAECgoKHQATACIZAA==.Keynallan:BAAANQADCggIEQAAAA==.',
Kh='Khalur:BAAANQAECggICAABNQAECggIEAAJAAAAAQ==.',
Ki='Kilan:BAAANQAECgUIBQAAAA==.Kin:BAAANQAECgMIAwABNQAFFAgIIAAYAHojAA==.Kinkykelly:BAABNQAECn8jAAIbAAoKqiC7BwDfAgAbAAoKqiC7BwDfAgABNQAFFAcIFAAOAM0gAA==.Kinkyknight:BAACNQAFFH8UAAIOAAcKzSBoBQAfAgAOAAcKzSBoBQAfAgA1AAQKfy8AAg4ACgpbInQKAOgCAA4ACgpbInQKAOgCAAAA.Kinkypal:BAAANQAFFAEIAQABNQAFFAcIFAAOAM0gAA==.',
Kr='Kreslin:BAAANQAECgQIBAABNQAECgcIEAAJAAAAAA==.Kriista:BAAANQAECgEIAgAAAA==.Krixxus:BAAANQAECggIEAAAAA==.',
Ku='Kuroishi:BAAANQAECgQIBAAAAA==.',
['Kø']='Kø:BAAANQAECgQIAwABNQAECggIKAAcAAobAA==.',
La='Lahar:BAABNQAECn8XAAIBAAkK9xVuRQBIAgABAAkK9xVuRQBIAgABNQAECgoKPgAFAKwlAA==.Lancer:BAAANQAECgMIAwAAAA==.',
Le='Leof:BAACNQAFFH8FAAIOAAUK1REUEQD2AAAOAAUK1REUEQD2AAA1AAQKfx0AAg4ACQrQF1YYAEMCAA4ACQrQF1YYAEMCAAE1AAQKBwgQAAkAAAAA.',
Li='Limptriscuit:BAAANQAECgEIAQAAAA==.Littlelam:BAACNQAFFH8GAAMdAAIKxRnEIABJAAAdAAEKxRnEIABJAAAOAAEKAAAGPgAXAAA1AAQKfxcAAh0ACQp2IFQjALcCAB0ACQp2IFQjALcCAAAA.',
Lo='Locrock:BAAANQAECgYICAAAAA==.Lorkhan:BAAANQAECggIDgAAAA==.Lotti:BAAANQADCgcIDQAAAA==.',
Lt='Ltcclover:BAAANQADCgYIFwAAAA==.',
Lu='Lugren:BAAANQAECgMIBAAAAA==.',
Ly='Lyssandra:BAABNQAECn8kAAIPAAoKpwZejQCLAQAPAAoKpwZejQCLAQAAAA==.',
Ma='Madclaw:BAAANQADCgYIBgAAAA==.Magith:BAAANQAECgcIDAAAAA==.Manhattan:BAAANQAECgUICAABNQAFFAgIFgANAJgXAA==.Martini:BAABNQAECn8nAAMKAAkKBSDyHwCOAgAZAAgK1RzEGAC3AgAKAAkK1BvyHwCOAgABNQAFFAgIFgANAJgXAA==.Mayalaran:BAAANQAECgYIDQABNQAECgYIDQAJAAAAAA==.',
Mc='Mccavity:BAABNQAECn9HAAIeAAoKTRVXBgANAgAeAAoKTRVXBgANAgABNQABCgQIBAAJAAAAAA==.',
Me='Mekabruti:BAAANQAECgQIBAABNQAECgcIDwAJAAAAAA==.',
Mi='Misticphii:BAAANQADCgYIBgAAAA==.',
Mo='Moocelee:BAAANQADCgYIDAAAAA==.',
Mu='Murc:BAABNQAECn8sAAMdAAkKaxsPMQBqAgAdAAkKaxsPMQBqAgAVAAMK4g2kgwCfAAAAAA==.Murdoch:BAAANQADCggICAAAAA==.',
Na='Na:BAAANQABCgQIBAAAAA==.',
Ne='Nevoir:BAAANQADCgQIBAAAAA==.',
Nh='Nhasgul:BAAANQAECgcIBgABNQABCgIIAgAJAAAAAA==.Nhasraxion:BAACNQAFFH8XAAIXAAcKFRpxAgCRAQAXAAcKFRpxAgCRAQA1AAQKfzMAAxcACgoUIdQOAK8CABcACgr2H9QOAK8CABYABQrdGZoQAQMBAAE1AAEKAggCAAkAAAAA.Nhasrezim:BAABNQAECn8YAAIMAAkK+w9oDwBQAQAMAAkK+w9oDwBQAQABNQABCgIIAgAJAAAAAA==.',
Ni='Niceneasy:BAAANQADCgcIDAABNQAECgkJLAAdAGsbAA==.',
No='Nocturnal:BAAANQAECgMIBQAAAA==.Nowaifu:BAAANQAECgUICAAAAA==.',
Nv='Nvii:BAAANQAECgMIAwAAAA==.',
Or='Ornithogalum:BAAANQADCgUIBgAAAA==.',
Ow='Owlbread:BAAANQAECggIDgAAAA==.',
Oz='Ozwin:BAAANQAECgEIAQABNQAFFAYIEwAOANwkAA==.',
Pa='Palarin:BAACNQAFFH8gAAMYAAgKeiO4AQAVAwAYAAgKeiO4AQAVAwAWAAMK2B+VFQADAQA1AAQKfzsAAxgACgpTJT8HAJEDABgACgpTJT8HAJEDABYAAwrhHloeAewAAAAA.Pawmi:BAAANQAECgIIBAABNQAECgUICAAJAAAAAA==.',
Pe='Peccator:BAABNQAECn8+AAIFAAoKrCX7AgC8AwAFAAoKrCX7AgC8AwAAAA==.Persess:BAAANQAECgMIAwAAAA==.',
Pl='Plat:BAABNQAECn8tAAIcAAkKWA66FwBbAQAcAAkKWA66FwBbAQAAAA==.Platspriest:BAAANQAECgEIAQAAAA==.Ploo:BAACNQAFFH8JAAIfAAQKNxnKCQDaAAAfAAQKNxnKCQDaAAA1AAQKfzAAAh8ACgqnIrsHAFMDAB8ACgqnIrsHAFMDAAAA.',
Pu='Punkinhed:BAAANQADCggIDwAAAA==.',
Ra='Rahkor:BAAANQADCgUIBwABNQAECgkJLAAdAGsbAA==.Raveheart:BAABNQAECn8dAAIFAAkKBiCCGgAEAwAFAAkKBiCCGgAEAwAAAA==.',
Re='Refr:BAACNQAFFH8JAAIUAAUKuhNOEgDbAAAUAAUKuhNOEgDbAAA1AAQKfzAAAhQACgpLILkZAC8DABQACgpLILkZAC8DAAAA.Renzo:BAAANQAECgYICQABNQAFFAYIEwAOANwkAA==.',
Rh='Rhaegon:BAAANQADCgcICwAAAA==.',
Ri='Rinslock:BAAANQAECggICAABNQAFFAgIIAAYAHojAA==.Riskante:BAACNQAFFH8IAAMWAAQKVA/aGgC+AAAWAAMKVA/aGgC+AAAYAAIKswg1IQB0AAA1AAQKf0EAAxgACgq6FVZFAFECABgACgq6FVZFAFECABYACQptHw1cABwCAAAA.',
Ro='Roonrana:BAAANQADCgYIDAAAAA==.Rosecake:BAAANQAECggIEQAAAA==.Rosemari:BAAANQAECgQJBQABNQAFFAYIEwAgAEsdAA==.Rosey:BAACNQAFFH8TAAIgAAYKSx1NAABMAQAgAAYKSx1NAABMAQA1AAQKf1UAAiAACgqgIjsBAIcDACAACgqgIjsBAIcDAAAA.Rouge:BAABNQAECn8XAAMKAAkK6BwWEQBuAgAKAAcKOiAWEQBuAgAZAAMKzBTufwC0AAAAAA==.',
Ru='Runebraker:BAAANQAECgcIEAAAAA==.',
Sa='Sardor:BAABNQAECn8iAAMCAAoKGxe4EAC8AgACAAoKGxe4EAC8AgAQAAgKnBrWGQDaAQABNQAFFAYIEwAOANwkAA==.',
Sc='Scottyno:BAACNQAFFH8HAAIWAAIKcwrMKQBxAAAWAAIKcwrMKQBxAAA1AAQKf0AAAhYACgqsGY1rAFsCABYACgqsGY1rAFsCAAAA.',
Se='Senarria:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclaw:BAAANQADCgYICwAAAA==.Shanithell:BAAANQAECgQIAwAAAA==.Shanksz:BAAANQADCgIIAgAAAA==.Shellyd:BAAANQAECgEIAQAAAA==.',
Si='Siennaa:BAAANQADCgIIAgAAAA==.Sierra:BAAANQAECgQIBAAAAA==.Sinfulsmite:BAAANQAECgcIDwAAAA==.',
Sk='Skark:BAAANQAECgIIAwAAAA==.',
Sl='Sleifer:BAAANQAECgQICQAAAA==.Slothy:BAABNQAECn8pAAMhAAoK2hZHWQBLAgAhAAoK2xVHWQBLAgAiAAIKERu8UACNAAAAAA==.',
Sn='Sneakyhand:BAACNQAFFH8XAAIIAAcK+yHtBwD0AQAIAAcK+yHtBwD0AQA1AAQKfzYAAwgACgp/JpkJAKcDAAgACgp/JpkJAKcDAAcAAQqhGTVBADoAAAAA.',
Sp='Spicyretort:BAAANQADCgYIBgAAAA==.',
St='Starling:BAAANQAECgYIDQAAAA==.Stew:BAABNQAECn8YAAIjAAcKRwY1XwACAQAjAAcKRwY1XwACAQABNQAECggIHAAGAO8VAA==.',
Sy='Sylvi:BAAANQAECggIDwAAAA==.',
Ta='Takitsu:BAAANQAECgEIAQAAAA==.',
Th='Tharion:BAABNQAECn8WAAIEAAgKbB6ODwASAgAEAAgKbB6ODwASAgAAAA==.',
Ti='Tinytoes:BAAANQAECgIIAgAAAA==.Tired:BAABNQAECn8oAAIcAAgKChtfDgDkAQAcAAgKChtfDgDkAQAAAA==.Tish:BAAANQAECggIEQABNQAECgcIEAAJAAAAAA==.',
To='Tomn:BAAANQADCggIDgAAAA==.Towa:BAACNQAFFH8TAAIjAAYKtQurDAD9AAAjAAYKtQurDAD9AAA1AAQKf0oAAwwACgp+G3IOANMBACMACgqlFk4oAFwCAAwACApsHHIOANMBAAAA.',
Tr='Trater:BAEANQADCgMIAwAAAA==.',
Va='Vaskie:BAECNQAFFH8SAAIIAAYKexTsDgBaAQAIAAYKexTsDgBaAQA1AAQKf0wAAggACgr+IncTAG4DAAgACgr+IncTAG4DAAAA.',
Ve='Veil:BAAANQADCgYICAABNQAECgkJFwAKAOgcAA==.Velenar:BAAANQAECgQIBAABNQAFFAYIEwAOANwkAA==.Vella:BAABNQAECn8UAAIiAAkKTRbvBwCDAgAiAAkKTRbvBwCDAgAAAA==.',
Vo='Vooduel:BAAANQAECgcIBwAAAA==.',
Vy='Vyra:BAABNQAECn8kAAIWAAoKCAr4pACEAQAWAAoKCAr4pACEAQAAAA==.',
Wa='Wallê:BAAANQADCgYIBgAAAA==.',
We='Wetasscat:BAABNQAECn8UAAMhAAkK1xjNYwAuAgAhAAkK1xjNYwAuAgAiAAEKkhetbQBDAAAAAA==.',
Wo='Wotardag:BAAANQADCgcJDQAAAA==.',
Xa='Xavierr:BAAANQABCgIIAgAAAA==.',
Yo='Yorinn:BAABNQAECn8aAAIkAAkKGxbwDABHAgAkAAkKGxbwDABHAgABNQAFFAYIEwAOANwkAA==.',
Ys='Ysayle:BAAANQAECgEJAgABNQAECgUICAAJAAAAAA==.',
Yu='Yucky:BAAANQAECgYICAAAAA==.',
Za='Zaht:BAAANQAECgUIBgAAAA==.Zargus:BAAANQAECgEIAQAAAA==.',
Ze='Zetsuon:BAABNQAECn9BAAICAAoKeh6lEgCfAgACAAoKeh6lEgCfAgAAAA==.',
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
