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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Mage-Fire','DemonHunter-Devourer','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Priest-Shadow','Paladin-Holy','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Monk-Windwalker','Hunter-Survival','Priest-Holy','Warrior-Protection','DeathKnight-Frost',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAUJDQABADAQAA==.',
Ab='Abotou:BAAALgAECgEJAQAAAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgAECgMJAwAAAA==.Allice:BAABLgAECn8fAAMCAAcJwBxfAwA8AgACAAcJaxxfAwA8AgABAAQJoQwFEAGUAAAAAA==.Alsheyra:BAAALgAECgcJCwAAAA==.Altan:BAAALgADCgMJAwAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAFFAIJAgAAAA==.',
An='Anastasija:BAAALgAECgEJAgAAAA==.Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgAECgEJAQAAAA==.',
Ar='Arahwn:BAAALgAECgUJBQAAAA==.Arolden:BAAALgADCgEJAQAAAA==.',
As='Astaru:BAAALgAECgQJBwABLgAECgkJKAABAEAMAA==.',
Au='Aughyst:BAAALgAECgQJBAAAAA==.Augnyxia:BAABLgAECn8tAAQDAAgJJROuJACYAQADAAgJhhGuJACYAQAEAAQJIATiLQB7AAAFAAQJ8Q7rHABmAAAAAA==.Augtism:BAABLgAECn86AAQGAAkJ4CJ9AgCpAgAGAAgJQCJ9AgCpAgAHAAkJPSDkKAA4AgAIAAIJYx8FDwBYAAAAAA==.Augtysm:BAAALgAECgIJBAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgUJDwAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAkJSwAFAD8jAA==.',
Be='Beefquake:BAABLgAECn8jAAIJAAkJ2yDSAADnAgAJAAkJ2yDSAADnAgAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Berafii:BAAALgAECgEJAQAAAA==.Bersh:BAABLgAECn8xAAQKAAkJFR0xBwBdAgAKAAkJFxwxBwBdAgALAAYJuhftQgAnAQAMAAEJAQiMngAyAAAAAA==.',
Bi='Bigmoomoo:BAAALgAECgkJEwAAAA==.Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBwAAAA==.Blasters:BAAALgAECggJCAAAAA==.Bloodjury:BAACLgAFFH8GAAINAAIJdAwGTQB7AAANAAIJdAwGTQB7AAAuAAQKfyEAAw0ACQlcGZlTAM4BAA0ACQlcGZlTAM4BAA4ABAleDFIOAHgAAAAA.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAABLgAECn8VAAIPAAgJpxiVKwD8AQAPAAgJpxiVKwD8AQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Booghur:BAAALgADCgUJBQAAAA==.Boonktown:BAABLgAECn8rAAMBAAkJnw0gYwC4AQABAAkJQA0gYwC4AQAQAAcJuQn5BAB9AQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgYJDgAAAA==.Broken:BAAALgAECgEJBAAAAA==.Bruceleela:BAAALgAECgYJCwABLgAECgcJIQARAH4VAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bushetti:BAABLgAECn8dAAMPAAgJCBVVTABeAQAPAAgJCBVVTABeAQASAAMJmxg/aQB7AAABLgAFFAMJEAAMAHUkAA==.',
Ca='Callmeôp:BAAALgAECgEJAQAAAA==.Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMLAAkJYBElJQDoAQALAAkJYBElJQDoAQAMAAYJDxUgVwBaAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgUJCAAAAA==.Cazisham:BAABLgAECn8mAAMKAAkJSQZFGQA7AQAKAAkJSQZFGQA7AQAMAAEJcgHwSAALAAAAAA==.',
Ce='Cevianne:BAABLgAECn8sAAITAAgJjRMsOADNAQATAAgJjRMsOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chamhealeon:BAAALgAECgIJAgAAAA==.Chanok:BAAALgADCgUJCAAAAA==.Chaoticsaint:BAABLgAECn8XAAIUAAgJEBF2MAAFAQAUAAgJEBF2MAAFAQAAAA==.Chingatumaga:BAAALgAECgMJBgAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Ci='Ciaphis:BAAALgAECgMJAwAAAA==.Cinnabuns:BAAALgADCgMJAQAAAA==.',
Cl='Claros:BAAALgAECggJDQAAAA==.',
Co='Coal:BAABLgAECn8+AAMRAAkJBiT9CAAFAwARAAkJBiT9CAAFAwAVAAcJ5xsdCQDcAQAAAA==.Coalesce:BAAALgADCgQJBAABLgAECgkJPgARAAYkAA==.Coltonater:BAACLgAFFH8IAAIBAAQJ7Ri/JwA3AQABAAQJ7Ri/JwA3AQAuAAQKfz4AAgEACAnuIYElAIYCAAEACAnuIYElAIYCAAAA.Corlieb:BAAALgAECgQJBAAAAA==.Coyo:BAAALgADCgIJAgAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.Curtis:BAAALgAFFAEJAgAAAA==.',
['Cá']='Cáséy:BAACLgAFFH8VAAIBAAQJDh41RABgAQABAAQJDh41RABgAQAuAAQKfyMAAgEACQmeHSg5ADQCAAEACQmeHSg5ADQCAAAA.',
['Cä']='Cäsey:BAAALgAECgYJCgABLgAFFAUJFQABAA4eAA==.',
Da='Dampening:BAAALgAECgMJAwABLgAECgUJBQAWAAAAAA==.Danbi:BAACLgAFFH8PAAQFAAUJlAi8BACbAAADAAQJzAfQPQDQAAAFAAMJLAa8BACbAAAEAAQJuAtrEwBzAAAuAAQKfzUABAQACQmUF+wNAPABAAQACAlEF+wNAPABAAMACQn2E24dAOsBAAUABAm2D9gXAJ0AAAAA.Darkshroud:BAAALgAECgIJAgAAAA==.Datbi:BAAALgAECgQJBAAAAA==.',
De='Deathdeamon:BAAALgAECgEJAQAAAA==.Deathdylan:BAACLgAFFH8aAAIXAAYJpQtUEADuAAAXAAYJpQtUEADuAAAuAAQKfzIAAhcACQknHzEIAJQCABcACQknHzEIAJQCAAAA.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAABLgAECn8hAAIRAAcJfhVgYwBhAQARAAcJfhVgYwBhAQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Delice:BAAALgAECgYJDAAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demiev:BAAALgAECgEJAQAAAA==.Demonware:BAAALgAECgEJAQAAAA==.Demítríus:BAAALgADCgcJJQAAAA==.Dethh:BAAALgADCgYJCQAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Di='Diddymaxx:BAAALgAECgEJAQAAAA==.Didibehindu:BAAALgADCgQJBgAAAA==.Dionarose:BAAALgADCgYJBgAAAA==.Dionos:BAAALgAECgEJAQAAAA==.Divineflava:BAAALgAFFAEJAQAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Dragonlord:BAAALgAECgYJBgAAAA==.Draugr:BAAALgAECgMJAwAAAA==.Dravyn:BAABLgAECn8oAAIBAAkJQAzEaACrAQABAAkJQAzEaACrAQAAAA==.Draximus:BAAALgAECgEJAQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxNNQCeAgABAAgJmhxNNQCeAgAAAA==.Druqz:BAACLgAFFH8WAAIBAAUJeQRudwDrAAABAAUJeQRudwDrAAAuAAQKfxkAAgEACAmeChqdAEABAAEACAmeChqdAEABAAAA.Druski:BAAALgAECgQJBwAAAA==.Drævn:BAABLgAECn9NAAMQAAcJrBnnAQALAQABAAcJrxQsfQB9AQAQAAYJdBrnAQALAQAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8dAAMRAAgJQRu3FQADAgARAAgJQRu3FQADAgAVAAIJQgumDQBuAAAuAAQKfykAAhEACQlvJH4GACQDABEACQlvJH4GACQDAAAA.Duragon:BAABLgAECn8WAAIYAAkJBwdsDwDaAAAYAAkJBwdsDwDaAAAAAA==.Durkagon:BAAALgAECgMJBAAAAA==.',
Dw='Dwimbear:BAAALgAECgEJAQAAAA==.Dwimhoof:BAAALgAECgEJBwAAAA==.',
Ed='Ediconegoen:BAAALgAECgEJAgAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAACLgAFFH8XAAIZAAQJWx+oEAA3AQAZAAQJWx+oEAA3AQAuAAQKfxsAAhkACQkAH/sPAD8CABkACQkAH/sPAD8CAAAA.',
Em='Emancipation:BAAALgAECgYJDgAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJ0gtCbwCcAQABAAkJ0gtCbwCcAQACAAIJOgZTGQBNAAAAAA==.Endofdays:BAABLgAFFH8GAAIaAAMJJA2cpwDMAAAaAAMJJA2cpwDMAAAAAA==.Enro:BAACLgAFFH8TAAIUAAYJWw86CwD5AAAUAAYJWw86CwD5AAAuAAQKf0IAAxQACQnrH4oFAOcCABQACQnrH4oFAOcCABEABAmqB361AJ0AAAAA.',
Er='Erovia:BAACLgAFFH8LAAITAAMJ9QRjcQC8AAATAAMJ9QRjcQC8AAAuAAQKfyMAAhMACQlXCYKAAD4BABMACQlXCYKAAD4BAAAA.',
Es='Esclipse:BAAALgAECgcJCgAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAABLgAFFH8GAAIYAAMJoQ1LHADGAAAYAAMJoQ1LHADGAAAAAA==.',
Fe='Felony:BAABLgAECn8zAAIUAAkJGCS4AwAYAwAUAAkJGCS4AwAYAwAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fh='Fhenix:BAAALgAECgEJAQAAAA==.',
Fl='Flavaflare:BAAALgAECgUJCAABLgAECggJGwASADEdAA==.Flavah:BAABLgAECn8bAAISAAgJMR2YHAAdAgASAAgJMR2YHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8wAAMaAAkJqBP2WgC2AQAaAAkJqBP2WgC2AQAXAAcJDQRAPQCbAAAAAA==.Flower:BAABLgAFFH8FAAITAAMJRxbTWQDyAAATAAMJRxbTWQDyAAAAAA==.',
Fo='Foodex:BAAALgAECgcJEQAAAA==.Fourleaf:BAACLgAFFH8eAAIbAAYJ5BizCAAPAQAbAAYJ5BizCAAPAQAuAAQKfzwAAhsACQlCIe0BAOoCABsACQlCIe0BAOoCAAAA.',
Fr='Frydayx:BAAALgAECgMJBAAAAA==.',
Fu='Furlock:BAAALgAECgIJAgAAAA==.Furral:BAACLgAFFH8MAAIcAAMJRxnMDADqAAAcAAMJRxnMDADqAAAuAAQKfyEAAhwACQk3HxIEAMYCABwACQk3HxIEAMYCAAAA.Furretc:BAAALgAECgMJBAAAAA==.',
Ga='Gaeth:BAABLgAECn8jAAIPAAkJUBAIQgCZAQAPAAkJUBAIQgCZAQAAAA==.',
Ge='Gelys:BAAALgAECgQJBAABLgAFFAQJCAAdAF8LAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Gl='Gleg:BAABLgAFFH8QAAIMAAMJdSRtFQAhAQAMAAMJdSRtFQAhAQAAAA==.Glibby:BAAALgAECgMJAwABLgAFFAQJCAAdAF8LAA==.',
Gn='Gnomeagedon:BAAALgAFFAMJAwAAAA==.',
Go='Goldielocks:BAAALgAECgMJAwAAAA==.Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Granddiddy:BAAALgAECgEJAgAAAA==.Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8WAAIRAAcJwxeSXAByAQARAAcJwxeSXAByAQAAAA==.Grimthedread:BAAALgADCgYJBgAAAA==.Grimvess:BAAALgAECggJCQAAAA==.Griselden:BAABLgAFFH8HAAIRAAIJZBKOSgBNAAARAAIJZBKOSgBNAAAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Hamburgler:BAAALgADCgYJBgABLgAECgkJIAATAKchAA==.Hammerobby:BAAALgAECgYJCgABLgAECgcJIQARAH4VAA==.Handlebar:BAAALgAECgUJCgABLgAECgcJIQARAH4VAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8gAAINAAkJERGEYQCtAQANAAkJERGEYQCtAQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.Holyshock:BAABLgAECn8dAAMNAAcJIgZwFAGgAAANAAYJmgRwFAGgAAAeAAYJEgOJFwBfAAAAAA==.',
Hu='Hungsu:BAAALgAECgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgYJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Id='Idris:BAAALgADCgYJCQAAAA==.',
Il='Ilkkarid:BAABLgAECn8bAAMfAAgJIBISHAC2AQAfAAgJ/BESHAC2AQAgAAYJBgp3EgDiAAAAAA==.Illidank:BAAALgADCgUJBQAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAABLgAECn8fAAIdAAgJ1Q/wCAA7AQAdAAgJ1Q/wCAA7AQAAAA==.',
Is='Ishpoo:BAABLgAECn8vAAINAAkJ0xC8VgDHAQANAAkJ0xC8VgDHAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jecht:BAAALgADCgEJAQAAAA==.Jelqer:BAABLgAECn8VAAMFAAYJsCCaEgC4AQAFAAYJsCCaEgC4AQADAAUJZBQXMABFAQAAAA==.Jenila:BAEALgAECgEJAgABLgAECgcJDAAWAAAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8qAAIPAAkJOR3uFACiAgAPAAkJOR3uFACiAgAAAA==.Jlawzzs:BAAALgAECgMJAgAAAA==.',
Jo='Job:BAACLgAFFH83AAMUAAkJGSAzAgBAAgARAAkJ+R0/CwBqAgAUAAcJhyAzAgBAAgAuAAQKf0QAAxEACQnUJbYEADsDABEACQnUJLYEADsDABQABwkgI5gFAIQBAAAA.',
Ju='Juanweasley:BAABLgAFFH8GAAIHAAMJlwgcPACgAAAHAAMJlwgcPACgAAAAAA==.Judoriel:BAAALgAECgcJDAAAAA==.Julz:BAAALgADCgUJBQAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8oAAITAAkJuRoiHwBsAgATAAkJuRoiHwBsAgAAAA==.Kaimin:BAABLgAECn9ZAAIaAAkJ7yFHAwDCAgAaAAkJ7yFHAwDCAgAAAA==.Kaledor:BAAALgADCgEJAQAAAA==.Karthas:BAAALgAECgIJBQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAWAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8xAAMZAAkJdRhLEABsAgAZAAkJdRhLEABsAgAdAAMJFAPIVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8yAAMMAAkJ8xA0PwCxAQAMAAkJ8xA0PwCxAQAKAAQJfAo0LACXAAAAAA==.Khonsu:BAAALgAECgcJDAAAAA==.',
Ki='Kiba:BAABLgAECn8kAAMhAAcJwg8qRABbAQAhAAcJwg8qRABbAQAiAAQJpgpOWgCqAAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAABLgAECn8gAAIMAAgJ2Rj5IwA3AgAMAAgJ2Rj5IwA3AgAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Kowadin:BAAALgADCgEJAQAAAA==.Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8lAAIOAAkJkQsiGwA/AQAOAAkJkQsiGwA/AQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAACLgAFFH8iAAIhAAcJpxKrDgCbAQAhAAcJpxKrDgCbAQAuAAQKfzwAAyEACQkQIfMGADIDACEACQkQIfMGADIDACIAAwl3Dg1mAIoAAAAA.',
La='Larenta:BAAALgAECgYJCwAAAA==.Larethiana:BAACLgAFFH8FAAIPAAUJhgoSLQABAQAPAAUJhgoSLQABAQAuAAQKfxQAAw8ACAnpFKJMAHEBAA8ABwmMFaJMAHEBABIABgn1FgA1AGoBAAAA.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Letloose:BAAALgADCgEJAQAAAA==.Lexibelle:BAABLgAECn8UAAMeAAYJXQMfagDSAAAeAAYJXQMfagDSAAANAAQJRQGAIQFbAAAAAA==.',
Li='Lightbright:BAACLgAFFH8VAAINAAUJFCCWLABcAQANAAUJFCCWLABcAQAuAAQKfyMAAg0ACQlVJJcHAFoDAA0ACQlVJJcHAFoDAAAA.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAABLgAECn8yAAIdAAcJlB4XFgAaAgAdAAcJlB4XFgAaAgAAAA==.Linnasha:BAABLgAECn8tAAIPAAkJLhfUJAAlAgAPAAkJLhfUJAAlAgAAAA==.Litlefoot:BAABLgAECn8UAAILAAkJUhDyKgCbAQALAAkJUhDyKgCbAQAAAA==.',
Lo='Lornzap:BAABLgAFFH8NAAILAAMJNBsWKgDtAAALAAMJNBsWKgDtAAAAAA==.Lostwanderer:BAABLgAECn8dAAMhAAgJBRjbHQAqAgAhAAgJBRjbHQAqAgAiAAIJrAV/jwBBAAAAAA==.Lot:BAAALgAFFAEJAQABLgAFFAkJNwAUABkgAA==.Lowcowlorie:BAAALgAECgEJAQAAAA==.',
['Lú']='Lúthiien:BAAALgAECgIJAgAAAA==.',
Ma='Machine:BAACLgAFFH8LAAIjAAMJuheZDwCkAAAjAAMJuheZDwCkAAAuAAQKfx8AAiMACQlfElUSABYCACMACQlfElUSABYCAAAA.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maidenlilith:BAAALgADCgEJAQAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8xAAIUAAkJ3xYlEgAKAgAUAAkJ3xYlEgAKAgAAAA==.Manamontana:BAAALgAECgQJBAAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Mannanan:BAAALgAECgcJDgAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meatrocketxd:BAAALgAECgcJAQAAAA==.Meddicare:BAAALgADCgUJBQAAAA==.Metalicana:BAAALgADCgEJAQAAAA==.',
Mi='Mindra:BAABLgAECn8xAAQTAAkJziC1EgC8AgATAAkJziC1EgC8AgAjAAIJPRAaTwB0AAAbAAEJhwzvPQAuAAAAAA==.Minyaura:BAAALgADCgQJBAAAAA==.Minyholy:BAAALgAECgQJBAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Mirañda:BAAALgADCgEJAQAAAA==.Miridian:BAAALgAECgcJDwAAAA==.Miromoney:BAAALgADCgUJBQAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgAECgYJEgAAAA==.Moobundo:BAAALgADCgEJAQAAAA==.Moogician:BAAALgAECgIJBgABLgAECgkJIAATAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonmama:BAAALgAECgEJAQAAAA==.Moonsïnd:BAABLgAECn8rAAMPAAkJZA1wQACQAQAPAAkJZA1wQACQAQAcAAIJehJlOgBvAAAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgAECgcJDwAAAA==.Morgrin:BAAALgAECgQJBgAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8iAAIfAAgJAhP1IQCGAQAfAAgJAhP1IQCGAQAAAA==.',
My='Mydira:BAAALgAECgkJDAAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAACLgAFFH8GAAIPAAMJdQYfTQCKAAAPAAMJdQYfTQCKAAAuAAQKfxkABA8ACQmnGK8VAJsCAA8ACQmnGK8VAJsCAAkAAgn4BxJvADoAABIAAQmXCs6SACwAAAAA.Nalthexon:BAAALgAECgYJBgABLgAFFAMJBgAPAHUGAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Necropox:BAAALgAECgcJCQAAAA==.Negativeone:BAAALgADCgYJAgAAAA==.Neko:BAABLgAFFH8FAAIhAAMJ8wzJLAB3AAAhAAMJ8wzJLAB3AAAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAeANscAA==.',
Ni='Niavanith:BAAALgAECgYJEgAAAA==.Nicotine:BAAALgAECgEJAQAAAA==.Nights:BAAALgAFFAEJAQABLgAFFAMJCwAjALoXAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAACLgAFFH8gAAMFAAYJJBrkAgBSAQAFAAYJJBrkAgBSAQADAAQJrQ/vMgD2AAAuAAQKf0QAAwUACQnUI8oAACcDAAUACQnUI8oAACcDAAQABQnUFfMYAEUBAAAA.Nizo:BAABLgAECn86AAIPAAkJlx+XDQDtAgAPAAkJlx+XDQDtAgAAAA==.',
Nj='Njal:BAAALgAECgUJBQAAAA==.',
No='Noblitz:BAACLgAFFH8IAAMdAAQJXwt5HgD+AAAdAAQJXwt5HgD+AAAkAAEJNxU/NgA6AAAuAAQKfyAABB0ACQlWGB8QAFsCAB0ACQlWGB8QAFsCACQABgnRGdcmAI4BABkAAQkIHgIeAFQAAAAA.Novastrike:BAABLgAECn8mAAMMAAgJohdNQwCgAQAMAAgJohdNQwCgAQALAAgJ3wtTWwDSAAAAAA==.',
Ny='Nymphia:BAAALgAECgMJAwAAAA==.Nyrif:BAACLgAFFH8XAAIXAAQJLBsDFwAxAQAXAAQJLBsDFwAxAQAuAAQKfyIAAhcACQnzGuMQAP0BABcACQnzGuMQAP0BAAAA.',
Ob='Obsidion:BAAALgAECgQJBwAAAA==.',
Oj='Ojon:BAAALgADCgYJBgAAAA==.Ojoon:BAABLgAECn8eAAIBAAcJsxA4GQARAQABAAcJsxA4GQARAQAAAA==.',
Om='Omnisllash:BAACLgAFFH8PAAIBAAQJ2RGfLAAcAQABAAQJ2RGfLAAcAQAuAAQKfxwAAgEACQkhGecQAF0BAAEACQkhGecQAF0BAAAA.',
Or='Orisana:BAACLgAFFH8TAAMjAAQJoxtfDwBJAQAjAAQJoxtfDwBJAQATAAIJNxWQiQCLAAAuAAQKf1EABCMACQlCIaIFAMsCABsACQnAGnkMAOUCACMACQneH6IFAMsCABMABQmMGY2BADsBAAAA.',
Pa='Palatrin:BAAALgADCggJDwAAAA==.Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8YAAMEAAUJAQwLGAAVAQAEAAUJAQwLGAAVAQADAAEJlwjiZgA4AAAAAA==.',
Ph='Phoenìx:BAAALgAECgEJAgAAAA==.Phyter:BAAALgAECgIJBQAAAA==.',
Pi='Pillin:BAABLgAECn8hAAMgAAkJ6hvZAADIAQAgAAkJyxvZAADIAQAfAAMJ+BWTDQCZAAAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8hAAMYAAkJcB0zFwA0AgAYAAkJcB0zFwA0AgAlAAEJ7AiGUgA0AAAAAA==.Powerwordmoo:BAAALgAECgEJAQABLgAECgkJIAATAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Prina:BAAALgAECgMJAwAAAA==.Provi:BAAALgAECggJDAAAAA==.',
Ps='Psyffe:BAAALgAECgUJCgAAAA==.Psyrge:BAAALgAECgYJBgAAAA==.',
['Pä']='Päïn:BAAALgAECgcJCQAAAA==.',
Qu='Queue:BAABLgAECn9EAAIXAAkJIBD6GgCFAQAXAAkJIBD6GgCFAQAAAA==.',
Ra='Razorsight:BAAALgAECgEJAQAAAA==.',
Re='Rebeccayaros:BAAALgAECgUJDwAAAA==.Redle:BAABLgAECn8fAAINAAgJdA10JwC7AAANAAgJdA10JwC7AAAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAECLgAFFH8gAAQjAAYJPhhdBABzAQAjAAYJPhhdBABzAQAbAAEJtgcQKgBIAAATAAEJFAPtrwA8AAAuAAQKfzgAAyMACQnGIH8GALkCACMACQkFIH8GALkCABsACAkSFgAeADYCAAAA.',
Ro='Rokkitok:BAAALgAECgkJEgAAAA==.Roku:BAAALgAECgMJAwAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.Rottenbeef:BAAALgAECgQJCAAAAA==.',
Ru='Rulnic:BAAALgAECgEJAwAAAA==.',
['Rà']='Ràwrshàk:BAAALgAECgYJDQAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8nAAITAAkJqBq4KgAzAgATAAkJqBq4KgAzAgAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgABLgAFFAEJAQAWAAAAAA==.',
Sa='Sacredbeef:BAAALgAECgEJAQAAAA==.Sanyo:BAAALgADCgEJAQAAAA==.Sarahjan:BAAALgAECgIJAgAAAA==.Sathen:BAAALgADCgEJAQAAAA==.Sayo:BAAALgAECgUJBQAAAA==.',
Sc='Scylar:BAAALgAECgEJAQAAAA==.',
Se='Sea:BAACLgAFFH8iAAIMAAYJ6h1HDAARAgAMAAYJ6h1HDAARAgAuAAQKfyMAAgwACQmyIOYBAG4DAAwACQmyIOYBAG4DAAAA.Seliph:BAAALgAECgQJBAAAAA==.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgkJDwAAAA==.Shadowrose:BAABLgAECn8xAAMcAAkJahkuDAD2AQAcAAgJuhcuDAD2AQAPAAQJhQ3OegDHAAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAABLgAECn8aAAIHAAkJ4hV6NwD7AQAHAAkJ4hV6NwD7AQAAAA==.Shamamama:BAAALgADCgEJAQAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAwAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAWAAAAAA==.Sheneneh:BAAALgADCgcJDgAAAA==.Shiemi:BAAALgAECgcJBgAAAA==.Shootingbo:BAAALgAECgEJAQAAAA==.Shunsui:BAACLgAFFH8LAAIHAAUJfAuuXwAIAQAHAAUJfAuuXwAIAQAuAAQKfzAAAwcACQmoG5sdAHMCAAcACQmoG5sdAHMCAAgAAQkAACRvADcAAAAA.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Silentomen:BAAALgADCgkJCQAAAA==.Siley:BAABLgAECn8YAAIeAAkJ2xzDFABrAgAeAAkJ2xzDFABrAgAAAA==.Sinnister:BAABLgAFFH8GAAIRAAQJZhKVMQCwAAARAAQJZhKVMQCwAAAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgYJCwAAAA==.',
Sk='Skinnypete:BAAALgAECgEJAQAAAA==.Skullmonkêy:BAABLgAFFH8NAAIaAAQJfAgRPADqAAAaAAQJfAgRPADqAAABLgAFFAUJCwAHAHwLAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slothcountry:BAAALgADCgkJAgAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snaghelli:BAAALgAECgEJAQABLgAFFAcJGwAYAH0eAA==.Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAABLgAFFH8GAAIfAAEJWxuMOgBVAAAfAAEJWxuMOgBVAAAAAA==.',
So='Sooner:BAACLgAFFH8SAAMaAAQJMx/OTQBWAQAaAAQJMx/OTQBWAQAmAAMJXRSoFwDOAAAuAAQKfxkAAyYABwl7HfEEAPwBACYABgl0IPEEAPwBABoABQkMHPiCAHwBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgIJAgAAAA==.',
Sp='Spaztacular:BAAALgAECgQJBAAAAA==.',
Sq='Squeaky:BAAALgAECgcJEgAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.Stumpy:BAAALgADCgMJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgkJAQAAAA==.Sunraku:BAAALgADCgIJAgAAAA==.',
Sy='Syrupp:BAAALgAECgkJDgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.Tayn:BAAALgAECgUJCAAAAA==.',
Te='Tealeaf:BAAALgAECgQJBAAAAA==.Temporary:BAAALgAECgIJAgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Thackery:BAAALgADCgMJBAAAAA==.Theblackdk:BAAALgADCgQJAwAAAA==.Thinsheets:BAAALgADCgcJCQABLgAFFAIJBgANAHQMAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
To='Tortus:BAAALgAECgEJAQAAAA==.Toxicrumor:BAAALgAFFAMJAwAAAA==.',
Tr='Trillidan:BAAALgAECgEJAQAAAA==.Triplenine:BAAALgAECgIJAgABLgAFFAkJNwABANMdAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgQJBQAAAA==.',
Tu='Tucktoo:BAAALgAECgYJCQAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAACLgAFFH8gAAMdAAcJWROgBgCzAQAdAAcJWROgBgCzAQAZAAIJRAUNQwBvAAAuAAQKfy8AAx0ACQnmFrEWABQCAB0ACQnmFrEWABQCABkABAlICL9QAMAAAAAA.Unholysmurfh:BAAALgAFFAEJAQAAAA==.',
Uw='Uwurailme:BAABLgAECn8VAAQIAAcJNg8KMgDwAAAHAAYJcQxriwBCAQAIAAUJHAoKMgDwAAAGAAIJrRN5HQCGAAAAAA==.',
Va='Vagãbon:BAAALgAFFAIJBAABLgAFFAMJCwAjALoXAA==.Valenix:BAACLgAFFH8VAAMiAAQJIwyBDADiAAAiAAQJIwyBDADiAAAhAAMJSwpnRwCHAAAuAAQKfx8AAyIACQlmENdCAPMAACIABwlDENdCAPMAACEACAnrESxvAMoAAAAA.Valkryi:BAAALgAECgEJAQAAAA==.Varys:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.Vaxîs:BAAALgAECgMJAwAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAABLgAECn8hAAIFAAkJ8h5mAADDAgAFAAkJ8h5mAADDAgAAAA==.',
Vi='Violencé:BAAALgAECgYJBgAAAA==.',
Vo='Vo:BAAALgAECgYJEgAAAA==.',
Vu='Vulasity:BAAALgAECgcJBwAAAA==.',
['Vâ']='Vâlenix:BAAALgAFFAIJAgAAAA==.',
Wa='Warder:BAABLgAECn8hAAIYAAkJFxgmIwDaAQAYAAkJFxgmIwDaAQAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wiigo:BAABLgAFFH8GAAIhAAMJ0g6/JgCVAAAhAAMJ0g6/JgCVAAAAAA==.Wincks:BAABLgAECn8pAAQIAAkJ+BzPDAByAQAIAAYJIB7PDAByAQAHAAYJCBjjCgBTAQAGAAMJth4vBQAKAQAAAA==.Winnër:BAAALgAECgEJAQAAAA==.',
Xa='Xana:BAAALgADCgUJBQABLgAFFAQJCAAdAF8LAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAABLgAECn8oAAICAAkJxxV6AgAtAgACAAkJxxV6AgAtAgAAAA==.Zackman:BAACLgAFFH8hAAIeAAYJFAtHDABEAQAeAAYJFAtHDABEAQAuAAQKf0wAAh4ACQm9FeMZADcCAB4ACQm9FeMZADcCAAAA.',
Zh='Zhimer:BAAALgADCgIJAgAAAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.Zombie:BAABLgAFFH8JAAIaAAUJBBTYKAAwAQAaAAUJBBTYKAAwAQAAAA==.Zosos:BAAALgAECgEJAgAAAA==.',
Zu='Zulrea:BAAALgAECgcJCgAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJCwAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAFFAEJAQAWAAAAAA==.',
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
