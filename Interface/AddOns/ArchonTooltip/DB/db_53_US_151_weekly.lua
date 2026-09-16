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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Shadow','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Mage-Arcane','Mage-Frost','DeathKnight-Blood','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Arms',}
local provider = {region='US',realm='Malfurion',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaluah:BAAANQAECgEIAQAAAA==.',
Ac='Acmis:BAAANQADCgYIFgABNQAECgIIAgABAAAAAA==.Acp:BAAANQAECgUICAAAAA==.',
Ad='Adomangma:BAAANQABCgQIBQAAAA==.',
Ah='Ahjumma:BAAANQAECgYIDgAAAA==.',
Ai='Ailskush:BAAANQAECgUICQAAAA==.',
Ak='Akadein:BAAANQADCgUIBQAAAA==.Akun:BAAANQADCgYIDAABNQAECgMIAwABAAAAAA==.Akurantirea:BAAANQAECgMIAwAAAA==.',
Al='Algerax:BAAANQAECgIIAwAAAA==.Allise:BAAANQADCgcIGAAAAA==.Alphamaled:BAAANQAECgYIDAAAAA==.Alva:BAAANQADCgYICAAAAA==.Aléthia:BAAANQAECgQIBQAAAA==.',
Am='Ambaxius:BAAANQADCgYIBgAAAA==.',
An='Anathemá:BAAANQADCgYICgAAAA==.Ange:BAAANQADCggIEAAAAA==.',
Ap='Apawpriest:BAAANQAECgYIDQAAAA==.',
Ar='Arke:BAAANQADCggICAAAAA==.Arraeroda:BAAANQAECgIIAgAAAA==.Arrence:BAAANQAECgIIAgABNQAECgYIDgABAAAAAA==.',
As='Ashara:BAAANQADCgcIBwAAAA==.Ashlena:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Astela:BAAANQAECgMIBAAAAA==.',
Au='Aumtatsat:BAAANQAECgUICQAAAA==.Autumn:BAAANQAECgQICAAAAA==.',
Av='Avan:BAAANQADCggICAAAAA==.Avatan:BAAANQAECgQICQAAAA==.Avedeath:BAAANQADCggIFwAAAA==.Aveena:BAAANQADCgMIAwAAAA==.',
Ay='Ayara:BAABNQAECoE7AAICAAkJ7CFdBABxAwACAAkJ7CFdBABxAwAAAA==.Ayrad:BAAANQAECgMIAwAAAA==.',
Ba='Badderdragon:BAAANQAECgcIEgAAAA==.Badmrmittens:BAAANQADCggIDwAAAA==.Badmuffin:BAAANQAECgIIAgAAAA==.Bahkita:BAAANQAECgQIBAAAAA==.Bakatran:BAAANQADCgMIBAAAAA==.Balamuth:BAAANQADCgYIBgAAAA==.Bandrui:BAAANQADCgYICgAAAA==.Barthas:BAAANQABCgQIBAAAAA==.',
Be='Begachan:BAAANQADCgYIBgAAAA==.Berkstein:BAAANQAECgIIAgAAAA==.',
Bi='Bigcai:BAAANQADCgYIBgAAAA==.Biggisnicker:BAAANQAECgYIDgAAAA==.Bigspriesty:BAAANQADCggIFAAAAA==.Bigtone:BAAANQAECgMIBgAAAA==.Bimbomz:BAAANQAECgQICwAAAA==.Biochemist:BAAANQADCgMIBAABNQAECgYIDQABAAAAAA==.Bioengineer:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Biogenic:BAAANQAECgYIDQAAAA==.Biomass:BAAANQADCgcICAABNQAECgYIDQABAAAAAA==.Biophysics:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.Birdbrain:BAAANQAECgYICwAAAA==.',
Bl='Blewîsa:BAAANQADCgMIAwAAAA==.Blvck:BAAANQADCgQIBAAAAA==.',
Bo='Boodylicious:BAAANQADCgYIBwABNQAECgIIBAABAAAAAA==.Borucmonk:BAAANQADCgYIDgABNQAECgMIAwABAAAAAA==.Borucwar:BAAANQAECgMIAwAAAA==.',
Br='Braedia:BAAANQADCggIFwAAAA==.Brassticus:BAAANQADCgcIBwAAAA==.Brawrski:BAAANQADCggIDwABNQAECgEIAQABAAAAAA==.Briele:BAAANQAECgIIAwAAAA==.Brise:BAAANQADCggIEAAAAA==.Brosabi:BAAANQAECgUICQABNQAECgcICgABAAAAAA==.Brucewaynexb:BAAANQABCgYIBgAAAA==.',
Bu='Bubs:BAAANQAECgQICgAAAA==.Buddhïst:BAAANQAECggIDwAAAA==.Burrhas:BAAANQADCgIIAgAAAA==.Buxky:BAAANQADCgEIAQAAAA==.',
['Bí']='Bítten:BAAANQAECgQIBAAAAA==.',
Ca='Cakesinatra:BAAANQADCggIDQABNQAECgIIAwABAAAAAA==.Cakewastaken:BAAANQAECgIIAwAAAA==.Cakke:BAAANQADCgUIBgAAAA==.Calkestis:BAAANQADCgQIBwAAAA==.Candre:BAAANQAECgYIDgAAAA==.Candyears:BAAANQADCgIIAgAAAA==.Capii:BAAANQAECgMIBAABNQAECgQIBgABAAAAAA==.Capristal:BAAANQAECgQIBgAAAA==.Carebeär:BAAANQADCgQIBAAAAA==.Caròl:BAAANQADCgUIBQAAAA==.Cassiera:BAAANQAECgYIDgAAAA==.Cauldren:BAAANQADCggIGwAAAA==.',
Ch='Chalice:BAAANQADCgYICwAAAA==.Charkycc:BAAANQADCgMIAwAAAA==.Chay:BAAANQAFFAEIAQAAAA==.Chaylin:BAAANQADCgcICAABNQAFFAEIAQABAAAAAA==.Chikage:BAAANQAECgEIAQAAAA==.Chillen:BAAANQAECgcIBgAAAA==.Chillzen:BAAANQADCgUIBQAAAA==.Chinofwin:BAAANQABCgIIAgAAAA==.Chivo:BAAANQAECgIIAgAAAA==.Chopu:BAAANQAECgQIBgAAAA==.Chrîstîne:BAAANQADCgYIBgAAAA==.Chuckspadina:BAAANQAECgYIEAAAAA==.Chuggin:BAAANQADCgMIAwAAAA==.Chyna:BAAANQADCgcIDAAAAA==.',
Ci='Cibø:BAAANQAECgEIAQAAAA==.Cilghalcao:BAAANQAECgIIAgAAAA==.Cirdae:BAAANQAECgYIDQAAAA==.',
Cl='Cleric:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.Cloudstone:BAAANQADCgQIBAAAAA==.Clõud:BAAANQAECgIIAwAAAA==.',
Co='Cococolalaw:BAAANQADCgEIAQAAAA==.Coggknocker:BAAANQABCgMIAwAAAA==.Coldsnaps:BAAANQADCgYIBgAAAA==.Conc:BAAANQAECgcIEAAAAA==.Cormac:BAAANQADCggICAAAAA==.',
Cp='Cpthardfap:BAAANQAECgUICAAAAA==.',
Cr='Crazynip:BAAANQAECgcIEgAAAA==.Crickit:BAAANQAECgQIBAAAAA==.Crispr:BAAANQADCggIDAAAAA==.Cryavus:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.Crylucis:BAAANQAECgYIDwAAAA==.Crymagus:BAAANQADCgcIBwABNQAECgYIDwABAAAAAA==.Crypticál:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.',
Cu='Cujo:BAAANQAECgYIDwAAAA==.',
Cy='Cyanidesun:BAAANQADCgcIDgAAAA==.Cybre:BAAANQADCgcIGAAAAA==.Cyndaquill:BAAANQAECggIAQAAAA==.Cyndil:BAAANQAECgQIBgAAAA==.Cysora:BAAANQAECgEIAQAAAA==.',
['Cä']='Cästiel:BAAANQAECgIIBAAAAA==.',
Da='Daahntaat:BAAANQABCgMIBQAAAA==.Daesyn:BAAANQABCgMIBAAAAA==.Dallei:BAAANQAECgIIAgAAAA==.Danbearpig:BAAANQABCgQIBAAAAA==.Dandish:BAAANQAECgQICAAAAA==.Darcane:BAAANQAECgYIEQAAAA==.Darkvayne:BAAANQAECgYIBgAAAA==.Darrington:BAAANQAECgMIAwAAAA==.Dathrel:BAAANQADCggIEQAAAA==.Dawnfather:BAAANQABCgYIBwAAAA==.Dawnfoxer:BAAANQADCgUIBQAAAA==.',
De='Deathpig:BAAANQADCggIAgAAAA==.Deezaster:BAAANQAECgEIAQAAAA==.Def:BAAANQAECgcICwAAAA==.Delani:BAAANQAECgEIAQAAAA==.Delisius:BAAANQADCgYIBgAAAA==.Deltaco:BAAANQADCgYIEQAAAA==.Dementis:BAAANQADCgUIBwABNQADCgUICQABAAAAAA==.Demonnova:BAABNQAECoEfAAMCAAkJxhwIDgC5AgACAAgJkx4IDgC5AgADAAIJIwkxQgCEAAAAAA==.Dendude:BAAANQABCgEIAQAAAA==.Devinity:BAAANQADCgUIBQAAAA==.Dezsp:BAACNQAFFIEMAAIEAAUJaSK7AAAMAgAEAAUJaSK7AAAMAgA1AAQKgSIAAgQACQkWJp0AAOADAAQACQkWJp0AAOADAAAA.',
Dg='Dghunter:BAAANQAECgUIDwAAAA==.',
Di='Dietrinea:BAAANQADCgIIAgAAAA==.',
Do='Docsored:BAAANQAECgEIAQAAAA==.Dontholdback:BAAANQADCgUIBQAAAA==.Donuts:BAAANQAECgQIBAAAAA==.Doomchick:BAAANQABCgYICgAAAA==.',
Dr='Dragn:BAAANQADCgYIDAAAAA==.Dragnas:BAAANQAECgYIEAAAAA==.Dragniperake:BAAANQAECgUICQAAAA==.Drbluejeans:BAAANQAECgEIAQABNQAECggIDAABAAAAAA==.Drbug:BAAANQAECgUIBgABNQAECggIDAABAAAAAA==.Drdots:BAAANQAECgYIDAAAAA==.Dreadnaunt:BAAANQAECgEIAQAAAA==.Dreamhc:BAAANQAECgYIDwAAAA==.Dresperea:BAAANQADCgUIBQAAAA==.Drugral:BAAANQAECgcIEgAAAA==.',
Du='Dugronn:BAAANQADCggIGwAAAA==.',
Dw='Dwarfvadar:BAAANQAECgIIAgAAAA==.',
Ea='Eadric:BAAANQADCggIDQAAAA==.',
El='Elanthemage:BAAANQAECgIIAgAAAA==.Eleison:BAACNQAFFIEFAAIEAAMJCBvUAwAmAQAEAAMJCBvUAwAmAQA1AAQKgRgAAgQACQnBIb8DAHkDAAQACQnBIb8DAHkDAAAA.Ellairis:BAAANQAECgIIAgAAAA==.Ellesperis:BAAANQAECgIIAgAAAA==.Ellumon:BAAANQAECgEIAQAAAA==.Elyana:BAAANQADCggIGQAAAA==.Elyssarelsia:BAAANQAECgUIBQAAAA==.',
Em='Emergnc:BAAANQADCgQIBAAAAA==.',
Er='Eragôn:BAAANQAECgUIBwAAAA==.Erinyes:BAAANQAECgUIDAAAAA==.',
Es='Estee:BAAANQAECgIIAgAAAA==.',
Et='Ethyl:BAAANQADCgEIAQAAAA==.',
Ex='Exarkune:BAAANQADCgYIBgAAAA==.Executioner:BAAANQAECgEIAQAAAA==.',
Fa='Fatfish:BAAANQADCggIBQAAAA==.Fatty:BAAANQAECgYIDQAAAA==.',
Fe='Fenja:BAAANQAECgYIEAAAAA==.Feul:BAABNQAECoE7AAIFAAkJfBs+EwC/AgAFAAkJfBs+EwC/AgAAAA==.Feyded:BAAANQAECgIIAgAAAA==.Feylis:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.',
Fh='Fhara:BAAANQADCgUIBgAAAA==.',
Fi='Fiasko:BAAANQAECgYIEQAAAA==.Fiir:BAAANQADCggIEwAAAA==.Firehose:BAAANQADCgUIBQABNQAECgYIDwABAAAAAA==.',
Fl='Flippÿ:BAAANQAECgIIAwAAAA==.Flowerpower:BAAANQAECgMIAwAAAA==.Fluffythecup:BAAANQAECgIIAgAAAA==.',
Fm='Fmliplaygoat:BAAANQAECgQICAAAAA==.',
Fo='Foreverdead:BAAANQADCgQIBQAAAA==.Formidonis:BAABNQAECoEVAAMGAAgJWBoPJABZAgAGAAcJLBoPJABZAgAHAAIJGhH1PgCNAAAAAA==.Foxyboo:BAAANQADCgYICwAAAA==.',
Fr='Frostlady:BAAANQADCgUIBQAAAA==.Frostyna:BAAANQAECgYIEQAAAA==.',
Fu='Fubber:BAAANQAECgcIEAAAAA==.Fulgur:BAAANQAECgQIBQAAAA==.Funsizegurly:BAAANQAECgUIDQAAAA==.',
Ga='Gallypotter:BAAANQAECgUIEgAAAA==.Garygabagool:BAAANQAECgcIEQAAAA==.Gawdshamit:BAAANQAECgQIBgAAAA==.Gawdspet:BAAANQAECgIIAwABNQAECgkJHQAGACodAA==.',
Ge='Gemcutter:BAAANQADCgEIAQAAAA==.Geoffreey:BAAANQADCggIFAAAAA==.',
Gh='Ghakk:BAAANQADCgYICAAAAA==.Ghostmane:BAAANQABCgYIDQAAAA==.Ghostorc:BAAANQAECgUICgAAAA==.',
Gi='Gichidolo:BAAANQADCgEIAQAAAA==.Giegs:BAAANQAECgUICgAAAA==.',
Gl='Glockcoma:BAAANQADCgUIBAAAAA==.',
Gn='Gnatytoop:BAAANQAECgYIDgAAAA==.Gnawrly:BAAANQAECgQICQAAAA==.',
Go='Gonzo:BAAANQAECgcIDQAAAA==.Goodgirl:BAAANQAECgQIBgABNQAECggIDAABAAAAAA==.Goodgurl:BAAANQAECggIDAAAAA==.Govrek:BAAANQAECgEIAgAAAA==.',
Gr='Greenstone:BAAANQADCgQIBQAAAA==.Gricavent:BAAANQAECgQIBAAAAA==.Grobyc:BAAANQAECgEIAQAAAA==.Grïm:BAAANQAECgYIDQAAAA==.',
Gt='Gtfobubble:BAAANQAECgQIBAAAAA==.Gtfolava:BAAANQADCgcIDAAAAA==.',
Gu='Guldont:BAAANQADCggIEwAAAA==.',
Ha='Hankering:BAAANQAECgIIAwABNQAECgYIEQABAAAAAA==.Hankopher:BAAANQAECgYIEQAAAA==.Hanziè:BAAANQAECgEIAQAAAA==.Haptics:BAABNQAECoEUAAMIAAgJ4hx0CQCwAgAIAAgJwBt0CQCwAgAJAAUJSB5vGQCxAQAAAA==.Harbinger:BAAANQADCgMIAwAAAA==.Harmonix:BAAANQAECgQIBQAAAA==.Hasbin:BAAANQADCgUIBQAAAA==.Hatzel:BAAANQAECgcIDQAAAA==.',
He='Heaf:BAAANQAECgEIAQAAAA==.Hecateis:BAAANQADCggIFgAAAA==.Heenan:BAAANQAECgEIAgAAAA==.Hellhaunt:BAAANQAECgEIAQAAAA==.Hellstar:BAAANQADCgcICAAAAA==.Hemdh:BAAANQADCggIDgABNQAFFAUIBwAIAD8hAA==.Herukas:BAAANQAECgQIBgAAAA==.Hexsteele:BAAANQAECgcICAABNQAECgkJIQAKAJEkAA==.',
Hi='Hikons:BAAANQADCgUIBQABNQAECgYIDQABAAAAAA==.Hitdeath:BAAANQADCgcIDQABNQADCggICAABAAAAAA==.',
Ho='Hohiro:BAAANQADCgcIDgAAAA==.Holdmybear:BAAANQAECgQIBQAAAA==.Holyblood:BAAANQAECgQIBAAAAA==.Holyfudge:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Holyhyper:BAAANQAECgYIDgAAAA==.Holyness:BAAANQADCgEIAQAAAA==.Holywaddles:BAAANQADCgYIDAAAAA==.',
Hr='Hrinnu:BAAANQAECgUICgAAAA==.',
Ht='Htownshawdo:BAAANQAECgQIBQAAAA==.',
Hu='Huevocutter:BAAANQADCggICAAAAA==.Huntardftw:BAAANQADCgQIAgAAAA==.Huntwick:BAAANQAECgQIBAAAAA==.Hurkaj:BAAANQAECgQIBQAAAA==.Huwest:BAAANQAECgEIAQAAAA==.',
['Hü']='Hünterrific:BAAANQADCgMIBQAAAA==.',
Ic='Icanhealyou:BAAANQAECgcIEQAAAA==.',
Ih='Ihatepriests:BAAANQAECgQICAAAAA==.',
Il='Illusk:BAAANQAECgIIAwABNQAECgYIEQABAAAAAA==.',
In='Incisor:BAAANQADCgYIBgAAAA==.Incline:BAAANQAECgQIBAAAAA==.Inoo:BAAANQAECgMIBQAAAA==.',
Ir='Irishhammer:BAAANQAECgIIAgAAAA==.',
Is='Isvnpcdhg:BAAANQAECgEIAgAAAA==.',
It='Itkovien:BAAANQAECgQIBAAAAA==.',
['Iá']='Ián:BAAANQAECgYIDgAAAA==.',
Ja='Janq:BAAANQAECgcIEgAAAA==.Jayde:BAAANQADCgUIBgAAAA==.',
Je='Jerrodsmage:BAAANQAECgIIAgAAAA==.Jezbrez:BAAANQAECgUICwAAAA==.',
Ji='Jinzu:BAAANQAECggIEwAAAA==.Jizzledizzle:BAAANQAECgEIAQAAAA==.',
Jo='Jono:BAAANQAECgEIAQAAAA==.',
Jp='Jphlip:BAAANQAECgYIDQAAAA==.Jpmagi:BAAANQAFFAEIAQAAAA==.',
Ju='Juice:BAAANQADCggIFAAAAA==.Juisi:BAAANQAECgYIEAAAAA==.Justania:BAAANQADCgEIAQABNQAECgYICAABAAAAAA==.',
['Jô']='Jô:BAAANQADCggIDgAAAA==.',
Ka='Kaeloth:BAAANQAECgYIDAAAAA==.Kagayoshi:BAAANQADCgIIAgAAAA==.Kainen:BAAANQABCgQIBgAAAA==.Kalal:BAAANQADCgYIBgAAAA==.Kalebmonk:BAAANQADCgYIBwABNQAECgYIEQABAAAAAA==.Kalebpal:BAAANQAECgYIEQAAAA==.Kamtano:BAAANQAECgIIAgAAAA==.Kavaliro:BAAANQADCgMIAwAAAA==.Kayaane:BAAANQABCgYICAAAAA==.Kayaanu:BAAANQAECgYIDgAAAA==.Kazimiraci:BAAANQADCggICAAAAA==.',
Ke='Kegsmasher:BAAANQADCggICAAAAA==.Kellholy:BAAANQAECgcIBwAAAA==.',
Kh='Khyzer:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.',
Ki='Kickya:BAAANQABCgEIAQAAAA==.Kidkill:BAAANQADCgIIAgAAAA==.Killaboy:BAAANQADCgEIAQAAAA==.Killstar:BAAANQADCgUICQAAAA==.Kindeesver:BAAANQADCgMIAwAAAA==.Kirke:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Kirriana:BAAANQAECgIIAwAAAA==.Kisara:BAAANQADCgIIAgABNQAECgQICAABAAAAAA==.',
Kk='Kkitty:BAAANQADCggICQAAAA==.',
Kl='Kleddus:BAAANQADCgYIBgAAAA==.Kletas:BAAANQAECgUIBQAAAA==.Kletus:BAAANQADCgYICAAAAA==.',
Kn='Knokkpriest:BAAANQAECgYICgAAAA==.',
Ko='Kobs:BAAANQADCgUIBQAAAA==.Kopy:BAAANQAECgUIDAABNQAECgcICAABAAAAAA==.Korvash:BAAANQAECgQICAAAAA==.',
Kr='Kroitz:BAAANQADCgUIBQAAAA==.Kromgol:BAAANQAFFAEIAQAAAA==.',
Ku='Kujaku:BAAANQAECgIIAgAAAA==.',
Kw='Kwende:BAAANQADCggIGwAAAA==.',
Ky='Kyela:BAAANQAECgIIAgAAAA==.Kyrtion:BAAANQAECgYIEQAAAA==.',
['Kä']='Kätsuö:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
['Kø']='Kørupted:BAAANQAECgIIAgAAAA==.',
La='Lamiisa:BAAANQAECgQICAAAAA==.Lanaris:BAAANQADCggIEAAAAA==.Laurandrel:BAAANQAECgIIAgAAAA==.Laved:BAAANQAECgYIDgAAAA==.Lawgi:BAAANQAECgYIEAAAAA==.Lawliet:BAAANQABCgIIAgAAAA==.',
Ld='Ldkils:BAAANQADCgIIAgAAAA==.Ldlockem:BAAANQAECgUICgAAAA==.',
Le='Lewìn:BAAANQAECgcIBgAAAA==.',
Li='Likäbäws:BAAANQADCgYIBgAAAA==.Lilitü:BAAANQADCggICQAAAA==.Lilshadow:BAAANQADCgEIAQAAAA==.Lilwascal:BAAANQADCgYIDwAAAA==.Lilya:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Linatheslayr:BAAANQADCggIDQAAAA==.Linossa:BAAANQAECgcIDQAAAA==.Lithiris:BAAANQAECgYICAAAAA==.',
Ll='Llonso:BAAANQADCgUIBQAAAA==.',
Lo='Lockjam:BAAANQADCgEIAQAAAA==.Lookiezi:BAAANQAECgcIEQAAAA==.Lovemuffîn:BAAANQAECgQIBgAAAA==.',
Lu='Lucidonis:BAAANQAECgUIBwAAAA==.Luminaconri:BAAANQADCgUIBgAAAA==.',
Ly='Lystia:BAAANQAECgIIAgAAAA==.',
['Læ']='Læncelot:BAAANQAECgMIAwAAAA==.',
Ma='Madriel:BAAANQAECgIIAgAAAA==.Mafanya:BAAANQABCgYICgAAAA==.Magento:BAABNQAECoEYAAMLAAgJ9hsHSgBvAgALAAgJFRgHSgBvAgAMAAIJTCAkEwDBAAAAAA==.Maladie:BAAANQAECgYIDQAAAA==.Malvaron:BAAANQADCgUIBQAAAA==.Mauna:BAAANQADCggIDwAAAA==.Mavzy:BAAANQAECgYIEAAAAA==.',
Mc='Mcbubbies:BAAANQAECggIDgAAAA==.Mcfknkfc:BAAANQADCggIEAAAAA==.',
Me='Meeyo:BAAANQADCgEIAQAAAA==.Megamanmeat:BAAANQAECggIAgAAAA==.Melpomne:BAAANQADCgMIAwAAAA==.',
Mi='Micti:BAAANQAECgUICQAAAA==.Milamber:BAAANQAECgQICAAAAA==.Minionrogue:BAAANQAECgEIAQAAAA==.Minyon:BAAANQAECgUIDwAAAA==.Miruna:BAAANQADCgcICgAAAA==.Missiles:BAAANQADCgIIAgAAAA==.Missing:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
Mo='Mogge:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.Mommadragon:BAAANQAECgIIAgAAAA==.Monsterflexx:BAAANQAECgQIBAAAAA==.Moosè:BAAANQADCgYIFQAAAA==.',
Mu='Mugron:BAAANQAECgcIDQABNQAFFAUICQANAHsZAA==.',
My='Mydkfelloff:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.Myronath:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Mystafire:BAAANQADCgYIDgAAAA==.Mythpriest:BAAANQAECgIIAgABNQAECgYIEAABAAAAAA==.',
Na='Nadlug:BAAANQADCgcIEwAAAA==.Naki:BAAANQAECgQIBQABNQAECgcICwABAAAAAA==.Naljubuites:BAAANQABCgYICwAAAA==.Naradda:BAAANQADCgUIBQAAAA==.Nazra:BAAANQADCgMIAwAAAA==.',
Ne='Neebstrasza:BAAANQADCgYICAAAAA==.Nensuk:BAAANQADCgEIAQAAAA==.Newdamda:BAAANQADCggIFAAAAA==.',
Ni='Nicodormus:BAAANQAECgEIAQAAAA==.Nicolius:BAAANQAECgYIEQAAAA==.Ningenalah:BAAANQAECgYIEAAAAA==.Ningenurion:BAAANQAECgIIAwABNQAECgYIEAABAAAAAA==.Nippÿ:BAAANQAECgYIEQAAAA==.',
No='Norav:BAAANQAECgcIDwAAAA==.Nordryde:BAAANQAECggIDgAAAA==.Nordrydm:BAAANQADCggICgABNQAECggIDgABAAAAAA==.Notfrïendly:BAAANQADCgIIAgAAAA==.Novamortis:BAAANQADCgQIBAAAAA==.',
Nu='Nuabo:BAAANQADCgMIAwABNQAECgYIDgABAAAAAA==.',
Of='Offensive:BAAANQAECgQIBAAAAA==.',
Ol='Olayhahla:BAAANQAECgQIBgAAAA==.',
Op='Opalausia:BAAANQADCgYIBgAAAA==.',
Or='Oregano:BAABNQAECoEVAAIOAAgJdiMdAwAoAwAOAAgJdiMdAwAoAwAAAA==.',
Os='Osyrus:BAAANQADCgEIAQAAAA==.',
Ou='Ourania:BAAANQADCgEIAQAAAA==.',
Ov='Overkill:BAAANQABCgQIBAAAAA==.',
Pa='Padreberk:BAAANQADCgYIEgAAAA==.Painremains:BAAANQADCgcIDAAAAA==.Pantyfa:BAAANQADCgIIAwAAAA==.',
Pe='Pekkie:BAAANQADCggIHAAAAA==.Penpineapple:BAAANQAECgEIAQAAAA==.Penthesilea:BAAANQAECgEIAQAAAA==.Perchance:BAAANQABCgIIAgAAAA==.Pestcontrol:BAAANQAECgEIAQAAAA==.',
Ph='Phallon:BAAANQAECgIIAwAAAA==.',
Pi='Pioree:BAABNQAECoEZAAQPAAgJihVvFwCWAQAPAAYJFBZvFwCWAQAQAAQJNRDEGgD6AAARAAIJlAeEEQBQAAAAAA==.Pixen:BAEANQAECgQIBQABNQAECggIFwAGAAwXAA==.',
Po='Ponglenis:BAAANQADCggIEAAAAA==.Pookiebear:BAAANQADCgMIAwAAAA==.Poonany:BAAANQAECgEIAQAAAA==.Pootnuts:BAAANQADCgIIAgAAAA==.',
Pr='Prandal:BAAANQAECgEIAQAAAA==.Pregzuel:BAAANQADCgUIBgAAAA==.Projecthorde:BAAANQAECgYIDgAAAA==.Pronouns:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.',
Py='Pyroganus:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Qu='Quanzanon:BAAANQAECgYIDQAAAA==.Quizhik:BAAANQADCggIEQABNQAECgYIDAABAAAAAA==.',
Ra='Rachelrae:BAAANQAECgYIEAAAAA==.Radbrother:BAAANQABCgIIAgAAAA==.Rag:BAAANQADCggICAAAAA==.Ralphy:BAAANQAECgUICgAAAA==.Ramenwrapz:BAAANQAECgQIBAAAAA==.Raryees:BAAANQAFFAEIAQAAAA==.',
Re='Reddynon:BAAANQAECgQICAAAAA==.Reginald:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Relin:BAAANQAECggIDwAAAA==.Relinbear:BAAANQADCgcIBwABNQAECggIDwABAAAAAA==.Relse:BAAANQADCgEIAQAAAA==.Renika:BAAANQAECgYICgAAAA==.Renmazuo:BAAANQAECgcICwAAAA==.Renrax:BAAANQAECgEIAQAAAA==.Reopal:BAAANQADCgUIBQAAAA==.Resperea:BAAANQAECgEIAgAAAA==.Revwild:BAAANQAECgQIBQAAAA==.',
Ri='Ricassou:BAAANQAECgMIBQAAAA==.Rivendell:BAAANQAECgYIDgAAAA==.',
Ro='Roonkmc:BAAANQAECgIIAgABNQADCgEIAQABAAAAAA==.Rorynne:BAAANQAECgIIAwAAAA==.',
Rr='Rrubio:BAAANQADCggIEgAAAA==.',
Ru='Rucy:BAAANQABCgMIAwAAAA==.Ruend:BAAANQADCgYIBgAAAA==.',
Ry='Ryndkmc:BAAANQADCggICAABNQADCgEIAQABAAAAAA==.Ryuujin:BAAANQADCgYICwAAAA==.',
['Ré']='Réflex:BAAANQADCgQIBgAAAA==.Réfléx:BAAANQAECgEIAQAAAA==.',
['Ró']='Ródin:BAAANQAECgQIBgABNQAFFAMIBQAEAAgbAA==.',
Sa='Saeya:BAAANQADCgMIBAAAAA==.Sakurai:BAAANQAECgIIAgAAAA==.Salorllis:BAAANQAECgMIAwAAAA==.Samedï:BAAANQADCgYIBgAAAA==.Sarah:BAAANQADCggIAgAAAA==.Saristia:BAAANQAECgIIAgAAAA==.Saveu:BAAANQAECgUICwAAAA==.',
Sc='Screampies:BAAANQAECgQIBgAAAA==.',
Se='Seagulls:BAEANQAECgEIAQAAAA==.Seayaa:BAAANQAECgIIAgAAAA==.Seiryu:BAAANQADCgMIAwAAAA==.Selindia:BAAANQAECgIIAgAAAA==.Sellsword:BAAANQADCgMIAwAAAA==.',
Sf='Sfx:BAAANQADCggIDAABNQAECgMIAwABAAAAAA==.',
Sg='Sgt:BAAANQAECgIIAgAAAA==.',
Sh='Shadowydeath:BAAANQADCgYIEAAAAA==.Shaedee:BAAANQAECgcIDAAAAA==.Shallon:BAAANQAECgYIDQAAAA==.Shammpoo:BAAANQABCgUIBgAAAA==.Shammyshaga:BAAANQAECgMIAwAAAA==.Shapest:BAAANQADCgQIBAAAAA==.Shelby:BAAANQADCgcIBwAAAA==.Shilihu:BAAANQADCggIFwAAAA==.Shinukishin:BAAANQAECgQICAAAAA==.Shnottz:BAAANQAECgEIAQAAAA==.Shorzy:BAAANQAECgQICAAAAA==.Shredzdh:BAAANQAECgYICAAAAA==.',
Si='Sienar:BAAANQADCggICwAAAA==.Sillybone:BAAANQADCgEIAQAAAA==.Simulacra:BAAANQAECgIIAgAAAA==.Sitonmytotem:BAAANQADCggIDgAAAA==.Sixteen:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyblades:BAAANQADCgEIAQAAAA==.Slu:BAABNQAECoEaAAILAAkJfiNMEABnAwALAAkJfiNMEABnAwABNQAECgYIDwABAAAAAA==.',
Sm='Smashinsmith:BAAANQAECgIIAwAAAA==.Smorgasbord:BAAANQAECgEIAQAAAA==.',
Sn='Snackpack:BAAANQAECgYIDAAAAA==.Snowblind:BAAANQAECgEIAQAAAA==.Snowdancer:BAAANQADCggIDwAAAA==.',
So='Sokkmage:BAAANQADCgYIDAAAAA==.Solnar:BAAANQAECgMIAwAAAA==.Somno:BAAANQAECgYIDgAAAA==.Sonory:BAAANQADCggICAAAAA==.Sophea:BAAANQADCgUIBwAAAA==.Soska:BAAANQADCgYIDAAAAA==.Soulfly:BAAANQAECgEIAQAAAA==.Soulsabi:BAAANQAECgcICgAAAA==.Soulshaper:BAAANQADCgcIFQAAAA==.',
Sp='Spectral:BAABNQAECoEaAAISAAkJdCECCgAMAwASAAkJdCECCgAMAwAAAA==.Spiritspawn:BAAANQAECgcIEQAAAA==.Spookyshark:BAAANQADCgQIBAAAAA==.Spoonman:BAAANQAECgcIDwAAAA==.Spåwnkîll:BAAANQADCgUIBQAAAA==.',
Sq='Squidheäd:BAAANQABCgYICAAAAA==.',
St='Stardrift:BAAANQADCggIEgAAAA==.Stare:BAAANQABCgUIAwAAAA==.Stellar:BAAANQADCgEIAQAAAA==.Stere:BAAANQAECgcIDgAAAA==.Stinggrayjr:BAAANQAECgEIAQAAAA==.Stormhuff:BAAANQADCgUIBQAAAA==.Stärkiller:BAAANQADCgEIAQAAAA==.Stòrm:BAAANQADCgEIAQAAAA==.Stórm:BAAANQADCgYICQAAAA==.',
Su='Sunderance:BAAANQADCgMIAwAAAA==.Superhilock:BAAANQAECgcIEgAAAA==.Supplesuckle:BAAANQABCgIIAgABNQAECgQIBgABAAAAAA==.',
Sv='Svelesstiá:BAAANQADCgYICgAAAA==.',
Sy='Sybrand:BAAANQAECgYIDgAAAA==.Syrelliia:BAAANQAECgcIEgAAAA==.Syrenia:BAAANQABCgEIAQAAAA==.',
['Sæ']='Sævage:BAAANQAECgYIBwAAAA==.',
['Sø']='Sørta:BAAANQAECgIIAgAAAA==.',
Ta='Tae:BAAANQADCggICwAAAA==.Taigun:BAAANQAECgIIAgAAAA==.Tarnac:BAAANQADCgYICwAAAA==.Tazorface:BAAANQAECgYIDAAAAA==.',
Te='Terkey:BAAANQAECgcIEgABNQAECggIGgALAPQZAA==.',
Th='Tharkash:BAAANQAECgEIAQAAAA==.Thedocktore:BAAANQADCgYIBgAAAA==.Thedockwho:BAAANQAECgQIBgAAAA==.Thedoctorwho:BAAANQADCgUIBQAAAA==.Theliarcy:BAAANQADCgYIBwAAAA==.Thesaint:BAAANQADCgQIBAAAAA==.Thirdeye:BAAANQAECgYIDgAAAA==.Thoxic:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.Thunderbuns:BAAANQADCggICAAAAA==.Thundrcat:BAAANQADCgEIAQAAAA==.',
Ti='Tiffaniie:BAAANQABCgIIAwAAAA==.Timidity:BAAANQAECgIIAgAAAA==.Tinkerbelles:BAAANQADCgMIAwAAAA==.Tipz:BAAANQAECgQIBgAAAA==.Tiras:BAAANQADCgEIAQAAAA==.',
To='Toolip:BAAANQAECgQICAAAAA==.Tornwraith:BAAANQADCggIGQAAAA==.Towel:BAAANQADCgcIBwABNQAECgQICwABAAAAAA==.',
Tr='Traumademon:BAAANQABCggICwABNQADCggIEwABAAAAAA==.Traumasdruid:BAAANQADCggIEwAAAA==.Traviana:BAAANQADCggIEwAAAA==.Trehuga:BAABNQAECoEdAAITAAkJ+hi8CQCdAgATAAkJ+hi8CQCdAgAAAA==.Trikky:BAAANQAECgEIAQAAAA==.Triso:BAAANQAECgYIDwAAAA==.Trochanter:BAAANQADCgUIBQAAAA==.Tronus:BAAANQAECgEIAQABNQAECgUICgABAAAAAA==.',
Ts='Tsukaar:BAAANQAECgYIDgAAAA==.',
Tu='Tutorialboss:BAABNQAECoEfAAMUAAkJSCPQAgCLAwAUAAkJKyPQAgCLAwAVAAEJTSTIwwBDAAAAAA==.',
Tw='Twohorns:BAAANQAECgcIEgAAAA==.',
['Tö']='Töterfrieren:BAAANQAECgUICwAAAA==.',
Ul='Ulrika:BAAANQADCggIFQAAAA==.Ultrön:BAAANQAECgQICAAAAA==.',
Um='Umbryelle:BAAANQADCgcICAAAAA==.',
Un='Undermaw:BAAANQAECgcIEgAAAA==.Unforgyven:BAAANQADCggIDAAAAA==.Unicron:BAAANQADCggIFQAAAA==.Uniscorn:BAAANQABCgIIAgAAAA==.',
Ur='Ursoulismine:BAAANQAECgEIAgAAAA==.',
Va='Valennah:BAAANQADCgcIDQAAAA==.Valgaar:BAAANQADCggIFgAAAA==.Vaneste:BAAANQAECgcIDAAAAA==.Vartlock:BAAANQAECgYIDQAAAA==.Vartrino:BAAANQAECgQICAABNQAECgYIDQABAAAAAA==.',
Ve='Veganator:BAAANQAECgYIEAAAAA==.Veggies:BAAANQAECgEIAQAAAA==.Velani:BAAANQADCggIFAABNQAECgQICAABAAAAAA==.Vendoralia:BAAANQADCgIIAgAAAA==.Verifiedbot:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Verlant:BAAANQAECgQICAAAAA==.',
Vi='Vinnyboombat:BAAANQABCgQIBAABNQADCgYICwABAAAAAA==.Virâyâ:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Vitus:BAAANQADCggIDQAAAA==.',
Vl='Vladriel:BAAANQAECgIIAwAAAA==.',
Vo='Voljinn:BAAANQADCggIDwAAAA==.',
Wa='Waddlebottle:BAAANQAECgMIAwAAAA==.Wallock:BAAANQAECgIIAgAAAA==.War:BAAANQAECgcICAAAAA==.Warrdruid:BAAANQADCgIIAgAAAA==.Watchnu:BAAANQADCggIIgAAAA==.',
Wh='Whimsy:BAAANQADCggIFAAAAA==.Whät:BAAANQADCggIHAABNQAECgEIAQABAAAAAA==.',
Wi='Willowhite:BAAANQAECgQIBgAAAA==.',
Wo='Wockyslush:BAAANQADCgUIBQAAAA==.',
Wu='Wubers:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.Wubwub:BAAANQAECgcIBwAAAA==.Wulfjin:BAAANQAECgUIDAAAAA==.',
Xa='Xalia:BAAANQADCgQIBQAAAA==.',
Xe='Xellie:BAAANQADCgUIBgAAAA==.',
Xu='Xua:BAAANQADCgYIDAAAAA==.',
['Xë']='Xërík:BAAANQADCggIGQAAAA==.',
Yo='Yopan:BAAANQADCgcIDwAAAA==.',
['Yå']='Yåmatohime:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Za='Zada:BAAANQADCgQIBAAAAA==.Zah:BAAANQAECgEIAQAAAA==.Zanntrhay:BAAANQABCgIIAgAAAA==.Zappymczaps:BAAANQADCggICgAAAA==.Zappÿ:BAAANQADCggICAAAAA==.Zaremis:BAABNQAECoEYAAMFAAgJMSNQCQAmAwAFAAgJMSNQCQAmAwAKAAMJMgPQlQCDAAAAAA==.Zayehuo:BAAANQADCgcIFgAAAA==.',
Ze='Zeeni:BAAANQAECgIIAgAAAA==.Zelphie:BAAANQAECgUICgAAAA==.Zemmy:BAAANQAECgMIAwAAAA==.Zemtor:BAAANQADCgYIBgAAAA==.Zent:BAAANQAECgEIAQAAAA==.Zenus:BAAANQAECgIIBAAAAA==.Zenveyra:BAAANQADCgUIBwAAAA==.Zerase:BAAANQAECgQICAAAAA==.Zerttrak:BAAANQAECgYIEAAAAA==.Zeus:BAAANQADCgQIBAAAAA==.',
Zi='Zilong:BAAANQAECgMIAwAAAA==.Zitania:BAAANQAECgIIBAAAAA==.',
Zu='Zugma:BAABNQAECoEYAAIWAAgJ+RzGHwDYAgAWAAgJ+RzGHwDYAgAAAA==.',
['Æl']='Ælin:BAAANQAECgIIAgAAAA==.',
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
