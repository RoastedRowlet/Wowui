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

local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Paladin-Holy','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Hunter-BeastMastery','Warrior-Fury','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Demonology','Unknown-Unknown','Warlock-Destruction','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Paladin-Protection','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Feral','Shaman-Elemental','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Devourer','Druid-Guardian','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane','Rogue-Outlaw',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aachoo:BAAALgADCgEJAQAAAA==.Aairidari:BAABLgAECn9YAAIBAAkJcBZzAwDzAQABAAkJcBZzAwDzAQAAAA==.Aatrox:BAAALgAECgUJBQABLgAECgkJLgACACogAA==.',
Ab='Abruna:BAAALgAECgcJEwABLgAFFAkJIAADAKcUAA==.Abruno:BAACLgAFFH8gAAIDAAkJpxQgKADWAQADAAkJpxQgKADWAQAuAAQKfzAAAgMACQmDIgkQAEgDAAMACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAkJIAADAKcUAA==.',
Ad='Adrasteia:BAAALgADCgQJAQABLgAFFAQJGgADAPoXAA==.Adrians:BAABLgAECn8qAAIDAAkJuxbTPwAdAgADAAkJuxbTPwAdAgAAAA==.Adunea:BAAALgAECggJDQAAAA==.',
Ae='Aeown:BAABLgAECn82AAMCAAgJVw6AhQBkAQACAAgJVw6AhQBkAQAEAAcJpQnySgAQAQABLgAECgkJTAAFAFgVAA==.Aerdis:BAAALgAECgcJEwABLgAECgkJFgAGAIIRAA==.Aery:BAABLgAFFH8FAAIHAAEJeiH8MgBcAAAHAAEJeiH8MgBcAAABLgAFFAcJGQAIADEfAA==.',
Ag='Aggerwator:BAAALgAECgEJAwABLgAECggJHQAJACciAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAFFAIJAgABLgAFFAcJEwAKAKIeAA==.Akkani:BAAALgAECgEJAQAAAA==.',
Al='Alahrî:BAACLgAFFH8GAAILAAMJ2QWTIwCEAAALAAMJ2QWTIwCEAAAuAAQKfzoABAsACQnzEOoWAOEBAAsACQnzEOoWAOEBAAwABgn+DAcOACsBAA0ABwnqCn1EABgBAAAA.Alandira:BAAALgAECgcJCAAAAA==.Alandrìas:BAACLgAFFH8WAAIOAAQJKA+pBADNAAAOAAQJKA+pBADNAAAuAAQKfy0AAg4ACQmcFA4JAN4BAA4ACQmcFA4JAN4BAAAA.Allydari:BAAALgAECgEJAgAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAIPAAkJsB3WBQA9AwAPAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn8+AAILAAkJahd0CQBQAgALAAkJahd0CQBQAgAAAA==.Alyard:BAAALgAECgEJAQABLgAECgkJHgACAKgYAA==.',
Am='Amelya:BAABLgAECn8VAAIDAAcJ2gpyyQD7AAADAAcJ2gpyyQD7AAAAAA==.Amethystia:BAAALgADCgYJBgAAAA==.Amirandis:BAAALgAECgYJDAAAAA==.Amuri:BAABLgAECn8gAAICAAgJyRA4cwCHAQACAAgJyRA4cwCHAQAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJDAAAAA==.Androonatorz:BAACLgAFFH8cAAIEAAgJohizEAC0AQAEAAgJohizEAC0AQAuAAQKfy0AAwQACQkDJV4CAIcDAAQACQkDJV4CAIcDAAIABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAABLgAECn8UAAIQAAcJtgxshwArAQAQAAcJtgxshwArAQAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAAALgAECgYJBgABLgAECgcJAQARAAAAAA==.Ardemus:BAABLgAECn8XAAMSAAYJIBIFGQDaAAASAAYJIBIFGQDaAAAQAAEJYAAYNAEWAAABLgAFFAIJAgARAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Artex:BAAALgAECgEJAgAAAA==.Arveiturace:BAABLgAECn8jAAINAAcJEgZjDQCgAAANAAcJEgZjDQCgAAAAAA==.',
As='Ashborrn:BAACLgAFFH8GAAITAAIJTRd2XgCeAAATAAIJTRd2XgCeAAAuAAQKfxYAAhMABwl3F+UXAPMAABMABwl3F+UXAPMAAAAA.Ashtar:BAABLgAECn8nAAIJAAkJ+RosAwAaAgAJAAkJ+RosAwAaAgAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgAHAJEWAA==.',
Av='Averyi:BAAALgAECgIJAgAAAA==.',
Aw='Awake:BAAALgAECgEJAgAAAA==.Awaken:BAABLgAECn8dAAIDAAgJaiKoGwC2AgADAAgJaiKoGwC2AgAAAA==.Awoomonk:BAABLgAECn8VAAQUAAYJnyJFFwDvAQAUAAYJYyJFFwDvAQAVAAUJ9xmpJwB7AQAHAAEJSBKdtwA3AAAAAA==.',
Ax='Axhure:BAAALgAECgEJAQAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMTAAYJgBZIQwBuAQATAAUJgBZIQwBuAQAWAAEJAACdYQAAAAAuAAQKfyEAAhMACAlFIWEVAPsCABMACAlFIWEVAPsCAAAA.Baelzharon:BAAALgAECgMJAwAAAA==.Balddrex:BAAALgAECgQJBAAAAA==.Balefire:BAACLgAFFH8IAAIQAAQJQBKGUwAfAQAQAAQJQBKGUwAfAQAuAAQKfywAAxAACQmRHZscAHkCABAACQmRHZscAHkCABIAAgntGMY5AEEAAAAA.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgAECgQJCgABLgAECgkJMAAIAP0PAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Bedown:BAAALgAECgQJCQABLgAECgUJCwARAAAAAA==.Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAABLgAECn8UAAIDAAkJUQqXoAA6AQADAAkJUQqXoAA6AQAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bh='Bhangbros:BAAALgAFFAMJBAAAAA==.',
Bi='Biggums:BAAALgAECgUJBQAAAA==.Bigwill:BAABLgAECn9BAAIDAAkJxSF4EwDlAgADAAkJxSF4EwDlAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAACLgAFFH8SAAIPAAQJwxPJEwDsAAAPAAQJwxPJEwDsAAAuAAQKf1QAAg8ACQkUIIYCAEYCAA8ACQkUIIYCAEYCAAAA.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgAECgYJDAAAAA==.Bluewaffles:BAAALgAECgQJBgABLgAECgkJFgAWAIkCAA==.',
Bo='Borealzombie:BAAALgAECgYJCgABLgAECgkJJgAXAN8cAA==.Boudicah:BAAALgADCgEJAQAAAA==.Bouzol:BAAALgAECgQJBAAAAA==.',
Br='Braicel:BAACLgAFFH8hAAIYAAgJmB3SBQAgAgAYAAgJmB3SBQAgAgAuAAQKfzIAAhgACQnkJHQDACoDABgACQnkJHQDACoDAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAZAFwZAA==.Brimara:BAAALgAFFAIJAwAAAA==.Brothaagamor:BAAALgAECgEJAQAAAA==.Brunomirror:BAAALgAECgkJDwABLgAFFAkJIAADAKcUAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJDgABLgAECgkJGQAIAIMfAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJRAAOAH4UAA==.Bunsen:BAAALgAECgEJAQABLgAFFAQJGAAaAHsdAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8mAAQbAAkJgCCwBwB7AgAbAAkJcCCwBwB7AgAcAAcJTx2uEwC0AQAJAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Callyne:BAAALgAECgIJAgAAAA==.Cambro:BAABLgAECn8WAAMCAAYJehnygAB4AQACAAYJTRnygAB4AQAXAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQPAAgJYhd9KwCmAQAPAAcJBBV9KwCmAQAdAAcJkRdCTQBaAQAeAAIJ+gANOwAYAAAAAA==.Captinsano:BAAALgAECgIJAQABLgAECggJHAATALsPAA==.Capz:BAACLgAFFH9UAAMbAAkJ7SQpAABHAgAJAAgJth9wAgCVAgAbAAkJWyQpAABHAgAuAAQKfyYAAxsACQnRIzwDANsCABsACAkCJTwDANsCAAkACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJDAAAAA==.Case:BAAALgAECgEJAwAAAA==.Cassius:BAAALgAECgEJAgAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECggJCwAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECgkJEgAAAA==.Ceezidan:BAAALgADCgEJAQAAAA==.Ceezinator:BAAALgAECgUJCAAAAA==.Ceeznuts:BAAALgADCgIJAgAAAA==.Cefteldore:BAAALgADCgcJBwAAAA==.Celebrïmbor:BAAALgAECgMJAgAAAA==.',
Ch='Chair:BAAALgAECggJEQABLgAFFAQJGgADAPoXAA==.Chichujongar:BAAALgAECgQJBAABLgAFFAkJJAAUAGQOAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chokehold:BAAALgADCgMJAwAAAA==.Chopperr:BAAALgAECgcJDAABLgAFFAIJBgAUACkhAA==.Chosenöne:BAAALgAECgYJDQAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8aAAIDAAQJ+hcHKgAqAQADAAQJ+hcHKgAqAQAuAAQKfz4AAgMACQnDIIkPAP4CAAMACQnDIIkPAP4CAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8VAAISAAcJyhKnAgC+AQASAAcJyhKnAgC+AQAuAAQKf1gAAhIACQl5JWIAAFADABIACQl5JWIAAFADAAAA.Clow:BAABLgAECn8dAAMJAAgJJyLMGgB1AgAJAAcJqiPMGgB1AgAbAAMJaB72KgCcAAAAAA==.',
Co='Colossus:BAAALgAECgMJBQAAAA==.Comparabull:BAAALgADCgcJEQABLgAECgkJIQADALMPAA==.Coolcrush:BAABLgAECn8+AAMVAAkJyiXEAQBZAwAVAAkJTyXEAQBZAwAUAAkJuSFWAwAdAwAAAA==.Corven:BAACLgAFFH8fAAIQAAkJSRRmHADlAQAQAAkJSRRmHADlAQAuAAQKf04AAxAACQlPI4gFADcDABAACQlPI4gFADcDABkAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwABLgAFFAkJHwAQAEkUAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJBAABLgAECgkJJgAHAB0YAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgkJEgAAAA==.Cryovox:BAAALgAECgUJBQAAAA==.Crôwley:BAAALgAECgQJCQAAAA==.',
Cu='Cumazzing:BAACLgAFFH8hAAICAAgJ/CJeAgDeAgACAAgJ/CJeAgDeAgAuAAQKfyoAAgIACQmJJrYCAK4DAAIACQmJJrYCAK4DAAAA.',
Da='Daalletra:BAAALgAECgYJBgABLgAECgcJAQARAAAAAA==.Dadrin:BAAALgADCgkJQQAAAA==.Daedyxes:BAACLgAFFH8MAAIWAAMJpg/LGACVAAAWAAMJpg/LGACVAAAuAAQKf1oAAhYACQkvHG0CAEICABYACQkvHG0CAEICAAAA.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Daní:BAAALgAECgQJBQAAAA==.Darfretail:BAABLgAECn8rAAIJAAkJhR5JCQDNAgAJAAkJhR5JCQDNAgAAAA==.Dargrum:BAAALgAFFAEJAQAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgYJDgAAAA==.Daveah:BAAALgADCggJCAAAAA==.Daygath:BAACLgAFFH8HAAIfAAIJmApkRwBwAAAfAAIJmApkRwBwAAAuAAQKfzEAAh8ACQlvFe0bAAICAB8ACQlvFe0bAAICAAAA.',
De='Deadlyiris:BAACLgAFFH8OAAMbAAQJ0RIMCwAQAQAbAAQJyRIMCwAQAQAJAAEJoRE8OAA/AAAuAAQKfzAAAxsACQnfIt4CABIDABsACQnfIt4CABIDAAkABgkfEJlKAHsBAAEuAAUUBAkYABoAex0A.Deadshot:BAAALgAECgEJAQAAAA==.Deatharin:BAAALgAECgYJDQAAAA==.Decompose:BAAALgAECgEJAwAAAA==.Demonbulio:BAABLgAECn84AAIBAAkJFBbJEAAcAgABAAkJFBbJEAAcAgAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAZAFwZAA==.Demonlorrd:BAAALgAECgIJAgABLgAECgQJEAARAAAAAA==.Demonskitten:BAABLgAECn8fAAIZAAkJXBlQBAA8AgAZAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgAECgEJAQAAAA==.Descendantt:BAAALgAECgEJAQAAAA==.Devilbullet:BAAALgADCgIJAwAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Diddylord:BAAALgAECgEJAwABLgAFFAIJBgAUACkhAA==.Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn84AAICAAkJtxRLXAC5AQACAAkJtxRLXAC5AQAAAA==.Dithehealer:BAABLgAECn8kAAMXAAkJYCB3AwDcAgAXAAkJYCB3AwDcAgACAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.Divinecandie:BAAALgAECgEJAQAAAA==.',
Dk='Dkdi:BAABLgAECn8rAAIWAAkJ9yLYAAANAwAWAAkJ9yLYAAANAwAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAIDAAYJQR6ZcQDwAQADAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgkJMwAgABUYAA==.Doogie:BAAALgAECgEJCQAAAA==.Dortak:BAAALgADCgQJBAABLgAECgUJDwARAAAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgARAAAAAA==.Dragonlife:BAAALgADCgIJAgAAAA==.Dragømir:BAAALgAFFAIJAgABLgAFFAUJCAANAMkCAA==.Draksha:BAAALgAECgUJBQABLgAECggJHQAJACciAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreadeye:BAAALgAECgMJAwAAAA==.Dreamfyres:BAACLgAFFH8YAAMMAAcJQRvpAQB9AQAMAAUJBCHpAQB9AQANAAUJ6BmxIQBSAQAuAAQKfysAAwwACQkmJQcBAF0DAAwACAmKJQcBAF0DAA0ACQkqJGIDADoDAAAA.Drenamai:BAABLgAECn8hAAIIAAkJMBMxPADvAQAIAAkJMBMxPADvAQAAAA==.Drewetta:BAABLgAECn9AAAIPAAkJjBTkBwBPAQAPAAkJjBTkBwBPAQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwARAAAAAA==.Durbana:BAAALgAECgUJCgAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.Duskfire:BAAALgAECgEJAQAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAABLgAECn8VAAMhAAYJqBckEgBWAQAhAAYJcBYkEgBWAQAWAAIJ9xQ/WAA+AAAAAA==.',
Ed='Edrocz:BAAALgAECgcJAQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8gAAICAAUJ0iaCFADGAQACAAUJ0iaCFADGAQAuAAQKfzoAAgIACQkGJq4BAMgDAAIACQkGJq4BAMgDAAEuAAUUCAkhAAIA/CIA.',
Ek='Ekhart:BAAALgAECgEJAQAAAA==.',
El='Elandin:BAAALgAECggJDwAAAA==.Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8UAAIiAAgJtQqxEQCCAQAiAAgJtQqxEQCCAQAuAAQKfxYAAiIACQmBDSEmAMgBACIACQmBDSEmAMgBAAAA.Elvwyr:BAAALgAECggJDQAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8UAAMfAAgJoBc+DAB9AQAfAAcJ6hY+DAB9AQAaAAEJ9whmewBIAAAuAAQKfyAAAx8ACAkkHtkTAIACAB8ACAkkHtkTAIACABoABAk3Cat1ALoAAAAA.Emmy:BAABLgAECn8UAAIGAAYJxyAuKgCiAQAGAAYJxyAuKgCiAQAAAA==.Emogothbabe:BAAALgAFFAIJAwABLgAFFAIJBgAUACkhAA==.Emowrecky:BAAALgAECgMJAwAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAABLgAFFH8NAAMTAAcJyhnhMAAQAQATAAUJBiDhMAAQAQAhAAQJZhJRCwDkAAAAAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQABAAQJqB30AQB7AQAjAAYJDRYbMQBhAQAOAAEJECe3AwB2AAAuAAQKfz8AAwEACQl9JXMAAOgDAAEACQl8JXMAAOgDACMACQm1IuYFACwDAAEuAAUUBwkNABMAyhkA.Eneldenes:BAABLgAFFH8FAAMkAAIJ3B7cLwBdAAAkAAEJDyHcLwBdAAAdAAEJfgLnfQAkAAAAAA==.Enjoyer:BAAALgAECggJEgABLgAECgkJGgAPABcPAA==.',
Er='Ereitherla:BAABLgAECn89AAIIAAkJhg93WQCYAQAIAAkJhg93WQCYAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAFFAIJAgABLgAFFAIJBgAUACkhAA==.',
Ev='Evanthe:BAAALgADCgEJAgAAAA==.',
Ex='Excalibear:BAABLgAECn8vAAIEAAkJPRaSJQDbAQAEAAkJPRaSJQDbAQABLgAFFAYJFwADAMocAA==.Exigrr:BAABLgAFFH8HAAIPAAYJ+BWLCwBoAQAPAAYJ+BWLCwBoAQAAAA==.',
Ey='Eydis:BAAALgADCgkJIAAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Farc:BAAALgAECgUJBgAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECgkJDAAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Felryno:BAAALgADCgQJBwAAAA==.Fenrys:BAAALgADCgIJAgAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fistbroz:BAABLgAECn8eAAMkAAkJ8xVHEgDMAQAkAAkJFBRHEgDMAQAeAAcJDxUeFAB/AQABLgAFFAkJJAAUAGQOAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAITAAkJPxjvRwDqAQATAAkJPxjvRwDqAQAAAA==.Fleredil:BAABLgAECn9IAAMYAAkJqSGwBQD4AgAYAAkJqSGwBQD4AgAGAAgJzRrAEQBSAgAAAA==.Flingernle:BAAALgAECgkJDwAAAA==.Floista:BAAALgAECggJDQAAAA==.Floistas:BAABLgAFFH8LAAIIAAMJWBPVXwDlAAAIAAMJWBPVXwDlAAAAAA==.',
Fo='Forepray:BAABLgAECn8YAAIYAAkJxR/pBwDRAgAYAAkJxR/pBwDRAgABLgAFFAkJIAAJAKATAA==.Forger:BAACLgAFFH8IAAIcAAMJNghXFQB4AAAcAAMJNghXFQB4AAAuAAQKfzUAAhwACQlMGP4MABoCABwACQlMGP4MABoCAAAA.Forsakey:BAAALgAECgUJDwABLgAFFAYJEQAdAB8ZAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freedomfite:BAAALgAECgEJAQAAAA==.Freshdk:BAACLgAFFH8UAAQTAAUJaiSaRABrAQATAAQJaiSaRABrAQAhAAQJLhe/EAAQAQAWAAEJAABZYAAAAAAuAAQKfzYABBMACQkFJHAMADcDABMACQkDJHAMADcDACEACAlhIbkHABkCABYAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAFFAEJBQAQANwaAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostitution:BAAALgAECgEJAQAAAA==.Frostycheeks:BAACLgAFFH8rAAMTAAUJHR3zJgA6AQATAAQJHR3zJgA6AQAWAAUJxgp5FAC9AAAuAAQKf0QAAhMACAloI7oGAAACABMACAloI7oGAAACAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQjAAgJ0CJzHwBYAgAjAAgJlyJzHwBYAgAOAAIJqiPkKABgAAABAAIJTxj8ZgA/AAAAAA==.Future:BAAALgAECgYJDwABLgAFFAMJCAAZACwbAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaav:BAAALgAECgUJBwABLgAECggJHQAJACciAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgAECgQJBgABLgAFFAIJBgAUACkhAA==.',
Gh='Ghettox:BAAALgAECgYJCwAAAA==.Ghostblades:BAACLgAFFH8aAAMTAAcJDxkiNQCVAQATAAcJDxkiNQCVAQAhAAEJAAB/LwAAAAAuAAQKfysAAxMACQmBIYYXALkCABMACQmBIYYXALkCACEAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.Ghuleh:BAAALgAECgEJAgAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBwABLgAFFAkJMQAYAD8ZAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAABLgAFFH8IAAIaAAYJ9AubIgBlAQAaAAYJ9AubIgBlAQABLgAFFAYJFwADAMocAA==.Gorm:BAAALgAECgQJBAABLgAFFAIJCAATAMggAA==.',
Gr='Gratata:BAAALgAECgMJBQABLgAECgkJJgAHAB0YAA==.Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAABLgAECn8bAAMlAAkJ4w4oCADMAQAlAAkJMQ4oCADMAQAiAAQJ7Q7oOADtAAABLgAECgkJTAACADoiAA==.Grinny:BAABLgAECn9MAAMCAAkJOiK+CQAaAwACAAkJOiK+CQAaAwAEAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Gu='Gunna:BAAALgAECgIJAwABLgAFFAMJCAAZACwbAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Halbruck:BAAALgAFFAEJAQAAAA==.Haldane:BAABLgAECn8qAAICAAkJ8gxydgCBAQACAAkJ8gxydgCBAQABLgAFFAQJGAAaAHsdAA==.Havochunter:BAABLgAECn8ZAAIIAAgJgx9+OgD1AQAIAAgJgx9+OgD1AQAAAA==.',
He='Heidegger:BAAALgAECgQJCQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8zAAIgAAkJFRh3BgAsAgAgAAkJFRh3BgAsAgAAAA==.Heriod:BAAALgAECgYJCQAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgAECgUJCgAAAA==.Holywráth:BAABLgAECn8XAAICAAcJlwz/rAAjAQACAAcJlwz/rAAjAQAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAABLgAECn8WAAMiAAkJtRNsGgDFAQAiAAkJtRNsGgDFAQAlAAEJ2REbJgA7AAAAAA==.Hunterdh:BAABLgAECn9AAAIIAAkJvA9KEgBYAQAIAAkJvA9KEgBYAQAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8gAAIJAAkJoBPQCADSAQAJAAkJoBPQCADSAQAuAAQKfzAAAgkACQkIIRQMAKgCAAkACQkIIRQMAKgCAAAA.',
Ic='Icecandie:BAAALgAECgYJEgAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAgJGAAMAEEbAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJTAAFAFgVAA==.',
Im='Imistmypants:BAABLgAECn8mAAIHAAkJHRjuEwB8AgAHAAkJHRjuEwB8AgAAAA==.Impera:BAAALgAECgUJDQAAAA==.',
In='Infinitevoid:BAAALgADCgUJDAAAAA==.Innervatez:BAABLgAFFH8bAAIdAAkJOBxUBADZAgAdAAkJOBxUBADZAgAAAA==.Inspectda:BAABLgAECn8VAAIQAAgJgwcadgBxAQAQAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Ir='Irryna:BAAALgADCgcJBwAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAILAAgJJBt9CwAiAgALAAgJJBt9CwAiAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn84AAIDAAkJORY0RAAPAgADAAkJORY0RAAPAgAAAA==.Jakbandit:BAAALgADCgEJAQAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn9HAAIDAAkJHSVnCgAmAwADAAkJHSVnCgAmAwAAAA==.Jaquio:BAAALgAECgEJAQAAAA==.Jarten:BAABLgAECn83AAIhAAkJqiKDAQAhAwAhAAkJqiKDAQAhAwAAAA==.Jaylebate:BAABLgAECn9OAAMTAAkJaiKCBABtAgAWAAkJCB7tAQByAgATAAkJzCGCBABtAgAAAA==.',
Je='Jerrenn:BAABLgAECn8eAAMCAAkJqBjUQAAEAgACAAgJ3hfUQAAEAgAEAAIJLwlfeQBaAAAAAA==.Jesseatamer:BAACLgAFFH8IAAIIAAMJKiOlIgAfAQAIAAMJKiOlIgAfAQAuAAQKfzoAAggACQmaJscAAJIDAAgACQmaJscAAJIDAAAA.',
Ji='Jinshi:BAAALgAECgEJAQABLgAECggJHQAJACciAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jortak:BAAALgAECggJEwABLgAECgkJTgATAGoiAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwARAAAAAA==.',
Js='Jstrawr:BAAALgAFFAQJBAAAAA==.Jsttotem:BAAALgAFFAMJAwABLgAFFAQJBAARAAAAAA==.',
Ju='Judge:BAAALgAECgEJAgAAAA==.Julberry:BAAALgAECgEJAQAAAA==.Julesx:BAAALgAFFAEJAQAAAA==.Justar:BAAALgADCgMJBQAAAA==.',
['Jë']='Jësus:BAAALgAECgcJDgAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kaipoc:BAAALgADCgMJAwAAAA==.Kakamora:BAABLgAECn8UAAMgAAgJGhleEABVAQAIAAgJbBZWVQCkAQAgAAcJ/BNeEABVAQABLgAFFAQJBwAfAAcKAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAITAAkJVBboRgDuAQATAAkJVBboRgDuAQAAAA==.Karen:BAAALgAECgUJDQABLgAECgkJOAACALcUAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJBAAAAA==.Karyana:BAAALgAFFAMJAwAAAA==.Karyis:BAABLgAFFH8IAAIQAAQJHxNVIgAPAQAQAAQJHxNVIgAPAQAAAA==.Kastia:BAABLgAECn8XAAIDAAYJlxDvGgAFAQADAAYJlxDvGgAFAQAAAA==.Katrynwel:BAABLgAECn8hAAIDAAkJsw/nfQB8AQADAAkJsw/nfQB8AQAAAA==.Katsumi:BAAALgAECgcJEwAAAA==.Kaylestia:BAAALgAECgkJCQAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Keliki:BAAALgADCgMJAwAAAA==.Kellenah:BAAALgADCgkJIgAAAA==.Kettama:BAAALgAECgEJAgABLgAFFAIJBgAUACkhAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.Khold:BAACLgAFFH8FAAIhAAMJJwZOEQCjAAAhAAMJJwZOEQCjAAAuAAQKfxwABBYACAmLGVkGAEcBABMABwmRGXdRAM8BABYABwnhEVkGAEcBACEABwlNBtMdAN4AAAAA.',
Ki='Killalltoday:BAABLgAECn9CAAMaAAkJPxK7SQCIAQAaAAkJPxK7SQCIAQAmAAgJNg5SEwCDAQAAAA==.Killersmile:BAAALgADCgkJCQAAAA==.Kilon:BAAALgAFFAEJAQAAAA==.Kiritò:BAAALgAECgMJAwAAAA==.Kirkk:BAABLgAECn8WAAIEAAYJIhc+MACZAQAEAAYJIhc+MACZAQAAAA==.Kivareous:BAAALgAFFAIJAwAAAA==.Kixarea:BAAALgADCgkJDQABLgAFFAIJAwARAAAAAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAABLgAECn8ZAAIWAAgJsxZXFQDCAQAWAAgJsxZXFQDCAQAAAA==.Knixx:BAACLgAFFH8aAAMYAAYJwg/bCgBFAQAYAAUJtg/bCgBFAQAFAAUJeAiqMADPAAAuAAQKf0YABBgACQmlGkAMAIwCABgACQmlGkAMAIwCAAYABwk6GGQbAAECAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.Knuppelus:BAAALgADCgIJAgAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIUAAkJUxEBJwB4AQAUAAkJUxEBJwB4AQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIHAAkJmhhRFQBvAgAHAAkJmhhRFQBvAgAAAA==.Koyya:BAABLgAFFH8GAAMaAAIJ4Aq2cQBaAAAaAAIJ4Aq2cQBaAAAfAAEJGQiLWwA0AAAAAA==.',
Kr='Krunchee:BAABLgAECn8qAAIfAAgJXgv7UAD0AAAfAAgJXgv7UAD0AAAAAA==.',
Ku='Kufoo:BAABLgAECn9CAAMJAAkJeCaxAQBjAwAJAAkJoSWxAQBjAwAcAAkJ0SWBBADcAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJCAAZACwbAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8gAAIOAAkJkxccBgA4AgAOAAkJkxccBgA4AgABLgAECgkJIAAOAJMXAA==.Kyokushin:BAAALgAECgMJAwAAAA==.Kyzo:BAAALgAECgkJDwAAAA==.',
['Ké']='Kéndra:BAAALgAECgMJAwAAAA==.',
La='Ladiable:BAAALgAECgYJDAABLgAFFAYJHQAIAA0hAA==.Laggyboi:BAAALgAECgYJCAAAAA==.Lansseax:BAABLgAECn8aAAMYAAkJ7BCQBgB5AQAYAAkJ7BCQBgB5AQAFAAIJVwWQbgBOAAAAAA==.Laraelin:BAAALgADCgYJBgAAAA==.Lascerette:BAAALgAECgYJCgAAAA==.Law:BAAALgADCgcJEQAAAA==.Layez:BAAALgAECgEJAQABLgAFFAMJBwATAKgSAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Leo:BAAALgAFFAEJAQAAAA==.Lethe:BAAALgAECgcJCAABLgAFFAgJFAAiALUKAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAAIAAAbAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgIJBAARAAAAAA==.Lilyröse:BAAALgAECgIJBAAAAA==.Lionsong:BAAALgAECgYJBgABLgAFFAMJCAAZACwbAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAACLgAFFH8FAAIQAAMJngsyOwCiAAAQAAMJngsyOwCiAAAuAAQKf0EAAhAACQlyHDkFAP0BABAACQlyHDkFAP0BAAAA.Lohmi:BAAALgAECgYJDAAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAACLgAFFH8PAAIPAAQJMgMMHwCLAAAPAAQJMgMMHwCLAAAuAAQKfywAAg8ACQkIC0IsAHYBAA8ACQkIC0IsAHYBAAAA.Lovekiing:BAAALgAECgQJBQAAAA==.',
Lu='Luania:BAABLgAECn8bAAIIAAYJyBQZFgAyAQAIAAYJyBQZFgAyAQAAAA==.Lufselda:BAAALgAECgEJAQAAAA==.Lumnia:BAAALgAECgEJAgAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lurtz:BAABLgAECn8YAAIIAAYJ4BY3bwBiAQAIAAYJ4BY3bwBiAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgIJAwAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.Lyzzardkng:BAABLgAECn8XAAICAAcJTwiEJwC7AAACAAcJTwiEJwC7AAAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAgJFAAfAKAXAA==.',
Ma='Maango:BAAALgAECgkJCAAAAA==.Maemu:BAAALgAECgEJAQAAAA==.Magedh:BAAALgADCgEJAQAAAA==.Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn9QAAMDAAkJnh7hAwCyAgADAAkJnh7hAwCyAgAnAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgQJCAAAAA==.Makeawish:BAAALgAFFAEJAQABLgAFFAMJBQATADoDAA==.Malkala:BAAALgAECgYJCgAAAA==.Malonormu:BAAALgAECgYJBgAAAA==.Mamadeezy:BAAALgAECgcJDQAAAA==.Manical:BAABLgAECn8UAAIPAAgJhA0QOwAmAQAPAAgJhA0QOwAmAQAAAA==.Mashiach:BAAALgAFFAMJAwABLgAFFAYJFwATAKUSAA==.Matthyjsz:BAAALgADCgIJAgAAAA==.Maxgoon:BAABLgAECn8WAAIQAAcJwgzVcwB2AQAQAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQABLgAECgkJEQARAAAAAA==.',
Me='Megumin:BAABLgAECn8cAAQDAAgJdhNFZgCxAQADAAgJ7hJFZgCxAQAnAAMJeA/pDACZAAAoAAIJ3xNtGgBEAAABLgAECgkJLgACACogAA==.Mellisandria:BAAALgAECgcJEQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn81AAIUAAkJmCOMAgA0AwAUAAkJmCOMAgA0AwAAAA==.Merriska:BAACLgAFFH8GAAMEAAIJxyC5NwCOAAAEAAIJxyC5NwCOAAACAAEJHRG2uABFAAAuAAQKfxsAAwIACQk1IqElAJACAAIACAlWI6ElAJACAAQACAm7IJsTAHUCAAEuAAUUCAkgAAcA+R8A.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Miessa:BAAALgAECgEJAQAAAA==.Mikeysmom:BAAALgAECggJEAABLgAECgkJBgARAAAAAA==.Mirigosa:BAAALgAECggJCAABLgAFFAQJGgADAPoXAA==.Misseslovett:BAAALgAECgcJDAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8/AAIkAAgJoBi7AgDhAQAkAAgJoBi7AgDhAQAuAAQKfz0AAiQACQnPHGAHAIACACQACQnPHGAHAIACAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAACLgAFFH8PAAMEAAQJriNTEwCUAQAEAAQJriNTEwCUAQACAAMJYxfnMADLAAAuAAQKfzoABAQACQk2JrIBAGgDAAQACQk2JrIBAGgDABcABwmOIacBAEECAAIAAQlhGbpzAUUAAAAA.Morgause:BAABLgAECn8aAAIQAAkJqwn5DwAHAQAQAAkJqwn5DwAHAQAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.',
Mu='Muirdin:BAABLgAECn8kAAIIAAkJvhF4WwCTAQAIAAkJvhF4WwCTAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMbAAkJYCJ9CgBCAgAbAAkJbCF9CgBCAgAJAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAFFAEJAQABLgAFFAEJBQAQANwaAA==.',
Na='Naanomage:BAABLgAECn8VAAIDAAgJCA8EuQAUAQADAAgJCA8EuQAUAQAAAA==.Nacht:BAAALgADCgEJAQABLgAFFAcJEwAKAKIeAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAACLgAFFH8FAAIQAAEJ3Bp9vABRAAAQAAEJ3Bp9vABRAAAuAAQKf0QAAxAACQmhJKMDAFcDABAACAmhJKMDAFcDABIAAQkAAPZcAFgAAAAA.Nemoralia:BAAALgAECggJEgAAAA==.Nezuuko:BAAALgADCgUJBwAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMjAAkJrxzhIQCGAgAjAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn9BAAIMAAkJ3w2ACACoAQAMAAkJ3w2ACACoAQAAAA==.Nitemelduser:BAAALgAECgEJAQAAAA==.Nixilis:BAAALgADCgcJCgAAAA==.',
No='Noiire:BAAALgAFFAIJAwABLgAFFAgJFAAiALUKAA==.Nombra:BAAALgAECgEJAgAAAA==.Nopal:BAAALgAECgMJAwAAAA==.Nopriest:BAACLgAFFH8YAAIYAAcJ9CHrAwBUAgAYAAcJ9CHrAwBUAgAuAAQKfzUAAhgACQnzJWwBAGcDABgACQnzJWwBAGcDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn9EAAQOAAkJfhR4AgByAQABAAkJuBLoFgDPAQAOAAcJ3hR4AgByAQAjAAMJcAQqBgFEAAAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAABLgAECn8kAAMHAAkJZRNqEAAlAQAHAAgJIRFqEAAlAQAVAAQJSxHUQgD0AAAAAA==.Nugs:BAAALgAECgEJAQAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAcJIQAiANMdAA==.',
Oa='Oakly:BAACLgAFFH8JAAIdAAMJNxO1PwCxAAAdAAMJNxO1PwCxAAAuAAQKfy4AAh0ACAk0HpwTAK4CAB0ACAk0HpwTAK4CAAAA.',
Ob='Obsidian:BAAALgAECggJEAABLgAFFAQJDwAEAK4jAA==.',
Od='Odysse:BAAALgAECgYJBwAAAA==.',
Ok='Okami:BAAALgAECgQJBQAAAA==.',
On='Onaroll:BAABLgAFFH8GAAIHAAMJrgd7SACDAAAHAAMJrgd7SACDAAABLgAFFAkJHQAdAL4UAA==.Onehotelf:BAAALgAECgcJEwAAAA==.',
Oo='Ooyagoddess:BAABLgAECn8vAAMFAAYJcx4cBQDUAQAFAAYJpBocBQDUAQAGAAYJWxWDKwBtAQAAAA==.',
Or='Orenthil:BAAALgAECgEJAQABLgAFFAMJCQACAOseAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAYJFgAIALYeAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAACLgAFFH8IAAIVAAMJMB4GCgACAQAVAAMJMB4GCgACAQAuAAQKfyUAAhUABgmoI6EcAMoBABUABgmoI6EcAMoBAAAA.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAIJAgABLgAFFAgJGAAMAEEbAA==.Pann:BAAALgAECgEJAQABLgAECggJFQAUAFcSAA==.Papatiny:BAAALgAECgYJBgAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn87AAIfAAkJ6RkVGwAIAgAfAAkJ6RkVGwAIAgAAAA==.Pawsa:BAACLgAFFH8GAAIUAAIJKSHTEQDAAAAUAAIJKSHTEQDAAAAuAAQKf0YAAxQACQmnHzYLAIECABQACQmnHzYLAIECABUACAkWGq0VAAsCAAAA.Pawsome:BAAALgAECgYJCwABLgAECgkJOwAfAOkZAA==.Pawthetic:BAACLgAFFH8dAAIdAAkJvhTCBgACAgAdAAkJvhTCBgACAgAuAAQKfzMAAx0ACQkDITwDAGEDAB0ACQkDITwDAGEDAA8ACQnzHF0PAGkCAAAA.',
Pe='Peelforheals:BAACLgAFFH8RAAMYAAUJyxTLFQC0AAAYAAMJChHLFQC0AAAFAAQJWAzPHACkAAAuAAQKfy8AAxgACQmKGPogAL4BABgACAlFF/ogAL4BAAUABwm7FRocALUBAAAA.Penguindemic:BAABLgAECn8sAAIQAAkJaiYbAgBxAwAQAAkJaiYbAgBxAwAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJJgAHAB0YAA==.Pep:BAABLgAECn8fAAMVAAkJ1x30DAB1AgAVAAkJ1x30DAB1AgAHAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgAECgcJCAAAAA==.Petruccius:BAACLgAFFH8ZAAIPAAcJXBLhCQCNAQAPAAcJXBLhCQCNAQAuAAQKfzEAAg8ACQmFH1EHAOECAA8ACQmFH1EHAOECAAAA.Pewpewlepew:BAAALgAFFAIJAgAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgkJKgAjAIoVAA==.Phaeku:BAABLgAECn8qAAIjAAkJihVLMwD4AQAjAAkJihVLMwD4AQAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQABLgAECgQJBQARAAAAAA==.',
Pl='Plaga:BAAALgAECgcJBwABLgAFFAMJBQATADoDAA==.Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Poochita:BAAALgAECgMJBAAAAA==.Poppop:BAAALgADCgMJAwAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJEAABLgAECgkJPgAVAMolAA==.Powermonk:BAAALgAECgQJBwAAAA==.',
Pr='Prayre:BAAALgADCgkJFwAAAA==.Prey:BAABLgAECn8cAAIIAAUJMxh/GQAWAQAIAAUJMxh/GQAWAQAAAA==.Prikarea:BAAALgAECgQJBAABLgAFFAIJAwARAAAAAA==.Prospa:BAAALgAECgQJCAABLgAFFAIJBgAUACkhAA==.Prumper:BAACLgAFFH8JAAIDAAUJwAdIkAC3AAADAAUJwAdIkAC3AAAuAAQKf0MAAgMACQmaIGsnAH0CAAMACQmaIGsnAH0CAAAA.',
Pu='Puffinondank:BAAALgAECgEJAQABLgAFFAIJBgAUACkhAA==.Purah:BAABLgAFFH8GAAIpAAUJxh+dAQBsAQApAAUJxh+dAQBsAQAAAA==.',
Py='Pyric:BAAALgAECgEJBAAAAA==.Pyrin:BAAALgAECgEJAQAAAA==.',
Qu='Quaido:BAAALgAECgEJBAAAAA==.Quesoblanco:BAAALgAECgkJCwAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgYJDAAAAA==.Qybxboogiemo:BAAALgAECgEJAgAAAA==.Qybxboogietk:BAAALgAECgIJAgAAAA==.',
Ra='Rabid:BAAALgAECgEJBQAAAA==.Raghallov:BAAALgAECgMJAwAAAA==.Ragingstorm:BAAALgADCgIJAwAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8yAAITAAkJPx1OIACIAgATAAkJPx1OIACIAgAAAA==.Ravokkc:BAAALgADCgUJBgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Reaperan:BAAALgAECgMJAgAAAA==.Redbearon:BAAALgAECgkJEwAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Refractrix:BAAALgAECgUJDQAAAA==.Regena:BAABLgAECn9MAAQFAAkJWBUSHwDVAQAFAAkJcw4SHwDVAQAGAAkJUhScIQC2AQAYAAcJdwzhEAC9AAAAAA==.Relyssa:BAAALgAECgcJDgAAAA==.Remorse:BAACLgAFFH8bAAIcAAkJcRezCACpAQAcAAkJcRezCACpAQAuAAQKf0sAAhwACQnxIogCABwDABwACQnxIogCABwDAAAA.Required:BAAALgAFFAMJAwABLgAFFAkJPQAjAJwiAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8tAAMdAAkJ+x2LDQDuAgAdAAkJ+x2LDQDuAgAPAAkJoxdjFAAwAgABLgAFFAIJAwARAAAAAA==.Rim:BAABLgAECn9EAAIaAAkJfB5WCwADAwAaAAkJfB5WCwADAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Riproot:BAAALgAECgUJBQAAAA==.Risque:BAACLgAFFH8QAAIDAAQJKhc1WAAtAQADAAQJKhc1WAAtAQAuAAQKfyoAAgMACQlIIXUfAKECAAMACQlIIXUfAKECAAAA.',
Ro='Ronard:BAACLgAFFH8HAAITAAIJthv70gCOAAATAAIJthv70gCOAAAuAAQKf0kAAhMACQkQJksEAF4DABMACQkQJksEAF4DAAAA.Ronfar:BAACLgAFFH8ZAAImAAcJPRT4BQBfAQAmAAcJPRT4BQBfAQAuAAQKf08AAiYACQkLJU0BAC0DACYACQkLJU0BAC0DAAAA.Rook:BAAALgAECggJEAAAAA==.Rootwalker:BAAALgAECgEJAQAAAA==.',
Ru='Rukidingme:BAAALgAECgYJEgAAAA==.Rumonkingme:BAAALgADCgUJBwAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Rustyglass:BAAALgAECgEJAQAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8wAAICAAkJbQ3SYgCqAQACAAkJbQ3SYgCqAQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAABLgAECn8XAAICAAgJMgpxnwA4AQACAAgJMgpxnwA4AQAAAA==.',
Sa='Sacrifice:BAAALgADCgQJBAAAAA==.Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Sango:BAAALgADCgMJBgAAAA==.Saronas:BAAALgADCgkJEAABLgAECgkJNwAhAKoiAA==.',
Sc='Schrutes:BAAALgADCgEJAQAAAA==.Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAIVAAcJVBRCLAB+AQAVAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQdAAgJdhy3JQAiAgAdAAcJ1By3JQAiAgAPAAYJ+R6FHwADAgAkAAEJGQaYNQAfAAAAAA==.Scubowsuit:BAAALgAECgYJCQAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAFFAEJAgAAAA==.Selen:BAABLgAECn9EAAMEAAkJmiGbBgAjAwAEAAkJmiGbBgAjAwACAAIJDhP9NACDAAAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Semballin:BAAALgAECgEJAwAAAA==.Semdogg:BAAALgAECgEJAQABLgAECgkJNwABAKQhAA==.Semtex:BAAALgAECgEJAQAAAA==.Semy:BAAALgAECgEJAQABLgAECgkJNwABAKQhAA==.Seråphiel:BAABLgAECn8pAAIIAAgJXAisfwA/AQAIAAgJXAisfwA/AQAAAA==.Seswatha:BAACLgAFFH8XAAIDAAYJyhyHKwDEAQADAAYJyhyHKwDEAQAuAAQKfzwAAgMACQklJX8FAFcDAAMACQklJX8FAFcDAAAA.',
Sh='Shadowbaron:BAABLgAECn8XAAIYAAgJUxOCBQCbAQAYAAgJUxOCBQCbAQAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shakras:BAAALgADCgEJAQABLgAECgkJTAAFAFgVAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAACLgAFFH8HAAIaAAUJhCPjDACEAQAaAAUJhCPjDACEAQAuAAQKfxwAAxoACQlaIhoLAAYDABoACQlaIhoLAAYDAB8ABQnXGOtTAOoAAAEuAAUUCAkcAAQAohgA.Shamdi:BAAALgAECgUJBQAAAA==.Shawti:BAAALgADCgcJCAAAAA==.Shawtyy:BAAALgADCgcJBwAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAABLgAECn8aAAIPAAkJFw9SJQChAQAPAAkJFw9SJQChAQAAAA==.Shocktop:BAABLgAECn8fAAImAAkJrSJiAQAoAwAmAAkJrSJiAQAoAwAAAA==.Shockzilla:BAAALgADCgUJBAAAAA==.Shortandold:BAAALgAECgYJBgAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAARAAAAAA==.Shortserkit:BAAALgAECgYJBgAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAARAAAAAA==.Shådowfire:BAAALgAECggJCQAAAA==.Shìft:BAACLgAFFH8VAAIdAAQJyw+FFQDNAAAdAAQJyw+FFQDNAAAuAAQKfzMAAh0ACQlXGS4VAKACAB0ACQlXGS4VAKACAAAA.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgAECgEJAQAAAA==.Sillynanny:BAAALgAECgUJCQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAAPALAdAA==.',
Sk='Skuùuß:BAAALgADCgQJBAAAAA==.Skybluhunter:BAAALgADCgMJAwAAAA==.Skycaller:BAAALgAECgIJAgAAAA==.Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAABLgAECn8lAAQBAAcJFxt3BAC4AQABAAcJFxt3BAC4AQAOAAMJPRf+GgDEAAAjAAIJKA3dyABmAAABLgAECgkJHAAIAMUZAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimybuffalo:BAAALgAECgQJBAABLgAECgkJIQAkAKAiAA==.Slimydruid:BAABLgAECn8hAAIkAAkJoCKLBgCUAgAkAAkJoCKLBgCUAgAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8wAAQoAAgJ1SWfAgBmAgADAAgJaiF+LQC8AgAoAAgJUyOfAgBmAgAnAAQJcx/kBgA9AQABLgAFFAMJCAAZACwbAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokinontech:BAAALgAECgEJAwABLgAFFAIJBgAUACkhAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIbAAkJCgssIABdAQAbAAkJCgssIABdAQAAAA==.Smugs:BAABLgAFFH8KAAIgAAQJ+g+vDAC6AAAgAAQJ+g+vDAC6AAAAAA==.Smugxl:BAABLgAECn8YAAIgAAkJJBylAwCPAgAgAAkJJBylAwCPAgAAAA==.',
Sn='Snowtard:BAAALgAECgEJAQAAAA==.',
So='Solid:BAAALgAECgUJBgAAAA==.Sonicberger:BAAALgADCgQJBAABLgAECgkJKwATAOQcAA==.Sonicbergger:BAAALgAECgYJCAABLgAECgkJKwATAOQcAA==.Sonicecho:BAAALgAECgIJAgAAAA==.Soniclavv:BAAALgAECgcJEwAAAA==.Sonicpoe:BAAALgADCgkJDAABLgAECgkJKwATAOQcAA==.Soniko:BAAALgAECgEJAQABLgAECgkJHAAIAMUZAA==.Sonícberger:BAABLgAECn8rAAMTAAkJ5BzcLABMAgATAAkJ5BzcLABMAgAWAAQJTw+0OACxAAAAAA==.Soulcaliber:BAAALgAECgEJAgAAAA==.Soulleader:BAAALgADCgYJBgAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
Sq='Squee:BAAALgAFFAIJAwABLgAFFAgJIAAHAPkfAA==.',
St='Stain:BAAALgAECgUJEwAAAA==.Stealth:BAAALgAECggJDgABLgAFFAMJBwATAKgSAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stillheart:BAAALgAECgkJAQAAAA==.Stith:BAAALgADCgYJCAAAAA==.Stkinbck:BAABLgAECn8+AAIiAAkJNhDyIQCGAQAiAAkJNhDyIQCGAQAAAA==.Stonehenge:BAACLgAFFH8YAAMaAAQJex02JwBLAQAaAAQJex02JwBLAQAfAAIJ9gzKKQBoAAAuAAQKfyIAAhoACQmzISsQANACABoACQmzISsQANACAAAA.Stonepalm:BAAALgAECgQJCAAAAA==.Stratan:BAABLgAECn8dAAMXAAcJcgs4KwDBAAACAAcJZQgo6ADUAAAXAAcJcgo4KwDBAAAAAA==.',
Su='Subbzero:BAAALgAECgMJAwAAAA==.Suffer:BAACLgAFFH8IAAMZAAMJLBtLDgChAAAQAAMJExkIcgDdAAAZAAIJzRtLDgChAAAuAAQKfxoABBAACAmsI4AUAKoCABAACAmQI4AUAKoCABkAAwnOI+gdANAAABIAAgn0GJFjAEcAAAAA.Sukuna:BAAALgAECgYJCQAAAA==.Sundermere:BAAALgAECgEJAgABLgAECgEJBAARAAAAAA==.Sunlight:BAAALgAECgQJBQAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8gAAICAAgJACLTIwCZAgACAAgJACLTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8kAAQUAAkJZA5ZBwCGAQAUAAcJ8g1ZBwCGAQAVAAUJLA15EQAxAQAHAAIJ0wB1cAAiAAAuAAQKfzsAAxQACQk3HTYSACQCABUACAliHXkTAFUCABQACQlBGjYSACQCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.Synzen:BAAALgAECgQJBAAAAA==.',
['Sá']='Sásukeuchiha:BAAALgAECgYJCwABLgAECgkJMAAIAP0PAA==.',
['Sä']='Sätansangel:BAAALgAECgUJBwAAAA==.',
['Sî']='Sî:BAAALgAECgIJAwAAAA==.',
Ta='Tabbz:BAABLgAECn8sAAMfAAkJvRnFGQATAgAfAAkJvRnFGQATAgAaAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAABLgAFFH8RAAImAAQJVRF8BgABAQAmAAQJVRF8BgABAQAAAA==.Tallyhochick:BAACLgAFFH8RAAIIAAQJsgVAPgC1AAAIAAQJsgVAPgC1AAAuAAQKfy8AAggACQlcDDFPALUBAAgACQlcDDFPALUBAAAA.Tam:BAAALgAECgYJBgABLgAECgcJJgAfADgWAA==.Taman:BAABLgAECn8mAAMfAAcJOBamKADPAQAfAAcJOBamKADPAQAaAAcJHx0fCwCFAQAAAA==.Tamü:BAAALgAECgQJBgABLgAECgcJJgAfADgWAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAABLgAECn8ZAAIUAAkJUQvgMAA/AQAUAAkJUQvgMAA/AQAAAA==.Telean:BAAALgAFFAEJAQAAAA==.Telkon:BAAALgAECgkJDQAAAA==.Tellesto:BAABLgAECn8wAAMKAAkJpBwhEwAOAgAKAAkJqxohEwAOAgAIAAMJNRfi3gCQAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECgkJQAAPAIwUAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgAECgIJBQAAAA==.Thebigonion:BAABLgAECn8kAAIfAAYJMQ9MUwDsAAAfAAYJMQ9MUwDsAAAAAA==.',
Ti='Tiatriic:BAAALgAECgEJAQABLgAECgEJAwARAAAAAA==.Tibberino:BAAALgAECggJDwAAAA==.Ticklantical:BAAALgAECggJDgABLgAECgkJUAADAJ4eAA==.Tigerfist:BAAALgAECgEJAQAAAA==.Tikareous:BAAALgAECgMJAwABLgAFFAIJAwARAAAAAA==.Tinydeath:BAAALgAECgcJBwABLgAECgkJKwAIADMhAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8sAAMUAAkJLBxhEwAWAgAUAAkJ3BthEwAWAgAVAAUJghrpKABzAQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwAIADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMIAAkJMyEFDwDDAgAIAAkJECAFDwDDAgAKAAQJtxCgOgDpAAAAAA==.',
To='Toko:BAACLgAFFH8dAAIIAAcJKCAsAgB9AQAIAAcJKCAsAgB9AQAuAAQKfykAAwgACQkjIuIIAAUDAAgACQkjIuIIAAUDACAAAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMhAAkJlhp5CAAGAgAhAAkJlhp5CAAGAgAWAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBQAAAA==.Tourma:BAAALgAFFAEJBAAAAA==.',
Tr='Trapattack:BAAALgAECgQJBwAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECgkJEQARAAAAAA==.Truepatriot:BAACLgAFFH8JAAIEAAMJbxmOLwC5AAAEAAMJbxmOLwC5AAAuAAQKfycAAwQACAmoExMyALcBAAQACAmoExMyALcBABcABQnpEt0pAMoAAAAA.Truexlord:BAABLgAECn8WAAITAAcJegzHpgAiAQATAAcJegzHpgAiAQAAAA==.Truthes:BAACLgAFFH8HAAITAAMJqBJcVQCvAAATAAMJqBJcVQCvAAAuAAQKfxUAAhMACQmsHBghAIQCABMACQmsHBghAIQCAAAA.Truthez:BAAALgAECgEJAQABLgAFFAMJBwATAKgSAA==.Truthful:BAAALgAECgEJAQABLgAFFAMJBwATAKgSAA==.Truths:BAAALgAFFAEJAQABLgAFFAMJBwATAKgSAA==.Truthsx:BAABLgAECn8nAAMZAAgJGiAHBgAhAgAZAAgJph8HBgAhAgAQAAUJchothgAtAQABLgAFFAMJBwATAKgSAA==.Truthy:BAAALgAECgIJAgAAAA==.Truthz:BAAALgADCgYJBgABLgAFFAMJBwATAKgSAA==.',
Tu='Tubie:BAAALgAECgQJBwAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgcJEwAAAA==.Tygerhealz:BAAALgAECgIJAgAAAA==.Tylaatape:BAABLgAFFH8FAAITAAMJOgMTvACxAAATAAMJOgMTvACxAAAAAA==.Tyraell:BAABLgAECn8sAAMEAAkJkR2CDgCtAgAEAAkJkR2CDgCtAgACAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAACLgAFFH8FAAIWAAMJdxkZLgCOAAAWAAMJdxkZLgCOAAAuAAQKfxsAAhYACQlEH10FAOsCABYACQlEH10FAOsCAAEuAAUUBwkdAAgAKCAA.',
Ud='Uddermadness:BAAALgADCgQJBAAAAA==.Udor:BAABLgAECn8aAAIIAAgJLgyZbABoAQAIAAgJLgyZbABoAQAAAA==.',
Um='Umbrae:BAACLgAFFH8NAAMGAAQJ2RDCDgC/AAAGAAQJ2RDCDgC/AAAYAAEJpQDnQwAMAAAuAAQKfz0AAwYACQlGHxkQAGgCAAYACAnNHhkQAGgCABgAAQnjB+eCADgAAAAA.',
Up='Upies:BAABLgAECn8VAAINAAgJ6gKyXgC+AAANAAgJ6gKyXgC+AAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAABLgAECn8mAAIQAAkJdw2bfAA/AQAQAAkJdw2bfAA/AQAAAA==.',
Va='Vahder:BAAALgAECgEJAQAAAA==.Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIQAAMJjwgkjQCrAAAQAAMJjwgkjQCrAAAuAAQKfyMAAxAACQnGGp8fAGcCABAACQnGGp8fAGcCABIAAQn0HlUxAFgAAAAA.Vazro:BAACLgAFFH8PAAIEAAQJGBQ9EAD6AAAEAAQJGBQ9EAD6AAAuAAQKfx4AAwQACQkkF8ICADgCAAQACQkkF8ICADgCAAIABAmXDEUxAJIAAAAA.',
Ve='Veera:BAABLgAECn83AAIfAAkJ6xXRGwADAgAfAAkJ6xXRGwADAgAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Velyris:BAAALgAECgQJBAAAAA==.Vendyr:BAABLgAECn8aAAQZAAgJlCLxBwDOAQAQAAcJQx41LQBZAgAZAAYJsxnxBwDOAQASAAIJ8AscYABPAAAAAA==.Veyra:BAAALgAECgUJBgAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Vindictina:BAAALgADCgEJAQAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgQJBwARAAAAAA==.Vixenne:BAAALgAECgEJAQAAAA==.Vizan:BAAALgAECgMJAwABLgAFFAMJBwATAKgSAA==.',
Vo='Void:BAAALgAECgUJCAABLgAFFAMJCAAZACwbAA==.Voidbloom:BAAALgADCgYJBgAAAA==.Voidvoid:BAAALgAECggJDgABLgAFFAMJBwATAP8YAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorggol:BAABLgAECn8rAAIbAAkJbRkoDgAIAgAbAAkJbRkoDgAIAgAAAA==.Vortexin:BAAALgADCgEJAQAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAICAAcJ0hXiZAC3AQACAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8OAAICAAQJlA2jVAAGAQACAAQJlA2jVAAGAQAuAAQKfyIAAgIACAmbHq0jAJoCAAIACAmbHq0jAJoCAAAA.',
We='Weeooeeooeeo:BAAALgAECggJCgABLgAECgkJRAAOAH4UAA==.Wellby:BAABLgAECn8WAAIWAAkJiQJmCwC+AAAWAAkJiQJmCwC+AAAAAA==.Westerin:BAABLgAECn84AAISAAkJMhzZAgB+AgASAAkJMhzZAgB+AgAAAA==.',
Wh='Whachagonado:BAAALgAECgIJAgAAAA==.Whatapal:BAAALgAECgQJBAAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgAECgQJBAAAAA==.Wimateeka:BAABLgAECn8eAAQXAAcJzh2QDwDMAQAXAAcJzh2QDwDMAQAEAAUJxRIPYQD4AAACAAQJlw2Y3QDRAAABLgAECgkJEwARAAAAAA==.Wimatreeka:BAAALgAECgkJEwAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgkJEwARAAAAAA==.Windfury:BAABLgAECn8bAAMfAAYJ6yS/BgCAAQAfAAYJIiG/BgCAAQAmAAMJHyXZBwDYAAABLgAFFAMJCAAZACwbAA==.Windigo:BAACLgAFFH8FAAIhAAMJ3gVxGgC2AAAhAAMJ3gVxGgC2AAAuAAQKfyAABCEABglcFbMHANgAABYABgnEEYInAAIBACEABQnUFrMHANgAABMAAwlyCMkeAYYAAAAA.Winginit:BAABLgAECn8YAAMNAAkJUBlADwByAgANAAkJUBlADwByAgALAAgJfw+6BgDAAAABLgAFFAkJHQAdAL4UAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAFFAEJAwAAAA==.Wootangz:BAAALgAECgEJAQABLgAECgQJCAARAAAAAA==.Worthyreaper:BAAALgAECgEJAQAAAA==.',
Wr='Wrastelas:BAAALgAECgQJCAAAAA==.',
Wu='Wurkim:BAAALgAECgEJAQABLgAECgQJCAARAAAAAA==.',
Wy='Wylder:BAAALgAECgQJBAABLgAFFAYJHwATAMYbAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xanto:BAABLgAFFH8WAAMIAAcJbR1wBwBDAgAIAAYJnh1wBwBDAgAgAAUJLxVIBQCRAQABLgAFFAkJOAADAKsZAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xe='Xenôn:BAAALgAECgYJBgAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAgAAAA==.',
Xo='Xolotl:BAAALgADCgIJAgAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJOAACALcUAA==.',
Ye='Yespaladin:BAAALgAFFAIJAgABLgAFFAcJGAAYAPQhAA==.',
Yi='Yiddosh:BAAALgAECgMJDAAAAA==.',
Yo='Yogí:BAACLgAFFH8YAAIaAAcJXRzpDgD2AQAaAAcJXRzpDgD2AQAuAAQKfx4AAxoACAk6I94FABQDABoACAk6I94FABQDACYABAkJDLkqAKMAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8gAAMHAAgJ+R9mCQByAgAHAAgJ+R9mCQByAgAVAAMJdBszIADXAAAAAA==.Yuwon:BAAALgAECgEJAQABLgAECggJHQAJACciAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8xAAMcAAkJKhUcEADmAQAcAAkJtBQcEADmAQAJAAIJuhBugQBzAAAAAA==.Zanalia:BAAALgAECgkJEQAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeeko:BAAALgAECgUJCAAAAA==.Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8tAAIQAAkJ3g1oTwCtAQAQAAkJ3g1oTwCtAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zenkuh:BAABLgAECn8ZAAIfAAYJviINBwB3AQAfAAYJviINBwB3AQABLgAFFAUJEAADAPEUAA==.Zensho:BAAALgAECgYJCQAAAA==.Zeplenith:BAAALgAECgIJAwAAAA==.',
Zi='Zipsion:BAABLgAECn8iAAIIAAkJ/iCQGwCAAgAIAAkJ/iCQGwCAAgAAAA==.Zithen:BAACLgAFFH8UAAMNAAUJNQ7oNQDsAAANAAUJNQ7oNQDsAAALAAEJ0QFsMAAlAAAuAAQKfyEABA0ACQmPGIojAKEBAA0ACQkPGIojAKEBAAwAAgnIF5IhAEgAAAsAAQncEoQOADYAAAAA.Zivver:BAABLgAECn8tAAIcAAkJYSJZBQDDAgAcAAkJYSJZBQDDAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECggJDgAAAA==.',
['Zé']='Zéná:BAAALgAECgMJAwAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIEAAgJUR/MGQA4AgAEAAgJUR/MGQA4AgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAABLgAECn8ZAAMCAAcJYBVPiABfAQACAAcJNRJPiABfAQAXAAUJ1BeWIQAIAQAAAA==.',
['Üt']='Üther:BAABLgAECn8uAAMCAAkJKiCxIwB2AgACAAkJHCCxIwB2AgAXAAIJKBzTMQCeAAAAAA==.',
['ßu']='ßubbleøseven:BAABLgAFFH8JAAICAAIJZyBTfAC9AAACAAIJZyBTfAC9AAAAAA==.',
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
