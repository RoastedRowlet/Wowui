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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Mistweaver','Warrior-Protection','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Warrior-Fury','Shaman-Restoration','Hunter-Marksmanship','Evoker-Devastation','Druid-Restoration','Mage-Frost','Monk-Brewmaster','Evoker-Augmentation','DeathKnight-Blood','Warrior-Arms','Druid-Guardian','Warlock-Destruction','Monk-Windwalker','Druid-Feral','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Frost','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abráms:BAAALgAECgEJAQAAAA==.',
Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8jAAIBAAkJBRz8SwDiAQABAAkJBRz8SwDiAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzggVNABIAQACAAkJzggVNABIAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn80AAIBAAkJvg44gwBpAQABAAkJvg44gwBpAQAAAA==.',
Aj='Ajaki:BAABLgAECn8qAAQEAAgJlBUHAgDOAAAFAAcJmAbZQwD5AAAEAAgJlBUHAgDOAAACAAMJUAzyYQCSAAAAAA==.',
Al='Allandra:BAAALgAECgYJBgAAAA==.Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJBAAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgYJEgAAAA==.Amelandra:BAAALgAECgEJAQAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgIJAgAAAA==.Anklebiter:BAAALgAECgEJAwAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgcJDwAAAA==.Arlan:BAABLgAECn8fAAIGAAkJdR7dDgCoAgAGAAkJdR7dDgCoAgAAAA==.Arlequin:BAABLgAECn8ZAAMHAAkJjgnTqwDOAAAHAAcJMAnTqwDOAAAIAAMJqAqAVQBlAAAAAA==.Arnagan:BAAALgAECgUJBQAAAA==.',
As='Asale:BAAALgAECgEJAQAAAA==.Ascend:BAAALgAECgYJCAABLgAFFAMJAwADAAAAAA==.Asharothh:BAABLgAECn8mAAIJAAkJYxtYFwBeAgAJAAkJYxtYFwBeAgAAAA==.Ashdem:BAABLgAECn8ZAAIHAAcJNw7sgwAYAQAHAAcJNw7sgwAYAQAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAABLgAECn8YAAIKAAkJlhF8FACqAQAKAAkJlhF8FACqAQAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1geyjQAtAAAFAAIJFgLpiQAfAAAAAA==.Azkar:BAAALgADCgEJAQAAAA==.Azorahai:BAABLgAECn8xAAILAAgJmwxcdgB3AQALAAgJmwxcdgB3AQAAAA==.Azshalia:BAABLgAECn8hAAIKAAgJFwt6IgAcAQAKAAgJFwt6IgAcAQAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8nAAQMAAgJURCeCgB2AQAMAAgJMA+eCgB2AQANAAYJpA3vNQBgAQAOAAcJkQxLDgBAAQABLgAECgcJCwADAAAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMIAAcJ6R0CFQDnAQAIAAcJ6R0CFQDnAQAHAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8wAAIPAAkJOxUNLgAkAgAPAAkJOxUNLgAkAgAAAA==.',
Be='Beffis:BAAALgAECgMJAwAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8vAAMQAAkJuiWnAAAuAwAQAAkJmCWnAAAuAwARAAgJ7B3MJgBCAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Blitzkriêg:BAAALgAECgIJAQAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgASAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8tAAITAAkJ3R1HDgCIAgATAAkJ3R1HDgCIAgAAAA==.Boblin:BAABLgAECn8oAAIUAAcJZBAaAQBOAQAUAAcJZBAaAQBOAQAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn81AAIVAAkJGSBUBwA7AwAVAAkJGSBUBwA7AwAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAABLgAECn8dAAMPAAcJ9QK4zwCqAAAPAAYJswK4zwCqAAAWAAcJpgL/AQBDAAAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSI+EADkAgABAAkJrSI+EADkAgAAAA==.Bosshogshift:BAAALgAECgYJBgABLgAECgkJNAABAK0iAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8JAAIKAAUJziAkBgAIAQAKAAUJziAkBgAIAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgASAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bulgear:BAAALgAECgMJBgAAAA==.Bupropion:BAABLgAECn8eAAIHAAYJAhl7YQBmAQAHAAYJAhl7YQBmAQABLgAECgkJNQAXAMEfAA==.Bushwhacker:BAAALgAECgYJBgAAAA==.Butterbean:BAABLgAECn8tAAIPAAkJCCB3CwDnAgAPAAkJCCB3CwDnAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECggJEQAAAA==.Catameringue:BAABLgAECn8WAAIYAAcJBBHsRAB9AQAYAAcJBBHsRAB9AQAAAA==.',
Ch='Chickenhawk:BAAALgAECgEJAQAAAA==.Chicxulub:BAABLgAECn8cAAIZAAkJ+RO7XwDBAQAZAAkJ+RO7XwDBAQAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMVAAkJKCBBCQDjAgAVAAkJKCBBCQDjAgATAAYJCRELUAD3AAAAAA==.Clickshoot:BAAALgAECgYJCwAAAA==.',
Co='Coaca:BAABLgAECn8yAAMBAAkJ6x0XIgB+AgABAAkJ6x0XIgB+AgAGAAEJEQf8mQAmAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAFFAMJCQARABAbAA==.Confluent:BAABLgAECn81AAMYAAkJQyW7AQC+AwAYAAkJQyW7AQC+AwASAAkJAhgfEgBHAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn83AAIaAAkJ7xLzIwCLAQAaAAkJ7xLzIwCLAQAAAA==.',
Cu='Cursè:BAAALgADCgIJAgABLgAECgkJKwAZAEkIAA==.',
Cy='Cythrandir:BAAALgAECgYJDAABLgAFFAUJEwAZAP8RAA==.',
Da='Dalkith:BAAALgAECgEJAQABLgAECggJEwADAAAAAA==.Daniellena:BAAALgADCgkJGAAAAA==.Davwr:BAAALgAECgMJAwABLgAECggJFgALAIgUAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECgkJEwAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Demoloro:BAAALgAECgEJAQAAAA==.Dethrahzen:BAABLgAECn87AAMXAAgJnwepAACfAAAXAAgJnwepAACfAAAbAAIJhwGXnQAjAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8tAAIUAAkJpRouGAAtAgAUAAkJpRouGAAtAgAAAA==.',
Dj='Djcamsoda:BAAALgAECgEJAgAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAABLgAECn8UAAIcAAgJbQnzKQAIAQAcAAgJbQnzKQAIAQAAAA==.',
Do='Doomslayer:BAAALgADCgkJDwAAAA==.Dorelios:BAAALgADCgQJBAAAAA==.Dotsfordayz:BAAALgAECgMJBAABLgAECgMJBQADAAAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJGAAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAABLgAECn8WAAMPAAYJbQW3tQDZAAAPAAYJbQW3tQDZAAAWAAMJGwAFnAAOAAAAAA==.',
Du='Dubstep:BAAALgAECgYJEQAAAA==.Dugatotems:BAABLgAECn80AAMVAAkJPxrjGwA5AgAVAAkJPxrjGwA5AgATAAkJ5QjwPABCAQAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dumpytruck:BAAALgAECgQJBQAAAA==.Dunkle:BAABLgAECn8tAAMdAAkJgyD8BwB2AgAUAAkJihz8EwCuAgAdAAkJzBv8BwB2AgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8pAAIPAAkJkwskUACyAQAPAAkJkwskUACyAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEgAAAA==.',
Eb='Ebonise:BAAALgAECgUJDwAAAA==.',
Ed='Edrelang:BAABLgAECn8fAAMUAAcJ3QnkSgAaAQAUAAcJ3QnkSgAaAQAdAAIJrQSVcgA8AAAAAA==.',
Ee='Eerikki:BAAALgAECgYJEQAAAA==.',
Ei='Eightsix:BAAALgAFFAIJAwABLgAFFAMJAwADAAAAAA==.Ein:BAABLgAECn82AAIXAAkJXRrqAgB+AgAXAAkJXRrqAgB+AgAAAA==.',
El='Ellechero:BAABLgAECn8kAAMeAAgJQAgpOQDBAAASAAcJKQXuUQDGAAAeAAcJfQcpOQDBAAAAAA==.Ellonia:BAAALgAECgMJAwABLgAECggJIAAfAO4eAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.Elsmerelda:BAAALgADCgUJBQAAAA==.',
Er='Eragøn:BAABLgAECn8WAAIPAAcJrBolQwDZAQAPAAcJrBolQwDZAQAAAA==.Erinna:BAAALgAECgEJBQAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgcJEQAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgkJHwAKANAIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.Fextrius:BAAALgAECgYJCgAAAA==.',
Fl='Florassa:BAAALgADCgUJBQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAACLgAFFH8HAAILAAMJFA7SqQDKAAALAAMJFA7SqQDKAAAuAAQKfyEAAgsABgnTFiqNAEsBAAsABgnTFiqNAEsBAAEuAAUUBAkSABQA8B0A.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgAECgQJBAAAAA==.Furrystorm:BAAALgAFFAEJAgAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIZAAkJlA6aYwC3AQAZAAkJlA6aYwC3AQAAAA==.Garroc:BAAALgAECgYJBgAAAA==.',
Gh='Ghast:BAABLgAECn9nAAMRAAkJ/xqfJQBHAgARAAkJ7RefJQBHAgAQAAcJ8BJXDACXAQAAAA==.Ghats:BAABLgAECn8aAAQRAAgJnRjjNwD6AQARAAgJnRjjNwD6AQAQAAIJFRiPNgBKAAAfAAIJHBScOwA8AAABLgAFFAMJAwADAAAAAA==.',
Gi='Giddley:BAAALgAECgEJAQAAAA==.Gigaflare:BAABLgAECn8nAAIZAAkJqAwkgwDLAQAZAAkJqAwkgwDLAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnev:BAAALgADCgYJBgAAAA==.Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatale:BAAALgAECgYJCwABLgAECgkJLAALAFQgAA==.Goatknight:BAABLgAECn8sAAILAAkJVCCEEwDTAgALAAkJVCCEEwDTAgAAAA==.Goatwings:BAAALgAECgIJAgAAAA==.Goatwizard:BAAALgAECgMJAwAAAA==.Gobblynn:BAAALgADCggJEAAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAxH4ADeAAABAAcJHAxH4ADeAAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn9GAAIRAAkJbhBJAgAHAQARAAkJbhBJAgAHAQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJCAAAAA==.Greywings:BAABLgAECn83AAIXAAkJrQ1PCQCWAQAXAAkJrQ1PCQCWAQAAAA==.Grimroxs:BAABLgAECn84AAMOAAkJ5BB+BwDgAQAOAAkJ+w9+BwDgAQANAAMJAwtiAgCIAAAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgAECgQJBwABLgAECgMJBQADAAAAAA==.Grizzlemaw:BAAALgAECgcJDAAAAA==.',
Ha='Hacheros:BAAALgAECgIJAgAAAA==.Hadic:BAAALgADCgEJAQABLgAECgkJCQADAAAAAA==.Hairypits:BAAALgAECgYJDQABLgAECgkJLAALAFQgAA==.Handerbug:BAABLgAECn8uAAMSAAkJRyb0AgCFAwASAAkJRyb0AgCFAwAeAAYJtByqFwCUAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgASAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgASAEcmAA==.Handybug:BAAALgAECgEJAQABLgAECgkJLgASAEcmAA==.Hankit:BAAALgAECgQJBQAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJCgAAAA==.Hazmati:BAAALgADCgkJCQABLgAFFAQJDAAgAKYHAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Healtaxi:BAAALgAECgMJBQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAABLgAECn8hAAIEAAkJIwsKLQBjAQAEAAkJIwsKLQBjAQAAAA==.Heinrich:BAABLgAECn8vAAMBAAgJ8iMeFwC4AgABAAgJ8iMeFwC4AgAGAAQJPRFAbADJAAAAAA==.Heira:BAAALgADCgQJCAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.Hippypedro:BAAALgAECgYJEQABLgAFFAYJHgAIAJUdAA==.',
Ho='Hogglethorp:BAAALgAECggJEwAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCgkJGgAAAA==.Holyloro:BAAALgADCgIJAgAAAA==.Horns:BAAALgAECgUJBQAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAFFAIJBAAAAA==.',
Il='Ilina:BAAALgAECgUJDQABLgAFFAIJAgADAAAAAA==.Illadron:BAAALgAFFAEJAgAAAA==.Illecebra:BAAALgAFFAEJAQAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAABLgAECn8cAAMSAAgJSAp0OQAtAQASAAgJSAp0OQAtAQAYAAMJUgxKnQB2AAAAAA==.',
Ja='Jagerblunt:BAACLgAFFH8KAAIPAAQJtxcZMwBIAQAPAAQJtxcZMwBIAQAuAAQKfyQAAg8ACQmoGWgyABICAA8ACQmoGWgyABICAAAA.',
Jd='Jdbud:BAAALgAECgQJBgAAAA==.Jdpot:BAAALgAECgYJEAAAAA==.',
Je='Jenaaidy:BAABLgAECn8uAAICAAgJBxbgHgDOAQACAAgJBxbgHgDOAQAAAA==.',
Jh='Jhannae:BAAALgADCgEJAgAAAA==.',
Ji='Jiks:BAAALgAECgIJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLgAJAPIhAA==.Joshery:BAABLgAECn8uAAMJAAkJ8iGLBQAJAwAJAAkJ8iGLBQAJAwAgAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJCQABLgAECgkJLgAJAPIhAA==.',
Ju='Judge:BAABLgAECn8sAAIBAAkJ6BJdTgDcAQABAAkJ6BJdTgDcAQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8zAAIcAAkJtCFbBADvAgAcAAkJtCFbBADvAgAAAA==.',
Ka='Katasaria:BAACLgAFFH8VAAMUAAUJFCDHEwBsAQAUAAUJFCDHEwBsAQAdAAEJxxRZQABJAAAuAAQKfysAAxQACAmNIG4UAKoCABQACAkXIG4UAKoCAB0ABQk0GpQsABgBAAAA.Kaycee:BAAALgADCgUJCAABLgAECgcJCwADAAAAAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECgcJCwADAAAAAA==.Kaycer:BAAALgADCggJDwABLgAECgcJCwADAAAAAA==.',
Ke='Keeps:BAAALgAECgEJAQAAAA==.Kerl:BAAALgAECggJEQABLgAECgkJCQADAAAAAA==.',
Ki='Kiboridi:BAAALgAECgQJBQAAAA==.Killerxx:BAAALgAECgEJAQABLgAECgcJHwAUAN0JAA==.Kimetshu:BAABLgAECn8gAAIIAAgJaBQUHgCLAQAIAAgJaBQUHgCLAQAAAA==.Kirana:BAABLgAECn8vAAMSAAkJfQaHPgAVAQASAAkJfQaHPgAVAQAYAAUJRASumACBAAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAILAAgJRAttkABfAQALAAgJRAttkABfAQAAAA==.',
Ko='Kolaro:BAAALgAECgEJAgAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIhAAkJqBtuBgCAAgAhAAkJqBtuBgCAAgAAAA==.Kravin:BAAALgAECgQJCwAAAA==.Krunzar:BAAALgAECgUJBwAAAA==.',
Kt='Ktheir:BAAALgAECgMJAwAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Lammasthan:BAAALgAECgkJCQAAAA==.Laneywine:BAAALgAECgYJDgAAAA==.Larlifax:BAAALgAECgUJBwAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAACLgAFFH8FAAIUAAIJhhohBQChAAAUAAIJhhohBQChAAAuAAQKfzMAAhQACQlxJWoCAE0DABQACQlxJWoCAE0DAAAA.Levìstus:BAABLgAECn8tAAILAAkJTRm2LQBJAgALAAkJTRm2LQBJAgAAAA==.Leylaní:BAABLgAECn8jAAIPAAkJrRTAMAAZAgAPAAkJrRTAMAAZAgAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgUJBwAAAA==.Loosecaboose:BAAALgAECgEJAQAAAA==.Loroessan:BAAALgAECgkJDwAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAABLgAECn8VAAIBAAcJCxA6kwBMAQABAAcJCxA6kwBMAQAAAA==.Lukas:BAAALgAECgcJCQABLgAECgkJZwARAP8aAA==.Lunet:BAAALgAECgcJBwAAAA==.Lustie:BAAALgAECgYJEwABLgAECgkJNQAXAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAXAMEfAA==.Lytheum:BAABLgAECn81AAIXAAkJwR8rAgCsAgAXAAkJwR8rAgCsAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
['Lü']='Lücid:BAAALgAECgEJAgAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQAVACggAA==.Magerrac:BAAALgAECgEJAQABLgAECgkJHwAKANAIAA==.Magikon:BAAALgAECgEJAQAAAA==.Magista:BAAALgAECgIJAgAAAA==.Malachar:BAABLgAECn8xAAIKAAkJIA1HGAB9AQAKAAkJIA1HGAB9AQAAAA==.Malboro:BAABLgAECn8rAAIRAAgJ7BJAWwCMAQARAAgJ7BJAWwCMAQAAAA==.Maled:BAABLgAECn8tAAQQAAgJih42CADnAQAQAAcJXhw2CADnAQAfAAMJzBzIFgDuAAARAAMJohBP3wCcAAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrew:BAAALgAECgkJBwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Mej:BAAALgAECgQJBAAAAA==.Meldin:BAABLgAECn8jAAIPAAkJZCDnDwDRAgAPAAkJZCDnDwDRAgAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgUJCQAAAA==.Method:BAABLgAECn8rAAMiAAkJBxT7EQCmAQAiAAkJhxP7EQCmAQABAAIJFxNOPAFwAAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMGAAcJdh2UJQDbAQAGAAcJdh2UJQDbAQABAAEJJgEw1AERAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIgAAkJ5Bl2EABGAgAgAAkJ5Bl2EABGAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8nAAMHAAgJGBbDSgCmAQAHAAgJzxXDSgCmAQAjAAEJeRgmKQBAAAAAAA==.Mineos:BAABLgAECn8XAAIUAAcJvAs/RwApAQAUAAcJvAs/RwApAQAAAA==.Minipedro:BAAALgAECgEJAQABLgAFFAYJHgAIAJUdAA==.Mistrmiso:BAAALgAECgMJAgABLgAECgkJLwAQALolAA==.Mizoh:BAAALgAECgYJEAAAAA==.',
Mo='Moahuntress:BAAALgAECgYJCQAAAA==.Mookie:BAAALgAECgMJAwAAAA==.Moonlyt:BAAALgADCgkJIQAAAA==.Morgaine:BAAALgADCggJCwABLgAECgkJHwAKANAIAA==.Morn:BAABLgAECn8bAAMXAAkJNRt+BwBzAgAXAAkJNRt+BwBzAgAbAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJZwARAP8aAA==.',
Mt='Mtrain:BAAALgAECgYJCgABLgAFFAMJAwADAAAAAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myori:BAAALgAECgMJAwAAAA==.Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgAECgYJCAAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAABLgAECn8jAAIcAAkJSReKEAADAgAcAAkJSReKEAADAgAAAA==.Neeryn:BAAALgAECgIJAgAAAA==.Nestiae:BAAALgAECgMJAwABLgAECgYJCQADAAAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAFFAIJBAADAAAAAA==.Nightsfuri:BAABLgAECn8bAAISAAgJHxNdKQCIAQASAAgJHxNdKQCIAQAAAA==.Nik:BAAALgAECgQJBQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8hAAIPAAkJKgyWUgCrAQAPAAkJKgyWUgCrAQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orlandbro:BAABLgAECn8nAAQPAAkJ2x1iGAB3AgAkAAkJxhy4BQCyAgAPAAkJ4BdiGAB3AgAWAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAABLgAECn8bAAMLAAkJUg8kcwB9AQALAAkJzQ0kcwB9AQAcAAQJpg+4NADFAAAAAA==.Patchy:BAAALgAECgQJBAAAAA==.Pawradox:BAABLgAECn8kAAICAAkJ8ww1KgCAAQACAAkJ8ww1KgCAAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAwAAAA==.',
Ph='Phenomenon:BAABLgAECn8aAAIPAAcJ1iAQJwBEAgAPAAcJ1iAQJwBEAgAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIcAAkJUh7iBwCpAgAcAAkJUh7iBwCpAgAAAA==.Pitviper:BAABLgAECn8UAAIlAAYJBxm7FAA1AQAlAAYJBxm7FAA1AQAAAA==.',
Pl='Plina:BAABLgAECn8hAAIBAAkJGhcnPgANAgABAAkJGhcnPgANAgAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponglenis:BAAALgAFFAIJAgABLgAFFAIJBAADAAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAABLgAFFH8KAAIVAAQJCBP6NwACAQAVAAQJCBP6NwACAQAAAA==.',
Pu='Pulli:BAAALgAECgkJEQAAAA==.',
Pv='Pve:BAACLgAFFH8FAAIkAAUJBwVtHwDbAAAkAAUJBwVtHwDbAAAuAAQKfy8AAiQACQn0H+IGALECACQACQn0H+IGALECAAAA.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAACLgAFFH8HAAIVAAMJ7QhbBwCPAAAVAAMJ7QhbBwCPAAAuAAQKfyMAAhUACQmCFesBADQBABUACQmCFesBADQBAAAA.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIZAAcJcRTEjwBYAQAZAAcJcRTEjwBYAQAAAA==.Rathane:BAACLgAFFH8FAAIPAAQJtQqrUgAEAQAPAAQJtQqrUgAEAQAuAAQKfyMAAg8ACQkCGvYBAJEBAA8ACQkCGvYBAJEBAAAA.Rawrmuch:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.Ray:BAAALgAECgYJBgABLgAECgkJGwAXADUbAA==.',
Re='Realmclovin:BAAALgAECgUJBQAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Redrabbit:BAAALgAECgYJBwAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8uAAIGAAkJjiYqAAD0AwAGAAkJjiYqAAD0AwAAAA==.',
Ri='Rizmund:BAAALgAECgEJAQAAAA==.Rizzwan:BAABLgAECn8rAAIkAAkJnyCFBADlAgAkAAkJnyCFBADlAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMgAAMJYQnCKgClAAAgAAMJYQnCKgClAAAJAAIJ0AxpUQBiAAAuAAQKfykABAkACQmMHZUQAJ4CAAkACAmXHJUQAJ4CACAACAmwG2ETACICABoAAQmJDjWPADQAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAFFAEJAQABLgAFFAUJFQAUABQgAA==.Romy:BAABLgAECn8sAAIZAAgJhQI54gDXAAAZAAgJhQI54gDXAAAAAA==.Roonoe:BAAALgAECgMJAwAAAA==.',
Ru='Runecleaver:BAABLgAECn87AAMVAAkJBCKdEQDBAgAVAAkJBCKdEQDBAgATAAQJExYYUwDtAAAAAA==.Ruw:BAABLgAECn8rAAMOAAkJchFzCADEAQAOAAgJGhNzCADEAQANAAQJKgg4QQDAAAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8lAAILAAkJ7h9HFwC7AgALAAkJ7h9HFwC7AgAAAA==.Satania:BAABLgAECn8fAAIIAAkJGiTyBAAlAwAIAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8rAAMEAAkJ1RO6FQAmAgAEAAkJ1RO6FQAmAgACAAcJjxOYLABxAQAAAA==.',
Se='Segora:BAABLgAECn8aAAIRAAYJRAcGnwAbAQARAAYJRAcGnwAbAQABLgAECgkJRgARAG4QAA==.Seimus:BAABLgAECn8UAAIZAAUJcRE31wDnAAAZAAUJcRE31wDnAAAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAABLgAECn8UAAIBAAYJFBHatAAYAQABAAYJFBHatAAYAQAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAABLgAECn8iAAISAAgJIAh9QgADAQASAAgJIAh9QgADAQAAAA==.Sharius:BAABLgAECn8rAAIZAAkJSQhJgQB1AQAZAAkJSQhJgQB1AQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIZAAkJ6hJwZAAPAgAZAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJDgAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.Shutendoji:BAAALgAECgEJAgABLgAECggJHQAgAKohAA==.',
Si='Sightlightx:BAABLgAECn8UAAMgAAkJNhEkOQAdAQAgAAcJ9w0kOQAdAQAJAAYJDRYVWwAIAQAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8xAAIUAAkJvgrBMgCAAQAUAAkJvgrBMgCAAQAAAA==.Sinkingbridg:BAAALgAECgIJAgAAAA==.Siryn:BAABLgAECn8hAAMGAAgJQANPWgDNAAAGAAgJQANPWgDNAAABAAEJKQMlFgAhAAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smallest:BAAALgAECgcJCwAAAA==.Smashn:BAABLgAECn8cAAMlAAcJ7xOfEABsAQAlAAcJQxKfEABsAQALAAYJmwuQxwD0AAAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.Snakeshadow:BAAALgAECgkJCQAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAFFAEJAQADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAImAAkJmBOJAwDlAQAmAAkJmBOJAwDlAQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgAECgEJAQAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.Susa:BAAALgADCgEJAQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMYAAkJAB7UEACxAgAYAAkJAB7UEACxAgASAAcJnhXwLQBrAQAAAA==.Syrden:BAAALgAECgYJCAAAAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCggJDQAAAA==.Tanholy:BAAALgAECgUJBAAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJCgAAAA==.Tessarion:BAAALgAECgkJCQAAAA==.',
Th='Thandas:BAABLgAECn89AAIBAAgJXhXOAgAqAQABAAgJXhXOAgAqAQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAwAAAA==.Thniper:BAABLgAECn8oAAMWAAkJURgyGABrAgAWAAgJQBsyGABrAgAkAAUJ9wyEMQAgAQAAAA==.Thoriumaster:BAAALgAECgQJBQAAAA==.Thouvan:BAAALgAECgEJAQAAAA==.Thugnastyy:BAAALgAFFAIJBAABLgAFFAIJBAADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIGAAkJqxpvFgBYAgAGAAkJqxpvFgBYAgAAAA==.',
To='Tost:BAAALgAECgEJAQABLgAECgIJAQADAAAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.Tusker:BAAALgAECgUJBQAAAA==.',
Ty='Tyinviril:BAACLgAFFH8JAAICAAQJ0B6KEABnAQACAAQJ0B6KEABnAQAuAAQKf1EAAgIACQnWJZUBAGIDAAIACQnWJZUBAGIDAAAA.',
Un='Unter:BAAALgAECgEJAQAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8YAAMBAAcJTA/JGACqAQABAAcJTA/JGACqAQAGAAEJRgFZSAA7AAAuAAQKf0AAAwEACAlcIREgAIgCAAEACAlcIREgAIgCAAYABQk8CflgAPgAAAAA.Verna:BAAALgADCgIJAgAAAA==.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAABLgAECn8SAAIHAAcJDwtFiAAQAQAHAAcJDwtFiAAQAQAAAA==.Vonawesome:BAAALgAECgQJCAAAAA==.Vorpalblade:BAABLgAECn8uAAIKAAkJMRcpEADkAQAKAAkJMRcpEADkAQAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAABLgAFFH8HAAILAAMJLQg4twC5AAALAAMJLQg4twC5AAAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgAECgQJBAAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8xAAMnAAkJCx8HAQDOAgAnAAkJCx8HAQDOAgAZAAEJPBnsSwE/AAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIiAAkJfhIeEgCkAQAiAAkJfhIeEgCkAQAAAA==.Willowfox:BAAALgAECgMJCwAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJDAAAAA==.Wobblingwar:BAAALgAECgMJAwAAAA==.',
Wr='Wrahis:BAAALgAECgUJCAAAAA==.Wram:BAABLgAECn8fAAMKAAkJ0AgiIgAfAQAKAAkJ0AgiIgAfAQAUAAIJJAEfuQAZAAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECgkJHwAKANAIAA==.Wreckuiem:BAAALgAECggJEwAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8gAAMfAAgJ7h4XBgAEAgAfAAgJ8x0XBgAEAgARAAYJ8RiaTAC1AQAAAA==.',
Xe='Xenophilious:BAAALgAECgIJAgAAAA==.',
Xi='Xiøn:BAACLgAFFH8TAAIHAAUJOhriOwA2AQAHAAUJOhriOwA2AQAuAAQKfysAAgcACQm5HloRALcCAAcACQm5HloRALcCAAAA.',
Xr='Xristinà:BAAALgADCgkJCQAAAA==.',
Ya='Yamauba:BAAALgAECgMJAwAAAA==.',
Yn='Yn:BAAALgAFFAIJAwAAAA==.',
Zi='Zillara:BAABLgAECn8bAAIOAAkJaAZoDwAuAQAOAAkJaAZoDwAuAQAAAA==.',
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
