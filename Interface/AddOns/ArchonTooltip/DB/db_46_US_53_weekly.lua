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

local lookup = {'Warlock-Demonology','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Monk-Brewmaster','Druid-Guardian','Priest-Holy','Priest-Discipline','Priest-Shadow','DemonHunter-Devourer','Shaman-Elemental','Paladin-Protection','Shaman-Restoration','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Balance','Monk-Windwalker','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Hunter-BeastMastery','DemonHunter-Havoc','DeathKnight-Unholy','Monk-Mistweaver','Mage-Arcane','Warrior-Protection','Rogue-Subtlety',}
local provider = {region='US',realm='Chromaggus',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adeaa:BAAALgADCgcJCQAAAA==.',
Al='Alisaie:BAAALgAFFAMJAwABLgAFFAcJHwABAMQTAQ==.',
An='Anasazi:BAAALgAECgMJBQAAAA==.Andrémarkis:BAAALgAECgMJBAABLgAFFAcJHwABAMQTAQ==.',
Ar='Aranaya:BAAALgAECgUJDwAAAA==.',
As='Aspersio:BAABLgAECn8dAAICAAcJmRPGGwBMAQACAAcJmRPGGwBMAQAAAA==.',
Az='Azuragirl:BAAALgAECgEJAQAAAA==.',
Ba='Barecarebear:BAAALgADCgcJBwABLgAECgUJCQADAAAAAA==.Barehunt:BAAALgADCgcJBwABLgAECgUJCQADAAAAAA==.',
Be='Bedorea:BAABLgAECn8tAAMEAAgJdxiWGQD+AQAEAAgJdxiWGQD+AQAFAAEJ0Aa5RQAtAAAAAA==.',
Bi='Biblikal:BAAALgAECgEJAQAAAA==.Bigwhiskey:BAAALgAECgIJAgAAAA==.',
Bl='Blessurheart:BAAALgAECgMJAwABLgAFFAcJHwABAMQTAQ==.',
Bo='Bobthelob:BAAALgAECgEJAQAAAA==.Bohatyn:BAAALgADCgkJDwAAAA==.Bora:BAAALgAECgQJCgABLgAECgYJFwAGABMZAA==.Boxab:BAAALgAFFAEJAQABLgAFFAcJHwABAMQTAQ==.',
Bu='Buckchuck:BAABLgAECn8WAAIHAAcJMxgBEwCGAQAHAAcJMxgBEwCGAQAAAA==.Bumwitboba:BAABLgAECn8dAAQIAAYJdB87GAAaAgAIAAYJdB87GAAaAgAJAAQJeg3gTACJAAAKAAEJcxCcagA5AAAAAA==.',
Ca='Cairra:BAAALgAECgMJAwAAAA==.Calypso:BAAALgADCgkJHAAAAA==.Capecod:BAABLgAECn8cAAILAAcJ3AYAhwDoAAALAAcJ3AYAhwDoAAAAAA==.Captnstabbin:BAAALgAECgMJAwAAAA==.',
Ch='Chicaka:BAAALgAECgIJAgAAAA==.Chironex:BAAALgAFFAIJAgAAAA==.',
Co='Cofee:BAAALgAECgEJAQABLgAECgYJFwAGABMZAA==.',
Da='Daelnei:BAABLgAECn8gAAIEAAYJpAz6RgAAAQAEAAYJpAz6RgAAAQAAAA==.Damja:BAAALgAECgYJEgAAAA==.Darkloky:BAABLgAECn8pAAIMAAgJawnZPgAIAQAMAAgJawnZPgAIAQAAAA==.Darksinburnr:BAAALgAECgUJBQAAAA==.Dasa:BAABLgAECn8UAAINAAcJtQznHgARAQANAAcJtQznHgARAQAAAA==.',
De='Debby:BAABLgAECn8YAAIOAAYJGhXlRQBjAQAOAAYJGhXlRQBjAQAAAA==.Derka:BAAALgAECgMJBgAAAA==.Deâthwang:BAAALgAECgYJDAAAAA==.',
Do='Donane:BAABLgAECn8XAAIPAAgJ4BKvIwDCAQAPAAgJ4BKvIwDCAQAAAA==.',
Dr='Drimbo:BAABLgAECn8XAAMQAAcJLwJIXgCQAAAQAAcJLwJIXgCQAAARAAEJ5QDsTwAVAAAAAA==.',
Du='Duareapa:BAAALgAECgYJDAAAAA==.',
Ec='Echoes:BAABLgAECn8iAAISAAgJxx04DgBOAgASAAgJxx04DgBOAgAAAA==.',
El='Elnovia:BAAALgADCgEJAQAAAA==.',
Er='Eriden:BAAALgADCgQJBAAAAA==.',
Fa='Fatherchuck:BAAALgADCgcJDAAAAA==.',
Fi='Fizzl:BAABLgAECn8fAAIKAAgJCxYDHAC/AQAKAAgJCxYDHAC/AQAAAA==.',
Fl='Floraa:BAAALgADCgEJAQAAAA==.',
Fr='Frellnik:BAAALgAECgUJCAAAAA==.',
Go='Gobknobbler:BAAALgADCgIJAgAAAA==.Gogurt:BAAALgADCgkJDAAAAA==.Goldi:BAABLgAECn8XAAMGAAYJExngLgArAQAGAAYJExngLgArAQATAAEJvgGziwAgAAAAAA==.',
Hi='Hipthrust:BAAALgADCgEJAQAAAA==.',
Ho='Hogsmasher:BAAALgADCgUJBQAAAA==.',
Ik='Ikarro:BAAALgAECgEJAQABLgAECgkJJgAKAFMfAA==.',
In='Insindia:BAAALgAECgcJDAAAAA==.',
Ja='Jasa:BAAALgAECgYJEQAAAA==.',
Je='Jebber:BAAALgADCggJDwAAAA==.',
Ji='Jigsaw:BAAALgAECgEJAQAAAA==.',
Ka='Kalima:BAABLgAECn8aAAIBAAYJjQ+cigAPAQABAAYJjQ+cigAPAQAAAA==.Kalios:BAAALgADCgcJBwAAAA==.Kaplan:BAABLgAECn8mAAMOAAgJggicSgBRAQAOAAgJggicSgBRAQAMAAYJTQdiUwC7AAAAAA==.',
Ke='Kerelm:BAAALgADCgYJBgAAAA==.',
Kh='Khane:BAABLgAECn8jAAMPAAcJcRLyMwBZAQAPAAYJ+hPyMwBZAQAUAAcJtxC2gABNAQAAAA==.',
Ki='Kiernan:BAAALgAECgUJBQAAAA==.Kiril:BAAALgAECgQJBgAAAA==.Kitana:BAAALgAECgYJBgABLgAFFAcJHwABAMQTAA==.',
Kl='Klara:BAAALgAECgQJBwABLgAECgYJFwAGABMZAA==.',
Kn='Knifed:BAAALgAECgQJBQAAAA==.',
Ko='Kobalte:BAAALgADCgIJAgAAAA==.',
Ku='Kuhedamerung:BAAALgAECgEJAQAAAA==.',
Lf='Lfbeerpst:BAAALgADCgYJBgAAAA==.',
Ma='Maelle:BAACLgAFFH8fAAMBAAcJxBOZDgDVAQABAAcJjROZDgDVAQAVAAIJyg9dDQCiAAAuAAQKfzMABAEACAm+JHgbALACAAEACAkWI3gbALACABUABQnJIlMMAP0BABYABAl4HhQYALoAAAAA.Magewings:BAABLgAECn8WAAIXAAYJkwzKrQAKAQAXAAYJkwzKrQAKAQAAAA==.Manglehaft:BAAALgAECgQJCAAAAA==.Mangos:BAAALgAECgUJBgAAAA==.Mastain:BAAALgAFFAMJAwAAAA==.',
Me='Mexcutioner:BAABLgAECn8zAAIYAAkJyRslEwCOAgAYAAkJyRslEwCOAgAAAA==.',
Mi='Mikayla:BAAALgAECgMJAwAAAA==.Miranda:BAAALgAFFAIJAwABLgAFFAcJHwABAMQTAQ==.Mixup:BAACLgAFFH8HAAIBAAQJ/QWDVgDsAAABAAQJ/QWDVgDsAAAuAAQKf0IAAgEACQl8HswQAK4CAAEACQl8HswQAK4CAAAA.',
Mo='Mollan:BAAALgAECgQJBwAAAA==.Moonkiller:BAAALgAECgMJAwAAAA==.',
My='Mynta:BAAALgAECggJEQAAAA==.Myronar:BAABLgAECn81AAICAAkJtxmvCwAkAgACAAkJtxmvCwAkAgAAAA==.Mythikal:BAAALgAECgYJEAAAAA==.',
Na='Nalgene:BAAALgADCgcJFAAAAA==.Narcotized:BAAALgADCgQJBAABLgAECgUJCAADAAAAAA==.',
Ot='Otekah:BAABLgAECn8eAAMPAAcJsBcNHgDrAQAPAAcJsBcNHgDrAQAUAAUJ/Agy+QCTAAAAAA==.',
Pe='Peppanutz:BAAALgAECgUJBQAAAA==.',
Pi='Pinuno:BAABLgAECn8WAAIZAAcJngyYJAAYAQAZAAcJngyYJAAYAQAAAA==.',
Pr='Prikk:BAAALgADCggJCAAAAA==.',
Ps='Psychocircus:BAABLgAECn81AAIaAAkJNQzIUgCoAQAaAAkJNQzIUgCoAQAAAA==.',
Pu='Puncho:BAABLgAECn8eAAQbAAcJfhIuMABoAQAbAAYJtxQuMABoAQAGAAcJygweMAAkAQATAAQJcwm9agBTAAAAAA==.Putmypwninu:BAAALgAECgYJEgAAAA==.',
Ra='Razoar:BAAALgADCgIJAgAAAA==.',
Re='Redsonja:BAAALgAECgYJBgAAAA==.',
Ri='Riiven:BAAALgAECggJDwABLgAECgkJHwAXAGMPAA==.',
Ro='Roadhouse:BAAALgADCgkJCQAAAA==.Ronald:BAAALgADCgEJAQAAAA==.',
Ru='Rustinbieber:BAAALgAECgYJDAABLgAECgYJDAADAAAAAA==.',
Sa='Saebe:BAAALgAECgQJDAABLgAECggJEQADAAAAAA==.Sandaexpress:BAAALgAECgQJBAABLgAECgUJCQADAAAAAA==.Saxarin:BAAALgAECgMJAwAAAA==.',
Sc='Schnuckems:BAAALgADCggJDwAAAA==.',
Se='Serovelle:BAABLgAFFH8HAAIaAAQJYBPyRQA7AQAaAAQJYBPyRQA7AQAAAA==.',
Sh='Shikaka:BAAALgAECgUJBQABLgAECgUJCQADAAAAAA==.Shme:BAACLgAFFH8QAAIXAAQJ8gsWHgBSAQAXAAQJ8gsWHgBSAQAuAAQKfzQAAxcACAnVHVErAMUCABcACAnVHVErAMUCABwAAQmKFQYdADgAAAAA.Shmeian:BAAALgAECgEJAQABLgAFFAQJEAAXAPILAA==.Shruikan:BAAALgAECgQJBQAAAA==.',
Si='Sidaria:BAAALgAECgYJBwABLgAECgkJLAAUAKYkAA==.Silex:BAAALgADCgIJAgAAAA==.Sithras:BAAALgAECgcJBwABLgAECgkJLAAUAKYkAA==.',
Sk='Skrunchie:BAAALgAECgIJAgAAAA==.',
So='Soulreaper:BAAALgAECgMJAwAAAA==.',
St='Starasmirra:BAAALgAECgIJBQABLgAECggJEQADAAAAAA==.Stjùdé:BAAALgADCgYJAQAAAA==.Stompede:BAABLgAECn8VAAMEAAcJigodQgATAQAEAAcJHgodQgATAQAdAAUJagYnLwCeAAAAAA==.',
Su='Summonir:BAAALgAECgIJAgAAAA==.Sunhawk:BAAALgADCgkJCQAAAA==.',
Sw='Swayne:BAABLgAECn8eAAIOAAcJ9RJ2QAB6AQAOAAcJ9RJ2QAB6AQAAAA==.',
Sy='Syllogica:BAACLgAFFH8MAAIeAAQJ6RAnHQD3AAAeAAQJ6RAnHQD3AAAuAAQKfxYAAh4ACAmsEAEhAGABAB4ACAmsEAEhAGABAAAA.',
Ta='Tamino:BAAALgAECgUJBgAAAA==.Taurenister:BAAALgADCgcJEQAAAA==.Tazzi:BAABLgAECn9CAAIIAAkJVCSiAQCJAwAIAAkJVCSiAQCJAwAAAA==.',
Te='Tenderloinz:BAAALgAECgUJDwAAAA==.Tetrohydro:BAAALgADCgEJAQAAAA==.',
To='Toxxiic:BAAALgAECgMJBAAAAA==.',
Tr='Triggeredmon:BAAALgAECgYJBQAAAA==.',
Tw='Twofive:BAACLgAFFH8HAAIPAAIJdhfZFwCGAAAPAAIJdhfZFwCGAAAuAAQKfyoAAg8ACAl/IrMFABADAA8ACAl/IrMFABADAAAA.',
Ty='Tyrant:BAAALgAECgYJEwAAAA==.',
Va='Valanir:BAAALgAECgEJAQAAAA==.Vannahelzing:BAAALgAECggJDAAAAA==.Vaughan:BAABLgAECn8sAAIUAAkJpiTMBgAhAwAUAAkJpiTMBgAhAwAAAA==.',
Vi='Violence:BAAALgAECgYJCQAAAA==.',
Wa='Waffle:BAABLgAECn84AAIBAAgJShj/OADdAQABAAgJShj/OADdAQAAAA==.Wallskee:BAAALgADCgIJAgAAAA==.Wasteeface:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.Wasteysage:BAAALgAECgcJDgAAAA==.',
Wh='Whollycow:BAAALgAECgUJCQAAAA==.',
Wi='Wildheart:BAAALgADCgcJCAAAAA==.Wily:BAAALgAECgYJBwABLgAECgYJFwAGABMZAA==.',
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
