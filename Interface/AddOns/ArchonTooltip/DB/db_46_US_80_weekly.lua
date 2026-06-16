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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Druid-Restoration','Mage-Fire','DemonHunter-Devourer','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','DeathKnight-Blood','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Priest-Shadow','Paladin-Holy','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Hunter-Survival','Druid-Guardian','Priest-Holy','Warrior-Fury','Warrior-Protection','DeathKnight-Frost',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAUJDQABADAQAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgAECgIJAgAAAA==.Allice:BAABLgAECn8fAAMCAAcJwBxfAwA8AgACAAcJaxxfAwA8AgABAAQJoQyLDAGUAAAAAA==.Alsheyra:BAAALgAECgcJCwAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAFFAIJAgAAAA==.',
An='Anastasija:BAAALgAECgEJAgAAAA==.Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgYJDgAAAA==.',
Ar='Arahwn:BAAALgAECgUJBQAAAA==.',
As='Astaru:BAAALgAECgQJBwABLgAECgkJKAABAEAMAA==.',
Au='Aughyst:BAAALgAECgQJBAAAAA==.Augnyxia:BAABLgAECn8sAAQDAAcJnxOuJACYAQADAAcJuxGuJACYAQAEAAQJIAQ3LQB8AAAFAAQJ8Q5yHABmAAAAAA==.Augtism:BAABLgAECn8zAAQGAAkJXCJlAgCrAgAGAAgJqSFlAgCrAgAHAAkJgx9HKAA5AgAIAAEJAADXXQBVAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgUJBwAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAkJIQAFAMgfAA==.',
Be='Beefquake:BAAALgAECggJDwAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Berafii:BAAALgAECgEJAQAAAA==.Bersh:BAABLgAECn8xAAQJAAkJFR3+BgBeAgAJAAkJFxz+BgBeAgAKAAYJuhfiQQAnAQALAAEJAQiMngAyAAAAAA==.',
Bi='Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBAAAAA==.Bloodjury:BAABLgAECn8bAAIMAAgJvxpwUgDPAQAMAAgJvxpwUgDPAQAAAA==.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAABLgAECn8VAAINAAgJpxg0KwD8AQANAAgJpxg0KwD8AQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Booghur:BAAALgADCgUJBQAAAA==.Boonktown:BAABLgAECn8rAAMBAAkJnw3NYQC4AQABAAkJQA3NYQC4AQAOAAcJuQn5BAB9AQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgYJDgAAAA==.Bruceleela:BAAALgAECgYJCwABLgAECgcJIQAPAH4VAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bushetti:BAABLgAECn8dAAMNAAgJCBVsSwBfAQANAAgJCBVsSwBfAQAQAAMJmxiCZwB7AAABLgAFFAMJDQALANcfAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMKAAkJYBElJQDoAQAKAAkJYBElJQDoAQALAAYJDxW9VQBaAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgUJCAAAAA==.Cazisham:BAABLgAECn8jAAIJAAkJSQayGAA8AQAJAAkJSQayGAA8AQAAAA==.',
Ce='Cevianne:BAABLgAECn8sAAIRAAgJjRMsOADNAQARAAgJjRMsOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chamhealeon:BAAALgAECgIJAgAAAA==.Chanok:BAAALgADCgMJBgAAAA==.Chaoticsaint:BAABLgAECn8XAAISAAgJEBFRLwAHAQASAAgJEBFRLwAHAQAAAA==.Chingatumaga:BAAALgADCgIJAgAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Cl='Claros:BAAALgAECggJDAAAAA==.',
Co='Coal:BAABLgAECn81AAMPAAkJuCPECAAFAwAPAAkJuCPECAAFAwATAAcJ5xv9CADcAQAAAA==.Coalesce:BAAALgADCgQJBAABLgAECgkJNQAPALgjAA==.Coltonater:BAABLgAECn8+AAIBAAgJ7iHDJACHAgABAAgJ7iHDJACHAgAAAA==.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.',
['Cá']='Cáséy:BAACLgAFFH8QAAIBAAQJDh59QwBmAQABAAQJDh59QwBmAQAuAAQKfyMAAgEACQmeHUI4ADUCAAEACQmeHUI4ADUCAAAA.',
['Cä']='Cäsey:BAAALgAECgUJCQABLgAFFAUJEAABAA4eAA==.',
Da='Daktari:BAAALgADCgYJBgABLgAECgkJLgANAAocAA==.Dampening:BAAALgAECgMJAwABLgAECgUJBQAUAAAAAA==.Danbi:BAACLgAFFH8GAAMDAAQJzAeTOwDVAAADAAQJzAeTOwDVAAAEAAIJ+wj8JQBeAAAuAAQKfzUABAQACQmUF8ENAO8BAAQACAlEF8ENAO8BAAMACQn2E8scAO4BAAUABAm2D3gXAJ0AAAAA.Darkshroud:BAAALgAECgIJAgAAAA==.',
De='Deathdylan:BAACLgAFFH8QAAIVAAQJyQntJADGAAAVAAQJyQntJADGAAAuAAQKfzAAAhUACQlAHggKAHACABUACQlAHggKAHACAAAA.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAABLgAECn8hAAIPAAcJfhURYgBgAQAPAAcJfhURYgBgAQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Delice:BAAALgAECgEJAQAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demiev:BAAALgAECgEJAQAAAA==.Demítríus:BAAALgADCgYJDQAAAA==.Dethh:BAAALgADCgYJCQAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Di='Dionarose:BAAALgADCgYJBgAAAA==.Dionos:BAAALgAECgEJAQAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Dragonlord:BAAALgAECgYJBgAAAA==.Draugr:BAAALgADCgUJBQAAAA==.Dravyn:BAABLgAECn8oAAIBAAkJQAwjZwCrAQABAAkJQAwjZwCrAQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxNNQCeAgABAAgJmhxNNQCeAgAAAA==.Druqz:BAACLgAFFH8QAAIBAAQJAwSddAD4AAABAAQJAwSddAD4AAAuAAQKfxkAAgEACAmeCt+aAEABAAEACAmeCt+aAEABAAAA.Drævn:BAABLgAECn82AAMOAAYJGhpNBwAoAQABAAYJHBZnmABFAQAOAAUJThlNBwAoAQAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8aAAMPAAcJqB3rEwAGAgAPAAcJqB3rEwAGAgATAAIJQgsxDQBuAAAuAAQKfykAAg8ACQlvJD8GACQDAA8ACQlvJD8GACQDAAAA.Duragon:BAAALgAECgcJDQAAAA==.',
Dw='Dwimbear:BAAALgAECgEJAQAAAA==.Dwimhoof:BAAALgAECgEJAwAAAA==.',
Ed='Ediconegoen:BAAALgAECgEJAgAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAACLgAFFH8QAAIWAAQJqRwCHgBdAQAWAAQJqRwCHgBdAQAuAAQKfxsAAhYACQkAH/sPAD8CABYACQkAH/sPAD8CAAAA.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgYJDgAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJ0gt/bQCcAQABAAkJ0gt/bQCcAQACAAIJOgZTGQBNAAAAAA==.Endofdays:BAAALgAFFAIJAgAAAA==.Enro:BAACLgAFFH8IAAISAAQJiQwXEwAIAQASAAQJiQwXEwAIAQAuAAQKf0AAAxIACQmqH4wFAOQCABIACQmqH4wFAOQCAA8ABAmqB361AJ0AAAAA.',
Er='Erovia:BAACLgAFFH8HAAIRAAMJoQMGcACzAAARAAMJoQMGcACzAAAuAAQKfyMAAhEACQlXCfx9AD4BABEACQlXCfx9AD4BAAAA.',
Es='Esclipse:BAAALgAECgcJCgAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgAECgQJBwAAAA==.',
Fe='Felony:BAABLgAECn8zAAISAAkJGCSIAwAbAwASAAkJGCSIAwAbAwAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavaflare:BAAALgAECgEJAQABLgAECggJGwAQADEdAA==.Flavah:BAABLgAECn8bAAIQAAgJMR2YHAAdAgAQAAgJMR2YHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8wAAMXAAkJqBMEWgC2AQAXAAkJqBMEWgC2AQAVAAcJDQThOwCfAAAAAA==.Flower:BAABLgAFFH8FAAIRAAMJRxbCVQDzAAARAAMJRxbCVQDzAAAAAA==.',
Fo='Foodex:BAAALgAECgcJEQAAAA==.Fourleaf:BAACLgAFFH8RAAIYAAQJMxueEABUAQAYAAQJMxueEABUAQAuAAQKfzoAAhgACQlCIdYBAOsCABgACQlCIdYBAOsCAAAA.',
Fr='Frydayx:BAAALgAECgMJBAAAAA==.',
Fu='Furral:BAACLgAFFH8KAAIZAAMJRxlLDADqAAAZAAMJRxlLDADqAAAuAAQKfyEAAhkACQk3HwAEAMUCABkACQk3HwAEAMUCAAAA.',
Ga='Gaeth:BAABLgAECn8jAAINAAkJUBAIQgCZAQANAAkJUBAIQgCZAQAAAA==.',
Ge='Gelys:BAAALgAECgQJBAABLgAFFAQJBwAaAF8LAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Gl='Gleg:BAABLgAFFH8NAAILAAMJ1x+LNAAIAQALAAMJ1x+LNAAIAQAAAA==.',
Gn='Gnomeagedon:BAAALgAFFAIJAgAAAA==.',
Go='Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8WAAIPAAcJwxd9WwByAQAPAAcJwxd9WwByAQAAAA==.Grimthedread:BAAALgADCgYJBgAAAA==.Grimvess:BAAALgAECggJCQAAAA==.Griselden:BAAALgAFFAIJAgAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Hamburgler:BAAALgADCgYJBgABLgAECgkJIAARAKchAA==.Hammerobby:BAAALgAECgYJCgABLgAECgcJIQAPAH4VAA==.Handlebar:BAAALgAECgUJCgABLgAECgcJIQAPAH4VAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAFFAEJAQAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8gAAIMAAkJEREhXwCwAQAMAAkJEREhXwCwAQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.Holyshock:BAABLgAECn8YAAMMAAYJmgQGFwGZAAAMAAYJmgQGFwGZAAAbAAQJPgIRcgBrAAAAAA==.',
Hu='Hungsu:BAAALgAECgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgYJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Id='Idris:BAAALgADCgYJBgAAAA==.',
Il='Ilkkarid:BAABLgAECn8bAAMcAAgJIBKaGwC2AQAcAAgJ/BGaGwC2AQAdAAYJBgohEgDmAAAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAABLgAECn8ZAAIaAAcJpQotQwAAAQAaAAcJpQotQwAAAQAAAA==.',
Is='Ishpoo:BAABLgAECn8vAAIMAAkJ0xCPVQDHAQAMAAkJ0xCPVQDHAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jecht:BAAALgADCgEJAQAAAA==.Jelqer:BAABLgAECn8VAAMFAAYJsCCaEgC4AQAFAAYJsCCaEgC4AQADAAUJZBQXMABFAQAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8qAAINAAkJOR2hFACjAgANAAkJOR2hFACjAgAAAA==.Jlawzzs:BAAALgAECgMJAgAAAA==.',
Jo='Job:BAACLgAFFH8hAAMPAAgJ5R3DCQBvAgAPAAgJaR3DCQBvAgASAAMJNiJjDgAuAQAuAAQKfzwAAw8ACQmiJH8EADwDAA8ACQmiJH8EADwDABIABwm/INgjAJ4BAAAA.',
Ju='Juanweasley:BAAALgAECgMJBgAAAA==.Judoriel:BAAALgAECgcJDAAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8oAAIRAAkJuRpOHgBsAgARAAkJuRpOHgBsAgAAAA==.Kaimin:BAABLgAECn9MAAIXAAkJHCErDgD5AgAXAAkJHCErDgD5AgAAAA==.Karthas:BAAALgAECgIJBQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAUAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8xAAMWAAkJdRj1DwBuAgAWAAkJdRj1DwBuAgAaAAMJFAPIVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8yAAMLAAkJ8xBIPgCxAQALAAkJ8xBIPgCxAQAJAAQJfArpKgCYAAAAAA==.Khonsu:BAAALgAECgcJDAAAAA==.',
Ki='Kiba:BAABLgAECn8kAAMeAAcJwg+nQgBaAQAeAAcJwg+nQgBaAQAfAAQJpgopWQCqAAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAABLgAECn8gAAILAAgJ2Rg4IwA3AgALAAgJ2Rg4IwA3AgAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Kowadin:BAAALgADCgEJAQAAAA==.Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8lAAIgAAkJkQu7GgA/AQAgAAkJkQu7GgA/AQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAACLgAFFH8TAAIeAAUJFROnIgBKAQAeAAUJFROnIgBKAQAuAAQKfzwAAx4ACQkQIcwGADEDAB4ACQkQIcwGADEDAB8AAwl3DspjAIwAAAAA.',
La='Larethiana:BAACLgAFFH8FAAINAAUJhgriKwABAQANAAUJhgriKwABAQAuAAQKfxQAAw0ACAnpFKJMAHEBAA0ABwmMFaJMAHEBABAABgn1FgA1AGoBAAAA.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMbAAYJXQMfagDSAAAbAAYJXQMfagDSAAAMAAQJRQGAIQFbAAAAAA==.',
Li='Lightbright:BAACLgAFFH8MAAIMAAQJ6BzAKQBeAQAMAAQJ6BzAKQBeAQAuAAQKfyMAAgwACQlVJJcHAFoDAAwACQlVJJcHAFoDAAAA.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAABLgAECn8pAAIaAAcJZB4tFgAYAgAaAAcJZB4tFgAYAgAAAA==.Linnasha:BAABLgAECn8rAAINAAgJwBikLwDiAQANAAgJwBikLwDiAQAAAA==.Litlefoot:BAAALgAECgkJEwAAAA==.',
Lo='Lornzap:BAABLgAFFH8MAAIKAAMJNBtaKADuAAAKAAMJNBtaKADuAAAAAA==.Lostwanderer:BAABLgAECn8dAAMeAAgJBRg6HQApAgAeAAgJBRg6HQApAgAfAAIJrAXjjABBAAAAAA==.Lot:BAAALgAFFAEJAQABLgAFFAgJIQAPAOUdAA==.Lowcowlorie:BAAALgAECgEJAQAAAA==.',
Ma='Machine:BAACLgAFFH8GAAIhAAMJqRKXHQDgAAAhAAMJqRKXHQDgAAAuAAQKfx8AAiEACQlfEgsSABoCACEACQlfEgsSABoCAAAA.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8xAAISAAkJ3xbfEQAKAgASAAkJ3xbfEQAKAgAAAA==.Manamontana:BAAALgAECgEJAQAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Mannanan:BAAALgAECgcJDgAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meatrocketxd:BAAALgAECgcJAQAAAA==.Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8xAAQRAAkJziAGEgC9AgARAAkJziAGEgC9AgAhAAIJPRBMTgB0AAAYAAEJhwz9PAAuAAAAAA==.Minyaura:BAAALgADCgQJBAAAAA==.Minyholy:BAAALgAECgQJBAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Mirañda:BAAALgADCgEJAQAAAA==.Miridian:BAAALgAECgcJDwAAAA==.Miromoney:BAAALgADCgUJBQAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgAECgYJDgAAAA==.Moogician:BAAALgAECgIJBgABLgAECgkJIAARAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonsïnd:BAABLgAECn8rAAMNAAkJZA26PwCRAQANAAkJZA26PwCRAQAZAAIJehLbOABvAAAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgADCgQJAwAAAA==.Morgrin:BAAALgAECgQJBgAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8iAAIcAAgJAhNrIQCGAQAcAAgJAhNrIQCGAQAAAA==.',
My='Mydira:BAAALgAECgkJDAAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAACLgAFFH8GAAINAAMJdQZtSwCKAAANAAMJdQZtSwCKAAAuAAQKfxkABA0ACQmnGF8VAJsCAA0ACQmnGF8VAJsCACIAAgn4B6drADoAABAAAQmXChKQACwAAAAA.Nalthexon:BAAALgAECgYJBgABLgAFFAMJBgANAHUGAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neko:BAAALgAFFAEJAQAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAbANscAA==.',
Ni='Niavanith:BAAALgAECgYJEgAAAA==.Nights:BAAALgAECgcJEgABLgAFFAMJBgAhAKkSAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAACLgAFFH8SAAMFAAQJdB3XAgBQAQAFAAQJdB3XAgBQAQADAAQJrQ+lMQD5AAAuAAQKf0IAAwUACQnUI8UAACgDAAUACQnUI8UAACgDAAQABQnUFa4YAEUBAAAA.Nizo:BAABLgAECn8uAAINAAkJChwbDgDlAgANAAkJChwbDgDlAgAAAA==.',
No='Noblitz:BAACLgAFFH8HAAMaAAQJXwuMHQD+AAAaAAQJXwuMHQD+AAAjAAEJNxXoNAA7AAAuAAQKfxsAAxoACQlWGOwPAF0CABoACQlWGOwPAF0CACMABgnWGC0mAI8BAAAA.Novastrike:BAABLgAECn8mAAMLAAgJohc4QgCgAQALAAgJohc4QgCgAQAKAAgJ3wteWQDUAAAAAA==.',
Ny='Nyrif:BAACLgAFFH8QAAIVAAQJJRsMFgA0AQAVAAQJJRsMFgA0AQAuAAQKfyIAAhUACQnzGpEQAP8BABUACQnzGpEQAP8BAAAA.',
Oj='Ojoon:BAABLgAECn8UAAIBAAcJOgpdrQAiAQABAAcJOgpdrQAiAQAAAA==.',
Om='Omnisllash:BAABLgAFFH8GAAIBAAMJ+QllhQDUAAABAAMJ+QllhQDUAAAAAA==.',
Or='Orisana:BAACLgAFFH8TAAMhAAQJoxvCDgBKAQAhAAQJoxvCDgBKAQARAAIJNxVMhACLAAAuAAQKf04ABCEACQlCIXUFAM4CABgACQnAGnkMAOUCACEACQneH3UFAM4CABEABQmMGfl+ADwBAAAA.',
Pa='Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8YAAMEAAUJAQx3FwAVAQAEAAUJAQx3FwAVAQADAAEJlwidYwA7AAAAAA==.Pewpewbang:BAAALgAECgQJBAAAAA==.',
Ph='Phoenìx:BAAALgAECgEJAgAAAA==.Phyter:BAAALgAECgIJBQAAAA==.',
Pi='Pillin:BAABLgAECn8UAAMdAAcJZhcOCQCaAQAdAAcJZhcOCQCaAQAcAAIJKgofXAA1AAAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8hAAMkAAkJcB29FgA3AgAkAAkJcB29FgA3AgAlAAEJ7AghUQA0AAAAAA==.Powerwordmoo:BAAALgAECgEJAQABLgAECgkJIAARAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Prina:BAAALgADCgUJBQAAAA==.Provi:BAAALgAECggJDAAAAA==.',
Ps='Psyffe:BAAALgAECgUJCgAAAA==.Psyrge:BAAALgAECgYJBgAAAA==.',
Qu='Queue:BAABLgAECn86AAIVAAkJcw+BGgCIAQAVAAkJcw+BGgCIAQAAAA==.',
Re='Rebeccayaros:BAAALgAECgUJDwAAAA==.Redle:BAABLgAECn8aAAIMAAgJzQsmnQA5AQAMAAgJzQsmnQA5AQAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAECLgAFFH8TAAQhAAQJKRhoDgBNAQAhAAQJKRhoDgBNAQAYAAEJtgcQKgBIAAARAAEJFANhqQA8AAAuAAQKfzQAAyEACQmxHzMGAL4CACEACQlOHjMGAL4CABgACAkSFgAeADYCAAAA.',
Ro='Rokkitok:BAAALgAECgcJEAAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
Ru='Rulnic:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràwrshàk:BAAALgAECgYJDQAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8mAAIRAAkJqBqXKQA0AgARAAkJqBqXKQA0AgAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgABLgAFFAEJAQAUAAAAAA==.',
Se='Sea:BAACLgAFFH8iAAILAAYJ6h0tCwARAgALAAYJ6h0tCwARAgAuAAQKfyMAAgsACQmyIOYBAG4DAAsACQmyIOYBAG4DAAAA.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgkJDwAAAA==.Shadowrose:BAABLgAECn8xAAMZAAkJahn1CwD1AQAZAAgJuhf1CwD1AQANAAQJhQ1teQDIAAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAABLgAECn8YAAIHAAkJuBT4NQAAAgAHAAkJuBT4NQAAAgAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAwAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAUAAAAAA==.Shiemi:BAAALgAECgcJBgAAAA==.Shootingbo:BAAALgAECgEJAQAAAA==.Shunsui:BAACLgAFFH8JAAIHAAQJfAtgXQAIAQAHAAQJfAtgXQAIAQAuAAQKfy4AAwcACQlcG/odAG8CAAcACQlcG/odAG8CAAgAAQkAACRvADcAAAAA.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Silentomen:BAAALgADCgkJCQAAAA==.Siley:BAABLgAECn8YAAIbAAkJ2xzDFABrAgAbAAkJ2xzDFABrAgAAAA==.Sinnister:BAAALgAFFAIJAgAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgYJCwAAAA==.',
Sk='Skullmonkêy:BAAALgAFFAMJAwABLgAFFAQJCQAHAHwLAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAABLgAFFH8GAAIcAAEJWxvmOABVAAAcAAEJWxvmOABVAAAAAA==.',
So='Sooner:BAACLgAFFH8SAAMXAAQJMx8LSgBZAQAXAAQJMx8LSgBZAQAmAAMJXRR8FgDOAAAuAAQKfxkAAyYABwl7HfEEAPwBACYABgl0IPEEAPwBABcABQkMHPiCAHwBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgIJAgAAAA==.',
Sq='Squeaky:BAAALgAECgcJEQAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.',
Sy='Syrupp:BAAALgAECgkJDgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.Tayn:BAAALgAECgMJBAAAAA==.',
Te='Tealeaf:BAAALgAECgQJBAAAAA==.Temporary:BAAALgAECgIJAgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Thackery:BAAALgADCgMJBAAAAA==.Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
To='Tortus:BAAALgAECgEJAQAAAA==.Toxicrumor:BAAALgAFFAMJAwAAAA==.',
Tr='Triplenine:BAAALgAECgIJAgABLgAFFAgJIAABAG4bAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgQJBQAAAA==.',
Tu='Tucktoo:BAAALgAECgYJCQAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAACLgAFFH8RAAMaAAQJvw/qGgAPAQAaAAQJvw/qGgAPAQAWAAIJRAWzQABwAAAuAAQKfy8AAxoACQnmFukVABsCABoACQnmFukVABsCABYABAlICK1PAMAAAAAA.',
Uw='Uwurailme:BAABLgAECn8VAAQIAAcJNg8KMgDwAAAHAAYJcQxriwBCAQAIAAUJHAoKMgDwAAAGAAIJrRN5HQCGAAAAAA==.',
Va='Valenix:BAACLgAFFH8OAAMfAAQJuwa5JQC2AAAfAAQJuwa5JQC2AAAeAAMJSwoORACIAAAuAAQKfx8AAx8ACQlmEHBBAPYAAB8ABwlDEHBBAPYAAB4ACAnrEedrAMoAAAAA.Valkryi:BAAALgAECgEJAQAAAA==.Varys:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.Vaxîs:BAAALgAECgMJAwAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAAALgAECgUJBgAAAA==.',
Vo='Vo:BAAALgAECgYJEgAAAA==.',
Vu='Vulasity:BAAALgAECgcJBwAAAA==.',
Wa='Warder:BAABLgAECn8cAAIkAAgJABduIgDeAQAkAAgJABduIgDeAQAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wiigo:BAAALgAFFAIJAwAAAA==.Wincks:BAABLgAECn8ZAAMIAAcJsRx/DABzAQAIAAYJIB5/DABzAQAHAAUJNRbZewBAAQAAAA==.',
Xa='Xana:BAAALgADCgUJBQABLgAFFAQJBwAaAF8LAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAABLgAECn8nAAICAAkJjxVrAgAuAgACAAkJjxVrAgAuAgAAAA==.Zackman:BAACLgAFFH8TAAIbAAQJRwd6LADEAAAbAAQJRwd6LADEAAAuAAQKf0MAAhsACQkYE1oZADoCABsACQkYE1oZADoCAAAA.',
Zh='Zhimer:BAAALgADCgIJAgAAAA==.',
Zi='Zinagos:BAAALgAFFAIJAgABLgAFFAQJDgAfALsGAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.Zombie:BAAALgAFFAIJAgAAAA==.Zosos:BAAALgAECgEJAgAAAA==.',
Zu='Zulrea:BAAALgAECgcJCgAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJCwAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAFFAEJAQAUAAAAAA==.',
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
