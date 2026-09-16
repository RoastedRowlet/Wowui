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

local lookup = {'Unknown-Unknown','Paladin-Protection','Mage-Frost','Mage-Arcane','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Monk-Windwalker','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Warrior-Arms','DemonHunter-Devourer','Monk-Mistweaver',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ac='Acaeus:BAAANQABCgQIBQAAAA==.Aceforlife:BAAANQADCgcIFwAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgYIBgAAAA==.Aequus:BAAANQABCgQIAgAAAA==.Aevenyhm:BAAANQAECgUICQAAAA==.',
Ag='Aghorn:BAAANQAECgEIAQAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Ak='Akijin:BAAANQABCgQIBAABNQAECgQIBQABAAAAAA==.Akismite:BAAANQAECgQIBQAAAA==.',
Al='Alemental:BAAANQADCgcIEgABNQADCggIEAABAAAAAA==.Algana:BAAANQADCggIDAABNQAECgUICAABAAAAAA==.Allhallows:BAAANQAECgEIAQAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAAANQAECgQIBwAAAA==.Altarboizyum:BAAANQAECgIIAQABNQAECggIGAACAD8gAA==.',
An='Andanto:BAAANQAECgMIAwAAAA==.Angeliz:BAAANQAECgYIBgAAAA==.Anneweaver:BAABNQAECoEkAAMDAAgJ5x3cBAAPAgAEAAgJdBkURgB9AgADAAgJwRncBAAPAgABNQAECgcIDgAEANsVAA==.Anorantha:BAAANQAECgQIEwAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAAANQADCgUIBQABNQADCggIFgABAAAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arizticat:BAAANQABCgIIAwAAAA==.Arrowin:BAAANQADCgQIBAAAAA==.',
As='Ashalan:BAAANQAECgIIAwAAAA==.Asherabinx:BAAANQABCgYIDgAAAA==.Astesia:BAAANQADCgYIBgAAAA==.Astrraa:BAAANQADCgUIBgAAAA==.Asulo:BAAANQADCggIDwABNQAFFAEIAQABAAAAAA==.',
At='Atrejha:BAAANQAFFAEIAQAAAA==.',
Au='Aurä:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.',
Av='Avera:BAAANQADCgYIBgAAAA==.',
Aw='Awesome:BAAANQAECgEIAgAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azrina:BAAANQAECgUIBwAAAA==.',
Ba='Baidden:BAAANQADCgMIBQAAAA==.Baldrogue:BAAANQAECgcIDwAAAA==.Baldwarrior:BAAANQAECgUICwAAAA==.Bandidos:BAAANQADCgYICAAAAA==.',
Be='Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgMIAwAAAA==.Behealzabub:BAAANQAECgIIAgAAAA==.Belmatride:BAAANQAECgIIAwAAAA==.Belpepper:BAAANQAECgUICAAAAA==.Bendelmonte:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQADCggIGgAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAAANQAECgQIBQAAAA==.Bindinglight:BAABNQAECoEmAAMFAAkJUhNcIgAgAgAFAAgJeRNcIgAgAgAGAAcJ7Q+IFQDGAQAAAA==.Birdofhermes:BAAANQADCgMIAwAAAA==.Biñx:BAAANQABCgQICQAAAA==.',
Bl='Blarr:BAAANQADCggIDgAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgABAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgcIEAABAAAAAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQADCgUICAAAAA==.Boonksdeath:BAAANQADCgIIAgAAAA==.Boonksdragon:BAAANQADCggICwAAAA==.Boonlock:BAAANQADCgIIAgAAAA==.Boreowlis:BAAANQABCgQICAAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQADCgIIAgAAAA==.Brisanna:BAAANQAECgIIAgAAAA==.',
Bu='Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAAANQAECgMIAwAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
Ca='Caelix:BAAANQADCgQIBQAAAA==.Caledor:BAAANQAECgIIAgAAAA==.Camitriel:BAABNQAECoF4AAMHAAgJZyYTCgAZAwAHAAcJNSYTCgAZAwAIAAQJAyWhEgC5AQAAAA==.',
Ch='Chadder:BAAANQAECgYICwAAAA==.Charliie:BAAANQAECgUICQAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cheesydemon:BAAANQAECgMIAwAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCgQIBAAAAA==.Clockworks:BAAANQADCgcIDwAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAAANQAECgYIDQABNQAECggIGAAEABkXAA==.Coneja:BAAANQAECgUICAAAAA==.Coomspit:BAAANQADCggICAAAAA==.Covidnynteen:BAAANQADCgMIAwAAAA==.Cowtastrophe:BAAANQABCgcIEAAAAA==.',
Cr='Craiso:BAAANQAECgYIDAAAAA==.Crankinhawg:BAAANQAECgQICwAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQADCggIGgABAAAAAA==.Crisarrow:BAAANQADCggIGAAAAA==.',
Cu='Current:BAAANQAECgUICQAAAA==.',
Cy='Cynesh:BAACNQAFFIENAAMJAAYJOyEhAABmAgAJAAYJOyEhAABmAgAKAAMJdgSkCQCwAAA1AAQKgRoAAwkACQnMJZkCALMDAAkACQnDJZkCALMDAAoABwmqHX4YAAcCAAAA.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Dangybangy:BAAANQAECgQIBAAAAA==.Danjaianka:BAAANQADCgcIFwAAAA==.Darkken:BAAANQADCgYIBgABNQADCgcIDwABAAAAAA==.Darkkragmur:BAAANQAECgQIBgAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Datbishkarma:BAAANQAECgMIBAAAAA==.',
Dd='Dding:BAAANQAECggIEwAAAA==.',
De='Deadbarcy:BAAANQAECgIIAgAAAA==.Deathklok:BAAANQADCgUIBQAAAA==.Deathran:BAAANQAECgUICgAAAA==.Deezgrips:BAAANQAFFAEIAQAAAA==.Deffgwip:BAAANQADCgcIDAAAAA==.Delfine:BAAANQADCggIEQAAAA==.Desimus:BAAANQADCgMIAwAAAA==.Despott:BAAANQAECgYICAAAAA==.Dethfox:BAAANQAECgEIAQAAAA==.',
Di='Dioni:BAAANQAECgUICQABNQAECgYIDAABAAAAAA==.Dirknasty:BAAANQAECgEIAQAAAA==.Diyfootjobs:BAAANQADCgYIFQAAAA==.',
Dk='Dkurther:BAAANQADCgYIBwAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doublehelix:BAAANQAECgEIAQAAAA==.Dovish:BAAANQAECgQIBAAAAA==.',
Dr='Drackygacky:BAAANQADCgYIDAAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAAANQAECgMIAwAAAA==.Draz:BAAANQADCggICgAAAA==.Droozh:BAAANQADCgMIAwAAAA==.',
Du='Duesenjaeger:BAAANQADCgEIAQAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAAANQAECgQIBQAAAA==.',
['Dø']='Døric:BAAANQADCgcIDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Ec='Ectoplasm:BAAANQADCgUIBQAAAA==.',
Eh='Ehud:BAAANQAECgQICAAAAA==.',
Ei='Eisiss:BAAANQABCgEIAQAAAA==.',
Ek='Ekô:BAAANQADCggIDgAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAAANQAECgYIDwAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Elementium:BAAANQAECgIIAgAAAA==.Elfmas:BAAANQAECgUIBwAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.',
Em='Emerhy:BAAANQAECgEIAQAAAA==.',
Es='Escänor:BAAANQAECgMIBAAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eylos:BAAANQADCgIIAgAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQADCggIDwAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQADCgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQIBQAAAA==.',
Fi='Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgQIBgAAAA==.Flexhack:BAAANQAECgMIAwAAAA==.Flåsh:BAAANQAECgUICQAAAA==.',
Fo='Focinnet:BAAANQAECgQICAAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Four:BAAANQADCgYIDgAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frieren:BAAANQAECgMIAwAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galithiri:BAAANQAECgEIAQAAAA==.Ganthani:BAAANQAECgMIBgAAAA==.Garzett:BAAANQAECgYIDgAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAAANQADCggICgAAAA==.',
Gh='Ghostdaliar:BAAANQADCgIIAgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAECgkJJgAFAFITAA==.Glizzyrizily:BAAANQADCgMIAwABNQAECgkJJgAFAFITAA==.Glizzyys:BAAANQADCggICwABNQAECgkJJgAFAFITAA==.Gllizzard:BAAANQADCgMIAwAAAA==.',
Go='Gordo:BAAANQAECgYIBgAAAA==.Gore:BAAANQADCgQIBAAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Grenzo:BAAANQAECgEIAQAAAA==.Grhm:BAAANQADCggIDgAAAA==.Grim:BAABNQAECoEZAAILAAkJaSGBCABCAwALAAkJaSGBCABCAwAAAA==.',
Gu='Gumsy:BAAANQADCgYICgABNQAECgQIBgABAAAAAA==.',
['Gø']='Gørë:BAAANQADCgQIBgAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAAANQAECgQIBQAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgMIAwAAAA==.',
He='Healscat:BAAANQADCgUIBQAAAA==.Healsdog:BAAANQADCgUIBQAAAA==.Hecâte:BAAANQABCggICgAAAA==.Helfon:BAAANQAECgUIDAAAAA==.Helgadknight:BAAANQABCgMIAwAAAA==.Helganelf:BAAANQADCgIIAwAAAA==.Helices:BAAANQAECggIBgAAAA==.',
Hi='Highlordt:BAAANQAECgYIDAAAAA==.Highlordtron:BAAANQADCggIDgAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQADCggIGQAAAA==.Holyfae:BAABNQAECoEWAAIMAAgJYhRWIwBQAgAMAAgJYhRWIwBQAgAAAA==.Holygrom:BAAANQAECgcIDgAAAA==.Holysplash:BAAANQAECgMIAwAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAEBNQAECoEdAAILAAkJgySfAgC2AwALAAkJgySfAgC2AwABNQAECgkJJgALAHgmAA==.Honeyshamwow:BAAANQADCgQIBAAAAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCggIFwAAAA==.Hopesfall:BAAANQAECgIIAwAAAA==.Howzitcuz:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Hozari:BAAANQAECgYIDgAAAA==.',
Ht='Ht:BAAANQADCgYIBgAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgIIAgAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAECgkJJgAFAFITAA==.',
Il='Ilirranna:BAAANQAECgIIBAAAAA==.',
In='Infi:BAACNQAFFIEOAAIKAAYJKRz2AAA0AgAKAAYJKRz2AAA0AgA1AAQKgR4AAgoACQkwJXkCAJQDAAoACQkwJXkCAJQDAAAA.Initapoop:BAAANQAECgEIAQAAAA==.Inosukè:BAAANQAECgYIDwAAAA==.Invisibro:BAAANQAECgQIBAAAAA==.',
Io='Ioannis:BAAANQAECgEIAQAAAA==.',
Is='Isos:BAAANQAECgYIDQAAAA==.Isus:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.',
Iy='Iykyk:BAAANQADCgQICQABNQAECgQIBwABAAAAAA==.',
Ja='Jadeadly:BAAANQAECgcICAAAAA==.Jaded:BAABNQAECoEYAAINAAkJPBLdDwA7AgANAAkJPBLdDwA7AgAAAA==.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAAANQAECgEIAQAAAA==.Javyr:BAAANQAECgIIAwAAAA==.Jayfmtv:BAAANQADCggIDAAAAA==.',
Je='Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Jl='Jlnxy:BAAANQAECgYICQAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judo:BAAANQADCgIIAgAAAA==.',
Ka='Kadre:BAAANQAECgEIAQAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQADCgcIBwABNQAFFAEIAQABAAAAAA==.Kaiola:BAAANQADCgYIEAAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kamistri:BAAANQAECgYIBwAAAA==.Kanaa:BAAANQADCgIIAgAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.Karessandra:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Karrison:BAAANQADCgEIAQAAAA==.Kayarra:BAAANQADCgEIAQAAAA==.Kayonna:BAAANQABCgEIAQAAAA==.',
Ke='Keastral:BAAANQADCgIIAgAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAAANQAECgUIDgAAAA==.Kelestrah:BAAANQADCgQIBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAAANQAECgQIBwAAAA==.Kerthur:BAAANQADCgYIBgAAAA==.',
Ki='Kickpigeons:BAAANQABCgQIBgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAAANQAECgIIAgAAAA==.',
Ko='Kodeck:BAAANQADCggIGAAAAA==.Kodokan:BAAANQADCgQICAAAAA==.Koshima:BAAANQAECgYIDQAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimhit:BAAANQADCgUICwAAAA==.Krimrok:BAAANQABCgIIAgAAAA==.',
Ku='Kudranne:BAAANQADCgQICAABNQAECgEIAQABAAAAAA==.Kugia:BAAANQAECgYIDAAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
['Kø']='Køkushibø:BAAANQABCgUIBQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAABNQAECoEXAAMOAAkJGxxNEgA/AgAOAAcJ/xpNEgA/AgAPAAQJHQ4YaADQAAAAAA==.Leethul:BAAANQAECgQIBgAAAA==.Lelethxx:BAAANQAECgEIAQAAAA==.Lesanna:BAAANQAECgYIEAAAAA==.Leysmith:BAAANQAECgYIEgAAAA==.',
Li='Lifestream:BAAANQADCgcIEgAAAA==.Lilheal:BAAANQADCgIIAgAAAA==.Lilium:BAAANQADCgUIBQAAAA==.Lionël:BAAANQADCggIEwAAAA==.Lizzanna:BAAANQAECgUIBgAAAA==.',
Lo='Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgMIAwAAAA==.Lorast:BAAANQADCgQIBAAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lu='Lumibell:BAAANQABCgYIBwAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQABCgIIAgAAAA==.Madderco:BAAANQAECggICAAAAA==.Magaspy:BAAANQAECgEIAQAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magikiarly:BAAANQADCgYIDwABNQAECgIIAgABAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Mamimage:BAABNQAECoEYAAIEAAgJGRd0UwBQAgAEAAgJGRd0UwBQAgAAAA==.Marukka:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQADCgcICQAAAA==.',
Me='Meadowlark:BAAANQAECgIIAgAAAA==.Mefistofeles:BAAANQAECgQIBgAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAAANQAECgYICAABNQAECgIIAgABAAAAAA==.Metalrules:BAAANQABCggICAAAAA==.Methypheni:BAAANQAECgIIAgAAAA==.',
Mi='Milfshotz:BAAANQADCgIIAgAAAA==.Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQADCgUIBQAAAA==.Mirajanna:BAAANQAECgYIDwAAAA==.Missmouthoff:BAAANQAECgMICAAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQADCggICQAAAA==.',
Mo='Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgEIAQAAAA==.Mookins:BAAANQAECgQICgAAAA==.Moonfishing:BAAANQAECgYICgAAAA==.Moonfly:BAABNQAECoEbAAIFAAkJyx0qCQBJAwAFAAkJyx0qCQBJAwAAAA==.Morax:BAAANQADCgcIEQAAAA==.Mourne:BAAANQAECgUICQAAAA==.',
Ms='Mssmalvile:BAAANQADCgQIBAAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQADCgYICQABNQAECgQIBgABAAAAAA==.Nalaana:BAAANQAECgEIAgAAAA==.Nalariel:BAAANQAECgcIEwAAAA==.Nalmagedan:BAAANQADCggIDQAAAA==.Nandorr:BAAANQADCgEIAQAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQADCggIEAAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nervouz:BAAANQAECgUIBwAAAA==.',
Ni='Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQADCgcIEQAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.',
Nu='Nualaperafin:BAABNQAECoEZAAIQAAgJxxoyBgCwAgAQAAgJxxoyBgCwAgAAAA==.',
Ny='Nyvara:BAAANQADCgQIBAAAAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Oi='Oiyo:BAAANQABCggICQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAAANQAECgUICAAAAA==.',
Om='Omie:BAAANQADCgQIBAAAAA==.',
On='Onlyrage:BAAANQAECgQIBAAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAAANQAECgcICwAAAA==.',
Op='Openingshift:BAAANQADCggIEAAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgEIAgAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palkavanka:BAAANQADCgYIEAAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Persephie:BAAANQADCgUIDQABNQAECgQIBgABAAAAAA==.',
Ph='Pharmacology:BAAANQAECgQIBgAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQADCgYICwAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCggIDQAAAA==.',
Po='Popa:BAABNQAECoEcAAIMAAkJ4BhREQDYAgAMAAkJ4BhREQDYAgAAAA==.',
Pr='Prathe:BAAANQAECgEIAQAAAA==.Prayinfury:BAAANQAECgQIBAAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgQICAAAAA==.',
Pu='Pulsate:BAAANQAECgQIBgAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECgYIBgAAAA==.',
Qa='Qaucker:BAAANQAECgYIBgAAAA==.',
Qi='Qiz:BAAANQAECgMIBAAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quadhelix:BAAANQAECgMIAwAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Ragémachine:BAAANQADCgQIBAAAAA==.Raiken:BAAANQADCgYIFQAAAA==.Rasto:BAAANQAECgQIBAAAAA==.Raszto:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQADCgUIBgAAAA==.Rendezook:BAAANQAECgIIAgAAAA==.',
Ri='Rincewind:BAAANQADCggIDgAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgIIAgAAAA==.',
Ro='Roci:BAAANQADCgQIBAAAAA==.Rocker:BAAANQAECggICAAAAA==.Roxus:BAAANQAECgUICwAAAA==.',
Sa='Saegusa:BAAANQAECgEIAQAAAA==.Saepius:BAAANQAECgIIAgAAAA==.Salestia:BAAANQAECgQIBwAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sasive:BAAANQAECgIIAgAAAA==.Satanicpanic:BAAANQAECgEIAQAAAA==.Sazoku:BAAANQAECgYICQAAAA==.',
Sc='Scarletnight:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Schmall:BAAANQADCgcIFgAAAA==.Scrodumpulse:BAAANQADCgcICwAAAA==.',
Se='Sendit:BAAANQAECgIIAwAAAA==.Seniormage:BAAANQAECgEIAQAAAA==.Serveil:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.',
Sh='Shadesprint:BAAANQAECgIIAwAAAA==.Shamamoomoo:BAAANQAECgIIAgAAAA==.Shaowen:BAAANQADCgYIBgABNQADCggIEAABAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAABNQAECoEWAAIJAAcJFRHSSADVAQAJAAcJFRHSSADVAQAAAA==.Shiau:BAAANQAECgUIBgAAAA==.Shinky:BAAANQADCgUIBAABNQAECgUICgABAAAAAA==.Shý:BAAANQAECgMIAwAAAA==.',
Si='Silvaine:BAAANQADCggIEwAAAA==.Silverstorm:BAABNQAECoEYAAIRAAgJxBHuRQAcAgARAAgJxBHuRQAcAgAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQIBAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMIBAAAAA==.Slashyr:BAAANQAECgQICAAAAA==.',
Sn='Snipez:BAAANQAECgEIAQAAAA==.Snortyhotorc:BAAANQADCgIIAgAAAA==.Snortymcgoop:BAAANQAECgYICAAAAA==.',
So='Solclipeus:BAABNQAECoEYAAICAAgJPyD1BADvAgACAAgJPyD1BADvAgAAAA==.Soldh:BAAANQAECgMIBQABNQAECggIGAACAD8gAA==.Soulrecall:BAAANQAECgEIAQAAAA==.Soupz:BAAANQAECgMIAwAAAA==.',
Sp='Sparadin:BAAANQADCgYIEQAAAA==.Spartacûs:BAAANQAECgQIBQAAAA==.Spikore:BAAANQABCgQIBgAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAABNQAECoEcAAIHAAkJdiKOAgCNAwAHAAkJdiKOAgCNAwAAAA==.Stítch:BAAANQADCgQIBAABNQAECgkJHAAHAHYiAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQADCgQIBAAAAA==.Suldån:BAAANQADCgcIEgAAAA==.Sunfurious:BAAANQADCggIDQAAAA==.Suoop:BAAANQADCgYICgAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQADCgcIFAAAAA==.Syraice:BAAANQADCgUIBQABNQAECgYIEgABAAAAAA==.Syrare:BAAANQADCgYIDgAAAA==.Syvenari:BAAANQAECgIIAgAAAA==.',
['Sï']='Sïxx:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.',
Ta='Tachisan:BAAANQAECgIIAgAAAA==.Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCgQICAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDAAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgYICAAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQADCggICAAAAA==.Tatsumy:BAAANQAECgQICQAAAA==.',
Tc='Tcmon:BAAANQAFFAEIAQAAAA==.',
Te='Teaglizzy:BAAANQADCgEIAQABNQAECgkJJgAFAFITAA==.Teehole:BAAANQAECgUIBgAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.',
Th='Thebigtuna:BAABNQAECoEVAAISAAkJFh11BgBCAwASAAkJFh11BgBCAwAAAA==.Theladydruid:BAAANQAECgQICgAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQAECgEIAQAAAA==.Thighsoffel:BAAANQADCgcIEwAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thunderhóof:BAAANQABCgYIDQAAAA==.',
Ti='Tigerpa:BAAANQAECgEIAQAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAAANQAECgQICgAAAA==.Tinystotems:BAAANQAECgQIBgAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQAECgQIEQAAAA==.Tisaryn:BAAANQADCggIDgAAAA==.',
To='Tofulady:BAABNQAECoEcAAITAAkJRR1xAwAnAwATAAkJRR1xAwAnAwAAAA==.Tohu:BAAANQABCgIIAgAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQADCgYIBgAAAA==.Totemtoker:BAAANQADCggICAAAAA==.',
Tr='Tremors:BAAANQADCggICAAAAA==.',
Ts='Tsufury:BAAANQAECgIIAgAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoone:BAAANQADCgQIBAAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unhowly:BAABNQAECoEaAAILAAkJ9CIsAwCpAwALAAkJ9CIsAwCpAwAAAA==.Unpoppable:BAAANQAECgQIBwAAAA==.',
Va='Vakir:BAAANQAECgcIDwAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgEIAQAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.Vatica:BAAANQADCggIDAAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Venvalzhar:BAAANQAECgQICAAAAA==.Veralidaine:BAAANQAECgIIAgAAAA==.Vestammeni:BAAANQAECgcICwAAAA==.',
Vi='Vixsaurion:BAAANQAECgEIAQAAAA==.',
Vl='Vlamort:BAAANQADCgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vow:BAAANQAECgUICQAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAAANQAECgYICgABNQAECggIGAAEABkXAA==.Weedvegeta:BAAANQAECgQIBQAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetremin:BAAANQADCgYICgAAAA==.',
Wh='Whirpy:BAAANQAECgUIBwAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQAECgUIBgAAAA==.',
Wi='Wildbeefwood:BAAANQADCgYIBgAAAA==.Wingedlady:BAAANQAECgIIAgAAAA==.Wingss:BAAANQAECgYIEQAAAA==.',
Wu='Wushu:BAAANQADCgYIBgAAAA==.',
Xi='Xiing:BAAANQAECgcICwAAAA==.Xinei:BAAANQADCgQIAQAAAA==.',
Xn='Xneutron:BAAANQAECgMIAwAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Ya='Yaiie:BAAANQADCggIEgAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yuuki:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
['Yü']='Yüto:BAAANQAECggIEQAAAA==.',
Za='Zabuto:BAAANQAECgQIBgAAAA==.Zahäära:BAAANQADCggIDwAAAA==.Zaldiz:BAAANQADCgIIAgAAAA==.Zarrtan:BAAANQADCgYICwAAAA==.Zazprie:BAAANQAECgMIAwAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQAAAA==.',
Zu='Zual:BAAANQADCgYIBgAAAA==.Zularraka:BAAANQADCgEIAQAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAAANQAECgUIBgAAAA==.',
['Äl']='Älissia:BAAANQADCgcICwAAAA==.',
['Ål']='Ålexthegrëat:BAAANQABCgcICgAAAA==.',
['Ën']='Ëndo:BAAANQAECgQIBgAAAA==.',
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
