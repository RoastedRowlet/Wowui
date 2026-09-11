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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaryyee:BAAANQADCggIDgAAAA==.',
Ac='Acaeus:BAAANQABCgQIBQAAAA==.Aceforlife:BAAANQADCgcIEQAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgMIAwAAAA==.Aequus:BAAANQABCgQIAgAAAA==.Aevenyhm:BAAANQAECgUIBQAAAA==.',
Ag='Aghorn:BAAANQADCgQIBAAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Ak='Akijin:BAAANQABCgQIBAABNQAECgQIBAABAAAAAA==.Akismite:BAAANQAECgQIBAAAAA==.',
Al='Alemental:BAAANQADCgcIEgABNQADCggICAABAAAAAA==.Algana:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Allhallows:BAAANQADCgcIEAAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAAANQAECgMIBQAAAA==.',
An='Andanto:BAAANQADCgYIEQAAAA==.Angeliz:BAAANQADCgQIBAAAAA==.Anneweaver:BAABNQAECoEUAAMCAAgJ1BypAgA4AgADAAgJQBV2NwBdAgACAAgJwRmpAgA4AgAAAA==.Anorantha:BAAANQAECgQICAAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAAANQADCgUIBQABNQADCgcIDgABAAAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arrowin:BAAANQADCgQIBAAAAA==.',
As='Ashalan:BAAANQAECgEIAQAAAA==.Asherabinx:BAAANQABCgYIDgAAAA==.Astesia:BAAANQADCgYIBgAAAA==.Astrraa:BAAANQADCgQIBQAAAA==.Asulo:BAAANQADCggIDwABNQAFFAEIAQABAAAAAA==.',
At='Atrejha:BAAANQAECgYIDAAAAA==.',
Au='Aurä:BAAANQADCggIFQABNQAECgYICgABAAAAAA==.',
Aw='Awesome:BAAANQAECgEIAQAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azrina:BAAANQAECgIIAgAAAA==.',
Ba='Baidden:BAAANQADCgMIBQAAAA==.Baldrogue:BAAANQAECgcIBwAAAA==.Baldwarrior:BAAANQAECgQIBgAAAA==.Bandidos:BAAANQADCgYIBQAAAA==.',
Be='Beckz:BAAANQADCgUIBQAAAA==.Beefhambacon:BAAANQADCgUIBQAAAA==.Behealzabub:BAAANQADCggIDQAAAA==.Belmatride:BAAANQAECgIIAgAAAA==.Belpepper:BAAANQAECgUICAAAAA==.Bendelmonte:BAAANQADCgQIBAABNQADCggIFAABAAAAAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQADCgcIEgAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAAANQAECgQIBQAAAA==.Bindinglight:BAABNQAECoEbAAMEAAkJqBAoHQDvAQAEAAgJehAoHQDvAQAFAAcJ2g3UDwDDAQAAAA==.Birdofhermes:BAAANQADCgMIAwAAAA==.Biñx:BAAANQABCgQICQAAAA==.',
Bl='Blarr:BAAANQADCggIDgAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.Blindvoid:BAAANQADCggICwABNQADCgIIAgABAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgYIDAABAAAAAA==.',
Bo='Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQADCgUICAAAAA==.Boonksdeath:BAAANQADCgIIAgAAAA==.Boonksdragon:BAAANQADCgMIAwAAAA==.Boonlock:BAAANQADCgIIAgAAAA==.Boreowlis:BAAANQABCgQICAAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQADCgIIAgAAAA==.Brisanna:BAAANQADCggIEwAAAA==.',
Bu='Budgeroo:BAAANQAECgMIAwAAAA==.',
['Bà']='Bàwlz:BAAANQADCggIFAAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
Ca='Caelix:BAAANQADCgQIBQAAAA==.Camitriel:BAABNQAECoFFAAMGAAgJCyYEBQAaAwAGAAcJ9iUEBQAaAwAHAAQJeCO7EwCiAQAAAA==.',
Ch='Chadder:BAAANQAECgQIBQAAAA==.Charliie:BAAANQAECgMIBAAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cheesydemon:BAAANQADCggIEgAAAA==.Cherryfudge:BAAANQADCgQIBQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.',
Cl='Classyshammy:BAAANQADCgQIBAAAAA==.Clockworks:BAAANQADCgcICgAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAAANQAECgUICAABNQAFFAEIAgABAAAAAA==.Coneja:BAAANQAECgEIAQAAAA==.',
Cr='Craiso:BAAANQAECgQIBgAAAA==.Crankinhawg:BAAANQAECgQICAAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYIBgABNQADCggIGgABAAAAAA==.Crisarrow:BAAANQADCgcIEAAAAA==.',
Cu='Current:BAAANQAECgQIBAAAAA==.',
Cy='Cynesh:BAACNQAFFIEIAAMIAAUJPiAfAAD1AQAIAAUJPiAfAAD1AQAJAAMJdgSKBQC7AAA1AAQKgRgAAwgACQlnJRwBAL0DAAgACQleJRwBAL0DAAkABwmqHUwRADcCAAAA.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Dangybangy:BAAANQADCggIFgAAAA==.Danjaianka:BAAANQADCgcIDwAAAA==.Darkkragmur:BAAANQAECgIIAgAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Datbishkarma:BAAANQAECgEIAQAAAA==.',
Dd='Dding:BAAANQAECgYICwAAAA==.',
De='Deadbarcy:BAAANQADCgIIAgAAAA==.Deathklok:BAAANQADCgUIBQAAAA==.Deathran:BAAANQAECgQIBQAAAA==.Deezgrips:BAAANQAECgYICgAAAA==.Deffgwip:BAAANQADCgcIDAAAAA==.Delfine:BAAANQADCgcICQAAAA==.Desimus:BAAANQADCgMIAwAAAA==.Despott:BAAANQAECgYICAAAAA==.Dethfox:BAAANQADCggIFAAAAA==.',
Di='Dioni:BAAANQAECgMIBAABNQAECgQIBgABAAAAAA==.Dirknasty:BAAANQADCgYIDwAAAA==.Diyfootjobs:BAAANQADCgYIEAAAAA==.',
Dk='Dkurther:BAAANQADCgEIAQAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doublehelix:BAAANQAECgEIAQAAAA==.',
Dr='Drackygacky:BAAANQADCgYIBwAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAAANQADCggIEwAAAA==.Draz:BAAANQADCggICgAAAA==.',
Du='Duesenjaeger:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAAANQAECgQIBQAAAA==.',
['Dø']='Døric:BAAANQADCgcIDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Eh='Ehud:BAAANQAECgEIAgAAAA==.',
Ek='Ekô:BAAANQADCggIDgAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAAANQAECgYICwAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Elementium:BAAANQADCgcIBwAAAA==.Elfmas:BAAANQAECgUIBwAAAA==.',
Em='Emerhy:BAAANQAECgEIAQAAAA==.',
Es='Escänor:BAAANQAECgIIAgAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eylos:BAAANQADCgIIAgAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQADCgUIBwAAAA==.Fanorage:BAAANQADCgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQIBQAAAA==.',
Fi='Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgQIBgAAAA==.Flexhack:BAAANQADCgYIEAAAAA==.Flåsh:BAAANQAECgQIBAAAAA==.',
Fo='Focinnet:BAAANQADCggIDwAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Four:BAAANQADCgUICAAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frieren:BAAANQADCggIDwAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galithiri:BAAANQADCggICAAAAA==.Ganthani:BAAANQAECgMIAwAAAA==.Garzett:BAAANQAECgUICAAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAAANQADCgIIAgAAAA==.',
Gh='Ghostdaliar:BAAANQADCgIIAgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAECgkJGwAEAKgQAA==.Glizzyrizily:BAAANQADCgMIAwABNQAECgkJGwAEAKgQAA==.Glizzyys:BAAANQADCgMIAwABNQAECgkJGwAEAKgQAA==.Gllizzard:BAAANQADCgMIAwAAAA==.',
Go='Gordo:BAAANQAECgYIBgAAAA==.Gore:BAAANQADCgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggIDgAAAA==.Grhm:BAAANQADCggIDgAAAA==.Grim:BAABNQAECoEZAAIKAAkJaSHTBABlAwAKAAkJaSHTBABlAwAAAA==.',
Gu='Gumsy:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
['Gø']='Gørë:BAAANQADCgQIBgAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAAANQAECgEIAQAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgMIAwAAAA==.',
He='Healsdog:BAAANQADCgMIAwAAAA==.Hecâte:BAAANQABCgMIBAAAAA==.Helfon:BAAANQAECgQIBwAAAA==.Helganelf:BAAANQADCgIIAwAAAA==.Helices:BAAANQADCggIEgAAAA==.',
Hi='Highlordt:BAAANQAECgUIBgAAAA==.Highlordtron:BAAANQADCggIDQAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.',
Hk='Hkala:BAAANQADCggIEgAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQADCgcIEQAAAA==.Holyfae:BAAANQAECgYIDQAAAA==.Holygrom:BAAANQAECgUIBQAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAEANQAFFAEIAQABNQAECgkJIAAKAP8lAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCgYIDwAAAA==.Hopesfall:BAAANQAECgIIAgAAAA==.Howzitcuz:BAAANQABCgQIBAABNQAECgEIAQABAAAAAA==.Hozari:BAAANQAECgUICAAAAA==.',
Ht='Ht:BAAANQADCgYIBgAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQADCggIEgAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAECgkJGwAEAKgQAA==.',
Il='Ilirranna:BAAANQAECgIIAwAAAA==.',
In='Infi:BAACNQAFFIEIAAIJAAUJEx/jAADyAQAJAAUJEx/jAADyAQA1AAQKgRoAAgkACQnWJKkBAKUDAAkACQnWJKkBAKUDAAAA.Initapoop:BAAANQADCgYIBgAAAA==.Inosukè:BAAANQAECgUICQAAAA==.',
Io='Ioannis:BAAANQADCgYIDgAAAA==.',
Is='Isos:BAAANQAECgYICAAAAA==.Isus:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.',
Iy='Iykyk:BAAANQADCgQICQABNQAECgEIAQABAAAAAA==.',
Ja='Jadeadly:BAAANQAECgcIBAAAAA==.Jaded:BAAANQAECgcIDAAAAA==.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAAANQADCggIFQAAAA==.Javyr:BAAANQAECgEIAQAAAA==.Jayfmtv:BAAANQADCgQIBAAAAA==.',
Je='Jessicax:BAAANQAECgQIBAAAAA==.',
Jl='Jlnxy:BAAANQAECgQIBAAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judo:BAAANQADCgIIAgAAAA==.',
Ka='Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.Kaiola:BAAANQADCgYIDAAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kamistri:BAAANQAECgEIAQAAAA==.Kanaa:BAAANQADCgIIAgAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.Karessandra:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.Karrison:BAAANQADCgEIAQAAAA==.',
Ke='Keastral:BAAANQADCgIIAgAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAAANQAECgUICgAAAA==.Kelestrah:BAAANQADCgQIBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAAANQAECgEIAQAAAA==.',
Ki='Kickpigeons:BAAANQABCgQIBgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAAANQAECgIIAgAAAA==.',
Ko='Kodeck:BAAANQADCgcIEAAAAA==.Kodokan:BAAANQADCgQICAAAAA==.Koshima:BAAANQAECgQIBwAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimhit:BAAANQADCgUICwAAAA==.',
Ku='Kudranne:BAAANQADCgQICAABNQADCggICAABAAAAAA==.Kugia:BAAANQAECgQIBgAAAA==.',
Ky='Kynndell:BAAANQADCgYIEAAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazyryx:BAAANQADCgMIAwAAAA==.',
Le='Leetheal:BAAANQAECggIEQAAAA==.Leethul:BAAANQAECgIIAgAAAA==.Lelethxx:BAAANQAECgEIAQAAAA==.Lesanna:BAAANQAECgYICgAAAA==.Leysmith:BAAANQAECgUICgAAAA==.',
Li='Lifestream:BAAANQADCgcIEgAAAA==.Lilheal:BAAANQADCgIIAgAAAA==.Lionël:BAAANQADCgYICwAAAA==.Lizbethe:BAAANQAECgEIAQAAAA==.',
Lo='Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQADCgcICAAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lu='Lumibell:BAAANQABCgUIBQAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQABCgIIAgAAAA==.Magaspy:BAAANQADCggIDgAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magikiarly:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Mamimage:BAAANQAFFAEIAgAAAA==.Marukka:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQADCgcICQAAAA==.',
Me='Meadowlark:BAAANQAECgIIAgAAAA==.Mefistofeles:BAAANQAECgIIAgAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Metalrules:BAAANQABCgIIAgAAAA==.Methypheni:BAAANQAECgIIAgAAAA==.',
Mi='Milfshotz:BAAANQADCgIIAgAAAA==.Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQADCgUIBQAAAA==.Mirajanna:BAAANQAECgYICgAAAA==.Missmouthoff:BAAANQAECgMIBQAAAA==.Mitenâ:BAAANQADCgMIBAAAAA==.Mizzxgummy:BAAANQADCggICQAAAA==.',
Mo='Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQADCgUIDQAAAA==.Mookins:BAAANQAECgQIBAAAAA==.Moonfishing:BAAANQAECgYIBgAAAA==.Moonfly:BAAANQAECggIEQAAAA==.Morax:BAAANQADCgYIDQAAAA==.Mourne:BAAANQAECgMIBAAAAA==.',
Ms='Mssmalvile:BAAANQADCgQIAwAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Nalaana:BAAANQAECgEIAgAAAA==.Nalariel:BAAANQAECgcIEAAAAA==.Nalmagedan:BAAANQADCgUIBQAAAA==.Nandorr:BAAANQADCgEIAQAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQADCggICAAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nervouz:BAAANQAECgMIAwAAAA==.',
Ni='Nikis:BAAANQADCgcICwAAAA==.',
No='Nobbs:BAAANQADCgYICQAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.',
Nu='Nualaperafin:BAAANQAECgcIDwAAAA==.',
Ny='Nyvara:BAAANQADCgQIBAAAAA==.Nyxkitsune:BAAANQADCgQIBQAAAA==.',
Oi='Oiyo:BAAANQABCgYIBwAAAA==.',
Ol='Olayro:BAAANQAECgMIAwAAAA==.',
On='Onlyrage:BAAANQADCgYIBgAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAAANQAECgQIBAAAAA==.',
Op='Openingshift:BAAANQADCgYICAAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgEIAQAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palkavanka:BAAANQADCgYICgAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Persephie:BAAANQADCgUICAABNQAECgMIAwABAAAAAA==.',
Ph='Pharmacology:BAAANQAECgIIAgAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQADCgYIBgAAAA==.',
Pi='Pinkberri:BAAANQABCgQIBgAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCgUIBAAAAA==.',
Po='Popa:BAAANQAECgcIDwAAAA==.',
Pr='Prathe:BAAANQADCggIFAAAAA==.Prayinfury:BAAANQADCggICAAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgQIBAAAAA==.',
Pu='Pulsate:BAAANQAECgIIAgAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Qa='Qaucker:BAAANQADCggIFAAAAA==.',
Qi='Qiz:BAAANQAECgEIAQAAAA==.',
Qu='Quadhelix:BAAANQADCgcIBwAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Rad:BAAANQADCgUICQABNQAECgIIAQABAAAAAA==.Raiken:BAAANQADCgYIDwAAAA==.Rasto:BAAANQADCggIDQAAAA==.Raszto:BAAANQADCgIIAgABNQADCggIDQABAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQADCgUIBgAAAA==.Rendezook:BAAANQADCgMIAwAAAA==.',
Ri='Rincewind:BAAANQADCgMIBgAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgIIAgAAAA==.',
Ro='Roci:BAAANQADCgQIBAAAAA==.Rocker:BAAANQAECggICAAAAA==.Roxus:BAAANQAECgMIBgAAAA==.',
Sa='Saegusa:BAAANQADCggIDQAAAA==.Saepius:BAAANQAECgIIAgAAAA==.Salestia:BAAANQAECgMIAwAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sasive:BAAANQADCggIDgAAAA==.Satanicpanic:BAAANQADCggICAAAAA==.Sazoku:BAAANQAECgQIBAAAAA==.',
Sc='Schmall:BAAANQADCgYIDwAAAA==.Scrodumpulse:BAAANQADCgYIBgAAAA==.',
Se='Sendit:BAAANQAECgEIAQAAAA==.Seniormage:BAAANQAECgEIAQAAAA==.Serveil:BAAANQADCgIIAgABNQAECgYIDAABAAAAAA==.',
Sh='Shadesprint:BAAANQAECgIIAwAAAA==.Shamamoomoo:BAAANQADCgcIDwAAAA==.Shaowen:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAAANQAECgYIEQAAAA==.Shiau:BAAANQAECgEIAQAAAA==.Shinky:BAAANQADCgUIBAABNQAECgQIBQABAAAAAA==.Shý:BAAANQADCggICQAAAA==.',
Si='Silvaine:BAAANQADCgYICwAAAA==.Silverstorm:BAAANQAECgcIDQAAAA==.Sixii:BAAANQADCggIDQAAAA==.',
Sk='Skitzz:BAAANQADCgIIAgAAAQ==.',
Sl='Slackr:BAAANQADCgQIBAAAAA==.Slackrm:BAAANQADCgMIBAAAAA==.Slashyr:BAAANQAECgQIBwAAAA==.',
Sn='Snipez:BAAANQAECgEIAQAAAA==.Snortyhotorc:BAAANQADCgIIAgAAAA==.Snortymcgoop:BAAANQAECgMIBAAAAA==.',
So='Solclipeus:BAAANQAECgYIDAAAAA==.Soldh:BAAANQAECgMIAwABNQAECgYIDAABAAAAAA==.Soupz:BAAANQADCggIFAAAAA==.',
Sp='Sparadin:BAAANQADCgYIEQAAAA==.Spartacûs:BAAANQAECgEIAQAAAA==.Spikore:BAAANQABCgQIBgAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Strånge:BAAANQAECgYIAwAAAA==.Stìtch:BAAANQAFFAIIAgAAAA==.Stítch:BAAANQADCgQIBAABNQAFFAIIAgABAAAAAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQADCgQIBAAAAA==.Suldån:BAAANQADCgcIDAAAAA==.Suoop:BAAANQADCgYICgAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQADCgYIDQAAAA==.Syraice:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.Syrare:BAAANQADCgYIDgAAAA==.Syvenari:BAAANQAECgEIAQAAAA==.',
['Sï']='Sïxx:BAAANQADCgMIAwABNQADCggIDQABAAAAAA==.',
Ta='Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCgQIBAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgQIBgAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgIIAgAAAA==.Tatsumy:BAAANQAECgIIAQAAAA==.',
Tc='Tcmon:BAAANQAFFAEIAQAAAA==.',
Te='Teaglizzy:BAAANQADCgEIAQABNQAECgkJGwAEAKgQAA==.Teehole:BAAANQAECgEIAQAAAA==.Telihill:BAAANQADCgUICQAAAA==.Telsarra:BAAANQAECgQIBAAAAA==.',
Th='Thebigtuna:BAAANQAECggICwAAAA==.Theladydruid:BAAANQAECgQIBgAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQADCgQIBAAAAA==.Thighsoffel:BAAANQADCgcIDgAAAA==.Thunderhóof:BAAANQABCgYICwAAAA==.',
Ti='Tigerpa:BAAANQADCgEIAQAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAAANQAECgQIBgAAAA==.Tinystotems:BAAANQAECgEIAQAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQAECgQICgAAAA==.Tiptip:BAAANQAECgIIAgAAAA==.Tisaryn:BAAANQADCggICwAAAA==.',
To='Tofulady:BAAANQAECgcIEgAAAA==.',
Tr='Tremors:BAAANQADCggICAAAAA==.',
Ts='Tsufury:BAAANQADCgIIAwAAAA==.',
Tw='Twobithusler:BAAANQADCgYIBwAAAA==.Twoone:BAAANQADCgIIAgAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Un='Unhowly:BAAANQAECgcIDwAAAA==.Unpoppable:BAAANQAECgIIAgAAAA==.',
Va='Vakir:BAAANQAECgUICAAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQADCgYICQAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.Vatica:BAAANQADCgUIBgAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Venvalzhar:BAAANQAECgQIBAAAAA==.Veralidaine:BAAANQAECgIIAgAAAA==.Vestammeni:BAAANQAECgcIBwAAAA==.',
Vi='Vixsaurion:BAAANQADCgIIAgAAAA==.',
Vl='Vlamort:BAAANQADCgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vow:BAAANQAECgUIBgAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wc='Wckd:BAAANQAECgYIDAAAAA==.',
We='Weaksnow:BAAANQAECgUIBgABNQAFFAEIAgABAAAAAA==.Weedvegeta:BAAANQAECgEIAQAAAA==.Wetremin:BAAANQADCgQIBAAAAA==.',
Wh='Whirpy:BAAANQAECgIIAgAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQAECgEIAQAAAA==.',
Wi='Wingedlady:BAAANQADCgcIEgAAAA==.Wingss:BAAANQAECgUIEAAAAA==.',
Wu='Wushu:BAAANQADCgYIBgAAAA==.',
Xi='Xiing:BAAANQADCggICwAAAA==.Xinei:BAAANQADCgQIAQAAAA==.',
Xn='Xneutron:BAAANQAECgEIAQAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Ya='Yaiie:BAAANQADCggIEAAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yuuki:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
['Yü']='Yüto:BAAANQAECgcICwAAAA==.',
Za='Zabuto:BAAANQAECgIIAgAAAA==.Zahäära:BAAANQADCgUIBwAAAA==.Zaldiz:BAAANQADCgIIAgAAAA==.Zarrtan:BAAANQADCgYIBgAAAA==.Zazprie:BAAANQADCgcICQAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAAANQAECgIIAQAAAA==.',
['Äl']='Älissia:BAAANQADCgcICwAAAA==.',
['Ën']='Ëndo:BAAANQAECgMIAwAAAA==.',
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
