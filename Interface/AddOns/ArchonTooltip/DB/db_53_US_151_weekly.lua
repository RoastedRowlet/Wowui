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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Shaman-Restoration',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaluah:BAAANQADCgMIAwAAAA==.',
Ac='Acmis:BAAANQADCgYICgABNQADCgcIDQABAAAAAA==.',
Ad='Adomangma:BAAANQABCgQIBAAAAA==.',
Ah='Ahjumma:BAAANQAECgMIAwAAAA==.',
Ak='Akurantirea:BAAANQADCgcIDQAAAA==.',
Al='Allise:BAAANQADCgYICwAAAA==.Alphamaled:BAAANQAECgEIAQAAAA==.Aléthia:BAAANQADCgYICgAAAA==.',
An='Anathemá:BAAANQADCgUIBQAAAA==.Ange:BAAANQADCggIEAAAAA==.',
Ap='Apawpriest:BAAANQAECgIIAgAAAA==.',
Ar='Arraeroda:BAAANQADCgcIDQAAAA==.',
As='Astela:BAAANQADCggIDQAAAA==.',
Au='Aumtatsat:BAAANQAECgUICQAAAA==.Autumn:BAAANQAECgEIAQAAAA==.',
Av='Avatan:BAAANQAECgEIAQAAAA==.Avedeath:BAAANQADCggIDQAAAA==.Aveena:BAAANQADCgMIAwAAAA==.',
Ay='Ayara:BAABNQAECoEZAAICAAgJOiHJBAAFAwACAAgJOiHJBAAFAwAAAA==.',
Ba='Badderdragon:BAAANQAECgQIBQAAAA==.Badmuffin:BAAANQADCgcIDQAAAA==.Bakatran:BAAANQADCgMIBAAAAA==.Balamuth:BAAANQADCgYIBgAAAA==.Bandrui:BAAANQADCgUICQAAAA==.',
Be='Bearlygrillz:BAAANQADCggICAAAAA==.Berkstein:BAAANQADCgcIDQAAAA==.',
Bi='Biggisnicker:BAAANQAECgMIBAAAAA==.Bigspriesty:BAAANQADCgUIBQAAAA==.Bigtone:BAAANQAECgEIAQAAAA==.Bimbomz:BAAANQAECgMIBAAAAA==.Biochemist:BAAANQADCgMIBAABNQADCgcICAABAAAAAA==.Bioengineer:BAAANQADCgYIBgABNQADCgcICAABAAAAAA==.Biogenic:BAAANQADCgIIAgABNQADCgcICAABAAAAAA==.Biomass:BAAANQADCgcICAAAAA==.Birdbrain:BAAANQAECgUIBQAAAA==.',
Bo='Borucmonk:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Borucwar:BAAANQAECgEIAQAAAA==.',
Br='Braedia:BAAANQADCgUICQAAAA==.Brassticus:BAAANQADCgcIBwAAAA==.Brawrski:BAAANQADCgUIBwAAAA==.Briele:BAAANQADCgcIDQAAAA==.Brosabi:BAAANQAECgQIBAABNQAECgEIAQABAAAAAA==.',
Bu='Bubs:BAAANQAECgQIBAAAAA==.',
['Bí']='Bítten:BAAANQADCgcIDgAAAA==.',
Ca='Cakesinatra:BAAANQADCgUIBQABNQADCgYICwABAAAAAA==.Cakewastaken:BAAANQADCgYICwAAAA==.Cakke:BAAANQADCgEIAQAAAA==.Calkestis:BAAANQADCgMIAwAAAA==.Candre:BAAANQAECgMIAwAAAA==.Candyears:BAAANQADCgIIAgAAAA==.Capristal:BAAANQADCgYICAAAAA==.Carebeär:BAAANQADCgQIBAAAAA==.Cauldren:BAAANQADCggICwAAAA==.',
Ch='Chalice:BAAANQADCgUIBQAAAA==.Chay:BAAANQAECgIIAgAAAA==.Chaylin:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Chikage:BAAANQADCgIIAgAAAA==.Chillen:BAAANQADCggICAAAAA==.Chinofwin:BAAANQABCgIIAgAAAA==.Chivo:BAAANQADCgMIAwAAAA==.Chopu:BAAANQADCgcIDAAAAA==.Chuckspadina:BAAANQAECgQIBAAAAA==.Chuggin:BAAANQADCgMIAwAAAA==.Chyna:BAAANQADCgcIDAAAAA==.',
Ci='Cibø:BAAANQADCgYIBgAAAA==.Cilghalcao:BAAANQAECgIIAgAAAA==.Cirdae:BAAANQAECgMIAwAAAA==.',
Cl='Cleric:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Clõud:BAAANQADCgcIDAAAAA==.',
Co='Cococolalaw:BAAANQADCgEIAQAAAA==.Conc:BAAANQAECgMIAwAAAA==.',
Cp='Cpthardfap:BAAANQAECgQIBQAAAA==.',
Cr='Crazynip:BAAANQAECgYIBgAAAA==.Crickit:BAAANQADCggIDAAAAA==.Cryavus:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Crylucis:BAAANQAECgMIAwAAAA==.Crypticál:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
Cu='Cujo:BAAANQAECgMIAwAAAA==.',
Cy='Cyanidesun:BAAANQADCgcICAAAAA==.Cybre:BAAANQADCgYICwAAAA==.Cyndaquill:BAAANQADCgEIAQAAAA==.Cyndil:BAAANQAECgEIAQAAAA==.Cysora:BAAANQADCgYICgAAAA==.',
['Cä']='Cästiel:BAAANQADCggIDAAAAA==.',
Da='Daesyn:BAAANQABCgEIAQAAAA==.Dallei:BAAANQADCgYICgAAAA==.Danbearpig:BAAANQABCgQIBAAAAA==.Dandish:BAAANQADCggIDAAAAA==.Darcane:BAAANQAECgQIBQAAAA==.Darkvayne:BAAANQADCgcIDAAAAA==.Dathrel:BAAANQADCgUIBQAAAA==.',
De='Deathpig:BAAANQADCggIAgAAAA==.Deezaster:BAAANQADCgUIBQAAAA==.Def:BAAANQAECgQIBAAAAA==.Delani:BAAANQAECgEIAQAAAA==.Deltaco:BAAANQADCgQIBQAAAA==.Dementis:BAAANQADCgUIBwAAAA==.Demonnova:BAAANQAECgcIDQAAAA==.Dezsp:BAAANQAFFAIIAgAAAA==.',
Dg='Dghunter:BAAANQAECgQIBgAAAA==.',
Do='Docsored:BAAANQADCgYIBgAAAA==.Dontholdback:BAAANQADCgUIBQAAAA==.Donuts:BAAANQADCggIDAAAAA==.',
Dr='Dragn:BAAANQADCgIIAgAAAA==.Dragnas:BAAANQAECgQIBAAAAA==.Dragniperake:BAAANQADCggIDQAAAA==.Drdots:BAAANQAECgEIAQAAAA==.Dreamhc:BAAANQAECgMIAwAAAA==.Dresperea:BAAANQADCgUIBQAAAA==.Drugral:BAAANQAECgQIBQAAAA==.',
Du='Dugronn:BAAANQADCgYICwAAAA==.',
Dw='Dwarfvadar:BAAANQADCgUIBQAAAA==.',
Ea='Eadric:BAAANQADCgQIBAAAAA==.',
El='Elanthemage:BAAANQADCgcIDQAAAA==.Eleison:BAAANQAECgcIDAAAAA==.Ellairis:BAAANQADCgcICQAAAA==.Ellesperis:BAAANQADCggICAAAAA==.Elyana:BAAANQADCgYICwAAAA==.',
Er='Eragôn:BAAANQADCgcIDQAAAA==.Erinyes:BAAANQAECgMIAwAAAA==.',
Es='Estee:BAAANQADCgUIBQAAAA==.',
Et='Ethyl:BAAANQADCgEIAQAAAA==.',
Ex='Exarkune:BAAANQADCgYIBgAAAA==.Executioner:BAAANQADCggICwAAAA==.',
Fa='Fatfish:BAAANQADCggIAgAAAA==.Fatty:BAAANQAECgMIAwAAAA==.',
Fe='Fenja:BAAANQAECgQIBAAAAA==.Feul:BAABNQAECoEZAAIDAAgJtRymBgCrAgADAAgJtRymBgCrAgAAAA==.Feyded:BAAANQADCgcIDQAAAA==.Feylis:BAAANQADCgUIBQABNQADCggIDQABAAAAAA==.',
Fh='Fhara:BAAANQADCgEIAQAAAA==.',
Fi='Fiasko:BAAANQAECgQIBgAAAA==.Firehose:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Fl='Flowerpower:BAAANQAECgMIAwAAAA==.Fluffythecup:BAAANQADCgcIDQAAAA==.',
Fm='Fmliplaygoat:BAAANQADCgcIDQAAAA==.',
Fo='Formidonis:BAAANQAECgUIBwAAAA==.Foxyboo:BAAANQADCgYICwAAAA==.',
Fr='Frostyna:BAAANQAECgQIBgAAAA==.',
Fu='Fubber:BAAANQAECgQIBQAAAA==.Fulgur:BAAANQADCggIDAAAAA==.Funsizegurly:BAAANQAECgMIAwAAAA==.',
Ga='Gallypotter:BAAANQAECgQIBwAAAA==.Garygabagool:BAAANQAECgQIBAAAAA==.Gawdshamit:BAAANQADCgcICgAAAA==.Gawdspet:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.',
Ge='Geoffreey:BAAANQADCgYICwAAAA==.',
Gh='Ghakk:BAAANQADCgIIAgAAAA==.Ghostorc:BAAANQAECgEIAQAAAA==.',
Gi='Giegs:BAAANQAECgMIAwAAAA==.',
Gl='Glockcoma:BAAANQADCgUIBAAAAA==.',
Gn='Gnatytoop:BAAANQAECgMIAwAAAA==.Gnawrly:BAAANQAECgEIAQAAAA==.',
Go='Gonzo:BAAANQADCgcICwAAAA==.Goodgirl:BAAANQAECgQIBAABNQAECgYIBgABAAAAAA==.Goodgurl:BAAANQAECgYIBgAAAA==.Govrek:BAAANQAECgEIAQAAAA==.',
Gr='Greenstone:BAAANQADCgEIAQAAAA==.Gricavent:BAAANQADCgEIAQAAAA==.Grobyc:BAAANQADCgMIBAAAAA==.Grïm:BAAANQAECgIIAgAAAA==.',
Gt='Gtfobubble:BAAANQADCgEIAQAAAA==.Gtfolava:BAAANQADCgYICQAAAA==.',
Gu='Guldont:BAAANQADCgQIBgAAAA==.',
Ha='Hankopher:BAAANQAECgQIBgAAAA==.Hanziè:BAAANQADCgYICgAAAA==.Haptics:BAAANQAECgEIAgAAAA==.Harbinger:BAAANQADCgMIAwAAAA==.Harmonix:BAAANQAECgEIAQAAAA==.',
He='Heaf:BAAANQADCggIDwAAAA==.Hecateis:BAAANQADCgYICAAAAA==.Heenan:BAAANQADCggIDgAAAA==.Hellhaunt:BAAANQADCgIIAgAAAA==.Hellstar:BAAANQADCgUIBQAAAA==.Hemdh:BAAANQADCggIDgABNQAECgcIDQABAAAAAA==.Herukas:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Hexsteele:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.',
Ho='Holdmybear:BAAANQAECgEIAQAAAA==.Holyfudge:BAAANQADCgYICgABNQAECgQIBAABAAAAAA==.Holyhyper:BAAANQAECgUIBwAAAA==.Holywaddles:BAAANQADCgIIAgAAAA==.',
Hr='Hrinnu:BAAANQAECgEIAQAAAA==.',
Ht='Htownshawdo:BAAANQADCgYICgAAAA==.',
Hu='Huntardftw:BAAANQADCgQIAgAAAA==.Huntwick:BAAANQADCgcIDAAAAA==.Hurkaj:BAAANQAECgEIAQAAAA==.',
Ic='Icanhealyou:BAAANQAECgQIBAAAAA==.',
Ih='Ihatepriests:BAAANQADCggIDgAAAA==.',
In='Incisor:BAAANQADCgYIBgAAAA==.Incline:BAAANQADCgUIBQAAAA==.Inoo:BAAANQAECgIIAgAAAA==.',
Ir='Irishhammer:BAAANQADCgcIDQAAAA==.',
Is='Isvnpcdhg:BAAANQAECgEIAQAAAA==.',
It='Itkovien:BAAANQADCgMIAwAAAA==.',
['Iá']='Ián:BAAANQAECgMIAwAAAA==.',
Ja='Janq:BAAANQAECgUIBQAAAA==.',
Je='Jerrodsmage:BAAANQADCgUIBQAAAA==.Jezbrez:BAAANQAECgQIBgAAAA==.',
Ji='Jinzu:BAAANQAECgIIAgAAAA==.Jizzledizzle:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.',
Jp='Jphlip:BAAANQAECgMIBAAAAA==.Jpmagi:BAAANQAECgUIBwAAAA==.',
Ju='Juice:BAAANQADCgUIBQAAAA==.Juisi:BAAANQAECgQIBAAAAA==.',
['Jô']='Jô:BAAANQADCgUIBAAAAA==.',
Ka='Kaeloth:BAAANQAECgEIAQAAAA==.Kagayoshi:BAAANQADCgIIAgAAAA==.Kainen:BAAANQABCgQIBAAAAA==.Kalebmonk:BAAANQADCgYIBwABNQAECgQIBgABAAAAAA==.Kalebpal:BAAANQAECgQIBgAAAA==.Kamtano:BAAANQADCgcIDQAAAA==.Kavaliro:BAAANQADCgMIAwAAAA==.Kayaanu:BAAANQAECgMIAwAAAA==.Kazimiraci:BAAANQADCggICAAAAA==.',
Ki='Kickya:BAAANQABCgEIAQAAAA==.Kidkill:BAAANQADCgIIAgAAAA==.Killstar:BAAANQADCgQIBAABNQADCgUIBwABAAAAAA==.Kindeesver:BAAANQADCgMIAwAAAA==.Kirke:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Kisara:BAAANQADCgIIAgABNQADCggIDgABAAAAAA==.',
Kl='Kletas:BAAANQAECgUIBQAAAA==.Kletus:BAAANQADCgYIBgAAAA==.',
Kn='Knokkpriest:BAAANQAECgMIAwAAAA==.',
Ko='Kobs:BAAANQADCgUIBQAAAA==.Kopy:BAAANQAECgUIBwAAAA==.Korvash:BAAANQADCgYIBgAAAA==.',
Kr='Kromgol:BAAANQADCgYICQAAAA==.',
Ku='Kujaku:BAAANQADCgcIDQAAAA==.',
Kw='Kwende:BAAANQADCgYICwAAAA==.',
Ky='Kyela:BAAANQADCgcIDQAAAA==.Kyrtion:BAAANQAECgQIBQAAAA==.',
['Kø']='Kørupted:BAAANQADCgcIDQAAAA==.',
La='Lamiisa:BAAANQADCggICwAAAA==.Lanaris:BAAANQADCgYIBgAAAA==.Laurandrel:BAAANQADCgcICwAAAA==.Laved:BAAANQAECgMIAwAAAA==.Lawgi:BAAANQAECgQIBAAAAA==.',
Ld='Ldkils:BAAANQADCgIIAgAAAA==.Ldlockem:BAAANQAECgEIAQAAAA==.',
Li='Lilitü:BAAANQADCggICQAAAA==.Lilwascal:BAAANQADCgUIBgAAAA==.Lilya:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Linatheslayr:BAAANQADCgUIBQAAAA==.Linossa:BAAANQAECgIIAgAAAA==.',
Ll='Llonso:BAAANQADCgUIBQAAAA==.',
Lo='Lookiezi:BAAANQAECgMICAAAAA==.Lovemuffîn:BAAANQADCgcICQAAAA==.',
Lu='Lucidonis:BAAANQADCgcIDQAAAA==.Luminaconri:BAAANQADCgEIAQAAAA==.',
Ly='Lystia:BAAANQADCgYICAAAAA==.',
['Læ']='Læncelot:BAAANQADCgUIBQAAAA==.',
Ma='Madriel:BAAANQADCgUIBQAAAA==.Magento:BAAANQAECgUIBwAAAA==.Maladie:BAAANQAECgMIBAAAAA==.Malvaron:BAAANQADCgUIBQAAAA==.Mavzy:BAAANQAECgQIBgAAAA==.',
Mc='Mcbubbies:BAAANQAECgEIAQAAAA==.Mcfknkfc:BAAANQADCggIDQAAAA==.',
Me='Meeyo:BAAANQADCgEIAQAAAA==.Megamanmeat:BAAANQADCggIEAAAAA==.',
Mi='Micti:BAAANQAECgIIAgAAAA==.Milamber:BAAANQADCggIEAAAAA==.Minyon:BAAANQAECgQIBgAAAA==.Miruna:BAAANQADCgMIAwAAAA==.',
Mo='Mommadragon:BAAANQADCgYICQAAAA==.Monsterflexx:BAAANQAECgMIAwAAAA==.Moosè:BAAANQADCgYICgAAAA==.',
Mu='Mugron:BAAANQADCggICgABNQAFFAEIAQABAAAAAA==.',
My='Mydkfelloff:BAAANQADCggICAAAAA==.Myronath:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Mystafire:BAAANQADCgIIAgAAAA==.Mythpriest:BAAANQAECgIIAgAAAA==.',
Na='Nadlug:BAAANQADCgYIDAAAAA==.Naki:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.Naljubuites:BAAANQABCgIIBAAAAA==.',
Ne='Neebstrasza:BAAANQADCgIIAgAAAA==.Newdamda:BAAANQADCgcIDQAAAA==.',
Ni='Nicolius:BAAANQAECgQIBgAAAA==.Ningenalah:BAAANQAECgQIBgAAAA==.Nippÿ:BAAANQAECgQIBgAAAA==.',
No='Norav:BAAANQAECgEIAQAAAA==.Nordryde:BAAANQAECgcIDAAAAA==.Notfrïendly:BAAANQADCgIIAgAAAA==.',
Of='Offensive:BAAANQAECgQIBAAAAA==.',
Ol='Olayhahla:BAAANQAECgIIAgAAAA==.',
Op='Opalausia:BAAANQADCgYIBgAAAA==.',
Or='Oregano:BAAANQAECgUIBwAAAA==.',
Ou='Ourania:BAAANQADCgEIAQAAAA==.',
Pa='Padreberk:BAAANQADCgYIBgAAAA==.Painremains:BAAANQADCgUIBQAAAA==.Pantyfa:BAAANQADCgIIAwAAAA==.',
Pe='Pekkie:BAAANQADCgcIDAAAAA==.Penthesilea:BAAANQAECgEIAQAAAA==.Pestcontrol:BAAANQADCggIDgAAAA==.',
Ph='Phallon:BAAANQADCgcIDAAAAA==.',
Pi='Pioree:BAAANQAECgUICQAAAA==.',
Po='Ponglenis:BAAANQADCggICAAAAA==.Poonany:BAAANQAECgEIAQAAAA==.',
Pr='Prandal:BAAANQAECgEIAQAAAA==.Pregzuel:BAAANQADCgUIBgAAAA==.Projecthorde:BAAANQAECgMIAwAAAA==.',
Py='Pyroganus:BAAANQADCgYIBgAAAA==.',
Qu='Quanzanon:BAAANQAECgIIAgAAAA==.Quizhik:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
Ra='Rachelrae:BAAANQAECgQIBAAAAA==.Ralphy:BAAANQADCggIDwAAAA==.Ramenwrapz:BAAANQADCgcICwAAAA==.Raryees:BAAANQAECgMIAwAAAA==.',
Re='Reddynon:BAAANQADCggIEAAAAA==.Reginald:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Relin:BAAANQAECgUIBwAAAA==.Relinbear:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.Relse:BAAANQADCgEIAQAAAA==.Renika:BAAANQAECgEIAgAAAA==.Renmazuo:BAAANQAECgMIAwAAAA==.Renrax:BAAANQADCgYICgAAAA==.Resperea:BAAANQADCggICwAAAA==.Revwild:BAAANQADCgYIDAAAAA==.',
Ri='Ricassou:BAAANQADCggIDgAAAA==.Rivendell:BAAANQAECgEIAgAAAA==.',
Ro='Roonkmc:BAAANQADCgQIBQABNQADCgEIAQABAAAAAA==.Rorynne:BAAANQADCgYIDAAAAA==.',
Rr='Rrubio:BAAANQADCgcIBwAAAA==.',
Ru='Ruend:BAAANQADCgYIBgAAAA==.',
Ry='Ryndkmc:BAAANQADCggICAABNQADCgEIAQABAAAAAA==.Ryuujin:BAAANQADCgQIBAAAAA==.',
['Ré']='Réflex:BAAANQADCgQIBgAAAA==.Réfléx:BAAANQAECgEIAQAAAA==.',
['Ró']='Ródin:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.',
Sa='Saeya:BAAANQADCgMIBAAAAA==.Sakurai:BAAANQADCgcIDQAAAA==.Salorllis:BAAANQADCgYIBgAAAA==.Saristia:BAAANQADCgcIDQAAAA==.Saveu:BAAANQAECgIIAgAAAA==.',
Sc='Screampies:BAAANQADCgcIDgAAAA==.',
Se='Seagulls:BAEANQADCggIDgAAAA==.Seayaa:BAAANQADCgcIDQAAAA==.Seiryu:BAAANQADCgIIAgAAAA==.Selindia:BAAANQADCgcIDQAAAA==.Sellsword:BAAANQADCgMIAwAAAA==.',
Sf='Sfx:BAAANQADCgYIBgABNQAECgcIBwABAAAAAA==.',
Sg='Sgt:BAAANQADCgUICQAAAA==.',
Sh='Shadowydeath:BAAANQADCgYICQAAAA==.Shaedee:BAAANQAECgIIBAAAAA==.Shallon:BAAANQAECgYIDAAAAA==.Shammyshaga:BAAANQADCggIDgAAAA==.Shapest:BAAANQADCgQIBAAAAA==.Shelby:BAAANQADCgUIBQAAAA==.Shilihu:BAAANQADCgcICAAAAA==.Shinukishin:BAAANQAECgEIAQAAAA==.Shorzy:BAAANQADCggIEAAAAA==.Shredzdh:BAAANQADCgcIDQAAAA==.',
Si='Sillybone:BAAANQADCgEIAQAAAA==.Simulacra:BAAANQADCgYIBgAAAA==.Sitonmytotem:BAAANQADCgYIBgAAAA==.',
Sl='Sloppyblades:BAAANQABCgIIAgAAAA==.Slu:BAAANQAECgcIDQABNQAECgIIAgABAAAAAA==.',
Sm='Smashinsmith:BAAANQAECgIIAgAAAA==.Smorgasbord:BAAANQADCgYICgAAAA==.',
Sn='Snackpack:BAAANQAECgEIAQAAAA==.Snowblind:BAAANQADCgUIBQAAAA==.Snowdancer:BAAANQADCgQIBAAAAA==.',
So='Sokkmage:BAAANQADCgYIDAAAAA==.Solnar:BAAANQADCgYICwAAAA==.Somno:BAAANQAECgMIAwAAAA==.Soulfly:BAAANQADCgYICwAAAA==.Soulsabi:BAAANQAECgEIAQAAAA==.Soulshaper:BAAANQADCgYICgAAAA==.',
Sp='Spectral:BAAANQAECgcIBwAAAA==.Spiritspawn:BAAANQAECgMIBAAAAA==.Spookyshark:BAAANQADCgIIAgAAAA==.Spoonman:BAAANQAECgEIAgAAAA==.Spåwnkîll:BAAANQADCgUIBQAAAA==.',
Sq='Squidheäd:BAAANQABCgQIBAAAAA==.',
St='Stardrift:BAAANQADCggIDAAAAA==.Stere:BAAANQAECgEIAgAAAA==.Stormhoff:BAAANQADCggICAAAAA==.Stormhuff:BAAANQADCgUIBQAAAA==.Stärkiller:BAAANQADCgEIAQAAAA==.',
Su='Sunderance:BAAANQADCgMIAwAAAA==.Superhilock:BAAANQAECgQIBQAAAA==.Supplesuckle:BAAANQABCgIIAgABNQADCgcIDgABAAAAAA==.',
Sv='Svelesstiá:BAAANQADCgEIAQAAAA==.',
Sy='Sybrand:BAAANQAECgMIAwAAAA==.Syrelliia:BAAANQAECgQIBQAAAA==.Syrenia:BAAANQABCgEIAQAAAA==.',
['Sæ']='Sævage:BAAANQAECgEIAQAAAA==.',
['Sø']='Sørta:BAAANQADCgcIDQAAAA==.',
Ta='Tae:BAAANQADCgMIAwAAAA==.Taigun:BAAANQADCgcIDQAAAA==.Tarnac:BAAANQADCgYIBwAAAA==.Tazorface:BAAANQAECgEIAQAAAA==.',
Te='Terkey:BAAANQAECgUIBQABNQAECgYICAABAAAAAA==.',
Th='Tharkash:BAAANQADCgcIEgAAAA==.Thedockwho:BAAANQADCgcIDAAAAA==.Theliarcy:BAAANQADCgEIAQAAAA==.Thesaint:BAAANQADCgQIBAAAAA==.Thirdeye:BAAANQAECgMIAwAAAA==.Thoxic:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Thunderbuns:BAAANQADCggICAAAAA==.Thundrcat:BAAANQADCgEIAQAAAA==.',
Ti='Tipz:BAAANQAECgEIAQAAAA==.Tiras:BAAANQADCgEIAQAAAA==.',
To='Toolip:BAAANQADCggIEAAAAA==.Tornwraith:BAAANQADCgYICQAAAA==.Towel:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
Tr='Traumasdruid:BAAANQADCggIDQAAAA==.Traviana:BAAANQADCgIIAwAAAA==.Trehuga:BAAANQAECgQIBgAAAA==.Trikky:BAAANQADCgYICQAAAA==.Triso:BAAANQAECgIIAgAAAA==.Tronus:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Ts='Tsukaar:BAAANQAECgQIBAAAAA==.',
Tu='Tutorialboss:BAAANQAFFAEIAQAAAA==.',
Tw='Twohorns:BAAANQAECgQIBQAAAA==.',
['Tö']='Töterfrieren:BAAANQADCggIDgAAAA==.',
Ul='Ulrika:BAAANQADCgYIBgAAAA==.Ultrön:BAAANQADCgIIAgAAAA==.',
Um='Umbryelle:BAAANQADCgcICAAAAA==.',
Un='Undermaw:BAAANQAECgUIBwAAAA==.Unforgyven:BAAANQADCggIDAAAAA==.Unicron:BAAANQADCgUIBgAAAA==.',
Ur='Ursoulismine:BAAANQAECgEIAQAAAA==.',
Va='Valennah:BAAANQADCgYIBgAAAA==.Valgaar:BAAANQADCggIDQAAAA==.Vaneste:BAAANQAECgMIBAAAAA==.Vartlock:BAAANQAECgMIAwAAAA==.Vartrino:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Ve='Veganator:BAAANQAECgQIBAAAAA==.Veggies:BAAANQADCgYICgAAAA==.Velani:BAAANQADCggIDgAAAA==.Vendoralia:BAAANQABCgQIBgAAAA==.Verlant:BAAANQAECgEIAQAAAA==.',
Vi='Vitus:BAAANQADCgUIBQAAAA==.',
Vl='Vladriel:BAAANQADCgcIDAAAAA==.',
Wa='Waddlebottle:BAAANQADCgcIBwAAAA==.Wallock:BAAANQADCgIIAgAAAA==.Warrdruid:BAAANQADCgIIAgAAAA==.Watchnu:BAAANQADCggIEQAAAA==.',
Wh='Whimsy:BAAANQADCgUIBgAAAA==.Whät:BAAANQADCgcIDAAAAA==.',
Wi='Willowhite:BAAANQADCgcIDAAAAA==.',
Wo='Wockyslush:BAAANQADCgUIBQAAAA==.',
Wu='Wubwub:BAAANQADCggICAAAAA==.Wulfjin:BAAANQAECgIIAgAAAA==.',
Xa='Xalia:BAAANQADCgQIBQAAAA==.',
Xe='Xellie:BAAANQADCgUIBgAAAA==.',
['Xë']='Xërík:BAAANQADCgYICgAAAA==.',
Yo='Yopan:BAAANQADCgYICAAAAA==.',
['Yå']='Yåmatohime:BAAANQADCgUIBQABNQADCgcIDAABAAAAAA==.',
Za='Zappymczaps:BAAANQADCgIIAgAAAA==.Zaremis:BAAANQAECgUIBwAAAA==.Zayehuo:BAAANQADCgUICAAAAA==.',
Ze='Zelphie:BAAANQAECgEIAQAAAA==.Zemmy:BAAANQADCgIIAgAAAA==.Zent:BAAANQAECgEIAQAAAA==.Zenus:BAAANQADCggIDQAAAA==.Zenveyra:BAAANQADCgEIAQAAAA==.Zerase:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.Zerttrak:BAAANQAECgQIBAAAAA==.',
Zi='Zilong:BAAANQADCggICAAAAA==.Zitania:BAAANQADCgcICgAAAA==.',
Zu='Zugma:BAAANQAECgYICQAAAA==.',
['Çh']='Çhristopher:BAAANQADCgYICgAAAA==.',
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
