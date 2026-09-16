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

local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Discipline','Priest-Holy','Druid-Feral','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Mage-Frost','Mage-Arcane','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Warrior-Protection','Monk-Mistweaver','Warlock-Demonology',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acks:BAAANQADCgYICgABNQAFFAEIAQABAAAAAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAAANQAECgQIBgAAAA==.Aex:BAAANQAECgcIEgABNQAFFAEIAQABAAAAAA==.',
Ah='Ahnkhano:BAAANQADCgcIDQAAAA==.',
Ai='Ainge:BAAANQADCgYIDAAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFIEKAAMCAAUJpxRZAgB9AQACAAQJVBlZAgB9AQADAAEJFgLzAQBKAAA1AAQKgSMAAwIACQkeJSABAMkDAAIACQkeJSABAMkDAAMAAgkMFwURAIgAAAAA.',
Al='Allistrana:BAAANQAECgIIAwAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Amairis:BAAANQAECgEIAQAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAAANQAECgYIEgAAAA==.',
At='Ataliya:BAAANQAECgEIAQAAAA==.',
Au='Auranar:BAAANQADCggIGQAAAA==.Aurelya:BAAANQAECgMIAwAAAA==.Aurilia:BAAANQADCggIFwAAAA==.',
Av='Avanicus:BAAANQAECgIIAwAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBAAAAA==.Avé:BAAANQAECgQIBAAAAA==.',
Ax='Axellent:BAAANQAFFAEIAQAAAA==.Axiomlegacy:BAAANQAECgYIDQAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgIIAgAAAA==.',
Ba='Banderblitz:BAAANQAECgQICAAAAA==.Bar:BAABNQAECoEaAAMCAAkJyxN3EgA8AgACAAgJdRJ3EgA8AgAEAAgJTQt+PACeAQAAAA==.',
Be='Bearlyshady:BAAANQAECgcIEwAAAA==.Bellarina:BAAANQADCggIGQAAAA==.Bellatrixie:BAAANQAECgMIBAAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQADCgYIDwAAAA==.Bermy:BAAANQAECgYICQAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAAANQAECgYIEAAAAA==.Biku:BAAANQAECgIIAQAAAA==.',
Bl='Blackhawkdk:BAAANQAECgYIDQAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBQAAAA==.Blindwarrior:BAAANQADCggICAAAAA==.Bloodshadow:BAAANQADCggIGQAAAA==.',
Bo='Bovinity:BAAANQABCgUIBQAAAA==.',
Br='Breakcooloz:BAAANQAECgQIBgABNQAECgYIDAABAAAAAA==.Bretcoe:BAAANQADCgYIDAAAAA==.Brooce:BAAANQAECgMIBQAAAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Burstinurass:BAAANQAECgYIDAAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Carbonight:BAABNQAECoEhAAIFAAkJfiTTAACgAwAFAAkJfiTTAACgAwAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECgYIEQABAAAAAA==.Cellyne:BAAANQAECgIIAQAAAA==.',
Ch='Chaoswind:BAAANQAECgYIDwAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwABAAAAAA==.Chelives:BAEANQADCggIHQAAAA==.Cherpnome:BAAANQAECgIIAgAAAA==.Cherubix:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Chromus:BAAANQAFFAIIAgAAAA==.',
Ci='Cires:BAAANQAECgEIAQAAAA==.',
Co='Colanasou:BAAANQADCggIEQAAAA==.Coldbattler:BAAANQAECgMIAwAAAA==.Convictions:BAAANQAECgYICwABNQAFFAYICwAGAI4XAA==.Corrick:BAAANQADCgYICgAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAECggIEwAAAQ==.',
Cy='Cydric:BAAANQAECgMIAwAAAA==.',
Da='Daarrkstar:BAAANQADCggIHQABNQAECgQIBQABAAAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCgIIAgAAAA==.Deathrival:BAAANQABCgIIAgAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Demonkare:BAAANQADCggIDwABNQAECgcIEwABAAAAAA==.Demoray:BAACNQAFFIEMAAMHAAYJaBwyAgDEAQAHAAUJYBwyAgDEAQAIAAEJkByhDABsAAA1AAQKgR0AAwcACQnSJCACAKADAAcACQnSJCACAKADAAgAAQn5GPO8AE4AAAAA.Demvinity:BAAANQADCggIDwAAAA==.Dethrone:BAAANQAECgcICwAAAA==.Deus:BAABNQAECoEaAAMCAAUJhhUcIgBeAQACAAUJhhUcIgBeAQADAAEJNw/nGAA3AAAAAA==.',
Di='Dinosocks:BAAANQAFFAMIAwAAAA==.Dirtydragon:BAAANQAECgQIBQAAAA==.Divinedecay:BAAANQADCggIFQABNQAECgUICwABAAAAAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Donoraginn:BAAANQADCggIEwAAAA==.Donos:BAAANQADCggIEwABNQADCggIEwABAAAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQADCggIEQAAAA==.Drathiel:BAAANQADCggIDAAAAA==.Drwho:BAAANQAECgIIAgAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dî']='Dîxon:BAAANQADCggICwABNQAECgYIDAABAAAAAA==.',
Fa='Facestealerr:BAAANQADCggIFwAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAAANQAECgEIAQAAAA==.',
Fl='Flairrick:BAAANQAECgIIAQAAAA==.Flars:BAAANQAECgQIBwAAAA==.Flatliner:BAABNQAECoEYAAIJAAgJGQcQQgCpAQAJAAgJGQcQQgCpAQAAAA==.',
Fo='Forq:BAAANQADCgcICAAAAA==.',
Fr='Frankzappn:BAAANQAECgUICgAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAAANQAECgUICgAAAA==.Fruitcakes:BAAANQAECgQIBQAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAQAAAA==.Fuddrael:BAAANQAECgIIAwAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAAANQADCggIHQAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQADCgYICAAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAAANQAECgcIEgAAAA==.',
Gl='Glimagi:BAAANQADCggIDwAAAA==.',
Gr='Grimjawz:BAAANQAECgcIEwAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAMIAwABAAAAAA==.',
Gu='Gummibear:BAAANQAECgQIBAAAAA==.',
Ha='Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAAANQAECgQIBAAAAA==.Harthoon:BAABNQAECoEdAAMKAAkJTh20AgCKAgAKAAgJLh+0AgCKAgALAAkJQA9zUQBXAgAAAA==.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Holiebelle:BAAANQAECgIIAQAAAA==.Holyshield:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Honeynoats:BAAANQAECgQIBgAAAA==.Hotdwarf:BAAANQAECgIIAgAAAA==.',
Hr='Hrumm:BAAANQAFFAIIAgAAAA==.',
Hu='Hullkk:BAABNQAECoEYAAIGAAkJHCQDBwCbAwAGAAkJHCQDBwCbAwAAAA==.Hush:BAAANQAECgMIAgAAAA==.Hutchadina:BAAANQADCgIIAgAAAA==.Hutchkins:BAAANQAECgMIAgAAAA==.Hutchyo:BAAANQABCgQIAwABNQAECgMIAgABAAAAAA==.',
Hy='Hydro:BAAANQADCgcIBwAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icirus:BAAANQAECgUIDgAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQADCggIDAABAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAAANQADCggIFgAAAA==.',
Ja='Jagere:BAAANQAECgYIBgAAAA==.Jahde:BAAANQAECgEIAQAAAA==.Jaina:BAAANQADCgYIDAAAAA==.Jandrae:BAAANQAECgcIEgAAAA==.',
Je='Jessecuster:BAAANQADCgMIAwAAAA==.',
Ji='Jiffypop:BAAANQADCgMIAwABNQAECgMIAgABAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQADCgQIBAAAAA==.',
Jo='Joanofarc:BAAANQADCgUIBQAAAA==.Joloc:BAAANQAECgMIBAAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQADCggIGQABNQAECgQICAABAAAAAA==.Kare:BAAANQAECgQICAABNQAECgcIEwABAAAAAA==.Karee:BAAANQAECgcIEwAAAA==.',
Ke='Kermodk:BAAANQAECgUICgAAAA==.',
Kh='Khold:BAAANQAECgMIBAAAAA==.',
Ko='Koltara:BAABNQAECoEXAAIMAAgJASG1CgDyAgAMAAgJASG1CgDyAgABNQAFFAIIAgABAAAAAA==.Koltarax:BAAANQAECgEIAQABNQAFFAIIAgABAAAAAA==.Koltaros:BAAANQAECgQIBAABNQAFFAIIAgABAAAAAA==.Konshis:BAAANQAECgUIDAAAAA==.Kookymonster:BAAANQAECgYIDAAAAA==.Kos:BAABNQAECoEfAAMNAAkJGx8XBwD/AgANAAkJux4XBwD/AgAOAAEJFxfkeABGAAAAAA==.',
Kr='Krathos:BAAANQADCgYIBgAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCgYIBwAAAA==.',
Ku='Kuragaru:BAABNQAECoEdAAIPAAkJ5R2XAwA+AwAPAAkJ5R2XAwA+AwAAAA==.',
La='Lapis:BAAANQAECgMIBQAAAA==.',
Le='Lester:BAAANQAECgMIBAAAAA==.Levina:BAAANQAECgYIEQAAAA==.Lexysady:BAAANQADCgIIBAAAAA==.',
Li='Lidrahl:BAAANQAECgcIEQAAAA==.Liliria:BAAANQAECgcIEwAAAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAAANQAECgIIAgAAAA==.',
Ln='Lnpoop:BAAANQAECgYIDAAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBAAAAA==.Lorelei:BAAANQADCggIDgAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAAANQAECgYIDAAAAA==.Lucariõ:BAABNQAECoEfAAIEAAkJOSMdCAAnAwAEAAkJOSMdCAAnAwAAAA==.Lumina:BAAANQAECgIIAQAAAA==.',
Ly='Lyllies:BAAANQAECgcIEwAAAA==.Lyv:BAAANQADCgYIBgABNQADCggIDAABAAAAAA==.',
Ma='Mafia:BAAANQADCgYIBgAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAAANQAECgQIBgAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgEIAQAAAA==.Matrim:BAAANQADCgYICwAAAA==.Mattdæmon:BAAANQAECgQIBQAAAA==.',
Me='Meekogaia:BAABNQAECoEaAAMQAAcJgg1eTAB3AQAQAAcJgg1eTAB3AQARAAUJ6wq2agANAQAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Millerowntoo:BAAANQAECgYIBwAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCgEIAQAAAA==.',
Mj='Mjoln:BAAANQADCggICAAAAA==.',
Mo='Mobius:BAAANQADCggIFQAAAA==.Molvnma:BAAANQAECggIAQAAAA==.Monkeycoke:BAAANQADCggICAABNQADCggIFQABAAAAAA==.Montkriege:BAAANQADCgcIEAAAAA==.',
Mu='Murfie:BAAANQAECgYICQAAAA==.Murica:BAAANQADCgYICgABNQAECgYIEAABAAAAAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
Na='Nashira:BAAANQAECgYICwAAAA==.Nashness:BAAANQAECgcIEAAAAA==.',
Ne='Nerdvader:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Nesquík:BAAANQADCgUIBwAAAA==.',
Ni='Niis:BAAANQAECgUICAAAAA==.Niterage:BAAANQAECgMIAwAAAA==.',
Nn='Nn:BAAANQAECgIIAQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgEIAQAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAAANQAECgIIAwAAAA==.',
['Nì']='Nìr:BAAANQAECgUIBQAAAA==.',
Od='Odinrex:BAAANQAECggIAgAAAA==.',
Op='Opuntia:BAAANQADCggIFwAAAA==.',
Ow='Ownham:BAAANQAECgQIBAABNQAECgYIBwABAAAAAA==.',
Pa='Paddingidiot:BAAANQAFFAIIAgAAAA==.Paladinheal:BAAANQADCgYICQAAAA==.Pallypaladin:BAABNQAECoEbAAISAAkJch6tFQDzAgASAAkJch6tFQDzAgAAAA==.Partywolf:BAAANQADCggIGAAAAA==.',
Ph='Phatzero:BAAANQAECgUICwAAAA==.',
Po='Polard:BAAANQAECgQIBQAAAA==.',
Pr='Procreeper:BAAANQADCgcIBwABNQAECgkJIQAFAH4kAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAAANQADCgcIDQABNQAECgQIBQABAAAAAA==.',
Ra='Rabit:BAAANQADCgEIAQAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rainyblu:BAAANQADCgQICAAAAA==.Rawrshåk:BAAANQAECgUICwAAAA==.',
Rc='Rc:BAAANQAECgQIBwAAAA==.',
Rh='Rhodraco:BAAANQAECgIIAQAAAA==.Rhownyn:BAAANQABCgQIBQAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAAANQAECgMIBgABNQADCggIGQABAAAAAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Rq='Rq:BAAANQADCgYIBgAAAA==.',
Ry='Ryyukken:BAAANQADCgYIEgAAAA==.',
Sa='Saella:BAAANQADCgYIDgAAAA==.Saluda:BAAANQABCgIIAgAAAA==.Saphyria:BAAANQABCgIIAgAAAA==.Sarentu:BAAANQAECgcIEgAAAA==.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQADCgIIAgAAAA==.Senile:BAAANQAECgIIAQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.',
Sh='Shadesoflife:BAAANQABCgIIAgAAAA==.Shadydice:BAAANQADCgUIBQABNQAECgcIEwABAAAAAA==.Shadyvoid:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.Shadówglider:BAAANQADCggIEQAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAAANQAECgYICQAAAA==.Shamallaman:BAAANQAECgYICAAAAA==.Sharkweek:BAAANQAECgMIAwAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggIGgAAAA==.Shydestroyer:BAAANQADCgMIAwAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.Sinfulness:BAAANQADCgEIAQAAAA==.',
Sk='Skikette:BAAANQAECgQIBgAAAA==.Skinrot:BAAANQAECgYICwAAAA==.',
Sm='Smig:BAAANQADCgYIDQAAAA==.',
Sn='Snowball:BAAANQADCggIEwAAAA==.',
So='Soeki:BAAANQAECgIIAQAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAAANQAECgQIBgAAAA==.Soullovez:BAAANQAECgMIBAABNQAECgQIBgABAAAAAA==.Soulshocks:BAAANQAECgIIAwABNQAECgQIBgABAAAAAA==.Soulviver:BAAANQAECgUICgAAAA==.',
Sp='Spiritwarden:BAAANQAECgIIAwAAAA==.Splootz:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.',
Sq='Squirtdadday:BAAANQADCgIIAgABNQADCgYIDAABAAAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAAANQAECgcIEgAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Suxor:BAAANQAECgMIAwAAAA==.',
Sw='Swordboardal:BAABNQAECoEaAAITAAgJlg5zCgDIAQATAAgJlg5zCgDIAQAAAA==.',
Sy='Sybius:BAAANQAECgMIBAAAAA==.Symptom:BAAANQAECgEIAQAAAA==.Syncophat:BAAANQAECgIIAgAAAA==.',
Ta='Tad:BAAANQADCgcICwAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQADCggIDwAAAA==.Talanzen:BAAANQAECgQIBwAAAA==.',
Te='Teacup:BAAANQAECgEIAgAAAA==.',
Th='Thrakara:BAABNQAECoEgAAIUAAkJiBhvBwCfAgAUAAkJiBhvBwCfAgAAAA==.Thrakaru:BAAANQAECgUIBQAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgIIAQAAAA==.Thundrall:BAAANQAECgEIAQAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAAANQAECgcICQAAAA==.',
To='Torches:BAAANQADCgcIBwAAAA==.',
Tr='Triad:BAAANQADCgYIBgAAAA==.Truths:BAACNQAFFIELAAIGAAYJjhemAQA7AgAGAAYJjhemAQA7AgA1AAQKgRcAAgYACQkyI+UMAGIDAAYACQkyI+UMAGIDAAAA.Trystrom:BAAANQADCgYIBgAAAA==.',
Ts='Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txbloodstorm:BAAANQADCgcICAAAAA==.Txgunny:BAAANQADCggIEAAAAA==.',
Ty='Tymptriss:BAAANQADCggIFwAAAA==.',
Um='Umbren:BAAANQAECgIIAgAAAA==.',
Va='Valartha:BAAANQADCggIFwAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgMIBAAAAA==.Velsea:BAAANQADCgYICQAAAA==.Velstadt:BAAANQAECgMIBAAAAA==.Venhance:BAAANQAECgUICQAAAA==.Venotu:BAAANQAECgQIBgAAAA==.Vermilion:BAAANQAECgEIAQAAAA==.',
Vh='Vholatile:BAAANQAECgUIBgAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgIIAgAAAQ==.',
Vo='Voidherron:BAAANQAECgIIAQAAAA==.Voodoomama:BAAANQADCgYIBgAAAA==.',
Wa='Warlockbot:BAABNQAECoEbAAIVAAkJKRveDQDyAgAVAAkJKRveDQDyAgAAAA==.Warmongral:BAAANQADCgMIBQAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAAANQAECgIIAgAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCgcICgABNQAECgcICQABAAAAAA==.Wildbill:BAAANQADCgYIBwAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIAwAAAA==.Woolala:BAAANQAECgcIEwAAAA==.',
Wu='Wut:BAAANQADCgYICgABNQAECgYIDAABAAAAAA==.',
Xa='Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQADCggIFAAAAA==.',
Ya='Yazmyn:BAAANQAECgMIBAAAAA==.',
Ye='Yerehmi:BAAANQADCgYICQAAAA==.',
Yu='Yuny:BAAANQAECgMIAwAAAA==.',
Za='Zaier:BAAANQAECgcIEwAAAA==.',
Ze='Zeltan:BAABNQAECoEaAAIJAAcJzhrGKQApAgAJAAcJzhrGKQApAgAAAA==.',
Zh='Zhundrenga:BAAANQADCggIFwAAAA==.',
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
