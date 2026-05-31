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
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Ackrenoth:BAABLgAECn8fAAIBAAkJEhF5IgCsAQABAAkJEhF5IgCsAQAAAA==.',
Ad='Adynn:BAABLgAECn83AAMCAAkJQyWcAQBeAwACAAkJQyWcAQBeAwADAAIJMh1cmgBqAAAAAA==.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAAALgAECgcJDwAAAA==.',
Ag='Agrathayn:BAAALgAECgYJCgAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJNQAEAEsaAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAABLgAECn81AAMFAAkJBiZyAQBgAwAFAAkJBiZyAQBgAwAGAAEJ6RSGZAA5AAAAAA==.Allyeska:BAAALgAECgIJAgAAAA==.Alnharaelune:BAAALgADCgYJEAAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAABLgAECn8fAAIHAAYJZRFeeAAUAQAHAAYJZRFeeAAUAQAAAA==.',
An='Anali:BAABLgAECn8eAAIIAAkJZyA1BwDoAgAIAAkJZyA1BwDoAgAAAA==.Anani:BAABLgAECn8fAAIJAAkJOApLKABtAQAJAAkJOApLKABtAQAAAA==.Andavin:BAABLgAECn8tAAIKAAYJ2ASl6wCxAAAKAAYJ2ASl6wCxAAAAAA==.Angreifer:BAACLgAFFH8NAAILAAUJjhlFDABFAQALAAUJjhlFDABFAQAuAAQKfy8ABAsACQmvHAoKAD0CAAsACAnBHgoKAD0CAAUACQn1DmEyAOIBAAYAAgnfDv5qADAAAAAA.Anori:BAABLgAECn8mAAICAAgJNhhnGADyAQACAAgJNhhnGADyAQAAAA==.',
Ao='Aonar:BAABLgAECn8UAAIMAAUJNBWMWAA1AQAMAAUJNBWMWAA1AQAAAA==.',
Ar='Arc:BAABLgAECn8tAAINAAgJcSGgEwCkAgANAAgJcSGgEwCkAgAAAA==.Archenteron:BAAALgAECgQJCAAAAA==.Arctat:BAAALgAECgMJAwAAAA==.Ardorcinder:BAAALgAECgQJCAAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJCwAAAA==.Artea:BAAALgAECgYJBgAAAA==.',
As='Asbjorne:BAABLgAECn8eAAIOAAgJTxUYIwDXAQAOAAgJTxUYIwDXAQAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
Au='Audi:BAAALgADCgQJCQAAAA==.Augamand:BAAALgAECgYJCAAAAA==.Autumnmoon:BAABLgAECn8lAAIPAAgJVA63BAB4AQAPAAgJVA63BAB4AQAAAA==.',
Av='Avelos:BAACLgAFFH8MAAMIAAUJkATmEwABAQAIAAUJkATmEwABAQAJAAIJWANrLABuAAAuAAQKfy0ABAgACQm4GSMYAPYBAAgACQm4GSMYAPYBABAABAmHBspGAIYAAAkAAgmuDO9pAE0AAAAA.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAABLgAECn8tAAURAAkJlBxNBgB+AgARAAkJ8RtNBgB+AgACAAYJZAoQTgDxAAASAAEJ3BxUOABVAAADAAIJIwN8yQA3AAAAAA==.Ayzmist:BAAALgAECgYJCQAAAA==.Ayzmyth:BAABLgAECn8lAAITAAcJbw9MPABMAQATAAcJbw9MPABMAQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAIMAAcJ7yAVDwCgAgAMAAcJ7yAVDwCgAgAAAA==.Bashra:BAAALgAECgYJEQAAAA==.',
Be='Beasic:BAABLgAECn8/AAMUAAkJEQ3hTADlAAAUAAcJxwnhTADlAAAMAAYJyAHnngBnAAAAAA==.Beastmode:BAAALgAECgcJBwAAAA==.Beletili:BAABLgAECn8zAAIIAAgJbxjDEgAwAgAIAAgJbxjDEgAwAgAAAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn8uAAMVAAkJQxKHEwD8AAAHAAkJJBEtUwCrAQAVAAYJWhKHEwD8AAAAAA==.Birdman:BAAALgAECgYJEwABLgAECgkJLgAVAEMSAA==.Bismuth:BAAALgAECgUJCAAAAA==.',
Bj='Bjornin:BAAALgAECgEJAQAAAA==.',
Bl='Blackraven:BAABLgAECn8lAAMWAAgJpx3jLQAOAgAWAAYJKB7jLQAOAgAXAAcJgBjRGwCwAQAAAA==.Blatendrg:BAABLgAECn8vAAIBAAkJ9BB7IwClAQABAAkJ9BB7IwClAQAAAA==.Blindcloud:BAABLgAECn8XAAIYAAgJAgZALQD0AAAYAAgJAgZALQD0AAAAAA==.',
Bo='Boot:BAABLgAECn8WAAIOAAYJYBkgKAC0AQAOAAYJYBkgKAC0AQAAAA==.Bophedes:BAABLgAECn8WAAMZAAcJoxmkUQC7AQAZAAcJoxmkUQC7AQAaAAEJbw71VAAuAAAAAA==.Borodemonin:BAEBLgAECn8ZAAIHAAYJASSjLQD7AQAHAAYJASSjLQD7AQABLgAFFAQJEQAJADIlAA==.Bosstun:BAAALgADCgMJAwAAAA==.Bozrohin:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn9AAAIIAAkJkRUIFQAWAgAIAAkJkRUIFQAWAgAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Brieanna:BAAALgADCgQJBwAAAA==.Bromith:BAAALgAECgEJAQAAAA==.Brugen:BAAALgAECgYJBgAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgYJDgAAAA==.Cariñosa:BAAALgAECgEJAQAAAA==.Carøline:BAAALgAECgEJAQAAAA==.Caska:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgUJCwAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8sAAMZAAgJ6h1eKwA+AgAZAAgJ6h1eKwA+AgAbAAEJ3wtJGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgYJEQAAAA==.Charles:BAABLgAECn8tAAIcAAkJlSRgAwAeAwAcAAkJlSRgAwAeAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiarus:BAAALgADCgkJGAABLgAFFAUJDQALAI4ZAA==.Chiot:BAABLgAECn88AAILAAkJxB0JBgCcAgALAAkJxB0JBgCcAgAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8lAAMFAAkJAhnoGQAKAgAFAAkJ6hfoGQAKAgALAAUJbhmuIQAKAQAAAA==.Chuga:BAABLgAECn8iAAMNAAgJQg7BXwB2AQANAAgJTg3BXwB2AQAdAAQJHQ1LLgBSAAAAAA==.',
Ci='Cimerian:BAABLgAECn8iAAMeAAgJdAzbHwAJAQAeAAcJoA3bHwAJAQAKAAYJdAUe5QC5AAAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECgcJHwAMAHAQAA==.',
Co='Cobalticus:BAAALgAECgYJDgAAAA==.Corange:BAAALgAECgEJAQAAAA==.Corlock:BAAALgAECgQJBAAAAA==.Cormech:BAAALgAECgcJEwAAAA==.Cornite:BAABLgAECn8YAAIZAAgJDg31cQBsAQAZAAgJDg31cQBsAQAAAA==.',
Cr='Crizzo:BAABLgAECn84AAIWAAkJ6B9SDADdAgAWAAkJ6B9SDADdAgAAAA==.',
Cy='Cyndrial:BAAALgADCgQJCwAAAA==.',
Da='Daddyslilgrl:BAABLgAECn8bAAINAAYJYwIL3gCJAAANAAYJYwIL3gCJAAAAAA==.Dakra:BAEBLgAECn8yAAMGAAkJUR02BQChAgAGAAkJUR02BQChAgALAAEJOwxYTAAvAAAAAA==.Dalamar:BAAALgAFFAMJCQAAAQ==.Dalandis:BAAALgAECgYJBgAAAA==.Dalyeth:BAABLgAECn8iAAIVAAYJRCbZBABlAgAVAAYJRCbZBABlAgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAACLgAFFH8JAAIWAAMJzw09GQCiAAAWAAMJzw09GQCiAAAuAAQKfxQAAhYACAmcHrALAOUCABYACAmcHrALAOUCAAAA.Daunt:BAAALgAECggJCAABLgAECgkJOgACAAYQAA==.',
De='Decypher:BAABLgAECn8pAAISAAkJ+BZOCAApAgASAAkJ+BZOCAApAgAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Deliverance:BAAALgAFFAQJCwABLgAFFAMJCQAfAAAAAQ==.Demonablaze:BAAALgAECgIJAwAAAA==.Dentik:BAABLgAECn8vAAMDAAkJZA96OACiAQADAAkJZA96OACiAQARAAIJ4gKGZgAnAAAAAA==.Denuma:BAAALgAECgYJBgAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgQJCQABLgAECgkJKQASAPgWAA==.Dheriana:BAAALgAECgQJBAABLgAECgkJKQASAPgWAA==.',
Di='Diamair:BAABLgAECn88AAMgAAkJTRmoAwDEAQAEAAkJlBPNRAD2AQAgAAgJGBioAwDEAQAAAA==.Diamones:BAAALgAECgMJAwAAAA==.Dixiee:BAAALgAECgYJDwAAAA==.',
Dn='Dnegelpal:BAABLgAECn8mAAIKAAkJUxC+XQCdAQAKAAkJUxC+XQCdAQAAAA==.',
Do='Docbison:BAAALgADCgMJBQABLgAECgYJDAAfAAAAAA==.Dodgecharger:BAABLgAECn8VAAIMAAYJlgTpfQDEAAAMAAYJlgTpfQDEAAAAAA==.Dornix:BAABLgAECn8pAAINAAgJZyDwJwAuAgANAAgJZyDwJwAuAgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgcJDAAAAA==.Dragonfood:BAABLgAECn8YAAIWAAYJJggIkQACAQAWAAYJJggIkQACAQAAAA==.Drakilu:BAABLgAECn9AAAIWAAkJQB4cEAC7AgAWAAkJQB4cEAC7AgAAAA==.Drasic:BAACLgAFFH8MAAIDAAMJYBX5MwDOAAADAAMJYBX5MwDOAAAuAAQKfzwAAgMACQmyIaMEAGQDAAMACQmyIaMEAGQDAAAA.Dreddscott:BAAALgAECgUJBQABLgAECgkJOAAhADAfAA==.Drophin:BAAALgADCgkJGwAAAA==.Drunken:BAABLgAECn8xAAIiAAgJ3R8rCwBwAgAiAAgJ3R8rCwBwAgAAAA==.Druphin:BAAALgADCgYJEgAAAA==.',
Du='Durward:BAABLgAECn9AAAQZAAkJzyIGCQAZAwAZAAkJzyIGCQAZAwAaAAQJ/w5FNACvAAAbAAIJNxfpIgB+AAAAAA==.Duvo:BAABLgAECn8XAAIWAAYJtx1fXwBvAQAWAAYJtx1fXwBvAQAAAA==.',
Dw='Dwarfo:BAAALgAECgYJDgAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.Dwarvey:BAAALgADCgMJAwAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAABLgAECn8cAAMRAAcJ2gavOACbAAARAAcJ2gavOACbAAACAAQJpQB3fwAyAAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIbAAgJlR6GAgCPAgAbAAgJlR6GAgCPAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAABLgAECn8bAAINAAkJIQLPvQDBAAANAAkJIQLPvQDBAAAAAA==.Elemental:BAACLgAFFH8KAAMUAAQJcgqnIwDyAAAUAAQJcgqnIwDyAAAMAAEJKASMcQA2AAAuAAQKfywAAxQACQmxGagOALoCABQACQmxGagOALoCAAwAAwm4CRmOAF4AAAEuAAUUBgkQAAIACQkA.Eleussen:BAAALgAECgMJAwAAAA==.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgAECgMJBAAAAA==.Elloseth:BAABLgAECn8mAAIJAAYJfxyZIgCTAQAJAAYJfxyZIgCTAQAAAA==.Elmorin:BAAALgAECgcJDwAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAABLgAECn8VAAIWAAYJrQwXkgAAAQAWAAYJrQwXkgAAAQAAAA==.',
Ep='Epica:BAABLgAECn8oAAIEAAcJ+xQogQBaAQAEAAcJ+xQogQBaAQAAAA==.',
Er='Eragonhawk:BAABLgAECn8pAAIKAAgJfxtHKQBEAgAKAAgJfxtHKQBEAgAAAA==.Erelynn:BAAALgAECgQJBAABLgAECgkJJQAIAMkRAA==.Eroldan:BAABLgAECn8cAAMMAAgJmR8qEQCuAgAMAAgJmR8qEQCuAgAUAAEJKRJklQAuAAAAAA==.Erovianoria:BAACLgAFFH8KAAIWAAMJygVAWQDEAAAWAAMJygVAWQDEAAAuAAQKfykAAhYACQm/Fv8WAIACABYACQm/Fv8WAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.Eräthis:BAAALgAECgMJAwAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAABLgAECn8qAAIYAAgJdyJ/BwCdAgAYAAgJdyJ/BwCdAgABLgAFFAcJJwANADYXAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8sAAIMAAkJShftGgBaAgAMAAkJShftGgBaAgAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Fa='Fatalfury:BAABLgAECn8iAAMKAAkJShlrTwDBAQAKAAgJ7xdrTwDBAQAOAAQJgwfBWwCrAAAAAA==.Fauxstorm:BAABLgAECn8WAAMjAAUJUhqIFwAqAQAjAAUJUhqIFwAqAQAUAAIJ/BF9kAA1AAAAAA==.',
Fi='Finngan:BAABLgAECn8uAAIdAAkJoQ7yCQCIAQAdAAkJoQ7yCQCIAQAAAA==.Fireina:BAAALgAECgYJEQAAAA==.',
Fo='Forestkin:BAAALgAECgYJEQABLgAECgYJIgAVAEQmAA==.Fossilis:BAABLgAECn8YAAMkAAcJHgWtEQD3AAAkAAcJAQWtEQD3AAAhAAUJ2wIUTwCzAAAAAA==.',
Fr='Frenzyz:BAAALgADCgIJAgAAAA==.Frozenthunda:BAAALgAECgQJCgAAAA==.',
Fu='Furna:BAABLgAECn8sAAIQAAYJ4hTbJwBuAQAQAAYJ4hTbJwBuAQAAAA==.',
Fy='Fyahka:BAAALgADCgQJBAAAAA==.Fyon:BAAALgAECgYJCQAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAACLgAFFH8KAAIFAAQJpArvIgAOAQAFAAQJpArvIgAOAQAuAAQKfzYAAgUACQn4F38UADkCAAUACQn4F38UADkCAAAA.Galileia:BAAALgADCgMJBAAAAA==.',
Gh='Ghorienge:BAAALgAECgYJDwAAAA==.Ghostcat:BAAALgAECgIJAgAAAA==.',
Gi='Gilox:BAABLgAECn8bAAIkAAgJGBCaCQCQAQAkAAgJGBCaCQCQAQAAAA==.',
Gn='Gndmexia:BAAALgAECgYJEwAAAA==.Gneiss:BAAALgAECgYJEQAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8iAAIDAAkJiCCcBgBBAwADAAkJiCCcBgBBAwAAAA==.',
Gr='Graymon:BAABLgAECn8WAAIFAAUJrRzWPAA8AQAFAAUJrRzWPAA8AQAAAA==.Greebo:BAABLgAECn8WAAIRAAUJ0QPMUQBNAAARAAUJ0QPMUQBNAAAAAA==.Griknor:BAABLgAECn8fAAMGAAYJRgU/IgDaAAAGAAYJRgU/IgDaAAAFAAQJBgMhdQBzAAAAAA==.Grimniel:BAAALgAECgIJAwAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAAALgAECggJEwAAAA==.',
Gw='Gwenyver:BAABLgAECn8cAAIKAAgJqgLl5wC1AAAKAAgJqgLl5wC1AAAAAA==.',
Ha='Hadoukendk:BAAALgAECggJEwAAAA==.Hafaken:BAAALgAECgEJAQAAAA==.Hallien:BAAALgADCgEJAQAAAA==.Hamord:BAABLgAECn8eAAIeAAgJ5Q7THAAWAQAeAAgJ5Q7THAAWAQAAAA==.Hansdelbruk:BAAALgADCgEJAQAAAA==.Hardlight:BAAALgADCggJCQAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgAECgQJBAAAAA==.Harliqynn:BAABLgAECn8cAAIWAAkJ4BrtIABAAgAWAAkJ4BrtIABAAgAAAA==.Harlock:BAABLgAECn8jAAIhAAkJXxwcDgAuAgAhAAkJXxwcDgAuAgAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.Hazelnuts:BAAALgAECgIJAQAAAA==.',
He='Heartkiller:BAAALgAECgQJBAABLgAECgkJKAAEAPsUAA==.Helleye:BAAALgAECgcJEQAAAA==.',
Hi='Hiten:BAABLgAECn9AAAQhAAkJKRuWCQB1AgAhAAkJIRuWCQB1AgAkAAUJRBWIDQBEAQAlAAEJjwhGIQAsAAAAAA==.',
Ho='Hopedaimond:BAABLgAECn8mAAIUAAkJ3A07LQB1AQAUAAkJ3A07LQB1AQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8/AAMWAAkJAA4iRAC9AQAWAAkJAA4iRAC9AQAXAAYJowMAOwDPAAAAAA==.',
Hy='Hypro:BAABLgAECn8xAAIMAAkJeyU7AADXAwAMAAkJeyU7AADXAwAAAA==.',
['Há']='Háides:BAAALgADCgIJAgAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIeAAcJByOXBAC6AgAeAAcJByOXBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJEwAAAA==.',
Ie='Iepa:BAAALgAECggJCQAAAA==.',
Il='Ilthad:BAABLgAECn8eAAIYAAcJQhSgHAB0AQAYAAcJQhSgHAB0AQAAAA==.',
Im='Imperio:BAAALgADCgYJBgAAAA==.Imshalar:BAAALgAECggJEAAAAA==.',
In='Inconcvabull:BAABLgAECn8WAAINAAgJEAsLeAA+AQANAAgJEAsLeAA+AQAAAA==.Inferious:BAAALgAECgUJDwABLgAECgcJFgAZAKMZAA==.Infurryating:BAAALgAECgcJBwAAAA==.Inistus:BAAALgADCgcJCwAAAA==.',
Ir='Iralis:BAAALgAECgYJDQAAAA==.',
Is='Ischadè:BAAALgAECgEJAQAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgkJEAAAAA==.Itsirk:BAABLgAECn8rAAIOAAgJdxrqGQAgAgAOAAgJdxrqGQAgAgAAAA==.',
Iz='Izyebelle:BAABLgAECn8qAAMJAAkJ5gFrVACWAAAJAAkJ5gFrVACWAAAIAAEJUAFodAAUAAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAABLgAECn8vAAIeAAgJfiTsAgDdAgAeAAgJfiTsAgDdAgAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jiayou:BAAALgADCgEJAQAAAA==.Jimmydin:BAACLgAFFH8LAAIKAAQJmhQcMwAtAQAKAAQJmhQcMwAtAQAuAAQKfzwAAwoACQnJGaEhAGkCAAoACQnJGaEhAGkCAA4ACQklGbQeACICAAAA.Jix:BAABLgAECn8YAAMdAAgJkhi9DgDeAQAdAAYJtxy9DgDeAQANAAQJSAxGrQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8xAAQHAAkJhhIbQgCqAQAHAAkJ5REbQgCqAQAVAAMJyxWlHgCSAAAYAAEJYw4QbwA2AAAAAA==.',
Ju='Juego:BAAALgADCgEJAQAAAA==.Julkan:BAAALgAECgQJBgAAAA==.Junhoong:BAABLgAECn84AAIKAAkJDxPkRQDdAQAKAAkJDxPkRQDdAQAAAA==.',
Jy='Jynnysa:BAAALgAECgYJDwABLgAECgYJKAAeABcjAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAABLgAECn8WAAIGAAcJiBRHGwBoAQAGAAcJiBRHGwBoAQAAAA==.Kairoll:BAABLgAECn8mAAIIAAkJuBW8FAAZAgAIAAkJuBW8FAAZAgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Kannah:BAAALgAECgYJCwABLgAECggJFgAOAH8ZAA==.Karaa:BAABLgAECn8oAAITAAcJwwZNXwDAAAATAAcJwwZNXwDAAAAAAA==.Kariena:BAABLgAECn8hAAIWAAgJnh5dIgBEAgAWAAgJnh5dIgBEAgAAAA==.Katesluage:BAABLgAECn81AAIEAAkJSxrkMQA6AgAEAAkJSxrkMQA6AgAAAA==.Kawrrl:BAAALgAECgEJAQAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJNQAEAEsaAA==.',
Ke='Keeya:BAABLgAECn8wAAIZAAcJSBIPhABGAQAZAAcJSBIPhABGAQAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kelkan:BAAALgAECgEJAQAAAA==.Kendari:BAABLgAECn8XAAIaAAYJ/QSmOwCKAAAaAAYJ/QSmOwCKAAAAAA==.Kernasas:BAABLgAECn8sAAIdAAcJwxUrCgCDAQAdAAcJwxUrCgCDAQAAAA==.Keslynn:BAAALgAECgIJAwABLgAECggJIQAWAJ4eAA==.Ketrani:BAAALgAECgEJAgABLgAECggJIQAWAJ4eAA==.',
Kh='Khiari:BAAALgAECgQJBAABLgAECggJIAAKAE8QAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAAALgAECgYJEQAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJKQANAGcgAA==.Kirtiao:BAAALgAECgEJAgABLgAECggJIQAWAJ4eAA==.Kitalidie:BAAALgAECgIJAgABLgAECggJIQAWAJ4eAA==.Kizaraan:BAABLgAECn8dAAMmAAgJewT+IADVAAAmAAcJxgP+IADVAAAnAAMJzwKGHQBRAAAAAA==.',
Kl='Kleyntamar:BAAALgAECgUJDgAAAA==.',
Kn='Knyghtly:BAAALgAECgkJAwAAAA==.',
Ko='Konstantien:BAAALgAECgYJBgAAAA==.Koshamunzo:BAAALgADCgYJBgAAAA==.',
Kr='Kritt:BAAALgAECgYJBgAAAA==.Kritter:BAAALgAECgYJDwAAAA==.Krohm:BAABLgAECn8uAAMKAAkJcyM9BgAtAwAKAAkJcyM9BgAtAwAeAAEJ8hitQQBFAAAAAA==.Krostana:BAAALgADCgEJAQAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgAECgYJDgAAAA==.Kungfuey:BAAALgADCgcJBwAAAA==.Kupau:BAAALgAECgQJBAAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Lanss:BAABLgAECn9KAAILAAkJ9yQ3AQBIAwALAAkJ9yQ3AQBIAwAAAA==.Larachel:BAAALgAECgcJEgAAAA==.Laur:BAABLgAECn8uAAIJAAkJaxP5GgDRAQAJAAkJaxP5GgDRAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8jAAIKAAkJUBxbJgBRAgAKAAkJUBxbJgBRAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAABLgAECn8WAAIeAAUJERxmGAA/AQAeAAUJERxmGAA/AQAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAwAAAA==.Lilipo:BAABLgAECn8tAAIcAAgJGgl8MgAkAQAcAAgJGgl8MgAkAQAAAA==.Liltara:BAABLgAECn8kAAIEAAcJMQKe7QCkAAAEAAcJMQKe7QCkAAAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llanz:BAAALgADCgkJKgAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAACLgAFFH8IAAINAAMJQwcIcwDEAAANAAMJQwcIcwDEAAAuAAQKfy0AAg0ACAm+FGdPAKEBAA0ACAm+FGdPAKEBAAAA.Lokdan:BAAALgAECgYJCQAAAA==.Loppy:BAAALgAECgIJAgAAAA==.Loula:BAABLgAECn8nAAIEAAgJSAOxwwDlAAAEAAgJSAOxwwDlAAAAAA==.Lowryder:BAACLgAFFH8FAAIhAAMJCgmGJQDOAAAhAAMJCgmGJQDOAAAuAAQKfyAAAyEACQniFB0RAAoCACEACQniFB0RAAoCACQAAQmbBmIgADEAAAAA.Loxes:BAAALgAECgcJDQABLgAECgYJCwAfAAAAAA==.Loxy:BAAALgAECgUJDAAAAA==.',
Lu='Lukam:BAAALgAECgUJEAAAAA==.Lunaellana:BAAALgAECgQJBAAAAA==.Lus:BAABLgAECn8UAAMNAAYJsRfzegBmAQANAAYJsRfzegBmAQAdAAIJuggxUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAABLgAECn8aAAUDAAgJgB2jEgClAgADAAgJgB2jEgClAgARAAQJPAwdQgBzAAASAAIJUwQ2QQA7AAACAAIJTwExmgAOAAABLgAFFAMJCAADAEcHAA==.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
['Lü']='Lüvpüp:BAAALgAECggJEQABLgAECgkJIgAZALIbAA==.',
Ma='Magicfang:BAAALgAECgYJCwAAAA==.Maiku:BAABLgAECn89AAINAAkJcRU0KwAfAgANAAkJcRU0KwAfAgAAAA==.Makado:BAABLgAECn8gAAQdAAgJ2gjSHACtAAANAAUJ4AU1uADLAAAdAAcJQAfSHACtAAAoAAUJvQf7HQCqAAAAAA==.Makaris:BAAALgADCgQJBQAAAA==.Maknanimus:BAAALgADCgQJBAAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAABLgAECn8gAAINAAYJpBqjVwCKAQANAAYJpBqjVwCKAQAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Matua:BAAALgAECgEJAQAAAA==.Maycee:BAAALgAECgYJDAAAAA==.',
Mc='Mcnaugh:BAABLgAECn8eAAMaAAgJlA7eIAAyAQAaAAgJbA3eIAAyAQAZAAQJKRQt0QDOAAAAAA==.Mcsaltface:BAABLgAECn8aAAIKAAgJKhkZQgDoAQAKAAgJKhkZQgDoAQAAAA==.',
Me='Meddic:BAAALgAECgIJAgAAAA==.Menaras:BAACLgAFFH8KAAMMAAMJfw6MSQCsAAAMAAMJfw6MSQCsAAAUAAIJZgL3PgBrAAAuAAQKfywAAxQACQkmHTsSAJECABQACQkmHTsSAJECAAwACAmOF4REAH8BAAAA.Menarot:BAABLgAFFH8GAAIZAAMJtQcmlADFAAAZAAMJtQcmlADFAAABLgAFFAMJCgAMAH8OAA==.Mendais:BAAALgADCgYJCgAAAA==.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAFFAUJDQALAI4ZAA==.',
Mi='Mikeydluffy:BAABLgAECn8aAAIcAAkJVBUDEwASAgAcAAkJVBUDEwASAgAAAA==.Mirosmundo:BAACLgAFFH8QAAIiAAUJdxiSGQA5AQAiAAUJdxiSGQA5AQAuAAQKfy0AAiIACQknH9oIAPkCACIACQknH9oIAPkCAAAA.Mistfit:BAABLgAECn8WAAITAAcJSBPaNABxAQATAAcJSBPaNABxAQAAAA==.Miyagi:BAAALgAECgYJEAAAAA==.Miyu:BAABLgAECn8vAAQIAAkJlBIqIACsAQAIAAkJlBIqIACsAQAJAAUJdxl+MAA6AQAQAAEJ1A2WawAxAAAAAA==.',
Mo='Mod:BAABLgAECn8rAAMUAAkJlSRVCgClAgAUAAgJSSRVCgClAgAMAAYJihOrUwA3AQAAAA==.Modaka:BAAALgAECgMJBQAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moffizi:BAAALgADCgcJBwAAAA==.Moggatorash:BAAALgAECgcJEgAAAA==.Mogtham:BAABLgAECn8/AAIRAAkJ/RfSCQAqAgARAAkJ/RfSCQAqAgAAAA==.Moirenna:BAAALgAECgEJAQABLgAFFAcJJwANADYXAA==.Moisticklez:BAAALgAECgUJCwAAAA==.Monkeyspaul:BAABLgAECn8cAAIcAAgJQhvDFABHAgAcAAgJQhvDFABHAgABLgAECgkJKwALANgcAA==.Moonfall:BAABLgAECn8YAAIHAAYJDg/7ggD9AAAHAAYJDg/7ggD9AAAAAA==.Moonpig:BAAALgAECgMJAwAAAA==.Moosader:BAABLgAECn8vAAMKAAkJDBiPSgDPAQAKAAgJQBaPSgDPAQAOAAcJkAiVVwAdAQAAAA==.Morellea:BAACLgAFFH8OAAIHAAQJKA33QAAKAQAHAAQJKA33QAAKAQAuAAQKfxYAAgcACQkSGVk2AB0CAAcACQkSGVk2AB0CAAAA.Morighann:BAABLgAECn8qAAIWAAkJvSNXDwDCAgAWAAkJvSNXDwDCAgAAAA==.Morkith:BAAALgAFFAEJAQAAAA==.Morphalot:BAAALgAFFAEJAQAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mostank:BAAALgADCgMJAwAAAA==.Mousse:BAAALgADCgMJAwABLgAECgkJQQATAO4kAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgAECgMJBQABLgAECgkJOgACAAYQAA==.',
My='Mylea:BAAALgAECgIJAgABLgAECgYJGAAHAA4PAA==.Mynkx:BAABLgAECn8gAAIKAAgJTxDAcwBsAQAKAAgJTxDAcwBsAQAAAA==.Mythyras:BAABLgAECn8oAAIeAAYJFyPuCwDwAQAeAAYJFyPuCwDwAQABLgAECgYJKAAeABcjAA==.',
Na='Naeomy:BAAALgADCgkJCQAAAA==.Nahaman:BAAALgAECgYJDAAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8fAAIOAAYJJhTxNABnAQAOAAYJJhTxNABnAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8QAAMCAAYJCQlsIgDsAAACAAQJ3gpsIgDsAAADAAIJaQKITwBxAAAuAAQKfxwABQMACAl0GxElACUCAAMACAl0GxElACUCABIABQl/F9gcAPwAABEAAglaFQ9BAHcAAAIAAgkXFzBuAFMAAAAA.Netherite:BAABLgAECn8dAAIgAAgJMBGFBACSAQAgAAgJMBGFBACSAQAAAA==.Nethim:BAAALgAECgEJAQABLgAECggJHQAgADARAA==.Netre:BAAALgAECgcJEAAAAA==.Nezana:BAABLgAECn8uAAQmAAkJhhjNCgAeAgAmAAgJ5xbNCgAeAgABAAgJdxHeJwCJAQAnAAMJNggpNwBeAAAAAA==.',
Ni='Nianah:BAAALgADCggJEAAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8rAAIRAAkJyB1iBQCYAgARAAkJyB1iBQCYAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Nobunada:BAAALgAECgIJAgABLgAECgkJCQAfAAAAAA==.Nobunaga:BAAALgAECgIJAwABLgAECgkJCQAfAAAAAA==.Noranna:BAABLgAECn8WAAIWAAUJYA+MnADrAAAWAAUJYA+MnADrAAAAAA==.',
Ny='Nynsyn:BAAALgAECgIJAgABLgAECgYJKAAeABcjAA==.',
['Nø']='Nøva:BAAALgAECgIJAwABLgAFFAQJBgAZAAwQAA==.',
Oh='Ohthesemyboo:BAAALgAECgkJEwAAAA==.Ohwellz:BAABLgAECn8dAAMMAAcJ1g3fZgAHAQAMAAUJiRDfZgAHAQAUAAcJXBFFSAD3AAABLgAECggJHAAKAD8aAA==.',
On='On:BAAALgAECgEJAQAAAA==.',
Op='Ophin:BAABLgAECn8fAAIZAAcJfR35OQAEAgAZAAcJfR35OQAEAgAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Or:BAAALgAECgYJEgAAAA==.Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.Ornaxxi:BAAALgAECgQJBAAAAA==.',
Ov='Overheal:BAABLgAECn8aAAImAAgJsQxoFABxAQAmAAgJsQxoFABxAQAAAA==.',
Oy='Oyuki:BAAALgAECgkJCQAAAA==.',
Pa='Padhu:BAABLgAECn8aAAIiAAgJDgcIOwD+AAAiAAgJDgcIOwD+AAAAAA==.Palox:BAAALgAECgYJBgAAAA==.Panamared:BAABLgAECn84AAIhAAkJMB+SBgCuAgAhAAkJMB+SBgCuAgAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn9BAAMIAAkJPxS6FwD7AQAIAAkJPxS6FwD7AQAQAAcJmwwFKgBfAQAAAA==.Pezza:BAABLgAECn8bAAIMAAgJaxKoOQCsAQAMAAgJaxKoOQCsAQAAAA==.',
Ph='Phantomlord:BAABLgAECn8UAAIZAAkJ8hKsNwANAgAZAAkJ8hKsNwANAgABLgAECgkJKAAEAPsUAA==.Phaze:BAABLgAECn8aAAIXAAkJ0Bc2EgALAgAXAAkJ0Bc2EgALAgAAAA==.Phia:BAABLgAECn8eAAMWAAkJ/x4ZEgCnAgAWAAkJ/x4ZEgCnAgAXAAEJEhWBLABCAAAAAA==.Pholcus:BAAALgAECgUJEAAAAA==.',
Pr='Prothagon:BAABLgAECn8rAAMmAAkJsxdaBwBxAgAmAAkJsxdaBwBxAgABAAIJQBbGawBsAAAAAA==.',
Ps='Psylix:BAABLgAECn86AAMYAAkJWR0HBwCoAgAYAAkJWR0HBwCoAgAHAAEJZwvy+wAyAAAAAA==.',
Pu='Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAABLgAECn8WAAIKAAUJJAtK4QC9AAAKAAUJJAtK4QC9AAAAAA==.Raevennlumis:BAABLgAECn8cAAIKAAkJUgZ3lwAqAQAKAAkJUgZ3lwAqAQAAAA==.Rahkhard:BAAALgAFFAEJAQAAAA==.Randrius:BAAALgADCgYJBgAAAA==.Ransha:BAAALgAECgYJEAABLgAECgkJLgAVAEMSAA==.Rascdit:BAAALgAECgcJDgAAAA==.',
Re='Redwood:BAAALgAECgYJEwAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Renwic:BAAALgAECgMJBgAAAA==.Reylani:BAEALgAECgcJBwABLgAECgkJMgAGAFEdAA==.',
Rh='Rheingard:BAAALgAECgEJAQAAAA==.Rhemiroll:BAAALgAECggJDgAAAA==.Rhintalle:BAEALgAECgEJAQABLgAECgUJEwAfAAAAAA==.',
Ri='Rickroll:BAAALgAECgMJBQAAAA==.Riepa:BAAALgADCgEJAQAAAA==.Risotto:BAABLgAECn9BAAMTAAkJ7iR/AQC4AwATAAkJ7iR/AQC4AwAcAAEJkBd6ggA9AAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgAECgUJBgAAAA==.',
Ru='Ruaic:BAAALgAECgEJAQAAAA==.Rumblelight:BAABLgAECn8WAAIKAAgJpwsphQBKAQAKAAgJpwsphQBKAQAAAA==.Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgcJDwAAAA==.Sagehawk:BAAALgAECgYJEwAAAA==.Saitamà:BAAALgADCgMJAwAAAA==.Sali:BAAALgAECgEJAgAAAA==.Salmuna:BAAALgADCgEJAQAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIcAAgJJhRWIACVAQAcAAgJJhRWIACVAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAABLgAECn80AAIEAAkJHx79EwDMAgAEAAkJHx79EwDMAgAAAA==.Sarova:BAAALgAECgYJEQAAAA==.Satori:BAAALgAECgUJEQAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJBAAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.Scone:BAAALgAECgYJBgAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAABLgAECn8vAAIZAAkJqBzxGwCMAgAZAAkJqBzxGwCMAgAAAA==.Sellidor:BAABLgAECn8bAAIWAAkJFyCoDwC/AgAWAAkJFyCoDwC/AgAAAA==.Senamue:BAAALgADCggJCAAAAA==.Seriniyaa:BAAALgAECgYJEwAAAA==.',
Sh='Shaey:BAAALgAECgQJBAAAAA==.Shaureesa:BAAALgAECgQJBAAAAA==.Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8oAAIKAAkJOwPM3ADDAAAKAAkJOwPM3ADDAAAAAA==.Shirito:BAABLgAECn8uAAIZAAkJGyYNBQBKAwAZAAkJGyYNBQBKAwAAAA==.Shiritodh:BAABLgAECn8eAAIHAAgJeCVQFQCFAgAHAAgJeCVQFQCFAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8wAAMeAAkJKiPWAQATAwAeAAkJKiPWAQATAwAKAAYJsBY2egCGAQABLgAFFAMJCAALAJkRAA==.Shugo:BAAALgAECgYJCQAAAA==.Shyle:BAAALgAECgQJCQAAAA==.',
Si='Sienje:BAABLgAECn8tAAIKAAkJXx8NDwDXAgAKAAkJXx8NDwDXAgAAAA==.Simpleson:BAABLgAECn8nAAMNAAgJQBt9LAAaAgANAAgJQBt9LAAaAgAdAAUJxQ7ONADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAABLgAECn8bAAMYAAcJPhQJJQAsAQAYAAYJzBYJJQAsAQAHAAYJ7wrZngDFAAAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAAALgAECgcJEgABLgAECgkJAwAfAAAAAA==.Skribble:BAABLgAECn8WAAMQAAYJcQxRNwAPAQAQAAYJcQxRNwAPAQAJAAYJKwkvRQDUAAAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slackbear:BAABLgAECn8qAAINAAgJ0higLQAWAgANAAgJ0higLQAWAgAAAA==.Slaete:BAAALgAECgcJEgAAAA==.Slycen:BAAALgADCgcJBwAAAA==.',
So='Sokey:BAABLgAECn8UAAIWAAYJCgpFjAANAQAWAAYJCgpFjAANAQAAAA==.Solemn:BAABLgAECn8gAAIJAAgJXRrQEgAfAgAJAAgJXRrQEgAfAgABLgAECgkJGwAWABcgAA==.Soleva:BAAALgADCgkJDwAAAA==.Solrana:BAABLgAECn8VAAMZAAcJKAMH2QDDAAAZAAcJ9gIH2QDDAAAbAAEJOAPyOQAOAAAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgAECgYJCQAAAA==.Sorren:BAAALgAECgEJAQAAAA==.Sorrows:BAABLgAECn8XAAIdAAgJvQpMEQAWAQAdAAgJvQpMEQAWAQAAAA==.Sosukesagara:BAAALgAECgYJCQAAAA==.Sotta:BAAALgAECgMJBQAAAA==.Soulbled:BAABLgAECn8mAAIVAAkJmQ40DQCEAQAVAAkJmQ40DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAABLgAECn8aAAIMAAgJwR5XDQDVAgAMAAgJwR5XDQDVAgAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAABLgAECn8UAAIKAAYJ7gde1ADOAAAKAAYJ7gde1ADOAAAAAA==.Superbautumn:BAABLgAECn8ZAAIKAAkJox+WJABaAgAKAAkJox+WJABaAgAAAA==.',
Sy='Sylo:BAABLgAECn8kAAIZAAgJMBUcVwCsAQAZAAgJMBUcVwCsAQAAAA==.Synalaid:BAAALgAECgQJBQAAAA==.Synnyca:BAAALgAECgMJBAABLgAECgYJKAAeABcjAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAAALgAECgcJEgAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIZAAkJsht+KACYAgAZAAkJsht+KACYAgAAAA==.Tadoshi:BAAALgADCgEJAQAAAA==.Taeonaki:BAAALgAECgMJAwAAAA==.Tagnaras:BAAALgAECgcJEwAAAA==.Tahlang:BAAALgAECgEJBAAAAA==.Tali:BAABLgAECn8dAAMWAAgJiA1bWQB/AQAWAAgJiA1bWQB/AQApAAEJYwbkPQAiAAAAAA==.Taliasluage:BAAALgAECgQJBAABLgAECgkJNQAEAEsaAA==.Tamune:BAABLgAECn8VAAIkAAcJ1hxUBgD0AQAkAAcJ1hxUBgD0AQAAAA==.Tangle:BAABLgAECn8UAAMDAAYJ1RleMgDCAQADAAYJ1RleMgDCAQACAAYJ/wGBYgBxAAABLgAECgkJAwAfAAAAAA==.Tanka:BAABLgAECn83AAMGAAkJ7STpAABhAwAGAAkJ7STpAABhAwALAAIJfRI4OwByAAAAAA==.Tanuki:BAAALgADCgkJMwAAAA==.Tashlaraz:BAEALgAECgUJEwAAAA==.Tasi:BAAALgADCgEJAQAAAA==.Taurannosaur:BAAALgAECgEJAwAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.Tavia:BAAALgADCgMJAwABLgAECgkJKgAfAAAAAQ==.',
Te='Telkas:BAAALgAECgIJAgAAAA==.Temporantus:BAAALgAECgYJEgAAAA==.Tenko:BAABLgAECn8fAAIEAAgJaRKUXQCuAQAEAAgJaRKUXQCuAQAAAA==.Texaspete:BAAALgADCgIJAwAAAA==.',
Th='Thaddeus:BAABLgAECn8kAAIUAAkJURDRJQCiAQAUAAkJURDRJQCiAQAAAA==.Thariane:BAAALgADCgcJDgABLgAECgEJAQAfAAAAAA==.Thaxxas:BAAALgADCgIJAgAAAA==.Therm:BAACLgAFFH8KAAIKAAQJryZkDQC/AQAKAAQJryZkDQC/AQAuAAQKfzwAAgoACQlXJtwBAG8DAAoACQlXJtwBAG8DAAAA.Thoramier:BAABLgAECn8hAAQeAAkJ2xqUCwD1AQAeAAcJ8B2UCwD1AQAKAAYJ4wyIxADkAAAOAAIJGhTjZgB8AAAAAA==.Thorgrymm:BAAALgADCgcJCwAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timadia:BAAALgAECgEJAQAAAA==.Timoonja:BAAALgAECgYJDAAAAA==.',
To='Tonatuih:BAACLgAFFH8GAAMHAAMJbQ1OWgC/AAAHAAMJxglOWgC/AAAYAAEJ4hTSIgBDAAAuAAQKfzcABAcACQkhH84hADcCAAcACAnvG84hADcCABgACQnVGkkXAKoBABUABgmXFqINAHwBAAAA.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAcJGwALAMoiAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAABLgAECn8oAAIoAAkJgBg5BQAZAgAoAAkJgBg5BQAZAgAAAA==.Triipod:BAAALgAECgIJAgAAAA==.Trinkat:BAABLgAECn8WAAIEAAUJUgSR/ACLAAAEAAUJUgSR/ACLAAAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgkJDQAAAA==.Tynk:BAAALgAECgQJBAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tyreitherinn:BAAALgAECgMJAwAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.Unìqùe:BAAALgADCgEJAQAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAAALgAECgYJEwAAAA==.Vaerethra:BAAALgADCgEJAQAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn9DAAINAAkJtQXPcgBJAQANAAkJtQXPcgBJAQAAAA==.Valsedor:BAAALgAECgYJBgAAAA==.Valwar:BAABLgAECn8kAAIFAAkJ8xkkHABsAgAFAAkJ8xkkHABsAgAAAA==.Vareyn:BAABLgAECn8XAAMeAAYJGQncLQCZAAAKAAMJrAqz+wCcAAAeAAYJlAbcLQCZAAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgUJCwAAAA==.Velle:BAAALgAFFAIJAwABLgAFFAMJCgAWAMoFAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAACLgAFFH8HAAIKAAUJGBm0JABTAQAKAAUJGBm0JABTAQAuAAQKfyIAAx4ACAmaHlUJACACAB4ABwmoG1UJACACAAoABglAIF5HAA0CAAAA.Vorth:BAABLgAECn80AAMbAAkJSBqzBABQAgAbAAkJHxmzBABQAgAZAAcJiRQosAD+AAAAAA==.Vorükh:BAABLgAECn8XAAMkAAcJCApBDQBKAQAkAAYJaAtBDQBKAQAhAAYJsANJPAC3AAABLgAECgkJGgASADIRAA==.',
Vy='Vyrlana:BAACLgAFFH8HAAImAAMJgAQfHwCYAAAmAAMJgAQfHwCYAAAuAAQKfxwAAyYACQncEh8OANoBACYACQncEh8OANoBAAEABgnRAuZIALQAAAAA.',
Wa='Waldir:BAABLgAECn8+AAMOAAkJsyQvAQCmAwAOAAkJsyQvAQCmAwAKAAIJuB4v6QCzAAAAAA==.Waldstein:BAABLgAECn8xAAIZAAYJfxmTbAB4AQAZAAYJfxmTbAB4AQAAAA==.Wanted:BAABLgAECn8oAAQKAAcJuw+HhwBrAQAKAAcJYw+HhwBrAQAOAAUJnBLeRAAVAQAeAAYJSwqlKgCsAAAAAA==.Watz:BAABLgAECn8zAAIWAAkJmBTqNgDqAQAWAAkJmBTqNgDqAQAAAA==.',
We='Wensa:BAAALgAECgYJCwAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xenophage:BAAALgADCgMJAwAAAA==.Xessala:BAAALgAECgUJBgAAAA==.',
Xh='Xheero:BAACLgAFFH8KAAIWAAMJuBJqTADpAAAWAAMJuBJqTADpAAAuAAQKfzsAAhYACQmcHuEPAL0CABYACQmcHuEPAL0CAAAA.Xheerom:BAAALgAECgcJEgAAAA==.',
Ye='Yeast:BAAALgAECgMJAwAAAA==.',
Yu='Yulica:BAABLgAECn8WAAIEAAUJKw3E0gDNAAAEAAUJKw3E0gDNAAAAAA==.',
Za='Zaffy:BAABLgAECn8wAAIdAAkJWxI0BwDGAQAdAAkJWxI0BwDGAQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgAECgMJBgAAAA==.Zaleron:BAAALgAECgYJBwAAAA==.Zanazath:BAABLgAECn8dAAMnAAcJ0Ro3EADZAQAnAAYJRhw3EADZAQABAAYJvhN0PQATAQAAAA==.Zano:BAAALgAECgQJBAAAAA==.Zaruba:BAABLgAECn8wAAMUAAgJIhHnKwB9AQAUAAgJIhHnKwB9AQAMAAIJ5wCcmgA4AAABLgAECgkJOgACAAYQAA==.Zatheon:BAABLgAECn8lAAIKAAgJXhl3SgDPAQAKAAgJXhl3SgDPAQAAAA==.Zatkyng:BAABLgAECn8cAAIcAAgJ5g96NwAMAQAcAAgJ5g96NwAMAQAAAA==.',
Ze='Zekos:BAAALgAECgYJCQAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8rAAILAAkJ2ByiCQBFAgALAAkJ2ByiCQBFAgAAAA==.Zimdalar:BAABLgAECn8aAAMiAAYJGRxEJAB4AQAiAAYJGRxEJAB4AQAcAAEJ2QygjAAyAAAAAA==.',
Zo='Zolhs:BAAALgAECgEJAgAAAA==.Zolls:BAAALgAECgMJBgAAAA==.',
Zu='Zulre:BAABLgAECn9KAAIZAAkJFRglLgAzAgAZAAkJFRglLgAzAgAAAA==.',
['Ôv']='Ôverkill:BAAALgAECgEJAQABLgAECggJGgAmALEMAA==.',
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
