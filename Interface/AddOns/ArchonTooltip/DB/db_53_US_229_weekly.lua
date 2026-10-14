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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','Paladin-Retribution','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection','Paladin-Holy','Druid-Guardian','Druid-Balance','Druid-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Evoker-Augmentation','Warrior-Fury','DemonHunter-Vengeance','Monk-Mistweaver','DemonHunter-Havoc','Evoker-Preservation','Warrior-Arms','Warrior-Protection','Hunter-Marksmanship','Mage-Fire','Warlock-Affliction',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaralyn:BAAANQAECgMIAwAAAA==.',
Ab='Abmikaze:BAAANQADCggICgAAAA==.Absolon:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.Abysseon:BAABNQAECn8YAAMCAAgKpRpDLwAlAgACAAgKpRpDLwAlAgADAAMK2w0TqQB7AAAAAA==.',
Ac='Ace:BAABNQAECn8dAAMEAAgKdh/5GAAPAgAEAAYKFh75GAAPAgAFAAMKNiKObQDyAAABNQAECgEIAQABAAAAAA==.',
Ad='Adios:BAACNQAFFH8RAAIGAAYKDA9ABQDbAQAGAAYKDA9ABQDbAQA1AAQKfyoAAgYACQq/HtwJADkDAAYACQq/HtwJADkDAAAA.Adorean:BAABNQAECn8dAAIHAAgKzxJzngDgAQAHAAgKzxJzngDgAQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgQIDAAAAA==.Agrohn:BAAANQAECgYIDwAAAA==.',
Ai='Aimnskin:BAAANQADCggJEwAAAA==.',
Al='Alcore:BAABNQAECn8dAAQDAAkKNRnfHwCxAgADAAcK2yHfHwCxAgAIAAYKaBzXSwDiAQACAAMKUgvYlABkAAAAAA==.Aliine:BAABNQAECn8WAAIDAAYKIBNjbQA8AQADAAYKIBNjbQA8AQAAAA==.',
Am='Ameiisaa:BAABNQAECn8ZAAMJAAcKrQkF5gDFAAAJAAUK3wQF5gDFAAAKAAQKSQN55gCZAAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAACNQAFFH8IAAIJAAQKkBOlFAAmAQAJAAQKkBOlFAAmAQA1AAQKfzwAAgkACQoRINMZACwDAAkACQoRINMZACwDAAAA.',
An='Anxie:BAABNQAECn8ZAAILAAcKxQWQ7QAhAQALAAcKxQWQ7QAhAQAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAYIEgAMAP8aAA==.',
Ao='Aoifae:BAAANQAECgUIDAAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECn8ZAAQNAAkKnAnOfwCUAQANAAgKGgrOfwCUAQAOAAcKewadPwAtAQAPAAEKMAXjLgAmAAAAAA==.Apprentice:BAABNQAECn8VAAIQAAcKngItSgC/AAAQAAcKngItSgC/AAAAAA==.',
Ar='Aramos:BAABNQAECn8iAAIRAAgKDxnuPABuAgARAAgKDxnuPABuAgAAAA==.Aramôs:BAAANQAECgQIBwAAAA==.Arkhangel:BAABNQAECn8ZAAIHAAgKJBhLdgA8AgAHAAgKJBhLdgA8AgAAAA==.Arta:BAAANQAECgQIBwAAAA==.Artavian:BAAANQABCgIIAwAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAAANQAECgYIEwAAAA==.Assiam:BAAANQADCgIIAgAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECgkJMgADAAwaAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQAECgQIDAAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.',
Be='Beaker:BAABNQAECn8iAAISAAgKohH9HQCqAQASAAgKohH9HQCqAQAAAA==.Beastmode:BAABNQAECn8tAAMTAAgKPRVNPQAJAgATAAgKPRVNPQAJAgAUAAgKThOXKQDPAQAAAA==.Bedlem:BAAANQAECgYIDAAAAA==.Beko:BAABNQAECn8fAAIVAAkK2xvaQQABAwAVAAkK2xvaQQABAwAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBgAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgMIBwAAAA==.Billydan:BAAANQAECgcIEQAAAA==.',
Bl='Blackhide:BAAANQABCgMIBAAAAA==.Blackpanthxr:BAABNQAECn8uAAQKAAkKuxNXRgBFAgAKAAkKuxNXRgBFAgAWAAcKghGGGQDHAQAJAAcKfAc8rAA3AQAAAA==.Blackvortex:BAAANQAECgQIBAAAAA==.Bloodgoat:BAAANQADCggICwAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECggIHAAXAOYjAA==.Bloodyburst:BAABNQAECn8aAAMMAAgK2CKXBQCMAgAMAAcKEyOXBQCMAgAFAAIKDBwjgACpAAABNQAECggIHAAXAOYjAA==.Bloodyfistz:BAABNQAECn8cAAMXAAgK5iMyDgD5AgAXAAgKzyMyDgD5AgAYAAIKMyNfIgDDAAAAAA==.Blue:BAABNQAECn8fAAIJAAkKAxu9KgDSAgAJAAkKAxu9KgDSAgAAAA==.Bluethreetwo:BAAANQAECgQICAAAAA==.',
Bo='Bookofzeref:BAAANQAECgcIBwAAAA==.Boost:BAAANQABCgIIBAAAAA==.',
Br='Brayend:BAAANQAECgcICwAAAA==.Brewguts:BAAANQAECgcIDwAAAA==.Brimscythe:BAABNQAECn8pAAIZAAkKnxwrCQDfAgAZAAkKnxwrCQDfAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggIDgAAAA==.Caliandis:BAAANQAECgUIEAAAAA==.Calvey:BAAANQAECgMIAwAAAA==.Cambrai:BAAANQAECgQIBwAAAA==.Cannabelle:BAABNQAECn8gAAILAAgK4iKZHQAgAwALAAgK4iKZHQAgAwAAAA==.Carclias:BAABNQAECn8wAAMaAAkKnBY1DQAkAgAaAAgKkxU1DQAkAgAbAAcKMBQCjQDBAQAAAA==.Carthrix:BAAANQAECgcIDQAAAA==.Catbarf:BAAANQAECgYIAQABNQAECgkJKgAWAO0dAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAAANQAECgQICwAAAA==.',
Ce='Celery:BAAANQAECgUIBQABNQAFFAYIGwADAHcXAA==.Cellika:BAAANQAECgUIDgAAAA==.Cerdelz:BAAANQAECgQIBAAAAA==.',
Ch='Chaoscookies:BAABNQAECn8vAAMaAAkKWRX6EgDaAQAaAAcKEBb6EgDaAQAbAAYKeg+rpwB/AQAAAA==.Chartkov:BAAANQAECgQIBQAAAA==.Cheezee:BAABNQAFFH8TAAMVAAcKLhDgDwDzAQAVAAYKzhPgDwDzAQAcAAEKrwFxEQBLAAAAAA==.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQADCggIEwAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECggIEwABAAAAAA==.',
Ci='Cinderpetal:BAAANQAECgQICAAAAA==.',
Ck='Ckay:BAAANQAECgcIBwAAAA==.',
Cl='Clawsome:BAAANQADCggIEwAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAACNQAFFH8GAAMDAAIKSA81IwBvAAACAAIK9wnlFgCEAAADAAIKSA81IwBvAAA1AAQKfyEABAIACQoeG4QgAIUCAAIACAryGIQgAIUCAAgABwoFFQ1gAIwBAAMABApXFR6HAN4AAAAA.Comlock:BAAANQADCgYIDAAAAA==.Complacent:BAABNQAECn8cAAISAAcKRAMuPwC4AAASAAcKRAMuPwC4AAAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgIIBAAAAA==.Coriander:BAABNQAECn8YAAIdAAkKlBI9CAAUAgAdAAkKlBI9CAAUAgAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAAANQAECgYIDAABNQAECgYIDwABAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAcIFgAXANQXAA==.',
Cy='Cynical:BAAANQAECgIIAwABNQAECgEIAQABAAAAAA==.Cyonicus:BAABNQAECn8dAAIbAAgKlBuOWgBEAgAbAAgKlBuOWgBEAgAAAA==.Cyska:BAABNQAECn8yAAIDAAkKDBooJwCDAgADAAkKDBooJwCDAgAAAA==.',
['Cé']='Cécé:BAABNQAECn8eAAIHAAgKNxk/ZwBiAgAHAAgKNxk/ZwBiAgAAAA==.',
['Cë']='Cëcë:BAAANQAECgMIAwAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAABNQAECn8nAAINAAkKZg9iTgA2AgANAAkKZg9iTgA2AgAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagerlaurn:BAABNQAECn8YAAMTAAgKtxtEKACQAgATAAgKtxtEKACQAgAUAAQKxhuzOQBMAQAAAA==.Dagevas:BAAANQADCgYIBgAAAA==.Dakeria:BAAANQADCgYIGgAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEAAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECn8sAAIeAAkKZBI3CgAnAgAeAAkKZBI3CgAnAgABNQAFFAUIDAAHACUcAA==.Davriell:BAAANQAECgUICgAAAA==.Dax:BAAANQAECgUIEAAAAA==.Daxing:BAAANQADCggIFAABNQAECgkJJAANAKYdAA==.',
De='Deeppurple:BAAANQAECgUICQAAAA==.Del:BAABNQAECn8lAAIfAAgK9SUZAgBuAwAfAAgK9SUZAgBuAwABNQAECggIJQAgAEUaAA==.Demoniaca:BAAANQADCgEIAQAAAA==.Demonic:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Demonshady:BAAANQABCggIFAAAAA==.Demoraliziñg:BAAANQADCggIDgABNQAECggIIQAhAGcZAA==.Demostache:BAABNQAECn8qAAMbAAkKiCFHLQDOAgAbAAgKyiBHLQDOAgAaAAIKyRX0TgCRAAABNQAFFAIIBgADAEgPAA==.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECn8jAAIJAAgK9SCuJQDrAgAJAAgK9SCuJQDrAgAAAA==.',
Di='Diivision:BAAANQAECgEIAQABNQAECgkJIgAGAOEQAA==.',
Do='Dolomite:BAAANQAECgcIEwAAAA==.Dorow:BAABNQAECn8nAAMTAAkKBxg+JQClAgATAAkKBxg+JQClAgAUAAQKsQzzTADVAAAAAA==.Dotabolt:BAAANQAECgYIEQABNQAECgcIDgABAAAAAA==.',
Dr='Dracthyris:BAABNQAECn8WAAIiAAgKUgoUJQCUAQAiAAgKUgoUJQCUAQAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Dreaa:BAAANQAECgEIAQAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECn8qAAIWAAkK7R1XBwAIAwAWAAkK7R1XBwAIAwAAAA==.',
Du='Dunsel:BAAANQAECgUIDAABNQAECgkJKQAZAJ8cAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgQIBAAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECn8nAAMjAAgKbBLpiQD/AQAjAAgKbBLpiQD/AQAkAAIK/QkOPABRAAAAAA==.',
['Dã']='Dãnny:BAAANQADCggIDQABNQAECggIJwAjAGwSAA==.',
Ea='Earendil:BAAANQAECggICAAAAA==.',
Eb='Ebonshade:BAAANQAECgEIAQAAAA==.',
Ed='Edena:BAAANQAECgEIAQAAAA==.Edginglord:BAAANQAECgQIBgAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQAAAA==.Eloras:BAAANQAECgQIBQAAAA==.Elunbi:BAABNQAECn8rAAMNAAkK9h09HgD2AgANAAkKVR09HgD2AgAPAAYKkhSKDQBZAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQAECgQIBAAAAA==.',
Ep='Epsilòn:BAEANQAECggIEAAAAA==.',
Er='Ernest:BAAANQAECgUIDAAAAA==.Errani:BAAANQAECgYIDwAAAA==.',
Es='Esper:BAAANQAECgYIDAAAAA==.Esterlia:BAAANQADCgYIBgABNQAECgkJJAANAKYdAA==.',
Et='Eternal:BAAANQAECgEIAQAAAA==.',
Eu='Eureki:BAAANQAECgcICwAAAA==.',
Ev='Evilkarma:BAAANQAECgYIDwAAAA==.Evocatis:BAACNQAFFH8KAAIHAAQKFx1gDwBPAQAHAAQKFx1gDwBPAQA1AAQKfyQAAwcACQqKJIskADADAAcACQqKJIskADADABEABApTDYDKAOIAAAAA.',
Ey='Eyekonicklok:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Eyesdeadeyed:BAABNQAECn8mAAIlAAkKTxUgJgAYAgAlAAkKTxUgJgAYAgAAAA==.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAABNQAECn8kAAMHAAgKCB9YRQDBAgAHAAgKCB9YRQDBAgARAAUK2hvHfQCcAQAAAA==.Falco:BAAANQAECggIAQABNQAECggICAABAAAAAA==.Faon:BAAANQAECgEIAQAAAA==.Farrea:BAAANQADCggIFwABNQAECgQIBAABAAAAAA==.Fatlock:BAAANQAECgQICQABNQAECgkJKwAXACAcAA==.Fayvia:BAAANQABCggIDQAAAA==.',
Fe='Feebz:BAAANQADCgYIBwAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECgMIBAABNQAECgEIAQABAAAAAA==.Firebirdz:BAACNQAFFH8JAAIUAAQK2RaRCQBBAQAUAAQK2RaRCQBBAQA1AAQKfxsAAhQACQpLH/ASALMCABQACQpLH/ASALMCAAAA.',
Fl='Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCggIEAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAABNQAECn8lAAIGAAgKQRFmJwAFAgAGAAgKQRFmJwAFAgAAAA==.Freshhéals:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Friargark:BAAANQADCgYICwAAAA==.Frizby:BAAANQAECgQIBQAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQAECgUIDQAAAA==.',
Fy='Fyrelord:BAAANQAECgEIAQAAAA==.Fyuna:BAABNQAECn8iAAIKAAgKjR6ZLACuAgAKAAgKjR6ZLACuAgAAAA==.',
Ga='Gark:BAAANQAECgQICAAAAA==.Garkk:BAAANQADCgQJBAAAAA==.Garrumn:BAAANQADCgcIBwABNQAFFAIIBgADAEgPAA==.Gazzi:BAAANQAECggIEwAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgUIDgABAAAAAA==.',
Gi='Giuseppee:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Gióvanna:BAAANQAECgQIBgAAAA==.',
Gl='Glodskegg:BAAANQAECggIEwAAAA==.',
Go='Goldensea:BAAANQAECgQICwAAAA==.Gotenk:BAAANQAECgYIDQAAAA==.Goyim:BAAANQAECgQIBQAAAA==.',
Gr='Gr:BAAANQADCgMICQAAAA==.Grissoul:BAAANQAECgYIBgAAAA==.Grody:BAAANQAECgUIEAAAAA==.Gryms:BAAANQADCgUIBQAAAA==.',
Gu='Guroo:BAABNQAECn8iAAILAAgKyAoXmwDNAQALAAgKyAoXmwDNAQAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
['Gí']='Gígí:BAAANQAECgIIAgAAAA==.Gíl:BAAANQADCgQIBAAAAA==.',
Ha='Hagarn:BAABNQAECn8mAAIHAAkKLBRhegAyAgAHAAkKLBRhegAyAgAAAA==.Halastrin:BAAANQAECgEIAQAAAA==.Halimah:BAAANQAECgQICQAAAA==.Halois:BAAANQADCgYIBgABNQAECgcIHAADABkSAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggIDgAAAA==.Hazan:BAAANQAECggIDwABNQAECgkJKgAWAO0dAA==.',
He='Hexmachine:BAABNQAECn8rAAIbAAkKFhb+RQB9AgAbAAkKFhb+RQB9AgAAAA==.',
Ho='Hole:BAAANQADCgYJBgAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgEIAgAAAA==.',
Hy='Hypertext:BAAANQAECgcIEwAAAA==.',
Ia='Iamahriman:BAABNQAECn8aAAIJAAgK5Qd0iQCIAQAJAAgK5Qd0iQCIAQAAAA==.Iamarawn:BAABNQAECn8ZAAILAAgKCwXpuQCLAQALAAgKCwXpuQCLAQAAAA==.',
Ic='Icecreme:BAAANQABCgYIDgAAAA==.Icegoesbrr:BAAANQADCgEIAQAAAA==.',
Ig='Ignite:BAABNQAECn8jAAMVAAkKrh9xQQACAwAVAAgKGiFxQQACAwAcAAEKJxc0QABCAAAAAA==.',
Il='Illestria:BAABNQAECn8oAAIHAAgKQxBZmgDpAQAHAAgKQxBZmgDpAQAAAA==.Illumiscotty:BAABNQAECn8sAAQVAAkKZSX/CwCmAwAVAAkKZSX/CwCmAwAcAAMKzR5jHAAJAQAmAAEKIB5mCgBZAAAAAA==.',
In='Incognonetoo:BAAANQAECgcICAAAAA==.Insania:BAABNQAECn8YAAMKAAcKtAOdtwD4AAAKAAcKtAOdtwD4AAAJAAUK/ARO1ADnAAAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgYIHQAAAA==.',
Ja='Jab:BAAANQABCgQIBAAAAA==.Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQADCggIDgABNQAECgkJJAANAKYdAA==.Jastirri:BAAANQAECgUIDAAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgUICgAAAA==.Jimothy:BAAANQADCggIDgABNQADCgYICgABAAAAAA==.Jin:BAAANQAECgQIBAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAAANQAECggIEwAAAA==.',
Ju='Juicez:BAAANQAECgQIBwAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECggICgAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIEwAAAA==.Katio:BAABNQAECn8vAAMFAAkKpCESNQAAAgAFAAUK4yISNQAAAgAEAAQKiB69LgBFAQAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAAANQAECgUIDgAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgMIBAAAAA==.Kessandra:BAACNQAFFH8eAAMbAAcKsyIKAQC6AgAbAAcKsyIKAQC6AgAnAAEKAAChCABeAAA1AAQKfyEAAycACQokJRwCABADACcACQonIhwCABADABsABQpKI7OfAJIBAAAA.Kexally:BAAANQAECgIIAwAAAA==.Kexkan:BAAANQADCgQIDAABNQAECgIIAwABAAAAAA==.Kezzia:BAAANQADCgMIAwAAAA==.',
Kh='Khurri:BAAANQAECggIEwAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAAANQAFFAEIAQAAAA==.Kisor:BAAANQADCgQIBwAAAA==.Kitchenstink:BAAANQAECggIEwAAAA==.',
Ko='Koifo:BAAANQABCgUIBgAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggICgAAAA==.',
Kr='Kritanta:BAABNQAECn8cAAIDAAcKGRIvWACPAQADAAcKGRIvWACPAQAAAA==.Krystallus:BAAANQAECgQIBgAAAA==.',
Ku='Kurnea:BAAANQAECgUIDQAAAA==.',
['Kó']='Kórrá:BAAANQADCgMIAwAAAA==.',
La='Lachlann:BAAANQAECgUIDAAAAA==.Ladriel:BAAANQADCgcIBwABNQAECgkJFQAUAEcVAA==.Lakartó:BAACNQAFFH8FAAIZAAIKahg1CwCZAAAZAAIKahg1CwCZAAA1AAQKfy0ABBkACQq2HLMKAL8CABkACQpGG7MKAL8CAB0ABgqUG9cKALkBACIAAQpYH09JAFMAAAAA.Laleaf:BAAANQABCggIEAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgQIBQAAAA==.',
Ld='Ldritch:BAACNQAFFH8RAAMFAAUKVyFGCQBtAQAEAAQKeSDiBwB/AQAFAAQKUSFGCQBtAQA1AAQKfyIABAQACQpmJCAaAAUCAAQABgpaIyAaAAUCAAUABQryI+Q7ANwBAAwAAQo/GagZAEUAAAAA.',
Le='Leifson:BAAANQAECgUIBwAAAA==.Leonedis:BAAANQAECgQIEQAAAA==.Lethea:BAAANQADCgYICgAAAA==.Levious:BAAANQAECgcIEQAAAA==.',
Li='Lianara:BAAANQADCgQICwABNQAECgUICAABAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAACNQAFFH8KAAIWAAQK5h8BAwB3AQAWAAQK5h8BAwB3AQA1AAQKfywAAhYACQpvIQYGACUDABYACQpvIQYGACUDAAAA.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECn8lAAMgAAgKRRosEwBGAgAgAAgKRRosEwBGAgAXAAIKEgr+XQBiAAAAAA==.Luxurious:BAABNQAECn8WAAIfAAcKuwV7GwD+AAAfAAcKuwV7GwD+AAAAAA==.',
Ma='Maaca:BAAANQADCgYIDgAAAA==.Maecarepicha:BAAANQAECgUICgAAAA==.Magicmoose:BAAANQABCggIDAAAAA==.Malachor:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Maligned:BAAANQAECgcIDwAAAA==.Martichoux:BAAANQAECggIEwAAAA==.Mastakronik:BAAANQABCgMIAwAAAA==.Match:BAAANQAECgMIAwAAAA==.Mathas:BAABNQAECn8zAAQRAAkK/h8bDgBYAwARAAkK/h8bDgBYAwAHAAIKeAcqgQFQAAAQAAEKpw4FdgAlAAAAAA==.Mathilda:BAAANQAECgMIBAAAAA==.',
Mc='Mccholock:BAAANQAECgUIDwAAAA==.Mcmach:BAAANQAECgYICwAAAA==.',
Me='Meddox:BAEANQABCggIDgAAAA==.Mehaoloka:BAAANQADCgcICgAAAA==.Memelle:BAAANQAECgUIEAAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAAANQAECgUIDgAAAA==.Menotthatorc:BAAANQAECgIIAgABNQAFFAIIBgADAEgPAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAAANQAECgUIDgAAAA==.Mesilana:BAAANQADCggIDAAAAA==.Metrx:BAAANQAECgQIBAAAAA==.',
Mi='Mikosen:BAAANQAECgQIBAAAAA==.Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAAANQAECgUIEAAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.Mithian:BAAANQADCgMJAwAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgUIBgAAAA==.Monichan:BAAANQADCggICwAAAA==.Moosecheeks:BAAANQAECgcIEQAAAA==.Morganna:BAAANQABCggIDQAAAA==.Morior:BAAANQAECgUIDgAAAA==.Morslucifer:BAABNQAECn8XAAMnAAgKvBh4BQBoAgAnAAgKvBh4BQBoAgAaAAEKehMtcgA8AAAAAA==.Motorcade:BAABNQAECn8XAAIYAAcKVAOWHgD5AAAYAAcKVAOWHgD5AAAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQADCgYIDAAAAA==.',
My='Mypal:BAAANQAECgQICgAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
['Mû']='Mûrasaki:BAAANQABCgQIBQAAAA==.',
Na='Naula:BAAANQAECgEIAQAAAA==.',
Ne='Neather:BAAANQAECgYIEwAAAA==.Neron:BAAANQADCgUIDQAAAA==.Nezkima:BAAANQAECgUIBQABNQAECgkJKgAKAIYgAA==.',
Ni='Nidivh:BAAANQAECgMIBgAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAAANQAECgUIDQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAgAAAA==.Nira:BAABNQAECn8iAAINAAgKzxmBQQBiAgANAAgKzxmBQQBiAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAAANQAECgYIEQAAAA==.',
No='Nodöts:BAAANQAECggICAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Notdeadyet:BAAANQAECgUIDAAAAA==.Notron:BAAANQAECggIEQAAAA==.Noz:BAAANQADCgYIEQAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQABCgEIAwAAAA==.Nychophysis:BAAANQAECgUIEAAAAA==.Nyxion:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oakarm:BAAANQAECggICAAAAA==.Oasis:BAAANQAECgYIBwAAAA==.',
Od='Odyssius:BAAANQAECggIAQAAAA==.',
Og='Ogden:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Om='Omars:BAAANQAECgUICAAAAA==.',
On='Ontherun:BAAANQAECgIIAgAAAA==.',
Op='Oprawinfury:BAAANQAECgUICAAAAA==.',
Ou='Ourus:BAABNQAECn8zAAIkAAkKCiIsAwBvAwAkAAkKCiIsAwBvAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Panax:BAAANQAECgUIBwAAAA==.Paulo:BAAANQAECgUIEgAAAA==.',
Pe='Pele:BAAANQAECgUICQAAAA==.Pellito:BAAANQADCgQICAAAAA==.Perpetrator:BAABNQAECn8YAAIDAAcKuQO6gwDqAAADAAcKuQO6gwDqAAAAAA==.',
Pi='Picklez:BAAANQAECgcICwABNQAECgkJFQAhACYUAA==.Piki:BAABNQAECn8XAAIKAAgK6AnxhwByAQAKAAgK6AnxhwByAQAAAA==.',
Po='Poepwn:BAABNQAECn8eAAQgAAYKvwwaKwARAQAgAAYKvwwaKwARAQAYAAIKAQUBLwBBAAAXAAEKAACWdQAgAAAAAA==.',
Pr='Pray:BAAANQAECgYICAABNQAECgEIAQABAAAAAA==.Prescient:BAAANQAECggIBgAAAA==.',
Pu='Puffypanda:BAAANQAECgUICAAAAA==.Putnamehere:BAAANQABCgcICQAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quill:BAAANQAECggIEwAAAA==.',
Ra='Raging:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Ralz:BAABNQAECn8aAAICAAYK3RRkTwBvAQACAAYK3RRkTwBvAQAAAA==.Rangon:BAAANQADCggIDwAAAA==.Rannick:BAAANQAECgUIEAAAAA==.Ranua:BAAANQAECgUICQABNQAECgkJJAANAKYdAA==.Ratdemonmike:BAAANQAECgUIDQAAAA==.Rate:BAAANQAECgUICwABNQAECgkJIgAGAOEQAA==.Ratio:BAABNQAECn8iAAIGAAkK4RDlJQATAgAGAAkK4RDlJQATAgAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAAANQAECgEIAgAAAA==.',
Ri='Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgUIDQABNQAECgcIBwABAAAAAA==.',
Ru='Ruden:BAAANQAECgMIBQAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECggIDAABNQAECgkJKgAWAO0dAA==.',
Rw='Rwqr:BAABNQAECn8uAAIhAAgKKQwjQAC4AQAhAAgKKQwjQAC4AQAAAA==.',
['Rä']='Räiden:BAAANQAECgUIDwAAAA==.',
Sa='Salacake:BAAANQAECgQIBAAAAA==.Salacakei:BAABNQAECn8kAAMFAAgKthKDMQAUAgAFAAgKIRKDMQAUAgAEAAQKIA/ANQAGAQAAAA==.Salin:BAAANQAECgUICAAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFH8eAAIQAAcKyh7QAAClAgAQAAcKyh7QAAClAgA1AAQKfyIAAhAACQomJnwFAFYDABAACQomJnwFAFYDAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scarletpaw:BAAANQAECgEIAQAAAA==.Scoobie:BAAANQAECgEIAQABNQAECggIJQALAIwfAA==.Scoobydo:BAAANQAECgUIBwABNQAECggIJQALAIwfAA==.Scratches:BAAANQAECgIIBAAAAA==.Scrubs:BAACNQAFFH8GAAILAAQK3gNIGgDjAAALAAQK3gNIGgDjAAA1AAQKfygAAgsACQovGgk+AK4CAAsACQovGgk+AK4CAAAA.',
Se='Seider:BAAANQAECggICAAAAA==.Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadhunter:BAAANQABCgQIAgAAAA==.Shadpriest:BAAANQABCgIIAgABNQABCgQIAgABAAAAAA==.Shaggzy:BAACNQAFFH8WAAIXAAcK1BctAwA1AgAXAAcK1BctAwA1AgA1AAQKfy0AAhcACQreIzoHAFoDABcACQreIzoHAFoDAAAA.Shallabal:BAAANQAECggICAAAAA==.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAAANQAECgUIEAAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAAANQAECgUIDQAAAA==.Shockdoctor:BAABNQAECn8aAAMKAAgK+CJ6GwD/AgAKAAgK+CJ6GwD/AgAJAAMKTxQX9gChAAAAAA==.Shortrange:BAAANQADCgEJAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJKwARACokAA==.',
Sl='Sleples:BAABNQAECn8lAAILAAgKjB9KKQDxAgALAAgKjB9KKQDxAgAAAA==.Slufgor:BAAANQAECgQIBwAAAA==.Slyxxii:BAAANQAECgQIBAAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCgcIEgAAAA==.',
Sn='Snoo:BAAANQAECgQICwAAAA==.',
So='Solarlite:BAAANQAECgQIBAAAAA==.Solinari:BAAANQABCgIIBAAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAABNQAECn8aAAMNAAkKqCPWCAB7AwANAAkKqCPWCAB7AwAPAAIK8CS2FQDNAAAAAA==.Soulbreakër:BAABNQAECn8nAAICAAgK0Qz3RwCXAQACAAgK0Qz3RwCXAQAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYIDQAAAA==.Sparks:BAAANQAECgIIAgABNQAECgYIDwABAAAAAA==.Specimen:BAAANQADCggJEgAAAA==.Speddling:BAAANQAECgYIDwAAAA==.Spellgennce:BAAANQAECgQIBAAAAA==.Spicey:BAAANQADCgYIBgABNQAECgkJKgALABMeAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQAECgMIBAAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAAANQAECgUICgAAAA==.',
Sr='Srbranchmgr:BAAANQADCgMIBAAAAA==.',
St='Starbrow:BAABNQAECn8VAAILAAcKOyKxSgCLAgALAAcKOyKxSgCLAgAAAA==.Starrybeko:BAAANQABCgYIBgABNQAECgkJHwAVANsbAA==.Stilez:BAAANQAECggIBwABNQAECggIEAABAAAAAA==.Stormlight:BAAANQAECgUIDQAAAA==.Strudelmaker:BAAANQAECgMIAwABNQAECggIIQAhAGcZAA==.',
Su='Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAAANQAECgQIBwAAAA==.',
Sy='Syland:BAAANQAECgUIDQAAAA==.Sylvanäs:BAAANQAECgQICQAAAA==.Syrellina:BAAANQAECgQIBAABNQAECgkJJAANAKYdAA==.Sysna:BAABNQAECn8mAAMOAAgK7x8XEwDPAgAOAAcKhiQXEwDPAgANAAcKRCD/QQBgAgAAAA==.',
Ta='Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECn8dAAIKAAcKXBSFbQC/AQAKAAcKXBSFbQC/AQAAAA==.Tankwar:BAAANQADCgYIFwAAAA==.Targis:BAABNQAECn8hAAIjAAgKDw+rogDBAQAjAAgKDw+rogDBAQAAAA==.Tauran:BAAANQADCgcIDwAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECgkJJAANAKYdAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Tergar:BAAANQAECgEIAQAAAA==.',
Th='Thaleas:BAAANQAECgQIBwAAAA==.Thegreatkhal:BAAANQAECgUIDQAAAA==.Therizino:BAAANQADCgEIAQAAAA==.Thorizine:BAAANQAECgYIEAAAAA==.Thorlas:BAABNQAECn8bAAMKAAcKuiGGSgA1AgAKAAYKeiGGSgA1AgAJAAMKCxeN7AC3AAAAAA==.Thornado:BAAANQADCgMIAwAAAA==.Thotsfortots:BAAANQAECggIBQABNQAECggIGAATALcbAA==.Thylacoleo:BAAANQADCgUIBQAAAA==.',
Ti='Timmúk:BAABNQAECn8hAAIhAAgKZxnZKgBHAgAhAAgKZxnZKgBHAgAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAABAAAAAA==.Tomma:BAAANQAECggIDgAAAA==.Torment:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Torsion:BAAANQAECgcIEwAAAA==.',
Tr='Trailerpark:BAAANQADCgMJAwAAAA==.Tratre:BAABNQAECn8XAAMZAAcKWR7MDwBbAgAZAAcKWR7MDwBbAgAiAAIKcApiRwBgAAAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQAECgQIBwAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAcIEQAEAIwXAA==.Tust:BAAANQADCggIDgABNQADCgYICgABAAAAAA==.',
Ty='Tylandy:BAABNQAECn8iAAIVAAkKdSGfGQBvAwAVAAkKdSGfGQBvAwAAAA==.Tytaniormu:BAAANQAECgYIBwAAAA==.',
['Tê']='Tês:BAAANQAECgUICwAAAA==.',
Un='Undeadbetty:BAAANQADCgcICAAAAA==.Undeathtwoy:BAAANQAECgEIAQABNQAECggIJgAOAIscAA==.',
Va='Vaayl:BAAANQAECgUIDgAAAA==.Vaelraen:BAAANQAECgUICgAAAA==.Valcher:BAAANQAECgUICAAAAA==.Valendera:BAAANQAECggIEwAAAA==.Valerius:BAAANQAECgMIAwAAAA==.Valguero:BAAANQADCggICQAAAA==.Valifadin:BAAANQAECgUIEAAAAA==.Valndrevy:BAAANQADCggIFgAAAA==.Vamire:BAAANQAECggIEAAAAA==.Vanpèlt:BAAANQADCgUICQAAAA==.Vansan:BAABNQAECn8kAAMNAAkKph2JHwDvAgANAAkKph2JHwDvAgAOAAEKNAeLfAAuAAAAAA==.',
Ve='Venngennce:BAABNQAECn8vAAICAAkKAB82FQDfAgACAAkKAB82FQDfAgAAAA==.',
Vi='Viktir:BAAANQADCgYIDAABNQAECgUICQABAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Voladen:BAAANQAECgEIAQAAAA==.Vorkath:BAABNQAECn8lAAMZAAgKOiSHBQA3AwAZAAgKOiSHBQA3AwAiAAQKOwogOQDJAAAAAA==.Vormette:BAAANQADCggIFgAAAA==.',
Vt='Vtae:BAAANQAECgUIDAAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAABNQAECn8fAAIUAAcKlxAgMwB9AQAUAAcKlxAgMwB9AQAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Wo='Woxkal:BAABNQAECn8bAAQCAAcKswf/XwAdAQACAAcK1wX/XwAdAQAIAAMKAAZgtACCAAADAAMKegelrQBtAAAAAA==.',
Wu='Wubblebubble:BAAANQAECgYICgAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgUIDQAAAA==.',
Xu='Xuzhu:BAABNQAECn8WAAIVAAkKYxQDmABQAgAVAAkKYxQDmABQAgABNQAFFAUICAATAMAJAA==.',
Ye='Yelignar:BAAANQABCgEIAQAAAA==.',
Yi='Yinei:BAAANQAFFAIIAgAAAA==.',
Yl='Ylvis:BAABNQAECn8bAAILAAgKbhXXdgAfAgALAAgKbhXXdgAfAgAAAA==.',
Yo='Yol:BAABNQAECn8aAAIdAAkKngxSCgDKAQAdAAkKngxSCgDKAQAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECgcIHgAAAQ==.',
Yv='Yvetal:BAAANQAECgUICgABNQAFFAIIBgADAEgPAA==.',
Za='Zapdos:BAAANQADCggICAAAAA==.Zarion:BAACNQAFFH8OAAIUAAUKCx3xBADNAQAUAAUKCx3xBADNAQA1AAQKfyYAAxQACQpPI+oEAHMDABQACQpPI+oEAHMDABMAAQoAAKLBAB4AAAAA.Zarra:BAAANQAECgIJBAAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQIBAAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQADCgUIBQABNQAFFAUIDgAUAAsdAA==.Ziyar:BAAANQAECgMIBwABNQAFFAUIDgAUAAsdAA==.',
Zo='Zocorro:BAAANQAECgUICAAAAA==.',
Zy='Zypherdius:BAAANQAECgIIAgAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFH8ZAAIHAAUKghivCgCZAQAHAAUKghivCgCZAQA1AAQKfygAAgcACQrVIA06AOYCAAcACQrVIA06AOYCAAAA.',
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
