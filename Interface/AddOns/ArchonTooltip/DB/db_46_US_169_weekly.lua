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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Paladin-Holy','Paladin-Retribution','Priest-Discipline','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Warlock-Affliction','Warrior-Protection','Warrior-Arms','Paladin-Protection','Druid-Restoration','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Priest-Holy','DeathKnight-Frost','Shaman-Enhancement','Mage-Fire','Mage-Arcane','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aairidari:BAABLgAECn8eAAIBAAYJ2g60IgD9AAABAAYJ2g60IgD9AAAAAA==.',
Ab='Abruna:BAAALgAECgcJEgABLgAFFAYJFwACAMUYAA==.Abruno:BAACLgAFFH8XAAICAAYJxRgIFgCvAQACAAYJxRgIFgCvAQAuAAQKfy8AAgIACQmDIgkQAEgDAAIACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAYJFwACAMUYAA==.',
Ad='Adrians:BAABLgAECn8oAAICAAgJbBU8RADOAQACAAgJbBU8RADOAQAAAA==.',
Ae='Aeown:BAABLgAECn8hAAMDAAcJpQl0OQAVAQADAAcJpQl0OQAVAQAEAAEJagLxUQElAAABLgAECgkJOwAFAGQUAA==.Aerdis:BAAALgAECgUJBgABLgAECgcJDgAGAAAAAA==.',
Ag='Aggerwator:BAAALgAECgEJAgABLgAECgcJGAAHAMohAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAECgQJCgABLgAFFAQJDAAIAIkYAA==.',
Al='Alahrî:BAABLgAECn81AAQJAAkJ8xDqFgDhAQAJAAkJ8xDqFgDhAQAKAAYJ/gx9CQBGAQALAAcJ2wpvMgAVAQAAAA==.Alandrìas:BAABLgAECn8tAAIMAAkJnBR5BQD6AQAMAAkJnBR5BQD6AQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3WBQA9AwANAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn8uAAIJAAgJnxfCCAAZAgAJAAgJnxfCCAAZAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAICAAcJ2go3lgAUAQACAAcJ2go3lgAUAQAAAA==.Amirandis:BAAALgAECgYJBgAAAA==.Amuri:BAAALgAECgYJCwAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJCgAAAA==.Androonatorz:BAACLgAFFH8YAAIDAAYJFByWBgDnAQADAAYJFByWBgDnAQAuAAQKfy0AAwMACQkDJdMAAJ8DAAMACQkDJdMAAJ8DAAQABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAAALgAECgcJEgAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgAAAA==.Ardemus:BAABLgAECn8XAAMOAAYJIBILEQDnAAAOAAYJIBILEQDnAAAPAAEJYAAYNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAAALgAECgQJDAAAAA==.',
As='Ashborrn:BAAALgAECgUJCwAAAA==.Ashtar:BAABLgAECn8TAAIHAAgJvRN2KwBZAQAHAAgJvRN2KwBZAQAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgAQAJAWAA==.',
Aw='Awake:BAAALgAECgEJAQAAAA==.Awaken:BAAALgAECgcJEgAAAA==.Awoomonk:BAAALgAECgIJAgAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMRAAYJgBawEgBOAQARAAUJgBawEgBOAQASAAEJAAACOwAAAAAuAAQKfyEAAhEACAlFIWEVAPsCABEACAlFIWEVAPsCAAAA.Balddrex:BAAALgADCgkJCQAAAA==.Balefire:BAABLgAECn8kAAMPAAkJqBhkGgBMAgAPAAkJqBhkGgBMAgAOAAIJ7RhwKgBFAAAAAA==.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgADCgYJBgABLgAECggJJAATAJgNAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECgUJCQAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn8vAAICAAkJ4SCZDgDUAgACAAkJ4SCZDgDUAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAABLgAECn8yAAINAAkJexwmCgBoAgANAAkJexwmCgBoAgAAAA==.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgADCgkJDwAAAA==.Bluewaffles:BAAALgAECgEJAgABLgAECgIJAgAGAAAAAA==.',
Bo='Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8dAAIUAAYJAyADAwDxAQAUAAYJAyADAwDxAQAuAAQKfywAAhQACQmDJE0CACUDABQACQmDJE0CACUDAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAVAFwZAA==.Brimara:BAAALgAFFAEJAgAAAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQABLgAECggJDAAGAAAAAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJJwABANoPAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8aAAQWAAgJfR98DADYAQAWAAcJTx18DADYAQAXAAgJ7B2QDgCzAQAHAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMEAAYJehnygAB4AQAEAAYJTRnygAB4AQAYAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYhd9KwCmAQANAAcJBBV9KwCmAQAZAAcJkxfaOwBeAQAaAAIJ+gANOwAYAAAAAA==.Capz:BAACLgAFFH8iAAMXAAcJhiApAABHAgAXAAcJth4pAABHAgAHAAUJqCJVBwB3AQAuAAQKfyYAAxcACQnRIzwDANsCABcACAkCJTwDANsCAAcACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJCQAAAA==.Cassius:BAAALgAECgEJAQAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECgcJCQAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECgYJDQAAAA==.Celebrïmbor:BAAALgAECgMJAQAAAA==.',
Ch='Chair:BAAALgAECggJDQABLgAFFAMJBgACAFEDAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chopperr:BAAALgAECgQJBAAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8GAAICAAMJUQMUgwCBAAACAAMJUQMUgwCBAAAuAAQKfyoAAgIACQnZFtMzAAkCAAIACQnZFtMzAAkCAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8NAAIOAAQJMBQfAwA+AQAOAAQJMBQfAwA+AQAuAAQKf0QAAg4ACQlhJScAAGUDAA4ACQlhJScAAGUDAAAA.Clow:BAABLgAECn8YAAMHAAcJyiHMGgB1AgAHAAYJhyPMGgB1AgAXAAMJcRr2KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQAAAA==.Coolcrush:BAABLgAECn8jAAMbAAgJDyLlCABwAgAbAAgJvB7lCABwAgAcAAYJnyEwFQDGAQAAAA==.Corgnelius:BAAALgADCgYJDAAAAA==.Corven:BAACLgAFFH8UAAIPAAYJAhWwEwCRAQAPAAYJAhWwEwCRAQAuAAQKfz0AAw8ACQmJHwAKANQCAA8ACQmJHwAKANQCABUAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwAAAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJAwABLgAECgkJFgAQAOoOAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgcJDQAAAA==.Cryovox:BAAALgADCgYJCQAAAA==.',
Cu='Cumazzing:BAACLgAFFH8TAAIEAAYJxiT6AgAhAgAEAAYJxiT6AgAhAgAuAAQKfyoAAgQACQmNJrYCAK4DAAQACQmNJrYCAK4DAAAA.',
Da='Dadrin:BAAALgADCggJFQAAAA==.Daedyxes:BAABLgAECn8eAAISAAcJQhN/FABXAQASAAcJQhN/FABXAQAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Darfretail:BAABLgAECn8WAAIHAAgJAhGENgDOAQAHAAgJAhGENgDOAQAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgIJAgAAAA==.Daygath:BAABLgAECn8qAAIdAAkJjBQkFAD4AQAdAAkJjBQkFAD4AQAAAA==.',
De='Deadlyiris:BAABLgAECn8fAAMXAAkJlR2QBQBiAgAXAAkJlR2QBQBiAgAHAAYJHxCZSgB7AQABLgAECgkJHwAeAKMhAA==.Deatharin:BAAALgAECgYJDQAAAA==.Demonbulio:BAABLgAECn8kAAIBAAgJAxJxFACJAQABAAgJAxJxFACJAQAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAVAFwZAA==.Demonskitten:BAABLgAECn8fAAIVAAkJXBlQBAA8AgAVAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgADCgMJBQAAAA==.Descendantt:BAAALgADCgIJAgAAAA==.Devilbullet:BAAALgADCgIJAgAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn8yAAIEAAkJtxSoOgDSAQAEAAkJtxSoOgDSAQAAAA==.Dithehealer:BAABLgAECn8cAAMYAAkJVx73BABeAgAYAAkJVx73BABeAgAEAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAICAAYJQR6ZcQDwAQACAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECggJGQAfAMwSAA==.Doogie:BAAALgAECgEJAQAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAGAAAAAA==.Dragømir:BAAALgAECgEJAQAAAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8WAAMKAAUJDCLpAQB9AQAKAAUJBCHpAQB9AQALAAMJESKLGwAlAQAuAAQKfysAAwoACQkmJQcBAF0DAAoACAmKJQcBAF0DAAsACQkrJBECAEEDAAAA.Drenamai:BAABLgAECn8YAAITAAcJ2BKwUABYAQATAAcJ2BKwUABYAQAAAA==.Drewetta:BAABLgAECn8kAAINAAgJ2wx1JgBAAQANAAgJ2wx1JgBAAQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAGAAAAAA==.Durbana:BAAALgAECgMJAwAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgUJCAAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8RAAIEAAQJxSbwCACwAQAEAAQJxSbwCACwAQAuAAQKfzoAAgQACQkFJmsBAG4DAAQACQkFJmsBAG4DAAEuAAUUBgkTAAQAxiQA.',
El='Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8OAAIgAAYJZAeCCwBgAQAgAAYJZAeCCwBgAQAuAAQKfxYAAiAACQmBDSEmAMgBACAACQmBDSEmAMgBAAAA.Elvwyr:BAAALgADCgYJBwAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8LAAMdAAYJzxZXFQAhAQAdAAUJihVXFQAhAQAeAAEJ9wiSSwBNAAAuAAQKfyAAAx0ACAkkHtkTAIACAB0ACAkkHtkTAIACAB4ABAk3Cat1ALoAAAAA.Emmy:BAAALgAECgYJEwAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAAALgAFFAEJAQABLgAFFAYJFwABAPMeAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQAIAAYJDRZEEwCMAQABAAQJqB30AQB7AQAMAAEJECe3AwB2AAAuAAQKfy4AAwEACQl8JXMAAOgDAAEACQl8JXMAAOgDAAgABQkPG0lVADgBAAAA.Eneldenes:BAAALgAECgEJAQAAAA==.Enjoyer:BAAALgAECgYJEAAAAA==.',
Er='Ereitherla:BAABLgAECn8mAAITAAcJ+wuVWQA+AQATAAcJ+wuVWQA+AQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAECgYJBgAAAA==.',
Ex='Excalibear:BAABLgAECn8mAAIDAAgJ8BTAJgCIAQADAAgJ8BTAJgCIAQABLgAFFAUJDwACAEQaAA==.',
Ey='Eydis:BAAALgADCgUJBQAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECgEJAQAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fistbroz:BAAALgAECggJDgABLgAFFAYJGQAbAEwQAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAIRAAkJPxgoLwD9AQARAAkJPxgoLwD9AQAAAA==.Fleredil:BAABLgAECn84AAMhAAgJzRrDCgBxAgAhAAgJzRrDCgBxAgAUAAcJGiDSDwARAgAAAA==.Flingernle:BAAALgAECgEJAwAAAA==.Floista:BAAALgAECgYJBgAAAA==.Floistas:BAABLgAFFH8FAAITAAMJpggDUQCUAAATAAMJpggDUQCUAAAAAA==.',
Fo='Forepray:BAAALgAECgQJBgABLgAFFAYJFgAHADkbAA==.Forger:BAABLgAECn8rAAIWAAgJUBdSDQDIAQAWAAgJUBdSDQDIAQAAAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freeballin:BAAALgAECgEJAQABLgAECggJJgABAEAfAA==.Freshdk:BAACLgAFFH8UAAQRAAUJaiTHHwAcAQAiAAQJLhenBAA6AQARAAQJaiTHHwAcAQASAAEJAAANOgAAAAAuAAQKfzYABBEACQkFJHAMADcDABEACQkDJHAMADcDACIACAlhIakDADgCABIAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAECgkJLAAPAPQgAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostycheeks:BAACLgAFFH8HAAIRAAQJdRInOgDwAAARAAQJdRInOgDwAAAuAAQKfzQAAhEACAkII38SAJsCABEACAkII38SAJsCAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQIAAgJziIKFABjAgAIAAgJliIKFABjAgAMAAIJqiOlHABlAAABAAIJTxhARQBCAAAAAA==.Future:BAAALgAECgYJDQABLgAFFAMJBQAPABMZAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaerlan:BAAALgAECgQJBAAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgADCgEJAQAAAA==.',
Gh='Ghostblades:BAACLgAFFH8WAAMRAAUJfBhoFQBOAQARAAUJfBhoFQBOAQAiAAEJAAAQFAAAAAAuAAQKfykAAxEACQlOIbsNAMQCABEACQlOIbsNAMQCACIAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBAABLgAFFAcJGQAUALUaAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAAALgAFFAIJAgABLgAFFAUJDwACAEQaAA==.',
Gr='Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAAALgAECgQJBAABLgAECgkJQAAEAOcfAA==.Grinny:BAABLgAECn9AAAMEAAkJ5x/SDADIAgAEAAkJ5x/SDADIAgADAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8aAAIEAAgJdQrndAA7AQAEAAgJdQrndAA7AQABLgAECgkJHwAeAKMhAA==.Havochunter:BAAALgAECggJDAAAAA==.',
He='Heidegger:BAAALgAECgQJBQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8ZAAIfAAgJzBLdCwAnAQAfAAgJzBLdCwAnAQAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgADCgcJDQAAAA==.Holywráth:BAAALgADCgkJEwAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCQAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECgUJCQAAAA==.Hunterdh:BAABLgAECn8fAAITAAYJTgnbfADmAAATAAYJTgnbfADmAAAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8WAAIHAAYJORvNAwCtAQAHAAYJORvNAwCtAQAuAAQKfzAAAgcACQkIIVsFANECAAcACQkIIVsFANECAAAA.',
Ic='Icecandie:BAAALgAECgYJDQAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAUJFgAKAAwiAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJOwAFAGQUAA==.',
Im='Imistmypants:BAABLgAECn8WAAIQAAkJ6g5LHgCrAQAQAAkJ6g5LHgCrAQAAAA==.',
In='Infinitevoid:BAAALgADCgQJBAAAAA==.Innervatez:BAABLgAFFH8RAAIZAAcJlBnMAgBxAgAZAAcJlBnMAgBxAgAAAA==.Inspectda:BAABLgAECn8VAAIPAAgJgwcadgBxAQAPAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAIJAAgJJBs7CAAoAgAJAAgJJBs7CAAoAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn8oAAICAAgJ/BVdSADBAQACAAgJ/BVdSADBAQAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn82AAICAAkJfCTzBQAwAwACAAkJfCTzBQAwAwAAAA==.Jarten:BAABLgAECn8dAAIiAAgJESFGAwBKAgAiAAgJESFGAwBKAgAAAA==.Jaylebate:BAABLgAECn8wAAMRAAkJeR+PEACrAgARAAkJeR+PEACrAgASAAIJIxESNQBnAAAAAA==.',
Je='Jerrenn:BAAALgAECggJEgAAAA==.Jesseatamer:BAABLgAECn8fAAITAAgJ8yRZCADbAgATAAgJ8yRZCADbAgAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwAGAAAAAA==.',
Ju='Judge:BAAALgADCgEJAQAAAA==.Justar:BAAALgADCgIJAgAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAABLgAECn8UAAMTAAgJGRmHNQC1AQATAAgJaxaHNQC1AQAfAAcJ/BNcDAAeAQAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAIRAAkJVBZKLgABAgARAAkJVBZKLgABAgAAAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Kastia:BAAALgAECgQJCAAAAA==.Katrynwel:BAAALgAECgcJCwAAAA==.Katsumi:BAAALgADCgkJMQAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCgMJBgAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.',
Ki='Killalltoday:BAABLgAECn8tAAMeAAgJGxFqNwB1AQAeAAgJGxFqNwB1AQAjAAcJig1mEAA3AQAAAA==.Kilon:BAAALgAECgYJCAAAAA==.Kirkk:BAAALgADCgkJFAAAAA==.Kixarea:BAAALgADCgkJDQABLgAECgkJJQAZADcgAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAAALgAECgYJDQAAAA==.Knixx:BAACLgAFFH8TAAMUAAQJYQlfEgAgAQAUAAQJYQlfEgAgAQAFAAQJXwiGJQCYAAAuAAQKfzEABCEACQmpGGQbAAECACEABwk6GGQbAAECABQACQlqFWsUANwBAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIcAAkJUxHoHACDAQAcAAkJUxHoHACDAQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIQAAkJmhgGDQBnAgAQAAkJmhgGDQBnAgAAAA==.Koyya:BAAALgAECgkJEwAAAA==.',
Ku='Kufoo:BAABLgAECn8tAAMWAAgJIyaHAgDqAgAWAAgJgyWHAgDqAgAHAAgJSCXRBQDJAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJBQAPABMZAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8WAAIMAAgJyBMKBwDDAQAMAAgJyBMKBwDDAQAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
La='Layez:BAAALgADCgUJBQABLgAFFAIJAwAGAAAAAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Lethe:BAAALgAECgUJBQABLgAFFAYJDgAgAGQHAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAATAPsaAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgEJAgAGAAAAAA==.Lilyröse:BAAALgAECgEJAgAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn8tAAIPAAkJJBl2JAASAgAPAAkJJBl2JAASAgAAAA==.Lohmi:BAAALgAECgMJAwAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAABLgAECn8gAAINAAkJRgYFKQAvAQANAAkJRgYFKQAvAQAAAA==.',
Lu='Luania:BAAALgAECgQJCQAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgEJAQAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAYJCwAdAM8WAA==.',
Ma='Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn8xAAMCAAkJPRhNIwBSAgACAAkJPRhNIwBSAgAkAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgMJBAAAAA==.Mamadeezy:BAAALgAECgEJAQAAAA==.Manical:BAAALgAECgQJBgAAAA==.Mashiach:BAAALgADCgcJBwABLgAECgQJCAAGAAAAAA==.Maxgoon:BAABLgAECn8WAAIPAAcJwgzVcwB2AQAPAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQAAAA==.',
Me='Megumin:BAABLgAECn8WAAQCAAgJqBHckAAeAQACAAgJwhDckAAeAQAkAAMJeA8GCACtAAAlAAEJHRhtGgBEAAABLgAECgkJLQAEACogAA==.Mellisandria:BAAALgAECgYJCwAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn8lAAIcAAgJGR9xCgBUAgAcAAgJGR9xCgBUAgAAAA==.Merriska:BAACLgAFFH8FAAMDAAIJxyAEJgCjAAADAAIJxyAEJgCjAAAEAAEJHRFDcgBOAAAuAAQKfxkAAwQACQlAIaElAJACAAQABwnzIaElAJACAAMACAm7IJsTAHUCAAEuAAUUBAkJABAAdxcA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECggJDQABLgAECgkJAQAGAAAAAA==.Misseslovett:BAAALgADCgQJBAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8XAAImAAYJkQ7DBAA2AQAmAAYJkQ7DBAA2AQAuAAQKfzoAAiYACQnXG14EAH8CACYACQnXG14EAH8CAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAABLgAECn8oAAIDAAkJGyayAQBoAwADAAkJGyayAQBoAwAAAA==.Morgause:BAAALgAECgcJDwABLgAECggJIwANADMMAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.Mowenudown:BAAALgAECgEJAQAAAA==.',
Mu='Muirdin:BAABLgAECn8aAAITAAgJ+BB+QACMAQATAAgJ+BB+QACMAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMXAAkJYCKqBQBgAgAXAAkJbCGqBQBgAgAHAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAECgkJLAAPAPQgAA==.',
Na='Naanomage:BAAALgAECgYJCQAAAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAABLgAECn8sAAMPAAkJ9CBaCwDFAgAPAAgJ9CBaCwDFAgAOAAEJAAD2XABYAAAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMIAAkJrxzhIQCGAgAIAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn8sAAIKAAgJQQ2uBwB6AQAKAAgJQQ2uBwB6AQAAAA==.',
No='Noiire:BAAALgAECgIJAgABLgAFFAYJDgAgAGQHAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8RAAIUAAQJuSWLBAC+AQAUAAQJuSWLBAC+AQAuAAQKfzUAAhQACQnzJZEAAHkDABQACQnzJZEAAHkDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn8nAAIBAAkJ2g+KEQCuAQABAAkJ2g+KEQCuAQAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAAALgAECggJDQAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAUJEwAgAPcYAA==.',
Oa='Oakly:BAACLgAFFH8FAAIZAAMJnBBOQAB3AAAZAAMJnBBOQAB3AAAuAAQKfyUAAhkABwmoGzsfAAcCABkABwmoGzsfAAcCAAAA.',
Ob='Obsidian:BAAALgADCgMJAwABLgAECgkJKAADABsmAA==.',
On='Onaroll:BAAALgAFFAIJBAABLgAFFAYJFQAZAJsUAA==.',
Oo='Ooyagoddess:BAAALgAECgQJCwAAAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAUJEAATAHYfAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8XAAIbAAYJGSKfHAB6AQAbAAYJGSKfHAB6AQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAEJAQABLgAFFAUJFgAKAAwiAA==.Pann:BAAALgAECgEJAQABLgAECgYJCQAGAAAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn8mAAIdAAcJgRnmHwCQAQAdAAcJgRnmHwCQAQAAAA==.Pawsa:BAABLgAECn8hAAMbAAcJhhhLGQCYAQAbAAcJhhhLGQCYAQAcAAMJWQ+jagCYAAAAAA==.Pawthetic:BAACLgAFFH8VAAIZAAYJmxTfCQDOAQAZAAYJmxTfCQDOAQAuAAQKfy8AAxkACQkDITwDAGEDABkACQkDITwDAGEDAA0ACQmSGiEJAHsCAAAA.',
Pe='Peelforheals:BAABLgAECn8kAAMFAAcJuxUaHAC1AQAFAAcJuxUaHAC1AQAUAAYJ6RVPKgAsAQAAAA==.Penguindemic:BAABLgAECn8aAAIPAAgJBiYOHACtAgAPAAgJBiYOHACtAgAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJFgAQAOoOAA==.Pep:BAABLgAECn8fAAMbAAkJ1x1RBwCQAgAbAAkJ1x1RBwCQAgAQAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgADCgQJBAAAAA==.Petruccius:BAAALgAECgUJCgAAAA==.Pewpewlepew:BAAALgAECggJEAAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgcJDwAGAAAAAA==.Phaeku:BAAALgAECgcJDwAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJDAABLgAECggJIwAbAA8iAA==.Powermonk:BAAALgAECgMJAwAAAA==.',
Pr='Prey:BAAALgADCgEJAQAAAA==.Prospa:BAAALgAECgQJBQAAAA==.Prumper:BAACLgAFFH8FAAICAAQJ6QZCZgDGAAACAAQJ6QZCZgDGAAAuAAQKfzkAAgIACQlUH+UXAJICAAIACQlUH+UXAJICAAAA.',
Py='Pyric:BAAALgAECgEJAwAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgQJBgAAAA==.Qybxboogietk:BAAALgAECgEJAQAAAA==.',
Ra='Rabid:BAAALgADCgEJAQAAAA==.Raghallov:BAAALgADCggJCgAAAA==.Ragingstorm:BAAALgADCgIJAgAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8wAAIRAAkJPh2QEQCiAgARAAkJPh2QEQCiAgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgEJAQAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Regena:BAABLgAECn87AAMFAAkJZBThFADeAQAFAAkJawzhFADeAQAhAAkJUhRkFgDVAQAAAA==.Remorse:BAACLgAFFH8UAAIWAAYJ+xQ7BwBfAQAWAAYJ+xQ7BwBfAQAuAAQKfzoAAhYACQnfHisEAKcCABYACQnfHisEAKcCAAAA.Required:BAAALgAECgYJCAABLgAFFAcJHAAIACUcAA==.Retro:BAABLgAECn8YAAIdAAcJpgXQQQDVAAAdAAcJpgXQQQDVAAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8lAAMZAAkJNyDcDQCrAgAZAAgJGSDcDQCrAgANAAcJ4hjtFwC3AQAAAA==.Rim:BAABLgAECn8zAAIeAAkJ8R2OBgAAAwAeAAkJ8R2OBgAAAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8JAAICAAMJbBVlVAD8AAACAAMJbBVlVAD8AAAuAAQKfygAAgIACQnKH3gVAKICAAIACQnKH3gVAKICAAAA.',
Ro='Ronard:BAACLgAFFH8HAAIRAAIJthvDQQCeAAARAAIJthvDQQCeAAAuAAQKfz8AAhEACQlTJIQGAG8DABEACQlTJIQGAG8DAAAA.Ronfar:BAACLgAFFH8TAAIjAAUJhBWuBAAuAQAjAAUJhBWuBAAuAQAuAAQKf0IAAiMACQl6IbABAOICACMACQl6IbABAOICAAAA.',
Ru='Rukidingme:BAAALgADCgcJEAAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8mAAIEAAcJ5AmugAAkAQAEAAcJ5AmugAAkAQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAAALgAECggJEQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCgkJEAABLgAECggJHQAiABEhAA==.',
Sc='Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAIbAAcJVBRCLAB+AQAbAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQZAAgJdhy3JQAiAgAZAAcJ1By3JQAiAgANAAYJ+R6FHwADAgAmAAEJGQaYNQAfAAAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAECgkJDAAAAA==.Selen:BAABLgAECn8xAAIDAAkJ6R+DBAAXAwADAAkJ6R+DBAAXAwAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Seråphiel:BAAALgAECgQJEgAAAA==.Seswatha:BAACLgAFFH8PAAICAAUJRBp9GwBdAQACAAUJRBp9GwBdAQAuAAQKfy8AAgIACQlYIrcIAAsDAAIACQlYIrcIAAsDAAAA.',
Sh='Shadowbaron:BAAALgADCgkJGQAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAAALgAECgkJEwABLgAFFAYJGAADABQcAA==.Shamdi:BAAALgADCgYJBgAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAAALgADCgYJBgABLgAECgYJEAAGAAAAAA==.Shocktop:BAAALgAECggJEQAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAGAAAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Shìft:BAABLgAECn8sAAIZAAkJkxdWEQCCAgAZAAkJkxdWEQCCAgAAAA==.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgADCgYJBwAAAA==.Sillynanny:BAAALgAECgQJBAAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAAALgAECgQJEQABLgAECgcJEwAGAAAAAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8XAAImAAYJHSTsCQDiAQAmAAYJHSTsCQDiAQAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8rAAQlAAgJkyWfAgBmAgACAAgJjyB+LQC8AgAlAAYJsiKfAgBmAgAkAAQJcx81BABaAQABLgAFFAMJBQAPABMZAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIXAAkJCgvaEwBsAQAXAAkJCgvaEwBsAQAAAA==.Smugxl:BAAALgAECgYJBgAAAA==.',
So='Sonicberger:BAAALgADCgQJBAABLgAECggJIwARAP0bAA==.Sonicbergger:BAAALgAECgQJBAABLgAECggJIwARAP0bAA==.Sonicpoe:BAAALgADCgkJDAABLgAECggJIwARAP0bAA==.Sonícberger:BAABLgAECn8jAAMRAAgJ/RuTOQDVAQARAAgJ/RuTOQDVAQASAAQJTw85JgC/AAAAAA==.Soulcaliber:BAAALgADCgEJAQAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
St='Stain:BAAALgAECgUJCQAAAA==.Stealth:BAAALgAECggJCQABLgAFFAIJAwAGAAAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stith:BAAALgADCgIJAgAAAA==.Stkinbck:BAABLgAECn8mAAIgAAcJjRBpHgBFAQAgAAcJjRBpHgBFAQAAAA==.Stonehenge:BAABLgAECn8fAAIeAAkJoyGZCADfAgAeAAkJoyGZCADfAgAAAA==.Stonepalm:BAAALgADCggJEQAAAA==.Stratan:BAAALgAECgQJCAAAAA==.',
Su='Suffer:BAACLgAFFH8FAAIPAAMJExm5RwDzAAAPAAMJExm5RwDzAAAuAAQKfxYAAw8ABwlyJKsVAGsCAA8ABwlyJKsVAGsCAA4AAgn0GJFjAEcAAAAA.Sundermere:BAAALgAECgEJAQAAAA==.Sunlight:BAAALgADCgIJAgAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8ZAAIEAAcJiSDTIwCZAgAEAAcJiSDTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8ZAAQbAAYJTBAQDwALAQAbAAQJuAwQDwALAQAcAAUJJwxKEAD+AAAQAAIJ0wA3OQAmAAAuAAQKfzgAAxwACQmoGzoMADgCABsACAlmG3kTAFUCABwACQmEGToMADgCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.',
['Sä']='Sätansangel:BAAALgAECgEJAQAAAA==.',
Ta='Tabbz:BAABLgAECn8qAAMdAAkJfxnrDwAlAgAdAAkJfxnrDwAlAgAeAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgAECgEJAQAAAA==.Tallyhochick:BAABLgAECn8oAAITAAkJxwvZMwC8AQATAAkJxwvZMwC8AQAAAA==.Taman:BAABLgAECn8hAAMeAAcJbBtoGQAsAgAeAAcJbBtoGQAsAgAdAAcJOBamKADPAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAAALgAECgcJBwAAAA==.Telkon:BAAALgADCgYJBgAAAA==.Tellesto:BAABLgAECn8wAAMnAAkJnRzCCwAnAgAnAAkJqxrCCwAnAgATAAMJIhclnQCaAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECggJJAANANsMAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgADCgcJBwAAAA==.Thebigonion:BAAALgAECgEJAQAAAA==.',
Ti='Tibberino:BAAALgAECgcJBwAAAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8oAAMcAAgJOxxnFgC7AQAcAAgJJxtnFgC7AQAbAAUJghqxGgCLAQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwATADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMTAAkJMyEFDwDDAgATAAkJECAFDwDDAgAnAAQJtxADKwD3AAAAAA==.',
To='Toko:BAACLgAFFH8bAAITAAYJJSIyAwDgAQATAAYJJSIyAwDgAQAuAAQKfykAAxMACQkjIu8HAOACABMACQkjIu8HAOACAB8AAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMiAAkJlhrvAwArAgAiAAkJlhrvAwArAgASAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBAAAAA==.',
Tr='Trapattack:BAAALgADCgEJAQAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECgUJBQAGAAAAAA==.Truepatriot:BAACLgAFFH8JAAIDAAMJbxnPHgDbAAADAAMJbxnPHgDbAAAuAAQKfycAAwMACAmpExMyALcBAAMACAmpExMyALcBABgABQnpEmMdANQAAAAA.Truexlord:BAABLgAECn8WAAIRAAcJegyCdwAtAQARAAcJegyCdwAtAQAAAA==.Truthes:BAAALgAFFAIJAwAAAA==.Truthez:BAAALgADCgMJBgABLgAFFAIJAwAGAAAAAA==.Truths:BAAALgAECgIJAgABLgAFFAIJAwAGAAAAAA==.Truthsx:BAABLgAECn8kAAMVAAgJGiBJAwAgAgAVAAgJph9JAwAgAgAPAAUJchriYgA9AQABLgAFFAIJAwAGAAAAAA==.Truthz:BAAALgADCgYJBgABLgAFFAIJAwAGAAAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgQJBAAAAA==.Tygerkillz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAECgYJCAAAAA==.Tyraell:BAABLgAECn8sAAMDAAkJkR0dCADIAgADAAkJkR0dCADIAgAEAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAABLgAECn8aAAISAAgJEyFdBQDrAgASAAgJEyFdBQDrAgABLgAFFAYJGwATACUiAA==.',
Ud='Udor:BAABLgAECn8YAAITAAgJLgzERgB2AQATAAgJLgzERgB2AQAAAA==.',
Um='Umbrae:BAABLgAECn8qAAMhAAkJtxuGEAAbAgAhAAgJzBqGEAAbAgAUAAEJ4wd4WwBAAAAAAA==.',
Up='Upies:BAAALgAECgcJEwAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAAALgAECgUJDgAAAA==.',
Va='Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIPAAMJjwiiXgC7AAAPAAMJjwiiXgC7AAAuAAQKfyAAAg8ACQnbGdAYAFcCAA8ACQnbGdAYAFcCAAAA.',
Ve='Veera:BAABLgAECn8sAAIdAAkJ6BJDGQDGAQAdAAkJ6BJDGQDGAQAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Vendyr:BAABLgAECn8ZAAQVAAgJoyHxBwDOAQAPAAcJQx41LQBZAgAVAAYJYhjxBwDOAQAOAAIJ8AscYABPAAAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgMJAwAGAAAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorgol:BAABLgAECn8qAAIXAAkJbRnwBwAkAgAXAAkJbRnwBwAkAgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAIEAAcJ0hXiZAC3AQAEAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8NAAIEAAQJlA3zKAAwAQAEAAQJlA3zKAAwAQAuAAQKfxwAAgQACAmzHa0jAJoCAAQACAmzHa0jAJoCAAAA.',
We='Wellby:BAAALgAECgIJAgAAAA==.Westerin:BAABLgAECn8hAAIOAAkJBhpYAwAZAgAOAAkJBhpYAwAZAgAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgcJBwAAAA==.Wimateeka:BAABLgAECn8dAAQYAAcJzh2EDQCVAQAYAAcJzh2EDQCVAQADAAUJxRIPYQD4AAAEAAQJlw2Y3QDRAAAAAA==.Wimatreeka:BAAALgAECgIJAgAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgcJHQAYAM4dAA==.Windfury:BAAALgAECgYJEAABLgAFFAMJBQAPABMZAA==.Windigo:BAAALgAECgYJEwAAAA==.Winginit:BAAALgAECgcJDQABLgAFFAYJFQAZAJsUAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAECgYJBQAAAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAQAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJMgAEALcUAA==.',
Ye='Yespaladin:BAAALgAECgYJBwABLgAFFAQJEQAUALklAA==.',
Yi='Yiddosh:BAAALgAECgMJCQAAAA==.',
Yo='Yogí:BAACLgAFFH8QAAIeAAYJbhw8BAAPAgAeAAYJbhw8BAAPAgAuAAQKfxoAAx4ACAk6I94FABQDAB4ACAk6I94FABQDACMAAQk+A+IuACoAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8JAAMQAAQJdxdzEgBDAQAQAAQJdxdzEgBDAQAbAAMJdBsqEQD3AAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8ZAAIWAAYJEhMmHAAGAQAWAAYJEhMmHAAGAQAAAA==.Zanalia:BAAALgAECgMJBAABLgAECgUJBQAGAAAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8XAAIPAAgJEQr6WgBRAQAPAAgJEQr6WgBRAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zensho:BAAALgAECgYJCQAAAA==.',
Zi='Zipsion:BAABLgAECn8dAAITAAkJ/iBuEwBuAgATAAkJ/iBuEwBuAgAAAA==.Zithen:BAACLgAFFH8FAAMLAAMJVhFIOwB/AAALAAIJBQdIOwB/AAAJAAEJ0QHmIQA4AAAuAAQKfxgAAgsACQmfF4ojAKEBAAsACQmfF4ojAKEBAAAA.Zivver:BAABLgAECn8qAAIWAAkJXiJuAgDvAgAWAAkJXiJuAgDvAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECgMJBAAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIDAAgJUR8oEABQAgADAAgJUR8oEABQAgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAAALgAECgYJDQAAAA==.',
['Üt']='Üther:BAABLgAECn8tAAMEAAkJKiDoEwCRAgAEAAkJHCDoEwCRAgAYAAIJKhz7IwCiAAAAAA==.',
['ßu']='ßubbleøseven:BAAALgAFFAEJAgAAAA==.',
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
