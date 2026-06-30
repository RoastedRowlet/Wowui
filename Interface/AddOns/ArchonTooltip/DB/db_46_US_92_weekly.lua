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

local lookup = {'Warlock-Demonology','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Warrior-Arms','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Druid-Guardian','Druid-Feral','Mage-Frost','Hunter-Marksmanship','Mage-Fire','Monk-Brewmaster','Mage-Arcane','Priest-Discipline','Druid-Restoration','Warlock-Affliction','Rogue-Outlaw','Warrior-Protection',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abrakådabruh:BAAALgAECgYJEQAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8aAAMCAAcJyhzpJgCOAQACAAUJEBzpJgCOAQADAAcJOBEFLwBkAQABLgAFFAcJEAAEAFgFAA==.',
Ae='Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIFAAkJpiCiFQDBAgAFAAkJpiCiFQDBAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainjel:BAAALgADCgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexdh:BAAALgAECgEJAQAAAA==.Alexr:BAAALgADCgMJAwABLgAECgEJAQAGAAAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.Altaxia:BAAALgAECgYJBgAAAA==.',
Am='Amarantus:BAAALgAECgYJCQABLgAFFAUJFAAHAGMPAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAACLgAFFH8IAAIIAAMJ6hvuBgC9AAAIAAMJ6hvuBgC9AAAuAAQKfxUAAggACAnJEOocALUBAAgACAnJEOocALUBAAEuAAUUBwkcAAkAhRoA.Anmodru:BAAALgAECgYJBgABLgAFFAcJHAAJAIUaAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAIKAAcJxw1rKwBsAQAKAAcJxw1rKwBsAQAAAA==.',
Ap='Apoldelon:BAAALgAECgIJAgAAAA==.',
Aq='Aqulath:BAACLgAFFH8ZAAILAAUJJB9AAwBmAQALAAUJJB9AAwBmAQAuAAQKfx4AAgsACQkzHakEAHACAAsACQkzHakEAHACAAAA.Aquílés:BAAALgAECgQJCQAAAA==.',
Ar='Arazensetal:BAABLgAECn9aAAIMAAkJvCISAACUAwAMAAkJvCISAACUAwAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAcJFAANAIQOAA==.Ardênt:BAAALgAECgEJAQAAAA==.Ariandrel:BAACLgAFFH8FAAIOAAMJvwYDSQCBAAAOAAMJvwYDSQCBAAAuAAQKfx4AAw4ACQkdETEsAM8BAA4ACQkdETEsAM8BAA8AAQlbAE+OABQAAAAA.Aridhol:BAABLgAECn8XAAIQAAgJPQLN4AB1AAAQAAgJPQLN4AB1AAAAAA==.Arkaedius:BAACLgAFFH8HAAIQAAMJQxZFXwDSAAAQAAMJQxZFXwDSAAAuAAQKfyoAAhAACQnIJM8AAIICABAACQnIJM8AAIICAAAA.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJDAABLgAECgYJCQAGAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn9LAAIKAAkJDiRiAAAlAwAKAAkJDiRiAAAlAwAAAA==.Ation:BAAALgAECgEJAgAAAA==.Atulno:BAAALgAECgYJBgAAAA==.',
Au='Aubrii:BAAALgAECgQJBQAAAA==.Aukatsang:BAACLgAFFH8PAAIPAAcJvxyVCACQAQAPAAcJvxyVCACQAQAuAAQKfyoAAg8ACQmTI10BAKMDAA8ACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgAECgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIRAAgJ9xz+FAClAgARAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIPAAQJvRyFEwAhAQAPAAQJvRyFEwAhAQAuAAQKfyQAAg8ACAndHpEJAN8CAA8ACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn9TAAISAAkJnB5PBQCdAgASAAkJnB5PBQCdAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAFAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgkJCQAAAA==.',
Be='Bearhold:BAAALgAECgYJCQAAAA==.Beefy:BAAALgAECgMJBAAAAA==.Beenis:BAAALgAECgQJBQAAAA==.Beersnob:BAABLgAECn8kAAIOAAkJLxZfHgAmAgAOAAkJLxZfHgAmAgAAAA==.Bellamafia:BAAALgAECgEJAQAAAA==.Benjam:BAACLgAFFH8TAAIQAAcJrRZQGgDgAQAQAAcJrRZQGgDgAQAuAAQKfygAAhAABwnlI0wZAL0CABAABwnlI0wZAL0CAAAA.Benyo:BAAALgAECgUJCQAAAA==.',
Bi='Bigmikeyg:BAABLgAECn9VAAIFAAkJghoHAwDkAQAFAAkJghoHAwDkAQAAAA==.Bigsteve:BAABLgAECn9PAAMRAAkJ/CR8BAAdAwARAAkJ9CR8BAAdAwATAAkJQx5aAACWAgAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMUAAMJJwqwCADLAAANAAMJiQWXDwD0AAAUAAMJJwqwCADLAAAuAAQKfxYAAw0ABwlSHPUqAKUBAA0ABwkjHPUqAKUBABQAAwmaGgAAAAAAAAAA.Blinded:BAAALgAECgkJAwAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgARAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgYJCQAGAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Brickley:BAAALgAFFAIJAgABLgAFFAUJGQALACQfAA==.Bronzesun:BAAALgAECgUJCQAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIEAAkJMRpGGQCAAgAEAAkJMRpGGQCAAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
['Bø']='Bønd:BAAALgAECgEJAQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQMAAkJHQX8IgBhAQAMAAkJHQX8IgBhAQAVAAMJGgjIMgCAAAAWAAMJ0AigfwBfAAAAAA==.Calizon:BAAALgAECgkJEgAAAA==.Calogero:BAAALgADCgEJAQAAAA==.Camc:BAAALgAECgQJEQAAAA==.Canowhoopass:BAABLgAECn8mAAIXAAgJvApARQAfAQAXAAgJvApARQAfAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cell:BAAALgAFFAIJAgABLgAFFAYJFAAYAHAeAA==.Cerassin:BAACLgAFFH8wAAIQAAcJ6xjWCACGAQAQAAcJ6xjWCACGAQAuAAQKfzYAAhAACQkJIf8KAPACABAACQkJIf8KAPACAAAA.Cereas:BAABLgAECn9EAAIKAAkJ5RkFEQAZAgAKAAkJ5RkFEQAZAgAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chevota:BAAALgAECgYJBgABLgAFFAQJBgABAN0IAA==.Chichobelo:BAABLgAFFH8VAAQYAAgJYhZxIQDrAQAYAAYJxxhxIQDrAQAZAAUJNRCgAgA9AQAaAAEJAACTGwAAAAAAAA==.Chuckrutis:BAACLgAFFH8FAAIWAAQJGw81NQDuAAAWAAQJGw81NQDuAAAuAAQKfyEAAxUACAlIHXAMABQCABUABglSHnAMABQCABYABQl4HHErAJEBAAAA.',
Cl='Cliché:BAABLgAECn8jAAMbAAgJPRSRIgDwAQAbAAgJPRSRIgDwAQAFAAYJMge56wDQAAAAAA==.Cloberintime:BAAALgAECgEJAQAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8YAAIcAAYJhBkZPgAxAQAcAAYJhBkZPgAxAQAuAAQKfyoAAhwACQk6IXYCAHEDABwACQk6IXYCAHEDAAAA.',
Co='Combination:BAABLgAECn9VAAIdAAkJqyLzAAAFAwAdAAkJqyLzAAAFAwABLgAFFAgJLgAFAN0ZAA==.Constrace:BAAALgAECgYJCAAAAA==.Corvenall:BAABLgAECn86AAIVAAkJlA7VCACgAQAVAAkJlA7VCACgAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAABLgAECn8UAAIRAAgJIgYjTQASAQARAAgJIgYjTQASAQAAAA==.Crossbow:BAACLgAFFH8KAAIcAAMJJRbFWgDvAAAcAAMJJRbFWgDvAAAuAAQKf0MAAhwACQkoIBsPAMICABwACQkoIBsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAUJGQALACQfAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJDAABLgAECgkJRAAKAOUZAA==.',
['Cõ']='Cõnker:BAAALgAFFAEJAQAAAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Danglyudders:BAABLgAECn8WAAIeAAYJERhcAwAFAQAeAAYJERhcAwAFAQAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAIAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Davinah:BAAALgAECgEJAQAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.Dayje:BAAALgAECgIJAgAAAA==.',
De='Deathbcmesyu:BAABLgAECn8iAAIYAAkJLBtsKwBSAgAYAAkJLBtsKwBSAgAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgkJDAABLgAECgkJIQAfAB8hAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwADANoNAA==.Deondre:BAAALgAECgQJCQAAAA==.Detin:BAAALgAECgEJAQAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJIQAfAB8hAA==.',
Di='Diehappy:BAABLgAECn8ZAAMZAAcJAQsdHADuAAAZAAYJzQwdHADuAAAaAAYJ/AX6PQCYAAAAAA==.Dillie:BAAALgAECgUJCQAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAcJGwALAOgjAA==.Dompal:BAABLgAFFH8FAAIFAAMJNx+tGwC+AAAFAAMJNx+tGwC+AAABLgAFFAcJGwALAOgjAA==.Donkystyle:BAAALgAECgQJCAAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJTAAgAIUmAA==.Drovinos:BAAALgAECgYJBgAAAA==.Drualia:BAAALgAECgIJAgAAAA==.Druken:BAABLgAECn8XAAIcAAgJFQr1BgBYAQAcAAgJFQr1BgBYAQAAAA==.Drybonez:BAABLgAECn8UAAIgAAYJ0Aha+AAKAQAgAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8WAAMcAAcJPyAeKwBdAQAcAAYJVR8eKwBdAQAhAAIJSR/hKABnAAAuAAQKfyMAAyEACQm3JNIJAAYDACEACAmdItIJAAYDABwAAwlvIxyeAAUBAAAA.Dràgonkíng:BAABLgAECn8gAAMiAAkJLQd8CAAIAQAiAAkJLQd8CAAIAQAgAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAIRAAkJWRwCFABRAgARAAkJWRwCFABRAgABLgAFFAUJFQAYALUdAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIDAAgJ2g1qMQBWAQADAAgJ2g1qMQBWAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgYJCQAAAA==.',
['Dà']='Dànger:BAAALgADCgEJAQAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAVAKYfAA==.',
Eg='Ego:BAABLgAECn83AAIRAAkJMiSlBwDkAgARAAkJMiSlBwDkAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elijahtheone:BAAALgAECgMJAwAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAgAHciAA==.Emmone:BAAALgAECgYJEQAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.Emorexx:BAAALgAECgYJCQAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAjAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAABLgAECn8cAAIdAAcJ0xdcAQBEAQAdAAcJ0xdcAQBEAQAAAA==.Excaleon:BAAALgAECgYJCwAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAFFAIJAgAAAA==.Faunna:BAACLgAFFH8UAAIHAAUJYw9ELADbAAAHAAUJYw9ELADbAAAuAAQKfz4AAgcACQmEIJwHAN0CAAcACQmEIJwHAN0CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgUJBgAAAA==.Felaz:BAABLgAECn82AAIkAAkJJCADAQDFAgAkAAkJJCADAQDFAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAABLgAECn8dAAIgAAcJWBUABQCLAQAgAAcJWBUABQCLAQAAAA==.Ferreil:BAAALgAECgEJAQAAAA==.Festy:BAAALgAECgEJAQAAAA==.',
Fi='Fingerguns:BAACLgAFFH8RAAIlAAQJaQiQCwDXAAAlAAQJaQiQCwDXAAAuAAQKfx0ABCUACQndFSsTAEgCACUACQndFSsTAEgCAAIAAwl3CO5mAJEAAAMAAwkJCChzAFsAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAUPgAA5AQABAAkJDQUPgAA5AQAdAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBwAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgAECgUJCQAAAA==.Floortank:BAABLgAECn80AAMZAAkJbwvREQBbAQAZAAgJ2wvREQBbAQAYAAgJAQYgpQAkAQAAAA==.',
Fo='Fonn:BAAALgAECgEJAQAAAA==.Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIbAAMJUBsJKwDSAAAbAAMJUBsJKwDSAAAuAAQKfxsAAhsABwnKI4sRAIcCABsABwnKI4sRAIcCAAAA.Friday:BAAALgAECgEJAQAAAA==.Frikilatar:BAAALgAECgEJCQAAAA==.Frostyhatesu:BAAALgADCgMJAwABLgAECgIJAwAGAAAAAA==.Frrank:BAACLgAFFH8bAAITAAcJmiMHBwDuAQATAAcJmiMHBwDuAQAuAAQKfzQAAhMACQkoJWEAALQDABMACQkoJWEAALQDAAAA.Frugalgunny:BAAALgADCgUJBQAAAA==.',
Fu='Fullerene:BAAALgAECgEJAwAAAA==.Funnelcake:BAAALgAECgYJBgAAAA==.',
Ga='Galcain:BAACLgAFFH8PAAMcAAUJfiCnIgB6AQAcAAUJfiCnIgB6AQAIAAQJSRD1BwCoAAAuAAQKfy8ABBwACQnwIfYHABEDABwACAm2IvYHABEDAAgACAl9FogYANwBACEAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAUJDwAcAH4gAA==.Gantz:BAAALgAECgcJDAAAAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAGAAAAAA==.',
Gi='Gintoko:BAAALgAECgMJBgAAAA==.Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8tAAIgAAkJ/BXAQgATAgAgAAkJ/BXAQgATAgAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Grimseek:BAACLgAFFH8FAAIhAAQJfxI9FAAnAQAhAAQJfxI9FAAnAQAuAAQKfx0AAiEABwlpIkgAAGUCACEABwlpIkgAAGUCAAEuAAUUCAkuAAUA3RkA.Gripmepapi:BAABLgAFFH8YAAIYAAQJaBUUHAD6AAAYAAQJaBUUHAD6AAAAAA==.Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgAECgEJAQAAAA==.Grumandel:BAABLgAECn9TAAIfAAkJaiCCAAAKAgAfAAkJaiCCAAAKAgAAAA==.',
Gu='Guce:BAAALgAECgcJDgAAAA==.Gudetama:BAABLgAECn8bAAMcAAkJsCDBFwB7AgAcAAYJESPBFwB7AgAIAAcJwx16DwA3AgAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgAECgQJBAAAAA==.Hakur:BAABLgAECn88AAIFAAkJQhyCMAA/AgAFAAkJQhyCMAA/AgAAAA==.Halfpink:BAAALgAECgEJAQABLgAECgkJIgAmAD0gAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hammertóe:BAAALgAECgIJAwAAAA==.Hanabi:BAAALgAECgYJBgAAAA==.Hanma:BAACLgAFFH8VAAIYAAcJgRn5IADuAQAYAAcJgRn5IADuAQAuAAQKfygAAhgACQkFHxEsAIgCABgACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn9MAAIgAAkJ5hH3BQBoAQAgAAkJ5hH3BQBoAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgAECgEJAQAAAA==.Hiroki:BAABLgAECn8zAAIYAAkJeA+nUADRAQAYAAkJeA+nUADRAQAAAA==.Hitachitotem:BAACLgAFFH8kAAIXAAQJARtjCAAMAQAXAAQJARtjCAAMAQAuAAQKfxkAAhcACAmtGl0aAEACABcACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJDwAAAA==.Hiyodad:BAAALgADCgUJBQAAAA==.Hiyodadk:BAAALgAECgIJAgAAAA==.Hiyodal:BAAALgAECgQJBAAAAA==.Hiyodam:BAAALgADCgIJAgAAAA==.Hiyodat:BAAALgAECgYJCgAAAA==.Hiyodaw:BAABLgAECn8UAAIdAAUJLQbJJgB/AAAdAAUJLQbJJgB/AAAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Hollycat:BAAALgAECgkJAwAAAA==.Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAIQAAkJ2hquHwBXAgAQAAkJ2hquHwBXAgABLgAFFAEJAQAGAAAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAUJFgARAAMiAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQACACsgAA==.Holyshifts:BAABLgAECn8dAAIFAAcJghWzBACJAQAFAAcJghWzBACJAQAAAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8lAAIgAAkJxhTHQwAQAgAgAAkJxhTHQwAQAgAAAA==.',
In='Inflikted:BAABLgAECn8lAAIYAAkJVQgQeQBxAQAYAAkJVQgQeQBxAQAAAA==.Interwebz:BAABLgAECn8dAAMYAAkJHh3pIgB7AgAYAAkJKxzpIgB7AgAaAAIJ9h1LPgCXAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Iz='Izztargaryen:BAAALgADCgEJAQAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgYJCQAGAAAAAA==.Jankook:BAAALgAECgEJAQAAAA==.Jazzarin:BAAALgAECgYJCgAAAA==.',
Je='Jehannum:BAABLgAECn8+AAIXAAkJmhZpAQDkAQAXAAkJmhZpAQDkAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgYJEQAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8IAAIbAAQJfxocIAAcAQAbAAQJfxocIAAcAQABLgAFFAUJLAAEALMlAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgAECgUJCQAAAA==.Jurkzarbirt:BAAALgAECgQJBQAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jì']='Jìnbe:BAABLgAECn8cAAIjAAcJ7Q7xAQAuAQAjAAcJ7Q7xAQAuAQAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIDAAgJ0hekJQCeAQADAAgJ0hekJQCeAQAAAA==.',
Ka='Kaefaith:BAAALgAECgMJAwAAAA==.Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kainiy:BAAALgAECgMJBQAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgYJEQAAAA==.Kassan:BAABLgAECn8dAAQCAAcJYwgeBAADAQACAAcJYwgeBAADAQADAAYJ6A3EBQDIAAAlAAEJfgIciQAhAAAAAA==.Katarena:BAABLgAECn83AAIbAAgJVRAGMgCOAQAbAAgJVRAGMgCOAQAAAA==.Kathyra:BAACLgAFFH8GAAIBAAQJ3QjyfADKAAABAAQJ3QjyfADKAAAuAAQKfygAAwEACQn5Dv1OAK4BAAEACQn5Dv1OAK4BACcAAQnvASM3ACcAAAAA.Kavax:BAABLgAECn8mAAIbAAkJhBSNGQA6AgAbAAkJhBSNGQA6AgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIFAAYJlw9ZLQBaAQAFAAYJlw9ZLQBaAQAuAAQKfzwAAgUACQnFHiwiAH0CAAUACQnFHiwiAH0CAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kelorth:BAAALgADCggJCAAAAA==.Kentyr:BAABLgAECn83AAMNAAgJ8xFLHACzAQANAAgJ8xFLHACzAQAoAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khaldormu:BAAALgAECggJBwAAAA==.Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAUJFgARAAMiAA==.Kinký:BAACLgAFFH8HAAIRAAQJYwxeKAAUAQARAAQJYwxeKAAUAQAuAAQKfy8AAxEACQk0FlcYACsCABEACQk0FlcYACsCABMAAQnbFDd1ADcAAAEuAAQKBwkTAAYAAAAA.Kiraelis:BAABLgAECn8lAAIhAAkJqg8WDQCPAQAhAAkJqg8WDQCPAQAAAA==.Kisara:BAAALgADCggJDAABLgAFFAMJBQAFAOsNAA==.Kiss:BAAALgADCgEJAQABLgAFFAEJAQAGAAAAAA==.Kivea:BAABLgAECn8aAAMgAAkJZg9LZAC1AQAgAAkJZg9LZAC1AQAiAAEJBAe/FQAoAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Konvik:BAAALgAECgEJAQAAAA==.Kooka:BAAALgADCgMJAwAAAA==.Korvoh:BAABLgAECn9RAAMlAAkJLB+JAAC8AgAlAAkJLB+JAAC8AgACAAMJUxeOXQC8AAAAAA==.',
Kr='Krincess:BAABLgAECn8gAAIWAAkJehqWAAB3AgAWAAkJehqWAAB3AgABLgAECgkJNAAXAAAkAA==.Kringe:BAABLgAECn80AAMXAAkJACRvBAAcAwAXAAkJACRvBAAcAwAEAAEJLQQO6QAlAAAAAA==.Krinny:BAAALgAECgUJBQABLgAECgkJNAAXAAAkAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumaro:BAAALgAECgMJAwAAAA==.Kumonk:BAABLgAECn8cAAIPAAcJWAbMSwDTAAAPAAcJWAbMSwDTAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBgAAAA==.',
['Kä']='Kämik:BAABLgAECn9LAAIcAAkJrCG3CgAAAwAcAAkJrCG3CgAAAwAAAA==.',
['Kì']='Kìn:BAABLgAECn8pAAMlAAcJ8wrDPQAWAQAlAAYJggzDPQAWAQADAAYJfASxDABUAAAAAA==.',
La='Lampion:BAABLgAECn8hAAIKAAkJdAzxIABxAQAKAAkJdAzxIABxAQAAAA==.Langris:BAAALgAECgEJAwAAAA==.Lasstchance:BAABLgAECn8aAAIcAAcJQQ2yewBIAQAcAAcJQQ2yewBIAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8pAAIBAAkJ/h41DwDTAgABAAkJ/h41DwDTAgAAAA==.',
Le='Leijona:BAAALgAECgMJBwAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgAECgUJCQAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Lightbunny:BAAALgAECgMJAwAAAA==.Lightstorms:BAAALgAECgcJCAAAAA==.Likeatrain:BAABLgAECn86AAIpAAkJrBZxDQAUAgApAAkJrBZxDQAUAgAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMbAAgJJRN/KADqAQAbAAgJJRN/KADqAQAFAAUJDgjKDQGoAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMbAAkJOh5bFgBYAgAbAAkJOh5bFgBYAgAFAAYJTQzJ6ADTAAAAAA==.Lintha:BAAALgAECggJEgAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAABLgAECn8UAAMWAAYJKhWDOwA9AQAWAAYJKhWDOwA9AQAVAAEJ3wOVKgAkAAABLgAFFAUJFgARAAMiAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8bAAMNAAgJlBc8GwC9AQANAAgJlBc8GwC9AQAUAAEJhxD2HwAzAAAAAA==.Lokininja:BAAALgAECgEJAQAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn9MAAIPAAkJkyRAAAAxAwAPAAkJkyRAAAAxAwAAAA==.',
Lu='Luber:BAABLgAECn80AAMEAAkJ7wwvQwChAQAEAAkJ7wwvQwChAQAXAAYJCw1lCQB9AAAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAACLgAFFH8MAAIaAAMJJCWqBQAvAQAaAAMJJCWqBQAvAQAuAAQKf1IAAhoACQkiJrQAAGkDABoACQkiJrQAAGkDAAAA.Luxzy:BAABLgAECn8fAAMcAAgJ8Q8cBgBxAQAcAAcJmBEcBgBxAQAhAAgJ0QcRFQATAQAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgAECgEJAQAAAA==.Manbearcat:BAABLgAECn8iAAImAAkJPSBwCgAWAwAmAAkJPSBwCgAWAwAAAA==.Marbleous:BAACLgAFFH8KAAIRAAMJBiQ8KwAHAQARAAMJBiQ8KwAHAQAuAAQKfxgAAhEABgm6Iz8oALoBABEABgm6Iz8oALoBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIgAmAD0gAA==.Mcspicy:BAAALgAECgUJCAAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAnAFkfAA==.Mechalomania:BAAALgAECgkJCQABLgAECgkJOgAHAKAQAA==.Melhina:BAAALgAECgUJCQABLgAECgkJPAAnAGwcAA==.Memisstotem:BAABLgAECn8eAAIEAAcJgRrRMgDoAQAEAAcJgRrRMgDoAQAAAA==.Merle:BAACLgAFFH8WAAIRAAUJAyJ7BABbAQARAAUJAyJ7BABbAQAuAAQKf1QAAxEACQlUJcYCAEUDABEACQkgJMYCAEUDABMABgncJIUOAAMCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8dAAIQAAgJ7Rn7KQAhAgAQAAgJ7Rn7KQAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Mikethegray:BAABLgAECn8dAAIXAAcJwxN/AgBuAQAXAAcJwxN/AgBuAQABLgAECgkJVQAFAIIaAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8eAAICAAcJmA2DNQAtAQACAAcJmA2DNQAtAQAAAA==.Mistborn:BAABLgAECn84AAQCAAkJiCIhCQC5AgACAAkJiCIhCQC5AgAlAAQJ1RyJKQBMAQADAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAVAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn87AAIfAAkJZCDxAgDvAgAfAAkJZCDxAgDvAgAAAA==.Monkjamin:BAABLgAFFH8GAAIjAAMJThcKNgDOAAAjAAMJThcKNgDOAAAAAA==.Moolimbo:BAABLgAECn8qAAIXAAkJghi7FgAwAgAXAAkJghi7FgAwAgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAVAKYfAA==.Mooseboy:BAABLgAECn8tAAIfAAkJah70BACpAgAfAAkJah70BACpAgAAAA==.Mooserton:BAACLgAFFH8FAAIbAAMJeBAeMQCvAAAbAAMJeBAeMQCvAAAuAAQKfzYAAxsACQmaHEoIAAcDABsACQmaHEoIAAcDAAUABgmsD8/cAOIAAAAA.Mootalstrike:BAABLgAECn8zAAIRAAkJbhVUHwD0AQARAAkJbhVUHwD0AQAAAA==.Moshworm:BAABLgAECn86AAIHAAkJoBD3IgCyAQAHAAkJoBD3IgCyAQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAUJFQAYALUdAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAYJGAAcAIQZAA==.',
['Mä']='Mängo:BAAALgADCgYJBgAAAA==.',
Na='Nalaxx:BAAALgAECgkJAQAAAA==.Natsumi:BAABLgAECn8WAAIEAAcJxgvbZgAnAQAEAAcJxgvbZgAnAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIWAAYJVQPRQwDRAAAWAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAIgAAkJBh4LIwCRAgAgAAkJBh4LIwCRAgAAAA==.Neuroticaine:BAABLgAECn9aAAMDAAkJNxzUAAAsAgADAAkJNxzUAAAsAgAlAAQJVQ4JSwDYAAAAAA==.Nev:BAACLgAFFH8SAAMcAAQJsCGMMABOAQAcAAQJsCGMMABOAQAhAAMJ6AVCGQDAAAAuAAQKfyEAAxwACAncIsYjAC8CABwABwkjIsYjAC8CACEABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8QAAINAAQJzAtdIAAiAQANAAQJzAtdIAAiAQAAAA==.',
Ni='Nico:BAABLgAECn8bAAIIAAkJChIjEQCxAQAIAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQnAAkJWR+gBABRAgAnAAkJUx+gBABRAgAdAAcJIBqjCgCZAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgAECgUJCQAAAA==.Nooblets:BAACLgAFFH8HAAINAAMJ/xoZKQDiAAANAAMJ/xoZKQDiAAAuAAQKfxsAAg0ABwnMIGMbALwBAA0ABwnMIGMbALwBAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMQAAkJQBLCVACIAQAQAAkJQBLCVACIAQALAAIJwhRuMgA6AAAAAA==.Noxxus:BAABLgAECn8fAAISAAkJvRqdDAD9AQASAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAnAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAAALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAACLgAFFH8PAAIYAAQJVAe5HAD2AAAYAAQJVAe5HAD2AAAuAAQKfx0AAxgACQkqDKVnAJcBABgACQkqDKVnAJcBABoAAQn0AfNmABwAAAAA.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAXAIIYAA==.',
Om='Omnivus:BAAALgAECgMJBgAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgEJAwAGAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAbAFAbAA==.Oratherah:BAABLgAFFH8LAAIaAAMJziS0JgC+AAAaAAMJziS0JgC+AAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8mAAIRAAkJPiILBwDtAgARAAkJPiILBwDtAgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAABLgAECn8YAAIKAAgJLxY7FgDYAQAKAAgJLxY7FgDYAQAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn9VAAIZAAkJoQxDAQA+AQAZAAkJoQxDAQA+AQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAXAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHQAYAB4dAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIgAmAD0gAA==.Pitchblende:BAABLgAECn8xAAIbAAkJMBKAHwAHAgAbAAkJMBKAHwAHAgAAAA==.',
Po='Poeppsul:BAAALgAECgEJAQAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Polyrock:BAAALgADCgQJBAAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAYAOEkAA==.Porthub:BAABLgAECn8pAAIgAAkJLAkneACJAQAgAAkJLAkneACJAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAABLgAECn8WAAMcAAcJhBFBbABpAQAcAAcJhBFBbABpAQAhAAEJAAB3SQAAAAAAAA==.Rajak:BAAALgAECgYJCAAAAA==.Range:BAAALgAFFAIJAgAAAA==.Raph:BAABLgAECn8XAAImAAYJAxqvAwAhAQAmAAYJAxqvAwAhAQAAAA==.Rathibrew:BAACLgAFFH8bAAIjAAcJzh14DADOAQAjAAcJzh14DADOAQAuAAQKfzgAAiMACQmcJLwBAIwDACMACQmcJLwBAIwDAAAA.',
Re='Reckurface:BAAALgAECgEJAQAAAA==.Redine:BAAALgAECgQJBAAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgcJCgAAAA==.Rellt:BAAALgADCgQJBgAAAA==.Remnants:BAABLgAECn8UAAIjAAYJihvDJwDIAQAjAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8YAAQCAAgJRQe3OQASAQACAAgJRQe3OQASAQADAAUJEAOrbQBpAAAlAAEJ4gHeigAcAAAAAA==.',
Rh='Rhayge:BAAALgAECgcJDAAAAA==.Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgQJCAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAGAAAAAA==.Rompally:BAAALgAECgYJCQAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8VAAQYAAUJtR0lQwBvAQAYAAUJtR0lQwBvAQAZAAEJUQ3YJwBGAAAaAAEJAAA8WAAAAAAuAAQKfzEAAhgACQnGHywrAFMCABgACQnGHywrAFMCAAAA.',
['Rê']='Rêvolt:BAABLgAFFH8IAAIQAAIJYg4LggB7AAAQAAIJYg4LggB7AAAAAA==.Rêzìcå:BAAALgADCgkJCQAAAA==.',
['Rô']='Rôwdy:BAAALgAECgEJAQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAABLgAECn8ZAAMcAAgJ0getfABGAQAcAAgJ0getfABGAQAhAAQJWwF4PAAyAAAAAA==.Salezar:BAABLgAECn8rAAIVAAkJph9jAQDnAgAVAAkJph9jAQDnAgAAAA==.Sandoud:BAABLgAECn8cAAIHAAkJ6xNFGgD5AQAHAAkJ6xNFGgD5AQAAAA==.Sapientia:BAABLgAECn8tAAIFAAkJqwgTjABZAQAFAAkJqwgTjABZAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECgkJRAAKAOUZAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgAECgEJAgAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIbAAQJcw/iKADdAAAbAAQJcw/iKADdAAAuAAQKfyEAAxsACAlaGMcZAEUCABsACAlaGMcZAEUCAAUAAQnyDycyAT8AAAEuAAUUCAkhACAAThoA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAMJAgAAAA==.Selenesul:BAABLgAECn8sAAMFAAkJ9RxlHwCLAgAFAAkJ9RxlHwCLAgASAAMJTAynNAB0AAAAAA==.Selyda:BAAALgAECgEJAQAAAA==.Senzie:BAACLgAFFH8ZAAIPAAUJex96DABgAQAPAAUJex96DABgAQAuAAQKfyUAAg8ACQkiHlYNAHACAA8ACQkiHlYNAHACAAEuAAUUBgkRAA8AuBIA.Sevro:BAAALgADCgQJBAABLgAECgkJJgAbAIQUAA==.',
Sh='Shadowdrake:BAABLgAECn8hAAIWAAkJBwz7AwDdAAAWAAkJBwz7AwDdAAAAAA==.Shadowheàrt:BAABLgAECn8mAAMbAAcJkBexAgBjAQAbAAYJSxexAgBjAQAFAAQJOQU8OAF1AAAAAA==.Shadowshifty:BAABLgAECn8mAAIeAAgJFQ97AwD9AAAeAAgJFQ97AwD9AAAAAA==.Shadowtotem:BAAALgAECgYJBgAAAA==.Shaeen:BAABLgAFFH8JAAILAAMJpRD7CQCxAAALAAMJpRD7CQCxAAAAAA==.Shagi:BAABLgAECn8qAAIjAAkJIhanFwDrAQAjAAkJIhanFwDrAQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Shanson:BAAALgAECgQJBAAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharklee:BAAALgADCgEJAgAAAA==.Sharroz:BAABLgAECn8dAAMZAAcJiB1oAwBWAgAZAAcJiB1oAwBWAgAaAAQJVQ7wQQCHAAAAAA==.Shauna:BAACLgAFFH8PAAIcAAcJYhW9AgAUAgAcAAcJYhW9AgAUAgAuAAQKfxUAAhwACAn6DqhOALYBABwACAn6DqhOALYBAAAA.Shdw:BAAALgAECgUJCQAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMlAAgJeBpPFwAcAgAlAAgJeBpPFwAcAgADAAEJJQKaaQAlAAABLgAFFAUJFQAYALUdAA==.Shockybalboa:BAABLgAECn8UAAIXAAcJNBP/NQBiAQAXAAcJNBP/NQBiAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBwAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skoftyia:BAAALgAECgEJAQABLgAFFAMJCgARAIIVAA==.Skooda:BAABLgAECn8tAAIXAAkJaA5AMAB+AQAXAAkJaA5AMAB+AQAAAA==.Skyded:BAABLgAECn8yAAIYAAkJLBn3MAA7AgAYAAkJLBn3MAA7AgAAAA==.Skyfire:BAAALgAECgYJAQAAAA==.Skyknight:BAABLgAECn8hAAIRAAkJnBN0KQCzAQARAAkJnBN0KQCzAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8PAAMIAAYJ8xJEFAAqAQAIAAYJ8xJEFAAqAQAhAAIJBwsJJwB0AAAuAAQKfzsAAwgACQlyI3kEAOYCAAgACQlQInkEAOYCACEACAnWHuoSAJ8CAAAA.Slaughterman:BAAALgAECgEJAgAAAA==.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgADCgYJCwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8vAAIQAAkJdR4EAQBZAgAQAAkJdR4EAQBZAgAAAA==.Solence:BAAALgADCgIJAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAABLgAECn8cAAIFAAgJuR06IwB4AgAFAAgJuR06IwB4AgAAAA==.Soralas:BAAALgAECgcJEgAAAA==.',
Sp='Spaazz:BAABLgAECn8jAAIFAAkJsyGAFADHAgAFAAkJsyGAFADHAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
St='Staggerstout:BAAALgAECgEJAQAAAA==.Starofdreams:BAAALgAECgQJCAABLgAECgkJLAAlACgTAA==.Starweaver:BAABLgAECn8sAAMlAAkJKBOyKQCHAQAlAAkJ0QmyKQCHAQACAAgJJhMDKwBwAQAAAA==.Stellmarine:BAABLgAECn8dAAIHAAkJzRoSGwDyAQAHAAkJzRoSGwDyAQAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgcJEQAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMeAAkJIhu3CABhAgAeAAkJ4Rq3CABhAgAHAAYJBBrnKgCqAQAAAA==.',
Su='Sunamé:BAAALgAECgUJCwAAAA==.Sunarianna:BAAALgAECgIJAgAAAA==.',
Sw='Swaazil:BAACLgAFFH8YAAIgAAQJcwj7HADqAAAgAAQJcwj7HADqAAAuAAQKfyYAAiAACQkrEaBeAMMBACAACQkrEaBeAMMBAAAA.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgQJBQAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAGAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8fAAIQAAcJIQ1RiAAPAQAQAAcJIQ1RiAAPAQAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taken:BAAALgAECgYJBgAAAA==.Taloriesh:BAACLgAFFH8HAAICAAMJ3x66GAD2AAACAAMJ3x66GAD2AAAuAAQKfysABAIACQmlHmwIAOQCAAIACQmlHmwIAOQCAAMAAQk+FepgADYAACUAAQkdDlJ8AC8AAAAA.Tanazir:BAEBLgAECn8eAAMVAAkJpRCeCQCMAQAVAAgJKhGeCQCMAQAWAAIJ5g+hBwB2AAAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarivel:BAAALgAECgIJAgAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8ZAAIPAAgJKRA2KwBkAQAPAAgJKRA2KwBkAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIdAAgJnBwLBQAlAgAdAAgJnBwLBQAlAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECgkJHgAVAKUQAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIFAAkJLBlZRQATAgAFAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8XAAIcAAcJKQapmQANAQAcAAcJKQapmQANAQAAAA==.Tilamano:BAACLgAFFH8GAAIBAAIJ1iOGdwDTAAABAAIJ1iOGdwDTAAAuAAQKfzsABB0ACQmlJfgBAK4CAB0ACAnSJPgBAK4CACcACAk6JPgCAJMCAAEACAkyJEMmAEQCAAAA.Tilthulhu:BAAALgAECgMJAwABLgAFFAIJBgABANYjAA==.',
Tm='Tmntmikey:BAABLgAFFH8WAAQOAAYJhxMJCgA8AQAOAAYJhxMJCgA8AQAjAAMJbgHpRACOAAAPAAEJvAfsRgAzAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMcAAcJRCMZHwBLAgAcAAcJgCIZHwBLAgAhAAYJMSMUIgAVAgABLgAFFAEJAQAGAAAAAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAjAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAjAO8lAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAjAO8lAA==.Toopie:BAACLgAFFH8FAAIjAAEJ7yUyTwBlAAAjAAEJ7yUyTwBlAAAuAAQKfx4AAyMACAn7IWULANcCACMACAn7IWULANcCAA8ABQlvGSQ4AD0BAAAA.Totoku:BAAALgAECgcJDAAAAA==.',
Tr='Trackdown:BAAALgAECgcJBwAAAA==.Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8qAAImAAkJxBsvEgC8AgAmAAkJxBsvEgC8AgAAAA==.Tryath:BAABLgAECn8ZAAMmAAgJ4wqVcwDaAAAmAAcJcAiVcwDaAAAHAAQJzAmvZwCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
Ty='Tyrethia:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIdAAUJAhUcBwAlAQAdAAUJAhUcBwAlAQAuAAQKfyQAAh0ACQl8G2oCAOUCAB0ACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIIAAkJCh8hAwABAwAIAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAIQAAkJQiBfEwDlAgAQAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgcJHAAgAPsVAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn8/AAISAAkJoiMnAgAYAwASAAkJoiMnAgAYAwAAAA==.Valros:BAAALgADCgEJAQABLgAECgkJKgAjACIWAA==.Vanaras:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgUJDwABLgAECgkJIgAYACwbAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMNAAkJnxYOFQD4AQANAAkJshUOFQD4AQAUAAUJ8xGAEwDJAAAAAA==.Veraana:BAABLgAECn8WAAIbAAYJGRqcAgBtAQAbAAYJGRqcAgBtAQAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn9VAAIcAAkJvR1jAQCiAgAcAAkJvR1jAQCiAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8fAAQlAAcJoiRJDABZAgAlAAcJoiRJDABZAgADAAEJphQvOQBIAAACAAEJuwddFAAnAAAuAAQKfywAAyUACQnfJhEAAPkDACUACQnfJhEAAPkDAAMAAQnWIX5xAF8AAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJBAAAAA==.Vidette:BAAALgAECgEJAQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAnAFkfAA==.Viv:BAABLgAECn8qAAMSAAkJLiK8BQCWAgASAAcJPCS8BQCWAgAFAAcJCSJWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8gAAIFAAkJjAallQBJAQAFAAkJjAallQBJAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAABLgAECn8WAAMYAAgJzAeGpQAjAQAYAAgJ4waGpQAjAQAaAAMJXQgaYAAqAAAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAQJBgAWAE4TAA==.Warrendemon:BAACLgAFFH8ZAAIQAAcJViQEFgABAgAQAAcJViQEFgABAgAuAAQKfzUAAxAACQkDJrsBAMADABAACQkDJrsBAMADAAoAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgkJEgAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIgAAkJWBOvUgA/AgAgAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8hAAMfAAkJHyHIBACuAgAfAAkJ1SDIBACuAgAeAAMJ+xQkPgCuAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Woregontail:BAAALgADCggJCAAAAA==.Wowbelly:BAACLgAFFH8IAAIOAAQJggxzNgDPAAAOAAQJggxzNgDPAAAuAAQKfx0AAg4ABwnFG0EWABECAA4ABwnFG0EWABECAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAAOAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAABLgAECn8WAAMFAAcJsg6EsgAbAQAFAAcJpAuEsgAbAQASAAYJlA6bKADSAAAAAA==.',
Xo='Xonk:BAACLgAFFH8YAAInAAcJkhDRAgB1AQAnAAcJkhDRAgB1AQAuAAQKfyQAAicACQkQICwBAPECACcACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECgkJIgAYACwbAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEwAAAA==.',
Yu='Yuuna:BAABLgAECn8VAAIBAAcJogN+ywC6AAABAAcJogN+ywC6AAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8WAAMKAAgJYAkYKwAnAQAKAAgJYAkYKwAnAQAQAAYJ+QID3wB5AAAAAA==.Zapp:BAABLgAECn8WAAIUAAYJiwqxAQCtAAAUAAYJiwqxAQCtAAAAAA==.Zaps:BAABLgAECn8pAAIJAAkJKCMpAgADAwAJAAkJKCMpAgADAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8cAAIgAAcJlBNeggBzAQAgAAcJlBNeggBzAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMEAAkJ4QstTgB4AQAEAAkJ4QstTgB4AQAXAAcJxwg5VQDlAAAAAA==.Zenreto:BAABLgAECn9JAAIUAAkJ1yAfAACVAgAUAAkJ1yAfAACVAgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8ZAAIgAAcJgBwdLwCwAQAgAAcJgBwdLwCwAQAuAAQKfysAAiAACAnAJG0SADkDACAACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8cAAIJAAcJhRoWAwCpAQAJAAcJhRoWAwCpAQAuAAQKfzAAAgkACQkGJXQAAHADAAkACQkGJXQAAHADAAAA.',
['Ät']='Äthena:BAABLgAECn8WAAIdAAYJMgczBACEAAAdAAYJMgczBACEAAAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8zAAMBAAkJuR3tGgCCAgABAAkJuR3tGgCCAgAdAAQJGwjCQQCuAAAAAA==.',
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
