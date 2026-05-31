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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Monk-Brewmaster','Druid-Guardian','Priest-Holy','Priest-Discipline','Priest-Shadow','DemonHunter-Devourer','Shaman-Elemental','Paladin-Protection','Shaman-Restoration','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Balance','Monk-Windwalker','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Havoc','Monk-Mistweaver','Mage-Arcane','Warrior-Protection','Rogue-Subtlety',}
local provider = {region='US',realm='Chromaggus',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJIAABAMQTAQ==.',
An='Anasazi:BAAALgAECgMJBwAAAA==.Andrémarkis:BAAALgAECgQJBgABLgAFFAcJIAABAMQTAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8dAAICAAcJmRN5HgBIAQACAAcJmRN5HgBIAQAAAA==.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Barehunt:BAAALgADCgkJCQABLgAFFAEJAQADAAAAAA==.',
Be='Bedorea:BAABLgAECn80AAMEAAkJyRmZDwBqAgAEAAkJyRmZDwBqAgAFAAEJ0Aa5RQAtAAAAAA==.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Bladestormz:BAAALgAFFAMJAwAAAA==.Blessurheart:BAAALgAECgMJAwABLgAFFAcJIAABAMQTAQ==.Bloodweiser:BAAALgAECgUJCwAAAA==.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAECgYJFwAGABMZAA==.Boxab:BAAALgAFFAIJAgABLgAFFAcJIAABAMQTAQ==.',
Bu='Buckchuck:BAABLgAECn8YAAIHAAgJyRhIDwDQAQAHAAgJyRhIDwDQAQAAAA==.Bumwitboba:BAABLgAECn8dAAQIAAYJdB87GAAaAgAIAAYJdB87GAAaAgAJAAQJeg2aVQBzAAAKAAEJcxB4cgA4AAAAAA==.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAABLgAECn8cAAILAAcJ3AbMkwDaAAALAAcJ3AbMkwDaAAAAAA==.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgMJAwAAAA==.Chironex:BAAALgAFFAIJAgAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAECgYJFwAGABMZAA==.',
Da='Daelnei:BAABLgAECn8mAAIEAAYJGxCCQwAfAQAEAAYJGxCCQwAfAQAAAA==.Damja:BAAALgAECgYJEgAAAA==.Darkloky:BAABLgAECn8wAAIMAAgJQQvVPQAhAQAMAAgJQQvVPQAhAQAAAA==.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAINAAcJtQznHgARAQANAAcJtQznHgARAQAAAA==.',
De='Debby:BAABLgAECn8cAAIOAAYJGhVwTABhAQAOAAYJGhVwTABhAQAAAA==.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECgYJDAAAAA==.',
Do='Donane:BAABLgAECn8bAAIPAAgJ1xTLIQDgAQAPAAgJ1xTLIQDgAQAAAA==.',
Dr='Drimbo:BAABLgAECn8XAAMQAAcJLwLtZwB4AAAQAAcJLwLtZwB4AAARAAEJ5QDsTwAVAAAAAA==.',
Du='Duareapa:BAAALgAECgYJDAABLgAECgYJEAADAAAAAA==.',
Ec='Echoes:BAABLgAECn8nAAISAAgJ+B4uDAB+AgASAAgJ+B4uDAB+AgAAAA==.Ectomage:BAAALgAECgEJAQAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAIKAAgJCxZyHgCzAQAKAAgJCxZyHgCzAQAAAA==.',
Fl='Floraa:BAAALgAECgQJBAAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMGAAYJExnNMQAoAQAGAAYJExnNMQAoAQATAAEJvgGziwAgAAAAAA==.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAFFAEJAgAAAA==.',
Il='Illidave:BAAALgAECgYJCwAAAA==.',
In='Insindia:BAAALgAECgcJEQAAAA==.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ9HkwALAQABAAYJjQ9HkwALAQAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8mAAMOAAgJggjtUABQAQAOAAgJggjtUABQAQAMAAYJTQe2WQC7AAAAAA==.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMPAAcJcRK+NwBXAQAPAAYJ+hO+NwBXAQAUAAcJtxB4jQA7AQAAAA==.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kitana:BAAALgAECgYJBgABLgAFFAcJIAABAMQTAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAECgYJFwAGABMZAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Madlabz:BAAALgADCgUJBQAAAA==.Maelle:BAACLgAFFH8gAAMBAAcJxBPzFADMAQABAAcJjRPzFADMAQAVAAIJyg9dDQCiAAAuAAQKfzMABAEACAm+JHgbALACAAEACAkWI3gbALACABUABQnJIlMMAP0BABYABAl4HhQYALoAAAAA.Magewings:BAABLgAECn8WAAIXAAYJkwz8ugDzAAAXAAYJkwz8ugDzAAAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Mastain:BAAALgAFFAMJBAAAAA==.',
Me='Mexcutioner:BAABLgAECn84AAIYAAkJyRuJFwCCAgAYAAkJyRuJFwCCAgAAAA==.',
Mi='Mikayla:BAAALgAECgMJAwAAAA==.Miranda:BAAALgAFFAQJBwABLgAFFAcJIAABAMQTAQ==.Misobeastie:BAAALgAECgUJBQAAAA==.Mixup:BAACLgAFFH8MAAIBAAUJMxGDQAAzAQABAAUJMxGDQAAzAQAuAAQKf0sAAgEACQlyIMEMANoCAAEACQlyIMEMANoCAAAA.',
Mo='Mollan:BAAALgAECgQJBwAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn86AAMCAAkJtxk8DQAcAgACAAkJtxk8DQAcAgAZAAUJkgq40QDNAAAAAA==.Mythikal:BAABLgAECn8WAAIZAAcJuA3NgwBHAQAZAAcJuA3NgwBHAQAAAA==.',
Na='Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAADAAAAAA==.',
Ot='Otekah:BAABLgAECn8eAAMPAAcJsBeAIADpAQAPAAcJsBeAIADpAQAUAAUJ/AjADwGDAAAAAA==.',
Pe='Peppanutz:BAAALgAECgUJBAAAAA==.',
Pi='Pinuno:BAABLgAECn8WAAIaAAcJngyBKAASAQAaAAcJngyBKAASAQAAAA==.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn82AAIZAAkJNQyHWQCmAQAZAAkJNQyHWQCmAQAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQbAAcJfhK5NgBnAQAbAAYJtxS5NgBnAQAGAAcJygw3MwAhAQATAAQJcwlTdABTAAAAAA==.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAXAGMPAA==.',
Ro='Roadhouse:BAAALgADCgkJEwAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAAALgAECgYJEAAAAA==.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQADAAAAAA==.Sandaexpress:BAAALgAFFAEJAQAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIZAAQJYBPeUAAyAQAZAAQJYBPeUAAyAQAAAA==.',
Sh='Shikaka:BAAALgAECgUJBQABLgAFFAEJAQADAAAAAA==.Shme:BAACLgAFFH8QAAIXAAQJ8gsWHgBSAQAXAAQJ8gsWHgBSAQAuAAQKfzQAAxcACAnVHVErAMUCABcACAnVHVErAMUCABwAAQmKFQYdADgAAAAA.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAXAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJCAABLgAFFAQJBwAUAIAgAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAFFAQJBwAUAIAgAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQADAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8bAAQEAAcJjwulRAAbAQAEAAcJJQulRAAbAQAdAAUJagZVMwCWAAAFAAEJwAkLcAAqAAAAAA==.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8jAAIOAAcJVBhsLADtAQAOAAcJVBhsLADtAQAAAA==.',
Sy='Syllogica:BAACLgAFFH8SAAIeAAQJSBaQFQBEAQAeAAQJSBaQFQBEAQAuAAQKfxYAAh4ACAmsEJokAFUBAB4ACAmsEJokAFUBAAAA.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9IAAIIAAkJkCSkAQCRAwAIAAkJkCSkAQCRAwAAAA==.',
Te='Tenderloinz:BAAALgAECgUJEQAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIPAAIJdhfZFwCGAAAPAAIJdhfZFwCGAAAuAAQKfyoAAg8ACAl/IrMFABADAA8ACAl/IrMFABADAAAA.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJDAAAAA==.Vaughan:BAACLgAFFH8HAAIUAAQJgCD/FACPAQAUAAQJgCD/FACPAQAuAAQKfy0AAhQACQmmJJMIABIDABQACQmmJJMIABIDAAAA.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Vo='Voidmo:BAAALgAECgkJBAAAAA==.',
Wa='Waffle:BAABLgAECn87AAIBAAgJ/BmwNQD1AQABAAgJ/BmwNQD1AQAAAA==.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whollycow:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAAALgAECgYJDAABLgAECgYJFwAGABMZAA==.',
Wy='Wylin:BAAALgAECgUJCAAAAA==.',
Za='Zahn:BAAALgAECgYJCgAAAA==.Zaka:BAAALgADCgEJAQAAAA==.',
Ze='Zeraph:BAAALgAECgMJAwAAAA==.',
Zu='Zulander:BAAALgAECgIJAwAAAA==.',
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
