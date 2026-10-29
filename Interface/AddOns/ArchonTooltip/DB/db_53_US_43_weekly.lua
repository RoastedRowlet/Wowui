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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Paladin-Retribution','Shaman-Elemental','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warrior-Arms','DeathKnight-Unholy','Warrior-Protection','Warlock-Destruction','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Priest-Shadow','Priest-Holy','Mage-Arcane','Rogue-Assassination','Hunter-BeastMastery','Warrior-Fury','Druid-Restoration','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Mage-Fire','Mage-Frost','Warlock-Affliction','Druid-Guardian','Rogue-Subtlety','DemonHunter-Devourer','Hunter-Survival','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAABNQAECn8fAAICAAoK4wyUIADIAQACAAoK4wyUIADIAQABNQAECgoKOAADAAQcAA==.',
Ae='Aeolos:BAAANQADCgcIDwAAAA==.Aesthetic:BAAANQAECgcIDgABNQAFFAcIGAAEAHUbAA==.',
Ag='Agrios:BAACNQAFFH8JAAIFAAIKoxLGEACYAAAFAAIKoxLGEACYAAA1AAQKfzsAAgUACgoRHqgMAIACAAUACgoRHqgMAIACAAAA.',
Ai='Aiellee:BAAANQAECgMIBQAAAA==.',
Ak='Akias:BAAANQAECgYIEQAAAA==.',
Al='Alexandra:BAAANQAECgUICAABNQAECgYICAABAAAAAA==.Alliekill:BAAANQAECgMIAwABNQAECgkJHAAGANYOAA==.Altaurus:BAAANQAECgUIDQAAAA==.Alynnei:BAAANQAECggICwABNQAECgYICAABAAAAAA==.',
Am='Amare:BAAANQAECgQICwAAAA==.Amiria:BAAANQADCggICwAAAA==.',
An='Andros:BAABNQAECn8aAAIHAAcKZhSRlQCwAQAHAAcKZhSRlQCwAQAAAA==.Anekaatwo:BAAANQAECgEIAQAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Araxe:BAAANQAECgQIBAABNQAECgoKNQAIAM0aAA==.Arroyo:BAABNQAECn83AAIJAAoKuB4cEQAuAwAJAAoKuB4cEQAuAwAAAA==.',
As='Askadar:BAACNQAFFH8KAAIKAAQK6SXPAABCAQAKAAQK6SXPAABCAQA1AAQKfysAAgoACgr4JiEAAAsEAAoACgr4JiEAAAsEAAAA.',
Az='Azora:BAABNQAECn8gAAMLAAkKUhmsDAAtAgALAAcK3xmsDAAtAgAHAAcKZBamhwDTAQAAAA==.Azzura:BAAANQAECgEIAQAAAA==.',
Ba='Baheem:BAAANQAECgQIBwAAAA==.Bams:BAABNQAECn8gAAIMAAgKJRaKVQBCAQAMAAgKJRaKVQBCAQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECn8kAAMNAAoKsBtuCQDbAgANAAoKsBtuCQDbAgAOAAEK3AGoKAAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECn8nAAIDAAoK6hHMcgBJAgADAAoK6hHMcgBJAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQAECgQICAAAAA==.',
Bi='Bifrons:BAAANQADCgYIGAAAAA==.Bigdill:BAAANQAECgQIBAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIBgAAAA==.Bluè:BAAANQAECgQIBgAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCgYIHQAAAA==.Boolil:BAAANQAECgcIEgABNQAECgoKOgAPAOINAA==.Booloved:BAABNQAECn86AAQPAAoK4g2yAwCTAQAPAAkKAg+yAwCTAQAQAAkKHgSLPABGAQARAAYK8QGBywDAAAAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Brotato:BAAANQAECgQIBAABNQAECgoKNwASAOEaAA==.Broxx:BAAANQADCgcICQAAAA==.',
Bu='Bulwei:BAAANQAECgYICAAAAA==.',
Bw='Bwimbosawme:BAAANQAFFAIIAwABNQAFFAMIBwATAA0bAA==.',
By='Byssrak:BAAANQAECgMIAgAAAA==.',
Ca='Calmcarnage:BAAANQAECgEIAQAAAA==.Carmêl:BAAANQAECgUIBQABNQAECgoKMAASAHYgAA==.Cattiebuzz:BAAANQADCgIIAgABNQAECgkJLgAUAKgaAA==.Cattiegreen:BAABNQAECn8uAAIUAAkKqBrCQgDZAQAUAAkKqBrCQgDZAQAAAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Chopshop:BAAANQADCgUIBQAAAA==.Christopher:BAABNQAECn8lAAISAAkKghbXgwB3AgASAAkKghbXgwB3AgAAAA==.',
Co='Consolata:BAAANQADCgMIAwAAAA==.Costica:BAAANQADCgUIBQAAAA==.',
Cr='Creepychaos:BAAANQADCggICAABNQAECgUIBwABAAAAAA==.Creepydemise:BAAANQAECgUIBwAAAA==.Creepydrunk:BAAANQADCgcICQABNQAECgUIBwABAAAAAA==.Croixsmash:BAABNQAECn8XAAMIAAkKSBXmkwDqAQAIAAgKFhXmkwDqAQAVAAMKpRK4HwDAAAAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.Curse:BAAANQADCggIDgAAAA==.',
Cy='Cylvanna:BAAANQAECgQICgAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Darkrest:BAAANQADCggIEwAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgkJFwAIAEgVAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECn8uAAIDAAoKyAyZqgDKAQADAAoKyAyZqgDKAQAAAA==.Dawnn:BAAANQAECgUICwAAAA==.',
De='Deanwnchestr:BAAANQAECgYIDQAAAA==.Deatnshadow:BAAANQAECggIDAAAAA==.Delyrius:BAAANQADCggICAABNQAECgoKLQAGAL0YAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgUICQAAAA==.',
Do='Dogeatdog:BAAANQADCgcIDwAAAA==.Dorus:BAAANQADCgQIBAAAAA==.',
Dr='Draakell:BAABNQAECn8YAAIJAAgK2Q55JwA/AQAJAAgK2Q55JwA/AQAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAAANQAECgYIEQAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.Dryrain:BAAANQAECggICgAAAA==.',
Du='Dudè:BAAANQAECgUIDwAAAA==.',
['Dâ']='Dâggèr:BAACNQAFFH8HAAITAAMKDRsqDwD3AAATAAMKDRsqDwD3AAA1AAQKfxUAAhMABwryHI8vACUCABMABwryHI8vACUCAAAA.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggIDAAAAA==.',
El='Elarae:BAABNQAECn8nAAIUAAkKWRUpPQDtAQAUAAkKWRUpPQDtAQAAAA==.Elawen:BAAANQADCgUIBQAAAA==.Elementblah:BAABNQAECn8UAAIEAAYKng9/mgBjAQAEAAYKng9/mgBjAQAAAA==.Elfkinn:BAACNQAFFH8ZAAIFAAUKyxw6DQCYAQAFAAUKyxw6DQCYAQA1AAQKfygAAwUACgqsIZIdAN0CAAUACgqsIZIdAN0CABYAAQqHAf2FABUAAAAA.Elivaniel:BAAANQADCgYIBgAAAA==.Ellemere:BAAANQAECgUIBQABNQAECgYICAABAAAAAA==.',
Em='Emerita:BAAANQAECgUIBQAAAA==.Emeryl:BAAANQAECgQIBQABNQAFFAcIGAAEAHUbAA==.Empathyforyo:BAABNQAECn8rAAMUAAkKdRjsSgCNAgAUAAgKXRvsSgCNAgAXAAQKAAlQVwDIAAAAAA==.',
En='Enna:BAAANQADCgYIGAAAAA==.',
Eq='Equinox:BAABNQAECn8eAAIFAAoKexBoOwAZAgAFAAoKexBoOwAZAgAAAA==.',
Er='Eredris:BAAANQADCgIIAgAAAA==.Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAABNQAECn8hAAMYAAgKQBnTDAD3AQAYAAgKdxjTDAD3AQAZAAUKshjQTwBaAQAAAA==.',
Es='Eshtar:BAAANQAECgUICQAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAABNQAECn8VAAIXAAgK2BPhKgD0AQAXAAgK2BPhKgD0AQAAAA==.Exzanthia:BAAANQADCggICwAAAA==.',
Ey='Eyln:BAABNQAECn8dAAIXAAcKeQv9GQA1AQAXAAcKeQv9GQA1AQAAAA==.',
Fa='Falkor:BAABNQAECn80AAIaAAoKjheTEgCDAgAaAAoKjheTEgCDAgAAAA==.Fayway:BAABNQAECn80AAMWAAoKexy6CgCQAgAWAAoKexy6CgCQAgAFAAEKAABoyQAZAAAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECn81AAIbAAoKch7CAwCQAgAbAAoKch7CAwCQAgAAAA==.',
Fi='Figgy:BAABNQAECn8bAAIHAAoKywtmjQDFAQAHAAoKywtmjQDFAQAAAA==.Firepower:BAABNQAECn83AAQSAAoK4RrmUADfAgASAAoK4RrmUADfAgAcAAIKVw6dBAB0AAAdAAEKvhl5QwA9AAAAAA==.',
Fo='Forevershy:BAAANQADCggIHgAAAA==.',
Fr='Fries:BAEANQAECggIDwAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Ge='Georgiee:BAAANQADCgIIAgAAAA==.',
Gi='Giggles:BAABNQAECn8XAAIEAAcKvRCgjgB/AQAEAAcKvRCgjgB/AQAAAA==.',
Go='Goh:BAAANQAECgQIBAAAAA==.Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIDgABNQAECgkJJwAMAI4iAA==.Gothrim:BAAANQADCggICAAAAA==.',
Gr='Greenbean:BAAANQADCggJCAABNQAFFAUIGQAFAMscAA==.Groto:BAABNQAECn8UAAIeAAcK2A13DQCDAQAeAAcK2A13DQCDAQAAAA==.Grrum:BAAANQAECgUIBAAAAA==.Grèy:BAAANQAECgYIDgAAAA==.',
Gu='Gullible:BAAANQAECgYICgAAAA==.',
Ha='Hairy:BAAANQAECgMIAwAAAA==.Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQAECgcICAAAAA==.Hanjo:BAABNQAECn8VAAIKAAYKDB2MFADeAQAKAAYKDB2MFADeAQAAAA==.Hatookorr:BAABNQAECn8dAAIGAAgKZx5TIgCjAgAGAAgKZx5TIgCjAgABNQAECgoKNwASAOEaAA==.',
He='Heledrianis:BAAANQAECgUIBwAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Ho='Hornet:BAAANQADCggIJAAAAA==.',
Hy='Hydé:BAACNQAFFH8ZAAMfAAcK1Bq+AABYAQAfAAYKiyC+AABYAQAbAAEK9wMdAwBLAAA1AAQKfx0AAh8ACgqCHFILALgCAB8ACgqCHFILALgCAAAA.',
Ik='Ikwon:BAAANQADCgUIBwAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
In='Intuned:BAAANQAECgcIBwABNQAFFAMIBwATAA0bAA==.',
Is='Ishmael:BAAANQAECgQIBAAAAA==.Ismeldbad:BAAANQAECgMIBgABNQAECgkJHAAgAKQbAA==.',
Ja='Jaland:BAAANQABCgQIBAAAAA==.',
Je='Jellybreak:BAABNQAECn8mAAIFAAcKqxCkJQBXAQAFAAcKqxCkJQBXAQAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAABNQAECn8VAAIRAAYKQhaXfwCaAQARAAYKQhaXfwCaAQAAAA==.Kateblue:BAABNQAECn8VAAIFAAYKgQyXYABNAQAFAAYKgQyXYABNAQAAAA==.',
Ke='Keeble:BAAANQAECggIDAAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAABNQAECn8lAAMeAAkKzRdIAwD0AQAeAAkKzRdIAwD0AQAHAAMKWAWQIgF9AAAAAA==.Kelsyyr:BAAANQAECgUIBwABNQAECgkJJQAeAM0XAA==.Kenpachi:BAAANQADCgEIAQAAAA==.',
Ki='Kidneysweeny:BAABNQAECn8cAAMgAAkKpBvWIQC9AQAgAAYK6xfWIQC9AQATAAQKXRuJMQCoAAAAAA==.Kikyou:BAABNQAECn8pAAMCAAgK3RtBHgDaAQAJAAcKoBx5OQA+AgACAAgKohVBHgDaAQABNQAFFAcIIQAhAIgeAA==.Kim:BAABNQAECn8aAAIiAAgKZg5pCADOAQAiAAgKZg5pCADOAQAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQAECgMIAwAAAA==.Krelbelorll:BAABNQAECn8lAAIhAAoKyQ/IKAD+AQAhAAoKyQ/IKAD+AQAAAA==.Krowley:BAABNQAECn8hAAIMAAgKwgt/kABfAQAMAAgKwgt/kABfAQAAAA==.',
Ku='Kurast:BAABNQAECn8bAAIHAAkKbgWffAD+AAAHAAkKbgWffAD+AAABNQAECgoKNAAaAI4XAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFH8TAAMSAAcKsxqNCQBYAQASAAYKCBuNCQBYAQAdAAEKXRliCABdAAA1AAQKfyAAAxIACgqyIjlKAO0CABIACgqyIjlKAO0CAB0AAQp9HeZJADEAAAAA.',
Kx='Kxwono:BAABNQAECn8YAAMFAAkKYQ8VPADVAAAFAAgKEBEVPADVAAAWAAIKCA2ARwBuAAAAAA==.',
Ky='Kyoyama:BAAANQAECggIDgABNQAECgoKOgAHAFokAA==.',
La='Ladýshinobu:BAABNQAECn8gAAIjAAcKuguMXgAmAQAjAAcKuguMXgAmAQAAAA==.',
Le='Leahu:BAAANQAECggICwAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgMIAwAAAA==.',
Li='Lilalpha:BAAANQAECgQIBAABNQAECgkJHAAgAKQbAA==.Lisavia:BAABNQAECn8XAAIQAAgK3gNESwDqAAAQAAgK3gNESwDqAAAAAA==.',
Lo='Locholovis:BAAANQAECgcIEAAAAA==.Locklicous:BAABNQAECn80AAIHAAoK8BpyIgD6AgAHAAoK8BpyIgD6AgABNQAECgkJFwAIAEgVAA==.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFH8TAAIGAAUKJRawEABMAQAGAAUKJRawEABMAQA1AAQKfzgAAwYACgomHksUAAcCAAYACgqkHUsUAAcCAAkABAr/HO18ACgBAAAA.',
Lu='Luminouss:BAACNQAFFH8MAAIMAAcKTxFkCwCXAQAMAAcKTxFkCwCXAQA1AAQKf0YAAwwACgoxHhMlANECAAwACgoxHhMlANECAAQAAgoZFo+zAEIAAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYICQABNQAECgoKLQAGAL0YAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQAECgEIAQAAAA==.Magnuus:BAAANQAECgUIDgAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQAECgUICAAAAA==.Mantis:BAABNQAECn8rAAIMAAoK1SAWCQAxAwAMAAoK1SAWCQAxAwABNQAECgoKNAAaAI4XAA==.',
Me='Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAABNQAECn8VAAIQAAYKBw65OgBSAQAQAAYKBw65OgBSAQAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mercas:BAAANQAECgYICAABNQAECgkJLAASAJcXAA==.Mezi:BAABNQAECn8pAAIRAAcKPB6kMwDuAQARAAcKPB6kMwDuAQAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mh='Mhonster:BAABNQAECn8ZAAMhAAoKbBrqCQBbAgAhAAoKbBrqCQBbAgAZAAEK2ggabAAvAAABNQAECgYICAABAAAAAA==.',
Mi='Miasma:BAAANQAECgYIBgAAAA==.Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAABNQAECn8jAAMZAAoK/BEHHQCxAQAZAAoK2gsHHQCxAQAhAAUKwhqkOgBxAQAAAA==.',
Mo='Morjek:BAAANQADCgcIBwAAAA==.Morley:BAAANQAECgQIBQAAAA==.',
Mu='Mulron:BAABNQAECn8gAAIkAAgK4xb5GAAvAgAkAAgK4xb5GAAvAgAAAA==.',
My='Myrica:BAAANQAECgcICQAAAA==.',
Ni='Nishand:BAAANQADCgEIAQAAAA==.',
Oa='Oakenshíeld:BAACNQAFFH8NAAIFAAUKuQ8pEwA4AQAFAAUKuQ8pEwA4AQA1AAQKfzsAAgUACgqIHesJALICAAUACgqIHesJALICAAAA.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAABNQAECn8VAAIDAAoKehgqWgCJAgADAAoKehgqWgCJAgAAAA==.',
Oo='Oozwoz:BAAANQAECgQIBwAAAA==.',
Ou='Outfoxed:BAABNQAECn8gAAMMAAoKphzJGAB8AgAMAAoKphzJGAB8AgAEAAEKDwdsNwEyAAABNQAFFAcIGwARAA4aAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAABNQAECn8VAAIFAAYKXQi8aQAlAQAFAAYKXQi8aQAlAQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCgcIGQAAAA==.',
Pi='Pinbalwizard:BAAANQAECgUIBAABNQAECggIHQAGAFcYAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAIAGkSAA==.Plagueblade:BAABNQAECn8VAAIGAAYKlRHjbABBAQAGAAYKlRHjbABBAQAAAA==.',
Po='Poppy:BAAANQAECgEIAQAAAA==.',
Pr='Progression:BAAANQAECggICwAAAA==.',
Ra='Ragingrain:BAAANQADCgUIBQAAAA==.Rainsshammy:BAABNQAECn8vAAIMAAkKshguNwCCAgAMAAkKshguNwCCAgAAAA==.Rawak:BAAANQABCggIDgAAAA==.Rawktuah:BAAANQADCgMIAwAAAA==.',
Re='Realhelz:BAAANQAECgQIBAAAAA==.Redsamilf:BAAANQAECgYIEwAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAABNQAECn8UAAMjAAcKvBvSWwAuAQAjAAUKFhjSWwAuAQADAAYKIQxOnQAZAQAAAA==.Resaana:BAAANQAECgIIAwABNQAECgUICAABAAAAAA==.Restofarian:BAABNQAECn8nAAMMAAkKjiK6DABaAwAMAAkKjiK6DABaAwAEAAQKURCy3QDaAAAAAA==.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAABNQAECn8UAAIlAAYKrRDqHQCCAQAlAAYKrRDqHQCCAQAAAA==.',
Ri='Rianon:BAAANQADCgcICAABNQAECgcIEQABAAAAAA==.Rizzy:BAABNQAECn84AAMJAAoKWA5HTADjAQAJAAoKWA5HTADjAQACAAcKmgfbWgA+AQAAAA==.',
Ro='Rotinshot:BAACNQAFFH8JAAIUAAMKkhS/DQDmAAAUAAMKkhS/DQDmAAA1AAQKfyoAAxQACgpLHgwTALgCABQACgpLHgwTALgCABcAAgopBXB9AE4AAAAA.Rottinheals:BAAANQAECgYIBgABNQAFFAMICQAUAJIUAA==.',
Ru='Rutikee:BAABNQAECn8vAAMWAAkKnA8VLwCiAQAWAAkKnA8VLwCiAQAFAAIKiQP9pABQAAAAAA==.',
Ry='Rykér:BAAANQAECgUIBQABNQAFFAcIGQAfANQaAA==.Ryomensukuna:BAABNQAECn8UAAIJAAkK0yCrKACWAgAJAAkK0yCrKACWAgAAAA==.',
Sa='Sahrotaar:BAAANQAECggIAQAAAA==.Sandrill:BAAANQAECgQJBQABNQAECgoKNwASAOEaAA==.Savior:BAAANQAECgIIAgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgUIBQAAAA==.Seizon:BAABNQAECn8YAAIiAAYKAxhhCQChAQAiAAYKAxhhCQChAQAAAA==.Senseicanz:BAAANQADCgYIBgAAAA==.Serom:BAAANQAECgYIDgAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggICwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sharpshôôter:BAAANQADCgUIBQAAAA==.Sherunn:BAAANQAECgUIDAAAAA==.Shimakaze:BAABNQAECn8hAAIUAAcKgQnBtQCYAQAUAAcKgQnBtQCYAQAAAA==.Shmitty:BAAANQAECgYICwABNQAFFAMIBwATAA0bAA==.Shooters:BAABNQAECn8UAAMiAAcK/Ro5CADXAQAUAAcKuRfukwDhAQAiAAYKHBg5CADXAQAAAA==.Shyminx:BAAANQADCgcICwAAAA==.Shymistress:BAABNQAECn8sAAIUAAkKmxtrRQCcAgAUAAkKmxtrRQCcAgAAAA==.Shåmmy:BAABNQAECn80AAIMAAoKihS0SgA4AgAMAAoKihS0SgA4AgAAAA==.',
Si='Sindralea:BAABNQAECn8XAAIZAAcK0xVxRQCbAQAZAAcK0xVxRQCbAQAAAA==.',
Sk='Skiá:BAABNQAECn8zAAIbAAgKzR3xCADAAgAbAAgKzR3xCADAAgAAAA==.',
Sl='Slayerkitty:BAAANQABCgEIAQAAAA==.Slicedbread:BAAANQAECgEIAQAAAA==.',
So='Solaene:BAAANQAECgYICAAAAA==.Songatsu:BAAANQADCggIDAAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Sparkleglory:BAAANQAECgEIAQAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAABNQAECn8oAAIDAAkK5hexUADEAQADAAkK5hexUADEAQAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAMIBwATAA0bAA==.Stormfox:BAABNQAECn8YAAIEAAgKQwbApwBFAQAEAAgKQwbApwBFAQAAAA==.Strawhat:BAAANQAECgQICwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgQIDAAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQAECgQIBQAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAABNQAECn8YAAMaAAgKvRUbCABHAgAaAAgKvRUbCABHAgANAAEK0xHeHQAyAAAAAA==.Tannuk:BAABNQAECn85AAIkAAoKIRrUCAA3AgAkAAoKIRrUCAA3AgAAAA==.Tarz:BAAANQABCgIIAgAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgUIBQABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAABNQAECn8uAAIEAAkKDRvJMwCqAgAEAAkKDRvJMwCqAgAAAA==.',
Th='Thekingbak:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAABNQAECn8sAAIjAAgKvxiTVQAZAgAjAAgKvxiTVQAZAgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tn='Tntclepriest:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
To='Toru:BAAANQAECgIIAgABNQAECgoKOAADAAQcAA==.Totems:BAABNQAECn8gAAIlAAkKLROqDgCiAQAlAAkKLROqDgCiAQABNQAECgMIAgABAAAAAA==.Touchmycheek:BAAANQADCggICAAAAA==.',
Tr='Tridius:BAABNQAECn9XAAMRAAoKdyNYBQCTAwARAAoKdyNYBQCTAwAQAAEKAADqdAA8AAAAAA==.Trixx:BAAANQAECgUICwAAAA==.Truda:BAAANQADCgEIAQAAAA==.',
Tu='Tuffcracker:BAAANQAECgUICgAAAA==.Turdanator:BAAANQAECggIDwAAAA==.',
Tw='Twinturboj:BAABNQAECn8WAAIIAAcK5AQ/tACjAAAIAAcK5AQ/tACjAAAAAA==.Twittle:BAAANQAECgQIEAAAAA==.',
Ty='Tylovastus:BAAANQAECggIDQAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.Tyton:BAAANQADCgMIAwAAAA==.',
Ub='Ube:BAABNQAECn8bAAIIAAgKjx/QRwCyAgAIAAgKjx/QRwCyAgAAAA==.',
Ur='Uriah:BAABNQAECn8YAAIUAAYK3wnNjAAYAQAUAAYK3wnNjAAYAQAAAA==.Ursúla:BAABNQAECn8VAAIHAAoKDw66cwAGAgAHAAoKDw66cwAGAgABNQAFFAUIGQAFAMscAA==.Urïah:BAAANQADCgYICQABNQAECgYIGAAUAN8JAA==.',
Ut='Utherr:BAAANQAECggICAAAAA==.',
Va='Valaravaus:BAAANQADCggICwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.Veryletheone:BAAANQAECgQIBQAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgUIBQAAAA==.',
['Vé']='Végeta:BAABNQAECn8VAAIhAAgKFgKePABaAAAhAAgKFgKePABaAAABNQAECgoKNAAaAI4XAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wh='Whitecoma:BAAANQABCgIIAgAAAA==.',
Wo='Wooloo:BAACNQAFFH8PAAQHAAcKrhYTGQAsAQAHAAUKYxcTGQAsAQAeAAIK0Ae1CQBaAAALAAEKbiOZFgBXAAA1AAQKfywABAcACgr+JXkTAI0CAAcACgr5JXkTAI0CAAsABwp3G5oPAAMCAB4AAQpPJZUSAG0AAAAA.',
Wy='Wynona:BAACNQAFFH8FAAISAAIKTwdoTgCJAAASAAIKTwdoTgCJAAA1AAQKfzMAAhIACgpvF789AP0BABIACgpvF789AP0BAAAA.',
Xa='Xanagore:BAABNQAECn8eAAMIAAcKSRI1qgCzAQAIAAcKSRI1qgCzAQAKAAMKWAuXNQCIAAAAAA==.',
Xk='Xkwon:BAAANQADCggIDgAAAA==.Xkwøn:BAACNQAFFH8PAAImAAUKFBtnAADxAAAmAAUKFBtnAADxAAA1AAQKfzoAAiYACgrWIm4AAP4CACYACgrWIm4AAP4CAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAAANQAECggIEwAAAA==.',
Xu='Xunie:BAAANQADCggIKwAAAA==.',
Yl='Yloh:BAABNQAECn8jAAQRAAkKMCQrBwCLAwARAAkKMCQrBwCLAwAQAAYK4wX7WAClAAAPAAIK3Q1SIABfAAAAAA==.',
Yo='Yoquiere:BAAANQAECgQIBAAAAA==.',
Za='Zaisplash:BAAANQAECgUICgAAAA==.Zana:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Zaretan:BAAANQADCggIIgAAAA==.',
Zb='Zbrute:BAABNQAECn8hAAIUAAgK+BC0dQAkAgAUAAgK+BC0dQAkAgAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAACNQAFFH8ZAAQJAAcKGxFlAgA7AQAJAAUK6Q1lAgA7AQACAAUKpRCFDAAXAQAGAAEKAAC5NAAqAAA1AAQKfyMAAwkACgptH/MXAL0BAAkACgqWHvMXAL0BAAIABQqCFjFqAPYAAAAA.',
Zu='Zulpher:BAAANQADCggIIAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgIIAgAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAACNQAFFH8LAAISAAUK6RahGADlAAASAAUK6RahGADlAAA1AAQKfysAAhIACgpHI1kFADsDABIACgpHI1kFADsDAAAA.',
['ße']='ßeorn:BAAANQABCgIIAgAAAA==.',
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
