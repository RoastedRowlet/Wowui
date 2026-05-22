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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warrior-Protection','Evoker-Devastation','Druid-Feral','Paladin-Holy','Druid-Restoration','Monk-Brewmaster','Mage-Frost','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Warlock-Destruction','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','Hunter-Marksmanship','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8bAAIBAAYJPyCqVQDhAQABAAYJPyCqVQDhAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzggpIgBgAQACAAkJzggpIgBgAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJBgADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn8ZAAIBAAgJ0wuAdAA5AQABAAgJ0wuAdAA5AQAAAA==.',
Aj='Ajaki:BAABLgAECn8ZAAQEAAcJZBcmGwClAQAEAAcJZBcmGwClAQAFAAQJvAXZQQCLAAACAAIJDAmnUgBeAAAAAA==.',
Al='Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJAwAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgQJCgAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgEJAQAAAA==.Anklebiter:BAAALgADCgIJAgAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECggJDgAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgMJAwAAAA==.Arlan:BAAALgAECggJDwAAAA==.Arlequin:BAABLgAECn8YAAMGAAgJVgkRhQDBAAAGAAcJLAkRhQDBAAAHAAIJUwpeTAAxAAAAAA==.Arnagan:BAAALgAECgIJAgAAAA==.',
As='Asharothh:BAABLgAECn8eAAIIAAkJ6ho9FgARAgAIAAkJ6ho9FgARAgAAAA==.Ashdem:BAAALgAECgYJCwAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAAALgAECgYJDQAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1gcXZQAvAAAFAAIJFgLLXgAjAAAAAA==.Azorahai:BAABLgAECn8hAAIJAAcJ1wcQjQABAQAJAAcJ1wcQjQABAQAAAA==.Azshalia:BAAALgAECgUJDAAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8dAAQKAAcJqQ9kCwAEAQALAAYJpA3vNQBgAQAKAAcJGg5kCwAEAQAMAAIJTA2PFwBpAAAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMHAAcJ6R3yCwAGAgAHAAcJ6R3yCwAGAgAGAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8eAAINAAgJPBKrOQCjAQANAAgJPBKrOQCjAQAAAA==.',
Be='Beffis:BAAALgADCgMJAwAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8tAAMOAAkJuiU3AABCAwAOAAkJmCU3AABCAwAPAAgJ7B2yFgBjAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgAQAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8ZAAIRAAgJqBxNEAAfAgARAAgJqBxNEAAfAgAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn8XAAISAAcJERmKLACsAQASAAcJERmKLACsAQAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAAALgAECgYJCAAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSLCBgAIAwABAAkJrSLCBgAIAwAAAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8IAAITAAUJfyC3CgAnAQATAAUJfyC3CgAnAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgAQAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bupropion:BAABLgAECn8aAAIGAAYJUBZ9WQApAQAGAAYJUBZ9WQApAQABLgAECgkJNQAUAMEfAA==.Bushwhacker:BAABLgAECn8YAAMQAAcJ0guCLgAMAQAQAAcJMQuCLgAMAQAVAAIJJQsIJwBlAAAAAA==.Butterbean:BAABLgAECn8tAAINAAkJByCPCgDAAgANAAkJByCPCgDAAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECgcJDgAAAA==.Catameringue:BAAALgAECgYJDAAAAA==.',
Ch='Chicxulub:BAAALgADCgcJDQAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMSAAkJKCBBCQDjAgASAAkJKCBBCQDjAgARAAYJCRGMNgAEAQAAAA==.',
Co='Coaca:BAABLgAECn8eAAMBAAgJhxvqKAAVAgABAAgJhxvqKAAVAgAWAAEJEQdmegAnAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAECggJHQAPAJ4cAA==.Confluent:BAABLgAECn81AAMXAAkJQyXVAADFAwAXAAkJQyXVAADFAwAQAAkJAxjyCgBZAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn8zAAIYAAkJ7hEfHACHAQAYAAkJ7hEfHACHAQAAAA==.',
Cu='Cursè:BAAALgADCgEJAQABLgAECgkJKwAZAEkIAA==.',
Cy='Cythrandir:BAAALgAECgYJCwABLgAFFAMJCwAZAA4VAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.Davdk:BAAALgAECgQJBAABLgAECgYJBwADAAAAAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECgYJCwAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Dethrahzen:BAABLgAECn8bAAMUAAcJQAI3EwCMAAAUAAcJQAI3EwCMAAAaAAEJWgElfAANAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8iAAIbAAgJ/BlqGADdAQAbAAgJ/BlqGADdAQAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgADCgYJCAAAAA==.',
Do='Dorelios:BAAALgADCgMJAwAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJFwAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAAALgAECgUJCQAAAA==.',
Du='Dubstep:BAAALgAECgIJAwAAAA==.Dugatotems:BAABLgAECn8dAAISAAkJPRjjGwA5AgASAAkJPRjjGwA5AgAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dunkle:BAABLgAECn8tAAMcAAkJhCDwAwCWAgAbAAkJihz8EwCuAgAcAAkJzhvwAwCWAgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8XAAINAAgJewdLVwBCAQANAAgJewdLVwBCAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEQAAAA==.',
Eb='Ebonise:BAAALgAECgQJCAAAAA==.',
Ed='Edrelang:BAAALgAECgcJDwAAAA==.',
Ee='Eerikki:BAAALgAECgQJCAAAAA==.',
Ei='Ein:BAABLgAECn8tAAIUAAkJ1Rg/AgBqAgAUAAkJ1Rg/AgBqAgAAAA==.',
El='Ellechero:BAAALgAECgQJDQAAAA==.Ellonia:BAAALgADCgYJCwABLgAECggJGQAdANMeAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Eragøn:BAAALgAECgYJDAAAAA==.Erinna:BAAALgAECgEJBAAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgQJCAAAAA==.Erosandra:BAAALgADCgIJAgABLgAECggJGgATANAIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAABLgAECn8XAAIJAAUJYxncfwAaAQAJAAUJYxncfwAaAQABLgAFFAQJCgAbAD0YAA==.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgADCgcJDwAAAA==.Furrystorm:BAAALgAECgEJAQAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIZAAkJlA7AQwDOAQAZAAkJlA7AQwDOAQAAAA==.',
Gh='Ghast:BAABLgAECn9AAAMPAAkJ4RSpJgAFAgAPAAkJghSpJgAFAgAOAAEJqx3tIgA/AAAAAA==.Ghats:BAAALgAECgcJDgAAAA==.',
Gi='Gigaflare:BAABLgAECn8nAAIZAAkJqAwMZQBzAQAZAAkJqAwMZQBzAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatknight:BAABLgAECn8mAAIJAAkJUyCbCgDiAgAJAAkJUyCbCgDiAgAAAA==.Gobblynn:BAAALgADCggJCwAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAxKlwD6AAABAAcJHAxKlwD6AAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn8lAAIPAAgJjQyUZQA1AQAPAAgJjQyUZQA1AQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJBAAAAA==.Greywings:BAABLgAECn8hAAIUAAcJhQ0GCgA4AQAUAAcJhQ0GCgA4AQAAAA==.Grimroxs:BAABLgAECn8cAAIMAAgJzwupCAB0AQAMAAgJzwupCAB0AQAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgADCgYJBgAAAA==.Grizzlemaw:BAAALgAECgQJBgAAAA==.',
Ha='Hacheros:BAAALgAECgEJAQAAAA==.Hairypits:BAAALgAECgQJCAABLgAECgkJJgAJAFMgAA==.Handerbug:BAABLgAECn8uAAMQAAkJRybAAQA+AwAQAAkJRybAAQA+AwAeAAYJtByHDQCcAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgAQAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgAQAEcmAA==.Hankit:BAAALgAECgMJAgAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJBwAAAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAAALgAECggJEwAAAA==.Heinrich:BAABLgAECn8lAAMBAAgJlCHnGQBoAgABAAgJlCHnGQBoAgAWAAQJPRG9VACHAAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.',
Ho='Hogglethorp:BAAALgAECggJDAAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCgkJEQAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAECgkJAwAAAA==.',
Il='Ilina:BAAALgAECgQJBAAAAA==.Illadron:BAAALgAECgYJCAAAAA==.Illecebra:BAAALgAECgYJDAAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAAALgAECgYJDQAAAA==.',
Ja='Jagerblunt:BAABLgAECn8iAAINAAgJShiQMADIAQANAAgJShiQMADIAQAAAA==.',
Jd='Jdbud:BAAALgAECgIJAgAAAA==.Jdpot:BAAALgAECgQJBgAAAA==.',
Je='Jenaaidy:BAAALgAECgUJDgAAAA==.',
Jh='Jhannae:BAAALgADCgEJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLQAIAPIhAA==.Joshery:BAABLgAECn8tAAMIAAkJ8iGLBQAJAwAIAAkJ8iGLBQAJAwAfAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJBwABLgAECgkJLQAIAPIhAA==.',
Ju='Judge:BAABLgAECn8hAAIBAAcJrA0hcwA8AQABAAcJrA0hcwA8AQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8fAAIgAAgJsh7KCAA8AgAgAAgJsh7KCAA8AgAAAA==.',
Ka='Katasaria:BAACLgAFFH8MAAMbAAQJ9RmWDABUAQAbAAQJ9RmWDABUAQAcAAEJxxQsIQBPAAAuAAQKfysAAxsACAmPIAgMAGICABsACAkTIAgMAGICABwABQk2Gm4cABsBAAAA.Kaycee:BAAALgADCgMJBAABLgAECgcJHQAKAKkPAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECgcJHQAKAKkPAA==.Kaycer:BAAALgADCggJDwABLgAECgcJHQAKAKkPAA==.',
Ke='Keeps:BAAALgADCgEJAQAAAA==.Kerl:BAAALgAECggJCgAAAA==.',
Ki='Kiboridi:BAAALgADCgMJAwAAAA==.Kimetshu:BAABLgAECn8cAAIHAAcJFBYlFwBkAQAHAAcJFBYlFwBkAQAAAA==.Kirana:BAABLgAECn8dAAIQAAgJeQVrNADsAAAQAAgJeQVrNADsAAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAIJAAgJQwttkABfAQAJAAgJQwttkABfAQAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIVAAkJqBtdAwCUAgAVAAkJqBtdAwCUAgAAAA==.Kravin:BAAALgAECgIJAgAAAA==.Krunzar:BAAALgAECgMJBQAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Laneywine:BAAALgAECgUJBQAAAA==.Larlifax:BAAALgAECgIJAgAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8vAAIbAAkJTyXVAABiAwAbAAkJTyXVAABiAwAAAA==.Levìstus:BAABLgAECn8eAAIJAAgJgRUEQgC2AQAJAAgJgRUEQgC2AQAAAA==.Leylaní:BAAALgAECggJEwAAAA==.Leyva:BAAALgAECgEJAQAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgEJAgAAAA==.Loroessan:BAAALgAECgUJCAAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAAALgAECgUJCwAAAA==.Lukas:BAAALgAECgIJAgABLgAECgkJQAAPAOEUAA==.Lunet:BAAALgADCgcJCAAAAA==.Lustie:BAAALgAECgYJEAABLgAECgkJNQAUAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAUAMEfAA==.Lytheum:BAABLgAECn81AAIUAAkJwR8NAQDPAgAUAAkJwR8NAQDPAgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQASACggAA==.Magerrac:BAAALgADCgQJBQABLgAECggJGgATANAIAA==.Malachar:BAABLgAECn8dAAITAAgJUgsnGAAsAQATAAgJUgsnGAAsAQAAAA==.Malboro:BAABLgAECn8iAAIPAAcJehJbVgBbAQAPAAcJehJbVgBbAQAAAA==.Maled:BAAALgAECgUJDgAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Meldin:BAAALgAECggJEwAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgQJBwAAAA==.Method:BAABLgAECn8rAAMhAAkJBxR5CwC3AQAhAAkJhxN5CwC3AQABAAIJFxOY5QB7AAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMWAAcJeh0zJwCDAQAWAAcJeh0zJwCDAQABAAEJJgFvWQEUAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIfAAkJ4xmOCQBjAgAfAAkJ4xmOCQBjAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8gAAMGAAgJDhYONwCeAQAGAAgJxRUONwCeAQAiAAEJeRgmKQBAAAAAAA==.Mineos:BAAALgAECgQJBQAAAA==.Mizoh:BAAALgAECgYJDwAAAA==.',
Mo='Moahuntress:BAAALgAECgQJBAAAAA==.Moonlyt:BAAALgADCgkJIAAAAA==.Morgaine:BAAALgADCgMJAwABLgAECggJGgATANAIAA==.Morn:BAABLgAECn8ZAAMUAAgJaBp+BwBzAgAUAAgJaBp+BwBzAgAaAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJQAAPAOEUAA==.',
Mt='Mtrain:BAAALgAECgMJBQABLgAECgcJDgADAAAAAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgADCgYJBgAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAAALgAECggJEwAAAA==.Nestiae:BAAALgAECgMJAwAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAECgkJAwADAAAAAA==.Nightsfuri:BAABLgAECn8bAAIQAAgJHhMjHACNAQAQAAgJHhMjHACNAQAAAA==.Nik:BAAALgAECgEJAQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8WAAINAAgJ3QxGRAB8AQANAAgJ3QxGRAB8AQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orialis:BAAALgADCgQJBAABLgADCgcJFwADAAAAAA==.Orlandbro:BAABLgAECn8nAAQjAAkJ3B3gBwBmAgANAAkJ4BdiGAB3AgAjAAkJxxzgBwBmAgAkAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAAALgAECggJEgAAAA==.Patchy:BAAALgADCgMJAwAAAA==.Pawradox:BAABLgAECn8dAAICAAkJmwwhGwCYAQACAAkJmwwhGwCYAQAAAA==.',
Pe='Peadar:BAAALgAECgIJAgAAAA==.',
Ph='Phenomenon:BAAALgAECgYJCQAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIgAAkJUh4IBgCCAgAgAAkJUh4IBgCCAgAAAA==.Pitviper:BAAALgAECgQJDgAAAA==.',
Pl='Plina:BAAALgAECggJEQAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAAALgAFFAIJAgAAAA==.',
Pu='Pulli:BAAALgAECggJDQAAAA==.',
Pv='Pve:BAABLgAECn8nAAIjAAkJ9h1uBgCDAgAjAAkJ9h1uBgCDAgAAAA==.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8eAAISAAkJdhMWIQDxAQASAAkJdhMWIQDxAQAAAA==.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIZAAcJcRR5ZgBwAQAZAAcJcRR5ZgBwAQAAAA==.Rathane:BAABLgAECn8bAAINAAgJsBkgIwAzAgANAAgJsBkgIwAzAgAAAA==.Ray:BAAALgAECgYJBgABLgAECggJGQAUAGgaAA==.',
Re='Realmclovin:BAAALgADCgQJBAAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8fAAIWAAgJrSZYAQCBAwAWAAgJrSZYAQCBAwAAAA==.',
Ri='Rizzwan:BAABLgAECn8dAAIjAAgJ2hylCgA1AgAjAAgJ2hylCgA1AgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMfAAMJYQmRFwDCAAAfAAMJYQmRFwDCAAAIAAIJ0AxAKQB0AAAuAAQKfyIABB8ACQmlHBAMADUCAB8ACAmvGxAMADUCAAgACAkVFGotADgBABgAAQmJDmBwADoAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAECgMJBAABLgAFFAQJDAAbAPUZAA==.Romy:BAAALgAECgUJDgAAAA==.',
Ru='Runecleaver:BAABLgAECn81AAMSAAkJBCKeCQDPAgASAAkJBCKeCQDPAgARAAQJExZZOQD4AAAAAA==.Ruw:BAABLgAECn8VAAIMAAcJWw0rCgBPAQAMAAcJWw0rCgBPAQAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8iAAIJAAkJBR9SDwC2AgAJAAkJBR9SDwC2AgAAAA==.Satania:BAABLgAECn8fAAIHAAkJGiTyBAAlAwAHAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8XAAMCAAgJEQ4XLgAVAQACAAYJ9A8XLgAVAQAEAAUJmQ3IOQDFAAAAAA==.',
Se='Segora:BAABLgAECn8aAAIPAAYJRAcGnwAbAQAPAAYJRAcGnwAbAQABLgAECggJJQAPAI0MAA==.Seimus:BAAALgAECgUJCQAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAAALgAECgUJCQAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAAALgAECgUJDAAAAA==.Sharius:BAABLgAECn8rAAIZAAkJSQgxXACJAQAZAAkJSQgxXACJAQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIZAAkJ6hJwZAAPAgAZAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJCQAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.Shutendoji:BAAALgAECgEJAQABLgAECggJHAAfAB0hAA==.',
Si='Sightlightx:BAAALgAECgcJDgAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8fAAIbAAgJ3QlNLgBIAQAbAAgJ3QlNLgBIAQAAAA==.Siryn:BAAALgAECgUJDQAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smashn:BAAALgAECgQJBAAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAECgYJDAADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAIlAAkJmBMLAgAXAgAlAAkJmBMLAgAXAgAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgADCgUJBwAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMXAAkJ/x3UEACxAgAXAAkJ/x3UEACxAgAQAAcJnhUvHwB0AQAAAA==.Syrden:BAAALgAECgEJAQABLgAECgkJFgAXAOgLAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCgYJCwAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJCAAAAA==.',
Th='Thandas:BAABLgAECn8lAAIBAAcJ9gj3hwAUAQABAAcJ9gj3hwAUAQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAgAAAA==.Thniper:BAABLgAECn8oAAMkAAkJTBhYCACsAQAkAAgJOxtYCACsAQAjAAUJ9wymJAAlAQAAAA==.Thouvan:BAAALgADCgEJAQAAAA==.Thugnastyy:BAAALgAECgIJBQABLgAECgkJAwADAAAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIWAAkJqxrCDQBuAgAWAAkJqxrCDQBuAgAAAA==.',
To='Tost:BAAALgADCgcJBwAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.',
Ty='Tyinviril:BAABLgAECn8+AAICAAkJECUfAQBaAwACAAkJECUfAQBaAwAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8PAAIBAAYJFw+uDQCNAQABAAYJFw+uDQCNAQAuAAQKfzIAAwEACAlIHkQpABQCAAEACAlIHkQpABQCABYABQk8CflgAPgAAAAA.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAAALgAECgcJEQAAAA==.Vonawesome:BAAALgAECgMJBQAAAA==.Vorpalblade:BAABLgAECn8uAAITAAkJMRelCQAQAgATAAkJMRelCQAQAgAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAAALgAFFAEJAQAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgADCgkJCQAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8vAAMmAAkJoB7RAACTAgAmAAkJoB7RAACTAgAZAAEJPBmiBwFEAAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIhAAkJfhKhCwC1AQAhAAkJfhKhCwC1AQAAAA==.Willowfox:BAAALgAECgMJCAAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJCgAAAA==.Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgAECgUJBgAAAA==.Wram:BAABLgAECn8aAAITAAgJ0AjSHQD2AAATAAgJ0AjSHQD2AAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECggJGgATANAIAA==.Wreckuiem:BAAALgAECgcJDgAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8ZAAMdAAgJ0x5DAwAcAgAdAAgJ8h1DAwAcAgAPAAIJLRbzvgB+AAAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAACLgAFFH8GAAIGAAMJrxHePQDjAAAGAAMJrxHePQDjAAAuAAQKfyMAAgYACQmvHX4MAKYCAAYACQmvHX4MAKYCAAAA.',
Zi='Zillara:BAAALgAECgcJEAAAAA==.',
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
