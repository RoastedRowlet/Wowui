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

local lookup = {'Unknown-Unknown','Priest-Holy','Priest-Discipline','Druid-Restoration','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Warlock-Destruction','Druid-Balance','Druid-Feral','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Shaman-Elemental','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Marksmanship','Paladin-Holy','Hunter-Survival','Warlock-Affliction','Druid-Guardian','Priest-Shadow','Shaman-Enhancement','Warrior-Arms','Mage-Arcane','Rogue-Assassination','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Mage-Frost','Monk-Mistweaver','Warrior-Protection','Rogue-Subtlety','Warrior-Fury',}
local provider = {region='US',realm="Sen'jin",name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acarie:BAAANQABCgQIBgAAAA==.Acon:BAAANQADCgEIAQABNQAECgYIEgABAAAAAA==.Actaeon:BAAANQADCgUIBQAAAA==.',
Ae='Aegrias:BAACNQAFFIEIAAICAAQKZg2zEgA+AQACAAQKZg2zEgA+AQA1AAQKgSMAAwMACQrmGYUHAOQBAAIACAqJGbdHACkCAAMACAoeEoUHAOQBAAAA.Aelrindel:BAAANQADCgEIAQAAAA==.Aethelwolf:BAAANQAECgUIBwAAAA==.',
Ak='Akkeno:BAAANQABCgQIBAAAAA==.',
Al='Alainy:BAAANQADCggIDwAAAA==.Alentrya:BAAANQADCgYIDwABNQAECgcIHwAEAAkdAA==.Alestraza:BAAANQADCgEIAQABNQAECggIHAAFAHYaAA==.Alice:BAAANQAECgMIBQAAAA==.Alithea:BAAANQADCgQJBAABNQAECgYIEgABAAAAAA==.Aliveagain:BAAANQADCgUIFAAAAA==.Allek:BAAANQADCgQIBAAAAA==.Alongtoo:BAAANQAECgUICgAAAA==.',
Am='Amageros:BAAANQAECgYIDgAAAA==.Amaterasu:BAABNQAECoEsAAIGAAkKNR3iFwDXAgAGAAkKNR3iFwDXAgAAAA==.Amonamärth:BAAANQAECgIIBAAAAA==.',
An='Andrael:BAAANQADCggIEgAAAA==.Andraszun:BAAANQAECgEIAwAAAA==.Andruin:BAAANQADCgYIBgAAAA==.Annagul:BAAANQADCgUICAAAAA==.Annieoaklea:BAAANQADCgUIGAAAAA==.Anob:BAAANQADCgMIAwAAAA==.Anubuskid:BAAANQADCgYIBgAAAA==.Anubusx:BAAANQADCgYIBgAAAA==.',
Ao='Aoîrlen:BAAANQAECgcIDQAAAA==.',
Aq='Aqua:BAABNQAECoEgAAIHAAgKURYTRAAmAgAHAAgKURYTRAAmAgAAAA==.',
Ar='Araedral:BAAANQADCgQJBAAAAA==.Aragurn:BAAANQADCgMIAwAAAA==.Argussy:BAAANQAECgQICwAAAA==.Artemís:BAAANQAECgcIDgABNQAECggIHAAFAHYaAA==.Arthanin:BAAANQAECgYIDAABNQAECgkJIgAIAKIYAA==.Arthrogate:BAAANQADCgUIGAAAAA==.Artorius:BAAANQADCgEIAQAAAA==.Arägoss:BAAANQADCgUIBQAAAA==.',
As='Asmund:BAAANQAECgQIBAAAAA==.Astana:BAAANQAECgYIEAAAAA==.Astraii:BAABNQAECoEaAAMJAAcKviDDMQAvAgAJAAYKkCHDMQAvAgAKAAEK0xuCLwBUAAAAAA==.Astyanaax:BAAANQAECgQIBwAAAA==.',
At='Attrox:BAAANQAECgUIEAAAAA==.',
Au='Augtistic:BAAANQAECgYIEQAAAA==.Auridia:BAAANQADCgUIFAAAAA==.',
Av='Avalef:BAAANQAECgIIAgAAAA==.',
Az='Azagonnath:BAAANQAECgUICQAAAA==.',
Ba='Babushka:BAABNQAECoEaAAILAAgKGCKjBwAdAwALAAgKGCKjBwAdAwAAAA==.Babybread:BAAANQAECgQICAAAAA==.Backtrak:BAABNQAECoEfAAIMAAcKyxxwVgBGAgAMAAcKyxxwVgBGAgAAAA==.Bagagwa:BAAANQADCgEIAQAAAA==.Balthug:BAAANQADCgQIBQAAAA==.Bamboomnster:BAABNQAECoEbAAINAAgKThN7IwDcAQANAAgKThN7IwDcAQAAAA==.Bankei:BAAANQAECggICAAAAA==.Bankpokc:BAAANQADCgEIAQAAAA==.Bareeyyee:BAABNQAECoEnAAIOAAkKChyjIADrAgAOAAkKChyjIADrAgAAAA==.Barikade:BAAANQADCgYIBgAAAA==.Baréin:BAAANQADCgUIBQAAAA==.Bassinel:BAABNQAECoEWAAIPAAgKKhx6BgCHAgAPAAgKKhx6BgCHAgAAAA==.',
Be='Beavacleava:BAAANQADCgQJBAAAAA==.Beesbok:BAAANQADCgYIBgAAAA==.Belasius:BAAANQADCgMIAwAAAA==.Bellaßeár:BAAANQADCgYIEgAAAA==.Belldandy:BAAANQADCgYICwAAAA==.Belleshamira:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Benniehill:BAAANQADCggIHQABNQAECgUIEQABAAAAAA==.',
Bi='Bigdaddydan:BAABNQAECoEcAAMOAAkKCx2sKAC9AgAOAAkKCx2sKAC9AgAHAAEKHAZLBAEyAAAAAA==.Bigsexxy:BAAANQAECgEIAQAAAA==.Billymayge:BAAANQADCgUIBQAAAA==.Bishämon:BAABNQAECoEcAAMQAAkK9RhtHQB4AgAQAAkK9RhtHQB4AgARAAEKCwjj1gApAAAAAA==.',
Bj='Bjorgan:BAAANQAECgIIAgAAAA==.',
Bl='Blackbullben:BAAANQABCgcJBwAAAA==.Bled:BAAANQAECgQIBAAAAA==.Blessthefall:BAAANQAECgcIEAAAAA==.Blinddate:BAABNQAECoErAAISAAkKJBp+HgCAAgASAAkKJBp+HgCAAgAAAA==.Blindside:BAABNQAECoEbAAMSAAcKMBJWOQC0AQASAAcKMBJWOQC0AQATAAYKPQsQOwBEAQAAAA==.Bloodrose:BAAANQADCgEIAQABNQADCgYIEwABAAAAAA==.Bloodytex:BAAANQADCgYIDAABNQAECgcIJgAJADogAA==.Bluejayne:BAAANQADCgYIEAAAAA==.',
Bo='Bodnar:BAAANQAECgQICAAAAA==.Bohe:BAAANQADCgYIDwAAAA==.Boldog:BAAANQAECgQIBwAAAA==.Bombpop:BAAANQAECgEIAQAAAA==.Bonesy:BAAANQAECgEIAQAAAA==.Bootyfull:BAAANQADCgQIBAAAAA==.Borderlands:BAAANQABCgEIAQAAAA==.Bouldin:BAAANQAECgIIAgAAAA==.Bouseman:BAAANQABCgIIAgAAAA==.',
Br='Brandn:BAABNQAECoEtAAMMAAkK3yVqAgDYAwAMAAkK3yVqAgDYAwAUAAcKvhVFLQC8AQAAAA==.Bridgett:BAABNQAECoEfAAICAAcKUiEVMgB/AgACAAcKUiEVMgB/AgAAAA==.Brioche:BAAANQADCggICQAAAA==.Brown:BAAANQADCgUIBgAAAA==.Bruisechi:BAAANQABCgIIAgAAAA==.',
Bu='Budcrest:BAAANQADCgEIAQABNQAECgUIEQABAAAAAA==.Bums:BAAANQADCgYICQAAAA==.',
['Bü']='Bümps:BAAANQAECgYIEgAAAA==.',
Ca='Cabinet:BAAANQAECgQJBAAAAA==.Cabrakan:BAAANQADCgMIAwABNQAECgkJKgAHAKMdAA==.Caledor:BAAANQADCggIDwAAAA==.Cancer:BAAANQAECgUIEAAAAA==.Candace:BAAANQABCgYIBgABNQAFFAEIAQABAAAAAA==.Captclamslam:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Carti:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.Catbutt:BAABNQAECoElAAIKAAgK3CKDBAAhAwAKAAgK3CKDBAAhAwAAAA==.',
Ce='Celata:BAAANQADCgEIAQAAAA==.Cereth:BAAANQADCgUICgABNQAECgUIDAABAAAAAA==.Cerissia:BAAANQAECgQIBAABNQAFFAIIAgABAAAAAA==.',
Ch='Chapo:BAAANQADCggIFAAAAA==.Chewshocka:BAAANQADCgUICAAAAA==.Chinanumbwon:BAAANQADCgUJBgAAAA==.',
Ci='Cindi:BAAANQADCgUIBQAAAA==.Citrusmaxima:BAAANQAECgMJAwABNQAECggIIgAVAHYTAA==.',
Cl='Cliffmage:BAAANQAECggICwAAAA==.',
Co='Coco:BAABNQAECoEdAAQWAAkKAB2XAgDvAgAWAAkK+hqXAgDvAgAMAAUKhR5frwBxAQAUAAIKrgeBbABYAAAAAA==.Cocopuf:BAAANQAECgMIAwAAAA==.Codels:BAAANQAECgQIDwAAAA==.Corex:BAAANQAECgUIBQABNQAECgcJDQABAAAAAA==.Corlock:BAAANQAECgYIDAAAAA==.',
Cr='Crb:BAAANQAECgYIEgAAAA==.Creelope:BAAANQADCgMIBQAAAA==.Crimsonsong:BAABNQAECoEeAAIGAAcKygYmbAAfAQAGAAcKygYmbAAfAQAAAA==.Crixsas:BAAANQADCgEIAQAAAA==.Crocodile:BAAANQABCgYIDQAAAA==.Croise:BAABNQAECoEgAAIVAAgKTiIqGQABAwAVAAgKTiIqGQABAwAAAA==.Crössblesser:BAAANQAECgYIEAAAAA==.',
Cu='Cursesteve:BAABNQAECoEbAAIXAAgKUhkNBACGAgAXAAgKUhkNBACGAgAAAA==.',
Cy='Cyna:BAAANQADCgIIAgAAAA==.Cynarel:BAAANQAECgcIEwAAAA==.Cyrial:BAAANQAECgUIEwAAAA==.',
Da='Daemarcus:BAAANQADCgUIBQAAAA==.Darctricity:BAABNQAECoEhAAMOAAgKphQ/TAAZAgAOAAgKphQ/TAAZAgAHAAEKOwc3BwEuAAAAAA==.Darten:BAAANQADCgIIAgAAAA==.Dashay:BAAANQAECgcIEwAAAA==.Dawnflow:BAAANQADCgUIBQAAAA==.Dazao:BAABNQAECoEfAAIYAAcKTBV9FgC/AQAYAAcKTBV9FgC/AQAAAA==.',
De='Deathdealr:BAAANQAECgQIBAAAAA==.Deathslayr:BAAANQAECgUICwAAAA==.Deathsranger:BAAANQAECgQICwAAAA==.Decks:BAABNQAECoEaAAMZAAgKIB70FACYAgAZAAgKIB70FACYAgACAAcK/Bx+RQAxAgAAAA==.Degath:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Deianne:BAABNQAECoEqAAIHAAkKLSEGEQAnAwAHAAkKLSEGEQAnAwAAAA==.Deks:BAAANQAECgQIBQABNQAECggIGgAZACAeAA==.Delerius:BAAANQAECgIIAgAAAA==.Delomarr:BAAANQAECgUIDAAAAA==.Deltre:BAACNQAFFIEMAAMIAAQK6RwjCQCsAAAFAAIKMB+NIQC5AAAIAAIKoxojCQCsAAA1AAQKgToAAwUACQqFJAwmANQCAAUABwrtIwwmANQCAAgABQq4HUwUAMQBAAAA.Demonimai:BAAANQAECgEIAQAAAA==.Depletechkn:BAABNQAECoEmAAIEAAgKdx5UEAC1AgAEAAgKdx5UEAC1AgAAAA==.Desecratés:BAAANQAECgcICQAAAA==.Destshooter:BAAANQADCgQIBAAAAA==.Dewiaychardi:BAAANQAECgMIAwABNQAECgYIDgABAAAAAA==.Deäthcowd:BAACNQAFFIEOAAMRAAUKByJ6AwDjAQARAAUK4B56AwDjAQAQAAMKJCWfBwAtAQA1AAQKgSEAAxAACQrRI2sQAO4CABAACApwI2sQAO4CABEACAqZI2glAIkCAAAA.',
Di='Dim:BAAANQADCggIDgAAAA==.Dinaszun:BAAANQADCgYIFAAAAA==.Disrupt:BAAANQAECgIIBAABNQAECgQIBwABAAAAAA==.Dizdemona:BAAANQAECgYIEwAAAA==.Dizrupt:BAAANQAECgQIBwAAAA==.',
Dj='Dj:BAAANQAECgcIEwAAAA==.',
Do='Doomstickk:BAABNQAECoEfAAIMAAgK2h23KgDNAgAMAAgK2h23KgDNAgAAAA==.Dopy:BAABNQAECoEcAAIaAAkKbyIOAgCQAwAaAAkKbyIOAgCQAwAAAA==.Dorania:BAAANQAECgQICwAAAA==.',
Dr='Dracoradh:BAABNQAECoEiAAMSAAgKLRxQKQArAgASAAcKhRpQKQArAgATAAgKLxT9JAD/AQABNQABCgQIBgABAAAAAA==.Dracorapalli:BAAANQADCgYIBgABNQABCgQIBgABAAAAAA==.Drakondra:BAAANQADCggIDgAAAA==.Draziel:BAABNQAECoEXAAIJAAcKeAtcUwBhAQAJAAcKeAtcUwBhAQAAAA==.Drazzert:BAAANQAECgcIDgAAAA==.Dryádalis:BAAANQAECgQJBQAAAA==.',
Du='Dungarrth:BAAANQAECgUICQABNQAECgcIEAABAAAAAA==.Dunhammer:BAAANQAECgIIAwAAAA==.Duverlierst:BAAANQAECgUICQAAAA==.Duzt:BAAANQAECgIIAwAAAA==.',
Dw='Dwarvenbufet:BAAANQADCgUIBgAAAA==.',
Dy='Dyhrd:BAAANQAECgYIDgAAAA==.Dysrupt:BAAANQAECgQJBAABNQAECgQIBwABAAAAAA==.',
['Dü']='Dücky:BAAANQAECgQIBAAAAA==.',
Ea='Eatcrayons:BAABNQAECoEgAAIbAAkK1hmeOgDEAgAbAAkK1hmeOgDEAgAAAA==.',
Ei='Eirtae:BAAANQADCggJDQAAAA==.',
El='Ellaryn:BAAANQAECggIEgAAAA==.Elluvious:BAABNQAECoEZAAIIAAcK9hEqFQC8AQAIAAcK9hEqFQC8AQAAAA==.Elorla:BAAANQADCggIFQAAAA==.Elumage:BAAANQADCgQIBAAAAA==.Eluzai:BAAANQADCgMJAwAAAA==.',
Em='Emporerzur:BAAANQADCgcIBwAAAA==.Empyria:BAAANQADCgYIBwAAAA==.',
En='Enchantertim:BAAANQADCgIIAgAAAA==.Enhypen:BAAANQADCgUIBQAAAA==.',
Er='Eriaeveline:BAAANQADCgQIBAAAAA==.',
Ew='Ewaker:BAAANQAECgUICgAAAA==.',
Ey='Eyante:BAAANQAECgIIAgABNQAECggILAAcAGwiAA==.',
Fa='Faenerys:BAAANQADCgUJBQAAAA==.Faerundur:BAAANQAECgYIDwAAAA==.Falcor:BAAANQADCgMIAwAAAA==.Falmouth:BAAANQAECgUIDAAAAA==.',
Fe='Felco:BAABNQAECoEtAAIPAAgKSyX3AQBeAwAPAAgKSyX3AQBeAwAAAA==.Feltharion:BAAANQAECgEIAQAAAA==.',
Fi='Fishing:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.Fitzjuno:BAAANQAECgUIEAAAAA==.',
Fl='Flannegan:BAAANQABCgIIAwAAAA==.Flasksaver:BAAANQADCgMIBgAAAA==.Flexgrip:BAAANQADCgEIAQABNQAECgUJDgABAAAAAA==.Flixxer:BAAANQAECgIIAgAAAA==.Floorpov:BAAANQAECgYICgABNQAECgcIEwABAAAAAA==.Flÿnn:BAAANQABCgQIBQAAAA==.',
Fo='Forgotthehot:BAAANQAECgQIBAAAAA==.Fortified:BAABNQAECoEgAAMCAAgKfhj5TAAVAgACAAgKfhj5TAAVAgAZAAIK4ghvXQBgAAAAAA==.Foxylàdy:BAAANQADCgQIBAAAAA==.',
Fr='Frostty:BAAANQAECggIBgAAAA==.',
Fu='Funkaspuck:BAAANQAECgMIAwAAAA==.',
Ga='Gaara:BAABNQAECoEWAAIdAAgK5A58LwDtAQAdAAgK5A58LwDtAQAAAA==.Gafgalron:BAAANQAECgUIDgAAAA==.Galadd:BAAANQADCgYIBgABNQAECgUJDgABAAAAAA==.Galadhunt:BAAANQADCgUIBQABNQAECgUJDgABAAAAAA==.Galatha:BAAANQAECgYICwAAAA==.Gama:BAAANQADCgYIDAAAAA==.Gamonwan:BAAANQABCgIIAgAAAA==.Gandoofus:BAABNQAECoEWAAIcAAgK0QzKvgDjAQAcAAgK0QzKvgDjAQAAAA==.Gardengnome:BAABNQAECoEbAAIcAAgKCwvsxwDRAQAcAAgKCwvsxwDRAQAAAA==.Garisashlong:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Garrot:BAAANQAFFAIIAgAAAA==.Gayren:BAAANQAECgQIBAAAAA==.',
Ge='Gerardway:BAAANQAECgYIBgAAAA==.',
Gi='Giga:BAABNQAECoEaAAIMAAcKWhEAhwDNAQAMAAcKWhEAhwDNAQAAAA==.Gigapal:BAAANQADCgUIBQAAAA==.Gigashadow:BAAANQADCgUIBQAAAA==.',
Gl='Glad:BAAANQAECgUJDgAAAA==.Glenix:BAAANQAECgYIBgABNQAECggIEQABAAAAAA==.Gluck:BAAANQADCgQIBAAAAA==.',
Go='Goosterfrad:BAAANQAECgcIEAAAAA==.',
Gr='Grampy:BAAANQADCgUIGAAAAA==.Greyparse:BAAANQAECgYIBgABNQAECgcIDwABAAAAAA==.Grundie:BAAANQADCgYIEAABNQAECgMIBQABAAAAAA==.',
Gu='Guldanramsey:BAAANQADCgUJCQAAAA==.Gullurg:BAAANQAECgIIBQABNQAECgYICQABAAAAAA==.Gutthisclass:BAAANQADCgUIBQAAAA==.',
Gw='Gweneviere:BAAANQAECgQICAAAAA==.',
['Gá']='Gáthix:BAAANQAECgIIAgAAAA==.',
['Gî']='Gîrth:BAABNQAECoEkAAIOAAkKpiB/FAA7AwAOAAkKpiB/FAA7AwABNQAFFAYICgAFAFcVAA==.',
Ha='Hades:BAAANQAECgUIDQAAAA==.Hadesfalcon:BAAANQAECgUIDgAAAA==.Hadesz:BAAANQAECgcIEQAAAA==.Hainne:BAAANQADCgYIBgAAAA==.Halfthore:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Hallack:BAAANQADCgYICwAAAA==.Handrob:BAABNQAECoEeAAIeAAgKwBrIXQBUAgAeAAgKwBrIXQBUAgAAAA==.Hanoii:BAABNQAECoEhAAQZAAgK6xaVHAA7AgAZAAgK6xaVHAA7AgACAAYKKhQ1dgCAAQADAAEKsQEtLQAeAAABNQAECgkJJwAOAAocAA==.Happyguy:BAAANQADCgcICwABNQAECgkJHAAaAG8iAA==.Harrier:BAAANQADCgIIBAABNQAECgUICQABAAAAAA==.Hayles:BAABNQAECoEcAAIfAAgKfh80CwDHAgAfAAgKfh80CwDHAgAAAA==.',
He='Healteamsix:BAABNQAECoEeAAIHAAgKBx7xLACKAgAHAAgKBx7xLACKAgAAAA==.Hebrews:BAAANQADCgYIBwABNQAECgUIDwABAAAAAA==.Het:BAAANQADCgYIBgAAAA==.',
Hi='Hideyoshi:BAAANQADCgYIDwAAAA==.Hilbilystrik:BAAANQADCgMIAwAAAA==.Hitowerr:BAAANQADCgYIGQAAAA==.',
Ho='Hollywoodx:BAABNQAECoEeAAIMAAgKag8vbwAHAgAMAAgKag8vbwAHAgAAAA==.Holymonty:BAAANQADCggIEAAAAA==.Hoofinit:BAAANQAECgEIAQAAAA==.Hormonemadme:BAAANQAECgEIAQAAAA==.Hottboi:BAAANQADCgQIBAAAAA==.',
Hu='Huangx:BAAANQAECgMICwAAAA==.Humungus:BAAANQAECggICAABNQAECgkJHAAaAG8iAA==.Husbones:BAABNQAECoEhAAIGAAgKTRlyLABKAgAGAAgKTRlyLABKAgAAAA==.Huszilla:BAABNQAECoEhAAMgAAcK6AewDgAsAQAgAAcK6AewDgAsAQALAAUK4ASUNQDIAAABNQAECggIIQAGAE0ZAA==.',
['Hó']='Hólynova:BAAANQAECgYIDwABNQAECggICwABAAAAAA==.',
Ia='Iamdrunk:BAAANQAECgUIBQAAAA==.Iamgroot:BAAANQAECgEIAQAAAA==.',
Ic='Icemanrec:BAAANQAECgMIBAAAAA==.Icwiener:BAAANQAECggIDwAAAA==.',
Ig='Igneel:BAAANQABCgMIAwAAAA==.Igniz:BAAANQAECgEIAQAAAA==.',
Il='Illyrion:BAAANQAECgUIBQAAAA==.',
Im='Immunity:BAAANQAECgQIDQAAAA==.',
In='Incarnacion:BAAANQABCgcIDAAAAA==.Indrä:BAAANQADCgQIBAAAAA==.Infernatus:BAAANQADCgIIAgAAAA==.Intome:BAAANQAECgUICQAAAA==.',
It='Itaska:BAABNQAECoEZAAMhAAcKRRA2FgApAQAhAAUKLRM2FgApAQAcAAUKjgt8LgEaAQAAAA==.Itfitzwell:BAAANQADCgYIFAAAAA==.',
['Iù']='Iùwúl:BAABNQAECoElAAIiAAgKfCRyBgAXAwAiAAgKfCRyBgAXAwAAAA==.',
Ja='Jackmage:BAAANQADCgUIBQAAAA==.Jameywomp:BAAANQAECgQICAABNQAECgcIEwABAAAAAA==.',
Je='Jegra:BAAANQAECgUIBQABNQAECgcIHwANAK4gAA==.Jellyfingerz:BAAANQAECgEJAQAAAA==.Jestik:BAABNQAECoEXAAIGAAcKOBo4PwDjAQAGAAcKOBo4PwDjAQAAAA==.',
Jh='Jhyl:BAAANQAECgUIEAAAAA==.',
Ji='Jimithing:BAAANQADCgYIBwAAAA==.Jinu:BAAANQAECgUICwAAAA==.',
Jl='Jl:BAAANQAECgUIDQABNQAECgYICAABAAAAAA==.',
Jo='Joherys:BAAANQAECggIAQAAAA==.Joints:BAAANQAECggIDwAAAA==.Jordroy:BAABNQAECoEtAAIbAAkKACUuCACtAwAbAAkKACUuCACtAwAAAA==.',
['Jæ']='Jægeren:BAAANQADCgIJAgABNQAFFAEIAQABAAAAAA==.',
Ka='Kaanuu:BAAANQAECgUIDwAAAA==.Kaargadin:BAAANQADCgMIAwAAAA==.Kabbage:BAAANQAECgUIEgAAAA==.Kablam:BAABNQAECoEvAAIOAAkK8iEREABaAwAOAAkK8iEREABaAwAAAA==.Kadon:BAAANQADCgYIDAABNQADCggIDwABAAAAAA==.Kalindigo:BAAANQAECgYIEgAAAA==.Kalter:BAAANQAECgEJAgAAAA==.Kamarigh:BAAANQADCgUIDQAAAA==.Kamui:BAABNQAECoEpAAMQAAkK6iJRBwBcAwAQAAkKoyJRBwBcAwARAAQKVCCDcgAmAQAAAA==.Kappa:BAABNQAECoEVAAINAAgKixIiIwDgAQANAAgKixIiIwDgAQAAAA==.Kapreesun:BAAANQADCggIEAABNQAECgYICQABAAAAAA==.Kaprisun:BAAANQAECgYICQAAAA==.Kapu:BAAANQAECgEIAQAAAA==.Karynnora:BAABNQAECoEaAAIVAAcKuwEWuQDgAAAVAAcKuwEWuQDgAAAAAA==.Karziz:BAAANQADCgYIDgAAAA==.Kashaani:BAAANQADCgUIBAAAAA==.',
Ke='Kelibarranth:BAAANQAECgIIBAAAAA==.Kemanthuurel:BAABNQAECoEbAAIgAAcKzgy4DABcAQAgAAcKzgy4DABcAQAAAA==.Keyhook:BAAANQAECgQICwAAAA==.',
Kh='Khaoticus:BAAANQAECgUICQAAAA==.',
Ki='Kickpow:BAAANQADCgYIBwAAAA==.Killayla:BAAANQADCggIEAAAAA==.Killerelvis:BAABNQAECoEeAAMVAAgKkRbLWADtAQAVAAcKohbLWADtAQAeAAcKOhhGhQDqAQAAAA==.Kittens:BAAANQADCgUIBQAAAA==.',
Kn='Knollyeti:BAAANQAECgUICwAAAA==.',
Ko='Koalajin:BAABNQAECoEWAAIcAAgKFQoL3QCoAQAcAAgKFQoL3QCoAQAAAA==.Kobi:BAAANQADCgUIEAAAAA==.Kopróx:BAAANQAECgMIBgABNQAECggIHAAFAHYaAA==.Korfane:BAABNQAECoEfAAIEAAcKCR2BGwAwAgAEAAcKCR2BGwAwAgAAAA==.Koteega:BAAANQADCgYIBgAAAA==.',
Kr='Krazystrike:BAAANQAECgUIEwAAAA==.Kryptonikz:BAAANQAECgUIEQAAAA==.',
Ku='Kuber:BAABNQAECoEsAAMFAAkKsRGLcgDgAQAFAAcKAhOLcgDgAQAIAAMK5wldSACcAAAAAA==.',
Ky='Kybria:BAAANQABCgEIAQAAAA==.',
La='Laelene:BAAANQADCgYIEQAAAA==.Lalabelle:BAAANQABCgIIAgAAAA==.Lamonda:BAAANQADCgcIBwAAAA==.Layn:BAAANQADCgcICAAAAA==.Laytnight:BAAANQAECggIBwAAAA==.',
Le='Lehsmit:BAABNQAECoEiAAIOAAkKohwvJADWAgAOAAkKohwvJADWAgAAAA==.Lemonpoppy:BAABNQAECoEVAAIUAAgKCxmKHQBIAgAUAAgKCxmKHQBIAgABNQAECggIGAAaADkeAA==.',
Li='Lilspuds:BAAANQAECgYICQAAAA==.Lilyame:BAAANQAECgEIAQAAAA==.Littlesam:BAAANQAECgUIBQAAAA==.',
Ll='Llucas:BAABNQAECoEiAAIRAAgK3CWyFQD1AgARAAgK3CWyFQD1AgAAAA==.Lluther:BAAANQAECggICAAAAA==.Lluthrall:BAAANQAECgcIEAAAAA==.',
Lo='Locian:BAABNQAECoEjAAMXAAgKAQfzFQDDAAAFAAgK7QYSlACEAQAXAAUKowPzFQDDAAAAAA==.Lockbox:BAAANQAECgcIBwABNQAECgcIEAABAAAAAA==.Locked:BAAANQAECgUIEQAAAA==.Locnismonstr:BAAANQADCgUIBQAAAA==.Lolzsec:BAAANQADCgYIEwAAAA==.Loycen:BAABNQAECoEsAAIjAAkKSSZpAADrAwAjAAkKSSZpAADrAwAAAA==.',
Lu='Lucàs:BAACNQAFFIEGAAIJAAIKRxrXGACrAAAJAAIKRxrXGACrAAA1AAQKgSoAAgkACQqfJDQEALIDAAkACQqfJDQEALIDAAAA.Lunarosá:BAABNQAECoEkAAIMAAgKGxLKYAArAgAMAAgKGxLKYAArAgAAAA==.Lustra:BAAANQADCggIDgAAAA==.Lustyrusty:BAAANQAECgEIAQAAAA==.',
Ly='Lykiri:BAAANQADCggIEQAAAA==.Lyllyth:BAAANQAECgcIEwAAAA==.Lyric:BAAANQAECgYIDwAAAA==.Lysandraa:BAAANQAECgUIEAAAAA==.',
Ma='Madren:BAAANQAECgUIEAAAAA==.Magari:BAAANQADCggICwAAAA==.Magicspell:BAAANQADCgYIBgAAAA==.Magz:BAAANQADCgQIBAAAAA==.Maidro:BAAANQADCgYICgAAAA==.Maitotem:BAAANQADCggIFAAAAA==.Maituli:BAAANQADCgYJFQAAAA==.Malhus:BAAANQAECgQIBAAAAA==.Manu:BAAANQAECgQICwAAAA==.Maplefoxx:BAABNQAECoEkAAINAAgK6BQ4HgAVAgANAAgK6BQ4HgAVAgAAAA==.Maragosa:BAAANQAECgMIBAAAAA==.Marlik:BAAANQADCgMIBAAAAA==.Mashadar:BAAANQAECgUICQAAAA==.Matthew:BAAANQADCgQIBAAAAA==.',
Mc='Mcstuffíns:BAAANQAECgUICwAAAA==.',
Me='Mechaorcleb:BAAANQAECgcIDwAAAA==.Meducea:BAAANQADCgUIGAAAAA==.Meea:BAAANQAECgMIBQAAAA==.Meegzies:BAAANQAECgYICAAAAA==.Megadööm:BAABNQAECoEgAAMeAAgKLBrecQAdAgAeAAgKLBrecQAdAgAVAAIKhgQ49wBVAAAAAA==.Megz:BAAANQADCgUIBQAAAA==.Megzi:BAAANQADCgIIAgAAAA==.Megzies:BAAANQAECgQIBwAAAA==.',
Mi='Mikethemge:BAAANQAECgUICgAAAA==.Mikori:BAABNQAECoEdAAMcAAcKqSBweAB3AgAcAAcKqSBweAB3AgAhAAEKExf+NwBGAAAAAA==.Mikura:BAAANQABCgUIBQAAAA==.Ministerry:BAAANQADCgcICgAAAA==.Mithael:BAAANQADCgUICgAAAA==.',
Mn='Mnementh:BAAANQABCggIEgAAAA==.',
Mo='Mobium:BAAANQAECgYIDgAAAA==.Monolith:BAAANQADCgQIBAABNQAECgYIEgABAAAAAA==.Montyopython:BAAANQAECgUIDwAAAA==.Moocowd:BAABNQAECoEaAAMeAAgKlR9INwDQAgAeAAgKlR9INwDQAgAVAAEKAAb/BAE3AAAAAA==.Mookie:BAAANQABCgQIBgAAAA==.Mordsithcara:BAAANQAECgIIAgAAAA==.Morganian:BAAANQAECgYICAAAAA==.Morlen:BAAANQABCgQIBQAAAA==.Mortissia:BAAANQADCgUICAAAAA==.Motodk:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.Motoguerr:BAAANQAECgEIAgAAAA==.Mozzie:BAAANQAECgUIDAAAAA==.Mozzofdeath:BAAANQADCggICAAAAA==.',
Mu='Muertenoche:BAAANQADCgUIEAAAAA==.Murista:BAABNQAECoEdAAIiAAcKbxiPFQD1AQAiAAcKbxiPFQD1AQAAAA==.Mushy:BAAANQADCgYIBgABNQAFFAQICAATANEYAA==.',
My='Mylke:BAAANQADCggIGwABNQAECgUIEwABAAAAAA==.Myronar:BAAANQADCgUIBgAAAA==.Mysery:BAAANQADCggIDgAAAA==.Myslicer:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.Mysticdragon:BAAANQAECgUIEAAAAA==.',
['Má']='Máylyn:BAAANQAECgEIAQAAAA==.',
['Mì']='Mìss:BAAANQADCgIIAgAAAA==.',
['Mó']='Mórrigan:BAAANQAECgQIBwAAAA==.',
Na='Naisary:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Namanari:BAAANQAECgYICwAAAA==.Narasha:BAAANQABCgcICQAAAA==.Nassa:BAAANQAECggIEQAAAA==.Nazzareth:BAAANQAECgcIEwAAAA==.',
Ne='Nefret:BAAANQAECgQICgAAAA==.Nest:BAAANQAECgcIDgAAAA==.Neverlied:BAAANQAECgUIDgAAAA==.Neversson:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Newsoul:BAAANQAECgEIAQAAAA==.Nexum:BAAANQAECgYIBwAAAA==.',
Ni='Nicolemarie:BAAANQAECgQIDAABNQAECgkJIgAVANohAA==.Niipplets:BAACNQAFFIEKAAQFAAYKVxUnCgCbAQAFAAUKxRUnCgCbAQAIAAEKLxMjFwBTAAAXAAEKZQDrEAAiAAA1AAQKgSAABAUACQpGIiYiAOQCAAUACQqQISYiAOQCAAgABgoTHbsQAOsBABcAAQofHMEmAEEAAAAA.Nilophyte:BAACNQAFFIEIAAIGAAQKUR1VDABgAQAGAAQKUR1VDABgAQA1AAQKgSMAAgYACQqXIA4RABEDAAYACQqXIA4RABEDAAAA.Ningning:BAAANQADCgYICwAAAA==.Ninzy:BAACNQAFFIEUAAMdAAYKshw3AgApAgAdAAYKshw3AgApAgAkAAQKUBT9BwBeAQA1AAQKgSUAAx0ACQrHJYgDAJADAB0ACQqNJYgDAJADACQACApeJDEMAKICAAAA.Nirazath:BAAANQADCgYIBgAAAA==.Nishino:BAAANQADCgUIBQAAAA==.Nito:BAAANQAECgYIEgAAAA==.',
No='Noirdesmort:BAAANQABCgYIBwAAAA==.Nolenardan:BAABNQAECoEeAAIMAAgKmBuGPQCOAgAMAAgKmBuGPQCOAgAAAA==.Norrakprime:BAAANQAECgYIEAAAAA==.Notspanky:BAABNQAECoEoAAMbAAkKOiT1FgBTAwAbAAkKjCL1FgBTAwAlAAYKqyROBgCCAgAAAA==.',
Ny='Nyxenya:BAABNQAECoEqAAIGAAkKIhbPKABfAgAGAAkKIhbPKABfAgAAAA==.Nyxnyx:BAAANQAECgEIAQABNQAECggIIgAVAHYTAA==.',
['Nô']='Nôvus:BAAANQAECgUIEAAAAA==.',
['Nÿ']='Nÿx:BAAANQADCggJCAAAAA==.',
Og='Ogtree:BAAANQADCgYIBgABNQAECgcIHwANAK4gAA==.',
Ol='Oldpriestguy:BAAANQADCgEIAQAAAA==.',
Or='Orchestral:BAAANQAECgIIAwAAAA==.Orgazmoo:BAAANQADCgQIBAAAAA==.Ortem:BAAANQAECgYJAgAAAA==.',
Pa='Pagtuga:BAAANQADCgYIEQAAAA==.Palamine:BAAANQADCggIFgAAAA==.Palasqueeze:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.Palicombat:BAAANQADCgYIBgAAAA==.Palyfail:BAAANQADCgQIBAAAAA==.Pastordiddy:BAAANQAECgEIAQABNQAECgcIEwABAAAAAA==.',
Pe='Peenuts:BAAANQAECgYIEAAAAA==.Pesha:BAAANQABCgQIAwABNQAECgYIDwABAAAAAA==.Petals:BAAANQAECgIIAwAAAA==.',
Ph='Phandapart:BAAANQAECgQICAAAAA==.',
Pi='Piip:BAAANQAECgYIEAAAAA==.',
Pl='Plushfire:BAAANQADCggIEwAAAA==.',
Po='Pokcmvmxckm:BAABNQAECoEZAAIMAAcKuxStdQD2AQAMAAcKuxStdQD2AQAAAA==.Pokcmxmvkcm:BAAANQADCgUIBwAAAA==.Porthubdtcom:BAAANQAECgUIBQAAAA==.',
Pr='Preyed:BAAANQADCgYICgAAAA==.Primora:BAAANQAECgIIAwAAAA==.Protocol:BAAANQAECgUIEAAAAA==.',
Pt='Ptsdthegamer:BAAANQADCgYIGQAAAA==.',
Pu='Pugg:BAAANQAECgYIDQAAAA==.Purplecrayon:BAAANQAECgcJDwAAAA==.',
['Pø']='Pøisonivy:BAAANQAECgUIBQABNQAECggIGgAVAKAlAA==.',
Ra='Rads:BAAANQADCggICQAAAA==.Raiden:BAAANQAECgMIAwABNQAECggIGgAVAKAlAA==.Raimee:BAAANQAECgcIDQAAAA==.Raistim:BAAANQABCgQJCAAAAA==.Rameth:BAAANQADCggIIwABNQAECgYIHAAUABsUAA==.Ranji:BAAANQADCgQICAAAAA==.Ranmojo:BAAANQADCgcICgAAAA==.Ravenholm:BAAANQAECgIIAgAAAA==.Rayn:BAAANQAFFAEIAQAAAA==.Raynes:BAAANQADCgEIAQABNQAECggIHAAfAH4fAA==.',
Re='Redlikeroses:BAAANQAECgQICQAAAA==.Reygar:BAAANQADCggIGwABNQAECggIGwACADkNAA==.',
Rh='Rhickssyn:BAABNQAECoEnAAQZAAgKHBgHGwBNAgAZAAgKHBgHGwBNAgACAAQKpg1bpQDqAAADAAQK/QXDFgCnAAAAAA==.Rhyleejo:BAAANQADCgUIGAAAAA==.Rhyzamel:BAAANQADCgYIGQAAAA==.',
Ri='Rictuss:BAAANQADCgIIAgAAAA==.Riias:BAAANQAECgIIAgAAAA==.',
Ro='Rocq:BAABNQAECoEeAAICAAgKYxeIQABDAgACAAgKYxeIQABDAgAAAA==.Rogust:BAAANQADCgEIAQAAAA==.Rongo:BAAANQADCggIHQAAAA==.',
Ru='Rustybeer:BAAANQAECgYIDgAAAA==.',
Ry='Rynia:BAAANQAECgMIAwAAAA==.',
['Rí']='Ríddíck:BAAANQAECgEIAQAAAA==.',
['Ró']='Róxas:BAAANQAECgIIBQAAAA==.',
Sa='Sadîst:BAABNQAECoEgAAMZAAkKDAsOKQC4AQAZAAgK3AsOKQC4AQACAAcKiwdCjgAwAQAAAA==.Sanloran:BAAANQABCgIIAgAAAA==.Sarasvati:BAABNQAECoEsAAMEAAkKQwxEJADUAQAEAAkKQwxEJADUAQAJAAEKtQADuAAWAAAAAA==.Sartoss:BAAANQADCgUIBQAAAA==.Savriemina:BAABNQAECoEfAAIiAAkKnB1aCQDaAgAiAAkKnB1aCQDaAgAAAA==.Sayakaa:BAAANQADCgYIBgABNQAFFAQICAAGAHgbAA==.',
Sc='Scallion:BAAANQAECgcIEAAAAA==.Scynth:BAAANQADCggICAAAAA==.',
Se='Seamorebuttz:BAAANQADCgUJBgAAAA==.Selaestra:BAAANQADCgYIBgAAAA==.Semara:BAAANQAECgYIEAAAAA==.Semya:BAAANQAECgUICwAAAA==.Semí:BAAANQAECgQIBAAAAA==.Seradk:BAAANQAECgIIAgAAAA==.Seraphíne:BAACNQAFFIERAAICAAYKDxq7BQAZAgACAAYKDxq7BQAZAgA1AAQKgSQAAgIACQrsI3sLAFUDAAIACQrsI3sLAFUDAAAA.Serial:BAAANQAECgYIBgAAAA==.Serzul:BAAANQAECgYIEQAAAA==.Sewazbek:BAAANQAECgcIDwAAAA==.',
Sh='Shadhuan:BAAANQAECgUIBgAAAA==.Shadowhayze:BAABNQAECoEYAAIaAAgKOR4kCQDSAgAaAAgKOR4kCQDSAgAAAA==.Shamanate:BAAANQAECgUICgAAAA==.Shamanizer:BAAANQADCgYICgAAAA==.Shamuljakson:BAABNQAECoEYAAIOAAcKfREQagCyAQAOAAcKfREQagCyAQAAAA==.Sharana:BAAANQADCgUIBQAAAA==.Sharin:BAAANQADCgYIEQAAAA==.Sheprock:BAAANQABCgMIAgABNQAECgYIDwABAAAAAA==.Shevraeth:BAAANQADCgYIDwABNQAECgcIHwACAFIhAA==.Shizhisjiz:BAAANQAECgcIEwAAAA==.Shrilla:BAAANQAECgUIEAAAAA==.',
Si='Sidonay:BAABNQAECoEcAAMFAAgKdhqRPACCAgAFAAgKdhqRPACCAgAIAAIKOwYqYQBXAAAAAA==.Sigil:BAAANQAECgcIEgAAAA==.Sikathor:BAAANQADCgYICAABNQAECgYICAABAAAAAA==.Sikodeath:BAAANQAECgYICAAAAA==.Sikomode:BAAANQAECgQIBgABNQAECgYICAABAAAAAA==.Simplysinful:BAABNQAECoEqAAQXAAgKDR0dBACCAgAXAAgKDR0dBACCAgAFAAYKqhQ3jgCUAQAIAAIKsRGqUACBAAAAAA==.Sims:BAABNQAECoEcAAMFAAgK+hvGNgCVAgAFAAgK+hvGNgCVAgAIAAEKBQkOdQAzAAAAAA==.Sinnershep:BAAANQAECgYIDwAAAA==.Siouxii:BAAANQAFFAEIAQAAAA==.',
Sk='Skul:BAAANQAECgYIDgAAAA==.',
Sl='Slannen:BAAANQADCgUIBQAAAA==.Slatag:BAAANQAECgYIDQAAAA==.Slime:BAACNQAFFIEZAAMTAAcKpSKVAAC+AgATAAcKbiKVAAC+AgASAAEK4yKvFgBoAAA1AAQKgToAAxIACQpuJrgBANcDABIACQoBJbgBANcDABMACQrjJVcBANUDAAAA.Slugbug:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.',
Sm='Smashcombat:BAAANQAECgEIAQAAAA==.',
So='Soiledsoul:BAAANQADCggIFwAAAA==.Sojourner:BAAANQAECgUIEAAAAA==.Sonyafey:BAAANQADCggICAAAAA==.Soo:BAAANQADCgQIBAAAAA==.',
Sp='Sparklenips:BAAANQAECgUIDAAAAA==.Sprig:BAABNQAECoEZAAMOAAgKVBPmUgAAAgAOAAgKVBPmUgAAAgAaAAEKWwDLNAAXAAAAAA==.Sprite:BAAANQADCgQIBAABNQAECgYICAABAAAAAA==.Spritezero:BAAANQAECgYICAAAAA==.',
St='Staraynne:BAAANQADCgUIGAAAAA==.Starfiery:BAAANQAECgEIAQAAAA==.Starheist:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.Starmaster:BAAANQADCggIIQABNQAECgEIAQABAAAAAA==.Steaktacular:BAAANQADCgYIDAAAAA==.Sterbefall:BAAANQADCggIFAAAAA==.Stihll:BAABNQAECoEdAAIMAAcKtBqJXwAuAgAMAAcKtBqJXwAuAgAAAA==.Storming:BAAANQADCgYIFAAAAA==.Stormlight:BAABNQAECoEkAAICAAgK5AotbwCYAQACAAgK5AotbwCYAQAAAA==.Strea:BAAANQADCggICAAAAA==.Stretchnutz:BAAANQADCgIIAgAAAA==.',
Su='Sunjia:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.',
Sw='Sweetangel:BAAANQAECgQICAAAAA==.',
Sy='Synclaar:BAABNQAECoEmAAMYAAkKpQpUIgA/AQAJAAcKlQpmUgBmAQAYAAgKpQhUIgA/AQAAAA==.Syrioûs:BAAANQADCgYICgAAAA==.Syskar:BAAANQADCgEIAQAAAA==.',
['Så']='Såyoko:BAAANQAECgYIEwAAAA==.',
['Sé']='Séptember:BAAANQAECgYIBgAAAA==.',
['Sí']='Sízzle:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.',
['Sø']='Søøner:BAAANQADCgcIBwAAAA==.',
Ta='Tadinanefer:BAAANQADCgQICAAAAA==.Tailstwo:BAABNQAECoEZAAIMAAcKuwu6mACjAQAMAAcKuwu6mACjAQAAAA==.Taintshockur:BAAANQAECgEIAQAAAA==.Talmi:BAAANQADCgUIEAAAAA==.Tamiria:BAAANQAECgQICgAAAA==.Tanora:BAAANQAECgUIBgAAAA==.Taterbeast:BAAANQADCgEIAQAAAA==.',
Te='Terademon:BAAANQAECgUICwAAAA==.Teraknightt:BAAANQAECgcIEwAAAA==.Terryfic:BAAANQADCggIEAAAAA==.Tethlis:BAAANQAECgcIBwABNQAECgcJFwAGADgaAA==.',
Th='Thecollector:BAAANQADCgUIBQAAAA==.Thecurrybear:BAAANQAECgUICAAAAA==.Thefearful:BAABNQAECoEbAAQCAAkKphhuZwC0AQACAAcKtBZuZwC0AQAZAAUKjBajNwBBAQADAAEK4QeNKgApAAAAAA==.Thejin:BAAANQADCgQIBQAAAA==.Thelios:BAABNQAECoEtAAIFAAgKKxOxagD2AQAFAAgKKxOxagD2AQAAAA==.Theomore:BAAANQAECgIIAwAAAA==.Thicci:BAAANQADCgQIBAABNQAECggIHAANAKQeAA==.Thierryjames:BAAANQAECgEIAQAAAA==.Thisisfunny:BAAANQABCgIIAgAAAA==.Thragar:BAABNQAECoEdAAIMAAcKUyLFMQC0AgAMAAcKUyLFMQC0AgAAAA==.Thrina:BAABNQAECoEZAAIhAAYKrBu6CgDnAQAhAAYKrBu6CgDnAQAAAA==.Thuss:BAAANQAECgYIEwAAAA==.Thyrin:BAAANQABCgYIBgAAAA==.',
Ti='Timtalks:BAABNQAECoEcAAIHAAgKCheTTAAFAgAHAAgKCheTTAAFAgAAAA==.Tiryen:BAAANQADCgEIAQAAAA==.Titan:BAAANQADCgQJCwAAAA==.',
Tm='Tmagnome:BAAANQADCgYICgABNQAECgIIAwABAAAAAA==.',
To='Toobyfour:BAAANQABCgcIDQAAAA==.Tooggy:BAACNQAFFIEGAAIMAAMK6xBoEgAAAQAMAAMK6xBoEgAAAQA1AAQKgTwAAgwACQp9IxUFALADAAwACQp9IxUFALADAAAA.Toogy:BAAANQADCgQIBAABNQAFFAMIBgAMAOsQAA==.',
Tr='Tremira:BAAANQADCgEIAQAAAA==.Trickshot:BAAANQADCggIHQAAAA==.Trinighte:BAAANQABCgEIAQAAAA==.Trogdot:BAAANQADCgYIBgAAAA==.Trogstomp:BAAANQAECgUIEwAAAA==.Trus:BAAANQADCgIIAgAAAA==.Tryxze:BAAANQAECgcJDQAAAA==.',
Tu='Tuatha:BAABNQAECoEsAAIcAAkK1x/KQwDuAgAcAAkK1x/KQwDuAgAAAA==.Tubesock:BAAANQABCgEIAQAAAA==.',
Tw='Twisteddeath:BAAANQADCgIIAgABNQAECggIGgAVAKAlAA==.Twistedlight:BAABNQAECoEaAAMVAAgKoCX0CAB0AwAVAAgKoCX0CAB0AwAeAAEKXxR+agE6AAAAAA==.',
Ty='Tygraen:BAAANQAECgEJAQABNQAFFAIIAgABAAAAAA==.Tygroen:BAAANQAFFAIIAgAAAA==.',
['Tà']='Tàllàhàssee:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
['Tø']='Tønga:BAAANQADCgQIBAAAAA==.',
Ud='Uday:BAAANQAECggIBAABNQAECgkJHAAaAG8iAA==.',
Uh='Uhohdh:BAACNQAFFIEIAAITAAQK0RiuBwBdAQATAAQK0RiuBwBdAQA1AAQKgSMAAhMACQq2JJsFAHIDABMACQq2JJsFAHIDAAAA.',
Um='Umira:BAAANQADCgYIBgAAAA==.',
Un='Uncledeath:BAAANQAECggICwAAAA==.Unos:BAAANQAECggIAQAAAA==.Unosdk:BAAANQADCgQIBAABNQAECggIAQABAAAAAA==.',
Ur='Uranium:BAAANQADCgMIBwABNQAECgcIJgAJADogAA==.',
Us='Usva:BAAANQADCgYIDwAAAA==.',
Va='Vaiygarshprd:BAABNQAECoEmAAMdAAkKyQx0KwAIAgAdAAkKyQx0KwAIAgAkAAMKlQKuQgBzAAAAAA==.Valhalla:BAAANQAECgIIAwAAAA==.Valreth:BAAANQADCgUIBwAAAA==.Valtorin:BAAANQADCgUIBQAAAA==.Vandalize:BAABNQAECoEWAAIeAAcKgQ+BpACfAQAeAAcKgQ+BpACfAQAAAA==.Vandrayne:BAAANQAECgEIAQAAAA==.Vanitas:BAABNQAECoElAAMRAAgKgR/xLwBNAgARAAgKIB/xLwBNAgAQAAcKxxgmLQD/AQAAAA==.',
Ve='Veddar:BAAANQADCgQICAAAAA==.Veleice:BAAANQADCgMIAwAAAA==.Vellaide:BAABNQAECoEeAAIeAAgKGgqnrQCLAQAeAAgKGgqnrQCLAQAAAA==.Veltrafang:BAABNQAECoEfAAIMAAYKdQ8tpwCEAQAMAAYKdQ8tpwCEAQAAAA==.Veltramoon:BAAANQADCgIIAgABNQAECgYIHwAMAHUPAA==.Vennisa:BAACNQAFFIEQAAICAAYKQROyBwDwAQACAAYKQROyBwDwAQA1AAQKgTUAAwIACQoDIzsKAF8DAAIACQoDIzsKAF8DABkAAwpaCAVYAHgAAAAA.Vessryn:BAAANQAECgcIBwABNQAFFAMIBwAWACcUAA==.',
Vh='Vhelkan:BAABNQAECoEdAAIWAAgKHxkIBACPAgAWAAgKHxkIBACPAgAAAA==.',
Vi='Viciousvixen:BAAANQADCgcIDQAAAA==.',
Vr='Vraelin:BAAANQAECgcIDwAAAA==.',
['Vé']='Vélèdryke:BAAANQAECgIIAgABNQAECgkJIgAIAKIYAA==.',
Wa='Waltmallow:BAAANQADCgEIAQAAAA==.Warco:BAAANQADCgYIBgABNQAECggILQAPAEslAA==.Wardiv:BAAANQADCgUIFAAAAA==.Warfár:BAAANQADCgYIDgAAAA==.Wargazm:BAAANQADCgQJBAAAAA==.',
We='Wedel:BAAANQAECgYICAAAAA==.Wenixx:BAAANQADCgQIBAAAAA==.Wesleywillis:BAAANQABCgUIBgAAAA==.',
Wh='Whisperas:BAAANQADCggICQAAAA==.Whodahoda:BAAANQAECgQICAAAAA==.',
Wi='Wighal:BAAANQAECgUICAAAAA==.Wildbeaver:BAAANQADCgYIBgAAAA==.Willis:BAAANQADCgQIBQABNQAECgcIEAABAAAAAA==.Windfurry:BAABNQAECoEfAAMOAAcKjBJ5aAC2AQAOAAcKjBJ5aAC2AQAHAAQKGAl6xwCvAAAAAA==.Winsock:BAAANQADCgYICwAAAA==.',
Wo='Wolf:BAABNQAECoEcAAMHAAgKqyHdFQAGAwAHAAgKqyHdFQAGAwAaAAEKXQsNLwA9AAAAAA==.Woodhøuse:BAAANQADCgQIBQABNQAECgQIBwABAAAAAA==.Wookieebrew:BAAANQAECgYIDwAAAA==.Worbear:BAABNQAECoEiAAIYAAkK2B+RBAA6AwAYAAkK2B+RBAA6AwAAAA==.',
Wr='Wrent:BAAANQADCgEIAQAAAA==.',
Wu='Wumbo:BAABNQAECoEdAAITAAkK/w1rIgAXAgATAAkK/w1rIgAXAgAAAA==.',
Xa='Xandabull:BAAANQADCgUIGAAAAA==.Xaniengenn:BAAANQADCggICgAAAA==.',
Xe='Xem:BAAANQAECgQJBgAAAA==.Xen:BAABNQAECoEaAAISAAgKWSA2EwDmAgASAAgKWSA2EwDmAgAAAA==.Xeney:BAAANQAECgYICgAAAA==.Xenie:BAAANQADCgcIDAAAAA==.Xenity:BAAANQADCgUIBQAAAA==.Xenjoza:BAAANQAECgUIDgAAAA==.Xenpai:BAAANQADCgcICgAAAA==.Xens:BAAANQAECgQIEQAAAA==.Xeny:BAAANQADCgQIBAAAAA==.Xerorage:BAABNQAECoEiAAQlAAkKUx/8AgAXAwAlAAkKUx/8AgAXAwAbAAYKVRe3mwCtAQAjAAIKYQvgNgBIAAABNQAFFAEIAQABAAAAAA==.Xerorunes:BAAANQAFFAEIAQAAAA==.',
Xo='Xochil:BAAANQAECgYIEgAAAA==.',
Xp='Xp:BAAANQAECgUIBQAAAA==.Xplosionmage:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.',
Ya='Yakov:BAAANQADCgUIBgAAAA==.',
Ye='Yeezùs:BAABNQAECoEcAAINAAgKpB69EgCkAgANAAgKpB69EgCkAgAAAA==.Yesican:BAAANQADCgYIBgAAAA==.',
Yi='Yimiru:BAAANQAECgEIAQABNQAECgMICwABAAAAAA==.',
Yu='Yuffie:BAAANQAECgIIAwAAAA==.Yumikiim:BAABNQAECoEiAAMHAAkK2xtaIgC/AgAHAAkK2xtaIgC/AgAOAAcK1BDubQCmAQABNQAECgkJIgAVANohAA==.',
Za='Zaknafein:BAABNQAECoEZAAMdAAcKihakMQDfAQAdAAYKGxmkMQDfAQAkAAYKpwjcKgBRAQAAAA==.Zanazoth:BAABNQAECoElAAIaAAkKIyThAQCWAwAaAAkKIyThAQCWAwAAAA==.Zandinja:BAAANQADCgUIBQAAAA==.Zankir:BAAANQADCgMIAwAAAA==.Zanziri:BAAANQAECgUICQAAAA==.',
Ze='Zeffyre:BAAANQAECgEIAQAAAA==.Zepher:BAAANQAECgIIAwAAAA==.Zerdirk:BAAANQAECgQIBAABNQAECgkJLAARAAQdAA==.',
Zh='Zhero:BAAANQADCgEIAQABNQAECgYICAABAAAAAA==.Zhífù:BAAANQADCgQIBAAAAA==.',
Zi='Zillaby:BAABNQAECoEsAAIcAAgKbCI6PwD5AgAcAAgKbCI6PwD5AgAAAA==.Zimbobway:BAAANQADCgIIAgABNQAECgQICAABAAAAAA==.Zindori:BAABNQAECoEiAAIVAAkK2iFqCQBwAwAVAAkK2iFqCQBwAwAAAA==.Ziploc:BAAANQADCgMIAwABNQAECgUJDgABAAAAAA==.',
Zl='Zlup:BAABNQAECoEWAAIbAAgKVyLsJwAKAwAbAAgKVyLsJwAKAwAAAA==.',
Zo='Zodiark:BAAANQADCgYIDwAAAA==.Zohan:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Zol:BAAANQADCgYIBgAAAA==.Zoltair:BAAANQAECgUICQAAAA==.',
Zr='Zroth:BAAANQADCgYIDAAAAA==.',
Zu='Zugadin:BAABNQAECoEbAAIeAAcKCBecgQD0AQAeAAcKCBecgQD0AQAAAA==.Zugthoth:BAAANQADCgYIDAABNQAECggIEwABAAAAAA==.Zukaya:BAAANQAECgUIEAABNQAECgYICAABAAAAAA==.Zullivain:BAABNQAECoEsAAMRAAkKBB0qGgDVAgARAAkKBB0qGgDVAgAGAAcKkgykWgBmAQAAAA==.',
Zx='Zxinn:BAAANQADCgIIAgAAAA==.',
['Åc']='Åctaeon:BAAANQAECgQIBQAAAA==.Åcume:BAAANQADCggIDgAAAA==.',
['Ìi']='Ìiíith:BAAANQADCgYIBgABNQADCggJCAABAAAAAA==.',
['Ív']='Ívery:BAAANQAECgcICgAAAA==.',
['Íz']='Ízzÿ:BAAANQAECgQIBwAAAA==.',
['Ôm']='Ômëñ:BAAANQAECgQICAAAAA==.',
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
