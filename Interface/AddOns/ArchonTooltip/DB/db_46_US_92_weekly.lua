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

local lookup = {'Warlock-Demonology','Priest-Holy','Priest-Shadow','Shaman-Restoration','Paladin-Retribution','Druid-Balance','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Unknown-Unknown','Warrior-Fury','Paladin-Protection','Warrior-Arms','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Druid-Feral','Mage-Frost','Hunter-Marksmanship','Mage-Fire','Monk-Brewmaster','Mage-Arcane','Priest-Discipline','Warlock-Affliction','Rogue-Outlaw','Warrior-Protection','Druid-Restoration','Druid-Guardian',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abrakådabruh:BAAALgAECgYJCwAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8ZAAMCAAcJyhw/JgCOAQACAAUJEBw/JgCOAQADAAcJOBFnLgBmAQABLgAFFAYJDwAEAMwCAA==.',
Ae='Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIFAAkJpiAIFQDCAgAFAAkJpiAIFQDCAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainjel:BAAALgADCgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.Altaxia:BAAALgAECgYJBgAAAA==.',
Am='Amarantus:BAAALgAECgYJCQABLgAFFAUJEwAGAGMPAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAACLgAFFH8FAAIHAAIJ2h0+JACqAAAHAAIJ2h0+JACqAAAuAAQKfxUAAgcACAnJEE4cALoBAAcACAnJEE4cALoBAAEuAAUUBgkbAAgA/x4A.Anmodru:BAAALgAECgYJBgABLgAFFAYJGwAIAP8eAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAIJAAcJxw1rKwBsAQAJAAcJxw1rKwBsAQAAAA==.',
Ap='Apoldelon:BAAALgAECgIJAgAAAA==.',
Aq='Aqulath:BAACLgAFFH8VAAIKAAUJJB8MAwBoAQAKAAUJJB8MAwBoAQAuAAQKfxwAAgoACQnpG5IEAHACAAoACQnpG5IEAHACAAAA.Aquílés:BAAALgAECgEJAgAAAA==.',
Ar='Arazensetal:BAABLgAECn9LAAILAAkJXRxZBADmAgALAAkJXRxZBADmAgAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAYJEwAMAMAPAA==.Ariandrel:BAACLgAFFH8FAAINAAMJvwaqRQCCAAANAAMJvwaqRQCCAAAuAAQKfx4AAw0ACQkdEU4rAM4BAA0ACQkdEU4rAM4BAA4AAQlbAE+OABQAAAAA.Aridhol:BAAALgAECggJEQAAAA==.Arkaedius:BAACLgAFFH8HAAIPAAMJQxa5XADSAAAPAAMJQxa5XADSAAAuAAQKfyIAAg8ACQkWHxALAO0CAA8ACQkWHxALAO0CAAAA.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJDAABLgAECgQJBAAQAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn88AAIJAAkJ+CKQAwAaAwAJAAkJ+CKQAwAaAwAAAA==.Atulno:BAAALgAECgYJBgAAAA==.',
Au='Aubrii:BAAALgAECgQJBQAAAA==.Aukatsang:BAACLgAFFH8OAAIOAAYJ1x4eCACQAQAOAAYJ1x4eCACQAQAuAAQKfyoAAg4ACQmTI10BAKMDAA4ACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgAECgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIRAAgJ9xz+FAClAgARAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIOAAQJvRy3EgAhAQAOAAQJvRy3EgAhAQAuAAQKfyQAAg4ACAndHpEJAN8CAA4ACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn9LAAISAAkJnB4vBQCdAgASAAkJnB4vBQCdAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAFAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgMJAwAAAA==.',
Be='Bearhold:BAAALgAECgYJCQAAAA==.Beefy:BAAALgAECgMJBAAAAA==.Beenis:BAAALgAECgQJBQAAAA==.Beersnob:BAABLgAECn8kAAINAAkJLxbEHQAlAgANAAkJLxbEHQAlAgAAAA==.Benjam:BAACLgAFFH8TAAIPAAcJrRaDGADhAQAPAAcJrRaDGADhAQAuAAQKfygAAg8ABwnlI0wZAL0CAA8ABwnlI0wZAL0CAAAA.Benyo:BAAALgAECgQJBAAAAA==.',
Bi='Bigmikeyg:BAABLgAECn9NAAIFAAkJIxkjKABgAgAFAAkJIxkjKABgAgAAAA==.Bigsteve:BAABLgAECn9AAAMRAAkJ8CJHBAAgAwARAAkJ8CJHBAAgAwATAAgJ1hLeGgCAAQAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMUAAMJJwqACADPAAAMAAMJiQWXDwD0AAAUAAMJJwqACADPAAAuAAQKfxYAAwwABwlSHPUqAKUBAAwABwkjHPUqAKUBABQAAwmaGgAAAAAAAAAA.Blinded:BAAALgAECgkJAwAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgARAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgQJBAAQAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Brickley:BAAALgAFFAEJAQABLgAFFAUJFQAKACQfAA==.Bronzesun:BAAALgAECgEJAQAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIEAAkJMRq+GACAAgAEAAkJMRq+GACAAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQLAAkJHQX8IgBhAQALAAkJHQX8IgBhAQAVAAMJGgjIMgCAAAAWAAMJ0AhAfABjAAAAAA==.Calizon:BAAALgAECgkJEgAAAA==.Camc:BAAALgAECgQJEAAAAA==.Canowhoopass:BAABLgAECn8mAAIXAAgJvArBQwAgAQAXAAgJvArBQwAgAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8oAAIPAAYJiBzxIgCbAQAPAAYJiBzxIgCbAQAuAAQKfzYAAg8ACQkJIcAKAPECAA8ACQkJIcAKAPECAAAA.Cereas:BAABLgAECn9CAAIJAAgJixu8EAAbAgAJAAgJixu8EAAbAgAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chevota:BAAALgAECgYJBgABLgAECgkJKAABAPkOAA==.Chichobelo:BAABLgAFFH8NAAQYAAcJZBmCHgDtAQAYAAYJxxiCHgDtAQAZAAEJuR5yIwBUAAAaAAEJAABXVQAAAAAAAA==.Chuckrutis:BAACLgAFFH8FAAIWAAQJGw8VMwD0AAAWAAQJGw8VMwD0AAAuAAQKfyEAAxUACAlIHXAMABQCABUABglSHnAMABQCABYABQl4HOcqAJEBAAAA.',
Cl='Cliché:BAABLgAECn8jAAMbAAgJPRQWIgDxAQAbAAgJPRQWIgDxAQAFAAYJMgdk5wDSAAAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8XAAIcAAUJfht6OgAyAQAcAAUJfht6OgAyAQAuAAQKfyoAAhwACQk6IXYCAHEDABwACQk6IXYCAHEDAAAA.',
Co='Combination:BAABLgAECn9NAAIdAAkJqiHmAAAHAwAdAAkJqiHmAAAHAwABLgAFFAgJJwAFAN0ZAA==.Constrace:BAAALgAECgYJCAAAAA==.Corvenall:BAABLgAECn86AAIVAAkJlA6yCACgAQAVAAkJlA6yCACgAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECggJEwAAAA==.Crossbow:BAACLgAFFH8KAAIcAAMJJRY8VgDxAAAcAAMJJRY8VgDxAAAuAAQKf0IAAhwACQkoIBsPAMICABwACQkoIBsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAUJFQAKACQfAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJDAABLgAECggJQgAJAIsbAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Danglyudders:BAAALgAECgYJCwAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAHAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.Dayje:BAAALgAECgIJAgAAAA==.',
De='Deathbcmesyu:BAABLgAECn8cAAIYAAkJYxVqMwAvAgAYAAkJYxVqMwAvAgAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgkJDAABLgAECgkJIQAeAB8hAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwADANoNAA==.Deondre:BAAALgAECgQJCAAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJIQAeAB8hAA==.',
Di='Diehappy:BAABLgAECn8YAAMZAAcJwwpYGwDwAAAZAAYJgwxYGwDwAAAaAAYJ/AXNPACaAAAAAA==.Dillie:BAAALgAECgQJBAAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAYJGgAKAMUjAA==.Dompal:BAAALgAFFAIJAgABLgAFFAYJGgAKAMUjAA==.Donkystyle:BAAALgAECgQJCAAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJQQAfAH4mAA==.Drovinos:BAAALgAECgYJBgAAAA==.Druken:BAAALgAECgYJDwAAAA==.Drybonez:BAABLgAECn8UAAIfAAYJ0Aha+AAKAQAfAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8VAAMcAAYJMSSIJwBgAQAcAAUJCCSIJwBgAQAgAAIJSR+NJwBpAAAuAAQKfyMAAyAACQm3JNIJAAYDACAACAmdItIJAAYDABwAAwlvI9SaAAYBAAAA.Dràgonkíng:BAABLgAECn8dAAMhAAgJvAZTCAAFAQAhAAgJvAZTCAAFAQAfAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAIRAAkJWRyWEwBUAgARAAkJWRyWEwBUAgABLgAFFAUJEgAYAC8cAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIDAAgJ2g0+MABbAQADAAgJ2g0+MABbAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgYJCAAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAVAKYfAA==.',
Eg='Ego:BAABLgAECn83AAIRAAkJMiRzBwDmAgARAAkJMiRzBwDmAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elijahtheone:BAAALgAECgMJAwAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAfAHciAA==.Emmone:BAAALgAECgYJEAAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAiAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAABLgAECn8VAAIdAAcJixVPCwCIAQAdAAcJixVPCwCIAQAAAA==.Excaleon:BAAALgAECgUJCgAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAFFAIJAgAAAA==.Faunna:BAACLgAFFH8TAAIGAAUJYw8DKwDbAAAGAAUJYw8DKwDbAAAuAAQKfz0AAgYACQmEIGsHAN0CAAYACQmEIGsHAN0CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgUJBgAAAA==.Felaz:BAABLgAECn82AAIjAAkJJCD8AADGAgAjAAkJJCD8AADGAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAAALgAECgYJDAAAAA==.Ferreil:BAAALgAECgEJAQAAAA==.Festy:BAAALgADCgYJBgAAAA==.',
Fi='Fingerguns:BAACLgAFFH8KAAIkAAQJ5gWOLADlAAAkAAQJ5gWOLADlAAAuAAQKfx0ABCQACQndFaoSAEsCACQACQndFaoSAEsCAAIAAwl3CO5mAJEAAAMAAwkJCE5xAFsAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAUPfgA8AQABAAkJDQUPfgA8AQAdAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBgAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgAECgQJBAAAAA==.Floortank:BAABLgAECn80AAMZAAkJbws8EQBfAQAZAAgJ2ws8EQBfAQAYAAgJAQZ5oQAnAQAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIbAAMJUBv8KQDTAAAbAAMJUBv8KQDTAAAuAAQKfxsAAhsABwnKI4sRAIcCABsABwnKI4sRAIcCAAAA.Frikilatar:BAAALgAECgEJCAAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAQAAAAAA==.Frrank:BAACLgAFFH8aAAITAAYJwyVhBgDyAQATAAYJwyVhBgDyAQAuAAQKfzQAAhMACQkoJWEAALQDABMACQkoJWEAALQDAAAA.',
Fu='Fullerene:BAAALgAECgEJAgAAAA==.',
Ga='Galcain:BAACLgAFFH8KAAMcAAQJDR93JABrAQAcAAQJDR93JABrAQAHAAMJtQ9dIwC0AAAuAAQKfy4ABBwACQnwIfYHABEDABwACAm2IvYHABEDAAcACAkHFvAXAOIBACAAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAQJCgAcAA0fAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAQAAAAAA==.',
Gi='Gintoko:BAAALgAECgMJBgAAAA==.Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8tAAIfAAkJ/BWnQQAUAgAfAAkJ/BWnQQAUAgAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Grimseek:BAAALgAFFAQJBAABLgAFFAgJJwAFAN0ZAA==.Gripmepapi:BAABLgAFFH8UAAIYAAQJjRS9WQA8AQAYAAQJjRS9WQA8AQAAAA==.Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn9MAAIeAAkJgRwcBQChAgAeAAkJgRwcBQChAgAAAA==.',
Gu='Guce:BAAALgAECgcJDgAAAA==.Gudetama:BAABLgAECn8bAAMcAAkJsCDBFwB7AgAcAAYJESPBFwB7AgAHAAcJwx08DwA6AgAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgAECgQJBAAAAA==.Hakur:BAABLgAECn87AAIFAAkJQhycLwBAAgAFAAkJQhycLwBAAgAAAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hanabi:BAAALgAECgYJBgAAAA==.Hanma:BAACLgAFFH8VAAIYAAcJgBnvHQDwAQAYAAcJgBnvHQDwAQAuAAQKfygAAhgACQkFHxEsAIgCABgACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn9EAAIfAAkJ2w8pYgC3AQAfAAkJ2w8pYgC3AQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgAECgEJAQAAAA==.Hiroki:BAABLgAECn8xAAIYAAkJQQ5wTwDSAQAYAAkJQQ5wTwDSAQAAAA==.Hitachitotem:BAACLgAFFH8dAAIXAAQJARv6GABLAQAXAAQJARv6GABLAQAuAAQKfxkAAhcACAmtGl0aAEACABcACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJDwAAAA==.Hiyodad:BAAALgADCgUJBQAAAA==.Hiyodadk:BAAALgAECgIJAgAAAA==.Hiyodal:BAAALgAECgEJAQAAAA==.Hiyodam:BAAALgADCgIJAgAAAA==.Hiyodat:BAAALgAECgYJCgAAAA==.Hiyodaw:BAAALgAECgUJEAAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Hollycat:BAAALgAECgkJAgAAAA==.Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAIPAAkJ2hoqHwBXAgAPAAkJ2hoqHwBXAgAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAQJDwARAK8hAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQACACsgAA==.Holyshifts:BAAALgAECgYJCwAAAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8lAAIfAAkJxhTmQgAQAgAfAAkJxhTmQgAQAgAAAA==.',
In='Inflikted:BAABLgAECn8lAAIYAAkJVQhpdgB0AQAYAAkJVQhpdgB0AQAAAA==.Interwebz:BAABLgAECn8dAAMYAAkJHh02IgB8AgAYAAkJKxw2IgB8AgAaAAIJ9h1ePQCYAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Iz='Izztargaryen:BAAALgADCgEJAQAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgQJBAAQAAAAAA==.Jazzarin:BAAALgAECgQJBwAAAA==.',
Je='Jehannum:BAABLgAECn8wAAIXAAkJyRAfLACRAQAXAAkJyRAfLACRAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJEAAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8IAAIbAAQJfxohHwAeAQAbAAQJfxohHwAeAQABLgAFFAUJIgAEAC4lAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgAECgQJBAAAAA==.Jurkzarbirt:BAAALgAECgQJBQAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jì']='Jìnbe:BAAALgAECgYJCwAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIDAAgJ0hcLJQCgAQADAAgJ0hcLJQCgAQAAAA==.',
Ka='Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kainiy:BAAALgAECgMJBAAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgYJDgAAAA==.Kassan:BAAALgAECgYJCwAAAA==.Katarena:BAABLgAECn83AAIbAAgJVRB1MQCPAQAbAAgJVRB1MQCPAQAAAA==.Kathyra:BAABLgAECn8oAAMBAAkJ+Q4TTQCyAQABAAkJ+Q4TTQCyAQAlAAEJ7wEjNwAnAAAAAA==.Kavax:BAABLgAECn8mAAIbAAkJgxQvGQA7AgAbAAkJgxQvGQA7AgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIFAAYJlw8hKwBaAQAFAAYJlw8hKwBaAQAuAAQKfzwAAgUACQnFHoshAH4CAAUACQnFHoshAH4CAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kelorth:BAAALgADCggJCAAAAA==.Kentyr:BAABLgAECn81AAMMAAgJ5RGWHACuAQAMAAgJ5RGWHACuAQAmAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khaldormu:BAAALgAECggJBwAAAA==.Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAQJDwARAK8hAA==.Kinký:BAACLgAFFH8HAAIRAAQJYwwEJwAUAQARAAQJYwwEJwAUAQAuAAQKfy8AAxEACQk0FvsXAC0CABEACQk0FvsXAC0CABMAAQnbFINyADcAAAEuAAQKBwkTABAAAAAA.Kiraelis:BAABLgAECn8lAAIgAAkJqg/hDACQAQAgAAkJqg/hDACQAQAAAA==.Kisara:BAAALgADCggJDAABLgAFFAMJBQAFAOsNAA==.Kiss:BAAALgADCgEJAQABLgAFFAEJAQAQAAAAAA==.Kivea:BAABLgAECn8aAAMfAAkJZg+lYgC2AQAfAAkJZg+lYgC2AQAhAAEJBAcNFQAoAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Konvik:BAAALgAECgEJAQAAAA==.Kooka:BAAALgADCgEJAQAAAA==.Korvoh:BAABLgAECn9JAAMkAAkJDB3cCADkAgAkAAkJAx3cCADkAgACAAMJUxeOXQC8AAAAAA==.',
Kr='Krincess:BAAALgAECgYJCwABLgAECgkJNAAXAAAkAA==.Kringe:BAABLgAECn80AAMXAAkJACRBBAAdAwAXAAkJACRBBAAdAwAEAAEJLQSq5AAlAAAAAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumaro:BAAALgAECgIJAgAAAA==.Kumonk:BAABLgAECn8cAAIOAAcJWAYxSgDVAAAOAAcJWAYxSgDVAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBgAAAA==.',
['Kä']='Kämik:BAABLgAECn9DAAIcAAkJmSFDCgABAwAcAAkJmSFDCgABAwAAAA==.',
['Kì']='Kìn:BAABLgAECn8lAAMkAAcJ8gqZPQAVAQAkAAYJggyZPQAVAQADAAUJjwJUcgBZAAAAAA==.',
La='Lampion:BAABLgAECn8hAAIJAAkJdAwAIAB1AQAJAAkJdAwAIAB1AQAAAA==.Langris:BAAALgAECgEJAwAAAA==.Lasstchance:BAABLgAECn8ZAAIcAAcJeAxJeQBIAQAcAAcJeAxJeQBIAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8pAAIBAAkJ/h6/DgDVAgABAAkJ/h6/DgDVAgAAAA==.',
Le='Leijona:BAAALgAECgIJBQAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgAECgQJBAAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Lightbunny:BAAALgAECgMJAwAAAA==.Likeatrain:BAABLgAECn84AAInAAkJrBYiDQAVAgAnAAkJrBYiDQAVAgAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMbAAgJJRN/KADqAQAbAAgJJRN/KADqAQAFAAUJDggbCAGqAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMbAAkJOh4GFgBZAgAbAAkJOh4GFgBZAgAFAAYJTQw/5ADVAAAAAA==.Lintha:BAAALgAECgcJBgAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAABLgAECn8UAAMWAAYJKhXzOgA8AQAWAAYJKhXzOgA8AQAVAAEJ3wPmKQAkAAABLgAFFAQJDwARAK8hAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8bAAMMAAgJlBfCGgC+AQAMAAgJlBfCGgC+AQAUAAEJhxD2HwAzAAAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn89AAIOAAkJzSJaBAARAwAOAAkJzSJaBAARAwAAAA==.',
Lu='Luber:BAABLgAECn8vAAMEAAkJ7wwfQgChAQAEAAkJ7wwfQgChAQAXAAYJcguxVQDfAAAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAACLgAFFH8GAAIaAAMJFiOTFgAvAQAaAAMJFiOTFgAvAQAuAAQKf1AAAhoACQkEJsYAAGYDABoACQkEJsYAAGYDAAAA.Luxzy:BAAALgAFFAEJAQAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAABLgAECn8iAAIoAAkJPSA1CgAWAwAoAAkJPSA1CgAWAwAAAA==.Marbleous:BAACLgAFFH8KAAIRAAMJBiS7KQAIAQARAAMJBiS7KQAIAQAuAAQKfxgAAhEABgm6I9EnALsBABEABgm6I9EnALsBAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIgAoAD0gAA==.Mcspicy:BAAALgAECgUJCAAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAlAFkfAA==.Melhina:BAAALgAECgUJCQABLgAECggJOQAlANIcAA==.Memisstotem:BAABLgAECn8eAAIEAAcJgRryMQDoAQAEAAcJgRryMQDoAQAAAA==.Merle:BAACLgAFFH8PAAIRAAQJryEFDwCHAQARAAQJryEFDwCHAQAuAAQKf1QAAxEACQlUJagCAEcDABEACQkgJKgCAEcDABMABgncJDcOAAQCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8ZAAIPAAgJ7RlXKQAhAgAPAAgJ7RlXKQAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Mikethegray:BAAALgAECgYJCwABLgAECgkJTQAFACMZAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8eAAICAAcJmA2iNAAtAQACAAcJmA2iNAAtAQAAAA==.Mistborn:BAABLgAECn84AAQCAAkJiCIhCQC5AgACAAkJiCIhCQC5AgAkAAQJ1RyJKQBMAQADAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAVAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn86AAIeAAkJZCDhAgDvAgAeAAkJZCDhAgDvAgAAAA==.Monkjamin:BAABLgAFFH8GAAIiAAMJThcJNQDOAAAiAAMJThcJNQDOAAAAAA==.Moolimbo:BAABLgAECn8qAAIXAAkJghhKFgAxAgAXAAkJghhKFgAxAgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAVAKYfAA==.Mooseboy:BAABLgAECn8tAAIeAAkJah7eBACoAgAeAAkJah7eBACoAgAAAA==.Mooserton:BAACLgAFFH8FAAIbAAMJeBD3LwCwAAAbAAMJeBD3LwCwAAAuAAQKfzYAAxsACQmaHBoIAAgDABsACQmaHBoIAAgDAAUABgmsD2bYAOUAAAAA.Mootalstrike:BAABLgAECn8zAAIRAAkJbhXQHgD2AQARAAkJbhXQHgD2AQAAAA==.Moshworm:BAABLgAECn84AAIGAAkJMw8tIgC0AQAGAAkJMw8tIgC0AQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAUJEgAYAC8cAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAUJFwAcAH4bAA==.',
['Mä']='Mängo:BAAALgADCgYJBgAAAA==.',
Na='Nalaxx:BAAALgAECgkJAQAAAA==.Natsumi:BAABLgAECn8WAAIEAAcJxgsnZQAnAQAEAAcJxgsnZQAnAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIWAAYJVQPRQwDRAAAWAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAIfAAkJBh5VIgCSAgAfAAkJBh5VIgCSAgAAAA==.Neuroticaine:BAABLgAECn9RAAMDAAkJ1xe/EgA8AgADAAkJ1xe/EgA8AgAkAAQJCA5KSgDZAAAAAA==.Nev:BAACLgAFFH8SAAMcAAQJsCHjLABRAQAcAAQJsCHjLABRAQAgAAMJ6AVCGQDAAAAuAAQKfyEAAxwACAncIsYjAC8CABwABwkjIsYjAC8CACAABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8QAAIMAAQJzAtUHwAiAQAMAAQJzAtUHwAiAQAAAA==.',
Ni='Nico:BAABLgAECn8bAAIHAAkJChIjEQCxAQAHAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQlAAkJWR+BBABSAgAlAAkJUx+BBABSAgAdAAcJIBpcCgCaAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgAECgQJBAAAAA==.Nooblets:BAACLgAFFH8HAAIMAAMJ/xriJwDjAAAMAAMJ/xriJwDjAAAuAAQKfxsAAgwABwnMIOQaAL0BAAwABwnMIOQaAL0BAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMPAAkJQBKNUwCIAQAPAAkJQBKNUwCIAQAKAAIJwhSDMQA6AAAAAA==.Noxxus:BAABLgAECn8fAAISAAkJvRqdDAD9AQASAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAlAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAACLgAFFH8HAAIYAAQJugKQmADbAAAYAAQJugKQmADbAAAuAAQKfxoAAxgACQnsCi5oAJMBABgACQnsCi5oAJMBABoAAQn0AWJlABwAAAAA.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAXAIIYAA==.',
Om='Omnivus:BAAALgAECgMJBQAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgEJAgAQAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAbAFAbAA==.Oratherah:BAABLgAFFH8LAAIaAAMJziTLJQDAAAAaAAMJziTLJQDAAAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8mAAIRAAkJPiLaBgDvAgARAAkJPiLaBgDvAgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAAALgAECggJEAAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn9NAAIZAAkJiAjJEQBXAQAZAAkJiAjJEQBXAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAXAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHQAYAB4dAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIgAoAD0gAA==.Pitchblende:BAABLgAECn8xAAIbAAkJMBIZHwAIAgAbAAkJMBIZHwAIAgAAAA==.',
Po='Poeppsul:BAAALgADCgMJAwAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Polyrock:BAAALgADCgQJBAAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAYAOEkAA==.Porthub:BAABLgAECn8pAAIfAAkJLAlPdgCJAQAfAAkJLAlPdgCJAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAABLgAECn8VAAMcAAcJJREEagBpAQAcAAcJJREEagBpAQAgAAEJAAA0SAAAAAAAAA==.Rajak:BAAALgAECgIJAwAAAA==.Range:BAAALgAFFAIJAgAAAA==.Raph:BAAALgAECgYJDAAAAA==.Rathibrew:BAACLgAFFH8aAAIiAAYJMCFuCwDQAQAiAAYJMCFuCwDQAQAuAAQKfzgAAiIACQmcJLwBAIwDACIACQmcJLwBAIwDAAAA.',
Re='Reckurface:BAAALgAECgEJAQAAAA==.Redine:BAAALgAECgMJAwAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCQAAAA==.Rellt:BAAALgADCgQJBgAAAA==.Remnants:BAABLgAECn8UAAIiAAYJihvDJwDIAQAiAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8XAAQCAAgJ5gXaOwABAQACAAgJ5gXaOwABAQADAAUJEAOIawBrAAAkAAEJ4gGxhwAcAAAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgQJCAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAQAAAAAA==.Rompally:BAAALgAECgUJBQAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8SAAQYAAUJLxy1RQBjAQAYAAUJLxy1RQBjAQAZAAEJUQ0RJgBGAAAaAAEJAAAvVQAAAAAuAAQKfzEAAhgACQnGH1gqAFUCABgACQnGH1gqAFUCAAAA.',
['Rê']='Rêvolt:BAABLgAFFH8IAAIPAAIJYg7OfgB7AAAPAAIJYg7OfgB7AAAAAA==.Rêzìcå:BAAALgADCgkJCQAAAA==.',
['Rô']='Rôwdy:BAAALgAECgEJAQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAABLgAECn8ZAAMcAAgJ0gdXegBGAQAcAAgJ0gdXegBGAQAgAAQJWwGQOwAyAAAAAA==.Salezar:BAABLgAECn8rAAIVAAkJph9XAQDoAgAVAAkJph9XAQDoAgAAAA==.Sandoud:BAABLgAECn8cAAIGAAkJ6xOLGQD8AQAGAAkJ6xOLGQD8AQAAAA==.Sapientia:BAABLgAECn8tAAIFAAkJqwhTiQBbAQAFAAkJqwhTiQBbAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECggJQgAJAIsbAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIbAAQJcw/wJwDeAAAbAAQJcw/wJwDeAAAuAAQKfyEAAxsACAlaGMcZAEUCABsACAlaGMcZAEUCAAUAAQnyDycyAT8AAAEuAAUUCAkhAB8AThoA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAIJAgAAAA==.Selenesul:BAABLgAECn8sAAMFAAkJ9RzGHgCMAgAFAAkJ9RzGHgCMAgASAAMJTAynNAB0AAAAAA==.Selyda:BAAALgADCgUJBgAAAA==.Senzie:BAACLgAFFH8YAAIOAAUJex/PCwBhAQAOAAUJex/PCwBhAQAuAAQKfyUAAg4ACQkiHhgNAHECAA4ACQkiHhgNAHECAAEuAAUUBQkQAA4AChUA.Sevro:BAAALgADCgQJBAABLgAECgkJJgAbAIMUAA==.',
Sh='Shadowdrake:BAABLgAECn8ZAAIWAAkJqAoJMAB1AQAWAAkJqAoJMAB1AQAAAA==.Shadowheàrt:BAABLgAECn8gAAMbAAcJ2hXiNQB1AQAbAAYJSxXiNQB1AQAFAAQJOQWNMwF1AAAAAA==.Shadowshifty:BAABLgAECn8fAAIpAAYJdhCOLgDtAAApAAYJdhCOLgDtAAAAAA==.Shadowtotem:BAAALgAECgYJBgAAAA==.Shaeen:BAABLgAFFH8GAAIKAAMJ7AykCQCxAAAKAAMJ7AykCQCxAAAAAA==.Shagi:BAABLgAECn8nAAIiAAgJwBe0GADfAQAiAAgJwBe0GADfAQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharklee:BAAALgADCgEJAgAAAA==.Sharroz:BAABLgAECn8dAAMZAAcJiB1oAwBWAgAZAAcJiB1oAwBWAgAaAAQJVQ64QACJAAAAAA==.Shauna:BAACLgAFFH8HAAIcAAcJEgUuagDFAAAcAAcJEgUuagDFAAAuAAQKfxUAAhwACAn6DupMALcBABwACAn6DupMALcBAAAA.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMkAAgJeBrMFgAdAgAkAAgJeBrMFgAdAgADAAEJJQKaaQAlAAABLgAFFAUJEgAYAC8cAA==.Shockybalboa:BAABLgAECn8UAAIXAAcJNBMNNQBjAQAXAAcJNBMNNQBjAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBgAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skoftyia:BAAALgAECgEJAQABLgAFFAMJCAARAIIVAA==.Skooda:BAABLgAECn8tAAIXAAkJaA5YLwB/AQAXAAkJaA5YLwB/AQAAAA==.Skyded:BAABLgAECn8yAAIYAAkJLBkUMAA8AgAYAAkJLBkUMAA8AgAAAA==.Skyknight:BAABLgAECn8hAAIRAAkJnBMlKAC5AQARAAkJnBMlKAC5AQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8NAAMHAAUJjxa8EwAqAQAHAAUJjxa8EwAqAQAgAAIJBwv/JQB0AAAuAAQKfzsAAwcACQlyIzkEAOwCAAcACQlQIjkEAOwCACAACAnWHuoSAJ8CAAAA.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgADCgYJCwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8nAAIPAAkJ8RqMHwBUAgAPAAkJ8RqMHwBUAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAABLgAECn8aAAIFAAgJZxzsJwBhAgAFAAgJZxzsJwBhAgAAAA==.Soralas:BAAALgAECgcJEQAAAA==.',
Sp='Spaazz:BAABLgAECn8jAAIFAAkJsyHtEwDJAgAFAAkJsyHtEwDJAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
St='Staggerstout:BAAALgAECgEJAQAAAA==.Starweaver:BAABLgAECn8oAAMkAAkJkxJVKACOAQAkAAkJmAhVKACOAQACAAgJJhNhKgBwAQAAAA==.Stellmarine:BAABLgAECn8dAAIGAAkJzRqyGgDzAQAGAAkJzRqyGgDzAQAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgYJDQAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMpAAkJIhuICABhAgApAAkJ4RqICABhAgAGAAYJBBrnKgCqAQAAAA==.',
Su='Subzro:BAAALgAECgUJCQAAAA==.Sunamé:BAAALgAECgUJCwAAAA==.',
Sw='Swaazil:BAACLgAFFH8SAAIfAAQJVgj8agAVAQAfAAQJVgj8agAVAQAuAAQKfyYAAh8ACQkrEWNdAMQBAB8ACQkrEWNdAMQBAAAA.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgIJAgAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAQAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8eAAIPAAcJQwxfhgAPAQAPAAcJQwxfhgAPAQAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taken:BAAALgAECgYJBgAAAA==.Taloriesh:BAACLgAFFH8HAAICAAMJ3x7oFwD4AAACAAMJ3x7oFwD4AAAuAAQKfysABAIACQmlHj4IAOUCAAIACQmlHj4IAOUCAAMAAQk+FepgADYAACQAAQkdDpF3ADEAAAAA.Tanazir:BAEBLgAECn8aAAIVAAgJKhF8CQCMAQAVAAgJKhF8CQCMAQAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarivel:BAAALgAECgIJAgAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8XAAIOAAgJwA+MKgBlAQAOAAgJwA+MKgBlAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIdAAgJnBzZBAAnAgAdAAgJnBzZBAAnAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECggJGgAVACoRAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIFAAkJLBlZRQATAgAFAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8WAAIcAAcJ1AXAlgANAQAcAAcJ1AXAlgANAQAAAA==.Tilamano:BAABLgAECn87AAQdAAkJpSXpAQCwAgAdAAgJ0iTpAQCwAgAlAAgJOiTfAgCUAgABAAgJMiSHJQBGAgAAAA==.Tilthulhu:BAAALgAECgMJAwABLgAECgkJOwAdAKUlAA==.',
Tm='Tmntmikey:BAABLgAFFH8RAAQNAAYJqQ94HgBtAQANAAYJqQ94HgBtAQAiAAMJbgGtQwCOAAAOAAEJvAfBRAAzAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMcAAcJRCMZHwBLAgAcAAcJgCIZHwBLAgAgAAYJMSMUIgAVAgABLgAECgkJFwAPANoaAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAiAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAiAO8lAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAiAO8lAA==.Toopie:BAACLgAFFH8FAAIiAAEJ7yXCTQBmAAAiAAEJ7yXCTQBmAAAuAAQKfx4AAyIACAn7IWULANcCACIACAn7IWULANcCAA4ABQlvGSQ4AD0BAAAA.',
Tr='Trackdown:BAAALgAECgcJBwAAAA==.Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8qAAIoAAkJxBvxEQC8AgAoAAkJxBvxEQC8AgAAAA==.Tryath:BAABLgAECn8ZAAMoAAgJ4wpBcgDbAAAoAAcJcAhBcgDbAAAGAAQJzAn5ZQCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIdAAUJAhWbBgAsAQAdAAUJAhWbBgAsAQAuAAQKfyQAAh0ACQl8G2oCAOUCAB0ACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIHAAkJCh8hAwABAwAHAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAIPAAkJQiBfEwDlAgAPAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgcJGwAfAPsVAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn8/AAISAAkJoiMNAgAYAwASAAkJoiMNAgAYAwAAAA==.Valros:BAAALgADCgEJAQABLgAECggJJwAiAMAXAA==.Vanaras:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgQJCgABLgAECgkJHAAYAGMVAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMMAAkJnxaUFAD6AQAMAAkJshWUFAD6AQAUAAUJ8xGAEwDJAAAAAA==.Veraana:BAAALgAECgYJCwAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn9GAAIcAAkJcBuHHwBmAgAcAAkJcBuHHwBmAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8cAAMkAAYJpyVfCwBcAgAkAAYJpyVfCwBcAgADAAEJphRYNwBIAAAuAAQKfywAAyQACQnfJhEAAPkDACQACQnfJhEAAPkDAAMAAQnWIZtvAF8AAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJAwAAAA==.Vidette:BAAALgAECgEJAQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAlAFkfAA==.Viv:BAABLgAECn8pAAMSAAgJ8SK8BQCWAgASAAcJPCS8BQCWAgAFAAYJEiNWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8gAAIFAAkJjAaKkgBLAQAFAAkJjAaKkgBLAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAAALgAECggJEwAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAQJBQAWAFkPAA==.Warrendemon:BAACLgAFFH8YAAIPAAYJCiYiFAAEAgAPAAYJCiYiFAAEAgAuAAQKfzUAAw8ACQkDJrsBAMADAA8ACQkDJrsBAMADAAkAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgYJBgAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIfAAkJWBOvUgA/AgAfAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8hAAMeAAkJHyGwBACuAgAeAAkJ1SCwBACuAgApAAMJ+xSgPACtAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Woregontail:BAAALgADCggJCAAAAA==.Wowbelly:BAACLgAFFH8IAAINAAQJggzyMwDQAAANAAQJggzyMwDQAAAuAAQKfx0AAg0ABwnFG0EWABECAA0ABwnFG0EWABECAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAANAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAAALgAECgYJEQAAAA==.',
Xo='Xonk:BAACLgAFFH8XAAIlAAYJQxGeAgB3AQAlAAYJQxGeAgB3AQAuAAQKfyQAAiUACQkQICwBAPECACUACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECgkJHAAYAGMVAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEQAAAA==.',
Yu='Yuuna:BAAALgAECgYJEwAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8WAAMJAAgJYAnuKQApAQAJAAgJYAnuKQApAQAPAAYJ+QJt2wB5AAAAAA==.Zapp:BAAALgAECgYJCwAAAA==.Zaps:BAABLgAECn8pAAIIAAkJKCMYAgAEAwAIAAkJKCMYAgAEAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8cAAIfAAcJlBO5gABzAQAfAAcJlBO5gABzAQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMEAAkJ4QvzTAB4AQAEAAkJ4QvzTAB4AQAXAAcJxwhxUwDnAAAAAA==.Zenreto:BAABLgAECn9BAAIUAAkJHR87AgC+AgAUAAkJHR87AgC+AgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8YAAIfAAYJgR/4KwC/AQAfAAYJgR/4KwC/AQAuAAQKfysAAh8ACAnAJG0SADkDAB8ACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8bAAIIAAYJ/x7ZAgCvAQAIAAYJ/x7ZAgCvAQAuAAQKfzAAAggACQkGJW4AAHEDAAgACQkGJW4AAHEDAAAA.',
['Ät']='Äthena:BAAALgAECgYJCwAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8zAAMBAAkJuR1eGgCEAgABAAkJuR1eGgCEAgAdAAQJGwjCQQCuAAAAAA==.',
['Ún']='Úncle:BAAALgAECgEJAQAAAA==.',
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
