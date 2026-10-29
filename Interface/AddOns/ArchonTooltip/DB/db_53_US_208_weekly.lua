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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','Mage-Frost','DeathKnight-Blood','Warlock-Demonology','Hunter-Marksmanship','DeathKnight-Frost','Hunter-BeastMastery','Mage-Arcane','Warrior-Arms','Priest-Holy','Priest-Shadow','Monk-Windwalker','Druid-Feral','Druid-Balance','Warlock-Destruction','Paladin-Protection','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Priest-Discipline','Monk-Mistweaver','Warlock-Affliction','Druid-Guardian','Warrior-Fury','Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Druid-Restoration','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aanna:BAAANQADCgUIBQAAAA==.',
Ab='Abandonedcat:BAAANQAECgQIAgABNQAECgoKNQABANMjAA==.Abor:BAAANQAECggIDwAAAA==.Abuela:BAABNQAECn8yAAMCAAoKqx1sDQAZAwACAAoKvxxsDQAZAwABAAcKhxhEKQDfAQAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ad='Adaela:BAAANQADCgIIAgABNQAECgkJKgACABobAA==.',
Ae='Aegla:BAABNQAECn8sAAIDAAkKxhVjPwAgAgADAAkKxhVjPwAgAgAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ag='Aghlath:BAAANQAECgYICAAAAA==.',
Ak='Akiko:BAAANQAECgYIDQABNQAECgoKLgAEAGQcAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFH8QAAIFAAQKQxKVEADjAAAFAAQKQxKVEADjAAA1AAQKfykAAgUACQrTHD0NANICAAUACQrTHD0NANICAAAA.Alliar:BAABNQAECn8qAAMGAAoKUxwnKwC2AgAGAAoKUxwnKwC2AgAHAAYKPwl5rAA7AQAAAA==.Allynstraza:BAABNQAECn8VAAIFAAYKARClKgBYAQAFAAYKARClKgBYAQAAAA==.',
Am='Amgems:BAAANQAECgQIBQABNQAECgYICQAIAAAAAA==.Amordred:BAAANQAECgQIDgAAAA==.',
An='Anasterion:BAABNQAECn8VAAIJAAgK8CAlbgBUAgAJAAgK8CAlbgBUAgAAAA==.Andarus:BAABNQAECn8dAAIJAAcKvxh5WQCrAQAJAAcKvxh5WQCrAQABNQAECgoKOQAKAF4bAA==.Ankles:BAABNQAECn8nAAMLAAkKfiPRBwB/AwALAAkKfiPRBwB/AwADAAIK+glCzwBPAAAAAA==.Ansley:BAAANQADCgUICAABNQAECgkJKgACABobAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgYIBwABNQAECgoKQQAMADweAA==.',
As='Ashli:BAABNQAECn8qAAMCAAkKGhtpGAC5AgACAAgK+BtpGAC5AgABAAgKDBhpIwAHAgAAAA==.Astiri:BAAANQAFFAEIAQAAAA==.',
At='Atlasbär:BAAANQAECgQIBAABNQADCgYIDwAIAAAAAA==.Atlasdark:BAABNQAECn8ZAAIGAAoKPxwuHgBSAgAGAAoKPxwuHgBSAgABNQADCgYIDwAIAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.Atreyu:BAAANQAECgYIAgAAAA==.',
Ba='Balrock:BAAANQAECgIIBQAAAA==.Balthromaw:BAABNQAECn8rAAIMAAoKuBgWHQBPAgAMAAoKuBgWHQBPAgAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQAIAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECgQIBAABNQAFFAMIBQANAIoKAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belfdelphine:BAAANQAECgcIBgAAAA==.Bellum:BAAANQAECgYICAAAAA==.Belstab:BAABNQAECn8tAAMBAAgK/g/XGwD3AQABAAgKhw/XGwD3AQACAAcKcwkNTgCHAQABNQAFFAQICwAOADwEAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIEAABNQAECgoKGwAPACojAQ==.',
Bg='Bgbalkoth:BAAANQADCgYIDAAAAA==.',
Bi='Bifurthegrey:BAAANQAECgQIAwAAAA==.Bigblammy:BAAANQADCggICAABNQAFFAcIGQAQACAfAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQABNQAECgYIEAAIAAAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Blinkss:BAAANQAECgYIBgAAAA==.Bloodavenger:BAABNQAECn8dAAMEAAkKZgx0ZgDkAQAEAAkKZgx0ZgDkAQAJAAUK9wb3KgHZAAAAAA==.Bloodemongar:BAABNQAECn8WAAIDAAkKvg5RZgB3AQADAAkKvg5RZgB3AQAAAA==.Bloodhoundss:BAABNQAECn8hAAIRAAkKchR/TQCcAQARAAkKchR/TQCcAQAAAA==.Blössöm:BAAANQAECgYIDAAAAA==.',
Bo='Bobdk:BAACNQAFFH8cAAMDAAYKlR0FBAD0AQADAAYKlR0FBAD0AQALAAEKAADsOAAgAAA1AAQKfzgAAgMACgo9JLkEAPsCAAMACgo9JLkEAPsCAAAA.Bomboklaat:BAAANQADCgMIBgAAAA==.Boomfrin:BAAANQAECgUICgAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECn8lAAMSAAkK6BA6WQAWAgASAAkK6BA6WQAWAgATAAEKXAWlewAxAAAAAA==.',
Br='Braegen:BAABNQAECn8WAAIPAAgKnRMkVwCXAQAPAAgKnRMkVwCXAQABNQAECgoKOQAKAF4bAA==.Brewslee:BAAANQADCggICAAAAA==.Brewsleê:BAAANQAECgQIBAAAAA==.Bruceleett:BAABNQAECn8zAAIUAAkKlRFlEQDOAQAUAAkKlRFlEQDOAQABNQADCgcIFwAIAAAAAA==.',
Bu='Buffmeister:BAAANQAECgUIBQAAAA==.Bullioss:BAAANQAECgIICQABNQAECgoKGwAPACojAA==.',
['Bö']='Böbbyboucher:BAABNQAECn8fAAIHAAcK8x60PwB2AgAHAAcK8x60PwB2AgAAAA==.',
Ca='Cainn:BAAANQADCggIEwABNQAECgkJJwAJACUUAA==.Caldrid:BAAANQADCgYIDwAAAA==.Calfurion:BAABNQAECn8VAAMVAAgKqB3zEAD4AQAWAAcKShxEPwAAAgAVAAYK1B7zEAD4AQAAAA==.Calvary:BAAANQAECggIDgABNQAECggIFQAVAKgdAA==.Capncrunch:BAAANQADCgYICwAAAA==.Cardiganz:BAAANQABCgUIBQAAAA==.Cazleah:BAABNQAECn83AAIHAAoKkyEOGQAzAwAHAAoKkyEOGQAzAwAAAA==.',
Ce='Cessatio:BAABNQAECn8dAAIXAAYK4gtFDQC0AAAXAAYK4gtFDQC0AAAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAABNQAECn8pAAIJAAoKYhvGNAAlAgAJAAoKYhvGNAAlAgABNQAECgoKUQABAM8gAA==.Chowming:BAAANQABCgEIAQAAAA==.Chrisbrewn:BAABNQAECn8kAAIRAAkKzhMkcgA+AgARAAkKzhMkcgA+AgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clamsweat:BAAANQABCgIIAgAAAA==.Clevelandoe:BAACNQAFFH8FAAINAAMKigoPGQC5AAANAAMKigoPGQC5AAA1AAQKfzkAAw0ACQpIJGEOAPwCAA0ACQq6IWEOAPwCAA8ABQoUHMKnALYBAAAA.',
Co='Cobbknob:BAAANQAECgUIBwAAAA==.Cocobear:BAAANQAECgEIAQAAAA==.Coeurdeleon:BAABNQAECn8dAAMJAAoKTxTxhAAeAgAJAAoKTxTxhAAeAgAYAAEKAAC2ZgBHAAAAAA==.Cokakilla:BAAANQADCgUIBAAAAA==.Condemnation:BAABNQAECn85AAISAAoKqxnFOACFAgASAAoKqxnFOACFAgAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgYICgABNQADCggIDQAIAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQAIAAAAAA==.Coriantumr:BAAANQADCgYIBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQAECgQIBQAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbazar:BAAANQABCgcICwAAAA==.Curbstomped:BAABNQAECn8gAAMPAAoKjBQzbwAzAgAPAAoKjBQzbwAzAgANAAMK7gN0bgB2AAAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgYIDQABNQAFFAcIEwAQABQiAA==.Darkvizzy:BAABNQAECn85AAQDAAoKnh21DQBBAgADAAkKsR21DQBBAgALAAgKsREjZABhAQAOAAIK3gqYlwBlAAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgYIBwAAAA==.Demiplo:BAABNQAECn8mAAIPAAkK5xGFegAZAgAPAAkK5xGFegAZAgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQAIAAAAAA==.Denelak:BAABNQAECn8hAAMPAAoKZx8QEgBYAwAPAAoK2x0QEgBYAwANAAkKcxcqGQCOAgAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAAANQAECggIDgABNQAECgoKMgACAKsdAA==.',
Di='Dirtycasual:BAAANQAECggIDgABNQAECgoKMgACAKsdAA==.Discipline:BAABNQAECn8xAAMYAAkKBRypEgB4AgAYAAkKrxupEgB4AgAJAAgKchU8mQDxAQAAAA==.',
Do='Doggo:BAAANQAECgEIAQAAAA==.Dotsurdead:BAAANQAECggICwAAAA==.',
Dr='Dratr:BAABNQAECn8jAAIZAAkKjQuwFwDtAQAZAAkKjQuwFwDtAQAAAA==.Draxyl:BAABNQAECn8xAAMLAAoK3hVSKQBSAQADAAkKJA/aSgDqAQALAAoKCRRSKQBSAQAAAA==.Drekhan:BAAANQAECgYIDgABNQAECgoKOQAKAF4bAA==.Drfizzle:BAAANQAECgEIAQABNQAECgkJKgARAOIgAA==.Drham:BAABNQAECn8kAAIaAAkKJQ4vKQD6AQAaAAkKJQ4vKQD6AQAAAA==.Drogbar:BAAANQAECgEIAQABNQAECgkJIwAUAO4VAA==.Drokos:BAAANQAECgUIBwABNQAECgoKGwAPACojAA==.Drtree:BAAANQADCgcIBwAAAA==.Druni:BAAANQADCgEIAQAAAA==.',
Du='Dunhambones:BAABNQAECn81AAIDAAoKXCAbEQAuAwADAAoKXCAbEQAuAwAAAA==.Duo:BAABNQAECn8uAAIbAAoKlhPSAQBwAgAbAAoKlhPSAQBwAgABNQAECggIDwAIAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Elcosote:BAAANQAECgYIBQAAAA==.Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQAECgYICQAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECn85AAQSAAoK+hIhPwC4AQASAAoK+hIhPwC4AQATAAIK6QGceQA1AAAcAAEK/gUdKQAyAAAAAA==.Elèctra:BAAANQAECgcIDwAAAA==.',
En='Engraver:BAAANQADCggICAAAAA==.Enochs:BAAANQADCgIIAgAAAA==.Enyô:BAAANQADCgQIBAABNQAECgcIHwAHAPMeAA==.',
Er='Erada:BAABNQAECn8tAAMKAAoKXR5sAgCZAgAKAAkK9yBsAgCZAgAQAAkKsBSWjABmAgAAAA==.',
Ev='Evoklando:BAAANQADCgUICgABNQAFFAMIBQANAIoKAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgcIDAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIAwABNQAECggIDwAIAAAAAA==.',
Fe='Felad:BAABNQAECn8uAAMdAAoKViXgAAD1AwAdAAoKViXgAAD1AwAUAAEKAACXZwBAAAABNQAECgUICgAIAAAAAA==.Felwen:BAABNQAECn8UAAICAAoKGRM+GQAyAQACAAoKGRM+GQAyAQAAAA==.',
Fh='Fhalanx:BAAANQAECgYIBwAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECgcIDgABNQAECgoKGQAHAL0NAA==.Flappyy:BAABNQAECn8ZAAMHAAoKvQ1EPgBbAQAHAAoKvQ1EPgBbAQAGAAMKNAZ6+gB2AAAAAA==.Flowdinstuna:BAABNQAECn8fAAIaAAoKNBdCGgCHAgAaAAoKNBdCGgCHAgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAABNQAECn8sAAIPAAoK2BioRACdAgAPAAoK2BioRACdAgAAAA==.Freakmage:BAAANQADCgUIBQAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.',
Fu='Furrybait:BAEANQAECgcICAAAAA==.Furyiosa:BAABNQAECn8oAAIRAAoKrx6+FgCxAgARAAoKrx6+FgCxAgAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgAIAAAAAA==.Gaiseric:BAABNQAECn8oAAIDAAkKsBq3PwAfAgADAAkKsBq3PwAfAgAAAA==.Gamago:BAAANQAECggIBQAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECn8cAAQXAAkKix5CKAA2AQAMAAcKWBpmcQAMAgAXAAQKCh9CKAA2AQAeAAEKAADLKQBFAAAAAA==.Getoverhere:BAAANQADCggICwAAAA==.',
Gi='Girltank:BAAANQAECgIIBAAAAA==.',
Gn='Gnarlak:BAAANQAECgIIAwAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gorestomp:BAAANQAECgEIAQAAAA==.Gotboned:BAAANQAECgcIDAABNQAFFAYIBgAfAGMeAA==.Gotfleas:BAACNQAFFH8GAAIfAAYKYx6WAAA6AgAfAAYKYx6WAAA6AgA1AAQKfyQAAx8ACgrJJSQBANsDAB8ACgrJJSQBANsDABUAAQpkAAAAAAAAAAAA.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAABNQAECn8wAAIaAAoKXhNIKQD5AQAaAAoKXhNIKQD5AQAAAA==.Greyfax:BAABNQAECn8mAAIEAAoK4R5SGQATAwAEAAoK4R5SGQATAwAAAA==.Grimthruul:BAABNQAECn8oAAIHAAoKHgfRjQCBAQAHAAoKHgfRjQCBAQAAAA==.Grommkar:BAABNQAECn8jAAIRAAkKDg7IkADyAQARAAkKDg7IkADyAQAAAA==.Groztok:BAAANQADCgMIAwAAAA==.Grumpig:BAAANQADCgQIDAAAAA==.Grèggory:BAAANQAECgQIBAAAAA==.',
Gu='Gusari:BAEANQAECgEIAQABNQAECggIDAAIAAAAAA==.Gutx:BAAANQADCgQIBAAAAA==.',
Ha='Hadmeathello:BAAANQAECgIIAgAAAA==.Halucination:BAABNQAECn8dAAMTAAkK7wxiJAAOAgATAAkK7wxiJAAOAgASAAIKlwRr7QBcAAAAAA==.Harthan:BAABNQAECn8bAAMRAAkK6hHFnQDSAQARAAkK6hHFnQDSAQAgAAEKkQ4MIgA5AAAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayden:BAABNQAECn8YAAIJAAoKxRsRWACOAgAJAAoKxRsRWACOAgAAAA==.Hayleigh:BAAANQAECgIIAgAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwAIAAAAAA==.Helya:BAAANQADCgMIBgAAAA==.Henchman:BAAANQABCgQICAABNQAECgoKGwAPACojAA==.Hetzák:BAABNQAECn8sAAIWAAoKYhFzOgAfAgAWAAoKYhFzOgAfAgAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBgAAAA==.Hintolisu:BAABNQAECn81AAIVAAoKGB03BgANAwAVAAoKGB03BgANAwAAAA==.',
Ho='Hobbess:BAABNQAECn8UAAIaAAgK9BB3LADeAQAaAAgK9BB3LADeAQABNQAFFAgIKAAWAO8lAA==.Holybaloney:BAABNQAECn8jAAMYAAoKeRzKEQCEAgAYAAgKFx/KEQCEAgAJAAkKtAi3ewBaAQAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Holyvaj:BAAANQAECggIDgAAAA==.Hongis:BAAANQAECgEIAQAAAA==.Hoofinit:BAABNQAECn8qAAIRAAkK4iBtKgARAwARAAkK4iBtKgARAwAAAA==.',
Hu='Huatarm:BAABNQAECn8qAAIhAAoKuRgMDQBiAgAhAAoKuRgMDQBiAgAAAA==.',
Ia='Iadygaga:BAABNQAECn8eAAQSAAoKow49UgBpAQASAAoKow49UgBpAQATAAYKrhA0QQAnAQAcAAIKlQM6IwBPAAAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECgkJLAADAMYVAA==.',
Ir='Ironpaw:BAAANQADCgUIBQAAAA==.Ironspin:BAAANQAECgQIBgAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Is='Isisankh:BAAANQADCggICAAAAA==.Isolated:BAAANQAECggIAQABNQAECgoKMgACAKsdAA==.',
Ja='Jaark:BAACNQAFFH8PAAIMAAUKlxNTDgDiAAAMAAUKlxNTDgDiAAA1AAQKfzgAAwwACgoMIDomAOsCAAwACgoMIDomAOsCAB4AAwpOHQgPAJ0AAAAA.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgMIBQABNQAECgkJKgACABobAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jehanne:BAAANQADCgQIBQAAAA==.Jen:BAABNQAECn85AAISAAoK1Bb+TgA4AgASAAoK1Bb+TgA4AgAAAA==.',
Jo='Jocon:BAAANQAECgYIBgAAAA==.',
Ju='Jugulator:BAAANQADCggIEAAAAA==.Jumpey:BAABNQAECn8aAAMiAAcK4BRmEACrAQAiAAYKnhhmEACrAQAjAAUKFQmfaQDSAAABNQAECgkJIgAkAOgWAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAABNQAECn8mAAIHAAoKFhksMQC2AgAHAAoKFhksMQC2AgABNQAECgQIBgAIAAAAAA==.Kanami:BAABNQAECn8dAAIRAAgKMhZNQQDJAQARAAgKMhZNQQDJAQAAAA==.Kaynyx:BAABNQAECn8uAAIBAAoKCB3oBgAQAwABAAoKCB3oBgAQAwAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAABNQAECn8nAAIJAAkKJRSqfAAxAgAJAAkKJRSqfAAxAgAAAA==.Kenzie:BAAANQAECgMIBAAAAA==.Kerb:BAABNQAECn8nAAQLAAkKOw81KQBSAQALAAkKOw81KQBSAQAOAAIK3gbXmQBgAAADAAEKAAAn6AAsAAAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECn8aAAMaAAgK7hjYJwAFAgAaAAgK4xTYJwAFAgAjAAQKtBckYAD8AAAAAA==.',
Ki='Kikiko:BAAANQAECgMIAwAAAA==.Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECn8WAAIjAAgKDxfMMQAbAgAjAAgKDxfMMQAbAgAAAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQAJAPAgAA==.',
Kl='Klaris:BAAANQAECgQIBAAAAA==.',
Kn='Knewtoomuch:BAAANQADCgcIBwAAAA==.',
Ko='Konjur:BAACNQAFFH8ZAAMQAAcKIB9pCwAdAgAQAAYK7h1pCwAdAgAKAAIK/SDhAgC/AAA1AAQKfygAAhAACgqDJbMHAB8DABAACgqDJbMHAB8DAAAA.Korpen:BAAANQADCgEIAQAAAA==.',
Kr='Krelock:BAAANQAECgYICgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgQIBQABNQAECgoKSgAhANQZAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
Ky='Kytheon:BAAANQADCgIIAgAAAA==.',
['Kà']='Kàmó:BAAANQAECgcIBwABNQAECgQIBgAIAAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgQIBgAAAA==.',
['Kä']='Kämo:BAAANQAECgIIAwABNQAECgQIBgAIAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgUICwABNQAFFAUIDgAlAEsiAA==.Lakeyy:BAACNQAFFH8OAAIlAAUKSyJHBQBRAQAlAAUKSyJHBQBRAQA1AAQKfzUAAyUACgqbJY8CAKQDACUACgqbJY8CAKQDABYABAppHYRHAKYAAAAA.Lakeyys:BAAANQAECgEIAQABNQAFFAUIDgAlAEsiAA==.Lanuor:BAAANQADCgEIAQAAAA==.Laufey:BAAANQAECgIIAgAAAA==.Lavagobrr:BAAANQAECgQIBAABNQAECggIDgAIAAAAAA==.Lawrence:BAACNQAFFH8OAAIGAAUK0hDQCwAmAQAGAAUK0hDQCwAmAQA1AAQKfy0AAwYACgrfHtYtAKsCAAYACgrfHtYtAKsCAAcABQooF7GLAIYAAAAA.',
Le='Lesaeria:BAABNQAECn8eAAIaAAkKQRlXGgCGAgAaAAkKQRlXGgCGAgABNQAECgoKPQAZACkiAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQAECgIIAgAAAA==.Lightsardine:BAAANQADCgIIAgAAAA==.Lilikoii:BAAANQAECgIIAgABNQAFFAUIDgAlAEsiAA==.Liljit:BAAANQAECgEIAgABNQAECgoKLgAEAGQcAA==.Lilslaver:BAABNQAECn8dAAIPAAgKNAc3dABNAQAPAAgKNAc3dABNAQAAAA==.Limerence:BAAANQAECgcIBwAAAA==.Lisex:BAACNQAFFH8LAAMOAAUKTwz9DAAPAQAOAAQKTwz9DAAPAQALAAEKAAByNQApAAA1AAQKfyIAAw4ACQpNIU0YAMgCAA4ACQpNIU0YAMgCAAsAAQoiFu3FAD0AAAAA.Lithe:BAABNQAECn9BAAIJAAoKdB2CLAAWAwAJAAoKdB2CLAAWAwABNQAECgoKUAAHADYiAA==.',
Lo='Lockjhaw:BAAANQAFFAEIAQAAAA==.Locklear:BAABNQAECn84AAIJAAkKAxciRQDpAQAJAAkKAxciRQDpAQAAAA==.Logic:BAACNQAFFH8eAAQbAAcK1RYZAAAKAgAbAAYK8hYZAAAKAgAQAAYKYhM3EwDdAQAKAAMKIRj/AgD3AAA1AAQKfzcABBAACgozIytaAMsCABAACgrHICtaAMsCABsABwpqINMBAIABAAoAAwreJDsMAEQBAAAA.Lola:BAAANQAECgIIAgABNQAFFAUIDgAlAEsiAA==.Lolbrez:BAAANQAECggIBgAAAA==.',
Lu='Lunanarn:BAAANQADCgIIAgAAAA==.Lunaria:BAAANQAECgUIBgABNQAFFAUIDgAlAEsiAA==.Lusty:BAABNQAECn8iAAIkAAkK6BYEEQBFAgAkAAkK6BYEEQBFAgAAAA==.Luthix:BAAANQADCgIIAgAAAA==.Luxe:BAAANQAECgIIAgABNQAFFAUIDgAlAEsiAA==.',
Ma='Macediin:BAABNQAECn8lAAIDAAgKxRqOEgD8AQADAAgKxRqOEgD8AQAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECn8bAAIaAAkKiByaHABwAgAaAAkKiByaHABwAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgkJJgANAM8ZAA==.Magnolìa:BAAANQAECgUICQAAAA==.Malefic:BAAANQAECgMIBQABNQAFFAcIGQAQACAfAA==.Malthael:BAABNQAECn8rAAMDAAoKmxWHPQApAgADAAkKvheHPQApAgAOAAgKlg0nUwBjAQAAAA==.Mamageek:BAAANQAECggIEwAAAA==.Mami:BAAANQAECgEIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECgkJLgAHABQhAA==.Manix:BAAANQAECgcIDwABNQAECggIDgAIAAAAAA==.Mareo:BAAANQAECgQIBwAAAA==.Marksterique:BAABNQAECn8mAAINAAkKzxmaGQCKAgANAAkKzxmaGQCKAgAAAA==.Masochist:BAAANQAECgMIAwAAAA==.',
Me='Meeko:BAACNQAFFH8SAAIFAAgKpRQyBAA5AgAFAAgKpRQyBAA5AgA1AAQKf1AAAgUACgp5IgoGAEkDAAUACgp5IgoGAEkDAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgMIAwAAAA==.Metalbound:BAAANQAECgYIDAAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAABNQAECn8cAAIZAAgKqSSzBgAZAwAZAAgKqSSzBgAZAwAAAA==.Misslobster:BAABNQAECn8WAAIGAAcKpA76oQAxAQAGAAcKpA76oQAxAQAAAA==.',
Mo='Mokoko:BAABNQAECn8wAAIkAAoKdhw3CwC0AgAkAAoKdhw3CwC0AgAAAA==.Mokolock:BAAANQAECgYICAABNQAECgoKMAAkAHYcAA==.Moomoo:BAABNQAECn8oAAIWAAkKFh4dFQAeAwAWAAkKFh4dFQAeAwAAAA==.Moorlin:BAAANQAECgUIDAAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgoKMAAkAHYcAA==.',
Mu='Mumra:BAAANQADCgUIBQAAAA==.',
My='Myka:BAAANQAECggIDgAAAA==.Mysticphatty:BAAANQADCggJCAABNQAECgIIAgAIAAAAAA==.Myyst:BAAANQAECgMIAwAAAA==.',
Na='Nanaka:BAAANQAECgQIBAABNQAECgYIDQAIAAAAAA==.Nawtalhere:BAAANQADCgQIBAABNQAECgoKLQALAFAiAA==.',
Ne='Necro:BAABNQAECn8fAAIDAAkKix3WIwCzAgADAAkKix3WIwCzAgAAAA==.Necrota:BAABNQAECn8ZAAMLAAkKZxoCMwBCAgALAAkK4hgCMwBCAgADAAEKOiGUxABiAAABNQAFFAcIGQAQACAfAA==.Nekronomicon:BAAANQADCggICgABNQAECgoKOQASAKsZAA==.Neuron:BAACNQAFFH8VAAMlAAcKxRluAgDcAQAlAAcKxRluAgDcAQAWAAQKUAd5FwDyAAA1AAQKfyUAAyUACgobHAsSAMACACUACgobHAsSAMACABYABgpGEFpXAHkBAAAA.Nexdorei:BAAANQABCggICAAAAA==.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAABNQAECn81AAIfAAkKqh/FCADtAgAfAAkKqh/FCADtAgAAAA==.Nightflame:BAAANQAECgQJCAAAAA==.Ninjavc:BAABNQAECn8iAAICAAgKwAoXFgBJAQACAAgKwAoXFgBJAQAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAAANQAECgYIDAAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQAECgUICAAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Olpheux:BAAANQAECgMIAwAAAA==.',
On='Onayro:BAAANQABCgIIAgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgYIDAAAAA==.Oreyn:BAABNQAECn8XAAMgAAkKEhYsCgBlAQAgAAYKshksCgBlAQARAAgKcA4VagBIAQAAAA==.Organ:BAAANQAECgcIEAAAAA==.Orngar:BAAANQADCgMIAwAAAA==.',
Pa='Padle:BAABNQAECn8bAAMTAAoKVBISDQANAgATAAoKVBISDQANAgAcAAUKHhbXBABHAQAAAA==.Paladín:BAABNQAECn83AAMYAAoKyRaxDQDGAQAYAAkKxxexDQDGAQAJAAYKcA/cvwDdAAAAAA==.Palazar:BAABNQAECn8tAAIJAAoKuCD/MgAAAwAJAAoKuCD/MgAAAwAAAA==.Paoka:BAAANQADCgQIBwABNQADCggIFwAIAAAAAA==.Pappamidnite:BAAANQAECggICAAAAA==.Pargonz:BAABNQAECn9RAAMBAAoKzyCnCgDnAgABAAoKzyCnCgDnAgACAAIKlw6sjwBzAAAAAA==.Patoko:BAABNQAECn8oAAIZAAkKsB2ACgDKAgAZAAkKsB2ACgDKAgAAAA==.Paxwet:BAAANQAECgcICQAAAA==.Payn:BAAANQAECgUICgAAAA==.Paypay:BAABNQAECn82AAIlAAkKFx+gCQAsAwAlAAkKFx+gCQAsAwAAAA==.',
Ph='Phalannx:BAAANQAECgIIAwAAAA==.Philipx:BAAANQAECgEIAQAAAA==.Phinks:BAAANQADCgIIAgABNQAECgoKSQAZAH8lAA==.',
Pi='Piglittle:BAAANQAECgYIDQAAAA==.Pindad:BAABNQAECn8bAAIPAAoKKiMlDQB2AwAPAAoKKiMlDQB2AwAAAA==.',
Pl='Plzdispelme:BAABNQAECn8uAAMEAAoKZBw8LwCpAgAEAAoKZBw8LwCpAgAJAAEKAACWpgE0AAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAABNQAECn8eAAIXAAgKIREwDwAIAgAXAAgKIREwDwAIAgAAAA==.',
Pr='Priesticles:BAAANQAECgcICgABNQADCgcIFwAIAAAAAA==.Proshvam:BAAANQAECgEIAQAAAA==.',
Pu='Purrzac:BAABNQAECn8VAAIfAAgKYR2jGQDcAQAfAAgKYR2jGQDcAQABNQAECgoKLgAEAGQcAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Racialskill:BAAANQAECggICQABNQAECgoKLgAEAGQcAA==.Ragingmonkx:BAABNQAECn8jAAIUAAkK7hXlIAAlAgAUAAkK7hXlIAAlAgAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Raventer:BAABNQAECn8aAAIPAAgKhw6OgAAxAQAPAAgKhw6OgAAxAQAAAA==.Razdrood:BAAANQADCgcIBgABNQAECgQIDAAIAAAAAA==.Razlock:BAAANQAECgQIDAAAAA==.Razorclaws:BAAANQAECgQIBwAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAABNQAECn8nAAIDAAkKdxoeDQBLAgADAAkKdxoeDQBLAgAAAA==.Risky:BAAANQAECggIBwAAAA==.',
Ro='Roguesucks:BAAANQADCggIDQAAAA==.Rollos:BAABNQAECn8oAAIMAAkKyhutVQBVAgAMAAkKyhutVQBVAgAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAACNQAFFH8TAAMQAAcKFCLGBQBnAgAQAAYKqiLGBQBnAgAKAAEKux+ICwBfAAA1AAQKfxUAAhAABQqFJMJbAJoBABAABQqFJMJbAJoBAAAA.Ryujinsimp:BAACNQAFFH8MAAMkAAUKURr8BAB2AQAkAAUKURr8BAB2AQAmAAQKrxR/BgAbAQA1AAQKfyIAAyYACQq/JO0DANwCACQACQo1IsIIAOoCACYACAo9JO0DANwCAAE1AAUUBwgTABAAFCIA.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMIAwAIAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAUIEAASABgaAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECn8jAAIFAAkKggwRHwDiAQAFAAkKggwRHwDiAQAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAACNQAFFH8PAAQeAAYKEBSjBAClAAAeAAIKGhSjBAClAAAMAAMKrBciMwCPAAAXAAEK0AxjHgBLAAA1AAQKf8IABB4ACgrdJVcAAEQDAAwACAr6JbQPAFQDAB4ACgq9JFcAAEQDABcABwoDJDAEAOwCAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAFFAMIBQANAIoKAA==.Shamanigans:BAAANQADCggIEgAAAA==.Shangzha:BAABNQAECn89AAIZAAoKKSJqAgAEAwAZAAoKKSJqAgAEAwAAAA==.Shareholder:BAEBNQAECn8mAAIMAAoKWCS5BAAgAwAMAAoKWCS5BAAgAwABNQAFFAYICQAQAKoYAA==.Shiivera:BAABNQAECn8rAAIGAAoKmh3AMQCZAgAGAAoKmh3AMQCZAgAAAA==.Shimada:BAABNQAECn8vAAIPAAoKexzmKAD0AgAPAAoKexzmKAD0AgAAAA==.Shotsyll:BAACNQAFFH8IAAIPAAMKfRTfFgADAQAPAAMKfRTfFgADAQA1AAQKfxcAAg8ACAqtG1WMAPIBAA8ACAqtG1WMAPIBAAAA.',
Sk='Skarín:BAAANQADCgMIAQAAAA==.Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAABNQAECn8uAAMCAAoKQh2NBACJAgACAAkKYRyNBACJAgABAAoKNxq2FAB8AgAAAA==.Skynomad:BAAANQAECgYIEgAAAA==.',
Sl='Slyde:BAABNQAECn8hAAIDAAcKWyOsJQCoAgADAAcKWyOsJQCoAgAAAA==.',
Sm='Smalldk:BAABNQAFFH8JAAMLAAIKAAAzJwBdAAALAAEKAAAzJwBdAAADAAEKAAB2JQA2AAABNQAFFAYIEgAJALEVAA==.Smallrichard:BAAANQAECgEIAQABNQAECgkJIgAQAF4UAA==.Smashytash:BAAANQAECgcIEAABNQAECgoKMQAiALocAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAABNQAECn8dAAMEAAgKSA7shgCGAQAEAAgKSA7shgCGAQAJAAEKGwEmXwEZAAAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgoKMQAiALocAA==.',
Sn='Snek:BAAANQAECgEIBAAAAA==.Snowing:BAAANQAECgYIDAABNQAECgkJGAADAHYWAA==.Snugglybear:BAABNQAECn8eAAIfAAoKliPFAQBGAwAfAAoKliPFAQBGAwAAAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Sodlid:BAAANQAECgYICQAAAA==.Solariaa:BAAANQAECgIIAwABNQAFFAUIDgAlAEsiAA==.Solfreid:BAAANQAECgYIEAAAAA==.Sophism:BAAANQAECggIEgABNQAFFAcIHgAbANUWAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwALAFAmAA==.Soulfang:BAABNQAECn8vAAIgAAkK9xTBBgDJAQAgAAkK9xTBBgDJAQAAAA==.Soulfox:BAAANQADCgQIBAABNQAECgcIDwAIAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAABNQAECn8XAAIGAAoK0BbnJAAlAgAGAAoK0BbnJAAlAgABNQAFFAQIBQABAOwFAA==.Sprocketrot:BAABNQAECn8ZAAMOAAkKzBisFgAfAgAOAAkKdhSsFgAfAgADAAUKgx3oWwCgAQAAAA==.',
Sq='Squidmonk:BAABNQAECn8aAAIdAAkKoQ5xGwDLAQAdAAkKoQ5xGwDLAQAAAA==.',
St='Stardrive:BAACNQAFFH8NAAIRAAUK5QdGFQC5AAARAAUK5QdGFQC5AAA1AAQKfyUAAhEACgp8EVl/AB0CABEACgp8EVl/AB0CAAAA.Steelwhacka:BAABNQAECn8VAAMUAAgK7gs8MgCFAQAUAAgK7gs8MgCFAQAdAAUKgwtxMgDWAAAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFH8YAAIUAAcK9BlWAwA+AQAUAAcK9BlWAwA+AQA1AAQKfyYAAhQACgoXIiMUALYCABQACgoXIiMUALYCAAAA.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAABNQAECn8UAAQMAAgKAg0PzgAuAQAMAAYKXQwPzgAuAQAXAAIKTQ61WgBwAAAeAAIKuQuoLQA7AAAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQAECgYIBwABNQAECgYIEgAIAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgYIDAAAAA==.Surtur:BAABNQAECn9HAAMRAAoKHBzhQADIAgARAAoKHBzhQADIAgAhAAcKcBAJDwBGAQAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECgoKNwAYAMkWAA==.',
Sy='Sygismund:BAABNQAECn8lAAMjAAkKVAYkLwAqAQAjAAkKVAYkLwAqAQAaAAIK3AD1SwAPAAAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAABNQAECn8zAAIPAAoK2hwnJAAGAwAPAAoK2hwnJAAGAwAAAA==.Taotien:BAAANQAECgcICgAAAA==.Tashbringer:BAAANQAECgIIBAABNQAECgoKMQAiALocAA==.',
Tc='Tchaik:BAABNQAECn8uAAMSAAoKZCA4FQAmAwASAAoKZCA4FQAmAwATAAIK7hR+QABGAAAAAA==.',
Te='Tecknicaliti:BAAANQAECgQIBAAAAA==.Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgUIEgAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQAECgMIBgAAAA==.Theios:BAABNQAECn8bAAIRAAgKRwtJgQARAQARAAgKRwtJgQARAQABNQAECgkJLAADAMYVAA==.Thickthang:BAABNQAECn82AAMZAAoK+yNuAgCFAwAZAAoK+yNuAgCFAwAHAAQKrhYp3gDZAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECn9IAAIiAAoKPCOHAQCPAwAiAAoKPCOHAQCPAwAAAA==.Tinytea:BAABNQAECn9IAAMUAAoKXxxVCwBEAgAUAAoKXxxVCwBEAgAnAAEKAABiLQBSAAAAAA==.Tinytilted:BAAANQADCgEIAQAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgcIDQAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAABNQAECn82AAIMAAoK5wwXOgDBAQAMAAoK5wwXOgDBAQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgUICAAIAAAAAA==.',
Tr='Trusinner:BAABNQAECn8bAAIRAAgKRxjdbgBGAgARAAgKRxjdbgBGAgAAAA==.',
Ts='Tsusha:BAEANQAECgUIEAABNQAECgYIBwAIAAAAAA==.',
Tu='Turkeyleg:BAAANQADCggIHwAAAA==.',
Tw='Twippy:BAABNQAECn8oAAIHAAoKKRP8TABDAgAHAAoKKRP8TABDAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgcIEgABNQAECgQIAwAIAAAAAA==.Tyriam:BAABNQAECn82AAIJAAoKYxs3RQDFAgAJAAoKYxs3RQDFAgAAAA==.',
Ud='Udderchaos:BAAANQAECgMIBQAAAA==.',
Un='Unifey:BAAANQAECgMIAwAAAA==.',
Va='Valess:BAAANQAECgEIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.Varrae:BAAANQADCgIIAgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAACNQAFFH8OAAIkAAUKsRk1AgDVAAAkAAUKsRk1AgDVAAA1AAQKfzUAAiQACgryHlsHAAwDACQACgryHlsHAAwDAAAA.Verso:BAABNQAECn8eAAIoAAgKERnOBgBZAgAoAAgKERnOBgBZAgAAAA==.',
Vi='Vitalithry:BAABNQAECn8oAAMmAAkKKxg3BgBrAgAmAAkKKxg3BgBrAgAkAAMKThdtDwDdAAAAAA==.Vivii:BAAANQAECgcICwAAAA==.Vizzysmash:BAAANQAECgYIBgABNQAECgoKOQADAJ4dAA==.',
Vo='Voden:BAAANQABCgUIBwAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECn9BAAMOAAoKihf8HADkAQAOAAoKihf8HADkAQALAAUKuwxvjADQAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAABNQAECn8uAAMHAAkKFCFLJwDmAgAHAAkKFCFLJwDmAgAGAAMKqxTn2wCwAAAAAA==.',
Wi='Wiiska:BAACNQAFFH8NAAITAAUKsBDfAwAxAQATAAUKsBDfAwAxAQA1AAQKfzIAAxMACgp0HMkUAL0CABMACgp0HMkUAL0CABIABwqzCMZ2APIAAAAA.Wildling:BAAANQADCgIIAwAAAA==.Windoelicker:BAAANQADCgcIFwAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgoKGwAPACojAA==.Wrlccywhefr:BAABNQAECn81AAQBAAoK0yOhFAB8AgABAAgKfCGhFAB8AgACAAcKwiPYIgBwAgAoAAYKph/HCQDnAQAAAA==.',
Wu='Wuggles:BAABNQAECn8eAAIlAAkKORdHGgBnAgAlAAkKORdHGgBnAgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAABNQAECn8jAAIPAAkKvRpHdwAhAgAPAAkKvRpHdwAhAgAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwARAEcYAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQAECgYIDAAAAA==.',
Ye='Yetil:BAABNQAECn8WAAIEAAgKYQ07fACkAQAEAAgKYQ07fACkAQAAAA==.',
Yn='Ynotraw:BAACNQAFFH8FAAIRAAMKEhkXDgDwAAARAAMKEhkXDgDwAAA1AAQKfzIAAhEACgocIo8MAJMDABEACgocIo8MAJMDAAAA.Ynotstorm:BAAANQAECgQIBAAAAA==.',
Yo='Yourephired:BAABNQAECn8lAAMKAAgKFQ9iEgCBAQAKAAgKFQ9iEgCBAQAQAAEKAAAp2gEoAAAAAA==.',
Za='Zaerix:BAAANQADCgYICQAAAA==.Zaknafein:BAAANQAECgMIBAABNQAECgoKOQAKAF4bAA==.Zarah:BAAANQAECgEIAQAAAA==.Zaycursed:BAAANQAECgQICgABNQAECggIHgAHABQfAA==.Zaydream:BAAANQADCgcIBwABNQAECggIHgAHABQfAA==.Zaylight:BAAANQADCggICAABNQAECggIHgAHABQfAA==.Zayseer:BAABNQAECn8eAAIHAAgKFB+TOACUAgAHAAgKFB+TOACUAgAAAA==.',
Ze='Zello:BAABNQAECn8dAAMSAAkKnARhbwAIAQASAAgKdARhbwAIAQATAAQKcATnYAB+AAAAAA==.',
Zh='Zhengy:BAAANQAECgQIDwABNQAECgoKOQAKAF4bAA==.',
Zi='Ziggybeast:BAABNQAECn8hAAQWAAoKWx1dNwAyAgAWAAgK/R1dNwAyAgAlAAgKnBgoJAAEAgAfAAEKAADIZAArAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgQIEgAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggIHgAHABQfAA==.',
['ßb']='ßbõÿ:BAAANQAECgIIAgAAAA==.',
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
