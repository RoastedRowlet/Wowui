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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Druid-Guardian','Priest-Holy','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival','Druid-Balance','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Monk-Mistweaver','Mage-Arcane','Rogue-Subtlety','Druid-Restoration',}
local provider = {region='US',realm='Chromaggus',name='US',type='weekly',zone=46,date='2026-07-05',data={Ad='Adeaa:BAAALgADCgkJDQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJIQABANcUAQ==.',
An='Anasazi:BAAALgAECggJDwAAAA==.Andrémarkis:BAAALgAECgQJBwABLgAFFAcJIQABANcUAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8kAAICAAcJIhVYAwA+AQACAAcJIhVYAwA+AQAAAA==.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgAFFAEJAQABLgAFFAMJCAADADkWAA==.Barehunt:BAAALgADCgkJCQABLgAFFAMJCAADADkWAA==.',
Be='Bedorea:BAABLgAECn86AAMEAAkJex5jAgDCAQAEAAkJex5jAgDCAQAFAAEJ0Aa5RQAtAAAAAA==.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Bladestormz:BAABLgAFFH8JAAMGAAUJGRN1GQDMAAAGAAMJGxd1GQDMAAAFAAQJmw2hKQDGAAAAAA==.Blessurheart:BAAALgAECgMJAwABLgAFFAcJIQABANcUAQ==.Bloodweiser:BAABLgAECn8WAAMHAAYJSBJzOQAWAQAHAAYJSBJzOQAWAQAIAAIJqAXnkQA/AAAAAA==.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAFFAYJDQAJAO0VAA==.Boxab:BAAALgAFFAIJAgABLgAFFAcJIQABANcUAQ==.',
Bu='Buckchuck:BAABLgAECn8YAAIKAAgJyRhBEgDMAQAKAAgJyRhBEgDMAQAAAA==.Bullship:BAAALgADCgYJBgAAAA==.Bumwitboba:BAABLgAECn8dAAQLAAYJdB87GAAaAgALAAYJdB87GAAaAgAMAAQJeg0MYAB+AAANAAEJcxCbggA4AAAAAA==.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Canto:BAAALgADCgEJAQAAAA==.Capecod:BAABLgAECn8cAAIJAAcJ3AbnnwDjAAAJAAcJ3AbnnwDjAAAAAA==.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgQJBgAAAA==.Chironex:BAABLgAFFH8LAAIOAAUJgRaiJwBJAQAOAAUJgRaiJwBJAQAAAA==.Chucknasty:BAAALgAFFAIJAgAAAA==.Chuleta:BAAALgAECgQJBQAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAFFAYJDQAJAO0VAA==.Conjuresnacc:BAAALgAECgQJBAAAAA==.',
Da='Daelnei:BAABLgAECn81AAIEAAgJ4hMCBQA+AQAEAAgJ4hMCBQA+AQAAAA==.Damja:BAABLgAECn8YAAIEAAYJkgt+YgDOAAAEAAYJkgt+YgDOAAAAAA==.Darkloky:BAABLgAECn9FAAIPAAkJahCQBwDiAAAPAAkJahCQBwDiAAAAAA==.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAIQAAcJtQznHgARAQAQAAcJtQznHgARAQAAAA==.',
De='Debby:BAABLgAECn8lAAIOAAkJvxXqCAAiAQAOAAkJvxXqCAAiAQAAAA==.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECggJDwAAAA==.',
Do='Donane:BAABLgAECn8rAAIRAAgJJRmEAgCxAQARAAgJJRmEAgCxAQAAAA==.',
Dr='Dragondeez:BAAALgAFFAMJAwABLgAFFAcJIQABANcUAQ==.Drimbo:BAABLgAECn8XAAMSAAcJLwKpcQCHAAASAAcJLwKpcQCHAAATAAEJ5QDsTwAVAAAAAA==.',
Du='Duareapa:BAAALgAECgYJDAABLgAECgkJIgAUAH4cAA==.',
Ec='Echoes:BAABLgAECn8nAAIVAAgJ+B7cDQB8AgAVAAgJ+B7cDQB8AgAAAA==.Ectomage:BAAALgAECgQJBAAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAINAAgJCxbYIgCxAQANAAgJCxbYIgCxAQAAAA==.',
Fl='Floraa:BAAALgAECgYJCwAAAA==.',
Fo='Forfoxsake:BAAALgADCgEJAQAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Gh='Ghoulghasm:BAAALgAECgYJBgAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMHAAYJExkJNgAlAQAHAAYJExkJNgAlAQAIAAEJvgGziwAgAAABLgAFFAYJDQAJAO0VAA==.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAABLgAFFH8GAAMWAAEJLxhwJwBHAAAWAAEJLxhwJwBHAAADAAEJQhPMeABDAAAAAA==.',
Il='Illidave:BAABLgAECn8nAAMXAAkJcwyTBwC6AAAXAAkJ4QiTBwC6AAAYAAgJwQvhAwCWAAAAAA==.',
In='Insindia:BAABLgAECn8XAAIXAAgJSAvvKQAvAQAXAAgJSAvvKQAvAQAAAA==.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ+foAD+AAABAAYJjQ+foAD+AAAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8oAAMOAAkJqwkTWwBMAQAOAAgJgggTWwBMAQAPAAgJQgdCSwAIAQAAAA==.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMRAAcJcRIHPQBSAQARAAYJ+hMHPQBSAQAZAAcJtxBxoAA3AQAAAA==.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kitana:BAAALgAFFAMJAwABLgAFFAcJIQABANcUAA==.Kitri:BAAALgAECgEJAQAAAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAFFAYJDQAJAO0VAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Lo='Lovatar:BAAALgAFFAEJAgAAAA==.',
Lu='Lunesta:BAAALgAECgEJAQABLgAFFAUJCQADAMccAA==.',
Ma='Madlabz:BAAALgADCgUJBQAAAA==.Maelle:BAACLgAFFH8hAAQBAAcJ1xSYJAC5AQABAAcJjROYJAC5AQAaAAIJyg9dDQCiAAAbAAEJtyIXCABmAAAuAAQKfzMABAEACAm+JHgbALACAAEACAkWI3gbALACABoABQnJIlMMAP0BABsABAl4HhQYALoAAAAA.Magewings:BAABLgAECn8WAAIcAAYJkwwQygD6AAAcAAYJkwwQygD6AAAAAA==.Mangiare:BAAALgAECggJDwAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Manitaur:BAAALgAECgcJCAAAAA==.Mastain:BAAALgAFFAMJBAAAAA==.',
Me='Mexcutioner:BAABLgAECn9GAAIdAAkJ1R1kFwCbAgAdAAkJ1R1kFwCbAgAAAA==.',
Mi='Mikayla:BAAALgAECggJEAAAAA==.Miranda:BAAALgAFFAQJCwABLgAFFAcJIQABANcUAQ==.Misobeastie:BAAALgAECgcJEwAAAA==.Mixup:BAACLgAFFH8RAAIBAAUJ3RUkTAAuAQABAAUJ3RUkTAAuAQAuAAQKf0sAAgEACQlyIJAPANACAAEACQlyIJAPANACAAAA.',
Mo='Mollan:BAAALgAECgcJDAAAAA==.Monkeys:BAAALgAFFAMJAQAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn86AAMCAAkJtxnXDwAOAgACAAkJtxnXDwAOAgADAAUJkgr26QDIAAAAAA==.Mythikal:BAABLgAECn8jAAIDAAkJYhVgBADOAQADAAkJYhVgBADOAQAAAA==.',
Na='Nagini:BAAALgAECgQJBgAAAA==.Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAAeAAAAAA==.',
Ne='Necromantic:BAAALgAECgUJBQAAAA==.Necropheelia:BAAALgAECgIJAgAAAA==.Nemesis:BAAALgAECgEJAQAAAA==.',
Ni='Niko:BAAALgAECgEJAQAAAA==.',
No='Nolwenn:BAAALgADCgEJAQAAAA==.Notthefather:BAABLgAECn8VAAIZAAcJVRAxDwAAAQAZAAcJVRAxDwAAAQAAAA==.',
Ot='Otekah:BAABLgAECn8mAAMRAAgJWBh2GgAwAgARAAgJWBh2GgAwAgAZAAUJ/AiIKAGJAAAAAA==.',
Ov='Overthereman:BAAALgAFFAEJAQABLgAFFAMJCAADADkWAA==.',
Pe='Peppanutz:BAAALgAECgUJBAAAAA==.',
Pi='Pinuno:BAABLgAECn8mAAIXAAgJMw5QJABWAQAXAAgJMw5QJABWAQAAAA==.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn82AAIDAAkJNQyzZQCbAQADAAkJNQyzZQCbAQAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQfAAcJfhImQQBpAQAfAAYJtxQmQQBpAQAHAAcJygycNwAeAQAIAAQJcwn4ggBRAAAAAA==.Putmypwninu:BAAALgAECgYJEwAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAcAGMPAA==.',
Ro='Roadhouse:BAAALgAECgQJBAAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rudra:BAAALgAECgIJAgAAAA==.Rustinbieber:BAABLgAECn8iAAIUAAkJfhyGAAC0AgAUAAkJfhyGAAC0AgAAAA==.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQAeAAAAAA==.Sandaexpress:BAABLgAFFH8IAAIDAAMJORaJRwCXAAADAAMJORaJRwCXAAAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIDAAQJYBM3aQAnAQADAAQJYBM3aQAnAQAAAA==.',
Sh='Shikaka:BAAALgAECgUJBQABLgAFFAMJCAADADkWAA==.Shme:BAACLgAFFH8QAAIcAAQJ8gsWHgBSAQAcAAQJ8gsWHgBSAQAuAAQKfzQAAxwACAnVHVErAMUCABwACAnVHVErAMUCACAAAQmKFQYdADgAAAAA.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAcAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJCAABLgAFFAUJDQAZADMlAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAFFAUJDQAZADMlAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQAeAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8dAAQEAAgJLgxMTQARAQAEAAcJJQtMTQARAQAGAAUJagbdOACSAAAFAAIJ1AwNWwBuAAAAAA==.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8kAAIOAAcJVBieMgDoAQAOAAcJVBieMgDoAQAAAA==.',
Sy='Syllogica:BAACLgAFFH8aAAIhAAQJQBY5GgBEAQAhAAQJQBY5GgBEAQAuAAQKfxcAAiEACQmoEAgpAE8BACEACQmoEAgpAE8BAAAA.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Tankeybear:BAAALgAFFAEJAQAAAA==.Tankeybell:BAAALgAFFAYJAQAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9WAAILAAkJkCQ2AgCFAwALAAkJkCQ2AgCFAwAAAA==.',
Te='Tenderloinz:BAABLgAECn8WAAIiAAYJLRH4BQANAQAiAAYJLRH4BQANAQAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Toothandclaw:BAAALgADCgMJAwAAAA==.Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.Triggeredpri:BAAALgADCgYJAQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIRAAIJdhfZFwCGAAARAAIJdhfZFwCGAAAuAAQKfyoAAhEACAl/IrMFABADABEACAl/IrMFABADAAAA.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJEgAAAA==.Vaughan:BAACLgAFFH8NAAIZAAUJMyXlFwCvAQAZAAUJMyXlFwCvAQAuAAQKfy0AAhkACQmmJF0LAAsDABkACQmmJF0LAAsDAAAA.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Vo='Voidmo:BAAALgAECgkJBAAAAA==.',
Vy='Vynathenin:BAAALgAECgUJDQAAAA==.',
Wa='Waffle:BAACLgAFFH8GAAIBAAQJMwbAbwDiAAABAAQJMwbAbwDiAAAuAAQKfz0AAgEACAm8Gs81AAICAAEACAm8Gs81AAICAAAA.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgAeAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whatacombo:BAAALgAECgYJBwABLgAFFAMJCAADADkWAA==.Whollycow:BAAALgAFFAEJAgABLgAFFAMJCAADADkWAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAABLgAFFH8NAAIJAAYJ7RVhDgByAQAJAAYJ7RVhDgByAQAAAA==.',
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
