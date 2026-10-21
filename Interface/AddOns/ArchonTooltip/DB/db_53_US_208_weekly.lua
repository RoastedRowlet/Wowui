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

local lookup = {'Rogue-Assassination','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Frost','DeathKnight-Blood','Warlock-Demonology','Rogue-Subtlety','Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Arcane','Warrior-Arms','Priest-Holy','Priest-Shadow','Monk-Windwalker','Druid-Feral','Druid-Balance','Warlock-Destruction','Paladin-Protection','DeathKnight-Frost','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Priest-Discipline','Monk-Mistweaver','Warlock-Affliction','Druid-Guardian','Warrior-Fury','Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Druid-Restoration','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aanna:BAAANQADCgUIBQAAAA==.',
Ab='Abor:BAAANQAECgcIDQAAAA==.Abuela:BAABNQAECn8rAAIBAAoKvxxsDQAZAwABAAoKvxxsDQAZAwAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ad='Adaela:BAAANQADCgIIAgABNQAECgkJIgABACIaAA==.',
Ae='Aegla:BAABNQAECn8rAAICAAkKxhVjPwAgAgACAAkKxhVjPwAgAgAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ag='Aghlath:BAAANQAECgYICAAAAA==.',
Ak='Akiko:BAAANQAECgYIDQABNQAECgoKKAADAFMaAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFH8QAAIEAAQKQxKqBwCsAAAEAAQKQxKqBwCsAAA1AAQKfykAAgQACQrTHD0NANICAAQACQrTHD0NANICAAAA.Alliar:BAABNQAECn8nAAMFAAoKUxwnKwC2AgAFAAoKUxwnKwC2AgAGAAYKPwl5rAA7AQAAAA==.Allynstraza:BAABNQAECn8VAAIEAAYKARClKgBYAQAEAAYKARClKgBYAQAAAA==.',
Am='Amgems:BAAANQAECgQIBQAAAA==.Amordred:BAAANQAECgQIDgAAAA==.',
An='Anasterion:BAABNQAECn8VAAIHAAgK8CAlbgBUAgAHAAgK8CAlbgBUAgAAAA==.Andarus:BAABNQAECn8WAAIHAAYKWhJGUgAgAQAHAAYKWhJGUgAgAQABNQAECgoKMQAIAF0XAA==.Ankles:BAABNQAECn8nAAMJAAkKfiPRBwB/AwAJAAkKfiPRBwB/AwACAAIK+glCzwBPAAAAAA==.Ansley:BAAANQADCgUICAABNQAECgkJIgABACIaAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgEIAQABNQAECgoKNwAKAOIcAA==.',
As='Ashli:BAABNQAECn8iAAMBAAkKIhrwCgB2AQABAAgK+BvwCgB2AQALAAEKHA+QTQA9AAAAAA==.',
At='Atlasbär:BAAANQAECgQIBAABNQADCgYIDwAMAAAAAA==.Atlasdark:BAAANQAECggIDwABNQADCgYIDwAMAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.',
Ba='Balrock:BAAANQAECgIIBQAAAA==.Balthromaw:BAABNQAECn8iAAIKAAkKZRVBEgCzAQAKAAkKZRVBEgCzAQAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQAMAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECgQIBAABNQAFFAMIBQANAIoKAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Bellum:BAAANQAECgMIAwAAAA==.Belstab:BAABNQAECn8tAAMLAAgK/g/XGwD3AQALAAgKhw/XGwD3AQABAAcKcwkNTgCHAQAAAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIEAABNQAECgoKGQAOAEwhAQ==.',
Bg='Bgbalkoth:BAAANQADCgYIDAAAAA==.',
Bi='Bifurthegrey:BAAANQAECgQIAwAAAA==.Bigblammy:BAAANQADCggICAABNQAFFAYIGAAPAO4dAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQABNQAECgYIEAAMAAAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Blinkss:BAAANQAECgYIBgAAAA==.Bloodavenger:BAABNQAECn8dAAMDAAkKZgx0ZgDkAQADAAkKZgx0ZgDkAQAHAAUK9wb3KgHZAAAAAA==.Bloodemongar:BAABNQAECn8VAAICAAkK4AxRZgB3AQACAAkK4AxRZgB3AQAAAA==.Bloodhoundss:BAABNQAECn8gAAIQAAgKBhVRHgCKAQAQAAgKBhVRHgCKAQAAAA==.Blössöm:BAAANQAECgQICgAAAA==.',
Bo='Bobdk:BAACNQAFFH8cAAMCAAYKlR0FBAD0AQACAAYKlR0FBAD0AQAJAAEKAADsOAAgAAA1AAQKfy4AAgIACgr9ITEWAAkDAAIACgr9ITEWAAkDAAAA.Bomboklaat:BAAANQADCgMIBAAAAA==.Boomfrin:BAAANQAECgUICgAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECn8lAAMRAAkK6BA6WQAWAgARAAkK6BA6WQAWAgASAAEKXAWlewAxAAAAAA==.',
Br='Braegen:BAAANQAECgYIDgABNQAECgoKMQAIAF0XAA==.Brewslee:BAAANQADCggICAAAAA==.Brewsleê:BAAANQAECgQIBAAAAA==.Bruceleett:BAABNQAECn8qAAITAAkKlRE7BADeAQATAAkKlRE7BADeAQABNQADCgcIFwAMAAAAAA==.',
Bu='Buffmeister:BAAANQAECgUIBQAAAA==.Bullioss:BAAANQAECgIIBwABNQAECgoKGQAOAEwhAA==.',
['Bö']='Böbbyboucher:BAABNQAECn8fAAIGAAcK8x60PwB2AgAGAAcK8x60PwB2AgAAAA==.',
Ca='Cainn:BAAANQADCggIEwABNQAECggIJQAHALgVAA==.Caldrid:BAAANQADCgYIDwAAAA==.Calfurion:BAABNQAECn8VAAMUAAgKqB3zEAD4AQAVAAcKShxEPwAAAgAUAAYK1B7zEAD4AQAAAA==.Calvary:BAAANQAECggIDAABNQAECggIFQAUAKgdAA==.Capncrunch:BAAANQADCgUIBQAAAA==.Cazleah:BAABNQAECn8vAAIGAAoKsyB9CwC4AQAGAAoKsyB9CwC4AQAAAA==.',
Ce='Cessatio:BAABNQAECn8ZAAIWAAUKXQZmCgB4AAAWAAUKXQZmCgB4AAAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAABNQAECn8hAAIHAAoKMBtcCgA4AgAHAAoKMBtcCgA4AgABNQAECgoKPwALAG8eAA==.Chrisbrewn:BAABNQAECn8kAAIQAAkKzhMkcgA+AgAQAAkKzhMkcgA+AgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clevelandoe:BAACNQAFFH8FAAINAAMKigoPGQC5AAANAAMKigoPGQC5AAA1AAQKfzAAAw0ACQpUI2EOAPwCAA0ACQpSIWEOAPwCAA4ABQocG8KnALYBAAAA.',
Co='Cobbknob:BAAANQAECgQIBAAAAA==.Cocobear:BAAANQAECgEIAQAAAA==.Coeurdeleon:BAABNQAECn8dAAMHAAoKTxTxhAAeAgAHAAoKTxTxhAAeAgAXAAEKAAC2ZgBHAAAAAA==.Cokakilla:BAAANQADCgUIAwAAAA==.Condemnation:BAABNQAECn8zAAIRAAoKQRlhEQDrAQARAAoKQRlhEQDrAQAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgYICgABNQADCggIDQAMAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQAMAAAAAA==.Coriantumr:BAAANQADCgYIBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQAECgQIBQAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbazar:BAAANQABCgcJCwAAAA==.Curbstomped:BAABNQAECn8dAAMOAAoKlhIzbwAzAgAOAAoKlhIzbwAzAgANAAMK7gN0bgB2AAAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgYICAABNQAFFAcIEwAPABQiAA==.Darkvizzy:BAABNQAECn8uAAQCAAkKSRa+BgDCAQACAAgKIRS+BgDCAQAJAAcKag8jZABhAQAYAAIK3gqYlwBlAAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgUIBgAAAA==.Demiplo:BAABNQAECn8gAAIOAAgK6xKFegAZAgAOAAgK6xKFegAZAgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQAMAAAAAA==.Denelak:BAABNQAECn8hAAMOAAoKZx8QEgBYAwAOAAoK2x0QEgBYAwANAAkKcxcqGQCOAgAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAAANQAECggIDgABNQAECgoKKwABAL8cAA==.',
Di='Dirtycasual:BAAANQAECggICwABNQAECgoKKwABAL8cAA==.Discipline:BAABNQAECn8sAAMXAAkKBRz0BgCOAQAHAAgKchU8mQDxAQAXAAgKyRz0BgCOAQAAAA==.',
Do='Doggo:BAAANQAECgEIAQAAAA==.Dotsurdead:BAAANQAECggICAAAAA==.',
Dr='Dratr:BAABNQAECn8dAAIZAAkKAguwFwDtAQAZAAkKAguwFwDtAQAAAA==.Draxyl:BAABNQAECn8tAAMJAAoKxhSBFgAzAQACAAkKJA/aSgDqAQAJAAoKFRCBFgAzAQAAAA==.Drekhan:BAAANQAECgQICAABNQAECgoKMQAIAF0XAA==.Drham:BAABNQAECn8kAAIaAAkKJQ4vKQD6AQAaAAkKJQ4vKQD6AQAAAA==.Drogbar:BAAANQAECgEIAQABNQAECgkJIwATAO4VAA==.Drokos:BAAANQAECgYIBwABNQAECgoKGQAOAEwhAA==.Drtree:BAAANQADCgcIBwAAAA==.Druni:BAAANQADCgEIAQAAAA==.',
Du='Dunhambones:BAABNQAECn8tAAICAAoK5B8jBAAEAgACAAoK5B8jBAAEAgAAAA==.Duo:BAABNQAECn8oAAIbAAoKlhPSAQBwAgAbAAoKlhPSAQBwAgABNQAECgcIDQAMAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Elcosote:BAAANQAECgEIAQAAAA==.Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQAECgUICQAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECn8vAAQRAAoK+hIYNgAoAQARAAoK+hIYNgAoAQASAAIK6QGceQA1AAAcAAEK/gUdKQAyAAAAAA==.Elèctra:BAAANQAECgcIDQAAAA==.',
En='Engraver:BAAANQADCggICAAAAA==.Enochs:BAAANQADCgIIAgAAAA==.Enyô:BAAANQADCgQIBAABNQAECgcIHwAGAPMeAA==.',
Er='Erada:BAABNQAECn8jAAMIAAkK8xWtDgC/AQAPAAgKHBaWjABmAgAIAAYK6hitDgC/AQAAAA==.',
Ev='Evoklando:BAAANQADCgUICgABNQAFFAMIBQANAIoKAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exlo:BAAANQABCgIIAgAAAA==.Exorcism:BAAANQADCgcIDAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIAwABNQAECgcIDQAMAAAAAA==.',
Fe='Felad:BAABNQAECn8oAAMdAAgKFibUAAA+AwAdAAgKFibUAAA+AwATAAEKAACXZwBAAAABNQAECgUICQAMAAAAAA==.Felwen:BAAANQAFFAIIAwAAAA==.',
Fh='Fhalanx:BAAANQAECgEIAQAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECgcIDgABNQAECgoKGQAGAKINAA==.Flappyy:BAABNQAECn8ZAAMGAAoKog1CFAB4AQAGAAoKog1CFAB4AQAFAAMKNAZ6+gB2AAAAAA==.Flowdinstuna:BAABNQAECn8ZAAIaAAoKlRVCGgCHAgAaAAoKlRVCGgCHAgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAABNQAECn8sAAIOAAoK2BioRACdAgAOAAoK2BioRACdAgAAAA==.Freakmage:BAAANQADCgUIBQAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.',
Fu='Furrybait:BAEANQAECgQIBwAAAA==.Furyiosa:BAABNQAECn8eAAIQAAoK7xiLGgCbAQAQAAoK7xiLGgCbAQAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgAMAAAAAA==.Gaiseric:BAABNQAECn8kAAICAAgK0hq3PwAfAgACAAgK0hq3PwAfAgAAAA==.Gamago:BAAANQAECggIBAAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECn8cAAQWAAkKix5CKAA2AQAKAAcKWBpmcQAMAgAWAAQKCh9CKAA2AQAeAAEKAADLKQBFAAAAAA==.Getoverhere:BAAANQADCggICwAAAA==.',
Gi='Girltank:BAAANQAECgIIBAAAAA==.',
Gn='Gnarlak:BAAANQAECgEIAgAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gotboned:BAAANQAECgcIDAABNQAFFAYIBgAfAGMeAA==.Gotfleas:BAACNQAFFH8GAAIfAAYKYx6WAAA6AgAfAAYKYx6WAAA6AgA1AAQKfyMAAx8ACQr1JSQBANsDAB8ACQr1JSQBANsDABQAAQpkAAAAAAAAAAAA.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAABNQAECn8sAAIaAAoKWhIOCQB/AQAaAAoKWhIOCQB/AQAAAA==.Greyfax:BAABNQAECn8gAAIDAAkKMx5SGQATAwADAAkKMx5SGQATAwAAAA==.Grimthruul:BAABNQAECn8iAAIGAAgK2QfRjQCBAQAGAAgK2QfRjQCBAQAAAA==.Grommkar:BAABNQAECn8jAAIQAAkKDg7IkADyAQAQAAkKDg7IkADyAQAAAA==.Grumpig:BAAANQADCgQIDAAAAA==.Grèggory:BAAANQAECgIIAgAAAA==.',
Gu='Gusari:BAEANQAECgEIAQABNQAECggIDAAMAAAAAA==.Gutx:BAAANQADCgQIBAAAAA==.',
Ha='Hadmeathello:BAAANQAECgIIAgAAAA==.Halucination:BAABNQAECn8dAAMSAAkK7wxiJAAOAgASAAkK7wxiJAAOAgARAAIKlwRr7QBcAAAAAA==.Harthan:BAABNQAECn8ZAAMQAAcK+xPFnQDSAQAQAAcK+xPFnQDSAQAgAAEKkQ5UFgA+AAAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayden:BAAANQAECggIEgAAAA==.Hayleigh:BAAANQADCgYIBwAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwAMAAAAAA==.Helya:BAAANQADCgMIBAAAAA==.Henchman:BAAANQABCgQICAABNQAECgoKGQAOAEwhAA==.Hetzák:BAABNQAECn8sAAIVAAoKYhFzOgAfAgAVAAoKYhFzOgAfAgAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBgAAAA==.Hintolisu:BAABNQAECn8uAAIUAAoK8Rw3BgANAwAUAAoK8Rw3BgANAwAAAA==.',
Ho='Hobbess:BAABNQAECn8UAAIaAAgK9BB3LADeAQAaAAgK9BB3LADeAQABNQAFFAgIJwAVAO8lAA==.Holybaloney:BAABNQAECn8jAAMXAAoKeRzKEQCEAgAXAAgKFx/KEQCEAgAHAAkKtAhWLwByAQAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Holyvaj:BAAANQAECgIIAgABNQAECgQIBAAMAAAAAA==.Hongis:BAAANQAECgEIAQAAAA==.Hoofinit:BAABNQAECn8kAAIQAAkKgh9tKgARAwAQAAkKgh9tKgARAwAAAA==.',
Hu='Huatarm:BAABNQAECn8qAAIhAAoKuRgMDQBiAgAhAAoKuRgMDQBiAgAAAA==.',
Ia='Iadygaga:BAAANQAECggIEwAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECgkJKwACAMYVAA==.',
Ir='Ironspin:BAAANQAECgQIBgAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Ja='Jaark:BAACNQAFFH8NAAIKAAUKqg4iCgDNAAAKAAUKqg4iCgDNAAA1AAQKfy4AAwoACgoAHjomAOsCAAoACgoAHjomAOsCAB4AAwpOHbwHALMAAAAA.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgIIBQABNQAECgkJIgABACIaAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jehanne:BAAANQADCgQIBQAAAA==.Jen:BAABNQAECn80AAIRAAoKhxXVLABJAQARAAoKhxXVLABJAQAAAA==.',
Jo='Jocon:BAAANQADCggIGwAAAA==.',
Ju='Jugulator:BAAANQADCggIEAAAAA==.Jumpey:BAABNQAECn8aAAMiAAcK4BRmEACrAQAiAAYKnhhmEACrAQAjAAUKFQmfaQDSAAABNQAECggIIQAkAC4YAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAABNQAECn8kAAIGAAkKDRosMQC2AgAGAAkKDRosMQC2AgABNQAECgQIBgAMAAAAAA==.Kanami:BAABNQAECn8XAAIQAAcK2hTTOQAzAQAQAAcK2hTTOQAzAQAAAA==.Kaynyx:BAABNQAECn8uAAILAAoKCB3oBgAQAwALAAoKCB3oBgAQAwAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAABNQAECn8lAAIHAAgKuBWqfAAxAgAHAAgKuBWqfAAxAgAAAA==.Kenzie:BAAANQAECgMIAwAAAA==.Kerb:BAABNQAECn8fAAQJAAgK+A31GQAeAQAJAAgK+A31GQAeAQAYAAIK3gbXmQBgAAACAAEKAAAn6AAsAAAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECn8aAAMaAAgK7hjYJwAFAgAaAAgK4xTYJwAFAgAjAAQKtBckYAD8AAAAAA==.',
Ki='Kikiko:BAAANQADCgUIBQAAAA==.Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECn8WAAIjAAgKDxfMMQAbAgAjAAgKDxfMMQAbAgAAAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQAHAPAgAA==.',
Kl='Klaris:BAAANQAECgQIBAAAAA==.',
Kn='Knewtoomuch:BAAANQADCgcIBwAAAA==.',
Ko='Konjur:BAACNQAFFH8YAAMPAAYK7h1pCwAdAgAPAAYK7h1pCwAdAgAIAAEKEh6GBQBeAAA1AAQKfx8AAg8ACgr7JFs4ABcDAA8ACgr7JFs4ABcDAAAA.',
Kr='Krelock:BAAANQAECgYICgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgIIBAABNQAECgoKPwAhABYZAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
Ky='Kytheon:BAAANQADCgIIAgAAAA==.',
['Kâ']='Kâmø:BAAANQAECgQIBgAAAA==.',
['Kä']='Kämo:BAAANQAECgIIAwABNQAECgQIBgAMAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgUICwABNQAFFAUIDAAlAEsiAA==.Lakeyy:BAACNQAFFH8MAAIlAAUKSyIIAwBiAQAlAAUKSyIIAwBiAQA1AAQKfzEAAyUACgobJY8CAKQDACUACgobJY8CAKQDABUABAppHRMrALYAAAAA.Lakeyys:BAAANQAECgEIAQABNQAFFAUIDAAlAEsiAA==.Lanuor:BAAANQADCgEIAQAAAA==.Laufey:BAAANQADCgcIBQAAAA==.Lavagobrr:BAAANQAECgQIBAAAAA==.Lawrence:BAACNQAFFH8MAAIFAAUKBw/TBgA1AQAFAAUKBw/TBgA1AQA1AAQKfykAAwUACgrfHtYtAKsCAAUACgrfHtYtAKsCAAYAAwo9GCDsAL8AAAAA.',
Le='Lesaeria:BAABNQAECn8aAAIaAAkKQRlXGgCGAgAaAAkKQRlXGgCGAgABNQAECgoKKwAZANAfAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQAECgIIAgAAAA==.Lightsardine:BAAANQADCgIIAgAAAA==.Lilikoii:BAAANQAECgIIAgABNQAFFAUIDAAlAEsiAA==.Liljit:BAAANQAECgEIAgABNQAECgoKKAADAFMaAA==.Lilslaver:BAABNQAECn8WAAIOAAcK+wY/YwDkAAAOAAcK+wY/YwDkAAAAAA==.Lisex:BAACNQAFFH8LAAMYAAUKTwz9DAAPAQAYAAQKTwz9DAAPAQAJAAEKAAByNQApAAA1AAQKfyIAAxgACQpNIU0YAMgCABgACQpNIU0YAMgCAAkAAQoiFu3FAD0AAAAA.Lithe:BAABNQAECn85AAIHAAoKLB0bEwDjAQAHAAoKLB0bEwDjAQABNQAECgoKQgAGAL4fAA==.',
Lo='Lockjhaw:BAAANQAFFAEIAQAAAA==.Locklear:BAABNQAECn8xAAIHAAgK1hQALQB5AQAHAAgK1hQALQB5AQAAAA==.Logic:BAACNQAFFH8eAAQbAAcK1RYZAAAKAgAbAAYK8hYZAAAKAgAPAAYKYhM3EwDdAQAIAAMKIRj/AgD3AAA1AAQKfy0AAw8ACgryICtaAMsCAA8ACgrHICtaAMsCABsAAwqjIJ0FAB8BAAAA.Lola:BAAANQAECgMIAgABNQAFFAUIDAAlAEsiAA==.Lolbrez:BAAANQAECggIBgAAAA==.',
Lu='Lunanarn:BAAANQADCgEIAQAAAA==.Lunaria:BAAANQAECgUIBgABNQAFFAUIDAAlAEsiAA==.Lusty:BAABNQAECn8hAAIkAAgKLhgEEQBFAgAkAAgKLhgEEQBFAgAAAA==.Luthix:BAAANQABCggIDwAAAA==.Luxe:BAAANQAECgIIAgABNQAFFAUIDAAlAEsiAA==.',
Ma='Macediin:BAABNQAECn8cAAICAAgKrBnaCACmAQACAAgKrBnaCACmAQAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECn8aAAIaAAkKiByaHABwAgAaAAkKiByaHABwAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgkJJgANAM8ZAA==.Magnolìa:BAAANQAECgUICQAAAA==.Malefic:BAAANQAECgMIAwABNQAFFAYIGAAPAO4dAA==.Malthael:BAABNQAECn8rAAMCAAoKXBWHPQApAgACAAkKdheHPQApAgAYAAgKlg0nUwBjAQAAAA==.Mamageek:BAAANQAECggIEwAAAA==.Mami:BAAANQAECgEIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECgkJKAAGAGofAA==.Manix:BAAANQAECgUICgABNQAECggICQAMAAAAAA==.Mareo:BAAANQAECgQIBQAAAA==.Marksterique:BAABNQAECn8mAAINAAkKzxmaGQCKAgANAAkKzxmaGQCKAgAAAA==.Masochist:BAAANQAECgIIAgAAAA==.',
Me='Meeko:BAACNQAFFH8QAAIEAAcKuBYyBAA5AgAEAAcKuBYyBAA5AgA1AAQKf0sAAgQACgpeIgoGAEkDAAQACgpeIgoGAEkDAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgMIAwAAAA==.Metalbound:BAAANQAECgQICgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAABNQAECn8bAAIZAAgKqSSzBgAZAwAZAAgKqSSzBgAZAwAAAA==.Misslobster:BAABNQAECn8VAAIFAAYKcg/6oQAxAQAFAAYKcg/6oQAxAQAAAA==.',
Mo='Mokoko:BAABNQAECn8vAAIkAAoKgRs3CwC0AgAkAAoKgRs3CwC0AgAAAA==.Mokolock:BAAANQAECgUICAABNQAECgoKLwAkAIEbAA==.Moomoo:BAABNQAECn8oAAIVAAkKFh4dFQAeAwAVAAkKFh4dFQAeAwAAAA==.Moorlin:BAAANQAECgUIBwAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgoKLwAkAIEbAA==.',
My='Myka:BAAANQAECggICQAAAA==.Mysticphatty:BAAANQADCggJCAABNQAECgIIAgAMAAAAAA==.Myyst:BAAANQAECgMIAwAAAA==.',
Na='Nawtalhere:BAAANQADCgQIBAABNQAECgoKLQAJAFAiAA==.',
Ne='Necro:BAABNQAECn8fAAICAAkKix3WIwCzAgACAAkKix3WIwCzAgAAAA==.Necrota:BAABNQAECn8ZAAMJAAkKZxoCMwBCAgAJAAkK4hgCMwBCAgACAAEKOiGUxABiAAABNQAFFAYIGAAPAO4dAA==.Nekronomicon:BAAANQADCggICgABNQAECgoKMwARAEEZAA==.Neuron:BAACNQAFFH8UAAMlAAYKkhvwAQClAQAlAAYKkhvwAQClAQAVAAQKUAd5FwDyAAA1AAQKfyIAAyUACgpaGgsSAMACACUACgpaGgsSAMACABUABgpGEFpXAHkBAAAA.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAABNQAECn8uAAIfAAgK2R/FCADtAgAfAAgK2R/FCADtAgAAAA==.Nightflame:BAAANQAECgQJCAAAAA==.Ninjavc:BAABNQAECn8bAAIBAAcK/gf4GQD7AAABAAcK/gf4GQD7AAAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAAANQAECgYICgAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQAECgUIBgAAAA==.',
Of='Offbrand:BAAANQAECggICAAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Olpheux:BAAANQAECgMIAwAAAA==.',
On='Onayro:BAAANQABCgIIAgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgQICgAAAA==.Oreyn:BAAANQAECgcIDQAAAA==.Organ:BAAANQAECgcIDAAAAA==.Orngar:BAAANQADCgMIAwAAAA==.',
Pa='Padle:BAAANQAECggIDgAAAA==.Paladín:BAABNQAECn8uAAMXAAoK6BWvGgAaAgAXAAgKUhevGgAaAgAHAAYKcA9QbQDrAAAAAA==.Palazar:BAABNQAECn8tAAIHAAoKuCD/MgAAAwAHAAoKuCD/MgAAAwAAAA==.Paoka:BAAANQADCgQIBwABNQADCggIEQAMAAAAAA==.Pappamidnite:BAAANQAECggICAAAAA==.Pargonz:BAABNQAECn8/AAMLAAoKbx6ZAQCfAgALAAoKbx6ZAQCfAgABAAIKlw6sjwBzAAAAAA==.Patoko:BAABNQAECn8lAAIZAAkKEhyACgDKAgAZAAkKEhyACgDKAgAAAA==.Paxwet:BAAANQAECgIIAgAAAA==.Payn:BAAANQAECgUICQAAAA==.Paypay:BAABNQAECn82AAIlAAkKFx+gCQAsAwAlAAkKFx+gCQAsAwAAAA==.',
Ph='Phalannx:BAAANQAECgIIAwAAAA==.Philipx:BAAANQAECgEIAQAAAA==.Phinks:BAAANQADCgIIAgABNQAECgoKPgAZAMgiAA==.',
Pi='Piglittle:BAAANQAECgYIDQAAAA==.Pindad:BAABNQAECn8ZAAIOAAoKTCElDQB2AwAOAAoKTCElDQB2AwAAAA==.',
Pl='Plzdispelme:BAABNQAECn8oAAMDAAoKUxo8LwCpAgADAAoKUxo8LwCpAgAHAAEKAACWpgE0AAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAABNQAECn8eAAIWAAgKIREwDwAIAgAWAAgKIREwDwAIAgAAAA==.',
Pr='Priesticles:BAAANQAECgcICQABNQADCgcIFwAMAAAAAA==.Proshvam:BAAANQAECgEIAQAAAA==.',
Pu='Purrzac:BAAANQAECggICAABNQAECgoKKAADAFMaAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Racialskill:BAAANQAECggICQABNQAECgoKKAADAFMaAA==.Ragingmonkx:BAABNQAECn8jAAITAAkK7hXlIAAlAgATAAkK7hXlIAAlAgAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Raventer:BAABNQAECn8UAAIOAAcKmg/0pAC8AQAOAAcKmg/0pAC8AQAAAA==.Razdrood:BAAANQADCgUIAwABNQAECgYICAAMAAAAAA==.Razlock:BAAANQAECgYICAAAAA==.Razorclaws:BAAANQAECgQIBwAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAABNQAECn8fAAICAAkKbxfEBgDCAQACAAkKbxfEBgDCAQAAAA==.',
Ro='Roguesucks:BAAANQADCggIDQAAAA==.Rollos:BAABNQAECn8iAAIKAAkKyht7HAB9AQAKAAkKyht7HAB9AQAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAABNQAFFH8TAAMPAAcKFCLGBQBnAgAPAAYKqiLGBQBnAgAIAAEKux+ICwBfAAAAAA==.Ryujinsimp:BAACNQAFFH8MAAMkAAUKURr8BAB2AQAkAAUKURr8BAB2AQAmAAQKrxR/BgAbAQA1AAQKfyIAAyYACQq/JO0DANwCACQACQo1IsIIAOoCACYACAo9JO0DANwCAAE1AAUUBwgTAA8AFCIA.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMIAwAMAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAUIDgARABgaAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECn8jAAIEAAkKggwRHwDiAQAEAAkKggwRHwDiAQAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAACNQAFFH8PAAQeAAYKEBSjBAClAAAeAAIKGhSjBAClAAAKAAMKrBdAGABYAAAWAAEK0AxjHgBLAAA1AAQKf7gABB4ACgrdJUUBAFIDAAoACAr6JbQPAFQDAB4ACQq+JEUBAFIDABYABwoDJDAEAOwCAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAFFAMIBQANAIoKAA==.Shamanigans:BAAANQADCgYIDwAAAA==.Shangzha:BAABNQAECn8rAAIZAAoK0B/kBQAqAwAZAAoK0B/kBQAqAwAAAA==.Shareholder:BAEBNQAECn8gAAIKAAoKDCTxAAApAwAKAAoKDCTxAAApAwABNQAFFAUICAAPAK0ZAA==.Shiivera:BAABNQAECn8rAAIFAAoKmh3AMQCZAgAFAAoKmh3AMQCZAgAAAA==.Shimada:BAABNQAECn8oAAIOAAoKcBzmKAD0AgAOAAoKcBzmKAD0AgAAAA==.Shotsyll:BAACNQAFFH8IAAIOAAMKfRTfFgADAQAOAAMKfRTfFgADAQA1AAQKfxcAAg4ACAqtG0oxAF0BAA4ACAqtG0oxAF0BAAAA.',
Sk='Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAABNQAECn8kAAMBAAkKyxxEAQCtAgABAAkKYRxEAQCtAgALAAcKBhU+HQDpAQAAAA==.Skynomad:BAAANQAECgYIEgAAAA==.',
Sl='Slyde:BAABNQAECn8hAAICAAcKWyOsJQCoAgACAAcKWyOsJQCoAgAAAA==.',
Sm='Smalldk:BAABNQAFFH8IAAMJAAIKAAAzJwBdAAAJAAEKAAAzJwBdAAACAAEKAAB2JQA2AAABNQAFFAYIEgAHALEVAA==.Smallrichard:BAAANQAECgEIAQABNQAECggIIQAPAGUWAA==.Smashytash:BAAANQAECgcIDAAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAABNQAECn8XAAIDAAcKIg/shgCGAQADAAcKIg/shgCGAQAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgcIDAAMAAAAAA==.',
Sn='Snek:BAAANQAECgEIBAAAAA==.Snowing:BAAANQAECgYICQABNQAECggIEgAMAAAAAA==.Snugglybear:BAABNQAECn8UAAIfAAcKfx6jDgB6AgAfAAcKfx6jDgB6AgABNQAFFAQIBQAJAMIZAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Sodlid:BAAANQAECgMIBAABNQAECgQIBQAMAAAAAA==.Solariaa:BAAANQAECgIIAwABNQAFFAUIDAAlAEsiAA==.Solfreid:BAAANQAECgYIEAAAAA==.Sophism:BAAANQAECggIDwABNQAFFAcIHgAbANUWAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAJAFAmAA==.Soulfang:BAABNQAECn8mAAIgAAcKyRQbBgBAAQAgAAcKyRQbBgBAAQAAAA==.Soulfox:BAAANQADCgQIBAABNQAECgcIDQAMAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAAANQAECgYIDAABNQAFFAQIBQALAOwFAA==.Sprocketrot:BAAANQAECggIEgAAAA==.',
Sq='Squidmonk:BAABNQAECn8aAAIdAAkKoQ5xGwDLAQAdAAkKoQ5xGwDLAQAAAA==.',
St='Stardrive:BAACNQAFFH8MAAIQAAUK5QcMDQDEAAAQAAUK5QcMDQDEAAA1AAQKfyQAAhAACgp8EVl/AB0CABAACgp8EVl/AB0CAAAA.Steelwhacka:BAABNQAECn8VAAMTAAgK7gs8MgCFAQATAAgK7gs8MgCFAQAdAAUKgwtxMgDWAAAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFH8XAAITAAYKaRygBAD2AQATAAYKaRygBAD2AQA1AAQKfyUAAhMACgrGHiMUALYCABMACgrGHiMUALYCAAAA.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAAANQAECggIDQAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQAECgEIAQABNQAECgYIEgAMAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgQICgAAAA==.Surtur:BAABNQAECn89AAIQAAoKqBpNEwC/AQAQAAoKqBpNEwC/AQAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECgoKLgAXAOgVAA==.',
Sy='Sygismund:BAABNQAECn8dAAMjAAgKIwWPKwC+AAAjAAgKIwWPKwC+AAAaAAIK3ADHOwASAAAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAABNQAECn8uAAIOAAoKGBwnJAAGAwAOAAoKGBwnJAAGAwAAAA==.Taotien:BAAANQAECgcICgAAAA==.Tashbringer:BAAANQAECgIIAwABNQAECgcIDAAMAAAAAA==.',
Tc='Tchaik:BAABNQAECn8tAAMRAAoKZCA4FQAmAwARAAoKZCA4FQAmAwASAAEKAABDeQA1AAAAAA==.',
Te='Tecknicaliti:BAAANQADCgIIAgAAAA==.Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgUIDwAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQAECgMIBgAAAA==.Theios:BAABNQAECn8bAAIQAAgKRwvUPwAkAQAQAAgKRwvUPwAkAQABNQAECgkJKwACAMYVAA==.Thickthang:BAABNQAECn8yAAMZAAoK+yNuAgCFAwAZAAoK+yNuAgCFAwAGAAQKrhYp3gDZAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECn8+AAIiAAoKFSOcAACmAgAiAAoKFSOcAACmAgAAAA==.Tinytea:BAABNQAECn8+AAMTAAoKxhsvAwAPAgATAAoKxhsvAwAPAgAnAAEKAABiLQBSAAAAAA==.Tinytilted:BAAANQADCgEIAQAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgcIDQAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAABNQAECn8sAAIKAAoKHgyrEAC+AQAKAAoKHgyrEAC+AQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgUICAAMAAAAAA==.',
Tr='Trusinner:BAABNQAECn8bAAIQAAgKRxjdbgBGAgAQAAgKRxjdbgBGAgAAAA==.',
Ts='Tsusha:BAEANQAECgUIDwAAAA==.',
Tu='Turkeyleg:BAAANQADCggIHwAAAA==.',
Tw='Twippy:BAABNQAECn8oAAIGAAoKKRP8TABDAgAGAAoKKRP8TABDAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgcIEgABNQAECgQIAwAMAAAAAA==.Tyriam:BAABNQAECn8vAAIHAAoKYxs3RQDFAgAHAAoKYxs3RQDFAgAAAA==.',
Ud='Udderchaos:BAAANQAECgEIAgAAAA==.',
Un='Unifey:BAAANQAECgIIAgAAAA==.',
Va='Valess:BAAANQAECgEIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.Varrae:BAAANQADCgIIAgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAACNQAFFH8MAAIkAAUKsRlHAQDXAAAkAAUKsRlHAQDXAAA1AAQKfzEAAiQACgoyHlsHAAwDACQACgoyHlsHAAwDAAAA.Verso:BAABNQAECn8ZAAIoAAgKZhjOBgBZAgAoAAgKZhjOBgBZAgAAAA==.',
Vi='Vitalithry:BAABNQAECn8gAAImAAgKtBg3BgBrAgAmAAgKtBg3BgBrAgAAAA==.Vivii:BAAANQAECgcICwAAAA==.Vizzysmash:BAAANQADCggICAABNQAECgkJLgACAEkWAA==.',
Vo='Voden:BAAANQABCgIIBAAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECn86AAMYAAoKzRWRBwDeAQAYAAoKzRWRBwDeAQAJAAUKuwxvjADQAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAABNQAECn8oAAMGAAkKah9iDACvAQAGAAkKah9iDACvAQAFAAMKqxTn2wCwAAAAAA==.',
Wi='Wiiska:BAACNQAFFH8NAAISAAUKsBA3AgA6AQASAAUKsBA3AgA6AQA1AAQKfysAAxIACgp0HMkUAL0CABIACgp0HMkUAL0CABEAAgpIAjDxAFAAAAAA.Wildling:BAAANQADCgIIAwAAAA==.Windoelicker:BAAANQADCgcIFwAAAA==.',
Wo='Worgya:BAAANQADCgUIBQABNQAECgcIDQAMAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgoKGQAOAEwhAA==.Wrlccywhefr:BAABNQAECn8uAAQLAAoK0yN+BAACAgABAAcKwiPYIgBwAgALAAcK/CB+BAACAgAoAAYKph/HCQDnAQAAAA==.',
Wu='Wuggles:BAABNQAECn8eAAIlAAkKORdHGgBnAgAlAAkKORdHGgBnAgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAABNQAECn8fAAIOAAkKvxgyNwBNAQAOAAkKvxgyNwBNAQAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwAQAEcYAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQAECgQIBwAAAA==.',
Ye='Yetil:BAAANQAECgcIEwAAAA==.',
Yn='Ynotraw:BAACNQAFFH8FAAIQAAMKEhmzBwAAAQAQAAMKEhmzBwAAAQA1AAQKfzIAAhAACgocIo8MAJMDABAACgocIo8MAJMDAAAA.Ynotstorm:BAAANQAECgQIBAAAAA==.',
Yo='Yourephired:BAABNQAECn8fAAMIAAcKtA5iEgCBAQAIAAcKtA5iEgCBAQAPAAEKAAAp2gEoAAAAAA==.',
Za='Zaerix:BAAANQADCgYICQAAAA==.Zaknafein:BAAANQAECgMIBAABNQAECgoKMQAIAF0XAA==.Zarah:BAAANQAECgEIAQAAAA==.Zaycursed:BAAANQAECgQICgABNQAECggIHgAGABQfAA==.Zaydream:BAAANQADCgcIBwABNQAECggIHgAGABQfAA==.Zaylight:BAAANQADCggICAABNQAECggIHgAGABQfAA==.Zayseer:BAABNQAECn8eAAIGAAgKFB+TOACUAgAGAAgKFB+TOACUAgAAAA==.',
Ze='Zello:BAABNQAECn8WAAMRAAgKGQQOagCXAAARAAcK2QMOagCXAAASAAQKxgPnYAB+AAAAAA==.',
Zh='Zhengy:BAAANQAECgQICwABNQAECgoKMQAIAF0XAA==.',
Zi='Ziggybeast:BAABNQAECn8gAAQVAAoKWx1dNwAyAgAVAAgK/R1dNwAyAgAlAAcKqhgoJAAEAgAfAAEKAADIZAArAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgUIEQAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggIHgAGABQfAA==.',
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
