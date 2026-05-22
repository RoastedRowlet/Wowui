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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Hunter-Marksmanship','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Shaman-Enhancement','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Druid-Guardian','Rogue-Outlaw','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','DeathKnight-Frost','Druid-Feral','Priest-Discipline','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','DemonHunter-Vengeance','Priest-Shadow','Paladin-Protection','Warrior-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adamonious:BAAALgAECgYJCwABLgAECgkJFgABAA8WAA==.Adaware:BAAALgAECgMJAwAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.Adellea:BAAALgAECgYJBwAAAA==.',
Ai='Aisha:BAAALgAECgEJAQAAAA==.',
Al='Alba:BAABLgAECn8kAAICAAgJpRzrIwAuAgACAAgJpRzrIwAuAgABLgAFFAMJCAABACseAA==.Aletta:BAAALgADCgQJCwABLgAECgMJBQADAAAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAABLgAECn8oAAMBAAgJZROZMADIAQABAAgJZROZMADIAQAEAAIJTAm4JQBVAAAAAA==.Angelys:BAAALgAECgQJBQAAAA==.',
Ap='Aphrobitey:BAAALgAECgIJAgAAAA==.',
Aq='Aquâ:BAAALgADCgkJDwABLgAECggJIgAFAFYbAA==.',
Ar='Arianes:BAAALgAECgcJDgABLgAECgkJIwACAB4kAA==.Arturias:BAABLgAECn8XAAICAAgJdxJaRACwAQACAAgJdxJaRACwAQAAAA==.',
At='Athenaowl:BAAALgAECgYJDQAAAA==.',
Au='Autofocus:BAABLgAECn8cAAIBAAgJNhr2JgD0AQABAAgJNhr2JgD0AQAAAA==.',
Aw='Aweyna:BAAALgAECggJDAAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAACLgAFFH8JAAIGAAMJ4REOBQD1AAAGAAMJ4REOBQD1AAAuAAQKfyoAAgYACAmPHzwDAD0CAAYACAmPHzwDAD0CAAAA.Ayasumi:BAAALgAECgIJAgAAAA==.',
Ba='Babaganoosh:BAAALgAECgQJBgAAAA==.Baoyue:BAAALgAECgYJCQABLgAFFAMJBwAHAKEIAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Benmonk:BAAALgAECgMJAwAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigstones:BAACLgAFFH8GAAIIAAMJRQQxJgC6AAAIAAMJRQQxJgC6AAAuAAQKfyMAAggACAnsDtcnAG0BAAgACAnsDtcnAG0BAAAA.',
Bl='Blacksavior:BAAALgAECgQJBAAAAA==.Blindbone:BAAALgAECgcJCAABLgAECgcJEQADAAAAAA==.Bluehydra:BAAALgADCgcJCAAAAA==.',
Bo='Bobbydigital:BAABLgAECn8wAAIJAAkJZxpLBwBgAgAJAAkJZxpLBwBgAgAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Boneski:BAAALgAECgUJEAAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAABLgAECn8ZAAIJAAYJPwnqKQCyAAAJAAYJPwnqKQCyAAAAAA==.Brixx:BAAALgAECgMJAwAAAA==.Brudiclad:BAABLgAECn8hAAQKAAgJmxEAEAAuAQAKAAcJwxAAEAAuAQALAAYJaQvqegAGAQAMAAIJzxH2UQB4AAAAAA==.',
Bu='Budfight:BAAALgADCgkJBQAAAA==.Butterfinger:BAAALgADCgQJBwAAAA==.Buxxor:BAAALgAECgcJBwAAAA==.',
Ca='Caimark:BAABLgAECn8iAAINAAgJVANP3AA6AQANAAgJVANP3AA6AQAAAA==.Calahan:BAACLgAFFH8GAAICAAMJgBnJNQAFAQACAAMJgBnJNQAFAQAuAAQKfx0AAgIACAmsGmw0AFACAAIACAmsGmw0AFACAAAA.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chikostix:BAABLgAECn8WAAIOAAcJZQX8FADvAAAOAAcJZQX8FADvAAAAAA==.Christae:BAABLgAECn8eAAIPAAgJ2Bv5DgAuAgAPAAgJ2Bv5DgAuAgAAAA==.',
Cl='Clementînê:BAAALgAECgIJAgAAAA==.Clemêntine:BAAALgAECgYJBgAAAA==.Clydè:BAABLgAECn9NAAMQAAkJ6RaHFABJAgAQAAgJbheHFABJAgARAAkJQBJEFADPAQAAAA==.Cláncey:BAAALgAECggJDAAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCwAAAA==.Cocytus:BAAALgADCgIJAgABLgAFFAIJBgALAL4UAA==.Colinferal:BAAALgAFFAEJAQAAAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromised:BAABLgAECn8nAAISAAgJExx2CgAiAgASAAgJExx2CgAiAgAAAA==.Conquests:BAAALgAECgEJAQAAAA==.Corelack:BAABLgAFFH8FAAITAAMJ9A6PCwC0AAATAAMJ9A6PCwC0AAAAAA==.',
Cr='Crwth:BAAALgAECgEJAQAAAA==.',
Cu='Cupis:BAAALgAECgQJBAAAAA==.Curendae:BAABLgAECn8kAAIBAAgJKhYeLgDSAQABAAgJKhYeLgDSAQAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8TAAINAAUJoxoNOQBHAQANAAUJoxoNOQBHAQAuAAQKfxgAAg0ACQktGDxMAFICAA0ACQktGDxMAFICAAAA.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAABLgAECn8VAAMQAAYJEQQlQwCmAAAQAAYJEQQlQwCmAAAFAAMJxgNZYwBJAAAAAA==.',
De='Deadlee:BAAALgADCgEJAQAAAA==.Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Delicious:BAEALgAFFAIJAgABLgAFFAYJFQANACYRAA==.Despair:BAAALgADCggJDgABLgAFFAMJCAABACseAA==.',
Di='Dice:BAACLgAFFH8JAAIUAAQJwhd+AgBUAQAUAAQJwhd+AgBUAQAuAAQKfygAAhQACQlqIaUAAAMDABQACQlqIaUAAAMDAAAA.Disturbd:BAACLgAFFH8OAAMVAAUJ5ApISQAkAQAVAAQJ5ApISQAkAQAJAAEJAAAeOgAAAAAuAAQKfxUAAxUACQkZC3hKAJsBABUACQkZC3hKAJsBAAkABAmJAMY9AFsAAAAA.Disturbian:BAAALgAFFAIJAwABLgAFFAUJDgAVAOQKAA==.Dixierecht:BAABLgAECn8gAAIWAAgJbhvZDgBfAgAWAAgJbhvZDgBfAgAAAA==.',
Do='Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drunkenhealz:BAAALgAECgQJCAAAAA==.Drvargas:BAAALgAECgQJBwAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
['Dè']='Dèrty:BAAALgAECgIJAgAAAA==.',
El='Elenestern:BAEBLgAECn8YAAINAAgJHwmLcwBTAQANAAgJHwmLcwBTAQAAAA==.Elmo:BAABLgAECn8fAAMNAAgJzhPmRwDAAQANAAgJdRPmRwDAAQAXAAEJwxWGDgBBAAAAAA==.',
Em='Emryssa:BAAALgAECgMJDAAAAA==.',
Er='Erosis:BAACLgAFFH8JAAINAAMJKh2WTwAIAQANAAMJKh2WTwAIAQAuAAQKfyEAAg0ACAkiIwIvALYCAA0ACAkiIwIvALYCAAAA.',
Ez='Ezaratren:BAAALgAECgUJCQABLgAFFAMJBQATAPQOAA==.',
Fa='Fakêr:BAAALgADCgEJAQAAAA==.',
Fe='Fear:BAACLgAFFH8FAAILAAMJMxu+HQANAQALAAMJMxu+HQANAQAuAAQKfyYAAwsACAl8IOgrAF8CAAsACAl8IOgrAF8CAAwABQkbFk4bAHIBAAAA.Felcatalyist:BAABLgAECn8fAAMVAAgJvRgcYwDKAQAVAAgJHBYcYwDKAQAJAAgJXA21GgAvAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAABLgAECn8VAAIWAAcJ+hBgKwBmAQAWAAcJ+hBgKwBmAQAAAA==.Felysria:BAAALgAECgQJAgAAAA==.',
Fi='Fistitresk:BAAALgADCgQJBAABLgAECgcJEgADAAAAAA==.Fistofwayne:BAAALgAECgYJDgABLgAFFAQJDgAYALQeAA==.',
Ga='Gakopozy:BAAALgAECgYJCQAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIVAAMJvBEhJwD7AAAVAAMJvBEhJwD7AAAAAA==.',
Gl='Glorrex:BAAALgADCgYJBgAAAA==.',
Go='Gongsho:BAAALgADCggJDwAAAA==.',
Gr='Grïmyst:BAAALgAECgEJAQABLgAFFAMJBQATAPQOAA==.',
Gu='Guldán:BAAALgAECgYJDgAAAA==.',
Gw='Gwydre:BAACLgAFFH8RAAIJAAQJaCDsBwBzAQAJAAQJaCDsBwBzAQAuAAQKfxUAAgkACAnpHrMMAOoBAAkACAnpHrMMAOoBAAAA.',
Ha='Havran:BAAALgAECgQJBAABLgAECgkJPgATABcXAA==.Havrin:BAABLgAECn8+AAMTAAkJFxe5CQDkAQATAAkJFxe5CQDkAQAZAAEJQhLgMQA7AAAAAA==.',
He='Headshots:BAACLgAFFH8IAAIBAAMJKx5oLgACAQABAAMJKx5oLgACAQAuAAQKfyYAAgEACQnIHV0UAJMCAAEACQnIHV0UAJMCAAAA.Hexatar:BAAALgAECgQJBAAAAA==.',
Hk='Hkia:BAAALgADCgUJBwAAAA==.',
Ho='Holmie:BAAALgADCgkJCgAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogaplop:BAACLgAFFH8TAAIVAAUJkyalDwC8AQAVAAUJkyalDwC8AQAuAAQKfzUAAxUACQmlIwMUAAMDABUACQlWIQMUAAMDAAkACAlFIYQFAJMCAAAA.',
Hu='Huamulan:BAABLgAECn8zAAICAAgJWQXhigAPAQACAAgJWQXhigAPAQAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAECggJJwANAMQaAA==.Ibchilling:BAABLgAECn8nAAINAAgJxBpGNAAGAgANAAgJxBpGNAAGAgAAAA==.Ibcorrupted:BAAALgAECgUJCQABLgAECggJJwANAMQaAA==.',
Ic='Icarrus:BAACLgAFFH8IAAIFAAMJdgyEIAC0AAAFAAMJdgyEIAC0AAAuAAQKfyoAAwUACAniHIMWAPMBAAUACAniHIMWAPMBABAABAmQE0lAALAAAAEuAAQKBgkUABUA0xkA.Icarus:BAAALgADCgEJAQABLgAECgYJFAAVANMZAA==.Iccarus:BAAALgAECgUJBQABLgAECgYJFAAVANMZAA==.Icebone:BAAALgAECgcJCgABLgAECgcJEQADAAAAAA==.',
Ig='Ignis:BAABLgAECn8UAAIVAAYJ0xnwbABBAQAVAAYJ0xnwbABBAQAAAA==.',
Il='Illioch:BAAALgAECgEJAQAAAA==.',
Im='Imaway:BAAALgAECgEJAQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJCwAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwADAAAAAA==.',
Ja='Jackbfistn:BAAALgAECgcJEQAAAA==.Jaskim:BAAALgAECggJDwAAAA==.',
Je='Jeses:BAAALgAECgQJBQABLgAECggJKQACAL4VAA==.',
Jo='Jolty:BAAALgAECgEJAQABLgAFFAQJDwAVACUeAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAAALgAECgYJCwAAAA==.',
Jy='Jyundiel:BAAALgADCgYJBgABLgADCgYJBgADAAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kaazaama:BAAALgADCgYJBgAAAA==.Kahtonah:BAAALgADCgMJAwAAAA==.Kalessin:BAAALgADCgkJBQAAAA==.Kaltaan:BAABLgAECn8gAAMaAAgJ1SFxBwC2AgAaAAgJ1SFxBwC2AgAPAAQJUh8jPABKAQAAAA==.Karasan:BAABLgAECn8cAAIBAAgJOhlOMQDFAQABAAgJOhlOMQDFAQAAAA==.Karenas:BAABLgAECn8YAAMNAAgJpBmCVAA7AgANAAgJpBmCVAA7AgAXAAIJ4QqZFgBmAAAAAA==.Karr:BAAALgAECgcJDQAAAA==.Kataraara:BAACLgAFFH8HAAIRAAQJRiAGCgCCAQARAAQJRiAGCgCCAQAuAAQKfxcAAhEACAntJN4EADwDABEACAntJN4EADwDAAEuAAUUBQkQAAkAHiYA.Katbeans:BAABLgAECn8iAAQFAAgJ8xvQDABoAgAFAAgJ8xvQDABoAgARAAQJpguRYgC4AAAQAAEJJhZUZwA/AAAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.Katrielle:BAAALgAECgUJBQAAAA==.',
Ke='Kelicemoon:BAABLgAECn8kAAMLAAgJIQoAkQDbAAALAAcJ+ggAkQDbAAAMAAcJIAeBJQBWAAABLgAECgkJKwAVANcTAA==.Kemono:BAAALgADCgYJBgAAAA==.',
Kh='Khaliope:BAABLgAECn8xAAIbAAkJigwsYACAAQAbAAkJigwsYACAAQAAAA==.',
Ki='Kiara:BAACLgAFFH8OAAIcAAQJVxqsDgBIAQAcAAQJVxqsDgBIAQAuAAQKfyYAAxwACQlpH1QIALUCABwACQlpH1QIALUCAB0AAQnFCeptADIAAAAA.Kiryu:BAAALgAECgUJBQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgMJAwAAAA==.',
Kr='Krogers:BAAALgAECgMJBQAAAA==.',
Ku='Kumojo:BAAALgAECgkJAgAAAA==.',
Ky='Kyndlearya:BAAALgADCgEJAQAAAA==.',
['Kû']='Kûrr:BAAALgAECgEJAQABLgAECggJDAADAAAAAA==.',
La='Lahrnaon:BAAALgAECgcJDwAAAA==.Laxeron:BAABLgAECn8eAAIIAAgJnyTNBQDJAgAIAAgJnyTNBQDJAgAAAA==.',
Le='Leotherassy:BAAALgAECgIJAwAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgAECgYJBwAAAA==.',
Lo='Lotiel:BAAALgAECgMJCQABLgAFFAQJCQAeAKMNAA==.',
Lu='Lucrecia:BAABLgAECn8WAAMbAAYJbB0oUgCuAQAbAAUJ2iEoUgCuAQAfAAEJswudLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJEgAAAA==.',
Ma='Madeye:BAAALgADCgQJBAAAAA==.Mal:BAAALgADCgkJCQABLgAECgYJCgADAAAAAA==.Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAABLgAECn8aAAICAAgJcQsagwAdAQACAAgJcQsagwAdAQAAAA==.Mcfeast:BAABLgAECn8WAAIgAAcJNA83JQBKAQAgAAcJNA83JQBKAQAAAA==.',
Me='Medra:BAABLgAECn8fAAIIAAgJ6xURHgCuAQAIAAgJ6xURHgCuAQAAAA==.Meowdi:BAAALgADCgkJBQAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAABLgAECn8kAAINAAcJAQZwnQAFAQANAAcJAQZwnQAFAQAAAA==.',
Mi='Minibone:BAAALgAECgMJAwABLgAECgcJEQADAAAAAA==.',
Mo='Monana:BAAALgADCgkJBQAAAA==.Morar:BAAALgAECgIJBAAAAA==.Morul:BAAALgAECgQJBAAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgUJCAAAAA==.',
Na='Nanija:BAAALgADCgkJBQAAAA==.',
Ne='Nezrin:BAAALgADCgEJAQAAAA==.',
Ni='Nightcat:BAAALgAECgEJAQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbane:BAAALgADCgYJBgABLgAECggJFwACAKAgAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Niteshiftah:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgQJBAAAAA==.Nixie:BAABLgAECn8iAAIeAAgJYgbaVAD3AAAeAAgJYgbaVAD3AAAAAA==.',
No='Nobonesjones:BAACLgAFFH8LAAISAAUJlQacBgDfAAASAAUJlQacBgDfAAAuAAQKfxsAAhIACQlPFjMeAM4BABIACQlPFjMeAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAACLgAFFH8JAAMLAAMJ+hx5ZACoAAALAAIJ8x15ZACoAAAMAAEJChtWFwBPAAAuAAQKfyIAAwsACAkQI8cjABQCAAsABgmgIscjABQCAAwABQm+HzkaAHsBAAAA.',
Ol='Oliiver:BAABLgAECn8cAAIBAAkJXB6qEwBrAgABAAkJXB6qEwBrAgAAAA==.',
Om='Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAADAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAABLgAECn8hAAIbAAgJoiBIFgBRAgAbAAgJoiBIFgBRAgAAAA==.',
Pa='Panaceus:BAABLgAECn83AAIcAAkJ1iIDAQB8AwAcAAkJ1iIDAQB8AwAAAA==.Paragon:BAAALgADCgkJDQABLgAFFAMJDgAVAFYgAA==.Patron:BAAALgADCgIJAwAAAA==.',
Pe='Perennial:BAAALgAECgYJCQAAAA==.Perpetrator:BAAALgAECgEJAgAAAA==.',
Ph='Phreeq:BAEALgAECgYJCgABLgAECgYJGgAWAMwTAA==.Phrequency:BAEBLgAECn8aAAMWAAYJzBM4KwBnAQAWAAYJzBM4KwBnAQACAAQJzRMuyAD4AAAAAA==.',
Pi='Piety:BAAALgADCgIJAgAAAA==.Pig:BAAALgAECgEJAQABLgAFFAUJEwAVAJMmAA==.',
Pl='Playingwow:BAAALgAECgcJEQAAAA==.Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAACLgAFFH8JAAIJAAMJbBQPFwDMAAAJAAMJbBQPFwDMAAAuAAQKfzAAAgkACAmEHjMIAEkCAAkACAmEHjMIAEkCAAAA.',
Pr='Profang:BAAALgADCgUJAwAAAA==.',
Py='Pyrelic:BAABLgAFFH8PAAIQAAUJgRpMCABKAQAQAAUJgRpMCABKAQAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAQJEQAJAGggAA==.',
['Pö']='Pöncho:BAAALgADCgMJAwAAAA==.',
Qa='Qayllera:BAAALgADCgkJEQAAAA==.',
Qe='Qelcie:BAAALgAECgMJAwAAAA==.',
Qu='Quizet:BAAALgADCgYJCAAAAA==.',
Ra='Radicchio:BAAALgADCgkJBQAAAA==.Radkeem:BAABLgAECn8UAAIJAAcJGRzKFABxAQAJAAcJGRzKFABxAQAAAA==.Raf:BAAALgAECgYJBwAAAA==.Raizo:BAAALgAECgEJAQAAAA==.Rakeem:BAAALgAECgcJEAABLgAECgcJFAAJABkcAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.',
Re='Redtoxin:BAAALgADCgkJBgAAAA==.Reilley:BAACLgAFFH8QAAIVAAQJGxp1OQBDAQAVAAQJGxp1OQBDAQAuAAQKfyoAAhUACAmaIYkSAJoCABUACAmaIYkSAJoCAAAA.Reilleÿ:BAAALgAECgQJBAABLgAFFAQJEAAVABsaAA==.Reko:BAAALgAECgQJAwAAAA==.Remorsa:BAAALgAECgUJDgAAAA==.Renni:BAABLgAECn8nAAILAAkJQxNMLwDcAQALAAkJQxNMLwDcAQAAAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8kAAIWAAkJLBbkGwDYAQAWAAkJLBbkGwDYAQAAAA==.',
Ro='Rosealia:BAAALgAECgYJEgAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAACLgAFFH8HAAIHAAMJoQiLGwDbAAAHAAMJoQiLGwDbAAAuAAQKfzwAAgcACQlsHb0EAKwCAAcACQlsHb0EAKwCAAAA.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Sacon:BAAALgADCgcJBwABLgAECgYJCgADAAAAAA==.Saintzan:BAAALgAECgcJDQAAAA==.Salivan:BAAALgAECgUJCgAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJCwABLgAECggJHwACAJETAA==.Sathariel:BAAALgAECgIJAgAAAA==.',
Sc='Scalyboyos:BAABLgAECn8gAAIcAAgJcQvJEgBRAQAcAAgJcQvJEgBRAQAAAA==.Schmoop:BAACLgAFFH8HAAIgAAUJKCA1BwCMAQAgAAUJKCA1BwCMAQAuAAQKfyQABCAACAmUIoEPAIwCACAACAmUIoEPAIwCAA8ABgmLGswiAGQBABoAAQnxEGNWADQAAAEuAAUUBQkTABUAkyYA.',
Se='Seldaria:BAAALgAECgYJEAAAAA==.Senza:BAABLgAECn8VAAICAAYJUAllpADkAAACAAYJUAllpADkAAAAAA==.Senzyri:BAABLgAECn8iAAIBAAgJrxMMQgCEAQABAAgJrxMMQgCEAQAAAA==.Sephirath:BAAALgAECgIJAgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECgcJEQADAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgADAAAAAA==.',
Sh='Shamagoth:BAAALgADCgEJAQAAAA==.Shambhala:BAAALgADCgcJDQAAAA==.Shoes:BAAALgAECgUJBwAAAA==.',
Si='Simic:BAABLgAECn8kAAIJAAgJDg8uFwBUAQAJAAgJDg8uFwBUAQAAAA==.',
Sm='Smokeace:BAAALgADCgYJBgAAAA==.',
Sn='Snowthistle:BAAALgAECgYJEAAAAA==.',
So='Sorle:BAAALgADCgYJCQABLgAECggJHwAIAOsVAA==.Soulnãris:BAAALgAECgcJCQAAAA==.',
Sp='Spin:BAAALgAFFAIJAwAAAA==.Spudpal:BAAALgADCgEJAQABLgAECggJIAAaANUhAA==.Spyro:BAAALgADCgUJBQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgEJAQAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Stonymahoney:BAABLgAECn88AAICAAkJjhpMFwB4AgACAAkJjhpMFwB4AgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Sumorna:BAAALgAECgEJAQAAAA==.Suraisu:BAABLgAECn8rAAIIAAgJxSOTBgC5AgAIAAgJxSOTBgC5AgAAAA==.Suê:BAAALgADCgEJAQABLgADCgQJBAADAAAAAA==.',
Sv='Sveela:BAACLgAFFH8IAAITAAMJzhcJCADqAAATAAMJzhcJCADqAAAuAAQKfyIAAhMACAnlIcEDAMoCABMACAnlIcEDAMoCAAAA.Sveelaa:BAABLgAECn8eAAIBAAgJrRkPIgANAgABAAgJrRkPIgANAgABLgAFFAMJCAATAM4XAA==.Sveella:BAAALgADCgEJAQABLgAFFAMJCAATAM4XAA==.',
Sw='Swampjimmy:BAAALgAECgYJCAAAAA==.',
Sy='Sylrin:BAAALgADCgcJCgAAAA==.Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgYJBwAAAA==.Tacocat:BAABLgAECn80AAIPAAkJmh7uBADzAgAPAAkJmh7uBADzAgAAAA==.Talras:BAAALgADCgkJDAAAAA==.',
Te='Temlock:BAABLgAECn8vAAILAAgJzhgsMQBIAgALAAgJzhgsMQBIAgABLgAECgkJLgAJAB0hAA==.Tempest:BAAALgAECgUJBQABLgAFFAMJDgAVAFYgAA==.Temtank:BAABLgAECn8uAAIJAAkJHSFvAgD5AgAJAAkJHSFvAgD5AgAAAA==.',
Tr='Trak:BAABLgAECn8UAAIdAAgJKAzmMwAtAQAdAAgJKAzmMwAtAQAAAA==.Trukarak:BAABLgAECn8fAAICAAgJkRNdVwB7AQACAAgJkRNdVwB7AQAAAA==.',
Tu='Tuvaquitamuu:BAAALgAECgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Valenti:BAABLgAECn8aAAMhAAYJ7BDsGQD0AAAhAAYJ7BDsGQD0AAACAAEJ0AZ4SwEpAAAAAA==.Valor:BAABLgAECn8kAAICAAcJhiF9MAD2AQACAAcJhiF9MAD2AQAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.Velynesti:BAAALgAECgQJBAAAAA==.',
Vi='Vipershot:BAAALgADCggJDwAAAA==.',
Wa='Warlode:BAAALgADCgkJBQAAAA==.',
We='Weewoo:BAAALgADCgcJCwAAAA==.',
Wi='Wildama:BAABLgAECn8aAAIeAAgJLAzxTAATAQAeAAgJLAzxTAATAQAAAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgYJBgABLgAECgkJFQACAOMbAA==.',
Xi='Xiao:BAABLgAECn8cAAIFAAkJJRbKFAAEAgAFAAkJJRbKFAAEAgAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAFFAEJAQADAAAAAA==.',
Ya='Yahargul:BAABLgAECn8aAAIgAAcJTAwAKwAlAQAgAAcJTAwAKwAlAQAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Za='Zaterok:BAAALgAECgMJAwABLgAECggJHwACAJETAA==.',
Ze='Zeik:BAABLgAECn8gAAMhAAkJkBfZCADuAQAhAAkJkBfZCADuAQACAAMJngrn+gBgAAAAAA==.Zephyrgosa:BAAALgADCgcJDgAAAA==.Zerase:BAAALgADCgkJBQAAAA==.',
Zu='Zucco:BAAALgAECgkJCQAAAA==.Zuufungo:BAAALgAECgUJBQABLgAECggJIAAaANUhAA==.',
['Zí']='Zíx:BAABLgAECn8kAAIiAAgJ3w/vGAAlAQAiAAgJ3w/vGAAlAQAAAA==.',
['Àl']='Àlcàrà:BAAALgAECgYJEQAAAA==.',
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
