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

local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Paladin-Holy','Priest-Discipline','Priest-Holy','Warrior-Fury','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Demonology','Unknown-Unknown','Warlock-Destruction','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Protection','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','DeathKnight-Frost','DemonHunter-Devourer','Druid-Guardian','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aairidari:BAABLgAECn85AAIBAAkJUBCTFwC4AQABAAkJUBCTFwC4AQAAAA==.Aatrox:BAAALgAECgUJBQABLgAECgkJLgACACogAA==.',
Ab='Abruna:BAAALgAECgcJEwABLgAFFAcJGgADAL4XAA==.Abruno:BAACLgAFFH8aAAIDAAcJvhczHwDqAQADAAcJvhczHwDqAQAuAAQKfzAAAgMACQmDIgkQAEgDAAMACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAcJGgADAL4XAA==.',
Ad='Adrasteia:BAAALgADCgQJAQABLgAFFAQJEAADAEoUAA==.Adrians:BAABLgAECn8qAAIDAAkJuxZPPAAiAgADAAkJuxZPPAAiAgAAAA==.Adunea:BAAALgAECgUJBQAAAA==.',
Ae='Aeown:BAABLgAECn81AAMCAAgJzg2xfgBmAQACAAgJzg2xfgBmAQAEAAcJpQnmRwATAQABLgAECgkJQgAFAGQUAA==.Aerdis:BAAALgAECgYJEQABLgAECggJFAAGAO0RAA==.',
Ag='Aggerwator:BAAALgAECgEJAwABLgAECggJHAAHACciAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAFFAIJAgABLgAFFAUJDwAIANggAA==.',
Al='Alahrî:BAACLgAFFH8GAAIJAAMJ2QXyIACMAAAJAAMJ2QXyIACMAAAuAAQKfzoABAkACQnzEOoWAOEBAAkACQnzEOoWAOEBAAoABgn+DC4NAC8BAAsABwnqCnQ/ACABAAAA.Alandira:BAAALgAECgcJCAAAAA==.Alandrìas:BAACLgAFFH8HAAIMAAMJhglZCgCSAAAMAAMJhglZCgCSAAAuAAQKfy0AAgwACQmcFHsIAN4BAAwACQmcFHsIAN4BAAAA.Allydari:BAAALgAECgEJAQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3WBQA9AwANAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn87AAIJAAkJRBYLCQBSAgAJAAkJRBYLCQBSAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAIDAAcJ2gryvwAEAQADAAcJ2gryvwAEAQAAAA==.Amethystia:BAAALgADCgYJBgAAAA==.Amirandis:BAAALgAECgYJDAAAAA==.Amuri:BAABLgAECn8dAAICAAgJkhA2bACLAQACAAgJkhA2bACLAQAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJCgAAAA==.Androonatorz:BAACLgAFFH8ZAAIEAAYJpRzYDQDKAQAEAAYJpRzYDQDKAQAuAAQKfy0AAwQACQkDJQ4CAIoDAAQACQkDJQ4CAIoDAAIABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAABLgAECn8UAAIOAAcJtgxDgQAyAQAOAAcJtgxDgQAyAQAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgABLgAECgcJAQAPAAAAAA==.Ardemus:BAABLgAECn8XAAMQAAYJIBIwFwDeAAAQAAYJIBIwFwDeAAAOAAEJYAAYNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAABLgAECn8UAAILAAUJ0gMEbgCCAAALAAUJ0gMEbgCCAAAAAA==.',
As='Ashborrn:BAAALgAECgcJEgAAAA==.Ashtar:BAABLgAECn8YAAIHAAkJLBcBHwDxAQAHAAkJLBcBHwDxAQAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgARAJEWAA==.',
Av='Averyi:BAAALgAECgIJAgAAAA==.',
Aw='Awake:BAAALgAECgEJAQAAAA==.Awaken:BAABLgAECn8dAAIDAAgJaiJvGQC7AgADAAgJaiJvGQC7AgAAAA==.Awoomonk:BAAALgAECgYJEAAAAA==.',
Ax='Axhure:BAAALgAECgEJAQAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMSAAYJgBZfOAB1AQASAAUJgBZfOAB1AQATAAEJAADvVwAAAAAuAAQKfyEAAhIACAlFIWEVAPsCABIACAlFIWEVAPsCAAAA.Balddrex:BAAALgAECgQJBAAAAA==.Balefire:BAACLgAFFH8HAAIOAAQJQBJQSwAjAQAOAAQJQBJQSwAjAQAuAAQKfysAAw4ACQlPHVEbAHsCAA4ACQlPHVEbAHsCABAAAgntGGE2AEIAAAAA.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgADCgcJFgABLgAECgkJLAAUAMEPAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECggJEQAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn8+AAIDAAkJxSHPEQDqAgADAAkJxSHPEQDqAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAACLgAFFH8IAAINAAQJ1BK2HQAYAQANAAQJ1BK2HQAYAQAuAAQKf0QAAg0ACQk+Hl0IAMQCAA0ACQk+Hl0IAMQCAAAA.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgAECgQJBAAAAA==.Bluewaffles:BAAALgAECgMJBQABLgAECgUJBwAPAAAAAA==.',
Bo='Borealzombie:BAAALgAECgYJCQABLgAECgkJJgAVAN8cAA==.Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8gAAIWAAcJvx0BBAAwAgAWAAcJvx0BBAAwAgAuAAQKfzIAAhYACQnkJA0DADEDABYACQnkJA0DADEDAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAXAFwZAA==.Brewthane:BAAALgAECgYJBgAAAA==.Brimara:BAAALgAFFAEJAgAAAA==.Brunomirror:BAAALgAECgkJDwABLgAFFAcJGgADAL4XAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQABLgAECggJFgAUAKscAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJOgABACkSAA==.Bunsen:BAAALgAECgEJAQABLgAFFAQJEQAYAEcdAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8jAAQZAAgJnyAMBwB+AgAZAAgJjSAMBwB+AgAaAAcJTx1jEgC4AQAHAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMCAAYJehnygAB4AQACAAYJTRnygAB4AQAVAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYhd9KwCmAQANAAcJBBV9KwCmAQAbAAcJkRexSgBaAQAcAAIJ+gANOwAYAAAAAA==.Capz:BAACLgAFFH8uAAMZAAcJ4iApAABHAgAZAAcJHSApAABHAgAHAAUJqCJVBwB3AQAuAAQKfyYAAxkACQnRIzwDANsCABkACAkCJTwDANsCAAcACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJDAAAAA==.Cassius:BAAALgAECgEJAgAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECggJCwAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECggJDwAAAA==.Ceezinator:BAAALgAECgQJBAAAAA==.Cefteldore:BAAALgADCgcJBwAAAA==.Celebrïmbor:BAAALgAECgMJAgAAAA==.',
Ch='Chair:BAAALgAECggJDQABLgAFFAQJEAADAEoUAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chokehold:BAAALgADCgMJAwAAAA==.Chopperr:BAAALgAECgQJBAAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8QAAIDAAQJShQJTwA8AQADAAQJShQJTwA8AQAuAAQKfz4AAgMACQnDIAYOAAUDAAMACQnDIAYOAAUDAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8QAAIQAAYJ8RFlAwB4AQAQAAYJ8RFlAwB4AQAuAAQKf0gAAhAACQlhJUwAAFcDABAACQlhJUwAAFcDAAAA.Clow:BAABLgAECn8cAAMHAAgJJyLMGgB1AgAHAAcJqiPMGgB1AgAZAAMJaB72KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQABLgAECggJGAADAEwLAA==.Coolcrush:BAABLgAECn8zAAMdAAkJTyWBAQBeAwAdAAkJTyWBAQBeAwAeAAYJ9iH3GADXAQAAAA==.Corgnelius:BAAALgADCgYJDAAAAA==.Corven:BAACLgAFFH8YAAIOAAcJVxbYFADtAQAOAAcJVxbYFADtAQAuAAQKf04AAw4ACQlPI98EAD0DAA4ACQlPI98EAD0DABcAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwAAAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJBAABLgAECgkJJAARAN0XAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgkJEgAAAA==.Cryovox:BAAALgAECgQJBAAAAA==.Crôwley:BAAALgAECgQJCQAAAA==.',
Cu='Cumazzing:BAACLgAFFH8dAAICAAgJ/CJtAQDlAgACAAgJ/CJtAQDlAgAuAAQKfyoAAgIACQmJJrYCAK4DAAIACQmJJrYCAK4DAAAA.',
Da='Dadrin:BAAALgADCgkJLwAAAA==.Daedyxes:BAABLgAECn84AAITAAkJ3hlPCwBQAgATAAkJ3hlPCwBQAgAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Daní:BAAALgAECgQJBQAAAA==.Darfretail:BAABLgAECn8rAAIHAAkJhR5BCADVAgAHAAkJhR5BCADVAgAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgQJCQAAAA==.Daygath:BAACLgAFFH8HAAIfAAIJmAq1PwB6AAAfAAIJmAq1PwB6AAAuAAQKfzEAAh8ACQlvFSsaAAMCAB8ACQlvFSsaAAMCAAAA.',
De='Deadlyiris:BAABLgAECn8vAAMZAAkJ3yJpAgAXAwAZAAkJ3yJpAgAXAwAHAAYJHxCZSgB7AQABLgAFFAQJEQAYAEcdAA==.Deatharin:BAAALgAECgYJDQAAAA==.Decompose:BAAALgAECgEJAwAAAA==.Demonbulio:BAABLgAECn81AAIBAAkJFBZPDwAgAgABAAkJFBZPDwAgAgAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAXAFwZAA==.Demonlorrd:BAAALgADCgEJAQABLgAECgQJEAAPAAAAAA==.Demonskitten:BAABLgAECn8fAAIXAAkJXBlQBAA8AgAXAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgAECgEJAQAAAA==.Descendantt:BAAALgADCgIJAgAAAA==.Devilbullet:BAAALgADCgIJAwAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn84AAICAAkJtxSkVgC8AQACAAkJtxSkVgC8AQAAAA==.Dithehealer:BAABLgAECn8jAAMVAAkJYCAqAwDfAgAVAAkJYCAqAwDfAgACAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.Divinecandie:BAAALgAECgEJAQAAAA==.',
Dk='Dkdi:BAAALgAECgkJEQAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAIDAAYJQR6ZcQDwAQADAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgkJKQAgANAUAA==.Doogie:BAAALgAECgEJBQAAAA==.Dortak:BAAALgADCgQJBAABLgAECgUJDwAPAAAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAPAAAAAA==.Dragømir:BAAALgAECgEJAQABLgAFFAMJAwAPAAAAAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8XAAMKAAYJoR7pAQB9AQAKAAUJBCHpAQB9AQALAAQJyx3DHABbAQAuAAQKfysAAwoACQkmJQcBAF0DAAoACAmKJQcBAF0DAAsACQkqJC8DAD0DAAAA.Drenamai:BAABLgAECn8hAAIUAAkJMBPSNgD3AQAUAAkJMBPSNgD3AQAAAA==.Drewetta:BAABLgAECn82AAINAAkJzxCNHwC+AQANAAkJzxCNHwC+AQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.Durbana:BAAALgAECgUJCgAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.Duskfire:BAAALgAECgEJAQAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgYJEgAAAA==.',
Ed='Edrocz:BAEALgAECgcJAQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8XAAICAAUJwSaDEADBAQACAAUJwSaDEADBAQAuAAQKfzoAAgIACQkGJq4BAMgDAAIACQkGJq4BAMgDAAEuAAUUCAkdAAIA/CIA.',
El='Elandin:BAAALgAECggJDwAAAA==.Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8QAAIhAAcJhQaHDgCLAQAhAAcJhQaHDgCLAQAuAAQKfxYAAiEACQmBDSEmAMgBACEACQmBDSEmAMgBAAAA.Elvwyr:BAAALgAECgUJBQAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8NAAMfAAYJcRh3IQALAQAfAAUJlRd3IQALAQAYAAEJ9wh9cABIAAAuAAQKfyAAAx8ACAkkHtkTAIACAB8ACAkkHtkTAIACABgABAk3Cat1ALoAAAAA.Emmy:BAABLgAECn8UAAIGAAYJxyAuKgCiAQAGAAYJxyAuKgCiAQAAAA==.Emogothbabe:BAAALgAECgUJBQAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAABLgAFFH8GAAMSAAMJGh7regD+AAASAAMJGh7regD+AAAiAAEJNB4YHwBZAAABLgAFFAYJFwABAPMeAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQABAAQJqB30AQB7AQAjAAYJDRY4KQBqAQAMAAEJECe3AwB2AAAuAAQKfz8AAwEACQl9JXMAAOgDAAEACQl8JXMAAOgDACMACQm1IkUFACwDAAAA.Eneldenes:BAAALgAFFAEJAQAAAA==.Enjoyer:BAAALgAECggJEgABLgAECgkJDwAPAAAAAA==.',
Er='Ereitherla:BAABLgAECn8zAAIUAAgJGQzOXgB+AQAUAAgJGQzOXgB+AQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAECgYJEQAAAA==.',
Ev='Evanthe:BAAALgADCgEJAQAAAA==.',
Ex='Excalibear:BAABLgAECn8vAAIEAAkJPRaPIwDeAQAEAAkJPRaPIwDeAQABLgAFFAUJEwADAL4gAA==.',
Ey='Eydis:BAAALgADCgkJDgAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Farc:BAAALgAECgUJBQAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECgcJCgAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Felryno:BAAALgADCgQJBAAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fircey:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.Fistbroz:BAABLgAECn8eAAMkAAkJ8xW3EADNAQAkAAkJFBS3EADNAQAcAAcJDxW3EgB/AQABLgAFFAcJHQAdAGkPAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAISAAkJPxjkQQD2AQASAAkJPxjkQQD2AQAAAA==.Fleredil:BAABLgAECn9IAAMWAAkJqSEhBQD/AgAWAAkJqSEhBQD/AgAGAAgJzRpiEABWAgAAAA==.Flingernle:BAAALgAECgEJAwAAAA==.Floista:BAAALgAECggJDQAAAA==.Floistas:BAABLgAFFH8LAAIUAAMJWBOZUwDrAAAUAAMJWBOZUwDrAAAAAA==.',
Fo='Forepray:BAAALgAFFAEJAQABLgAFFAcJGQAHAIoXAA==.Forger:BAABLgAECn8zAAIaAAkJmhbODQACAgAaAAkJmhbODQACAgAAAA==.Forsakey:BAAALgAECgUJBQABLgAFFAUJDwAbAMsaAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8UAAQSAAUJaiRKOAB2AQASAAQJaiRKOAB2AQAiAAQJLheIDQATAQATAAEJAAC3VgAAAAAuAAQKfzYABBIACQkFJHAMADcDABIACQkDJHAMADcDACIACAlhIdwGACACABMAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAECgkJPgAOAHsiAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostitution:BAAALgAECgEJAQAAAA==.Frostycheeks:BAACLgAFFH8PAAISAAQJGxsrTgBGAQASAAQJGxsrTgBGAQAuAAQKfzUAAhIACAkKI7IdAI0CABIACAkKI7IdAI0CAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQjAAgJ0CKoHQBYAgAjAAgJlyKoHQBYAgAMAAIJqiNZJgBhAAABAAIJTxjdXgBAAAAAAA==.Future:BAAALgAECgYJDwABLgAFFAMJCAAXACwbAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaerlan:BAAALgAECgUJDQAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgAECgQJBgAAAA==.',
Gh='Ghettox:BAAALgAECgUJBQAAAA==.Ghostblades:BAACLgAFFH8ZAAMSAAYJFxp7KAClAQASAAYJFxp7KAClAQAiAAEJAABeKAAAAAAuAAQKfysAAxIACQmBIYwVAL0CABIACQmBIYwVAL0CACIAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.Ghuleh:BAAALgAECgEJAQAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBQABLgAFFAcJGgAWALAaAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAABLgAFFH8FAAIYAAQJjBAzMAAKAQAYAAQJjBAzMAAKAQABLgAFFAUJEwADAL4gAA==.Gorm:BAAALgAECgEJAQABLgAFFAIJBAAPAAAAAA==.',
Gr='Gratata:BAAALgAECgMJBQABLgAECgkJJAARAN0XAA==.Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAABLgAECn8XAAIlAAkJMQ7KBwDOAQAlAAkJMQ7KBwDOAQABLgAECgkJSQACADoiAA==.Grinny:BAABLgAECn9JAAMCAAkJOiKBCAAeAwACAAkJOiKBCAAeAwAEAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Gu='Gunna:BAAALgAECgEJAQABLgAFFAMJCAAXACwbAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8jAAICAAkJhgwzcQCBAQACAAkJhgwzcQCBAQABLgAFFAQJEQAYAEcdAA==.Havochunter:BAABLgAECn8WAAIUAAcJqxzGNQD6AQAUAAcJqxzGNQD6AQAAAA==.',
He='Heidegger:BAAALgAECgQJCQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8pAAIgAAkJ0BQuCADwAQAgAAkJ0BQuCADwAQAAAA==.Heriod:BAAALgAECgEJAgAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgADCgcJDQAAAA==.Holywráth:BAAALgAECgUJDAAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECggJEQAAAA==.Hunterdh:BAABLgAECn8uAAIUAAgJmwlzbwBWAQAUAAgJmwlzbwBWAQAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8ZAAIHAAcJihe2BgDVAQAHAAcJihe2BgDVAQAuAAQKfzAAAgcACQkIIQELAK8CAAcACQkIIQELAK8CAAAA.',
Ic='Icecandie:BAAALgAECgYJEgAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAYJFwAKAKEeAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJQgAFAGQUAA==.',
Im='Imistmypants:BAABLgAECn8kAAIRAAkJ3RdMEgB6AgARAAkJ3RdMEgB6AgAAAA==.',
In='Infinitevoid:BAAALgADCgUJDAAAAA==.Innervatez:BAABLgAFFH8YAAIbAAgJ4hz9AgDqAgAbAAgJ4hz9AgDqAgAAAA==.Inspectda:BAABLgAECn8VAAIOAAgJgwcadgBxAQAOAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAIJAAgJJBsRCwAjAgAJAAgJJBsRCwAjAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn81AAIDAAkJORa+QAAUAgADAAkJORa+QAAUAgAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn8/AAIDAAkJpCQ1CQAtAwADAAkJpCQ1CQAtAwAAAA==.Jarten:BAABLgAECn8sAAIiAAkJZSJvAQAdAwAiAAkJZSJvAQAdAwAAAA==.Jaylebate:BAABLgAECn88AAMSAAkJtyC0HACSAgASAAkJeh+0HACSAgATAAgJ4Rw5DAA+AgAAAA==.',
Je='Jerrenn:BAABLgAECn8eAAMCAAkJqBhqPAAHAgACAAgJ3hdqPAAHAgAEAAIJLwnodABaAAAAAA==.Jesseatamer:BAABLgAECn8vAAIUAAkJ7CVfAQB/AwAUAAkJ7CVfAQB/AwAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jortak:BAAALgAECggJEwABLgAECgkJPAASALcgAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwAPAAAAAA==.',
Ju='Judge:BAAALgAECgEJAgAAAA==.Julesx:BAAALgAFFAEJAQAAAA==.Justar:BAAALgADCgMJBQAAAA==.',
['Jë']='Jësus:BAAALgAECgcJBwAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAABLgAECn8UAAMgAAgJGhlCDwBZAQAUAAgJbBYsTgCrAQAgAAcJ/BNCDwBZAQABLgAFFAMJBAAPAAAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAISAAkJVBZfQgD0AQASAAkJVBZfQgD0AQAAAA==.Karen:BAAALgAECgQJBwABLgAECgkJOAACALcUAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJAwAAAA==.Kastia:BAAALgAECgQJCAAAAA==.Katrynwel:BAABLgAECn8YAAIDAAgJTAvHgABvAQADAAgJTAvHgABvAQAAAA==.Katsumi:BAAALgADCgkJQgAAAA==.Kaylestia:BAAALgAECgkJCQAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCgUJEwAAAA==.Kettama:BAAALgAECgEJAQAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.Khold:BAABLgAECn8UAAMSAAgJIhdUTQDTAQASAAcJkRlUTQDTAQAiAAcJTQYAGwDmAAAAAA==.',
Ki='Killalltoday:BAABLgAECn8/AAMYAAkJPhAARgCIAQAYAAgJMxEARgCIAQAmAAgJNg4HEgCFAQAAAA==.Kilon:BAAALgAFFAEJAQAAAA==.Kirkk:BAAALgAECgEJAQAAAA==.Kivareous:BAAALgAFFAIJAwAAAA==.Kixarea:BAAALgADCgkJDQABLgAFFAIJAwAPAAAAAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAABLgAECn8ZAAITAAgJsxbeEwDIAQATAAgJsxbeEwDIAQAAAA==.Knixx:BAACLgAFFH8VAAMWAAUJswr7HAD1AAAWAAQJYQn7HAD1AAAFAAUJeAhtKwDSAAAuAAQKf0IABBYACQnfGXUMAIQCABYACQnfGXUMAIQCAAYABwk6GGQbAAECAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIeAAkJUxFIJQB6AQAeAAkJUxFIJQB6AQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIRAAkJmhi8EwBsAgARAAkJmhi8EwBsAgAAAA==.Koyya:BAAALgAFFAIJAwAAAA==.',
Ku='Kufoo:BAABLgAECn8/AAMHAAkJeCZbAQBpAwAHAAkJoSVbAQBpAwAaAAgJ1CUSBADhAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJCAAXACwbAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8gAAIMAAkJkxepBQA5AgAMAAkJkxepBQA5AgAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
['Ké']='Kéndra:BAAALgAECgMJAwAAAA==.',
La='Ladiable:BAAALgAECgYJCQABLgAFFAYJFQAUAF8eAA==.Laggyboi:BAAALgAECgYJBgAAAA==.Lansseax:BAAALgAECgcJDQAAAA==.Laraelin:BAAALgADCgYJBgAAAA==.Lascerette:BAAALgAECgQJBAAAAA==.Law:BAAALgADCgcJCQAAAA==.Layez:BAAALgAECgEJAQABLgAFFAIJAwAPAAAAAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Leo:BAAALgAECgEJAQAAAA==.Lethe:BAAALgAECgcJCAABLgAFFAcJEAAhAIUGAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAAUAAAbAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgIJBAAPAAAAAA==.Lilyröse:BAAALgAECgIJBAAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn86AAIOAAkJFRtpJgA+AgAOAAkJFRtpJgA+AgAAAA==.Lohmi:BAAALgAECgYJCwAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAACLgAFFH8JAAINAAQJ6gLjMACoAAANAAQJ6gLjMACoAAAuAAQKfywAAg0ACQkIC00pAHkBAA0ACQkIC00pAHkBAAAA.',
Lu='Luania:BAAALgAECgQJCgAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lurtz:BAABLgAECn8YAAIUAAYJ4BamZwBnAQAUAAYJ4BamZwBnAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgEJAQAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.Lyzzardkng:BAAALgAECgcJDQAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAYJDQAfAHEYAA==.',
Ma='Maango:BAAALgAECgkJCAAAAA==.Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn9EAAMDAAkJOBqCJgB7AgADAAkJOBqCJgB7AgAnAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgQJCAAAAA==.Malkala:BAAALgAECgUJBQAAAA==.Mamadeezy:BAAALgAECgIJAwAAAA==.Manical:BAAALgAECgYJEAAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAUJEgASAI8WAA==.Maxgoon:BAABLgAECn8WAAIOAAcJwgzVcwB2AQAOAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQABLgAECggJDAAPAAAAAA==.',
Me='Megumin:BAABLgAECn8cAAQDAAgJdhM2YgC0AQADAAgJ7hI2YgC0AQAnAAMJeA/QCwCaAAAoAAIJ3xNtGgBEAAABLgAECgkJLgACACogAA==.Mellisandria:BAAALgAECgcJEQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn81AAIeAAkJmCNIAgA3AwAeAAkJmCNIAgA3AwAAAA==.Merriska:BAACLgAFFH8FAAMEAAIJxyAgNACSAAAEAAIJxyAgNACSAAACAAEJHRFPpgBFAAAuAAQKfxsAAwIACQk1IqElAJACAAIACAlWI6ElAJACAAQACAm7IJsTAHUCAAEuAAUUBQkSABEADSQA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECggJEAABLgAECgkJBgAPAAAAAA==.Misseslovett:BAAALgAECgUJCQAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8aAAIkAAcJQg+nBwBiAQAkAAcJQg+nBwBiAQAuAAQKfz0AAiQACQnPHLsGAIECACQACQnPHLsGAIECAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAACLgAFFH8JAAIEAAQJpyMyEQCdAQAEAAQJpyMyEQCdAQAuAAQKfzMAAwQACQk2JrIBAGgDAAQACQk2JrIBAGgDAAIAAQlhGd1eAUcAAAAA.Morgause:BAAALgAECggJEwAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.',
Mu='Muirdin:BAABLgAECn8gAAIUAAgJpBEiVwCSAQAUAAgJpBEiVwCSAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMZAAkJYCKlCQBGAgAZAAkJbCGlCQBGAgAHAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAECgkJPgAOAHsiAA==.',
Na='Naanomage:BAAALgAECgYJEgAAAA==.Nacht:BAAALgADCgEJAQABLgAFFAUJDwAIANggAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAABLgAECn8+AAMOAAkJeyIKCgD7AgAOAAgJeyIKCgD7AgAQAAEJAAD2XABYAAAAAA==.Nemoralia:BAAALgAECgcJDAAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMjAAkJrxzhIQCGAgAjAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn8+AAIKAAkJtw3oBwCsAQAKAAkJtw3oBwCsAQAAAA==.',
No='Noiire:BAAALgAFFAEJAgABLgAFFAcJEAAhAIUGAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8UAAIWAAUJ/CRzBQAIAgAWAAUJ/CRzBQAIAgAuAAQKfzUAAhYACQnzJT0BAG8DABYACQnzJT0BAG8DAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn86AAMBAAkJKRJrFgDEAQABAAkJKRJrFgDEAQAjAAMJcAQm+ABEAAAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAABLgAECn8XAAMRAAkJcA6eQwBDAQARAAgJjgueQwBDAQAdAAQJSxFGPwD0AAAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAYJGwAhAHwfAA==.',
Oa='Oakly:BAACLgAFFH8JAAIbAAMJNxOTOgC9AAAbAAMJNxOTOgC9AAAuAAQKfy4AAhsACAk0HpUSAK8CABsACAk0HpUSAK8CAAAA.',
Ob='Obsidian:BAAALgAECggJEAABLgAFFAQJCQAEAKcjAA==.',
On='Onaroll:BAABLgAFFH8GAAIRAAMJrgfJPQCMAAARAAMJrgfJPQCMAAABLgAFFAcJFwAbAL4SAA==.Onehotelf:BAAALgAECgcJEgAAAA==.',
Oo='Ooyagoddess:BAABLgAECn8UAAIGAAYJJRTjKwBeAQAGAAYJJRTjKwBeAQAAAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAYJFgAUALYeAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8gAAIdAAYJ2SL8GgDLAQAdAAYJ2SL8GgDLAQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAIJAgABLgAFFAYJFwAKAKEeAA==.Pann:BAAALgAECgEJAQABLgAECgYJEgAPAAAAAA==.Papatiny:BAAALgAECgYJBgAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn8xAAIfAAgJshe0IADQAQAfAAgJshe0IADQAQAAAA==.Pawsa:BAABLgAECn88AAMeAAgJmh0jDQBcAgAeAAgJmB0jDQBcAgAdAAgJFhpGFAANAgAAAA==.Pawsome:BAAALgAECgQJBAABLgAECggJMQAfALIXAA==.Pawthetic:BAACLgAFFH8XAAIbAAcJvhILDwDzAQAbAAcJvhILDwDzAQAuAAQKfy8AAxsACQkDITwDAGEDABsACQkDITwDAGEDAA0ACQmRGikOAG4CAAAA.',
Pe='Peelforheals:BAACLgAFFH8KAAIFAAIJLRDaNwCCAAAFAAIJLRDaNwCCAAAuAAQKfykAAwUACAlqFBocALUBAAUABwm7FRocALUBABYABwk9GGAjAKUBAAAA.Penguindemic:BAABLgAECn8rAAIOAAkJaia3AQB3AwAOAAkJaia3AQB3AwAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJJAARAN0XAA==.Pep:BAABLgAECn8fAAMdAAkJ1x0SDAB4AgAdAAkJ1x0SDAB4AgARAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgAECgcJBwAAAA==.Petruccius:BAACLgAFFH8IAAINAAQJ/BB6JgDnAAANAAQJ/BB6JgDnAAAuAAQKfyMAAg0ACAn/HJoPAFsCAA0ACAn/HJoPAFsCAAAA.Pewpewlepew:BAAALgAECggJEgAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgkJJAAjALITAA==.Phaeku:BAABLgAECn8kAAIjAAkJshPHMAD4AQAjAAkJshPHMAD4AQAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJEAABLgAECgkJMwAdAE8lAA==.Powermonk:BAAALgAECgQJBwAAAA==.',
Pr='Prayre:BAAALgADCgkJEgAAAA==.Prey:BAAALgAECgUJCAAAAA==.Prospa:BAAALgAECgQJBwAAAA==.Prumper:BAACLgAFFH8IAAIDAAQJMgmIhwC9AAADAAQJMgmIhwC9AAAuAAQKf0EAAgMACQlUH8gkAIICAAMACQlUH8gkAIICAAAA.',
Py='Pyric:BAAALgAECgEJBAAAAA==.',
Qu='Quesoblanco:BAAALgAECgkJCAAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgYJCwAAAA==.Qybxboogiemo:BAAALgAECgEJAgAAAA==.Qybxboogietk:BAAALgAECgEJAQAAAA==.',
Ra='Rabid:BAAALgAECgEJAwAAAA==.Raghallov:BAAALgADCggJCgAAAA==.Ragingstorm:BAAALgADCgIJAwAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8wAAISAAkJPx34HQCMAgASAAkJPx34HQCMAgAAAA==.Ravokkc:BAAALgADCgMJAwAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgkJEwAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Regena:BAABLgAECn9CAAQFAAkJZBTrHgDIAQAFAAkJawzrHgDIAQAGAAkJUhS2HwC3AQAWAAcJ3AgcPgAQAQAAAA==.Relyssa:BAAALgAECgcJDgAAAA==.Remorse:BAACLgAFFH8YAAIaAAcJXRpsBgC+AQAaAAcJXRpsBgC+AQAuAAQKf0sAAhoACQnxIj4CACADABoACQnxIj4CACADAAAA.Required:BAAALgAFFAMJAwABLgAFFAcJHwAjACUcAA==.Retro:BAABLgAECn8hAAIfAAcJFQdNUwDaAAAfAAcJFQdNUwDaAAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8tAAMbAAkJ+x2yDADvAgAbAAkJ+x2yDADvAgANAAkJoxfUEgA0AgABLgAFFAIJAwAPAAAAAA==.Rim:BAABLgAECn9EAAIYAAkJfB5ECgAFAwAYAAkJfB5ECgAFAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8QAAIDAAQJKheuUAA6AQADAAQJKheuUAA6AQAuAAQKfyoAAgMACQlIITAdAKYCAAMACQlIITAdAKYCAAAA.',
Ro='Ronard:BAACLgAFFH8HAAISAAIJthusvQCUAAASAAIJthusvQCUAAAuAAQKf0kAAhIACQkQJqUDAGMDABIACQkQJqUDAGMDAAAA.Ronfar:BAACLgAFFH8WAAImAAYJxxSSBABrAQAmAAYJxxSSBABrAQAuAAQKf0oAAiYACQnEIhsBADIDACYACQnEIhsBADIDAAAA.',
Ru='Rukidingme:BAAALgAECgYJEQAAAA==.Rumonkingme:BAAALgADCgQJAwAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Rustyglass:BAAALgAECgEJAQAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8wAAICAAkJbQ3XXACtAQACAAkJbQ3XXACtAQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAABLgAECn8XAAICAAgJMgq6lQA8AQACAAgJMgq6lQA8AQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCgkJEAABLgAECgkJLAAiAGUiAA==.',
Sc='Schrutes:BAAALgADCgEJAQAAAA==.Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAIdAAcJVBRCLAB+AQAdAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQbAAgJdhy3JQAiAgAbAAcJ1By3JQAiAgANAAYJ+R6FHwADAgAkAAEJGQaYNQAfAAAAAA==.Scubowsuit:BAAALgAECgYJBwAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAECgkJDQAAAA==.Selen:BAABLgAECn8/AAIEAAkJmiHxBQAmAwAEAAkJmiHxBQAmAwAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Semballin:BAAALgAECgEJAwAAAA==.Semdogg:BAAALgAECgEJAQABLgAECgkJNwABAKQhAA==.Semtex:BAAALgAECgEJAQAAAA==.Seråphiel:BAABLgAECn8eAAIUAAcJCQXuogDsAAAUAAcJCQXuogDsAAAAAA==.Seswatha:BAACLgAFFH8TAAIDAAUJviB9GwBdAQADAAUJviB9GwBdAQAuAAQKfzEAAgMACQmpIkgLABoDAAMACQmpIkgLABoDAAAA.',
Sh='Shadowbaron:BAAALgAECgQJBwAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAABLgAECn8cAAMYAAkJWiILCgAIAwAYAAkJWiILCgAIAwAfAAUJ1xjhTgDqAAABLgAFFAYJGQAEAKUcAA==.Shamdi:BAAALgADCgYJBgAAAA==.Shawti:BAAALgADCgcJCAAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAAALgAECgkJDwAAAA==.Shocktop:BAABLgAECn8fAAImAAkJrSIuAQAuAwAmAAkJrSIuAQAuAwAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAPAAAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAPAAAAAA==.Shådowfire:BAAALgAECgcJBwAAAA==.Shìft:BAACLgAFFH8FAAIbAAMJDQyqQACpAAAbAAMJDQyqQACpAAAuAAQKfzMAAhsACQlXGRgUAKICABsACQlXGRgUAKICAAAA.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgAECgEJAQAAAA==.Sillynanny:BAAALgAECgUJCQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skuùuß:BAAALgADCgMJAwAAAA==.Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAABLgAECn8YAAQBAAUJphk9KgAZAQABAAUJQhg9KgAZAQAMAAMJPRdIGQDEAAAjAAIJKA3dyABmAAABLgAECggJGAAUAFQbAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8eAAIkAAgJ5iLvBQCXAgAkAAgJ5iLvBQCXAgAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8rAAQoAAgJqiWfAgBmAgADAAgJjyB+LQC8AgAoAAYJ0iKfAgBmAgAnAAQJcx84BgBBAQABLgAFFAMJCAAXACwbAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokinontech:BAAALgAECgEJAQAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIZAAkJCgvUHQBjAQAZAAkJCgvUHQBjAQAAAA==.Smugs:BAABLgAFFH8HAAIgAAQJ+g9VEwAeAQAgAAQJ+g9VEwAeAQAAAA==.Smugxl:BAABLgAECn8YAAIgAAkJJBxBAwCUAgAgAAkJJBxBAwCUAgAAAA==.',
So='Solid:BAAALgAECgEJAQAAAA==.Sonicberger:BAAALgADCgQJBAABLgAECgkJKQASADUcAA==.Sonicbergger:BAAALgAECgYJCAABLgAECgkJKQASADUcAA==.Soniclavv:BAAALgAECgcJBwAAAA==.Sonicpoe:BAAALgADCgkJDAABLgAECgkJKQASADUcAA==.Sonícberger:BAABLgAECn8pAAMSAAkJNRziKQBRAgASAAkJNRziKQBRAgATAAQJTw+rNQC1AAAAAA==.Soulcaliber:BAAALgAECgEJAgAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
Sq='Squee:BAAALgAFFAEJAQABLgAFFAUJEgARAA0kAA==.',
St='Stain:BAAALgAECgUJDgAAAA==.Stealth:BAAALgAECggJDgABLgAFFAIJAwAPAAAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stillheart:BAAALgAECgkJAQAAAA==.Stith:BAAALgADCgYJCAAAAA==.Stkinbck:BAABLgAECn8zAAIhAAgJyA7sIQB2AQAhAAgJyA7sIQB2AQAAAA==.Stonehenge:BAACLgAFFH8RAAIYAAQJRx3oIABRAQAYAAQJRx3oIABRAQAuAAQKfyIAAhgACQmzIdYOANICABgACQmzIdYOANICAAAA.Stonepalm:BAAALgADCgkJKQAAAA==.Stratan:BAABLgAECn8WAAMVAAYJjQoeKQDCAAAVAAYJZAoeKQDCAAACAAYJDAZE7gC/AAAAAA==.',
Su='Subbzero:BAAALgADCgcJEgAAAA==.Suffer:BAACLgAFFH8IAAMXAAMJLBsyDACpAAAOAAMJExmyaADgAAAXAAIJzRsyDACpAAAuAAQKfxoABA4ACAmsI+YSALACAA4ACAmQI+YSALACABcAAwnOI2sbANEAABAAAgn0GJFjAEcAAAAA.Sukuna:BAAALgAECgQJBAAAAA==.Sundermere:BAAALgAECgEJAgABLgAECgEJAwAPAAAAAA==.Sunlight:BAAALgAECgQJBAAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8eAAICAAgJ/iDTIwCZAgACAAgJ/iDTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8dAAQdAAcJaQ8sDgBDAQAdAAUJLA0sDgBDAQAeAAUJJwxKEAD+AAARAAIJ0wANYgAiAAAuAAQKfzkAAx4ACQk3HUQRACUCAB0ACAliHXkTAFUCAB4ACQmDGUQRACUCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.',
['Sä']='Sätansangel:BAAALgAECgQJBQAAAA==.',
Ta='Tabbz:BAABLgAECn8sAAMfAAkJvRkrGAAUAgAfAAkJvRkrGAAUAgAYAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgAFFAEJAQAAAA==.Tallyhochick:BAACLgAFFH8FAAIUAAIJzANSggB9AAAUAAIJzANSggB9AAAuAAQKfy8AAhQACQlcDHZIALwBABQACQlcDHZIALwBAAAA.Taman:BAABLgAECn8iAAMYAAcJbRsvJQAiAgAYAAcJbRsvJQAiAgAfAAcJOBamKADPAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAABLgAECn8XAAIeAAgJdAy+LgBCAQAeAAgJdAy+LgBCAQAAAA==.Telean:BAAALgAFFAEJAQAAAA==.Telkon:BAAALgAECggJCAAAAA==.Tellesto:BAABLgAECn8wAAMIAAkJpByjEQAaAgAIAAkJqxqjEQAaAgAUAAMJNRf+0ACUAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECgkJNgANAM8QAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgAECgIJAwAAAA==.Thebigonion:BAAALgAECgQJBQAAAA==.',
Ti='Tibberino:BAAALgAECggJDwAAAA==.Ticklantical:BAAALgAECggJCAABLgAECgkJRAADADgaAA==.Tinydeath:BAAALgAECgcJBwABLgAECgkJKwAUADMhAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8sAAMeAAkJLBxkEgAYAgAeAAkJ3BtkEgAYAgAdAAUJghqOJgB1AQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwAUADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMUAAkJMyEFDwDDAgAUAAkJECAFDwDDAgAIAAQJtxA9OADwAAAAAA==.',
To='Toko:BAACLgAFFH8cAAIUAAYJJSIsAgB9AQAUAAYJJSIsAgB9AQAuAAQKfykAAxQACQkjIuIIAAUDABQACQkjIuIIAAUDACAAAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMiAAkJlhp8BwAOAgAiAAkJlhp8BwAOAgATAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBQAAAA==.Tourma:BAAALgAFFAEJAgAAAA==.',
Tr='Trapattack:BAAALgAECgQJBgAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECggJDAAPAAAAAA==.Truepatriot:BAACLgAFFH8JAAIEAAMJbxmtKwDCAAAEAAMJbxmtKwDCAAAuAAQKfycAAwQACAmoExMyALcBAAQACAmoExMyALcBABUABQnpEr8nAMsAAAAA.Truexlord:BAABLgAECn8WAAISAAcJewzvmwApAQASAAcJewzvmwApAQAAAA==.Truthes:BAAALgAFFAIJAwAAAA==.Truthez:BAAALgADCgMJBgABLgAFFAIJAwAPAAAAAA==.Truths:BAAALgAECgcJDgABLgAFFAIJAwAPAAAAAA==.Truthsx:BAABLgAECn8nAAMXAAgJGiBUBQAlAgAXAAgJph9UBQAlAgAOAAUJchoUggAwAQABLgAFFAIJAwAPAAAAAA==.Truthz:BAAALgADCgYJBgABLgAFFAIJAwAPAAAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgQJBAAAAA==.Tygerkillz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAFFAEJAQAAAA==.Tyraell:BAABLgAECn8sAAMEAAkJkR2KDQCvAgAEAAkJkR2KDQCvAgACAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAACLgAFFH8FAAITAAMJdxkAKgCSAAATAAMJdxkAKgCSAAAuAAQKfxsAAhMACQlEH10FAOsCABMACQlEH10FAOsCAAEuAAUUBgkcABQAJSIA.',
Ud='Udor:BAABLgAECn8aAAIUAAgJLgxUZABvAQAUAAgJLgxUZABvAQAAAA==.',
Um='Umbrae:BAABLgAECn87AAMGAAkJ+hydFQAYAgAGAAgJOBydFQAYAgAWAAEJ4wcLeQA8AAAAAA==.',
Up='Upies:BAABLgAECn8VAAILAAgJ6gIRWQDCAAALAAgJ6gIRWQDCAAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAABLgAECn8aAAIOAAYJ5Qv6nAD/AAAOAAYJ5Qv6nAD/AAAAAA==.',
Va='Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIOAAMJjwjXggCuAAAOAAMJjwjXggCuAAAuAAQKfyMAAw4ACQnGGrAdAGsCAA4ACQnGGrAdAGsCABAAAQn0HnIuAFkAAAAA.Vazro:BAAALgADCgYJBgAAAA==.',
Ve='Veera:BAABLgAECn83AAIfAAkJ6xXfGQAFAgAfAAkJ6xXfGQAFAgAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Vendyr:BAABLgAECn8aAAQXAAgJlCLxBwDOAQAOAAcJQx41LQBZAgAXAAYJsxnxBwDOAQAQAAIJ8AscYABPAAAAAA==.Veyra:BAAALgAECgUJBQAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgQJBwAPAAAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voidvoid:BAAALgAECggJCAABLgAFFAMJBgASAE0XAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorgol:BAABLgAECn8qAAIZAAkJbRlWDQAIAgAZAAkJbRlWDQAIAgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAICAAcJ0hXiZAC3AQACAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8OAAICAAQJlA1mSgAKAQACAAQJlA1mSgAKAQAuAAQKfyIAAgIACAmbHq0jAJoCAAIACAmbHq0jAJoCAAAA.',
We='Weeooeeooeeo:BAAALgAECgUJBQABLgAECgkJOgABACkSAA==.Wellby:BAAALgAECgUJBwAAAA==.Westerin:BAABLgAECn83AAIQAAkJMhyIAgCDAgAQAAkJMhyIAgCDAgAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgkJEAAAAA==.Wimateeka:BAABLgAECn8dAAQVAAcJzh2QDwDMAQAVAAcJzh2QDwDMAQAEAAUJxRIPYQD4AAACAAQJlw2Y3QDRAAAAAA==.Wimatreeka:BAAALgAECgkJEwAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgcJHQAVAM4dAA==.Windfury:BAAALgAECgYJEgABLgAFFAMJCAAXACwbAA==.Windigo:BAACLgAFFH8FAAIiAAMJ3gUaFgC2AAAiAAMJ3gUaFgC2AAAuAAQKfxwABCIABgnvFIYdAM4AABMABgnEEYInAAIBACIABAmWFoYdAM4AABIAAwlyCE8NAYsAAAAA.Winginit:BAABLgAECn8WAAMLAAkJUBloDgB1AgALAAkJUBloDgB1AgAJAAcJTAmZIQDaAAABLgAFFAcJFwAbAL4SAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAECgYJCAAAAA==.Wootangz:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.Worthyreaper:BAAALgAECgEJAQAAAA==.',
Wr='Wrastelas:BAAALgAECgQJBwAAAA==.',
Wu='Wurkim:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.',
Wy='Wylder:BAAALgAECgQJBAABLgAFFAUJGQASAO8hAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xanto:BAAALgAFFAEJAQABLgAFFAcJKAADACweAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xe='Xenôn:BAAALgAECgYJBgAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAgAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJOAACALcUAA==.',
Ye='Yespaladin:BAAALgAFFAEJAQABLgAFFAUJFAAWAPwkAA==.',
Yi='Yiddosh:BAAALgAECgMJDAAAAA==.',
Yo='Yogí:BAACLgAFFH8SAAIYAAYJbhx6DQDgAQAYAAYJbhx6DQDgAQAuAAQKfx0AAxgACAk6I94FABQDABgACAk6I94FABQDACYABAkJDGonAKQAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8SAAMRAAUJDSR6DQAGAgARAAUJDSR6DQAGAgAdAAMJdBtjHADlAAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8tAAMaAAgJXxV8EwCrAQAaAAgJVBR8EwCrAQAHAAIJuhDieQB4AAAAAA==.Zanalia:BAAALgAECggJDAAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeeko:BAAALgAECgUJCAAAAA==.Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8rAAIOAAkJ3g1eSQC5AQAOAAkJ3g1eSQC5AQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zensho:BAAALgAECgYJCQAAAA==.Zeplenith:BAAALgAECgIJAwAAAA==.',
Zi='Zipsion:BAABLgAECn8iAAIUAAkJ/iA+GACJAgAUAAkJ/iA+GACJAgAAAA==.Zithen:BAACLgAFFH8LAAMLAAMJjgz4QAC0AAALAAMJjgz4QAC0AAAJAAEJ0QFYLQAlAAAuAAQKfx4AAgsACQkPGIojAKEBAAsACQkPGIojAKEBAAAA.Zivver:BAABLgAECn8tAAIaAAkJYSK4BADLAgAaAAkJYSK4BADLAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECggJDAAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIEAAgJUR9SGAA6AgAEAAgJUR9SGAA6AgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAABLgAECn8ZAAMCAAcJYBU3gABjAQACAAcJNRI3gABjAQAVAAUJ1BfcHwAIAQAAAA==.',
['Üt']='Üther:BAABLgAECn8uAAMCAAkJKiCdIAB7AgACAAkJHCCdIAB7AgAVAAIJKBw+LwCeAAAAAA==.',
['ßu']='ßubbleøseven:BAABLgAFFH8IAAICAAIJPx1kdgCtAAACAAIJPx1kdgCtAAAAAA==.',
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
