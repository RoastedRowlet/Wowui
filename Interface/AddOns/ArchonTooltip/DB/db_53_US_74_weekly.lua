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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Warrior-Protection','Warrior-Arms','Unknown-Unknown','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Blood','Mage-Arcane','Druid-Guardian','Druid-Balance','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Rogue-Assassination','Mage-Fire','DemonHunter-Devourer','Druid-Feral','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adarlaliiana:BAAANQAECgQIDgAAAA==.',
Ap='Aphillion:BAAANQAECgEIAQAAAA==.',
Ar='Arator:BAAANQADCgMIAwAAAA==.Arcadius:BAAANQADCgUICQAAAA==.',
At='Athenia:BAAANQAECgEIAQAAAA==.',
Ax='Axél:BAAANQADCgcIDQAAAA==.',
Az='Azarathia:BAAANQADCgEIAQAAAA==.',
Ba='Barbaria:BAABNQAECn8WAAIBAAcKZBQakwBHAQABAAcKZBQakwBHAQAAAA==.Bastas:BAABNQAECn8fAAICAAkKAAp+LgCnAQACAAkKAAp+LgCnAQAAAA==.',
Be='Beekro:BAACNQAFFH8SAAIDAAYKyAsmBQARAQADAAYKyAsmBQARAQA1AAQKfzAAAgMACgq5HKkDAO0CAAMACgq5HKkDAO0CAAAA.Beladentata:BAAANQAECgYIDAABNQAFFAYIFgAEAEcXAA==.Belarina:BAAANQAECgcICgABNQAFFAYIFgAEAEcXAA==.Belated:BAAANQAECgcICQAAAA==.Belatink:BAACNQAFFH8WAAIEAAYKRxcTCADvAQAEAAYKRxcTCADvAQA1AAQKf2EAAwQACgpVJK8DAOYDAAQACgpVJK8DAOYDAAUAAwonC7sbAIkAAAAA.Bernocke:BAAANQAECgUIBQAAAA==.',
Bi='Bilando:BAABNQAECn8XAAMGAAkKgRNbHAB3AQAHAAkKgw5CrwCnAQAGAAYK0hZbHAB3AQAAAA==.',
Bl='Bludlust:BAAANQAECgUIBQAAAA==.Blueberry:BAACNQAFFH8WAAIEAAYKdSG1BABOAgAEAAYKdSG1BABOAgA1AAQKfzMAAwQACgoBJNcJAHoDAAQACgp5INcJAHoDAAUABwqsIQcEAJgCAAAA.',
Bo='Bonezthug:BAABNQAECn8cAAMFAAgK7xVSCgClAQAEAAcK6A4GeQCwAQAFAAYKlhZSCgClAQAAAA==.Borden:BAAANQAECgcIDgAAAA==.',
Ca='Calaart:BAAANQAECgEIAQAAAA==.',
Ch='Chainer:BAABNQAECn8wAAIBAAoKJBb2TACHAgABAAoKJBb2TACHAgAAAA==.',
Cl='Clubsandwich:BAAANQAECgEIAgAAAA==.',
Da='Dacker:BAAANQAECgEIAwAAAA==.Daelen:BAAANQAECgIIBAABNQAECggIEgAIAAAAAQ==.Darthvolo:BAAANQAECgEIAQAAAA==.',
De='Deftones:BAAANQAECgQIBAAAAA==.Demonveil:BAAANQADCgYIBgABNQAECgkJFwAJAOgcAA==.',
Do='Dolt:BAAANQAECgQIBwAAAA==.Domiati:BAAANQADCgYIBgAAAA==.',
Dr='Drezzarnbez:BAAANQAECgEIAQAAAA==.Drvoidberg:BAAANQAECgYICwAAAA==.',
Du='Durgrim:BAAANQAECgYIEAAAAA==.',
Ee='Eeèva:BAAANQADCgYJCgAAAA==.',
El='Electrabuzz:BAAANQADCgMIAwAAAA==.Ellanaras:BAAANQAECggIDQAAAA==.',
Em='Emi:BAAANQADCggIGAAAAA==.',
Ep='Epoxxy:BAAANQAECgUIBgAAAA==.',
Er='Erzkal:BAABNQAFFH8JAAMKAAUKdgnKEgATAQAKAAUKiwTKEgATAQABAAMK4QzdHwC0AAABNQAECggIFwALAJEiAA==.',
Es='Espresso:BAACNQAFFH8UAAIMAAcKbxkjBAASAgAMAAcKbxkjBAASAgA1AAQKf0EAAgwACgp7JW8BAG8DAAwACgp7JW8BAG8DAAAA.',
Fo='Foxme:BAAANQADCgIIAgAAAA==.',
Ga='Gaartak:BAACNQAFFH8TAAINAAYK3CQBBQCfAQANAAYK3CQBBQCfAQA1AAQKf0AAAg0ACgoYJpUAAPQDAA0ACgoYJpUAAPQDAAAA.Garren:BAABNQAECn8aAAIOAAYKzwzQHwFXAQAOAAYKzwzQHwFXAQAAAA==.',
Gi='Giantcow:BAAANQAECgMIAwAAAA==.Gith:BAACNQAFFH8QAAIBAAUKDAw6CQAqAQABAAUKDAw6CQAqAQA1AAQKfyUAAgEACgpvGidAAKoCAAEACgpvGidAAKoCAAAA.Githlock:BAAANQAECgMIBAABNQAFFAUIEAABAAwMAA==.Githon:BAABNQAECn8cAAQCAAcKsQ6zPQA2AQACAAcKsQ6zPQA2AQAPAAYKBAuPMwAGAQAQAAQKzwyOfwDQAAABNQAFFAUIEAABAAwMAA==.',
Gl='Glittercakes:BAAANQAECgEIAQAAAA==.',
Gr='Griselbrand:BAAANQAECgUIAQAAAA==.Grogrin:BAACNQAFFH8TAAIRAAYKVA6HAAAlAQARAAYKVA6HAAAlAQA1AAQKf0EAAhEACgo/ICYCAPECABEACgo/ICYCAPECAAAA.',
Ha='Halordric:BAAANQAECgEIAQABNQAECgUIBgAIAAAAAA==.',
He='Hekate:BAAANQADCggICgAAAA==.Heyblinkin:BAAANQAECgUIBQAAAA==.',
Hi='Hitmonlee:BAAANQADCggICAABNQAFFAgIIgADAMQiAA==.',
Ho='Hocus:BAAANQAECgUIBgABNQAFFAYIFgASANwTAA==.Houtoku:BAAANQAECggIEgAAAQ==.Hozi:BAAANQADCgYIBgABNQAECgkJFgAMAOUUAA==.Hozina:BAABNQAECn8WAAQMAAkK5RR1NwBpAQAMAAYKqhB1NwBpAQAEAAIKtwWz5wBvAAAFAAIKwAUDIgBVAAAAAA==.',
Hu='Huck:BAAANQADCggIDgAAAA==.Hultron:BAAANQADCgIIAgAAAA==.Huntington:BAABNQAECn8bAAIBAAgKVxB+ggBsAQABAAgKVxB+ggBsAQAAAA==.',
Im='Imcrying:BAAANQAECgQIBAABNQAFFAYIFgASANwTAA==.Imtrying:BAACNQAFFH8WAAISAAYK3BM4BwC4AQASAAYK3BM4BwC4AQA1AAQKfzQAAxIACgqUIP8ZAAkDABIACgqUIP8ZAAkDABMAAQp/ByoxATgAAAAA.',
Iz='Izuna:BAABNQAECn8jAAIUAAkK5SAJGgC7AgAUAAkK5SAJGgC7AgAAAA==.',
Ja='Jaavere:BAAANQADCgcICwAAAA==.Jayaesir:BAACNQAFFH8HAAIVAAMKChevFwDrAAAVAAMKChevFwDrAAA1AAQKf0oAAhUACgp7JXIIALgDABUACgp7JXIIALgDAAAA.Jayal:BAACNQAFFH8PAAIVAAUKFA7lDwBOAQAVAAUKFA7lDwBOAQA1AAQKfzgAAhUACgqKIyIVAPkCABUACgqKIyIVAPkCAAAA.',
Jo='Johndurgrim:BAACNQAFFH8OAAIWAAUKWRzFBADZAAAWAAUKWRzFBADZAAA1AAQKfzYABBYACgppHzoMANYCABYACgppHzoMANYCABcABQrwDBq+AAABABUAAQoAACKIAU8AAAE1AAQKBggQAAgAAAAA.Jooja:BAABNQAECn8eAAIYAAcKRA9MRwCoAQAYAAcKRA9MRwCoAQABNQAECggIHAAFAO8VAA==.',
Ka='Katbelle:BAACNQAFFH8WAAIZAAYKIQk5AAAZAQAZAAYKIQk5AAAZAQA1AAQKfz8AAhkACgoTHAwBAGYCABkACgoTHAwBAGYCAAAA.',
Ke='Keyi:BAAANQADCggICAABNQAECggIEgAIAAAAAA==.Keynallan:BAAANQADCggIEQAAAA==.',
Kh='Khalur:BAAANQAECgIIAwABNQAECggIEgAIAAAAAQ==.',
Ki='Kilan:BAAANQAECgUIBQAAAA==.Kin:BAAANQAECgMIAwABNQAFFAcIHwAXAPckAA==.Kinkykelly:BAABNQAECn8gAAIaAAoKqiCRBQD0AgAaAAoKqiCRBQD0AgABNQAFFAYIEwANAC0gAA==.Kinkyknight:BAACNQAFFH8TAAINAAYKLSBoBQAfAgANAAYKLSBoBQAfAgA1AAQKfy4AAg0ACgpbIg0IAPcCAA0ACgpbIg0IAPcCAAAA.Kinkypal:BAAANQAFFAEIAQABNQAFFAYIEwANAC0gAA==.',
Kr='Kreslin:BAAANQAECgQIBAABNQAECgYIEAAIAAAAAA==.Kriista:BAAANQAECgEIAQAAAA==.Krixxus:BAAANQAECggICQAAAA==.',
Ku='Kuroishi:BAAANQAECgQIBAAAAA==.',
['Kø']='Kø:BAAANQAECgQIAwABNQAECggIJwAbAAUbAA==.',
La='Lahar:BAAANQAECggIEwABNQAECgoKPgAEAKwlAA==.Lancer:BAAANQAECgMIAwAAAA==.',
Le='Leof:BAACNQAFFH8FAAINAAUK1RG1CwAEAQANAAUK1RG1CwAEAQA1AAQKfxgAAg0ACQpNFXoYABgCAA0ACQpNFXoYABgCAAE1AAQKBggQAAgAAAAA.',
Li='Limptriscuit:BAAANQAECgEIAQAAAA==.Littlelam:BAACNQAFFH8GAAMcAAIKxRnEIABJAAAcAAEKxRnEIABJAAANAAEKAAAGPgAXAAA1AAQKfxcAAhwACQp2IFQjALcCABwACQp2IFQjALcCAAAA.',
Lo='Locrock:BAAANQAECgYICAAAAA==.Lorkhan:BAAANQAECggIDgAAAA==.Lotti:BAAANQADCgcIDQAAAA==.',
Lt='Ltcclover:BAAANQADCgYIFwAAAA==.',
Lu='Lugren:BAAANQAECgMIBAAAAA==.',
Ly='Lyssandra:BAABNQAECn8UAAIOAAkK2gRorgAdAQAOAAkK2gRorgAdAQAAAA==.',
Ma='Madclaw:BAAANQADCgYIBgAAAA==.Magith:BAAANQAECgcIDAAAAA==.Malgan:BAAANQAECgIIAgABNQAECggIEgAIAAAAAQ==.Manhattan:BAAANQAECgUICAABNQAFFAcIFAAMAG8ZAA==.Martini:BAABNQAECn8nAAMJAAkKBSAXGQCQAgAYAAgK1RzEGAC3AgAJAAkK1BsXGQCQAgABNQAFFAcIFAAMAG8ZAA==.Mayalaran:BAAANQAECgUIDAABNQAECgYIDQAIAAAAAA==.',
Mc='Mccavity:BAABNQAECn9GAAIdAAoKTRUjBAAiAgAdAAoKTRUjBAAiAgABNQABCgQIBAAIAAAAAA==.',
Me='Mekabruti:BAAANQAECgQIBAABNQAECgcIDwAIAAAAAA==.',
Mi='Misticphii:BAAANQADCgYIBgAAAA==.',
Mo='Moocelee:BAAANQADCgYIDAAAAA==.',
Mu='Murc:BAABNQAECn8sAAMcAAkKaxsPMQBqAgAcAAkKaxsPMQBqAgAUAAMK4g2kgwCfAAAAAA==.Murdoch:BAAANQADCggICAAAAA==.',
Na='Na:BAAANQABCgQIBAAAAA==.',
Ne='Nevoir:BAAANQADCgQIBAAAAA==.',
Nh='Nhasgul:BAAANQAECgcIBgABNQABCgIIAgAIAAAAAA==.Nhasraxion:BAACNQAFFH8WAAIWAAYKxBiwAgA6AQAWAAYKxBiwAgA6AQA1AAQKfzEAAxYACgr+INQOAK8CABYACgrgH9QOAK8CABUABQrdGZoQAQMBAAE1AAEKAggCAAgAAAAA.Nhasrezim:BAAANQAECggIDwABNQABCgIIAgAIAAAAAA==.',
Ni='Niceneasy:BAAANQADCgcIDAABNQAECgkJLAAcAGsbAA==.',
No='Nocturnal:BAAANQAECgQIBQAAAA==.Nowaifu:BAAANQAECgUIDAAAAA==.',
Or='Ornithogalum:BAAANQADCgUIBgAAAA==.',
Ow='Owlbread:BAAANQAECgcIDgAAAA==.',
Oz='Ozwin:BAAANQAECgEIAgABNQAFFAYIEwANANwkAA==.',
Pa='Palarin:BAACNQAFFH8fAAMXAAcK9ySAAQDMAgAXAAcK9ySAAQDMAgAVAAMK2B+VFQADAQA1AAQKfzoAAxcACgosJT8HAJEDABcACgosJT8HAJEDABUAAwrhHloeAewAAAAA.Pawmi:BAAANQAECgIIBAABNQAECgUIDAAIAAAAAA==.',
Pe='Peccator:BAABNQAECn8+AAIEAAoKrCU+AgAMBAAEAAoKrCU+AgAMBAAAAA==.Persess:BAAANQAECgMIAwAAAA==.',
Pl='Plat:BAABNQAECn8fAAIbAAcKEA2EGABzAQAbAAcKEA2EGABzAQAAAA==.Ploo:BAACNQAFFH8JAAIeAAQKNxlCBwDhAAAeAAQKNxlCBwDhAAA1AAQKfzAAAh4ACgqnIrsHAFMDAB4ACgqnIrsHAFMDAAAA.',
Pu='Punkinhed:BAAANQADCggIDwAAAA==.',
Ra='Rahkor:BAAANQADCgUIBwABNQAECgkJLAAcAGsbAA==.Raveheart:BAABNQAECn8dAAIEAAkKBiBqEgAaAwAEAAkKBiBqEgAaAwAAAA==.',
Re='Refr:BAACNQAFFH8JAAITAAUKuhMSDgDhAAATAAUKuhMSDgDhAAA1AAQKfzAAAhMACgpLILkZAC8DABMACgpLILkZAC8DAAAA.Renzo:BAAANQAECgYICQABNQAFFAYIEwANANwkAA==.',
Rh='Rhaegon:BAAANQADCgcICwAAAA==.',
Ri='Rinslock:BAAANQAECggICwABNQAFFAcIHwAXAPckAA==.Riskante:BAACNQAFFH8GAAMVAAMKVA8BHQCMAAAVAAMKVA8BHQCMAAAXAAEKIAwyLAA/AAA1AAQKfzcAAxcACgq6FVZFAFECABcACgq6FVZFAFECABUACAodGLSxALsBAAAA.',
Ro='Roonrana:BAAANQADCgYIDAAAAA==.Rosecake:BAAANQAECggIEQAAAA==.Rosemari:BAAANQAECgQJBQABNQAFFAYIEwAfAEsdAA==.Rosey:BAACNQAFFH8TAAIfAAYKSx03AABXAQAfAAYKSx03AABXAQA1AAQKf0cAAh8ACgqgIjsBAIcDAB8ACgqgIjsBAIcDAAAA.Rouge:BAABNQAECn8XAAMJAAkK6BwWEQBuAgAJAAcKOiAWEQBuAgAYAAMKzBTufwC0AAAAAA==.',
Ru='Runebraker:BAAANQAECgcIEAAAAA==.',
Sa='Sardor:BAAANQAECgcIEgABNQAFFAYIEwANANwkAA==.',
Sc='Scottyno:BAABNQAECn84AAIVAAoKhxeNawBbAgAVAAoKhxeNawBbAgAAAA==.',
Se='Senarria:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclaw:BAAANQADCgYICwAAAA==.Shanithell:BAAANQAECgQIAwAAAA==.Shanksz:BAAANQADCgIIAgAAAA==.Shellyd:BAAANQAECgEIAQAAAA==.',
Si='Siennaa:BAAANQADCgIIAgAAAA==.Sierra:BAAANQAECgQIBAAAAA==.Sinfulsmite:BAAANQAECgcIDwAAAA==.',
Sk='Skark:BAAANQAECgIIAwAAAA==.',
Sl='Sleifer:BAAANQAECgQJCQAAAA==.Slothy:BAABNQAECn8pAAMgAAoK2hZHWQBLAgAgAAoK2xVHWQBLAgAhAAIKERu8UACNAAAAAA==.',
Sn='Sneakyhand:BAACNQAFFH8WAAIHAAYKeiF0BwCUAQAHAAYKeiF0BwCUAQA1AAQKfzQAAwcACgp/JpkJAKcDAAcACgp/JpkJAKcDAAYAAQqhGTVBADoAAAAA.',
St='Starling:BAAANQAECgYIDQAAAA==.Stew:BAABNQAECn8YAAIiAAcKRwY1XwACAQAiAAcKRwY1XwACAQABNQAECggIHAAFAO8VAA==.',
Sy='Sylvi:BAAANQAECggIEAAAAA==.',
Ta='Takitsu:BAAANQAECgEIAQAAAA==.',
Th='Tharion:BAAANQAECgcIEQAAAA==.',
Ti='Tinytoes:BAAANQAECgIIAgAAAA==.Tired:BAABNQAECn8nAAIbAAgKBRsMCgDzAQAbAAgKBRsMCgDzAQAAAA==.Tish:BAAANQAECggIEQABNQAECgYIEAAIAAAAAA==.',
To='Tomn:BAAANQADCggIDgAAAA==.Towa:BAACNQAFFH8TAAIiAAYKtQutCAAKAQAiAAYKtQutCAAKAQA1AAQKf0QAAwsACgpJGnIOANMBACIACgqlFk4oAFwCAAsABgooHXIOANMBAAAA.',
Tr='Trater:BAEANQADCgMIAwAAAA==.',
Va='Vaskie:BAECNQAFFH8SAAIHAAYKexRwCQBqAQAHAAYKexRwCQBqAQA1AAQKf0wAAgcACgr+IncTAG4DAAcACgr+IncTAG4DAAAA.',
Ve='Veil:BAAANQADCgYICAABNQAECgkJFwAJAOgcAA==.Velenar:BAAANQAECgUIBQABNQAFFAYIEwANANwkAA==.Vella:BAABNQAECn8UAAIhAAkKTRbvBwCDAgAhAAkKTRbvBwCDAgAAAA==.',
Vo='Vooduel:BAAANQAECgcIBwAAAA==.',
Vy='Vyra:BAABNQAECn8aAAIVAAkKngg8xgCQAQAVAAkKngg8xgCQAQAAAA==.',
Wa='Wallê:BAAANQADCgYIBgAAAA==.Warsawz:BAAANQAECgEIAQAAAA==.',
We='Wetasscat:BAABNQAECn8UAAMgAAkK1xjNYwAuAgAgAAkK1xjNYwAuAgAhAAEKkhetbQBDAAAAAA==.',
Wo='Wotardag:BAAANQADCgcJDQAAAA==.',
Xa='Xavierr:BAAANQAECgEIAQAAAA==.',
Yo='Yorinn:BAAANQAECgcIEAABNQAFFAYIEwANANwkAA==.',
Ys='Ysayle:BAAANQAECgEJAgABNQAECgUIDAAIAAAAAA==.',
Yu='Yucky:BAAANQAECgUIBwABNQAECgYIDAAIAAAAAA==.',
Za='Zaht:BAAANQAECgUIBgAAAA==.Zargus:BAAANQAECgEIAQAAAA==.',
Ze='Zetsuon:BAABNQAECn88AAICAAoKEB3NEQBkAgACAAoKEB3NEQBkAgAAAA==.',
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
