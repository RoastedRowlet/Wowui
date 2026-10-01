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

local lookup = {'Shaman-Restoration','Warlock-Demonology','Hunter-BeastMastery','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Rogue-Assassination','Paladin-Protection','DeathKnight-Unholy','DemonHunter-Devourer','Unknown-Unknown','Priest-Holy','Priest-Shadow','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Rogue-Outlaw','Shaman-Elemental','Warrior-Arms','DeathKnight-Frost','DemonHunter-Havoc','Warrior-Fury','Shaman-Enhancement','Mage-Arcane','Mage-Frost','Druid-Balance','Warrior-Protection','DeathKnight-Blood','Monk-Mistweaver','Druid-Feral','Evoker-Augmentation','Druid-Restoration','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety','DemonHunter-Vengeance',}
local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aarg:BAAANQAECggICAAAAA==.',
Ab='Abcede:BAAANQAECgMIAwABNQAECgkJIgABAOAcAA==.',
Ac='Accio:BAAANQAECgQIBAAAAA==.Achillguy:BAAANQADCgUIBQAAAA==.',
Ad='Adaa:BAAANQAECgEJAQAAAA==.',
Ae='Aeava:BAAANQABCgMIAwABNQAECgYIHQACAMcKAA==.Aelene:BAAANQAECgMIAwAAAA==.',
Ag='Agnostic:BAABNQAECoEhAAIDAAkKaR3DIwDPAgADAAkKaR3DIwDPAgAAAA==.Agonybehold:BAAANQADCgUICgAAAA==.',
Ai='Aisa:BAACNQAFFIEbAAQEAAcKZBxpAwDTAAACAAQKXBefCAB9AQAEAAIKmyRpAwDTAAAFAAEKFyAMBQBhAAA1AAQKgSAABAQACQo2JboKADoCAAQABgooI7oKADoCAAIABgq7I8JMACcCAAUAAQpdJLwbAGYAAAAA.Aish:BAACNQAFFIEbAAIGAAcK/R9xAAC3AgAGAAcK/R9xAAC3AgA1AAQKgRoAAgYACQq8JhYJAJ4DAAYACQq8JhYJAJ4DAAAA.Aiso:BAAANQABCggIEwAAAA==.',
Ak='Akali:BAACNQAFFIEKAAIHAAQKcSaQAgDPAQAHAAQKcSaQAgDPAQA1AAQKgTgAAgcACArwJkYCAKIDAAcACArwJkYCAKIDAAAA.',
Al='Alakazami:BAAANQADCgEIAQAAAA==.Aldofio:BAAANQAECgQIBwAAAA==.Alhttabe:BAABNQAECoEZAAIIAAcKBCMdCwCoAgAIAAcKBCMdCwCoAgAAAA==.Alirann:BAAANQAFFAIIAwAAAA==.Alisu:BAAANQAECgQIBAABNQAECgkJHAAJAAIeAA==.Alvln:BAACNQAFFIEIAAIKAAUKtATGBgBJAQAKAAUKtATGBgBJAQA1AAQKgS0AAgoACQoWIBQGAF8DAAoACQoWIBQGAF8DAAAA.',
An='Anduïn:BAAANQADCgIIAgABNQAECgcIHgAGABcZAA==.Andyrios:BAAANQAECgQICAAAAA==.',
Ap='Apoplectic:BAAANQAECgYIEAAAAA==.',
Aq='Aquaila:BAAANQADCgcIBwABNQAECgIJAwALAAAAAA==.',
Ar='Aradesya:BAAANQAECgUIBQAAAA==.Aradinya:BAAANQADCggICAAAAA==.Arahat:BAAANQAECgYIBwAAAA==.Arakinya:BAAANQAECgcIEQAAAA==.Aralinya:BAACNQAFFIEIAAIMAAUK+BgcCADAAQAMAAUK+BgcCADAAQA1AAQKgSoAAwwACQpOFwY8ADECAAwACQpOFwY8ADECAA0ACArHEcMfAPABAAAA.Aratus:BAAANQAECgcIDgAAAA==.Ardentflame:BAABNQAECoEVAAMCAAcK/xDlcAC0AQACAAcK/xDlcAC0AQAFAAEKjA77JAA8AAAAAA==.Arindel:BAAANQADCgIIAgAAAA==.Arsoul:BAAANQADCgIIAgAAAA==.',
As='Asperonia:BAACNQAFFIEbAAIOAAcKQAm+AgApAgAOAAcKQAm+AgApAgA1AAQKgSQAAg4ACQrhGWIeAMkCAA4ACQrhGWIeAMkCAAAA.Asterisk:BAAANQAECgcICgABNQAFFAcIGwAEAGQcAA==.Astinous:BAAANQADCggICAAAAA==.Astlyr:BAAANQADCgUICAAAAA==.Astrid:BAACNQAFFIERAAIPAAcKYhGOAgBBAgAPAAcKYhGOAgBBAgA1AAQKgR4AAw8ACQpiIlgFAD8DAA8ACQpiIlgFAD8DABAAAQrzGy4vAFQAAAAA.',
At='Athera:BAAANQADCgYIBgAAAA==.Atiermonk:BAAANQAECgEIAQAAAA==.',
Au='Ausdemonic:BAAANQAECgQICAAAAA==.',
Av='Avell:BAABNQAECoEbAAIOAAkKHCUoAgDBAwAOAAkKHCUoAgDBAwAAAA==.Avocardio:BAAANQAECgYIBQAAAA==.',
Ax='Axiomatic:BAAANQAECgUIBQAAAA==.',
Az='Aziluth:BAAANQAECgYIBgAAAA==.Azraél:BAAANQADCggIBwAAAA==.Azriox:BAAANQADCgUIBQAAAA==.Azsharia:BAAANQADCgYIBgAAAA==.Azzielliea:BAAANQAECgYJEQAAAA==.',
Ba='Badumdadoom:BAAANQAECgMIAwABNQAFFAcIDwARAFYiAA==.Balance:BAAANQAECgEIAQAAAA==.Barleybrew:BAAANQADCgIIAgABNQABCgYIBQALAAAAAA==.Battletank:BAAANQAECgcIEgABNQAFFAUICAAKALQEAA==.',
Be='Beefchar:BAAANQAECgEIAQAAAA==.Beefquake:BAABNQAECoEkAAMBAAkKUxvOIgCjAgABAAkKUxvOIgCjAgASAAMK+Bd3sADbAAAAAA==.Betray:BAAANQAECgcIDAAAAA==.Beàr:BAAANQAECgQIBAAAAA==.',
Bi='Bigbadbaka:BAACNQAFFIEbAAITAAcKXSA3AQDHAgATAAcKXSA3AQDHAgA1AAQKgSYAAhMACQrDJYgGALEDABMACQrDJYgGALEDAAAA.Bigdecay:BAABNQAECoEnAAMJAAgKZCCzFADeAgAJAAgKZCCzFADeAgAUAAQKTxV+SQATAQAAAA==.',
Bl='Blackfish:BAAANQAECgIIAgAAAA==.Blasez:BAAANQAECgYIEAAAAA==.Blazez:BAACNQAFFIEIAAIGAAUKBxUQBgCeAQAGAAUKBxUQBgCeAQA1AAQKgTAAAgYACQr8I6w8AJgCAAYACQr8I6w8AJgCAAAA.Blazpew:BAAANQADCggICAAAAA==.Blood:BAEANQAECgEIAQABNQAECgYICQALAAAAAA==.',
Bo='Bogart:BAACNQAFFIEKAAICAAUK1BPcCwBIAQACAAUK1BPcCwBIAQA1AAQKgS4ABAIACQq4IgEwAI4CAAIACApsIgEwAI4CAAQABAqNHF0mAC0BAAUAAQpwH1kdAFsAAAAA.Bomohdh:BAABNQAECoEWAAIVAAkKNBj/HQBiAgAVAAkKNBj/HQBiAgABNQAFFAUICgATACARAA==.Bomohomo:BAACNQAFFIEKAAMTAAUKIBEIEQA2AQATAAQKuREIEQA2AQAWAAEKuw4ZAwBZAAA1AAQKgSEAAhMACQrDHwo1ALoCABMACQrDHwo1ALoCAAAA.Boogeymayne:BAAANQADCgIIAgAAAA==.Bootycallz:BAAANQAECgEJAQAAAA==.Bossimón:BAAANQAECgQIBQAAAA==.',
Br='Brainlag:BAAANQAECgIIAgAAAA==.Brawny:BAAANQAECgYIDQAAAA==.Brev:BAAANQADCgEIAQABNQAECggIGQAXAIgdAA==.Brevren:BAAANQADCgMIAwABNQAECggIGQAXAIgdAA==.Brevrin:BAABNQAECoEZAAIXAAgKiB3TCQCjAgAXAAgKiB3TCQCjAgAAAA==.',
Bu='Bubbix:BAAANQAECgQICwAAAA==.Buddhatime:BAAANQADCgYIBgABNQAECggIEQALAAAAAA==.Bui:BAABNQAFFIEZAAIIAAcKgB+AAACHAgAIAAcKgB+AAACHAgAAAA==.Buikia:BAAANQAFFAIIAgABNQAFFAcIGQAIAIAfAA==.Buikyah:BAAANQAECgMIBQABNQAFFAcIGQAIAIAfAA==.Bunnyhop:BAAANQAECgMIBAAAAA==.Buysfeetpics:BAACNQAFFIEUAAMYAAcKGRPeCAD6AQAYAAYK2BPeCAD6AQAZAAEKng7ZBwBcAAA1AAQKgSYAAhgACQoAJFQUAHIDABgACQoAJFQUAHIDAAAA.',
['Bâ']='Bânê:BAAANQAECggIEwAAAA==.',
Ca='Calx:BAAANQAECgIIAgABNQAFFAQICwAPAO0VAA==.Camerõn:BAAANQADCgYJBgAAAA==.Cannicus:BAACNQAFFIEVAAIYAAcKORmVAQCdAgAYAAcKORmVAQCdAgA1AAQKgSYAAhgACQqHJEMaAFoDABgACQqHJEMaAFoDAAAA.Cantheal:BAAANQAECgQIBQAAAA==.Capel:BAAANQADCgIIAgAAAA==.Cardinal:BAAANQAECgYIDAABNQAECggIEQALAAAAAA==.',
Ce='Celavii:BAABNQAECoEbAAIDAAgKrhgwQABiAgADAAgKrhgwQABiAgAAAA==.Celeena:BAAANQAECgQICwAAAA==.',
Ch='Chamane:BAAANQAFFAEIAQAAAA==.Chanengtotem:BAAANQADCgcIBwAAAA==.Chappell:BAAANQAECgYIDQAAAA==.Chargeplox:BAAANQAECgYIBgAAAA==.Chii:BAAANQADCgEIAQAAAA==.Chillicheese:BAAANQADCgUIBwAAAA==.Chinnohoho:BAAANQAECgYIBgAAAA==.Chinnomojo:BAAANQAECgcIDwAAAA==.',
Ci='Cindermoon:BAAANQAECgIIAwAAAA==.Cinna:BAAANQADCgYIBgAAAA==.',
Cl='Cloudhorn:BAAANQAECgYIEQAAAA==.',
Cm='Cmi:BAAANQAECgYIBgABNQAFFAEIAQALAAAAAA==.',
Co='Colena:BAEBNQAECoEmAAIMAAkKkBjwJQCYAgAMAAkKkBjwJQCYAgAAAA==.Conquest:BAAANQAECgUICQAAAA==.Conzy:BAAANQAECgQIDAAAAA==.Coopsfire:BAAANQAECgMIBAAAAA==.Corbulus:BAABNQAECoE3AAIGAAgKjRogRwBzAgAGAAgKjRogRwBzAgAAAA==.',
Cr='Create:BAAANQADCgcIBwABNQADCggIDQALAAAAAA==.Crispyarrowz:BAAANQAECgEIAQABNQAECgkJJQAYAJ0bAA==.Crispymage:BAABNQAECoElAAIYAAkKnRvATADCAgAYAAkKnRvATADCAgAAAA==.Cronus:BAAANQAECgIIBAAAAA==.Crypsis:BAAANQAECgQIBAAAAA==.',
Ct='Ctierwarlock:BAABNQAECoEgAAICAAgKwyN1DABEAwACAAgKwyN1DABEAwABNQAFFAcIFgAaALQmAA==.',
Cy='Cyndi:BAAANQAECgIIBQAAAA==.Cynxs:BAAANQAECgYIEwABNQAECgkJHQAXAPEaAA==.',
Da='Dahala:BAAANQADCgQIBAABNQAECgkJGQAbADodAA==.Dannoh:BAAANQAECgQICAAAAA==.Dannyxie:BAAANQADCgUIBQAAAA==.Darcious:BAAANQAECgUICgABNQAECggJGwADAK4YAA==.Darkcinders:BAABNQAECoEkAAICAAkKMBNRTwAfAgACAAkKMBNRTwAfAgAAAA==.Davayer:BAAANQAECgYJCwAAAA==.',
De='Deadjkcocoon:BAAANQADCgMIBAAAAA==.Deadlly:BAABNQAECoEdAAIIAAgKORkfEgAwAgAIAAgKORkfEgAwAgAAAA==.Deathbfbirth:BAAANQADCggICAABNQAECgQIBAALAAAAAA==.Deathdruid:BAAANQAECgIIAwABNQAFFAUICAAJAM4cAA==.Deathfire:BAAANQAECgQIBAAAAA==.Deathmage:BAAANQAECgMIAwABNQAFFAUICAAJAM4cAA==.Deathmonks:BAAANQAECgEIAQABNQAFFAUICAAJAM4cAA==.Deathrocks:BAACNQAFFIEIAAMJAAUKzhydBQBdAQAJAAQKEiGdBQBdAQAcAAEKvwvPKAAnAAA1AAQKgSMAAgkACQqcJdMFAIEDAAkACQqcJdMFAIEDAAAA.Deathsshaman:BAAANQAECgEIAQABNQAFFAUICAAJAM4cAA==.Deathwarlock:BAAANQABCgEIAQABNQAFFAUICAAJAM4cAA==.Demöníc:BAAANQAECgcJEQAAAA==.Deplock:BAAANQAECgUICgABNQAECgcIDAALAAAAAA==.Destcrypt:BAAANQAECggIEAABNQAECggIFgAdAN8iAA==.Destinyisall:BAAANQADCgcJDAAAAA==.Destwind:BAABNQAECoEWAAIdAAgK3yKdBgABAwAdAAgK3yKdBgABAwAAAA==.',
Di='Dilo:BAAANQADCggIBwAAAA==.Disbelief:BAAANQADCgEIAQAAAA==.Divinfinity:BAABNQAECoEWAAQIAAcKmg7KJABdAQAIAAYKhhDKJABdAQAOAAYKyAXHkgASAQAGAAIKoQFWXwEpAAAAAA==.',
Do='Doeji:BAABNQAECoEgAAIHAAkKNA2oHgAxAgAHAAkKNA2oHgAxAgAAAA==.Dotdotseckz:BAABNQAECoEjAAMEAAcKrhgMLgD/AAACAAUKIhTgkABXAQAEAAMKIhsMLgD/AAAAAA==.',
Dr='Dracdoy:BAAANQAECggIDQABNQAECggIEQALAAAAAA==.Drackor:BAAANQADCgUIBQAAAA==.Drethalis:BAAANQAECgEIAgAAAA==.Drewstormio:BAAANQAECgQJBQABNQAECgQJBQALAAAAAA==.Dryene:BAAANQAECgIIAgAAAA==.',
Ds='Dsdh:BAACNQAFFIEWAAIKAAcKpRsRAQCCAgAKAAcKpRsRAQCCAgA1AAQKgR0AAgoACQqfJP8FAGADAAoACQqfJP8FAGADAAAA.',
Du='Dulang:BAABNQAECoElAAIDAAkKBiDLFAAeAwADAAkKBiDLFAAeAwAAAA==.Dunfreezeyou:BAAANQAECgEIAgAAAA==.Dunsmiteyou:BAAANQAECgEIAQAAAA==.',
Ea='Eattherich:BAAANQAECgcIEwAAAA==.',
Eb='Eb:BAAANQAECgIIAgABNQAFFAcIEQAHAHkTAA==.',
Ec='Ectruby:BAABNQAECoEtAAMeAAkKUSFjBwCHAgAeAAkKUSFjBwCHAgAaAAIK0BCoggBiAAAAAA==.',
El='Elammental:BAAANQADCgYIBgAAAA==.Elertricsoup:BAAANQAECgIIAgAAAA==.Elwarlocko:BAABNQAECoEYAAQFAAgKuRjwCACoAQACAAcKPxI9bQC/AQAFAAUKVxrwCACoAQAEAAIKcRIqTACFAAAAAA==.Elyndre:BAACNQAFFIESAAQfAAYK7BcaAwBdAQAfAAQKgBMaAwBdAQAQAAMKoBwmBgD8AAAPAAEKhgqtEQBTAAA1AAQKgSUABBAACQraHXYJALICABAACQq6GnYJALICAB8ABArNImoJAJABAA8AAwqAHS8sAPYAAAAA.',
Em='Emberis:BAAANQADCgUIBQAAAA==.',
En='Endari:BAAANQAECgUIBQAAAA==.Endlockz:BAABNQAECoEfAAQCAAkKtxPDOABsAgACAAkKtxPDOABsAgAFAAIKOwcPHQBdAAAEAAIKsQXwWwBZAAAAAA==.',
Er='Erikk:BAACNQAFFIEcAAIKAAcKmBKhAQBUAgAKAAcKmBKhAQBUAgA1AAQKgSYAAgoACQorIloGAFoDAAoACQorIloGAFoDAAAA.',
Es='Escher:BAAANQADCgYIEQAAAA==.Espresso:BAAANQAECgIIAgABNQAFFAYIHQADACobAA==.Esprit:BAAANQAECgQIBgABNQAFFAQICwAYALsUAA==.',
Ex='Excalibur:BAAANQAECgMIBAAAAA==.',
Fa='Faeia:BAABNQAECoEiAAIgAAcKEhpgGQAgAgAgAAcKEhpgGQAgAgABNQAFFAYICAABAFEcAA==.Faenirel:BAABNQAECoEaAAIYAAgKThjmewBOAgAYAAgKThjmewBOAgABNQAFFAEIAgALAAAAAA==.Faeya:BAACNQAFFIEIAAIBAAQKURxjEQDLAAABAAQKURxjEQDLAAA1AAQKgSoAAwEACQoOJZ4DAJsDAAEACQoOJZ4DAJsDABIABwpWF2tGAA4CAAAA.Fairyen:BAAANQAECgUIDgAAAA==.Faithful:BAAANQAECgYIDAAAAA==.Faithless:BAAANQAECgQIBAAAAA==.Famine:BAAANQADCgUIBQABNQAECgcIDAALAAAAAA==.Farapanda:BAAANQADCgYICQAAAA==.Fastcharge:BAAANQAECgcIEAABNQAFFAUICAAKALQEAA==.',
Fe='Feidutdut:BAAANQAECgcIEgAAAA==.Feldown:BAAANQAFFAEIAQABNQAECgkJJAAhALsjAA==.',
Ff='Ffdeathpunch:BAAANQADCgQIBAABNQAECggIGQAXAIgdAA==.Ffen:BAAANQAECgYIDQABNQAECggIEAALAAAAAA==.',
Fi='Fibanocci:BAABNQAECoEgAAIYAAkKoRg0aQB7AgAYAAkKoRg0aQB7AgAAAA==.Fierce:BAABNQAECoEnAAMQAAkK1RJ/DgA9AgAQAAkK1RJ/DgA9AgAfAAEKAAMHHwAlAAAAAA==.Filthypally:BAAANQADCgQIBgAAAA==.Firaguy:BAAANQAECgUICgAAAA==.Fixated:BAABNQAECoEdAAMCAAYKxwqunAA5AQACAAYKxwqunAA5AQAEAAEKbAD3egAaAAAAAA==.',
Fl='Flamerage:BAAANQAECgcIEAAAAA==.',
Fr='Frankadelic:BAAANQAECgYIEwAAAA==.Frieren:BAAANQAECgQIBQAAAA==.Frodolol:BAACNQAFFIEZAAMYAAcKDBsjBgAfAgAYAAYKtRwjBgAfAgAZAAMKmhYyAQAKAQA1AAQKgSkAAhgACQprJDweAEwDABgACQprJDweAEwDAAAA.Frostik:BAAANQAECgEIAQAAAA==.Frostyfruit:BAABNQAECoEeAAMYAAgKLBvXbAByAgAYAAgKdhrXbAByAgAZAAMKUhFEGwDSAAAAAA==.',
Fu='Fufamace:BAAANQADCgIIAwAAAA==.Fufina:BAAANQADCgcIDwAAAA==.',
Fw='Fwoopie:BAABNQAECoEbAAIcAAgKvyA9FQDWAgAcAAgKvyA9FQDWAgAAAA==.Fwooplin:BAAANQAECgUICAABNQAECggIGwAcAL8gAA==.',
Ga='Gandea:BAAANQADCgMIAwAAAA==.Gannina:BAABNQAECoEjAAMiAAkKeB2bCwDvAgAiAAkKeB2bCwDvAgAjAAQKpQjwHQCrAAAAAA==.Garage:BAAANQADCgEIAQAAAA==.',
Gi='Gillemon:BAAANQADCgQIBQAAAA==.Givre:BAAANQAECgUIBQAAAA==.Gizzy:BAAANQAECgUIEwAAAA==.',
Go='Goodra:BAAANQADCgYIBgABNQAFFAUICAAKALQEAA==.Goodwill:BAABNQAECoEkAAMhAAkKuyMpCAA1AwAhAAgKUSMpCAA1AwADAAgKcCGyLwCdAgAAAA==.Gorillaunitt:BAAANQADCgIIAgAAAA==.Gortrek:BAAANQAECgUIBQAAAA==.',
Gr='Graoul:BAAANQAECgEIAwAAAA==.Greybeards:BAAANQADCgcICQAAAA==.Gritt:BAAANQAECgMIBQAAAA==.Gryffin:BAABNQAECoEdAAINAAgK3BYVGQBBAgANAAgK3BYVGQBBAgAAAA==.',
Gu='Gugudan:BAAANQAECgMIBgAAAA==.Gunnina:BAAANQAECgEIAQAAAA==.Gutsc:BAABNQAECoEkAAIdAAkK5B9FBQAkAwAdAAkK5B9FBQAkAwAAAA==.Guyhulikatit:BAAANQADCggICAABNQAFFAcIEQAHAHkTAA==.Guzzan:BAAANQAECgYIBwAAAA==.',
Ha='Haialorhwa:BAAANQADCgQIBwAAAA==.Hammerboltie:BAAANQAECgIJAQABNQAECgkJIAAYAKEYAA==.Hatewatching:BAAANQAECgcIDwAAAA==.',
He='Healbòt:BAAANQAECgIIAgAAAA==.Hemorrhage:BAABNQAECoEkAAIkAAkKSxlwCgC0AgAkAAkKSxlwCgC0AgAAAA==.Hermighty:BAAANQAECgUIDwABNQAECggIGQADAB0cAA==.Hershéy:BAABNQAECoEdAAIgAAgKpiORBQBHAwAgAAgKpiORBQBHAwAAAA==.Hert:BAAANQAECggIDwAAAA==.',
Hi='Hiradaira:BAABNQAFFIEOAAMYAAcKOhUMCQD3AQAYAAYKLRUMCQD3AQAZAAEKhxUjBwBeAAAAAA==.',
Ho='Holasimón:BAAANQAECgQJCgAAAA==.Hollyjoel:BAAANQADCgMIAwAAAA==.Hothotseckz:BAAANQAECgEIAgABNQAECgcIIwAEAK4YAA==.',
Hu='Hukk:BAABNQAECoEZAAMbAAkKOh3rBgCtAgAbAAgKph7rBgCtAgATAAEK2BGJEQE+AAAAAA==.Huwuk:BAAANQAECgEJAQABNQAECgkJGQAbADodAA==.',
Hy='Hypervoltage:BAAANQADCgMIAwAAAA==.Hypnos:BAABNQAECoEYAAICAAgKqAkTcAC3AQACAAgKqAkTcAC3AQAAAA==.',
['Hà']='Hà:BAABNQAECoEXAAIYAAgK/xqQZACFAgAYAAgK/xqQZACFAgAAAA==.',
['Há']='Háá:BAAANQAECgIIAgAAAA==.',
Ia='Iamundecided:BAAANQADCggIDQAAAA==.Iamzzr:BAAANQAECgYIBwAAAA==.',
Ic='Icysun:BAAANQAECggIEgAAAA==.',
Ig='Igneous:BAAANQAECgMJBAAAAA==.',
Im='Image:BAAANQAECgUIBQABNQADCggIDQALAAAAAA==.Imnotamage:BAAANQADCgMIBgAAAA==.',
Is='Ish:BAAANQAECggIBgAAAA==.Isopod:BAAANQADCgYICAAAAA==.',
Ja='Jabbah:BAAANQAECgIIBAAAAA==.Jackee:BAAANQAECgQICQABNQAECgcIDAALAAAAAA==.Jasmean:BAACNQAFFIEKAAIhAAUKMxYnCwA4AQAhAAUKMxYnCwA4AQA1AAQKgScAAyEACQrkIsIOANMCACEACArTIsIOANMCAAMAAwpjFQTkAMIAAAAA.',
Je='Jellybeanss:BAABNQAECoEeAAMVAAgKrhkyGgCDAgAVAAgKrhkyGgCDAgAKAAEKqQ2hVQA8AAAAAA==.Jereu:BAAANQADCgcIDQAAAA==.',
Jo='Jobless:BAAANQAECgYIBwAAAA==.Jodix:BAAANQADCgcICQAAAA==.Johnevoker:BAAANQAECgYICAABNQAECgkJHwABAHMYAA==.Johnpaladin:BAAANQAECgYICgABNQAECgkJHwABAHMYAA==.Johnthedeath:BAAANQAECggIAwABNQAECgkJHwABAHMYAA==.Johnthemonk:BAAANQAECgYICAABNQAECgkJHwABAHMYAA==.Jojobao:BAAANQAECgEJAQAAAA==.Jombii:BAAANQAECgcIDgABNQAFFAUICwAHAI0PAA==.Jordoom:BAAANQAECgYIDAAAAA==.',
Ju='Judicas:BAAANQAECgIIAwAAAA==.',
['Jë']='Jëwjuice:BAAANQABCgQIBAAAAA==.',
Ka='Kafra:BAAANQAECgQIBAABNQAECggIGQADAB0cAA==.Kafrial:BAAANQAECggIDQABNQAECggIGQADAB0cAA==.Kamazi:BAABNQAECoETAAIfAAgK6RdEBgAYAgAfAAgK6RdEBgAYAgAAAA==.Kannina:BAAANQAECgEIAQAAAA==.Kariiyon:BAAANQAECgIIBQAAAA==.Katalen:BAAANQADCgQIBQAAAA==.Kate:BAAANQAECgEIAQAAAA==.Kayapau:BAACNQAFFIEMAAMSAAUKFgq/DAAnAQASAAQKZAm/DAAnAQABAAIKIwbaGQCHAAA1AAQKgSEAAxIACQomHbQcAO4CABIACQomHbQcAO4CABcABAojC9ogANMAAAAA.',
Ke='Kevd:BAAANQAECgYICgABNQAFFAYIFwABAD4dAA==.Kevin:BAACNQAFFIEXAAIBAAYKPh2AAgAzAgABAAYKPh2AAgAzAgA1AAQKgSIAAgEACQpjJYQDAJ0DAAEACQpjJYQDAJ0DAAAA.Kevp:BAAANQAECgYIBgABNQAFFAYIFwABAD4dAA==.',
Kh='Khaii:BAACNQAFFIEKAAMYAAUK4hOkDQC+AQAYAAUK4hOkDQC+AQAZAAEK4gQHDgBEAAA1AAQKgS0AAxgACQqVJdQbAFQDABgACQpYJdQbAFQDABkAAwq8JNgTACkBAAAA.',
Ki='Kidevil:BAAANQAECgUIDAAAAA==.Kimmiereed:BAABNQAECoEsAAQFAAgKlh33AwBnAgAFAAcKeB/3AwBnAgACAAUKkxPBjQBfAQAEAAEKKwh5cQAwAAAAAA==.',
Ko='Kodette:BAAANQAECgQIBAAAAA==.Komai:BAABNQAECoEmAAMBAAkKdSJDBgB5AwABAAkKdSJDBgB5AwASAAYKUx0rTQDzAQAAAA==.Kopikia:BAABNQAECoEaAAMVAAgKUQ/vLgDTAQAVAAgKFA/vLgDTAQAKAAcKiQpULgCNAQAAAA==.',
Kr='Krucify:BAAANQAECggJDgAAAA==.',
Kt='Ktl:BAAANQAECgYIBgABNQAECgkJIgAGALwiAA==.Ktx:BAABNQAECoEiAAMGAAkKvCI5DgB5AwAGAAkKvCI5DgB5AwAOAAEKIgdB7gA0AAAAAA==.',
Ku='Kulak:BAAANQADCggICwABNQAECggIGgADAIQRAA==.',
Ky='Kyall:BAABNQAECoEnAAQVAAkKUBwdFwCgAgAVAAkKUBwdFwCgAgAlAAQK0RinEgAbAQAKAAEKww4qVwA3AAAAAA==.Kyalln:BAAANQAECgQIBAAAAA==.',
La='Ladiesman:BAAANQAECggIBgAAAA==.Lafret:BAAANQADCggIDgAAAA==.Lamerzz:BAAANQAECgEIAQAAAA==.Lamzhar:BAAANQADCgIIAgAAAA==.',
Le='Lebronyames:BAAANQAECgYIDwAAAA==.Lelith:BAAANQAECgcIEgAAAA==.Lerazar:BAAANQAECgEIAQAAAA==.Lettuce:BAAANQAECggIEQAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Lipskiz:BAAANQAECgQIAwAAAA==.Liquidstorm:BAAANQAECgEIAQABNQAECgkJIAAMACQfAA==.Liquidvoid:BAABNQAECoEgAAMMAAkKJB/2DAA1AwAMAAkKJB/2DAA1AwANAAIKZA7SUgBiAAAAAA==.Littleannie:BAAANQAECgUIBQAAAA==.',
Lo='Lokk:BAAANQAECgMIAwAAAA==.',
Lu='Luurch:BAACNQAFFIEKAAMkAAQKoBkaBgBuAQAkAAQKoBkaBgBuAQAHAAEKERqVEgBTAAA1AAQKgSwAAyQACQqMJOcDAE4DACQACAorJecDAE4DAAcABAomHyQ6AGcBAAAA.',
Ly='Lynnae:BAAANQAECgEIAQABNQAECggIGgADAIQRAA==.Lythillen:BAAANQADCgMIBAAAAA==.Lythium:BAAANQADCgMIAwAAAA==.',
['Lî']='Lîght:BAAANQAECgYICwABNQAECgcIDAALAAAAAA==.',
Ma='Maceson:BAAANQADCggIDAAAAA==.Maddenz:BAAANQADCgYIBgAAAA==.Magikcreepz:BAAANQAECggIDgAAAA==.Magnamund:BAAANQABCgYIDQAAAA==.Marvik:BAAANQADCgIIAgAAAA==.Masquerapet:BAACNQAFFIEcAAIcAAcKDhamAQBdAgAcAAcKDhamAQBdAgA1AAQKgSYAAhwACQqoHLwXAL8CABwACQqoHLwXAL8CAAAA.Mavqt:BAAANQAFFAEIAQAAAA==.',
Me='Medina:BAAANQAECgIIAwAAAA==.Megadeath:BAABNQAECoEeAAIUAAkKPRXLIgAiAgAUAAkKPRXLIgAiAgAAAA==.Mentalas:BAABNQAECoEXAAIDAAcKsQmIgwCkAQADAAcKsQmIgwCkAQAAAA==.Mepuzzible:BAAANQAECgYIBgABNQAECgcIDAALAAAAAA==.Meulah:BAAANQAECgUICgABNQAECggIGQADAB0cAA==.',
Mi='Miah:BAAANQAECggJDgAAAA==.Miao:BAACNQAFFIERAAIBAAYKZxgxAwARAgABAAYKZxgxAwARAgA1AAQKgSQAAgEACQocJVsCALADAAEACQocJVsCALADAAE1AAUUBggRACAAahIA.Miaomiaomiao:BAACNQAFFIERAAIgAAYKahIjAgD1AQAgAAYKahIjAgD1AQA1AAQKgSgAAiAACQpCIP4GACsDACAACQpCIP4GACsDAAAA.Miaomiaorawr:BAACNQAFFIEGAAIMAAUKJQrvCgCQAQAMAAUKJQrvCgCQAQA1AAQKgRYAAgwABwoiHvotAHACAAwABwoiHvotAHACAAE1AAUUBggRACAAahIA.Minamai:BAABNQAECoEaAAMMAAcK6wxbagB1AQAMAAcK6wxbagB1AQANAAEKJAuBaAAnAAABNQAECgkJIgABAOAcAA==.Minaminis:BAAANQAECgYICQAAAA==.Misdirecting:BAAANQADCgYICgABNQADCggIDQALAAAAAA==.',
Mo='Monggoloid:BAAANQADCgMIAwAAAA==.Monsieurstun:BAAANQADCgEIAQAAAA==.Moomooda:BAAANQAECgUIBQAAAA==.Moongrass:BAAANQAECgQIBwAAAA==.Mousemarâ:BAABNQAECoEdAAMHAAgKcA7NJQD3AQAHAAgKcA7NJQD3AQAkAAMKuQPmOwCMAAAAAA==.',
Mu='Mungomania:BAAANQAECgYIDwAAAA==.Mutedz:BAABNQAECoEVAAIOAAkKag+KPwAmAgAOAAkKag+KPwAmAgAAAA==.',
Na='Nagaridar:BAAANQADCgUIBQAAAA==.Nargorr:BAAANQADCgYIDAAAAA==.Naruwa:BAAANQADCgMJAwAAAA==.',
Ne='Necroticdr:BAAANQAECggIEgABNQAECgkJLAAJAJgjAA==.Necroticlol:BAABNQAECoEsAAMJAAkKmCP/DQAfAwAJAAkKjyP/DQAfAwAUAAcKgx8qGwBoAgAAAA==.Necroticlòl:BAABNQAECoEbAAMGAAgKDhT+bgD1AQAGAAgKPBL+bgD1AQAIAAIKIxjdRACCAAABNQAECgkJLAAJAJgjAA==.Neeyana:BAAANQADCggIDwAAAA==.Neff:BAAANQAECggIEAAAAA==.Nefpore:BAAANQAECgYIEQAAAA==.Nenepok:BAAANQAECgQIAQAAAA==.Nephelem:BAAANQADCgIIAgAAAA==.',
Ni='Niij:BAAANQAECgYIEQAAAA==.Nimon:BAAANQADCgQIBAAAAA==.Nitox:BAAANQAECgIIBQAAAA==.',
No='Nocchii:BAAANQAECgIIAgAAAA==.Nolimits:BAAANQAECgIIAgAAAA==.Nopantiesx:BAAANQAECgEIAQAAAA==.Norielia:BAAANQADCgYICQAAAA==.Noruid:BAAANQAECgYIDgABNQAECgkJIQATAKMiAA==.Nosivire:BAAANQAECgEIAQAAAA==.Nosok:BAAANQAECgIIBAABNQAECggIEwALAAAAAA==.Notwiththema:BAAANQAECgcIEwAAAA==.Noughtawolf:BAABNQAECoEeAAIbAAgKzBs8CACEAgAbAAgKzBs8CACEAgAAAA==.',
Nt='Nthope:BAAANQAFFAYIFAAAAQ==.',
Nv='Nvictus:BAAANQADCgQIBQAAAA==.',
Od='Odîn:BAAANQADCggICgAAAA==.',
On='Onlyfire:BAAANQAECgYIBwAAAA==.Onlylight:BAAANQAECggIAgAAAA==.',
Pa='Palabean:BAAANQADCgcIEAAAAA==.Pamie:BAAANQAECgQIBgABNQAECgkJKwAOAJ4fAA==.Patsie:BAAANQAECgcIEgAAAA==.',
Pe='Peach:BAAANQAECgYICgABNQAFFAYIEgAkAOYRAA==.Peeta:BAAANQADCgIIAgAAAA==.Pepperino:BAAANQAECgYIDwAAAA==.Perseph:BAAANQAECggIBwAAAA==.',
Ph='Pharmercy:BAAANQAECgEIAgABNQAFFAcIGwAEAGQcAA==.Phoebe:BAAANQADCgYIBgAAAA==.',
Pi='Piyona:BAAANQAECgYIDAAAAA==.',
Po='Pocketpie:BAAANQABCgYICwAAAA==.Poros:BAAANQADCgYIBgABNQAECgkJJQAJAMMeAA==.Porosdk:BAABNQAECoElAAIJAAkKwx6tEgDvAgAJAAkKwx6tEgDvAgAAAA==.Poteb:BAAANQADCgUIBwAAAA==.Powerangers:BAAANQAECgQIBQAAAA==.',
Pr='Prevailor:BAAANQADCgUIAgAAAA==.Prodigal:BAACNQAFFIEKAAIlAAUKqwmjAQDxAAAlAAUKqwmjAQDxAAA1AAQKgR8AAiUACQpVEyAIAB8CACUACQpVEyAIAB8CAAAA.',
Pt='Pterion:BAAANQAFFAEIAQAAAA==.',
Pu='Pumbz:BAABNQAECoEVAAMDAAgKcB8jaQDpAQADAAUKySAjaQDpAQAhAAMKMB0pPQAAAQAAAA==.Punprepared:BAEBNQAECoEgAAMKAAgKwiWCBACAAwAKAAgKwiWCBACAAwAlAAEKjBBFIwBDAAAAAA==.',
Qe='Qeb:BAACNQAFFIERAAIHAAcKeRPHAAB7AgAHAAcKeRPHAAB7AgA1AAQKgSUAAwcACQobIxwGAEYDAAcACQobIxwGAEYDACQABQouEeorACwBAAAA.Qezam:BAAANQAECgEIAQABNQAECgIIAgALAAAAAA==.',
Qi='Qio:BAAANQABCggIEgAAAA==.Qisz:BAABNQAECoEZAAIRAAcKmRCOCQC/AQARAAcKmRCOCQC/AQAAAA==.',
['Qí']='Qíqi:BAABNQAECoEnAAINAAkKLRbvEgCUAgANAAkKLRbvEgCUAgAAAA==.',
Ra='Raincy:BAAANQADCgEIAQAAAA==.Rainrain:BAAANQAECgIIAgABNQAFFAUICwAYAKQbAA==.Rashes:BAAANQAECgYICgAAAA==.Rashika:BAAANQAECgIIAQABNQAECggIGQADAB0cAA==.Rashypoopy:BAAANQAECgEIAQAAAA==.Ratix:BAAANQAECgIIAgAAAA==.Ravenn:BAAANQAECgQJBQAAAA==.Razoxaynne:BAAANQAECgQIBQAAAA==.',
Re='Resolute:BAAANQAECgIIAgAAAA==.Restinpieces:BAAANQAECggICgAAAA==.Reverb:BAAANQABCgIIAgABNQAECgYIHQACAMcKAA==.Reverencia:BAAANQAECgEIAgAAAA==.Revnger:BAAANQADCggIEAAAAA==.',
Rh='Rhyker:BAAANQAECgcIDQAAAA==.',
Ri='Riinegan:BAAANQAECgQIBAAAAA==.Rimreaper:BAAANQAECgYIEAAAAA==.Rinnegan:BAAANQAECgIIAgAAAA==.',
Ro='Rolypollie:BAAANQAECgEIAgAAAA==.Rorak:BAAANQADCgQICAABNQAECgkJKwATAF0UAA==.',
Ru='Ruptured:BAABNQAECoEqAAIHAAgKyySaBwAuAwAHAAgKyySaBwAuAwAAAA==.',
Ry='Ryndra:BAAANQADCgYIBgAAAA==.',
['Rä']='Räzoxane:BAAANQADCgIIAgAAAA==.',
Sa='Salamifreak:BAAANQADCgUIBQAAAA==.Satria:BAAANQADCggJDwAAAA==.Saveth:BAAANQAECgMJAwABNQAECgUICwALAAAAAA==.',
Sc='Scamdawg:BAAANQADCggIFQAAAA==.Screamin:BAAANQADCgEIAQAAAA==.Scumdawg:BAAANQADCgcICQAAAA==.',
Se='Senyorita:BAAANQAECgIIAgAAAA==.',
Sh='Shadesong:BAAANQAECgIJAwAAAA==.Shadowboiz:BAABNQAECoEkAAMCAAkKKibYAADrAwACAAkKKibYAADrAwAEAAIK1ha6RACdAAAAAA==.Shadowlesz:BAAANQAECggIAgAAAA==.Shamdoy:BAAANQAECggIEQAAAA==.Shampagne:BAABNQAECoEYAAIBAAgKKg8mXwCbAQABAAgKKg8mXwCbAQABNQAECgYIHQACAMcKAA==.Shapeshiift:BAAANQADCgYIBgAAAA==.Shidann:BAACNQAFFIEWAAIaAAcKtCZOAAAhAwAaAAcKtCZOAAAhAwA1AAQKgSMAAhoACQr6JkkAAAQEABoACQr6JkkAAAQEAAAA.Shiifty:BAAANQADCgIIBAAAAA==.Shintopal:BAABNQAECoEVAAIGAAcKexXWnwBzAQAGAAcKexXWnwBzAQAAAA==.Shintoslash:BAAANQAECgUICgAAAA==.Shopgirl:BAAANQADCgYIBgAAAA==.',
Si='Siewteng:BAAANQAECgIIAgAAAA==.Silentsnipe:BAAANQADCggICAAAAA==.Silverdeath:BAABNQAECoEXAAIUAAgKlg73LwC8AQAUAAgKlg73LwC8AQAAAA==.Silvermaiden:BAAANQABCgIIAgAAAA==.Sinorph:BAABNQAECoEmAAIlAAkKyBvAAwDQAgAlAAkKyBvAAwDQAgAAAA==.',
Sl='Slappuccino:BAAANQAECgYIEQAAAA==.Sleeptime:BAAANQAECggIEQAAAA==.',
Sn='Sneakyitch:BAAANQAECgcIEAAAAA==.Snipez:BAAANQAECgEIAQABNQAFFAMIBQABADUjAA==.Snowflake:BAAANQAECgIIBAAAAA==.',
So='Soggybiscuit:BAAANQAECgEIAQAAAA==.Soil:BAACNQAFFIELAAIPAAQK7RUSCQBNAQAPAAQK7RUSCQBNAQA1AAQKgSsAAw8ACQrGGQcOAJ0CAA8ACQrGGQcOAJ0CABAABwogCtIaAF8BAAAA.Solanaz:BAAANQAECgQICQAAAA==.Somedruid:BAAANQAECgQIBQABNQAFFAEIAgALAAAAAA==.Somepally:BAAANQAECgcIEwABNQAFFAEIAgALAAAAAA==.Songfíre:BAAANQAECgUIBwAAAA==.Sorahal:BAAANQADCgEIAQAAAA==.',
Sp='Spagalnero:BAAANQAECgEJAQAAAA==.Spinnywinny:BAAANQAECgEIAQAAAA==.',
St='Stampedê:BAAANQAECgQIBAAAAA==.Stan:BAACNQAFFIEPAAMDAAUKuiDDAgDyAQADAAUKuiDDAgDyAQAhAAMKLRCLEADUAAA1AAQKgS4AAwMACQr9JLwLAF4DAAMACAoUJrwLAF4DACEACArpHK0bAD4CAAAA.Stanstanstan:BAABNQAECoEVAAIXAAgK1B4ZBwDoAgAXAAgK1B4ZBwDoAgABNQAFFAUIDwADALogAA==.Starleet:BAAANQADCgIIAgAAAA==.Stier:BAAANQAECgQIBQABNQADCggIDQALAAAAAA==.Stiggyy:BAAANQAECggIEgAAAA==.Stiria:BAAANQAECgQIBwAAAA==.Stormscythe:BAAANQAECgIIBQAAAA==.',
Su='Supercleave:BAAANQAECgQICAAAAA==.Superdope:BAAANQAECgQIBAAAAA==.Superfly:BAAANQAECgQIDgAAAA==.Supermayhem:BAAANQADCgQJBQAAAA==.Suspense:BAAANQABCgYICAAAAA==.Sutiao:BAACNQAFFIEKAAIYAAUKPhhADwCvAQAYAAUKPhhADwCvAQA1AAQKgSoAAhgACQpSJHkOAI0DABgACQpSJHkOAI0DAAAA.',
Sw='Swissarmy:BAAANQAECgYIBQAAAA==.Switchknife:BAABNQAECoEaAAMHAAcKLSBbFQCFAgAHAAcKvh9bFQCFAgAkAAQK5R3fJgBgAQAAAA==.',
Sy='Sylasiana:BAAANQAECgEIAQAAAA==.Synasta:BAACNQAFFIEKAAMCAAYKEBlABQDBAQACAAUK4hhABQDBAQAEAAIKcBHuCgCnAAA1AAQKgScABAQACQoDIm0JAFICAAIACAq8IhIgANECAAQABwp+HW0JAFICAAUAAgqaIWMTAMQAAAAA.Syrent:BAAANQAECgQICAAAAA==.',
Ta='Taano:BAAANQADCgUICwAAAA==.Tallia:BAAANQAECgUICwABNQAECggIJgAYAEceAA==.Talons:BAAANQAECgcIDwAAAA==.Tamed:BAAANQAECgUICwAAAA==.Tancs:BAAANQAECgcIDgAAAA==.Tandem:BAAANQAECgUIBQAAAA==.Tarocakes:BAABNQAECoEaAAMfAAkKkgkyDQAfAQAfAAcKSggyDQAfAQAPAAgKlwAkPQBbAAAAAA==.Taurium:BAABNQAECoElAAMGAAkKkBbbSABtAgAGAAkKkBbbSABtAgAOAAcKRhB/YwCfAQAAAA==.',
Te='Teaki:BAABNQAECoEwAAIYAAgKQA6ppgDrAQAYAAgKQA6ppgDrAQAAAA==.Telsh:BAABNQAECoEZAAIDAAgKHRyxKwCtAgADAAgKHRyxKwCtAgAAAA==.Temperance:BAAANQAECgMIBAABNQAECgkJJAABAFMbAA==.Temsik:BAABNQAECoEkAAIDAAkKZCA0DQBSAwADAAkKZCA0DQBSAwAAAA==.Temsikdab:BAAANQAECgIIAgAAAA==.',
Th='Thoth:BAABNQAECoEkAAQCAAkKCB0HXAD1AQACAAYKuhwHXAD1AQAEAAMKuRVRNwDPAAAFAAIK/xrYFQCjAAABNQAECgIIBAALAAAAAA==.Thrallish:BAAANQAECgMIBAAAAA==.Thrux:BAAANQAECgYIEgAAAA==.Thura:BAAANQAECgEIAQAAAA==.',
Ti='Tidal:BAAANQAECgcIDAAAAA==.Tiddlyniblit:BAAANQAECgUICAAAAA==.Tigbugha:BAAANQADCgYIDwAAAA==.',
To='Tommyh:BAACNQAFFIEZAAINAAcKTh6tAAClAgANAAcKTh6tAAClAgA1AAQKgSYAAg0ACQpcJawDAIsDAA0ACQpcJawDAIsDAAAA.Topuzzible:BAAANQAECgEIAQABNQAECgcIDAALAAAAAA==.Torress:BAAANQAECgYIEAAAAA==.Totemistyk:BAAANQAECggJDQAAAA==.Toufz:BAABNQAECoElAAMhAAkKOh3sHAAxAgAhAAgK/RjsHAAxAgADAAUKZCG7bgDaAQAAAA==.',
Tr='Trianth:BAABNQAECoEeAAIGAAcKFxmEcgDrAQAGAAcKFxmEcgDrAQAAAA==.Tribbie:BAABNQAECoEaAAQJAAkKwx62IwBnAgAJAAgKCSC2IwBnAgAUAAEKlBSjfgA+AAAcAAEKgRG+rAAxAAAAAA==.Tribbier:BAACNQAFFIELAAMHAAUKqQguBAB+AQAHAAUKqQguBAB+AQAkAAIK9wClDAB7AAA1AAQKgRcAAwcACQoQGMASAKACAAcACQoQGMASAKACACQAAQoQDw9DAEUAAAAA.',
Tw='Twidger:BAAANQAECgYIDQAAAA==.',
Ty='Tyranadia:BAABNQAECoElAAIJAAkKThmWIgBuAgAJAAkKThmWIgBuAgAAAA==.Tystus:BAAANQAECgQIBgAAAA==.',
Um='Um:BAAANQAECgEIAQAAAA==.',
Up='Upstairs:BAABNQAECoEfAAIBAAkKcxjDKwB0AgABAAkKcxjDKwB0AgAAAA==.',
Ur='Uruga:BAAANQAECgEIAQAAAA==.',
Uz='Uzryn:BAAANQAECgUIBQAAAA==.',
Va='Varnoxx:BAACNQAFFIEKAAMJAAUK1RjBBgA9AQAJAAQK/RbBBgA9AQAcAAEKNiDWHABdAAA1AAQKgS4AAwkACQqIJDUZALgCAAkACQqIJDUZALgCABwAAQrWJViUAG4AAAAA.',
Vi='Vicioûs:BAAANQAECgUJCwAAAA==.Vinkwink:BAAANQADCgYIBgAAAA==.Vinwink:BAAANQAECgEIAgAAAA==.Vishnar:BAACNQAFFIEGAAICAAQKRAVZEAAQAQACAAQKRAVZEAAQAQA1AAQKgRwAAgIACAoDGRM9AF0CAAIACAoDGRM9AF0CAAAA.',
Vo='Vollic:BAAANQADCggICAAAAA==.',
Vv='Vvoo:BAAANQAECgIIBQAAAA==.',
Vy='Vyndish:BAAANQAECgQIBAAAAA==.',
Wa='Wander:BAAANQAECgUIEQAAAA==.Wardz:BAAANQADCgYICwAAAA==.Watever:BAAANQAECggIEgAAAA==.Wavedash:BAAANQAECgYIEQAAAA==.Wazaldin:BAAANQAECgEJAQAAAA==.',
We='Wendell:BAAANQADCggIDgAAAA==.Wetpantees:BAAANQAECgEIAQAAAA==.',
Wh='Whispess:BAAANQAECgIIBQAAAA==.',
Wi='Winnievoid:BAAANQAECgcJDgAAAA==.',
Wo='Woodro:BAABNQAECoEWAAIOAAgKihF7TQDvAQAOAAgKihF7TQDvAQAAAA==.Woz:BAAANQAECgQIBAABNQAECgYIBwALAAAAAA==.',
Xa='Xahara:BAAANQADCggICAAAAA==.',
Xl='Xln:BAAANQAECgQIDAABNQAECgkJIgABAOAcAA==.',
Xt='Xtion:BAACNQAFFIEKAAMhAAUKZRq2DQAEAQAhAAQKVRm2DQAEAQADAAEKpB5tIABdAAA1AAQKgS0AAyEACQqNJRAKABUDACEACQqoJBAKABUDAAMAAgrTIa0PAUMAAAAA.',
Ya='Yagnatia:BAAANQAECgUIBgAAAA==.',
Yo='Yongbok:BAAANQAECgIIBAAAAA==.',
Yr='Yrano:BAAANQAECgYJCwAAAA==.',
Yv='Yva:BAAANQADCggIBAAAAA==.',
Za='Zapu:BAAANQADCgUIBQAAAA==.Zaraxes:BAAANQAECgUIBgAAAA==.',
Ze='Zeladine:BAAANQABCggIEQAAAA==.Zelgaira:BAACNQAFFIEJAAIJAAUKNB4iAwCvAQAJAAUKNB4iAwCvAQA1AAQKgR0AAgkACQooIYsUAN8CAAkACQooIYsUAN8CAAE1AAUUBggKAAIAEBkA.Zelind:BAAANQAECgYICQABNQAECggILQANAN4GAA==.Zelvaris:BAACNQAFFIEPAAIRAAcKViIQAACrAgARAAcKViIQAACrAgA1AAQKgTkAAhEACQrfJVgAANMDABEACQrfJVgAANMDAAAA.Zenõ:BAABNQAECoEbAAIOAAkKfBi3JQCfAgAOAAkKfBi3JQCfAgAAAA==.Zerine:BAAANQAECgEIAwAAAA==.Zerkerman:BAAANQADCgcJBwAAAA==.',
Zi='Zipp:BAAANQABCgQIBAABNQAECgIIAgALAAAAAA==.Zipps:BAAANQAECgIIAgAAAA==.Zirka:BAABNQAECoEmAAIYAAgKRx4oUgC0AgAYAAgKRx4oUgC0AgAAAA==.Zivayhr:BAAANQADCgEIAQAAAA==.',
Zu='Zucchini:BAAANQADCgYICAAAAA==.',
Zy='Zylexo:BAAANQABCggIEwAAAA==.',
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
