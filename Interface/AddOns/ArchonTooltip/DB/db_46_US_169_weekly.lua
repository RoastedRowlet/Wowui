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

local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Paladin-Holy','Priest-Discipline','Priest-Holy','Warrior-Fury','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Demonology','Unknown-Unknown','Warlock-Destruction','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Paladin-Protection','Druid-Restoration','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','Druid-Guardian','DeathKnight-Frost','Shaman-Enhancement','Mage-Fire','Mage-Arcane','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aairidari:BAABLgAECn8vAAIBAAgJLQ/3HgBdAQABAAgJLQ/3HgBdAQAAAA==.Aatrox:BAAALgAECgUJBQABLgAECgkJLgACACogAA==.',
Ab='Abruna:BAAALgAECgcJEwABLgAFFAYJGAADAMUYAA==.Abruno:BAACLgAFFH8YAAIDAAYJxRhEKQCVAQADAAYJxRhEKQCVAQAuAAQKfzAAAgMACQmDIgkQAEgDAAMACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAYJGAADAMUYAA==.',
Ad='Adrasteia:BAAALgADCgQJAQABLgAFFAMJDAADAGMRAA==.Adrians:BAABLgAECn8qAAIDAAkJuxblOAAeAgADAAkJuxblOAAeAgAAAA==.',
Ae='Aeown:BAABLgAECn8wAAMCAAgJ3Qn5jAA8AQACAAgJ3Qn5jAA8AQAEAAcJpQkoRQAUAQABLgAECgkJQgAFAGQUAA==.Aerdis:BAAALgAECgYJDQABLgAECggJFAAGAO0RAA==.',
Ag='Aggerwator:BAAALgAECgEJAwABLgAECggJGwAHACciAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAFFAIJAgABLgAFFAUJDwAIAIkYAA==.',
Al='Alahrî:BAACLgAFFH8GAAIJAAMJ2QVpHgCiAAAJAAMJ2QVpHgCiAAAuAAQKfzoABAkACQnzEOoWAOEBAAkACQnzEOoWAOEBAAoABgn+DFoMADoBAAsABwnqCvg5ACMBAAAA.Alandira:BAAALgAECgcJCAAAAA==.Alandrìas:BAABLgAECn8tAAIMAAkJnBSxBwDrAQAMAAkJnBSxBwDrAQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3WBQA9AwANAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn86AAIJAAkJRBahCABSAgAJAAkJRBahCABSAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAIDAAcJ2goLvwDtAAADAAcJ2goLvwDtAAAAAA==.Amethystia:BAAALgADCgYJBgAAAA==.Amirandis:BAAALgAECgYJCwAAAA==.Amuri:BAAALgAECgcJEQAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJCgAAAA==.Androonatorz:BAACLgAFFH8ZAAIEAAYJpRx0CwDaAQAEAAYJpRx0CwDaAQAuAAQKfy0AAwQACQkDJcABAI4DAAQACQkDJcABAI4DAAIABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAABLgAECn8UAAIOAAcJtgwWewA4AQAOAAcJtgwWewA4AQAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgABLgAECgcJAQAPAAAAAA==.Ardemus:BAABLgAECn8XAAMQAAYJIBLPFQDfAAAQAAYJIBLPFQDfAAAOAAEJYAAYNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAAALgAECgUJEQAAAA==.',
As='Ashborrn:BAAALgAECgcJEgAAAA==.Ashtar:BAABLgAECn8VAAIHAAkJvBIqKwCUAQAHAAkJvBIqKwCUAQAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgARAJEWAA==.',
Aw='Awake:BAAALgAECgEJAQAAAA==.Awaken:BAABLgAECn8bAAIDAAgJKCDPIACGAgADAAgJKCDPIACGAgAAAA==.Awoomonk:BAAALgAECgYJDwAAAA==.',
Ax='Axhure:BAAALgADCgYJBQAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMSAAYJgBZYMAB3AQASAAUJgBZYMAB3AQATAAEJAADuTwAAAAAuAAQKfyEAAhIACAlFIWEVAPsCABIACAlFIWEVAPsCAAAA.Balddrex:BAAALgADCgkJCQAAAA==.Balefire:BAABLgAECn8qAAMOAAkJTx1jGQCAAgAOAAkJTx1jGQCAAgAQAAIJ7RiDMwBCAAAAAA==.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgADCgcJDgABLgAECgkJKAAUAMEPAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECggJEQAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn88AAIDAAkJnSHeEQDbAgADAAkJnSHeEQDbAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAABLgAECn87AAINAAkJPR0PCgCeAgANAAkJPR0PCgCeAgAAAA==.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgAECgQJBAAAAA==.Bluewaffles:BAAALgAECgMJBQABLgAECgUJBwAPAAAAAA==.',
Bo='Borealzombie:BAAALgAECgMJAwAAAA==.Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8fAAIVAAcJvx3sAgA7AgAVAAcJvx3sAgA7AgAuAAQKfzAAAhUACQmDJCYDAB0DABUACQmDJCYDAB0DAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAWAFwZAA==.Brimara:BAAALgAFFAEJAgAAAA==.Brunomirror:BAAALgAECgkJDwABLgAFFAYJGAADAMUYAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQABLgAECggJFAAUAKgbAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJOQABACkSAA==.Bunsen:BAAALgAECgEJAQABLgAFFAQJDQAXAEodAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8eAAQYAAgJqB9mFACkAQAZAAcJTx0yEQC/AQAYAAgJih5mFACkAQAHAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMCAAYJehnygAB4AQACAAYJTRnygAB4AQAaAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYhd9KwCmAQANAAcJBBV9KwCmAQAbAAcJkRefRwBeAQAcAAIJ+gANOwAYAAAAAA==.Capz:BAACLgAFFH8uAAMYAAcJ4iApAABHAgAYAAcJHSApAABHAgAHAAUJqCJVBwB3AQAuAAQKfyYAAxgACQnRIzwDANsCABgACAkCJTwDANsCAAcACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJDAAAAA==.Cassius:BAAALgAECgEJAgAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECggJCwAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECgcJDgAAAA==.Ceezinator:BAAALgAECgQJBAAAAA==.Cefteldore:BAAALgADCgcJBwAAAA==.Celebrïmbor:BAAALgAECgMJAQAAAA==.',
Ch='Chair:BAAALgAECggJDQABLgAFFAMJDAADAGMRAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chokehold:BAAALgADCgEJAQAAAA==.Chopperr:BAAALgAECgQJBAAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8MAAIDAAMJYxH1bADnAAADAAMJYxH1bADnAAAuAAQKfzUAAgMACQlMIB0OAPUCAAMACQlMIB0OAPUCAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8PAAIQAAYJ7hABAwBzAQAQAAYJ7hABAwBzAQAuAAQKf0cAAhAACQlhJUQAAFYDABAACQlhJUQAAFYDAAAA.Clow:BAABLgAECn8bAAMHAAgJJyLMGgB1AgAHAAcJqiPMGgB1AgAYAAMJaB72KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQAAAA==.Coolcrush:BAABLgAECn8vAAMdAAkJMCVmAQBfAwAdAAkJMCVmAQBfAwAeAAYJ9iHEFwDYAQAAAA==.Corgnelius:BAAALgADCgYJDAAAAA==.Corven:BAACLgAFFH8WAAIOAAYJ2hW6HQCdAQAOAAYJ2hW6HQCdAQAuAAQKf04AAw4ACQlPI1EEAEIDAA4ACQlPI1EEAEIDABYAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwAAAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJBAABLgAECgkJJAARAN0XAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgkJEgAAAA==.Cryovox:BAAALgAECgQJBAAAAA==.Crôwley:BAAALgAECgQJCAAAAA==.',
Cu='Cumazzing:BAACLgAFFH8YAAICAAcJmyJ0AwByAgACAAcJmyJ0AwByAgAuAAQKfyoAAgIACQmJJrYCAK4DAAIACQmJJrYCAK4DAAAA.',
Da='Dadrin:BAAALgADCgkJJgAAAA==.Daedyxes:BAABLgAECn8vAAITAAgJ3Ri5DwDzAQATAAgJ3Ri5DwDzAQAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Daní:BAAALgAECgQJBQAAAA==.Darfretail:BAABLgAECn8eAAIHAAgJfRQdJQC4AQAHAAgJfRQdJQC4AQAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgQJBwAAAA==.Daygath:BAACLgAFFH8FAAIfAAIJmAp6OgB7AAAfAAIJmAp6OgB7AAAuAAQKfzEAAh8ACQlvFW0YAAcCAB8ACQlvFW0YAAcCAAAA.',
De='Deadlyiris:BAABLgAECn8nAAMYAAkJXCF1AwDgAgAYAAkJXCF1AwDgAgAHAAYJHxCZSgB7AQABLgAFFAQJDQAXAEodAA==.Deatharin:BAAALgAECgYJDQAAAA==.Decompose:BAAALgAECgEJAwAAAA==.Demonbulio:BAABLgAECn80AAIBAAkJxhUsDgAiAgABAAkJxhUsDgAiAgAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAWAFwZAA==.Demonskitten:BAABLgAECn8fAAIWAAkJXBlQBAA8AgAWAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgAECgEJAQAAAA==.Descendantt:BAAALgADCgIJAgAAAA==.Devilbullet:BAAALgADCgIJAwAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn84AAICAAkJtxRjUAC/AQACAAkJtxRjUAC/AQAAAA==.Dithehealer:BAABLgAECn8jAAMaAAkJYCDRAgDjAgAaAAkJYCDRAgDjAgACAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.Divinecandie:BAAALgAECgEJAQAAAA==.',
Dk='Dkdi:BAAALgAECggJCAAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAIDAAYJQR6ZcQDwAQADAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgkJIQAgAFwTAA==.Doogie:BAAALgAECgEJBAAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAPAAAAAA==.Dragømir:BAAALgAECgEJAQABLgAFFAMJAwAPAAAAAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8XAAMKAAYJoR7pAQB9AQAKAAUJBCHpAQB9AQALAAQJyx3TFwBlAQAuAAQKfysAAwoACQkmJQcBAF0DAAoACAmKJQcBAF0DAAsACQkqJOsCADUDAAAA.Drenamai:BAABLgAECn8hAAIUAAkJMBPyMQD+AQAUAAkJMBPyMQD+AQAAAA==.Drewetta:BAABLgAECn8zAAINAAkJCA8GIACuAQANAAkJCA8GIACuAQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.Durbana:BAAALgAECgUJCQAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgYJEgAAAA==.',
Ed='Edrocz:BAEALgAECgcJAQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8XAAICAAUJwSazDADHAQACAAUJwSazDADHAQAuAAQKfzoAAgIACQkGJq4BAMgDAAIACQkGJq4BAMgDAAEuAAUUBwkYAAIAmyIA.',
El='Elandin:BAAALgAECgYJCwAAAA==.Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8OAAIhAAYJZAffEwBNAQAhAAYJZAffEwBNAQAuAAQKfxYAAiEACQmBDSEmAMgBACEACQmBDSEmAMgBAAAA.Elvwyr:BAAALgAECgQJBAAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8NAAMfAAYJcRiVHQAPAQAfAAUJlReVHQAPAQAXAAEJ9whuZwBIAAAuAAQKfyAAAx8ACAkkHtkTAIACAB8ACAkkHtkTAIACABcABAk3Cat1ALoAAAAA.Emmy:BAABLgAECn8UAAIGAAYJxyAuKgCiAQAGAAYJxyAuKgCiAQAAAA==.Emogothbabe:BAAALgAECgUJBQAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAAALgAFFAIJBAABLgAFFAYJFwABAPMeAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQABAAQJqB30AQB7AQAIAAYJDRbUIgB0AQAMAAEJECe3AwB2AAAuAAQKfz8AAwEACQl9JXMAAOgDAAEACQl8JXMAAOgDAAgACQm1It0EACsDAAAA.Eneldenes:BAAALgAECgEJAQAAAA==.Enjoyer:BAAALgAECggJEgAAAA==.',
Er='Ereitherla:BAABLgAECn8tAAIUAAgJSAsEXgBzAQAUAAgJSAsEXgBzAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAECgYJDAAAAA==.',
Ev='Evanthe:BAAALgADCgEJAQAAAA==.',
Ex='Excalibear:BAABLgAECn8vAAIEAAkJPRa7IQDgAQAEAAkJPRa7IQDgAQABLgAFFAUJDwADAEQaAA==.',
Ey='Eydis:BAAALgADCgUJBQAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Farc:BAAALgAECgEJAQAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECgcJCgAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Felryno:BAAALgADCgQJBAAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fircey:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.Fistbroz:BAABLgAECn8eAAMiAAkJ8xXzDgDVAQAiAAkJFBTzDgDVAQAcAAcJDxVAEQCAAQABLgAFFAYJGwAdABcRAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAISAAkJPxhRPgD2AQASAAkJPxhRPgD2AQAAAA==.Fleredil:BAABLgAECn9IAAMVAAkJqSF5BAD6AgAVAAkJqSF5BAD6AgAGAAgJzRoXDwBeAgAAAA==.Flingernle:BAAALgAECgEJAwAAAA==.Floista:BAAALgAECggJDQAAAA==.Floistas:BAABLgAFFH8LAAIUAAMJWBO8SQDvAAAUAAMJWBO8SQDvAAAAAA==.',
Fo='Forepray:BAAALgAFFAEJAQABLgAFFAYJFwAHADkbAA==.Forger:BAABLgAECn8zAAIZAAkJmhaHDAANAgAZAAkJmhaHDAANAgAAAA==.Forsakey:BAAALgADCgEJAQABLgAFFAUJDwAbAMsaAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8UAAQSAAUJaiRNLwB5AQASAAQJaiRNLwB5AQAjAAQJLhfnCgAgAQATAAEJAADNTgAAAAAuAAQKfzYABBIACQkFJHAMADcDABIACQkDJHAMADcDACMACAlhIRMGAB8CABMAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAECgkJNQAOACshAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostycheeks:BAACLgAFFH8PAAISAAQJGxvCQwBJAQASAAQJGxvCQwBJAQAuAAQKfzUAAhIACAkKIy8bAJACABIACAkKIy8bAJACAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQIAAgJ0CILHABYAgAIAAgJlyILHABYAgAMAAIJqiMCJABiAAABAAIJTxhvWABAAAAAAA==.Future:BAAALgAECgYJDwABLgAFFAMJCAAWACwbAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaerlan:BAAALgAECgUJDAAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgAECgQJBAAAAA==.',
Gh='Ghettox:BAAALgAECgUJBQAAAA==.Ghostblades:BAACLgAFFH8YAAMSAAYJ5xaQKgCGAQASAAYJ5xaQKgCGAQAjAAEJAAADIwAAAAAuAAQKfykAAxIACQlOIYsVALMCABIACQlOIYsVALMCACMAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBAABLgAFFAcJGgAVALAaAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAABLgAFFH8FAAIXAAQJixDmKAAcAQAXAAQJixDmKAAcAQABLgAFFAUJDwADAEQaAA==.',
Gr='Gratata:BAAALgAECgMJBQABLgAECgkJJAARAN0XAA==.Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAAALgAECgkJEgABLgAECgkJQgACAOcfAA==.Grinny:BAABLgAECn9CAAMCAAkJ5x9fFgCmAgACAAkJ5x9fFgCmAgAEAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8aAAICAAgJdQqZmgAlAQACAAgJdQqZmgAlAQABLgAFFAQJDQAXAEodAA==.Havochunter:BAABLgAECn8UAAIUAAcJqBvEOQDgAQAUAAcJqBvEOQDgAQAAAA==.',
He='Heidegger:BAAALgAECgQJCAAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8hAAIgAAkJXBMjCQDQAQAgAAkJXBMjCQDQAQAAAA==.Heriod:BAAALgAECgEJAgAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgADCgcJDQAAAA==.Holywráth:BAAALgAECgUJCAAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECggJEQAAAA==.Hunterdh:BAABLgAECn8qAAIUAAcJownbgAAkAQAUAAcJownbgAAkAQAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8XAAIHAAYJORs6CQCcAQAHAAYJORs6CQCcAQAuAAQKfzAAAgcACQkIIdEJALMCAAcACQkIIdEJALMCAAAA.',
Ic='Icecandie:BAAALgAECgYJEgAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAYJFwAKAKEeAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJQgAFAGQUAA==.',
Im='Imistmypants:BAABLgAECn8kAAIRAAkJ3RfWEAB7AgARAAkJ3RfWEAB7AgAAAA==.',
In='Infinitevoid:BAAALgADCgUJCQAAAA==.Innervatez:BAABLgAFFH8YAAIbAAgJ4hwoAgDyAgAbAAgJ4hwoAgDyAgAAAA==.Inspectda:BAABLgAECn8VAAIOAAgJgwcadgBxAQAOAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAIJAAgJJBudCgAiAgAJAAgJJBudCgAiAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn80AAIDAAkJORbBPAAQAgADAAkJORbBPAAQAgAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn8/AAIDAAkJpCQMCAAqAwADAAkJpCQMCAAqAwAAAA==.Jarten:BAABLgAECn8kAAIjAAkJ8x8FAwCaAgAjAAkJ8x8FAwCaAgAAAA==.Jaylebate:BAABLgAECn87AAMSAAkJtyCzGgCTAgASAAkJeh+zGgCTAgATAAgJ4Rw3CwBEAgAAAA==.',
Je='Jerrenn:BAABLgAECn8eAAMCAAkJqBhjOAAIAgACAAgJ3hdjOAAIAgAEAAIJLwnBcABaAAAAAA==.Jesseatamer:BAABLgAECn8nAAIUAAkJeCUTAgBpAwAUAAkJeCUTAgBpAwAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jortak:BAAALgAECgcJCwABLgAECgkJOwASALcgAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.',
Ju='Judge:BAAALgAECgEJAQAAAA==.Justar:BAAALgADCgMJBQAAAA==.',
['Jë']='Jësus:BAAALgAECgcJBgAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAABLgAECn8UAAMgAAgJGhl3DgBcAQAUAAgJbBZbSACwAQAgAAcJ/BN3DgBcAQABLgAFFAMJBAAPAAAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAISAAkJVBamPgD1AQASAAkJVBamPgD1AQAAAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJAQABLgAECgEJAQAPAAAAAA==.Kastia:BAAALgAECgQJCAAAAA==.Katrynwel:BAABLgAECn8YAAIDAAgJTAt5fgBgAQADAAgJTAt5fgBgAQAAAA==.Katsumi:BAAALgADCgkJPAAAAA==.Kaylestia:BAAALgAECgkJCQAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCgUJDgAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.Khold:BAAALgAECggJDQAAAA==.',
Ki='Killalltoday:BAABLgAECn8+AAMXAAkJPhC/QQCKAQAXAAgJMxG/QQCKAQAkAAgJNg6YEACIAQAAAA==.Kilon:BAAALgAFFAEJAQAAAA==.Kirkk:BAAALgAECgEJAQAAAA==.Kivareous:BAAALgAFFAIJAgAAAA==.Kixarea:BAAALgADCgkJDQABLgAFFAIJAgAPAAAAAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAABLgAECn8ZAAITAAgJsxZfEgDNAQATAAgJsxZfEgDNAQAAAA==.Knixx:BAACLgAFFH8TAAMVAAQJYQkXGgADAQAVAAQJYQkXGgADAQAFAAQJXwgLMwCFAAAuAAQKf0IABBUACQnmGWoLAH4CABUACQnmGWoLAH4CAAYABwk6GGQbAAECAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIeAAkJUxHXIwB6AQAeAAkJUxHXIwB6AQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIRAAkJmhhEEgBrAgARAAkJmhhEEgBrAgAAAA==.Koyya:BAAALgAECgkJEwAAAA==.',
Ku='Kufoo:BAABLgAECn8+AAMHAAkJaCYLAQBtAwAHAAkJoSULAQBtAwAZAAgJwSWyAwDjAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJCAAWACwbAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8ZAAIMAAkJVhTxBgACAgAMAAkJVhTxBgACAgAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
['Ké']='Kéndra:BAAALgAECgMJAwAAAA==.',
La='Ladiable:BAAALgAECgYJCQABLgAFFAYJEQAUALcdAA==.Laggyboi:BAAALgAECgUJBQAAAA==.Lansseax:BAAALgAECgcJBwAAAA==.Lascerette:BAAALgAECgQJBAAAAA==.Law:BAAALgADCgMJAwAAAA==.Layez:BAAALgADCgUJBQABLgAFFAIJAwAPAAAAAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Leo:BAAALgAECgEJAQAAAA==.Lethe:BAAALgAECgcJCAABLgAFFAYJDgAhAGQHAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAAUAAAbAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgIJBAAPAAAAAA==.Lilyröse:BAAALgAECgIJBAAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn8xAAIOAAkJFRoqKgAkAgAOAAkJFRoqKgAkAgAAAA==.Lohmi:BAAALgAECgYJCwAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAACLgAFFH8FAAINAAMJ3gFKNwBuAAANAAMJ3gFKNwBuAAAuAAQKfyMAAg0ACQljCNotAFABAA0ACQljCNotAFABAAAA.',
Lu='Luania:BAAALgAECgQJCgAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lurtz:BAAALgAECgYJEQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgEJAQAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.Lyzzardkng:BAAALgAECgcJDQAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAYJDQAfAHEYAA==.',
Ma='Maango:BAAALgAECgkJCAAAAA==.Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn9DAAMDAAkJOBqrIwB4AgADAAkJOBqrIwB4AgAlAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgQJCAAAAA==.Malkala:BAAALgAECgUJBQAAAA==.Mamadeezy:BAAALgAECgIJAwAAAA==.Manical:BAAALgAECgYJDwAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAUJEgASAI8WAA==.Maxgoon:BAABLgAECn8WAAIOAAcJwgzVcwB2AQAOAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQABLgAECggJDAAPAAAAAA==.',
Me='Megumin:BAABLgAECn8cAAQDAAgJdhOXXACwAQADAAgJ7hKXXACwAQAlAAMJeA+9CgCdAAAmAAIJ3xNtGgBEAAABLgAECgkJLgACACogAA==.Mellisandria:BAAALgAECgcJEQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn81AAIeAAkJmCMJAgA5AwAeAAkJmCMJAgA5AwAAAA==.Merriska:BAACLgAFFH8FAAMEAAIJxyB0MACZAAAEAAIJxyB0MACZAAACAAEJHREtmgBFAAAuAAQKfxsAAwIACQk1IqElAJACAAIACAlWI6ElAJACAAQACAm7IJsTAHUCAAEuAAUUBAkRABEAdCMA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECggJEAABLgAECgkJBgAPAAAAAA==.Misseslovett:BAAALgAECgEJAQAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8YAAIiAAYJkQ4pCQAtAQAiAAYJkQ4pCQAtAQAuAAQKfzwAAiIACQmmHCEGAIICACIACQmmHCEGAIICAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAACLgAFFH8FAAIEAAMJKyVkGABEAQAEAAMJKyVkGABEAQAuAAQKfzEAAwQACQkbJrIBAGgDAAQACQkbJrIBAGgDAAIAAQlhGWxMAUgAAAAA.Morgause:BAAALgAECggJEgAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.Mowenudown:BAAALgAECgEJAQAAAA==.',
Mu='Muirdin:BAABLgAECn8fAAIUAAgJ9xAkVQCLAQAUAAgJ9xAkVQCLAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMYAAkJYCLUCABJAgAYAAkJbCHUCABJAgAHAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAECgkJNQAOACshAA==.',
Na='Naanomage:BAAALgAECgYJEAAAAA==.Nacht:BAAALgADCgEJAQABLgAFFAUJDwAIAIkYAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAABLgAECn81AAMOAAkJKyGlDQDTAgAOAAgJKyGlDQDTAgAQAAEJAAD2XABYAAAAAA==.Nemoralia:BAAALgAECgYJBgAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMIAAkJrxzhIQCGAgAIAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn89AAIKAAkJtw1TBwC2AQAKAAkJtw1TBwC2AQAAAA==.',
No='Noiire:BAAALgAFFAEJAgABLgAFFAYJDgAhAGQHAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8TAAIVAAUJ/CTiAwAXAgAVAAUJ/CTiAwAXAgAuAAQKfzUAAhUACQnzJQsBAGcDABUACQnzJQsBAGcDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn85AAMBAAkJKRLHFADHAQABAAkJKRLHFADHAQAIAAMJcATA6wBEAAAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAAALgAECggJDQAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAYJGgAhAHwfAA==.',
Oa='Oakly:BAACLgAFFH8JAAIbAAMJNxMeNgDEAAAbAAMJNxMeNgDEAAAuAAQKfy4AAhsACAk0HokRALACABsACAk0HokRALACAAAA.',
Ob='Obsidian:BAAALgAECggJCQABLgAFFAMJBQAEACslAA==.',
On='Onaroll:BAABLgAFFH8FAAIRAAMJrgfJNQCPAAARAAMJrgfJNQCPAAABLgAFFAYJFgAbAIoVAA==.Onehotelf:BAAALgAECgUJBQAAAA==.',
Oo='Ooyagoddess:BAAALgAECgYJEwAAAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAUJFQAUAKofAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8gAAIdAAYJ2SJrGQDPAQAdAAYJ2SJrGQDPAQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAIJAgABLgAFFAYJFwAKAKEeAA==.Pann:BAAALgAECgEJAQABLgAECgYJEAAPAAAAAA==.Papatiny:BAAALgAECgYJBgAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn8sAAIfAAgJRxcyIQDBAQAfAAgJRxcyIQDBAQAAAA==.Pawsa:BAABLgAECn8yAAMdAAgJxxsIEwARAgAdAAgJFhoIEwARAgAeAAYJZhsYIACUAQAAAA==.Pawthetic:BAACLgAFFH8WAAIbAAYJihXuEADAAQAbAAYJihXuEADAAQAuAAQKfy8AAxsACQkDITwDAGEDABsACQkDITwDAGEDAA0ACQmRGgcNAHICAAAA.',
Pe='Peelforheals:BAACLgAFFH8KAAIFAAIJLRBsMgCIAAAFAAIJLRBsMgCIAAAuAAQKfycAAwUACAlqFBocALUBAAUABwm7FRocALUBABUABwlrFu4nAG4BAAAA.Penguindemic:BAABLgAECn8kAAIOAAkJGyYABwAXAwAOAAkJGyYABwAXAwAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJJAARAN0XAA==.Pep:BAABLgAECn8fAAMdAAkJ1x0SCwB+AgAdAAkJ1x0SCwB+AgARAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgADCgQJBAAAAA==.Petruccius:BAACLgAFFH8HAAINAAQJvg8NJQDaAAANAAQJvg8NJQDaAAAuAAQKfx8AAg0ACAlTHKEPAE4CAA0ACAlTHKEPAE4CAAAA.Pewpewlepew:BAAALgAECggJEgAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgkJHAAIAIcNAA==.Phaeku:BAABLgAECn8cAAIIAAkJhw20SQCRAQAIAAkJhw20SQCRAQAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJDgABLgAECgkJLwAdADAlAA==.Powermonk:BAAALgAECgQJBwAAAA==.',
Pr='Prayre:BAAALgADCgkJEgAAAA==.Prey:BAAALgAECgUJCAAAAA==.Prospa:BAAALgAECgQJBwAAAA==.Prumper:BAACLgAFFH8IAAIDAAQJMgkwfgDAAAADAAQJMgkwfgDAAAAuAAQKf0EAAgMACQlUHw0iAH8CAAMACQlUHw0iAH8CAAAA.',
Py='Pyric:BAAALgAECgEJBAAAAA==.',
Qu='Quesoblanco:BAAALgAECgkJCAAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgQJBgAAAA==.Qybxboogiemo:BAAALgAECgEJAgAAAA==.Qybxboogietk:BAAALgAECgEJAQAAAA==.',
Ra='Rabid:BAAALgAECgEJAwAAAA==.Raghallov:BAAALgADCggJCgAAAA==.Ragingstorm:BAAALgADCgIJAwAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8wAAISAAkJPx2NGwCOAgASAAkJPx2NGwCOAgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgkJCgAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Regena:BAABLgAECn9CAAQFAAkJZBRRHADKAQAFAAkJawxRHADKAQAGAAkJUhT+HADFAQAVAAcJ3AhoPAD9AAAAAA==.Relyssa:BAAALgAECgYJCgAAAA==.Remorse:BAACLgAFFH8WAAIZAAYJeBbGCwBMAQAZAAYJeBbGCwBMAQAuAAQKf0sAAhkACQnxItoBACoDABkACQnxItoBACoDAAAA.Required:BAAALgAFFAMJAwABLgAFFAcJHwAIACUcAA==.Retro:BAABLgAECn8cAAIfAAcJFQe0TgDeAAAfAAcJFQe0TgDeAAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8qAAMbAAkJex3tDQDYAgAbAAkJex3tDQDYAgANAAkJoxd+EQA5AgABLgAFFAIJAgAPAAAAAA==.Rim:BAABLgAECn9CAAIXAAkJfB5KCQAIAwAXAAkJfB5KCQAIAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8QAAIDAAQJKhe4RQBCAQADAAQJKhe4RQBCAQAuAAQKfyoAAgMACQlIIfUaAKMCAAMACQlIIfUaAKMCAAAA.',
Ro='Ronard:BAACLgAFFH8HAAISAAIJthtsqwCXAAASAAIJthtsqwCXAAAuAAQKf0kAAhIACQkQJhkDAGUDABIACQkQJhkDAGUDAAAA.Ronfar:BAACLgAFFH8VAAIkAAUJPBa2BwAlAQAkAAUJPBa2BwAlAQAuAAQKf0oAAiQACQnEIusAADkDACQACQnEIusAADkDAAAA.',
Ru='Rukidingme:BAAALgAECgIJAwAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Rustyglass:BAAALgAECgEJAQAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8pAAICAAgJyQnejAA8AQACAAgJyQnejAA8AQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAABLgAECn8XAAICAAgJMgpxkQA0AQACAAgJMgpxkQA0AQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCgkJEAABLgAECgkJJAAjAPMfAA==.',
Sc='Schrutes:BAAALgADCgEJAQAAAA==.Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAIdAAcJVBRCLAB+AQAdAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQbAAgJdhy3JQAiAgAbAAcJ1By3JQAiAgANAAYJ+R6FHwADAgAiAAEJGQaYNQAfAAAAAA==.Scubowsuit:BAAALgAECgYJBwAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAECgkJDQAAAA==.Selen:BAABLgAECn88AAIEAAkJmiFaBQAqAwAEAAkJmiFaBQAqAwAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Semballin:BAAALgAECgEJAwAAAA==.Semidari:BAAALgAECgEJAQAAAA==.Semtex:BAAALgAECgEJAQAAAA==.Seråphiel:BAABLgAECn8bAAIUAAYJBQRlswC6AAAUAAYJBQRlswC6AAAAAA==.Seswatha:BAACLgAFFH8PAAIDAAUJRBp9GwBdAQADAAUJRBp9GwBdAQAuAAQKfzAAAgMACQlaIrcNAPgCAAMACQlaIrcNAPgCAAAA.',
Sh='Shadowbaron:BAAALgAECgQJBAAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAABLgAECn8cAAMXAAkJWiIZCQALAwAXAAkJWiIZCQALAwAfAAUJ1xgtSwDsAAABLgAFFAYJGQAEAKUcAA==.Shamdi:BAAALgADCgYJBgAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAAALgAECgcJBwABLgAECggJEgAPAAAAAA==.Shocktop:BAABLgAECn8fAAIkAAkJrSIDAQA0AwAkAAkJrSIDAQA0AwAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAPAAAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAPAAAAAA==.Shådowfire:BAAALgAECgIJAQAAAA==.Shìft:BAABLgAECn8zAAIbAAkJVxn2EgCjAgAbAAkJVxn2EgCjAgAAAA==.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgADCgYJBwAAAA==.Sillynanny:BAAALgAECgUJCQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skuùuß:BAAALgADCgMJAwAAAA==.Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAABLgAECn8VAAQBAAUJphlNJwAaAQABAAUJQhhNJwAaAQAMAAMJCRQxGwCoAAAIAAIJKA3dyABmAAABLgAECggJGAAUAFQbAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8dAAIiAAcJ7COLCABGAgAiAAcJ7COLCABGAgAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8rAAQmAAgJqiWfAgBmAgADAAgJjyB+LQC8AgAmAAYJ0iKfAgBmAgAlAAQJcx+nBQBIAQABLgAFFAMJCAAWACwbAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokinontech:BAAALgAECgEJAQAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIYAAkJCgtIGwBoAQAYAAkJCgtIGwBoAQAAAA==.Smugs:BAAALgAFFAMJAwAAAA==.Smugxl:BAABLgAECn8YAAIgAAkJJBz6AgCaAgAgAAkJJBz6AgCaAgAAAA==.',
So='Solid:BAAALgAECgEJAQAAAA==.Sonicberger:BAAALgADCgQJBAABLgAECgkJKQASADUcAA==.Sonicbergger:BAAALgAECgYJCAABLgAECgkJKQASADUcAA==.Soniclavv:BAAALgADCgQJBAAAAA==.Sonicpoe:BAAALgADCgkJDAABLgAECgkJKQASADUcAA==.Sonícberger:BAABLgAECn8pAAMSAAkJNRy2JgBUAgASAAkJNRy2JgBUAgATAAQJTw/aMgC2AAAAAA==.Soulcaliber:BAAALgAECgEJAgAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
St='Stain:BAAALgAECgUJDQAAAA==.Stealth:BAAALgAECggJDgABLgAFFAIJAwAPAAAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stillheart:BAAALgAECgkJAQAAAA==.Stith:BAAALgADCgYJCAAAAA==.Stkinbck:BAABLgAECn8tAAIhAAgJyA6BIAB3AQAhAAgJyA6BIAB3AQAAAA==.Stonehenge:BAACLgAFFH8NAAIXAAQJSh0jHQBXAQAXAAQJSh0jHQBXAQAuAAQKfyEAAhcACQmkIbUNANECABcACQmkIbUNANECAAAA.Stonepalm:BAAALgADCggJIAAAAA==.Stratan:BAAALgAECgYJEAAAAA==.',
Su='Subbzero:BAAALgADCgUJCAAAAA==.Suffer:BAACLgAFFH8IAAMWAAMJLBsyCgCrAAAOAAMJExmYXwDrAAAWAAIJzRsyCgCrAAAuAAQKfxoABA4ACAmsI2ARALQCAA4ACAmQI2ARALQCABYAAwnOI08ZANMAABAAAgn0GJFjAEcAAAAA.Sukuna:BAAALgAECgEJAQAAAA==.Sundermere:BAAALgAECgEJAQAAAA==.Sunlight:BAAALgADCgMJBAAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8dAAICAAgJ/iDTIwCZAgACAAgJ/iDTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8bAAQdAAYJFxGLFQAEAQAdAAQJtg6LFQAEAQAeAAUJJwxKEAD+AAARAAIJ0wA8VgAkAAAuAAQKfzkAAx4ACQk3HW0QACcCAB0ACAliHXkTAFUCAB4ACQmDGW0QACcCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.',
['Sä']='Sätansangel:BAAALgAECgIJAgAAAA==.',
Ta='Tabbz:BAABLgAECn8sAAMfAAkJvRmfFgAYAgAfAAkJvRmfFgAYAgAXAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgAECgEJBgAAAA==.Tallyhochick:BAACLgAFFH8FAAIUAAIJzAN1dQCBAAAUAAIJzAN1dQCBAAAuAAQKfy8AAhQACQlcDABDAMEBABQACQlcDABDAMEBAAAA.Taman:BAABLgAECn8hAAMXAAcJbRvYIgAkAgAXAAcJbRvYIgAkAgAfAAcJOBamKADPAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAAALgAECggJDwAAAA==.Telean:BAAALgAFFAEJAQAAAA==.Telkon:BAAALgAECggJCAAAAA==.Tellesto:BAABLgAECn8wAAMnAAkJpByREAAdAgAnAAkJqxqREAAdAgAUAAMJNRcBxgCVAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECgkJMwANAAgPAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgAECgIJAwAAAA==.Thebigonion:BAAALgAECgQJBQAAAA==.',
Ti='Tibberino:BAAALgAECggJDwAAAA==.Tinydeath:BAAALgAECgcJBwABLgAECgkJKwAUADMhAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8sAAMeAAkJLBxwEQAaAgAeAAkJ3BtwEQAaAgAdAAUJghpTJAB5AQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwAUADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMUAAkJMyEFDwDDAgAUAAkJECAFDwDDAgAnAAQJtxDrNQDxAAAAAA==.',
To='Toko:BAACLgAFFH8bAAIUAAYJJSIsAgB9AQAUAAYJJSIsAgB9AQAuAAQKfykAAxQACQkjIuIIAAUDABQACQkjIuIIAAUDACAAAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMjAAkJlhq1BgAKAgAjAAkJlhq1BgAKAgATAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBAAAAA==.Tourma:BAAALgAFFAEJAgAAAA==.',
Tr='Trapattack:BAAALgAECgQJBAAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECggJDAAPAAAAAA==.Truepatriot:BAACLgAFFH8JAAIEAAMJbxkXKADNAAAEAAMJbxkXKADNAAAuAAQKfycAAwQACAmoExMyALcBAAQACAmoExMyALcBABoABQnpErYlAMwAAAAA.Truexlord:BAABLgAECn8WAAISAAcJewyZlAApAQASAAcJewyZlAApAQAAAA==.Truthes:BAAALgAFFAIJAwAAAA==.Truthez:BAAALgADCgMJBgABLgAFFAIJAwAPAAAAAA==.Truths:BAAALgAECgcJDgABLgAFFAIJAwAPAAAAAA==.Truthsx:BAABLgAECn8nAAMWAAgJGiC3BAApAgAWAAgJph+3BAApAgAOAAUJchp1fAA1AQABLgAFFAIJAwAPAAAAAA==.Truthz:BAAALgADCgYJBgABLgAFFAIJAwAPAAAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgQJBAAAAA==.Tygerkillz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAFFAEJAQAAAA==.Tyraell:BAABLgAECn8sAAMEAAkJkR16DACzAgAEAAkJkR16DACzAgACAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAACLgAFFH8FAAITAAMJdxltJQCWAAATAAMJdxltJQCWAAAuAAQKfxsAAhMACQlEH10FAOsCABMACQlEH10FAOsCAAEuAAUUBgkbABQAJSIA.',
Ud='Udor:BAABLgAECn8aAAIUAAgJLgzJXQBzAQAUAAgJLgzJXQBzAQAAAA==.',
Um='Umbrae:BAABLgAECn80AAMGAAkJdBwRFAAfAgAGAAgJoRsRFAAfAgAVAAEJ4wfUcAA8AAAAAA==.',
Up='Upies:BAABLgAECn8VAAILAAgJ6gLvVwCtAAALAAgJ6gLvVwCtAAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAABLgAECn8XAAIOAAYJ+QrNmwD8AAAOAAYJ+QrNmwD8AAAAAA==.',
Va='Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIOAAMJjwhaeQC1AAAOAAMJjwhaeQC1AAAuAAQKfyMAAw4ACQnGGs4bAG8CAA4ACQnGGs4bAG8CABAAAQn0HsErAFoAAAAA.Vazro:BAAALgADCgEJAQAAAA==.',
Ve='Veera:BAABLgAECn83AAIfAAkJ6xXfFwAMAgAfAAkJ6xXfFwAMAgAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Vendyr:BAABLgAECn8aAAQWAAgJlCLxBwDOAQAOAAcJQx41LQBZAgAWAAYJsxnxBwDOAQAQAAIJ8AscYABPAAAAAA==.Veyra:BAAALgAECgUJBQAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgQJBwAPAAAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voidvoid:BAAALgADCgEJAQABLgAECgkJNgASAPYeAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorgol:BAABLgAECn8qAAIYAAkJbRlQDAALAgAYAAkJbRlQDAALAgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAICAAcJ0hXiZAC3AQACAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8OAAICAAQJlA3uQAASAQACAAQJlA3uQAASAQAuAAQKfyIAAgIACAmbHq0jAJoCAAIACAmbHq0jAJoCAAAA.',
We='Wellby:BAAALgAECgUJBwAAAA==.Westerin:BAABLgAECn8uAAIQAAkJBhoVAwBXAgAQAAkJBhoVAwBXAgAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgcJBwAAAA==.Wimateeka:BAABLgAECn8dAAQaAAcJzh2QDwDMAQAaAAcJzh2QDwDMAQAEAAUJxRIPYQD4AAACAAQJlw2Y3QDRAAAAAA==.Wimatreeka:BAAALgAECggJDAAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgcJHQAaAM4dAA==.Windfury:BAAALgAECgYJEgABLgAFFAMJCAAWACwbAA==.Windigo:BAABLgAECn8ZAAQTAAYJdxSCJwACAQATAAYJxBGCJwACAQAjAAQJ6w1ZIQCMAAASAAMJcghXAAGLAAAAAA==.Winginit:BAABLgAECn8WAAMLAAkJUBl7DQBuAgALAAkJUBl7DQBuAgAJAAcJTAlQIADcAAABLgAFFAYJFgAbAIoVAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAECgYJCAAAAA==.Wootangz:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.Worthyreaper:BAAALgAECgEJAQAAAA==.',
Wr='Wrastelas:BAAALgAECgQJBwAAAA==.',
Wu='Wurkim:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.',
Wy='Wylder:BAAALgAECgQJBAABLgAFFAUJFgASAO8hAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xanto:BAAALgAFFAEJAQABLgAFFAcJJAADAAIeAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xe='Xenôn:BAAALgAECgYJBgAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAQAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJOAACALcUAA==.',
Ye='Yespaladin:BAAALgAFFAEJAQABLgAFFAUJEwAVAPwkAA==.',
Yi='Yiddosh:BAAALgAECgMJDAAAAA==.',
Yo='Yogí:BAACLgAFFH8QAAIXAAYJbhxQCgDwAQAXAAYJbhxQCgDwAQAuAAQKfx0AAxcACAk6I94FABQDABcACAk6I94FABQDACQABAkJDIwkAKQAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8RAAMRAAQJdCMWEwCZAQARAAQJdCMWEwCZAQAdAAMJdBvGGQDnAAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8pAAMZAAgJOxVMEwCgAQAZAAgJLRNMEwCgAQAHAAIJuhDacwB4AAAAAA==.Zanalia:BAAALgAECggJDAAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8kAAIOAAkJ6AquUQCbAQAOAAkJ6AquUQCbAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zensho:BAAALgAECgYJCQAAAA==.',
Zi='Zipsion:BAABLgAECn8iAAIUAAkJ/iB+FQCRAgAUAAkJ/iB+FQCRAgAAAA==.Zithen:BAACLgAFFH8LAAMLAAMJjgzjOgC5AAALAAMJjgzjOgC5AAAJAAEJ0QEeKgAxAAAuAAQKfxwAAgsACQkPGIojAKEBAAsACQkPGIojAKEBAAAA.Zivver:BAABLgAECn8sAAIZAAkJYSIjBADVAgAZAAkJYSIjBADVAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECggJDAAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIEAAgJUR/gFgA8AgAEAAgJUR/gFgA8AgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAAALgAECgYJEQAAAA==.',
['Üt']='Üther:BAABLgAECn8uAAMCAAkJKiBtHQB9AgACAAkJHCBtHQB9AgAaAAIJKBywLACgAAAAAA==.',
['ßu']='ßubbleøseven:BAABLgAFFH8GAAICAAIJbRcicACfAAACAAIJbRcicACfAAAAAA==.',
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
