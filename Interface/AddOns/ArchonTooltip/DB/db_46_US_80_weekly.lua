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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Druid-Restoration','Mage-Fire','DemonHunter-Devourer','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','DeathKnight-Blood','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Priest-Shadow','Paladin-Holy','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Hunter-Survival','Priest-Holy','Warrior-Fury','Warrior-Protection','DeathKnight-Frost',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAUJDQABADAQAA==.',
Ab='Abotou:BAAALgAECgEJAQAAAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgAECgMJAwAAAA==.Allice:BAABLgAECn8fAAMCAAcJwBxfAwA8AgACAAcJaxxfAwA8AgABAAQJoQwFEAGUAAAAAA==.Alsheyra:BAAALgAECgcJCwAAAA==.Altan:BAAALgADCgMJAwAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAFFAIJAgAAAA==.',
An='Anastasija:BAAALgAECgEJAgAAAA==.Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgcJEAAAAA==.',
Ar='Arahwn:BAAALgAECgUJBQAAAA==.Arolden:BAAALgADCgEJAQAAAA==.',
As='Astaru:BAAALgAECgQJBwABLgAECgkJKAABAEAMAA==.',
Au='Aughyst:BAAALgAECgQJBAAAAA==.Augnyxia:BAABLgAECn8tAAQDAAgJJROuJACYAQADAAgJhhGuJACYAQAEAAQJIATiLQB7AAAFAAQJ8Q7rHABmAAAAAA==.Augtism:BAABLgAECn85AAQGAAkJ4CJ9AgCpAgAGAAgJQCJ9AgCpAgAHAAkJPSDkKAA4AgAIAAIJYx+XCQBZAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgUJDAAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAkJQQAFAPAiAA==.',
Be='Beefquake:BAABLgAECn8YAAIJAAkJXR4aAQBQAgAJAAkJXR4aAQBQAgAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Berafii:BAAALgAECgEJAQAAAA==.Bersh:BAABLgAECn8xAAQKAAkJFR0xBwBdAgAKAAkJFxwxBwBdAgALAAYJuhftQgAnAQAMAAEJAQiMngAyAAAAAA==.',
Bi='Bigmoomoo:BAAALgAECgkJEwAAAA==.Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBwAAAA==.Blasters:BAAALgAECgYJBgAAAA==.Bloodjury:BAACLgAFFH8FAAINAAIJdAzjPACGAAANAAIJdAzjPACGAAAuAAQKfx0AAg0ACQlcGZlTAM4BAA0ACQlcGZlTAM4BAAAA.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAABLgAECn8VAAIOAAgJpxiVKwD8AQAOAAgJpxiVKwD8AQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Booghur:BAAALgADCgUJBQAAAA==.Boonktown:BAABLgAECn8rAAMBAAkJnw0gYwC4AQABAAkJQA0gYwC4AQAPAAcJuQn5BAB9AQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgYJDgAAAA==.Broken:BAAALgAECgEJBAAAAA==.Bruceleela:BAAALgAECgYJCwABLgAECgcJIQAQAH4VAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bumslapr:BAAALgAECgEJAQAAAA==.Bushetti:BAABLgAECn8dAAMOAAgJCBVVTABeAQAOAAgJCBVVTABeAQARAAMJmxg/aQB7AAAAAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMLAAkJYBElJQDoAQALAAkJYBElJQDoAQAMAAYJDxUgVwBaAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgUJCAAAAA==.Cazisham:BAABLgAECn8lAAMKAAkJSQZFGQA7AQAKAAkJSQZFGQA7AQAMAAEJcgEPMwAMAAAAAA==.',
Ce='Cevianne:BAABLgAECn8sAAISAAgJjRMsOADNAQASAAgJjRMsOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chamhealeon:BAAALgAECgIJAgAAAA==.Chanok:BAAALgADCgUJCAAAAA==.Chaoticsaint:BAABLgAECn8XAAITAAgJEBF2MAAFAQATAAgJEBF2MAAFAQAAAA==.Chingatumaga:BAAALgADCgcJCgAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Ci='Cinnabuns:BAAALgADCgMJAQAAAA==.',
Cl='Claros:BAAALgAECggJDQAAAA==.',
Co='Coal:BAABLgAECn8+AAMQAAkJBiT9CAAFAwAQAAkJBiT9CAAFAwAUAAcJ5xsdCQDcAQAAAA==.Coalesce:BAAALgADCgQJBAABLgAECgkJPgAQAAYkAA==.Coltonater:BAACLgAFFH8FAAIBAAIJ9BbYQQCZAAABAAIJ9BbYQQCZAAAuAAQKfz4AAgEACAnuIYElAIYCAAEACAnuIYElAIYCAAAA.Corlieb:BAAALgAECgQJBAAAAA==.Coyo:BAAALgADCgIJAgAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.Curtis:BAAALgAFFAEJAgAAAA==.',
['Cá']='Cáséy:BAACLgAFFH8VAAIBAAQJDh41RABgAQABAAQJDh41RABgAQAuAAQKfyMAAgEACQmeHSg5ADQCAAEACQmeHSg5ADQCAAAA.',
['Cä']='Cäsey:BAAALgAECgYJCgABLgAFFAUJFQABAA4eAA==.',
Da='Daktari:BAAALgAECgQJBAABLgAECgkJOgAOAJcfAA==.Dampening:BAAALgAECgMJAwABLgAECgUJBQAVAAAAAA==.Danbi:BAACLgAFFH8PAAQFAAUJlAglAwCkAAADAAQJzAfQPQDQAAAFAAMJLAYlAwCkAAAEAAQJuAuPDgB+AAAuAAQKfzUABAQACQmUF+wNAPABAAQACAlEF+wNAPABAAMACQn2E24dAOsBAAUABAm2D9gXAJ0AAAAA.Darkshroud:BAAALgAECgIJAgAAAA==.Daugy:BAAALgAECgIJBAAAAA==.',
De='Deathdeamon:BAAALgAECgEJAQAAAA==.Deathdylan:BAACLgAFFH8ZAAIWAAUJFg1QDgDRAAAWAAUJFg1QDgDRAAAuAAQKfzIAAhYACQknHzEIAJQCABYACQknHzEIAJQCAAAA.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAABLgAECn8hAAIQAAcJfhVgYwBhAQAQAAcJfhVgYwBhAQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Delice:BAAALgAECgYJBwAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demiev:BAAALgAECgEJAQAAAA==.Demonware:BAAALgAECgEJAQAAAA==.Demítríus:BAAALgADCgYJEwAAAA==.Destroya:BAAALgADCgMJBQAAAA==.Dethh:BAAALgADCgYJCQAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Di='Dionarose:BAAALgADCgYJBgAAAA==.Dionos:BAAALgAECgEJAQAAAA==.Divineflava:BAAALgAECgIJAQAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Dragonlord:BAAALgAECgYJBgAAAA==.Draugr:BAAALgAECgMJAwAAAA==.Dravyn:BAABLgAECn8oAAIBAAkJQAzEaACrAQABAAkJQAzEaACrAQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxNNQCeAgABAAgJmhxNNQCeAgAAAA==.Druqz:BAACLgAFFH8WAAIBAAUJeQRudwDrAAABAAUJeQRudwDrAAAuAAQKfxkAAgEACAmeChqdAEABAAEACAmeChqdAEABAAAA.Druski:BAAALgAECgMJAwAAAA==.Drævn:BAABLgAECn9HAAMPAAcJZRjiBQBmAQABAAcJrxQsfQB9AQAPAAYJ7BjiBQBmAQAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8dAAMQAAgJQRu3FQADAgAQAAgJQRu3FQADAgAUAAIJQgumDQBuAAAuAAQKfykAAhAACQlvJH4GACQDABAACQlvJH4GACQDAAAA.Duragon:BAAALgAECggJEwAAAA==.',
Dw='Dwimbear:BAAALgAECgEJAQAAAA==.Dwimhoof:BAAALgAECgEJBwAAAA==.',
Ed='Ediconegoen:BAAALgAECgEJAgAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAACLgAFFH8XAAIXAAQJWx+MDABFAQAXAAQJWx+MDABFAQAuAAQKfxsAAhcACQkAH/sPAD8CABcACQkAH/sPAD8CAAAA.',
Em='Emancipation:BAAALgAECgYJDgAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJ0gtCbwCcAQABAAkJ0gtCbwCcAQACAAIJOgZTGQBNAAAAAA==.Endofdays:BAABLgAFFH8GAAIYAAMJJA2cpwDMAAAYAAMJJA2cpwDMAAAAAA==.Enro:BAACLgAFFH8SAAITAAUJSQ+8EgAOAQATAAUJSQ+8EgAOAQAuAAQKf0IAAxMACQnrH4oFAOcCABMACQnrH4oFAOcCABAABAmqB361AJ0AAAAA.',
Er='Erovia:BAACLgAFFH8LAAISAAMJ9QSIRABwAAASAAMJ9QSIRABwAAAuAAQKfyMAAhIACQlXCYKAAD4BABIACQlXCYKAAD4BAAAA.',
Es='Esclipse:BAAALgAECgcJCgAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgAFFAMJBAAAAA==.',
Fe='Felony:BAABLgAECn8zAAITAAkJGCS4AwAYAwATAAkJGCS4AwAYAwAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavaflare:BAAALgAECgEJAQABLgAECggJGwARADEdAA==.Flavah:BAABLgAECn8bAAIRAAgJMR2YHAAdAgARAAgJMR2YHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8wAAMYAAkJqBP2WgC2AQAYAAkJqBP2WgC2AQAWAAcJDQRAPQCbAAAAAA==.Flower:BAABLgAFFH8FAAISAAMJRxbTWQDyAAASAAMJRxbTWQDyAAAAAA==.',
Fo='Foodex:BAAALgAECgcJEQAAAA==.Fourleaf:BAACLgAFFH8dAAIZAAUJMxs1EQBQAQAZAAUJMxs1EQBQAQAuAAQKfzwAAhkACQlCIe0BAOoCABkACQlCIe0BAOoCAAAA.',
Fr='Frydayx:BAAALgAECgMJBAAAAA==.',
Fu='Furral:BAACLgAFFH8MAAIaAAMJRxnMDADqAAAaAAMJRxnMDADqAAAuAAQKfyEAAhoACQk3HxIEAMYCABoACQk3HxIEAMYCAAAA.Furretc:BAAALgAECgMJBAAAAA==.',
Ga='Gaeth:BAABLgAECn8jAAIOAAkJUBAIQgCZAQAOAAkJUBAIQgCZAQAAAA==.',
Ge='Gelys:BAAALgAECgQJBAABLgAFFAQJCAAbAF8LAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Gl='Gleg:BAABLgAFFH8QAAIMAAMJdSR0DwAvAQAMAAMJdSR0DwAvAQAAAA==.Glibby:BAAALgAECgMJAwABLgAFFAQJCAAbAF8LAA==.',
Gn='Gnomeagedon:BAAALgAFFAMJAwAAAA==.',
Go='Goldielocks:BAAALgAECgMJAwAAAA==.Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Granddiddy:BAAALgADCgMJBQAAAA==.Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8WAAIQAAcJwxeSXAByAQAQAAcJwxeSXAByAQAAAA==.Grimthedread:BAAALgADCgYJBgAAAA==.Grimvess:BAAALgAECggJCQAAAA==.Griselden:BAABLgAFFH8GAAIQAAIJeQ3eiABwAAAQAAIJeQ3eiABwAAAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Hamburgler:BAAALgADCgYJBgABLgAECgkJIAASAKchAA==.Hammerobby:BAAALgAECgYJCgABLgAECgcJIQAQAH4VAA==.Handlebar:BAAALgAECgUJCgABLgAECgcJIQAQAH4VAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAFFAEJAQAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8gAAINAAkJERGEYQCtAQANAAkJERGEYQCtAQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.Holyshock:BAABLgAECn8dAAMNAAcJIgZwFAGgAAANAAYJmgRwFAGgAAAcAAYJEgP1DgBfAAAAAA==.',
Hu='Hungsu:BAAALgAECgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgYJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Id='Idris:BAAALgADCgYJCQAAAA==.',
Il='Ilkkarid:BAABLgAECn8bAAMdAAgJIBISHAC2AQAdAAgJ/BESHAC2AQAeAAYJBgp3EgDiAAAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAABLgAECn8dAAIbAAcJeg3zCADhAAAbAAcJeg3zCADhAAAAAA==.',
Is='Ishpoo:BAABLgAECn8vAAINAAkJ0xC8VgDHAQANAAkJ0xC8VgDHAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jecht:BAAALgADCgEJAQAAAA==.Jelqer:BAABLgAECn8VAAMFAAYJsCCaEgC4AQAFAAYJsCCaEgC4AQADAAUJZBQXMABFAQAAAA==.Jenila:BAEALgAECgEJAgABLgAECgcJDAAVAAAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8qAAIOAAkJOR3uFACiAgAOAAkJOR3uFACiAgAAAA==.Jlawzzs:BAAALgAECgMJAgAAAA==.',
Jo='Job:BAACLgAFFH8pAAMQAAgJBR4/CwBqAgAQAAgJAB4/CwBqAgATAAMJ7CMADwAsAQAuAAQKf0IAAxAACQm8JbYEADsDABAACQnUJLYEADsDABMABwn3ImsEAFIBAAAA.',
Ju='Juanweasley:BAAALgAFFAMJBAAAAA==.Judoriel:BAAALgAECgcJDAAAAA==.Julz:BAAALgADCgUJBQAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8oAAISAAkJuRoiHwBsAgASAAkJuRoiHwBsAgAAAA==.Kaimin:BAABLgAECn9YAAIYAAkJ7yH8AQDVAgAYAAkJ7yH8AQDVAgAAAA==.Kaledor:BAAALgADCgEJAQAAAA==.Karthas:BAAALgAECgIJBQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAVAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8xAAMXAAkJdRhLEABsAgAXAAkJdRhLEABsAgAbAAMJFAPIVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8yAAMMAAkJ8xA0PwCxAQAMAAkJ8xA0PwCxAQAKAAQJfAo0LACXAAAAAA==.Khonsu:BAAALgAECgcJDAAAAA==.',
Ki='Kiba:BAABLgAECn8kAAMfAAcJwg8qRABbAQAfAAcJwg8qRABbAQAgAAQJpgpOWgCqAAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAABLgAECn8gAAIMAAgJ2Rj5IwA3AgAMAAgJ2Rj5IwA3AgAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Kowadin:BAAALgADCgEJAQAAAA==.Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8lAAIhAAkJkQsiGwA/AQAhAAkJkQsiGwA/AQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAACLgAFFH8hAAIfAAYJAxNHDgBkAQAfAAYJAxNHDgBkAQAuAAQKfzwAAx8ACQkQIfMGADIDAB8ACQkQIfMGADIDACAAAwl3Dg1mAIoAAAAA.',
La='Larenta:BAAALgADCgYJBgAAAA==.Larethiana:BAACLgAFFH8FAAIOAAUJhgoSLQABAQAOAAUJhgoSLQABAQAuAAQKfxQAAw4ACAnpFKJMAHEBAA4ABwmMFaJMAHEBABEABgn1FgA1AGoBAAAA.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMcAAYJXQMfagDSAAAcAAYJXQMfagDSAAANAAQJRQGAIQFbAAAAAA==.',
Li='Lightbright:BAACLgAFFH8VAAINAAUJFCCWLABcAQANAAUJFCCWLABcAQAuAAQKfyMAAg0ACQlVJJcHAFoDAA0ACQlVJJcHAFoDAAAA.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAABLgAECn8yAAIbAAcJlB4XFgAaAgAbAAcJlB4XFgAaAgAAAA==.Linnasha:BAABLgAECn8tAAIOAAkJLhfUJAAlAgAOAAkJLhfUJAAlAgAAAA==.Litlefoot:BAAALgAECgkJEwAAAA==.',
Lo='Lornzap:BAABLgAFFH8NAAILAAMJNBsWKgDtAAALAAMJNBsWKgDtAAAAAA==.Lostwanderer:BAABLgAECn8dAAMfAAgJBRjbHQAqAgAfAAgJBRjbHQAqAgAgAAIJrAV/jwBBAAAAAA==.Lot:BAAALgAFFAEJAQABLgAFFAgJKQAQAAUeAA==.Lowcowlorie:BAAALgAECgEJAQAAAA==.',
Ma='Machine:BAACLgAFFH8KAAIiAAMJ2hVmDQCcAAAiAAMJ2hVmDQCcAAAuAAQKfx8AAiIACQlfElUSABYCACIACQlfElUSABYCAAAA.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8xAAITAAkJ3xYlEgAKAgATAAkJ3xYlEgAKAgAAAA==.Manamontana:BAAALgAECgQJBAAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Mannanan:BAAALgAECgcJDgAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meatrocketxd:BAAALgAECgcJAQAAAA==.Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8xAAQSAAkJziC1EgC8AgASAAkJziC1EgC8AgAiAAIJPRAaTwB0AAAZAAEJhwzvPQAuAAAAAA==.Minyaura:BAAALgADCgQJBAAAAA==.Minyholy:BAAALgAECgQJBAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Mirañda:BAAALgADCgEJAQAAAA==.Miridian:BAAALgAECgcJDwAAAA==.Miromoney:BAAALgADCgUJBQAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgAECgYJEgAAAA==.Moogician:BAAALgAECgIJBgABLgAECgkJIAASAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonmama:BAAALgADCgMJAwAAAA==.Moonsïnd:BAABLgAECn8rAAMOAAkJZA1wQACQAQAOAAkJZA1wQACQAQAaAAIJehJlOgBvAAAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgAECgcJDwAAAA==.Morgrin:BAAALgAECgQJBgAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8iAAIdAAgJAhP1IQCGAQAdAAgJAhP1IQCGAQAAAA==.',
My='Mydira:BAAALgAECgkJDAAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAACLgAFFH8GAAIOAAMJdQYfTQCKAAAOAAMJdQYfTQCKAAAuAAQKfxkABA4ACQmnGK8VAJsCAA4ACQmnGK8VAJsCAAkAAgn4BxJvADoAABEAAQmXCs6SACwAAAAA.Nalthexon:BAAALgAECgYJBgABLgAFFAMJBgAOAHUGAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neko:BAAALgAFFAIJBAAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAcANscAA==.',
Ni='Niavanith:BAAALgAECgYJEgAAAA==.Nicotine:BAAALgAECgEJAQAAAA==.Nights:BAAALgAFFAEJAQABLgAFFAMJCgAiANoVAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAACLgAFFH8fAAMFAAUJdB3kAgBSAQAFAAUJdB3kAgBSAQADAAQJrQ/vMgD2AAAuAAQKf0QAAwUACQnUI8oAACcDAAUACQnUI8oAACcDAAQABQnUFfMYAEUBAAAA.Nizo:BAABLgAECn86AAIOAAkJlx+XDQDtAgAOAAkJlx+XDQDtAgAAAA==.',
Nj='Njal:BAAALgAECgQJBAAAAA==.',
No='Noblitz:BAACLgAFFH8IAAMbAAQJXwt5HgD+AAAbAAQJXwt5HgD+AAAjAAEJNxU/NgA6AAAuAAQKfyAABBsACQlWGB8QAFsCABsACQlWGB8QAFsCACMABgnRGdcmAI4BABcAAQkIHjsUAFUAAAAA.Novastrike:BAABLgAECn8mAAMMAAgJohdNQwCgAQAMAAgJohdNQwCgAQALAAgJ3wtTWwDSAAAAAA==.',
Ny='Nyrif:BAACLgAFFH8XAAIWAAQJLBvwCQAfAQAWAAQJLBvwCQAfAQAuAAQKfyIAAhYACQnzGuMQAP0BABYACQnzGuMQAP0BAAAA.',
Ob='Obsidion:BAAALgADCgYJBwAAAA==.',
Oj='Ojoon:BAABLgAECn8dAAIBAAcJshACEAAdAQABAAcJshACEAAdAQAAAA==.',
Om='Omnisllash:BAACLgAFFH8MAAIBAAQJ1wyaJQASAQABAAQJ1wyaJQASAQAuAAQKfxcAAgEACAl0FJZVANwBAAEACAl0FJZVANwBAAAA.',
Or='Orisana:BAACLgAFFH8TAAMiAAQJoxtfDwBJAQAiAAQJoxtfDwBJAQASAAIJNxWQiQCLAAAuAAQKf1EABCIACQlCIaIFAMsCABkACQnAGnkMAOUCACIACQneH6IFAMsCABIABQmMGY2BADsBAAAA.',
Pa='Palatrin:BAAALgADCggJDwAAAA==.Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8YAAMEAAUJAQwLGAAVAQAEAAUJAQwLGAAVAQADAAEJlwjiZgA4AAAAAA==.Pewpewbang:BAAALgAECgQJBQAAAA==.',
Ph='Phoenìx:BAAALgAECgEJAgAAAA==.Phyter:BAAALgAECgIJBQAAAA==.',
Pi='Pillin:BAABLgAECn8eAAMeAAgJSRvHAABpAQAeAAgJJhvHAABpAQAdAAIJRxDcWABEAAAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8hAAMkAAkJcB0zFwA0AgAkAAkJcB0zFwA0AgAlAAEJ7AiGUgA0AAAAAA==.Powerwordmoo:BAAALgAECgEJAQABLgAECgkJIAASAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Prina:BAAALgADCgUJBQAAAA==.Provi:BAAALgAECggJDAAAAA==.',
Ps='Psyffe:BAAALgAECgUJCgAAAA==.Psyrge:BAAALgAECgYJBgAAAA==.',
['Pä']='Päïn:BAAALgAECgMJAwAAAA==.',
Qu='Queue:BAABLgAECn9DAAIWAAkJIBD6GgCFAQAWAAkJIBD6GgCFAQAAAA==.',
Re='Rebeccayaros:BAAALgAECgUJDwAAAA==.Redle:BAABLgAECn8fAAINAAgJdA1LGQDGAAANAAgJdA1LGQDGAAAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAECLgAFFH8fAAQiAAUJERkxBQAvAQAiAAUJERkxBQAvAQAZAAEJtgcQKgBIAAASAAEJFAPtrwA8AAAuAAQKfzUAAyIACQmxH38GALkCACIACQlOHn8GALkCABkACAkSFgAeADYCAAAA.',
Ro='Rokkitok:BAAALgAECgkJEgAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
Ru='Rulnic:BAAALgAECgEJAwAAAA==.',
['Rà']='Ràwrshàk:BAAALgAECgYJDQAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8nAAISAAkJqBq4KgAzAgASAAkJqBq4KgAzAgAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgABLgAFFAEJAQAVAAAAAA==.',
Sa='Sanyo:BAAALgADCgEJAQAAAA==.Sarahjan:BAAALgAECgIJAgAAAA==.Sathen:BAAALgADCgEJAQAAAA==.',
Se='Sea:BAACLgAFFH8iAAIMAAYJ6h1HDAARAgAMAAYJ6h1HDAARAgAuAAQKfyMAAgwACQmyIOYBAG4DAAwACQmyIOYBAG4DAAAA.Seliph:BAAALgAECgQJBAAAAA==.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgkJDwAAAA==.Shadowrose:BAABLgAECn8xAAMaAAkJahkuDAD2AQAaAAgJuhcuDAD2AQAOAAQJhQ3OegDHAAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAABLgAECn8aAAIHAAkJ4hV6NwD7AQAHAAkJ4hV6NwD7AQAAAA==.Shamamama:BAAALgADCgEJAQAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAwAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAVAAAAAA==.Shiemi:BAAALgAECgcJBgAAAA==.Shootingbo:BAAALgAECgEJAQAAAA==.Shunsui:BAACLgAFFH8LAAIHAAUJfAuuXwAIAQAHAAUJfAuuXwAIAQAuAAQKfzAAAwcACQmoG5sdAHMCAAcACQmoG5sdAHMCAAgAAQkAACRvADcAAAAA.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Silentomen:BAAALgADCgkJCQAAAA==.Siley:BAABLgAECn8YAAIcAAkJ2xzDFABrAgAcAAkJ2xzDFABrAgAAAA==.Sinnister:BAABLgAFFH8GAAIQAAQJZhIDKAC9AAAQAAQJZhIDKAC9AAAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgYJCwAAAA==.',
Sk='Skullmonkêy:BAABLgAFFH8NAAIYAAQJfAjvKwADAQAYAAQJfAjvKwADAQABLgAFFAUJCwAHAHwLAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snaghelli:BAAALgAECgEJAQABLgAFFAcJGwAkAH0eAA==.Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAABLgAFFH8GAAIdAAEJWxuMOgBVAAAdAAEJWxuMOgBVAAAAAA==.',
So='Sooner:BAACLgAFFH8SAAMYAAQJMx/OTQBWAQAYAAQJMx/OTQBWAQAmAAMJXRSoFwDOAAAuAAQKfxkAAyYABwl7HfEEAPwBACYABgl0IPEEAPwBABgABQkMHPiCAHwBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgIJAgAAAA==.',
Sp='Spaztacular:BAAALgAECgQJBAAAAA==.',
Sq='Squeaky:BAAALgAECgcJEgAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.Stumpy:BAAALgADCgIJAQAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.Sunraku:BAAALgADCgIJAgAAAA==.',
Sy='Syrupp:BAAALgAECgkJDgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.Tayn:BAAALgAECgUJCAAAAA==.',
Te='Tealeaf:BAAALgAECgQJBAAAAA==.Temporary:BAAALgAECgIJAgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Thackery:BAAALgADCgMJBAAAAA==.Theblackdk:BAAALgADCgQJAwAAAA==.Thinsheets:BAAALgADCgcJCQABLgAFFAIJBQANAHQMAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
To='Tortus:BAAALgAECgEJAQAAAA==.Toxicrumor:BAAALgAFFAMJAwAAAA==.',
Tr='Triplenine:BAAALgAECgIJAgABLgAFFAkJKwABAOkZAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgQJBQAAAA==.',
Tu='Tucktoo:BAAALgAECgYJCQAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAACLgAFFH8YAAMbAAUJRBBLCwAFAQAbAAUJRBBLCwAFAQAXAAIJRAUNQwBvAAAuAAQKfy8AAxsACQnmFrEWABQCABsACQnmFrEWABQCABcABAlICL9QAMAAAAAA.',
Uw='Uwurailme:BAABLgAECn8VAAQIAAcJNg8KMgDwAAAHAAYJcQxriwBCAQAIAAUJHAoKMgDwAAAGAAIJrRN5HQCGAAAAAA==.',
Va='Vagãbon:BAAALgAFFAIJAgABLgAFFAMJCgAiANoVAA==.Valenix:BAACLgAFFH8VAAMgAAQJIwzACADpAAAgAAQJIwzACADpAAAfAAMJSwpnRwCHAAAuAAQKfx8AAyAACQlmENdCAPMAACAABwlDENdCAPMAAB8ACAnrESxvAMoAAAAA.Valkryi:BAAALgAECgEJAQAAAA==.Varys:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.Vaxîs:BAAALgAECgMJAwAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAABLgAECn8WAAIFAAkJPh4+AADHAgAFAAkJPh4+AADHAgAAAA==.',
Vi='Violencé:BAAALgAECgYJBgAAAA==.',
Vo='Vo:BAAALgAECgYJEgAAAA==.',
Vu='Vulasity:BAAALgAECgcJBwAAAA==.',
Wa='Warder:BAABLgAECn8gAAIkAAgJwRgmIwDaAQAkAAgJwRgmIwDaAQAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wiigo:BAABLgAFFH8GAAIfAAMJ0g5oIACbAAAfAAMJ0g5oIACbAAAAAA==.Wincks:BAABLgAECn8jAAQHAAkJ+BwQBwBeAQAIAAYJIB7PDAByAQAHAAYJCBgQBwBeAQAGAAIJ9x31BQCtAAAAAA==.',
Xa='Xana:BAAALgADCgUJBQABLgAFFAQJCAAbAF8LAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAABLgAECn8oAAICAAkJxxV6AgAtAgACAAkJxxV6AgAtAgAAAA==.Zackman:BAACLgAFFH8gAAIcAAUJXwo8CwAUAQAcAAUJXwo8CwAUAQAuAAQKf0kAAhwACQlJFeMZADcCABwACQlJFeMZADcCAAAA.',
Zh='Zhimer:BAAALgADCgIJAgAAAA==.',
Zi='Zinagos:BAAALgAFFAIJAgABLgAFFAQJFQAgACMMAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.Zombie:BAAALgAFFAIJAwAAAA==.Zosos:BAAALgAECgEJAgAAAA==.',
Zu='Zulrea:BAAALgAECgcJCgAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJCwAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAFFAEJAQAVAAAAAA==.',
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
