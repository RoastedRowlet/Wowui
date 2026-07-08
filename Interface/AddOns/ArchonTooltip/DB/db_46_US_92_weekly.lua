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

local lookup = {'Warlock-Demonology','Mage-Frost','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Warrior-Arms','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Druid-Guardian','Druid-Feral','Hunter-Marksmanship','Mage-Fire','Monk-Brewmaster','Mage-Arcane','Priest-Discipline','Druid-Restoration','Warlock-Affliction','Rogue-Outlaw','Warrior-Protection',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abrakådabruh:BAABLgAECn8YAAICAAcJYweEEgDhAAACAAcJYweEEgDhAAAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8cAAMDAAgJNx3pJgCOAQADAAYJwRzpJgCOAQAEAAcJOBEFLwBkAQABLgAFFAcJEAAFAFQFAA==.',
Ae='Aelanori:BAAALgADCgYJCwAAAA==.Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIGAAkJpiCiFQDBAgAGAAkJpiCiFQDBAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainjel:BAAALgAECgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexdh:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Alexr:BAAALgAFFAEJAQAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.Altaxia:BAAALgAECgYJBgAAAA==.',
Am='Amarantus:BAAALgAECgYJCQABLgAFFAUJFQAIAGMPAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAACLgAFFH8KAAIJAAMJcBwBCgC5AAAJAAMJcBwBCgC5AAAuAAQKfxUAAgkACAnJEOocALUBAAkACAnJEOocALUBAAEuAAUUCAkiAAoAmxsA.Anmodru:BAAALgAECgYJBgABLgAFFAgJIgAKAJsbAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAILAAcJxw1rKwBsAQALAAcJxw1rKwBsAQAAAA==.',
Ap='Apoldelon:BAAALgAECgIJAgAAAA==.',
Aq='Aqulath:BAACLgAFFH8ZAAIMAAUJJB9AAwBmAQAMAAUJJB9AAwBmAQAuAAQKfyAAAgwACQluHakEAHACAAwACQluHakEAHACAAAA.Aquílés:BAAALgAECgQJCQAAAA==.',
Ar='Arazensetal:BAABLgAECn9jAAINAAkJ9SIYAACMAwANAAkJ9SIYAACMAwAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAgJFQAOABYNAA==.Ardênt:BAAALgAECgEJAQAAAA==.Ariandrel:BAACLgAFFH8FAAIPAAMJvwYDSQCBAAAPAAMJvwYDSQCBAAAuAAQKfx4AAw8ACQkdETEsAM8BAA8ACQkdETEsAM8BABAAAQlbAE+OABQAAAAA.Aridhol:BAABLgAECn8ZAAIRAAkJ3gLN4AB1AAARAAkJ3gLN4AB1AAAAAA==.Arkaedius:BAACLgAFFH8HAAIRAAMJQxZFXwDSAAARAAMJQxZFXwDSAAAuAAQKfywAAhEACQnIJMQAAOsCABEACQnIJMQAAOsCAAAA.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJDAABLgAECgYJCQAHAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn9UAAILAAkJVySJAAAtAwALAAkJVySJAAAtAwAAAA==.Ation:BAAALgAECgIJBQAAAA==.Atulno:BAAALgAECgcJCQAAAA==.',
Au='Aubrii:BAAALgAECgUJCgAAAA==.Aukatsang:BAACLgAFFH8QAAIQAAgJbByVCACQAQAQAAgJbByVCACQAQAuAAQKfyoAAhAACQmTI10BAKMDABAACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgAECgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8fAAISAAgJ9xz+FAClAgASAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIQAAQJvRyFEwAhAQAQAAQJvRyFEwAhAQAuAAQKfyQAAhAACAndHpEJAN8CABAACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn9TAAITAAkJnB5PBQCdAgATAAkJnB5PBQCdAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAGAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgkJCQAAAA==.',
Be='Bearhold:BAAALgAECgYJCQAAAA==.Beefy:BAAALgAECgMJBAAAAA==.Beenis:BAAALgAECgQJBQAAAA==.Beersnob:BAABLgAECn8kAAIPAAkJLxZfHgAmAgAPAAkJLxZfHgAmAgAAAA==.Bellamafia:BAAALgAECgEJAQAAAA==.Benjam:BAACLgAFFH8TAAIRAAcJrRZQGgDgAQARAAcJrRZQGgDgAQAuAAQKfygAAhEABwnlI0wZAL0CABEABwnlI0wZAL0CAAAA.Benyo:BAAALgAECgUJCQAAAA==.',
Bi='Bigmikeyg:BAABLgAECn9cAAIGAAkJmRyoAgBiAgAGAAkJmRyoAgBiAgAAAA==.Bigsteve:BAABLgAECn9QAAMSAAkJ/CR8BAAdAwASAAkJ9CR8BAAdAwAUAAkJYB6DAACVAgAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMVAAMJJwqwCADLAAAOAAMJiQWXDwD0AAAVAAMJJwqwCADLAAAuAAQKfxYAAw4ABwlSHPUqAKUBAA4ABwkjHPUqAKUBABUAAwmaGgAAAAAAAAAA.Blinded:BAAALgAECgkJAwAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgASAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgYJCQAHAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Brickley:BAAALgAFFAIJAgABLgAFFAUJGQAMACQfAA==.Bronzesun:BAAALgAECgUJCQAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIFAAkJMRpGGQCAAgAFAAkJMRpGGQCAAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
['Bø']='Bønd:BAAALgAECgEJAQAAAA==.',
['Bú']='Búllshifts:BAAALgADCgkJCQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQNAAkJHQX8IgBhAQANAAkJHQX8IgBhAQAWAAMJGgjIMgCAAAAXAAMJ0AigfwBfAAAAAA==.Calizon:BAAALgAECgkJEgAAAA==.Calogero:BAAALgADCgEJAQAAAA==.Camc:BAAALgAECgQJEQAAAA==.Canowhoopass:BAABLgAECn8mAAIYAAgJvApARQAfAQAYAAgJvApARQAfAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cell:BAAALgAFFAIJAgABLgAFFAYJFAAZAHAeAA==.Cerassin:BAACLgAFFH81AAIRAAcJ9hhZCwCdAQARAAcJ9hhZCwCdAQAuAAQKfzYAAhEACQkJIf8KAPACABEACQkJIf8KAPACAAAA.Cereas:BAABLgAECn9EAAILAAkJ4xkFEQAZAgALAAkJ4xkFEQAZAgAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chevota:BAEALgAECgYJBgABLgAFFAQJBwABAHAMAA==.Chichobelo:BAABLgAFFH8VAAQZAAgJYhZxIQDrAQAZAAYJxxhxIQDrAQAaAAUJNRBvBAAwAQAbAAEJAAAWJAAAAAAAAA==.Chuckrutis:BAACLgAFFH8FAAIXAAQJGw81NQDuAAAXAAQJGw81NQDuAAAuAAQKfyEAAxYACAlIHXAMABQCABYABglSHnAMABQCABcABQl4HHErAJEBAAAA.',
Cl='Cliché:BAABLgAECn8kAAMcAAgJPRSRIgDwAQAcAAgJPRSRIgDwAQAGAAYJMge56wDQAAAAAA==.Cloberintime:BAAALgAECgcJCAAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8ZAAIdAAcJWxYZPgAxAQAdAAcJWxYZPgAxAQAuAAQKfyoAAh0ACQk6IXYCAHEDAB0ACQk6IXYCAHEDAAAA.',
Co='Combination:BAABLgAECn9VAAIeAAkJrCLzAAAFAwAeAAkJrCLzAAAFAwABLgAFFAgJLgAGAN0ZAA==.Constrace:BAAALgAECgYJCAAAAA==.Corvenall:BAABLgAECn86AAIWAAkJlA7VCACgAQAWAAkJlA7VCACgAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAABLgAECn8UAAISAAgJIgYjTQASAQASAAgJIgYjTQASAQAAAA==.Crossbow:BAACLgAFFH8KAAIdAAMJJRbFWgDvAAAdAAMJJRbFWgDvAAAuAAQKf0MAAh0ACQkoIBsPAMICAB0ACQkoIBsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAUJGQAMACQfAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJDAABLgAECgkJRAALAOMZAA==.',
['Cõ']='Cõnker:BAAALgAFFAEJAQAAAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Danglyudders:BAABLgAECn8WAAIfAAYJERgJBQAEAQAfAAYJERgJBQAEAQAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAJAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Davinah:BAAALgAECgEJAQAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.Dayje:BAAALgAECgIJAgAAAA==.',
De='Deathbcmesyu:BAACLgAFFH8FAAIZAAIJwQleUwB0AAAZAAIJwQleUwB0AAAuAAQKfyIAAhkACQksG2wrAFICABkACQksG2wrAFICAAAA.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgkJDAABLgAECgkJIQAgAB8hAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwAEANoNAA==.Deondre:BAAALgAECgQJCQAAAA==.Detin:BAAALgAECgEJAQAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJIQAgAB8hAA==.',
Di='Diehappy:BAABLgAECn8bAAMaAAgJAwsdHADuAAAaAAcJgwwdHADuAAAbAAYJ/AX6PQCYAAAAAA==.Dillie:BAAALgAECgUJCQAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAgJHAAMAOchAA==.Dompal:BAABLgAFFH8HAAIGAAMJUCJaIQDQAAAGAAMJUCJaIQDQAAABLgAFFAgJHAAMAOchAA==.Donkystyle:BAAALgAECgQJCAAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJVQACAIUmAA==.Drovinos:BAAALgAECgYJBgAAAA==.Drualia:BAAALgAECgIJAgAAAA==.Druken:BAABLgAECn8XAAIdAAgJEgoQDAA1AQAdAAgJEgoQDAA1AQAAAA==.Drybonez:BAABLgAECn8UAAICAAYJ0Aha+AAKAQACAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8XAAMdAAgJSx8eKwBdAQAdAAcJXx4eKwBdAQAhAAIJSR/hKABnAAAuAAQKfyMAAyEACQm3JNIJAAYDACEACAmdItIJAAYDAB0AAwlvIxyeAAUBAAAA.Dràgonkíng:BAABLgAECn8gAAMiAAkJFQd8CAAIAQAiAAkJFQd8CAAIAQACAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAISAAkJWRwCFABRAgASAAkJWRwCFABRAgABLgAFFAUJGQAZALUdAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIEAAgJ2g1qMQBWAQAEAAgJ2g1qMQBWAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgcJCwAAAA==.',
['Dà']='Dànger:BAAALgADCgEJAQAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAWAKYfAA==.',
Ef='Efran:BAAALgAECgEJAQAAAA==.',
Eg='Ego:BAABLgAECn83AAISAAkJMiSlBwDkAgASAAkJMiSlBwDkAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elijahtheone:BAAALgAECgMJAwAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQACAHciAA==.Emmone:BAAALgAECgYJEQAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.Emorexx:BAAALgAECgYJCwAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAjAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAABLgAECn8eAAIeAAcJ0xeHAQBzAQAeAAcJ0xeHAQBzAQAAAA==.Excaleon:BAAALgAECgYJCwAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAFFAIJAgAAAA==.Faunna:BAACLgAFFH8VAAIIAAUJYw9ELADbAAAIAAUJYw9ELADbAAAuAAQKfz4AAggACQmEIJwHAN0CAAgACQmEIJwHAN0CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgUJBwAAAA==.Felaz:BAABLgAECn82AAIkAAkJJCADAQDFAgAkAAkJJCADAQDFAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAABLgAECn8fAAICAAkJ6xM8BAD4AQACAAkJ6xM8BAD4AQAAAA==.Ferreil:BAAALgAECgEJAgAAAA==.Festy:BAAALgAECgIJAgAAAA==.',
Fi='Fingerguns:BAACLgAFFH8RAAIlAAQJaQgGEADXAAAlAAQJaQgGEADXAAAuAAQKfx0ABCUACQndFSsTAEgCACUACQndFSsTAEgCAAMAAwl3CO5mAJEAAAQAAwkJCChzAFsAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAUPgAA5AQABAAkJDQUPgAA5AQAeAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBwAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgAECgUJCQAAAA==.Floortank:BAABLgAECn80AAMaAAkJbwvREQBbAQAaAAgJ2wvREQBbAQAZAAgJAQYgpQAkAQAAAA==.',
Fo='Fonn:BAAALgAECgYJBwAAAA==.Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIcAAMJUBsJKwDSAAAcAAMJUBsJKwDSAAAuAAQKfxsAAhwABwnKI4sRAIcCABwABwnKI4sRAIcCAAAA.Friday:BAAALgAECgMJBAAAAA==.Frikilatar:BAAALgAECgEJCwAAAA==.Frostyhatesu:BAAALgADCgMJAwABLgAECgIJAwAHAAAAAA==.Frrank:BAACLgAFFH8cAAIUAAgJXCEHBwDuAQAUAAgJXCEHBwDuAQAuAAQKfzQAAhQACQkoJWEAALQDABQACQkoJWEAALQDAAAA.Frugalgunny:BAAALgADCgUJBQAAAA==.',
Fu='Fullerene:BAAALgAECgIJBQAAAA==.Funnelcake:BAAALgAECgYJBgAAAA==.',
Ga='Galcain:BAACLgAFFH8SAAQdAAUJfiCnIgB6AQAdAAUJfiCnIgB6AQAJAAQJSRDJCwCeAAAhAAEJ0QKfGAA4AAAuAAQKfzEABB0ACQlWI/YHABEDAB0ACQkaI/YHABEDAAkACAl9FogYANwBACEAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAUJEgAdAH4gAA==.Ganondorff:BAAALgAECgMJAwAAAA==.Gantz:BAABLgAECn8VAAIGAAkJtQ2pBgCRAQAGAAkJtQ2pBgCRAQAAAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAHAAAAAA==.',
Gi='Gibbie:BAAALgAECgkJCAAAAA==.Gintoko:BAAALgAECgMJBgAAAA==.Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAACLgAFFH8FAAICAAMJJAreLgDHAAACAAMJJAreLgDHAAAuAAQKfy4AAgIACQkGF8BCABMCAAIACQkGF8BCABMCAAAA.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Grimseek:BAACLgAFFH8FAAIhAAQJfxI9FAAnAQAhAAQJfxI9FAAnAQAuAAQKfyYAAiEACQkfHz8AAO4CACEACQkfHz8AAO4CAAEuAAUUCAkuAAYA3RkA.Gripmepapi:BAABLgAFFH8ZAAIZAAQJaBU8KQD2AAAZAAQJaBU8KQD2AAAAAA==.Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgAECgEJAQAAAA==.Grumandel:BAABLgAECn9TAAIgAAkJaiA1BQChAgAgAAkJaiA1BQChAgAAAA==.',
Gu='Guce:BAAALgAECgcJDgAAAA==.Gudetama:BAABLgAECn8bAAMdAAkJsCDBFwB7AgAdAAYJESPBFwB7AgAJAAcJwx16DwA3AgAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgAECgQJBAAAAA==.Hakur:BAABLgAECn88AAIGAAkJQhyCMAA/AgAGAAkJQhyCMAA/AgAAAA==.Halfpink:BAAALgAECgEJAQABLgAECgkJIgAmAD0gAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hammertóe:BAAALgAECgIJBAAAAA==.Hanabi:BAAALgAECgYJBgAAAA==.Hanma:BAACLgAFFH8VAAIZAAcJgRn5IADuAQAZAAcJgRn5IADuAQAuAAQKfygAAhkACQkFHxEsAIgCABkACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn9MAAICAAkJ5hHCCABlAQACAAkJ5hHCCABlAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgAECgQJBAAAAA==.Hiroki:BAABLgAECn8zAAIZAAkJdw+nUADRAQAZAAkJdw+nUADRAQAAAA==.Hitachitotem:BAACLgAFFH8nAAIYAAQJARtMDAALAQAYAAQJARtMDAALAQAuAAQKfxkAAhgACAmtGl0aAEACABgACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJDwAAAA==.Hiyodad:BAAALgADCgUJBQAAAA==.Hiyodadk:BAAALgAECgIJAgAAAA==.Hiyodal:BAAALgAECgQJBAAAAA==.Hiyodam:BAAALgADCgIJAgAAAA==.Hiyodat:BAAALgAECgYJCgAAAA==.Hiyodaw:BAABLgAECn8UAAIeAAUJLQbJJgB/AAAeAAUJLQbJJgB/AAAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Hollycat:BAAALgAECgkJAwAAAA==.Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAIRAAkJ2hquHwBXAgARAAkJ2hquHwBXAgABLgAFFAEJAQAHAAAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAYJGwASAM4gAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQADACsgAA==.Holyshifts:BAABLgAECn8mAAIGAAkJORtCAgCDAgAGAAkJORtCAgCDAgAAAA==.',
Hu='Huxter:BAAALgADCgEJAQAAAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8lAAICAAkJxhTHQwAQAgACAAkJxhTHQwAQAgAAAA==.',
In='Inflikted:BAABLgAECn8lAAIZAAkJVQgQeQBxAQAZAAkJVQgQeQBxAQAAAA==.Interwebz:BAABLgAECn8eAAMZAAkJHh3pIgB7AgAZAAkJKxzpIgB7AgAbAAIJ9h1LPgCXAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Iz='Izztargaryen:BAAALgADCgEJAQAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgYJCQAHAAAAAA==.Jankook:BAAALgAECgEJAQAAAA==.Jazzarin:BAAALgAECgYJCgAAAA==.',
Je='Jehannum:BAABLgAECn9HAAIYAAkJ4ReFAQAtAgAYAAkJ4ReFAQAtAgAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgYJEQAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8JAAIcAAQJfxocIAAcAQAcAAQJfxocIAAcAQABLgAFFAUJLAAFALMlAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgAECgUJCQAAAA==.Jurkzarbirt:BAAALgAECgQJBQAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jì']='Jìnbe:BAABLgAECn8lAAIjAAkJsQ3FAQCLAQAjAAkJsQ3FAQCLAQAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIEAAgJ0hekJQCeAQAEAAgJ0hekJQCeAQAAAA==.',
Ka='Kaefaith:BAAALgAECgMJAwAAAA==.Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kainiy:BAAALgAECgMJBQAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgYJEQAAAA==.Kassan:BAABLgAECn8mAAQEAAkJnRUoAwB7AQAEAAcJMxUoAwB7AQADAAkJ+QkrBABOAQAlAAEJfgIciQAhAAAAAA==.Katarena:BAABLgAECn83AAIcAAgJVRAGMgCOAQAcAAgJVRAGMgCOAQAAAA==.Kathyra:BAECLgAFFH8HAAIBAAQJcAzyfADKAAABAAQJcAzyfADKAAAuAAQKfy0AAwEACQkgFE4IAB8BAAEACQkgFE4IAB8BACcAAQnvASM3ACcAAAAA.Kavax:BAABLgAECn8mAAIcAAkJhBSNGQA6AgAcAAkJhBSNGQA6AgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIGAAYJlw9ZLQBaAQAGAAYJlw9ZLQBaAQAuAAQKfzwAAgYACQnFHiwiAH0CAAYACQnFHiwiAH0CAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kelorth:BAAALgADCggJCAAAAA==.Kentyr:BAABLgAECn83AAMOAAgJ8xFLHACzAQAOAAgJ8xFLHACzAQAoAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khaldormu:BAAALgAECggJBwAAAA==.Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAYJGwASAM4gAA==.Kinký:BAACLgAFFH8LAAISAAQJkgw7DwDoAAASAAQJkgw7DwDoAAAuAAQKfy8AAxIACQk0FlcYACsCABIACQk0FlcYACsCABQAAQnbFDd1ADcAAAEuAAQKCAkUABIAChcA.Kiraelis:BAABLgAECn8lAAIhAAkJqg8WDQCPAQAhAAkJqg8WDQCPAQAAAA==.Kisara:BAAALgADCggJDAABLgAFFAMJBQAGAOsNAA==.Kiss:BAAALgADCgEJAQABLgAECgcJGQAFACIXAA==.Kitchner:BAAALgAECgYJBgAAAA==.Kitetsu:BAAALgAECgEJAQAAAA==.Kivea:BAABLgAECn8aAAMCAAkJZg9LZAC1AQACAAkJZg9LZAC1AQAiAAEJBAe/FQAoAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Konvik:BAAALgAECgEJAQAAAA==.Kooka:BAAALgADCgMJAwAAAA==.Korvoh:BAABLgAECn9RAAMlAAkJLh/MAAC6AgAlAAkJLh/MAAC6AgADAAMJUxeOXQC8AAAAAA==.',
Kr='Krincess:BAABLgAECn8nAAIXAAkJaRrYAABxAgAXAAkJaRrYAABxAgABLgAECgkJNAAYAAAkAA==.Kringe:BAABLgAECn80AAMYAAkJACRvBAAcAwAYAAkJACRvBAAcAwAFAAEJLQQO6QAlAAAAAA==.Krinny:BAAALgAECgUJBQABLgAECgkJNAAYAAAkAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumaro:BAAALgAECgMJAwAAAA==.Kumonk:BAABLgAECn8cAAIQAAcJWAbMSwDTAAAQAAcJWAbMSwDTAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBgAAAA==.',
['Kä']='Kämik:BAABLgAECn9LAAIdAAkJrCG3CgAAAwAdAAkJrCG3CgAAAwAAAA==.',
['Kì']='Kìn:BAABLgAECn8pAAMlAAcJ8wrDPQAWAQAlAAYJggzDPQAWAQAEAAYJfAREEgBRAAAAAA==.',
La='Lampion:BAABLgAECn8hAAILAAkJdAzxIABxAQALAAkJdAzxIABxAQAAAA==.Langris:BAAALgAECgEJAwAAAA==.Lasstchance:BAABLgAECn8cAAIdAAgJpAuyewBIAQAdAAgJpAuyewBIAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8pAAIBAAkJ/h41DwDTAgABAAkJ/h41DwDTAgAAAA==.',
Le='Leijona:BAAALgAECgQJCgAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgAECgUJCQAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Lightbunny:BAAALgAECgMJAwAAAA==.Lightstorms:BAAALgAECgcJCQAAAA==.Likeatrain:BAABLgAECn86AAIpAAkJrBZxDQAUAgApAAkJrBZxDQAUAgAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMcAAgJJRN/KADqAQAcAAgJJRN/KADqAQAGAAUJDgjKDQGoAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMcAAkJOh5bFgBYAgAcAAkJOh5bFgBYAgAGAAYJTQzJ6ADTAAAAAA==.Lintha:BAAALgAECggJEwAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAABLgAECn8UAAMXAAYJKhWDOwA9AQAXAAYJKhWDOwA9AQAWAAEJ3wOVKgAkAAABLgAFFAYJGwASAM4gAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8bAAMOAAgJlBc8GwC9AQAOAAgJlBc8GwC9AQAVAAEJhhD2HwAzAAAAAA==.Lokininja:BAAALgAECgIJAgAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn9VAAIQAAkJkyRPAABAAwAQAAkJkyRPAABAAwAAAA==.',
Lu='Luber:BAACLgAFFH8JAAIFAAMJYwrAIgCPAAAFAAMJYwrAIgCPAAAuAAQKfzUAAwUACQnvDC9DAKEBAAUACQnvDC9DAKEBABgABgkLDfpVAOMAAAAA.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAACLgAFFH8MAAIbAAMJJCUTCAAoAQAbAAMJJCUTCAAoAQAuAAQKf1IAAhsACQkiJrQAAGkDABsACQkiJrQAAGkDAAAA.Luxzy:BAABLgAECn8jAAMdAAgJ8Q9XCQBjAQAdAAcJmBFXCQBjAQAhAAgJ0QcRFQATAQAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgAECgEJAQAAAA==.Manbearcat:BAABLgAECn8iAAImAAkJPSBwCgAWAwAmAAkJPSBwCgAWAwAAAA==.Marbleous:BAACLgAFFH8KAAISAAMJBiQ8KwAHAQASAAMJBiQ8KwAHAQAuAAQKfxgAAhIABgm6Iz8oALoBABIABgm6Iz8oALoBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcdragon:BAAALgAECgUJBQAAAA==.Mcewan:BAAALgADCgUJBQAAAA==.Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIgAmAD0gAA==.Mcspicy:BAAALgAECgUJCAAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAnAFkfAA==.Mechalomania:BAAALgAECgkJCQABLgAECgkJOgAIAKAQAA==.Melhina:BAAALgAECgUJCQABLgAECgkJPAAnAG8cAA==.Memisstotem:BAABLgAECn8eAAIFAAcJgRrRMgDoAQAFAAcJgRrRMgDoAQAAAA==.Merle:BAACLgAFFH8bAAMSAAYJziArBwBSAQASAAUJAyIrBwBSAQAUAAQJFhfzBABMAQAuAAQKf1UAAxIACQloJcYCAEUDABIACQk0JMYCAEUDABQABgncJIUOAAMCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8dAAIRAAgJ7Rn7KQAhAgARAAgJ7Rn7KQAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Mikethegray:BAABLgAECn8fAAIYAAkJNRDOAgCgAQAYAAkJNRDOAgCgAQABLgAECgkJXAAGAJkcAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8eAAIDAAcJmA2DNQAtAQADAAcJmA2DNQAtAQAAAA==.Mistborn:BAABLgAECn84AAQDAAkJiCIhCQC5AgADAAkJiCIhCQC5AgAlAAQJ1RyJKQBMAQAEAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAWAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn87AAIgAAkJZCDxAgDvAgAgAAkJZCDxAgDvAgAAAA==.Monkjamin:BAABLgAFFH8GAAIjAAMJThcKNgDOAAAjAAMJThcKNgDOAAAAAA==.Moolimbo:BAABLgAECn8qAAIYAAkJghi7FgAwAgAYAAkJghi7FgAwAgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAWAKYfAA==.Mooseboy:BAABLgAECn8tAAIgAAkJah70BACpAgAgAAkJah70BACpAgAAAA==.Mooserton:BAACLgAFFH8FAAIcAAMJeBAeMQCvAAAcAAMJeBAeMQCvAAAuAAQKfzYAAxwACQmaHEoIAAcDABwACQmaHEoIAAcDAAYABgmsD8/cAOIAAAAA.Mootalstrike:BAABLgAECn8zAAISAAkJbhVUHwD0AQASAAkJbhVUHwD0AQAAAA==.Moshworm:BAABLgAECn86AAIIAAkJoBD3IgCyAQAIAAkJoBD3IgCyAQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAUJGQAZALUdAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgIJAwAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAcJGQAdAFsWAA==.Myraxes:BAAALgADCgIJAgAAAA==.',
['Mä']='Mängo:BAAALgADCgYJCAAAAA==.',
Na='Nalaxx:BAAALgAECgkJAQAAAA==.Natsumi:BAABLgAECn8WAAIFAAcJxgvbZgAnAQAFAAcJxgvbZgAnAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIXAAYJVQPRQwDRAAAXAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAICAAkJBh4LIwCRAgACAAkJBh4LIwCRAgAAAA==.Neuroticaine:BAABLgAECn9aAAMEAAkJMxxiAQAjAgAEAAkJMxxiAQAjAgAlAAQJVQ4JSwDYAAAAAA==.Nev:BAACLgAFFH8SAAMdAAQJsCGMMABOAQAdAAQJsCGMMABOAQAhAAMJ6AVCGQDAAAAuAAQKfyEAAx0ACAncIsYjAC8CAB0ABwkjIsYjAC8CACEABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8TAAIOAAQJfg0LDwDdAAAOAAQJfg0LDwDdAAAAAA==.',
Ni='Nico:BAABLgAECn8bAAIJAAkJChIjEQCxAQAJAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQnAAkJWR+gBABRAgAnAAkJUx+gBABRAgAeAAcJIBqjCgCZAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgAECgUJCQAAAA==.Nooblets:BAACLgAFFH8HAAIOAAMJ/xoZKQDiAAAOAAMJ/xoZKQDiAAAuAAQKfxsAAg4ABwnMIGMbALwBAA4ABwnMIGMbALwBAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMRAAkJQBLCVACIAQARAAkJQBLCVACIAQAMAAIJwhRuMgA6AAAAAA==.Noxxus:BAABLgAECn8fAAITAAkJvRqdDAD9AQATAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAnAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAAALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAACLgAFFH8RAAIZAAQJVAf+KQDyAAAZAAQJVAf+KQDyAAAuAAQKfx0AAxkACQkqDKVnAJcBABkACQkqDKVnAJcBABsAAQn0AfNmABwAAAAA.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAYAIIYAA==.',
Om='Omnivus:BAAALgAECgMJBgAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgIJBQAHAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAcAFAbAA==.Oratherah:BAABLgAFFH8LAAIbAAMJziS0JgC+AAAbAAMJziS0JgC+AAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8rAAISAAkJfCILBwDtAgASAAkJfCILBwDtAgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAABLgAECn8YAAILAAgJLxY7FgDYAQALAAgJLxY7FgDYAQAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn9VAAIaAAkJoQwNAgBBAQAaAAkJoQwNAgBBAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAYAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHgAZAB4dAA==.Pinkrosé:BAAALgAECgcJBwAAAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIgAmAD0gAA==.Pitchblende:BAABLgAECn8xAAIcAAkJMBKAHwAHAgAcAAkJMBKAHwAHAgAAAA==.',
Po='Poeppsul:BAAALgAECgEJAQAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Polyrock:BAAALgADCgQJBAAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAZAOEkAA==.Porthub:BAABLgAECn8pAAICAAkJLAkneACJAQACAAkJLAkneACJAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAABLgAECn8YAAMdAAgJKRJBbABpAQAdAAgJKRJBbABpAQAhAAEJAAB3SQAAAAAAAA==.Rajak:BAAALgAECgYJCAAAAA==.Range:BAAALgAFFAIJAgAAAA==.Raph:BAABLgAECn8XAAImAAYJAxp9BQAfAQAmAAYJAxp9BQAfAQAAAA==.Rathibrew:BAACLgAFFH8cAAIjAAgJDhx4DADOAQAjAAgJDhx4DADOAQAuAAQKfzgAAiMACQmcJLwBAIwDACMACQmcJLwBAIwDAAAA.',
Re='Reckurface:BAAALgAECgEJAQAAAA==.Redine:BAAALgAECgQJBAAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgcJCgAAAA==.Rellt:BAAALgADCgQJBgAAAA==.Remnants:BAABLgAECn8UAAIjAAYJihvDJwDIAQAjAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8YAAQDAAgJRQe3OQASAQADAAgJRQe3OQASAQAEAAUJEAOrbQBpAAAlAAEJ4gHeigAcAAAAAA==.',
Rh='Rhayge:BAABLgAECn8VAAIKAAkJ/BeKAABPAgAKAAkJ/BeKAABPAgAAAA==.Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgQJCAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAHAAAAAA==.Rompally:BAAALgAECgYJCQAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8ZAAQZAAUJtR0lQwBvAQAZAAUJtR0lQwBvAQAaAAEJUQ3YJwBGAAAbAAEJAAA8WAAAAAAuAAQKfzEAAhkACQnGHywrAFMCABkACQnGHywrAFMCAAAA.',
['Rê']='Rêvolt:BAABLgAFFH8IAAIRAAIJYg4LggB7AAARAAIJYg4LggB7AAAAAA==.Rêzìcå:BAAALgADCgkJCQAAAA==.',
['Rô']='Rôwdy:BAAALgAECgEJAQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAABLgAECn8ZAAMdAAgJ0getfABGAQAdAAgJ0getfABGAQAhAAQJWwF4PAAyAAAAAA==.Salezar:BAABLgAECn8rAAIWAAkJph9jAQDnAgAWAAkJph9jAQDnAgAAAA==.Sandoud:BAABLgAECn8cAAIIAAkJ6xNFGgD5AQAIAAkJ6xNFGgD5AQAAAA==.Sapientia:BAABLgAECn8tAAIGAAkJqwgTjABZAQAGAAkJqwgTjABZAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECgkJRAALAOMZAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgAECgEJAgAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIcAAQJcw/iKADdAAAcAAQJcw/iKADdAAAuAAQKfyEAAxwACAlaGMcZAEUCABwACAlaGMcZAEUCAAYAAQnyDycyAT8AAAEuAAUUCAkiAAIAThoA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAMJBAAAAA==.Selenesul:BAABLgAECn8sAAMGAAkJ9RxlHwCLAgAGAAkJ9RxlHwCLAgATAAMJTAynNAB0AAAAAA==.Selyda:BAAALgAECgEJAQAAAA==.Senzie:BAACLgAFFH8ZAAIQAAUJex96DABgAQAQAAUJex96DABgAQAuAAQKfyUAAhAACQkiHlYNAHACABAACQkiHlYNAHACAAEuAAUUBgkRABAAuBIA.Sevro:BAAALgADCgQJBAABLgAECgkJJgAcAIQUAA==.',
Sh='Shadowdrake:BAABLgAECn8hAAIXAAkJ+wsCBgDZAAAXAAkJ+wsCBgDZAAAAAA==.Shadowheàrt:BAABLgAECn8mAAMcAAcJkBf4AwBRAQAcAAYJSxf4AwBRAQAGAAQJOQU8OAF1AAAAAA==.Shadowshifty:BAABLgAECn8mAAIfAAgJLQ9vBQD0AAAfAAgJLQ9vBQD0AAAAAA==.Shadowtotem:BAAALgAECgYJBgAAAA==.Shaeen:BAABLgAFFH8JAAIMAAMJpRD7CQCxAAAMAAMJpRD7CQCxAAAAAA==.Shagi:BAABLgAECn8qAAIjAAkJJxanFwDrAQAjAAkJJxanFwDrAQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Shanson:BAAALgAECgQJBAAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharklee:BAAALgADCgEJAgAAAA==.Sharroz:BAABLgAECn8dAAMaAAcJiB1oAwBWAgAaAAcJiB1oAwBWAgAbAAQJVQ7wQQCHAAAAAA==.Shauna:BAACLgAFFH8PAAIdAAcJGBUIBQAKAgAdAAcJGBUIBQAKAgAuAAQKfxUAAh0ACAn6DqhOALYBAB0ACAn6DqhOALYBAAAA.Shdw:BAAALgAECgUJCQAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMlAAgJeBpPFwAcAgAlAAgJeBpPFwAcAgAEAAEJJQKaaQAlAAABLgAFFAUJGQAZALUdAA==.Shockybalboa:BAABLgAECn8UAAIYAAcJNBP/NQBiAQAYAAcJNBP/NQBiAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBwAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skoftyia:BAAALgAECgEJAQABLgAFFAMJCgASAIIVAA==.Skooda:BAABLgAECn8tAAIYAAkJaA5AMAB+AQAYAAkJaA5AMAB+AQAAAA==.Skyded:BAABLgAECn8yAAIZAAkJLBn3MAA7AgAZAAkJLBn3MAA7AgAAAA==.Skyfire:BAAALgAECgYJAQAAAA==.Skyknight:BAABLgAECn8iAAISAAkJ/RN0KQCzAQASAAkJ/RN0KQCzAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8QAAMJAAYJ8xJEFAAqAQAJAAYJ8xJEFAAqAQAhAAIJBwsJJwB0AAAuAAQKfzsAAwkACQlyI3kEAOYCAAkACQlQInkEAOYCACEACAnWHuoSAJ8CAAAA.Slaughterman:BAAALgAECgEJAwAAAA==.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgADCgYJCwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8vAAIRAAkJdR6OAQBOAgARAAkJdR6OAQBOAgAAAA==.Solence:BAAALgADCgIJAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAABLgAECn8cAAIGAAgJuR06IwB4AgAGAAgJuR06IwB4AgAAAA==.Soralas:BAAALgAECgcJEgAAAA==.',
Sp='Spaazz:BAABLgAECn8lAAIGAAkJsyGAFADHAgAGAAkJsyGAFADHAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
St='Staggerstout:BAAALgAECgEJAQAAAA==.Starofdreams:BAAALgAECgQJCAABLgAECgkJLAAlADoTAA==.Starweaver:BAABLgAECn8sAAMlAAkJOhOyKQCHAQAlAAkJ4gmyKQCHAQADAAgJJhMDKwBwAQAAAA==.Stellmarine:BAABLgAECn8dAAIIAAkJzRoSGwDyAQAIAAkJzRoSGwDyAQAAAA==.Stelthest:BAAALgAECgQJBAAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgcJEwAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMfAAkJIhu3CABhAgAfAAkJ4Rq3CABhAgAIAAYJBBrnKgCqAQAAAA==.',
Su='Sunamé:BAAALgAECgUJCwAAAA==.Sunarianna:BAAALgAECgUJBgAAAA==.',
Sw='Swaazil:BAACLgAFFH8YAAICAAQJcwgtKQDfAAACAAQJcwgtKQDfAAAuAAQKfyYAAgIACQkrEaBeAMMBAAIACQkrEaBeAMMBAAAA.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgQJBQAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAHAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8fAAIRAAcJIQ1RiAAPAQARAAcJIQ1RiAAPAQAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taken:BAAALgAECgYJBgAAAA==.Taloriesh:BAACLgAFFH8HAAIDAAMJ3x66GAD2AAADAAMJ3x66GAD2AAAuAAQKfysABAMACQmlHmwIAOQCAAMACQmlHmwIAOQCAAQAAQk+FepgADYAACUAAQkdDlJ8AC8AAAAA.Tanazir:BAEBLgAECn8eAAMWAAkJpRCeCQCMAQAWAAgJKhGeCQCMAQAXAAIJ5g8qCwByAAAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarivel:BAAALgAECgIJAgAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8ZAAIQAAgJKRA2KwBkAQAQAAgJKRA2KwBkAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIeAAgJnBwLBQAlAgAeAAgJnBwLBQAlAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECgkJHgAWAKUQAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIGAAkJLBlZRQATAgAGAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8XAAIdAAcJKQapmQANAQAdAAcJKQapmQANAQAAAA==.Tilamano:BAACLgAFFH8GAAIBAAIJ1iOGdwDTAAABAAIJ1iOGdwDTAAAuAAQKfzsABB4ACQmlJfgBAK4CAB4ACAnSJPgBAK4CACcACAk6JPgCAJMCAAEACAkyJEMmAEQCAAAA.Tilthulhu:BAAALgAECgMJAwABLgAFFAIJBgABANYjAA==.',
Tl='Tlital:BAAALgAECgEJAQAAAA==.',
Tm='Tmntmikey:BAABLgAFFH8WAAQPAAYJhxPVDgAxAQAPAAYJhxPVDgAxAQAjAAMJbgHpRACOAAAQAAEJvAfsRgAzAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMdAAcJRCMZHwBLAgAdAAcJgCIZHwBLAgAhAAYJMSMUIgAVAgABLgAFFAEJAQAHAAAAAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAjAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAjAO8lAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAjAO8lAA==.Toopie:BAACLgAFFH8FAAIjAAEJ7yUyTwBlAAAjAAEJ7yUyTwBlAAAuAAQKfx4AAyMACAn7IWULANcCACMACAn7IWULANcCABAABQlvGSQ4AD0BAAAA.Totemwebz:BAAALgAECgQJBAAAAA==.Totoku:BAABLgAECn8VAAIFAAkJ3hRnAgA0AgAFAAkJ3hRnAgA0AgAAAA==.',
Tr='Trackdown:BAAALgAECgcJBwAAAA==.Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8qAAImAAkJxBsvEgC8AgAmAAkJxBsvEgC8AgAAAA==.Tryath:BAABLgAECn8ZAAMmAAgJ4wqVcwDaAAAmAAcJcAiVcwDaAAAIAAQJzAmvZwCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
Ty='Tyrethia:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIeAAUJAhUcBwAlAQAeAAUJAhUcBwAlAQAuAAQKfyQAAh4ACQl8G2oCAOUCAB4ACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIJAAkJCh8hAwABAwAJAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAIRAAkJQiBfEwDlAgARAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECggJHQACAOsVAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn8/AAITAAkJoiMnAgAYAwATAAkJoiMnAgAYAwAAAA==.Valros:BAAALgADCgEJAQABLgAECgkJKgAjACcWAA==.Vanaras:BAAALgAECgIJAgAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgUJDwABLgAFFAIJBQAZAMEJAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMOAAkJnxYOFQD4AQAOAAkJshUOFQD4AQAVAAUJ8xGAEwDJAAAAAA==.Veraana:BAABLgAECn8bAAIcAAcJcxsRAgDYAQAcAAcJcxsRAgDYAQAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn9eAAIdAAkJNB74AQCdAgAdAAkJNB74AQCdAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8iAAQlAAgJfyJJDABZAgAlAAgJfyJJDABZAgAEAAEJphQvOQBIAAADAAEJuweXGgAnAAAuAAQKfywAAyUACQnfJhEAAPkDACUACQnfJhEAAPkDAAQAAQnWIX5xAF8AAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJBAAAAA==.Vidette:BAAALgAECgEJAQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAnAFkfAA==.Viv:BAABLgAECn8qAAMTAAkJLiK8BQCWAgATAAcJPCS8BQCWAgAGAAcJCSJWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8gAAIGAAkJjAallQBJAQAGAAkJjAallQBJAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAABLgAECn8WAAMZAAgJzAeGpQAjAQAZAAgJ4waGpQAjAQAbAAMJXQgaYAAqAAAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAABLgAECn8XAAIRAAYJ7ROIkAD/AAARAAYJ7ROIkAD/AAABLgAFFAUJCgAXAKIXAA==.Warrendemon:BAACLgAFFH8aAAIRAAgJCyMEFgABAgARAAgJCyMEFgABAgAuAAQKfzUAAxEACQkDJrsBAMADABEACQkDJrsBAMADAAsAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgkJFwAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAICAAkJWBOvUgA/AgACAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8hAAMgAAkJHyHIBACuAgAgAAkJ1SDIBACuAgAfAAMJ+xQkPgCuAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Woregontail:BAAALgADCggJCAAAAA==.Wowbelly:BAACLgAFFH8IAAIPAAQJggxzNgDPAAAPAAQJggxzNgDPAAAuAAQKfx0AAg8ABwnFG0EWABECAA8ABwnFG0EWABECAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAAPAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAABLgAECn8XAAMGAAcJsg6EsgAbAQAGAAcJpAuEsgAbAQATAAYJlA6bKADSAAAAAA==.',
Xo='Xonk:BAACLgAFFH8eAAInAAgJuxChAACVAQAnAAgJuxChAACVAQAuAAQKfyQAAicACQkQICwBAPECACcACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAFFAIJBQAZAMEJAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEwAAAA==.',
Yu='Yuuna:BAABLgAECn8YAAIBAAcJrgR+ywC6AAABAAcJrgR+ywC6AAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8WAAMLAAgJYAkYKwAnAQALAAgJYAkYKwAnAQARAAYJ+QID3wB5AAAAAA==.Zapp:BAABLgAECn8WAAIVAAYJiwpsAgCsAAAVAAYJiwpsAgCsAAAAAA==.Zaps:BAABLgAECn8pAAIKAAkJKCMpAgADAwAKAAkJKCMpAgADAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8dAAICAAgJ2BJeggBzAQACAAgJ2BJeggBzAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMFAAkJ4QstTgB4AQAFAAkJ4QstTgB4AQAYAAcJxwg5VQDlAAAAAA==.Zenreto:BAABLgAECn9JAAIVAAkJ1yAvAACWAgAVAAkJ1yAvAACWAgAAAA==.Zerani:BAAALgADCgcJBwAAAA==.Zerce:BAAALgAECgEJAQAAAA==.Zergonia:BAAALgADCgMJAwAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8aAAICAAgJjxodLwCwAQACAAgJjxodLwCwAQAuAAQKfysAAgIACAnAJG0SADkDAAIACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8iAAIKAAgJmxtlAABKAgAKAAgJmxtlAABKAgAuAAQKfzAAAgoACQkGJXQAAHADAAoACQkGJXQAAHADAAAA.',
['Ät']='Äthena:BAABLgAECn8WAAIeAAYJMgf+BQCBAAAeAAYJMgf+BQCBAAAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8zAAMBAAkJuR3tGgCCAgABAAkJuR3tGgCCAgAeAAQJGwjCQQCuAAAAAA==.',
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
