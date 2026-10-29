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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Rogue-Assassination','Monk-Windwalker','DeathKnight-Frost','Hunter-BeastMastery','Mage-Arcane','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','Warrior-Protection','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Mage-Frost','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Hunter-Marksmanship','Priest-Discipline','Monk-Brewmaster','Druid-Guardian','Hunter-Survival','Monk-Mistweaver','DemonHunter-Devourer',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-10-27',data={Ak='Akaidia:BAAANQAECggICAABNQAECggIEQABAAAAAA==.',
Al='Alckmin:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAAANQAECgYIDwAAAA==.Allysaun:BAAANQAECgMIBQAAAA==.',
Am='Amaurra:BAAANQAECgEIAgAAAA==.Amorina:BAABNQAECn8YAAICAAoK0Q95uQCqAQACAAoK0Q95uQCqAQAAAA==.',
An='Ananth:BAAANQAECgEIAQAAAA==.Anda:BAAANQAECgEIAQAAAA==.Andill:BAAANQAECgQICAAAAA==.Andromeda:BAAANQAECgUICQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAACNQAFFH8NAAMDAAUKHRzhCwAHAQADAAQKHRzhCwAHAQAEAAEKAAAEBAAAAAA1AAQKfycAAgMACgpRHr5OAJ0CAAMACgpRHr5OAJ0CAAAA.Angrygnome:BAABNQAECn80AAMFAAoKTx9cAwAQAwAFAAoKLRtcAwAQAwAGAAoKRRs9EgCXAgAAAA==.Angélique:BAAANQAECgcIDAABNQAFFAUIDQADAB0cAA==.Anieros:BAAANQAECgEIAgABNQAFFAQICAAHAEwRAA==.',
Ar='Arai:BAAANQADCgIIAgAAAA==.Arax:BAAANQAECgQIBwAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAABNQAECn8VAAICAAcKVAetDQEIAQACAAcKVAetDQEIAQAAAA==.Armâgeddon:BAABNQAECn8kAAIDAAkKcyB+LAAKAwADAAkKcyB+LAAKAwAAAA==.Arrokoth:BAAANQAECgEIAQAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.',
As='Astyl:BAAANQADCgMIAgAAAA==.',
At='Athurnz:BAAANQAECgEIAQAAAA==.Atropós:BAAANQAECgYIEQAAAA==.Attachedplag:BAABNQAECn8YAAMDAAgK3AwyiwD6AAADAAgK3AwyiwD6AAAEAAEKPQb8NgArAAAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQAECgUIBwAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Baconhuntard:BAAANQAECgMIBAAAAA==.Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQAECgUIBwAAAA==.Banzen:BAAANQADCggIGwAAAA==.Battle:BAEANQADCgIIAgABNQAECgoKNAAIAAsfAA==.',
Be='Beardedyeti:BAAANQAECgEIAgAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAABNQAECn8rAAIJAAoKiRiGHADoAQAJAAoKiRiGHADoAQAAAA==.Bernese:BAAANQAECgcICgAAAA==.Berunma:BAABNQAECn8WAAIKAAgKYw23rgCnAQAKAAgKYw23rgCnAQAAAA==.',
Bh='Bhain:BAAANQAFFAQIBAAAAA==.',
Bi='Bileshots:BAAANQAECgYICwAAAA==.Biowolf:BAACNQAFFH8GAAILAAMKdQMUKQCOAAALAAMKdQMUKQCOAAA1AAQKfxoAAgsACQqwEeWyAB0CAAsACQqwEeWyAB0CAAAA.Birdhunter:BAAANQAECgYIBgAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgQIBAABAAAAAA==.Bishopxix:BAAANQAECgQIBAAAAA==.Bits:BAAANQAECgMIBgAAAA==.',
Bj='Bjoren:BAABNQAECn8vAAMMAAoKqSCIFwAaAwAMAAoKqSCIFwAaAwANAAEKAAADlwAKAAAAAA==.',
Bl='Blackki:BAAANQADCgQIBQAAAA==.Bloodbaron:BAAANQAECgIIAgABNQAECgcIGgAGAOsWAA==.',
Bo='Bootiebang:BAABNQAECn8gAAIOAAYK4AZ8MAA7AQAOAAYK4AZ8MAA7AQAAAA==.Bootieknight:BAAANQADCgcIBwAAAA==.Bootycaall:BAAANQADCgcIDgAAAA==.Boxxie:BAAANQADCgcIFQAAAA==.',
Br='Branches:BAAANQADCgMIAwAAAA==.Brockshot:BAAANQAECgEIBQAAAA==.',
Bu='Bucknekkid:BAAANQAECgUICQAAAA==.Buckwhild:BAABNQAECn8hAAMMAAoKChyxMwCZAgAMAAoKChyxMwCZAgANAAEKAADLigAfAAAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAABNQAECn88AAMPAAoKkB6+CwDdAgAPAAoKkB6+CwDdAgACAAUKnhSuywDJAAAAAA==.Canadaisheal:BAAANQAECgYIEQAAAA==.Catslol:BAAANQADCgIIAgAAAA==.',
Ce='Cerñuñños:BAAANQAECgIIAwAAAA==.Cesàrè:BAAANQAECgQIEgAAAA==.',
Ch='Chahra:BAAANQAECgUICQAAAA==.Chamuki:BAABNQAECn8UAAMQAAkKUxOCLAA7AQAQAAgKxBOCLAA7AQARAAEKOxBgMAA8AAABNQAFFAYIGgASAGUcAA==.Chuubak:BAAANQAECggIEAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAABNQAECn8UAAMEAAcKpw9gEQDUAAAEAAcKpw9gEQDUAAADAAUKgwZ1wwCFAAAAAA==.',
Co='Cocomami:BAAANQADCgUIBQAAAA==.Colonidus:BAAANQAECgQIBAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAABNQAECn8bAAITAAcKchNREAAyAQATAAcKchNREAAyAQAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAABNQAECn8oAAMDAAoKqBwNIQBtAgADAAoKqBwNIQBtAgAEAAQKWxiFHgDMAAAAAA==.',
Da='Dagby:BAAANQADCgcIGwAAAA==.Dandi:BAAANQAECgIIAwAAAA==.Daneaus:BAAANQAECgEIAQABNQAECggIIAAUAEskAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darkscorp:BAAANQADCgIIAgAAAA==.Darkwolf:BAAANQAECgQICAAAAA==.Darnuus:BAABNQAECn8sAAMVAAoKbh3jKADAAgAVAAoKbh3jKADAAgAWAAUK8Qm5hwCPAAAAAA==.Datnv:BAAANQADCggICAAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAABNQAECn8hAAMXAAgK1Aw6PgAyAQAXAAcKJQs6PgAyAQASAAcKwAaWcQADAQAAAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAABNQAECn8fAAIGAAkKKxcGLAABAgAGAAkKKxcGLAABAgAAAA==.Delai:BAAANQADCgMIAwAAAA==.Dellin:BAABNQAECn8fAAISAAgKlxYqIgBzAQASAAgKlxYqIgBzAQAAAA==.Demeco:BAEANQAECgUJCQABNQAFFAgIFAAUAOQZAA==.Demondots:BAAANQAECgUIBwAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Di='Diminuendo:BAAANQAECgIIAgAAAA==.Divertido:BAAANQAECgEIAQAAAA==.',
Do='Dogz:BAAANQAECgUIBgABNQAFFAcIHQAKAHIhAA==.Doozydruid:BAABNQAECn8UAAISAAcKeg/rVQCAAQASAAcKeg/rVQCAAQAAAA==.Dorozh:BAAANQAECgYIDwAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonstorm:BAAANQADCgQIBAAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAABNQAECn8eAAIMAAcK4xYpUABxAQAMAAcK4xYpUABxAQAAAA==.Dreadar:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.Dreadpally:BAAANQADCgYJCgABNQAECgEIAgABAAAAAA==.Dreco:BAAANQAECgUIEwAAAA==.Driver:BAEANQAECggICAAAAA==.Drtydhn:BAAANQABCgMIAwAAAA==.Druuzak:BAABNQAECn8mAAIYAAoKHQ7XDgC9AQAYAAoKHQ7XDgC9AQAAAA==.Dryconias:BAABNQAECn9AAAICAAoK4hqzQwDJAgACAAoK4hqzQwDJAgAAAA==.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duncanmcleod:BAABNQAECn8aAAIDAAkKZhZ6cgA9AgADAAkKZhZ6cgA9AgABNQAECgoKJgAMANQdAA==.Dunkelzhan:BAABNQAECn8iAAILAAgKBBT+1gDZAQALAAgKBBT+1gDZAQAAAA==.',
Dv='Dvldogma:BAAANQAECgUIDwAAAA==.',
Dy='Dyana:BAAANQAECgYIDwAAAA==.',
Dz='Dz:BAABNQAECn88AAMUAAoKniXFBACqAwAUAAoKniXFBACqAwACAAYKDA7I9AAzAQAAAA==.',
['Dø']='Dømimømmÿ:BAAANQAECgMIAwAAAA==.',
Ec='Ecobessie:BAAANQADCgcICwAAAA==.Ecowolf:BAAANQADCgYICgABNQADCgcICwABAAAAAA==.',
Ed='Edlund:BAABNQAECn8aAAIZAAgKTwmFCwAtAQAZAAgKTwmFCwAtAQAAAA==.',
El='Electricfun:BAAANQAECgMIAwAAAA==.Ellenaim:BAAANQAECgUICAAAAA==.Elvy:BAABNQAECn80AAISAAoKPxhwEwAWAgASAAoKPxhwEwAWAgAAAA==.',
En='Enngin:BAAANQAECgMIBAAAAA==.Enroks:BAABNQAECn80AAQWAAoKhxMxKQC+AQAWAAoKhxMxKQC+AQAVAAYKZhkdggCGAQAaAAEKAAARNwAzAAAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAABNQAECn8rAAMXAAgKOxSWHwBiAQAXAAgKOxSWHwBiAQASAAUKlwSchQC8AAAAAA==.Evangelina:BAAANQADCgEIAQAAAA==.',
Ex='Exsalsior:BAACNQAFFH8IAAMHAAQKTBGLAwDqAAAHAAMKTBGLAwDqAAAOAAEKAADZHAAAAAA1AAQKfxcAAgcACQr4E6g1AAICAAcACQr4E6g1AAICAAAA.',
Fa='Fabulousness:BAAANQAECgYICwAAAA==.Fathur:BAAANQAECgEIAQAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQAECgUIEgAAAA==.Furussy:BAAANQADCgcIBwAAAA==.Furytotem:BAAANQAECgEIAwABNQAECgEIAQABAAAAAA==.',
Ga='Galadhras:BAAANQADCgYIDAAAAA==.Galdryn:BAAANQABCgQIBQAAAA==.Gamboslice:BAABNQAECn8sAAIJAAoKyhWiIQC/AQAJAAoKyhWiIQC/AQAAAA==.Garkevon:BAABNQAECn8kAAMbAAkKQwZoLAAfAQAbAAkKQwZoLAAfAQAcAAIK8gH7wgBCAAAAAA==.',
Ge='Geoffana:BAAANQAECgEIAQAAAA==.Gevul:BAABNQAECn9UAAQGAAoKOhuaKwADAgAGAAkKkhuaKwADAgAFAAMK+hFKOQDbAAAdAAEKAADLMQAxAAAAAA==.',
Gh='Ghuun:BAABNQAECn8aAAIGAAcK6xb7WABYAQAGAAcK6xb7WABYAQAAAA==.',
Gl='Glep:BAAANQAECgEIAQAAAA==.Glimmervoid:BAAANQAECgQICQAAAA==.',
Go='Golland:BAAANQAECgEIAQABNQAECgoKMQAWAFIYAA==.Goob:BAAANQAECgEIAQAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAABNQAECn8XAAICAAgKjBVkiAAWAgACAAgKjBVkiAAWAgAAAA==.Grimero:BAAANQAECggIAgAAAA==.Groinsapper:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Grozny:BAAANQAECgEIAQABNQAECgYIHwAYAMsNAA==.',
Gs='Gsstuff:BAAANQADCgIIAgAAAA==.',
Gu='Gumboslice:BAACNQAFFH8HAAIXAAUKcBQUBwAKAQAXAAUKcBQUBwAKAQA1AAQKfzkAAxcACgrOHlIRAMkCABcACgrOHlIRAMkCABIAAQoAAEiCAAAAAAAA.Gumiho:BAAANQAECgYIEgAAAA==.Gusgus:BAABNQAECn8cAAIYAAcKGwwuEAAIAQAYAAcKGwwuEAAIAQAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAACNQAFFH8JAAIKAAQKkxGSEQBHAQAKAAQKkxGSEQBHAQA1AAQKfyUAAgoACgrAIZsTAFADAAoACgrAIZsTAFADAAAA.Habanero:BAABNQAECn8cAAIWAAkK7R5QHAAZAgAWAAkK7R5QHAAZAgAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQAECggIAgABNQAECggKLwAeAD0MAA==.Hammerfist:BAAANQAECgMIBQAAAA==.Hark:BAAANQADCgcIFgAAAA==.Haveabubble:BAAANQAECgEIAQABNQAECggIIAATAO4YAA==.',
He='Healvisprsly:BAAANQAECgEIAgAAAA==.Helena:BAABNQAECn8yAAMPAAoKJSEyBQC2AgAPAAoKJSEyBQC2AgACAAgKNhpecwBIAgAAAA==.Heliarc:BAAANQADCgcIHAAAAA==.',
Hi='Hidän:BAABNQAECn8bAAMGAAcKuwukvQBRAQAGAAcKuwukvQBRAQAFAAEKwgWSfgAuAAAAAA==.Himself:BAAANQAECgEIAQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.Hoomalu:BAAANQADCgIIAgAAAA==.',
Hu='Huund:BAAANQADCgUIBQAAAA==.Huutou:BAAANQADCgYICwAAAA==.',
Il='Illatix:BAAANQAECgQICQAAAA==.Illustriä:BAAANQAECgUIDwAAAA==.',
In='Insidious:BAABNQAECn8bAAIcAAcKlxxiMABQAgAcAAcKlxxiMABQAgAAAA==.',
Ir='Irs:BAAANQAECggIDAAAAA==.',
Is='Isisvane:BAAANQAECgEIAQAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECgkJKQAYADIfAA==.Itchymage:BAABNQAECn8pAAMYAAkKMh+jFQBTAQALAAkKxh2ghwBvAgAYAAQKEh2jFQBTAQAAAA==.',
Iv='Ivyrayne:BAAANQAECgEIAQAAAA==.',
Ja='Jaganash:BAAANQAECgQIBAABNQAECgYIEgABAAAAAA==.Jakeofny:BAAANQAECgYICwAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIEAAAAA==.',
Ji='Jighlipuff:BAABNQAECn8aAAICAAcKVwYgBQEXAQACAAcKVwYgBQEXAQAAAA==.Jigs:BAABNQAECn8qAAIKAAgKkAoDfwA1AQAKAAgKkAoDfwA1AQAAAA==.Jinxy:BAAANQADCggINwABNQAECgQICQABAAAAAA==.',
Ju='Judgements:BAAANQAECgQIBgAAAA==.Jug:BAAANQADCggIKQAAAA==.Jujutanketh:BAAANQAECgUIDgAAAA==.Junebugg:BAAANQAECgYIDgAAAA==.',
Ka='Kabøchi:BAABNQAECn8ZAAIIAAcKnA/uIAAfAQAIAAcKnA/uIAAfAQAAAA==.Kafia:BAAANQAECgUIBwAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQAECgYIDgAAAA==.Kanaloa:BAAANQAECgYICAAAAA==.Kaorin:BAAANQAECgEIAQABNQAECgoKNAAVAKMjAA==.Karindis:BAABNQAECn8vAAIRAAoKOyHlAwAYAwARAAoKOyHlAwAYAwAAAA==.Kathulhu:BAAANQAECgIIBAAAAA==.Kayler:BAAANQAECggIEQAAAA==.',
Ke='Kegerator:BAAANQADCgMIBAAAAA==.Keldica:BAABNQAECn8YAAIGAAoKxBaTHgBGAgAGAAoKxBaTHgBGAgABNQAECgoKIwAWACseAA==.Kenshan:BAAANQAECgEIAgAAAA==.',
Kh='Khalinor:BAABNQAECn8UAAIUAAgKGh50OACCAgAUAAgKGh50OACCAgAAAA==.Khotuhn:BAAANQAECgQIBAAAAA==.',
Ki='Kickazdin:BAABNQAECn8vAAMUAAoKyx7hKADFAgAUAAkKOx/hKADFAgACAAEKAABNngE4AAAAAA==.Killadragon:BAAANQAECgUIBQAAAA==.Kiryie:BAAANQAECgUIBgAAAA==.Kitinna:BAABNQAECn8UAAMLAAcKZAMtxADCAAALAAcK4AItxADCAAAYAAEKXAQLUQAlAAAAAA==.',
Kl='Klaw:BAAANQADCgYIEAAAAA==.',
Ko='Korraa:BAABNQAECn8iAAMVAAkKUhxfTwAnAgAVAAkKUhxfTwAnAgAWAAUKVhGqsQAvAQAAAA==.',
Kp='Kprist:BAAANQAECgUIDQAAAA==.',
Kr='Kraigen:BAAANQAECgYIDQAAAA==.',
Ku='Kunzhut:BAABNQAECn8eAAMbAAgKIhWnVQC7AQAbAAgKIhWnVQC7AQAJAAQKsQiJZQCPAAAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgcIEwAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Laeli:BAAANQAECgQICQAAAA==.Lailyre:BAAANQAECggIBwABNQAECggIEQABAAAAAA==.Laydin:BAABNQAECn8gAAIKAAgKIwVdAAEEAQAKAAgKIwVdAAEEAQABNQAECggIIQAXANQMAA==.',
Lb='Lb:BAABNQAECn8kAAMKAAoKNhp0KgA3AgAKAAoKNhp0KgA3AgAeAAUKcAsxSwAJAQAAAA==.',
Le='Legzanot:BAABNQAECn8+AAIWAAoKERWaHAAXAgAWAAoKERWaHAAXAgAAAA==.Lestrade:BAABNQAECn8jAAIcAAkKgQ+tJgBjAQAcAAkKgQ+tJgBjAQABNQAECgoKLAAVAG4dAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAABNQAECn8hAAMCAAcKchVOkQAvAQACAAcKchVOkQAvAQAUAAMKigzlBAFvAAAAAA==.Lightsfallen:BAABNQAECn8mAAMMAAoK1B1/DAAbAwAMAAoK1B1/DAAbAwAfAAEKuwa4LQApAAAAAA==.Lithia:BAAANQAECgUICAAAAA==.Littlemo:BAAANQAECgUIEgAAAA==.',
Lo='Lohnar:BAAANQAECgUIEgAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgcIEgAAAA==.Lucielbaal:BAABNQAECn8dAAIGAAgKFRiLSgCFAQAGAAgKFRiLSgCFAQAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQAECgIIAwAAAA==.Lunareth:BAAANQAECgYIEgABNQAECgYIHwAYAMsNAA==.',
Ly='Lyrska:BAAANQAECgUIEgAAAA==.Lytearrow:BAABNQAECn8YAAIKAAgK+Qn+kQDlAQAKAAgK+Qn+kQDlAQAAAA==.',
['Lì']='Lìvíd:BAAANQAECgUIEAAAAA==.',
Ma='Mahrylee:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgUICQAAAA==.Makbeard:BAAANQADCgYIBgABNQAECgcIDwABAAAAAA==.Makmobius:BAAANQAECgcIDwAAAA==.Manbearpally:BAAANQAECgEIAgAAAA==.Mannypack:BAAANQAECgUICwAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgcIFwABAAAAAA==.Mathau:BAAANQADCgcIFwAAAA==.Maztrix:BAAANQAECgIIAwAAAA==.',
Mc='Mcleary:BAAANQAECgQIEAAAAA==.',
Me='Meistro:BAAANQAECgEIAQAAAA==.Meldrus:BAABNQAECn8XAAIGAAgK/gnsmQCmAQAGAAgK/gnsmQCmAQAAAA==.Mending:BAAANQAECgcICgAAAA==.',
Mi='Miala:BAAANQAECgIIBgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAABNQAECn8gAAIVAAgKbSCtMwCRAgAVAAgKbSCtMwCRAgAAAA==.Miler:BAAANQAECgUICgAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAABNQAECn8dAAIXAAYKCCQfGgBpAgAXAAYKCCQfGgBpAgAAAA==.Mogryn:BAABNQAECn8bAAIKAAgK8ReyUQCnAQAKAAgK8ReyUQCnAQAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moondog:BAAANQAECgEIAgAAAA==.Moonwarriorx:BAAANQAECggIDgAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQAECgMIBgABNQAECgEIAQABAAAAAA==.Morthok:BAAANQAECgYIEAAAAA==.Mosh:BAABNQAECn8jAAIgAAcK8xyEBwB7AQAgAAcK8xyEBwB7AQAAAA==.',
Mu='Muskelunge:BAAANQAECgEIAwAAAA==.Mustachekick:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAABNQAECn8gAAIKAAgK+RejcwApAgAKAAgK+RejcwApAgAAAA==.Nafir:BAAANQAECgEIAQAAAA==.Nakky:BAAANQADCggICwAAAA==.Naritra:BAAANQAECggIAgABNQAECggIEQABAAAAAA==.Nazgor:BAABNQAECn8fAAIbAAoKVhwEEAAgAgAbAAoKVhwEEAAgAgAAAA==.',
Ne='Necrodragon:BAAANQADCgMIBgAAAA==.Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQAECgEIAwAAAA==.Newwt:BAAANQADCgcIBwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQAECgUICQAAAA==.',
Oa='Oath:BAAANQAECgYIEgAAAA==.',
Ob='Obscyra:BAABNQAECn8fAAIYAAYKyw2RGAAzAQAYAAYKyw2RGAAzAQAAAA==.',
Oc='Ochiie:BAAANQAECgQIAwAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddsham:BAAANQADCgUIBgAAAA==.Oddyeppyep:BAAANQAECgEIAgAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Og='Oghamm:BAAANQAECgEIAQAAAA==.',
Ol='Olmek:BAACNQAFFH8KAAMDAAUK2wYKGwA8AQADAAUK2wYKGwA8AQAEAAEK7AnzBgA9AAA1AAQKf0YAAwMACgqRIA0hADQDAAMACgqRIA0hADQDAAQABAruD+IeAMgAAAAA.',
Oo='Oochie:BAABNQAECn8lAAIMAAkK7AtoPwC3AQAMAAkK7AtoPwC3AQAAAA==.Oochiee:BAAANQAECgQIBQAAAA==.Oochiië:BAAANQAECgEIAQAAAA==.',
Op='Oprahwndfury:BAAANQAECgEIBgABNQAECgEIAgABAAAAAA==.',
Pa='Palanoris:BAAANQABCggIGwAAAA==.Palasades:BAAANQAECgUIDgAAAA==.Palelore:BAAANQAECgEIBQAAAA==.Pallydussy:BAAANQAECgMIAwAAAA==.Pallymarc:BAAANQADCgQIBAAAAA==.Pandalorian:BAABNQAECn8mAAIMAAoKLxUYSgBHAgAMAAoKLxUYSgBHAgAAAA==.Papapumpies:BAABNQAECn82AAIDAAoK6yLJLAAJAwADAAoK6yLJLAAJAwAAAA==.Parlow:BAAANQAECgEIAQAAAA==.Pazzo:BAAANQAECgUICAAAAA==.',
Ph='Pharaa:BAABNQAECn8cAAINAAcKOgaJJwDLAAANAAcKOgaJJwDLAAAAAA==.Philandre:BAAANQAECgQIBAAAAA==.',
Pi='Picoso:BAAANQAECgYIDwAAAA==.Piianna:BAABNQAECn8vAAIMAAoKJBhCLwCrAgAMAAoKJBhCLwCrAgAAAA==.Pizzaroll:BAABNQAECn8qAAIhAAoKOR/WCADrAgAhAAoKOR/WCADrAgAAAA==.',
Po='Pomégranate:BAAANQADCggICgAAAA==.',
Pu='Puckster:BAAANQAECgQICQAAAA==.',
['Pø']='Pøwe:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.',
Qa='Qatbarph:BAAANQAECgYIEgAAAA==.',
Qi='Qikkaw:BAABNQAECn8cAAMVAAYKdBS+mgBEAQAVAAYKdBS+mgBEAQAWAAYKwwcWkAB9AAAAAA==.',
Qu='Quantos:BAABNQAECn8eAAIhAAcK2RG9HAAkAQAhAAcK2RG9HAAkAQAAAA==.',
Ra='Raatha:BAABNQAECn8fAAICAAgK9hnVYACYAQACAAgK9hnVYACYAQAAAA==.Raganar:BAABNQAECn8kAAIPAAcKkwyhIwDhAAAPAAcKkwyhIwDhAAAAAA==.Rago:BAAANQAECgcIDAAAAA==.Rasz:BAABNQAECn8uAAMKAAgKDBoRRgDNAQAKAAgKDBoRRgDNAQAeAAYK4wzsSQARAQAAAA==.Rayjean:BAAANQADCgMIAwABNQADCgcIGQABAAAAAA==.',
Re='Regelia:BAAANQADCgcIBwAAAA==.Reider:BAAANQADCggIFwAAAA==.Relmax:BAAANQAECggIDwAAAA==.Rennia:BAAANQAECgIIAgABNQAECggIEQABAAAAAA==.Renzu:BAAANQAECgEIAQAAAA==.',
Rh='Rhonwynn:BAABNQAECn8dAAIVAAcKnRf0MgDUAQAVAAcKnRf0MgDUAQAAAA==.',
Ri='Rikershipdwn:BAAANQAECgUICwAAAA==.Rimrave:BAABNQAECn8gAAMTAAgK7hi+CgCWAQATAAcKdBe+CgCWAQADAAgKrA1QwgB3AQAAAA==.Ritobeans:BAAANQADCgcICgAAAA==.',
Rk='Rk:BAABNQAECn8hAAIZAAcK3AyqDQD/AAAZAAcK3AyqDQD/AAABNQAECgkJJgAiANsLAA==.',
Ro='Robertkenway:BAABNQAECn8mAAIiAAkK2wviBwDnAQAiAAkK2wviBwDnAQAAAA==.Roberto:BAAANQADCggICgAAAA==.Rod:BAABNQAECn8nAAIjAAoKCRM1GwDPAQAjAAoKCRM1GwDPAQAAAA==.Rokte:BAABNQAECn8VAAIdAAoK8g8zBADAAQAdAAoK8g8zBADAAQAAAA==.Rollhots:BAAANQAECgYIDQAAAA==.Rook:BAABNQAECn8pAAMdAAoKDyJrAQBIAwAdAAoKkx9rAQBIAwAGAAQKxR7bUwBnAQAAAA==.Rooke:BAABNQAECn8fAAIDAAkKoRrEegAoAgADAAkKoRrEegAoAgABNQAECgoKKQAdAA8iAA==.Rorsh:BAAANQAECgQIBAAAAA==.Rosekenway:BAABNQAECn8fAAMXAAgK+wwdHwBmAQAXAAgK+wwdHwBmAQASAAEKwwGOwgAfAAABNQAECgkJJgAiANsLAA==.',
Rr='Rratt:BAAANQAECgEIAgAAAA==.',
Ru='Rubyknight:BAAANQADCgMIAwAAAA==.Running:BAAANQAECgUIBQAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQAECgUIEgAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQICgAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAABNQAECn8mAAMYAAgKhhgNDgDMAQAYAAgKhhgNDgDMAQALAAEKHA5ILQE0AAAAAA==.',
Se='Sedrick:BAABNQAECn8kAAMCAAkKNxR/wgCXAQACAAcKBhJ/wgCXAQAUAAgKahNxkgBnAQAAAA==.Sekaholic:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekhmett:BAAANQADCgIIAgAAAA==.Sekndestroy:BAAANQAECgIIAgAAAA==.Seksational:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Sekthyr:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Sekzen:BAAANQADCgUJDgABNQAECgIIAgABAAAAAA==.',
Sh='Shamtune:BAACNQAFFH8JAAIVAAMK/xCIGQDPAAAVAAMK/xCIGQDPAAA1AAQKfyUAAxUACgoXFtBIAD8CABUACgoXFtBIAD8CABYAAQqdDkEuAToAAAAA.Sharayman:BAAANQADCgcIGQAAAA==.Shattered:BAAANQADCgYICQAAAA==.Shaydra:BAABNQAECn8hAAIJAAgKIBU3QwC3AQAJAAgKIBU3QwC3AQAAAA==.Shazool:BAABNQAECn80AAMVAAoKoyODCQB1AwAVAAoKoyODCQB1AwAaAAQK/gqTJwDqAAAAAA==.Shevee:BAAANQADCgEIAQAAAA==.Shifterz:BAAANQAECgUICgAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAAANQAECgYIDwAAAA==.',
Si='Siarra:BAAANQADCgMIAwAAAA==.Sind:BAAANQADCgIIAgABNQAECgUIDQABAAAAAA==.Sindella:BAAANQAECgUIDQAAAA==.Sindrè:BAAANQABCgUIBQABNQAECgUIDQABAAAAAA==.Sinna:BAAANQAECgEIAgAAAA==.Sinpriest:BAAANQAECgIIAwABNQAECgMIBQABAAAAAA==.',
Sk='Skedaddle:BAAANQAECgQICgAAAA==.',
Sl='Slashgquit:BAABNQAECn8ZAAIcAAcKVCJCMABQAgAcAAcKVCJCMABQAgAAAA==.Slumbermist:BAABNQAECn8lAAIIAAgKghTsLACyAQAIAAgKghTsLACyAQABNQAECgEIAQABAAAAAA==.',
Sn='Snazzi:BAABNQAECn8ZAAIWAAgKpwqRfACuAQAWAAgKpwqRfACuAQAAAA==.Snowtitan:BAAANQADCgUIBQAAAA==.',
So='Solam:BAAANQAECgMIAwAAAA==.',
Sp='Sploob:BAAANQADCgUIBQAAAA==.',
St='Stabbs:BAAANQADCggIDgAAAA==.Strawberyy:BAAANQAECgEIAgABNQAFFAUIDQADAB0cAA==.Strongboy:BAAANQADCgUIBwAAAA==.Stx:BAAANQADCggICAABNQAECggIFAAiAN8PAA==.',
Su='Survival:BAAANQAECgEIAQAAAA==.',
Sy='Syndar:BAABNQAECn8jAAMWAAoKKx41KQDcAgAWAAkKsh81KQDcAgAVAAEKnhwMtQBRAAAAAA==.Synthetic:BAABNQAECn8ZAAIFAAYK2Q0kDAC+AAAFAAYK2Q0kDAC+AAAAAA==.',
Sz='Szasstaam:BAAANQAECggIBgAAAA==.',
Ta='Talionsauron:BAAANQADCggIAgAAAA==.Tandá:BAAANQADCgMIAwABNQADCggICgABAAAAAA==.Tarnaris:BAAANQADCgIIAgAAAA==.Tattersaile:BAAANQADCgUIBwAAAA==.',
Te='Tecsaran:BAAANQAECgYIDAABNQAECgoKIwAWACseAA==.Tekis:BAAANQAECgQIEAAAAA==.Tensanio:BAAANQAECgUIBgAAAA==.',
Th='Thalira:BAAANQAECgYIDQAAAA==.Thalrix:BAABNQAECn8cAAICAAoK9hDTUADDAQACAAoK9hDTUADDAQAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUJBwAAAA==.Thetowelie:BAAANQAECgEIAQAAAA==.Thickneck:BAAANQADCgUIBQAAAA==.',
Ti='Tieson:BAAANQAECgEIBwAAAA==.Tinkera:BAAANQADCgcIEQAAAA==.Titanosaurus:BAAANQAECgIIAgAAAA==.',
To='Tomcruise:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Torridwells:BAAANQAECgUICQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAABNQAECn8aAAIVAAYKRhQxUQBSAQAVAAYKRhQxUQBSAQAAAA==.Troagstar:BAABNQAECn8aAAIWAAYK/xDAoABVAQAWAAYK/xDAoABVAQAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAABNQAECn8wAAMQAAoKVR9+CgCnAgAQAAoKVR9+CgCnAgAkAAEKAAAtbQAzAAAAAA==.Tyrmog:BAAANQAECgEIAQAAAA==.Tytus:BAAANQAECgEIAQAAAA==.',
Un='Undetha:BAAANQAECgcIEAAAAA==.',
Us='Ushas:BAABNQAECn8pAAMMAAkKzRjdVAAkAgAMAAkKzRjdVAAkAgANAAEKAAAZhAAlAAAAAA==.',
Va='Vaeiane:BAAANQAECggICQABNQAECggIEQABAAAAAA==.Vali:BAAANQADCgcIDQABNQAECgYIEgABAAAAAA==.Valindrea:BAAANQAECgUIEgAAAA==.Vasrael:BAAANQAECgYIDwAAAA==.',
Ve='Vel:BAABNQAECn8uAAMkAAoKAAsnFACrAQAkAAoKAAsnFACrAQARAAcKmQI/FwB9AAAAAA==.Velnie:BAAANQAECgMIBQAAAA==.Venvanse:BAAANQAECgEIAQABNQAECgoKIAALAJkMAA==.Verq:BAAANQAECgEIAQAAAA==.Vexen:BAABNQAECn8cAAIkAAcKUBe9LQDUAQAkAAcKUBe9LQDUAQAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAABNQAECn8zAAMkAAoKohtnFwCjAgAkAAoKohtnFwCjAgAQAAcKeA2USQB/AQAAAA==.',
Vy='Vynis:BAAANQAFFAEIAQABNQAFFAMICQAVAP8QAA==.Vyrahildard:BAABNQAECn8gAAICAAgKChl2ggAjAgACAAgKChl2ggAjAgAAAA==.',
Wa='Wakkiq:BAAANQAECgEIAQAAAA==.Wasteland:BAABNQAECn84AAIcAAoKhAxRJgBlAQAcAAoKhAxRJgBlAQAAAA==.Watermelon:BAACNQAFFH8GAAIVAAMKuQ3hEADQAAAVAAMKuQ3hEADQAAA1AAQKfy8AAxUACgreEYZZAAQCABUACgreEYZZAAQCABYABAokAkYCAYsAAAE1AAUUBQgNABcAgAoA.',
We='Weaselhunter:BAABNQAECn8ZAAIKAAoKOyPdFQBEAwAKAAoKOyPdFQBEAwAAAA==.Weasellock:BAABNQAECn8VAAIGAAcKTRG0dgAMAQAGAAcKTRG0dgAMAQABNQAECgoKGQAKADsjAA==.Weaselmage:BAAANQAECgMIEQABNQAECgoKGQAKADsjAA==.Weaselshammy:BAAANQAECgUIEwABNQAECgoKGQAKADsjAA==.',
Wh='Whatthef:BAAANQADCgcIDwAAAA==.',
Wi='Wildweasel:BAAANQAECgQICQABNQAECgoKGQAKADsjAA==.Willbarr:BAAANQAECgEIAQAAAA==.Winterhide:BAAANQAECgYIEgAAAA==.Wishbone:BAAANQAECgQIEQAAAA==.',
Wo='Womamatoo:BAAANQADCgcICgAAAA==.',
Xa='Xallie:BAEANQAECgYIEAAAAA==.Xanvyr:BAAANQAECgQICQABNQAECgUICwABAAAAAA==.Xaquillis:BAABNQAECn8mAAIcAAoK+A4fKABZAQAcAAoK+A4fKABZAQAAAA==.Xaras:BAAANQADCgMIAwAAAA==.',
Xe='Xentrie:BAAANQAECgUICAAAAA==.Xeyvara:BAABNQAECn8gAAIRAAgKyyAABQDtAQARAAgKyyAABQDtAQAAAA==.',
Ya='Yah:BAAANQADCggICwAAAA==.',
Za='Zaravalatha:BAAANQAECgEIAQAAAA==.Zarihanna:BAABNQAECn83AAILAAgKkBDPwAADAgALAAgKkBDPwAADAgAAAA==.Zariia:BAAANQAECgEIAQAAAA==.Zarsiia:BAAANQAECgQIEgAAAA==.Zatima:BAAANQAECgUIBQAAAA==.',
Ze='Zernakk:BAAANQAECgUIDAAAAA==.Zestdh:BAAANQAECgUIBwAAAA==.Zestyknight:BAAANQAECgUIBwAAAA==.',
Zi='Zindeshal:BAAANQADCgcICwAAAA==.',
Zo='Zorcunter:BAABNQAECn8sAAIKAAoK+yTbEwBPAwAKAAoK+yTbEwBPAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBgAAAA==.',
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
