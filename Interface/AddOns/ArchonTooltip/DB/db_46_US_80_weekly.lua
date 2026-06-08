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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Druid-Restoration','Mage-Fire','DemonHunter-Devourer','Druid-Balance','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','DeathKnight-Blood','Priest-Discipline','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Rogue-Subtlety','Rogue-Outlaw','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Paladin-Protection','Paladin-Holy','Hunter-Survival','Druid-Guardian','Warrior-Fury','Warrior-Protection','DeathKnight-Frost',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAUJDQABADAQAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Alendrael:BAAALgAECgIJAgAAAA==.Allice:BAABLgAECn8fAAMCAAcJwBxfAwA8AgACAAcJaxxfAwA8AgABAAQJoQyiAgGdAAAAAA==.Alterion:BAAALgAECgMJBAAAAA==.Altimusprime:BAAALgAECgkJDwAAAA==.',
An='Anastasija:BAAALgAECgEJAgAAAA==.Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgYJDgAAAA==.',
Ar='Arahwn:BAAALgAECgUJBQAAAA==.',
As='Astaru:BAAALgAECgQJBwABLgAECgkJKAABAEAMAA==.',
Au='Aughyst:BAAALgAECgQJBAAAAA==.Augnyxia:BAABLgAECn8sAAQDAAcJnxOuJACYAQADAAcJuxGuJACYAQAEAAQJIATjKwB+AAAFAAQJ8Q4IGwBqAAAAAA==.Augtism:BAABLgAECn8zAAQGAAkJXCIsAgCvAgAGAAgJqSEsAgCvAgAHAAkJgx8UJgBAAgAIAAEJAADXXQBVAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgAECgUJBgAAAA==.Bandobras:BAAALgAECgUJCgAAAA==.Bangtwinkdh:BAAALgAFFAMJAwABLgAFFAgJIAAFACAgAA==.',
Be='Beefquake:BAAALgAECggJDQAAAA==.Belfdelphine:BAAALgAECgYJCwAAAA==.Berafii:BAAALgAECgEJAQAAAA==.Bersh:BAABLgAECn8xAAQJAAkJFR2SBgBhAgAJAAkJFxySBgBhAgAKAAYJuhfuPgAoAQALAAEJAQiMngAyAAAAAA==.',
Bi='Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBAAAAA==.Bloodjury:BAABLgAECn8bAAIMAAgJvxp5TgDRAQAMAAgJvxp5TgDRAQAAAA==.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAABLgAECn8VAAINAAgJpxjuKQD8AQANAAgJpxjuKQD8AQAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Boonktown:BAABLgAECn8rAAMBAAkJnw1cXADDAQABAAkJQA1cXADDAQAOAAcJuQn5BAB9AQAAAA==.Booschlock:BAAALgAECgMJAwAAAA==.',
Br='Brambles:BAAALgAECgYJDgAAAA==.Bruceleela:BAAALgAECgYJCwABLgAECgcJIQAPAH4VAA==.Brunarr:BAAALgAECgQJEQAAAA==.',
Bu='Bushetti:BAABLgAECn8dAAMNAAgJCBVPSQBgAQANAAgJCBVPSQBgAQAQAAMJmxjHYwB8AAABLgAFFAMJCwALANcfAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8dAAMKAAkJYBElJQDoAQAKAAkJYBElJQDoAQALAAYJDxWVUgBaAQAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Caylo:BAAALgAECgUJCAAAAA==.Cazisham:BAABLgAECn8gAAIJAAcJ/QR8IADiAAAJAAcJ/QR8IADiAAAAAA==.',
Ce='Cevianne:BAABLgAECn8sAAIRAAgJjRMsOADNAQARAAgJjRMsOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chanok:BAAALgADCgMJBgAAAA==.Chaoticsaint:BAABLgAECn8XAAISAAgJEBHhLAAIAQASAAgJEBHhLAAIAQAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Cl='Claros:BAAALgAECggJDAAAAA==.',
Co='Coal:BAABLgAECn81AAMPAAkJuCMlCAAGAwAPAAkJuCMlCAAGAwATAAcJ5xuHCADdAQAAAA==.Coalesce:BAAALgADCgQJBAABLgAECgkJNQAPALgjAA==.Coltonater:BAABLgAECn8+AAIBAAgJ7iEaIwCLAgABAAgJ7iEaIwCLAgAAAA==.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.',
['Cá']='Cáséy:BAACLgAFFH8QAAIBAAQJDh7tOwBsAQABAAQJDh7tOwBsAQAuAAQKfyEAAgEACAmkHWM8AIYCAAEACAmkHWM8AIYCAAAA.',
['Cä']='Cäsey:BAAALgAECgUJCQABLgAFFAQJEAABAA4eAA==.',
Da='Daktari:BAAALgADCgYJBgABLgAECgkJLgANAAocAA==.Dampening:BAAALgAECgMJAwABLgAECgUJBQAUAAAAAA==.Danbi:BAACLgAFFH8GAAMDAAQJzAcENwDcAAADAAQJzAcENwDcAAAEAAIJ+wjXIwBmAAAuAAQKfzUABAQACQmUFywNAPcBAAQACAlEFywNAPcBAAMACQn2E9sbAO8BAAUABAm2D80WAJ0AAAAA.Darkshroud:BAAALgAECgIJAgAAAA==.',
De='Deathdylan:BAACLgAFFH8MAAIVAAMJnwvEKACaAAAVAAMJnwvEKACaAAAuAAQKfzAAAhUACQlAHkIJAHcCABUACQlAHkIJAHcCAAAA.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAABLgAECn8hAAIPAAcJfhX4XgBgAQAPAAcJfhX4XgBgAQAAAA==.Deathshaq:BAAALgADCggJGQAAAA==.Delice:BAAALgAECgEJAQAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demítríus:BAAALgADCgYJDQAAAA==.Dethh:BAAALgADCgYJCQAAAA==.Dethpally:BAAALgADCgYJBgAAAA==.',
Di='Dionos:BAAALgAECgEJAQAAAA==.',
Do='Dourwolf:BAAALgADCgUJBAAAAA==.',
Dr='Dragman:BAAALgAECgUJBQAAAA==.Dragonlord:BAAALgAECgYJBgAAAA==.Draugr:BAAALgADCgUJBQAAAA==.Dravyn:BAABLgAECn8oAAIBAAkJQAxIYQC2AQABAAkJQAxIYQC2AQAAAA==.Drfiredumper:BAABLgAECn8iAAIBAAgJmhxNNQCeAgABAAgJmhxNNQCeAgAAAA==.Druqz:BAACLgAFFH8MAAIBAAMJygPSiAC4AAABAAMJygPSiAC4AAAuAAQKfxkAAgEACAmeCumVAEcBAAEACAmeCumVAEcBAAAA.Drævn:BAABLgAECn8wAAMOAAYJahnOBgAqAQABAAYJFBW7mgA/AQAOAAUJThnOBgAqAQAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8aAAMPAAcJqB2gDwAVAgAPAAcJqB2gDwAVAgATAAIJQgsKDABuAAAuAAQKfycAAg8ACAnLIk8UAJYCAA8ACAnLIk8UAJYCAAAA.Duragon:BAAALgAECgUJBQAAAA==.',
Dw='Dwimbear:BAAALgAECgEJAQAAAA==.Dwimhoof:BAAALgAECgEJAgAAAA==.',
Ed='Ediconegoen:BAAALgAECgEJAgAAAA==.',
Ei='Eiir:BAAALgADCgQJAwAAAA==.',
El='Eldin:BAACLgAFFH8MAAIWAAMJ6B7QJAAHAQAWAAMJ6B7QJAAHAQAuAAQKfxsAAhYACQkAH/sPAD8CABYACQkAH/sPAD8CAAAA.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgYJDgAAAA==.',
En='Enchantress:BAABLgAECn8hAAMBAAkJ0guGZwCnAQABAAkJ0guGZwCnAQACAAIJOgZTGQBNAAAAAA==.Endofdays:BAAALgAECggJDgAAAA==.Enro:BAACLgAFFH8GAAISAAMJjwjEGQC1AAASAAMJjwjEGQC1AAAuAAQKfzsAAxIACQljHsMGALwCABIACQljHsMGALwCAA8ABAmqB361AJ0AAAAA.',
Er='Erovia:BAACLgAFFH8HAAIRAAMJoQOrZgC4AAARAAMJoQOrZgC4AAAuAAQKfyMAAhEACQlXCcZ3AEMBABEACQlXCcZ3AEMBAAAA.',
Es='Esclipse:BAAALgAECgcJCQAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgAECgQJBwAAAA==.',
Fe='Felony:BAABLgAECn8zAAISAAkJGCQVAwAeAwASAAkJGCQVAwAeAwAAAA==.Feyri:BAAALgADCgMJAwAAAA==.',
Fl='Flavaflare:BAAALgAECgEJAQABLgAECggJGwAQADEdAA==.Flavah:BAABLgAECn8bAAIQAAgJMR2YHAAdAgAQAAgJMR2YHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8wAAMXAAkJqBOTVgC6AQAXAAkJqBOTVgC6AQAVAAcJDQRFOQCjAAAAAA==.Flower:BAAALgAFFAIJAgAAAA==.',
Fo='Foodex:BAAALgAECgcJEQAAAA==.Fourleaf:BAACLgAFFH8NAAIYAAQJvhZJEABHAQAYAAQJvhZJEABHAQAuAAQKfzUAAhgACQklIG0CAMMCABgACQklIG0CAMMCAAAA.',
Fr='Frydayx:BAAALgAECgMJBAAAAA==.',
Fu='Furral:BAACLgAFFH8HAAIZAAIJCRk2EACkAAAZAAIJCRk2EACkAAAuAAQKfyEAAhkACQk3H68DAMkCABkACQk3H68DAMkCAAAA.',
Ga='Gaeth:BAABLgAECn8jAAINAAkJUBAIQgCZAQANAAkJUBAIQgCZAQAAAA==.',
Ge='Gelys:BAAALgAECgQJBAABLgAFFAEJAwAUAAAAAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Gl='Gleg:BAABLgAFFH8LAAILAAMJ1x+mLwAMAQALAAMJ1x+mLwAMAQAAAA==.',
Go='Goopdawg:BAAALgAECgQJDAAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAABLgAECn8WAAIPAAcJwxe/WABxAQAPAAcJwxe/WABxAQAAAA==.Grimthedread:BAAALgADCgYJBgAAAA==.Grimvess:BAAALgAECggJCQAAAA==.Griselden:BAAALgAECgEJAQAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Hamburgler:BAAALgADCgYJBgABLgAECgkJIAARAKchAA==.Hammerobby:BAAALgAECgYJCgABLgAECgcJIQAPAH4VAA==.Handlebar:BAAALgAECgUJCgABLgAECgcJIQAPAH4VAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellomon:BAAALgAFFAEJAQAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAABLgAECn8eAAIMAAkJFBA+XwCoAQAMAAkJFBA+XwCoAQAAAA==.Holycrem:BAAALgADCgEJAQAAAA==.Holyshock:BAAALgAECgYJEQAAAA==.',
Hu='Hungsu:BAAALgAECgEJAQAAAA==.',
Hy='Hyournmaru:BAAALgAECgYJBAAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
Il='Ilkkarid:BAABLgAECn8ZAAMaAAgJ4BGWGgC0AQAaAAgJvBGWGgC0AQAbAAYJBgp2EQDmAAAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAAALgAECgkJEwAAAA==.',
Is='Ishpoo:BAABLgAECn8vAAIMAAkJ0xB5UQDJAQAMAAkJ0xB5UQDJAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJIgABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jecht:BAAALgADCgEJAQAAAA==.Jelqer:BAABLgAECn8VAAMFAAYJsCCaEgC4AQAFAAYJsCCaEgC4AQADAAUJZBQXMABFAQAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8qAAINAAkJOR3cEwCjAgANAAkJOR3cEwCjAgAAAA==.Jlawzzs:BAAALgAECgIJAgAAAA==.',
Jo='Job:BAACLgAFFH8dAAIPAAgJaR3YBgCBAgAPAAgJaR3YBgCBAgAuAAQKfzwAAw8ACQmiJCAEAD0DAA8ACQmiJCAEAD0DABIABwm/INgjAJ4BAAAA.',
Ju='Juanweasley:BAAALgAECgMJBgAAAA==.Judoriel:BAAALgAECgcJDAAAAA==.Junkyard:BAAALgAECgQJCgAAAA==.',
Ka='Kahsindre:BAABLgAECn8oAAIRAAkJuRq0GwBzAgARAAkJuRq0GwBzAgAAAA==.Kaimin:BAABLgAECn9FAAIXAAkJeCACDwDsAgAXAAkJeCACDwDsAgAAAA==.Karthas:BAAALgAECgIJBQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQAUAAAAAA==.Kennypowers:BAAALgAECgQJCAAAAA==.Kezeshi:BAABLgAECn8xAAMWAAkJdRg1DwBvAgAWAAkJdRg1DwBvAgAcAAMJFAPIVQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8yAAMLAAkJ8xDoOwCxAQALAAkJ8xDoOwCxAQAJAAQJfArcKACZAAAAAA==.Khonsu:BAAALgAECgcJDAAAAA==.',
Ki='Kiba:BAABLgAECn8kAAMdAAcJwg/NPgBZAQAdAAcJwg/NPgBZAQAeAAQJpgqdVQCqAAAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAABLgAECn8fAAILAAgJZxg+IwAtAgALAAgJZxg+IwAtAgAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Kowadin:BAAALgADCgEJAQAAAA==.Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAABLgAECn8lAAIfAAkJkQubGQBAAQAfAAkJkQubGQBAAQAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAACLgAFFH8PAAIdAAQJGRa/JQASAQAdAAQJGRa/JQASAQAuAAQKfzwAAx0ACQkQIUkGADEDAB0ACQkQIUkGADEDAB4AAwl3DsxfAIwAAAAA.',
La='Larethiana:BAACLgAFFH8FAAINAAUJhgqhKAASAQANAAUJhgqhKAASAQAuAAQKfxQAAw0ACAnpFKJMAHEBAA0ABwmMFaJMAHEBABAABgn1FgA1AGoBAAAA.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMgAAYJXQMfagDSAAAgAAYJXQMfagDSAAAMAAQJRQGAIQFbAAAAAA==.',
Li='Lightbright:BAACLgAFFH8IAAIMAAMJ9B/8UQD6AAAMAAMJ9B/8UQD6AAAuAAQKfyMAAgwACQlVJJcHAFoDAAwACQlVJJcHAFoDAAAA.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAABLgAECn8kAAIcAAcJGB7HFQAWAgAcAAcJGB7HFQAWAgAAAA==.Linnasha:BAABLgAECn8rAAINAAgJwBhsLgDiAQANAAgJwBhsLgDiAQAAAA==.Litlefoot:BAAALgAECggJCwAAAA==.',
Lo='Lornzap:BAABLgAFFH8MAAIKAAMJNBv1JQD2AAAKAAMJNBv1JQD2AAAAAA==.Lostwanderer:BAABLgAECn8VAAMdAAgJLwvvSwAiAQAdAAgJLwvvSwAiAQAeAAIJrAWkhgBBAAAAAA==.Lot:BAAALgAFFAEJAQABLgAFFAgJHQAPAGkdAA==.Lowcowlorie:BAAALgAECgEJAQAAAA==.',
Ma='Machine:BAACLgAFFH8GAAIhAAMJqRKnGwDhAAAhAAMJqRKnGwDhAAAuAAQKfx8AAiEACQlfEjQRAB4CACEACQlfEjQRAB4CAAAA.Magoo:BAAALgAECgIJAgAAAA==.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8xAAISAAkJ3xbKEAAMAgASAAkJ3xbKEAAMAgAAAA==.Manamontana:BAAALgAECgEJAQAAAA==.Manawurm:BAAALgAECgEJAQAAAA==.Mannanan:BAAALgAECgcJDgAAAA==.Marble:BAAALgAECgUJCAAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meatrocketxd:BAAALgAECgcJAQAAAA==.Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8xAAQRAAkJziCfEADCAgARAAkJziCfEADCAgAhAAIJPRBvTAB0AAAYAAEJhwzXOgAuAAAAAA==.Minyaura:BAAALgADCgQJBAAAAA==.Minyholy:BAAALgAECgQJBAAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Mirañda:BAAALgADCgEJAQAAAA==.Miridian:BAAALgAECgcJDwAAAA==.Miromoney:BAAALgADCgUJBQAAAA==.Mitsuri:BAAALgAECggJDgAAAA==.',
Mo='Moatie:BAAALgAECgYJDgAAAA==.Moogician:BAAALgAECgIJBgABLgAECgkJIAARAKchAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonsïnd:BAABLgAECn8rAAMNAAkJZA3jPQCSAQANAAkJZA3jPQCSAQAZAAIJehJ/NAB1AAAAAA==.Moonwren:BAAALgAECgkJAQAAAA==.Mooradin:BAAALgADCgQJAwAAAA==.Morgrin:BAAALgAECgQJBgAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAABLgAECn8iAAIaAAgJAhMIIACGAQAaAAgJAhMIIACGAQAAAA==.',
My='Mydira:BAAALgAECgkJDAAAAA==.Mysha:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalth:BAACLgAFFH8GAAINAAMJdQYeRgCYAAANAAMJdQYeRgCYAAAuAAQKfxkABA0ACQmnGKYUAJsCAA0ACQmnGKYUAJsCACIAAgn4B+VjADsAABAAAQmXCgOLACwAAAAA.Nalthexon:BAAALgAECgYJBgABLgAFFAMJBgANAHUGAA==.Navysis:BAAALgAECgMJAQAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neverender:BAAALgAECgUJBwAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECgkJGAAgANscAA==.',
Ni='Niavanith:BAAALgAECgYJEQAAAA==.Nights:BAAALgAECgcJEQABLgAFFAMJBgAhAKkSAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAACLgAFFH8OAAIFAAQJdB1YAgBcAQAFAAQJdB1YAgBcAQAuAAQKfz0AAwUACQkRI98AABcDAAUACQkRI98AABcDAAQABQnUFVEYAEQBAAAA.Nizo:BAABLgAECn8uAAINAAkJChx1DQDmAgANAAkJChx1DQDmAgAAAA==.',
No='Noblitz:BAAALgAFFAEJAwAAAA==.Novastrike:BAABLgAECn8mAAMLAAgJohfpPwCgAQALAAgJohfpPwCgAQAKAAgJ3wuKVQDUAAAAAA==.',
Ny='Nyrif:BAACLgAFFH8MAAIVAAMJZx3tHADsAAAVAAMJZx3tHADsAAAuAAQKfyIAAhUACQnzGo8PAAUCABUACQnzGo8PAAUCAAAA.',
Oj='Ojoon:BAAALgAECgcJEQAAAA==.',
Om='Omnisllash:BAAALgAFFAIJAwAAAA==.',
Or='Orisana:BAACLgAFFH8TAAMhAAQJoxu/DABQAQAhAAQJoxu/DABQAQARAAIJNxWTeQCQAAAuAAQKf04ABCEACQlCIRkFANMCABgACQnAGnkMAOUCACEACQneHxkFANMCABEABQmMGTR4AEIBAAAA.',
Pa='Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAABLgAFFH8YAAMEAAUJAQwYFgAcAQAEAAUJAQwYFgAcAQADAAEJlwiHXgA8AAAAAA==.',
Ph='Phoenìx:BAAALgAECgEJAgAAAA==.Phyter:BAAALgAECgIJBQAAAA==.',
Pi='Pillin:BAAALgAECgcJEwAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAABLgAECn8hAAMjAAkJcB0wFQBAAgAjAAkJcB0wFQBAAgAkAAEJ7AhATgA0AAAAAA==.Powerwordmoo:BAAALgAECgEJAQABLgAECgkJIAARAKchAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Prina:BAAALgADCgUJBQAAAA==.Provi:BAAALgAECggJDAAAAA==.',
Ps='Psyffe:BAAALgAECgUJCgAAAA==.Psyrge:BAAALgAECgUJBQAAAA==.',
Qu='Queue:BAABLgAECn86AAIVAAkJcw/wGACOAQAVAAkJcw/wGACOAQAAAA==.',
Re='Rebeccayaros:BAAALgAECgUJDwAAAA==.Redle:BAABLgAECn8aAAIMAAgJzQs+lgA7AQAMAAgJzQs+lgA7AQAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAECLgAFFH8PAAQhAAQJwxQRDwA+AQAhAAQJwxQRDwA+AQAYAAEJtgcQKgBIAAARAAEJFAOcnQA8AAAuAAQKfy8AAyEACQm6HmcHAKQCACEACQlXHWcHAKQCABgACAkSFgAeADYCAAAA.',
Ro='Rokkitok:BAAALgAECgcJEAAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
Ru='Rulnic:BAAALgAECgEJAQAAAA==.',
['Rà']='Ràwrshàk:BAAALgAECgYJCAAAAA==.',
['Rå']='Råwrshåk:BAABLgAECn8mAAIRAAkJqBriJgA5AgARAAkJqBriJgA5AgAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgABLgAFFAEJAQAUAAAAAA==.',
Se='Sea:BAACLgAFFH8fAAILAAYJ6h33CAAVAgALAAYJ6h33CAAVAgAuAAQKfyIAAgsACQmSIOYBAG4DAAsACQmSIOYBAG4DAAAA.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowaurora:BAAALgAECgkJDwAAAA==.Shadowrose:BAABLgAECn8xAAMZAAkJahkWCwD7AQAZAAgJuhcWCwD7AQANAAQJhQ1PdgDJAAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAABLgAECn8YAAIHAAkJuBRNMwAGAgAHAAkJuBRNMwAGAgAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAwAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAAUAAAAAA==.Shiemi:BAAALgAECgcJBQAAAA==.Shootingbo:BAAALgAECgEJAQAAAA==.Shunsui:BAACLgAFFH8IAAIHAAQJNQsWWAAJAQAHAAQJNQsWWAAJAQAuAAQKfy0AAwcACQlcGzUcAHUCAAcACQlcGzUcAHUCAAgAAQkAACRvADcAAAAA.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Silentomen:BAAALgADCgkJCQAAAA==.Siley:BAABLgAECn8YAAIgAAkJ2xzDFABrAgAgAAkJ2xzDFABrAgAAAA==.Sinnister:BAAALgAFFAIJAgAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgAECgYJCwAAAA==.',
Sl='Sleepytree:BAAALgAECgcJDwAAAA==.Slugo:BAAALgADCgcJCAAAAA==.',
Sn='Snail:BAAALgAECgMJAwAAAA==.Sneakytrix:BAABLgAFFH8FAAIaAAEJWxvMNQBSAAAaAAEJWxvMNQBSAAAAAA==.',
So='Sooner:BAACLgAFFH8SAAMXAAQJMx9ZQABiAQAXAAQJMx9ZQABiAQAlAAMJXRS/EwDOAAAuAAQKfxkAAyUABwl7HfEEAPwBACUABgl0IPEEAPwBABcABQkMHPiCAHwBAAAA.Sorcerix:BAAALgADCgQJBAAAAA==.Soror:BAAALgAECgIJAgAAAA==.',
Sq='Squeaky:BAAALgAECgcJEAAAAA==.',
St='Starar:BAAALgADCgkJDwAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJEAAAAA==.Sungodess:BAAALgAECgEJAQAAAA==.',
Sy='Syrupp:BAAALgAECgkJDgAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.Tayn:BAAALgAECgIJAgAAAA==.',
Te='Tealeaf:BAAALgAECgQJBAAAAA==.Temporary:BAAALgAECgIJAgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Thackery:BAAALgADCgMJBAAAAA==.Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
To='Tortus:BAAALgAECgEJAQAAAA==.Toxicrumor:BAAALgAFFAIJAgAAAA==.',
Tr='Triplenine:BAAALgAECgIJAgABLgAFFAgJHgABAG4bAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.Tsavø:BAAALgAECgQJBQAAAA==.',
Tu='Tucktoo:BAAALgAECgIJAwAAAA==.',
Ty='Tyundric:BAAALgADCgYJCgAAAA==.',
Un='Unholysage:BAACLgAFFH8NAAMcAAQJOQz/GwD8AAAcAAQJOQz/GwD8AAAWAAIJRAUrPABxAAAuAAQKfy8AAxwACQnmFvsUAB0CABwACQnmFvsUAB0CABYABAlICMlLAMIAAAAA.',
Uw='Uwurailme:BAABLgAECn8VAAQIAAcJNg8KMgDwAAAHAAYJcQxriwBCAQAIAAUJHAoKMgDwAAAGAAIJrRN5HQCGAAAAAA==.',
Va='Valenix:BAACLgAFFH8MAAMeAAMJNAiiJgCrAAAeAAMJNAiiJgCrAAAdAAMJSwrKPACQAAAuAAQKfx8AAx4ACQlmEOE+APYAAB4ABwlDEOE+APYAAB0ACAnrEcFkAMoAAAAA.Valkryi:BAAALgAECgEJAQAAAA==.Varys:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.Vaxîs:BAAALgAECgMJAwAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.Venetrazat:BAAALgAECgUJBgAAAA==.',
Vo='Vo:BAAALgAECgYJEgAAAA==.',
Vu='Vulasity:BAAALgAECgcJBwAAAA==.',
Wa='Warder:BAABLgAECn8cAAIjAAgJABdoIADmAQAjAAgJABdoIADmAQAAAA==.Warp:BAAALgAECgcJEwAAAA==.',
Wh='Whiteshaq:BAAALgAECgYJCwAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wiigo:BAAALgAECgYJBgAAAA==.Wincks:BAABLgAECn8YAAMIAAcJsRy9CwB1AQAIAAYJIB69CwB1AQAHAAUJNRYMeQBCAQAAAA==.',
Xa='Xana:BAAALgADCgUJBQABLgAFFAEJAwAUAAAAAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAABLgAECn8nAAICAAkJjxVNAgAvAgACAAkJjxVNAgAvAgAAAA==.Zackman:BAACLgAFFH8PAAIgAAQJRwfUKADVAAAgAAQJRwfUKADVAAAuAAQKfz0AAiAACQnfEn8YADgCACAACQnfEn8YADgCAAAA.',
Zh='Zhimer:BAAALgADCgIJAgAAAA==.',
Zi='Zinagos:BAAALgAECggJEQABLgAFFAMJDAAeADQIAA==.',
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
