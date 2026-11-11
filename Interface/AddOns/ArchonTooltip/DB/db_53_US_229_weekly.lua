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
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaralyn:BAAANQAECgYIDwAAAA==.',
Ab='Abmikaze:BAABNQAECn8WAAIBAAkKCBhwBwAmAgABAAkKCBhwBwAmAgAAAA==.Absolon:BAAANQAECgEIAQABNQAECgUIDAACAAAAAA==.Abysseon:BAABNQAECn8eAAMDAAoK+Ro4MAAkAgADAAoK+Ro4MAAkAgAEAAMK2w2IqgB7AAAAAA==.',
Ac='Ace:BAABNQAECn8vAAMFAAoKWyFAJABlAgAFAAkKtR9AJABlAgAGAAMKNiK0bwDyAAABNQAECgEIBQACAAAAAA==.',
Ad='Adios:BAACNQAFFH8SAAIHAAcKuA1jBQDbAQAHAAcKuA1jBQDbAQA1AAQKf0AAAgcACgrGIgAKADkDAAcACgrGIgAKADkDAAAA.Adorean:BAABNQAECn8mAAIIAAoKeRGZoADgAQAIAAoKeRGZoADgAQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgUIEgAAAA==.Agrohn:BAABNQAECn8YAAMIAAcKQxSRuQCqAQAIAAcKQxSRuQCqAQAJAAEKrgKUNAEjAAAAAA==.',
Ai='Aimnskin:BAAANQAECgIIAgAAAA==.',
Al='Alcore:BAABNQAECn80AAQEAAoKpSFQIACxAgAEAAkK/CFQIACxAgADAAkKaBypGwBbAgAKAAYKaByeTADiAQAAAA==.Aliine:BAABNQAECn8mAAIEAAgKYQ6ASwAAAQAEAAgKYQ6ASwAAAQAAAA==.Ally:BAAANQAECgEIAQABNQAECgoKNwAHAEsdAA==.',
Am='Ameiisaa:BAABNQAECn8mAAMLAAgKqAgRlADnAAALAAcKzAQRlADnAAAMAAYKPAQP6QDFAAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQAECgEIAgAAAA==.Amytiel:BAACNQAFFH8MAAIMAAUKkBMkFQAmAQAMAAUKkBMkFQAmAQA1AAQKf10AAgwACgpwI9wHADYDAAwACgpwI9wHADYDAAAA.',
An='Anxie:BAABNQAECn8mAAINAAoKGwb1zwD4AAANAAoKGwb1zwD4AAAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAcIEwAOAEYZAA==.',
Ao='Aoifae:BAABNQAECn8VAAIIAAYKQRLAywCEAQAIAAYKQRLAywCEAQAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECn8ZAAQPAAkKnAk3gQCUAQAPAAgKGgo3gQCUAQAQAAcKewY1QAAtAQARAAEKMAVqLwAmAAAAAA==.Apprentice:BAABNQAECn8zAAISAAkKWgNANwDAAAASAAkKWgNANwDAAAAAAA==.',
Ar='Aramos:BAABNQAECn8tAAIJAAkKYRyNPQBuAgAJAAkKYRyNPQBuAgAAAA==.Aramôs:BAABNQAECn8XAAIJAAYKuR9lUQC8AQAJAAYKuR9lUQC8AQAAAA==.Aristania:BAAANQAECgIIAgAAAA==.Arkhangel:BAABNQAECn8ZAAIIAAgKJBiNeAA7AgAIAAgKJBiNeAA7AgAAAA==.Arta:BAABNQAECn8aAAMTAAcKNg9VIgDRAAATAAUKShFVIgDRAAAUAAIK5wbAJgEtAAAAAA==.Artavian:BAAANQAECgEIAQAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashes:BAAANQAECgEIAQAAAA==.Ashhealz:BAABNQAECn80AAIPAAkKvw6odwBbAQAPAAkKvw6odwBbAQAAAA==.Assiam:BAAANQADCgIIAgAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Au='Auberon:BAAANQAECgMIAwAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Ay='Ayame:BAAANQABCgMIBQAAAA==.',
Az='Azael:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.Azuzu:BAAANQAECgEIAQABNQAECgoKOAAEAP4XAA==.',
Ba='Badflood:BAAANQABCgQIBAAAAA==.Balacarn:BAAANQAECgIIBAAAAA==.Barlok:BAAANQAECgQIEAAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.Basicampfire:BAAANQAECgcICAABNQAECggIHwAVAM8IAA==.Bautumn:BAAANQAECgEIAQAAAA==.',
Be='Beaker:BAABNQAECn8zAAIWAAoKOx6uCQCVAgAWAAoKOx6uCQCVAgAAAA==.Beastmode:BAABNQAECn9KAAMXAAoKuRijGwAOAgAXAAoKuRijGwAOAgAYAAgK3hUhMABuAQAAAA==.Bedlem:BAAANQAECggIEAAAAA==.Beko:BAABNQAECn8yAAIZAAoKrhzwQwD8AgAZAAoKrhzwQwD8AgAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBwAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgUICwAAAA==.Bigs:BAAANQAECgEIBAAAAA==.Billydan:BAABNQAECn8rAAIaAAoK9w16KQCrAQAaAAoK9w16KQCrAQAAAA==.',
Bl='Blackhide:BAAANQABCgUIBgAAAA==.Blackpanthxr:BAABNQAECn84AAQLAAoK+xQwRwBFAgALAAoK+xQwRwBFAgAbAAcKghHWGQDHAQAMAAcKfAdXrgA2AQAAAA==.Blackvortex:BAAANQAECgQIBQAAAA==.Bloodgoat:BAAANQADCggICwAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECgkJHgAcAFkjAA==.Bloodyburst:BAABNQAECn8aAAMOAAgK2CKlBQCMAgAOAAcKEyOlBQCMAgAGAAIKDBywggCpAAABNQAECgkJHgAcAFkjAA==.Bloodyfistz:BAABNQAECn8eAAMcAAkKWSNhDgD5AgAcAAkKRCNhDgD5AgAdAAIKMyOyIgDDAAAAAA==.Blue:BAABNQAECn8qAAIMAAoKvxw/KwDTAgAMAAoKvxw/KwDTAgAAAA==.Bluethreetwo:BAAANQAECgQICAAAAA==.',
Bo='Bookofzeref:BAAANQAECgcIBwAAAA==.Boost:BAAANQAECgEIAQAAAA==.',
Br='Brayend:BAABNQAECn8lAAIbAAoKug1MEQDqAQAbAAoKug1MEQDqAQAAAA==.Brewguts:BAABNQAECn8cAAIeAAkK5xqnDABMAgAeAAkK5xqnDABMAgAAAA==.Brimscythe:BAABNQAECn88AAIfAAoKzR33BABoAgAfAAoKzR33BABoAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQAECgEIBAAAAA==.Caliandis:BAABNQAECn8iAAITAAgKGg6cGwAQAQATAAgKGg6cGwAQAQAAAA==.Calvey:BAAANQAECgYIDwAAAA==.Cambrai:BAABNQAECn8cAAIcAAgKfQ7EJQBUAQAcAAgKfQ7EJQBUAQAAAA==.Cannabelle:BAABNQAECn8sAAINAAoKLSBBHgAeAwANAAoKLSBBHgAeAwAAAA==.Carclias:BAACNQAFFH8JAAMgAAUKhgpBBwCCAAAhAAMKBAtjJQCQAAAgAAIKBwpBBwCCAAA1AAQKf1EAAyAACgoUHU8NACQCACAACQpsGE8NACQCACEACQolGFZYALcBAAAA.Carthrix:BAABNQAECn8iAAMUAAoKgg3CWgDbAQAUAAoKgg3CWgDbAQATAAEKAgLyRwAfAAAAAA==.Catbarf:BAAANQAECgYIAQABNQAECgoKMQAbALUeAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAABNQAECn8VAAINAAcKThElugAiAQANAAcKThElugAiAQAAAA==.',
Ce='Celery:BAABNQAECn8VAAMWAAcKMSNzDQBOAgAWAAcKMSNzDQBOAgAiAAUKngn7IwDEAAABNQAFFAcIHAAEAC4WAA==.Celindril:BAAANQADCggIDgAAAA==.Cellika:BAAANQAECgYIEQAAAA==.Cerdelz:BAAANQAECgQIBQAAAA==.',
Ch='Chanclatotem:BAAANQADCgIIAgAAAA==.Chaoscookies:BAABNQAECn9FAAMgAAoKNhYeEwDaAQAgAAcKsxYeEwDaAQAhAAgKMRFSdwBhAQAAAA==.Chaotik:BAAANQAECgEIAQAAAA==.Chartkov:BAAANQAECgYIDwAAAA==.Cheezee:BAACNQAFFH8TAAMZAAcKLhB9EADzAQAZAAYKzhN9EADzAQAjAAEKrwHVEQBLAAA1AAQKfx8AAhkACQoEJXkEAF8DABkACQoEJXkEAF8DAAAA.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQAECgMIAwAAAA==.Chilly:BAAANQAECgEIAQAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECgkJGAAMAGAWAA==.',
Ci='Cinderpetal:BAAANQAECgQICAAAAA==.Cisero:BAAANQAECgEIAQABNQAECggIGwAXANUNAA==.',
Ck='Ckay:BAAANQAECggIEAAAAA==.',
Cl='Clawsome:BAAANQADCggIEwAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYICAAAAA==.Cohemew:BAACNQAFFH8HAAMEAAMKSA/JIwBvAAADAAMK9wmUFwCEAAAEAAIKSA/JIwBvAAA1AAQKfyIABAMACgq3Gi8hAIQCAAMACQrRGC8hAIQCAAoABwoFFf5gAIwBAAQABApXFTaIAN4AAAE1AAUUBQgNACEAdRYA.Comlock:BAAANQADCgcIEwAAAA==.Complacent:BAABNQAECn8+AAIWAAoKTQWbMgDuAAAWAAoKTQWbMgDuAAAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgIIBQAAAA==.Coriander:BAABNQAECn8YAAIVAAkKlBJQCAAUAgAVAAkKlBJQCAAUAgAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAABNQAECn8aAAMYAAoKfhRgQgDtAQAYAAkKRhVgQgDtAQAXAAQKtRFTRADaAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAgIHQAcACAVAA==.',
Cy='Cynical:BAAANQAECgIIBQABNQAECgEIBQACAAAAAA==.Cyonicus:BAABNQAECn8mAAIhAAoK4BkRXABDAgAhAAoK4BkRXABDAgAAAA==.Cyska:BAABNQAECn84AAIEAAoK/heUJwCDAgAEAAoK/heUJwCDAgAAAA==.',
['Cé']='Cécé:BAABNQAECn8qAAIIAAkKDBkwaQBgAgAIAAkKDBkwaQBgAgAAAA==.',
['Cë']='Cëcë:BAAANQAECgMIAwAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAABNQAECn9bAAMPAAoKlxcDJwCgAgAPAAoKlxcDJwCgAgAQAAEKYAXZYAAvAAAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagaurie:BAAANQAECggICAABNQAECgoKIwAYAD4cAA==.Dagerlaurn:BAABNQAECn8jAAMYAAoKPhzDKACQAgAYAAoKPhzDKACQAgAXAAUKkhhmOgBMAQAAAA==.Dagevas:BAAANQAECgUIBQAAAA==.Dakeria:BAAANQADCgcIIQAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEQAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECn9OAAIBAAoKOBn4BgA2AgABAAoKOBn4BgA2AgABNQAFFAUIDQAIACUcAA==.Davriell:BAABNQAECn8zAAIDAAoKQRPfJQATAgADAAoKQRPfJQATAgAAAA==.Dax:BAABNQAECn8jAAINAAgKqw0HkQB3AQANAAgKqw0HkQB3AQAAAA==.Daxing:BAAANQADCggIFAABNQAECgoKLgAPAGMhAA==.',
De='Deeppurple:BAABNQAECn8VAAMkAAcKBwmGBQDeAAAkAAcKBwmGBQDeAAAZAAEKFQAvagEFAAAAAA==.Del:BAABNQAECn82AAIlAAoKXybeAQAPAwAlAAoKXybeAQAPAwABNQAECgoKNgAeAJwcAA==.Demoniaca:BAAANQAECgQIBQAAAA==.Demonic:BAAANQAECgUIDAABNQAECgEIBQACAAAAAA==.Demonshady:BAAANQAECgEIAQAAAA==.Demoraliziñg:BAAANQAECgEIAgABNQAECgkJKAAaAKcaAA==.Demostache:BAACNQAFFH8NAAMhAAUKdRYIEgAAAQAhAAQKfxoIEgAAAQAgAAIKWQpZBwCBAAA1AAQKfzcAAyEACgr6IzUuAM0CACEACQqwIzUuAM0CACAAAwqXEu8bAHoAAAAA.Derevi:BAAANQAECgEIAQAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECn82AAIMAAoKXCKFGwCEAgAMAAoKXCKFGwCEAgAAAA==.',
Di='Diivision:BAAANQAECgQIBgABNQAECgoKNwAHAEsdAA==.',
Do='Dolomite:BAABNQAECn8dAAIZAAoKegWLzAD+AAAZAAoKegWLzAD+AAAAAA==.Dorow:BAABNQAECn8yAAMYAAoKnBi8JQClAgAYAAoKnBi8JQClAgAXAAYKiBR3OAAdAQABNQAECgkJJAAcAIIXAA==.Dotabolt:BAABNQAECn8VAAIhAAcKyw+4nACeAQAhAAcKyw+4nACeAQABNQAECgoKJQAjAJwbAA==.',
Dr='Dracthyris:BAABNQAECn8tAAImAAkKXAySFQCDAQAmAAkKXAySFQCDAQAAAA==.Drag:BAAANQAECgQIBAAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Dreaa:BAAANQAECgEIAgAAAA==.Drinkme:BAAANQAECgEIAgAAAA==.Droki:BAABNQAECn8xAAIbAAoKtR58BwAGAwAbAAoKtR58BwAGAwAAAA==.',
Du='Dunsel:BAABNQAECn8eAAIJAAgKbg0PaABqAQAJAAgKbg0PaABqAQABNQAECgoKPAAfAM0dAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgYICgAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECn9BAAMUAAoKyxR6TgABAgAUAAoKyxR6TgABAgATAAIK/QnjPABRAAAAAA==.',
['Dã']='Dãnny:BAAANQADCggIDQABNQAECgoKQQAUAMsUAA==.',
Ea='Earendil:BAAANQAECggICAAAAA==.',
Eb='Ebonshade:BAAANQAECgQICgAAAA==.',
Ed='Edena:BAAANQAECgQIBQAAAA==.Edginglord:BAABNQAECn8dAAIHAAgKFQX+MQD0AAAHAAgKFQX+MQD0AAAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQABNQAECggIAQACAAAAAA==.Eloras:BAABNQAECn8cAAIMAAkK8xzdJQA8AgAMAAkK8xzdJQA8AgAAAA==.Elosien:BAAANQAECgUIBQABNQAECgkJJwAPAMgYAA==.Elunbi:BAABNQAECn9IAAMPAAoKNx3ZHgD1AgAPAAoKNx3ZHgD1AgARAAYKkhSZDQBZAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQAECgQICQAAAA==.',
Ep='Epsilòn:BAEBNQAECn8cAAQhAAkKVAzczwAqAQAhAAYKrxLczwAqAQAnAAEKTwvfKwA1AAAgAAgKFwAMiAAdAAAAAA==.',
Er='Ernest:BAABNQAECn8ZAAISAAgKmxdLIABVAQASAAgKmxdLIABVAQAAAA==.Errani:BAABNQAECn8uAAMjAAgKQg8dEQCVAQAjAAgKQg8dEQCVAQAZAAIKHQSGXQEoAAAAAA==.',
Es='Esheman:BAAANQAECgUIBgAAAA==.Esper:BAAANQAECgcIEAAAAA==.Esterlia:BAAANQAECgMIAwABNQAECgoKLgAPAGMhAA==.',
Et='Eternal:BAAANQAECgEIBQAAAA==.',
Eu='Eureki:BAABNQAECn8iAAIaAAoKdAnPMQB0AQAaAAoKdAnPMQB0AQAAAA==.',
Ev='Evilkarma:BAAANQAECggIEwAAAA==.Evocatis:BAACNQAFFH8NAAIIAAYKDRbhDwBOAQAIAAYKDRbhDwBOAQA1AAQKf0UABAgACgrwJeoFAGYDAAgACgrwJeoFAGYDAAkABApTDRvNAOEAABIAAQpgFyZdADcAAAAA.',
Ex='Exilion:BAAANQAECgYIEAAAAA==.',
Ey='Eyekonicklok:BAAANQAECgYICwABNQAECgQIBQACAAAAAA==.Eyesdeadeyed:BAACNQAFFH8IAAIoAAQKwAuMEgCpAAAoAAQKwAuMEgCpAAA1AAQKfzIAAygACgqMFoImABgCACgACgqMFoImABgCAA0AAQpbEGozAUYAAAAA.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAABNQAECn89AAMIAAoKJR3SRgDAAgAIAAoKJR3SRgDAAgAJAAYKExwLfwCcAQAAAA==.Faon:BAAANQAECgcIEAAAAA==.Farrea:BAAANQAECgQIBgABNQAECgUICQACAAAAAA==.Fatlock:BAAANQAECgQICgABNQAECgoKNgAcALkbAA==.Fayvia:BAAANQAECgQIBQAAAA==.',
Fe='Feebz:BAAANQAECgEIAQAAAA==.Feebzykun:BAAANQADCgEIAQAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECggIEgABNQAECgEIBQACAAAAAA==.Firebirdz:BAACNQAFFH8MAAIXAAYKnhLWCQBBAQAXAAYKnhLWCQBBAQA1AAQKfzQAAxcACgrgHiYTALQCABcACgrgHiYTALQCABgABQp3Ez9GAPcAAAAA.Firebirdzx:BAAANQAECgMICAABNQAFFAYIDAAXAJ4SAA==.',
Fl='Flappy:BAAANQAECgEIAgAAAA==.Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCggIEAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAABNQAECn9BAAIHAAoKURJHGQDTAQAHAAoKURJHGQDTAQAAAA==.Freshhéals:BAAANQAECgEIAQABNQAFFAYICAAOAMEQAA==.Friargark:BAAANQAECgIIAgAAAA==.Frizby:BAAANQAECgQIBwAAAA==.Frostypaw:BAAANQAECgQIBwAAAA==.',
Fu='Fuzzybut:BAABNQAECn8YAAIWAAcKbBq5GgDPAQAWAAcKbBq5GgDPAQAAAA==.',
Fy='Fyrelord:BAAANQAECgIIBAAAAA==.Fyuna:BAABNQAECn8zAAMLAAoK7Rw1LQCtAgALAAoK7Rw1LQCtAgAMAAEKmwZ//AAsAAAAAA==.',
Ga='Gark:BAAANQAECgYIEwAAAA==.Garkk:BAAANQADCgQIBAAAAA==.Garrumn:BAAANQADCgcIBwABNQAFFAUIDQAhAHUWAA==.Gazzi:BAABNQAECn8WAAIWAAkKcg6rHAC9AQAWAAkKcg6rHAC9AQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAgABNQAECgoKJAAPANIfAA==.',
Gi='Giuseppee:BAAANQAECgMIAwABNQAECgUICAACAAAAAA==.Gióvanna:BAAANQAECgYIEQAAAA==.',
Gl='Glodskegg:BAABNQAECn8WAAIgAAkKlBG9CQBcAgAgAAkKlBG9CQBcAgAAAA==.',
Go='Gobblious:BAAANQADCgYIBgAAAA==.Goldensea:BAAANQAECgQIDAAAAA==.Gondra:BAAANQABCgEIAQAAAA==.Gotenk:BAABNQAECn8eAAQiAAkKlCJYCQCzAgAiAAkKlCJYCQCzAgAXAAIKtxRcWwB0AAAYAAEK8AwggwA1AAAAAA==.Goyim:BAAANQAECgQIBgAAAA==.',
Gr='Gr:BAAANQADCggIHAAAAA==.Grissoul:BAAANQAECgYICgAAAA==.Grody:BAABNQAECn8UAAIhAAYKNQrm0wAiAQAhAAYKNQrm0wAiAQAAAA==.Gryms:BAAANQAECgYICwAAAA==.',
Gu='Guroo:BAABNQAECn8wAAINAAoKwQu2hgCPAQANAAoKwQu2hgCPAQAAAA==.Gutslammer:BAABNQAECn8fAAIJAAoKuhgQIwCZAgAJAAoKuhgQIwCZAgAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAwAAAA==.',
['Gí']='Gígí:BAAANQAECgIIBAAAAA==.Gíl:BAAANQAECgQIBAAAAA==.',
Ha='Hagarn:BAACNQAFFH8IAAIIAAMKow1oFgDKAAAIAAMKow1oFgDKAAA1AAQKfzEAAggACgrDFC18ADICAAgACgrDFC18ADICAAAA.Halastrin:BAAANQAECgEIAwAAAA==.Halimah:BAAANQAECgQIDgAAAA==.Halois:BAAANQADCgYIBgABNQAECggIHgAEADwSAA==.Handjabz:BAAANQAECgIIAgAAAA==.Hansong:BAAANQABCgQICAAAAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggIEAAAAA==.Harleypuddin:BAAANQAECggIAQAAAA==.Harleysmol:BAAANQAECgcIBwAAAA==.Harvestt:BAAANQADCgQIBAAAAA==.Hazan:BAABNQAECn8UAAIUAAkKfBVRmgA1AQAUAAkKfBVRmgA1AQABNQAECgoKMQAbALUeAA==.',
He='Hexmachine:BAABNQAECn8+AAIhAAoKFhdURwB8AgAhAAoKFhdURwB8AgAAAA==.',
Ho='Hole:BAAANQAECgEIAQAAAA==.Hollymagic:BAAANQAECgEIAQAAAA==.Holmstein:BAAANQADCggICAAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgQICwAAAA==.',
Hy='Hypertext:BAABNQAECn8ZAAIcAAkKZA/LLACzAQAcAAkKZA/LLACzAQAAAA==.',
Ia='Iamahriman:BAABNQAECn8nAAIMAAkKAAkMZABCAQAMAAkKAAkMZABCAQAAAA==.Iamarawn:BAABNQAECn8jAAINAAgKTQY7vACLAQANAAgKTQY7vACLAQAAAA==.Iamvanth:BAAANQAECgEIAQAAAA==.',
Ic='Icecreme:BAAANQAECgEIAQAAAA==.Icegoesbrr:BAAANQADCgEIAQAAAA==.',
Ig='Ignite:BAABNQAECn8/AAMZAAoKmiOgGQDVAgAZAAkKUSSgGQDVAgAjAAEKlh4sMQBZAAAAAA==.',
Il='Illestria:BAABNQAECn9LAAIIAAoKgxGKdQDPAQAIAAoKgxGKdQDPAQAAAA==.Illumiscotty:BAABNQAECn80AAQZAAoKQyVdDACkAwAZAAoKQyVdDACkAwAjAAMKzR7JHAAIAQAkAAEKIB6JCgBZAAAAAA==.',
Im='Imodium:BAAANQAECgIIAwAAAA==.',
In='Incognonetoo:BAAANQAECggICwABNQAECgoKGAAiAJMMAA==.Insania:BAABNQAECn8rAAMLAAoKGQYZbgBSAQALAAoKGQYZbgBSAQAMAAcKrAXy1gDmAAAAAA==.',
Io='Iol:BAAANQAECgEIAQAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
It='Itsrubio:BAAANQAECgIIAgAAAA==.',
Iz='Izara:BAAANQADCgYIJAAAAA==.',
Ja='Jab:BAAANQAECgEIAQAAAA==.Jamizi:BAAANQADCgcIBwAAAA==.Jasindra:BAAANQAECgQIBAABNQAECgoKLgAPAGMhAA==.Jaspally:BAAANQAECgcIDAABNQAECgoKLgAPAGMhAA==.Jastirri:BAAANQAECgUIDgAAAA==.Jayd:BAAANQAECggIAgAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgUIDgAAAA==.Jimothy:BAAANQADCggIJAABNQAECgUIDQACAAAAAA==.Jin:BAAANQAECgQICAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAABNQAECn8WAAMIAAkKaBJIpwDRAQAIAAkKIxBIpwDRAQASAAcKAQ2uOAAnAQAAAA==.',
Ju='Juicez:BAABNQAECn8WAAILAAUK8BnTegAsAQALAAUK8BnTegAsAQAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECggIDwAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIEwAAAA==.Katio:BAACNQAFFH8FAAIFAAIKPAqKGwCMAAAFAAIKPAqKGwCMAAA1AAQKf0cAAwUACgrOIaYaAKACAAUACgrSHKYaAKACAAYABQrjIgs2AAECAAAA.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAABNQAECn8kAAIUAAkKmQaeqgARAQAUAAkKmQaeqgARAQAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgQICAAAAA==.Kessandra:BAACNQAFFH8eAAMhAAcKsyIgAQC2AgAhAAcKsyIgAQC2AgAnAAEKAADeCABeAAA1AAQKfzMAAycACgrAJfMBANICACcACgp7JfMBANICACEABgq+IxKiAJEBAAAA.Kexally:BAAANQAECgUIEgAAAA==.Kexkan:BAAANQAECgEIAQABNQAECgUIEgACAAAAAA==.Kexxy:BAAANQADCgMIBQABNQAECgUIEgACAAAAAA==.Kezzia:BAAANQADCgcICgAAAA==.',
Kh='Khurri:BAABNQAECn8WAAIiAAkKQB30BwDcAgAiAAkKQB30BwDcAgAAAA==.',
Ki='Kiarah:BAAANQAECgIIBgAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQAECgEIAQAAAA==.Kirr:BAABNQAECn8vAAINAAoKiCJZDgAVAwANAAoKiCJZDgAVAwAAAA==.Kisor:BAAANQADCgQIBwAAAA==.Kitchenstink:BAABNQAECn8WAAIUAAkKHBGBigABAgAUAAkKHBGBigABAgAAAA==.',
Ko='Koifo:BAAANQABCgUIBgAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggIEAAAAA==.',
Kr='Kritanta:BAABNQAECn8eAAIEAAgKPBLzWACPAQAEAAgKPBLzWACPAQAAAA==.Krystallus:BAABNQAECn8rAAIYAAoKEhBMJwCuAQAYAAoKEhBMJwCuAQAAAA==.',
Ku='Kurnea:BAABNQAECn8oAAIJAAgKrCCMHQC+AgAJAAgKrCCMHQC+AgAAAA==.',
['Kó']='Kórrá:BAAANQAECgIIBAAAAA==.',
La='Lachlann:BAABNQAECn8hAAILAAgKOxDPbABWAQALAAgKOxDPbABWAQAAAA==.Ladriel:BAAANQADCgcIBwABNQAECgoKHwAXADQYAA==.Lakartó:BAACNQAFFH8KAAMfAAUKOBUiAwDPAAAfAAQKOBUiAwDPAAAmAAEKKQgBFwA/AAA1AAQKf0AABB8ACgqGHc8KAL4CAB8ACgqQHM8KAL4CABUABgqUG+wKALkBACYAAQpYHzRKAFMAAAAA.Laleaf:BAAANQAECgEIAQAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgUICgABNQAECgYIBgACAAAAAA==.Layderik:BAAANQABCgEIAQAAAA==.',
Ld='Ldritch:BAACNQAFFH8YAAMFAAcKUSEUBwCfAQAFAAYK6x0UBwCfAQAGAAUKViKTCQBsAQA1AAQKfzwABAUACgqHJfECAHADAAUACgqHJfECAHADAAYABgpiIek8ANwBAA4AAQo/GeIZAEUAAAAA.',
Le='Leifson:BAAANQAECgYIDgAAAA==.Leonedis:BAABNQAECn8rAAIUAAgKLwu2lgA9AQAUAAgKLwu2lgA9AQAAAA==.Lethea:BAAANQADCgYICgAAAA==.Levious:BAABNQAECn8sAAIIAAoKIBpIZQBrAgAIAAoKIBpIZQBrAgAAAA==.',
Li='Lianara:BAAANQADCgQICwABNQAECgUICwACAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lokren:BAAANQAECgQICAAAAA==.Lovedoctor:BAAANQAECgEIAgAAAA==.',
Lu='Ludo:BAACNQAFFH8RAAIbAAYKTSBvAQBbAQAbAAYKTSBvAQBbAQA1AAQKf04AAhsACgpRJXIBAFIDABsACgpRJXIBAFIDAAAA.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECn82AAMeAAoKnBxlEwBGAgAeAAoKnBxlEwBGAgAcAAcKWAtVLQAYAQAAAA==.Luxurious:BAABNQAECn8uAAIlAAgKHAdvFADxAAAlAAgKHAdvFADxAAAAAA==.',
['Lø']='Løøna:BAAANQAECgEIAQAAAA==.',
Ma='Maaca:BAAANQAECggICgAAAA==.Madeofhide:BAAANQADCgMIAwAAAA==.Maecarepicha:BAAANQAECgUIDgAAAA==.Magicmoose:BAAANQAECgUICQAAAA==.Mahi:BAAANQAECgQIBAAAAA==.Malachor:BAAANQADCgQIBAABNQAECgQIDAACAAAAAA==.Maligned:BAABNQAECn8XAAIKAAoKIQkSeQA2AQAKAAoKIQkSeQA2AQAAAA==.Martichoux:BAABNQAECn8WAAIZAAkK9ReChgBxAgAZAAkK9ReChgBxAgAAAA==.Mastakronik:BAAANQAECgEIAQAAAA==.Match:BAAANQAECgMIBQAAAA==.Mathas:BAABNQAECn87AAQJAAoKQB5ADgBYAwAJAAoKQB5ADgBYAwASAAQKZRDLNADNAAAIAAIKeAfXhgFQAAAAAA==.Mathilda:BAAANQAECgMIBAAAAA==.',
Mc='Mccholock:BAABNQAECn8fAAMBAAkKLREjEwBvAQABAAgKehEjEwBvAQAUAAYKtwiP1QC1AAAAAA==.Mcmach:BAABNQAECn8WAAIkAAcK3gvdAwBFAQAkAAcK3gvdAwBFAQAAAA==.',
Me='Meddox:BAEANQADCgQIBAAAAA==.Mehaoloka:BAAANQADCggIEQAAAA==.Memelle:BAABNQAECn8fAAIjAAgKiBEmEwB1AQAjAAgKiBEmEwB1AQAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAABNQAECn8eAAMWAAgKORBKKQAoAQAWAAgKORBKKQAoAQAXAAIKtQQBcQBCAAAAAA==.Menotthatorc:BAAANQAECgQIBAABNQAFFAUIDQAhAHUWAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAABNQAECn8kAAMPAAoK0h/iDQBgAwAPAAoK0h/iDQBgAwAQAAEKAAD/hwAiAAAAAA==.Mesilana:BAAANQAECgMIAwAAAA==.Metrx:BAAANQAECgUIBAAAAA==.',
Mi='Mikosen:BAAANQAECgYIDAAAAA==.Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAABNQAECn8nAAIPAAkKyBh3QQAdAgAPAAkKyBh3QQAdAgAAAA==.Misseymiss:BAAANQAECgIIAgABNQAECggIJgALAKgIAA==.Mithian:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgUIDgAAAA==.Monichan:BAAANQAECgYIDAAAAA==.Moosecheeks:BAABNQAECn8dAAIWAAoKHhkJEwAzAgAWAAoKHhkJEwAzAgAAAA==.Morganna:BAABNQAECn8ZAAIZAAoKugS20wDxAAAZAAoKugS20wDxAAAAAA==.Morior:BAABNQAECn8gAAIgAAgKgAwvCgAOAQAgAAgKgAwvCgAOAQAAAA==.Morslucifer:BAABNQAECn8cAAMnAAgKvBiKBQBoAgAnAAgKvBiKBQBoAgAgAAEKehPDcgA8AAAAAA==.Motorcade:BAABNQAECn83AAIdAAkKogNaEwDaAAAdAAkKogNaEwDaAAAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQAECgYICAAAAA==.',
My='Mypal:BAABNQAECn8nAAIIAAgKGAeh2gAQAQAIAAgKGAeh2gAQAQAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
['Mû']='Mûrasaki:BAAANQAECgEIAwAAAA==.',
Na='Nature:BAAANQAECgEIAgABNQAECgEIBQACAAAAAA==.Naula:BAAANQAECgQIBgAAAA==.',
Ne='Neather:BAABNQAECn8iAAIjAAoKgxeVCgAfAgAjAAoKgxeVCgAfAgAAAA==.Neron:BAAANQAECgEIAgAAAA==.Nexeon:BAAANQAECgcICgABNQAECgoKHgADAPkaAA==.Nezkima:BAAANQAECgUIBgABNQAECgoKQwALAHgiAA==.',
Ni='Nidivh:BAAANQAECgQIDwAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAABNQAECn8WAAIIAAYKgA8u4wBVAQAIAAYKgA8u4wBVAQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgMIBAAAAA==.Nira:BAABNQAECn8pAAIPAAoKMRiTQgBiAgAPAAoKMRiTQgBiAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAABNQAECn8XAAIiAAkKyxRuEgDXAQAiAAkKyxRuEgDXAQAAAA==.',
No='Nodöts:BAAANQAECggICQAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Nonetoo:BAABNQAECn8YAAIiAAoKkwyCFQBWAQAiAAoKkwyCFQBWAQAAAA==.Notdeadyet:BAABNQAECn8VAAINAAYK8Qex2ABPAQANAAYK8Qex2ABPAQAAAA==.Notron:BAABNQAECn8dAAIaAAoKJhpmJwBjAgAaAAoKJhpmJwBjAgAAAA==.Noz:BAAANQADCggIGgAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQAECgUIBgAAAA==.Nychophysis:BAABNQAECn8hAAMGAAgKsAy9OACjAAAFAAQK3gkyjwDWAAAGAAYKywy9OACjAAAAAA==.Nyxion:BAAANQADCggICgABNQAECgQICgACAAAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oakarm:BAAANQAECggICAAAAA==.Oasis:BAAANQAECggICgAAAA==.',
Od='Odyssius:BAAANQAECggIBwAAAA==.',
Og='Ogbamz:BAAANQADCgQIBAAAAA==.Ogden:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.',
Om='Omars:BAAANQAECgYICwAAAA==.',
On='Ontherun:BAAANQAECgUIDAAAAA==.',
Op='Oprawinfury:BAAANQAECgUICwAAAA==.',
Or='Orgazmik:BAAANQADCgYIDAAAAA==.Orphani:BAAANQABCgMIAQAAAA==.',
Ou='Ourus:BAABNQAECn9CAAITAAoKXiI4AwBvAwATAAoKXiI4AwBvAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Panax:BAAANQAECgUIEAAAAA==.Paulo:BAABNQAECn8bAAIIAAYKAgqF8gA3AQAIAAYKAgqF8gA3AQAAAA==.',
Pe='Pele:BAABNQAECn8bAAMXAAgK1Q1oLABvAQAXAAgK1Q1oLABvAQAYAAEKAACLzAAUAAAAAA==.Pellito:BAAANQADCgUICAAAAA==.Perpetrator:BAABNQAECn81AAIEAAgKCgbNSQAIAQAEAAgKCgbNSQAIAQAAAA==.',
Pi='Piki:BAABNQAECn8tAAILAAoKhg2ZXQCJAQALAAoKhg2ZXQCJAQAAAA==.',
Po='Poepwn:BAABNQAECn82AAQeAAkKlA8oFQCWAQAeAAkKlA8oFQCWAQAdAAYK+wbYGACXAAAcAAEKAACQdwAgAAAAAA==.',
Pr='Pray:BAABNQAECn8YAAIPAAkKeRxaJQCqAgAPAAkKeRxaJQCqAgABNQAECgEIBQACAAAAAA==.Prescient:BAAANQAECggIEAAAAA==.',
Pu='Puffypanda:BAABNQAECn8XAAIeAAcK8xVrFACjAQAeAAcK8xVrFACjAQAAAA==.Putnamehere:BAAANQAECgEIAgAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quadeshboy:BAAANQAECggIDgABNQAECgoKPwAZAJojAA==.Quill:BAABNQAECn8WAAIXAAkKmRlvFwCFAgAXAAkKmRlvFwCFAgAAAA==.',
Ra='Raging:BAAANQAECgIIAgABNQAECgEIBQACAAAAAA==.Ralz:BAABNQAECn8aAAIDAAYK3RT7UABvAQADAAYK3RT7UABvAQAAAA==.Rangon:BAAANQADCggIDwAAAA==.Rannick:BAABNQAECn8jAAMbAAgK3Az3GABrAQAbAAgK3Az3GABrAQALAAEK9QYKJQEoAAAAAA==.Ranua:BAAANQAECgUICwABNQAECgoKLgAPAGMhAA==.Ratdemonmike:BAABNQAECn8YAAIlAAcKhB5gCgCfAQAlAAcKhB5gCgCfAQAAAA==.Rate:BAABNQAECn8ZAAIaAAgKVRPDNABhAQAaAAgKVRPDNABhAQABNQAECgoKNwAHAEsdAA==.Ratio:BAABNQAECn83AAIHAAoKSx3qCwCIAgAHAAoKSx3qCwCIAgAAAA==.',
Re='Reecurve:BAAANQAECgEIAQAAAA==.Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAABNQAECn8cAAMhAAoKGRmkMAA9AgAhAAoKGRmkMAA9AgAgAAEKSg/uNQA0AAAAAA==.',
Ri='Richard:BAAANQAECgMIAwAAAA==.Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAABNQAECn8UAAMLAAcKUxlSfQCTAQALAAYK1xdSfQCTAQAMAAQK+woUqACjAAAAAA==.Rosary:BAAANQAECgQIBQABNQAECgEIBQACAAAAAA==.',
Ru='Rude:BAAANQAECgEIAgABNQAECgEIBQACAAAAAA==.Ruden:BAAANQAECgQIDAAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECggIDQABNQAECgoKMQAbALUeAA==.',
Rw='Rwqr:BAABNQAECn84AAIaAAkKHAvpQAC4AQAaAAkKHAvpQAC4AQAAAA==.',
['Rä']='Räiden:BAABNQAECn8pAAMjAAoKlBCfCgDcAQAjAAoKlBCfCgDcAQAZAAYKsAccOAEvAQAAAA==.',
Sa='Salacake:BAAANQAECgQIBAAAAA==.Salacakei:BAABNQAECn9AAAMGAAoKqBJRFgBuAQAFAAoK6Q/fPADyAQAGAAgKbxJRFgBuAQAAAA==.Salin:BAAANQAECgcIDwAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQAECgEIAQAAAA==.Sarthy:BAACNQAFFH8eAAISAAcKyh7VAAClAgASAAcKyh7VAAClAgA1AAQKfzYAAhIACgo+JmEBAG4DABIACgo+JmEBAG4DAAAA.Sassaphras:BAAANQAECgQIBgAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scaley:BAAANQAECgMIAgABNQAECgEIBQACAAAAAA==.Scarletpaw:BAAANQAECgEIAQAAAA==.Scoobie:BAAANQAECgEIAgABNQAECgoKRAANABAfAA==.Scoobydo:BAABNQAECn8XAAIaAAYK8BE9SQDuAAAaAAYK8BE9SQDuAAABNQAECgoKRAANABAfAA==.Scratches:BAAANQAECgQICgAAAA==.Scrubs:BAACNQAFFH8GAAINAAQK3gPlGgDjAAANAAQK3gPlGgDjAAA1AAQKf1UAAg0ACgqhH8wVAOcCAA0ACgqhH8wVAOcCAAAA.',
Se='Seider:BAAANQAECggIBgAAAA==.Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadhunter:BAAANQAECggIAQAAAA==.Shadmage:BAAANQAECgIIAgABNQAECggIAQACAAAAAA==.Shadpriest:BAAANQABCgIIAgABNQAECggIAQACAAAAAA==.Shaggzy:BAACNQAFFH8dAAIcAAgKIBVSAwA1AgAcAAgKIBVSAwA1AgA1AAQKf0cAAhwACgpdJcYDADYDABwACgpdJcYDADYDAAAA.Shallabal:BAAANQAECggICAAAAA==.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAABNQAECn8oAAMoAAkK1w0cHwBjAQANAAcKPRAotgCYAQAoAAkKngscHwBjAQAAAA==.Shelgon:BAAANQAECgQIBwAAAA==.Shiel:BAABNQAECn8YAAIiAAcK8RATHQAAAQAiAAcK8RATHQAAAQAAAA==.Shockdoctor:BAABNQAECn8rAAMLAAoK2iNgCACFAwALAAoK2iNgCACFAwAMAAMKTxR2+QCgAAAAAA==.Shootrmcgavn:BAAANQAECgQIBAABNQAECgQIBQACAAAAAA==.Shortrange:BAAANQADCgEIAQAAAA==.Shurples:BAAANQAECgEIAwABNQAECgkJKwAJACokAA==.',
Si='Sintotem:BAAANQAECgMIAwAAAA==.',
Sl='Sleples:BAABNQAECn9EAAINAAoKEB+eHwC0AgANAAoKEB+eHwC0AgAAAA==.Slufgor:BAAANQAECgYIEgAAAA==.Slyxxii:BAAANQAECgQIBAAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCggIFQAAAA==.',
Sn='Sniperbeko:BAAANQAECgEIAQABNQAECgoKMgAZAK4cAA==.Snoo:BAAANQAECgUIDgAAAA==.',
So='Solarlite:BAAANQAECgQICQAAAA==.Solinari:BAAANQABCgIIBAAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAABNQAECn8aAAMPAAkKqCMVCQB7AwAPAAkKqCMVCQB7AwARAAIK8CTpFQDNAAAAAA==.Soulbreakër:BAABNQAECn80AAIDAAkKcAw6SQCXAQADAAkKcAw6SQCXAQAAAA==.',
Sp='Spankymcbeat:BAAANQAECgEIAwAAAA==.Sparks:BAAANQAECgUIBwABNQAECgoKGgAYAH4UAA==.Specimen:BAAANQAECgEIAQAAAA==.Speddling:BAABNQAECn8dAAIZAAkKuw+01wDYAQAZAAkKuw+01wDYAQABNQAECgoKGgAYAH4UAA==.Spellgennce:BAAANQAECgQIBAAAAA==.Spicey:BAAANQADCgYIDAABNQAECgYICQACAAAAAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQAECgUIEQAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAABNQAECn8aAAINAAkK4AsHdwC0AQANAAkK4AsHdwC0AQAAAA==.',
Sr='Srbranchmgr:BAAANQADCgMIBAAAAA==.',
St='Starbrow:BAABNQAECn8cAAINAAgKaiIxTACJAgANAAgKaiIxTACJAgAAAA==.Starrybeko:BAAANQAECgEIAQABNQAECgoKMgAZAK4cAA==.Sticky:BAAANQAECgEIAQAAAA==.Stilez:BAAANQAECggIBwABNQAECggIEAACAAAAAA==.Stole:BAAANQAECgQIAwABNQAECgoKGgAYAH4UAA==.Stormlight:BAABNQAECn8jAAIXAAgK6w2zKQCFAQAXAAgK6w2zKQCFAQAAAA==.Strudelmaker:BAAANQAECgMIBwABNQAECgkJKAAaAKcaAA==.Stárrk:BAAANQADCgQIBAAAAA==.',
Su='Sumikka:BAAANQADCgQIBAAAAA==.Summernight:BAAANQAECgEIAQAAAA==.Sushistryke:BAABNQAECn8WAAINAAYKwgro1wDmAAANAAYKwgro1wDmAAAAAA==.',
Sv='Svetaköln:BAAANQADCgYIBgAAAA==.',
Sy='Syland:BAABNQAECn8YAAINAAcKewr3uQAjAQANAAcKewr3uQAjAQAAAA==.Sylvanäs:BAABNQAECn8cAAINAAUK5Apm8gAdAQANAAUK5Apm8gAdAQAAAA==.Syrellina:BAAANQAECgQIBAABNQAECgoKLgAPAGMhAA==.Sysna:BAABNQAECn8+AAMQAAoKQCNxCADRAgAQAAoKQCNxCADRAgAPAAcKRCAbQwBfAgAAAA==.',
Ta='Taiga:BAAANQADCgEIAQABNQAFFAUIDQAhAHUWAA==.Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECn8nAAILAAgKEhXKbgC/AQALAAgKEhXKbgC/AQAAAA==.Tankwar:BAAANQADCgYIFwAAAA==.Targis:BAABNQAECn8mAAIUAAoKzA2DpADBAQAUAAoKzA2DpADBAQAAAA==.Tauran:BAAANQAECgEIAwAAAA==.Tazanaz:BAAANQAECgUIBgABNQAECgoKLgAPAGMhAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwACAAAAAA==.Tergar:BAAANQAECgcICgAAAA==.Teâfâ:BAAANQADCgQIAgAAAA==.',
Th='Thaleas:BAABNQAECn8vAAQJAAoKRBBTXQCPAQAJAAkKXw5TXQCPAQASAAkKPRM6GwCBAQAIAAUKAg3u/wDUAAAAAA==.Thegreatkhal:BAABNQAECn8lAAIQAAgKfxgtHgCFAQAQAAgKfxgtHgCFAQAAAA==.Thequickness:BAAANQABCgYIBwAAAA==.Therizino:BAAANQADCgEIAQAAAA==.Thorizine:BAAANQAECgcIEAAAAA==.Thorlas:BAABNQAECn84AAMLAAoK6h9TDwAzAwALAAoK6h9TDwAzAwAMAAMKCxet7wC3AAAAAA==.Thornado:BAAANQAECgYICwAAAA==.Thotsfortots:BAAANQAECggICQABNQAECgoKIwAYAD4cAA==.Thylacoleo:BAAANQADCgUIBQAAAA==.',
Ti='Timmúk:BAABNQAECn8oAAIaAAkKpxp9KwBHAgAaAAkKpxp9KwBHAgAAAA==.',
To='Tolkorthuul:BAAANQAECgQICAABNQADCgcICAACAAAAAA==.Tomma:BAAANQAECggIEAAAAA==.Torment:BAAANQAECgQICAABNQAECgEIBQACAAAAAA==.Torsion:BAABNQAECn8bAAIMAAgKlRrYPACCAgAMAAgKlRrYPACCAgAAAA==.',
Tr='Trailerpark:BAAANQADCgMIAwAAAA==.Tratre:BAABNQAECn8lAAMfAAkKLBzvDwBaAgAfAAkKLBzvDwBaAgAmAAQKMg8kLQB+AAAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAABNQAECn8aAAIaAAcK7wiTSgDnAAAaAAcK7wiTSgDnAAAAAA==.',
Tu='Tub:BAAANQAECgEIAQAAAA==.Tucknroll:BAAANQAECgEIAQAAAA==.Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAgIEgAaAHoWAA==.Turd:BAAANQADCgcIBwAAAA==.Tust:BAAANQAECgUICgABNQAECgUIDQACAAAAAA==.',
Ty='Tylandy:BAABNQAECn85AAIZAAoKoiJaGgBsAwAZAAoKoiJaGgBsAwAAAA==.Tytaniormu:BAAANQAECgYICAAAAA==.',
['Tê']='Tês:BAAANQAECgUICwAAAA==.',
Un='Undeadbetty:BAAANQADCgcICAAAAA==.Undeathtwoy:BAAANQAFFAEIAQABNQAECgkJNAAQAGUcAA==.',
Va='Vaayl:BAABNQAECn8gAAIbAAoKQyAbBgDGAgAbAAoKQyAbBgDGAgAAAA==.Vaelraen:BAAANQAECgUIDQAAAA==.Valbrand:BAAANQAECgEIAQAAAA==.Valcher:BAABNQAECn8bAAMYAAcKIgU5WwCiAAAYAAcKIgU5WwCiAAAXAAEK4wNkgAAfAAAAAA==.Valendera:BAABNQAECn8WAAIhAAkKRAkdlAC0AQAhAAkKRAkdlAC0AQAAAA==.Valerius:BAAANQAECgcIDgAAAA==.Valguero:BAAANQADCggICwAAAA==.Valiant:BAAANQAECgYIBgABNQAFFAgIFQAYAKYQAA==.Valifadin:BAABNQAECn8oAAIpAAkKFB/cAwBEAgApAAkKFB/cAwBEAgAAAA==.Valndrevy:BAAANQADCggIHAAAAA==.Vamire:BAAANQAECggIEAAAAA==.Vanpèlt:BAAANQADCgYIFwAAAA==.Vansan:BAABNQAECn8uAAQPAAoKYyEjIADvAgAPAAoK/CAjIADvAgARAAEKKSAlEgBeAAAQAAIKwBBGXAA4AAAAAA==.',
Ve='Venngennce:BAABNQAECn83AAIDAAoKeh+zFQDeAgADAAoKeh+zFQDeAgAAAA==.Verran:BAAANQAECgEIAQAAAA==.',
Vi='Viktir:BAAANQAECgIIAgABNQAECggIGwAXANUNAA==.Vintage:BAAANQAECgcIDwAAAA==.',
Vo='Voided:BAAANQAECgQIBwAAAA==.Voladen:BAAANQAECgEIAwAAAA==.Vorkath:BAABNQAECn82AAMfAAoKTyOiBQA2AwAfAAoKTyOiBQA2AwAmAAUKGw9yJwCyAAAAAA==.Vormette:BAAANQADCggIGQAAAA==.',
Vt='Vtae:BAABNQAECn8gAAINAAgKDQj/ngBZAQANAAgKDQj/ngBZAQAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAABNQAECn88AAIXAAoKKRNCGQArAgAXAAoKKRNCGQArAgAAAA==.Westin:BAAANQADCgIIAgAAAA==.',
Wh='Whitedragon:BAAANQAECggIAgAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.',
Wo='Woxkal:BAABNQAECn8sAAQKAAkKeQgcPQAOAQADAAcK1wXlYQAdAQAKAAcKNAccPQAOAQAEAAUKlAe2fgBjAAAAAA==.',
Wu='Wubblebubble:BAABNQAECn8XAAIEAAoKHAcMTQD7AAAEAAoKHAcMTQD7AAAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAABNQAECn8YAAIPAAcKlxggbQDXAQAPAAcKlxggbQDXAQAAAA==.',
Xu='Xuzhu:BAABNQAECn8pAAIZAAoKeRdbmgBMAgAZAAoKeRdbmgBMAgABNQAFFAcIFQAYAFQbAA==.',
Ye='Yelignar:BAAANQAECgEIAQAAAA==.',
Yi='Yinei:BAAANQAFFAIIAgAAAA==.',
Yl='Ylvis:BAABNQAECn8fAAINAAoK8hR+eAAeAgANAAoK8hR+eAAeAgAAAA==.',
Yo='Yol:BAABNQAECn8aAAIVAAkKngxjCgDKAQAVAAkKngxjCgDKAQAAAA==.Yoliesha:BAAANQAECgEIAgAAAA==.Yoshymi:BAAANQAECggILAAAAQ==.',
Yu='Yukikaze:BAAANQABCgQIBAAAAA==.',
Yv='Yvetal:BAAANQAECgUIDAABNQAFFAUIDQAhAHUWAA==.',
Za='Zapdos:BAAANQADCggICAAAAA==.Zarion:BAACNQAFFH8WAAIXAAYKrB8bBQDNAQAXAAYKrB8bBQDNAQA1AAQKfyoAAxcACgrvIv0EAHMDABcACgrvIv0EAHMDABgAAQoAANvDAB4AAAAA.Zarra:BAAANQAECgQIBwAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQIBQAAAA==.Zetterberg:BAAANQAECggIAQAAAA==.Zextan:BAAANQABCgIIAgABNQAECgkJJAAaAOQJAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zh='Zhath:BAAANQAECgIIAwAAAA==.',
Zi='Zilik:BAAANQAFFAIIAgABNQAFFAYIFgAXAKwfAA==.Ziyar:BAAANQAECgQIDAABNQAFFAYIFgAXAKwfAA==.',
Zo='Zocorro:BAAANQAECgYIDQAAAA==.',
Zr='Zra:BAAANQADCgEIAQAAAA==.',
Zy='Zypherdius:BAAANQAECgQICQAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFH8aAAIIAAYKyRdfCwCTAQAIAAYKyRdfCwCTAQA1AAQKfzoAAggACgpRJR47AOUCAAgACgpRJR47AOUCAAAA.',
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
