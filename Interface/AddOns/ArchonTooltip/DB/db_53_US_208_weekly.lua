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

local lookup = {'Rogue-Subtlety','Druid-Restoration','Druid-Guardian','Druid-Feral','Rogue-Assassination','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','Mage-Arcane','DeathKnight-Blood','Warlock-Demonology','Mage-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Arms','Priest-Holy','Priest-Shadow','Monk-Windwalker','Paladin-Protection','Druid-Balance','Warlock-Destruction','Hunter-Survival','DeathKnight-Frost','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Priest-Discipline','Monk-Mistweaver','Warlock-Affliction','Warrior-Fury','Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aanna:BAAANQAECggICwAAAA==.',
Ab='Abandonedcat:BAAANQAECggIDAABNQAECgoKNQABANMjAA==.Abor:BAABNQAECn8gAAQCAAoK/QNLQQAdAQACAAoK/QNLQQAdAQADAAoKDAcsLgAKAQAEAAMKSgq2LwCUAAAAAA==.Abuela:BAABNQAECn85AAMFAAoKRh5sDQAZAwAFAAoKvxxsDQAZAwABAAkKSRg8MAAoAgAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ad='Adaela:BAAANQADCgIIAgABNQAECgoKNQAFAIkhAA==.',
Ae='Aegla:BAABNQAECn8zAAIGAAkKvxYtIwCyAQAGAAkKvxYtIwCyAQAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ag='Aghlath:BAAANQAECgYICAAAAA==.',
Ak='Akiko:BAAANQAECgYIDQABNQAECgoKOAAHAGodAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFH8RAAIIAAUKZA9XDQDyAAAIAAUKZA9XDQDyAAA1AAQKfzYAAwgACgoRGz0NANICAAgACgoRGz0NANICAAkAAQruCHglAC8AAAAA.Alliar:BAABNQAECn8uAAMKAAoKFh0nKwC2AgAKAAoKFh0nKwC2AgALAAYKPwl5rAA7AQAAAA==.Allynstraza:BAABNQAECn8VAAIIAAYKARClKgBYAQAIAAYKARClKgBYAQAAAA==.',
Am='Amgems:BAAANQAECgQIBQABNQAECgcIDQAMAAAAAA==.Amordred:BAABNQAECn8XAAIFAAYKQQbEOwCXAAAFAAYKQQbEOwCXAAAAAA==.',
An='Anasterion:BAABNQAECn8VAAINAAgK8CAlbgBUAgANAAgK8CAlbgBUAgAAAA==.Andarus:BAABNQAECn8hAAINAAcKuhrYgwCwAQANAAcKuhrYgwCwAQABNQAFFAMIBgAOAFEQAA==.Ankles:BAABNQAECn8nAAMPAAkKfiPRBwB/AwAPAAkKfiPRBwB/AwAGAAIK+glCzwBPAAAAAA==.Ansley:BAAANQADCgUICAABNQAECgoKNQAFAIkhAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgYICwABNQAECgoKSwAQAK0fAA==.',
As='Ashli:BAABNQAECn81AAMFAAoKiSEUBADpAgAFAAoKiSEUBADpAgABAAgKDBivNQAQAgAAAA==.Astiri:BAACNQAFFH8HAAIRAAYKLRNOAQAtAQARAAYKLRNOAQAtAQA1AAQKfxsAAhEACgo8IDcCAPkCABEACgo8IDcCAPkCAAAA.',
At='Atlasbär:BAAANQAECgUIBAABNQAECggICAAMAAAAAA==.Atlasdark:BAABNQAECn8ZAAIKAAoKPxznMwA3AgAKAAoKPxznMwA3AgABNQAECggICAAMAAAAAA==.Atlasfallen:BAAANQAECggICAAAAA==.Atreyu:BAAANQAECgYIBgAAAA==.',
Ba='Balrock:BAAANQAECgIIBQAAAA==.Balthromaw:BAABNQAECn87AAIQAAoKVhuPIQB/AgAQAAoKVhuPIQB/AgAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQAMAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECgYIBwABNQAFFAMIBQASAIoKAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belfdelphine:BAAANQAECgcIBgAAAA==.Bellum:BAAANQAECgcIEAAAAA==.Belstab:BAABNQAECn8tAAMBAAgK/g/XGwD3AQABAAgKhw/XGwD3AQAFAAcKcwkNTgCHAQABNQAFFAQICwAGADwEAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIEAABNQAECgoKJwATADEkAQ==.',
Bg='Bgbalkoth:BAAANQADCgYIDAAAAA==.',
Bi='Bifurthegrey:BAAANQAECgUIBAAAAA==.Bigblammy:BAAANQADCggICAABNQAFFAcIGQAOACAfAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQABNQAECgYIEAAMAAAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Blinkss:BAAANQAECgYIBgAAAA==.Bloodavenger:BAABNQAECn8dAAMHAAkKZgx0ZgDkAQAHAAkKZgx0ZgDkAQANAAUK9wb3KgHZAAAAAA==.Bloodemongar:BAABNQAECn8WAAIGAAkKvg5RZgB3AQAGAAkKvg5RZgB3AQAAAA==.Bloodhoundss:BAABNQAECn8kAAIUAAoK4xV4UgD0AQAUAAoK4xV4UgD0AQAAAA==.Blössöm:BAAANQAECgYIDAAAAA==.',
Bo='Bobdk:BAACNQAFFH8eAAMGAAcKvBwFBAD0AQAGAAcKvBwFBAD0AQAPAAEKAADsOAAgAAA1AAQKf0EAAgYACgp+JMYGAAEDAAYACgp+JMYGAAEDAAAA.Bomboklaat:BAAANQADCgMIBgAAAA==.Bonejangles:BAAANQAECgYIDAAAAA==.Boomfrin:BAAANQAECgUICgAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECn8lAAMVAAkK6BA6WQAWAgAVAAkK6BA6WQAWAgAWAAEKXAWlewAxAAAAAA==.',
Br='Braegen:BAABNQAECn8jAAMTAAkKuBWNRAA3AgATAAkKuBWNRAA3AgASAAEKPgYYZAAyAAABNQAFFAMIBgAOAFEQAA==.Brewslee:BAAANQADCggICAAAAA==.Brewsleê:BAAANQAECgQIBAAAAA==.Bruceleett:BAABNQAECn8/AAIXAAkKjRIGGQDRAQAXAAkKjRIGGQDRAQABNQADCgcIFwAMAAAAAA==.',
Bu='Buffmeister:BAAANQAECgUIBQAAAA==.Bullioss:BAABNQAECn8YAAMNAAgKlxnIhgCqAQANAAcKlxnIhgCqAQAYAAMKGxj2RQDYAAABNQAECgoKJwATADEkAA==.',
['Bà']='Bàtman:BAAANQADCgcIDAAAAA==.',
['Bö']='Böbbyboucher:BAABNQAECn8lAAILAAoKUhy0PwB2AgALAAoKUhy0PwB2AgAAAA==.',
Ca='Cainn:BAAANQADCggIEwABNQAECgoKLgANAP8XAA==.Caldrid:BAAANQADCgYIDwAAAA==.Calfurion:BAABNQAECn8VAAMEAAgKqB3zEAD4AQAZAAcKShxEPwAAAgAEAAYK1B7zEAD4AQAAAA==.Calvary:BAAANQAECggIDgABNQAECggIFQAEAKgdAA==.Capncrunch:BAAANQADCgYICwAAAA==.Cazleah:BAABNQAECn84AAILAAoKkyEOGQAzAwALAAoKkyEOGQAzAwAAAA==.',
Ce='Cessatio:BAABNQAECn8pAAIaAAoKFwvhBgBXAQAaAAoKFwvhBgBXAQAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAABNQAECn8tAAINAAoKYhvYXAAJAgANAAoKYhvYXAAJAgABNQAECgoKUwABAM8gAA==.Chowming:BAAANQABCgEIAQAAAA==.Chrisbrewn:BAABNQAECn8kAAIUAAkKzhMkcgA+AgAUAAkKzhMkcgA+AgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clamsweat:BAAANQABCgIIAgAAAA==.Clevelandoe:BAACNQAFFH8FAAISAAMKigoPGQC5AAASAAMKigoPGQC5AAA1AAQKfzkAAxIACQpIJGEOAPwCABIACQq6IWEOAPwCABMABQoUHMKnALYBAAAA.',
Co='Cobbknob:BAAANQAECgUIBwAAAA==.Cocobear:BAAANQAECgEIAQAAAA==.Coeurdeleon:BAABNQAECn8dAAMNAAoKTxTxhAAeAgANAAoKTxTxhAAeAgAYAAEKAAC2ZgBHAAAAAA==.Cokakilla:BAAANQADCggIDAAAAA==.Condemnation:BAABNQAECn9BAAIVAAoKyBnFOACFAgAVAAoKyBnFOACFAgAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgYICgABNQADCggIDQAMAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQAMAAAAAA==.Coriantumr:BAAANQADCgYIBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQAECgQIBQAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbstomped:BAABNQAECn8sAAQTAAoKjBQzbwAzAgATAAoKjBQzbwAzAgASAAUKLwmDMADZAAAbAAEKAADvFQAAAAAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgcIEAABNQAFFAgIFQAOALEdAA==.Darkvizzy:BAABNQAECn9EAAQGAAoKnh1SFwAfAgAGAAkKsR1SFwAfAgAPAAkKVhHkMAB7AQAcAAQKQg5oiQB+AAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgYIBwAAAA==.Demiplo:BAABNQAECn8oAAITAAkKyBSFegAZAgATAAkKyBSFegAZAgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQAMAAAAAA==.Denelak:BAABNQAECn8hAAMTAAoKZx8QEgBYAwATAAoK2x0QEgBYAwASAAkKcxcqGQCOAgAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAABNQAECn8WAAIOAAoKThe+tgAWAgAOAAoKThe+tgAWAgABNQAECgoKOQAFAEYeAA==.',
Di='Dirtycasual:BAAANQAECggIDgABNQAECgoKOQAFAEYeAA==.Discipline:BAABNQAECn8+AAMYAAoKTh0ODABdAgAYAAoKTh0ODABdAgANAAgKchU8mQDxAQAAAA==.',
Do='Doggo:BAAANQAECgEIAQAAAA==.Dotsurdead:BAAANQAECggICwAAAA==.',
Dr='Dratr:BAABNQAECn8xAAIdAAoKng05FQCnAQAdAAoKng05FQCnAQAAAA==.Draxyl:BAACNQAFFH8GAAMPAAIKSAbxIABXAAAPAAIKSAbxIABXAAAGAAEKnAClJgAsAAA1AAQKfzkAAw8ACgp2F0wzAG4BAAYACQokD9pKAOoBAA8ACgoCFkwzAG4BAAAA.Drekhan:BAABNQAECn8YAAMPAAYKyQMeYgCxAAAPAAYKyQMeYgCxAAAcAAQK2wL1mQBgAAABNQAFFAMIBgAOAFEQAA==.Drfizzle:BAAANQAECgEIAQABNQAECgoKMAAUAAsgAA==.Drham:BAABNQAECn8kAAIeAAkKJQ4vKQD6AQAeAAkKJQ4vKQD6AQAAAA==.Drogbar:BAAANQAECgEIAQABNQAECgkJIwAXAO4VAA==.Drokos:BAAANQAECgYIBwABNQAECgoKJwATADEkAA==.Drtree:BAAANQADCgcIBwAAAA==.Druni:BAAANQADCgEIAQAAAA==.',
Du='Dunhambones:BAABNQAECn83AAIGAAoK4yEbEQAuAwAGAAoK4yEbEQAuAwAAAA==.Duo:BAABNQAECn82AAIfAAoKExTSAQBwAgAfAAoKExTSAQBwAgABNQAECgoKIAACAP0DAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Elcosote:BAAANQAECgUICgAAAA==.Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQAECgYICQAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECn8+AAQVAAoK+hKwYwD1AQAVAAoK+hKwYwD1AQAWAAIK6QGceQA1AAAgAAEK/gUdKQAyAAAAAA==.Elrey:BAAANQAECggIBwABNQAECgoKOQAFAEYeAA==.Elèctra:BAAANQAECggIEQAAAA==.',
En='Enochs:BAAANQADCgIIAgAAAA==.Enyô:BAAANQADCgQIBAABNQAECgoKJQALAFIcAA==.',
Er='Erada:BAABNQAECn8zAAMRAAoKYyARAwDNAgARAAoKYyARAwDNAgAOAAkKsBSWjABmAgAAAA==.',
Ev='Evesong:BAAANQABCgYIBwAAAA==.Evoklando:BAAANQADCgUICgABNQAFFAMIBQASAIoKAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgcIDAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIBAABNQAECgoKIAACAP0DAA==.',
Fe='Felad:BAABNQAECn88AAMhAAoKXyXrAQDcAwAhAAoKXyXrAQDcAwAXAAEKAACXZwBAAAABNQAECgcIDQAMAAAAAA==.Felonyflapp:BAAANQAECgEIAQABNQAECgoKGgALAMENAA==.',
Fh='Fhalanx:BAAANQAECggICAAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECggIDgABNQAECgoKGgALAMENAA==.Flappyy:BAABNQAECn8aAAMLAAoKwQ1MYABOAQALAAoKwQ1MYABOAQAKAAMKNAZ6+gB2AAAAAA==.Flowdinstuna:BAABNQAECn8oAAIeAAoKkRdCGgCHAgAeAAoKkRdCGgCHAgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAABNQAECn8sAAITAAoK2BioRACdAgATAAoK2BioRACdAgAAAA==.Freakmage:BAAANQADCgUIBQAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.Friereñ:BAAANQAECgEIAQAAAA==.',
Fu='Furrybait:BAEANQAECggICAAAAA==.Furyiosa:BAABNQAECn8sAAIUAAoKtB7dJgCaAgAUAAoKtB7dJgCaAgAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgAMAAAAAA==.Gaiseric:BAABNQAECn8pAAIGAAkKsBq3PwAfAgAGAAkKsBq3PwAfAgAAAA==.Gamago:BAAANQAECggIBQAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECn8cAAQaAAkKix5CKAA2AQAQAAcKWBpmcQAMAgAaAAQKCh9CKAA2AQAiAAEKAADLKQBFAAAAAA==.Getoverhere:BAAANQADCggICwAAAA==.',
Gi='Girltank:BAAANQAECgIIBAAAAA==.',
Gn='Gnarlak:BAAANQAECgIIBAAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gorestomp:BAAANQAECggIDAAAAA==.Gotboned:BAAANQAECgcIDAABNQAFFAYIBgADAGMeAA==.Gotfleas:BAACNQAFFH8GAAIDAAYKYx6WAAA6AgADAAYKYx6WAAA6AgA1AAQKfycAAwMACgrvJSQBANsDAAMACgrJJSQBANsDAAQAAgoUE0YzAG0AAAAA.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAABNQAECn83AAIeAAoKexRIKQD5AQAeAAoKexRIKQD5AQAAAA==.Greyfax:BAABNQAECn8rAAIHAAoKFSJSGQATAwAHAAoKFSJSGQATAwAAAA==.Grimthruul:BAABNQAECn8qAAILAAoKHgfRjQCBAQALAAoKHgfRjQCBAQAAAA==.Grommkar:BAABNQAECn8jAAIUAAkKDg7IkADyAQAUAAkKDg7IkADyAQAAAA==.Groztok:BAAANQAECgEIAQAAAA==.Grumpig:BAAANQADCgQIDAAAAA==.Grèggory:BAAANQAECgQICAAAAA==.',
Gu='Gusari:BAEANQAECgEIAQABNQAECggIDAAMAAAAAA==.Gutx:BAAANQADCgQIBAAAAA==.',
Ha='Hadmeathello:BAAANQAECggIEQAAAA==.Halucination:BAABNQAECn8dAAMWAAkK7wxiJAAOAgAWAAkK7wxiJAAOAgAVAAIKlwRr7QBcAAAAAA==.Harthan:BAABNQAECn8hAAMUAAoKqBHFnQDSAQAUAAoKqBHFnQDSAQAjAAEKkQ6tMAA4AAAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayden:BAABNQAECn8bAAINAAoKpxwRWACOAgANAAoKpxwRWACOAgAAAA==.Hayleigh:BAAANQAECgQIBgAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwAMAAAAAA==.Helya:BAAANQADCgMIBgAAAA==.Henchman:BAAANQABCgQICAABNQAECgoKJwATADEkAA==.Hetzák:BAABNQAECn8sAAIZAAoKYhFzOgAfAgAZAAoKYhFzOgAfAgAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBgAAAA==.Hintolisu:BAACNQAFFH8HAAIEAAQK6Q/EAQDPAAAEAAQK6Q/EAQDPAAA1AAQKfz4AAgQACgrMHzcGAA0DAAQACgrMHzcGAA0DAAAA.',
Ho='Hobbess:BAABNQAECn8UAAIeAAgK9BB3LADeAQAeAAgK9BB3LADeAQABNQAFFAoKMQAZABchAA==.Holybaloney:BAABNQAECn8jAAMYAAoKeRzKEQCEAgAYAAgKFx/KEQCEAgANAAkKtAh7tQBPAQAAAA==.Holycheng:BAABNQAECn8cAAMHAAkKmyCyEAAqAwAHAAkKmyCyEAAqAwANAAEKKQ8ElQE/AAAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Hongis:BAAANQAECgEIAQAAAA==.Hoofinit:BAABNQAECn8wAAIUAAoKCyBtKgARAwAUAAoKCyBtKgARAwAAAA==.',
Hu='Huatarm:BAABNQAECn8qAAIkAAoKuRgMDQBiAgAkAAoKuRgMDQBiAgAAAA==.',
Ia='Iadygaga:BAABNQAECn8nAAQVAAoKChJgawDcAQAVAAoKChJgawDcAQAWAAYKLRnkHQCIAQAgAAIKlQM6IwBPAAAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icejade:BAAANQADCggICAABNQAECgYIBgAMAAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECgkJMwAGAL8WAA==.',
Ir='Ironpaw:BAAANQADCgUICAAAAA==.Ironspin:BAAANQAECgQIBgAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Is='Isisankh:BAAANQAECgQIBAAAAA==.Isolated:BAAANQAECggIAwABNQAECgoKOQAFAEYeAA==.',
Ja='Jaark:BAACNQAFFH8PAAIQAAUKlxO3FwDZAAAQAAUKlxO3FwDZAAA1AAQKfzgAAxAACgoMIDomAOsCABAACgoMIDomAOsCACIAAwpOHRAbAI0AAAAA.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgYIDAABNQAECgoKNQAFAIkhAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jehanne:BAAANQADCgQIBQAAAA==.Jen:BAACNQAFFH8HAAIVAAQKSQtQGgAMAQAVAAQKSQtQGgAMAQA1AAQKf0cAAhUACgqQF/5OADgCABUACgqQF/5OADgCAAAA.',
Jo='Jocon:BAAANQAECgYIBgAAAA==.',
Ju='Jugulator:BAAANQADCggIEAAAAA==.Jumpey:BAABNQAECn8bAAMlAAcKMxZmEACrAQAlAAYKnhhmEACrAQAmAAUKEQufaQDSAAABNQAECgkJIgAJAOgWAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAABNQAECn8mAAILAAoKFhksMQC2AgALAAoKFhksMQC2AgABNQAECgQIBgAMAAAAAA==.Kanami:BAABNQAECn8rAAIUAAkKjRhoNgBXAgAUAAkKjRhoNgBXAgAAAA==.Kaynyx:BAABNQAECn8uAAIBAAoKCB3oBgAQAwABAAoKCB3oBgAQAwAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAABNQAECn8uAAINAAoK/xdMcgDXAQANAAoK/xdMcgDXAQAAAA==.Kenzie:BAAANQAECgYICwAAAA==.Kerb:BAABNQAECn82AAQPAAkKMRAjNwBaAQAPAAkKMRAjNwBaAQAcAAIK3gbXmQBgAAAGAAEKAAAn6AAsAAAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECn8aAAMeAAgK7hjYJwAFAgAeAAgK4xTYJwAFAgAmAAQKtBckYAD8AAAAAA==.',
Ki='Kikiko:BAAANQAECgMIAwAAAA==.Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECn8WAAImAAgKDxfMMQAbAgAmAAgKDxfMMQAbAgAAAA==.Kitsurubami:BAAANQAECggIDAABNQAECgoKNQAFAIkhAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQANAPAgAA==.',
Kl='Klaris:BAAANQAECgQIBAAAAA==.',
Kn='Knewtoomuch:BAAANQADCgcIBwAAAA==.',
Ko='Konjur:BAACNQAFFH8ZAAMOAAcKIB9pCwAdAgAOAAYK7h1pCwAdAgARAAIK/SBnBQCwAAA1AAQKfyoAAg4ACgqDJUgSAPwCAA4ACgqDJUgSAPwCAAAA.Korpen:BAAANQADCgEIAQAAAA==.',
Kr='Krelock:BAAANQAECgYICgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgQIBgABNQAECgoKUQAkAC0aAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
Ky='Kytheon:BAAANQADCgIIAgAAAA==.',
['Kà']='Kàmó:BAAANQAECgcIDgABNQAECgQIBgAMAAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgQIBgAAAA==.',
['Kä']='Kämo:BAAANQAECgIIAwABNQAECgQIBgAMAAAAAA==.',
La='Laelada:BAAANQAECgcICQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgcIEAABNQAFFAYIEgACAOwfAA==.Lakeyy:BAACNQAFFH8SAAMCAAYK7B/UBQCUAQACAAYK7B/UBQCUAQAZAAEKfgR6IgA8AAA1AAQKfzYAAwIACgqbJY8CAKQDAAIACgqbJY8CAKQDABkABAppHdRzAPsAAAAA.Lakeyys:BAAANQAECgIIAQABNQAFFAYIEgACAOwfAA==.Lanuor:BAAANQADCgEIAQAAAA==.Laufey:BAAANQAECgQIBwAAAA==.Lavagobrr:BAAANQAECgQIBAABNQAECgkJHAAHAJsgAA==.Lawrence:BAACNQAFFH8TAAIKAAYKQRN0DAB4AQAKAAYKQRN0DAB4AQA1AAQKfy8AAwoACgrfHtYtAKsCAAoACgrfHtYtAKsCAAsABQooF0q5AIMAAAAA.',
Le='Lesaeria:BAABNQAECn8hAAIeAAkKkxpXGgCGAgAeAAkKkxpXGgCGAgABNQAECgoKSgAdAC8kAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQAECgIIAgAAAA==.Lightsardine:BAAANQADCgIIAgAAAA==.Lilikoii:BAAANQAECgQIBAABNQAFFAYIEgACAOwfAA==.Liljit:BAAANQAECgEIAgABNQAECgoKOAAHAGodAA==.Lilslaver:BAABNQAECn8fAAITAAkKnQdjjQCAAQATAAkKnQdjjQCAAQAAAA==.Limerence:BAAANQAECgcIBwAAAA==.Lisex:BAACNQAFFH8LAAMcAAUKTwz9DAAPAQAcAAQKTwz9DAAPAQAPAAEKAAByNQApAAA1AAQKfyIAAxwACQpNIU0YAMgCABwACQpNIU0YAMgCAA8AAQoiFu3FAD0AAAE1AAUUBwgSAAUAhQ4A.Lithe:BAABNQAECn9OAAINAAoKOh+CLAAWAwANAAoKOh+CLAAWAwABNQAECgoKXQALAJ0iAA==.',
Lo='Lockjhaw:BAAANQAFFAEIAQAAAA==.Locklear:BAABNQAECn84AAINAAkKAxd+dADSAQANAAkKAxd+dADSAQAAAA==.Logic:BAACNQAFFH8gAAQfAAgKCBYZAAAKAgAfAAYK8hYZAAAKAgAOAAYKYhM3EwDdAQARAAQKmxb/AgD3AAA1AAQKfzoABA4ACgozIytaAMsCAA4ACgqBIitaAMsCAB8ABwpqIMUDAE4BABEAAwreJOkTADgBAAAA.Lola:BAAANQAECgcICQABNQAFFAYIEgACAOwfAA==.Lolbrez:BAAANQAECggICwAAAA==.',
Lu='Luminovian:BAAANQADCgQIBAAAAA==.Lunanarn:BAAANQADCgIIAwAAAA==.Lunaria:BAAANQAFFAEIAQABNQAFFAYIEgACAOwfAA==.Lusty:BAABNQAECn8iAAIJAAkK6BYEEQBFAgAJAAkK6BYEEQBFAgAAAA==.Luxe:BAAANQAECgIIAgABNQAFFAYIEgACAOwfAA==.',
Ma='Macediin:BAABNQAECn8tAAIGAAoKoBg7GAAWAgAGAAoKoBg7GAAWAgAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECn8bAAIeAAkKiByaHABwAgAeAAkKiByaHABwAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgkJJgASAM8ZAA==.Magnolìa:BAAANQAECgUICQAAAA==.Malefic:BAAANQAECgQIBgABNQAFFAcIGQAOACAfAA==.Malthael:BAABNQAECn8yAAMGAAoKWReHPQApAgAGAAoKqBaHPQApAgAcAAgKlg0nUwBjAQAAAA==.Mamageek:BAAANQAECggIEwAAAA==.Mami:BAAANQAECgIIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECgkJNAALALgiAA==.Manix:BAABNQAECn8rAAQHAAkKmBuAHADFAgAHAAkKmBuAHADFAgANAAIKsAieiQE0AAAYAAEKiwU4aAAnAAAAAA==.Mareo:BAAANQAECgQIBwAAAA==.Marksterique:BAABNQAECn8mAAISAAkKzxmaGQCKAgASAAkKzxmaGQCKAgAAAA==.Masochist:BAAANQAECgMIAwAAAA==.Mausko:BAAANQABCgUIBQAAAA==.',
Me='Meeko:BAACNQAFFH8UAAIIAAgKpRQyBAA5AgAIAAgKpRQyBAA5AgA1AAQKf14AAggACgqKIpIDAF8DAAgACgqKIpIDAF8DAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgQIBQAAAA==.Metalbound:BAAANQAECgcIDgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAABNQAECn8cAAIdAAgKqSSzBgAZAwAdAAgKqSSzBgAZAwAAAA==.Misslobster:BAABNQAECn8WAAIKAAcKpA76oQAxAQAKAAcKpA76oQAxAQAAAA==.',
Mo='Mokoko:BAABNQAECn8wAAIJAAoKdhw3CwC0AgAJAAoKdhw3CwC0AgAAAA==.Mokolock:BAAANQAECgYICAABNQAECgoKMAAJAHYcAA==.Moomoo:BAABNQAECn8oAAIZAAkKFh4dFQAeAwAZAAkKFh4dFQAeAwAAAA==.Moondough:BAAANQADCgEIAQAAAA==.Moorlin:BAAANQAECgYIDQAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgoKMAAJAHYcAA==.',
Mu='Mumra:BAAANQADCgUIBQAAAA==.',
My='Myka:BAAANQAECggIDgABNQAECgkJKwAHAJgbAA==.Mysticphatty:BAAANQADCggJCAABNQAECgIIAgAMAAAAAA==.Myyst:BAAANQAECgQIBQAAAA==.',
Na='Nanaka:BAAANQAECgUIBQABNQAECgYIDgAMAAAAAA==.Nanook:BAAANQADCgcIBwAAAA==.Nawtalhere:BAAANQADCgQIBAABNQAECgoKLQAPAFAiAA==.',
Ne='Necro:BAABNQAECn8fAAIGAAkKix3WIwCzAgAGAAkKix3WIwCzAgAAAA==.Necrota:BAABNQAECn8ZAAMPAAkKZxoCMwBCAgAPAAkK4hgCMwBCAgAGAAEKOiGUxABiAAABNQAFFAcIGQAOACAfAA==.Nekronomicon:BAAANQADCggICgABNQAECgoKQQAVAMgZAA==.Neuron:BAACNQAFFH8VAAMCAAcKxRnNAwAAAgACAAcKxRnNAwAAAgAZAAQKUAd5FwDyAAA1AAQKfycAAwIACgpPHQsSAMACAAIACgpPHQsSAMACABkABgpGEFpXAHkBAAAA.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAABNQAECn8/AAIDAAkKuSDFCADtAgADAAkKuSDFCADtAgAAAA==.Nightflame:BAAANQAECgUICAAAAA==.Ninjavc:BAABNQAECn8kAAIFAAkKkwp6FwBiAQAFAAkKkwp6FwBiAQAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAABNQAECn8ZAAIQAAkK3QkecwBsAQAQAAkK3QkecwBsAQAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQAECgcICQAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Olpheux:BAAANQAECgQIAwAAAA==.',
On='Onayro:BAAANQABCgIIAgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgYIDAAAAA==.Oreyn:BAABNQAECn8YAAMjAAkKEhZDEQBLAQAjAAYKshlDEQBLAQAUAAgKcA4UlgA/AQAAAA==.Organ:BAABNQAECn8VAAQjAAkKegv2FQAEAQAjAAcKcAz2FQAEAQAkAAUKywORMACxAAAUAAcKtgfr2wCoAAAAAA==.Orngar:BAAANQADCgMIAwAAAA==.',
Pa='Padle:BAABNQAECn8hAAMWAAoKZxLzEwAIAgAWAAoKZxLzEwAIAgAgAAUKHhZbBwBGAQAAAA==.Paladín:BAABNQAECn87AAMYAAoKxhd5FADNAQAYAAkKcxl5FADNAQANAAcK2g+00gAdAQAAAA==.Palazar:BAACNQAFFH8HAAINAAQK2xI7FADXAAANAAQK2xI7FADXAAA1AAQKfzEAAg0ACgrKIP8yAAADAA0ACgrKIP8yAAADAAAA.Paoka:BAAANQADCgQIBwABNQADCggIGQAMAAAAAA==.Pappamidnite:BAAANQAECggICAAAAA==.Pargonz:BAABNQAECn9TAAMBAAoKzyCMDwDyAgABAAoKzyCMDwDyAgAFAAIKlw6sjwBzAAAAAA==.Patoko:BAABNQAECn8tAAIdAAkKsB2ACgDKAgAdAAkKsB2ACgDKAgAAAA==.Paxwet:BAABNQAECn8aAAINAAoKWw8bdQDQAQANAAoKWw8bdQDQAQAAAA==.Payn:BAAANQAECgcIDQAAAA==.Paypay:BAABNQAECn82AAICAAkKFx+gCQAsAwACAAkKFx+gCQAsAwAAAA==.',
Ph='Phalannx:BAAANQAECgQIBgAAAA==.Philipx:BAAANQAECgEIAQAAAA==.Phinks:BAAANQADCgIIAgABNQAECgoKVAAdAIolAA==.Phráxas:BAAANQAECgEIAQABNQAFFAMIBgAOAFEQAA==.',
Pi='Piglittle:BAAANQAECgYIDQAAAA==.Pindad:BAABNQAECn8nAAITAAoKMSQlDQB2AwATAAoKMSQlDQB2AwAAAA==.',
Pl='Plzdispelme:BAABNQAECn84AAMHAAoKah08LwCpAgAHAAoKah08LwCpAgANAAEKAACWpgE0AAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAABNQAECn8fAAIaAAkKaBAwDwAIAgAaAAkKaBAwDwAIAgAAAA==.',
Pr='Priesticles:BAABNQAECn8ZAAIVAAoKxgi4WwC5AQAVAAoKxgi4WwC5AQABNQADCgcIFwAMAAAAAA==.Proshvam:BAAANQAECgEIAQAAAA==.Prym:BAABNQAECn8jAAMHAAkKWw5icABQAQAHAAkKWw5icABQAQANAAEKGwF1qAEYAAAAAA==.',
Pu='Purrzac:BAABNQAECn8eAAIDAAgKrh6jGQDcAQADAAgKrh6jGQDcAQABNQAECgoKOAAHAGodAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Racialskill:BAAANQAECggICQABNQAECgoKOAAHAGodAA==.Ragingmonkx:BAABNQAECn8jAAIXAAkK7hXlIAAlAgAXAAkK7hXlIAAlAgAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Ravenious:BAAANQAECggICAAAAA==.Raventer:BAABNQAECn8aAAITAAgKhw70pAC8AQATAAgKhw70pAC8AQAAAA==.Razdrood:BAAANQADCgcIBgABNQAECgcIGwAQAI8MAA==.Razlock:BAABNQAECn8bAAIQAAcKjwzLmAATAQAQAAcKjwzLmAATAQAAAA==.Razorclaws:BAAANQAECgQIBwAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAABNQAECn8wAAIGAAkK2BzJDgCEAgAGAAkK2BzJDgCEAgAAAA==.Risky:BAAANQAECggIBwAAAA==.',
Ro='Roguesucks:BAAANQADCggIDQAAAA==.Roller:BAAANQAECggICAAAAA==.Rollos:BAABNQAECn8yAAIQAAoKHx2QLQBKAgAQAAoKHx2QLQBKAgAAAA==.Rot:BAAANQADCggICAAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAACNQAFFH8VAAMOAAgKsR3GBQBnAgAOAAcKSB3GBQBnAgARAAEKux+ICwBfAAA1AAQKfxYAAg4ABQqKJVF9AJ0BAA4ABQqKJVF9AJ0BAAAA.Ryujinsimp:BAACNQAFFH8MAAMJAAUKURr8BAB2AQAJAAUKURr8BAB2AQAnAAQKrxR/BgAbAQA1AAQKfyIAAycACQq/JO0DANwCAAkACQo1IsIIAOoCACcACAo9JO0DANwCAAE1AAUUCAgVAA4AsR0A.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMIAwAMAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAcIFgAVAB4XAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECn8jAAIIAAkKggwRHwDiAQAIAAkKggwRHwDiAQAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAACNQAFFH8PAAQiAAYKEBSjBAClAAAiAAIKGhSjBAClAAAQAAMKrBciMwCPAAAaAAEK0AxjHgBLAAA1AAQKf9YABCIACgr8JUUBAFIDABAACAr6JbQPAFQDACIACgreJEUBAFIDABoACAoDJDAEAOwCAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAFFAMIBQASAIoKAA==.Shamanigans:BAAANQADCggIEgAAAA==.Shangzha:BAABNQAECn9KAAIdAAoKLySkAQBLAwAdAAoKLySkAQBLAwAAAA==.Shareholder:BAEBNQAECn8vAAIQAAoKmiTMBwAmAwAQAAoKmiTMBwAmAwABNQAFFAYICQAOAKoYAA==.Shiivera:BAABNQAECn8rAAIKAAoKmh3AMQCZAgAKAAoKmh3AMQCZAgAAAA==.Shimada:BAABNQAECn8wAAITAAoKexzmKAD0AgATAAoKexzmKAD0AgAAAA==.Shotsyll:BAACNQAFFH8IAAITAAMKfRTfFgADAQATAAMKfRTfFgADAQA1AAQKfxgAAhMACAqtG1WMAPIBABMACAqtG1WMAPIBAAAA.',
Sk='Skarín:BAAANQADCgMIAQAAAA==.Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAABNQAECn85AAMFAAoKQh0cCABdAgABAAoKOBrHHwCAAgAFAAkKYRwcCABdAgAAAA==.Skynomad:BAAANQAECgYIEgAAAA==.',
Sl='Slyde:BAABNQAECn8hAAIGAAcKWyOsJQCoAgAGAAcKWyOsJQCoAgAAAA==.',
Sm='Smalldk:BAACNQAFFH8KAAMPAAIKAAAzJwBdAAAPAAEKAAAzJwBdAAAGAAEKAAB2JQA2AAA1AAQKfxcAAwYACgo/FENkAH8BAAYACgqvEUNkAH8BAA8ABQoYHdxnAFMBAAE1AAUUBggSAA0AsRUA.Smallrichard:BAAANQAECgEIAQABNQAECgQICgAMAAAAAA==.Smashytash:BAABNQAECn8bAAIjAAoKOxWyCAAFAgAjAAoKOxWyCAAFAgAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgoKGwAjADsVAA==.',
Sn='Snek:BAAANQAECgEIBAAAAA==.Snowing:BAAANQAECgYIDwABNQAECgkJGAAGAHYWAA==.Snugglybear:BAABNQAECn8zAAIDAAoKNSaqAACIAwADAAoKNSaqAACIAwABNQAFFAQIDAAPAFseAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Sodlid:BAAANQAECgcIDQAAAA==.Solariaa:BAAANQAECgMIAwABNQAFFAYIEgACAOwfAA==.Solborne:BAAANQABCgQIBgAAAA==.Solfreid:BAAANQAECgYIEAAAAA==.Sophism:BAABNQAECn8WAAMFAAoKeBd7LAA1AgAFAAoK+BN7LAA1AgABAAYKARYEagBMAQABNQAFFAgIIAAfAAgWAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAPAFAmAA==.Soulfang:BAABNQAECn85AAIjAAoKiBYiCAATAgAjAAoKiBYiCAATAgAAAA==.Soulfox:BAAANQADCgQIBAABNQAECggIEQAMAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulripper:BAAANQAECggICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAABNQAECn8jAAIKAAoK0BwwFQD7AgAKAAoK0BwwFQD7AgABNQAFFAQIBQABAOwFAA==.Sprocketrot:BAABNQAECn8eAAMcAAkKUxmfJQAUAgAcAAkK/RSfJQAUAgAGAAUKgx3oWwCgAQAAAA==.',
Sq='Squidmonk:BAABNQAECn8eAAIhAAkKHBFxGwDLAQAhAAkKHBFxGwDLAQAAAA==.',
St='Stardrive:BAACNQAFFH8PAAIUAAUK5QfHIAD6AAAUAAUK5QfHIAD6AAA1AAQKfyYAAhQACgphEll/AB0CABQACgphEll/AB0CAAAA.Steelwhacka:BAABNQAECn8VAAMXAAgK7gs8MgCFAQAXAAgK7gs8MgCFAQAhAAUKgwtxMgDWAAAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFH8YAAIXAAcK9BmgBAD2AQAXAAcK9BmgBAD2AQA1AAQKfycAAhcACgqaIiMUALYCABcACgqaIiMUALYCAAAA.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAABNQAECn8YAAQQAAoKjQ0DrADoAAAQAAgKTQ0DrADoAAAaAAIKTQ61WgBwAAAiAAIKuQuoLQA7AAAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQAECgYIBwABNQAECgYIEgAMAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgYIDAAAAA==.Surtur:BAABNQAECn9bAAMUAAoKGB32MQBpAgAUAAoKGB32MQBpAgAkAAcKcBBoGAAxAQAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECgoKOwAYAMYXAA==.Swoobs:BAAANQAECggIBwABNQAFFAQICwAGADwEAA==.',
Sy='Sygismund:BAABNQAECn8yAAMmAAkKWgaIQQAXAQAmAAkKWgaIQQAXAQAeAAIK3ADmWwAPAAAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAACNQAFFH8IAAITAAQK9A8hFADgAAATAAQK9A8hFADgAAA1AAQKfzsAAhMACgpfHickAAYDABMACgpfHickAAYDAAAA.Tandalil:BAAANQADCgUIBQAAAA==.Tanglefoot:BAAANQAECgEIAQAAAA==.Taotien:BAAANQAECgcICwAAAA==.Tashbringer:BAAANQAECgIIBQABNQAECgoKGwAjADsVAA==.',
Tc='Tchaik:BAABNQAECn8yAAMVAAoKZCA4FQAmAwAVAAoKZCA4FQAmAwAWAAIK7hQNVgBDAAAAAA==.',
Te='Teccnicality:BAAANQAECgQIBAAAAA==.Tecknicaliti:BAAANQAECgQIBgAAAA==.Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgUIEgAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQAECgMIBgAAAA==.Theios:BAABNQAECn8iAAIUAAgK1gx9jQBSAQAUAAgK1gx9jQBSAQABNQAECgkJMwAGAL8WAA==.Thickthang:BAABNQAECn82AAMdAAoK+yNuAgCFAwAdAAoK+yNuAgCFAwALAAQKrhYp3gDZAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECn9cAAMlAAoKgCRGAQA0AwAlAAoKgCRGAQA0AwAeAAEKAAAMYAAAAAAAAA==.Timewarp:BAAANQAECggICAABNQAECgoKUgAXABofAA==.Tinytea:BAABNQAECn9SAAMXAAoKGh9nCgCvAgAXAAoKGh9nCgCvAgAoAAEKAABiLQBSAAAAAA==.Tinytilted:BAAANQADCgEIAQAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgcIDQAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAABNQAECn9DAAIQAAoK8Q7FSQDlAQAQAAoK8Q7FSQDlAQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgUICAAMAAAAAA==.',
Tr='Trilicia:BAABNQAECn8cAAMFAAoK9hWJFACBAQAFAAoK/BSJFACBAQABAAcKNxAbdAAsAQAAAA==.Trusinner:BAABNQAECn8bAAIUAAgKRxjdbgBGAgAUAAgKRxjdbgBGAgAAAA==.',
Ts='Tsusha:BAEBNQAECn8UAAILAAYKEw4VowBPAQALAAYKEw4VowBPAQABNQAECggIFAANABsHAA==.',
Tu='Turkeyleg:BAAANQADCggIHwAAAA==.',
Tw='Twippy:BAABNQAECn8oAAILAAoKKRP8TABDAgALAAoKKRP8TABDAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQAECgQIBAABNQAECgUIBAAMAAAAAA==.Tyriam:BAABNQAECn8/AAINAAoK8R03RQDFAgANAAoK8R03RQDFAgAAAA==.',
Ud='Udderchaos:BAAANQAECggIDgAAAA==.',
Un='Undeadboss:BAAANQADCgUIBgABNQAECggIEQAMAAAAAA==.Unifey:BAAANQAECgYIBwAAAA==.',
Va='Valess:BAAANQAECgIIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.Varrae:BAAANQADCgIIAgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAACNQAFFH8TAAIJAAYK/heVAQA0AQAJAAYK/heVAQA0AQA1AAQKfzsAAgkACgowIFsHAAwDAAkACgowIFsHAAwDAAAA.Verso:BAABNQAECn8oAAIpAAoKCxfOBgBZAgApAAoKCxfOBgBZAgAAAA==.',
Vi='Vitalithry:BAABNQAECn8qAAMnAAoKpxc3BgBrAgAnAAoKpxc3BgBrAgAJAAQK2hFdFADdAAAAAA==.Vivii:BAAANQAECgcICwAAAA==.Vizzysmash:BAAANQAECgYIBgABNQAECgoKRAAGAJ4dAA==.',
Vo='Voden:BAAANQABCgUICAAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.Watpex:BAAANQAECgQIBAAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECn9IAAMcAAoKBBkCKQBRAgAcAAoKBBkCKQBRAgAPAAUKoA9vjADQAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAABNQAECn80AAMLAAkKuCJLJwDmAgALAAkKuCJLJwDmAgAKAAMKqxTn2wCwAAAAAA==.Whiteshadow:BAAANQAECgQICAAAAA==.',
Wi='Wiiska:BAACNQAFFH8OAAMWAAYK3RS2BgAcAQAWAAUKsBC2BgAcAQAVAAEKXwDINABDAAA1AAQKfzgAAxYACgrPHckUAL0CABYACgrPHckUAL0CABUABwpkCl6ZAPcAAAAA.Wildling:BAAANQADCgIIAwAAAA==.Windoelicker:BAAANQADCgcIFwAAAA==.',
Wo='Worgya:BAAANQAECgQIAwABNQAECggIEQAMAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgoKJwATADEkAA==.Wrlccywhefr:BAABNQAECn81AAQBAAoK0yNzHgCIAgABAAgKfCFzHgCIAgAFAAcKwiPYIgBwAgApAAYKph/HCQDnAQAAAA==.',
Wu='Wuggles:BAABNQAECn8eAAICAAkKORdHGgBnAgACAAkKORdHGgBnAgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAABNQAECn8nAAITAAkKPhxHdwAhAgATAAkKPhxHdwAhAgAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwAUAEcYAA==.',
Xy='Xyklon:BAAANQADCgQIBAAAAA==.',
Ya='Yahmon:BAABNQAECn8cAAIKAAkKtQ4LWwCSAQAKAAkKtQ4LWwCSAQAAAA==.',
Ye='Yetil:BAABNQAECn8ZAAIHAAkK9w47fACkAQAHAAkK9w47fACkAQAAAA==.',
Yn='Ynotraw:BAACNQAFFH8FAAIUAAMKEhn9FgDhAAAUAAMKEhn9FgDhAAA1AAQKfzIAAhQACgocIo8MAJMDABQACgocIo8MAJMDAAAA.Ynotstorm:BAAANQAECgQIBAAAAA==.',
Yo='Yourephired:BAABNQAECn8rAAMRAAoKvhC9DACvAQARAAoKvhC9DACvAQAOAAEKAAAp2gEoAAAAAA==.',
Za='Zaerix:BAAANQADCgYICQAAAA==.Zaknafein:BAAANQAECgUICQABNQAFFAMIBgAOAFEQAA==.Zarah:BAAANQAECgEIAQAAAA==.Zaycursed:BAAANQAECgQICgABNQAECggIHgALABQfAA==.Zaydream:BAAANQADCgcIBwABNQAECggIHgALABQfAA==.Zaylight:BAAANQADCggICAABNQAECggIHgALABQfAA==.Zayseer:BAABNQAECn8eAAILAAgKFB+TOACUAgALAAgKFB+TOACUAgAAAA==.',
Ze='Zello:BAABNQAECn8rAAMVAAoK4wlzdgBfAQAVAAkKVgpzdgBfAQAWAAQKcATnYAB+AAAAAA==.',
Zh='Zhengy:BAABNQAECn8VAAIaAAYKFhEsCQAiAQAaAAYKFhEsCQAiAQABNQAFFAMIBgAOAFEQAA==.',
Zi='Ziggybeast:BAABNQAECn8jAAQZAAoKWx1dNwAyAgAZAAgK/R1dNwAyAgACAAgKqRooJAAEAgADAAEKAADIZAArAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAABNQAECn8bAAMkAAUKJAoUMABzAAAUAAQKBAM2LAF8AAAkAAUKJAoUMABzAAAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggIHgALABQfAA==.',
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
