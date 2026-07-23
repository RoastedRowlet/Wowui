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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Affliction','Monk-Mistweaver','Shaman-Restoration','Warrior-Protection','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Warrior-Fury','Hunter-Marksmanship','Evoker-Devastation','Druid-Restoration','Druid-Guardian','Mage-Frost','Monk-Brewmaster','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Blood','Warrior-Arms','Warlock-Destruction','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Frost','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abráms:BAAALgAECgEJAQAAAA==.',
Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8jAAIBAAkJBRz7SwDiAQABAAkJBRz7SwDiAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzggZNABIAQACAAkJzggZNABIAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn80AAIBAAkJtg43gwBpAQABAAkJtg43gwBpAQAAAA==.',
Aj='Ajaki:BAABLgAECn8sAAQEAAgJJRZwCAD9AAAEAAgJJRZwCAD9AAAFAAcJmAbZQwD5AAACAAMJUAz8YQCSAAAAAA==.',
Al='Allandra:BAAALgAECgYJBgAAAA==.Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJBAAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgYJEgAAAA==.Amelandra:BAAALgAECgEJAQAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgIJAgAAAA==.Anklebiter:BAAALgAECgEJBAAAAA==.Ankolo:BAAALgADCgMJAwAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgcJEwAAAA==.Arlan:BAABLgAECn8fAAIGAAkJdR7cDgCoAgAGAAkJdR7cDgCoAgAAAA==.Arlequin:BAABLgAECn8ZAAMHAAkJjgnVqwDOAAAHAAcJMAnVqwDOAAAIAAMJqAqCVQBlAAAAAA==.Arnagan:BAAALgAECgUJBQAAAA==.',
As='Asale:BAAALgAECgEJAQAAAA==.Ascend:BAAALgAECgYJCAABLgAFFAQJBwAJANoKAA==.Asharothh:BAABLgAECn8mAAIKAAkJYxtWFwBeAgAKAAkJYxtWFwBeAgAAAA==.Ashdem:BAABLgAECn8ZAAIHAAcJNw7tgwAYAQAHAAcJNw7tgwAYAQAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.Ashtomb:BAAALgAECgEJAQABLgAECgkJOwALAAQiAA==.',
At='Athenâ:BAABLgAECn8YAAIMAAkJlhF8FACqAQAMAAkJlhF8FACqAQAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1ge5jQAtAAAFAAIJFgLpiQAfAAAAAA==.Azkar:BAAALgADCgEJAQAAAA==.Azorahai:BAABLgAECn84AAINAAgJdQ97EwDuAAANAAgJdQ97EwDuAAAAAA==.Azshalia:BAABLgAECn8mAAIMAAkJDAt7IgAcAQAMAAkJDAt7IgAcAQAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8nAAQOAAgJURCeCgB2AQAOAAgJMA+eCgB2AQAPAAYJpA3vNQBgAQAQAAcJkQxMDgBAAQABLgAECgcJDQADAAAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMIAAcJ6R0BFQDnAQAIAAcJ6R0BFQDnAQAHAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8wAAIRAAkJOxULLgAkAgARAAkJOxULLgAkAgAAAA==.',
Be='Beffis:BAAALgAECgMJAwAAAA==.Belindra:BAAALgADCgUJBQAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgAECgUJBQABLgAECgkJSgARAL8ZAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8vAAMJAAkJuiWnAAAuAwAJAAkJmCWnAAAuAwASAAgJ7B3LJgBCAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Blitzkriêg:BAAALgAECgIJAQAAAA==.Bloodscare:BAAALgADCgEJAQAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgATAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8tAAIUAAkJzh1IDgCIAgAUAAkJzh1IDgCIAgAAAA==.Boblin:BAABLgAECn8oAAIVAAcJZBD6BgBAAQAVAAcJZBD6BgBAAQAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn81AAILAAkJGSBSBwA7AwALAAkJGSBSBwA7AwAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAABLgAECn8gAAMWAAcJ5wNaBwBfAAARAAYJswK+zwCqAAAWAAcJmANaBwBfAAAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSI/EADkAgABAAkJrSI/EADkAgAAAA==.Bosshogshift:BAAALgAECgYJBgABLgAECgkJNAABAK0iAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8RAAIMAAUJ/SPBBACvAQAMAAUJ/SPBBACvAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgATAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bulgear:BAAALgAECgMJBgAAAA==.Bupropion:BAABLgAECn8eAAIHAAYJAhl6YQBmAQAHAAYJAhl6YQBmAQABLgAECgkJNQAXAMEfAA==.Bushwhacker:BAAALgAECgYJCAAAAA==.Butterbean:BAABLgAECn8tAAIRAAkJCCB3CwDnAgARAAkJCCB3CwDnAgAAAA==.',
Ca='Cacio:BAAALgAECgcJCAABLgAECgkJSgARAL8ZAA==.Cali:BAAALgAECgMJAwAAAA==.Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECggJEgAAAA==.Catameringue:BAABLgAECn8nAAQYAAcJCxVGBQB8AQAYAAcJCxVGBQB8AQATAAcJnBCwBgAuAQAZAAEJoQH/JQARAAAAAA==.',
Ch='Chickenhawk:BAAALgAECgUJBwAAAA==.Chicxulub:BAABLgAECn8cAAIaAAkJ8xO7XwDBAQAaAAkJ8xO7XwDBAQAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.Chonkyninja:BAAALgAECgEJAQAAAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMLAAkJKCBBCQDjAgALAAkJKCBBCQDjAgAUAAYJCREPUAD3AAAAAA==.Clickshoot:BAAALgAECgYJDAAAAA==.',
Co='Coaca:BAABLgAECn8yAAMBAAkJ6h0XIgB+AgABAAkJ6h0XIgB+AgAGAAEJEQf5mQAmAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAFFAQJDgASAFYaAA==.Confluent:BAABLgAECn81AAMYAAkJQyW7AQC+AwAYAAkJQyW7AQC+AwATAAkJAhggEgBHAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn85AAMbAAkJ7xL2IwCLAQAbAAkJ7xL2IwCLAQAcAAEJygoHHgAoAAAAAA==.',
Cu='Cursè:BAAALgADCgIJAgABLgAECgkJLAAaAN8JAA==.',
Cy='Cythrandir:BAAALgAECgYJDAABLgAFFAUJEwAaAP8RAA==.',
Da='Daikellus:BAAALgAECgQJBAAAAA==.Dalkith:BAAALgAECgIJAwABLgAECggJEwADAAAAAA==.Daniellena:BAAALgADCgkJGAAAAA==.Darkstaker:BAAALgADCgEJAQAAAA==.Daruta:BAAALgADCgUJBQAAAA==.Davwr:BAAALgAECgMJAwABLgAECgkJGAANAH8TAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECgkJEwAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Demoloro:BAAALgAECgEJAQAAAA==.Denia:BAAALgADCggJCAAAAA==.Dethrahzen:BAABLgAECn9JAAMXAAkJMAg5AgD9AAAXAAkJMAg5AgD9AAAdAAIJhwGanQAjAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8tAAIVAAkJpRouGAAtAgAVAAkJpRouGAAtAgAAAA==.',
Dj='Djcamsoda:BAAALgAECgEJAgAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAABLgAECn8eAAMeAAgJCAwhCADFAAAeAAgJ+wshCADFAAANAAEJiRDqQgA0AAAAAA==.',
Do='Doomslayer:BAAALgAECgYJCgAAAA==.Dorelios:BAAALgADCgQJBAAAAA==.Dotsfordayz:BAAALgAECgMJBAABLgAFFAMJAwADAAAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJGAAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAABLgAECn8WAAMRAAYJbQW8tQDZAAARAAYJbQW8tQDZAAAWAAMJGwAFnAAOAAAAAA==.Drstránge:BAAALgAECgcJDAAAAA==.',
Du='Dubstep:BAAALgAECgYJEQAAAA==.Dugatotems:BAABLgAECn86AAMLAAkJPxrjGwA5AgALAAkJPxrjGwA5AgAUAAkJNhD+BgA0AQAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dumpytruck:BAAALgAECgQJBQAAAA==.Dunkle:BAABLgAECn8tAAMfAAkJgyD8BwB2AgAVAAkJihz8EwCuAgAfAAkJzBv8BwB2AgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8pAAIRAAkJkwsjUACyAQARAAkJkwsjUACyAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEgAAAA==.',
Eb='Ebonise:BAAALgAECgUJDwAAAA==.',
Ed='Edrelang:BAABLgAECn8hAAMVAAgJQQzmSgAaAQAVAAcJaQvmSgAaAQAfAAMJ5QgtEwA0AAAAAA==.',
Ee='Eerikki:BAAALgAECgYJEQAAAA==.',
Ei='Eightsix:BAAALgAFFAIJAwABLgAFFAQJBwAJANoKAA==.Ein:BAABLgAECn82AAIXAAkJXRrqAgB+AgAXAAkJXRrqAgB+AgAAAA==.',
El='Ellechero:BAABLgAECn8mAAMZAAgJXAgqOQDBAAATAAcJ/wX2UQDGAAAZAAcJfQcqOQDBAAAAAA==.Ellonia:BAAALgAECgMJAwABLgAECggJIAAgAO4eAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.Elsmerelda:BAAALgAECgEJAQAAAA==.',
Er='Eragøn:BAABLgAECn8WAAIRAAcJrBokQwDZAQARAAcJrBokQwDZAQAAAA==.Erinna:BAAALgAECgEJBgAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAABLgAECn8XAAMBAAkJTQ2PBwGvAAABAAYJfwSPBwGvAAAGAAUJKgovDACjAAAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgkJHwAMANAIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fedagolas:BAAALgAECgEJAQAAAA==.Felmor:BAEALgADCgQJBAABLgAFFAQJBwASAHAMAA==.Fengpopo:BAAALgADCgEJAQAAAA==.Fextrius:BAAALgAECgYJCgAAAA==.',
Fl='Flappystabs:BAAALgADCgEJAQAAAA==.Florassa:BAAALgADCgUJBQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAACLgAFFH8HAAINAAMJFA7NqQDKAAANAAMJFA7NqQDKAAAuAAQKfyEAAg0ABgnTFi2NAEsBAA0ABgnTFi2NAEsBAAEuAAUUBAkSABUA8B0A.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgAECgQJBAAAAA==.Furrystorm:BAAALgAFFAEJAgAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIaAAkJlA6bYwC3AQAaAAkJlA6bYwC3AQAAAA==.Garroc:BAAALgAECgYJBgAAAA==.',
Gh='Ghast:BAABLgAECn9xAAMSAAkJbRvDBQCnAQASAAkJzhjDBQCnAQAJAAcJ8BJXDACXAQAAAA==.Ghats:BAACLgAFFH8HAAMJAAQJ2gofAwANAQAJAAQJ2gofAwANAQASAAEJJQfiygA/AAAuAAQKfxsABBIACQmNF+U3APoBABIACAmdGOU3APoBAAkAAwkYFCkNAEgAACAAAgkcFJ07ADwAAAAA.',
Gi='Giddley:BAAALgAECgEJAQAAAA==.Gigaflare:BAABLgAECn8nAAIaAAkJqAwkgwDLAQAaAAkJqAwkgwDLAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgIJAgAAAA==.',
Gn='Gnev:BAAALgAECgEJAQAAAA==.Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatale:BAAALgAECgYJCwABLgAECgkJLAANAFQgAA==.Goatknight:BAABLgAECn8sAAINAAkJVCCGEwDTAgANAAkJVCCGEwDTAgAAAA==.Goatwings:BAAALgAECgIJAgAAAA==.Goatwizard:BAAALgAECgMJAwAAAA==.Gobblynn:BAAALgADCggJEAAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAxK4ADeAAABAAcJHAxK4ADeAAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn9OAAISAAkJDhFQCABXAQASAAkJDhFQCABXAQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJCAAAAA==.Greywings:BAABLgAECn83AAIXAAkJrQ1PCQCWAQAXAAkJrQ1PCQCWAQAAAA==.Grimroxs:BAABLgAECn84AAMQAAkJ5BB+BwDgAQAQAAkJ+w9+BwDgAQAPAAMJAwueDAB3AAAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgAECgQJCQABLgAFFAMJAwADAAAAAA==.Grizzlemaw:BAAALgAECgcJEgAAAA==.',
Ha='Hacheros:BAAALgAECgIJAgAAAA==.Hadic:BAAALgADCgEJAQABLgAECgkJCQADAAAAAA==.Hairypits:BAAALgAECgYJDQABLgAECgkJLAANAFQgAA==.Handerbug:BAABLgAECn8uAAMTAAkJRyb0AgCFAwATAAkJRyb0AgCFAwAZAAYJtBypFwCUAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgATAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgATAEcmAA==.Handybug:BAAALgAECgEJAQABLgAECgkJLgATAEcmAA==.Hankit:BAAALgAECgQJBQAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJCgAAAA==.Hazmati:BAAALgADCgkJCQABLgAFFAQJDgAcALkHAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Healtaxi:BAAALgAFFAMJAwAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAABLgAECn8hAAIEAAkJIwsNLQBjAQAEAAkJIwsNLQBjAQAAAA==.Heinrich:BAABLgAECn8vAAMBAAgJ8iMeFwC4AgABAAgJ8iMeFwC4AgAGAAQJPRFAbADJAAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.Hippypedro:BAAALgAECgYJEQABLgAFFAcJIgAIAOscAA==.',
Ho='Hobotimers:BAAALgAECgEJAQABLgAECgIJAQADAAAAAA==.Hogglethorp:BAAALgAECggJEwAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyfist:BAAALgADCgEJAQAAAA==.Holyhooters:BAAALgAECgEJAQAAAA==.Holyloro:BAAALgADCgIJAgAAAA==.Horns:BAAALgAECggJCAAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Hy='Hyper:BAAALgADCgEJAQAAAA==.',
['Hé']='Héxualhealin:BAAALgAECgEJAQAAAA==.',
Ie='Iegend:BAAALgAFFAIJBAAAAA==.',
Il='Ilina:BAAALgAECgUJDQABLgAFFAIJAgADAAAAAA==.Illadron:BAAALgAFFAEJAgAAAA==.Illecebra:BAAALgAFFAEJAQAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAABLgAECn8dAAMTAAgJ6Qx4OQAtAQATAAgJ6Qx4OQAtAQAYAAMJUgxLnQB2AAAAAA==.',
Ja='Jabuljina:BAAALgAECgEJAQAAAA==.Jacksus:BAAALgAFFAEJAQAAAA==.Jagerblunt:BAACLgAFFH8LAAIRAAQJSBkWMwBIAQARAAQJSBkWMwBIAQAuAAQKfyQAAhEACQmoGWYyABICABEACQmoGWYyABICAAAA.',
Jd='Jdbud:BAAALgAECgQJBgAAAA==.Jdpot:BAAALgAECgYJEAAAAA==.',
Je='Jenaaidy:BAABLgAECn80AAICAAkJdhl3BgBDAQACAAkJdhl3BgBDAQAAAA==.',
Jh='Jhannae:BAAALgAECgYJEAAAAA==.',
Ji='Jiks:BAAALgAECgIJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLgAKAPIhAA==.Joshery:BAABLgAECn8uAAMKAAkJ8iGLBQAJAwAKAAkJ8iGLBQAJAwAcAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJCQABLgAECgkJLgAKAPIhAA==.',
Ju='Judge:BAABLgAECn8sAAIBAAkJ6BJZTgDcAQABAAkJ6BJZTgDcAQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8zAAIeAAkJtCFZBADvAgAeAAkJtCFZBADvAgAAAA==.',
Ka='Katasaria:BAACLgAFFH8XAAMVAAYJRRy3EwBsAQAVAAUJFCC3EwBsAQAfAAIJ5hC+GgBNAAAuAAQKfysAAxUACAmNIG4UAKoCABUACAkXIG4UAKoCAB8ABQk0GpUsABgBAAAA.Katiebug:BAAALgADCgUJBQAAAA==.Katiekat:BAAALgADCgMJAwAAAA==.Kaycee:BAAALgADCgUJCAABLgAECgcJDQADAAAAAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECgcJDQADAAAAAA==.Kaycer:BAAALgADCggJDwABLgAECgcJDQADAAAAAA==.',
Ke='Keeps:BAAALgAECgEJAQAAAA==.Kerl:BAAALgAECggJEQABLgAECgkJCQADAAAAAA==.',
Ki='Kiboridi:BAAALgAECgQJBgAAAA==.Killerxx:BAAALgAECgEJAgABLgAECggJIQAVAEEMAA==.Kimetshu:BAABLgAECn8gAAIIAAgJaBQUHgCLAQAIAAgJaBQUHgCLAQAAAA==.Kirana:BAABLgAECn8vAAMTAAkJfQaMPgAVAQATAAkJfQaMPgAVAQAYAAUJRASumACBAAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAINAAgJRAttkABfAQANAAgJRAttkABfAQAAAA==.',
Ko='Kolaro:BAAALgAECgEJAgAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIhAAkJqBtwBgCAAgAhAAkJqBtwBgCAAgAAAA==.Kravin:BAAALgAECgQJCwAAAA==.Krunzar:BAAALgAECgUJBwAAAA==.',
Kt='Ktheir:BAAALgAECgMJBAAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Lammasthan:BAAALgAECgkJCQAAAA==.Laneywine:BAAALgAECgYJDwAAAA==.Larlifax:BAAALgAECgUJBwAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.Lauxy:BAAALgAECgUJCAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAACLgAFFH8PAAIVAAUJBR+bCABrAQAVAAUJBR+bCABrAQAuAAQKfzMAAhUACQlxJWoCAE0DABUACQlxJWoCAE0DAAAA.Levìstus:BAABLgAECn8tAAINAAkJTRm2LQBJAgANAAkJTRm2LQBJAgAAAA==.Leylaní:BAABLgAECn8jAAIRAAkJrRS+MAAZAgARAAkJrRS+MAAZAgAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.Lilmissblue:BAAALgAECgcJBwAAAA==.',
Lo='Loan:BAAALgAECgEJAgAAAA==.Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgUJBwAAAA==.Loosecaboose:BAAALgAECgcJCAAAAA==.Loroessan:BAAALgAECgkJDwAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAABLgAECn8ZAAIBAAkJRRAYHgC/AAABAAkJRRAYHgC/AAAAAA==.Lukas:BAAALgAECgcJCQABLgAECgkJcQASAG0bAA==.Lunet:BAAALgAECgcJBwAAAA==.Lustie:BAAALgAECgYJEwABLgAECgkJNQAXAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAXAMEfAA==.Lytheum:BAABLgAECn81AAIXAAkJwR8rAgCsAgAXAAkJwR8rAgCsAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
['Lü']='Lücid:BAAALgAECgEJAgAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQALACggAA==.Magerrac:BAAALgAECgEJAQABLgAECgkJHwAMANAIAA==.Magikon:BAAALgAECgEJAQAAAA==.Magista:BAAALgAECgMJAwAAAA==.Malachar:BAABLgAECn8xAAIMAAkJIA1FGAB9AQAMAAkJIA1FGAB9AQAAAA==.Malboro:BAABLgAECn8rAAISAAgJ7BJAWwCMAQASAAgJ7BJAWwCMAQAAAA==.Maled:BAABLgAECn8zAAQJAAkJoh43CADnAQAJAAgJFxw3CADnAQAgAAQJkxzKFgDuAAASAAMJohBR3wCcAAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrew:BAAALgAECgkJBwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Mej:BAAALgAECgQJBAAAAA==.Meldin:BAABLgAECn8jAAIRAAkJZCDkDwDRAgARAAkJZCDkDwDRAgAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgUJCQAAAA==.Method:BAABLgAECn8rAAMiAAkJBxT7EQCmAQAiAAkJhxP7EQCmAQABAAIJFxNXPAFwAAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMGAAcJdh2WJQDbAQAGAAcJdh2WJQDbAQABAAEJJgEz1AERAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIcAAkJ5Bl2EABGAgAcAAkJ5Bl2EABGAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8nAAMHAAgJGBbDSgCmAQAHAAgJzxXDSgCmAQAjAAEJeRgmKQBAAAAAAA==.Mineos:BAABLgAECn8ZAAIVAAcJww4+RwApAQAVAAcJww4+RwApAQAAAA==.Minipedro:BAAALgAECgQJBAABLgAFFAcJIgAIAOscAA==.Mistrmiso:BAAALgAECgMJAgABLgAECgkJLwAJALolAA==.Mizoh:BAAALgAECgYJEAAAAA==.',
Mo='Moahuntress:BAAALgAECgYJCQAAAA==.Mookie:BAAALgAECgMJAwAAAA==.Moonlyt:BAAALgADCgkJIQAAAA==.Morgaine:BAAALgAECgcJBwABLgAECgkJHwAMANAIAA==.Morn:BAABLgAECn8bAAMXAAkJNRt+BwBzAgAXAAkJNRt+BwBzAgAdAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJcQASAG0bAA==.',
Mt='Mtrain:BAAALgAECgYJCgABLgAFFAQJBwAJANoKAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myori:BAAALgAECgMJAwAAAA==.Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgAECgYJCAAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.Naturesdevil:BAAALgAECgUJBQABLgAFFAMJDQAOAEEGAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAABLgAECn8jAAIeAAkJSReJEAADAgAeAAkJSReJEAADAgAAAA==.Neeryn:BAAALgAECgIJAgAAAA==.Nestiae:BAAALgAECgMJAwABLgAECgYJCQADAAAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAFFAIJBAADAAAAAA==.Nightsfuri:BAABLgAECn8bAAITAAgJHxNfKQCIAQATAAgJHxNfKQCIAQAAAA==.Nik:BAAALgAECgQJBQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8hAAIRAAkJKgyTUgCrAQARAAkJKgyTUgCrAQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orlandbro:BAABLgAECn8nAAQRAAkJ2x1iGAB3AgAkAAkJxhy4BQCyAgARAAkJ4BdiGAB3AgAWAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Papapedro:BAAALgAECgIJAgABLgAFFAcJIgAIAOscAA==.Patantrad:BAABLgAECn8bAAMNAAkJUg8ncwB9AQANAAkJzQ0ncwB9AQAeAAQJpg+6NADFAAAAAA==.Patchs:BAAALgAECgYJBgAAAA==.Patchy:BAAALgAECgUJBQAAAA==.Pawradox:BAABLgAECn8lAAICAAkJxg03KgCAAQACAAkJxg03KgCAAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAwAAAA==.',
Ph='Phenomenon:BAABLgAECn8jAAIRAAcJSCEkCADJAQARAAcJSCEkCADJAQAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIeAAkJUh7iBwCpAgAeAAkJUh7iBwCpAgAAAA==.Pitviper:BAABLgAECn8XAAIlAAcJnBi7FAA1AQAlAAcJnBi7FAA1AQAAAA==.',
Pl='Plina:BAABLgAECn8hAAIBAAkJGhclPgANAgABAAkJGhclPgANAgAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponglenis:BAAALgAFFAIJAgABLgAFFAIJBAADAAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Poshiesty:BAAALgAFFAEJAQAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAABLgAFFH8KAAILAAQJCBP/NwACAQALAAQJCBP/NwACAQAAAA==.',
Pu='Pulli:BAAALgAECgkJEQAAAA==.',
Pv='Pve:BAACLgAFFH8FAAIkAAUJBwVtHwDbAAAkAAUJBwVtHwDbAAAuAAQKfy8AAiQACQn0H+EGALECACQACQn0H+EGALECAAAA.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAACLgAFFH8PAAILAAQJvA+rHADUAAALAAQJvA+rHADUAAAuAAQKfyYAAgsACQnDFQ8LAEEBAAsACQnDFQ8LAEEBAAAA.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIaAAcJcRTIjwBYAQAaAAcJcRTIjwBYAQAAAA==.Rathane:BAACLgAFFH8IAAIRAAQJtQqrUgAEAQARAAQJtQqrUgAEAQAuAAQKfykAAhEACQlSGnwMAHUBABEACQlSGnwMAHUBAAAA.Rawrmuch:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.Ray:BAAALgAECgYJBgABLgAECgkJGwAXADUbAA==.',
Re='Realmclovin:BAAALgAECgUJBQAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Redrabbit:BAAALgAECgYJBwAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8uAAIGAAkJjiYpAAD0AwAGAAkJjiYpAAD0AwAAAA==.',
Ri='Rizmund:BAAALgAECgEJAQAAAA==.Rizzwan:BAABLgAECn8rAAIkAAkJoyCEBADlAgAkAAkJoyCEBADlAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMcAAMJYQnAKgClAAAcAAMJYQnAKgClAAAKAAIJ0AxsUQBiAAAuAAQKfykABAoACQmMHZEQAJ4CAAoACAmXHJEQAJ4CABwACAmwG2ETACICABsAAQmJDjiPADQAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAFFAEJAgABLgAFFAYJFwAVAEUcAA==.Romy:BAABLgAECn8vAAIaAAgJMQM94gDXAAAaAAgJMQM94gDXAAAAAA==.Roonoe:BAAALgAECgMJAwAAAA==.',
Ru='Runecleaver:BAABLgAECn87AAMLAAkJBCKdEQDBAgALAAkJBCKdEQDBAgAUAAQJExYbUwDsAAAAAA==.Ruw:BAABLgAECn8yAAMQAAkJlBToAAC0AQAQAAgJrhboAAC0AQAPAAQJKgg6QQDAAAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8lAAINAAkJ7h9HFwC7AgANAAkJ7h9HFwC7AgAAAA==.Satania:BAABLgAECn8fAAIIAAkJGiTyBAAlAwAIAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8rAAMEAAkJ1RO6FQAmAgAEAAkJ1RO6FQAmAgACAAcJjxOaLABxAQAAAA==.',
Se='Segora:BAABLgAECn8aAAISAAYJRAcGnwAbAQASAAYJRAcGnwAbAQABLgAECgkJTgASAA4RAA==.Seimus:BAABLgAECn8UAAIaAAUJcRE81wDnAAAaAAUJcRE81wDnAAAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAABLgAECn8UAAIBAAYJFBHZtAAYAQABAAYJFBHZtAAYAQAAAA==.Shababba:BAAALgAECgIJAQAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shamoosier:BAAALgAECgMJAwAAAA==.Shapòópy:BAABLgAECn8kAAITAAkJTgmCQgADAQATAAkJTgmCQgADAQAAAA==.Sharius:BAABLgAECn8sAAIaAAkJ3wlIgQB1AQAaAAkJ3wlIgQB1AQAAAA==.Shavv:BAAALgADCggJCAAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIaAAkJ6hJwZAAPAgAaAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJDgAAAA==.Shoot:BAAALgAECgEJAQAAAA==.Shootybooty:BAAALgAECgMJAwAAAA==.Shutendoji:BAAALgAECgEJAgABLgAECggJHQAcAKohAA==.',
Si='Sightlightx:BAABLgAECn8VAAMcAAkJNhElOQAdAQAcAAcJ9w0lOQAdAQAKAAYJDRYXWwAIAQAAAA==.Sigs:BAAALgAECgMJBAAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8xAAIVAAkJvgrCMgCAAQAVAAkJvgrCMgCAAQAAAA==.Sinkingbridg:BAAALgAECgIJAgAAAA==.Siryn:BAABLgAECn8nAAMGAAkJ/wNPWgDNAAAGAAkJ/wNPWgDNAAABAAEJGgUoXAAhAAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smallest:BAAALgAECgcJDQAAAA==.Smashn:BAABLgAECn8iAAMlAAcJgBUmBAAPAQAlAAcJwBQmBAAPAQANAAYJmwuZxwD0AAAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.Snakeshadow:BAAALgAECgkJCQAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAFFAEJAQADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAImAAkJmBOJAwDlAQAmAAkJmBOJAwDlAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgAECgEJAQAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Sunkenbridge:BAAALgADCgQJBAAAAA==.Surperknight:BAAALgADCgUJBQAAAA==.Susa:BAAALgADCgEJAQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMYAAkJAB7UEACxAgAYAAkJAB7UEACxAgATAAcJnhXyLQBrAQAAAA==.Syrden:BAAALgAECgYJCAABLgAECgkJFgAYAOgLAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Takkut:BAAALgAECgYJCQABLgAECggJIQAVAEEMAA==.Takory:BAAALgADCgQJBAAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCggJDQAAAA==.Tanholy:BAAALgAECgUJBQAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tarnation:BAAALgAECgEJAQAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAFFAIJAwAAAA==.Tessarion:BAAALgAECgkJCQAAAA==.',
Th='Thandas:BAABLgAECn9BAAIBAAgJbRXxEQAfAQABAAgJbRXxEQAfAQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAwAAAA==.Thniper:BAABLgAECn8oAAMWAAkJURgyGABrAgAWAAgJQBsyGABrAgAkAAUJ9wyIMQAgAQAAAA==.Thoriumaster:BAAALgAECgUJDQAAAA==.Thouvan:BAAALgAECgEJAQAAAA==.Thugnastyy:BAAALgAFFAIJBAABLgAFFAIJBAADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIGAAkJqxpwFgBYAgAGAAkJqxpwFgBYAgAAAA==.',
To='Tost:BAAALgAECgEJAQABLgAECgIJAQADAAAAAA==.Touchyfeely:BAAALgAECgUJBQAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.Tusker:BAAALgAECgUJBQAAAA==.',
Ty='Tyinviril:BAACLgAFFH8YAAICAAcJ4yP8AQB1AgACAAcJ4yP8AQB1AgAuAAQKf1QAAgIACQnWJZQBAGIDAAIACQnWJZQBAGIDAAAA.',
Ul='Ulrik:BAAALgAECgEJAQABLgAECgkJcQASAG0bAA==.',
Un='Unter:BAAALgAECgEJAQAAAA==.',
Ur='Urana:BAAALgADCgMJAwAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.Varlund:BAAALgAECgUJBgAAAA==.',
Ve='Veraz:BAACLgAFFH8ZAAMBAAcJTA+3GACqAQABAAcJTA+3GACqAQAGAAEJRgFTSAA7AAAuAAQKf0AAAwEACAlcIRIgAIgCAAEACAlcIRIgAIgCAAYABQk8CflgAPgAAAAA.Verna:BAAALgADCgIJAgAAAA==.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAABLgAECn8SAAIHAAcJDwtGiAAQAQAHAAcJDwtGiAAQAQAAAA==.Voidrayge:BAAALgAECgEJAQAAAA==.Vonawesome:BAAALgAECgUJCwAAAA==.Vorpalblade:BAABLgAECn8uAAIMAAkJMRcoEADkAQAMAAkJMRcoEADkAQAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAABLgAFFH8HAAINAAMJLQgxtwC5AAANAAMJLQgxtwC5AAAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgAECgQJBAAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8xAAMnAAkJ5B4HAQDOAgAnAAkJ5B4HAQDOAgAaAAEJPBnwSwE/AAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIiAAkJfhIeEgCkAQAiAAkJfhIeEgCkAQAAAA==.Willowfox:BAAALgAECgMJCwAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJDAAAAA==.Wobblingwar:BAAALgAECgMJAwABLgAECgcJDAADAAAAAA==.',
Wr='Wrahis:BAAALgAECgUJCAAAAA==.Wram:BAABLgAECn8fAAMMAAkJ0AgjIgAfAQAMAAkJ0AgjIgAfAQAVAAIJJAEiuQAZAAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECgkJHwAMANAIAA==.Wreckuiem:BAAALgAECggJEwAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8gAAMgAAgJ7h4YBgAEAgAgAAgJ8x0YBgAEAgASAAYJ8RicTAC1AQAAAA==.',
Xa='Xamgreen:BAAALgADCgkJCQAAAA==.',
Xe='Xenophilious:BAAALgAECgcJBwAAAA==.',
Xi='Xiomara:BAAALgADCgUJBQAAAA==.Xiøn:BAACLgAFFH8TAAIHAAUJOhrVOwA2AQAHAAUJOhrVOwA2AQAuAAQKfysAAgcACQm5HlgRALcCAAcACQm5HlgRALcCAAAA.',
Xr='Xristinà:BAAALgADCgkJCQAAAA==.',
Ya='Yamauba:BAAALgAECgQJBAAAAA==.',
Yn='Yn:BAAALgAFFAIJAwAAAA==.',
Zi='Zillara:BAABLgAECn8bAAIQAAkJaAZpDwAuAQAQAAkJaAZpDwAuAQAAAA==.',
['Zù']='Zùlfang:BAAALgAECgUJBQABLgAECgkJKwAVAGgZAA==.',
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
