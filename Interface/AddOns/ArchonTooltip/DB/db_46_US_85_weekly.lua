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

local lookup = {'Monk-Windwalker','Warrior-Protection','Warrior-Arms','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Monk-Mistweaver','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Warrior-Fury','Paladin-Holy','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Priest-Holy','Rogue-Outlaw','Hunter-Marksmanship','Druid-Feral',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwAAAA==.Aldrich:BAAALgAECgQJBAAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Alys:BAABLgAECn82AAIBAAkJYw41IQCiAQABAAkJYw41IQCiAQAAAA==.',
Am='Amaniatres:BAABLgAECn8ZAAMCAAYJQxBmJwD0AAACAAYJRQ5mJwD0AAADAAQJEw9cSQChAAAAAA==.Ammartin:BAABLgAECn8UAAIEAAgJagocawBnAQAEAAgJagocawBnAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgUJBQAAAA==.Anahera:BAAALgADCgQJBAABLgAECgQJBgAFAAAAAA==.Angrylizard:BAAALgAECgEJAgAAAA==.Anklebiterr:BAAALgAECgUJBwAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arabella:BAAALgAECgUJDgAAAA==.Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgkJHAAAAA==.Ariiana:BAABLgAECn8XAAIGAAkJIx7ABgAQAwAGAAkJIx7ABgAQAwAAAA==.',
As='Asapshocky:BAACLgAFFH8OAAIHAAYJthnCFQBlAQAHAAYJthnCFQBlAQAuAAQKfy4AAgcACQnTI+kEAA4DAAcACQnTI+kEAA4DAAAA.Asclepios:BAAALgAECgMJBAAAAA==.Asmoday:BAAALgAECgYJBgAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgkJIwAIACEUAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgAFAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Beastwallker:BAAALgADCgUJBgAAAA==.Bellabelle:BAAALgAECgQJCQAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAABLgAECn8VAAIJAAcJgh00EgDoAQAJAAcJgh00EgDoAQAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgYJCQAFAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8iAAMKAAkJ0h87BwC9AgAKAAkJ0h87BwC9AgALAAgJ9w5AXwBnAQAAAA==.Bighead:BAAALgAECgYJCAABLgAFFAMJBwABALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwABALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgUJBgAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAKACUcAA==.Bootyßandaid:BAABLgAFFH8MAAIMAAMJphdjOgDaAAAMAAMJphdjOgDaAAABLgAFFAQJCwANAH4XAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBgAAAA==.',
Bu='Buckis:BAAALgAECgYJEAAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgkJCgAAAA==.',
Ca='Cahk:BAAALgAECgIJAgAAAA==.Cajia:BAABLgAECn8sAAMOAAgJRwucHAC/AAAPAAgJtQm6fAA/AQAOAAYJBgucHAC/AAAAAA==.Canon:BAAALgAECgkJAgAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAQAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Chiwhiz:BAAALgAECgEJAQABLgAECgQJCwAFAAAAAA==.Choggy:BAABLgAECn8tAAIRAAkJxhu5DgBsAgARAAkJxhu5DgBsAgAAAA==.Chogs:BAAALgAECgMJBAABLgAECgkJLQARAMYbAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Cokebear:BAAALgAECgMJAwABLgAECggJJAASAHEaAA==.Composer:BAAALgAECgEJAgAAAA==.Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgUJCgABLgAFFAMJBwABALYHAA==.',
Cr='Crinklecut:BAABLgAECn8ZAAITAAgJQQyCJABtAQATAAgJQQyCJABtAQAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMSAAkJsCJpBQBfAwASAAkJsCJpBQBfAwAUAAUJMho8NgBjAQAAAA==.Deadybear:BAAALgADCgkJEAABLgAECgkJSgAVAFMSAA==.Deathkyter:BAAALgAECgEJAQAAAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAIWAAkJhSUECwAMAwAWAAkJhSUECwAMAwAAAA==.',
Do='Donnabb:BAAALgAECggJEgAAAA==.Donteatbees:BAAALgAECgUJDgAAAA==.Dop:BAAALgAECgEJAQAAAA==.Doran:BAABLgAECn8cAAIKAAgJ+hONFgDPAQAKAAgJ+hONFgDPAQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAILAAcJIBziUwCoAQALAAcJIBziUwCoAQAAAA==.',
Dr='Draedis:BAAALgAECgMJCAAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBgAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgAFAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn86AAMXAAkJtBioBAAjAgAXAAkJVBaoBAAjAgAMAAcJNxN3NABeAQAAAA==.Dreademperor:BAACLgAFFH8JAAICAAQJdBU6GQDHAAACAAQJdBU6GQDHAAAuAAQKfycAAwIACQkhHvAEAPYCAAIACQkhHvAEAPYCABgABAlDD85fANUAAAEuAAUUBQkMAAkAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAIJAAUJJR/aFQA1AQAJAAUJJR/aFQA1AQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAAJACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAAJACUfAA==.Drenrah:BAABLgAECn8nAAIZAAkJug8gKwC0AQAZAAkJug8gKwC0AQAAAA==.Drgndeeznutz:BAACLgAFFH8LAAINAAQJfhf5EgAvAQANAAQJfhf5EgAvAQAuAAQKfycAAg0ACQnPH/8EANkCAA0ACQnPH/8EANkCAAAA.Drizz:BAAALgAECgIJBAAAAA==.Drizzaer:BAAALgAECgEJAgAAAA==.Drunkenrage:BAACLgAFFH8lAAIaAAgJOxziAwBdAgAaAAgJOxziAwBdAgAuAAQKfx4AAhoACQkcIvsBAIIDABoACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgYJCAAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8xAAIRAAkJhAgTLwBiAQARAAkJhAgTLwBiAQAAAA==.Elementdemon:BAAALgAECgUJBgAAAA==.Ellabelle:BAAALgADCgMJAwAAAA==.',
En='Enthalpy:BAABLgAECn8pAAIbAAkJch7BGgC4AgAbAAkJch7BGgC4AgAAAA==.',
Er='Erakazsod:BAAALgAECgEJAQAAAA==.Erazath:BAAALgAECgUJCAABLgAECgkJEAAFAAAAAA==.',
Es='Esperzoa:BAABLgAECn8vAAIJAAgJgRw+DQA1AgAJAAgJgRw+DQA1AgAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAAJACUfAA==.',
Eu='Eucalicdes:BAABLgAECn9CAAIcAAkJvhd9DQAGAgAcAAkJvhd9DQAGAgAAAA==.',
Ez='Ezal:BAAALgAECgYJCAAAAA==.Ezra:BAAALgAECgQJBAAAAA==.',
Fa='Fallyn:BAAALgAECgEJAQAAAA==.Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJQAWAJQlAA==.Fathermajor:BAAALgAECgQJBAAAAA==.',
Fe='Felicity:BAACLgAFFH8WAAITAAUJ2h0bGwA6AQATAAUJ2h0bGwA6AQAuAAQKfzYAAxMACQmWIpIEAE4DABMACQmWIpIEAE4DAB0ABQmDDX4VANEAAAAA.Ferendis:BAABLgAECn8nAAILAAgJPiM8EwCmAgALAAgJPiM8EwCmAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAKACUcAA==.',
Fl='Flokii:BAAALgADCgEJAQAAAA==.Florita:BAAALgAECgUJBQAAAA==.Flydormu:BAAALgAECgYJDAABLgAECgkJIwAbAFYYAA==.',
Fo='Fordinn:BAABLgAECn80AAMYAAkJsBgrGwATAgAYAAkJZRYrGwATAgACAAcJeRWZGgBhAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.Frigidgrip:BAAALgAECgMJAwAAAA==.',
Fu='Fuddytwo:BAABLgAECn8lAAIUAAkJghzUCwCWAgAUAAkJghzUCwCWAgAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAFFAIJBAAPAFUaAA==.Gasket:BAACLgAFFH8WAAMeAAUJRhp+DQAnAQAfAAUJ/Bd7WQA8AQAeAAQJ3hN+DQAnAQAuAAQKfyUAAx8ACQlnIsMiALQCAB8ACQlvIcMiALQCAB4AAwkcIL8YAAsBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAUJFQAWAHwiAA==.',
Gh='Ghidõráh:BAAALgAECgEJAQAAAA==.Ghorac:BAAALgADCgYJDAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Gn='Gnollfang:BAAALgADCgYJBgAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgUJBgAAAA==.Griffith:BAAALgAECgEJAQAAAA==.Grit:BAAALgAECgYJDAAAAA==.',
Gu='Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgAWAIUlAA==.Hark:BAACLgAFFH8WAAIEAAUJwA6NQgAiAQAEAAUJwA6NQgAiAQAuAAQKfywAAgQACQmOG+lOALEBAAQACQmOG+lOALEBAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn80AAIVAAkJgCLpAQBlAwAVAAkJgCLpAQBlAwAAAA==.',
He='Heisenburgg:BAAALgAECgUJBQAAAA==.Hekus:BAEALgAECgcJEQAAAA==.Helanua:BAABLgAECn8qAAIHAAkJQhFWJgC0AQAHAAkJQhFWJgC0AQAAAA==.Hellsplay:BAAALgADCgIJAgAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippolytus:BAAALgADCgkJCQABLgAECgkJLgAaAPQkAA==.Hippopotamus:BAAALgAECgMJAwAAAA==.Hit:BAAALgAECgYJCwAAAA==.',
Ho='Holytide:BAABLgAECn8uAAMHAAkJlA3qQQAnAQAHAAgJFAvqQQAnAQAgAAkJPggddwDzAAAAAA==.Hope:BAABLgAECn8wAAIUAAgJbwxsOAAuAQAUAAgJbwxsOAAuAQAAAA==.Horrorfang:BAABLgAECn9HAAIfAAkJUiGWCwAPAwAfAAkJUiGWCwAPAwAAAA==.',
Hu='Hukjo:BAAALgAECgcJEQABLgAECgkJIwAIACEUAA==.',
Ib='Ibaar:BAACLgAFFH8VAAIMAAUJ/iNSHQBtAQAMAAUJ/iNSHQBtAQAuAAQKfy4AAwwACQm9I00HAAUDAAwACAk0I00HAAUDABcABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8gAAMRAAgJnCA/CwDPAgARAAgJnCA/CwDPAgAGAAQJPBW2NwDpAAABLgAFFAQJDAAIALEgAA==.',
Il='Illedren:BAABLgAECn8QAAILAAgJwwc7kAAAAQALAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAILAAkJDiTxEwDhAgALAAkJDiTxEwDhAgAAAA==.',
Ir='Irraedorine:BAABLgAECn8WAAMTAAkJ6gheHgCfAQATAAkJ6gheHgCfAQAdAAgJCwRnEwDuAAAAAA==.',
Is='Isabel:BAAALgAECgYJDAABLgAECgkJFAAEAC4UAA==.',
It='Ithacus:BAABLgAECn8nAAIhAAkJSBA0EQCbAQAhAAkJSBA0EQCbAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgAECgUJBQAAAA==.',
Ji='Jinnlee:BAAALgAECgUJBgAAAA==.Jinoo:BAABLgAECn9CAAIHAAkJhhvqDgB+AgAHAAkJhhvqDgB+AgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAUJFQAMAP4jAA==.',
Jo='Joe:BAAALgAECgcJCgAAAA==.Jorek:BAABLgAECn8WAAIYAAkJ7BQjKAC5AQAYAAkJ7BQjKAC5AQAAAA==.',
Ju='Jugulator:BAAALgADCgcJDQAAAA==.',
Ka='Kaejung:BAAALgAECgUJBgAAAA==.Kaihune:BAAALgADCgIJAgAAAA==.Kainairobi:BAAALgAECgUJCQAAAA==.Kaiva:BAAALgAECgQJBgAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAABLgAECn8VAAIYAAgJqws5OwBYAQAYAAgJqws5OwBYAQAAAA==.Kavik:BAABLgAECn8fAAIZAAkJHhkMEQCLAgAZAAkJHhkMEQCLAgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8WAAIJAAUJxRNXHgDvAAAJAAUJxRNXHgDvAAAuAAQKfykAAwkACQnJFf8gAEcBAAkACQmpFf8gAEcBAB8AAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAECgcJEgAAAA==.Keemõ:BAABLgAECn8XAAMLAAYJvw0YnQDkAAALAAYJ0wwYnQDkAAAiAAYJowk4IACXAAAAAA==.Keemøsabi:BAAALgAECgYJCAAAAA==.Keflá:BAAALgAECgYJEgAAAA==.Keineliebe:BAAALgADCgYJBgAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn9IAAIfAAkJuQ8HTQDZAQAfAAkJuQ8HTQDZAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAABLgAECn8oAAMeAAkJiRaLCAACAgAeAAkJTxOLCAACAgAfAAgJ3RDSaQCPAQAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8hAAQPAAgJzCKxPQDkAQAPAAcJNSCxPQDkAQAQAAQJbCKmEwAuAQAOAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwABALYHAA==.',
Kk='Kkain:BAAALgAECgIJBwAAAA==.',
Ko='Korihor:BAABLgAECn8nAAIjAAgJYx0vCQA8AgAjAAgJYx0vCQA8AgAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMKAAcJJRxtPwC0AAALAAYJrxkZfgAvAQAKAAMJKSBtPwC0AAAAAA==.Krispy:BAABLgAECn83AAQBAAkJEhZ2FAAUAgABAAkJEhZ2FAAUAgAaAAcJOA2cNwAcAQAIAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ku='Kumiho:BAAALgAECgYJBgAAAA==.',
Ky='Kyndil:BAAALgAECgYJEAAAAA==.',
La='Laerin:BAAALgAECgUJDgAAAA==.Laxus:BAAALgADCgcJDAABLgAECgkJGAAXAHkMAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIfAAcJkg+ZqAAcAQAfAAcJkg+ZqAAcAQAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBwAEAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Liisara:BAABLgAECn8bAAILAAgJZggciAAMAQALAAgJZggciAAMAQAAAA==.Lily:BAABLgAECn80AAIcAAkJuxl3DAAVAgAcAAkJuxl3DAAVAgAAAA==.Linadra:BAABLgAECn8sAAIWAAkJgwkhjgBSAQAWAAkJgwkhjgBSAQAAAA==.Linzur:BAAALgADCgEJAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8VAAIWAAUJfCLkHQCIAQAWAAUJfCLkHQCIAQAuAAQKfykAAhYACQm1JUgRAAYDABYACQm1JUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn9EAAMkAAkJZhefEQBRAgAkAAkJZhefEQBRAgARAAUJdA0aTwDRAAAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn9CAAIWAAkJcBPISQDmAQAWAAkJcBPISQDmAQAAAA==.',
Ma='Macy:BAAALgAECgcJEgAAAA==.Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgQJCAABLgAECgkJKwAWAHQLAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBgAAAA==.Malphoz:BAAALgAECgUJBwAAAA==.Mandragora:BAABLgAECn8YAAIWAAcJhhJmhwBeAQAWAAcJhhJmhwBeAQAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Mekator:BAAALgAECgQJBAAAAA==.Meko:BAAALgAECgUJBwAAAA==.Merrycow:BAAALgAECgYJBgAAAA==.Mew:BAAALgAECgEJAgAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIBAAQJJwsJHgDeAAABAAQJJwsJHgDeAAAuAAQKfygAAgEACQkTIigHANUCAAEACQkTIigHANUCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn8/AAIPAAkJzwrsWgCMAQAPAAkJzwrsWgCMAQAAAA==.Mildoo:BAABLgAECn8rAAIQAAkJBA+SCwCgAQAQAAkJBA+SCwCgAQAAAA==.Milkymoo:BAABLgAECn8bAAICAAUJrRY+JQADAQACAAUJrRY+JQADAQABLgAFFAgJLwAkAPsWAA==.Millina:BAAALgADCgIJAgABLgAECgkJNgABAGMOAA==.Mimira:BAAALgADCgEJAwAAAA==.Minipal:BAAALgAECgcJEQAAAA==.Mixednuts:BAACLgAFFH8MAAIIAAQJsSAuHgBvAQAIAAQJsSAuHgBvAQAuAAQKfycAAwgACQmiIgEEAHIDAAgACQmiIgEEAHIDAAEABgkoIKofANoBAAAA.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgABLgAFFAQJCwANAH4XAA==.Monq:BAABLgAECn8XAAMBAAgJBBgyHADJAQABAAgJBBgyHADJAQAaAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mythion:BAABLgAECn8kAAMSAAgJcRr/JAAhAgASAAgJcRr/JAAhAgAUAAQJCQX0aQBzAAAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIfAAgJkBdVbgCFAQAfAAgJkBdVbgCFAQAAAA==.Nafari:BAAALgAECggJCAAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8rAAMkAAkJxxltFwAQAgAkAAkJxxltFwAQAgARAAUJZQisVwCyAAAAAA==.Narus:BAAALgAECgcJCgABLgAECgkJNAAYALAYAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAISAAMJzBK8OgC+AAASAAMJzBK8OgC+AAAuAAQKfyIAAxIACAkJI1gPANcCABIACAkJI1gPANcCABQAAQllEtyAADAAAAEuAAUUBAkLAA0AfhcA.Neodin:BAABLgAECn8jAAIYAAkJlQ95JQDKAQAYAAkJlQ95JQDKAQAAAA==.Nephadin:BAAALgADCgUJAwABLgAECgkJJwAjANchAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8sAAIfAAkJiRNjPwADAgAfAAkJiRNjPwADAgAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBgAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgYJCwAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEwAAAA==.Nothros:BAAALgADCgQJBAAAAA==.',
Ob='Obsidiian:BAABLgAECn8UAAIlAAgJjREXCgCBAQAlAAgJjREXCgCBAQAAAA==.Obsidion:BAABLgAECn8XAAMRAAYJ1QrpWQCqAAARAAUJlwfpWQCqAAAkAAQJDgjJVACDAAABLgAECgkJNAAYALAYAA==.',
Od='Odie:BAAALgAECgYJDwAAAA==.',
On='Onemorehit:BAAALgAECgEJAwAAAA==.Onlyfangs:BAABLgAECn9KAAMVAAkJUxL9DAD/AQAVAAkJUxL9DAD/AQAMAAYJtwUIaQCbAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.Ossin:BAAALgAECgYJBgAAAA==.',
Pa='Padivyn:BAABLgAECn8ZAAIHAAgJzxgDIwDKAQAHAAgJzxgDIwDKAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.Palidenman:BAAALgAECgQJAwAAAA==.',
Pe='Peanads:BAAALgADCgcJEAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAABLgAECn8qAAMSAAkJuiHDBABsAwASAAkJuiHDBABsAwAUAAIJAQUFgABEAAAAAA==.',
Ph='Phlampped:BAAALgADCgUJBQABLgAFFAgJHwAWAJsYAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn9CAAIYAAkJHB1UDACjAgAYAAkJHB1UDACjAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwAFAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8oAAMRAAkJeRQAHgDUAQARAAkJeRQAHgDUAQAkAAEJQgQHhQAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAQAPEbAA==.Ravenbear:BAAALgAECgQJBQABLgAECgkJSgAVAFMSAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8eAAIEAAcJaxCNQACtAQAEAAcJaxCNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAABLgAECn8XAAQEAAcJ+hX5XACKAQAEAAcJSRX5XACKAQAmAAMJLxTiHgC0AAANAAEJAADDbAAAAAAAAA==.Retrix:BAAALgAECgIJAwAAAA==.',
Ri='Rion:BAABLgAECn8XAAIbAAkJcxFJYQC5AQAbAAkJcxFJYQC5AQAAAA==.Ristvakbaen:BAACLgAFFH8EAAIPAAIJVRpFkACbAAAPAAIJVRpFkACbAAAuAAQKfzoABBAACQnmJCQDAIcCABAACAlGJSQDAIcCAA8ACQm8HR0fAGgCAA4ABgk9JeMFAAUCAAAA.',
Ro='Robynlee:BAABLgAECn8qAAIkAAgJIhN/IwDKAQAkAAgJIhN/IwDKAQAAAA==.Roccobb:BAAALgADCgYJBgAAAA==.Rogùe:BAAALgAECgQJBgAAAA==.Rosebelle:BAAALgADCgcJEAAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgAFAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Sailrmoonkin:BAAALgAECgQJBAABLgAECggJLwAJAIEcAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanathein:BAAALgADCgcJBwAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.Satin:BAAALgAECggJDQAAAA==.',
Sc='Sceryna:BAABLgAECn8oAAIWAAkJzBclSADrAQAWAAkJzBclSADrAQAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgQJCQABLgAECgcJGAAWAIYSAA==.Scottlock:BAABLgAECn8VAAIOAAcJqh5dBQAWAgAOAAcJqh5dBQAWAgABLgAECgkJLgAhAAIjAA==.Screwbrew:BAAALgAECgIJAgAAAA==.Screwid:BAAALgAECgQJBAAAAA==.Screwtotems:BAAALgAECgEJAQAAAA==.Scrmndemn:BAABLgAECn8vAAIWAAkJTQcgoQAzAQAWAAkJTQcgoQAzAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIfAAcJNhZmcACoAQAfAAcJNhZmcACoAQAAAA==.Serpent:BAACLgAFFH8OAAICAAYJ5BQNCgCGAQACAAYJ5BQNCgCGAQAuAAQKfyMAAgIACQlnH+gHAHwCAAIACQlnH+gHAHwCAAEuAAUUBwkaAAkA4hIA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAFFAIJBAAPAFUaAA==.Sharaseth:BAAALgAECgcJDwAAAA==.Shikita:BAABLgAECn9GAAMSAAkJmB48DQDvAgASAAkJmB48DQDvAgAUAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8fAAIWAAUJ0xtiNQA9AQAWAAUJ0xtiNQA9AQAuAAQKfykAAhYACQkfHuoyADICABYACQkfHuoyADICAAAA.Shimbuktu:BAAALgAECgEJAQABLgAFFAUJHwAWANMbAA==.Shimfu:BAAALgAECgEJAQABLgAFFAUJHwAWANMbAA==.Shimjun:BAAALgAECgUJCAABLgAFFAUJHwAWANMbAA==.Shimpbizkit:BAABLgAECn8ZAAIbAAcJAg3OnAA9AQAbAAcJAg3OnAA9AQABLgAFFAUJHwAWANMbAA==.Shimsong:BAAALgAECgYJEgABLgAFFAUJHwAWANMbAA==.Shmerek:BAABLgAECn8XAAICAAkJRSAUCAB4AgACAAkJRSAUCAB4AgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAgAAAA==.Silverlumen:BAAALgAECgYJEgAAAA==.Silversaevus:BAAALgADCgQJBAAAAA==.Silverstream:BAACLgAFFH8IAAISAAMJGgrbRwCUAAASAAMJGgrbRwCUAAAuAAQKfyoAAhIACQnoER1CAJkBABIACQnoER1CAJkBAAAA.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAABLgAECn8VAAINAAkJQxCoEwAJAgANAAkJQxCoEwAJAgAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJDAABLgAECgkJIwAbAFYYAA==.Solitudé:BAABLgAECn8eAAMPAAgJBiT8HgBpAgAPAAcJPiH8HgBpAgAQAAUJoSU7FAAoAQABLgAFFAUJDwAeAP4fAA==.Soteirian:BAABLgAECn8rAAMWAAkJdAsFdgCAAQAWAAkJdAsFdgCAAQAjAAEJjwK9XQASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn8zAAIfAAkJTRzTGACvAgAfAAkJTRzTGACvAgAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8rAAMgAAgJMhCARgCQAQAgAAgJMhCARgCQAQAHAAYJ0RODRAAdAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAZAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgYJCwABLgAECgkJQwAWAGgkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn9AAAIEAAkJ/hYjKAA6AgAEAAkJ/hYjKAA6AgAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIKAAkJPCUnBAAHAwAKAAkJPCUnBAAHAwAAAA==.Syriene:BAABLgAECn8oAAInAAkJzg7PEgCKAQAnAAkJzg7PEgCKAQABLgAECgkJFgATAOoIAA==.',
Ta='Tankhealz:BAAALgAECgMJBQAAAA==.Tanthe:BAAALgAECgMJAwAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQABLgAFFAUJFgAIAEocAA==.',
Te='Tecks:BAABLgAECn8XAAIkAAkJwgW9OwABAQAkAAkJwgW9OwABAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.',
Th='Theatrix:BAAALgAECgQJBAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8oAAMDAAkJGBX+DwDtAQADAAkJGBX+DwDtAQAYAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thiaraxo:BAABLgAECn8VAAIIAAkJmwVsdgCuAAAIAAkJmwVsdgCuAAAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8lAAIWAAkJlCVXBQBJAwAWAAkJlCVXBQBJAwAAAA==.Thsarus:BAABLgAECn8vAAMLAAgJ6yBiHABnAgALAAgJ6yBiHABnAgAiAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAISAAkJmgSheADKAAASAAkJmgSheADKAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBgAAAA==.',
Tk='Tkt:BAAALgAECgIJAwABLgAECgUJCQAFAAAAAA==.',
To='Toatani:BAAALgAECgQJBQABLgAECgQJBgAFAAAAAA==.Tokkaebi:BAAALgAECgkJAwAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAFFAUJBQAPAIUWAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIIAAUJShxTGgCTAQAIAAUJShxTGgCTAQAuAAQKfywAAwgACQn/GUgcADACAAgACQn/GUgcADACABoABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8jAAIbAAkJVhiFOwApAgAbAAkJVhiFOwApAgAAAA==.',
Ug='Ugolok:BAABLgAECn8iAAMeAAcJ3AUAIQDBAAAfAAcJcARG1wDcAAAeAAYJQwYAIQDBAAAAAA==.',
Ur='Uriél:BAABLgAECn8uAAILAAkJNSWBAgBeAwALAAkJNSWBAgBeAwABLgAFFAUJDwAeAP4fAA==.',
Va='Valeene:BAABLgAECn8tAAIUAAkJLiI2BAAdAwAUAAkJLiI2BAAdAwAAAA==.Varek:BAAALgAECgkJEwAAAA==.',
Ve='Veiler:BAABLgAECn9GAAMEAAkJERNBNQAEAgAEAAkJERNBNQAEAgAmAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8oAAIbAAkJqANZpAAxAQAbAAkJqANZpAAxAQAAAA==.',
Vh='Vhye:BAABLgAFFH8FAAIgAAMJmANpYQB+AAAgAAMJmANpYQB+AAAAAA==.',
Vi='Vidnoi:BAAALgAECgEJAwAAAA==.Vinstalation:BAABLgAECn81AAIeAAkJcRwGBgBJAgAeAAkJcRwGBgBJAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8jAAMEAAkJ8hP2SwC5AQAEAAkJ8hP2SwC5AQAmAAEJFw9aPQAtAAAAAA==.',
Vr='Vritraz:BAACLgAFFH8PAAMeAAUJ/h+mBwBqAQAeAAQJ/h+mBwBqAQAfAAEJAABHJAEAAAAuAAQKfxUAAx4ACQmLIn0GADsCAB4ABwk+I30GADsCAB8AAgl0IHLzALgAAAAA.Vrock:BAAALgAECgEJAQABLgAECgkJKQAbAHIeAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8RAAIEAAQJ/AUpUAACAQAEAAQJ/AUpUAACAQAuAAQKfyIAAgQACQkAEF5FAJsBAAQACQkAEF5FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgQJDgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Xe='Xendria:BAAALgAECgEJAgAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaye:BAAALgAECggJDAAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIfAAgJJxE+kwBZAQAfAAgJJxE+kwBZAQAAAA==.Zendonn:BAABLgAECn8bAAIBAAcJxwVKUADCAAABAAcJxwVKUADCAAAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIJAAkJdxlFFQDAAQAJAAkJdxlFFQDAAQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMSAAkJ+RXSNwDIAQASAAkJ+RXSNwDIAQAUAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAAAAA==.',
['ßo']='ßoomer:BAAALgADCgIJAgABLgAFFAMJBwABALYHAA==.',
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
