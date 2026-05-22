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

local lookup = {'Monk-Brewmaster','Priest-Discipline','Paladin-Retribution','Shaman-Restoration','Mage-Frost','Druid-Feral','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-BeastMastery','Warlock-Demonology','Shaman-Enhancement','Shaman-Elemental','Hunter-Survival','Warrior-Protection','Paladin-Holy','Druid-Guardian','Druid-Restoration','Priest-Shadow','DeathKnight-Unholy','Warlock-Destruction','Unknown-Unknown','Hunter-Marksmanship','Monk-Windwalker','Druid-Balance','Paladin-Protection','Warrior-Fury','Evoker-Devastation','Monk-Mistweaver','Evoker-Preservation','Warrior-Arms','DeathKnight-Frost','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','DeathKnight-Blood','Priest-Holy','Mage-Arcane','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aalst:BAABLgAECn8WAAIBAAYJzQkiOgDXAAABAAYJzQkiOgDXAAAAAA==.',
Ac='Achillesheal:BAABLgAECn8ZAAICAAYJoR8SFAAMAgACAAYJoR8SFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acshec:BAAALgADCgYJDgABLgAECgcJIgADAEAbAA==.Acuna:BAAALgAECgcJCQAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn8tAAIBAAgJug9QIgBYAQABAAgJug9QIgBYAQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.Aessan:BAAALgADCgkJDwABLgAECgcJHgAEAOANAA==.',
Ag='Aggrenox:BAABLgAECn8bAAIDAAYJ5Qn8owDkAAADAAYJ5Qn8owDkAAAAAA==.',
Ai='Aisathya:BAABLgAECn8ZAAIFAAgJPCNhEgC2AgAFAAgJPCNhEgC2AgAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJBgAAAA==.Albina:BAAALgAECgIJBAAAAA==.Aldelvir:BAAALgAECgcJDQABLgAECgcJLwAGAHoXAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAAALgAECggJEgAAAA==.Alzhimers:BAAALgAECgUJCQAAAA==.',
Am='Amberscale:BAACLgAFFH8FAAIHAAMJ3hKZJwDiAAAHAAMJ3hKZJwDiAAAuAAQKfyQAAgcACAkIHZUPACUCAAcACAkIHZUPACUCAAAA.Amyrrin:BAABLgAECn8UAAIDAAgJlRFjXwBoAQADAAgJlRFjXwBoAQAAAA==.',
An='Ancientiur:BAABLgAECn8ZAAMIAAkJvxrGMgCwAQAIAAkJnhjGMgCwAQAJAAMJ+RI8GwBvAAAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAAALgAECgYJEQAAAA==.Angrulus:BAABLgAECn8qAAIKAAkJ/xdHHQAoAgAKAAkJ/xdHHQAoAgAAAA==.Animal:BAAALgAECgIJAgAAAA==.Animlshiftr:BAABLgAECn8jAAIGAAgJrQ2vDwBWAQAGAAgJrQ2vDwBWAQAAAA==.',
Ap='Apollo:BAABLgAECn8bAAILAAYJYAmwhgDuAAALAAYJYAmwhgDuAAAAAA==.',
Ar='Aradunn:BAACLgAFFH8PAAIEAAQJsST2CQCvAQAEAAQJsST2CQCvAQAuAAQKfyMABAQACAkYI/sGAAQDAAQACAkYI/sGAAQDAAwAAgmeI74fAGcAAA0AAwlYHgAAAAAAAAAA.Araedis:BAABLgAECn8oAAIOAAgJ2gxdFwCdAQAOAAgJ2gxdFwCdAQAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwAPAP0JAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgYJDAAAAA==.',
As='Ashvehtta:BAAALgAECggJDwAAAA==.Assaelysia:BAAALgAECgIJAgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgAECgEJAQAAAA==.Astralon:BAAALgAECgIJAwAAAA==.',
At='Atharion:BAABLgAECn8iAAMQAAgJpB7OCQCoAgAQAAgJpB7OCQCoAgADAAMJZAwmDAF/AAAAAA==.Atheus:BAAALgADCgEJAQAAAA==.',
Av='Avanda:BAAALgAECgEJBAAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAABLgAECn8bAAIMAAgJqhQ1CgCvAQAMAAgJqhQ1CgCvAQAAAA==.',
Az='Azaléa:BAAALgADCgcJBwAAAA==.Azrathalos:BAAALgAECgcJEwAAAA==.Azémstraza:BAAALgAECgYJBgAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAABLgAECn8eAAIKAAYJ9htZLwD0AQAKAAYJ9htZLwD0AQAAAA==.Balinor:BAABLgAECn8UAAIQAAYJOw9vNwAeAQAQAAYJOw9vNwAeAQABLgAECggJLQAPAIUdAA==.',
Be='Bearett:BAABLgAECn8nAAIRAAgJQCO5AgDEAgARAAgJQCO5AgDEAgAAAA==.Belylight:BAAALgAECgkJBgAAAA==.Belymoon:BAAALgAECgkJCQAAAA==.Bernd:BAABLgAECn8iAAIRAAgJOg3MFwAWAQARAAgJOg3MFwAWAQAAAA==.Beörn:BAABLgAECn8nAAISAAgJZCLBBgAUAwASAAgJZCLBBgAUAwAAAA==.',
Bl='Blackgrinn:BAABLgAECn8eAAMCAAcJLRBsIABsAQACAAcJLRBsIABsAQATAAcJRwaOMgD8AAAAAA==.Blackkgrin:BAAALgADCgQJBAAAAA==.Blasphemous:BAABLgAECn8dAAIUAAcJgBSSXQBmAQAUAAcJgBSSXQBmAQAAAA==.Blasé:BAABLgAECn8tAAMLAAgJESAeFQBuAgALAAgJESAeFQBuAgAVAAEJAACjXABZAAABLgAFFAEJAQAWAAAAAA==.Blazéoné:BAAALgAECgMJAwAAAA==.Blessin:BAAALgAECgcJCQAAAA==.',
Bo='Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMXAAIJ7xKHHQCgAAAXAAIJ7xKHHQCgAAAKAAIJNQidVACIAAAuAAQKfywABBcACAmYIZcNANgCABcACAkUHpcNANgCAA4ABwnWHYwSAM4BAAoAAgl9HtecAJkAAAAA.Bobsmonk:BAAALgADCgEJAQAAAA==.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAIUAAcJdR3VSAAZAgAUAAcJdR3VSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwAUAHUdAA==.',
Br='Brakevilt:BAAALgADCgQJBAAAAA==.Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Bruche:BAABLgAECn8oAAIUAAgJ8BykKQATAgAUAAgJ8BykKQATAgAAAA==.Brujaah:BAAALgAECgYJBgABLgAECgkJOgAWAAAAAQ==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Bubagumps:BAAALgAECgEJAQAAAA==.',
Bw='Bwca:BAABLgAFFH8GAAIKAAMJ9A5EOADlAAAKAAMJ9A5EOADlAAABLgAFFAMJCgAEABUGAA==.',
Ca='Caine:BAABLgAECn8tAAIPAAgJhR0+DABIAgAPAAgJhR0+DABIAgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgQJBAABLgAECgcJHgAEAOANAA==.Casey:BAAALgAECgUJEAAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAABLgAECn8eAAIEAAcJ4A3WQQBEAQAEAAcJ4A3WQQBEAQAAAA==.',
Ce='Cellina:BAABLgAECn8WAAIYAAYJaRB+LQAFAQAYAAYJaRB+LQAFAQAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgAECgYJCgABLgAECggJGwAFAGkRAA==.',
Ch='Chaniqua:BAAALgADCgQJBQAAAA==.Chiman:BAAALgAECgUJDAABLgAECgYJDgAWAAAAAA==.Chronophage:BAAALgAECgUJBQAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Ci='Ciders:BAAALgAECgEJAQABLgAECgYJFQAOAFYOAA==.',
Cl='Clasastrasza:BAAALgAECgQJBAAAAA==.Classá:BAACLgAFFH8KAAMSAAMJYhzzIAADAQASAAMJYhzzIAADAQAZAAMJzhW+HADlAAAuAAQKfzUAAxkACAmyID4OALkCABkABwluJD4OALkCABIABgnDHclGAIcBAAAA.Clawz:BAAALgAFFAIJAgABLgAFFAMJBQADANwXAA==.',
Co='Codedd:BAABLgAECn8ZAAISAAcJeRCUPgBPAQASAAcJeRCUPgBPAQAAAA==.Commit:BAAALgAECggJDgAAAA==.Comradeprime:BAAALgAECgQJCQAAAA==.Corlys:BAABLgAECn8hAAIDAAgJoB4JIABEAgADAAgJoB4JIABEAgAAAA==.Covi:BAAALgADCgYJBQAAAA==.',
Cr='Crispìn:BAAALgAECgUJCgAAAA==.Crossbones:BAAALgAECgIJAgAAAA==.Crue:BAAALgAECgMJBQAAAA==.',
Cu='Curthar:BAACLgAFFH8FAAIDAAMJ3BdzNwAAAQADAAMJ3BdzNwAAAQAuAAQKfxoAAxoACQnLIW8EAG8CABoABwkvJG8EAG8CAAMABgmgHr1PAI8BAAAA.',
Cy='Cyndee:BAABLgAECn8sAAIbAAkJZBM9GQDVAQAbAAkJZBM9GQDVAQAAAA==.Cynnafrost:BAAALgAECgEJAQAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn8tAAIXAAkJZx/sAQC2AgAXAAkJZx/sAQC2AgAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgAECgYJBgABLgAECgYJHgAKAPYbAA==.Dankmonk:BAABLgAECn8aAAIBAAcJuw96KQArAQABAAcJuw96KQArAQAAAA==.Darcnis:BAAALgADCgkJGwAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn8rAAIIAAgJewhNawD6AAAIAAgJewhNawD6AAAAAA==.Darklasminth:BAAALgAECgQJCAAAAA==.Darthwang:BAABLgAECn8fAAILAAYJ6BjsWgC3AQALAAYJ6BjsWgC3AQAAAA==.Darthwing:BAAALgAECgMJAwABLgAECgYJHwALAOgYAA==.Dartos:BAABLgAECn8xAAIUAAkJQCQJBQAuAwAUAAkJQCQJBQAuAwAAAA==.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAYJFgAFAP8YAA==.Deathsend:BAAALgAECggJCAAAAA==.Debluddk:BAAALgAECgcJEgABLgAECggJJAAcAGscAA==.Deep:BAAALgAECgEJAQABLgAECggJIwAdACghAA==.Deepfister:BAABLgAECn8jAAIdAAgJKCHGBwDDAgAdAAgJKCHGBwDDAgAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECggJIwAdACghAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgcJCgAAAA==.Diluvium:BAABLgAECn8hAAIDAAgJ9hIOTQCXAQADAAgJ9hIOTQCXAQAAAA==.Discodank:BAAALgAECgMJBAAAAA==.',
Dj='Djpleasant:BAACLgAFFH8JAAIFAAMJqw/hVwD0AAAFAAMJqw/hVwD0AAAuAAQKfyoAAgUACQl8HCodAHICAAUACQl8HCodAHICAAAA.',
Dk='Dktelmtwo:BAAALgADCgkJEQAAAA==.',
Do='Doneisha:BAAALgAECgQJCQAAAA==.Dontcare:BAAALgAFFAEJAQAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Drakamar:BAABLgAECn8lAAQcAAgJZwK3EgCVAAAcAAgJZwK3EgCVAAAeAAYJMALjIwCAAAAHAAEJLgCrbAAMAAAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAABLgAECn8bAAIZAAgJ/h1lDABCAgAZAAgJ/h1lDABCAgAAAA==.',
Du='Dunzledorf:BAAALgAECgcJBwAAAA==.',
Dy='Dynammes:BAABLgAECn8bAAIFAAYJMBkajAC6AQAFAAYJMBkajAC6AQABLgAECggJLQAbANIhAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgAECgMJAwAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8OAAIBAAQJcBqFEgA8AQABAAQJcBqFEgA8AQAuAAQKfxgAAwEACAmlHJsVAMEBAAEABQm9H5sVAMEBABgABwkpF+kjALcBAAAA.',
Eg='Egraw:BAAALgAECgQJBAAAAA==.',
El='Elementals:BAAALgAECgkJDgAAAA==.Elixera:BAAALgAECgEJAQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.Elémental:BAAALgADCggJDQAAAA==.',
Em='Emilwhaury:BAAALgADCgIJAgAAAA==.',
Ep='Epia:BAABLgAECn8dAAIYAAcJ8wtiKQAdAQAYAAcJ8wtiKQAdAQAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Essaila:BAABLgAECn8hAAIGAAgJ1wpEEABMAQAGAAgJ1wpEEABMAQAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8cAAMbAAgJTiTxBgCyAgAbAAgJTiTxBgCyAgAfAAIJnxfkOABMAAAAAA==.',
Ev='Evocati:BAABLgAECn8XAAMUAAYJ6hc+dgAtAQAUAAYJGRc+dgAtAQAgAAUJ9BUAAAAAAAAAAA==.Evoka:BAABLgAECn8kAAMcAAgJaxzyDAAMAgAcAAcJVh/yDAAMAgAHAAYJXxjbJQBbAQAAAA==.',
Ex='Excision:BAABLgAECn8eAAMHAAgJWA7ZMgAQAQAcAAcJcw2yHgA5AQAHAAcJ1wvZMgAQAQAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Ez='Ezindrozath:BAABLgAECn8iAAQLAAgJDxb6OAC2AQALAAgJUhX6OAC2AQAhAAQJcBYlEQAbAQAVAAEJ7wVOeQAqAAAAAA==.',
Fa='Fahbio:BAABLgAECn8XAAIaAAYJ8QFLMQCLAAAaAAYJ8QFLMQCLAAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAABLgAECn8mAAMLAAcJGhCEWgBQAQALAAcJGhCEWgBQAQAhAAEJaQgDJgA0AAAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgAECgIJAgABLgAECgcJGgAiAKMTAA==.Fivevolts:BAABLgAECn8eAAIjAAgJUiA+AgB7AgAjAAgJUiA+AgB7AgAAAA==.',
Fl='Flailuid:BAAALgAECgQJDAAAAA==.Flimfam:BAAALgAECgEJAQAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgEJBQAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgYJBwAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAACLgAFFH8HAAIYAAMJDhcGEwDmAAAYAAMJDhcGEwDmAAAuAAQKfzQAAhgACAm5ImAGAKQCABgACAm5ImAGAKQCAAAA.Fries:BAEALgAECgEJAQABLgAFFAQJBwALAKYPAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8nAAIHAAgJ8w08KgA+AQAHAAgJ8w08KgA+AQAAAA==.',
Fu='Fudd:BAABLgAECn8bAAIKAAYJRBzROQDHAQAKAAYJRBzROQDHAQAAAA==.Fupa:BAABLgAECn8VAAIKAAYJ3gp1bgAHAQAKAAYJ3gp1bgAHAQAAAA==.',
Ga='Gaiaslieg:BAAALgADCgMJAwAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAABLgAECn8cAAIGAAcJuh+ZBwD+AQAGAAcJuh+ZBwD+AQAAAA==.',
Ge='Genius:BAABLgAECn8bAAIfAAcJTxvXDgClAQAfAAcJTxvXDgClAQAAAA==.Gennosuke:BAAALgADCgcJBQAAAA==.',
Gh='Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8VAAIDAAgJ0BjlfgB8AQADAAgJ0BjlfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAAALgAECgMJAwAAAA==.Gnomad:BAABLgAECn8aAAIFAAcJGgOrtQDbAAAFAAcJGgOrtQDbAAAAAA==.',
Go='Gouge:BAAALgAECgkJOgAAAQ==.',
Gr='Griffynshu:BAABLgAECn8dAAISAAgJnBzvEgBwAgASAAgJnBzvEgBwAgAAAA==.Griz:BAAALgAECgYJBgAAAA==.Grizzlyburr:BAAALgAECgcJBwABLgAECgkJHgABAMMUAA==.Grunewald:BAABLgAECn87AAIKAAgJRAh8WwA2AQAKAAgJRAh8WwA2AQAAAA==.',
Gu='Guinn:BAAALgADCgIJAgABLgAECggJJwAHAPMNAA==.Gula:BAABLgAECn8hAAMhAAkJPRU/CQCxAQALAAkJJhRKOQC1AQAhAAYJHRc/CQCxAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAACLgAFFH8NAAICAAQJAx6wEQBoAQACAAQJAx6wEQBoAQAuAAQKfxgAAxMABwm4E5QgANQBABMABwm4E5QgANQBAAIABAnJIhYwAB8BAAAA.Hando:BAAALgAECgYJBgAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heavyshlump:BAABLgAECn8eAAIBAAkJwxSDDQAhAgABAAkJwxSDDQAhAgAAAA==.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIiAAgJARvUEwB3AgAiAAgJARvUEwB3AgAAAA==.Heimdall:BAABLgAECn8UAAIQAAgJShotEwAtAgAQAAgJShotEwAtAgAAAA==.Hellavva:BAAALgAECgMJAwAAAA==.Hench:BAAALgADCgIJAgAAAA==.Henchling:BAABLgAECn81AAMEAAkJHCApCQDkAgAEAAkJHCApCQDkAgANAAkJaBLoFwDRAQAAAA==.Henchragon:BAAALgADCgUJBQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIFAAcJzxv2TACyAQAFAAcJzxv2TACyAQABLgAFFAMJCAAHAOYUAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAiAAEbAA==.Holexios:BAAALgAECgQJBwABLgAECgYJDgAWAAAAAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAQAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAABLgAECn8VAAIKAAYJVQw7bAAMAQAKAAYJVQw7bAAMAQAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgAECgIJAgAAAA==.',
Ic='Icieblade:BAAALgAECgkJEQAAAA==.Icyscorcher:BAABLgAECn8bAAMFAAgJaREkVACeAQAFAAgJaREkVACeAQAkAAMJpwOyCwB3AAAAAA==.',
Ik='Ikairi:BAAALgAECgEJAQAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.',
Im='Immeira:BAABLgAECn8XAAIEAAYJIwr7VAD4AAAEAAYJIwr7VAD4AAAAAA==.',
In='Intense:BAAALgAECgcJAwAAAA==.',
Ja='Jackheals:BAACLgAFFH8JAAISAAMJABM1JwDcAAASAAMJABM1JwDcAAAuAAQKfyYAAxIACAk/HgcbACUCABIACAk/HgcbACUCABkAAQnZAdqPABsAAAAA.Jaehaerys:BAAALgAECgQJBAABLgAECggJIQADAKAeAA==.Jaldon:BAAALgAECgQJBAABLgAECgkJHgABAMMUAA==.',
Jb='Jblackly:BAAALgAECgYJCAAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinphoenix:BAABLgAECn8gAAMKAAkJeR5nCgDCAgAKAAkJeR5nCgDCAgAXAAQJkAeMXwDDAAAAAA==.Jitb:BAAALgADCgYJBgABLgAFFAUJCwAdAOELAA==.',
Jo='Jobin:BAACLgAFFH8KAAIUAAMJQxLvZQDpAAAUAAMJQxLvZQDpAAAuAAQKfxkAAhQACAn1G0twAKgBABQACAn1G0twAKgBAAAA.Journei:BAAALgAECgYJDQAAAA==.',
Ju='Judging:BAABLgAECn8iAAMQAAgJ5RGOKAB6AQAQAAgJ5RGOKAB6AQADAAIJHSVIsADQAAAAAA==.Junkhead:BAAALgAECgEJAQAAAA==.',
Ka='Kaethe:BAAALgAECgYJBgAAAA==.Kaiduo:BAAALgADCgEJAQAAAA==.Kaitos:BAAALgAFFAIJAgABLgAFFAMJBQADANwXAA==.Kalmas:BAABLgAFFH8JAAIZAAMJmwdsIQDAAAAZAAMJmwdsIQDAAAAAAA==.',
Ke='Kegz:BAAALgADCgcJBwABLgAECggJIwACAJkeAA==.Kelendrian:BAAALgADCgkJCgAAAA==.Kellayna:BAAALgAECgcJDwAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Keylö:BAAALgADCgUJBwAAAA==.Kezix:BAABLgAECn8eAAILAAkJkg7ROAC3AQALAAkJkg7ROAC3AQAAAA==.',
Kh='Kharigosa:BAAALgAECgEJAQABLgAECgYJDgAWAAAAAA==.',
Ki='Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8mAAQHAAgJfhGoIwChAQAHAAgJvA+oIwChAQAcAAIJ7gtWGwA7AAAeAAEJwQF4TgAiAAAAAA==.',
Kl='Klerik:BAACLgAFFH8SAAILAAUJYBQPLwAxAQALAAUJYBQPLwAxAQAuAAQKfykABAsACQkSH2wRAIoCAAsACQmqHWwRAIoCABUAAgkpEmxMAIgAACEAAQlxJO4eAFQAAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8WAAIlAAUJbCBrCgBNAQAlAAUJbCBrCgBNAQAuAAQKfzcAAiUACQlQI74CAO0CACUACQlQI74CAO0CAAAA.Kore:BAABLgAECn8aAAISAAYJZBbqOgBhAQASAAYJZBbqOgBhAQAAAA==.Korrag:BAAALgAECgQJBQAAAA==.Kozarke:BAABLgAECn8iAAIcAAgJXhRQBQDGAQAcAAgJXhRQBQDGAQAAAA==.',
Kp='Kpop:BAABLgAECn8XAAIJAAkJfxktBwAWAgAJAAkJfxktBwAWAgABLgAECgkJHgABAMMUAA==.',
Kr='Krissia:BAABLgAECn8hAAIUAAkJgxj2NADkAQAUAAkJgxj2NADkAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgAECgQJBAAAAA==.',
['Kí']='Kítsuñe:BAAALgADCggJCwAAAA==.',
['Kî']='Kîn:BAABLgAECn8aAAIIAAYJ2he6VgAxAQAIAAYJ2he6VgAxAQAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8rAAMmAAgJSRJoHgCIAQAmAAgJSRJoHgCIAQATAAEJFARBbAAjAAAAAA==.Lalipop:BAABLgAECn8gAAImAAYJvhjfHQCNAQAmAAYJvhjfHQCNAQAAAA==.Landroval:BAABLgAECn8cAAIHAAcJkhokGwCsAQAHAAcJkhokGwCsAQAAAA==.Lauma:BAACLgAFFH8KAAIEAAMJFQaFNQCtAAAEAAMJFQaFNQCtAAAuAAQKfxUAAgQABwmwEqgyAIsBAAQABwmwEqgyAIsBAAAA.Lawson:BAABLgAECn8oAAIUAAgJfxq5OgDQAQAUAAgJfxq5OgDQAQAAAA==.',
Le='Lelora:BAAALgAECgUJCQAAAA==.Lenthaden:BAABLgAECn8tAAMLAAgJRRjSNgC+AQALAAgJFhXSNgC+AQAVAAYJqxNeJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgADCgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lilflame:BAAALgAECgEJAQAAAA==.Lio:BAAALgAECgYJDgAAAA==.Lissetteliz:BAAALgAECgQJBQAAAA==.Livdangerous:BAAALgADCgUJBQAAAA==.',
Lo='Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJDQAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.Lunchdk:BAACLgAFFH8NAAMlAAMJOhebDgCAAAAUAAIJJR7cegCvAAAlAAIJBwybDgCAAAAuAAQKfygAAxQACQlzH5QMAM8CABQACAlXI5QMAM8CACUACAlzF2gVALwBAAAA.',
Ly='Lyreth:BAABLgAECn8pAAIZAAkJJBB1GQClAQAZAAkJJBB1GQClAQAAAA==.',
Ma='Madax:BAABLgAECn8tAAIbAAgJ0iFuCgB4AgAbAAgJ0iFuCgB4AgAAAA==.Mageymutt:BAACLgAFFH8WAAIFAAYJ/xhbDAC7AQAFAAYJ/xhbDAC7AQAuAAQKfyUAAwUACAmNIKElANwCAAUACAmNIKElANwCACcAAwkmCx8UAIQAAAAA.Maggidabeast:BAABLgAECn8ZAAIFAAgJ9gOAmwAJAQAFAAgJ9gOAmwAJAQAAAA==.Magnion:BAAALgAECgEJAQAAAA==.Maison:BAAALgAECgQJBQAAAA==.Malase:BAAALgADCgUJAwAAAA==.Maloch:BAAALgADCgUJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAACLgAFFH8FAAIgAAIJ0wv2DACPAAAgAAIJ0wv2DACPAAAuAAQKfzEAAiAACQmqGjEEABwCACAACQmqGjEEABwCAAAA.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAACLgAFFH8FAAIFAAIJbRXdbQCqAAAFAAIJbRXdbQCqAAAuAAQKfywAAgUACQmnHdkZAIUCAAUACQmnHdkZAIUCAAAA.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minervá:BAAALgADCgMJAwABLgAFFAMJCgASAGIcAA==.Missbehaving:BAABLgAECn8ZAAImAAcJjRTtIwBcAQAmAAcJjRTtIwBcAQAAAA==.',
Mo='Morefire:BAAALgAECgQJCAABLgAECgkJDgAWAAAAAA==.Mosmos:BAAALgADCgkJFQAAAA==.',
Mu='Muddslinger:BAABLgAECn8WAAIbAAgJEgubLABRAQAbAAgJEgubLABRAQAAAA==.Mumra:BAABLgAECn8kAAQmAAgJSwOxMgDzAAAmAAgJSwOxMgDzAAACAAYJdgFaPwC0AAATAAEJAAA6cgAAAAAAAA==.',
My='Mystblade:BAAALgAECgIJAgAAAA==.Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgAECgIJAwAAAA==.Nanaki:BAABLgAECn8iAAIeAAkJKyDzBgDQAgAeAAkJKyDzBgDQAgAAAA==.Nannette:BAAALgAECgYJDgAAAA==.Nappe:BAAALgADCgcJBwABLgAECggJGQADABciAA==.Narag:BAABLgAECn8kAAIKAAgJtxPjPQCTAQAKAAgJtxPjPQCTAQAAAA==.Nazfu:BAAALgAECgEJAQAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Nerfertari:BAAALgAECgEJBAAAAA==.Netanyahoo:BAAALgAECgUJCwAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn8eAAMEAAgJqBuLGQAoAgAEAAgJqBuLGQAoAgANAAIJmAjxZwBSAAAAAA==.',
Ni='Ninex:BAABLgAECn8cAAIQAAgJTR/RGABMAgAQAAgJTR/RGABMAgAAAA==.Ninisina:BAABLgAECn8nAAMEAAcJVh88EwBeAgAEAAcJVh88EwBeAgAMAAEJ7wOHLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Nonaleeta:BAAALgAECgQJBQAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Nowhere:BAAALgAECgUJBQABLgAECgcJGgAiAKMTAA==.Nowon:BAABLgAECn8YAAMoAAYJHRI3IAAOAQAoAAYJHRI3IAAOAQAJAAEJpwhmKgAdAAAAAA==.',
Nu='Nudream:BAABLgAECn8WAAIQAAgJqQNNOQAUAQAQAAgJqQNNOQAUAQAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAABLgAECn8VAAMZAAYJCA8VNwDeAAAZAAYJCA8VNwDeAAAGAAEJDwbNOgAhAAAAAA==.',
Ol='Oldjerry:BAABLgAECn8aAAIiAAcJoxNvGgBpAQAiAAcJoxNvGgBpAQAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Op='Opalyte:BAABLgAECn8aAAImAAYJHA+IMAACAQAmAAYJHA+IMAACAQAAAA==.',
Or='Orichalcum:BAABLgAECn8hAAIdAAgJaBwsDQBjAgAdAAgJaBwsDQBjAgAAAA==.Orphiee:BAAALgAECgMJBQAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgEJAQAAAA==.',
Ou='Outis:BAAALgAFFAIJBAAAAQ==.',
Pa='Pakoros:BAABLgAECn8tAAMEAAkJKBi2EAB4AgAEAAkJKBi2EAB4AgANAAQJBwp7agCZAAAAAA==.Palibuddy:BAAALgAECgMJAwAAAA==.Pallyfreak:BAAALgAECgMJAwAAAA==.',
Pe='Peachy:BAAALgADCgEJAgABLgAECggJIgAEAC8VAA==.Penderin:BAAALgADCgYJBgABLgAECgcJLwAGAHoXAA==.Pensham:BAAALgAECgEJAgABLgAECgcJLwAGAHoXAA==.Perlindree:BAABLgAECn8lAAIKAAYJnAgMagAqAQAKAAYJnAgMagAqAQAAAA==.',
Pg='Pgorlelgy:BAABLgAECn8nAAIKAAkJqRVcJwDyAQAKAAkJqRVcJwDyAQAAAA==.',
Ph='Phira:BAAALgADCgEJAQAAAA==.Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn8eAAIDAAcJ8hD/awBLAQADAAcJ8hD/awBLAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgAWAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAABLgAECn8UAAILAAcJ6QEqtQCUAAALAAcJ6QEqtQCUAAAAAA==.Poppers:BAAALgADCgYJBgAAAA==.',
Pr='Preacharond:BAACLgAFFH8JAAITAAMJoQ5vFwDqAAATAAMJoQ5vFwDqAAAuAAQKfz8AAhMACQmBH50EANkCABMACQmBH50EANkCAAAA.Promir:BAAALgAECgcJDQAAAA==.',
Pu='Purdie:BAAALgAECgQJBAABLgAECgcJHgAEAOANAA==.',
Qe='Qeesa:BAAALgAECgEJAQAAAA==.',
Qi='Qiryana:BAAALgADCgIJAgAAAA==.',
Ra='Raeliene:BAABLgAECn8cAAIDAAgJgxu9KAAWAgADAAgJgxu9KAAWAgAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn8tAAICAAgJtxzbCwBbAgACAAgJtxzbCwBbAgAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Relaxnerdlol:BAAALgAECgEJAgAAAA==.Reldwick:BAAALgADCgYJBwAAAA==.Renew:BAABLgAECn8bAAMmAAgJwB0pCgB6AgAmAAgJwB0pCgB6AgATAAcJOhJ5IgBdAQAAAA==.Renix:BAACLgAFFH8HAAINAAMJVRz5GwDyAAANAAMJVRz5GwDyAAAuAAQKfzAAAw0ACQlgHkkJAIQCAA0ACQlgHkkJAIQCAAwAAQl1CxYtADIAAAAA.Reno:BAAALgAECgMJAwAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgUJBAAAAA==.',
Ri='Ripmyname:BAAALgAECgYJBgAAAA==.Riverah:BAAALgAECgQJCAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAABLgAECn8YAAImAAUJVRUhKgAtAQAmAAUJVRUhKgAtAQAAAA==.',
Ru='Rukaillin:BAAALgAECgYJBgAAAA==.',
Ry='Ryukaii:BAAALgAECgUJBQAAAA==.Ryyah:BAABLgAECn8tAAMQAAgJxxD/IwCaAQAQAAgJxxD/IwCaAQADAAQJLQNe7wBsAAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwAAAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAIJAwAAAA==.',
Sa='Saetyl:BAABLgAECn8aAAIZAAYJKwLDTwB0AAAZAAYJKwLDTwB0AAAAAA==.Saga:BAAALgADCgEJAQAAAA==.Salvynus:BAAALgAECgUJBQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQAWAAAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seanthaniel:BAEALgADCgQJBAABLgAECgYJCgAWAAAAAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQAWAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semii:BAAALgAECgIJAgAAAA==.Serkesul:BAABLgAECn8jAAITAAgJ6iP5BQC5AgATAAgJ6iP5BQC5AgAAAA==.Sevinas:BAABLgAECn8VAAIMAAYJUQ1nFAD3AAAMAAYJUQ1nFAD3AAAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shaftstop:BAAALgADCgkJCQABLgAECgUJBQAWAAAAAA==.Shamallamá:BAAALgADCgkJCgABLgAECggJJQAKABQiAA==.Shamthis:BAAALgAECgkJDQAAAA==.Shamwoww:BAAALgAFFAEJAQABLgAFFAMJCQATAKEOAA==.Shamyou:BAABLgAECn8UAAMEAAkJ1xnQGwA6AgAEAAkJ1xnQGwA6AgANAAYJKRq6JgBeAQAAAA==.Shealie:BAAALgADCgMJAwABLgAECggJJAAiADIZAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAAALgAECgYJEAABLgAECgkJHgABAMMUAA==.Shlumpdragon:BAAALgAECgMJAwABLgAECgkJHgABAMMUAA==.Shokcz:BAAALgAECgEJAgAAAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8TAAIEAAUJRybSAgAyAgAEAAUJRybSAgAyAgAuAAQKfy4AAgQACQkMJkYCAGkDAAQACQkMJkYCAGkDAAAA.',
Si='Silvey:BAABLgAECn8iAAIIAAgJriAyEACBAgAIAAgJriAyEACBAgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAABLgAECn8UAAMUAAgJSxBYbgA+AQAUAAgJSxBYbgA+AQAlAAEJXA2nSwAfAAAAAA==.Skully:BAAALgAECgEJAQAAAA==.Skyylorne:BAAALgAECgMJBQAAAA==.',
Sl='Slipnslide:BAAALgADCgYJBgABLgAECggJLQACALccAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snow:BAAALgAECgYJBgABLgAECgkJIgAeACsgAA==.Snowfawn:BAABLgAECn8YAAIKAAcJJw3YUwBNAQAKAAcJJw3YUwBNAQABLgAFFAEJAQAWAAAAAA==.Snusnurae:BAAALgAECgYJCQAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Somay:BAAALgAECgMJBgAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECgkJIgAeACsgAA==.',
Sp='Spanana:BAABLgAFFH8MAAIUAAQJThK3FQBNAQAUAAQJThK3FQBNAQAAAA==.Specialist:BAAALgAFFAIJAwAAAA==.Spicychopz:BAACLgAFFH8YAAIFAAgJeCMOAQDXAgAFAAgJeCMOAQDXAgAuAAQKfxcAAgUACAnbIRUdAAEDAAUACAnbIRUdAAEDAAAA.Splishsplásh:BAABLgAECn8VAAIEAAYJoB1xIAD1AQAEAAYJoB1xIAD1AQAAAA==.Sprattyboii:BAAALgAECggJEgAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAAALgAECggJDwAAAA==.',
St='Staltis:BAAALgAECgMJBAABLgAECggJJwAHAPMNAA==.Starrling:BAAALgAECgcJCQAAAA==.Starzia:BAABLgAECn8oAAICAAgJeQcQIwBXAQACAAgJeQcQIwBXAQAAAA==.Stupidtree:BAACLgAFFH8HAAISAAMJCBs2IQABAQASAAMJCBs2IQABAQAuAAQKfxwAAhIABwnLI3kOAKMCABIABwnLI3kOAKMCAAAA.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8iAAILAAgJuxkwJQAMAgALAAgJuxkwJQAMAgAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJBQABLgAECgMJBAAWAAAAAA==.Swiftblossom:BAAALgAECgEJAQAAAA==.',
Sy='Sylvanex:BAAALgAECgQJCgAAAA==.',
['Sê']='Sêrënîty:BAAALgADCgEJAQABLgAFFAQJCAADAOQPAA==.',
Ta='Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgUJCgABLgAECgYJDgAWAAAAAA==.Talarus:BAAALgAECggJDwAAAA==.Talurana:BAAALgAECgEJAQAAAA==.Tanadria:BAABLgAECn8aAAIiAAgJ2glHHABXAQAiAAgJ2glHHABXAQAAAA==.Tangerene:BAACLgAFFH8HAAICAAMJbAHgIwCkAAACAAMJbAHgIwCkAAAuAAQKfxoAAwIACAncBQYuAC4BAAIABwmBBgYuAC4BACYABgkTAhteALoAAAAA.Tapioca:BAACLgAFFH8IAAIKAAMJICBhKAAcAQAKAAMJICBhKAAcAQAuAAQKfyIAAgoACAkXIa0MANoCAAoACAkXIa0MANoCAAAA.Tashyr:BAAALgAECgEJAQAAAA==.',
Tc='Tchort:BAAALgAECgQJBAABLgAFFAYJFgAFAP8YAA==.',
Te='Telm:BAABLgAECn8iAAMDAAcJQBuQRgCqAQADAAcJghmQRgCqAQAaAAcJShrGDwBwAQAAAA==.Tentilious:BAAALgADCggJCwAAAA==.',
Th='Thadeusputz:BAAALgAECgEJAQAAAA==.Thaÿne:BAAALgAECgcJEAAAAA==.Thebestpally:BAACLgAFFH8FAAMDAAIJ1AN2ZQCCAAADAAIJKgJ2ZQCCAAAaAAEJzwWnEQAkAAAuAAQKfzUAAxoACAnmG6oGACUCABoACAnZG6oGACUCAAMABQmNDQXlAMQAAAAA.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAABLgAECn8YAAMQAAgJ4R/KEQA7AgAQAAgJ4R/KEQA7AgADAAEJJQ59QgEzAAAAAA==.Tidds:BAABLgAECn8gAAMLAAcJyQnfcgAYAQALAAcJRAjfcgAYAQAhAAIJYgjRHwBQAAAAAA==.',
To='Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8XAAIEAAcJux6OAAClAgAEAAcJux6OAAClAgAuAAQKfyMAAgQACQm1I/ECAFIDAAQACQm1I/ECAFIDAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAACLgAFFH8KAAIHAAQJVgdPIgAEAQAHAAQJVgdPIgAEAQAuAAQKfysAAwcACQkiFd4WAB8CAAcACQkiFd4WAB8CABwAAwkmBKczAHcAAAAA.Triggaman:BAAALgADCgUJBQABLgAECgcJIgADAEAbAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJCAABLgAFFAMJCAAKACAgAA==.',
Uj='Ujio:BAABLgAECn8XAAMQAAYJzBnpIwCaAQAQAAYJzBnpIwCaAQADAAMJpwfG3wCFAAAAAA==.',
Un='Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgIJAwAAAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAFFAEJAQABLgAFFAIJBAAWAAAAAQ==.',
Va='Vaden:BAAALgAECgEJAQABLgAECgYJFQAOAFYOAA==.Vaelthys:BAAALgAECgUJCQABLgAECggJIgALAA8WAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAABLgAECn8gAAMHAAgJYhOBIwBtAQAHAAgJEhOBIwBtAQAcAAIJ2gqzOQBMAAABLgAECggJLQAbANIhAA==.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAFFAMJCQADALgUAA==.Vanaheim:BAAALgAECggJDAAAAA==.Vance:BAAALgAECgYJEQAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Varala:BAAALgAECgMJAwAAAA==.',
Ve='Vel:BAACLgAFFH8UAAMUAAYJIyG8CwDfAQAUAAYJIyG8CwDfAQAlAAEJAADBPAAAAAAuAAQKfzkAAhQACAmKJaAKAEcDABQACAmKJaAKAEcDAAAA.Velandis:BAAALgADCgcJBwAAAA==.Velenari:BAAALgAECgEJAQABLgAECggJIwACAJkeAA==.Vellea:BAAALgAECgYJDgAAAA==.Velwar:BAAALgAECgcJBQABLgAFFAYJFAAUACMhAA==.Velýth:BAAALgAECgUJDAABLgAFFAYJFAAUACMhAA==.Venmeumshna:BAAALgADCgYJBgAAAA==.Veritas:BAAALgAECgYJCwAAAA==.Vexxius:BAACLgAFFH8FAAIOAAIJfRhwGACyAAAOAAIJfRhwGACyAAAuAAQKfxwABA4ACQkIGe8KADECAA4ACQn8FO8KADECABcABwkpFKEPABgBAAoAAQkgDxLZADkAAAAA.',
Vi='Viero:BAAALgAECgcJBwAAAA==.',
Vo='Vorathis:BAAALgAECgYJDAABLgAFFAQJDwAEALEkAA==.',
Vy='Vylana:BAAALgAECgYJDAABLgAFFAQJCAADAOQPAA==.',
['Và']='Vàlkyrie:BAACLgAFFH8JAAIDAAMJuBREOgD6AAADAAMJuBREOgD6AAAuAAQKfyIAAgMACQkNHnEiAKACAAMACQkNHnEiAKACAAAA.',
Wa='Wack:BAAALgAFFAEJAQAAAA==.Wanderfoot:BAABLgAECn8VAAIOAAYJVg6jIwAuAQAOAAYJVg6jIwAuAQAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn8jAAILAAgJ0hGISACCAQALAAgJ0hGISACCAQAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAIPAAgJ/QknIwAlAQAPAAgJ/QknIwAlAQAAAA==.Wavestabe:BAABLgAECn8vAAIGAAcJeheQCwChAQAGAAcJeheQCwChAQAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgcJLwAGAHoXAA==.',
Wr='Wreck:BAABLgAECn8lAAILAAgJMgzZWQBSAQALAAgJMgzZWQBSAQAAAA==.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.Xerxseize:BAAALgAECgEJAQAAAA==.',
['Xì']='Xìon:BAAALgAECgUJBQAAAA==.',
Ya='Yayrri:BAABLgAECn8iAAINAAgJlRCKJgBfAQANAAgJlRCKJgBfAQAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zahne:BAAALgAECgMJAwABLgAECgkJIQALAEEgAA==.Zatarra:BAAALgADCgEJAQAAAA==.Zathamax:BAABLgAECn8VAAIFAAgJaQNsowD7AAAFAAgJaQNsowD7AAAAAA==.Zavya:BAAALgADCgEJAQABLgAECgYJGwABABgMAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zextron:BAABLgAECn8oAAIoAAgJqRDaFQBzAQAoAAgJqRDaFQBzAQAAAA==.',
Zi='Ziaya:BAABLgAECn8bAAIBAAYJGAw5PQDLAAABAAYJGAw5PQDLAAAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgQJBwABLgAECgYJDgAWAAAAAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8oAAIoAAgJ6wfcHQAjAQAoAAgJ6wfcHQAjAQAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Él']='Élwë:BAAALgADCgUJBQAAAA==.',
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
