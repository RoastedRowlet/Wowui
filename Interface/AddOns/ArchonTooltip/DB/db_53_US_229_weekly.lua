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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection','Evoker-Augmentation','Druid-Guardian','Druid-Restoration','Druid-Balance','Mage-Arcane','DemonHunter-Havoc','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Evoker-Devastation','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Druid-Feral','Mage-Frost','Warrior-Fury','DemonHunter-Vengeance','Evoker-Preservation','Hunter-Marksmanship','Mage-Fire','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaralyn:BAAANQAECgYICAAAAA==.',
Ab='Abmikaze:BAAANQAECggIEAAAAA==.Absolon:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.Abysseon:BAABNQAECn8eAAMCAAoK+Ro4MAAkAgACAAoK+Ro4MAAkAgADAAMK2w2IqgB7AAAAAA==.',
Ac='Ace:BAABNQAECn8sAAMEAAoKWyGOHwBhAgAEAAkKtR+OHwBhAgAFAAMKNiK0bwDyAAABNQAECgEIAQABAAAAAA==.',
Ad='Adios:BAACNQAFFH8RAAIGAAYKDA9jBQDbAQAGAAYKDA9jBQDbAQA1AAQKf0AAAgYACgrGIgAKADkDAAYACgrGIgAKADkDAAAA.Adorean:BAABNQAECn8gAAIHAAoKMhCZoADgAQAHAAoKMhCZoADgAQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgQIEQAAAA==.Agrohn:BAABNQAECn8YAAMHAAcKQxSRuQCqAQAHAAcKQxSRuQCqAQAIAAEKrgKUNAEjAAAAAA==.',
Ai='Aimnskin:BAAANQAECgIIAgAAAA==.',
Al='Alcore:BAABNQAECn8uAAQDAAoK/B5QIACxAgADAAcK2yFQIACxAgACAAkKsRtAGQBPAgAJAAYKaByeTADiAQAAAA==.Aliine:BAABNQAECn8mAAIDAAgKYQ51RAADAQADAAgKYQ51RAADAQAAAA==.',
Am='Ameiisaa:BAABNQAECn8gAAMKAAgKJgV/jQDdAAAKAAcKsgJ/jQDdAAALAAUK3wQP6QDFAAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAACNQAFFH8MAAILAAUKkBMkFQAmAQALAAUKkBMkFQAmAQA1AAQKf1UAAgsACgp7IoYRAMICAAsACgp7IoYRAMICAAAA.',
An='Anxie:BAABNQAECn8mAAIMAAoKGwbkuQD6AAAMAAoKGwbkuQD6AAAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAcIEwANAEYZAA==.',
Ao='Aoifae:BAABNQAECn8VAAIHAAYKQRLAywCEAQAHAAYKQRLAywCEAQAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECn8ZAAQOAAkKnAk3gQCUAQAOAAgKGgo3gQCUAQAPAAcKewY1QAAtAQAQAAEKMAVqLwAmAAAAAA==.Apprentice:BAABNQAECn8rAAIRAAkKPgPUMQDCAAARAAkKPgPUMQDCAAAAAA==.',
Ar='Aramos:BAABNQAECn8rAAIIAAgKqhqNPQBuAgAIAAgKqhqNPQBuAgAAAA==.Aramôs:BAAANQAECgYIEAAAAA==.Aristania:BAAANQAECgIIAgAAAA==.Arkhangel:BAABNQAECn8ZAAIHAAgKJBiNeAA7AgAHAAgKJBiNeAA7AgAAAA==.Arta:BAAANQAECgUIEQAAAA==.Artavian:BAAANQABCgIIAwAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAABNQAECn8sAAIOAAgKIhDsfwCZAQAOAAgKIhDsfwCZAQAAAA==.Assiam:BAAANQADCgIIAgAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Ay='Ayame:BAAANQABCgMIBQAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECgoKOAADAP4XAA==.',
Ba='Badflood:BAAANQABCgQIBAAAAA==.Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQAECgQIDwAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.Basicampfire:BAAANQAECgcICAABNQAECggIHwASAM8IAA==.Bautumn:BAAANQAECgEIAQAAAA==.',
Be='Beaker:BAABNQAECn8tAAITAAoKShwACwBaAgATAAoKShwACwBaAgAAAA==.Beastmode:BAABNQAECn9EAAMUAAoKuRiSFwANAgAUAAoKuRiSFwANAgAVAAgKsRUNLABoAQAAAA==.Bedlem:BAAANQAECggIDwAAAA==.Beko:BAABNQAECn8yAAIWAAoKrhzwQwD8AgAWAAoKrhzwQwD8AgAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBgAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgMIBwAAAA==.Billydan:BAABNQAECn8rAAIXAAoK9w2jJACpAQAXAAoK9w2jJACpAQAAAA==.',
Bl='Blackhide:BAAANQABCgUIBgAAAA==.Blackpanthxr:BAABNQAECn84AAQKAAoK+xQwRwBFAgAKAAoK+xQwRwBFAgAYAAcKghHWGQDHAQALAAcKfAdXrgA2AQAAAA==.Blackvortex:BAAANQAECgQIBAAAAA==.Bloodgoat:BAAANQADCggICwAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECgkJHgAZAFkjAA==.Bloodyburst:BAABNQAECn8aAAMNAAgK2CKlBQCMAgANAAcKEyOlBQCMAgAFAAIKDBywggCpAAABNQAECgkJHgAZAFkjAA==.Bloodyfistz:BAABNQAECn8eAAMZAAkKWSNhDgD5AgAZAAkKRCNhDgD5AgAaAAIKMyOyIgDDAAAAAA==.Blue:BAABNQAECn8qAAILAAoKwhw/KwDTAgALAAoKwhw/KwDTAgAAAA==.Bluethreetwo:BAAANQAECgQICAAAAA==.',
Bo='Bookofzeref:BAAANQAECgcIBwAAAA==.Boost:BAAANQABCgIIBAAAAA==.',
Br='Brayend:BAABNQAECn8lAAIYAAoKug38DgDqAQAYAAoKug38DgDqAQAAAA==.Brewguts:BAABNQAECn8cAAIbAAkK5xrnCgBTAgAbAAkK5xrnCgBTAgAAAA==.Brimscythe:BAABNQAECn88AAIcAAoKzR1CBABtAgAcAAoKzR1CBABtAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggIDgAAAA==.Caliandis:BAABNQAECn8eAAIdAAcKEA+DHQDaAAAdAAcKEA+DHQDaAAAAAA==.Calvey:BAAANQAECgYIDgAAAA==.Cambrai:BAAANQAECgYIEAAAAA==.Cannabelle:BAABNQAECn8qAAIMAAkK8CFBHgAeAwAMAAkK8CFBHgAeAwAAAA==.Carclias:BAACNQAFFH8IAAMeAAQKvwxjBgCDAAAeAAIKBwpjBgCDAAAfAAIKLhKaLQBOAAA1AAQKf1AAAx4ACgoDHU8NACQCAB4ACQpsGE8NACQCAB8ACQoRGGNOALEBAAAA.Carthrix:BAABNQAECn8fAAMgAAkK1AvHZwCQAQAgAAkK1AvHZwCQAQAdAAEKAgJeQQAfAAAAAA==.Catbarf:BAAANQAECgYIAQABNQAECgoKMQAYALUeAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAABNQAECn8UAAIMAAcKThHcqwAWAQAMAAcKThHcqwAWAQAAAA==.',
Ce='Celery:BAABNQAECn8VAAMTAAcKMSNqCwBSAgATAAcKMSNqCwBSAgAhAAUKngnaHgDEAAABNQAFFAcIHAADAC4WAA==.Cellika:BAAANQAECgYIDwAAAA==.Cerdelz:BAAANQAECgQIBAAAAA==.',
Ch='Chanclatotem:BAAANQADCgIIAgAAAA==.Chaoscookies:BAABNQAECn9DAAMeAAoKNhYeEwDaAQAeAAcKsxYeEwDaAQAfAAgKMRH2bABXAQAAAA==.Chaotik:BAAANQABCgIIAgAAAA==.Chartkov:BAAANQAECgUIDQAAAA==.Cheezee:BAACNQAFFH8TAAMWAAcKLhB9EADzAQAWAAYKzhN9EADzAQAiAAEKrwHVEQBLAAA1AAQKfxYAAhYACQqFIdASAOwCABYACQqFIdASAOwCAAAA.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQADCggIFgAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECgkJFgALADgWAA==.',
Ci='Cinderpetal:BAAANQAECgQICAAAAA==.',
Ck='Ckay:BAAANQAECggIDwAAAA==.',
Cl='Clawsome:BAAANQADCggIEwAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAACNQAFFH8GAAMDAAIKSA/JIwBvAAACAAIK9wmUFwCEAAADAAIKSA/JIwBvAAA1AAQKfyIABAIACgq3Gi8hAIQCAAIACQrRGC8hAIQCAAkABwoFFf5gAIwBAAMABApXFTaIAN4AAAE1AAUUBAgMAB4AvxQA.Comlock:BAAANQADCgcIEwAAAA==.Complacent:BAABNQAECn81AAITAAoKsgQ2LgDlAAATAAoKsgQ2LgDlAAAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgIIBAAAAA==.Coriander:BAABNQAECn8YAAISAAkKlBJQCAAUAgASAAkKlBJQCAAUAgAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAABNQAECn8aAAMVAAoKfhRgQgDtAQAVAAkKRhVgQgDtAQAUAAQKtRH0PQDVAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAcIGQAZANQXAA==.',
Cy='Cynical:BAAANQAECgIIAwABNQAECgEIAQABAAAAAA==.Cyonicus:BAABNQAECn8fAAIfAAoKMRkRXABDAgAfAAoKMRkRXABDAgAAAA==.Cyska:BAABNQAECn84AAIDAAoK/heUJwCDAgADAAoK/heUJwCDAgAAAA==.',
['Cé']='Cécé:BAABNQAECn8qAAIHAAkKDBkwaQBgAgAHAAkKDBkwaQBgAgAAAA==.',
['Cë']='Cëcë:BAAANQAECgMIAwAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAABNQAECn9RAAMOAAoKvRYHIwCYAgAOAAoKvRYHIwCYAgAPAAEKYAVvWAAvAAAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagaurie:BAAANQAECggICAABNQAECgoKIgAVAF4bAA==.Dagerlaurn:BAABNQAECn8iAAMVAAoKXhvDKACQAgAVAAoKXhvDKACQAgAUAAUKkhhmOgBMAQAAAA==.Dagevas:BAAANQAECgUIBQAAAA==.Dakeria:BAAANQADCgcIIQAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEAAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECn9EAAIjAAoKOBlTCADgAQAjAAoKOBlTCADgAQABNQAFFAUIDQAHACUcAA==.Davriell:BAABNQAECn8rAAICAAoKBw+wJwDgAQACAAoKBw+wJwDgAQAAAA==.Dax:BAABNQAECn8iAAIMAAcKqwx2ngAxAQAMAAcKqwx2ngAxAQAAAA==.Daxing:BAAANQADCggIFAABNQAECgoKLAAOAGMhAA==.',
De='Deeppurple:BAAANQAECgUIEwAAAA==.Del:BAABNQAECn8wAAIkAAoKXSbBAQAIAwAkAAoKXSbBAQAIAwABNQAECgoKMAAbAAIZAA==.Demoniaca:BAAANQAECgUIBAAAAA==.Demonic:BAAANQAECgUICwABNQAECgEIAQABAAAAAA==.Demonshady:BAAANQABCggIFAAAAA==.Demoraliziñg:BAAANQADCggIDgABNQAECgkJKAAXAKcaAA==.Demostache:BAACNQAFFH8MAAMeAAQKvxR7BgCCAAAfAAMK8xlOGgCqAAAeAAIKWQp7BgCCAAA1AAQKfzcAAx8ACgr6IzUuAM0CAB8ACQqwIzUuAM0CAB4AAwqXEtEYAHwAAAAA.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECn8xAAILAAoKPSFOJgDqAgALAAoKPSFOJgDqAgAAAA==.',
Di='Diivision:BAAANQAECgQIBgABNQAECgoKNAAGAN8YAA==.',
Do='Dolomite:BAABNQAECn8XAAIWAAgKUgVrGQFhAQAWAAgKUgVrGQFhAQAAAA==.Dorow:BAABNQAECn8yAAMVAAoKnBi8JQClAgAVAAoKnBi8JQClAgAUAAYKiBSoMQAeAQABNQAECgkJJAAZAIIXAA==.Dotabolt:BAABNQAECn8VAAIfAAcKyw+4nACeAQAfAAcKyw+4nACeAQABNQAECgoKJAAiAJwbAA==.',
Dr='Dracthyris:BAABNQAECn8tAAIlAAkKXAwQEwCHAQAlAAkKXAwQEwCHAQAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Dreaa:BAAANQAECgEIAgAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECn8xAAIYAAoKtR58BwAGAwAYAAoKtR58BwAGAwAAAA==.',
Du='Dunsel:BAABNQAECn8aAAIIAAcK7wyvbgA3AQAIAAcK7wyvbgA3AQABNQAECgoKPAAcAM0dAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgYICQAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECn9BAAMgAAoKyxR5RAAEAgAgAAoKyxR5RAAEAgAdAAIK/QnjPABRAAAAAA==.',
['Dã']='Dãnny:BAAANQADCggIDQABNQAECgoKQQAgAMsUAA==.',
Ea='Earendil:BAAANQAECggICAAAAA==.',
Eb='Ebonshade:BAAANQAECgQIBQAAAA==.',
Ed='Edena:BAAANQAECgQIBAAAAA==.Edginglord:BAABNQAECn8WAAIGAAgKGQTtMQDVAAAGAAgKGQTtMQDVAAAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQAAAA==.Eloras:BAABNQAECn8ZAAILAAkK8xwEIABEAgALAAkK8xwEIABEAgAAAA==.Elunbi:BAABNQAECn9DAAMOAAoK1xzZHgD1AgAOAAoKRhzZHgD1AgAQAAYKkhSZDQBZAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQAECgQIBQAAAA==.',
Ep='Epsilòn:BAEBNQAECn8YAAMfAAkKtwrczwAqAQAfAAYKrxLczwAqAQAeAAgKFwAMiAAdAAAAAA==.',
Er='Ernest:BAABNQAECn8XAAIRAAcKABmHIwAeAQARAAcKABmHIwAeAQAAAA==.Errani:BAABNQAECn8nAAMiAAcKqxAdEQCVAQAiAAcKqxAdEQCVAQAWAAIKHQQzTwEpAAAAAA==.',
Es='Esheman:BAAANQAECgYIBQAAAA==.Esper:BAAANQAECgcIDQAAAA==.Esterlia:BAAANQAECgMIAwABNQAECgoKLAAOAGMhAA==.',
Et='Eternal:BAAANQAECgEIAQAAAA==.',
Eu='Eureki:BAABNQAECn8dAAIXAAkK4QjhNAA5AQAXAAkK4QjhNAA5AQAAAA==.',
Ev='Evilkarma:BAAANQAECggIEgAAAA==.Evocatis:BAACNQAFFH8NAAIHAAYKDRbhDwBOAQAHAAYKDRbhDwBOAQA1AAQKf0IABAcACgr3JE8JAEMDAAcACgr3JE8JAEMDAAgABApTDRvNAOEAABEAAQpgFzFVADkAAAAA.',
Ex='Exilion:BAAANQAECgUIBwAAAA==.',
Ey='Eyekonicklok:BAAANQAECgYICwABNQAECgQIBAABAAAAAA==.Eyesdeadeyed:BAACNQAFFH8IAAImAAQKwAs7DwCrAAAmAAQKwAs7DwCrAAA1AAQKfzIAAyYACgqMFoImABgCACYACgqMFoImABgCAAwAAQpbEEkfAUgAAAAA.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAABNQAECn87AAMHAAoKJR3SRgDAAgAHAAoKJR3SRgDAAgAIAAYKExwLfwCcAQAAAA==.Faon:BAAANQAECgYICQAAAA==.Farrea:BAAANQAECgQIBgABNQAECgUICQABAAAAAA==.Fatlock:BAAANQAECgQICQABNQAECgoKNQAZALkbAA==.Fayvia:BAAANQAECgQIBAAAAA==.',
Fe='Feebz:BAAANQADCgYIBwAAAA==.Feebzykun:BAAANQABCgIIBAAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECggIEAABNQAECgEIAQABAAAAAA==.Firebirdz:BAACNQAFFH8MAAIUAAYKnhLWCQBBAQAUAAYKnhLWCQBBAQA1AAQKfzIAAxQACgr4HSYTALQCABQACgr4HSYTALQCABUABQp3E18/APoAAAAA.Firebirdzx:BAAANQAECgMICAABNQAFFAYIDAAUAJ4SAA==.',
Fl='Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCggIEAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAABNQAECn8/AAIGAAoKARInFgDXAQAGAAoKARInFgDXAQAAAA==.Freshhéals:BAAANQAECgEIAQABNQAFFAYICAANAMEQAA==.Friargark:BAAANQAECgIIAgAAAA==.Frizby:BAAANQAECgQIBgAAAA==.Frostypaw:BAAANQAECgQIBQAAAA==.',
Fu='Fuzzybut:BAABNQAECn8XAAITAAcKbBq5GgDPAQATAAcKbBq5GgDPAQAAAA==.',
Fy='Fyrelord:BAAANQAECgMIAgAAAA==.Fyuna:BAABNQAECn8tAAIKAAoK8Rs1LQCtAgAKAAoK8Rs1LQCtAgAAAA==.',
Ga='Gark:BAAANQAECgUIDQAAAA==.Garkk:BAAANQADCgQJBAAAAA==.Garrumn:BAAANQADCgcIBwABNQAFFAQIDAAeAL8UAA==.Gazzi:BAABNQAECn8WAAITAAkKcg6rHAC9AQATAAkKcg6rHAC9AQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgkJHwAOANseAA==.',
Gi='Giuseppee:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Gióvanna:BAAANQAECgUIEAAAAA==.',
Gl='Glodskegg:BAABNQAECn8WAAIeAAkKlBG9CQBcAgAeAAkKlBG9CQBcAgAAAA==.',
Go='Gobblious:BAAANQADCgYIBgAAAA==.Goldensea:BAAANQAECgQICwAAAA==.Gondra:BAAANQABCgEIAQAAAA==.Gotenk:BAABNQAECn8dAAQhAAkKlCJYCQCzAgAhAAkKlCJYCQCzAgAUAAEK6RkrYABGAAAVAAEK8AzPegA1AAAAAA==.Goyim:BAAANQAECgQIBQAAAA==.',
Gr='Gr:BAAANQADCgcIFAAAAA==.Grissoul:BAAANQAECgYIBgAAAA==.Grody:BAABNQAECn8UAAIfAAYKNQrm0wAiAQAfAAYKNQrm0wAiAQAAAA==.Gryms:BAAANQAECgYICwAAAA==.',
Gu='Guroo:BAABNQAECn8qAAIMAAkKTQxiiABeAQAMAAkKTQxiiABeAQAAAA==.Gutslammer:BAABNQAECn8dAAIIAAoKuhizHACmAgAIAAoKuhizHACmAgAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
['Gí']='Gígí:BAAANQAECgIIBAAAAA==.Gíl:BAAANQAECgQIBAAAAA==.',
Ha='Hagarn:BAACNQAFFH8FAAIHAAIKPQ6wHgCEAAAHAAIKPQ6wHgCEAAA1AAQKfzEAAgcACgrDFC18ADICAAcACgrDFC18ADICAAAA.Halastrin:BAAANQAECgEIAQAAAA==.Halimah:BAAANQAECgQICQAAAA==.Halois:BAAANQADCgYIBgABNQAECgcIHAADABkSAA==.Handjabz:BAAANQAECgIIAgAAAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggIEAAAAA==.Harvestt:BAAANQADCgQIBAAAAA==.Hazan:BAABNQAECn8UAAIgAAkKfBUriAA9AQAgAAkKfBUriAA9AQABNQAECgoKMQAYALUeAA==.',
He='Hexmachine:BAABNQAECn89AAIfAAoKFhdURwB8AgAfAAoKFhdURwB8AgAAAA==.',
Ho='Hollymagic:BAAANQADCggIBgAAAA==.Holmstein:BAAANQADCggICAAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgEIAgAAAA==.',
Hy='Hypertext:BAABNQAECn8ZAAIZAAkKZA/LLACzAQAZAAkKZA/LLACzAQAAAA==.',
Ia='Iamahriman:BAABNQAECn8lAAILAAgKqwgoiwCIAQALAAgKqwgoiwCIAQAAAA==.Iamarawn:BAABNQAECn8gAAIMAAgKSgU7vACLAQAMAAgKSgU7vACLAQAAAA==.Iamvanth:BAAANQAECgEIAQAAAA==.',
Ic='Icecreme:BAAANQABCgYIDgAAAA==.Icegoesbrr:BAAANQADCgEIAQAAAA==.',
Ig='Ignite:BAABNQAECn88AAMWAAoKjSNsFgDYAgAWAAkKQiRsFgDYAgAiAAEKlh4lLABaAAAAAA==.',
Il='Illestria:BAABNQAECn9CAAIHAAoKgRDGcgCqAQAHAAoKgRDGcgCqAQAAAA==.Illumiscotty:BAABNQAECn80AAQWAAoKQyVdDACkAwAWAAoKQyVdDACkAwAiAAMKzR7JHAAIAQAnAAEKIB6JCgBZAAAAAA==.',
Im='Imodium:BAAANQAECgIIAgAAAA==.',
In='Incognonetoo:BAAANQAECggICwAAAA==.Insania:BAABNQAECn8mAAMKAAkK2AUgeQAVAQAKAAgKhwYgeQAVAQALAAYKdwTy1gDmAAAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
It='Itsrubio:BAAANQAECgIIAgAAAA==.',
Iz='Izara:BAAANQADCgYIJAAAAA==.',
Ja='Jab:BAAANQABCgQIBAAAAA==.Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQAECgUICgABNQAECgoKLAAOAGMhAA==.Jastirri:BAAANQAECgUIDAAAAA==.Jayd:BAAANQAECggIAgAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgUIDQAAAA==.Jimothy:BAAANQADCggIJAABNQAECgUIDAABAAAAAA==.Jin:BAAANQAECgQICAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAABNQAECn8WAAMHAAkKaBJIpwDRAQAHAAkKIxBIpwDRAQARAAcKAQ2uOAAnAQAAAA==.',
Ju='Juicez:BAAANQAECgUIEQAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECggIDgAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIEwAAAA==.Katio:BAABNQAECn9DAAMEAAoKeCEFGQCQAgAEAAoKAxwFGQCQAgAFAAUK4yILNgABAgAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAABNQAECn8gAAIgAAcKygZIswDcAAAgAAcKygZIswDcAAAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgQICAAAAA==.Kessandra:BAACNQAFFH8eAAMfAAcKsyIgAQC2AgAfAAcKsyIgAQC2AgAoAAEKAADeCABeAAA1AAQKfy4AAygACgrAJR8CAA8DACgACgpLJB8CAA8DAB8ABgq+I4x8ADEBAAAA.Kexally:BAAANQAECgUIDgAAAA==.Kexkan:BAAANQAECgEIAQABNQAECgUIDgABAAAAAA==.Kexxy:BAAANQADCgMIBQABNQAECgUIDgABAAAAAA==.Kezzia:BAAANQADCgcICgAAAA==.',
Kh='Khurri:BAABNQAECn8WAAIhAAkKQB30BwDcAgAhAAkKQB30BwDcAgAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAABNQAECn8rAAIMAAoKfSGzEADzAgAMAAoKfSGzEADzAgAAAA==.Kisor:BAAANQADCgQIBwAAAA==.Kitchenstink:BAABNQAECn8WAAIgAAkKHBGBigABAgAgAAkKHBGBigABAgAAAA==.',
Ko='Koifo:BAAANQABCgUIBgAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggIEAAAAA==.',
Kr='Kritanta:BAABNQAECn8cAAIDAAcKGRLzWACPAQADAAcKGRLzWACPAQAAAA==.Krystallus:BAABNQAECn8hAAIVAAcKDRDQPAAGAQAVAAcKDRDQPAAGAQAAAA==.',
Ku='Kurnea:BAABNQAECn8hAAIIAAgKLyBMGQC/AgAIAAgKLyBMGQC/AgAAAA==.',
['Kó']='Kórrá:BAAANQAECgIIAwAAAA==.',
La='Lachlann:BAABNQAECn8hAAIKAAgKOxBQXwBoAQAKAAgKOxBQXwBoAQAAAA==.Ladriel:BAAANQADCgcIBwABNQAECgoKHwAUADQYAA==.Lakartó:BAACNQAFFH8IAAIcAAQKrBLhBACDAAAcAAQKrBLhBACDAAA1AAQKfz4ABBwACgqGHc8KAL4CABwACgqQHM8KAL4CABIABgqUG+wKALkBACUAAQpYHzRKAFMAAAAA.Laleaf:BAAANQABCggIEAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgUICgABNQAECgYIBgABAAAAAA==.',
Ld='Ldritch:BAACNQAFFH8XAAMEAAYKgCB8BQCgAQAEAAYK6x18BQCgAQAFAAQKUSGTCQBsAQA1AAQKfzYABAQACgqHJasCAGwDAAQACgqHJasCAGwDAAUABgpiIek8ANwBAA0AAQo/GeIZAEUAAAAA.',
Le='Leifson:BAAANQAECgcICAAAAA==.Leonedis:BAABNQAECn8oAAIgAAgK6Aq5iAA7AQAgAAgK6Aq5iAA7AQAAAA==.Lethea:BAAANQADCgYICgAAAA==.Levious:BAABNQAECn8kAAIHAAoKIBpIZQBrAgAHAAoKIBpIZQBrAgAAAA==.',
Li='Lianara:BAAANQADCgQICwABNQAECgUICwABAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lokren:BAAANQAECgQIBwAAAA==.Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAACNQAFFH8RAAIYAAYKTSApAQBjAQAYAAYKTSApAQBjAQA1AAQKf0QAAhgACgrZJJoBAEUDABgACgrZJJoBAEUDAAAA.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECn8wAAMbAAoKAhllEwBGAgAbAAoKAhllEwBGAgAZAAcKWAuuKAAcAQAAAA==.Luxurious:BAABNQAECn8nAAIkAAgKlga6EgDpAAAkAAgKlga6EgDpAAAAAA==.',
Ma='Maaca:BAAANQAECgYICAAAAA==.Madeofhide:BAAANQADCgMIAwAAAA==.Maecarepicha:BAAANQAECgUIDQAAAA==.Magicmoose:BAAANQAECgUICAAAAA==.Malachor:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.Maligned:BAAANQAECgcIEQAAAA==.Martichoux:BAABNQAECn8WAAIWAAkK9ReChgBxAgAWAAkK9ReChgBxAgAAAA==.Mastakronik:BAAANQABCgMIBAAAAA==.Match:BAAANQAECgMIAwAAAA==.Mathas:BAABNQAECn87AAQIAAoKQB5ADgBYAwAIAAoKQB5ADgBYAwARAAQKZRBULgDVAAAHAAIKeAfXhgFQAAAAAA==.Mathilda:BAAANQAECgMIBAAAAA==.',
Mc='Mccholock:BAABNQAECn8dAAMjAAkK6RAjEwBvAQAjAAgKKREjEwBvAQAgAAYKtwhaxQC3AAAAAA==.Mcmach:BAABNQAECn8WAAInAAcK3gsmAwBQAQAnAAcK3gsmAwBQAQAAAA==.',
Me='Meddox:BAEANQADCgQIBAAAAA==.Mehaoloka:BAAANQADCggIEQAAAA==.Memelle:BAABNQAECn8bAAIiAAYKNBUmEwB1AQAiAAYKNBUmEwB1AQAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAABNQAECn8bAAMTAAcKJhF8KQAFAQATAAcKJhF8KQAFAQAUAAIKtQQBcQBCAAAAAA==.Menotthatorc:BAAANQAECgQIBAABNQAFFAQIDAAeAL8UAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAABNQAECn8fAAMOAAkK2x5KFwDwAgAOAAkK2x5KFwDwAgAPAAEKAAD/hwAiAAAAAA==.Mesilana:BAAANQAECgMIAwAAAA==.Metrx:BAAANQAECgUIBAAAAA==.',
Mi='Mikosen:BAAANQAECgYIDAAAAA==.Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAABNQAECn8jAAIOAAgKwBiFRQDqAQAOAAgKwBiFRQDqAQAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.Mithian:BAAANQADCgMJAwABNQADCggIBgABAAAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgUIDAAAAA==.Monichan:BAAANQAECgQIBgAAAA==.Moosecheeks:BAABNQAECn8dAAITAAoKHhknEwDJAQATAAoKHhknEwDJAQAAAA==.Morganna:BAABNQAECn8ZAAIWAAoKugSswgD4AAAWAAoKugSswgD4AAAAAA==.Morior:BAABNQAECn8gAAIeAAgKgAyICAAVAQAeAAgKgAyICAAVAQAAAA==.Morslucifer:BAABNQAECn8cAAMoAAgKvBiKBQBoAgAoAAgKvBiKBQBoAgAeAAEKehPDcgA8AAAAAA==.Motorcade:BAABNQAECn8uAAIaAAkKhANwEQDaAAAaAAkKhANwEQDaAAAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQAECgYICAAAAA==.',
My='Mypal:BAABNQAECn8hAAIHAAgKhwbayAAFAQAHAAgKhwbayAAFAQAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
['Mû']='Mûrasaki:BAAANQABCgQIBwAAAA==.',
Na='Naula:BAAANQAECgQIBQAAAA==.',
Ne='Neather:BAABNQAECn8hAAIiAAkKCxiVCgAfAgAiAAkKCxiVCgAfAgAAAA==.Neron:BAAANQADCgUIDQAAAA==.Nexeon:BAAANQAECgUIBgABNQAECgoKHgACAPkaAA==.Nezkima:BAAANQAECgUIBQABNQAECgoKQQAKAHgiAA==.',
Ni='Nidivh:BAAANQAECgQIDAAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAABNQAECn8WAAIHAAYKgA8u4wBVAQAHAAYKgA8u4wBVAQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAwAAAA==.Nira:BAABNQAECn8nAAIOAAoKMRiTQgBiAgAOAAoKMRiTQgBiAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAABNQAECn8WAAIhAAgKDhRuEgDXAQAhAAgKDhRuEgDXAQAAAA==.',
No='Nodöts:BAAANQAECggICAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Nonetoo:BAAANQAECggICQABNQAECggICwABAAAAAA==.Notdeadyet:BAABNQAECn8UAAIMAAYK8Qex2ABPAQAMAAYK8Qex2ABPAQAAAA==.Notron:BAABNQAECn8bAAIXAAoKFxlmJwBjAgAXAAoKFxlmJwBjAgAAAA==.Noz:BAAANQADCggIFgAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQAECgUIBQAAAA==.Nychophysis:BAABNQAECn8dAAMFAAcK6AyjNQCmAAAFAAYKywyjNQCmAAAEAAMK/wjbjwCdAAAAAA==.Nyxion:BAAANQADCggICgABNQAECgQIBQABAAAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oakarm:BAAANQAECggICAAAAA==.Oasis:BAAANQAECggICAAAAA==.',
Od='Odyssius:BAAANQAECggIAQAAAA==.',
Og='Ogbamz:BAAANQADCgQIBAAAAA==.Ogden:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Om='Omars:BAAANQAECgYICAAAAA==.',
On='Ontherun:BAAANQAECgUIBwAAAA==.',
Op='Oprawinfury:BAAANQAECgUICwAAAA==.',
Or='Orgazmik:BAAANQADCgYIDAAAAA==.Orphani:BAAANQABCgMIAQAAAA==.',
Ou='Ourus:BAABNQAECn9CAAIdAAoKXiI4AwBvAwAdAAoKXiI4AwBvAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Panax:BAAANQAECgUIEAAAAA==.Paulo:BAABNQAECn8bAAIHAAYKAgqF8gA3AQAHAAYKAgqF8gA3AQAAAA==.',
Pe='Pele:BAAANQAECgUIEgAAAA==.Pellito:BAAANQADCgQICAAAAA==.Perpetrator:BAABNQAECn8tAAIDAAgKVAXzRAAAAQADAAgKVAXzRAAAAQAAAA==.',
Pi='Piki:BAABNQAECn8sAAIKAAoKPA0OUgCYAQAKAAoKPA0OUgCYAQAAAA==.',
Po='Poepwn:BAABNQAECn8xAAQbAAgK2Q72FQBiAQAbAAgK2Q72FQBiAQAaAAYK+wZJFgCbAAAZAAEKAACQdwAgAAAAAA==.',
Pr='Pray:BAABNQAECn8YAAIOAAkKeRxvHgC3AgAOAAkKeRxvHgC3AgABNQAECgEIAQABAAAAAA==.Prescient:BAAANQAECggIEAAAAA==.',
Pu='Puffypanda:BAAANQAECgUIEAAAAA==.Putnamehere:BAAANQABCgcICQAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quadeshboy:BAAANQAECggIDgABNQAECgoKPAAWAI0jAA==.Quill:BAAANQAECggIEwAAAA==.',
Ra='Raging:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Ralz:BAABNQAECn8aAAICAAYK3RT7UABvAQACAAYK3RT7UABvAQAAAA==.Rangon:BAAANQADCggIDwAAAA==.Rannick:BAABNQAECn8fAAMYAAcKGQwDGwAkAQAYAAcKGQwDGwAkAQAKAAEK9QYKJQEoAAAAAA==.Ranua:BAAANQAECgUICQABNQAECgoKLAAOAGMhAA==.Ratdemonmike:BAABNQAECn8YAAIkAAcKhB4ACQCjAQAkAAcKhB4ACQCjAQAAAA==.Rate:BAABNQAECn8XAAIXAAgKjhLGLwBZAQAXAAgKjhLGLwBZAQABNQAECgoKNAAGAN8YAA==.Ratio:BAABNQAECn80AAIGAAoK3xhHEAAoAgAGAAoK3xhHEAAoAgAAAA==.',
Re='Reecurve:BAAANQAECgEIAQAAAA==.Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAABNQAECn8bAAMfAAoKGRkhKABFAgAfAAoKGRkhKABFAgAeAAEKSg/uMQA0AAAAAA==.',
Ri='Richard:BAAANQAECgMIAwAAAA==.Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgYIEQABNQAECgcICQABAAAAAA==.Rosary:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.',
Ru='Ruden:BAAANQAECgQICQAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECggIDQABNQAECgoKMQAYALUeAA==.',
Rw='Rwqr:BAABNQAECn84AAIXAAkKHAvpQAC4AQAXAAkKHAvpQAC4AQAAAA==.',
['Rä']='Räiden:BAABNQAECn8nAAMiAAoK+w8KCQDYAQAiAAoK+w8KCQDYAQAWAAYKsAccOAEvAQAAAA==.',
Sa='Salacake:BAAANQAECgQIBAAAAA==.Salacakei:BAABNQAECn9AAAMFAAoKqBJqFAByAQAEAAoK6Q9CNQDnAQAFAAgKbxJqFAByAQAAAA==.Salin:BAAANQAECggIDwAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFH8eAAIRAAcKyh7VAAClAgARAAcKyh7VAAClAgA1AAQKfy0AAhEACgocJpQFAFYDABEACgocJpQFAFYDAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scaley:BAAANQAECgMIAQABNQAECgEIAQABAAAAAA==.Scarletpaw:BAAANQAECgEIAQAAAA==.Scoobie:BAAANQAECgEIAgABNQAECgkJOgAMACEhAA==.Scoobydo:BAAANQAECgUIEAABNQAECgkJOgAMACEhAA==.Scratches:BAAANQAECgQICAAAAA==.Scrubs:BAACNQAFFH8GAAIMAAQK3gPlGgDjAAAMAAQK3gPlGgDjAAA1AAQKf0oAAgwACgp2G9QlAH0CAAwACgp2G9QlAH0CAAAA.',
Se='Seider:BAAANQAECggIBgAAAA==.Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadmage:BAAANQABCgIIAgABNQABCgIIAgABAAAAAA==.Shadpriest:BAAANQABCgIIAgAAAA==.Shaggzy:BAACNQAFFH8ZAAIZAAcK1BdSAwA1AgAZAAcK1BdSAwA1AgA1AAQKf0EAAhkACgovJGYEABsDABkACgovJGYEABsDAAAA.Shallabal:BAAANQAECggICAAAAA==.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAABNQAECn8kAAMmAAgKfw+7IwASAQAMAAcKPRAotgCYAQAmAAcKEg67IwASAQAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAABNQAECn8XAAIhAAcK8RADGQD+AAAhAAcK8RADGQD+AAAAAA==.Shockdoctor:BAABNQAECn8rAAMKAAoK2iPMBgCQAwAKAAoK2iPMBgCQAwALAAMKTxR2+QCgAAAAAA==.Shortrange:BAAANQADCgEIAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJKwAIACokAA==.',
Si='Sintotem:BAAANQAECgMIAwAAAA==.',
Sl='Sleples:BAABNQAECn86AAIMAAkKISEeKgDwAgAMAAkKISEeKgDwAgAAAA==.Slufgor:BAAANQAECgQIDwAAAA==.Slyxxii:BAAANQAECgQIBAAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCggIFQAAAA==.',
Sn='Sniperbeko:BAAANQAECgEIAQABNQAECgoKMgAWAK4cAA==.Snoo:BAAANQAECgUICwAAAA==.',
So='Solarlite:BAAANQAECgQIBQAAAA==.Solinari:BAAANQABCgIIBAAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAABNQAECn8aAAMOAAkKqCMVCQB7AwAOAAkKqCMVCQB7AwAQAAIK8CTpFQDNAAAAAA==.Soulbreakër:BAABNQAECn8yAAICAAkKcAw6SQCXAQACAAkKcAw6SQCXAQAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYIDQAAAA==.Sparks:BAAANQAECgMIBAABNQAECgoKGgAVAH4UAA==.Specimen:BAAANQADCggJEgAAAA==.Speddling:BAABNQAECn8dAAIWAAkKuw9KlwBJAQAWAAkKuw9KlwBJAQABNQAECgoKGgAVAH4UAA==.Spellgennce:BAAANQAECgQIBAAAAA==.Spicey:BAAANQADCgYIDAABNQAECgoKPAAMAOcgAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQAECgUIDAAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAABNQAECn8WAAIMAAgKZQrMhgBiAQAMAAgKZQrMhgBiAQAAAA==.',
Sr='Srbranchmgr:BAAANQADCgMIBAAAAA==.',
St='Starbrow:BAABNQAECn8aAAIMAAgKFSIxTACJAgAMAAgKFSIxTACJAgAAAA==.Starrybeko:BAAANQABCgYIBgABNQAECgoKMgAWAK4cAA==.Sticky:BAAANQABCgIIAgAAAA==.Stilez:BAAANQAECggIBwABNQAECggIEAABAAAAAA==.Stole:BAAANQAECgQIAwABNQAECgoKGgAVAH4UAA==.Stormlight:BAABNQAECn8cAAIUAAcKIg8qKABjAQAUAAcKIg8qKABjAQAAAA==.Strudelmaker:BAAANQAECgMIAwABNQAECgkJKAAXAKcaAA==.Stárrk:BAAANQADCgQIBAAAAA==.',
Su='Sumikka:BAAANQADCgQIBAAAAA==.Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAAANQAECgYIEAAAAA==.',
Sv='Svetaköln:BAAANQADCgYIBgAAAA==.',
Sy='Syland:BAABNQAECn8XAAIMAAcKewrqpQAhAQAMAAcKewrqpQAhAQAAAA==.Sylvanäs:BAABNQAECn8bAAIMAAUK5Apm8gAdAQAMAAUK5Apm8gAdAQAAAA==.Syrellina:BAAANQAECgQIBAABNQAECgoKLAAOAGMhAA==.Sysna:BAABNQAECn89AAMPAAoKQCNfBwDVAgAPAAoKQCNfBwDVAgAOAAcKRCAbQwBfAgAAAA==.',
Ta='Taiga:BAAANQADCgEIAQABNQAFFAQIDAAeAL8UAA==.Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECn8lAAIKAAcKXBTKbgC/AQAKAAcKXBTKbgC/AQAAAA==.Tankwar:BAAANQADCgYIFwAAAA==.Targis:BAABNQAECn8hAAIgAAgKDw+DpADBAQAgAAgKDw+DpADBAQAAAA==.Tauran:BAAANQADCgcIDwAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECgoKLAAOAGMhAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Tergar:BAAANQAECgMIBQAAAA==.Teâfâ:BAAANQADCgQIAgAAAA==.',
Th='Thaleas:BAABNQAECn8pAAQRAAoKPhHSFwCEAQARAAgKCBLSFwCEAQAIAAkKjgwwYQBiAQAHAAQK+QllGgGLAAAAAA==.Thegreatkhal:BAABNQAECn8eAAIPAAgKKBjnGwB4AQAPAAgKKBjnGwB4AQAAAA==.Thequickness:BAAANQABCgYIBwAAAA==.Therizino:BAAANQADCgEIAQAAAA==.Thorizine:BAAANQAECgcIEAAAAA==.Thorlas:BAABNQAECn8vAAMKAAgKtR83JwBfAgAKAAgKtR83JwBfAgALAAMKCxet7wC3AAAAAA==.Thornado:BAAANQAECgQIBwAAAA==.Thotsfortots:BAAANQAECggICQABNQAECgoKIgAVAF4bAA==.Thylacoleo:BAAANQADCgUIBQAAAA==.',
Ti='Timmúk:BAABNQAECn8oAAIXAAkKpxp9KwBHAgAXAAkKpxp9KwBHAgAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAABAAAAAA==.Tomma:BAAANQAECggIDgAAAA==.Torment:BAAANQAECgQIBwABNQAECgEIAQABAAAAAA==.Torsion:BAABNQAECn8bAAILAAgKlRrYPACCAgALAAgKlRrYPACCAgAAAA==.',
Tr='Trailerpark:BAAANQADCgMIAwAAAA==.Tratre:BAABNQAECn8lAAMcAAkKLBzvDwBaAgAcAAkKLBzvDwBaAgAlAAQKMg9bKQB/AAAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAABNQAECn8UAAIXAAYKJAhAUgCmAAAXAAYKJAhAUgCmAAAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAgIEgAXAHoWAA==.Turd:BAAANQADCgcIBwAAAA==.Tust:BAAANQAECgUICgABNQAECgUIDAABAAAAAA==.',
Ty='Tylandy:BAABNQAECn80AAIWAAoKoiJaGgBsAwAWAAoKoiJaGgBsAwAAAA==.Tytaniormu:BAAANQAECgYIBwAAAA==.',
['Tê']='Tês:BAAANQAECgUICwAAAA==.',
Un='Undeadbetty:BAAANQADCgcICAAAAA==.Undeathtwoy:BAAANQAFFAEIAQABNQAECgkJNAAPAGUcAA==.',
Va='Vaayl:BAABNQAECn8cAAIYAAkKwR44CwAzAgAYAAkKwR44CwAzAgAAAA==.Vaelraen:BAAANQAECgUICgAAAA==.Valcher:BAABNQAECn8bAAMVAAcKIgXvUwCjAAAVAAcKIgXvUwCjAAAUAAEK4wNkgAAfAAAAAA==.Valendera:BAABNQAECn8WAAIfAAkKRAkdlAC0AQAfAAkKRAkdlAC0AQAAAA==.Valerius:BAAANQAECggICgAAAA==.Valguero:BAAANQADCggICwAAAA==.Valifadin:BAABNQAECn8iAAIpAAgKsx7rBADlAQApAAgKsx7rBADlAQAAAA==.Valndrevy:BAAANQADCggIHAAAAA==.Vamire:BAAANQAECggIEAAAAA==.Vanpèlt:BAAANQADCgYIFwAAAA==.Vansan:BAABNQAECn8sAAQOAAoKYyEjIADvAgAOAAoK/CAjIADvAgAQAAEKKSApEABeAAAPAAIKwBAqVAA4AAAAAA==.',
Ve='Venngennce:BAABNQAECn83AAICAAoKeh+zFQDeAgACAAoKeh+zFQDeAgAAAA==.Verran:BAAANQAECgEIAQAAAA==.',
Vi='Viktir:BAAANQAECgIIAgABNQAECgUIEgABAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Voladen:BAAANQAECgEIAQAAAA==.Vorkath:BAABNQAECn8wAAMcAAoKCyOiBQA2AwAcAAoKCyOiBQA2AwAlAAQKOwqgOQDJAAAAAA==.Vormette:BAAANQADCggIGQAAAA==.',
Vt='Vtae:BAABNQAECn8ZAAIMAAYKDgdi3QBGAQAMAAYKDgdi3QBGAQAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAABNQAECn8yAAIUAAgKlxNQHwCzAQAUAAgKlxNQHwCzAQAAAA==.Westin:BAAANQADCgIIAgAAAA==.',
Wh='Whitedragon:BAAANQAECggIAgAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Wo='Woxkal:BAABNQAECn8pAAQJAAgKiAiuNwAQAQACAAcK1wXlYQAdAQAJAAcKNAeuNwAQAQADAAMKegcdrwBtAAAAAA==.',
Wu='Wubblebubble:BAAANQAECggIEgAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgcIEwAAAA==.',
Xu='Xuzhu:BAABNQAECn8pAAIWAAoKeRd8bACqAQAWAAoKeRd8bACqAQABNQAFFAcIFQAVAFQbAA==.',
Ye='Yelignar:BAAANQABCgEIAQAAAA==.',
Yi='Yinei:BAAANQAFFAIIAgAAAA==.',
Yl='Ylvis:BAABNQAECn8bAAIMAAgKbhV+eAAeAgAMAAgKbhV+eAAeAgAAAA==.',
Yo='Yol:BAABNQAECn8aAAISAAkKngxjCgDKAQASAAkKngxjCgDKAQAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECggIJwAAAQ==.',
Yu='Yukikaze:BAAANQABCgQIBAAAAA==.',
Yv='Yvetal:BAAANQAECgUIDAABNQAFFAQIDAAeAL8UAA==.',
Za='Zapdos:BAAANQADCggICAAAAA==.Zarion:BAACNQAFFH8WAAIUAAYKrB+MBACqAQAUAAYKrB+MBACqAQA1AAQKfyoAAxQACgrvIv0EAHMDABQACgrvIv0EAHMDABUAAQoAANvDAB4AAAAA.Zarra:BAAANQAECgQIBgAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQIBAAAAA==.Zetterberg:BAAANQAECggIAQAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQAFFAIIAgABNQAFFAYIFgAUAKwfAA==.Ziyar:BAAANQAECgQICgABNQAFFAYIFgAUAKwfAA==.',
Zo='Zocorro:BAAANQAECgUICwAAAA==.',
Zr='Zra:BAAANQADCgEIAQAAAA==.',
Zy='Zypherdius:BAAANQAECgQIBwAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFH8aAAIHAAYKyRdfCwCTAQAHAAYKyRdfCwCTAQA1AAQKfzoAAgcACgpRJR47AOUCAAcACgpRJR47AOUCAAAA.',
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
