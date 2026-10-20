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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Paladin-Retribution','Shaman-Elemental','Druid-Balance','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Priest-Shadow','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Druid-Restoration','Hunter-Marksmanship','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Mage-Frost','Druid-Guardian','Rogue-Subtlety','Warlock-Affliction','DemonHunter-Devourer','Hunter-Survival','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAABNQAECn8VAAICAAkKRAkiFABmAQACAAkKRAkiFABmAQABNQAECgoKLgADAPcbAA==.',
Ae='Aendia:BAAANQADCgEIAQAAAA==.Aeolos:BAAANQADCgcIDQAAAA==.Aesthetic:BAAANQAECgcIDgABNQAFFAcIFwAEAHUbAA==.',
Ag='Agrios:BAACNQAFFH8HAAIFAAIKIxABDgBtAAAFAAIKIxABDgBtAAA1AAQKfzEAAgUACgqxGpcYAAIDAAUACgqxGpcYAAIDAAAA.',
Ai='Aiellee:BAAANQAECgMIBgAAAA==.',
Ak='Akias:BAAANQAECgYICwAAAA==.',
Al='Alexandra:BAAANQAECgQIBQABNQABCgQIBAABAAAAAA==.Alliekill:BAAANQAECgMIAwABNQAECggIFgAGABQPAA==.Altaurus:BAAANQAECgUIDQAAAA==.Alynnei:BAAANQAECgIIAwABNQABCgQIBAABAAAAAA==.',
Am='Amare:BAAANQAECgQICwAAAA==.Amiria:BAAANQADCggICAAAAA==.',
An='Andros:BAAANQAECgYIEwAAAA==.Anekaatwo:BAAANQAECgEIAQAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Araxe:BAAANQAECgQIBAAAAA==.Arroyo:BAABNQAECn8sAAIHAAgKLCMcEQAuAwAHAAgKLCMcEQAuAwAAAA==.',
As='Askadar:BAACNQAFFH8JAAIIAAMK6SVxAABKAQAIAAMK6SVxAABKAQA1AAQKfyoAAggACgr4JiEAAAsEAAgACgr4JiEAAAsEAAAA.',
Az='Azora:BAABNQAECn8gAAMJAAkKUhmsDAAtAgAJAAcK3xmsDAAtAgAKAAcKZBZvTADuAAAAAA==.Azzura:BAAANQAECgEIAQAAAA==.',
Ba='Baheem:BAAANQAECgMIAwAAAA==.Bams:BAABNQAECn8cAAILAAgKlRQ+OwD7AAALAAgKlRQ+OwD7AAAAAA==.Bangadang:BAAANQADCgEIAQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECn8kAAMMAAoKrRtuCQDbAgAMAAoKrRtuCQDbAgANAAEK3AGoKAAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECn8nAAIDAAoK6hHMcgBJAgADAAoK6hHMcgBJAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQAECgQIBAAAAA==.',
Bi='Bifrons:BAAANQADCgYIGQAAAA==.Bigdill:BAAANQAECgQIBAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIBwAAAA==.Bluè:BAAANQAECgQIBgAAAA==.',
Bo='Bobble:BAAANQADCgUIBgAAAA==.Bonedmg:BAAANQADCgEIAQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCgYIHQAAAA==.Boolil:BAAANQAECgUIEQABNQAECgoKMgAOAJQNAA==.Boolove:BAAANQAECgEIAQABNQAECgoKMgAOAJQNAA==.Booloved:BAABNQAECn8yAAQOAAoKlA1yCgChAQAOAAkKrA5yCgChAQAPAAkKHgSLPABGAQAQAAYK8QGBywDAAAAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Brillianna:BAAANQADCgEIAQAAAA==.Brotato:BAAANQAECgUIBQABNQAECggIHQAGAGceAA==.Broxx:BAAANQADCgcICQAAAA==.',
Bu='Bulwei:BAAANQAECgYIBwAAAA==.',
By='Byssrak:BAAANQAECgMIAgAAAA==.',
Ca='Calmcarnage:BAAANQAECgEIAQAAAA==.Carmêl:BAAANQAECgQIBQABNQAECgoKKgARABceAA==.Cattiegreen:BAABNQAECn8rAAISAAcKzRvrLwBhAQASAAcKzRvrLwBhAQAAAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEgABAAAAAA==.',
Ch='Chopshop:BAAANQADCgUIBgAAAA==.Christopher:BAABNQAECn8lAAIRAAkKghbXgwB3AgARAAkKghbXgwB3AgAAAA==.',
Co='Costica:BAAANQADCgUIBQAAAA==.',
Cr='Creepychaos:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Creepydemise:BAAANQAECgUIBQAAAA==.Creepydrunk:BAAANQADCgQIBAABNQAECgUIBQABAAAAAA==.Croixsmash:BAABNQAECn8XAAMTAAkKSBXmkwDqAQATAAgKFhXmkwDqAQAUAAMKpRK4HwDAAAAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.Curse:BAAANQADCgYIBgAAAA==.',
Cy='Cylvanna:BAAANQAECgQICgAAAA==.',
Da='Darandipity:BAAANQADCgEIAQAAAA==.Darkagedemon:BAAANQADCgQIBAAAAA==.Darkrest:BAAANQADCggIEQAAAA==.Dartboofer:BAAANQADCgYIBwABNQAECgkJFwATAEgVAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECn8pAAIDAAoK0wuZqgDKAQADAAoK0wuZqgDKAQAAAA==.Dawnn:BAAANQAECgUICwAAAA==.',
De='Deanwnchestr:BAAANQAECgUIDgAAAA==.Deatnshadow:BAAANQAECggIDAAAAA==.Dendin:BAAANQADCgcIBwAAAA==.Dethdragon:BAAANQADCgEIAQAAAA==.',
Dm='Dmncgdss:BAAANQAECgQICQAAAA==.',
Do='Dogeatdog:BAAANQADCgYICAAAAA==.Dorus:BAAANQADCgQIBAAAAA==.',
Dr='Draakell:BAAANQAECgcIEQAAAA==.Dragonstew:BAAANQADCgYIBwAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAAANQAECgUICwAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.Dryrain:BAAANQAECgIIAgAAAA==.',
Du='Dudè:BAAANQAECgYIDgAAAA==.',
['Dâ']='Dâggèr:BAACNQAFFH8HAAIVAAMKDRsqDwD3AAAVAAMKDRsqDwD3AAA1AAQKfxQAAhUABwpbG48vACUCABUABwpbG48vACUCAAAA.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQADCgEIAQAAAA==.',
El='Eladawn:BAAANQAECgEIAQABNQAFFAYICwALAAgTAA==.Elarae:BAABNQAECn8fAAISAAgKcxZSLABsAQASAAgKcxZSLABsAQAAAA==.Elawen:BAAANQADCgUIBQAAAA==.Elementblah:BAABNQAECn8UAAIEAAYKng9/mgBjAQAEAAYKng9/mgBjAQAAAA==.Elfkinn:BAACNQAFFH8VAAIFAAUKgBysBQAFAQAFAAUKgBysBQAFAQA1AAQKfyMAAwUACgo4H5IdAN0CAAUACgo4H5IdAN0CABYAAQqHAf2FABUAAAAA.Elivaniel:BAAANQADCgYIBwAAAA==.Ellemere:BAAANQAECgUIBQABNQABCgQIBAABAAAAAA==.Elybermoon:BAAANQADCgEIAQAAAA==.',
Em='Emeryl:BAAANQAECgQIBQABNQAFFAcIFwAEAHUbAA==.Empathyforyo:BAABNQAECn8rAAMSAAkKdRjsSgCNAgASAAgKXRvsSgCNAgAXAAQKAAlQVwDIAAAAAA==.',
En='Enna:BAAANQADCgYIGQAAAA==.',
Eq='Equinox:BAABNQAECn8eAAIFAAoKexBoOwAZAgAFAAoKexBoOwAZAgAAAA==.',
Er='Eredris:BAAANQADCgIIAgAAAA==.Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAABNQAECn8dAAMYAAgKjxfTDAD3AQAYAAgKxhbTDAD3AQAZAAUKshjQTwBaAQAAAA==.',
Es='Eshtar:BAAANQAECgQIBAAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAABNQAECn8UAAIXAAgK2BPhKgD0AQAXAAgK2BPhKgD0AQAAAA==.Exzanthia:BAAANQADCggICwAAAA==.',
Ey='Eyln:BAABNQAECn8WAAIXAAYKygzJPwBVAQAXAAYKygzJPwBVAQAAAA==.',
Fa='Falkor:BAABNQAECn8tAAIaAAoKkRU3BwBWAQAaAAoKkRU3BwBWAQAAAA==.Fayway:BAABNQAECn8qAAMWAAkKEh39BQD0AQAWAAkKEh39BQD0AQAFAAEKAABoyQAZAAAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECn8rAAIbAAkKBB71BAA2AwAbAAkKBB71BAA2AwAAAA==.',
Fi='Figgy:BAABNQAECn8ZAAIKAAkK6wpmjQDFAQAKAAkK6wpmjQDFAQAAAA==.Firepower:BAABNQAECn8yAAMRAAoKdhpcJQCAAQARAAoKdhpcJQCAAQAcAAEKvhl5QwA9AAABNQAECggIHQAGAGceAA==.',
Fo='Forevershy:BAAANQADCggIIAAAAA==.',
Fr='Fries:BAEANQAECggIDwAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Ge='Georgiee:BAAANQAECgEIAQAAAA==.',
Gi='Giggles:BAAANQAECgYIDgAAAA==.',
Go='Goh:BAAANQAECgQIBAAAAA==.Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIDgABNQAECgkJJwALAI4iAA==.Gothrim:BAAANQADCggICQAAAA==.',
Gr='Greenbean:BAAANQADCggJCAABNQAFFAUIFQAFAIAcAA==.Groto:BAAANQAECgcIEgAAAA==.Grrum:BAAANQAECgUIBAAAAA==.Grèy:BAAANQAECgYIDgAAAA==.',
Gu='Gullible:BAAANQAECgYICwAAAA==.',
Ha='Hairy:BAAANQAECgQIBAAAAA==.Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQAECgEIAQAAAA==.Hanjo:BAABNQAECn8VAAIIAAYKDB2MFADeAQAIAAYKDB2MFADeAQAAAA==.Hatookorr:BAABNQAECn8dAAIGAAgKZx5TIgCjAgAGAAgKZx5TIgCjAgAAAA==.',
He='Heledrianis:BAAANQAECgUIBgAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Hi='Highlordlink:BAAANQADCgEIAQAAAA==.',
Ho='Hornet:BAAANQADCggIJgAAAA==.',
Hy='Hydé:BAACNQAFFH8XAAIdAAYKiyBaAABoAQAdAAYKiyBaAABoAQA1AAQKfxwAAh0ACgpYHFILALgCAB0ACgpYHFILALgCAAAA.',
Ik='Ikwon:BAAANQADCgUIBwAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
In='Intuned:BAAANQADCgMIAwABNQAFFAMIBwAVAA0bAA==.',
Is='Ishmael:BAAANQAECgQIBAAAAA==.Ismeldbad:BAAANQAECgMIBQABNQAECgkJHAAeAKQbAA==.',
Ja='Jaland:BAAANQABCgQIBAAAAA==.',
Je='Jellybreak:BAABNQAECn8fAAIFAAcKXA9mDgBpAQAFAAcKXA9mDgBpAQAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAABNQAECn8VAAIQAAYKQhaXfwCaAQAQAAYKQhaXfwCaAQAAAA==.Kateblue:BAABNQAECn8VAAIFAAYKgQyXYABNAQAFAAYKgQyXYABNAQAAAA==.',
Ke='Keeble:BAAANQAECgUIBgAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAABNQAECn8dAAMfAAgKaRlUAQCzAQAfAAgKaRlUAQCzAQAKAAMKWAWQIgF9AAAAAA==.Kelsyyr:BAAANQAECgUIBwABNQAECggIHQAfAGkZAA==.Kenpachi:BAAANQADCgEIAgAAAA==.Kethry:BAAANQAECgEIAQAAAA==.',
Ki='Kidneysweeny:BAABNQAECn8cAAMeAAkKpBvWIQC9AQAeAAYK6xfWIQC9AQAVAAQKXRvvKACrAAAAAA==.Kikyou:BAABNQAECn8mAAMCAAgKMBv+BgDpAQAHAAcKoBx5OQA+AgACAAgKmBL+BgDpAQABNQAFFAYIIAAgALcgAA==.Kim:BAABNQAECn8WAAIhAAgK8A1pCADOAQAhAAgK8A1pCADOAQAAAA==.Kinrah:BAAANQAECgUIBQAAAA==.Kissofdeáth:BAAANQADCggIEAAAAA==.',
Kr='Kreepywife:BAAANQAECgMIAwAAAA==.Krelbelorll:BAABNQAECn8lAAIgAAoKyQ/IKAD+AQAgAAoKyQ/IKAD+AQAAAA==.Krowley:BAABNQAECn8dAAILAAgKsAl/kABfAQALAAgKsAl/kABfAQAAAA==.',
Ku='Kurast:BAABNQAECn8VAAIKAAYKagVZgACCAAAKAAYKagVZgACCAAABNQAECgoKLQAaAJEVAA==.Kurukuru:BAAANQADCgEIAQAAAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFH8SAAIRAAYKCBuZBABnAQARAAYKCBuZBABnAQA1AAQKfx8AAxEACgqyIjlKAO0CABEACgqyIjlKAO0CABwAAQp9HeZJADEAAAAA.',
Kx='Kxwono:BAABNQAECn8UAAMFAAkKxQyeXgBWAQAFAAcKrg2eXgBWAQAWAAIKJwrcMQBqAAAAAA==.',
Ky='Kyoyama:BAAANQAECgcIBwABNQAECgoKMgAKAJMjAA==.',
La='Ladýshinobu:BAABNQAECn8cAAIiAAcKpwk+PQD0AAAiAAcKpwk+PQD0AAAAAA==.',
Le='Leahu:BAAANQAECggICwAAAA==.Lediaa:BAAANQADCgQIBQAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgMIAwAAAA==.',
Li='Linkjrb:BAAANQADCgEIAQAAAA==.Lisavia:BAAANQAECggIEQAAAA==.',
Lo='Locholovis:BAAANQAECgcIDgAAAA==.Locklicous:BAABNQAECn8vAAIKAAkKhRtyIgD6AgAKAAkKhRtyIgD6AgABNQAECgkJFwATAEgVAA==.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFH8TAAIGAAUKJRawEABMAQAGAAUKJRawEABMAQA1AAQKfy8AAwYACgpJHWsiAKICAAYACgqLHGsiAKICAAcABAr/HO18ACgBAAAA.',
Lu='Luminouss:BAACNQAFFH8LAAILAAYKCBNkCwCXAQALAAYKCBNkCwCXAQA1AAQKfzsAAwsACgojHRMlANECAAsACgojHRMlANECAAQAAQrTFWUnAUMAAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lycanthor:BAAANQADCgEIAQAAAA==.Lyrium:BAAANQADCgYIBgABNQAECggIJQAGABEbAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQAECgEIAQAAAA==.Magnuus:BAAANQAECgUICgAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQAECgQICAAAAA==.Mantis:BAABNQAECn8iAAILAAkKwyD0CgAUAgALAAkKwyD0CgAUAgABNQAECgoKLQAaAJEVAA==.',
Me='Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAABNQAECn8VAAIPAAYKBw65OgBSAQAPAAYKBw65OgBSAQAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mercas:BAAANQAECgUIBgABNQAECggIJAARAAgZAA==.Mezi:BAABNQAECn8iAAIQAAcKBByADgAJAgAQAAcKBByADgAJAgAAAA==.',
Mg='Mg:BAAANQADCgUIDwAAAA==.',
Mh='Mhonster:BAAANQAECggIDQABNQABCgQIBAABAAAAAA==.',
Mi='Miasma:BAAANQAECgEIAQAAAA==.Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAABNQAECn8fAAMZAAkKMRAsDwBzAQAZAAkKLwksDwBzAQAgAAUKwhqkOgBxAQAAAA==.',
Mo='Mollymurder:BAAANQADCgEIAQAAAA==.Morley:BAAANQAECgQIBAAAAA==.',
Mu='Mulron:BAABNQAECn8cAAIjAAgKuBb5GAAvAgAjAAgKuBb5GAAvAgAAAA==.',
My='Myrica:BAAANQAECggICAAAAA==.',
Ni='Nishand:BAAANQADCgEIAQAAAA==.',
Nu='Nuwa:BAAANQADCgEIAQAAAA==.',
Oa='Oakenshíeld:BAACNQAFFH8LAAIFAAQKRxQpEwA4AQAFAAQKRxQpEwA4AQA1AAQKfzEAAgUACgpLGwoZAP8CAAUACgpLGwoZAP8CAAAA.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Og='Ogrimfist:BAAANQADCgEIAgAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAAANQAECggIEQAAAA==.',
Oo='Oozwoz:BAAANQAECgMIAwAAAA==.',
Ou='Outfoxed:BAAANQAECggIEwABNQAFFAYIGgAQAKkaAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAABNQAECn8VAAIFAAYKXQi8aQAlAQAFAAYKXQi8aQAlAQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCgYIFQAAAA==.',
Pi='Pinbalwizard:BAAANQAECgUIBQABNQAECggIHQAGAFcYAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgATAGkSAA==.Plagueblade:BAABNQAECn8VAAIGAAYKlRHjbABBAQAGAAYKlRHjbABBAQAAAA==.',
Po='Poppy:BAAANQADCgEIAQAAAA==.',
Pr='Progression:BAAANQAECggICwAAAA==.',
Qu='Quivera:BAAANQAECgEIAQAAAA==.',
Ra='Ragingrain:BAAANQADCgUIBQAAAA==.Rainsshammy:BAABNQAECn8nAAILAAgKPhsuNwCCAgALAAgKPhsuNwCCAgAAAA==.Rascalfrak:BAAANQADCgEIAQAAAA==.Rawak:BAAANQABCggIDgAAAA==.Rawktuah:BAAANQADCgMIAwAAAA==.',
Re='Realhelz:BAAANQAECgQIBAAAAA==.Redsamilf:BAAANQAECgYIDgAAAA==.Rekka:BAAANQADCgYICwAAAA==.Requizik:BAAANQAECgUIDAAAAA==.Resaana:BAAANQAECgIIAwABNQAECgQICAABAAAAAA==.Restofarian:BAABNQAECn8nAAMLAAkKjiK6DABaAwALAAkKjiK6DABaAwAEAAQKURCy3QDaAAAAAA==.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAABNQAECn8UAAIkAAYKrRDqHQCCAQAkAAYKrRDqHQCCAQAAAA==.',
Ri='Rianon:BAAANQADCgEIAQABNQAECggIEAABAAAAAA==.Rizzy:BAABNQAECn84AAMHAAoKWA5HTADjAQAHAAoKWA5HTADjAQACAAcKmgfbWgA+AQAAAA==.',
Ro='Rotinshot:BAACNQAFFH8JAAISAAMKkhS5BwDsAAASAAMKkhS5BwDsAAA1AAQKfyEAAxIACgpnHV0rAOwCABIACgpnHV0rAOwCABcAAgopBXB9AE4AAAAA.',
Ru='Rutikee:BAABNQAECn8rAAMWAAkKMg4VLwCiAQAWAAkKMg4VLwCiAQAFAAIKiQP9pABQAAAAAA==.',
Ry='Rykér:BAAANQAECgUIBQABNQAFFAYIFwAdAIsgAA==.Ryomensukuna:BAABNQAECn8UAAIHAAkK0yCrKACWAgAHAAkK0yCrKACWAgAAAA==.',
Sa='Sahrotaar:BAAANQAECggIAgAAAA==.Sandrill:BAAANQAECgQJBQABNQAECggIHQAGAGceAA==.Savior:BAAANQAECgIIAgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgQIBQAAAA==.Seizon:BAAANQAECgQIDQAAAA==.Senseicanz:BAAANQADCgYICAAAAA==.Sephie:BAAANQAECgEIAQAAAA==.Serom:BAAANQAECgUIDwAAAA==.Sethic:BAAANQADCgYJBQAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkbayte:BAAANQADCgEIAQAAAA==.Sharkie:BAAANQADCggICwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sharpshôôter:BAAANQADCgUIBQAAAA==.Sherunn:BAAANQAECgQIDAAAAA==.Shimakaze:BAABNQAECn8hAAISAAcKgQkWXwDtAAASAAcKgQkWXwDtAAAAAA==.Shmitty:BAAANQAECgYICwABNQAFFAMIBwAVAA0bAA==.Shooters:BAABNQAECn8UAAMhAAcK/Ro5CADXAQASAAcKuRfukwDhAQAhAAYKHBg5CADXAQAAAA==.Shyminx:BAAANQADCgQIBAAAAA==.Shymistress:BAABNQAECn8mAAISAAkKUxtrRQCcAgASAAkKUxtrRQCcAgAAAA==.Shåmmy:BAABNQAECn8rAAILAAkKlhS0SgA4AgALAAkKlhS0SgA4AgAAAA==.',
Si='Sindralea:BAABNQAECn8VAAIZAAcKcBVxRQCbAQAZAAcKcBVxRQCbAQAAAA==.',
Sj='Sjöfn:BAAANQADCgEIAQAAAA==.',
Sk='Skiá:BAABNQAECn8sAAIbAAgKuB3xCADAAgAbAAgKuB3xCADAAgAAAA==.',
Sl='Slayerkitty:BAAANQADCgEIAQAAAA==.Slicedbread:BAAANQAECgEIAQAAAA==.',
So='Songatsu:BAAANQADCggIDAAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Sparkleglory:BAAANQAECgEIAQAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAABNQAECn8mAAIDAAkK5hewEAD1AQADAAkK5hewEAD1AQAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAMIBwAVAA0bAA==.Stormfox:BAABNQAECn8WAAIEAAgKOgbApwBFAQAEAAgKOgbApwBFAQAAAA==.Strawhat:BAAANQAECgQICwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgQIDAAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQAECgQIBQAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAAANQAECgQIEAAAAA==.Tannuk:BAABNQAECn8vAAIjAAgK0Bx6BADEAQAjAAgK0Bx6BADEAQAAAA==.Tarz:BAAANQADCgEIAQAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgUIBQABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAABNQAECn8mAAIEAAgKrx3JMwCqAgAEAAgKrx3JMwCqAgAAAA==.',
Th='Thekingbak:BAAANQAECgEIAQABNQAECggIEAABAAAAAA==.Thromose:BAAANQADCgEIAQAAAA==.Throwinhands:BAAANQADCgEIAQAAAA==.Thundaris:BAAANQADCgEIAgAAAA==.',
Ti='Tiari:BAABNQAECn8qAAIiAAgKGheTVQAZAgAiAAgKGheTVQAZAgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tn='Tntclepriest:BAAANQAECgEIAQABNQADCgcICwABAAAAAA==.',
To='Totems:BAABNQAECn8bAAIkAAkKtRG4BQChAQAkAAkKtRG4BQChAQABNQAECgIIAgABAAAAAA==.',
Tr='Tridius:BAABNQAECn9JAAMQAAoK/CL8BwCEAwAQAAoK/CL8BwCEAwAPAAEKAADqdAA8AAAAAA==.Trixx:BAAANQAECgUICwAAAA==.',
Tu='Tuffcracker:BAAANQAECgUICgAAAA==.Turdanator:BAAANQAECgUICAAAAA==.',
Tw='Twinturboj:BAAANQAECgYIDgAAAA==.Twittle:BAAANQAECgUIDgAAAA==.',
Ty='Tylovastus:BAAANQAECggIDQAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.Tyton:BAAANQADCgMIAwAAAA==.',
Ub='Ube:BAABNQAECn8bAAITAAgKjx/QRwCyAgATAAgKjx/QRwCyAgAAAA==.',
Ur='Uriah:BAAANQAECgUIEgAAAA==.Ursúla:BAAANQAECggIEAABNQAFFAUIFQAFAIAcAA==.Urïah:BAAANQADCgYICQABNQAECgUIEgABAAAAAA==.',
Ut='Utherr:BAAANQAECggICAAAAA==.',
Va='Valaravaus:BAAANQADCggICwAAAA==.Valinthria:BAAANQADCgEIAQAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.Veryletheone:BAAANQAECgQIAgAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgUIBQAAAA==.',
['Vé']='Végeta:BAAANQAECgQIDAABNQAECgoKLQAaAJEVAA==.',
Wa='Wardwhelp:BAAANQADCggJEgAAAA==.',
Wh='Whitecoma:BAAANQADCgEIAgAAAA==.',
Wi='Wildprayer:BAAANQADCgEIAQABNQAECgYIFQAWAC8bAA==.Wildtotem:BAAANQADCgEIAQABNQAECgYIFQAWAC8bAA==.',
Wo='Wooloo:BAACNQAFFH8OAAQKAAcKrhYTGQAsAQAKAAQKYxcTGQAsAQAfAAIK0AcDBABbAAAJAAEKbiOZFgBXAAA1AAQKfyMAAwkACgotIJoPAAMCAAoABwolJm1KAHQCAAkABwp3G5oPAAMCAAAA.',
Wy='Wynona:BAACNQAFFH8FAAIRAAIKTwdoTgCJAAARAAIKTwdoTgCJAAA1AAQKfykAAhEACQr9Fn93AI4CABEACQr9Fn93AI4CAAAA.',
Xa='Xanagore:BAABNQAECn8eAAMTAAcKSRI1qgCzAQATAAcKSRI1qgCzAQAIAAMKWAuXNQCIAAAAAA==.',
Xk='Xkwon:BAAANQADCggIDgAAAA==.Xkwøn:BAACNQAFFH8OAAIlAAQKFBtPAAD+AAAlAAQKFBtPAAD+AAA1AAQKfzEAAiUACgoYIuEBAFUDACUACgoYIuEBAFUDAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAAANQAECggIEAAAAA==.',
Xu='Xunie:BAAANQADCggILAAAAA==.',
Yl='Yloh:BAABNQAECn8gAAQQAAkKMCQrBwCLAwAQAAkKMCQrBwCLAwAPAAYK4wX7WAClAAAOAAIK3Q1SIABfAAAAAA==.',
Yo='Yoquiere:BAAANQAECgQIBAAAAA==.',
Za='Zaedra:BAAANQADCggIAQAAAA==.Zaisplash:BAAANQAECgUICgAAAA==.Zana:BAAANQADCgUIBgABNQAECgUICgABAAAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Zaretan:BAAANQADCggIHQAAAA==.',
Zb='Zbrute:BAABNQAECn8dAAISAAgKvRC0dQAkAgASAAgKvRC0dQAkAgAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAACNQAFFH8XAAQHAAYKuBNIAQA+AQAHAAUK6Q1IAQA+AQACAAQK+hOFDAAXAQAGAAEKAAC5NAAqAAA1AAQKfyEAAwcACgrXG54GAMQBAAcACgrXG54GAMQBAAIABAoyGTFqAPYAAAAA.',
Zu='Zulpher:BAAANQADCggIIAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgIIAwAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAACNQAFFH8JAAIRAAQKJRSbLQAkAQARAAQKJRSbLQAkAQA1AAQKfyAAAhEACQqxIA8ZAHEDABEACQqxIA8ZAHEDAAAA.',
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
