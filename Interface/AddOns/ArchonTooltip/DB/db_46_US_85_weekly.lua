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

local lookup = {'Monk-Windwalker','Warrior-Protection','Warrior-Arms','Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Warrior-Fury','Paladin-Holy','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Priest-Holy','Rogue-Outlaw','Hunter-Marksmanship','Druid-Feral',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Alys:BAABLgAECn8yAAIBAAkJPQ7THwCjAQABAAkJPQ7THwCjAQAAAA==.',
Am='Amaniatres:BAABLgAECn8YAAMCAAYJQxD/JwDlAAACAAYJMg3/JwDlAAADAAQJEw87RgCkAAAAAA==.Ammartin:BAAALgAECgcJEwAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBQAAAA==.Anahera:BAAALgADCgQJBAABLgAECgQJBgAEAAAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECgUJCQAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Ariiana:BAABLgAECn8XAAIFAAkJIx5rBgAQAwAFAAkJIx5rBgAQAwAAAA==.',
As='Asapshocky:BAACLgAFFH8OAAIGAAYJthktEgB2AQAGAAYJthktEgB2AQAuAAQKfy4AAgYACQnTI3sEABEDAAYACQnTI3sEABEDAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwAHACEUAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgAEAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAAALgAECgQJBgAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAABLgAECn8VAAIIAAcJgh1JEQDsAQAIAAcJgh1JEQDsAQAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgYJCQAEAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMJAAkJ0h+eBgDAAgAJAAkJ0h+eBgDAAgAKAAgJ9w45XABnAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwABALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwABALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAJACUcAA==.Bootyßandaid:BAABLgAFFH8JAAILAAMJpheONgDeAAALAAMJpheONgDeAAABLgAFFAQJCwAMAH4XAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAAALgAECgYJEAAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgIJAgAAAA==.Cajia:BAABLgAECn8sAAMNAAgJRwv1GgDDAAAOAAgJtQkqdwBGAQANAAYJBgv1GgDDAAAAAA==.Canon:BAAALgAECgkJAQAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAPAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwAEAAAAAA==.Choggy:BAABLgAECn8tAAIQAAkJxhsKDgBvAgAQAAkJxhsKDgBvAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLQAQAMYbAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCgABLgAFFAMJBwABALYHAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAIRAAgJQQwTIwBtAQARAAgJQQwTIwBtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMSAAkJsCINBQBgAwASAAkJsCINBQBgAwATAAUJMho8NgBjAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgAUAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIVAAkJhSXaCQAQAwAVAAkJhSXaCQAQAwAAAA==.',
Do='Donnabb:BAAALgAECggJEgAAAA==.Donteatbees:BAAALgAECgUJCQAAAA==.Dop:BAAALgAECgEJAQAAAA==.Doran:BAABLgAECn8cAAIJAAgJ+hNbFQDQAQAJAAgJ+hNbFQDQAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIKAAcJIBziUwCoAQAKAAcJIBziUwCoAQAAAA==.',
Dr='Draedis:BAAALgAECgMJCAAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgAEAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn86AAMWAAkJtBhbBAAoAgAWAAkJVBZbBAAoAgALAAcJNxOTMgBgAQAAAA==.Dreademperor:BAACLgAFFH8JAAICAAQJdBW1FgDUAAACAAQJdBW1FgDUAAAuAAQKfycAAwIACQkhHvAEAPYCAAIACQkhHvAEAPYCABcABAlDD4tcANUAAAEuAAUUBQkMAAgAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIIAAUJJR+AEwA8AQAIAAUJJR+AEwA8AQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAIACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAIACUfAA==.Drenrah:BAABLgAECn8nAAIYAAkJug/HKQC1AQAYAAkJug/HKQC1AQAAAA==.Drgndeeznutz:BAACLgAFFH8LAAIMAAQJfhdiEQAvAQAMAAQJfhdiEQAvAQAuAAQKfycAAgwACQnPH7MEANwCAAwACQnPH7MEANwCAAAA.Drizz:BAAALgAECgIJBAAAAA==.Drizzaer:BAAALgAECgEJAgAAAA==.Drunkenrage:BAACLgAFFH8lAAIZAAgJOxzwAgBkAgAZAAgJOxzwAgBkAgAuAAQKfx4AAhkACQkcIvsBAIIDABkACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edaddylock:BAAALgADCgUJBQAAAA==.Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAIQAAkJhAiILABrAQAQAAkJhAiILABrAQAAAA==.Elementdemon:BAAALgAECgUJBgAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8nAAIaAAkJch4kGQC8AgAaAAkJch4kGQC8AgAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQAAAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAAEAAAAAA==.',
Es='Esperzoa:BAABLgAECn8nAAIIAAgJgRyBDAA4AgAIAAgJgRyBDAA4AgAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAIACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIbAAkJvhecDAAHAgAbAAkJvhecDAAHAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgQJBAAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJQAVAJQlAA==.Fathermajor:BAAALgADCggJCAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAIRAAUJ2h2YGABBAQARAAUJ2h2YGABBAQAuAAQKfzYAAxEACQmWIpIEAE4DABEACQmWIpIEAE4DABwABQmDDbcUANIAAAAA.Ferendis:BAABLgAECn8nAAIKAAgJPiNEEgCnAgAKAAgJPiNEEgCnAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAJACUcAA==.',
Fl='Florita:BAAALgAECgUJBQAAAA==.Flydormu:BAAALgAECgYJCQABLgAECgkJIwAaAFYYAA==.',
Fo='Fordinn:BAABLgAECn8vAAMXAAkJlRgEJQDHAQAXAAkJCxUEJQDHAQACAAcJgRSFGwBPAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8iAAITAAkJghwkCwCYAgATAAkJghwkCwCYAgAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAECgkJOgAPAOYkAA==.Gasket:BAACLgAFFH8SAAMdAAUJRhqqCwAmAQAeAAUJ/Bf5UABAAQAdAAQJ3hOqCwAmAQAuAAQKfyUAAx4ACQlnIsMiALQCAB4ACQlvIcMiALQCAB0AAwkcIEAXAA4BAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAUJEQAVAHwiAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgAVAIUlAA==.Hark:BAACLgAFFH8SAAIfAAUJwA7wOgAsAQAfAAUJwA7wOgAsAQAuAAQKfyoAAh8ACQkNGvc3AM4BAB8ACQkNGvc3AM4BAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn80AAIUAAkJgCLQAQBpAwAUAAkJgCLQAQBpAwAAAA==.',
He='Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8qAAIGAAkJQhGfJAC1AQAGAAkJQhGfJAC1AQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAZAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn8qAAMGAAkJ7wy7PwAkAQAGAAgJqQq7PwAkAQAgAAkJWQd8dwDnAAAAAA==.Hope:BAABLgAECn8wAAITAAgJbwxJNgAuAQATAAgJbwxJNgAuAQAAAA==.Horrorfang:BAABLgAECn9DAAIeAAkJ6SDwDAD9AgAeAAkJ6SDwDAD9AgAAAA==.',
Hu='Hukjo:BAAALgAECgcJEAABLgAECgkJIwAHACEUAA==.',
Ib='Ibaar:BAACLgAFFH8VAAILAAUJ/iNmGQB3AQALAAUJ/iNmGQB3AQAuAAQKfy4AAwsACQm9I00HAAUDAAsACAk0I00HAAUDABYABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8gAAMQAAgJnCA/CwDPAgAQAAgJnCA/CwDPAgAFAAQJPBW2NwDpAAABLgAFFAQJDAAHALEgAA==.',
Il='Illedren:BAABLgAECn8QAAIKAAgJwwc7kAAAAQAKAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIKAAkJDiTxEwDhAgAKAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAAALgAECggJCAAAAA==.',
Is='Isabel:BAAALgAECgYJBgABLgAECggJEQAEAAAAAA==.',
It='Ithacus:BAABLgAECn8nAAIhAAkJSBAeEACiAQAhAAkJSBAeEACiAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgUJBgAAAA==.Jinoo:BAABLgAECn9CAAIGAAkJhhv3DQCAAgAGAAkJhhv3DQCAAgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAUJFQALAP4jAA==.',
Jo='Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIXAAkJ7BQkJgDAAQAXAAkJ7BQkJgDAAQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kaihune:BAAALgADCgIJAgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIXAAgJqwtMOABdAQAXAAgJqwtMOABdAQAAAA==.Kavik:BAABLgAECn8fAAIYAAkJHhkxEACNAgAYAAkJHhkxEACNAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8SAAIIAAUJxRMxGwD4AAAIAAUJxRMxGwD4AAAuAAQKfykAAwgACQnJFZcfAEwBAAgACQmpFZcfAEwBAB4AAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAECgcJEgAAAA==.Keemõ:BAABLgAECn8XAAMiAAYJvw3VHgCXAAAKAAYJ0wwJmADjAAAiAAYJownVHgCXAAAAAA==.Keemøsabi:BAAALgAECgUJBQAAAA==.Keflá:BAAALgAECgQJDAAAAA==.Keineliebe:BAAALgADCgYJBgAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9EAAIeAAkJEA/jSwDYAQAeAAkJEA/jSwDYAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8lAAMdAAkJiBbfCQDSAQAdAAgJIBTfCQDSAQAeAAgJ3RCHZACWAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQOAAgJzCK1OwDnAQAOAAcJNSC1OwDnAQAPAAQJbCJhEgAwAQANAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwABALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8fAAIjAAgJGRseCwAJAgAjAAgJGRseCwAJAgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMJAAcJJRzsOwC1AAAKAAYJrxkZfgAvAQAJAAMJKSDsOwC1AAAAAA==.Krispy:BAABLgAECn80AAQBAAkJSRU7FQADAgABAAkJSRU7FQADAgAZAAcJOA1LNgAdAQAHAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgYJCwAAAA==.',
La='Laerin:BAAALgAECgUJCQAAAA==.Laxus:BAAALgADCgcJDAABLgAECgkJGAAWAHkMAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIeAAcJkg91oQAgAQAeAAcJkg91oQAgAQAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAfAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Liisara:BAABLgAECn8bAAIKAAgJZgiWgwAMAQAKAAgJZgiWgwAMAQAAAA==.Lily:BAABLgAECn8wAAIbAAkJTBk6DAANAgAbAAkJTBk6DAANAgAAAA==.Linadra:BAABLgAECn8sAAIVAAkJgwkXiABUAQAVAAkJgwkXiABUAQAAAA==.Linzur:BAAALgADCgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8RAAIVAAUJfCLHGwCCAQAVAAUJfCLHGwCCAQAuAAQKfykAAhUACQm1JUgRAAYDABUACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9AAAMkAAkJGxdsEQBKAgAkAAkJGxdsEQBKAgAQAAUJdA1nTADUAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn84AAIVAAgJ3Q8neAByAQAVAAgJ3Q8neAByAQAAAA==.',
Ma='Macy:BAAALgAECgYJDAAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgQJCAABLgAECggJKAAVAMULAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBQAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8UAAIVAAcJdQ+DkABFAQAVAAcJdQ+DkABFAQAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Mew:BAAALgAECgEJAgAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIBAAQJJwv0GgDuAAABAAQJJwv0GgDuAAAuAAQKfygAAgEACQkTIncGANsCAAEACQkTIncGANsCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn87AAIOAAkJqwrqVwCQAQAOAAkJqwrqVwCQAQAAAA==.Mildoo:BAABLgAECn8rAAIPAAkJBA/RCgChAQAPAAkJBA/RCgChAQAAAA==.Milkymoo:BAABLgAECn8bAAICAAUJrRbGIwAFAQACAAUJrRbGIwAFAQABLgAFFAgJLwAkAPsWAA==.Millina:BAAALgADCgIJAgABLgAECgkJMgABAD0OAA==.Mimira:BAAALgADCgEJAQAAAA==.Minipal:BAAALgAECgcJEQAAAA==.Mixednuts:BAACLgAFFH8MAAIHAAQJsSBAGgB0AQAHAAQJsSBAGgB0AQAuAAQKfycAAwcACQmiIq8DAHMDAAcACQmiIq8DAHMDAAEABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJCwAMAH4XAA==.Monq:BAABLgAECn8XAAMBAAgJBBgzGwDJAQABAAgJBBgzGwDJAQAZAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mythion:BAABLgAECn8hAAMSAAgJBxjdLADrAQASAAgJBxjdLADrAQATAAQJCQUbZgB0AAAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIeAAgJkBenaQCKAQAeAAgJkBenaQCKAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMkAAkJxxkbFgATAgAkAAkJxxkbFgATAgAQAAUJZQhLUwC5AAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJLwAXAJUYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAISAAMJzBLLNwDJAAASAAMJzBLLNwDJAAAuAAQKfyIAAxIACAkJI7EOANgCABIACAkJI7EOANgCABMAAQllEtyAADAAAAEuAAUUBAkLAAwAfhcA.Neodin:BAABLgAECn8jAAIXAAkJlQ99IwDRAQAXAAkJlQ99IwDRAQAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJJwAjANchAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8oAAIeAAkJkRJeQwDxAQAeAAkJkRJeQwDxAQAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obsidiian:BAABLgAECn8UAAIlAAgJjRHGCQCAAQAlAAgJjRHGCQCAAQAAAA==.Obsidion:BAABLgAECn8WAAMQAAYJ1QoaVgCvAAAQAAUJlwcaVgCvAAAkAAQJDggfUgCDAAABLgAECgkJLwAXAJUYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMUAAkJUxJwDAAGAgAUAAkJUxJwDAAGAgALAAYJtwU+ZQCdAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIGAAgJzxhTIQDLAQAGAAgJzxhTIQDLAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgIJAgAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAABLgAECn8pAAMSAAkJuiFvBABtAwASAAkJuiFvBABtAwATAAIJAQWdewBEAAAAAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn8+AAIXAAkJjRzrCwCjAgAXAAkJjRzrCwCjAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwAEAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8oAAMQAAkJeRSTHADZAQAQAAkJeRSTHADZAQAkAAEJQgQHhQAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAPAPEbAA==.Ravenbear:BAAALgAECgQJBAABLgAECgkJSgAUAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8eAAIfAAcJaxCNQACtAQAfAAcJaxCNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8WAAQfAAYJthV6dABLAQAfAAYJ4hR6dABLAQAmAAMJLxTPHQC0AAAMAAEJAAAdaQAAAAAAAA==.Retrix:BAAALgAECgEJAQAAAA==.',
Ri='Rion:BAABLgAECn8XAAIaAAkJcxFiXADDAQAaAAkJcxFiXADDAQAAAA==.Ristvakbaen:BAABLgAECn86AAQPAAkJ5iTPAgCLAgAPAAgJRiXPAgCLAgAOAAkJvB2+HQBrAgANAAYJPSV8BQAIAgAAAA==.',
Ro='Robynlee:BAABLgAECn8qAAIkAAgJIhN/IwDKAQAkAAgJIhN/IwDKAQAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAECgQJBgAAAA==.Rosebelle:BAAALgADCgYJDAAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgAEAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBAABLgAECggJJwAIAIEcAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAABLgAECn8oAAIVAAkJzBdPRADuAQAVAAkJzBdPRADuAQAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCAABLgAECgcJFAAVAHUPAA==.Scottlock:BAABLgAECn8UAAINAAcJqh76BAAZAgANAAcJqh76BAAZAgABLgAECgkJLgAhAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgEJAQAAAA==.Screwtotems:BAAALgADCgYJBgAAAA==.Scrmndemn:BAABLgAECn8tAAIVAAgJVgfWtgAJAQAVAAgJVgfWtgAJAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIeAAcJNhZmcACoAQAeAAcJNhZmcACoAQAAAA==.Serpent:BAACLgAFFH8KAAICAAYJCRI+DABTAQACAAYJCRI+DABTAQAuAAQKfyMAAgIACQlnH1sHAIECAAIACQlnH1sHAIECAAEuAAUUBwkUAAgA9hEA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAECgkJOgAPAOYkAA==.Sharaseth:BAAALgAECgcJDwAAAA==.Shikita:BAABLgAECn9CAAMSAAgJVx+mEwClAgASAAgJVx+mEwClAgATAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8eAAIVAAUJTxsANQAzAQAVAAUJTxsANQAzAQAuAAQKfykAAhUACQkfHiYwADUCABUACQkfHiYwADUCAAAA.Shimjun:BAAALgAECgUJBgABLgAFFAUJHgAVAE8bAA==.Shimpbizkit:BAABLgAECn8ZAAIaAAcJAg3GlQBHAQAaAAcJAg3GlQBHAQABLgAFFAUJHgAVAE8bAA==.Shimsong:BAAALgAECgYJEAABLgAFFAUJHgAVAE8bAA==.Shmerek:BAABLgAECn8XAAICAAkJRSCCBwB9AgACAAkJRSCCBwB9AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silverlumen:BAAALgAECgYJEgAAAA==.Silversaevus:BAAALgADCgIJAgAAAA==.Silverstream:BAACLgAFFH8GAAISAAMJbQdKRQCbAAASAAMJbQdKRQCbAAAuAAQKfyoAAhIACQnoER1CAJkBABIACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAAALgAECgkJEQAAAA==.Slease:BAAALgADCgYJBwAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJIwAaAFYYAA==.Solitudé:BAABLgAECn8eAAMOAAgJBiScHQBsAgAOAAcJPiGcHQBsAgAPAAUJoSXvEgApAQABLgAFFAUJDwAdAP4fAA==.Soteirian:BAABLgAECn8oAAMVAAgJxQt1jwBHAQAVAAgJxQt1jwBHAQAjAAEJjwIqWgASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn8tAAIeAAkJShxUFwCyAgAeAAkJShxUFwCyAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMgAAgJMhDzQwCQAQAgAAgJMhDzQwCQAQAGAAYJ0RNmQQAeAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAYAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwAVAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn89AAIfAAkJTRZ7KAAyAgAfAAkJTRZ7KAAyAgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIJAAkJPCW6AwAKAwAJAAkJPCW6AwAKAwAAAA==.Syriene:BAABLgAECn8oAAInAAkJzg6NEQCPAQAnAAkJzg6NEQCPAQAAAA==.',
Ta='Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgAHAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIkAAkJwgXXOQADAQAkAAkJwgXXOQADAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.',
Th='Theatrix:BAAALgAECgQJBAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8nAAMDAAkJGBVDDwDvAQADAAkJGBVDDwDvAQAXAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAABLgAECn8VAAIHAAkJmwV7bwCsAAAHAAkJmwV7bwCsAAAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8lAAIVAAkJlCW9BABMAwAVAAkJlCW9BABMAwAAAA==.Thsarus:BAABLgAECn8vAAMKAAgJ6yAmGwBnAgAKAAgJ6yAmGwBnAgAiAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAISAAkJmgR7dQDLAAASAAkJmgR7dQDLAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgEJAQABLgAECgUJCQAEAAAAAA==.',
To='Toatani:BAAALgAECgQJBQABLgAECgQJBgAEAAAAAA==.Tokkaebi:BAAALgAECgkJAgAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQAOAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIHAAUJShzGFgCXAQAHAAUJShzGFgCXAQAuAAQKfywAAwcACQn/GYwaAC8CAAcACQn/GYwaAC8CABkABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8jAAIaAAkJVhg8OQAtAgAaAAkJVhg8OQAtAgAAAA==.',
Ug='Ugolok:BAABLgAECn8fAAMdAAcJ3AXuHgDEAAAeAAcJzwPG1wDUAAAdAAYJQwbuHgDEAAAAAA==.',
Ur='Uriél:BAABLgAECn8uAAIKAAkJNSU+AgBgAwAKAAkJNSU+AgBgAwABLgAFFAUJDwAdAP4fAA==.',
Va='Valeene:BAABLgAECn8qAAITAAkJFCIBBAAbAwATAAkJFCIBBAAbAwAAAA==.Varek:BAAALgAECggJDwAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMfAAkJERPbMQAKAgAfAAkJERPbMQAKAgAmAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8oAAIaAAkJqANlngA5AQAaAAkJqANlngA5AQAAAA==.',
Vh='Vhye:BAAALgAFFAIJAwAAAA==.',
Vi='Vidnoi:BAAALgAECgEJAQAAAA==.Vinstalation:BAABLgAECn81AAIdAAkJcRyBBQBNAgAdAAkJcRyBBQBNAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8jAAMfAAkJ8hPmRgDBAQAfAAkJ8hPmRgDBAQAmAAEJFw9LOwAtAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8PAAMdAAUJ/h/tBQByAQAdAAQJ/h/tBQByAQAeAAEJAABsEQEAAAAuAAQKfxUAAx0ACQmLIucFAD8CAB0ABwk+I+cFAD8CAB4AAgl0IMbrALgAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJJwAaAHIeAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8NAAIfAAQJrQQ7TwD1AAAfAAQJrQQ7TwD1AAAuAAQKfyIAAh8ACQkAEF5FAJsBAB8ACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaye:BAAALgAECgcJCgAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIeAAgJJxE+kwBZAQAeAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAIBAAcJxwUmTQDCAAABAAcJxwUmTQDCAAAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIIAAkJdxn0EwDIAQAIAAkJdxn0EwDIAQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMSAAkJ+RXSNwDIAQASAAkJ+RXSNwDIAQATAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAAAAA==.',
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
