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
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE/OgAjAgABAAkJuxE/OgAjAgAAAA==.Abrakådabruh:BAAALgAECgUJBQAAAA==.Abzero:BAAALgAECgIJBQAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJCAAAAA==.Adinne:BAABLgAECn8ZAAMCAAcJyhy4JACQAQACAAUJEBy4JACQAQADAAcJOBH0LABpAQABLgAFFAYJDwAEAMwCAA==.',
Ae='Aethira:BAAALgAECgEJAwAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8+AAIFAAkJpiB0EwDFAgAFAAkJpiB0EwDFAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.Ainz:BAAALgADCgkJCQAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Alfee:BAAALgAECgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.',
Am='Amarantus:BAAALgAECgYJCQABLgAFFAMJDAAGAOAOAA==.Amarndeus:BAAALgADCgMJAwAAAA==.Ammerie:BAAALgAECgkJAgAAAA==.',
An='Anakim:BAAALgAECgQJBgAAAA==.Anmo:BAABLgAECn8VAAIHAAgJyRAHGwDAAQAHAAgJyRAHGwDAAQABLgAFFAYJGwAIAP8eAA==.Anmodru:BAAALgAECgYJBgABLgAFFAYJGwAIAP8eAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aonani:BAAALgAECggJBgAAAA==.Aotc:BAABLgAECn8WAAIJAAcJxw1rKwBsAQAJAAcJxw1rKwBsAQAAAA==.',
Ap='Apoldelon:BAAALgAECgIJAgAAAA==.',
Aq='Aquaism:BAAALgADCgIJAgAAAA==.Aqulath:BAACLgAFFH8RAAIKAAQJbx7UAgBhAQAKAAQJbx7UAgBhAQAuAAQKfxoAAgoACQnOG04EAHECAAoACQnOG04EAHECAAAA.Aquílés:BAAALgAECgEJAQAAAA==.',
Ar='Arazensetal:BAABLgAECn9EAAILAAkJyhqcBQCyAgALAAkJyhqcBQCyAgAAAA==.Arctica:BAAALgAECgIJAgABLgAFFAYJEwAMAMAPAA==.Ariandrel:BAACLgAFFH8FAAINAAMJvwZWPgCJAAANAAMJvwZWPgCJAAAuAAQKfx4AAw0ACQkdEd0oAMwBAA0ACQkdEd0oAMwBAA4AAQlbAE+OABQAAAAA.Aridhol:BAAALgAECggJEQAAAA==.Arkaedius:BAABLgAECn8bAAIPAAkJfhw5EQCvAgAPAAkJfhw5EQCvAgAAAA==.Arker:BAAALgADCgIJAgAAAA==.',
As='Asashin:BAAALgADCgcJDAABLgAECgQJBAAQAAAAAA==.Asellus:BAAALgAECgcJDAAAAA==.Ashraun:BAAALgAECgMJBgAAAA==.Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn81AAIJAAkJyyJJAwAYAwAJAAkJyyJJAwAYAwAAAA==.Atulno:BAAALgAECgYJBgAAAA==.',
Au='Aubrii:BAAALgAECgEJAQAAAA==.Aukatsang:BAACLgAFFH8OAAIOAAYJ1x6LBgCeAQAOAAYJ1x6LBgCeAQAuAAQKfyoAAg4ACQmTI10BAKMDAA4ACQmTI10BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.Auroraa:BAAALgADCgYJBgAAAA==.',
Az='Azymor:BAAALgAECgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8fAAIRAAgJ9xz+FAClAgARAAgJ9xz+FAClAgAAAA==.Bagabo:BAACLgAFFH8NAAIOAAQJvRzCEAAtAQAOAAQJvRzCEAAtAQAuAAQKfyQAAg4ACAndHpEJAN8CAA4ACAndHpEJAN8CAAAA.Baladeva:BAABLgAECn9EAAISAAkJnB7LBACgAgASAAkJnB7LBACgAgAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECgkJPgAFAKYgAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgMJAwAAAA==.',
Be='Bearhold:BAAALgAECgQJBAAAAA==.Beefy:BAAALgAECgMJBAAAAA==.Beenis:BAAALgAECgQJBQAAAA==.Beersnob:BAABLgAECn8kAAINAAkJLxY3HAAiAgANAAkJLxY3HAAiAgAAAA==.Benjam:BAACLgAFFH8TAAIPAAcJrRYLFADvAQAPAAcJrRYLFADvAQAuAAQKfygAAg8ABwnlI0wZAL0CAA8ABwnlI0wZAL0CAAAA.Benyo:BAAALgAECgQJBAAAAA==.',
Bi='Bigmikeyg:BAABLgAECn9GAAIFAAkJwhdxLQBAAgAFAAkJwhdxLQBAAgAAAA==.Bigsteve:BAABLgAECn85AAMRAAkJ8CLVAwAkAwARAAkJ8CLVAwAkAwATAAgJ1hKlGQCDAQAAAA==.',
Bl='Blanket:BAACLgAFFH8MAAMUAAMJJwrtBwDVAAAMAAMJiQWXDwD0AAAUAAMJJwrtBwDVAAAuAAQKfxYAAwwABwlSHPUqAKUBAAwABwkjHPUqAKUBABQAAwmaGgAAAAAAAAAA.Blinded:BAAALgAECgkJAwAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAMJCgARAAYkAA==.',
Br='Brewtel:BAAALgADCgcJBwABLgAECgQJBAAQAAAAAA==.Bricked:BAAALgAECgIJBAAAAA==.Brickley:BAAALgAECgEJAQABLgAFFAQJEQAKAG8eAA==.Bronzesun:BAAALgADCgYJBgAAAA==.',
Bu='Bubbahowl:BAAALgADCgEJAQAAAA==.Bukara:BAAALgAECgUJCAAAAA==.Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8jAAIEAAkJMRpxFwCCAgAEAAkJMRpxFwCCAgAAAA==.',
['Bõ']='Bõnd:BAAALgAECgYJDwAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8eAAQLAAkJHQX8IgBhAQALAAkJHQX8IgBhAQAVAAMJGgjIMgCAAAAWAAMJ0Ai9dwBjAAAAAA==.Calizon:BAAALgAECgkJEgAAAA==.Camc:BAAALgAECgQJDwAAAA==.Canowhoopass:BAABLgAECn8mAAIXAAgJvArJQAAgAQAXAAgJvArJQAAgAQAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8iAAIPAAYJTxrSIACUAQAPAAYJTxrSIACUAQAuAAQKfzYAAg8ACQkJIQ4KAPECAA8ACQkJIQ4KAPECAAAA.Cereas:BAABLgAECn8+AAIJAAgJixsCEAAXAgAJAAgJixsCEAAXAgAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgYJCAAAAA==.Chichobelo:BAABLgAFFH8NAAQYAAcJZBmMFwD+AQAYAAYJxxiMFwD+AQAZAAEJuR4uHwBXAAAaAAEJAABFTwAAAAAAAA==.Chuckrutis:BAACLgAFFH8FAAIWAAQJGw+gLgD7AAAWAAQJGw+gLgD7AAAuAAQKfyEAAxUACAlIHXAMABQCABUABglSHnAMABQCABYABQl4HJwpAJIBAAAA.',
Cl='Cliché:BAABLgAECn8dAAMbAAgJrhJHJQDTAQAbAAgJrhJHJQDTAQAFAAYJMgeF3wDSAAAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8XAAIcAAUJfhuYMwA7AQAcAAUJfhuYMwA7AQAuAAQKfyoAAhwACQk6IXYCAHEDABwACQk6IXYCAHEDAAAA.',
Co='Coldandwet:BAABLgAFFH8MAAIYAAMJDRQoggDwAAAYAAMJDRQoggDwAAAAAA==.Combination:BAABLgAECn9GAAIdAAkJsSAPAQDtAgAdAAkJsSAPAQDtAgABLgAFFAcJJgAFABAdAA==.Constrace:BAAALgAECgYJCAAAAA==.Corvenall:BAABLgAECn86AAIVAAkJlA4tCAClAQAVAAkJlA4tCAClAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECggJEwAAAA==.Crossbow:BAACLgAFFH8KAAIcAAMJJRYbTgD4AAAcAAMJJRYbTgD4AAAuAAQKf0IAAhwACQkoIBsPAMICABwACQkoIBsPAMICAAAA.Crystoph:BAAALgAECgEJAQABLgAFFAQJEQAKAG8eAA==.',
Cs='Cshepp:BAAALgADCgIJAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Cy='Cylan:BAAALgADCgYJDAABLgAECggJPgAJAIsbAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Danglyudders:BAAALgAECgUJBQAAAA==.Dante:BAAALgAECgIJAwABLgAECgkJGwAHAAoSAA==.Darkluster:BAAALgAECgUJCgAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.',
De='Deathbcmesyu:BAABLgAECn8XAAIYAAgJfxCuggBVAQAYAAgJfxCuggBVAQAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgYJEgAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demonheart:BAAALgAECgQJBAABLgAECgkJIQAeAB8hAA==.Demorian:BAAALgAECgEJAQABLgAECggJJwADANoNAA==.Deondre:BAAALgAECgQJCAAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.Devoutheart:BAAALgAECgQJBAABLgAECgkJIQAeAB8hAA==.',
Di='Diehappy:BAABLgAECn8YAAMZAAcJwwqaGQDzAAAZAAYJgwyaGQDzAAAaAAYJ/AUFOgCfAAAAAA==.Dillie:BAAALgAECgQJBAAAAA==.Disguize:BAAALgAECgQJBQAAAA==.Dismount:BAAALgAECgcJDQAAAA==.',
Do='Domevoker:BAAALgAFFAMJAwABLgAFFAYJGgAKAMUjAA==.Dompal:BAAALgAFFAIJAgABLgAFFAYJGgAKAMUjAA==.Donkystyle:BAAALgAECgQJCAAAAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dragonshark:BAAALgADCgEJAQAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAkJOQAfAH4mAA==.Drovinos:BAAALgAECgYJBgAAAA==.Druken:BAAALgAECgUJDgAAAA==.Drybonez:BAABLgAECn8UAAIfAAYJ0Aha+AAKAQAfAAYJ0Aha+AAKAQAAAA==.Drylie:BAACLgAFFH8VAAMcAAYJMSQSIQBrAQAcAAUJCCQSIQBrAQAgAAIJSR9kJABrAAAuAAQKfyMAAyAACQm3JNIJAAYDACAACAmdItIJAAYDABwAAwlvIxKVAAgBAAAA.Dràgonkíng:BAABLgAECn8aAAMhAAgJDQVqCQDXAAAhAAgJDQVqCQDXAAAfAAEJOwC/iwEGAAAAAA==.',
Dt='Dtinnel:BAABLgAECn8nAAIRAAkJWRw3EgBcAgARAAkJWRw3EgBcAgABLgAFFAUJEgAYAC8cAA==.',
Du='Dumbledussy:BAABLgAECn8nAAIDAAgJ2g1qLQBmAQADAAgJ2g1qLQBmAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.Dustinterp:BAAALgAECgYJCAAAAA==.',
Ed='Edanor:BAAALgAECgQJBQABLgAECgkJKwAVAKYfAA==.',
Eg='Ego:BAABLgAECn83AAIRAAkJMiSzBgDrAgARAAkJMiSzBgDrAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elrondo:BAAALgAECgEJAQAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAfAHciAA==.Emmone:BAAALgAECgUJDwAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.',
En='Endo:BAAALgAECgEJAQAAAA==.Entuidax:BAAALgAFFAIJAgABLgAFFAQJDAAiAO4TAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAABLgAECn8UAAIdAAcJihWSCgCLAQAdAAcJihWSCgCLAQAAAA==.Excaleon:BAAALgAECgUJCgAAAA==.',
Fa='Faker:BAAALgAECgYJDgAAAA==.Farglight:BAAALgAECgQJBAAAAA==.Faunna:BAACLgAFFH8MAAIGAAMJ4A7LLgCzAAAGAAMJ4A7LLgCzAAAuAAQKfz0AAgYACQmEIOUGAN8CAAYACQmEIOUGAN8CAAAA.',
Fe='Feath:BAAALgAECgkJAQAAAA==.Feebeeboofae:BAAALgAECgIJAgAAAA==.Felaz:BAABLgAECn82AAIjAAkJJCDtAADJAgAjAAkJJCDtAADJAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.Ferreii:BAAALgAECgUJBgAAAA==.',
Fi='Fingerguns:BAACLgAFFH8GAAIkAAMJMQQ8MwCkAAAkAAMJMQQ8MwCkAAAuAAQKfx0ABCQACQndFbERAE0CACQACQndFbERAE0CAAIAAwl3CO5mAJEAAAMAAwkJCDNtAFsAAAAA.Fionaa:BAABLgAECn8dAAMBAAkJOAXWeABCAQABAAkJDQXWeABCAQAdAAEJsAfxeAAqAAAAAA==.Fiyona:BAAALgAECgMJBgAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgAECgQJBAAAAA==.Floortank:BAABLgAECn8vAAMYAAgJFQiXmQAtAQAYAAgJAQaXmQAtAQAZAAcJBQi4GQDyAAAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAACLgAFFH8LAAIbAAMJUBv6JgDhAAAbAAMJUBv6JgDhAAAuAAQKfxsAAhsABwnKI4sRAIcCABsABwnKI4sRAIcCAAAA.Frikilatar:BAAALgAECgEJBwAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAQAAAAAA==.Frrank:BAACLgAFFH8aAAITAAYJwyUUBQD8AQATAAYJwyUUBQD8AQAuAAQKfzQAAhMACQkoJWEAALQDABMACQkoJWEAALQDAAAA.',
Fu='Fullerene:BAAALgAECgEJAgAAAA==.',
Ga='Galcain:BAACLgAFFH8GAAMcAAMJbR0ZTgD4AAAcAAMJbR0ZTgD4AAAHAAMJtQ8LIQC4AAAuAAQKfy4ABBwACQnwIfYHABEDABwACAm2IvYHABEDAAcACAkHFtUWAOgBACAAAwlUGtBgAL0AAAAA.Galkhan:BAAALgAECgQJBAABLgAFFAMJBgAcAG0dAA==.Gardonea:BAAALgADCggJDgAAAA==.',
Gh='Ghostmain:BAAALgAECgQJBgABLgAECgcJAgAQAAAAAA==.',
Gi='Gintoko:BAAALgAECgMJBgAAAA==.Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8mAAIfAAgJhxPgbACaAQAfAAgJhxPgbACaAQAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.Glamor:BAAALgAECgQJBAAAAA==.',
Go='Gorizarev:BAAALgAECgQJCgAAAA==.',
Gr='Grimseek:BAAALgAECgUJBQABLgAFFAcJJgAFABAdAA==.Grippysox:BAAALgADCgYJBgAAAA==.Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn9FAAIeAAkJOxvFBQCFAgAeAAkJOxvFBQCFAgAAAA==.',
Gu='Guce:BAAALgAECgcJDgAAAA==.Gudetama:BAABLgAECn8bAAMcAAkJsCDBFwB7AgAcAAYJESPBFwB7AgAHAAcJwx15DgA/AgAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgYJCgAAAA==.Haidie:BAAALgAECgQJBAAAAA==.Hakur:BAABLgAECn87AAIFAAkJQhz+LABCAgAFAAkJQhz+LABCAgAAAA==.Hamahara:BAAALgAECgYJBwAAAA==.Hanma:BAACLgAFFH8VAAIYAAcJgBk2GQD0AQAYAAcJgBk2GQD0AQAuAAQKfygAAhgACQkFHxEsAIgCABgACQkFHxEsAIgCAAAA.Harribel:BAABLgAECn89AAIfAAkJsQ/uXQC/AQAfAAkJsQ/uXQC/AQAAAA==.',
He='Heimdall:BAAALgADCgQJAQAAAA==.Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.Heresbrucey:BAAALgADCgEJAQAAAA==.',
Hi='Higheleazar:BAAALgAECgEJAQAAAA==.Hiroki:BAABLgAECn8oAAIYAAgJ9gutdQBwAQAYAAgJ9gutdQBwAQAAAA==.Hitachitotem:BAACLgAFFH8ZAAIXAAQJehZPHQAgAQAXAAQJehZPHQAgAQAuAAQKfxkAAhcACAmtGl0aAEACABcACAmtGl0aAEACAAAA.Hiyoda:BAAALgAECgYJDwAAAA==.Hiyodad:BAAALgADCgUJBQAAAA==.Hiyodadk:BAAALgADCgYJBgAAAA==.Hiyodal:BAAALgAECgEJAQAAAA==.Hiyodam:BAAALgADCgEJAQAAAA==.Hiyodat:BAAALgAECgMJAwAAAA==.Hiyodaw:BAAALgAECgUJCwAAAA==.Hizzon:BAAALgADCgcJDAAAAA==.',
Ho='Hollycat:BAAALgAECgkJAgAAAA==.Holous:BAAALgAECgYJCAAAAA==.Holybjoly:BAABLgAECn8XAAIPAAkJ2hrpHQBXAgAPAAkJ2hrpHQBXAgAAAA==.Holymaet:BAAALgADCgEJAQABLgAFFAQJDgARAK8hAA==.Holyphatso:BAAALgADCgMJAwABLgAECgkJKQACACsgAA==.Holyshifts:BAAALgAECgUJBQAAAA==.',
Hy='Hyperíon:BAAALgAECgYJCwAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAABLgAECn8lAAIfAAkJxhQOPwAZAgAfAAkJxhQOPwAZAgAAAA==.',
In='Inflikted:BAABLgAECn8lAAIYAAkJVQi+cAB6AQAYAAkJVQi+cAB6AQAAAA==.Interwebz:BAABLgAECn8cAAMYAAkJHh0fIACBAgAYAAkJKxwfIACBAgAaAAIJ9h02OwCaAAAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgAECgQJBAAQAAAAAA==.Jazzarin:BAAALgAECgMJAwAAAA==.',
Je='Jehannum:BAABLgAECn8pAAIXAAkJJA+KLQB/AQAXAAkJJA+KLQB/AQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJEAAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAABLgAFFH8IAAIbAAQJfxpjHQAnAQAbAAQJfxpjHQAnAQABLgAFFAUJHQAEAC4lAA==.Josen:BAAALgAECgEJAQAAAA==.',
Ju='Juliana:BAAALgAECgQJBAAAAA==.Jurkzarbirt:BAAALgAECgMJAwAAAA==.',
Jz='Jz:BAAALgAECgQJBwAAAA==.',
['Jì']='Jìnbe:BAAALgAECgUJBQAAAA==.',
['Jú']='Júdâs:BAABLgAECn8cAAIDAAgJ0heCIgCsAQADAAgJ0heCIgCsAQAAAA==.',
Ka='Kaelibrimbor:BAAALgAECgcJBwAAAA==.Kaelon:BAAALgAECgEJAQAAAA==.Kaeläni:BAAALgAECgQJBwAAAA==.Kainiy:BAAALgAECgEJAQAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Kamrudy:BAAALgAECgYJDQAAAA==.Kassan:BAAALgAECgUJBQAAAA==.Katarena:BAABLgAECn83AAIbAAgJVRABMACPAQAbAAgJVRABMACPAQAAAA==.Kathyra:BAABLgAECn8nAAMBAAkJ6g6ISgC2AQABAAkJ6g6ISgC2AQAlAAEJ7wEjNwAnAAAAAA==.Kavax:BAABLgAECn8lAAIbAAkJXxROGQAwAgAbAAkJXxROGQAwAgAAAA==.',
Ke='Keel:BAAALgAECggJEgAAAA==.Keeller:BAACLgAFFH8TAAIFAAYJlw/wJABgAQAFAAYJlw/wJABgAQAuAAQKfzsAAgUACQnFHkkfAIECAAUACQnFHkkfAIECAAAA.Keggor:BAAALgAECgEJAgAAAA==.Kentyr:BAABLgAECn8yAAMMAAgJZBHfGwCqAQAMAAgJZBHfGwCqAQAmAAIJZwGDDgA0AAAAAA==.Keolus:BAAALgAECgQJBQAAAA==.',
Kh='Khasket:BAAALgAECgYJDgAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgAECgMJAwABLgAFFAQJDgARAK8hAA==.Kinký:BAACLgAFFH8FAAIRAAMJWg/CLwDdAAARAAMJWg/CLwDdAAAuAAQKfy8AAxEACQk0FrYWADMCABEACQk0FrYWADMCABMAAQnbFAhtADcAAAEuAAQKBwkTABAAAAAA.Kiraelis:BAABLgAECn8lAAIgAAkJqg9JDACTAQAgAAkJqg9JDACTAQAAAA==.Kisara:BAAALgADCgYJCgABLgAFFAMJBQAFAOsNAA==.Kiss:BAAALgADCgEJAQABLgAFFAEJAQAQAAAAAA==.Kivea:BAABLgAECn8aAAMfAAkJZg9TXQDBAQAfAAkJZg9TXQDBAQAhAAEJBAfeEwApAAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Koi:BAAALgAECggJDwAAAA==.Konagda:BAAALgADCggJEQAAAA==.Konvik:BAAALgAECgEJAQAAAA==.Korvoh:BAABLgAECn9GAAMkAAkJDB11CADkAgAkAAkJAx11CADkAgACAAMJUxeOXQC8AAAAAA==.',
Kr='Krincess:BAAALgAECgUJBQABLgAECgkJLQAXAEQjAA==.Kringe:BAABLgAECn8tAAMXAAkJRCPCBAAKAwAXAAkJRCPCBAAKAwAEAAEJLQTI2gAlAAAAAA==.Krynn:BAAALgAECgYJBgAAAA==.',
Ku='Kumonk:BAABLgAECn8cAAIOAAcJWAZaRwDVAAAOAAcJWAZaRwDVAAAAAA==.',
Ky='Kyloris:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämik:BAABLgAECn9DAAIcAAkJmSEVCQAIAwAcAAkJmSEVCQAIAwAAAA==.',
['Kì']='Kìn:BAABLgAECn8aAAMkAAYJsAZ2RADmAAAkAAYJsAZ2RADmAAADAAIJbwP7dgBAAAAAAA==.',
La='Lampion:BAABLgAECn8hAAIJAAkJdAxtHgB1AQAJAAkJdAxtHgB1AQAAAA==.Langris:BAAALgAECgEJAgAAAA==.Lasstchance:BAABLgAECn8ZAAIcAAcJeAxbcwBNAQAcAAcJeAxbcwBNAQAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8pAAIBAAkJ/h7ADQDZAgABAAkJ/h7ADQDZAgAAAA==.',
Le='Leijona:BAAALgAECgIJBAAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgAECgQJBAAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Likeatrain:BAABLgAECn8vAAInAAkJdxAKFQCVAQAnAAkJdxAKFQCVAQAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMbAAgJJRN/KADqAQAbAAgJJRN/KADqAQAFAAUJDggO/wCqAAAAAA==.Lilwagyu:BAAALgAFFAMJBAAAAA==.Linds:BAABLgAECn85AAMbAAkJOh4EFQBaAgAbAAkJOh4EFQBaAgAFAAYJTQxV3ADVAAAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgcJEgAAAA==.Littlefoot:BAAALgAECgYJEgABLgAFFAQJDgARAK8hAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAABLgAECn8bAAMMAAgJlBeBGQC/AQAMAAgJlBeBGQC/AQAUAAEJhxD2HwAzAAAAAA==.Lorralen:BAAALgAECggJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn82AAIOAAkJbSJ2BAAIAwAOAAkJbSJ2BAAIAwAAAA==.',
Lu='Luber:BAABLgAECn8pAAIEAAkJ7wynPwChAQAEAAkJ7wynPwChAQAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAABLgAECn9LAAIaAAkJ9SXcAABjAwAaAAkJ9SXcAABjAwAAAA==.Luxzy:BAAALgAFFAEJAQAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAABLgAECn8hAAIoAAkJPSC3CQAXAwAoAAkJPSC3CQAXAwAAAA==.Marbleous:BAACLgAFFH8KAAIRAAMJBiRpJgAKAQARAAMJBiRpJgAKAQAuAAQKfxgAAhEABgm6I64mAL0BABEABgm6I64mAL0BAAAA.Marina:BAAALgADCgcJDQAAAA==.',
Mc='Mcgrips:BAAALgAECgEJAQAAAA==.Mcpink:BAAALgAECgQJCAABLgAECgkJIQAoAD0gAA==.Mcspicy:BAAALgAECgMJAwAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgkJHQAlAFkfAA==.Melhina:BAAALgAECgUJCQABLgAECggJNwAlAL8cAA==.Memisstotem:BAABLgAECn8eAAIEAAcJgRrDLwDoAQAEAAcJgRrDLwDoAQAAAA==.Merle:BAACLgAFFH8OAAIRAAQJryFqDACOAQARAAQJryFqDACOAQAuAAQKf1MAAxEACQkNJY0CAEQDABEACQnYI40CAEQDABMABgncJHANAAcCAAAA.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAABLgAECn8ZAAIPAAgJ7RmeJwAhAgAPAAgJ7RmeJwAhAgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Mikethegray:BAAALgAECgUJBQABLgAECgkJRgAFAMIXAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAABLgAECn8eAAICAAcJmA23MgAvAQACAAcJmA23MgAvAQAAAA==.Mistborn:BAABLgAECn84AAQCAAkJiCIhCQC5AgACAAkJiCIhCQC5AgAkAAQJ1RyJKQBMAQADAAIJsBXIUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Modinn:BAAALgAECgEJAQABLgAECgkJKwAVAKYfAA==.Mojoe:BAAALgAECgEJAQAAAA==.Momoku:BAABLgAECn8zAAIeAAkJkR7CAwDGAgAeAAkJkR7CAwDGAgAAAA==.Monkjamin:BAABLgAFFH8GAAIiAAMJThc7MgDSAAAiAAMJThc7MgDSAAAAAA==.Moolimbo:BAABLgAECn8qAAIXAAkJghgWFQAyAgAXAAkJghgWFQAyAgAAAA==.Moonfawn:BAAALgAECgIJAgABLgAECgkJKwAVAKYfAA==.Mooseboy:BAABLgAECn8tAAIeAAkJah6BBACrAgAeAAkJah6BBACrAgAAAA==.Mooserton:BAABLgAECn80AAMbAAkJDBojCgDfAgAbAAkJDBojCgDfAgAFAAYJrA/j0ADlAAAAAA==.Mootalstrike:BAABLgAECn8zAAIRAAkJbhUWHQD/AQARAAkJbhUWHQD/AQAAAA==.Moshworm:BAABLgAECn8vAAIGAAkJ0QwCLQBhAQAGAAkJ0QwCLQBhAQAAAA==.',
Mu='Muramasa:BAAALgAECgEJAQABLgAFFAUJEgAYAC8cAA==.Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAUJFwAcAH4bAA==.',
Na='Nalaxx:BAAALgAECgEJAQAAAA==.Natsumi:BAABLgAECn8WAAIEAAcJxguGYQAnAQAEAAcJxguGYQAnAQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIWAAYJVQPRQwDRAAAWAAYJVQPRQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn84AAIfAAkJBh6eIACWAgAfAAkJBh6eIACWAgAAAA==.Neuroticaine:BAABLgAECn9KAAMDAAkJPRcFFAAoAgADAAkJPRcFFAAoAgAkAAQJCA7eRgDaAAAAAA==.Nev:BAACLgAFFH8SAAMcAAQJsCG7JgBZAQAcAAQJsCG7JgBZAQAgAAMJ6AVCGQDAAAAuAAQKfyEAAxwACAncIsYjAC8CABwABwkjIsYjAC8CACAABwmhHLEkAAICAAAA.Nexassin:BAABLgAFFH8NAAIMAAMJQgrwKQC/AAAMAAMJQgrwKQC/AAAAAA==.',
Ni='Nico:BAABLgAECn8bAAIHAAkJChIjEQCxAQAHAAkJChIjEQCxAQAAAA==.Nimz:BAABLgAECn8dAAQlAAkJWR8UBABVAgAlAAkJUx8UBABVAgAdAAcJIBqdCQCdAQABAAIJrRPO7ACBAAAAAA==.',
No='Noctrine:BAAALgAECgQJBAAAAA==.Nooblets:BAACLgAFFH8HAAIMAAMJ/xogJQDoAAAMAAMJ/xogJQDoAAAuAAQKfxsAAgwABwnMIJgZAL4BAAwABwnMIJgZAL4BAAAA.Noradia:BAAALgAECgMJBAAAAA==.Noxxic:BAAALgAECgcJCgAAAA==.Noxxidari:BAABLgAECn8iAAMPAAkJQBKkUACIAQAPAAkJQBKkUACIAQAKAAIJwhRILwA6AAAAAA==.Noxxus:BAABLgAECn8fAAISAAkJvRqdDAD9AQASAAkJvRqdDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgkJHQAlAFkfAA==.Nyrunde:BAAALgAECgIJAwAAAA==.',
['Nô']='Nôpmage:BAAALgAECgYJBQAAAA==.Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBgAAAA==.',
Of='Offended:BAABLgAECn8UAAMYAAkJpgUOiwBGAQAYAAkJpgUOiwBGAQAaAAEJ9AEPYQAdAAAAAA==.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Ol='Olimbo:BAAALgAECgUJBgABLgAECgkJKgAXAIIYAA==.',
Om='Omnivus:BAAALgAECgMJBAAAAA==.',
On='One:BAAALgADCgMJAwAAAA==.Oneeyedwilli:BAAALgAECgIJAgAAAA==.',
Op='Opinion:BAAALgADCgMJAwABLgAECgEJAgAQAAAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCwAbAFAbAA==.Oratherah:BAABLgAFFH8LAAIaAAMJziQJIwDEAAAaAAMJziQJIwDEAAAAAA==.Orbs:BAAALgAECgEJAQAAAA==.Orchist:BAABLgAECn8lAAIRAAkJPiI9BgD0AgARAAkJPiI9BgD0AgAAAA==.',
Ow='Owlyheals:BAAALgADCgQJBAAAAA==.',
Oz='Ozôls:BAAALgAECggJDwAAAA==.',
Pa='Paidu:BAAALgAECgcJBwAAAA==.Palei:BAAALgAECgYJBgAAAA==.Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn9GAAIZAAkJiAhtEABbAQAZAAkJiAhtEABbAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgkJKgAXAIIYAA==.',
Ph='Phenothal:BAAALgADCgIJAgAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgkJHAAYAB4dAA==.Pinkymcpink:BAAALgAECgEJAQABLgAECgkJIQAoAD0gAA==.Pitchblende:BAABLgAECn8xAAIbAAkJMBLnHQAJAgAbAAkJMBLnHQAJAgAAAA==.',
Po='Poeppsul:BAAALgADCgMJAwAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Pooqi:BAAALgAECgMJAwABLgAFFAUJEAAYAOEkAA==.Porthub:BAABLgAECn8pAAIfAAkJLAlucACTAQAfAAkJLAlucACTAQAAAA==.',
Pr='Protagoras:BAAALgAECgcJBwAAAA==.',
Pu='Purejoy:BAAALgAECgcJDwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qq='Qqcumber:BAAALgADCgIJAgAAAA==.',
Qu='Quillz:BAAALgAECgIJBAAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAABLgAECn8VAAMcAAcJJRF1ZQBsAQAcAAcJJRF1ZQBsAQAgAAEJAABsRQAAAAAAAA==.Rajak:BAAALgAECgIJAwAAAA==.Range:BAAALgAECgUJBgAAAA==.Raph:BAAALgAECgUJBgAAAA==.Rathibrew:BAACLgAFFH8aAAIiAAYJMCFuCQDVAQAiAAYJMCFuCQDVAQAuAAQKfzgAAiIACQmcJLwBAIwDACIACQmcJLwBAIwDAAAA.',
Re='Reckurface:BAAALgAECgEJAQAAAA==.Redine:BAAALgAECgMJAwAAAA==.Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCQAAAA==.Rellt:BAAALgADCgIJAgAAAA==.Remnants:BAABLgAECn8UAAIiAAYJihvDJwDIAQAiAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.Revanchist:BAABLgAECn8XAAQCAAgJ5gXrOQACAQACAAgJ5gXrOQACAQADAAUJEAP5ZQBxAAAkAAEJ4gG6gAAcAAAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBwAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgAECgIJAgAAAA==.',
Ro='Rockyx:BAAALgAECgQJCAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAQJBAAQAAAAAA==.Rompally:BAAALgAECgUJBQAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAACLgAFFH8SAAQYAAUJLxxLPABsAQAYAAUJLxxLPABsAQAZAAEJUQ26IQBGAAAaAAEJAAAgTwAAAAAuAAQKfzEAAhgACQnGHyYoAFkCABgACQnGHyYoAFkCAAAA.',
['Rê']='Rêzìcå:BAAALgADCgkJCQAAAA==.',
['Rô']='Rôwdy:BAAALgAECgEJAQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAABLgAECn8WAAMcAAcJuAV2kwALAQAcAAcJuAV2kwALAQAgAAQJWwGAOQAyAAAAAA==.Salezar:BAABLgAECn8rAAIVAAkJph9FAQDqAgAVAAkJph9FAQDqAgAAAA==.Sandoud:BAABLgAECn8cAAIGAAkJ6xNYGAD+AQAGAAkJ6xNYGAD+AQAAAA==.Sapientia:BAABLgAECn8tAAIFAAkJqwhhgwBdAQAFAAkJqwhhgwBdAQAAAA==.Saragon:BAAALgAECgcJDQABLgAECggJPgAJAIsbAA==.Satheion:BAAALgADCgkJCwAAAA==.Savagex:BAAALgADCgEJAQAAAA==.',
Sc='Scottkill:BAACLgAFFH8GAAIbAAQJcw/AJADvAAAbAAQJcw/AJADvAAAuAAQKfyEAAxsACAlaGMcZAEUCABsACAlaGMcZAEUCAAUAAQnyDycyAT8AAAEuAAUUCAkhAB8AThoA.',
Se='Sebaux:BAAALgAECgQJCwAAAA==.Segur:BAAALgAFFAIJAgAAAA==.Selenesul:BAABLgAECn8sAAMFAAkJ9RyOHACPAgAFAAkJ9RyOHACPAgASAAMJTAynNAB0AAAAAA==.Selyda:BAAALgADCgUJBgAAAA==.Senzie:BAACLgAFFH8TAAIOAAQJex90CgBpAQAOAAQJex90CgBpAQAuAAQKfyUAAg4ACQkiHnEMAHMCAA4ACQkiHnEMAHMCAAEuAAUUBQkQAA4AChUA.Sevro:BAAALgADCgQJBAABLgAECgkJJQAbAF8UAA==.',
Sh='Shadowdrake:BAABLgAECn8ZAAIWAAkJqArRLQB5AQAWAAkJqArRLQB5AQAAAA==.Shadowheàrt:BAABLgAECn8eAAMbAAcJ2hU8NAB2AQAbAAYJSxU8NAB2AQAFAAQJOQUJKQF1AAAAAA==.Shadowshifty:BAABLgAECn8fAAIpAAYJdhDeKwDuAAApAAYJdhDeKwDuAAAAAA==.Shadowtotem:BAAALgAECgYJBgAAAA==.Shaeen:BAABLgAFFH8FAAIKAAMJNwiVCgCNAAAKAAMJNwiVCgCNAAAAAA==.Shagi:BAABLgAECn8jAAIiAAgJoRdKGADdAQAiAAgJoRdKGADdAQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharkantor:BAAALgADCgEJAQAAAA==.Sharklee:BAAALgADCgEJAgAAAA==.Sharroz:BAABLgAECn8dAAMZAAcJiB1oAwBWAgAZAAcJiB1oAwBWAgAaAAQJVQ4JPgCNAAAAAA==.Shauna:BAAALgAFFAEJAQAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8hAAMkAAgJeBrSFQAeAgAkAAgJeBrSFQAeAgADAAEJJQKaaQAlAAABLgAFFAUJEgAYAC8cAA==.Shockybalboa:BAABLgAECn8UAAIXAAcJNBOrMgBjAQAXAAcJNBOrMgBjAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Silvver:BAAALgAECgMJBgAAAA==.Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skooda:BAABLgAECn8tAAIXAAkJaA5qLQB/AQAXAAkJaA5qLQB/AQAAAA==.Skyded:BAABLgAECn8yAAIYAAkJLBlYLQBBAgAYAAkJLBlYLQBBAgAAAA==.Skyknight:BAABLgAECn8hAAIRAAkJnBM/JgC/AQARAAkJnBM/JgC/AQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAACLgAFFH8LAAMHAAQJZBaFEgApAQAHAAQJZBaFEgApAQAgAAIJBwvMIgB6AAAuAAQKfzsAAwcACQlyI9gDAPICAAcACQlQItgDAPICACAACAnWHuoSAJ8CAAAA.',
Sn='Snapahead:BAAALgAECgQJBAAAAA==.Sneakytony:BAAALgADCgcJBwAAAA==.Snowclaw:BAAALgADCgYJCwAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8nAAIPAAkJ8RpLHgBUAgAPAAkJ8RpLHgBUAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAABLgAECn8TAAIFAAgJjBkvOwAMAgAFAAgJjBkvOwAMAgAAAA==.Soralas:BAAALgAECgcJEQAAAA==.',
Sp='Spaazz:BAABLgAECn8jAAIFAAkJsyFsEgDMAgAFAAkJsyFsEgDMAgAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.Spuds:BAAALgAECgEJAQAAAA==.',
St='Starweaver:BAABLgAECn8oAAMkAAkJkxJAJgCRAQAkAAkJmAhAJgCRAQACAAgJJhP1KABxAQAAAA==.Stellmarine:BAABLgAECn8dAAIGAAkJzRptGQD0AQAGAAkJzRptGQD0AQAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgYJDAAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8yAAMpAAkJIhv+BwBiAgApAAkJ4Rr+BwBiAgAGAAYJBBrnKgCqAQAAAA==.',
Su='Subzro:BAAALgAECgUJCQAAAA==.Sunamé:BAAALgAECgUJCwAAAA==.',
Sw='Swaazil:BAACLgAFFH8KAAIfAAMJ8wX7hADFAAAfAAMJ8wX7hADFAAAuAAQKfyYAAh8ACQkrEVRYAM4BAB8ACQkrEVRYAM4BAAAA.Swan:BAAALgAFFAIJBAAAAA==.Sweetlady:BAAALgAECgIJAgAAAA==.Swiftsama:BAAALgAECgEJAQABLgAECgcJEAAQAAAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAABLgAECn8cAAIPAAcJuwp9iAABAQAPAAcJuwp9iAABAQAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taken:BAAALgAECgYJBgAAAA==.Taloriesh:BAACLgAFFH8HAAICAAMJ3x7aFQD9AAACAAMJ3x7aFQD9AAAuAAQKfysABAIACQmlHqEHAOgCAAIACQmlHqEHAOgCAAMAAQk+FepgADYAACQAAQkdDr9wADMAAAAA.Tanazir:BAEBLgAECn8WAAIVAAgJxg3gDAA2AQAVAAgJxg3gDAA2AQAAAA==.Taric:BAAALgAECgIJAgAAAA==.Tarivel:BAAALgAECgEJAQAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAABLgAECn8XAAIOAAgJwA9sKABpAQAOAAgJwA9sKABpAQAAAA==.',
Te='Techytechy:BAABLgAECn8eAAIdAAgJnBx7BAArAgAdAAgJnBx7BAArAgAAAA==.Tenebris:BAEALgAECgMJAwABLgAECggJFgAVAMYNAA==.Tennmage:BAAALgAECgEJAQAAAA==.Terenii:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrakk:BAAALgAECgQJBAAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8aAAIFAAkJLBlZRQATAgAFAAkJLBlZRQATAgAAAA==.',
Ti='Tigermaster:BAABLgAECn8WAAIcAAcJ1AUkkAASAQAcAAcJ1AUkkAASAQAAAA==.Tilamano:BAABLgAECn87AAQdAAkJpSW/AQC1AgAdAAgJ0iS/AQC1AgAlAAgJOiSdAgCXAgABAAgJMiQeJABJAgAAAA==.Tilthulhu:BAAALgAECgMJAwABLgAECgkJOwAdAKUlAA==.',
Tm='Tmntmikey:BAABLgAFFH8PAAMNAAUJ5Q+LIgAqAQANAAUJ5Q+LIgAqAQAiAAMJbgHjQACQAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMcAAcJRCMZHwBLAgAcAAcJgCIZHwBLAgAgAAYJMSMUIgAVAgABLgAECgkJFwAPANoaAA==.Tonberry:BAAALgAECgkJBgAAAA==.Tonycheeks:BAAALgAECgQJBQAAAA==.Tonyhunter:BAAALgADCgYJBgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJBQAiAO8lAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJBQAiAO8lAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJBQAiAO8lAA==.Toopie:BAACLgAFFH8FAAIiAAEJ7yXnSgBnAAAiAAEJ7yXnSgBnAAAuAAQKfx4AAyIACAn7IWULANcCACIACAn7IWULANcCAA4ABQlvGSQ4AD0BAAAA.',
Tr='Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8qAAIoAAkJxBtCEQC9AgAoAAkJxBtCEQC9AgAAAA==.Tryath:BAABLgAECn8ZAAMoAAgJ4wozbwDdAAAoAAcJcAgzbwDdAAAGAAQJzAlpYgCAAAAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.Turtlegrnade:BAAALgADCgEJAQAAAA==.Tuzzyfits:BAAALgAECgEJAQAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8OAAIdAAUJAhXRBQAuAQAdAAUJAhXRBQAuAQAuAAQKfyQAAh0ACQl8G2oCAOUCAB0ACQl8G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8aAAIHAAkJCh8hAwABAwAHAAkJCh8hAwABAwAAAA==.',
Ul='Ultimapriest:BAAALgAECgYJDwAAAA==.',
Um='Umbrute:BAABLgAECn8rAAIPAAkJQiBfEwDlAgAPAAkJQiBfEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgcJGQAfALkVAA==.',
Va='Vader:BAAALgAECgMJAwAAAA==.Valcristo:BAABLgAECn8/AAISAAkJoiPhAQAaAwASAAkJoiPhAQAaAwAAAA==.Valros:BAAALgADCgEJAQABLgAECggJIwAiAKEXAA==.Vanaras:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgQJBgABLgAECggJFwAYAH8QAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8qAAMMAAkJnxaSEwD7AQAMAAkJshWSEwD7AQAUAAUJ8xGAEwDJAAAAAA==.Veraana:BAAALgAECgUJBQAAAA==.Verdraxa:BAAALgAECgEJAQAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn8/AAIcAAkJcBvwHABtAgAcAAkJcBvwHABtAgAAAA==.',
Vi='Vicariana:BAACLgAFFH8bAAIkAAYJpyUqCQBkAgAkAAYJpyUqCQBkAgAuAAQKfywAAyQACQnfJhEAAPkDACQACQnfJhEAAPkDAAMAAQnWIRZrAGAAAAAA.Vicdoom:BAAALgAECgYJBgAAAA==.Vichoot:BAAALgAFFAIJAwAAAA==.Vidette:BAAALgAECgEJAQAAAA==.Viduus:BAAALgAECgQJBgABLgAECgkJHQAlAFkfAA==.Viv:BAABLgAECn8nAAMSAAgJ8SK8BQCWAgASAAcJPCS8BQCWAgAFAAYJEiNWOQA+AgAAAA==.',
Vo='Vodmor:BAABLgAECn8dAAIFAAkJGgbmkQBDAQAFAAkJGgbmkQBDAQAAAA==.Voideddn:BAAALgADCgYJBgAAAA==.Voldermort:BAAALgAECgcJEgAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgUJBQAAAA==.Wallzi:BAAALgAECgYJEwABLgAFFAQJBQAWAFkPAA==.Warrendemon:BAACLgAFFH8YAAIPAAYJCiaWEAAMAgAPAAYJCiaWEAAMAgAuAAQKfzUAAw8ACQkDJrsBAMADAA8ACQkDJrsBAMADAAkAAwn9InlDAOkAAAAA.Waygun:BAAALgADCgYJBgAAAA==.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIfAAkJWBOvUgA/AgAfAAkJWBOvUgA/AgAAAA==.Wildheart:BAABLgAECn8hAAMeAAkJHyFQBACyAgAeAAkJ1SBQBACyAgApAAMJ+xQwOQCtAAAAAA==.Wilker:BAAALgADCgEJAQAAAA==.Wissa:BAAALgAECggJCAAAAA==.',
Wo='Wowbelly:BAACLgAFFH8IAAINAAQJggz6LgDTAAANAAQJggz6LgDTAAAuAAQKfx0AAg0ABwnFG0EWABECAA0ABwnFG0EWABECAAAA.Wowbellyjr:BAAALgAFFAEJAQABLgAFFAQJCAANAIIMAA==.',
Xa='Xaanii:BAAALgADCgcJCAAAAA==.Xandon:BAAALgAECgUJCgAAAA==.',
Xo='Xonk:BAACLgAFFH8XAAIlAAYJQxH+AQCFAQAlAAYJQxH+AQCFAQAuAAQKfyQAAiUACQkQICwBAPECACUACQkQICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgYJCAAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECggJFwAYAH8QAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgYJEQAAAA==.',
Yu='Yuuna:BAAALgAECgQJDAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAABLgAECn8UAAMJAAcJQQhrMQDrAAAJAAcJQQhrMQDrAAAPAAYJ+QKa0wB5AAAAAA==.Zapp:BAAALgAECgUJBQAAAA==.Zaps:BAABLgAECn8pAAIIAAkJKCPdAQAJAwAIAAkJKCPdAQAJAwAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCgkJDAAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAABLgAECn8cAAIfAAcJlBNsfQB2AQAfAAcJlBNsfQB2AQAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zebco:BAAALgADCgQJBAAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn81AAMEAAkJ4QsKSgB5AQAEAAkJ4QsKSgB5AQAXAAcJxwjbTwDnAAAAAA==.Zenreto:BAABLgAECn9BAAIUAAkJHR8NAgDAAgAUAAkJHR8NAgDAAgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8YAAIfAAYJgR9/JQDEAQAfAAYJgR9/JQDEAQAuAAQKfysAAh8ACAnAJG0SADkDAB8ACAnAJG0SADkDAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8bAAIIAAYJ/x4wAgC2AQAIAAYJ/x4wAgC2AQAuAAQKfy0AAggACQmSI2sAAG4DAAgACQmSI2sAAG4DAAAA.',
['Ät']='Äthena:BAAALgAECgUJBQAAAA==.',
['Îl']='Îllîdan:BAABLgAFFH8IAAIPAAIJYg4BdwCAAAAPAAIJYg4BdwCAAAAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8zAAMBAAkJuR3mGACJAgABAAkJuR3mGACJAgAdAAQJGwjCQQCuAAAAAA==.',
['Ún']='Úncle:BAAALgADCgYJBgAAAA==.',
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
