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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Hunter-Survival','Warrior-Fury','Evoker-Devastation','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Protection','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Aberration:BAAALgAECgEJAgAAAA==.',
Ad='Adorraa:BAAALgAECgUJBgABLgAFFAEJAQABAAAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8gAAMCAAgJ3BfPCgDPAQACAAYJkxnPCgDPAQADAAIJdQ69PgCrAAAuAAQKfyEAAwIACQm1IUcCAFEDAAIACQm1IUcCAFEDAAMABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgADCgkJDAAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQAEAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAFFAQJBAAAAA==.',
Ai='Airali:BAACLgAFFH8IAAIFAAQJ+QUzTAD4AAAFAAQJ+QUzTAD4AAAuAAQKfxcAAwUACQn+E2tkALgBAAUACQn+E2tkALgBAAYAAwmJCNM3AGIAAAAA.Airedale:BAABLgAECn8jAAIHAAgJfhOuRQC4AQAHAAgJfhOuRQC4AQAAAA==.',
Ak='Akairo:BAABLgAECn8xAAMIAAkJACSCAgBBAwAIAAkJACSCAgBBAwAJAAgJrBGVJwBxAQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgYJBgABLgAFFAQJBgADALINAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderxl:BAABLgAECn8WAAMGAAYJAB1gFwBfAQAGAAYJAB1gFwBfAQAFAAUJWBUErwAEAQABLgAECggJAwABAAAAAA==.Aleybobwa:BAABLgAECn8fAAMKAAkJjhKdJgC/AQAKAAkJjhKdJgC/AQAFAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8nAAIKAAkJmxsHCwDHAgAKAAkJmxsHCwDHAgAAAA==.Amulius:BAABLgAECn81AAIFAAkJyyXnAwBOAwAFAAkJyyXnAwBOAwAAAA==.',
An='Anderdingus:BAAALgADCgUJBQAAAA==.Andormath:BAAALgAECgQJBgAAAA==.Andramedae:BAABLgAECn8uAAMLAAkJixTgIAAtAgALAAkJixTgIAAtAgAMAAYJCw0DQgDpAAAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgADCgkJCQAAAA==.Anoki:BAABLgAECn85AAMNAAkJ/xroEgCdAgANAAkJ/xroEgCdAgAOAAEJgQuXnwAnAAAAAA==.',
Ao='Aolus:BAACLgAFFH8RAAIMAAQJuxhnGgAcAQAMAAQJuxhnGgAcAQAuAAQKfxsAAgwACQkVHDETAHsCAAwACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJBAABAAAAAA==.Arcaina:BAABLgAECn8fAAIPAAgJHAnKkQA5AQAPAAgJHAnKkQA5AQAAAA==.Ares:BAAALgADCgcJBwABLgAECgkJLAAQAJEWAA==.Arez:BAABLgAECn8sAAIQAAkJkRZnMAALAgAQAAkJkRZnMAALAgAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJOgARALclAA==.Artèmís:BAABLgAECn8nAAISAAkJDSWaAgAQAwASAAkJDSWaAgAQAwAAAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgADCgkJGgAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athenä:BAAALgAECgMJBAAAAA==.',
Au='Aura:BAAALgAFFAEJAQAAAA==.',
Az='Azaekho:BAABLgAECn8kAAINAAkJcxQIKgDmAQANAAkJcxQIKgDmAQAAAA==.',
Ba='Baalzak:BAAALgADCgYJBQAAAA==.Backfliphoe:BAAALgAECgcJBwAAAA==.Badoosh:BAABLgAECn8oAAITAAgJcB2aGACHAgATAAgJcB2aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn8tAAQUAAgJliBOAgCQAgAUAAgJliBOAgCQAgADAAMJ5BD7TACdAAACAAEJMAvxOAAtAAAAAA==.Baliw:BAAALgADCgUJBAAAAA==.Balto:BAAALgADCgMJAwAAAA==.',
Bb='Bbl:BAECLgAFFH8ZAAIOAAUJYxgRFwA3AQAOAAUJYxgRFwA3AQAuAAQKfyUAAg4ACQnWIFgKAPACAA4ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8PAAIPAAQJ2xFGKwAIAQAPAAQJ2xFGKwAIAQAuAAQKfyMAAg8ACQnDGZo7AIgCAA8ACQnDGZo7AIgCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAABLgAECn8YAAIFAAkJHxGxTwDBAQAFAAkJHxGxTwDBAQAAAA==.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAQJDgAFADoaAA==.',
Bi='Bieorne:BAABLgAECn85AAIVAAkJtR9ZEADYAgAVAAkJtR9ZEADYAgAAAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIQAAQJXQtQUgAOAQAQAAQJXQtQUgAOAQAuAAQKfxQAAhAACQnuFEYwAAsCABAACQnuFEYwAAsCAAAA.Bloodwrath:BAAALgAECgIJBAAAAA==.Blueveins:BAAALgAECgcJCgAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIQAAIJ5R5xfwCkAAAQAAIJ5R5xfwCkAAAuAAQKfxgAAxAACQnvHP4PAPoCABAACQnvHP4PAPoCABYAAQkAAFJIAAAAAAEuAAUUAwkIAAoAaxsA.Boondocks:BAABLgAECn8xAAMXAAkJtB0lDAB3AQAXAAUJ8CElDAB3AQAQAAUJ3hg+YQByAQAAAA==.',
Br='Braca:BAAALgADCgEJAgAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8ZAAIYAAkJLQ8kIQCNAQAYAAkJLQ8kIQCNAQABLgAECgkJKQAZAJ4bAA==.Brielle:BAABLgAECn8tAAIHAAkJuBd7JAA5AgAHAAkJuBd7JAA5AgAAAA==.Brokenbranch:BAAALgAECgYJEgAAAA==.Brudene:BAABLgAECn8UAAITAAcJFRF2VABZAQATAAcJFRF2VABZAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Bubbletruble:BAAALgAECgYJBgAAAA==.Buddylock:BAABLgAECn8iAAIQAAkJmgmibwBQAQAQAAkJmgmibwBQAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8QAAIaAAYJ9BvqCABvAQAaAAYJ9BvqCABvAQAuAAQKfx0AAhoACAk5I0EFADEDABoACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn88AAMbAAkJHR91BwAKAwAbAAkJHR91BwAKAwAaAAYJMRkfLABFAQABLgAECgkJJwASAA0lAA==.',
Ca='Caboozles:BAABLgAECn87AAIHAAkJCRbDMgD7AQAHAAkJCRbDMgD7AQAAAA==.Caliopia:BAABLgAECn8xAAMOAAkJvBTFGwDqAQAOAAkJvBTFGwDqAQANAAYJYQpzZgAJAQAAAA==.Caliper:BAAALgAECgEJAQAAAA==.Caplyta:BAAALgADCgYJBgABLgAFFAUJEgAJACscAA==.Captnhuntcat:BAAALgAECggJEwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8oAAITAAkJEBQYHQDyAQATAAkJEBQYHQDyAQAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8bAAMcAAkJaR2cEAABAgAcAAkJaR2cEAABAgAVAAQJJA83tQD2AAAAAA==.Chemistree:BAABLgAECn8oAAILAAkJORGFKwDpAQALAAkJORGFKwDpAQAAAA==.Chillout:BAABLgAECn8nAAIPAAkJvw2ZWQC4AQAPAAkJvw2ZWQC4AQAAAA==.Chillums:BAABLgAECn8cAAIQAAcJ4iP7GgCzAgAQAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgQJBwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Ci='Cillah:BAAALgAECgEJAQABLgAECgkJMAATAJcfAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgcJCwABAAAAAA==.',
Co='Codeblue:BAAALgADCgYJBwAAAA==.Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8dAAIKAAkJYg5sJQDGAQAKAAkJYg5sJQDGAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Cy='Cy:BAAALgAECgYJCQABLgAECgYJFgAQAI4RAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJFQAVAB4bAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Damrek:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn8wAAMdAAkJnyRHAQBaAwAdAAkJnyRHAQBaAwAeAAkJuh/eDgC5AgAAAA==.Darà:BAAALgADCgkJFgABLgAECggJKgAMANEPAA==.Dashyll:BAAALgAECgMJBAAAAA==.Davyfknjones:BAABLgAECn8aAAIHAAgJTxjaLQAOAgAHAAgJTxjaLQAOAgAAAA==.Daynia:BAAALgAECgYJEAAAAA==.',
De='Deadbolt:BAAALgAECgYJBgAAAA==.Deadlegslul:BAABLgAECn8fAAIHAAgJOR1NIwA/AgAHAAgJOR1NIwA/AgAAAA==.Deadlegsmd:BAAALgAECgQJCAAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJBwAAAA==.Deathmono:BAAALgAECgYJCQAAAA==.Deathshark:BAACLgAFFH8RAAIcAAQJAhygEABBAQAcAAQJAhygEABBAQAuAAQKfy0AAhwACQnSHb0KAGwCABwACQnSHb0KAGwCAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8fAAIPAAcJmQhLuAD4AAAPAAcJmQhLuAD4AAABLgAECggJMAANABARAA==.Demeter:BAABLgAECn86AAIGAAkJ4xLcDQDMAQAGAAkJ4xLcDQDMAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denalli:BAAALgADCgIJAgAAAA==.Denarien:BAAALgAECgkJDAAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJKQAZAJ4bAA==.Devouress:BAABLgAECn8ZAAIeAAgJDhgeNgDXAQAeAAgJDhgeNgDXAQAAAA==.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIfAAcJGQn9IQAuAQAfAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn8pAAMTAAgJIxj/HADyAQATAAgJ8xf/HADyAQAfAAEJzhwOQwBOAAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAQJDwAYAPMJAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAIDAAgJYhrwGQDtAQADAAgJYhrwGQDtAQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgABAAAAAA==.Draggnar:BAAALgAECgYJEgAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAABLgAECn8cAAMSAAkJnQtjFwDYAQASAAkJ9gpjFwDYAQAgAAcJeAZ+HAC2AAAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJDwAOAEwhAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMMAAkJnBhBGQA9AgAMAAgJsBlBGQA9AgALAAcJ4BiYPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn86AAIRAAkJtyVQAABiAwARAAkJtyVQAABiAwAAAA==.',
Eb='Ebojager:BAABLgAECn8+AAIeAAkJiRlJGwBcAgAeAAkJiRlJGwBcAgAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJJwASAA0lAA==.',
Ei='Eibon:BAACLgAFFH8XAAIVAAcJTRd6CgA+AgAVAAcJTRd6CgA+AgAuAAQKfx4AAhUACQnNIakUAAADABUACQnNIakUAAADAAAA.Einfreren:BAAALgAECgQJBAAAAA==.',
El='Elliiria:BAAALgAECgQJBAAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAABLgAECn8ZAAIhAAcJ5RN3IAClAQAhAAcJ5RN3IAClAQAAAA==.Elwarrioro:BAAALgAECgYJDwAAAA==.',
Em='Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8oAAIiAAkJzxQnCAAqAgAiAAkJzxQnCAAqAgAAAA==.',
En='Enobia:BAABLgAECn8jAAMWAAcJsxO9DABVAQAWAAcJsxO9DABVAQAQAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgcJCwABAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgQJBQABLgAECgkJLAAQAJEWAA==.Eskath:BAABLgAECn8hAAIQAAgJXh9sIQBQAgAQAAgJXh9sIQBQAgABLgAECgkJKQAZAJ4bAA==.Essential:BAACLgAFFH8IAAIFAAQJNguyRgAFAQAFAAQJNguyRgAFAQAuAAQKfx0AAgUACAnpErtsAHsBAAUACAnpErtsAHsBAAAA.',
Et='Eternalpain:BAAALgAECgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8hAAIaAAYJfxPlNgAPAQAaAAYJfxPlNgAPAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCQAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECggJHQAYAJoOAA==.Ferrara:BAACLgAFFH8gAAQgAAgJDyHDDABgAQAgAAcJkx7DDABgAQASAAIJhSHbHQDMAAAHAAEJtx+1HwBiAAAuAAQKfyAABCAACQnRIykGADoDACAACQmLIykGADoDAAcAAQn1I6ywAGIAABIAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAABLgAECn8XAAIOAAYJRiFuIAANAgAOAAYJRiFuIAANAgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJOgAMAHkjAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8UAAIIAAgJ6BZXAQB5AgAIAAgJ6BZXAQB5AgAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgAECgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgABAAAAAA==.Frostednip:BAACLgAFFH8PAAMVAAQJJhpfQwBKAQAVAAQJ3RlfQwBKAQAjAAIJoRKpFQCXAAAuAAQKfyQAAyMACQnaIBQIAOMBABUACQm/IJU3AA4CACMABwmhGxQIAOMBAAAA.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8HAAQDAAMJ9gQlQAClAAADAAMJ9gQlQAClAAACAAMJvQdiHgCiAAAUAAEJlwEsDABCAAAuAAQKfxUAAwIACQlTE2YSABkCAAIACQlTE2YSABkCAAMAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECgYJBgAAAA==.Galnarn:BAACLgAFFH8iAAIYAAcJyyBjBAAeAgAYAAcJyyBjBAAeAgAuAAQKfyEAAhgACQlkHfgNALQCABgACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Garious:BAAALgAECgcJBwABLgAFFAUJDAAVAIsgAA==.Garjingo:BAAALgAECgUJBgABLgAECggJLQAUAJYgAA==.Garlicbae:BAAALgAECgYJEgAAAA==.Garwulf:BAAALgAECgkJEAAAAA==.',
Ge='Gefaustet:BAABLgAECn8xAAMfAAkJqxmqCgAwAgAfAAkJqxmqCgAwAgAEAAEJawiocQAoAAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgcJCQAAAA==.',
Go='Goatcheesè:BAAALgAECgIJBAAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAFFAEJAQAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAABLgAECn8VAAMYAAgJhgZNNwAPAQAYAAgJhgZNNwAPAQAaAAMJHgJHmAAqAAAAAA==.Grayes:BAABLgAECn8fAAIZAAYJMQhgOQCYAAAZAAYJMQhgOQCYAAABLgAECggJFQAYAIYGAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hallowshade:BAABLgAECn8XAAIkAAcJFhnlJQDKAQAkAAcJFhnlJQDKAQAAAA==.Hardran:BAABLgAECn8cAAIFAAcJYgz/ogAXAQAFAAcJYgz/ogAXAQAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgQJBwAAAA==.Hatreddyes:BAAALgADCgYJCwABLgAECggJCQABAAAAAA==.Hatredyes:BAAALgAECggJCQAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECggJCQABAAAAAA==.',
He='Heatedsoul:BAAALgAECgEJAQAAAA==.Helare:BAABLgAECn8XAAIMAAkJ2xjbDwBLAgAMAAkJ2xjbDwBLAgAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8nAAIlAAkJrQ1GEQCAAQAlAAkJrQ1GEQCAAQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgEJAQABLgAECgkJJQAPABEhAA==.Horsegirl:BAAALgAECgEJAgAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Huffmetoes:BAEALgADCgUJBQABLgAECgkJPAAIAIMZAA==.Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECggJCQAAAA==.Huulrokk:BAAALgADCgkJCwABLgAECgYJCwABAAAAAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJJwAKAJsbAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwABAAAAAA==.Idlewild:BAEALgADCgkJDAABLgAECgYJFAAOAAcNAA==.',
If='Iforgotnaaru:BAABLgAECn8XAAMNAAcJ4QslZwAGAQANAAcJ4QslZwAGAQAOAAQJtQqkXgCsAAAAAA==.',
Ik='Ikedizzy:BAAALgAECgEJAQABLgAECgMJBAABAAAAAA==.Ikeslice:BAAALgAECgMJBAAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAACLgAFFH8HAAIOAAMJsSCsHQAPAQAOAAMJsSCsHQAPAQAuAAQKfywAAg4ACAl6JGUIAMQCAA4ACAl6JGUIAMQCAAAA.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAITAAgJxxOHKACkAQATAAgJxxOHKACkAQAAAA==.',
In='Innex:BAABLgAECn8nAAIVAAkJGx+lJgBUAgAVAAkJGx+lJgBUAgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECgkJJwAVABsfAA==.Innexvoker:BAABLgAECn8YAAIDAAgJag+cLQBnAQADAAgJag+cLQBnAQABLgAECgkJJwAVABsfAA==.Inpesca:BAAALgADCgUJBQABLgAFFAQJBgADALINAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgYJCwAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8eAAIgAAcJuQ5+EQAtAQAgAAcJuQ5+EQAtAQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8oAAINAAgJyRKaRAB/AQANAAgJyRKaRAB/AQAAAA==.Itzpie:BAABLgAECn81AAIPAAkJNxYnQQACAgAPAAkJNxYnQQACAgAAAA==.',
Ja='Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8gAAMVAAcJPBBaiAA/AQAVAAcJPBBaiAA/AQAcAAUJcQeUPQCBAAAAAA==.Jakeakuma:BAABLgAECn8UAAIQAAkJBAwlXwCsAQAQAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8aAAImAAUJoQc2FQDBAAAmAAUJoQc2FQDBAAAAAA==.Jasonborne:BAAALgAECgQJBAAAAA==.Jaynne:BAAALgADCgcJCAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgAECgcJBgAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn8+AAIYAAkJrx/uBQDOAgAYAAkJrx/uBQDOAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIaAAgJGiFcCAD0AgAaAAgJGiFcCAD0AgABLgAFFAQJBAABAAAAAA==.Junfan:BAAALgAECgcJAwAAAA==.',
['Jà']='Jàckblack:BAAALgAECgQJCAAAAA==.',
Ka='Kaashaa:BAACLgAFFH8MAAIHAAQJFxd+IwBSAQAHAAQJFxd+IwBSAQAuAAQKf0AAAgcACQnLIW4LAOUCAAcACQnLIW4LAOUCAAAA.Kaelsgf:BAAALgAECgcJBwAAAA==.Kahllan:BAABLgAECn8qAAMMAAgJ0Q9ZKgBlAQAMAAgJ0Q9ZKgBlAQALAAEJLhTWvAA8AAAAAA==.Kahnigitt:BAABLgAECn8VAAIVAAYJXAomuQDwAAAVAAYJXAomuQDwAAAAAA==.Kalsifire:BAAALgADCgcJCgAAAA==.Kataltoholic:BAABLgAECn8aAAIPAAYJOAFYGQFcAAAPAAYJOAFYGQFcAAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIeAAYJCxp5UAC1AQAeAAYJCxp5UAC1AQAAAA==.Kaýhás:BAAALgADCgYJBgAAAA==.',
Ke='Kelinïsha:BAABLgAECn8pAAIPAAgJJQqnmAAtAQAPAAgJJQqnmAAtAQAAAA==.Kelynna:BAABLgAECn8pAAIIAAgJDhzhDwBUAgAIAAgJDhzhDwBUAgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJBQAAAA==.',
Kh='Khaodemus:BAAALgAECggJCQAAAA==.Khellder:BAAALgADCgYJBgABLgAECgkJEQABAAAAAA==.Khelldyr:BAAALgAECggJCAABLgAECgkJEQABAAAAAA==.Khellrond:BAAALgAECgkJEQAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiiras:BAABLgAECn8vAAIPAAgJ9A10eABtAQAPAAgJ9A10eABtAQAAAA==.Kimbodh:BAACLgAFFH8YAAIeAAUJOSTCGgCgAQAeAAUJOSTCGgCgAQAuAAQKfyYAAh4ACAkOJK8MAM4CAB4ACAkOJK8MAM4CAAEuAAEKAwkBAAEAAAAA.Kimoora:BAAALgAECgIJAgAAAA==.Kimshady:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8uAAIeAAkJjxClQQCsAQAeAAkJjxClQQCsAQAAAA==.',
Kl='Klefthoof:BAABLgAECn8wAAMNAAgJEBGyNwC2AQANAAgJEBGyNwC2AQAOAAEJUQSeqAAfAAAAAA==.',
Ko='Kodey:BAABLgAECn8eAAIWAAgJsROlCQCQAQAWAAgJsROlCQCQAQABLgAFFAMJCwAWANgHAA==.Kordy:BAAALgAECgkJAQAAAA==.Korey:BAAALgAECgEJAQAAAA==.',
Kr='Kraniah:BAAALgAECgYJCwAAAA==.Krimboz:BAABLgAECn8uAAIQAAkJ+hlMHQBmAgAQAAkJ+hlMHQBmAgAAAA==.Krimbrouge:BAAALgAECgYJCAAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8rAAISAAgJXhotDwAsAgASAAgJXhotDwAsAgAAAA==.Krìsta:BAACLgAFFH8GAAMXAAIJ7QKlDQB3AAAXAAIJ7QKlDQB3AAAQAAEJ8QBwvAAxAAAuAAQKfx4AAxcACAncDFgNAGABABcABwleDlgNAGABABAABwknBOuzANIAAAAA.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ7wkOMwArAQAJAAgJ7wkOMwArAQAIAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgAECgYJCwAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8KAAIJAAQJUxW5EwAwAQAJAAQJUxW5EwAwAQAuAAQKfxgAAgkACQlvHb4XACYCAAkACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8sAAMHAAgJ6R8rIgBFAgAHAAgJ6R8rIgBFAgAgAAUJGxE4FQD6AAAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAAALgAECgYJEgAAAA==.Leonarde:BAACLgAFFH8PAAMHAAQJKBnpMgAwAQAHAAQJIBnpMgAwAQAgAAMJ2Q/RFQDuAAAuAAQKfyIABCAACQkZGb8gACACACAACAkSF78gACACAAcABQl/GMBgAGwBABIAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIQAAYJjhEniQAdAQAQAAYJjhEniQAdAQAAAA==.Leyla:BAAALgADCgkJCQAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn80AAIaAAkJbhbEEwAJAgAaAAkJbhbEEwAJAgAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgYJDwAAAA==.',
Ll='Llevanya:BAABLgAECn88AAIFAAkJUxDMTwDAAQAFAAkJUxDMTwDAAQAAAA==.Llinaigh:BAABLgAECn8ZAAIHAAkJgxXtMgD6AQAHAAkJgxXtMgD6AQAAAA==.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAgABLgAECgkJMAATAJcfAA==.Lomu:BAABLgAECn8pAAQZAAkJnhtUCABMAgAZAAkJnhtUCABMAgALAAEJ7Q5JzwAvAAAMAAEJigSWkAAhAAAAAA==.Loredalso:BAAALgAECgEJAQAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAFABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
['Lê']='Lêdrollan:BAAALgAECgIJAgABLgAFFAQJCgAJAFMVAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Magicdreams:BAABLgAECn80AAIMAAkJNAnjKgBiAQAMAAkJNAnjKgBiAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIVAAYJMRUHowA6AQAVAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIcAAkJFhshCwBjAgAcAAkJFhshCwBjAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAAALgAECgcJCAAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwABAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIkAAkJ0R1FDwAgAgAkAAkJ0R1FDwAgAgAAAA==.Materia:BAAALgAECgEJAQAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJEhH4KgB3AQADAAgJwBD4KgB3AQACAAYJFQtdKQAoAQAUAAMJjw8OFgCdAAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8xAAIFAAkJKCGfDADrAgAFAAkJKCGfDADrAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMiAAkJGxU2BgCWAgAiAAkJGxU2BgCWAgAOAAgJyg+CPQAiAQAAAA==.',
Me='Meerchi:BAABLgAECn8xAAMPAAkJCBkcMwA0AgAPAAkJCBkcMwA0AgAnAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meiriie:BAAALgADCgQJBAAAAA==.Meowkai:BAAALgAECgYJBwABLgAECgkJJwASAA0lAA==.Mesthos:BAAALgAECgcJDAABLgAECgkJKAARACwmAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAIDAAgJlBKOGgD2AQADAAgJlBKOGgD2AQAAAA==.',
Mi='Miciah:BAAALgAECgQJBAAAAA==.Mickieta:BAABLgAECn8xAAIFAAkJwh+kFgClAgAFAAkJwh+kFgClAgAAAA==.Microsurge:BAACLgAFFH8HAAIPAAQJ4AjNYAANAQAPAAQJ4AjNYAANAQAuAAQKfx0AAg8ACAkiHdslANsCAA8ACAkiHdslANsCAAAA.Mikalau:BAABLgAECn8oAAIHAAgJohPfPgDOAQAHAAgJohPfPgDOAQAAAA==.Mikaluu:BAABLgAECn8ZAAIQAAYJmQUguADLAAAQAAYJmQUguADLAAAAAA==.Miqkail:BAAALgAECggJCgABLgAECgkJKAARACwmAA==.Missteek:BAAALgAECgUJCgABLgAECggJLQAUAJYgAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8PAAIJAAQJpQ/HGAANAQAJAAQJpQ/HGAANAQAuAAQKfyAAAwkACQnXHeQOAJUCAAkACQnXHeQOAJUCAAgAAwklBoFqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJJwAKAJsbAA==.Mognel:BAABLgAECn82AAIQAAkJxxx6JQA7AgAQAAkJxxx6JQA7AgAAAA==.Mogrungar:BAABLgAECn8jAAINAAkJEQ6ONQC/AQANAAkJEQ6ONQC/AQAAAA==.Moistdk:BAAALgAECgEJAQAAAA==.Moisten:BAABLgAECn8eAAIOAAkJQyDuBgDcAgAOAAkJQyDuBgDcAgAAAA==.Mokuo:BAAALgAECgUJBQAAAA==.Monklee:BAAALgAECgEJAgAAAA==.Moomootus:BAABLgAECn8kAAMFAAkJbheUSQDSAQAFAAgJdhaUSQDSAQAKAAQJ/B5VOABUAQAAAA==.Morgalea:BAAALgAECgcJAQAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIaAAgJRyBsDQClAgAaAAgJRyBsDQClAgABLgAECggJGQAeAA4YAA==.Mystynight:BAAALgAECgYJCgAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8lAAIOAAgJEA9GNQBKAQAOAAgJEA9GNQBKAQAAAA==.Naggs:BAAALgAECgkJCAAAAA==.Nagini:BAABLgAECn8fAAIQAAgJdwgmfQA0AQAQAAgJdwgmfQA0AQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn88AAMIAAkJgxnLGQDlAQAIAAcJGRnLGQDlAQAJAAkJtBH/NAAhAQAAAA==.Nietzcha:BAAALgAECgMJBAAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAABLgAECn8kAAMMAAgJ7RbjGQDjAQAMAAgJ7RbjGQDjAQAlAAUJRw0JLwB/AAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgcJDwAAAA==.Nioh:BAABLgAECn8iAAIeAAkJxRbNKgAIAgAeAAkJxRbNKgAIAgAAAA==.',
No='Noodles:BAABLgAECn8nAAIeAAgJnwiDigDtAAAeAAgJnwiDigDtAAAAAA==.Nordrydd:BAAALgAECgYJBgABLgAFFAYJFgAbACQZAA==.Nordrydsh:BAAALgAECgQJBQABLgAFFAYJFgAbACQZAA==.',
Nu='Nuggs:BAABLgAECn8YAAIlAAkJzBDyDQCzAQAlAAkJzBDyDQCzAQAAAA==.Nuhpie:BAACLgAFFH8XAAMEAAcJhw4bHQDYAAAEAAQJugsbHQDYAAATAAMJUxE1LgDXAAAuAAQKfx4AAwQACQlfHS4cAGEBAAQABQmuGi4cAGEBABMABQlsHCpFABkBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIVAAkJax/AFQCyAgAVAAkJax/AFQCyAgAAAA==.',
Od='Odelay:BAAALgADCgEJAQAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8iAAINAAgJ1iNvAAAJAwANAAgJ1iNvAAAJAwAuAAQKfycAAw0ACQlvJUsAAM8DAA0ACQlvJUsAAM8DAA4AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopositive:BAAALgADCgYJBgAAAA==.Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Orgarrot:BAAALgADCgYJBgABLgAECggJCQABAAAAAA==.Oricelle:BAABLgAECn8oAAIeAAkJRRbIJQAhAgAeAAkJRRbIJQAhAgAAAA==.Oridis:BAAALgAECgkJBwAAAA==.Oryon:BAEBLgAECn8xAAIXAAkJQhTqBgDmAQAXAAkJQhTqBgDmAQAAAA==.',
Ov='Ovarb:BAABLgAECn8hAAIcAAkJkRhvDwD4AQAcAAkJkRhvDwD4AQAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDQAAAA==.Palasexo:BAAALgAECgUJBQABLgAECgcJCAABAAAAAA==.Palldude:BAAALgADCgQJBQAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Peachie:BAAALgADCgEJAQAAAA==.Pesti:BAACLgAFFH8XAAIkAAMJoB3AGwAdAQAkAAMJoB3AGwAdAQAuAAQKf0sAAiQACQkMI2oCACYDACQACQkMI2oCACYDAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8+AAINAAkJQiMuAwB6AwANAAkJQiMuAwB6AwAAAA==.',
Pi='Pissedwolf:BAAALgAECgUJBgAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8eAAIYAAgJCRBfJwBjAQAYAAgJCRBfJwBjAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAACLgAFFH8MAAIPAAQJVhOxSwA4AQAPAAQJVhOxSwA4AQAuAAQKf0cABA8ACQkJIp4LAAgDAA8ACQmIIZ4LAAgDACgABQnyFiQMABABACcAAQmjELsQADIAAAAA.Proctologist:BAABLgAECn8rAAMYAAkJDRk4EAApAgAYAAkJ6Rc4EAApAgAaAAQJYRPIPAD0AAAAAA==.Proserpìne:BAABLgAECn8xAAIeAAgJEQqRcQAkAQAeAAgJEQqRcQAkAQAAAA==.',
Ps='Psychojester:BAACLgAFFH8MAAIiAAQJjRTSBwAkAQAiAAQJjRTSBwAkAQAuAAQKf0MAAiIACQk2IcgBAAMDACIACQk2IcgBAAMDAAAA.Psylir:BAAALgAECgQJDgAAAA==.Psypra:BAAALgAECgUJBQAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIPAAUJihsxqwANAQAPAAUJihsxqwANAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAACLgAFFH8FAAIPAAIJDQ8cjgCUAAAPAAIJDQ8cjgCUAAAuAAQKfz8AAw8ACQkLIUoNAPsCAA8ACQkLIUoNAPsCACgAAQmXIHkZAEwAAAEuAAUUBQkaAAcAQh4A.',
Ra='Raijyu:BAABLgAECn84AAMIAAkJBx8cBQAZAwAIAAkJBx8cBQAZAwAJAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJNgAMAM8WAA==.Rainstormin:BAABLgAECn82AAMMAAkJzxYqEwAlAgAMAAkJzxYqEwAlAgAZAAYJxgmZNgClAAAAAA==.Rakarra:BAABLgAECn8bAAMLAAgJ2wtoTABKAQALAAgJ2wtoTABKAQAMAAcJYQcPTQD2AAAAAA==.Ranalia:BAAALgADCgcJBwAAAA==.Rawrstance:BAABLgAECn8xAAMcAAkJ1RnbGAB/AQAVAAcJoRxjZwCEAQAcAAkJXw/bGAB/AQABLgADCgcJCwABAAAAAA==.Razgrize:BAACLgAFFH8FAAIPAAIJ3hGRiQCbAAAPAAIJ3hGRiQCbAAAuAAQKfysAAg8ACQmcGu4jAHcCAA8ACQmcGu4jAHcCAAAA.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgADAGIaAA==.Reeshan:BAABLgAECn8fAAMFAAkJ1yNKCwD3AgAFAAkJ1yNKCwD3AgAKAAIJaxQ7bABnAAAAAA==.Reilin:BAAALgAECgcJCwAAAA==.Remsham:BAABLgAECn8nAAIiAAkJxg2SDQC7AQAiAAkJxg2SDQC7AQAAAA==.Reniel:BAAALgAECgYJBgABLgAECgkJLgAeAI8QAA==.Renwyck:BAABLgAECn8oAAIRAAkJLCY+AABrAwARAAkJLCY+AABrAwAAAA==.Revengemoon:BAACLgAFFH8RAAIFAAQJsxISOgAgAQAFAAQJsxISOgAgAQAuAAQKfyMAAgUACQmVGsApAH4CAAUACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgABAAAAAA==.Ringberg:BAACLgAFFH8IAAIKAAMJaxtBJgDaAAAKAAMJaxtBJgDaAAAuAAQKfxcAAwoABwlSH18WAEECAAoABwlSH18WAEECAAUAAwmmFET0AKYAAAAA.',
Ro='Robane:BAAALgAECgUJDwAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Rockette:BAAALgADCgYJBgAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn8yAAMNAAkJxBpGEgCjAgANAAkJxBpGEgCjAgAiAAgJiiLqBQBoAgAAAA==.',
Ru='Rubidea:BAAALgADCgQJBAAAAA==.Ruckus:BAEALgAECgYJEQABLgAECgYJFAAOAAcNAA==.Ruder:BAAALgAECgMJBAABLgAECggJCQABAAAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJxBtnEQBzAgAJAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgADCgcJCwAAAA==.Sandkat:BAABLgAECn8/AAITAAkJOSInBQD+AgATAAkJOSInBQD+AgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgAECgIJAgAAAA==.Saraelin:BAABLgAFFH8GAAIQAAIJ6wDPqwBLAAAQAAIJ6wDPqwBLAAAAAA==.Saray:BAAALgAECgcJEgAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEwATAO4QAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDgAAAA==.Serahstia:BAABLgAECn8eAAIPAAgJ9xWHWgC1AQAPAAgJ9xWHWgC1AQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shadowmeld:BAAALgAECgEJAQAAAA==.Shadysadie:BAAALgAECgUJBQAAAA==.Shaiy:BAAALgAECgcJEAAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwABAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAAALgAECgUJDAAAAA==.Shirtles:BAABLgAECn8YAAIOAAYJggNLZwCSAAAOAAYJggNLZwCSAAAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgUJCQAAAA==.Shèp:BAABLgAECn8ZAAIKAAgJFhEEKwCiAQAKAAgJFhEEKwCiAQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIOAAUJ/hmfAwCvAQAOAAUJ/hmfAwCvAQABLgAFFAYJDgASACUWAA==.Siffrin:BAAALgAECgIJAgAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8lAAMQAAgJnhUzawBaAQAQAAYJ0hIzawBaAQAXAAUJJRaeFgDrAAABLgAECggJJQADAJQSAA==.Sinkingship:BAAALgAECgUJBQAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8dAAIcAAkJuh9wBQDAAgAcAAkJuh9wBQDAAgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sliy:BAAALgAECgIJAgAAAA==.Sloothe:BAAALgADCgQJBAAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8WAAIFAAkJgRqVLgAtAgAFAAkJgRqVLgAtAgAAAA==.',
Sp='Sprodage:BAABLgAECn8xAAIKAAgJShfdHwDtAQAKAAgJShfdHwDtAQAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAABAAAAAA==.Stanil:BAABLgAECn8lAAMHAAgJiAjIZgBeAQAHAAgJiAjIZgBeAQAgAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDAAAAA==.Stellare:BAABLgAECn8wAAIdAAkJHRe5DgAZAgAdAAkJHRe5DgAZAgAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Stinklines:BAAALgAECgEJAgABLgAECggJLQAUAJYgAA==.Strangetame:BAAALgADCgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEwAAAA==.',
Su='Suetonius:BAACLgAFFH8JAAIVAAQJIxugNgBmAQAVAAQJIxugNgBmAQAuAAQKfxMAAxUACAlXJDQOAOkCABUACAlXJDQOAOkCACMAAgk4E2coAFcAAAAA.Suguru:BAAALgAECggJCQAAAA==.Sungsuf:BAAALgADCgQJBAAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8rAAIPAAkJaBpeMQA8AgAPAAkJaBpeMQA8AgAAAA==.Suraschi:BAAALgAECgYJBgABLgAECgkJKwAPAGgaAA==.',
Sv='Svelda:BAABLgAECn8fAAMJAAYJrQvlPwDsAAAJAAYJrQvlPwDsAAAhAAUJmAUVSgCuAAAAAA==.',
Sw='Swisscake:BAABLgAECn86AAIMAAkJeSPvAgAzAwAMAAkJeSPvAgAzAwAAAA==.',
Sy='Sylain:BAAALgAECgYJEgABLgAECgkJFQAkAKEKAA==.Synwav:BAAALgADCgEJAQAAAA==.',
Ta='Tannatax:BAABLgAECn8tAAINAAkJZQa7UQBNAQANAAkJZQa7UQBNAQAAAA==.Tashah:BAAALgADCgIJAgAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAABAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMPAAkJnBUrTQDcAQAPAAkJnBUrTQDcAQAnAAEJGgELFAAKAAAAAA==.Thewretch:BAABLgAECn85AAIQAAkJhyL8BQAmAwAQAAkJhyL8BQAmAwAAAA==.Thibble:BAAALgADCgYJBgAAAA==.Thumpthump:BAABLgAECn8nAAQSAAkJQBjpEQAOAgAgAAYJwx6nIgARAgASAAkJMhDpEQAOAgAHAAEJqQ6mCwE5AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEBLgAECn8UAAIOAAYJBw11TADnAAAOAAYJBw11TADnAAAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAABLgAECn8cAAIHAAgJJhaLNgDsAQAHAAgJJhaLNgDsAQAAAA==.',
To='Toastnbutta:BAABLgAECn8mAAILAAkJ9xldFgCBAgALAAkJ9xldFgCBAgAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmUMQBcAgAFAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgYJBwAAAA==.Traumatism:BAAALgAECgYJCQAAAA==.Trevor:BAABLgAECn8/AAImAAkJdxdLBABAAgAmAAkJdxdLBABAAgAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAACLgAFFH8HAAMlAAMJIhFlDADFAAAlAAMJjQtlDADFAAAZAAEJXBlMKABOAAAuAAQKfxYAAxkABwlfHAcVAIoBABkABgk0HAcVAIoBACUABQmGG/EXAC0BAAEuAAUUBAkRABwAAhwA.Tsura:BAAALgAECgMJAwAAAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.',
Un='Unclepeepers:BAACLgAFFH8RAAIbAAQJ4iBwFwBrAQAbAAQJ4iBwFwBrAQAuAAQKfy4AAxoACQkPIwcOAFECABoACAmOIgcOAFECABsACQm0GxUeAAECAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAABLgAECn8XAAIVAAcJ3QsOtwDzAAAVAAcJ3QsOtwDzAAAAAA==.',
Ur='Urtag:BAACLgAFFH8OAAMgAAgJBhC1CQCWAQAgAAcJRA21CQCWAQAHAAEJlCCregBkAAAuAAQKfxUAAyAACAnyFboqANYBACAACAkZFboqANYBAAcAAgm6F+e/AKIAAAAA.',
Va='Vadge:BAAALgADCgcJBwABLgADCgcJCwABAAAAAA==.Vaeryn:BAAALgAECgUJBQABLgAFFAMJBQAhAIEGAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAACLgAFFH8FAAIhAAMJgQa7NAB9AAAhAAMJgQa7NAB9AAAuAAQKf1sAAyEACAkUH48IANACACEACAkUH48IANACAAkABwmCD142ABoBAAAA.Valryn:BAAALgAECgYJDgABLgAFFAMJBQAhAIEGAA==.Valtar:BAABLgAECn8gAAINAAkJoBzpFgB6AgANAAkJoBzpFgB6AgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAABLgAECn8nAAMcAAgJhR5LDwAXAgAcAAgJ7R1LDwAXAgAVAAUJ4R7lcABuAQAAAA==.',
Ve='Velra:BAAALgADCgEJAQABLgAFFAMJBQAhAIEGAA==.Veraalyn:BAABLgAECn8dAAMOAAgJHhGtPQAiAQAOAAgJHhGtPQAiAQANAAMJxwiifgCZAAAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIQAAkJdQWddABFAQAQAAkJdQWddABFAQAAAA==.Vikaya:BAAALgAECgYJBwAAAA==.Vilevixon:BAABLgAECn8dAAMJAAkJ4hanFAAMAgAJAAkJ4hanFAAMAgAhAAEJDwSLdgAjAAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAABAAAAAA==.Wanlok:BAAALgAECgQJBgAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn8wAAQTAAkJlx/LCADBAgATAAkJlx/LCADBAgAEAAYJ7RDNKwADAQAfAAEJ6A4xUQAkAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8fAAIHAAgJeAzDRgCWAQAHAAgJeAzDRgCWAQAAAA==.Wildside:BAABLgAECn8XAAMHAAYJJh4bUACZAQAHAAYJJh4bUACZAQASAAYJFBYaJQBlAQAAAA==.',
Wu='Wujifei:BAAALgAFFAIJAwAAAA==.Wulffgar:BAAALgAECgQJBAAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJCgAAAA==.',
Xa='Xandronys:BAAALgAECggJCwAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECggJCgAAAA==.Xenie:BAAALgAECgUJCgAAAA==.',
Xi='Xinema:BAAALgAECgQJBAAAAA==.Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgAECgMJBwAAAA==.',
Yd='Ydeatho:BAAALgAECgMJAwAAAA==.',
Ye='Yeet:BAABLgAECn8bAAIkAAkJNBj5IgDhAQAkAAkJNBj5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgMJBgAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgIJAgAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8bAAMKAAkJcBIZRQBjAQAKAAkJcBIZRQBjAQAFAAEJYQ4hdwEvAAAAAA==.Zanos:BAAALgADCgIJAgAAAA==.Zarayssa:BAAALgADCgQJBAAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zeeva:BAABLgAECn8UAAMWAAYJ9x8LCgCGAQAWAAYJiR0LCgCGAQAXAAMJ+h2zIgB/AAAAAA==.Zendead:BAABLgAECn8jAAIaAAkJCiONBgDRAgAaAAkJCiONBgDRAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.Zerkces:BAAALgADCgIJAgAAAA==.',
Zi='Zionspartan:BAABLgAECn8uAAIHAAgJ/Q5WUACYAQAHAAgJ/Q5WUACYAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugpriest:BAAALgADCgYJBgAAAA==.Zugzugshaman:BAABLgAECn8iAAQNAAkJhRaQIAAyAgANAAkJhRaQIAAyAgAOAAQJrwOHbgCJAAAiAAEJYQBVPAAdAAAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8dAAIYAAgJmg70LABCAQAYAAgJmg70LABCAQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAAALgAECgYJBgAAAA==.',
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
