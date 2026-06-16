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

local lookup = {'Evoker-Augmentation','Druid-Balance','Druid-Restoration','Mage-Frost','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Priest-Holy','Priest-Shadow','Paladin-Retribution','Warrior-Protection','Shaman-Restoration','Warlock-Demonology','Paladin-Holy','Mage-Fire','Priest-Discipline','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Shaman-Elemental','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Monk-Windwalker','Warlock-Destruction','Paladin-Protection','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Hunter-Marksmanship',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Ackrenoth:BAABLgAECn8tAAIBAAkJExNRHgDjAQABAAkJExNRHgDjAQAAAA==.',
Ad='Adynn:BAACLgAFFH8HAAMCAAMJLRmlKQDjAAACAAMJLRmlKQDjAAADAAEJQhJUbQA3AAAuAAQKfzsAAwIACQneJYMBAGoDAAIACQneJYMBAGoDAAMAAgkyHf6hAGoAAAAA.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAAALgAECggJEwAAAA==.',
Ag='Agrathayn:BAAALgAECgYJCgAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJNQAEAEsaAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alanatre:BAAALgADCggJDgAAAA==.Alenoth:BAAALgAECgMJAwAAAA==.Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAACLgAFFH8FAAIFAAMJXxtNKQAKAQAFAAMJXxtNKQAKAQAuAAQKfzkAAwUACQkGJgcCAFkDAAUACQkGJgcCAFkDAAYAAQnpFEpxADkAAAAA.Allyeska:BAAALgAECgMJAwAAAA==.Alnharaelune:BAAALgADCgkJEQAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAABLgAECn8gAAIHAAcJbxDJbABGAQAHAAcJbxDJbABGAQAAAA==.',
An='Anali:BAACLgAFFH8GAAIIAAQJaBVjFQAQAQAIAAQJaBVjFQAQAQAuAAQKfx4AAggACQlnIJgIAN0CAAgACQlnIJgIAN0CAAAA.Anani:BAABLgAECn8uAAIJAAkJ7BFBGwDqAQAJAAkJ7BFBGwDqAQAAAA==.Andavin:BAABLgAECn8tAAIKAAYJ2ARY/gC2AAAKAAYJ2ARY/gC2AAAAAA==.Angreifer:BAACLgAFFH8XAAILAAYJsxwQCQCXAQALAAYJsxwQCQCXAQAuAAQKfy8ABAsACQmvHKQLADACAAsACAnBHqQLADACAAUACQn1DmEyAOIBAAYAAgnfDi53AC8AAAAA.Angron:BAAALgAFFAEJAQAAAA==.Anori:BAABLgAECn8mAAICAAgJNhgpGwDuAQACAAgJNhgpGwDuAQAAAA==.',
Ao='Aonar:BAABLgAECn8ZAAIMAAUJNBXMYAA0AQAMAAUJNBXMYAA0AQAAAA==.',
Ar='Arc:BAABLgAECn82AAINAAkJySIlBgAtAwANAAkJySIlBgAtAwAAAA==.Archenteron:BAAALgAECgQJCAAAAA==.Arctat:BAAALgAECgMJAwAAAA==.Ardorcinder:BAAALgAECgYJDwAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJDwABLgAECggJKAAMANAfAA==.Artea:BAAALgAECgYJBgAAAA==.',
As='Asbjorne:BAABLgAECn8qAAIOAAkJVRagEwBwAgAOAAkJVRagEwBwAgAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
At='Atryssa:BAAALgAECgQJBAAAAA==.',
Au='Audi:BAAALgADCgYJDAAAAA==.Augamand:BAAALgAECgYJCAAAAA==.Autumnmoon:BAABLgAECn8wAAIPAAgJUxAmBQCDAQAPAAgJUxAmBQCDAQAAAA==.',
Av='Avelos:BAACLgAFFH8QAAQIAAUJeQaBFwD7AAAIAAUJeQaBFwD7AAAJAAIJWAMNNABnAAAQAAEJ+Ad/SwA6AAAuAAQKfy8ABAgACQm4GTsbAOoBAAgACQm4GTsbAOoBABAABQktBspGAIYAAAkAAgmuDD1xAFsAAAAA.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAABLgAECn8uAAURAAkJlBx1BwB6AgARAAkJ8Rt1BwB6AgACAAYJZAoQTgDxAAASAAEJ3BxjQQBVAAADAAIJIwN8yQA3AAAAAA==.Ayzmist:BAAALgAECgYJCQAAAA==.Ayzmyth:BAABLgAECn8lAAITAAcJbw/eRQBNAQATAAcJbw/eRQBNAQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAIMAAcJ7yAVDwCgAgAMAAcJ7yAVDwCgAgAAAA==.Bashra:BAAALgAECgYJEQAAAA==.',
Be='Beasic:BAABLgAECn9BAAMUAAkJWg09VQDhAAAUAAcJxwk9VQDhAAAMAAYJyAFKrgBmAAAAAA==.Beastmode:BAAALgAECggJDwAAAA==.Beletili:BAABLgAECn83AAIIAAkJ5xfMDwBpAgAIAAkJ5xfMDwBpAgAAAA==.Bellissimo:BAAALgAECgEJAQABLgAECgkJMwAMAEoXAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn8zAAMVAAkJQxK1FQD5AAAHAAkJJBEtUwCrAQAVAAYJWhK1FQD5AAAAAA==.Birdman:BAABLgAECn8UAAMMAAYJJBF5XQA/AQAMAAYJJBF5XQA/AQAUAAYJtRCtSAANAQABLgAECgkJMwAVAEMSAA==.Bismuth:BAAALgAECgcJEAAAAA==.',
Bj='Bjornin:BAAALgAECgEJAQAAAA==.',
Bl='Blackraven:BAABLgAECn8lAAMWAAgJpx2hNQACAgAWAAYJKB6hNQACAgAXAAcJgBidHgCnAQAAAA==.Blatendrg:BAABLgAECn8vAAIBAAkJ9BCPJgCrAQABAAkJ9BCPJgCrAQAAAA==.Blindcloud:BAABLgAECn8aAAIYAAgJUAYJMwDxAAAYAAgJUAYJMwDxAAAAAA==.',
Bo='Boot:BAABLgAECn8gAAIOAAYJWxo5KQDBAQAOAAYJWxo5KQDBAQAAAA==.Bophedes:BAABLgAECn8XAAMZAAgJZReFRwDpAQAZAAgJZReFRwDpAQAaAAEJbw6TXQAtAAAAAA==.Borodemonin:BAEBLgAECn8dAAIHAAYJLiSMLwAFAgAHAAYJLiSMLwAFAgABLgAFFAUJEwAJADIlAA==.Bosstun:BAAALgADCgMJAwAAAA==.Bozrohin:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn9CAAIIAAkJkRUaGAAJAgAIAAkJkRUaGAAJAgAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Brieanna:BAAALgADCgQJDAAAAA==.Bromith:BAAALgAECgEJAQAAAA==.Brugen:BAAALgAECgcJCgAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calavero:BAAALgAECgQJBAABLgAECggJKAAMANAfAA==.Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgYJDgAAAA==.Cariñosa:BAAALgAECgEJAQAAAA==.Carøline:BAAALgAECgEJAQAAAA==.Caska:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgUJCwAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8vAAMZAAkJ0R1lHgCPAgAZAAkJ0R1lHgCPAgAbAAEJ3wtJGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgYJEQAAAA==.Charles:BAABLgAECn8tAAIcAAkJlSQ+BAAUAwAcAAkJlSQ+BAAUAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiarus:BAAALgADCgkJGAABLgAFFAYJFwALALMcAA==.Chiot:BAABLgAECn8+AAILAAkJ7B03BwCPAgALAAkJ7B03BwCPAgAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8lAAMFAAkJAhk5HQADAgAFAAkJ6hc5HQADAgALAAUJbhmIJQABAQAAAA==.Chuga:BAABLgAECn8jAAMNAAgJkQ67aQBoAQANAAgJnA27aQBoAQAdAAQJHQ0yMwBQAAAAAA==.',
Ci='Cimerian:BAABLgAECn8hAAMeAAgJWwzbHwAJAQAeAAcJoA3bHwAJAQAKAAUJigVGFAGcAAAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECggJIwAMANcOAA==.',
Co='Cobalticus:BAAALgAECgYJDgAAAA==.Corange:BAAALgAECgEJAQAAAA==.Corlock:BAAALgAECgQJBAAAAA==.Cormech:BAAALgAECgcJEwAAAA==.Cornite:BAABLgAECn8YAAIZAAgJDg0ffgBkAQAZAAgJDg0ffgBkAQAAAA==.',
Cr='Crizzo:BAABLgAECn87AAIWAAkJ6B9/DwDQAgAWAAkJ6B9/DwDQAgAAAA==.',
Cy='Cyndrial:BAAALgADCgYJEgAAAA==.',
Da='Daddyslilgrl:BAABLgAECn8nAAINAAcJCAUqsADkAAANAAcJCAUqsADkAAAAAA==.Dakra:BAEBLgAECn80AAMGAAkJKR6LBQCuAgAGAAkJKR6LBQCuAgALAAEJOwwLUwAvAAAAAA==.Dalamar:BAAALgAFFAMJCQABLgAFFAQJEgAJABAUAQ==.Dalandis:BAAALgAFFAEJAQAAAA==.Dalyeth:BAABLgAECn8pAAIVAAcJBSbhAwCPAgAVAAcJBSbhAwCPAgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAACLgAFFH8JAAIWAAMJzw09GQCiAAAWAAMJzw09GQCiAAAuAAQKfxQAAhYACAmcHrALAOUCABYACAmcHrALAOUCAAAA.Daunt:BAABLgAECn8WAAIdAAgJtA+BDQBgAQAdAAgJtA+BDQBgAQABLgAECgkJRgACAPURAA==.',
De='Decypher:BAABLgAECn8pAAISAAkJ+BaeCQAkAgASAAkJ+BaeCQAkAgABLgAFFAIJAwAfAAAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Deliverance:BAACLgAFFH8SAAIJAAQJEBTtFwAhAQAJAAQJEBTtFwAhAQAuAAQKfzEAAwkACQnJIXIEABIDAAkACQnJIXIEABIDAAgABAnPChRZAHAAAAAA.Demonablaze:BAAALgAECgIJAwAAAA==.Dentik:BAABLgAECn83AAMDAAkJvQ+XOQCtAQADAAkJvQ+XOQCtAQARAAIJ4gLueAAmAAAAAA==.Denuma:BAAALgAECgYJBgAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgYJDwABLgAFFAIJAwAfAAAAAA==.Dheriana:BAAALgAFFAIJAwAAAA==.',
Di='Diamair:BAABLgAECn8+AAMgAAkJTRkrBAC5AQAEAAkJlBPgSgD4AQAgAAgJGBgrBAC5AQAAAA==.Diamones:BAAALgAECgMJAwAAAA==.Dixiee:BAABLgAECn8WAAIJAAcJbgSETgDTAAAJAAcJbgSETgDTAAAAAA==.',
Dn='Dnegelpal:BAABLgAECn8mAAIKAAkJUxBzZQCiAQAKAAkJUxBzZQCiAQAAAA==.',
Do='Docbison:BAAALgADCgQJCQABLgAECgYJDAAfAAAAAA==.Dodgecharger:BAABLgAECn8eAAIMAAYJEgavgwDSAAAMAAYJEgavgwDSAAAAAA==.Dornix:BAABLgAECn8pAAINAAgJZyAFLAAoAgANAAgJZyAFLAAoAgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgcJDAAAAA==.Dragonfood:BAABLgAECn8fAAIWAAcJGA+lbgBfAQAWAAcJGA+lbgBfAQAAAA==.Drakilu:BAABLgAECn9CAAIWAAkJQB7PEwCvAgAWAAkJQB7PEwCvAgAAAA==.Drasic:BAACLgAFFH8PAAIDAAMJFRd1NgDNAAADAAMJFRd1NgDNAAAuAAQKfzwAAgMACQmyIUYFAGIDAAMACQmyIUYFAGIDAAAA.Dreamcloud:BAAALgAECgUJBQAAAA==.Dreddscott:BAAALgAECgUJBQABLgAECgkJOgAhADAfAA==.Drophin:BAAALgAECgMJBgAAAA==.Drunken:BAABLgAECn8xAAIiAAgJ3R+BDABsAgAiAAgJ3R+BDABsAgAAAA==.Druphin:BAAALgADCgYJEgAAAA==.',
Du='Durward:BAABLgAECn9FAAQZAAkJzyL5CgAUAwAZAAkJzyL5CgAUAwAaAAUJ/w6gOQCqAAAbAAIJNxduKQCCAAAAAA==.Duvo:BAABLgAECn8ZAAIWAAcJ0xy0TAC3AQAWAAcJ0xy0TAC3AQAAAA==.',
Dw='Dwarfo:BAABLgAECn8WAAIKAAgJawaPtgATAQAKAAgJawaPtgATAQAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.Dwarvey:BAAALgADCgMJAwAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAABLgAECn8dAAMRAAgJbQdiOAC/AAARAAgJbQdiOAC/AAACAAQJpQA4iwAyAAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIbAAgJlR6GAgCPAgAbAAgJlR6GAgCPAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAABLgAECn8bAAINAAkJIQK4ygC6AAANAAkJIQK4ygC6AAAAAA==.Elemental:BAACLgAFFH8NAAMUAAUJmArWKwDfAAAUAAUJmArWKwDfAAAMAAIJxQoraABoAAAuAAQKfzEAAxQACQmyHEYNAJACABQACQmyHEYNAJACAAwAAwm4CRmOAF4AAAEuAAUUBgkQAAIACQkA.Eleussen:BAAALgAECgMJAwAAAA==.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgAECgQJCAAAAA==.Elloseth:BAABLgAECn8nAAIJAAcJtB2tGAAAAgAJAAcJtB2tGAAAAgAAAA==.Elmorin:BAABLgAECn8UAAIGAAgJgAy+IwBCAQAGAAgJgAy+IwBCAQAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAABLgAECn8eAAIWAAYJ0w5+mQAIAQAWAAYJ0w5+mQAIAQAAAA==.',
Ep='Epica:BAABLgAECn8oAAIEAAcJ+xQTjwBWAQAEAAcJ+xQTjwBWAQAAAA==.',
Er='Eragonhawk:BAABLgAECn8qAAIKAAgJFh1/KwBRAgAKAAgJFh1/KwBRAgAAAA==.Erelynn:BAAALgAECgQJBAABLgAECgkJJwAIAMkRAA==.Eroldan:BAABLgAECn8kAAMMAAkJyx4rDAD2AgAMAAkJyx4rDAD2AgAUAAQJUA1+ZAC0AAAAAA==.Erovianoria:BAACLgAFFH8KAAIWAAMJygUebQC8AAAWAAMJygUebQC8AAAuAAQKfykAAhYACQm/Fv8WAIACABYACQm/Fv8WAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.Eräthis:BAAALgAECgMJAwAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAABLgAECn8qAAIYAAgJdyI5CQCUAgAYAAgJdyI5CQCUAgABLgAFFAgJKwANACQUAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8zAAIMAAkJShfeGwBpAgAMAAkJShfeGwBpAgAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Ex='Expire:BAAALgAECgQJBQAAAA==.',
Fa='Fatalfury:BAABLgAECn8lAAMKAAkJoxrpUgDOAQAKAAgJeBnpUgDOAQAOAAQJCQ4VVwDYAAAAAA==.Fauxstorm:BAABLgAECn8bAAMjAAUJsBonGQA3AQAjAAUJsBonGQA3AQAUAAIJ/BFmoAA1AAAAAA==.',
Fi='Finngan:BAABLgAECn8wAAIdAAkJoQ6HCwCDAQAdAAkJoQ6HCwCDAQAAAA==.Fireina:BAABLgAECn8XAAIPAAcJvAGQDgBuAAAPAAcJvAGQDgBuAAAAAA==.',
Fl='Fluria:BAAALgAECgIJAgABLgAECgkJJwAIAMkRAA==.',
Fo='Forestkin:BAABLgAECn8aAAIRAAYJaCDIEQDMAQARAAYJaCDIEQDMAQABLgAECgcJKQAVAAUmAA==.Fossilis:BAABLgAECn8YAAMkAAcJHgUmEwDyAAAkAAcJAQUmEwDyAAAhAAUJ2wIUTwCzAAAAAA==.',
Fr='Frenzyz:BAAALgADCgIJAgAAAA==.Friartuk:BAAALgADCgEJAQAAAA==.Frozenthunda:BAAALgAECgQJCgAAAA==.',
Fu='Furna:BAABLgAECn8yAAIQAAcJgRJpJgCbAQAQAAcJgRJpJgCbAQAAAA==.',
Fy='Fyahka:BAAALgADCgQJBAAAAA==.Fyon:BAAALgAECgYJCQAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAACLgAFFH8SAAIFAAUJ4AwEJgAYAQAFAAUJ4AwEJgAYAQAuAAQKfzYAAgUACQn4F7gXAC8CAAUACQn4F7gXAC8CAAAA.Galileia:BAAALgADCgMJBAAAAA==.',
Gh='Ghorienge:BAAALgAECgYJDwAAAA==.Ghostcat:BAAALgAECgIJAgAAAA==.',
Gi='Gilox:BAABLgAECn8gAAIkAAkJ5BDuBwDQAQAkAAkJ5BDuBwDQAQAAAA==.',
Gl='Gleefortrees:BAAALgAECgcJBwAAAA==.Glinteastwar:BAAALgAECgMJAwAAAA==.',
Gn='Gndmexia:BAAALgAECgYJEwAAAA==.Gneiss:BAAALgAECgcJEgAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8iAAIDAAkJiCBdBwA/AwADAAkJiCBdBwA/AwAAAA==.',
Gr='Graymon:BAABLgAECn8gAAIFAAUJTB66OQBeAQAFAAUJTB66OQBeAQAAAA==.Greebo:BAABLgAECn8gAAIRAAUJ5ANpXgBOAAARAAUJ5ANpXgBOAAAAAA==.Griknor:BAABLgAECn8fAAMGAAYJRgU/IgDaAAAGAAYJRgU/IgDaAAAFAAQJBgPTfwBzAAAAAA==.Grimniel:BAAALgAECgIJAwAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAABLgAECn8UAAIKAAgJWRtlNAAsAgAKAAgJWRtlNAAsAgAAAA==.Gussie:BAAALgADCgQJBAABLgAECgcJFgAJAG4EAA==.',
Gw='Gwenyver:BAABLgAECn8nAAIKAAkJPQPk2ADkAAAKAAkJPQPk2ADkAAAAAA==.',
Ha='Hadoukendk:BAAALgAECggJEwAAAA==.Hafaken:BAAALgAECgEJAQAAAA==.Hallien:BAAALgADCgEJAQAAAA==.Hamord:BAABLgAECn8hAAIeAAkJtg4FGgBGAQAeAAkJtg4FGgBGAQAAAA==.Hansdelbruk:BAAALgADCgEJAQAAAA==.Hardlight:BAAALgAECgYJBgAAAA==.Harington:BAAALgAECgMJAwAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgAECgQJBAAAAA==.Harliqynn:BAACLgAFFH8GAAIWAAMJ3BvnVQDyAAAWAAMJ3BvnVQDyAAAuAAQKfxwAAhYACQngGu0gAEACABYACQngGu0gAEACAAAA.Harlock:BAABLgAECn8jAAIhAAkJXxxAEAAmAgAhAAkJXxxAEAAmAgAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.Hazelnuts:BAAALgAECgIJAQAAAA==.',
He='Heartkiller:BAAALgAECgQJBAABLgAECgkJKAAEAPsUAA==.Hellcrazed:BAAALgADCgMJAwABLgAFFAQJCAARALQbAA==.Helleye:BAABLgAECn8dAAIRAAgJPQtWLAD5AAARAAgJPQtWLAD5AAAAAA==.',
Hi='Hiten:BAABLgAECn9CAAQhAAkJxRtYCgB7AgAhAAkJvhtYCgB7AgAkAAUJRBWIDQBEAQAlAAEJjwiGJQArAAAAAA==.',
Ho='Hopedaimond:BAABLgAECn8nAAIUAAkJ3A3DMgBuAQAUAAkJ3A3DMgBuAQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8/AAMWAAkJAA6ZTgCyAQAWAAkJAA6ZTgCyAQAXAAYJowMpPwDLAAAAAA==.',
Hy='Hypro:BAABLgAECn8xAAIMAAkJeyU7AADXAwAMAAkJeyU7AADXAwAAAA==.',
['Há']='Háides:BAAALgADCgIJAgAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIeAAcJByOXBAC6AgAeAAcJByOXBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJEwAAAA==.',
Ie='Iepa:BAAALgAECggJEQAAAA==.',
Il='Ilthad:BAABLgAECn8sAAMYAAgJbxcgFADvAQAYAAgJbxcgFADvAQAHAAEJ9QJHNQEbAAAAAA==.',
Im='Imneth:BAAALgAECgEJAQABLgAECggJHQAgADARAA==.Imperio:BAAALgADCgYJBgAAAA==.Imshalar:BAAALgAECggJEAAAAA==.',
In='Inconcvabull:BAABLgAECn8XAAINAAgJEAtwgwAyAQANAAgJEAtwgwAyAQAAAA==.Inferious:BAAALgAECgUJDwABLgAECggJFwAZAGUXAA==.Infurryating:BAAALgAECgkJBwAAAA==.Inistus:BAAALgAECgMJAwAAAA==.',
Ir='Iralis:BAAALgAECgcJEAAAAA==.Iroar:BAAALgADCgEJAQAAAA==.',
Is='Ischadè:BAAALgAECgMJBAAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgkJEQAAAA==.Itsirk:BAABLgAECn8wAAIOAAkJuxlhFABpAgAOAAkJuxlhFABpAgAAAA==.',
Iz='Izyebelle:BAABLgAECn8qAAMJAAkJ5gGbXQCcAAAJAAkJ5gGbXQCcAAAIAAEJUAGTfQATAAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAABLgAECn8wAAIeAAgJ3SRKAwDhAgAeAAgJ3SRKAwDhAgAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jiayou:BAAALgADCgEJAQAAAA==.Jimmydin:BAACLgAFFH8RAAMOAAUJYB3VGABVAQAOAAQJChvVGABVAQAKAAQJmhSdQgAhAQAuAAQKfzwAAwoACQnKGScnAGUCAAoACQnKGScnAGUCAA4ACQklGbQeACICAAAA.Jix:BAABLgAECn8YAAMdAAgJkhi9DgDeAQAdAAYJtxy9DgDeAQANAAQJSAxGrQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8xAAQHAAkJhhI1SQCnAQAHAAkJ5RE1SQCnAQAVAAMJyxWlHgCSAAAYAAEJYw4QbwA2AAAAAA==.',
Ju='Juego:BAAALgADCgEJAQAAAA==.Julkan:BAAALgAECgQJBgAAAA==.Junhoong:BAABLgAECn9CAAIKAAkJVRU5QAAEAgAKAAkJVRU5QAAEAgAAAA==.',
Jy='Jynnysa:BAAALgAECgcJEAABLgAECgYJLgAeAE0jAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAABLgAECn8dAAIGAAgJIBi0DgD+AQAGAAgJIBi0DgD+AQAAAA==.Kairoll:BAABLgAECn8mAAIIAAkJuBX3FwAKAgAIAAkJuBX3FwAKAgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Kannah:BAAALgAECggJDwAAAA==.Karaa:BAABLgAECn8uAAITAAgJwwaPZQDdAAATAAgJwwaPZQDdAAAAAA==.Kariena:BAABLgAECn8oAAIWAAgJ5h4cHwBpAgAWAAgJ5h4cHwBpAgAAAA==.Katesluage:BAABLgAECn81AAIEAAkJSxoSNwA5AgAEAAkJSxoSNwA5AgAAAA==.Kawrrl:BAAALgAECgEJAQAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJNQAEAEsaAA==.',
Ke='Keeya:BAABLgAECn8/AAIZAAgJABQmVwC9AQAZAAgJABQmVwC9AQAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kelkan:BAAALgAECgEJAQAAAA==.Kendari:BAABLgAECn8cAAMZAAkJzwnPvwD7AAAZAAQJzw/PvwD7AAAaAAYJ/QSZQQCGAAAAAA==.Kernasas:BAABLgAECn9DAAIdAAgJhxWDCAC/AQAdAAgJhxWDCAC/AQAAAA==.Keslynn:BAAALgAECgIJAwABLgAECggJKAAWAOYeAA==.Ketrani:BAAALgAECgEJAgABLgAECggJKAAWAOYeAA==.',
Kh='Khiari:BAAALgAECgYJDgABLgAECggJLQAKAGcVAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAAALgAECggJEwAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJKQANAGcgAA==.Kirtiao:BAAALgAECgEJAgABLgAECggJKAAWAOYeAA==.Kitalidie:BAAALgAECgQJBgABLgAECggJKAAWAOYeAA==.Kizaraan:BAABLgAECn8dAAMmAAgJewTMIwDMAAAmAAcJxgPMIwDMAAAnAAMJzwJQIABNAAAAAA==.',
Kl='Kleyntamar:BAABLgAECn8YAAIDAAUJaxk7RwBwAQADAAUJaxk7RwBwAQAAAA==.',
Kn='Knyghtly:BAAALgAECgkJAwAAAA==.',
Ko='Konstantien:BAAALgAECgYJBgAAAA==.Koshamunzo:BAAALgADCgYJBgAAAA==.',
Kr='Kreios:BAAALgAECgkJBwAAAA==.Kritt:BAAALgAECgYJDAAAAA==.Kritter:BAAALgAECgYJDwAAAA==.Krohm:BAABLgAECn8uAAMKAAkJcyP+BwApAwAKAAkJcyP+BwApAwAeAAEJ8hgaSABEAAAAAA==.Krostana:BAAALgADCgEJAQAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgAECgYJDgAAAA==.Kungfuey:BAAALgAECgUJBQAAAA==.Kupau:BAAALgAECgQJBAAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Lanss:BAACLgAFFH8HAAILAAMJoxynFAD2AAALAAMJoxynFAD2AAAuAAQKf0wAAgsACQkRJacBAD4DAAsACQkRJacBAD4DAAAA.Larachel:BAABLgAECn8cAAMIAAgJRR0wDQCQAgAIAAgJRR0wDQCQAgAJAAcJShaMJwCQAQAAAA==.Laur:BAABLgAECn8uAAIJAAkJaxMTHgDTAQAJAAkJaxMTHgDTAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8jAAIKAAkJUBxbLABNAgAKAAkJUBxbLABNAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAABLgAECn8gAAIeAAUJZR0uGQBNAQAeAAUJZR0uGQBNAQAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAwAAAA==.Lilipo:BAABLgAECn83AAIcAAgJsAzHMQA7AQAcAAgJsAzHMQA7AQAAAA==.Liltara:BAABLgAECn8vAAIEAAcJqgJp8wC7AAAEAAcJqgJp8wC7AAAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llamatotems:BAAALgAECgcJBwABLgAECgkJRAAZAMoNAA==.Llanz:BAAALgADCgkJKgAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAACLgAFFH8LAAINAAMJawctgwC6AAANAAMJawctgwC6AAAuAAQKfy0AAg0ACAm+FClXAJYBAA0ACAm+FClXAJYBAAAA.Lokdan:BAAALgAECgYJCQAAAA==.Loppy:BAAALgAECgIJAgAAAA==.Loula:BAABLgAECn8pAAIEAAkJHgMIygD3AAAEAAkJHgMIygD3AAAAAA==.Lowryder:BAACLgAFFH8MAAIhAAQJTQtEIAAbAQAhAAQJTQtEIAAbAQAuAAQKfyIAAyEACQniFMkTAAICACEACQniFMkTAAICACQAAQmbBmIgADEAAAAA.Loxes:BAAALgAECgcJDQABLgAECgYJCwAfAAAAAA==.Loxy:BAAALgAECgUJDAAAAA==.',
Lu='Lukam:BAAALgAECgUJEAAAAA==.Lunaellana:BAAALgAECgQJBAAAAA==.Lus:BAABLgAECn8UAAMNAAYJsRfzegBmAQANAAYJsRfzegBmAQAdAAIJuggxUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAACLgAFFH8FAAIDAAMJegxgRQCaAAADAAMJegxgRQCaAAAuAAQKfxoABQMACAmAHYcUAKMCAAMACAmAHYcUAKMCABEABAk8DFNMAHMAABIAAglTBOZMADoAAAIAAglPAemoAA4AAAAA.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
['Lü']='Lüvpüp:BAAALgAECggJEQABLgAECgkJIgAZALIbAA==.',
Ma='Magicfang:BAAALgAECgYJCwAAAA==.Maiku:BAABLgAECn8/AAINAAkJcRUcMAAWAgANAAkJcRUcMAAWAgAAAA==.Makado:BAACLgAFFH8HAAQoAAQJ2QFBEACLAAAoAAMJtwFBEACLAAAdAAIJmwGLGABkAAANAAEJmgFh0wApAAAuAAQKfyAABB0ACAnaCHgvAP0AAB0ABwlAB3gvAP0AAA0ABQngBUPGAMEAACgABQm9B1UiAKgAAAAA.Makaris:BAAALgADCgQJBQAAAA==.Makaveli:BAAALgAFFAIJAwAAAA==.Maknanimus:BAAALgADCgQJBAAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAABLgAECn8gAAINAAYJpBopXQCGAQANAAYJpBopXQCGAQAAAA==.Matheniel:BAAALgAECgEJAQAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Matua:BAAALgAECgEJAgAAAA==.Maycee:BAAALgAECgcJEwAAAA==.',
Mc='Mcat:BAAALgAECgMJAwAAAA==.Mcnaugh:BAABLgAECn8qAAMaAAkJWQ8AHAB4AQAaAAkJpA4AHAB4AQAZAAQJKRSE5ADLAAAAAA==.Mcsaltface:BAABLgAECn8hAAIKAAkJZRkNLABOAgAKAAkJZRkNLABOAgAAAA==.',
Me='Meddic:BAAALgAECgIJAgAAAA==.Menaras:BAACLgAFFH8KAAMMAAMJfw5ZWQCUAAAMAAMJfw5ZWQCUAAAUAAIJZgLRSgBhAAAuAAQKfywAAxQACQkmHTsSAJECABQACQkmHTsSAJECAAwACAmOF89LAHwBAAAA.Menarot:BAABLgAFFH8GAAIZAAMJtQdwrwC/AAAZAAMJtQdwrwC/AAABLgAFFAMJCgAMAH8OAA==.Mendais:BAAALgADCgkJCwAAAA==.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAFFAYJFwALALMcAA==.',
Mi='Mikeydluffy:BAABLgAECn8aAAIcAAkJVBXTFQAGAgAcAAkJVBXTFQAGAgAAAA==.Mirosberto:BAAALgAECgYJBgABLgAFFAUJFQAiADcaAA==.Mirosmundo:BAACLgAFFH8VAAIiAAUJNxr6GwBCAQAiAAUJNxr6GwBCAQAuAAQKfy8AAiIACQmrH9oIAPkCACIACQmrH9oIAPkCAAAA.Mistfit:BAABLgAECn8WAAITAAcJSBMSPQBzAQATAAcJSBMSPQBzAQAAAA==.Miyagi:BAAALgAECgYJEAAAAA==.Miyu:BAABLgAECn84AAQJAAkJ6RqCGwDnAQAJAAgJOhqCGwDnAQAIAAkJEhNEIwCkAQAQAAEJ1A0HeQAwAAAAAA==.',
Mo='Mod:BAABLgAECn8rAAMUAAkJlSQqDACeAgAUAAgJSSQqDACeAgAMAAYJihOrUwA3AQAAAA==.Modaka:BAAALgAECgMJBQAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moffizi:BAAALgADCgcJCwAAAA==.Moggatorash:BAAALgAECgcJEgAAAA==.Mogtham:BAABLgAECn9BAAIRAAkJ/Rd+CwAmAgARAAkJ/Rd+CwAmAgAAAA==.Moirenna:BAAALgAECgEJAQABLgAFFAgJKwANACQUAA==.Moisticklez:BAAALgAECgUJCwAAAA==.Monkeyspaul:BAABLgAECn8cAAIcAAgJQhvDFABHAgAcAAgJQhvDFABHAgABLgAECgkJKwALANgcAA==.Moonfall:BAABLgAECn8eAAMHAAYJiBENiwAGAQAHAAYJFRANiwAGAQAVAAUJHw1HHQCtAAAAAA==.Moonpig:BAAALgAECgcJCgAAAA==.Moosader:BAABLgAECn8vAAMKAAkJDBg0VADLAQAKAAgJQBY0VADLAQAOAAcJkAiVVwAdAQAAAA==.Morellea:BAACLgAFFH8UAAIHAAQJUxcFOwAyAQAHAAQJUxcFOwAyAQAuAAQKfxYAAgcACQkSGVk2AB0CAAcACQkSGVk2AB0CAAAA.Morighann:BAABLgAECn8qAAIWAAkJvSMPEwC1AgAWAAkJvSMPEwC1AgAAAA==.Morkith:BAAALgAFFAIJAgAAAA==.Morphalot:BAAALgAFFAEJAQAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mostank:BAAALgADCgMJAwAAAA==.Mousse:BAAALgADCgMJAwABLgAECgkJQwATABclAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgAECgcJEQABLgAECgkJRgACAPURAA==.',
My='Mylea:BAAALgAECgIJAgABLgAECgYJHgAHAIgRAA==.Mynkx:BAABLgAECn8tAAIKAAgJZxXqTwDWAQAKAAgJZxXqTwDWAQAAAA==.Mythyras:BAABLgAECn8uAAIeAAYJTSO5DAD2AQAeAAYJTSO5DAD2AQAAAA==.',
Na='Naeomy:BAAALgADCgkJCQAAAA==.Nahaman:BAAALgAECgYJDAAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8fAAIOAAYJJhT/OABlAQAOAAYJJhT/OABlAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8QAAMCAAYJCQmtKADpAAACAAQJ3gqtKADpAAADAAIJaQIFVQBsAAAuAAQKfx8ABQMACAl0GxElACUCAAMACAl0GxElACUCABIABQl/F7ogAPwAABEABQkdE8QyANgAAAIAAgkXF6p3AFMAAAAA.Netherite:BAABLgAECn8dAAIgAAgJMBFIBQCFAQAgAAgJMBFIBQCFAQAAAA==.Nethim:BAAALgAECgcJCQABLgAECggJHQAgADARAA==.Netre:BAABLgAECn8UAAIBAAcJewdYVADaAAABAAcJewdYVADaAAABLgAECggJEQAfAAAAAA==.Netsuke:BAAALgAECgUJBQAAAA==.Nezana:BAABLgAECn80AAQmAAkJ1xhoCwAgAgAmAAgJQhdoCwAgAgABAAkJghHOIADRAQAnAAQJJwzFFwCZAAAAAA==.',
Ni='Nianah:BAAALgADCggJEAAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8rAAIRAAkJyB1iBgCUAgARAAkJyB1iBgCUAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Nobunada:BAAALgAECgIJAgABLgAFFAEJAQAfAAAAAA==.Nobunaga:BAAALgAFFAEJAQAAAA==.Noranna:BAABLgAECn8gAAIWAAUJPhS3nQAAAQAWAAUJPhS3nQAAAQAAAA==.',
Ny='Nynsyn:BAAALgAECgUJBwABLgAECgYJLgAeAE0jAA==.',
['Nø']='Nøva:BAAALgAECgIJAwABLgAFFAUJFwAKAL4cAA==.',
Oh='Ohthesemyboo:BAAALgAECgkJEwAAAA==.Ohwellz:BAABLgAECn8dAAMMAAcJ1g00cAAGAQAMAAUJiRA0cAAGAQAUAAcJXBEQTwD2AAABLgAECggJHAAKAD8aAA==.',
On='On:BAAALgAECgEJAQAAAA==.',
Op='Ophin:BAABLgAECn8lAAIZAAgJIyCXHQCUAgAZAAgJIyCXHQCUAgAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Or:BAABLgAECn8VAAIFAAYJrxZmOwBXAQAFAAYJrxZmOwBXAQAAAA==.Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.Ornaxxi:BAAALgAECgUJCQAAAA==.',
Ov='Overheal:BAABLgAECn8bAAImAAkJ/wyNEgCcAQAmAAkJ/wyNEgCcAQAAAA==.',
Oy='Oyuki:BAAALgAECgkJCQABLgAFFAEJAQAfAAAAAA==.',
Pa='Padhu:BAABLgAECn8bAAIiAAkJagaJNAAqAQAiAAkJagaJNAAqAQAAAA==.Palox:BAAALgAECgYJBgAAAA==.Panamared:BAABLgAECn86AAIhAAkJMB/4BwCmAgAhAAkJMB/4BwCmAgAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn9DAAMIAAkJPxTjGgDuAQAIAAkJPxTjGgDuAQAQAAcJmwyDLwBfAQAAAA==.Pezza:BAABLgAECn8dAAIMAAkJaRKkMQDpAQAMAAkJaRKkMQDpAQAAAA==.',
Ph='Phantomlord:BAABLgAECn8WAAIZAAkJfhPyPQAIAgAZAAkJfhPyPQAIAgABLgAECgkJKAAEAPsUAA==.Phaze:BAABLgAECn8aAAIXAAkJ0BeBFAABAgAXAAkJ0BeBFAABAgAAAA==.Phia:BAABLgAECn8eAAMWAAkJ/x4ZEgCnAgAWAAkJ/x4ZEgCnAgAXAAEJEhWBLABCAAAAAA==.Pholcus:BAAALgAECgUJEAAAAA==.',
Pr='Prothagon:BAABLgAECn8rAAMmAAkJsxf/BwBuAgAmAAkJsxf/BwBuAgABAAIJQBa3dgByAAAAAA==.',
Ps='Psylix:BAABLgAECn88AAMYAAkJWR21CACeAgAYAAkJWR21CACeAgAHAAEJZwvDEgEyAAAAAA==.',
Pu='Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAABLgAECn8bAAIKAAUJJAsY8gDFAAAKAAUJJAsY8gDFAAAAAA==.Raevennlumis:BAABLgAECn8cAAIKAAkJUgY0owAwAQAKAAkJUgY0owAwAQAAAA==.Rahkhard:BAABLgAECn8eAAIiAAkJ6xryCwB0AgAiAAkJ6xryCwB0AgAAAA==.Randrius:BAAALgADCgYJBgAAAA==.Ransha:BAABLgAECn8VAAIUAAcJJBB6QAAuAQAUAAcJJBB6QAAuAQABLgAECgkJMwAVAEMSAA==.Rascdit:BAABLgAECn8UAAIRAAgJPQ9pIABGAQARAAgJPQ9pIABGAQAAAA==.',
Re='Redwood:BAABLgAECn8ZAAIRAAgJGwoJMADlAAARAAgJGwoJMADlAAAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Renwic:BAAALgAECgMJBgAAAA==.Reylani:BAEALgAECgcJBwABLgAECgkJNAAGACkeAA==.',
Rh='Rheingard:BAAALgAECgEJAQAAAA==.Rhemiroll:BAABLgAECn8WAAMcAAgJpwvWSQDXAAAcAAcJ4gnWSQDXAAATAAcJ3AMzegClAAAAAA==.Rhintalle:BAEALgAECgEJAQABLgAECgUJGAAYAIcRAA==.',
Ri='Rickroll:BAAALgAECgMJBQAAAA==.Riepa:BAAALgADCgEJAQABLgAECggJEQAfAAAAAA==.Risotto:BAABLgAECn9DAAMTAAkJFyXPAQC5AwATAAkJFyXPAQC5AwAcAAEJkBdokAA9AAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgAECgUJCQAAAA==.Rolli:BAAALgADCgkJCQAAAA==.',
Ru='Ruaic:BAAALgAECgUJBQAAAA==.Rumblelight:BAABLgAECn8WAAIKAAgJpwsvkgBMAQAKAAgJpwsvkgBMAQAAAA==.Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgcJDwAAAA==.Sagehawk:BAABLgAECn8ZAAIWAAgJnxSnRwDGAQAWAAgJnxSnRwDGAQAAAA==.Saitamà:BAAALgADCgMJAwAAAA==.Sali:BAAALgAECgEJAgAAAA==.Salmuna:BAAALgADCgEJAQAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIcAAgJJhSxJACKAQAcAAgJJhSxJACKAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAABLgAECn82AAIEAAkJHSDLEwDhAgAEAAkJHSDLEwDhAgAAAA==.Sarova:BAAALgAECgYJEQAAAA==.Satori:BAABLgAECn8bAAITAAUJDh1RNgCTAQATAAUJDh1RNgCTAQAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJBAAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.Scone:BAAALgAECgYJBgAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAABLgAECn8xAAIZAAkJ8xwaHwCMAgAZAAkJ8xwaHwCMAgAAAA==.Sellidor:BAABLgAECn8fAAIWAAkJKyD1EgC2AgAWAAkJKyD1EgC2AgAAAA==.Senamue:BAAALgADCggJCAAAAA==.Seriniyaa:BAABLgAECn8ZAAINAAgJYAM6wADLAAANAAgJYAM6wADLAAAAAA==.',
Sh='Shaey:BAAALgAECgQJBAAAAA==.Shamanthá:BAAALgAECgMJAwAAAA==.Shaureesa:BAAALgAECgQJBAAAAA==.Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8oAAIKAAkJOwOe7wDIAAAKAAkJOwOe7wDIAAAAAA==.Shirito:BAABLgAECn8uAAIZAAkJGyaUBgBBAwAZAAkJGyaUBgBBAwAAAA==.Shiritodh:BAABLgAECn8eAAIHAAgJeCXjFwCEAgAHAAgJeCXjFwCEAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8wAAMeAAkJKiNMAgANAwAeAAkJKiNMAgANAwAKAAYJsBY2egCGAQABLgAFFAQJCAARALQbAA==.Shugo:BAAALgAECgYJEwAAAA==.Shune:BAAALgAECgYJBgAAAA==.Shyle:BAAALgAECgQJCQAAAA==.',
Si='Sienje:BAABLgAECn84AAIKAAkJ8B8xEADiAgAKAAkJ8B8xEADiAgAAAA==.Simpleson:BAABLgAECn8pAAMNAAkJ1hk0IgBXAgANAAkJ1hk0IgBXAgAdAAUJxQ7ONADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAABLgAECn8bAAMYAAcJPhQeKgAoAQAYAAYJzBYeKgAoAQAHAAYJ7wrGpwDRAAAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAABLgAECn8YAAImAAYJaRqCDwDPAQAmAAYJaRqCDwDPAQABLgAECgkJAwAfAAAAAA==.Skribble:BAABLgAECn8cAAMQAAYJBw/pOQAnAQAQAAYJBw/pOQAnAQAJAAYJ9gkySgDjAAAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slackbear:BAABLgAECn8rAAINAAgJYhlkMQARAgANAAgJYhlkMQARAgAAAA==.Slaete:BAABLgAECn8ZAAIYAAgJAwhGMAABAQAYAAgJAwhGMAABAQAAAA==.Slycen:BAAALgADCgcJBwAAAA==.',
So='Sokey:BAABLgAECn8XAAIWAAcJeAzDeABJAQAWAAcJeAzDeABJAQAAAA==.Solemn:BAABLgAECn8xAAIJAAkJ5SD6BAAHAwAJAAkJ5SD6BAAHAwABLgAECgkJHwAWACsgAA==.Soleva:BAAALgADCgkJDwAAAA==.Solidious:BAAALgAECgQJBQAAAA==.Solrana:BAABLgAECn8fAAMZAAgJ/gSvsAAQAQAZAAgJ/gSvsAAQAQAbAAEJOANiQgAdAAAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgAECgYJCQAAAA==.Sorren:BAAALgAECgIJAgAAAA==.Sorrows:BAABLgAECn8YAAIdAAgJ7wqhEwAQAQAdAAgJ7wqhEwAQAQAAAA==.Sosukesagara:BAAALgAECgYJCQAAAA==.Sotta:BAAALgAECgMJBQAAAA==.Soulbled:BAABLgAECn8mAAIVAAkJmQ40DQCEAQAVAAkJmQ40DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAABLgAECn8oAAIMAAgJ0B9RDQDpAgAMAAgJ0B9RDQDpAgAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAABLgAECn8aAAIKAAgJCAqwmQA/AQAKAAgJCAqwmQA/AQAAAA==.Superbautumn:BAABLgAECn8ZAAIKAAkJox+CKgBVAgAKAAkJox+CKgBVAgAAAA==.',
Sy='Sylo:BAABLgAECn8lAAIZAAkJyBUFQwD3AQAZAAkJyBUFQwD3AQAAAA==.Synalaid:BAAALgAECgQJBQAAAA==.Synnyca:BAAALgAECgQJCAABLgAECgYJLgAeAE0jAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAABLgAECn8VAAINAAcJBg+xgwAxAQANAAcJBg+xgwAxAQAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIZAAkJsht+KACYAgAZAAkJsht+KACYAgAAAA==.Tadoshi:BAAALgADCgEJAQAAAA==.Taeonaki:BAAALgAECgMJAwAAAA==.Tagnaras:BAAALgAECgcJEwAAAA==.Tahlang:BAAALgAECgEJBQAAAA==.Tali:BAABLgAECn8pAAMWAAkJChCTPADqAQAWAAkJChCTPADqAQApAAEJYwYvQwAiAAAAAA==.Taliasluage:BAAALgAECgUJDgABLgAECgkJNQAEAEsaAA==.Tamune:BAABLgAECn8YAAIkAAkJvh12AgCvAgAkAAkJvh12AgCvAgAAAA==.Tangle:BAABLgAECn8eAAMDAAcJlxlfJwASAgADAAcJlxlfJwASAgACAAYJ/wH6agBwAAABLgAECgkJAwAfAAAAAA==.Tanka:BAABLgAECn85AAMGAAkJ7SRNAQBYAwAGAAkJ7SRNAQBYAwALAAIJfRI4OwByAAAAAA==.Tanuki:BAAALgADCgkJMwAAAA==.Tashlaraz:BAEBLgAECn8YAAIYAAUJhxH9NgDaAAAYAAUJhxH9NgDaAAAAAA==.Tasi:BAAALgADCgEJAQAAAA==.Taurannosaur:BAAALgAECgEJAwAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.Tavia:BAAALgADCgUJBQABLgAECgkJNAAfAAAAAQ==.',
Te='Telkas:BAAALgAECgYJDAAAAA==.Temporantus:BAABLgAECn8VAAIRAAkJdxKTEgDCAQARAAkJdxKTEgDCAQAAAA==.Tenko:BAABLgAECn8qAAIEAAkJZxelNQA/AgAEAAkJZxelNQA/AgAAAA==.Texaspete:BAAALgADCgIJAwAAAA==.',
Th='Thaddeus:BAABLgAECn8mAAIUAAkJyhCeKQCgAQAUAAkJyhCeKQCgAQAAAA==.Thariane:BAAALgADCgcJDgABLgAECgEJAQAfAAAAAA==.Thaxxas:BAAALgADCgYJCQAAAA==.Therm:BAACLgAFFH8NAAIKAAQJsiZUEwDCAQAKAAQJsiZUEwDCAQAuAAQKf0MAAgoACQmrJtMAAI8DAAoACQmrJtMAAI8DAAAA.Thoramier:BAABLgAECn8jAAQeAAkJRBs6DAD9AQAeAAcJfB46DAD9AQAKAAYJvBF3swAXAQAOAAIJGhQobgB6AAAAAA==.Thorgrymm:BAAALgAECgMJAwAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timadia:BAAALgAECgEJAQAAAA==.Timoonja:BAAALgAECgYJDQAAAA==.',
To='Tonatuih:BAACLgAFFH8JAAMHAAMJrA2gaQCyAAAHAAMJxgmgaQCyAAAYAAIJFQ9kIQCGAAAuAAQKfzsABAcACQmQH/ckADcCAAcACAnvG/ckADcCABgACQlEG6YZAK8BABUABwkIFKINAHwBAAAA.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAgJHwALAOgiAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAABLgAECn8qAAIoAAkJ6xgdBgAcAgAoAAkJ6xgdBgAcAgAAAA==.Triipod:BAAALgAECgIJAgAAAA==.Trinkat:BAABLgAECn8bAAIEAAUJpgTjBwGcAAAEAAUJpgTjBwGcAAAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgkJDQAAAA==.Tynk:BAAALgAECgQJBAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tynnyri:BAAALgAECgEJAQABLgAECggJKAAMANAfAA==.Typicallama:BAAALgAECggJAgABLgAECgkJFwANAB0PAA==.Tyreitherinn:BAAALgAECgMJBgAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.Unìqùe:BAAALgADCgEJAQAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAABLgAECn8ZAAIcAAgJoQcfQgDzAAAcAAgJoQcfQgDzAAAAAA==.Vaerethra:BAAALgADCgEJAQAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn9VAAINAAkJMgc+cwBSAQANAAkJMgc+cwBSAQAAAA==.Valsedor:BAAALgAECgYJBgAAAA==.Valwar:BAABLgAECn8kAAIFAAkJ8xkkHABsAgAFAAkJ8xkkHABsAgAAAA==.Vanwyngarden:BAAALgAECgEJAQAAAA==.Vareyn:BAABLgAECn8dAAMeAAcJ9QqIJwDWAAAeAAcJjwmIJwDWAAAKAAMJrAqz+wCcAAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgUJCwAAAA==.Velle:BAAALgAFFAIJAwABLgAFFAMJCgAWAMoFAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAACLgAFFH8MAAIKAAUJGBlsMwBCAQAKAAUJGBlsMwBCAQAuAAQKfyMAAx4ACAmQIrEKABsCAB4ABwmoG7EKABsCAAoABwmQIF5HAA0CAAAA.Vorth:BAABLgAECn84AAMbAAkJSxzJBAB1AgAbAAkJIhvJBAB1AgAZAAcJiRTsvgD8AAAAAA==.Vorükh:BAABLgAECn8XAAMkAAcJCApBDQBKAQAkAAYJaAtBDQBKAQAhAAYJsANrQgCzAAABLgAECgkJHgASAHARAA==.',
Vy='Vyrlana:BAACLgAFFH8HAAImAAMJgARvIwB9AAAmAAMJgARvIwB9AAAuAAQKfxwAAyYACQncEl4PANIBACYACQncEl4PANIBAAEABgnRAuZIALQAAAAA.',
Wa='Waldir:BAABLgAECn9AAAMOAAkJsySaAQChAwAOAAkJsySaAQChAwAKAAIJuB7R/wC0AAAAAA==.Waldstein:BAABLgAECn8zAAIZAAcJfBjsWwCxAQAZAAcJfBjsWwCxAQAAAA==.Wanted:BAABLgAECn8oAAQKAAcJuw+HhwBrAQAKAAcJYw+HhwBrAQAOAAUJnBLKSQATAQAeAAYJSwqRLgCrAAAAAA==.Watz:BAABLgAECn83AAIWAAkJqxc9LQAkAgAWAAkJqxc9LQAkAgAAAA==.',
We='Wensa:BAAALgAECgYJCwAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xenophage:BAAALgADCgMJAwAAAA==.Xessala:BAAALgAECgUJBgAAAA==.',
Xh='Xheero:BAACLgAFFH8NAAIWAAMJuBIVXgDhAAAWAAMJuBIVXgDhAAAuAAQKfzsAAhYACQmcHtITAK8CABYACQmcHtITAK8CAAAA.Xheerom:BAAALgAECgcJEgAAAA==.',
Ye='Yeast:BAAALgAECgYJCAAAAA==.',
Yu='Yulica:BAABLgAECn8gAAIEAAUJABB82ADhAAAEAAUJABB82ADhAAAAAA==.',
Za='Zaffy:BAABLgAECn8wAAIdAAkJWxKQCAC/AQAdAAkJWxKQCAC/AQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgAECgMJBgAAAA==.Zaleron:BAAALgAECggJCQAAAA==.Zanazath:BAABLgAECn8dAAMnAAcJ0Ro3EADZAQAnAAYJRhw3EADZAQABAAYJvhMWRgAOAQAAAA==.Zano:BAAALgAECgUJBwAAAA==.Zaruba:BAACLgAFFH8GAAIUAAMJigfrOgCdAAAUAAMJigfrOgCdAAAuAAQKfzYAAxQACQmxEGImALQBABQACQmxEGImALQBAAwAAgnnAJyaADgAAAEuAAQKCQlGAAIA9REA.Zatheon:BAABLgAECn8lAAIKAAgJXhkdVADLAQAKAAgJXhkdVADLAQAAAA==.Zatkyng:BAACLgAFFH8GAAIcAAMJoAo5KACqAAAcAAMJoAo5KACqAAAuAAQKfxwAAhwACAnmD3I9AAYBABwACAnmD3I9AAYBAAAA.',
Ze='Zekos:BAAALgAECgcJCgAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8rAAILAAkJ2Bz/CACOAgALAAkJ2Bz/CACOAgAAAA==.Zimdalar:BAABLgAECn8kAAMiAAYJwxwEIwCPAQAiAAYJwxwEIwCPAQAcAAEJ2QzcmwAxAAAAAA==.',
Zo='Zolhs:BAAALgAECgEJAgAAAA==.Zolls:BAAALgAECgMJBgAAAA==.',
Zu='Zulre:BAABLgAECn9XAAIZAAkJvBrIIQB+AgAZAAkJvBrIIQB+AgAAAA==.',
['Ôv']='Ôverkill:BAAALgAECgIJAwABLgAECgkJGwAmAP8MAA==.',
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
