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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Druid-Restoration','Mage-Fire','DemonHunter-Devourer','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','DeathKnight-Blood','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Paladin-Holy','Hunter-Survival','Rogue-Subtlety','Warrior-Fury','DeathKnight-Frost',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAQJDAABAMcTAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgADCgEJAQAAAA==.Allice:BAABLgAECn8fAAMCAAcJwBxfAwA8AgACAAcJaxxfAwA8AgABAAQJoQxp7AChAAAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAECgkJDwAAAA==.',
An='Anastasija:BAAALgAECgEJAQAAAA==.Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgYJDgAAAA==.',
Ar='Arahwn:BAAALgAECgUJBQAAAA==.',
Au='Augnyxia:BAABLgAECn8sAAQDAAcJnxOuJACYAQADAAcJuxGuJACYAQAEAAQJIAQUKAB/AAAFAAQJ8Q4ZGABvAAAAAA==.Augtism:BAABLgAECn8vAAQGAAgJ4iF3AwBLAgAHAAgJsyDtJwByAgAGAAcJ/SB3AwBLAgAIAAEJAADXXQBVAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgEJAgAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAgJIAAFACAgAA==.',
Be='Beefquake:BAAALgAECggJDQAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Bersh:BAABLgAECn8xAAQJAAkJFR0DBQBuAgAJAAkJFxwDBQBuAgAKAAYJuhc/NwArAQALAAEJAQiMngAyAAAAAA==.',
Bi='Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBAAAAA==.Bloodjury:BAABLgAECn8aAAIMAAcJVhq7YwCJAQAMAAcJVhq7YwCJAQAAAA==.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAABLgAECn8VAAINAAgJpxiyJQD+AQANAAgJpxiyJQD+AQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Boonktown:BAABLgAECn8rAAMBAAkJnw3UUADNAQABAAkJQA3UUADNAQAOAAcJuQn5BAB9AQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgYJDgAAAA==.Bruceleela:BAAALgAECgYJCwABLgAECgcJIQAPAH4VAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bushetti:BAABLgAECn8dAAMNAAgJCBUfQwBhAQANAAgJCBUfQwBhAQAQAAMJmxiBWAB9AAABLgAFFAMJBgALAFUbAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMKAAkJYBElJQDoAQAKAAkJYBElJQDoAQALAAYJDxXCRwBcAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgUJCAAAAA==.Cazisham:BAABLgAECn8bAAIJAAcJ/QTAGgDiAAAJAAcJ/QTAGgDiAAAAAA==.',
Ce='Cevianne:BAABLgAECn8sAAIRAAgJjRMsOADNAQARAAgJjRMsOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chaoticsaint:BAABLgAECn8XAAISAAgJEBHVJQAPAQASAAgJEBHVJQAPAQAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Cl='Claros:BAAALgAECggJCQAAAA==.',
Co='Coal:BAABLgAECn80AAMPAAgJkyOFEACjAgAPAAgJkyOFEACjAgATAAcJ5xtGBwDmAQAAAA==.Coalesce:BAAALgADCgQJBAABLgAECggJNAAPAJMjAA==.Coltonater:BAABLgAECn8+AAIBAAgJ7iGoHACVAgABAAgJ7iGoHACVAgAAAA==.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.',
['Cá']='Cáséy:BAACLgAFFH8LAAIBAAQJxBW2OwBLAQABAAQJxBW2OwBLAQAuAAQKfx8AAgEACAmkHWM8AIYCAAEACAmkHWM8AIYCAAAA.',
['Cä']='Cäsey:BAAALgAECgUJCQABLgAFFAQJCwABAMQVAA==.',
Da='Daktari:BAAALgADCgYJBgABLgAECgkJLgANAAocAA==.Dampening:BAAALgAECgMJAwABLgAECgUJBQAUAAAAAA==.Danbi:BAABLgAECn8zAAQDAAkJ9hNBGAD0AQADAAkJ9hNBGAD0AQAEAAgJoxabDADkAQAFAAQJtg8TFACnAAAAAA==.Darkshroud:BAAALgAECgIJAgAAAA==.',
De='Deathdylan:BAACLgAFFH8IAAIVAAMJCgtIIACkAAAVAAMJCgtIIACkAAAuAAQKfywAAhUACAkYHUANAAYCABUACAkYHUANAAYCAAAA.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAABLgAECn8hAAIPAAcJfhWTVQBiAQAPAAcJfhWTVQBiAQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Delice:BAAALgAECgEJAQAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demítríus:BAAALgADCgYJDQAAAA==.Dethh:BAAALgADCgYJCQAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Di='Dionos:BAAALgAECgEJAQAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Dragonlord:BAAALgAECgYJBgAAAA==.Draugr:BAAALgADCgUJBQAAAA==.Dravyn:BAABLgAECn8mAAIBAAgJqQxYcQB6AQABAAgJqQxYcQB6AQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxNNQCeAgABAAgJmhxNNQCeAgAAAA==.Druqz:BAACLgAFFH8GAAIBAAMJRQNJdwC1AAABAAMJRQNJdwC1AAAuAAQKfxkAAgEACAmeCiCGAE8BAAEACAmeCiCGAE8BAAAA.Drævn:BAABLgAECn8lAAMBAAYJbhW5lgAwAQABAAYJVRO5lgAwAQAOAAMJJRRYCADLAAAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8YAAMPAAYJVSBiEADKAQAPAAYJVSBiEADKAQATAAIJQgsZCQByAAAuAAQKfyUAAg8ACAmmIlwSAJICAA8ACAmmIlwSAJICAAAA.',
Dw='Dwimbear:BAAALgADCgEJAQAAAA==.Dwimhoof:BAAALgADCgcJCQAAAA==.',
Ed='Ediconegoen:BAAALgAECgEJAgAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAACLgAFFH8GAAIWAAMJzhuhHwALAQAWAAMJzhuhHwALAQAuAAQKfxoAAhYACQkAH/sPAD8CABYACQkAH/sPAD8CAAAA.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgYJDgAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJ0gubWgCxAQABAAkJ0gubWgCxAQACAAIJOgZTGQBNAAAAAA==.Endofdays:BAAALgAECggJDQAAAA==.Enro:BAABLgAECn8yAAMSAAgJlRq4DgAFAgASAAgJlRq4DgAFAgAPAAQJqgd+tQCdAAAAAA==.',
Er='Erovia:BAABLgAECn8jAAIRAAkJVwmdZQBLAQARAAkJVwmdZQBLAQAAAA==.',
Es='Esclipse:BAAALgAECgcJCQAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgAECgMJAwAAAA==.',
Fe='Felony:BAABLgAECn8xAAISAAgJaCQ3BQDDAgASAAgJaCQ3BQDDAgAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavah:BAABLgAECn8XAAIQAAgJMR2YHAAdAgAQAAgJMR2YHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8wAAMXAAkJqBMcSwC+AQAXAAkJqBMcSwC+AQAVAAcJDQQqMgClAAAAAA==.Flower:BAAALgAFFAIJAgAAAA==.',
Fo='Foodex:BAAALgAECgcJEQAAAA==.Fourleaf:BAACLgAFFH8GAAIYAAMJRxOEEwDmAAAYAAMJRxOEEwDmAAAuAAQKfy4AAhgACAkSH8cEAEACABgACAkSH8cEAEACAAAA.',
Fr='Frydayx:BAAALgAECgMJAwAAAA==.',
Fu='Furral:BAACLgAFFH8FAAIZAAIJihLmDACeAAAZAAIJihLmDACeAAAuAAQKfx0AAhkACAliHPIGADwCABkACAliHPIGADwCAAAA.',
Ga='Gaeth:BAABLgAECn8jAAINAAkJUBAIQgCZAQANAAkJUBAIQgCZAQAAAA==.',
Ge='Gelys:BAAALgAECgQJBAAAAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Gl='Gleg:BAABLgAFFH8GAAILAAMJVRv8KgD+AAALAAMJVRv8KgD+AAAAAA==.',
Go='Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8UAAIPAAYJmhhGZQA2AQAPAAYJmhhGZQA2AQAAAA==.Grimvess:BAAALgAECggJCQAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Hamburgler:BAAALgADCgYJBgABLgAECgkJIAARAKchAA==.Hammerobby:BAAALgAECgYJCgABLgAECgcJIQAPAH4VAA==.Handlebar:BAAALgAECgUJCgABLgAECgcJIQAPAH4VAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAECgMJBgABLgAECgUJCgAUAAAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8dAAIMAAgJLxFRZgCDAQAMAAgJLxFRZgCDAQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.Holyshock:BAAALgAECgUJBgAAAA==.',
Hy='Hyournmaru:BAAALgAECgYJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Il='Ilkkarid:BAAALgAECgYJEAAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAAALgAECgkJEwAAAA==.',
Is='Ishpoo:BAABLgAECn8vAAIMAAkJ0xDDQADlAQAMAAkJ0xDDQADlAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jecht:BAAALgADCgEJAQAAAA==.Jelqer:BAABLgAECn8VAAMFAAYJsCCaEgC4AQAFAAYJsCCaEgC4AQADAAUJZBQXMABFAQAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8qAAINAAkJOR0lEQCnAgANAAkJOR0lEQCnAgAAAA==.',
Jo='Job:BAACLgAFFH8WAAIPAAYJPCKzDwDQAQAPAAYJPCKzDwDQAQAuAAQKfzsAAw8ACQmiJBcDAEYDAA8ACQmiJBcDAEYDABIABgnFINgjAJ4BAAAA.',
Ju='Juanweasley:BAAALgAECgMJBAAAAA==.Judoriel:BAAALgAECgcJCgAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8oAAIRAAkJuRqeFQB9AgARAAkJuRqeFQB9AgAAAA==.Kaimin:BAABLgAECn85AAIXAAkJaB7nFQCiAgAXAAkJaB7nFQCiAgAAAA==.Karthas:BAAALgAECgIJBQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAUAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8xAAMWAAkJdRhqDAB7AgAWAAkJdRhqDAB7AgAaAAMJFAPIVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8yAAMLAAkJ8xCyMwCzAQALAAkJ8xCyMwCzAQAJAAQJfArMIQCZAAAAAA==.Khonsu:BAAALgAECgcJDAAAAA==.',
Ki='Kiba:BAABLgAECn8jAAMbAAcJwg+ANQBKAQAbAAcJwg+ANQBKAQAcAAMJTQgzWgB5AAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAABLgAECn8eAAILAAcJRxmvJQD+AQALAAcJRxmvJQD+AQAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Kowadin:BAAALgADCgEJAQAAAA==.Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8lAAIdAAkJkQvlFQBHAQAdAAkJkQvlFQBHAQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAACLgAFFH8HAAIbAAQJJA88IADyAAAbAAQJJA88IADyAAAuAAQKfzYAAxsACQkQId0EADQDABsACQkQId0EADQDABwAAwl0Dq9TAI8AAAAA.',
La='Larethiana:BAACLgAFFH8FAAINAAUJhgpLIAAkAQANAAUJhgpLIAAkAQAuAAQKfxQAAw0ACAnpFKJMAHEBAA0ABwmMFaJMAHEBABAABgn1FgA1AGoBAAAA.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMeAAYJXQMfagDSAAAeAAYJXQMfagDSAAAMAAQJRQGAIQFbAAAAAA==.',
Li='Lightbright:BAACLgAFFH8FAAIMAAMJahogQwD+AAAMAAMJahogQwD+AAAuAAQKfyAAAgwACAkGJZcHAFoDAAwACAkGJZcHAFoDAAAA.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAABLgAECn8XAAIaAAYJUBerKQBbAQAaAAYJUBerKQBbAQAAAA==.Linnasha:BAABLgAECn8rAAINAAgJwBh0KQDmAQANAAgJwBh0KQDmAQAAAA==.Litlefoot:BAAALgAECgIJAgAAAA==.',
Lo='Lornzap:BAABLgAFFH8GAAIKAAMJpRb+IwDcAAAKAAMJpRb+IwDcAAAAAA==.Lostwanderer:BAAALgAECggJDgAAAA==.Lot:BAAALgAECgUJBQABLgAFFAYJFgAPADwiAA==.Lowcowlorie:BAAALgAECgEJAQAAAA==.',
Ma='Machine:BAABLgAECn8ZAAIfAAgJ5w2DGwCjAQAfAAgJ5w2DGwCjAQAAAA==.Magoo:BAAALgAECgIJAgAAAA==.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8xAAISAAkJ3xaNDQAXAgASAAkJ3xaNDQAXAgAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Mannanan:BAAALgAECgcJDgAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meatrocketxd:BAAALgAECgcJAQAAAA==.Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8xAAQRAAkJziDiCwDQAgARAAkJziDiCwDQAgAfAAIJPRAIRQB1AAAYAAEJhwwxNQAuAAAAAA==.Minyholy:BAAALgAECgQJBAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Mirañda:BAAALgADCgEJAQAAAA==.Miridian:BAAALgAECgcJDwAAAA==.Miromoney:BAAALgADCgUJBQAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgAECgUJCAAAAA==.Moogician:BAAALgAECgIJBgABLgAECgkJIAARAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonsïnd:BAABLgAECn8oAAINAAgJzQ1iQwBgAQANAAgJzQ1iQwBgAQAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgADCgQJAwAAAA==.Morgrin:BAAALgAECgMJAwAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8iAAIgAAgJAhMJGwCWAQAgAAgJAhMJGwCWAQAAAA==.',
My='Mydira:BAAALgAECgkJDAAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAABLgAFFH8GAAINAAMJdQYmOgCqAAANAAMJdQYmOgCqAAAAAA==.Nalthexon:BAAALgAECgYJBgABLgAFFAMJBgANAHUGAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAeANscAA==.',
Ni='Niavanith:BAAALgAECgYJEQAAAA==.Nights:BAAALgAECgcJCwABLgAECggJGQAfAOcNAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAACLgAFFH8IAAIFAAMJAxyVBAAKAQAFAAMJAxyVBAAKAQAuAAQKfzEAAgUACAmkIsoBAKYCAAUACAmkIsoBAKYCAAAA.Nizo:BAABLgAECn8uAAINAAkJChxgCwDrAgANAAkJChxgCwDrAgAAAA==.',
No='Noblitz:BAAALgAECgcJDwAAAA==.Novastrike:BAABLgAECn8mAAMLAAgJohfZNgCkAQALAAgJohfZNgCkAQAKAAgJ3wviSgDYAAAAAA==.',
Ny='Nyrif:BAACLgAFFH8GAAIVAAMJLxzNFwDrAAAVAAMJLxzNFwDrAAAuAAQKfyEAAhUACQkBGrsNAP4BABUACQkBGrsNAP4BAAAA.',
Oj='Ojoon:BAAALgAECgUJBwAAAA==.',
Om='Omnisllash:BAAALgAFFAIJAwAAAA==.',
Or='Orisana:BAACLgAFFH8PAAMfAAQJXRKHDgA8AQAfAAQJXRKHDgA8AQARAAIJNxU4XgCVAAAuAAQKf0sABB8ACQnQH5YEAMoCABgACQnAGnkMAOUCAB8ACQl2HpYEAMoCABEABQmMGVdoAEQBAAAA.',
Pa='Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8YAAMEAAUJAQwyEQBIAQAEAAUJAQwyEQBIAQADAAEJlwhMUAA/AAAAAA==.',
Ph='Phoenìx:BAAALgAECgEJAQAAAA==.Phyter:BAAALgAECgIJAwAAAA==.',
Pi='Pillin:BAAALgAECgcJEwAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8aAAIhAAcJHB+lJQClAQAhAAcJHB+lJQClAQAAAA==.Powerwordmoo:BAAALgAECgEJAQABLgAECgkJIAARAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Prina:BAAALgADCgUJBQAAAA==.Provi:BAAALgAECggJDAAAAA==.',
Ps='Psyffe:BAAALgAECgUJBgAAAA==.Psyrge:BAAALgAECgQJBAAAAA==.',
Qu='Queue:BAABLgAECn8yAAIVAAgJyBCtGgBWAQAVAAgJyBCtGgBWAQAAAA==.',
Re='Rebeccayaros:BAAALgAECgUJDQAAAA==.Redle:BAAALgAECggJEQAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAECLgAFFH8IAAQfAAMJeA17GADlAAAfAAMJeA17GADlAAAYAAEJtgcQKgBIAAARAAEJFAP7fQA8AAAuAAQKfykAAx8ACAm5HJ8PABoCABgACAkSFgAeADYCAB8ACAkkG58PABoCAAAA.',
Ro='Rokkitok:BAAALgAECgcJEAAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
['Rà']='Ràwrshàk:BAAALgADCgcJBwAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8mAAIRAAkJqBpRHgBGAgARAAkJqBpRHgBGAgAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgAAAA==.',
Se='Sea:BAACLgAFFH8bAAILAAYJBh1UBQAeAgALAAYJBh1UBQAeAgAuAAQKfyIAAgsACQmSIOYBAG4DAAsACQmSIOYBAG4DAAAA.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgYJCgAAAA==.Shadowrose:BAABLgAECn8xAAMZAAkJahkUCQAEAgAZAAgJuhcUCQAEAgANAAQJhQ1TbQDLAAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAABLgAECn8YAAIHAAkJuBQTKwAVAgAHAAkJuBQTKwAVAgAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAwAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAUAAAAAA==.Shiemi:BAAALgAECgMJBQAAAA==.Shootingbo:BAAALgAECgEJAQAAAA==.Shunsui:BAACLgAFFH8FAAIHAAMJAgx8YQDVAAAHAAMJAgx8YQDVAAAuAAQKfyoAAwcACAkAG3YpABwCAAcACAkAG3YpABwCAAgAAQkAACRvADcAAAAA.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Siley:BAABLgAECn8YAAIeAAkJ2xzDFABrAgAeAAkJ2xzDFABrAgAAAA==.Sinnister:BAAALgAECgcJDQAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgYJCwAAAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAAALgAFFAEJAwAAAA==.',
So='Sooner:BAACLgAFFH8SAAMXAAQJMx/eKAB4AQAXAAQJMx/eKAB4AQAiAAMJXRTvDADgAAAuAAQKfxkAAyIABwl7HfEEAPwBACIABgl0IPEEAPwBABcABQkMHPiCAHwBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgIJAgAAAA==.',
Sq='Squeaky:BAAALgAECgUJBwAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.',
Sy='Syrupp:BAAALgAECgkJCgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.Tayn:BAAALgAECgIJAgAAAA==.',
Te='Tealeaf:BAAALgAECgQJBAAAAA==.Temporary:BAAALgAECgEJAQAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Thackery:BAAALgADCgMJAwAAAA==.Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
To='Toxicrumor:BAAALgAECgYJBgAAAA==.',
Tr='Triplenine:BAAALgAECgIJAgABLgAFFAgJHQABAIgaAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgQJBQAAAA==.',
Tu='Tucktoo:BAAALgAECgIJAwAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAACLgAFFH8GAAMWAAMJZg/CMACCAAAWAAIJNgTCMACCAAAaAAEJvAx3LABNAAAuAAQKfy8AAxoACQnmFmsRACYCABoACQnmFmsRACYCABYABAlICKJBAMgAAAAA.',
Uw='Uwurailme:BAABLgAECn8VAAQIAAcJNg8KMgDwAAAHAAYJcQxriwBCAQAIAAUJHAoKMgDwAAAGAAIJrRN5HQCGAAAAAA==.',
Va='Valenix:BAACLgAFFH8GAAMcAAMJNAjcHQC2AAAcAAMJNAjcHQC2AAAbAAMJXwYELQCZAAAuAAQKfx4AAxwACAkTEdU2APsAABwABwlDENU2APsAABsABwnQEu8/AOIAAAAA.Valkryi:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAAALgAECgUJBgAAAA==.',
Vo='Vo:BAAALgAECgYJEgAAAA==.',
Wa='Warder:BAABLgAECn8aAAIhAAcJLxb8KQCLAQAhAAcJLxb8KQCLAQAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wincks:BAABLgAECn8XAAMIAAcJWRy2CQB9AQAIAAYJIB62CQB9AQAHAAUJ7RRadQA5AQAAAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAABLgAECn8fAAICAAkJ8hG7AgD6AQACAAkJ8hG7AgD6AQAAAA==.Zackman:BAACLgAFFH8IAAIeAAMJBwb0LACVAAAeAAMJBwb0LACVAAAuAAQKfzYAAh4ACAlNFCkcAPsBAB4ACAlNFCkcAPsBAAAA.',
Zh='Zhimer:BAAALgADCgIJAgAAAA==.',
Zi='Zinagos:BAAALgAECggJDgABLgAFFAMJBgAcADQIAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.Zombie:BAAALgAECgQJBgAAAA==.Zosos:BAAALgAECgEJAQAAAA==.',
Zu='Zulrea:BAAALgAECgcJCgAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJCwAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAECgUJCgAUAAAAAA==.',
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
