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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Paladin-Retribution','Shaman-Elemental','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warrior-Arms','DeathKnight-Unholy','Warrior-Protection','Warlock-Destruction','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Priest-Holy','Priest-Shadow','Rogue-Assassination','Mage-Arcane','Hunter-BeastMastery','Warrior-Fury','Paladin-Protection','Rogue-Subtlety','Druid-Restoration','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Mage-Fire','Mage-Frost','Warlock-Affliction','Druid-Guardian','DemonHunter-Devourer','Hunter-Survival','Paladin-Holy','Shaman-Enhancement','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAABNQAECn8oAAICAAoK0w15KQDUAQACAAoK0w15KQDUAQABNQAECgoKQgADAGQgAA==.',
Ae='Aeolos:BAAANQADCggIEgAAAA==.Aesthetic:BAAANQAECgcIDgABNQAFFAcIGAAEAHUbAA==.',
Ag='Agrios:BAACNQAFFH8KAAIFAAMKrQ6NDwDQAAAFAAMKrQ6NDwDQAAA1AAQKf0cAAgUACgoiH9UNAKgCAAUACgoiH9UNAKgCAAAA.',
Ai='Aiellee:BAAANQAECgUICAAAAA==.',
Ak='Akias:BAAANQAECgYIEQAAAA==.',
Al='Alexandra:BAAANQAECgUICgABNQAFFAIIAgABAAAAAA==.Alliekill:BAAANQAECgMIAwABNQAECgkJHgAGAAYPAA==.Altaurus:BAAANQAECgUIDQAAAA==.Alynnei:BAAANQAECggIDgABNQAFFAIIAgABAAAAAA==.',
Am='Amare:BAAANQAECgUIDwAAAA==.Amiria:BAAANQADCggICwAAAA==.',
An='Andros:BAABNQAECn8fAAIHAAcK5RSRlQCwAQAHAAcK5RSRlQCwAQAAAA==.Anekaatwo:BAAANQAECgEIAQAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Araxe:BAAANQAECgQIBAABNQAECgoKPAAIAFAbAA==.Arroyo:BAABNQAECn86AAIJAAoKJCAcEQAuAwAJAAoKJCAcEQAuAwAAAA==.',
As='Askadar:BAACNQAFFH8KAAIKAAQK6SUrAQA8AQAKAAQK6SUrAQA8AQA1AAQKfywAAgoACgr4JiEAAAsEAAoACgr4JiEAAAsEAAAA.',
Az='Azora:BAABNQAECn8kAAMLAAoKRhesDAAtAgALAAcK3xmsDAAtAgAHAAgKxxSmhwDTAQAAAA==.Azzura:BAAANQAECgEIAQAAAA==.',
Ba='Baheem:BAAANQAECgQICwAAAA==.Bams:BAABNQAECn8iAAIMAAgKnBZAfQCUAQAMAAgKnBZAfQCUAQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECn8oAAMNAAoKeR1uCQDbAgANAAoKeR1uCQDbAgAOAAEK3AGoKAAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECn8nAAIDAAoK6hHMcgBJAgADAAoK6hHMcgBJAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQAECgYIDwAAAA==.',
Bi='Bifrons:BAAANQADCgYIGAAAAA==.Bigdill:BAAANQAECgQIBAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIBgAAAA==.Bluè:BAAANQAECgQIBgAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCggIHwAAAA==.Boolil:BAABNQAECn8YAAIMAAkK+QfFaABIAQAMAAkK+QfFaABIAQABNQAECgoKQwAPAC0PAA==.Boolove:BAAANQAECgcICAABNQAECgoKQwAPAC0PAA==.Booloved:BAABNQAECn9DAAQPAAoKLQ8dBQCLAQAPAAkKAg8dBQCLAQAQAAoKOwecXwCHAQARAAkKHgSLPABGAQAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Brotato:BAAANQAECgUIBgABNQAFFAMIBgAGAIYSAA==.Broxx:BAAANQADCgcICQAAAA==.',
Bu='Bulwei:BAAANQAECgYICAAAAA==.',
Bw='Bwimbosawme:BAAANQAFFAMIAgABNQAFFAMICQASAA0bAA==.',
By='Byssrak:BAAANQAECgYIBwAAAA==.',
Ca='Calmcarnage:BAAANQAECgEIAQAAAA==.Carmêl:BAAANQAECgUIBgABNQAECgoKNAATAH4gAA==.Cattiebuzz:BAAANQADCgIIAgABNQAECgkJLgAUAKgaAA==.Cattiegreen:BAABNQAECn8uAAIUAAkKqBoAaQBCAgAUAAkKqBoAaQBCAgAAAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Chopshop:BAAANQAECgEIAQAAAA==.Christopher:BAABNQAECn8pAAITAAoK0xXXgwB3AgATAAoK0xXXgwB3AgAAAA==.',
Co='Consolata:BAAANQADCgMIAwAAAA==.Costica:BAAANQADCgUIBQAAAA==.',
Cr='Creepychaos:BAAANQADCggICAABNQAECgcIDwABAAAAAA==.Creepydemise:BAAANQAECgcIDwAAAA==.Creepydrunk:BAAANQADCggIEQABNQAECgcIDwABAAAAAA==.Croixsmash:BAABNQAECn8bAAMIAAkKSBXmkwDqAQAIAAgKFhXmkwDqAQAVAAMKpRK4HwDAAAAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.Curse:BAAANQAECgMIAwAAAA==.',
Cy='Cylvanna:BAAANQAECgUIDgAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Darkrest:BAAANQADCggIFwAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgkJGwAIAEgVAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECn8zAAIDAAoKJg2ZqgDKAQADAAoKJg2ZqgDKAQAAAA==.Dawnn:BAAANQAECgUICwAAAA==.',
De='Deanwnchestr:BAABNQAECn8eAAITAAgKOgTEwwD2AAATAAgKOgTEwwD2AAAAAA==.Deatnshadow:BAAANQAECggIEAAAAA==.Delyrius:BAAANQADCggICAABNQAECgUIBAABAAAAAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgUICQAAAA==.',
Do='Dogeatdog:BAAANQADCggIFgAAAA==.Dorus:BAAANQADCgQIBAAAAA==.',
Dr='Draakell:BAABNQAECn8ZAAIJAAgK2Q6rMQAyAQAJAAgK2Q6rMQAyAQAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAABNQAECn8XAAMHAAYKLAYTnQDnAAAHAAYKLAYTnQDnAAALAAMKagFlfwAtAAAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.Dryrain:BAABNQAECn8VAAMWAAoKzA8IFQCjAQAWAAkKzA8IFQCjAQADAAIKMQPBeQErAAAAAA==.',
Du='Dudè:BAAANQAECgYIEQAAAA==.',
['Dâ']='Dâggèr:BAACNQAFFH8JAAMSAAMKDRsqDwD3AAASAAMKDRsqDwD3AAAXAAEKqAPiIQA+AAA1AAQKfxwAAhIACAruIUAFAKYCABIACAruIUAFAKYCAAAA.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggIDAAAAA==.',
El='Eladawn:BAAANQAECgYIBgABNQAFFAcIDAAMAE8RAA==.Elarae:BAABNQAECn8pAAIUAAoKahdHOAA3AgAUAAoKahdHOAA3AgAAAA==.Elawen:BAAANQADCgYIBQAAAA==.Elementblah:BAABNQAECn8UAAIEAAYKng9/mgBjAQAEAAYKng9/mgBjAQAAAA==.Elfkinn:BAACNQAFFH8dAAIFAAUKkyAsCgAZAQAFAAUKkyAsCgAZAQA1AAQKfzEAAwUACgqsIUcKAN0CAAUACgqsIUcKAN0CABgAAgqjAch2ABQAAAAA.Elivaniel:BAAANQADCgYIBgAAAA==.Ellemere:BAAANQAECgUIBgABNQAFFAIIAgABAAAAAA==.',
Em='Emerita:BAAANQAECgUIBQAAAA==.Emeryl:BAAANQAECgQIBQABNQAFFAcIGAAEAHUbAA==.Empathyforyo:BAABNQAECn8rAAMUAAkKdRjsSgCNAgAUAAgKXRvsSgCNAgAZAAQKAAlQVwDIAAAAAA==.',
Eq='Equinox:BAABNQAECn8eAAIFAAoKexBoOwAZAgAFAAoKexBoOwAZAgAAAA==.',
Er='Eredris:BAAANQADCgIIAgAAAA==.Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAABNQAECn8lAAMaAAkKZhrTDAD3AQAaAAgKshrTDAD3AQAbAAcKchjQTwBaAQAAAA==.',
Es='Eshtar:BAAANQAECgUIDAAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAABNQAECn8XAAIZAAgK2BPhKgD0AQAZAAgK2BPhKgD0AQAAAA==.Exzanthia:BAAANQADCggICwAAAA==.',
Ey='Eyln:BAABNQAECn8dAAIZAAcKeQubIQAkAQAZAAcKeQubIQAkAQAAAA==.',
Fa='Falkor:BAABNQAECn88AAIcAAoKjheTEgCDAgAcAAoKjheTEgCDAgAAAA==.Fayway:BAABNQAECn89AAMYAAoK9h3HCgDkAgAYAAoK9h3HCgDkAgAFAAEKAABoyQAZAAAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECn89AAIdAAoKwh8MBADFAgAdAAoKwh8MBADFAgAAAA==.',
Fi='Figgy:BAABNQAECn8mAAIHAAoKgA6ZRgDLAQAHAAoKgA6ZRgDLAQAAAA==.Firepower:BAABNQAECn8/AAQTAAoKkh3CNABQAgATAAoKkh3CNABQAgAeAAIKVw7+BgBwAAAfAAEKvhl5QwA9AAABNQAFFAMIBgAGAIYSAA==.',
Fo='Forevershy:BAAANQADCggIJgAAAA==.',
Fr='Fries:BAEANQAECggIDwAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Ge='Georgiee:BAAANQAECgEIAgAAAA==.',
Gi='Giggles:BAABNQAECn8fAAIEAAgKjhMCSQB4AQAEAAgKjhMCSQB4AQAAAA==.',
Go='Goh:BAAANQAECgQIBAAAAA==.Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIDgABNQAFFAUIBQAMAMkPAA==.Gothrim:BAAANQADCggICAAAAA==.',
Gr='Greenbean:BAAANQADCggJCAABNQAFFAUIHQAFAJMgAA==.Groto:BAABNQAECn8UAAIgAAcK2A13DQCDAQAgAAcK2A13DQCDAQAAAA==.Grrum:BAAANQAECgUIBAAAAA==.Grèy:BAAANQAECgYIDgAAAA==.',
Gu='Gullible:BAAANQAECgYICwAAAA==.',
Ha='Hairy:BAAANQAECgQIBQAAAA==.Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQAECggIDgAAAA==.Hanjo:BAABNQAECn8XAAIKAAgKbRuMFADeAQAKAAgKbRuMFADeAQAAAA==.Hatookorr:BAACNQAFFH8GAAIGAAMKhhJAEQC5AAAGAAMKhhJAEQC5AAA1AAQKfx0AAgYACApnHlMiAKMCAAYACApnHlMiAKMCAAAA.',
He='Heledrianis:BAAANQAECgYIDQAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Ho='Hornet:BAAANQADCggIJAAAAA==.',
Hy='Hydé:BAACNQAFFH8ZAAMhAAcK1BoVAQBRAQAhAAYKiyAVAQBRAQAdAAEK9wPOAwBGAAA1AAQKfx4AAiEACgq2HFILALgCACEACgq2HFILALgCAAAA.',
Ik='Ikwon:BAAANQADCgUIBwAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
In='Intuned:BAAANQAFFAIIAQABNQAFFAMICQASAA0bAA==.',
Is='Ishmael:BAAANQAECgQIBAAAAA==.Ismeldbad:BAAANQAECgUICQABNQAECgoKIAAXAMYaAA==.',
Ja='Jaland:BAAANQABCgQIBAAAAA==.',
Je='Jellybreak:BAABNQAECn8mAAIFAAcKqxDYMABIAQAFAAcKqxDYMABIAQAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAABNQAECn8XAAIQAAgKZhKXfwCaAQAQAAgKZhKXfwCaAQAAAA==.Kateblue:BAABNQAECn8XAAIFAAgKqQyXYABNAQAFAAgKqQyXYABNAQAAAA==.',
Ke='Keeble:BAAANQAECggIEgAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAABNQAECn8oAAMgAAoKnRb/BAAAAgAgAAoKnRb/BAAAAgAHAAMKWAWQIgF9AAAAAA==.Kelsyyr:BAAANQAECgYIBwABNQAECgoKKAAgAJ0WAA==.Kenpachi:BAAANQADCgEIAQAAAA==.Kethry:BAAANQAECgYIBwAAAA==.',
Ki='Kidneysweeny:BAABNQAECn8gAAMXAAoKxhrWIQC9AQAXAAgKIxrWIQC9AQASAAQKXRuqNgCiAAAAAA==.Kikyou:BAABNQAECn8tAAMCAAkKqhzCIgACAgAJAAcKKyB5OQA+AgACAAkKHBXCIgACAgABNQAFFAcIIQAiAIgeAA==.Kim:BAABNQAECn8cAAIjAAgKbA9pCADOAQAjAAgKbA9pCADOAQAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQAECgQIBwAAAA==.Krelbelorll:BAABNQAECn8lAAIiAAoKyQ/IKAD+AQAiAAoKyQ/IKAD+AQAAAA==.Krowley:BAABNQAECn8kAAIMAAgKwgt/kABfAQAMAAgKwgt/kABfAQAAAA==.',
Ku='Kurast:BAABNQAECn8lAAIHAAkK4gXAiAAVAQAHAAkK4gXAiAAVAQABNQAECgoKPAAcAI4XAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFH8TAAMTAAcKsxp0DgBIAQATAAYKCBt0DgBIAQAfAAEKXRlHCwBdAAA1AAQKfyAAAxMACgqyIjlKAO0CABMACgqyIjlKAO0CAB8AAQp9HeZJADEAAAAA.',
Kx='Kxwono:BAABNQAECn8bAAMFAAkKYQ+eXgBWAQAFAAgKEBGeXgBWAQAYAAQKjA5MPwDOAAAAAA==.',
Ky='Kyoyama:BAABNQAECn8VAAIMAAkK7RJmNQAVAgAMAAkK7RJmNQAVAgABNQAECgoKQwAHAHgkAA==.',
La='Ladýshinobu:BAABNQAECn8iAAIkAAcKxwuyeQAXAQAkAAcKxwuyeQAXAQAAAA==.',
Le='Leahu:BAAANQAECggICwAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgMIAwAAAA==.',
Li='Lilalpha:BAAANQAECgQIBAABNQAECgoKIAAXAMYaAA==.Lisavia:BAABNQAECn8XAAIRAAgK3gNESwDqAAARAAgK3gNESwDqAAAAAA==.',
Lo='Locholovis:BAAANQAECgcIEAAAAA==.Locklicous:BAACNQAFFH8GAAIHAAMKXAxTFADZAAAHAAMKXAxTFADZAAA1AAQKfzUAAgcACgpfHHIiAPoCAAcACgpfHHIiAPoCAAE1AAQKCQkbAAgASBUA.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFH8UAAIGAAYKdRSwEABMAQAGAAYKdRSwEABMAQA1AAQKf0EAAwYACgq+HlMYABkCAAYACgo9HlMYABkCAAkABAr/HO18ACgBAAAA.',
Lu='Luminouss:BAACNQAFFH8MAAIMAAcKTxFkCwCXAQAMAAcKTxFkCwCXAQA1AAQKf0oAAwwACgoxHhMlANECAAwACgoxHhMlANECAAQAAgoZFvPRAEIAAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYICQABNQAECgUIBAABAAAAAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQAECgEIAQAAAA==.Magnuus:BAABNQAECn8WAAIWAAgK9QxZIgAoAQAWAAgK9QxZIgAoAQAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQAECgUICAAAAA==.Manadorfirn:BAAANQADCgMIAwAAAA==.Mantis:BAABNQAECn80AAIMAAoKfiHJDAA7AwAMAAoKfiHJDAA7AwABNQAECgoKPAAcAI4XAA==.',
Me='Mechagnomee:BAAANQAECgEIAQAAAA==.Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAABNQAECn8XAAIRAAgKBQ25OgBSAQARAAgKBQ25OgBSAQAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mercas:BAAANQAECgcICQABNQAECggIEwABAAAAAA==.Mezi:BAABNQAECn8xAAIQAAgKwBt/PAAQAgAQAAgKwBt/PAAQAgAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mh='Mhonster:BAABNQAECn8cAAMiAAoKQxv8DgA+AgAiAAoKbBr8DgA+AgAbAAMKkBEQTwCzAAABNQAFFAIIAgABAAAAAA==.',
Mi='Miasma:BAAANQAECgYIBwAAAA==.Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAABNQAECn8mAAMbAAoKGhUZIgC+AQAbAAoKzQ4ZIgC+AQAiAAYKdRikOgBxAQAAAA==.',
Mo='Morjek:BAAANQADCgcICwAAAA==.Morley:BAAANQAECgQIBQAAAA==.',
Mu='Mulron:BAABNQAECn8iAAIWAAgKDhj5GAAvAgAWAAgKDhj5GAAvAgAAAA==.',
My='Myrica:BAAANQAECgcICgAAAA==.',
Ni='Nishand:BAAANQADCgEIAQAAAA==.',
Oa='Oakenshíeld:BAACNQAFFH8NAAIFAAUKuQ8pEwA4AQAFAAUKuQ8pEwA4AQA1AAQKf0QAAgUACgqhIF8JAOwCAAUACgqhIF8JAOwCAAAA.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAABNQAECn8YAAIDAAoKYhoqWgCJAgADAAoKYhoqWgCJAgAAAA==.',
On='Onlyfeigns:BAAANQAECgIIAgAAAA==.',
Oo='Oozwoz:BAAANQAECgUICAAAAA==.',
Ou='Outfoxed:BAABNQAECn8gAAMMAAoKphwsJQBrAgAMAAoKphwsJQBrAgAEAAEKDwdsNwEyAAAAAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAABNQAECn8VAAIFAAYKXQi8aQAlAQAFAAYKXQi8aQAlAQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCggIGgAAAA==.',
Pi='Pinbalwizard:BAAANQAECgUIBgABNQAECggIHQAGAFcYAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAIAGkSAA==.Plagueblade:BAABNQAECn8XAAIGAAgKBxHjbABBAQAGAAgKBxHjbABBAQAAAA==.',
Po='Podtinder:BAAANQAECggICAABNQAECgoKPAAcAI4XAA==.Poppy:BAAANQAECgEIAQAAAA==.',
Pr='Progression:BAAANQAECggICwAAAA==.',
Qu='Quivera:BAAANQAECgEIAQAAAA==.',
Ra='Rainsshammy:BAABNQAECn8xAAMMAAoKvBkuNwCCAgAMAAkK3BguNwCCAgAEAAEKfgvK6QAtAAAAAA==.Rawak:BAAANQABCggIDgAAAA==.Rawktuah:BAAANQADCgMIAwABNQAECgoKLwAUAMoRAA==.',
Re='Realhelz:BAAANQAECgQIBAAAAA==.Redsamilf:BAABNQAECn8XAAIkAAYKKgyIkgDVAAAkAAYKKgyIkgDVAAAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAABNQAECn8UAAMkAAcKvBvzdQAiAQAkAAUKFhjzdQAiAQADAAYKIQyTwQASAQAAAA==.Resaana:BAAANQAECgQIBwABNQAECgUICAABAAAAAA==.Restofarian:BAACNQAFFH8FAAIMAAUKyQ+pDgBkAQAMAAUKyQ+pDgBkAQA1AAQKfycAAwwACQqOIroMAFoDAAwACQqOIroMAFoDAAQABApRELLdANoAAAAA.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAABNQAECn8UAAIlAAYKrRDqHQCCAQAlAAYKrRDqHQCCAQAAAA==.',
Ri='Rianon:BAAANQADCgcICAABNQAECgcIEwABAAAAAA==.Rikel:BAAANQADCgQIBAAAAA==.Rizzy:BAABNQAECn84AAMJAAoKWA5HTADjAQAJAAoKWA5HTADjAQACAAcKmgfbWgA+AQAAAA==.',
Ro='Rotinshot:BAACNQAFFH8JAAIUAAMKkhQZEgDgAAAUAAMKkhQZEgDgAAA1AAQKfyoAAxQACgpLHsUgAJUCABQACgpLHsUgAJUCABkAAgopBXB9AE4AAAAA.Rottinheals:BAAANQAECgcICAABNQAFFAMICQAUAJIUAA==.',
Ru='Rutikee:BAABNQAECn8yAAMYAAkKuxAVLwCiAQAYAAkKuxAVLwCiAQAFAAIKiQP9pABQAAAAAA==.',
Ry='Rykér:BAAANQAECgUIBQABNQAFFAcIGQAhANQaAA==.Ryomensukuna:BAABNQAECn8UAAIJAAkK0yCrKACWAgAJAAkK0yCrKACWAgAAAA==.',
Sa='Sahrotaar:BAAANQAECggIBAAAAA==.Sandrill:BAAANQAECgQJBQABNQAFFAMIBgAGAIYSAA==.Savior:BAAANQAECgIIAgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgUIBQAAAA==.Seizon:BAABNQAECn8dAAIjAAcK5BYlBwBsAQAjAAcK5BYlBwBsAQAAAA==.Senseicanz:BAAANQADCgYIBgAAAA==.Sephie:BAAANQAECgEIBAAAAA==.Serom:BAABNQAECn8eAAMYAAgKLxPhGwDZAQAYAAgKLxPhGwDZAQAFAAIKnAa4pwBIAAAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggICwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sharpshôôter:BAAANQAECgUIBQAAAA==.Sherunn:BAAANQAECgQIDgAAAA==.Shimakaze:BAABNQAECn8pAAIUAAkKAwm4gQBtAQAUAAkKAwm4gQBtAQAAAA==.Shmitty:BAAANQAECgcICwABNQAFFAMICQASAA0bAA==.Shooters:BAABNQAECn8UAAMjAAcK/Ro5CADXAQAUAAcKuRfukwDhAQAjAAYKHBg5CADXAQAAAA==.Shoretee:BAAANQAECgEIAQAAAA==.Shyminx:BAAANQADCgcICwAAAA==.Shymistress:BAABNQAECn80AAIUAAkKQR1rRQCcAgAUAAkKQR1rRQCcAgAAAA==.Shåmmy:BAABNQAECn80AAIMAAoKihS0SgA4AgAMAAoKihS0SgA4AgAAAA==.',
Si='Sindralea:BAABNQAECn8ZAAIbAAgKPBZxRQCbAQAbAAgKPBZxRQCbAQAAAA==.',
Sk='Skiá:BAABNQAECn82AAIdAAkKVh8UBwBLAgAdAAkKVh8UBwBLAgAAAA==.',
Sl='Slayerkitty:BAAANQABCgEIAQAAAA==.Slicedbread:BAAANQAECgEIAQAAAA==.',
So='Solaene:BAAANQAFFAIIAgAAAA==.Songatsu:BAAANQADCggIDAAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQAECgUICgABAAAAAA==.Sparkleglory:BAAANQAECgEIAQAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAABNQAECn8tAAIDAAoKqReBUwD8AQADAAoKqReBUwD8AQAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAMICQASAA0bAA==.Stormfox:BAABNQAECn8ZAAIEAAgKnwbApwBFAQAEAAgKnwbApwBFAQAAAA==.Strawhat:BAAANQAECgQICwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgUIEAAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQAECgUICgAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAABNQAECn8fAAMcAAkKFxgTCACcAgAcAAkKFxgTCACcAgANAAEK0xFfIgAyAAAAAA==.Tannuk:BAABNQAECn8/AAIWAAoKmRrlCwA/AgAWAAoKmRrlCwA/AgAAAA==.Tarz:BAAANQABCgIIAgAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAABNQAECn8vAAIEAAoKaxrJMwCqAgAEAAoKaxrJMwCqAgAAAA==.',
Th='Thekingbak:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Throwinhands:BAAANQAECgEIAQAAAA==.Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAABNQAECn8sAAIkAAgKvxiTVQAZAgAkAAgKvxiTVQAZAgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tn='Tntclepriest:BAAANQAECgEIAQABNQAECgMIAgABAAAAAA==.',
To='Toru:BAAANQAECgcICQABNQAECgoKQgADAGQgAA==.Totems:BAABNQAECn8kAAIlAAkKxhcXDQAQAgAlAAkKxhcXDQAQAgABNQAECgMIAgABAAAAAA==.Touchmycheek:BAAANQADCggICAAAAA==.',
Tr='Tridius:BAABNQAECn9zAAMQAAoKWCXhAQAYBAAQAAoKWCXhAQAYBAARAAEKAADqdAA8AAAAAA==.Trixx:BAAANQAECgUICwAAAA==.Truda:BAAANQADCgEIAQAAAA==.Trìck:BAAANQAECgEIAQAAAA==.',
Tu='Tuffcracker:BAAANQAECgUICgAAAA==.Turdanator:BAABNQAECn8WAAMQAAkKRxToOQAdAgAQAAkKRxToOQAdAgARAAEKkgvVWAAvAAAAAA==.',
Tw='Twinturboj:BAABNQAECn8WAAIIAAcK5AS8+gDnAAAIAAcK5AS8+gDnAAAAAA==.Twittle:BAABNQAECn8aAAMMAAUKIxeiggD6AAAMAAUKIxeiggD6AAAEAAIKQRVj0wBBAAAAAA==.',
Ty='Tylovastus:BAAANQAECggIEQAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.Tyton:BAAANQADCgMIAwAAAA==.',
Ub='Ube:BAABNQAECn8bAAIIAAgKjx/QRwCyAgAIAAgKjx/QRwCyAgAAAA==.',
Ur='Uriah:BAABNQAECn8dAAIUAAYKnQqmoAAsAQAUAAYKnQqmoAAsAQAAAA==.Ursúla:BAABNQAECn8bAAIHAAoKTA66cwAGAgAHAAoKTA66cwAGAgABNQAFFAUIHQAFAJMgAA==.Urïah:BAAANQADCgYICQABNQAECgYIHQAUAJ0KAA==.',
Ut='Utherr:BAAANQAECggICwAAAA==.',
Va='Valaravaus:BAAANQADCggICwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.Veryletheone:BAAANQAECgQIBgAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgUICQAAAA==.',
['Vé']='Végeta:BAABNQAECn8XAAMiAAgKFgIjXQCEAAAiAAgKFgIjXQCEAAAbAAEKZARLgwARAAABNQAECgoKPAAcAI4XAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wh='Whitecoma:BAAANQABCgIIAgAAAA==.',
Wo='Wooloo:BAACNQAFFH8QAAQHAAcKrhYTGQAsAQAHAAUKYxcTGQAsAQAgAAIK0Ae1CQBaAAALAAEKbiOZFgBXAAA1AAQKfzAABAcACgr+JbwBAHEDAAcACgr5JbwBAHEDAAsABwp3G5oPAAMCACAAAQpPJRYcAGIAAAAA.',
Wy='Wynona:BAACNQAFFH8IAAITAAMKGgrsIQDUAAATAAMKGgrsIQDUAAA1AAQKfzwAAhMACgrEF6E7ADcCABMACgrEF6E7ADcCAAAA.',
Xa='Xanagore:BAABNQAECn8eAAMIAAcKSRI1qgCzAQAIAAcKSRI1qgCzAQAKAAMKWAuXNQCIAAAAAA==.',
Xk='Xkwon:BAAANQAECgIIBAAAAA==.Xkwøn:BAACNQAFFH8QAAImAAYK3BVDAAAzAQAmAAYK3BVDAAAzAQA1AAQKfzsAAiYACgrMI5MAAP0CACYACgrMI5MAAP0CAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAABNQAECn8XAAIiAAoKEw2MJgAtAQAiAAoKEw2MJgAtAQAAAA==.',
Xu='Xunie:BAAANQADCggIKwAAAA==.',
Yl='Yloh:BAABNQAECn8kAAQQAAkKMCQrBwCLAwAQAAkKMCQrBwCLAwARAAYK4wX7WAClAAAPAAIK3Q1SIABfAAAAAA==.',
Yo='Yoquiere:BAAANQAECgQIBAAAAA==.',
Za='Zaisplash:BAAANQAECgUICgAAAA==.Zana:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Zaretan:BAAANQADCggIJAAAAA==.',
Zb='Zbrute:BAABNQAECn8jAAIUAAgKhhK0dQAkAgAUAAgKhhK0dQAkAgAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAACNQAFFH8ZAAQJAAcKGxGrAwAmAQAJAAUK6Q2rAwAmAQACAAUKpRCFDAAXAQAGAAEKAAC5NAAqAAA1AAQKfyYAAwkACgqdH7QWAAoCAAkACgqWHrQWAAoCAAIABgqPGJRaAO4AAAAA.',
Zu='Zulpher:BAAANQADCggIIAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgIIAwAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAACNQAFFH8LAAITAAUK6RaaIADbAAATAAUK6RaaIADbAAA1AAQKfysAAhMACgpHIwwLAB4DABMACgpHIwwLAB4DAAAA.',
['ße']='ßeorn:BAAANQABCgIIAgABNQAECgoKcwAQAFglAA==.',
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
