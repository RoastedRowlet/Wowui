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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Hunter-Survival','Warrior-Fury','Evoker-Devastation','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Aberration:BAAALgAECgEJAgAAAA==.',
Ad='Adorraa:BAAALgAECgQJBAABLgAFFAEJAQABAAAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8cAAMCAAcJsxdgCADmAQACAAYJkxlgCADmAQADAAEJkQw3SwBQAAAuAAQKfyEAAwIACQm1IUcCAFEDAAIACQm1IUcCAFEDAAMABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgADCgkJDAAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQAEAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAFFAQJBAAAAA==.',
Ai='Airali:BAACLgAFFH8IAAIFAAQJ+QV6QAAFAQAFAAQJ+QV6QAAFAQAuAAQKfxcAAwUACQn+E2tkALgBAAUACQn+E2tkALgBAAYAAwmJCNM3AGIAAAAA.Airedale:BAABLgAECn8hAAIHAAcJ0BJaVQB1AQAHAAcJ0BJaVQB1AQAAAA==.',
Ak='Akairo:BAABLgAECn8xAAMIAAkJACSCAgBBAwAIAAkJACSCAgBBAwAJAAgJrBEZIgCOAQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgYJBgABLgAECgkJJgADAKQgAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderxl:BAAALgAECgYJDgABLgAECggJAwABAAAAAA==.Aleybobwa:BAABLgAECn8fAAMKAAkJjhLNIwDBAQAKAAkJjhLNIwDBAQAFAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8nAAIKAAkJmxuVCQDMAgAKAAkJmxuVCQDMAgAAAA==.Amulius:BAABLgAECn81AAIFAAkJyyX/AgBcAwAFAAkJyyX/AgBcAwAAAA==.',
An='Anderdingus:BAAALgADCgUJBQAAAA==.Andormath:BAAALgAECgQJBgAAAA==.Andramedae:BAABLgAECn8lAAMLAAkJixSSHgAuAgALAAkJixSSHgAuAgAMAAEJdwfmfAAqAAAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgADCgkJCQAAAA==.Anoki:BAABLgAECn85AAMNAAkJ/xqbEAChAgANAAkJ/xqbEAChAgAOAAEJgQs1kwAnAAAAAA==.',
Ao='Aolus:BAACLgAFFH8RAAIMAAQJuxiTFgAyAQAMAAQJuxiTFgAyAQAuAAQKfxsAAgwACQkVHDETAHsCAAwACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJBAABAAAAAA==.Arcaina:BAABLgAECn8YAAIPAAcJhwnKnAAmAQAPAAcJhwnKnAAmAQAAAA==.Ares:BAAALgADCgcJBwABLgAECgkJLAAQAJEWAA==.Arez:BAABLgAECn8sAAIQAAkJkRaMLAAPAgAQAAkJkRaMLAAPAgAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJOgARALclAA==.Artèmís:BAABLgAECn8nAAISAAkJDSX+AQAaAwASAAkJDSX+AQAaAwAAAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgADCgkJEQAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athenä:BAAALgAECgMJBAAAAA==.',
Au='Aura:BAAALgAFFAEJAQAAAA==.',
Az='Azaekho:BAABLgAECn8kAAINAAkJcxQIKgDmAQANAAkJcxQIKgDmAQAAAA==.',
Ba='Baalzak:BAAALgADCgYJBQAAAA==.Backfliphoe:BAAALgAECgcJBwAAAA==.Badoosh:BAABLgAECn8nAAITAAgJCB2aGACHAgATAAgJCB2aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn8pAAQUAAgJXyBCAgCEAgAUAAgJXyBCAgCEAgADAAMJ5BD7TACdAAACAAEJMAvpNQAtAAAAAA==.Baliw:BAAALgADCgUJBAAAAA==.Balto:BAAALgADCgMJAwAAAA==.',
Bb='Bbl:BAECLgAFFH8VAAIOAAUJIxRtGAAjAQAOAAUJIxRtGAAjAQAuAAQKfyUAAg4ACQnWIFgKAPACAA4ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8PAAIPAAQJ2xFGKwAIAQAPAAQJ2xFGKwAIAQAuAAQKfyMAAg8ACQnDGZo7AIgCAA8ACQnDGZo7AIgCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAAALgAFFAEJAgAAAA==.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAQJCgAFAGIRAA==.',
Bi='Bieorne:BAABLgAECn82AAIVAAgJYiEdGQCOAgAVAAgJYiEdGQCOAgAAAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIQAAQJXQtnSQAQAQAQAAQJXQtnSQAQAQAuAAQKfxQAAhAACQnuFJMrABMCABAACQnuFJMrABMCAAAA.Bloodwrath:BAAALgAECgIJAwAAAA==.Blueveins:BAAALgAECgcJBwAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIQAAIJ5R6dcwCnAAAQAAIJ5R6dcwCnAAAuAAQKfxgAAxAACQnvHP4PAPoCABAACQnvHP4PAPoCABYAAQkAAL5DAAAAAAEuAAUUAwkIAAoAaxsA.Boondocks:BAABLgAECn8oAAMXAAkJkBs9DwAzAQAQAAUJzBZUaABWAQAXAAUJPiA9DwAzAQAAAA==.',
Br='Braca:BAAALgADCgEJAgAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8XAAIYAAgJBRBoJwBWAQAYAAgJBRBoJwBWAQABLgAECgkJKQAZAJ4bAA==.Brielle:BAABLgAECn8tAAIHAAkJuBc4HwBBAgAHAAkJuBc4HwBBAgAAAA==.Brokenbranch:BAAALgAECgUJEAAAAA==.Brudene:BAABLgAECn8UAAITAAcJFRF2VABZAQATAAcJFRF2VABZAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Buddylock:BAABLgAECn8iAAIQAAkJmgkNaABWAQAQAAkJmgkNaABWAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8QAAIaAAYJ9BsiBwB0AQAaAAYJ9BsiBwB0AQAuAAQKfx0AAhoACAk5I0EFADEDABoACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn88AAMbAAkJHR+UBgALAwAbAAkJHR+UBgALAwAaAAYJMRmHKABHAQABLgAECgkJJwASAA0lAA==.',
Ca='Caboozles:BAABLgAECn84AAIHAAkJOhW2MADwAQAHAAkJOhW2MADwAQAAAA==.Caliopia:BAABLgAECn8xAAMOAAkJvBTzGADuAQAOAAkJvBTzGADuAQANAAYJYQpfXgAJAQAAAA==.Caplyta:BAAALgADCgYJBgABLgAFFAUJEgAJACscAA==.Captnhuntcat:BAAALgAECggJEwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8oAAITAAkJEBTfGQD7AQATAAkJEBTfGQD7AQAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8bAAMcAAkJaR2cEAABAgAcAAkJaR2cEAABAgAVAAQJJA/0pgD5AAAAAA==.Chemistree:BAABLgAECn8oAAILAAkJORG7KADrAQALAAkJORG7KADrAQAAAA==.Chillout:BAABLgAECn8mAAIPAAgJYw7WawCGAQAPAAgJYw7WawCGAQAAAA==.Chillums:BAABLgAECn8cAAIQAAcJ4iP7GgCzAgAQAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgQJBgAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgQJBAABAAAAAA==.',
Co='Codeblue:BAAALgADCgUJBQAAAA==.Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8dAAIKAAkJYg65IgDJAQAKAAkJYg65IgDJAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Cy='Cy:BAAALgAECgYJCAAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJFQAVAB4bAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn8nAAMdAAkJLiMMDQDCAgAdAAkJuh8MDQDCAgAeAAgJ4iMcEwA+AgAAAA==.Darà:BAAALgADCgcJDgABLgAECggJJAAMAJ0OAA==.Dashyll:BAAALgAECgMJBAAAAA==.Davyfknjones:BAAALgAECggJEwAAAA==.Daynia:BAAALgAECgUJCAAAAA==.',
De='Deadbolt:BAAALgAECgYJBgAAAA==.Deadlegslul:BAABLgAECn8dAAIHAAcJ8B4aKwAHAgAHAAcJ8B4aKwAHAgAAAA==.Deadlegsmd:BAAALgAECgEJAgAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJBwAAAA==.Deathmono:BAAALgAECgYJCQAAAA==.Deathshark:BAACLgAFFH8KAAIcAAQJWBubDgBAAQAcAAQJWBubDgBAAQAuAAQKfy0AAhwACQnSHfILACACABwACQnSHfILACACAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8bAAIPAAcJWAcSrwAIAQAPAAcJWAcSrwAIAQAAAA==.Demeter:BAABLgAECn86AAIGAAkJ4xKJDADPAQAGAAkJ4xKJDADPAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denarien:BAAALgAECgkJDAAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJKQAZAJ4bAA==.Devouress:BAABLgAECn8SAAIdAAgJFRTmQwCZAQAdAAgJFRTmQwCZAQABLgAECggJGAAaAEcgAA==.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIfAAcJGQn9IQAuAQAfAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn8kAAMTAAgJrhUAJACvAQATAAgJ/xMAJACvAQAfAAEJzhxhPgBQAAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAQJCwAYAMgIAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAIDAAgJYhoEGAD2AQADAAgJYhoEGAD2AQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgABAAAAAA==.Draggnar:BAAALgAECgUJEAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAABLgAECn8cAAMSAAkJnQtxFQDcAQASAAkJ9gpxFQDcAQAgAAcJeAaAGgC4AAAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJDwAOAEwhAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMMAAkJnBhBGQA9AgAMAAgJsBlBGQA9AgALAAcJ4BiYPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn86AAIRAAkJtyU+AABpAwARAAkJtyU+AABpAwAAAA==.',
Eb='Ebojager:BAABLgAECn85AAIdAAgJdRkxJwARAgAdAAgJdRkxJwARAgAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJJwASAA0lAA==.',
Ei='Eibon:BAACLgAFFH8UAAIVAAYJyBQOFADHAQAVAAYJyBQOFADHAQAuAAQKfx4AAhUACQnNIakUAAADABUACQnNIakUAAADAAAA.',
El='Elliiria:BAAALgAECgQJBAAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAABLgAECn8ZAAIhAAcJ5RMIHgCuAQAhAAcJ5RMIHgCuAQAAAA==.Elwarrioro:BAAALgAECgYJDwAAAA==.',
Em='Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8gAAIiAAgJFBEEDgCZAQAiAAgJFBEEDgCZAQAAAA==.',
En='Enobia:BAABLgAECn8fAAMWAAcJeBMODABPAQAWAAcJeBMODABPAQAQAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgQJBAABAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgQJBQABLgAECgkJLAAQAJEWAA==.Eskath:BAABLgAECn8fAAIQAAgJXR8yHgBWAgAQAAgJXR8yHgBWAgABLgAECgkJKQAZAJ4bAA==.Essential:BAACLgAFFH8IAAIFAAQJNgviOgAVAQAFAAQJNgviOgAVAQAuAAQKfx0AAgUACAnpEjtgAJEBAAUACAnpEjtgAJEBAAAA.',
Et='Eternalpain:BAAALgAECgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8hAAIaAAYJfxNxMgARAQAaAAYJfxNxMgARAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCQAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECggJHAAYAJoOAA==.Ferrara:BAACLgAFFH8cAAQgAAcJqiFICgB0AQAgAAcJhB5ICgB0AQASAAEJ9iXoIwBsAAAHAAEJtx+1HwBiAAAuAAQKfyAABCAACQnRIykGADoDACAACQmLIykGADoDAAcAAQn1I6ywAGIAABIAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAABLgAECn8XAAIOAAYJRiFuIAANAgAOAAYJRiFuIAANAgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJOgAMAHkjAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8RAAIIAAcJTBU1AgAjAgAIAAcJTBU1AgAjAgAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgAECgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgABAAAAAA==.Frostednip:BAACLgAFFH8LAAIVAAQJyRbVPQBIAQAVAAQJyRbVPQBIAQAuAAQKfyQAAyMACQnaIPMGAO0BABUACQm/IIEyABECACMABwmhG/MGAO0BAAAA.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8HAAQDAAMJ9gTFOACvAAADAAMJ9gTFOACvAAACAAMJvQesGwCsAAAUAAEJlwEsDABCAAAuAAQKfxUAAwIACQlTE2YSABkCAAIACQlTE2YSABkCAAMAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECgUJBQAAAA==.Galnarn:BAACLgAFFH8fAAIYAAcJyyDFAgAtAgAYAAcJyyDFAgAtAgAuAAQKfyEAAhgACQlkHfgNALQCABgACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Garious:BAAALgAECgcJBwABLgAFFAQJCwAVAIsgAA==.Garjingo:BAAALgAECgUJBgABLgAECggJKQAUAF8gAA==.Garlicbae:BAAALgAECgYJDgAAAA==.Garwulf:BAAALgAECgYJDQAAAA==.',
Ge='Gefaustet:BAABLgAECn8oAAMfAAkJZRkrCwAXAgAfAAkJZRkrCwAXAgAEAAEJawh+YgAuAAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgcJCQAAAA==.',
Go='Goatcheesè:BAAALgAECgIJBAAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAECgcJEAAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAABLgAECn8UAAMYAAgJWQZFPQDnAAAYAAcJ3wZFPQDnAAAaAAMJHgKeiwAqAAAAAA==.Grayes:BAABLgAECn8aAAIZAAYJEQa7OQBzAAAZAAYJEQa7OQBzAAABLgAECggJFAAYAFkGAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hallowshade:BAABLgAECn8XAAIkAAcJFhnlJQDKAQAkAAcJFhnlJQDKAQAAAA==.Hardran:BAABLgAECn8bAAIFAAYJgwv5sAD7AAAFAAYJgwv5sAD7AAAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgQJBwAAAA==.Hatreddyes:BAAALgADCgYJCwABLgAECggJCQABAAAAAA==.Hatredyes:BAAALgAECggJCQAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECggJCQABAAAAAA==.',
He='Heatedsoul:BAAALgAECgEJAQAAAA==.Helare:BAABLgAECn8VAAIMAAgJ5hVnHwCfAQAMAAgJ5hVnHwCfAQAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8lAAIlAAgJMw31EgBTAQAlAAgJMw31EgBTAQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgEJAQABLgAECgkJJQAPABEhAA==.Horsegirl:BAAALgAECgEJAQAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Huffmetoes:BAAALgADCgUJBQAAAA==.Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECgEJAQAAAA==.Huulrokk:BAAALgADCgkJCwABLgAECgYJCQABAAAAAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJJwAKAJsbAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwABAAAAAA==.Idlewild:BAEALgADCgkJCgABLgAECgYJEAABAAAAAA==.',
If='Iforgotnaaru:BAABLgAECn8XAAMNAAcJ4Qs/XwAHAQANAAcJ4Qs/XwAHAQAOAAQJtQppVwCuAAAAAA==.',
Ik='Ikedizzy:BAAALgAECgEJAQABLgAECgMJBAABAAAAAA==.Ikeslice:BAAALgAECgMJBAAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAACLgAFFH8FAAIOAAIJICENKgC7AAAOAAIJICENKgC7AAAuAAQKfykAAg4ACAknJOcHAL0CAA4ACAknJOcHAL0CAAAA.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAITAAgJxxMSJQCpAQATAAgJxxMSJQCpAQAAAA==.',
In='Innex:BAABLgAECn8mAAIVAAkJGx9rIgBaAgAVAAkJGx9rIgBaAgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECgkJJgAVABsfAA==.Innexvoker:BAABLgAECn8YAAIDAAgJag+JKQB4AQADAAgJag+JKQB4AQABLgAECgkJJgAVABsfAA==.Inpesca:BAAALgADCgUJBQABLgAECgkJJgADAKQgAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgYJCwAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8ZAAIgAAYJGBDUEwD8AAAgAAYJGBDUEwD8AAAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8oAAINAAgJyRLbPgCAAQANAAgJyRLbPgCAAQAAAA==.Itzpie:BAABLgAECn81AAIPAAkJNxbcOwAPAgAPAAkJNxbcOwAPAgAAAA==.',
Ja='Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8aAAMVAAYJeRB/ogAAAQAVAAYJeRB/ogAAAQAcAAUJcQcOOQCBAAAAAA==.Jakeakuma:BAABLgAECn8UAAIQAAkJBAwlXwCsAQAQAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8aAAImAAUJoQfsEwDDAAAmAAUJoQfsEwDDAAAAAA==.Jaynne:BAAALgADCgcJBwAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgAECgcJBgAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn81AAIYAAkJgh+MBQDLAgAYAAkJgh+MBQDLAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIaAAgJGiFcCAD0AgAaAAgJGiFcCAD0AgABLgAFFAQJBAABAAAAAA==.Junfan:BAAALgAECgcJAwAAAA==.',
['Jà']='Jàckblack:BAAALgAECgQJBQAAAA==.',
Ka='Kaashaa:BAACLgAFFH8IAAIHAAMJpBj0NwAGAQAHAAMJpBj0NwAGAQAuAAQKf0AAAgcACQnLISwJAO4CAAcACQnLISwJAO4CAAAA.Kaelsgf:BAAALgAECgcJBwAAAA==.Kahllan:BAABLgAECn8kAAMMAAgJnQ4/KQBYAQAMAAgJnQ4/KQBYAQALAAEJLhR4tAA8AAAAAA==.Kahnigitt:BAABLgAECn8UAAIVAAYJzQnRrwDrAAAVAAYJzQnRrwDrAAAAAA==.Kalsifire:BAAALgADCgMJAwAAAA==.Kataltoholic:BAABLgAECn8aAAIPAAYJOAF8BQFsAAAPAAYJOAF8BQFsAAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIdAAYJCxp5UAC1AQAdAAYJCxp5UAC1AQAAAA==.Kaýhás:BAAALgADCgYJBgAAAA==.',
Ke='Kelinïsha:BAABLgAECn8pAAIPAAgJJQpZhwBMAQAPAAgJJQpZhwBMAQAAAA==.Kelynna:BAABLgAECn8oAAIIAAgJDhx1DgBYAgAIAAgJDhx1DgBYAgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJBQAAAA==.',
Kh='Khellder:BAAALgADCgYJBgAAAA==.Khelldyr:BAAALgAECggJCAAAAA==.Khellrond:BAAALgAECgkJDAAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiiras:BAABLgAECn8vAAIPAAgJ9A10bgCBAQAPAAgJ9A10bgCBAQAAAA==.Kimbodh:BAACLgAFFH8TAAIdAAUJayPLFgCcAQAdAAUJayPLFgCcAQAuAAQKfyYAAh0ACAkOJDILANYCAB0ACAkOJDILANYCAAEuAAEKAwkBAAEAAAAA.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8oAAIdAAgJMhF/TgB4AQAdAAgJMhF/TgB4AQAAAA==.',
Kl='Klefthoof:BAABLgAECn8tAAMNAAcJbhBoSABZAQANAAcJbhBoSABZAQAOAAEJUQRPmwAfAAABLgAECggJGwAPAFgHAA==.',
Ko='Kodey:BAABLgAECn8cAAIWAAgJmxKVCQB/AQAWAAgJmxKVCQB/AQABLgAFFAMJCAAWANgHAA==.Kordy:BAAALgAECgkJAQAAAA==.Korey:BAAALgAECgEJAQAAAA==.',
Kr='Kraniah:BAAALgAECgYJCQAAAA==.Krimboz:BAABLgAECn8rAAIQAAgJPhjVLQAJAgAQAAgJPhjVLQAJAgAAAA==.Krimbrouge:BAAALgAECgYJBwAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8nAAISAAgJphfXEQACAgASAAgJphfXEQACAgAAAA==.Krìsta:BAACLgAFFH8GAAMXAAIJ7QJvCgB5AAAXAAIJ7QJvCgB5AAAQAAEJ8QAyrQAxAAAuAAQKfx0AAxcACAncDFgNAGABABcABwleDlgNAGABABAABwknBJeqANUAAAAA.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ7wl6LABKAQAJAAgJ7wl6LABKAQAIAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgAECgYJCwAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8GAAIJAAMJrxUuGgDxAAAJAAMJrxUuGgDxAAAuAAQKfxgAAgkACQlvHb4XACYCAAkACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8oAAMHAAgJjx0gKQAPAgAHAAgJjx0gKQAPAgAgAAUJGxHCEwD9AAAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAAALgAECgUJEAAAAA==.Leonarde:BAACLgAFFH8PAAMHAAQJKBlYKQAxAQAHAAQJIBlYKQAxAQAgAAMJ2Q/RFQDuAAAuAAQKfyIABCAACQkZGb8gACACACAACAkSF78gACACAAcABQl/GKhWAHIBABIAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIQAAYJjhHKgQAgAQAQAAYJjhHKgQAgAQAAAA==.Leyla:BAAALgADCgkJCQAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn80AAIaAAkJbhbCEQAQAgAaAAkJbhbCEQAQAgAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgYJCwAAAA==.',
Ll='Llevanya:BAABLgAECn8zAAIFAAgJRQ5qagB6AQAFAAgJRQ5qagB6AQAAAA==.Llinaigh:BAABLgAECn8XAAIHAAgJXRUJVgBzAQAHAAgJXRUJVgBzAQAAAA==.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAgABLgAECgkJJwATAPMeAA==.Lomu:BAABLgAECn8pAAQZAAkJnhsoBwBPAgAZAAkJnhsoBwBPAgALAAEJ7Q5JzwAvAAAMAAEJigTohQAhAAAAAA==.Loredalso:BAAALgADCggJFgAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAFABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
['Lê']='Lêdrollan:BAAALgAECgIJAgABLgAFFAMJBgAJAK8VAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Magicdreams:BAABLgAECn8xAAIMAAgJJQmjMQAlAQAMAAgJJQmjMQAlAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIVAAYJMRUHowA6AQAVAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIcAAkJFhshCwBjAgAcAAkJFhshCwBjAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAAALgADCgYJCwABLgADCgcJCwABAAAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwABAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIkAAkJ0R1YDQAsAgAkAAkJ0R1YDQAsAgAAAA==.Materia:BAAALgAECgEJAQAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJEhEjKACAAQADAAgJwBAjKACAAQACAAYJFQtdKQAoAQAUAAMJjw+AFAChAAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8xAAIFAAkJKCE3CgD7AgAFAAkJKCE3CgD7AgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMiAAkJGxU2BgCWAgAiAAkJGxU2BgCWAgAOAAgJyg/tOAAjAQAAAA==.',
Me='Meerchi:BAABLgAECn8xAAMPAAkJCBn3LgA/AgAPAAkJCBn3LgA/AgAnAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meowkai:BAAALgAECgYJBwABLgAECgkJJwASAA0lAA==.Mesthos:BAAALgAECgcJDAABLgAECgkJJAARAJ4lAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAIDAAgJlBKOGgD2AQADAAgJlBKOGgD2AQAAAA==.',
Mi='Mickieta:BAABLgAECn8oAAIFAAkJwh80FACuAgAFAAkJwh80FACuAgAAAA==.Microsurge:BAACLgAFFH8HAAIPAAQJ4Ai8VgAWAQAPAAQJ4Ai8VgAWAQAuAAQKfx0AAg8ACAkiHdslANsCAA8ACAkiHdslANsCAAAA.Mikalau:BAABLgAECn8dAAIHAAgJghEcRQCmAQAHAAgJghEcRQCmAQAAAA==.Mikaluu:BAABLgAECn8YAAIQAAYJmQU5rgDPAAAQAAYJmQU5rgDPAAAAAA==.Miqkail:BAAALgAECggJCgABLgAECgkJJAARAJ4lAA==.Missteek:BAAALgAECgUJCgABLgAECggJKQAUAF8gAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8PAAIJAAQJpQ90FQAfAQAJAAQJpQ90FQAfAQAuAAQKfyAAAwkACQnXHeQOAJUCAAkACQnXHeQOAJUCAAgAAwklBoFqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJJwAKAJsbAA==.Mognel:BAABLgAECn82AAIQAAkJxxymIQBDAgAQAAkJxxymIQBDAgAAAA==.Mogrungar:BAABLgAECn8jAAINAAkJEQ7xMADBAQANAAkJEQ7xMADBAQAAAA==.Moisten:BAABLgAECn8eAAIOAAkJQyAHBgDgAgAOAAkJQyAHBgDgAgAAAA==.Monklee:BAAALgAECgEJAgAAAA==.Moomootus:BAABLgAECn8dAAMFAAkJYRVLVwCmAQAFAAgJHhRLVwCmAQAKAAQJ/B5tNABXAQAAAA==.Morgalea:BAAALgAECgcJAQAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIaAAgJRyBsDQClAgAaAAgJRyBsDQClAgAAAA==.Mystynight:BAAALgAECgYJCAAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8eAAIOAAgJng6/MgBDAQAOAAgJng6/MgBDAQAAAA==.Nagini:BAABLgAECn8fAAIQAAgJdwjFdAA6AQAQAAgJdwjFdAA6AQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn88AAMIAAkJgxl2FwDsAQAIAAcJGRl2FwDsAQAJAAkJtBEkMwAlAQAAAA==.Nietzcha:BAAALgAECgEJAQAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAABLgAECn8aAAMMAAYJFheFKgBPAQAMAAYJ6BaFKgBPAQAlAAUJRw1uKQCJAAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgYJCwAAAA==.Nioh:BAABLgAECn8iAAIdAAkJxRYFJwARAgAdAAkJxRYFJwARAgAAAA==.',
No='Noodles:BAABLgAECn8nAAIdAAgJnwjdfgD6AAAdAAgJnwjdfgD6AAAAAA==.Nordrydsh:BAAALgADCgkJCQABLgAFFAUJFQAbAHAZAA==.',
Nu='Nuggs:BAABLgAECn8YAAIlAAkJzBBZDAC9AQAlAAkJzBBZDAC9AQAAAA==.Nuhpie:BAACLgAFFH8VAAMEAAcJhw7LFwDbAAAEAAQJugvLFwDbAAATAAMJUxFTKADaAAAuAAQKfx4AAwQACQlfHTgZAGYBAAQABQmuGjgZAGYBABMABQlsHPU/ABwBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIVAAkJax8mEwC2AgAVAAkJax8mEwC2AgAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8eAAINAAcJAyQTAQCkAgANAAcJAyQTAQCkAgAuAAQKfycAAw0ACQlvJUsAAM8DAA0ACQlvJUsAAM8DAA4AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Oricelle:BAABLgAECn8oAAIdAAkJRRYHIgAsAgAdAAkJRRYHIgAsAgAAAA==.Oridis:BAAALgAECgkJBwAAAA==.Oryon:BAEBLgAECn8sAAIXAAgJyBTuCACiAQAXAAgJyBTuCACiAQAAAA==.',
Ov='Ovarb:BAABLgAECn8hAAIcAAkJkRijDQAAAgAcAAkJkRijDQAAAgAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDQAAAA==.Palasexo:BAAALgADCgcJCwAAAA==.Palldude:BAAALgADCgIJAgAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Pesti:BAACLgAFFH8RAAIkAAMJIBWZDgAGAQAkAAMJIBWZDgAGAQAuAAQKf0kAAiQACQkMI+wBAC8DACQACQkMI+wBAC8DAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8+AAINAAkJQiOFAgB9AwANAAkJQiOFAgB9AwAAAA==.',
Pi='Pissedwolf:BAAALgAECgUJBgAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8dAAIYAAgJCRBLJQBkAQAYAAgJCRBLJQBkAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAACLgAFFH8IAAIPAAMJxRN0YQDzAAAPAAMJxRN0YQDzAAAuAAQKfz4AAw8ACQljIGINAPcCAA8ACQlaIGINAPcCACgABQmtEiQMABABAAAA.Proctologist:BAABLgAECn8jAAMYAAgJoBh5FgDWAQAYAAgJoBh5FgDWAQAaAAIJXAnhaQBUAAAAAA==.Proserpìne:BAABLgAECn8uAAIdAAgJaAnGZwAwAQAdAAgJaAnGZwAwAQAAAA==.',
Ps='Psychojester:BAACLgAFFH8IAAIiAAMJDRmaBwABAQAiAAMJDRmaBwABAQAuAAQKf0MAAiIACQk2IXgBAAgDACIACQk2IXgBAAgDAAAA.Psylir:BAAALgAECgQJDgAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIPAAUJihsapQAYAQAPAAUJihsapQAYAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAABLgAECn86AAMPAAgJSyHBGACqAgAPAAgJSyHBGACqAgAoAAEJlyB5GQBMAAABLgAFFAUJFwAHADobAA==.',
Ra='Raijyu:BAABLgAECn84AAMIAAkJBx9TBAAhAwAIAAkJBx9TBAAhAwAJAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJNgAMAM8WAA==.Rainstormin:BAABLgAECn82AAMMAAkJzxZCEQAoAgAMAAkJzxZCEQAoAgAZAAYJxglKLwCoAAAAAA==.Rakarra:BAABLgAECn8YAAMLAAcJ3gy9UQAlAQALAAcJ3gy9UQAlAQAMAAYJDgcPTQD2AAAAAA==.Ranalia:BAAALgADCgcJBwAAAA==.Rawrstance:BAABLgAECn8xAAMcAAkJ1RmrFgCCAQAVAAcJoRxNYACEAQAcAAkJXw+rFgCCAQABLgADCgQJBAABAAAAAA==.Razgrize:BAABLgAECn8hAAIPAAgJ7RZ2SADmAQAPAAgJ7RZ2SADmAQAAAA==.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgADAGIaAA==.Reeshan:BAABLgAECn8fAAMFAAkJ1yMwCQAGAwAFAAkJ1yMwCQAGAwAKAAIJaxR/ZgBoAAAAAA==.Reilin:BAAALgAECgQJBQAAAA==.Remsham:BAABLgAECn8lAAIiAAgJpw5dDwCBAQAiAAgJpw5dDwCBAQAAAA==.Reniel:BAAALgADCgcJBAABLgAECggJKAAdADIRAA==.Renwyck:BAABLgAECn8kAAIRAAkJniV4AABOAwARAAkJniV4AABOAwAAAA==.Revengemoon:BAACLgAFFH8RAAIFAAQJsxJmLwAwAQAFAAQJsxJmLwAwAQAuAAQKfyMAAgUACQmVGsApAH4CAAUACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgABAAAAAA==.Ringberg:BAACLgAFFH8IAAIKAAMJaxt2IgDeAAAKAAMJaxt2IgDeAAAuAAQKfxcAAwoABwlSH3wUAEQCAAoABwlSH3wUAEQCAAUAAwmmFIDgALYAAAAA.',
Ro='Robane:BAAALgAECgUJDwAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn8tAAMiAAgJiiIVBQBsAgAiAAgJiiIVBQBsAgANAAgJlxuIFgBpAgAAAA==.',
Ru='Rubidea:BAAALgADCgQJBAAAAA==.Ruckus:BAEALgAECgYJEAAAAA==.Ruder:BAAALgAECgMJBAABLgAECggJCQABAAAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJxBtnEQBzAgAJAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgADCgQJBAAAAA==.Sandkat:BAABLgAECn86AAITAAgJvCL3CQCjAgATAAgJvCL3CQCjAgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgAECgEJAQAAAA==.Saraelin:BAAALgAFFAIJBAAAAA==.Saray:BAAALgAECgcJDQAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEwATAO4QAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDQAAAA==.Serahstia:BAABLgAECn8dAAIPAAgJ9xUsVADDAQAPAAgJ9xUsVADDAQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shadowmeld:BAAALgAECgEJAQAAAA==.Shadysadie:BAAALgAECgUJBQAAAA==.Shaiy:BAAALgAECgMJBQAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwABAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAAALgAECgUJCAAAAA==.Shirtles:BAABLgAECn8VAAIOAAYJggPvXwCSAAAOAAYJggPvXwCSAAAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgUJCQAAAA==.Shèp:BAABLgAECn8ZAAIKAAgJFhEZKACkAQAKAAgJFhEZKACkAQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIOAAUJ/hmfAwCvAQAOAAUJ/hmfAwCvAQABLgAFFAYJDgASACUWAA==.Siffrin:BAAALgAECgIJAgAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8lAAMQAAgJnhUiZABgAQAQAAYJ0hIiZABgAQAXAAUJJRaVEwD3AAABLgAECggJJQADAJQSAA==.Sinkingship:BAAALgAECgUJBQAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8ZAAIcAAkJ5x2kBgCSAgAcAAkJ5x2kBgCSAgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sloothe:BAAALgADCgUJBQAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8WAAIFAAkJgRp3KAA/AgAFAAkJgRp3KAA/AgAAAA==.',
Sp='Sprodage:BAABLgAECn8uAAIKAAgJbxT/IQDOAQAKAAgJbxT/IQDOAQAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAABAAAAAA==.Stanil:BAABLgAECn8dAAMHAAgJ7AZybQA4AQAHAAgJ7AZybQA4AQAgAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDAAAAA==.Stellare:BAABLgAECn8tAAIeAAkJFRcmDQAdAgAeAAkJFRcmDQAdAgAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Strangetame:BAAALgADCgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEwAAAA==.',
Su='Suetonius:BAACLgAFFH8FAAIVAAMJqh34XQASAQAVAAMJqh34XQASAQAuAAQKfxMAAxUACAlXJAcMAO0CABUACAlXJAcMAO0CACMAAgk4E/ghAGYAAAAA.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8rAAIPAAkJaBrOLABIAgAPAAkJaBrOLABIAgAAAA==.Suraschi:BAAALgAECgYJBgABLgAECgkJKwAPAGgaAA==.',
Sv='Svelda:BAABLgAECn8cAAMJAAYJIAsGOwD+AAAJAAYJIAsGOwD+AAAhAAUJmAXaQQDGAAAAAA==.',
Sw='Swisscake:BAABLgAECn86AAIMAAkJeSOKAgA2AwAMAAkJeSOKAgA2AwAAAA==.',
Sy='Sylain:BAAALgAECgYJEQABLgAECgkJFQAkAKEKAA==.',
Ta='Tannatax:BAABLgAECn8oAAINAAgJoAa3VAArAQANAAgJoAa3VAArAQAAAA==.Tashah:BAAALgADCgIJAgAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAABAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMPAAkJnBWZQwD1AQAPAAkJnBWZQwD1AQAnAAEJGgFqEQALAAAAAA==.Thewretch:BAABLgAECn80AAIQAAgJViJ8DwC5AgAQAAgJViJ8DwC5AgAAAA==.Thumpthump:BAABLgAECn8nAAQSAAkJQBhcEAATAgASAAkJMhBcEAATAgAgAAYJwx6nIgARAgAHAAEJqQ4y/wA1AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEALgAECgUJCAABLgAECgYJEAABAAAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAABLgAECn8ZAAIHAAYJ4xdvWABtAQAHAAYJ4xdvWABtAQAAAA==.',
To='Toastnbutta:BAABLgAECn8kAAILAAkJ9xnLFACBAgALAAkJ9xnLFACBAgAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmUMQBcAgAFAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgQJBAAAAA==.Traumatism:BAAALgAECgYJBwAAAA==.Trevor:BAABLgAECn86AAImAAgJgBbEBQD3AQAmAAgJgBbEBQD3AQAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAACLgAFFH8HAAMlAAMJIhH6CQDaAAAlAAMJjQv6CQDaAAAZAAEJXBnMHwBPAAAuAAQKfxYAAxkABwlfHGMSAIwBABkABgk0HGMSAIwBACUABQmGG0wVADcBAAEuAAUUBAkKABwAWBsA.Tsura:BAAALgAECgIJAgAAAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.',
Un='Unclepeepers:BAACLgAFFH8QAAIbAAQJ5R/WFABgAQAbAAQJ5R/WFABgAQAuAAQKfy4AAxoACQkPI5YMAFUCABoACAmOIpYMAFUCABsACQm0G80aAAICAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAABLgAECn8XAAIVAAcJ3QuXqgDzAAAVAAcJ3QuXqgDzAAAAAA==.',
Ur='Urtag:BAABLgAFFH8KAAIgAAYJRw0DDABUAQAgAAYJRw0DDABUAQAAAA==.',
Va='Vadge:BAAALgADCgcJBwABLgADCgQJBAABAAAAAA==.Vaeryn:BAAALgADCgkJCQABLgAECggJTgAhABQfAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAABLgAECn9OAAMhAAgJFB+DBwDaAgAhAAgJFB+DBwDaAgAJAAYJRwvwUQCUAAAAAA==.Valryn:BAAALgAECgYJCQABLgAECggJTgAhABQfAA==.Valtar:BAABLgAECn8gAAINAAkJoBxAFAB9AgANAAkJoBxAFAB9AgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAABLgAECn8iAAMcAAgJ7R1LDwAXAgAcAAgJ7R1LDwAXAgAVAAQJeBQMxwDIAAAAAA==.',
Ve='Veraalyn:BAABLgAECn8dAAMOAAgJHhHAOAAkAQAOAAgJHhHAOAAkAQANAAMJxwiifgCZAAAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIQAAkJdQWsbABLAQAQAAkJdQWsbABLAQAAAA==.Vikaya:BAAALgAECgUJBQAAAA==.Vilevixon:BAABLgAECn8dAAMJAAkJ4hbCEgAXAgAJAAkJ4hbCEgAXAgAhAAEJDwS8bQAjAAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAABAAAAAA==.Wanlok:BAAALgAECgQJBQAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn8nAAQTAAkJ8x7LCAC1AgATAAkJ8x7LCAC1AgAEAAYJ7RA9JwAGAQAfAAEJ6A59SwAlAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8eAAIHAAgJKwzDRgCWAQAHAAgJKwzDRgCWAQAAAA==.Wildside:BAAALgAECgcJEQAAAA==.',
Wu='Wujifei:BAAALgAECgIJAgAAAA==.Wulffgar:BAAALgADCgcJCQAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJCgAAAA==.',
Xa='Xandronys:BAAALgAECgcJCgAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECgcJCQAAAA==.Xenie:BAAALgAECgUJCgAAAA==.',
Xi='Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgAECgMJBQAAAA==.',
Yd='Ydeatho:BAAALgAECgIJAgAAAA==.',
Ye='Yeet:BAABLgAECn8bAAIkAAkJNBj5IgDhAQAkAAkJNBj5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgEJBAAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgIJAgAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8bAAMKAAkJcBIZRQBjAQAKAAkJcBIZRQBjAQAFAAEJYQ58VQE2AAAAAA==.Zanos:BAAALgADCgIJAgAAAA==.Zarayssa:BAAALgADCgQJBAAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zeeva:BAABLgAECn8UAAMWAAYJ9x//CACMAQAWAAYJiR3/CACMAQAXAAMJ+h3GHgCDAAAAAA==.Zendead:BAABLgAECn8jAAIaAAkJCiOMBQDWAgAaAAkJCiOMBQDWAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.Zerkces:BAAALgADCgIJAgAAAA==.',
Zi='Zionspartan:BAABLgAECn8uAAIHAAgJ/Q4cSQCZAQAHAAgJ/Q4cSQCZAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugpriest:BAAALgADCgYJBgAAAA==.Zugzugshaman:BAABLgAECn8iAAQNAAkJhRYpHQA2AgANAAkJhRYpHQA2AgAOAAQJrwOHbgCJAAAiAAEJYQDXNAAdAAAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8cAAIYAAgJmg40KgBFAQAYAAgJmg40KgBFAQAAAA==.',
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
