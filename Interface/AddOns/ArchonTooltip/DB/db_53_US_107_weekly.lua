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

local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Discipline','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Druid-Balance','Druid-Guardian','Druid-Feral','Shaman-Restoration','Evoker-Preservation','Warrior-Arms','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Druid-Restoration','Mage-Frost','Mage-Arcane','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Rogue-Subtlety','Shaman-Elemental','Warrior-Fury','Warrior-Protection','Monk-Mistweaver','Warlock-Demonology',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acks:BAAANQADCgYICgABNQAFFAIJAwABAAAAAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAAANQAECgYIDAAAAA==.Aex:BAAANQAECgcIEgABNQAFFAIJAwABAAAAAA==.',
Ah='Ahnkhano:BAAANQADCgcJDQAAAA==.',
Ai='Ainge:BAAANQAECgEJAQAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFIENAAMCAAUKqhQnBAB0AQACAAQKVBknBAB0AQADAAEKFgKaAgBHAAA1AAQKgSsAAwIACQovJZMBAMEDAAIACQovJZMBAMEDAAMAAgoMF2cTAIQAAAAA.Akorius:BAAANQAECgIIAgAAAA==.',
Al='Allistrana:BAAANQAECgQIBwAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgQJBgABAAAAAA==.Amairis:BAAANQAECgEJAgAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAABNQAECoEYAAQEAAgKoR0mFwB5AgAEAAgKaxwmFwB5AgAFAAYKsBXWKgCRAQAGAAIKpB/eEwC6AAAAAA==.Antiflag:BAAANQAECgYIBgAAAA==.',
At='Ataliya:BAAANQAECgQJBQAAAA==.',
Au='Auranar:BAAANQAECgQJBAAAAA==.Aurelya:BAAANQAECgUIDgAAAA==.Aurilia:BAAANQAECgEJAQAAAA==.',
Av='Avanicus:BAAANQAECgIIBQAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBAAAAA==.Avé:BAAANQAECgUJCQAAAA==.',
Ax='Axellent:BAAANQAFFAIJAwAAAA==.Axiomlegacy:BAAANQAECgYJEwAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgIJAwAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAAANQAECgUJDQAAAA==.Bar:BAABNQAECoEaAAMCAAkKyxPnFwAnAgACAAgKdRLnFwAnAgAHAAgKTQuoUACZAQAAAA==.',
Be='Bearlyshady:BAABNQAECoEXAAMIAAgKkBTgLAD/AQAIAAgKEhTgLAD/AQAJAAQKlAzVIAC4AAAAAA==.Bellarina:BAAANQADCggIGQAAAA==.Bellatrixie:BAAANQAECgQJCAAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQADCgcJEAAAAA==.Bermy:BAAANQAECgYJDwAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAAANQAECgcIEQAAAA==.Biku:BAAANQAECgIJAQAAAA==.',
Bl='Blackhawkdk:BAAANQAECgYIDQAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBQAAAA==.Blindwarrior:BAAANQAECgIIAgAAAA==.Bloodshadow:BAAANQAECgQIBAAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgUIBQAAAA==.',
Br='Breakcooloz:BAAANQAECgQJBgABNQAECgYIDAABAAAAAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIJAgABAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAAANQAECgUICgAAAA==.Brutak:BAAANQADCggJCAAAAA==.',
Bu='Burstinurass:BAAANQAECgYIDAAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Carbonight:BAABNQAECoEjAAIKAAkKhyRDAQCTAwAKAAkKhyRDAQCTAwAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECgcJEwABAAAAAA==.Cellyne:BAAANQAECgIJAgAAAA==.',
Ch='Chaoswind:BAABNQAECoEZAAILAAcKVh21LQBGAgALAAcKVh21LQBGAgAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwABAAAAAA==.Chelives:BAEANQAECgIIAgAAAA==.Cherpnome:BAAANQAECgIIAgABNQAECgcIEQABAAAAAA==.Chertheif:BAAANQADCgIIAgABNQAECgcIEQABAAAAAA==.Cherubix:BAAANQADCggIDgABNQAECgcIEQABAAAAAA==.Chromus:BAABNQAECoEaAAIMAAkKXBpJCwCuAgAMAAkKXBpJCwCuAgAAAA==.',
Ci='Cires:BAAANQAECgUIBgAAAA==.',
Co='Colanasou:BAAANQADCggIGQAAAA==.Coldbattler:BAAANQAECgQJBwAAAA==.Convictions:BAAANQAECgYICwABNQAFFAYIEAANAG0aAA==.Corrick:BAAANQAECgEIAQAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAIIAgAAAQ==.',
Cy='Cydric:BAAANQAECgQIBQAAAA==.',
Da='Daarrkstar:BAAANQADCggIHQABNQAECgQIBQABAAAAAA==.Dakaryn:BAAANQADCggJDQAAAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCgcJCQAAAA==.Deathrival:BAAANQABCgIIAgAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgUIBQAAAA==.Demonkare:BAAANQADCggIDwABNQAECggIFgAOAMIfAA==.Demoray:BAACNQAFFIERAAMPAAYK2iCRAwDJAQAPAAUKlCCRAwDJAQAQAAEKOyIxFQBwAAA1AAQKgSAAAw8ACQr6JFgDAIsDAA8ACQr6JFgDAIsDABAAAQr5GHTnAEkAAAAA.Demvinity:BAAANQAECgEJAQAAAA==.Dethrone:BAAANQAECgcIDwAAAA==.Deus:BAABNQAECoEgAAMCAAYK7xT9IwCQAQACAAYK7xT9IwCQAQADAAEKNw/oGwA3AAAAAA==.',
Di='Dinosocks:BAACNQAFFIEIAAMQAAUKug0aBQBiAQAQAAQKeg8aBQBiAQAPAAIK6QPhEQCFAAA1AAQKgR0AAxAACQpGFYZMAA0CABAABwrGF4ZMAA0CAA8ACAqNDLkkAKwBAAAA.Dirtydragon:BAAANQAECgUJCgAAAA==.Divinedecay:BAAANQAECgIIAgABNQAECggJEQABAAAAAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Donoraginn:BAAANQADCggIHAAAAA==.Donos:BAAANQADCggIGgABNQADCggIHAABAAAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQADCggIGAAAAA==.Drathiel:BAAANQADCggIDAAAAA==.Drwho:BAAANQAECgIJAwAAAA==.Drëëxx:BAAANQAECgEJAQAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dî']='Dîxon:BAAANQADCggICwABNQAECgYIDAABAAAAAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgEJAQAAAA==.',
Ex='Exhumina:BAAANQADCggJCAAAAA==.',
Fa='Facestealerr:BAAANQAECgEJAQAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAAANQAECgQIBwAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAAANQAECgIJAgAAAA==.Flars:BAAANQAECgcJDwAAAA==.Flatliner:BAABNQAECoEYAAIRAAgKGQelVQCdAQARAAgKGQelVQCdAQAAAA==.Flik:BAAANQAECgUIBQABNQAFFAIJAwABAAAAAA==.',
Fo='Forq:BAAANQADCgcICAAAAA==.',
Fr='Frankzappn:BAAANQAECgUICgAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAAANQAECgYIEAAAAA==.Fruitcakes:BAAANQAECgQICQAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAQAAAA==.Fuddrael:BAAANQAECgUICAAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAAANQAECgIIAgAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQADCgYICAAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAABNQAECoEVAAIRAAgKOhT4OQAQAgARAAgKOhT4OQAQAgAAAA==.',
Gl='Glimagi:BAAANQAECgEJAQAAAA==.',
Gr='Grimjawz:BAABNQAECoEXAAISAAgKvRE9GADwAQASAAgKvRE9GADwAQAAAA==.Grippysocks:BAAANQAFFAIJAgABNQAFFAUJCAAQALoNAA==.',
Gu='Gummibear:BAAANQAECgQICAAAAA==.',
Ha='Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAAANQAECgQJBgAAAA==.Harthoon:BAABNQAECoEhAAMTAAkKTh1ZBABvAgATAAgKLh9ZBABvAgAUAAkKnxBmYwBkAgAAAA==.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Holiebelle:BAAANQAECgIJAgAAAA==.Holyshield:BAAANQADCgEIAQABNQAECgcIEgABAAAAAA==.Honeynoats:BAAANQAECgUJCwAAAA==.Hotdwarf:BAAANQAECgQIBgAAAA==.',
Hr='Hrumm:BAABNQAECoEaAAMPAAkK9hbiEgCFAgAPAAkK9hbiEgCFAgAQAAUKswgvrgABAQAAAA==.',
Hu='Hullkk:BAABNQAECoEdAAINAAkKHyV5BgCpAwANAAkKHyV5BgCpAwAAAA==.Hush:BAAANQAECgMIAgAAAA==.Hutchadina:BAAANQADCgIIAgAAAA==.Hutchkins:BAAANQAECgQIBgAAAA==.Hutchyo:BAAANQABCgQJAwABNQAECgQIBgABAAAAAA==.',
Hy='Hydro:BAAANQADCgcIBwAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icirus:BAABNQAECoEbAAMRAAkKzxMwKABpAgARAAkKzxMwKABpAgAVAAQK0AhE0QDAAAAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQADCggIDAABAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAAANQAECgIIAgAAAA==.Invasion:BAAANQADCggICAAAAA==.',
It='Itzal:BAAANQAECgUIBQAAAA==.',
Ja='Jagere:BAAANQAECgYIDAAAAA==.Jahde:BAAANQAECgMJBAAAAA==.Jaina:BAAANQAECgEJAQAAAA==.Jandrae:BAABNQAECoEcAAMWAAgKoRvCEwB/AgAWAAgKoRvCEwB/AgAXAAIKqgdviwBTAAAAAA==.Jassykins:BAAANQAECgIJAQAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jiffypop:BAAANQADCgMIAwABNQAECgMIAgABAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQADCgQIBAAAAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAAANQAECgQICAAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgMJBAABAAAAAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQAECgIIAgABNQAECgUJDQABAAAAAA==.Kare:BAAANQAECgQICAABNQAECggIFgAOAMIfAA==.Karee:BAABNQAECoEWAAIOAAgKwh9SCAC9AgAOAAgKwh9SCAC9AgAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAAANQAECgYIEAAAAA==.',
Kh='Khold:BAAANQAECgMIBAAAAA==.',
Ko='Koltara:BAABNQAECoEXAAIFAAgKASFvDQDdAgAFAAgKASFvDQDdAgABNQAFFAIIBAABAAAAAA==.Koltarax:BAAANQAECgEIAQABNQAFFAIIBAABAAAAAA==.Koltarian:BAAANQAECgYIBgABNQAFFAIIBAABAAAAAA==.Koltaros:BAAANQAECgQIBAABNQAFFAIIBAABAAAAAA==.Konshis:BAAANQAECgYJEgAAAA==.Kookymonster:BAAANQAECgYIEgAAAA==.Kos:BAABNQAECoEjAAMWAAkKix+kDADfAgAWAAkKKx+kDADfAgAYAAEKFxciigBEAAAAAA==.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCgcJDAAAAA==.',
Ku='Kuragaru:BAABNQAECoEhAAIZAAkKAyDdAwBGAwAZAAkKAyDdAwBGAwAAAA==.',
La='Lapis:BAAANQAECgUICgAAAA==.',
Le='Lester:BAAANQAECgQIBwAAAA==.Levina:BAABNQAECoEbAAMJAAgKSBR/CwDsAQAJAAgKSBR/CwDsAQAIAAcKuwWsSQA8AQAAAA==.Lexysady:BAAANQADCgcJCwAAAA==.',
Li='Lidrahl:BAABNQAECoEXAAIXAAgKhxd/JgAjAgAXAAgKhxd/JgAjAgAAAA==.Liliria:BAABNQAECoEXAAIHAAgKeQbJVwB6AQAHAAgKeQbJVwB6AQAAAA==.Lillidân:BAAANQADCgIIAgABNQAECgkJHwAUAIkcAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAAANQAECgMJBQAAAA==.',
Ln='Lnpoop:BAAANQAECgcIEwAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgUJBgAAAA==.Lorelei:BAAANQAECgIIAgAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAAANQAECgcIDQAAAA==.Lucariõ:BAACNQAFFIEHAAIHAAQKGyEwBwCXAQAHAAQKGyEwBwCXAQA1AAQKgSIAAgcACQp5I8MKADADAAcACQp5I8MKADADAAAA.Lumina:BAAANQAECgIJAgAAAA==.',
Ly='Lyllies:BAABNQAECoEZAAIQAAgK2B0sKQCQAgAQAAgK2B0sKQCQAgAAAA==.Lyv:BAAANQADCgYIBgABNQADCggIDAABAAAAAA==.',
Ma='Mafia:BAAANQADCggIDgAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAAANQAECgUJCwAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgEIAQAAAA==.Matrim:BAAANQADCggJDgAAAA==.Mattdæmon:BAAANQAECgUICgAAAA==.',
Me='Meekogaia:BAABNQAECoEkAAMLAAgKAhEZRQDXAQALAAgKAhEZRQDXAQAaAAYKNA4XaQBZAQAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Millerowntoo:BAAANQAFFAMIAwAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.',
Mj='Mjoln:BAAANQADCggICAAAAA==.',
Mo='Mobius:BAAANQADCggIFQABNQAECgIIAgABAAAAAA==.Molvnma:BAAANQAECggIAQAAAA==.Monkeycoke:BAAANQAECgIIAgAAAA==.Montkriege:BAAANQADCgcIEAAAAA==.',
Mu='Murfie:BAAANQAECgYJDwAAAA==.Murica:BAAANQADCgYICgABNQAECgcIEQABAAAAAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
Na='Nashira:BAAANQAECgYIEQAAAA==.Nashness:BAABNQAECoEbAAIYAAgKrB/iEQDnAgAYAAgKrB/iEQDnAgAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgUICgABAAAAAA==.Nesquík:BAAANQADCgUJCQAAAA==.',
Ni='Niis:BAAANQAECgUICAAAAA==.Niterage:BAAANQAECgUJCAAAAA==.',
Nn='Nn:BAAANQAECgIJAgAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAAANQAECgIIAwAAAA==.',
['Nì']='Nìr:BAAANQAECgcIBwAAAA==.',
Od='Odinrex:BAAANQAECggJBQAAAA==.',
Op='Opuntia:BAAANQAECgEJAQAAAA==.',
Ow='Ownham:BAAANQAECgQIBAABNQAFFAMIAwABAAAAAA==.',
Pa='Paddingidiot:BAAANQAFFAIIBAAAAA==.Paladinheal:BAAANQADCgYICQAAAA==.Pallypaladin:BAABNQAECoEfAAIVAAkKLCD6HQD3AgAVAAkKLCD6HQD3AgAAAA==.Partywolf:BAAANQADCggIGAAAAA==.',
Ph='Phatzero:BAAANQAECggJEQAAAA==.',
Pi='Pinjo:BAAANQAECgUJBQAAAA==.',
Po='Polard:BAAANQAECgUICgAAAA==.',
Pr='Procreeper:BAAANQADCgcIBwABNQAECgkJIwAKAIckAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAAANQADCgcJEgABNQAECgYICwABAAAAAA==.',
Ra='Rabit:BAAANQADCgQIBAAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rainyblu:BAAANQADCgQICAAAAA==.Rawrshåk:BAAANQAECgYIEQAAAA==.',
Rc='Rc:BAAANQAECgUJDAAAAA==.',
Rh='Rhodraco:BAAANQAECgIJAgAAAA==.Rhownyn:BAAANQABCgQIBQAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAAANQAECgQICgABNQADCggIHAABAAAAAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Rq='Rq:BAAANQADCgYIBgAAAA==.',
Ry='Ryyukken:BAAANQAECgEIAQAAAA==.',
['Rà']='Ràwrshåk:BAAANQADCgQJBAAAAA==.',
Sa='Saella:BAAANQADCgYIDgAAAA==.Saluda:BAAANQABCgIIAgAAAA==.Samesde:BAAANQAECgMJAQAAAA==.Saphyria:BAAANQABCgIIAgAAAA==.Sarentu:BAAANQAFFAEJAQAAAA==.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQADCgUIBQAAAA==.Senile:BAAANQAECgIJAgAAAA==.Sertia:BAAANQADCgEIAQAAAA==.',
Sh='Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgUIBQABNQAECggIFwAIAJAUAA==.Shadyvoid:BAAANQAECgIIAgABNQAECggIFwAIAJAUAA==.Shadówglider:BAAANQAECgEJAQAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAAANQAECgYJDwAAAA==.Shamallaman:BAAANQAECgUJCAABNQAECgcJBwABAAAAAA==.Sharkweek:BAAANQAECgMIAwAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shydestroyer:BAAANQADCgMIAwAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.Sinfulness:BAAANQAECgEIAQAAAA==.',
Sk='Skikette:BAAANQAECgUJCwAAAA==.Skinrot:BAAANQAECgYIEQAAAA==.',
Sm='Smig:BAAANQAECgIIAgAAAA==.',
Sn='Snowball:BAAANQAECgIIAgAAAA==.',
So='Soeki:BAAANQAECgIJAgAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAAANQAECgQICgABNQAECgUICQABAAAAAA==.Soullovez:BAAANQAECgUICQAAAA==.Soulshocks:BAAANQAECgUJCAABNQAECgUICQABAAAAAA==.Soulviver:BAAANQAECgYIEAAAAA==.',
Sp='Spiritwarden:BAAANQAECgQJBgAAAA==.Splootz:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.',
Sq='Squirtdadday:BAAANQAECgIJAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECoEcAAQNAAgKFSSxKQDHAgANAAcKXCOxKQDHAgAbAAYKyCD7BgAJAgAcAAEKQiL6JABmAAAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Suxor:BAAANQAECgMIBQAAAA==.',
Sw='Swordboardal:BAABNQAECoEiAAIcAAkKDRPqCAA2AgAcAAkKDRPqCAA2AgAAAA==.',
Sy='Sybius:BAAANQAECgQJCAAAAA==.Symptom:BAAANQAECgEJAQAAAA==.Syncophat:BAAANQAECgQJBgAAAA==.',
Ta='Tad:BAAANQADCgcICwAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQAECgEJAQAAAA==.Talanzen:BAAANQAECgYIDQAAAA==.',
Te='Teacup:BAAANQAECgEJAgABNQAECgYJDgABAAAAAA==.',
Th='Thrakara:BAABNQAECoEkAAIdAAkKIhlOCQCfAgAdAAkKIhlOCQCfAgAAAA==.Thrakaru:BAAANQAECgYICwAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgIIAQAAAA==.Thundrall:BAAANQAECgEJAQAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAAANQAECggIDwAAAA==.',
To='Torches:BAAANQADCgcIBwAAAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFIEQAAINAAYKbRq7AgA2AgANAAYKbRq7AgA2AgA1AAQKgRkAAg0ACQoyI6QVADcDAA0ACQoyI6QVADcDAAAA.Trystrom:BAAANQADCgYIBgAAAA==.',
Ts='Tsuo:BAAANQAECgYIBgAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txblood:BAAANQADCgcJCAAAAA==.Txgunny:BAAANQAECgIIAgAAAA==.Txstormin:BAAANQADCgMJAwAAAA==.',
Ty='Tymptriss:BAAANQAECgIJAwAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbren:BAAANQAECgQIBgAAAA==.',
Ur='Urabadkity:BAAANQADCgIJAgAAAA==.',
Va='Valartha:BAAANQAECgEJAQAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velsea:BAAANQADCgYICQAAAA==.Velstadt:BAAANQAECgQICAAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAAANQAECgcIDQAAAA==.Vermilion:BAAANQAECgEIAQAAAA==.',
Vh='Vholatile:BAAANQAECgUIBgAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgQJBgAAAQ==.',
Vo='Voidherron:BAAANQAECgIJAgAAAA==.Voodoomama:BAAANQADCgYICwAAAA==.',
Wa='Warlockbot:BAACNQAFFIEFAAIeAAMK7An2DgDlAAAeAAMK7An2DgDlAAA1AAQKgRwAAh4ACQopG4wZAM8CAB4ACQopG4wZAM8CAAAA.Warmongral:BAAANQADCgMIBQAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAAANQAECgMJBQAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEAABNQAECggIDwABAAAAAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggJCAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIAwAAAA==.Woolala:BAABNQAECoEXAAIQAAgKyhQrPABFAgAQAAgKyhQrPABFAgAAAA==.',
Wr='Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQADCgYICgABNQAECgcIDQABAAAAAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMJAwAAAA==.',
Ya='Yazmyn:BAAANQAECgUICAAAAA==.',
Ye='Yerehmi:BAAANQADCgYICQAAAA==.',
Yu='Yuny:BAAANQAECgQJBwAAAA==.',
Za='Zaier:BAABNQAECoEZAAIRAAgKVhSbNAApAgARAAgKVhSbNAApAgAAAA==.',
Ze='Zeltan:BAABNQAECoEgAAIRAAcKtRuZMgAyAgARAAcKtRuZMgAyAgAAAA==.',
Zh='Zhundrenga:BAAANQAECgEJAQAAAA==.',
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
