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

local lookup = {'Warlock-Demonology','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Warrior-Arms','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Druid-Feral','Mage-Frost','Hunter-Marksmanship','Mage-Fire','Monk-Brewmaster','Mage-Arcane','Priest-Discipline','Warlock-Affliction','Rogue-Outlaw','Warrior-Protection','Druid-Restoration','Druid-Guardian',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abrakådabruh:BAAALgAECgYJEQAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8ZAAMCAAcJyhzlJgCOAQACAAUJEBzlJgCOAQADAAcJOBEBLwBkAQABLgAFFAYJDwAEAMwCAA==.',
Ae='Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIFAAkJpiCiFQDBAgAFAAkJpiCiFQDBAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainjel:BAAALgADCgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexdh:BAAALgAECgEJAQAAAA==.Alexr:BAAALgADCgMJAwABLgAECgEJAQAGAAAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.Altaxia:BAAALgAECgYJBgAAAA==.',
Am='Amarantus:BAAALgAECgYJCQABLgAFFAUJEwAHAGMPAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAACLgAFFH8FAAIIAAIJ2h04JQCoAAAIAAIJ2h04JQCoAAAuAAQKfxUAAggACAnJEOscALUBAAgACAnJEOscALUBAAEuAAUUBwkcAAkAhRoA.Anmodru:BAAALgAECgYJBgABLgAFFAcJHAAJAIUaAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAIKAAcJxw1rKwBsAQAKAAcJxw1rKwBsAQAAAA==.',
Ap='Apoldelon:BAAALgAECgIJAgAAAA==.',
Aq='Aqulath:BAACLgAFFH8ZAAILAAUJJB9AAwBmAQALAAUJJB9AAwBmAQAuAAQKfxwAAgsACQnpG6kEAHACAAsACQnpG6kEAHACAAAA.Aquílés:BAAALgAECgQJBgAAAA==.',
Ar='Arazensetal:BAABLgAECn9SAAIMAAkJ5B8WAAClAgAMAAkJ5B8WAAClAgAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAcJFAANAIQOAA==.Ariandrel:BAACLgAFFH8FAAIOAAMJvwb/SACBAAAOAAMJvwb/SACBAAAuAAQKfx4AAw4ACQkdES4sAM8BAA4ACQkdES4sAM8BAA8AAQlbAE+OABQAAAAA.Aridhol:BAABLgAECn8XAAIQAAgJPQLL4AB1AAAQAAgJPQLL4AB1AAAAAA==.Arkaedius:BAACLgAFFH8HAAIQAAMJQxZTXwDSAAAQAAMJQxZTXwDSAAAuAAQKfyIAAhAACQkWH1QLAO0CABAACQkWH1QLAO0CAAAA.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJDAABLgAECgQJBAAGAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn9DAAIKAAkJByO/AwAYAwAKAAkJByO/AwAYAwAAAA==.Ation:BAAALgAECgEJAQAAAA==.Atulno:BAAALgAECgYJBgAAAA==.',
Au='Aubrii:BAAALgAECgQJBQAAAA==.Aukatsang:BAACLgAFFH8PAAIPAAcJvxyWCACQAQAPAAcJvxyWCACQAQAuAAQKfyoAAg8ACQmTI10BAKMDAA8ACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgAECgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIRAAgJ9xz+FAClAgARAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIPAAQJvRyGEwAhAQAPAAQJvRyGEwAhAQAuAAQKfyQAAg8ACAndHpEJAN8CAA8ACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn9SAAISAAkJnB5PBQCdAgASAAkJnB5PBQCdAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAFAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgkJCQAAAA==.',
Be='Bearhold:BAAALgAECgYJCQAAAA==.Beefy:BAAALgAECgMJBAAAAA==.Beenis:BAAALgAECgQJBQAAAA==.Beersnob:BAABLgAECn8kAAIOAAkJLxZhHgAmAgAOAAkJLxZhHgAmAgAAAA==.Benjam:BAACLgAFFH8TAAIQAAcJrRZkGgDgAQAQAAcJrRZkGgDgAQAuAAQKfygAAhAABwnlI0wZAL0CABAABwnlI0wZAL0CAAAA.Benyo:BAAALgAECgUJCQAAAA==.',
Bi='Bigmikeyg:BAABLgAECn9UAAIFAAkJghpuAQCqAQAFAAkJghpuAQCqAQAAAA==.Bigsteve:BAABLgAECn9HAAMRAAkJ9CR7BAAdAwARAAkJ9CR7BAAdAwATAAgJ1hJkGwCAAQAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMUAAMJJwqwCADLAAANAAMJiQWXDwD0AAAUAAMJJwqwCADLAAAuAAQKfxYAAw0ABwlSHPUqAKUBAA0ABwkjHPUqAKUBABQAAwmaGgAAAAAAAAAA.Blinded:BAAALgAECgkJAwAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgARAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgQJBAAGAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Brickley:BAAALgAFFAIJAgABLgAFFAUJGQALACQfAA==.Bronzesun:BAAALgAECgUJBgAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIEAAkJMRpFGQCAAgAEAAkJMRpFGQCAAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQMAAkJHQX8IgBhAQAMAAkJHQX8IgBhAQAVAAMJGgjIMgCAAAAWAAMJ0AidfwBfAAAAAA==.Calizon:BAAALgAECgkJEgAAAA==.Camc:BAAALgAECgQJEAAAAA==.Canowhoopass:BAABLgAECn8mAAIXAAgJvAo+RQAeAQAXAAgJvAo+RQAeAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8qAAIQAAYJiBxYJQCYAQAQAAYJiBxYJQCYAQAuAAQKfzYAAhAACQkJIQELAPACABAACQkJIQELAPACAAAA.Cereas:BAABLgAECn9CAAIKAAgJixsHEQAZAgAKAAgJixsHEQAZAgAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chevota:BAAALgAECgYJBgABLgAFFAMJBQABAE4LAA==.Chichobelo:BAABLgAFFH8UAAQYAAgJYhaJIQDrAQAYAAYJxxiJIQDrAQAZAAUJNRC5AABEAQAaAAEJAABoWAAAAAAAAA==.Chuckrutis:BAACLgAFFH8FAAIWAAQJGw8xNQDuAAAWAAQJGw8xNQDuAAAuAAQKfyEAAxUACAlIHXAMABQCABUABglSHnAMABQCABYABQl4HHArAJEBAAAA.',
Cl='Cliché:BAABLgAECn8jAAMbAAgJPRSRIgDwAQAbAAgJPRSRIgDwAQAFAAYJMge26wDQAAAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8YAAIcAAYJhBkcPgAxAQAcAAYJhBkcPgAxAQAuAAQKfyoAAhwACQk6IXYCAHEDABwACQk6IXYCAHEDAAAA.',
Co='Combination:BAABLgAECn9UAAIdAAkJqyLzAAAFAwAdAAkJqyLzAAAFAwABLgAFFAgJKwAFAN0ZAA==.Constrace:BAAALgAECgYJCAAAAA==.Corvenall:BAABLgAECn86AAIVAAkJlA7VCACgAQAVAAkJlA7VCACgAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECggJEwAAAA==.Crossbow:BAACLgAFFH8KAAIcAAMJJRbFWgDvAAAcAAMJJRbFWgDvAAAuAAQKf0MAAhwACQkoIBsPAMICABwACQkoIBsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAUJGQALACQfAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJDAABLgAECggJQgAKAIsbAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Danglyudders:BAAALgAECgYJEQAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAIAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.Dayje:BAAALgAECgIJAgAAAA==.',
De='Deathbcmesyu:BAABLgAECn8iAAIYAAkJLBsBAgBNAQAYAAkJLBsBAgBNAQAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgkJDAABLgAECgkJIQAeAB8hAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwADANoNAA==.Deondre:BAAALgAECgQJCQAAAA==.Detin:BAAALgAECgEJAQAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJIQAeAB8hAA==.',
Di='Diehappy:BAABLgAECn8YAAMZAAcJwwodHADuAAAZAAYJgwwdHADuAAAaAAYJ/AX4PQCYAAAAAA==.Dillie:BAAALgAECgUJCQAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAcJGwALAOgjAA==.Dompal:BAAALgAFFAIJAgABLgAFFAcJGwALAOgjAA==.Donkystyle:BAAALgAECgQJCAAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJSgAfAIUmAA==.Drovinos:BAAALgAECgYJBgAAAA==.Druken:BAAALgAECgYJDwAAAA==.Drybonez:BAABLgAECn8UAAIfAAYJ0Aha+AAKAQAfAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8WAAMcAAcJPyAhKwBdAQAcAAYJVR8hKwBdAQAgAAIJSR/rKABnAAAuAAQKfyMAAyAACQm3JNIJAAYDACAACAmdItIJAAYDABwAAwlvIxmeAAUBAAAA.Dràgonkíng:BAABLgAECn8fAAMhAAgJ+wZ5CAAIAQAhAAgJ+wZ5CAAIAQAfAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAIRAAkJWRwDFABRAgARAAkJWRwDFABRAgABLgAFFAUJFQAYALUdAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIDAAgJ2g1nMQBWAQADAAgJ2g1nMQBWAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgYJCAAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAVAKYfAA==.',
Eg='Ego:BAABLgAECn83AAIRAAkJMiSkBwDkAgARAAkJMiSkBwDkAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elijahtheone:BAAALgAECgMJAwAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAfAHciAA==.Emmone:BAAALgAECgYJEQAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.Emorexx:BAAALgAECgEJAQAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAiAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAABLgAECn8VAAIdAAcJixWYCwCHAQAdAAcJixWYCwCHAQAAAA==.Excaleon:BAAALgAECgUJCgAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAFFAIJAgAAAA==.Faunna:BAACLgAFFH8TAAIHAAUJYw9GLADbAAAHAAUJYw9GLADbAAAuAAQKfz0AAgcACQmEIJwHAN0CAAcACQmEIJwHAN0CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgUJBgAAAA==.Felaz:BAABLgAECn82AAIjAAkJJCADAQDFAgAjAAkJJCADAQDFAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAAALgAECgYJEgAAAA==.Ferreil:BAAALgAECgEJAQAAAA==.Festy:BAAALgAECgEJAQAAAA==.',
Fi='Fingerguns:BAACLgAFFH8OAAIkAAQJ0QaVAwDhAAAkAAQJ0QaVAwDhAAAuAAQKfx0ABCQACQndFSoTAEgCACQACQndFSoTAEgCAAIAAwl3CO5mAJEAAAMAAwkJCB5zAFsAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAULgAA5AQABAAkJDQULgAA5AQAdAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBwAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgAECgUJCQAAAA==.Floortank:BAABLgAECn80AAMZAAkJbwvSEQBbAQAZAAgJ2wvSEQBbAQAYAAgJAQYcpQAkAQAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIbAAMJUBsKKwDSAAAbAAMJUBsKKwDSAAAuAAQKfxsAAhsABwnKI4sRAIcCABsABwnKI4sRAIcCAAAA.Frikilatar:BAAALgAECgEJCQAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAGAAAAAA==.Frrank:BAACLgAFFH8bAAITAAcJmiMJBwDuAQATAAcJmiMJBwDuAQAuAAQKfzQAAhMACQkoJWEAALQDABMACQkoJWEAALQDAAAA.',
Fu='Fullerene:BAAALgAECgEJAwAAAA==.',
Ga='Galcain:BAACLgAFFH8NAAMcAAUJfiCoIgB6AQAcAAUJfiCoIgB6AQAIAAMJtQ8rJAC0AAAuAAQKfy4ABBwACQnwIfYHABEDABwACAm2IvYHABEDAAgACAkHFosYANwBACAAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAUJDQAcAH4gAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAGAAAAAA==.',
Gi='Gintoko:BAAALgAECgMJBgAAAA==.Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8tAAIfAAkJ/BXBQgATAgAfAAkJ/BXBQgATAgAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Grimseek:BAAALgAFFAQJBAABLgAFFAgJKwAFAN0ZAA==.Gripmepapi:BAABLgAFFH8UAAIYAAQJjRSKXAA6AQAYAAQJjRSKXAA6AQAAAA==.Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn9SAAIeAAkJaiA1BQChAgAeAAkJaiA1BQChAgAAAA==.',
Gu='Guce:BAAALgAECgcJDgAAAA==.Gudetama:BAABLgAECn8bAAMcAAkJsCDBFwB7AgAcAAYJESPBFwB7AgAIAAcJwx17DwA3AgAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgAECgQJBAAAAA==.Hakur:BAABLgAECn88AAIFAAkJQhyEMAA/AgAFAAkJQhyEMAA/AgAAAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hanabi:BAAALgAECgYJBgAAAA==.Hanma:BAACLgAFFH8VAAIYAAcJgBkQIQDuAQAYAAcJgBkQIQDuAQAuAAQKfygAAhgACQkFHxEsAIgCABgACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn9LAAIfAAkJlhE3AwAmAQAfAAkJlhE3AwAmAQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgAECgEJAQAAAA==.Hiroki:BAABLgAECn8xAAIYAAkJQQ6jUADRAQAYAAkJQQ6jUADRAQAAAA==.Hitachitotem:BAACLgAFFH8dAAIXAAQJARtvGgBIAQAXAAQJARtvGgBIAQAuAAQKfxkAAhcACAmtGl0aAEACABcACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJDwAAAA==.Hiyodad:BAAALgADCgUJBQAAAA==.Hiyodadk:BAAALgAECgIJAgAAAA==.Hiyodal:BAAALgAECgEJAQAAAA==.Hiyodam:BAAALgADCgIJAgAAAA==.Hiyodat:BAAALgAECgYJCgAAAA==.Hiyodaw:BAABLgAECn8UAAIdAAUJLQbHJgB/AAAdAAUJLQbHJgB/AAAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Hollycat:BAAALgAECgkJAwAAAA==.Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAIQAAkJ2hqvHwBXAgAQAAkJ2hqvHwBXAgAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAUJEQARAK8hAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQACACsgAA==.Holyshifts:BAAALgAECgYJEQAAAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8lAAIfAAkJxhTLQwAQAgAfAAkJxhTLQwAQAgAAAA==.',
In='Inflikted:BAABLgAECn8lAAIYAAkJVQgPeQBxAQAYAAkJVQgPeQBxAQAAAA==.Interwebz:BAABLgAECn8dAAMYAAkJHh3rIgB7AgAYAAkJKxzrIgB7AgAaAAIJ9h1KPgCXAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Iz='Izztargaryen:BAAALgADCgEJAQAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgQJBAAGAAAAAA==.Jazzarin:BAAALgAECgUJCAAAAA==.',
Je='Jehannum:BAABLgAECn83AAIXAAkJZBTcAACGAQAXAAkJZBTcAACGAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgYJEQAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8IAAIbAAQJfxohIAAcAQAbAAQJfxohIAAcAQABLgAFFAUJJwAEALMlAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgAECgUJCQAAAA==.Jurkzarbirt:BAAALgAECgQJBQAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jì']='Jìnbe:BAAALgAECgYJEQAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIDAAgJ0hehJQCeAQADAAgJ0hehJQCeAQAAAA==.',
Ka='Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kainiy:BAAALgAECgMJBQAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgYJDgAAAA==.Kassan:BAAALgAECgYJEQAAAA==.Katarena:BAABLgAECn83AAIbAAgJVRAEMgCOAQAbAAgJVRAEMgCOAQAAAA==.Kathyra:BAACLgAFFH8FAAIBAAMJTgsJfQDKAAABAAMJTgsJfQDKAAAuAAQKfygAAwEACQn5Dv1OAK4BAAEACQn5Dv1OAK4BACUAAQnvASM3ACcAAAAA.Kavax:BAABLgAECn8mAAIbAAkJgxSQGQA6AgAbAAkJgxSQGQA6AgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIFAAYJlw9rLQBaAQAFAAYJlw9rLQBaAQAuAAQKfzwAAgUACQnFHi0iAH0CAAUACQnFHi0iAH0CAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kelorth:BAAALgADCggJCAAAAA==.Kentyr:BAABLgAECn83AAMNAAgJ8xFKHACzAQANAAgJ8xFKHACzAQAmAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khaldormu:BAAALgAECggJBwAAAA==.Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAUJEQARAK8hAA==.Kinký:BAACLgAFFH8HAAIRAAQJYwxfKAAUAQARAAQJYwxfKAAUAQAuAAQKfy8AAxEACQk0FlcYACsCABEACQk0FlcYACsCABMAAQnbFDl1ADcAAAEuAAQKBwkTAAYAAAAA.Kiraelis:BAABLgAECn8lAAIgAAkJqg8VDQCPAQAgAAkJqg8VDQCPAQAAAA==.Kisara:BAAALgADCggJDAABLgAFFAMJBQAFAOsNAA==.Kiss:BAAALgADCgEJAQABLgAFFAEJAQAGAAAAAA==.Kivea:BAABLgAECn8aAAMfAAkJZg9LZAC1AQAfAAkJZg9LZAC1AQAhAAEJBAe+FQAoAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Konvik:BAAALgAECgEJAQAAAA==.Kooka:BAAALgADCgEJAQAAAA==.Korvoh:BAABLgAECn9QAAMkAAkJ7h5RAABdAgAkAAkJ7h5RAABdAgACAAMJUxeOXQC8AAAAAA==.',
Kr='Krincess:BAABLgAECn8YAAIWAAgJXBdfAADHAQAWAAgJXBdfAADHAQABLgAECgkJNAAXAAAkAA==.Kringe:BAABLgAECn80AAMXAAkJACRvBAAcAwAXAAkJACRvBAAcAwAEAAEJLQQP6QAlAAAAAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumaro:BAAALgAECgMJAwAAAA==.Kumonk:BAABLgAECn8cAAIPAAcJWAbLSwDTAAAPAAcJWAbLSwDTAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBgAAAA==.',
['Kä']='Kämik:BAABLgAECn9KAAIcAAkJrCG5CgAAAwAcAAkJrCG5CgAAAwAAAA==.',
['Kì']='Kìn:BAABLgAECn8nAAMkAAcJ8wrEPQAWAQAkAAYJggzEPQAWAQADAAYJvwKXdABYAAAAAA==.',
La='Lampion:BAABLgAECn8hAAIKAAkJdAztIABxAQAKAAkJdAztIABxAQAAAA==.Langris:BAAALgAECgEJAwAAAA==.Lasstchance:BAABLgAECn8ZAAIcAAcJeAyzewBIAQAcAAcJeAyzewBIAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8pAAIBAAkJ/h41DwDTAgABAAkJ/h41DwDTAgAAAA==.',
Le='Leijona:BAAALgAECgIJBQAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgAECgUJCQAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Lightbunny:BAAALgAECgMJAwAAAA==.Lightstorms:BAAALgAECgYJBgAAAA==.Likeatrain:BAABLgAECn86AAInAAkJrBZyDQAUAgAnAAkJrBZyDQAUAgAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMbAAgJJRN/KADqAQAbAAgJJRN/KADqAQAFAAUJDgjDDQGoAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMbAAkJOh5cFgBYAgAbAAkJOh5cFgBYAgAFAAYJTQzF6ADTAAAAAA==.Lintha:BAAALgAECggJBwAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAABLgAECn8UAAMWAAYJKhWAOwA9AQAWAAYJKhWAOwA9AQAVAAEJ3wOVKgAkAAABLgAFFAUJEQARAK8hAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8bAAMNAAgJlBc7GwC9AQANAAgJlBc7GwC9AQAUAAEJhxD2HwAzAAAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn9EAAIPAAkJhyR/BAAQAwAPAAkJhyR/BAAQAwAAAA==.',
Lu='Luber:BAABLgAECn8xAAMEAAkJ7wwrQwChAQAEAAkJ7wwrQwChAQAXAAYJMAz3VQDjAAAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAACLgAFFH8HAAIaAAMJJCWLFwAsAQAaAAMJJCWLFwAsAQAuAAQKf1IAAhoACQkiJrQAAGkDABoACQkiJrQAAGkDAAAA.Luxzy:BAABLgAECn8UAAIgAAgJ0QcRFQATAQAgAAgJ0QcRFQATAQAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgAECgEJAQAAAA==.Manbearcat:BAABLgAECn8iAAIoAAkJPSBwCgAWAwAoAAkJPSBwCgAWAwAAAA==.Marbleous:BAACLgAFFH8KAAIRAAMJBiRAKwAHAQARAAMJBiRAKwAHAQAuAAQKfxgAAhEABgm6IzwoALoBABEABgm6IzwoALoBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIgAoAD0gAA==.Mcspicy:BAAALgAECgUJCAAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAlAFkfAA==.Mechalomania:BAAALgAECgkJCQABLgAECgkJOAAHADMPAA==.Melhina:BAAALgAECgUJCQABLgAECggJOgAlANIcAA==.Memisstotem:BAABLgAECn8eAAIEAAcJgRrPMgDoAQAEAAcJgRrPMgDoAQAAAA==.Merle:BAACLgAFFH8RAAIRAAUJryEzEACEAQARAAUJryEzEACEAQAuAAQKf1QAAxEACQlUJcYCAEUDABEACQkgJMYCAEUDABMABgncJIkOAAMCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8dAAIQAAgJ7Rn+KQAhAgAQAAgJ7Rn+KQAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Mikethegray:BAAALgAECgYJEQABLgAECgkJVAAFAIIaAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8eAAICAAcJmA1+NQAtAQACAAcJmA1+NQAtAQAAAA==.Mistborn:BAABLgAECn84AAQCAAkJiCIhCQC5AgACAAkJiCIhCQC5AgAkAAQJ1RyJKQBMAQADAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAVAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn86AAIeAAkJZCDxAgDvAgAeAAkJZCDxAgDvAgAAAA==.Monkjamin:BAABLgAFFH8GAAIiAAMJThcVNgDOAAAiAAMJThcVNgDOAAAAAA==.Moolimbo:BAABLgAECn8qAAIXAAkJghi8FgAwAgAXAAkJghi8FgAwAgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAVAKYfAA==.Mooseboy:BAABLgAECn8tAAIeAAkJah70BACpAgAeAAkJah70BACpAgAAAA==.Mooserton:BAACLgAFFH8FAAIbAAMJeBAdMQCvAAAbAAMJeBAdMQCvAAAuAAQKfzYAAxsACQmaHEoIAAcDABsACQmaHEoIAAcDAAUABgmsD8zcAOIAAAAA.Mootalstrike:BAABLgAECn8zAAIRAAkJbhVUHwD0AQARAAkJbhVUHwD0AQAAAA==.Moshworm:BAABLgAECn84AAIHAAkJMw/xIgCyAQAHAAkJMw/xIgCyAQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAUJFQAYALUdAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAYJGAAcAIQZAA==.',
['Mä']='Mängo:BAAALgADCgYJBgAAAA==.',
Na='Nalaxx:BAAALgAECgkJAQAAAA==.Natsumi:BAABLgAECn8WAAIEAAcJxgvVZgAnAQAEAAcJxgvVZgAnAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIWAAYJVQPRQwDRAAAWAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAIfAAkJBh4OIwCRAgAfAAkJBh4OIwCRAgAAAA==.Neuroticaine:BAABLgAECn9ZAAMDAAkJthtsAADvAQADAAkJthtsAADvAQAkAAQJVQ4JSwDYAAAAAA==.Nev:BAACLgAFFH8SAAMcAAQJsCGPMABOAQAcAAQJsCGPMABOAQAgAAMJ6AVCGQDAAAAuAAQKfyEAAxwACAncIsYjAC8CABwABwkjIsYjAC8CACAABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8QAAINAAQJzAtkIAAiAQANAAQJzAtkIAAiAQAAAA==.',
Ni='Nico:BAABLgAECn8bAAIIAAkJChIjEQCxAQAIAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQlAAkJWR+fBABRAgAlAAkJUx+fBABRAgAdAAcJIBqjCgCZAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgAECgUJCQAAAA==.Nooblets:BAACLgAFFH8HAAINAAMJ/xocKQDiAAANAAMJ/xocKQDiAAAuAAQKfxsAAg0ABwnMIGEbALwBAA0ABwnMIGEbALwBAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMQAAkJQBLFVACIAQAQAAkJQBLFVACIAQALAAIJwhRrMgA6AAAAAA==.Noxxus:BAABLgAECn8fAAISAAkJvRqdDAD9AQASAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAlAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAACLgAFFH8LAAIYAAQJ2gJPDAC8AAAYAAQJ2gJPDAC8AAAuAAQKfxwAAxgACQmbC6VnAJcBABgACQmbC6VnAJcBABoAAQn0AfNmABwAAAAA.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAXAIIYAA==.',
Om='Omnivus:BAAALgAECgMJBgAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgEJAwAGAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAbAFAbAA==.Oratherah:BAABLgAFFH8LAAIaAAMJziS7JgC9AAAaAAMJziS7JgC9AAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8mAAIRAAkJPiIKBwDtAgARAAkJPiIKBwDtAgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAABLgAECn8YAAIKAAgJLxY8FgDYAQAKAAgJLxY8FgDYAQAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn9UAAIZAAkJnQyVAAAUAQAZAAkJnQyVAAAUAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAXAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHQAYAB4dAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIgAoAD0gAA==.Pitchblende:BAABLgAECn8xAAIbAAkJMBKAHwAHAgAbAAkJMBKAHwAHAgAAAA==.',
Po='Poeppsul:BAAALgADCgMJAwAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Polyrock:BAAALgADCgQJBAAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAYAOEkAA==.Porthub:BAABLgAECn8pAAIfAAkJLAkleACJAQAfAAkJLAkleACJAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAABLgAECn8VAAMcAAcJJRFGbABpAQAcAAcJJRFGbABpAQAgAAEJAAB4SQAAAAAAAA==.Rajak:BAAALgAECgYJCAAAAA==.Range:BAAALgAFFAIJAgAAAA==.Raph:BAAALgAECgYJEgAAAA==.Rathibrew:BAACLgAFFH8bAAIiAAcJzh2MDADOAQAiAAcJzh2MDADOAQAuAAQKfzgAAiIACQmcJLwBAIwDACIACQmcJLwBAIwDAAAA.',
Re='Reckurface:BAAALgAECgEJAQAAAA==.Redine:BAAALgAECgMJAwAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgcJCgAAAA==.Rellt:BAAALgADCgQJBgAAAA==.Remnants:BAABLgAECn8UAAIiAAYJihvDJwDIAQAiAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8YAAQCAAgJRQezOQASAQACAAgJRQezOQASAQADAAUJEAOebQBpAAAkAAEJ4gHeigAcAAAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgQJCAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAGAAAAAA==.Rompally:BAAALgAECgYJCAAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8VAAQYAAUJtR0sQwBvAQAYAAUJtR0sQwBvAQAZAAEJUQ3bJwBGAAAaAAEJAAA9WAAAAAAuAAQKfzEAAhgACQnGHyorAFMCABgACQnGHyorAFMCAAAA.',
['Rê']='Rêvolt:BAABLgAFFH8IAAIQAAIJYg4UggB7AAAQAAIJYg4UggB7AAAAAA==.Rêzìcå:BAAALgADCgkJCQAAAA==.',
['Rô']='Rôwdy:BAAALgAECgEJAQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAABLgAECn8ZAAMcAAgJ0getfABGAQAcAAgJ0getfABGAQAgAAQJWwF8PAAyAAAAAA==.Salezar:BAABLgAECn8rAAIVAAkJph9jAQDnAgAVAAkJph9jAQDnAgAAAA==.Sandoud:BAABLgAECn8cAAIHAAkJ6xNDGgD5AQAHAAkJ6xNDGgD5AQAAAA==.Sapientia:BAABLgAECn8tAAIFAAkJqwgTjABZAQAFAAkJqwgTjABZAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECggJQgAKAIsbAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgAECgEJAgAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIbAAQJcw/kKADdAAAbAAQJcw/kKADdAAAuAAQKfyEAAxsACAlaGMcZAEUCABsACAlaGMcZAEUCAAUAAQnyDycyAT8AAAEuAAUUCAkhAB8AThoA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAIJAgAAAA==.Selenesul:BAABLgAECn8sAAMFAAkJ9RxjHwCLAgAFAAkJ9RxjHwCLAgASAAMJTAynNAB0AAAAAA==.Selyda:BAAALgAECgEJAQAAAA==.Senzie:BAACLgAFFH8YAAIPAAUJex95DABgAQAPAAUJex95DABgAQAuAAQKfyUAAg8ACQkiHlYNAHACAA8ACQkiHlYNAHACAAEuAAUUBgkRAA8AuBIA.Sevro:BAAALgADCgQJBAABLgAECgkJJgAbAIMUAA==.',
Sh='Shadowdrake:BAABLgAECn8dAAIWAAkJzQsuMQByAQAWAAkJzQsuMQByAQAAAA==.Shadowheàrt:BAABLgAECn8kAAMbAAcJMRZkAQAdAQAbAAYJsRVkAQAdAQAFAAQJOQUyOAF1AAAAAA==.Shadowshifty:BAABLgAECn8gAAIpAAcJAw+6LwDuAAApAAcJAw+6LwDuAAAAAA==.Shadowtotem:BAAALgAECgYJBgAAAA==.Shaeen:BAABLgAFFH8GAAILAAMJ7Az6CQCxAAALAAMJ7Az6CQCxAAAAAA==.Shagi:BAABLgAECn8pAAIiAAgJUhimFwDrAQAiAAgJUhimFwDrAQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharklee:BAAALgADCgEJAgAAAA==.Sharroz:BAABLgAECn8dAAMZAAcJiB1oAwBWAgAZAAcJiB1oAwBWAgAaAAQJVQ7uQQCHAAAAAA==.Shauna:BAACLgAFFH8IAAIcAAcJxAaYbgDFAAAcAAcJxAaYbgDFAAAuAAQKfxUAAhwACAn6DqhOALYBABwACAn6DqhOALYBAAAA.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMkAAgJeBpOFwAcAgAkAAgJeBpOFwAcAgADAAEJJQKaaQAlAAABLgAFFAUJFQAYALUdAA==.Shockybalboa:BAABLgAECn8UAAIXAAcJNBP8NQBiAQAXAAcJNBP8NQBiAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBwAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skoftyia:BAAALgAECgEJAQABLgAFFAMJCgARAIIVAA==.Skooda:BAABLgAECn8tAAIXAAkJaA4+MAB/AQAXAAkJaA4+MAB/AQAAAA==.Skyded:BAABLgAECn8yAAIYAAkJLBn2MAA7AgAYAAkJLBn2MAA7AgAAAA==.Skyknight:BAABLgAECn8hAAIRAAkJnBN0KQCzAQARAAkJnBN0KQCzAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8PAAMIAAYJ8xJDFAAqAQAIAAYJ8xJDFAAqAQAgAAIJBwsTJwB0AAAuAAQKfzsAAwgACQlyI3oEAOYCAAgACQlQInoEAOYCACAACAnWHuoSAJ8CAAAA.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgADCgYJCwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8uAAIQAAkJ1xyEAAALAgAQAAkJ1xyEAAALAgAAAA==.Solence:BAAALgADCgIJAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAABLgAECn8cAAIFAAgJuR06IwB4AgAFAAgJuR06IwB4AgAAAA==.Soralas:BAAALgAECgcJEQAAAA==.',
Sp='Spaazz:BAABLgAECn8jAAIFAAkJsyF/FADHAgAFAAkJsyF/FADHAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
St='Staggerstout:BAAALgAECgEJAQAAAA==.Starweaver:BAABLgAECn8qAAMkAAkJKBOwKQCHAQAkAAkJLgmwKQCHAQACAAgJJhP9KgBwAQAAAA==.Stellmarine:BAABLgAECn8dAAIHAAkJzRoRGwDyAQAHAAkJzRoRGwDyAQAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgcJEAAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMpAAkJIhu3CABhAgApAAkJ4Rq3CABhAgAHAAYJBBrnKgCqAQAAAA==.',
Su='Subzro:BAAALgAECgUJCQAAAA==.Sunamé:BAAALgAECgUJCwAAAA==.',
Sw='Swaazil:BAACLgAFFH8YAAIfAAQJcwhaCAD5AAAfAAQJcwhaCAD5AAAuAAQKfyYAAh8ACQkrEaFeAMMBAB8ACQkrEaFeAMMBAAAA.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgIJAgAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAGAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8fAAIQAAcJIQ1QiAAPAQAQAAcJIQ1QiAAPAQAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taken:BAAALgAECgYJBgAAAA==.Taloriesh:BAACLgAFFH8HAAICAAMJ3x65GAD2AAACAAMJ3x65GAD2AAAuAAQKfysABAIACQmlHmwIAOQCAAIACQmlHmwIAOQCAAMAAQk+FepgADYAACQAAQkdDlB8AC8AAAAA.Tanazir:BAEBLgAECn8cAAIVAAgJKhGeCQCMAQAVAAgJKhGeCQCMAQAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarivel:BAAALgAECgIJAgAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8YAAIPAAgJwA80KwBkAQAPAAgJwA80KwBkAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIdAAgJnBwLBQAlAgAdAAgJnBwLBQAlAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECggJHAAVACoRAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIFAAkJLBlZRQATAgAFAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8XAAIcAAcJKQaqmQANAQAcAAcJKQaqmQANAQAAAA==.Tilamano:BAACLgAFFH8FAAIBAAIJ1iPDDABxAAABAAIJ1iPDDABxAAAuAAQKfzsABB0ACQmlJfgBAK4CAB0ACAnSJPgBAK4CACUACAk6JPgCAJMCAAEACAkyJEMmAEQCAAAA.Tilthulhu:BAAALgAECgMJAwABLgAFFAIJBQABANYjAA==.',
Tm='Tmntmikey:BAABLgAFFH8VAAQOAAYJOBMNBAD8AAAOAAYJOBMNBAD8AAAiAAMJbgH1RACOAAAPAAEJvAftRgAzAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMcAAcJRCMZHwBLAgAcAAcJgCIZHwBLAgAgAAYJMSMUIgAVAgABLgAECgkJFwAQANoaAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAiAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAiAO8lAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAiAO8lAA==.Toopie:BAACLgAFFH8FAAIiAAEJ7yU7TwBlAAAiAAEJ7yU7TwBlAAAuAAQKfx4AAyIACAn7IWULANcCACIACAn7IWULANcCAA8ABQlvGSQ4AD0BAAAA.',
Tr='Trackdown:BAAALgAECgcJBwAAAA==.Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8qAAIoAAkJxBsvEgC8AgAoAAkJxBsvEgC8AgAAAA==.Tryath:BAABLgAECn8ZAAMoAAgJ4wqWcwDaAAAoAAcJcAiWcwDaAAAHAAQJzAmrZwCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
Ty='Tyrethia:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIdAAUJAhUeBwAlAQAdAAUJAhUeBwAlAQAuAAQKfyQAAh0ACQl8G2oCAOUCAB0ACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIIAAkJCh8hAwABAwAIAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAIQAAkJQiBfEwDlAgAQAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgcJHAAfAPsVAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn8/AAISAAkJoiMnAgAYAwASAAkJoiMnAgAYAwAAAA==.Valros:BAAALgADCgEJAQABLgAECggJKQAiAFIYAA==.Vanaras:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgUJDwABLgAECgkJIgAYACwbAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMNAAkJnxYNFQD5AQANAAkJshUNFQD5AQAUAAUJ8xGAEwDJAAAAAA==.Veraana:BAAALgAECgYJEQAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn9NAAIcAAkJHh0cAQD1AQAcAAkJHh0cAQD1AQAAAA==.',
Vi='Vicariana:BAACLgAFFH8dAAMkAAcJoiRcDABZAgAkAAcJoiRcDABZAgADAAEJphQsOQBIAAAuAAQKfywAAyQACQnfJhEAAPkDACQACQnfJhEAAPkDAAMAAQnWIXJxAF8AAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJAwAAAA==.Vidette:BAAALgAECgEJAQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAlAFkfAA==.Viv:BAABLgAECn8qAAMSAAkJLiK8BQCWAgASAAcJPCS8BQCWAgAFAAcJCSJWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8gAAIFAAkJjAaolQBJAQAFAAkJjAaolQBJAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAABLgAECn8VAAMYAAgJNweApQAjAQAYAAgJTgaApQAjAQAaAAMJXQgbYAAqAAAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAQJBQAWAFkPAA==.Warrendemon:BAACLgAFFH8ZAAIQAAcJViQXFgABAgAQAAcJViQXFgABAgAuAAQKfzUAAxAACQkDJrsBAMADABAACQkDJrsBAMADAAoAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgYJCQAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIfAAkJWBOvUgA/AgAfAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8hAAMeAAkJHyHHBACuAgAeAAkJ1SDHBACuAgApAAMJ+xQnPgCuAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Woregontail:BAAALgADCggJCAAAAA==.Wowbelly:BAACLgAFFH8IAAIOAAQJggxwNgDPAAAOAAQJggxwNgDPAAAuAAQKfx0AAg4ABwnFG0EWABECAA4ABwnFG0EWABECAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAAOAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAABLgAECn8WAAMFAAcJsg6FsgAbAQAFAAcJpAuFsgAbAQASAAYJlA6bKADSAAAAAA==.',
Xo='Xonk:BAACLgAFFH8YAAIlAAcJkhDRAgB1AQAlAAcJkhDRAgB1AQAuAAQKfyQAAiUACQkQICwBAPECACUACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECgkJIgAYACwbAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEgAAAA==.',
Yu='Yuuna:BAABLgAECn8VAAIBAAcJogOAywC6AAABAAcJogOAywC6AAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8WAAMKAAgJYAkTKwAnAQAKAAgJYAkTKwAnAQAQAAYJ+QIA3wB5AAAAAA==.Zapp:BAAALgAECgYJEQAAAA==.Zaps:BAABLgAECn8pAAIJAAkJKCMqAgADAwAJAAkJKCMqAgADAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8cAAIfAAcJlBNeggBzAQAfAAcJlBNeggBzAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMEAAkJ4QsoTgB4AQAEAAkJ4QsoTgB4AQAXAAcJxwg4VQDlAAAAAA==.Zenreto:BAABLgAECn9IAAIUAAkJ1yAYAAA2AgAUAAkJ1yAYAAA2AgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8ZAAIfAAcJgBw6LwCwAQAfAAcJgBw6LwCwAQAuAAQKfysAAh8ACAnAJG0SADkDAB8ACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8cAAIJAAcJhRoYAwCpAQAJAAcJhRoYAwCpAQAuAAQKfzAAAgkACQkGJXQAAHADAAkACQkGJXQAAHADAAAA.',
['Ät']='Äthena:BAAALgAECgYJEQAAAA==.',
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
