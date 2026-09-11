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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Shaman-Restoration','Rogue-Assassination','Shaman-Elemental','DeathKnight-Blood','Mage-Arcane','Hunter-Marksmanship','Hunter-BeastMastery',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaluah:BAAANQADCgcICgAAAA==.',
Ac='Acmis:BAAANQADCgYIEAABNQADCgcIDQABAAAAAA==.Acp:BAAANQAECgMIAwAAAA==.',
Ad='Adomangma:BAAANQABCgQIBAAAAA==.',
Ah='Ahjumma:BAAANQAECgUICAAAAA==.',
Ai='Ailskush:BAAANQAECgIIAwAAAA==.',
Ak='Akun:BAAANQADCgYIBgABNQADCggIFQABAAAAAA==.Akurantirea:BAAANQADCggIFQAAAA==.',
Al='Algerax:BAAANQAECgEIAQAAAA==.Allise:BAAANQADCgcIEgAAAA==.Alphamaled:BAAANQAECgYIBwAAAA==.Alva:BAAANQADCgIIAgAAAA==.Aléthia:BAAANQAECgEIAQAAAA==.',
An='Anathemá:BAAANQADCgUIBQAAAA==.Ange:BAAANQADCggIEAAAAA==.',
Ap='Apawpriest:BAAANQAECgUIBwAAAA==.',
Ar='Arke:BAAANQADCgIIAgAAAA==.Arraeroda:BAAANQADCgcIDQAAAA==.',
As='Astela:BAAANQAECgEIAQAAAA==.',
Au='Aumtatsat:BAAANQAECgUICQAAAA==.Autumn:BAAANQAECgMIBAAAAA==.',
Av='Avatan:BAAANQAECgQIBQAAAA==.Avedeath:BAAANQADCggIEQAAAA==.Aveena:BAAANQADCgMIAwAAAA==.',
Ay='Ayara:BAABNQAECoEpAAICAAgJkCMvBQBAAwACAAgJkCMvBQBAAwAAAA==.Ayrad:BAAANQADCgQIBAAAAA==.',
Ba='Badderdragon:BAAANQAECgYICwAAAA==.Badmrmittens:BAAANQADCggICAAAAA==.Badmuffin:BAAANQADCgcIDQAAAA==.Bahkita:BAAANQAECgQIBAAAAA==.Bakatran:BAAANQADCgMIBAAAAA==.Balamuth:BAAANQADCgYIBgAAAA==.Bandrui:BAAANQADCgYICgAAAA==.',
Be='Bearlygrillz:BAAANQADCggICwAAAA==.Berkstein:BAAANQADCgcIDQAAAA==.',
Bi='Bigcai:BAAANQADCgYIBgAAAA==.Biggisnicker:BAAANQAECgQICAAAAA==.Bigspriesty:BAAANQADCggIDQAAAA==.Bigtone:BAAANQAECgMIBAAAAA==.Bimbomz:BAAANQAECgMIBwAAAA==.Biochemist:BAAANQADCgMIBAABNQAECgYIBgABAAAAAA==.Bioengineer:BAAANQADCgYIBgABNQAECgYIBgABAAAAAA==.Biogenic:BAAANQAECgYIBgAAAA==.Biomass:BAAANQADCgcICAABNQAECgYIBgABAAAAAA==.Birdbrain:BAAANQAECgYICwAAAA==.',
Bl='Blewîsa:BAAANQADCgMIAwAAAA==.',
Bo='Boodylicious:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Borucmonk:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Borucwar:BAAANQAECgEIAQAAAA==.',
Br='Braedia:BAAANQADCgYIDwAAAA==.Brassticus:BAAANQADCgcIBwAAAA==.Brawrski:BAAANQADCgUIBwABNQADCgYIBgABAAAAAA==.Briele:BAAANQAECgEIAQAAAA==.Brise:BAAANQADCggICAAAAA==.Brosabi:BAAANQAECgUICQABNQAECgIIAwABAAAAAA==.Brucewaynexb:BAAANQABCgIIAgAAAA==.',
Bu='Bubs:BAAANQAECgQICAAAAA==.Buddhïst:BAAANQAECgcIBwAAAA==.',
['Bí']='Bítten:BAAANQAECgQIBAAAAA==.',
Ca='Cakesinatra:BAAANQADCggIDQABNQAECgIIAgABAAAAAA==.Cakewastaken:BAAANQAECgIIAgAAAA==.Cakke:BAAANQADCgUIBgAAAA==.Calkestis:BAAANQADCgMIAwAAAA==.Candre:BAAANQAECgUICAAAAA==.Candyears:BAAANQADCgIIAgAAAA==.Capii:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Capristal:BAAANQAECgIIAgAAAA==.Carebeär:BAAANQADCgQIBAAAAA==.Caròl:BAAANQADCgUIBQAAAA==.Cassiera:BAAANQAECgUICAAAAA==.Cauldren:BAAANQADCggIEwAAAA==.',
Ch='Chalice:BAAANQADCgYICwAAAA==.Charkycc:BAAANQADCgMIAwAAAA==.Chay:BAAANQAECgMIBQAAAA==.Chaylin:BAAANQADCgcICAABNQAECgMIBQABAAAAAA==.Chikage:BAAANQADCgIIAgAAAA==.Chillzen:BAAANQABCgUIBQAAAA==.Chinofwin:BAAANQABCgIIAgAAAA==.Chivo:BAAANQADCgYICQAAAA==.Chopu:BAAANQAECgIIAgAAAA==.Chuckspadina:BAAANQAECgYICgAAAA==.Chuggin:BAAANQADCgMIAwAAAA==.Chyna:BAAANQADCgcIDAAAAA==.',
Ci='Cibø:BAAANQADCgcIDAAAAA==.Cilghalcao:BAAANQAECgIIAgAAAA==.Cirdae:BAAANQAECgQIBwAAAA==.',
Cl='Cleric:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Clõud:BAAANQAECgEIAQAAAA==.',
Co='Cococolalaw:BAAANQADCgEIAQAAAA==.Coggknocker:BAAANQABCgMIAwAAAA==.Coldsnaps:BAAANQADCgYIBgAAAA==.Conc:BAAANQAECgYICQAAAA==.Cormac:BAAANQADCggICAAAAA==.',
Cp='Cpthardfap:BAAANQAECgQIBQAAAA==.',
Cr='Crazynip:BAAANQAECgYICwAAAA==.Crickit:BAAANQADCggIFAAAAA==.Crispr:BAAANQADCgQIBAAAAA==.Cryavus:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Crylucis:BAAANQAECgYICQAAAA==.Crypticál:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.',
Cu='Cujo:BAAANQAECgYICQAAAA==.',
Cy='Cyanidesun:BAAANQADCgcICAAAAA==.Cybre:BAAANQADCgcIEgAAAA==.Cyndil:BAAANQAECgEIAgAAAA==.Cysora:BAAANQADCgYIEAAAAA==.',
['Cä']='Cästiel:BAAANQAECgIIAgAAAA==.',
Da='Daesyn:BAAANQABCgMIBAAAAA==.Dallei:BAAANQAECgEIAQAAAA==.Danbearpig:BAAANQABCgQIBAAAAA==.Dandish:BAAANQAECgQIBAAAAA==.Darcane:BAAANQAECgYICwAAAA==.Darkvayne:BAAANQAECgIIAgAAAA==.Darrington:BAAANQAECgEIAQAAAA==.Dathrel:BAAANQADCgYIBgAAAA==.Dawnfather:BAAANQABCgYIBwAAAA==.',
De='Deathpig:BAAANQADCggIAgAAAA==.Deezaster:BAAANQAECgEIAQAAAA==.Def:BAAANQAECgcICwAAAA==.Delani:BAAANQAECgEIAQAAAA==.Deltaco:BAAANQADCgYICwAAAA==.Dementis:BAAANQADCgUIBwAAAA==.Demonnova:BAABNQAECoEXAAMCAAkJ9BvWCgDHAgACAAgJ9x3WCgDHAgADAAIJ5QfvLACGAAAAAA==.Dendude:BAAANQABCgEIAQAAAA==.Devinity:BAAANQADCgUIBQAAAA==.Dezsp:BAACNQAFFIEHAAIEAAUJah5jAAD3AQAEAAUJah5jAAD3AQA1AAQKgRkAAgQACQkgJOsAAMQDAAQACQkgJOsAAMQDAAAA.',
Dg='Dghunter:BAAANQAECgUICwAAAA==.',
Di='Dietrinea:BAAANQADCgIIAgAAAA==.',
Do='Docsored:BAAANQADCggIDgAAAA==.Dontholdback:BAAANQADCgUIBQAAAA==.Donuts:BAAANQADCggIFAAAAA==.Doomchick:BAAANQABCgYICAAAAA==.',
Dr='Dragn:BAAANQADCgQIBgAAAA==.Dragnas:BAAANQAECgYICgAAAA==.Dragniperake:BAAANQAECgQIBAAAAA==.Drbug:BAAANQAECgIIAgABNQAECgcICQABAAAAAA==.Drdots:BAAANQAECgUIBgAAAA==.Dreadnaunt:BAAANQADCggICAAAAA==.Dreamhc:BAAANQAECgYICQAAAA==.Dresperea:BAAANQADCgUIBQAAAA==.Drugral:BAAANQAECgYICwAAAA==.',
Du='Dugronn:BAAANQADCggIEwAAAA==.',
Dw='Dwarfvadar:BAAANQAECgIIAgAAAA==.',
Ea='Eadric:BAAANQADCgUIBQAAAA==.',
El='Elanthemage:BAAANQADCgcIDQAAAA==.Eleison:BAAANQAFFAIIAgAAAA==.Ellairis:BAAANQAECgIIAgAAAA==.Ellesperis:BAAANQADCggIDwAAAA==.Ellumon:BAAANQAECgEIAQAAAA==.Elyana:BAAANQADCgYIEQAAAA==.',
Em='Emergnc:BAAANQADCgQIBAAAAA==.',
Er='Eragôn:BAAANQAECgIIAgAAAA==.Erinyes:BAAANQAECgQIBwAAAA==.',
Es='Estee:BAAANQAECgIIAgAAAA==.',
Et='Ethyl:BAAANQADCgEIAQAAAA==.',
Ex='Exarkune:BAAANQADCgYIBgAAAA==.Executioner:BAAANQAECgEIAQAAAA==.',
Fa='Fatfish:BAAANQADCggIAgAAAA==.Fatty:BAAANQAECgQIBwAAAA==.',
Fe='Fenja:BAAANQAECgYICgAAAA==.Feul:BAABNQAECoEpAAIFAAgJPx3dDwCaAgAFAAgJPx3dDwCaAgAAAA==.Feyded:BAAANQADCgcIDQAAAA==.Feylis:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Fh='Fhara:BAAANQADCgUIBgAAAA==.',
Fi='Fiasko:BAAANQAECgUICwAAAA==.Fiir:BAAANQADCgYIBgAAAA==.Firehose:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.',
Fl='Flippÿ:BAAANQAECgEIAQAAAA==.Flowerpower:BAAANQAECgMIAwAAAA==.Fluffythecup:BAAANQADCgcIDQAAAA==.',
Fm='Fmliplaygoat:BAAANQAECgQIBAAAAA==.',
Fo='Foreverdead:BAAANQADCgEIAQAAAA==.Formidonis:BAAANQAECgYIDQAAAA==.Foxyboo:BAAANQADCgYICwAAAA==.',
Fr='Frostlady:BAAANQADCgUIBQAAAA==.Frostyna:BAAANQAECgUICwAAAA==.',
Fu='Fubber:BAAANQAECgQICQAAAA==.Fulgur:BAAANQAECgEIAQAAAA==.Funsizegurly:BAAANQAECgUICAAAAA==.',
Ga='Gallypotter:BAAANQAECgUIDAAAAA==.Garygabagool:BAAANQAECgYICgAAAA==.Gawdshamit:BAAANQAECgIIAgAAAA==.Gawdspet:BAAANQAECgEIAQABNQAECggIEQABAAAAAA==.',
Ge='Gemcutter:BAAANQADCgEIAQAAAA==.Geoffreey:BAAANQADCgcIDAAAAA==.',
Gh='Ghakk:BAAANQADCgIIAgAAAA==.Ghostmane:BAAANQABCgYICQAAAA==.Ghostorc:BAAANQAECgQIBQAAAA==.',
Gi='Giegs:BAAANQAECgQIBQAAAA==.',
Gl='Glockcoma:BAAANQADCgUIBAAAAA==.',
Gn='Gnatytoop:BAAANQAECgUICAAAAA==.Gnawrly:BAAANQAECgQIBQAAAA==.',
Go='Gonzo:BAAANQAECgYIBgAAAA==.Goodgirl:BAAANQAECgQIBgABNQAECgcICQABAAAAAA==.Goodgurl:BAAANQAECgcICQAAAA==.Govrek:BAAANQAECgEIAQAAAA==.',
Gr='Greenstone:BAAANQADCgMIAwAAAA==.Gricavent:BAAANQAECgQIBAAAAA==.Grobyc:BAAANQADCgMIBAAAAA==.Grïm:BAAANQAECgUIBwAAAA==.',
Gt='Gtfolava:BAAANQADCgYICQAAAA==.',
Gu='Guldont:BAAANQADCgYIDAAAAA==.',
Ha='Hankering:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Hankopher:BAAANQAECgUICwAAAA==.Hanziè:BAAANQADCggIEgAAAA==.Haptics:BAAANQAECgYICAAAAA==.Harbinger:BAAANQADCgMIAwAAAA==.Harmonix:BAAANQAECgEIAQAAAA==.Hatzel:BAAANQAECgYIBgAAAA==.',
He='Heaf:BAAANQAECgEIAQAAAA==.Hecateis:BAAANQADCgYIDgAAAA==.Heenan:BAAANQAECgEIAQAAAA==.Hellhaunt:BAAANQADCgIIAgAAAA==.Hellstar:BAAANQADCgUIBQAAAA==.Hemdh:BAAANQADCggIDgABNQAECgkJGAAGAP0jAA==.Herukas:BAAANQAECgQIBAAAAA==.Hexsteele:BAAANQAECgEIAQABNQAECgkJGAAHAB4kAA==.',
Hi='Hitdeath:BAAANQADCgYIBgAAAA==.',
Ho='Hohiro:BAAANQADCgcIDgAAAA==.Holdmybear:BAAANQAECgEIAQAAAA==.Holyfudge:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Holyhyper:BAAANQAECgYIDQAAAA==.Holywaddles:BAAANQADCgQIBgAAAA==.',
Hr='Hrinnu:BAAANQAECgMIBQAAAA==.',
Ht='Htownshawdo:BAAANQAECgEIAQAAAA==.',
Hu='Huntardftw:BAAANQADCgQIAgAAAA==.Huntwick:BAAANQAECgMIAwAAAA==.Hurkaj:BAAANQAECgEIAQAAAA==.',
['Hü']='Hünterrific:BAAANQADCgIIAgAAAA==.',
Ic='Icanhealyou:BAAANQAECgYICgAAAA==.',
Ih='Ihatepriests:BAAANQAECgQIBAAAAA==.',
Il='Illusk:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.',
In='Incisor:BAAANQADCgYIBgAAAA==.Incline:BAAANQADCgUIBQAAAA==.Inoo:BAAANQAECgMIAwAAAA==.',
Ir='Irishhammer:BAAANQADCgcIDQAAAA==.',
Is='Isvnpcdhg:BAAANQAECgEIAgAAAA==.',
It='Itkovien:BAAANQADCgcICgAAAA==.',
['Iá']='Ián:BAAANQAECgUICAAAAA==.',
Ja='Janq:BAAANQAECgYICwAAAA==.Jayde:BAAANQADCgUIBQAAAA==.',
Je='Jerrodsmage:BAAANQADCgUIBQAAAA==.Jezbrez:BAAANQAECgQIBwAAAA==.',
Ji='Jinzu:BAAANQAECgYIDAAAAA==.Jizzledizzle:BAAANQADCgcIBwABNQADCggIFAABAAAAAA==.',
Jp='Jphlip:BAAANQAECgMIBwAAAA==.Jpmagi:BAAANQAECggIDwABNQABCgIIAgABAAAAAA==.',
Ju='Juice:BAAANQADCgcIDAAAAA==.Juisi:BAAANQAECgYICgAAAA==.Justania:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.',
['Jô']='Jô:BAAANQADCgcICwAAAA==.',
Ka='Kaeloth:BAAANQAECgUIBgAAAA==.Kagayoshi:BAAANQADCgIIAgAAAA==.Kainen:BAAANQABCgQIBgAAAA==.Kalebmonk:BAAANQADCgYIBwABNQAECgUICwABAAAAAA==.Kalebpal:BAAANQAECgUICwAAAA==.Kamtano:BAAANQADCgcIDQAAAA==.Kavaliro:BAAANQADCgMIAwAAAA==.Kayaane:BAAANQABCgYICAAAAA==.Kayaanu:BAAANQAECgUICAAAAA==.Kazimiraci:BAAANQADCggICAAAAA==.',
Ke='Kegsmasher:BAAANQADCggICAAAAA==.',
Kh='Khyzer:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.',
Ki='Kickya:BAAANQABCgEIAQAAAA==.Kidkill:BAAANQADCgIIAgAAAA==.Killaboy:BAAANQADCgEIAQAAAA==.Killstar:BAAANQADCgQIBAABNQADCgUIBwABAAAAAA==.Kindeesver:BAAANQADCgMIAwAAAA==.Kirke:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Kirriana:BAAANQAECgEIAQAAAA==.Kisara:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Kk='Kkitty:BAAANQADCgIIAgAAAA==.',
Kl='Kletas:BAAANQAECgUIBQAAAA==.Kletus:BAAANQADCgYICAAAAA==.',
Kn='Knokkpriest:BAAANQAECgQIBwAAAA==.',
Ko='Kobs:BAAANQADCgUIBQAAAA==.Kopy:BAAANQAECgUIDAAAAA==.Korvash:BAAANQAECgQIBAAAAA==.',
Kr='Kromgol:BAAANQAECgYIBwAAAA==.',
Ku='Kujaku:BAAANQADCgcIDQAAAA==.',
Kw='Kwende:BAAANQADCggIEwAAAA==.',
Ky='Kyela:BAAANQADCgcIDQAAAA==.Kyrtion:BAAANQAECgYICwAAAA==.',
['Kä']='Kätsuö:BAAANQADCgYIBgABNQADCggIFAABAAAAAA==.',
['Kø']='Kørupted:BAAANQADCgcIDQAAAA==.',
La='Lamiisa:BAAANQAECgMIBgAAAA==.Lanaris:BAAANQADCgYIDAAAAA==.Laurandrel:BAAANQADCgcIEgAAAA==.Laved:BAAANQAECgUICAAAAA==.Lawgi:BAAANQAECgYICgAAAA==.Lawliet:BAAANQABCgIIAgAAAA==.',
Ld='Ldkils:BAAANQADCgIIAgAAAA==.Ldlockem:BAAANQAECgQIBQAAAA==.',
Li='Lilitü:BAAANQADCggICQAAAA==.Lilshadow:BAAANQADCgEIAQAAAA==.Lilwascal:BAAANQADCgUICQAAAA==.Lilya:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Linatheslayr:BAAANQADCgUIBQAAAA==.Linossa:BAAANQAECgYIDAAAAA==.Lithiris:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.',
Ll='Llonso:BAAANQADCgUIBQAAAA==.',
Lo='Lockjam:BAAANQADCgEIAQAAAA==.Lookiezi:BAAANQAECgMICgAAAA==.Lovemuffîn:BAAANQAECgIIAgAAAA==.',
Lu='Lucidonis:BAAANQAECgIIAgAAAA==.Luminaconri:BAAANQADCgUIBgAAAA==.',
Ly='Lystia:BAAANQADCgYIDgAAAA==.',
['Læ']='Læncelot:BAAANQADCgUIBQAAAA==.',
Ma='Madriel:BAAANQAECgIIAgAAAA==.Mafanya:BAAANQABCgYICgAAAA==.Magento:BAAANQAECgYIDQAAAA==.Maladie:BAAANQAECgMIBwAAAA==.Malvaron:BAAANQADCgUIBQAAAA==.Mauna:BAAANQADCgcIBwAAAA==.Mavzy:BAAANQAECgQICgAAAA==.',
Mc='Mcbubbies:BAAANQAECgcICAAAAA==.Mcfknkfc:BAAANQADCggIEAAAAA==.',
Me='Meeyo:BAAANQADCgEIAQAAAA==.',
Mi='Micti:BAAANQAECgQIBgAAAA==.Milamber:BAAANQAECgQIBAAAAA==.Minyon:BAAANQAECgUICwAAAA==.Miruna:BAAANQADCgcICgAAAA==.',
Mo='Mogge:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Mommadragon:BAAANQADCgYICQAAAA==.Monsterflexx:BAAANQAECgQIBAAAAA==.Moosè:BAAANQADCgYIDwAAAA==.',
Mu='Mugron:BAAANQAECgcIBwABNQAECgkJGgAIABsjAA==.',
My='Mydkfelloff:BAAANQADCggICAAAAA==.Myronath:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Mystafire:BAAANQADCgYICAAAAA==.Mythpriest:BAAANQAECgIIAgAAAA==.',
Na='Nadlug:BAAANQADCgcIEwAAAA==.Naki:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.Naljubuites:BAAANQABCgQIBgAAAA==.Naradda:BAAANQADCgUIBQAAAA==.Nazra:BAAANQADCgMIAwAAAA==.',
Ne='Neebstrasza:BAAANQADCgIIAgAAAA==.Newdamda:BAAANQADCgcIEQAAAA==.',
Ni='Nicodormus:BAAANQAECgEIAQAAAA==.Nicolius:BAAANQAECgUICwAAAA==.Ningenalah:BAAANQAECgQICgAAAA==.Ningenurion:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.Nippÿ:BAAANQAECgUICwAAAA==.',
No='Norav:BAAANQAECgYIBwAAAA==.Nordryde:BAAANQAECgcIDAAAAA==.Nordrydm:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Notfrïendly:BAAANQADCgIIAgAAAA==.Novamortis:BAAANQADCgQIBAAAAA==.',
Of='Offensive:BAAANQAECgQIBAAAAA==.',
Ol='Olayhahla:BAAANQAECgQIBgAAAA==.',
Op='Opalausia:BAAANQADCgYIBgAAAA==.',
Or='Oregano:BAAANQAECgYIDQAAAA==.',
Ou='Ourania:BAAANQADCgEIAQAAAA==.',
Ov='Overkill:BAAANQABCgQIBAAAAA==.',
Pa='Padreberk:BAAANQADCgYIDAAAAA==.Painremains:BAAANQADCgcIDAAAAA==.Pantyfa:BAAANQADCgIIAwAAAA==.',
Pe='Pekkie:BAAANQADCggIFAAAAA==.Penthesilea:BAAANQAECgEIAQAAAA==.Perchance:BAAANQABCgIIAgAAAA==.Pestcontrol:BAAANQAECgEIAQAAAA==.',
Ph='Phallon:BAAANQAECgEIAQAAAA==.',
Pi='Pioree:BAAANQAECgcIEAAAAA==.',
Po='Ponglenis:BAAANQADCggICAAAAA==.Pookiebear:BAAANQADCgMIAwAAAA==.Poonany:BAAANQAECgEIAQAAAA==.Pootnuts:BAAANQADCgIIAgAAAA==.',
Pr='Prandal:BAAANQAECgEIAQAAAA==.Pregzuel:BAAANQADCgUIBgAAAA==.Projecthorde:BAAANQAECgUICAAAAA==.Pronouns:BAAANQADCgEIAQABNQAECgUIBgABAAAAAA==.',
Py='Pyroganus:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Qu='Quanzanon:BAAANQAECgUIBwAAAA==.Quizhik:BAAANQADCgYICQABNQAECgYICgABAAAAAA==.',
Ra='Rachelrae:BAAANQAECgYICgAAAA==.Radbrother:BAAANQABCgIIAgAAAA==.Ralphy:BAAANQAECgUIBQAAAA==.Ramenwrapz:BAAANQADCggIEgAAAA==.Raryees:BAAANQAECgUICQAAAA==.',
Re='Reddynon:BAAANQAECgQIBAAAAA==.Reginald:BAAANQADCgIIAgABNQADCggIFQABAAAAAA==.Relin:BAAANQAECgcIDQAAAA==.Relinbear:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.Relse:BAAANQADCgEIAQAAAA==.Renika:BAAANQAECgMIBAAAAA==.Renmazuo:BAAANQAECgcICgAAAA==.Renrax:BAAANQADCggIGAAAAA==.Reopal:BAAANQADCgUIBQAAAA==.Resperea:BAAANQAECgEIAQAAAA==.Revwild:BAAANQAECgEIAQAAAA==.',
Ri='Ricassou:BAAANQAECgIIAgAAAA==.Rivendell:BAAANQAECgYICAAAAA==.',
Ro='Roonkmc:BAAANQADCgQICgABNQADCgEIAQABAAAAAA==.Rorynne:BAAANQAECgEIAQAAAA==.',
Rr='Rrubio:BAAANQADCgcICwAAAA==.',
Ru='Rucy:BAAANQABCgMIBAAAAA==.Ruend:BAAANQADCgYIBgAAAA==.',
Ry='Ryndkmc:BAAANQADCggICAABNQADCgEIAQABAAAAAA==.Ryuujin:BAAANQADCgYICgAAAA==.',
['Ré']='Réflex:BAAANQADCgQIBgAAAA==.Réfléx:BAAANQAECgEIAQAAAA==.',
['Ró']='Ródin:BAAANQAECgQIBgABNQAFFAIIAgABAAAAAA==.',
Sa='Saeya:BAAANQADCgMIBAAAAA==.Sakurai:BAAANQADCgcIDQAAAA==.Salorllis:BAAANQADCggIDgAAAA==.Samedï:BAAANQADCgYIBgAAAA==.Saristia:BAAANQADCgcIDQAAAA==.Saveu:BAAANQAECgQIBgAAAA==.',
Sc='Screampies:BAAANQAECgQIBAAAAA==.',
Se='Seagulls:BAEANQADCggIFQAAAA==.Seayaa:BAAANQADCgcIDQAAAA==.Seiryu:BAAANQADCgIIAgAAAA==.Selindia:BAAANQADCgcIDQAAAA==.Sellsword:BAAANQADCgMIAwAAAA==.',
Sf='Sfx:BAAANQADCggIDAABNQAFFAEIAQABAAAAAA==.',
Sg='Sgt:BAAANQADCgYIDwAAAA==.',
Sh='Shadowydeath:BAAANQADCgYIDwAAAA==.Shaedee:BAAANQAECgMIBQAAAA==.Shallon:BAAANQAECgYIDQAAAA==.Shammpoo:BAAANQABCgMIBAAAAA==.Shammyshaga:BAAANQADCggIDgAAAA==.Shapest:BAAANQADCgQIBAAAAA==.Shelby:BAAANQADCgYIBgAAAA==.Shilihu:BAAANQADCggIEAAAAA==.Shinukishin:BAAANQAECgQIBQAAAA==.Shnottz:BAAANQAECgEIAQAAAA==.Shorzy:BAAANQAECgQIBAAAAA==.Shredzdh:BAAANQAECgIIAgAAAA==.',
Si='Sienar:BAAANQADCggICAAAAA==.Sillybone:BAAANQADCgEIAQAAAA==.Simulacra:BAAANQADCggIDgAAAA==.Sitonmytotem:BAAANQADCggIDgAAAA==.Sixteen:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyblades:BAAANQADCgEIAQAAAA==.Slu:BAABNQAECoEYAAIJAAkJrCGfCAB6AwAJAAkJrCGfCAB6AwABNQAECgQIBwABAAAAAA==.',
Sm='Smashinsmith:BAAANQAECgIIAgAAAA==.Smorgasbord:BAAANQADCggIEgAAAA==.',
Sn='Snackpack:BAAANQAECgUIBgAAAA==.Snowblind:BAAANQAECgEIAQAAAA==.Snowdancer:BAAANQADCgQIBwAAAA==.',
So='Sokkmage:BAAANQADCgYIDAAAAA==.Solnar:BAAANQADCggIEwAAAA==.Somno:BAAANQAECgUICAAAAA==.Sonory:BAAANQADCggICAAAAA==.Sophea:BAAANQADCgUIBQAAAA==.Soulfly:BAAANQADCgYIEQAAAA==.Soulsabi:BAAANQAECgIIAwAAAA==.Soulshaper:BAAANQADCgYIDgAAAA==.',
Sp='Spectral:BAAANQAECgcIDgAAAA==.Spiritspawn:BAAANQAECgYICgAAAA==.Spookyshark:BAAANQADCgQIBAAAAA==.Spoonman:BAAANQAECgYICAAAAA==.Spåwnkîll:BAAANQADCgUIBQAAAA==.',
Sq='Squidheäd:BAAANQABCgYICAAAAA==.',
St='Stardrift:BAAANQADCggIEgAAAA==.Stellar:BAAANQADCgEIAQAAAA==.Stere:BAAANQAECgMIBQAAAA==.Stinggrayjr:BAAANQADCgEIAQAAAA==.Stormhuff:BAAANQADCgUIBQAAAA==.Stärkiller:BAAANQADCgEIAQAAAA==.Stòrm:BAAANQADCgEIAQAAAA==.Stórm:BAAANQADCgYIBgAAAA==.',
Su='Sunderance:BAAANQADCgMIAwAAAA==.Superhilock:BAAANQAECgYICwAAAA==.Supplesuckle:BAAANQABCgIIAgABNQAECgQIBAABAAAAAA==.',
Sv='Svelesstiá:BAAANQADCgQIBQAAAA==.',
Sy='Sybrand:BAAANQAECgUICAAAAA==.Syrelliia:BAAANQAECgYICwAAAA==.Syrenia:BAAANQABCgEIAQAAAA==.',
['Sæ']='Sævage:BAAANQAECgEIAQAAAA==.',
['Sø']='Sørta:BAAANQADCgcIDQAAAA==.',
Ta='Tae:BAAANQADCgYICQAAAA==.Taigun:BAAANQADCgcIDQAAAA==.Tarnac:BAAANQADCgYICwAAAA==.Tazorface:BAAANQAECgUIBgAAAA==.',
Te='Terkey:BAAANQAECgYICwABNQAFFAEIAQABAAAAAA==.',
Th='Tharkash:BAAANQADCggIGgAAAA==.Thedockwho:BAAANQAECgIIAgAAAA==.Thedoctorwho:BAAANQADCgUIBQAAAA==.Theliarcy:BAAANQADCgYIBwAAAA==.Thesaint:BAAANQADCgQIBAAAAA==.Thirdeye:BAAANQAECgUICAAAAA==.Thoxic:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Thunderbuns:BAAANQADCggICAAAAA==.Thundrcat:BAAANQADCgEIAQAAAA==.',
Ti='Tipz:BAAANQAECgEIAgAAAA==.Tiras:BAAANQADCgEIAQAAAA==.',
To='Toolip:BAAANQAECgQIBAAAAA==.Tornwraith:BAAANQADCggIEQAAAA==.Towel:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.',
Tr='Traumasdruid:BAAANQADCggIDQAAAA==.Traviana:BAAANQADCggICwAAAA==.Trehuga:BAAANQAECggIDgAAAA==.Trikky:BAAANQADCgYIDwAAAA==.Triso:BAAANQAECgQIBwAAAA==.Trochanter:BAAANQADCgEIAQAAAA==.Tronus:BAAANQAECgEIAQABNQAECgMIBQABAAAAAA==.',
Ts='Tsukaar:BAAANQAECgQICAAAAA==.',
Tu='Tutorialboss:BAABNQAECoEXAAMKAAkJoR8sBABPAwAKAAkJhB8sBABPAwALAAEJTSQwjQBJAAAAAA==.',
Tw='Twohorns:BAAANQAECgYICwAAAA==.',
['Tö']='Töterfrieren:BAAANQAECgQIBgAAAA==.',
Ul='Ulrika:BAAANQADCgcIDQAAAA==.Ultrön:BAAANQAECgQIBAAAAA==.',
Um='Umbryelle:BAAANQADCgcICAAAAA==.',
Un='Undermaw:BAAANQAECgUICwAAAA==.Unforgyven:BAAANQADCggIDAAAAA==.Unicron:BAAANQADCggIDgAAAA==.',
Ur='Ursoulismine:BAAANQAECgEIAgAAAA==.',
Va='Valennah:BAAANQADCgYIDAAAAA==.Valgaar:BAAANQADCggIFQAAAA==.Vaneste:BAAANQAECgYICgAAAA==.Vartlock:BAAANQAECgQIBwAAAA==.Vartrino:BAAANQAECgQIBgABNQAECgQIBwABAAAAAA==.',
Ve='Veganator:BAAANQAECgYICgAAAA==.Veggies:BAAANQADCggIEgAAAA==.Velani:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Vendoralia:BAAANQABCgUICQAAAA==.Verifiedbot:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Verlant:BAAANQAECgQIBAAAAA==.',
Vi='Vinnyboombat:BAAANQABCgQIBAABNQADCgYICwABAAAAAA==.Vitus:BAAANQADCgUIBQAAAA==.',
Vl='Vladriel:BAAANQAECgEIAQAAAA==.',
Vo='Voljinn:BAAANQADCggICAAAAA==.',
Wa='Waddlebottle:BAAANQAECgMIAwAAAA==.Wallock:BAAANQADCgIIAgAAAA==.War:BAAANQAECgEIAQAAAA==.Warrdruid:BAAANQADCgIIAgAAAA==.Watchnu:BAAANQADCggIGgAAAA==.',
Wh='Whimsy:BAAANQADCggIDgAAAA==.Whät:BAAANQADCggIFAAAAA==.',
Wi='Willowhite:BAAANQAECgIIAgAAAA==.',
Wo='Wockyslush:BAAANQADCgUIBQAAAA==.',
Wu='Wubwub:BAAANQADCggICAAAAA==.Wulfjin:BAAANQAECgUIBwAAAA==.',
Xa='Xalia:BAAANQADCgQIBQAAAA==.',
Xe='Xellie:BAAANQADCgUIBgAAAA==.',
Xu='Xua:BAAANQADCgYIBgAAAA==.',
['Xë']='Xërík:BAAANQADCgcIEQAAAA==.',
Yo='Yopan:BAAANQADCgcICQAAAA==.',
['Yå']='Yåmatohime:BAAANQADCgUIBQABNQADCggIFAABAAAAAA==.',
Za='Zah:BAAANQADCgcIBwAAAA==.Zanntrhay:BAAANQABCgIIAgAAAA==.Zappymczaps:BAAANQADCggICgAAAA==.Zaremis:BAAANQAECgYIDQAAAA==.Zayehuo:BAAANQADCgcIDwAAAA==.',
Ze='Zeeni:BAAANQAECgIIAgAAAA==.Zelphie:BAAANQAECgQIBQAAAA==.Zemmy:BAAANQADCggICgAAAA==.Zemtor:BAAANQADCgYIBgAAAA==.Zent:BAAANQAECgEIAQAAAA==.Zenus:BAAANQAECgIIAgAAAA==.Zenveyra:BAAANQADCgQIBQAAAA==.Zerase:BAAANQAECgQIBAAAAA==.Zerttrak:BAAANQAECgYICgAAAA==.Zeus:BAAANQADCgQIBAAAAA==.',
Zi='Zilong:BAAANQADCggICAAAAA==.Zitania:BAAANQAECgIIAgAAAA==.',
Zu='Zugma:BAAANQAECgcIEAAAAA==.',
['Æl']='Ælin:BAAANQADCggICAAAAA==.',
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
