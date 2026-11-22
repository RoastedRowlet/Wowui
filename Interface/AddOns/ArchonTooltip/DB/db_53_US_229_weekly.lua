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

local lookup = {'Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Protection','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Druid-Guardian','Druid-Restoration','Druid-Balance','Mage-Arcane','DemonHunter-Havoc','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Druid-Feral','Mage-Frost','Mage-Fire','DemonHunter-Vengeance','Evoker-Preservation','Warlock-Affliction','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaralyn:BAAANQAECgYIDwAAAA==.',
Ab='Abmikaze:BAABNQAECn8fAAIBAAkKohzMBACbAgABAAkKohzMBACbAgAAAA==.Absolon:BAAANQADCgMIAwABNQAECgUICgACAAAAAA==.Abysseon:BAABNQAECn8eAAMDAAoK+Ro4MAAkAgADAAoK+Ro4MAAkAgAEAAMK2w2IqgB7AAAAAA==.',
Ac='Ace:BAABNQAECn8vAAMFAAoKWyGmJwBkAgAFAAkKtR+mJwBkAgAGAAMKNiK0bwDyAAABNQAECgEIAQACAAAAAA==.',
Ad='Adios:BAACNQAFFH8SAAIHAAcKuA1jBQDbAQAHAAcKuA1jBQDbAQA1AAQKf0AAAgcACgrGIgAKADkDAAcACgrGIgAKADkDAAAA.Adorean:BAABNQAECn8pAAIIAAoKHBKZoADgAQAIAAoKHBKZoADgAQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgUIEgAAAA==.Agrohn:BAABNQAECn8YAAMIAAcKQxSRuQCqAQAIAAcKQxSRuQCqAQAJAAEKrgKUNAEjAAAAAA==.',
Ai='Aimnskin:BAAANQAECgIIAgAAAA==.',
Al='Alcore:BAABNQAECn82AAQEAAoKpSFQIACxAgAEAAkK/CFQIACxAgADAAoKaBwOHwBTAgAKAAYKaByeTADiAQAAAA==.Aliine:BAABNQAECn8mAAIEAAgKYQ4nUQD5AAAEAAgKYQ4nUQD5AAAAAA==.',
Am='Ameiisaa:BAABNQAECn8mAAMLAAgKqAiGnQDkAAALAAcKzASGnQDkAAAMAAYKPAQP6QDFAAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAACNQAFFH8PAAIMAAUKkBMkFQAmAQAMAAUKkBMkFQAmAQA1AAQKf2UAAgwACgrKI9MHADsDAAwACgrKI9MHADsDAAAA.',
An='Anxie:BAABNQAECn8mAAINAAoKGwZt3QD3AAANAAoKGwZt3QD3AAAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAgIFAAOADEYAA==.',
Ao='Aoifae:BAABNQAECn8VAAIIAAYKQRLAywCEAQAIAAYKQRLAywCEAQAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECn8ZAAQPAAkKnAk3gQCUAQAPAAgKGgo3gQCUAQAQAAcKewY1QAAtAQARAAEKMAVqLwAmAAAAAA==.Apprentice:BAABNQAECn86AAISAAkK9QMNNwDUAAASAAkK9QMNNwDUAAAAAA==.',
Ar='Aramos:BAABNQAECn8tAAIJAAkKYRyNPQBuAgAJAAkKYRyNPQBuAgAAAA==.Aramôs:BAABNQAECn8XAAIJAAYKuR/wVwC2AQAJAAYKuR/wVwC2AQAAAA==.Aristania:BAAANQAECgIIAgAAAA==.Arkhangel:BAABNQAECn8ZAAIIAAgKJBiNeAA7AgAIAAgKJBiNeAA7AgAAAA==.Arta:BAABNQAECn8bAAMTAAgKJA6BJQDOAAATAAUKShGBJQDOAAAUAAMK1wdeEwFVAAAAAA==.Artavian:BAAANQABCgIIAwAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAABNQAECn83AAIPAAkKvw7sfwCZAQAPAAkKvw7sfwCZAQAAAA==.Assiam:BAAANQADCgIIAgAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Au='Auberon:BAAANQAECgMIAwAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Ay='Ayame:BAAANQABCgMIBQAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECgoKOAAEAP4XAA==.',
Ba='Badflood:BAAANQABCgQIBAAAAA==.Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAABNQAECn8WAAINAAUK0gJZFwGEAAANAAUK0gJZFwGEAAAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.Basicampfire:BAAANQAECgUICwABNQAECggIHwAVAM8IAA==.Bautumn:BAAANQAECgEIAQAAAA==.',
Be='Beaker:BAABNQAECn81AAIWAAoKXR52CgCXAgAWAAoKXR52CgCXAgAAAA==.Beastmode:BAABNQAECn9KAAMXAAoKuRigHgALAgAXAAoKuRigHgALAgAYAAgK3hXiPQAJAgAAAA==.Bedlem:BAAANQAECggIDwAAAA==.Beko:BAABNQAECn8yAAIZAAoKrhzwQwD8AgAZAAoKrhzwQwD8AgAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBgAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgUICgAAAA==.Billydan:BAABNQAECn8rAAIaAAoK9w1YLQCoAQAaAAoK9w1YLQCoAQAAAA==.',
Bl='Blackhide:BAAANQABCgUIBgAAAA==.Blackpanthxr:BAABNQAECn84AAQLAAoK+xQwRwBFAgALAAoK+xQwRwBFAgAbAAcKghHWGQDHAQAMAAcKfAdXrgA2AQAAAA==.Blackvortex:BAAANQAECgQIBAAAAA==.Bloodgoat:BAAANQADCggICwAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECgkJHgAcAFkjAA==.Bloodyburst:BAABNQAECn8aAAMOAAgK2CKlBQCMAgAOAAcKEyOlBQCMAgAGAAIKDBywggCpAAABNQAECgkJHgAcAFkjAA==.Bloodyfistz:BAABNQAECn8eAAMcAAkKWSNhDgD5AgAcAAkKRCNhDgD5AgAdAAIKMyOyIgDDAAAAAA==.Blue:BAABNQAECn8qAAIMAAoKvxw/KwDTAgAMAAoKvxw/KwDTAgAAAA==.Bluethreetwo:BAAANQAECgQICAAAAA==.',
Bo='Bookofzeref:BAAANQAECgcIBwAAAA==.Boost:BAAANQABCgIIBAAAAA==.',
Br='Brayend:BAABNQAECn8lAAIbAAoKug3pEgDoAQAbAAoKug3pEgDoAQAAAA==.Brewguts:BAABNQAECn8cAAIeAAkK5xrmDQBEAgAeAAkK5xrmDQBEAgAAAA==.Brimscythe:BAABNQAECn88AAIfAAoKzR13BQBnAgAfAAoKzR13BQBnAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggIDgAAAA==.Caliandis:BAABNQAECn8iAAITAAgKGg4MHgAPAQATAAgKGg4MHgAPAQAAAA==.Calvey:BAAANQAECgYIDgAAAA==.Cambrai:BAABNQAECn8eAAIcAAkKRA+AIACaAQAcAAkKRA+AIACaAQAAAA==.Cannabelle:BAABNQAECn8sAAINAAoKLSBBHgAeAwANAAoKLSBBHgAeAwAAAA==.Carclias:BAACNQAFFH8JAAMgAAUKhgoUCACBAAAhAAMKBAv8KQCKAAAgAAIKBwoUCACBAAA1AAQKf1EAAyAACgoUHU8NACQCACAACQpsGE8NACQCACEACQolGAlgALUBAAAA.Carthrix:BAABNQAECn8iAAMUAAoKgg19YgDYAQAUAAoKgg19YgDYAQATAAEKAgJ9TAAfAAAAAA==.Catbarf:BAAANQAECgYIAQABNQAECgoKNAAbAN4eAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAABNQAECn8VAAINAAcKThE7yAAhAQANAAcKThE7yAAhAQAAAA==.',
Ce='Celery:BAABNQAECn8VAAMWAAcKMSOxDgBMAgAWAAcKMSOxDgBMAgAiAAUKngnCJwDEAAABNQAFFAcIHAAEAC4WAA==.Celindril:BAAANQADCggIDgAAAA==.Cellika:BAAANQAECgYIDwAAAA==.Cerdelz:BAAANQAECgQIBAAAAA==.',
Ch='Chanclatotem:BAAANQADCgIIAgAAAA==.Chaoscookies:BAABNQAECn9FAAMgAAoKNhYeEwDaAQAgAAcKsxYeEwDaAQAhAAgKMRH2gABfAQAAAA==.Chaotik:BAAANQABCgIIAgAAAA==.Chartkov:BAAANQAECgYIDwAAAA==.Cheezee:BAACNQAFFH8TAAMZAAcKLhB9EADzAQAZAAYKzhN9EADzAQAjAAEKrwHVEQBLAAA1AAQKfx8AAhkACQoEJWMFAFoDABkACQoEJWMFAFoDAAAA.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQAECgMIAwAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECgoKGwAMAKAWAA==.',
Ci='Cinderpetal:BAAANQAECgQICAAAAA==.',
Ck='Ckay:BAAANQAECggIDwAAAA==.',
Cl='Clawsome:BAAANQADCggIEwAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAACNQAFFH8HAAMEAAMKSA/JIwBvAAADAAMK9wmUFwCEAAAEAAIKSA/JIwBvAAA1AAQKfyIABAMACgq3Gi8hAIQCAAMACQrRGC8hAIQCAAoABwoFFf5gAIwBAAQABApXFTaIAN4AAAE1AAUUBQgNACEAdRYA.Comlock:BAAANQADCgcIEwAAAA==.Complacent:BAABNQAECn9GAAIWAAoKqQVFNQD2AAAWAAoKqQVFNQD2AAAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgMIBgAAAA==.Coriander:BAABNQAECn8YAAIVAAkKlBJQCAAUAgAVAAkKlBJQCAAUAgAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAABNQAECn8aAAMYAAoKfhRgQgDtAQAYAAkKRhVgQgDtAQAXAAQKtREzSQDaAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAgIHQAcACAVAA==.',
Cy='Cydnéy:BAAANQAECgEIAQAAAA==.Cynical:BAAANQAECgIIAwABNQAECgEIAQACAAAAAA==.Cyonicus:BAABNQAECn8sAAIhAAoKUxsRXABDAgAhAAoKUxsRXABDAgAAAA==.Cyska:BAABNQAECn84AAIEAAoK/heUJwCDAgAEAAoK/heUJwCDAgAAAA==.',
['Cé']='Cécé:BAABNQAECn8qAAIIAAkKDBkwaQBgAgAIAAkKDBkwaQBgAgAAAA==.',
['Cë']='Cëcë:BAAANQAECgMIAwAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAABNQAECn9mAAMPAAoKXhksIgDQAgAPAAoKXhksIgDQAgAQAAEKYAXUZgAvAAAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagaurie:BAAANQAECggICAABNQAECgoKIwAYAD4cAA==.Dagerlaurn:BAABNQAECn8jAAMYAAoKPhzDKACQAgAYAAoKPhzDKACQAgAXAAUKkhhmOgBMAQAAAA==.Dagevas:BAAANQAECgUIBQAAAA==.Dakeria:BAAANQADCgcIIQAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEAAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECn9SAAIBAAoKfBwBBQCTAgABAAoKfBwBBQCTAgABNQAFFAcIFAAIAL8iAA==.Davriell:BAABNQAECn80AAIDAAoKSxO/KQAPAgADAAoKSxO/KQAPAgAAAA==.Dax:BAABNQAECn8kAAINAAkKvg0WhACxAQANAAkKvg0WhACxAQAAAA==.Daxing:BAAANQADCggIFAABNQAECgoKLgAPAGMhAA==.',
De='Deeppurple:BAABNQAECn8VAAMkAAcKBwlFBgDeAAAkAAcKBwlFBgDeAAAZAAEKFQAEdAEFAAAAAA==.Del:BAABNQAECn85AAMlAAoKaCYEAgARAwAlAAoKaCYEAgARAwAaAAEKBiaAbQBxAAAAAA==.Demoniaca:BAAANQAECgQICQAAAA==.Demonic:BAAANQAECgUICwABNQAECgEIAQACAAAAAA==.Demonshady:BAAANQABCggIFAAAAA==.Demoraliziñg:BAAANQADCggIDgABNQAECgkJKAAaAKcaAA==.Demostache:BAACNQAFFH8NAAMhAAUKdRbHFQD4AAAhAAQKfxrHFQD4AAAgAAIKWQomCACAAAA1AAQKfzgAAyEACgr6IzUuAM0CACEACQqwIzUuAM0CACAAAwqXEhIeAHgAAAAA.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECn82AAIMAAoKXCKBHgB/AgAMAAoKXCKBHgB/AgAAAA==.',
Di='Diivision:BAAANQAECgQIBgABNQAECgoKNwAHAEsdAA==.',
Do='Dolomite:BAABNQAECn8dAAIZAAoKegW51gD9AAAZAAoKegW51gD9AAAAAA==.Dorow:BAABNQAECn8yAAMYAAoKnBi8JQClAgAYAAoKnBi8JQClAgAXAAYKiBT2PAAcAQAAAA==.Dotabolt:BAABNQAECn8VAAIhAAcKyw+4nACeAQAhAAcKyw+4nACeAQABNQAECgoKJQAjAJwbAA==.',
Dr='Dracthyris:BAABNQAECn8tAAImAAkKXAwoFwCCAQAmAAkKXAwoFwCCAQAAAA==.Drag:BAAANQAECggIEAAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Dreaa:BAAANQAECgEIAgAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECn80AAIbAAoK3h58BwAGAwAbAAoK3h58BwAGAwAAAA==.',
Du='Dunsel:BAABNQAECn8eAAIJAAgKbg2TcQBgAQAJAAgKbg2TcQBgAQABNQAECgoKPAAfAM0dAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgYICQAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECn9BAAMUAAoKyxQrVQD+AQAUAAoKyxQrVQD+AQATAAIK/QnjPABRAAAAAA==.',
['Dã']='Dãnny:BAAANQADCggIDQABNQAECgoKQQAUAMsUAA==.',
Ea='Earendil:BAAANQAECggICAAAAA==.',
Eb='Ebonshade:BAAANQAECgQICQAAAA==.',
Ed='Edena:BAAANQAECgQIBAAAAA==.Edginglord:BAABNQAECn8eAAIHAAgKiQUyNAD4AAAHAAgKiQUyNAD4AAAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAgAAAA==.Eloras:BAABNQAECn8cAAIMAAkK8xzuKQA4AgAMAAkK8xzuKQA4AgAAAA==.Elosien:BAAANQAECgUIBQABNQAECgkJJwAPAMgYAA==.Elunbi:BAABNQAECn9SAAMPAAoKhB7ZHgD1AgAPAAoKhB7ZHgD1AgARAAYKkhSZDQBZAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQAECgQIBQAAAA==.',
Ep='Epsilòn:BAEBNQAECn8cAAQhAAkKVAzczwAqAQAhAAYKrxLczwAqAQAnAAEKTwv5LgA1AAAgAAgKFwAMiAAdAAAAAA==.',
Er='Ernest:BAABNQAECn8aAAISAAkK5xeAGgCeAQASAAkK5xeAGgCeAQAAAA==.Errani:BAABNQAECn8uAAMjAAgKQg8dEQCVAQAjAAgKQg8dEQCVAQAZAAIKHQT9ZgEoAAAAAA==.',
Es='Esheman:BAAANQAECgUIBgAAAA==.Esper:BAAANQAECgYIDQAAAA==.Esterlia:BAAANQAECgMIAwABNQAECgoKLgAPAGMhAA==.',
Et='Eternal:BAAANQAECgEIAQAAAA==.',
Eu='Eureki:BAABNQAECn8oAAIaAAoK2glyMwCBAQAaAAoK2glyMwCBAQAAAA==.',
Ev='Evilkarma:BAAANQAECggIEgAAAA==.Evocatis:BAACNQAFFH8NAAIIAAYKDRbhDwBOAQAIAAYKDRbhDwBOAQA1AAQKf0UABAgACgrwJTEHAF8DAAgACgrwJTEHAF8DAAkABApTDRvNAOEAABIAAQpgF8tiADYAAAAA.',
Ex='Exilion:BAAANQAECgYIEAAAAA==.',
Ey='Eyekonicklok:BAAANQAECgYICwABNQAECgQIBAACAAAAAA==.Eyesdeadeyed:BAACNQAFFH8IAAIoAAQKwAtuFQCnAAAoAAQKwAtuFQCnAAA1AAQKfzIAAygACgqMFoImABgCACgACgqMFoImABgCAA0AAQpbEFpAAUYAAAAA.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAABNQAECn8+AAMIAAoKJR3SRgDAAgAIAAoKJR3SRgDAAgAJAAcKRhoLfwCcAQAAAA==.Faon:BAAANQAECgcIEAAAAA==.Faros:BAAANQAECgIIAgABNQAECgkJHQANALIgAA==.Farrea:BAAANQAECgQIBgABNQAECgUICQACAAAAAA==.Fatlock:BAAANQAECgQICQABNQAECgoKNgAcALkbAA==.Fayvia:BAAANQAECgQIBAAAAA==.',
Fe='Feebz:BAAANQADCgYIBwAAAA==.Feebzykun:BAAANQAECgUIBgAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECggIEAABNQAECgEIAQACAAAAAA==.Firebirdz:BAACNQAFFH8MAAIXAAYKnhLWCQBBAQAXAAYKnhLWCQBBAQA1AAQKfzQAAxcACgrgHiYTALQCABcACgrgHiYTALQCABgABQp3E7xKAPcAAAAA.Firebirdzx:BAAANQAECgMICAABNQAFFAYIDAAXAJ4SAA==.',
Fl='Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCggIEAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAABNQAECn9DAAIHAAoKpRIkGwDSAQAHAAoKpRIkGwDSAQAAAA==.Freshhéals:BAAANQAECgEIAQABNQAFFAYICAAOAMEQAA==.Friargark:BAAANQAECgIIAgAAAA==.Frizby:BAAANQAECgQIBwAAAA==.Frostypaw:BAAANQAECgQIBQAAAA==.',
Fu='Fuzzybut:BAABNQAECn8YAAIWAAcKbBq5GgDPAQAWAAcKbBq5GgDPAQAAAA==.',
Fy='Fyrelord:BAAANQAECgMIBAAAAA==.Fyuna:BAABNQAECn8zAAMLAAoK7Rw1LQCtAgALAAoK7Rw1LQCtAgAMAAEKmwY1CAEsAAAAAA==.',
Ga='Gark:BAAANQAECgYIEwAAAA==.Garkk:BAAANQADCgQIBAAAAA==.Garrumn:BAAANQADCgcIBwABNQAFFAUIDQAhAHUWAA==.Gazzi:BAABNQAECn8WAAIWAAkKcg6rHAC9AQAWAAkKcg6rHAC9AQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgoKJAAPANIfAA==.',
Gi='Giuseppee:BAAANQAECgMIAwABNQAECgUICAACAAAAAA==.Gióvanna:BAAANQAECgYIEQAAAA==.',
Gl='Glodskegg:BAABNQAECn8WAAIgAAkKlBG9CQBcAgAgAAkKlBG9CQBcAgAAAA==.',
Go='Gobblious:BAAANQADCgYIBgAAAA==.Goldensea:BAAANQAECgQICwAAAA==.Gondra:BAAANQABCgEIAQAAAA==.Gotenk:BAABNQAECn8eAAQiAAkKlCJYCQCzAgAiAAkKlCJYCQCzAgAXAAIKtxT0YABzAAAYAAEK8Aw9iQA1AAAAAA==.Goyim:BAAANQAECgQIBQAAAA==.',
Gr='Gr:BAAANQAECgEIAQAAAA==.Grissoul:BAAANQAECgYIBgAAAA==.Grody:BAABNQAECn8UAAIhAAYKNQrm0wAiAQAhAAYKNQrm0wAiAQAAAA==.Gryms:BAAANQAECgYICwAAAA==.',
Gu='Guroo:BAABNQAECn8wAAINAAoKwQtokwCOAQANAAoKwQtokwCOAQAAAA==.Gutslammer:BAABNQAECn8iAAIJAAoKuhiOKACIAgAJAAoKuhiOKACIAgAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
['Gí']='Gígí:BAAANQAECgIIBAAAAA==.Gíl:BAAANQAECgQIBQAAAA==.',
Ha='Hagarn:BAACNQAFFH8JAAIIAAQKow1aGQDHAAAIAAQKow1aGQDHAAA1AAQKfzIAAggACgrDFC18ADICAAgACgrDFC18ADICAAAA.Halastrin:BAAANQAECgEIAQAAAA==.Halimah:BAAANQAECgQICQAAAA==.Halois:BAAANQADCgYIBgABNQAECggIHgAEADwSAA==.Handjabz:BAAANQAECgIIAgAAAA==.Hansong:BAAANQAECgMIAwAAAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggIEAAAAA==.Harleypuddin:BAAANQAECggIAQAAAA==.Harleysmol:BAAANQAECgcIBwAAAA==.Harvestt:BAAANQADCgQIBAAAAA==.Hazan:BAABNQAECn8UAAIUAAkKfBWOpQAxAQAUAAkKfBWOpQAxAQABNQAECgoKNAAbAN4eAA==.',
He='Hexmachine:BAABNQAECn8+AAIhAAoKFhdURwB8AgAhAAoKFhdURwB8AgAAAA==.',
Ho='Hole:BAAANQADCgYIBgAAAA==.Hollymagic:BAAANQAECgEIAQAAAA==.Holmstein:BAAANQADCggICAAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgQIBgAAAA==.',
Hy='Hypertext:BAABNQAECn8ZAAIcAAkKZA/LLACzAQAcAAkKZA/LLACzAQAAAA==.',
Ia='Iamahriman:BAABNQAECn8tAAIMAAkKMQlAaQBMAQAMAAkKMQlAaQBMAQAAAA==.Iamarawn:BAABNQAECn8mAAINAAgKjwY7vACLAQANAAgKjwY7vACLAQAAAA==.Iamvanth:BAAANQAECgEIAQAAAA==.',
Ic='Icecreme:BAAANQABCgYIDgAAAA==.Icegoesbrr:BAAANQADCgEIAQAAAA==.',
Ig='Ignite:BAABNQAECn8/AAMZAAoKmiMyHADRAgAZAAkKUSQyHADRAgAjAAEKlh4QNQBXAAAAAA==.',
Il='Illestria:BAABNQAECn9LAAIIAAoKgxFbgQDKAQAIAAoKgxFbgQDKAQAAAA==.Illumiscotty:BAABNQAECn80AAQZAAoKQyVdDACkAwAZAAoKQyVdDACkAwAjAAMKzR7JHAAIAQAkAAEKIB6JCgBZAAAAAA==.',
Im='Imodium:BAAANQAECgIIAgAAAA==.',
In='Incognonetoo:BAAANQAECggICwABNQAECgoKHAAiAJsQAA==.Insania:BAABNQAECn8xAAMLAAoK9gaTcgBbAQALAAoK9gaTcgBbAQAMAAcKrAXy1gDmAAAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
It='Itsrubio:BAAANQAECgIIAgAAAA==.',
Iz='Izara:BAAANQADCgYIJAAAAA==.',
Ja='Jab:BAAANQABCgQIBAAAAA==.Jamizi:BAAANQADCgcIBwAAAA==.Jasindra:BAAANQAECgUIBQABNQAECgoKLgAPAGMhAA==.Jaspally:BAAANQAECgcIDAABNQAECgoKLgAPAGMhAA==.Jastirri:BAAANQAECgUIDAAAAA==.Jayd:BAAANQAECggIAgAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgUIDQAAAA==.Jimothy:BAAANQADCggIJAABNQAECgUIDQACAAAAAA==.Jin:BAAANQAECgQICAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAABNQAECn8WAAMIAAkKaBJIpwDRAQAIAAkKIxBIpwDRAQASAAcKAQ2uOAAnAQAAAA==.',
Ju='Juicez:BAABNQAECn8WAAILAAUK8Bl6hAAmAQALAAUK8Bl6hAAmAQAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECggIDgAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIEwAAAA==.Katio:BAACNQAFFH8IAAIFAAMKyA4nFADoAAAFAAMKyA4nFADoAAA1AAQKf0cAAwUACgrOIR8dAJ4CAAUACgrSHB8dAJ4CAAYABQrjIgs2AAECAAAA.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAABNQAECn8kAAIUAAkKmQaOtAAQAQAUAAkKmQaOtAAQAQAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgQICAAAAA==.Kessandra:BAACNQAFFH8eAAMhAAcKsyIgAQC2AgAhAAcKsyIgAQC2AgAnAAEKAADeCABeAAA1AAQKfzMAAycACgrAJR8CAA8DACcACgp7JR8CAA8DACEABgq+IxKiAJEBAAAA.Kexally:BAAANQAECgUIEgAAAA==.Kexkan:BAAANQAECgEIAQABNQAECgUIEgACAAAAAA==.Kexxy:BAAANQADCgMIBQABNQAECgUIEgACAAAAAA==.Kezzia:BAAANQADCgcICgAAAA==.',
Kh='Khurri:BAABNQAECn8WAAIiAAkKQB30BwDcAgAiAAkKQB30BwDcAgAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAABNQAECn8zAAINAAoKiCJpEQAKAwANAAoKiCJpEQAKAwAAAA==.Kisor:BAAANQADCgQIBwAAAA==.Kitchenstink:BAABNQAECn8WAAIUAAkKHBGBigABAgAUAAkKHBGBigABAgAAAA==.',
Ko='Koifo:BAAANQABCgUIBgAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggIEAAAAA==.',
Kr='Kritanta:BAABNQAECn8eAAIEAAgKPBLzWACPAQAEAAgKPBLzWACPAQAAAA==.Krystallus:BAABNQAECn8wAAIYAAoKExB6KQC0AQAYAAoKExB6KQC0AQAAAA==.',
Ku='Kurnea:BAABNQAECn8qAAIJAAkKnyCQFAAVAwAJAAkKnyCQFAAVAwAAAA==.',
['Kó']='Kórrá:BAAANQAECgIIAwAAAA==.',
La='Lachlann:BAABNQAECn8iAAILAAkKlRB1YgCQAQALAAkKlRB1YgCQAQAAAA==.Ladriel:BAAANQADCgcIBwABNQAECgoKHwAXADQYAA==.Lakartó:BAACNQAFFH8KAAMfAAUKOBWHAwDJAAAfAAQKOBWHAwDJAAAmAAEKKQhxGAA/AAA1AAQKf0IABB8ACgqGHc8KAL4CAB8ACgqQHM8KAL4CABUABgqUG+wKALkBACYAAQpYHzRKAFMAAAAA.Laleaf:BAAANQABCggIEAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgUICgABNQAECgYIBgACAAAAAA==.Layderik:BAAANQABCgEIAQAAAA==.',
Ld='Ldritch:BAACNQAFFH8YAAMFAAcKUSF2CACfAQAFAAYK6x12CACfAQAGAAUKViKTCQBsAQA1AAQKfzwABAUACgqHJSYDAHADAAUACgqHJSYDAHADAAYABgpiIek8ANwBAA4AAQo/GeIZAEUAAAAA.',
Le='Leifson:BAAANQAECggIEQAAAA==.Leonedis:BAABNQAECn8wAAIUAAgKBw3MkQBdAQAUAAgKBw3MkQBdAQAAAA==.Lethea:BAAANQADCgYICgAAAA==.Levious:BAABNQAECn8xAAIIAAoKiRpIZQBrAgAIAAoKiRpIZQBrAgAAAA==.',
Li='Lianara:BAAANQADCgQICwABNQAECgUICwACAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lokren:BAAANQAECgQIBwAAAA==.Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAACNQAFFH8RAAIbAAYKTSDIAQBTAQAbAAYKTSDIAQBTAQA1AAQKf1IAAhsACgp3JfUAAGwDABsACgp3JfUAAGwDAAAA.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECn84AAMeAAoKshxlEwBGAgAeAAoKshxlEwBGAgAcAAcKWAt9MAAYAQABNQAECgoKOQAlAGgmAA==.Luxurious:BAABNQAECn82AAIlAAgKbghEFQD9AAAlAAgKbghEFQD9AAAAAA==.',
Ma='Maaca:BAAANQAECggICgAAAA==.Madeofhide:BAAANQADCgMIAwAAAA==.Maecarepicha:BAAANQAECgUIDQAAAA==.Magicmoose:BAAANQAECgUICAAAAA==.Mahi:BAAANQAECgQIBAAAAA==.Mahiev:BAAANQAECgMIAwAAAA==.Malachor:BAAANQADCgQIBAABNQAECgQICQACAAAAAA==.Maligned:BAABNQAECn8XAAIKAAoKIQkSeQA2AQAKAAoKIQkSeQA2AQAAAA==.Martichoux:BAABNQAECn8WAAIZAAkK9ReChgBxAgAZAAkK9ReChgBxAgAAAA==.Mastakronik:BAAANQABCgMIBAAAAA==.Match:BAAANQAECgMIAwAAAA==.Mathas:BAABNQAECn87AAQJAAoKQB5ADgBYAwAJAAoKQB5ADgBYAwASAAQKZRDbOADLAAAIAAIKeAfXhgFQAAAAAA==.Mathilda:BAAANQAECgMIBAAAAA==.',
Mc='Mccholock:BAABNQAECn8fAAMBAAkKLREjEwBvAQABAAgKehEjEwBvAQAUAAYKtwgk4ACzAAAAAA==.Mcmach:BAABNQAECn8WAAIkAAcK3gtnBABDAQAkAAcK3gtnBABDAQAAAA==.',
Me='Meddox:BAEANQADCgQIBAAAAA==.Mehaoloka:BAAANQADCggIEQAAAA==.Memelle:BAABNQAECn8fAAIjAAgKiBEmEwB1AQAjAAgKiBEmEwB1AQAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAABNQAECn8eAAMWAAgKORATLQAnAQAWAAgKORATLQAnAQAXAAIKtQQBcQBCAAAAAA==.Menotthatorc:BAAANQAECgQIBAABNQAFFAUIDQAhAHUWAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAABNQAECn8kAAMPAAoK0h9qEABXAwAPAAoK0h9qEABXAwAQAAEKAAD/hwAiAAAAAA==.Mesilana:BAAANQAECgMIAwAAAA==.Metrx:BAAANQAECgUIBAAAAA==.',
Mi='Mikosen:BAAANQAECgYIDAAAAA==.Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAABNQAECn8nAAIPAAkKyBjGRgAdAgAPAAkKyBjGRgAdAgAAAA==.Misseymiss:BAAANQAECgIIAgABNQAECggIJgALAKgIAA==.Mithian:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgUIDwAAAA==.Monichan:BAAANQAECgYIDAAAAA==.Moosecheeks:BAABNQAECn8dAAIWAAoKHhkJEwAzAgAWAAoKHhkJEwAzAgAAAA==.Morganna:BAABNQAECn8ZAAIZAAoKugQJ3gDxAAAZAAoKugQJ3gDxAAAAAA==.Morior:BAABNQAECn8hAAIgAAkKsgwkCQA3AQAgAAkKsgwkCQA3AQAAAA==.Morslucifer:BAABNQAECn8cAAMnAAgKvBiKBQBoAgAnAAgKvBiKBQBoAgAgAAEKehPDcgA8AAAAAA==.Motorcade:BAABNQAECn8/AAIdAAkKtgN5FADeAAAdAAkKtgN5FADeAAAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQAECgYICAAAAA==.',
My='Mypal:BAABNQAECn8oAAIIAAkKfQenyQBDAQAIAAkKfQenyQBDAQAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
['Mû']='Mûrasaki:BAAANQABCgQIBwAAAA==.',
Na='Naula:BAAANQAECgQIBQAAAA==.',
Ne='Neather:BAABNQAECn8iAAIjAAoKgxeVCgAfAgAjAAoKgxeVCgAfAgAAAA==.Neron:BAAANQADCgUIDQAAAA==.Nexeon:BAAANQAECgcIDQABNQAECgoKHgADAPkaAA==.Nezkima:BAAANQAECgUIBQABNQAECgoKRQALAHgiAA==.',
Ni='Nidivh:BAAANQAECgQIDAAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAABNQAECn8WAAIIAAYKgA8u4wBVAQAIAAYKgA8u4wBVAQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgMIBAAAAA==.Nira:BAABNQAECn8pAAIPAAoKMRiTQgBiAgAPAAoKMRiTQgBiAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAABNQAECn8XAAIiAAkKyxRuEgDXAQAiAAkKyxRuEgDXAQAAAA==.',
No='Nodöts:BAAANQAECggICAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Nonetoo:BAABNQAECn8cAAIiAAoKmxBfEQCxAQAiAAoKmxBfEQCxAQAAAA==.Notdeadyet:BAABNQAECn8VAAINAAYK8Qex2ABPAQANAAYK8Qex2ABPAQAAAA==.Notron:BAABNQAECn8fAAIaAAoKbBpmJwBjAgAaAAoKbBpmJwBjAgAAAA==.Noz:BAAANQADCggIGgAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQAECgUIBQAAAA==.Nychophysis:BAABNQAECn8hAAMGAAgKsAxtOgCiAAAFAAQK3gmsmgDWAAAGAAYKywxtOgCiAAAAAA==.Nyxion:BAAANQADCggICgABNQAECgQICQACAAAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oakarm:BAAANQAECggICAAAAA==.Oasis:BAAANQAECggICAAAAA==.',
Og='Ogbamz:BAAANQADCgQIBAAAAA==.Ogden:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.',
Om='Omars:BAAANQAECgYICAAAAA==.',
On='Ontherun:BAAANQAECgUIDAAAAA==.',
Op='Oprawinfury:BAAANQAECgUICwAAAA==.',
Or='Orgazmik:BAAANQADCgYIEAAAAA==.Orphani:BAAANQABCgMIAQAAAA==.',
Ou='Ourus:BAABNQAECn9CAAITAAoKXiI4AwBvAwATAAoKXiI4AwBvAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Panax:BAAANQAECgYIEQAAAA==.Paulo:BAABNQAECn8bAAIIAAYKAgqF8gA3AQAIAAYKAgqF8gA3AQAAAA==.',
Pe='Pele:BAABNQAECn8bAAMXAAgK1Q2EMABsAQAXAAgK1Q2EMABsAQAYAAEKAACLzAAUAAAAAA==.Pellito:BAAANQADCgUICAAAAA==.Perpetrator:BAABNQAECn88AAIEAAgKcAYETgAFAQAEAAgKcAYETgAFAQAAAA==.',
Ph='Phredd:BAAANQAECgIIAgAAAA==.',
Pi='Piki:BAABNQAECn8tAAILAAoKhg0CZgCEAQALAAoKhg0CZgCEAQAAAA==.',
Po='Poepwn:BAABNQAECn89AAQeAAoKvg6qFAC5AQAeAAoKvg6qFAC5AQAdAAYK+waSGgCXAAAcAAEKAACQdwAgAAAAAA==.',
Pr='Pray:BAABNQAECn8YAAIPAAkKeRwHKgCjAgAPAAkKeRwHKgCjAgABNQAECgEIAQACAAAAAA==.Prescient:BAAANQAECggIEAAAAA==.',
Pu='Puffypanda:BAABNQAECn8XAAIeAAcK8xULFgCfAQAeAAcK8xULFgCfAQAAAA==.Putnamehere:BAAANQABCgcICQAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quadeshboy:BAAANQAECggIDgABNQAECgoKPwAZAJojAA==.Quill:BAAANQAECggIEwAAAA==.',
Ra='Raging:BAAANQAECgIIAgABNQAECgEIAQACAAAAAA==.Ralz:BAABNQAECn8aAAIDAAYK3RT7UABvAQADAAYK3RT7UABvAQAAAA==.Rangon:BAAANQADCggIDwAAAA==.Rannick:BAABNQAECn8jAAMbAAgK3AwKGwBpAQAbAAgK3AwKGwBpAQALAAEK9QYKJQEoAAAAAA==.Ranua:BAAANQAECgUICQABNQAECgoKLgAPAGMhAA==.Ratdemonmike:BAABNQAECn8YAAIlAAcKhB6ZCwCdAQAlAAcKhB6ZCwCdAQAAAA==.Rate:BAABNQAECn8ZAAIaAAgKVRNwOQBeAQAaAAgKVRNwOQBeAQABNQAECgoKNwAHAEsdAA==.Ratio:BAABNQAECn83AAIHAAoKSx00DQCAAgAHAAoKSx00DQCAAgAAAA==.',
Re='Reecurve:BAAANQAECgEIAQAAAA==.Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAABNQAECn8dAAMhAAoKGRmANgA3AgAhAAoKGRmANgA3AgAgAAEKSg+TOAA0AAAAAA==.',
Ri='Richard:BAAANQAECgMIAwAAAA==.Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgYIEQABNQAECggIDAACAAAAAA==.Rosary:BAAANQAECgQIBQABNQAECgEIAQACAAAAAA==.',
Ru='Ruden:BAAANQAECgQICQAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECggIDQABNQAECgoKNAAbAN4eAA==.',
Rw='Rwqr:BAABNQAECn84AAIaAAkKHAvpQAC4AQAaAAkKHAvpQAC4AQAAAA==.',
['Rä']='Räiden:BAABNQAECn8tAAMjAAoKHxGnCwDjAQAjAAoKHxGnCwDjAQAZAAYKsAccOAEvAQAAAA==.',
Sa='Salacake:BAAANQAECgQIBAAAAA==.Salacakei:BAABNQAECn9EAAMGAAoKZBPNFwBqAQAFAAoK+xB3PgADAgAGAAgKbxLNFwBqAQAAAA==.Salin:BAAANQAECgcIEAAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFH8eAAISAAcKyh7VAAClAgASAAcKyh7VAAClAgA1AAQKfzYAAhIACgo+Jo4BAGwDABIACgo+Jo4BAGwDAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scaley:BAAANQAECgMIAQABNQAECgEIAQACAAAAAA==.Scarletpaw:BAAANQAECgEIAQAAAA==.Scoobie:BAAANQAECgEIAgABNQAECgoKTQANALYfAA==.Scoobydo:BAABNQAECn8XAAIaAAYK8BGkTgDrAAAaAAYK8BGkTgDrAAABNQAECgoKTQANALYfAA==.Scratches:BAAANQAECgQICAAAAA==.Scrubs:BAACNQAFFH8GAAINAAQK3gPlGgDjAAANAAQK3gPlGgDjAAA1AAQKf14AAg0ACgrIIBoTAAADAA0ACgrIIBoTAAADAAAA.',
Se='Seider:BAAANQAECggIBgAAAA==.Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadmage:BAAANQAECgIIAgAAAA==.Shadpriest:BAAANQABCgIIAgABNQAECgIIAgACAAAAAA==.Shaggzy:BAACNQAFFH8dAAIcAAgKIBVSAwA1AgAcAAgKIBVSAwA1AgA1AAQKf0cAAhwACgpdJSkEADMDABwACgpdJSkEADMDAAAA.Shallabal:BAAANQAECggICAAAAA==.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAABNQAECn8oAAMoAAkK1w1vIQBhAQANAAcKPRAotgCYAQAoAAkKngtvIQBhAQAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAABNQAECn8YAAIiAAcK8RBKIAAAAQAiAAcK8RBKIAAAAQAAAA==.Shockdoctor:BAABNQAECn8rAAMLAAoK2iO2CQCAAwALAAoK2iO2CQCAAwAMAAMKTxR2+QCgAAAAAA==.Shootrmcgavn:BAAANQAECgQIBAABNQAECgQIBAACAAAAAA==.Shortrange:BAAANQADCgEIAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJKwAJACokAA==.',
Si='Sintotem:BAAANQAECgMIAwAAAA==.',
Sl='Sleples:BAABNQAECn9NAAINAAoKth96HwDCAgANAAoKth96HwDCAgAAAA==.Slufgor:BAAANQAECgYIEgAAAA==.Slyxxii:BAAANQAECgQIBAAAAA==.Slyyce:BAAANQAECgIIAgAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCggIFQAAAA==.',
Sn='Sniperbeko:BAAANQAECgEIAQABNQAECgoKMgAZAK4cAA==.Snoo:BAAANQAECgUICwAAAA==.',
So='Solarlite:BAAANQAECgQIBQAAAA==.Solinari:BAAANQABCgIIBAAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAABNQAECn8aAAMPAAkKqCMVCQB7AwAPAAkKqCMVCQB7AwARAAIK8CTpFQDNAAAAAA==.Soulbreakër:BAABNQAECn81AAIDAAkKHg06SQCXAQADAAkKHg06SQCXAQAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYIDQAAAA==.Sparks:BAAANQAECgUIBwABNQAECgoKGgAYAH4UAA==.Specimen:BAAANQADCggIEgAAAA==.Speddling:BAABNQAECn8dAAIZAAkKuw+01wDYAQAZAAkKuw+01wDYAQABNQAECgoKGgAYAH4UAA==.Spellgennce:BAAANQAECgQIBAAAAA==.Spicey:BAAANQADCgYIDAABNQAECgoKQQANAOcgAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQAECgUIEgAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAABNQAECn8aAAINAAkK4Au3gwCyAQANAAkK4Au3gwCyAQAAAA==.',
Sr='Srbranchmgr:BAAANQADCgMIBAAAAA==.',
St='Starbrow:BAABNQAECn8dAAINAAkKsiAxTACJAgANAAkKsiAxTACJAgAAAA==.Starrybeko:BAAANQABCgYIBgABNQAECgoKMgAZAK4cAA==.Sticky:BAAANQABCgIIAgAAAA==.Stilez:BAAANQAECggIBwABNQAECggIEAACAAAAAA==.Stole:BAAANQAECgQIAwABNQAECgoKGgAYAH4UAA==.Stormlight:BAABNQAECn8lAAIXAAkKFg1+KACsAQAXAAkKFg1+KACsAQAAAA==.Strudelmaker:BAAANQAECgMIAwABNQAECgkJKAAaAKcaAA==.Stárrk:BAAANQADCgQIBAAAAA==.',
Su='Sumikka:BAAANQADCgQIBAAAAA==.Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAABNQAECn8WAAINAAYKwgoj5QDmAAANAAYKwgoj5QDmAAAAAA==.',
Sv='Svetaköln:BAAANQADCgcIDgAAAA==.',
Sy='Syland:BAABNQAECn8YAAINAAcKewpFyAAhAQANAAcKewpFyAAhAQAAAA==.Sylvanäs:BAABNQAECn8cAAINAAUK5Apm8gAdAQANAAUK5Apm8gAdAQAAAA==.Syrellina:BAAANQAECgQIBAABNQAECgoKLgAPAGMhAA==.Sysna:BAABNQAECn8+AAMQAAoKQCMmCQDRAgAQAAoKQCMmCQDRAgAPAAcKRCAbQwBfAgAAAA==.',
Ta='Taiga:BAAANQADCgEIAQABNQAFFAUIDQAhAHUWAA==.Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECn8nAAILAAgKEhXKbgC/AQALAAgKEhXKbgC/AQAAAA==.Tankwar:BAAANQADCgYIFwAAAA==.Targis:BAABNQAECn8mAAIUAAoKzA2DpADBAQAUAAoKzA2DpADBAQAAAA==.Tauran:BAAANQADCgcIDwAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECgoKLgAPAGMhAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwACAAAAAA==.Tergar:BAAANQAECgcICgAAAA==.Teâfâ:BAAANQADCgQIAgAAAA==.',
Th='Thaleas:BAABNQAECn82AAQSAAoKvRWrGACxAQASAAkKOBarGACxAQAJAAkKXw4UZgCFAQAIAAUKAg0CEAHRAAAAAA==.Thegreatkhal:BAABNQAECn8nAAIQAAkKcBdUGgDJAQAQAAkKcBdUGgDJAQAAAA==.Thequickness:BAAANQABCgYIBwAAAA==.Therizino:BAAANQADCgEIAQAAAA==.Thorizine:BAAANQAECgYIEAAAAA==.Thorlas:BAABNQAECn8/AAMLAAoK8B8tDABjAwALAAoK8B8tDABjAwAMAAMKCxet7wC3AAAAAA==.Thornado:BAAANQAECgYICwAAAA==.Thotsfortots:BAAANQAECggICQABNQAECgoKIwAYAD4cAA==.Thylacoleo:BAAANQADCgUIBQAAAA==.',
Ti='Timmúk:BAABNQAECn8oAAIaAAkKpxp9KwBHAgAaAAkKpxp9KwBHAgAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAACAAAAAA==.Tomma:BAAANQAECggIDgAAAA==.Torment:BAAANQAECgQIBwABNQAECgEIAQACAAAAAA==.Torsion:BAABNQAECn8bAAIMAAgKlRrYPACCAgAMAAgKlRrYPACCAgAAAA==.',
Tr='Trailerpark:BAAANQADCgMIAwAAAA==.Tratre:BAABNQAECn8lAAMfAAkKLBzvDwBaAgAfAAkKLBzvDwBaAgAmAAQKMg+ELwB/AAAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAABNQAECn8aAAIaAAcK7wjqTwDlAAAaAAcK7wjqTwDlAAAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAgIEgAaAHoWAA==.Turd:BAAANQADCgcIBwAAAA==.Tust:BAAANQAECgUICgABNQAECgUIDQACAAAAAA==.',
Ty='Tylandy:BAABNQAECn8/AAIZAAoKoiJaGgBsAwAZAAoKoiJaGgBsAwAAAA==.Tytaniormu:BAAANQAECgYIBwAAAA==.',
['Tê']='Tês:BAAANQAECgUICwAAAA==.',
Un='Undeadbetty:BAAANQADCgcICAAAAA==.Undeathtwoy:BAAANQAFFAEIAQABNQAECgkJNAAQAGUcAA==.',
Va='Vaayl:BAABNQAECn8gAAIbAAoKQyDqBgC+AgAbAAoKQyDqBgC+AgAAAA==.Vaelraen:BAAANQAECgUICgAAAA==.Valcher:BAABNQAECn8bAAMYAAcKIgVOYACiAAAYAAcKIgVOYACiAAAXAAEK4wNkgAAfAAAAAA==.Valendera:BAABNQAECn8WAAIhAAkKRAkdlAC0AQAhAAkKRAkdlAC0AQAAAA==.Valerius:BAAANQAECggIDQAAAA==.Valguero:BAAANQADCggICwAAAA==.Valiant:BAAANQAECgUICgABNQAFFAgIFQAYAKYQAA==.Valifadin:BAABNQAECn8uAAIpAAoKBhx5AwBwAgApAAoKBhx5AwBwAgAAAA==.Valndrevy:BAAANQADCggIHAAAAA==.Vamire:BAAANQAECggIEAAAAA==.Vanpèlt:BAAANQADCgYIFwAAAA==.Vansan:BAABNQAECn8uAAQPAAoKYyEjIADvAgAPAAoK/CAjIADvAgARAAEKKSBbEwBeAAAQAAIKwBAYYgA4AAAAAA==.',
Ve='Vellas:BAAANQABCggIDAAAAA==.Venngennce:BAABNQAECn83AAIDAAoKeh+zFQDeAgADAAoKeh+zFQDeAgAAAA==.Verran:BAAANQAECgEIAQAAAA==.',
Vi='Viktir:BAAANQAECgIIAgABNQAECggIGwAXANUNAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Voladen:BAAANQAECgEIAQAAAA==.Vorkath:BAABNQAECn84AAMfAAoKliOiBQA2AwAfAAoKliOiBQA2AwAmAAUKGw8JKgCvAAAAAA==.Vormette:BAAANQADCggIGQAAAA==.',
Vt='Vtae:BAABNQAECn8iAAINAAkKqghIjgCaAQANAAkKqghIjgCaAQAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAABNQAECn9GAAMXAAoKKRPeGwAqAgAXAAoKKRPeGwAqAgAiAAUKhg6XLQChAAAAAA==.Westin:BAAANQADCgIIAgAAAA==.',
Wh='Whitedragon:BAAANQAECggIAgAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.',
Wo='Woxkal:BAABNQAECn8wAAQKAAoKMQiUQAANAQADAAcK1wXlYQAdAQAKAAcKNAeUQAANAQAEAAcK3geBXADPAAAAAA==.',
Wu='Wubblebubble:BAABNQAECn8XAAIEAAoKHAcYUgD1AAAEAAoKHAcYUgD1AAAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAABNQAECn8YAAIPAAcKlxggbQDXAQAPAAcKlxggbQDXAQAAAA==.',
Xu='Xuzhu:BAABNQAECn8pAAIZAAoKeRdbmgBMAgAZAAoKeRdbmgBMAgABNQAFFAcIFQAYAFQbAA==.',
Ye='Yelignar:BAAANQABCgEIAQAAAA==.',
Yi='Yinei:BAAANQAFFAIIAgAAAA==.',
Yl='Ylvis:BAABNQAECn8fAAINAAoK8hR+eAAeAgANAAoK8hR+eAAeAgAAAA==.',
Yo='Yol:BAABNQAECn8aAAIVAAkKngxjCgDKAQAVAAkKngxjCgDKAQAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECggILQAAAQ==.',
Yu='Yukikaze:BAAANQABCgQIBAAAAA==.',
Yv='Yvetal:BAAANQAECgUIDAABNQAFFAUIDQAhAHUWAA==.',
Za='Zapdos:BAAANQADCggICAAAAA==.Zarion:BAACNQAFFH8WAAIXAAYKrB8bBQDNAQAXAAYKrB8bBQDNAQA1AAQKfyoAAxcACgrvIv0EAHMDABcACgrvIv0EAHMDABgAAQoAANvDAB4AAAAA.Zarra:BAAANQAECgQIBgAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQIBAAAAA==.Zetterberg:BAAANQAECggIAQAAAA==.Zextan:BAAANQABCgIIAgABNQAECgoKJwAaAAoKAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQAFFAIIAgABNQAFFAYIFgAXAKwfAA==.Ziyar:BAAANQAECgQICgABNQAFFAYIFgAXAKwfAA==.',
Zo='Zocorro:BAAANQAECgYIDQAAAA==.',
Zr='Zra:BAAANQADCgEIAQAAAA==.',
Zy='Zypherdius:BAAANQAECgYICwAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFH8cAAIIAAgKDRlfCwCTAQAIAAgKDRlfCwCTAQA1AAQKfzoAAggACgpRJR47AOUCAAgACgpRJR47AOUCAAAA.',
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
