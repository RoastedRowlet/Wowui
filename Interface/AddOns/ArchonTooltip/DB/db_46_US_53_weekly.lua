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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Druid-Guardian','Priest-Holy','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Monk-Mistweaver','Mage-Arcane','Rogue-Subtlety',}
local provider = {region='US',realm='Chromaggus',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJIAABAMQTAQ==.',
An='Anasazi:BAAALgAECggJDQAAAA==.Andrémarkis:BAAALgAECgQJBwABLgAFFAcJIAABAMQTAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8dAAICAAcJmRNeIgA/AQACAAcJmRNeIgA/AQAAAA==.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgAFFAEJAQABLgAFFAMJCAADADkWAA==.Barehunt:BAAALgADCgkJCQABLgAFFAMJCAADADkWAA==.',
Be='Bedorea:BAABLgAECn81AAMEAAkJQBouEQBtAgAEAAkJQBouEQBtAgAFAAEJ0Aa5RQAtAAAAAA==.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Bladestormz:BAABLgAFFH8JAAMGAAUJGRNyGQDMAAAGAAMJGxdyGQDMAAAFAAQJmw2nKQDGAAAAAA==.Blessurheart:BAAALgAECgMJAwABLgAFFAcJIAABAMQTAQ==.Bloodweiser:BAABLgAECn8WAAMHAAYJSBJwOQAWAQAHAAYJSBJwOQAWAQAIAAIJqAXmkQA/AAAAAA==.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAFFAUJCgAJAIAWAA==.Boxab:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAQ==.',
Bu='Buckchuck:BAABLgAECn8YAAIKAAgJyRhCEgDMAQAKAAgJyRhCEgDMAQAAAA==.Bullship:BAAALgADCgYJBgAAAA==.Bumwitboba:BAABLgAECn8dAAQLAAYJdB87GAAaAgALAAYJdB87GAAaAgAMAAQJeg0KYAB+AAANAAEJcxCTggA4AAAAAA==.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Canto:BAAALgADCgEJAQAAAA==.Capecod:BAABLgAECn8cAAIJAAcJ3AbnnwDjAAAJAAcJ3AbnnwDjAAAAAA==.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgQJBgAAAA==.Chironex:BAABLgAFFH8LAAIOAAUJgRayJwBIAQAOAAUJgRayJwBIAQAAAA==.Chuleta:BAAALgAECgQJBQAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAFFAUJCgAJAIAWAA==.Conjuresnacc:BAAALgAECgQJBAAAAA==.',
Da='Daelnei:BAABLgAECn8vAAIEAAcJIRFFAgDUAAAEAAcJIRFFAgDUAAAAAA==.Damja:BAABLgAECn8WAAIEAAYJagp3YgDOAAAEAAYJagp3YgDOAAAAAA==.Darkloky:BAABLgAECn9CAAIPAAkJXhC2AQDyAAAPAAkJXhC2AQDyAAAAAA==.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAIQAAcJtQznHgARAQAQAAcJtQznHgARAQAAAA==.',
De='Debby:BAABLgAECn8lAAIOAAkJwhXhAQA4AQAOAAkJwhXhAQA4AQAAAA==.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECggJDwAAAA==.',
Do='Donane:BAABLgAECn8fAAIRAAgJOhc5HQAZAgARAAgJOhc5HQAZAgAAAA==.',
Dr='Drimbo:BAABLgAECn8XAAMSAAcJLwKncQCHAAASAAcJLwKncQCHAAATAAEJ5QDsTwAVAAAAAA==.',
Du='Duareapa:BAAALgAECgYJDAABLgAECgkJGQAUANUXAA==.',
Ec='Echoes:BAABLgAECn8nAAIVAAgJ+B7bDQB8AgAVAAgJ+B7bDQB8AgAAAA==.Ectomage:BAAALgAECgQJBAAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAINAAgJCxbXIgCxAQANAAgJCxbXIgCxAQAAAA==.',
Fl='Floraa:BAAALgAECgYJCwAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMHAAYJExkGNgAlAQAHAAYJExkGNgAlAQAIAAEJvgGziwAgAAABLgAFFAUJCgAJAIAWAA==.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAFFAEJBAAAAA==.',
Il='Illidave:BAABLgAECn8fAAMWAAkJvAlrAgCKAAAXAAYJcgtLGgDLAAAWAAkJrQZrAgCKAAAAAA==.',
In='Insindia:BAABLgAECn8WAAIWAAgJ8gnqKQAvAQAWAAgJ8gnqKQAvAQAAAA==.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ+doAD+AAABAAYJjQ+doAD+AAAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8oAAMOAAkJqwkNWwBMAQAOAAgJgggNWwBMAQAPAAgJQgdASwAIAQAAAA==.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMRAAcJcRIFPQBSAQARAAYJ+hMFPQBSAQAYAAcJtxBxoAA3AQAAAA==.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kitana:BAAALgAFFAMJAwABLgAFFAcJIAABAMQTAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAFFAUJCgAJAIAWAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Madlabz:BAAALgADCgUJBQAAAA==.Maelle:BAACLgAFFH8gAAMBAAcJxBPCJAC5AQABAAcJjRPCJAC5AQAZAAIJyg9dDQCiAAAuAAQKfzMABAEACAm+JHgbALACAAEACAkWI3gbALACABkABQnJIlMMAP0BABoABAl4HhQYALoAAAAA.Magewings:BAABLgAECn8WAAIbAAYJkwwKygD6AAAbAAYJkwwKygD6AAAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Manitaur:BAAALgAECgUJBQAAAA==.Mastain:BAAALgAFFAMJBAAAAA==.',
Me='Mexcutioner:BAABLgAECn9GAAIcAAkJ1R1lFwCbAgAcAAkJ1R1lFwCbAgAAAA==.',
Mi='Mikayla:BAAALgAECgcJCwAAAA==.Miranda:BAAALgAFFAQJCQABLgAFFAcJIAABAMQTAQ==.Misobeastie:BAAALgAECgYJEQAAAA==.Mixup:BAACLgAFFH8RAAIBAAUJ3RU/TAAuAQABAAUJ3RU/TAAuAQAuAAQKf0sAAgEACQlyIJAPANACAAEACQlyIJAPANACAAAA.',
Mo='Mollan:BAAALgAECgcJDAAAAA==.Monkeys:BAAALgAFFAMJAQAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn86AAMCAAkJtxnYDwAOAgACAAkJtxnYDwAOAgADAAUJkgrt6QDIAAAAAA==.Mythikal:BAABLgAECn8bAAIDAAgJXA+HbQCKAQADAAgJXA+HbQCKAQAAAA==.',
Na='Nagini:BAAALgAECgQJBgAAAA==.Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAAdAAAAAA==.',
Ne='Necropheelia:BAAALgAECgIJAgAAAA==.Nemesis:BAAALgAECgEJAQAAAA==.',
No='Notthefather:BAAALgAECgcJDgAAAA==.',
Ot='Otekah:BAABLgAECn8mAAMRAAgJWBh5GgAwAgARAAgJWBh5GgAwAgAYAAUJ/AiCKAGJAAAAAA==.',
Ov='Overthereman:BAAALgAECgUJCAABLgAFFAMJCAADADkWAA==.',
Pe='Peppanutz:BAAALgAECgUJBAAAAA==.',
Pi='Pinuno:BAABLgAECn8mAAIWAAgJMw5NJABWAQAWAAgJMw5NJABWAQAAAA==.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn82AAIDAAkJNQyzZQCbAQADAAkJNQyzZQCbAQAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQeAAcJfhIoQQBpAQAeAAYJtxQoQQBpAQAHAAcJygyZNwAeAQAIAAQJcwn6ggBRAAAAAA==.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAbAGMPAA==.',
Ro='Roadhouse:BAAALgAECgQJBAAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAABLgAECn8ZAAIUAAkJ1RedAAB0AQAUAAkJ1RedAAB0AQAAAA==.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQAdAAAAAA==.Sandaexpress:BAABLgAFFH8IAAIDAAMJORa+DgCaAAADAAMJORa+DgCaAAAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIDAAQJYBM7aQAnAQADAAQJYBM7aQAnAQAAAA==.',
Sh='Shikaka:BAAALgAECgUJBQABLgAFFAMJCAADADkWAA==.Shme:BAACLgAFFH8QAAIbAAQJ8gsWHgBSAQAbAAQJ8gsWHgBSAQAuAAQKfzQAAxsACAnVHVErAMUCABsACAnVHVErAMUCAB8AAQmKFQYdADgAAAAA.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAbAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJCAABLgAFFAUJDQAYADMlAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAFFAUJDQAYADMlAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQAdAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8dAAQEAAgJLgxITQARAQAEAAcJJQtITQARAQAGAAUJagbcOACSAAAFAAIJ1AwLWwBuAAAAAA==.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8kAAIOAAcJVBidMgDoAQAOAAcJVBidMgDoAQAAAA==.',
Sy='Syllogica:BAACLgAFFH8aAAIgAAQJQBY+GgBEAQAgAAQJQBY+GgBEAQAuAAQKfxcAAiAACQm0EAcpAE8BACAACQm0EAcpAE8BAAAA.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Tankeybell:BAAALgAECgkJAQAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9WAAILAAkJkCQ3AgCFAwALAAkJkCQ3AgCFAwAAAA==.',
Te='Tenderloinz:BAAALgAECgUJEQAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Tokkia:BAAALgAECggJCAAAAA==.Toothandclaw:BAAALgADCgMJAwAAAA==.Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIRAAIJdhfZFwCGAAARAAIJdhfZFwCGAAAuAAQKfyoAAhEACAl/IrMFABADABEACAl/IrMFABADAAAA.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJEQAAAA==.Vaughan:BAACLgAFFH8NAAIYAAUJMyX2FwCvAQAYAAUJMyX2FwCvAQAuAAQKfy0AAhgACQmmJFsLAAsDABgACQmmJFsLAAsDAAAA.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Vo='Voidmo:BAAALgAECgkJBAAAAA==.',
Vy='Vynathenin:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAACLgAFFH8GAAIBAAQJMwbYbwDiAAABAAQJMwbYbwDiAAAuAAQKfz0AAgEACAm8Gs41AAICAAEACAm8Gs41AAICAAAA.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgAdAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whatacombo:BAAALgAECgYJBwABLgAFFAMJCAADADkWAA==.Whollycow:BAAALgAFFAEJAgABLgAFFAMJCAADADkWAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAABLgAFFH8KAAIJAAUJgBYxBwDjAAAJAAUJgBYxBwDjAAAAAA==.',
Wy='Wylin:BAAALgAECgUJCAAAAA==.',
Za='Zahn:BAAALgAECgYJCgAAAA==.Zaka:BAAALgADCgEJAQAAAA==.',
Ze='Zeraph:BAAALgAECgMJAwAAAA==.',
Zu='Zulander:BAAALgAECgQJDAAAAA==.',
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
