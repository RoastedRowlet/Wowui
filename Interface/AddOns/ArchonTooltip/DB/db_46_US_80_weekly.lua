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
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAUJDQABADAQAA==.',
Ab='Abotou:BAAALgAECgEJAQAAAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgAECgIJAgAAAA==.Allice:BAABLgAECn8fAAMCAAcJwBxfAwA8AgACAAcJaxxfAwA8AgABAAQJoQwFEAGUAAAAAA==.Alsheyra:BAAALgAECgcJCwAAAA==.Altan:BAAALgADCgMJAwAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAFFAIJAgAAAA==.',
An='Anastasija:BAAALgAECgEJAgAAAA==.Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgcJEAAAAA==.',
Ar='Arahwn:BAAALgAECgUJBQAAAA==.',
As='Astaru:BAAALgAECgQJBwABLgAECgkJKAABAEAMAA==.',
Au='Aughyst:BAAALgAECgQJBAAAAA==.Augnyxia:BAABLgAECn8tAAQDAAgJJROuJACYAQADAAgJhhGuJACYAQAEAAQJIATiLQB7AAAFAAQJ8Q7rHABmAAAAAA==.Augtism:BAABLgAECn85AAQGAAkJ4CJ9AgCpAgAGAAgJQCJ9AgCpAgAHAAkJPSDkKAA4AgAIAAIJYx8wCABYAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgUJDAAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAkJOQAFAPAiAA==.',
Be='Beefquake:BAAALgAECgkJEQAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Berafii:BAAALgAECgEJAQAAAA==.Bersh:BAABLgAECn8xAAQJAAkJFR0xBwBdAgAJAAkJFxwxBwBdAgAKAAYJuhftQgAnAQALAAEJAQiMngAyAAAAAA==.',
Bi='Bigmoomoo:BAAALgAECgkJDAAAAA==.Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBwAAAA==.Bloodjury:BAACLgAFFH8FAAIMAAIJdAwQNACHAAAMAAIJdAwQNACHAAAuAAQKfx0AAgwACQlcGZlTAM4BAAwACQlcGZlTAM4BAAAA.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAABLgAECn8VAAINAAgJpxiVKwD8AQANAAgJpxiVKwD8AQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Booghur:BAAALgADCgUJBQAAAA==.Boonktown:BAABLgAECn8rAAMBAAkJnw0gYwC4AQABAAkJQA0gYwC4AQAOAAcJuQn5BAB9AQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgYJDgAAAA==.Broken:BAAALgAECgEJAgAAAA==.Bruceleela:BAAALgAECgYJCwABLgAECgcJIQAPAH4VAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bumslapr:BAAALgAECgEJAQAAAA==.Bushetti:BAABLgAECn8dAAMNAAgJCBVVTABeAQANAAgJCBVVTABeAQAQAAMJmxg/aQB7AAAAAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMKAAkJYBElJQDoAQAKAAkJYBElJQDoAQALAAYJDxUgVwBaAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgUJCAAAAA==.Cazisham:BAABLgAECn8kAAIJAAkJSQZFGQA7AQAJAAkJSQZFGQA7AQAAAA==.',
Ce='Cevianne:BAABLgAECn8sAAIRAAgJjRMsOADNAQARAAgJjRMsOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chamhealeon:BAAALgAECgIJAgAAAA==.Chanok:BAAALgADCgUJCAAAAA==.Chaoticsaint:BAABLgAECn8XAAISAAgJEBF2MAAFAQASAAgJEBF2MAAFAQAAAA==.Chingatumaga:BAAALgADCgcJCQAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Ci='Cinnabuns:BAAALgADCgEJAQAAAA==.',
Cl='Claros:BAAALgAECggJDQAAAA==.',
Co='Coal:BAABLgAECn8+AAMPAAkJBiT9CAAFAwAPAAkJBiT9CAAFAwATAAcJ5xsdCQDcAQAAAA==.Coalesce:BAAALgADCgQJBAABLgAECgkJPgAPAAYkAA==.Coltonater:BAACLgAFFH8FAAIBAAIJ9BYoOgCbAAABAAIJ9BYoOgCbAAAuAAQKfz4AAgEACAnuIYElAIYCAAEACAnuIYElAIYCAAAA.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.Curtis:BAAALgAFFAEJAQAAAA==.',
['Cá']='Cáséy:BAACLgAFFH8VAAIBAAQJDh41RABgAQABAAQJDh41RABgAQAuAAQKfyMAAgEACQmeHSg5ADQCAAEACQmeHSg5ADQCAAAA.',
['Cä']='Cäsey:BAAALgAECgYJCgABLgAFFAUJFQABAA4eAA==.',
Da='Daktari:BAAALgAECgQJBAABLgAECgkJNgANAMceAA==.Dampening:BAAALgAECgMJAwABLgAECgUJBQAUAAAAAA==.Danbi:BAACLgAFFH8PAAQFAAUJlAh5AgCuAAADAAQJzAfQPQDQAAAFAAMJLAZ5AgCuAAAEAAQJuAtlDAB/AAAuAAQKfzUABAQACQmUF+wNAPABAAQACAlEF+wNAPABAAMACQn2E24dAOsBAAUABAm2D9gXAJ0AAAAA.Darkshroud:BAAALgAECgIJAgAAAA==.Daugy:BAAALgAECgIJAwAAAA==.',
De='Deathdylan:BAACLgAFFH8YAAIVAAQJFg1ADADRAAAVAAQJFg1ADADRAAAuAAQKfzIAAhUACQknHzEIAJQCABUACQknHzEIAJQCAAAA.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAABLgAECn8hAAIPAAcJfhVgYwBhAQAPAAcJfhVgYwBhAQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Delice:BAAALgAECgYJBwAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demiev:BAAALgAECgEJAQAAAA==.Demonware:BAAALgAECgEJAQAAAA==.Demítríus:BAAALgADCgYJEwAAAA==.Destroya:BAAALgADCgEJAwAAAA==.Dethh:BAAALgADCgYJCQAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Di='Dionarose:BAAALgADCgYJBgAAAA==.Dionos:BAAALgAECgEJAQAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Dragonlord:BAAALgAECgYJBgAAAA==.Draugr:BAAALgAECgMJAwAAAA==.Dravyn:BAABLgAECn8oAAIBAAkJQAzEaACrAQABAAkJQAzEaACrAQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxNNQCeAgABAAgJmhxNNQCeAgAAAA==.Druqz:BAACLgAFFH8WAAIBAAUJeQQHOQChAAABAAUJeQQHOQChAAAuAAQKfxkAAgEACAmeChqdAEABAAEACAmeChqdAEABAAAA.Drævn:BAABLgAECn9EAAMOAAcJZRjiBQBmAQABAAcJrxQsfQB9AQAOAAYJ7BjiBQBmAQAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8dAAMPAAgJQRu3FQADAgAPAAgJQRu3FQADAgATAAIJQgumDQBuAAAuAAQKfykAAg8ACQlvJH4GACQDAA8ACQlvJH4GACQDAAAA.Duragon:BAAALgAECggJEwAAAA==.',
Dw='Dwimbear:BAAALgAECgEJAQAAAA==.Dwimhoof:BAAALgAECgEJBwAAAA==.',
Ed='Ediconegoen:BAAALgAECgEJAgAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAACLgAFFH8XAAIWAAQJWx+CCgBLAQAWAAQJWx+CCgBLAQAuAAQKfxsAAhYACQkAH/sPAD8CABYACQkAH/sPAD8CAAAA.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgYJDgAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJ0gtCbwCcAQABAAkJ0gtCbwCcAQACAAIJOgZTGQBNAAAAAA==.Endofdays:BAABLgAFFH8GAAIXAAMJJA2cpwDMAAAXAAMJJA2cpwDMAAAAAA==.Enro:BAACLgAFFH8RAAISAAUJSQ+8EgAOAQASAAUJSQ+8EgAOAQAuAAQKf0IAAxIACQnrH4oFAOcCABIACQnrH4oFAOcCAA8ABAmqB361AJ0AAAAA.',
Er='Erovia:BAACLgAFFH8LAAIRAAMJ9QQSOgB1AAARAAMJ9QQSOgB1AAAuAAQKfyMAAhEACQlXCYKAAD4BABEACQlXCYKAAD4BAAAA.',
Es='Esclipse:BAAALgAECgcJCgAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgAFFAEJAQAAAA==.',
Fe='Felony:BAABLgAECn8zAAISAAkJGCS4AwAYAwASAAkJGCS4AwAYAwAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavaflare:BAAALgAECgEJAQABLgAECggJGwAQADEdAA==.Flavah:BAABLgAECn8bAAIQAAgJMR2YHAAdAgAQAAgJMR2YHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floor:BAAALgAECgYJDAAAAA==.Floormatt:BAABLgAECn8wAAMXAAkJqBP2WgC2AQAXAAkJqBP2WgC2AQAVAAcJDQRAPQCbAAAAAA==.Flower:BAABLgAFFH8FAAIRAAMJRxbTWQDyAAARAAMJRxbTWQDyAAAAAA==.',
Fo='Foodex:BAAALgAECgcJEQAAAA==.Fourleaf:BAACLgAFFH8cAAIYAAUJMxs1EQBQAQAYAAUJMxs1EQBQAQAuAAQKfzwAAhgACQlCIe0BAOoCABgACQlCIe0BAOoCAAAA.',
Fr='Frydayx:BAAALgAECgMJBAAAAA==.',
Fu='Furral:BAACLgAFFH8MAAIZAAMJRxnMDADqAAAZAAMJRxnMDADqAAAuAAQKfyEAAhkACQk3HxIEAMYCABkACQk3HxIEAMYCAAAA.',
Ga='Gaeth:BAABLgAECn8jAAINAAkJUBAIQgCZAQANAAkJUBAIQgCZAQAAAA==.',
Ge='Gelys:BAAALgAECgQJBAABLgAFFAQJCAAaAF8LAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Gl='Gleg:BAABLgAFFH8QAAILAAMJdSTYDAA0AQALAAMJdSTYDAA0AQAAAA==.Glibby:BAAALgAECgMJAwABLgAFFAQJCAAaAF8LAA==.',
Gn='Gnomeagedon:BAAALgAFFAMJAwAAAA==.',
Go='Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Granddiddy:BAAALgADCgEJAQAAAA==.Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8WAAIPAAcJwxeSXAByAQAPAAcJwxeSXAByAQAAAA==.Grimthedread:BAAALgADCgYJBgAAAA==.Grimvess:BAAALgAECggJCQAAAA==.Griselden:BAABLgAFFH8GAAIPAAIJeQ3eiABwAAAPAAIJeQ3eiABwAAAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Hamburgler:BAAALgADCgYJBgABLgAECgkJIAARAKchAA==.Hammerobby:BAAALgAECgYJCgABLgAECgcJIQAPAH4VAA==.Handlebar:BAAALgAECgUJCgABLgAECgcJIQAPAH4VAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAFFAEJAQAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8gAAIMAAkJERGEYQCtAQAMAAkJERGEYQCtAQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.Holyshock:BAABLgAECn8dAAMMAAcJIgZwFAGgAAAMAAYJmgRwFAGgAAAbAAYJEgOoDABfAAAAAA==.',
Hu='Hungsu:BAAALgAECgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgYJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Id='Idris:BAAALgADCgYJCQAAAA==.',
Il='Ilkkarid:BAABLgAECn8bAAMcAAgJIBISHAC2AQAcAAgJ/BESHAC2AQAdAAYJBgp3EgDiAAAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAABLgAECn8dAAIaAAcJeg0eBwDmAAAaAAcJeg0eBwDmAAAAAA==.',
Is='Ishpoo:BAABLgAECn8vAAIMAAkJ0xC8VgDHAQAMAAkJ0xC8VgDHAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jecht:BAAALgADCgEJAQAAAA==.Jelqer:BAABLgAECn8VAAMFAAYJsCCaEgC4AQAFAAYJsCCaEgC4AQADAAUJZBQXMABFAQAAAA==.Jenila:BAEALgAECgEJAQABLgAECgcJDAAUAAAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8qAAINAAkJOR3uFACiAgANAAkJOR3uFACiAgAAAA==.Jlawzzs:BAAALgAECgMJAgAAAA==.',
Jo='Job:BAACLgAFFH8nAAMPAAgJ5R0/CwBqAgAPAAgJaR0/CwBqAgASAAMJ1CIADwAsAQAuAAQKfz0AAw8ACQmiJLYEADsDAA8ACQmiJLYEADsDABIABwm/INgjAJ4BAAAA.',
Ju='Juanweasley:BAAALgAFFAEJAQAAAA==.Judoriel:BAAALgAECgcJDAAAAA==.Julz:BAAALgADCgUJBQAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8oAAIRAAkJuRoiHwBsAgARAAkJuRoiHwBsAgAAAA==.Kaimin:BAABLgAECn9YAAIXAAkJ7yGYAQDdAgAXAAkJ7yGYAQDdAgAAAA==.Kaledor:BAAALgADCgEJAQAAAA==.Karthas:BAAALgAECgIJBQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAUAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8xAAMWAAkJdRhLEABsAgAWAAkJdRhLEABsAgAaAAMJFAPIVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8yAAMLAAkJ8xA0PwCxAQALAAkJ8xA0PwCxAQAJAAQJfAo0LACXAAAAAA==.Khonsu:BAAALgAECgcJDAAAAA==.',
Ki='Kiba:BAABLgAECn8kAAMeAAcJwg8qRABbAQAeAAcJwg8qRABbAQAfAAQJpgpOWgCqAAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAABLgAECn8gAAILAAgJ2Rj5IwA3AgALAAgJ2Rj5IwA3AgAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Kowadin:BAAALgADCgEJAQAAAA==.Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8lAAIgAAkJkQsiGwA/AQAgAAkJkQsiGwA/AQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAACLgAFFH8gAAIeAAUJUxXUDgAxAQAeAAUJUxXUDgAxAQAuAAQKfzwAAx4ACQkQIfMGADIDAB4ACQkQIfMGADIDAB8AAwl3Dg1mAIoAAAAA.',
La='Larenta:BAAALgADCgYJBgAAAA==.Larethiana:BAACLgAFFH8FAAINAAUJhgoSLQABAQANAAUJhgoSLQABAQAuAAQKfxQAAw0ACAnpFKJMAHEBAA0ABwmMFaJMAHEBABAABgn1FgA1AGoBAAAA.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMbAAYJXQMfagDSAAAbAAYJXQMfagDSAAAMAAQJRQGAIQFbAAAAAA==.',
Li='Lightbright:BAACLgAFFH8UAAIMAAUJFCCWLABcAQAMAAUJFCCWLABcAQAuAAQKfyMAAgwACQlVJJcHAFoDAAwACQlVJJcHAFoDAAAA.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAABLgAECn8yAAIaAAcJlB4XFgAaAgAaAAcJlB4XFgAaAgAAAA==.Linnasha:BAABLgAECn8tAAINAAkJLhfUJAAlAgANAAkJLhfUJAAlAgAAAA==.Litlefoot:BAAALgAECgkJEwAAAA==.',
Lo='Lornzap:BAABLgAFFH8NAAIKAAMJNBsWKgDtAAAKAAMJNBsWKgDtAAAAAA==.Lostwanderer:BAABLgAECn8dAAMeAAgJBRjbHQAqAgAeAAgJBRjbHQAqAgAfAAIJrAV/jwBBAAAAAA==.Lot:BAAALgAFFAEJAQABLgAFFAgJJwAPAOUdAA==.Lowcowlorie:BAAALgAECgEJAQAAAA==.',
Ma='Machine:BAACLgAFFH8IAAIhAAMJqRJhDACXAAAhAAMJqRJhDACXAAAuAAQKfx8AAiEACQlfElUSABYCACEACQlfElUSABYCAAAA.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8xAAISAAkJ3xYlEgAKAgASAAkJ3xYlEgAKAgAAAA==.Manamontana:BAAALgAECgQJBAAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Mannanan:BAAALgAECgcJDgAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meatrocketxd:BAAALgAECgcJAQAAAA==.Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8xAAQRAAkJziC1EgC8AgARAAkJziC1EgC8AgAhAAIJPRAaTwB0AAAYAAEJhwzvPQAuAAAAAA==.Minyaura:BAAALgADCgQJBAAAAA==.Minyholy:BAAALgAECgQJBAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Mirañda:BAAALgADCgEJAQAAAA==.Miridian:BAAALgAECgcJDwAAAA==.Miromoney:BAAALgADCgUJBQAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgAECgYJEgAAAA==.Moogician:BAAALgAECgIJBgABLgAECgkJIAARAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonmama:BAAALgADCgMJAwAAAA==.Moonsïnd:BAABLgAECn8rAAMNAAkJZA1wQACQAQANAAkJZA1wQACQAQAZAAIJehJlOgBvAAAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgAECgcJDwAAAA==.Morgrin:BAAALgAECgQJBgAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8iAAIcAAgJAhP1IQCGAQAcAAgJAhP1IQCGAQAAAA==.',
My='Mydira:BAAALgAECgkJDAAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAACLgAFFH8GAAINAAMJdQYfTQCKAAANAAMJdQYfTQCKAAAuAAQKfxkABA0ACQmnGK8VAJsCAA0ACQmnGK8VAJsCACIAAgn4BxJvADoAABAAAQmXCs6SACwAAAAA.Nalthexon:BAAALgAECgYJBgABLgAFFAMJBgANAHUGAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neko:BAAALgAFFAIJAwAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAbANscAA==.',
Ni='Niavanith:BAAALgAECgYJEgAAAA==.Nicotine:BAAALgAECgEJAQAAAA==.Nights:BAAALgAFFAEJAQABLgAFFAMJCAAhAKkSAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAACLgAFFH8eAAMFAAUJdB3kAgBSAQAFAAUJdB3kAgBSAQADAAQJrQ/vMgD2AAAuAAQKf0QAAwUACQnUI8oAACcDAAUACQnUI8oAACcDAAQABQnUFfMYAEUBAAAA.Nizo:BAABLgAECn82AAINAAkJxx6XDQDtAgANAAkJxx6XDQDtAgAAAA==.',
Nj='Njal:BAAALgAECgQJBAAAAA==.',
No='Noblitz:BAACLgAFFH8IAAMaAAQJXwt5HgD+AAAaAAQJXwt5HgD+AAAjAAEJNxU/NgA6AAAuAAQKfyAABBoACQlWGB8QAFsCABoACQlWGB8QAFsCACMABgnRGdcmAI4BABYAAQkIHtUQAFUAAAAA.Novastrike:BAABLgAECn8mAAMLAAgJohdNQwCgAQALAAgJohdNQwCgAQAKAAgJ3wtTWwDSAAAAAA==.',
Ny='Nyrif:BAACLgAFFH8XAAIVAAQJLBtACAAjAQAVAAQJLBtACAAjAQAuAAQKfyIAAhUACQnzGuMQAP0BABUACQnzGuMQAP0BAAAA.',
Oj='Ojoon:BAABLgAECn8YAAIBAAcJCQ67FgC9AAABAAcJCQ67FgC9AAAAAA==.',
Om='Omnisllash:BAACLgAFFH8IAAIBAAMJSwr4PACPAAABAAMJSwr4PACPAAAuAAQKfxcAAgEACAl0FJZVANwBAAEACAl0FJZVANwBAAAA.',
Or='Orisana:BAACLgAFFH8TAAMhAAQJoxtfDwBJAQAhAAQJoxtfDwBJAQARAAIJNxWQiQCLAAAuAAQKf1EABCEACQlCIaIFAMsCABgACQnAGnkMAOUCACEACQneH6IFAMsCABEABQmMGY2BADsBAAAA.',
Pa='Palatrin:BAAALgADCggJDwAAAA==.Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8YAAMEAAUJAQwLGAAVAQAEAAUJAQwLGAAVAQADAAEJlwjiZgA4AAAAAA==.Pewpewbang:BAAALgAECgQJBQAAAA==.',
Ph='Phoenìx:BAAALgAECgEJAgAAAA==.Phyter:BAAALgAECgIJBQAAAA==.',
Pi='Pillin:BAABLgAECn8XAAMdAAcJ4BgiCQCaAQAdAAcJtxgiCQCaAQAcAAIJRxDcWABEAAAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8hAAMkAAkJcB0zFwA0AgAkAAkJcB0zFwA0AgAlAAEJ7AiGUgA0AAAAAA==.Powerwordmoo:BAAALgAECgEJAQABLgAECgkJIAARAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Prina:BAAALgADCgUJBQAAAA==.Provi:BAAALgAECggJDAAAAA==.',
Ps='Psyffe:BAAALgAECgUJCgAAAA==.Psyrge:BAAALgAECgYJBgAAAA==.',
Qu='Queue:BAABLgAECn9DAAIVAAkJIBD6GgCFAQAVAAkJIBD6GgCFAQAAAA==.',
Re='Rebeccayaros:BAAALgAECgUJDwAAAA==.Redle:BAABLgAECn8fAAIMAAgJdA2yFADKAAAMAAgJdA2yFADKAAAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAECLgAFFH8eAAQhAAUJERkjBAA1AQAhAAUJERkjBAA1AQAYAAEJtgcQKgBIAAARAAEJFAPtrwA8AAAuAAQKfzUAAyEACQmxH38GALkCACEACQlOHn8GALkCABgACAkSFgAeADYCAAAA.',
Ro='Rokkitok:BAAALgAECgkJEgAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
Ru='Rulnic:BAAALgAECgEJAgAAAA==.',
['Rà']='Ràwrshàk:BAAALgAECgYJDQAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8nAAIRAAkJqBq4KgAzAgARAAkJqBq4KgAzAgAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgABLgAFFAEJAQAUAAAAAA==.',
Sa='Sanyo:BAAALgADCgEJAQAAAA==.Sarahjan:BAAALgAECgIJAgAAAA==.Sathen:BAAALgADCgEJAQAAAA==.',
Se='Sea:BAACLgAFFH8iAAILAAYJ6h1HDAARAgALAAYJ6h1HDAARAgAuAAQKfyMAAgsACQmyIOYBAG4DAAsACQmyIOYBAG4DAAAA.Seliph:BAAALgAECgQJBAAAAA==.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgkJDwAAAA==.Shadowrose:BAABLgAECn8xAAMZAAkJahkuDAD2AQAZAAgJuhcuDAD2AQANAAQJhQ3OegDHAAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAABLgAECn8aAAIHAAkJ4hV6NwD7AQAHAAkJ4hV6NwD7AQAAAA==.Shamamama:BAAALgADCgEJAQAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAwAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAUAAAAAA==.Shiemi:BAAALgAECgcJBgAAAA==.Shootingbo:BAAALgAECgEJAQAAAA==.Shunsui:BAACLgAFFH8LAAIHAAUJfAuuXwAIAQAHAAUJfAuuXwAIAQAuAAQKfzAAAwcACQmoG5sdAHMCAAcACQmoG5sdAHMCAAgAAQkAACRvADcAAAAA.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Silentomen:BAAALgADCgkJCQAAAA==.Siley:BAABLgAECn8YAAIbAAkJ2xzDFABrAgAbAAkJ2xzDFABrAgAAAA==.Sinnister:BAABLgAFFH8GAAIPAAQJZhKWIgDEAAAPAAQJZhKWIgDEAAAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgYJCwAAAA==.',
Sk='Skullmonkêy:BAABLgAFFH8NAAIXAAQJfAjuJAAJAQAXAAQJfAjuJAAJAQABLgAFFAUJCwAHAHwLAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snaghelli:BAAALgAECgEJAQABLgAFFAcJGwAkAH0eAA==.Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAABLgAFFH8GAAIcAAEJWxuMOgBVAAAcAAEJWxuMOgBVAAAAAA==.',
So='Sooner:BAACLgAFFH8SAAMXAAQJMx/OTQBWAQAXAAQJMx/OTQBWAQAmAAMJXRSoFwDOAAAuAAQKfxkAAyYABwl7HfEEAPwBACYABgl0IPEEAPwBABcABQkMHPiCAHwBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgIJAgAAAA==.',
Sq='Squeaky:BAAALgAECgcJEgAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.',
Sy='Syrupp:BAAALgAECgkJDgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.Tayn:BAAALgAECgMJBgAAAA==.',
Te='Tealeaf:BAAALgAECgQJBAAAAA==.Temporary:BAAALgAECgIJAgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Thackery:BAAALgADCgMJBAAAAA==.Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
To='Tortus:BAAALgAECgEJAQAAAA==.Toxicrumor:BAAALgAFFAMJAwAAAA==.',
Tr='Triplenine:BAAALgAECgIJAgABLgAFFAkJJAABAJoZAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgQJBQAAAA==.',
Tu='Tucktoo:BAAALgAECgYJCQAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAACLgAFFH8YAAMaAAUJRBA6CQAKAQAaAAUJRBA6CQAKAQAWAAIJRAUNQwBvAAAuAAQKfy8AAxoACQnmFrEWABQCABoACQnmFrEWABQCABYABAlICL9QAMAAAAAA.',
Uw='Uwurailme:BAABLgAECn8VAAQIAAcJNg8KMgDwAAAHAAYJcQxriwBCAQAIAAUJHAoKMgDwAAAGAAIJrRN5HQCGAAAAAA==.',
Va='Valenix:BAACLgAFFH8VAAMfAAQJIwwoBwDxAAAfAAQJIwwoBwDxAAAeAAMJSwpnRwCHAAAuAAQKfx8AAx8ACQlmENdCAPMAAB8ABwlDENdCAPMAAB4ACAnrESxvAMoAAAAA.Valkryi:BAAALgAECgEJAQAAAA==.Varys:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.Vaxîs:BAAALgAECgMJAwAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAAALgAECgkJDwAAAA==.',
Vo='Vo:BAAALgAECgYJEgAAAA==.',
Vu='Vulasity:BAAALgAECgcJBwAAAA==.',
Wa='Warder:BAABLgAECn8gAAIkAAgJwRgmIwDaAQAkAAgJwRgmIwDaAQAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wiigo:BAABLgAFFH8GAAIeAAMJ0g52HACdAAAeAAMJ0g52HACdAAAAAA==.Wincks:BAABLgAECn8hAAQIAAgJGh7PDAByAQAIAAYJIB7PDAByAQAHAAUJoBjnCAAQAQAGAAIJ9x2/BACtAAAAAA==.',
Xa='Xana:BAAALgADCgUJBQABLgAFFAQJCAAaAF8LAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAABLgAECn8nAAICAAkJjxV6AgAtAgACAAkJjxV6AgAtAgAAAA==.Zackman:BAACLgAFFH8fAAIbAAUJwQmoCQARAQAbAAUJwQmoCQARAQAuAAQKf0kAAhsACQlJFeMZADcCABsACQlJFeMZADcCAAAA.',
Zh='Zhimer:BAAALgADCgIJAgAAAA==.',
Zi='Zinagos:BAAALgAFFAIJAgABLgAFFAQJFQAfACMMAA==.',
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
