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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Shaman-Restoration','Druid-Guardian','Mage-Arcane','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Retribution','Warrior-Arms','Evoker-Preservation','Priest-Discipline','Monk-Windwalker','Priest-Shadow','Druid-Feral','Monk-Brewmaster','Mage-Frost','Evoker-Devastation','Warlock-Affliction','Warrior-Fury','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Blood','DeathKnight-Frost','Shaman-Enhancement','Rogue-Subtlety','Paladin-Holy','Paladin-Protection','Druid-Balance','Warrior-Protection','Evoker-Augmentation','DemonHunter-Vengeance',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAABNQAECoEdAAMBAAgKZCOiAQBBAwABAAgKZCOiAQBBAwACAAEKlhJFcQBEAAAAAA==.',
Ad='Adorian:BAAANQAECgIIBQAAAA==.Adros:BAAANQAECgEIAQAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAQICQADABAQAA==.Adrrelle:BAACNQAFFIEJAAMDAAQKEBA0FQDkAAADAAMKRBI0FQDkAAACAAIKegbuGgB7AAA1AAQKgSMAAwIACQrMGk4oAOcBAAIACArWFk4oAOcBAAMABAq0HeXDAEYBAAAA.',
Ae='Aelfwine:BAAANQAECgUIDgAAAA==.',
Ai='Ailaith:BAABNQAECoEXAAMDAAcKRR9gQACFAgADAAcKRR9gQACFAgACAAEK6AYygwAsAAAAAA==.',
Ak='Akariliselle:BAABNQAECoEqAAMEAAcKYyEUCgBNAgAEAAcKGRwUCgBNAgAFAAUKmSCzdQDXAQAAAA==.',
Al='Alakn:BAAANQAECgEIAgABNQAECgUIBQAGAAAAAA==.Alan:BAAANQAECgUIBQAAAA==.Albatross:BAAANQADCgQIBAAAAA==.Alcun:BAAANQADCgYIBwABNQAECgUIBQAGAAAAAA==.Alein:BAAANQADCgEIAQABNQAECgUIBQAGAAAAAA==.Alishia:BAAANQAECgEIAQAAAA==.Alluriel:BAAANQAECgQIBAABNQAECgUIBgAGAAAAAA==.Alydrostage:BAAANQAECgYIEAAAAA==.Alystriaz:BAAANQAECgQICgAAAA==.Alzheimerz:BAABNQAECoEhAAMHAAgKGiCeDgDuAgAHAAgKGiCeDgDuAgAIAAIKZBdFFQB8AAAAAA==.',
Am='Amaelalin:BAABNQAECoEXAAIJAAcKaAmifgBjAQAJAAcKaAmifgBjAQAAAA==.Amatoria:BAAANQAECgQIBwAAAA==.',
An='Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAGAAAAAA==.Andaya:BAABNQAECoEcAAIKAAgKsht9MwBrAgAKAAgKsht9MwBrAgAAAA==.Andemeli:BAAANQAECgUICwAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgIIBAAAAA==.',
Ar='Arandis:BAAANQAECgUIDQAAAA==.Arcianna:BAABNQAECoEXAAILAAgKYR7ZCAC2AgALAAgKYR7ZCAC2AgAAAA==.Arctica:BAAANQAECgUIDgAAAA==.Arjurn:BAABNQAECoEdAAIMAAgKGBoScQCGAgAMAAgKGBoScQCGAgAAAA==.Arlyndra:BAAANQADCgQIBAAAAA==.Armpitbutter:BAABNQAECoEfAAINAAgK/CL8BQAhAwANAAgK/CL8BQAhAwAAAA==.Artymiss:BAAANQAECgUIDgAAAA==.',
As='Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAABNQAECoEUAAIDAAYK2Rj2fwDeAQADAAYK2Rj2fwDeAQAAAA==.',
Ay='Ayorana:BAAANQADCggIEAAAAA==.',
Az='Azshura:BAAANQADCgYICQAAAA==.Azzinôth:BAABNQAECoEqAAMOAAkKXBFwLQALAgAOAAkKPw9wLQALAgAPAAcK3Q89MQCTAQAAAA==.',
Ba='Baldr:BAABNQAECoEVAAIQAAcKFAsDvQBqAQAQAAcKFAsDvQBqAQAAAA==.Balgar:BAAANQAECgYICgAAAA==.Bammz:BAABNQAECoEiAAIRAAgKox9fOQDIAgARAAgKox9fOQDIAgAAAA==.Bastia:BAAANQADCgYIEgAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAGAAAAAA==.Benbeckman:BAAANQAECgcIDwAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAAANQAECgYIDgAAAA==.Bloodytusks:BAAANQAECgEIAQAAAA==.',
Bo='Borrkbuster:BAAANQAECgQIBwAAAA==.',
Br='Brenri:BAAANQAECgMJBgAAAA==.Brewtality:BAAANQAECgQIBQABNQAECgkJKQASAEkbAA==.Brudanature:BAAANQADCgUIBQABNQAECgQIDAAGAAAAAA==.Brughe:BAAANQAECgUICwAAAA==.Brywynn:BAAANQADCggJDgABNQAECgQICAAGAAAAAA==.',
Bu='Bubbleoseven:BAABNQAECoEUAAMJAAcKVxtKRAA1AgAJAAcKVxtKRAA1AgATAAEKjRAAJAA5AAABNQAECgkJKQASAEkbAA==.Burnbabyburn:BAAANQAECggICAAAAA==.Burntbum:BAAANQADCggICAAAAA==.Buttacutta:BAAANQADCggIHgAAAA==.',
Ca='Cahoots:BAABNQAECoEiAAIUAAkKOSDuCwAAAwAUAAkKOSDuCwAAAwAAAA==.Caneste:BAACNQAFFIEIAAIVAAMKkhWqCwDxAAAVAAMKkhWqCwDxAAA1AAQKgSEAAhUACQpkIG0PAOQCABUACQpkIG0PAOQCAAAA.Capela:BAAANQABCgQIBAAAAA==.Catty:BAABNQAECoEbAAIWAAcKJRa9DgDsAQAWAAcKJRa9DgDsAQAAAA==.Cayleynne:BAABNQAECoEWAAIXAAgKpSDgBQDeAgAXAAgKpSDgBQDeAgAAAA==.',
Ce='Celestyl:BAAANQAECgEICAAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Cheapbeerz:BAABNQAECoEVAAMYAAcKPwa0GgD0AAAMAAcKkAIfKwEfAQAYAAYKuwa0GgD0AAAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQAECgMIBQAAAA==.Chromstrasza:BAABNQAECoEeAAIZAAkKqw3WEgADAgAZAAkKqw3WEgADAgAAAA==.',
Ci='Cindersmoke:BAAANQADCgMIAwAAAA==.Cinnia:BAABNQAECoEYAAMFAAYKZxMGlACEAQAFAAYKZxMGlACEAQAaAAEKVAnRLAAyAAAAAA==.',
Co='Comitus:BAABNQAECoEWAAIRAAcKLwUZxgA4AQARAAcKLwUZxgA4AQAAAA==.Conj:BAAANQAECgEIAQAAAA==.Conjarr:BAABNQAECoEhAAIJAAgK2BsNMQCDAgAJAAgK2BsNMQCDAgAAAA==.Cooters:BAAANQADCgQJBAABNQAECggIFgAbAMgaAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougarsixsix:BAAANQAECgIIBgAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECoEgAAIcAAgKFQwTWACJAQAcAAgKFQwTWACJAQAAAA==.Crypticcurse:BAAANQADCgcIIgAAAA==.',
Cy='Cynnai:BAABNQAECoEYAAIRAAcK8htFfwD6AQARAAcK8htFfwD6AQAAAA==.',
['Cå']='Cåstiel:BAAANQAECgEIAwAAAA==.',
Da='Daerthor:BAAANQADCgYJCQABNQAECgQIBwAGAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAABNQAECoEXAAMEAAcKjwwMRgCjAAAFAAQKKg5y2ADsAAAEAAMKawoMRgCjAAAAAA==.Danashal:BAABNQAECoEWAAISAAcKiQH9NgC/AAASAAcKiQH9NgC/AAAAAA==.Dangerranger:BAAANQAECgIIAgAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.Darrth:BAAANQAECgUIEwAAAA==.Darthbane:BAAANQAECgQICAAAAA==.Darthjareth:BAAANQADCgUIBQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAGAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Deathsyn:BAAANQAECgEIAQAAAA==.Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAAANQAECgYIEwAAAA==.Demontator:BAAANQADCggICAAAAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAABNQAECoEaAAIdAAgKtRSPTQAUAgAdAAgKtRSPTQAUAgAAAA==.Desmádre:BAABNQAECoEVAAMcAAcKvRz0OwALAgAcAAcK1Bj0OwALAgAeAAYKzhsERADMAQAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diabetto:BAAANQABCgYICQAAAA==.Diend:BAABNQAECoEZAAMKAAcK6SDVKwCPAgAKAAcK6SDVKwCPAgAdAAEKbQz1HQEuAAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.Distiffany:BAAANQAECgEIAQABNQAECgIIAwAGAAAAAA==.',
Dj='Djthelock:BAAANQAECgQICAAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYIBgABNQAECgQIBgAGAAAAAA==.',
Dr='Dravenpryde:BAAANQAECgcIEwABNQAECggIIgALAFgeAA==.Drbrad:BAAANQAECgQIBgAAAA==.Dreadfists:BAABNQAECoEWAAIfAAcK3RHsOgCkAQAfAAcK3RHsOgCkAQAAAA==.Druen:BAABNQAECoEXAAIWAAgK4xuWCACXAgAWAAgK4xuWCACXAgAAAA==.Drunkenpo:BAABNQAECoEZAAIXAAcKjSFZBwCpAgAXAAcKjSFZBwCpAgAAAA==.Drunkxdemon:BAAANQAECgUICQAAAA==.Drunkxmonk:BAAANQAFFAEIAQAAAA==.Drykin:BAAANQADCgYIBgAAAA==.Drïzl:BAEBNQAECoEVAAIdAAgKjhgdPQBYAgAdAAgKjhgdPQBYAgABNQAECgkJIQAHAOcZAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQAECgIIBgAAAA==.Dweñde:BAABNQAECoEZAAIFAAcKsgyHjwCQAQAFAAcKsgyHjwCQAQAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECgEIAwAAAA==.',
Ed='Eddrick:BAAANQAECgYIDgAAAA==.Edrid:BAAANQAECgYICwABNQAFFAQIDQASAAYeAA==.',
El='Elîsha:BAAANQADCgQIBAAAAA==.',
En='Engo:BAABNQAECoEjAAITAAgKWCHoAQAFAwATAAgKWCHoAQAFAwAAAA==.',
Er='Eradrá:BAAANQAECgIIBQAAAA==.Eragon:BAAANQAECgYICQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAAANQAECggIEAAAAA==.',
Ev='Evandra:BAAANQAECgYICQAAAA==.Evanorah:BAAANQAECgQIDAAAAA==.',
Fa='Faedeyeda:BAAANQAECgQIBgAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQADCgUIBQABNQAECgcIFQAgADwXAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMICQAGAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAgAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAgABNQAECgUICQAGAAAAAA==.',
Fr='Frojio:BAABNQAECoEXAAIfAAgKNgyCPACaAQAfAAgKNgyCPACaAQAAAA==.Frosten:BAAANQADCggIKwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIBAAAAA==.Gaff:BAABNQAECoEUAAIRAAYKjBh9mQCzAQARAAYKjBh9mQCzAQAAAA==.Gatekeeper:BAAANQADCgUIBQAAAA==.',
Ge='Georgiana:BAAANQAECgEIAwAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYICAAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAMICAAVAJIVAA==.',
Ha='Hadin:BAABNQAECoEUAAIMAAcKhx4ahABdAgAMAAcKhx4ahABdAgAAAA==.Halalnt:BAAANQAECgIIAwABNQAECgQICQAGAAAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGQAYAJUaAA==.Hamster:BAAANQADCgYIBgABNQAECgYIGAAZAEUZAA==.Hanu:BAAANQABCggICgAAAA==.Haozhao:BAABNQAECoEZAAILAAcKORa1FgC8AQALAAcKORa1FgC8AQAAAA==.Hazenpryde:BAABNQAECoEiAAILAAgKWB4ZCQCvAgALAAgKWB4ZCQCvAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIFQABNQAECgQIDAAGAAAAAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAABNQAECoEcAAIDAAgK4BJyXAA2AgADAAgK4BJyXAA2AgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.Howlears:BAAANQADCgIIAgAAAA==.',
Hu='Hulud:BAAANQAECgYIEgAAAA==.',
Hy='Hysgar:BAAANQAECgUICwABNQAECgYIDAAGAAAAAA==.',
Ie='Iechu:BAAANQAECgEJAQAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAABNQAECoEbAAMVAAgKvxrjJwDEAQAVAAYK8RfjJwDEAQAJAAUKghaYhABPAQAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAABNQAECoEdAAIRAAgKzxhcUgB3AgARAAgKzxhcUgB3AgAAAA==.Inic:BAAANQABCgQJBQAAAA==.Inix:BAAANQABCgIIAgAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgIIAgAAAA==.',
Ja='Jackfruit:BAAANQAECgUIEQAAAA==.Jaod:BAAANQADCgYIFgAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIAwAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQAECgEIAgAAAA==.Kalarae:BAAANQAECgUICwAAAA==.Kaljeer:BAABNQAECoEXAAIhAAYKWhc3HwDBAQAhAAYKWhc3HwDBAQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kaltharion:BAAANQAECgEIAQAAAA==.Kaluren:BAACNQAFFIENAAIiAAQKvB9ADABxAQAiAAQKvB9ADABxAQA1AAQKgSgAAyIACQqtJrMAAOkDACIACQqtJrMAAOkDABAABQoCHa+9AGgBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAAANQAECgUIEAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAABNQAECoEYAAIXAAcKHiOqBgDAAgAXAAcKHiOqBgDAAgAAAA==.Kapp:BAAANQAECgIIBAAAAA==.Karabar:BAABNQAECoEdAAIjAAgKix00DgCUAgAjAAgKix00DgCUAgAAAA==.Karnnaged:BAAANQAECgMIBwABNQAECgQIBQAGAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAGAAAAAA==.Karnnagexxl:BAAANQAECgMIBQABNQAECgQIBQAGAAAAAA==.Kasarra:BAAANQAECgIIBAAAAA==.Kayiku:BAAANQADCggIFAAAAA==.Kazagol:BAABNQAECoEdAAIPAAgKORbOHQBGAgAPAAgKORbOHQBGAgAAAA==.',
Kh='Khamaracy:BAAANQAECgIIBwAAAA==.',
Ko='Kojote:BAAANQADCgMIBgAAAA==.Kovalenko:BAAANQAECgYIDgAAAA==.',
Kr='Kryptus:BAABNQAECoEXAAIMAAYK5BdC1wCyAQAMAAYK5BdC1wCyAQAAAA==.',
Ku='Kurick:BAAANQAECgYIDAAAAA==.Kurshak:BAABNQAECoEaAAIkAAcKOBTrQADKAQAkAAcKOBTrQADKAQAAAA==.',
Ky='Kyngizzard:BAAANQAECgMICAABNQAECgQICQAGAAAAAA==.',
La='Latte:BAAANQAECgQIBwAAAA==.',
Le='Lenity:BAABNQAECoEVAAIhAAYKfAp2KQBgAQAhAAYKfAp2KQBgAQAAAA==.Lepidolite:BAAANQAECgEIAQAAAA==.',
Lo='Loan:BAAANQADCggIFgABNQAECgYIGAAZAEUZAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgMIBwAAAA==.',
Lu='Lucoryphus:BAAANQAECgQICQAAAA==.Lukeduke:BAACNQAFFIENAAIlAAQK9R1JAgBBAQAlAAQK9R1JAgBBAQA1AAQKgSQAAiUACQq8I+0CAGIDACUACQq8I+0CAGIDAAAA.Luketheduke:BAAANQAECgMIBAABNQAFFAQIDQAlAPUdAA==.Lunä:BAAANQAECgYIEwAAAA==.',
Ly='Lydia:BAABNQAECoEbAAMMAAcKlBqo2ACwAQAMAAYK0Rio2ACwAQAYAAIKPRs5JgCdAAAAAA==.Lyleath:BAAANQADCgQIBAABNQAECgUIBgAGAAAAAA==.',
['Lú']='Lúthien:BAAANQAECgEIAQAAAA==.',
Ma='Malcontent:BAAANQAECgMIBAABNQAECgQIBgAGAAAAAA==.Malifel:BAAANQAECgQIBgAAAA==.Mallord:BAAANQAECgQIBAABNQAECgQIBgAGAAAAAA==.Malstrom:BAAANQAECgIIBgABNQAECgQIBgAGAAAAAA==.Mandarin:BAAANQAECgUICAAAAA==.Mararose:BAAANQABCgIIBAAAAA==.Marashades:BAAANQAECgYICQAAAA==.Marsali:BAAANQAECgEIAQAAAA==.',
Me='Melabrin:BAAANQAECgYIDwAAAA==.Mercia:BAABNQAECoEVAAIjAAcKox5jFAA7AgAjAAcKox5jFAA7AgAAAA==.Mercý:BAAANQADCggIGAAAAA==.Merekoma:BAAANQAECgUIDgAAAA==.',
Mi='Mieena:BAAANQABCgQIBAAAAA==.Milhouse:BAAANQAECgEIBgAAAA==.Mingonashoba:BAAANQAECgEIAwAAAA==.Miragosa:BAAANQADCgQIBAAAAA==.Misschris:BAAANQAECgYICgAAAA==.Mistaricky:BAAANQAECgYICQAAAA==.',
Mo='Moadeed:BAAANQAECgUIDgAAAA==.Morphmious:BAABNQAECoEiAAIWAAgK5xbiCgBPAgAWAAgK5xbiCgBPAgAAAA==.Mortesque:BAAANQAECgQICwAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgIIBAAAAA==.',
My='Myroku:BAAANQABCgMIAwABNQAECgQIBgAGAAAAAA==.Myrrh:BAABNQAECoEgAAISAAgKugZ7JQBwAQASAAgKugZ7JQBwAQAAAA==.Mysklef:BAAANQAECgEIAQABNQAECgYIDAAGAAAAAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCQAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQAECgUIBgAGAAAAAA==.Nausican:BAAANQADCgUIBgAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECgYIDwAGAAAAAA==.Necrosector:BAABNQAECoEZAAIQAAcK8BoTaQA0AgAQAAcK8BoTaQA0AgAAAA==.Nelandra:BAAANQAECgIIBwAAAA==.Neongrasp:BAAANQAECgYICwAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.Ninjadk:BAEANQAECgIIAgABNQAECgkJIQAHAOcZAA==.',
No='Nomahuata:BAABNQAECoEjAAIdAAgKmBAeVwDxAQAdAAgKmBAeVwDxAQAAAA==.',
Nu='Nufrus:BAAANQAECgUICQAAAA==.Nurgle:BAAANQADCgUICQAAAA==.',
Ny='Nyeli:BAAANQAECgQICAAAAA==.Nyxi:BAAANQAECgIIBQAAAA==.',
['Né']='Néo:BAAANQAECgIIAgAAAA==.',
Om='Ommeta:BAAANQAECgMIAwABNQAECgkJJwAWAMsYAA==.',
On='Onefiftyone:BAABNQAECoEVAAQgAAcKPBdwEgAgAgAgAAcKGxdwEgAgAgAKAAMKChoAtADYAAAdAAEKEQ6NGwEvAAAAAA==.',
Pa='Palochka:BAAANQAECgQIBgAAAA==.Palpetine:BAAANQAECgEIAQAAAA==.Paltator:BAABNQAECoEVAAIQAAYKuQrZ2AAvAQAQAAYKuQrZ2AAvAQAAAA==.Pandazuken:BAABNQAECoEcAAIdAAgKjhbYRgAvAgAdAAgKjhbYRgAvAgAAAA==.Paradots:BAABNQAECoEpAAISAAkKSRu4DADIAgASAAkKSRu4DADIAgAAAA==.Paranitis:BAAANQAECgEIAQAAAA==.Paraparaboom:BAABNQAECoEWAAIbAAgKyBorBgCFAgAbAAgKyBorBgCFAgAAAA==.',
Ph='Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQAECgEIAQAGAAAAAA==.',
Pi='Pixpax:BAAANQAECgYIDQAAAA==.Pixyofdeath:BAAANQADCggIAwABNQAECgIIBwAGAAAAAA==.Pixystix:BAAANQAECgIIBwAAAA==.',
Po='Pomortem:BAAANQAECgQIDAAAAA==.Potsomancy:BAACNQAFFIEMAAIMAAYKihcdCgAMAgAMAAYKihcdCgAMAgA1AAQKgR8AAgwACQo0JOw2AA4DAAwACQo0JOw2AA4DAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ps='Psyberx:BAAANQAECggIAwAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQAECgQIBAAGAAAAAA==.Raivel:BAAANQAECgIIBwABNQAECgQICAAGAAAAAA==.Rambogg:BAAANQADCgMIAwABNQAFFAUICQAMAGEKAA==.Raneyth:BAAANQAECgUICwAAAA==.Ranoku:BAAANQADCgYIBgAAAA==.Ravagèr:BAAANQADCggICAABNQAECgkJKgAOAFwRAA==.Ravusternath:BAAANQADCgcIDQAAAA==.',
Re='Redwinetoast:BAAANQAECgQIBwAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAABNQAECoEYAAQZAAYKRRnvHABjAQAZAAUKpxbvHABjAQASAAMKOg+UOgClAAAmAAEK1AyUIAAxAAAAAA==.Reposess:BAAANQABCggIEgAAAA==.Reshyk:BAAANQAECgQIBQAAAA==.',
Rh='Rhobes:BAAANQADCgcIFAAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAAANQAECgYICgAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAGAAAAAA==.Rowene:BAAANQADCgYIFgAAAA==.',
Ru='Rumor:BAAANQAECgQIDAAAAA==.Rurry:BAACNQAFFIENAAISAAQKBh4DCgBjAQASAAQKBh4DCgBjAQA1AAQKgSMAAxIACQqQIyYDAH8DABIACQqQIyYDAH8DABkAAQohJbkwAGoAAAAA.',
Ry='Ryuuki:BAABNQAECoEdAAMcAAgKoCHNGgDQAgAcAAgKoCHNGgDQAgAeAAIKLg0HqwBVAAAAAA==.',
['Rï']='Rïzzler:BAEBNQAECoEhAAMHAAkK5xmJJwAiAgAHAAcKuhqJJwAiAgAhAAYKYxSkJQCEAQAAAA==.',
Sa='Safetysham:BAAANQAECgEIAgAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYJBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAGAAAAAA==.Salmoo:BAAANQAECgUICQAAAA==.Saltytator:BAAANQAECgMIBQAAAA==.Savonah:BAAANQADCggIIAAAAA==.',
Sc='Scaledaddy:BAAANQAECgYIEwAAAA==.Scallion:BAAANQADCggICwABNQAECggIHQABAGQjAA==.Scaryl:BAAANQAECgUICgAAAA==.Schneè:BAABNQAECoEoAAIlAAgKABOFFACxAQAlAAgKABOFFACxAQAAAA==.Scoom:BAACNQAFFIENAAIMAAQK+hsLHgBWAQAMAAQK+hsLHgBWAQA1AAQKgSwAAgwACQruJGMTAH8DAAwACQruJGMTAH8DAAAA.Scourgespawn:BAACNQAFFIEKAAMfAAQKiBSGBwAwAQAfAAQKiBSGBwAwAQAcAAEKYQd2HwA9AAA1AAQKgScAAx8ACQo8I6sMABkDAB8ACQo8I6sMABkDABwABAqODvOLAM4AAAAA.',
Se='Seikyo:BAABNQAECoEdAAIeAAgK4gyLUgCIAQAeAAgK4gyLUgCIAQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgQICQAGAAAAAA==.Selenë:BAAANQAECgQIBgAAAA==.Sento:BAAANQAECgEIAQAAAA==.Serok:BAAANQAECgcIDwAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgMJBQAAAA==.Shailora:BAAANQADCgQIBAABNQADCgQIBAAGAAAAAA==.Shalis:BAAANQAECgYIBwAAAA==.Sharivee:BAAANQAECgQICwAAAA==.Shazamir:BAAANQAECgUIDwAAAA==.Shibui:BAABNQAECoEZAAIOAAcKiA3hPwCHAQAOAAcKiA3hPwCHAQAAAA==.Shifthead:BAABNQAECoEnAAMWAAkKyxgOCwBLAgAWAAgK4BkOCwBLAgAkAAkKzxBhNAAdAgAAAA==.Shockazilla:BAABNQAECoEWAAIiAAcKvB2cNgBuAgAiAAcKvB2cNgBuAgAAAA==.Shortspanky:BAAANQAECgQIBwAAAA==.',
Si='Silaveen:BAAANQAECgEIAwAAAA==.Silverhorn:BAAANQAECgUIEAAAAA==.',
Sk='Skoduh:BAAANQAECgQIDAAAAA==.',
Sl='Slack:BAAANQAECgMJCAABNQAECgYIGAAZAEUZAA==.Sluggo:BAACNQAFFIELAAIQAAQKTRKkDABFAQAQAAQKTRKkDABFAQA1AAQKgSMAAhAACQpsH8k/ALECABAACQpsH8k/ALECAAAA.',
Sm='Smokeü:BAAANQADCggICgAAAA==.',
So='Solinaara:BAAANQABCgQIBAAAAA==.Soraka:BAAANQAECgEIBAAAAA==.',
Sp='Spiralist:BAAANQAECgEIAQAAAA==.',
St='Stonedalways:BAAANQAECgIIBQAAAA==.Stonytoni:BAAANQAECgEIAwAAAA==.',
Su='Sunfuri:BAABNQAECoEUAAIbAAgK5gOkGADyAAAbAAgK5gOkGADyAAAAAA==.Sus:BAACNQAFFIEMAAIOAAQKvhXvCgA1AQAOAAQKvhXvCgA1AQA1AAQKgSQAAw4ACQr+ILYUANgCAA4ACQr+ILYUANgCACcABAoJCUEdALUAAAAA.Susanoo:BAAANQAECgYIBgAAAA==.',
Ta='Taalia:BAAANQAECgIIBwAAAA==.Talonas:BAAANQAECgIIBQAAAA==.Tarathor:BAAANQAECgIIBwAAAA==.Tatortott:BAAANQADCgMIAwAAAA==.',
Te='Teknofarious:BAAANQAECgUIEAAAAA==.',
Th='Thaumas:BAAANQAECgEIAQAAAA==.Thesafe:BAAANQAECgYICQAAAA==.Thevin:BAAANQAECgUIEgABNQAECgYIGAAZAEUZAA==.Thialia:BAABNQAECoEVAAIJAAYK5Q2wjAA1AQAJAAYK5Q2wjAA1AQABNQAECgcIFwADAEUfAA==.Thialiadin:BAAANQAECgQIBQABNQAECgcIFwADAEUfAA==.Thickems:BAAANQAECgYIEAAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.Thorgrumn:BAAANQADCgIIAgAAAA==.',
Ti='Tinkabella:BAABNQAECoEdAAITAAgKdBrxAwCHAgATAAgKdBrxAwCHAgAAAA==.Tizl:BAEANQAECgIIAgABNQAECgkJIQAHAOcZAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgQIBwAAAA==.Trema:BAABNQAECoEeAAMjAAcKNBcQIAC5AQAjAAYKGRoQIAC5AQAQAAcKnQ0FtQB7AQAAAA==.Trialei:BAAANQAECgEIAQAAAA==.Trix:BAAANQAECgEIAQAAAA==.',
Ts='Tserendelgor:BAAANQAECgUICAABNQAECggIIQAHABogAA==.',
Tu='Tulsi:BAAANQAECgMICAAAAA==.',
Ty='Tyronos:BAAANQAECgYICQAAAA==.',
Va='Vaeltharion:BAAANQAECgQIBwAAAA==.Varedrae:BAAANQADCggIEAAAAA==.Vas:BAAANQADCgYIDwAAAA==.',
Ve='Verdandi:BAAANQAECgUIBgAAAA==.Vevicenth:BAAANQAECgUICwAAAA==.',
Vo='Voranth:BAAANQAECgYIDwAAAA==.',
Wa='Warenio:BAABNQAECoEYAAIlAAcKRRgREQDnAQAlAAcKRRgREQDnAQAAAA==.Warick:BAAANQADCgMIAwAAAA==.Warpsbulge:BAABNQAECoEZAAMYAAkKlRoYCQAVAgAYAAkKHxcYCQAVAgAMAAYKtx2VtQD1AQAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECgYICgAGAAAAAA==.',
Wh='Whakan:BAAANQADCggIIAABNQAECgQICQAGAAAAAA==.',
Wo='Wolfos:BAAANQAECgIIBwAAAA==.',
Wt='Wtfox:BAEBNQAECoEVAAIVAAcK6BBOKwCkAQAVAAcK6BBOKwCkAQAAAA==.',
Wy='Wysteri:BAAANQAECgUICQAAAA==.',
Xa='Xalatos:BAAANQAECggIDgAAAA==.Xalfein:BAAANQADCggIFAAAAA==.',
Xi='Xinu:BAAANQADCgIIAgABNQAECgcIGQADAH4XAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Ya='Yanakana:BAAANQAECgQIBAAAAA==.',
Za='Zakeko:BAAANQAECgIIBwAAAA==.Zanderpryde:BAAANQAECgIIAwABNQAECggIIgALAFgeAA==.Zariak:BAAANQAECgEIAwAAAA==.',
Ze='Zennite:BAAANQAECggICAAAAA==.Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAAANQAECgYICgAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAABNQAECoEZAAIDAAcKfhcdYgAnAgADAAcKfhcdYgAnAgAAAA==.',
Zo='Zota:BAAANQAECgYIBgAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECgYIDAAGAAAAAA==.Zulfionn:BAAANQAECgYICQAAAA==.Zurok:BAAANQADCgcIBwABNQAECgYIGAAZAEUZAA==.',
['Áy']='Áyrá:BAAANQAECgcICQAAAA==.',
['Øu']='Øuroboros:BAAANQAECgMICQAAAA==.',
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
