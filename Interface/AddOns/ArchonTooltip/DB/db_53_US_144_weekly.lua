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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Shaman-Elemental','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Subtlety','Warrior-Fury','Druid-Restoration','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Paladin-Retribution','Priest-Discipline','Priest-Holy','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','Evoker-Augmentation','Warrior-Arms','Evoker-Devastation','Monk-Brewmaster','Priest-Shadow','Warlock-Destruction','Paladin-Protection','Warrior-Protection','Mage-Frost','Evoker-Preservation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Account:BAAANQABCgQIBAAAAA==.',
Ae='Aetherr:BAAANQAECggIAQAAAA==.',
Ag='Agnithor:BAABNQAECn8oAAIBAAoK0BpmQwBTAgABAAoK0BpmQwBTAgAAAA==.',
Al='Aliadra:BAABNQAECn8fAAICAAoKqh8pSQDwAgACAAoKqh8pSQDwAgAAAA==.Alistor:BAAANQAECgEIAQAAAA==.Alistus:BAABNQAECn88AAMDAAoK/CMfAwDBAwADAAoK/CMfAwDBAwAEAAcKvx6cJAAiAgAAAA==.Alphá:BAAANQADCgcICAABNQAECgoKLAABAGsTAA==.',
Am='Amyliz:BAAANQABCggICgAAAA==.',
An='Angua:BAABNQAECn8oAAIFAAgK/hN/DAB9AQAFAAgK/hN/DAB9AQAAAA==.Anotheralt:BAABNQAECn8iAAMBAAgKkyT7BwBFAgABAAgKkyT7BwBFAgAGAAIKbhelDgFuAAAAAA==.',
Au='Aurius:BAAANQAECgUICQAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQAECgUIDgABNQAECggIFQAEAHUUAA==.Azhorra:BAAANQADCgYIDgAAAA==.Azzog:BAAANQAECgEIAQABNQAECgUICgAHAAAAAA==.Azül:BAABNQAECn8VAAIEAAgKdRSvHQDCAAAEAAgKdRSvHQDCAAAAAA==.',
Ba='Bacchanalian:BAAANQAECgUIBQABNQAECgcIHAABADERAA==.Baelrin:BAABNQAECn8dAAIGAAcKUhYrbwDTAQAGAAcKUhYrbwDTAQAAAA==.Baindyn:BAAANQAECgMIBAAAAA==.',
Be='Beaum:BAABNQAECn84AAICAAoKYiazAgDlAwACAAoKYiazAgDlAwAAAA==.',
Bi='Bigdrufus:BAAANQAECgEIAQAAAA==.',
Bl='Blackröse:BAABNQAECn8dAAMIAAkKvQzaBwDoAQAIAAkKsgzaBwDoAQAJAAcK1QRWRgAoAQAAAA==.Bladebane:BAABNQAECn8XAAIKAAcKpQOwQwBwAAAKAAcKpQOwQwBwAAAAAA==.Blight:BAAANQADCggICAABNQAFFAgIIgALALckAA==.Blksunshine:BAAANQADCggIFgAAAA==.',
Bo='Bolash:BAABNQAECn8sAAIMAAcKeB7UAgCrAQAMAAcKeB7UAgCrAQAAAA==.Bovinelover:BAABNQAECn82AAMNAAkKRCX9AQCxAwANAAkKRCX9AQCxAwAFAAEKAAC1YQAAAAAAAA==.',
Br='Bradthomas:BAAANQAECgUIBgAAAA==.Braindead:BAAANQAECgUIBgABNQAECggIFQAEAHUUAA==.Bruscha:BAAANQAECgIIAwAAAA==.',
Bu='Bulvhine:BAAANQAECgYIEgAAAA==.',
Ca='Cactusteeth:BAAANQAECgIIBAAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQAECgEIAQAAAA==.Cantatrix:BAAANQADCggIGAAAAA==.Capslok:BAAANQAECgUICQAAAA==.Captinmeat:BAAANQAFFAEIAgAAAA==.Castus:BAAANQAECgUICgAAAA==.',
Ce='Cecilx:BAABNQAECn8iAAIOAAgKsCMqBACtAgAOAAgKsCMqBACtAgAAAA==.Celiailia:BAAANQAECgQIBAAAAA==.Censøred:BAAANQAECgYIBgABNQAECgYIBgAHAAAAAA==.',
Ch='Chimerax:BAABNQAECn87AAMPAAoKQhwTBACkAgAPAAgKRx8TBACkAgAQAAgKshaPZAAsAgAAAA==.Chronic:BAAANQADCgYICgAAAA==.Chully:BAABNQAECn82AAIEAAkK6h6rEQDgAgAEAAkK6h6rEQDgAgAAAA==.',
Cl='Clairíty:BAAANQAECgcIEgAAAA==.Clegg:BAAANQAECgMIBAABNQAECggIFQAEAHUUAA==.Click:BAABNQAECn8XAAIRAAcK7w+OlQDdAQARAAcK7w+OlQDdAQAAAA==.',
Co='Comadore:BAABNQAECn8gAAISAAkKTBLDkQABAgASAAkKTBLDkQABAgAAAA==.',
Cr='Crankycad:BAAANQADCgcIDgAAAA==.Credan:BAEANQAECggICAAAAA==.',
Da='Daphe:BAAANQAECgUIEAAAAA==.Dardria:BAAANQAECgEIAQAAAA==.',
De='Deathslead:BAABNQAECn8gAAIRAAoKoRDpdQAkAgARAAoKoRDpdQAkAgAAAA==.Decrepe:BAABNQAECn81AAINAAkKmRzDCgCMAQANAAkKmRzDCgCMAQAAAA==.Delph:BAABNQAECn8lAAIMAAoKiBzCBADnAgAMAAoKiBzCBADnAgAAAA==.Deshal:BAAANQADCgcIJQAAAA==.Dethklock:BAAANQADCgEIAQAAAA==.',
Di='Discostar:BAABNQAECn8lAAMNAAkK4Q9IBgDrAQANAAkK4Q9IBgDrAQAFAAIKlATLnQBlAAAAAA==.Distill:BAAANQADCgQIBAABNQAFFAgIIgALALckAA==.',
Do='Dominicm:BAAANQAECggICQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCggIHAAAAA==.Droidgen:BAAANQADCgYIBgAAAA==.Druidcam:BAAANQAECgQICwAAAA==.',
Eb='Ebonhorn:BAAANQAECgMIBQAAAA==.',
Ei='Einari:BAABNQAECn8oAAMTAAgKtSREBACOAgATAAYKsSVEBACOAgAUAAgKNyFOHwCIAQAAAA==.Einark:BAAANQADCgQIBAAAAA==.',
Ek='Ekiim:BAAANQAECggICQAAAA==.',
El='Eldamari:BAAANQAECgYICAAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUIBQAAAA==.',
Er='Eridor:BAAANQAECgUIDAAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.Eshul:BAAANQADCgUIBQABNQAECgYIDQAHAAAAAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAABNQAECn8hAAIUAAoKExD7KwBNAQAUAAoKExD7KwBNAQAAAA==.',
Fa='Fabaztard:BAABNQAECn8aAAIFAAgKHw8AHAAGAQAFAAgKHw8AHAAGAQAAAA==.Faline:BAAANQAECgcIEwAAAA==.',
Fe='Felgetabouit:BAACNQAFFH8GAAIEAAIKwxjsBQCYAAAEAAIKwxjsBQCYAAA1AAQKfycAAgQACgoYHfEZAIoCAAQACgoYHfEZAIoCAAAA.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQADCgQIBgAAAA==.Feywynn:BAAANQADCgYIBgAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAABNQAECn8dAAIOAAgKHw7iFACtAQAOAAgKHw7iFACtAQAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgABNQAFFAMIBgAEAPMhAA==.',
Fo='Fontaine:BAAANQADCgUICAAAAA==.Foradin:BAAANQAECgUIDgAAAA==.Forky:BAAANQAECgEIBwAAAA==.Forloss:BAAANQAECgEIAQAAAA==.Foxknight:BAAANQAECgIIAwAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCggIBwAAAA==.',
Ft='Ftx:BAABNQAECn8UAAIVAAQKjhpbHADGAAAVAAQKjhpbHADGAAAAAA==.',
['Fí']='Fírefox:BAAANQAECgEIAQABNQAECgIIAwAHAAAAAA==.',
Ga='Gaern:BAABNQAECn8kAAMWAAoKyxhHNQBTAgAWAAkKwhpHNQBTAgAXAAMKyQpAPACyAAAAAA==.Gaidan:BAABNQAECn8WAAIFAAgKyRZ6PgAFAgAFAAgKyRZ6PgAFAgABNQAFFAUICwAEAI8UAA==.Gaidin:BAACNQAFFH8LAAIEAAUKjxT/BwCDAQAEAAUKjxT/BwCDAQA1AAQKfyIAAgQACgpOGDMbAH4CAAQACgpOGDMbAH4CAAAA.Gameslayer:BAAANQAECgYICAAAAA==.Gankzilla:BAACNQAFFH8GAAIYAAIKlQ7rBQB9AAAYAAIKlQ7rBQB9AAA1AAQKfygAAhgACgqaF7IfAIMCABgACgqaF7IfAIMCAAAA.Gavrill:BAAANQAECggICAAAAA==.',
Gi='Gila:BAAANQADCgcICAAAAA==.Gizzle:BAABNQAECn8lAAISAAoKUBL1hgAZAgASAAoKUBL1hgAZAgAAAA==.',
Gn='Gnarleywine:BAAANQAECgEIAQAAAA==.',
Go='Goldenstein:BAAANQAECgIIAQAAAA==.',
Gr='Greel:BAAANQADCgUICAAAAA==.Grimanack:BAAANQADCggIEQAAAA==.Grændal:BAAANQAECgQICAABNQAFFAUICwAEAI8UAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAABNQAECn8bAAMIAAcKQRKeAwBDAQAIAAcKQRKeAwBDAQARAAEKqAs4WAE6AAAAAA==.Haywire:BAAANQAECgEIAQAAAA==.',
He='Helldozer:BAABNQAECn8cAAIGAAcK6BUUIQA3AQAGAAcK6BUUIQA3AQAAAA==.Hexinu:BAABNQAECn8cAAMBAAcK3BqvLAAvAQABAAcK3BqvLAAvAQAGAAMK8A8jCQF6AAAAAA==.',
Hi='Hiyue:BAAANQAECggIBgAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQAECgQIBwAAAA==.',
Hy='Hypnocide:BAEBNQAECn8mAAIEAAgKPhMtCQB9AQAEAAgKPhMtCQB9AQAAAA==.',
Ib='Ibuki:BAAANQAECgUIBwABNQAFFAIIBgAOAMoEAA==.',
Ig='Iguanajon:BAABNQAECn8cAAINAAgKChcgHwA0AgANAAgKChcgHwA0AgAAAA==.',
Il='Illandren:BAABNQAECn8dAAMJAAkKhgy/NACoAQAJAAgKowq/NACoAQAIAAkKVwh+BAAbAQAAAA==.',
Im='Impsane:BAAANQAECgEIAQAAAA==.',
In='Innøminate:BAAANQAECgYIBgAAAA==.',
Ir='Irv:BAAANQAECgYIDwAAAA==.',
Is='Isellrocks:BAAANQAECgYICAAAAA==.',
Ja='Jaxxa:BAABNQAECn8XAAIRAAgKAw3JUgALAQARAAgKAw3JUgALAQAAAA==.',
Je='Jeddiah:BAAANQAECgUIEAAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAAANQAECgUICwAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAABNQAECn8bAAISAAcKqx5TZwBlAgASAAcKqx5TZwBlAgAAAA==.Judis:BAABNQAECn8xAAIYAAcKcxkCDQBfAQAYAAcKcxkCDQBfAQAAAA==.Justokevoker:BAABNQAECn82AAIZAAkKkxvrBACpAgAZAAkKkxvrBACpAgAAAA==.Justokpally:BAAANQAECgIIAwAAAA==.',
Ka='Kainda:BAAANQADCgIIAgAAAA==.Kairì:BAABNQAECn8aAAIMAAcKMBaADQDfAQAMAAcKMBaADQDfAQAAAA==.Kalifist:BAABNQAECn8qAAIVAAoKHBxmEgDJAgAVAAoKHBxmEgDJAgAAAA==.Kalku:BAAANQAECgYICgAAAA==.Kanajotoma:BAAANQAECgMIBQAAAA==.Karlai:BAABNQAECn8VAAMXAAkKPRNZQQDAAQAXAAgKPRNZQQDAAQAKAAEKAADSwwBBAAABNQAFFAUICwAEAI8UAA==.Kayle:BAAANQAECgUICgABNQAFFAIIBgAOAMoEAA==.',
Ke='Keldrune:BAAANQAECgMIAwAAAA==.Keleena:BAEBNQAECn8nAAIOAAgKQxqPCQApAgAOAAgKQxqPCQApAgAAAA==.Keze:BAABNQAECn82AAIRAAkKjB4eFwC/AQARAAkKjB4eFwC/AQAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAECgoKJAAWAMsYAA==.Khorlyssa:BAAANQAECgQIBAABNQAECgoKJAAWAMsYAA==.',
Ki='Kielir:BAAANQAECgEIAQAAAA==.Killzshot:BAAANQADCgQIBAABNQAFFAEIAgAHAAAAAA==.Kinst:BAABNQAECn8gAAIRAAcKpBRYjwDrAQARAAcKpBRYjwDrAQAAAA==.Kitanyia:BAABNQAECn8cAAIMAAkKsQ+zCwAHAgAMAAkKsQ+zCwAHAgAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAAANQAECgQICAAAAA==.',
Ko='Kordelia:BAABNQAECn8WAAICAAkK3BPMWgAHAQACAAkK3BPMWgAHAQABNQAECgoKJAAWAMsYAA==.',
Kr='Krench:BAAANQADCggIBwAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBAAAAA==.Kyloon:BAABNQAECn8eAAMTAAkKEQRoHgBtAAAUAAgKQwP7pQAjAQATAAMKtwRoHgBtAAAAAA==.Kyrah:BAABNQAECn8iAAIQAAgK+xQWFwCYAQAQAAgK+xQWFwCYAQAAAA==.',
La='Lakatryna:BAAANQAECgUJBQABNQAFFAYIGgAJAMEdAA==.Lamanira:BAAANQADCggIFgAAAA==.',
Le='Lejend:BAABNQAECn8jAAIaAAgKGhmgIQB9AQAaAAgKGhmgIQB9AQAAAA==.',
Li='Lithis:BAAANQAECgEIAQAAAA==.',
Ll='Llamakiller:BAAANQAECgEIAQABNQAECgMIBAAHAAAAAA==.Llanedh:BAAANQAECgIIAgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAAANQAECgYIEgAAAA==.Lorimuni:BAAANQADCggIFAAAAA==.',
Ly='Lytol:BAAANQAECgcIEQAAAA==.',
Ma='Maenad:BAABNQAECn8cAAIBAAcKMRGLHQB1AQABAAcKMRGLHQB1AQAAAA==.Maeple:BAAANQAECgYIEwAAAA==.Mageh:BAAANQAECgEIAQAAAA==.Manamontana:BAAANQAECgQIBQAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAACNQAFFH8OAAIFAAYK3B8TBwAeAgAFAAYK3B8TBwAeAgA1AAQKfy8AAgUACgovIVsEALoDAAUACgovIVsEALoDAAAA.Mentock:BAAANQABCgUICAAAAA==.',
Mi='Miami:BAACNQAFFH8XAAIbAAcKfBpiAQBDAgAbAAcKfBpiAQBDAgA1AAQKfyMAAxsACQopJSADAHsDABsACQopJSADAHsDABkAAQo2AMIpAAMAAAAA.Michelle:BAAANQADCgEIAQAAAA==.Mis:BAAANQAECgEIAQAAAA==.Missmaam:BAAANQAECgUICwAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAACNQAFFH8MAAIcAAUKXx2yAgC0AQAcAAUKXx2yAgC0AQA1AAQKfycAAhwACgq1I+0BAMMBABwACgq1I+0BAMMBAAE1AAQKCQk2ABwA6yIA.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mushuwoonter:BAAANQAECgQIBAABNQAFFAMIBQAUAGYMAA==.Muvok:BAAANQAECgYIDAAAAA==.Muztang:BAABNQAECn8YAAIaAAcK/xUELgBUAQAaAAcK/xUELgBUAQAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAABNQAECn82AAIcAAkK6yJyAQDwAQAcAAkK6yJyAQDwAQAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQAECgUIBwAAAA==.Nariar:BAAANQADCggICQABNQAFFAIIBgAOAMoEAA==.Nateldin:BAAANQAECggIDgAAAA==.',
Ne='Nepe:BAAANQAECgYICgAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgYIDwABNQAECgkJJgAUALsPAA==.',
No='Nocainus:BAABNQAECn8cAAIKAAcKSR2wCgCXAQAKAAcKSR2wCgCXAQAAAA==.',
['Nø']='Nøtsure:BAAANQAECgUICwABNQAECgYIBgAHAAAAAA==.',
Ob='Obsidia:BAABNQAECn8cAAIQAAcK8AguTwDmAAAQAAcK8AguTwDmAAAAAA==.',
Od='Oddlife:BAABNQAECn8ZAAMWAAYKZB7BQQAVAgAWAAYK1B3BQQAVAgAXAAIKzAwgnQBYAAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUIBQAAAA==.',
Ol='Oled:BAAANQADCgUIBQAAAA==.',
Om='Omari:BAAANQADCggICAAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQADCgIIAwABNQAECgMIBAAHAAAAAA==.',
Op='Ophj:BAABNQAECn8vAAICAAoKnx1/WQDNAgACAAoKnx1/WQDNAgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQAECggICQAHAAAAAA==.Orangutan:BAAANQAECgMIBQAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAABNQAECn8gAAIBAAkKIBV+UwAZAgABAAkKIBV+UwAZAgAAAA==.',
Pa='Pallycam:BAAANQAECgIIAgAAAA==.',
Pe='Pebda:BAAANQAECgMIAwAAAA==.Pebde:BAAANQAECgQICAAAAA==.Peluche:BAAANQAECgUIBAAAAA==.Pendor:BAAANQAECgEIAQAAAA==.Perilous:BAAANQAECgMIBQAAAA==.',
Ph='Phoelar:BAABNQAECn8VAAIFAAcKzQwxWAB0AQAFAAcKzQwxWAB0AQAAAA==.Phuumyn:BAABNQAECn8cAAIVAAcKAx0GCACPAQAVAAcKAx0GCACPAQAAAA==.',
Pi='Piccoblast:BAACNQAFFH8eAAICAAcKFxMoAwCPAQACAAcKFxMoAwCPAQA1AAQKfyoAAgIACgrqIjwtADQDAAIACgrqIjwtADQDAAAA.Pichus:BAAANQAECgQIBAABNQAECgoKLAABAGsTAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAACNQAFFH8KAAMUAAIKFyHXDwC8AAAUAAIKFyHXDwC8AAAdAAIKIgToFACAAAA1AAQKfx8AAx0ACgpaDsUzAIUBAB0ACAqcDMUzAIUBABQACAqeGkE7ABcBAAAA.Pippopper:BAAANQAECgIIAgABNQAECgoKPAADAPwjAA==.Pity:BAABNQAECn8UAAIEAAcK9BR2FQAEAQAEAAcK9BR2FQAEAQAAAA==.',
Pl='Plutø:BAAANQAECgYICQAAAA==.',
Po='Polylocks:BAAANQAECgUIBwAAAA==.Potatogg:BAAANQAECgEIBgAAAA==.',
Pr='Praeastra:BAEBNQAECn8iAAICAAkK5Qnr2QDTAQACAAkK5Qnr2QDTAQAAAA==.Prókill:BAAANQAECgUICgAAAA==.',
Ps='Psychokitty:BAABNQAECn8oAAINAAcKthPWFAAdAQANAAcKthPWFAAdAQAAAA==.',
Qu='Quilian:BAABNQAECn8lAAIUAAkKUyJrDwBKAwAUAAkKUyJrDwBKAwAAAA==.',
Ra='Raelynn:BAABNQAECn8cAAIUAAcK3R1PFADPAQAUAAcK3R1PFADPAQAAAA==.Rancier:BAAANQADCggIHAAAAA==.Rashalisk:BAAANQADCgUIBQAAAA==.',
Re='Rednecker:BAAANQABCgIIAgAAAA==.Redvex:BAABNQAECn82AAMQAAkKFSRJCgAEAgAQAAkKFSRJCgAEAgAeAAEKRyM0aABSAAAAAA==.Reinhard:BAABNQAECn8ZAAMfAAcKKg0PFQDgAAAfAAcKKg0PFQDgAAASAAEKgwyMpQE0AAAAAA==.Relani:BAAANQAECggICAAAAA==.Rencraw:BAAANQAECgMIBQAAAA==.Renras:BAAANQADCggJEwAAAA==.',
Rh='Rhain:BAAANQAECgcICwAAAA==.Rhexy:BAAANQAECgcIDQAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECn8oAAMLAAoKDhlIDACxAgALAAoKDhlIDACxAgAYAAIKjA2UjgB3AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAFFAIIBgAOAMoEAA==.Rootbeard:BAAANQAECgUJBgAAAA==.Rosanna:BAAANQAECgEIAgAAAA==.Rotyr:BAABNQAECn8ZAAITAAcKrhbfAADoAQATAAcKrhbfAADoAQAAAA==.',
Ru='Ruana:BAEANQAECgMIBQAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.',
Ry='Rye:BAABNQAECn83AAMTAAoKaRpzBACCAgATAAcKqR9zBACCAgAUAAoKcRQOUQAwAgAAAA==.',
Sa='Santhela:BAAANQADCgIIAgAAAA==.Sarahbera:BAAANQABCgIIAgAAAA==.',
Sc='Scoobey:BAAANQAECgUIDAAAAA==.Scots:BAAANQADCggIGgAAAA==.Scubbs:BAABNQAECn8jAAIBAAoKphcdRABQAgABAAoKphcdRABQAgAAAA==.Scubbsboo:BAAANQADCggICQABNQAECgoKIwABAKYXAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Servantes:BAABNQAECn8bAAINAAcK0AvMFAAdAQANAAcK0AvMFAAdAQAAAA==.',
Sh='Shamancam:BAAANQAECgQICAAAAA==.Shammyhagar:BAAANQADCggIDAAAAA==.Shamp:BAAANQAECgIIAgAAAA==.Shiggy:BAABNQAECn8ZAAIgAAgKogQ7EwCbAAAgAAgKogQ7EwCbAAAAAA==.Shotya:BAABNQAECn8XAAIRAAcKkg3kSQAgAQARAAcKkg3kSQAgAQAAAA==.',
Si='Sixpacktnt:BAAANQADCgYICwAAAA==.Sixthdemon:BAAANQADCgUIDwAAAA==.Sixthknight:BAAANQAECgYIDAAAAA==.',
Sl='Slappi:BAAANQAECgYIEQAAAA==.',
Sn='Snarkypony:BAAANQAECgEIAQAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQAECgEIAQAAAA==.',
Sp='Spcecialk:BAAANQAECgEIAQAAAA==.Specialk:BAABNQAECn8rAAIGAAoKgxUVDACyAQAGAAoKgxUVDACyAQAAAA==.Spellthat:BAAANQAFFAEIAQAAAA==.',
St='Stiner:BAAANQAECgIIAgAAAA==.Stirredihime:BAAANQAECgUICAAAAA==.Stormmage:BAAANQAECgMIAwABNQAECgkJKAAKAKciAA==.',
Su='Sugarmomma:BAAANQADCgcIBwAAAA==.Sulph:BAABNQAECn8cAAISAAcKzBxuHwClAQASAAcKzBxuHwClAQAAAA==.Sundorei:BAAANQAECgIIBAAAAA==.',
Sv='Svalir:BAAANQAECgMIBAAAAA==.',
Ta='Talshekar:BAAANQAECgYIDQAAAA==.Tarsis:BAAANQAECgUICAAAAA==.',
Te='Teiana:BAABNQAECn8kAAISAAkK2SB8MwD+AgASAAkK2SB8MwD+AgAAAA==.',
Th='Thaevin:BAABNQAECn8bAAISAAgKmw6yxwCMAQASAAgKmw6yxwCMAQAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAABNQAECn8dAAMdAAkKlRyMFwCbAgAdAAkKlRyMFwCbAgAUAAMKNg7p2gCXAAAAAA==.Thingwan:BAABNQAECn81AAINAAoK3yCDCAA9AwANAAoK3yCDCAA9AwAAAA==.Thunderman:BAABNQAECn8VAAIGAAQKohpbrwA0AQAGAAQKohpbrwA0AQAAAA==.',
Ti='Tinyakromajr:BAAANQAECgYIDAABNQAECgYIFwAQAPMYAA==.Tinystink:BAABNQAECn8XAAMQAAYK8xgOiQDQAQAQAAYK8xgOiQDQAQAeAAEKAABshgAiAAAAAA==.',
To='Tors:BAABNQAECn87AAMFAAoKuBISBQD8AQAFAAkKJxUSBQD8AQANAAQKEgfcXQCQAAAAAA==.Totemdweller:BAAANQAECgEIAQAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQAECggICQAHAAAAAA==.',
Tr='Trasky:BAABNQAECn8fAAIXAAgKPA9VSQCXAQAXAAgKPA9VSQCXAQAAAA==.Trollololo:BAABNQAECn8cAAIhAAcKKhpJCgAmAgAhAAcKKhpJCgAmAgAAAA==.Troy:BAABNQAECn8cAAICAAgKCAz/fQDEAAACAAgKCAz/fQDEAAAAAA==.Trylly:BAAANQADCgcIBwABNQAECgUIBwAHAAAAAA==.Trëze:BAABNQAECn8rAAMRAAkKTh9bEwBSAwARAAkKTh9bEwBSAwAJAAUKWwedWwC2AAAAAA==.',
Tt='Ttaartt:BAACNQAFFH8GAAIiAAIKDRNnFACJAAAiAAIKDRNnFACJAAA1AAQKfxwAAiIACQqBD4EaAB0CACIACQqBD4EaAB0CAAAA.',
Ty='Typh:BAABNQAECn84AAIYAAoKUyJEBACSAwAYAAoKUyJEBACSAwAAAA==.',
Un='Undeaddemon:BAABNQAECn8VAAMQAAgKJRc1dwD9AQAQAAgKGhc1dwD9AQAeAAIK4RgLVgB8AAAAAA==.Undeaddh:BAAANQADCggICAABNQAECggIFQAQACUXAA==.Undeadscaly:BAAANQAECgYICAABNQAECggIFQAQACUXAA==.Undignified:BAABNQAECn8jAAIYAAcKNhB1FwAMAQAYAAcKNhB1FwAMAQAAAA==.Unholysixth:BAAANQAECgEIAgAAAA==.',
Va='Vander:BAAANQAECgIIAgAAAA==.Vanidarr:BAAANQADCgQIBAAAAA==.',
Ve='Verasia:BAAANQAECgIIAgAAAA==.',
Vi='Vidikan:BAAANQADCgIIAwAAAA==.Violett:BAABNQAECn8iAAIVAAoKbBybFACxAgAVAAoKbBybFACxAgAAAA==.Viserioñ:BAAANQAECgEIAQAAAA==.',
Vo='Voidwarranty:BAABNQAECn8sAAMBAAoKaxPJGQCMAQABAAoKaxPJGQCMAQAGAAYKaxj3iQCLAQAAAA==.Vortre:BAAANQABCgcIBwAAAA==.',
Vv='Vvumpscut:BAABNQAECn8pAAIBAAkK0xokDAAGAgABAAkK0xokDAAGAgAAAA==.',
Wa='Waldón:BAABNQAECn8YAAIjAAcK+gVyAQAVAQAjAAcK+gVyAQAVAQAAAA==.',
We='Werrik:BAAANQADCgUIBQABNQAECgoKHwACAEkjAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wistywind:BAAANQABCggJCwAAAA==.',
Xc='Xclaw:BAAANQAECgUIBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgMIAwAAAA==.Xeroxshaman:BAAANQADCgQIAgAAAA==.',
Xi='Xilphira:BAAANQAECgMIAwAAAA==.Xirian:BAAANQAECgYIEwAAAA==.',
Xl='Xlithz:BAABNQAECn8dAAMgAAoKwAp8IQBBAQAgAAgKAAt8IQBBAQAaAAQKcAgEnQBsAAAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQADCgUIBQAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAABNQAECn8xAAIWAAoK9iDrDQBKAwAWAAoK9iDrDQBKAwAAAA==.Yondu:BAAANQADCgcIEQABNQAECgYIDgAHAAAAAA==.Yourgrandma:BAAANQADCgQIBAABNQAECgYIDgAHAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAABNQAECn8eAAIDAAcKrwcrIAD8AAADAAcKrwcrIAD8AAAAAA==.Zavis:BAAANQADCggIEwAAAA==.',
Ze='Zein:BAAANQADCggIHAAAAA==.Zente:BAABNQAECn8kAAIRAAoKsQ3VZABLAgARAAoKsQ3VZABLAgAAAA==.Zequill:BAABNQAECn8jAAIgAAgKvSHTAQAZAgAgAAgKvSHTAQAZAgAAAA==.Zevdots:BAAANQAECgQIBAABNQAECgkJIwARADAfAA==.Zevfury:BAAANQAECgUIBQABNQAECgkJIwARADAfAA==.Zevsticles:BAABNQAECn8jAAIRAAkKMB/QIwAIAwARAAkKMB/QIwAIAwAAAA==.',
Zh='Zhom:BAACNQAFFH8aAAIJAAYKwR0hAgBZAQAJAAYKwR0hAgBZAQA1AAQKfzEAAgkACgpSIWQNAAgDAAkACgpSIWQNAAgDAAAA.',
Zo='Zooj:BAABNQAECn8XAAIkAAcKIAltDgAXAQAkAAcKIAltDgAXAQAAAA==.Zorlak:BAAANQAECgUICgAAAA==.',
Zu='Zulall:BAAANQAECgMIAwAAAA==.',
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
