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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Priest-Holy','Rogue-Outlaw','Hunter-Marksmanship','Druid-Feral',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ae='Aelaster:BAAALgADCgYJBgAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwABLgAECggJCQABAAAAAA==.Aldrich:BAAALgAECgYJBwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Alys:BAABLgAECn82AAICAAkJYw4HIgCfAQACAAkJYw4HIgCfAQAAAA==.',
Am='Amaniatres:BAABLgAECn8aAAMDAAYJ4xMDJAAQAQADAAYJ5REDJAAQAQAEAAQJEw8VSwChAAABLgAECgcJCQABAAAAAA==.Ammartin:BAABLgAECn8VAAIFAAgJago4bQBnAQAFAAgJago4bQBnAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBgAAAA==.Anahera:BAAALgADCgQJBAABLgAECgYJDAABAAAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECgcJEAAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Ariiana:BAABLgAECn8XAAIGAAkJIx7rBgAOAwAGAAkJIx7rBgAOAwAAAA==.',
As='Asapshocky:BAACLgAFFH8QAAIHAAcJcBYQFwBjAQAHAAcJcBYQFwBjAQAuAAQKfy4AAgcACQnTIxIFAA0DAAcACQnTIxIFAA0DAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwAIACEUAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgABAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAAALgAECgQJCQAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAABLgAECn8VAAIJAAcJgh2HEgDmAQAJAAcJgh2HEgDmAQAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgMJAgABAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMKAAkJ0h9nBwC7AgAKAAkJ0h9nBwC7AgALAAgJ9w6fYABoAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwACALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwACALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAKACUcAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAAALgAECgYJEAAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgMJAwAAAA==.Cajia:BAABLgAECn8sAAMMAAgJRws7HQC+AAANAAgJtQnZfgA7AQAMAAYJBgs7HQC+AAAAAA==.Canon:BAAALgAECgkJAwAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAOAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwABAAAAAA==.Choggy:BAABLgAECn8uAAIPAAkJxhvoDgBqAgAPAAkJxhvoDgBqAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLgAPAMYbAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Cokebear:BAAALgAECgMJAwABLgAECggJJAAQAHEaAA==.Composer:BAAALgAECgcJCQAAAA==.Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCwABLgAFFAMJBwACALYHAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAIRAAgJQQwMJQBtAQARAAgJQQwMJQBtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMQAAkJsCKWBQBeAwAQAAkJsCKWBQBeAwASAAUJMho8NgBjAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgATAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIUAAkJhSVoCwAKAwAUAAkJhSVoCwAKAwAAAA==.',
Do='Donnabb:BAABLgAECn8YAAIUAAgJCQWaBwCRAAAUAAgJCQWaBwCRAAAAAA==.Donteatbees:BAAALgAECggJEgAAAA==.Dop:BAAALgAECgEJAgAAAA==.Doran:BAABLgAECn8cAAIKAAgJ+hMIFwDNAQAKAAgJ+hMIFwDNAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAILAAcJIBziUwCoAQALAAcJIBziUwCoAQAAAA==.',
Dr='Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgABAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn87AAMVAAkJwBi7BAAkAgAVAAkJJRi7BAAkAgAWAAcJNxMfNQBdAQAAAA==.Dreademperor:BAACLgAFFH8JAAIDAAQJdBUjGgDGAAADAAQJdBUjGgDGAAAuAAQKfycAAwMACQkhHvAEAPYCAAMACQkhHvAEAPYCABcABAlDDwJiAM8AAAEuAAUUBQkMAAkAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIJAAUJJR8VFwAwAQAJAAUJJR8VFwAwAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAJACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAJACUfAA==.Drenrah:BAABLgAECn8oAAIYAAkJug+jKwC0AQAYAAkJug+jKwC0AQAAAA==.Drgndeeznutz:BAACLgAFFH8LAAIZAAQJfheDEwAvAQAZAAQJfheDEwAvAQAuAAQKfycAAhkACQnPHyoFANYCABkACQnPHyoFANYCAAAA.Drizzaer:BAAALgAECgEJAgAAAA==.Drunkenrage:BAACLgAFFH8lAAIaAAgJOxxcBABbAgAaAAgJOxxcBABbAgAuAAQKfx4AAhoACQkcIvsBAIIDABoACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAIPAAkJhAikMABbAQAPAAkJhAikMABbAQAAAA==.Elementdemon:BAAALgAECgUJBgAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8pAAIbAAkJch6KGwC2AgAbAAkJch6KGwC2AgAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQAAAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAABAAAAAA==.',
Es='Esperzoa:BAABLgAECn8wAAIJAAgJgRyADQAyAgAJAAgJgRyADQAyAgAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAJACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIcAAkJvhfGDQAGAgAcAAkJvhfGDQAGAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgQJBAAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJQAUAJQlAA==.Fathermajor:BAAALgAECgQJBAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAIRAAUJ2h0XHAA6AQARAAUJ2h0XHAA6AQAuAAQKfzYAAxEACQmWIpIEAE4DABEACQmWIpIEAE4DAB0ABQmDDb8VANEAAAAA.Ferendis:BAABLgAECn8nAAILAAgJPiOkEwCmAgALAAgJPiOkEwCmAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAKACUcAA==.',
Fl='Flokii:BAAALgADCgEJAQAAAA==.Florita:BAAALgAECgYJBwAAAA==.Flydormu:BAAALgAECgYJDAABLgAECgkJKQAbAOQYAA==.',
Fo='Fordinn:BAABLgAECn80AAMXAAkJsBiRGwARAgAXAAkJZRaRGwARAgADAAcJeRUNGwBgAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8lAAISAAkJghw3DACSAgASAAkJghw3DACSAgAAAA==.Furrypunch:BAAALgAFFAEJAQAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAFFAIJBAANAFUaAA==.Gasket:BAACLgAFFH8XAAMeAAUJRhpJDgAnAQAfAAUJ/BcVXgA4AQAeAAQJ3hNJDgAnAQAuAAQKfyUAAx8ACQlnIsMiALQCAB8ACQlvIcMiALQCAB4AAwkcIEUZAAoBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAUJFgAUAHwiAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guidosarduci:BAAALgADCgEJAQAAAA==.Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgAUAIUlAA==.Hark:BAACLgAFFH8XAAIFAAUJwA6uRQAiAQAFAAUJwA6uRQAiAQAuAAQKfywAAgUACQmOG7lQALABAAUACQmOG7lQALABAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn80AAITAAkJgCL0AQBlAwATAAkJgCL0AQBlAwAAAA==.',
He='Heisenburgg:BAAALgAECgYJBgAAAA==.Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8rAAIHAAkJQhERJwCzAQAHAAkJQhERJwCzAQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAaAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn8uAAMHAAkJlA0XQwAnAQAHAAgJFAsXQwAnAQAgAAkJPgj4eAD0AAAAAA==.Hope:BAABLgAECn8wAAISAAgJbww1OQAuAQASAAgJbww1OQAuAQAAAA==.Horrorfang:BAABLgAECn9HAAIfAAkJUiHwCwANAwAfAAkJUiHwCwANAwAAAA==.',
Hu='Hukjo:BAAALgAECgcJEQABLgAECgkJIwAIACEUAA==.',
Ib='Ibaar:BAACLgAFFH8VAAIWAAUJ/iPZHgBpAQAWAAUJ/iPZHgBpAQAuAAQKfy4AAxYACQm9I00HAAUDABYACAk0I00HAAUDABUABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8gAAMPAAgJnCA/CwDPAgAPAAgJnCA/CwDPAgAGAAQJPBW2NwDpAAABLgAFFAQJDAAIALEgAA==.',
Il='Illedren:BAABLgAECn8QAAILAAgJwwc7kAAAAQALAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAILAAkJDiTxEwDhAgALAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAABLgAECn8bAAMRAAkJTAsTAQAWAQARAAkJTAsTAQAWAQAdAAgJCwScEwDuAAAAAA==.',
Is='Isabel:BAAALgAECgYJDAABLgAECgkJFAAFAC4UAA==.',
It='Ithacus:BAABLgAECn8oAAIhAAkJtBGdEQCaAQAhAAkJtBGdEQCaAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jatt:BAAALgAECgMJCAAAAA==.Jattao:BAAALgADCgEJAQAAAA==.Jattix:BAAALgAECgIJBQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgUJBgAAAA==.Jinoo:BAABLgAECn9CAAIHAAkJhhsxDwB9AgAHAAkJhhsxDwB9AgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAUJFQAWAP4jAA==.',
Jo='Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIXAAkJ7BT1KAC2AQAXAAkJ7BT1KAC2AQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kaihune:BAAALgADCgIJAgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgABLgAECgYJDAABAAAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIXAAgJqwt8PABTAQAXAAgJqwt8PABTAQAAAA==.Kavik:BAABLgAECn8fAAIYAAkJHhlLEQCKAgAYAAkJHhlLEQCKAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8XAAIJAAUJxRNYHwDsAAAJAAUJxRNYHwDsAAAuAAQKfykAAwkACQnJFaYhAEUBAAkACQmpFaYhAEUBAB8AAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAECgcJEgAAAA==.Keemõ:BAABLgAECn8XAAMLAAYJvw1PnwDkAAALAAYJ0wxPnwDkAAAiAAYJownPIACXAAAAAA==.Keemøsabi:BAAALgAECgYJCQAAAA==.Keflá:BAAALgAECgYJEgAAAA==.Keineliebe:BAAALgADCgcJBwAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9IAAIfAAkJuQ8+TgDYAQAfAAkJuQ8+TgDYAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8oAAMeAAkJiRbCCAD+AQAeAAkJTxPCCAD+AQAfAAgJ3RDlawCOAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQNAAgJzCKJPgDiAQANAAcJNSCJPgDiAQAOAAQJbCItFAAuAQAMAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwACALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8nAAIjAAgJYx1fCQA7AgAjAAgJYx1fCQA7AgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMKAAcJJRyvQACzAAALAAYJrxkZfgAvAQAKAAMJKSCvQACzAAAAAA==.Krispy:BAABLgAECn83AAQCAAkJEhbJFAAUAgACAAkJEhbJFAAUAgAaAAcJOA0SOAAcAQAIAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgYJEAAAAA==.',
La='Laerin:BAAALgAECggJEgAAAA==.Laxus:BAAALgADCgcJDAABLgAECgkJGAAVAHkMAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIfAAcJkg98rAAZAQAfAAcJkg98rAAZAQAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAFAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Liisara:BAABLgAECn8bAAILAAgJZggyigAMAQALAAgJZggyigAMAQAAAA==.Lily:BAABLgAECn80AAIcAAkJuxm1DAAWAgAcAAkJuxm1DAAWAgAAAA==.Linadra:BAABLgAECn8sAAIUAAkJgwmikQBPAQAUAAkJgwmikQBPAQAAAA==.Linzur:BAAALgADCgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8WAAIUAAUJfCJMIACGAQAUAAUJfCJMIACGAQAuAAQKfykAAhQACQm1JUgRAAYDABQACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9EAAMkAAkJZhfhEQBQAgAkAAkJZhfhEQBQAgAPAAUJdA1VUADPAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn9JAAIUAAkJ2xM1AwAYAQAUAAkJ2xM1AwAYAQAAAA==.',
Ma='Macandcheese:BAAALgADCgMJBwAAAA==.Macy:BAABLgAECn8YAAIbAAcJJhP7AgAwAQAbAAcJJhP7AgAwAQAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgQJCAABLgAECgkJMwAUAKQLAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBgAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8aAAIUAAgJhRNfiQBdAQAUAAgJhRNfiQBdAQAAAA==.Map:BAAALgAECgIJAgAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Merrycow:BAAALgAECgcJBwAAAA==.Mew:BAAALgAECgIJAwAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAICAAQJJwsCHwDeAAACAAQJJwsCHwDeAAAuAAQKfygAAgIACQkTIlcHANQCAAIACQkTIlcHANQCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn8/AAINAAkJzwqcXACIAQANAAkJzwqcXACIAQAAAA==.Mildoo:BAABLgAECn8sAAIOAAkJBA/2CwCeAQAOAAkJBA/2CwCeAQAAAA==.Milkymoo:BAABLgAECn8fAAIDAAUJoxucHgA/AQADAAUJoxucHgA/AQABLgAFFAgJLwAkAPsWAA==.Millina:BAAALgADCgIJAgABLgAECgkJNgACAGMOAA==.Mimira:BAAALgAECgEJAQAAAA==.Minipal:BAAALgAECgcJEQABLgAECggJCQABAAAAAA==.Mixednuts:BAACLgAFFH8MAAIIAAQJsSAMIABuAQAIAAQJsSAMIABuAQAuAAQKfycAAwgACQmiIhsEAHIDAAgACQmiIhsEAHIDAAIABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJCwAZAH4XAA==.Monq:BAABLgAECn8YAAMCAAgJBBi/HADJAQACAAgJBBi/HADJAQAaAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mythion:BAABLgAECn8kAAMQAAgJcRprJQAiAgAQAAgJcRprJQAiAgASAAQJCQWqawBzAAAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIfAAgJkBcucACEAQAfAAgJkBcucACEAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMkAAkJxxnRFwAPAgAkAAkJxxnRFwAPAgAPAAUJZQiRWQCvAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJNAAXALAYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAIQAAMJzBJAPAC+AAAQAAMJzBJAPAC+AAAuAAQKfyIAAxAACAkJI5sPANcCABAACAkJI5sPANcCABIAAQllEtyAADAAAAEuAAUUBAkLABkAfhcA.Neodin:BAABLgAECn8jAAIXAAkJlQ+zJgDEAQAXAAkJlQ+zJgDEAQAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJKAAjABQiAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8sAAIfAAkJiROvQAABAgAfAAkJiROvQAABAgAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obitrice:BAAALgADCgEJAQAAAA==.Obsidiian:BAABLgAECn8VAAIlAAgJlREnCgCBAQAlAAgJlREnCgCBAQAAAA==.Obsidion:BAABLgAECn8XAAMPAAYJ1Qq4WwCnAAAPAAUJlwe4WwCnAAAkAAQJDgj/VQCEAAABLgAECgkJNAAXALAYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMTAAkJUxIkDQAAAgATAAkJUxIkDQAAAgAWAAYJtwX9awCXAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.Ossin:BAAALgAECgYJBwAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIHAAgJzxiUIwDKAQAHAAgJzxiUIwDKAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgQJAwAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAACLgAFFH8FAAIQAAMJcB57KwAJAQAQAAMJcB57KwAJAQAuAAQKfyoAAxAACQm6Ie8EAGwDABAACQm6Ie8EAGwDABIAAgkBBTqCAEQAAAAA.',
Ph='Phlampped:BAAALgADCgUJBQABLgAFFAgJHwAUAJsYAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn9CAAIXAAkJHB2YDAChAgAXAAkJHB2YDAChAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwABAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8pAAMPAAkJeRQHHwDNAQAPAAkJeRQHHwDNAQAkAAEJwRHNBQA1AAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAOAPEbAA==.Ravenbear:BAAALgAECgQJBQABLgAECgkJSgATAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8fAAIFAAcJJBGNQACtAQAFAAcJJBGNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8YAAQFAAgJ9hMCXwCKAQAFAAcJSRUCXwCKAQAmAAMJLxRgHwC0AAAZAAIJ4we2AwBDAAAAAA==.Retrix:BAAALgAECgIJAwAAAA==.',
Ri='Rion:BAABLgAECn8XAAIbAAkJcxHQYgC5AQAbAAkJcxHQYgC5AQAAAA==.Ristvakbaen:BAACLgAFFH8EAAINAAIJVRqtkwCbAAANAAIJVRqtkwCbAAAuAAQKfzoABA4ACQnmJEEDAIYCAA4ACAlGJUEDAIYCAA0ACQm8HbofAGYCAAwABgk9JRYGAAQCAAAA.',
Ro='Robynlee:BAABLgAECn8wAAIkAAgJSxVyHADjAQAkAAgJSxVyHADjAQAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAECgQJBgAAAA==.Rosebelle:BAAALgADCgcJFgAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgABAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBQABLgAECggJMAAJAIEcAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAABLgAECn8oAAIUAAkJzBdDSQDqAQAUAAkJzBdDSQDqAQAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCQABLgAECggJGgAUAIUTAA==.Scottlock:BAABLgAECn8WAAIMAAcJqh6QBQAVAgAMAAcJqh6QBQAVAgABLgAECgkJLgAhAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgQJBAAAAA==.Screwtotems:BAAALgAECgEJAQAAAA==.Scrmndemn:BAABLgAECn8vAAIUAAkJTQeepAAwAQAUAAkJTQeepAAwAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIfAAcJNhZmcACoAQAfAAcJNhZmcACoAQAAAA==.Serpent:BAACLgAFFH8OAAIDAAYJ5BTACgCDAQADAAYJ5BTACgCDAQAuAAQKfyMAAgMACQlnHxoIAHoCAAMACQlnHxoIAHoCAAEuAAUUBwkfAAkA4hIA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAFFAIJBAANAFUaAA==.Sharaseth:BAAALgAECggJEAAAAA==.Shikita:BAABLgAECn9GAAMQAAkJmB52DQDvAgAQAAkJmB52DQDvAgASAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8fAAIUAAUJ0xt3OAA8AQAUAAUJ0xt3OAA8AQAuAAQKfykAAhQACQkfHv4zADACABQACQkfHv4zADACAAAA.Shimbuktu:BAAALgAECgEJAQABLgAFFAUJHwAUANMbAA==.Shimfu:BAAALgAECgEJAgABLgAFFAUJHwAUANMbAA==.Shimjun:BAAALgAECgUJCQABLgAFFAUJHwAUANMbAA==.Shimpbizkit:BAABLgAECn8ZAAIbAAcJAg0VnwA8AQAbAAcJAg0VnwA8AQABLgAFFAUJHwAUANMbAA==.Shimsong:BAAALgAECgYJEwABLgAFFAUJHwAUANMbAA==.Shmerek:BAABLgAECn8XAAIDAAkJRSBDCAB3AgADAAkJRSBDCAB3AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silverlumen:BAAALgAFFAEJAQAAAA==.Silversaevus:BAAALgADCgQJBAAAAA==.Silverstream:BAACLgAFFH8IAAIQAAMJGgqRSQCUAAAQAAMJGgqRSQCUAAAuAAQKfyoAAhAACQnoER1CAJkBABAACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAABLgAECn8VAAIZAAkJQxArFAAEAgAZAAkJQxArFAAEAgAAAA==.Slippery:BAAALgAFFAcJAgAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJKQAbAOQYAA==.Solitudé:BAABLgAECn8fAAMNAAgJBiSWHwBnAgANAAcJPiGWHwBnAgAOAAUJoSW2FAAoAQABLgAFFAUJDwAeAP4fAA==.Soteirian:BAABLgAECn8zAAMUAAkJpAuKcgCJAQAUAAkJpAuKcgCJAQAjAAEJjwJKXwASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn8zAAIfAAkJTRxTGQCuAgAfAAkJTRxTGQCuAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMgAAgJMhCJRwCQAQAgAAgJMhCJRwCQAQAHAAYJ0ROSRQAdAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAYAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwAUAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn9AAAIFAAkJ/hZEKQA5AgAFAAkJ/hZEKQA5AgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIKAAkJPCVZBAAEAwAKAAkJPCVZBAAEAwAAAA==.Syriene:BAABLgAECn8uAAInAAkJPBBwEQCjAQAnAAkJPBBwEQCjAQABLgAECgkJGwARAEwLAA==.',
Ta='Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.Tayger:BAAALgAECgEJAQAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgAIAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIkAAkJwgWbPAABAQAkAAkJwgWbPAABAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.Teslá:BAAALgAECgEJAQAAAA==.',
Th='Theatrix:BAAALgAECgQJBAABLgAECgcJCQABAAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8sAAMEAAkJ/hboDAAYAgAEAAkJ/hboDAAYAgAXAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAACLgAFFH8GAAIIAAMJ9hmqBgCgAAAIAAMJ9hmqBgCgAAAuAAQKfxUAAggACQmbBcd5ALAAAAgACQmbBcd5ALAAAAAA.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8lAAIUAAkJlCWWBQBHAwAUAAkJlCWWBQBHAwAAAA==.Thsarus:BAABLgAECn8vAAMLAAgJ6yDnHABnAgALAAgJ6yDnHABnAgAiAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIQAAkJmgQIegDJAAAQAAkJmgQIegDJAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgIJAwABLgAECgUJCQABAAAAAA==.',
To='Toatani:BAAALgAECgYJDAAAAA==.Tokkaebi:BAAALgAECgkJCgAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQANAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIIAAUJShwMHACSAQAIAAUJShwMHACSAQAuAAQKfywAAwgACQn/GeAcADECAAgACQn/GeAcADECABoABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8pAAIbAAkJ5BgAAgB2AQAbAAkJ5BgAAgB2AQAAAA==.',
Ug='Ugolok:BAABLgAECn8lAAMeAAcJEAbsIQC/AAAfAAcJAgWQ2wDZAAAeAAYJQwbsIQC/AAAAAA==.',
Ur='Uriél:BAABLgAECn8uAAILAAkJNSWeAgBeAwALAAkJNSWeAgBeAwABLgAFFAUJDwAeAP4fAA==.',
Va='Valeene:BAABLgAECn8tAAISAAkJLiJSBAAcAwASAAkJLiJSBAAcAwAAAA==.Varek:BAAALgAECgkJEwAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMFAAkJEROKNgADAgAFAAkJEROKNgADAgAmAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8pAAIbAAkJNwSqpgAwAQAbAAkJNwSqpgAwAQAAAA==.',
Vh='Vhye:BAABLgAFFH8GAAIgAAMJmANlZAB+AAAgAAMJmANlZAB+AAAAAA==.',
Vi='Vidnoi:BAAALgAECgEJAwAAAA==.Vinstalation:BAABLgAECn81AAIeAAkJcRwxBgBHAgAeAAkJcRwxBgBHAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8kAAMFAAkJ8hORTQC5AQAFAAkJ8hORTQC5AQAmAAEJFw9CAgA2AAAAAA==.',
Vr='Vritraz:BAACLgAFFH8PAAMeAAUJ/h91CABnAQAeAAQJ/h91CABnAQAfAAEJAAC2LQEAAAAuAAQKfxUAAx4ACQmLIqEGADkCAB4ABwk+I6EGADkCAB8AAgl0IPj2ALcAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJKQAbAHIeAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8SAAIFAAQJDQaLUwACAQAFAAQJDQaLUwACAQAuAAQKfyIAAgUACQkAEF5FAJsBAAUACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Xe='Xendria:BAAALgAECgEJAgAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaye:BAAALgAECggJDAAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIfAAgJJxE+kwBZAQAfAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAICAAcJxwUgUgDAAAACAAcJxwUgUgDAAAAAAA==.Zerk:BAAALgAECgEJAQAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIJAAkJdxmzFQC+AQAJAAkJdxmzFQC+AQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Zà']='Zàknafein:BAAALgAECgYJBgAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMQAAkJ+RXSNwDIAQAQAAkJ+RXSNwDIAQASAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAAAAA==.',
['ßo']='ßoomer:BAAALgADCgIJAgABLgAFFAMJBwACALYHAA==.',
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
