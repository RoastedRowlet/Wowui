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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Druid-Feral','Druid-Guardian','Druid-Balance','Unknown-Unknown','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','DeathKnight-Frost','Warrior-Arms','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Druid-Restoration','Mage-Fire','Mage-Arcane','Monk-Mistweaver','Paladin-Protection','Warrior-Protection','Priest-Shadow',}
local provider = {region='US',realm='TolBarad',name='US',type='weekly',zone=46,date='2026-07-12',data={Ae='Aelarion:BAAALgADCgIJAgAAAA==.',
Ai='Airfryer:BAABLgAECn8wAAMBAAgJvR07BAA/AgABAAgJvR07BAA/AgACAAMJQBDN5wCPAAABLgAECggJMwADAPggAA==.',
Aj='Ajorc:BAABLgAECn8aAAIEAAcJKhuaCgAdAgAEAAcJKhuaCgAdAgAAAA==.Ajudando:BAACLgAFFH8lAAMEAAYJNh8pAgC+AQAEAAYJgx4pAgC+AQAFAAQJthPqEQD1AAAuAAQKf0YABAQACQm7H1YHAGUCAAQACAnyIlYHAGUCAAUACQk0GPITALgBAAYAAgm0Cs5vAGAAAAAA.',
Ak='Akindart:BAAALgAFFAEJAQAAAA==.',
An='Anneliese:BAAALgAECgQJBQAAAA==.',
Ar='Aranaki:BAAALgAECgEJAQAAAA==.Arc:BAAALgAECgIJBAAAAA==.Arcadeshadow:BAAALgAECgYJDgABLgAECgcJCwAHAAAAAA==.Arkanjjo:BAAALgAECgEJAQAAAA==.Arkhin:BAAALgADCgYJBgABLgAECgQJBAAHAAAAAA==.Artesuda:BAAALgAECgIJAwAAAA==.Artorus:BAAALgAECgIJAgAAAA==.',
Au='Aurelya:BAAALgAECgcJCgAAAA==.',
Aw='Awrelius:BAAALgADCgUJDAAAAA==.',
Ay='Ayuub:BAAALgAECgQJBAAAAA==.',
Az='Aznat:BAAALgAECgYJDgABLgAECgkJJgAIAK0ZAA==.',
Ba='Bachir:BAAALgAECgcJBwAAAA==.Balduco:BAAALgAECgQJDQABLgAFFAIJAgAHAAAAAA==.Barkernth:BAABLgAECn8hAAIJAAgJwRXaFQC2AQAJAAgJwRXaFQC2AQAAAA==.Baródius:BAAALgADCgQJBwAAAA==.Batatadoci:BAABLgAECn8VAAIKAAgJqggLvAAOAQAKAAgJqggLvAAOAQAAAA==.',
Be='Bellatryx:BAAALgAECgIJAgAAAA==.Benx:BAAALgAECgQJAQAAAA==.',
Bi='Bianca:BAAALgAECgcJCAAAAA==.Bispopelado:BAAALgADCgcJBwAAAA==.',
Br='Brunnoo:BAAALgAECgUJCAABLgAECggJGAALAKgaAA==.Brutaal:BAAALgADCgUJBQAAAA==.Brutállus:BAAALgADCgcJBwAAAA==.',
Ca='Calangosauro:BAACLgAFFH8FAAMMAAIJXg8eJgBmAAAMAAIJXg8eJgBmAAANAAIJ+w4gKQBVAAAuAAQKfxUABA4ABwnIEtUCAKcAAA0ABgmADuBNAPYAAA4ABAk4E9UCAKcAAAwABglPDioHAFkAAAAA.Capetalista:BAAALgADCgIJAgABLgAECggJKgALAAocAA==.Caynann:BAAALgAECgMJAwAAAA==.',
Ch='Chinchanchen:BAAALgAECgQJCAAAAA==.Chronicles:BAAALgAECgQJBQAAAA==.',
Co='Coqueiro:BAAALgADCgYJBgAAAA==.Cowtholic:BAAALgAECgQJBAABLgAECgcJDAAHAAAAAA==.',
Cr='Cremador:BAABLgAECn8VAAIKAAgJBQiFHwChAAAKAAgJBQiFHwChAAAAAA==.',
Cy='Cyrannus:BAAALgAECgMJAwABLgAECggJMwADAPggAA==.',
Da='Dabura:BAAALgADCgEJBQAAAA==.Dam:BAAALgADCgYJBgAAAA==.',
De='Deabu:BAAALgADCgQJBQAAAA==.Demethryus:BAAALgADCgYJBgAAAA==.Dennath:BAAALgAECgQJBgAAAA==.Ders:BAAALgADCgEJAQAAAA==.Devilton:BAABLgAECn9KAAMPAAgJNxnmAQAMAgAPAAgJNxnmAQAMAgAQAAgJwBOXSQCpAQAAAA==.',
Di='Diericshaman:BAAALgADCgUJBQAAAA==.',
Dk='Dkagulino:BAAALgAECgMJAwABLgAFFAMJCAARAJQgAA==.',
Do='Domri:BAABLgAECn8bAAIRAAgJaCAHHwBLAgARAAgJaCAHHwBLAgAAAA==.Donnus:BAABLgAECn81AAILAAkJfyDPIQCWAgALAAkJfyDPIQCWAgAAAA==.Doomhand:BAAALgAECgQJBAAAAA==.Dormin:BAAALgADCgUJBQAAAA==.Dorotty:BAAALgAECgUJBgAAAA==.',
Dr='Dragolancer:BAAALgAECgMJAwAAAA==.Drakonvolk:BAABLgAECn86AAMDAAkJvyOvDAAHAwADAAkJ1SKvDAAHAwASAAcJLyDRAwA9AgAAAA==.Drevanir:BAAALgADCggJCAAAAA==.Druidzuda:BAAALgADCgEJAQAAAA==.',
Du='Dudah:BAAALgAECgEJAQAAAA==.',
['Dé']='Dégell:BAAALgAECgUJCQAAAA==.',
Ed='Edy:BAABLgAECn8WAAIRAAkJ1SNKBQA9AwARAAkJ1SNKBQA9AwAAAA==.',
Ee='Eelai:BAAALgADCgQJBAAAAA==.',
Ei='Einheriar:BAAALgADCgUJBQAAAA==.',
El='Elanya:BAAALgAECgUJCAAAAA==.Elidaryel:BAABLgAECn80AAIQAAkJFSA4EADAAgAQAAkJFSA4EADAAgAAAA==.Elma:BAAALgAECgEJAgABLgAECgkJJgACAHQdAA==.Elrondperedh:BAAALgAECgMJBAAAAA==.',
Er='Eryeth:BAAALgAECgYJBwABLgAECgkJJgAIAK0ZAA==.',
Es='Esnupe:BAAALgAECgQJCAAAAA==.',
Ex='Excloud:BAAALgAECgUJBQAAAA==.',
Fa='Faephine:BAABLgAECn8iAAIGAAkJcA61AwB+AQAGAAkJcA61AwB+AQAAAA==.Fallora:BAAALgADCgYJBgAAAA==.',
Fe='Felithia:BAAALgADCgQJBAABLgAFFAYJEgASAF4VAA==.',
Fr='Fred:BAAALgAECgUJCQAAAA==.Frozenrune:BAABLgAECn8lAAMSAAgJ1B/zBAD8AQASAAYJ4STzBAD8AQAJAAgJYBbJEgDgAQAAAA==.',
Fu='Fuleco:BAABLgAECn8vAAMTAAgJ4CPrCwAoAgATAAYJpSLrCwAoAgAUAAgJdCFRHAALAgAAAA==.',
Ga='Gablle:BAACLgAFFH8LAAIVAAMJ2h/BFgALAQAVAAMJ2h/BFgALAQAuAAQKfzYAAxUACQneDc8pAG0BABUACQneDc8pAG0BABYACQkbBeE0ACsBAAAA.Gabrielstone:BAAALgAECgQJBgAAAA==.Gabriwel:BAAALgAECgQJDwAAAA==.',
Gl='Glimmuln:BAABLgAECn8qAAMXAAYJjQnpggDZAAAXAAYJjQnpggDZAAAYAAMJewVYHwAqAAAAAA==.Glimwr:BAAALgAECgQJEgAAAA==.',
Go='Gordorc:BAAALgAECgEJAQAAAA==.Gorvok:BAAALgADCgMJAwAAAA==.',
Gr='Grongos:BAAALgAFFAIJAgAAAA==.Grumps:BAAALgADCgcJBwAAAA==.',
Gu='Gudeath:BAAALgAECgcJBwAAAA==.Gueber:BAAALgAECgYJDAAAAA==.Gueberlin:BAAALgADCgQJBAAAAA==.Guebernir:BAAALgADCgYJDAAAAA==.',
Ha='Hakoda:BAAALgAECgEJAQAAAA==.Harggoth:BAAALgAECggJEQAAAA==.',
He='Hergor:BAABLgAECn8vAAQYAAkJRBP/JgC0AQAYAAkJRBP/JgC0AQAXAAUJxAwyjADCAAAZAAIJvQgfLAA1AAAAAA==.Hexdrinker:BAAALgAECgEJAQABLgAECgEJAgAHAAAAAA==.',
Ir='Irmasuelen:BAAALgAECgYJCwAAAA==.',
Je='Jeh:BAAALgAECgMJAwAAAA==.Jeje:BAAALgAECgQJBwAAAA==.',
Jo='Jorgebenjorg:BAAALgAECgEJAQAAAA==.',
Ka='Kalanguin:BAAALgADCgEJAQAAAA==.Kandarai:BAAALgAECgIJAgAAAA==.Kate:BAABLgAECn8jAAIaAAkJZxS4MgDUAQAaAAkJZxS4MgDUAQAAAA==.',
Ke='Kessig:BAAALgAFFAEJAQAAAA==.',
Kh='Khylin:BAAALgAECgUJCAAAAA==.',
Kl='Klimorin:BAAALgADCgMJBAAAAA==.',
Ko='Kouta:BAAALgAECgEJAQAAAA==.',
Kr='Krzero:BAAALgADCgIJAgABLgAECgkJOgADAL8jAA==.',
Lc='Lcabronehboy:BAABLgAECn8kAAILAAcJThfwaQCoAQALAAcJThfwaQCoAQAAAA==.',
Le='Lexan:BAABLgAECn85AAQZAAgJXhcjAQDqAQAZAAgJ+RYjAQDqAQAYAAgJwRAdNgBhAQAXAAIJ8wkuugBZAAAAAA==.',
Li='Liadine:BAAALgADCgYJBwAAAA==.Linlygan:BAAALgADCgQJBAAAAA==.Lint:BAAALgADCgQJAwAAAA==.Lissão:BAABLgAECn8kAAMJAAkJBB7sCQB0AgAJAAkJBB7sCQB0AgADAAEJ8QCTPAEZAAAAAA==.',
Lu='Lucians:BAABLgAFFH8KAAIXAAMJCQcdNwBXAAAXAAMJCQcdNwBXAAAAAA==.Lucoa:BAAALgADCgUJBQABLgAECgkJJgACAHQdAA==.Luhanar:BAAALgAECgYJCwABLgAECgkJOgADAL8jAA==.',
Ly='Lylithe:BAAALgAECgEJAQAAAA==.',
Ma='Madow:BAABLgAECn8mAAICAAkJdB3tGQCIAgACAAkJdB3tGQCIAgAAAA==.Magmafire:BAABLgAECn85AAMbAAkJwiIfAQDAAgAbAAkJaiEfAQDAAgAcAAcJ8x/XAgBYAgAAAA==.Magronego:BAAALgAECgYJCAAAAA==.Malakain:BAAALgAECgQJBQAAAA==.Mayha:BAAALgAECgUJCQABLgAECgkJIQAKAFkWAA==.Mazakita:BAAALgADCgMJAwAAAA==.',
Me='Mellahel:BAAALgADCgUJBQAAAA==.',
Mi='Mitsy:BAABLgAECn8dAAMdAAYJfh8KCQBVAQAdAAYJfh8KCQBVAQAVAAYJDAt6PwAcAQAAAA==.',
Mo='Moffati:BAAALgADCgMJAwAAAA==.Morevil:BAAALgADCgQJBAAAAA==.Morgane:BAAALgAECgkJCAAAAA==.Morterubra:BAABLgAECn8zAAMDAAgJ+CD+HwCJAgADAAgJ+CD+HwCJAgAJAAUJoAsrQACOAAAAAA==.Mosa:BAABLgAECn8gAAIXAAgJPg5xTwB0AQAXAAgJPg5xTwB0AQAAAA==.Mozart:BAAALgAECgYJBgAAAA==.',
Mu='Mulkzagoon:BAAALgADCgQJBgAAAA==.Murodan:BAAALgAECgQJBAAAAA==.Musphelheim:BAAALgADCgcJBwAAAA==.',
['Mö']='Mörrigan:BAAALgAECgcJBwAAAA==.',
Na='Nadruk:BAABLgAECn8jAAIXAAcJuh7wHQAsAgAXAAcJuh7wHQAsAgAAAA==.Natalia:BAAALgAECgkJDQAAAA==.',
Ne='Neon:BAAALgAECgYJCgAAAA==.Neskau:BAAALgAECgEJAQABLgAECggJOQAZAF4XAA==.Nevinha:BAAALgADCgEJAQAAAA==.Neymardacaça:BAAALgADCgIJAgAAAA==.',
Ni='Nidaime:BAABLgAECn8aAAILAAgJRhNQ0gBJAQALAAgJRhNQ0gBJAQAAAA==.',
No='Noach:BAAALgADCgMJAwABLgAFFAIJAgAHAAAAAA==.Nocro:BAAALgADCgEJAQAAAA==.',
Oa='Oathkeeper:BAAALgAECgMJAwAAAA==.',
Od='Odahviing:BAAALgAECgYJDAABLgAECggJMwADAPggAA==.',
Oi='Oicasada:BAAALgADCgMJBAAAAA==.',
Op='Optix:BAAALgAECgMJAwAAAA==.',
Ox='Oxylus:BAABLgAECn8cAAIaAAgJqxHlOwCkAQAaAAgJqxHlOwCkAQAAAA==.',
Pa='Padremario:BAAALgADCgEJAgAAAA==.Palahorda:BAAALgADCgUJBQAAAA==.Panchorf:BAABLgAECn9KAAMeAAgJCgkbBwCvAAAeAAgJEwgbBwCvAAAKAAMJiQncKABvAAAAAA==.',
Pe='Pescador:BAAALgAECgcJEAAAAA==.Pevê:BAAALgAECgcJCQAAAA==.',
Po='Porcentagem:BAAALgAECgEJAgABLgAECgMJCAAHAAAAAA==.',
Pr='Prihunter:BAABLgAECn9KAAIRAAgJwQyNDABRAQARAAgJwQyNDABRAQAAAA==.Primanocte:BAAALgADCgYJBgAAAA==.',
Pu='Pudincessa:BAAALgAECgUJBwAAAA==.',
Ra='Rafikii:BAACLgAFFH8GAAIFAAMJRwKBPgAyAAAFAAMJRwKBPgAyAAAuAAQKfx0AAgUACAndApAgAJoAAAUACAndApAgAJoAAAAA.Randel:BAAALgADCgQJBAAAAA==.Raswell:BAAALgADCgEJAQAAAA==.',
Re='Rellana:BAAALgADCgIJAgAAAA==.',
Rh='Rhadamants:BAAALgAECgIJAgAAAA==.',
Ri='Richard:BAAALgADCggJBQAAAA==.Ritaa:BAABLgAECn8cAAIKAAcJSxuaRwAMAgAKAAcJSxuaRwAMAgAAAA==.Rizúl:BAAALgAECgQJBAAAAA==.',
Rl='Rldsbvb:BAABLgAECn8mAAIIAAkJrRnxDwAxAgAIAAkJrRnxDwAxAgAAAA==.',
Ro='Rokigame:BAAALgAECgEJAQABLgAECgIJAwAHAAAAAA==.Rotgaz:BAAALgAECgQJBwAAAA==.',
Sa='Sabedetudo:BAAALgAECgEJAgAAAA==.Sadomie:BAABLgAECn80AAIRAAkJ7hi3MQAVAgARAAkJ7hi3MQAVAgAAAA==.',
Sh='Shagratth:BAAALgADCgcJDQABLgAECggJIQACANgcAA==.Shalthear:BAAALgAECgIJBAABLgAECgkJJgACAHQdAA==.Shindi:BAAALgADCgQJBQAAAA==.Shreka:BAAALgAECgYJEgAAAA==.',
Si='Silaleas:BAAALgAECgkJEwAAAA==.Sin:BAAALgAECgIJAgAAAA==.',
Sk='Skiff:BAAALgAECgEJAgAAAA==.',
Sn='Snoxxie:BAAALgAECgEJAQABLgAECgEJAgAHAAAAAA==.',
So='Solana:BAAALgADCgYJBgAAAA==.',
Sr='Srjhon:BAAALgAECgEJAgAAAA==.',
Sw='Sweej:BAABLgAFFH8IAAMFAAMJyxYQGADFAAAFAAMJyxYQGADFAAAaAAEJ/gVHdgAvAAAAAA==.',
Ta='Tacalypau:BAAALgADCgYJBgAAAA==.Tahir:BAAALgAECgcJDAAAAA==.Taichi:BAAALgAECgEJAgAAAA==.Taima:BAAALgAFFAIJBAAAAA==.',
Th='Thebrunovest:BAABLgAECn8ZAAIDAAYJEhAAywDvAAADAAYJEhAAywDvAAAAAA==.Thortrevan:BAABLgAECn8sAAIRAAgJ0h2ZEAC1AgARAAgJ0h2ZEAC1AgAAAA==.Thrain:BAABLgAECn8fAAIfAAcJexl6HQBJAQAfAAcJexl6HQBJAQAAAA==.',
Ti='Tiffah:BAABLgAECn8pAAILAAkJ5yGTEwDkAgALAAkJ5yGTEwDkAgAAAA==.Tinth:BAAALgADCgEJAQAAAA==.Tixi:BAAALgAECgcJBwAAAA==.',
To='Toranaar:BAAALgAECgUJCAABLgAECgkJFgARANUjAA==.Torresmo:BAAALgAECgEJAQAAAA==.Totahealer:BAAALgAECgMJBQABLgAFFAIJAgAHAAAAAA==.',
Tr='Traix:BAAALgAECgYJEgAAAA==.Trememoita:BAAALgAECgMJAwAAAA==.',
Uh='Uheal:BAAALgAECgMJAwAAAA==.',
Ut='Utherjr:BAAALgAECgMJAwAAAA==.',
Va='Vanthyn:BAAALgAECgEJAQAAAA==.',
Ve='Veccia:BAAALgADCgIJAgAAAA==.Veltharys:BAAALgADCgIJAgAAAA==.',
Vh='Vherk:BAAALgADCgQJBAAAAA==.',
Vi='Visemir:BAAALgADCgQJBAAAAA==.',
We='Wenasnoches:BAAALgADCggJDAAAAA==.',
Wh='Whitetusk:BAAALgADCgcJBwAAAA==.',
Wo='Wonderkast:BAAALgAECgEJAQABLgAFFAgJJwAgAAUkAA==.',
Wu='Wurdulak:BAAALgADCgEJBQAAAA==.',
Xa='Xamelo:BAABLgAECn9KAAIXAAgJSCTwAAAsAwAXAAgJSCTwAAAsAwAAAA==.',
Xi='Xicobruxo:BAAALgAECgUJBgAAAA==.',
Yo='Yona:BAABLgAECn8WAAICAAYJgwqpzAC5AAACAAYJgwqpzAC5AAABLgAECgkJIQAKAFkWAA==.Yorkann:BAAALgAECgIJAgAAAA==.',
Za='Zadockn:BAAALgAECgQJBgAAAA==.',
Zu='Zughy:BAAALgAECgYJCQABLgAFFAgJJwAgAAUkAA==.',
['Zé']='Zédaplanta:BAABLgAECn8fAAIaAAYJ+hO1SQBoAQAaAAYJ+hO1SQBoAQAAAA==.',
['Är']='Ärkin:BAAALgAECgYJCQABLgAECggJMwADAPggAA==.',
['Ðe']='Ðeath:BAAALgAECgYJEgABLgAECggJLwATAOAjAA==.',
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
