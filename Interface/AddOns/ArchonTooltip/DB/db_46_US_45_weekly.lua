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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Mistweaver','Warrior-Protection','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Warrior-Fury','Shaman-Restoration','Hunter-Marksmanship','Evoker-Devastation','Druid-Feral','Druid-Restoration','Mage-Frost','Monk-Brewmaster','Evoker-Augmentation','Warrior-Arms','Druid-Guardian','Warlock-Destruction','Monk-Windwalker','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Frost','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abráms:BAAALgAECgEJAQAAAA==.',
Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8jAAIBAAkJBRxLSgDlAQABAAkJBRxLSgDlAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzgiFMgBPAQACAAkJzgiFMgBPAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn8tAAIBAAgJAw+pgABrAQABAAgJAw+pgABrAQAAAA==.',
Aj='Ajaki:BAABLgAECn8jAAQEAAcJ6xdhJQCVAQAEAAcJ6xdhJQCVAQAFAAcJmAZPQgD+AAACAAIJDAl7cQBbAAAAAA==.',
Al='Allandra:BAAALgAECgYJBgAAAA==.Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJAwAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgYJEgAAAA==.Amelandra:BAAALgAECgEJAQAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgIJAgAAAA==.Anklebiter:BAAALgAECgEJAQAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECgkJEQAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgcJDgAAAA==.Arlan:BAABLgAECn8fAAIGAAkJdR6gDgCpAgAGAAkJdR6gDgCpAgAAAA==.Arlequin:BAABLgAECn8ZAAMHAAkJjgldqQDOAAAHAAcJMAldqQDOAAAIAAMJqAq7UwBlAAAAAA==.Arnagan:BAAALgAECgUJBQAAAA==.',
As='Asale:BAAALgAECgEJAQAAAA==.Ascend:BAAALgAECgYJCAABLgAFFAMJAwADAAAAAA==.Asharothh:BAABLgAECn8mAAIJAAkJYxu5FgBeAgAJAAkJYxu5FgBeAgAAAA==.Ashdem:BAABLgAECn8ZAAIHAAcJNw4BggAYAQAHAAcJNw4BggAYAQAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAABLgAECn8YAAIKAAkJlhE5FACqAQAKAAkJlhE5FACqAQAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1gc9iwAtAAAFAAIJFgLEhgAfAAAAAA==.Azkar:BAAALgADCgEJAQAAAA==.Azorahai:BAABLgAECn8xAAILAAgJmwyYcwB6AQALAAgJmwyYcwB6AQAAAA==.Azshalia:BAABLgAECn8gAAIKAAgJBwv1IQAcAQAKAAgJBwv1IQAcAQAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8nAAQMAAgJURBnCgB6AQAMAAgJMA9nCgB6AQANAAYJpA3vNQBgAQAOAAcJkQwlDgBAAQAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMIAAcJ6R2lFADoAQAIAAcJ6R2lFADoAQAHAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8wAAIPAAkJOxXULAAmAgAPAAkJOxXULAAmAgAAAA==.',
Be='Beffis:BAAALgAECgMJAwAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8vAAMQAAkJuiWgAAAwAwAQAAkJmCWgAAAwAwARAAgJ7B1CJQBIAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgASAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8rAAITAAkJWB0CDgCJAgATAAkJWB0CDgCJAgAAAA==.Boblin:BAABLgAECn8eAAIUAAYJbw7uSwAWAQAUAAYJbw7uSwAWAQAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn8xAAIVAAkJGSAgBwA8AwAVAAkJGSAgBwA8AwAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAABLgAECn8ZAAMPAAcJowLFywCqAAAPAAYJswLFywCqAAAWAAQJYgKBNQBEAAAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSK7DwDmAgABAAkJrSK7DwDmAgAAAA==.Bosshogshift:BAAALgAECgYJBgABLgAECgkJNAABAK0iAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8JAAIKAAUJziAkBgAIAQAKAAUJziAkBgAIAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgASAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bulgear:BAAALgAECgMJBgAAAA==.Bupropion:BAABLgAECn8eAAIHAAYJAhkrYABlAQAHAAYJAhkrYABlAQABLgAECgkJNQAXAMEfAA==.Bushwhacker:BAABLgAECn8iAAMSAAcJoBCBOQApAQASAAcJzw6BOQApAQAYAAMJ0Az1MgCNAAAAAA==.Butterbean:BAABLgAECn8tAAIPAAkJCCB3CwDnAgAPAAkJCCB3CwDnAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECggJEQAAAA==.Catameringue:BAABLgAECn8WAAIZAAcJBBEaRAB9AQAZAAcJBBEaRAB9AQAAAA==.',
Ch='Chickenhawk:BAAALgAECgEJAQAAAA==.Chicxulub:BAABLgAECn8aAAIaAAgJ7BNHXgDBAQAaAAgJ7BNHXgDBAQAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMVAAkJKCBBCQDjAgAVAAkJKCBBCQDjAgATAAYJCRG8TgD3AAAAAA==.Clickshoot:BAAALgAECgYJCwAAAA==.',
Co='Coaca:BAABLgAECn8wAAMBAAkJKR1yIQB/AgABAAkJKR1yIQB/AgAGAAEJEQchmAAmAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAFFAIJBgARACcWAA==.Confluent:BAABLgAECn81AAMZAAkJQyWkAQC+AwAZAAkJQyWkAQC+AwASAAkJAhiPEQBKAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn83AAIbAAkJ7xKQIwCMAQAbAAkJ7xKQIwCMAQAAAA==.',
Cu='Cursè:BAAALgADCgIJAgABLgAECgkJKwAaAEkIAA==.',
Cy='Cythrandir:BAAALgAECgYJDAABLgAFFAUJEwAaAP8RAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.Davwr:BAAALgAECgMJAwABLgAECggJFgALAIgUAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECgkJEwAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Dethrahzen:BAABLgAECn82AAMXAAgJyAWTEAD9AAAXAAgJyAWTEAD9AAAcAAIJhwH8mQAkAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8sAAIUAAkJpRrbFwAuAgAUAAkJpRrbFwAuAgAAAA==.',
Dj='Djcamsoda:BAAALgAECgEJAQAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgAECgcJEgAAAA==.',
Do='Doomslayer:BAAALgADCgkJDwAAAA==.Dorelios:BAAALgADCgQJBAAAAA==.Dotsfordayz:BAAALgAECgMJBAABLgAECgMJBAADAAAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJGAAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAABLgAECn8WAAMPAAYJbQU3sgDZAAAPAAYJbQU3sgDZAAAWAAMJGwAFnAAOAAAAAA==.',
Du='Dubstep:BAAALgAECgYJEQAAAA==.Dugatotems:BAABLgAECn8zAAMVAAkJPxrjGwA5AgAVAAkJPxrjGwA5AgATAAkJ5QieOwBDAQAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dumpytruck:BAAALgAECgQJBQAAAA==.Dunkle:BAABLgAECn8tAAMdAAkJgyDABwB3AgAUAAkJihz8EwCuAgAdAAkJzBvABwB3AgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8oAAIPAAkJkwt+TgCyAQAPAAkJkwt+TgCyAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEgAAAA==.',
Eb='Ebonise:BAAALgAECgUJCwAAAA==.',
Ed='Edrelang:BAABLgAECn8eAAMUAAcJ3QlISQAfAQAUAAcJ3QlISQAfAQAdAAIJrQR1bwA9AAAAAA==.',
Ee='Eerikki:BAAALgAECgYJEQAAAA==.',
Ei='Eightsix:BAAALgAFFAIJAwABLgAFFAMJAwADAAAAAA==.Ein:BAABLgAECn82AAIXAAkJXRrVAgB+AgAXAAkJXRrVAgB+AgAAAA==.',
El='Ellechero:BAABLgAECn8kAAMeAAgJQAjCNwDCAAASAAcJKQWWUADGAAAeAAcJfQfCNwDCAAAAAA==.Ellonia:BAAALgAECgMJAwABLgAECggJIAAfAO4eAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Eragøn:BAABLgAECn8WAAIPAAcJrBqDQQDZAQAPAAcJrBqDQQDZAQAAAA==.Erinna:BAAALgAECgEJBAAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgYJEAAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgkJHwAKANAIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.Fextrius:BAAALgAECgYJCgAAAA==.',
Fl='Florassa:BAAALgADCgUJBQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAACLgAFFH8HAAILAAMJFA5CpADOAAALAAMJFA5CpADOAAAuAAQKfyEAAgsABgnTFpmKAE0BAAsABgnTFpmKAE0BAAEuAAUUBAkSABQA8B0A.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgAECgQJBAAAAA==.Furrystorm:BAAALgAFFAEJAgAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIaAAkJlA4OYgC4AQAaAAkJlA4OYgC4AQAAAA==.Garroc:BAAALgAECgYJBgAAAA==.',
Gh='Ghast:BAABLgAECn9mAAMRAAkJ/xoSJQBIAgARAAkJ7RcSJQBIAgAQAAcJ8BIFDACYAQAAAA==.Ghats:BAABLgAECn8VAAMRAAgJnRjpOQDxAQARAAgJnRjpOQDxAQAfAAEJAABDVAAAAAABLgAFFAMJAwADAAAAAA==.',
Gi='Giddley:BAAALgAECgEJAQAAAA==.Gigaflare:BAABLgAECn8nAAIaAAkJqAwkgwDLAQAaAAkJqAwkgwDLAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnev:BAAALgADCgYJBgAAAA==.Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatale:BAAALgAECgYJCwABLgAECgkJLAALAFQgAA==.Goatknight:BAABLgAECn8sAAILAAkJVCAbEwDUAgALAAkJVCAbEwDUAgAAAA==.Goatwings:BAAALgAECgIJAgAAAA==.Gobblynn:BAAALgADCggJEAAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAzf2wDgAAABAAcJHAzf2wDgAAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn9CAAIRAAkJCw93TAC0AQARAAkJCw93TAC0AQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJCAAAAA==.Greywings:BAABLgAECn83AAIXAAkJrQ0vCQCWAQAXAAkJrQ0vCQCWAQAAAA==.Grimroxs:BAABLgAECn82AAMOAAkJ+w9jBwDgAQAOAAkJ+w9jBwDgAQANAAIJEgU1TwBnAAAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgAECgQJBwABLgAECgMJBAADAAAAAA==.Grizzlemaw:BAAALgAECgcJDAAAAA==.',
Ha='Hacheros:BAAALgAECgIJAgAAAA==.Hadic:BAAALgADCgEJAQABLgAECgkJCQADAAAAAA==.Hairypits:BAAALgAECgYJDQABLgAECgkJLAALAFQgAA==.Handerbug:BAABLgAECn8uAAMSAAkJRyZ0AwAwAwASAAkJRyZ0AwAwAwAeAAYJtBz8FgCUAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgASAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgASAEcmAA==.Handybug:BAAALgAECgEJAQABLgAECgkJLgASAEcmAA==.Hankit:BAAALgAECgQJBQAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJCgAAAA==.Hazmati:BAAALgADCgkJCQABLgAFFAQJDAAgAKYHAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Healtaxi:BAAALgAECgMJBAAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAABLgAECn8hAAIEAAkJIwteLABjAQAEAAkJIwteLABjAQAAAA==.Heinrich:BAABLgAECn8vAAMBAAgJ8iOFFgC6AgABAAgJ8iOFFgC6AgAGAAQJPRFAbADJAAAAAA==.Heira:BAAALgADCgQJCAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.Hippypedro:BAAALgAECgYJEQABLgAFFAUJHAAIAKEbAA==.',
Ho='Hogglethorp:BAAALgAECggJEwAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCgkJGgAAAA==.Horns:BAAALgAECgUJBQAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAFFAIJBAAAAA==.',
Il='Ilina:BAAALgAECgUJDQABLgAFFAIJAgADAAAAAA==.Illadron:BAAALgAFFAEJAgAAAA==.Illecebra:BAAALgAFFAEJAQAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAABLgAECn8cAAMSAAgJSAqbOAAtAQASAAgJSAqbOAAtAQAZAAMJUgznmwB2AAAAAA==.',
Ja='Jagerblunt:BAACLgAFFH8KAAIPAAQJtxdkLwBKAQAPAAQJtxdkLwBKAQAuAAQKfyQAAg8ACQmoGUYxABMCAA8ACQmoGUYxABMCAAAA.',
Jd='Jdbud:BAAALgAECgIJAgAAAA==.Jdpot:BAAALgAECgYJEAAAAA==.',
Je='Jenaaidy:BAABLgAECn8tAAICAAgJkBWcHgDPAQACAAgJkBWcHgDPAQAAAA==.',
Jh='Jhannae:BAAALgADCgEJAQAAAA==.',
Ji='Jiks:BAAALgAECgIJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLgAJAPIhAA==.Joshery:BAABLgAECn8uAAMJAAkJ8iGLBQAJAwAJAAkJ8iGLBQAJAwAgAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJCQABLgAECgkJLgAJAPIhAA==.',
Ju='Judge:BAABLgAECn8sAAIBAAkJ6BJVTQDdAQABAAkJ6BJVTQDdAQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8xAAIhAAkJmCE6BADyAgAhAAkJmCE6BADyAgAAAA==.',
Ka='Katasaria:BAACLgAFFH8VAAMUAAUJFCCHEgBuAQAUAAUJFCCHEgBuAQAdAAEJxxTjPQBJAAAuAAQKfysAAxQACAmNIG4UAKoCABQACAkXIG4UAKoCAB0ABQk0GqUrABgBAAAA.Kaycee:BAAALgADCgUJCAABLgAECggJJwAMAFEQAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECggJJwAMAFEQAA==.Kaycer:BAAALgADCggJDwABLgAECggJJwAMAFEQAA==.',
Ke='Keeps:BAAALgAECgEJAQAAAA==.Kerl:BAAALgAECggJEQABLgAECgkJCQADAAAAAA==.',
Ki='Kiboridi:BAAALgAECgQJBQAAAA==.Killerxx:BAAALgAECgEJAQABLgAECgcJHgAUAN0JAA==.Kimetshu:BAABLgAECn8gAAIIAAgJaBRGHQCNAQAIAAgJaBRGHQCNAQAAAA==.Kirana:BAABLgAECn8uAAMSAAkJfQYtPQAXAQASAAkJfQYtPQAXAQAZAAUJRAQ+lwCBAAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAILAAgJRAttkABfAQALAAgJRAttkABfAQAAAA==.',
Ko='Kolaro:BAAALgAECgEJAgAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIYAAkJqBtLBgCAAgAYAAkJqBtLBgCAAgAAAA==.Kravin:BAAALgAECgQJCwAAAA==.Krunzar:BAAALgAECgUJBwAAAA==.',
Kt='Ktheir:BAAALgAECgIJAgAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Lammasthan:BAAALgAECgkJCQAAAA==.Laneywine:BAAALgAECgYJDgAAAA==.Larlifax:BAAALgAECgUJBwAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8zAAIUAAkJcSVSAgBQAwAUAAkJcSVSAgBQAwAAAA==.Levìstus:BAABLgAECn8rAAILAAkJ0RjbLABKAgALAAkJ0RjbLABKAgAAAA==.Leylaní:BAABLgAECn8jAAIPAAkJrRSaLwAZAgAPAAkJrRSaLwAZAgAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgUJBwAAAA==.Loroessan:BAAALgAECgkJDwAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAABLgAECn8UAAIBAAcJCxCFjwBQAQABAAcJCxCFjwBQAQAAAA==.Lukas:BAAALgAECgcJCQABLgAECgkJZgARAP8aAA==.Lunet:BAAALgAECgcJBwAAAA==.Lustie:BAAALgAECgYJEwABLgAECgkJNQAXAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAXAMEfAA==.Lytheum:BAABLgAECn81AAIXAAkJwR8dAgCsAgAXAAkJwR8dAgCsAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
['Lü']='Lücid:BAAALgAECgEJAgAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQAVACggAA==.Magerrac:BAAALgAECgEJAQABLgAECgkJHwAKANAIAA==.Magikon:BAAALgADCgUJBQAAAA==.Magista:BAAALgAECgIJAgAAAA==.Malachar:BAABLgAECn8vAAIKAAkJIA3nFwB+AQAKAAkJIA3nFwB+AQAAAA==.Malboro:BAABLgAECn8qAAIRAAgJ7BKRWQCQAQARAAgJ7BKRWQCQAQAAAA==.Maled:BAABLgAECn8sAAQQAAgJRh78BwDoAQAQAAcJXhz8BwDoAQAfAAMJLRxMFgDvAAARAAMJohCT2wCgAAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrew:BAAALgAECgkJBwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Mej:BAAALgAECgQJBAAAAA==.Meldin:BAABLgAECn8jAAIPAAkJZCBDDwDTAgAPAAkJZCBDDwDTAgAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgUJCQAAAA==.Method:BAABLgAECn8rAAMiAAkJBxS0EQCmAQAiAAkJhxO0EQCmAQABAAIJFxNtNwFwAAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMGAAcJdh29JADeAQAGAAcJdh29JADeAQABAAEJJgHOywERAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIgAAkJ5Bk0EABGAgAgAAkJ5Bk0EABGAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8nAAMHAAgJGBbaSQClAQAHAAgJzxXaSQClAQAjAAEJeRgmKQBAAAAAAA==.Mineos:BAABLgAECn8XAAIUAAcJvAtlRQAvAQAUAAcJvAtlRQAvAQAAAA==.Minipedro:BAAALgAECgEJAQABLgAFFAUJHAAIAKEbAA==.Mistrmiso:BAAALgAECgMJAgABLgAECgkJLwAQALolAA==.Mizoh:BAAALgAECgYJEAAAAA==.',
Mo='Moahuntress:BAAALgAECgYJCQAAAA==.Moonlyt:BAAALgADCgkJIQAAAA==.Morgaine:BAAALgADCggJDAABLgAECgkJHwAKANAIAA==.Morn:BAABLgAECn8bAAMXAAkJNRt+BwBzAgAXAAkJNRt+BwBzAgAcAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJZgARAP8aAA==.',
Mt='Mtrain:BAAALgAECgYJCgABLgAFFAMJAwADAAAAAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myori:BAAALgAECgMJAwAAAA==.Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgAECgYJCAAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAABLgAECn8jAAIhAAkJSRc0EAAFAgAhAAkJSRc0EAAFAgAAAA==.Neeryn:BAAALgAECgIJAgAAAA==.Nestiae:BAAALgAECgMJAwABLgAECgYJCQADAAAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAFFAIJBAADAAAAAA==.Nightsfuri:BAABLgAECn8bAAISAAgJHxPaKACHAQASAAgJHxPaKACHAQAAAA==.Nik:BAAALgAECgQJBQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8gAAIPAAkJKgzyUACrAQAPAAkJKgzyUACrAQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orlandbro:BAABLgAECn8nAAQPAAkJ2x1iGAB3AgAkAAkJxhy4BQCyAgAPAAkJ4BdiGAB3AgAWAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAABLgAECn8bAAMLAAkJUg++cACAAQALAAkJzQ2+cACAAQAhAAQJpg/7MwDGAAAAAA==.Patchy:BAAALgAECgQJBAAAAA==.Pawradox:BAABLgAECn8kAAICAAkJ8wzYKACHAQACAAkJ8wzYKACHAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAwAAAA==.',
Ph='Phenomenon:BAABLgAECn8YAAIPAAcJ1iAHJgBFAgAPAAcJ1iAHJgBFAgAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIhAAkJUh7iBwCpAgAhAAkJUh7iBwCpAgAAAA==.Pitviper:BAABLgAECn8UAAIlAAYJBxlPFAA3AQAlAAYJBxlPFAA3AQAAAA==.',
Pl='Plina:BAABLgAECn8hAAIBAAkJGhdFPQANAgABAAkJGhdFPQANAgAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponglenis:BAAALgAFFAIJAgABLgAFFAIJBAADAAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAABLgAFFH8KAAIVAAQJCBP7NQACAQAVAAQJCBP7NQACAQAAAA==.',
Pu='Pulli:BAAALgAECgkJEQAAAA==.',
Pv='Pve:BAACLgAFFH8FAAIkAAUJBwWnHgDbAAAkAAUJBwWnHgDbAAAuAAQKfy0AAiQACQn0H4IGALcCACQACQn0H4IGALcCAAAA.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8eAAIVAAkJdxOjMgDlAQAVAAkJdxOjMgDlAQAAAA==.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIaAAcJcRQQjgBYAQAaAAcJcRQQjgBYAQAAAA==.Rathane:BAACLgAFFH8FAAIPAAQJtQo8TwAEAQAPAAQJtQo8TwAEAQAuAAQKfxwAAg8ACAm1HCAjADMCAA8ACAm1HCAjADMCAAAA.Rawrmuch:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.Ray:BAAALgAECgYJBgABLgAECgkJGwAXADUbAA==.',
Re='Realmclovin:BAAALgAECgUJBQAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Redrabbit:BAAALgAECgYJBwAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8sAAIGAAkJjiYlAAD2AwAGAAkJjiYlAAD2AwAAAA==.',
Ri='Rizzwan:BAABLgAECn8pAAIkAAkJhx9iBADoAgAkAAkJhx9iBADoAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMgAAMJYQlXKQClAAAgAAMJYQlXKQClAAAJAAIJ0AzMTQBiAAAuAAQKfykABAkACQmMHTAQAJ0CAAkACAmXHDAQAJ0CACAACAmwGxATACMCABsAAQmJDriNADQAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAFFAEJAQABLgAFFAUJFQAUABQgAA==.Romy:BAABLgAECn8sAAIaAAgJhQI53wDYAAAaAAgJhQI53wDYAAAAAA==.Roonoe:BAAALgAECgMJAwAAAA==.',
Ru='Runecleaver:BAABLgAECn87AAMVAAkJBCIlEQDCAgAVAAkJBCIlEQDCAgATAAQJExayUQDtAAAAAA==.Ruw:BAABLgAECn8rAAMOAAkJchFZCADEAQAOAAgJGhNZCADEAQANAAQJKggcQADAAAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8lAAILAAkJ7h/LFgC7AgALAAkJ7h/LFgC7AgAAAA==.Satania:BAABLgAECn8fAAIIAAkJGiTyBAAlAwAIAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8pAAMEAAkJ1RNjFQAmAgAEAAkJ1RNjFQAmAgACAAcJjxNPKwB4AQAAAA==.',
Se='Segora:BAABLgAECn8aAAIRAAYJRAcGnwAbAQARAAYJRAcGnwAbAQABLgAECgkJQgARAAsPAA==.Seimus:BAABLgAECn8UAAIaAAUJcRGa1ADnAAAaAAUJcRGa1ADnAAAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAABLgAECn8UAAIBAAYJFBGqsgAYAQABAAYJFBGqsgAYAQAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAABLgAECn8hAAISAAgJ7QZ/QQADAQASAAgJ7QZ/QQADAQAAAA==.Sharius:BAABLgAECn8rAAIaAAkJSQhyfwB1AQAaAAkJSQhyfwB1AQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIaAAkJ6hJwZAAPAgAaAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJDgAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.Shutendoji:BAAALgAECgEJAgABLgAECggJHQAgAKohAA==.',
Si='Sightlightx:BAAALgAECggJEwAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8xAAIUAAkJvgpUMQCGAQAUAAkJvgpUMQCGAQAAAA==.Sinkingbridg:BAAALgAECgIJAgAAAA==.Siryn:BAABLgAECn8gAAIGAAgJQAM0WQDPAAAGAAgJQAM0WQDPAAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smallest:BAAALgAECgUJCQABLgAECggJJwAMAFEQAA==.Smashn:BAABLgAECn8YAAMlAAcJmRMyEQBgAQAlAAcJAhEyEQBgAQALAAYJmwu6wwD2AAAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.Snakeshadow:BAAALgAECgkJCQAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAFFAEJAQADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAImAAkJmBN4AwDmAQAmAAkJmBN4AwDmAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgAECgEJAQAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMZAAkJAB7UEACxAgAZAAkJAB7UEACxAgASAAcJnhVVLQBrAQAAAA==.Syrden:BAAALgAECgYJCAABLgAECgkJFgAZAOgLAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCggJDQAAAA==.Tanholy:BAAALgAECgUJAwAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJCAAAAA==.Tessarion:BAAALgAECgkJCQAAAA==.',
Th='Thandas:BAABLgAECn84AAIBAAgJnhEkbQCRAQABAAgJnhEkbQCRAQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAwAAAA==.Thniper:BAABLgAECn8oAAMWAAkJURgyGABrAgAWAAgJQBsyGABrAgAkAAUJ9wxaMQAgAQAAAA==.Thouvan:BAAALgAECgEJAQAAAA==.Thugnastyy:BAAALgAFFAIJBAABLgAFFAIJBAADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIGAAkJqxoIFgBZAgAGAAkJqxoIFgBZAgAAAA==.',
To='Tost:BAAALgAECgEJAQABLgAECgIJAQADAAAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.Tusker:BAAALgAECgUJBQAAAA==.',
Ty='Tyinviril:BAACLgAFFH8JAAICAAQJ0B6sDwBpAQACAAQJ0B6sDwBpAQAuAAQKf0kAAgIACQlKJQICAFQDAAIACQlKJQICAFQDAAAA.',
Un='Unter:BAAALgAECgEJAQAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8VAAMBAAcJTA/EFgCrAQABAAcJTA/EFgCrAQAGAAEJRgHTRgA7AAAuAAQKf0AAAwEACAlcIVwfAIkCAAEACAlcIVwfAIkCAAYABQk8CflgAPgAAAAA.Verna:BAAALgADCgIJAgAAAA==.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAABLgAECn8SAAIHAAcJDws0hgAQAQAHAAcJDws0hgAQAQAAAA==.Vonawesome:BAAALgAECgQJCAAAAA==.Vorpalblade:BAABLgAECn8uAAIKAAkJMRfZDwDmAQAKAAkJMRfZDwDmAQAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAABLgAFFH8HAAILAAMJLQg8sQC9AAALAAMJLQg8sQC9AAAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgADCgkJCQAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8wAAMnAAkJ2B4HAQDOAgAnAAkJ2B4HAQDOAgAaAAEJPBmERwE/AAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIiAAkJfhLUEQCkAQAiAAkJfhLUEQCkAQAAAA==.Willowfox:BAAALgAECgMJCwAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJCwAAAA==.Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgAECgUJCAAAAA==.Wram:BAABLgAECn8fAAMKAAkJ0AicIQAfAQAKAAkJ0AicIQAfAQAUAAIJJAG+tQAZAAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECgkJHwAKANAIAA==.Wreckuiem:BAAALgAECggJEwAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8gAAMfAAgJ7h7oBQAFAgAfAAgJ8x3oBQAFAgARAAYJ8Rj/SwC2AQAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAACLgAFFH8TAAIHAAUJOhp2OQA4AQAHAAUJOhp2OQA4AQAuAAQKfysAAgcACQm5HhIRALcCAAcACQm5HhIRALcCAAAA.',
Xr='Xristinà:BAAALgADCgkJCQAAAA==.',
Ya='Yamauba:BAAALgAECgMJAwAAAA==.',
Yn='Yn:BAAALgAFFAIJAwAAAA==.',
Zi='Zillara:BAABLgAECn8bAAIOAAkJaAZGDwAuAQAOAAkJaAZGDwAuAQAAAA==.',
['Zù']='Zùlfang:BAAALgAECgUJBQABLgAECgkJKwAUAGgZAA==.',
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
