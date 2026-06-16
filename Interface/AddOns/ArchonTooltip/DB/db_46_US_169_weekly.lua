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

local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Paladin-Holy','Priest-Discipline','Priest-Holy','Warrior-Fury','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Demonology','Unknown-Unknown','Warlock-Destruction','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Feral','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','DeathKnight-Frost','DemonHunter-Devourer','Druid-Guardian','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aairidari:BAABLgAECn9BAAIBAAkJXhKLFQDcAQABAAkJXhKLFQDcAQAAAA==.Aatrox:BAAALgAECgUJBQABLgAECgkJLgACACogAA==.',
Ab='Abruna:BAAALgAECgcJEwABLgAFFAcJGgADAL4XAA==.Abruno:BAACLgAFFH8aAAIDAAcJvhevJADnAQADAAcJvhevJADnAQAuAAQKfzAAAgMACQmDIgkQAEgDAAMACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAcJGgADAL4XAA==.',
Ad='Adrasteia:BAAALgADCgQJAQABLgAFFAQJEAADAEoUAA==.Adrians:BAABLgAECn8qAAIDAAkJuxbWPgAdAgADAAkJuxbWPgAdAgAAAA==.Adunea:BAAALgAECggJDQAAAA==.',
Ae='Aeown:BAABLgAECn82AAMCAAgJVw5YggBnAQACAAgJVw5YggBnAQAEAAcJpQnmSQASAQABLgAECgkJRAAFAFgVAA==.Aerdis:BAAALgAECgYJEQABLgAECgkJFgAGAIIRAA==.',
Ag='Aggerwator:BAAALgAECgEJAwABLgAECggJHAAHACciAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAFFAIJAgABLgAFFAYJEQAIAMcdAA==.',
Al='Alahrî:BAACLgAFFH8GAAIJAAMJ2QXAIgCEAAAJAAMJ2QXAIgCEAAAuAAQKfzoABAkACQnzEOoWAOEBAAkACQnzEOoWAOEBAAoABgn+DNINACoBAAsABwnqCr1CABsBAAAA.Alandira:BAAALgAECgcJCAAAAA==.Alandrìas:BAACLgAFFH8LAAIMAAQJzQmBCADGAAAMAAQJzQmBCADGAAAuAAQKfy0AAgwACQmcFO4IAN4BAAwACQmcFO4IAN4BAAAA.Allydari:BAAALgAECgEJAQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3WBQA9AwANAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn87AAIJAAkJRBZPCQBQAgAJAAkJRBZPCQBQAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAIDAAcJ2goPxwD7AAADAAcJ2goPxwD7AAAAAA==.Amethystia:BAAALgADCgYJBgAAAA==.Amirandis:BAAALgAECgYJDAAAAA==.Amuri:BAABLgAECn8eAAICAAgJkhCVcQCIAQACAAgJkhCVcQCIAQAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJCgAAAA==.Androonatorz:BAACLgAFFH8ZAAIEAAYJpRz2DwC0AQAEAAYJpRz2DwC0AQAuAAQKfy0AAwQACQkDJUMCAIgDAAQACQkDJUMCAIgDAAIABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAABLgAECn8UAAIOAAcJtgwEhQAvAQAOAAcJtgwEhQAvAQAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgABLgAECgcJAQAPAAAAAA==.Ardemus:BAABLgAECn8XAAMQAAYJIBJ3GADbAAAQAAYJIBJ3GADbAAAOAAEJYAAYNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAABLgAECn8YAAILAAUJ0gMncgCAAAALAAUJ0gMncgCAAAAAAA==.',
As='Ashborrn:BAAALgAECgcJEgAAAA==.Ashtar:BAABLgAECn8dAAIHAAkJJxjDFgA3AgAHAAkJJxjDFgA3AgAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgARAJEWAA==.',
Av='Averyi:BAAALgAECgIJAgAAAA==.',
Aw='Awake:BAAALgAECgEJAgAAAA==.Awaken:BAABLgAECn8dAAIDAAgJaiL6GgC2AgADAAgJaiL6GgC2AgAAAA==.Awoomonk:BAABLgAECn8UAAQSAAYJnyIAFwDvAQASAAYJYyIAFwDvAQATAAUJ9xn8JgB7AQARAAEJSBK2sQA3AAAAAA==.',
Ax='Axhure:BAAALgAECgEJAQAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMUAAYJgBb1PwBwAQAUAAUJgBb1PwBwAQAVAAEJAABnXgAAAAAuAAQKfyEAAhQACAlFIWEVAPsCABQACAlFIWEVAPsCAAAA.Balddrex:BAAALgAECgQJBAAAAA==.Balefire:BAACLgAFFH8HAAIOAAQJQBJeUQAfAQAOAAQJQBJeUQAfAQAuAAQKfywAAw4ACQmRHWkbAH4CAA4ACQmRHWkbAH4CABAAAgntGJE4AEEAAAAA.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgAECgMJAwABLgAECgkJLAAWAMEPAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECggJEQAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn9BAAIDAAkJxSHzEgDmAgADAAkJxSHzEgDmAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAACLgAFFH8IAAINAAQJ1BJ/IAAVAQANAAQJ1BJ/IAAVAQAuAAQKf0QAAg0ACQk+HuAIAMMCAA0ACQk+HuAIAMMCAAAA.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgAECgYJCgAAAA==.Bluewaffles:BAAALgAECgMJBQABLgAECgUJCgAPAAAAAA==.',
Bo='Borealzombie:BAAALgAECgYJCQABLgAECgkJJgAXAN8cAA==.Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8gAAIYAAcJvx0xBQAkAgAYAAcJvx0xBQAkAgAuAAQKfzIAAhgACQnkJFkDACwDABgACQnkJFkDACwDAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAZAFwZAA==.Brimara:BAAALgAFFAIJAwAAAA==.Brunomirror:BAAALgAECgkJDwABLgAFFAcJGgADAL4XAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQABLgAECggJFwAWAKscAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJPQABALgSAA==.Bunsen:BAAALgAECgEJAQABLgAFFAQJEQAaAEcdAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8jAAQbAAgJnyCFBwB8AgAbAAgJjSCFBwB8AgAcAAcJTx1bEwC1AQAHAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMCAAYJehnygAB4AQACAAYJTRnygAB4AQAXAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYhd9KwCmAQANAAcJBBV9KwCmAQAdAAcJkReQTABaAQAeAAIJ+gANOwAYAAAAAA==.Captinsano:BAAALgAECgEJAQABLgAECggJHAAUALsPAA==.Capz:BAACLgAFFH8uAAMbAAcJ4iApAABHAgAbAAcJHSApAABHAgAHAAUJqCJVBwB3AQAuAAQKfyYAAxsACQnRIzwDANsCABsACAkCJTwDANsCAAcACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJDAAAAA==.Cassius:BAAALgAECgEJAgAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECggJCwAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECggJDwAAAA==.Ceezinator:BAAALgAECgQJBAAAAA==.Cefteldore:BAAALgADCgcJBwAAAA==.Celebrïmbor:BAAALgAECgMJAgAAAA==.',
Ch='Chair:BAAALgAECggJEQABLgAFFAQJEAADAEoUAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chokehold:BAAALgADCgMJAwAAAA==.Chopperr:BAAALgAECgQJBAABLgAECggJQwASAH8fAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8QAAIDAAQJShSQVQA8AQADAAQJShSQVQA8AQAuAAQKfz4AAgMACQnDIBQPAAADAAMACQnDIBQPAAADAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8QAAIQAAYJ8RH4AwB1AQAQAAYJ8RH4AwB1AQAuAAQKf0gAAhAACQlhJVoAAFIDABAACQlhJVoAAFIDAAAA.Clow:BAABLgAECn8cAAMHAAgJJyLMGgB1AgAHAAcJqiPMGgB1AgAbAAMJaB72KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQABLgAECggJHwADADUOAA==.Coolcrush:BAABLgAECn88AAMTAAkJyiWpAQBbAwATAAkJTyWpAQBbAwASAAkJuSE7AwAdAwAAAA==.Corgnelius:BAAALgADCgYJDAAAAA==.Corven:BAACLgAFFH8YAAIOAAcJVxYCGgDmAQAOAAcJVxYCGgDmAQAuAAQKf04AAw4ACQlPI1AFADkDAA4ACQlPI1AFADkDABkAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwABLgAFFAcJGAAOAFcWAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJBAABLgAECgkJJgARAB0YAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgkJEgAAAA==.Cryovox:BAAALgAECgQJBAAAAA==.Crôwley:BAAALgAECgQJCQAAAA==.',
Cu='Cumazzing:BAACLgAFFH8fAAICAAgJ/CImAgDdAgACAAgJ/CImAgDdAgAuAAQKfyoAAgIACQmJJrYCAK4DAAIACQmJJrYCAK4DAAAA.',
Da='Dadrin:BAAALgADCgkJOAAAAA==.Daedyxes:BAABLgAECn9AAAIVAAkJiBuHCQB5AgAVAAkJiBuHCQB5AgAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Daní:BAAALgAECgQJBQAAAA==.Darfretail:BAABLgAECn8rAAIHAAkJhR4NCQDPAgAHAAkJhR4NCQDPAgAAAA==.Dargrum:BAAALgAECgYJBgAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgQJCwAAAA==.Daygath:BAACLgAFFH8HAAIfAAIJmAoBRQBwAAAfAAIJmAoBRQBwAAAuAAQKfzEAAh8ACQlvFYgbAAICAB8ACQlvFYgbAAICAAAA.',
De='Deadlyiris:BAABLgAECn8vAAMbAAkJ3yK/AgATAwAbAAkJ3yK/AgATAwAHAAYJHxCZSgB7AQABLgAFFAQJEQAaAEcdAA==.Deatharin:BAAALgAECgYJDQAAAA==.Decompose:BAAALgAECgEJAwAAAA==.Demonbulio:BAABLgAECn81AAIBAAkJFBZeEAAeAgABAAkJFBZeEAAeAgAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAZAFwZAA==.Demonlorrd:BAAALgAECgIJAgABLgAECgQJEAAPAAAAAA==.Demonskitten:BAABLgAECn8fAAIZAAkJXBlQBAA8AgAZAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgAECgEJAQAAAA==.Descendantt:BAAALgAECgEJAQAAAA==.Devilbullet:BAAALgADCgIJAwAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn84AAICAAkJtxQbWwC6AQACAAkJtxQbWwC6AQAAAA==.Dithehealer:BAABLgAECn8kAAMXAAkJYCBgAwDdAgAXAAkJYCBgAwDdAgACAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.Divinecandie:BAAALgAECgEJAQAAAA==.',
Dk='Dkdi:BAABLgAECn8ZAAIVAAkJBSD/BADdAgAVAAkJBSD/BADdAgAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAIDAAYJQR6ZcQDwAQADAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgkJMAAgAOcWAA==.Doogie:BAAALgAECgEJBQAAAA==.Dortak:BAAALgADCgQJBAABLgAECgUJDwAPAAAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAPAAAAAA==.Dragømir:BAAALgAECgEJAQABLgAFFAUJCAALAMkCAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8XAAMKAAYJoR7pAQB9AQAKAAUJBCHpAQB9AQALAAQJyx2EIABUAQAuAAQKfysAAwoACQkmJQcBAF0DAAoACAmKJQcBAF0DAAsACQkqJFADADsDAAAA.Drenamai:BAABLgAECn8hAAIWAAkJMBPkOgDvAQAWAAkJMBPkOgDvAQAAAA==.Drewetta:BAABLgAECn84AAINAAkJyRGsHQDYAQANAAkJyRGsHQDYAQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.Durbana:BAAALgAECgUJCgAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.Duskfire:BAAALgAECgEJAQAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgYJEwAAAA==.',
Ed='Edrocz:BAEALgAECgcJAQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8bAAICAAUJxiacEwDAAQACAAUJxiacEwDAAQAuAAQKfzoAAgIACQkGJq4BAMgDAAIACQkGJq4BAMgDAAEuAAUUCAkfAAIA/CIA.',
El='Elandin:BAAALgAECggJDwAAAA==.Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8QAAIhAAcJhQbDEACDAQAhAAcJhQbDEACDAQAuAAQKfxYAAiEACQmBDSEmAMgBACEACQmBDSEmAMgBAAAA.Elvwyr:BAAALgAECggJDAAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8NAAMfAAYJcRgYJQD9AAAfAAUJlRcYJQD9AAAaAAEJ9wjkdwBIAAAuAAQKfyAAAx8ACAkkHtkTAIACAB8ACAkkHtkTAIACABoABAk3Cat1ALoAAAAA.Emmy:BAABLgAECn8UAAIGAAYJxyAuKgCiAQAGAAYJxyAuKgCiAQAAAA==.Emogothbabe:BAAALgAECgUJBgABLgAECggJQwASAH8fAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAABLgAFFH8GAAMUAAMJGh5ThgD4AAAUAAMJGh5ThgD4AAAiAAEJNB5WIwBWAAABLgAFFAYJFwABAPMeAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQABAAQJqB30AQB7AQAjAAYJDRb1LgBhAQAMAAEJECe3AwB2AAAuAAQKfz8AAwEACQl9JXMAAOgDAAEACQl8JXMAAOgDACMACQm1Iq4FACwDAAAA.Eneldenes:BAAALgAFFAIJAwAAAA==.Enjoyer:BAAALgAECggJEgABLgAECgkJGAANACcOAA==.',
Er='Ereitherla:BAABLgAECn87AAIWAAgJsA/LVwCYAQAWAAgJsA/LVwCYAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAECgYJEQABLgAECggJQwASAH8fAA==.',
Ev='Evanthe:BAAALgADCgEJAQAAAA==.',
Ex='Excalibear:BAABLgAECn8vAAIEAAkJPRbhJADdAQAEAAkJPRbhJADdAQABLgAFFAYJFQADAMocAA==.',
Ey='Eydis:BAAALgADCgkJFwAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Farc:BAAALgAECgUJBQAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECgcJCgAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Felryno:BAAALgADCgQJBAAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fircey:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.Fistbroz:BAABLgAECn8eAAMkAAkJ8xXQEQDMAQAkAAkJFBTQEQDMAQAeAAcJDxW5EwB9AQABLgAFFAcJHQATAGkPAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAIUAAkJPxgzRgDtAQAUAAkJPxgzRgDtAQAAAA==.Fleredil:BAABLgAECn9IAAMYAAkJqSGIBQD7AgAYAAkJqSGIBQD7AgAGAAgJzRp0EQBTAgAAAA==.Flingernle:BAAALgAECgEJAwAAAA==.Floista:BAAALgAECggJDQAAAA==.Floistas:BAABLgAFFH8LAAIWAAMJWBPUWwDlAAAWAAMJWBPUWwDlAAAAAA==.',
Fo='Forepray:BAAALgAFFAEJAQABLgAFFAcJGQAHAIoXAA==.Forger:BAABLgAECn8zAAIcAAkJmhaVDgD+AQAcAAkJmhaVDgD+AQAAAA==.Forsakey:BAAALgAECgUJBQABLgAFFAUJDwAdAMsaAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8UAAQUAAUJaiSvPwBxAQAUAAQJaiSvPwBxAQAiAAQJLhfjDwAQAQAVAAEJAAAbXQAAAAAuAAQKfzYABBQACQkFJHAMADcDABQACQkDJHAMADcDACIACAlhIZEHABsCABUAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAECgkJPgAOAHsiAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostitution:BAAALgAECgEJAQAAAA==.Frostycheeks:BAACLgAFFH8UAAMUAAUJGxtqVgBCAQAUAAQJGxtqVgBCAQAVAAUJLAT1KACqAAAuAAQKfzUAAhQACAkKI5ofAIoCABQACAkKI5ofAIoCAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQjAAgJ0CLxHgBYAgAjAAgJlyLxHgBYAgAMAAIJqiM2KABgAAABAAIJTxhpZAA/AAAAAA==.Future:BAAALgAECgYJDwABLgAFFAMJCAAZACwbAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaav:BAAALgAECgQJBgABLgAECggJHAAHACciAA==.Gaerlan:BAAALgAECgUJDQAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgAECgQJBgABLgAECggJQwASAH8fAA==.',
Gh='Ghettox:BAAALgAECgUJBwAAAA==.Ghostblades:BAACLgAFFH8ZAAMUAAYJFxoBMQCaAQAUAAYJFxoBMQCaAQAiAAEJAABPLQAAAAAuAAQKfysAAxQACQmBIQsXALoCABQACQmBIQsXALoCACIAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.Ghuleh:BAAALgAECgEJAQAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBgABLgAFFAcJGgAYALAaAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAABLgAFFH8IAAIaAAYJ7wveIABmAQAaAAYJ7wveIABmAQABLgAFFAYJFQADAMocAA==.Gorm:BAAALgAECgQJBAABLgAFFAIJBAAPAAAAAA==.',
Gr='Gratata:BAAALgAECgMJBQABLgAECgkJJgARAB0YAA==.Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAABLgAECn8bAAMlAAkJ4w4NCADMAQAlAAkJMQ4NCADMAQAhAAQJ7Q71NwDtAAABLgAECgkJSQACADoiAA==.Grinny:BAABLgAECn9JAAMCAAkJOiJjCQAbAwACAAkJOiJjCQAbAwAEAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Gu='Gunna:BAAALgAECgIJAgABLgAFFAMJCAAZACwbAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8qAAICAAkJ8gzGcwCEAQACAAkJ8gzGcwCEAQABLgAFFAQJEQAaAEcdAA==.Havochunter:BAABLgAECn8XAAIWAAcJqxz3OAD2AQAWAAcJqxz3OAD2AQAAAA==.',
He='Heidegger:BAAALgAECgQJCQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8wAAIgAAkJ5xboBgAbAgAgAAkJ5xboBgAbAgAAAA==.Heriod:BAAALgAECgEJAgAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgAECgUJBQAAAA==.Holywráth:BAAALgAECgUJDAAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECggJEwAAAA==.Hunterdh:BAABLgAECn8vAAIWAAkJfgmgWwCOAQAWAAkJfgmgWwCOAQAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8ZAAIHAAcJihdGCADTAQAHAAcJihdGCADTAQAuAAQKfzAAAgcACQkIIdQLAKoCAAcACQkIIdQLAKoCAAAA.',
Ic='Icecandie:BAAALgAECgYJEgAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAYJFwAKAKEeAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJRAAFAFgVAA==.',
Im='Imistmypants:BAABLgAECn8mAAIRAAkJHRhuEwB7AgARAAkJHRhuEwB7AgAAAA==.',
In='Infinitevoid:BAAALgADCgUJDAAAAA==.Innervatez:BAABLgAFFH8YAAIdAAgJ4hzWAwDcAgAdAAgJ4hzWAwDcAgAAAA==.Inspectda:BAABLgAECn8VAAIOAAgJgwcadgBxAQAOAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAIJAAgJJBtZCwAiAgAJAAgJJBtZCwAiAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn81AAIDAAkJORYaQwAPAgADAAkJORYaQwAPAgAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn8/AAIDAAkJpCQJCgAnAwADAAkJpCQJCgAnAwAAAA==.Jarten:BAABLgAECn81AAIiAAkJqiJwAQAkAwAiAAkJqiJwAQAkAwAAAA==.Jaylebate:BAABLgAECn88AAMUAAkJtyClHgCOAgAUAAkJeh+lHgCOAgAVAAgJ4Rz3DAA5AgAAAA==.',
Je='Jerrenn:BAABLgAECn8eAAMCAAkJqBjJPwAFAgACAAgJ3hfJPwAFAgAEAAIJLwkmeABaAAAAAA==.Jesseatamer:BAABLgAECn84AAIWAAkJlyaxAACTAwAWAAkJlyaxAACTAwAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jortak:BAAALgAECggJEwABLgAECgkJPAAUALcgAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.',
Ju='Judge:BAAALgAECgEJAgAAAA==.Julesx:BAAALgAFFAEJAQAAAA==.Justar:BAAALgADCgMJBQAAAA==.',
['Jë']='Jësus:BAAALgAECgcJCAAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAABLgAECn8UAAMgAAgJGhkPEABWAQAWAAgJbBaTUwCkAQAgAAcJ/BMPEABWAQABLgAFFAMJBAAPAAAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAIUAAkJVBalRQDvAQAUAAkJVBalRQDvAQAAAA==.Karen:BAAALgAECgUJDQABLgAECgkJOAACALcUAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJAwAAAA==.Kastia:BAAALgAECgUJDAAAAA==.Katrynwel:BAABLgAECn8fAAIDAAgJNQ7/ewB9AQADAAgJNQ7/ewB9AQAAAA==.Katsumi:BAAALgADCgkJQgAAAA==.Kaylestia:BAAALgAECgkJCQAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCggJFgAAAA==.Kettama:BAAALgAECgEJAQABLgAECggJQwASAH8fAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.Khold:BAABLgAECn8VAAMUAAgJIhdqUADQAQAUAAcJkRlqUADQAQAiAAcJTQbVHADjAAAAAA==.',
Ki='Killalltoday:BAABLgAECn8/AAMaAAkJPhCkSACIAQAaAAgJMxGkSACIAQAmAAgJNg7dEgCEAQAAAA==.Killersmile:BAAALgADCggJCAAAAA==.Kilon:BAAALgAFFAEJAQAAAA==.Kirkk:BAAALgAECgYJDAAAAA==.Kivareous:BAAALgAFFAIJAwAAAA==.Kixarea:BAAALgADCgkJDQABLgAFFAIJAwAPAAAAAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAABLgAECn8ZAAIVAAgJsxbyFADEAQAVAAgJsxbyFADEAQAAAA==.Knixx:BAACLgAFFH8VAAMYAAUJswodHwDzAAAYAAQJYQkdHwDzAAAFAAUJeAgQLwDQAAAuAAQKf0YABBgACQmlGtwLAJICABgACQmlGtwLAJICAAYABwk6GGQbAAECAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAISAAkJUxGdJgB4AQASAAkJUxGdJgB4AQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIRAAkJmhjMFABuAgARAAkJmhjMFABuAgAAAA==.Koyya:BAAALgAFFAIJAwAAAA==.',
Ku='Kufoo:BAABLgAECn8/AAMHAAkJeCacAQBlAwAHAAkJoSWcAQBlAwAcAAgJ1CVvBADdAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJCAAZACwbAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8gAAIMAAkJkxcBBgA4AgAMAAkJkxcBBgA4AgAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
['Ké']='Kéndra:BAAALgAECgMJAwAAAA==.',
La='Ladiable:BAAALgAECgYJCQABLgAFFAYJFQAWAF8eAA==.Laggyboi:BAAALgAECgYJBwAAAA==.Lansseax:BAAALgAECgcJDQAAAA==.Laraelin:BAAALgADCgYJBgAAAA==.Lascerette:BAAALgAECgYJCgAAAA==.Law:BAAALgADCgcJDwAAAA==.Layez:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Leo:BAAALgAECgEJAQAAAA==.Lethe:BAAALgAECgcJCAABLgAFFAcJEAAhAIUGAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAAWAAAbAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgIJBAAPAAAAAA==.Lilyröse:BAAALgAECgIJBAAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn86AAIOAAkJFRvNJwA7AgAOAAkJFRvNJwA7AgAAAA==.Lohmi:BAAALgAECgYJDAAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAACLgAFFH8JAAINAAQJ6gJrNACnAAANAAQJ6gJrNACnAAAuAAQKfywAAg0ACQkICxErAHgBAA0ACQkICxErAHgBAAAA.',
Lu='Luania:BAAALgAECgUJEAAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lurtz:BAABLgAECn8YAAIWAAYJ4BbbbABjAQAWAAYJ4BbbbABjAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgIJAwAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.Lyzzardkng:BAAALgAECgcJDQAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAYJDQAfAHEYAA==.',
Ma='Maango:BAAALgAECgkJCAAAAA==.Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn9EAAMDAAkJOBp8KAB2AgADAAkJOBp8KAB2AgAnAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgQJCAAAAA==.Malkala:BAAALgAECgUJBwAAAA==.Mamadeezy:BAAALgAECgIJAwAAAA==.Manical:BAAALgAECgYJEQAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAUJFQAUAI8WAA==.Maxgoon:BAABLgAECn8WAAIOAAcJwgzVcwB2AQAOAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQABLgAECggJDgAPAAAAAA==.',
Me='Megumin:BAABLgAECn8cAAQDAAgJdhOYZACyAQADAAgJ7hKYZACyAQAnAAMJeA+aDACZAAAoAAIJ3xNtGgBEAAABLgAECgkJLgACACogAA==.Mellisandria:BAAALgAECgcJEQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn81AAISAAkJmCN4AgA0AwASAAkJmCN4AgA0AwAAAA==.Merriska:BAACLgAFFH8FAAMEAAIJxyBYNgCPAAAEAAIJxyBYNgCPAAACAAEJHRG7sgBFAAAuAAQKfxsAAwIACQk1IqElAJACAAIACAlWI6ElAJACAAQACAm7IJsTAHUCAAEuAAUUBgkWABEAciQA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECggJEAABLgAECgkJBgAPAAAAAA==.Mirigosa:BAAALgAECggJCAABLgAFFAQJEAADAEoUAA==.Misseslovett:BAAALgAECgcJDAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8bAAIkAAcJDBD/BwBsAQAkAAcJDBD/BwBsAQAuAAQKfz0AAiQACQnPHDEHAIECACQACQnPHDEHAIECAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAACLgAFFH8JAAIEAAQJpyNvEgCWAQAEAAQJpyNvEgCWAQAuAAQKfzMAAwQACQk2JrIBAGgDAAQACQk2JrIBAGgDAAIAAQlhGU1tAUYAAAAA.Morgause:BAAALgAECggJEwAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.',
Mu='Muirdin:BAABLgAECn8hAAIWAAgJtRKtWQCTAQAWAAgJtRKtWQCTAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMbAAkJYCJOCgBCAgAbAAkJbCFOCgBCAgAHAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAECgkJPgAOAHsiAA==.',
Na='Naanomage:BAAALgAECgYJEwAAAA==.Nacht:BAAALgADCgEJAQABLgAFFAYJEQAIAMcdAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAABLgAECn8+AAMOAAkJeyLYCgD3AgAOAAgJeyLYCgD3AgAQAAEJAAD2XABYAAAAAA==.Nemoralia:BAAALgAECggJDgAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMjAAkJrxzhIQCGAgAjAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn8+AAIKAAkJtw1mCACoAQAKAAkJtw1mCACoAQAAAA==.',
No='Noiire:BAAALgAFFAEJAgABLgAFFAcJEAAhAIUGAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8UAAIYAAUJ/CSPBgACAgAYAAUJ/CSPBgACAgAuAAQKfzUAAhgACQnzJV4BAGoDABgACQnzJV4BAGoDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn89AAMBAAkJuBJ5FgDPAQABAAkJuBJ5FgDPAQAjAAMJcATBAQFEAAAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAABLgAECn8eAAMRAAkJCBKcOQCEAQARAAgJmQ+cOQCEAQATAAQJSxHEQQD0AAAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAYJGwAhAHwfAA==.',
Oa='Oakly:BAACLgAFFH8JAAIdAAMJNxM2PgCyAAAdAAMJNxM2PgCyAAAuAAQKfy4AAh0ACAk0HlITAK8CAB0ACAk0HlITAK8CAAAA.',
Ob='Obsidian:BAAALgAECggJEAABLgAFFAQJCQAEAKcjAA==.',
On='Onaroll:BAABLgAFFH8GAAIRAAMJrgcfRQCEAAARAAMJrgcfRQCEAAABLgAFFAcJFwAdAL4SAA==.Onehotelf:BAAALgAECgcJEwAAAA==.',
Oo='Ooyagoddess:BAABLgAECn8ZAAIGAAYJWxXUKgBtAQAGAAYJWxXUKgBtAQAAAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAYJFgAWALYeAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8gAAITAAYJ2SIGHADLAQATAAYJ2SIGHADLAQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAIJAgABLgAFFAYJFwAKAKEeAA==.Pann:BAAALgAECgEJAQABLgAECgYJEwAPAAAAAA==.Papatiny:BAAALgAECgYJBgAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn85AAIfAAgJ/BmpGgAJAgAfAAgJ/BmpGgAJAgAAAA==.Pawsa:BAABLgAECn9DAAMSAAgJfx8GCwCBAgASAAgJfx8GCwCBAgATAAgJFhpPFQAMAgAAAA==.Pawsome:BAAALgAECgUJCQABLgAECggJOQAfAPwZAA==.Pawthetic:BAACLgAFFH8XAAIdAAcJvhLyEQDaAQAdAAcJvhLyEQDaAQAuAAQKfy8AAx0ACQkDITwDAGEDAB0ACQkDITwDAGEDAA0ACQmRGvgOAGwCAAAA.',
Pe='Peelforheals:BAACLgAFFH8KAAIFAAIJLRAvPACBAAAFAAIJLRAvPACBAAAuAAQKfywAAxgACAm+Gn4gAMABABgABwmhGX4gAMABAAUABwm7FRocALUBAAAA.Penguindemic:BAABLgAECn8sAAIOAAkJaibwAQBzAwAOAAkJaibwAQBzAwAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJJgARAB0YAA==.Pep:BAABLgAECn8fAAMTAAkJ1x23DAB2AgATAAkJ1x23DAB2AgARAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgAECgcJCAAAAA==.Petruccius:BAACLgAFFH8MAAINAAUJ1hRuHwAbAQANAAUJ1hRuHwAbAQAuAAQKfysAAg0ACAmsIIYOAHMCAA0ACAmsIIYOAHMCAAAA.Pewpewlepew:BAAALgAECggJEgAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgkJJwAjALkTAA==.Phaeku:BAABLgAECn8nAAIjAAkJuRO0MgD4AQAjAAkJuRO0MgD4AQAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Poochita:BAAALgADCgEJAQAAAA==.Poppop:BAAALgADCgMJAwAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJEAABLgAECgkJPAATAMolAA==.Powermonk:BAAALgAECgQJBwAAAA==.',
Pr='Prayre:BAAALgADCgkJFQAAAA==.Prey:BAAALgAECgUJCAAAAA==.Prospa:BAAALgAECgQJBwABLgAECggJQwASAH8fAA==.Prumper:BAACLgAFFH8IAAIDAAQJMgmwjgC9AAADAAQJMgmwjgC9AAAuAAQKf0EAAgMACQlUH78mAH4CAAMACQlUH78mAH4CAAAA.',
Py='Pyric:BAAALgAECgEJBAAAAA==.',
Qu='Quesoblanco:BAAALgAECgkJCgAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgYJCwAAAA==.Qybxboogiemo:BAAALgAECgEJAgAAAA==.Qybxboogietk:BAAALgAECgIJAgAAAA==.',
Ra='Rabid:BAAALgAECgEJAwAAAA==.Raghallov:BAAALgAECgMJAwAAAA==.Ragingstorm:BAAALgADCgIJAwAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8wAAIUAAkJPx3MHwCIAgAUAAkJPx3MHwCIAgAAAA==.Ravokkc:BAAALgADCgMJAwAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgkJEwAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Refractrix:BAAALgAECgQJBAAAAA==.Regena:BAABLgAECn9EAAQFAAkJWBUZHgDaAQAFAAkJqg0ZHgDaAQAGAAkJUhQKIQC2AQAYAAcJ3AgZQQAJAQAAAA==.Relyssa:BAAALgAECgcJDgAAAA==.Remorse:BAACLgAFFH8YAAIcAAcJXRoZCACsAQAcAAcJXRoZCACsAQAuAAQKf0sAAhwACQnxInoCAB0DABwACQnxInoCAB0DAAAA.Required:BAAALgAFFAMJAwABLgAFFAcJIgAjACUcAA==.Retro:BAABLgAECn8mAAIfAAcJ8QlwTwD0AAAfAAcJ8QlwTwD0AAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8tAAMdAAkJ+x1UDQDuAgAdAAkJ+x1UDQDuAgANAAkJoxfIEwAzAgABLgAFFAIJAwAPAAAAAA==.Rim:BAABLgAECn9EAAIaAAkJfB4ACwAEAwAaAAkJfB4ACwAEAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8QAAIDAAQJKhdgVwA5AQADAAQJKhdgVwA5AQAuAAQKfyoAAgMACQlIIcYeAKICAAMACQlIIcYeAKICAAAA.',
Ro='Ronard:BAACLgAFFH8HAAIUAAIJthsCzACSAAAUAAIJthsCzACSAAAuAAQKf0kAAhQACQkQJhUEAF8DABQACQkQJhUEAF8DAAAA.Ronfar:BAACLgAFFH8WAAImAAYJxxR7BQBlAQAmAAYJxxR7BQBlAQAuAAQKf0oAAiYACQnEIkQBAC4DACYACQnEIkQBAC4DAAAA.Rook:BAAALgAECggJCAAAAA==.',
Ru='Rukidingme:BAAALgAECgYJEgAAAA==.Rumonkingme:BAAALgADCgUJBwAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Rustyglass:BAAALgAECgEJAQAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8wAAICAAkJbQ1fYQCrAQACAAkJbQ1fYQCrAQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAABLgAECn8XAAICAAgJMgrrmwA7AQACAAgJMgrrmwA7AQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCgkJEAABLgAECgkJNQAiAKoiAA==.',
Sc='Schrutes:BAAALgADCgEJAQAAAA==.Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAITAAcJVBRCLAB+AQATAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQdAAgJdhy3JQAiAgAdAAcJ1By3JQAiAgANAAYJ+R6FHwADAgAkAAEJGQaYNQAfAAAAAA==.Scubowsuit:BAAALgAECgYJCQAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAECgkJDQAAAA==.Selen:BAABLgAECn8/AAIEAAkJmiFwBgAkAwAEAAkJmiFwBgAkAwAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Semballin:BAAALgAECgEJAwAAAA==.Semdogg:BAAALgAECgEJAQABLgAECgkJNwABAKQhAA==.Semtex:BAAALgAECgEJAQAAAA==.Seråphiel:BAABLgAECn8jAAIWAAgJZAUHjwAcAQAWAAgJZAUHjwAcAQAAAA==.Seswatha:BAACLgAFFH8VAAIDAAYJyhyLKQDMAQADAAYJyhyLKQDMAQAuAAQKfzoAAgMACQklJS4FAFkDAAMACQklJS4FAFkDAAAA.',
Sh='Shadowbaron:BAAALgAECgQJCwAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAABLgAECn8cAAMaAAkJWiLDCgAGAwAaAAkJWiLDCgAGAwAfAAUJ1xiGUgDqAAABLgAFFAYJGQAEAKUcAA==.Shamdi:BAAALgADCgYJBgAAAA==.Shawti:BAAALgADCgcJCAAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAABLgAECn8YAAINAAkJJw5YJACkAQANAAkJJw5YJACkAQAAAA==.Shocktop:BAABLgAECn8fAAImAAkJrSJXAQAqAwAmAAkJrSJXAQAqAwAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAPAAAAAA==.Shortserkit:BAAALgAECgYJBgAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAPAAAAAA==.Shådowfire:BAAALgAECgcJBwAAAA==.Shìft:BAACLgAFFH8JAAIdAAQJOQsMNwDLAAAdAAQJOQsMNwDLAAAuAAQKfzMAAh0ACQlXGd8UAKACAB0ACQlXGd8UAKACAAAA.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgAECgEJAQAAAA==.Sillynanny:BAAALgAECgUJCQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skuùuß:BAAALgADCgMJAwAAAA==.Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAABLgAECn8bAAQBAAUJ2xrCJwA4AQABAAUJ2xrCJwA4AQAMAAMJPReHGgDEAAAjAAIJKA3dyABmAAABLgAECgkJGgAWAP4YAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8eAAIkAAgJ5iJeBgCVAgAkAAgJ5iJeBgCVAgAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8rAAQoAAgJqiWfAgBmAgADAAgJjyB+LQC8AgAoAAYJ0iKfAgBmAgAnAAQJcx+vBgA+AQABLgAFFAMJCAAZACwbAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokinontech:BAAALgAECgEJAQABLgAECggJQwASAH8fAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIbAAkJCgtuHwBeAQAbAAkJCgtuHwBeAQAAAA==.Smugs:BAABLgAFFH8HAAIgAAQJ+g+sFQARAQAgAAQJ+g+sFQARAQAAAA==.Smugxl:BAABLgAECn8YAAIgAAkJJByHAwCQAgAgAAkJJByHAwCQAgAAAA==.',
So='Solid:BAAALgAECgEJAQAAAA==.Sonicberger:BAAALgADCgQJBAABLgAECgkJKQAUADUcAA==.Sonicbergger:BAAALgAECgYJCAABLgAECgkJKQAUADUcAA==.Soniclavv:BAAALgAECgcJCAAAAA==.Sonicpoe:BAAALgADCgkJDAABLgAECgkJKQAUADUcAA==.Sonícberger:BAABLgAECn8pAAMUAAkJNRwLLABOAgAUAAkJNRwLLABOAgAVAAQJTw/xNwCyAAAAAA==.Soulcaliber:BAAALgAECgEJAgAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
Sq='Squee:BAAALgAFFAIJAwABLgAFFAYJFgARAHIkAA==.',
St='Stain:BAAALgAECgUJEQAAAA==.Stealth:BAAALgAECggJDgABLgAFFAIJAwAPAAAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stillheart:BAAALgAECgkJAQAAAA==.Stith:BAAALgADCgYJCAAAAA==.Stkinbck:BAABLgAECn88AAIhAAgJSxBnIQCGAQAhAAgJSxBnIQCGAQAAAA==.Stonehenge:BAACLgAFFH8RAAIaAAQJRx1FJQBMAQAaAAQJRx1FJQBMAQAuAAQKfyIAAhoACQmzIcEPANACABoACQmzIcEPANACAAAA.Stonepalm:BAAALgADCgkJKQAAAA==.Stratan:BAABLgAECn8bAAMXAAYJjAugKgDBAAACAAYJ4wfz4wDWAAAXAAYJZAqgKgDBAAAAAA==.',
Su='Subbzero:BAAALgADCgcJEgAAAA==.Suffer:BAACLgAFFH8IAAMZAAMJLBuYDQCjAAAOAAMJExmBbwDdAAAZAAIJzRuYDQCjAAAuAAQKfxoABA4ACAmsI/wTAKwCAA4ACAmQI/wTAKwCABkAAwnOIykdANEAABAAAgn0GJFjAEcAAAAA.Sukuna:BAAALgAECgUJBQAAAA==.Sundermere:BAAALgAECgEJAgABLgAECgEJAwAPAAAAAA==.Sunlight:BAAALgAECgQJBAAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8eAAICAAgJ/iDTIwCZAgACAAgJ/iDTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8dAAQTAAcJaQ+WEAAzAQATAAUJLA2WEAAzAQASAAUJJwxKEAD+AAARAAIJ0wCeawAiAAAuAAQKfzkAAxIACQk3HfkRACQCABMACAliHXkTAFUCABIACQmDGfkRACQCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.Synzen:BAAALgADCgIJAgAAAA==.',
['Sä']='Sätansangel:BAAALgAECgQJBQAAAA==.',
Ta='Tabbz:BAABLgAECn8sAAMfAAkJvRlrGQATAgAfAAkJvRlrGQATAgAaAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgAFFAMJBAAAAA==.Tallyhochick:BAACLgAFFH8KAAIWAAQJkAMeWwDmAAAWAAQJkAMeWwDmAAAuAAQKfy8AAhYACQlcDJlNALUBABYACQlcDJlNALUBAAAA.Taman:BAABLgAECn8iAAMaAAcJbRv4JgAhAgAaAAcJbRv4JgAhAgAfAAcJOBamKADPAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAABLgAECn8XAAISAAgJdAxeMAA/AQASAAgJdAxeMAA/AQAAAA==.Telean:BAAALgAFFAEJAQAAAA==.Telkon:BAAALgAECggJCgAAAA==.Tellesto:BAABLgAECn8wAAMIAAkJpBy1EgATAgAIAAkJqxq1EgATAgAWAAMJNRd12gCRAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECgkJOAANAMkRAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgAECgIJBAAAAA==.Thebigonion:BAABLgAECn8ZAAIfAAYJbw0sUwDoAAAfAAYJbw0sUwDoAAAAAA==.',
Ti='Tibberino:BAAALgAECggJDwAAAA==.Ticklantical:BAAALgAECggJCAABLgAECgkJRAADADgaAA==.Tinydeath:BAAALgAECgcJBwABLgAECgkJKwAWADMhAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8sAAMSAAkJLBwkEwAWAgASAAkJ3BskEwAWAgATAAUJgho1KAB0AQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwAWADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMWAAkJMyEFDwDDAgAWAAkJECAFDwDDAgAIAAQJtxCxOQDtAAAAAA==.',
To='Toko:BAACLgAFFH8cAAIWAAYJJSIsAgB9AQAWAAYJJSIsAgB9AQAuAAQKfykAAxYACQkjIuIIAAUDABYACQkjIuIIAAUDACAAAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMiAAkJlho8CAAJAgAiAAkJlho8CAAJAgAVAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBQAAAA==.Tourma:BAAALgAFFAEJAwAAAA==.',
Tr='Trapattack:BAAALgAECgQJBwAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECggJDgAPAAAAAA==.Truepatriot:BAACLgAFFH8JAAIEAAMJbxlzLgC5AAAEAAMJbxlzLgC5AAAuAAQKfycAAwQACAmoExMyALcBAAQACAmoExMyALcBABcABQnpEkEpAMsAAAAA.Truexlord:BAABLgAECn8WAAIUAAcJewzfogAlAQAUAAcJewzfogAlAQAAAA==.Truthes:BAAALgAFFAIJAwAAAA==.Truthez:BAAALgADCgMJBgABLgAFFAIJAwAPAAAAAA==.Truths:BAAALgAECgcJDgABLgAFFAIJAwAPAAAAAA==.Truthsx:BAABLgAECn8nAAMZAAgJGiDoBQAiAgAZAAgJph/oBQAiAgAOAAUJchqlhAAvAQABLgAFFAIJAwAPAAAAAA==.Truthz:BAAALgADCgYJBgABLgAFFAIJAwAPAAAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgUJCAAAAA==.Tygerhealz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAFFAMJBAAAAA==.Tyraell:BAABLgAECn8sAAMEAAkJkR1EDgCuAgAEAAkJkR1EDgCuAgACAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAACLgAFFH8FAAIVAAMJdxkYLQCPAAAVAAMJdxkYLQCPAAAuAAQKfxsAAhUACQlEH10FAOsCABUACQlEH10FAOsCAAEuAAUUBgkcABYAJSIA.',
Ud='Udor:BAABLgAECn8aAAIWAAgJLgx/agBoAQAWAAgJLgx/agBoAQAAAA==.',
Um='Umbrae:BAACLgAFFH8FAAMGAAMJhQiIKwBkAAAGAAIJKwyIKwBkAAAYAAEJpwDaQQAMAAAuAAQKfz0AAwYACQlGH9QPAGkCAAYACAnNHtQPAGkCABgAAQnjB1V+ADwAAAAA.',
Up='Upies:BAABLgAECn8VAAILAAgJ6gJ0XADAAAALAAgJ6gJ0XADAAAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAABLgAECn8hAAIOAAcJBQ4zegBEAQAOAAcJBQ4zegBEAQAAAA==.',
Va='Vahder:BAAALgAECgEJAQAAAA==.Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIOAAMJjwg7igCrAAAOAAMJjwg7igCrAAAuAAQKfyMAAw4ACQnGGg0fAGgCAA4ACQnGGg0fAGgCABAAAQn0Hl4wAFgAAAAA.Vazro:BAAALgAECgYJBgAAAA==.',
Ve='Veera:BAABLgAECn83AAIfAAkJ6xVFGwAEAgAfAAkJ6xVFGwAEAgAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Velyris:BAAALgAECgMJAwAAAA==.Vendyr:BAABLgAECn8aAAQZAAgJlCLxBwDOAQAOAAcJQx41LQBZAgAZAAYJsxnxBwDOAQAQAAIJ8AscYABPAAAAAA==.Veyra:BAAALgAECgUJBgAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgQJBwAPAAAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voidvoid:BAAALgAECggJDgABLgAFFAMJBgAUAE0XAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorgol:BAABLgAECn8qAAIbAAkJbRnxDQAIAgAbAAkJbRnxDQAIAgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAICAAcJ0hXiZAC3AQACAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8OAAICAAQJlA2rUQAHAQACAAQJlA2rUQAHAQAuAAQKfyIAAgIACAmbHq0jAJoCAAIACAmbHq0jAJoCAAAA.',
We='Weeooeeooeeo:BAAALgAECggJCgABLgAECgkJPQABALgSAA==.Wellby:BAAALgAECgUJCgAAAA==.Westerin:BAABLgAECn84AAIQAAkJMhy6AgCAAgAQAAkJMhy6AgCAAgAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgkJEAAAAA==.Wimateeka:BAABLgAECn8eAAQXAAcJzh2QDwDMAQAXAAcJzh2QDwDMAQAEAAUJxRIPYQD4AAACAAQJlw2Y3QDRAAABLgAECgkJEwAPAAAAAA==.Wimatreeka:BAAALgAECgkJEwAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgkJEwAPAAAAAA==.Windfury:BAAALgAECgYJEgABLgAFFAMJCAAZACwbAA==.Windigo:BAACLgAFFH8FAAIiAAMJ3gUrGQC2AAAiAAMJ3gUrGQC2AAAuAAQKfx0ABCIABgn8FEEYABABACIABQldFkEYABABABUABgnEEYInAAIBABQAAwlyCPIYAYcAAAAA.Winginit:BAABLgAECn8WAAMLAAkJUBkKDwBzAgALAAkJUBkKDwBzAgAJAAcJTAl7IgDXAAABLgAFFAcJFwAdAL4SAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAECgYJCAAAAA==.Wootangz:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.Worthyreaper:BAAALgAECgEJAQAAAA==.',
Wr='Wrastelas:BAAALgAECgQJBwAAAA==.',
Wu='Wurkim:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.',
Wy='Wylder:BAAALgAECgQJBAABLgAFFAUJGgAUAO8hAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xanto:BAAALgAFFAEJAQABLgAFFAcJKAADACweAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xe='Xenôn:BAAALgAECgYJBgAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAgAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJOAACALcUAA==.',
Ye='Yespaladin:BAAALgAFFAEJAQABLgAFFAUJFAAYAPwkAA==.',
Yi='Yiddosh:BAAALgAECgMJDAAAAA==.',
Yo='Yogí:BAACLgAFFH8VAAIaAAYJ/BymDQD2AQAaAAYJ/BymDQD2AQAuAAQKfx4AAxoACAk6I94FABQDABoACAk6I94FABQDACYABAkJDJopAKMAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8WAAMRAAYJciR9CAB0AgARAAYJciR9CAB0AgATAAMJdBspHwDYAAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8vAAMcAAkJ2RTRDwDmAQAcAAkJOBTRDwDmAQAHAAIJuhCqfwBzAAAAAA==.Zanalia:BAAALgAECggJDgAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeeko:BAAALgAECgUJCAAAAA==.Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8rAAIOAAkJ3g15TQCxAQAOAAkJ3g15TQCxAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zenkuh:BAAALgAECgUJCAABLgAFFAUJEAADAPEUAA==.Zensho:BAAALgAECgYJCQAAAA==.Zeplenith:BAAALgAECgIJAwAAAA==.',
Zi='Zipsion:BAABLgAECn8iAAIWAAkJ/iCfGgCBAgAWAAkJ/iCfGgCBAgAAAA==.Zithen:BAACLgAFFH8PAAMLAAQJNQ61MwDyAAALAAQJNQ61MwDyAAAJAAEJ0QFMLwAlAAAuAAQKfx4AAgsACQkPGIojAKEBAAsACQkPGIojAKEBAAAA.Zivver:BAABLgAECn8tAAIcAAkJYSI8BQDFAgAcAAkJYSI8BQDFAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECggJDgAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIEAAgJUR9vGQA5AgAEAAgJUR9vGQA5AgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAABLgAECn8ZAAMCAAcJYBVEhgBgAQACAAcJNRJEhgBgAQAXAAUJ1BchIQAIAQAAAA==.',
['Üt']='Üther:BAABLgAECn8uAAMCAAkJKiAKIwB3AgACAAkJHCAKIwB3AgAXAAIJKBwLMQCeAAAAAA==.',
['ßu']='ßubbleøseven:BAABLgAFFH8JAAICAAIJZyDGdwC/AAACAAIJZyDGdwC/AAAAAA==.',
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
