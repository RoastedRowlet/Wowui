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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Warrior-Protection','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Warrior-Arms','Mage-Arcane','Mage-Frost','Druid-Feral','Monk-Brewmaster','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','Paladin-Retribution','Warlock-Affliction','DeathKnight-Blood','Shaman-Elemental','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Vengeance','Paladin-Protection','Druid-Guardian','Warrior-Fury','Hunter-BeastMastery','Shaman-Enhancement','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Devourer','DeathKnight-Unholy',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaragon:BAAANQAECgYIBgABNQAFFAcIFQABALUgAA==.',
Ab='Abysmal:BAAANQAECgQJDAAAAA==.',
Ad='Adame:BAAANQABCgUIBQAAAA==.',
Ae='Aeriona:BAAANQAECgYJEAAAAA==.Aerolock:BAAANQAECgEIAQABNQAECgcJDQACAAAAAA==.Aerosong:BAAANQAECgcJDQAAAA==.',
Af='Affalon:BAAANQAECgQJBAAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.Agemo:BAAANQABCgIIAgAAAA==.',
Ai='Aine:BAAANQAECggICQAAAA==.Ainkor:BAAANQAECgQIBQABNQAECgYIDwACAAAAAA==.',
Ak='Akyospirit:BAAANQAECgYJEAAAAA==.',
Al='Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAAANQAECgMIBAAAAA==.Allumin:BAAANQADCgcIBwAAAA==.Alpha:BAAANQAECgcJEwAAAA==.',
Am='Amamonk:BAAANQAECgYJBgAAAA==.Ammert:BAAANQADCggJDQAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAUJDgADAPUXAA==.Angliko:BAAANQADCgMJAwABNQAECgYJDQACAAAAAA==.Annei:BAABNQAECoEeAAMEAAgKeSLtGwCpAgAEAAYKoybtGwCpAgAFAAYKIhA+JQCEAQAAAA==.Anomandaris:BAAANQAECgIJBQAAAA==.Anquan:BAAANQAECgQIBAAAAA==.Anya:BAAANQAECgMIAwAAAA==.',
Ap='Apothica:BAAANQAECgYJCgAAAA==.Apothicc:BAAANQAECgMIBAABNQAECgYJCgACAAAAAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgUJDAAAAA==.',
Aq='Aquae:BAAANQAECgUJBQAAAA==.',
Ar='Arcohunt:BAAANQADCgcJBwABNQAECgUJDAACAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argodin:BAAANQAECgYIBQAAAA==.',
As='Asheritâ:BAAANQAECgEIAQAAAA==.Ashvalis:BAAANQAECgUICwAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECgUJCAAAAA==.Askr:BAAANQAECgQIBQAAAA==.Asphar:BAAANQAECgYJDAAAAA==.Asynic:BAAANQADCgYIEAABNQADCggICAACAAAAAA==.',
Au='Aung:BAABNQAECoEdAAIGAAgKbSTOBwBFAwAGAAgKbSTOBwBFAwAAAA==.Auri:BAAANQADCggJEwAAAA==.',
Av='Avitarkorra:BAAANQADCgcJBwAAAA==.',
Ax='Axex:BAAANQAECgIIAgAAAA==.',
Az='Azamii:BAAANQAECgYICwABNQAECgYJDwACAAAAAA==.Azarion:BAAANQAECgUICAAAAA==.Azill:BAABNQAECoEcAAIBAAkKsRz9CgDVAgABAAkKsRz9CgDVAgAAAA==.Azreial:BAAANQABCgYICgAAAA==.Azrëiäl:BAAANQADCgIIAgAAAA==.Azulon:BAAANQAECgIIAwAAAA==.Azurefury:BAAANQAECgUJCAAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.',
Ba='Bandi:BAAANQAECgEJBAAAAA==.Bartrak:BAAANQADCgIJAgABNQAECgIIAwACAAAAAA==.Battôsai:BAAANQAECgMJAwAAAA==.',
Be='Bearfucius:BAAANQAECgQICAAAAA==.Bearrific:BAAANQAECgUJCQAAAA==.Behomadra:BAAANQADCgMIAwAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAAANQAECgYIDQAAAA==.',
Bi='Billthekid:BAAANQADCgcIBwAAAA==.Binksy:BAABNQAECoEpAAIHAAkKVRsAIwDpAgAHAAkKVRsAIwDpAgAAAA==.Biscuit:BAACNQAFFIEOAAIDAAUK9RepAACwAQADAAUK9RepAACwAQA1AAQKgSIAAwMACQr6JNkAALYDAAMACQr6JNkAALYDAAcAAQrAEW3zAD4AAAAA.',
Bl='Blaam:BAAANQADCgYIDwAAAA==.Blazin:BAABNQAECoEkAAMIAAkKOSH6MwDxAgAIAAkK2SD6MwDxAgAJAAUKahvXCQCqAQAAAA==.Blinkzy:BAAANQADCgUICQABNQAECgkJKQAHAFUbAA==.Blitzoria:BAAANQADCgYIBgAAAA==.Bloui:BAAANQADCgUIDAAAAA==.Blueknight:BAAANQAECgUJCQAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Bobinsky:BAAANQADCgEIAQAAAA==.Borlok:BAAANQAECgYIEAAAAQ==.',
Br='Brannigan:BAABNQAECoEbAAIHAAgKGhweQQBiAgAHAAgKGhweQQBiAgAAAA==.Brannigandh:BAAANQAECgQJCgABNQAECggIGwAHABocAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQADCgYIDAAAAA==.Briantu:BAAANQADCggJCAAAAA==.Brickfelt:BAAANQABCgYICgAAAA==.Brickitphil:BAAANQAECgUICgAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Brustomp:BAAANQADCgYIBgABNQAECgIJAgACAAAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAAANQAECgQJBgAAAA==.Bulldan:BAAANQADCgYIBwAAAA==.Bullvi:BAAANQAECgMJAwAAAA==.',
['Bä']='Bärkler:BAAANQAECgUJBgAAAA==.',
['Bé']='Béckléy:BAABNQAECoEXAAIKAAkKLSLSAQBtAwAKAAkKLSLSAQBtAwAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Cali:BAAANQADCgYIBgAAAA==.Cannïbal:BAAANQADCgcIBwAAAA==.Cara:BAAANQADCgEIAQAAAA==.Carra:BAAANQAECgYIEAAAAA==.Cassiopeía:BAEANQAECgQIBQABNQAECgYJDAACAAAAAA==.Catriona:BAAANQAECgQJCgAAAA==.',
Ch='Charcuterie:BAACNQAFFIEOAAILAAUKVBGiAQBiAQALAAUKVBGiAQBiAQA1AAQKgR4AAgsACQqSIGsDABYDAAsACQqSIGsDABYDAAAA.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheezeburg:BAAANQAECgQIBwAAAA==.Chicken:BAAANQAECgcIBwABNQAFFAUJDgADAPUXAA==.Chikindalf:BAAANQADCgEJAQAAAA==.Chillidán:BAAANQAECgUJDQAAAA==.Choggie:BAAANQAECgcJEgAAAA==.',
Co='Cons:BAABNQAECoEcAAMEAAgKAiM9EAD8AgAEAAgKAiM9EAD8AgAMAAEKBAuQHQAyAAAAAA==.Corellon:BAAANQAECgYJCgAAAA==.',
Cr='Cranee:BAABNQAECoEcAAMNAAgKWRA8SgD2AQANAAgKWRA8SgD2AQAOAAIKqQL4VgBVAAAAAA==.Cranium:BAAANQAECggICAAAAA==.Crazytasty:BAAANQAECgYIEgAAAA==.',
Da='Dabora:BAABNQAECoEcAAMPAAgKpx1dDwCZAgAPAAgKpx1dDwCZAgAQAAIKEg4XEwBpAAAAAA==.Damassan:BAAANQABCgQJBAAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYICwABNQAECgUJCQACAAAAAA==.Darige:BAAANQAECgQJCgAAAA==.Darim:BAABNQAECoEVAAIRAAgKuRy+NwB1AgARAAgKuRy+NwB1AgABNQADCgYIBgACAAAAAA==.Darthspawn:BAAANQAECgMIBAAAAA==.Daryn:BAAANQAECgEIAQAAAA==.Davidbowy:BAAANQADCgQIBQABNQAECgIJAgACAAAAAA==.',
De='Deathollow:BAAANQADCgYIBgAAAA==.Demonainkor:BAAANQAECgEIAQABNQAECgYIDwACAAAAAA==.Demonicfury:BAAANQAECgIJAgAAAA==.Dencity:BAABNQAECoEdAAMEAAgKqhtQLwA6AgAEAAgKqhtQLwA6AgAMAAEK3wOwIAAmAAAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQADCgcICwABNQAECgYJEAACAAAAAA==.Devitodevour:BAAANQAECgYJEAAAAA==.Devwarr:BAAANQAECgIIAwABNQAECgYJEAACAAAAAA==.',
Dh='Dhbert:BAAANQAECgIJAgAAAA==.Dhomeli:BAAANQAECgIIAwAAAA==.',
Di='Dirtchez:BAAANQAECgQJBAAAAA==.Disastrophy:BAAANQAECgIIAgAAAA==.Disturbed:BAABNQAECoEcAAQNAAgKhhK5UwDSAQANAAcKmRC5UwDSAQAOAAIKqRkFQQCbAAASAAEKkwTQJAAtAAAAAA==.',
Dk='Dkson:BAABNQAECoEfAAITAAkKByAIDAAbAwATAAkKByAIDAAbAwAAAA==.',
Do='Docen:BAAANQADCggIGgAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.Download:BAAANQADCggICAAAAA==.',
Dr='Dragonfist:BAAANQAECgEJAQAAAA==.Dragthyr:BAAANQADCgUIDAAAAA==.Druiaier:BAAANQADCggIEwAAAA==.Druknatsu:BAAANQAECgEIAQAAAA==.',
Du='Dustyknight:BAAANQAECgQIBgAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgYICAAAAA==.',
Ed='Edge:BAAANQAECgUJCAAAAA==.',
El='Eleathe:BAAANQADCgYIBgAAAA==.Elgimpster:BAAANQADCgIIAgAAAA==.Elidoria:BAABNQAECoEcAAIIAAgKMBLfewAiAgAIAAgKMBLfewAiAgAAAA==.Elphinia:BAAANQADCgYJBgABNQAECggIFwAUAD4YAA==.',
En='Enoki:BAAANQAECggIDQABNQAFFAUJDAAVAIwUAA==.',
Ep='Ephodess:BAAANQADCggIGAAAAA==.',
Er='Eraduckated:BAAANQAECgYJDgAAAA==.',
Es='Esile:BAAANQAECgYJEAAAAA==.Esoryn:BAAANQAECgcJEwAAAA==.',
Ev='Everlife:BAAANQAECgEIAwAAAA==.Evilainkor:BAAANQAECgYIDwAAAA==.',
Ex='Exia:BAAANQAFFAMJBAAAAA==.',
Fa='Fauzzie:BAAANQAECgEIAQAAAA==.Fayrel:BAAANQAECgUJCAAAAA==.',
Fe='Fedders:BAABNQAECoEbAAIRAAgKlCPpEABOAwARAAgKlCPpEABOAwAAAA==.Felaids:BAABNQAECoEYAAQNAAgKYBUPfQBMAQANAAUKPBYPfQBMAQAOAAIKvxW2RwCEAAASAAIKDQlVFgBvAAAAAA==.Felnyx:BAAANQADCgYJCgAAAA==.Feor:BAAANQAECgEIAQAAAA==.Feralyn:BAAANQADCgYJCgAAAA==.Fero:BAAANQADCgUICAAAAA==.',
Fi='Fillon:BAACNQAFFIEJAAIRAAQK/RjtBABuAQARAAQK/RjtBABuAQA1AAQKgRwAAhEACQqOILYWACUDABEACQqOILYWACUDAAAA.Fionas:BAAANQAECgUJCAAAAA==.Firexcracker:BAAANQADCgQJBAAAAA==.Fishfood:BAAANQAECgYJDwAAAA==.Fixer:BAAANQAECgEIAQAAAA==.',
Fl='Flappysnail:BAAANQADCgUIBQAAAA==.Flatine:BAAANQADCgEIAQAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frazzle:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAAANQAECggIEQAAAA==.',
Fu='Fujitora:BAAANQADCggIBAAAAA==.Funbunz:BAAANQADCgMIAQAAAA==.',
['Fø']='Førd:BAABNQAECoEmAAQWAAkKmxskCADAAgAWAAkK9xckCADAAgAXAAcK9Rj8BQDzAQAYAAUKKgXzKgDMAAAAAA==.',
Ga='Gangrene:BAAANQAECgYIEAAAAA==.Gaspasser:BAAANQAECgIIAwAAAA==.Gaviin:BAAANQAECgYJBgAAAA==.Gazamiseh:BAAANQABCgIIAgAAAA==.',
Ge='Gearador:BAAANQADCgEIAQAAAA==.Genovia:BAAANQADCgQIBAABNQAECgIJAgACAAAAAA==.Gerhart:BAABNQAECoEWAAMGAAgKgxeTHwAfAgAGAAgK6RaTHwAfAgAZAAYKhBMHDABmAQAAAA==.',
Gi='Gigarius:BAAANQAECgQJCgAAAA==.Gizelia:BAAANQADCgEIAQAAAA==.',
Gl='Gleya:BAAANQADCgEIAQAAAA==.Gloomy:BAAANQADCgYIBgAAAA==.',
Go='Goblinsrhot:BAAANQADCgcIBwAAAA==.Goncor:BAAANQAECgEIAQABNQAECggIHgAEAHkiAA==.Gorrelord:BAAANQADCgIIAgABNQAECgkJJAAIADkhAA==.',
Gr='Gracze:BAAANQAECgUIBQAAAA==.Granolah:BAAANQAECgQJBQABNQAECggJHAAPAKcdAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgEIAQAAAA==.Griffmonk:BAAANQAECgYIDwAAAA==.Grumpymage:BAAANQAECgcJEgAAAA==.',
Gu='Gunjamomma:BAAANQADCgMIAwABNQADCgYIDQACAAAAAA==.',
Ha='Hafsac:BAAANQAECgMIAwAAAA==.Hamasakura:BAAANQADCggIDwAAAA==.Hardord:BAAANQADCggJHQAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Haryle:BAAANQADCggICAAAAA==.Hayanne:BAAANQAECgYIEAAAAA==.',
He='Healzjoogewd:BAAANQADCgYIBgAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.',
Hi='Hikary:BAAANQABCgIIAgAAAA==.',
Ho='Hochunk:BAAANQAECgYJCwAAAA==.Holikow:BAAANQAECgIJBQAAAA==.Holyherpies:BAAANQADCgYICwAAAA==.Holyness:BAAANQAECgQJCAAAAA==.Honeybunz:BAAANQADCgEIAQAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAABNQAECoEaAAMaAAgKohPwEQD7AQAaAAgKcBPwEQD7AQARAAcKrAschwBrAQABNQAECgkJHwAYAIghAA==.',
Hu='Hurano:BAAANQAECgQIBAAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIDgAAAA==.',
Id='Idyllwild:BAAANQADCggIGwAAAA==.',
Il='Illusiõn:BAAANQAECgQIBAAAAA==.',
In='Inducktive:BAAANQADCgIIAgABNQAECgYJDgACAAAAAA==.Inkdot:BAABNQAECoEWAAMVAAgKixwAKABqAgAVAAcKAB4AKABqAgARAAYKZBNyewCMAQAAAA==.Inkshield:BAAANQADCgYIBgABNQAECggIAQACAAAAAA==.Inkwell:BAAANQADCgYIBgABNQAECggJFgAVAIscAA==.Innerlight:BAAANQAECgEIAQAAAA==.',
Io='Iomedáe:BAAANQADCgMIAwAAAA==.',
Ir='Irishnight:BAAANQADCgQIBAABNQAECggIGQAbAPYNAA==.Ironlightnin:BAAANQADCgUIBQAAAA==.Irritate:BAAANQAECgEIAQAAAA==.',
Ja='Jakobo:BAAANQAECgYJCAAAAA==.Jandreyn:BAAANQADCgEIAQAAAA==.Jarthas:BAAANQADCgYIDAAAAA==.Jazlynel:BAAANQADCgYIBgAAAA==.',
Je='Jelly:BAACNQAFFIEMAAIVAAUKjBTuBACmAQAVAAUKjBTuBACmAQA1AAQKgR0AAxUACQrNH9AKAD4DABUACQrNH9AKAD4DABEAAQrdHy8EAVEAAAAA.Jenivira:BAAANQADCgMIAwAAAA==.',
Jo='Jozalin:BAAANQABCgMIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgMIBQAAAA==.Junknthtrunk:BAAANQADCgYJCAAAAA==.',
Ka='Kaelana:BAAANQABCgQJBQAAAA==.Kamahl:BAAANQAECgcJCwAAAA==.',
Ke='Keanew:BAAANQAECgUIDgAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIFwAAAA==.Keonna:BAAANQADCgUIDQAAAA==.Keppra:BAAANQADCggIEwAAAA==.Kerlin:BAAANQAECgMIBwAAAA==.',
Kh='Kheilah:BAAANQADCgEIAQAAAA==.Khurst:BAAANQAECgQJBAAAAA==.',
Ki='Kilaben:BAAANQAECgQIBwAAAA==.Kimmex:BAAANQADCgEIAQAAAA==.Kinoxo:BAACNQAFFIEKAAIHAAYKyxzeAgAuAgAHAAYKyxzeAgAuAgA1AAQKgSoAAwcACQpiJHEHAKADAAcACQpiJHEHAKADABwAAQpIIcwbAGEAAAAA.Kinozo:BAAANQAECgMIAwAAAA==.Kittyclysm:BAAANQADCgcIDQAAAA==.',
Ko='Kossuth:BAAANQABCgEIAQAAAA==.Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQADCgQIBAAAAA==.',
La='Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgUICQABNQAECgkJKQAHAFUbAA==.Leditoo:BAAANQADCggICAAAAA==.Legnase:BAAANQAECgYJDwAAAA==.Leiche:BAAANQAECgEIAwAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Liferia:BAAANQAECgYJBgAAAA==.Ligmabonez:BAAANQADCgcIFgAAAA==.Lilchloe:BAAANQADCgEIAQAAAA==.Lilnasty:BAAANQADCgMIAwABNQAECgQJDAACAAAAAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Littlefry:BAAANQABCgEIAQAAAA==.Livesey:BAAANQAECgUJCAAAAA==.',
Lo='Longshañk:BAAANQAECgUIDAAAAA==.',
Lu='Lucibrew:BAAANQAECgcJEQAAAA==.Luto:BAAANQAECggIAgAAAA==.',
Ma='Macpreizy:BAAANQADCgQICAAAAA==.Mattydruid:BAAANQAECgMIAwAAAA==.Mavramune:BAABNQAECoEfAAIdAAgKYxgaMgBrAgAdAAgKYxgaMgBrAgAAAA==.',
Mc='Mcfürry:BAAANQAECgIIAgAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECggJFgAeAG8YAA==.Mendinna:BAAANQADCggIHQABNQAECgQIBwACAAAAAA==.Mendoon:BAAANQAECgQIBwAAAA==.Methir:BAAANQADCgUIBQABNQAECgYIEAACAAAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAACNQAFFIEHAAIdAAQKQBMPBQBkAQAdAAQKQBMPBQBkAQA1AAQKgSoAAh0ACQoDJrMAAPUDAB0ACQoDJrMAAPUDAAAA.Mistborn:BAAANQAECggIAQAAAA==.',
Mo='Montebrew:BAAANQADCgYIBgABNQADCgcIBwACAAAAAA==.Montecane:BAAANQADCgcIBwAAAA==.Mooky:BAAANQAECgYJDgAAAA==.Moonfire:BAAANQAECggJCAAAAA==.Moriang:BAAANQADCgEIAQAAAA==.Moshicat:BAAANQAECgIIAgAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAAANQAECgQJCgAAAA==.',
Na='Nakir:BAAANQAECgIJBAAAAA==.Naraku:BAABNQAECoEfAAMOAAkKPRw7HwBTAQANAAYKuBm3VADPAQAOAAQKBRw7HwBTAQAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neebiter:BAAANQAECgYJBwAAAA==.Nehemez:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Neshock:BAAANQAECgIIAgABNQAECggJHQAfAEMbAA==.Nettie:BAAANQAECgEIAQABNQAECgIJAgACAAAAAA==.Netty:BAAANQAECgIJAgAAAA==.',
No='Noctyra:BAAANQADCgMIAwAAAA==.Novakayne:BAAANQADCgEIAQAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.',
Ny='Nymphetamine:BAAANQAECgMIBQAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAABNQAECoEWAAIgAAgKAwnLJACrAQAgAAgKAwnLJACrAQAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ou='Ouinur:BAAANQABCggICAABNQAECgQIBwACAAAAAA==.',
Ow='Owenwilson:BAAANQADCgUIBQAAAA==.',
Pa='Pandaloco:BAAANQADCgUIBwAAAA==.Pandalôc:BAAANQAECgEIAQAAAA==.Pandoe:BAACNQAFFIEOAAIbAAUKlyBZAAAAAgAbAAUKlyBZAAAAAgA1AAQKgScAAhsACQoNJnEAAOUDABsACQoNJnEAAOUDAAAA.',
Pe='Penelopea:BAAANQAECgQJBgAAAA==.Perun:BAAANQAECgUJBwAAAA==.',
Ph='Phenomenal:BAAANQAECgIIBAAAAA==.Pheonyx:BAAANQADCgYIEAAAAA==.',
Pi='Picarus:BAAANQADCgYIBgAAAA==.Picklerìck:BAAANQAECgIIBAAAAA==.',
Pl='Planb:BAAANQAECgUJCwABNQAECggIHAANAFkQAA==.',
Po='Porteagarder:BAAANQADCggIGwABNQAECgUIBwACAAAAAA==.',
Pr='Preparedpie:BAABNQAECoEsAAMhAAkKziDZBAByAwAhAAkKziDZBAByAwAGAAQKfg8SSQDBAAAAAA==.Pringler:BAAANQAECgYICgABNQAFFAUJDgADAPUXAA==.Producktive:BAAANQAECgIIAgABNQAECgYJDgACAAAAAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQADCggJFQABNQAECgYJEAACAAAAAA==.Príestly:BAAANQAECgQJBgAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQAECgQJBAAAAA==.',
Py='Pyatt:BAAANQAECgYJDQAAAA==.Pyromaniacal:BAAANQAECgQJBAAAAA==.',
Qu='Quack:BAAANQAECggJBwAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECggJBwACAAAAAA==.Quesoblanco:BAAANQADCgUICQAAAA==.Quilae:BAAANQADCggJFQABNQAECgUIBwACAAAAAA==.',
Qy='Qyburn:BAAANQAECgcJEQAAAA==.',
Ra='Radioface:BAAANQADCggICgAAAA==.Raerlynn:BAEANQADCgcJBwABNQAECgQIBgACAAAAAA==.Ragecage:BAAANQADCggICAABNQAECggIFAANAPgWAA==.Randivh:BAAANQADCgYJDAAAAA==.Rassputin:BAAANQAECgUICQAAAA==.',
Re='Recipes:BAAANQAECgIIAgABNQAECggIAQACAAAAAA==.Redbeardd:BAAANQADCgQIBAAAAA==.Reigwend:BAAANQADCgMIBQAAAA==.Remish:BAAANQABCgQIBgABNQAECgMIAwACAAAAAA==.Rendezvous:BAAANQADCgUIBQAAAA==.Renkà:BAABNQAECoEXAAIUAAgKPhh+KgBqAgAUAAgKPhh+KgBqAgAAAA==.Resmondo:BAAANQADCgcICQAAAA==.Revaerlous:BAABNQAECoEgAAIiAAgKnx5QEwDXAgAiAAgKnx5QEwDXAgAAAA==.',
Rh='Rheas:BAAANQADCgYIDAABNQAECgIJAgACAAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAUJDgADAPUXAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roereker:BAAANQADCggICAAAAA==.Roflsummon:BAAANQADCgEJAQABNQAECgIJAgACAAAAAA==.Roflthump:BAAANQADCgcJBwAAAA==.Roketraccoon:BAAANQADCggJEwAAAA==.Roshamandes:BAAANQAECgYJDQAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAgABNQAECgUJCQACAAAAAA==.',
['Rè']='Rèi:BAAANQAECgEJAQABNQAECgYIEgACAAAAAA==.',
Sa='Sabermage:BAAANQAECgIIAwAAAA==.Sacredchikín:BAAANQAECgcJEwAAAA==.Samuel:BAAANQAECgIIAgAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Sasukie:BAAANQAECgMIBAAAAA==.Saxa:BAAANQAECgYJDwAAAA==.',
Sc='Screamsoda:BAAANQAECgIJAwABNQAECggIAQACAAAAAA==.Scrubzz:BAAANQAECgUJCwAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekolock:BAAANQAECgQICAAAAA==.Seyekosis:BAAANQAECgYJCgAAAA==.',
Sg='Sgathaich:BAEANQAECgQIBgAAAA==.',
Sh='Shallistiah:BAAANQAECgUJDwAAAA==.Shamadin:BAAANQADCgEJAQAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgUICgAAAA==.Shamdh:BAAANQAECgYJBgAAAA==.Shamdwarf:BAAANQADCgcICgAAAA==.Shamuel:BAAANQADCgYIBgAAAA==.Shiftnfard:BAAANQADCggIDgAAAA==.Shobadon:BAAANQADCgEIAQAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgQIBwAAAA==.',
Si='Siatral:BAABNQAECoEfAAIYAAkKiCGLAwBcAwAYAAkKiCGLAwBcAwAAAA==.Siete:BAAANQAECgQICQAAAA==.Siggopotomus:BAAANQAECgIJAgAAAA==.Sigvolden:BAAANQAECgEJAQABNQAECgIJAgACAAAAAA==.Silchar:BAAANQADCgEIAQAAAA==.Silicon:BAAANQAECgUJDAAAAA==.Silver:BAAANQAECgIIAgABNQAECgUJDAACAAAAAA==.Siona:BAAANQAECgYIEAAAAA==.Sixpaths:BAAANQAECgYIEwABNQAECggIAQACAAAAAA==.Siyunkai:BAEANQAECgIIAwAAAA==.',
Sk='Skadie:BAAANQAECgYJDAAAAA==.Skittellz:BAAANQABCgMIAwAAAA==.Skiye:BAAANQADCgEIAQAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgACAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgACAAAAAA==.Skwup:BAABNQAECoEhAAMVAAkK4RjqGADIAgAVAAkK4RjqGADIAgARAAQKKRasqgATAQAAAA==.',
Sl='Slackness:BAAANQADCgQIBAAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggJCQABNQAECgkJJAAIADkhAA==.Sleepybeard:BAAANQAECgQIBwAAAA==.Slubadub:BAAANQAFFAEJAQAAAA==.',
Sm='Smiteslay:BAAANQAECgUJCgABNQAECgkJJAAIADkhAA==.',
Sn='Snivels:BAAANQAECgUJCQAAAA==.',
So='So:BAAANQAECgQIBQAAAA==.Soil:BAAANQAECgcJEwAAAA==.Somna:BAAANQAECgUJCwAAAA==.',
Sp='Sparrkle:BAABNQAECoEWAAIOAAgKBwUIIABMAQAOAAgKBwUIIABMAQAAAA==.Spinecrawler:BAABNQAECoEUAAINAAgK+BYnOwAxAgANAAgK+BYnOwAxAgAAAA==.Spyro:BAAANQADCggJJAAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQAECgIJAgACAAAAAA==.Staryknight:BAAANQAECgIIAgAAAA==.Steelrat:BAAANQADCgEIAQAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stickshamm:BAAANQADCggICAAAAA==.Stiick:BAAANQAECgYIEAAAAA==.Stonecracker:BAAANQADCgEIAQAAAA==.Stìmpak:BAAANQADCgYIDwABNQAECgIIAgACAAAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.Sudsy:BAAANQADCgQJBAABNQAECgQJBgACAAAAAA==.Supadupaman:BAAANQABCgYJBwAAAA==.Supaman:BAAANQABCgIIAgAAAA==.',
Sw='Sweetbippy:BAAANQADCggJGwAAAA==.Swifthealss:BAAANQAECgQIBwAAAA==.Swirls:BAAANQADCggICQAAAA==.',
Sy='Sylunae:BAAANQADCgcIEgABNQAECgUIBwACAAAAAA==.Syluné:BAAANQAECgUIBwAAAA==.',
Ta='Tacoshaman:BAAANQADCgIJAgABNQADCgYIDQACAAAAAA==.Tacozpriest:BAAANQADCgYIDQAAAA==.Taelyx:BAAANQAECgUJDQAAAA==.Tambot:BAAANQAECgYICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgQIBgAAAA==.Tazmina:BAABNQAECoEhAAIGAAYKEh9sJADwAQAGAAYKEh9sJADwAQAAAA==.',
Te='Teddykgb:BAAANQADCgQIBAAAAA==.Tessa:BAAANQAECgYIEAAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAAANQAECgcJDQAAAA==.Thalooze:BAAANQADCgEIAQABNQAECgIJAgACAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinyjapeto:BAAANQAECgQIBQAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAAANQAECgYIEAAAAA==.Tortapounder:BAAANQAECgQJCQAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgQIBgAAAA==.',
Tu='Turin:BAABNQAECoEWAAIDAAgKlwigEgBjAQADAAgKlwigEgBjAQAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twiggysmalls:BAAANQADCgUIBAAAAA==.Twilghtdawn:BAAANQADCgUIBQAAAA==.Twotone:BAAANQADCgYICgAAAA==.',
Ty='Tybo:BAAANQAECgUICAAAAA==.Tycho:BAAANQADCgUIBwAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.',
Un='Uncás:BAAANQAECgQICwAAAA==.Undyinggnome:BAAANQADCggJEgAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Va='Vaelock:BAAANQAECgUJBwAAAA==.Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQADCggIFgAAAA==.Valoryan:BAAANQAECgYIEAAAAA==.Vasoline:BAAANQAECgIJAQABNQAECgYIDQACAAAAAA==.Vaxtur:BAAANQAECggJCAAAAA==.',
Ve='Vegà:BAAANQAECgQJDQAAAA==.Vendettis:BAAANQAECgEIAQAAAA==.Vextaerin:BAAANQAECgUIBwAAAA==.Vextarin:BAAANQADCgYJBgABNQAECgUIBwACAAAAAA==.Veylyn:BAAANQAECgUJCwAAAA==.Veztaroth:BAAANQAECgUICwAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQADCgEIAQAAAA==.Voidyo:BAABNQAECoEbAAMhAAgKAiNdCQAdAwAhAAgKAiNdCQAdAwAGAAIKMx8nUgCIAAAAAA==.',
Wh='Whiskeyjak:BAAANQAECgYICgAAAA==.',
Wi='Willowbark:BAAANQADCgUICAAAAA==.Willowest:BAABNQAECoEdAAIdAAgKih9GFwDvAgAdAAgKih9GFwDvAgAAAA==.Wizbizzler:BAAANQAECgYJDgAAAA==.',
Wr='Wrathstorm:BAABNQAECoEWAAIeAAgKbxhGCgBxAgAeAAgKbxhGCgBxAgAAAA==.',
Xa='Xalatoes:BAAANQABCgYICAAAAA==.Xanatose:BAAANQAECgUIBgABNQAECggICwACAAAAAA==.Xanier:BAAANQADCgUIDQAAAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAAANQAECgUJCgAAAA==.Xithia:BAEANQAECgIIAgAAAA==.',
Xx='Xxcor:BAAANQADCggIDQAAAA==.',
Xy='Xyndylyne:BAAANQADCgYIBgAAAA==.',
Ya='Yanella:BAABNQAECoEXAAIEAAgKxhdrLwA6AgAEAAgKxhdrLwA6AgAAAA==.',
Yi='Yisdk:BAAANQAECgUJBQAAAA==.Yisshaman:BAAANQAECgYJDgAAAA==.',
Yo='Yogibearz:BAAANQAECgEJAQABNQAECgQICQACAAAAAA==.',
Za='Zanax:BAAANQAECgIIAgAAAA==.Zandarbribbs:BAAANQAECgEJAQAAAA==.Zarrah:BAAANQABCgMJBQAAAA==.',
Ze='Zennya:BAAANQAECgUICAAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.Zenthora:BAAANQADCgIIAgAAAA==.',
Zo='Zoldyck:BAAANQADCggIBwAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.Zyrx:BAAANQADCggIDwAAAA==.',
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
