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

local lookup = {'Warrior-Protection','Priest-Shadow','Priest-Discipline','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','DeathKnight-Blood','DeathKnight-Unholy','Priest-Holy','Druid-Balance','Druid-Guardian','Druid-Restoration','Mage-Arcane','Druid-Feral','Shaman-Restoration','Evoker-Preservation','Warrior-Arms','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','Paladin-Holy','Mage-Frost','Paladin-Retribution','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Rogue-Subtlety','Shaman-Elemental','Monk-Windwalker','Warrior-Fury',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acks:BAAANQADCgYICgABNQAFFAIIBQABAHEUAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAAANQAECgcIDQAAAA==.Aex:BAAANQAECgcIEgABNQAFFAIIBQABAHEUAA==.',
Ah='Ahnkhano:BAAANQADCgcJDQAAAA==.',
Ai='Ainge:BAAANQAECgEJAQAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFIESAAMCAAcK/BazAQA2AgACAAYKexqzAQA2AgADAAEKFgJCAwBHAAA1AAQKgS4AAwIACQpQJacCAKUDAAIACQpQJacCAKUDAAMAAgoMF+4WAIIAAAAA.Akorius:BAAANQAECgIIAgAAAA==.',
Al='Allistrana:BAAANQAECgYIDQAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alpacalyptic:BAAANQAECgYIBgAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgYIDAAEAAAAAA==.Amairis:BAAANQAECgMIBQAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAABNQAECoEfAAQFAAgKJR6ZGQCJAgAFAAgKVh2ZGQCJAgAGAAYKThYCMAB/AQAHAAIKpB8fGQC1AAAAAA==.Antiflag:BAAANQAECgYIBgAAAA==.',
At='Ataliya:BAAANQAECgQJBQAAAA==.',
Au='Auranar:BAAANQAECgQIBgAAAA==.Aurelya:BAAANQAECgUIEQAAAA==.Aurilia:BAAANQAECgEIAQAAAA==.',
Av='Avanicus:BAAANQAECgYICwAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBAAAAA==.Avé:BAAANQAECgYIDwAAAA==.',
Ax='Axellent:BAABNQAFFIEFAAIBAAIKcRQyBACCAAABAAIKcRQyBACCAAAAAA==.Axiomlegacy:BAABNQAECoEXAAMIAAcKDh5bKQA9AgAIAAcKDh5bKQA9AgAJAAEKpwiRswAuAAAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgMIBgAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAAANQAECgUIEgAAAA==.Bar:BAABNQAECoEdAAMCAAkK1RdoGgAvAgACAAgKARdoGgAvAgAKAAgKTQsSZACNAQAAAA==.',
Be='Bearlyshady:BAABNQAECoEgAAQLAAkKfxfqLQAqAgALAAgKSxbqLQAqAgAMAAQKlAzcKgCyAAANAAEKugOTWwAxAAAAAA==.Bellarina:BAAANQADCggIGQAAAA==.Bellatrixie:BAAANQAECgQIDwAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQADCggIEQAAAA==.Bermy:BAAANQAECgcIEgAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAABNQAECoEdAAIOAAgKlxxRcwBiAgAOAAgKlxxRcwBiAgAAAA==.Biku:BAAANQAECgIIAgAAAA==.',
Bl='Blackhawkdk:BAABNQAECoEYAAMJAAgKLhTeNwDlAQAJAAgKHRTeNwDlAQAIAAEKhxVHpgA/AAAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBQAAAA==.Blindwarrior:BAAANQAECgIIAgAAAA==.Bloodshadow:BAAANQAECgUICgAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgcICgAAAA==.',
Br='Breakcooloz:BAAANQAECgQIBgABNQAFFAUIBQAJAJUUAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIJAgAEAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAAANQAECgUIDwAAAA==.Broom:BAAANQAECgQIBAABNQAECggIHQAOAJccAA==.Brutak:BAAANQADCggJCAAAAA==.',
Bu='Burstinurass:BAACNQAFFIEFAAIJAAUKlRRWAwCnAQAJAAUKlRRWAwCnAQA1AAQKgRUAAgkACQoaHfwOABQDAAkACQoaHfwOABQDAAAA.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Caelix:BAAANQAECgIIAgAAAA==.Carbo:BAAANQAECgYIBgABNQAECgkJIwAPAIckAA==.Carbonight:BAABNQAECoEjAAIPAAkKhyQAAgB4AwAPAAkKhyQAAgB4AwAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECgcIFQAQAHYOAA==.Cellyne:BAAANQAECgMIBQAAAA==.',
Ch='Chaoswind:BAABNQAECoEgAAIQAAgKVxudLgBmAgAQAAgKVxudLgBmAgAAAA==.Charlee:BAAANQADCgYIBgAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwAEAAAAAA==.Chelives:BAEANQAECgQIBgAAAA==.Chertheif:BAAANQADCgQIBgABNQAECggIAgAEAAAAAA==.Cherubix:BAAANQAECggIAgAAAA==.Chromus:BAACNQAFFIEJAAIRAAUKjhVKBgCnAQARAAUKjhVKBgCnAQA1AAQKgR4AAhEACQoKHNYKANMCABEACQoKHNYKANMCAAAA.',
Ci='Cires:BAAANQAECgYIDAAAAA==.',
Co='Colanasou:BAAANQADCggIHgAAAA==.Coldbattler:BAAANQAECgQIBwAAAA==.Convictions:BAAANQAECgYICwABNQAFFAcIFgASAJUeAA==.Corrick:BAAANQAECgEIAgAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAMIBQAAAQ==.',
Cy='Cydric:BAAANQAECgYICwAAAA==.',
Da='Daarrkstar:BAAANQADCggIHQABNQAECgQIBQAEAAAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.Damageguy:BAAANQAECgYIBgABNQAFFAUICQASAC8iAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCgcICgAAAA==.Deathrival:BAAANQADCggICAAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgUIBQAAAA==.Demonkare:BAAANQAECgUIBQABNQAECgkJGgATABAgAA==.Demoray:BAACNQAFFIEYAAMUAAcKcyC4AgArAgAUAAYKFyC4AgArAgAVAAEKmSI5HgBpAAA1AAQKgSEAAxQACQo0JdwEAHEDABQACQo0JdwEAHEDABUAAQr5GEsNAUYAAAAA.Demvinity:BAAANQAECgEIAQAAAA==.Dethrone:BAAANQAECgcIEQAAAA==.Deus:BAABNQAECoEnAAMCAAYKvhaMJgCmAQACAAYKvhaMJgCmAQADAAMKLBbmEQDQAAAAAA==.',
Di='Dinosocks:BAACNQAFFIENAAMVAAUKMBBNCABfAQAVAAQKmhJNCABfAQAUAAIK6QNDFwB4AAA1AAQKgSAAAxUACQpGFbhgAAECABUABwrGF7hgAAECABQACAo6DuIqAKMBAAAA.Dirtydragon:BAAANQAECgUIDwAAAA==.Divinedecay:BAAANQAECgQIBgABNQAECgkJGwAVADMVAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Dok:BAAANQADCgYIBgAAAA==.Donoraginn:BAAANQADCggIJAAAAA==.Donos:BAAANQADCggIIQABNQADCggIJAAEAAAAAA==.Dorsai:BAAANQADCgUIBQAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQADCggIHgAAAA==.Drathiel:BAAANQADCggIDAABNQAECgEIAQAEAAAAAA==.Drwho:BAAANQAECgUICAAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dî']='Dîxon:BAAANQADCggICwABNQAFFAUIBQAJAJUUAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgQIBQAAAA==.',
Ex='Exhumina:BAAANQAECgMIAwAAAA==.',
Fa='Facestealerr:BAAANQAECgEIAQAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAAANQAECgUIDAAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAAANQAECgMIBQAAAA==.Flars:BAABNQAECoEVAAIWAAgK+CFtDQD1AgAWAAgK+CFtDQD1AgAAAA==.Flatliner:BAABNQAECoEZAAIXAAgKPgemZwCRAQAXAAgKPgemZwCRAQAAAA==.Flik:BAAANQAECgUIBQABNQAFFAIIBQABAHEUAA==.',
Fo='Forq:BAAANQADCgcICAAAAA==.',
Fr='Fran:BAAANQADCgYIBgABNQAECggIHQAOAJccAA==.Frankzappn:BAAANQAECgUIDAAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAABNQAECoEYAAIGAAgKwRVYHAA7AgAGAAgKwRVYHAA7AgAAAA==.Fruitcakes:BAAANQAECgQIDQAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAQAAAA==.Fuddrael:BAAANQAECgYIDgAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAAANQAECgQIBgAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQAECgEIAQAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAABNQAECoEWAAIXAAgKOhTTRgAJAgAXAAgKOhTTRgAJAgAAAA==.',
Gl='Glimagi:BAAANQAECgEIAQAAAA==.',
Go='Gonefishing:BAAANQADCgYIBgABNQAECgkJIAAVAJsXAA==.Gotêtsu:BAAANQADCggICAAAAA==.',
Gr='Grimjawz:BAABNQAECoEXAAINAAgKvRFUHgDkAQANAAgKvRFUHgDkAQAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAUIDQAVADAQAA==.',
Gu='Gummibear:BAAANQAECgUIDQAAAA==.',
Gy='Gyr:BAAANQAECgIIAgAAAA==.',
Ha='Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAAANQAECgQJBgAAAA==.Harthoon:BAACNQAFFIEJAAIOAAUKkAgFFQBzAQAOAAUKkAgFFQBzAQA1AAQKgSUAAxgACQpOHXQGAFACAA4ACQoyEfd4AFUCABgACAouH3QGAFACAAAA.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Holiebelle:BAAANQAECgMIBQAAAA==.Holyshield:BAAANQADCgEIAQABNQAECggIHAAKACYbAA==.Honeynoats:BAAANQAECgYIEQAAAA==.Hotdwarf:BAAANQAECgQICwAAAA==.',
Hr='Hrumm:BAACNQAFFIEJAAIUAAUKxxAaCAB9AQAUAAUKxxAaCAB9AQA1AAQKgR4AAxQACQpHG00QAMACABQACQpHG00QAMACABUABQqzCGDRAPQAAAAA.',
Hu='Hullkk:BAACNQAFFIEJAAISAAUKLyKUBgD1AQASAAUKLyKUBgD1AQA1AAQKgSIAAhIACQq4JSoHAKsDABIACQq4JSoHAKsDAAAA.Hush:BAAANQAECgMIAgAAAA==.Hutchadina:BAAANQADCgIIAgAAAA==.Hutchkins:BAAANQAECgYICwAAAA==.Hutchknight:BAAANQAECgQIBAABNQAECgYICwAEAAAAAA==.Hutchyo:BAAANQABCgQIAwABNQAECgYICwAEAAAAAA==.',
Hy='Hydro:BAAANQADCgcICQAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icirus:BAABNQAECoElAAMXAAkKzBztFQD+AgAXAAkKzBztFQD+AgAZAAQK0AiU/QCwAAAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAAANQAECgYIBwAAAA==.Invasion:BAAANQADCggICAAAAA==.',
It='Itzal:BAAANQAECgYIBgAAAA==.',
Ja='Jagere:BAAANQAECgYIDAAAAA==.Jahde:BAAANQAECgQIBwAAAA==.Jaina:BAAANQAECgEJAQAAAA==.Jandrae:BAABNQAECoEiAAQWAAgKwBxOHQBUAgAWAAgKoRtOHQBUAgAJAAQK4B54UABpAQAIAAIKqgfVnQBTAAAAAA==.Jassykins:BAAANQAECgIIAwAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jiffypop:BAAANQADCgMIAwABNQAECgMIAgAEAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQADCgQIBgABNQAECgcIEAAEAAAAAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAAANQAECgUIDQAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgQIBwAEAAAAAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQAECgIIBAABNQAECgUIEgAEAAAAAA==.Kare:BAAANQAECgUIDAABNQAECgkJGgATABAgAA==.Karee:BAABNQAECoEaAAITAAkKECAsBwABAwATAAkKECAsBwABAwAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAABNQAECoEYAAIIAAgKCh8TFQDXAgAIAAgKCh8TFQDXAgAAAA==.',
Kh='Khold:BAAANQAECgUICQAAAA==.',
Ki='Kissofdeath:BAAANQADCgIIAgAAAA==.',
Ko='Koltara:BAABNQAECoEZAAIGAAgKSSFdDwDVAgAGAAgKSSFdDwDVAgABNQAFFAUICQAUAJ4SAA==.Koltarax:BAAANQAECgEIAQABNQAFFAUICQAUAJ4SAA==.Koltarian:BAAANQAECgYIBgABNQAFFAUICQAUAJ4SAA==.Koltaros:BAAANQAECgQIBAABNQAFFAUICQAUAJ4SAA==.Konshis:BAABNQAECoEdAAIaAAcKahVrFgC+AQAaAAcKahVrFgC+AQAAAA==.Kookymonster:BAABNQAECoEiAAMbAAkK5CC5KQCnAgAbAAcKKCG5KQCnAgAcAAIK+R8XPgC1AAAAAA==.Kos:BAACNQAFFIEHAAMWAAUK2gebCgC+AAAWAAMKAQibCgC+AAAJAAIKnwfIDwCMAAA1AAQKgScAAxYACQpzIIcPANwCABYACQoTIIcPANwCAAkAAQoXF2OpADwAAAAA.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCgcJDAAAAA==.',
Ku='Kuragaru:BAACNQAFFIEJAAIdAAUKUA/eBACnAQAdAAUKUA/eBACnAQA1AAQKgSUAAh0ACQplIIQEADkDAB0ACQplIIQEADkDAAAA.',
La='Lapis:BAAANQAECgUIDwAAAA==.',
Le='Lester:BAAANQAECgUIDAAAAA==.Levina:BAABNQAECoEeAAMMAAkKShP5DwDcAQAMAAgKSBT5DwDcAQALAAkKdgfVPgCxAQAAAA==.Lexysady:BAAANQADCgcIEgAAAA==.',
Li='Lidrael:BAAANQADCgYIBgABNQAECgkJIAAIAGEeAA==.Lidrahl:BAABNQAECoEgAAIIAAkKYR5tDgAXAwAIAAkKYR5tDgAXAwAAAA==.Lilihunt:BAAANQADCgYIBgAAAA==.Liliria:BAABNQAECoEgAAIKAAkKHgyISAD8AQAKAAkKHgyISAD8AQAAAA==.Lillidân:BAAANQADCgUIBgABNQAECgkJJgAOACceAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAAANQAECgUICgAAAA==.',
Ln='Lnpoop:BAABNQAECoEeAAINAAgK3RjDFQBOAgANAAgK3RjDFQBOAgAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBgAAAA==.Lorelei:BAAANQAECgQIBgAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAABNQAECoEYAAIRAAgK2RoSDwCLAgARAAgK2RoSDwCLAgAAAA==.Lucariõ:BAACNQAFFIEMAAIKAAUKYB87BgDqAQAKAAUKYB87BgDqAQA1AAQKgSYAAgoACQoMJPkMADUDAAoACQoMJPkMADUDAAAA.Lumina:BAAANQAECgIIAgAAAA==.',
Ly='Lyllies:BAABNQAECoEcAAIVAAkKoRwsKwCvAgAVAAkKoRwsKwCvAgAAAA==.Lyv:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
Ma='Mafia:BAAANQADCggIEQAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAAANQAECgYIEQAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgEIAQAAAA==.Matrim:BAAANQADCggIEQAAAA==.Mattdæmon:BAAANQAECgUIDwAAAA==.',
Me='Meekogaia:BAABNQAECoE0AAMQAAgKExXsRAAAAgAQAAgKExXsRAAAAgAeAAYKpg8gewBbAQAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQADCggICAAEAAAAAA==.Millerowntoo:BAACNQAFFIEIAAMJAAUKQx0qBQBtAQAJAAQK1SIqBQBtAQAIAAEK/Aa/KwAhAAA1AAQKgRcAAgkACAqoJtEGAHMDAAkACAqoJtEGAHMDAAAA.Millions:BAAANQAECgcIBwABNQAFFAIIBQABAHEUAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.Mital:BAAANQABCgMIAwAAAA==.',
Mj='Mjoln:BAAANQADCggICAAAAA==.',
Mo='Mobius:BAAANQADCggIFQABNQAECgQIBgAEAAAAAA==.Molvnma:BAAANQAECggIAQAAAA==.Monkeycoke:BAAANQAECgQIBgAAAA==.Montkriege:BAAANQADCgcIEAAAAA==.',
Mu='Murfie:BAAANQAECgcIEgAAAA==.Murica:BAAANQADCgYICgABNQAECggIHQAOAJccAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
Na='Nashira:BAAANQAECgYIEQAAAA==.Nashness:BAABNQAECoEjAAMJAAgK/iCqHQCTAgAJAAgKrB+qHQCTAgAWAAgKMxuvFgCQAgAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgUIDwAEAAAAAA==.Nesquík:BAAANQADCgUIDgAAAA==.Nezar:BAAANQAECgMIAwAAAA==.',
Ni='Nicokira:BAAANQAECgEIAQAAAA==.Niis:BAAANQAECgcIDwAAAA==.Niterage:BAAANQAECgUIDQAAAA==.',
Nn='Nn:BAAANQAECgMIBQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAAANQAECgYICQAAAA==.',
['Nì']='Nìr:BAAANQAFFAEIAQAAAA==.',
Od='Odinrex:BAAANQAECggICQAAAA==.',
Op='Opuntia:BAAANQAECgEIAQAAAA==.',
Ow='Ownham:BAAANQAECgQIBAABNQAFFAUICAAJAEMdAA==.',
Pa='Paddingidiot:BAABNQAFFIEJAAIUAAUKnhLKBwCDAQAUAAUKnhLKBwCDAQAAAA==.Paladinheal:BAAANQAECgMIAwAAAA==.Pallypaladin:BAACNQAFFIEIAAIZAAUK7hBEBgCXAQAZAAUK7hBEBgCXAQA1AAQKgSgAAhkACQpSI4UNAH0DABkACQpSI4UNAH0DAAAA.Partywolf:BAAANQAECgMIAwAAAA==.',
Ph='Phatzero:BAABNQAECoEbAAIVAAkKMxVEQABiAgAVAAkKMxVEQABiAgAAAA==.',
Pi='Pinjo:BAAANQAECgUICAAAAA==.',
Po='Polard:BAAANQAECgUIDwAAAA==.',
Pr='Procreeper:BAAANQAECgEIAQABNQAECgkJIwAPAIckAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAAANQAECgEIAQABNQAECgYIEAAEAAAAAA==.',
Ra='Rabit:BAAANQAECgEIAQAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rainyblu:BAAANQADCggIDwAAAA==.Rawrshåk:BAABNQAECoEYAAISAAcKKx/VSgBrAgASAAcKKx/VSgBrAgAAAA==.',
Rc='Rc:BAAANQAECgYIEgAAAA==.',
Rh='Rhodraco:BAAANQAECgMIBQAAAA==.Rhownyn:BAAANQABCgQIBQAAAA==.Rhoxy:BAAANQADCgYIBgAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAAANQAECgUIDwABNQADCggIHwAEAAAAAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Rq='Rq:BAAANQAECgIIAgAAAA==.',
Ry='Ryyukken:BAAANQAECgIIAwAAAA==.',
['Rà']='Ràwrshåk:BAAANQADCgQJBAAAAA==.',
Sa='Saella:BAAANQADCgYIFAAAAA==.Saluda:BAAANQABCgIIAgAAAA==.Samesde:BAAANQAECgMIAgAAAA==.Saphyria:BAAANQABCgIIAgAAAA==.Sarentu:BAABNQAECoEXAAIfAAkKxhfQFQBUAgAfAAkKxhfQFQBUAgAAAA==.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQADCgUIBgAAAA==.Senile:BAAANQAECgMIBQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.Sesnic:BAAANQADCggICAAAAA==.',
Sh='Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgYICwABNQAECgkJIAALAH8XAA==.Shadydk:BAAANQADCgQIBAABNQAECgkJIAALAH8XAA==.Shadysmash:BAAANQADCgIIAgAAAA==.Shadyvoid:BAAANQAECgQIBgABNQAECgkJIAALAH8XAA==.Shadówglider:BAAANQAECgEJAQAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAAANQAECgYIEQAAAA==.Shamallaman:BAAANQAECgUJCAABNQAECgcIDgAEAAAAAA==.Sharkweek:BAAANQAECgMIAwAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shydestroyer:BAAANQADCgMIAwAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.Sinfulness:BAAANQAECgMIBAAAAA==.',
Sk='Skikette:BAAANQAECgUIEAAAAA==.Skinrot:BAAANQAECgYIEQAAAA==.',
Sm='Smig:BAAANQAECgMIBQAAAA==.',
Sn='Snowball:BAAANQAECgMIBQAAAA==.',
So='Soeki:BAAANQAECgIIAwAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAAANQAECgYIDwABNQAECgYIEAAEAAAAAA==.Soullovez:BAAANQAECgYIEAAAAA==.Soulshocks:BAAANQAECgUIDQABNQAECgYIEAAEAAAAAA==.Soulviver:BAABNQAECoEYAAIKAAgKcw4+VQDHAQAKAAgKcw4+VQDHAQAAAA==.',
Sp='Spiritwarden:BAAANQAECgYIDAAAAA==.Spliffy:BAAANQADCgQIBAAAAA==.Splootz:BAAANQADCggIEAABNQAECgEIAQAEAAAAAA==.',
Sq='Squirtdadday:BAAANQAECgIJAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECoEiAAQSAAkKQyTyDgBxAwASAAkK/yHyDgBxAwAgAAYKyCBdCQD0AQABAAEKQiJmLABiAAAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Suxor:BAAANQAECgQICQAAAA==.',
Sw='Swordboardal:BAABNQAECoEiAAIBAAkKDROTDAAWAgABAAkKDROTDAAWAgAAAA==.',
Sy='Sybius:BAAANQAECgQJCAAAAA==.Symptom:BAAANQAECgEJAQAAAA==.Syncophat:BAAANQAECgQICgAAAA==.',
Ta='Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQAECgEIAQAAAA==.Talanzen:BAABNQAECoEWAAIOAAgKBCS1KAAoAwAOAAgKBCS1KAAoAwAAAA==.Tarrzok:BAAANQADCgcIAwABNQAECgkJIAALAH8XAA==.',
Te='Teacup:BAAANQAECgIIBAABNQAECgYJDgAEAAAAAA==.',
Th='Thrakara:BAACNQAFFIEJAAMaAAUKFQyABAAVAQAaAAQKQwaABAAVAQAfAAMKUAmCCADPAAA1AAQKgSgAAxoACQp7GR4MAIgCABoACQp7GR4MAIgCAB8AAwobIvUwACABAAAA.Thrakaru:BAAANQAECgcIEgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgIIAgAAAA==.Thundrall:BAAANQAECgEIAgAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAAANQAECggIEwAAAA==.Tioshadow:BAAANQADCgMIAwABNQAECgkJJgAfALgcAA==.',
To='Torches:BAAANQADCgcIBwAAAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFIEWAAISAAcKlR7WAQCiAgASAAcKlR7WAQCiAgA1AAQKgRsAAhIACQoyIzoeAB0DABIACQoyIzoeAB0DAAAA.Trystrom:BAAANQADCgYIDAAAAA==.',
Ts='Tsuo:BAAANQAECgcIDQAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txblood:BAAANQADCgcJCAAAAA==.Txgunny:BAAANQAECgQIBgAAAA==.Txstormin:BAAANQADCgMJAwAAAA==.',
Ty='Tymptriss:BAAANQAECgIIAwAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbrage:BAAANQAECgYIBgABNQAFFAUICQARAI4VAA==.Umbren:BAAANQAECgYIDAAAAA==.',
Ur='Urabadkity:BAAANQADCgQIBgAAAA==.',
Us='Usefulmelee:BAAANQAECgUIBQABNQAFFAUICQAUAJ4SAA==.',
Va='Valartha:BAAANQAECgEIAQAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velstadt:BAAANQAECgUIDQAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAABNQAECoEWAAITAAgK6BiZEgApAgATAAgK6BiZEgApAgAAAA==.Vermilion:BAAANQAECgEIAQAAAA==.',
Vh='Vholatile:BAAANQAECgcIDQAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgQICgAAAQ==.',
Vo='Voidherron:BAAANQAECgMIBQAAAA==.Voidknight:BAAANQADCgcICQAAAA==.Voodoomama:BAAANQADCgYIEQAAAA==.',
Wa='Warlockbot:BAACNQAFFIEJAAIbAAQKQw0RDgAtAQAbAAQKQw0RDgAtAQA1AAQKgR4AAhsACQrjHFAkAL4CABsACQrjHFAkAL4CAAAA.Warmongral:BAAANQADCgQICQAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAAANQAECgMIBwAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEgABNQAECggIEwAEAAAAAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggICAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIAwAAAA==.Woolala:BAABNQAECoEgAAIVAAkKmxeFLgCiAgAVAAkKmxeFLgCiAgAAAA==.',
Wr='Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQADCgYICgABNQAECggIGAARANkaAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMIAwAAAA==.',
Ya='Yaana:BAAANQADCgcIBwAAAA==.Yazmyn:BAAANQAECgUIDQAAAA==.',
Ye='Yerehmi:BAAANQADCgYICQAAAA==.',
Yu='Yuny:BAAANQAECgYIDQAAAA==.',
Za='Zaier:BAABNQAECoEiAAIXAAkKSBqRHgDHAgAXAAkKSBqRHgDHAgAAAA==.',
Ze='Zeltan:BAABNQAECoEwAAIXAAgKqR7HGQDkAgAXAAgKqR7HGQDkAgAAAA==.',
Zh='Zhundrenga:BAAANQAECgEIAQAAAA==.',
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
