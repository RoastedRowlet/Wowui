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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Affliction','Monk-Mistweaver','Shaman-Restoration','Warrior-Protection','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Warrior-Fury','Hunter-Marksmanship','Evoker-Devastation','Druid-Restoration','Mage-Frost','Monk-Brewmaster','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Blood','Warrior-Arms','Druid-Guardian','Warlock-Destruction','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Frost','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abráms:BAAALgAECgEJAQAAAA==.',
Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8jAAIBAAkJBRz7SwDiAQABAAkJBRz7SwDiAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzggZNABIAQACAAkJzggZNABIAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn80AAIBAAkJvg43gwBpAQABAAkJvg43gwBpAQAAAA==.',
Aj='Ajaki:BAABLgAECn8sAAQEAAgJKhYhBAACAQAEAAgJKhYhBAACAQAFAAcJmAbZQwD5AAACAAMJUAz8YQCSAAAAAA==.',
Al='Allandra:BAAALgAECgYJBgAAAA==.Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJBAAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgYJEgAAAA==.Amelandra:BAAALgAECgEJAQAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgIJAgAAAA==.Anklebiter:BAAALgAECgEJBAAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgcJEAAAAA==.Arlan:BAABLgAECn8fAAIGAAkJdR7cDgCoAgAGAAkJdR7cDgCoAgAAAA==.Arlequin:BAABLgAECn8ZAAMHAAkJjgnVqwDOAAAHAAcJMAnVqwDOAAAIAAMJqAqCVQBlAAAAAA==.Arnagan:BAAALgAECgUJBQAAAA==.',
As='Asale:BAAALgAECgEJAQAAAA==.Ascend:BAAALgAECgYJCAABLgAFFAQJBwAJANoKAA==.Asharothh:BAABLgAECn8mAAIKAAkJYxtWFwBeAgAKAAkJYxtWFwBeAgAAAA==.Ashdem:BAABLgAECn8ZAAIHAAcJNw7tgwAYAQAHAAcJNw7tgwAYAQAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.Ashtomb:BAAALgAECgEJAQABLgAECgkJOwALAAQiAA==.',
At='Athenâ:BAABLgAECn8YAAIMAAkJlhF8FACqAQAMAAkJlhF8FACqAQAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1ge5jQAtAAAFAAIJFgLpiQAfAAAAAA==.Azkar:BAAALgADCgEJAQAAAA==.Azorahai:BAABLgAECn8yAAINAAgJig1edgB3AQANAAgJig1edgB3AQAAAA==.Azshalia:BAABLgAECn8hAAIMAAgJFwt7IgAcAQAMAAgJFwt7IgAcAQAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8nAAQOAAgJURCeCgB2AQAOAAgJMA+eCgB2AQAPAAYJpA3vNQBgAQAQAAcJkQxMDgBAAQABLgAECgcJDAADAAAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMIAAcJ6R0BFQDnAQAIAAcJ6R0BFQDnAQAHAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8wAAIRAAkJOxULLgAkAgARAAkJOxULLgAkAgAAAA==.',
Be='Beffis:BAAALgAECgMJAwAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQABLgAECgkJQAARADMYAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8vAAMJAAkJuiWnAAAuAwAJAAkJmCWnAAAuAwASAAgJ7B3LJgBCAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Blitzkriêg:BAAALgAECgIJAQAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgATAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8tAAIUAAkJ3R1IDgCIAgAUAAkJ3R1IDgCIAgAAAA==.Boblin:BAABLgAECn8oAAIVAAcJZBAtAwBLAQAVAAcJZBAtAwBLAQAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn81AAILAAkJGSBSBwA7AwALAAkJGSBSBwA7AwAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAABLgAECn8dAAMRAAcJ9QK+zwCqAAARAAYJswK+zwCqAAAWAAcJpgJDNgBEAAAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSI/EADkAgABAAkJrSI/EADkAgAAAA==.Bosshogshift:BAAALgAECgYJBgABLgAECgkJNAABAK0iAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8JAAIMAAUJziAkBgAIAQAMAAUJziAkBgAIAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgATAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bulgear:BAAALgAECgMJBgAAAA==.Bupropion:BAABLgAECn8eAAIHAAYJAhl6YQBmAQAHAAYJAhl6YQBmAQABLgAECgkJNQAXAMEfAA==.Bushwhacker:BAAALgAECgYJCAAAAA==.Butterbean:BAABLgAECn8tAAIRAAkJCCB3CwDnAgARAAkJCCB3CwDnAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECggJEgAAAA==.Catameringue:BAABLgAECn8cAAMYAAcJBBHqRAB9AQAYAAcJBBHqRAB9AQATAAYJ7wyVBADpAAAAAA==.',
Ch='Chickenhawk:BAAALgAECgEJAgAAAA==.Chicxulub:BAABLgAECn8cAAIZAAkJ+RO7XwDBAQAZAAkJ+RO7XwDBAQAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMLAAkJKCBBCQDjAgALAAkJKCBBCQDjAgAUAAYJCREPUAD3AAAAAA==.Clickshoot:BAAALgAECgYJDAAAAA==.',
Co='Coaca:BAABLgAECn8yAAMBAAkJ6x0XIgB+AgABAAkJ6x0XIgB+AgAGAAEJEQf5mQAmAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAFFAMJCgASADYbAA==.Confluent:BAABLgAECn81AAMYAAkJQyW7AQC+AwAYAAkJQyW7AQC+AwATAAkJAhggEgBHAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn85AAMaAAkJ7xL2IwCLAQAaAAkJ7xL2IwCLAQAbAAEJygpZEQAoAAAAAA==.',
Cu='Cursè:BAAALgADCgIJAgABLgAECgkJLAAZAN8JAA==.',
Cy='Cythrandir:BAAALgAECgYJDAABLgAFFAUJEwAZAP8RAA==.',
Da='Daikellus:BAAALgAECgQJBAAAAA==.Dalkith:BAAALgAECgIJAgABLgAECggJEwADAAAAAA==.Daniellena:BAAALgADCgkJGAAAAA==.Davwr:BAAALgAECgMJAwABLgAECgkJGAANAH4TAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECgkJEwAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Demoloro:BAAALgAECgEJAQAAAA==.Dethrahzen:BAABLgAECn8+AAMXAAkJiAdGAQDGAAAXAAkJiAdGAQDGAAAcAAIJhwGanQAjAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8tAAIVAAkJpRouGAAtAgAVAAkJpRouGAAtAgAAAA==.',
Dj='Djcamsoda:BAAALgAECgEJAgAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAABLgAECn8ZAAMdAAgJCAz3KQAIAQAdAAgJmwr3KQAIAQANAAEJiRA+JAA5AAAAAA==.',
Do='Doomslayer:BAAALgAECgEJAQAAAA==.Dorelios:BAAALgADCgQJBAAAAA==.Dotsfordayz:BAAALgAECgMJBAABLgAECgMJBQADAAAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJGAAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAABLgAECn8WAAMRAAYJbQW8tQDZAAARAAYJbQW8tQDZAAAWAAMJGwAFnAAOAAAAAA==.Drstránge:BAAALgADCgYJBgAAAA==.',
Du='Dubstep:BAAALgAECgYJEQAAAA==.Dugatotems:BAABLgAECn80AAMLAAkJPxrjGwA5AgALAAkJPxrjGwA5AgAUAAkJ5QjyPABCAQAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dumpytruck:BAAALgAECgQJBQAAAA==.Dunkle:BAABLgAECn8tAAMeAAkJgyD8BwB2AgAVAAkJihz8EwCuAgAeAAkJzBv8BwB2AgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8pAAIRAAkJkwsjUACyAQARAAkJkwsjUACyAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEgAAAA==.',
Eb='Ebonise:BAAALgAECgUJDwAAAA==.',
Ed='Edrelang:BAABLgAECn8gAAMVAAcJaQvmSgAaAQAVAAcJaQvmSgAaAQAeAAIJrQSUcgA8AAAAAA==.',
Ee='Eerikki:BAAALgAECgYJEQAAAA==.',
Ei='Eightsix:BAAALgAFFAIJAwABLgAFFAQJBwAJANoKAA==.Ein:BAABLgAECn82AAIXAAkJXRrqAgB+AgAXAAkJXRrqAgB+AgAAAA==.',
El='Ellechero:BAABLgAECn8kAAMfAAgJQAgqOQDBAAATAAcJKQX2UQDGAAAfAAcJfQcqOQDBAAAAAA==.Ellonia:BAAALgAECgMJAwABLgAECggJIAAgAO4eAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.Elsmerelda:BAAALgADCgUJBQAAAA==.',
Er='Eragøn:BAABLgAECn8WAAIRAAcJrBokQwDZAQARAAcJrBokQwDZAQAAAA==.Erinna:BAAALgAECgEJBQAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgcJEgAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgkJHwAMANAIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fedagolas:BAAALgAECgEJAQAAAA==.Fengpopo:BAAALgADCgEJAQAAAA==.Fextrius:BAAALgAECgYJCgAAAA==.',
Fl='Florassa:BAAALgADCgUJBQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAACLgAFFH8HAAINAAMJFA7NqQDKAAANAAMJFA7NqQDKAAAuAAQKfyEAAg0ABgnTFi2NAEsBAA0ABgnTFi2NAEsBAAEuAAUUBAkSABUA8B0A.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgAECgQJBAAAAA==.Furrystorm:BAAALgAFFAEJAgAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIZAAkJlA6bYwC3AQAZAAkJlA6bYwC3AQAAAA==.Garroc:BAAALgAECgYJBgAAAA==.',
Gh='Ghast:BAABLgAECn9oAAMSAAkJ/xqgJQBHAgASAAkJ7RegJQBHAgAJAAcJ8BJXDACXAQAAAA==.Ghats:BAACLgAFFH8HAAMJAAQJ2gogAQAlAQAJAAQJ2gogAQAlAQASAAEJJQfiygA/AAAuAAQKfxoABBIACAmdGOU3APoBABIACAmdGOU3APoBAAkAAgkVGI82AEoAACAAAgkcFJ07ADwAAAAA.',
Gi='Giddley:BAAALgAECgEJAQAAAA==.Gigaflare:BAABLgAECn8nAAIZAAkJqAwkgwDLAQAZAAkJqAwkgwDLAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgIJAgAAAA==.',
Gn='Gnev:BAAALgAECgEJAQAAAA==.Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatale:BAAALgAECgYJCwABLgAECgkJLAANAFQgAA==.Goatknight:BAABLgAECn8sAAINAAkJVCCGEwDTAgANAAkJVCCGEwDTAgAAAA==.Goatwings:BAAALgAECgIJAgAAAA==.Goatwizard:BAAALgAECgMJAwAAAA==.Gobblynn:BAAALgADCggJEAAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAxK4ADeAAABAAcJHAxK4ADeAAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn9GAAISAAkJbRCKBgABAQASAAkJbRCKBgABAQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJCAAAAA==.Greywings:BAABLgAECn83AAIXAAkJrQ1PCQCWAQAXAAkJrQ1PCQCWAQAAAA==.Grimroxs:BAABLgAECn84AAMQAAkJ5BB+BwDgAQAQAAkJ+w9+BwDgAQAPAAMJAwuZBgB8AAAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgAECgQJCAABLgAECgMJBQADAAAAAA==.Grizzlemaw:BAAALgAECgcJDQAAAA==.',
Ha='Hacheros:BAAALgAECgIJAgAAAA==.Hadic:BAAALgADCgEJAQABLgAECgkJCQADAAAAAA==.Hairypits:BAAALgAECgYJDQABLgAECgkJLAANAFQgAA==.Handerbug:BAABLgAECn8uAAMTAAkJRyb0AgCFAwATAAkJRyb0AgCFAwAfAAYJtBypFwCUAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgATAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgATAEcmAA==.Handybug:BAAALgAECgEJAQABLgAECgkJLgATAEcmAA==.Hankit:BAAALgAECgQJBQAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJCgAAAA==.Hazmati:BAAALgADCgkJCQABLgAFFAQJDgAbALkHAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Healtaxi:BAAALgAECgMJBQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAABLgAECn8hAAIEAAkJIwsNLQBjAQAEAAkJIwsNLQBjAQAAAA==.Heinrich:BAABLgAECn8vAAMBAAgJ8iMeFwC4AgABAAgJ8iMeFwC4AgAGAAQJPRFAbADJAAAAAA==.Heira:BAAALgADCgQJCAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.Hippypedro:BAAALgAECgYJEQABLgAFFAYJIQAIAEseAA==.',
Ho='Hogglethorp:BAAALgAECggJEwAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyfist:BAAALgADCgEJAQAAAA==.Holyhooters:BAAALgADCgkJGgAAAA==.Holyloro:BAAALgADCgIJAgAAAA==.Horns:BAAALgAECgUJBQAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAFFAIJBAAAAA==.',
Il='Ilina:BAAALgAECgUJDQABLgAFFAIJAgADAAAAAA==.Illadron:BAAALgAFFAEJAgAAAA==.Illecebra:BAAALgAFFAEJAQAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAABLgAECn8cAAMTAAgJSAp4OQAtAQATAAgJSAp4OQAtAQAYAAMJUgxLnQB2AAAAAA==.',
Ja='Jagerblunt:BAACLgAFFH8LAAIRAAQJSBkWMwBIAQARAAQJSBkWMwBIAQAuAAQKfyQAAhEACQmoGWYyABICABEACQmoGWYyABICAAAA.',
Jd='Jdbud:BAAALgAECgQJBgAAAA==.Jdpot:BAAALgAECgYJEAAAAA==.',
Je='Jenaaidy:BAABLgAECn8vAAICAAgJnhbgHgDOAQACAAgJnhbgHgDOAQAAAA==.',
Jh='Jhannae:BAAALgAECgEJAQAAAA==.',
Ji='Jiks:BAAALgAECgIJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLgAKAPIhAA==.Joshery:BAABLgAECn8uAAMKAAkJ8iGLBQAJAwAKAAkJ8iGLBQAJAwAbAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJCQABLgAECgkJLgAKAPIhAA==.',
Ju='Judge:BAABLgAECn8sAAIBAAkJ6BJZTgDcAQABAAkJ6BJZTgDcAQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8zAAIdAAkJtCFZBADvAgAdAAkJtCFZBADvAgAAAA==.',
Ka='Katasaria:BAACLgAFFH8WAAMVAAUJFCC3EwBsAQAVAAUJFCC3EwBsAQAeAAEJxxRWQABJAAAuAAQKfysAAxUACAmNIG4UAKoCABUACAkXIG4UAKoCAB4ABQk0GpUsABgBAAAA.Kaycee:BAAALgADCgUJCAABLgAECgcJDAADAAAAAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECgcJDAADAAAAAA==.Kaycer:BAAALgADCggJDwABLgAECgcJDAADAAAAAA==.',
Ke='Keeps:BAAALgAECgEJAQAAAA==.Kerl:BAAALgAECggJEQABLgAECgkJCQADAAAAAA==.',
Ki='Kiboridi:BAAALgAECgQJBQAAAA==.Killerxx:BAAALgAECgEJAgABLgAECgcJIAAVAGkLAA==.Kimetshu:BAABLgAECn8gAAIIAAgJaBQUHgCLAQAIAAgJaBQUHgCLAQAAAA==.Kirana:BAABLgAECn8vAAMTAAkJfQaMPgAVAQATAAkJfQaMPgAVAQAYAAUJRASumACBAAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAINAAgJRAttkABfAQANAAgJRAttkABfAQAAAA==.',
Ko='Kolaro:BAAALgAECgEJAgAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIhAAkJqBtwBgCAAgAhAAkJqBtwBgCAAgAAAA==.Kravin:BAAALgAECgQJCwAAAA==.Krunzar:BAAALgAECgUJBwAAAA==.',
Kt='Ktheir:BAAALgAECgMJAwAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Lammasthan:BAAALgAECgkJCQAAAA==.Laneywine:BAAALgAECgYJDwAAAA==.Larlifax:BAAALgAECgUJBwAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAACLgAFFH8JAAIVAAQJQhp0BABcAQAVAAQJQhp0BABcAQAuAAQKfzMAAhUACQlxJWoCAE0DABUACQlxJWoCAE0DAAAA.Levìstus:BAABLgAECn8tAAINAAkJTRm2LQBJAgANAAkJTRm2LQBJAgAAAA==.Leylaní:BAABLgAECn8jAAIRAAkJrRS+MAAZAgARAAkJrRS+MAAZAgAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgUJBwAAAA==.Loosecaboose:BAAALgAECgcJCAAAAA==.Loroessan:BAAALgAECgkJDwAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAABLgAECn8XAAIBAAcJCxA5kwBMAQABAAcJCxA5kwBMAQAAAA==.Lukas:BAAALgAECgcJCQABLgAECgkJaAASAP8aAA==.Lunet:BAAALgAECgcJBwAAAA==.Lustie:BAAALgAECgYJEwABLgAECgkJNQAXAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAXAMEfAA==.Lytheum:BAABLgAECn81AAIXAAkJwR8rAgCsAgAXAAkJwR8rAgCsAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
['Lü']='Lücid:BAAALgAECgEJAgAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQALACggAA==.Magerrac:BAAALgAECgEJAQABLgAECgkJHwAMANAIAA==.Magikon:BAAALgAECgEJAQAAAA==.Magista:BAAALgAECgMJAwAAAA==.Malachar:BAABLgAECn8xAAIMAAkJIA1FGAB9AQAMAAkJIA1FGAB9AQAAAA==.Malboro:BAABLgAECn8rAAISAAgJ7BJAWwCMAQASAAgJ7BJAWwCMAQAAAA==.Maled:BAABLgAECn8uAAQJAAgJ6x43CADnAQAJAAcJXhw3CADnAQAgAAMJrR3KFgDuAAASAAMJohBR3wCcAAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrew:BAAALgAECgkJBwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Mej:BAAALgAECgQJBAAAAA==.Meldin:BAABLgAECn8jAAIRAAkJZCDkDwDRAgARAAkJZCDkDwDRAgAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgUJCQAAAA==.Method:BAABLgAECn8rAAMiAAkJBxT7EQCmAQAiAAkJhxP7EQCmAQABAAIJFxNXPAFwAAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMGAAcJdh2WJQDbAQAGAAcJdh2WJQDbAQABAAEJJgEz1AERAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIbAAkJ5Bl2EABGAgAbAAkJ5Bl2EABGAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8nAAMHAAgJGBbDSgCmAQAHAAgJzxXDSgCmAQAjAAEJeRgmKQBAAAAAAA==.Mineos:BAABLgAECn8XAAIVAAcJvAs+RwApAQAVAAcJvAs+RwApAQAAAA==.Minipedro:BAAALgAECgQJBAABLgAFFAYJIQAIAEseAA==.Mistrmiso:BAAALgAECgMJAgABLgAECgkJLwAJALolAA==.Mizoh:BAAALgAECgYJEAAAAA==.',
Mo='Moahuntress:BAAALgAECgYJCQAAAA==.Mookie:BAAALgAECgMJAwAAAA==.Moonlyt:BAAALgADCgkJIQAAAA==.Morgaine:BAAALgADCggJCwABLgAECgkJHwAMANAIAA==.Morn:BAABLgAECn8bAAMXAAkJNRt+BwBzAgAXAAkJNRt+BwBzAgAcAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJaAASAP8aAA==.',
Mt='Mtrain:BAAALgAECgYJCgABLgAFFAQJBwAJANoKAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myori:BAAALgAECgMJAwAAAA==.Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgAECgYJCAAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAABLgAECn8jAAIdAAkJSReJEAADAgAdAAkJSReJEAADAgAAAA==.Neeryn:BAAALgAECgIJAgAAAA==.Nestiae:BAAALgAECgMJAwABLgAECgYJCQADAAAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAFFAIJBAADAAAAAA==.Nightsfuri:BAABLgAECn8bAAITAAgJHxNfKQCIAQATAAgJHxNfKQCIAQAAAA==.Nik:BAAALgAECgQJBQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8hAAIRAAkJKgyTUgCrAQARAAkJKgyTUgCrAQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orlandbro:BAABLgAECn8nAAQRAAkJ2x1iGAB3AgAkAAkJxhy4BQCyAgARAAkJ4BdiGAB3AgAWAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAABLgAECn8bAAMNAAkJUg8ncwB9AQANAAkJzQ0ncwB9AQAdAAQJpg+6NADFAAAAAA==.Patchs:BAAALgAECgYJBgAAAA==.Patchy:BAAALgAECgQJBAAAAA==.Pawradox:BAABLgAECn8kAAICAAkJ8ww3KgCAAQACAAkJ8ww3KgCAAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAwAAAA==.',
Ph='Phenomenon:BAABLgAECn8dAAIRAAcJ1iAPJwBEAgARAAcJ1iAPJwBEAgAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIdAAkJUh7iBwCpAgAdAAkJUh7iBwCpAgAAAA==.Pitviper:BAABLgAECn8XAAIlAAcJthi7FAA1AQAlAAcJthi7FAA1AQAAAA==.',
Pl='Plina:BAABLgAECn8hAAIBAAkJGhclPgANAgABAAkJGhclPgANAgAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponglenis:BAAALgAFFAIJAgABLgAFFAIJBAADAAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAABLgAFFH8KAAILAAQJCBP/NwACAQALAAQJCBP/NwACAQAAAA==.',
Pu='Pulli:BAAALgAECgkJEQAAAA==.',
Pv='Pve:BAACLgAFFH8FAAIkAAUJBwVtHwDbAAAkAAUJBwVtHwDbAAAuAAQKfy8AAiQACQn0H+EGALECACQACQn0H+EGALECAAAA.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAACLgAFFH8KAAILAAMJ2Q/CFACmAAALAAMJ2Q/CFACmAAAuAAQKfyYAAgsACQnDFRwFAEQBAAsACQnDFRwFAEQBAAAA.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIZAAcJcRTIjwBYAQAZAAcJcRTIjwBYAQAAAA==.Rathane:BAACLgAFFH8HAAIRAAQJtQqrUgAEAQARAAQJtQqrUgAEAQAuAAQKfykAAhEACQlRGlwFAIkBABEACQlRGlwFAIkBAAAA.Rawrmuch:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.Ray:BAAALgAECgYJBgABLgAECgkJGwAXADUbAA==.',
Re='Realmclovin:BAAALgAECgUJBQAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Redrabbit:BAAALgAECgYJBwAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8uAAIGAAkJjiYpAAD0AwAGAAkJjiYpAAD0AwAAAA==.',
Ri='Rizmund:BAAALgAECgEJAQAAAA==.Rizzwan:BAABLgAECn8rAAIkAAkJnyCEBADlAgAkAAkJnyCEBADlAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMbAAMJYQnAKgClAAAbAAMJYQnAKgClAAAKAAIJ0AxsUQBiAAAuAAQKfykABAoACQmMHZEQAJ4CAAoACAmXHJEQAJ4CABsACAmwG2ETACICABoAAQmJDjiPADQAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAFFAEJAQABLgAFFAUJFgAVABQgAA==.Romy:BAABLgAECn8tAAIZAAgJxAI94gDXAAAZAAgJxAI94gDXAAAAAA==.Roonoe:BAAALgAECgMJAwAAAA==.',
Ru='Runecleaver:BAABLgAECn87AAMLAAkJBCKdEQDBAgALAAkJBCKdEQDBAgAUAAQJExYbUwDsAAAAAA==.Ruw:BAABLgAECn8yAAMQAAkJnBRaAAC5AQAQAAgJuBZaAAC5AQAPAAQJKgg6QQDAAAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8lAAINAAkJ7h9HFwC7AgANAAkJ7h9HFwC7AgAAAA==.Satania:BAABLgAECn8fAAIIAAkJGiTyBAAlAwAIAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8rAAMEAAkJ1RO6FQAmAgAEAAkJ1RO6FQAmAgACAAcJjxOaLABxAQAAAA==.',
Se='Segora:BAABLgAECn8aAAISAAYJRAcGnwAbAQASAAYJRAcGnwAbAQABLgAECgkJRgASAG0QAA==.Seimus:BAABLgAECn8UAAIZAAUJcRE81wDnAAAZAAUJcRE81wDnAAAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAABLgAECn8UAAIBAAYJFBHZtAAYAQABAAYJFBHZtAAYAQAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAABLgAECn8iAAITAAgJIAiCQgADAQATAAgJIAiCQgADAQAAAA==.Sharius:BAABLgAECn8sAAIZAAkJ3wlIgQB1AQAZAAkJ3wlIgQB1AQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIZAAkJ6hJwZAAPAgAZAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJDgAAAA==.Shootybooty:BAAALgAECgMJAwAAAA==.Shutendoji:BAAALgAECgEJAgABLgAECggJHQAbAKohAA==.',
Si='Sightlightx:BAABLgAECn8UAAMbAAkJNhElOQAdAQAbAAcJ9w0lOQAdAQAKAAYJDRYXWwAIAQAAAA==.Sigs:BAAALgAECgEJAQAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8xAAIVAAkJvgrCMgCAAQAVAAkJvgrCMgCAAQAAAA==.Sinkingbridg:BAAALgAECgIJAgAAAA==.Siryn:BAABLgAECn8iAAMGAAgJQANPWgDNAAAGAAgJQANPWgDNAAABAAEJGgVoNAAiAAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smallest:BAAALgAECgcJDAAAAA==.Smashn:BAABLgAECn8iAAMlAAcJgBXEAQAMAQAlAAcJwBTEAQAMAQANAAYJmwuZxwD0AAAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.Snakeshadow:BAAALgAECgkJCQAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAFFAEJAQADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAImAAkJmBOJAwDlAQAmAAkJmBOJAwDlAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgAECgEJAQAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.Susa:BAAALgADCgEJAQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMYAAkJAB7UEACxAgAYAAkJAB7UEACxAgATAAcJnhXyLQBrAQAAAA==.Syrden:BAAALgAECgYJCAABLgAECgkJFgAYAOgLAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCggJDQAAAA==.Tanholy:BAAALgAECgUJBAAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJCgAAAA==.Tessarion:BAAALgAECgkJCQAAAA==.',
Th='Thandas:BAABLgAECn9BAAIBAAgJbRVfCAAmAQABAAgJbRVfCAAmAQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAwAAAA==.Thniper:BAABLgAECn8oAAMWAAkJURgyGABrAgAWAAgJQBsyGABrAgAkAAUJ9wyIMQAgAQAAAA==.Thoriumaster:BAAALgAECgQJBQAAAA==.Thouvan:BAAALgAECgEJAQAAAA==.Thugnastyy:BAAALgAFFAIJBAABLgAFFAIJBAADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIGAAkJqxpwFgBYAgAGAAkJqxpwFgBYAgAAAA==.',
To='Tost:BAAALgAECgEJAQABLgAECgIJAQADAAAAAA==.Touchyfeely:BAAALgAECgUJBQAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.Tusker:BAAALgAECgUJBQAAAA==.',
Ty='Tyinviril:BAACLgAFFH8MAAICAAQJNR+LEABnAQACAAQJNR+LEABnAQAuAAQKf1IAAgIACQnWJZQBAGIDAAIACQnWJZQBAGIDAAAA.',
Un='Unter:BAAALgAECgEJAQAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8ZAAMBAAcJTA+3GACqAQABAAcJTA+3GACqAQAGAAEJRgFTSAA7AAAuAAQKf0AAAwEACAlcIRIgAIgCAAEACAlcIRIgAIgCAAYABQk8CflgAPgAAAAA.Verna:BAAALgADCgIJAgAAAA==.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAABLgAECn8SAAIHAAcJDwtGiAAQAQAHAAcJDwtGiAAQAQAAAA==.Vonawesome:BAAALgAECgQJCQAAAA==.Vorpalblade:BAABLgAECn8uAAIMAAkJMRcoEADkAQAMAAkJMRcoEADkAQAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAABLgAFFH8HAAINAAMJLQgxtwC5AAANAAMJLQgxtwC5AAAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgAECgQJBAAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8xAAMnAAkJ5B4HAQDOAgAnAAkJ5B4HAQDOAgAZAAEJPBnwSwE/AAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIiAAkJfhIeEgCkAQAiAAkJfhIeEgCkAQAAAA==.Willowfox:BAAALgAECgMJCwAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJDAAAAA==.Wobblingwar:BAAALgAECgMJAwAAAA==.',
Wr='Wrahis:BAAALgAECgUJCAAAAA==.Wram:BAABLgAECn8fAAMMAAkJ0AgjIgAfAQAMAAkJ0AgjIgAfAQAVAAIJJAEiuQAZAAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECgkJHwAMANAIAA==.Wreckuiem:BAAALgAECggJEwAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8gAAMgAAgJ7h4YBgAEAgAgAAgJ8x0YBgAEAgASAAYJ8RicTAC1AQAAAA==.',
Xe='Xenophilious:BAAALgAECgIJAgAAAA==.',
Xi='Xiøn:BAACLgAFFH8TAAIHAAUJOhrVOwA2AQAHAAUJOhrVOwA2AQAuAAQKfysAAgcACQm5HlgRALcCAAcACQm5HlgRALcCAAAA.',
Xr='Xristinà:BAAALgADCgkJCQAAAA==.',
Ya='Yamauba:BAAALgAECgQJBAAAAA==.',
Yn='Yn:BAAALgAFFAIJAwAAAA==.',
Zi='Zillara:BAABLgAECn8bAAIQAAkJaAZpDwAuAQAQAAkJaAZpDwAuAQAAAA==.',
['Zù']='Zùlfang:BAAALgAECgUJBQAAAA==.',
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
