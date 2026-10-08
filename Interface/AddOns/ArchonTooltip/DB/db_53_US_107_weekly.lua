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

local lookup = {'Warrior-Protection','Paladin-Retribution','Paladin-Holy','Priest-Shadow','Priest-Discipline','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Druid-Feral','Shaman-Restoration','Evoker-Preservation','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','Monk-Windwalker','Mage-Frost','Monk-Mistweaver','Rogue-Subtlety','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acks:BAAANQADCgYICgABNQAFFAMIBgABAL4QAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAABNQAECoEVAAMCAAgK7Qjr2QAtAQACAAcKrQXr2QAtAQADAAIKgQU98ABlAAAAAA==.Aex:BAAANQAECgcIEgABNQAFFAMIBgABAL4QAA==.',
Ah='Ahnkhano:BAAANQAECgYIBgAAAA==.',
Ai='Ainge:BAAANQAECgEJAQAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFIEXAAMEAAcKdRxZAQCGAgAEAAcKdRxZAQCGAgAFAAEKFgKDAwBHAAA1AAQKgTgAAwQACQpQJXkDAJkDAAQACQpQJXkDAJkDAAUACArUJNMAAGQDAAAA.Akorius:BAAANQAECgIIAgAAAA==.',
Al='Allistrana:BAAANQAECgYIEwAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alpacalyptic:BAAANQAECgYIBgAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgYIEgAGAAAAAA==.Amairis:BAAANQAECgQICQAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAABNQAECoEnAAQHAAkKDR41EwDmAgAHAAkKxh01EwDmAgAIAAYKThbMNAB3AQAJAAIKpB+dHQCyAAAAAA==.Antiflag:BAAANQAECgYIBgAAAA==.',
At='Ataliya:BAAANQAECgYICQAAAA==.',
Au='Auranar:BAAANQAECgQICgAAAA==.Aurelya:BAABNQAECoEgAAIKAAcK+gzedQCBAQAKAAcK+gzedQCBAQAAAA==.Aurilia:BAAANQAECgIIAwAAAA==.',
Av='Avanicus:BAAANQAECgYIEQAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBAAAAA==.Avé:BAAANQAECgYIEwAAAA==.',
Ax='Axellent:BAACNQAFFIEGAAIBAAMKvhDOAwDGAAABAAMKvhDOAwDGAAA1AAQKgRcABAsACAo2G44PAI4BAAsABQqMGY4PAI4BAAwABQoDGVayAHABAAEAAwoFF+QoAMMAAAAA.Axiomlegacy:BAABNQAECoEeAAMNAAgK9h8nGQDNAgANAAgK9h8nGQDNAgAOAAEKpwiN0QAuAAAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgQIBwAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAABNQAECoEbAAMLAAcK/BnECwDgAQALAAYKiBvECwDgAQAMAAcKHRPKkgDGAQAAAA==.Banzgrave:BAAANQADCgcIBwAAAA==.Bar:BAABNQAECoEdAAMEAAkK1RdlHwAaAgAEAAgKARdlHwAaAgAKAAgKTQsldQCDAQAAAA==.',
Be='Bearlyshady:BAABNQAECoEoAAQPAAkK4BduIwCVAgAPAAkK4BduIwCVAgAQAAQKlAy6NQCtAAARAAEKugNAaQAvAAABNQADCgYIBgAGAAAAAA==.Bellarina:BAAANQAECgQIBAAAAA==.Bellatrixie:BAAANQAECgQIDwAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQADCggIEQAAAA==.Bermy:BAABNQAECoEZAAMSAAgKcwwVFQC8AQASAAgKjAsVFQC8AQATAAQKWgYyBgF/AAAAAA==.Berzerkercow:BAAANQADCgEIAQAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAABNQAECoElAAIUAAgKqx5RbQCOAgAUAAgKqx5RbQCOAgAAAA==.Biku:BAAANQAECgIIBAAAAA==.Bitesthesky:BAAANQAECgUIBQAAAA==.',
Bl='Blackhawkdk:BAABNQAECoEfAAMOAAgKahcKPQAGAgAOAAgKWBcKPQAGAgANAAEKhxWktQA+AAAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBQAAAA==.Blindwarrior:BAAANQAECgIIAgAAAA==.Bloodshadow:BAAANQAECgUIDwAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgcICgAAAA==.',
Br='Breakcooloz:BAAANQAECgQIBgABNQAFFAUIBQAOAJUUAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIJAgAGAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAABNQAECoEaAAICAAcK9RnVewADAgACAAcK9RnVewADAgAAAA==.Broom:BAAANQAECgQIBAABNQAECggIJQAUAKseAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Burstinurass:BAACNQAFFIEFAAIOAAUKlRTtBgCMAQAOAAUKlRTtBgCMAQA1AAQKgRUAAg4ACQoaHd4XAOUCAA4ACQoaHd4XAOUCAAAA.Buzzliteyear:BAAANQADCgUIBQAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Caelix:BAAANQAECgMIAwAAAA==.Carbo:BAAANQAECgYIBgABNQAECgkJIwAVAIckAA==.Carbonight:BAABNQAECoEjAAIVAAkKhyTNAgBqAwAVAAkKhyTNAgBqAwAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECggIFgAWACENAA==.Celintha:BAAANQADCgEIAQAAAA==.Cellyne:BAAANQAECgQIBwAAAA==.',
Ch='Chaoswind:BAABNQAECoEnAAIWAAgKoByhMQB0AgAWAAgKoByhMQB0AgAAAA==.Charlee:BAAANQADCggICQAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwAGAAAAAA==.Chelives:BAEANQAECgUICwAAAA==.Chromus:BAACNQAFFIEMAAIXAAUKjhVaCACPAQAXAAUKjhVaCACPAQA1AAQKgSIAAhcACQqLHK0LANkCABcACQqLHK0LANkCAAAA.',
Ci='Cires:BAAANQAECggIEwAAAA==.',
Co='Colanasou:BAAANQAECgIIAgAAAA==.Coldbattler:BAAANQAECgQIBwAAAA==.Convictions:BAAANQAECgYICwABNQAFFAcIFgAMAJUeAA==.Corrick:BAAANQAECgMIBAAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAQICQAAAQ==.',
Cy='Cydric:BAAANQAECggIEwAAAA==.',
Da='Daarrkstar:BAAANQADCggIHQABNQAECgQIBQAGAAAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.Damageguy:BAAANQAECgYIBgABNQAFFAUIDgAMAJ8iAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCgcIEQAAAA==.Deathrival:BAAANQADCggICAAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgYICwAAAA==.Demonkare:BAAANQAECgUICgABNQAECgkJHQAYAGshAA==.Demoray:BAACNQAFFIEeAAMZAAcKHCElAwA6AgAZAAYK3CAlAwA6AgAaAAEKmSI5JgBlAAA1AAQKgSMAAxkACQqXJcQEAH8DABkACQqXJcQEAH8DABoAAQr5GJstAUUAAAAA.Demvinity:BAAANQAECgIIAwAAAA==.Dethrone:BAAANQAFFAEIAQAAAA==.Deus:BAABNQAECoEwAAMEAAcKRxVeJQDcAQAEAAcKRxVeJQDcAQAFAAUKNhWZDQBDAQAAAA==.',
Di='Dinosocks:BAACNQAFFIEPAAMaAAcK0QxZDABYAQAaAAQKmhJZDABYAQAZAAQKJwS3EAADAQA1AAQKgScAAxoACQqSF+lgACoCABoABwqcGulgACoCABkACAocD5EuALABAAAA.Dirtydragon:BAAANQAECgYIEgAAAA==.Divinedecay:BAAANQAECgUICAABNQAECgkJIwAaAE4bAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Dok:BAAANQADCgYIBgAAAA==.Donoraginn:BAAANQADCggILAAAAA==.Donos:BAAANQADCggIJwABNQADCggILAAGAAAAAA==.Dontkare:BAAANQADCgMIAwABNQAECgkJHQAYAGshAA==.Dorsai:BAAANQADCgUIBQAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQADCggIHgAAAA==.Drathiel:BAAANQAECgEIAQAAAA==.Drwho:BAAANQAECgYICQAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Du='Duckymet:BAAANQADCggICAAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dî']='Dîxon:BAAANQADCggICwABNQAFFAUIBQAOAJUUAA==.',
['Dô']='Dôz:BAAANQAECgMIAwAAAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgQIBQAAAA==.',
Ex='Exhumina:BAAANQAECgMIBQAAAA==.',
Fa='Facestealerr:BAAANQAECgEIAQAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAABNQAECoEVAAIPAAcKKQo3VwBPAQAPAAcKKQo3VwBPAQAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAAANQAECgQICQAAAA==.Flars:BAABNQAECoEdAAIbAAgKhyOBDAAaAwAbAAgKhyOBDAAaAwAAAA==.Flatliner:BAABNQAECoEZAAIDAAgKPgdudwCKAQADAAgKPgdudwCKAQAAAA==.Flik:BAAANQAECgYICwABNQAFFAMIBgABAL4QAA==.',
Fo='Forq:BAAANQADCgcICAAAAA==.',
Fr='Fran:BAAANQADCgYIBgABNQAECggIJQAUAKseAA==.Frankzappn:BAAANQAECgcIEwAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAABNQAECoEgAAIIAAgKZRcrHgBDAgAIAAgKZRcrHgBDAgAAAA==.Fruitcakes:BAAANQAECgQIEQAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAQAAAA==.Fuddrael:BAAANQAECgYIDgAAAA==.Fuddrucker:BAAANQAECgIIAgAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAAANQAECgUICwAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQAECgMIAwAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAABNQAECoEaAAIDAAgK5hXURwApAgADAAgK5hXURwApAgAAAA==.',
Gl='Glimagi:BAAANQAECgIIAwAAAA==.',
Gn='Gnxr:BAEANQAECgIIAgABNQAECgkJIwAcAF8kAA==.',
Go='Gonefishing:BAAANQADCgYIBgABNQAECgkJKAAaAAAYAA==.',
Gr='Grimjawz:BAABNQAECoEfAAIRAAkKSxTqGABOAgARAAkKSxTqGABOAgAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAcIDwAaANEMAA==.',
Gu='Gummibear:BAAANQAECgUIEQAAAA==.',
Gy='Gyr:BAAANQAECgIIAgAAAA==.',
Ha='Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAAANQAECgUICwAAAA==.Harthoon:BAACNQAFFIEOAAIUAAUKXQkWHABqAQAUAAUKXQkWHABqAQA1AAQKgSkAAx0ACQpOHZ4IACUCABQACQqqEeKFAFkCAB0ACAouH54IACUCAAAA.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Holiebelle:BAAANQAECgQICQAAAA==.Holyshield:BAAANQADCgEIAQABNQAECggIHQAKACYbAA==.Honeynoats:BAABNQAECoEdAAIKAAgKrwf0dgB9AQAKAAgKrwf0dgB9AQAAAA==.Hotdwarf:BAAANQAECgYIEQAAAA==.',
Hr='Hrumm:BAACNQAFFIEMAAIZAAUKxxDTCgBrAQAZAAUKxxDTCgBrAQA1AAQKgSIAAxkACQpHG70UAKMCABkACQpHG70UAKMCABoABQqzCCLvAPMAAAAA.',
Hu='Hullkk:BAACNQAFFIEOAAIMAAUKnyKLCAD+AQAMAAUKnyKLCAD+AQA1AAQKgSYAAgwACQq4JRELAJcDAAwACQq4JRELAJcDAAAA.Hush:BAAANQAECgMIAgAAAA==.Hutchadina:BAAANQADCgIIAgAAAA==.Hutchkins:BAAANQAECgYIEQAAAA==.Hutchknight:BAAANQAECgQIBAABNQAECgYIEQAGAAAAAA==.Hutchyo:BAAANQADCgUIBQABNQAECgYIEQAGAAAAAA==.',
Hy='Hydro:BAAANQADCgcICQAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icirus:BAABNQAECoEtAAMDAAkK/h3CFQAVAwADAAkK/h3CFQAVAwACAAQK0AgOIgGtAAAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQAECgEIAQAGAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAAANQAECggIDgAAAA==.',
It='Itzal:BAAANQAECgYIBgAAAA==.',
Ja='Jagere:BAAANQAECgYIEgAAAA==.Jahde:BAAANQAECgQICQAAAA==.Jaina:BAAANQAECgQIBQAAAA==.Jandrae:BAABNQAECoEnAAQbAAkKLhxMIABfAgAbAAgKCBxMIABfAgAOAAUKbB1RVQCUAQANAAIKqgd7rQBQAAAAAA==.Jassykins:BAAANQAECgQIBwAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jiffypop:BAAANQADCgMIAwABNQAECgMIAgAGAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQADCgQIBgABNQAECggIHwAPAFoTAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAAANQAECgYIEwAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgQICQAGAAAAAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQAECgQICAABNQAECgcIGwALAPwZAA==.Kare:BAAANQAECgYIDQABNQAECgkJHQAYAGshAA==.Karee:BAABNQAECoEdAAIYAAkKayEwCAACAwAYAAkKayEwCAACAwAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kauko:BAAANQAECggICAAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAABNQAECoEYAAINAAgKCh8kGgDFAgANAAgKCh8kGgDFAgAAAA==.',
Kh='Khold:BAAANQAECgYIDwAAAA==.',
Ki='Kissofdeath:BAAANQADCgIIAgAAAA==.',
Ko='Koltara:BAABNQAECoEZAAIIAAgKSSGGEgDBAgAIAAgKSSGGEgDBAgABNQAFFAUIDgAZALISAA==.Koltarax:BAAANQAECgEIAQABNQAFFAUIDgAZALISAA==.Koltarian:BAAANQAECgYIBgABNQAFFAUIDgAZALISAA==.Koltaros:BAAANQAECgQIBAABNQAFFAUIDgAZALISAA==.Konshis:BAABNQAECoElAAIeAAgK+x99CADrAgAeAAgK+x99CADrAgAAAA==.Kookymonster:BAABNQAECoEsAAMTAAkKpCLDBgCJAwATAAkKpCLDBgCJAwASAAIK+R9iQgCwAAAAAA==.Kos:BAACNQAFFIEMAAQOAAUKmxSoCQBSAQAOAAQKqBioCQBSAQAbAAMKAQhODQC5AAANAAEKagRXNQAbAAA1AAQKgSsAAxsACQpBIScVAMACABsACQoTICcVAMACAA4ABQo2H29OALIBAAAA.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCgcJDAAAAA==.',
Ku='Kuragaru:BAACNQAFFIEOAAIfAAUK5xHkBQCtAQAfAAUK5xHkBQCtAQA1AAQKgSkAAh8ACQqiIUIEAEoDAB8ACQqiIUIEAEoDAAAA.',
La='Lala:BAAANQADCgYIBgAAAA==.Lapis:BAABNQAECoEWAAIWAAcKxB+aMQB0AgAWAAcKxB+aMQB0AgAAAA==.',
Le='Lester:BAAANQAECgYIEgAAAA==.Levina:BAABNQAECoEoAAMQAAkKXBRnFQDMAQAPAAkKjxBPMQAyAgAQAAgKSBRnFQDMAQAAAA==.Lexysady:BAAANQAECgcIBwAAAA==.',
Li='Lidrael:BAAANQADCgYIBgABNQAECgkJKAANAK4gAA==.Lidrahl:BAABNQAECoEoAAINAAkKriCvCwBGAwANAAkKriCvCwBGAwAAAA==.Lilihunt:BAAANQADCgYIBgAAAA==.Liliria:BAABNQAECoEoAAIKAAkKHgy0VgDwAQAKAAkKHgy0VgDwAQAAAA==.Lillidân:BAAANQADCgUIBgABNQAECgkJKgAUADkeAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAAANQAECgUIDwAAAA==.',
Ln='Lnpoop:BAABNQAECoEiAAIRAAgKJRkuFwBiAgARAAgKJRkuFwBiAgAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBgAAAA==.Lonaki:BAAANQADCgIIAgAAAA==.Lorelei:BAAANQAECgUICAAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAABNQAECoEgAAIXAAgKTxsiEQCEAgAXAAgKTxsiEQCEAgAAAA==.Lucariõ:BAACNQAFFIERAAIKAAUKUSG+BwDvAQAKAAUKUSG+BwDvAQA1AAQKgSkAAgoACQoMJAwSACQDAAoACQoMJAwSACQDAAAA.Lumina:BAAANQAECgQIBAAAAA==.',
Ly='Lyllies:BAABNQAECoEfAAIaAAkKoRziNgCjAgAaAAkKoRziNgCjAgAAAA==.Lyv:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.',
Ma='Mafia:BAAANQADCggIEQAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAABNQAECoEbAAIbAAcKoQ+vPgCNAQAbAAcKoQ+vPgCNAQAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgEIAQAAAA==.Matrim:BAAANQADCggIEQAAAA==.Mattdæmon:BAABNQAECoEZAAMHAAYK9gY+UQAVAQAHAAYK9gY+UQAVAQAJAAYKOQNgHQC0AAAAAA==.',
Me='Meekogaia:BAABNQAECoFEAAMWAAgKExUTUQD0AQAWAAgKExUTUQD0AQAgAAYKMBBaiwBXAQAAAA==.Meekosan:BAAANQADCgcIBwAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQADCggICAAGAAAAAA==.Millerowntoo:BAACNQAFFIEMAAMOAAUKjB7CBQCmAQAOAAQKcCTCBQCmAQANAAEK/AZcMwAhAAA1AAQKgRsAAg4ACAqoJqkJAF8DAA4ACAqoJqkJAF8DAAAA.Millions:BAAANQAFFAIIAgABNQAFFAMIBgABAL4QAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.Mital:BAAANQABCgYICAAAAA==.',
Mj='Mjoln:BAAANQADCggICAAAAA==.',
Mo='Mobius:BAAANQADCggIFQABNQAECgUICwAGAAAAAA==.Molvnma:BAAANQAECggIAQAAAA==.Monkeycoke:BAAANQAECgUICwAAAA==.Montkriege:BAAANQAECgEIAQAAAA==.',
Mu='Murfie:BAABNQAECoEZAAIEAAgKTBd9HQAxAgAEAAgKTBd9HQAxAgAAAA==.Murica:BAAANQADCgYICgABNQAECggIJQAUAKseAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
Na='Nashira:BAAANQAECgcIEwAAAA==.Nashness:BAABNQAECoEjAAMbAAgK/iD6HQBzAgAbAAgKMxv6HQBzAgAOAAgKrB//LQBXAgAAAA==.Naturdimund:BAAANQADCgMIAwAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgYIGQAHAPYGAA==.Nesquík:BAAANQADCgUIEQAAAA==.Nezar:BAAANQAECgQIBwAAAA==.',
Ni='Nicokira:BAAANQAECgEIAQAAAA==.Niis:BAAANQAECgcIDwAAAA==.Niterage:BAAANQAECgUIEgAAAA==.',
Nn='Nn:BAAANQAECgQICQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAAANQAECggIEAAAAA==.',
['Nì']='Nìr:BAABNQAFFIEFAAIHAAQKmQ5iCwAsAQAHAAQKmQ5iCwAsAQAAAA==.',
Od='Odinrex:BAAANQAECggIDQAAAA==.',
Op='Opuntia:BAAANQAECgIIAwAAAA==.',
Or='Orexion:BAAANQADCgUIBQAAAA==.',
Ow='Ownham:BAAANQAECgcIDAABNQAFFAUIDAAOAIweAA==.',
Pa='Paddingidiot:BAABNQAFFIEOAAIZAAUKshJQCgB0AQAZAAUKshJQCgB0AQAAAA==.Paladinheal:BAAANQAECgYIDwAAAA==.Pallypaladin:BAACNQAFFIEMAAICAAUKohLDCACTAQACAAUKohLDCACTAQA1AAQKgTAAAgIACQpSI8kSAGwDAAIACQpSI8kSAGwDAAAA.Partywolf:BAAANQAECgQIBwAAAA==.',
Ph='Phatzero:BAABNQAECoEjAAIaAAkKThv0HgAAAwAaAAkKThv0HgAAAwAAAA==.',
Pi='Pinjo:BAAANQAECgYICQAAAA==.',
Po='Polard:BAAANQAECgYIEAAAAA==.Pownown:BAAANQAECgQIBAABNQAFFAUIDAAOAIweAA==.',
Pr='Procreeper:BAAANQAECgEIAQABNQAECgkJIwAVAIckAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAAANQAECgQIBQABNQAECggIFwAMACccAA==.',
Ra='Rabit:BAAANQAECgEIAQAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rafïki:BAAANQADCgYIBgAAAA==.Rainyblu:BAAANQADCggIFAAAAA==.Rawrshåk:BAABNQAECoEgAAIMAAgKOR5DPAC/AgAMAAgKOR5DPAC/AgAAAA==.',
Rb='Rb:BAAANQAECgEIAQAAAA==.',
Rc='Rc:BAABNQAECoEaAAIXAAcKtBZXHADnAQAXAAcKtBZXHADnAQAAAA==.',
Rh='Rhodraco:BAAANQAECgQICQAAAA==.Rhownyn:BAAANQADCgIIAgAAAA==.Rhoxy:BAAANQADCggIDgAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAABNQAECoEaAAIMAAcKfBZmiwDZAQAMAAcKfBZmiwDZAQABNQAECgcKGgAMAHwWAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Rq='Rq:BAAANQAECgMIBAAAAA==.',
Ry='Ryyukken:BAAANQAECgIIAwAAAA==.',
['Rà']='Ràwrshåk:BAAANQADCgQJBAAAAA==.',
Sa='Saella:BAAANQADCgcIFQAAAA==.Sakarja:BAAANQADCgQIBAAAAA==.Saluda:BAAANQAECgIIAgAAAA==.Samesde:BAAANQAECgQIBgAAAA==.Samras:BAAANQAECgEIAQAAAA==.Saphyria:BAAANQABCgIIAgAAAA==.Sarentu:BAABNQAECoEaAAIcAAkK2RdSGQBNAgAcAAkK2RdSGQBNAgAAAA==.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQADCgUIBgAAAA==.Senile:BAAANQAECgQICQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.Sesnic:BAAANQAECgMIAwAAAA==.',
Sh='Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgYICwABNQADCgYIBgAGAAAAAA==.Shadydk:BAAANQADCgQIBAABNQADCgYIBgAGAAAAAA==.Shadylid:BAAANQADCgYIBgAAAA==.Shadysmash:BAAANQADCgYIBwAAAA==.Shadyvoid:BAAANQAECgQIBgABNQADCgYIBgAGAAAAAA==.Shadówglider:BAAANQAECgIIAwAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAABNQAECoEXAAIIAAgK+h7WEwCzAgAIAAgK+h7WEwCzAgAAAA==.Shamallaman:BAAANQAECgUJCAABNQAECggIGAACALMiAA==.Sharkweek:BAAANQAECgMIAwAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shydestroyer:BAAANQADCgMIAwAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.Sinfulness:BAAANQAECgQICAAAAA==.',
Sk='Skikette:BAABNQAECoEbAAITAAcKMgcKqABTAQATAAcKMgcKqABTAQAAAA==.Skinrot:BAABNQAECoEbAAIRAAgKHAyfKwCLAQARAAgKHAyfKwCLAQAAAA==.',
Sm='Smig:BAAANQAECgMICAAAAA==.',
Sn='Snowball:BAAANQAECgUICgAAAA==.',
So='Soeki:BAAANQAECgQIBwAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAABNQAECoEbAAISAAcKQRS4EQDfAQASAAcKQRS4EQDfAQAAAA==.Soullovez:BAAANQAECgYIEwABNQAECgcIGwASAEEUAA==.Soulshocks:BAAANQAECgYIEwABNQAECgcIGwASAEEUAA==.Soulviver:BAABNQAECoEgAAIKAAgKrhBpXQDZAQAKAAgKrhBpXQDZAQAAAA==.',
Sp='Spiritwarden:BAAANQAECggIEwAAAA==.Spliffy:BAAANQADCgQIBAAAAA==.Splootz:BAAANQADCggIEAABNQAECggICQAGAAAAAA==.Spoiledbratt:BAAANQABCgUIBQAAAA==.',
Sq='Squirtdadday:BAAANQAECgIJAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECoEoAAQMAAkK6SQ8CQCkAwAMAAkKaCM8CQCkAwALAAYKyCBcCwDpAQABAAEKQiJnMwBfAAAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Suxor:BAAANQAECgQIDQAAAA==.',
Sw='Swordboardal:BAABNQAECoElAAIBAAkKGxWFDQAtAgABAAkKGxWFDQAtAgAAAA==.',
Sy='Sybius:BAAANQAECgQJCAAAAA==.Symptom:BAAANQAECgEIAQAAAA==.Syncophat:BAAANQAECgQICgAAAA==.',
Ta='Tad:BAAANQAECgMIAgAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQAECgIIAwAAAA==.Talanzen:BAABNQAECoEYAAIUAAgKBCTWMgAZAwAUAAgKBCTWMgAZAwAAAA==.Talonia:BAAANQADCggICAABNQAECgYIEgAGAAAAAA==.Tanakiko:BAAANQABCgUIBQAAAA==.Tarrzok:BAAANQADCgcIBQABNQADCgYIBgAGAAAAAA==.',
Te='Teacup:BAAANQAECgIIBgABNQAECgcIEAAGAAAAAA==.',
Th='Thrakara:BAACNQAFFIEOAAMeAAUKUAWbBABWAQAeAAUKUAWbBABWAQAcAAMKoAqjCgDKAAA1AAQKgSwAAx4ACQp/GdsOAG0CAB4ACQp/GdsOAG0CABwAAwobIvE4ABUBAAAA.Thrakaru:BAABNQAECoEeAAIUAAkKCxJtgABlAgAUAAkKCxJtgABlAgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgIIAgAAAA==.Thundrall:BAAANQAECgIIBAAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAABNQAECoEYAAIhAAgKUh2pFQCqAgAhAAgKUh2pFQCqAgAAAA==.Tioshadow:BAAANQAECgIIAwABNQAFFAMIBQAcAA4RAA==.',
To='Torches:BAAANQADCgcIBwAAAA==.Totemissues:BAAANQABCgMIAwABNQAECgkJIwAaAE4bAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFIEWAAIMAAcKlR4zAwCQAgAMAAcKlR4zAwCQAgA1AAQKgRsAAgwACQoyI/gnAAoDAAwACQoyI/gnAAoDAAAA.Trystrom:BAAANQADCgYIDAAAAA==.',
Ts='Tsuo:BAAANQAECgcIDQAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txblood:BAAANQADCgcJCAAAAA==.Txgunny:BAAANQAECgUICwAAAA==.Txstormin:BAAANQADCgMJAwAAAA==.',
Ty='Tymptriss:BAAANQAECgIIBQAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbrage:BAAANQAECggIDgABNQAFFAUIDAAXAI4VAA==.Umbren:BAAANQAECgYIEgAAAA==.',
Ur='Urabadkity:BAAANQADCgYICwAAAA==.',
Us='Usefulmelee:BAAANQAECggIDQABNQAFFAUIDgAZALISAA==.',
Va='Valartha:BAAANQAECgIIAwAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velsea:BAAANQAECgMIAgAAAA==.Velstadt:BAAANQAECgYIEwAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAABNQAECoEdAAIYAAgKIhuZEQBhAgAYAAgKIhuZEQBhAgAAAA==.Vermilion:BAAANQAECgIIAwAAAA==.',
Vh='Vholatile:BAAANQAECgcIDQAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgUIDwAAAQ==.',
Vo='Voidherron:BAAANQAECgMIBwAAAA==.Voidknight:BAAANQADCgcICQAAAA==.Voodoomama:BAAANQADCgYIEQAAAA==.',
Wa='Warlockbot:BAACNQAFFIENAAITAAUKcxAuDACBAQATAAUKcxAuDACBAQA1AAQKgSAAAhMACQrgHnwqAMICABMACQrgHnwqAMICAAAA.Warmongral:BAAANQADCgQICQAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAAANQAECgQICwAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEgABNQAECggIGAAhAFIdAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggICAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIAwAAAA==.Woolala:BAABNQAECoEoAAIaAAkKABi1NQCnAgAaAAkKABi1NQCnAgAAAA==.',
Wr='Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQADCgYICgABNQAECggIIAAXAE8bAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMIAwAAAA==.',
Ya='Yaana:BAAANQADCggIDwAAAA==.Yazmyn:BAAANQAECgYIDgAAAA==.',
Ye='Yerehmi:BAAANQADCgYICQAAAA==.',
Yu='Yuny:BAAANQAECgYIEwAAAA==.',
Za='Zaier:BAABNQAECoEqAAMDAAkKSBr4JAC/AgADAAkKSBr4JAC/AgACAAUKMhF+2QAuAQAAAA==.',
Ze='Zeltan:BAABNQAECoFBAAIDAAkKwB2/EgApAwADAAkKwB2/EgApAwAAAA==.',
Zh='Zhundrenga:BAAANQAECgIIAwAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
['År']='Åres:BAAANQADCgEIAQAAAA==.',
['ßl']='ßlastvenom:BAAANQADCgYICQAAAA==.',
['ßä']='ßäbaracus:BAAANQADCgQIBAAAAA==.',
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
