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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Paladin-Retribution','Shaman-Elemental','Druid-Balance','Rogue-Subtlety','DeathKnight-Blood','Warlock-Demonology','Warrior-Arms','DeathKnight-Unholy','Warrior-Protection','Warlock-Destruction','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Priest-Holy','Priest-Shadow','Rogue-Assassination','Mage-Arcane','Hunter-BeastMastery','Warrior-Fury','Paladin-Protection','Druid-Restoration','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Mage-Fire','Mage-Frost','Warlock-Affliction','Druid-Guardian','DemonHunter-Devourer','Hunter-Survival','Paladin-Holy','Shaman-Enhancement','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAABNQAECn8wAAICAAoKCRJBJwAKAgACAAoKCRJBJwAKAgABNQAECgoKSwADAAkiAA==.',
Ae='Aeolos:BAAANQADCggIEgAAAA==.Aesthetic:BAAANQAECgcIDgABNQAFFAcIGAAEAHUbAA==.',
Ag='Agrios:BAACNQAFFH8KAAIFAAMKrQ4lEgDPAAAFAAMKrQ4lEgDPAAA1AAQKf1QAAgUACgrJH1MNAMUCAAUACgrJH1MNAMUCAAAA.',
Ai='Aiellee:BAAANQAECgUIBwAAAA==.',
Ak='Akias:BAAANQAECgYIEQAAAA==.',
Al='Alexandra:BAAANQAECgUICgABNQAECgkJFAAGAP0XAA==.Alliekill:BAAANQAECgMIAwABNQAECgkJHgAHAAYPAA==.Altaurus:BAAANQAECgUIDQAAAA==.Alynnei:BAAANQAECggIDwABNQAECgkJFAAGAP0XAA==.',
Am='Amare:BAAANQAECgUIDwAAAA==.Amiria:BAAANQADCggICwAAAA==.',
An='Andros:BAABNQAECn8gAAIIAAgK1xSRlQCwAQAIAAgK1xSRlQCwAQAAAA==.Anekaatwo:BAAANQAECgEIAQAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Araxe:BAAANQAECgQIBAABNQAECgoKPAAJAFAbAA==.Arroyo:BAABNQAECn88AAIKAAoKJSAcEQAuAwAKAAoKJSAcEQAuAwAAAA==.',
As='Askadar:BAACNQAFFH8KAAILAAQK6SV9AQA3AQALAAQK6SV9AQA3AQA1AAQKfy0AAgsACgr4JiEAAAsEAAsACgr4JiEAAAsEAAAA.',
Az='Azora:BAABNQAECn8kAAMMAAoKRhesDAAtAgAMAAcK3xmsDAAtAgAIAAgKxxSmhwDTAQAAAA==.Azzura:BAAANQAECgEIAQAAAA==.',
Ba='Baheem:BAAANQAECgQICwAAAA==.Bams:BAABNQAECn8kAAINAAgKnBZAfQCUAQANAAgKnBZAfQCUAQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECn8rAAMOAAoK2R1uCQDbAgAOAAoK2R1uCQDbAgAPAAEK3AGoKAAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECn8nAAIDAAoK6hHMcgBJAgADAAoK6hHMcgBJAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAABNQAECn8WAAILAAgKWgnIHAAEAQALAAgKWgnIHAAEAQAAAA==.',
Bi='Bifrons:BAAANQADCgYIGAAAAA==.Bigdill:BAAANQAECgQIBAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIBgAAAA==.Bluè:BAAANQAECgQIBgAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCggIHwAAAA==.Boolil:BAABNQAECn8YAAINAAkK+QdZdgA5AQANAAkK+QdZdgA5AQABNQAECgoKQwAQAC0PAA==.Boolove:BAAANQAECgcIBQABNQAECgoKQwAQAC0PAA==.Booloved:BAABNQAECn9DAAQQAAoKLQ/ZBQCMAQAQAAkKAg/ZBQCMAQARAAoKOwclbACAAQASAAkKHgSLPABGAQAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Brotato:BAAANQAECggIDgABNQAFFAMIBgAHAIYSAA==.Broxx:BAAANQADCgcICQAAAA==.',
Bu='Bulwei:BAAANQAECgcICQAAAA==.',
Bw='Bwimbosawme:BAAANQAFFAMIAgABNQAFFAQICgATAA0bAA==.',
By='Byssrak:BAAANQAECgQICgAAAA==.',
Ca='Calmcarnage:BAAANQAECgEIAQAAAA==.Carmêl:BAAANQAECgYICAABNQAECgoKOQAUAOEgAA==.Cattiebuzz:BAAANQADCgIIAgABNQAECgkJLgAVAKgaAA==.Cattiegreen:BAABNQAECn8uAAIVAAkKqBoAaQBCAgAVAAkKqBoAaQBCAgAAAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Christopher:BAABNQAECn8pAAIUAAoK0xXXgwB3AgAUAAoK0xXXgwB3AgAAAA==.',
Co='Consolata:BAAANQADCgMIAwAAAA==.Costica:BAAANQADCgUIBQAAAA==.',
Cr='Creepychaos:BAAANQADCggIDwABNQAECgkJFwAKAAsFAA==.Creepydemise:BAABNQAECn8XAAIKAAkKCwV/QAD9AAAKAAkKCwV/QAD9AAAAAA==.Creepydrunk:BAAANQADCggIEQABNQAECgkJFwAKAAsFAA==.Croixsmash:BAABNQAECn8hAAMWAAkKfBWEFQAKAQAJAAgKFhXmkwDqAQAWAAYKhxSEFQAKAQAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.Curse:BAAANQAECgMIAwAAAA==.',
Cy='Cylvanna:BAAANQAECgYIDwAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Darkrest:BAAANQADCggIFwAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgkJIQAWAHwVAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECn85AAIDAAoKlQ1pnQB9AQADAAoKlQ1pnQB9AQAAAA==.Dawnn:BAAANQAECgYIDQAAAA==.',
De='Deanwnchestr:BAABNQAECn8kAAIUAAgKhgTZzAD9AAAUAAgKhgTZzAD9AAAAAA==.Deatnshadow:BAAANQAECggIDgAAAA==.Delyrius:BAAANQADCggICAABNQAECgoKNAAHAIEZAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgYICgAAAA==.',
Do='Dogeatdog:BAAANQADCggIGQAAAA==.Dorus:BAAANQADCgQIBAAAAA==.',
Dr='Draakell:BAABNQAECn8ZAAIKAAgK2Q4SNwAuAQAKAAgK2Q4SNwAuAQAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAABNQAECn8dAAMIAAYKNAd+rgDjAAAIAAYKLgZ+rgDjAAAMAAQKVgSbNwAvAAAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.Dryrain:BAABNQAECn8fAAMXAAoKexE2FgC2AQAXAAoKexE2FgC2AQADAAIKMQNqmAEpAAAAAA==.',
Du='Dudè:BAAANQAECgYIDwAAAA==.',
['Dâ']='Dâggèr:BAACNQAFFH8KAAMTAAQKDRsqDwD3AAATAAQKDRsqDwD3AAAGAAEKqAP/JQA+AAA1AAQKfyQAAhMACQpEJFwBAFkDABMACQpEJFwBAFkDAAAA.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggIDAAAAA==.',
El='Eladawn:BAAANQAECgYIBQABNQAFFAcIDAANAE8RAA==.Elarae:BAABNQAECn8xAAIVAAoK1RdoPQBLAgAVAAoK1RdoPQBLAgAAAA==.Elawen:BAAANQADCgYIBQAAAA==.Elementblah:BAABNQAECn8UAAIEAAYKng9/mgBjAQAEAAYKng9/mgBjAQAAAA==.Elfkinn:BAACNQAFFH8dAAIFAAUKkyA6DQCYAQAFAAUKkyA6DQCYAQA1AAQKf0AAAwUACgrJIi4IAA8DAAUACgrJIi4IAA8DABgAAgqjAViBABQAAAAA.Elivaniel:BAAANQADCgYIBgAAAA==.Ellemere:BAAANQAECgUIBQABNQAECgkJFAAGAP0XAA==.',
Em='Emerita:BAAANQAECgUIBQAAAA==.Emeryl:BAAANQAECgQIBQABNQAFFAcIGAAEAHUbAA==.Empathyforyo:BAABNQAECn8rAAMVAAkKdRjsSgCNAgAVAAgKXRvsSgCNAgAZAAQKAAlQVwDIAAAAAA==.',
Eq='Equinox:BAABNQAECn8eAAIFAAoKexBoOwAZAgAFAAoKexBoOwAZAgAAAA==.',
Er='Eredris:BAAANQADCgIIAgAAAA==.Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAABNQAECn8nAAMaAAkKZhrTDAD3AQAaAAgKshrTDAD3AQAbAAgKmhfQTwBaAQAAAA==.',
Es='Eshtar:BAAANQAECgUIDQAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAABNQAECn8YAAIZAAkKRBThKgD0AQAZAAkKRBThKgD0AQAAAA==.Exzanthia:BAAANQADCggICwAAAA==.',
Ey='Eyln:BAABNQAECn8dAAIZAAcKeQvBJQAnAQAZAAcKeQvBJQAnAQAAAA==.',
Fa='Falkor:BAABNQAECn89AAIcAAoKjheTEgCDAgAcAAoKjheTEgCDAgAAAA==.Fayway:BAABNQAECn9CAAMYAAoKQR/cCgAJAwAYAAoKQR/cCgAJAwAFAAEKAABoyQAZAAAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECn89AAIdAAoKwh8XBQC7AgAdAAoKwh8XBQC7AgAAAA==.',
Fi='Figgy:BAABNQAECn8zAAIIAAoKqBAYRQDzAQAIAAoKqBAYRQDzAQAAAA==.Firepower:BAABNQAECn9HAAQUAAoKzx5TJACjAgAUAAoKzx5TJACjAgAeAAIKVw6mCABqAAAfAAEKvhl5QwA9AAABNQAFFAMIBgAHAIYSAA==.',
Fo='Forevershy:BAAANQADCggILQAAAA==.',
Fr='Fries:BAEANQAECggIDwAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Ge='Georgiee:BAAANQADCgIIAgAAAA==.',
Gi='Giggles:BAABNQAECn8kAAIEAAgKjhMxVAB0AQAEAAgKjhMxVAB0AQAAAA==.',
Go='Goh:BAAANQAECgQIBAAAAA==.Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIDgABNQAFFAUIBQANAMkPAA==.Gothrim:BAAANQADCggICAAAAA==.',
Gr='Groto:BAABNQAECn8UAAIgAAcK2A13DQCDAQAgAAcK2A13DQCDAQAAAA==.Grrum:BAAANQAECgUIBAAAAA==.Grèy:BAAANQAECgYIDgAAAA==.',
Gu='Gullible:BAAANQAECgYICgAAAA==.',
Ha='Hairy:BAAANQAECgQIAwAAAA==.Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQAECggIEQAAAA==.Hanjo:BAABNQAECn8fAAILAAkK3hnwDQDBAQALAAkK3hnwDQDBAQAAAA==.Hatookorr:BAACNQAFFH8GAAIHAAMKhhL0FACzAAAHAAMKhhL0FACzAAA1AAQKfx0AAgcACApnHlMiAKMCAAcACApnHlMiAKMCAAAA.',
He='Heledrianis:BAAANQAECgYIDAAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Ho='Hornet:BAAANQADCggIJAAAAA==.',
Hy='Hydé:BAACNQAFFH8bAAMhAAgKyBmwAACdAQAhAAcKJR6wAACdAQAdAAEK9wM1BABGAAA1AAQKfx4AAiEACgq2HFILALgCACEACgq2HFILALgCAAAA.',
Ik='Ikwon:BAAANQADCgUIBwAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
In='Intuned:BAAANQAFFAIIAQABNQAFFAQICgATAA0bAA==.',
Is='Ishmael:BAAANQAECgQIBAAAAA==.Ismeldbad:BAAANQAECgQICQABNQAECgoKIQAGAF4bAA==.',
Ja='Jaland:BAAANQABCgQIBAAAAA==.',
Je='Jeddak:BAAANQADCgUIBQAAAA==.Jellybreak:BAABNQAECn8tAAMFAAcKqxCCNgBHAQAFAAcKqxCCNgBHAQAhAAcKjgeTNADjAAAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAABNQAECn8fAAIRAAkKlRIBVADUAQARAAkKlRIBVADUAQAAAA==.Kateblue:BAABNQAECn8eAAIFAAkKPA2QOQA2AQAFAAkKPA2QOQA2AQAAAA==.',
Ke='Keeble:BAAANQAECggIEQAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAABNQAECn8zAAMgAAoKtRkoBABLAgAgAAoKtRkoBABLAgAIAAMKWAWQIgF9AAAAAA==.Kelsyyr:BAAANQAECgYIBwABNQAECgoKMwAgALUZAA==.Kenpachi:BAAANQADCgEIAQAAAA==.Kethry:BAAANQAECgYIBAAAAA==.Keyas:BAAANQADCgQIBAAAAA==.',
Ki='Kidneysweeny:BAABNQAECn8hAAMGAAoKXhvWIQC9AQAGAAgK7RrWIQC9AQATAAQKXRsgOQChAAAAAA==.Kikyou:BAABNQAECn8uAAMCAAkK9x4/KQD9AQAKAAgKsiB5OQA+AgACAAkKHBU/KQD9AQABNQAFFAcIIQAiAIgeAA==.Kim:BAABNQAECn8eAAIjAAgKbA9pCADOAQAjAAgKbA9pCADOAQAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQAECgQICgAAAA==.Krelbelorll:BAABNQAECn8lAAIiAAoKyQ/IKAD+AQAiAAoKyQ/IKAD+AQAAAA==.Krowley:BAABNQAECn8mAAINAAgKwgt/kABfAQANAAgKwgt/kABfAQAAAA==.',
Ku='Kurast:BAABNQAECn8lAAIIAAkK4gWFlAAcAQAIAAkK4gWFlAAcAQABNQAECgoKPQAcAI4XAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFH8TAAMUAAcKsxodEwBBAQAUAAYKCBsdEwBBAQAfAAEKXRnzDQBUAAA1AAQKfyEAAxQACgqyIjlKAO0CABQACgqyIjlKAO0CAB8AAQp9HeZJADEAAAAA.',
Kx='Kxwono:BAABNQAECn8dAAMFAAkKbg+eXgBWAQAFAAgKEBGeXgBWAQAYAAUKeBE+OQAZAQAAAA==.',
Ky='Kyoyama:BAABNQAECn8VAAINAAkK7hJlPQAKAgANAAkK7hJlPQAKAgABNQAECgoKRQAIAHgkAA==.',
La='Ladýshinobu:BAABNQAECn8kAAIkAAcKxwsUiAAMAQAkAAcKxwsUiAAMAQAAAA==.',
Le='Leahu:BAAANQAECggICwAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgMIAwAAAA==.',
Li='Lilalpha:BAAANQAECgQIBAABNQAECgoKIQAGAF4bAA==.Lisavia:BAABNQAECn8XAAISAAgK3gNESwDqAAASAAgK3gNESwDqAAAAAA==.',
Lo='Locholovis:BAAANQAECggIEQAAAA==.Locklicous:BAACNQAFFH8GAAIIAAMKXAydGADTAAAIAAMKXAydGADTAAA1AAQKfz8AAggACgqLHgoWAL4CAAgACgqLHgoWAL4CAAE1AAQKCQkhABYAfBUA.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFH8UAAIHAAYKdRSwEABMAQAHAAYKdRSwEABMAQA1AAQKf0IAAwcACgozHyIaAB8CAAcACgqxHiIaAB8CAAoABAr/HO18ACgBAAAA.',
Lu='Luminouss:BAACNQAFFH8MAAINAAcKTxFkCwCXAQANAAcKTxFkCwCXAQA1AAQKf1MAAw0ACgpOHhMlANECAA0ACgpOHhMlANECAAQACQpqFTQsABgCAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYICQABNQAECgoKNAAHAIEZAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQAECgEIAQAAAA==.Magnuus:BAABNQAECn8aAAIXAAgK9QzXJwAeAQAXAAgK9QzXJwAeAQAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQAECgQIDAABNQAECgUICAABAAAAAA==.Manadorfirn:BAAANQADCgMIAwAAAA==.Mantis:BAABNQAECn80AAINAAoKfiGpDwAvAwANAAoKfiGpDwAvAwABNQAECgoKPQAcAI4XAA==.',
Me='Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAABNQAECn8fAAISAAkK5QyxHwB1AQASAAkK5QyxHwB1AQAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mercas:BAAANQAECggIEAAAAA==.Mezi:BAABNQAECn84AAIRAAgKwBsdQAAjAgARAAgKwBsdQAAjAgAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mh='Mhonster:BAABNQAECn8mAAMiAAoKQxuJEQAzAgAiAAoKbBqJEQAzAgAbAAQKBhRTRQADAQABNQAECgkJFAAGAP0XAA==.',
Mi='Miasma:BAAANQAECgYIDAAAAA==.Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAABNQAECn8oAAMbAAoKGhVrJwC7AQAbAAoKzQ5rJwC7AQAiAAYKdRikOgBxAQAAAA==.Misscuttie:BAAANQAECgEIAQAAAA==.',
Mo='Morjek:BAAANQADCgcICwAAAA==.Morley:BAAANQAECgQIBQAAAA==.',
Mu='Mulron:BAABNQAECn8kAAIXAAgKDhj5GAAvAgAXAAgKDhj5GAAvAgAAAA==.',
My='Myrica:BAAANQAECgcICQAAAA==.',
Ni='Nishand:BAAANQADCgEIAQAAAA==.',
Oa='Oakenshíeld:BAACNQAFFH8NAAIFAAUKuQ8pEwA4AQAFAAUKuQ8pEwA4AQA1AAQKf00AAgUACgpbIfsIAAMDAAUACgpbIfsIAAMDAAAA.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAABNQAECn8ZAAMDAAoKYhoqWgCJAgADAAoKYhoqWgCJAgAXAAEKAAA7dgAAAAAAAA==.',
Oo='Oozwoz:BAAANQAECgQICwAAAA==.',
Ou='Outfoxed:BAABNQAECn8gAAMNAAoKphzuMACdAgANAAoKphzuMACdAgAEAAEKDwdsNwEyAAABNQAFFAcIGwARAA4aAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAABNQAECn8VAAIFAAYKXQi8aQAlAQAFAAYKXQi8aQAlAQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCggIIgAAAA==.',
Pi='Pinbalwizard:BAAANQAECgUIBAABNQAECggIHgAHAFcYAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAJAGkSAA==.Plagueblade:BAABNQAECn8fAAIHAAkKNhKVNwBYAQAHAAkKNhKVNwBYAQAAAA==.',
Po='Podtinder:BAAANQAECggIBgABNQAECgoKPQAcAI4XAA==.Poppy:BAAANQAECgEIAQAAAA==.',
Pr='Progression:BAAANQAECggICwAAAA==.',
Ra='Ragingrain:BAAANQAECgcIBwAAAA==.Rainsshammy:BAABNQAECn8zAAMNAAoKPhcuNwCCAgANAAoKPhcuNwCCAgAEAAEKfguv+wAtAAAAAA==.Rassarudk:BAAANQAECgQIAgAAAA==.Rawak:BAAANQABCggIDgAAAA==.Rawktuah:BAAANQADCgMIAwAAAA==.',
Re='Realhelz:BAAANQAECgQIBAAAAA==.Redsamilf:BAABNQAECn8XAAIkAAYKKgwBvwD+AAAkAAYKKgwBvwD+AAAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAABNQAECn8UAAMkAAcKvBuWggAbAQAkAAUKFhiWggAbAQADAAYKIQzB2wAPAQAAAA==.Resaana:BAAANQAECgUICAAAAA==.Restofarian:BAACNQAFFH8FAAINAAUKyQ+pDgBkAQANAAUKyQ+pDgBkAQA1AAQKfycAAw0ACQqOIroMAFoDAA0ACQqOIroMAFoDAAQABApRELLdANoAAAAA.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAABNQAECn8UAAIlAAYKrRDqHQCCAQAlAAYKrRDqHQCCAQAAAA==.',
Ri='Rianon:BAAANQADCggIDwABNQAECgkJFAAbABQZAA==.Rikel:BAAANQADCgQIBAAAAA==.Rizzy:BAABNQAECn84AAMKAAoKWA5HTADjAQAKAAoKWA5HTADjAQACAAcKmgfbWgA+AQAAAA==.',
Ro='Rotinshot:BAACNQAFFH8JAAIVAAMKkhTVFADbAAAVAAMKkhTVFADbAAA1AAQKfyoAAxUACgpLHvknAJICABUACgpLHvknAJICABkAAgopBXB9AE4AAAAA.Rottinheals:BAAANQAECgYICwABNQAFFAMICQAVAJIUAA==.',
Ru='Rutikee:BAABNQAECn84AAMYAAoKaBLFGwANAgAYAAoKaBLFGwANAgAFAAIKiQP9pABQAAAAAA==.',
Ry='Rykér:BAAANQAECgUIBQABNQAFFAgIGwAhAMgZAA==.Ryomensukuna:BAABNQAECn8UAAIKAAkK0yCrKACWAgAKAAkK0yCrKACWAgAAAA==.',
Sa='Sahrotaar:BAAANQAECggIAQAAAA==.Sandrill:BAAANQAECgQJBQABNQAFFAMIBgAHAIYSAA==.Savior:BAAANQAECgQIBgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.Scrom:BAAANQADCgMIAgAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgUIBQAAAA==.Seizon:BAABNQAECn8gAAIjAAcKkRckCABmAQAjAAcKkRckCABmAQAAAA==.Senseicanz:BAAANQADCgYIBgAAAA==.Serom:BAABNQAECn8kAAMYAAgKGhmfFABqAgAYAAgKGhmfFABqAgAFAAIKnAa4pwBIAAAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggICwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sharpshôôter:BAAANQAECgQIBQAAAA==.Sherunn:BAABNQAECn8VAAIFAAUKqgTRggDFAAAFAAUKqgTRggDFAAAAAA==.Shimakaze:BAABNQAECn8wAAIVAAkKAwlmkwByAQAVAAkKAwlmkwByAQAAAA==.Shmitty:BAAANQAECgcICwABNQAFFAQICgATAA0bAA==.Shooters:BAABNQAECn8UAAMjAAcK/Ro5CADXAQAVAAcKuRfukwDhAQAjAAYKHBg5CADXAQAAAA==.Shyminx:BAAANQADCgcICwAAAA==.Shymistress:BAABNQAECn89AAIVAAoKEx3WOABYAgAVAAoKEx3WOABYAgAAAA==.Shåmmy:BAABNQAECn80AAINAAoKihS0SgA4AgANAAoKihS0SgA4AgAAAA==.',
Si='Sindralea:BAABNQAECn8nAAIbAAkKaxjkIQDmAQAbAAkKaxjkIQDmAQAAAA==.',
Sk='Skiá:BAABNQAECn83AAIdAAkKVh/zCABAAgAdAAkKVh/zCABAAgAAAA==.',
Sl='Slayerkitty:BAAANQABCgEIAQAAAA==.Slicedbread:BAAANQAECgEIAQAAAA==.',
So='Solaene:BAABNQAECn8UAAIGAAkK/ReOIwBpAgAGAAkK/ReOIwBpAgAAAA==.Songatsu:BAAANQADCggIDAAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Sparkleglory:BAAANQAECgYIBwAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAABNQAECn8zAAIDAAoKRxrETAA0AgADAAoKRxrETAA0AgAAAA==.Stonefaith:BAAANQAECggICgAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAQICgATAA0bAA==.Stormfox:BAABNQAECn8ZAAIEAAgKnwbApwBFAQAEAAgKnwbApwBFAQAAAA==.Strawhat:BAAANQAECgQICwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgYIEQAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQAECgQICQAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.Synginryxari:BAAANQAECgEIAQAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAABNQAECn8mAAMcAAkKwRjQCACmAgAcAAkKwRjQCACmAgAOAAQKTQskGgCOAAAAAA==.Tannuk:BAABNQAECn9FAAIXAAoKSBxqCwBqAgAXAAoKSBxqCwBqAgAAAA==.Tarz:BAAANQABCgIIAgAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAABNQAECn84AAIEAAoKaxrJMwCqAgAEAAoKaxrJMwCqAgAAAA==.',
Th='Thekingbak:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAABNQAECn8vAAIkAAkKAxeTVQAZAgAkAAkKAxeTVQAZAgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tn='Tntclepriest:BAAANQAECgEIAQABNQAECgMIAgABAAAAAA==.',
To='Toru:BAAANQAECggIEQABNQAECgoKSwADAAkiAA==.Totems:BAABNQAECn8pAAIlAAkKchj8DQAgAgAlAAkKchj8DQAgAgABNQAECgMIAgABAAAAAA==.Touchmycheek:BAAANQADCggICAAAAA==.',
Tr='Tridius:BAABNQAECn+BAAMRAAoKkyUlAQA2BAARAAoKkyUlAQA2BAASAAIKAADqdAA8AAAAAA==.Trixx:BAAANQAECgUICwAAAA==.Truda:BAAANQADCgEIAQAAAA==.',
Tu='Tuffcracker:BAAANQAECgUICgAAAA==.Turdanator:BAABNQAECn8fAAMRAAoK7hScMwBcAgARAAoK7hScMwBcAgASAAgKgA+NGgCvAQAAAA==.',
Tw='Twinturboj:BAABNQAECn8WAAIJAAcK5AS8+gDnAAAJAAcK5AS8+gDnAAAAAA==.Twittle:BAAANQAECgUIEwAAAA==.',
Ty='Tylovastus:BAABNQAECn8aAAIVAAkKvg+AdAC6AQAVAAkKvg+AdAC6AQAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.Tyton:BAAANQADCgMIAwAAAA==.',
Ub='Ube:BAABNQAECn8bAAIJAAgKjx/QRwCyAgAJAAgKjx/QRwCyAgAAAA==.',
Ur='Uriah:BAABNQAECn8hAAIVAAYKZQvqrwA3AQAVAAYKZQvqrwA3AQAAAA==.Ursúla:BAABNQAECn8cAAIIAAoKAQ+6cwAGAgAIAAoKAQ+6cwAGAgABNQAFFAUIHQAFAJMgAA==.Urïah:BAAANQADCgYICQABNQAECgYIIQAVAGULAA==.',
Va='Valaravaus:BAAANQADCggICwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.Veryletheone:BAAANQAECgQIBQAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgYIDgAAAA==.',
['Vé']='Végeta:BAABNQAECn8XAAMiAAgKFgIjXQCEAAAiAAgKFgIjXQCEAAAbAAEKZARWjQARAAABNQAECgoKPQAcAI4XAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wh='Whitecoma:BAAANQABCgIIAgAAAA==.',
Wo='Wooloo:BAACNQAFFH8RAAQIAAgKcxUTGQAsAQAIAAYKXhUTGQAsAQAgAAIK0Ae1CQBaAAAMAAEKbiOZFgBXAAA1AAQKfzAABAgACgr+JWoCAG0DAAgACgr5JWoCAG0DAAwABwp3G5oPAAMCACAAAQpPJfUgAF8AAAAA.',
Wy='Wynona:BAACNQAFFH8IAAIUAAMKGgpOJwDOAAAUAAMKGgpOJwDOAAA1AAQKfzwAAhQACgrEF7FEADECABQACgrEF7FEADECAAAA.',
Xa='Xanagore:BAABNQAECn8fAAMJAAgKsBA1qgCzAQAJAAgKsBA1qgCzAQALAAMKWAuXNQCIAAAAAA==.Xanshamoo:BAAANQAECgUIBQAAAA==.',
Xk='Xkwon:BAAANQAECgIIAwAAAA==.Xkwøn:BAACNQAFFH8QAAImAAYK3BVPAAAwAQAmAAYK3BVPAAAwAQA1AAQKfzsAAiYACgrMI6kAAPgCACYACgrMI6kAAPgCAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAABNQAECn8ZAAIiAAoKrw0nNQCaAQAiAAoKrw0nNQCaAQAAAA==.',
Xu='Xunie:BAAANQADCggIKwAAAA==.',
Yl='Yloh:BAABNQAECn8kAAQRAAkKMCQrBwCLAwARAAkKMCQrBwCLAwASAAYK4wX7WAClAAAQAAIK3Q1SIABfAAAAAA==.',
Yo='Yoquiere:BAAANQAECgQIBAAAAA==.',
Za='Zaisplash:BAAANQAECgUICgAAAA==.Zana:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgYIDQABAAAAAA==.Zaretan:BAAANQADCggIJAAAAA==.',
Zb='Zbrute:BAABNQAECn8lAAIVAAgKhhK0dQAkAgAVAAgKhhK0dQAkAgAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAACNQAFFH8bAAQKAAgK4A50BAAiAQAKAAUK6Q10BAAiAQACAAYKEA6FDAAXAQAHAAEKAAC5NAAqAAA1AAQKfygAAwoACgo9INwQAGgCAAoACgo2H9wQAGgCAAIABgqPGO9lAOsAAAAA.',
Zu='Zulpher:BAAANQADCggIIAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgIIAgAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAACNQAFFH8LAAIUAAUK6Rb+JQDVAAAUAAUK6Rb+JQDVAAA1AAQKfysAAhQACgpHI60OABEDABQACgpHI60OABEDAAAA.',
['ße']='ßeorn:BAAANQABCgIIAgABNQAECgoKgQARAJMlAA==.',
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
