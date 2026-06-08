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
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Ackrenoth:BAABLgAECn8nAAIBAAkJ0xHJIQDDAQABAAkJ0xHJIQDDAQAAAA==.',
Ad='Adynn:BAACLgAFFH8GAAMCAAMJeBdQKQDUAAACAAMJeBdQKQDUAAADAAEJQhIJZwA8AAAuAAQKfzkAAwIACQmhJZMBAGMDAAIACQmhJZMBAGMDAAMAAgkyHYueAGoAAAAA.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAAALgAECgcJEQAAAA==.',
Ag='Agrathayn:BAAALgAECgYJCgAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJNQAEAEsaAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alanatre:BAAALgADCggJCAAAAA==.Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAABLgAECn83AAMFAAkJBia8AQBdAwAFAAkJBia8AQBdAwAGAAEJ6RTTawA5AAAAAA==.Allyeska:BAAALgAECgMJAwAAAA==.Alnharaelune:BAAALgADCgkJEQAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAABLgAECn8fAAIHAAYJZRHhfQAXAQAHAAYJZRHhfQAXAQAAAA==.',
An='Anali:BAACLgAFFH8GAAIIAAQJaBWAEwAUAQAIAAQJaBWAEwAUAQAuAAQKfx4AAggACQlnIPkHAOACAAgACQlnIPkHAOACAAAA.Anani:BAABLgAECn8nAAIJAAkJxhDCHADYAQAJAAkJxhDCHADYAQAAAA==.Andavin:BAABLgAECn8tAAIKAAYJ2ATA9QC2AAAKAAYJ2ATA9QC2AAAAAA==.Angreifer:BAACLgAFFH8RAAILAAUJ2B2bDABOAQALAAUJ2B2bDABOAQAuAAQKfy8ABAsACQmvHPUKADUCAAsACAnBHvUKADUCAAUACQn1DmEyAOIBAAYAAgnfDk9xADAAAAAA.Angron:BAAALgAECgIJAgAAAA==.Anori:BAABLgAECn8mAAICAAgJNhjpGQDvAQACAAgJNhjpGQDvAQAAAA==.',
Ao='Aonar:BAABLgAECn8UAAIMAAUJNBU8XQA1AQAMAAUJNBU8XQA1AQAAAA==.',
Ar='Arc:BAABLgAECn8uAAINAAkJOiHNCQD+AgANAAkJOiHNCQD+AgAAAA==.Archenteron:BAAALgAECgQJCAAAAA==.Arctat:BAAALgAECgMJAwAAAA==.Ardorcinder:BAAALgAECgUJDQAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJCwAAAA==.Artea:BAAALgAECgYJBgAAAA==.',
As='Asbjorne:BAABLgAECn8kAAIOAAkJuxS1GQAtAgAOAAkJuxS1GQAtAgAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
Au='Audi:BAAALgADCgQJCQAAAA==.Augamand:BAAALgAECgYJCAAAAA==.Autumnmoon:BAABLgAECn8wAAIPAAgJUxDKBACGAQAPAAgJUxDKBACGAQAAAA==.',
Av='Avelos:BAACLgAFFH8PAAQIAAUJSwb4FQD8AAAIAAUJSwb4FQD8AAAJAAIJWAO1MABnAAAQAAEJ+AdJRgA6AAAuAAQKfy8ABAgACQm4GeQZAO0BAAgACQm4GeQZAO0BABAABQktBspGAIYAAAkAAgmuDHpqAGIAAAAA.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAABLgAECn8uAAURAAkJlBwDBwB7AgARAAkJ8RsDBwB7AgACAAYJZAoQTgDxAAASAAEJ3BxqPQBVAAADAAIJIwN8yQA3AAAAAA==.Ayzmist:BAAALgAECgYJCQAAAA==.Ayzmyth:BAABLgAECn8lAAITAAcJbw/GQQBMAQATAAcJbw/GQQBMAQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAIMAAcJ7yAVDwCgAgAMAAcJ7yAVDwCgAgAAAA==.Bashra:BAAALgAECgYJEQAAAA==.',
Be='Beasic:BAABLgAECn9BAAMUAAkJWg2RUQDhAAAUAAcJxwmRUQDhAAAMAAYJyAGqpwBmAAAAAA==.Beastmode:BAAALgAECggJDwAAAA==.Beletili:BAABLgAECn81AAIIAAkJ5xfXDgBrAgAIAAkJ5xfXDgBrAgAAAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn8zAAMVAAkJQxLGFAD5AAAHAAkJJBEtUwCrAQAVAAYJWhLGFAD5AAAAAA==.Birdman:BAAALgAECgYJEwABLgAECgkJMwAVAEMSAA==.Bismuth:BAAALgAECgcJDwAAAA==.',
Bj='Bjornin:BAAALgAECgEJAQAAAA==.',
Bl='Blackraven:BAABLgAECn8lAAMWAAgJpx1hMgAIAgAWAAYJKB5hMgAIAgAXAAcJgBgdHQCvAQAAAA==.Blatendrg:BAABLgAECn8vAAIBAAkJ9BC+JACvAQABAAkJ9BC+JACvAQAAAA==.Blindcloud:BAABLgAECn8XAAIYAAgJAgazMADvAAAYAAgJAgazMADvAAAAAA==.',
Bo='Boot:BAABLgAECn8bAAIOAAYJWxrRJwDCAQAOAAYJWxrRJwDCAQAAAA==.Bophedes:BAABLgAECn8XAAMZAAgJZRcdRADuAQAZAAgJZRcdRADuAQAaAAEJbw6dWQAuAAAAAA==.Borodemonin:BAEBLgAECn8dAAIHAAYJLiR8LQAGAgAHAAYJLiR8LQAGAgABLgAFFAUJEwAJADIlAA==.Bosstun:BAAALgADCgMJAwAAAA==.Bozrohin:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn9CAAIIAAkJkRXbFgALAgAIAAkJkRXbFgALAgAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Brieanna:BAAALgADCgQJCwAAAA==.Bromith:BAAALgAECgEJAQAAAA==.Brugen:BAAALgAECgcJCgAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgYJDgAAAA==.Cariñosa:BAAALgAECgEJAQAAAA==.Carøline:BAAALgAECgEJAQAAAA==.Caska:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgUJCwAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8vAAMZAAkJ0R1lHACUAgAZAAkJ0R1lHACUAgAbAAEJ3wtJGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgYJEQAAAA==.Charles:BAABLgAECn8tAAIcAAkJlSTZAwAYAwAcAAkJlSTZAwAYAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiarus:BAAALgADCgkJGAABLgAFFAUJEQALANgdAA==.Chiot:BAABLgAECn8+AAILAAkJ7B2mBgCVAgALAAkJ7B2mBgCVAgAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8lAAMFAAkJAhkJHAAHAgAFAAkJ6hcJHAAHAgALAAUJbhkCJAADAQAAAA==.Chuga:BAABLgAECn8iAAMNAAgJQg7tZABwAQANAAgJTg3tZABwAQAdAAQJHQ3PMABSAAAAAA==.',
Ci='Cimerian:BAABLgAECn8hAAMeAAgJWwzbHwAJAQAeAAcJoA3bHwAJAQAKAAUJigWSCQGeAAAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECggJIwAMANcOAA==.',
Co='Cobalticus:BAAALgAECgYJDgAAAA==.Corange:BAAALgAECgEJAQAAAA==.Corlock:BAAALgAECgQJBAAAAA==.Cormech:BAAALgAECgcJEwAAAA==.Cornite:BAABLgAECn8YAAIZAAgJDg2kdwBsAQAZAAgJDg2kdwBsAQAAAA==.',
Cr='Crizzo:BAABLgAECn85AAIWAAkJ6B8fDgDWAgAWAAkJ6B8fDgDWAgAAAA==.',
Cy='Cyndrial:BAAALgADCgQJDwAAAA==.',
Da='Daddyslilgrl:BAABLgAECn8iAAINAAcJ8wMZvADMAAANAAcJ8wMZvADMAAAAAA==.Dakra:BAEBLgAECn80AAMGAAkJKR4nBQCxAgAGAAkJKR4nBQCxAgALAAEJOwz2TwAvAAAAAA==.Dalamar:BAAALgAFFAMJCQAAAQ==.Dalandis:BAAALgAFFAEJAQAAAA==.Dalyeth:BAABLgAECn8pAAIVAAcJBSaZAwCRAgAVAAcJBSaZAwCRAgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAACLgAFFH8JAAIWAAMJzw09GQCiAAAWAAMJzw09GQCiAAAuAAQKfxQAAhYACAmcHrALAOUCABYACAmcHrALAOUCAAAA.Daunt:BAAALgAECggJEgABLgAECgkJQQACAE8RAA==.',
De='Decypher:BAABLgAECn8pAAISAAkJ+BYICQAnAgASAAkJ+BYICQAnAgABLgAFFAIJAgAfAAAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Deliverance:BAAALgAFFAQJDwABLgAFFAMJCQAfAAAAAQ==.Demonablaze:BAAALgAECgIJAwAAAA==.Dentik:BAABLgAECn80AAMDAAkJvQ+mOgChAQADAAkJvQ+mOgChAQARAAIJ4gJhcAAmAAAAAA==.Denuma:BAAALgAECgYJBgAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgQJCQABLgAFFAIJAgAfAAAAAA==.Dheriana:BAAALgAFFAIJAgAAAA==.',
Di='Diamair:BAABLgAECn8+AAMgAAkJTRnvAwC9AQAEAAkJlBOuRQAEAgAgAAgJGBjvAwC9AQAAAA==.Diamones:BAAALgAECgMJAwAAAA==.Dixiee:BAABLgAECn8WAAIJAAcJbgTASgDaAAAJAAcJbgTASgDaAAAAAA==.',
Dn='Dnegelpal:BAABLgAECn8mAAIKAAkJUxBLYQCjAQAKAAkJUxBLYQCjAQAAAA==.',
Do='Docbison:BAAALgADCgQJCQABLgAECgYJDAAfAAAAAA==.Dodgecharger:BAABLgAECn8ZAAIMAAYJrwQThADFAAAMAAYJrwQThADFAAAAAA==.Dornix:BAABLgAECn8pAAINAAgJZyBkKgAqAgANAAgJZyBkKgAqAgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgcJDAAAAA==.Dragonfood:BAABLgAECn8fAAIWAAcJGA/ZZwBnAQAWAAcJGA/ZZwBnAQAAAA==.Drakilu:BAABLgAECn9CAAIWAAkJQB4XEgC2AgAWAAkJQB4XEgC2AgAAAA==.Drasic:BAACLgAFFH8PAAIDAAMJFRemNADXAAADAAMJFRemNADXAAAuAAQKfzwAAgMACQmyIfIEAGIDAAMACQmyIfIEAGIDAAAA.Dreamcloud:BAAALgAECgUJBQAAAA==.Dreddscott:BAAALgAECgUJBQABLgAECgkJOgAhADAfAA==.Drophin:BAAALgADCgkJGwAAAA==.Drunken:BAABLgAECn8xAAIiAAgJ3R/wCwBuAgAiAAgJ3R/wCwBuAgAAAA==.Druphin:BAAALgADCgYJEgAAAA==.',
Du='Durward:BAABLgAECn9EAAQZAAkJzyIJCgAYAwAZAAkJzyIJCgAYAwAaAAQJ/w5NNwCtAAAbAAIJNxfVJgCDAAAAAA==.Duvo:BAABLgAECn8ZAAIWAAcJ0xyASAC8AQAWAAcJ0xyASAC8AQAAAA==.',
Dw='Dwarfo:BAABLgAECn8VAAIKAAcJzAWfzQDpAAAKAAcJzAWfzQDpAAAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.Dwarvey:BAAALgADCgMJAwAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAABLgAECn8dAAMRAAgJbQf/NAC/AAARAAgJbQf/NAC/AAACAAQJpQAIhgAyAAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIbAAgJlR6GAgCPAgAbAAgJlR6GAgCPAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAABLgAECn8bAAINAAkJIQJhxAC+AAANAAkJIQJhxAC+AAAAAA==.Elemental:BAACLgAFFH8MAAMUAAQJmArRJwDtAAAUAAQJmArRJwDtAAAMAAIJxQpOYABtAAAuAAQKfzEAAxQACQmyHIIMAJICABQACQmyHIIMAJICAAwAAwm4CRmOAF4AAAEuAAUUBgkQAAIACQkA.Eleussen:BAAALgAECgMJAwAAAA==.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgAECgMJBAAAAA==.Elloseth:BAABLgAECn8nAAIJAAcJtB3HFwACAgAJAAcJtB3HFwACAgAAAA==.Elmorin:BAAALgAECggJEwAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAABLgAECn8ZAAIWAAYJMQ0NmQAAAQAWAAYJMQ0NmQAAAQAAAA==.',
Ep='Epica:BAABLgAECn8oAAIEAAcJ+xQliQBfAQAEAAcJ+xQliQBfAQAAAA==.',
Er='Eragonhawk:BAABLgAECn8qAAIKAAgJFh3kKABUAgAKAAgJFh3kKABUAgAAAA==.Erelynn:BAAALgAECgQJBAABLgAECgkJJwAIAMkRAA==.Eroldan:BAABLgAECn8hAAMMAAgJmR/XEgCrAgAMAAgJmR/XEgCrAgAUAAQJUA04YAC0AAAAAA==.Erovianoria:BAACLgAFFH8KAAIWAAMJygX9YwDBAAAWAAMJygX9YwDBAAAuAAQKfykAAhYACQm/Fv8WAIACABYACQm/Fv8WAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.Eräthis:BAAALgAECgMJAwAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAABLgAECn8qAAIYAAgJdyJ7CACXAgAYAAgJdyJ7CACXAgABLgAFFAcJKAANADYXAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8zAAIMAAkJSheOGgBqAgAMAAkJSheOGgBqAgAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Ex='Expire:BAAALgAECgIJAgAAAA==.',
Fa='Fatalfury:BAABLgAECn8jAAMKAAkJShkAVQDBAQAKAAgJ7xcAVQDBAQAOAAQJgweTXwCqAAAAAA==.Fauxstorm:BAABLgAECn8bAAMjAAUJsBrJFwA6AQAjAAUJsBrJFwA6AQAUAAIJ/BEimQA1AAAAAA==.',
Fi='Finngan:BAABLgAECn8uAAIdAAkJoQ7DCgCHAQAdAAkJoQ7DCgCHAQAAAA==.Fireina:BAABLgAECn8WAAIPAAYJigG8DgBcAAAPAAYJigG8DgBcAAAAAA==.',
Fl='Fluria:BAAALgAECgIJAgABLgAECgkJJwAIAMkRAA==.',
Fo='Forestkin:BAABLgAECn8VAAIRAAYJ0B9SEQDEAQARAAYJ0B9SEQDEAQABLgAECgcJKQAVAAUmAA==.Fossilis:BAABLgAECn8YAAMkAAcJHgV4EgDzAAAkAAcJAQV4EgDzAAAhAAUJ2wIUTwCzAAAAAA==.',
Fr='Frenzyz:BAAALgADCgIJAgAAAA==.Friartuk:BAAALgADCgEJAQAAAA==.Frozenthunda:BAAALgAECgQJCgAAAA==.',
Fu='Furna:BAABLgAECn8yAAIQAAcJgRKgJACcAQAQAAcJgRKgJACcAQAAAA==.',
Fy='Fyahka:BAAALgADCgQJBAAAAA==.Fyon:BAAALgAECgYJCQAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAACLgAFFH8OAAIFAAQJqQuCJQAOAQAFAAQJqQuCJQAOAQAuAAQKfzYAAgUACQn4F0wWADYCAAUACQn4F0wWADYCAAAA.Galileia:BAAALgADCgMJBAAAAA==.',
Gh='Ghorienge:BAAALgAECgYJDwAAAA==.Ghostcat:BAAALgAECgIJAgAAAA==.',
Gi='Gilox:BAABLgAECn8gAAIkAAkJ5BCvBwDSAQAkAAkJ5BCvBwDSAQAAAA==.',
Gn='Gndmexia:BAAALgAECgYJEwAAAA==.Gneiss:BAAALgAECgYJEQAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8iAAIDAAkJiCACBwBAAwADAAkJiCACBwBAAwAAAA==.',
Gr='Graymon:BAABLgAECn8bAAIFAAUJjR2ZPABKAQAFAAUJjR2ZPABKAQAAAA==.Greebo:BAABLgAECn8bAAIRAAUJ0QMWWgBLAAARAAUJ0QMWWgBLAAAAAA==.Griknor:BAABLgAECn8fAAMGAAYJRgU/IgDaAAAGAAYJRgU/IgDaAAAFAAQJBgM4ewBzAAAAAA==.Grimniel:BAAALgAECgIJAwAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAABLgAECn8UAAIKAAgJWRudMQAvAgAKAAgJWRudMQAvAgAAAA==.Gussie:BAAALgADCgQJBAABLgAECgcJFgAJAG4EAA==.',
Gw='Gwenyver:BAABLgAECn8hAAIKAAgJwAJ07gC/AAAKAAgJwAJ07gC/AAAAAA==.',
Ha='Hadoukendk:BAAALgAECggJEwAAAA==.Hafaken:BAAALgAECgEJAQAAAA==.Hallien:BAAALgADCgEJAQAAAA==.Hamord:BAABLgAECn8fAAIeAAkJmQ4AGQBGAQAeAAkJmQ4AGQBGAQAAAA==.Hansdelbruk:BAAALgADCgEJAQAAAA==.Hardlight:BAAALgADCggJCQAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgAECgQJBAAAAA==.Harliqynn:BAACLgAFFH8GAAIWAAMJ3Bs9TgD4AAAWAAMJ3Bs9TgD4AAAuAAQKfxwAAhYACQngGu0gAEACABYACQngGu0gAEACAAAA.Harlock:BAABLgAECn8jAAIhAAkJXxxsDwAoAgAhAAkJXxxsDwAoAgAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.Hazelnuts:BAAALgAECgIJAQAAAA==.',
He='Heartkiller:BAAALgAECgQJBAABLgAECgkJKAAEAPsUAA==.Hellcrazed:BAAALgADCgMJAwABLgAECgcJFgARAPwfAA==.Helleye:BAABLgAECn8cAAIRAAgJPQvfKQD5AAARAAgJPQvfKQD5AAAAAA==.',
Hi='Hiten:BAABLgAECn9CAAQhAAkJxRurCQB+AgAhAAkJvhurCQB+AgAkAAUJRBWIDQBEAQAlAAEJjwigIwArAAAAAA==.',
Ho='Hopedaimond:BAABLgAECn8nAAIUAAkJ3A2lMABuAQAUAAkJ3A2lMABuAQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8/AAMWAAkJAA5wSQC5AQAWAAkJAA5wSQC5AQAXAAYJowNbPQDOAAAAAA==.',
Hy='Hypro:BAABLgAECn8xAAIMAAkJeyU7AADXAwAMAAkJeyU7AADXAwAAAA==.',
['Há']='Háides:BAAALgADCgIJAgAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIeAAcJByOXBAC6AgAeAAcJByOXBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJEwAAAA==.',
Ie='Iepa:BAAALgAECggJCQAAAA==.',
Il='Ilthad:BAABLgAECn8mAAMYAAgJ7BRFFwC6AQAYAAgJ7BRFFwC6AQAHAAEJ9QKWKQEbAAAAAA==.',
Im='Imneth:BAAALgAECgEJAQABLgAECggJHQAgADARAA==.Imperio:BAAALgADCgYJBgAAAA==.Imshalar:BAAALgAECggJEAAAAA==.',
In='Inconcvabull:BAABLgAECn8XAAINAAgJEAunfQA5AQANAAgJEAunfQA5AQAAAA==.Inferious:BAAALgAECgUJDwABLgAECggJFwAZAGUXAA==.Infurryating:BAAALgAECgkJBwAAAA==.Inistus:BAAALgADCggJCwAAAA==.',
Ir='Iralis:BAAALgAECgcJEAAAAA==.Iroar:BAAALgADCgEJAQAAAA==.',
Is='Ischadè:BAAALgAECgIJAgAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgkJEQAAAA==.Itsirk:BAABLgAECn8wAAIOAAkJuxl5EwBqAgAOAAkJuxl5EwBqAgAAAA==.',
Iz='Izyebelle:BAABLgAECn8qAAMJAAkJ5gHqWQCgAAAJAAkJ5gHqWQCgAAAIAAEJUAGReQATAAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAABLgAECn8wAAIeAAgJ3SQTAwDiAgAeAAgJ3SQTAwDiAgAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jiayou:BAAALgADCgEJAQAAAA==.Jimmydin:BAACLgAFFH8NAAIKAAQJmhT9OwAkAQAKAAQJmhT9OwAkAQAuAAQKfzwAAwoACQnKGbAkAGgCAAoACQnKGbAkAGgCAA4ACQklGbQeACICAAAA.Jix:BAABLgAECn8YAAMdAAgJkhi9DgDeAQAdAAYJtxy9DgDeAQANAAQJSAxGrQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8xAAQHAAkJhhK5RgCmAQAHAAkJ5RG5RgCmAQAVAAMJyxWlHgCSAAAYAAEJYw4QbwA2AAAAAA==.',
Ju='Juego:BAAALgADCgEJAQAAAA==.Julkan:BAAALgAECgQJBgAAAA==.Junhoong:BAABLgAECn89AAIKAAkJDxNcSwDaAQAKAAkJDxNcSwDaAQAAAA==.',
Jy='Jynnysa:BAAALgAECgcJEAABLgAECgYJLgAeAE0jAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAABLgAECn8cAAIGAAgJIBj4DQAAAgAGAAgJIBj4DQAAAgAAAA==.Kairoll:BAABLgAECn8mAAIIAAkJuBW2FgANAgAIAAkJuBW2FgANAgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Kannah:BAAALgAECgYJDAABLgAECggJFgAOAH8ZAA==.Karaa:BAABLgAECn8rAAITAAgJsQbyXgDdAAATAAgJsQbyXgDdAAAAAA==.Kariena:BAABLgAECn8nAAIWAAgJ5R6hHABuAgAWAAgJ5R6hHABuAgAAAA==.Katesluage:BAABLgAECn81AAIEAAkJSxrtNAA+AgAEAAkJSxrtNAA+AgAAAA==.Kawrrl:BAAALgAECgEJAQAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJNQAEAEsaAA==.',
Ke='Keeya:BAABLgAECn84AAIZAAgJ3RG/YACfAQAZAAgJ3RG/YACfAQAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kelkan:BAAALgAECgEJAQAAAA==.Kendari:BAABLgAECn8cAAMZAAkJzwkkuAD/AAAZAAQJzw8kuAD/AAAaAAYJ/QTxPgCJAAAAAA==.Kernasas:BAABLgAECn82AAIdAAgJ4RSbCACzAQAdAAgJ4RSbCACzAQAAAA==.Keslynn:BAAALgAECgIJAwABLgAECggJJwAWAOUeAA==.Ketrani:BAAALgAECgEJAgABLgAECggJJwAWAOUeAA==.',
Kh='Khiari:BAAALgAECgYJCgABLgAECggJJgAKAH4QAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAAALgAECgcJEgAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJKQANAGcgAA==.Kirtiao:BAAALgAECgEJAgABLgAECggJJwAWAOUeAA==.Kitalidie:BAAALgAECgQJBgABLgAECggJJwAWAOUeAA==.Kizaraan:BAABLgAECn8dAAMmAAgJewRKIgDUAAAmAAcJxgNKIgDUAAAnAAMJzwLcHgBQAAAAAA==.',
Kl='Kleyntamar:BAAALgAECgUJEwAAAA==.',
Kn='Knyghtly:BAAALgAECgkJAwAAAA==.',
Ko='Konstantien:BAAALgAECgYJBgAAAA==.Koshamunzo:BAAALgADCgYJBgAAAA==.',
Kr='Kreios:BAAALgAECgkJBwAAAA==.Kritt:BAAALgAECgYJBwAAAA==.Kritter:BAAALgAECgYJDwAAAA==.Krohm:BAABLgAECn8uAAMKAAkJcyM6BwAsAwAKAAkJcyM6BwAsAwAeAAEJ8hhMRQBEAAAAAA==.Krostana:BAAALgADCgEJAQAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgAECgYJDgAAAA==.Kungfuey:BAAALgAECgUJBQAAAA==.Kupau:BAAALgAECgQJBAAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Lanss:BAABLgAECn9MAAILAAkJESVtAQBDAwALAAkJESVtAQBDAwAAAA==.Larachel:BAABLgAECn8WAAMIAAgJRxp2EgA8AgAIAAgJRxp2EgA8AgAJAAcJShawJQCWAQAAAA==.Laur:BAABLgAECn8uAAIJAAkJaxPYHADWAQAJAAkJaxPYHADWAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8jAAIKAAkJUBztKQBPAgAKAAkJUBztKQBPAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAABLgAECn8bAAIeAAUJZR0kGABOAQAeAAUJZR0kGABOAQAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAwAAAA==.Lilipo:BAABLgAECn82AAIcAAgJzAvlMAA2AQAcAAgJzAvlMAA2AQAAAA==.Liltara:BAABLgAECn8kAAIEAAcJMQKC9QCzAAAEAAcJMQKC9QCzAAAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llamatotems:BAAALgAECgcJBwABLgAECgkJRAAZAMoNAA==.Llanz:BAAALgADCgkJKgAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAACLgAFFH8KAAINAAMJQweEfAC8AAANAAMJQweEfAC8AAAuAAQKfy0AAg0ACAm+FM9TAJwBAA0ACAm+FM9TAJwBAAAA.Lokdan:BAAALgAECgYJCQAAAA==.Loppy:BAAALgAECgIJAgAAAA==.Loula:BAABLgAECn8pAAIEAAkJHgOjxAD9AAAEAAkJHgOjxAD9AAAAAA==.Lowryder:BAACLgAFFH8IAAIhAAMJPQu4JwDXAAAhAAMJPQu4JwDXAAAuAAQKfyIAAyEACQniFMYSAAMCACEACQniFMYSAAMCACQAAQmbBmIgADEAAAAA.Loxes:BAAALgAECgcJDQABLgAECgYJCwAfAAAAAA==.Loxy:BAAALgAECgUJDAAAAA==.',
Lu='Lukam:BAAALgAECgUJEAAAAA==.Lunaellana:BAAALgAECgQJBAAAAA==.Lus:BAABLgAECn8UAAMNAAYJsRfzegBmAQANAAYJsRfzegBmAQAdAAIJuggxUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAABLgAECn8aAAUDAAgJgB3AEwCkAgADAAgJgB3AEwCkAgARAAQJPAzmRwByAAASAAIJUwRLRwA7AAACAAIJTwFxogAOAAABLgAFFAMJCAADAEcHAA==.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
['Lü']='Lüvpüp:BAAALgAECggJEQABLgAECgkJIgAZALIbAA==.',
Ma='Magicfang:BAAALgAECgYJCwAAAA==.Maiku:BAABLgAECn8/AAINAAkJcRVeLgAZAgANAAkJcRVeLgAZAgAAAA==.Makado:BAACLgAFFH8HAAQoAAQJ2QGrDgCRAAAoAAMJtwGrDgCRAAAdAAIJmwHpFgBkAAANAAEJmgGxyQApAAAuAAQKfyAABB0ACAnaCHgvAP0AAB0ABwlAB3gvAP0AAA0ABQngBe6+AMcAACgABQm9B2IgAKgAAAAA.Makaris:BAAALgADCgQJBQAAAA==.Makaveli:BAAALgAFFAIJAgAAAA==.Maknanimus:BAAALgADCgQJBAAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAABLgAECn8gAAINAAYJpBo+WwCHAQANAAYJpBo+WwCHAQAAAA==.Matheniel:BAAALgAECgEJAQAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Matua:BAAALgAECgEJAQAAAA==.Maycee:BAAALgAECgcJEwAAAA==.',
Mc='Mcnaugh:BAABLgAECn8kAAMaAAkJ7g7bGgB6AQAaAAkJJg7bGgB6AQAZAAQJKRQO3ADOAAAAAA==.Mcsaltface:BAABLgAECn8eAAIKAAgJKRq6PAAGAgAKAAgJKRq6PAAGAgAAAA==.',
Me='Meddic:BAAALgAECgIJAgAAAA==.Menaras:BAACLgAFFH8KAAMMAAMJfw4uUgCaAAAMAAMJfw4uUgCaAAAUAAIJZgIERQBpAAAuAAQKfywAAxQACQkmHTsSAJECABQACQkmHTsSAJECAAwACAmOF9xIAH0BAAAA.Menarot:BAABLgAFFH8GAAIZAAMJtQebogDEAAAZAAMJtQebogDEAAABLgAFFAMJCgAMAH8OAA==.Mendais:BAAALgADCgkJCwAAAA==.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAFFAUJEQALANgdAA==.',
Mi='Mikeydluffy:BAABLgAECn8aAAIcAAkJVBV7FAALAgAcAAkJVBV7FAALAgAAAA==.Mirosberto:BAAALgAECgYJBgABLgAFFAUJFAAiADcaAA==.Mirosmundo:BAACLgAFFH8UAAIiAAUJNxp4GQBHAQAiAAUJNxp4GQBHAQAuAAQKfy8AAiIACQmrH9oIAPkCACIACQmrH9oIAPkCAAAA.Mistfit:BAABLgAECn8WAAITAAcJSBOgOQByAQATAAcJSBOgOQByAQAAAA==.Miyagi:BAAALgAECgYJEAAAAA==.Miyu:BAABLgAECn8xAAQIAAkJEhPCIQCnAQAIAAkJEhPCIQCnAQAJAAUJdxm7MwBBAQAQAAEJ1A0ScwAwAAAAAA==.',
Mo='Mod:BAABLgAECn8rAAMUAAkJlSRlCwCgAgAUAAgJSSRlCwCgAgAMAAYJihOrUwA3AQAAAA==.Modaka:BAAALgAECgMJBQAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moffizi:BAAALgADCgcJBwAAAA==.Moggatorash:BAAALgAECgcJEgAAAA==.Mogtham:BAABLgAECn9BAAIRAAkJ/Re6CgAmAgARAAkJ/Re6CgAmAgAAAA==.Moirenna:BAAALgAECgEJAQABLgAFFAcJKAANADYXAA==.Moisticklez:BAAALgAECgUJCwAAAA==.Monkeyspaul:BAABLgAECn8cAAIcAAgJQhvDFABHAgAcAAgJQhvDFABHAgABLgAECgkJKwALANgcAA==.Moonfall:BAABLgAECn8ZAAIHAAYJFRCIhgAFAQAHAAYJFRCIhgAFAQAAAA==.Moonpig:BAAALgAECgcJCgAAAA==.Moosader:BAABLgAECn8vAAMKAAkJDBizTwDOAQAKAAgJQBazTwDOAQAOAAcJkAiVVwAdAQAAAA==.Morellea:BAACLgAFFH8RAAIHAAQJhQ5jRgAHAQAHAAQJhQ5jRgAHAQAuAAQKfxYAAgcACQkSGVk2AB0CAAcACQkSGVk2AB0CAAAA.Morighann:BAABLgAECn8qAAIWAAkJvSNwEQC7AgAWAAkJvSNwEQC7AgAAAA==.Morkith:BAAALgAFFAIJAgAAAA==.Morphalot:BAAALgAFFAEJAQAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mostank:BAAALgADCgMJAwAAAA==.Mousse:BAAALgADCgMJAwABLgAECgkJQwATABclAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgAECgcJEAABLgAECgkJQQACAE8RAA==.',
My='Mylea:BAAALgAECgIJAgABLgAECgYJGQAHABUQAA==.Mynkx:BAABLgAECn8mAAIKAAgJfhCQcwB8AQAKAAgJfhCQcwB8AQAAAA==.Mythyras:BAABLgAECn8uAAIeAAYJTSMoDAD3AQAeAAYJTSMoDAD3AQAAAA==.',
Na='Naeomy:BAAALgADCgkJCQAAAA==.Nahaman:BAAALgAECgYJDAAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8fAAIOAAYJJhRGNwBmAQAOAAYJJhRGNwBmAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8QAAMCAAYJCQnzJQDrAAACAAQJ3grzJQDrAAADAAIJaQKVUgBwAAAuAAQKfx8ABQMACAl0GxElACUCAAMACAl0GxElACUCABIABQl/Fy8fAPwAABEABQkdE8YvANgAAAIAAgkXF6lzAFMAAAAA.Netherite:BAABLgAECn8dAAIgAAgJMBHwBACLAQAgAAgJMBHwBACLAQAAAA==.Nethim:BAAALgAECgYJBgABLgAECggJHQAgADARAA==.Netre:BAABLgAECn8UAAIBAAcJewdUUQDcAAABAAcJewdUUQDcAAAAAA==.Nezana:BAABLgAECn8yAAQmAAkJ1xgsCwAhAgAmAAgJQhcsCwAhAgABAAgJdxFeKgCOAQAnAAQJJwwHFwCaAAAAAA==.',
Ni='Nianah:BAAALgADCggJEAAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8rAAIRAAkJyB34BQCVAgARAAkJyB34BQCVAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Nobunada:BAAALgAECgIJAgABLgAECgkJCQAfAAAAAA==.Nobunaga:BAAALgAECgIJBAABLgAECgkJCQAfAAAAAA==.Noranna:BAABLgAECn8bAAIWAAUJIhG3oADwAAAWAAUJIhG3oADwAAAAAA==.',
Ny='Nynsyn:BAAALgAECgIJAgABLgAECgYJLgAeAE0jAA==.',
['Nø']='Nøva:BAAALgAECgIJAwABLgAFFAQJBwAZAAwQAA==.',
Oh='Ohthesemyboo:BAAALgAECgkJEwAAAA==.Ohwellz:BAABLgAECn8dAAMMAAcJ1g07bAAHAQAMAAUJiRA7bAAHAQAUAAcJXBGmSwD2AAABLgAECggJHAAKAD8aAA==.',
On='On:BAAALgAECgEJAQAAAA==.',
Op='Ophin:BAABLgAECn8fAAIZAAcJfR2qPQADAgAZAAcJfR2qPQADAgAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Or:BAABLgAECn8VAAIFAAYJrxZWOQBZAQAFAAYJrxZWOQBZAQAAAA==.Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.Ornaxxi:BAAALgAECgQJBAAAAA==.',
Ov='Overheal:BAABLgAECn8aAAImAAgJsQw4FQBwAQAmAAgJsQw4FQBwAQAAAA==.',
Oy='Oyuki:BAAALgAECgkJCQAAAA==.',
Pa='Padhu:BAABLgAECn8aAAIiAAgJDgdAPQD+AAAiAAgJDgdAPQD+AAAAAA==.Palox:BAAALgAECgYJBgAAAA==.Panamared:BAABLgAECn86AAIhAAkJMB9FBwCqAgAhAAkJMB9FBwCqAgAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn9DAAMIAAkJPxR2GQDxAQAIAAkJPxR2GQDxAQAQAAcJmwwxLQBiAQAAAA==.Pezza:BAABLgAECn8cAAIMAAgJ0xJQOwC0AQAMAAgJ0xJQOwC0AQAAAA==.',
Ph='Phantomlord:BAABLgAECn8WAAIZAAkJfhMMOgAQAgAZAAkJfhMMOgAQAgABLgAECgkJKAAEAPsUAA==.Phaze:BAABLgAECn8aAAIXAAkJ0BdoEwAIAgAXAAkJ0BdoEwAIAgAAAA==.Phia:BAABLgAECn8eAAMWAAkJ/x4ZEgCnAgAWAAkJ/x4ZEgCnAgAXAAEJEhWBLABCAAAAAA==.Pholcus:BAAALgAECgUJEAAAAA==.',
Pr='Prothagon:BAABLgAECn8rAAMmAAkJsxe8BwBxAgAmAAkJsxe8BwBxAgABAAIJQBa1cgByAAAAAA==.',
Ps='Psylix:BAABLgAECn88AAMYAAkJWR0BCAChAgAYAAkJWR0BCAChAgAHAAEJZwtQCAEyAAAAAA==.',
Pu='Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAABLgAECn8bAAIKAAUJJAvk6QDFAAAKAAUJJAvk6QDFAAAAAA==.Raevennlumis:BAABLgAECn8cAAIKAAkJUgaPnAAxAQAKAAkJUgaPnAAxAQAAAA==.Rahkhard:BAABLgAECn8XAAIiAAkJyhlGDQBaAgAiAAkJyhlGDQBaAgAAAA==.Randrius:BAAALgADCgYJBgAAAA==.Ransha:BAABLgAECn8VAAIUAAcJJBCOPQAvAQAUAAcJJBCOPQAvAQABLgAECgkJMwAVAEMSAA==.Rascdit:BAAALgAECgcJDgAAAA==.',
Re='Redwood:BAABLgAECn8VAAIRAAYJZgtbOQCsAAARAAYJZgtbOQCsAAAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Renwic:BAAALgAECgMJBgAAAA==.Reylani:BAEALgAECgcJBwABLgAECgkJNAAGACkeAA==.',
Rh='Rheingard:BAAALgAECgEJAQAAAA==.Rhemiroll:BAAALgAECggJEAAAAA==.Rhintalle:BAEALgAECgEJAQABLgAECgUJGAAYAIcRAA==.',
Ri='Rickroll:BAAALgAECgMJBQAAAA==.Riepa:BAAALgADCgEJAQAAAA==.Risotto:BAABLgAECn9DAAMTAAkJFyWgAQC6AwATAAkJFyWgAQC6AwAcAAEJkBcEigA9AAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgAECgUJBgAAAA==.Rolli:BAAALgADCgkJCQAAAA==.',
Ru='Ruaic:BAAALgAECgUJBQAAAA==.Rumblelight:BAABLgAECn8WAAIKAAgJpws0jABNAQAKAAgJpws0jABNAQAAAA==.Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgcJDwAAAA==.Sagehawk:BAAALgAECgYJEwAAAA==.Saitamà:BAAALgADCgMJAwAAAA==.Sali:BAAALgAECgEJAgAAAA==.Salmuna:BAAALgADCgEJAQAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIcAAgJJhTCIgCOAQAcAAgJJhTCIgCOAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAABLgAECn82AAIEAAkJHSCZEgDlAgAEAAkJHSCZEgDlAgAAAA==.Sarova:BAAALgAECgYJEQAAAA==.Satori:BAABLgAECn8WAAITAAUJ2RxlNACMAQATAAUJ2RxlNACMAQAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJBAAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.Scone:BAAALgAECgYJBgAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAABLgAECn8xAAIZAAkJ8xwwHQCQAgAZAAkJ8xwwHQCQAgAAAA==.Sellidor:BAABLgAECn8dAAIWAAkJFyC6EQC5AgAWAAkJFyC6EQC5AgAAAA==.Senamue:BAAALgADCggJCAAAAA==.Seriniyaa:BAABLgAECn8VAAINAAYJpAO10QCpAAANAAYJpAO10QCpAAAAAA==.',
Sh='Shaey:BAAALgAECgQJBAAAAA==.Shamanthá:BAAALgAECgMJAwAAAA==.Shaureesa:BAAALgAECgQJBAAAAA==.Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8oAAIKAAkJOwPE5gDIAAAKAAkJOwPE5gDIAAAAAA==.Shirito:BAABLgAECn8uAAIZAAkJGybhBQBGAwAZAAkJGybhBQBGAwAAAA==.Shiritodh:BAABLgAECn8eAAIHAAgJeCXGFgCEAgAHAAgJeCXGFgCEAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8wAAMeAAkJKiMZAgAPAwAeAAkJKiMZAgAPAwAKAAYJsBY2egCGAQABLgAECgcJFgARAPwfAA==.Shugo:BAAALgAECgYJDgAAAA==.Shyle:BAAALgAECgQJCQAAAA==.',
Si='Sienje:BAABLgAECn84AAIKAAkJ8B/EDgDmAgAKAAkJ8B/EDgDmAgAAAA==.Simpleson:BAABLgAECn8pAAMNAAkJ1hnHIABaAgANAAkJ1hnHIABaAgAdAAUJxQ7ONADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAABLgAECn8bAAMYAAcJPhToJwApAQAYAAYJzBboJwApAQAHAAYJ7wpcogDRAAAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAAALgAECgcJEwABLgAECgkJAwAfAAAAAA==.Skribble:BAABLgAECn8XAAMQAAYJcQyoOgAWAQAQAAYJcQyoOgAWAQAJAAYJ9gnARgDqAAAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slackbear:BAABLgAECn8rAAINAAgJYhnKLgAXAgANAAgJYhnKLgAXAgAAAA==.Slaete:BAAALgAECggJEwAAAA==.Slycen:BAAALgADCgcJBwAAAA==.',
So='Sokey:BAABLgAECn8VAAIWAAYJlgsAlQAIAQAWAAYJlgsAlQAIAQAAAA==.Solemn:BAABLgAECn8pAAIJAAkJkB3JCAC9AgAJAAkJkB3JCAC9AgABLgAECgkJHQAWABcgAA==.Soleva:BAAALgADCgkJDwAAAA==.Solidious:BAAALgAECgQJBAAAAA==.Solrana:BAABLgAECn8bAAMZAAgJLQQotQADAQAZAAgJDgQotQADAQAbAAEJOAPIPQAeAAAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgAECgYJCQAAAA==.Sorren:BAAALgAECgIJAgAAAA==.Sorrows:BAABLgAECn8YAAIdAAgJ7wpqEgAVAQAdAAgJ7wpqEgAVAQAAAA==.Sosukesagara:BAAALgAECgYJCQAAAA==.Sotta:BAAALgAECgMJBQAAAA==.Soulbled:BAABLgAECn8mAAIVAAkJmQ40DQCEAQAVAAkJmQ40DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAABLgAECn8lAAIMAAgJ0B92DADrAgAMAAgJ0B92DADrAgAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAABLgAECn8WAAIKAAYJgwhg2ADaAAAKAAYJgwhg2ADaAAAAAA==.Superbautumn:BAABLgAECn8ZAAIKAAkJox8HKABYAgAKAAkJox8HKABYAgAAAA==.',
Sy='Sylo:BAABLgAECn8lAAIZAAkJyBW9PgD/AQAZAAkJyBW9PgD/AQAAAA==.Synalaid:BAAALgAECgQJBQAAAA==.Synnyca:BAAALgAECgQJCAABLgAECgYJLgAeAE0jAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAABLgAECn8VAAINAAcJBg80gAA0AQANAAcJBg80gAA0AQAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIZAAkJsht+KACYAgAZAAkJsht+KACYAgAAAA==.Tadoshi:BAAALgADCgEJAQAAAA==.Taeonaki:BAAALgAECgMJAwAAAA==.Tagnaras:BAAALgAECgcJEwAAAA==.Tahlang:BAAALgAECgEJBAAAAA==.Tali:BAABLgAECn8jAAMWAAkJUA/dPADiAQAWAAkJUA/dPADiAQApAAEJYwa2QAAiAAAAAA==.Taliasluage:BAAALgAECgUJCQABLgAECgkJNQAEAEsaAA==.Tamune:BAABLgAECn8VAAIkAAcJ1hy/BgDwAQAkAAcJ1hy/BgDwAQAAAA==.Tangle:BAABLgAECn8eAAMDAAcJlxlJJgATAgADAAcJlxlJJgATAgACAAYJ/wEyZwBxAAABLgAECgkJAwAfAAAAAA==.Tanka:BAABLgAECn85AAMGAAkJ7SQbAQBdAwAGAAkJ7SQbAQBdAwALAAIJfRI4OwByAAAAAA==.Tanuki:BAAALgADCgkJMwAAAA==.Tashlaraz:BAEBLgAECn8YAAIYAAUJhxEUNADbAAAYAAUJhxEUNADbAAAAAA==.Tasi:BAAALgADCgEJAQAAAA==.Taurannosaur:BAAALgAECgEJAwAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.Tavia:BAAALgADCgMJAwABLgAECgkJMgAfAAAAAQ==.',
Te='Telkas:BAAALgAECgYJCwAAAA==.Temporantus:BAAALgAECgcJEwAAAA==.Tenko:BAABLgAECn8mAAIEAAkJWRYJNgA5AgAEAAkJWRYJNgA5AgAAAA==.Texaspete:BAAALgADCgIJAwAAAA==.',
Th='Thaddeus:BAABLgAECn8mAAIUAAkJyhDAJwChAQAUAAkJyhDAJwChAQAAAA==.Thariane:BAAALgADCgcJDgABLgAECgEJAQAfAAAAAA==.Thaxxas:BAAALgADCgQJBgAAAA==.Therm:BAACLgAFFH8NAAIKAAQJsibcDwDGAQAKAAQJsibcDwDGAQAuAAQKf0IAAgoACQmrJrMAAJADAAoACQmrJrMAAJADAAAA.Thoramier:BAABLgAECn8jAAQeAAkJRButCwD+AQAeAAcJfB6tCwD+AQAKAAYJvBGjqwAaAQAOAAIJGhRLawB6AAAAAA==.Thorgrymm:BAAALgADCggJCwAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timadia:BAAALgAECgEJAQAAAA==.Timoonja:BAAALgAECgYJDAAAAA==.',
To='Tonatuih:BAACLgAFFH8IAAMHAAMJrA3YYgC2AAAHAAMJxgnYYgC2AAAYAAIJFQ86HgCGAAAuAAQKfzkABAcACQmQH2sjADcCAAcACAnvG2sjADcCABgACQlEGy8YALEBABUABgmXFqINAHwBAAAA.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAgJHwALAOgiAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAABLgAECn8qAAIoAAkJ6xh9BQAfAgAoAAkJ6xh9BQAfAgAAAA==.Triipod:BAAALgAECgIJAgAAAA==.Trinkat:BAABLgAECn8WAAIEAAUJUgQrAQGgAAAEAAUJUgQrAQGgAAAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgkJDQAAAA==.Tynk:BAAALgAECgQJBAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tynnyri:BAAALgAECgEJAQAAAA==.Typicallama:BAAALgAECggJAgABLgAECgkJFwANAB0PAA==.Tyreitherinn:BAAALgAECgMJAwAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.Unìqùe:BAAALgADCgEJAQAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAABLgAECn8VAAIcAAYJ8wYiWACiAAAcAAYJ8wYiWACiAAAAAA==.Vaerethra:BAAALgADCgEJAQAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn9MAAINAAkJnAZecABVAQANAAkJnAZecABVAQAAAA==.Valsedor:BAAALgAECgYJBgAAAA==.Valwar:BAABLgAECn8kAAIFAAkJ8xkkHABsAgAFAAkJ8xkkHABsAgAAAA==.Vareyn:BAABLgAECn8cAAMeAAcJNgqvJwDMAAAeAAcJZgivJwDMAAAKAAMJrAqz+wCcAAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgUJCwAAAA==.Velle:BAAALgAFFAIJAwABLgAFFAMJCgAWAMoFAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAACLgAFFH8MAAIKAAUJGBkpLABKAQAKAAUJGBkpLABKAQAuAAQKfyIAAx4ACAmaHiQKAB0CAB4ABwmoGyQKAB0CAAoABglAIF5HAA0CAAAA.Vorth:BAABLgAECn82AAMbAAkJ0xtmBAB3AgAbAAkJqRpmBAB3AgAZAAcJiRRGuQD+AAAAAA==.Vorükh:BAABLgAECn8XAAMkAAcJCApBDQBKAQAkAAYJaAtBDQBKAQAhAAYJsAPDPwCzAAABLgAECgkJHAASADIRAA==.',
Vy='Vyrlana:BAACLgAFFH8HAAImAAMJgASrIQCEAAAmAAMJgASrIQCEAAAuAAQKfxwAAyYACQncEqUOANkBACYACQncEqUOANkBAAEABgnRAuZIALQAAAAA.',
Wa='Waldir:BAABLgAECn9AAAMOAAkJsyR1AQCjAwAOAAkJsyR1AQCjAwAKAAIJuB6t9gC1AAAAAA==.Waldstein:BAABLgAECn8xAAIZAAYJfxmAcgB3AQAZAAYJfxmAcgB3AQAAAA==.Wanted:BAABLgAECn8oAAQKAAcJuw+HhwBrAQAKAAcJYw+HhwBrAQAOAAUJnBK0RwAUAQAeAAYJSwrgLACrAAAAAA==.Watz:BAABLgAECn81AAIWAAkJqxfLKQAsAgAWAAkJqxfLKQAsAgAAAA==.',
We='Wensa:BAAALgAECgYJCwAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xenophage:BAAALgADCgMJAwAAAA==.Xessala:BAAALgAECgUJBgAAAA==.',
Xh='Xheero:BAACLgAFFH8NAAIWAAMJuBIKVgDmAAAWAAMJuBIKVgDmAAAuAAQKfzsAAhYACQmcHhYSALYCABYACQmcHhYSALYCAAAA.Xheerom:BAAALgAECgcJEgAAAA==.',
Ye='Yeast:BAAALgAECgYJCAAAAA==.',
Yu='Yulica:BAABLgAECn8bAAIEAAUJIw8J1ADmAAAEAAUJIw8J1ADmAAAAAA==.',
Za='Zaffy:BAABLgAECn8wAAIdAAkJWxLnBwDDAQAdAAkJWxLnBwDDAQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgAECgMJBgAAAA==.Zaleron:BAAALgAECgcJCAAAAA==.Zanazath:BAABLgAECn8dAAMnAAcJ0Ro3EADZAQAnAAYJRhw3EADZAQABAAYJvhPaQgATAQAAAA==.Zano:BAAALgAECgUJBgAAAA==.Zaruba:BAABLgAECn8yAAMUAAkJehBlJQCvAQAUAAkJehBlJQCvAQAMAAIJ5wCcmgA4AAABLgAECgkJQQACAE8RAA==.Zatheon:BAABLgAECn8lAAIKAAgJXhnRTwDOAQAKAAgJXhnRTwDOAQAAAA==.Zatkyng:BAACLgAFFH8GAAIcAAMJoAqbJAC4AAAcAAMJoAqbJAC4AAAuAAQKfxwAAhwACAnmDzU7AAYBABwACAnmDzU7AAYBAAAA.',
Ze='Zekos:BAAALgAECgcJCgAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8rAAILAAkJ2Bz/CACOAgALAAkJ2Bz/CACOAgAAAA==.Zimdalar:BAABLgAECn8fAAMiAAYJwxzlIQCRAQAiAAYJwxzlIQCRAQAcAAEJ2QzzlAAxAAAAAA==.',
Zo='Zolhs:BAAALgAECgEJAgAAAA==.Zolls:BAAALgAECgMJBgAAAA==.',
Zu='Zulre:BAABLgAECn9RAAIZAAkJ9RllJwBcAgAZAAkJ9RllJwBcAgAAAA==.',
['Ôv']='Ôverkill:BAAALgAECgIJAwABLgAECggJGgAmALEMAA==.',
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
