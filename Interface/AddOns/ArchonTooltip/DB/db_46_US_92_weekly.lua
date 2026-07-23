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

local lookup = {'Warlock-Demonology','Mage-Frost','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Warrior-Arms','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Druid-Guardian','Druid-Restoration','Druid-Feral','Hunter-Marksmanship','Mage-Fire','Monk-Brewmaster','Mage-Arcane','Priest-Discipline','Warlock-Affliction','Rogue-Outlaw','Warrior-Protection',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abchanchu:BAAALgAECgIJAgAAAA==.Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abrakådabruh:BAABLgAECn8fAAICAAkJWgn1DQBOAQACAAkJWgn1DQBOAQAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8eAAMDAAgJNx3pJgCOAQADAAYJwRzpJgCOAQAEAAcJIhMFLwBkAQABLgAFFAcJEAAFAFQFAA==.',
Ae='Aelanori:BAAALgAECgEJAQAAAA==.Aethira:BAAALgAECgEJAwAAAA==.',
Ag='Ageros:BAAALgADCgEJAQAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIGAAkJpiCiFQDBAgAGAAkJpiCiFQDBAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainjel:BAAALgAECgIJBAAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexdh:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Alexr:BAAALgAFFAEJAQAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.Altaxia:BAAALgAECgYJBgAAAA==.',
Am='Amarantus:BAAALgAECgYJCQABLgAFFAUJGQAIADMRAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAACLgAFFH8KAAIJAAMJcBw7DQCsAAAJAAMJcBw7DQCsAAAuAAQKfxUAAgkACAnJEOocALUBAAkACAnJEOocALUBAAEuAAUUCAkiAAoAmxsA.Anmodru:BAAALgAECgYJBgABLgAFFAgJIgAKAJsbAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAILAAcJxw1rKwBsAQALAAcJxw1rKwBsAQAAAA==.',
Ap='Apoldelon:BAAALgAECgIJAgAAAA==.',
Aq='Aqulath:BAACLgAFFH8aAAIMAAYJAB5AAwBmAQAMAAYJAB5AAwBmAQAuAAQKfyYAAgwACQltH7MAAG0CAAwACQltH7MAAG0CAAAA.Aquílés:BAAALgAECgQJCQAAAA==.',
Ar='Arazensetal:BAABLgAECn9lAAINAAkJ9SIeAACVAwANAAkJ9SIeAACVAwAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAgJFQAOABYNAA==.Ardênt:BAAALgAECgEJAQAAAA==.Ariandrel:BAACLgAFFH8FAAIPAAMJvwYDSQCBAAAPAAMJvwYDSQCBAAAuAAQKfx4AAw8ACQkdETEsAM8BAA8ACQkdETEsAM8BABAAAQlbAE+OABQAAAAA.Aridhol:BAABLgAECn8gAAIRAAkJ3gObGgCMAAARAAkJ3gObGgCMAAAAAA==.Arkaedius:BAACLgAFFH8HAAIRAAMJQxZFXwDSAAARAAMJQxZFXwDSAAAuAAQKfywAAhEACQnIJCsBAN8CABEACQnIJCsBAN8CAAAA.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJDAABLgAECgYJCQAHAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.Astravelle:BAAALgADCgcJBwAAAA==.',
At='Athenä:BAABLgAECn9bAAILAAkJbCS0AAA6AwALAAkJbCS0AAA6AwAAAA==.Ation:BAAALgAECgIJCAAAAA==.Atulno:BAAALgAECgcJCQAAAA==.',
Au='Aubrii:BAAALgAECgUJBgAAAA==.Aukatsang:BAACLgAFFH8QAAIQAAgJbByVCACQAQAQAAgJbByVCACQAQAuAAQKfyoAAhAACQmTI10BAKMDABAACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgAECgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8fAAISAAgJ9xz+FAClAgASAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIQAAQJvRyFEwAhAQAQAAQJvRyFEwAhAQAuAAQKfyQAAhAACAndHpEJAN8CABAACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn9TAAITAAkJnB5PBQCdAgATAAkJnB5PBQCdAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAGAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgAECgUJBQAAAA==.',
Be='Bearhold:BAAALgAECgYJCQAAAA==.Beautyblood:BAAALgADCgMJAwAAAA==.Beefy:BAAALgAECgMJBAAAAA==.Beenis:BAAALgAECgQJBQAAAA==.Beersnob:BAABLgAECn8kAAIPAAkJLxZfHgAmAgAPAAkJLxZfHgAmAgAAAA==.Bellamafia:BAAALgAECgEJAQAAAA==.Benjam:BAACLgAFFH8TAAIRAAcJrRZQGgDgAQARAAcJrRZQGgDgAQAuAAQKfygAAhEABwnlI0wZAL0CABEABwnlI0wZAL0CAAAA.Benyo:BAAALgAECgYJCgAAAA==.',
Bi='Bigmikeyg:BAABLgAECn9jAAIGAAkJ3hyGAwB9AgAGAAkJ3hyGAwB9AgAAAA==.Bigsteve:BAABLgAECn9QAAMSAAkJ/CR8BAAdAwASAAkJ9CR8BAAdAwAUAAkJYB7AAACTAgAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMVAAMJJwqwCADLAAAOAAMJiQWXDwD0AAAVAAMJJwqwCADLAAAuAAQKfxYAAw4ABwlSHPUqAKUBAA4ABwkjHPUqAKUBABUAAwmaGgAAAAAAAAAA.Blinded:BAAALgAECgkJAwAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgASAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgYJCQAHAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Brickley:BAAALgAFFAIJAgABLgAFFAYJGgAMAAAeAA==.Bronzesun:BAAALgAECgUJCQAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIFAAkJMRpGGQCAAgAFAAkJMRpGGQCAAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
['Bø']='Bønd:BAAALgAECgEJAQAAAA==.',
['Bú']='Búllshifts:BAAALgADCgkJCQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQNAAkJHQX8IgBhAQANAAkJHQX8IgBhAQAWAAMJGgjIMgCAAAAXAAMJ0AigfwBfAAAAAA==.Calizon:BAAALgAECgkJEgAAAA==.Calogero:BAAALgADCgEJAQAAAA==.Camc:BAAALgAECgQJEQAAAA==.Canowhoopass:BAABLgAECn8mAAIYAAgJvApARQAfAQAYAAgJvApARQAfAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cell:BAAALgAFFAIJAgABLgAFFAYJFAAZAHAeAA==.Cerassin:BAACLgAFFH8+AAIRAAcJ9hijDwCVAQARAAcJ9hijDwCVAQAuAAQKfzYAAhEACQkJIf8KAPACABEACQkJIf8KAPACAAAA.Cereas:BAABLgAECn9JAAILAAkJFho9AwC8AQALAAkJFho9AwC8AQAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chevota:BAEALgAFFAEJAQABLgAFFAQJBwABAHAMAA==.Chichobelo:BAABLgAFFH8VAAQZAAgJYhZxIQDrAQAZAAYJxxhxIQDrAQAaAAUJNRC/BgAgAQAbAAEJAADPLAAAAAAAAA==.Chuckrutis:BAACLgAFFH8FAAIXAAQJGw81NQDuAAAXAAQJGw81NQDuAAAuAAQKfyEAAxYACAlIHXAMABQCABYABglSHnAMABQCABcABQl4HHErAJEBAAAA.Chulk:BAAALgAECgUJBQAAAA==.',
Cl='Cliché:BAABLgAECn8kAAMcAAgJPRSRIgDwAQAcAAgJPRSRIgDwAQAGAAYJMge56wDQAAAAAA==.Cloberintime:BAAALgAECgkJDwAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8ZAAIdAAcJWxYZPgAxAQAdAAcJWxYZPgAxAQAuAAQKfyoAAh0ACQk6IXYCAHEDAB0ACQk6IXYCAHEDAAAA.',
Co='Combination:BAABLgAECn9VAAIeAAkJrCLzAAAFAwAeAAkJrCLzAAAFAwABLgAFFAgJLgAGAN0ZAA==.Constrace:BAAALgAECgYJCAAAAA==.Corvenall:BAABLgAECn86AAIWAAkJlA7VCACgAQAWAAkJlA7VCACgAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAABLgAECn8UAAISAAgJIgYjTQASAQASAAgJIgYjTQASAQAAAA==.Crossbow:BAACLgAFFH8KAAIdAAMJJRbFWgDvAAAdAAMJJRbFWgDvAAAuAAQKf0MAAh0ACQkoIBsPAMICAB0ACQkoIBsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAYJGgAMAAAeAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJDAABLgAECgkJSQALABYaAA==.',
['Cõ']='Cõnker:BAAALgAFFAEJAQAAAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Danglyudders:BAABLgAECn8bAAMfAAgJFxY9BwD/AAAfAAYJERg9BwD/AAAgAAUJRQ2DCgDVAAAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAJAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darshul:BAAALgAECgEJAQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Davinah:BAAALgAECgEJAgAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.Dayje:BAAALgAECgMJBQAAAA==.',
De='Deathation:BAAALgAECgEJAQAAAA==.Deathbcmesyu:BAACLgAFFH8GAAIZAAIJGA7HZQB6AAAZAAIJGA7HZQB6AAAuAAQKfzUAAxkACQlnIA8CAOcCABkACQlnIA8CAOcCABoAAQliDXERACgAAAAA.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgkJDAABLgAECgkJIQAhAB8hAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwAEANoNAA==.Deondre:BAAALgAECgQJCQAAAA==.Detin:BAAALgAECgEJAQAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJIQAhAB8hAA==.',
Di='Diehappy:BAABLgAECn8dAAMaAAgJcgwdHADuAAAaAAcJjQwdHADuAAAbAAYJRwn6PQCYAAAAAA==.Dillie:BAAALgAECgUJCQAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAgJHAAMAOchAA==.Dompal:BAABLgAFFH8HAAIGAAMJUCLBLADHAAAGAAMJUCLBLADHAAABLgAFFAgJHAAMAOchAA==.Donkyote:BAAALgAECgMJAwAAAA==.Donkystyle:BAAALgAECgQJCAAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJXgACAM0mAA==.Drovinos:BAAALgAECgYJBgAAAA==.Drualia:BAAALgAECgIJAgAAAA==.Druken:BAABLgAECn8XAAIdAAgJEgprEAA9AQAdAAgJEgprEAA9AQAAAA==.Drybonez:BAABLgAECn8UAAICAAYJ0Aha+AAKAQACAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8XAAMdAAgJSx8eKwBdAQAdAAcJXx4eKwBdAQAiAAIJSR/hKABnAAAuAAQKfyMAAyIACQm3JNIJAAYDACIACAmdItIJAAYDAB0AAwlvIxyeAAUBAAAA.Dràgonkíng:BAABLgAECn8gAAMjAAkJFQd8CAAIAQAjAAkJFQd8CAAIAQACAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAISAAkJWRwCFABRAgASAAkJWRwCFABRAgABLgAFFAUJGQAZALUdAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIEAAgJ2g1qMQBWAQAEAAgJ2g1qMQBWAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgcJCwAAAA==.',
['Dà']='Dànger:BAAALgADCgEJAQAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAWAKYfAA==.',
Ef='Efran:BAAALgAECgEJAQAAAA==.',
Eg='Ego:BAABLgAECn83AAISAAkJMiSlBwDkAgASAAkJMiSlBwDkAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elijahtheone:BAAALgAECgMJAwAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQACAHciAA==.Emmone:BAAALgAECgYJEQAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.Emorexx:BAAALgAECgYJCwAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAkAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAACLgAFFH8FAAIeAAIJ7QrDCACDAAAeAAIJ7QrDCACDAAAuAAQKfyAAAh4ABwmRGA4CAH4BAB4ABwmRGA4CAH4BAAAA.Excaleon:BAAALgAECgYJCwAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Falcon:BAAALgADCgUJBQAAAA==.Farglight:BAAALgAFFAIJAgAAAA==.Faunna:BAACLgAFFH8ZAAIIAAUJMxF8EADuAAAIAAUJMxF8EADuAAAuAAQKfz4AAggACQmEIJwHAN0CAAgACQmEIJwHAN0CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgUJBwAAAA==.Felaz:BAABLgAECn82AAIlAAkJJCADAQDFAgAlAAkJJCADAQDFAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAABLgAECn8gAAICAAkJ6xNEBgD0AQACAAkJ6xNEBgD0AQAAAA==.Ferreil:BAAALgAECgEJAwAAAA==.Festy:BAAALgAECgIJAgAAAA==.',
Fi='Fingerguns:BAACLgAFFH8RAAImAAQJaQipFADOAAAmAAQJaQipFADOAAAuAAQKfx0ABCYACQndFSsTAEgCACYACQndFSsTAEgCAAMAAwl3CO5mAJEAAAQAAwkJCChzAFsAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAUPgAA5AQABAAkJDQUPgAA5AQAeAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBwAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgAECgYJCgAAAA==.Floortank:BAABLgAECn81AAMaAAkJbwvREQBbAQAaAAgJ2wvREQBbAQAZAAgJAQYgpQAkAQAAAA==.',
Fo='Fonn:BAAALgAECgYJBwAAAA==.Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freamh:BAAALgADCgYJBgAAAA==.Freeteddyp:BAACLgAFFH8LAAIcAAMJUBsJKwDSAAAcAAMJUBsJKwDSAAAuAAQKfxsAAhwABwnKI4sRAIcCABwABwnKI4sRAIcCAAAA.Friday:BAAALgAECgMJBQAAAA==.Frikilatar:BAAALgAECgEJDAAAAA==.Frostyhatesu:BAAALgADCgMJAwABLgAECgIJAwAHAAAAAA==.Frrank:BAACLgAFFH8cAAIUAAgJXCEHBwDuAQAUAAgJXCEHBwDuAQAuAAQKfzQAAhQACQkoJWEAALQDABQACQkoJWEAALQDAAAA.Frugalgunny:BAAALgADCgUJBQAAAA==.',
Fu='Fullerene:BAAALgAECgMJBgAAAA==.Funnelcake:BAAALgAECgYJBgAAAA==.',
Ga='Galcain:BAACLgAFFH8SAAQdAAUJfiCnIgB6AQAdAAUJfiCnIgB6AQAJAAQJSRAlDwCUAAAiAAEJ0QI8HgA0AAAuAAQKfzEABB0ACQlWI/YHABEDAB0ACQkaI/YHABEDAAkACAl9FogYANwBACIAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAUJEgAdAH4gAA==.Ganondorff:BAAALgAECgMJAwAAAA==.Gantz:BAABLgAECn8XAAIGAAkJ2w01CgCLAQAGAAkJ2w01CgCLAQAAAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAHAAAAAA==.',
Gi='Gibbie:BAAALgAECgkJCAAAAA==.Gintoko:BAAALgAECgMJBgAAAA==.Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAACLgAFFH8FAAICAAMJJArAOgDDAAACAAMJJArAOgDDAAAuAAQKfy4AAgIACQkGF8BCABMCAAIACQkGF8BCABMCAAAA.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Greybull:BAAALgAECgEJAQAAAA==.Grimseek:BAACLgAFFH8FAAIiAAQJfxI9FAAnAQAiAAQJfxI9FAAnAQAuAAQKfy0AAiIACQmxIjYAADkDACIACQmxIjYAADkDAAEuAAUUCAkuAAYA3RkA.Gripmepapi:BAABLgAFFH8dAAIZAAQJeheyLgAIAQAZAAQJeheyLgAIAQAAAA==.Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgAECgEJAQAAAA==.Grumandel:BAABLgAECn9TAAIhAAkJaiA1BQChAgAhAAkJaiA1BQChAgAAAA==.',
Gu='Guce:BAAALgAECgcJDgAAAA==.Gudetama:BAABLgAECn8bAAMdAAkJsCDBFwB7AgAdAAYJESPBFwB7AgAJAAcJwx16DwA3AgAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gungnir:BAAALgAECgMJAwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgAECgQJBAAAAA==.Hakur:BAABLgAECn88AAIGAAkJQhyCMAA/AgAGAAkJQhyCMAA/AgAAAA==.Halfpink:BAAALgAECgEJAQABLgAECgkJIgAgAD0gAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hammertóe:BAAALgAECgIJBAAAAA==.Hanabi:BAAALgAECgYJBgAAAA==.Hanma:BAACLgAFFH8VAAIZAAcJgRn5IADuAQAZAAcJgRn5IADuAQAuAAQKfygAAhkACQkFHxEsAIgCABkACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn9MAAICAAkJ5hE7DQBYAQACAAkJ5hE7DQBYAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgAECgQJBAAAAA==.Hiroki:BAABLgAECn8zAAIZAAkJdw+nUADRAQAZAAkJdw+nUADRAQAAAA==.Hitachitotem:BAACLgAFFH8pAAIYAAQJARvaDgAdAQAYAAQJARvaDgAdAQAuAAQKfxkAAhgACAmtGl0aAEACABgACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJDwAAAA==.Hiyodad:BAAALgADCgUJBQAAAA==.Hiyodadk:BAAALgAECgIJAgAAAA==.Hiyodal:BAAALgAECgQJBAAAAA==.Hiyodam:BAAALgADCgIJAgAAAA==.Hiyodat:BAAALgAECgYJCgAAAA==.Hiyodaw:BAABLgAECn8UAAIeAAUJLQbJJgB/AAAeAAUJLQbJJgB/AAAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Hollycat:BAAALgAECgkJAwAAAA==.Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAIRAAkJ2hquHwBXAgARAAkJ2hquHwBXAgABLgAFFAEJAQAHAAAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAYJHgASAM4gAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQADACsgAA==.Holyshifts:BAABLgAECn8tAAIGAAkJARw8AwCRAgAGAAkJARw8AwCRAgAAAA==.',
Hu='Huxter:BAAALgADCgEJAQAAAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8lAAICAAkJxhTHQwAQAgACAAkJxhTHQwAQAgAAAA==.',
In='Inflikted:BAABLgAECn8lAAIZAAkJVQgQeQBxAQAZAAkJVQgQeQBxAQAAAA==.Interwebz:BAABLgAECn8eAAMZAAkJHh3pIgB7AgAZAAkJKxzpIgB7AgAbAAIJ9h1LPgCXAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Iz='Izztargaryen:BAAALgADCgEJAQAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgYJCQAHAAAAAA==.Jakarm:BAAALgAECgEJAQAAAA==.Jankook:BAAALgAECgEJAQAAAA==.Jazzarin:BAAALgAECgYJCgAAAA==.',
Je='Jehannum:BAABLgAECn9HAAIYAAkJ4RdRAgAkAgAYAAkJ4RdRAgAkAgAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgYJEQAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8JAAIcAAQJfxocIAAcAQAcAAQJfxocIAAcAQABLgAFFAUJLwAFAO4lAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgAECgYJCgAAAA==.Jurkzarbirt:BAAALgAECgQJBQAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jì']='Jìnbe:BAABLgAECn8sAAIkAAkJbhEBAgC0AQAkAAkJbhEBAgC0AQABLgAECgkJUwATAJweAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIEAAgJ0hekJQCeAQAEAAgJ0hekJQCeAQAAAA==.',
Ka='Kaefaith:BAAALgAECgMJAwAAAA==.Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kaimi:BAAALgAECgkJBgAAAA==.Kainiy:BAAALgAECgUJCQAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAABLgAECn8YAAIGAAcJUgwzFAAKAQAGAAcJUgwzFAAKAQAAAA==.Kaoti:BAAALgAECgUJBQAAAA==.Kassan:BAABLgAECn8tAAQEAAkJXxeqBACAAQAEAAcJMxWqBACAAQADAAkJHwrGBQBUAQAmAAUJHg2ACwDoAAAAAA==.Katarena:BAABLgAECn83AAIcAAgJVRAGMgCOAQAcAAgJVRAGMgCOAQAAAA==.Kathyra:BAECLgAFFH8HAAIBAAQJcAzyfADKAAABAAQJcAzyfADKAAAuAAQKfy0AAwEACQkgFHMLABwBAAEACQkgFHMLABwBACcAAQnvASM3ACcAAAAA.Kavax:BAABLgAECn8mAAIcAAkJhBSNGQA6AgAcAAkJhBSNGQA6AgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIGAAYJlw9ZLQBaAQAGAAYJlw9ZLQBaAQAuAAQKfzwAAgYACQnFHiwiAH0CAAYACQnFHiwiAH0CAAAA.Keellie:BAAALgAECgEJAQAAAA==.Kegbash:BAAALgAECgEJAQABLgAECgkJMAALABceAA==.Keggor:BAAALgAECgEJAgAAAA==.Kelorth:BAAALgADCggJCAAAAA==.Kentyr:BAABLgAECn83AAMOAAgJ8xFLHACzAQAOAAgJ8xFLHACzAQAoAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khaldormu:BAAALgAECggJBwAAAA==.Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAYJHgASAM4gAA==.Kinký:BAACLgAFFH8OAAISAAQJSg1iEwDqAAASAAQJSg1iEwDqAAAuAAQKfy8AAxIACQk0FlcYACsCABIACQk0FlcYACsCABQAAQnbFDd1ADcAAAEuAAQKCAkUABIAChcA.Kiraelis:BAABLgAECn8lAAIiAAkJqg8WDQCPAQAiAAkJqg8WDQCPAQAAAA==.Kisara:BAAALgADCggJDAABLgAFFAMJBQAGAOsNAA==.Kiss:BAAALgADCgEJAQABLgAECgcJGQAFACIXAA==.Kitchner:BAAALgAECgYJCQAAAA==.Kitetsu:BAAALgAECgEJAQAAAA==.Kivea:BAABLgAECn8aAAMCAAkJZg9LZAC1AQACAAkJZg9LZAC1AQAjAAEJBAe/FQAoAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgAECgMJAwAAAA==.Konvik:BAAALgAECgMJAwAAAA==.Kooka:BAAALgADCgMJAwAAAA==.Korvoh:BAABLgAECn9RAAMmAAkJLh83AQDHAgAmAAkJLh83AQDHAgADAAMJUxeOXQC8AAAAAA==.',
Kr='Krincess:BAABLgAECn8sAAIXAAkJaRonAQBvAgAXAAkJaRonAQBvAgABLgAECgkJNAAYAAAkAA==.Kringe:BAABLgAECn80AAMYAAkJACRvBAAcAwAYAAkJACRvBAAcAwAFAAEJLQQO6QAlAAAAAA==.Krinny:BAAALgAECgUJBQABLgAECgkJNAAYAAAkAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumaro:BAAALgAECgMJAwAAAA==.Kumonk:BAABLgAECn8cAAIQAAcJWAbMSwDTAAAQAAcJWAbMSwDTAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBgAAAA==.',
['Kä']='Kämik:BAABLgAECn9LAAIdAAkJrCG3CgAAAwAdAAkJrCG3CgAAAwAAAA==.',
['Kì']='Kìn:BAABLgAECn8qAAMmAAcJUAzDPQAWAQAmAAYJGg7DPQAWAQAEAAYJfAQZGgBLAAAAAA==.',
La='Lampion:BAABLgAECn8hAAILAAkJdAzxIABxAQALAAkJdAzxIABxAQAAAA==.Langris:BAAALgAECgEJAwAAAA==.Lasstchance:BAABLgAECn8eAAIdAAgJvQyyewBIAQAdAAgJvQyyewBIAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8pAAIBAAkJ/h41DwDTAgABAAkJ/h41DwDTAgAAAA==.',
Le='Leijona:BAAALgAECgUJEAAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgAECgYJCgAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Lightbunny:BAAALgAECgMJAwAAAA==.Lightstorms:BAAALgAECggJEQAAAA==.Likeatrain:BAABLgAECn87AAIpAAkJzBZxDQAUAgApAAkJzBZxDQAUAgAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMcAAgJJRN/KADqAQAcAAgJJRN/KADqAQAGAAUJDgjKDQGoAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMcAAkJOh5bFgBYAgAcAAkJOh5bFgBYAgAGAAYJTQzJ6ADTAAAAAA==.Lintha:BAAALgAECggJEwAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littleangel:BAAALgADCgMJAwAAAA==.Littlefoot:BAABLgAECn8UAAMXAAYJKhWDOwA9AQAXAAYJKhWDOwA9AQAWAAEJ3wOVKgAkAAABLgAFFAYJHgASAM4gAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8dAAMOAAgJlBc8GwC9AQAOAAgJlBc8GwC9AQAVAAEJhxD2HwAzAAAAAA==.Lokininja:BAAALgAECgQJBwAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn9XAAIQAAkJkyRqAABCAwAQAAkJkyRqAABCAwAAAA==.',
Lu='Luber:BAECLgAFFH8NAAMFAAMJSA8GKQCWAAAFAAMJSA8GKQCWAAAYAAIJGQJGKwBKAAAuAAQKfz8AAwUACQkJGXMCAIICAAUACQkJGXMCAIICABgABgkLDfpVAOMAAAEuAAUUBAkUABkA5gcA.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAACLgAFFH8SAAIbAAUJdSPxBgCOAQAbAAUJdSPxBgCOAQAuAAQKf1QAAhsACQkwJrQAAGkDABsACQkwJrQAAGkDAAAA.Luxzy:BAACLgAFFH8GAAMdAAMJgAitOgCtAAAdAAMJgAitOgCtAAAiAAEJagGWPAAuAAAuAAQKfyMAAx0ACAnxD/YNAF0BAB0ABwmYEfYNAF0BACIACAnRBxEVABMBAAAA.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Makarich:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Malachron:BAAALgAECgEJAQAAAA==.Manbearcat:BAABLgAECn8iAAIgAAkJPSBwCgAWAwAgAAkJPSBwCgAWAwAAAA==.Marbleous:BAACLgAFFH8KAAISAAMJBiQ8KwAHAQASAAMJBiQ8KwAHAQAuAAQKfxgAAhIABgm6Iz8oALoBABIABgm6Iz8oALoBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcdragon:BAAALgAECgUJBgAAAA==.Mcewan:BAAALgADCgUJBQAAAA==.Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIgAgAD0gAA==.Mcspicy:BAAALgAECgUJCAAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAnAFkfAA==.Mechalomania:BAAALgAECgkJCQABLgAECgkJOgAIAKAQAA==.Melhina:BAAALgAECgUJCQABLgAECgkJQQAnAOkcAA==.Memisstotem:BAABLgAECn8eAAIFAAcJgRrRMgDoAQAFAAcJgRrRMgDoAQAAAA==.Merle:BAACLgAFFH8eAAMSAAYJziCDCABtAQASAAYJ8xuDCABtAQAUAAQJFhfSBgBCAQAuAAQKf1UAAxIACQloJcYCAEUDABIACQk0JMYCAEUDABQABgncJIUOAAMCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8dAAIRAAgJ7Rn7KQAhAgARAAgJ7Rn7KQAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Mikethegray:BAABLgAECn8fAAIYAAkJNRAsBACdAQAYAAkJNRAsBACdAQABLgAECgkJYwAGAN4cAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8eAAIDAAcJmA2DNQAtAQADAAcJmA2DNQAtAQAAAA==.Mistborn:BAABLgAECn84AAQDAAkJiCIhCQC5AgADAAkJiCIhCQC5AgAmAAQJ1RyJKQBMAQAEAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAWAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn9AAAIhAAkJ4SHxAgDvAgAhAAkJ4SHxAgDvAgAAAA==.Monkjamin:BAABLgAFFH8GAAIkAAMJThcKNgDOAAAkAAMJThcKNgDOAAAAAA==.Moolimbo:BAABLgAECn8qAAIYAAkJghi7FgAwAgAYAAkJghi7FgAwAgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAWAKYfAA==.Mooseboy:BAABLgAECn8tAAIhAAkJah70BACpAgAhAAkJah70BACpAgAAAA==.Mooserton:BAACLgAFFH8FAAIcAAMJeBAeMQCvAAAcAAMJeBAeMQCvAAAuAAQKfzYAAxwACQmaHEoIAAcDABwACQmaHEoIAAcDAAYABgmsD8/cAOIAAAAA.Mootalstrike:BAABLgAECn8zAAISAAkJbhVUHwD0AQASAAkJbhVUHwD0AQAAAA==.Moshworm:BAABLgAECn86AAIIAAkJoBD3IgCyAQAIAAkJoBD3IgCyAQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAUJGQAZALUdAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgIJAwAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAcJGQAdAFsWAA==.Myraxes:BAAALgADCgIJAgAAAA==.',
['Mä']='Mängo:BAAALgADCgYJCAAAAA==.',
Na='Nalaxx:BAAALgAECgkJAQAAAA==.Natsumi:BAABLgAECn8WAAIFAAcJxgvbZgAnAQAFAAcJxgvbZgAnAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIXAAYJVQPRQwDRAAAXAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAICAAkJBh4LIwCRAgACAAkJBh4LIwCRAgAAAA==.Neuroticaine:BAABLgAECn9aAAMEAAkJMxwmAgAbAgAEAAkJMxwmAgAbAgAmAAQJVQ4JSwDYAAAAAA==.Nev:BAACLgAFFH8SAAMdAAQJsCGMMABOAQAdAAQJsCGMMABOAQAiAAMJ6AVCGQDAAAAuAAQKfyEAAx0ACAncIsYjAC8CAB0ABwkjIsYjAC8CACIABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8UAAIOAAQJfg0dFADOAAAOAAQJfg0dFADOAAAAAA==.',
Ni='Nico:BAABLgAECn8bAAIJAAkJChIjEQCxAQAJAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQnAAkJWR+gBABRAgAnAAkJUx+gBABRAgAeAAcJIBqjCgCZAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgAECgYJCgAAAA==.Nooblets:BAACLgAFFH8HAAIOAAMJ/xoZKQDiAAAOAAMJ/xoZKQDiAAAuAAQKfxsAAg4ABwnMIGMbALwBAA4ABwnMIGMbALwBAAAA.Nop:BAAALgAECgEJAQAAAA==.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMRAAkJQBLCVACIAQARAAkJQBLCVACIAQAMAAIJwhRuMgA6AAAAAA==.Noxxus:BAABLgAECn8fAAITAAkJvRqdDAD9AQATAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAnAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAAALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAECLgAFFH8UAAIZAAQJ5gfCNADzAAAZAAQJ5gfCNADzAAAuAAQKfyQAAxkACQkqDKVnAJcBABkACQkqDKVnAJcBABsABwlTBr0IALcAAAAA.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAYAIIYAA==.',
Om='Omnivus:BAAALgAECgMJBgAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgMJBgAHAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAcAFAbAA==.Oratherah:BAABLgAFFH8LAAIbAAMJziS0JgC+AAAbAAMJziS0JgC+AAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8rAAISAAkJfCILBwDtAgASAAkJfCILBwDtAgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAABLgAECn8YAAILAAgJLxY7FgDYAQALAAgJLxY7FgDYAQAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn9VAAIaAAkJoQwVAwBCAQAaAAkJoQwVAwBCAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAYAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHgAZAB4dAA==.Pinkrosé:BAAALgAECgcJBwAAAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIgAgAD0gAA==.Pitchblende:BAABLgAECn8xAAIcAAkJMBKAHwAHAgAcAAkJMBKAHwAHAgAAAA==.',
Po='Poeppsul:BAAALgAECgEJAQAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Polyrock:BAAALgADCgQJBAAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAZAOEkAA==.Porthub:BAABLgAECn8pAAICAAkJLAkneACJAQACAAkJLAkneACJAQAAAA==.',
Pr='Prangkim:BAAALgAECgkJBwAAAA==.Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAABLgAECn8YAAMdAAgJKRJBbABpAQAdAAgJKRJBbABpAQAiAAEJAAB3SQAAAAAAAA==.Rajak:BAAALgAECgYJCAAAAA==.Range:BAAALgAFFAIJAgAAAA==.Raph:BAABLgAECn8XAAIgAAYJAxpwNADKAQAgAAYJAxpwNADKAQAAAA==.Rathibrew:BAACLgAFFH8cAAIkAAgJDhx4DADOAQAkAAgJDhx4DADOAQAuAAQKfzgAAiQACQmcJLwBAIwDACQACQmcJLwBAIwDAAAA.',
Re='Reckurface:BAAALgAECgEJAQAAAA==.Redine:BAAALgAECgQJBQAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgcJCgAAAA==.Rellt:BAAALgAECgEJAgAAAA==.Remnants:BAABLgAECn8UAAIkAAYJihvDJwDIAQAkAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8YAAQDAAgJRQe3OQASAQADAAgJRQe3OQASAQAEAAUJEAOrbQBpAAAmAAEJ4gHeigAcAAAAAA==.',
Rh='Rhayge:BAABLgAECn8cAAIKAAkJ0xyIAACqAgAKAAkJ0xyIAACqAgAAAA==.Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgQJCAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAHAAAAAA==.Rompally:BAAALgAECgYJCQAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8ZAAQZAAUJtR0lQwBvAQAZAAUJtR0lQwBvAQAaAAEJUQ3YJwBGAAAbAAEJAAA8WAAAAAAuAAQKfzEAAhkACQnGHywrAFMCABkACQnGHywrAFMCAAAA.',
['Rê']='Rêvolt:BAABLgAFFH8IAAIRAAIJYg4LggB7AAARAAIJYg4LggB7AAAAAA==.Rêzìcå:BAAALgADCgkJCQAAAA==.',
['Rô']='Rôwdy:BAAALgAECgEJAQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAABLgAECn8ZAAMdAAgJ0getfABGAQAdAAgJ0getfABGAQAiAAQJWwF4PAAyAAAAAA==.Salezar:BAABLgAECn8rAAIWAAkJph9jAQDnAgAWAAkJph9jAQDnAgAAAA==.Sandoud:BAABLgAECn8cAAIIAAkJ6xNFGgD5AQAIAAkJ6xNFGgD5AQAAAA==.Sapientia:BAABLgAECn8tAAIGAAkJqwgTjABZAQAGAAkJqwgTjABZAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECgkJSQALABYaAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgAECgEJAgAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIcAAQJcw/iKADdAAAcAAQJcw/iKADdAAAuAAQKfyEAAxwACAlaGMcZAEUCABwACAlaGMcZAEUCAAYAAQnyDycyAT8AAAEuAAUUCQkjAAIAthkA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAMJBAAAAA==.Selenesul:BAABLgAECn8sAAMGAAkJ9RxlHwCLAgAGAAkJ9RxlHwCLAgATAAMJTAynNAB0AAAAAA==.Selyda:BAAALgAECgEJAQAAAA==.Senzie:BAACLgAFFH8cAAIQAAUJjiB6DABgAQAQAAUJjiB6DABgAQAuAAQKfyUAAhAACQkiHlYNAHACABAACQkiHlYNAHACAAEuAAUUBwkTABAA4RAA.Sevro:BAAALgADCgQJBAABLgAECgkJJgAcAIQUAA==.',
Sh='Shadowdrake:BAABLgAECn8hAAIXAAkJ+wswMQByAQAXAAkJ+wswMQByAQAAAA==.Shadowheàrt:BAABLgAECn8nAAMcAAgJ6hWfBACBAQAcAAcJchWfBACBAQAGAAQJOQU8OAF1AAAAAA==.Shadowshifty:BAABLgAECn8nAAIfAAkJLRAxBQA+AQAfAAkJLRAxBQA+AQAAAA==.Shadowtotem:BAAALgAECgYJBgAAAA==.Shaeen:BAABLgAFFH8JAAIMAAMJpRD7CQCxAAAMAAMJpRD7CQCxAAAAAA==.Shagi:BAABLgAECn8qAAIkAAkJJxanFwDrAQAkAAkJJxanFwDrAQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Shanson:BAAALgAECgQJBAAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharklee:BAAALgADCgEJAgAAAA==.Sharroz:BAABLgAECn8dAAMaAAcJiB1oAwBWAgAaAAcJiB1oAwBWAgAbAAQJVQ7wQQCHAAAAAA==.Shauna:BAACLgAFFH8PAAIdAAcJGBVlCQDpAQAdAAcJGBVlCQDpAQAuAAQKfxUAAh0ACAn6DqhOALYBAB0ACAn6DqhOALYBAAAA.Shdw:BAAALgAECgUJCQAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMmAAgJeBpPFwAcAgAmAAgJeBpPFwAcAgAEAAEJJQKaaQAlAAABLgAFFAUJGQAZALUdAA==.Shockybalboa:BAABLgAECn8UAAIYAAcJNBP/NQBiAQAYAAcJNBP/NQBiAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBwAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skoftyia:BAAALgAECgEJAQABLgAFFAMJCgASAIIVAA==.Skooda:BAABLgAECn8tAAIYAAkJaA5AMAB+AQAYAAkJaA5AMAB+AQAAAA==.Skyded:BAABLgAECn8yAAIZAAkJLBn3MAA7AgAZAAkJLBn3MAA7AgAAAA==.Skyfire:BAAALgAECgcJAQAAAA==.Skyknight:BAABLgAECn8iAAISAAkJ/RN0KQCzAQASAAkJ/RN0KQCzAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8RAAMJAAYJ8xJEFAAqAQAJAAYJ8xJEFAAqAQAiAAIJBwsJJwB0AAAuAAQKfzsAAwkACQlyI3kEAOYCAAkACQlQInkEAOYCACIACAnWHuoSAJ8CAAAA.Slaughterman:BAAALgAECgMJBgAAAA==.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgADCgYJCwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8vAAIRAAkJdR5nAgBGAgARAAkJdR5nAgBGAgAAAA==.Solence:BAAALgADCgIJAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAABLgAECn8dAAIGAAgJuR06IwB4AgAGAAgJuR06IwB4AgAAAA==.Soralas:BAAALgAECgcJEgAAAA==.',
Sp='Spaazz:BAABLgAECn8nAAIGAAkJsyGAFADHAgAGAAkJsyGAFADHAgAAAA==.Spanky:BAAALgAECgMJAwAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
St='Staggerstout:BAAALgAECgEJAQAAAA==.Starofdreams:BAAALgAECgQJCAABLgAECgkJMAAmAIoTAA==.Starweaver:BAABLgAECn8wAAMmAAkJihOyKQCHAQAmAAkJWQqyKQCHAQADAAgJ1xQDKwBwAQAAAA==.Stellmarine:BAABLgAECn8dAAIIAAkJzRoSGwDyAQAIAAkJzRoSGwDyAQAAAA==.Stelthest:BAAALgAECgQJBAAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAABLgAECn8YAAIRAAcJxA2yDwDqAAARAAcJxA2yDwDqAAAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMfAAkJIhu3CABhAgAfAAkJ4Rq3CABhAgAIAAYJBBrnKgCqAQAAAA==.',
Su='Sunamé:BAAALgAECgUJCwAAAA==.Sunarianna:BAAALgAECgUJBgAAAA==.',
Sw='Swaazil:BAACLgAFFH8YAAICAAQJcwhhNADbAAACAAQJcwhhNADbAAAuAAQKfyYAAgIACQkrEaBeAMMBAAIACQkrEaBeAMMBAAAA.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgQJBgAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAHAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8fAAIRAAcJIQ1RiAAPAQARAAcJIQ1RiAAPAQAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taken:BAAALgAECgYJBgAAAA==.Taloriesh:BAACLgAFFH8HAAIDAAMJ3x66GAD2AAADAAMJ3x66GAD2AAAuAAQKfysABAMACQmlHmwIAOQCAAMACQmlHmwIAOQCAAQAAQk+FepgADYAACYAAQkdDlJ8AC8AAAAA.Tanazir:BAEBLgAECn8eAAMWAAkJpRCeCQCMAQAWAAgJKhGeCQCMAQAXAAIJ5g+vDgByAAAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarivel:BAAALgAECgIJAgAAAA==.Tarok:BAAALgAECgYJBgAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8ZAAIQAAgJKRA2KwBkAQAQAAgJKRA2KwBkAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIeAAgJnBwLBQAlAgAeAAgJnBwLBQAlAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECgkJHgAWAKUQAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIGAAkJLBlZRQATAgAGAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8XAAIdAAcJKQapmQANAQAdAAcJKQapmQANAQAAAA==.Tilamano:BAACLgAFFH8GAAIBAAIJ1iOGdwDTAAABAAIJ1iOGdwDTAAAuAAQKfzsABB4ACQmlJfgBAK4CAB4ACAnSJPgBAK4CACcACAk6JPgCAJMCAAEACAkyJEMmAEQCAAAA.Tilthulhu:BAAALgAECgMJAwABLgAFFAIJBgABANYjAA==.',
Tl='Tlital:BAAALgAECgEJAQAAAA==.',
Tm='Tmntmikey:BAABLgAFFH8WAAQPAAYJhxNOIABsAQAPAAYJhxNOIABsAQAkAAMJbgHpRACOAAAQAAEJvAfsRgAzAAAAAA==.',
To='Tobirama:BAAALgAFFAIJAgAAAA==.Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMdAAcJRCMZHwBLAgAdAAcJgCIZHwBLAgAiAAYJMSMUIgAVAgABLgAFFAEJAQAHAAAAAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAkAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAkAO8lAA==.Toomey:BAAALgAECgEJAQAAAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAkAO8lAA==.Toopie:BAACLgAFFH8FAAIkAAEJ7yUyTwBlAAAkAAEJ7yUyTwBlAAAuAAQKfx4AAyQACAn7IWULANcCACQACAn7IWULANcCABAABQlvGSQ4AD0BAAAA.Totemwebz:BAAALgAECgUJBQAAAA==.Totoku:BAABLgAECn8XAAIFAAkJJhWNAwA3AgAFAAkJJhWNAwA3AgAAAA==.',
Tr='Trackdown:BAAALgAECgcJBwAAAA==.Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8qAAIgAAkJxBsvEgC8AgAgAAkJxBsvEgC8AgAAAA==.Tryath:BAABLgAECn8ZAAMgAAgJ4wqVcwDaAAAgAAcJcAiVcwDaAAAIAAQJzAmvZwCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
Ty='Tyrethia:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIeAAUJAhUcBwAlAQAeAAUJAhUcBwAlAQAuAAQKfyQAAh4ACQl8G2oCAOUCAB4ACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIJAAkJCh8hAwABAwAJAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAIRAAkJQiBfEwDlAgARAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgkJJAACAAkZAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn8/AAITAAkJoiMnAgAYAwATAAkJoiMnAgAYAwAAAA==.Valros:BAAALgADCgEJAQABLgAECgkJKgAkACcWAA==.Vanaras:BAAALgAECgIJAgAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgUJDwABLgAFFAIJBgAZABgOAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMOAAkJnxYOFQD4AQAOAAkJshUOFQD4AQAVAAUJ8xGAEwDJAAAAAA==.Veraana:BAABLgAECn8gAAIcAAkJnxjSAQBFAgAcAAkJnxjSAQBFAgAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestre:BAAALgAECgQJBQAAAA==.Vestt:BAABLgAECn9lAAIdAAkJXR7sAgCmAgAdAAkJXR7sAgCmAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8iAAQmAAgJfyJJDABZAgAmAAgJfyJJDABZAgAEAAEJphQvOQBIAAADAAEJuwegIAAjAAAuAAQKfywAAyYACQnfJhEAAPkDACYACQnfJhEAAPkDAAQAAQnWIX5xAF8AAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJBAAAAA==.Vidette:BAAALgAECgEJAQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAnAFkfAA==.Viv:BAABLgAECn8qAAMTAAkJLiK8BQCWAgATAAcJPCS8BQCWAgAGAAcJCSJWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8gAAIGAAkJjAallQBJAQAGAAkJjAallQBJAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAABLgAECn8XAAMZAAgJ4wiGpQAjAQAZAAgJ4waGpQAjAQAbAAQJwwp+EQBFAAAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAABLgAECn8ZAAIRAAYJ7ROIkAD/AAARAAYJ7ROIkAD/AAABLgAFFAUJCgAXAKIXAA==.Warrendemon:BAACLgAFFH8aAAIRAAgJCyMEFgABAgARAAgJCyMEFgABAgAuAAQKfzUAAxEACQkDJrsBAMADABEACQkDJrsBAMADAAsAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgkJFwAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAICAAkJWBOvUgA/AgACAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8hAAMhAAkJHyHIBACuAgAhAAkJ1SDIBACuAgAfAAMJ+xQkPgCuAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Woregontail:BAAALgADCggJCAAAAA==.Wowbelly:BAACLgAFFH8IAAIPAAQJggxzNgDPAAAPAAQJggxzNgDPAAAuAAQKfyIAAg8ABwl4HV8FAMsBAA8ABwl4HV8FAMsBAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAAPAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAABLgAECn8XAAMGAAcJsg6EsgAbAQAGAAcJpAuEsgAbAQATAAYJlA6bKADSAAAAAA==.',
Xo='Xonk:BAACLgAFFH8fAAInAAgJuxBAAQB/AQAnAAgJuxBAAQB/AQAuAAQKfyQAAicACQkQICwBAPECACcACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAFFAIJBgAZABgOAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEwAAAA==.',
Yu='Yuuna:BAABLgAECn8YAAIBAAcJrgR+ywC6AAABAAcJrgR+ywC6AAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8YAAMLAAgJdAsYKwAnAQALAAgJdAsYKwAnAQARAAYJ+QID3wB5AAAAAA==.Zapp:BAABLgAECn8dAAIVAAgJlA2dAQBDAQAVAAgJlA2dAQBDAQAAAA==.Zaps:BAABLgAECn8pAAIKAAkJKCMpAgADAwAKAAkJKCMpAgADAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8fAAICAAgJvBReggBzAQACAAgJvBReggBzAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMFAAkJ4QstTgB4AQAFAAkJ4QstTgB4AQAYAAcJxwg5VQDlAAAAAA==.Zenreto:BAABLgAECn9JAAIVAAkJ1yBYAACIAgAVAAkJ1yBYAACIAgAAAA==.Zerani:BAAALgADCgkJEgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.Zergonia:BAAALgADCgYJCQAAAA==.',
Zh='Zhenbao:BAAALgAECgIJAgAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.Zurid:BAAALgAECgYJBgAAAA==.',
Zy='Zyria:BAACLgAFFH8aAAICAAgJjxodLwCwAQACAAgJjxodLwCwAQAuAAQKfysAAgIACAnAJG0SADkDAAIACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8iAAIKAAgJmxvNAAAlAgAKAAgJmxvNAAAlAgAuAAQKfz4AAgoACQlkJhMAAH4DAAoACQlkJhMAAH4DAAAA.',
['Ät']='Äthena:BAABLgAECn8WAAIeAAYJMgceJgCEAAAeAAYJMgceJgCEAAAAAA==.',
['Ër']='Ëroc:BAAALgADCgEJAQAAAA==.',
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
