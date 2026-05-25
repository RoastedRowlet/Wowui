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

local lookup = {'Evoker-Augmentation','Druid-Balance','Druid-Restoration','Mage-Frost','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Priest-Holy','Priest-Shadow','Paladin-Retribution','Warrior-Protection','Warlock-Demonology','Paladin-Holy','Mage-Fire','Priest-Discipline','Druid-Guardian','Monk-Mistweaver','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Monk-Windwalker','Warlock-Destruction','Paladin-Protection','Druid-Feral','Unknown-Unknown','Mage-Arcane','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Evoker-Devastation','Hunter-Marksmanship',}
local provider = {region='US',realm='SilverHand',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Ackrenoth:BAABLgAECn8bAAIBAAgJ6RETKgB0AQABAAgJ6RETKgB0AQAAAA==.',
Ad='Adynn:BAABLgAECn80AAMCAAgJ0ySGBQDkAgACAAgJ0ySGBQDkAgADAAIJMh0+kwBqAAAAAA==.',
Ae='Aermoss:BAAALgADCgQJAwAAAA==.Aethreal:BAAALgAECgEJAQAAAA==.',
Af='Afridium:BAAALgAECgcJDAAAAA==.',
Ag='Agrathayn:BAAALgAECgYJCgAAAA==.',
Ai='Ainasluage:BAAALgAECgYJDgABLgAECgkJNAAEAEsaAA==.',
Ak='Akikusa:BAAALgADCgYJBgAAAA==.',
Al='Alexishime:BAAALgADCgYJBgAAAA==.Algolae:BAAALgAECgEJAQAAAA==.Alista:BAABLgAECn8yAAMFAAgJXSV9BgDcAgAFAAgJXSV9BgDcAgAGAAEJ6RQXWwA5AAAAAA==.Alnharaelune:BAAALgADCgYJEAAAAA==.',
Am='Amarea:BAAALgADCgcJBwAAAA==.Amor:BAABLgAECn8dAAIHAAYJZhHacQAYAQAHAAYJZhHacQAYAQAAAA==.',
An='Anali:BAABLgAECn8cAAIIAAgJOiK6CAC7AgAIAAgJOiK6CAC7AgAAAA==.Anani:BAABLgAECn8bAAIJAAgJnwjOLgA8AQAJAAgJnwjOLgA8AQAAAA==.Andavin:BAABLgAECn8tAAIKAAYJ2ATT1wDCAAAKAAYJ2ATT1wDCAAAAAA==.Angreifer:BAACLgAFFH8IAAILAAQJFhK9DwAHAQALAAQJFhK9DwAHAQAuAAQKfy8ABAsACQmvHMcIAEgCAAsACAnBHscIAEgCAAUACQn1DmEyAOIBAAYAAgnfDplfADEAAAAA.Anori:BAABLgAECn8hAAICAAgJhxURHAC6AQACAAgJhxURHAC6AQAAAA==.',
Ao='Aonar:BAAALgAECgUJDwAAAA==.',
Ar='Arc:BAABLgAECn8sAAIMAAgJtyBDFACVAgAMAAgJtyBDFACVAgAAAA==.Archenteron:BAAALgAECgIJBAAAAA==.Arctat:BAAALgAECgMJAwAAAA==.Ardorcinder:BAAALgAECgIJBAAAAA==.Ariaannaas:BAAALgADCgUJBgAAAA==.Arkaan:BAAALgAECgUJCwAAAA==.Artea:BAAALgAECgYJBgAAAA==.',
As='Asbjorne:BAABLgAECn8bAAINAAcJ9hZAKACjAQANAAcJ9hZAKACjAQAAAA==.Aseopp:BAAALgADCgIJAgAAAA==.',
Au='Audi:BAAALgADCgMJAwAAAA==.Augamand:BAAALgAECgYJCAAAAA==.Autumnmoon:BAABLgAECn8cAAIOAAYJlA8nBgAcAQAOAAYJlA8nBgAcAQAAAA==.',
Av='Avelos:BAACLgAFFH8LAAMIAAQJeQXyFQDjAAAIAAQJeQXyFQDjAAAJAAIJWAP3JwBzAAAuAAQKfy0ABAgACQm4GcUVAP0BAAgACQm4GcUVAP0BAA8ABAmHBspGAIYAAAkAAgmuDIZcAGUAAAAA.',
Aw='Awrfus:BAAALgAECgMJAwAAAA==.',
Ay='Ayrie:BAABLgAECn8oAAQQAAkJoRqiBgBfAgAQAAkJoRqiBgBfAgACAAYJZAoQTgDxAAADAAIJIwN8yQA3AAAAAA==.Ayzmist:BAAALgAECgYJCQAAAA==.Ayzmyth:BAABLgAECn8lAAIRAAcJbw9ZNQBLAQARAAcJbw9ZNQBLAQAAAA==.',
Ba='Babygirldemi:BAABLgAECn8VAAISAAcJ7yAVDwCgAgASAAcJ7yAVDwCgAgAAAA==.Bashra:BAAALgAECgYJEQAAAA==.',
Be='Beasic:BAABLgAECn82AAMTAAkJDQ1mRwDlAAATAAcJwglmRwDlAAASAAYJwwFhkwBmAAAAAA==.Beastmode:BAAALgAECgcJBwAAAA==.Beletili:BAABLgAECn8yAAIIAAgJyBdqEgAkAgAIAAgJyBdqEgAkAgAAAA==.',
Bi='Birb:BAAALgAECgkJDwAAAA==.Birddh:BAABLgAECn8uAAMUAAkJQxLnEQACAQAHAAkJJBEtUwCrAQAUAAYJWhLnEQACAQAAAA==.Birdman:BAAALgAECgYJDwABLgAECgkJLgAUAEMSAA==.Bismuth:BAAALgAECgUJCAAAAA==.',
Bj='Bjornin:BAAALgAECgEJAQAAAA==.',
Bl='Blackraven:BAABLgAECn8lAAMVAAgJsx11JwAXAgAVAAYJNh51JwAXAgAWAAcJgBhYGQC2AQAAAA==.Blatendrg:BAABLgAECn8vAAIBAAkJ9BA8IAC0AQABAAkJ9BA8IAC0AQAAAA==.Blindcloud:BAABLgAECn8UAAIXAAYJcgYmNAC1AAAXAAYJcgYmNAC1AAAAAA==.',
Bo='Boot:BAAALgAECgYJEwAAAA==.Bophedes:BAABLgAECn8UAAMYAAcJHxcsZgB2AQAYAAcJHxcsZgB2AQAZAAEJbw59TgAuAAAAAA==.Borodemonin:BAEBLgAECn8YAAIHAAYJryMGLQD0AQAHAAYJryMGLQD0AQABLgAFFAQJEAAJADIlAA==.Bosstun:BAAALgADCgMJAwAAAA==.Bozrohin:BAAALgADCgMJAwAAAA==.',
Br='Bread:BAAALgAECgMJAwAAAA==.Breae:BAABLgAECn82AAIIAAkJkRXxEgAeAgAIAAkJkRXxEgAeAgAAAA==.Brewstur:BAAALgAECgMJAwAAAA==.Brieanna:BAAALgADCgMJAwAAAA==.Bromith:BAAALgAECgEJAQAAAA==.Brugen:BAAALgAECgYJBgAAAA==.',
Bu='Buneyne:BAAALgADCgYJBgAAAA==.',
Ca='Calenn:BAAALgADCgYJBQAAAA==.Calyma:BAAALgAECgYJDgAAAA==.Cariñosa:BAAALgAECgEJAQAAAA==.Carøline:BAAALgAECgEJAQAAAA==.Caska:BAAALgAECgEJAQAAAA==.Catsclaw:BAAALgAECgUJCgAAAA==.',
Ce='Ceneda:BAAALgADCgQJBAAAAA==.Cenjeru:BAABLgAECn8nAAMYAAgJXh0tLQAnAgAYAAgJXh0tLQAnAgAaAAEJ3wtJGAAvAAAAAA==.Cervantez:BAAALgADCgMJAwAAAA==.',
Ch='Challah:BAAALgAECgYJEQAAAA==.Charles:BAABLgAECn8tAAIbAAkJlSTNAgAkAwAbAAkJlSTNAgAkAwAAAA==.Chezzy:BAAALgAECgQJBAAAAA==.Chiarus:BAAALgADCgkJGAABLgAFFAQJCAALABYSAA==.Chiot:BAABLgAECn8yAAILAAkJKh1FBgCGAgALAAkJKh1FBgCGAgAAAA==.Chonkr:BAAALgAECgcJEQAAAA==.Chubs:BAABLgAECn8iAAMFAAgJMxiWIgC5AQAFAAgJLheWIgC5AQALAAQJchiQKQDAAAAAAA==.Chuga:BAABLgAECn8iAAMMAAgJQg60WAB9AQAMAAgJTg20WAB9AQAcAAQJHQ2sKgBVAAAAAA==.',
Ci='Cimerian:BAABLgAECn8iAAMdAAgJdAzbHwAJAQAdAAcJoA3bHwAJAQAKAAYJdAVvzwDOAAAAAA==.',
Cl='Cloudysky:BAAALgADCggJFwABLgAECgcJHwASAHAQAA==.',
Co='Cobalticus:BAAALgAECgYJDQAAAA==.Corange:BAAALgAECgEJAQAAAA==.Corlock:BAAALgAECgQJBAAAAA==.Cormech:BAAALgAECgcJEwAAAA==.Cornite:BAABLgAECn8XAAIYAAcJQQ6ZfQBCAQAYAAcJQQ6ZfQBCAQAAAA==.',
Cr='Crizzo:BAABLgAECn83AAIVAAkJ8R/3CQDlAgAVAAkJ8R/3CQDlAgAAAA==.',
Cy='Cyndrial:BAAALgADCgMJBQAAAA==.',
Da='Daddyslilgrl:BAABLgAECn8VAAIMAAYJXQJZ0wCJAAAMAAYJXQJZ0wCJAAAAAA==.Dakra:BAEBLgAECn8pAAIGAAkJDxuaBgBwAgAGAAkJDxuaBgBwAgAAAA==.Dalamar:BAAALgAFFAMJCQAAAQ==.Dalandis:BAAALgAECgUJBQAAAA==.Dalyeth:BAABLgAECn8cAAIUAAYJ3yXZBABlAgAUAAYJ3yXZBABlAgAAAA==.Danathirus:BAAALgADCgMJAwAAAA==.Darell:BAAALgADCgUJBQAAAA==.Darkwingorc:BAACLgAFFH8IAAIVAAMJzw09GQCiAAAVAAMJzw09GQCiAAAuAAQKfxQAAhUACAmcHrALAOUCABUACAmcHrALAOUCAAAA.Daunt:BAAALgADCgkJCQABLgAECggJMAATACIRAA==.',
De='Decypher:BAABLgAECn8mAAIeAAgJpBO+DAC2AQAeAAgJpBO+DAC2AQAAAA==.Deebz:BAAALgAECgUJDAAAAA==.Deliverance:BAAALgAFFAQJCAABLgAFFAMJCQAfAAAAAQ==.Demonablaze:BAAALgAECgIJAwAAAA==.Dentik:BAABLgAECn8sAAMDAAkJYA8DNQCkAQADAAkJYA8DNQCkAQAQAAIJ4gKlWAAnAAAAAA==.Denuma:BAAALgAECgYJBgAAAA==.Devaren:BAAALgADCgIJAgAAAA==.Devilina:BAAALgAECgQJCgAAAA==.',
Dh='Dheri:BAAALgAECgQJCQABLgAECggJJgAeAKQTAA==.',
Di='Diamair:BAABLgAECn88AAMgAAkJTRlCAwDQAQAEAAkJlBOBPAANAgAgAAgJGBhCAwDQAQAAAA==.Diamones:BAAALgAECgMJAwAAAA==.Dixiee:BAAALgAECgYJCQAAAA==.',
Dn='Dnegelpal:BAABLgAECn8mAAIKAAkJUxAdTwC8AQAKAAkJUxAdTwC8AQAAAA==.',
Do='Docbison:BAAALgADCgMJAwABLgAECgYJBgAfAAAAAA==.Dodgecharger:BAAALgAECgYJDwAAAA==.Dornix:BAABLgAECn8pAAIMAAgJZyB3JAAzAgAMAAgJZyB3JAAzAgAAAA==.',
Dr='Draavin:BAAALgADCgcJDQAAAA==.Dracsunemiku:BAAALgAECggJCwABLgAECgkJIgAYALIbAA==.Dragerin:BAAALgAECgcJDAAAAA==.Dragonfood:BAAALgAECgYJEgAAAA==.Drakilu:BAABLgAECn82AAIVAAkJAR7tDwCqAgAVAAkJAR7tDwCqAgAAAA==.Drasic:BAACLgAFFH8JAAIDAAMJMRSBLwDSAAADAAMJMRSBLwDSAAAuAAQKfzoAAgMACAk/I6sHACIDAAMACAk/I6sHACIDAAAA.Dreddscott:BAAALgAECgQJBAABLgAECgkJLwAhAMQeAA==.Drophin:BAAALgADCgkJGwAAAA==.Drunken:BAABLgAECn8xAAIiAAgJ3R8bCgB1AgAiAAgJ3R8bCgB1AgAAAA==.Druphin:BAAALgADCgYJEgAAAA==.',
Du='Durward:BAABLgAECn84AAQYAAkJaSHsCgD4AgAYAAkJaSHsCgD4AgAZAAQJ/w4wMACwAAAaAAEJ6hFDKwAvAAAAAA==.Duvo:BAABLgAECn8XAAIVAAYJtx1PVQB1AQAVAAYJtx1PVQB1AQAAAA==.',
Dw='Dwarfo:BAAALgAECgYJCQAAAA==.Dwarfoson:BAAALgADCgkJEAAAAA==.',
Dy='Dynastyvalor:BAAALgADCgEJAQAAAA==.Dynastÿ:BAAALgAECgMJAwAAAA==.Dynomite:BAABLgAECn8aAAMQAAYJ6AYINgCFAAAQAAYJ6AYINgCFAAACAAQJpQBEdgAyAAAAAA==.',
['Dé']='Détank:BAABLgAECn8cAAIaAAgJlR6GAgCPAgAaAAgJlR6GAgCPAgAAAA==.',
Ei='Eiene:BAAALgAECgYJDAAAAA==.',
El='Elbarrio:BAABLgAECn8bAAIMAAkJIQKIswDFAAAMAAkJIQKIswDFAAAAAA==.Elemental:BAACLgAFFH8KAAMTAAQJcgqQHgADAQATAAQJcgqQHgADAQASAAEJKAR7YgA9AAAuAAQKfywAAxMACQmxGagOALoCABMACQmxGagOALoCABIAAwm4CRmOAF4AAAEuAAUUBQkPAAIA3goA.Eleussen:BAAALgAECgMJAwAAAA==.Ellohir:BAAALgAECgEJAQAAAA==.Ellomortis:BAAALgAECgMJBAAAAA==.Elloseth:BAABLgAECn8iAAIJAAYJ7hvOJAB7AQAJAAYJ7hvOJAB7AQAAAA==.Elmorin:BAAALgAECgcJCwAAAA==.',
Em='Emeraldshdw:BAAALgADCgcJBwAAAA==.',
En='Enclaves:BAAALgADCgkJCgAAAA==.',
Eo='Eolon:BAAALgAECgYJDwAAAA==.',
Ep='Epica:BAABLgAECn8oAAIEAAcJ+xRKegBnAQAEAAcJ+xRKegBnAQAAAA==.',
Er='Eragonhawk:BAABLgAECn8jAAIKAAgJ/xf/PwDoAQAKAAgJ/xf/PwDoAQAAAA==.Erelynn:BAAALgAECgQJBAABLgAECgkJJQAIAMkRAA==.Eroldan:BAABLgAECn8ZAAMSAAcJIyDPFwBeAgASAAcJIyDPFwBeAgATAAEJKRKjiQAvAAAAAA==.Erovianoria:BAACLgAFFH8KAAIVAAMJygUZTQDFAAAVAAMJygUZTQDFAAAuAAQKfykAAhUACQm/Fv8WAIACABUACQm/Fv8WAIACAAAA.Eruadan:BAAALgADCggJEQAAAA==.Eräthis:BAAALgAECgMJAwAAAA==.',
Es='Essital:BAAALgADCgYJBwAAAA==.Essun:BAABLgAECn8qAAIXAAgJdyJ1BgClAgAXAAgJdyJ1BgClAgAAAA==.',
Eu='Euthanize:BAAALgADCgQJBwAAAA==.',
Ev='Evanthe:BAABLgAECn8sAAISAAkJShcZGABdAgASAAkJShcZGABdAgAAAA==.Evelyiss:BAAALgADCgEJAQAAAA==.',
Fa='Fatalfury:BAABLgAECn8fAAMKAAgJQhe/TQDAAQAKAAgJQhe/TQDAAQANAAMJbgg0YQB+AAAAAA==.Fauxstorm:BAAALgAECgUJEQAAAA==.',
Fi='Finngan:BAABLgAECn8qAAIcAAkJ/AtlDABKAQAcAAkJ/AtlDABKAQAAAA==.Fireina:BAAALgAECgYJEQAAAA==.',
Fo='Forestkin:BAAALgAECgYJCwABLgAECgYJHAAUAN8lAA==.Fossilis:BAABLgAECn8YAAMjAAcJHgV+EAD8AAAjAAcJAQV+EAD8AAAhAAUJ2wIUTwCzAAAAAA==.',
Fr='Frozenthunda:BAAALgAECgQJCgAAAA==.',
Fu='Furna:BAABLgAECn8oAAIPAAYJ4hQfJAB+AQAPAAYJ4hQfJAB+AQAAAA==.',
Fy='Fyahka:BAAALgADCgQJBAAAAA==.Fyon:BAAALgAECgYJBwAAAA==.',
['Fá']='Fáeryn:BAAALgAECgYJBgAAAA==.',
Ga='Gabrael:BAACLgAFFH8HAAIFAAQJ1AflHwAHAQAFAAQJ1AflHwAHAQAuAAQKfzYAAgUACQn4F8MRAEUCAAUACQn4F8MRAEUCAAAA.Galileia:BAAALgADCgMJBAAAAA==.',
Gh='Ghorienge:BAAALgAECgYJDwAAAA==.Ghostcat:BAAALgAECgIJAgAAAA==.',
Gi='Gilox:BAABLgAECn8bAAIjAAgJGBDTCACWAQAjAAgJGBDTCACWAQAAAA==.',
Gn='Gndmexia:BAAALgAECgIJBwAAAA==.Gneiss:BAAALgAECgYJDwAAAA==.',
Go='Goliat:BAAALgAECgMJAwAAAA==.Gothgirldemi:BAABLgAECn8iAAIDAAkJiCDTBQBCAwADAAkJiCDTBQBCAwAAAA==.',
Gr='Graymon:BAAALgAECgUJEQAAAA==.Greebo:BAAALgAECgUJEQAAAA==.Griknor:BAABLgAECn8fAAMGAAYJRgU/IgDaAAAGAAYJRgU/IgDaAAAFAAQJBgPmbAB1AAAAAA==.Grimniel:BAAALgAECgIJAwAAAA==.',
Gu='Guatalupe:BAAALgAECgMJAwAAAA==.Guilherme:BAAALgAECgQJBQAAAA==.',
Gw='Gwenyver:BAABLgAECn8ZAAIKAAcJdgLe6wCmAAAKAAcJdgLe6wCmAAAAAA==.',
Ha='Hadoukendk:BAAALgAECggJEgAAAA==.Hafaken:BAAALgAECgEJAQAAAA==.Hallien:BAAALgADCgEJAQAAAA==.Hamord:BAABLgAECn8bAAIdAAcJchDYHgDuAAAdAAcJchDYHgDuAAAAAA==.Harlequìn:BAAALgAECgQJCAAAAA==.Harliquette:BAAALgAECgQJBAAAAA==.Harliqynn:BAABLgAECn8cAAIVAAkJ4BrtIABAAgAVAAkJ4BrtIABAAgAAAA==.Harlock:BAABLgAECn8jAAIhAAkJXxxRDAA7AgAhAAkJXxxRDAA7AgAAAA==.Hayreddin:BAAALgADCgUJBQAAAA==.Hazelnuts:BAAALgAECgIJAQAAAA==.',
He='Heartkiller:BAAALgAECgQJBAABLgAECgkJKAAEAPsUAA==.Helleye:BAAALgAECgcJEQAAAA==.',
Hi='Hiten:BAABLgAECn82AAQhAAkJrRnqCgBSAgAhAAkJpRnqCgBSAgAjAAUJRBWIDQBEAQAkAAEJjwheHgAsAAAAAA==.',
Ho='Hopedaimond:BAABLgAECn8mAAITAAkJ3A2OKQB3AQATAAkJ3A2OKQB3AQAAAA==.',
Hu='Huntertattoo:BAABLgAECn82AAMVAAkJAA4HPgC+AQAVAAkJAA4HPgC+AQAWAAMJeAKFTQBFAAAAAA==.',
Hy='Hypro:BAABLgAECn8xAAISAAkJeyU7AADXAwASAAkJeyU7AADXAwAAAA==.',
['Há']='Háides:BAAALgADCgIJAgAAAA==.',
['Hí']='Hírra:BAABLgAECn8ZAAIdAAcJByOXBAC6AgAdAAcJByOXBAC6AgAAAA==.',
Ic='Icynips:BAAALgADCgkJEwAAAA==.',
Ie='Iepa:BAAALgAECgEJAQAAAA==.',
Il='Ilthad:BAABLgAECn8XAAIXAAYJihK1JAAXAQAXAAYJihK1JAAXAQAAAA==.',
Im='Imperio:BAAALgADCgYJBgAAAA==.Imshalar:BAAALgAECggJEAAAAA==.',
In='Inconcvabull:BAAALgAECggJDwAAAA==.Inferious:BAAALgAECgUJDwABLgAECgcJFAAYAB8XAA==.Infurryating:BAAALgAECgcJBwAAAA==.Inistus:BAAALgADCgUJBQAAAA==.',
Ir='Iralis:BAAALgAECgYJDQAAAA==.',
Is='Ischadè:BAAALgAECgEJAQAAAA==.Iskuros:BAAALgADCgIJAgAAAA==.',
It='Ithlarin:BAAALgAECgQJBwAAAA==.Itsirk:BAABLgAECn8rAAINAAgJdxqVFwAlAgANAAgJdxqVFwAlAgAAAA==.',
Iz='Izyebelle:BAABLgAECn8hAAIJAAcJiwHhVwB4AAAJAAcJiwHhVwB4AAAAAA==.',
Ja='Jadevine:BAAALgADCgIJAgAAAA==.Jadynara:BAAALgAECgEJAQAAAA==.',
Je='Jeloi:BAABLgAECn8pAAIdAAgJtSNEAwC7AgAdAAgJtSNEAwC7AgAAAA==.Jerichorye:BAAALgADCgEJAQAAAA==.',
Jh='Jherak:BAAALgADCgEJAQAAAA==.',
Ji='Jiayou:BAAALgADCgEJAQAAAA==.Jimmydin:BAACLgAFFH8HAAIKAAQJahFvLgAyAQAKAAQJahFvLgAyAQAuAAQKfzYAAw0ACQklGbQeACICAA0ACQklGbQeACICAAoACAkeF54/AOkBAAAA.Jix:BAABLgAECn8YAAMcAAgJkhi9DgDeAQAcAAYJtxy9DgDeAQAMAAQJSAxGrQD+AAAAAA==.',
Jo='Johnný:BAABLgAECn8xAAQHAAkJhhISPAC2AQAHAAkJ5RESPAC2AQAUAAMJyxWlHgCSAAAXAAEJYw4QbwA2AAAAAA==.',
Ju='Juego:BAAALgADCgEJAQAAAA==.Julkan:BAAALgAECgQJBgAAAA==.Junhoong:BAABLgAECn80AAIKAAgJtxI8WwCcAQAKAAgJtxI8WwCcAQAAAA==.',
Jy='Jynnysa:BAAALgAECgYJCQABLgAECgYJIgAdABIgAA==.',
Ka='Kabira:BAAALgADCgQJBAAAAA==.Kai:BAABLgAECn8WAAIGAAcJiBS1FwBzAQAGAAcJiBS1FwBzAQAAAA==.Kairoll:BAABLgAECn8mAAIIAAkJuBXNEgAgAgAIAAkJuBXNEgAgAgAAAA==.Kaizo:BAAALgADCgYJBgAAAA==.Kannah:BAAALgAECgYJCwABLgAECggJFgANAH8ZAA==.Karaa:BAABLgAECn8iAAIRAAcJgwX8VAC+AAARAAcJgwX8VAC+AAAAAA==.Kariena:BAABLgAECn8eAAIVAAcJCx0DOQDPAQAVAAcJCx0DOQDPAQAAAA==.Katesluage:BAABLgAECn80AAIEAAkJSxoaLQBHAgAEAAkJSxoaLQBHAgAAAA==.Kaylasluage:BAAALgADCgEJAQABLgAECgkJNAAEAEsaAA==.',
Ke='Keeya:BAABLgAECn8qAAIYAAcJSBLkeQBKAQAYAAcJSBLkeQBKAQAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kelkan:BAAALgAECgEJAQAAAA==.Kendari:BAABLgAECn8XAAIZAAYJ/QQuNwCLAAAZAAYJ/QQuNwCLAAAAAA==.Kernasas:BAABLgAECn8sAAIcAAcJwxUmCQCIAQAcAAcJwxUmCQCIAQAAAA==.Keslynn:BAAALgAECgIJAwABLgAECgcJHgAVAAsdAA==.Ketrani:BAAALgAECgEJAgABLgAECgcJHgAVAAsdAA==.',
Kh='Khiari:BAAALgADCgkJKAABLgAECgYJGwAKANcRAA==.',
Ki='Kildarin:BAAALgAECgcJCwAAAA==.Kilrith:BAAALgAECgYJDwAAAA==.Kindrok:BAAALgADCgcJCAABLgAECggJKQAMAGcgAA==.Kirtiao:BAAALgAECgEJAgABLgAECgcJHgAVAAsdAA==.Kitalidie:BAAALgAECgIJAgABLgAECgcJHgAVAAsdAA==.Kizaraan:BAABLgAECn8aAAIlAAcJxgNMHwDVAAAlAAcJxgNMHwDVAAAAAA==.',
Kl='Kleyntamar:BAAALgAECgUJCQAAAA==.',
Kn='Knyghtly:BAAALgAECgkJAwAAAA==.',
Ko='Konstantien:BAAALgAECgYJBgAAAA==.',
Kr='Kritter:BAAALgAECgYJDwAAAA==.Krohm:BAABLgAECn8lAAMKAAkJaSAoEwD6AgAKAAkJaSAoEwD6AgAdAAEJ8hh2PABFAAAAAA==.Krostana:BAAALgADCgEJAQAAAA==.Krshna:BAAALgAECgUJCQAAAA==.',
Ku='Kumachikara:BAAALgAECgYJDQAAAA==.Kungfuey:BAAALgADCgcJBwAAAA==.Kupau:BAAALgAECgQJBAAAAA==.',
Ky='Kynnigos:BAAALgADCgYJCwAAAA==.',
La='Lallita:BAAALgAECgUJDgAAAA==.Landah:BAAALgAECgIJAgAAAA==.Lanss:BAABLgAECn9CAAILAAkJ+CO8AQAnAwALAAkJ+CO8AQAnAwAAAA==.Larachel:BAAALgAECgcJDgAAAA==.Laur:BAABLgAECn8uAAIJAAkJaxONGADdAQAJAAkJaxONGADdAQAAAA==.',
Le='Leathergimp:BAAALgAECgYJCwAAAA==.Leipäjuusto:BAABLgAECn8jAAIKAAkJUBzTIABkAgAKAAkJUBzTIABkAgAAAA==.Lextalionant:BAAALgAECgIJAgAAAA==.',
Li='Liartes:BAAALgAECgUJEQAAAA==.Liderela:BAAALgADCgMJAwAAAA==.Lightwirly:BAAALgADCgIJAwAAAA==.Lilipo:BAABLgAECn8fAAIbAAcJTAc5PADiAAAbAAcJTAc5PADiAAAAAA==.Liltara:BAABLgAECn8gAAIEAAcJHgLU4QC0AAAEAAcJHgLU4QC0AAAAAA==.Littlefawn:BAAALgADCgUJBwAAAA==.',
Lj='Ljos:BAAALgAECgEJAQAAAA==.',
Ll='Llanz:BAAALgADCgkJKgAAAA==.',
Lo='Loarddruid:BAAALgADCgUJBQAAAA==.Lockybalboa:BAAALgAECgEJAQAAAA==.Logoth:BAACLgAFFH8FAAIMAAMJdwO1gACTAAAMAAMJdwO1gACTAAAuAAQKfy0AAgwACAm+FElJAKgBAAwACAm+FElJAKgBAAAA.Lokdan:BAAALgAECgQJBwAAAA==.Loppy:BAAALgAECgIJAgAAAA==.Loula:BAABLgAECn8mAAIEAAgJSAP4tAD+AAAEAAgJSAP4tAD+AAAAAA==.Lowryder:BAABLgAECn8eAAMhAAgJFxUHFwC8AQAhAAgJFxUHFwC8AQAjAAEJmwZiIAAxAAAAAA==.Loxes:BAAALgAECgcJDQABLgAECgYJCwAfAAAAAA==.Loxy:BAAALgAECgUJDAAAAA==.',
Lu='Lukam:BAAALgAECgUJEAAAAA==.Lunaellana:BAAALgADCgcJFwAAAA==.Lus:BAABLgAECn8UAAMMAAYJsRfzegBmAQAMAAYJsRfzegBmAQAcAAIJuggxUwB0AAAAAA==.',
Ly='Lycidas:BAAALgADCgcJBwAAAA==.Lycopersicum:BAABLgAECn8UAAUDAAYJWhp5LwDCAQADAAYJWhp5LwDCAQAQAAQJPAyvOQB0AAAeAAIJUwSBOABBAAACAAIJTwFsjgAOAAABLgAFFAMJCAADAEcHAA==.',
['Lì']='Lìlguy:BAAALgAECgIJAgAAAA==.',
Ma='Magicfang:BAAALgAECgYJCgAAAA==.Maiku:BAABLgAECn8zAAIMAAkJWBRDMAD/AQAMAAkJWBRDMAD/AQAAAA==.Makado:BAABLgAECn8gAAQcAAgJ2ghnGgCyAAAMAAUJ4AU3rQDQAAAmAAUJvQcFGgC0AAAcAAcJQAdnGgCyAAAAAA==.Makaris:BAAALgADCgMJAwAAAA==.Maknanimus:BAAALgADCgEJAQAAAA==.Maknygos:BAAALgADCgcJBwAAAA==.Makoroth:BAABLgAECn8aAAIMAAYJXxMmcgBAAQAMAAYJXxMmcgBAAQAAAA==.Matriarch:BAAALgAECgcJDgAAAA==.Matthiás:BAAALgADCgMJAwAAAA==.Matua:BAAALgAECgEJAQAAAA==.Maycee:BAAALgAECgYJBgAAAA==.',
Mc='Mcnaugh:BAABLgAECn8bAAMZAAcJIw9WJQD6AAAZAAcJfgxWJQD6AAAYAAQJKRRnwgDPAAAAAA==.Mcsaltface:BAABLgAECn8XAAIKAAYJzhojcwBoAQAKAAYJzhojcwBoAQAAAA==.',
Me='Meddic:BAAALgADCggJDwAAAA==.Menaras:BAACLgAFFH8KAAMSAAMJfw77PgC1AAASAAMJfw77PgC1AAATAAIJZgI9OABwAAAuAAQKfywAAxMACQkmHTsSAJECABMACQkmHTsSAJECABIACAmOF2U+AIIBAAAA.Menarot:BAAALgAFFAMJAwABLgAFFAMJCgASAH8OAA==.Mendais:BAAALgADCgYJCgAAAA==.Metgot:BAAALgADCgYJBgAAAA==.Meztlitotol:BAAALgAECgYJCgABLgAFFAQJCAALABYSAA==.',
Mi='Mikeydluffy:BAABLgAECn8aAAIbAAkJVhULEQAZAgAbAAkJVhULEQAZAgAAAA==.Mirosmundo:BAACLgAFFH8PAAIiAAQJdxikFQBBAQAiAAQJdxikFQBBAQAuAAQKfy0AAiIACQknH9oIAPkCACIACQknH9oIAPkCAAAA.Mistfit:BAABLgAECn8WAAIRAAcJSBOlLgBxAQARAAcJSBOlLgBxAQAAAA==.Miyagi:BAAALgAECgYJEAAAAA==.Miyu:BAABLgAECn8sAAMIAAgJvxMFIwCIAQAIAAgJvxMFIwCIAQAJAAUJixZWMwAjAQAAAA==.',
Mo='Mod:BAABLgAECn8rAAMTAAkJlSQUCQCpAgATAAgJSSQUCQCpAgASAAYJihOrUwA3AQAAAA==.Modaka:BAAALgAECgMJBQAAAA==.Moelly:BAAALgADCgkJCQAAAA==.Moffizi:BAAALgADCgcJBwAAAA==.Moggatorash:BAAALgAECgcJEgAAAA==.Mogtham:BAABLgAECn82AAIQAAkJAReCCQAXAgAQAAkJAReCCQAXAgAAAA==.Moirenna:BAAALgAECgEJAQAAAA==.Moisticklez:BAAALgAECgUJCwAAAA==.Monkeyspaul:BAABLgAECn8cAAIbAAgJQhvDFABHAgAbAAgJQhvDFABHAgABLgAECgkJKwALANgcAA==.Moonfall:BAABLgAECn8VAAIHAAYJmw1shADuAAAHAAYJmw1shADuAAAAAA==.Moonpig:BAAALgAECgMJAwAAAA==.Moosader:BAABLgAECn8mAAMKAAcJXhghWwCdAQAKAAcJXhghWwCdAQANAAYJcQiVVwAdAQAAAA==.Morellea:BAACLgAFFH8LAAIHAAQJ1QuyOgAOAQAHAAQJ1QuyOgAOAQAuAAQKfxYAAgcACQkSGVk2AB0CAAcACQkSGVk2AB0CAAAA.Morighann:BAABLgAECn8qAAIVAAkJvSNNDADMAgAVAAkJvSNNDADMAgAAAA==.Morkith:BAAALgAECggJEAAAAA==.Morphalot:BAAALgAFFAEJAQAAAA==.Mosrael:BAAALgAECgMJBAAAAA==.Mostank:BAAALgADCgMJAwAAAA==.Mousse:BAAALgADCgMJAwABLgAECgkJNwARANskAA==.Moñgoose:BAAALgADCgYJBgAAAA==.',
Mu='Muella:BAAALgAECgMJBQABLgAECggJMAATACIRAA==.',
My='Mylea:BAAALgAECgIJAgABLgAECgYJFQAHAJsNAA==.Mynkx:BAABLgAECn8bAAIKAAYJ1xGJnQAaAQAKAAYJ1xGJnQAaAQAAAA==.Mythyras:BAABLgAECn8iAAIdAAYJEiA4DgCxAQAdAAYJEiA4DgCxAQABLgAECgYJIgAdABIgAA==.',
Na='Nahaman:BAAALgAECgYJBgAAAA==.Nalo:BAAALgADCgMJAwAAAA==.Naxion:BAABLgAECn8fAAINAAYJJhQ6MQBqAQANAAYJJhQ6MQBqAQAAAA==.Naxon:BAAALgADCgYJBgAAAA==.',
Ne='Nechahira:BAACLgAFFH8PAAMCAAUJ3grqHQAIAQACAAQJ3grqHQAIAQADAAEJwAHcYQAyAAAuAAQKfxwABQMACAl0GxElACUCAAMACAl0GxElACUCAB4ABQl/F10aAP8AABAAAglaFaY4AHkAAAIAAgkXF6xmAFMAAAAA.Netherite:BAABLgAECn8aAAIgAAcJcQ8JBgA9AQAgAAcJcQ8JBgA9AQAAAA==.Nethim:BAAALgAECgEJAQABLgAECgcJGgAgAHEPAA==.Netre:BAAALgAECgcJEAAAAA==.Nezana:BAABLgAECn8sAAQlAAgJrRlyDADnAQAlAAcJ/RdyDADnAQABAAgJdxFLJQCSAQAnAAMJNggpNwBeAAAAAA==.',
Ni='Nianah:BAAALgADCggJEAAAAA==.Nighty:BAAALgADCgEJAQAAAA==.Nimirawr:BAABLgAECn8rAAIQAAkJyB2sBACbAgAQAAkJyB2sBACbAgAAAA==.Nisus:BAAALgADCgcJBwAAAA==.',
No='Nobunada:BAAALgAECgIJAgAAAA==.Nobunaga:BAAALgAECgIJAgAAAA==.Noranna:BAAALgAECgUJEQAAAA==.',
Ny='Nynsyn:BAAALgAECgIJAgABLgAECgYJIgAdABIgAA==.',
['Nø']='Nøva:BAAALgAECgEJAQABLgAFFAQJBQAYAAwQAA==.',
Oh='Ohthesemyboo:BAAALgAECgkJEwAAAA==.Ohwellz:BAABLgAECn8ZAAMTAAcJXBH8QgD3AAATAAcJXBH8QgD3AAASAAIJchVmiwB9AAABLgAECggJGgAKAD8aAA==.',
Op='Ophin:BAABLgAECn8bAAIYAAcJXBsdQADhAQAYAAcJXBsdQADhAQAAAA==.Ophiri:BAAALgADCgUJBQAAAA==.',
Or='Or:BAAALgAECgYJCwAAAA==.Orhail:BAAALgADCgEJAQAAAA==.Orlandu:BAAALgAECgYJDwAAAA==.Ornaxxi:BAAALgADCgYJAgAAAA==.',
Ov='Overheal:BAABLgAECn8ZAAIlAAgJsQxcEwBwAQAlAAgJsQxcEwBwAQAAAA==.',
Pa='Padhu:BAABLgAECn8ZAAIiAAgJ+AYFOAD/AAAiAAgJ+AYFOAD/AAAAAA==.Palox:BAAALgAECgYJBgAAAA==.Panamared:BAABLgAECn8vAAIhAAkJxB6WCAB5AgAhAAkJxB6WCAB5AgAAAA==.Parishealton:BAAALgAECgcJBwAAAA==.',
Pe='Peezee:BAAALgAECgEJAQAAAA==.Pennyfeather:BAABLgAECn83AAMIAAkJPxSWFQAAAgAIAAkJPxSWFQAAAgAPAAYJiA3fKwBIAQAAAA==.Pezza:BAABLgAECn8ZAAISAAgJzQ/KPgCBAQASAAgJzQ/KPgCBAQAAAA==.',
Ph='Phantomlord:BAAALgAECgcJCgABLgAECgkJKAAEAPsUAA==.Phaze:BAABLgAECn8aAAIWAAkJ0BefEAAPAgAWAAkJ0BefEAAPAgAAAA==.Phia:BAABLgAECn8eAAMVAAkJ/x4ZEgCnAgAVAAkJ/x4ZEgCnAgAWAAEJEhWBLABCAAAAAA==.Pholcus:BAAALgAECgUJEAAAAA==.',
Pr='Prothagon:BAABLgAECn8rAAMlAAkJsxecBgB3AgAlAAkJsxecBgB3AgABAAIJQBY2ZgByAAAAAA==.',
Ps='Psylix:BAABLgAECn8wAAMXAAkJExhmDAApAgAXAAkJExhmDAApAgAHAAEJZwvX7QAyAAAAAA==.',
Pu='Purrá:BAAALgADCgMJAgAAAA==.',
Ra='Raeburne:BAAALgAECgUJEQAAAA==.Raevennlumis:BAABLgAECn8cAAIKAAkJUgaZhABFAQAKAAkJUgaZhABFAQAAAA==.Rahkhard:BAAALgAECgcJCgAAAA==.Randrius:BAAALgADCgYJBgAAAA==.Ransha:BAAALgAECgYJDAABLgAECgkJLgAUAEMSAA==.Rascdit:BAAALgAECgcJDgAAAA==.',
Re='Redwood:BAAALgAECgYJDgAAAA==.Refurbished:BAAALgAECgQJCQAAAA==.Renwic:BAAALgAECgMJBgAAAA==.Reylani:BAEALgAECgcJBwABLgAECgkJKQAGAA8bAA==.',
Rh='Rheingard:BAAALgADCgUJCAAAAA==.Rhemiroll:BAAALgAECgcJDgAAAA==.Rhintalle:BAEALgADCgUJBwABLgAECgQJCwAfAAAAAA==.',
Ri='Rickroll:BAAALgAECgMJBQAAAA==.Riepa:BAAALgADCgEJAQAAAA==.Risotto:BAABLgAECn83AAMRAAkJ2ySEAQCuAwARAAkJ2ySEAQCuAwAbAAEJkBekdwA9AAAAAA==.',
Ro='Rocketbilly:BAAALgADCgEJAQAAAA==.Rocksand:BAAALgAECgUJBgAAAA==.',
Ru='Ruaic:BAAALgAECgEJAQAAAA==.Rumblelight:BAAALgAECgYJBgAAAA==.Ruska:BAAALgAECgEJAQAAAA==.Rusku:BAAALgADCgcJBwAAAA==.',
Ry='Rylanus:BAAALgADCgEJAgAAAA==.',
Sa='Sabbatini:BAAALgAECgcJDwAAAA==.Sagehawk:BAAALgAECgYJEwAAAA==.Saitamà:BAAALgADCgIJAgAAAA==.Sali:BAAALgAECgEJAgAAAA==.Salmuna:BAAALgADCgEJAQAAAA==.Saltywoyer:BAAALgADCgIJAQAAAA==.Samyueru:BAABLgAECn8WAAIbAAgJJhSCHQCZAQAbAAgJJhSCHQCZAQAAAA==.Sandpaws:BAAALgADCgMJAwAAAA==.Sarcastic:BAABLgAECn8xAAIEAAgJPh6AJABuAgAEAAgJPh6AJABuAgAAAA==.Sarova:BAAALgAECgYJCwAAAA==.Satori:BAAALgAECgUJEQAAAA==.Saxet:BAAALgAECgYJCwAAAA==.Saxie:BAAALgADCgIJAgAAAA==.',
Sc='Schrie:BAAALgAECgEJAQAAAA==.Scone:BAAALgAECgYJBgAAAA==.',
Se='Sel:BAAALgADCgcJCgAAAA==.Seldeath:BAABLgAECn8lAAIYAAkJ2hpVIABlAgAYAAkJ2hpVIABlAgAAAA==.Sellidor:BAABLgAECn8ZAAIVAAgJlR5vHwBAAgAVAAgJlR5vHwBAAgAAAA==.Senamue:BAAALgADCggJCAAAAA==.Seriniyaa:BAAALgAECgYJEgAAAA==.',
Sh='Shaey:BAAALgAECgQJBAAAAA==.Sheara:BAAALgAECgkJAQAAAA==.Shinjiro:BAABLgAECn8oAAIKAAkJOwMfywDVAAAKAAkJOwMfywDVAAAAAA==.Shirito:BAABLgAECn8uAAIYAAkJGyb/AwBQAwAYAAkJGyb/AwBQAwAAAA==.Shiritodh:BAABLgAECn8eAAIHAAgJeCU0EwCMAgAHAAgJeCU0EwCMAgAAAA==.Shminglebolt:BAAALgADCgcJCwAAAA==.Shortnstout:BAABLgAECn8pAAMdAAkJKiN6AQAWAwAdAAkJKiN6AQAWAwAKAAYJsBY2egCGAQABLgAFFAMJBQALAJkRAA==.Shugo:BAAALgAECgYJBgAAAA==.Shyle:BAAALgAECgQJCQAAAA==.',
Si='Sienje:BAABLgAECn8kAAIKAAgJCxscLQAqAgAKAAgJCxscLQAqAgAAAA==.Simpleson:BAABLgAECn8mAAMMAAgJCBlVLwADAgAMAAgJCBlVLwADAgAcAAUJxQ7ONADjAAAAAA==.Simplic:BAAALgADCgEJAQAAAA==.Sinbàd:BAABLgAECn8bAAMXAAcJPhSuIQAvAQAXAAYJzBauIQAvAQAHAAYJ7woqkgDSAAAAAA==.Sindannie:BAAALgAECgEJAgAAAA==.',
Sk='Skie:BAAALgAECgcJDAABLgAECgkJAwAfAAAAAA==.Skribble:BAABLgAECn8TAAMPAAYJcQxQMgAhAQAPAAYJcQxQMgAhAQAJAAQJrwi4SQC5AAAAAA==.Skrreemo:BAAALgADCgYJCAAAAA==.',
Sl='Slackbear:BAABLgAECn8kAAIMAAgJlBQhPQDOAQAMAAgJlBQhPQDOAQAAAA==.Slaete:BAAALgAECgcJEgAAAA==.Slycen:BAAALgADCgcJBwAAAA==.',
So='Sokey:BAAALgAECgYJDAAAAA==.Solemn:BAABLgAECn8UAAIJAAgJiBLpHgCnAQAJAAgJiBLpHgCnAQABLgAECggJGQAVAJUeAA==.Soleva:BAAALgADCgkJDwAAAA==.Solrana:BAABLgAECn8VAAMYAAcJKAOnyADFAAAYAAcJ9gKnyADFAAAaAAEJOAPjMAAeAAAAAA==.Solyndrisa:BAAALgAECgEJAQAAAA==.Songmistress:BAAALgAECgQJBwAAAA==.Sorren:BAAALgADCgkJLQAAAA==.Sorrows:BAABLgAECn8UAAIcAAcJrgpHEgD2AAAcAAcJrgpHEgD2AAAAAA==.Sosukesagara:BAAALgAECgQJBwAAAA==.Sotta:BAAALgAECgMJBQAAAA==.Soulbled:BAABLgAECn8mAAIUAAkJmQ40DQCEAQAUAAkJmQ40DQCEAQAAAA==.',
Sp='Spire:BAAALgADCgUJBQAAAA==.',
St='Stardrive:BAAALgAECgYJEQAAAA==.Stravasza:BAAALgADCgMJAwAAAA==.',
Su='Sunasha:BAAALgAECgYJEgAAAA==.Superbautumn:BAABLgAECn8ZAAIKAAkJox/kHwBpAgAKAAkJox/kHwBpAgAAAA==.',
Sy='Sylo:BAABLgAECn8gAAIYAAgJTRSZVQCgAQAYAAgJTRSZVQCgAQAAAA==.Synalaid:BAAALgAECgQJBQAAAA==.Synnyca:BAAALgAECgMJBAABLgAECgYJIgAdABIgAA==.Syrezi:BAAALgADCgEJAQAAAA==.Syrup:BAAALgAECgcJEgAAAA==.',
['Só']='Sóta:BAAALgAECgUJCAAAAA==.',
Ta='Taat:BAAALgADCgYJBgAAAA==.Tachyon:BAABLgAECn8iAAIYAAkJsht+KACYAgAYAAkJsht+KACYAgAAAA==.Tadoshi:BAAALgADCgEJAQAAAA==.Taeonaki:BAAALgAECgMJAwAAAA==.Tagnaras:BAAALgAECgYJBgAAAA==.Tahlang:BAAALgAECgEJBAAAAA==.Tali:BAABLgAECn8aAAMVAAcJxQ0dZQBMAQAVAAcJxQ0dZQBMAQAoAAEJYwaFOgAiAAAAAA==.Taliasluage:BAAALgAECgQJBAABLgAECgkJNAAEAEsaAA==.Tamune:BAABLgAECn8VAAIjAAcJ1hyvBQD7AQAjAAcJ1hyvBQD7AQAAAA==.Tangle:BAAALgAECgcJDgABLgAECgkJAwAfAAAAAA==.Tanka:BAABLgAECn8tAAMGAAkJdSQZAQBKAwAGAAkJdSQZAQBKAwALAAIJfRI4OwByAAAAAA==.Tanuki:BAAALgADCgkJMwAAAA==.Tashlaraz:BAEALgAECgQJCwAAAA==.Tasi:BAAALgADCgEJAQAAAA==.Taurannosaur:BAAALgAECgEJAgAAAA==.Taveleron:BAAALgAECgUJCAAAAA==.Tavia:BAAALgADCgMJAwABLgAECggJJgAfAAAAAQ==.',
Te='Temporantus:BAAALgAECgYJEAAAAA==.Tenko:BAABLgAECn8WAAIEAAgJJw6haQCMAQAEAAgJJw6haQCMAQAAAA==.Texaspete:BAAALgADCgIJAgAAAA==.',
Th='Thaddeus:BAABLgAECn8jAAITAAkJURBnIgClAQATAAkJURBnIgClAQAAAA==.Thariane:BAAALgADCgcJDgABLgAECgEJAQAfAAAAAA==.Therm:BAACLgAFFH8KAAIKAAQJrybnCQDHAQAKAAQJrybnCQDHAQAuAAQKfzoAAgoACQlQJt8BAHEDAAoACQlQJt8BAHEDAAAA.Thoramier:BAABLgAECn8hAAQdAAkJ2xpPCgD4AQAdAAcJ8B1PCgD4AQAKAAYJ4ww7sgD6AAANAAIJGhR7YQB9AAAAAA==.Thorgrymm:BAAALgADCgUJBQAAAA==.Thruxton:BAAALgADCggJCAAAAA==.',
Ti='Timoonja:BAAALgAECgYJDAAAAA==.',
To='Tonatuih:BAABLgAECn80AAQHAAgJiR7hHgA+AgAHAAgJ7xvhHgA+AgAUAAYJlxaiDQB8AQAXAAgJnxmBKwDoAAAAAA==.Torg:BAAALgADCgYJBgAAAA==.',
Tr='Tree:BAAALgAFFAIJAgABLgAFFAcJGwALAMoiAA==.Treyen:BAAALgADCgkJCQAAAA==.Trezzia:BAABLgAECn8kAAImAAkJrxfhBAARAgAmAAkJrxfhBAARAgAAAA==.Triipod:BAAALgAECgEJAQAAAA==.Trinkat:BAAALgAECgUJEQAAAA==.Trojinn:BAAALgAECgUJCQAAAA==.',
Ty='Tybalt:BAAALgADCgMJAwAAAA==.Tylean:BAAALgAECgcJDQAAAA==.Tynk:BAAALgAECgQJBAAAAA==.Tynkarchanna:BAAALgADCgIJAgAAAA==.Tyreitherinn:BAAALgADCgUJCAAAAA==.',
Un='Unicornpup:BAAALgADCgMJAwAAAA==.Unìqùe:BAAALgADCgEJAQAAAA==.',
Va='Vaddix:BAAALgADCgcJDAAAAA==.Vadrozsa:BAAALgAECgYJEgAAAA==.Vaerethra:BAAALgADCgEJAQAAAA==.Valeran:BAAALgADCgIJAQAAAA==.Valkrissa:BAABLgAECn86AAIMAAkJaQW/cgA/AQAMAAkJaQW/cgA/AQAAAA==.Valsedor:BAAALgAECgYJBgAAAA==.Valwar:BAABLgAECn8kAAIFAAkJ8xkkHABsAgAFAAkJ8xkkHABsAgAAAA==.Vareyn:BAABLgAECn8XAAMdAAYJGQmQKgCaAAAKAAMJrAqz+wCcAAAdAAYJlAaQKgCaAAAAAA==.',
Ve='Vegeto:BAAALgAECgYJCQAAAA==.Velithice:BAAALgAECgUJCgAAAA==.Velle:BAAALgAECgUJBQABLgAFFAMJCgAVAMoFAA==.',
Vi='Vienge:BAAALgADCgEJAQAAAA==.',
Vo='Vonon:BAACLgAFFH8FAAIKAAUJvRhyHgBaAQAKAAUJvRhyHgBaAQAuAAQKfyIAAx0ACAmaHjoIACUCAB0ABwmoGzoIACUCAAoABglAIF5HAA0CAAAA.Vorth:BAABLgAECn8xAAMaAAgJrRr1BgDtAQAaAAgJWhn1BgDtAQAYAAcJiRTzowD+AAAAAA==.Vorükh:BAABLgAECn8XAAMjAAcJCApBDQBKAQAjAAYJaAtBDQBKAQAhAAYJsAO1NwC7AAABLgAECgkJGQAeADIRAA==.',
Vy='Vyrlana:BAACLgAFFH8HAAIlAAMJgASIHACfAAAlAAMJgASIHACfAAAuAAQKfxwAAyUACQncEsIMAOEBACUACQncEsIMAOEBAAEABgnRAuZIALQAAAAA.',
Wa='Waldir:BAABLgAECn82AAINAAkJsyT+AACpAwANAAkJsyT+AACpAwAAAA==.Waldstein:BAABLgAECn8pAAIYAAYJIRi5dABUAQAYAAYJIRi5dABUAQAAAA==.Wanted:BAABLgAECn8oAAQKAAcJuw+HhwBrAQAKAAcJYw+HhwBrAQANAAUJnBK1QAAXAQAdAAYJSwqUJwCsAAAAAA==.Watz:BAABLgAECn8wAAIVAAgJ6hNJPwC5AQAVAAgJ6hNJPwC5AQAAAA==.',
We='Wensa:BAAALgAECgYJCwAAAA==.',
Wr='Wratsoul:BAAALgAECgEJAQAAAA==.',
Xe='Xenophage:BAAALgADCgMJAwAAAA==.Xessala:BAAALgAECgMJBAAAAA==.',
Xh='Xheero:BAACLgAFFH8IAAIVAAMJZRAERADiAAAVAAMJZRAERADiAAAuAAQKfzUAAhUACAk6HSUeAEcCABUACAk6HSUeAEcCAAAA.Xheerom:BAAALgAECgcJEgAAAA==.',
Yu='Yulica:BAAALgAECgUJEQAAAA==.',
Za='Zaffy:BAABLgAECn8tAAIcAAkJWxInBgDRAQAcAAkJWxInBgDRAQAAAA==.Zaktoe:BAAALgADCgEJAQAAAA==.Zaktrix:BAAALgAECgEJAwAAAA==.Zaleron:BAAALgAECgYJBgAAAA==.Zanazath:BAABLgAECn8dAAMnAAcJ0Ro3EADZAQAnAAYJRhw3EADZAQABAAYJvhO6OwAUAQAAAA==.Zaruba:BAABLgAECn8wAAMTAAgJIhEoKAB/AQATAAgJIhEoKAB/AQASAAIJ5wCcmgA4AAAAAA==.Zatheon:BAABLgAECn8lAAIKAAgJXhkdQgDhAQAKAAgJXhkdQgDhAQAAAA==.Zatkyng:BAABLgAECn8cAAIbAAgJ5g+/MgAQAQAbAAgJ5g+/MgAQAQAAAA==.',
Ze='Zekos:BAAALgAECgUJCAAAAA==.',
Zi='Zidko:BAAALgADCgYJBgAAAA==.Zillver:BAABLgAECn8rAAILAAkJ2BxMCABTAgALAAkJ2BxMCABTAgAAAA==.Zimdalar:BAABLgAECn8XAAMiAAYJGRwAIgB6AQAiAAYJGRwAIgB6AQAbAAEJ2QwHgQAyAAAAAA==.',
Zo='Zolhs:BAAALgAECgEJAQAAAA==.Zolls:BAAALgAECgMJBgAAAA==.',
Zu='Zulre:BAABLgAECn9BAAIYAAkJfxc2KwAwAgAYAAkJfxc2KwAwAgAAAA==.',
['Ôv']='Ôverkill:BAAALgADCgkJJQABLgAECggJGQAlALEMAA==.',
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
