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

local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Discipline','Druid-Feral','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Devourer','Monk-Mistweaver',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acks:BAAANQADCgYICgABNQAECgcIEQABAAAAAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAAANQAECgQIBAAAAA==.Aex:BAAANQAECgcIEQAAAA==.',
Ah='Ahnkhano:BAAANQADCgcIDQAAAA==.',
Ai='Ainge:BAAANQADCgYIDAAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAABNQAECoEeAAMCAAkJDyQ2AQC1AwACAAkJDyQ2AQC1AwADAAIJDBf/DQCLAAAAAA==.',
Al='Allistrana:BAAANQAECgEIAQAAAA==.Allpower:BAAANQADCgUICAAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQADCggIEgABAAAAAA==.Amairis:BAAANQADCgcIEgAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAAANQAECgUICwAAAA==.',
At='Ataliya:BAAANQADCgcIBwAAAA==.',
Au='Auranar:BAAANQADCggIEQAAAA==.Aurelya:BAAANQADCgYICAAAAA==.Aurilia:BAAANQADCgcIDwAAAA==.',
Av='Avanicus:BAAANQAECgEIAQAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQADCggIDwAAAA==.',
Ax='Axellent:BAAANQAECgMIAwABNQAECgcIEQABAAAAAA==.Axiomlegacy:BAAANQAECgQIBwAAAA==.',
Az='Azulien:BAAANQADCgcIEwAAAA==.',
Ba='Banderblitz:BAAANQAECgIIBAAAAA==.Bar:BAAANQAECgcIEAAAAA==.',
Be='Bearlyshady:BAAANQAECgcIDAAAAA==.Bellarina:BAAANQADCgYIEQAAAA==.Bellatrixie:BAAANQAECgEIAQAAAA==.Beriadhwen:BAAANQADCgYIDwAAAA==.Bermy:BAAANQAECgQIBQAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAAANQAECgUICgAAAA==.Biku:BAAANQAECgEIAQAAAA==.',
Bl='Blackhawkdk:BAAANQAECgQIBwAAAA==.Blende:BAAANQAECgEIAQAAAA==.Bloodshadow:BAAANQADCggIEQAAAA==.',
Br='Breakcooloz:BAAANQAECgQIBgABNQAECgYIDAABAAAAAA==.Bretcoe:BAAANQADCgYIBgAAAA==.Brooce:BAAANQAECgIIAgAAAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Burstinurass:BAAANQAECgYIDAAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Carbonight:BAABNQAECoEYAAIEAAkJyyKrAACAAwAEAAkJyyKrAACAAwAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Cellyne:BAAANQAECgEIAQAAAA==.',
Ch='Chaoswind:BAAANQAECgQICQAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwABAAAAAA==.Chelives:BAEANQADCggIFQAAAA==.Cherpnome:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.Cherubix:BAAANQADCgUIBwABNQAECgQIBAABAAAAAA==.Chromus:BAAANQAECgcIDAAAAA==.',
Ci='Cires:BAAANQAECgEIAQAAAA==.',
Co='Colanasou:BAAANQADCgcIDQAAAA==.Coldbattler:BAAANQADCgYICAAAAA==.Convictions:BAAANQAECgYICwABNQAFFAQIBAABAAAAAA==.Corrick:BAAANQADCgYICgAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAECgcIBwAAAQ==.',
Cy='Cydric:BAAANQADCgcIBwAAAA==.',
Da='Daarrkstar:BAAANQADCggIFQABNQAECgEIAQABAAAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathrival:BAAANQABCgIIAgAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Demonkare:BAAANQADCggICwABNQAECgcIDAABAAAAAA==.Demoray:BAACNQAFFIEGAAIFAAUJERWwAQCtAQAFAAUJERWwAQCtAQA1AAQKgRoAAwUACQnOI9IBAKADAAUACQnOI9IBAKADAAYAAQn5GNWKAE8AAAAA.Demvinity:BAAANQADCgcIBwAAAA==.Dethrone:BAAANQAECgQIBAAAAA==.Deus:BAAANQAECgQIEAAAAA==.',
Di='Dinosocks:BAAANQAECgYIBgABNQAFFAEIAQABAAAAAA==.Dirtydragon:BAAANQAECgEIAQAAAA==.Divinedecay:BAAANQADCggIDwABNQAECgQIBgABAAAAAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgQIBwAAAA==.',
Do='Donoraginn:BAAANQADCggICwABNQADCggIDgABAAAAAA==.Donos:BAAANQADCggIDgAAAA==.Dotgenerate:BAAANQAECgEIAQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQADCggIEAAAAA==.Drathiel:BAAANQADCggIDAAAAA==.Drwho:BAAANQADCgcIEwAAAA==.Drëëxx:BAAANQADCgYIEAAAAA==.',
['Dî']='Dîxon:BAAANQADCggICwABNQAECgYIDAABAAAAAA==.',
Fa='Facestealerr:BAAANQADCgcIDwAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.',
Fl='Flairrick:BAAANQAECgEIAQAAAA==.Flars:BAAANQAECgEIAQAAAA==.Flatliner:BAAANQAECgcIDgAAAA==.',
Fo='Forq:BAAANQADCgEIAgAAAA==.',
Fr='Frankzappn:BAAANQAECgQIBQAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAAANQAECgQIBQAAAA==.Fruitcakes:BAAANQAECgEIAQAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAQAAAA==.Fuddrael:BAAANQAECgIIAwAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAAANQADCggIFQAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQADCgYICAAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAAANQAECgYICwAAAA==.',
Gl='Glimagi:BAAANQADCgcIBwAAAA==.',
Gr='Grimjawz:BAAANQAECgcIDAAAAA==.Grippysocks:BAAANQAFFAEIAQAAAA==.',
Gu='Gummibear:BAAANQAECgQIBAAAAA==.',
Ha='Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAAANQAECgEIAQAAAA==.Harthoon:BAAANQAECgcIEQAAAA==.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Holiebelle:BAAANQAECgEIAQAAAA==.Holyshield:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.Honeynoats:BAAANQAECgIIAgAAAA==.Hotdwarf:BAAANQADCgYICwAAAA==.',
Hr='Hrumm:BAAANQAECgcICwAAAA==.',
Hu='Hullkk:BAAANQAECgcIDQAAAA==.Hutchadina:BAAANQADCgIIAgAAAA==.Hutchkins:BAAANQAECgEIAQAAAA==.',
Hy='Hydro:BAAANQADCgcIBwAAAA==.',
Ic='Icirus:BAAANQAECgUICQAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQADCggIDAABAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAAANQADCgcIDgAAAA==.',
Ja='Jagere:BAAANQAECgYIBgAAAA==.Jahde:BAAANQADCgcIEAAAAA==.Jaina:BAAANQADCgYIBgAAAA==.Jandrae:BAAANQAECgYICwAAAA==.Jassykins:BAAANQADCggICwAAAA==.',
Je='Jessecuster:BAAANQADCgMIAwAAAA==.',
Ji='Jiffypop:BAAANQADCgMIAwAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQADCgQIBAAAAA==.',
Jo='Joloc:BAAANQAECgMIAwAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQADCgcIEAABAAAAAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQADCgcIEQABNQAECgIIBAABAAAAAA==.Kare:BAAANQAECgMIAwABNQAECgcIDAABAAAAAA==.Karee:BAAANQAECgcIDAAAAA==.',
Ke='Kermodk:BAAANQAECgQIBQAAAA==.',
Kh='Khold:BAAANQAECgEIAQAAAA==.',
Ko='Koltara:BAABNQAECoEXAAIHAAgJASFdBwAPAwAHAAgJASFdBwAPAwAAAA==.Koltaros:BAAANQADCgcIBwABNQAECggIFwAHAAEhAA==.Konshis:BAAANQAECgQIBwAAAA==.Kookymonster:BAAANQAECgQIBgAAAA==.Kos:BAAANQAECgcIEwAAAA==.',
Kr='Krathos:BAAANQADCgYIBgAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCgUIBQAAAA==.',
Ku='Kuragaru:BAAANQAECgcIEQAAAA==.',
La='Lapis:BAAANQAECgIIAgAAAA==.',
Le='Lester:BAAANQAECgMIAwAAAA==.Levina:BAAANQAECgYIBwAAAA==.Lexysady:BAAANQADCgIIAgAAAA==.',
Li='Lidrahl:BAAANQAECgcICgAAAA==.Liliria:BAAANQAECgcIDAAAAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAAANQADCggIDwAAAA==.',
Ln='Lnpoop:BAAANQAECgUIBgAAAA==.',
Lo='Lockjauz:BAAANQADCgQIBAAAAA==.Lorelei:BAAANQADCgcIDQAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAAANQAECgUICgAAAA==.Lucariõ:BAAANQAECggIEwAAAA==.Lumina:BAAANQAECgEIAQAAAA==.',
Ly='Lyllies:BAAANQAECgcIDAAAAA==.Lyv:BAAANQADCgYIBgABNQADCggIDAABAAAAAA==.',
Ma='Mafia:BAAANQADCgYIBgAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAAANQAECgIIAgAAAA==.Matcauthon:BAAANQADCgcIDQAAAA==.Matrim:BAAANQADCgUIBQAAAA==.Mattdæmon:BAAANQAECgEIAQAAAA==.',
Me='Meekogaia:BAAANQAECgUIDwAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Millerowntoo:BAAANQAECgQIAgABNQAECgQIBAABAAAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCgEIAQAAAA==.',
Mj='Mjoln:BAAANQADCggICAAAAA==.',
Mo='Mobius:BAAANQADCggIFQAAAA==.Montkriege:BAAANQADCgcIDgAAAA==.',
Mu='Murfie:BAAANQAECgQIBQAAAA==.Murica:BAAANQADCgYICgABNQAECgUICgABAAAAAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
Na='Nashira:BAAANQAECgUIBQAAAA==.Nashness:BAAANQAECgQICQAAAA==.',
Ne='Nerdvader:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Nesquík:BAAANQADCgIIAgAAAA==.Nezar:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Ni='Niis:BAAANQAECgIIAwAAAA==.Niterage:BAAANQADCgUIBgAAAA==.',
Nn='Nn:BAAANQAECgEIAQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAAANQAECgIIAwAAAA==.',
Op='Opuntia:BAAANQADCgcIDwAAAA==.',
Ow='Ownham:BAAANQAECgQIBAAAAA==.',
Pa='Paddingidiot:BAAANQADCgUIBQABNQAECggIFwAHAAEhAA==.Paladinheal:BAAANQADCgYICQAAAA==.Pallypaladin:BAAANQAECgcIEQAAAA==.Partywolf:BAAANQADCgYIEAAAAA==.',
Ph='Phatzero:BAAANQAECgQIBgAAAA==.',
Po='Polard:BAAANQAECgIIAgAAAA==.',
Pr='Procreeper:BAAANQADCgcIBwABNQAECgkJGAAEAMsiAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ra='Rabit:BAAANQADCgEIAQAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rainyblu:BAAANQADCgQIBAAAAA==.Rawrshåk:BAAANQAECgQIBgAAAA==.',
Rc='Rc:BAAANQAECgMIAwAAAA==.',
Rh='Rhodraco:BAAANQAECgEIAQAAAA==.Rhownyn:BAAANQABCgQIBQAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAAANQAECgMIAwABNQADCggIEQABAAAAAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Ry='Ryyukken:BAAANQADCgYIEgAAAA==.',
Sa='Saella:BAAANQADCgYIDgAAAA==.Saluda:BAAANQABCgIIAgAAAA==.Samesde:BAAANQADCgIIAgAAAA==.Sarentu:BAAANQAECgYICwAAAA==.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQADCgIIAgAAAA==.Senile:BAAANQAECgEIAQAAAA==.',
Sh='Shadydice:BAAANQADCgUIBQABNQAECgcIDAABAAAAAA==.Shadyvoid:BAAANQADCgYICwABNQAECgcIDAABAAAAAA==.Shadówglider:BAAANQADCgcIDwAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAAANQAECgQIBQAAAA==.Shamallaman:BAAANQAECgMIBQAAAA==.Sharkweek:BAAANQADCggIEwAAAA==.Sheol:BAAANQADCggIDgAAAA==.Sheyoni:BAAANQADCgcIEwAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.',
Sk='Skikette:BAAANQAECgIIAgAAAA==.Skinrot:BAAANQAECgQIBQAAAA==.',
Sm='Smig:BAAANQADCgUICAAAAA==.',
Sn='Snowball:BAAANQADCggICwAAAA==.',
So='Soeki:BAAANQAECgEIAQAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Soullovez:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Soulshocks:BAAANQAECgIIAwAAAA==.Soulviver:BAAANQAECgQIBQAAAA==.',
Sp='Spiritwarden:BAAANQAECgIIAwAAAA==.Splootz:BAAANQADCggICAAAAA==.',
St='Stimer:BAAANQAECgYIDAAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Suxor:BAAANQADCgcIDAAAAA==.',
Sw='Swordboardal:BAAANQAECgcIEQAAAA==.',
Sy='Sybius:BAAANQAECgEIAQAAAA==.Symptom:BAAANQAECgEIAQAAAA==.Syncophat:BAAANQADCggIEwAAAA==.',
Ta='Tad:BAAANQADCgYICAAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQADCgUIBwAAAA==.Talanzen:BAAANQAECgMIAwAAAA==.',
Te='Teacup:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
Th='Thrakara:BAABNQAECoEXAAIIAAgJBRtIBgB5AgAIAAgJBRtIBgB5AgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgEIAQAAAA==.Thundrall:BAAANQAECgEIAQAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAAANQAECgIIAgAAAA==.',
To='Torches:BAAANQADCgcIBwAAAA==.',
Tr='Truths:BAAANQAFFAQIBAAAAA==.Trystrom:BAAANQADCgYIBgAAAA==.',
Tx='Txbloodstorm:BAAANQADCgYIBgAAAA==.Txgunny:BAAANQADCggICgAAAA==.',
Ty='Tymptriss:BAAANQADCgcIDwAAAA==.',
Um='Umbren:BAAANQADCggIEwAAAA==.',
Va='Valartha:BAAANQADCgcIDwAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgMIBAAAAA==.Velsea:BAAANQADCgYICQAAAA==.Velstadt:BAAANQAECgMIAwAAAA==.Venhance:BAAANQAECgQIBAAAAA==.Venotu:BAAANQAECgQIBgAAAA==.Vermilion:BAAANQADCgcIFQAAAA==.',
Vh='Vholatile:BAAANQAECgEIAQAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQADCgcIDQAAAQ==.',
Vo='Voidherron:BAAANQAECgEIAQAAAA==.Voodoomama:BAAANQADCgYIBgAAAA==.',
Wa='Warlockbot:BAAANQAECgcIDwAAAA==.Warmongral:BAAANQADCgMIBQAAAA==.Waterboot:BAAANQADCgMIAwAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAAANQADCggIEAAAAA==.',
Wh='Wholesome:BAAANQADCgcIBgAAAA==.',
Wi='Wig:BAAANQADCgQIBAAAAA==.Wildbill:BAAANQADCgYIBwAAAA==.',
Wo='Wombo:BAAANQAECgMIAwAAAA==.Woolala:BAAANQAECgcIDAAAAA==.',
Wu='Wut:BAAANQADCgYICgABNQAECgUICgABAAAAAA==.',
Xa='Xalisto:BAAANQADCgMIAwAAAA==.',
Xl='Xlia:BAAANQADCggIEgAAAA==.',
Ya='Yazmyn:BAAANQAECgEIAQAAAA==.',
Ye='Yerehmi:BAAANQADCgYICQAAAA==.',
Yu='Yuny:BAAANQAECgMIAwAAAA==.',
Za='Zaier:BAAANQAECgcIDAAAAA==.',
Ze='Zeltan:BAAANQAECgUIDwAAAA==.',
Zh='Zhundrenga:BAAANQADCgcIDwAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
['År']='Åres:BAAANQADCgEIAQAAAA==.',
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
