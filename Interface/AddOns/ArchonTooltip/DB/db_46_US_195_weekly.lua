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

local lookup = {'Evoker-Augmentation','Druid-Balance','Druid-Restoration','Mage-Frost','Warrior-Fury','Warrior-Arms','Priest-Holy','Priest-Shadow','Paladin-Retribution','Warrior-Protection','Warlock-Demonology','Paladin-Holy','Mage-Fire','Priest-Discipline','Druid-Guardian','Monk-Mistweaver','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Survival','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Warlock-Destruction','Paladin-Protection','Druid-Feral','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Monk-Brewmaster','DeathKnight-Blood','DemonHunter-Havoc','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Evoker-Devastation','Hunter-Marksmanship',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Ackrenoth:BAABLgAECn8VAAIBAAgJ5xFuJABpAQABAAgJ5xFuJABpAQAAAA==.',
Ad='Adynn:BAABLgAECn8sAAMCAAgJWySrBQDCAgACAAgJWySrBQDCAgADAAIJsBaSoQCGAAAAAA==.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAAALgAECgcJCAAAAA==.',
Ag='Agrathayn:BAAALgAECgUJBQAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJMwAEAEwaAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAABLgAECn8qAAMFAAgJLCX7BQDGAgAFAAgJLCX7BQDGAgAGAAEJ6RTQSwA6AAAAAA==.Alnharaelune:BAAALgADCgQJCgAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAAALgAECgYJEwAAAA==.',
An='Anali:BAABLgAECn8bAAIHAAgJbiHnBwCqAgAHAAgJbiHnBwCqAgAAAA==.Anani:BAABLgAECn8VAAIIAAgJ5Qe6KgAqAQAIAAgJ5Qe6KgAqAQAAAA==.Andavin:BAABLgAECn8jAAIJAAYJyQQsugDDAAAJAAYJyQQsugDDAAAAAA==.Angreifer:BAABLgAECn8uAAQKAAkJuBusBwA/AgAKAAgJoR2sBwA/AgAFAAkJ+Q5hMgDiAQAGAAIJ3w7RTwAxAAAAAA==.Anori:BAABLgAECn8bAAICAAgJ1RQlGQCrAQACAAgJ1RQlGQCrAQAAAA==.',
Ao='Aonar:BAAALgAECgQJDAAAAA==.',
Ar='Arc:BAABLgAECn8mAAILAAgJVyA9FwBhAgALAAgJVyA9FwBhAgAAAA==.Archenteron:BAAALgAECgIJAgAAAA==.Arctat:BAAALgAECgMJAwAAAA==.Ardorcinder:BAAALgAECgIJAgAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJCwAAAA==.Artea:BAAALgAECgYJBgAAAA==.',
As='Asbjorne:BAABLgAECn8ZAAIMAAcJ9hbeIQCrAQAMAAcJ9hbeIQCrAQAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
Au='Audi:BAAALgADCgMJAwAAAA==.Augamand:BAAALgAECgYJCAAAAA==.Autumnmoon:BAABLgAECn8bAAINAAYJYA54BQAVAQANAAYJYA54BQAVAQAAAA==.',
Av='Avelos:BAACLgAFFH8GAAMHAAMJZQaQFwCwAAAHAAMJZQaQFwCwAAAIAAIJWAMRIgB4AAAuAAQKfy0ABAcACQm4Gc0RAAoCAAcACQm4Gc0RAAoCAA4ABAmHBspGAIYAAAgAAgmuDMhQAGYAAAAA.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAABLgAECn8dAAQPAAgJgRhdCgDaAQAPAAcJ+BtdCgDaAQACAAYJZAoQTgDxAAADAAIJIwN8yQA3AAAAAA==.Ayzmist:BAAALgAECgYJCQAAAA==.Ayzmyth:BAABLgAECn8dAAIQAAYJjg58OAD5AAAQAAYJjg58OAD5AAAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAIRAAcJ7yAVDwCgAgARAAcJ7yAVDwCgAgAAAA==.Bashra:BAAALgAECgYJEQAAAA==.',
Be='Beasic:BAABLgAECn8uAAMSAAkJxQv3PQDlAAASAAcJFgn3PQDlAAARAAYJmgH1gwBcAAAAAA==.Beletili:BAABLgAECn8qAAIHAAgJPBbEEgD+AQAHAAgJPBbEEgD+AQAAAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn8nAAMTAAkJ/BAtUwCrAQATAAkJqxAtUwCrAQAUAAYJqQ5tEgDUAAAAAA==.Birdman:BAAALgAECgUJCQABLgAECgkJJwATAPwQAA==.Bismuth:BAAALgAECgMJAwAAAA==.',
Bj='Bjornin:BAAALgAECgEJAQAAAA==.',
Bl='Blackraven:BAABLgAECn8eAAMVAAcJGRptFwCfAQAVAAcJCBhtFwCfAQAWAAEJ8R4kvABbAAAAAA==.Blatendrg:BAABLgAECn8vAAIBAAkJ8hAIHACnAQABAAkJ8hAIHACnAQAAAA==.Blindcloud:BAAALgAECgYJEwAAAA==.',
Bo='Boot:BAAALgAECgQJDQAAAA==.Bophedes:BAAALgAECgcJEwAAAA==.Borodemonin:BAEALgAECgYJEgAAAA==.Bosstun:BAAALgADCgMJAwAAAA==.Bozrohin:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn8uAAIHAAkJ5RS5EAAZAgAHAAkJ5RS5EAAZAgAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Brieanna:BAAALgADCgMJAwAAAA==.Bromith:BAAALgAECgEJAQAAAA==.Brugen:BAAALgAECgYJBgAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgYJDAAAAA==.Cariñosa:BAAALgAECgEJAQAAAA==.Carøline:BAAALgAECgEJAQAAAA==.Caska:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgUJCQAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8iAAMXAAgJNxzILQADAgAXAAgJNxzILQADAgAYAAEJ3wtJGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgYJEQAAAA==.Charles:BAABLgAECn8tAAIZAAkJlCTyAQAvAwAZAAkJlCTyAQAvAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiarus:BAAALgADCgkJDwABLgAECgkJLgAKALgbAA==.Chiot:BAABLgAECn8qAAIKAAkJXByXBQB5AgAKAAkJXByXBQB5AgAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8gAAMFAAgJMxi7GwDDAQAFAAgJLRe7GwDDAQAKAAQJchgwJADGAAAAAA==.Chuga:BAABLgAECn8cAAMLAAgJwQqAbwAhAQALAAgJ6QiAbwAhAQAaAAQJHQ3BJQBWAAAAAA==.',
Ci='Cimerian:BAABLgAECn8bAAMbAAcJoA3bHwAJAQAbAAcJoA3bHwAJAQAJAAQJrgNn8gBqAAAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwAAAA==.',
Co='Cobalticus:BAAALgAECgYJDAAAAA==.Corange:BAAALgADCgkJEwAAAA==.Corlock:BAAALgADCgQJBgAAAA==.Cormech:BAAALgAECgcJEQAAAA==.Cornite:BAABLgAECn8VAAIXAAcJfA2cbABEAQAXAAcJfA2cbABEAQAAAA==.',
Cr='Crizzo:BAABLgAECn8pAAIWAAgJDBmoLgDSAQAWAAgJDBmoLgDSAQAAAA==.',
Cy='Cyndrial:BAAALgADCgMJBQAAAA==.',
Da='Daddyslilgrl:BAAALgAECgYJDwAAAA==.Dakra:BAEBLgAECn8hAAIGAAkJPRrGBgBBAgAGAAkJPRrGBgBBAgAAAA==.Dalamar:BAAALgAFFAMJCQAAAQ==.Dalyeth:BAABLgAECn8cAAIUAAYJ3yXZBABlAgAUAAYJ3yXZBABlAgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAABLgAFFH8GAAIWAAMJzw09GQCiAAAWAAMJzw09GQCiAAAAAA==.Daunt:BAAALgADCgkJCQABLgAECggJJwASANAMAA==.',
De='Decypher:BAABLgAECn8eAAIcAAgJYxDbDACLAQAcAAgJYxDbDACLAQAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Deliverance:BAAALgAFFAQJCAABLgAFFAMJCQAdAAAAAQ==.Demonablaze:BAAALgAECgEJAQAAAA==.Dentik:BAABLgAECn8dAAMDAAcJIRIATwANAQADAAYJhREATwANAQAPAAIJ4QKDRQAnAAAAAA==.Denuma:BAAALgAECgEJAQAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgQJCQABLgAECggJHgAcAGMQAA==.',
Di='Diamair:BAABLgAECn80AAMeAAkJhRisAgDgAQAeAAgJExisAgDgAQAEAAkJ8A/yQADZAQAAAA==.Diamones:BAAALgAECgMJAwAAAA==.Dixiee:BAAALgAECgMJAwAAAA==.',
Dn='Dnegelpal:BAABLgAECn8mAAIJAAkJUhBCQgC5AQAJAAkJUhBCQgC5AQAAAA==.',
Do='Docbison:BAAALgADCgMJAwABLgADCgkJGQAdAAAAAA==.Dodgecharger:BAAALgAECgMJBwAAAA==.Dornix:BAABLgAECn8pAAILAAgJZyBtHAA/AgALAAgJZyBtHAA/AgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dragerin:BAAALgAECgcJDAAAAA==.Dragonfood:BAAALgAECgYJDAAAAA==.Drakilu:BAABLgAECn8uAAIWAAkJxxqMFABlAgAWAAkJxxqMFABlAgAAAA==.Drasic:BAACLgAFFH8GAAIDAAMJgRExKgDNAAADAAMJgRExKgDNAAAuAAQKfzkAAgMACAk+IxgGACQDAAMACAk+IxgGACQDAAAA.Dreddscott:BAAALgADCgYJBgABLgAECgkJKwAfANEeAA==.Drophin:BAAALgADCgkJEwAAAA==.Drunken:BAABLgAECn8pAAIgAAgJbh6ICgBSAgAgAAgJbh6ICgBSAgAAAA==.Druphin:BAAALgADCgYJEgAAAA==.',
Du='Durward:BAABLgAECn8rAAQXAAgJUCHSGQBqAgAXAAgJUCHSGQBqAgAhAAQJ/w5PJwC4AAAYAAEJ6hFCIgAyAAAAAA==.Duvo:BAABLgAECn8XAAIWAAYJtx2JQQCIAQAWAAYJtx2JQQCIAQAAAA==.',
Dw='Dwarfo:BAAALgAECgIJAwAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAABLgAECn8WAAMPAAUJgwb1MQBfAAAPAAUJgwb1MQBfAAACAAQJpQAxZwA1AAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIYAAgJlR6GAgCPAgAYAAgJlR6GAgCPAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAABLgAECn8ZAAILAAgJ/wHoqgCrAAALAAgJ/wHoqgCrAAAAAA==.Elemental:BAACLgAFFH8IAAISAAQJPAhZGgACAQASAAQJPAhZGgACAQAuAAQKfykAAxIACQkiGagOALoCABIACQkiGagOALoCABEAAwm4CRmOAF4AAAEuAAUUBQkPAAIA3goA.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgAECgMJAwAAAA==.Elloseth:BAABLgAECn8cAAIIAAYJyRsjHgB/AQAIAAYJyRsjHgB/AQAAAA==.Elmorin:BAAALgAECgUJBQAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAAALgAECgMJBwAAAA==.',
Ep='Epica:BAABLgAECn8kAAIEAAcJ+xRzZgByAQAEAAcJ+xRzZgByAQAAAA==.',
Er='Eragonhawk:BAABLgAECn8dAAIJAAgJ/xdiNADpAQAJAAgJ/xdiNADpAQAAAA==.Erelynn:BAAALgADCgUJCQAAAA==.Eroldan:BAABLgAECn8ZAAMRAAcJIyCREgBmAgARAAcJIyCREgBmAgASAAEJKRLydgAxAAAAAA==.Erovianoria:BAACLgAFFH8JAAIWAAMJggQPPwDHAAAWAAMJggQPPwDHAAAuAAQKfygAAhYACQm8Fv8WAIACABYACQm8Fv8WAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.Eräthis:BAAALgAECgMJAwAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAABLgAECn8iAAIiAAgJ6yCIBgCAAgAiAAgJ6yCIBgCAAgAAAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8lAAIRAAgJwRMMLACxAQARAAgJwRMMLACxAQAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Fa='Fatalfury:BAABLgAECn8ZAAIJAAgJNRdXPgDFAQAJAAgJNRdXPgDFAQAAAA==.Fauxstorm:BAAALgAECgQJDAAAAA==.',
Fi='Finngan:BAABLgAECn8oAAIaAAkJ2QvFCgBGAQAaAAkJ2QvFCgBGAQAAAA==.Fireina:BAAALgAECgYJEAAAAA==.',
Fo='Forestkin:BAAALgAECgMJBQABLgAECgYJHAAUAN8lAA==.Fossilis:BAABLgAECn8YAAMjAAcJHgWzDgD5AAAjAAcJAQWzDgD5AAAfAAUJ2wIUTwCzAAAAAA==.',
Fr='Frozenthunda:BAAALgAECgMJBwAAAA==.',
Fu='Furna:BAABLgAECn8iAAIOAAYJhxRyHgB/AQAOAAYJhxRyHgB/AQAAAA==.',
Fy='Fyahka:BAAALgADCgQJBAAAAA==.Fyon:BAAALgAECgEJAQAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAABLgAECn82AAIFAAkJ+RcfDQBWAgAFAAkJ+RcfDQBWAgAAAA==.',
Gh='Ghorienge:BAAALgAECgYJDwAAAA==.Ghostcat:BAAALgADCgIJAgAAAA==.',
Gi='Gilox:BAABLgAECn8bAAIjAAgJGRB+BwCWAQAjAAgJGRB+BwCWAQAAAA==.',
Gn='Gndmexia:BAAALgAECgIJBQAAAA==.Gneiss:BAAALgAECgQJCQAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8iAAIDAAkJhyCdBABEAwADAAkJhyCdBABEAwAAAA==.',
Gr='Graymon:BAAALgAECgQJDAAAAA==.Greebo:BAAALgAECgQJDAAAAA==.Griknor:BAABLgAECn8fAAMGAAYJRgU/IgDaAAAGAAYJRgU/IgDaAAAFAAQJBgNBXwB3AAAAAA==.Grimniel:BAAALgAECgIJAwAAAA==.Gryphonwrest:BAAALgADCgMJBAAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAAALgAECgQJBAAAAA==.',
Gw='Gwenyver:BAABLgAECn8XAAIJAAYJpQLs1wCVAAAJAAYJpQLs1wCVAAAAAA==.',
Ha='Hadoukendk:BAAALgAECgcJDAAAAA==.Hafaken:BAAALgAECgEJAQAAAA==.Hallien:BAAALgADCgEJAQAAAA==.Hamord:BAABLgAECn8ZAAIbAAcJchBpGgDwAAAbAAcJchBpGgDwAAAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgAECgQJBAAAAA==.Harliqynn:BAABLgAECn8bAAIWAAgJ3RrtIABAAgAWAAgJ3RrtIABAAgAAAA==.Harlock:BAABLgAECn8iAAIfAAgJRh5/DQAAAgAfAAgJRh5/DQAAAgAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.Hazelnuts:BAAALgAECgEJAQAAAA==.',
He='Heartkiller:BAAALgAECgIJAgABLgAECgkJJAAEAPsUAA==.Helleye:BAAALgAECgYJCgAAAA==.',
Hi='Hiten:BAABLgAECn8uAAQfAAkJsBhMCgA0AgAfAAkJqBhMCgA0AgAjAAUJRBWIDQBEAQAkAAEJjwiEGgAsAAAAAA==.',
Ho='Hopedaimond:BAABLgAECn8jAAISAAgJbw58KwBCAQASAAgJbw58KwBCAQAAAA==.',
Hu='Huntertattoo:BAABLgAECn8uAAIWAAkJAA4mMgDDAQAWAAkJAA4mMgDDAQAAAA==.',
Hy='Hypro:BAABLgAECn8xAAIRAAkJfCU7AADXAwARAAkJfCU7AADXAwAAAA==.',
['Há']='Háides:BAAALgADCgIJAgAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIbAAcJByOXBAC6AgAbAAcJByOXBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJEgAAAA==.',
Ie='Iepa:BAAALgADCgYJBgAAAA==.',
Il='Ilthad:BAAALgAECgYJEQAAAA==.',
Im='Imperio:BAAALgADCgYJBgAAAA==.Imshalar:BAAALgAECggJDgAAAA==.',
In='Inconcvabull:BAAALgAECggJDwAAAA==.Inferious:BAAALgAECgUJDAABLgAECgcJEwAdAAAAAA==.Infurryating:BAAALgAECgcJBwAAAA==.Inistus:BAAALgADCgUJBQAAAA==.',
Ir='Iralis:BAAALgAECgYJDQAAAA==.',
Is='Ischadè:BAAALgADCgkJCgAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgQJBwAAAA==.Itsirk:BAABLgAECn8rAAIMAAgJdxoCEwAxAgAMAAgJdxoCEwAxAgAAAA==.',
Iz='Izyebelle:BAABLgAECn8hAAIIAAcJiwG/TAB5AAAIAAcJiwG/TAB5AAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAABLgAECn8dAAIbAAgJEiKRAwCNAgAbAAgJEiKRAwCNAgAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jimmydin:BAABLgAECn82AAMMAAkJJhm0HgAiAgAMAAkJJhm0HgAiAgAJAAgJHhdrLwD8AQAAAA==.Jix:BAABLgAECn8YAAMaAAgJkhi9DgDeAQAaAAYJtxy9DgDeAQALAAQJSAxGrQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8wAAQTAAkJQhJhOgCTAQATAAkJoRFhOgCTAQAUAAMJyxWlHgCSAAAiAAEJYw4QbwA2AAAAAA==.',
Ju='Julkan:BAAALgAECgQJBgAAAA==.Junhoong:BAABLgAECn8sAAIJAAgJYBJMTwCTAQAJAAgJYBJMTwCTAQAAAA==.',
Jy='Jynnysa:BAAALgAECgMJAwABLgAECgYJHAAbABIgAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAABLgAECn8UAAIGAAcJTxLUFQBVAQAGAAcJTxLUFQBVAQAAAA==.Kairoll:BAABLgAECn8mAAIHAAkJuBVEDwArAgAHAAkJuBVEDwArAgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Kannah:BAAALgAECgYJCwAAAA==.Karaa:BAABLgAECn8dAAIQAAcJbQLVTQCYAAAQAAcJbQLVTQCYAAAAAA==.Kariena:BAABLgAECn8dAAIWAAcJFh05LADdAQAWAAcJFh05LADdAQAAAA==.Katesluage:BAABLgAECn8zAAIEAAkJTBqlIgBVAgAEAAkJTBqlIgBVAgAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJMwAEAEwaAA==.',
Ke='Keeya:BAABLgAECn8iAAIXAAYJfxJ0jgABAQAXAAYJfxJ0jgABAQAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kelkan:BAAALgAECgEJAQAAAA==.Kendari:BAAALgAECgYJEgAAAA==.Kernasas:BAABLgAECn8mAAIaAAcJ/xQ9CQBlAQAaAAcJ/xQ9CQBlAQAAAA==.Keslynn:BAAALgAECgIJAwABLgAECgcJHQAWABYdAA==.Ketrani:BAAALgAECgEJAgABLgAECgcJHQAWABYdAA==.',
Kh='Khiari:BAAALgADCgkJIAABLgAECgYJGwAJANcRAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAAALgAECgQJCQAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJKQALAGcgAA==.Kirtiao:BAAALgAECgEJAgABLgAECgcJHQAWABYdAA==.Kitalidie:BAAALgAECgIJAgABLgAECgcJHQAWABYdAA==.Kizaraan:BAABLgAECn8YAAIlAAcJvwMKHADWAAAlAAcJvwMKHADWAAAAAA==.',
Kl='Kleyntamar:BAAALgAECgQJBAAAAA==.',
Kn='Knyghtly:BAAALgAECgkJAwAAAA==.',
Ko='Konstantien:BAAALgAECgYJBgAAAA==.',
Kr='Kritter:BAAALgAECgMJBwAAAA==.Krohm:BAABLgAECn8kAAIJAAkJaSAoEwD6AgAJAAkJaSAoEwD6AgAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgAECgQJBwAAAA==.Kungfuey:BAAALgADCgcJBwAAAA==.Kupau:BAAALgAECgQJBAAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Lanss:BAABLgAECn85AAIKAAkJ9COIAQAhAwAKAAkJ9COIAQAhAwAAAA==.Larachel:BAAALgAECgUJBwAAAA==.Laur:BAABLgAECn8sAAIIAAkJ9BJ7FADbAQAIAAkJ9BJ7FADbAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8jAAIJAAkJUBylGABxAgAJAAkJUBylGABxAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAAALgAECgQJDAAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAwAAAA==.Lilipo:BAABLgAECn8dAAIZAAYJswdcOADSAAAZAAYJswdcOADSAAAAAA==.Liltara:BAABLgAECn8bAAIEAAcJFAK1ygC3AAAEAAcJFAK1ygC3AAAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llanz:BAAALgADCgkJKgAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAABLgAECn8tAAILAAgJvRQdPQCqAQALAAgJvRQdPQCqAQAAAA==.Lokdan:BAAALgAECgMJBAAAAA==.Loppy:BAAALgAECgIJAgAAAA==.Loula:BAABLgAECn8fAAIEAAgJCAPbpwD1AAAEAAgJCAPbpwD1AAAAAA==.Lowryder:BAABLgAECn8dAAMfAAgJqxSDFACoAQAfAAgJqxSDFACoAQAjAAEJmwZiIAAxAAAAAA==.Loxes:BAAALgAECgcJDQABLgAECgYJCwAdAAAAAA==.Loxy:BAAALgAECgUJDAAAAA==.',
Lu='Lukam:BAAALgAECgUJDAAAAA==.Lunaellana:BAAALgADCgcJEQAAAA==.Lus:BAABLgAECn8UAAMLAAYJsRfzegBmAQALAAYJsRfzegBmAQAaAAIJuggxUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAAALgAECgYJDQABLgAFFAMJBQADAOIFAA==.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
Ma='Magicfang:BAAALgAECgYJCQAAAA==.Maiku:BAABLgAECn8rAAILAAkJlBJgLgDiAQALAAkJlBJgLgDiAQAAAA==.Makado:BAABLgAECn8fAAQaAAgJlQjSFwCuAAALAAUJ3wWKmwDIAAAaAAcJQAfSFwCuAAAmAAQJOQdzGACAAAAAAA==.Makaris:BAAALgADCgMJAwAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAABLgAECn8YAAILAAYJyg5TdwAQAQALAAYJyg5TdwAQAQAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Matua:BAAALgAECgEJAQAAAA==.Maycee:BAAALgADCgkJGQAAAA==.',
Mc='Mcnaugh:BAABLgAECn8ZAAMhAAcJIw87IQDjAAAhAAcJfgw7IQDjAAAXAAQJKRRUpADaAAAAAA==.Mcsaltface:BAABLgAECn8XAAIJAAYJzhq1WQB4AQAJAAYJzhq1WQB4AQAAAA==.',
Me='Meddic:BAAALgADCgYJBwAAAA==.Menaras:BAACLgAFFH8JAAMRAAMJfw7JNgCpAAARAAMJfw7JNgCpAAASAAIJZgLhLwBzAAAuAAQKfysAAxIACQkmHTsSAJECABIACQkmHTsSAJECABEABwk3F49BAHoBAAAA.Menarot:BAAALgAECgUJBQABLgAFFAMJCQARAH8OAA==.Mendais:BAAALgADCgQJBAAAAA==.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAECgkJLgAKALgbAA==.',
Mi='Mikeydluffy:BAAALgAECggJEAAAAA==.Mirosmundo:BAACLgAFFH8KAAIgAAQJERNTGAAdAQAgAAQJERNTGAAdAQAuAAQKfy0AAiAACQkmH9oIAPkCACAACQkmH9oIAPkCAAAA.Mistfit:BAABLgAECn8WAAIQAAcJSBMjJgBtAQAQAAcJSBMjJgBtAQAAAA==.Miyagi:BAAALgAECgYJEAAAAA==.Miyu:BAABLgAECn8kAAMHAAgJ9xKeKQAyAQAHAAcJ3hGeKQAyAQAIAAUJPxFzQQDuAAAAAA==.',
Mo='Mod:BAABLgAECn8rAAMSAAkJlCS1BgC1AgASAAgJRyS1BgC1AgARAAYJihOrUwA3AQAAAA==.Modaka:BAAALgAECgIJAgAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moggatorash:BAAALgAECgcJEgAAAA==.Mogtham:BAABLgAECn8uAAIPAAkJShVgCQDvAQAPAAkJShVgCQDvAQAAAA==.Moirenna:BAAALgAECgEJAQAAAA==.Moisticklez:BAAALgAECgMJBgAAAA==.Monkeyspaul:BAABLgAECn8cAAIZAAgJQhvDFABHAgAZAAgJQhvDFABHAgABLgAECgkJKwAKAM0cAA==.Moonfall:BAAALgAECgQJEQAAAA==.Moonpig:BAAALgAECgMJAwAAAA==.Moosader:BAABLgAECn8mAAMJAAcJXhidSACmAQAJAAcJXhidSACmAQAMAAYJcQiVVwAdAQAAAA==.Morellea:BAACLgAFFH8LAAITAAQJ1QtmMAAVAQATAAQJ1QtmMAAVAQAuAAQKfxQAAhMACAkpGVk2AB0CABMACAkpGVk2AB0CAAAA.Morighann:BAABLgAECn8qAAIWAAkJvSOSBwDmAgAWAAkJvSOSBwDmAgAAAA==.Morkith:BAAALgAECgEJAQAAAA==.Morphalot:BAAALgAECgIJAgAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mostank:BAAALgADCgMJAwAAAA==.Mousse:BAAALgADCgMJAwABLgAECgkJLwAQAEgkAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgAECgIJAgABLgAECggJJwASANAMAA==.',
My='Mylea:BAAALgADCgUJBQABLgAECgQJEQAdAAAAAA==.Mynkx:BAABLgAECn8bAAIJAAYJ1xESggAhAQAJAAYJ1xESggAhAQAAAA==.Mythyras:BAABLgAECn8cAAIbAAYJEiBFDACrAQAbAAYJEiBFDACrAQABLgAECgYJHAAbABIgAA==.',
Na='Nahaman:BAAALgADCgkJGQAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8aAAIMAAYJphE1LwBQAQAMAAYJphE1LwBQAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8PAAMCAAUJ3gqmGAAOAQACAAQJ3gqmGAAOAQADAAEJwAEbVgAzAAAuAAQKfxYABAMACAl0GxElACUCAAMACAl0GxElACUCABwAAwklERIkALQAAAIAAgkLF7ZbAFAAAAAA.Netherite:BAABLgAECn8YAAIeAAcJ6A56BQA+AQAeAAcJ6A56BQA+AQAAAA==.Nethim:BAAALgAECgEJAQABLgAECgcJGAAeAOgOAA==.Netre:BAAALgAECgcJDQAAAA==.Nezana:BAABLgAECn8kAAQlAAgJrRmMCgDrAQAlAAcJ/heMCgDrAQABAAYJgQpfOQDzAAAnAAMJNQgpNwBeAAAAAA==.',
Ni='Nianah:BAAALgADCggJCwAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8rAAIPAAkJyB25AwCZAgAPAAkJyB25AwCZAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Noranna:BAAALgAECgQJDAAAAA==.',
['Nø']='Nøva:BAAALgADCgcJBwABLgAFFAQJDQAJAP4hAA==.',
Oh='Ohthesemyboo:BAAALgAECgYJCgAAAA==.Ohwellz:BAAALgAECgcJEwABLgAECggJEQAdAAAAAA==.',
Op='Ophin:BAABLgAECn8bAAIXAAcJXBuuMwDrAQAXAAcJXBuuMwDrAQAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Or:BAAALgAECgYJCwAAAA==.Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.Ornaxxi:BAAALgADCgYJAgAAAA==.',
Ov='Overheal:BAABLgAECn8XAAIlAAcJvgxWEwBJAQAlAAcJvgxWEwBJAQAAAA==.',
Pa='Padhu:BAABLgAECn8XAAIgAAcJ0wcpOgDZAAAgAAcJ0wcpOgDZAAAAAA==.Palox:BAAALgAECgYJBgAAAA==.Panamared:BAABLgAECn8rAAIfAAkJ0R7JBgB7AgAfAAkJ0R7JBgB7AgAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn8vAAIHAAkJBxSWEgAAAgAHAAkJBxSWEgAAAgAAAA==.Pezza:BAABLgAECn8XAAIRAAcJrRGmOQBqAQARAAcJrRGmOQBqAQAAAA==.',
Ph='Phantomlord:BAAALgAECgYJCAABLgAECgkJJAAEAPsUAA==.Phaze:BAABLgAECn8aAAIVAAkJ0BcPDQAUAgAVAAkJ0BcPDQAUAgAAAA==.Phia:BAABLgAECn8eAAMWAAkJ/x4ZEgCnAgAWAAkJ/x4ZEgCnAgAVAAEJEhWBLABCAAAAAA==.Pholcus:BAAALgAECgUJCAAAAA==.',
Pr='Prothagon:BAABLgAECn8rAAMlAAkJshdjBQB+AgAlAAkJshdjBQB+AgABAAIJQBaPWAB1AAAAAA==.',
Ps='Psylix:BAABLgAECn8rAAIiAAkJdRedCgAgAgAiAAkJdRedCgAgAgAAAA==.',
Pu='Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAAALgAECgQJDAAAAA==.Raevennlumis:BAABLgAECn8aAAIJAAgJLQa3jgALAQAJAAgJLQa3jgALAQAAAA==.Rahkhard:BAAALgAECgMJAwAAAA==.Randrius:BAAALgADCgYJBgAAAA==.Ransha:BAAALgAECgUJBgABLgAECgkJJwATAPwQAA==.Rascdit:BAAALgAECgcJDgAAAA==.',
Re='Redwood:BAAALgAECgYJDQAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Renwic:BAAALgAECgMJBgAAAA==.Reylani:BAEALgAECgcJBwABLgAECgkJIQAGAD0aAA==.',
Rh='Rheingard:BAAALgADCgUJCAAAAA==.Rhemiroll:BAAALgAECgcJDgAAAA==.Rhintalle:BAEALgADCgUJBwABLgAECgQJCwAdAAAAAA==.',
Ri='Rickroll:BAAALgAECgIJAgAAAA==.Riepa:BAAALgADCgEJAQAAAA==.Risotto:BAABLgAECn8vAAMQAAkJSCR8AQCaAwAQAAkJSCR8AQCaAwAZAAEJkBdXZwBAAAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgAECgEJAQAAAA==.',
Ru='Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgYJDgAAAA==.Sagehawk:BAAALgAECgYJEwAAAA==.Sali:BAAALgAECgEJAgAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIZAAgJJhQ4GQCYAQAZAAgJJhQ4GQCYAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAABLgAECn8pAAIEAAgJVRu3LAAlAgAEAAgJVRu3LAAlAgAAAA==.Sarova:BAAALgAECgMJBAAAAA==.Satori:BAAALgAECgQJDAAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJAgAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAABLgAECn8dAAIXAAkJERq4IABCAgAXAAkJERq4IABCAgAAAA==.Sellidor:BAAALgAECggJEwAAAA==.Senamue:BAAALgADCggJCAAAAA==.Seriniyaa:BAAALgAECgYJDgAAAA==.',
Sh='Shaey:BAAALgAECgMJAwAAAA==.Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8mAAIJAAgJ9gICwgC2AAAJAAgJ9gICwgC2AAAAAA==.Shirito:BAABLgAECn8uAAIXAAkJGiaBAgBaAwAXAAkJGiaBAgBaAwAAAA==.Shiritodh:BAABLgAECn8eAAITAAgJeCXTDgCOAgATAAgJeCXTDgCOAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8jAAMbAAkJ7iI2AQAMAwAbAAkJ7iI2AQAMAwAJAAYJsBY2egCGAQABLgAFFAIJAgAdAAAAAA==.Shyle:BAAALgAECgQJCQAAAA==.',
Si='Sienje:BAABLgAECn8cAAIJAAgJqRnqNADnAQAJAAgJqRnqNADnAQAAAA==.Simpleson:BAABLgAECn8eAAMLAAgJkBesMADYAQALAAgJkBesMADYAQAaAAUJxQ7ONADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAABLgAECn8bAAMiAAcJPhTEGwA4AQAiAAYJzBbEGwA4AQATAAYJ7gqzgADMAAAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAAALgAECgYJBQABLgAECgkJAwAdAAAAAA==.Skribble:BAAALgAECgQJEAAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slackbear:BAABLgAECn8dAAILAAgJZxIiPwCjAQALAAgJZxIiPwCjAQAAAA==.Slaete:BAAALgAECgYJDQAAAA==.Slycen:BAAALgADCgcJBwAAAA==.',
So='Sokey:BAAALgAECgMJBAAAAA==.Solemn:BAAALgAECgcJEwABLgAECggJEwAdAAAAAA==.Soleva:BAAALgADCgkJDwAAAA==.Solrana:BAAALgAECgYJEwAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgAECgMJBAAAAA==.Sorren:BAAALgADCgkJLQAAAA==.Sorrows:BAABLgAECn8UAAIaAAcJrgoqEADyAAAaAAcJrgoqEADyAAAAAA==.Sosukesagara:BAAALgAECgMJBAAAAA==.Sotta:BAAALgAECgMJBQAAAA==.Soulbled:BAABLgAECn8mAAIUAAkJmQ40DQCEAQAUAAkJmQ40DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAAALgAECgYJEAAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAAALgAECgYJDgAAAA==.Superbautumn:BAABLgAECn8ZAAIJAAkJox8QFwB7AgAJAAkJox8QFwB7AgAAAA==.',
Sy='Sylo:BAABLgAECn8cAAIXAAcJ9RV/YQBeAQAXAAcJ9RV/YQBeAQAAAA==.Synalaid:BAAALgAECgQJBQAAAA==.Synnyca:BAAALgAECgMJBAABLgAECgYJHAAbABIgAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAAALgAECgYJCwAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIXAAkJsht+KACYAgAXAAkJsht+KACYAgAAAA==.Taeonaki:BAAALgAECgMJAwAAAA==.Tagnaras:BAAALgADCggJEQAAAA==.Tahlang:BAAALgAECgEJBAAAAA==.Tali:BAABLgAECn8YAAMWAAcJtg08VABNAQAWAAcJtg08VABNAQAoAAEJYwYDLwAkAAAAAA==.Tamune:BAABLgAECn8VAAIjAAcJ1xydBAD9AQAjAAcJ1xydBAD9AQAAAA==.Tangle:BAAALgAECgcJDAABLgAECgkJAwAdAAAAAA==.Tanka:BAABLgAECn8lAAMGAAgJ9iOEAwCoAgAGAAgJ9iOEAwCoAgAKAAIJfRI4OwByAAAAAA==.Tanuki:BAAALgADCgkJMwAAAA==.Tashlaraz:BAEALgAECgQJCwAAAA==.Tasi:BAAALgADCgEJAQAAAA==.Taurannosaur:BAAALgAECgEJAQAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.Tavia:BAAALgADCgMJAwABLgAECggJIgAdAAAAAQ==.',
Te='Temporantus:BAAALgAECgUJCgAAAA==.Tenko:BAAALgAECgcJDgAAAA==.',
Th='Thaddeus:BAABLgAECn8bAAISAAgJxhD3JwBZAQASAAgJxhD3JwBZAQAAAA==.Thariane:BAAALgADCgcJDgABLgAECgEJAQAdAAAAAA==.Therm:BAACLgAFFH8HAAIJAAQJeya4BgDJAQAJAAQJeya4BgDJAQAuAAQKfzQAAgkACQlJJmoHAFwDAAkACQlJJmoHAFwDAAAA.Thoramier:BAABLgAECn8WAAMbAAcJURkhDgCLAQAbAAYJThwhDgCLAQAJAAYJ4wyHlQD/AAAAAA==.Thorgrymm:BAAALgADCgUJBQAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timoonja:BAAALgAECgQJCQAAAA==.',
To='Tonatuih:BAABLgAECn8sAAQTAAgJ1R0jOACcAQATAAcJzRgjOACcAQAUAAYJlxaiDQB8AQAiAAgJnxnUJADsAAAAAA==.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAcJGAAKALoiAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAABLgAECn8hAAImAAkJGRbaAwAIAgAmAAkJGRbaAwAIAgAAAA==.Triipod:BAAALgAECgEJAQAAAA==.Trinkat:BAAALgAECgQJDAAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgcJDQAAAA==.Tynk:BAAALgAECgQJBAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tyreitherinn:BAAALgADCgUJCAAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAAALgAECgYJDgAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn8xAAILAAkJ9wTsawApAQALAAkJ9wTsawApAQAAAA==.Valsedor:BAAALgAECgYJBgAAAA==.Valwar:BAABLgAECn8kAAIFAAkJ8hn3EgASAgAFAAkJ8hn3EgASAgAAAA==.Vareyn:BAAALgAECgYJEQAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgUJCgAAAA==.Velle:BAAALgAECgUJBQABLgAFFAMJCQAWAIIEAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAABLgAECn8fAAMbAAgJ8R1+BgAsAgAbAAcJpht+BgAsAgAJAAYJVR9eRwANAgAAAA==.Vorth:BAABLgAECn8pAAMYAAgJghlzBgDDAQAYAAgJLxhzBgDDAQAXAAcJExNHngDkAAAAAA==.Vorükh:BAABLgAECn8XAAMjAAcJCApBDQBKAQAjAAYJaAtBDQBKAQAfAAYJsANnMQC0AAABLgAECgkJGQAcAC8RAA==.',
Vy='Vyrlana:BAACLgAFFH8HAAIlAAMJgAReGQCfAAAlAAMJgAReGQCfAAAuAAQKfxwAAyUACQndEt4KAOUBACUACQndEt4KAOUBAAEABgnRAuZIALQAAAAA.',
Wa='Waldir:BAABLgAECn8uAAIMAAkJ9iPWAACeAwAMAAkJ9iPWAACeAwAAAA==.Waldstein:BAABLgAECn8WAAIXAAYJSxbScAA7AQAXAAYJSxbScAA7AQAAAA==.Wanted:BAABLgAECn8iAAQJAAcJYw+HhwBrAQAJAAcJYw+HhwBrAQAMAAUJnBLHOAAZAQAbAAYJegU9KQB/AAAAAA==.Watz:BAABLgAECn8oAAIWAAgJjhNoNAC6AQAWAAgJjhNoNAC6AQAAAA==.',
We='Wensa:BAAALgAECgYJCwAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xenophage:BAAALgADCgMJAwAAAA==.Xessala:BAAALgAECgMJBAAAAA==.',
Xh='Xheero:BAACLgAFFH8FAAIWAAMJhg8kNgDsAAAWAAMJhg8kNgDsAAAuAAQKfysAAhYACAkdG2ArAOABABYACAkdG2ArAOABAAAA.Xheerom:BAAALgAECgcJEgAAAA==.',
Yu='Yulica:BAAALgAECgQJDAAAAA==.',
Za='Zaffy:BAABLgAECn8sAAIaAAkJWxIqBQDOAQAaAAkJWxIqBQDOAQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgAECgEJAgAAAA==.Zaleron:BAAALgADCgkJJQAAAA==.Zanazath:BAABLgAECn8dAAMnAAcJ0Ro3EADZAQAnAAYJRhw3EADZAQABAAYJvhMFNAANAQAAAA==.Zaruba:BAABLgAECn8nAAMSAAgJ0AwZNQANAQASAAgJ0AwZNQANAQARAAIJ5wCcmgA4AAAAAA==.Zatheon:BAABLgAECn8lAAIJAAgJXRnBNADnAQAJAAgJXRnBNADnAQAAAA==.Zatkyng:BAABLgAECn8bAAIZAAcJBRF4LwBrAQAZAAcJBRF4LwBrAQAAAA==.',
Ze='Zekos:BAAALgAECgQJBwAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8rAAIKAAkJzRw2BgBoAgAKAAkJzRw2BgBoAgAAAA==.Zimdalar:BAAALgAECgQJEQAAAA==.',
Zo='Zolls:BAAALgAECgMJBQAAAA==.',
Zu='Zulre:BAABLgAECn84AAIXAAkJbxZAJgAlAgAXAAkJbxZAJgAlAgAAAA==.',
['Ôv']='Ôverkill:BAAALgADCggJIwABLgAECgcJFwAlAL4MAA==.',
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
