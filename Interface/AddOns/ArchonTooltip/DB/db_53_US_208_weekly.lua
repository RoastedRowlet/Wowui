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
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aanna:BAAANQAECgMIAwAAAA==.',
Ab='Abandonedcat:BAAANQAECggIDQABNQAECgoKNQABANMjAA==.Abor:BAABNQAECn8cAAQCAAoK/QNLQQAdAQACAAoK/QNLQQAdAQADAAgKSgbfMwDGAAAEAAMKSgq2LwCUAAAAAA==.Abuela:BAABNQAECn8zAAMFAAoKKR5sDQAZAwAFAAoKvxxsDQAZAwABAAgKnBeDKgAfAgAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ad='Adaela:BAAANQADCgIIAgABNQAECgkJMgAFAAEfAA==.',
Ae='Aegla:BAABNQAECn8zAAIGAAkKvxYWHwC2AQAGAAkKvxYWHwC2AQAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ag='Aghlath:BAAANQAECgYICAAAAA==.',
Ak='Akiko:BAAANQAECgYIDQABNQAECgoKMgAHAGodAA==.',
Al='Alastina:BAAANQAECgIIAgAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFH8QAAIIAAQKQxKVEADjAAAIAAQKQxKVEADjAAA1AAQKfy0AAwgACgq9Gj0NANICAAgACQrTHD0NANICAAkAAQruCO4iAC8AAAAA.Alliar:BAABNQAECn8sAAMKAAoKFh0nKwC2AgAKAAoKFh0nKwC2AgALAAYKPwl5rAA7AQAAAA==.Allynstraza:BAABNQAECn8VAAIIAAYKARClKgBYAQAIAAYKARClKgBYAQAAAA==.',
Am='Amgems:BAAANQAECgQIBQABNQAECgcIDQAMAAAAAA==.Amordred:BAAANQAECgQIEQAAAA==.',
An='Anasterion:BAABNQAECn8VAAINAAgK8CAlbgBUAgANAAgK8CAlbgBUAgAAAA==.Andarus:BAABNQAECn8fAAINAAcKvxihgACLAQANAAcKvxihgACLAQABNQAECgoKQwAOABIcAA==.Andrøgyny:BAAANQADCgEIAQAAAA==.Ankles:BAABNQAECn8nAAMPAAkKfiPRBwB/AwAPAAkKfiPRBwB/AwAGAAIK+glCzwBPAAAAAA==.Ansley:BAAANQADCgUICgABNQAECgkJMgAFAAEfAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgYICwABNQAECgoKSgAQAG8fAA==.',
As='Ashli:BAABNQAECn8yAAMFAAkKAR9pCQAeAgAFAAgKxiBpCQAeAgABAAgKDBjwLQANAgAAAA==.Astiri:BAACNQAFFH8HAAIRAAYKLRPxAAA2AQARAAYKLRPxAAA2AQA1AAQKfxQAAhEACgomHyYCAOICABEACgomHyYCAOICAAAA.',
At='Atlasbär:BAAANQAECgUIBAABNQADCgYIDwAMAAAAAA==.Atlasdark:BAABNQAECn8ZAAIKAAoKPxx+LABCAgAKAAoKPxx+LABCAgABNQADCgYIDwAMAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.Atreyu:BAAANQAECgcIAgAAAA==.',
Az='Azgrom:BAAANQADCgEIAQAAAA==.',
Ba='Balrock:BAAANQAECgIIBQAAAA==.Balthromaw:BAABNQAECn8zAAIQAAoKDhvoIQBlAgAQAAoKDhvoIQBlAgAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQAMAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECgQIBAABNQAFFAMIBQASAIoKAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belfdelphine:BAAANQAECgcICgAAAA==.Bellum:BAAANQAECgcIEQAAAA==.Belstab:BAABNQAECn8tAAMBAAgK/g/XGwD3AQABAAgKhw/XGwD3AQAFAAcKcwkNTgCHAQAAAA==.Bethevangel:BAAANQADCgEIAgAAAA==.Betrayer:BAAANQAECgcIEAABNQAECgoKIgATAKEjAQ==.',
Bg='Bgbalkoth:BAAANQADCgYIDAAAAA==.',
Bi='Bifurthegrey:BAAANQAECgUIBAAAAA==.Bigblammy:BAAANQADCggICQABNQAFFAcIGQAOACAfAA==.Biophage:BAAANQAECgQICwAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQABNQAECgYIEQAMAAAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Blinkss:BAAANQAECgYIBgAAAA==.Bloodavenger:BAABNQAECn8dAAMHAAkKZgx0ZgDkAQAHAAkKZgx0ZgDkAQANAAUK9wb3KgHZAAAAAA==.Bloodemongar:BAABNQAECn8WAAIGAAkKvg5RZgB3AQAGAAkKvg5RZgB3AQAAAA==.Bloodhoundss:BAABNQAECn8kAAIUAAoK4xXTRwD5AQAUAAoK4xXTRwD5AQAAAA==.Blössöm:BAAANQAECgYIDAAAAA==.',
Bo='Bobdk:BAACNQAFFH8eAAMGAAcKvBwFBAD0AQAGAAcKvBwFBAD0AQAPAAEKAADsOAAgAAA1AAQKfzkAAgYACgp+JNoGAPACAAYACgp+JNoGAPACAAAA.Bomboklaat:BAAANQADCgMIBwAAAA==.Bonejangles:BAAANQAECgQICAAAAA==.Boomfrin:BAAANQAECgUICgAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECn8lAAMVAAkK6BA6WQAWAgAVAAkK6BA6WQAWAgAWAAEKXAWlewAxAAAAAA==.',
Br='Braegen:BAABNQAECn8dAAMTAAkKVRRCUADtAQATAAkKVRRCUADtAQASAAEKPgYfXwAyAAABNQAECgoKQwAOABIcAA==.Brewslee:BAAANQADCggICAAAAA==.Brewsleê:BAAANQAECgQIBAAAAA==.Bruceleett:BAABNQAECn86AAIXAAkKohHuFgDIAQAXAAkKohHuFgDIAQABNQADCgcIFwAMAAAAAA==.',
Bu='Buffmeister:BAAANQAECgUIBQAAAA==.Bullioss:BAABNQAECn8XAAMNAAgKlxm2bgCzAQANAAcKlxm2bgCzAQAYAAMKGxj2RQDYAAABNQAECgoKIgATAKEjAA==.',
['Bà']='Bàtman:BAAANQADCgUIBQAAAA==.',
['Bè']='Bètrayèr:BAAANQAECgEIAgAAAA==.',
['Bö']='Böbbyboucher:BAABNQAECn8hAAILAAgKux20PwB2AgALAAgKux20PwB2AgAAAA==.',
Ca='Cainn:BAAANQADCggIFQABNQAECgkJKgANABYYAA==.Caldrid:BAAANQADCgYIDwAAAA==.Calfurion:BAABNQAECn8VAAMEAAgKqB3zEAD4AQAZAAcKShxEPwAAAgAEAAYK1B7zEAD4AQAAAA==.Calvary:BAAANQAECggIDwABNQAECggIFQAEAKgdAA==.Capncrunch:BAAANQADCgYICwAAAA==.Cardiganz:BAAANQABCgUIBQAAAA==.Carving:BAAANQAECgEIAQAAAA==.Cazleah:BAABNQAECn84AAILAAoKkyEOGQAzAwALAAoKkyEOGQAzAwAAAA==.',
Ce='Cessatio:BAABNQAECn8hAAIaAAYK4guAEQCxAAAaAAYK4guAEQCxAAAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAABNQAECn8tAAINAAoKYhuUTAAQAgANAAoKYhuUTAAQAgABNQAECgoKUgABAM8gAA==.Chowming:BAAANQAECgEIAgAAAA==.Chrisbrewn:BAABNQAECn8kAAIUAAkKzhMkcgA+AgAUAAkKzhMkcgA+AgAAAA==.Chudlord:BAAANQADCgEIAQAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clamsweat:BAAANQADCgEIAQAAAA==.Clevelandoe:BAACNQAFFH8FAAISAAMKigoPGQC5AAASAAMKigoPGQC5AAA1AAQKfzkAAxIACQpIJGEOAPwCABIACQq6IWEOAPwCABMABQoUHMKnALYBAAAA.',
Co='Cobbknob:BAAANQAECgUICAAAAA==.Cocobear:BAAANQAECgEIAQAAAA==.Coeurdeleon:BAABNQAECn8dAAMNAAoKTxTxhAAeAgANAAoKTxTxhAAeAgAYAAEKAAC2ZgBHAAAAAA==.Cokakilla:BAAANQADCgUIBAAAAA==.Condemnation:BAABNQAECn89AAIVAAoKvxnFOACFAgAVAAoKvxnFOACFAgAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgYICgABNQADCggIDQAMAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQAMAAAAAA==.Coriantumr:BAAANQADCgYICAAAAA==.',
Cr='Creampuff:BAAANQADCgEIAQAAAA==.Critneyfear:BAAANQAECgQIBQAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbazar:BAAANQAECgEIAwAAAA==.Curbstomped:BAABNQAECn8kAAQTAAoKjBQzbwAzAgATAAoKjBQzbwAzAgASAAMK7gN0bgB2AAAbAAEKAACnEwAAAAAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgYIDwABNQAFFAgIFQAOALEdAA==.Darkvizzy:BAABNQAECn9CAAQGAAoKnh3jEwApAgAGAAkKsR3jEwApAgAPAAkKVhGIKwB/AQAcAAQKQg4EfQB/AAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deadmeatcow:BAAANQADCgEIAQAAAA==.Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgYICAAAAA==.Demiplo:BAABNQAECn8oAAITAAkKyBSFegAZAgATAAkKyBSFegAZAgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQAMAAAAAA==.Denelak:BAABNQAECn8hAAMTAAoKZx8QEgBYAwATAAoK2x0QEgBYAwASAAkKcxcqGQCOAgAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAABNQAECn8VAAIOAAoKThe+tgAWAgAOAAoKThe+tgAWAgABNQAECgoKMwAFACkeAA==.',
Di='Dirtycasual:BAAANQAECggIEAABNQAECgoKMwAFACkeAA==.Discipline:BAABNQAECn84AAMYAAoK0Bv7DAAqAgAYAAoK0Bv7DAAqAgANAAgKchU8mQDxAQAAAA==.',
Do='Doggo:BAAANQAECgEIAQAAAA==.Dotsurdead:BAAANQAECggIDQAAAA==.',
Dr='Dratr:BAABNQAECn8qAAIdAAoK+AuoEwCVAQAdAAoK+AuoEwCVAQAAAA==.Draxyl:BAACNQAFFH8GAAMPAAIKSAaWHABZAAAPAAIKSAaWHABZAAAGAAEKnAClJgAsAAA1AAQKfzUAAw8ACgr3Ft8xAFoBAAYACQokD9pKAOoBAA8ACgoiFd8xAFoBAAAA.Drekhan:BAABNQAECn8VAAMPAAYKkAOcWwCuAAAPAAYKkAOcWwCuAAAcAAQK2wL1mQBgAAABNQAECgoKQwAOABIcAA==.Drfizzle:BAAANQAECgEIAQABNQAECgoKMAAUAAsgAA==.Drham:BAABNQAECn8kAAIeAAkKJQ4vKQD6AQAeAAkKJQ4vKQD6AQAAAA==.Drogbar:BAAANQAECgEIAQABNQAECgkJIwAXAO4VAA==.Drokos:BAAANQAECgYICwABNQAECgoKIgATAKEjAA==.Drtree:BAAANQADCgcIBwAAAA==.Druni:BAAANQADCgEIAQAAAA==.',
Du='Dunhambones:BAABNQAECn83AAIGAAoK4yEbEQAuAwAGAAoK4yEbEQAuAwAAAA==.Duo:BAABNQAECn80AAIfAAoKExTSAQBwAgAfAAoKExTSAQBwAgABNQAECgoKHAACAP0DAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Elcosote:BAAANQAECgcIDQAAAA==.Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQAECgYIDAAAAA==.Elminstr:BAAANQADCgYIBwAAAA==.Elowynn:BAABNQAECn8+AAQVAAoK+hLfUwCxAQAVAAoK+hLfUwCxAQAWAAIK6QGceQA1AAAgAAEK/gUdKQAyAAAAAA==.Elrey:BAAANQAECggICQABNQAECgoKMwAFACkeAA==.Elèctra:BAAANQAECggIEgAAAA==.',
En='Engraver:BAAANQAECgEIAwAAAA==.Enochs:BAAANQADCgIIAwAAAA==.Enyô:BAAANQADCgQIBAABNQAECggIIQALALsdAA==.',
Er='Erada:BAABNQAECn8zAAMRAAoKYyBbAgDWAgARAAoKYyBbAgDWAgAOAAkKsBSWjABmAgAAAA==.',
Ev='Evesong:BAAANQAECgEIAgAAAA==.Evoklando:BAAANQADCgUICgABNQAFFAMIBQASAIoKAA==.',
Ex='Exinquisitor:BAAANQADCgIIAwAAAA==.Exlo:BAAANQAECgEIAgAAAA==.Exorcism:BAAANQADCgcIDAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIAwABNQAECgoKHAACAP0DAA==.',
Fe='Felad:BAABNQAECn83AAMhAAoKXyV9AQDmAwAhAAoKXyV9AQDmAwAXAAEKAACXZwBAAAABNQAECggIDgAMAAAAAA==.',
Fh='Fhalanx:BAAANQAECggICgAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECggIDgABNQAECgoKGgALAMENAA==.Flappyy:BAABNQAECn8aAAMLAAoKwQ1GVABQAQALAAoKwQ1GVABQAQAKAAMKNAZ6+gB2AAAAAA==.Floh:BAAANQADCgEIAQAAAA==.Flowdinstuna:BAABNQAECn8jAAIeAAoKXRdCGgCHAgAeAAoKXRdCGgCHAgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIBQAAAA==.',
Fr='Framistina:BAABNQAECn8sAAITAAoK2BioRACdAgATAAoK2BioRACdAgAAAA==.Freakmage:BAAANQADCgUIBQAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.Friereñ:BAAANQAECgEIAQAAAA==.',
Fu='Furrybait:BAEANQAECggICQAAAA==.Furyiosa:BAABNQAECn8rAAIUAAoKrx4aIwCXAgAUAAoKrx4aIwCXAgAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgAMAAAAAA==.Gaiseric:BAABNQAECn8pAAIGAAkKsBq3PwAfAgAGAAkKsBq3PwAfAgAAAA==.Gamago:BAAANQAECggIBQAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECn8cAAQaAAkKix5CKAA2AQAQAAcKWBpmcQAMAgAaAAQKCh9CKAA2AQAiAAEKAADLKQBFAAAAAA==.Getoverhere:BAAANQADCggICwAAAA==.',
Gi='Girltank:BAAANQAECgIIBAAAAA==.',
Gn='Gnarlak:BAAANQAECgIIBwAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gorestomp:BAAANQAECggIDQAAAA==.Gotboned:BAAANQAECgcIDAABNQAFFAYIBgADAGMeAA==.Gotfleas:BAACNQAFFH8GAAIDAAYKYx6WAAA6AgADAAYKYx6WAAA6AgA1AAQKfycAAwMACgrvJSQBANsDAAMACgrJJSQBANsDAAQAAgoUE14sAG0AAAAA.',
Gr='Graxis:BAAANQADCgEIAQAAAA==.Grendaldh:BAABNQAECn8zAAIeAAoKexRIKQD5AQAeAAoKexRIKQD5AQAAAA==.Greyfax:BAABNQAECn8rAAIHAAoKFSJSGQATAwAHAAoKFSJSGQATAwAAAA==.Grimthruul:BAABNQAECn8oAAILAAoKHgfRjQCBAQALAAoKHgfRjQCBAQAAAA==.Grommkar:BAABNQAECn8jAAIUAAkKDg7IkADyAQAUAAkKDg7IkADyAQAAAA==.Groztok:BAAANQAECgEIAgAAAA==.Grumpig:BAAANQADCgQIDAAAAA==.Grèggory:BAAANQAECgQICAAAAA==.Gríffìths:BAAANQAECgEIAQAAAA==.',
Gu='Gulmolfson:BAAANQADCggIAQAAAA==.Gusari:BAEANQAECgEIAQABNQAECggIDgAMAAAAAA==.Gutx:BAAANQADCgQIBAAAAA==.',
Ha='Hadmeathello:BAAANQAECggICwAAAA==.Halucination:BAABNQAECn8dAAMWAAkK7wxiJAAOAgAWAAkK7wxiJAAOAgAVAAIKlwRr7QBcAAAAAA==.Harnan:BAAANQADCgEIAQAAAA==.Harthan:BAABNQAECn8fAAMUAAoKqBHFnQDSAQAUAAoKqBHFnQDSAQAjAAEKkQ6WKgA5AAAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayden:BAABNQAECn8bAAINAAoKpxwRWACOAgANAAoKpxwRWACOAgAAAA==.Hayleigh:BAAANQAECgQIBQAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwAMAAAAAA==.Helya:BAAANQADCgMIBgAAAA==.Henchman:BAAANQABCgQICAABNQAECgoKIgATAKEjAA==.Hetzák:BAABNQAECn8sAAIZAAoKYhFzOgAfAgAZAAoKYhFzOgAfAgAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBgAAAA==.Hintolisu:BAACNQAFFH8FAAIEAAMKYw5cAgCOAAAEAAMKYw5cAgCOAAA1AAQKfzoAAgQACgr7HjcGAA0DAAQACgr7HjcGAA0DAAAA.',
Ho='Hobbess:BAABNQAECn8UAAIeAAgK9BB3LADeAQAeAAgK9BB3LADeAQABNQAFFAoKKwAZAO4gAA==.Holybaloney:BAABNQAECn8jAAMYAAoKeRzKEQCEAgAYAAgKFx/KEQCEAgANAAkKtAjopQBCAQAAAA==.Holycrit:BAAANQADCgMIBAAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Holyvaj:BAAANQAECggIEgAAAA==.Hongis:BAAANQAECgEIAQAAAA==.Hoofinit:BAABNQAECn8wAAIUAAoKCyBtKgARAwAUAAoKCyBtKgARAwAAAA==.',
Hu='Huatarm:BAABNQAECn8qAAIkAAoKuRgMDQBiAgAkAAoKuRgMDQBiAgAAAA==.',
Ia='Iadygaga:BAABNQAECn8gAAQVAAoKChJgawDcAQAVAAoKChJgawDcAQAWAAYKrhA0QQAnAQAgAAIKlQM6IwBPAAAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icejade:BAAANQADCggICAABNQAECgYIBgAMAAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECgkJMwAGAL8WAA==.',
In='Inue:BAAANQADCgEIAQAAAA==.',
Ir='Ironpaw:BAAANQADCgUICAAAAA==.Ironspin:BAAANQAECgQIBgAAAA==.Irønwølf:BAAANQADCgEIAQAAAA==.',
Is='Isisankh:BAAANQAECgQIBAAAAA==.Isolated:BAAANQAECggIAwABNQAECgoKMwAFACkeAA==.',
Ja='Jaark:BAACNQAFFH8PAAIQAAUKlxN9EwDgAAAQAAUKlxN9EwDgAAA1AAQKfzgAAxAACgoMIDomAOsCABAACgoMIDomAOsCACIAAwpOHQcXAI0AAAAA.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgUICgABNQAECgkJMgAFAAEfAA==.Jasparr:BAAANQADCgEIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jehanne:BAAANQADCgQIBgAAAA==.Jen:BAACNQAFFH8FAAIVAAMKIgpwJACIAAAVAAMKIgpwJACIAAA1AAQKf0MAAhUACgqQF/5OADgCABUACgqQF/5OADgCAAAA.',
Jo='Jocon:BAAANQAECgcIBgAAAA==.Jonnysnow:BAAANQADCgEIAQAAAA==.Joédirté:BAAANQAECgEIAQAAAA==.',
Ju='Jugulator:BAAANQADCggIEAAAAA==.Jumpey:BAABNQAECn8bAAMlAAcKMxZmEACrAQAlAAYKnhhmEACrAQAmAAUKEQufaQDSAAABNQAECgkJIgAJAOgWAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAABNQAECn8mAAILAAoKFhksMQC2AgALAAoKFhksMQC2AgABNQAECgQIBgAMAAAAAA==.Kanami:BAABNQAECn8lAAIUAAkKjhepPQAfAgAUAAkKjhepPQAfAgAAAA==.Kaynyx:BAABNQAECn8uAAIBAAoKCB3oBgAQAwABAAoKCB3oBgAQAwAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAABNQAECn8qAAINAAkKFhiqfAAxAgANAAkKFhiqfAAxAgAAAA==.Kemosabe:BAAANQADCgEIAQAAAA==.Kenzie:BAAANQAECgYICgAAAA==.Kerb:BAABNQAECn8vAAQPAAkK1w+GMwBRAQAPAAkK1w+GMwBRAQAcAAIK3gbXmQBgAAAGAAEKAAAn6AAsAAAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECn8aAAMeAAgK7hjYJwAFAgAeAAgK4xTYJwAFAgAmAAQKtBckYAD8AAAAAA==.',
Kh='Khallap:BAAANQADCgEIAQAAAA==.',
Ki='Kikiko:BAAANQAECgMIBAAAAA==.Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECn8WAAImAAgKDxfMMQAbAgAmAAgKDxfMMQAbAgAAAA==.Kitsurubami:BAAANQAECgUIBgABNQAECgkJMgAFAAEfAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQANAPAgAA==.',
Kl='Klaris:BAAANQAECgQIBAAAAA==.',
Kn='Knewtoomuch:BAAANQADCgcIBwAAAA==.',
Ko='Konjur:BAACNQAFFH8ZAAMOAAcKIB9pCwAdAgAOAAYK7h1pCwAdAgARAAIK/SBqBAC1AAA1AAQKfykAAg4ACgqDJXYOAAYDAA4ACgqDJXYOAAYDAAAA.Korpen:BAAANQADCgEIAQAAAA==.',
Kr='Krelock:BAAANQAECgYICgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgQIBwABNQAECgoKUQAkAC0aAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
Ky='Kytheon:BAAANQADCgIIAgAAAA==.',
['Kà']='Kàmó:BAAANQAECggIEAABNQAECgQIBgAMAAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgQIBgAAAA==.',
['Kä']='Kämo:BAAANQAECgIIAwABNQAECgQIBgAMAAAAAA==.',
La='Laelada:BAAANQAECgcICgAAAA==.Lagertha:BAAANQADCgcICAAAAA==.Lakey:BAAANQAECggIDQABNQAFFAYIEgACAOwfAA==.Lakeyy:BAACNQAFFH8SAAMCAAYK7B+2BACkAQACAAYK7B+2BACkAQAZAAEKfgQlHwA8AAA1AAQKfzUAAwIACgqbJY8CAKQDAAIACgqbJY8CAKQDABkABAppHdRzAPsAAAAA.Lakeyys:BAAANQAECgIIAQABNQAFFAYIEgACAOwfAA==.Lanuor:BAAANQADCgEIAQAAAA==.Laufey:BAAANQAECgYICQAAAA==.Lavagobrr:BAAANQAECgQIBAABNQAECggIEgAMAAAAAA==.Lawrence:BAACNQAFFH8TAAIKAAYKQRMACgB9AQAKAAYKQRMACgB9AQA1AAQKfy4AAwoACgrfHtYtAKsCAAoACgrfHtYtAKsCAAsABQooF7qoAIMAAAAA.',
Le='Lesaeria:BAABNQAECn8fAAIeAAkKkxlXGgCGAgAeAAkKkxlXGgCGAgABNQAECgoKRgAdAO4jAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQAECgIIAgAAAA==.Lightsardine:BAAANQADCgIIAgAAAA==.Lilikoii:BAAANQAECgIIBAABNQAFFAYIEgACAOwfAA==.Liljit:BAAANQAECgEIAgABNQAECgoKMgAHAGodAA==.Lilslaver:BAABNQAECn8fAAITAAkKnQdMfQB3AQATAAkKnQdMfQB3AQAAAA==.Limerence:BAAANQAECgcIBwAAAA==.Lindow:BAAANQAECgEIAQAAAA==.Lisex:BAACNQAFFH8LAAMcAAUKTwz9DAAPAQAcAAQKTwz9DAAPAQAPAAEKAAByNQApAAA1AAQKfyIAAxwACQpNIU0YAMgCABwACQpNIU0YAMgCAA8AAQoiFu3FAD0AAAE1AAUUBggRAAUA7w4A.Lithe:BAABNQAECn9IAAINAAoKEx6CLAAWAwANAAoKEx6CLAAWAwABNQAECgoKVwALAHsiAA==.',
Lo='Lockjhaw:BAAANQAFFAEIAQAAAA==.Locklear:BAABNQAECn84AAINAAkKAxcCZgDIAQANAAkKAxcCZgDIAQAAAA==.Logic:BAACNQAFFH8gAAQfAAgKCBYZAAAKAgAfAAYK8hYZAAAKAgAOAAYKYhM3EwDdAQARAAQKmxb/AgD3AAA1AAQKfzgABA4ACgozIytaAMsCAA4ACgqBIitaAMsCAB8ABwpqIBEDAFoBABEAAwreJPsQADsBAAAA.Lola:BAAANQAECgMIBQABNQAFFAYIEgACAOwfAA==.Lolbrez:BAAANQAECggIDAAAAA==.',
Lu='Luminovian:BAAANQADCgQIBAAAAA==.Lunanarn:BAAANQADCgIIAwAAAA==.Lunaria:BAAANQAFFAEIAQABNQAFFAYIEgACAOwfAA==.Lusty:BAABNQAECn8iAAIJAAkK6BYEEQBFAgAJAAkK6BYEEQBFAgAAAA==.Luthix:BAAANQAECgEIAQAAAA==.Luxe:BAAANQAECgIIBAABNQAFFAYIEgACAOwfAA==.',
Ma='Macediin:BAABNQAECn8tAAIGAAoKoBgAFQAdAgAGAAoKoBgAFQAdAgAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECn8bAAIeAAkKiByaHABwAgAeAAkKiByaHABwAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgkJJgASAM8ZAA==.Magnolìa:BAAANQAECgUICQAAAA==.Malefic:BAAANQAECgQICAABNQAFFAcIGQAOACAfAA==.Malthael:BAABNQAECn8uAAMGAAoKmxWHPQApAgAGAAoK5hSHPQApAgAcAAgKlg0nUwBjAQAAAA==.Mamageek:BAAANQAECggIEwAAAA==.Mami:BAAANQAECgIIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECgkJNAALALgiAA==.Manix:BAABNQAECn8fAAQHAAkKcRnaHQCdAgAHAAkKcRnaHQCdAgANAAIKsAjbbAE0AAAYAAEKiwVGYAAnAAAAAA==.Mareo:BAAANQAECgQIBwAAAA==.Marksterique:BAABNQAECn8mAAISAAkKzxmaGQCKAgASAAkKzxmaGQCKAgAAAA==.Masochist:BAAANQAECgMIAwAAAA==.',
Me='Meeko:BAACNQAFFH8TAAIIAAgKpRQyBAA5AgAIAAgKpRQyBAA5AgA1AAQKf1oAAggACgqKIscDAD4DAAgACgqKIscDAD4DAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgQIBgAAAA==.Metalbound:BAAANQAECgcIDgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBgAAAA==.Millican:BAABNQAECn8cAAIdAAgKqSSzBgAZAwAdAAgKqSSzBgAZAwAAAA==.Misslobster:BAABNQAECn8WAAIKAAcKpA76oQAxAQAKAAcKpA76oQAxAQAAAA==.Mistapoop:BAAANQADCgEIAQAAAA==.',
Mo='Mokoko:BAABNQAECn8wAAIJAAoKdhw3CwC0AgAJAAoKdhw3CwC0AgAAAA==.Mokolock:BAAANQAECgYICAABNQAECgoKMAAJAHYcAA==.Moomoo:BAABNQAECn8oAAIZAAkKFh4dFQAeAwAZAAkKFh4dFQAeAwAAAA==.Moondough:BAAANQADCgEIAQAAAA==.Moorlin:BAAANQAECgYIDgAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgoKMAAJAHYcAA==.',
Mu='Mumra:BAAANQADCgUIBQAAAA==.',
My='Myka:BAAANQAECggIDwABNQAECgkJHwAHAHEZAA==.Mysticphatty:BAAANQADCggJCAABNQAECgIIAgAMAAAAAA==.Myyst:BAAANQAECgQICAAAAA==.',
Na='Nanaka:BAAANQAECgYIBgAAAA==.Nawtalhere:BAAANQADCgQIBAABNQAECgoKLQAPAFAiAA==.',
Ne='Necro:BAABNQAECn8fAAIGAAkKix3WIwCzAgAGAAkKix3WIwCzAgAAAA==.Necrota:BAABNQAECn8ZAAMPAAkKZxoCMwBCAgAPAAkK4hgCMwBCAgAGAAEKOiGUxABiAAABNQAFFAcIGQAOACAfAA==.Nekronomicon:BAAANQADCggICgABNQAECgoKPQAVAL8ZAA==.Neuron:BAACNQAFFH8VAAMCAAcKxRnNAwAAAgACAAcKxRnNAwAAAgAZAAQKUAd5FwDyAAA1AAQKfycAAwIACgpPHQsSAMACAAIACgpPHQsSAMACABkABgpGEFpXAHkBAAAA.Nexdorei:BAAANQAECgEIAwAAAA==.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICQAAAA==.Nigdruu:BAABNQAECn84AAIDAAkKWCDFCADtAgADAAkKWCDFCADtAgAAAA==.Nightflame:BAAANQAECgUICAAAAA==.Ninjavc:BAABNQAECn8kAAIFAAkKkwqKFQBlAQAFAAkKkwqKFQBlAQAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noha:BAAANQADCgEIAQAAAA==.Noora:BAAANQAECgYIEgAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQAECgcICwAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Olpheux:BAAANQAECgQIBgAAAA==.',
On='Onayro:BAAANQADCgEIAQAAAA==.',
Op='Oprahwinfrey:BAAANQADCggICAAAAA==.',
Or='Oralys:BAAANQAECgYIDAAAAA==.Oreyn:BAABNQAECn8YAAMjAAkKEhalDgBRAQAjAAYKshmlDgBRAQAUAAgKcA6lhgBAAQAAAA==.Organ:BAABNQAECn8VAAQjAAkKegsfEwAGAQAjAAcKcAwfEwAGAQAkAAUKywORMACxAAAUAAcKtgd+zACpAAAAAA==.Orngar:BAAANQADCgMIBAAAAA==.',
Pa='Padle:BAABNQAECn8hAAMWAAoKZxKfEQAJAgAWAAoKZxKfEQAJAgAgAAUKHhZ0BgBGAQAAAA==.Paladín:BAABNQAECn87AAMYAAoKxhdHEQDYAQAYAAkKcxlHEQDYAQANAAcK2g+8twAiAQAAAA==.Palazar:BAACNQAFFH8FAAINAAMK2xIDHACQAAANAAMK2xIDHACQAAA1AAQKfzEAAg0ACgrKIP8yAAADAA0ACgrKIP8yAAADAAAA.Paoka:BAAANQADCgQICQABNQADCggIGwAMAAAAAA==.Pappamidnite:BAAANQAECggICAAAAA==.Pargonz:BAABNQAECn9SAAMBAAoKzyDBDQDvAgABAAoKzyDBDQDvAgAFAAIKlw6sjwBzAAAAAA==.Patoko:BAABNQAECn8tAAIdAAkKsB2ACgDKAgAdAAkKsB2ACgDKAgAAAA==.Paxwet:BAABNQAECn8VAAINAAoKDw3JdwCeAQANAAoKDw3JdwCeAQAAAA==.Payn:BAAANQAECggIDgAAAA==.Paypay:BAABNQAECn82AAICAAkKFx+gCQAsAwACAAkKFx+gCQAsAwAAAA==.',
Ph='Phalannx:BAAANQAECgQIBwAAAA==.Philipx:BAAANQAECgEIAQAAAA==.Phinks:BAAANQADCgIIAgABNQAECgoKUAAdAH8lAA==.Phráxas:BAAANQAECgEIAQABNQAECgoKQwAOABIcAA==.',
Pi='Piglittle:BAAANQAECgYIDQAAAA==.Pindad:BAABNQAECn8iAAITAAoKoSMlDQB2AwATAAoKoSMlDQB2AwAAAA==.',
Pl='Plzdispelme:BAABNQAECn8yAAMHAAoKah08LwCpAgAHAAoKah08LwCpAgANAAEKAACWpgE0AAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAABNQAECn8eAAIaAAgKIREwDwAIAgAaAAgKIREwDwAIAgAAAA==.',
Pr='Priesticles:BAABNQAECn8VAAIVAAoKYwezUwCyAQAVAAoKYwezUwCyAQABNQADCgcIFwAMAAAAAA==.Proshvam:BAAANQAECgEIAQAAAA==.',
Pu='Purrzac:BAABNQAECn8ZAAIDAAgKOh6jGQDcAQADAAgKOh6jGQDcAQABNQAECgoKMgAHAGodAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Racialskill:BAAANQAECggICQABNQAECgoKMgAHAGodAA==.Ragingmonkx:BAABNQAECn8jAAIXAAkK7hXlIAAlAgAXAAkK7hXlIAAlAgAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Ravenious:BAAANQAECggICAAAAA==.Raventer:BAABNQAECn8aAAITAAgKhw70pAC8AQATAAgKhw70pAC8AQAAAA==.Razdrood:BAAANQADCgcIBgABNQAECgcIFwAQAI8MAA==.Razlock:BAABNQAECn8XAAIQAAcKjwz0hwAXAQAQAAcKjwz0hwAXAQAAAA==.Razorclaws:BAAANQAECgQIBwAAAA==.Razpuutinn:BAAANQADCgEIAQAAAA==.',
Re='Redshift:BAAANQAECgEIAQAAAA==.Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAABNQAECn8tAAIGAAkKnBsuDwBjAgAGAAkKnBsuDwBjAgAAAA==.Risky:BAAANQAECggIBwAAAA==.',
Ro='Roguesucks:BAAANQADCggIDQAAAA==.Rollos:BAABNQAECn8yAAIQAAoKHx1gJQBTAgAQAAoKHx1gJQBTAgAAAA==.Roysmom:BAAANQADCgUICgAAAA==.',
Ry='Ryujinshin:BAACNQAFFH8VAAMOAAgKsR3GBQBnAgAOAAcKSB3GBQBnAgARAAEKux+ICwBfAAA1AAQKfxYAAg4ABQqKJTtvAKIBAA4ABQqKJTtvAKIBAAAA.Ryujinsimp:BAACNQAFFH8MAAMJAAUKURr8BAB2AQAJAAUKURr8BAB2AQAnAAQKrxR/BgAbAQA1AAQKfyIAAycACQq/JO0DANwCAAkACQo1IsIIAOoCACcACAo9JO0DANwCAAE1AAUUCAgVAA4AsR0A.',
['Rä']='Rävylock:BAAANQADCgEIAQABNQAECgMIAwAMAAAAAA==.',
Sa='Saeli:BAAANQADCgEIAQAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAYIFQAVAK0XAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECn8jAAIIAAkKggwRHwDiAQAIAAkKggwRHwDiAQAAAA==.Sandmann:BAAANQADCgUICgAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Sc='Scapegoatx:BAAANQADCgEIAQAAAA==.',
Se='Seer:BAACNQAFFH8PAAQiAAYKEBSjBAClAAAiAAIKGhSjBAClAAAQAAMKrBciMwCPAAAaAAEK0AxjHgBLAAA1AAQKf84ABCIACgr8JfsAABYDABAACAr6JbQPAFQDACIACgreJPsAABYDABoACAoDJDAEAOwCAAAA.Sehkreht:BAAANQADCggIEAAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAFFAMIBQASAIoKAA==.Shamanigans:BAAANQADCggIEgAAAA==.Shangzha:BAABNQAECn9GAAIdAAoK7iO8AQA/AwAdAAoK7iO8AQA/AwAAAA==.Shareholder:BAEBNQAECn8vAAIQAAoKmiS9BQAvAwAQAAoKmiS9BQAvAwABNQAFFAYICQAOAKoYAA==.Shiivera:BAABNQAECn8rAAIKAAoKmh3AMQCZAgAKAAoKmh3AMQCZAgAAAA==.Shimada:BAABNQAECn8wAAITAAoKexzmKAD0AgATAAoKexzmKAD0AgAAAA==.Shotsyll:BAACNQAFFH8IAAITAAMKfRTfFgADAQATAAMKfRTfFgADAQA1AAQKfxgAAhMACAqtG1WMAPIBABMACAqtG1WMAPIBAAAA.',
Sk='Skarín:BAAANQADCgMIAQAAAA==.Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAABNQAECn81AAMFAAoKQh30BgBoAgABAAoKOBq2GwB8AgAFAAkKYRz0BgBoAgAAAA==.Skynomad:BAAANQAECgYIEgAAAA==.',
Sl='Slyde:BAABNQAECn8hAAIGAAcKWyOsJQCoAgAGAAcKWyOsJQCoAgAAAA==.',
Sm='Smalldk:BAACNQAFFH8KAAMPAAIKAAAzJwBdAAAPAAEKAAAzJwBdAAAGAAEKAAB2JQA2AAA1AAQKfxcAAwYACgo/FENkAH8BAAYACgqvEUNkAH8BAA8ABQoYHdxnAFMBAAE1AAUUBggSAA0AsRUA.Smallrichard:BAAANQAECgEIAQABNQAECgkJIgAOAF4UAA==.Smashytash:BAABNQAECn8XAAIjAAkK1RRqCQDBAQAjAAkK1RRqCQDBAQAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAABNQAECn8hAAMHAAgKSA7shgCGAQAHAAgKSA7shgCGAQANAAEKGwHuiwEZAAAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgkJFwAjANUUAA==.',
Sn='Snek:BAAANQAECgEIBAAAAA==.Snowing:BAAANQAECgYIDwABNQAECgkJGAAGAHYWAA==.Snugglybear:BAABNQAECn8nAAIDAAoKOCVjAQBrAwADAAoKOCVjAQBrAwABNQAFFAQICgAPAFseAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Sodlid:BAAANQAECgcIDQAAAA==.Solariaa:BAAANQAECgMIBQABNQAFFAYIEgACAOwfAA==.Solborne:BAAANQAECgEIAwAAAA==.Solfreid:BAAANQAECgYIEQAAAA==.Sophism:BAABNQAECn8WAAMFAAoKeBd7LAA1AgAFAAoK+BN7LAA1AgABAAYKARYjWwBKAQABNQAFFAgIIAAfAAgWAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAPAFAmAA==.Soulfang:BAABNQAECn85AAIjAAoKiBa/BgAZAgAjAAoKiBa/BgAZAgAAAA==.Soulfox:BAAANQADCgQIBAABNQAECggIEgAMAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulripper:BAAANQAECgUIBQAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAABNQAECn8aAAIKAAoKTRfnMQAlAgAKAAoKTRfnMQAlAgABNQAFFAQIBQABAOwFAA==.Sprocketrot:BAABNQAECn8dAAMcAAkKShlyIAATAgAcAAkK9BRyIAATAgAGAAUKgx3oWwCgAQAAAA==.',
Sq='Squidmonk:BAABNQAECn8aAAIhAAkKoQ5xGwDLAQAhAAkKoQ5xGwDLAQAAAA==.',
St='Stalwart:BAAANQADCgEIAQABNQAFFAYIDwAiABAUAA==.Stardrive:BAACNQAFFH8PAAIUAAUK5QfHIAD6AAAUAAUK5QfHIAD6AAA1AAQKfyYAAhQACgphEll/AB0CABQACgphEll/AB0CAAAA.Steelrend:BAAANQAECgEIAQABNQAECgoKJAAUAOMVAA==.Steelwhacka:BAABNQAECn8VAAMXAAgK7gs8MgCFAQAXAAgK7gs8MgCFAQAhAAUKgwtxMgDWAAAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFH8YAAIXAAcK9BmgBAD2AQAXAAcK9BmgBAD2AQA1AAQKfycAAhcACgqaIiMUALYCABcACgqaIiMUALYCAAAA.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAABNQAECn8YAAQQAAoKjQ1hoQDeAAAQAAgKTQ1hoQDeAAAaAAIKTQ61WgBwAAAiAAIKuQuoLQA7AAAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQAECgYICAABNQAECgYIEgAMAAAAAA==.Superpowers:BAAANQADCgcIDAAAAA==.Supersaiyan:BAAANQAECgYIDAAAAA==.Surtur:BAABNQAECn9RAAMUAAoKzRznLwBZAgAUAAoKzRznLwBZAgAkAAcKcBC8FAA4AQAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECgoKOwAYAMYXAA==.Swoobs:BAAANQAECggICQABNQAECggILQABAP4PAA==.',
Sy='Sygismund:BAABNQAECn8rAAMmAAkKWgbhOgAWAQAmAAkKWgbhOgAWAQAeAAIK3AAMVgAPAAAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAACNQAFFH8GAAITAAMKhA5uGwCcAAATAAMKhA5uGwCcAAA1AAQKfzcAAhMACgoPHSckAAYDABMACgoPHSckAAYDAAAA.Tandalil:BAAANQADCgUIBQAAAA==.Taotien:BAAANQAECgcICwAAAA==.Tashbringer:BAAANQAECgIIBQABNQAECgkJFwAjANUUAA==.Tazatrath:BAAANQAECgIIBQAAAA==.',
Tc='Tchaik:BAABNQAECn8yAAMVAAoKZCA4FQAmAwAVAAoKZCA4FQAmAwAWAAIK7hQ4TgBDAAAAAA==.',
Te='Tecknicaliti:BAAANQAECgUIBgAAAA==.Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgUIEgAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQAECgMIBgAAAA==.Theios:BAABNQAECn8hAAIUAAgKqAy9gQBMAQAUAAgKqAy9gQBMAQABNQAECgkJMwAGAL8WAA==.Thickthang:BAABNQAECn82AAMdAAoK+yNuAgCFAwAdAAoK+yNuAgCFAwALAAQKrhYp3gDZAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECn9SAAMlAAoKgCQ2AQArAwAlAAoKgCQ2AQArAwAeAAEKAAAzWgAAAAAAAA==.Tinytea:BAABNQAECn9SAAMXAAoKGh8aCQCzAgAXAAoKGh8aCQCzAgAoAAEKAABiLQBSAAAAAA==.Tinytilted:BAAANQADCgEIAQAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgcIDQAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAABNQAECn89AAIQAAoK8QwUUACsAQAQAAoK8QwUUACsAQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBwABNQAECgUICAAMAAAAAA==.',
Tr='Trilicia:BAABNQAECn8cAAMFAAoK9hXLEgCEAQAFAAoK/BTLEgCEAQABAAcKNxCcYwAtAQAAAA==.Trusinner:BAABNQAECn8bAAIUAAgKRxjdbgBGAgAUAAgKRxjdbgBGAgAAAA==.',
Ts='Tsusha:BAEBNQAECn8UAAILAAYKEw4VowBPAQALAAYKEw4VowBPAQABNQAECgcIDQAMAAAAAA==.',
Tu='Turkeyleg:BAAANQADCggIIQAAAA==.',
Tw='Twippy:BAABNQAECn8oAAILAAoKKRP8TABDAgALAAoKKRP8TABDAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgcIEgABNQAECgUIBAAMAAAAAA==.Tyriam:BAABNQAECn89AAINAAoKTRw3RQDFAgANAAoKTRw3RQDFAgAAAA==.',
Ud='Udderchaos:BAAANQAECgMIBQAAAA==.',
Un='Undeadboss:BAAANQADCgUIBQABNQAECggIEgAMAAAAAA==.Unifey:BAAANQAECgQIBwAAAA==.',
Va='Valess:BAAANQAECgIIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.Varrae:BAAANQADCgIIAgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAACNQAFFH8TAAIJAAYK/hc8AQA8AQAJAAYK/hc8AQA8AQA1AAQKfzYAAgkACgqyH1sHAAwDAAkACgqyH1sHAAwDAAAA.Verso:BAABNQAECn8kAAIpAAkKxhfOBgBZAgApAAkKxhfOBgBZAgAAAA==.',
Vi='Vitalithry:BAABNQAECn8qAAMnAAoKpxc3BgBrAgAnAAoKpxc3BgBrAgAJAAQK2hF6EgDfAAAAAA==.Vivii:BAAANQAECgcICwAAAA==.Vizzysmash:BAAANQAECgYIBgABNQAECgoKQgAGAJ4dAA==.',
Vo='Voden:BAAANQABCgUICAAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.Vynn:BAAANQADCgYIAQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECn9HAAMcAAoKBBkCKQBRAgAcAAoKBBkCKQBRAgAPAAUKoA9vjADQAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAABNQAECn80AAMLAAkKuCJLJwDmAgALAAkKuCJLJwDmAgAKAAMKqxTn2wCwAAAAAA==.Whiteshadow:BAAANQAECgQIBAAAAA==.',
Wi='Wiiska:BAACNQAFFH8OAAMWAAYK3RR4BQAjAQAWAAUKsBB4BQAjAQAVAAEKXwABMQBDAAA1AAQKfzUAAxYACgp0HMkUAL0CABYACgp0HMkUAL0CABUABwpkChmMAPsAAAAA.Wildling:BAAANQADCgIIAwAAAA==.Windoelicker:BAAANQADCgcIFwAAAA==.',
Wo='Worgya:BAAANQAECgQIAQABNQAECggIEgAMAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgoKIgATAKEjAA==.Wrlccywhefr:BAABNQAECn81AAQBAAoK0yN/GgCGAgABAAgKfCF/GgCGAgAFAAcKwiPYIgBwAgApAAYKph/HCQDnAQAAAA==.',
Wu='Wuggles:BAABNQAECn8eAAICAAkKORdHGgBnAgACAAkKORdHGgBnAgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAABNQAECn8mAAITAAkK5BtHdwAhAgATAAkK5BtHdwAhAgAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwAUAEcYAA==.',
Xy='Xyklon:BAAANQADCgQIBAAAAA==.',
Ya='Yahmon:BAAANQAECgYIEwAAAA==.',
Ye='Yetil:BAABNQAECn8ZAAIHAAkK9w47fACkAQAHAAkK9w47fACkAQAAAA==.',
Yn='Ynotraw:BAACNQAFFH8FAAIUAAMKEhkaEwDnAAAUAAMKEhkaEwDnAAA1AAQKfzIAAhQACgocIo8MAJMDABQACgocIo8MAJMDAAAA.Ynotstorm:BAAANQAECgQIBAAAAA==.',
Yo='Yourephired:BAABNQAECn8nAAMRAAgKRA9iEgCBAQARAAgKRA9iEgCBAQAOAAEKAAAp2gEoAAAAAA==.',
Za='Zaerix:BAAANQADCgYICQAAAA==.Zaknafein:BAAANQAECgUICQABNQAECgoKQwAOABIcAA==.Zarah:BAAANQAECgEIAQAAAA==.Zaycursed:BAAANQAECgQICgABNQAECggIHgALABQfAA==.Zaydream:BAAANQADCgcICAABNQAECggIHgALABQfAA==.Zaylight:BAAANQADCggICAABNQAECggIHgALABQfAA==.Zayseer:BAABNQAECn8eAAILAAgKFB+TOACUAgALAAgKFB+TOACUAgAAAA==.',
Ze='Zello:BAABNQAECn8gAAMVAAkKegZVfgAjAQAVAAgKjgZVfgAjAQAWAAQKcATnYAB+AAAAAA==.',
Zh='Zhengy:BAABNQAECn8VAAIaAAYKFhHEBwApAQAaAAYKFhHEBwApAQABNQAECgoKQwAOABIcAA==.',
Zi='Ziggybeast:BAABNQAECn8jAAQZAAoKWx1dNwAyAgAZAAgK/R1dNwAyAgACAAgKqRooJAAEAgADAAEKAADIZAArAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggIDAAAAA==.',
Zy='Zydia:BAABNQAECn8WAAMkAAUKGAqhKwBxAAAUAAQKBAM2LAF8AAAkAAUKGAqhKwBxAAAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcICAABNQAECggIHgALABQfAA==.',
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
