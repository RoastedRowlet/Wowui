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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Affliction','Shaman-Elemental','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Paladin-Protection','Priest-Discipline','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','Warrior-Protection','Paladin-Holy','Shaman-Restoration','Druid-Restoration','DemonHunter-Devourer','Mage-Frost','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abbii:BAAANQADCgIIAgAAAA==.',
Ai='Aidalen:BAAANQAECgEIAQAAAA==.',
Ak='Akaidia:BAAANQAECggICAABNQAECggIEgABAAAAAA==.',
Al='Alckmin:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAABNQAECn8VAAICAAkKUxQNGABOAQACAAkKUxQNGABOAQAAAA==.Allysaun:BAAANQAECgMICAAAAA==.Altacia:BAAANQADCgQIBAAAAA==.',
Am='Amaurra:BAAANQABCgQIBAAAAA==.Amorina:BAABNQAECn8eAAIDAAoKPxG1nQBRAQADAAoKPxG1nQBRAQAAAA==.',
An='Anda:BAAANQAECgEIAQAAAA==.Andill:BAAANQAECgQICAAAAA==.Andracca:BAAANQAECgUIBQAAAA==.Andromeda:BAAANQAECgUICQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAACNQAFFH8OAAMEAAYK9BeMCgBQAQAEAAUK9BeMCgBQAQAFAAEKAADmBAAAAAA1AAQKfygAAgQACgpRHr5OAJ0CAAQACgpRHr5OAJ0CAAAA.Angrygnome:BAABNQAECn88AAMGAAoKax9cAwAQAwAGAAoKLRtcAwAQAwAHAAoK+RzUGACXAgAAAA==.Angélique:BAAANQAECggIDwABNQAFFAYIDgAEAPQXAA==.Anieros:BAAANQAECgEIAgABNQAFFAQICAACAEwRAA==.',
Ar='Arai:BAAANQADCgMIBAAAAA==.Arax:BAAANQAECggIDwAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAABNQAECn8aAAIDAAcKJQpd5gDWAAADAAcKJQpd5gDWAAAAAA==.Armâgeddon:BAABNQAECn8qAAIEAAkKcyB+LAAKAwAEAAkKcyB+LAAKAwAAAA==.Arrokoth:BAAANQAECgEIAQAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.',
As='Astyl:BAAANQAECgYIBgAAAA==.',
At='Athurnz:BAAANQAECgEIAQAAAA==.Atropós:BAABNQAECn8YAAIIAAkKaQqjfQCAAQAIAAkKaQqjfQCAAQAAAA==.Attachedplag:BAABNQAECn8fAAMEAAkKUA2naACNAQAEAAkKUA2naACNAQAFAAEKPQb8NgArAAAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQAECgYIBgAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Baconhuntard:BAAANQAECgMIAwAAAA==.Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQAECgUIBgAAAA==.Banzen:BAAANQADCggIGwAAAA==.Battle:BAEANQADCgIIAgABNQAECgoKOAAJACAfAA==.',
Be='Beardedyeti:BAAANQABCgQIBAAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAABNQAECn8vAAIKAAoK8RgJJgDqAQAKAAoK8RgJJgDqAQAAAA==.Bernese:BAAANQAECgcICgAAAA==.Berunma:BAABNQAECn8ZAAILAAgKlw23rgCnAQALAAgKlw23rgCnAQAAAA==.',
Bh='Bhain:BAABNQAECn8WAAQGAAoKNxpRCgDyAAAHAAoKYhefMQAbAgAGAAMKxBtRCgDyAAAMAAEKAAD1KwAAAAABNQAECgkJHwANAGEcAA==.',
Bi='Bileshots:BAAANQAECggIDwAAAA==.Biowolf:BAACNQAFFH8GAAIIAAMKdQNLMQCKAAAIAAMKdQNLMQCKAAA1AAQKfxoAAggACQqwEeWyAB0CAAgACQqwEeWyAB0CAAAA.Birdhunter:BAAANQAECgYIBgAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgQIBAABAAAAAA==.Bishopxix:BAAANQAECgQIBAAAAA==.Bits:BAAANQAECgQICgAAAA==.',
Bj='Bjoren:BAABNQAECn8vAAMOAAoKqSCIFwAaAwAOAAoKqSCIFwAaAwAPAAEKAAADlwAKAAAAAA==.',
Bl='Blackki:BAAANQADCgQIBQAAAA==.Bloodbaron:BAAANQAECgcIBgABNQAECggIIQAHAGYVAA==.',
Bo='Bootiebang:BAABNQAECn8gAAIQAAYK4AZ8MAA7AQAQAAYK4AZ8MAA7AQAAAA==.Bootieknight:BAAANQADCgcIBwAAAA==.Bootycaall:BAAANQADCgcIDgAAAA==.Boxxie:BAAANQADCgcIFQAAAA==.',
Br='Branches:BAAANQADCgMIAwAAAA==.Brockshot:BAAANQAECgQIBQAAAA==.',
Bu='Bucknekkid:BAAANQAECgUICQAAAA==.Buckwhild:BAABNQAECn8oAAMOAAoKChzJKwBjAgAOAAoKChzJKwBjAgAPAAEKAADLigAfAAAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAABNQAECn9DAAMRAAoKnCLtBwCiAgARAAoKnCLtBwCiAgADAAUKnhRE8gDEAAAAAA==.Canadaisheal:BAABNQAECn8XAAMSAAgKuw8iBgBUAQASAAYKHBIiBgBUAQAPAAIKvAcAWgAsAAAAAA==.Catslol:BAAANQADCgIIAwAAAA==.',
Ce='Cerñuñños:BAAANQAECgIIAwAAAA==.Cesàrè:BAABNQAECn8XAAITAAUKHgvqJQCqAAATAAUKHgvqJQCqAAAAAA==.',
Ch='Chahra:BAAANQAECgUICQAAAA==.Chamuki:BAABNQAECn8XAAMUAAkKGBVINQA3AQAUAAgKyhVINQA3AQAVAAEKOxBgMAA8AAABNQAFFAcIHAAWAPAZAA==.Chuubak:BAAANQAECggIEAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAABNQAECn8VAAMFAAgK1A7oEwD4AAAFAAgK1A7oEwD4AAAEAAUKgwbE3QCFAAAAAA==.',
Co='Cocomami:BAAANQADCgUIBQAAAA==.Colonidus:BAAANQAECgQIBAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAABNQAECn8iAAIXAAcKxRM6FAA/AQAXAAcKxRM6FAA/AQAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAABNQAECn8pAAMEAAoKqBzLMABVAgAEAAoKqBzLMABVAgAFAAQKWxiFHgDMAAAAAA==.',
Da='Dagby:BAAANQADCgcIGwAAAA==.Dandi:BAAANQAECgIIAgAAAA==.Daneaus:BAAANQADCgMIAwABNQAECggIJwAYANUkAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darkscorp:BAAANQADCgIIAgAAAA==.Darkwolf:BAAANQAECgQICAAAAA==.Darnuus:BAABNQAECn82AAMZAAoKbh3jKADAAgAZAAoKbh3jKADAAgANAAUKCQ1SmgCeAAAAAA==.Datnv:BAAANQADCggICAAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAABNQAECn8mAAMaAAgKSBAKLABFAQAaAAgKSBAKLABFAQAWAAcKwAaWcQADAQAAAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAABNQAECn8lAAIHAAoKLBh7KQA/AgAHAAoKLBh7KQA/AgAAAA==.Delai:BAAANQADCgMIAwAAAA==.Dellin:BAABNQAECn8mAAIWAAgKWRgZKQB9AQAWAAgKWRgZKQB9AQAAAA==.Demeco:BAEANQAECgUICAABNQAFFAkJFgAYAMIYAA==.Demondots:BAAANQAECgUIDAAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Dh='Dhalseem:BAAANQAECgUIBQAAAA==.',
Di='Diminuendo:BAAANQAECgIIAgAAAA==.Divertido:BAAANQAECgEIAQAAAA==.',
Do='Dogz:BAABNQAECn8UAAMbAAkKWRo8CwB+AgAbAAkKWRo8CwB+AgAVAAIKuwsKIgBWAAABNQAFFAcIHQALAHIhAA==.Doozydruid:BAABNQAECn8UAAIWAAcKeg/rVQCAAQAWAAcKeg/rVQCAAQAAAA==.Dorozh:BAABNQAECn8VAAIGAAkKPw/TBwAoAQAGAAkKPw/TBwAoAQAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonstorm:BAAANQAECggICAAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAABNQAECn8eAAIOAAcK4xY3agBiAQAOAAcK4xY3agBiAQAAAA==.Dreadar:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Dreadmage:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Dreadpally:BAAANQADCgYJCgABNQADCgYICgABAAAAAA==.Dreco:BAAANQAECgcIEgAAAA==.Driver:BAEANQAECggICQAAAA==.Drtydhn:BAAANQABCgMIAwAAAA==.Druuzak:BAABNQAECn8uAAIcAAoKRw69CgCvAQAcAAoKRw69CgCvAQAAAA==.Dryconias:BAABNQAECn9JAAIDAAoKBB6zQwDJAgADAAoKBB6zQwDJAgAAAA==.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duknazra:BAAANQAECgIIAgAAAA==.Duncanmcleod:BAABNQAECn8dAAIEAAoK/RaaVQDIAQAEAAoK/RaaVQDIAQABNQAECgoKKgAOANQdAA==.Dunkelzhan:BAABNQAECn8pAAIIAAgKehQrkABXAQAIAAgKehQrkABXAQAAAA==.',
Dv='Dvldogma:BAAANQAECgUIDQAAAA==.',
Dy='Dyana:BAABNQAECn8VAAILAAkKtAyNqQCyAQALAAkKtAyNqQCyAQAAAA==.',
Dz='Dz:BAABNQAECn9DAAMYAAoKpyXFBACqAwAYAAoKpyXFBACqAwADAAYKDA7I9AAzAQAAAA==.',
['Dø']='Dømimømmÿ:BAAANQAECgMIAwAAAA==.',
Ec='Ecobessie:BAAANQADCgcIDQAAAA==.Ecowolf:BAAANQADCgYICgABNQADCgcIDQABAAAAAA==.',
Ed='Edlund:BAABNQAECn8bAAIdAAgKTwm4DgAjAQAdAAgKTwm4DgAjAQAAAA==.',
El='Electricfun:BAAANQAECgMIAwAAAA==.Ellenaim:BAAANQAECgUICAAAAA==.Elvy:BAABNQAECn87AAIWAAoKQBlnGQANAgAWAAoKQBlnGQANAgAAAA==.',
En='Enngin:BAAANQAECgMIAwAAAA==.Enroks:BAABNQAECn80AAQNAAoKhxMvOgCxAQANAAoKhxMvOgCxAQAZAAYKZhkdggCGAQAeAAEKAAARNwAzAAAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAABNQAECn8wAAMaAAgKAxUWLAC7AQAaAAgKAxUWLAC7AQAWAAUKWgechQC8AAAAAA==.Evangelina:BAAANQADCgEIAQAAAA==.',
Ex='Exsalsior:BAACNQAFFH8IAAMCAAQKTBHGBADeAAACAAMKTBHGBADeAAAQAAEKAACbIwAAAAA1AAQKfxgAAgIACQr4E6g1AAICAAIACQr4E6g1AAICAAAA.',
Ey='Eyedoc:BAAANQAECgEIAQAAAA==.',
Fa='Fabulousness:BAAANQAECgcIEgAAAA==.Fathur:BAAANQADCggICwAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQAECgUIEQAAAA==.Furussy:BAAANQADCgcIBwAAAA==.Furytotem:BAAANQAECgEIAgABNQAECgEIAQABAAAAAA==.',
Ga='Galadhras:BAAANQADCgYIDAAAAA==.Galdryn:BAAANQABCgQIBQAAAA==.Gamboslice:BAABNQAECn8wAAIKAAoKZxZqLQA1AgAKAAoKZxZqLQA1AgAAAA==.Garkevon:BAABNQAECn8sAAMfAAkKqQjQKwBVAQAfAAkKqQjQKwBVAQAgAAMKPgTJjAA7AAAAAA==.',
Ge='Gevul:BAABNQAECn9fAAQHAAoKmBwoMQAdAgAHAAkKIx0oMQAdAgAGAAMK+hFKOQDbAAAMAAEKAADLMQAxAAAAAA==.',
Gh='Ghuun:BAABNQAECn8hAAIHAAgKZhULXQCEAQAHAAgKZhULXQCEAQAAAA==.',
Gi='Gitmerge:BAAANQADCgYIBgAAAA==.',
Gl='Glep:BAAANQADCggICwAAAA==.Glimmervoid:BAAANQAECgQICQAAAA==.',
Go='Golland:BAAANQABCgIIAgABNQAECgoKOQANAKAaAA==.Goob:BAAANQADCgYIBgAAAA==.Gorecurse:BAAANQAECgIIAgAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAABNQAECn8ZAAIDAAgKFxdkiAAWAgADAAgKFxdkiAAWAgAAAA==.Grimero:BAAANQAECggIAwAAAA==.Groinsapper:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Grozny:BAAANQAECgEIAQABNQAECgkJGAAWACQPAA==.',
Gs='Gsstuff:BAAANQADCgIIAgAAAA==.',
Gu='Gumboslice:BAACNQAFFH8JAAIaAAUKjhQwBwBEAQAaAAUKjhQwBwBEAQA1AAQKfz4AAxoACgrmH1IRAMkCABoACgrmH1IRAMkCABYAAQoAAG6UAAAAAAAA.Gumiho:BAAANQAECgcIEgAAAA==.Gusgus:BAABNQAECn8jAAIcAAgKbgz+EQAuAQAcAAgKbgz+EQAuAQAAAA==.Guud:BAAANQAECgQIBAAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAACNQAFFH8JAAILAAQKkxGSEQBHAQALAAQKkxGSEQBHAQA1AAQKfyUAAgsACgrAIZsTAFADAAsACgrAIZsTAFADAAAA.Habanero:BAABNQAECn8jAAINAAkKvR/OIQA4AgANAAkKvR/OIQA4AgAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQAECggIAgABNQAECgkKOgAhAHcNAA==.Hammerfist:BAAANQAECgYIDgAAAA==.Hark:BAAANQADCgcIGAAAAA==.Haveabubble:BAAANQAECgEIAQABNQAECggIJwAXAO4YAA==.',
He='Healvisprsly:BAAANQAECgEIAQAAAA==.Helena:BAABNQAECn80AAMRAAoKdCK+BgDCAgARAAoKdCK+BgDCAgADAAgKNhpecwBIAgAAAA==.Heliarc:BAAANQADCgcIHgAAAA==.',
Hi='Hidän:BAABNQAECn8bAAMHAAcKuwukvQBRAQAHAAcKuwukvQBRAQAGAAEKwgWSfgAuAAAAAA==.Himself:BAAANQADCgUIBQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.Hoomalu:BAAANQADCgIIAgAAAA==.',
Hu='Huund:BAAANQADCgUIBQAAAA==.Huutou:BAAANQAECgEIAQAAAA==.',
Il='Illatix:BAAANQAECgQICAAAAA==.Illustriä:BAABNQAECn8YAAILAAYKzww4vwDvAAALAAYKzww4vwDvAAAAAA==.',
In='Insidious:BAABNQAECn8cAAIgAAcKlxxiMABQAgAgAAcKlxxiMABQAgAAAA==.',
Ir='Irs:BAABNQAECn8VAAIDAAkKRRdNPgA/AgADAAkKRRdNPgA/AgAAAA==.',
Is='Isisvane:BAAANQAECgEIAQAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECgkJKQAcADIfAA==.Itchymage:BAABNQAECn8pAAMcAAkKMh+jFQBTAQAIAAkKxh2ghwBvAgAcAAQKEh2jFQBTAQAAAA==.',
Iv='Ivyrayne:BAAANQAECgEIAQAAAA==.',
Ja='Jaganash:BAAANQAECgUIBQABNQAECgoKGwAQAA0WAA==.Jakeofny:BAAANQAECgYICQAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIDQAAAA==.',
Ji='Jighlipuff:BAABNQAECn8iAAIDAAgK8gWo4gDbAAADAAgK8gWo4gDbAAAAAA==.Jigs:BAABNQAECn8yAAILAAkKrQslegB+AQALAAkKrQslegB+AQAAAA==.Jinxy:BAAANQADCggINwABNQAECgQIDwABAAAAAA==.',
Ju='Judgements:BAAANQAECgQICgAAAA==.Jug:BAAANQADCggIMQAAAA==.Jujutanketh:BAAANQAECgUICwAAAA==.Junebugg:BAABNQAECn8VAAIIAAYKogMDcwHYAAAIAAYKogMDcwHYAAAAAA==.',
Ka='Kabøchi:BAABNQAECn8fAAIJAAcK+RAhJgAwAQAJAAcK+RAhJgAwAQAAAA==.Kafia:BAAANQAECgcIEAAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQAECgYIDAAAAA==.Kanaloa:BAAANQAECgUIDgAAAA==.Kaorin:BAAANQAECgEIAQABNQAECgoKNAAZAKMjAA==.Karindis:BAABNQAECn8vAAIVAAoKOyHlAwAYAwAVAAoKOyHlAwAYAwAAAA==.Kathulhu:BAAANQAECgIIAwAAAA==.Kayler:BAAANQAECggIEgAAAA==.',
Ke='Kegerator:BAAANQADCgQIBQAAAA==.Keldica:BAABNQAECn8aAAIHAAoKERhqKwA2AgAHAAoKERhqKwA2AgABNQAECgoKJQANACseAA==.Kenshan:BAAANQAECgEIAQAAAA==.',
Kh='Khalinor:BAABNQAECn8bAAIYAAkKPx7LGwCtAgAYAAkKPx7LGwCtAgAAAA==.Khotuhn:BAAANQAECgQIBAAAAA==.',
Ki='Kickazdin:BAABNQAECn8vAAMYAAoKyx7hKADFAgAYAAkKOx/hKADFAgADAAEKAABNngE4AAAAAA==.Killadragon:BAAANQAECgUIBQAAAA==.Kiryie:BAAANQAECgUIBgAAAA==.Kitinna:BAABNQAECn8WAAMIAAcKZAMC3gDFAAAIAAcK8QIC3gDFAAAcAAEKXAQLUQAlAAAAAA==.',
Kl='Klaw:BAAANQADCgYIEAAAAA==.',
Ko='Korraa:BAABNQAECn8lAAMZAAoKBBxfTwAnAgAZAAoKBBxfTwAnAgANAAYKKBGqsQAvAQAAAA==.',
Kp='Kprist:BAAANQAECgUIDAAAAA==.',
Kr='Kraigen:BAABNQAECn8UAAIUAAcKRg3VNQA0AQAUAAcKRg3VNQA0AQAAAA==.',
Ku='Kunzhut:BAABNQAECn8fAAMfAAgKIhWnVQC7AQAfAAgKIhWnVQC7AQAKAAQKsQhneQCKAAAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgcIEwAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Laeli:BAAANQAECgQIDwAAAA==.Lailyre:BAAANQAECggIBwABNQAECggIEgABAAAAAA==.Laydin:BAABNQAECn8gAAILAAgKIwVdAAEEAQALAAgKIwVdAAEEAQABNQAECggIJgAaAEgQAA==.',
Lb='Lb:BAABNQAECn8kAAMLAAoKNhrfQgAVAgALAAoKNhrfQgAVAgAhAAUKcAsxSwAJAQAAAA==.',
Le='Legzanot:BAACNQAFFH8FAAINAAIKKgMlJQA1AAANAAIKKgMlJQA1AAA1AAQKf0sAAg0ACgpFFuImABUCAA0ACgpFFuImABUCAAAA.Lestrade:BAABNQAECn8rAAIgAAoKCxFKIwC0AQAgAAoKCxFKIwC0AQABNQAECgoKNgAZAG4dAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAABNQAECn8pAAMDAAgKUxWKkwBlAQADAAgKUxWKkwBlAQAYAAMKigzlBAFvAAAAAA==.Lightsfallen:BAABNQAECn8qAAMOAAoK1B1UFAAJAwAOAAoK1B1UFAAJAwASAAEKuwa4LQApAAAAAA==.Lilnasdormu:BAAANQADCgUIBQABNQAECgcIGQAKAPARAA==.Lithia:BAAANQAECgUICAAAAA==.Littlemo:BAAANQAECgUIEAAAAA==.',
Lo='Lohnar:BAAANQAECgUIEAAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgcIEgAAAA==.Lucielbaal:BAABNQAECn8kAAIHAAgKsRpdSwC7AQAHAAgKsRpdSwC7AQAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQAECgEIBQAAAA==.Lunareth:BAABNQAECn8YAAIWAAkKJA9lKwBtAQAWAAkKJA9lKwBtAQAAAA==.',
Ly='Lyrska:BAAANQAECgUIEgAAAA==.Lytearrow:BAABNQAECn8YAAILAAgK+Qn+kQDlAQALAAgK+Qn+kQDlAQAAAA==.',
['Lì']='Lìvíd:BAAANQAECgYIEQAAAA==.',
Ma='Mahrylee:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgUICQAAAA==.Makbeard:BAAANQADCgYIBgABNQAECggIFgAiADERAA==.Makmobius:BAABNQAECn8WAAIiAAgKMRHeCABcAQAiAAgKMRHeCABcAQAAAA==.Manbearpally:BAAANQAECgEIAQAAAA==.Mannypack:BAAANQAECgUICQAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgcIFwABAAAAAA==.Mathau:BAAANQADCgcIFwAAAA==.Maztrix:BAAANQAECgIIAwAAAA==.',
Mc='Mcleary:BAABNQAECn8VAAIDAAUKug1t3gDiAAADAAUKug1t3gDiAAAAAA==.',
Me='Meistro:BAAANQAECgEIAgAAAA==.Meldrus:BAABNQAECn8XAAIHAAgK/gnsmQCmAQAHAAgK/gnsmQCmAQAAAA==.Mending:BAAANQAECgYICQAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAABNQAECn8nAAIZAAgK+CBeKABZAgAZAAgK+CBeKABZAgAAAA==.Miler:BAAANQAECgUIDAAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAABNQAECn8dAAIaAAYKCCQfGgBpAgAaAAYKCCQfGgBpAgAAAA==.Mogryn:BAABNQAECn8iAAILAAkKNRd2TQD1AQALAAkKNRd2TQD1AQAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moondog:BAAANQAECgEIAQAAAA==.Moonwarriorx:BAABNQAECn8UAAIFAAkKyRIECADoAQAFAAkKyRIECADoAQAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQAECgQIBAABNQAECgEIAQABAAAAAA==.Morthok:BAABNQAECn8XAAIHAAcK/BGxYQB2AQAHAAcK/BGxYQB2AQAAAA==.Mosh:BAABNQAECn8jAAIjAAcK8xyEDQAjAgAjAAcK8xyEDQAjAgAAAA==.',
Mu='Muskelunge:BAAANQAECgQIBgAAAA==.Mustachekick:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAABNQAECn8nAAILAAgK5hijcwApAgALAAgK5hijcwApAgAAAA==.Nafir:BAAANQAECgYICAAAAA==.Nakky:BAAANQADCggICwAAAA==.Naritra:BAAANQAECggIAgABNQAECggIEgABAAAAAA==.Nazgor:BAABNQAECn8mAAIfAAoKVhwZFAAnAgAfAAoKVhwZFAAnAgAAAA==.',
Ne='Necrodragon:BAAANQADCgMIBgAAAA==.Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQADCgcIHgAAAA==.Newwt:BAAANQADCgcIBwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQAECgUIDQAAAA==.',
Oa='Oath:BAABNQAECn8bAAMQAAoKDRYRKwAcAgAQAAoKNxIRKwAcAgACAAUK4RZfWwBKAQAAAA==.',
Ob='Obscyra:BAABNQAECn8iAAIcAAYKyw2RGAAzAQAcAAYKyw2RGAAzAQABNQAECgkJGAAWACQPAA==.',
Oc='Ochiie:BAAANQAECgQIAwAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddsham:BAAANQADCgYIBwAAAA==.Oddyeppyep:BAAANQADCgYIEQAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Ol='Olmek:BAACNQAFFH8MAAMEAAYKwQUKGwA8AQAEAAYKwQUKGwA8AQAFAAEK7AnzBgA9AAA1AAQKf08AAwQACgoVIzwNABwDAAQACgoVIzwNABwDAAUABAruD+IeAMgAAAAA.',
Oo='Oochie:BAABNQAECn8pAAIOAAkKfQ3lUQC5AQAOAAkKfQ3lUQC5AQAAAA==.Oochiee:BAAANQAECgQIBgAAAA==.Oochiië:BAAANQAECgQIBgAAAA==.',
Op='Oprahwndfury:BAAANQAECgMIBQABNQAECgEIAQABAAAAAA==.',
Pa='Palanoris:BAAANQABCggIGwAAAA==.Palasades:BAABNQAECn8VAAIDAAgKvQYL4wDbAAADAAgKvQYL4wDbAAAAAA==.Palelore:BAAANQAECgQIBwAAAA==.Pallydussy:BAAANQAECgMIBAAAAA==.Pallymarc:BAAANQADCgQIBAAAAA==.Pandalorian:BAABNQAECn8tAAIOAAoKSBYYSgBHAgAOAAoKSBYYSgBHAgAAAA==.Papapumpies:BAABNQAECn8/AAIEAAoK6yLoGwC9AgAEAAoK6yLoGwC9AgAAAA==.Parlow:BAAANQADCggIGQAAAA==.Pazzo:BAAANQAECgUIBgAAAA==.',
Ph='Pharaa:BAABNQAECn8jAAIPAAgKlgeIJQAbAQAPAAgKlgeIJQAbAQAAAA==.Philandre:BAAANQAECgQIBwAAAA==.',
Pi='Picoso:BAABNQAECn8VAAIIAAcK7AXgxAD0AAAIAAcK7AXgxAD0AAAAAA==.Piianna:BAABNQAECn8vAAIOAAoKJBhCLwCrAgAOAAoKJBhCLwCrAgAAAA==.Pikshunoob:BAAANQADCgIIAgAAAA==.Pizzaroll:BAABNQAECn8uAAIkAAoKrx/WCADrAgAkAAoKrx/WCADrAgAAAA==.',
Pl='Ploppy:BAAANQADCgIIAgAAAA==.',
Po='Pomégranate:BAAANQADCggICgAAAA==.',
Pu='Puckster:BAAANQAECgQIDwAAAA==.',
['Pø']='Pøwe:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.',
Qa='Qatbarph:BAAANQAECgYIEgAAAA==.',
Qi='Qikkaw:BAABNQAECn8kAAMZAAgKvRC+mgBEAQAZAAgKvRC+mgBEAQANAAYKMQqgpQCJAAAAAA==.',
Qu='Quantos:BAABNQAECn8kAAIkAAcKDhOWJQAgAQAkAAcKDhOWJQAgAQAAAA==.',
Ra='Raatha:BAABNQAECn8mAAIDAAgK9hndfwCNAQADAAgK9hndfwCNAQAAAA==.Raganar:BAABNQAECn8sAAIRAAgK4QvTJgAFAQARAAgK4QvTJgAFAQAAAA==.Rago:BAAANQAECgcICwAAAA==.Rasz:BAABNQAECn82AAMLAAkKQxqBSQAAAgALAAkKQxqBSQAAAgAhAAYK4wzsSQARAQAAAA==.Rayjean:BAAANQADCgMIBQABNQAECgYIBgABAAAAAA==.',
Re='Regelia:BAAANQADCgcIBwAAAA==.Reider:BAAANQADCggIFwAAAA==.Relmax:BAABNQAECn8VAAIXAAkKvgUAIQC9AAAXAAkKvgUAIQC9AAAAAA==.Rennia:BAAANQAECgIIAgABNQAECggIEgABAAAAAA==.Renzu:BAAANQAECgEIAQAAAA==.',
Rh='Rhonwynn:BAABNQAECn8kAAIZAAgKuReXNAAZAgAZAAgKuReXNAAZAgAAAA==.',
Ri='Rikershipdwn:BAAANQAECggIDwAAAA==.Rimrave:BAABNQAECn8nAAMXAAgK7hidDwCDAQAXAAcKdBedDwCDAQAEAAgKNBA7hABGAQAAAA==.Ritobeans:BAAANQADCgcICgAAAA==.',
Rk='Rk:BAABNQAECn8hAAIdAAcK3AwBEQD4AAAdAAcK3AwBEQD4AAABNQAECgoKIwAaACsNAA==.',
Ro='Robertkenway:BAABNQAECn8sAAIlAAkK2wviBwDnAQAlAAkK2wviBwDnAQABNQAECgoKIwAaACsNAA==.Roberto:BAAANQADCggICgAAAA==.Rod:BAABNQAECn8nAAITAAoKCRM1GwDPAQATAAoKCRM1GwDPAQAAAA==.Rokte:BAABNQAECn8cAAIMAAoK4xJFBQD1AQAMAAoK4xJFBQD1AQABNQAECgoKHAAMAOMSAA==.Rollhots:BAAANQAECgYIDQAAAA==.Rook:BAABNQAECn8zAAMMAAoKHCNrAQBIAwAMAAoKZCFrAQBIAwAHAAQKxR4TbgBUAQAAAA==.Rooke:BAABNQAECn8fAAIEAAkKoRrEegAoAgAEAAkKoRrEegAoAgABNQAECgoKMwAMABwjAA==.Rorsh:BAAANQAECgQIBAAAAA==.Rosekenway:BAABNQAECn8jAAMaAAoKKw1dHgC9AQAaAAoKKw1dHgC9AQAWAAEKwwGOwgAfAAAAAA==.',
Rr='Rratt:BAAANQADCgcIDwAAAA==.',
Ru='Rubyknight:BAAANQADCgYICQAAAA==.Running:BAAANQAECgYIBgAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQAECgUIEAAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQICQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAABNQAECn8uAAMcAAkKiReNCQDMAQAcAAkKiReNCQDMAQAIAAEKHA5MRwE0AAAAAA==.',
Se='Sedrick:BAABNQAECn8qAAQDAAkKphR/wgCXAQADAAgKghJ/wgCXAQAYAAgKEBRxkgBnAQARAAQK2hRyMwC5AAAAAA==.Sekaholic:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekhmett:BAAANQADCgIIAgAAAA==.Sekndestroy:BAAANQAECgIIAgAAAA==.Seksational:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Sekthyr:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Sekzen:BAAANQADCgUJDgABNQAECgIIAgABAAAAAA==.',
Sh='Shamtune:BAACNQAFFH8NAAIZAAUK/BFUDgAwAQAZAAUK/BFUDgAwAQA1AAQKfyYAAxkACgoXFtBIAD8CABkACgoXFtBIAD8CAA0AAQqdDkEuAToAAAAA.Sharayman:BAAANQAECgYIBgAAAA==.Shattered:BAAANQAECgIIAwAAAA==.Shaydra:BAABNQAECn8mAAIKAAgKIBU3QwC3AQAKAAgKIBU3QwC3AQAAAA==.Shazool:BAABNQAECn80AAMZAAoKoyODCQB1AwAZAAoKoyODCQB1AwAeAAQK/gqTJwDqAAAAAA==.Shevee:BAAANQADCgEIAQAAAA==.Shifterz:BAAANQAECgUICgAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAABNQAECn8VAAIkAAkKhAxjKwA8AQAkAAkKhAxjKwA8AQAAAA==.',
Si='Siarra:BAAANQADCgMIAwAAAA==.Sind:BAAANQADCgIIAgABNQAECgUIDQABAAAAAA==.Sindella:BAAANQAECgUIDQAAAA==.Sindrè:BAAANQABCgUIBQABNQAECgUIDQABAAAAAA==.Sinna:BAAANQADCgYICgAAAA==.Sinpriest:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Sk='Skedaddle:BAAANQAECgQICwAAAA==.',
Sl='Slashgquit:BAABNQAECn8ZAAIgAAcKVCJCMABQAgAgAAcKVCJCMABQAgAAAA==.Slumbermist:BAABNQAECn8pAAIJAAgKghTsLACyAQAJAAgKghTsLACyAQABNQAECgEIAQABAAAAAA==.',
Sn='Snazzi:BAABNQAECn8dAAINAAgKBQuRfACuAQANAAgKBQuRfACuAQAAAA==.Snowtitan:BAAANQADCgUIBQAAAA==.',
So='Solam:BAAANQAECgMIAwAAAA==.',
Sp='Sploob:BAAANQADCgUIBQAAAA==.',
St='Stabbs:BAAANQADCggIDgAAAA==.Steph:BAAANQAECgIIAwAAAA==.Strawberyy:BAAANQAECgMIAwABNQAFFAYIDgAEAPQXAA==.Strongboy:BAAANQADCgUIBwAAAA==.Stx:BAAANQADCggICAABNQAECggIFAAlAN8PAA==.',
Su='Survival:BAAANQAECgIIAwAAAA==.',
Sy='Syndar:BAABNQAECn8lAAMNAAoKKx41KQDcAgANAAkKsh81KQDcAgAZAAIK1g9RugB3AAAAAA==.Synthetic:BAABNQAECn8fAAIGAAYKjg86DgDJAAAGAAYKjg86DgDJAAAAAA==.',
Sz='Szasstaam:BAAANQAECggIBAAAAA==.',
Ta='Talionsauron:BAAANQADCggIAgAAAA==.Tandá:BAAANQADCgMIAwABNQADCggICgABAAAAAA==.Tarnaris:BAAANQADCgIIAgAAAA==.Tattersaile:BAAANQADCgUIBwAAAA==.',
Te='Tecsaran:BAAANQAECgcICgABNQAECgoKJQANACseAA==.Tekis:BAAANQAECgQICQAAAA==.Tensanio:BAAANQAECgUIBQAAAA==.',
Th='Thalira:BAAANQAECggIEQAAAA==.Thalrix:BAABNQAECn8jAAIDAAoKyBIFXADjAQADAAoKyBIFXADjAQAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUJBwAAAA==.Thetowelie:BAAANQADCgMIAwAAAA==.Thickneck:BAAANQADCgUIBQAAAA==.',
Ti='Tieson:BAAANQAECgYICgAAAA==.Tinkera:BAAANQADCgcIEQAAAA==.Titanosaurus:BAAANQAECgIIAgAAAA==.',
To='Tomcruise:BAAANQABCgUICAABNQAECgIIAgABAAAAAA==.Torridwells:BAAANQAECgUICQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAABNQAECn8gAAIZAAYKGhdtVwCEAQAZAAYKGhdtVwCEAQAAAA==.Troagstar:BAABNQAECn8gAAINAAYKZRHAoABVAQANAAYKZRHAoABVAQAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAACNQAFFH8FAAIUAAQKWg88CwDfAAAUAAQKWg88CwDfAAA1AAQKfzIAAxQACgpVH8IPAIcCABQACgpVH8IPAIcCABsAAQoAAC1tADMAAAAA.Tyrmog:BAAANQADCggIFAAAAA==.Tytus:BAAANQABCgcIDwAAAA==.',
Un='Undetha:BAABNQAECn8XAAIgAAgK4BYgJwCaAQAgAAgK4BYgJwCaAQAAAA==.',
Us='Ushas:BAABNQAECn8uAAMOAAoKxBmnSQDYAQAOAAoKxBmnSQDYAQAPAAEKAAAZhAAlAAAAAA==.',
Va='Vaeiane:BAAANQAECggICQABNQAECggIEgABAAAAAA==.Vali:BAAANQADCgcIDQABNQAECgoKGwAQAA0WAA==.Valindrea:BAAANQAECgUIEAAAAA==.Vasrael:BAAANQAECgcIEQAAAA==.Vasrannah:BAAANQAECgUIBQAAAA==.',
Ve='Vel:BAABNQAECn83AAMbAAoKygvOGAC3AQAbAAoKygvOGAC3AQAVAAcKmQIXIQC7AAAAAA==.Velnie:BAAANQAECgMIBQAAAA==.Venvanse:BAAANQAECgEIAQAAAA==.Verq:BAAANQAECgEIAQAAAA==.Vexen:BAABNQAECn8cAAIbAAcKUBe9LQDUAQAbAAcKUBe9LQDUAQAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAACNQAFFH8GAAIbAAMK+wuuCwB9AAAbAAMK+wuuCwB9AAA1AAQKfzcAAxsACgqiG2cXAKMCABsACgqiG2cXAKMCABQABwp4DZRJAH8BAAAA.',
Vy='Vynis:BAAANQAFFAEIAQABNQAFFAUIDQAZAPwRAA==.Vyrahildard:BAABNQAECn8nAAIDAAgKChl2ggAjAgADAAgKChl2ggAjAgAAAA==.',
Wa='Wakkiq:BAAANQAECgEIAQAAAA==.Wasteland:BAABNQAECn9AAAIgAAoK6A18KgCGAQAgAAoK6A18KgCGAQAAAA==.Watermelon:BAACNQAFFH8JAAIZAAMKmRDEFADRAAAZAAMKmRDEFADRAAA1AAQKfzkAAxkACgreEYZZAAQCABkACgreEYZZAAQCAA0ABgoCFAxtAAcBAAE1AAUUBQgRABoA7g4A.',
We='Weaselhunter:BAABNQAECn8fAAILAAoKxCPdFQBEAwALAAoKxCPdFQBEAwAAAA==.Weasellock:BAABNQAECn8bAAIHAAcKKRWocQBLAQAHAAcKKRWocQBLAQABNQAECgoKHwALAMQjAA==.Weaselmage:BAABNQAECn8XAAMIAAcKhBBPwwD3AAAIAAcKJw1PwwD3AAAcAAIKoBp0PwBGAAABNQAECgoKHwALAMQjAA==.Weaselshammy:BAABNQAECn8ZAAINAAgKqBoNawDfAQANAAgKqBoNawDfAQABNQAECgoKHwALAMQjAA==.',
Wh='Whatthef:BAAANQADCgcIDwAAAA==.',
Wi='Wildweasel:BAAANQAECgUIDQABNQAECgoKHwALAMQjAA==.Willbarr:BAAANQAECgEIAQAAAA==.Winterhide:BAABNQAECn8ZAAMKAAcK8BFrRABHAQAfAAYKfxMRcQBRAQAKAAcKNQtrRABHAQAAAA==.Wishbone:BAABNQAECn8VAAIIAAgKZAsVowAyAQAIAAgKZAsVowAyAQAAAA==.',
Wo='Womamatoo:BAAANQADCgcICgAAAA==.',
Xa='Xallie:BAEANQAECgYIDgAAAA==.Xanvyr:BAAANQAECggIDAABNQAECgUICQABAAAAAA==.Xaquillis:BAABNQAECn8qAAIgAAoKJxCfMABhAQAgAAoKJxCfMABhAQAAAA==.Xaras:BAAANQADCgMIAwAAAA==.',
Xe='Xentrie:BAAANQAECgQIDAAAAA==.Xeyvara:BAABNQAECn8nAAIVAAgKNSK5BQAhAgAVAAgKNSK5BQAhAgAAAA==.',
Ya='Yah:BAAANQADCggIDQAAAA==.',
Za='Zaravalatha:BAAANQADCgUICQAAAA==.Zarihanna:BAABNQAECn83AAIIAAgKkBDPwAADAgAIAAgKkBDPwAADAgAAAA==.Zariia:BAAANQAECgEIBAAAAA==.Zarsiia:BAAANQAECgQIDgAAAA==.Zatima:BAAANQAECgUIBQAAAA==.',
Ze='Zernakk:BAAANQAECgUICgAAAA==.Zestdh:BAAANQAECgUIBwAAAA==.Zestyknight:BAAANQAECggIEQAAAA==.',
Zi='Zindeshal:BAAANQADCggIDQAAAA==.',
Zo='Zorcunter:BAABNQAECn81AAILAAoK+ySUDAARAwALAAoK+ySUDAARAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQAECgEIAQAAAA==.',
['Ðo']='Ðonjon:BAAANQAECgEIAgAAAA==.',
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
