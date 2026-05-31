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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Monk-Mistweaver','Warrior-Protection','DeathKnight-Unholy','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warlock-Affliction','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Evoker-Devastation','Druid-Feral','Druid-Restoration','Monk-Brewmaster','Mage-Frost','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Druid-Guardian','Warlock-Destruction','Monk-Windwalker','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Frost','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acast:BAAALgAECgEJAgAAAA==.Acurd:BAABLgAECn8iAAIBAAgJMRxnYACWAQABAAgJMRxnYACWAQAAAA==.',
Ad='Adaila:BAABLgAECn8sAAICAAkJzgjeLgBEAQACAAkJzgjeLgBEAQAAAA==.Adelassaria:BAAALgADCgMJAwAAAA==.Admire:BAAALgAECgMJAwAAAA==.Adresh:BAAALgAECgMJAwABLgAECgUJCAADAAAAAA==.',
Ai='Aicianklip:BAAALgAECgQJCAAAAA==.Aiir:BAABLgAECn8oAAIBAAgJPA7cegBeAQABAAgJPA7cegBeAQAAAA==.',
Aj='Ajaki:BAABLgAECn8iAAQEAAcJ6xdCIQCjAQAEAAcJ6xdCIQCjAQAFAAYJJwffQgDRAAACAAIJDAnXZABbAAAAAA==.',
Al='Allaria:BAAALgAECgQJBAAAAA==.Almondor:BAAALgAECgIJAwAAAA==.Alwayspala:BAAALgAECggJEgAAAA==.',
Am='Amaterasu:BAAALgADCgIJAgAAAA==.Ambridgerose:BAAALgAECgYJEAAAAA==.Amplify:BAAALgAECgIJAgAAAA==.',
An='Andam:BAAALgAECgIJAgAAAA==.Anklebiter:BAAALgADCgIJAgAAAA==.Antiwend:BAAALgADCgIJAwAAAA==.',
Ao='Aoleyn:BAAALgADCgMJAwAAAA==.',
Ap='Aphaea:BAAALgAECggJDwAAAA==.Apokolips:BAAALgAECgYJBgAAAA==.Appolyin:BAAALgAECgEJAQAAAA==.',
Ar='Arieyana:BAAALgADCgYJDQAAAA==.Arlaf:BAAALgAECgcJCwAAAA==.Arlan:BAABLgAECn8dAAIGAAgJhB6vFABSAgAGAAgJhB6vFABSAgAAAA==.Arlequin:BAABLgAECn8ZAAMHAAkJjgkbnwDFAAAHAAcJMAkbnwDFAAAIAAMJqAq2SQBnAAAAAA==.Arnagan:BAAALgAECgUJBQAAAA==.',
As='Asale:BAAALgAECgEJAQAAAA==.Ascend:BAAALgAECgYJCAABLgAECggJFQAJAJ0YAA==.Asharothh:BAABLgAECn8mAAIKAAkJYxucEwBeAgAKAAkJYxucEwBeAgAAAA==.Ashdem:BAABLgAECn8VAAIHAAcJtg1AegAQAQAHAAcJtg1AegAQAQAAAA==.Ashmag:BAAALgADCgYJBgAAAA==.Ashmonk:BAAALgADCgYJCAAAAA==.',
At='Athenâ:BAABLgAECn8UAAILAAgJ1RIGFgB/AQALAAgJ1RIGFgB/AQAAAA==.',
Av='Avari:BAAALgAECgQJBAABLgAECgcJFAABABwMAA==.',
Az='Azariel:BAABLgAECn8uAAQEAAkJXw83KgChAQAEAAkJXw83KgChAQACAAEJ1gcQfAAuAAAFAAIJFgLLXgAjAAAAAA==.Azkar:BAAALgADCgEJAQAAAA==.Azorahai:BAABLgAECn8mAAIMAAcJ1wdNqQAIAQAMAAcJ1wdNqQAIAQAAAA==.Azshalia:BAAALgAECgcJEwAAAA==.Azuldrac:BAAALgADCgYJBQAAAA==.',
Ba='Backstabitha:BAABLgAECn8mAAQNAAgJjg/FCQB1AQANAAgJaw7FCQB1AQAOAAYJpA3vNQBgAQAPAAcJjQz0DABHAQAAAA==.Baelos:BAAALgAECgQJBAAAAA==.Baishu:BAABLgAECn8eAAMIAAcJ6R29EQDwAQAIAAcJ6R29EQDwAQAHAAYJkwhBkQD9AAAAAA==.Banilibug:BAABLgAECn8nAAIQAAgJtBUBPQDVAQAQAAgJtBUBPQDVAQAAAA==.',
Be='Beffis:BAAALgAECgMJAwAAAA==.Benimaru:BAAALgAECgEJAwAAAA==.Beorngoat:BAAALgADCgYJBgAAAA==.Besaggy:BAAALgADCgYJBgAAAA==.',
Bi='Biali:BAAALgADCgkJCQAAAA==.Biwwie:BAAALgAECggJEAAAAA==.',
Bl='Blackout:BAABLgAECn8vAAMRAAkJuiVuAAA7AwARAAkJmCVuAAA7AwAJAAgJ7B1YIQBQAgAAAA==.Bleekz:BAAALgADCgMJAwAAAA==.Bluecleric:BAAALgADCgIJAgAAAA==.Bluerabbit:BAAALgADCgEJAQABLgAECgkJLgASAEcmAA==.',
Bo='Bobbybrady:BAABLgAECn8iAAITAAgJgB1FFAAwAgATAAgJgB1FFAAwAgAAAA==.Boblin:BAAALgAECgIJAgAAAA==.Bofi:BAAALgADCggJCAAAAA==.Boggnarley:BAABLgAECn8nAAIUAAgJ1R5lEwCYAgAUAAgJ1R5lEwCYAgAAAA==.Bokni:BAAALgADCgcJBwAAAA==.Boombayah:BAAALgAECgYJEwAAAA==.Bosshog:BAABLgAECn80AAIBAAkJrSK0DADqAgABAAkJrSK0DADqAgAAAA==.Bosshogshift:BAAALgAECgYJBgABLgAECgkJNAABAK0iAA==.',
Br='Brayk:BAAALgADCgUJDgAAAA==.',
Bu='Bubblesquish:BAAALgADCgUJBQAAAA==.Bufforc:BAABLgAFFH8IAAILAAUJfyAkBgAIAQALAAUJfyAkBgAIAQAAAA==.Buglerion:BAAALgAECgMJAwABLgAECgkJLgASAEcmAA==.Buildie:BAAALgAECgIJAgAAAA==.Bulgear:BAAALgAECgEJAgAAAA==.Bupropion:BAABLgAECn8eAAIHAAYJAhmCWQBiAQAHAAYJAhmCWQBiAQABLgAECgkJNQAVAMEfAA==.Bushwhacker:BAABLgAECn8hAAMSAAcJzw6kNAArAQASAAcJzw6kNAArAQAWAAIJJQvnNQBdAAAAAA==.Butterbean:BAABLgAECn8tAAIQAAkJCCB3CwDnAgAQAAkJCCB3CwDnAgAAAA==.',
Ca='Capew:BAAALgADCgIJAgAAAA==.Captdirtyjay:BAAALgAECgIJAgAAAA==.Cassardis:BAAALgAECggJEQAAAA==.Catameringue:BAABLgAECn8WAAIXAAcJBBEHQAB/AQAXAAcJBBEHQAB/AQAAAA==.',
Ch='Chickenhawk:BAAALgAECgEJAQAAAA==.Chicxulub:BAAALgAECggJDwAAAA==.Chido:BAAALgADCgYJCgABLgAECgcJFAABABwMAA==.',
Ci='Cigfa:BAAALgADCgUJBQAAAA==.',
Cl='Classfantasy:BAABLgAECn8xAAMUAAkJKCBBCQDjAgAUAAkJKCBBCQDjAgATAAYJCREVRwD7AAAAAA==.Clickshoot:BAAALgAECgUJBQAAAA==.',
Co='Coaca:BAABLgAECn8nAAMBAAgJZh0NMAAnAgABAAgJZh0NMAAnAgAGAAEJEQemjgAmAAAAAA==.Cobalt:BAAALgAECgMJBAABLgAECgQJBAADAAAAAA==.Confluent:BAABLgAECn81AAMXAAkJQyVVAQDCAwAXAAkJQyVVAQDCAwASAAkJAhh2DwBQAgAAAA==.Conor:BAAALgAECgEJAQAAAA==.',
Cr='Crowlèy:BAABLgAECn83AAIYAAkJ7xK1IACQAQAYAAkJ7xK1IACQAQAAAA==.',
Cu='Cursè:BAAALgADCgIJAgABLgAECgkJKwAZAEkIAA==.',
Cy='Cythrandir:BAAALgAECgYJDAABLgAFFAMJDgAZAL0WAA==.',
Da='Daniellena:BAAALgADCgkJGAAAAA==.Davwr:BAAALgAECgMJAwABLgAECgYJBwADAAAAAA==.',
Dd='Ddccssff:BAAALgAECgQJCAAAAA==.',
De='Deathcoiled:BAAALgAECggJEAAAAA==.Defnotademon:BAAALgAECgQJBQAAAA==.Dethrahzen:BAABLgAECn8mAAMVAAcJ9QKNFQCkAAAVAAcJ9QKNFQCkAAAaAAIJhwHZigAlAAAAAA==.',
Di='Dirtydan:BAAALgADCgMJAgAAAA==.Disektor:BAABLgAECn8qAAIbAAgJuRucHgDmAQAbAAgJuRucHgDmAQAAAA==.',
Dj='Djcamsoda:BAAALgAECgEJAQAAAA==.',
Dk='Dkmeatz:BAAALgAECgEJAQAAAA==.Dkray:BAAALgAECgYJDAAAAA==.',
Do='Dorelios:BAAALgADCgMJAwAAAA==.Dotsfordayz:BAAALgAECgEJAQAAAA==.Dovahkiin:BAAALgAECgEJAQAAAA==.',
Dr='Dracaris:BAAALgADCgcJGAAAAA==.Dragonboy:BAAALgAECgIJAgAAAA==.Dronesworn:BAAALgAECgYJEQAAAA==.',
Du='Dubstep:BAAALgAECgYJEAAAAA==.Dugatotems:BAABLgAECn8rAAMUAAkJchjjGwA5AgAUAAkJchjjGwA5AgATAAkJYQgCNgBGAQAAAA==.Dukunbringer:BAAALgADCgQJAQAAAA==.Dumptruck:BAAALgADCgUJBQAAAA==.Dumpytruck:BAAALgAECgQJBQAAAA==.Dunkle:BAABLgAECn8tAAMcAAkJgyB/BgCBAgAbAAkJihz8EwCuAgAcAAkJzBt/BgCBAgAAAA==.Dunklebug:BAAALgAECgEJAQAAAA==.Duskhawk:BAABLgAECn8gAAIQAAgJkwnlYQBqAQAQAAgJkwnlYQBqAQAAAA==.',
['Dâ']='Dârkness:BAAALgAECgcJEgAAAA==.',
Eb='Ebonise:BAAALgAECgUJCgAAAA==.',
Ed='Edrelang:BAABLgAECn8YAAMbAAcJAQkoRgAVAQAbAAcJAQkoRgAVAQAcAAEJdAX2cgAmAAAAAA==.',
Ee='Eerikki:BAAALgAECgYJEAAAAA==.',
Ei='Ein:BAABLgAECn8zAAIVAAkJXRp0AgCGAgAVAAkJXRp0AgCGAgAAAA==.',
El='Ellechero:BAABLgAECn8hAAMdAAgJpQcQNQCsAAASAAcJ4AS5SgDEAAAdAAYJWQcQNQCsAAAAAA==.Ellonia:BAAALgAECgMJAwABLgAECggJIAAeAO4eAA==.Elowinnie:BAAALgADCgQJBQAAAA==.Elphiè:BAAALgADCgMJAwAAAA==.',
Er='Eragøn:BAABLgAECn8WAAIQAAcJrBrsOADjAQAQAAcJrBrsOADjAQAAAA==.Erinna:BAAALgAECgEJBAAAAA==.Erli:BAAALgADCgIJAgAAAA==.Erommêl:BAAALgAECgYJEAAAAA==.Erosandra:BAAALgADCgIJAgABLgAECgkJHgALAFYIAA==.',
Fa='Faedaurum:BAAALgADCgUJBQAAAA==.Farsha:BAAALgADCgkJCQABLgAECgcJFAABABwMAA==.',
Fe='Fengpopo:BAAALgADCgEJAQAAAA==.Fextrius:BAAALgAECgYJCAAAAA==.',
Fo='Fopa:BAAALgADCgcJDwAAAA==.',
Fr='Franman:BAABLgAECn8hAAIMAAYJ0xa/fABVAQAMAAYJ0xa/fABVAQABLgAFFAQJDwAbAPAdAA==.Frthckr:BAAALgAECgYJDAAAAA==.',
Fu='Funnelcakes:BAAALgADCgcJDwAAAA==.Furrystorm:BAAALgAFFAEJAgAAAA==.',
Fy='Fyrestar:BAAALgADCgIJAgAAAA==.',
Ga='Galatrix:BAABLgAECn8tAAIZAAkJlA7QVwC9AQAZAAkJlA7QVwC9AQAAAA==.',
Gh='Ghast:BAABLgAECn9NAAMJAAkJkhWvLQAVAgAJAAkJMxWvLQAVAgARAAEJqx0MMwA8AAAAAA==.Ghats:BAABLgAECn8VAAMJAAgJnRj0NAD4AQAJAAgJnRj0NAD4AQAeAAEJAAC2TQAAAAAAAA==.',
Gi='Gigaflare:BAABLgAECn8nAAIZAAkJqAwkgwDLAQAZAAkJqAwkgwDLAQAAAA==.Girl:BAAALgADCgMJAwAAAA==.',
Gl='Glahmgold:BAAALgAECgEJAQAAAA==.',
Gn='Gnorbert:BAAALgADCgcJDAAAAA==.',
Go='Goatale:BAAALgAECgYJCwABLgAECgkJLAAMAFQgAA==.Goatknight:BAABLgAECn8sAAIMAAkJVCAOEADaAgAMAAkJVCAOEADaAgAAAA==.Goatwings:BAAALgAECgIJAgAAAA==.Gobblynn:BAAALgADCggJEAAAAA==.Golokan:BAABLgAECn8UAAIBAAcJHAxlygDcAAABAAcJHAxlygDcAAAAAA==.Goodspeed:BAAALgAECgEJAwAAAA==.Gora:BAABLgAECn81AAIJAAkJng0RTwCiAQAJAAkJng0RTwCiAQAAAA==.',
Gr='Gragdan:BAAALgADCgMJAwAAAA==.Greifswald:BAAALgAECgEJAQAAAA==.Gretchen:BAAALgAECgQJCAAAAA==.Greywings:BAABLgAECn82AAIVAAgJjQ6qCQB4AQAVAAgJjQ6qCQB4AQAAAA==.Grimroxs:BAABLgAECn8rAAIPAAgJVg76CQCHAQAPAAgJVg76CQCHAQAAAA==.Grippy:BAAALgADCgYJBgAAAA==.Griptape:BAAALgAECgEJAQAAAA==.Grizzlemaw:BAAALgAECgcJDAAAAA==.',
Ha='Hacheros:BAAALgAECgIJAgAAAA==.Hadic:BAAALgADCgEJAQABLgAECgkJCQADAAAAAA==.Hairypits:BAAALgAECgQJCAABLgAECgkJLAAMAFQgAA==.Handerbug:BAABLgAECn8uAAMSAAkJRyblAgA0AwASAAkJRyblAgA0AwAdAAYJtBzbEwCXAQAAAA==.Handiebug:BAAALgADCgYJBgABLgAECgkJLgASAEcmAA==.Handurbug:BAAALgAECgMJBQABLgAECgkJLgASAEcmAA==.Handybug:BAAALgADCgMJAwABLgAECgkJLgASAEcmAA==.Hankit:BAAALgAECgQJBQAAAA==.Harandayum:BAAALgADCgUJCAAAAA==.Harnbinger:BAAALgAECgMJBAAAAA==.Havel:BAAALgAECgYJCgAAAA==.',
He='Healsalot:BAAALgADCgEJAQAAAA==.Heatsman:BAAALgADCgEJAQAAAA==.Heiler:BAABLgAECn8fAAIEAAgJDgvcLgBAAQAEAAgJDgvcLgBAAQAAAA==.Heinrich:BAABLgAECn8vAAMBAAgJ8iOdEgC/AgABAAgJ8iOdEgC/AgAGAAQJPRFAbADJAAAAAA==.Heira:BAAALgADCgQJCAAAAA==.',
Hi='Hi:BAAALgADCgEJAQAAAA==.Hippypedro:BAAALgAECgYJBgABLgAFFAQJFgAIAHIZAA==.',
Ho='Hogglethorp:BAAALgAECggJEwAAAA==.Hololo:BAAALgADCgIJAgAAAA==.Holyhooters:BAAALgADCgkJEQAAAA==.',
Hr='Hrima:BAAALgAECgYJDwAAAA==.Hruurs:BAAALgADCgcJCgAAAA==.',
Hu='Humunculi:BAAALgADCgcJBwAAAA==.Huntion:BAAALgAECgQJBAAAAA==.',
Ie='Iegend:BAAALgAECgkJBAABLgAFFAEJAQADAAAAAA==.',
Il='Ilina:BAAALgAECgUJCgABLgAFFAIJAgADAAAAAA==.Illadron:BAAALgAECgYJCAAAAA==.Illecebra:BAAALgAECgYJDAAAAA==.',
Im='Imashammy:BAAALgADCgYJBgAAAA==.',
In='Inala:BAABLgAECn8XAAMSAAgJvAgMOAAYAQASAAgJvAgMOAAYAQAXAAMJUgzXlAB1AAAAAA==.',
Ja='Jagerblunt:BAABLgAECn8kAAIQAAkJqBmaKQAhAgAQAAkJqBmaKQAhAgAAAA==.',
Jd='Jdbud:BAAALgAECgIJAgAAAA==.Jdpot:BAAALgAECgYJDgAAAA==.',
Je='Jenaaidy:BAABLgAECn8gAAICAAcJ1xQoJQCBAQACAAcJ1xQoJQCBAQAAAA==.',
Jh='Jhannae:BAAALgADCgEJAQAAAA==.',
Jo='Joshed:BAAALgADCgIJAgABLgAECgkJLgAKAPIhAA==.Joshery:BAABLgAECn8uAAMKAAkJ8iGLBQAJAwAKAAkJ8iGLBQAJAwAfAAYJQiY2DwCLAgAAAA==.Joshieboba:BAAALgAECgYJCQABLgAECgkJLgAKAPIhAA==.',
Ju='Judge:BAABLgAECn8rAAIBAAgJyhI9XgCcAQABAAgJyhI9XgCcAQAAAA==.Juhara:BAAALgADCgYJBgAAAA==.Justviolence:BAAALgADCgUJBQAAAA==.',
Jy='Jynrokka:BAABLgAECn8oAAIgAAgJSCG3BwCKAgAgAAgJSCG3BwCKAgAAAA==.',
Ka='Katasaria:BAACLgAFFH8SAAMbAAUJAR4pEQBeAQAbAAUJAR4pEQBeAQAcAAEJxxTIMgBKAAAuAAQKfysAAxsACAmNIEwSAE4CABsACAkXIEwSAE4CABwABQk0GsYnABgBAAAA.Kaycee:BAAALgADCgUJCAABLgAECggJJgANAI4PAA==.Kayceedeeuh:BAAALgADCgUJBQABLgAECggJJgANAI4PAA==.Kaycer:BAAALgADCggJDwABLgAECggJJgANAI4PAA==.',
Ke='Keeps:BAAALgAECgEJAQAAAA==.Kerl:BAAALgAECggJEQABLgAECgkJCQADAAAAAA==.',
Ki='Kiboridi:BAAALgAECgQJBQAAAA==.Kimetshu:BAABLgAECn8gAAIIAAgJaBSfGQCSAQAIAAgJaBSfGQCSAQAAAA==.Kirana:BAABLgAECn8mAAISAAgJTQZhPwD0AAASAAgJTQZhPwD0AAAAAA==.',
Kn='Knserbrave:BAABLgAECn8WAAIMAAgJRAttkABfAQAMAAgJRAttkABfAQAAAA==.',
Kr='Kraphtdinner:BAABLgAECn8rAAIWAAkJqBs/BQCEAgAWAAkJqBs/BQCEAgAAAA==.Kravin:BAAALgAECgQJBwAAAA==.Krunzar:BAAALgAECgMJBQAAAA==.',
Kt='Ktheir:BAAALgADCgUJBQAAAA==.',
Ku='Kudrani:BAAALgAECgMJAwABLgAECgcJFAABABwMAA==.',
Ky='Kynnas:BAAALgADCggJDQAAAA==.',
La='Lammasthan:BAAALgAECgkJCQAAAA==.Laneywine:BAAALgAECgYJDAAAAA==.Larlifax:BAAALgAECgUJBwAAAA==.Lauxilicous:BAAALgADCgQJBAAAAA==.',
Le='Lemonytuba:BAAALgAECgUJBQAAAA==.Leonuss:BAABLgAECn8yAAIbAAkJcSXRAQBUAwAbAAkJcSXRAQBUAwAAAA==.Levìstus:BAABLgAECn8nAAIMAAgJHhgpPQD6AQAMAAgJHhgpPQD6AQAAAA==.Leylaní:BAABLgAECn8hAAIQAAgJpBXzOgDcAQAQAAgJpBXzOgDcAQAAAA==.Leyva:BAAALgAECgEJAQABLgAECgYJCAADAAAAAA==.',
Li='Lightstoes:BAAALgADCgUJBQAAAA==.Lillinth:BAAALgADCgEJAQAAAA==.',
Lo='Lobriok:BAAALgADCgkJGAAAAA==.Longknight:BAAALgAECgQJBgAAAA==.Loroessan:BAAALgAECgUJCAAAAA==.Lowal:BAAALgADCgQJBAAAAA==.',
Lu='Lucylawladin:BAAALgAECgcJDwAAAA==.Lukas:BAAALgAECgcJCQABLgAECgkJTQAJAJIVAA==.Lunet:BAAALgAECgEJAQAAAA==.Lustie:BAAALgAECgYJEwABLgAECgkJNQAVAMEfAA==.',
Ly='Lynnadin:BAAALgAECgUJCwAAAA==.Lyrenda:BAAALgADCgEJAQAAAA==.Lythea:BAAALgADCgYJBgABLgAECgkJNQAVAMEfAA==.Lytheum:BAABLgAECn81AAIVAAkJwR/NAQC0AgAVAAkJwR/NAQC0AgAAAA==.',
['Lí']='Líghts:BAAALgADCgEJAQAAAA==.',
['Lü']='Lücid:BAAALgAECgEJAgAAAA==.',
Ma='Machetesquad:BAAALgADCgkJCwABLgAECgkJMQAUACggAA==.Magerrac:BAAALgAECgEJAQABLgAECgkJHgALAFYIAA==.Malachar:BAABLgAECn8mAAILAAgJWg5GGQBaAQALAAgJWg5GGQBaAQAAAA==.Malboro:BAABLgAECn8qAAIJAAgJ7BJ0UQCbAQAJAAgJ7BJ0UQCbAQAAAA==.Maled:BAABLgAECn8fAAQRAAcJnB3mDABqAQARAAYJ7RvmDABqAQAeAAMJ8BrsFADnAAAJAAMJohDgzQCmAAAAAA==.Maleficent:BAAALgAECgkJCwAAAA==.Mandrew:BAAALgAECgkJBwAAAA==.Mandrews:BAAALgAECgkJDgAAAA==.',
Me='Mej:BAAALgAECgQJBAAAAA==.Meldin:BAABLgAECn8hAAIQAAgJ8SCNFgCJAgAQAAgJ8SCNFgCJAgAAAA==.Mennia:BAAALgADCgIJAgAAAA==.Merve:BAAALgAECgUJCQAAAA==.Method:BAABLgAECn8rAAMhAAkJBxSrDwCuAQAhAAkJhxOrDwCuAQABAAIJFxOkJQFnAAAAAA==.Methodbuggle:BAAALgADCgQJBAAAAA==.Mew:BAABLgAECn8cAAMGAAcJdh2SIQDhAQAGAAcJdh2SIQDhAQABAAEJJgEIpQESAAAAAA==.',
Mi='Miannya:BAABLgAECn8kAAIfAAkJ5BlYDgBMAgAfAAkJ5BlYDgBMAgAAAA==.Mignons:BAAALgADCgQJBAAAAA==.Milgauss:BAABLgAECn8nAAMHAAgJGBbdQwCkAQAHAAgJzxXdQwCkAQAiAAEJeRgmKQBAAAAAAA==.Mineos:BAABLgAECn8VAAIbAAYJWwyFSwABAQAbAAYJWwyFSwABAQAAAA==.Mistrmiso:BAAALgAECgMJAgABLgAECgkJLwARALolAA==.Mizoh:BAAALgAECgYJEAAAAA==.',
Mo='Moahuntress:BAAALgAECgYJCQAAAA==.Moonlyt:BAAALgADCgkJIAAAAA==.Morgaine:BAAALgADCggJCgABLgAECgkJHgALAFYIAA==.Morn:BAABLgAECn8ZAAMVAAgJaBp+BwBzAgAVAAgJaBp+BwBzAgAaAAQJVBWbPQD2AAAAAA==.Motley:BAAALgADCgcJDQABLgAECgkJTQAJAJIVAA==.',
Mt='Mtrain:BAAALgAECgYJCgABLgAECggJFQAJAJ0YAA==.',
Mu='Muradìn:BAAALgADCgkJCQAAAA==.',
My='Myra:BAAALgAECgQJDwAAAA==.Mystu:BAAALgAECgYJCAAAAA==.',
Na='Nadalrus:BAAALgADCgIJAgAAAA==.Nadià:BAAALgAECgMJAwAAAA==.',
Ne='Necroshaman:BAAALgADCgYJBgAAAA==.Needagrip:BAABLgAECn8hAAIgAAgJOxbwEwC5AQAgAAgJOxbwEwC5AQAAAA==.Neeryn:BAAALgAECgIJAgAAAA==.Nestiae:BAAALgAECgMJAwABLgAECgYJCQADAAAAAA==.Neverplayed:BAAALgADCgcJCQAAAA==.',
Ni='Nice:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Nightsfuri:BAABLgAECn8bAAISAAgJHxNHJQCIAQASAAgJHxNHJQCIAQAAAA==.Nik:BAAALgAECgQJBQAAAA==.Niqi:BAAALgADCgYJBgAAAA==.Nivara:BAAALgADCgQJCAAAAA==.',
No='Noodlebloat:BAAALgAECgQJBAAAAA==.',
Ny='Nynevans:BAABLgAECn8dAAIQAAgJ3QzrWACBAQAQAAgJ3QzrWACBAQAAAA==.Nyrobi:BAAALgADCgIJAgAAAA==.Nystannia:BAAALgADCgcJDQABLgAECgcJFAABABwMAA==.Nytheria:BAAALgADCgIJAQAAAA==.',
Od='Oderon:BAAALgADCgYJDAAAAA==.',
Om='Omron:BAAALgADCgEJAQAAAA==.',
Or='Orialis:BAAALgADCgQJBAABLgADCgcJGAADAAAAAA==.Orlandbro:BAABLgAECn8nAAQQAAkJ2x1iGAB3AgAjAAkJxhy4BQCyAgAQAAkJ4BdiGAB3AgAkAAEJMBA6igAxAAAAAA==.Orlondbro:BAAALgAECgEJAQAAAA==.Orso:BAAALgAECgEJAQAAAA==.',
Ot='Otohime:BAAALgADCgEJAQAAAA==.',
Pa='Pandawa:BAAALgAECgMJAwAAAA==.Patantrad:BAAALgAECgkJEwAAAA==.Patchy:BAAALgAECgQJBAAAAA==.Pawradox:BAABLgAECn8kAAICAAkJ8wzAJQB9AQACAAkJ8wzAJQB9AQAAAA==.',
Pe='Peadar:BAAALgAECgIJAgAAAA==.',
Ph='Phenomenon:BAAALgAECgYJDwAAAA==.Phumsukrit:BAAALgADCgcJCQAAAA==.',
Pi='Pippens:BAABLgAECn81AAIgAAkJUh6pCQBjAgAgAAkJUh6pCQBjAgAAAA==.Pitviper:BAABLgAECn8UAAIlAAYJBxmGEQAtAQAlAAYJBxmGEQAtAQAAAA==.',
Pl='Plina:BAABLgAECn8fAAIBAAgJDhaSVwCsAQABAAgJDhaSVwCsAQAAAA==.',
Po='Pohö:BAAALgADCgQJBAAAAA==.Ponglenis:BAAALgAECgMJBQABLgAFFAEJAQADAAAAAA==.Ponponte:BAAALgADCgQJBAAAAA==.Potatolor:BAAALgAECgYJDgAAAA==.',
Pr='Prettycolorz:BAABLgAFFH8GAAIUAAMJmQqISQCsAAAUAAMJmQqISQCsAAAAAA==.',
Pu='Pulli:BAAALgAECgkJEQAAAA==.',
Pv='Pve:BAACLgAFFH8FAAIjAAUJBwWyGQDuAAAjAAUJBwWyGQDuAAAuAAQKfy0AAiMACQn0H20FAMQCACMACQn0H20FAMQCAAAA.',
Pw='Pwyll:BAAALgADCgcJCwAAAA==.',
Ra='Raiina:BAABLgAECn8eAAIUAAkJdxNtLQDoAQAUAAkJdxNtLQDoAQAAAA==.Rainn:BAAALgAECgMJAwAAAA==.Rainnstorm:BAAALgADCgcJCwAAAA==.Rains:BAABLgAECn8UAAIZAAcJcRTNggBWAQAZAAcJcRTNggBWAQAAAA==.Rathane:BAACLgAFFH8FAAIQAAQJtQqfPgAQAQAQAAQJtQqfPgAQAQAuAAQKfxwAAhAACAm1HCAjADMCABAACAm1HCAjADMCAAAA.Rawrmuch:BAAALgAECgQJBAABLgAECggJEQADAAAAAA==.Ray:BAAALgAECgYJBgABLgAECggJGQAVAGgaAA==.',
Re='Realmclovin:BAAALgAECgUJBQAAAA==.Reaperzz:BAAALgADCgcJCAAAAA==.Redrabbit:BAAALgAECgUJBQAAAA==.Regulusaug:BAAALgADCgMJAwAAAA==.Relvana:BAAALgAECgMJAwAAAA==.',
Rh='Rhapsody:BAABLgAECn8oAAIGAAgJrSbhAQCJAwAGAAgJrSbhAQCJAwAAAA==.',
Ri='Rizzwan:BAABLgAECn8mAAIjAAgJwCBlBwCdAgAjAAgJwCBlBwCdAgAAAA==.',
Rj='Rjay:BAACLgAFFH8GAAMfAAMJYQnsIQC1AAAfAAMJYQnsIQC1AAAKAAIJ0AydPABrAAAuAAQKfykABAoACQmMHSYOAJsCAAoACAmXHCYOAJsCAB8ACAmwG5kQAC0CABgAAQmJDoCFADQAAAAA.',
Rl='Rly:BAAALgADCgEJAQAAAA==.',
Ro='Robo:BAAALgAECgMJBAABLgAFFAUJEgAbAAEeAA==.Romy:BAABLgAECn8fAAIZAAcJJAJ/7gCiAAAZAAcJJAJ/7gCiAAAAAA==.Roonoe:BAAALgAECgIJAgAAAA==.',
Ru='Runecleaver:BAABLgAECn87AAMUAAkJBCKyDgDGAgAUAAkJBCKyDgDGAgATAAQJExa/SgDuAAAAAA==.Ruw:BAABLgAECn8jAAMPAAgJEhByCwBmAQAPAAcJSxFyCwBmAQAOAAQJKghhOgDDAAAAAA==.',
Sa='Sadvibes:BAAALgADCgcJBgAAAA==.Sardroth:BAABLgAECn8lAAIMAAkJ7h+CEwDBAgAMAAkJ7h+CEwDBAgAAAA==.Satania:BAABLgAECn8fAAIIAAkJGiTyBAAlAwAIAAkJGiTyBAAlAwAAAA==.Satavara:BAABLgAECn8gAAMEAAgJLRdzMAA1AQAEAAUJLhRzMAA1AQACAAYJBRPKNAAiAQAAAA==.',
Se='Segora:BAABLgAECn8aAAIJAAYJRAcGnwAbAQAJAAYJRAcGnwAbAQABLgAECgkJNQAJAJ4NAA==.Seimus:BAAALgAECgUJEwAAAA==.Seniortotem:BAAALgAECgUJDQAAAA==.',
Sh='Shaanael:BAAALgAECgYJEgAAAA==.Shadowdecay:BAAALgADCgcJEQAAAA==.Shapòópy:BAABLgAECn8ZAAISAAYJRgY1TwC0AAASAAYJRgY1TwC0AAAAAA==.Sharius:BAABLgAECn8rAAIZAAkJSQhmeABtAQAZAAkJSQhmeABtAQAAAA==.Shawesome:BAAALgAECgQJBAAAAA==.Shiera:BAABLgAECn8cAAIZAAkJ6hJwZAAPAgAZAAkJ6hJwZAAPAgAAAA==.Shihajimari:BAAALgAECgUJCQAAAA==.Shootybooty:BAAALgADCgYJBgAAAA==.Shutendoji:BAAALgAECgEJAgABLgAECggJHQAfAKohAA==.',
Si='Sightlightx:BAAALgAECggJEQAAAA==.Siltrois:BAAALgAECgMJBAAAAA==.Silvershine:BAABLgAECn8uAAIbAAgJKguRNwBUAQAbAAgJKguRNwBUAQAAAA==.Siryn:BAABLgAECn8eAAIGAAcJhAPlVwC9AAAGAAcJhAPlVwC9AAAAAA==.',
Sl='Slurpin:BAAALgADCgYJBgAAAA==.',
Sm='Smashn:BAAALgAECgYJCgAAAA==.',
Sn='Snacks:BAAALgADCgQJBAAAAA==.',
So='Sortiara:BAAALgADCgYJBgABLgAECgYJDAADAAAAAA==.',
Sp='Spelledwong:BAABLgAECn8lAAImAAkJmBPtAgD4AQAmAAkJmBPtAgD4AQAAAA==.Spinlock:BAAALgADCgUJBgAAAA==.',
St='Stonehammer:BAAALgAECgEJAQAAAA==.Stormkight:BAAALgAECgIJAgAAAA==.Stormwovles:BAAALgADCgcJEAAAAA==.',
Su='Surperknight:BAAALgADCgUJBQAAAA==.',
Sw='Swaggart:BAAALgAECgEJAQAAAA==.',
Sy='Sylesta:BAABLgAECn8sAAMXAAkJAB7UEACxAgAXAAkJAB7UEACxAgASAAcJnhVbKQBsAQAAAA==.Syrden:BAAALgAECgYJCAABLgAECgkJFgAXAOgLAA==.',
Ta='Tagin:BAAALgADCgMJAwAAAA==.Tallyn:BAAALgADCgMJAwAAAA==.Talís:BAAALgADCggJDQAAAA==.Tapyourtoes:BAAALgADCgQJBAAAAA==.Tayloria:BAAALgAECgEJAQAAAA==.',
Te='Tenrizzy:BAAALgAECgIJCAAAAA==.Tessarion:BAAALgAECgkJCQAAAA==.',
Th='Thandas:BAABLgAECn8rAAIBAAcJCgrVrgAFAQABAAcJCgrVrgAFAQAAAA==.Thanoris:BAAALgADCgEJAQAAAA==.Therealolaf:BAAALgAECgkJAgAAAA==.Thniper:BAABLgAECn8oAAMkAAkJURgyGABrAgAkAAgJQBsyGABrAgAjAAUJ9wzDLQAnAQAAAA==.Thouvan:BAAALgAECgEJAQAAAA==.Thugnastyy:BAAALgAFFAEJAQAAAA==.',
Ti='Tiamaria:BAABLgAECn8nAAIGAAkJqxq3EwBcAgAGAAkJqxq3EwBcAgAAAA==.',
To='Tost:BAAALgADCgcJBwAAAA==.',
Tu='Turquoise:BAAALgAECgYJBgAAAA==.Tusker:BAAALgADCgcJCgAAAA==.',
Ty='Tyinviril:BAABLgAECn9HAAICAAkJLCXPAQBIAwACAAkJLCXPAQBIAwAAAA==.',
Un='Unter:BAAALgAECgEJAQAAAA==.',
Va='Valynx:BAAALgAECgUJBwAAAA==.',
Ve='Veraz:BAACLgAFFH8QAAMBAAYJFw+RHgBoAQABAAYJFw+RHgBoAQAGAAEJRgGiPwA+AAAuAAQKfzoAAwEACAkQIV0dAH4CAAEACAkQIV0dAH4CAAYABQk8CflgAPgAAAAA.',
Vi='Vietoutlaw:BAAALgADCgIJAgAAAA==.',
Vl='Vll:BAAALgAECgEJAQAAAA==.',
Vo='Voidbowels:BAABLgAECn8SAAIHAAcJDwvmfAALAQAHAAcJDwvmfAALAQAAAA==.Vonawesome:BAAALgAECgQJCAAAAA==.Vorpalblade:BAABLgAECn8uAAILAAkJMRfYDQD0AQALAAkJMRfYDQD0AQAAAA==.',
Vy='Vylas:BAAALgAECgUJCAAAAA==.Vynicon:BAABLgAFFH8GAAIMAAMJwgdLlgDBAAAMAAMJwgdLlgDBAAAAAA==.Vyraal:BAAALgADCggJDgAAAA==.',
Wa='Warlorok:BAAALgADCgkJCQAAAA==.',
We='Wedge:BAAALgAECgEJAQAAAA==.Weirdfish:BAAALgAECgkJBgAAAA==.Wend:BAABLgAECn8wAAMnAAkJ2B4HAQDOAgAnAAkJ2B4HAQDOAgAZAAEJPBnxNQE6AAAAAA==.',
Wi='Wildpaleon:BAABLgAECn8eAAIhAAkJfhLLDwCtAQAhAAkJfhLLDwCtAQAAAA==.Willowfox:BAAALgAECgMJCAAAAA==.',
Wo='Wobblersmonk:BAAALgAECgcJCgAAAA==.Wobblingwar:BAAALgAECgIJAgAAAA==.',
Wr='Wrahis:BAAALgAECgUJCAAAAA==.Wram:BAABLgAECn8eAAMLAAkJVgjgHgAiAQALAAkJVgjgHgAiAQAbAAIJJAHnpQAZAAAAAA==.Wramphist:BAAALgADCgYJBgABLgAECgkJHgALAFYIAA==.Wreckuiem:BAAALgAECggJEQAAAA==.Wreckuiemd:BAAALgADCgIJAgAAAA==.',
Wy='Wychlord:BAABLgAECn8gAAMeAAgJ7h4DBQALAgAeAAgJ8x0DBQALAgAJAAYJ8RjbRgC6AQAAAA==.',
Xe='Xenophilious:BAAALgADCgEJAQAAAA==.',
Xi='Xiøn:BAACLgAFFH8NAAIHAAUJ8RglLgBCAQAHAAUJ8RglLgBCAQAuAAQKfysAAgcACQm5HuEOALkCAAcACQm5HuEOALkCAAAA.',
Xr='Xristinà:BAAALgADCgkJCQAAAA==.',
Zi='Zillara:BAABLgAECn8bAAIPAAkJZwYDDgA0AQAPAAkJZwYDDgA0AQAAAA==.',
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
