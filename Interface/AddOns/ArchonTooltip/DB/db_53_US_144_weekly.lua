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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Subtlety','Warrior-Fury','Druid-Restoration','Paladin-Holy','Druid-Guardian','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Priest-Discipline','Paladin-Protection','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','Evoker-Augmentation','Warrior-Arms','Evoker-Devastation','Monk-Brewmaster','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','Shaman-Enhancement','Mage-Frost','Evoker-Preservation','Mage-Fire',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Account:BAAANQAECgEIAQAAAA==.',
Ae='Aetherr:BAAANQAECggIBAAAAA==.',
Ag='Agnithor:BAABNQAECn8oAAIBAAoK0BpmQwBTAgABAAoK0BpmQwBTAgAAAA==.',
Al='Aliadra:BAABNQAECn8pAAICAAoKdiJdFAC9AgACAAoKdiJdFAC9AgAAAA==.Alistor:BAAANQAECgEIAgAAAA==.Alistus:BAACNQAFFH8GAAMDAAIKKyJHDACaAAADAAIKKyJHDACaAAAEAAEK2gGODgAtAAA1AAQKf0IAAwMACgohJR8DAMEDAAMACgohJR8DAMEDAAQABwq/HpwkACICAAAA.Alphá:BAAANQADCgcICAABNQAECgoKMAABAOoTAA==.',
Am='Amyliz:BAAANQABCggICgAAAA==.',
An='Angua:BAABNQAECn8pAAIFAAkKkhKPHwCKAQAFAAkKkhKPHwCKAQAAAA==.Anotheralt:BAABNQAECn8rAAMBAAkKQSJ+DAD+AgABAAkKQSJ+DAD+AgAGAAIKbhelDgFuAAAAAA==.',
Au='Aurius:BAABNQAECn8VAAIHAAgKvgekqwAAAQAHAAgKvgekqwAAAQAAAA==.',
Av='Aveliandis:BAAANQAECgUIBwAAAA==.',
Ax='Axuz:BAAANQAECgEIAgAAAA==.',
Az='Azerphage:BAAANQAECgUIDwABNQAECggIFQAEAHUUAA==.Azhorra:BAAANQADCgYIDgAAAA==.Azzog:BAAANQAECgEIAQABNQAECgUICwAIAAAAAA==.Azül:BAABNQAECn8VAAIEAAgKdRTMOQB3AQAEAAgKdRTMOQB3AQAAAA==.',
Ba='Bacchanalian:BAAANQAECgYICwABNQAECgcIHgABADERAA==.Baelrin:BAABNQAECn8mAAIGAAkKCBXYKwCvAQAGAAkKCBXYKwCvAQAAAA==.Baindyn:BAAANQAECgMIBwAAAA==.Barator:BAAANQAECgEIAgAAAA==.',
Be='Beaum:BAABNQAECn84AAICAAoKYiazAgDlAwACAAoKYiazAgDlAwAAAA==.',
Bi='Bigdrufus:BAAANQAECgEIAgAAAA==.',
Bl='Blackröse:BAABNQAECn8dAAMJAAkKvQzaBwDoAQAJAAkKsgzaBwDoAQAKAAcK1QRWRgAoAQAAAA==.Bladebane:BAABNQAECn8bAAILAAgKSQSlVACZAAALAAgKSQSlVACZAAAAAA==.Blight:BAAANQADCggICAABNQAFFAgIIgAMALckAA==.Blksunshine:BAAANQADCggIFgAAAA==.Bloodbite:BAAANQAECgUIBQAAAA==.',
Bo='Bolash:BAABNQAECn8yAAINAAcKeB6qCABYAgANAAcKeB6qCABYAgAAAA==.Bovinelover:BAACNQAFFH8IAAIOAAUKcBz3BABdAQAOAAUKcBz3BABdAQA1AAQKf0UAAw4ACgqpJZ4AABwEAA4ACgqpJZ4AABwEAAUAAQoAABeCAAAAAAAA.',
Br='Bradthomas:BAAANQAECgUICQAAAA==.Braindead:BAAANQAECgUIBgABNQAECggIFQAEAHUUAA==.Bruscha:BAAANQAECgMIBAAAAA==.',
Bu='Bulvhine:BAABNQAECn8eAAIHAAkK8hzSOAAWAgAHAAkK8hzSOAAWAgAAAA==.',
Ca='Cactusteeth:BAAANQAECgIIBQAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQAECgMICAAAAA==.Cantatrix:BAAANQADCggIGAAAAA==.Capslok:BAAANQAECgYIDgAAAA==.Captinmeat:BAAANQAFFAEIAgAAAA==.Castus:BAAANQAECgUICwAAAA==.',
Ce='Cecilx:BAABNQAECn8qAAIPAAgKlSRrCQAxAwAPAAgKlSRrCQAxAwAAAA==.Celiailia:BAAANQAECgQIBAAAAA==.Censøred:BAAANQAECgYIBwABNQAECgkJFgAQAPsOAA==.',
Ch='Chimerax:BAABNQAECn9DAAMRAAoKSB8TBACkAgARAAgKRx8TBACkAgASAAgKPRyPZAAsAgAAAA==.Chully:BAABNQAECn88AAIEAAkK9R+rEQDgAgAEAAkK9R+rEQDgAgAAAA==.',
Cl='Clairíty:BAABNQAECn8YAAMTAAgKdBm+VgAeAgATAAgKdBm+VgAeAgAUAAEKAACehwAiAAAAAA==.Clegg:BAAANQAECgQIBQABNQAECggIFQAEAHUUAA==.Click:BAABNQAECn8gAAIVAAgKuhR1TAC3AQAVAAgKuhR1TAC3AQAAAA==.',
Co='Comadore:BAACNQAFFH8FAAIHAAIKxwUCGwB3AAAHAAIKxwUCGwB3AAA1AAQKfyMAAgcACgp9E8ORAAECAAcACgp9E8ORAAECAAAA.',
Cr='Crankycad:BAAANQAECgEIAQAAAA==.Credan:BAEANQAECggICQAAAA==.',
Cu='Cuyo:BAAANQAECgQIBAAAAA==.',
Da='Daphe:BAAANQAECgUIEAAAAA==.Dardria:BAAANQAECgEIBAAAAA==.Darknesheart:BAAANQAECgEIAgAAAA==.',
De='Deathslead:BAABNQAECn8iAAIVAAoKIRPpdQAkAgAVAAoKIRPpdQAkAgAAAA==.Decrepe:BAABNQAECn87AAIOAAkKUB0EFQCfAgAOAAkKUB0EFQCfAgAAAA==.Delph:BAABNQAECn8mAAINAAoKiBzCBADnAgANAAoKiBzCBADnAgAAAA==.Deshal:BAAANQADCgcIJwAAAA==.Dethklock:BAAANQADCgEIAQAAAA==.',
Di='Discostar:BAABNQAECn8sAAMOAAoKyRXgDABkAgAOAAoKyRXgDABkAgAFAAIKlATLnQBlAAAAAA==.Distill:BAAANQADCgQIBAABNQAFFAgIIgAMALckAA==.',
Do='Dominicm:BAAANQAECggICQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCggIHAAAAA==.Droidgen:BAAANQADCggIDQAAAA==.Druidcam:BAAANQAECgUIDwAAAA==.',
Eb='Ebonhorn:BAAANQAECgMICAAAAA==.',
Ei='Einari:BAABNQAECn8xAAMWAAkKBiVEBACOAgATAAkK6yGxMgCdAgAWAAYKsSVEBACOAgAAAA==.Einark:BAAANQADCgQIBAAAAA==.',
Ek='Ekiim:BAAANQAECggIDwAAAA==.',
El='Eldamari:BAAANQAECgYIDgAAAA==.Elinis:BAAANQAECgUIBgAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUIBQAAAA==.',
Er='Eridor:BAAANQAECgUIDQAAAA==.',
Es='Esbernia:BAAANQAECgUICgAAAA==.Eshul:BAAANQAECgEIAQABNQAECggIFAAXAFQGAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ew='Ew:BAAANQAECgcIAQAAAA==.',
Ex='Exek:BAABNQAECn8oAAITAAoKnBLBMwDtAQATAAoKnBLBMwDtAQAAAA==.',
Fa='Fabaztard:BAABNQAECn8iAAIFAAgKmhEGIwBsAQAFAAgKmhEGIwBsAQAAAA==.Faline:BAABNQAECn8XAAIOAAgKOAuDOgBMAQAOAAgKOAuDOgBMAQAAAA==.',
Fe='Felgetabouit:BAACNQAFFH8IAAIEAAIKwxj9CACPAAAEAAIKwxj9CACPAAA1AAQKfyoAAgQACgpSHfEZAIoCAAQACgpSHfEZAIoCAAAA.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQADCgQIBgAAAA==.Feywynn:BAAANQADCgYIBgAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAABNQAECn8lAAIPAAgK+hNHMwDUAQAPAAgK+hNHMwDUAQAAAA==.Filintos:BAAANQAECgEIAQAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgABNQAFFAMIBgAEAPMhAA==.',
Fo='Fontaine:BAAANQAECgEIAQAAAA==.Foradin:BAABNQAECn8WAAMXAAYKdApSQAD4AAAXAAYKdApSQAD4AAAHAAYKJAN7NwHHAAAAAA==.Forky:BAAANQAECgEICAAAAA==.Forloss:BAAANQAECgEIAQAAAA==.Foxknight:BAAANQAECgMIBgAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAwAAAA==.Fryeren:BAAANQADCggIBwAAAA==.',
Ft='Ftx:BAABNQAECn8aAAIYAAUKExy+FQCRAQAYAAUKExy+FQCRAQAAAA==.',
['Fí']='Fírefox:BAAANQAECgEIAQABNQAECgMIBgAIAAAAAA==.',
Ga='Gaern:BAABNQAECn8nAAMZAAoKUxlHNQBTAgAZAAkKwhpHNQBTAgAaAAMK9w5iWgC0AAAAAA==.Gaidan:BAABNQAECn8cAAIFAAgKxRYRJgBUAQAFAAgKxRYRJgBUAQABNQAFFAYIDAAEAEsQAA==.Gaidin:BAACNQAFFH8MAAIEAAYKSxD/BwCDAQAEAAYKSxD/BwCDAQA1AAQKfyYAAgQACgo8GzMbAH4CAAQACgo8GzMbAH4CAAAA.Gameslayer:BAAANQAECgYIDwAAAA==.Gankzilla:BAACNQAFFH8IAAMbAAIKcg+QBwCBAAAbAAIKlQ6QBwCBAAAMAAEKvw8UGQBQAAA1AAQKfysAAxsACgopGbIfAIMCABsACgopGbIfAIMCAAwAAQqnBACpABcAAAAA.Gavrill:BAAANQAECggICAAAAA==.',
Gi='Gila:BAAANQAECgQIBAAAAA==.Gizzle:BAACNQAFFH8GAAIHAAIKFg0NGQCDAAAHAAIKFg0NGQCDAAA1AAQKfygAAgcACgrrFPWGABkCAAcACgrrFPWGABkCAAAA.',
Gn='Gnarleywine:BAAANQAECgEIBAAAAA==.',
Go='Goldenstein:BAAANQAECgIIAgAAAA==.',
Gr='Greel:BAAANQADCgUICAAAAA==.Grimanack:BAAANQAECgEIAgAAAA==.Grændal:BAAANQAECgQICgABNQAFFAYIDAAEAEsQAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAABNQAECn8kAAMJAAgKhxGsBACdAQAJAAgKhxGsBACdAQAVAAEKqAs4WAE6AAAAAA==.Haywire:BAAANQAECgEIAQAAAA==.',
He='Helheim:BAAANQAECgEIAQAAAA==.Helldozer:BAABNQAECn8lAAIGAAgK1hQFOgBtAQAGAAgK1hQFOgBtAQAAAA==.Hexinu:BAABNQAECn8lAAMBAAgKaxtgOQC1AQABAAgKaxtgOQC1AQAGAAMK8A8jCQF6AAAAAA==.',
Hi='Hiyue:BAAANQAECggICgAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQAECgQIDQAAAA==.',
Hy='Hypnocide:BAEBNQAECn8vAAIEAAkKYxEsFQCdAQAEAAkKYxEsFQCdAQAAAA==.',
Ib='Ibuki:BAAANQAECgUICAABNQAFFAIICAAPAMoEAA==.',
Ig='Iguanajon:BAABNQAECn8gAAIOAAoKjRYgHwA0AgAOAAoKjRYgHwA0AgAAAA==.',
Il='Illandren:BAABNQAECn8jAAQKAAkK5w+/NACoAQAKAAgKowq/NACoAQAJAAkK2whXBgBDAQAVAAMKhRg7rQDUAAAAAA==.',
Im='Impsane:BAAANQAECgEIAwAAAA==.',
In='Innøminate:BAAANQAECggICgABNQAECgkJFgAQAPsOAA==.',
Ir='Irv:BAAANQAECgYIDwAAAA==.',
Is='Isellrocks:BAAANQAECgYICQAAAA==.',
Ja='Jaxxa:BAABNQAECn8XAAIVAAgKAw3CowC+AQAVAAgKAw3CowC+AQAAAA==.',
Je='Jeddiah:BAABNQAECn8YAAIMAAYKogsjMgArAQAMAAYKogsjMgArAQAAAA==.Jetstorm:BAAANQAECgYIBwAAAA==.',
Ji='Jinkès:BAABNQAECn8XAAIKAAcK9ghCIwDkAAAKAAcK9ghCIwDkAAAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAABNQAECn8bAAIHAAcKqx5TZwBlAgAHAAcKqx5TZwBlAgAAAA==.Judis:BAABNQAECn9BAAIbAAgKixc5DQCrAQAbAAgKixc5DQCrAQAAAA==.Justokevoker:BAABNQAECn89AAIcAAkKmRvrBACpAgAcAAkKmRvrBACpAgAAAA==.Justokpally:BAAANQAECgIIAwAAAA==.',
Ka='Kainda:BAAANQAECgEIAgAAAA==.Kairì:BAABNQAECn8bAAINAAgKzhWADQDfAQANAAgKzhWADQDfAQAAAA==.Kalifist:BAABNQAECn8uAAIYAAoK+xxmEgDJAgAYAAoK+xxmEgDJAgAAAA==.Kalku:BAAANQAECgcIEAAAAA==.Kanajotoma:BAAANQAECgMICAAAAA==.Karlai:BAABNQAECn8ZAAMaAAkKPRNZQQDAAQAaAAgKPRNZQQDAAQALAAEKAADSwwBBAAABNQAFFAYIDAAEAEsQAA==.Kayle:BAAANQAECgUIDAABNQAFFAIICAAPAMoEAA==.',
Ke='Keldrune:BAAANQAECgYICgAAAA==.Keleena:BAEBNQAECn8wAAIPAAkKoRqEGACAAgAPAAkKoRqEGACAAgAAAA==.Keze:BAABNQAECn88AAIVAAkK6h8iNwDFAgAVAAkK6h8iNwDFAgAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAECgoKJwAZAFMZAA==.Khorlyssa:BAAANQAECgUIBwABNQAECgoKJwAZAFMZAA==.',
Ki='Kielir:BAAANQAECgEIBAAAAA==.Killzshot:BAAANQADCgQIBAABNQAFFAEIAgAIAAAAAA==.Kinst:BAABNQAECn8iAAIVAAkKEBNYjwDrAQAVAAkKEBNYjwDrAQAAAA==.Kirito:BAAANQADCgEIAQAAAA==.Kitanyia:BAABNQAECn8cAAINAAkKsQ+zCwAHAgANAAkKsQ+zCwAHAgAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAAANQAECgYIEQAAAA==.',
Ko='Kordelia:BAABNQAECn8aAAICAAkKPRW4rgAlAgACAAkKPRW4rgAlAgABNQAECgoKJwAZAFMZAA==.',
Kr='Krench:BAAANQADCggIBwAAAA==.Kris:BAAANQADCgMIAwAAAA==.Krusty:BAAANQAECgEIAgAAAA==.',
Ku='Kuiper:BAAANQAECgEIAQAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBAAAAA==.Kyloon:BAABNQAECn8lAAMTAAkKAgWUYgAwAQATAAgKigSUYgAwAQAWAAMKtwRoHgBtAAAAAA==.Kyrah:BAABNQAECn8qAAISAAkKlRP0OwC5AQASAAkKlRP0OwC5AQAAAA==.',
La='Lakatryna:BAAANQAECgUJBwABNQAFFAYIGgAKAMEdAA==.Lamanira:BAAANQADCggIFgAAAA==.',
Le='Lejend:BAABNQAECn8qAAIdAAgKkRq3TgCYAQAdAAgKkRq3TgCYAQAAAA==.',
Li='Lithis:BAAANQAECgEIBAAAAA==.',
Ll='Llamakiller:BAAANQAECgIIBAABNQAECggIAQAIAAAAAA==.Llanedh:BAAANQAECgYIBgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAABNQAECn8ZAAIHAAcKkgf1swDxAAAHAAcKkgf1swDxAAAAAA==.Lorimuni:BAAANQAECgEIAQAAAA==.',
Ly='Lytol:BAABNQAECn8VAAICAAgKRBEOZgB9AQACAAgKRBEOZgB9AQAAAA==.',
Ma='Maenad:BAABNQAECn8eAAIBAAcKMRHeTABiAQABAAcKMRHeTABiAQAAAA==.Maeple:BAABNQAECn8cAAITAAgKTyBbGgCNAgATAAgKTyBbGgCNAgAAAA==.Mageh:BAAANQAECgQIBQAAAA==.Manamontana:BAAANQAECgUIBwAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAACNQAFFH8PAAIFAAcKTh8TBwAeAgAFAAcKTh8TBwAeAgA1AAQKfzgAAgUACgrwJFsEALoDAAUACgrwJFsEALoDAAAA.Mentock:BAAANQABCgUICAAAAA==.',
Mi='Miami:BAACNQAFFH8XAAIeAAcKfBpiAQBDAgAeAAcKfBpiAQBDAgA1AAQKfyMAAx4ACQopJSADAHsDAB4ACQopJSADAHsDABwAAQo2AMIpAAMAAAAA.Michelle:BAAANQADCgUIBwAAAA==.Mis:BAAANQAECgEIAgAAAA==.Missmaam:BAAANQAECgUIDAAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAACNQAFFH8PAAIfAAYK4SSbAAC5AQAfAAYK4SSbAAC5AQA1AAQKfzcAAh8ACgqNJhQAAJoDAB8ACgqNJhQAAJoDAAE1AAQKCQk2AB8A6yIA.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mudflap:BAAANQADCgMIAwAAAA==.Mushuwoonter:BAAANQAECgQIBAABNQAFFAMIBQATAGYMAA==.Muvok:BAAANQAECggIEgAAAA==.Muztang:BAABNQAECn8fAAIdAAgKlhVRTACgAQAdAAgKlhVRTACgAQAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAABNQAECn82AAIfAAkK6yK1BAAnAwAfAAkK6yK1BAAnAwAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQAECgUICAAAAA==.Nariar:BAAANQADCggICQABNQAFFAIICAAPAMoEAA==.Nateldin:BAAANQAECggIDwAAAA==.',
Ne='Nepe:BAAANQAECgcIEgAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgcIEwABNQAECgkJJwATALsPAA==.',
No='Nocainus:BAABNQAECn8lAAILAAgKHB4BFgDyAQALAAgKHB4BFgDyAQAAAA==.',
['Nø']='Nøtsure:BAABNQAECn8WAAMQAAkK+w40GABNAQAQAAkKcA40GABNAQAFAAMKHBJFhQC9AAAAAA==.',
Ob='Obsidia:BAABNQAECn8eAAISAAgKxAgLdwALAQASAAgKxAgLdwALAQAAAA==.',
Od='Oddlife:BAABNQAECn8ZAAMZAAYKZB7BQQAVAgAZAAYK1B3BQQAVAgAaAAIKzAwgnQBYAAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUIBQAAAA==.',
Ol='Oled:BAAANQADCgUIBQAAAA==.',
Om='Omari:BAAANQADCggICAAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQAECgEIAQABNQAECggIAQAIAAAAAA==.',
Op='Ophj:BAABNQAECn8zAAICAAoKOR9/WQDNAgACAAoKOR9/WQDNAgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQAECggIDwAIAAAAAA==.Orangutan:BAAANQAECgMICAAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAABNQAECn8hAAIBAAoKKhR+UwAZAgABAAoKKhR+UwAZAgAAAA==.',
Pa='Pallycam:BAAANQAECgIIAgAAAA==.Palmsdeep:BAAANQAECggIAgAAAA==.',
Pe='Pebda:BAAANQAECgMIAwAAAA==.Pebde:BAAANQAECgQICQAAAA==.Peluche:BAAANQAECgUIBQAAAA==.Pendor:BAAANQAECgEIBAAAAA==.Perilous:BAAANQAECgMIBwAAAA==.',
Ph='Pheanris:BAAANQADCgUIBAAAAA==.Phoelar:BAABNQAECn8XAAIFAAcK8Qw4NQD4AAAFAAcK8Qw4NQD4AAAAAA==.Phuumyn:BAABNQAECn8lAAIYAAgKnRskEQDTAQAYAAgKnRskEQDTAQAAAA==.',
Pi='Piccoblast:BAACNQAFFH8eAAICAAcKFxOhBgCCAQACAAcKFxOhBgCCAQA1AAQKfy0AAgIACgqVJDwtADQDAAIACgqVJDwtADQDAAAA.Pichus:BAAANQAECgQIBAABNQAECgoKMAABAOoTAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAACNQAFFH8KAAMTAAIKFyEbGQC1AAATAAIKFyEbGQC1AAAUAAIKIgToFACAAAA1AAQKfyIAAxMACgqyFeVqAN4BABMACAqeGuVqAN4BABQACAqcDMUzAIUBAAAA.Pippopper:BAAANQAECgIIAgABNQAFFAIIBgADACsiAA==.Pity:BAABNQAECn8YAAMEAAgKERQNHwAxAQAEAAgKERQNHwAxAQAgAAEKAABYKwAAAAAAAA==.',
Pl='Plutø:BAABNQAECn8WAAMZAAkKZAswHgCDAQAZAAkKZAswHgCDAQAaAAYKOQXzbQDmAAAAAA==.',
Po='Polylocks:BAAANQAECgUIBwAAAA==.Potatogg:BAAANQAECgEIBgAAAA==.',
Pr='Praeastra:BAEBNQAECn8kAAICAAkK5Qnr2QDTAQACAAkK5Qnr2QDTAQAAAA==.Prókill:BAAANQAECgYIEQAAAA==.',
Ps='Psychokitty:BAABNQAECn8vAAIOAAcKYBUfGACxAQAOAAcKYBUfGACxAQAAAA==.',
Pu='Purimus:BAAANQAECgEIAgAAAA==.',
Qu='Quilian:BAACNQAFFH8GAAITAAIK4CH9GAC2AAATAAIK4CH9GAC2AAA1AAQKfygAAhMACgotIGsPAEoDABMACgotIGsPAEoDAAAA.',
Ra='Raelynn:BAABNQAECn8lAAITAAgKgRz9KgAbAgATAAgKgRz9KgAbAgAAAA==.Rancier:BAAANQADCggIHAAAAA==.Rashalisk:BAAANQADCgUIBQAAAA==.',
Re='Rednecker:BAAANQAECgEIAQAAAA==.Redvex:BAABNQAECn83AAMSAAkKJiWBEwA/AwASAAkKJiWBEwA/AwAhAAEKRyM0aABSAAAAAA==.Reinhard:BAABNQAECn8dAAMXAAcKvg5UIwDjAAAXAAcKvg5UIwDjAAAHAAEKgwyMpQE0AAAAAA==.Relani:BAAANQAECggIEgABNQAECgkJIQAGAJ8YAA==.Rencraw:BAAANQAECgMIBQAAAA==.Renras:BAAANQAECgEIAgAAAA==.',
Rh='Rhain:BAAANQAECgcIEAAAAA==.Rhexy:BAAANQAECggIEwAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECn8xAAMMAAoKPhtIDACxAgAMAAoKPhtIDACxAgAbAAIKjA2UjgB3AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAFFAIICAAPAMoEAA==.Rootbeard:BAAANQAECgUJBwAAAA==.Rosanna:BAAANQAECgEIAwAAAA==.Rotyr:BAABNQAECn8fAAIWAAgKzRmqAQBkAgAWAAgKzRmqAQBkAgAAAA==.',
Ru='Ruana:BAEANQAECgMICAAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.Rubyrazor:BAAANQAECgEIAQAAAA==.',
Ry='Rye:BAABNQAECn8/AAMWAAoKnxxzBACCAgAWAAgKgR1zBACCAgATAAoKrxasLQANAgAAAA==.',
Sa='Santhela:BAAANQADCgIIAgAAAA==.Sarahbera:BAAANQAECgEIAQAAAA==.',
Sc='Scoobey:BAAANQAECgUIDgAAAA==.Scots:BAAANQADCggIIQAAAA==.Scubbs:BAABNQAECn8mAAIBAAoKphcdRABQAgABAAoKphcdRABQAgAAAA==.Scubbsboo:BAAANQADCggICQABNQAECgoKJgABAKYXAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Selenàgomez:BAAANQAECgEIAQAAAA==.Servantes:BAABNQAECn8kAAIOAAgKQw1ZHgBuAQAOAAgKQw1ZHgBuAQAAAA==.',
Sh='Shamancam:BAAANQAECgQICAAAAA==.Shammyhagar:BAAANQADCggIDAAAAA==.Shamp:BAAANQAECgIIAgAAAA==.Shamu:BAAANQAECgMIAwABNQAECgoKMwACADkfAA==.Shiggy:BAABNQAECn8cAAIiAAgKcghMGwC3AAAiAAgKcghMGwC3AAAAAA==.Shotya:BAABNQAECn8gAAIVAAgKmQzDbQBcAQAVAAgKmQzDbQBcAQAAAA==.',
Si='Sixpacktnt:BAAANQADCgcIEgAAAA==.Sixthdemon:BAAANQADCgUIFAAAAA==.Sixthknight:BAAANQAECgUIEQAAAA==.',
Sl='Slappi:BAABNQAECn8UAAIjAAcKIBDaFAA6AQAjAAcKIBDaFAA6AQAAAA==.',
Sn='Snacky:BAAANQAECgEIAQAAAA==.Snarkypony:BAAANQAECgEICgAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQAECgEIAQAAAA==.',
Sp='Spcecialk:BAAANQAECgIIAgAAAA==.Specialk:BAABNQAECn8wAAMGAAoKthX7IQDvAQAGAAoKthX7IQDvAQABAAIKLALmvABCAAAAAA==.Spellthat:BAAANQAFFAEIAQAAAA==.',
St='Stiner:BAAANQAECgIIAgAAAA==.Stirredihime:BAAANQAECgUICQAAAA==.Stormmage:BAAANQAECgMIBAABNQAECgkJKgALAKciAA==.',
Su='Sugarmomma:BAAANQAECgEIAQAAAA==.Sulph:BAABNQAECn8mAAIHAAkKgRlaQwDvAQAHAAkKgRlaQwDvAQAAAA==.Sundorei:BAAANQAECgIIBAAAAA==.',
Sv='Svalir:BAAANQAECgMIBQABNQAECggIAQAIAAAAAA==.',
Ta='Talshekar:BAABNQAECn8XAAIeAAgKSwbXDgDnAAAeAAgKSwbXDgDnAAAAAA==.Tarsis:BAAANQAECgUICQAAAA==.',
Te='Teiana:BAABNQAECn8lAAIHAAoKVCB8MwD+AgAHAAoKVCB8MwD+AgAAAA==.',
Th='Thaevin:BAABNQAECn8kAAIHAAkKmA3cewBaAQAHAAkKmA3cewBaAQAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAABNQAECn8dAAMUAAkKlRyMFwCbAgAUAAkKlRyMFwCbAgATAAMKNg7p2gCXAAAAAA==.Thingwan:BAABNQAECn8+AAIOAAoKBiGDCAA9AwAOAAoKBiGDCAA9AwAAAA==.Thunderman:BAABNQAECn8VAAIGAAQKohpbrwA0AQAGAAQKohpbrwA0AQAAAA==.',
Ti='Tinyakromajr:BAAANQAECgcIEwAAAA==.Tinystink:BAABNQAECn8XAAMSAAYK8xgOiQDQAQASAAYK8xgOiQDQAQAhAAEKAABshgAiAAABNQAECgcIEwAIAAAAAA==.',
To='Toddstephens:BAAANQAECgEIBgAAAA==.Tors:BAABNQAECn9FAAMFAAoKKxRJFQD9AQAFAAoKKxRJFQD9AQAOAAQKEgfcXQCQAAAAAA==.Totemdweller:BAAANQAECgEIBAAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQAECggIDwAIAAAAAA==.',
Tr='Trasky:BAABNQAECn8nAAIaAAoKFw0oNgBEAQAaAAoKFw0oNgBEAQAAAA==.Trollololo:BAABNQAECn8jAAIkAAgKjxlJCgAmAgAkAAgKjxlJCgAmAgAAAA==.Troy:BAABNQAECn8jAAICAAkK6Awp/QCTAQACAAkK6Awp/QCTAQAAAA==.Trylly:BAAANQADCgcIBwABNQAECgUIBwAIAAAAAA==.Trëze:BAACNQAFFH8FAAIVAAIKqxKiFQCeAAAVAAIKqxKiFQCeAAA1AAQKfzAAAxUACgqVHlsTAFIDABUACgqVHlsTAFIDAAoABQpbB51bALYAAAAA.',
Tt='Ttaartt:BAACNQAFFH8GAAIlAAIKDRNnFACJAAAlAAIKDRNnFACJAAA1AAQKfxwAAiUACQqBD4EaAB0CACUACQqBD4EaAB0CAAAA.',
Tw='Twing:BAAANQAECgEIAQABNQAECgEIAgAIAAAAAA==.',
Ty='Typh:BAABNQAECn8+AAIbAAoKrCREBACSAwAbAAoKrCREBACSAwAAAA==.',
Un='Undeaddemon:BAABNQAECn8XAAQSAAkKCBU1dwD9AQASAAgKXRc1dwD9AQAhAAIK4RgLVgB8AAARAAEKZQRSHgAqAAAAAA==.Undeaddh:BAAANQADCggICAABNQAECgkJFwASAAgVAA==.Undeadscaly:BAAANQAECggICgABNQAECgkJFwASAAgVAA==.Undignified:BAABNQAECn8rAAMbAAgKYhFlEQB3AQAbAAgKYhFlEQB3AQAMAAEKAADJtQAAAAAAAA==.Unholysixth:BAAANQAECgEIAwAAAA==.',
Va='Valoria:BAAANQADCgEIAQABNQAECgkJIwAKAOcPAA==.Vander:BAAANQAECggICgAAAA==.Vanidarr:BAAANQADCgQIBAAAAA==.Vazdra:BAAANQAECggIAQAAAA==.',
Ve='Verasia:BAAANQAECgMIBAAAAA==.',
Vi='Vidikan:BAAANQAECgMIAwAAAA==.Violett:BAABNQAECn8oAAIYAAoK5hybFACxAgAYAAoK5hybFACxAgAAAA==.Viserioñ:BAAANQAECgEIBAAAAA==.',
Vo='Voidwarranty:BAABNQAECn8wAAMBAAoK6hPiMgDUAQABAAoK6hPiMgDUAQAGAAYKaxj3iQCLAQAAAA==.Vortre:BAAANQAECgEIAQAAAA==.',
Vv='Vvumpscut:BAABNQAECn8qAAIBAAkK0xpJLwDnAQABAAkK0xpJLwDnAQAAAA==.',
Wa='Waldón:BAABNQAECn8eAAImAAcK+gWtAgASAQAmAAcK+gWtAgASAQAAAA==.',
We='Werrik:BAAANQADCgUIBQABNQAECgoKHwACAEkjAA==.',
Wi='Wildsoul:BAAANQAECgEIAgAAAA==.Wildthorne:BAAANQADCgEIAQABNQAFFAEIAgAIAAAAAA==.Wistywind:BAAANQABCggJCwAAAA==.',
Xc='Xclaw:BAAANQAECgUIBgAAAA==.',
Xe='Xeroxgravity:BAAANQAECgMIAwAAAA==.Xeroxshaman:BAAANQADCgQIAgAAAA==.',
Xi='Xilphira:BAAANQAECgQIBgAAAA==.Xirian:BAABNQAECn8UAAMdAAcKFQV2kgDoAAAdAAcKFQV2kgDoAAAiAAIKWAO6QQA5AAAAAA==.',
Xl='Xlithz:BAABNQAECn8kAAMiAAoKCw18IQBBAQAiAAgK/wt8IQBBAQAdAAcKTQqYjQD0AAAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQAECgQIBAAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAABNQAECn83AAIZAAoKHyHrDQBKAwAZAAoKHyHrDQBKAwAAAA==.Yondu:BAAANQADCggIFAABNQAECgYIEAAIAAAAAA==.Yourgrandma:BAAANQADCgQIBAABNQAECgYIEAAIAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAABNQAECn8jAAIDAAcKrwewNQACAQADAAcKrwewNQACAQAAAA==.Zavis:BAAANQAECgQIBAAAAA==.',
Ze='Zein:BAAANQADCggIHAAAAA==.Zemora:BAAANQAECgEIAwAAAA==.Zente:BAABNQAECn8nAAIVAAoKjA/VZABLAgAVAAoKjA/VZABLAgAAAA==.Zequill:BAABNQAECn8sAAMiAAkKKh+8BQAtAgAiAAgKBCK8BQAtAgANAAEKDg7HIQA7AAAAAA==.Zevdots:BAAANQAECgQIBAABNQAECgoKJAAVALYdAA==.Zevfury:BAAANQAECgUIBgABNQAECgoKJAAVALYdAA==.Zevsticles:BAABNQAECn8kAAIVAAoKth3QIwAIAwAVAAoKth3QIwAIAwAAAA==.',
Zh='Zhom:BAACNQAFFH8aAAIKAAYKwR1TBABHAQAKAAYKwR1TBABHAQA1AAQKfzIAAgoACgpSIWQNAAgDAAoACgpSIWQNAAgDAAAA.',
Zo='Zooj:BAABNQAECn8gAAIjAAgKsQhpFABBAQAjAAgKsQhpFABBAQAAAA==.Zorlak:BAAANQAECgUIDAAAAA==.',
Zu='Zulall:BAAANQAECgUIBwAAAA==.',
Zy='Zylofeather:BAAANQADCgUIBQAAAA==.',
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
