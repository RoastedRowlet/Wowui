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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection','Evoker-Augmentation','Druid-Guardian','Druid-Restoration','Druid-Balance','Mage-Arcane','DemonHunter-Havoc','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Evoker-Devastation','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Mage-Frost','Warrior-Fury','DemonHunter-Vengeance','Evoker-Preservation','Hunter-Marksmanship','Druid-Feral','Mage-Fire','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaralyn:BAAANQAECgQIBgAAAA==.',
Ab='Abmikaze:BAAANQAECggIEAAAAA==.Absolon:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.Abysseon:BAABNQAECn8eAAMCAAoK+Ro4MAAkAgACAAoK+Ro4MAAkAgADAAMK2w2IqgB7AAAAAA==.',
Ac='Ace:BAABNQAECn8sAAMEAAoKWyEAGABdAgAEAAkKtR8AGABdAgAFAAMKNiK0bwDyAAABNQAECgEIAQABAAAAAA==.',
Ad='Adios:BAACNQAFFH8RAAIGAAYKDA9jBQDbAQAGAAYKDA9jBQDbAQA1AAQKfzYAAgYACgrdIQAKADkDAAYACgrdIQAKADkDAAAA.Adorean:BAABNQAECn8fAAIHAAoKMhCZoADgAQAHAAoKMhCZoADgAQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgQIDQAAAA==.Agrohn:BAABNQAECn8YAAMHAAcKQxSRuQCqAQAHAAcKQxSRuQCqAQAIAAEKrgKUNAEjAAAAAA==.',
Ai='Aimnskin:BAAANQADCggJEwAAAA==.',
Al='Alcore:BAABNQAECn8mAAQDAAoKpBlQIACxAgADAAcK2yFQIACxAgAJAAYKaByeTADiAQACAAkKgRO3JgCcAQAAAA==.Aliine:BAABNQAECn8iAAIDAAgKYQ6iNwAGAQADAAgKYQ6iNwAGAQAAAA==.',
Am='Ameiisaa:BAABNQAECn8gAAMKAAgKJgUZdADiAAAKAAcKsgIZdADiAAALAAUK3wQP6QDFAAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAACNQAFFH8MAAILAAUKkBMkFQAmAQALAAUKkBMkFQAmAQA1AAQKf0sAAgsACgrgIC8aACwDAAsACgrgIC8aACwDAAAA.',
An='Anxie:BAABNQAECn8gAAIMAAkKwQVfsgDKAAAMAAkKwQVfsgDKAAAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAcIEwANAEYZAA==.',
Ao='Aoifae:BAABNQAECn8UAAIHAAYKQRLAywCEAQAHAAYKQRLAywCEAQAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECn8ZAAQOAAkKnAk3gQCUAQAOAAgKGgo3gQCUAQAPAAcKewY1QAAtAQAQAAEKMAVqLwAmAAAAAA==.Apprentice:BAABNQAECn8jAAIRAAkKCgNKKwCyAAARAAkKCgNKKwCyAAAAAA==.',
Ar='Aramos:BAABNQAECn8lAAIIAAgK3xmNPQBuAgAIAAgK3xmNPQBuAgAAAA==.Aramôs:BAAANQAECgUIDAAAAA==.Aristania:BAAANQAECgIIAgAAAA==.Arkhangel:BAABNQAECn8ZAAIHAAgKJBiNeAA7AgAHAAgKJBiNeAA7AgAAAA==.Arta:BAAANQAECgUIDQAAAA==.Artavian:BAAANQABCgIIAwAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAABNQAECn8lAAIOAAgKoA/sfwCZAQAOAAgKoA/sfwCZAQAAAA==.Assiam:BAAANQADCgIIAgAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Ay='Ayame:BAAANQABCgMIBQAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECgoKNgADAP4XAA==.',
Ba='Badflood:BAAANQABCgIIAgAAAA==.Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQAECgQIDwAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.Basicampfire:BAAANQAECgQIBQABNQAECggIHwASAM8IAA==.Bautumn:BAAANQAECgEIAQAAAA==.',
Be='Beaker:BAABNQAECn8rAAITAAoK7hpOCABWAgATAAoK7hpOCABWAgAAAA==.Beastmode:BAABNQAECn8+AAMUAAoKixXyKQDPAQAUAAoKixXyKQDPAQAVAAgKsRVrIQB6AQAAAA==.Bedlem:BAAANQAECgcIDQAAAA==.Beko:BAABNQAECn8tAAIWAAoKqRvwQwD8AgAWAAoKqRvwQwD8AgAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBgAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgMIBwAAAA==.Billydan:BAABNQAECn8jAAIXAAkK2w2rIACRAQAXAAkK2w2rIACRAQAAAA==.',
Bl='Blackhide:BAAANQABCgUIBgAAAA==.Blackpanthxr:BAABNQAECn82AAQKAAoK+xQwRwBFAgAKAAoK+xQwRwBFAgAYAAcKghHWGQDHAQALAAcKfAdXrgA2AQAAAA==.Blackvortex:BAAANQAECgQIBAAAAA==.Bloodgoat:BAAANQADCggICwAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECgkJHgAZAFkjAA==.Bloodyburst:BAABNQAECn8aAAMNAAgK2CKlBQCMAgANAAcKEyOlBQCMAgAFAAIKDBywggCpAAABNQAECgkJHgAZAFkjAA==.Bloodyfistz:BAABNQAECn8eAAMZAAkKWSNhDgD5AgAZAAkKRCNhDgD5AgAaAAIKMyOyIgDDAAAAAA==.Blue:BAABNQAECn8lAAILAAoKXRo/KwDTAgALAAoKXRo/KwDTAgAAAA==.Bluethreetwo:BAAANQAECgQICAAAAA==.',
Bo='Bookofzeref:BAAANQAECgcIBwAAAA==.Boost:BAAANQABCgIIBAAAAA==.',
Br='Brayend:BAABNQAECn8dAAIYAAoKqA30CgD0AQAYAAoKqA30CgD0AQAAAA==.Brewguts:BAABNQAECn8cAAIbAAkK5xqHBwBqAgAbAAkK5xqHBwBqAgAAAA==.Brimscythe:BAABNQAECn81AAIcAAoKFRxSBAAuAgAcAAoKFRxSBAAuAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggIDgAAAA==.Caliandis:BAABNQAECn8cAAIdAAcKEA9gFwDbAAAdAAcKEA9gFwDbAAAAAA==.Calvey:BAAANQAECgYIDgAAAA==.Cambrai:BAAANQAECgcIDQAAAA==.Cannabelle:BAABNQAECn8kAAIMAAkK8CFBHgAeAwAMAAkK8CFBHgAeAwAAAA==.Carclias:BAACNQAFFH8IAAMeAAQKvwwDBQCMAAAeAAIKBwoDBQCMAAAfAAIKLhIeJgBOAAA1AAQKf0cAAx4ACgrNG08NACQCAB4ACQpsGE8NACQCAB8ACQrhFM5CAJ8BAAAA.Carthrix:BAABNQAECn8XAAMgAAkKlAo8pwC7AQAgAAgKAgw8pwC7AQAdAAEKAgKpNgAgAAAAAA==.Catbarf:BAAANQAECgYIAQABNQAECgoKMQAYALUeAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAAANQAECgYIEgAAAA==.',
Ce='Celery:BAAANQAECgYIEgABNQAFFAcIHAADAC4WAA==.Cellika:BAAANQAECgYIDwAAAA==.Cerdelz:BAAANQAECgQIBAAAAA==.',
Ch='Chanclatotem:BAAANQADCgIIAgAAAA==.Chaoscookies:BAABNQAECn8/AAMeAAoKNhYeEwDaAQAeAAcKsxYeEwDaAQAfAAgKMRF9VgBfAQAAAA==.Chaotik:BAAANQABCgIIAgAAAA==.Chartkov:BAAANQAECgUICQAAAA==.Cheezee:BAABNQAFFH8TAAMWAAcKLhB9EADzAQAWAAYKzhN9EADzAQAhAAEKrwHVEQBLAAAAAA==.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQADCggIFgAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECgkJFQALAJcVAA==.',
Ci='Cinderpetal:BAAANQAECgQICAAAAA==.',
Ck='Ckay:BAAANQAECgcIBwAAAA==.',
Cl='Clawsome:BAAANQADCggIEwAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAACNQAFFH8GAAMDAAIKSA/JIwBvAAACAAIK9wmUFwCEAAADAAIKSA/JIwBvAAA1AAQKfyIABAIACgq3Gi8hAIQCAAIACQrRGC8hAIQCAAkABwoFFf5gAIwBAAMABApXFTaIAN4AAAE1AAUUBAgKAB8AvxQA.Comlock:BAAANQADCgcIEwAAAA==.Complacent:BAABNQAECn8uAAITAAoKaQSCKQDHAAATAAoKaQSCKQDHAAAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgIIBAAAAA==.Coriander:BAABNQAECn8YAAISAAkKlBJQCAAUAgASAAkKlBJQCAAUAgAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAABNQAECn8ZAAMVAAoKfhRgQgDtAQAVAAkKRhVgQgDtAQAUAAMKIhGaXgAnAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAcIGAAZANQXAA==.',
Cy='Cynical:BAAANQAECgIIAwABNQAECgEIAQABAAAAAA==.Cyonicus:BAABNQAECn8fAAIfAAoKMRkRXABDAgAfAAoKMRkRXABDAgAAAA==.Cyska:BAABNQAECn82AAIDAAoK/heUJwCDAgADAAoK/heUJwCDAgAAAA==.',
['Cé']='Cécé:BAABNQAECn8pAAIHAAkKzxgwaQBgAgAHAAkKzxgwaQBgAgAAAA==.',
['Cë']='Cëcë:BAAANQAECgMIAwAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAABNQAECn89AAIOAAoKBhNJJABGAgAOAAoKBhNJJABGAgAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagaurie:BAAANQAECggICAABNQAECgoKIQAVAF4bAA==.Dagerlaurn:BAABNQAECn8hAAMVAAoKXhtZFwDiAQAVAAoKXhtZFwDiAQAUAAUKkhhmOgBMAQAAAA==.Dagevas:BAAANQADCgYICAAAAA==.Dakeria:BAAANQADCgYIGgAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEAAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECn86AAIiAAoKrRZPCgAnAgAiAAoKrRZPCgAnAgABNQAFFAUIDQAHACUcAA==.Davriell:BAABNQAECn8dAAICAAoKlgoNJgCgAQACAAoKlgoNJgCgAQAAAA==.Dax:BAABNQAECn8cAAIMAAcK8AurggAtAQAMAAcK8AurggAtAQAAAA==.Daxing:BAAANQADCggIFAABNQAECgoKKwAOAJwfAA==.',
De='Deeppurple:BAAANQAECgUIDQAAAA==.Del:BAABNQAECn8uAAIjAAoKUiYyAQALAwAjAAoKUiYyAQALAwABNQAECgoKLgAbAFQYAA==.Demonic:BAAANQAECgUICAABNQAECgEIAQABAAAAAA==.Demonshady:BAAANQABCggIFAAAAA==.Demoraliziñg:BAAANQADCggIDgABNQAECgkJJwAXAKcaAA==.Demostache:BAACNQAFFH8KAAMfAAQKvxSjEwCwAAAfAAMK8xmjEwCwAAAeAAIKWQrBDQBMAAA1AAQKfzYAAx8ACgr6I1MfAEICAB8ACQqwI1MfAEICAB4AAwqXEjITAIAAAAAA.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECn8vAAILAAoKPSGUFABjAgALAAoKPSGUFABjAgAAAA==.',
Di='Diivision:BAAANQAECgEIAgABNQAECgoKLQAGAM8YAA==.',
Do='Dolomite:BAABNQAECn8XAAIWAAgKUgVrGQFhAQAWAAgKUgVrGQFhAQAAAA==.Dorow:BAABNQAECn8wAAMVAAoKnBi8JQClAgAVAAoKnBi8JQClAgAUAAYKiBSsJgAnAQAAAA==.Dotabolt:BAABNQAECn8VAAIfAAcKyw+4nACeAQAfAAcKyw+4nACeAQABNQAECgoKIAAhAJwbAA==.',
Dr='Dracthyris:BAABNQAECn8nAAIkAAkKEAz4DgCCAQAkAAkKEAz4DgCCAQAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Dreaa:BAAANQAECgEIAQAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECn8xAAIYAAoKtR58BwAGAwAYAAoKtR58BwAGAwAAAA==.',
Du='Dunsel:BAABNQAECn8YAAIIAAcKGgyXYAAgAQAIAAcKGgyXYAAgAQABNQAECgoKNQAcABUcAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgYICQAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECn84AAMgAAkKAhXVQADMAQAgAAkKAhXVQADMAQAdAAIK/QnjPABRAAAAAA==.',
['Dã']='Dãnny:BAAANQADCggIDQABNQAECgkJOAAgAAIVAA==.',
Ea='Earendil:BAAANQAECggICAAAAA==.',
Eb='Ebonshade:BAAANQAECgQIBQAAAA==.',
Ed='Edena:BAAANQAECgEIAQAAAA==.Edginglord:BAAANQAECgcIDAAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQAAAA==.Eloras:BAABNQAECn8XAAILAAkK2RsrJwDLAQALAAkK2RsrJwDLAQAAAA==.Elunbi:BAABNQAECn85AAMOAAoK1xzZHgD1AgAOAAoKRhzZHgD1AgAQAAYKkhSZDQBZAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQAECgQIBQAAAA==.',
Ep='Epsilòn:BAEBNQAECn8YAAMfAAkKtwrczwAqAQAfAAYKrxLczwAqAQAeAAgKFwAMiAAdAAAAAA==.',
Er='Ernest:BAAANQAECgUIEQAAAA==.Errani:BAABNQAECn8hAAMhAAcKqxAdEQCVAQAhAAcKqxAdEQCVAQAWAAIKHQS6NAEpAAAAAA==.',
Es='Esheman:BAAANQADCgQIDAAAAA==.Esper:BAAANQAECgcIDQAAAA==.Esterlia:BAAANQAECgMIAwABNQAECgoKKwAOAJwfAA==.',
Et='Eternal:BAAANQAECgEIAQAAAA==.',
Eu='Eureki:BAABNQAECn8dAAIXAAkK4QgTKQBRAQAXAAkK4QgTKQBRAQAAAA==.',
Ev='Evilkarma:BAAANQAECgcIEAAAAA==.Evocatis:BAACNQAFFH8MAAIHAAUKFx3hDwBOAQAHAAUKFx3hDwBOAQA1AAQKfzoABAcACgrsI1kXAMICAAcACgrsI1kXAMICAAgABApTDRvNAOEAABEAAQpgF1NHADwAAAAA.',
Ex='Exilion:BAAANQAECgMIAwAAAA==.',
Ey='Eyekonicklok:BAAANQAECgYICAABNQAECgQIBAABAAAAAA==.Eyesdeadeyed:BAACNQAFFH8GAAIlAAMKago2DwB0AAAlAAMKago2DwB0AAA1AAQKfy4AAyUACgqMFoImABgCACUACgqMFoImABgCAAwAAQpbELH+AEgAAAAA.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAABNQAECn8zAAMHAAoKeRnSRgDAAgAHAAoKeRnSRgDAAgAIAAYKExwLfwCcAQAAAA==.Faon:BAAANQAECgYICQAAAA==.Farrea:BAAANQAECgEIAgABNQAECgUICQABAAAAAA==.Fatlock:BAAANQAECgQICQABNQAECgoKMwAZALkbAA==.Fayvia:BAAANQAECgQIBAAAAA==.',
Fe='Feebz:BAAANQADCgYIBwAAAA==.Feebzykun:BAAANQABCgIIBAAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECggIDQABNQAECgEIAQABAAAAAA==.Firebirdz:BAACNQAFFH8LAAIUAAUKRBPWCQBBAQAUAAUKRBPWCQBBAQA1AAQKfykAAhQACgr4HSYTALQCABQACgr4HSYTALQCAAAA.Firebirdzx:BAAANQAECgMIBQABNQAFFAUICwAUAEQTAA==.',
Fl='Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCggIEAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAABNQAECn82AAIGAAkKRhGsFwB9AQAGAAkKRhGsFwB9AQAAAA==.Freshhéals:BAAANQAECgEIAQABNQAFFAUIBwANAEwPAA==.Frizby:BAAANQAECgQIBgAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAABNQAECn8VAAITAAYKIxm5GgDPAQATAAYKIxm5GgDPAQAAAA==.',
Fy='Fyrelord:BAAANQAECgMIAgAAAA==.Fyuna:BAABNQAECn8rAAIKAAoKzxo1LQCtAgAKAAoKzxo1LQCtAgAAAA==.',
Ga='Gark:BAAANQAECgQIDAAAAA==.Garkk:BAAANQADCgQJBAAAAA==.Garrumn:BAAANQADCgcIBwABNQAFFAQICgAfAL8UAA==.Gazzi:BAABNQAECn8WAAITAAkKcg6rHAC9AQATAAkKcg6rHAC9AQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECggIHgAOADMfAA==.',
Gi='Giuseppee:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Gióvanna:BAAANQAECgUIDQAAAA==.',
Gl='Glodskegg:BAABNQAECn8WAAIeAAkKlBG9CQBcAgAeAAkKlBG9CQBcAgAAAA==.',
Go='Gobblious:BAAANQADCgYIBgAAAA==.Goldensea:BAAANQAECgQICwAAAA==.Gondra:BAAANQABCgEIAQAAAA==.Gotenk:BAABNQAECn8ZAAMmAAkKiSKmBgABAgAmAAkKiSKmBgABAgAUAAEK6RkTUQBKAAAAAA==.Goyim:BAAANQAECgQIBQAAAA==.',
Gr='Gr:BAAANQADCgYIEwAAAA==.Grissoul:BAAANQAECgYIBgAAAA==.Grody:BAABNQAECn8UAAIfAAYKNQrm0wAiAQAfAAYKNQrm0wAiAQAAAA==.Gryms:BAAANQAECgYICwAAAA==.',
Gu='Guroo:BAABNQAECn8qAAIMAAkKTQzuZQBwAQAMAAkKTQzuZQBwAQAAAA==.Gutslammer:BAABNQAECn8ZAAIIAAoKuhibEQDBAgAIAAoKuhibEQDBAgAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
['Gí']='Gígí:BAAANQAECgIIBAAAAA==.Gíl:BAAANQAECgUIBAAAAA==.',
Ha='Hagarn:BAACNQAFFH8FAAIHAAIKPQ5XGACHAAAHAAIKPQ5XGACHAAA1AAQKfy0AAgcACgrDFC18ADICAAcACgrDFC18ADICAAAA.Halastrin:BAAANQAECgEIAQAAAA==.Halimah:BAAANQAECgQICQAAAA==.Halois:BAAANQADCgYIBgABNQAECgcIHAADABkSAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggIDgAAAA==.Harvestt:BAAANQADCgQIBAAAAA==.Hazan:BAAANQAECggIEwABNQAECgoKMQAYALUeAA==.',
He='Hexmachine:BAABNQAECn84AAIfAAoKuxZURwB8AgAfAAoKuxZURwB8AgAAAA==.',
Ho='Hole:BAAANQADCgYJBgAAAA==.Hollymagic:BAAANQADCggIBgAAAA==.Holmstein:BAAANQADCggICAAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgEIAgAAAA==.',
Hy='Hypertext:BAABNQAECn8XAAIZAAkKZA/LLACzAQAZAAkKZA/LLACzAQAAAA==.',
Ia='Iamahriman:BAABNQAECn8fAAILAAgKIAgoiwCIAQALAAgKIAgoiwCIAQAAAA==.Iamarawn:BAABNQAECn8cAAIMAAgKSgU7vACLAQAMAAgKSgU7vACLAQAAAA==.',
Ic='Icecreme:BAAANQABCgYIDgAAAA==.Icegoesbrr:BAAANQADCgEIAQAAAA==.',
Ig='Ignite:BAABNQAECn8zAAMWAAoKfiDDJgBaAgAWAAkK0yHDJgBaAgAhAAEKJxcGQQBCAAAAAA==.',
Il='Illestria:BAABNQAECn85AAIHAAkKAxB+aQCDAQAHAAkKAxB+aQCDAQAAAA==.Illumiscotty:BAABNQAECn80AAQWAAoKQyVdDACkAwAWAAoKQyVdDACkAwAhAAMKzR7JHAAIAQAnAAEKIB6JCgBZAAAAAA==.',
Im='Imodium:BAAANQAECgIIAgAAAA==.',
In='Incognonetoo:BAAANQAECggICQABNQAECggICQABAAAAAA==.Insania:BAABNQAECn8mAAMKAAkK2AWKYQAZAQAKAAgKhwaKYQAZAQALAAYKdwTy1gDmAAAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgYIJAAAAA==.',
Ja='Jab:BAAANQABCgQIBAAAAA==.Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQAECgUICgABNQAECgoKKwAOAJwfAA==.Jastirri:BAAANQAECgUIDAAAAA==.Jayd:BAAANQAECggIAgAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgUIDQAAAA==.Jimothy:BAAANQADCggIDgABNQAECgQIBQABAAAAAA==.Jin:BAAANQAECgQICAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAABNQAECn8WAAMHAAkKaBJIpwDRAQAHAAkKIxBIpwDRAQARAAcKAQ2uOAAnAQAAAA==.',
Ju='Juicez:BAAANQAECgUIDQAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECggIDgAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIEwAAAA==.Katio:BAABNQAECn8/AAMEAAoKeCGpEwCFAgAEAAoKAxypEwCFAgAFAAUK4yILNgABAgAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAABNQAECn8eAAIgAAcKygbqmwDUAAAgAAcKygbqmwDUAAAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgMIBAAAAA==.Kessandra:BAACNQAFFH8eAAMfAAcKsyIgAQC2AgAfAAcKsyIgAQC2AgAoAAEKAADeCABeAAA1AAQKfyoAAygACgp1JR8CAA8DACgACgoyIx8CAA8DAB8ABgq+I5JiAD4BAAAA.Kexally:BAAANQAECgMICQAAAA==.Kexkan:BAAANQADCgQIDAABNQAECgMICQABAAAAAA==.Kexxy:BAAANQADCgMIAwABNQAECgMICQABAAAAAA==.Kezzia:BAAANQADCgYICQAAAA==.',
Kh='Khurri:BAABNQAECn8WAAImAAkKQB30BwDcAgAmAAkKQB30BwDcAgAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAABNQAECn8hAAIMAAoKgxmBHgBxAgAMAAoKgxmBHgBxAgAAAA==.Kisor:BAAANQADCgQIBwAAAA==.Kitchenstink:BAABNQAECn8WAAIgAAkKHBGBigABAgAgAAkKHBGBigABAgAAAA==.',
Ko='Koifo:BAAANQABCgUIBgAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggIEAAAAA==.',
Kr='Kritanta:BAABNQAECn8cAAIDAAcKGRLzWACPAQADAAcKGRLzWACPAQAAAA==.Krystallus:BAAANQAECgUIEQAAAA==.',
Ku='Kurnea:BAAANQAECggIEwAAAA==.',
['Kó']='Kórrá:BAAANQAECgIIAwAAAA==.',
La='Lachlann:BAABNQAECn8bAAIKAAcKcw/9WgAuAQAKAAcKcw/9WgAuAQAAAA==.Ladriel:BAAANQADCgcIBwABNQAECgoKHwAUADQYAA==.Lakartó:BAACNQAFFH8HAAIcAAMKrBICBACFAAAcAAMKrBICBACFAAA1AAQKfzUABBwACgqPHM8KAL4CABwACgpNG88KAL4CABIABgqUG+wKALkBACQAAQpYHzRKAFMAAAAA.Laleaf:BAAANQABCggIEAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgUICgABNQAECgYIBgABAAAAAA==.',
Ld='Ldritch:BAACNQAFFH8XAAMEAAYKgCCgAwChAQAEAAYK6x2gAwChAQAFAAQKUSGTCQBsAQA1AAQKfy4ABAQACgpFJAAGACIDAAQACgpFJAAGACIDAAUABgpiIek8ANwBAA0AAQo/GeIZAEUAAAAA.',
Le='Leifson:BAAANQAECgUIBwAAAA==.Leonedis:BAABNQAECn8hAAIgAAcKZgl+kQDrAAAgAAcKZgl+kQDrAAAAAA==.Lethea:BAAANQADCgYICgAAAA==.Levious:BAABNQAECn8cAAIHAAkK6xlIZQBrAgAHAAkK6xlIZQBrAgAAAA==.',
Li='Lianara:BAAANQADCgQICwABNQAECgUICwABAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lokren:BAAANQAECgQIBwAAAA==.Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAACNQAFFH8QAAIYAAUK5h+hAQAGAQAYAAUK5h+hAQAGAQA1AAQKfzsAAhgACgqkID0GACIDABgACgqkID0GACIDAAAA.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECn8uAAMbAAoKVBhlEwBGAgAbAAoKVBhlEwBGAgAZAAcKWAuBIAAiAQAAAA==.Luxurious:BAABNQAECn8fAAIjAAgKjQbGDgDlAAAjAAgKjQbGDgDlAAAAAA==.',
Ma='Maaca:BAAANQAECgIIAgAAAA==.Madeofhide:BAAANQADCgMIAwAAAA==.Maecarepicha:BAAANQAECgUIDQAAAA==.Magicmoose:BAAANQAECgQIBgAAAA==.Malachor:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.Maligned:BAAANQAECgcIEQAAAA==.Martichoux:BAABNQAECn8WAAIWAAkK9ReChgBxAgAWAAkK9ReChgBxAgAAAA==.Mastakronik:BAAANQABCgMIBAAAAA==.Match:BAAANQAECgMIAwAAAA==.Mathas:BAABNQAECn87AAQIAAoKQB5ADgBYAwAIAAoKQB5ADgBYAwARAAQKZRBUJADcAAAHAAIKeAfXhgFQAAAAAA==.Mathilda:BAAANQAECgMIBAAAAA==.',
Mc='Mccholock:BAABNQAECn8ZAAMiAAYKzRIjEwBvAQAiAAYKzRIjEwBvAQAgAAUKfQbIzAB0AAAAAA==.Mcmach:BAABNQAECn8WAAInAAcK3gsCAgBmAQAnAAcK3gsCAgBmAQAAAA==.',
Me='Meddox:BAEANQABCggIFgAAAA==.Mehaoloka:BAAANQADCgcIEAAAAA==.Memelle:BAABNQAECn8ZAAIhAAYKNBUmEwB1AQAhAAYKNBUmEwB1AQAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAABNQAECn8bAAMTAAcKJhGBHwANAQATAAcKJhGBHwANAQAUAAIKtQQBcQBCAAAAAA==.Menotthatorc:BAAANQAECgIIAgABNQAFFAQICgAfAL8UAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAABNQAECn8eAAMOAAgKMx/9FQC1AgAOAAgKMx/9FQC1AgAPAAEKAAD/hwAiAAAAAA==.Mesilana:BAAANQAECgMIAwAAAA==.Metrx:BAAANQAECgUIBAAAAA==.',
Mi='Mikosen:BAAANQAECgUICAAAAA==.Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAABNQAECn8hAAIOAAgKDhdYOwDIAQAOAAgKDhdYOwDIAQAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.Mithian:BAAANQADCgMJAwABNQADCggIBgABAAAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgUICQAAAA==.Monichan:BAAANQAECgMIAwAAAA==.Moosecheeks:BAABNQAECn8cAAITAAkKXRkJEwAzAgATAAkKXRkJEwAzAgAAAA==.Morganna:BAAANQAECggIBwAAAA==.Morior:BAABNQAECn8dAAIeAAcKdw3gBwD0AAAeAAcKdw3gBwD0AAAAAA==.Morslucifer:BAABNQAECn8aAAMoAAgKvBiKBQBoAgAoAAgKvBiKBQBoAgAeAAEKehPDcgA8AAAAAA==.Motorcade:BAABNQAECn8lAAIaAAkKSQNSDgDaAAAaAAkKSQNSDgDaAAAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQAECgYICAAAAA==.',
My='Mypal:BAABNQAECn8aAAIHAAcKfgb+xADUAAAHAAcKfgb+xADUAAAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
['Mû']='Mûrasaki:BAAANQABCgQIBwAAAA==.',
Na='Naula:BAAANQAECgQIBQAAAA==.',
Ne='Neather:BAABNQAECn8dAAIhAAkKVxeVCgAfAgAhAAkKVxeVCgAfAgAAAA==.Neron:BAAANQADCgUIDQAAAA==.Nexeon:BAAANQAECgUIBQABNQAECgoKHgACAPkaAA==.Nezkima:BAAANQAECgUIBQABNQAECgoKPQAKAFwgAA==.',
Ni='Nidivh:BAAANQAECgQIDAAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAABNQAECn8WAAIHAAYKgA8u4wBVAQAHAAYKgA8u4wBVAQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAwAAAA==.Nira:BAABNQAECn8nAAIOAAoKMRiTQgBiAgAOAAoKMRiTQgBiAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAABNQAECn8UAAImAAcK/xJuEgDXAQAmAAcK/xJuEgDXAQAAAA==.',
No='Nodöts:BAAANQAECggICAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Nonetoo:BAAANQAECggICQAAAA==.Notdeadyet:BAABNQAECn8UAAIMAAYK8Qex2ABPAQAMAAYK8Qex2ABPAQAAAA==.Notron:BAABNQAECn8ZAAIXAAkKehhmJwBjAgAXAAkKehhmJwBjAgAAAA==.Noz:BAAANQADCggIFQAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQAECgMIBAAAAA==.Nychophysis:BAABNQAECn8bAAMFAAcK6AyxLwCwAAAFAAYKywyxLwCwAAAEAAIKVArBfQB3AAAAAA==.Nyxion:BAAANQADCggICgABNQAECgQIBQABAAAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oakarm:BAAANQAECggICAAAAA==.Oasis:BAAANQAECgcICAAAAA==.',
Od='Odyssius:BAAANQAECggIAQAAAA==.',
Og='Ogbamz:BAAANQADCgQIBAAAAA==.Ogden:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Om='Omars:BAAANQAECgYICAAAAA==.',
On='Ontherun:BAAANQAECgUIBwAAAA==.',
Op='Oprawinfury:BAAANQAECgUICwAAAA==.',
Or='Orgazmik:BAAANQADCgYIBgAAAA==.Orphani:BAAANQABCgMIAQAAAA==.',
Ou='Ourus:BAABNQAECn9CAAIdAAoKXiI4AwBvAwAdAAoKXiI4AwBvAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Panax:BAAANQAECgUICwAAAA==.Paulo:BAABNQAECn8bAAIHAAYKAgqF8gA3AQAHAAYKAgqF8gA3AQAAAA==.',
Pe='Pele:BAAANQAECgUIDQAAAA==.Pellito:BAAANQADCgQICAAAAA==.Perpetrator:BAABNQAECn8lAAIDAAgKwwQAOwD2AAADAAgKwwQAOwD2AAAAAA==.',
Pi='Piki:BAABNQAECn8mAAIKAAoK5AopTABkAQAKAAoK5AopTABkAQAAAA==.',
Po='Poepwn:BAABNQAECn8pAAQbAAcKIw2UKwARAQAbAAcKIw2UKwARAQAaAAYK+wauEQCnAAAZAAEKAACQdwAgAAAAAA==.',
Pr='Pray:BAABNQAECn8YAAIOAAkKeRxdEwDMAgAOAAkKeRxdEwDMAgABNQAECgEIAQABAAAAAA==.Prescient:BAAANQAECggIDgAAAA==.',
Pu='Puffypanda:BAAANQAECgUICwAAAA==.Putnamehere:BAAANQABCgcICQAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quadeshboy:BAAANQAECgIIAwAAAA==.Quill:BAAANQAECggIEwAAAA==.',
Ra='Raging:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Ralz:BAABNQAECn8aAAICAAYK3RT7UABvAQACAAYK3RT7UABvAQAAAA==.Rangon:BAAANQADCggIDwAAAA==.Rannick:BAABNQAECn8dAAMYAAcKGQwwFgAnAQAYAAcKGQwwFgAnAQAKAAEK9QYKJQEoAAAAAA==.Ranua:BAAANQAECgUICQABNQAECgoKKwAOAJwfAA==.Ratdemonmike:BAABNQAECn8WAAIjAAYKVR+uDAD6AQAjAAYKVR+uDAD6AQAAAA==.Rate:BAABNQAECn8UAAIXAAcKcRTUKwA/AQAXAAcKcRTUKwA/AQABNQAECgoKLQAGAM8YAA==.Ratio:BAABNQAECn8tAAIGAAoKzxjWCwA0AgAGAAoKzxjWCwA0AgAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAABNQAECn8VAAMfAAoK5BgOHQBQAgAfAAoK5BgOHQBQAgAeAAEKSg9WKQA2AAAAAA==.',
Ri='Richard:BAAANQAECgMIAwAAAA==.Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgYIDwABNQAECgcICQABAAAAAA==.',
Ru='Ruden:BAAANQAECgQICQAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECggIDQABNQAECgoKMQAYALUeAA==.',
Rw='Rwqr:BAABNQAECn84AAIXAAkKHAvpQAC4AQAXAAkKHAvpQAC4AQAAAA==.',
['Rä']='Räiden:BAABNQAECn8eAAMhAAkKwA1aCwBSAQAhAAgK5A5aCwBSAQAWAAYKsAccOAEvAQAAAA==.',
Sa='Salacake:BAAANQAECgQIBAAAAA==.Salacakei:BAABNQAECn82AAMFAAkK0RLHDwCKAQAFAAgKbxLHDwCKAQAEAAcKMBDzVwD8AAAAAA==.Salin:BAAANQAECggIDwAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFH8eAAIRAAcKyh7VAAClAgARAAcKyh7VAAClAgA1AAQKfyoAAhEACgocJpQFAFYDABEACgocJpQFAFYDAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scaley:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Scarletpaw:BAAANQAECgEIAQAAAA==.Scoobie:BAAANQAECgEIAQABNQAECgkJNwAMAEofAA==.Scoobydo:BAAANQAECgUICwABNQAECgkJNwAMAEofAA==.Scratches:BAAANQAECgIIBAAAAA==.Scrubs:BAACNQAFFH8GAAIMAAQK3gPlGgDjAAAMAAQK3gPlGgDjAAA1AAQKfz4AAgwACgoAGkYiAF4CAAwACgoAGkYiAF4CAAAA.',
Se='Seider:BAAANQAECggIBgAAAA==.Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadhunter:BAAANQABCgQIAgAAAA==.Shadpriest:BAAANQABCgIIAgABNQABCgQIAgABAAAAAA==.Shaggzy:BAACNQAFFH8YAAIZAAcK1BdSAwA1AgAZAAcK1BdSAwA1AgA1AAQKfzwAAhkACgruIy0DABwDABkACgruIy0DABwDAAAA.Shallabal:BAAANQAECggICAAAAA==.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAABNQAECn8iAAMlAAgKfw/NHAAZAQAMAAcKPRAotgCYAQAlAAcKEg7NHAAZAQAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAABNQAECn8VAAImAAYKrQ6oGwBJAQAmAAYKrQ6oGwBJAQAAAA==.Shockdoctor:BAABNQAECn8lAAMKAAoK/SIZBgBsAwAKAAoK/SIZBgBsAwALAAMKTxR2+QCgAAAAAA==.Shortrange:BAAANQADCgEIAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJKwAIACokAA==.',
Si='Sintotem:BAAANQAECgMIAwAAAA==.',
Sl='Sleples:BAABNQAECn83AAIMAAkKSh8eKgDwAgAMAAkKSh8eKgDwAgAAAA==.Slufgor:BAAANQAECgQICwAAAA==.Slyxxii:BAAANQAECgQIBAAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCggIFQAAAA==.',
Sn='Sniperbeko:BAAANQAECgEIAQABNQAECgoKLQAWAKkbAA==.Snoo:BAAANQAECgQICwAAAA==.',
So='Solarlite:BAAANQAECgQIBQAAAA==.Solinari:BAAANQABCgIIBAAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAABNQAECn8aAAMOAAkKqCMVCQB7AwAOAAkKqCMVCQB7AwAQAAIK8CTpFQDNAAAAAA==.Soulbreakër:BAABNQAECn8wAAICAAkKcAw6SQCXAQACAAkKcAw6SQCXAQAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYIDQAAAA==.Sparks:BAAANQAECgMIBAABNQAECgoKGQAVAH4UAA==.Specimen:BAAANQADCggJEgAAAA==.Speddling:BAABNQAECn8dAAIWAAkKuw8OfABKAQAWAAkKuw8OfABKAQABNQAECgoKGQAVAH4UAA==.Spellgennce:BAAANQAECgQIBAAAAA==.Spicey:BAAANQADCgYIDAABNQAECgoKNgAMAOcgAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQAECgMIBwAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAAANQAECgcIEgAAAA==.',
Sr='Srbranchmgr:BAAANQADCgMIBAAAAA==.',
St='Starbrow:BAABNQAECn8ZAAIMAAgKuiExTACJAgAMAAgKuiExTACJAgAAAA==.Starrybeko:BAAANQABCgYIBgABNQAECgoKLQAWAKkbAA==.Sticky:BAAANQABCgIIAgAAAA==.Stilez:BAAANQAECggIBwABNQAECggIEAABAAAAAA==.Stormlight:BAAANQAECgcIEwAAAA==.Strudelmaker:BAAANQAECgMIAwABNQAECgkJJwAXAKcaAA==.',
Su='Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAAANQAECgUIDAAAAA==.',
Sy='Syland:BAABNQAECn8VAAIMAAYKggpYzwBiAQAMAAYKggpYzwBiAQAAAA==.Sylvanäs:BAABNQAECn8XAAIMAAUK5Apm8gAdAQAMAAUK5Apm8gAdAQAAAA==.Syrellina:BAAANQAECgQIBAABNQAECgoKKwAOAJwfAA==.Sysna:BAABNQAECn80AAMPAAoK1yJ9BQDNAgAPAAoK1yJ9BQDNAgAOAAcKRCAbQwBfAgAAAA==.',
Ta='Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECn8fAAIKAAcKXBTKbgC/AQAKAAcKXBTKbgC/AQAAAA==.Tankwar:BAAANQADCgYIFwAAAA==.Targis:BAABNQAECn8hAAIgAAgKDw+DpADBAQAgAAgKDw+DpADBAQAAAA==.Tauran:BAAANQADCgcIDwAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECgoKKwAOAJwfAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Tergar:BAAANQAECgIIAgAAAA==.Teâfâ:BAAANQADCgQIAgAAAA==.',
Th='Thaleas:BAABNQAECn8iAAQIAAoKoQ79SQBuAQAIAAkKjgz9SQBuAQARAAYKyhMEGwAkAQAHAAMKxAspEQFqAAAAAA==.Thegreatkhal:BAABNQAECn8XAAIPAAcKJRqVKQDbAQAPAAcKJRqVKQDbAQAAAA==.Therizino:BAAANQADCgEIAQAAAA==.Thorizine:BAAANQAECgcIEAAAAA==.Thorlas:BAABNQAECn8oAAMKAAgK4hy1JwASAgAKAAgK4hy1JwASAgALAAMKCxet7wC3AAAAAA==.Thornado:BAAANQADCgMIAwAAAA==.Thotsfortots:BAAANQAECggICAABNQAECgoKIQAVAF4bAA==.Thylacoleo:BAAANQADCgUIBQAAAA==.',
Ti='Timmúk:BAABNQAECn8nAAIXAAkKpxp9KwBHAgAXAAkKpxp9KwBHAgAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAABAAAAAA==.Tomma:BAAANQAECggIDgAAAA==.Torment:BAAANQAECgYIBAABNQAECgEIAQABAAAAAA==.Torsion:BAABNQAECn8bAAILAAgKlRrYPACCAgALAAgKlRrYPACCAgAAAA==.',
Tr='Trailerpark:BAAANQADCgMJAwAAAA==.Tratre:BAABNQAECn8jAAMcAAgKzB3vDwBaAgAcAAgKzB3vDwBaAgAkAAQKMg/XIgCCAAAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQAECgUIDQAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAcIEAAXAOoZAA==.Turd:BAAANQADCgcIBwAAAA==.Tust:BAAANQAECgUICgABNQAECgQIBQABAAAAAA==.',
Ty='Tylandy:BAABNQAECn8zAAIWAAoKoiJaGgBsAwAWAAoKoiJaGgBsAwAAAA==.Tytaniormu:BAAANQAECgYIBwAAAA==.',
['Tê']='Tês:BAAANQAECgUICwAAAA==.',
Un='Undeadbetty:BAAANQADCgcICAAAAA==.Undeathtwoy:BAAANQAECgUIBwAAAA==.',
Va='Vaayl:BAABNQAECn8bAAIYAAgKzh9vCgABAgAYAAgKzh9vCgABAgAAAA==.Vaelraen:BAAANQAECgUICgAAAA==.Valcher:BAABNQAECn8aAAMVAAcKIgXVRQCtAAAVAAcKIgXVRQCtAAAUAAEK4wNkgAAfAAAAAA==.Valendera:BAABNQAECn8WAAIfAAkKRAkdlAC0AQAfAAkKRAkdlAC0AQAAAA==.Valerius:BAAANQAECgcICgAAAA==.Valguero:BAAANQADCggICwAAAA==.Valifadin:BAABNQAECn8fAAIpAAgKsx54AwDuAQApAAgKsx54AwDuAQAAAA==.Valndrevy:BAAANQADCggIGwAAAA==.Vamire:BAAANQAECggIEAAAAA==.Vanpèlt:BAAANQADCgYIEwAAAA==.Vansan:BAABNQAECn8rAAQOAAoKnB8jIADvAgAOAAoKNR8jIADvAgAQAAEKKSD7DABeAAAPAAIKwBC6RgA4AAAAAA==.',
Ve='Venngennce:BAABNQAECn83AAICAAoKeh+zFQDeAgACAAoKeh+zFQDeAgAAAA==.Verran:BAAANQAECgEIAQAAAA==.',
Vi='Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Voladen:BAAANQAECgEIAQAAAA==.Vorkath:BAABNQAECn8uAAMcAAoKmSKiBQA2AwAcAAoKmSKiBQA2AwAkAAQKOwqgOQDJAAAAAA==.Vormette:BAAANQADCggIGQAAAA==.',
Vt='Vtae:BAABNQAECn8UAAIMAAYKjQZi3QBGAQAMAAYKjQZi3QBGAQAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAABNQAECn8vAAIUAAgKshImGACxAQAUAAgKshImGACxAQAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Wo='Woxkal:BAABNQAECn8iAAQJAAgK+AfYMAAEAQACAAcK1wXlYQAdAQAJAAcKEQbYMAAEAQADAAMKegcdrwBtAAAAAA==.',
Wu='Wubblebubble:BAAANQAECggIDwAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgUIDwAAAA==.',
Xu='Xuzhu:BAABNQAECn8iAAIWAAoKeRe9TgDCAQAWAAoKeRe9TgDCAQAAAA==.',
Ye='Yelignar:BAAANQABCgEIAQAAAA==.',
Yi='Yinei:BAAANQAFFAIIAgAAAA==.',
Yl='Ylvis:BAABNQAECn8bAAIMAAgKbhV+eAAeAgAMAAgKbhV+eAAeAgAAAA==.',
Yo='Yol:BAABNQAECn8aAAISAAkKngxjCgDKAQASAAkKngxjCgDKAQAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECggIJAAAAQ==.',
Yu='Yukikaze:BAAANQABCgQIBAAAAA==.',
Yv='Yvetal:BAAANQAECgUIDAABNQAFFAQICgAfAL8UAA==.',
Za='Zapdos:BAAANQADCggICAAAAA==.Zarion:BAACNQAFFH8TAAIUAAUKrSEbBQDNAQAUAAUKrSEbBQDNAQA1AAQKfyoAAxQACgrvIv0EAHMDABQACgrvIv0EAHMDABUAAQoAANvDAB4AAAAA.Zarra:BAAANQAECgQIBgAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQIBAAAAA==.Zetterberg:BAAANQAECggIAQAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQAECgMIBAABNQAFFAUIEwAUAK0hAA==.Ziyar:BAAANQAECgMIBwABNQAFFAUIEwAUAK0hAA==.',
Zo='Zocorro:BAAANQAECgUICwAAAA==.',
Zr='Zra:BAAANQADCgEIAQAAAA==.',
Zy='Zypherdius:BAAANQAECgQIBQAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFH8aAAIHAAYKyRdfCwCTAQAHAAYKyRdfCwCTAQA1AAQKfzoAAgcACgpRJWgkAHQCAAcACgpRJWgkAHQCAAAA.',
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
