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

local lookup = {'Evoker-Augmentation','Druid-Balance','Druid-Restoration','Warlock-Demonology','Mage-Frost','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Priest-Holy','Priest-Shadow','Paladin-Retribution','Warrior-Protection','Shaman-Restoration','Paladin-Holy','Mage-Fire','Priest-Discipline','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Monk-Windwalker','Warlock-Destruction','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','Monk-Brewmaster','Shaman-Enhancement','Rogue-Outlaw','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Hunter-Marksmanship',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-06-27',data={Ac='Ackrenoth:BAABLgAECn81AAIBAAkJfhS1GgAAAgABAAkJfhS1GgAAAgAAAA==.',
Ad='Adynn:BAACLgAFFH8MAAMCAAMJ+R1GCAACAQACAAMJ+R1GCAACAQADAAEJQhK1bwA3AAAuAAQKfzwAAwIACQneJXgBAGwDAAIACQneJXgBAGwDAAMAAgkyHYCjAGoAAAAA.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aeru:BAAALgAECgYJBgAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAABLgAECn8UAAIEAAYJDwwAqADyAAAEAAYJDwwAqADyAAAAAA==.',
Ag='Agrathayn:BAAALgAECgYJCgAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJOAAFAMMaAA==.Aittoth:BAAALgADCgEJAQAAAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alanatre:BAAALgADCggJDgAAAA==.Alenoth:BAAALgAECgMJAwAAAA==.Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAACLgAFFH8KAAIGAAMJqiHMCAAEAQAGAAMJqiHMCAAEAQAuAAQKfzkAAwYACQkGJiACAFYDAAYACQkGJiACAFYDAAcAAQnpFB90ADkAAAAA.Allyeska:BAAALgAECgUJDgAAAA==.Alnharaelune:BAAALgADCgkJEQAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAABLgAECn8iAAIIAAgJDBErWQB8AQAIAAgJDBErWQB8AQAAAA==.',
An='Anali:BAACLgAFFH8HAAIJAAQJaBU7FgAOAQAJAAQJaBU7FgAOAQAuAAQKfx4AAgkACQlnIMcIAN0CAAkACQlnIMcIAN0CAAAA.Anani:BAABLgAECn82AAIKAAkJDhMTGgD1AQAKAAkJDhMTGgD1AQAAAA==.Andavin:BAABLgAECn8tAAILAAYJ2ARNAwG0AAALAAYJ2ARNAwG0AAAAAA==.Angreifer:BAACLgAFFH8YAAIMAAYJsxzTCQCTAQAMAAYJsxzTCQCTAQAuAAQKfy8ABAwACQmvHOsLAC4CAAwACAnBHusLAC4CAAYACQn1DmEyAOIBAAcAAgnfDiF7AC4AAAAA.Angron:BAAALgAFFAMJBAAAAA==.Anoana:BAAALgADCggJCAAAAA==.Anori:BAABLgAECn8nAAICAAgJqBh2GwDvAQACAAgJqBh2GwDvAQAAAA==.',
Ao='Aonar:BAABLgAECn8bAAINAAYJhBRvYgA0AQANAAYJhBRvYgA0AQAAAA==.',
Ar='Arc:BAABLgAECn86AAIEAAkJTCNiBgAqAwAEAAkJTCNiBgAqAwAAAA==.Archenteron:BAAALgAECgQJCQAAAA==.Arctat:BAAALgAECgMJAwAAAA==.Ardorcinder:BAAALgAECgYJEAAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJDwABLgAECggJKgANAPUfAA==.Artea:BAAALgAECgYJCAAAAA==.',
As='Asbjorne:BAABLgAECn8xAAIOAAkJORvIAABQAgAOAAkJORvIAABQAgAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.Astrayl:BAAALgAECgkJCQAAAA==.',
At='Atryssa:BAAALgAECgUJBQAAAA==.',
Au='Audi:BAAALgADCgYJDAAAAA==.Augamand:BAAALgAECgYJCAAAAA==.Autumnmoon:BAABLgAECn89AAIPAAgJKxKRAAAnAQAPAAgJKxKRAAAnAQAAAA==.',
Av='Avelos:BAACLgAFFH8SAAQJAAYJCAc/EQBFAQAJAAYJCAc/EQBFAQAKAAIJWAO1NQBnAAAQAAEJ+AeQTQA6AAAuAAQKfzAABAkACQm4GbkbAOoBAAkACQm4GbkbAOoBABAABQktBspGAIYAAAoAAgmuDK9zAFoAAAAA.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAABLgAECn8uAAURAAkJlByhBwB6AgARAAkJ8RuhBwB6AgACAAYJZAoQTgDxAAASAAEJ3BweQwBVAAADAAIJIwN8yQA3AAAAAA==.Ayzmist:BAAALgAECgYJCQAAAA==.Ayzmyth:BAABLgAECn8lAAITAAcJbw94RwBOAQATAAcJbw94RwBOAQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAINAAcJ7yAVDwCgAgANAAcJ7yAVDwCgAgAAAA==.Bashra:BAAALgAECgYJEQAAAA==.',
Be='Beasic:BAABLgAECn9BAAMUAAkJWg3xVgDgAAAUAAcJxwnxVgDgAAANAAYJyAF+sQBmAAAAAA==.Beastmode:BAAALgAECggJDwABLgAFFAMJAwAVAAAAAA==.Beletili:BAACLgAFFH8IAAIJAAMJhBgsBgDSAAAJAAMJhBgsBgDSAAAuAAQKfzcAAgkACQnnFxAQAGkCAAkACQnnFxAQAGkCAAAA.Bellissimo:BAAALgAECgEJAQABLgAECgkJMwANAEoXAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn80AAMWAAkJQxIPFgD5AAAIAAkJJBEtUwCrAQAWAAYJ3BUPFgD5AAAAAA==.Birdman:BAABLgAECn8aAAMNAAYJJBEKXwA/AQANAAYJJBEKXwA/AQAUAAYJIRMdRAAiAQABLgAECgkJNAAWAEMSAA==.Bismuth:BAABLgAECn8WAAIXAAcJzQ7dLgAOAQAXAAcJzQ7dLgAOAQAAAA==.',
Bj='Bjornin:BAAALgAECgEJAQAAAA==.',
Bl='Blackraven:BAABLgAECn8lAAMYAAgJpx0fNwABAgAYAAYJKB4fNwABAgAZAAcJgBhNHwCiAQAAAA==.Blatendrg:BAABLgAECn8vAAIBAAkJ9BB6JwCnAQABAAkJ9BB6JwCnAQAAAA==.Blindcloud:BAABLgAECn8fAAIXAAgJIwfkBgCBAAAXAAgJIwfkBgCBAAAAAA==.',
Bo='Boot:BAABLgAECn8jAAIOAAgJoxbFKQDAAQAOAAgJoxbFKQDAAQAAAA==.Bophedes:BAABLgAECn8ZAAMaAAgJrRq6OgAVAgAaAAgJrRq6OgAVAgAbAAEJbw4UXwAtAAAAAA==.Borodemonin:BAEBLgAECn8dAAIIAAYJLiRMMAAFAgAIAAYJLiRMMAAFAgABLgAFFAYJFAAKACkkAA==.Bosstun:BAAALgADCgMJAwAAAA==.Bozrohin:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn9CAAIJAAkJkRWDGAAJAgAJAAkJkRWDGAAJAgAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Briawind:BAAALgAECgkJAwAAAA==.Brieanna:BAAALgADCgQJDAAAAA==.Bromith:BAAALgAECgEJAQAAAA==.Brugen:BAAALgAECgcJCgAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calavero:BAAALgAECgYJEAABLgAECggJKgANAPUfAA==.Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgYJDgAAAA==.Cariñosa:BAAALgAECgEJAQAAAA==.Carøline:BAAALgAECgEJAQAAAA==.Caska:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgUJCwAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8xAAMaAAkJlx4hHwCOAgAaAAkJlx4hHwCOAgAcAAEJ3wtJGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgYJEQAAAA==.Charles:BAABLgAECn8tAAIdAAkJlSRZBAATAwAdAAkJlSRZBAATAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiarus:BAAALgADCgkJGAABLgAFFAYJGAAMALMcAA==.Chiot:BAABLgAECn8+AAIMAAkJ7B1nBwCNAgAMAAkJ7B1nBwCNAgAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8lAAMGAAkJAhmXHQABAgAGAAkJ6heXHQABAgAMAAUJbhkiJgABAQAAAA==.Chuga:BAABLgAECn8jAAMEAAgJkQ4hbABkAQAEAAgJnA0hbABkAQAeAAQJHQ2BNABQAAAAAA==.',
Ci='Cimerian:BAABLgAECn8iAAMfAAgJWwzbHwAJAQAfAAcJoA3bHwAJAQALAAUJigURGAGcAAAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECgkJKAANAOYQAA==.',
Co='Cobalticus:BAAALgAECgYJDgAAAA==.Coledarus:BAAALgAFFAIJAgAAAA==.Corange:BAAALgAECgEJAQAAAA==.Corlink:BAAALgAECgEJAQAAAA==.Corlock:BAAALgAECgQJBAAAAA==.Cormech:BAAALgAECgcJEwAAAA==.Cornite:BAABLgAECn8ZAAIaAAkJFw37gABhAQAaAAkJFw37gABhAQAAAA==.Cotolete:BAAALgADCgMJAwAAAA==.',
Cr='Crazy:BAAALgAFFAMJAwAAAA==.Crizzo:BAABLgAECn87AAIYAAkJ6B8mEADPAgAYAAkJ6B8mEADPAgAAAA==.',
Cu='Cuby:BAAALgAECgIJAgAAAA==.',
Cy='Cyndrial:BAAALgADCgYJEgAAAA==.',
Da='Daddyslilgrl:BAABLgAECn8qAAIEAAgJVgUfowD6AAAEAAgJVgUfowD6AAAAAA==.Dakra:BAEBLgAECn80AAMHAAkJKR6tBQCtAgAHAAkJKR6tBQCtAgAMAAEJOwyCVAAvAAAAAA==.Dalamar:BAAALgAFFAMJCQABLgAFFAUJGwAKAJMUAQ==.Dalandis:BAAALgAFFAEJAQAAAA==.Dalyeth:BAABLgAECn8sAAIWAAgJeiX/AQDzAgAWAAgJeiX/AQDzAgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAACLgAFFH8JAAIYAAMJzw09GQCiAAAYAAMJzw09GQCiAAAuAAQKfxQAAhgACAmcHrALAOUCABgACAmcHrALAOUCAAAA.Darkwulf:BAAALgAECgEJAgAAAA==.Daunt:BAABLgAECn8WAAIeAAgJtA/EDQBgAQAeAAgJtA/EDQBgAQABLgAECgkJRwACAPURAA==.',
De='Decypher:BAABLgAECn8pAAISAAkJ+Ba0CQAnAgASAAkJ+Ba0CQAnAgABLgAFFAMJBwAgACwDAA==.Deebz:BAAALgAECgUJDAAAAA==.Deliverance:BAACLgAFFH8bAAIKAAUJkxQrCADbAAAKAAUJkxQrCADbAAAuAAQKfzEAAwoACQnJIZEEAA8DAAoACQnJIZEEAA8DAAkABAnPCmRaAHAAAAAA.Demonablaze:BAAALgAECgIJAwAAAA==.Dentik:BAABLgAECn89AAQDAAkJGBA6OgCsAQADAAkJGBA6OgCsAQARAAIJ4gLVfAAmAAACAAEJDAmLEQAjAAAAAA==.Denuma:BAAALgAECgYJBgAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgcJEAABLgAFFAMJBwAgACwDAA==.Dheriana:BAABLgAFFH8HAAMgAAMJLAOWAQCvAAAgAAMJLAOWAQCvAAAhAAEJPASPGgBEAAAAAA==.',
Di='Diamair:BAABLgAECn8+AAMiAAkJTRk6BAC5AQAFAAkJlBMtTAD3AQAiAAgJGBg6BAC5AQAAAA==.Diamones:BAAALgAECgMJAwAAAA==.Dixiee:BAABLgAECn8WAAIKAAcJbgTRTwDRAAAKAAcJbgTRTwDRAAAAAA==.',
Dn='Dnegelpal:BAABLgAECn8mAAILAAkJUxDXZgCiAQALAAkJUxDXZgCiAQAAAA==.',
Do='Docbison:BAAALgADCgQJCQABLgAECgYJDAAVAAAAAA==.Dodgecharger:BAABLgAECn8gAAINAAYJEgbkhQDSAAANAAYJEgbkhQDSAAAAAA==.Dornix:BAABLgAECn8pAAIEAAgJZyC6LAAmAgAEAAgJZyC6LAAmAgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgcJDAAAAA==.Dragonfood:BAABLgAECn8iAAIYAAgJpw5ZXACQAQAYAAgJpw5ZXACQAQAAAA==.Drakilu:BAABLgAECn9CAAIYAAkJQB6QFACuAgAYAAkJQB6QFACuAgAAAA==.Drakkthor:BAAALgADCgEJAQAAAA==.Drasic:BAACLgAFFH8RAAIDAAMJFRfpNwDNAAADAAMJFRfpNwDNAAAuAAQKfzwAAgMACQmyIXIFAGEDAAMACQmyIXIFAGEDAAAA.Dreamcloud:BAAALgAECgUJBQAAAA==.Dreddscott:BAAALgAECgUJBQABLgAECgkJOgAhADAfAA==.Drophin:BAAALgAECgMJDAAAAA==.Drunken:BAABLgAECn8yAAIjAAgJ3R+vDABrAgAjAAgJ3R+vDABrAgAAAA==.Druphin:BAAALgADCgYJEgAAAA==.Drurok:BAAALgAECgkJCQAAAA==.',
Du='Durward:BAABLgAECn9FAAQaAAkJzyJZCwATAwAaAAkJzyJZCwATAwAbAAUJ/w5dOgCpAAAcAAIJNxdcKgCCAAAAAA==.Duvo:BAABLgAECn8aAAIYAAgJfhqWPADuAQAYAAgJfhqWPADuAQAAAA==.',
Dw='Dwarfo:BAABLgAECn8YAAILAAgJawYjugARAQALAAgJawYjugARAQAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.Dwarvey:BAAALgADCgMJAwAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAABLgAECn8fAAMRAAgJbQfPOQC/AAARAAgJbQfPOQC/AAACAAQJpQDDjQAyAAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIcAAgJlR6GAgCPAgAcAAgJlR6GAgCPAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elansar:BAAALgAECgIJAgAAAA==.Elbarrio:BAABLgAECn8bAAIEAAkJIQKrzAC4AAAEAAkJIQKrzAC4AAAAAA==.Elemental:BAACLgAFFH8OAAMUAAYJfA2IHQAwAQAUAAYJfA2IHQAwAQANAAIJxQpUawBoAAAuAAQKfzgAAxQACQmyHIkNAJACABQACQmyHIkNAJACAA0ACAnaGAseAF0CAAEuAAUUBwkRAAIASAgA.Eleussen:BAAALgAECgMJAwAAAA==.Ellochan:BAAALgAECgEJAQAAAA==.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgAECgQJCAAAAA==.Elloseth:BAABLgAECn8oAAIKAAgJyhvEEwAxAgAKAAgJyhvEEwAxAgAAAA==.Elmorin:BAABLgAECn8UAAIHAAgJgAy2JABAAQAHAAgJgAy2JABAAQAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAABLgAECn8gAAIYAAYJzw6MnAAIAQAYAAYJzw6MnAAIAQAAAA==.',
Ep='Epica:BAABLgAECn8oAAIFAAcJ+xTckABWAQAFAAcJ+xTckABWAQAAAA==.',
Er='Eragonhawk:BAABLgAECn8xAAILAAkJ5B0WAgA4AgALAAkJ5B0WAgA4AgAAAA==.Erelynn:BAAALgAECgQJBAABLgAECgQJBQAVAAAAAA==.Eroldan:BAABLgAECn8kAAMNAAkJyx57DAD2AgANAAkJyx57DAD2AgAUAAQJUA0JZgC0AAAAAA==.Erovianoria:BAACLgAFFH8KAAIYAAMJygWvcQC8AAAYAAMJygWvcQC8AAAuAAQKfykAAhgACQm/Fv8WAIACABgACQm/Fv8WAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.Eräthis:BAAALgAECgMJAwAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAABLgAECn8qAAIXAAgJdyKDCQCSAgAXAAgJdyKDCQCSAgABLgAFFAgJLAAEACQUAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8zAAINAAkJShdpHABpAgANAAkJShdpHABpAgAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Ex='Expire:BAAALgAFFAEJAQAAAA==.',
Fa='Fatalfury:BAABLgAECn8mAAMLAAkJoxopVADNAQALAAgJeBkpVADNAQAOAAQJfRCbUgDuAAAAAA==.Fauxstorm:BAABLgAECn8bAAMkAAUJsBqlGQA3AQAkAAUJsBqlGQA3AQAUAAIJ/BGzowA1AAAAAA==.',
Fi='Finngan:BAABLgAECn8yAAIeAAkJoQ7QCwCCAQAeAAkJoQ7QCwCCAQAAAA==.Fireina:BAABLgAECn8YAAIPAAcJygH5DgBuAAAPAAcJygH5DgBuAAAAAA==.',
Fj='Fjordin:BAAALgAECgYJBgAAAA==.',
Fl='Fluria:BAAALgAECgQJBQAAAA==.',
Fo='Forestkin:BAABLgAECn8cAAIRAAYJhyBKEgDMAQARAAYJhyBKEgDMAQABLgAECggJLAAWAHolAA==.Fossilis:BAABLgAECn8YAAMgAAcJHgVbEwDyAAAgAAcJAQVbEwDyAAAhAAUJ2wIUTwCzAAAAAA==.Foxhope:BAAALgADCgcJDgABLgAECgcJHQAaABodAA==.',
Fr='Frenzyz:BAAALgADCgIJAgAAAA==.Friartuk:BAAALgADCgEJAQAAAA==.Frozenthunda:BAAALgAECgQJCgAAAA==.',
Fu='Furna:BAABLgAECn81AAIQAAgJ+xGLIQDCAQAQAAgJ+xGLIQDCAQAAAA==.',
Fy='Fyahka:BAAALgADCgQJBAAAAA==.Fyon:BAAALgAECgYJCQAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAACLgAFFH8bAAIGAAUJaw18CAAIAQAGAAUJaw18CAAIAQAuAAQKfzYAAgYACQn4FyMYAC0CAAYACQn4FyMYAC0CAAAA.Galileia:BAAALgADCgMJBAAAAA==.',
Gh='Ghorienge:BAAALgAECgYJDwAAAA==.Ghostcat:BAAALgAECgIJAgAAAA==.',
Gi='Gilox:BAABLgAECn8gAAIgAAkJ5BAKCADQAQAgAAkJ5BAKCADQAQAAAA==.',
Gl='Gleefortrees:BAAALgAECgcJDAAAAA==.Glinteastwar:BAAALgAECgMJAwAAAA==.',
Gn='Gndmexia:BAAALgAECgYJEwAAAA==.Gneiss:BAAALgAECgcJEwAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8iAAIDAAkJiCCRBwA/AwADAAkJiCCRBwA/AwAAAA==.',
Gr='Graymon:BAABLgAECn8iAAIGAAYJOBpcOgBcAQAGAAYJOBpcOgBcAQAAAA==.Greebo:BAABLgAECn8iAAIRAAYJVgNVYQBOAAARAAYJVgNVYQBOAAAAAA==.Griknor:BAABLgAECn8fAAMHAAYJRgU/IgDaAAAHAAYJRgU/IgDaAAAGAAQJBgONggBvAAAAAA==.Grimniel:BAAALgAECgIJAwAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAABLgAECn8UAAILAAgJWRtlNQArAgALAAgJWRtlNQArAgAAAA==.Gussie:BAAALgADCgQJBAABLgAECgcJFgAKAG4EAA==.',
Gw='Gwenyver:BAABLgAECn8sAAILAAkJQAOU3ADiAAALAAkJQAOU3ADiAAAAAA==.',
Ha='Hadoukendk:BAAALgAECggJEwAAAA==.Hafaken:BAAALgAECgEJAQAAAA==.Hailthanatos:BAAALgAECgEJAgAAAA==.Hallien:BAAALgADCgEJAQAAAA==.Hamord:BAABLgAECn8jAAIfAAkJtg5fGgBGAQAfAAkJtg5fGgBGAQAAAA==.Hansdelbruk:BAAALgADCgEJAQAAAA==.Hardlight:BAAALgAECgYJDQAAAA==.Harington:BAAALgAECgMJAwAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgAECgQJBAAAAA==.Harliqynn:BAACLgAFFH8GAAIYAAMJ3BuTWQDyAAAYAAMJ3BuTWQDyAAAuAAQKfxwAAhgACQngGu0gAEACABgACQngGu0gAEACAAAA.Harlock:BAABLgAECn8qAAIhAAkJpxz/AADYAQAhAAkJpxz/AADYAQAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.Hazelnuts:BAAALgAECgIJAQAAAA==.',
He='Heartkiller:BAAALgAECgQJBAABLgAECgkJKAAFAPsUAA==.Hellcrazed:BAAALgADCgMJAwABLgAFFAQJDQARAOobAA==.Helleye:BAABLgAECn8fAAIRAAgJPQt8LQD4AAARAAgJPQt8LQD4AAAAAA==.',
Hi='Hiten:BAABLgAECn9CAAQhAAkJxRudCgB5AgAhAAkJvhudCgB5AgAgAAUJRBWIDQBEAQAlAAEJjwiWJgAqAAAAAA==.',
Ho='Hopedaimond:BAABLgAECn8rAAIUAAkJgQ/aMwBsAQAUAAkJgQ/aMwBsAQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8/AAMYAAkJAA45UACyAQAYAAkJAA45UACyAQAZAAYJowP/PwDIAAAAAA==.Husgus:BAAALgAECgIJAgABLgAFFAUJFwACANEQAA==.',
Hy='Hypro:BAABLgAECn8xAAINAAkJeyU7AADXAwANAAkJeyU7AADXAwAAAA==.',
['Há']='Háides:BAAALgADCgIJAgAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIfAAcJByOXBAC6AgAfAAcJByOXBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJEwAAAA==.',
Ie='Iepa:BAAALgAFFAEJAQAAAA==.',
Il='Ilthad:BAABLgAECn84AAMXAAgJ5BirAQCWAQAXAAgJ5BirAQCWAQAIAAEJ9QK0OgEbAAAAAA==.',
Im='Imneth:BAAALgAECgIJAgABLgAECggJHQAiADARAA==.Imperio:BAAALgADCgYJBgAAAA==.Imshalar:BAAALgAECggJEAAAAA==.',
In='Inconcvabull:BAABLgAECn8XAAIEAAgJEAufhQAuAQAEAAgJEAufhQAuAQAAAA==.Inferious:BAAALgAECgUJDwABLgAECggJGQAaAK0aAA==.Infurryating:BAAALgAECgkJBwAAAA==.Inistus:BAAALgAECgQJBAAAAA==.',
Ir='Iralis:BAAALgAECgcJEAAAAA==.Iroar:BAAALgADCgEJAQAAAA==.',
Is='Ischadè:BAAALgAECgMJBAAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgkJEQAAAA==.Itsirk:BAABLgAECn8wAAIOAAkJuxm6FABoAgAOAAkJuxm6FABoAgAAAA==.',
Iz='Izyebelle:BAABLgAECn8qAAMKAAkJ5gGLXwCaAAAKAAkJ5gGLXwCaAAAJAAEJUAGHfwATAAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAABLgAECn83AAIfAAkJUCVjAwDgAgAfAAkJUCVjAwDgAgAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jiayou:BAAALgADCgEJAQAAAA==.Jimmydin:BAACLgAFFH8VAAMOAAUJYB26GQBUAQAOAAQJChu6GQBUAQALAAUJmhSZRQAgAQAuAAQKfzwAAwsACQnKGXUoAGECAAsACQnKGXUoAGECAA4ACQklGbQeACICAAAA.Jix:BAABLgAECn8YAAMeAAgJkhi9DgDeAQAeAAYJtxy9DgDeAQAEAAQJSAxGrQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8xAAQIAAkJhhI5SgCoAQAIAAkJ5RE5SgCoAQAWAAMJyxWlHgCSAAAXAAEJYw4QbwA2AAAAAA==.',
Ju='Juego:BAAALgADCgEJAQAAAA==.Julkan:BAAALgAECgQJBgAAAA==.Junhoong:BAABLgAECn9GAAILAAkJQBZIQQADAgALAAkJQBZIQQADAgAAAA==.',
Jy='Jynnysa:BAAALgAECgcJEAABLgAECgcJMQAfAA4gAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAABLgAECn8dAAIHAAgJIBgQDwD9AQAHAAgJIBgQDwD9AQAAAA==.Kairoll:BAABLgAECn8mAAIJAAkJuBVYGAAKAgAJAAkJuBVYGAAKAgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Kannah:BAAALgAECggJEwAAAA==.Karaa:BAABLgAECn83AAITAAkJZgfxCgC7AAATAAkJZgfxCgC7AAAAAA==.Kariena:BAABLgAECn8pAAIYAAgJ5h4XIABnAgAYAAgJ5h4XIABnAgAAAA==.Katesluage:BAABLgAECn84AAIFAAkJwxrQNwA5AgAFAAkJwxrQNwA5AgAAAA==.Kawrrl:BAAALgAECgEJAwAAAA==.Kayallinne:BAAALgAECgYJBgABLgAECggJKQAYAOYeAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJOAAFAMMaAA==.',
Ke='Keeya:BAABLgAECn9IAAIaAAkJtxMzAwDFAQAaAAkJtxMzAwDFAQAAAA==.Kelina:BAAALgAECgIJAwAAAA==.Kelkan:BAAALgAECgEJAQAAAA==.Kendari:BAABLgAECn8cAAMaAAkJzwmxwgD6AAAaAAQJzw+xwgD6AAAbAAYJ/QRVQwCCAAAAAA==.Kernasas:BAABLgAECn9GAAIeAAgJuBbLCAC+AQAeAAgJuBbLCAC+AQAAAA==.Keslynn:BAAALgAECgIJAwABLgAECggJKQAYAOYeAA==.Ketrani:BAAALgAECgEJAgABLgAECggJKQAYAOYeAA==.',
Kh='Khiari:BAAALgAECgYJDwABLgAECggJOQALAI4XAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAABLgAECn8UAAMmAAgJfw3nFgAQAQAmAAYJpQ7nFgAQAQAEAAUJHgiGvADRAAAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJKQAEAGcgAA==.Kirtiao:BAAALgAECgEJAgABLgAECggJKQAYAOYeAA==.Kitalidie:BAAALgAECgQJBgABLgAECggJKQAYAOYeAA==.Kizaraan:BAABLgAECn8kAAMnAAkJNAa3AQDjAAAnAAgJzQW3AQDjAAAoAAMJzwLXIABNAAAAAA==.',
Kl='Kleyntamar:BAABLgAECn8aAAIDAAYJJBbdRwBwAQADAAYJJBbdRwBwAQAAAA==.',
Kn='Knyghtly:BAAALgAECgkJAwAAAA==.',
Ko='Konstantien:BAAALgAECgYJBgAAAA==.Koshamunzo:BAAALgADCgYJBgAAAA==.',
Kr='Kreios:BAAALgAECgkJBwAAAA==.Kritt:BAAALgAECgYJDQAAAA==.Kritter:BAAALgAECgYJDwAAAA==.Krohm:BAABLgAECn8uAAMLAAkJcyNaCAAoAwALAAkJcyNaCAAoAwAfAAEJ8hg9SQBEAAAAAA==.Krostana:BAAALgADCgEJAQAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgAECgYJDwAAAA==.Kungfuey:BAAALgAECgUJBQAAAA==.Kupau:BAAALgAECgQJBAAAAA==.Kurogami:BAAALgAFFAIJAgAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Landstrider:BAAALgAFFAIJAgABLgAFFAcJEQACAEgIAA==.Lanss:BAACLgAFFH8HAAIMAAMJoxyLFQDzAAAMAAMJoxyLFQDzAAAuAAQKf0wAAgwACQkRJbsBAD0DAAwACQkRJbsBAD0DAAAA.Larachel:BAABLgAECn8dAAMJAAgJRR1vDQCPAgAJAAgJRR1vDQCPAgAKAAcJShbXJwCQAQAAAA==.Laur:BAABLgAECn8uAAIKAAkJaxMNHwDNAQAKAAkJaxMNHwDNAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8jAAILAAkJUBwdLQBMAgALAAkJUBwdLQBMAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAABLgAECn8iAAIfAAYJoRyFGQBNAQAfAAYJoRyFGQBNAQAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAwAAAA==.Lilipo:BAABLgAECn9KAAIdAAgJkQ5CAgAzAQAdAAgJkQ5CAgAzAQAAAA==.Liltara:BAABLgAECn8vAAIFAAcJqgJz9gC7AAAFAAcJqgJz9gC7AAAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llamatotems:BAAALgAECgcJBwABLgAECgkJRAAaAMoNAA==.Llanz:BAAALgADCgkJKgAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAACLgAFFH8LAAIEAAMJawcBhgC6AAAEAAMJawcBhgC6AAAuAAQKfy0AAgQACAm+FK1YAJMBAAQACAm+FK1YAJMBAAAA.Lokdan:BAAALgAECgYJCQAAAA==.Loppy:BAAALgAECgIJAgAAAA==.Loula:BAABLgAECn8pAAIFAAkJHgOhzAD3AAAFAAkJHgOhzAD3AAAAAA==.Lowryder:BAACLgAFFH8MAAIhAAQJTQtSIQAbAQAhAAQJTQtSIQAbAQAuAAQKfyIAAyEACQniFEwUAAACACEACQniFEwUAAACACAAAQmbBmIgADEAAAAA.Loxes:BAAALgAECgcJDQABLgAECgYJCwAVAAAAAA==.Loxy:BAAALgAECgUJDAAAAA==.',
Lu='Lukam:BAAALgAECgUJEAAAAA==.Lunaellana:BAAALgAECgQJBAAAAA==.Lus:BAABLgAECn8UAAMEAAYJsRfzegBmAQAEAAYJsRfzegBmAQAeAAIJuggxUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAACLgAFFH8FAAIDAAMJegzyRgCaAAADAAMJegzyRgCaAAAuAAQKfxsABQMACAmAHdUUAKMCAAMACAmAHdUUAKMCABEABQlcDFNOAHMAABIAAglTBFRPADoAAAIAAglPASSsAA4AAAAA.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
['Lü']='Lüvpüp:BAAALgAFFAEJAgAAAA==.',
Ma='Magicfang:BAAALgAECgYJCwAAAA==.Maiku:BAABLgAECn8/AAIEAAkJcRVBMQATAgAEAAkJcRVBMQATAgAAAA==.Makado:BAACLgAFFH8HAAQmAAQJ2QHPEACLAAAmAAMJtwHPEACLAAAeAAIJmwGiGQBgAAAEAAEJmgEU2AApAAAuAAQKfyAABB4ACAnaCHgvAP0AAB4ABwlAB3gvAP0AAAQABQngBdnIAL4AACYABQm9BysjAKgAAAAA.Makaris:BAAALgADCgQJBQAAAA==.Makaveli:BAABLgAFFH8IAAIbAAMJGAqIDACTAAAbAAMJGAqIDACTAAAAAA==.Maknanimus:BAAALgADCgQJBAAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAABLgAECn8gAAIEAAYJpBrbXQCFAQAEAAYJpBrbXQCFAQAAAA==.Matheniel:BAAALgAECgEJAQAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Matua:BAAALgAECgEJBAAAAA==.Maycee:BAABLgAECn8UAAIYAAcJcg59dABWAQAYAAcJcg59dABWAQAAAA==.',
Mc='Mcat:BAAALgAECgMJBQAAAA==.Mcnaugh:BAABLgAECn8xAAMbAAkJyA8SAwD9AAAbAAkJEw8SAwD9AAAaAAQJKRSb6ADKAAAAAA==.Mcsaltface:BAABLgAECn8oAAILAAkJnhpdBACYAQALAAkJnhpdBACYAQAAAA==.',
Me='Meddic:BAAALgAECgYJCAAAAA==.Menaras:BAACLgAFFH8KAAMNAAMJfw7dWwCVAAANAAMJfw7dWwCVAAAUAAIJZgJ0TQBhAAAuAAQKfywAAxQACQkmHTsSAJECABQACQkmHTsSAJECAA0ACAmOFxNNAHwBAAAA.Menarot:BAABLgAFFH8GAAIaAAMJtQcStQC8AAAaAAMJtQcStQC8AAABLgAFFAMJCgANAH8OAA==.Mendais:BAAALgADCgkJCwAAAA==.Metgot:BAAALgAECgEJAQAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAFFAYJGAAMALMcAA==.',
Mi='Mikeydluffy:BAABLgAECn8aAAIdAAkJVBU0FgAGAgAdAAkJVBU0FgAGAgAAAA==.Mirosberto:BAAALgAECgcJDQABLgAFFAYJFgAjAFUXAA==.Mirosmundo:BAACLgAFFH8WAAIjAAYJVRdLFACBAQAjAAYJVRdLFACBAQAuAAQKfzEAAiMACQmrH9oIAPkCACMACQmrH9oIAPkCAAAA.Mistfit:BAABLgAECn8WAAITAAcJSBOYPgB0AQATAAcJSBOYPgB0AQAAAA==.Miyagi:BAAALgAECgYJEAAAAA==.Miyu:BAACLgAFFH8JAAIJAAMJPxBjCACgAAAJAAMJPxBjCACgAAAuAAQKfzkABAoACQnpGs0bAOYBAAoACAk6Gs0bAOYBAAkACQkSE9gjAKQBABAAAQnUDaF7ADAAAAAA.',
Mo='Mod:BAABLgAECn8rAAMUAAkJlSR4DACdAgAUAAgJSSR4DACdAgANAAYJihOrUwA3AQAAAA==.Modaka:BAAALgAECgMJBgAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moffizi:BAAALgADCgcJCwAAAA==.Moggatorash:BAAALgAECgcJEgAAAA==.Mogtham:BAABLgAECn9BAAIRAAkJ/Re4CwAmAgARAAkJ/Re4CwAmAgAAAA==.Moirenna:BAAALgAECgEJAQABLgAFFAgJLAAEACQUAA==.Moisticklez:BAAALgAECgUJCwAAAA==.Monkeyspaul:BAABLgAECn8cAAIdAAgJQhvDFABHAgAdAAgJQhvDFABHAgABLgAECgkJKwAMANgcAA==.Mooforn:BAAALgAECgIJAgAAAA==.Moonfall:BAABLgAECn8hAAMIAAgJqBAPDgCYAAAWAAUJHw3NHQCtAAAIAAgJnw8PDgCYAAAAAA==.Moonpig:BAAALgAECgcJCgAAAA==.Moosader:BAABLgAECn82AAMLAAkJmhX0BQBfAQALAAkJmhX0BQBfAQAOAAcJkAiVVwAdAQAAAA==.Morellea:BAACLgAFFH8VAAIIAAQJUxeRPQAxAQAIAAQJUxeRPQAxAQAuAAQKfxgAAggACQkSGVk2AB0CAAgACQkSGVk2AB0CAAAA.Morighann:BAABLgAECn8qAAIYAAkJvSPDEwC0AgAYAAkJvSPDEwC0AgAAAA==.Morkith:BAABLgAECn8VAAQHAAgJQQ8/JgA3AQAHAAcJUw8/JgA3AQAMAAQJbQ9tBACYAAAGAAEJKQ1cnwA2AAAAAA==.Morphalot:BAAALgAFFAEJAQAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mostank:BAAALgADCgMJAwAAAA==.Mousse:BAAALgADCgMJAwABLgAECgkJQwATABclAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgAECggJEwABLgAECgkJRwACAPURAA==.',
My='Mylea:BAAALgAECgMJAwABLgAECggJIQAIAKgQAA==.Mynkx:BAABLgAECn85AAILAAgJjheGBACQAQALAAgJjheGBACQAQAAAA==.Mythyras:BAABLgAECn8xAAQfAAcJDiD+DAD1AQAfAAYJTSP+DAD1AQAOAAEJlhZzCwBFAAALAAEJ0A9HlQEwAAAAAA==.',
Na='Naeomy:BAAALgAECgkJCQAAAA==.Nahaman:BAAALgAECgYJDAAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8fAAIOAAYJJhSlOQBlAQAOAAYJJhSlOQBlAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8RAAMCAAcJSAjjKQDpAAACAAQJ3grjKQDpAAADAAMJ4AKSVwBrAAAuAAQKfx8ABQMACAl0GxElACUCAAMACAl0GxElACUCABIABQl/F40hAPwAABEABQkdExM0ANgAAAIAAgkXF515AFMAAAAA.Netherite:BAABLgAECn8dAAIiAAgJMBFeBQCFAQAiAAgJMBFeBQCFAQAAAA==.Nethim:BAAALgAECggJDwABLgAECggJHQAiADARAA==.Netre:BAABLgAECn8UAAIBAAcJewczVgDYAAABAAcJewczVgDYAAABLgAFFAEJAQAVAAAAAA==.Netsuke:BAAALgAECgUJBQAAAA==.Nezana:BAACLgAFFH8HAAQBAAMJjAamFwB4AAABAAIJ2wimFwB4AAAoAAEJ7gHxAwA3AAAnAAEJFg6GLQAuAAAuAAQKfzQABCcACQnXGIgLACECACcACAlCF4gLACECAAEACQmCESchANABACgABAknDCQYAJoAAAAA.',
Ni='Nianah:BAAALgADCggJEAAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8rAAIRAAkJyB2MBgCUAgARAAkJyB2MBgCUAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Nobunada:BAAALgAECgIJAgABLgAFFAEJAgAVAAAAAA==.Nobunaga:BAAALgAFFAEJAgAAAA==.Noranna:BAABLgAECn8iAAIYAAYJZxHgoAAAAQAYAAYJZxHgoAAAAQAAAA==.',
Ny='Nynsyn:BAAALgAECgUJCQABLgAECgcJMQAfAA4gAA==.',
['Nø']='Nøva:BAAALgAECgIJAwABLgAFFAUJFwALAL4cAA==.',
Oh='Ohthesemyboo:BAAALgAECgkJEwAAAA==.Ohwellz:BAABLgAECn8dAAMNAAcJ1g0ScgAGAQANAAUJiRAScgAGAQAUAAcJXBGQUAD1AAABLgAECggJHAALAD8aAA==.',
On='On:BAAALgAECgEJAQAAAA==.',
Op='Ophin:BAABLgAECn8vAAIaAAgJuSA2HgCSAgAaAAgJuSA2HgCSAgAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Or:BAABLgAECn8VAAIGAAYJrxYFPABWAQAGAAYJrxYFPABWAQAAAA==.Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.Ornaxxi:BAAALgAECgUJCQAAAA==.',
Ov='Overheal:BAABLgAECn8jAAInAAkJ/g/DAAB+AQAnAAkJ/g/DAAB+AQAAAA==.',
Oy='Oyuki:BAAALgAECgkJCQABLgAFFAEJAgAVAAAAAA==.',
Pa='Padhu:BAABLgAECn8gAAIjAAkJxgYRNQAqAQAjAAkJxgYRNQAqAQAAAA==.Palox:BAAALgAECgYJCAAAAA==.Panamared:BAABLgAECn86AAIhAAkJMB8oCAClAgAhAAkJMB8oCAClAgAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn9DAAMJAAkJPxRUGwDuAQAJAAkJPxRUGwDuAQAQAAcJmwxAMQBXAQAAAA==.Pezza:BAABLgAECn8lAAINAAkJYxXRAgC5AQANAAkJYxXRAgC5AQAAAA==.',
Ph='Phantomlord:BAABLgAECn8WAAIaAAkJfhN/PwAFAgAaAAkJfhN/PwAFAgABLgAECgkJKAAFAPsUAA==.Phaze:BAABLgAECn8aAAIZAAkJ0BcHFQD7AQAZAAkJ0BcHFQD7AQAAAA==.Phia:BAABLgAECn8eAAMYAAkJ/x4ZEgCnAgAYAAkJ/x4ZEgCnAgAZAAEJEhWBLABCAAAAAA==.Pholcus:BAAALgAECgUJEAAAAA==.',
Pr='Prothagon:BAABLgAECn8rAAMnAAkJsxchCABvAgAnAAkJsxchCABvAgABAAIJQBaqeAByAAAAAA==.',
Ps='Psylix:BAABLgAECn88AAMXAAkJWR3uCACcAgAXAAkJWR3uCACcAgAIAAEJZwuZFwEyAAAAAA==.',
Pu='Punchdari:BAAALgAECgEJAQAAAA==.Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAABLgAECn8dAAILAAYJsQrr9ADFAAALAAYJsQrr9ADFAAAAAA==.Raevennlumis:BAABLgAECn8cAAILAAkJUgZ/pgAtAQALAAkJUgZ/pgAtAQAAAA==.Rahkhard:BAACLgAFFH8GAAIjAAIJPwv1DQB/AAAjAAIJPwv1DQB/AAAuAAQKfyEAAyMACQleHZgIAKkCACMACQlJHZgIAKkCAB0AAQmoHX9+AFcAAAAA.Randrius:BAAALgADCgYJBgAAAA==.Ransha:BAABLgAECn8VAAIUAAcJJBCvQQAtAQAUAAcJJBCvQQAtAQABLgAECgkJNAAWAEMSAA==.Rascdit:BAABLgAECn8UAAIRAAgJPQ8hIQBGAQARAAgJPQ8hIQBGAQAAAA==.Rayjin:BAAALgAECgEJAQAAAA==.',
Re='Redwood:BAABLgAECn8gAAIRAAkJUAzQAgAhAQARAAkJUAzQAgAhAQAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Renwic:BAAALgAECgMJBgAAAA==.Reylani:BAEALgAECgcJBwABLgAECgkJNAAHACkeAA==.',
Rh='Rheingard:BAAALgAECgEJAQAAAA==.Rhemiroll:BAABLgAECn8WAAMdAAgJpwt2SwDUAAAdAAcJ4gl2SwDUAAATAAcJ3AMhfgClAAAAAA==.Rhintalle:BAEALgAECgEJAQABLgAECgYJGgAXABEQAA==.',
Ri='Rickroll:BAAALgAECgMJBQAAAA==.Riepa:BAAALgADCgEJAQABLgAFFAEJAQAVAAAAAA==.Risotto:BAABLgAECn9DAAMTAAkJFyXcAQC5AwATAAkJFyXcAQC5AwAdAAEJkBeZkwA9AAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgAECgUJCgAAAA==.Rolli:BAAALgADCgkJCQAAAA==.',
Ru='Ruaic:BAAALgAECgUJBgAAAA==.Rumblelight:BAABLgAECn8WAAILAAgJpwumlQBJAQALAAgJpwumlQBJAQAAAA==.Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgcJDwAAAA==.Sagehawk:BAABLgAECn8gAAIYAAgJnxSBCAA4AQAYAAgJnxSBCAA4AQAAAA==.Saitamà:BAAALgADCgMJAwAAAA==.Sali:BAAALgAECgEJAgAAAA==.Salmuna:BAAALgADCgEJAQAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIdAAgJJhRGJQCJAQAdAAgJJhRGJQCJAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Saranaya:BAAALgAECgIJAQAAAA==.Sarcastic:BAACLgAFFH8HAAIFAAMJJRAGIwDGAAAFAAMJJRAGIwDGAAAuAAQKfzYAAgUACQkdIFEUAOACAAUACQkdIFEUAOACAAAA.Sarova:BAAALgAECgYJEgAAAA==.Satori:BAABLgAECn8dAAITAAYJFRzFNwCUAQATAAYJFRzFNwCUAQAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJBAAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.Scone:BAAALgAECgYJBgAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAABLgAECn8xAAIaAAkJ8xyeHwCLAgAaAAkJ8xyeHwCLAgAAAA==.Sellidor:BAACLgAFFH8GAAIYAAMJkxX9FAD2AAAYAAMJkxX9FAD2AAAuAAQKfyEAAhgACQkrIKMTALUCABgACQkrIKMTALUCAAAA.Seriniyaa:BAABLgAECn8gAAIEAAkJFQU0CQDGAAAEAAkJFQU0CQDGAAAAAA==.',
Sh='Shaey:BAAALgAECgQJBAAAAA==.Shamanthá:BAAALgAECgMJAwAAAA==.Shaureesa:BAAALgAECgQJBAAAAA==.Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8oAAILAAkJOwMz8wDHAAALAAkJOwMz8wDHAAAAAA==.Shirito:BAABLgAECn8uAAIaAAkJGybhBgBAAwAaAAkJGybhBgBAAwAAAA==.Shiritodh:BAABLgAECn8eAAIIAAgJeCVEGACEAgAIAAgJeCVEGACEAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8wAAMfAAkJKiNmAgAMAwAfAAkJKiNmAgAMAwALAAYJsBY2egCGAQABLgAFFAQJDQARAOobAA==.Shugo:BAABLgAECn8VAAIZAAcJagsTBQB+AAAZAAcJagsTBQB+AAAAAA==.Shune:BAAALgAECgYJBgAAAA==.Shyle:BAAALgAECgQJCQAAAA==.',
Si='Sienje:BAABLgAECn85AAILAAkJ8B+4EADhAgALAAkJ8B+4EADhAgAAAA==.Simpleson:BAABLgAECn8pAAMEAAkJ1hnOIgBWAgAEAAkJ1hnOIgBWAgAeAAUJxQ7ONADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAABLgAECn8bAAMXAAcJPhQQKwAnAQAXAAYJzBYQKwAnAQAIAAYJ7woiqgDRAAAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAABLgAECn8aAAInAAYJ5xq3DwDQAQAnAAYJ5xq3DwDQAQABLgAECgkJAwAVAAAAAA==.Skrabble:BAAALgAECgEJAQAAAA==.Skribble:BAABLgAECn8eAAMQAAgJIA6fOwAgAQAQAAYJBw+fOwAgAQAKAAgJBgqeSwDhAAAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slackbear:BAABLgAECn8xAAIEAAkJRBi8AwBmAQAEAAkJRBi8AwBmAQAAAA==.Slaete:BAABLgAECn8cAAIXAAgJ/QnRBgCFAAAXAAgJ/QnRBgCFAAAAAA==.Slycen:BAAALgADCgcJBwAAAA==.',
So='Sokey:BAABLgAECn8dAAIYAAcJnRDBDgDRAAAYAAcJnRDBDgDRAAAAAA==.Solemn:BAABLgAECn89AAIKAAkJfiFoAADLAgAKAAkJfiFoAADLAgABLgAFFAMJBgAYAJMVAA==.Soleva:BAAALgAECgIJAgAAAA==.Solidious:BAAALgAECgYJCgAAAA==.Solrana:BAABLgAECn8mAAMaAAgJdwZ2CAAJAQAaAAgJdwZ2CAAJAQAcAAEJOANdRAAcAAAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgAECgYJCQAAAA==.Sorren:BAAALgAECgIJAwAAAA==.Sorrows:BAABLgAECn8gAAIeAAkJVA33AQAIAQAeAAkJVA33AQAIAQAAAA==.Sosukesagara:BAAALgAECgYJCQAAAA==.Sotta:BAAALgAECgMJBQAAAA==.Soulbled:BAABLgAECn8mAAIWAAkJmQ40DQCEAQAWAAkJmQ40DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAABLgAECn8qAAINAAgJ9R+2DQDoAgANAAgJ9R+2DQDoAgAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAABLgAECn8eAAILAAkJ7wrmDQDOAAALAAkJ7wrmDQDOAAAAAA==.Superbautumn:BAABLgAECn8ZAAILAAkJox8/KwBUAgALAAkJox8/KwBUAgAAAA==.',
Sy='Sylo:BAABLgAECn8lAAIaAAkJyBXgRAD0AQAaAAkJyBXgRAD0AQAAAA==.Synalaid:BAAALgAECgQJBQAAAA==.Synnyca:BAAALgAECgQJCAABLgAECgcJMQAfAA4gAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAABLgAECn8XAAIEAAkJ/Q38hQAtAQAEAAkJ/Q38hQAtAQAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIaAAkJsht+KACYAgAaAAkJsht+KACYAgABLgAFFAEJAgAVAAAAAA==.Tadoshi:BAAALgADCgEJAQAAAA==.Taeonaki:BAAALgAECgMJAwAAAA==.Tagnaras:BAABLgAECn8ZAAMaAAcJ/RRiCgDnAAAbAAcJ/RR5HgBiAQAaAAYJ+gpiCgDnAAAAAA==.Tahlang:BAAALgAECgEJCAAAAA==.Tali:BAABLgAECn8wAAMYAAkJChDtBgBZAQAYAAkJChDtBgBZAQApAAEJYwY5RAAiAAAAAA==.Taliasluage:BAAALgAECgUJDgABLgAECgkJOAAFAMMaAA==.Tamune:BAABLgAECn8YAAIgAAkJvh2CAgCvAgAgAAkJvh2CAgCvAgAAAA==.Tangle:BAABLgAECn8eAAMDAAcJlxnbJwASAgADAAcJlxnbJwASAgACAAYJ/wGubABwAAABLgAECgkJAwAVAAAAAA==.Tanka:BAACLgAFFH8GAAIHAAMJ0xjhCwCKAAAHAAMJ0xjhCwCKAAAuAAQKfzkAAwcACQntJFoBAFcDAAcACQntJFoBAFcDAAwAAgl9Ejg7AHIAAAAA.Tanuki:BAAALgADCgkJMwAAAA==.Tashlaraz:BAEBLgAECn8aAAIXAAYJERA3OADZAAAXAAYJERA3OADZAAAAAA==.Tasi:BAAALgAECgEJAwAAAA==.Taurannosaur:BAAALgAECgEJAwAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.Tavia:BAAALgAECgEJAQABLgAECgkJOQAVAAAAAQ==.',
Te='Telkas:BAAALgAECgYJDAAAAA==.Temporantus:BAABLgAECn8WAAIRAAkJdxINEwDCAQARAAkJdxINEwDCAQAAAA==.Tenko:BAABLgAECn84AAIFAAkJBR2QAQCuAgAFAAkJBR2QAQCuAgAAAA==.Texaspete:BAAALgAECgEJAQAAAA==.',
Th='Thaddeus:BAABLgAECn8mAAIUAAkJyhBrKgCfAQAUAAkJyhBrKgCfAQAAAA==.Thariane:BAAALgAECgEJAQABLgAECgIJAwAVAAAAAA==.Thaxxas:BAAALgADCgYJCQAAAA==.Therm:BAACLgAFFH8OAAILAAQJsiZAFQDBAQALAAQJsiZAFQDBAQAuAAQKf0UAAgsACQmrJuoAAI0DAAsACQmrJuoAAI0DAAAA.Thoramier:BAABLgAECn8jAAQfAAkJRBt9DAD8AQAfAAcJfB59DAD8AQALAAYJvBEdtwAVAQAOAAIJGhQubwB6AAAAAA==.Thorgrymm:BAAALgAECgQJBAAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timadia:BAAALgAECgEJAQAAAA==.Timoonja:BAAALgAECggJEAAAAA==.',
To='Tonatuih:BAACLgAFFH8OAAMIAAMJUQ7XGwC5AAAIAAMJ5QrXGwC5AAAXAAIJFQ+RCQCFAAAuAAQKfzwABAgACQmQH4slADgCAAgACAnvG4slADgCABcACQlEGzQaAK4BABYABwkIFKINAHwBAAAA.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAkJJgAMAJklAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAABLgAECn8qAAImAAkJ6xhJBgAaAgAmAAkJ6xhJBgAaAgAAAA==.Triipod:BAAALgAECgIJAgAAAA==.Trinkat:BAABLgAECn8dAAIFAAYJ6QQ/CwGcAAAFAAYJ6QQ/CwGcAAAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.Tryst:BAAALgAECgMJAwAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tyfferian:BAAALgAECgIJAgAAAA==.Tylean:BAAALgAECgkJDQAAAA==.Tynk:BAAALgAECgQJBAABLgAECgcJDAAVAAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tynnyri:BAAALgAECgEJAQABLgAECggJKgANAPUfAA==.Typicallama:BAAALgAECggJAgABLgAECgkJFwAEAB0PAA==.Tyreitherinn:BAAALgAECgcJEAAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.Unìqùe:BAAALgADCgEJAQAAAA==.',
Uu='Uu:BAAALgAECgUJCQAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAABLgAECn8gAAIdAAkJQgjRAgAPAQAdAAkJQgjRAgAPAQAAAA==.Vaerethra:BAAALgADCgEJAQAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn9eAAIEAAkJzwn0AwBdAQAEAAkJzwn0AwBdAQAAAA==.Valsedor:BAAALgAECgYJBgAAAA==.Valwar:BAABLgAECn8kAAIGAAkJ8xkkHABsAgAGAAkJ8xkkHABsAgAAAA==.Vanwyngarden:BAAALgAECgEJAQAAAA==.Vareyn:BAABLgAECn8jAAMfAAcJ9QoAKADXAAAfAAcJrAkAKADXAAALAAMJrAqz+wCcAAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgUJCwABLgAECgYJCwAVAAAAAA==.Velle:BAAALgAFFAIJAwABLgAFFAMJCgAYAMoFAA==.',
Vi='Vienge:BAAALgAECgEJAQAAAA==.',
Vo='Vonon:BAACLgAFFH8OAAILAAUJKhnuMwBHAQALAAUJKhnuMwBHAQAuAAQKfyMAAx8ACAmQIuMKABsCAB8ABwmoG+MKABsCAAsABwmQIF5HAA0CAAAA.Vorth:BAACLgAFFH8JAAIcAAMJJQfsBgC7AAAcAAMJJQfsBgC7AAAuAAQKfzgAAxwACQlLHAIFAHECABwACQkiGwIFAHECABoABwmJFP7BAPsAAAAA.Vorükh:BAABLgAECn8XAAMgAAcJCApBDQBKAQAgAAYJaAtBDQBKAQAhAAYJsAOTQwCzAAABLgAECgkJHwASAJsRAA==.',
Vy='Vyrlana:BAACLgAFFH8HAAInAAMJgARFJAB9AAAnAAMJgARFJAB9AAAuAAQKfxwAAycACQncEo0PANMBACcACQncEo0PANMBAAEABgnRAuZIALQAAAAA.',
Wa='Waldir:BAABLgAECn9AAAMOAAkJsySsAQCgAwAOAAkJsySsAQCgAwALAAIJuB4+AwG0AAAAAA==.Waldstein:BAABLgAECn82AAIaAAgJrBgUXQCwAQAaAAgJrBgUXQCwAQAAAA==.Wanted:BAABLgAECn8oAAQLAAcJuw+HhwBrAQALAAcJYw+HhwBrAQAOAAUJnBKDSgASAQAfAAYJSwo9LwCrAAAAAA==.Watz:BAABLgAECn83AAIYAAkJqxdYLgAjAgAYAAkJqxdYLgAjAgAAAA==.',
We='Wensa:BAAALgAECgYJCwAAAA==.',
Wh='Whisperdlith:BAAALgAECgEJAQAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xenophage:BAAALgADCgMJAwAAAA==.Xessala:BAAALgAECgUJBgAAAA==.',
Xh='Xheero:BAACLgAFFH8NAAIYAAMJuBIkYgDhAAAYAAMJuBIkYgDhAAAuAAQKfzsAAhgACQmcHpQUAK4CABgACQmcHpQUAK4CAAAA.Xheerom:BAAALgAECgcJEgAAAA==.',
Ye='Yeast:BAAALgAECgkJDwAAAA==.',
Yo='Youtube:BAAALgAECgcJBwABLgAFFAQJDgALALImAA==.',
Yu='Yulica:BAABLgAECn8iAAIFAAYJMBHbFwBwAAAFAAYJMBHbFwBwAAAAAA==.',
Za='Zaffy:BAABLgAECn8xAAIeAAkJWxLdCAC9AQAeAAkJWxLdCAC9AQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgAECgMJCQAAAA==.Zaleron:BAAALgAECggJCgAAAA==.Zanazath:BAABLgAECn8dAAMoAAcJ0Ro3EADZAQAoAAYJRhw3EADZAQABAAYJvhMpRwAOAQAAAA==.Zano:BAAALgAECgYJCQAAAA==.Zaruba:BAACLgAFFH8KAAIUAAQJqQa/MADPAAAUAAQJqQa/MADPAAAuAAQKfzwAAxQACQkxESQEAAoBABQACQkxESQEAAoBAA0AAgnnAJyaADgAAAEuAAQKCQlHAAIA9REA.Zatheon:BAABLgAECn8lAAILAAgJXhlOVQDKAQALAAgJXhlOVQDKAQAAAA==.Zatkyng:BAACLgAFFH8GAAIdAAMJoAqXKQCqAAAdAAMJoAqXKQCqAAAuAAQKfxwAAh0ACAnmD/c+AAMBAB0ACAnmD/c+AAMBAAAA.',
Ze='Zekos:BAAALgAECgcJCgAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8rAAIMAAkJ2Bz/CACOAgAMAAkJ2Bz/CACOAgAAAA==.Zimdalar:BAABLgAECn8nAAMjAAgJihhvIwCPAQAjAAgJihhvIwCPAQAdAAEJ2Qz0ngAxAAAAAA==.',
Zo='Zolhs:BAAALgAECgEJAgAAAA==.Zolls:BAAALgAECgMJBgAAAA==.',
Zu='Zulre:BAABLgAECn9XAAIaAAkJvBpKIgB9AgAaAAkJvBpKIgB9AgAAAA==.',
['Ôv']='Ôverkill:BAAALgAECgIJAwABLgAECgkJIwAnAP4PAA==.',
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
