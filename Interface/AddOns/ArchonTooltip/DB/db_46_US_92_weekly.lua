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

local lookup = {'Warlock-Demonology','Mage-Frost','Mage-Arcane','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Warrior-Arms','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Warrior-Protection','Hunter-BeastMastery','Warlock-Destruction','Druid-Guardian','Druid-Restoration','Druid-Feral','Priest-Discipline','Hunter-Marksmanship','Mage-Fire','Monk-Brewmaster','Warlock-Affliction','Rogue-Outlaw',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abchanchu:BAAALgAECgQJBQAAAA==.Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abrakådabruh:BAABLgAECn8mAAMCAAkJug5LEgBMAQACAAkJSApLEgBMAQADAAQJyBLXBADxAAAAAA==.Absolverator:BAAALgADCgEJAQAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8fAAMEAAkJAh7pJgCOAQAEAAYJwRzpJgCOAQAFAAgJIRQFLwBkAQABLgAFFAcJEAAGAFQFAA==.',
Ae='Aelanori:BAAALgAECgUJBgAAAA==.Aethira:BAAALgAECgEJAwAAAA==.',
Ag='Ageros:BAAALgADCgEJAQAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIHAAkJpiCiFQDBAgAHAAkJpiCiFQDBAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainjel:BAAALgAECgMJBQAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Ak='Akaitsuki:BAAALgAECgkJCgABLgAECgkJLAAHAPUcAA==.',
Al='Alexdh:BAAALgAECgEJAQABLgAFFAEJAQAIAAAAAA==.Alexr:BAAALgAFFAEJAQAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.Altaxia:BAAALgAECgYJBgAAAA==.',
Am='Amarantus:BAAALgAECgYJCQABLgAFFAUJHQAJADgUAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAACLgAFFH8KAAIKAAMJcBx4DwCmAAAKAAMJcBx4DwCmAAAuAAQKfxUAAgoACAnJEOocALUBAAoACAnJEOocALUBAAEuAAUUCAklAAsA7xsA.Anmodru:BAAALgAECgYJBgABLgAFFAgJJQALAO8bAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAIMAAcJxw1rKwBsAQAMAAcJxw1rKwBsAQAAAA==.',
Ap='Apoldelon:BAAALgAECgIJAgAAAA==.',
Aq='Aqulath:BAACLgAFFH8bAAINAAYJzh5AAwBmAQANAAYJzh5AAwBmAQAuAAQKfy4AAg0ACQmFIJwAAMICAA0ACQmFIJwAAMICAAAA.Aquílés:BAAALgAECgQJCQAAAA==.',
Ar='Aragos:BAAALgAECgUJBQAAAA==.Arazensetal:BAABLgAECn9lAAIOAAkJ9SIsAACPAwAOAAkJ9SIsAACPAwAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAgJFQAPABYNAA==.Ardênt:BAAALgAECgEJAQAAAA==.Ariandrel:BAACLgAFFH8FAAIQAAMJvwYDSQCBAAAQAAMJvwYDSQCBAAAuAAQKfx4AAxAACQkdETEsAM8BABAACQkdETEsAM8BABEAAQlbAE+OABQAAAAA.Aridhol:BAABLgAECn8gAAISAAkJ3gOuIQCHAAASAAkJ3gOuIQCHAAAAAA==.Arkaedius:BAACLgAFFH8HAAISAAMJQxZFXwDSAAASAAMJQxZFXwDSAAAuAAQKfywAAhIACQnIJJ0BANMCABIACQnIJJ0BANMCAAAA.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJDAABLgAECgYJCQAIAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.Astravelle:BAAALgAECgQJBAAAAA==.',
At='Athenä:BAABLgAECn9bAAIMAAkJbCQEAQAqAwAMAAkJbCQEAQAqAwAAAA==.Ation:BAAALgAECgIJCAAAAA==.Atulno:BAAALgAECgcJCQAAAA==.',
Au='Aubrii:BAAALgAECgUJBwAAAA==.Aukatsang:BAACLgAFFH8QAAIRAAgJbByVCACQAQARAAgJbByVCACQAQAuAAQKfyoAAhEACQmTI10BAKMDABEACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgAECgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8fAAITAAgJ9xz+FAClAgATAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIRAAQJvRyFEwAhAQARAAQJvRyFEwAhAQAuAAQKfyQAAhEACAndHpEJAN8CABEACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn9TAAIUAAkJnB5PBQCdAgAUAAkJnB5PBQCdAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAHAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgAECgUJBQAAAA==.',
Be='Bearhold:BAAALgAECgYJCQAAAA==.Beautyblood:BAAALgADCgMJAwAAAA==.Beefy:BAAALgAECgMJBAAAAA==.Beenis:BAAALgAECgQJBQAAAA==.Beersnob:BAABLgAECn8kAAIQAAkJLxZfHgAmAgAQAAkJLxZfHgAmAgAAAA==.Bellamafia:BAAALgAECgEJAQAAAA==.Benjam:BAACLgAFFH8TAAISAAcJrRZQGgDgAQASAAcJrRZQGgDgAQAuAAQKfygAAhIABwnlI0wZAL0CABIABwnlI0wZAL0CAAAA.Benyo:BAAALgAECgcJCwAAAA==.',
Bi='Bigmikeyg:BAABLgAECn9qAAIHAAkJ4RyuBACAAgAHAAkJ4RyuBACAAgAAAA==.Bigsteve:BAABLgAECn9WAAMVAAkJFCWLAAAmAwAVAAkJViKLAAAmAwATAAkJ9CR8BAAdAwAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMWAAMJJwqwCADLAAAPAAMJiQWXDwD0AAAWAAMJJwqwCADLAAAuAAQKfxYAAw8ABwlSHPUqAKUBAA8ABwkjHPUqAKUBABYAAwmaGgAAAAAAAAAA.Blinded:BAAALgAECgkJAwAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgATAAYkAA==.',
Br='Brandie:BAAALgAECgEJAgAAAA==.Brewtel:BAAALgADCgcJBwABLgAECgYJCQAIAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Brickley:BAAALgAFFAIJAgABLgAFFAYJGwANAM4eAA==.Bronzesun:BAAALgAECgUJCQAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIGAAkJMRpGGQCAAgAGAAkJMRpGGQCAAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
['Bø']='Bønd:BAAALgAECgEJAQAAAA==.',
['Bú']='Búllshifts:BAAALgAECgUJBQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQOAAkJHQX8IgBhAQAOAAkJHQX8IgBhAQAXAAMJGgjIMgCAAAAYAAMJ0AigfwBfAAAAAA==.Caicos:BAAALgAECgEJAQAAAA==.Calizon:BAAALgAECgkJEgAAAA==.Calogero:BAAALgADCgEJAQAAAA==.Camc:BAAALgAECgQJEQAAAA==.Canowhoopass:BAABLgAECn8mAAIZAAgJvApARQAfAQAZAAgJvApARQAfAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cell:BAAALgAFFAIJAwABLgAFFAYJFAAaAHAeAA==.Cerassin:BAACLgAFFH9EAAISAAcJrxtSDQDnAQASAAcJrxtSDQDnAQAuAAQKfzYAAhIACQkJIf8KAPACABIACQkJIf8KAPACAAAA.Cereas:BAABLgAECn9JAAIMAAkJFhptBAC4AQAMAAkJFhptBAC4AQAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chevota:BAEBLgAFFH8GAAIGAAMJQwfrNwBsAAAGAAMJQwfrNwBsAAABLgAFFAQJBwABAHAMAA==.Chichobelo:BAABLgAFFH8WAAQaAAkJ0hRxIQDrAQAaAAYJxxhxIQDrAQAbAAYJKA+VBQBsAQAcAAEJAABnWAAAAAAAAA==.Chigger:BAEALgAECgEJAQABLgAFFAQJGAAaAOcJAA==.Chuckrutis:BAACLgAFFH8FAAIYAAQJGw81NQDuAAAYAAQJGw81NQDuAAAuAAQKfyEAAxcACAlIHXAMABQCABcABglSHnAMABQCABgABQl4HHErAJEBAAAA.Chulk:BAAALgAECgUJBQAAAA==.',
Cl='Cliché:BAABLgAECn8tAAMdAAkJYBPfBgB0AQAdAAkJYBPfBgB0AQAHAAYJMge56wDQAAAAAA==.Cloberintime:BAABLgAECn8WAAIeAAkJnhRgAgABAgAeAAkJnhRgAgABAgAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8ZAAIfAAcJWxYZPgAxAQAfAAcJWxYZPgAxAQAuAAQKfyoAAh8ACQk6IXYCAHEDAB8ACQk6IXYCAHEDAAAA.',
Co='Combination:BAABLgAECn9VAAIgAAkJrCLzAAAFAwAgAAkJrCLzAAAFAwABLgAFFAkJLwAHANUYAA==.Constrace:BAAALgAECgYJCAAAAA==.Corvenall:BAABLgAECn86AAIXAAkJlA7VCACgAQAXAAkJlA7VCACgAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAABLgAECn8VAAITAAkJawYjTQASAQATAAkJawYjTQASAQAAAA==.Crossbow:BAACLgAFFH8KAAIfAAMJJRbFWgDvAAAfAAMJJRbFWgDvAAAuAAQKf0MAAh8ACQkoIBsPAMICAB8ACQkoIBsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAYJGwANAM4eAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJDAABLgAECgkJSQAMABYaAA==.',
['Cõ']='Cõnker:BAAALgAFFAEJAQAAAA==.',
Da='Dabbernath:BAAALgAECgEJAQAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Danglyudders:BAABLgAECn8bAAMhAAgJFxYzCQD5AAAhAAYJERgzCQD5AAAiAAUJRQ1cDQDVAAAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAKAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darshul:BAAALgAECgIJAgAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Davinah:BAAALgAECgEJAgAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.Dayje:BAAALgAECgMJBgAAAA==.',
De='Deathation:BAAALgAFFAIJAgAAAA==.Deathbcmesyu:BAACLgAFFH8GAAIaAAIJGA6WcgB0AAAaAAIJGA6WcgB0AAAuAAQKfzYAAxoACQlnIOECANkCABoACQlnIOECANkCABsAAQliDY4XACoAAAAA.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Decimus:BAAALgAECgkJCQAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgkJDAABLgAECgkJIQAjAB8hAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwAFANoNAA==.Deondre:BAAALgAECgQJCQAAAA==.Detin:BAAALgAECgEJAQAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJIQAjAB8hAA==.',
Di='Diehappy:BAABLgAECn8eAAMbAAkJ2AwdHADuAAAbAAgJ/gwdHADuAAAcAAYJRwn6PQCYAAAAAA==.Dillie:BAAALgAECgYJCgAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.Diznan:BAAALgAECgcJBwABLgAECggJFAAkADAMAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAgJHAANAOchAA==.Dompal:BAABLgAFFH8HAAIHAAMJUCLiMwDCAAAHAAMJUCLiMwDCAAABLgAFFAgJHAANAOchAA==.Donkyote:BAAALgAECgMJAwAAAA==.Donkystyle:BAAALgAECgQJCAAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJawACAM0mAA==.Drovinos:BAAALgAECgYJBgAAAA==.Drualia:BAAALgAECgIJAgAAAA==.Druken:BAABLgAECn8XAAIfAAgJEgoLFwApAQAfAAgJEgoLFwApAQAAAA==.Drybonez:BAABLgAECn8UAAICAAYJ0Aha+AAKAQACAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8XAAMfAAgJSx8eKwBdAQAfAAcJXx4eKwBdAQAlAAIJSR/hKABnAAAuAAQKfyMAAyUACQm3JNIJAAYDACUACAmdItIJAAYDAB8AAwlvIxyeAAUBAAAA.Drywar:BAAALgADCgkJCwAAAA==.Dràgonkíng:BAABLgAECn8gAAMmAAkJFQd8CAAIAQAmAAkJFQd8CAAIAQACAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAITAAkJWRwCFABRAgATAAkJWRwCFABRAgABLgAFFAcJIgAaAEQZAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIFAAgJ2g1qMQBWAQAFAAgJ2g1qMQBWAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgcJCwAAAA==.',
['Dà']='Dànger:BAAALgADCgEJAQAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAXAKYfAA==.',
Ef='Efran:BAAALgAECgEJAQAAAA==.',
Eg='Ego:BAABLgAECn83AAITAAkJMiSlBwDkAgATAAkJMiSlBwDkAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elijahtheone:BAAALgAECgMJAwAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFwACAHciAA==.Emmone:BAAALgAECgYJEQAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.Emorexx:BAAALgAECgYJCwAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAnAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAACLgAFFH8FAAIgAAIJ7QrVCgB8AAAgAAIJ7QrVCgB8AAAuAAQKfyAAAiAABwmRGOQCAIEBACAABwmRGOQCAIEBAAAA.Excaleon:BAAALgAECgYJCwAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Falcon:BAAALgADCgUJBQAAAA==.Farglight:BAAALgAFFAIJAgAAAA==.Faunna:BAACLgAFFH8dAAIJAAUJOBRLEwDzAAAJAAUJOBRLEwDzAAAuAAQKfz8AAgkACQmeIJwHAN0CAAkACQmeIJwHAN0CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgUJBwAAAA==.Felaz:BAABLgAECn82AAIDAAkJJCADAQDFAgADAAkJJCADAQDFAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAABLgAECn8gAAICAAkJ6xOjCADuAQACAAkJ6xOjCADuAQAAAA==.Ferreil:BAAALgAECgEJAwAAAA==.Festy:BAAALgAECgIJAgAAAA==.',
Fi='Fingerguns:BAACLgAFFH8SAAIkAAQJaQj9GADAAAAkAAQJaQj9GADAAAAuAAQKfx0ABCQACQndFSsTAEgCACQACQndFSsTAEgCAAQAAwl3CO5mAJEAAAUAAwkJCChzAFsAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAUPgAA5AQABAAkJDQUPgAA5AQAgAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBwAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgAECgcJCwAAAA==.Floortank:BAABLgAECn83AAMbAAkJ4w7REQBbAQAbAAkJ4w7REQBbAQAaAAgJAQYgpQAkAQAAAA==.',
Fo='Fonn:BAAALgAECgYJBwAAAA==.Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freamh:BAAALgADCgYJBgAAAA==.Freeteddyp:BAACLgAFFH8LAAIdAAMJUBsJKwDSAAAdAAMJUBsJKwDSAAAuAAQKfxsAAh0ABwnKI4sRAIcCAB0ABwnKI4sRAIcCAAAA.Friday:BAAALgAECgQJBgAAAA==.Frikilatar:BAAALgAECgEJDAAAAA==.Frostyhatesu:BAAALgADCgMJAwABLgAECgIJAwAIAAAAAA==.Frrank:BAACLgAFFH8cAAIVAAgJXCEHBwDuAQAVAAgJXCEHBwDuAQAuAAQKfzQAAhUACQkoJWEAALQDABUACQkoJWEAALQDAAAA.Frugalgunny:BAAALgADCgUJBQAAAA==.',
Fu='Fullerene:BAAALgAECgQJCQAAAA==.Funnelcake:BAAALgAECgYJBgAAAA==.',
Ga='Galcain:BAACLgAFFH8VAAQfAAYJdhynIgB6AQAfAAUJfiCnIgB6AQAKAAQJSRBUEQCSAAAlAAIJlAfLEQB0AAAuAAQKfzEABB8ACQlWI/YHABEDAB8ACQkaI/YHABEDAAoACAl9FogYANwBACUAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAYJFQAfAHYcAA==.Ganondorff:BAAALgAECgMJAwAAAA==.Gantz:BAABLgAECn8XAAIHAAkJ2w2pDgB+AQAHAAkJ2w2pDgB+AQAAAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAIAAAAAA==.',
Gi='Gibbie:BAAALgAECgkJCAAAAA==.Gintoko:BAAALgAECgMJBgAAAA==.Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAACLgAFFH8FAAICAAMJJApVRAC4AAACAAMJJApVRAC4AAAuAAQKfy4AAgIACQkGF8BCABMCAAIACQkGF8BCABMCAAAA.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Greybull:BAAALgAECggJCQAAAA==.Griffy:BAAALgAECgQJBAAAAA==.Grimseek:BAACLgAFFH8HAAIlAAQJ9hg9FAAnAQAlAAQJ9hg9FAAnAQAuAAQKfzQAAiUACQnKIzkAAE4DACUACQnKIzkAAE4DAAEuAAUUCQkvAAcA1RgA.Gripmepapi:BAABLgAFFH8jAAIaAAQJlh3RHgBuAQAaAAQJlh3RHgBuAQAAAA==.Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgAECgEJAQAAAA==.Grumandel:BAABLgAECn9TAAIjAAkJaiA1BQChAgAjAAkJaiA1BQChAgAAAA==.',
Gu='Guce:BAAALgAECgcJDgAAAA==.Gudetama:BAABLgAECn8bAAMfAAkJsCDBFwB7AgAfAAYJESPBFwB7AgAKAAcJwx16DwA3AgAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gungnir:BAAALgAECgMJAwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgAECgQJBAAAAA==.Haitwahan:BAAALgAECgEJAQAAAA==.Hakur:BAABLgAECn88AAIHAAkJQhyCMAA/AgAHAAkJQhyCMAA/AgAAAA==.Halfpink:BAAALgAECgEJAQABLgAECgkJIgAiAD0gAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hammertóe:BAAALgAECgIJBAAAAA==.Hanabi:BAAALgAECgYJBgAAAA==.Hanma:BAACLgAFFH8ZAAIaAAkJkBz5IADuAQAaAAkJkBz5IADuAQAuAAQKfygAAhoACQkFHxEsAIgCABoACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn9MAAICAAkJ5hFVEQBXAQACAAkJ5hFVEQBXAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgAECgQJBAAAAA==.Hiroki:BAABLgAECn8zAAIaAAkJdw+nUADRAQAaAAkJdw+nUADRAQAAAA==.Hitachitotem:BAACLgAFFH8vAAIZAAQJ0R6oDgBPAQAZAAQJ0R6oDgBPAQAuAAQKfxkAAhkACAmtGl0aAEACABkACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJDwAAAA==.Hiyodad:BAAALgADCgUJBQAAAA==.Hiyodadk:BAAALgAECgIJAgAAAA==.Hiyodal:BAAALgAECgQJBAAAAA==.Hiyodam:BAAALgADCgIJAgAAAA==.Hiyodat:BAAALgAECgYJCgAAAA==.Hiyodaw:BAABLgAECn8UAAIgAAUJLQbJJgB/AAAgAAUJLQbJJgB/AAAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Hollycat:BAAALgAECgkJAwAAAA==.Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAISAAkJ2hquHwBXAgASAAkJ2hquHwBXAgABLgAFFAEJAQAIAAAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAcJIwATAGwhAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQAEACsgAA==.Holyshifts:BAABLgAECn8tAAIHAAkJARyOBACGAgAHAAkJARyOBACGAgAAAA==.',
Hu='Huntmcpink:BAAALgAECgEJAQABLgAECgkJIgAiAD0gAA==.Huxter:BAAALgADCgEJAQAAAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAACLgAFFH8FAAICAAMJuAc4RgCyAAACAAMJuAc4RgCyAAAuAAQKfyUAAgIACQnGFMdDABACAAIACQnGFMdDABACAAAA.',
In='Inflikted:BAABLgAECn8lAAIaAAkJVQgQeQBxAQAaAAkJVQgQeQBxAQAAAA==.Interwebz:BAABLgAECn8eAAMaAAkJHh3pIgB7AgAaAAkJKxzpIgB7AgAcAAIJ9h1LPgCXAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Iz='Izztargaryen:BAAALgADCgEJAQAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgYJCQAIAAAAAA==.Jakarm:BAAALgAECgEJAQAAAA==.Jankook:BAAALgAECgEJAQAAAA==.Jazzarin:BAAALgAECgYJDAAAAA==.',
Je='Jehannum:BAABLgAECn9HAAIZAAkJ4RdcAwAgAgAZAAkJ4RdcAwAgAgAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgYJEQAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8JAAIdAAQJfxocIAAcAQAdAAQJfxocIAAcAQABLgAFFAUJLwAGAO4lAA==.Joroby:BAAALgAECgEJAQAAAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgAECgcJCwAAAA==.Jurkzarbirt:BAAALgAECgQJBQAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jì']='Jìnbe:BAABLgAECn8zAAInAAkJixKOAgC0AQAnAAkJixKOAgC0AQABLgAECgkJUwAUAJweAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIFAAgJ0hekJQCeAQAFAAgJ0hekJQCeAQAAAA==.',
Ka='Kaefaith:BAAALgAECgMJAwAAAA==.Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kaimi:BAAALgAECgkJDgAAAA==.Kainiy:BAAALgAECgUJEQAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAABLgAECn8YAAIHAAcJUgw2HAD9AAAHAAcJUgw2HAD9AAAAAA==.Kaoti:BAAALgAECgUJBgAAAA==.Kassan:BAABLgAECn80AAQkAAkJSw4bBwCLAQAkAAgJNg4bBwCLAQAFAAcJMxWsBgB1AQAEAAkJHwrzBwBIAQAAAA==.Katarena:BAABLgAECn83AAIdAAgJVRAGMgCOAQAdAAgJVRAGMgCOAQAAAA==.Kathyra:BAECLgAFFH8HAAIBAAQJcAzyfADKAAABAAQJcAzyfADKAAAuAAQKfy0AAwEACQkgFMQOABcBAAEACQkgFMQOABcBACgAAQnvASM3ACcAAAAA.Kavax:BAABLgAECn8mAAIdAAkJhBSNGQA6AgAdAAkJhBSNGQA6AgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIHAAYJlw9ZLQBaAQAHAAYJlw9ZLQBaAQAuAAQKfzwAAgcACQnFHiwiAH0CAAcACQnFHiwiAH0CAAAA.Keellie:BAAALgAECgEJAQAAAA==.Kegbash:BAAALgAECgEJAQABLgAECgkJMAAMABceAA==.Keggor:BAAALgAECgEJAgAAAA==.Kelorth:BAAALgADCggJCAAAAA==.Kentyr:BAABLgAECn83AAMPAAgJ8xFLHACzAQAPAAgJ8xFLHACzAQApAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khaldormu:BAAALgAECggJBwAAAA==.Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAcJIwATAGwhAA==.Kinký:BAACLgAFFH8PAAITAAQJSg2dFQDwAAATAAQJSg2dFQDwAAAuAAQKfy8AAxMACQk0FlcYACsCABMACQk0FlcYACsCABUAAQnbFDd1ADcAAAEuAAQKCAkUABMAChcA.Kiraelis:BAABLgAECn8lAAIlAAkJqg8WDQCPAQAlAAkJqg8WDQCPAQAAAA==.Kisara:BAAALgADCggJDAABLgAFFAMJBQAHAOsNAA==.Kiss:BAAALgADCgEJAQABLgAECgUJBQAIAAAAAA==.Kitchner:BAAALgAECgYJDwAAAA==.Kitetsu:BAAALgAECgEJAQAAAA==.Kivea:BAABLgAECn8aAAMCAAkJZg9LZAC1AQACAAkJZg9LZAC1AQAmAAEJBAe/FQAoAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgAECgMJAwAAAA==.Konvik:BAAALgAECgYJCwAAAA==.Kooka:BAAALgADCgMJAwAAAA==.Korvoh:BAABLgAECn9RAAMkAAkJLh+nAQDEAgAkAAkJLh+nAQDEAgAEAAMJUxeOXQC8AAAAAA==.',
Kr='Krincess:BAABLgAECn8sAAIYAAkJaRqCAQBYAgAYAAkJaRqCAQBYAgABLgAECgkJNgAZAAAkAA==.Kringe:BAABLgAECn82AAMZAAkJACRvBAAcAwAZAAkJACRvBAAcAwAGAAEJLQQO6QAlAAAAAA==.Krinmate:BAAALgAECgUJBQAAAA==.Krinny:BAAALgAECgUJBQABLgAECgkJNgAZAAAkAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumaro:BAAALgAECgMJAwAAAA==.Kumonk:BAABLgAECn8cAAIRAAcJWAbMSwDTAAARAAcJWAbMSwDTAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBgAAAA==.',
['Kä']='Kämik:BAABLgAECn9NAAIfAAkJrCG3CgAAAwAfAAkJrCG3CgAAAwAAAA==.',
['Kì']='Kìn:BAABLgAECn8rAAMkAAcJbgzDPQAWAQAkAAYJPQ7DPQAWAQAFAAYJfASgdABYAAAAAA==.',
La='Lampion:BAABLgAECn8hAAIMAAkJdAzxIABxAQAMAAkJdAzxIABxAQAAAA==.Langris:BAAALgAECgEJAwAAAA==.Lasstchance:BAABLgAECn8fAAIfAAkJDwyyewBIAQAfAAkJDwyyewBIAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8pAAIBAAkJ/h41DwDTAgABAAkJ/h41DwDTAgAAAA==.',
Le='Leijona:BAABLgAECn8WAAIdAAcJbw8xCABNAQAdAAcJbw8xCABNAQAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgAECgcJCwAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Lightbunny:BAAALgAECgMJAwAAAA==.Lightstorms:BAAALgAECggJEQAAAA==.Likeatrain:BAABLgAECn88AAIeAAkJ0RZxDQAUAgAeAAkJ0RZxDQAUAgAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMdAAgJJRN/KADqAQAdAAgJJRN/KADqAQAHAAUJDgjKDQGoAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMdAAkJOh5bFgBYAgAdAAkJOh5bFgBYAgAHAAYJTQzJ6ADTAAAAAA==.Lintha:BAAALgAECggJEwAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littleangel:BAAALgADCgMJAwAAAA==.Littlefoot:BAABLgAECn8UAAMYAAYJKhWDOwA9AQAYAAYJKhWDOwA9AQAXAAEJ3wOVKgAkAAABLgAFFAcJIwATAGwhAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8dAAMPAAgJlBc8GwC9AQAPAAgJlBc8GwC9AQAWAAEJhxD2HwAzAAAAAA==.Lokininja:BAABLgAECn8aAAMRAAYJowtqDQCtAAARAAUJLA5qDQCtAAAnAAYJMQOtCgCDAAAAAA==.Looker:BAAALgADCgQJBAAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn9XAAIRAAkJkySaAAAyAwARAAkJkySaAAAyAwAAAA==.',
Lu='Luber:BAECLgAFFH8SAAMGAAQJcQ/pIgDEAAAGAAQJcQ/pIgDEAAAZAAIJGgIAMwBGAAAuAAQKf0UAAwYACQlIGuUCAKACAAYACQlIGuUCAKACABkABgkLDfpVAOMAAAEuAAUUBAkYABoA5wkA.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAACLgAFFH8UAAIcAAYJMiJeBgDZAQAcAAYJMiJeBgDZAQAuAAQKf1UAAhwACQkwJrQAAGkDABwACQkwJrQAAGkDAAAA.Luxzy:BAACLgAFFH8LAAMfAAMJjg/0NADUAAAfAAMJjg/0NADUAAAlAAEJagGWPAAuAAAuAAQKfzcAAx8ACQkvGCAGAEQCAB8ACQkvGCAGAEQCACUACAnRBxEVABMBAAAA.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Makarich:BAAALgAECgEJAQABLgAFFAEJAQAIAAAAAA==.Malachron:BAAALgAECgEJAQAAAA==.Manbearcat:BAABLgAECn8iAAIiAAkJPSBwCgAWAwAiAAkJPSBwCgAWAwAAAA==.Marbleous:BAACLgAFFH8KAAITAAMJBiQ8KwAHAQATAAMJBiQ8KwAHAQAuAAQKfxgAAhMABgm6Iz8oALoBABMABgm6Iz8oALoBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcdragon:BAAALgAECgUJBgAAAA==.Mcewan:BAAALgADCgUJBQAAAA==.Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIgAiAD0gAA==.Mcspicy:BAAALgAECgUJCAAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAoAFkfAA==.Mechalomania:BAAALgAECgkJCQABLgAECgkJOgAJAKAQAA==.Melhina:BAAALgAECgUJCQABLgAECgkJQQAoAOkcAA==.Memisstotem:BAABLgAECn8eAAIGAAcJgRrRMgDoAQAGAAcJgRrRMgDoAQAAAA==.Merle:BAACLgAFFH8jAAMTAAcJbCEqBQD/AQATAAcJYB0qBQD/AQAVAAQJFhciCQAzAQAuAAQKf1UAAxMACQloJcYCAEUDABMACQk0JMYCAEUDABUABgncJIUOAAMCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8dAAISAAgJ7Rn7KQAhAgASAAgJ7Rn7KQAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Mikethegray:BAABLgAECn8fAAIZAAkJNRDrBQCbAQAZAAkJNRDrBQCbAQABLgAECgkJagAHAOEcAA==.Minaxy:BAAALgAECgcJBwAAAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8eAAIEAAcJmA2DNQAtAQAEAAcJmA2DNQAtAQAAAA==.Mistborn:BAABLgAECn84AAQEAAkJiCIhCQC5AgAEAAkJiCIhCQC5AgAkAAQJ1RyJKQBMAQAFAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAXAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn9AAAIjAAkJ4SHxAgDvAgAjAAkJ4SHxAgDvAgAAAA==.Monkjamin:BAABLgAFFH8GAAInAAMJThcKNgDOAAAnAAMJThcKNgDOAAAAAA==.Moolimbo:BAABLgAECn8qAAIZAAkJghi7FgAwAgAZAAkJghi7FgAwAgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAXAKYfAA==.Mooseboy:BAABLgAECn8tAAIjAAkJah70BACpAgAjAAkJah70BACpAgAAAA==.Mooserton:BAACLgAFFH8FAAIdAAMJeBAeMQCvAAAdAAMJeBAeMQCvAAAuAAQKfzYAAx0ACQmaHEoIAAcDAB0ACQmaHEoIAAcDAAcABgmsD8/cAOIAAAAA.Mootalstrike:BAABLgAECn8zAAITAAkJbhVUHwD0AQATAAkJbhVUHwD0AQAAAA==.Moshworm:BAABLgAECn86AAIJAAkJoBD3IgCyAQAJAAkJoBD3IgCyAQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAcJIgAaAEQZAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgIJAwAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAcJGQAfAFsWAA==.Myraxes:BAAALgADCgIJAgAAAA==.',
['Mä']='Mängo:BAAALgAECgUJAwAAAA==.',
Na='Nadlus:BAAALgADCgEJAQAAAA==.Nalaxx:BAAALgAECgkJAQAAAA==.Natsumi:BAABLgAECn8WAAIGAAcJxgvbZgAnAQAGAAcJxgvbZgAnAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIYAAYJVQPRQwDRAAAYAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAICAAkJBh4LIwCRAgACAAkJBh4LIwCRAgAAAA==.Neuroticaine:BAABLgAECn9aAAMFAAkJMxwkAwANAgAFAAkJMxwkAwANAgAkAAQJVQ4JSwDYAAAAAA==.Nev:BAACLgAFFH8SAAMfAAQJsCGMMABOAQAfAAQJsCGMMABOAQAlAAMJ6AVCGQDAAAAuAAQKfyEAAx8ACAncIsYjAC8CAB8ABwkjIsYjAC8CACUABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8UAAIPAAQJfg1dIAAiAQAPAAQJfg1dIAAiAQAAAA==.',
Ni='Nico:BAABLgAECn8bAAIKAAkJChIjEQCxAQAKAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQoAAkJWR+gBABRAgAoAAkJUx+gBABRAgAgAAcJIBqjCgCZAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgAECgcJCwAAAA==.Nooblets:BAACLgAFFH8HAAIPAAMJ/xoZKQDiAAAPAAMJ/xoZKQDiAAAuAAQKfxsAAg8ABwnMIGMbALwBAA8ABwnMIGMbALwBAAAA.Nop:BAAALgAECgEJAQAAAA==.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMSAAkJQBLCVACIAQASAAkJQBLCVACIAQANAAIJwhRuMgA6AAAAAA==.Noxxus:BAABLgAECn8fAAIUAAkJvRqdDAD9AQAUAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAoAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAAALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAECLgAFFH8YAAIaAAQJ5wmIPADpAAAaAAQJ5wmIPADpAAAuAAQKfycAAxoACQmEDqVnAJcBABoACQmEDqVnAJcBABwABwlTBkkMAK4AAAAA.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAZAIIYAA==.',
Om='Omnivus:BAAALgAECgMJBgAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgQJCQAIAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAdAFAbAA==.Oratherah:BAABLgAFFH8NAAIcAAQJphq0JgC+AAAcAAQJphq0JgC+AAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8rAAITAAkJfCILBwDtAgATAAkJfCILBwDtAgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAABLgAECn8YAAIMAAgJLxY7FgDYAQAMAAgJLxY7FgDYAQAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn9VAAIbAAkJoQw+BABLAQAbAAkJoQw+BABLAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAZAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHgAaAB4dAA==.Pinkrosé:BAAALgAECgcJBwAAAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIgAiAD0gAA==.Pitchblende:BAABLgAECn8xAAIdAAkJMBKAHwAHAgAdAAkJMBKAHwAHAgAAAA==.Pixies:BAAALgADCgIJAgAAAA==.',
Po='Poepsul:BAAALgAECgEJAQAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Polyrock:BAAALgADCgQJBAAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAaAOEkAA==.Porthub:BAABLgAECn8pAAICAAkJLAkneACJAQACAAkJLAkneACJAQAAAA==.',
Pr='Prangkim:BAAALgAECgkJBwAAAA==.Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAABLgAECn8YAAMfAAgJKRJBbABpAQAfAAgJKRJBbABpAQAlAAEJAAB3SQAAAAAAAA==.Rajak:BAAALgAECggJDQAAAA==.Range:BAAALgAFFAIJAgAAAA==.Raph:BAABLgAECn8XAAIiAAYJAxpwNADKAQAiAAYJAxpwNADKAQAAAA==.Rathibrew:BAACLgAFFH8cAAInAAgJDhx4DADOAQAnAAgJDhx4DADOAQAuAAQKfzgAAicACQmcJLwBAIwDACcACQmcJLwBAIwDAAAA.Rathidk:BAAALgADCgIJAgAAAA==.',
Re='Reckurface:BAAALgAECgIJBAAAAA==.Redine:BAAALgAECgUJBgAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgcJCgAAAA==.Rellt:BAAALgAECgIJAwAAAA==.Remnants:BAABLgAECn8UAAInAAYJihvDJwDIAQAnAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8YAAQEAAgJRQe3OQASAQAEAAgJRQe3OQASAQAFAAUJEAOrbQBpAAAkAAEJ4gHeigAcAAAAAA==.',
Rh='Rhayge:BAABLgAECn8jAAILAAkJfx6hAADEAgALAAkJfx6hAADEAgAAAA==.Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgUJCQAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAIAAAAAA==.Rompally:BAAALgAECgYJCQAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8iAAQaAAcJRBn9EADwAQAaAAcJRBn9EADwAQAbAAEJUQ3YJwBGAAAcAAEJAAA8WAAAAAAuAAQKfzEAAhoACQnGHywrAFMCABoACQnGHywrAFMCAAAA.',
['Rê']='Rêvolt:BAABLgAFFH8IAAISAAIJYg4LggB7AAASAAIJYg4LggB7AAAAAA==.Rêzìcå:BAAALgADCgkJCQAAAA==.',
['Rô']='Rôwdy:BAAALgAECgEJAQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAABLgAECn8ZAAMfAAgJ0getfABGAQAfAAgJ0getfABGAQAlAAQJWwF4PAAyAAAAAA==.Sahki:BAAALgAECgkJCAAAAA==.Salezar:BAABLgAECn8rAAIXAAkJph9jAQDnAgAXAAkJph9jAQDnAgAAAA==.Sandoud:BAABLgAECn8cAAIJAAkJ6xNFGgD5AQAJAAkJ6xNFGgD5AQAAAA==.Sannish:BAAALgAECgYJCwAAAA==.Sapientia:BAABLgAECn8tAAIHAAkJqwgTjABZAQAHAAkJqwgTjABZAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECgkJSQAMABYaAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgAECgEJAgAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIdAAQJcw/iKADdAAAdAAQJcw/iKADdAAAuAAQKfyEAAx0ACAlaGMcZAEUCAB0ACAlaGMcZAEUCAAcAAQnyDycyAT8AAAEuAAUUCQkkAAIAthkA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAMJBAAAAA==.Selenesul:BAABLgAECn8sAAMHAAkJ9RxlHwCLAgAHAAkJ9RxlHwCLAgAUAAMJTAynNAB0AAAAAA==.Selyda:BAAALgAECgEJAQAAAA==.Senzie:BAACLgAFFH8dAAIRAAYJex4vBQBnAQARAAYJex4vBQBnAQAuAAQKfyUAAhEACQkiHlYNAHACABEACQkiHlYNAHACAAEuAAUUCAkVABEAXRAA.Sevro:BAAALgADCgQJBAABLgAECgkJJgAdAIQUAA==.',
Sh='Shadowdrake:BAABLgAECn8hAAIYAAkJ+wswMQByAQAYAAkJ+wswMQByAQAAAA==.Shadowheàrt:BAABLgAECn8nAAMdAAgJ6hV1BgCBAQAdAAcJchV1BgCBAQAHAAQJOQU8OAF1AAAAAA==.Shadowshifty:BAABLgAECn8nAAIhAAkJLRDTBgA2AQAhAAkJLRDTBgA2AQAAAA==.Shadowtotem:BAAALgAECgYJBgAAAA==.Shaeen:BAABLgAFFH8JAAINAAMJpRD7CQCxAAANAAMJpRD7CQCxAAAAAA==.Shagi:BAABLgAECn8qAAInAAkJJxanFwDrAQAnAAkJJxanFwDrAQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Shanson:BAAALgAECgQJBAAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharklee:BAAALgADCgEJAgAAAA==.Sharroz:BAABLgAECn8dAAMbAAcJiB1oAwBWAgAbAAcJiB1oAwBWAgAcAAQJVQ7wQQCHAAAAAA==.Shauna:BAACLgAFFH8PAAIfAAcJGBVLDQDaAQAfAAcJGBVLDQDaAQAuAAQKfxUAAh8ACAn6DqhOALYBAB8ACAn6DqhOALYBAAAA.Shdw:BAAALgAECgUJCQAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMkAAgJeBpPFwAcAgAkAAgJeBpPFwAcAgAFAAEJJQKaaQAlAAABLgAFFAcJIgAaAEQZAA==.Shockybalboa:BAABLgAECn8UAAIZAAcJNBP/NQBiAQAZAAcJNBP/NQBiAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBwAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skoftyia:BAAALgAECgEJAQABLgAFFAMJCgATAIIVAA==.Skooda:BAABLgAECn8tAAIZAAkJaA5AMAB+AQAZAAkJaA5AMAB+AQAAAA==.Skyded:BAABLgAECn8yAAIaAAkJLBn3MAA7AgAaAAkJLBn3MAA7AgAAAA==.Skyfire:BAAALgAECgcJAQAAAA==.Skyknight:BAABLgAECn8iAAITAAkJ/RN0KQCzAQATAAkJ/RN0KQCzAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8SAAMKAAcJxhBEFAAqAQAKAAcJxhBEFAAqAQAlAAIJBwsJJwB0AAAuAAQKfzsAAwoACQlyI3kEAOYCAAoACQlQInkEAOYCACUACAnWHuoSAJ8CAAAA.Slaughterman:BAAALgAECgMJBwAAAA==.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgAECgEJAQAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8vAAISAAkJdR5OAwA8AgASAAkJdR5OAwA8AgAAAA==.Solence:BAAALgADCgIJAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAABLgAECn8eAAIHAAgJWx46IwB4AgAHAAgJWx46IwB4AgAAAA==.Soralas:BAAALgAECgcJEgAAAA==.',
Sp='Spaazz:BAABLgAECn8nAAIHAAkJsyGAFADHAgAHAAkJsyGAFADHAgAAAA==.Spanky:BAAALgAECgMJAwAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
Sq='Squeakbolt:BAAALgADCgYJBgAAAA==.',
St='Staggerstout:BAAALgAECgEJAQAAAA==.Starofdreams:BAAALgAECgQJCAABLgAFFAMJBgAEAEsPAA==.Starweaver:BAACLgAFFH8GAAMEAAMJSw9ZEACqAAAEAAMJcg5ZEACqAAAkAAEJDAWdNgApAAAuAAQKfzIAAwQACQmmFTEKAAsBACQACQlZCrIpAIcBAAQACAk3FzEKAAsBAAAA.Stellmarine:BAABLgAECn8dAAIJAAkJzRoSGwDyAQAJAAkJzRoSGwDyAQAAAA==.Stelthest:BAAALgAECgQJBAAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAABLgAECn8bAAISAAgJqg+UCgBSAQASAAgJqg+UCgBSAQAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMhAAkJIhu3CABhAgAhAAkJ4Rq3CABhAgAJAAYJBBrnKgCqAQAAAA==.',
Su='Sunamé:BAAALgAECgUJCwAAAA==.Sunarianna:BAAALgAECgUJBgAAAA==.',
Sw='Swaazil:BAACLgAFFH8YAAICAAQJcwgRPQDSAAACAAQJcwgRPQDSAAAuAAQKfyYAAgIACQkrEaBeAMMBAAIACQkrEaBeAMMBAAAA.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgQJBgAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAIAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8fAAISAAcJIQ1RiAAPAQASAAcJIQ1RiAAPAQAAAA==.Sylas:BAAALgADCggJCAAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taken:BAAALgAECgYJBgAAAA==.Taloriesh:BAACLgAFFH8HAAIEAAMJ3x66GAD2AAAEAAMJ3x66GAD2AAAuAAQKfysABAQACQmlHmwIAOQCAAQACQmlHmwIAOQCAAUAAQk+FepgADYAACQAAQkdDlJ8AC8AAAAA.Tanazir:BAEBLgAECn8eAAMXAAkJpRCeCQCMAQAXAAgJKhGeCQCMAQAYAAIJ5g8aEgBpAAAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarivel:BAAALgAECgIJAgAAAA==.Tarok:BAAALgAECgYJEgAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8ZAAIRAAgJKRA2KwBkAQARAAgJKRA2KwBkAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIgAAgJnBwLBQAlAgAgAAgJnBwLBQAlAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECgkJHgAXAKUQAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIHAAkJLBlZRQATAgAHAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8XAAIfAAcJKQapmQANAQAfAAcJKQapmQANAQAAAA==.Tilamano:BAACLgAFFH8GAAIBAAIJ1iOGdwDTAAABAAIJ1iOGdwDTAAAuAAQKfzsABCAACQmlJfgBAK4CACAACAnSJPgBAK4CACgACAk6JPgCAJMCAAEACAkyJEMmAEQCAAAA.Tilthulhu:BAAALgAECgMJAwABLgAFFAIJBgABANYjAA==.',
Tl='Tlital:BAAALgAECgEJAQAAAA==.',
Tm='Tmntmikey:BAABLgAFFH8WAAQQAAYJhxNOIABsAQAQAAYJhxNOIABsAQAnAAMJbgHpRACOAAARAAEJvAfsRgAzAAAAAA==.',
To='Tobirama:BAAALgAFFAIJAgAAAA==.Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMfAAcJRCMZHwBLAgAfAAcJgCIZHwBLAgAlAAYJMSMUIgAVAgABLgAFFAEJAQAIAAAAAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAnAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAnAO8lAA==.Toomey:BAAALgAECgEJAQAAAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAnAO8lAA==.Toopie:BAACLgAFFH8FAAInAAEJ7yUyTwBlAAAnAAEJ7yUyTwBlAAAuAAQKfx4AAycACAn7IWULANcCACcACAn7IWULANcCABEABQlvGSQ4AD0BAAAA.Totemwebz:BAAALgAECgUJBQAAAA==.Totoku:BAABLgAECn8eAAIGAAkJ0RWLBABFAgAGAAkJ0RWLBABFAgAAAA==.',
Tr='Trackdown:BAAALgAECgcJBwAAAA==.Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8qAAIiAAkJxBsvEgC8AgAiAAkJxBsvEgC8AgAAAA==.Tryath:BAABLgAECn8ZAAMiAAgJ4wqVcwDaAAAiAAcJcAiVcwDaAAAJAAQJzAmvZwCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
Ty='Tyrethia:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIgAAUJAhUcBwAlAQAgAAUJAhUcBwAlAQAuAAQKfyQAAiAACQl8G2oCAOUCACAACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIKAAkJCh8hAwABAwAKAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8uAAISAAkJQiBfEwDlAgASAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgkJKwACAFsZAA==.',
Us='Useche:BAAALgADCgYJCwAAAA==.',
Va='Vader:BAAALgAFFAIJAgAAAA==.Valcristo:BAABLgAECn8/AAIUAAkJoiMnAgAYAwAUAAkJoiMnAgAYAwAAAA==.Valros:BAAALgADCgEJAQABLgAECgkJKgAnACcWAA==.Vanaras:BAAALgAECgIJAgAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgUJDwABLgAFFAIJBgAaABgOAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMPAAkJnxYOFQD4AQAPAAkJshUOFQD4AQAWAAUJ8xGAEwDJAAAAAA==.Veraana:BAABLgAECn8nAAIdAAkJIhngAQCAAgAdAAkJIhngAQCAAgAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestre:BAAALgAECgQJBQAAAA==.Vestt:BAABLgAECn9lAAIfAAkJXR46BACVAgAfAAkJXR46BACVAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8iAAQkAAgJfyJJDABZAgAkAAgJfyJJDABZAgAFAAEJphQvOQBIAAAEAAEJuweIJAAiAAAuAAQKfywAAyQACQnfJhEAAPkDACQACQnfJhEAAPkDAAUAAQnWIX5xAF8AAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJBAAAAA==.Victorfang:BAAALgADCgIJAgAAAA==.Vidette:BAAALgAECgEJAQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAoAFkfAA==.Vinewhip:BAAALgADCgQJBAAAAA==.Viv:BAABLgAECn8qAAMUAAkJLiK8BQCWAgAUAAcJPCS8BQCWAgAHAAcJCSJWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8gAAIHAAkJjAallQBJAQAHAAkJjAallQBJAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAABLgAECn8YAAQaAAkJsgmGpQAjAQAaAAgJ4waGpQAjAQAcAAQJwwqOFwBEAAAbAAEJXQ+dFQA4AAAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAACLgAFFH8GAAISAAUJ2Q90IwD8AAASAAUJ2Q90IwD8AAAuAAQKfxkAAhIABgntE4iQAP8AABIABgntE4iQAP8AAAAA.Warrendemon:BAACLgAFFH8aAAISAAgJCyMEFgABAgASAAgJCyMEFgABAgAuAAQKfzUAAxIACQkDJrsBAMADABIACQkDJrsBAMADAAwAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgkJFwAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAICAAkJWBOvUgA/AgACAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8hAAMjAAkJHyHIBACuAgAjAAkJ1SDIBACuAgAhAAMJ+xQkPgCuAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Woregontail:BAAALgAECgEJAQAAAA==.Wowbelly:BAACLgAFFH8IAAIQAAQJggxzNgDPAAAQAAQJggxzNgDPAAAuAAQKfykAAhAABwkbH70FAO0BABAABwkbH70FAO0BAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAAQAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAABLgAECn8XAAMHAAcJsg6EsgAbAQAHAAcJpAuEsgAbAQAUAAYJlA6bKADSAAAAAA==.',
Xe='Xenocrates:BAAALgADCgYJBgAAAA==.',
Xo='Xonk:BAACLgAFFH8fAAIoAAgJuxDRAgB1AQAoAAgJuxDRAgB1AQAuAAQKfyQAAigACQkQICwBAPECACgACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Xy='Xylà:BAAALgADCgEJAQAAAA==.',
Ya='Yackson:BAAALgADCgEJAQAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAFFAIJBgAaABgOAA==.',
Yo='Yoru:BAAALgADCgQJBAAAAA==.Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEwAAAA==.',
Yu='Yuuna:BAABLgAECn8mAAIBAAcJrQYaGgCmAAABAAcJrQYaGgCmAAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8hAAMMAAkJbBiYAgA8AgAMAAkJbBiYAgA8AgASAAYJ+QID3wB5AAAAAA==.Zapp:BAABLgAECn8kAAIWAAkJixXOAAAaAgAWAAkJixXOAAAaAgAAAA==.Zaps:BAABLgAECn8pAAILAAkJKCMpAgADAwALAAkJKCMpAgADAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8mAAICAAkJZRRICQDbAQACAAkJZRRICQDbAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMGAAkJ4QstTgB4AQAGAAkJ4QstTgB4AQAZAAcJxwg5VQDlAAAAAA==.Zenreto:BAABLgAECn9JAAIWAAkJ1yCEAAB/AgAWAAkJ1yCEAAB/AgAAAA==.Zerani:BAAALgAECgMJBgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.Zergonia:BAAALgADCgYJCQAAAA==.',
Zh='Zhenbao:BAAALgAECgIJAgAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.Zurid:BAAALgAECgYJBgAAAA==.',
Zy='Zyria:BAACLgAFFH8aAAICAAgJjxodLwCwAQACAAgJjxodLwCwAQAuAAQKfywAAgIACQlRJG0SADkDAAIACQlRJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8lAAILAAgJ7xtEAQAUAgALAAgJ7xtEAQAUAgAuAAQKf0oAAgsACQmQJhYAAIEDAAsACQmQJhYAAIEDAAAA.',
['Ät']='Äthena:BAABLgAECn8WAAIgAAYJMgceJgCEAAAgAAYJMgceJgCEAAAAAA==.',
['Ån']='Ånmoa:BAAALgAECgUJBQABLgAFFAgJJQALAO8bAA==.',
['Ër']='Ëroc:BAAALgADCgEJAQAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8zAAMBAAkJuR3tGgCCAgABAAkJuR3tGgCCAgAgAAQJGwjCQQCuAAAAAA==.',
['Ún']='Úncle:BAAALgAECgEJAgAAAA==.',
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
