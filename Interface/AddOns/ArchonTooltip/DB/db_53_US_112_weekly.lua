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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Affliction','Priest-Shadow','Rogue-Subtlety','Paladin-Protection','Priest-Discipline','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','Warrior-Protection','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','DemonHunter-Devourer','Mage-Frost','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Druid-Guardian','Hunter-Survival','Evoker-Preservation',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abbii:BAAANQADCgIIAgAAAA==.',
Ai='Aidalen:BAAANQAECgEIAQAAAA==.',
Ak='Akaidia:BAAANQAECggIBgABNQAECggIEAABAAAAAA==.',
Al='Alaplateada:BAAANQAECgQIBAAAAA==.Alckmin:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAABNQAECn8eAAICAAoKPRaNEQCxAQACAAoKPRaNEQCxAQAAAA==.Allysaun:BAAANQAECgMIBQAAAA==.Altacia:BAAANQADCgQIBAAAAA==.',
Am='Amaurra:BAAANQABCgQIBAAAAA==.Amorina:BAABNQAECn8mAAIDAAoKOxQfoACNAQADAAoKOxQfoACNAQAAAA==.',
An='Anda:BAAANQAECgEIAQAAAA==.Andill:BAAANQAECgQIDAAAAA==.Andracca:BAAANQAECgUIBQABNQAECgcICwABAAAAAA==.Andromeda:BAAANQAECgUICQAAAA==.Aner:BAAANQADCgIIAwAAAA==.Angellete:BAACNQAFFH8OAAMEAAYK9BdYEABCAQAEAAUK9BdYEABCAQAFAAEKAADoBQAAAAA1AAQKfyoAAgQACgpEH75OAJ0CAAQACgpEH75OAJ0CAAAA.Angrygnome:BAABNQAECn9OAAMGAAoKOSFcAwAQAwAGAAoKLRtcAwAQAwAHAAoKHCCfEgDeAgAAAA==.Angélique:BAABNQAECn8ZAAIIAAoKFhefPwA8AgAIAAoKFhefPwA8AgABNQAFFAYIDgAEAPQXAA==.Anieros:BAAANQAECgEIAgABNQAFFAUIDQACAN0OAA==.',
Ar='Arai:BAAANQADCgYIBQAAAA==.Arax:BAAANQAECggIDwAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAABNQAECn8mAAIDAAkKDA6qowCGAQADAAkKDA6qowCGAQAAAA==.Armâgeddon:BAABNQAECn8qAAIEAAkKcyB+LAAKAwAEAAkKcyB+LAAKAwAAAA==.Arrokoth:BAAANQAECgUIBQAAAA==.Arthritas:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.Artistic:BAAANQAECgEIAQAAAA==.',
As='Astyl:BAAANQAECgYIBgAAAA==.',
At='Athurnz:BAAANQABCgIIAgAAAA==.Atropós:BAABNQAECn8fAAIJAAoKOAuZeAC8AQAJAAoKOAuZeAC8AQAAAA==.Attachedplag:BAABNQAECn8mAAMEAAkKhBH3XwDfAQAEAAkKhBH3XwDfAQAFAAEKPQb8NgArAAAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQAECgYIBgAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Baconhuntard:BAAANQAECgMIAwAAAA==.Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQAECgUIBgAAAA==.Banzen:BAAANQADCggIGwAAAA==.Battle:BAEANQADCgIIAgABNQAECgoKOAAKACAfAA==.',
Be='Beardedyeti:BAAANQABCgQIBAAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAABNQAECn84AAILAAoKKxluLQA1AgALAAoKKxluLQA1AgAAAA==.Bernese:BAAANQAECgcICQAAAA==.Berunma:BAABNQAECn8fAAIMAAkKAg+3rgCnAQAMAAkKAg+3rgCnAQAAAA==.',
Bh='Bhain:BAACNQAFFH8JAAQHAAUK4Ai/HQDDAAAHAAQK4Ai/HQDDAAANAAEKagedGQBGAAAGAAEKFAiRFQA/AAA1AAQKfycABAcACgp6HHEjAIQCAAcACgpGG3EjAIQCAA0ABwqAGZsLAIsBAAYABAoeGaEJACwBAAAA.',
Bi='Bileshots:BAAANQAECggIDQAAAA==.Biowolf:BAACNQAFFH8KAAIJAAQK2QXTMACvAAAJAAQK2QXTMACvAAA1AAQKfxoAAgkACQqwEeWyAB0CAAkACQqwEeWyAB0CAAAA.Birdhunter:BAAANQAECgYIBgAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgQIBAABAAAAAA==.Bishopxix:BAAANQAECgQIBAAAAA==.Bits:BAAANQAECgQIEQAAAA==.',
Bj='Bjoren:BAABNQAECn8vAAMIAAoKqSCIFwAaAwAIAAoKqSCIFwAaAwAOAAEKAAADlwAKAAAAAA==.',
Bl='Blackki:BAAANQADCgQIBQAAAA==.Bloodbaron:BAAANQAECggIDAABNQAECggIIwAHAF0XAA==.',
Bo='Bootiebang:BAABNQAECn8mAAIPAAYK4AZ8MAA7AQAPAAYK4AZ8MAA7AQAAAA==.Bootieknight:BAAANQADCgcIBwAAAA==.Bootycaall:BAAANQADCgcIDgAAAA==.Boxxie:BAAANQADCgcIFQAAAA==.',
Br='Branches:BAAANQADCgMIAwAAAA==.Brockshot:BAAANQAECgQIBQAAAA==.',
Bu='Bucknekkid:BAAANQAECgUICQAAAA==.Buckwhild:BAABNQAECn8vAAMIAAoKHh2xMwCZAgAIAAoKHh2xMwCZAgAOAAMK5ghXUABrAAAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAABNQAECn9RAAMQAAoK3iTaAQBjAwAQAAoK3iTaAQBjAwADAAUKnhRhHgG8AAAAAA==.Canadaisheal:BAABNQAECn8XAAMRAAgKuw/UBwBJAQARAAYKHBLUBwBJAQAOAAIKvAe6aAAsAAAAAA==.Catslol:BAAANQADCgIIAwAAAA==.',
Ce='Cerñuñños:BAAANQAECgIIAgAAAA==.Cesàrè:BAABNQAECn8YAAISAAYKhQkkKgCzAAASAAYKhQkkKgCzAAAAAA==.',
Ch='Chahra:BAAANQAECgUICQAAAA==.Chamuki:BAABNQAECn8eAAMTAAoKQBfVOQBcAQATAAkKQRjVOQBcAQAUAAEKOxBgMAA8AAABNQAFFAcIHAAVAPAZAA==.Chaosbolt:BAAANQAECgYICQAAAA==.Cheesecake:BAAANQADCgMIAwABNQAFFAYIDgAEAPQXAA==.Chuubak:BAAANQAECggIEAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAABNQAECn8ZAAMFAAgKkg9DGAAAAQAFAAgKkg9DGAAAAQAEAAUKgwaK9wCEAAAAAA==.',
Co='Cocomami:BAAANQADCgUIBQAAAA==.Colonidus:BAAANQAECgQIBAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAABNQAECn8tAAIWAAoKsRQLDwDHAQAWAAoKsRQLDwDHAQAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAABNQAECn8pAAMEAAoKqBzyPwBDAgAEAAoKqBzyPwBDAgAFAAQKWxiFHgDMAAAAAA==.',
Da='Dagby:BAAANQADCgcIGwAAAA==.Dandi:BAAANQAECgIIAgAAAA==.Daneaus:BAAANQADCgMIAwABNQAECgoKKgAXAL4kAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darkscorp:BAAANQADCgIIAgAAAA==.Darkwolf:BAAANQAECgQICAAAAA==.Darnuus:BAABNQAECn88AAMYAAoKbh3jKADAAgAYAAoKbh3jKADAAgAZAAUKCQ3UtACeAAAAAA==.Datnv:BAAANQADCggICAAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAABNQAECn81AAMaAAkKPw8aMgBgAQAaAAkKPw8aMgBgAQAVAAcKwAaWcQADAQAAAA==.Deathkweasel:BAAANQAECgYIBAABNQAECgoKKgAMAA4kAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAABNQAECn8pAAIHAAoKThiCNAA+AgAHAAoKThiCNAA+AgAAAA==.Delai:BAAANQADCgMIAwAAAA==.Dellin:BAABNQAECn8pAAIVAAoKsRa6IQDwAQAVAAoKsRa6IQDwAQAAAA==.Demeco:BAEBNQAFFH8KAAIXAAYKdROGCADlAQAXAAYKdROGCADlAQABNQAFFAkJGwAXAFMZAA==.Demondots:BAAANQAECgUIDAAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Dh='Dhalseem:BAAANQAECgUIBQAAAA==.',
Di='Diminuendo:BAAANQAECgIIAgAAAA==.',
Do='Dogz:BAABNQAECn8VAAMbAAkKWRo7DwBjAgAbAAkKWRo7DwBjAgAUAAIKuwukKQBNAAABNQAFFAcIHQAMAHIhAA==.Doozydruid:BAABNQAECn8UAAIVAAcKeg/rVQCAAQAVAAcKeg/rVQCAAQAAAA==.Dorozh:BAABNQAECn8eAAIGAAoKEBNqBQCkAQAGAAoKEBNqBQCkAQAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonstorm:BAAANQAECggICQAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAABNQAECn8kAAIIAAcKsRcmaACmAQAIAAcKsRcmaACmAQAAAA==.Dreadar:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Dreadmage:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Dreadpally:BAAANQADCgYJCgABNQADCgYICgABAAAAAA==.Dreco:BAAANQAECgcIEQAAAA==.Driver:BAEANQAECggICAAAAA==.Drtydhn:BAAANQABCgMIAwAAAA==.Druuzak:BAABNQAECn88AAIcAAoKjA77DADKAQAcAAoKjA77DADKAQAAAA==.Dryconias:BAACNQAFFH8GAAIDAAIKdQ73JQCEAAADAAIKdQ73JQCEAAA1AAQKf1UAAgMACgoUIIwqALcCAAMACgoUIIwqALcCAAAA.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duncanmcleod:BAABNQAECn8lAAIEAAoKGxlpSgAgAgAEAAoKGxlpSgAgAgABNQAECgoKNgAIAEEeAA==.Dunkelzhan:BAABNQAECn8zAAIJAAoKhRNhbQDXAQAJAAoKhRNhbQDXAQAAAA==.',
Dv='Dvldogma:BAAANQAECgUIDQAAAA==.',
Dy='Dyana:BAABNQAECn8eAAIMAAoKzhATiQCmAQAMAAoKzhATiQCmAQAAAA==.',
Dz='Dz:BAABNQAECn9DAAMXAAoKpyXFBACqAwAXAAoKpyXFBACqAwADAAYKDA7I9AAzAQAAAA==.',
['Dø']='Dømimømmÿ:BAAANQAECgMIAwAAAA==.',
Ec='Ecobessie:BAAANQAECgQIBAAAAA==.Ecowolf:BAAANQADCgcIDAABNQAECgQIBAABAAAAAA==.',
Ed='Edlund:BAABNQAECn8bAAIdAAgKTwmREQAgAQAdAAgKTwmREQAgAQAAAA==.',
El='Electricfun:BAAANQAECgMIAgAAAA==.Eligarf:BAAANQAECgYIBQAAAA==.Ellenaim:BAAANQAECgUICAAAAA==.Elvy:BAABNQAECn9BAAIVAAoKRRl1HgANAgAVAAoKRRl1HgANAgAAAA==.',
En='Enngin:BAAANQAECgMIAwAAAA==.Enroks:BAABNQAECn9DAAQZAAoKBRcxKwAxAgAZAAoKBRcxKwAxAgAYAAYKZhkdggCGAQAeAAEKAAARNwAzAAAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAABNQAECn80AAMaAAkKHRS5KwCSAQAaAAkKHRS5KwCSAQAVAAYK/gfXZwCJAAAAAA==.Evangelina:BAAANQADCgEIAQAAAA==.',
Ex='Exsalsior:BAACNQAFFH8NAAMCAAUK3Q43BwDZAAAPAAQK0QbTFQDbAAACAAMKTBE3BwDZAAA1AAQKfxgAAgIACQr4E6g1AAICAAIACQr4E6g1AAICAAAA.',
Ey='Eyedoc:BAAANQABCgIIBAAAAA==.',
Fa='Fabulousness:BAABNQAECn8WAAIIAAkKASACGwAAAwAIAAkKASACGwAAAwAAAA==.Fathur:BAAANQADCggICwAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQAECgUIDwAAAA==.Furussy:BAAANQADCgcIBwAAAA==.',
Ga='Galadhras:BAAANQADCgYIDAAAAA==.Galdryn:BAAANQABCgQIBQAAAA==.Gamboslice:BAABNQAECn8wAAILAAoKZxZqLQA1AgALAAoKZxZqLQA1AgAAAA==.Garkevon:BAABNQAECn8wAAMfAAoKigpOKQCZAQAfAAoKigpOKQCZAQAgAAMKPgSMnAA5AAAAAA==.',
Ge='Gevul:BAABNQAECn9mAAQHAAoKTR22QwCHAgAHAAkK8R22QwCHAgAGAAMK+hFKOQDbAAANAAEKAADLMQAxAAAAAA==.',
Gh='Ghuun:BAABNQAECn8jAAIHAAgKXRfvawCUAQAHAAgKXRfvawCUAQAAAA==.',
Gi='Gitmerge:BAAANQADCgYIBgAAAA==.',
Gl='Glep:BAAANQADCggICwAAAA==.Glimmervoid:BAAANQAECgQICQAAAA==.',
Go='Golland:BAAANQABCgIIAgABNQAECgoKPAAZAKAaAA==.Goob:BAAANQADCgYIBgAAAA==.Gorecurse:BAAANQAECgEIAQAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAABNQAECn8ZAAIDAAgKFxdkiAAWAgADAAgKFxdkiAAWAgAAAA==.Grimero:BAAANQAECggIAgAAAA==.Groinsapper:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Grozny:BAAANQAECgEIAQABNQAECgoKIgAVANQPAA==.',
Gs='Gsstuff:BAAANQADCgIIAgAAAA==.',
Gu='Gumboslice:BAACNQAFFH8NAAIaAAYK6RRKBwB9AQAaAAYK6RRKBwB9AQA1AAQKfz8AAxoACgrmH1IRAMkCABoACgrmH1IRAMkCABUAAQoAAIemAAAAAAAA.Gumiho:BAABNQAECn8aAAIYAAgKNRx/LABzAgAYAAgKNRx/LABzAgAAAA==.Gusgus:BAABNQAECn8qAAIcAAgKBA1QFQBCAQAcAAgKBA1QFQBCAQAAAA==.Guud:BAAANQAECgUIBAAAAA==.',
Gy='Gyroflux:BAAANQAECgUIBgAAAA==.',
Ha='Haackh:BAACNQAFFH8JAAIMAAQKkxGSEQBHAQAMAAQKkxGSEQBHAQA1AAQKfyUAAgwACgrAIZsTAFADAAwACgrAIZsTAFADAAAA.Habanero:BAABNQAECn8mAAIZAAoKkB+4HACLAgAZAAoKkB+4HACLAgAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQAECggIAgABNQAECgoKQgAhAOINAA==.Hammerfist:BAABNQAECn8ZAAIQAAgKOxE9HwB0AQAQAAgKOxE9HwB0AQAAAA==.Hark:BAAANQADCggIGwAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECgoKKgAWAHAVAA==.',
He='Healvisprsly:BAAANQAECgQIBQAAAA==.Helena:BAABNQAECn9GAAMQAAoKHSMYBQAOAwAQAAoKHSMYBQAOAwADAAgKNhpecwBIAgAAAA==.Heliarc:BAAANQADCggIHwAAAA==.',
Hi='Hidän:BAABNQAECn8bAAMHAAcKuwukvQBRAQAHAAcKuwukvQBRAQAGAAEKwgWSfgAuAAAAAA==.Himself:BAAANQADCgUIBQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.Hoomalu:BAAANQADCgIIAgAAAA==.',
Hu='Huund:BAAANQADCgUIBQAAAA==.Huutou:BAAANQAECgQIBQAAAA==.',
Id='Idori:BAAANQAECgYIBQAAAA==.',
Il='Illatix:BAAANQAECgQICAAAAA==.Illustriä:BAABNQAECn8fAAIMAAYKhg6F3gBEAQAMAAYKhg6F3gBEAQAAAA==.',
In='Insidious:BAABNQAECn8cAAIgAAcKlxxiMABQAgAgAAcKlxxiMABQAgAAAA==.',
Ir='Irs:BAABNQAECn8cAAIDAAkK3RhFSQBPAgADAAkK3RhFSQBPAgAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECgkJKQAcADIfAA==.Itchymage:BAABNQAECn8pAAMcAAkKMh+jFQBTAQAJAAkKxh2ghwBvAgAcAAQKEh2jFQBTAQAAAA==.',
Iv='Ivyrayne:BAAANQAECgEIAQAAAA==.',
Ja='Jaganash:BAAANQAECgUIBAABNQAECgoKIAAPAMQXAA==.Jakeofny:BAAANQAECgYICAAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIDQAAAA==.',
Ji='Jighlipuff:BAABNQAECn8mAAIDAAkKnQY04AAdAQADAAkKnQY04AAdAQAAAA==.Jigs:BAABNQAECn88AAIMAAoK4g7vZAD7AQAMAAoK4g7vZAD7AQAAAA==.Jinxy:BAAANQADCggINwABNQAECgUIGgAIAAkOAA==.',
Ju='Judgements:BAAANQAECgUICwAAAA==.Jug:BAAANQAECgIIAgAAAA==.Jujutanketh:BAAANQAECgUICgAAAA==.Junebugg:BAABNQAECn8pAAIJAAgKhwVoxwAZAQAJAAgKhwVoxwAZAQAAAA==.',
Ka='Kabøchi:BAABNQAECn8oAAIKAAgKQBICJAB7AQAKAAgKQBICJAB7AQAAAA==.Kafia:BAAANQAECgcIDwAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQAECgYIDgAAAA==.Kanaloa:BAAANQAECgUIDAAAAA==.Kaorin:BAAANQAECgEIAQABNQAECgoKNAAYAKMjAA==.Karindis:BAABNQAECn8vAAIUAAoKOyHlAwAYAwAUAAoKOyHlAwAYAwAAAA==.Kathulhu:BAAANQAECgQIBQAAAA==.Kayler:BAAANQAECggIEAAAAA==.',
Ke='Kegerator:BAAANQADCgQIBQAAAA==.Keldica:BAABNQAECn8aAAIHAAoKERguOAAxAgAHAAoKERguOAAxAgABNQAECgoKJQAZACseAA==.Kenshan:BAAANQAECgEIAQAAAA==.Keylogger:BAAANQAECgEIAgAAAA==.',
Kh='Khalinor:BAABNQAECn8eAAIXAAkKKiBEHgDKAgAXAAkKKiBEHgDKAgAAAA==.Khotuhn:BAAANQAECgQIBAAAAA==.',
Ki='Kickazdin:BAABNQAECn8vAAMXAAoKyx7hKADFAgAXAAkKOx/hKADFAgADAAEKAABNngE4AAAAAA==.Killadragon:BAAANQAECgUIBQAAAA==.Kiryie:BAAANQAECgUIBgAAAA==.Kitinna:BAABNQAECn8WAAMJAAcKZANm+QC+AAAJAAcK8QJm+QC+AAAcAAEKXAQLUQAlAAAAAA==.',
Kl='Klaw:BAAANQADCgYIEAAAAA==.',
Ko='Korraa:BAABNQAECn8nAAMYAAoKBBxfTwAnAgAYAAoKBBxfTwAnAgAZAAYKKBGqsQAvAQAAAA==.',
Kp='Kprist:BAAANQAECgUIDAAAAA==.',
Kr='Kraigen:BAABNQAECn8XAAITAAgKeA1KOABlAQATAAgKeA1KOABlAQAAAA==.',
Ku='Kunzhut:BAABNQAECn8fAAMfAAgKIhWnVQC7AQAfAAgKIhWnVQC7AQALAAQKsQgAjQCJAAAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgcIEwAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Laeli:BAABNQAECn8aAAIIAAUKCQ7wpADvAAAIAAUKCQ7wpADvAAAAAA==.Lailyre:BAAANQAECggIBgABNQAECggIEAABAAAAAA==.Laydin:BAABNQAECn8oAAIMAAgKIwVdAAEEAQAMAAgKIwVdAAEEAQABNQAECgkJNQAaAD8PAA==.',
Lb='Lb:BAABNQAECn8kAAMMAAoKNhpyXAAQAgAMAAoKNhpyXAAQAgAhAAUKcAsxSwAJAQAAAA==.',
Le='Legzanot:BAACNQAFFH8LAAIZAAQKqQYFFgC+AAAZAAQKqQYFFgC+AAA1AAQKf2EAAhkACgoQGb4kAFYCABkACgoQGb4kAFYCAAAA.Lestrade:BAABNQAECn88AAIgAAoKBBMvJADZAQAgAAoKBBMvJADZAQABNQAECgoKPAAYAG4dAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAABNQAECn8yAAMDAAgKlhV5sgBrAQADAAgKlhV5sgBrAQAXAAYKwA2mkgADAQAAAA==.Lightsfallen:BAABNQAECn82AAMIAAoKQR6vGgACAwAIAAoKQR6vGgACAwARAAEKuwa4LQApAAAAAA==.Lilnasdormu:BAAANQADCgUIBQABNQAECggIHAALAB8RAA==.Lithia:BAAANQAECgUICAAAAA==.Littlemo:BAAANQAECgUIDwAAAA==.',
Lo='Lohnar:BAAANQAECgUIDwAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgcIEgAAAA==.Lucielbaal:BAABNQAECn8nAAIHAAoKgxfAPAAgAgAHAAoKgxfAPAAgAgAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQAECgEIAQAAAA==.Lunareth:BAABNQAECn8iAAIVAAoK1A+pKgCrAQAVAAoK1A+pKgCrAQAAAA==.',
Ly='Lyrska:BAAANQAECgUIEQAAAA==.Lytearrow:BAABNQAECn8lAAIMAAoKZQsoagDvAQAMAAoKZQsoagDvAQAAAA==.',
['Lì']='Lìvíd:BAABNQAECn8bAAMFAAgKLguMFgAWAQAFAAgKnQqMFgAWAQAEAAQKEQfqIAGYAAAAAA==.',
Ma='Mahrylee:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgUICQAAAA==.Makbeard:BAAANQADCgYIBgABNQAECgoKGQAiACwPAA==.Makmobius:BAABNQAECn8ZAAIiAAoKLA8kCACvAQAiAAoKLA8kCACvAQAAAA==.Manbearpally:BAAANQAECgEIAQAAAA==.Mannypack:BAAANQAECgcIBwAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgcIFwABAAAAAA==.Mathau:BAAANQADCgcIFwAAAA==.Maztrix:BAAANQAECgIIAwAAAA==.',
Mc='Mcleary:BAABNQAECn8hAAIDAAYKhg8B3QAiAQADAAYKhg8B3QAiAQAAAA==.',
Me='Meistro:BAAANQABCgQIBAAAAA==.Meldrus:BAABNQAECn8XAAIHAAgK/gnsmQCmAQAHAAgK/gnsmQCmAQAAAA==.Mending:BAAANQAECggICgAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAABNQAECn8qAAIYAAoK9yAYFgAGAwAYAAoK9yAYFgAGAwAAAA==.Miler:BAABNQAECn8UAAILAAcKWAgQXgAfAQALAAcKWAgQXgAfAQAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAABNQAECn8iAAMaAAcK6yMfGgBpAgAaAAcK6yMfGgBpAgAVAAEKAACtpAAAAAAAAA==.Mogryn:BAABNQAECn84AAIMAAoKiBsTKACfAgAMAAoKiBsTKACfAgAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monkeydluffy:BAAANQAECgQIBQAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moondog:BAAANQAECgEIAQAAAA==.Moonwarriorx:BAABNQAECn8XAAIFAAkKcxOdCgDrAQAFAAkKcxOdCgDrAQAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQAECgQIBAABNQAECgkJMQAKAGsTAA==.Morthok:BAABNQAECn8aAAIHAAkKdA90WADLAQAHAAkKdA90WADLAQAAAA==.Mosh:BAABNQAECn8jAAIjAAcK8xyEDQAjAgAjAAcK8xyEDQAjAgAAAA==.',
Mu='Muskelunge:BAAANQAECgMICQAAAA==.Mustachekick:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAABNQAECn8vAAIMAAoKpxe9TQAzAgAMAAoKpxe9TQAzAgAAAA==.Nafir:BAAANQAECgYIBgAAAA==.Nakky:BAAANQADCggICwAAAA==.Nazgor:BAABNQAECn8xAAIfAAoKGR1LFABQAgAfAAoKGR1LFABQAgAAAA==.',
Ne='Necrodragon:BAAANQADCgMIBgAAAA==.Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQADCggIIQAAAA==.Newwt:BAAANQADCgcIBwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQAECggIDwAAAA==.',
Oa='Oath:BAABNQAECn8gAAMPAAoKxBf/MAA4AgAPAAoK7RP/MAA4AgACAAUK4RZfWwBKAQAAAA==.',
Ob='Obscyra:BAABNQAECn8mAAIcAAcKyw2RGAAzAQAcAAcKyw2RGAAzAQABNQAECgoKIgAVANQPAA==.',
Oc='Ochiie:BAAANQAECgQIAgAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddsham:BAAANQADCgYIBwAAAA==.Oddyeppyep:BAAANQADCgYIEQAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Ol='Olmek:BAACNQAFFH8MAAMEAAYKwQUKGwA8AQAEAAYKwQUKGwA8AQAFAAEK7AnzBgA9AAA1AAQKf1sAAwQACgrzI3sQABYDAAQACgp6I3sQABYDAAUABQpcIyEOAJ8BAAAA.',
Oo='Oochie:BAABNQAECn8pAAIIAAkKfQ1GZwCpAQAIAAkKfQ1GZwCpAQAAAA==.Oochiee:BAAANQAECgQIBQAAAA==.Oochiië:BAAANQAECgQIBQAAAA==.',
Op='Oprahwndfury:BAAANQAECgYICAABNQAECgQIBQABAAAAAA==.',
Pa='Palanoris:BAAANQABCggIGwAAAA==.Palasades:BAABNQAECn8fAAIDAAkKDglxwgBPAQADAAkKDglxwgBPAQAAAA==.Palelore:BAAANQAECgQIDAAAAA==.Pallydussy:BAAANQAECgMIAwAAAA==.Pallymarc:BAAANQADCgQIBAAAAA==.Pandalorian:BAABNQAECn82AAIIAAoKSBYYSgBHAgAIAAoKSBYYSgBHAgAAAA==.Papapumpies:BAABNQAECn9IAAIEAAoK6yLRGgDdAgAEAAoK6yLRGgDdAgAAAA==.Parlow:BAAANQADCggIGQAAAA==.Pazzo:BAAANQAECgUIBQAAAA==.',
Ph='Pharaa:BAABNQAECn8sAAIOAAgK/AehLAAiAQAOAAgK/AehLAAiAQAAAA==.Philandre:BAAANQAECgcIDgAAAA==.',
Pi='Picoso:BAABNQAECn8YAAIJAAgKswVhygAUAQAJAAgKswVhygAUAQAAAA==.Piianna:BAABNQAECn8vAAIIAAoKJBhCLwCrAgAIAAoKJBhCLwCrAgAAAA==.Pikshunoob:BAAANQADCgIIAgAAAA==.Pizzaroll:BAABNQAECn84AAIkAAoKIyG/BgDlAgAkAAoKIyG/BgDlAgAAAA==.',
Pl='Ploppy:BAAANQADCgIIAgAAAA==.',
Po='Pomégranate:BAAANQADCggICgAAAA==.Popeweaseliv:BAAANQAECgIIAgABNQAECgoKKgAMAA4kAA==.',
Pu='Puckster:BAABNQAECn8WAAIVAAUKeQOUbAB5AAAVAAUKeQOUbAB5AAAAAA==.Punchingfox:BAAANQAECgIIAgAAAA==.',
['Pø']='Pøwe:BAAANQADCgUICAABNQAECgQIBQABAAAAAA==.',
Qa='Qatbarph:BAAANQAECgYIEgAAAA==.',
Qi='Qik:BAAANQAECgUIBAAAAA==.Qikkaw:BAABNQAECn8vAAMYAAkKxBE4fAA+AQAYAAkKxBE4fAA+AQAZAAYKGAxVnQDNAAAAAA==.',
Qu='Quantos:BAABNQAECn8sAAIkAAgKUxH4KQA6AQAkAAgKUxH4KQA6AQAAAA==.',
Ra='Raatha:BAABNQAECn8rAAIDAAoKwBdXZgAEAgADAAoKwBdXZgAEAgAAAA==.Raganar:BAABNQAECn82AAIQAAgKMgwILgAJAQAQAAgKMgwILgAJAQAAAA==.Rago:BAAANQAECgcICwAAAA==.Rasz:BAABNQAECn8/AAMMAAkKYhxNTwAvAgAMAAkKYhxNTwAvAgAhAAYKgg3sSQARAQAAAA==.Rayjean:BAAANQADCgQIBwABNQAECgYICgABAAAAAA==.',
Re='Regelia:BAAANQADCgcIBwAAAA==.Reider:BAAANQAECgMIAwAAAA==.Relmax:BAABNQAECn8fAAIWAAoKIAi5HwAAAQAWAAoKIAi5HwAAAQAAAA==.Rennia:BAAANQAECgIIAgABNQAECggIEAABAAAAAA==.Renri:BAAANQAECgMIAwAAAA==.Renzu:BAAANQADCgYIAQAAAA==.',
Rh='Rhonwynn:BAABNQAECn8tAAIYAAgKgxjUPgAZAgAYAAgKgxjUPgAZAgAAAA==.',
Ri='Rikershipdwn:BAABNQAECn8aAAIMAAoKSww4mACEAQAMAAoKSww4mACEAQAAAA==.Rimrave:BAABNQAECn8qAAMWAAoKcBU1FAB7AQAEAAoK5Q6AcwCoAQAWAAcK6hc1FAB7AQAAAA==.Ritobeans:BAAANQADCggIDQAAAA==.',
Rk='Rk:BAABNQAECn8pAAIdAAgK+A36DgBVAQAdAAgK+A36DgBVAQABNQAECgoKLQAaALkQAA==.',
Ro='Robertkenway:BAABNQAECn8tAAIlAAkK2wviBwDnAQAlAAkK2wviBwDnAQABNQAECgoKLQAaALkQAA==.Roberto:BAAANQADCggICgAAAA==.Rod:BAABNQAECn8nAAISAAoKCRM1GwDPAQASAAoKCRM1GwDPAQAAAA==.Rokte:BAABNQAECn8kAAINAAoKcRNaBwDxAQANAAoKcRNaBwDxAQABNQAECgoKJAANAHETAA==.Rollhots:BAAANQAECgYIDQAAAA==.Rook:BAABNQAECn9AAAMNAAoKwiNrAQBIAwANAAoKPyNrAQBIAwAHAAYK4hxtTgDpAQAAAA==.Rooke:BAABNQAECn8fAAIEAAkKoRrEegAoAgAEAAkKoRrEegAoAgABNQAECgoKQAANAMIjAA==.Rorsh:BAAANQAECgQIBAAAAA==.Rosekenway:BAABNQAECn8tAAMaAAoKuRDgHQATAgAaAAoKuRDgHQATAgAVAAEKwwGOwgAfAAAAAA==.',
Rr='Rratt:BAAANQADCgcIDwAAAA==.',
Ru='Rubyknight:BAAANQADCgYICQAAAA==.Running:BAAANQAECggIEAAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQAECgUIDwAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQICQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAABNQAECn8vAAMcAAkKiRcNDgDMAQAcAAkKiRcNDgDMAQAJAAEKHA77XQE0AAAAAA==.',
Se='Sedrick:BAABNQAECn84AAQXAAoKex4cHQDSAgAXAAkKvB0cHQDSAgADAAkK1hJ/wgCXAQAQAAUK4xNONADjAAAAAA==.Sekaholic:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekhmett:BAAANQADCgIIAgAAAA==.Sekndestroy:BAAANQAECgIIAgAAAA==.Seksational:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Sekthyr:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Sekzen:BAAANQADCgUIDgABNQAECgIIAgABAAAAAA==.Sepulveda:BAAANQAECgQIBQABNQAECgcIIgAaAOsjAA==.',
Sh='Shamtune:BAACNQAFFH8NAAIYAAUK/BFGEwAvAQAYAAUK/BFGEwAvAQA1AAQKfyYAAxgACgoXFtBIAD8CABgACgoXFtBIAD8CABkAAQqdDkEuAToAAAAA.Sharayman:BAAANQAECgYICgAAAA==.Shattered:BAAANQAECgcICAAAAA==.Shaydra:BAABNQAECn8uAAILAAkKaRQ3QwC3AQALAAkKaRQ3QwC3AQAAAA==.Shazool:BAABNQAECn80AAMYAAoKoyODCQB1AwAYAAoKoyODCQB1AwAeAAQK/gqTJwDqAAAAAA==.Shevee:BAAANQADCgEIAQAAAA==.Shifterz:BAAANQAECgUICQAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAABNQAECn8XAAIkAAkKhAxjKwA8AQAkAAkKhAxjKwA8AQAAAA==.Shtialdryn:BAAANQADCgYIBgAAAA==.',
Si='Siarra:BAAANQADCgMIAwAAAA==.Sind:BAAANQADCgIIAgABNQAECgcIFQAHACcKAA==.Sindella:BAABNQAECn8VAAMHAAcKJwp/mwAhAQAHAAcKJwp/mwAhAQAGAAEKFgPNhQAjAAAAAA==.Sindrè:BAAANQABCgUIBQABNQAECgcIFQAHACcKAA==.Sinna:BAAANQADCgYICgAAAA==.Sinpriest:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Sk='Skedaddle:BAAANQAECgQICgABNQAECgkJPQAcAB0hAA==.',
Sl='Slashgquit:BAABNQAECn8ZAAIgAAcKVCJCMABQAgAgAAcKVCJCMABQAgAAAA==.Slinx:BAAANQADCgIIAgAAAA==.Slumbermist:BAABNQAECn8xAAIKAAkKaxPsLACyAQAKAAkKaxPsLACyAQAAAA==.',
Sn='Snazzi:BAABNQAECn8nAAIZAAgKdw2RfACuAQAZAAgKdw2RfACuAQAAAA==.Snowtitan:BAAANQADCgUIBQAAAA==.',
So='Solam:BAAANQAECgMIAwAAAA==.',
Sp='Sploob:BAAANQADCgUIBQAAAA==.',
St='Stabbs:BAAANQADCggIDgAAAA==.Steph:BAAANQAECgIIAgAAAA==.Strawberyy:BAAANQAECgMIAgABNQAFFAYIDgAEAPQXAA==.Strongboy:BAAANQADCgUIBwAAAA==.Stx:BAAANQADCggICAABNQAECggIFAAlAN8PAA==.',
Su='Survival:BAAANQAECgMIAgAAAA==.',
Sy='Syndar:BAABNQAECn8lAAMZAAoKKx41KQDcAgAZAAkKsh81KQDcAgAYAAIK1g8z0AB2AAAAAA==.Synthetic:BAABNQAECn8iAAIGAAcKog11DQDpAAAGAAcKog11DQDpAAAAAA==.',
Sz='Szasstaam:BAAANQAECggIBQAAAA==.',
Ta='Talionsauron:BAAANQADCggIAgAAAA==.Tandá:BAAANQADCgMIAwABNQADCggICgABAAAAAA==.Tarnaris:BAAANQADCgIIAgAAAA==.Tattersaile:BAAANQADCgUIBwAAAA==.',
Te='Tecsaran:BAAANQAECgYICgABNQAECgoKJQAZACseAA==.Tekis:BAAANQAECgQICAAAAA==.Tensanio:BAAANQAECgUIBAAAAA==.',
Th='Thalira:BAABNQAECn8cAAImAAoKCgaGHQApAQAmAAoKCgaGHQApAQAAAA==.Thalrix:BAABNQAECn8qAAIDAAoKEBRTZwACAgADAAoKEBRTZwACAgAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUIBwAAAA==.Thetowelie:BAAANQADCgMIAwAAAA==.Thickneck:BAAANQADCgUIBQAAAA==.',
Ti='Tieson:BAAANQAECgUIDAAAAA==.Tinkera:BAAANQADCgcIEQAAAA==.Titanosaurus:BAAANQAECgIIAgAAAA==.',
To='Tomcruise:BAAANQABCgUICAABNQAECgIIAgABAAAAAA==.Torridwells:BAAANQAECgUICQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAABNQAECn8jAAIYAAcKcRbTWACxAQAYAAcKcRbTWACxAQAAAA==.Troagstar:BAABNQAECn8jAAIZAAcKIA+egwAIAQAZAAcKIA+egwAIAQAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAACNQAFFH8FAAITAAQKWg95DwDRAAATAAQKWg95DwDRAAA1AAQKfzwAAxMACgpVH44TAIcCABMACgpVH44TAIcCABsABQpOEg01APIAAAAA.Tyrmog:BAAANQADCggIFAAAAA==.Tytus:BAAANQABCgcIDwAAAA==.',
Un='Undetha:BAABNQAECn8aAAIgAAkKqxfhIgDjAQAgAAkKqxfhIgDjAQAAAA==.',
Us='Ushas:BAABNQAECn81AAMIAAoKBRrdVAAkAgAIAAoKBRrdVAAkAgAOAAEKAAAZhAAlAAAAAA==.',
Va='Vaeiane:BAAANQAECggICAABNQAECggIEAABAAAAAA==.Vali:BAAANQADCgcIDQABNQAECgoKIAAPAMQXAA==.Valindrea:BAAANQAECgUIDwAAAA==.Vasrael:BAABNQAECn8UAAMDAAgKXQ/25gBNAQADAAgKXQ/25gBNAQAXAAQKfBrpqQAuAQAAAA==.Vasrannah:BAAANQAECgUIBQAAAA==.',
Ve='Vel:BAABNQAECn83AAMbAAoKygsJHwCrAQAbAAoKygsJHwCrAQAUAAcKmQIXIQC7AAAAAA==.Velnie:BAAANQAECgMIBQAAAA==.Venvanse:BAAANQAECgEIAQABNQAECgoKJwAJANIRAA==.Verq:BAAANQAECgEIAQAAAA==.Vexen:BAABNQAECn8cAAIbAAcKUBe9LQDUAQAbAAcKUBe9LQDUAQAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAACNQAFFH8GAAIbAAMK+wtJDgB4AAAbAAMK+wtJDgB4AAA1AAQKfzsAAxsACgpKHGcXAKMCABsACgpKHGcXAKMCABMACAoIEZRJAH8BAAAA.',
Vy='Vynis:BAAANQAFFAEIAQABNQAFFAUIDQAYAPwRAA==.Vyrahildard:BAABNQAECn8qAAIDAAoK8RV2ggAjAgADAAoK8RV2ggAjAgAAAA==.',
Wa='Wasteland:BAABNQAECn9AAAIgAAoK6A3VMwB6AQAgAAoK6A3VMwB6AQAAAA==.Watermelon:BAACNQAFFH8JAAIYAAMKmRDgGgDQAAAYAAMKmRDgGgDQAAA1AAQKfzkAAxgACgreEYZZAAQCABgACgreEYZZAAQCABkABgoCFPOGAAABAAE1AAUUBggWABoA3RIA.',
We='Weaselhunter:BAABNQAECn8qAAIMAAoKDiTdFQBEAwAMAAoKDiTdFQBEAwAAAA==.Weasellock:BAABNQAECn8lAAIHAAkKyhlePgAbAgAHAAkKyhlePgAbAgABNQAECgoKKgAMAA4kAA==.Weaselmage:BAABNQAECn8hAAMcAAkKcxIBHgDkAAAJAAgKfwzhowBcAQAcAAQKcBkBHgDkAAABNQAECgoKKgAMAA4kAA==.Weaselshammy:BAABNQAECn8jAAIZAAoKOxxyMAAXAgAZAAoKOxxyMAAXAgABNQAECgoKKgAMAA4kAA==.',
Wh='Whatthef:BAAANQADCgcIDwAAAA==.',
Wi='Wildweasel:BAABNQAECn8ZAAIDAAgKxBU/mQCaAQADAAgKxBU/mQCaAQABNQAECgoKKgAMAA4kAA==.Windchill:BAAANQAECgEIAQAAAA==.Winterhide:BAABNQAECn8cAAMLAAgKHxGQSAB2AQALAAgKWguQSAB2AQAfAAYKfxMRcQBRAQAAAA==.Wishbone:BAABNQAECn8kAAIJAAkKoxOfawDbAQAJAAkKoxOfawDbAQAAAA==.',
Wo='Womamatoo:BAAANQADCgcICgAAAA==.',
Xa='Xallie:BAEANQAECgYIDgAAAA==.Xanvyr:BAAANQAECgYICAABNQAECgUICQABAAAAAA==.Xaquillis:BAABNQAECn8qAAIgAAoKJxDSOgBWAQAgAAoKJxDSOgBWAQAAAA==.Xaras:BAAANQADCgMIAwAAAA==.',
Xe='Xentrie:BAAANQAECgQICgAAAA==.Xeyvara:BAABNQAECn8pAAIUAAoK/h5hBACYAgAUAAoK/h5hBACYAgAAAA==.',
Ya='Yah:BAAANQADCggIDQAAAA==.',
Za='Zaravalatha:BAAANQADCgUICQAAAA==.Zarihanna:BAABNQAECn83AAIJAAgKkBDPwAADAgAJAAgKkBDPwAADAgAAAA==.Zariia:BAAANQAECgIIAQAAAA==.Zarsiia:BAAANQAECgQIDQAAAA==.Zatima:BAAANQAECgUIBQAAAA==.',
Ze='Zernakk:BAAANQAECgUICgAAAA==.Zestdh:BAAANQAECgUIBwAAAA==.Zestyknight:BAABNQAECn8ZAAIgAAkKGB7oEwBxAgAgAAkKGB7oEwBxAgAAAA==.',
Zi='Zindeshal:BAAANQADCggIDQAAAA==.',
Zo='Zorcunter:BAABNQAECn89AAIMAAoK+yS2EAAPAwAMAAoK+yS2EAAPAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQAECgEIAQAAAA==.',
['Ðo']='Ðonjon:BAAANQAECgEIAQAAAA==.',
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
