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

local lookup = {'Rogue-Subtlety','Druid-Restoration','Druid-Guardian','Druid-Feral','Rogue-Assassination','Mage-Arcane','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Warlock-Demonology','Mage-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Arms','Priest-Holy','Priest-Shadow','Monk-Windwalker','Paladin-Protection','Druid-Balance','Warlock-Destruction','Hunter-Survival','DeathKnight-Frost','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Priest-Discipline','Monk-Mistweaver','Warlock-Affliction','Warrior-Fury','Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aanna:BAAANQAECggICwAAAA==.',
Ab='Abandonedcat:BAAANQAECggIDAABNQAECgoKNQABANMjAA==.Abor:BAABNQAECn8mAAQCAAoK/QNLQQAdAQACAAoK/QNLQQAdAQADAAoKagekLwAXAQAEAAMKSgq2LwCUAAAAAA==.Abuela:BAABNQAECn85AAMFAAoKRh5sDQAZAwAFAAoKvxxsDQAZAwABAAkKSRhJNQAmAgABNQAECgoKFgAGAE4XAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ad='Adaela:BAAANQADCgIIAgABNQAECgoKOQAFACAiAA==.',
Ae='Aegla:BAABNQAECn83AAIHAAkKvxZoJQC1AQAHAAkKvxZoJQC1AQAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ag='Aghlath:BAAANQAECgYICAAAAA==.',
Ak='Akiko:BAAANQAECgYIDQABNQAECgoKOgAIABYeAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFH8RAAIJAAUKZA/YDgDyAAAJAAUKZA/YDgDyAAA1AAQKfzcAAwkACgo7Gz0NANICAAkACgo7Gz0NANICAAoAAQruCDUnAC8AAAAA.Alliar:BAABNQAECn8uAAMLAAoKFh0nKwC2AgALAAoKFh0nKwC2AgAMAAYKPwl5rAA7AQAAAA==.Allynstraza:BAABNQAECn8VAAIJAAYKARClKgBYAQAJAAYKARClKgBYAQAAAA==.',
Am='Amgems:BAAANQAECgQIBQABNQAECgcIDQANAAAAAA==.Amordred:BAABNQAECn8dAAIFAAcKcgqRKgDnAAAFAAcKcgqRKgDnAAAAAA==.',
An='Anasterion:BAABNQAECn8VAAIOAAgK8CAlbgBUAgAOAAgK8CAlbgBUAgAAAA==.Andarus:BAABNQAECn8hAAIOAAcKuhqKkQCpAQAOAAcKuhqKkQCpAQABNQAFFAMIBgAGAFEQAA==.Ankles:BAABNQAECn8nAAMPAAkKfiPRBwB/AwAPAAkKfiPRBwB/AwAHAAIK+glCzwBPAAAAAA==.Ansley:BAAANQADCgUICAABNQAECgoKOQAFACAiAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgYICwABNQAECgoKTgAQAC8gAA==.',
As='Ashli:BAABNQAECn85AAMFAAoKICLsAwD4AgAFAAoKICLsAwD4AgABAAgKDBg4OwAPAgAAAA==.Astiri:BAACNQAFFH8HAAIRAAYKLROrAQAtAQARAAYKLROrAQAtAQA1AAQKfxwAAhEACgqZIGsCAPwCABEACgqZIGsCAPwCAAAA.',
At='Atlasblitz:BAAANQAECgYIBgAAAA==.Atlasbär:BAAANQAECgUIBAABNQAECggICAANAAAAAA==.Atlasdark:BAABNQAECn8bAAMLAAoKthxiPQBqAgALAAoKthxiPQBqAgAMAAEK0xTq8QA/AAABNQAECggICAANAAAAAA==.Atlasfallen:BAAANQAECggICAAAAA==.Atreyu:BAAANQAECgYIBwAAAA==.',
Ba='Balrock:BAAANQAECgIIBQAAAA==.Balthromaw:BAABNQAECn9CAAIQAAoKJRzYHwCUAgAQAAoKJRzYHwCUAgAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQANAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECggICQABNQAFFAMIBQASAIoKAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belfdelphine:BAAANQAECgcIBgAAAA==.Bellum:BAAANQAECgcIEAAAAA==.Belstab:BAABNQAECn8tAAMBAAgK/g/XGwD3AQABAAgKhw/XGwD3AQAFAAcKcwkNTgCHAQABNQAFFAQICwAHADwEAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIEAABNQAECgoKJwATADEkAQ==.',
Bg='Bgbalkoth:BAAANQADCgYIDAAAAA==.',
Bi='Bifurthegrey:BAAANQAECgUIBAABNQAECgUIBQANAAAAAA==.Bigblammy:BAAANQADCggICAABNQAFFAgIGwAGAE0eAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQABNQAECgYIEAANAAAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Blinkss:BAAANQAECgYIBgAAAA==.Bloodavenger:BAABNQAECn8dAAMIAAkKZgx0ZgDkAQAIAAkKZgx0ZgDkAQAOAAUK9wb3KgHZAAAAAA==.Bloodemongar:BAABNQAECn8WAAIHAAkKvg5RZgB3AQAHAAkKvg5RZgB3AQAAAA==.Bloodhoundss:BAABNQAECn8kAAIUAAoK4xWjWQDyAQAUAAoK4xWjWQDyAQAAAA==.Blössöm:BAAANQAECgYIDAAAAA==.',
Bo='Bobdk:BAACNQAFFH8eAAMHAAcKvBwFBAD0AQAHAAcKvBwFBAD0AQAPAAEKAADsOAAgAAA1AAQKf0EAAgcACgp+JI4HAPwCAAcACgp+JI4HAPwCAAAA.Bonejangles:BAAANQAECgcIDQAAAA==.Boomfrin:BAAANQAECgUICgAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECn8lAAMVAAkK6BA6WQAWAgAVAAkK6BA6WQAWAgAWAAEKXAWlewAxAAAAAA==.',
Br='Braegen:BAABNQAECn8kAAMTAAkKuBUXTQA0AgATAAkKuBUXTQA0AgASAAEKPgbRaAAyAAABNQAFFAMIBgAGAFEQAA==.Brewslee:BAAANQADCggICAAAAA==.Brewsleê:BAAANQAECgQIBAAAAA==.Bruceleett:BAABNQAECn8/AAIXAAkKjRIcGwDRAQAXAAkKjRIcGwDRAQABNQADCgcIFwANAAAAAA==.',
Bu='Buffmeister:BAAANQAECgUIBQAAAA==.Bullioss:BAABNQAECn8YAAMOAAgKlxmlkgCnAQAOAAcKlxmlkgCnAQAYAAMKGxj2RQDYAAABNQAECgoKJwATADEkAA==.',
['Bà']='Bàtman:BAAANQADCgcIDAAAAA==.',
['Bö']='Böbbyboucher:BAABNQAECn8lAAIMAAoKUhy0PwB2AgAMAAoKUhy0PwB2AgAAAA==.',
Ca='Cainn:BAAANQADCggIGAABNQAECgoKMQAOAP8XAA==.Caldrid:BAAANQADCgYIDwAAAA==.Calfurion:BAABNQAECn8VAAMEAAgKqB3zEAD4AQAZAAcKShxEPwAAAgAEAAYK1B7zEAD4AQAAAA==.Calvary:BAAANQAECggIDgABNQAECggIFQAEAKgdAA==.Capncrunch:BAAANQADCgYICwAAAA==.Cazleah:BAABNQAECn84AAIMAAoKkyEOGQAzAwAMAAoKkyEOGQAzAwAAAA==.',
Ce='Cessatio:BAABNQAECn8yAAIaAAoKOQ1uBgB7AQAaAAoKOQ1uBgB7AQAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAABNQAECn8tAAIOAAoKYhtjawBbAgAOAAoKYhtjawBbAgABNQAECgoKUwABAM8gAA==.Chowming:BAAANQABCgEIAQAAAA==.Chrisbrewn:BAABNQAECn8kAAIUAAkKzhMkcgA+AgAUAAkKzhMkcgA+AgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clamsweat:BAAANQABCgIIAgAAAA==.Clevelandoe:BAACNQAFFH8FAAISAAMKigoPGQC5AAASAAMKigoPGQC5AAA1AAQKfzkAAxIACQpIJGEOAPwCABIACQq6IWEOAPwCABMABQoUHMKnALYBAAAA.',
Co='Cobbknob:BAAANQAECgUIBwAAAA==.Cocobear:BAAANQAECgEIAQAAAA==.Coeurdeleon:BAABNQAECn8dAAMOAAoKTxTxhAAeAgAOAAoKTxTxhAAeAgAYAAEKAAC2ZgBHAAAAAA==.Cokakilla:BAAANQADCggIDAAAAA==.Condemnation:BAABNQAECn9BAAIVAAoKyBnFOACFAgAVAAoKyBnFOACFAgAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgYICgABNQADCggIDQANAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQANAAAAAA==.Coriantumr:BAAANQADCgYIBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQAECgQIBQAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbstomped:BAABNQAECn8wAAQTAAoKpRUzbwAzAgATAAoKpRUzbwAzAgASAAUKLwmqMwDZAAAbAAEKAADAFwAAAAAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgcIEAABNQAFFAgIFQAGALEdAA==.Darkvizzy:BAABNQAECn9EAAQHAAoKnh2dGQAaAgAHAAkKsR2dGQAaAgAPAAkKVhHTNAB0AQAcAAQKQg4lkQB+AAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgYIBwAAAA==.Demiplo:BAABNQAECn8oAAITAAkKyBSFegAZAgATAAkKyBSFegAZAgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQANAAAAAA==.Denelak:BAABNQAECn8hAAMTAAoKZx8QEgBYAwATAAoK2x0QEgBYAwASAAkKcxcqGQCOAgAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAABNQAECn8WAAIGAAoKThe+tgAWAgAGAAoKThe+tgAWAgAAAA==.',
Di='Dirtycasual:BAAANQAECggIDgABNQAECgoKFgAGAE4XAA==.Discipline:BAABNQAECn9EAAMYAAoKTh0vDQBbAgAYAAoKTh0vDQBbAgAOAAgKchU8mQDxAQAAAA==.',
Do='Doggo:BAAANQAECgEIAQAAAA==.Dotsurdead:BAAANQAECggICwAAAA==.',
Dr='Dratr:BAABNQAECn84AAIdAAoKjQ5eFQC/AQAdAAoKjQ5eFQC/AQAAAA==.Draxyl:BAACNQAFFH8IAAMPAAIKFwl2IgBeAAAPAAIKFwl2IgBeAAAHAAEKnAClJgAsAAA1AAQKfz0AAw8ACgp2F60yAIABAAcACQokD9pKAOoBAA8ACgoCFq0yAIABAAAA.Drekhan:BAABNQAECn8YAAMPAAYKyQPIZwCsAAAPAAYKyQPIZwCsAAAcAAQK2wL1mQBgAAABNQAFFAMIBgAGAFEQAA==.Drfizzle:BAAANQAECgEIAQABNQAECgoKMAAUAAsgAA==.Drham:BAABNQAECn8kAAIeAAkKJQ4vKQD6AQAeAAkKJQ4vKQD6AQAAAA==.Drogbar:BAAANQAECgEIAQABNQAECgkJIwAXAO4VAA==.Drokos:BAAANQAECgYIBwABNQAECgoKJwATADEkAA==.Drtree:BAAANQADCgcIBwAAAA==.Druni:BAAANQADCgEIAQAAAA==.',
Du='Dunhambones:BAABNQAECn83AAIHAAoK4yEbEQAuAwAHAAoK4yEbEQAuAwAAAA==.Duo:BAABNQAECn88AAIfAAoKExTSAQBwAgAfAAoKExTSAQBwAgABNQAECgoKJgACAP0DAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Elcosote:BAAANQAECgcIDAAAAA==.Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQAECgYICQAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECn8+AAQVAAoK+hKwYwD1AQAVAAoK+hKwYwD1AQAWAAIK6QGceQA1AAAgAAEK/gUdKQAyAAAAAA==.Elrey:BAAANQAECggIBwABNQAECgoKFgAGAE4XAA==.Elèctra:BAAANQAECggIEQAAAA==.',
En='Enochs:BAAANQADCgIIAgAAAA==.Enyô:BAAANQADCgQIBAABNQAECgoKJQAMAFIcAA==.',
Er='Erada:BAABNQAECn8zAAMRAAoKYyCRAwDGAgARAAoKYyCRAwDGAgAGAAkKsBSWjABmAgAAAA==.',
Ev='Evesong:BAAANQABCgYIBwAAAA==.Evoklando:BAAANQADCgUICgABNQAFFAMIBQASAIoKAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgcIDAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIBAABNQAECgoKJgACAP0DAA==.',
Fe='Felad:BAABNQAECn88AAMhAAoKXyU1AgDVAwAhAAoKXyU1AgDVAwAXAAEKAACXZwBAAAABNQAECgcIDQANAAAAAA==.Felonyflapp:BAAANQAECgIIAgABNQAECgoKGgAMAMENAA==.',
Fh='Fhalanx:BAAANQAECggICgAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECggIDgABNQAECgoKGgAMAMENAA==.Flappyy:BAABNQAECn8aAAMMAAoKwQ0gaQBMAQAMAAoKwQ0gaQBMAQALAAMKNAZ6+gB2AAAAAA==.Flowdinstuna:BAABNQAECn8oAAIeAAoKkRdCGgCHAgAeAAoKkRdCGgCHAgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAABNQAECn8sAAITAAoK2BioRACdAgATAAoK2BioRACdAgAAAA==.Freakmage:BAAANQADCgUIBQAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.Friereñ:BAAANQAECgEIAQAAAA==.',
Fu='Furrybait:BAEANQAECgcICgAAAA==.Furyiosa:BAABNQAECn8uAAIUAAoKtB50KACeAgAUAAoKtB50KACeAgAAAA==.',
Ga='Gaarak:BAAANQAECgIIAgAAAA==.Gahiji:BAAANQADCgcIDQABNQAECgQJBgANAAAAAA==.Gaiseric:BAABNQAECn8pAAIHAAkKsBq3PwAfAgAHAAkKsBq3PwAfAgAAAA==.Gamago:BAAANQAECggIBQAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECn8cAAQaAAkKix5CKAA2AQAQAAcKWBpmcQAMAgAaAAQKCh9CKAA2AQAiAAEKAADLKQBFAAAAAA==.Getoverhere:BAAANQADCggICwAAAA==.',
Gi='Girltank:BAAANQAECgIIBAAAAA==.',
Gn='Gnarlak:BAAANQAECgMIBQAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gorestomp:BAAANQAECggIDwABNQAECgoKTAAdADAkAA==.Gotboned:BAAANQAECgcIDAABNQAFFAYIBgADAGMeAA==.Gotfleas:BAACNQAFFH8GAAIDAAYKYx6WAAA6AgADAAYKYx6WAAA6AgA1AAQKfycAAwMACgrvJSQBANsDAAMACgrJJSQBANsDAAQAAgoUEwo4AG0AAAAA.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAABNQAECn83AAIeAAoKexRIKQD5AQAeAAoKexRIKQD5AQAAAA==.Greyfax:BAABNQAECn8rAAIIAAoKFSJSGQATAwAIAAoKFSJSGQATAwAAAA==.Grimthruul:BAABNQAECn8qAAIMAAoKHgfRjQCBAQAMAAoKHgfRjQCBAQAAAA==.Grommkar:BAABNQAECn8jAAIUAAkKDg7IkADyAQAUAAkKDg7IkADyAQAAAA==.Groztok:BAAANQAECgMIAwAAAA==.Grumpig:BAAANQADCgQIDAAAAA==.Grèggory:BAAANQAECgQICAAAAA==.',
Gu='Gusari:BAEANQAECgEIAQABNQAECggIDAANAAAAAA==.Gutx:BAAANQADCgQIBAAAAA==.',
Ha='Hadmeathello:BAAANQAECggIEQAAAA==.Halucination:BAABNQAECn8dAAMWAAkK7wxiJAAOAgAWAAkK7wxiJAAOAgAVAAIKlwRr7QBcAAAAAA==.Harthan:BAABNQAECn8hAAMUAAoKqBHFnQDSAQAUAAoKqBHFnQDSAQAjAAEKkQ7eNAA3AAAAAA==.Hatchep:BAAANQAECgEIAQAAAA==.Hayden:BAABNQAECn8bAAIOAAoKpxwRWACOAgAOAAoKpxwRWACOAgAAAA==.Hayleigh:BAABNQAECn8VAAIGAAoKYAi6fwCrAQAGAAoKYAi6fwCrAQAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwANAAAAAA==.Helya:BAAANQADCgMIBgAAAA==.Henchman:BAAANQABCgQICAABNQAECgoKJwATADEkAA==.Hetzák:BAABNQAECn8sAAIZAAoKYhFzOgAfAgAZAAoKYhFzOgAfAgAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBgAAAA==.Hintolisu:BAACNQAFFH8HAAIEAAQK6Q/xAQDPAAAEAAQK6Q/xAQDPAAA1AAQKf0QAAgQACgouITcGAA0DAAQACgouITcGAA0DAAAA.',
Ho='Hobbess:BAABNQAECn8UAAIeAAgK9BB3LADeAQAeAAgK9BB3LADeAQABNQAFFAoKMQAZABchAA==.Holybaloney:BAABNQAECn8jAAMYAAoKeRzKEQCEAgAYAAgKFx/KEQCEAgAOAAkKtAh4xABLAQAAAA==.Holycheng:BAABNQAECn8cAAMIAAkKmiBzEAA6AwAIAAkKmiBzEAA6AwAOAAEKKQ8ElQE/AAAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Hongis:BAAANQAECgEIAQAAAA==.Hoofinit:BAABNQAECn8wAAIUAAoKCyBtKgARAwAUAAoKCyBtKgARAwAAAA==.',
Hu='Huatarm:BAABNQAECn8qAAIkAAoKuRgMDQBiAgAkAAoKuRgMDQBiAgAAAA==.',
Ia='Iadygaga:BAABNQAECn8nAAQVAAoKChJgawDcAQAVAAoKChJgawDcAQAWAAYKLRlaIACIAQAgAAIKlQM6IwBPAAAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icejade:BAAANQADCggICAABNQAECgcIDAANAAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECgkJNwAHAL8WAA==.',
Ir='Ironpaw:BAAANQADCgUICAAAAA==.Ironspin:BAAANQAECgQIBgAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Is='Isisankh:BAAANQAECgQIBwAAAA==.Isolated:BAAANQAECggIAwABNQAECgoKFgAGAE4XAA==.',
Ja='Jaark:BAACNQAFFH8PAAIQAAUKlxMPHAAXAQAQAAUKlxMPHAAXAQA1AAQKfzgAAxAACgoMIDomAOsCABAACgoMIDomAOsCACIAAwpOHbkdAIoAAAAA.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgYIDQABNQAECgoKOQAFACAiAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jehanne:BAAANQADCgQIBQAAAA==.Jen:BAACNQAFFH8HAAIVAAQKSQvGHQAEAQAVAAQKSQvGHQAEAQA1AAQKf00AAhUACgo1GTZKAA8CABUACgo1GTZKAA8CAAAA.',
Jo='Jocon:BAAANQAECgYIBgAAAA==.',
Ju='Jugulator:BAAANQADCggIEAAAAA==.Jumpey:BAABNQAECn8bAAMlAAcKMxZmEACrAQAlAAYKnhhmEACrAQAmAAUKEQufaQDSAAABNQAECgkJIgAKAOgWAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAABNQAECn8mAAIMAAoKFhksMQC2AgAMAAoKFhksMQC2AgABNQAECgQIBgANAAAAAA==.Kanami:BAABNQAECn8rAAIUAAkKjRhqPABQAgAUAAkKjRhqPABQAgAAAA==.Kaynyx:BAABNQAECn8uAAIBAAoKCB3oBgAQAwABAAoKCB3oBgAQAwAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAABNQAECn8xAAIOAAoK/xeqfAAxAgAOAAoK/xeqfAAxAgAAAA==.Kenzie:BAAANQAECggIDgAAAA==.Kerb:BAABNQAECn84AAQPAAoKABCsMgCAAQAPAAoKABCsMgCAAQAcAAIK3gbXmQBgAAAHAAEKAAAn6AAsAAAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECn8aAAMeAAgK7hjYJwAFAgAeAAgK4xTYJwAFAgAmAAQKtBckYAD8AAAAAA==.',
Ki='Kikiko:BAAANQAECgQIAwAAAA==.Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECn8WAAImAAgKDxfMMQAbAgAmAAgKDxfMMQAbAgAAAA==.Kitsurubami:BAABNQAECn8WAAIUAAkKCBNaTAAaAgAUAAkKCBNaTAAaAgABNQAECgoKOQAFACAiAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQAOAPAgAA==.',
Kl='Klaris:BAAANQAECgQIBAAAAA==.',
Kn='Knewtoomuch:BAAANQADCgcIBwAAAA==.',
Ko='Konjur:BAACNQAFFH8bAAMGAAgKTR5pCwAdAgAGAAcKLh1pCwAdAgARAAIK/SBaBgCvAAA1AAQKfyoAAgYACgqDJewUAPYCAAYACgqDJewUAPYCAAAA.Korpen:BAAANQADCgUIBgAAAA==.',
Kr='Krelock:BAAANQAECgYICgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgQIBgABNQAECgoKVQAkAC4aAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
Ky='Kytheon:BAAANQADCgIIAgAAAA==.',
['Kà']='Kàmó:BAAANQAECgcIDgABNQAECgQIBgANAAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgQIBgAAAA==.',
['Kä']='Kämo:BAAANQAECgIIAwABNQAECgQIBgANAAAAAA==.',
La='Laelada:BAAANQAECgcICQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECggIEQABNQAFFAYIEgACAOwfAA==.Lakeyy:BAACNQAFFH8SAAMCAAYK7B+tBgCSAQACAAYK7B+tBgCSAQAZAAEKfgQDJQA6AAA1AAQKfzYAAwIACgqbJY8CAKQDAAIACgqbJY8CAKQDABkABAppHdRzAPsAAAAA.Lakeyys:BAAANQAECgIIAQABNQAFFAYIEgACAOwfAA==.Lanuor:BAAANQADCgEIAQAAAA==.Laufey:BAAANQAECgUICAAAAA==.Lavagobrr:BAAANQAECgQIBAABNQAECgkJHAAIAJogAA==.Lawrence:BAACNQAFFH8TAAILAAYKQRNnDgB3AQALAAYKQRNnDgB3AQA1AAQKfzAAAwsACgrfHtYtAKsCAAsACgrfHtYtAKsCAAwABQooFwrEAIMAAAAA.',
Le='Lesaeria:BAABNQAECn8mAAIeAAkKfBtXGgCGAgAeAAkKfBtXGgCGAgABNQAECgoKTAAdADAkAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQAECgIIAgAAAA==.Lightsardine:BAAANQADCgIIAgAAAA==.Lilikoii:BAAANQAECgQIBAABNQAFFAYIEgACAOwfAA==.Liljit:BAAANQAECgEIAgABNQAECgoKOgAIABYeAA==.Lilslaver:BAABNQAECn8fAAITAAkKnQcImwB+AQATAAkKnQcImwB+AQAAAA==.Limerence:BAAANQAECgcIBwAAAA==.Lisex:BAACNQAFFH8LAAMcAAUKTwz9DAAPAQAcAAQKTwz9DAAPAQAPAAEKAAByNQApAAA1AAQKfyIAAxwACQpNIU0YAMgCABwACQpNIU0YAMgCAA8AAQoiFu3FAD0AAAE1AAUUBwgSAAUAhQ4A.Lithe:BAABNQAECn9WAAIOAAoKyR+CLAAWAwAOAAoKyR+CLAAWAwABNQAECgoKZAAMALAiAA==.',
Lo='Lockjhaw:BAAANQAFFAEIAQAAAA==.Locklear:BAABNQAECn84AAIOAAkKAxdfgADMAQAOAAkKAxdfgADMAQAAAA==.Logic:BAACNQAFFH8gAAQfAAgKCBYZAAAKAgAfAAYK8hYZAAAKAgAGAAYKYhM3EwDdAQARAAQKmxb/AgD3AAA1AAQKfzoABAYACgozIytaAMsCAAYACgqBIitaAMsCAB8ABwpqIEIEAE0BABEAAwreJFYWADYBAAAA.Lola:BAAANQAECggIEAABNQAFFAYIEgACAOwfAA==.Lolbrez:BAAANQAECggICwAAAA==.',
Lu='Luminovian:BAAANQADCgQIBAAAAA==.Lunanarn:BAAANQADCgIIAwAAAA==.Lunaria:BAAANQAFFAEIAQABNQAFFAYIEgACAOwfAA==.Lusty:BAABNQAECn8iAAIKAAkK6BYEEQBFAgAKAAkK6BYEEQBFAgAAAA==.Luxe:BAAANQAECgIIAgABNQAFFAYIEgACAOwfAA==.',
Ma='Macediin:BAABNQAECn8tAAIHAAoKoBhVGgAUAgAHAAoKoBhVGgAUAgAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECn8bAAIeAAkKiByaHABwAgAeAAkKiByaHABwAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgkJJgASAM8ZAA==.Magnolìa:BAAANQAECgUICQAAAA==.Malefic:BAAANQAECgQIBgABNQAFFAgIGwAGAE0eAA==.Malthael:BAABNQAECn8yAAMHAAoKWReHPQApAgAHAAoKqBaHPQApAgAcAAgKlg0nUwBjAQAAAA==.Mamageek:BAAANQAECggIEwAAAA==.Mami:BAAANQAECgIIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECgoKOgAMAPkhAA==.Manix:BAABNQAECn81AAQIAAkKnR6kFAAUAwAIAAkKnR6kFAAUAwAOAAIKsAgOmwEzAAAYAAEKiwW5bQAnAAAAAA==.Mareo:BAAANQAECgQIBwAAAA==.Marksterique:BAABNQAECn8mAAISAAkKzxmaGQCKAgASAAkKzxmaGQCKAgAAAA==.Masochist:BAAANQAECgMIAwAAAA==.Mausko:BAAANQAECgcIBwAAAA==.',
Me='Meeko:BAACNQAFFH8WAAIJAAkK+BUyBAA5AgAJAAkK+BUyBAA5AgA1AAQKf14AAgkACgqKIuoDAF4DAAkACgqKIuoDAF4DAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgQIBQAAAA==.Metalbound:BAAANQAECgcIDgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAABNQAECn8cAAIdAAgKqSSzBgAZAwAdAAgKqSSzBgAZAwAAAA==.Misslobster:BAABNQAECn8WAAILAAcKpA76oQAxAQALAAcKpA76oQAxAQAAAA==.',
Mo='Mokoko:BAABNQAECn8wAAIKAAoKdhw3CwC0AgAKAAoKdhw3CwC0AgAAAA==.Mokolock:BAAANQAECgYICAABNQAECgoKMAAKAHYcAA==.Moomoo:BAABNQAECn8oAAIZAAkKFh4dFQAeAwAZAAkKFh4dFQAeAwAAAA==.Moondough:BAAANQADCgEIAQAAAA==.Moorlin:BAAANQAECgYIDQAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgoKMAAKAHYcAA==.',
Mu='Mumra:BAAANQADCgUIBQAAAA==.',
My='Myka:BAAANQAECggIDgABNQAECgkJNQAIAJ0eAA==.Mysticphatty:BAAANQADCggJCAABNQAECgIIAgANAAAAAA==.Myyst:BAAANQAECgQIBQAAAA==.',
Na='Nanaka:BAAANQAECgUIBQABNQAECgYIDgANAAAAAA==.Nanook:BAAANQADCgcIBwAAAA==.Nawtalhere:BAAANQADCgQIBAABNQAECgoKLQAPAFAiAA==.',
Ne='Necro:BAABNQAECn8fAAIHAAkKix3WIwCzAgAHAAkKix3WIwCzAgAAAA==.Necrota:BAABNQAECn8ZAAMPAAkKZxoCMwBCAgAPAAkK4hgCMwBCAgAHAAEKOiGUxABiAAABNQAFFAgIGwAGAE0eAA==.Nekronomicon:BAAANQADCggICgABNQAECgoKQQAVAMgZAA==.Neuron:BAACNQAFFH8XAAMCAAgKAhvIAgBlAgACAAgKAhvIAgBlAgAZAAQKUAd5FwDyAAA1AAQKfycAAwIACgpPHQsSAMACAAIACgpPHQsSAMACABkABgpGEFpXAHkBAAAA.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAABNQAECn8/AAIDAAkKuSDFCADtAgADAAkKuSDFCADtAgAAAA==.Nightflame:BAAANQAECgUICAAAAA==.Ninjavc:BAABNQAECn8kAAIFAAkKkwrvGABeAQAFAAkKkwrvGABeAQAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAABNQAECn8ZAAIQAAkK3QntewBrAQAQAAkK3QntewBrAQAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQAECgcICQAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Olpheux:BAAANQAECgQIAwAAAA==.',
On='Onayro:BAAANQABCgIIAgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgYIDAAAAA==.Oreyn:BAABNQAECn8YAAMjAAkKEhYeEwBHAQAjAAYKshkeEwBHAQAUAAgKcA43oAA9AQAAAA==.Organ:BAABNQAECn8VAAQjAAkKegt5GAD+AAAjAAcKcAx5GAD+AAAkAAUKywORMACxAAAUAAcKtgf45QCoAAAAAA==.Orngar:BAAANQADCgMIAwAAAA==.',
Pa='Padle:BAABNQAECn8hAAMWAAoKZxKRFQAIAgAWAAoKZxKRFQAIAgAgAAUKHhYPCABBAQAAAA==.Paladín:BAABNQAECn87AAMYAAoKxhe8FgDHAQAYAAkKcxm8FgDHAQAOAAcK2g9K4QAbAQAAAA==.Palazar:BAACNQAFFH8HAAIOAAQK2xIKFwDUAAAOAAQK2xIKFwDUAAA1AAQKfzEAAg4ACgrKIP8yAAADAA4ACgrKIP8yAAADAAAA.Paoka:BAAANQADCgQIBwABNQADCggIGQANAAAAAA==.Pappamidnite:BAAANQAECggICAAAAA==.Pargonz:BAABNQAECn9TAAMBAAoKzyARBgAjAwABAAoKzyARBgAjAwAFAAIKlw6sjwBzAAAAAA==.Patoko:BAABNQAECn8tAAIdAAkKsB2ACgDKAgAdAAkKsB2ACgDKAgAAAA==.Paxwet:BAABNQAECn8gAAIOAAoKWw/FewDWAQAOAAoKWw/FewDWAQAAAA==.Payn:BAAANQAECgcIDQAAAA==.Paypay:BAABNQAECn82AAICAAkKFx+gCQAsAwACAAkKFx+gCQAsAwAAAA==.',
Ph='Phalannx:BAAANQAECgQIBgAAAA==.Philipx:BAAANQAECgEIAQAAAA==.Phinks:BAAANQADCgIIAgABNQAECgoKVAAdAIolAA==.Phráxas:BAAANQAECgEIAQABNQAFFAMIBgAGAFEQAA==.',
Pi='Piglittle:BAAANQAECgYIDQAAAA==.Pindad:BAABNQAECn8nAAITAAoKMSQlDQB2AwATAAoKMSQlDQB2AwAAAA==.',
Pl='Plzdispelme:BAABNQAECn86AAMIAAoKFh4jKACKAgAIAAoKFh4jKACKAgAOAAEKAACWpgE0AAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAABNQAECn8fAAIaAAkKaBAwDwAIAgAaAAkKaBAwDwAIAgAAAA==.',
Pr='Priesticles:BAABNQAECn8ZAAIVAAoKxgiZZACyAQAVAAoKxgiZZACyAQABNQADCgcIFwANAAAAAA==.Proshvam:BAAANQAECgEIAQAAAA==.Prym:BAABNQAECn8tAAMIAAoK7w3FXAClAQAIAAoK7w3FXAClAQAOAAEKGwHyugEXAAAAAA==.',
Pu='Purrzac:BAABNQAECn8tAAIDAAoK1SGkBAAZAwADAAoK1SGkBAAZAwABNQAECgoKOgAIABYeAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Racialskill:BAAANQAECggICQABNQAECgoKOgAIABYeAA==.Ragingmonkx:BAABNQAECn8jAAIXAAkK7hXlIAAlAgAXAAkK7hXlIAAlAgAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Ravenious:BAAANQAECggICAAAAA==.Raventer:BAABNQAECn8aAAITAAgKhw70pAC8AQATAAgKhw70pAC8AQAAAA==.Razdrood:BAAANQADCgcIBgABNQAECgcIGwAQAI8MAA==.Razlock:BAABNQAECn8bAAIQAAcKjwyIogARAQAQAAcKjwyIogARAQAAAA==.Razorclaws:BAAANQAECgQIBwAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYICQAAAA==.',
Ri='Riggamortie:BAABNQAECn82AAIHAAkKhh4wDAC0AgAHAAkKhh4wDAC0AgAAAA==.Risky:BAAANQAECggIBwAAAA==.',
Ro='Roguesucks:BAAANQADCggIDQAAAA==.Roller:BAAANQAECggIEAABNQAECgoKTAAdADAkAA==.Rollos:BAABNQAECn84AAIQAAoKHx0cKwBiAgAQAAoKHx0cKwBiAgAAAA==.Rot:BAAANQADCggICAAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAACNQAFFH8VAAMGAAgKsR3GBQBnAgAGAAcKSB3GBQBnAgARAAEKux+ICwBfAAA1AAQKfxYAAgYABQqKJeyGAJoBAAYABQqKJeyGAJoBAAAA.Ryujinsimp:BAACNQAFFH8MAAMKAAUKURr8BAB2AQAKAAUKURr8BAB2AQAnAAQKrxR/BgAbAQA1AAQKfyIAAycACQq/JO0DANwCAAoACQo1IsIIAOoCACcACAo9JO0DANwCAAE1AAUUCAgVAAYAsR0A.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMIAwANAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAcIFgAVAB4XAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECn8jAAIJAAkKggwRHwDiAQAJAAkKggwRHwDiAQAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgIIAgAAAA==.',
Se='Seer:BAACNQAFFH8QAAQiAAcKEhOjBAClAAAiAAMKmhGjBAClAAAQAAMKrBciMwCPAAAaAAEK0AxjHgBLAAA1AAQKf90ABCIACgr8JTgBABUDABAACAr6JbQPAFQDACIACgrzJDgBABUDABoACAoDJDAEAOwCAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAFFAMIBQASAIoKAA==.Shamanigans:BAAANQADCggIEgAAAA==.Shangzha:BAABNQAECn9MAAIdAAoKMCTkAQBIAwAdAAoKMCTkAQBIAwAAAA==.Shareholder:BAEBNQAECn8vAAIQAAoKmiT+CgB1AwAQAAoKmiT+CgB1AwABNQAFFAYICQAGAKoYAA==.Shiivera:BAABNQAECn8rAAILAAoKmh3AMQCZAgALAAoKmh3AMQCZAgAAAA==.Shimada:BAABNQAECn8wAAITAAoKexzmKAD0AgATAAoKexzmKAD0AgAAAA==.Shotsyll:BAACNQAFFH8IAAITAAMKfRTfFgADAQATAAMKfRTfFgADAQA1AAQKfxgAAhMACAqtG1WMAPIBABMACAqtG1WMAPIBAAAA.',
Sk='Skarín:BAAANQADCgMIAQAAAA==.Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAABNQAECn89AAMFAAoKcR30CABWAgABAAoKAxtGIQCGAgAFAAkKYRz0CABWAgAAAA==.Skynomad:BAAANQAECgYIEgAAAA==.',
Sl='Slyde:BAABNQAECn8hAAIHAAcKWyOsJQCoAgAHAAcKWyOsJQCoAgAAAA==.',
Sm='Smalldk:BAACNQAFFH8KAAMPAAIKAAAzJwBdAAAPAAEKAAAzJwBdAAAHAAEKAAB2JQA2AAA1AAQKfxcAAwcACgo/FENkAH8BAAcACgqvEUNkAH8BAA8ABQoYHdxnAFMBAAE1AAUUBggSAA4AsRUA.Smallrichard:BAAANQAECgEIAQABNQAECgoKLAAGAEgXAA==.Smashytash:BAABNQAECn8kAAIjAAoK/hkXBgBqAgAjAAoK/hkXBgBqAgAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgoKJAAjAP4ZAA==.',
Sn='Snek:BAAANQAECgEIBAAAAA==.Snowing:BAAANQAECgYIDwABNQAECgkJGAAHAHYWAA==.Snugglybear:BAABNQAECn82AAIDAAoKWCaVAACMAwADAAoKWCaVAACMAwABNQAFFAQIDAAPAFseAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Sodlid:BAAANQAECgcIDQAAAA==.Solariaa:BAAANQAECgMIAwABNQAFFAYIEgACAOwfAA==.Solborne:BAAANQABCgQIBgAAAA==.Solfreid:BAAANQAECgYIEAAAAA==.Sophism:BAABNQAECn8WAAMFAAoKeBd7LAA1AgAFAAoK+BN7LAA1AgABAAYKARaQdABLAQABNQAFFAgIIAAfAAgWAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAPAFAmAA==.Soulfang:BAABNQAECn85AAIjAAoKiBZbCQALAgAjAAoKiBZbCQALAgAAAA==.Soulfox:BAAANQADCgQIBAABNQAECggIEQANAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulripper:BAAANQAECggIDgAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAABNQAECn8jAAILAAoK0BxTGADzAgALAAoK0BxTGADzAgABNQAFFAQIBQABAOwFAA==.Sprocketrot:BAABNQAECn8eAAMcAAkKZhm7KQAPAgAcAAkKEBW7KQAPAgAHAAUKgx3oWwCgAQAAAA==.',
Sq='Squidmonk:BAABNQAECn8eAAIhAAkKHBFxGwDLAQAhAAkKHBFxGwDLAQAAAA==.',
St='Stardrive:BAACNQAFFH8PAAIUAAUK5QfHIAD6AAAUAAUK5QfHIAD6AAA1AAQKfyYAAhQACgphEll/AB0CABQACgphEll/AB0CAAAA.Steelwhacka:BAABNQAECn8VAAMXAAgK7gs8MgCFAQAXAAgK7gs8MgCFAQAhAAUKgwtxMgDWAAAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFH8aAAIXAAgK9RagBAD2AQAXAAgK9RagBAD2AQA1AAQKfyoAAhcACgqaIiMUALYCABcACgqaIiMUALYCAAAA.Stormdealer:BAAANQAECgYIBgAAAA==.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAABNQAECn8YAAQQAAoKjQ0PzgAuAQAQAAgKTQ0PzgAuAQAaAAIKTQ61WgBwAAAiAAIKuQuoLQA7AAAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQAECgYIBwABNQAECgYIEgANAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgYIDAAAAA==.Surtur:BAABNQAECn9bAAMUAAoKGB2sNgBlAgAUAAoKGB2sNgBlAgAkAAcKcBDfGgAvAQAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECgoKOwAYAMYXAA==.Swoobs:BAAANQAECgcIBwABNQAFFAQICwAHADwEAA==.',
Sy='Sygismund:BAABNQAECn81AAMmAAoKpQZDPwA9AQAmAAoKpQZDPwA9AQAeAAIK3ADGXwAPAAAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAACNQAFFH8IAAITAAQK9A+EFgDeAAATAAQK9A+EFgDeAAA1AAQKfz8AAhMACgpfHickAAYDABMACgpfHickAAYDAAAA.Tandalil:BAAANQADCgUIBQAAAA==.Tanglefoot:BAAANQAECgUIBgAAAA==.Taotien:BAAANQAECgcICwAAAA==.Tashbringer:BAAANQAECgIIBQABNQAECgoKJAAjAP4ZAA==.Tashvoker:BAAANQAECgYIBgAAAA==.',
Tc='Tchaik:BAABNQAECn8yAAMVAAoKZCA4FQAmAwAVAAoKZCA4FQAmAwAWAAIK7hSMWwBDAAAAAA==.',
Te='Teccnicality:BAAANQAECgUICgAAAA==.Tecknicaliti:BAAANQAECgYIBwAAAA==.Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgUIEgAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQAECgMIBgAAAA==.Theios:BAABNQAECn8lAAIUAAgK1gwwlwBRAQAUAAgK1gwwlwBRAQABNQAECgkJNwAHAL8WAA==.Thickthang:BAABNQAECn82AAMdAAoK+yNuAgCFAwAdAAoK+yNuAgCFAwAMAAQKrhYp3gDZAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECn9cAAMlAAoKgCRxAQAzAwAlAAoKgCRxAQAzAwAeAAEKAAALZAAAAAAAAA==.Timewarp:BAAANQAECggICAABNQAECgoKUgAXABofAA==.Tinytea:BAABNQAECn9SAAMXAAoKGh8eCwCuAgAXAAoKGh8eCwCuAgAoAAEKAABiLQBSAAAAAA==.Tinytilted:BAAANQADCgEIAQAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgcIDQAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAABNQAECn9GAAIQAAoKpA+3TgDoAQAQAAoKpA+3TgDoAQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgYIBgABNQAECgUICAANAAAAAA==.',
Tr='Trilicia:BAABNQAECn8cAAMFAAoK9hXyFQB9AQAFAAoK/BTyFQB9AQABAAcKNxBsfwAqAQAAAA==.Trusinner:BAABNQAECn8bAAIUAAgKRxjdbgBGAgAUAAgKRxjdbgBGAgAAAA==.',
Ts='Tsusha:BAEBNQAECn8UAAIMAAYKEw4VowBPAQAMAAYKEw4VowBPAQABNQAECggIFQAOAPUHAA==.',
Tu='Turkeyleg:BAAANQADCggIHwAAAA==.',
Tw='Twippy:BAABNQAECn8oAAIMAAoKKRP8TABDAgAMAAoKKRP8TABDAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQAECgUIBQAAAA==.Tyriam:BAABNQAECn8/AAIOAAoK8R03RQDFAgAOAAoK8R03RQDFAgAAAA==.',
Ud='Udderchaos:BAABNQAECn8YAAISAAoK8QhPHACbAQASAAoK8QhPHACbAQAAAA==.',
Un='Undeadboss:BAAANQAECgIIAgABNQAECggIEQANAAAAAA==.Unifey:BAAANQAECgYIBwAAAA==.',
Va='Valess:BAAANQAECgIIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAACNQAFFH8TAAIKAAYK/hfnAQAoAQAKAAYK/hfnAQAoAQA1AAQKfzwAAgoACgqyIFsHAAwDAAoACgqyIFsHAAwDAAAA.Verso:BAABNQAECn8pAAIpAAoKCxfOBgBZAgApAAoKCxfOBgBZAgAAAA==.',
Vi='Vitalithry:BAABNQAECn8qAAMnAAoKpxc3BgBrAgAnAAoKpxc3BgBrAgAKAAQK2hGkFQDcAAAAAA==.Vivii:BAAANQAECgcICwAAAA==.Vizzysmash:BAAANQAECgYIBgABNQAECgoKRAAHAJ4dAA==.',
Vo='Voden:BAAANQABCgUICAAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.Watpex:BAAANQAECgQIBAAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECn9LAAMcAAoKPBoCKQBRAgAcAAoKPBoCKQBRAgAPAAUKoA9vjADQAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAABNQAECn86AAMMAAoK+SGuGAClAgAMAAoK+SGuGAClAgALAAMKqxTn2wCwAAAAAA==.Whiteshadow:BAAANQAECgUIDQAAAA==.',
Wi='Wiiska:BAACNQAFFH8OAAMWAAYK3RTcBwAbAQAWAAUKsBDcBwAbAQAVAAEKXwAvOABDAAA1AAQKfzgAAxYACgrPHckUAL0CABYACgrPHckUAL0CABUABwpkCoSjAPMAAAAA.Wildling:BAAANQADCgIIAwAAAA==.Windoelicker:BAAANQADCgcIFwAAAA==.',
Wo='Worgya:BAAANQAECgQIAwABNQAECggIEQANAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgoKJwATADEkAA==.Wrlccywhefr:BAABNQAECn81AAQBAAoK0yN6IQCFAgABAAgKfCF6IQCFAgAFAAcKwiPYIgBwAgApAAYKph/HCQDnAQAAAA==.',
Wu='Wuggles:BAABNQAECn8eAAICAAkKORdHGgBnAgACAAkKORdHGgBnAgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAABNQAECn8nAAITAAkKPhxHdwAhAgATAAkKPhxHdwAhAgAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwAUAEcYAA==.',
Xy='Xyklon:BAAANQADCgQIBAAAAA==.',
Ya='Yahmon:BAABNQAECn8gAAILAAoKpg8UUADSAQALAAoKpg8UUADSAQAAAA==.',
Ye='Yetil:BAABNQAECn8ZAAIIAAkK9w47fACkAQAIAAkK9w47fACkAQAAAA==.',
Yn='Ynotraw:BAACNQAFFH8FAAIUAAMKEhkSGgDhAAAUAAMKEhkSGgDhAAA1AAQKfzIAAhQACgocIo8MAJMDABQACgocIo8MAJMDAAAA.Ynotstorm:BAAANQAECgQIBAAAAA==.',
Yo='Yourephired:BAABNQAECn8rAAMRAAoKvhBXDgCvAQARAAoKvhBXDgCvAQAGAAEKAAAp2gEoAAAAAA==.',
Za='Zaerix:BAAANQADCgYICQAAAA==.Zaknafein:BAAANQAECgUICQABNQAFFAMIBgAGAFEQAA==.Zarah:BAAANQAECgEIAQAAAA==.Zaycursed:BAAANQAECgQICgABNQAECggIHgAMABQfAA==.Zaydream:BAAANQADCgcIBwABNQAECggIHgAMABQfAA==.Zaylight:BAAANQADCggICAABNQAECggIHgAMABQfAA==.Zayseer:BAABNQAECn8eAAIMAAgKFB+TOACUAgAMAAgKFB+TOACUAgAAAA==.',
Ze='Zello:BAABNQAECn8yAAMVAAoKDAw7YwC2AQAVAAkKvAw7YwC2AQAWAAUKTwXnYAB+AAAAAA==.',
Zh='Zhengy:BAABNQAECn8VAAIaAAYKFhFgCgAgAQAaAAYKFhFgCgAgAQABNQAFFAMIBgAGAFEQAA==.',
Zi='Ziggybeast:BAABNQAECn8jAAQZAAoKWx1dNwAyAgAZAAgK/R1dNwAyAgACAAgKqRooJAAEAgADAAEKAADIZAArAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAABNQAECn8jAAMkAAgK+AfgKQCwAAAkAAcKEwjgKQCwAAAUAAUKeQRm5wClAAAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggIHgAMABQfAA==.',
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
