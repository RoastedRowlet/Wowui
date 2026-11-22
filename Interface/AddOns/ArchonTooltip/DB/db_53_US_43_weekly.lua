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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Paladin-Retribution','Shaman-Elemental','Druid-Balance','Paladin-Protection','Rogue-Subtlety','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Warlock-Demonology','DeathKnight-Unholy','Warrior-Protection','Warlock-Destruction','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Priest-Holy','Priest-Shadow','Rogue-Assassination','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Mage-Fire','Mage-Frost','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','DemonHunter-Devourer','Hunter-Survival','Paladin-Holy','Shaman-Enhancement','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAABNQAECn8yAAICAAoKCRJ1KwAEAgACAAoKCRJ1KwAEAgABNQAECgoKTwADAAkiAA==.',
Ae='Aeolos:BAAANQADCggIEgAAAA==.Aesthetic:BAAANQAECgcIDgABNQAFFAcIGAAEAHUbAA==.',
Ag='Agrios:BAACNQAFFH8KAAIFAAMKrQ6CFADNAAAFAAMKrQ6CFADNAAA1AAQKf10AAgUACgrJH78NAMsCAAUACgrJH78NAMsCAAAA.',
Ai='Aiellee:BAAANQAECgUIBwAAAA==.',
Ak='Akias:BAABNQAECn8WAAIGAAcKEwInSgDDAAAGAAcKEwInSgDDAAAAAA==.',
Al='Alexandra:BAAANQAECgYIDQABNQAFFAIIBQAHAEIIAA==.Alliekill:BAAANQAECgMIAwABNQAECgkJHgAIAAYPAA==.Altaurus:BAAANQAECgUIDQAAAA==.Alynnei:BAABNQAECn8WAAMJAAkKRRNsVQD9AQAJAAkKRRNsVQD9AQAKAAEKzBQsMQBCAAABNQAFFAIIBQAHAEIIAA==.',
Am='Amare:BAAANQAECgUIEgAAAA==.Amiria:BAAANQADCggICwAAAA==.',
An='Andros:BAABNQAECn8gAAILAAgK1xSRlQCwAQALAAgK1xSRlQCwAQAAAA==.Anekaatwo:BAAANQAECgEIAQAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Araxe:BAAANQAECgQIBAABNQAECgoKPAAJAFAbAA==.Arroyo:BAABNQAECn89AAIMAAoKJSAcEQAuAwAMAAoKJSAcEQAuAwAAAA==.',
As='Askadar:BAACNQAFFH8KAAINAAQK6SXSAQAzAQANAAQK6SXSAQAzAQA1AAQKfy0AAg0ACgr4JiEAAAsEAA0ACgr4JiEAAAsEAAAA.',
Az='Azora:BAABNQAECn8kAAMOAAoKRhesDAAtAgAOAAcK3xmsDAAtAgALAAgKxxSmhwDTAQAAAA==.Azzura:BAAANQAECgEIAQAAAA==.',
Ba='Baheem:BAAANQAECgQIDwAAAA==.Bams:BAABNQAECn8pAAIPAAkK2BWNZwB/AQAPAAkK2BWNZwB/AQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECn8rAAMQAAoK2R1uCQDbAgAQAAoK2R1uCQDbAgARAAEK3AGoKAAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECn8nAAIDAAoK6hHMcgBJAgADAAoK6hHMcgBJAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAABNQAECn8XAAMNAAgKWgk0HwAEAQANAAgKWgk0HwAEAQAJAAEKcgIzNgEmAAAAAA==.',
Bi='Bifrons:BAAANQADCgYIGAAAAA==.Bigdill:BAAANQAECgQIBAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIBgAAAA==.Bluè:BAAANQAECgQIBgAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCggIHwAAAA==.Boolil:BAABNQAECn8YAAIPAAkK+QcZfwA2AQAPAAkK+QcZfwA2AQABNQAECgoKQwASAC0PAA==.Boolove:BAAANQAECgcIBQABNQAECgoKQwASAC0PAA==.Booloved:BAABNQAECn9DAAQSAAoKLQ+MBgCEAQASAAkKAg+MBgCEAQATAAoKOwdtdgB3AQAUAAkKHgSLPABGAQAAAA==.',
Bq='Bqcritraven:BAAANQADCgUIBQAAAA==.',
Br='Brotato:BAAANQAECggIDgABNQAFFAMIBgAIAIYSAA==.Broxx:BAAANQADCgcICQAAAA==.',
Bu='Bulwei:BAAANQAECgcIDQAAAA==.',
Bw='Bwimbosawme:BAAANQAFFAMIAgABNQAFFAQICgAVAA0bAA==.',
By='Byssrak:BAAANQAECgQICgAAAA==.',
Ca='Calmcarnage:BAAANQAECgEIAQAAAA==.Carmêl:BAAANQAECgYICQABNQAECgoKQAAWAFohAA==.Cattiebuzz:BAAANQADCgIIAgABNQAECgoKLwAXAAQZAA==.Cattiegreen:BAABNQAECn8vAAIXAAoKBBnoYQADAgAXAAoKBBnoYQADAgAAAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Christopher:BAABNQAECn8pAAIWAAoK0xXXgwB3AgAWAAoK0xXXgwB3AgAAAA==.',
Co='Consolata:BAAANQADCgMIAwAAAA==.Costica:BAAANQADCgUIBQAAAA==.',
Cr='Creepychaos:BAAANQADCggIDwABNQAECgkJGQAMANoFAA==.Creepydemise:BAABNQAECn8ZAAIMAAkK2gVaPwATAQAMAAkK2gVaPwATAQAAAA==.Creepydrunk:BAAANQADCggIGQABNQAECgkJGQAMANoFAA==.Croixsmash:BAABNQAECn8hAAMKAAkKfBWtFwAIAQAJAAgKFhXmkwDqAQAKAAYKhxStFwAIAQAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.Curse:BAAANQAECgMIAwAAAA==.',
Cy='Cylvanna:BAAANQAECgYIDwAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Darkrest:BAAANQADCggIFwAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgkJIQAKAHwVAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECn9AAAIDAAoKQw/4mQCZAQADAAoKQw/4mQCZAQAAAA==.Dawnn:BAAANQAECgcIEgAAAA==.',
De='Deanwnchestr:BAABNQAECn8nAAIWAAkKaQSnvgApAQAWAAkKaQSnvgApAQAAAA==.Deatnshadow:BAAANQAECggIDgAAAA==.Delyrius:BAAANQADCggICAABNQAECgoKNQAIAJwZAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgYICwAAAA==.',
Do='Dogeatdog:BAAANQADCggIIAAAAA==.Dorus:BAAANQADCgQIBAAAAA==.',
Dr='Draakell:BAABNQAECn8ZAAIMAAgK2Q5ZOgAtAQAMAAgK2Q5ZOgAtAQAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAABNQAECn8lAAMOAAgKxAo5CgAiAQAOAAgKEAo5CgAiAQALAAYKLgbetwDjAAAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.Dryrain:BAABNQAECn8fAAMGAAoKexF7GACzAQAGAAoKexF7GACzAQADAAIKMQO0qgEoAAAAAA==.',
Du='Dudè:BAAANQAECgYIDwAAAA==.',
['Dâ']='Dâggèr:BAACNQAFFH8KAAMVAAQKDRsqDwD3AAAVAAQKDRsqDwD3AAAHAAEKqAMbKQA+AAA1AAQKfyQAAhUACQpEJJoBAFQDABUACQpEJJoBAFQDAAAA.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggIDAAAAA==.',
El='Eladawn:BAAANQAECgYIBQABNQAFFAcIDAAPAE8RAA==.Elarae:BAABNQAECn8xAAIXAAoK1RcERQBJAgAXAAoK1RcERQBJAgAAAA==.Elawen:BAAANQADCgYIBQAAAA==.Elementblah:BAABNQAECn8UAAIEAAYKng9/mgBjAQAEAAYKng9/mgBjAQAAAA==.Elfkinn:BAACNQAFFH8dAAIFAAUKkyA6DQCYAQAFAAUKkyA6DQCYAQA1AAQKf0AAAwUACgrJIvcIAAwDAAUACgrJIvcIAAwDABgAAgqjAQCIABQAAAAA.Elivaniel:BAAANQADCgYIBgAAAA==.Ellemere:BAAANQAECgYIBwABNQAFFAIIBQAHAEIIAA==.',
Em='Emerita:BAAANQAECgUIBQAAAA==.Emeryl:BAAANQAECgQIBQABNQAFFAcIGAAEAHUbAA==.Empathyforyo:BAABNQAECn8rAAMXAAkKdRjsSgCNAgAXAAgKXRvsSgCNAgAZAAQKAAlQVwDIAAAAAA==.',
Eq='Equinox:BAABNQAECn8eAAIFAAoKexBoOwAZAgAFAAoKexBoOwAZAgAAAA==.',
Er='Eredris:BAAANQADCgIIAgAAAA==.Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAABNQAECn8sAAMaAAkKXRvTDAD3AQAaAAgKshrTDAD3AQAbAAgKthnEQgApAQAAAA==.',
Es='Eshtar:BAAANQAECgUIDgAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAABNQAECn8YAAIZAAkKRBThKgD0AQAZAAkKRBThKgD0AQAAAA==.Exzanthia:BAAANQADCggICwAAAA==.',
Ey='Eyln:BAABNQAECn8lAAIZAAgKmwuaHwB1AQAZAAgKmwuaHwB1AQAAAA==.',
Fa='Falkor:BAABNQAECn89AAIcAAoKjheTEgCDAgAcAAoKjheTEgCDAgAAAA==.Fayway:BAABNQAECn9CAAMYAAoKQR9CDAAGAwAYAAoKQR9CDAAGAwAFAAEKAABoyQAZAAAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECn89AAIdAAoKwh+7BQC2AgAdAAoKwh+7BQC2AgAAAA==.',
Fi='Figgy:BAABNQAECn8zAAILAAoKqBCfSwDxAQALAAoKqBCfSwDxAQAAAA==.Firepower:BAABNQAECn9JAAQWAAoKPx8AJgCnAgAWAAoKPx8AJgCnAgAeAAIKVw6gCQBqAAAfAAEKvhl5QwA9AAABNQAFFAMIBgAIAIYSAA==.',
Fo='Forevershy:BAAANQADCggILQAAAA==.',
Fr='Fries:BAEANQAECggIDwAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Ge='Georgiee:BAAANQADCgIIAgAAAA==.',
Gi='Giggles:BAABNQAECn8pAAIEAAgKfBS5WAB9AQAEAAgKfBS5WAB9AQAAAA==.',
Go='Goh:BAAANQAECgQIBAAAAA==.Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIDgABNQAFFAUIBQAPAMkPAA==.Gothrim:BAAANQADCggICAAAAA==.',
Gr='Groto:BAABNQAECn8UAAIgAAcK2A13DQCDAQAgAAcK2A13DQCDAQAAAA==.Grrum:BAAANQAECgQIBgAAAA==.Grèy:BAAANQAECgYIDgAAAA==.',
Gu='Gullible:BAAANQAECgYICgAAAA==.',
Ha='Hairy:BAAANQAECgQIAwAAAA==.Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAABNQAECn8YAAMhAAgKlAbbOwDLAAAhAAcKGATbOwDLAAAiAAYKsgeUGQCiAAAAAA==.Hanjo:BAABNQAECn8hAAINAAkK8Bn9DQDbAQANAAkK8Bn9DQDbAQAAAA==.Hatookorr:BAACNQAFFH8GAAIIAAMKhhIWGACtAAAIAAMKhhIWGACtAAA1AAQKfx0AAggACApnHlMiAKMCAAgACApnHlMiAKMCAAAA.',
He='Heledrianis:BAAANQAECgYIDQAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Ho='Hornet:BAAANQADCggIJAAAAA==.',
Hy='Hydé:BAACNQAFFH8bAAMjAAgKyBneAACYAQAjAAcKJR7eAACYAQAdAAEK9wOzBABFAAA1AAQKfx4AAiMACgq2HFILALgCACMACgq2HFILALgCAAAA.',
Ik='Ikwon:BAAANQADCgUIBwAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
In='Intuned:BAAANQAFFAIIAQABNQAFFAQICgAVAA0bAA==.',
Is='Ishmael:BAAANQAECgQIBAAAAA==.Ismeldbad:BAAANQAECgQICgABNQAECgoKIwAVAFYcAA==.',
Ja='Jaland:BAAANQABCgQIBAAAAA==.',
Je='Jeddak:BAAANQADCgUIBQAAAA==.Jellybreak:BAABNQAECn81AAMjAAgKHBB8LwAYAQAFAAcKqxCaOgBGAQAjAAgKYAl8LwAYAQAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAABNQAECn8hAAITAAkKlRIkWgDVAQATAAkKlRIkWgDVAQAAAA==.Kateblue:BAABNQAECn8gAAIFAAkKhQ18MwBwAQAFAAkKhQ18MwBwAQAAAA==.',
Ke='Keeble:BAAANQAECggIEQAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAABNQAECn83AAMgAAoKthoHBABjAgAgAAoKthoHBABjAgALAAMKWAWQIgF9AAAAAA==.Kelsyyr:BAAANQAECgYIBwABNQAECgoKNwAgALYaAA==.Kenpachi:BAAANQADCgEIAQAAAA==.Kethry:BAAANQAECgYIBAAAAA==.Keyas:BAAANQADCgQIBAAAAA==.',
Ki='Kidneysweeny:BAABNQAECn8jAAMVAAoKVhy/IwAQAQAHAAgK7RrWIQC9AQAVAAQKTh2/IwAQAQAAAA==.Kikyou:BAABNQAECn8uAAMMAAkK9x55OQA+AgAMAAgKsiB5OQA+AgACAAkKHBWyLQD4AQABNQAFFAcIIQAkAIgeAA==.Kim:BAABNQAECn8jAAIlAAkKcg9pCADOAQAlAAkKcg9pCADOAQAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQAECgYIEAAAAA==.Krelbelorll:BAABNQAECn8lAAIkAAoKyQ/IKAD+AQAkAAoKyQ/IKAD+AQAAAA==.Krowley:BAABNQAECn8rAAIPAAkK+wxPeQBHAQAPAAkK+wxPeQBHAQAAAA==.',
Ku='Kurast:BAABNQAECn8lAAILAAkK4gWsngAaAQALAAkK4gWsngAaAQABNQAECgoKPQAcAI4XAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFH8UAAMWAAgKeBfmDwCGAQAWAAcKFxfmDwCGAQAfAAEKXRmMDwBUAAA1AAQKfyEAAxYACgqyIjlKAO0CABYACgqyIjlKAO0CAB8AAQp9HeZJADEAAAAA.',
Kx='Kxwono:BAABNQAECn8dAAMFAAkKbg+eXgBWAQAFAAgKEBGeXgBWAQAYAAUKeBHBPQAYAQAAAA==.',
Ky='Kyoyama:BAABNQAECn8VAAIPAAkK7hKtQwAFAgAPAAkK7hKtQwAFAgABNQAECgoKSQALAMokAA==.',
La='Ladýshinobu:BAABNQAECn8oAAImAAgKJAxjegBGAQAmAAgKJAxjegBGAQAAAA==.',
Le='Leahu:BAAANQAECggICwAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgMIAwAAAA==.',
Li='Licaloapus:BAAANQAECgEIAQAAAA==.Lilalpha:BAAANQAECgQIBAABNQAECgoKIwAVAFYcAA==.Lisavia:BAABNQAECn8cAAIUAAkKZgRESwDqAAAUAAkKZgRESwDqAAAAAA==.',
Lo='Locholovis:BAAANQAECggIEQAAAA==.Locklicous:BAACNQAFFH8GAAILAAMKXAwfHADPAAALAAMKXAwfHADPAAA1AAQKfz8AAgsACgqLHosZALYCAAsACgqLHosZALYCAAE1AAQKCQkhAAoAfBUA.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFH8VAAIIAAcKyRFzDgAeAQAIAAcKyRFzDgAeAQA1AAQKf0IAAwgACgozH2siAKICAAgACgqxHmsiAKICAAwABAr/HO18ACgBAAAA.',
Lu='Luminouss:BAACNQAFFH8MAAIPAAcKTxFkCwCXAQAPAAcKTxFkCwCXAQA1AAQKf1sAAw8ACgpOHhMlANECAA8ACgpOHhMlANECAAQACQrtFasvABsCAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYICQABNQAECgoKNQAIAJwZAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQAECgEIAQAAAA==.Magnuus:BAABNQAECn8cAAIGAAgK9Qw/KwAcAQAGAAgK9Qw/KwAcAQAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQAECgQIDAABNQAECgUICAABAAAAAA==.Manadorfirn:BAAANQADCgMIAwAAAA==.Mantis:BAABNQAECn80AAIPAAoKfiHbEQArAwAPAAoKfiHbEQArAwABNQAECgoKPQAcAI4XAA==.',
Me='Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAABNQAECn8hAAMUAAkK5QzQIQB5AQAUAAkK5QzQIQB5AQATAAEK1gNN+gAsAAAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mercas:BAAANQAECggIEAAAAA==.Mezi:BAABNQAECn9AAAITAAkKmhkbOwBPAgATAAkKmhkbOwBPAgAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mh='Mhonster:BAABNQAECn8qAAMkAAoKixsIEwAwAgAkAAoKbBoIEwAwAgAbAAQKUheERAAgAQABNQAFFAIIBQAHAEIIAA==.',
Mi='Miasma:BAAANQAECgcIDQAAAA==.Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAABNQAECn8pAAMbAAoKGhUOKwC4AQAbAAoKzQ4OKwC4AQAkAAYKdRikOgBxAQAAAA==.Misscuttie:BAAANQAECgEIAgAAAA==.',
Mo='Morjek:BAAANQADCgcICwAAAA==.Morley:BAAANQAECgQIBQAAAA==.',
Ms='Msvelvet:BAAANQADCgQIAgABNQAECgQICQABAAAAAA==.',
Mu='Mulron:BAABNQAECn8pAAIGAAkK4Bb5GAAvAgAGAAkK4Bb5GAAvAgAAAA==.',
My='Myrica:BAAANQAECgcICQAAAA==.',
Ni='Nishand:BAAANQADCgEIAQAAAA==.',
Oa='Oakenshíeld:BAACNQAFFH8NAAIFAAUKuQ8pEwA4AQAFAAUKuQ8pEwA4AQA1AAQKf00AAgUACgpbIc4JAAADAAUACgpbIc4JAAADAAAA.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAABNQAECn8ZAAMDAAoKYhoqWgCJAgADAAoKYhoqWgCJAgAGAAEKAACRfAAAAAAAAA==.',
Oo='Oozwoz:BAAANQAECgUIEAAAAA==.',
Ou='Outfoxed:BAABNQAECn8gAAMPAAoKphzuMACdAgAPAAoKphzuMACdAgAEAAEKDwdsNwEyAAABNQAFFAcIGwATAA4aAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAABNQAECn8VAAIFAAYKXQi8aQAlAQAFAAYKXQi8aQAlAQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCggIKAAAAA==.',
Pi='Pinbalwizard:BAAANQAECgUIBAABNQAECggIHgAIAFcYAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAJAGkSAA==.Plagueblade:BAABNQAECn8hAAIIAAkKZRLeOQBbAQAIAAkKZRLeOQBbAQAAAA==.',
Po='Podtinder:BAAANQAECggIBgABNQAECgoKPQAcAI4XAA==.Poppy:BAAANQAECgEIAQAAAA==.',
Pr='Progression:BAAANQAECggICwAAAA==.',
Ra='Ragingrain:BAAANQAECgcIBwAAAA==.Rainsshammy:BAABNQAECn8zAAMPAAoKPhcuNwCCAgAPAAoKPhcuNwCCAgAEAAEKfgtoBwEtAAAAAA==.Rassarudk:BAAANQAECgQIAgAAAA==.Rawak:BAAANQABCggIDgAAAA==.Rawktuah:BAAANQADCgMIAwABNQAFFAIIBgAXAGgJAA==.',
Re='Realhelz:BAAANQAECgQIBAAAAA==.Redsamilf:BAABNQAECn8YAAImAAcKkgt5mgDvAAAmAAcKkgt5mgDvAAAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAABNQAECn8UAAMmAAcKvBtEigAZAQAmAAUKFhhEigAZAQADAAYKIQzY6gAMAQAAAA==.Resaana:BAAANQAECgUICAAAAA==.Restofarian:BAACNQAFFH8FAAIPAAUKyQ+pDgBkAQAPAAUKyQ+pDgBkAQA1AAQKfycAAw8ACQqOIroMAFoDAA8ACQqOIroMAFoDAAQABApRELLdANoAAAAA.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAABNQAECn8UAAInAAYKrRDqHQCCAQAnAAYKrRDqHQCCAQAAAA==.',
Ri='Rianon:BAAANQADCggIDwABNQAECgkJFAAbABQZAA==.Rikel:BAAANQADCgQIBAAAAA==.Rizzy:BAABNQAECn84AAMMAAoKWA5HTADjAQAMAAoKWA5HTADjAQACAAcKmgfbWgA+AQAAAA==.',
Ro='Rotinshot:BAACNQAFFH8JAAIXAAMKkhRCFwDZAAAXAAMKkhRCFwDZAAA1AAQKfyoAAxcACgpLHl0rAOwCABcACgpLHl0rAOwCABkAAgopBXB9AE4AAAAA.Rottinheals:BAAANQAECgYICwABNQAFFAMICQAXAJIUAA==.',
Ru='Rutikee:BAABNQAECn85AAMYAAoKaBLAHgAKAgAYAAoKaBLAHgAKAgAFAAIKiQP9pABQAAAAAA==.',
Ry='Rykér:BAAANQAECgUIBQABNQAFFAgIGwAjAMgZAA==.Ryomensukuna:BAABNQAECn8UAAIMAAkK0yCrKACWAgAMAAkK0yCrKACWAgAAAA==.',
Sa='Sahrotaar:BAAANQAECggIAQAAAA==.Sandrill:BAAANQAECgQJBQABNQAFFAMIBgAIAIYSAA==.Savior:BAAANQAECgQICgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.Scrom:BAAANQADCgMIAgAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgUIBQAAAA==.Seizon:BAABNQAECn8mAAIlAAcKxRegCABvAQAlAAcKxRegCABvAQAAAA==.Senseicanz:BAAANQADCgYIBgAAAA==.Serom:BAABNQAECn8nAAMYAAkKNxqPDwDOAgAYAAkKNxqPDwDOAgAFAAIKnAa4pwBIAAAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggICwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sharpshôôter:BAAANQAECggIDwAAAA==.Sherunn:BAABNQAECn8XAAIFAAUKqgTRggDFAAAFAAUKqgTRggDFAAAAAA==.Shimakaze:BAABNQAECn83AAIXAAkKZwmhmQCBAQAXAAkKZwmhmQCBAQAAAA==.Shmitty:BAAANQAECgcICwABNQAFFAQICgAVAA0bAA==.Shooters:BAABNQAECn8UAAMlAAcK/Ro5CADXAQAXAAcKuRfukwDhAQAlAAYKHBg5CADXAQAAAA==.Shyminx:BAAANQADCggIEwAAAA==.Shymistress:BAABNQAECn9AAAIXAAoK0x0eOwBiAgAXAAoK0x0eOwBiAgAAAA==.Shåmmy:BAABNQAECn80AAIPAAoKihS0SgA4AgAPAAoKihS0SgA4AgAAAA==.',
Si='Sindralea:BAABNQAECn8pAAIbAAkKaxizJADlAQAbAAkKaxizJADlAQAAAA==.',
Sk='Skiá:BAABNQAECn83AAIdAAkKVh80CgA7AgAdAAkKVh80CgA7AgAAAA==.',
Sl='Slayerkitty:BAAANQABCgEIAQAAAA==.Slicedbread:BAAANQAECgEIAQAAAA==.',
So='Solaene:BAACNQAFFH8FAAIHAAIKQggUHwCHAAAHAAIKQggUHwCHAAA1AAQKfxcAAgcACQp5GKUkAHICAAcACQp5GKUkAHICAAAA.Songatsu:BAAANQADCggIDAAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Sparkleglory:BAAANQAECgYIBwAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAABNQAECn85AAIDAAoKcxpsTABFAgADAAoKcxpsTABFAgAAAA==.Stonefaith:BAAANQAECggICgAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAQICgAVAA0bAA==.Stormfox:BAABNQAECn8cAAIEAAgKnwbApwBFAQAEAAgKnwbApwBFAQAAAA==.Strawhat:BAAANQAECgQICwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgYIEgAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQAECgQICQAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.Synginryxari:BAAANQAECgEIAQAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAABNQAECn8oAAMcAAkKwRiHCQClAgAcAAkKwRiHCQClAgAQAAUKTwo0GAC4AAAAAA==.Tannuk:BAABNQAECn9OAAIGAAoK0RzaCwB2AgAGAAoK0RzaCwB2AgAAAA==.Tarz:BAAANQABCgIIAgAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAABNQAECn84AAIEAAoKaxrJMwCqAgAEAAoKaxrJMwCqAgAAAA==.',
Th='Thekingbak:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAABNQAECn82AAImAAkKAxeTVQAZAgAmAAkKAxeTVQAZAgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tn='Tntclepriest:BAAANQAECgEIAQABNQAECgMIAgABAAAAAA==.',
To='Toru:BAABNQAECn8TAAIXAAkKqAxTYgACAgAXAAkKqAxTYgACAgABNQAECgoKTwADAAkiAA==.Totems:BAABNQAECn8pAAInAAkKchiODwAcAgAnAAkKchiODwAcAgABNQAECgMIAgABAAAAAA==.Touchmycheek:BAAANQADCggICAAAAA==.',
Tr='Tridius:BAABNQAECn+HAAMTAAoKkyWNAQAzBAATAAoKkyWNAQAzBAAUAAUKPxObOgDKAAAAAA==.Trixx:BAAANQAECgUICwAAAA==.Truda:BAAANQADCgEIAQAAAA==.',
Tu='Tuffcracker:BAAANQAECgUIDgAAAA==.Turdanator:BAABNQAECn8fAAMTAAoK7hRHOgBSAgATAAoK7hRHOgBSAgAUAAgKgA+eHACvAQAAAA==.',
Tw='Twinturboj:BAABNQAECn8WAAIJAAcK5AS8+gDnAAAJAAcK5AS8+gDnAAAAAA==.Twittle:BAAANQAECgUIEwAAAA==.',
Ty='Tylovastus:BAABNQAECn8aAAIXAAkKvg+ZgAC5AQAXAAkKvg+ZgAC5AQAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.Tyton:BAAANQADCgMIAwAAAA==.',
Ub='Ube:BAABNQAECn8bAAIJAAgKjx/QRwCyAgAJAAgKjx/QRwCyAgAAAA==.',
Ur='Uriah:BAABNQAECn8jAAIXAAcKLAzSmwB9AQAXAAcKLAzSmwB9AQAAAA==.Ursúla:BAABNQAECn8cAAILAAoKAQ+6cwAGAgALAAoKAQ+6cwAGAgABNQAFFAUIHQAFAJMgAA==.Urïah:BAAANQADCgYICQABNQAECgcIIwAXACwMAA==.',
Va='Valaravaus:BAAANQADCggICwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.Veryletheone:BAAANQAECgQIBQAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgYIDgAAAA==.',
['Vé']='Végeta:BAABNQAECn8XAAMkAAgKFgIjXQCEAAAkAAgKFgIjXQCEAAAbAAEKZAR+lAARAAABNQAECgoKPQAcAI4XAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wh='Whitecoma:BAAANQABCgIIAgAAAA==.',
Wi='Wildsmite:BAAANQAECgEIAQABNQAECgkJIAAYAMgYAA==.',
Wo='Wooloo:BAACNQAFFH8UAAQLAAgKBxsTGQAsAQALAAYKeBgTGQAsAQAgAAIK3BwVDABdAAAOAAEKbiOZFgBXAAA1AAQKfzAABAsACgr+Jf8CAGkDAAsACgr5Jf8CAGkDAA4ABwp3G5oPAAMCACAAAQpPJf4jAF4AAAAA.',
Wy='Wynona:BAACNQAFFH8IAAIWAAMKGgo7LADFAAAWAAMKGgo7LADFAAA1AAQKfzwAAhYACgrEF11KAC8CABYACgrEF11KAC8CAAAA.',
Xa='Xanagore:BAABNQAECn8iAAMJAAkK2hI1qgCzAQAJAAkK2hI1qgCzAQANAAMKWAuXNQCIAAAAAA==.Xanshamoo:BAAANQAECgUICgAAAA==.',
Xk='Xkwon:BAAANQAECgIIAwAAAA==.Xkwøn:BAACNQAFFH8QAAIoAAYK3BVdAAAnAQAoAAYK3BVdAAAnAQA1AAQKfzsAAigACgrMI7sAAPUCACgACgrMI7sAAPUCAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAABNQAECn8ZAAIkAAoKrw0nNQCaAQAkAAoKrw0nNQCaAQAAAA==.',
Xu='Xunie:BAAANQADCggIKwAAAA==.',
Yl='Yloh:BAABNQAECn8kAAQTAAkKMCQrBwCLAwATAAkKMCQrBwCLAwAUAAYK4wX7WAClAAASAAIK3Q1SIABfAAAAAA==.',
Yo='Yoquiere:BAAANQAECgQIBAAAAA==.',
Za='Zaisplash:BAAANQAECgUICgAAAA==.Zana:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.Zaretan:BAAANQADCggIJgAAAA==.',
Zb='Zbrute:BAABNQAECn8qAAIXAAkKRRK0dQAkAgAXAAkKRRK0dQAkAgAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAACNQAFFH8bAAQMAAgK4A5cBQAZAQAMAAUK6Q1cBQAZAQACAAYKEA6FDAAXAQAIAAEKAAC5NAAqAAA1AAQKfysAAwwACgr1IWYLAMMCAAwACgrFIWYLAMMCAAIABgqSGJdsAOsAAAAA.',
Zu='Zulpher:BAAANQADCggIIAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgIIAgAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAACNQAFFH8LAAIWAAUK6RabLQAkAQAWAAUK6RabLQAkAQA1AAQKfysAAhYACgpHIxMRAAoDABYACgpHIxMRAAoDAAAA.',
['ße']='ßeorn:BAAANQABCgIIAgABNQAECgoKhwATAJMlAA==.',
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
