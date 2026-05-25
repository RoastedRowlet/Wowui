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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','Unknown-Unknown','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Druid-Guardian','Druid-Balance','Monk-Mistweaver','Rogue-Outlaw','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','DeathKnight-Frost','Druid-Feral','Priest-Discipline','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','DemonHunter-Vengeance','Priest-Shadow','Warrior-Protection','Warrior-Arms','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgQJBAAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAgAAAA==.',
Al='Alba:BAABLgAECn8oAAICAAgJCh1PLAAuAgACAAgJCh1PLAAuAgABLgAFFAMJCQABACseAA==.Aletta:BAAALgAECgYJBwAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn8xAAMBAAkJSRQZKQAPAgABAAkJSRQZKQAPAgADAAIJTAl8KgBTAAAAAA==.Angelys:BAAALgAECgQJBgAAAA==.',
Ap='Aphrobitey:BAAALgAECgIJAgAAAA==.',
Aq='Aquâ:BAAALgADCgkJDwAAAA==.',
Ar='Arathas:BAAALgADCgcJBwAAAA==.Arianes:BAAALgAECgcJDgABLgAECgkJJgACAIgkAA==.Arturias:BAABLgAECn8aAAICAAgJdxJuWACjAQACAAgJdxJuWACjAQAAAA==.',
At='Athenaowl:BAAALgAECgYJDQAAAA==.',
Au='Autofocus:BAABLgAECn8eAAIBAAgJPBo8MADxAQABAAgJPBo8MADxAQAAAA==.',
Aw='Aweyna:BAAALgAECggJDAAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8NAAIEAAQJjBOZAwBRAQAEAAQJjBOZAwBRAQAuAAQKfyoAAgQACAmMHzEEADACAAQACAmMHzEEADACAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgQJCgAAAA==.Baoyue:BAAALgAECggJCwABLgAFFAQJCQAFAKEIAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigstones:BAACLgAFFH8IAAIGAAMJRQTULQCzAAAGAAMJRQTULQCzAAAuAAQKfyMAAgYACAnsDkIvAGsBAAYACAnsDkIvAGsBAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgcJCAABLgAECgcJEgAHAAAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn84AAIIAAkJghsNCABxAgAIAAkJghsNCABxAgAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8fAAIIAAcJ5wfkLADEAAAIAAcJ5wfkLADEAAAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8qAAQJAAkJvhN2BwDDAQAJAAkJMBJ2BwDDAQAKAAYJaQvHjwAGAQALAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgADCgkJBQAAAA==.Burnt:BAAALgAECgQJBAAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8uAAIMAAgJzgOHrAAMAQAMAAgJzgOHrAAMAQAAAA==.Calahan:BAACLgAFFH8GAAICAAMJgBm1RQD3AAACAAMJgBm1RQD3AAAuAAQKfx0AAgIACAmxGmw0AFACAAIACAmxGmw0AFACAAAA.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chancleta:BAAALgAECgYJBgAAAA==.Cherub:BAAALgADCgIJAgAAAA==.Chikostix:BAABLgAECn8gAAINAAcJXwhxFgAVAQANAAcJXwhxFgAVAQAAAA==.Christae:BAABLgAECn8mAAIOAAgJ9htnDwBLAgAOAAgJ9htnDwBLAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJDAAAAA==.Clydè:BAABLgAECn9SAAMPAAkJ6RaHFABJAgAPAAgJbheHFABJAgAQAAkJrhKjFwDLAQAAAA==.Cláncey:BAAALgAFFAEJAQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBwAKADkaAA==.Colinferal:BAAALgAFFAEJAQAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromise:BAAALgAECgIJAgAAAA==.Compromised:BAABLgAECn8vAAIRAAkJ3hvaBwCGAgARAAkJ3hvaBwCGAgAAAA==.Connalious:BAAALgAECgEJAQAAAA==.Conquests:BAAALgAECgEJAQAAAA==.Corelack:BAACLgAFFH8HAAISAAMJOBAHEQC0AAASAAMJOBAHEQC0AAAuAAQKfxcAAxIACQm9DRgbADIBABIACQmZDRgbADIBABMABQmpBVZTAJAAAAAA.',
Cr='Crwth:BAAALgAECgUJBQAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn8rAAIBAAkJORdTIgAxAgABAAkJORdTIgAxAgAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAIMAAUJoxovSAA3AQAMAAUJoxovSAA3AQAuAAQKfxgAAgwACQktGDxMAFICAAwACQktGDxMAFICAAAA.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8bAAMPAAcJ9gNhRwC4AAAPAAcJ9gNhRwC4AAAUAAUJrARlaQB4AAAAAA==.',
De='Deadlee:BAAALgADCgEJAQAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEALgAFFAIJAgABLgAFFAYJGgAMAO4SAA==.Despair:BAAALgADCggJDgABLgAFFAMJCQABACseAA==.',
Di='Dice:BAACLgAFFH8MAAIVAAQJHRnwAgBYAQAVAAQJHRnwAgBYAQAuAAQKfygAAhUACQltIfIAAPYCABUACQltIfIAAPYCAAAA.Disturbd:BAACLgAFFH8OAAMWAAUJ5AqqXAAVAQAWAAQJ5AqqXAAVAQAIAAEJAADDRQAAAAAuAAQKfxUAAxYACQkaC9NZAJUBABYACQkaC9NZAJUBAAgABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAWAOQKAA==.Dixierecht:BAABLgAECn8gAAIXAAgJbhskEwBSAgAXAAgJbhskEwBSAgAAAA==.',
Do='Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgUJEAAAAA==.Drvargas:BAAALgAECgQJCAAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAEBLgAECn8iAAIMAAkJvAw9VADDAQAMAAkJvAw9VADDAQAAAA==.Elmo:BAABLgAECn8oAAMMAAkJHhZeMAA5AgAMAAkJ0BVeMAA5AgAYAAEJwxUxEABAAAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erosis:BAACLgAFFH8NAAIMAAQJ/xtsLgBrAQAMAAQJ/xtsLgBrAQAuAAQKfyEAAgwACAkjIwIvALYCAAwACAkjIwIvALYCAAAA.',
Ez='Ezaratren:BAAALgAECgUJCgABLgAFFAMJBwASADgQAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8FAAIKAAMJMxu+HQANAQAKAAMJMxu+HQANAQAuAAQKfygAAwoACAmDIOgrAF8CAAoACAmDIOgrAF8CAAsABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8fAAMWAAgJvBgcYwDKAQAWAAgJHBYcYwDKAQAIAAgJXA3sIAAcAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8WAAIXAAgJfQ++KgCTAQAXAAgJfQ++KgCTAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Fistitresk:BAAALgADCgQJBAABLgAECgcJEwAHAAAAAA==.Fistofwayne:BAABLgAECn8UAAIQAAYJGgxdPgDjAAAQAAYJGgxdPgDjAAABLgAFFAQJEgAZABAgAA==.',
Fr='Frizzalot:BAAALgAECgEJAQAAAA==.Frizzer:BAAALgAECgMJAwAAAA==.',
Ga='Gakopozy:BAAALgAECgYJDwAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIWAAMJvBEhJwD7AAAWAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgAECgEJAQAAAA==.',
Gr='Grïmyst:BAAALgAECgEJAQABLgAFFAMJBwASADgQAA==.',
Gu='Guldán:BAAALgAECgYJEQAAAA==.',
Gw='Gwydre:BAACLgAFFH8RAAIIAAQJaCBFDABdAQAIAAQJaCBFDABdAQAuAAQKfxUAAggACAnqHvYNAC4CAAgACAnqHvYNAC4CAAAA.',
Ha='Havran:BAAALgAECgQJBAABLgAECgkJQwASABYXAA==.Havrin:BAABLgAECn9DAAMSAAkJFhceDADlAQASAAkJFhceDADlAQAaAAEJQhLgMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8JAAIBAAMJKx48PQD0AAABAAMJKx48PQD0AAAuAAQKfy4AAgEACQmVH10UAJMCAAEACQmVH10UAJMCAAAA.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgADCgUJBwAAAA==.',
Ho='Hoardkiller:BAAALgAECgQJAwABLgAFFAMJBwADAAkQAA==.Holmie:BAAALgADCgkJCgAAAA==.Honk:BAAALgAFFAIJAgAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogaplop:BAACLgAFFH8YAAMWAAUJkyYTGQCsAQAWAAUJkyYTGQCsAQAIAAUJqB/6CgBwAQAuAAQKfzcAAxYACQnOIwMUAAMDABYACQlWIQMUAAMDAAgACAkdIoIGAJUCAAAA.',
Hu='Huamulan:BAABLgAECn81AAICAAgJYQXNngAYAQACAAgJYQXNngAYAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAECgkJDgAHAAAAAA==.Ibchilling:BAABLgAECn8oAAIMAAgJxBpWQgD5AQAMAAgJxBpWQgD5AQABLgAECgkJDgAHAAAAAA==.Ibcorrupted:BAAALgAECgkJDgAAAA==.',
Ic='Icarrus:BAACLgAFFH8LAAIUAAMJ2RCKKACyAAAUAAMJ2RCKKACyAAAuAAQKfywAAxQACQnkHKkTAEYCABQACQnkHKkTAEYCAA8ABAmQEyBLAKsAAAEuAAUUBAkFABYAEwYA.Icarus:BAAALgADCgEJAQABLgAFFAQJBQAWABMGAA==.Iccarus:BAAALgAECgUJBQABLgAFFAQJBQAWABMGAA==.Icebone:BAAALgAECgcJCgABLgAECgcJEgAHAAAAAA==.',
Ig='Ignis:BAACLgAFFH8FAAIWAAQJEwYdYgAIAQAWAAQJEwYdYgAIAQAuAAQKfxYAAxYABgl5G3NtAGUBABYABgnzGXNtAGUBABkAAQkRFkQnAEMAAAAA.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJDgAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwAHAAAAAA==.',
Ja='Jackbfistn:BAAALgAECgcJEgAAAA==.Jaskim:BAABLgAECn8XAAMWAAkJiwqhWQCVAQAWAAkJbgqhWQCVAQAZAAIJ2AWyJgBGAAAAAA==.',
Je='Jeses:BAAALgAECgUJCAABLgAECgkJLwACAEIWAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAQJEwAWAAUiAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAABLgAECn8XAAMTAAYJ6wUXUACcAAATAAYJcQQXUACcAAAaAAMJ8gYkLgBoAAAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgAHAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJBQAAAA==.Kaltaan:BAABLgAECn8pAAMbAAkJuSGzBAAkAwAbAAkJuSGzBAAkAwAOAAQJUh8jPABKAQAAAA==.Karasan:BAABLgAECn8jAAIBAAkJ0BfPIwApAgABAAkJ0BfPIwApAgAAAA==.Karenas:BAABLgAECn8YAAMMAAgJpBmCVAA7AgAMAAgJpBmCVAA7AgAYAAIJ4QqZFgBmAAAAAA==.Karr:BAAALgAECgcJEQAAAA==.Kataraara:BAACLgAFFH8HAAIQAAQJRiBKDgB1AQAQAAQJRiBKDgB1AQAuAAQKfxcAAhAACAntJN4EADwDABAACAntJN4EADwDAAEuAAUUBQkVAAgAHiYA.Katbeans:BAABLgAECn8lAAQUAAkJ9RyZDwB0AgAUAAgJExyZDwB0AgAQAAUJIQ6RYgC4AAAPAAEJJhZSeAA8AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.',
Ke='Kelicemoon:BAABLgAECn8lAAMKAAgJ+wlzcgA/AQAKAAgJ7QdzcgA/AQALAAcJIQchKQBaAAABLgAECgkJNAAWAE0VAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn82AAIcAAkJpQ0rZgA0AQAcAAkJpQ0rZgA0AQAAAA==.',
Ki='Kiara:BAACLgAFFH8SAAIdAAUJVxnPDACVAQAdAAUJVxnPDACVAQAuAAQKfykAAx0ACQlpH1QIALUCAB0ACQlpH1QIALUCAB4AAglBENVlAHQAAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgMJAwAAAA==.',
Kr='Krogers:BAAALgAECgMJBQABLgAECgYJBwAHAAAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgADCgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
La='Lahrnaon:BAAALgAFFAIJAgAAAA==.Laxeron:BAABLgAECn8hAAIGAAgJ7yTdBwDDAgAGAAgJ7yTdBwDDAgAAAA==.',
Le='Leotherassy:BAAALgAECgQJBwAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Lotiel:BAAALgAECgMJCQABLgAFFAQJCwAfAC4TAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMcAAYJbB0oUgCuAQAcAAUJ2iEoUgCuAQAgAAEJswudLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madeye:BAAALgADCgQJBAAAAA==.Mahkaidook:BAAALgADCgYJBgAAAA==.Mal:BAAALgADCgkJCQABLgAECggJEgAHAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8cAAICAAgJcgu8lQAoAQACAAgJcgu8lQAoAQAAAA==.Mcfeast:BAABLgAECn8WAAIhAAcJNA8aLQBGAQAhAAcJNA8aLQBGAQAAAA==.',
Me='Medra:BAABLgAECn8nAAQGAAgJ6xU8JgChAQAGAAgJ6xU8JgChAQAiAAQJEgNnNgB0AAAjAAEJ2ASlaQAjAAAAAA==.Meowdi:BAAALgADCgkJBQAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn8sAAIMAAgJtwZMkAA8AQAMAAgJtwZMkAA8AQAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECgcJEgAHAAAAAA==.Mixr:BAAALgADCgQJAgAAAA==.',
Mo='Monana:BAAALgADCgkJBQAAAA==.Morar:BAAALgAECgUJCQAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nanija:BAAALgADCgkJBQAAAA==.',
Ne='Nezrin:BAAALgADCgEJAQAAAA==.',
Ni='Nightcat:BAAALgAECgQJBQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECggJFwACAKAgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nixie:BAABLgAECn8rAAMTAAkJ8gQ2OAABAQATAAkJ8gQ2OAABAQAfAAgJYgaGXwD3AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAIRAAUJlQacBgDfAAARAAUJlQacBgDfAAAuAAQKfxsAAhEACQlPFjMeAM4BABEACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8NAAMKAAQJeBrZOgAuAQAKAAQJzxXZOgAuAQALAAEJChsXGwBPAAAuAAQKfyIAAwoACAkeI+YtAAkCAAoABgmwIuYtAAkCAAsABQm9HzkaAHsBAAAA.',
Ok='Okkotsu:BAAALgAECgIJAgAAAA==.',
Ol='Oliiver:BAABLgAECn8lAAIBAAkJeB8LDQDEAgABAAkJeB8LDQDEAgAAAA==.',
Om='Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAAHAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8kAAIcAAkJyB5PFACEAgAcAAkJyB5PFACEAgAAAA==.',
Pa='Panaceus:BAABLgAECn86AAIdAAkJ1yJaAQB1AwAdAAkJ1yJaAQB1AwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDgAWAFYgAA==.Patron:BAAALgADCgIJAwAAAA==.',
Pe='Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgEJAgAAAA==.',
Ph='Phreeq:BAEALgAECgYJDgABLgAECgcJHwAXANUSAA==.Phrequency:BAEBLgAECn8fAAMXAAcJ1RJiKACjAQAXAAcJ1RJiKACjAQACAAQJzRMuyAD4AAAAAA==.',
Pi='Piety:BAAALgADCgIJAgAAAA==.Pig:BAAALgAECgEJAQABLgAFFAUJGAAWAJMmAA==.',
Pl='Playingwow:BAAALgAECgcJEwAAAA==.Plazmafury:BAAALgAECgMJAwAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8NAAIIAAQJrBi8DwAzAQAIAAQJrBi8DwAzAQAuAAQKfzAAAggACAmEHv0KADICAAgACAmEHv0KADICAAAA.',
Pr='Profang:BAAALgAECgQJBAAAAA==.',
Py='Pyrelic:BAABLgAFFH8UAAIPAAUJgRo3CwBDAQAPAAUJgRo3CwBDAQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEQAIAGggAA==.',
['Pö']='Pöncho:BAAALgAECgEJAQAAAA==.',
Qa='Qayllera:BAAALgAECgQJBAAAAA==.',
Qe='Qelcie:BAAALgAECgQJBQAAAA==.',
Qu='Quizet:BAAALgADCgYJCAAAAA==.',
Ra='Radicchio:BAAALgADCgkJBQAAAA==.Radkeem:BAABLgAECn8VAAIIAAgJaxrhDQD7AQAIAAgJaxrhDQD7AQAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgEJAQAAAA==.Rakeem:BAAALgAECgcJEAABLgAECggJFQAIAGsaAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.Razorknight:BAAALgAECgEJAQAAAA==.',
Re='Redtoxin:BAAALgADCgkJBgAAAA==.Reilley:BAACLgAFFH8RAAIWAAQJAxqvOQBQAQAWAAQJAxqvOQBQAQAuAAQKfyoAAhYACAmaIQcZAI8CABYACAmaIQcZAI8CAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAQJEQAWAAMaAA==.Reko:BAAALgAECgQJAwAAAA==.Remorsa:BAAALgAECgUJDgAAAA==.Renni:BAABLgAECn8sAAIKAAkJxBYrJAA1AgAKAAkJxBYrJAA1AgAAAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIXAAkJLBYzIgDMAQAXAAkJLBYzIgDMAQAAAA==.',
Ro='Rosealia:BAABLgAECn8WAAIBAAcJvAVohQADAQABAAcJvAVohQADAQAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8JAAIFAAQJoQgWIQDWAAAFAAQJoQgWIQDWAAAuAAQKf04AAgUACQl3IgECACsDAAUACQl3IgECACsDAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgADCgcJBwABLgAECggJEgAHAAAAAA==.Saintzan:BAAALgAECggJDgAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECggJKgACAAgVAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8iAAIdAAgJcQumFQBMAQAdAAgJcQumFQBMAQAAAA==.Schmoop:BAACLgAFFH8HAAIhAAUJKCCvCgB6AQAhAAUJKCCvCgB6AQAuAAQKfy4ABCEACAnyI98GAMYCACEACAnyI98GAMYCAA4ABgmLGtEoAFsBABsAAQnxEGNWADQAAAEuAAUUBQkYABYAkyYA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Senza:BAABLgAECn8aAAICAAcJaQnBpAAOAQACAAcJaQnBpAAOAQAAAA==.Senzyri:BAABLgAECn8jAAIBAAgJnxNSRgCiAQABAAgJnxNSRgCiAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECgcJEgAHAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgAHAAAAAA==.',
Sh='Shamagoth:BAAALgADCgEJAQAAAA==.Shambhala:BAAALgAECgYJBgAAAA==.Shoes:BAAALgAECgUJBwAAAA==.',
Si='Simic:BAABLgAECn8rAAIIAAkJvw5BGABwAQAIAAkJvw5BGABwAQAAAA==.',
Sm='Smokeace:BAAALgADCgYJBgAAAA==.',
Sn='Snowthistle:BAABLgAECn8WAAITAAcJPQUjRgDBAAATAAcJPQUjRgDBAAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECggJJwAGAOsVAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAABLgAFFH8GAAMPAAIJwhcQIgCUAAAPAAIJIRQQIgCUAAAQAAEJIBdDSABKAAAAAA==.Spudpal:BAAALgADCgEJAQABLgAECgkJKQAbALkhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgYJBgAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Static:BAAALgAECgYJBgAAAA==.Stonymahoney:BAABLgAECn88AAICAAkJjxqfHgBwAgACAAkJjxqfHgBwAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAABLgAECn80AAIGAAkJPySyAQBNAwAGAAkJPySyAQBNAwAAAA==.Suê:BAAALgADCgEJAQABLgADCgQJBAAHAAAAAA==.',
Sv='Sveela:BAACLgAFFH8OAAISAAQJdiAaBACBAQASAAQJdiAaBACBAQAuAAQKfyQAAhIACQlrIsEDAMoCABIACQlrIsEDAMoCAAAA.Sveelaa:BAABLgAECn8lAAIBAAgJax+BFACFAgABAAgJax+BFACFAgABLgAFFAQJDgASAHYgAA==.Sveella:BAAALgADCgEJAQABLgAFFAQJDgASAHYgAA==.',
Sw='Swampjimmy:BAAALgAECgYJCAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn87AAMOAAkJmR5uBgDsAgAOAAkJmR5uBgDsAgAhAAEJNAUCeQAnAAAAAA==.Talras:BAAALgAECgMJAwAAAA==.',
Te='Temlock:BAABLgAECn8wAAIKAAgJPRosMQBIAgAKAAgJPRosMQBIAgABLgAECgkJNgAIACQiAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDgAWAFYgAA==.Temtank:BAABLgAECn82AAIIAAkJJCL2AgD9AgAIAAkJJCL2AgD9AgAAAA==.',
Tr='Trak:BAABLgAECn8ZAAIeAAgJOQ1fNAA3AQAeAAgJOQ1fNAA3AQAAAA==.Trukarak:BAABLgAECn8qAAICAAgJCBXpUAC3AQACAAgJCBXpUAC3AQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Vaelithria:BAAALgAECgEJAQABLgAFFAQJCQAFAKEIAA==.Valenti:BAABLgAECn8gAAMkAAYJvBHMHQD4AAAkAAYJvBHMHQD4AAACAAEJ0AbEewElAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiEAQQDkAQACAAcJhiEAQQDkAQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJBQAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.',
Wi='Wildama:BAABLgAECn8hAAIfAAkJnA/aMgCvAQAfAAkJnA/aMgCvAQAAAA==.Wildtail:BAAALgAECgYJBgAAAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAECgkJGgACACIcAA==.',
Xi='Xiao:BAABLgAECn8lAAIUAAkJYRYZFgAsAgAUAAkJYRYZFgAsAgAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQAHAAAAAA==.',
Ya='Yahargul:BAABLgAECn8cAAIhAAgJ9gxIKABkAQAhAAgJ9gxIKABkAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Za='Zaterok:BAAALgAECgMJAwABLgAECggJKgACAAgVAA==.',
Ze='Zeik:BAABLgAECn8qAAMkAAkJLRurBQBrAgAkAAkJLRurBQBrAgACAAMJngoIIwFcAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgADCgkJBQAAAA==.',
Zu='Zucco:BAAALgAECgkJDgAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECgkJKQAbALkhAA==.',
['Zí']='Zíx:BAABLgAECn8lAAIiAAgJ1g/YGwAuAQAiAAgJ1g/YGwAuAQAAAA==.',
['Àl']='Àlcàrà:BAABLgAECn8YAAMIAAcJCg/3IAAcAQAIAAcJCg/3IAAcAQAWAAEJDgptIQEzAAAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Ÿa']='Ÿamar:BAAALgADCgMJAwAAAA==.',
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
