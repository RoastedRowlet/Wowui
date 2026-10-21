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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection','Evoker-Augmentation','Druid-Guardian','Druid-Restoration','Druid-Balance','Mage-Arcane','DemonHunter-Havoc','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Evoker-Devastation','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Mage-Frost','Warrior-Fury','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Preservation','Hunter-Marksmanship','Mage-Fire','Warlock-Affliction','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaralyn:BAAANQAECgMIBAAAAA==.',
Ab='Abmikaze:BAAANQAECggICAAAAA==.Absolon:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.Abysseon:BAABNQAECn8aAAMCAAoKZRk4MAAkAgACAAoKZRk4MAAkAgADAAMK2w2IqgB7AAAAAA==.',
Ac='Ace:BAABNQAECn8jAAMEAAkK6h82FQAwAQAEAAcK/x42FQAwAQAFAAMKNiK0bwDyAAABNQAECgEIAQABAAAAAA==.',
Ad='Adios:BAACNQAFFH8RAAIGAAYKDA9jBQDbAQAGAAYKDA9jBQDbAQA1AAQKfy4AAgYACgqgHAAKADkDAAYACgqgHAAKADkDAAAA.Adorean:BAABNQAECn8fAAIHAAoKMhCZoADgAQAHAAoKMhCZoADgAQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgQIDQAAAA==.Agrohn:BAABNQAECn8XAAMHAAcKQxSRuQCqAQAHAAcKQxSRuQCqAQAIAAEKrgKUNAEjAAAAAA==.',
Ai='Aimnskin:BAAANQADCggJEwAAAA==.',
Al='Alcore:BAABNQAECn8gAAQDAAoKARhQIACxAgADAAcK2yFQIACxAgAJAAYKaByeTADiAQACAAQKZAwWWQBXAAAAAA==.Aliine:BAABNQAECn8dAAIDAAgKYQ7OJgDaAAADAAgKYQ7OJgDaAAAAAA==.',
Am='Ameiisaa:BAABNQAECn8ZAAMKAAcKrQkP6QDFAAAKAAUK3wQP6QDFAAALAAQKSQMf6QCZAAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAACNQAFFH8KAAIKAAQKkBMkFQAmAQAKAAQKkBMkFQAmAQA1AAQKf0AAAgoACgoCHS8aACwDAAoACgoCHS8aACwDAAAA.',
An='Anxie:BAABNQAECn8eAAIMAAgKoAUPhgCgAAAMAAgKoAUPhgCgAAAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAcIEwANAEYZAA==.',
Ao='Aoifae:BAAANQAECgUIDAAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECn8ZAAQOAAkKnAk3gQCUAQAOAAgKGgo3gQCUAQAPAAcKewY1QAAtAQAQAAEKMAVqLwAmAAAAAA==.Apprentice:BAABNQAECn8cAAIRAAgKngJ8IgCFAAARAAgKngJ8IgCFAAAAAA==.',
Ar='Aramos:BAABNQAECn8kAAIIAAgKDxmNPQBuAgAIAAgKDxmNPQBuAgAAAA==.Aramôs:BAAANQAECgQIBwAAAA==.Arkhangel:BAABNQAECn8ZAAIHAAgKJBiNeAA7AgAHAAgKJBiNeAA7AgAAAA==.Arta:BAAANQAECgQICAAAAA==.Artavian:BAAANQABCgIIAwAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAABNQAECn8eAAIOAAcKlxEGTwDcAAAOAAcKlxEGTwDcAAAAAA==.Assiam:BAAANQADCgIIAgAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Ay='Ayame:BAAANQABCgMIBQAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECgoKNgADAP4XAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQAECgQIDgAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.Basicampfire:BAAANQAECgMIAwABNQAECggIHwASAM8IAA==.',
Be='Beaker:BAABNQAECn8kAAITAAoK+Q+CHgCrAQATAAoK+Q+CHgCrAQAAAA==.Beastmode:BAABNQAECn80AAMUAAgKThPyKQDPAQAUAAgKThPyKQDPAQAVAAgKPRWwDQBxAQAAAA==.Bedlem:BAAANQAECgYIDAAAAA==.Beko:BAABNQAECn8mAAIWAAoKURnsFgC2AQAWAAoKURnsFgC2AQAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBgAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgMIBwAAAA==.Billydan:BAABNQAECn8aAAIXAAkKqQ3mGwAWAQAXAAkKqQ3mGwAWAQAAAA==.',
Bl='Blackhide:BAAANQABCgUIBgAAAA==.Blackpanthxr:BAABNQAECn8yAAQLAAoKkRMwRwBFAgALAAoKkRMwRwBFAgAYAAcKghHWGQDHAQAKAAcKfAdXrgA2AQAAAA==.Blackvortex:BAAANQAECgQIBAAAAA==.Bloodgoat:BAAANQADCggICwAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECgkJHgAZAFkjAA==.Bloodyburst:BAABNQAECn8aAAMNAAgK2CKlBQCMAgANAAcKEyOlBQCMAgAFAAIKDBywggCpAAABNQAECgkJHgAZAFkjAA==.Bloodyfistz:BAABNQAECn8eAAMZAAkKWSNhDgD5AgAZAAkKRCNhDgD5AgAaAAIKMyOyIgDDAAAAAA==.Blue:BAABNQAECn8iAAIKAAkKQBs/KwDTAgAKAAkKQBs/KwDTAgAAAA==.Bluethreetwo:BAAANQAECgQICAAAAA==.',
Bo='Bookofzeref:BAAANQAECgcIBwAAAA==.Boost:BAAANQABCgIIBAAAAA==.',
Br='Brayend:BAAANQAECggIDwAAAA==.Brewguts:BAAANQAECgcIEQAAAA==.Brimscythe:BAABNQAECn8rAAIbAAkK3h1LCQDeAgAbAAkK3h1LCQDeAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggIDgAAAA==.Caliandis:BAABNQAECn8aAAIcAAcKEA+yDQDXAAAcAAcKEA+yDQDXAAAAAA==.Calvey:BAAANQAECgUICAAAAA==.Cambrai:BAAANQAECgcIDQAAAA==.Cannabelle:BAABNQAECn8jAAIMAAkK8CFBHgAeAwAMAAkK8CFBHgAeAwAAAA==.Carclias:BAACNQAFFH8HAAMdAAMKvwwqAwCXAAAdAAIKBwoqAwCXAAAeAAEKLhJ3GgBRAAA1AAQKfzsAAx0ACgpeGmwCAEIBAB4ACQpoEtYpAEsBAB0ACQpsGGwCAEIBAAAA.Carthrix:BAABNQAECn8XAAMfAAkKlAp3RQAWAQAfAAgKAgx3RQAWAQAcAAEKAgK6JgAkAAAAAA==.Catbarf:BAAANQAECgYIAQABNQAECgkJKgAYAO0dAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAAANQAECgQICwAAAA==.',
Ce='Celery:BAAANQAECgcICQABNQAFFAcIHAADAC4WAA==.Cellika:BAAANQAECgUIDgAAAA==.Cerdelz:BAAANQAECgQIBAAAAA==.',
Ch='Chanclatotem:BAAANQADCgIIAgAAAA==.Chaoscookies:BAABNQAECn83AAMdAAoKRxQeEwDaAQAdAAcKsxYeEwDaAQAeAAcKMA6sQgAHAQAAAA==.Chartkov:BAAANQAECgUICQAAAA==.Cheezee:BAABNQAFFH8TAAMWAAcKLhB9EADzAQAWAAYKzhN9EADzAQAgAAEKrwHVEQBLAAAAAA==.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQADCggIFgAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECgoKKAAWAO8NAA==.',
Ci='Cinderpetal:BAAANQAECgQICAAAAA==.',
Ck='Ckay:BAAANQAECgcIBwAAAA==.',
Cl='Clawsome:BAAANQADCggIEwAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAACNQAFFH8GAAMDAAIKSA/JIwBvAAACAAIK9wmUFwCEAAADAAIKSA/JIwBvAAA1AAQKfyIABAIACgq3Gi8hAIQCAAIACQrRGC8hAIQCAAkABwoFFf5gAIwBAAMABApXFTaIAN4AAAAA.Comlock:BAAANQADCgYIDAAAAA==.Complacent:BAABNQAECn8lAAITAAkKzQP9FgDMAAATAAkKzQP9FgDMAAAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgIIBAAAAA==.Coriander:BAABNQAECn8YAAISAAkKlBJQCAAUAgASAAkKlBJQCAAUAgAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAAANQAECgcIDQABNQAECgkJHQAWALsPAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAcIFwAZANQXAA==.',
Cy='Cynical:BAAANQAECgIIAwABNQAECgEIAQABAAAAAA==.Cyonicus:BAABNQAECn8fAAIeAAoKMRkRXABDAgAeAAoKMRkRXABDAgAAAA==.Cyska:BAABNQAECn82AAIDAAoK/heUJwCDAgADAAoK/heUJwCDAgAAAA==.',
['Cé']='Cécé:BAABNQAECn8kAAIHAAkKExghLQB4AQAHAAkKExghLQB4AQAAAA==.',
['Cë']='Cëcë:BAAANQAECgMIAwAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAABNQAECn8vAAIOAAoKRhA2JQBrAQAOAAoKRhA2JQBrAQAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagaurie:BAAANQAECgIIAgABNQAECgoKHAAUAAMZAA==.Dagerlaurn:BAABNQAECn8cAAMUAAoKAxlmOgBMAQAUAAQKxhtmOgBMAQAVAAoKFBt9EgBFAQAAAA==.Dagevas:BAAANQADCgYICAAAAA==.Dakeria:BAAANQADCgYIGgAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEAAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECn82AAIhAAoKrRb2AQDTAQAhAAoKrRb2AQDTAQABNQAFFAUIDQAHACUcAA==.Davriell:BAABNQAECn8VAAICAAoK4gcgDwCMAQACAAoK4gcgDwCMAQAAAA==.Dax:BAABNQAECn8XAAIMAAcK8AstOwBCAQAMAAcK8AstOwBCAQAAAA==.Daxing:BAAANQADCggIFAABNQAECgkJKAAOAJgeAA==.',
De='Deeppurple:BAAANQAECgUIDQAAAA==.Del:BAABNQAECn8nAAIiAAoKHyYjAgBuAwAiAAoKHyYjAgBuAwABNQAECgoKJwAjAFQYAA==.Demonic:BAAANQAECgMIBQABNQAECgEIAQABAAAAAA==.Demonshady:BAAANQABCggIFAAAAA==.Demoraliziñg:BAAANQADCggIDgABNQAECgkJIgAXACUaAA==.Demostache:BAACNQAFFH8GAAMeAAIK3RaJDACwAAAeAAIK3RaJDACwAAAdAAEKXApPIQBHAAA1AAQKfy0AAx4ACgrPIjUuAM0CAB4ACQpaIjUuAM0CAB0AAgrJFXVPAJEAAAE1AAUUAggGAAMASA8A.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECn8lAAIKAAoKTh9OJgDqAgAKAAoKTh9OJgDqAgAAAA==.',
Di='Diivision:BAAANQAECgEIAgABNQAECgoKJgAGAPYVAA==.',
Do='Dolomite:BAABNQAECn8XAAIWAAgKUgVrGQFhAQAWAAgKUgVrGQFhAQAAAA==.Dorow:BAABNQAECn8sAAMVAAoKghe8JQClAgAVAAkKBxi8JQClAgAUAAUKmQ/xIwC3AAABNQAECgkJIwAZAIIXAA==.Dotabolt:BAABNQAECn8VAAIeAAcKyw+4nACeAQAeAAcKyw+4nACeAQABNQAECggIEgABAAAAAA==.',
Dr='Dracthyris:BAABNQAECn8fAAIkAAkKAAzEBQB7AQAkAAkKAAzEBQB7AQAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Dreaa:BAAANQAECgEIAQAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECn8qAAIYAAkK7R18BwAGAwAYAAkK7R18BwAGAwAAAA==.',
Du='Dunsel:BAAANQAECgcIEgABNQAECgkJKwAbAN4dAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgQIBAAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECn8wAAMfAAkKWRKsDwDbAQAfAAkKWRKsDwDbAQAcAAIK/QnjPABRAAAAAA==.',
['Dã']='Dãnny:BAAANQADCggIDQABNQAECgkJMAAfAFkSAA==.',
Ea='Earendil:BAAANQAECggICAAAAA==.',
Eb='Ebonshade:BAAANQAECgEIAQAAAA==.',
Ed='Edena:BAAANQAECgEIAQAAAA==.Edginglord:BAAANQAECgcIDAAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQAAAA==.Eloras:BAAANQAECgYIBwAAAA==.Elunbi:BAABNQAECn8wAAMOAAoKpBzZHgD1AgAOAAoKEhzZHgD1AgAQAAYKkhSZDQBZAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQAECgUIBAAAAA==.',
Ep='Epsilòn:BAEBNQAECn8WAAMeAAkKtwrczwAqAQAeAAYKrxLczwAqAQAdAAgKFwAMiAAdAAAAAA==.',
Er='Ernest:BAAANQAECgUIEAAAAA==.Errani:BAABNQAECn8bAAMgAAcKqxAdEQCVAQAgAAcKqxAdEQCVAQAWAAIKHQQE+gAtAAAAAA==.',
Es='Esheman:BAAANQADCgQICAAAAA==.Esper:BAAANQAECgcIDQAAAA==.Esterlia:BAAANQAECgMIAwABNQAECgkJKAAOAJgeAA==.',
Et='Eternal:BAAANQAECgEIAQAAAA==.',
Eu='Eureki:BAABNQAECn8VAAIXAAcKYgkGIgDwAAAXAAcKYgkGIgDwAAAAAA==.',
Ev='Evilkarma:BAAANQAECgYIDwAAAA==.Evocatis:BAACNQAFFH8LAAIHAAUKFx3hDwBOAQAHAAUKFx3hDwBOAQA1AAQKfywABAcACgpQIXMlAC8DAAcACgpQIXMlAC8DAAgABApTDRvNAOEAABEAAQpgFw4wAEkAAAAA.',
Ey='Eyekonicklok:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Eyesdeadeyed:BAABNQAECn8qAAMlAAoKsBSCJgAYAgAlAAkKTxWCJgAYAgAMAAEKWxANuwBMAAAAAA==.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAABNQAECn8rAAMHAAoKkBrSRgDAAgAHAAkK8RzSRgDAAgAIAAYKExwLfwCcAQAAAA==.Falco:BAAANQAECggIAQABNQAECggIBgABAAAAAA==.Faon:BAAANQAECgMIBAAAAA==.Farrea:BAAANQAECgEIAgABNQAECgQICAABAAAAAA==.Fatlock:BAAANQAECgQICQABNQAECgkJLgAZACAcAA==.Fayvia:BAAANQABCggIDQAAAA==.',
Fe='Feebz:BAAANQADCgYIBwAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECgMIBAABNQAECgEIAQABAAAAAA==.Firebirdz:BAACNQAFFH8KAAIUAAUKRBPWCQBBAQAUAAUKRBPWCQBBAQA1AAQKfx8AAhQACgr4HSYTALQCABQACgr4HSYTALQCAAAA.Firebirdzx:BAAANQAECgIIAgABNQAFFAUICgAUAEQTAA==.',
Fl='Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCggIEAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAABNQAECn8uAAIGAAkKWhBhDgBBAQAGAAkKWhBhDgBBAQAAAA==.Freshhéals:BAAANQAECgEIAQABNQAFFAEIAgABAAAAAA==.Friargark:BAAANQADCgYIEQAAAA==.Frizby:BAAANQAECgQIBgAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQAECgUIDQAAAA==.',
Fy='Fyrelord:BAAANQAECgMIAgAAAA==.Fyuna:BAABNQAECn8kAAILAAoKbxo1LQCtAgALAAoKbxo1LQCtAgAAAA==.',
Ga='Gark:BAAANQAECgQIDAAAAA==.Garkk:BAAANQADCgQJBAAAAA==.Garrumn:BAAANQADCgcIBwABNQAFFAIIBgADAEgPAA==.Gazzi:BAABNQAECn8WAAITAAkKcg6rHAC9AQATAAkKcg6rHAC9AQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgcIFwAOAJweAA==.',
Gi='Giuseppee:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Gióvanna:BAAANQAECgQICAAAAA==.',
Gl='Glodskegg:BAABNQAECn8WAAIdAAkKlBG9CQBcAgAdAAkKlBG9CQBcAgAAAA==.',
Go='Goldensea:BAAANQAECgQICwAAAA==.Gotenk:BAAANQAECgcIEAAAAA==.Goyim:BAAANQAECgQIBQAAAA==.',
Gr='Gr:BAAANQADCgQIDQAAAA==.Grissoul:BAAANQAECgYIBgAAAA==.Grody:BAABNQAECn8UAAIeAAYKNQrm0wAiAQAeAAYKNQrm0wAiAQAAAA==.Gryms:BAAANQAECgYIBQAAAA==.',
Gu='Guroo:BAABNQAECn8jAAIMAAkKXglSnQDMAQAMAAkKXglSnQDMAQAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
['Gí']='Gígí:BAAANQAECgIIBAAAAA==.Gíl:BAAANQAECgQIBAAAAA==.',
Ha='Hagarn:BAABNQAECn8pAAIHAAoKOxMtfAAyAgAHAAoKOxMtfAAyAgAAAA==.Halastrin:BAAANQAECgEIAQAAAA==.Halimah:BAAANQAECgQICQAAAA==.Halois:BAAANQADCgYIBgABNQAECgcIHAADABkSAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggIDgAAAA==.Harvestt:BAAANQADCgQIBAAAAA==.Hazan:BAAANQAECggIDwABNQAECgkJKgAYAO0dAA==.',
He='Hexmachine:BAABNQAECn8xAAIeAAoKxRNURwB8AgAeAAoKxRNURwB8AgAAAA==.',
Ho='Hole:BAAANQADCgYJBgAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgIIAgAAAA==.',
Hy='Hypertext:BAABNQAECn8VAAIZAAgKvg/LLACzAQAZAAgKvg/LLACzAQAAAA==.',
Ia='Iamahriman:BAABNQAECn8cAAIKAAgK5QcoiwCIAQAKAAgK5QcoiwCIAQAAAA==.Iamarawn:BAABNQAECn8aAAIMAAgKCwU7vACLAQAMAAgKCwU7vACLAQAAAA==.',
Ic='Icecreme:BAAANQABCgYIDgAAAA==.Icegoesbrr:BAAANQADCgEIAQAAAA==.',
Ig='Ignite:BAABNQAECn8pAAMWAAoKSiCgDgD0AQAWAAkKmCGgDgD0AQAgAAEKJxcGQQBCAAAAAA==.',
Il='Illestria:BAABNQAECn8xAAIHAAkKAxDcIwCUAQAHAAkKAxDcIwCUAQAAAA==.Illumiscotty:BAABNQAECn8wAAQWAAoKeCNdDACkAwAWAAoKeCNdDACkAwAgAAMKzR7JHAAIAQAmAAEKIB6JCgBZAAAAAA==.',
In='Incognonetoo:BAAANQAECggICAAAAA==.Insania:BAABNQAECn8eAAMLAAcK/QYAOwD8AAALAAcK/QYAOwD8AAAKAAUK/ATy1gDmAAAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgYIIQAAAA==.',
Ja='Jab:BAAANQABCgQIBAAAAA==.Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQADCggIDgABNQAECgkJKAAOAJgeAA==.Jastirri:BAAANQAECgUIDAAAAA==.Jayd:BAAANQAECggIAgAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgUIDQAAAA==.Jimothy:BAAANQADCggIDgABNQADCgcICwABAAAAAA==.Jin:BAAANQAECgQIBQAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAABNQAECn8WAAMHAAkKaBJIpwDRAQAHAAkKIxBIpwDRAQARAAcKAQ2uOAAnAQAAAA==.',
Ju='Juicez:BAAANQAECgQICAAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECggICwAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIEwAAAA==.Katio:BAABNQAECn81AAMEAAoK4CBEBAAJAgAEAAkKCRxEBAAJAgAFAAUK4yILNgABAgAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAABNQAECn8YAAIfAAYKngegdACzAAAfAAYKngegdACzAAAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgMIBAAAAA==.Kessandra:BAACNQAFFH8eAAMeAAcKsyIgAQC2AgAeAAcKsyIgAQC2AgAnAAEKAADeCABeAAA1AAQKfycAAycACgpjJB8CAA8DACcACgqvIR8CAA8DAB4ABQp2I0tVANgAAAAA.Kexally:BAAANQAECgMIBgAAAA==.Kexkan:BAAANQADCgQIDAABNQAECgMIBgABAAAAAA==.Kezzia:BAAANQADCgMIAwAAAA==.',
Kh='Khurri:BAABNQAECn8WAAIoAAkKQB30BwDcAgAoAAkKQB30BwDcAgAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAABNQAECn8aAAIMAAoKCBMDBwBYAgAMAAoKCBMDBwBYAgAAAA==.Kisor:BAAANQADCgQIBwAAAA==.Kitchenstink:BAABNQAECn8WAAIfAAkKHBGBigABAgAfAAkKHBGBigABAgAAAA==.',
Ko='Koifo:BAAANQABCgUIBgAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggICgAAAA==.',
Kr='Kritanta:BAABNQAECn8cAAIDAAcKGRLzWACPAQADAAcKGRLzWACPAQAAAA==.Krystallus:BAAANQAECgUICwAAAA==.',
Ku='Kurnea:BAAANQAECgYIEwAAAA==.',
['Kó']='Kórrá:BAAANQAECgIIAgAAAA==.',
La='Lachlann:BAAANQAECgcIEgAAAA==.Ladriel:BAAANQADCgcIBwABNQAECgoKHwAUADQYAA==.Lakartó:BAACNQAFFH8GAAIbAAIKahgQBABMAAAbAAIKahgQBABMAAA1AAQKfzIABBsACQq2HM8KAL4CABsACQpGG88KAL4CABIABgqUG+wKALkBACQAAQpYHzRKAFMAAAAA.Laleaf:BAAANQABCggIEAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgYICAAAAA==.',
Ld='Ldritch:BAACNQAFFH8XAAMEAAYKgCBHAQC9AQAEAAYK6x1HAQC9AQAFAAQKUSGTCQBsAQA1AAQKfyQABAQACgpsIoIaAAQCAAQABgpaI4IaAAQCAAUABgpiIek8ANwBAA0AAQo/GeIZAEUAAAAA.',
Le='Leifson:BAAANQAECgUIBwAAAA==.Leonedis:BAABNQAECn8bAAIfAAYK7AjdgwCWAAAfAAYK7AjdgwCWAAAAAA==.Lethea:BAAANQADCgYICgAAAA==.Levious:BAABNQAECn8aAAIHAAkK6xlIZQBrAgAHAAkK6xlIZQBrAgAAAA==.',
Li='Lianara:BAAANQADCgQICwABNQAECgUICwABAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lokren:BAAANQAECgQIBwAAAA==.Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAACNQAFFH8PAAIYAAUK5h/aAAAgAQAYAAUK5h/aAAAgAQA1AAQKfzEAAhgACgqLID0GACIDABgACgqLID0GACIDAAAA.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECn8nAAMjAAoKVBhlEwBGAgAjAAoKVBhlEwBGAgAZAAIKEgppXwBiAAAAAA==.Luxurious:BAABNQAECn8cAAIiAAcKMQahCwCvAAAiAAcKMQahCwCvAAAAAA==.',
Ma='Maaca:BAAANQAECgIIAgAAAA==.Maecarepicha:BAAANQAECgUICwAAAA==.Magicmoose:BAAANQABCggIDAAAAA==.Malachor:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Maligned:BAAANQAECgcIDwAAAA==.Martichoux:BAABNQAECn8WAAIWAAkK9ReChgBxAgAWAAkK9ReChgBxAgAAAA==.Mastakronik:BAAANQABCgMIAwAAAA==.Match:BAAANQAECgMIAwAAAA==.Mathas:BAABNQAECn83AAQIAAoKQB5ADgBYAwAIAAoKQB5ADgBYAwAHAAIKeAfXhgFQAAARAAEKpw5gdwAlAAAAAA==.Mathilda:BAAANQAECgMIBAAAAA==.',
Mc='Mccholock:BAABNQAECn8VAAMhAAYKzRIjEwBvAQAhAAYKzRIjEwBvAQAfAAIKegqoNwFlAAAAAA==.Mcmach:BAAANQAECgYIEAAAAA==.',
Me='Meddox:BAEANQABCggIFgAAAA==.Mehaoloka:BAAANQADCgcICgAAAA==.Memelle:BAABNQAECn8ZAAIgAAYKNBUmEwB1AQAgAAYKNBUmEwB1AQAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAABNQAECn8ZAAMTAAcKJhGNDgAgAQATAAcKJhGNDgAgAQAUAAIKtQQBcQBCAAAAAA==.Menotthatorc:BAAANQAECgIIAgABNQAFFAIIBgADAEgPAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAABNQAECn8XAAMOAAcKnB6ZCABdAgAOAAcKnB6ZCABdAgAPAAEKAAD/hwAiAAAAAA==.Mesilana:BAAANQAECgMIAwAAAA==.Metrx:BAAANQAECgUIBAAAAA==.',
Mi='Mikosen:BAAANQAECgQIBAAAAA==.Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAABNQAECn8aAAIOAAcKxhY6GACwAQAOAAcKxhY6GACwAQAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.Mithian:BAAANQADCgMJAwAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgUIBwAAAA==.Monichan:BAAANQAECgMIAwAAAA==.Moosecheeks:BAABNQAECn8VAAITAAkK7hgJEwAzAgATAAkK7hgJEwAzAgAAAA==.Morior:BAABNQAECn8XAAIdAAYKfQ4LBQDZAAAdAAYKfQ4LBQDZAAAAAA==.Morslucifer:BAABNQAECn8ZAAMnAAgKvBiKBQBoAgAnAAgKvBiKBQBoAgAdAAEKehPDcgA8AAAAAA==.Motorcade:BAABNQAECn8dAAIaAAgKVANRDQCDAAAaAAgKVANRDQCDAAAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQAECgIIAgAAAA==.',
My='Mypal:BAAANQAECgYIDwAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
Na='Naula:BAAANQAECgEIAQAAAA==.',
Ne='Neather:BAABNQAECn8aAAIgAAgKEBeVCgAfAgAgAAgKEBeVCgAfAgAAAA==.Neron:BAAANQADCgUIDQAAAA==.Nezkima:BAAANQAECgUIBQABNQAECgoKMAALALIeAA==.',
Ni='Nidivh:BAAANQAECgMICAAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAABNQAECn8WAAIHAAYKgA8u4wBVAQAHAAYKgA8u4wBVAQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAgAAAA==.Nira:BAABNQAECn8kAAIOAAoKcRaTQgBiAgAOAAoKcRaTQgBiAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAABNQAECn8UAAIoAAcK/xJuEgDXAQAoAAcK/xJuEgDXAQAAAA==.',
No='Nodöts:BAAANQAECggICAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Nonetoo:BAAANQAECggIAQABNQAECggICAABAAAAAA==.Notdeadyet:BAAANQAECgUIDAAAAA==.Notron:BAABNQAECn8XAAIXAAkK4hZmJwBjAgAXAAkK4hZmJwBjAgAAAA==.Noz:BAAANQADCggIFAAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQAECgEIAwAAAA==.Nychophysis:BAABNQAECn8ZAAMFAAYKywyBJADAAAAFAAYKywyBJADAAAAEAAEKvQPLUQAzAAAAAA==.Nyxion:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oakarm:BAAANQAECggICAAAAA==.Oasis:BAAANQAECgYIBwAAAA==.',
Od='Odyssius:BAAANQAECggIAQAAAA==.',
Og='Ogden:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Om='Omars:BAAANQAECgUICAAAAA==.',
On='Ontherun:BAAANQAECgIIAgAAAA==.',
Op='Oprawinfury:BAAANQAECgUICwAAAA==.',
Or='Orphani:BAAANQABCgMIAQAAAA==.',
Ou='Ourus:BAABNQAECn85AAIcAAoKriA4AwBvAwAcAAoKriA4AwBvAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Panax:BAAANQAECgUICwAAAA==.Paulo:BAABNQAECn8WAAIHAAYKAgqF8gA3AQAHAAYKAgqF8gA3AQAAAA==.',
Pe='Pele:BAAANQAECgUIDQAAAA==.Pellito:BAAANQADCgQICAAAAA==.Perpetrator:BAABNQAECn8fAAIDAAgKMAQ4LADDAAADAAgKMAQ4LADDAAAAAA==.',
Pi='Picklez:BAAANQAECggIDgAAAA==.Piki:BAABNQAECn8eAAILAAkK5wrCNwAGAQALAAkK5wrCNwAGAQAAAA==.',
Po='Poepwn:BAABNQAECn8iAAQjAAcKAwwYFACsAAAjAAcKAwwYFACsAAAaAAIKAQWuLwBAAAAZAAEKAACQdwAgAAAAAA==.',
Pr='Pray:BAAANQAECgcIDQABNQAECgEIAQABAAAAAA==.Prescient:BAAANQAECggIBgAAAA==.',
Pu='Puffypanda:BAAANQAECgUICwAAAA==.Putnamehere:BAAANQABCgcICQAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quadeshboy:BAAANQAECgEIAQAAAA==.Quill:BAAANQAECggIEwAAAA==.',
Ra='Raging:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Ralz:BAABNQAECn8aAAICAAYK3RT7UABvAQACAAYK3RT7UABvAQAAAA==.Rangon:BAAANQADCggIDwAAAA==.Rannick:BAABNQAECn8bAAMYAAcKKguVCwA9AQAYAAcKKguVCwA9AQALAAEK9QYKJQEoAAAAAA==.Ranua:BAAANQAECgUICQABNQAECgkJKAAOAJgeAA==.Ratdemonmike:BAAANQAECgUIDgAAAA==.Rate:BAAANQAECgYIDwABNQAECgoKJgAGAPYVAA==.Ratio:BAABNQAECn8mAAIGAAoK9hVaJgATAgAGAAoK9hVaJgATAgAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAAANQAECgcICQAAAA==.',
Ri='Richard:BAAANQAECgMIAwAAAA==.Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgYIDwABNQAECgcICQABAAAAAA==.',
Ru='Ruden:BAAANQAECgMIBQAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECggIDAABNQAECgkJKgAYAO0dAA==.',
Rw='Rwqr:BAABNQAECn8vAAIXAAkKHAvpQAC4AQAXAAkKHAvpQAC4AQAAAA==.',
['Rä']='Räiden:BAABNQAECn8YAAMgAAgKlQ15BgA0AQAgAAcK6w55BgA0AQAWAAYKsAccOAEvAQAAAA==.',
Sa='Salacake:BAAANQAECgQIBAAAAA==.Salacakei:BAABNQAECn8tAAMFAAkKyBC5DgBPAQAFAAgKXRK5DgBPAQAEAAUKTAxmNgAGAQAAAA==.Salin:BAAANQAECgUICAAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFH8eAAIRAAcKyh7VAAClAgARAAcKyh7VAAClAgA1AAQKfygAAhEACgrsJZQFAFYDABEACgrsJZQFAFYDAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scaley:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Scarletpaw:BAAANQAECgEIAQAAAA==.Scoobie:BAAANQAECgEIAQABNQAECgkJLQAMAEofAA==.Scoobydo:BAAANQAECgUICwABNQAECgkJLQAMAEofAA==.Scratches:BAAANQAECgIIBAAAAA==.Scrubs:BAACNQAFFH8GAAIMAAQK3gPlGgDjAAAMAAQK3gPlGgDjAAA1AAQKfzQAAgwACgqNGY8GAGACAAwACgqNGY8GAGACAAAA.',
Se='Seider:BAAANQAECggIBgAAAA==.Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadhunter:BAAANQABCgQIAgAAAA==.Shadpriest:BAAANQABCgIIAgABNQABCgQIAgABAAAAAA==.Shaggzy:BAACNQAFFH8XAAIZAAcK1BdSAwA1AgAZAAcK1BdSAwA1AgA1AAQKfzIAAhkACgrmImQHAFoDABkACgrmImQHAFoDAAAA.Shallabal:BAAANQAECggICAAAAA==.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAABNQAECn8bAAMlAAcKqxHUGQC8AAAMAAcK7A8otgCYAQAlAAYKjg/UGQC8AAAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAAANQAECgUIDQAAAA==.Shockdoctor:BAABNQAECn8dAAMLAAkK/iLvGwD/AgALAAkK/iLvGwD/AgAKAAMKTxR2+QCgAAAAAA==.Shortrange:BAAANQADCgEJAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJKwAIACokAA==.',
Sl='Sleples:BAABNQAECn8tAAIMAAkKSh+0CQAtAgAMAAkKSh+0CQAtAgAAAA==.Slufgor:BAAANQAECgQICwAAAA==.Slyxxii:BAAANQAECgQIBAAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCggIFQAAAA==.',
Sn='Snoo:BAAANQAECgQICwAAAA==.',
So='Solarlite:BAAANQAECgUIBAAAAA==.Solinari:BAAANQABCgIIBAAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAABNQAECn8aAAMOAAkKqCMVCQB7AwAOAAkKqCMVCQB7AwAQAAIK8CTpFQDNAAAAAA==.Soulbreakër:BAABNQAECn8tAAICAAkKbQs6SQCXAQACAAkKbQs6SQCXAQAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYIDQAAAA==.Sparks:BAAANQAECgMIBAABNQAECgkJHQAWALsPAA==.Specimen:BAAANQADCggJEgAAAA==.Speddling:BAABNQAECn8dAAIWAAkKuw9OLQBpAQAWAAkKuw9OLQBpAQAAAA==.Spellgennce:BAAANQAECgQIBAAAAA==.Spicey:BAAANQADCgYIDAABNQAECgoKMAAMADseAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQAECgMIBwAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAAANQAECgUICwAAAA==.',
Sr='Srbranchmgr:BAAANQADCgMIBAAAAA==.',
St='Starbrow:BAABNQAECn8WAAIMAAcKhiIxTACJAgAMAAcKhiIxTACJAgAAAA==.Starrybeko:BAAANQABCgYIBgABNQAECgoKJgAWAFEZAA==.Stilez:BAAANQAECggIBwABNQAECggIEAABAAAAAA==.Stormlight:BAAANQAECgcIEwAAAA==.Strudelmaker:BAAANQAECgMIAwABNQAECgkJIgAXACUaAA==.',
Su='Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAAANQAECgQIBwAAAA==.',
Sy='Syland:BAAANQAECgUIDQAAAA==.Sylvanäs:BAAANQAECgUIDQAAAA==.Syrellina:BAAANQAECgQIBAABNQAECgkJKAAOAJgeAA==.Sysna:BAABNQAECn8qAAMOAAoK+x4bQwBfAgAOAAcKRCAbQwBfAgAPAAoKsCJ2BwB+AQAAAA==.',
Ta='Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECn8fAAILAAcKXBTKbgC/AQALAAcKXBTKbgC/AQAAAA==.Targis:BAABNQAECn8hAAIfAAgKDw+DpADBAQAfAAgKDw+DpADBAQAAAA==.Tauran:BAAANQADCgcIDwAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECgkJKAAOAJgeAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Tergar:BAAANQAECgIIAQAAAA==.',
Th='Thaleas:BAABNQAECn8bAAQRAAkKRRSlCwBDAQARAAYKyhOlCwBDAQAIAAgK+wnYQwDfAAAHAAEKAABFIQEAAAAAAA==.Thegreatkhal:BAABNQAECn8XAAIPAAcKJRq1CQBZAQAPAAcKJRq1CQBZAQAAAA==.Therizino:BAAANQADCgEIAQAAAA==.Thorizine:BAAANQAECgcIEAAAAA==.Thorlas:BAABNQAECn8hAAMLAAcKuiE/GACWAQALAAYKeiE/GACWAQAKAAMKCxet7wC3AAAAAA==.Thornado:BAAANQADCgMIAwAAAA==.Thotsfortots:BAAANQAECggIBQABNQAECgoKHAAUAAMZAA==.Thylacoleo:BAAANQADCgUIBQAAAA==.',
Ti='Timmúk:BAABNQAECn8iAAIXAAkKJRp9KwBHAgAXAAkKJRp9KwBHAgAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAABAAAAAA==.Tomma:BAAANQAECggIDgAAAA==.Torment:BAAANQAECgIIAQABNQAECgEIAQABAAAAAA==.Torsion:BAABNQAECn8bAAIKAAgKlRo5GABgAQAKAAgKlRo5GABgAQAAAA==.',
Tr='Trailerpark:BAAANQADCgMJAwAAAA==.Tratre:BAABNQAECn8dAAMbAAgKzB16BQA0AQAbAAgKzB16BQA0AQAkAAIKcAovSABgAAAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQAECgQICAAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAcIEAAXAOoZAA==.Tust:BAAANQAECgQICAABNQADCgcICwABAAAAAA==.',
Ty='Tylandy:BAABNQAECn8qAAIWAAoKfSFtBwBWAgAWAAoKfSFtBwBWAgAAAA==.Tytaniormu:BAAANQAECgYIBwAAAA==.',
['Tê']='Tês:BAAANQAECgUICwAAAA==.',
Un='Undeadbetty:BAAANQADCgcICAAAAA==.Undeathtwoy:BAAANQAECgEIAQABNQAECgkJLgAPAFUcAA==.',
Va='Vaayl:BAABNQAECn8UAAIYAAcK0x4tFgAGAgAYAAcK0x4tFgAGAgAAAA==.Vaelraen:BAAANQAECgUICgAAAA==.Valcher:BAAANQAECgYIDQAAAA==.Valendera:BAABNQAECn8WAAIeAAkKRAkdlAC0AQAeAAkKRAkdlAC0AQAAAA==.Valerius:BAAANQAECgYICAAAAA==.Valguero:BAAANQADCggICwAAAA==.Valifadin:BAABNQAECn8YAAIpAAcKuB5/AgB6AQApAAcKuB5/AgB6AQAAAA==.Valndrevy:BAAANQADCggIGQAAAA==.Vamire:BAAANQAECggIEAAAAA==.Vanpèlt:BAAANQADCgUIDQAAAA==.Vansan:BAABNQAECn8oAAQOAAkKmB4jIADvAgAOAAkKph0jIADvAgAQAAEKKSDTBwBgAAAPAAIKwBA0MAA9AAAAAA==.',
Ve='Venngennce:BAABNQAECn8zAAICAAoKXR2zFQDeAgACAAoKXR2zFQDeAgAAAA==.',
Vi='Viktir:BAAANQADCgYIDAABNQAECgUIDQABAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Voladen:BAAANQAECgEIAQAAAA==.Vorkath:BAABNQAECn8nAAMbAAoKJSKiBQA2AwAbAAoKJSKiBQA2AwAkAAQKOwqgOQDJAAAAAA==.Vormette:BAAANQADCggIGQAAAA==.',
Vt='Vtae:BAABNQAECn8UAAIMAAYKjQahhQChAAAMAAYKjQahhQChAAAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAABNQAECn8nAAIUAAgKjhHpCACpAQAUAAgKjhHpCACpAQAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Wo='Woxkal:BAABNQAECn8cAAQCAAgKcgflYQAdAQACAAcK1wXlYQAdAQAJAAQKDwY2tgCCAAADAAMKegcdrwBtAAAAAA==.',
Wu='Wubblebubble:BAAANQAECggICwAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgUIDQAAAA==.',
Xu='Xuzhu:BAABNQAECn8cAAIWAAoKXxOONQBUAQAWAAoKXxOONQBUAQABNQAFFAYIDgAVAGgOAA==.',
Ye='Yelignar:BAAANQABCgEIAQAAAA==.',
Yi='Yinei:BAAANQAFFAIIAgAAAA==.',
Yl='Ylvis:BAABNQAECn8bAAIMAAgKbhV+eAAeAgAMAAgKbhV+eAAeAgAAAA==.',
Yo='Yol:BAABNQAECn8aAAISAAkKngxjCgDKAQASAAkKngxjCgDKAQAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECggIIQAAAQ==.',
Yv='Yvetal:BAAANQAECgUIDAABNQAFFAIIBgADAEgPAA==.',
Za='Zapdos:BAAANQADCggICAAAAA==.Zarion:BAACNQAFFH8RAAIUAAUKYR8bBQDNAQAUAAUKYR8bBQDNAQA1AAQKfygAAxQACgrvIv0EAHMDABQACgrvIv0EAHMDABUAAQoAANvDAB4AAAAA.Zarra:BAAANQAECgQIBAAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQIBAAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQAECgIIAgABNQAFFAUIEQAUAGEfAA==.Ziyar:BAAANQAECgMIBwABNQAFFAUIEQAUAGEfAA==.',
Zo='Zocorro:BAAANQAECgUICwAAAA==.',
Zr='Zra:BAAANQADCgEIAQAAAA==.',
Zy='Zypherdius:BAAANQAECgIIAgAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFH8aAAIHAAYKyRdfCwCTAQAHAAYKyRdfCwCTAQA1AAQKfywAAgcACgryIB47AOUCAAcACgryIB47AOUCAAAA.',
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
