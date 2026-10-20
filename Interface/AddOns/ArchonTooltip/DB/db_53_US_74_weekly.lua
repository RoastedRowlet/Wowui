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

local lookup = {'Druid-Restoration','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Blood','Mage-Arcane','Warrior-Fury','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Rogue-Assassination','Mage-Fire','Druid-Feral','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adarlaliiana:BAAANQAECgQIDgAAAA==.',
Ar='Arcadius:BAAANQADCgUICQAAAA==.',
At='Athenia:BAAANQAECgEIAQAAAA==.',
Ax='Axél:BAAANQADCgcIDQAAAA==.',
Az='Azarathia:BAAANQADCgEIAQAAAA==.',
Ba='Barbaria:BAAANQAECgcIDwAAAA==.Bastas:BAABNQAECn8fAAIBAAkKAAp+LgCnAQABAAkKAAp+LgCnAQAAAA==.',
Be='Beekro:BAACNQAFFH8JAAICAAMKiQ2vBwDUAAACAAMKiQ2vBwDUAAA1AAQKfykAAgIACQqDG6kDAO0CAAIACQqDG6kDAO0CAAAA.Beladentata:BAAANQAECgYIDAABNQAFFAUIDQADAF8TAA==.Belarina:BAAANQAECgcICgABNQAFFAUIDQADAF8TAA==.Belatink:BAACNQAFFH8NAAIDAAUKXxMCBgCCAQADAAUKXxMCBgCCAQA1AAQKf0YAAwMACgoLIasKAG0DAAMACgoLIasKAG0DAAQAAwonC7sbAIkAAAAA.Bernocke:BAAANQADCggIEgAAAA==.',
Bi='Bilando:BAABNQAECn8WAAMFAAkKgRNbHAB3AQAFAAYK0hZbHAB3AQAGAAkKgw55XADgAAAAAA==.',
Bl='Bludlust:BAAANQAECgQIBAAAAA==.Blueberry:BAACNQAFFH8NAAIDAAUKrR5JAwDaAQADAAUKrR5JAwDaAQA1AAQKfyMAAwQACgqIIgcEAJgCAAQABwqsIQcEAJgCAAMABwqjIWQiAHgBAAAA.',
Bo='Bonezthug:BAABNQAECn8cAAMEAAgK7xVSCgClAQADAAcK6A4GeQCwAQAEAAYKlhZSCgClAQAAAA==.Borden:BAAANQAECgcIDAAAAA==.',
Ca='Calaart:BAAANQAECgEIAQAAAA==.',
Ch='Chainer:BAABNQAECn8oAAIHAAoK1hT2TACHAgAHAAoK1hT2TACHAgAAAA==.',
Cl='Clubsandwich:BAAANQAECgEIAgAAAA==.',
Da='Dacker:BAAANQAECgEIAQAAAA==.Darthvolo:BAAANQAECgEIAQAAAA==.',
De='Demonveil:BAAANQADCgYIBgABNQAECgkJFwAIAOgcAA==.',
Do='Dolt:BAAANQAECgQIBwAAAA==.',
Dr='Drezzarnbez:BAAANQAECgEIAQAAAA==.Drvoidberg:BAAANQAECgYICwAAAA==.',
Du='Durgrim:BAAANQAECgYIEAAAAA==.',
Ee='Eeèva:BAAANQADCgYJCgAAAA==.',
El='Ellanaras:BAAANQAECgcIBwAAAA==.',
Em='Emi:BAAANQADCggIGAAAAA==.',
Ep='Epoxxy:BAAANQADCgYIBgAAAA==.',
Er='Erzkal:BAABNQAFFH8JAAMJAAUKdgnKEgATAQAJAAUKiwTKEgATAQAHAAMK4QzdHwC0AAABNQAECggIFwAKAJEiAA==.',
Es='Espresso:BAACNQAFFH8UAAILAAcKbxkjBAASAgALAAcKbxkjBAASAgA1AAQKfy0AAgsACgo5I6MGAG4DAAsACgo5I6MGAG4DAAAA.',
Fo='Foxme:BAAANQADCgIIAgAAAA==.',
Ga='Gaartak:BAACNQAFFH8MAAIMAAUK3ySxAwA8AQAMAAUK3ySxAwA8AQA1AAQKfzsAAgwACgqwJZUAAPQDAAwACgqwJZUAAPQDAAAA.Garren:BAABNQAECn8aAAINAAYKzwzQHwFXAQANAAYKzwzQHwFXAQAAAA==.',
Gi='Giantcow:BAAANQAECgMIAwAAAA==.Gith:BAACNQAFFH8LAAIHAAQK0Q51CADiAAAHAAQK0Q51CADiAAA1AAQKfyAAAgcACgo2FydAAKoCAAcACgo2FydAAKoCAAAA.Githlock:BAAANQAECgMIBAABNQAFFAQICwAHANEOAA==.Githon:BAAANQAECgYIEwABNQAFFAQICwAHANEOAA==.',
Gl='Glittercakes:BAAANQAECgEIAQAAAA==.',
Gr='Grogrin:BAACNQAFFH8MAAIOAAUKJA12AQAmAQAOAAUKJA12AQAmAQA1AAQKfzIAAg4ACgrMHbMEAOoCAA4ACgrMHbMEAOoCAAAA.',
Ha='Halordric:BAAANQAECgEIAQABNQAECgUIBgAPAAAAAA==.',
He='Hekate:BAAANQADCggICgAAAA==.Heyblinkin:BAAANQAECgUIBQAAAA==.',
Hi='Hitmonlee:BAAANQADCggICAABNQAFFAgIIQACAMQiAA==.',
Ho='Hocus:BAAANQAECgUIBgABNQAFFAUIDQAQAN8SAA==.Houtoku:BAAANQAECggIDgAAAQ==.Hozi:BAAANQADCgYIBgABNQAECgkJFgALAOUUAA==.Hozina:BAABNQAECn8WAAQLAAkK5RR1NwBpAQALAAYKqhB1NwBpAQADAAIKtwWz5wBvAAAEAAIKwAUDIgBVAAAAAA==.',
Hu='Huck:BAAANQADCggIDgAAAA==.Hultron:BAAANQADCgIIAgAAAA==.Huntington:BAABNQAECn8UAAIHAAcK6hB+pAC9AQAHAAcK6hB+pAC9AQAAAA==.',
Im='Imcrying:BAAANQAECgQIBAABNQAFFAUIDQAQAN8SAA==.Imtrying:BAACNQAFFH8NAAIQAAUK3xJKBACFAQAQAAUK3xJKBACFAQA1AAQKfy0AAxAACgprIP8ZAAkDABAACgprIP8ZAAkDABEAAQp/ByoxATgAAAAA.',
Iz='Izuna:BAABNQAECn8iAAISAAkKTCAJGgC7AgASAAkKTCAJGgC7AgAAAA==.',
Ja='Jaavere:BAAANQADCgQIBAAAAA==.Jayaesir:BAACNQAFFH8HAAITAAMKChevFwDrAAATAAMKChevFwDrAAA1AAQKfzcAAhMACgoXJHIIALgDABMACgoXJHIIALgDAAAA.Jayal:BAACNQAFFH8KAAITAAUKywrlDwBOAQATAAUKywrlDwBOAQA1AAQKfyoAAhMACgqkH1NMALACABMACgqkH1NMALACAAAA.',
Jo='Johndurgrim:BAACNQAFFH8MAAIUAAUKqBs1AgDuAAAUAAUKqBs1AgDuAAA1AAQKfzUABBQACgppHzoMANYCABQACgppHzoMANYCABUABQrwDBq+AAABABMAAQoAACKIAU8AAAE1AAQKBggQAA8AAAAA.Jooja:BAABNQAECn8eAAIWAAcKRA9MRwCoAQAWAAcKRA9MRwCoAQABNQAECggIHAAEAO8VAA==.',
Ka='Katbelle:BAACNQAFFH8NAAIXAAUKzQUjAADjAAAXAAUKzQUjAADjAAA1AAQKfy8AAhcACgp1Fn8BAKICABcACgp1Fn8BAKICAAAA.',
Ke='Keyi:BAAANQADCggICAABNQAECgoKNAADAKAbAA==.Keynallan:BAAANQADCggIEQAAAA==.',
Ki='Kin:BAAANQAECgMIAwAAAA==.Kinkykelly:BAAANQAECggIDwABNQAFFAYIEwAMAC0gAA==.Kinkyknight:BAACNQAFFH8TAAIMAAYKLSBoBQAfAgAMAAYKLSBoBQAfAgA1AAQKfyAAAgwACgrnHUwKAJwBAAwACgrnHUwKAJwBAAAA.Kinkypal:BAAANQAFFAEIAQABNQAFFAYIEwAMAC0gAA==.',
Kr='Kreslin:BAAANQAECgQIBAABNQAECgYIEAAPAAAAAA==.Krixxus:BAAANQADCgQIBAAAAA==.',
Ku='Kuroishi:BAAANQAECgQIBAAAAA==.',
['Kø']='Kø:BAAANQAECgQIAwABNQAECggIHgAYAGAXAA==.',
La='Lahar:BAAANQAECgcICwABNQAECgoKMgADAPcjAA==.Lancer:BAAANQAECgMIAwAAAA==.',
Le='Leof:BAAANQAECgcIBwABNQAECgYIEAAPAAAAAA==.',
Li='Limptriscuit:BAAANQAECgEIAQAAAA==.Littlelam:BAACNQAFFH8GAAMZAAIKxRnEIABJAAAZAAEKxRnEIABJAAAMAAEKAAAGPgAXAAA1AAQKfxcAAhkACQp2IFQjALcCABkACQp2IFQjALcCAAAA.',
Lo='Locrock:BAAANQAECgYICAAAAA==.Lorkhan:BAAANQAECgYIDAAAAA==.Lotti:BAAANQADCgcIDQAAAA==.',
Lt='Ltcclover:BAAANQADCgYIFwAAAA==.',
Lu='Lugren:BAAANQAECgIIAwAAAA==.',
Ly='Lyssandra:BAAANQAECgYIBgAAAA==.',
Ma='Madclaw:BAAANQADCgYIBgAAAA==.Magith:BAAANQAECgcIDAAAAA==.Manhattan:BAAANQAECgQICAABNQAFFAcIFAALAG8ZAA==.Martini:BAABNQAECn8eAAMIAAkKAiBZDAB7AQAWAAgK1RzEGAC3AgAIAAcKvxlZDAB7AQABNQAFFAcIFAALAG8ZAA==.Mayalaran:BAAANQAECgUICAABNQAECgYIDQAPAAAAAA==.',
Mc='Mccavity:BAABNQAECn84AAIaAAkK/xOhAQCaAQAaAAkK/xOhAQCaAQABNQABCgQIBAAPAAAAAA==.',
Me='Mekabruti:BAAANQAECgQIBAABNQAECgcIDwAPAAAAAA==.',
Mi='Misticphii:BAAANQADCgYIBgAAAA==.',
Mo='Moocelee:BAAANQADCgYIDAAAAA==.',
Mu='Murc:BAABNQAECn8sAAMZAAkKaxsPMQBqAgAZAAkKaxsPMQBqAgASAAMK4g2kgwCfAAAAAA==.Murdoch:BAAANQADCggICAAAAA==.',
Na='Na:BAAANQABCgQIBAAAAA==.',
Ne='Nevoir:BAAANQADCgQIBAAAAA==.',
Nh='Nhasgul:BAAANQAECgYIBgABNQABCgIIAgAPAAAAAA==.Nhasraxion:BAACNQAFFH8NAAIUAAUK1hXgAgDPAAAUAAUK1hXgAgDPAAA1AAQKfyoAAxQACgrKHtQOAK8CABQACgqsHdQOAK8CABMABQrdGZoQAQMBAAE1AAEKAggCAA8AAAAA.Nhasrezim:BAAANQAECgYIBgABNQABCgIIAgAPAAAAAA==.',
Ni='Niceneasy:BAAANQADCgcIDAABNQAECgkJLAAZAGsbAA==.',
No='Nocturnal:BAAANQAECgQIBQAAAA==.Nowaifu:BAAANQAECgcICgAAAA==.',
Or='Ornithogalum:BAAANQADCgUIBgAAAA==.',
Ow='Owlbread:BAAANQAECgYIDAAAAA==.',
Oz='Ozwin:BAAANQAECgIIAQABNQAFFAUIDAAMAN8kAA==.',
Pa='Palarin:BAACNQAFFH8fAAMVAAcK9yRCAADpAgAVAAcK9yRCAADpAgATAAMK2B+VFQADAQA1AAQKfzAAAxUACgosJT8HAJEDABUACgosJT8HAJEDABMAAwrhHloeAewAAAAA.Pawmi:BAAANQAECgIIBAABNQAECgcICgAPAAAAAA==.',
Pe='Peccator:BAABNQAECn8yAAIDAAoK9yP7AgC8AwADAAoK9yP7AgC8AwAAAA==.Persess:BAAANQAECgMIAwAAAA==.',
Pl='Plat:BAABNQAECn8aAAIYAAcKEA2EGABzAQAYAAcKEA2EGABzAQAAAA==.Ploo:BAABNQAECn8sAAIbAAoKkSK7BwBTAwAbAAoKkSK7BwBTAwAAAA==.',
Pu='Punkinhed:BAAANQADCggIDwAAAA==.',
Ra='Rahkor:BAAANQADCgUIBwABNQAECgkJLAAZAGsbAA==.Raveheart:BAABNQAECn8UAAIDAAgKHxt0CgA9AgADAAgKHxt0CgA9AgAAAA==.',
Re='Refr:BAACNQAFFH8HAAIRAAUKuhMbBgDxAAARAAUKuhMbBgDxAAA1AAQKfywAAhEACgpLILkZAC8DABEACgpLILkZAC8DAAAA.Renzo:BAAANQAECgYICQABNQAFFAUIDAAMAN8kAA==.',
Rh='Rhaegon:BAAANQADCgcICwAAAA==.',
Ri='Riskante:BAABNQAECn8uAAMVAAoK6xRWRQBRAgAVAAkKSBZWRQBRAgATAAgKHRiDaAD0AAAAAA==.',
Ro='Roonrana:BAAANQADCgYIDAAAAA==.Rosecake:BAAANQAECgUICQAAAA==.Rosemari:BAAANQAECgQJBQABNQAFFAUIDAAcAM4eAA==.Rosey:BAACNQAFFH8MAAIcAAUKzh4+AAAQAQAcAAUKzh4+AAAQAQA1AAQKfz0AAhwACgprITsBAIcDABwACgprITsBAIcDAAAA.Rouge:BAABNQAECn8XAAMIAAkK6BwWEQBuAgAIAAcKOiAWEQBuAgAWAAMKzBTufwC0AAAAAA==.',
Ru='Runebraker:BAAANQAECgYIBgAAAA==.',
Sa='Sardor:BAAANQAECgUICQABNQAFFAUIDAAMAN8kAA==.',
Sc='Scottyno:BAABNQAECn8qAAITAAoKGRcGLQB5AQATAAoKGRcGLQB5AQAAAA==.',
Se='Senarria:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclaw:BAAANQADCgYICwAAAA==.Shanithell:BAAANQAECgQIAwAAAA==.Shanksz:BAAANQADCgIIAgAAAA==.Shellyd:BAAANQAECgEIAQAAAA==.',
Si='Siennaa:BAAANQADCgIIAgAAAA==.Sierra:BAAANQADCggJCAAAAA==.Sinfulsmite:BAAANQAECgcIDwAAAA==.',
Sk='Skark:BAAANQAECgIIAwAAAA==.',
Sl='Sleifer:BAAANQAECgQJCQAAAA==.Slothy:BAABNQAECn8oAAMdAAkK0xZHWQBLAgAdAAkKsBVHWQBLAgAeAAIKERu8UACNAAAAAA==.',
Sn='Sneakyhand:BAACNQAFFH8NAAIGAAUKyiDtBQAhAQAGAAUKyiDtBQAhAQA1AAQKfy0AAwYACgqrJZkJAKcDAAYACgqrJZkJAKcDAAUAAQqhGTVBADoAAAAA.',
St='Starling:BAAANQAECgYIDQAAAA==.Stew:BAABNQAECn8YAAIfAAcKRwY1XwACAQAfAAcKRwY1XwACAQABNQAECggIHAAEAO8VAA==.',
Sy='Sylvi:BAAANQAECggIDQAAAA==.',
Ta='Takitsu:BAAANQAECgEIAQAAAA==.',
Th='Tharion:BAAANQAECggIDQAAAA==.',
Ti='Tinytoes:BAAANQAECgIIAgAAAA==.Tired:BAABNQAECn8eAAIYAAgKYBf5BAB1AQAYAAgKYBf5BAB1AQAAAA==.Tish:BAAANQAECggIEQABNQAECgYIEAAPAAAAAA==.',
To='Tomn:BAAANQADCggIDgAAAA==.Towa:BAACNQAFFH8MAAIfAAUKEA3/BgC2AAAfAAUKEA3/BgC2AAA1AAQKfz8AAwoACgqgGXIOANMBAB8ACgr7FU4oAFwCAAoABgooHXIOANMBAAAA.',
Tr='Trater:BAEANQADCgMIAwAAAA==.',
Va='Vaskie:BAECNQAFFH8RAAIGAAUKeREZBgAdAQAGAAUKeREZBgAdAQA1AAQKf0AAAgYACgqRITgJACcCAAYACgqRITgJACcCAAAA.',
Ve='Veil:BAAANQADCgYICAABNQAECgkJFwAIAOgcAA==.Vella:BAABNQAECn8UAAIeAAkKTRbvBwCDAgAeAAkKTRbvBwCDAgAAAA==.',
Vo='Vooduel:BAAANQAECgcIBwAAAA==.',
Vy='Vyra:BAABNQAECn8UAAITAAgKQwk8xgCQAQATAAgKQwk8xgCQAQAAAA==.',
Wa='Wallê:BAAANQADCgYIBgAAAA==.',
We='Wetasscat:BAAANQAECgcIDgAAAA==.',
Wo='Wotardag:BAAANQADCgcJDQAAAA==.',
Yo='Yorinn:BAAANQAECgcIBwABNQAFFAUIDAAMAN8kAA==.',
Ys='Ysayle:BAAANQAECgEJAgABNQAECgcICgAPAAAAAA==.',
Yu='Yucky:BAAANQAECgUIBwAAAA==.',
Za='Zaht:BAAANQAECgUIBgAAAA==.Zargus:BAAANQAECgEIAQAAAA==.',
Ze='Zetsuon:BAABNQAECn8vAAIBAAoKEB3TFAChAgABAAoKEB3TFAChAgAAAA==.',
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
