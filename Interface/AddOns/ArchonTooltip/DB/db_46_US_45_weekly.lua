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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Monk-Mistweaver','Warrior-Protection','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Affliction','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Hunter-Marksmanship','Evoker-Devastation','Druid-Feral','Druid-Restoration','Mage-Frost','Monk-Brewmaster','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Druid-Guardian','Warlock-Destruction','Monk-Windwalker','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Frost','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8jAAIBAAkJBRxiRgDoAQABAAkJBRxiRgDoAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzgioLwBZAQACAAkJzgioLwBZAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn8oAAIBAAgJPA7CfgBmAQABAAgJPA7CfgBmAQAAAA==.',
Aj='Ajaki:BAABLgAECn8iAAQEAAcJ6xfaIwCXAQAEAAcJ6xfaIwCXAQAFAAYJJwcDRQDjAAACAAIJDAlrbQBbAAAAAA==.',
Al='Allandra:BAAALgAECgYJBgAAAA==.Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJAwAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgYJEAAAAA==.Amelandra:BAAALgAECgEJAQAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgIJAgAAAA==.Anklebiter:BAAALgAECgEJAQAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECgkJEQAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgcJDQAAAA==.Arlan:BAABLgAECn8fAAIGAAkJdR7VDQCrAgAGAAkJdR7VDQCrAgAAAA==.Arlequin:BAABLgAECn8ZAAMHAAkJjgnLowDOAAAHAAcJMAnLowDOAAAIAAMJqApHTwBlAAAAAA==.Arnagan:BAAALgAECgUJBQAAAA==.',
As='Asale:BAAALgAECgEJAQAAAA==.Ascend:BAAALgAECgYJCAABLgAECggJFQAJAJ0YAA==.Asharothh:BAABLgAECn8mAAIKAAkJYxteFQBdAgAKAAkJYxteFQBdAgAAAA==.Ashdem:BAABLgAECn8ZAAIHAAcJNw6vfQAYAQAHAAcJNw6vfQAYAQAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAABLgAECn8WAAILAAgJ1RKiFwB4AQALAAgJ1RKiFwB4AQAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1geghQAtAAAFAAIJFgLefwAfAAAAAA==.Azkar:BAAALgADCgEJAQAAAA==.Azorahai:BAABLgAECn8oAAIMAAgJDwg/iQBJAQAMAAgJDwg/iQBJAQAAAA==.Azshalia:BAABLgAECn8ZAAILAAcJqQnDJwDmAAALAAcJqQnDJwDmAAAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8nAAQNAAgJURAOCgB5AQANAAgJMA8OCgB5AQAOAAYJpA3vNQBgAQAPAAcJkQyfDQBCAQAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMIAAcJ6R17EwDqAQAIAAcJ6R17EwDqAQAHAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8tAAIQAAgJhhZ+OgDqAQAQAAgJhhZ+OgDqAQAAAA==.',
Be='Beffis:BAAALgAECgMJAwAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8vAAMRAAkJuiWMAAA0AwARAAkJmCWMAAA0AwAJAAgJ7B2zIwBLAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgASAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8oAAITAAgJuB0/FAA7AgATAAgJuB0/FAA7AgAAAA==.Boblin:BAAALgAECgUJDQAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn8tAAIUAAkJ6B+3CQANAwAUAAkJ6B+3CQANAwAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAABLgAECn8XAAMQAAcJowLVwgCuAAAQAAYJswLVwgCuAAAVAAQJYgIUMwBGAAAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSJqDgDpAgABAAkJrSJqDgDpAgAAAA==.Bosshogshift:BAAALgAECgYJBgABLgAECgkJNAABAK0iAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8IAAILAAUJfyAkBgAIAQALAAUJfyAkBgAIAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgASAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bulgear:BAAALgAECgMJBgAAAA==.Bupropion:BAABLgAECn8eAAIHAAYJAhkvXQBlAQAHAAYJAhkvXQBlAQABLgAECgkJNQAWAMEfAA==.Bushwhacker:BAABLgAECn8hAAMSAAcJzw4nNwAqAQASAAcJzw4nNwAqAQAXAAIJJQuWOgBdAAAAAA==.Butterbean:BAABLgAECn8tAAIQAAkJCCB3CwDnAgAQAAkJCCB3CwDnAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECggJEQAAAA==.Catameringue:BAABLgAECn8WAAIYAAcJBBFfQgB+AQAYAAcJBBFfQgB+AQAAAA==.',
Ch='Chickenhawk:BAAALgAECgEJAQAAAA==.Chicxulub:BAABLgAECn8XAAIZAAgJ7BN/WwDFAQAZAAgJ7BN/WwDFAQAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMUAAkJKCBBCQDjAgAUAAkJKCBBCQDjAgATAAYJCRFZSwD3AAAAAA==.Clickshoot:BAAALgAECgUJBQAAAA==.',
Co='Coaca:BAABLgAECn8tAAMBAAgJZh2mMQAvAgABAAgJZh2mMQAvAgAGAAEJEQfwkwAmAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAFFAIJBAAJANASAA==.Confluent:BAABLgAECn81AAMYAAkJQyV+AQDAAwAYAAkJQyV+AQDAAwASAAkJAhiuEABLAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn83AAIaAAkJ7xI2IgCPAQAaAAkJ7xI2IgCPAQAAAA==.',
Cu='Cursè:BAAALgADCgIJAgABLgAECgkJKwAZAEkIAA==.',
Cy='Cythrandir:BAAALgAECgYJDAABLgAFFAUJEwAZAP8RAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.Davwr:BAAALgAECgMJAwABLgAECgYJBwADAAAAAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECgkJEwAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Dethrahzen:BAABLgAECn8uAAMWAAgJdAOXEwDGAAAWAAgJdAOXEwDGAAAbAAIJhwHfkwAkAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8sAAIcAAkJpRrGFgAyAgAcAAkJpRrGFgAyAgAAAA==.',
Dj='Djcamsoda:BAAALgAECgEJAQAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgAECgYJDAAAAA==.',
Do='Doomslayer:BAAALgADCgcJBwAAAA==.Dorelios:BAAALgADCgMJAwAAAA==.Dotsfordayz:BAAALgAECgMJBAABLgAECgEJAgADAAAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJGAAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAABLgAECn8WAAMQAAYJbQU8qgDeAAAQAAYJbQU8qgDeAAAVAAMJGwAFnAAOAAAAAA==.',
Du='Dubstep:BAAALgAECgYJEAAAAA==.Dugatotems:BAABLgAECn8uAAMUAAkJPxrjGwA5AgAUAAkJPxrjGwA5AgATAAkJYQghOgA+AQAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dumpytruck:BAAALgAECgQJBQAAAA==.Dunkle:BAABLgAECn8tAAMdAAkJgyAsBwB8AgAcAAkJihz8EwCuAgAdAAkJzBssBwB8AgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8mAAIQAAgJNgzVWwCFAQAQAAgJNgzVWwCFAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEgAAAA==.',
Eb='Ebonise:BAAALgAECgUJCwAAAA==.',
Ed='Edrelang:BAABLgAECn8eAAMcAAcJ3QnuRgAgAQAcAAcJ3QnuRgAgAQAdAAIJrQSYaABAAAAAAA==.',
Ee='Eerikki:BAAALgAECgYJEQAAAA==.',
Ei='Eightsix:BAAALgAECgYJBgABLgAECggJFQAJAJ0YAA==.Ein:BAABLgAECn8zAAIWAAkJXRqkAgCBAgAWAAkJXRqkAgCBAgAAAA==.',
El='Ellechero:BAABLgAECn8kAAMeAAgJQAhbNADCAAASAAcJKQWuTQDHAAAeAAcJfQdbNADCAAAAAA==.Ellonia:BAAALgAECgMJAwABLgAECggJIAAfAO4eAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Eragøn:BAABLgAECn8WAAIQAAcJrBoaPgDdAQAQAAcJrBoaPgDdAQAAAA==.Erinna:BAAALgAECgEJBAAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgYJEAAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgkJHwALANAIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.Fextrius:BAAALgAECgYJCQAAAA==.',
Fl='Florassa:BAAALgADCgUJBQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAACLgAFFH8HAAIMAAMJFA4VmADTAAAMAAMJFA4VmADTAAAuAAQKfyEAAgwABgnTFomDAFQBAAwABgnTFomDAFQBAAEuAAUUBAkSABwA8B0A.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgADCgcJDwAAAA==.Furrystorm:BAAALgAFFAEJAgAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIZAAkJlA7AXADCAQAZAAkJlA7AXADCAQAAAA==.Garroc:BAAALgAECgYJBgAAAA==.',
Gh='Ghast:BAABLgAECn9ZAAMJAAkJdxkhLwAWAgAJAAkJPBUhLwAWAgARAAcJ8BIzCwCZAQAAAA==.Ghats:BAABLgAECn8VAAMJAAgJnRi8NwD1AQAJAAgJnRi8NwD1AQAfAAEJAABDUQAAAAAAAA==.',
Gi='Gigaflare:BAABLgAECn8nAAIZAAkJqAwkgwDLAQAZAAkJqAwkgwDLAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatale:BAAALgAECgYJCwABLgAECgkJLAAMAFQgAA==.Goatknight:BAABLgAECn8sAAIMAAkJVCC5EQDYAgAMAAkJVCC5EQDYAgAAAA==.Goatwings:BAAALgAECgIJAgAAAA==.Gobblynn:BAAALgADCggJEAAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAzU0gDiAAABAAcJHAzU0gDiAAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn86AAIJAAkJVg7pTACvAQAJAAkJVg7pTACvAQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJCAAAAA==.Greywings:BAABLgAECn82AAIWAAgJjQ5oCgBsAQAWAAgJjQ5oCgBsAQAAAA==.Grimroxs:BAABLgAECn8xAAIPAAgJaxBiCQCfAQAPAAgJaxBiCQCfAQAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgAECgEJAgABLgAECgEJAgADAAAAAA==.Grizzlemaw:BAAALgAECgcJDAAAAA==.',
Ha='Hacheros:BAAALgAECgIJAgAAAA==.Hadic:BAAALgADCgEJAQABLgAECgkJCQADAAAAAA==.Hairypits:BAAALgAECgYJDQABLgAECgkJLAAMAFQgAA==.Handerbug:BAABLgAECn8uAAMSAAkJRyYsAwAyAwASAAkJRyYsAwAyAwAeAAYJtByPFQCVAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgASAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgASAEcmAA==.Handybug:BAAALgAECgEJAQABLgAECgkJLgASAEcmAA==.Hankit:BAAALgAECgQJBQAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJCgAAAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Healtaxi:BAAALgAECgEJAgAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAABLgAECn8hAAIEAAkJIwvdKgBlAQAEAAkJIwvdKgBlAQAAAA==.Heinrich:BAABLgAECn8vAAMBAAgJ8iPOFAC9AgABAAgJ8iPOFAC9AgAGAAQJPRFAbADJAAAAAA==.Heira:BAAALgADCgQJCAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.Hippypedro:BAAALgAECgYJCwABLgAFFAUJGgAIAKEbAA==.',
Ho='Hogglethorp:BAAALgAECggJEwAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCgkJGgAAAA==.Horns:BAAALgADCgkJDwAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAFFAIJAwAAAA==.',
Il='Ilina:BAAALgAECgUJCwABLgAFFAIJAgADAAAAAA==.Illadron:BAAALgAFFAEJAgAAAA==.Illecebra:BAAALgAECgYJDAAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAABLgAECn8cAAMSAAgJSApyNgAtAQASAAgJSApyNgAtAQAYAAMJUgy7mAB2AAAAAA==.',
Ja='Jagerblunt:BAACLgAFFH8GAAIQAAMJ4REgVADqAAAQAAMJ4REgVADqAAAuAAQKfyQAAhAACQmoGZ8tABsCABAACQmoGZ8tABsCAAAA.',
Jd='Jdbud:BAAALgAECgIJAgAAAA==.Jdpot:BAAALgAECgYJEAAAAA==.',
Je='Jenaaidy:BAABLgAECn8mAAICAAcJ1xQuJwCLAQACAAcJ1xQuJwCLAQAAAA==.',
Jh='Jhannae:BAAALgADCgEJAQAAAA==.',
Ji='Jiks:BAAALgAECgIJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLgAKAPIhAA==.Joshery:BAABLgAECn8uAAMKAAkJ8iGLBQAJAwAKAAkJ8iGLBQAJAwAgAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJCQABLgAECgkJLgAKAPIhAA==.',
Ju='Judge:BAABLgAECn8rAAIBAAgJyhKHZQCZAQABAAgJyhKHZQCZAQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8uAAIhAAgJfyHeBwCSAgAhAAgJfyHeBwCSAgAAAA==.',
Ka='Katasaria:BAACLgAFFH8SAAMcAAUJAR7DFABUAQAcAAUJAR7DFABUAQAdAAEJxxShOABKAAAuAAQKfysAAxwACAmNIOoTAEsCABwACAkXIOoTAEsCAB0ABQk0Gl0qABgBAAAA.Kaycee:BAAALgADCgUJCAABLgAECggJJwANAFEQAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECggJJwANAFEQAA==.Kaycer:BAAALgADCggJDwABLgAECggJJwANAFEQAA==.',
Ke='Keeps:BAAALgAECgEJAQAAAA==.Kerl:BAAALgAECggJEQABLgAECgkJCQADAAAAAA==.',
Ki='Kiboridi:BAAALgAECgQJBQAAAA==.Kimetshu:BAABLgAECn8gAAIIAAgJaBTFGwCPAQAIAAgJaBTFGwCPAQAAAA==.Kirana:BAABLgAECn8sAAMSAAgJgQYPQgD2AAASAAgJgQYPQgD2AAAYAAUJRAQDlACBAAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAIMAAgJRAttkABfAQAMAAgJRAttkABfAQAAAA==.',
Ko='Kolaro:BAAALgAECgEJAQAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIXAAkJqBvgBQCCAgAXAAkJqBvgBQCCAgAAAA==.Kravin:BAAALgAECgQJBwAAAA==.Krunzar:BAAALgAECgMJBQAAAA==.',
Kt='Ktheir:BAAALgAECgIJAgAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Lammasthan:BAAALgAECgkJCQAAAA==.Laneywine:BAAALgAECgYJDAAAAA==.Larlifax:BAAALgAECgUJBwAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8yAAIcAAkJcSUuAgBQAwAcAAkJcSUuAgBQAwAAAA==.Levìstus:BAABLgAECn8oAAIMAAgJHhgWQQD4AQAMAAgJHhgWQQD4AQAAAA==.Leylaní:BAABLgAECn8jAAIQAAkJrRQzLAAhAgAQAAkJrRQzLAAhAgAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgUJBwAAAA==.Loroessan:BAAALgAECgcJDwAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAAALgAECgcJEwAAAA==.Lukas:BAAALgAECgcJCQABLgAECgkJWQAJAHcZAA==.Lunet:BAAALgAECgcJBwAAAA==.Lustie:BAAALgAECgYJEwABLgAECgkJNQAWAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAWAMEfAA==.Lytheum:BAABLgAECn81AAIWAAkJwR/zAQCwAgAWAAkJwR/zAQCwAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
['Lü']='Lücid:BAAALgAECgEJAgAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQAUACggAA==.Magerrac:BAAALgAECgEJAQABLgAECgkJHwALANAIAA==.Magista:BAAALgAECgIJAgAAAA==.Malachar:BAABLgAECn8sAAILAAgJWg4iGwBSAQALAAgJWg4iGwBSAQAAAA==.Malboro:BAABLgAECn8qAAIJAAgJ7BIhVgCVAQAJAAgJ7BIhVgCVAQAAAA==.Maled:BAABLgAECn8lAAQRAAcJOh5pDQByAQARAAYJ7RtpDQByAQAfAAMJLRxNFQDxAAAJAAMJohAk1gChAAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrew:BAAALgAECgkJBwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Mej:BAAALgAECgQJBAAAAA==.Meldin:BAABLgAECn8jAAIQAAkJZCDUDQDZAgAQAAkJZCDUDQDZAgAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgUJCQAAAA==.Method:BAABLgAECn8rAAMiAAkJBxTeEACpAQAiAAkJhxPeEACpAQABAAIJFxOPLAFwAAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMGAAcJdh1sIwDfAQAGAAcJdh1sIwDfAQABAAEJJgEKuwERAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIgAAkJ5BlsDwBIAgAgAAkJ5BlsDwBIAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8nAAMHAAgJGBZcRwCkAQAHAAgJzxVcRwCkAQAjAAEJeRgmKQBAAAAAAA==.Mineos:BAABLgAECn8XAAIcAAcJvAtSQgAzAQAcAAcJvAtSQgAzAQAAAA==.Minipedro:BAAALgAECgEJAQABLgAFFAUJGgAIAKEbAA==.Mistrmiso:BAAALgAECgMJAgABLgAECgkJLwARALolAA==.Mizoh:BAAALgAECgYJEAAAAA==.',
Mo='Moahuntress:BAAALgAECgYJCQAAAA==.Moonlyt:BAAALgADCgkJIQAAAA==.Morgaine:BAAALgADCggJDAABLgAECgkJHwALANAIAA==.Morn:BAABLgAECn8bAAMWAAkJNRt+BwBzAgAWAAkJNRt+BwBzAgAbAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJWQAJAHcZAA==.',
Mt='Mtrain:BAAALgAECgYJCgABLgAECggJFQAJAJ0YAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myori:BAAALgAECgEJAQAAAA==.Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgAECgYJCAAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAABLgAECn8jAAIhAAkJSRcxDwALAgAhAAkJSRcxDwALAgAAAA==.Neeryn:BAAALgAECgIJAgAAAA==.Nestiae:BAAALgAECgMJAwABLgAECgYJCQADAAAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAFFAIJAwADAAAAAA==.Nightsfuri:BAABLgAECn8bAAISAAgJHxM2JwCHAQASAAgJHxM2JwCHAQAAAA==.Nik:BAAALgAECgQJBQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8eAAIQAAgJ3Qw+XwB8AQAQAAgJ3Qw+XwB8AQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orlandbro:BAABLgAECn8nAAQQAAkJ2x1iGAB3AgAkAAkJxhy4BQCyAgAQAAkJ4BdiGAB3AgAVAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAABLgAECn8XAAMMAAkJpA6aiwBEAQAMAAkJHg2aiwBEAQAhAAQJpg8FMgDJAAAAAA==.Patchy:BAAALgAECgQJBAAAAA==.Pawradox:BAABLgAECn8kAAICAAkJ8wxlJgCRAQACAAkJ8wxlJgCRAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAwAAAA==.',
Ph='Phenomenon:BAABLgAECn8UAAIQAAcJXB6yLgAWAgAQAAcJXB6yLgAWAgAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIhAAkJUh7iBwCpAgAhAAkJUh7iBwCpAgAAAA==.Pitviper:BAABLgAECn8UAAIlAAYJBxkAEwA5AQAlAAYJBxkAEwA5AQAAAA==.',
Pl='Plina:BAABLgAECn8hAAIBAAkJGhczOgAPAgABAAkJGhczOgAPAgAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponglenis:BAAALgAECgMJBwABLgAFFAIJAwADAAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAABLgAFFH8GAAIUAAMJmQqzUQCbAAAUAAMJmQqzUQCbAAAAAA==.',
Pu='Pulli:BAAALgAECgkJEQAAAA==.',
Pv='Pve:BAACLgAFFH8FAAIkAAUJBwW4HADbAAAkAAUJBwW4HADbAAAuAAQKfy0AAiQACQn0HwgGAL0CACQACQn0HwgGAL0CAAAA.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8eAAIUAAkJdxNEMADmAQAUAAkJdxNEMADmAQAAAA==.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIZAAcJcRR0iwBbAQAZAAcJcRR0iwBbAQAAAA==.Rathane:BAACLgAFFH8FAAIQAAQJtQoyRwANAQAQAAQJtQoyRwANAQAuAAQKfxwAAhAACAm1HCAjADMCABAACAm1HCAjADMCAAAA.Rawrmuch:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.Ray:BAAALgAECgYJBgABLgAECgkJGwAWADUbAA==.',
Re='Realmclovin:BAAALgAECgUJBQAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Redrabbit:BAAALgAECgYJBwAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8pAAIGAAgJrSYgAgCIAwAGAAgJrSYgAgCIAwAAAA==.',
Ri='Rizzwan:BAABLgAECn8mAAIkAAgJwCAJCACZAgAkAAgJwCAJCACZAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMgAAMJYQmpJQCxAAAgAAMJYQmpJQCxAAAKAAIJ0Az3RABqAAAuAAQKfykABAoACQmMHT8PAJwCAAoACAmXHD8PAJwCACAACAmwG+MRACgCABoAAQmJDkmKADQAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAECgMJBAABLgAFFAUJEgAcAAEeAA==.Romy:BAABLgAECn8lAAIZAAcJNwKA8QC5AAAZAAcJNwKA8QC5AAAAAA==.Roonoe:BAAALgAECgMJAwAAAA==.',
Ru='Runecleaver:BAABLgAECn87AAMUAAkJBCIoEADDAgAUAAkJBCIoEADDAgATAAQJExYpTgDtAAAAAA==.Ruw:BAABLgAECn8lAAMPAAgJkxDTCwBoAQAPAAcJXRLTCwBoAQAOAAQJKgiMPQDAAAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8lAAIMAAkJ7h9rFQC+AgAMAAkJ7h9rFQC+AgAAAA==.Satania:BAABLgAECn8fAAIIAAkJGiTyBAAlAwAIAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8mAAMEAAgJJxV0GAD8AQAEAAgJJxV0GAD8AQACAAYJBRNqNgA0AQAAAA==.',
Se='Segora:BAABLgAECn8aAAIJAAYJRAcGnwAbAQAJAAYJRAcGnwAbAQABLgAECgkJOgAJAFYOAA==.Seimus:BAAALgAECgUJEwAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAABLgAECn8UAAIBAAYJFBEIrAAZAQABAAYJFBEIrAAZAQAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAABLgAECn8hAAISAAgJ7Qb7PgAEAQASAAgJ7Qb7PgAEAQAAAA==.Sharius:BAABLgAECn8rAAIZAAkJSQjHeACAAQAZAAkJSQjHeACAAQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIZAAkJ6hJwZAAPAgAZAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJDgAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.Shutendoji:BAAALgAECgEJAgABLgAECggJHQAgAKohAA==.',
Si='Sightlightx:BAAALgAECggJEwAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8xAAIcAAkJvgrGLgCNAQAcAAkJvgrGLgCNAQAAAA==.Siryn:BAABLgAECn8eAAIGAAcJhANaWwC8AAAGAAcJhANaWwC8AAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smallest:BAAALgADCgYJBgABLgAECggJJwANAFEQAA==.Smashn:BAAALgAECgcJEAAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.Snakeshadow:BAAALgAECgkJCQAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAECgYJDAADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAImAAkJmBM5AwDtAQAmAAkJmBM5AwDtAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgAECgEJAQAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMYAAkJAB7UEACxAgAYAAkJAB7UEACxAgASAAcJnhV9KwBrAQAAAA==.Syrden:BAAALgAECgYJCAABLgAECgkJFgAYAOgLAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCggJDQAAAA==.Tanholy:BAAALgAECgEJAQAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJCAAAAA==.Tessarion:BAAALgAECgkJCQAAAA==.',
Th='Thandas:BAABLgAECn8yAAIBAAgJDhA1dQB4AQABAAgJDhA1dQB4AQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAgAAAA==.Thniper:BAABLgAECn8oAAMVAAkJURgyGABrAgAVAAgJQBsyGABrAgAkAAUJ9wzFLwAlAQAAAA==.Thouvan:BAAALgAECgEJAQAAAA==.Thugnastyy:BAAALgAFFAEJAgABLgAFFAIJAwADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIGAAkJqxoGFQBaAgAGAAkJqxoGFQBaAgAAAA==.',
To='Tost:BAAALgAECgEJAQABLgAECgIJAQADAAAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.Tusker:BAAALgADCgcJEQAAAA==.',
Ty='Tyinviril:BAACLgAFFH8FAAICAAIJSB87JQC3AAACAAIJSB87JQC3AAAuAAQKf0kAAgIACQlKJdcBAFkDAAIACQlKJdcBAFkDAAAA.',
Un='Unter:BAAALgAECgEJAQAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8QAAMBAAYJFw87JgBcAQABAAYJFw87JgBcAQAGAAEJRgF6QwA9AAAuAAQKf0AAAwEACAlcIRkdAI0CAAEACAlcIRkdAI0CAAYABQk8CflgAPgAAAAA.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAABLgAECn8SAAIHAAcJDwu1gQAQAQAHAAcJDwu1gQAQAQAAAA==.Vonawesome:BAAALgAECgQJCAAAAA==.Vorpalblade:BAABLgAECn8uAAILAAkJMRf7DgDrAQALAAkJMRf7DgDrAQAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAABLgAFFH8HAAIMAAMJLQgrpADBAAAMAAMJLQgrpADBAAAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgADCgkJCQAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8wAAMnAAkJ2B4HAQDOAgAnAAkJ2B4HAQDOAgAZAAEJPBluPgE/AAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIiAAkJfhIBEQCnAQAiAAkJfhIBEQCnAQAAAA==.Willowfox:BAAALgAECgMJCwAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJCgAAAA==.Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgAECgUJCAAAAA==.Wram:BAABLgAECn8fAAMLAAkJ0AhNIAAhAQALAAkJ0AhNIAAhAQAcAAIJJAGMrgAZAAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECgkJHwALANAIAA==.Wreckuiem:BAAALgAECggJEwAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8gAAMfAAgJ7h57BQAJAgAfAAgJ8x17BQAJAgAJAAYJ8Rj5SQC4AQAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAACLgAFFH8SAAIHAAUJOhp+MwA/AQAHAAUJOhp+MwA/AQAuAAQKfysAAgcACQm5HkIQALcCAAcACQm5HkIQALcCAAAA.',
Xr='Xristinà:BAAALgADCgkJCQAAAA==.',
Zi='Zillara:BAABLgAECn8bAAIPAAkJaAbHDgAvAQAPAAkJaAbHDgAvAQAAAA==.',
['Zù']='Zùlfang:BAAALgAECgUJBQABLgAECgkJKwAcAGgZAA==.',
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
