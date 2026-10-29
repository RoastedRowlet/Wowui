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

local lookup = {'Druid-Restoration','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Blood','Mage-Arcane','Warrior-Fury','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Rogue-Assassination','Mage-Fire','DemonHunter-Devourer','Druid-Feral','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adarlaliiana:BAAANQAECgQIDgAAAA==.',
Ar='Arator:BAAANQADCgMIAwAAAA==.Arcadius:BAAANQADCgUICQAAAA==.',
At='Athenia:BAAANQAECgEIAQAAAA==.',
Ax='Axél:BAAANQADCgcIDQAAAA==.',
Az='Azarathia:BAAANQADCgEIAQAAAA==.',
Ba='Barbaria:BAAANQAECgcIEAAAAA==.Bastas:BAABNQAECn8fAAIBAAkKAAp+LgCnAQABAAkKAAp+LgCnAQAAAA==.',
Be='Beekro:BAACNQAFFH8MAAICAAMK+Q2vBwDUAAACAAMK+Q2vBwDUAAA1AAQKfy0AAgIACgpFGakDAO0CAAIACgpFGakDAO0CAAAA.Beladentata:BAAANQAECgYIDAABNQAFFAUIEAADAJ4UAA==.Belarina:BAAANQAECgcICgABNQAFFAUIEAADAJ4UAA==.Belated:BAAANQAECgcIBwAAAA==.Belatink:BAACNQAFFH8QAAIDAAUKnhQKCwB6AQADAAUKnhQKCwB6AQA1AAQKf1QAAwMACgoKJGsEAKYDAAMACgoKJGsEAKYDAAQAAwonC7sbAIkAAAAA.Bernocke:BAAANQAECgUIBQAAAA==.',
Bi='Bilando:BAABNQAECn8XAAMFAAkKgRNbHAB3AQAGAAkKgw5CrwCnAQAFAAYK0hZbHAB3AQAAAA==.',
Bl='Bludlust:BAAANQAECgUIBQAAAA==.Blueberry:BAACNQAFFH8QAAIDAAUKxx7NBgDMAQADAAUKxx7NBgDMAQA1AAQKfzAAAwMACgoBJEcFAJQDAAMACgp5IEcFAJQDAAQABwqsIQcEAJgCAAAA.',
Bo='Bonezthug:BAABNQAECn8cAAMEAAgK7xVSCgClAQADAAcK6A4GeQCwAQAEAAYKlhZSCgClAQAAAA==.Borden:BAAANQAECgcIDQAAAA==.',
Ca='Calaart:BAAANQAECgEIAQAAAA==.',
Ch='Chainer:BAABNQAECn8pAAIHAAoK1hT2TACHAgAHAAoK1hT2TACHAgAAAA==.',
Cl='Clubsandwich:BAAANQAECgEIAgAAAA==.',
Da='Dacker:BAAANQABCgEIAQAAAA==.Darthvolo:BAAANQAECgEIAQAAAA==.',
De='Deftones:BAAANQAECgQIBAAAAA==.Demonveil:BAAANQADCgYIBgABNQAECgkJFwAIAOgcAA==.',
Do='Dolt:BAAANQAECgQIBwAAAA==.',
Dr='Drezzarnbez:BAAANQAECgEIAQAAAA==.Drvoidberg:BAAANQAECgYICwAAAA==.',
Du='Durgrim:BAAANQAECgYIEAAAAA==.',
Ee='Eeèva:BAAANQADCgYJCgAAAA==.',
El='Electrabuzz:BAAANQADCgMIAwAAAA==.Ellanaras:BAAANQAECggICQAAAA==.',
Em='Emi:BAAANQADCggIGAAAAA==.',
Ep='Epoxxy:BAAANQADCgYIBgAAAA==.',
Er='Erzkal:BAABNQAFFH8JAAMJAAUKdgnKEgATAQAJAAUKiwTKEgATAQAHAAMK4QzdHwC0AAABNQAECggIFwAKAJEiAA==.',
Es='Espresso:BAACNQAFFH8UAAILAAcKbxkjBAASAgALAAcKbxkjBAASAgA1AAQKfzcAAgsACgrzJDUBAGQDAAsACgrzJDUBAGQDAAAA.',
Fo='Foxme:BAAANQADCgIIAgAAAA==.',
Ga='Gaartak:BAACNQAFFH8OAAIMAAUK3yScBgAxAQAMAAUK3yScBgAxAQA1AAQKfz8AAgwACgoYJpUAAPQDAAwACgoYJpUAAPQDAAAA.Garren:BAABNQAECn8aAAINAAYKzwzQHwFXAQANAAYKzwzQHwFXAQAAAA==.',
Gi='Giantcow:BAAANQAECgMIAwAAAA==.Gith:BAACNQAFFH8LAAIHAAQK0Q7EDgDcAAAHAAQK0Q7EDgDcAAA1AAQKfyQAAgcACgpvGidAAKoCAAcACgpvGidAAKoCAAAA.Githlock:BAAANQAECgMIBAABNQAFFAQICwAHANEOAA==.Githon:BAAANQAECgYIEwABNQAFFAQICwAHANEOAA==.',
Gl='Glittercakes:BAAANQAECgEIAQAAAA==.',
Gr='Grogrin:BAACNQAFFH8OAAIOAAUKJA12AQAmAQAOAAUKJA12AQAmAQA1AAQKfzsAAg4ACgo/ICIBABADAA4ACgo/ICIBABADAAAA.',
Ha='Halordric:BAAANQAECgEIAQABNQAECgUIBgAPAAAAAA==.',
He='Hekate:BAAANQADCggICgAAAA==.Heyblinkin:BAAANQAECgUIBQAAAA==.',
Hi='Hitmonlee:BAAANQADCggICAABNQAFFAgIIQACAMQiAA==.',
Ho='Hocus:BAAANQAECgUIBgABNQAFFAUIEAAQAN8SAA==.Houtoku:BAAANQAECgcIDQAAAQ==.Hozi:BAAANQADCgYIBgABNQAECgkJFgALAOUUAA==.Hozina:BAABNQAECn8WAAQLAAkK5RR1NwBpAQALAAYKqhB1NwBpAQADAAIKtwWz5wBvAAAEAAIKwAUDIgBVAAAAAA==.',
Hu='Huck:BAAANQADCggIDgAAAA==.Hultron:BAAANQADCgIIAgAAAA==.Huntington:BAABNQAECn8UAAIHAAcK6hB+pAC9AQAHAAcK6hB+pAC9AQAAAA==.',
Im='Imcrying:BAAANQAECgQIBAABNQAFFAUIEAAQAN8SAA==.Imtrying:BAACNQAFFH8QAAIQAAUK3xKyBwB6AQAQAAUK3xKyBwB6AQA1AAQKfzEAAxAACgprIP8ZAAkDABAACgprIP8ZAAkDABEAAQp/ByoxATgAAAAA.',
Iz='Izuna:BAABNQAECn8jAAISAAkK5SAJGgC7AgASAAkK5SAJGgC7AgAAAA==.',
Ja='Jaavere:BAAANQADCgcICwAAAA==.Jayaesir:BAACNQAFFH8HAAITAAMKChevFwDrAAATAAMKChevFwDrAAA1AAQKf0cAAhMACgpOJXIIALgDABMACgpOJXIIALgDAAAA.Jayal:BAACNQAFFH8NAAITAAUKywrlDwBOAQATAAUKywrlDwBOAQA1AAQKfzQAAhMACgqKI9kKAB4DABMACgqKI9kKAB4DAAAA.',
Jo='Johndurgrim:BAACNQAFFH8OAAIUAAUKWRyLAwDlAAAUAAUKWRyLAwDlAAA1AAQKfzYABBQACgppHzoMANYCABQACgppHzoMANYCABUABQrwDBq+AAABABMAAQoAACKIAU8AAAE1AAQKBggQAA8AAAAA.Jooja:BAABNQAECn8eAAIWAAcKRA9MRwCoAQAWAAcKRA9MRwCoAQABNQAECggIHAAEAO8VAA==.',
Ka='Katbelle:BAACNQAFFH8QAAIXAAUKKAc4AADXAAAXAAUKKAc4AADXAAA1AAQKfzwAAhcACgq/G3UAAJwCABcACgq/G3UAAJwCAAAA.',
Ke='Keyi:BAAANQADCggICAABNQAECggICQAPAAAAAA==.Keynallan:BAAANQADCggIEQAAAA==.',
Ki='Kin:BAAANQAECgMIAwAAAA==.Kinkykelly:BAABNQAECn8YAAIYAAoK8B5nBgCwAgAYAAoK8B5nBgCwAgABNQAFFAYIEwAMAC0gAA==.Kinkyknight:BAACNQAFFH8TAAIMAAYKLSBoBQAfAgAMAAYKLSBoBQAfAgA1AAQKfy0AAgwACgrwIUUFAAkDAAwACgrwIUUFAAkDAAAA.Kinkypal:BAAANQAFFAEIAQABNQAFFAYIEwAMAC0gAA==.',
Kr='Kreslin:BAAANQAECgQIBAABNQAECgYIEAAPAAAAAA==.Kriista:BAAANQADCgMIAwAAAA==.Krixxus:BAAANQADCgQIBAAAAA==.',
Ku='Kuroishi:BAAANQAECgQIBAAAAA==.',
['Kø']='Kø:BAAANQAECgQIAwABNQAECggIIAAZAI8XAA==.',
La='Lahar:BAAANQAECgcICwABNQAECgoKPAADAKslAA==.Lancer:BAAANQAECgMIAwAAAA==.',
Le='Leof:BAAANQAECggICwABNQAECgYIEAAPAAAAAA==.',
Li='Limptriscuit:BAAANQAECgEIAQAAAA==.Littlelam:BAACNQAFFH8GAAMaAAIKxRnEIABJAAAaAAEKxRnEIABJAAAMAAEKAAAGPgAXAAA1AAQKfxcAAhoACQp2IFQjALcCABoACQp2IFQjALcCAAAA.',
Lo='Locrock:BAAANQAECgYICAAAAA==.Lorkhan:BAAANQAECggIDQAAAA==.Lotti:BAAANQADCgcIDQAAAA==.',
Lt='Ltcclover:BAAANQADCgYIFwAAAA==.',
Lu='Lugren:BAAANQAECgMIBAAAAA==.',
Ly='Lyssandra:BAAANQAECggIDgAAAA==.',
Ma='Madclaw:BAAANQADCgYIBgAAAA==.Magith:BAAANQAECgcIDAAAAA==.Manhattan:BAAANQAECgQICAABNQAFFAcIFAALAG8ZAA==.Martini:BAABNQAECn8nAAMIAAkKBSAaEwCKAgAWAAgK1RzEGAC3AgAIAAkK1BsaEwCKAgABNQAFFAcIFAALAG8ZAA==.Mayalaran:BAAANQAECgUICQABNQAECgYIDQAPAAAAAA==.',
Mc='Mccavity:BAABNQAECn89AAIbAAoKrhS8AwDbAQAbAAoKrhS8AwDbAQABNQABCgQIBAAPAAAAAA==.',
Me='Mekabruti:BAAANQAECgQIBAABNQAECgcIDwAPAAAAAA==.',
Mi='Misticphii:BAAANQADCgYIBgAAAA==.',
Mo='Moocelee:BAAANQADCgYIDAAAAA==.',
Mu='Murc:BAABNQAECn8sAAMaAAkKaxsPMQBqAgAaAAkKaxsPMQBqAgASAAMK4g2kgwCfAAAAAA==.Murdoch:BAAANQADCggICAAAAA==.',
Na='Na:BAAANQABCgQIBAAAAA==.',
Ne='Nevoir:BAAANQADCgQIBAAAAA==.',
Nh='Nhasgul:BAAANQAECgcIBgABNQABCgIIAgAPAAAAAA==.Nhasraxion:BAACNQAFFH8QAAIUAAUKThcCBADRAAAUAAUKThcCBADRAAA1AAQKfy4AAxQACgrDINQOAK8CABQACgqlH9QOAK8CABMABQrdGZoQAQMBAAE1AAEKAggCAA8AAAAA.Nhasrezim:BAAANQAECggIDQABNQABCgIIAgAPAAAAAA==.',
Ni='Niceneasy:BAAANQADCgcIDAABNQAECgkJLAAaAGsbAA==.',
No='Nocturnal:BAAANQAECgQIBQAAAA==.Nowaifu:BAAANQAECgUICAAAAA==.',
Or='Ornithogalum:BAAANQADCgUIBgAAAA==.',
Ow='Owlbread:BAAANQAECgcIDQAAAA==.',
Oz='Ozwin:BAAANQAECgEIAQABNQAFFAUIDgAMAN8kAA==.',
Pa='Palarin:BAACNQAFFH8fAAMVAAcK9yS8AADdAgAVAAcK9yS8AADdAgATAAMK2B+VFQADAQA1AAQKfzkAAxUACgosJT8HAJEDABUACgosJT8HAJEDABMAAwrhHloeAewAAAAA.Pawmi:BAAANQAECgIIBAABNQAECgUICAAPAAAAAA==.',
Pe='Peccator:BAABNQAECn88AAIDAAoKqyUpAQAZBAADAAoKqyUpAQAZBAAAAA==.Persess:BAAANQAECgMIAwAAAA==.',
Pl='Plat:BAABNQAECn8aAAIZAAcKEA2EGABzAQAZAAcKEA2EGABzAQAAAA==.Ploo:BAACNQAFFH8GAAIcAAQKNxkJBgDgAAAcAAQKNxkJBgDgAAA1AAQKfywAAhwACgqRIrsHAFMDABwACgqRIrsHAFMDAAAA.',
Pu='Punkinhed:BAAANQADCggIDwAAAA==.',
Ra='Rahkor:BAAANQADCgUIBwABNQAECgkJLAAaAGsbAA==.Raveheart:BAABNQAECn8cAAIDAAgKmB/HEwDIAgADAAgKmB/HEwDIAgAAAA==.',
Re='Refr:BAACNQAFFH8JAAIRAAUKuhOWCgDiAAARAAUKuhOWCgDiAAA1AAQKfzAAAhEACgpLILkZAC8DABEACgpLILkZAC8DAAAA.Renzo:BAAANQAECgYICQABNQAFFAUIDgAMAN8kAA==.',
Rh='Rhaegon:BAAANQADCgcICwAAAA==.',
Ri='Riskante:BAABNQAECn8zAAMVAAoKuhVWRQBRAgAVAAoKuhVWRQBRAgATAAgKHRi0sQC7AQAAAA==.',
Ro='Roonrana:BAAANQADCgYIDAAAAA==.Rosecake:BAAANQAECgYICgAAAA==.Rosemari:BAAANQAECgQJBQABNQAFFAUIDgAdAM4eAA==.Rosey:BAACNQAFFH8OAAIdAAUKzh5TAAAEAQAdAAUKzh5TAAAEAQA1AAQKf0EAAh0ACgrWITsBAIcDAB0ACgrWITsBAIcDAAAA.Rouge:BAABNQAECn8XAAMIAAkK6BwWEQBuAgAIAAcKOiAWEQBuAgAWAAMKzBTufwC0AAAAAA==.',
Ru='Runebraker:BAAANQAECgcIDAAAAA==.',
Sa='Sardor:BAAANQAECgUICQABNQAFFAUIDgAMAN8kAA==.',
Sc='Scottyno:BAABNQAECn80AAITAAoKahfpSwDTAQATAAoKahfpSwDTAQAAAA==.',
Se='Senarria:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclaw:BAAANQADCgYICwAAAA==.Shanithell:BAAANQAECgQIAwAAAA==.Shanksz:BAAANQADCgIIAgAAAA==.Shellyd:BAAANQAECgEIAQAAAA==.',
Si='Siennaa:BAAANQADCgIIAgAAAA==.Sierra:BAAANQADCggJCAAAAA==.Sinfulsmite:BAAANQAECgcIDwAAAA==.',
Sk='Skark:BAAANQAECgIIAwAAAA==.',
Sl='Sleifer:BAAANQAECgQJCQAAAA==.Slothy:BAABNQAECn8pAAMeAAoK2hZHWQBLAgAeAAoK2xVHWQBLAgAfAAIKERu8UACNAAAAAA==.',
Sn='Sneakyhand:BAACNQAFFH8QAAIGAAUKuCEtCQAwAQAGAAUKuCEtCQAwAQA1AAQKfzEAAwYACgq0JZkJAKcDAAYACgq0JZkJAKcDAAUAAQqhGTVBADoAAAAA.',
St='Starling:BAAANQAECgYIDQAAAA==.Stew:BAABNQAECn8YAAIgAAcKRwY1XwACAQAgAAcKRwY1XwACAQABNQAECggIHAAEAO8VAA==.',
Sy='Sylvi:BAAANQAECgcIDQAAAA==.',
Ta='Takitsu:BAAANQAECgEIAQAAAA==.',
Th='Tharion:BAAANQAECgcIDwAAAA==.',
Ti='Tinytoes:BAAANQAECgIIAgAAAA==.Tired:BAABNQAECn8gAAIZAAgKjxftDgAkAgAZAAgKjxftDgAkAgAAAA==.Tish:BAAANQAECggIEQABNQAECgYIEAAPAAAAAA==.',
To='Tomn:BAAANQADCggIDgAAAA==.Towa:BAACNQAFFH8OAAIgAAUKEA3iDwAHAQAgAAUKEA3iDwAHAQA1AAQKf0MAAwoACgr1GXIOANMBACAACgpRFk4oAFwCAAoABgooHXIOANMBAAAA.',
Tr='Trater:BAEANQADCgMIAwAAAA==.',
Va='Vaskie:BAECNQAFFH8SAAIGAAYKexRBBgB2AQAGAAYKexRBBgB2AQA1AAQKf0kAAgYACgqRIXcTAG4DAAYACgqRIXcTAG4DAAAA.',
Ve='Veil:BAAANQADCgYICAABNQAECgkJFwAIAOgcAA==.Velenar:BAAANQAECgUIBAABNQAFFAUIDgAMAN8kAA==.Vella:BAABNQAECn8UAAIfAAkKTRbvBwCDAgAfAAkKTRbvBwCDAgAAAA==.',
Vo='Vooduel:BAAANQAECgcIBwAAAA==.',
Vy='Vyra:BAABNQAECn8UAAITAAgKQwk8xgCQAQATAAgKQwk8xgCQAQAAAA==.',
Wa='Wallê:BAAANQADCgYIBgAAAA==.',
We='Wetasscat:BAAANQAECgcIDgAAAA==.',
Wo='Wotardag:BAAANQADCgcJDQAAAA==.',
Xa='Xavierr:BAAANQABCgIIAgAAAA==.',
Yo='Yorinn:BAAANQAECgcICAABNQAFFAUIDgAMAN8kAA==.',
Ys='Ysayle:BAAANQAECgEJAgABNQAECgUICAAPAAAAAA==.',
Yu='Yucky:BAAANQAECgUIBwABNQAECgYICwAPAAAAAA==.',
Za='Zaht:BAAANQAECgUIBgAAAA==.Zargus:BAAANQAECgEIAQAAAA==.',
Ze='Zetsuon:BAABNQAECn84AAIBAAoKEB2mCwB9AgABAAoKEB2mCwB9AgAAAA==.',
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
