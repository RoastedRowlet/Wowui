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

local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Paladin-Holy','Priest-Discipline','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Paladin-Protection','Druid-Restoration','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','Druid-Guardian','Priest-Holy','DeathKnight-Frost','Shaman-Enhancement','Mage-Fire','Mage-Arcane','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aairidari:BAABLgAECn8tAAIBAAgJbQ5XHABeAQABAAgJbQ5XHABeAQAAAA==.Aatrox:BAAALgAECgUJBQABLgAECgkJLQACACogAA==.',
Ab='Abruna:BAAALgAECgcJEwABLgAFFAYJFwADAMUYAA==.Abruno:BAACLgAFFH8XAAIDAAYJxRi4IACgAQADAAYJxRi4IACgAQAuAAQKfy8AAgMACQmDIgkQAEgDAAMACQmDIgkQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAYJFwADAMUYAA==.',
Ad='Adrians:BAABLgAECn8oAAIDAAgJbRXnUQDKAQADAAgJbRXnUQDKAQAAAA==.',
Ae='Aeown:BAABLgAECn8pAAMEAAgJgAo4QQAUAQAEAAcJpQk4QQAUAQACAAYJywXxtgDyAAABLgAECgkJQgAFAGQUAA==.Aerdis:BAAALgAECgYJDQABLgAECggJEQAGAAAAAA==.',
Ag='Aggerwator:BAAALgAECgEJAgABLgAECggJGgAHACciAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAECgQJCgABLgAFFAUJDwAIAIkYAA==.',
Al='Alahrî:BAACLgAFFH8GAAIJAAMJ2QXEGwCqAAAJAAMJ2QXEGwCqAAAuAAQKfzoABAkACQnzEOoWAOEBAAkACQnzEOoWAOEBAAoABgn+DGsLAD4BAAsABwnqCns4ACQBAAAA.Alandira:BAAALgAECgcJCAAAAA==.Alandrìas:BAABLgAECn8tAAIMAAkJnBThBgDxAQAMAAkJnBThBgDxAQAAAA==.Aloiss:BAAALgADCgUJCAAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3WBQA9AwANAAkJsB3WBQA9AwAAAA==.Altera:BAABLgAECn82AAIJAAgJShi6CQAlAgAJAAgJShi6CQAlAgAAAA==.',
Am='Amelya:BAABLgAECn8VAAIDAAcJ2gpprQALAQADAAcJ2gpprQALAQAAAA==.Amethystia:BAAALgADCgYJBgAAAA==.Amirandis:BAAALgAECgYJCwAAAA==.Amuri:BAAALgAECgcJEQAAAA==.',
An='Andelarenn:BAAALgAECgkJCQAAAA==.Andere:BAAALgAECggJCgAAAA==.Androonatorz:BAACLgAFFH8ZAAIEAAYJpRzXCADiAQAEAAYJpRzXCADiAQAuAAQKfy0AAwQACQkDJWkBAJMDAAQACQkDJWkBAJMDAAIABAn+ETi+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAAALgAECgcJEwAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgAAAA==.Ardemus:BAABLgAECn8XAAMOAAYJIBL5EwDiAAAOAAYJIBL5EwDiAAAPAAEJYAAYNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAAALgAECgUJEQAAAA==.',
As='Ashborrn:BAAALgAECgUJDAAAAA==.Ashtar:BAABLgAECn8TAAIHAAgJvhNoMwBWAQAHAAgJvhNoMwBWAQAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAAALgAECgYJCgABLgAECgkJIgAQAJEWAA==.',
Aw='Awake:BAAALgAECgEJAQAAAA==.Awaken:BAABLgAECn8YAAIDAAcJYh5oOgAUAgADAAcJYh5oOgAUAgAAAA==.Awoomonk:BAAALgAECgYJCgAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8aAAMRAAYJgBbeJACDAQARAAUJgBbeJACDAQASAAEJAAB2RgAAAAAuAAQKfyEAAhEACAlFIWEVAPsCABEACAlFIWEVAPsCAAAA.Balddrex:BAAALgADCgkJCQAAAA==.Balefire:BAABLgAECn8nAAMPAAkJ5hofHABhAgAPAAkJ5hofHABhAgAOAAIJ7RglMABDAAAAAA==.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgADCgcJDgABLgAECgkJJwATANsNAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAwAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECgUJDQAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn80AAIDAAkJUiFhEgDTAgADAAkJUiFhEgDTAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAABLgAECn8yAAINAAkJfBwEDQBhAgANAAkJfBwEDQBhAgAAAA==.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgAECgQJBAAAAA==.Bluewaffles:BAAALgAECgMJBQABLgAECgQJBAAGAAAAAA==.',
Bo='Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8dAAIUAAYJAyDSBADiAQAUAAYJAyDSBADiAQAuAAQKfzAAAhQACQmDJKMCAC0DABQACQmDJKMCAC0DAAAA.Breedableram:BAAALgADCgYJBgABLgAECgkJHwAVAFwZAA==.Brimara:BAAALgAFFAEJAgAAAA==.Brunomirror:BAAALgAECggJCAABLgAFFAYJFwADAMUYAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQABLgAECggJDwAGAAAAAA==.Bucketojoy:BAAALgAECgIJAgABLgAECgkJMAABAFkQAA==.Bunsen:BAAALgAECgEJAQABLgAFFAQJCwAWAO4ZAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8eAAQXAAgJqB9TEgCpAQAYAAcJTx1jDwDKAQAXAAgJih5TEgCpAQAHAAYJGw+dUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMCAAYJehnygAB4AQACAAYJTRnygAB4AQAZAAEJpgRBSQAgAAAAAA==.Candie:BAAALgAECgEJAwAAAA==.Candierain:BAAALgAECgEJAgAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYhd9KwCmAQANAAcJBBV9KwCmAQAaAAcJkRflQwBeAQAbAAIJ+gANOwAYAAAAAA==.Capz:BAACLgAFFH8oAAMXAAcJyyApAABHAgAXAAcJBiApAABHAgAHAAUJqCJVBwB3AQAuAAQKfyYAAxcACQnRIzwDANsCABcACAkCJTwDANsCAAcACQktHq4PANUCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgUJDAAAAA==.Cassius:BAAALgAECgEJAgAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECggJCwAAAA==.',
Cd='Cdlam:BAAALgAECgQJBAAAAA==.',
Ce='Ceez:BAAALgAECgYJDQAAAA==.Cefteldore:BAAALgADCgcJBwAAAA==.Celebrïmbor:BAAALgAECgMJAQAAAA==.',
Ch='Chair:BAAALgAECggJDQABLgAFFAMJCQADAEgHAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chopperr:BAAALgAECgQJBAAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAACLgAFFH8JAAIDAAMJSAcEcADTAAADAAMJSAcEcADTAAAuAAQKfywAAgMACQkWGAY8AA4CAAMACQkWGAY8AA4CAAAA.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8OAAIOAAUJMBQZBAAzAQAOAAUJMBQZBAAzAQAuAAQKf0QAAg4ACQlhJTwAAF4DAA4ACQlhJTwAAF4DAAAA.Clow:BAABLgAECn8aAAMHAAgJJyLMGgB1AgAHAAcJqiPMGgB1AgAXAAMJcRr2KgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQAAAA==.Coolcrush:BAABLgAECn8sAAMcAAgJZyU8BAD4AgAcAAgJZyU8BAD4AgAdAAYJ9iEDFgDbAQAAAA==.Corgnelius:BAAALgADCgYJDAAAAA==.Corven:BAACLgAFFH8VAAIPAAYJAhXDGwCPAQAPAAYJAhXDGwCPAQAuAAQKf0YAAw8ACQkqI/QDAEIDAA8ACQkqI/QDAEIDABUAAQkAALk0ADIAAAAA.Corvenicus:BAAALgAECgMJAwAAAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crenty:BAAALgAECgIJBAABLgAECgkJIAAQAEcUAA==.Crosis:BAAALgAECgYJDgAAAA==.Crossfaded:BAAALgAECgkJEgAAAA==.Cryovox:BAAALgAECgQJBAAAAA==.',
Cu='Cumazzing:BAACLgAFFH8WAAICAAcJXCJaAgB0AgACAAcJXCJaAgB0AgAuAAQKfyoAAgIACQmJJrYCAK4DAAIACQmJJrYCAK4DAAAA.',
Da='Dadrin:BAAALgADCggJHQAAAA==.Daedyxes:BAABLgAECn8mAAISAAgJzxXfEgCyAQASAAgJzxXfEgCyAQAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Daní:BAAALgAECgQJBAAAAA==.Darfretail:BAABLgAECn8aAAIHAAgJEBKENgDOAQAHAAgJEBKENgDOAQAAAA==.Darkdemon:BAAALgAECgMJAwAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgAECgQJBwAAAA==.Daygath:BAABLgAECn8xAAIeAAkJbxUPFgAKAgAeAAkJbxUPFgAKAgAAAA==.',
De='Deadlyiris:BAABLgAECn8iAAMXAAkJ5h0CBgCAAgAXAAkJ5h0CBgCAAgAHAAYJHxCZSgB7AQABLgAFFAQJCwAWAO4ZAA==.Deatharin:BAAALgAECgYJDQAAAA==.Decompose:BAAALgAECgEJAgAAAA==.Demonbulio:BAABLgAECn8sAAIBAAgJIBWPEgDMAQABAAgJIBWPEgDMAQAAAA==.Demonisthicc:BAAALgAECgMJBQABLgAECgkJHwAVAFwZAA==.Demonskitten:BAABLgAECn8fAAIVAAkJXBlQBAA8AgAVAAkJXBlQBAA8AgAAAA==.Demonslayeer:BAAALgAECgEJAQAAAA==.Descendantt:BAAALgADCgIJAgAAAA==.Devilbullet:BAAALgADCgIJAwAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn84AAICAAkJtxSWRQDWAQACAAkJtxSWRQDWAQAAAA==.Dithehealer:BAABLgAECn8iAAMZAAkJ5B+jAgDXAgAZAAkJ5B+jAgDXAgACAAEJmQdyTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.Divinecandie:BAAALgAECgEJAQAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAIDAAYJQR6ZcQDwAQADAAYJQR6ZcQDwAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECggJGQAfAM0SAA==.Doogie:BAAALgAECgEJAgAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgYJCQAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAGAAAAAA==.Dragømir:BAAALgAECgEJAQAAAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8WAAMKAAUJDCLpAQB9AQAKAAUJBCHpAQB9AQALAAMJESLqIAAYAQAuAAQKfysAAwoACQkmJQcBAF0DAAoACAmKJQcBAF0DAAsACQkqJKkCAEEDAAAA.Drenamai:BAABLgAECn8hAAITAAkJMBPNLAAAAgATAAkJMBPNLAAAAgAAAA==.Drewetta:BAABLgAECn8sAAINAAkJIA5RHgCnAQANAAkJIA5RHgCnAQAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAGAAAAAA==.Durbana:BAAALgAECgQJBAAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgUJCgAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8SAAICAAUJwSaHCQDMAQACAAUJwSaHCQDMAQAuAAQKfzoAAgIACQkGJq4BAMgDAAIACQkGJq4BAMgDAAEuAAUUBwkWAAIAXCIA.',
El='Elandin:BAAALgAECgUJBQAAAA==.Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8OAAIgAAYJZAebEABVAQAgAAYJZAebEABVAQAuAAQKfxYAAiAACQmBDSEmAMgBACAACQmBDSEmAMgBAAAA.Elvwyr:BAAALgAECgEJAQAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8MAAMeAAYJcRgvGQAfAQAeAAUJlRcvGQAfAQAWAAEJ9wi8WgBMAAAuAAQKfyAAAx4ACAkkHtkTAIACAB4ACAkkHtkTAIACABYABAk3Cat1ALoAAAAA.Emmy:BAAALgAECgYJEwAAAA==.Emogothbabe:BAAALgAECgUJBQAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAAALgAFFAIJAwABLgAFFAYJFwABAPMeAA==.Endorush:BAACLgAFFH8XAAQBAAYJ8x70AQB7AQAIAAYJDRZcGwCBAQABAAQJqB30AQB7AQAMAAEJECe3AwB2AAAuAAQKfzcAAwEACQl9JXMAAOgDAAEACQl8JXMAAOgDAAgACQlkIoMEAC0DAAAA.Eneldenes:BAAALgAECgEJAQAAAA==.Enjoyer:BAAALgAECgcJEQAAAA==.',
Er='Ereitherla:BAABLgAECn8tAAITAAgJSAv0VQBzAQATAAgJSAv0VQBzAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAECgYJCwAAAA==.',
Ex='Excalibear:BAABLgAECn8vAAIEAAkJPRYbHwDjAQAEAAkJPRYbHwDjAQABLgAFFAUJDwADAEQaAA==.',
Ey='Eydis:BAAALgADCgUJBQAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJFwAAAA==.',
Fa='Faithchill:BAAALgAECgMJAwAAAA==.Fatherjeff:BAAALgADCgkJDQAAAA==.Fayith:BAAALgADCgEJAQAAAA==.',
Fe='Feironor:BAAALgAECgEJAQAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fircey:BAAALgAECgEJAQABLgAFFAIJAwAGAAAAAA==.Fistbroz:BAABLgAECn8XAAMhAAkJFBToDADZAQAhAAkJFBToDADZAQAbAAMJnweWKACIAAABLgAFFAYJGgAcABcRAA==.',
Fl='Flawpeacok:BAABLgAECn8cAAIRAAkJPxjqOAD6AQARAAkJPxjqOAD6AQAAAA==.Fleredil:BAABLgAECn8/AAMiAAgJzRqADQBmAgAiAAgJzRqADQBmAgAUAAcJGiCwFAADAgAAAA==.Flingernle:BAAALgAECgEJAwAAAA==.Floista:BAAALgAECggJDQAAAA==.Floistas:BAABLgAFFH8GAAITAAMJIQobSQDUAAATAAMJIQobSQDUAAAAAA==.',
Fo='Forepray:BAAALgAECgkJEgABLgAFFAYJFwAHADkbAA==.Forger:BAABLgAECn8zAAIYAAkJmhYWCwAZAgAYAAkJmhYWCwAZAgAAAA==.Forsakey:BAAALgADCgEJAQABLgAFFAQJDAAaAHUcAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freeballin:BAAALgAECgEJAwABLgAECggJLgABACkgAA==.Freshdk:BAACLgAFFH8UAAQRAAUJaiSBJQCBAQARAAQJaiSBJQCBAQAjAAQJLhdPCAArAQASAAEJAAB3RQAAAAAuAAQKfzYABBEACQkFJHAMADcDABEACQkDJHAMADcDACMACAlhISEFACoCABIAAQljDnVBAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAECgkJMgAPAPsgAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostycheeks:BAACLgAFFH8LAAIRAAQJ6BUKRQA8AQARAAQJ6BUKRQA8AQAuAAQKfzUAAhEACAkKIwMYAJUCABEACAkKIwMYAJUCAAAA.Frostywaffle:BAAALgAECgEJAQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8oAAQIAAgJ0CJVGQBgAgAIAAgJlyJVGQBgAgAMAAIJqiM3IQBkAAABAAIJTxhmUABAAAAAAA==.Future:BAAALgAECgYJDQABLgAFFAMJCAAVACwbAA==.Fuzzycat:BAAALgADCgEJAQAAAA==.',
Ga='Gaerlan:BAAALgAECgQJBAAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgADCgEJAQAAAA==.',
Gh='Ghostblades:BAACLgAFFH8WAAMRAAUJfBhoFQBOAQARAAUJfBhoFQBOAQAjAAEJAABiHAAAAAAuAAQKfykAAxEACQlOIfASALgCABEACQlOIfASALgCACMAAQnbHDcWADgAAAAA.Ghostdk:BAAALgAECgEJAgAAAA==.Ghostsham:BAAALgADCgMJAwAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJBAABLgAFFAcJGgAUALAaAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAAALgAFFAMJAwABLgAFFAUJDwADAEQaAA==.',
Gr='Grimzero:BAAALgADCgMJAwAAAA==.Grinnee:BAAALgAECgcJCwABLgAECgkJQgACAOcfAA==.Grinny:BAABLgAECn9CAAMCAAkJ5x9lEgC6AgACAAkJ5x9lEgC6AgAEAAIJowMyjQBKAAAAAA==.Grobthar:BAAALgADCgYJBgAAAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8aAAICAAgJdQp8hgBCAQACAAgJdQp8hgBCAQABLgAFFAQJCwAWAO4ZAA==.Havochunter:BAAALgAECggJDwAAAA==.',
He='Heidegger:BAAALgAECgQJBQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAABLgAECn8ZAAIfAAgJzRLLDABsAQAfAAgJzRLLDABsAQAAAA==.Heriod:BAAALgAECgEJAgAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgADCgcJDQAAAA==.Holywráth:BAAALgADCgkJEwAAAA==.Horndoggie:BAAALgAECgYJBgAAAA==.Hotea:BAAALgAECgUJCgAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECgUJDQAAAA==.Hunterdh:BAABLgAECn8lAAITAAcJjAivfAAXAQATAAcJjAivfAAXAQAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8XAAIHAAYJORuYBgChAQAHAAYJORuYBgChAQAuAAQKfzAAAgcACQkIITcIAL4CAAcACQkIITcIAL4CAAAA.',
Ic='Icecandie:BAAALgAECgYJDQAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAUJFgAKAAwiAA==.Ilostthegame:BAAALgADCgIJAgABLgAECgkJQgAFAGQUAA==.',
Im='Imistmypants:BAABLgAECn8gAAIQAAkJRxT0FgAkAgAQAAkJRxT0FgAkAgAAAA==.',
In='Infinitevoid:BAAALgADCgUJCQAAAA==.Innervatez:BAABLgAFFH8YAAIaAAgJ4hx6AQD1AgAaAAgJ4hx6AQD1AgAAAA==.Inspectda:BAABLgAECn8VAAIPAAgJgwcadgBxAQAPAAgJgwcadgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAABLgAECn8cAAIJAAgJJBvdCQAiAgAJAAgJJBvdCQAiAgAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn8wAAIDAAgJQhaNUQDLAQADAAgJQhaNUQDLAQAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn82AAIDAAkJfSS1CAAiAwADAAkJfSS1CAAiAwAAAA==.Jarten:BAABLgAECn8dAAIjAAgJFCHdBAA0AgAjAAgJFCHdBAA0AgAAAA==.Jaylebate:BAABLgAECn8yAAMRAAkJeh8+FwCaAgARAAkJeh8+FwCaAgASAAIJJBHAPwBgAAAAAA==.',
Je='Jerrenn:BAABLgAECn8WAAMCAAgJdBNOeABdAQACAAcJHRNOeABdAQAEAAEJlgNznQAsAAAAAA==.Jesseatamer:BAABLgAECn8fAAITAAgJ8ySUDADJAgATAAgJ8ySUDADJAgAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jortak:BAAALgAECgcJCwABLgAECgkJMgARAHofAA==.Jouska:BAAALgAECgYJCwABLgAECgcJBwAGAAAAAA==.',
Ju='Judge:BAAALgADCgEJAQAAAA==.Justar:BAAALgADCgMJBQAAAA==.',
['Jë']='Jësus:BAAALgAECgcJBgAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAABLgAECn8UAAMfAAgJGhlzDQBfAQATAAgJbBa/QQCxAQAfAAcJ/BNzDQBfAQABLgAFFAIJAgAGAAAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAABLgAECn8UAAIRAAkJVBYpOQD5AQARAAkJVBYpOQD5AQAAAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Kastia:BAAALgAECgQJCAAAAA==.Katrynwel:BAAALgAECggJEwAAAA==.Katsumi:BAAALgADCgkJPAAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Ke='Keení:BAAALgADCgkJCQAAAA==.Kellenah:BAAALgADCgMJCQAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.Khaliana:BAAALgADCgEJAQAAAA==.Khold:BAAALgAECgcJBwAAAA==.',
Ki='Killalltoday:BAABLgAECn81AAMWAAgJMxHnQQB0AQAWAAgJMxHnQQB0AQAkAAcJjQ1aFAAzAQAAAA==.Kilon:BAAALgAFFAEJAQAAAA==.Kirkk:BAAALgAECgEJAQAAAA==.Kivareous:BAAALgADCgkJCQABLgAECgkJJQAaADcgAA==.Kixarea:BAAALgADCgkJDQABLgAECgkJJQAaADcgAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAAALgAECgYJDQAAAA==.Knixx:BAACLgAFFH8TAAMUAAQJYQmoFgAVAQAUAAQJYQmoFgAVAQAFAAQJXwiNLACWAAAuAAQKfzwABBQACQmPGOENAFMCABQACQmPGOENAFMCACIABwk6GGQbAAECAAUABgldEMYtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIdAAkJUxFIIQB/AQAdAAkJUxFIIQB/AQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8rAAIQAAkJmhiQEABpAgAQAAkJmhiQEABpAgAAAA==.Koyya:BAAALgAECgkJEwAAAA==.',
Ku='Kufoo:BAABLgAECn81AAMHAAgJIyZWBQDyAgAHAAgJfiVWBQDyAgAYAAgJgyVnAwDhAgAAAA==.Kuma:BAAALgAECgUJCQABLgAFFAMJCAAVACwbAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAABLgAECn8XAAIMAAgJdhSCCADBAQAMAAgJdhSCCADBAQAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
['Ké']='Kéndra:BAAALgAECgMJAwAAAA==.',
La='Lascerette:BAAALgAECgMJAwAAAA==.Law:BAAALgADCgIJAgAAAA==.Layez:BAAALgADCgUJBQABLgAFFAIJAwAGAAAAAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Lethe:BAAALgAECgUJBQABLgAFFAYJDgAgAGQHAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJMAATAAAbAA==.Lilgeeked:BAAALgADCgcJDAAAAA==.Liliannarose:BAAALgADCgEJAQABLgAECgEJAgAGAAAAAA==.Lilyröse:BAAALgAECgEJAgAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn8xAAIPAAkJFRocJgArAgAPAAkJFRocJgArAgAAAA==.Lohmi:BAAALgAECgUJBQAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAABLgAECn8jAAINAAkJYwgeKgBSAQANAAkJYwgeKgBSAQAAAA==.',
Lu='Luania:BAAALgAECgQJCgAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lurtz:BAAALgAECgYJCgAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgAECgEJAQAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.Lyzzardkng:BAAALgAECgYJBgAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAYJDAAeAHEYAA==.',
Ma='Maango:BAAALgAECgkJCAAAAA==.Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn86AAMDAAkJYRltJgBlAgADAAkJYRltJgBlAgAlAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgQJCAAAAA==.Mamadeezy:BAAALgAECgEJAgAAAA==.Manical:BAAALgAECgYJDQAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAQJEAARAI8WAA==.Maxgoon:BAABLgAECn8WAAIPAAcJwgzVcwB2AQAPAAcJwgzVcwB2AQAAAA==.',
Mc='Mcfist:BAAALgAECgUJBQAAAA==.',
Me='Megumin:BAABLgAECn8cAAQDAAgJdhPWVQC+AQADAAgJ7hLWVQC+AQAlAAMJeA9JCQCrAAAmAAIJ3xNtGgBEAAABLgAECgkJLQACACogAA==.Mellisandria:BAAALgAECgcJEQAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn8tAAIdAAgJ5SL8BQDBAgAdAAgJ5SL8BQDBAgAAAA==.Merriska:BAACLgAFFH8FAAMEAAIJxyARLACdAAAEAAIJxyARLACdAAACAAEJHRGWhwBLAAAuAAQKfxsAAwIACQk1IqElAJACAAIACAlWI6ElAJACAAQACAm7IJsTAHUCAAEuAAUUBAkNABAAUCIA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECggJEAABLgAECgkJBQAGAAAAAA==.Misseslovett:BAAALgADCgQJBAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8XAAIhAAYJkQ4PBwA0AQAhAAYJkQ4PBwA0AQAuAAQKfzwAAiEACQmmHE0FAIQCACEACQmmHE0FAIQCAAAA.Mithras:BAAALgAECgEJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAABLgAECn8wAAMEAAkJGyayAQBoAwAEAAkJGyayAQBoAwACAAEJYRmENQFLAAAAAA==.Morgause:BAAALgAECgcJEAABLgAECggJJwANABANAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.Mowenudown:BAAALgAECgEJAQAAAA==.',
Mu='Muirdin:BAABLgAECn8aAAITAAgJ9xCMTwCGAQATAAgJ9xCMTwCGAQAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8fAAMXAAkJYCK2BwBTAgAXAAkJbCG2BwBTAgAHAAUJNRtqTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgAECgUJBQABLgAECgkJMgAPAPsgAA==.',
Na='Naanomage:BAAALgAECgYJDAAAAA==.Nagakabouros:BAAALgADCgEJAQAAAA==.Nagato:BAAALgADCgcJBwAAAA==.Naksami:BAAALgAECgIJAgAAAA==.',
Ne='Necrotoxin:BAABLgAECn8yAAMPAAkJ+yAqDgDEAgAPAAgJ+yAqDgDEAgAOAAEJAAD2XABYAAAAAA==.Nemoralia:BAAALgADCgIJAwAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMIAAkJrxzhIQCGAgAIAAkJOhrhIQCGAgABAAUJBCGyJgCLAQAAAA==.Nirath:BAABLgAECn80AAIKAAgJMw6wCACBAQAKAAgJMw6wCACBAQAAAA==.',
No='Noiire:BAAALgAFFAEJAQABLgAFFAYJDgAgAGQHAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8RAAIUAAQJuSXTBgCxAQAUAAQJuSXTBgCxAQAuAAQKfzUAAhQACQnzJdQAAHcDABQACQnzJdQAAHcDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn8wAAMBAAkJWRD7FACuAQABAAkJWRD7FACuAQAIAAMJcAR63wBEAAAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAAALgAECggJDQAAAA==.Nullfox:BAAALgADCgUJBQABLgAFFAYJGQAgAHwfAA==.',
Oa='Oakly:BAACLgAFFH8GAAIaAAMJsBCVMQDKAAAaAAMJsBCVMQDKAAAuAAQKfy4AAhoACAk0HicQALECABoACAk0HicQALECAAAA.',
Ob='Obsidian:BAAALgAECgEJAQABLgAECgkJMAAEABsmAA==.',
On='Onaroll:BAAALgAFFAIJBAABLgAFFAYJFgAaAIoVAA==.Onehotelf:BAAALgAECgUJBQAAAA==.',
Oo='Ooyagoddess:BAAALgAECgYJEgAAAA==.',
Ot='Otoah:BAAALgAECgYJBgABLgAFFAUJFQATAKofAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAABLgAECn8cAAIcAAYJ2SIUHACkAQAcAAYJ2SIUHACkAQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pamanda:BAAALgAFFAEJAQABLgAFFAUJFgAKAAwiAA==.Pann:BAAALgAECgEJAQABLgAECgYJDAAGAAAAAA==.Papatiny:BAAALgAECgYJBgAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn8sAAIeAAgJRxcIHgDFAQAeAAgJRxcIHgDFAQAAAA==.Pawsa:BAABLgAECn8rAAMcAAcJyhonFwDTAQAcAAcJyhonFwDTAQAdAAMJWQ+jagCYAAAAAA==.Pawthetic:BAACLgAFFH8WAAIaAAYJihUQDQDNAQAaAAYJihUQDQDNAQAuAAQKfy8AAxoACQkDITwDAGEDABoACQkDITwDAGEDAA0ACQmRGqwLAHQCAAAA.',
Pe='Peelforheals:BAACLgAFFH8FAAIFAAIJQwpzMQB9AAAFAAIJQwpzMQB9AAAuAAQKfycAAwUACAlqFBocALUBAAUABwm7FRocALUBABQABwlrFs8kAHsBAAAA.Penguindemic:BAABLgAECn8iAAIPAAkJ/CVaBgAXAwAPAAkJ/CVaBgAXAwAAAA==.Pentimus:BAAALgADCgYJCAABLgAECgkJIAAQAEcUAA==.Pep:BAABLgAECn8fAAMcAAkJ1x3GCQCDAgAcAAkJ1x3GCQCDAgAQAAEJUwMRcwAgAAAAAA==.Pephunt:BAAALgAECgEJAQAAAA==.Pepperoni:BAAALgADCgQJBAAAAA==.Petruccius:BAABLgAECn8ZAAINAAgJbRplEQAnAgANAAgJbRplEQAnAgAAAA==.Pewpewlepew:BAAALgAECggJEgAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECggJEQAGAAAAAA==.Phaeku:BAAALgAECggJEQAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Ponfarr:BAAALgAECgUJBQAAAA==.Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgYJDgABLgAECggJLAAcAGclAA==.Powermonk:BAAALgAECgQJBAAAAA==.',
Pr='Prayre:BAAALgADCgkJEgAAAA==.Prey:BAAALgAECgQJBAAAAA==.Prospa:BAAALgAECgQJBwAAAA==.Prumper:BAACLgAFFH8HAAIDAAQJMgnlcgDJAAADAAQJMgnlcgDJAAAuAAQKf0EAAgMACQlUH18eAIwCAAMACQlUH18eAIwCAAAA.',
Py='Pyric:BAAALgAECgEJBAAAAA==.',
Qu='Quesoblanco:BAAALgAECgcJBgAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgQJBgAAAA==.Qybxboogiemo:BAAALgAECgEJAgAAAA==.Qybxboogietk:BAAALgAECgEJAQAAAA==.',
Ra='Rabid:BAAALgAECgEJAgAAAA==.Raghallov:BAAALgADCggJCgAAAA==.Ragingstorm:BAAALgADCgIJAwAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8wAAIRAAkJPx1SGACTAgARAAkJPx1SGACTAgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgEJAQAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Regena:BAABLgAECn9CAAQFAAkJZBSbGQDXAQAFAAkJawybGQDXAQAiAAkJUhSPGgDNAQAUAAcJ3Ai4NQAYAQAAAA==.Relyssa:BAAALgAECgQJBAAAAA==.Remorse:BAACLgAFFH8VAAIYAAYJ+BVVCQBbAQAYAAYJ+BVVCQBbAQAuAAQKf0MAAhgACQkrIR8DAOwCABgACQkrIR8DAOwCAAAA.Required:BAAALgAFFAMJAwABLgAFFAcJHwAIACUcAA==.Retro:BAABLgAECn8cAAIeAAcJFQcTSQDfAAAeAAcJFQcTSQDfAAAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8lAAMaAAkJNyD1EACpAgAaAAgJGiD1EACpAgANAAcJ4hgDHQCzAQAAAA==.Rim:BAABLgAECn88AAIWAAkJfB7QBwALAwAWAAkJfB7QBwALAwAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAACLgAFFH8MAAIDAAMJ+Bu2WgAIAQADAAMJ+Bu2WgAIAQAuAAQKfyoAAgMACQlIIYQXALICAAMACQlIIYQXALICAAAA.',
Ro='Ronard:BAACLgAFFH8HAAIRAAIJthv+mQCcAAARAAIJthv+mQCcAAAuAAQKf0YAAhEACQloJIQGAG8DABEACQloJIQGAG8DAAAA.Ronfar:BAACLgAFFH8UAAIkAAUJPBbvBQAtAQAkAAUJPBbvBQAtAQAuAAQKf0oAAiQACQnEIr0AAD0DACQACQnEIr0AAD0DAAAA.',
Ru='Rukidingme:BAAALgAECgEJAgAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Rustyglass:BAAALgAECgEJAQAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8pAAICAAgJyQk7eQBbAQACAAgJyQk7eQBbAQAAAA==.Ryno:BAAALgAECgUJBgAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAABLgAECn8XAAICAAgJMgpqfgBRAQACAAgJMgpqfgBRAQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgUJCQAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCgkJEAABLgAECggJHQAjABQhAA==.',
Sc='Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8XAAIcAAcJVBRCLAB+AQAcAAcJVBRCLAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQaAAgJdhy3JQAiAgAaAAcJ1By3JQAiAgANAAYJ+R6FHwADAgAhAAEJGQaYNQAfAAAAAA==.Scubowsuit:BAAALgAECgMJAwAAAA==.',
Se='Sedria:BAAALgADCgQJBAAAAA==.Segarth:BAAALgAECgkJDQAAAA==.Selen:BAABLgAECn86AAIEAAkJ6CC3BQAWAwAEAAkJ6CC3BQAWAwAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Semtex:BAAALgAECgEJAQAAAA==.Seråphiel:BAABLgAECn8YAAITAAYJBQSHqwCvAAATAAYJBQSHqwCvAAAAAA==.Seswatha:BAACLgAFFH8PAAIDAAUJRBp9GwBdAQADAAUJRBp9GwBdAQAuAAQKfzAAAgMACQlaIqsLAAUDAAMACQlaIqsLAAUDAAAA.',
Sh='Shadowbaron:BAAALgAECgQJBAAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAABLgAECn8cAAMWAAkJWiKoBwAOAwAWAAkJWiKoBwAOAwAeAAUJ1xitRQDtAAABLgAFFAYJGQAEAKUcAA==.Shamdi:BAAALgADCgYJBgAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAAALgADCgYJBgABLgAECgcJEQAGAAAAAA==.Shocktop:BAABLgAECn8VAAIkAAgJ7CDJBgA2AgAkAAgJ7CDJBgA2AgAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAGAAAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Shìft:BAABLgAECn8zAAIaAAkJVxlDEQClAgAaAAkJVxlDEQClAgAAAA==.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgADCgYJBwAAAA==.Sillynanny:BAAALgAECgUJCQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAABLgAECn8VAAQBAAUJphnZIwAeAQABAAUJQhjZIwAeAQAMAAMJCRRvGQCqAAAIAAIJKA3dyABmAAABLgAECggJFgATAA0XAA==.Sliizzy:BAAALgADCgYJCQAAAA==.Slimydruid:BAABLgAECn8XAAIhAAYJHSRcDADiAQAhAAYJHSRcDADiAQAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8rAAQmAAgJqiWfAgBmAgADAAgJjyB+LQC8AgAmAAYJ0iKfAgBmAgAlAAQJcx8DBQBTAQABLgAFFAMJCAAVACwbAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAABLgAECn8UAAIXAAkJCguiFwB0AQAXAAkJCguiFwB0AQAAAA==.Smugxl:BAAALgAFFAMJAwAAAA==.',
So='Sonicberger:BAAALgADCgQJBAABLgAECgkJJwARAMAbAA==.Sonicbergger:BAAALgAECgYJCAABLgAECgkJJwARAMAbAA==.Sonicpoe:BAAALgADCgkJDAABLgAECgkJJwARAMAbAA==.Sonícberger:BAABLgAECn8nAAMRAAkJwBu3IwBUAgARAAkJwBu3IwBUAgASAAQJTw/LLgC4AAAAAA==.Soulcaliber:BAAALgAECgEJAQAAAA==.',
Sp='Spoontangle:BAAALgAECgEJAQAAAA==.',
St='Stain:BAAALgAECgUJCQAAAA==.Stealth:BAAALgAECggJDgABLgAFFAIJAwAGAAAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stillheart:BAAALgAECgkJAQAAAA==.Stith:BAAALgADCgYJCAAAAA==.Stkinbck:BAABLgAECn8tAAIgAAgJyA5wHQB/AQAgAAgJyA5wHQB/AQAAAA==.Stonehenge:BAACLgAFFH8LAAIWAAQJ7hm+HwAxAQAWAAQJ7hm+HwAxAQAuAAQKfyAAAhYACQmkIbkLANYCABYACQmkIbkLANYCAAAA.Stonepalm:BAAALgADCggJGQAAAA==.Stratan:BAAALgAECgUJDAAAAA==.',
Su='Subbzero:BAAALgADCgMJAwAAAA==.Suffer:BAACLgAFFH8IAAMVAAMJLBuEBwCxAAAPAAMJExkUVgDtAAAVAAIJzRuEBwCxAAAuAAQKfxkABA8ACAmsI1UPALoCAA8ACAmQI1UPALoCABUAAgmHJIghAG0AAA4AAgn0GJFjAEcAAAAA.Sukuna:BAAALgADCgIJAgAAAA==.Sundermere:BAAALgAECgEJAQAAAA==.Sunlight:BAAALgADCgMJBAAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8bAAICAAgJkCDTIwCZAgACAAgJkCDTIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8aAAQcAAYJFxEDEgAMAQAcAAQJtg4DEgAMAQAdAAUJJwxKEAD+AAAQAAIJ0wBYSAAlAAAuAAQKfzgAAx0ACQmoGxMPACsCABwACAlmG3kTAFUCAB0ACQmDGRMPACsCAAAA.',
Sy='Sylvia:BAAALgAECgUJCQAAAA==.Symphania:BAAALgAECgYJCwAAAA==.',
['Sä']='Sätansangel:BAAALgAECgEJAQAAAA==.',
Ta='Tabbz:BAABLgAECn8rAAMeAAkJfxmtFAAYAgAeAAkJfxmtFAAYAgAWAAEJBQerpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgAECgEJBQAAAA==.Tallyhochick:BAABLgAECn8vAAITAAkJXAzzPADBAQATAAkJXAzzPADBAQAAAA==.Taman:BAABLgAECn8hAAMWAAcJbRt/HwAmAgAWAAcJbRt/HwAmAgAeAAcJOBamKADPAQAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telarri:BAAALgAECgcJBwAAAA==.Telean:BAAALgAECgQJBAAAAA==.Telkon:BAAALgAECgQJBAAAAA==.Tellesto:BAABLgAECn8wAAMnAAkJpBztDgAiAgAnAAkJqxrtDgAiAgATAAMJNRcSuACUAAAAAA==.Tetabitanam:BAAALgAECgMJAwABLgAECgkJLAANACAOAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgAECgEJAQAAAA==.Thebigonion:BAAALgAECgQJBQAAAA==.',
Ti='Tibberino:BAAALgAECgcJBwAAAA==.Tinydeath:BAAALgAECgcJBwABLgAECgkJKwATADMhAA==.Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8qAAMdAAkJJRsAEwD8AQAdAAkJNBoAEwD8AQAcAAUJghpJIQB8AQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECgkJKwATADMhAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8rAAMTAAkJMyEFDwDDAgATAAkJECAFDwDDAgAnAAQJtxDBMgDxAAAAAA==.',
To='Toko:BAACLgAFFH8bAAITAAYJJSIsAgB9AQATAAYJJSIsAgB9AQAuAAQKfykAAxMACQkjIuIIAAUDABMACQkjIuIIAAUDAB8AAQmjChKMAC8AAAAA.Tomblord:BAABLgAECn8vAAMjAAkJlhrGBQATAgAjAAkJlhrGBQATAgASAAMJGAqPQABLAAAAAA==.Toogga:BAAALgAECgQJBAAAAA==.Tourma:BAAALgAECgEJAQAAAA==.',
Tr='Trapattack:BAAALgAECgQJBAAAAA==.Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECgUJBQAGAAAAAA==.Truepatriot:BAACLgAFFH8JAAIEAAMJbxkkJADRAAAEAAMJbxkkJADRAAAuAAQKfycAAwQACAmoExMyALcBAAQACAmoExMyALcBABkABQnpErciAM4AAAAA.Truexlord:BAABLgAECn8WAAIRAAcJewzYigApAQARAAcJewzYigApAQAAAA==.Truthes:BAAALgAFFAIJAwAAAA==.Truthez:BAAALgADCgMJBgABLgAFFAIJAwAGAAAAAA==.Truths:BAAALgAECgMJBgABLgAFFAIJAwAGAAAAAA==.Truthsx:BAABLgAECn8kAAMVAAgJGiAIBQAMAgAVAAgJph8IBQAMAgAPAAUJchpKdQA5AQABLgAFFAIJAwAGAAAAAA==.Truthz:BAAALgADCgYJBgABLgAFFAIJAwAGAAAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgQJBAAAAA==.Tygerkillz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAFFAEJAQAAAA==.Tyraell:BAABLgAECn8sAAMEAAkJkR0ZCwC4AgAEAAkJkR0ZCwC4AgACAAQJnwdM7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAABLgAECn8bAAISAAkJRB9dBQDrAgASAAkJRB9dBQDrAgABLgAFFAYJGwATACUiAA==.',
Ud='Udor:BAABLgAECn8aAAITAAgJLgzoVQBzAQATAAgJLgzoVQBzAQAAAA==.',
Um='Umbrae:BAABLgAECn80AAMiAAkJdBwfEgAoAgAiAAgJoRsfEgAoAgAUAAEJ4wdKaQA8AAAAAA==.',
Up='Upies:BAABLgAECn8VAAILAAgJ6gL4TQDKAAALAAgJ6gL4TQDKAAAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAAALgAECgYJEgAAAA==.',
Va='Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgQJCgAAAA==.Vanleiden:BAAALgAECgQJBwAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAACLgAFFH8FAAIPAAMJjwhSbgC2AAAPAAMJjwhSbgC2AAAuAAQKfyMAAw8ACQnGGvEYAHUCAA8ACQnGGvEYAHUCAA4AAQn0HhApAFoAAAAA.',
Ve='Veera:BAABLgAECn83AAIeAAkJ6xVYFQARAgAeAAkJ6xVYFQARAgAAAA==.Velkas:BAAALgAECgEJAQAAAA==.Vendyr:BAABLgAECn8ZAAQVAAgJoyHxBwDOAQAPAAcJQx41LQBZAgAVAAYJYhjxBwDOAQAOAAIJ8AscYABPAAAAAA==.Veyra:BAAALgAECgUJBQAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQABLgAECgQJBAAGAAAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voidvoid:BAAALgADCgEJAQABLgAECgkJMgARAKseAA==.Voodruid:BAAALgADCggJCgAAAA==.Vorgol:BAABLgAECn8qAAIXAAkJbRmECgAZAgAXAAkJbRmECgAZAgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8nAAICAAcJ0hXiZAC3AQACAAcJ0hXiZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8OAAICAAQJlA2+NQAiAQACAAQJlA2+NQAiAQAuAAQKfxwAAgIACAmzHa0jAJoCAAIACAmzHa0jAJoCAAAA.',
We='Wellby:BAAALgAECgQJBAAAAA==.Westerin:BAABLgAECn8nAAIOAAkJBhrvAgBQAgAOAAkJBhrvAgBQAgAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wildwest:BAAALgADCgcJBwAAAA==.Wimateeka:BAABLgAECn8dAAQZAAcJzh2QDwDMAQAZAAcJzh2QDwDMAQAEAAUJxRIPYQD4AAACAAQJlw2Y3QDRAAAAAA==.Wimatreeka:BAAALgAECggJCgAAAA==.Wimaugmenta:BAAALgAECgYJBgABLgAECgcJHQAZAM4dAA==.Windfury:BAAALgAECgYJEQABLgAFFAMJCAAVACwbAA==.Windigo:BAAALgAECgYJEwAAAA==.Winginit:BAABLgAECn8WAAMLAAkJUBkpDAB7AgALAAkJUBkpDAB7AgAJAAcJTAmjHgDcAAABLgAFFAYJFgAaAIoVAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgAECgYJCAAAAA==.Worthyreaper:BAAALgAECgEJAQAAAA==.',
Wr='Wrastelas:BAAALgAECgQJBAAAAA==.',
Wu='Wurkim:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.',
Wy='Wylder:BAAALgAECgQJBAABLgAFFAUJFAARALEhAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAQAAAA==.',
Ya='Yachak:BAAALgADCggJDwABLgAECgkJOAACALcUAA==.',
Ye='Yespaladin:BAAALgAFFAEJAQABLgAFFAQJEQAUALklAA==.',
Yi='Yiddosh:BAAALgAECgMJDAAAAA==.',
Yo='Yogí:BAACLgAFFH8QAAIWAAYJbhztBgAGAgAWAAYJbhztBgAGAgAuAAQKfx0AAxYACAk6I94FABQDABYACAk6I94FABQDACQABAkJDKMgAKQAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgkJDQAAAA==.',
Yu='Yumsumwum:BAABLgAFFH8NAAMQAAQJUCK+EACRAQAQAAQJUCK+EACRAQAcAAMJdBvTFQDuAAAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAABLgAECn8hAAIYAAgJkBA8FgBsAQAYAAgJkBA8FgBsAQAAAA==.Zanalia:BAAALgAECgQJCAABLgAECgUJBQAGAAAAAA==.Zarelasong:BAAALgADCgUJBQAAAA==.',
Ze='Zeffie:BAAALgAECgQJBwAAAA==.Zelxari:BAABLgAECn8cAAIPAAgJcwqQZABfAQAPAAgJcwqQZABfAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zensho:BAAALgAECgYJCQAAAA==.',
Zi='Zipsion:BAABLgAECn8dAAITAAkJ/iAUGwBaAgATAAkJ/iAUGwBaAgAAAA==.Zithen:BAACLgAFFH8IAAMLAAMJEAscNQC/AAALAAMJEAscNQC/AAAJAAEJ0QEAJgA4AAAuAAQKfxoAAgsACQmwF4ojAKEBAAsACQmwF4ojAKEBAAAA.Zivver:BAABLgAECn8rAAIYAAkJYSKIAwDdAgAYAAkJYSKIAwDdAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECgQJCAAAAA==.',
['År']='Årikard:BAABLgAECn8aAAIEAAgJUR+wFABCAgAEAAgJUR+wFABCAgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAAALgAECgYJDgAAAA==.',
['Üt']='Üther:BAABLgAECn8tAAMCAAkJKiDJGwCAAgACAAkJHCDJGwCAAgAZAAIJKBxYKQChAAAAAA==.',
['ßu']='ßubbleøseven:BAAALgAFFAIJBAAAAA==.',
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
