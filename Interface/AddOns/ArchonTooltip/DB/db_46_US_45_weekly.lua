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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Monk-Mistweaver','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Affliction','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warrior-Protection','Evoker-Devastation','Druid-Feral','Druid-Restoration','Monk-Brewmaster','Mage-Frost','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Druid-Guardian','Warlock-Destruction','Monk-Windwalker','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','Hunter-Marksmanship','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8hAAIBAAgJMRzmVwClAQABAAgJMRzmVwClAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzgjIKABhAQACAAkJzgjIKABhAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn8bAAIBAAgJ1AtZgABNAQABAAgJ1AtZgABNAQAAAA==.',
Aj='Ajaki:BAABLgAECn8iAAQEAAcJ6xdmHgCtAQAEAAcJ6xdmHgCtAQAFAAYJJwc6OwDtAAACAAIJDAkTXwBdAAAAAA==.',
Al='Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJAwAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgYJEAAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgIJAgAAAA==.Anklebiter:BAAALgADCgIJAgAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECggJDgAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgQJBwAAAA==.Arlan:BAABLgAECn8XAAIGAAgJcx7MEwBLAgAGAAgJcx7MEwBLAgAAAA==.Arlequin:BAABLgAECn8ZAAMHAAkJjgmtkADVAAAHAAcJMAmtkADVAAAIAAMJqApwQwBnAAAAAA==.Arnagan:BAAALgAECgIJAgAAAA==.',
As='Asale:BAAALgAECgEJAQAAAA==.Ascend:BAAALgAECgYJCAABLgAECggJFQAJAJ0YAA==.Asharothh:BAABLgAECn8eAAIKAAkJ6ho9FgARAgAKAAkJ6ho9FgARAgAAAA==.Ashdem:BAAALgAECgcJDAAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAAALgAECggJEwAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1gdMcwAvAAAFAAIJFgKrbgAgAAAAAA==.Azkar:BAAALgADCgEJAQAAAA==.Azorahai:BAABLgAECn8mAAILAAcJ1we4nQAIAQALAAcJ1we4nQAIAQAAAA==.Azshalia:BAAALgAECgUJDAAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8fAAQMAAgJTg8lCQBwAQAMAAgJ9Q0lCQBwAQANAAYJpA3vNQBgAQAOAAIJTA3CGgBkAAAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMIAAcJ6R3LDwD1AQAIAAcJ6R3LDwD1AQAHAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8gAAIPAAgJFhOxRQCkAQAPAAgJFhOxRQCkAQAAAA==.',
Be='Beffis:BAAALgADCgMJAwAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8tAAMQAAkJuiVzAAAuAwAQAAkJmCVzAAAuAwAJAAgJ7B3KHQBYAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgARAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8bAAISAAgJqBzJFAAXAgASAAgJqBzJFAAXAgAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn8fAAITAAgJ2B2nFAB5AgATAAgJ2B2nFAB5AgAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAAALgAECgYJDgAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSJACgD7AgABAAkJrSJACgD7AgAAAA==.Bosshogshift:BAAALgAECgYJBgABLgAECgkJNAABAK0iAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8IAAIUAAUJfyAkBgAIAQAUAAUJfyAkBgAIAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgARAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bulgear:BAAALgAECgEJAQAAAA==.Bupropion:BAABLgAECn8eAAIHAAYJAhnkUwBnAQAHAAYJAhnkUwBnAQABLgAECgkJNQAVAMEfAA==.Bushwhacker:BAABLgAECn8hAAMRAAcJzg6mMAArAQARAAcJzg6mMAArAQAWAAIJJQu0LgBlAAAAAA==.Butterbean:BAABLgAECn8tAAIPAAkJCCB3CwDnAgAPAAkJCCB3CwDnAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECggJEAAAAA==.Catameringue:BAAALgAECgYJDwAAAA==.',
Ch='Chicxulub:BAAALgAECgcJDAAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMTAAkJKCBBCQDjAgATAAkJKCBBCQDjAgASAAYJCRHdQQD8AAAAAA==.Clickshoot:BAAALgAECgUJBQAAAA==.',
Co='Coaca:BAABLgAECn8gAAMBAAgJiBtZNwAEAgABAAgJiBtZNwAEAgAGAAEJEQdthwAmAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAECgkJIAAJAD4cAA==.Confluent:BAABLgAECn81AAMXAAkJQyUaAQDEAwAXAAkJQyUaAQDEAwARAAkJAhj7DQBSAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn83AAIYAAkJ7xJsHgCTAQAYAAkJ7xJsHgCTAQAAAA==.',
Cu='Cursè:BAAALgADCgIJAgABLgAECgkJKwAZAEkIAA==.',
Cy='Cythrandir:BAAALgAECgYJCwABLgAFFAMJDgAZAL0WAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.Davwr:BAAALgAECgMJAwABLgAECgYJBwADAAAAAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECgcJDgAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Dethrahzen:BAABLgAECn8iAAMVAAcJoQLWFACcAAAVAAcJoQLWFACcAAAaAAIJhwFwhQAlAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8oAAIbAAgJmRteHADmAQAbAAgJmRteHADmAQAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgAECgUJDAAAAA==.',
Do='Dorelios:BAAALgADCgMJAwAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJGAAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAAALgAECgYJDQAAAA==.',
Du='Dubstep:BAAALgAECgIJBAAAAA==.Dugatotems:BAABLgAECn8mAAMTAAkJPRjjGwA5AgATAAkJPRjjGwA5AgASAAkJYQjcMQBHAQAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dumpytruck:BAAALgAECgIJAwAAAA==.Dunkle:BAABLgAECn8tAAMcAAkJgyCYBQCMAgAbAAkJihz8EwCuAgAcAAkJzBuYBQCMAgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8ZAAIPAAgJ5AdZZQBLAQAPAAgJ5AdZZQBLAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEQAAAA==.',
Eb='Ebonise:BAAALgAECgUJCgAAAA==.',
Ed='Edrelang:BAAALgAECgcJDwAAAA==.',
Ee='Eerikki:BAAALgAECgUJCgAAAA==.',
Ei='Ein:BAABLgAECn8zAAIVAAkJXRoLAgCTAgAVAAkJXRoLAgCTAgAAAA==.',
El='Ellechero:BAABLgAECn8aAAMRAAcJVQUbRwC9AAARAAcJXAQbRwC9AAAdAAQJKAUyPQBmAAAAAA==.Ellonia:BAAALgADCgYJCwABLgAECggJHwAeAO4eAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Eragøn:BAABLgAECn8UAAIPAAcJ+xY1RQCmAQAPAAcJ+xY1RQCmAQAAAA==.Erinna:BAAALgAECgEJBAAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgYJDQAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgkJHgAUAFYIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.Fextrius:BAAALgAECgIJAgAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAABLgAECn8dAAILAAYJ0xbYeABMAQALAAYJ0xbYeABMAQABLgAFFAQJCwAbAD0YAA==.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgADCgcJDwAAAA==.Furrystorm:BAAALgAFFAEJAgAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIZAAkJlA6iUADNAQAZAAkJlA6iUADNAQAAAA==.',
Gh='Ghast:BAABLgAECn9GAAMJAAkJ4hTILgAFAgAJAAkJgxTILgAFAgAQAAEJqx3hLAA/AAAAAA==.Ghats:BAABLgAECn8VAAMJAAgJnRjEMAD9AQAJAAgJnRjEMAD9AQAeAAEJAAAUSQAAAAAAAA==.',
Gi='Gigaflare:BAABLgAECn8nAAIZAAkJqAwkgwDLAQAZAAkJqAwkgwDLAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatale:BAAALgAECgYJBgABLgAECgkJLAALAFQgAA==.Goatknight:BAABLgAECn8sAAILAAkJVCDPDQDfAgALAAkJVCDPDQDfAgAAAA==.Goatwings:BAAALgAECgIJAgAAAA==.Gobblynn:BAAALgADCggJEAAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAyntQD0AAABAAcJHAyntQD0AAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn8sAAIJAAgJUw4+bQBKAQAJAAgJUw4+bQBKAQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJBAAAAA==.Greywings:BAABLgAECn80AAIVAAgJjQ7ZCAB8AQAVAAgJjQ7ZCAB8AQAAAA==.Grimroxs:BAABLgAECn8kAAIOAAgJFwzwCQB5AQAOAAgJFwzwCQB5AQAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgADCgYJBgAAAA==.Grizzlemaw:BAAALgAECgUJCgAAAA==.',
Ha='Hacheros:BAAALgAECgIJAgAAAA==.Hairypits:BAAALgAECgQJCAABLgAECgkJLAALAFQgAA==.Handerbug:BAABLgAECn8uAAMRAAkJRyaAAgA3AwARAAkJRyaAAgA3AwAdAAYJtBxZEQCaAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgARAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgARAEcmAA==.Handybug:BAAALgADCgMJAwABLgAECgkJLgARAEcmAA==.Hankit:BAAALgAECgQJBQAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJBwAAAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAABLgAECn8bAAIEAAgJ3QpELABDAQAEAAgJ3QpELABDAQAAAA==.Heinrich:BAABLgAECn8vAAMBAAgJ8iMVEADMAgABAAgJ8iMVEADMAgAGAAQJPRFAbADJAAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.',
Ho='Hogglethorp:BAAALgAECggJDAAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCgkJEQAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAECgkJBAAAAA==.',
Il='Ilina:BAAALgAECgUJCQABLgAFFAIJAgADAAAAAA==.Illadron:BAAALgAECgYJCAAAAA==.Illecebra:BAAALgAECgYJDAAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAAALgAECggJEgAAAA==.',
Ja='Jagerblunt:BAABLgAECn8kAAIPAAkJqBmFJAAlAgAPAAkJqBmFJAAlAgAAAA==.',
Jd='Jdbud:BAAALgAECgIJAgAAAA==.Jdpot:BAAALgAECgUJCAAAAA==.',
Je='Jenaaidy:BAABLgAECn8YAAICAAYJhBAkNAAgAQACAAYJhBAkNAAgAQAAAA==.',
Jh='Jhannae:BAAALgADCgEJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLQAKAPIhAA==.Joshery:BAABLgAECn8tAAMKAAkJ8iGLBQAJAwAKAAkJ8iGLBQAJAwAfAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJBwABLgAECgkJLQAKAPIhAA==.',
Ju='Judge:BAABLgAECn8pAAIBAAgJyhKzVACtAQABAAgJyhKzVACtAQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8hAAIgAAgJLx+2CgA3AgAgAAgJLx+2CgA3AgAAAA==.',
Ka='Katasaria:BAACLgAFFH8QAAMbAAQJAR40DQBmAQAbAAQJAR40DQBmAQAcAAEJxxRiKwBKAAAuAAQKfysAAxsACAmNIBAQAFUCABsACAkXIBAQAFUCABwABQk0GoYjABwBAAAA.Kaycee:BAAALgADCgUJCAABLgAECggJHwAMAE4PAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECggJHwAMAE4PAA==.Kaycer:BAAALgADCggJDwABLgAECggJHwAMAE4PAA==.',
Ke='Keeps:BAAALgADCgEJAQAAAA==.Kerl:BAAALgAECggJEQAAAA==.',
Ki='Kiboridi:BAAALgAECgQJBQAAAA==.Kimetshu:BAABLgAECn8eAAIIAAgJARRoFwCUAQAIAAgJARRoFwCUAQAAAA==.Kirana:BAABLgAECn8fAAIRAAgJhwW4PADrAAARAAgJhwW4PADrAAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAILAAgJRAttkABfAQALAAgJRAttkABfAQAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIWAAkJqBuIBACPAgAWAAkJqBuIBACPAgAAAA==.Kravin:BAAALgAECgIJAgAAAA==.Krunzar:BAAALgAECgMJBQAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Laneywine:BAAALgAECgUJCwAAAA==.Larlifax:BAAALgAECgUJBwAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8wAAIbAAkJTyWFAQBUAwAbAAkJTyWFAQBUAwAAAA==.Levìstus:BAABLgAECn8gAAILAAgJDBd0RgDMAQALAAgJDBd0RgDMAQAAAA==.Leylaní:BAABLgAECn8bAAIPAAgJnRTtPgC7AQAPAAgJnRTtPgC7AQAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgIJAwAAAA==.Loroessan:BAAALgAECgUJCAAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAAALgAECgUJCwAAAA==.Lukas:BAAALgAECgcJCQABLgAECgkJRgAJAOIUAA==.Lunet:BAAALgAECgEJAQAAAA==.Lustie:BAAALgAECgYJEwABLgAECgkJNQAVAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAVAMEfAA==.Lytheum:BAABLgAECn81AAIVAAkJwR97AQDAAgAVAAkJwR97AQDAAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQATACggAA==.Magerrac:BAAALgADCgkJDAABLgAECgkJHgAUAFYIAA==.Malachar:BAABLgAECn8fAAIUAAgJXAtNHAAqAQAUAAgJXAtNHAAqAQAAAA==.Malboro:BAABLgAECn8pAAIJAAcJeRPMYABoAQAJAAcJeRPMYABoAQAAAA==.Maled:BAABLgAECn8YAAQQAAYJfx1zCwBvAQAQAAYJ7RtzCwBvAQAJAAMJohAXwgCqAAAeAAIJVBmXHgCSAAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrew:BAAALgAECgkJBwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Mej:BAAALgAECgQJBAAAAA==.Meldin:BAABLgAECn8bAAIPAAgJUR+yGwBWAgAPAAgJUR+yGwBWAgAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgUJCQAAAA==.Method:BAABLgAECn8rAAMhAAkJBxQ2DgCyAQAhAAkJhxM2DgCyAQABAAIJFxM2CgF4AAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMGAAcJdh3zHgDkAQAGAAcJdh3zHgDkAQABAAEJJgFZhwETAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIfAAkJ5BmhDABUAgAfAAkJ5BmhDABUAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8gAAMHAAgJDxYXQQCkAQAHAAgJxhUXQQCkAQAiAAEJeRgmKQBAAAAAAA==.Mineos:BAAALgAECgYJDwAAAA==.Mistrmiso:BAAALgAECgEJAQABLgAECgkJLQAQALolAA==.Mizoh:BAAALgAECgYJDwAAAA==.',
Mo='Moahuntress:BAAALgAECgYJCQAAAA==.Moonlyt:BAAALgADCgkJIAAAAA==.Morgaine:BAAALgADCgUJBQABLgAECgkJHgAUAFYIAA==.Morn:BAABLgAECn8ZAAMVAAgJaBp+BwBzAgAVAAgJaBp+BwBzAgAaAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJRgAJAOIUAA==.',
Mt='Mtrain:BAAALgAECgMJBQABLgAECggJFQAJAJ0YAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgAECgMJAwAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAABLgAECn8bAAIgAAgJuRWQEgC3AQAgAAgJuRWQEgC3AQAAAA==.Nestiae:BAAALgAECgMJAwAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAECgkJBAADAAAAAA==.Nightsfuri:BAABLgAECn8bAAIRAAgJHxNnIgCIAQARAAgJHxNnIgCIAQAAAA==.Nik:BAAALgAECgQJBQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8WAAIPAAgJ3Qy9UwB5AQAPAAgJ3Qy9UwB5AQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orialis:BAAALgADCgQJBAABLgADCgcJGAADAAAAAA==.Orlandbro:BAABLgAECn8nAAQPAAkJ2x1iGAB3AgAjAAkJxhy4BQCyAgAPAAkJ4BdiGAB3AgAkAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAAALgAECggJEgAAAA==.Patchy:BAAALgAECgQJBAAAAA==.Pawradox:BAABLgAECn8hAAICAAkJ8wzZIACYAQACAAkJ8wzZIACYAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAgAAAA==.',
Ph='Phenomenon:BAAALgAECgYJDwAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIgAAkJUh5bCABrAgAgAAkJUh5bCABrAgAAAA==.Pitviper:BAAALgAECgQJDgAAAA==.',
Pl='Plina:BAABLgAECn8ZAAIBAAgJDhYFTADEAQABAAgJDhYFTADEAQAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponglenis:BAAALgAECgMJAwABLgAECgkJBAADAAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAAALgAFFAMJBAAAAA==.',
Pu='Pulli:BAAALgAECgkJDwAAAA==.',
Pv='Pve:BAABLgAECn8pAAIjAAkJaB5BCQBxAgAjAAkJaB5BCQBxAgAAAA==.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8eAAITAAkJdxMMKQDqAQATAAkJdxMMKQDqAQAAAA==.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIZAAcJcRRAfABiAQAZAAcJcRRAfABiAQAAAA==.Rathane:BAACLgAFFH8FAAIPAAQJtQrFNAASAQAPAAQJtQrFNAASAQAuAAQKfxwAAg8ACAm1HCAjADMCAA8ACAm1HCAjADMCAAAA.Ray:BAAALgAECgYJBgABLgAECggJGQAVAGgaAA==.',
Re='Realmclovin:BAAALgADCgQJBAAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8hAAIGAAgJrSbPAQCBAwAGAAgJrSbPAQCBAwAAAA==.',
Ri='Rizzwan:BAABLgAECn8fAAIjAAgJqh6aDABAAgAjAAgJqh6aDABAAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMfAAMJYQkiHQC8AAAfAAMJYQkiHQC8AAAKAAIJ0AwDNABuAAAuAAQKfykABAoACQmMHbEMAJsCAAoACAmXHLEMAJsCAB8ACAmwG+4OADMCABgAAQmJDk9+ADUAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAECgMJBAABLgAFFAQJEAAbAAEeAA==.Romy:BAABLgAECn8YAAIZAAYJ8wEg8wCUAAAZAAYJ8wEg8wCUAAAAAA==.Roonoe:BAAALgAECgIJAgAAAA==.',
Ru='Runecleaver:BAABLgAECn87AAMTAAkJBCLPDADJAgATAAkJBCLPDADJAgASAAQJExZYRQDuAAAAAA==.Ruw:BAABLgAECn8fAAMOAAcJxhF5CgBtAQAOAAcJSxF5CgBtAQANAAMJ9QiyPACXAAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8jAAILAAkJxB9NEgC8AgALAAkJxB9NEgC8AgAAAA==.Satania:BAABLgAECn8fAAIIAAkJGiTyBAAlAwAIAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8ZAAMCAAgJGQ7UNgASAQACAAYJ9A/UNgASAQAEAAUJ2Q+iPgDQAAAAAA==.',
Se='Segora:BAABLgAECn8aAAIJAAYJRAcGnwAbAQAJAAYJRAcGnwAbAQABLgAECggJLAAJAFMOAA==.Seimus:BAAALgAECgUJDwAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAAALgAECgYJDAAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAAALgAECgUJDgAAAA==.Sharius:BAABLgAECn8rAAIZAAkJSQjMagCJAQAZAAkJSQjMagCJAQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIZAAkJ6hJwZAAPAgAZAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJCQAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.Shutendoji:BAAALgAECgEJAgABLgAECggJHQAfAKohAA==.',
Si='Sightlightx:BAAALgAECggJEAAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8mAAIbAAgJawr4NABPAQAbAAgJawr4NABPAQAAAA==.Siryn:BAABLgAECn8XAAIGAAYJ8ANYVQCzAAAGAAYJ8ANYVQCzAAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smashn:BAAALgAECgQJBAAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAECgYJDAADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAIlAAkJmBOSAgAGAgAlAAkJmBOSAgAGAgAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgAECgEJAQAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMXAAkJAB7UEACxAgAXAAkJAB7UEACxAgARAAcJnhUbJgBtAQAAAA==.Syrden:BAAALgAECgMJAgABLgAECgkJFgAXAOgLAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCgYJCwAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJCAAAAA==.Tessarion:BAAALgAECgkJCQAAAA==.',
Th='Thandas:BAABLgAECn8lAAIBAAcJ9gjhpAAOAQABAAcJ9gjhpAAOAQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAgAAAA==.Thniper:BAABLgAECn8oAAMkAAkJURgyGABrAgAkAAgJQBsyGABrAgAjAAUJ9wwLKwAnAQAAAA==.Thouvan:BAAALgAECgEJAQAAAA==.Thugnastyy:BAAALgAECgIJBQABLgAECgkJBAADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIGAAkJqxreEQBhAgAGAAkJqxreEQBhAgAAAA==.',
To='Tost:BAAALgADCgcJBwAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.Tusker:BAAALgADCgQJBAAAAA==.',
Ty='Tyinviril:BAABLgAECn9GAAICAAkJLCV9AQBYAwACAAkJLCV9AQBYAwAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8QAAMBAAYJFw+LFQB9AQABAAYJFw+LFQB9AQAGAAEJRgEsPAA+AAAuAAQKfzoAAwEACAkQIaQZAIsCAAEACAkQIaQZAIsCAAYABQk8CflgAPgAAAAA.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAAALgAECgcJEgAAAA==.Vonawesome:BAAALgAECgQJCAAAAA==.Vorpalblade:BAABLgAECn8uAAIUAAkJMRdMDAABAgAUAAkJMRdMDAABAgAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAAALgAFFAEJAgAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgADCgkJCQAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8vAAMmAAkJoB4HAQDOAgAmAAkJoB4HAQDOAgAZAAEJPBlNIgFBAAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIhAAkJfhJGDgCxAQAhAAkJfhJGDgCxAQAAAA==.Willowfox:BAAALgAECgMJCAAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJCgAAAA==.Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgAECgUJCAAAAA==.Wram:BAABLgAECn8eAAMUAAkJVgj1GwAtAQAUAAkJVgj1GwAtAQAbAAIJJAF3mQAbAAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECgkJHgAUAFYIAA==.Wreckuiem:BAAALgAECggJEAAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8fAAMeAAgJ7h5MBAARAgAeAAgJ8x1MBAARAgAJAAYJmBafSQCnAQAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAACLgAFFH8LAAIHAAQJ8RgeJwBKAQAHAAQJ8RgeJwBKAQAuAAQKfysAAgcACQm5HgoNAMICAAcACQm5HgoNAMICAAAA.',
Xr='Xristinà:BAAALgADCgkJCQAAAA==.',
Zi='Zillara:BAABLgAECn8XAAIOAAkJIAX1DQApAQAOAAkJIAX1DQApAQAAAA==.',
['Zù']='Zùlfang:BAAALgAECgUJBQABLgAECgkJKwAbAGgZAA==.',
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
