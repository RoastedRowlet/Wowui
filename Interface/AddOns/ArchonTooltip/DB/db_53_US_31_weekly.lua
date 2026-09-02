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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aarkan:BAAANQAECgEIAQAAAA==.',
Ac='Acanialyn:BAAANQADCgUIBQAAAA==.',
Ad='Adea:BAAANQAECgMIBAAAAA==.',
Ae='Aeiro:BAAANQAECgIIAgAAAA==.Aetheriel:BAAANQADCgcIDAAAAA==.',
Ai='Aireez:BAAANQADCgUIBQAAAA==.Airrin:BAAANQADCgYICQAAAA==.',
Aj='Ajoseywales:BAAANQAECgMIAwAAAA==.',
Ak='Akatala:BAAANQAECgEIAQAAAA==.Akunda:BAAANQADCggIDwAAAA==.',
Al='Alamaania:BAAANQADCgcICwAAAA==.Alaterial:BAAANQADCgUIBQAAAA==.Aloha:BAAANQAECgYICgAAAA==.Aluriel:BAAANQAECgIIAgAAAA==.',
Am='Amenrah:BAAANQADCgQIBAAAAA==.',
An='Androse:BAAANQAECgQIBAAAAA==.',
Ap='Apollon:BAAANQAECgQIBAAAAA==.',
Ar='Argyle:BAAANQADCggIDgAAAA==.Arilu:BAAANQAECgEIAQAAAA==.Arkerite:BAAANQADCggIDwAAAA==.Aruj:BAAANQADCgcIDAAAAA==.',
As='Ashkari:BAAANQAECgIIAgAAAA==.Astrea:BAAANQADCgEIAQAAAA==.',
Au='Auphelia:BAAANQADCgMIAwAAAA==.',
Av='Aviendho:BAAANQADCgMIAwAAAA==.',
Ay='Ayhanu:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.',
Az='Azmythr:BAAANQAECgUIBgAAAA==.Azzaerial:BAAANQADCgIIAgAAAA==.Azzrael:BAAANQADCgEIAQAAAA==.',
Ba='Barto:BAAANQADCggICAAAAA==.Baxterpala:BAAANQADCgUIBQAAAA==.',
Be='Beyondthedk:BAAANQADCgcIBwAAAA==.',
Bi='Bigkahunas:BAAANQAECgQICgAAAA==.Bigman:BAAANQADCgQIBAAAAA==.Bignut:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Bigzacky:BAAANQAECgMIAwAAAA==.Bilcaster:BAAANQADCggIDAAAAA==.',
Bl='Bladlast:BAAANQADCggIDwAAAA==.Blankee:BAAANQAECgcIDAAAAA==.Blankey:BAAANQAECgYICQAAAA==.Bloodraven:BAAANQAECgIIAgAAAA==.',
Bo='Bombisevil:BAAANQAECgcICgAAAA==.Booz:BAAANQADCgEIAQABNQABCgQIBAABAAAAAA==.Booze:BAAANQAECgYICgABNQABCgQIBAABAAAAAA==.Bophades:BAAANQADCgYICwAAAA==.Borgîr:BAAANQAECgEIAgAAAA==.Bossee:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Bowfdeez:BAAANQADCgEIAQAAAA==.',
Br='Bracven:BAAANQADCgYICgAAAA==.Bradadin:BAAANQADCgcIDAAAAA==.Braydor:BAAANQABCgQIBgAAAA==.Brusque:BAAANQADCgUIBQAAAA==.',
Bu='Bubblerus:BAAANQADCgYIBgAAAA==.Buzzlightwgt:BAAANQABCgIIBAAAAA==.',
Ca='Caitastrophe:BAAANQAECgEIAQAAAA==.Calyssta:BAAANQAECgMIBAAAAA==.Cantbeatcook:BAAANQADCgYICwABNQADCggIEAABAAAAAA==.Cantou:BAAANQAECgEIAQAAAA==.Captcosmo:BAAANQADCgcIDQAAAA==.',
Ch='Chaosbrand:BAAANQAECgYICQAAAA==.Chickenfried:BAAANQADCgYIBgAAAA==.Chico:BAAANQADCgcIDgAAAA==.Chithris:BAAANQADCgYICgAAAA==.Chodoge:BAAANQAECgUIBwAAAA==.Chopsooey:BAAANQADCgQICAAAAA==.Chrisdk:BAAANQADCgcICgAAAA==.Chungi:BAAANQADCgYICAAAAA==.',
Ci='Ciimagi:BAAANQAECgMIBAAAAA==.Cirno:BAAANQAECgIIAgAAAA==.',
Cl='Clawsome:BAAANQADCgUIBQAAAA==.Cleetarus:BAAANQAECgIIAwAAAA==.Clíché:BAAANQADCgYICwAAAA==.',
Co='Cocodiablo:BAAANQAECgIIAwAAAA==.Constantino:BAAANQADCggIDgAAAA==.Copenshock:BAAANQADCggIDwAAAA==.Coraa:BAAANQADCggIDgAAAA==.',
Cr='Creammachine:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Creepsly:BAAANQADCgMIAwAAAA==.',
Da='Dagobert:BAAANQADCggICgAAAA==.Damien:BAAANQADCggIDgAAAA==.Daolin:BAAANQADCgQIBAAAAA==.Darkian:BAAANQAECgQIBAAAAA==.Dasani:BAAANQAECgIIAgAAAA==.Davinia:BAAANQADCgcIBwAAAA==.',
De='Dean:BAAANQAECgIIAgAAAA==.Decidurus:BAAANQADCgIIAgAAAA==.Deithknight:BAAANQADCgUIBQAAAA==.Demoncook:BAAANQADCggIEAAAAA==.Demono:BAAANQADCgYIBgAAAA==.Demons:BAAANQADCgEIAQAAAA==.Denishath:BAAANQABCgEIAQAAAA==.Depression:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Desalination:BAAANQADCggICQABNQAECgYICgABAAAAAA==.Deusvûlt:BAAANQADCggIEQAAAA==.Deyjavaknadi:BAAANQADCgIIAwAAAA==.',
Di='Digitalis:BAAANQADCgEIAQAAAA==.Dikaiosýni:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Diona:BAAANQADCggIDQAAAA==.Disco:BAAANQAECgcIDAAAAA==.Divinesmite:BAAANQADCggICQAAAA==.',
Dk='Dkandy:BAAANQAECgIIAgAAAA==.Dkykin:BAAANQAECgYIBwAAAA==.',
Do='Dotsrus:BAAANQAECgQIBAAAAA==.Downfawl:BAAANQAECgIIAgABNQAECgUIBgABAAAAAA==.',
Dr='Dracculus:BAAANQADCgcIBwAAAA==.Draginballz:BAAANQAECgEIAQAAAA==.Drakthor:BAAANQAECgQIBwAAAA==.Draxus:BAAANQADCggICAAAAA==.Dregar:BAAANQADCggIDgAAAA==.Drstab:BAAANQADCgYICgAAAA==.',
Du='Duck:BAAANQADCgYICwAAAA==.Dundrin:BAAANQADCgIIAgAAAA==.Durf:BAAANQADCgcICgAAAA==.Duska:BAAANQADCggIDgAAAA==.',
Dy='Dyondra:BAAANQADCggIDQAAAA==.Dyspare:BAAANQADCgIIAgAAAA==.',
['Dî']='Dîmmu:BAAANQADCgYICAAAAA==.',
Ea='Eatchikn:BAAANQAECgEIAQAAAA==.',
Ed='Edah:BAAANQADCggICQAAAA==.',
Ee='Eevah:BAAANQAECgEIAQAAAA==.',
El='Elepanda:BAAANQAECgIIAgAAAA==.Eleventeen:BAAANQAECgIIAgAAAA==.Elosai:BAAANQADCggIDgAAAA==.',
Em='Emesis:BAAANQADCgUIBQAAAA==.',
Es='Eseri:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Esreaver:BAAANQADCgcIDgAAAA==.',
Fa='Fangaxe:BAAANQAECgcIDQAAAA==.Fangbane:BAAANQADCgUIBQAAAA==.',
Fe='Felaequitas:BAAANQADCgUIBQAAAA==.Fentastic:BAAANQAECgEIAQAAAA==.Fentrock:BAAANQAECgIIAgAAAA==.',
Fi='Fisticuffs:BAAANQAECgEIAQAAAA==.',
Fl='Floshotmoo:BAAANQADCggIDgAAAA==.',
Fr='Fragii:BAAANQAECgQIBAAAAA==.',
Ga='Galaxum:BAAANQADCgEIAQAAAA==.Garana:BAAANQAECgEIAQAAAA==.Garzha:BAAANQADCgYIDAAAAA==.',
Ge='Gehenna:BAAANQADCgUIBwAAAA==.Gershas:BAAANQAECgQIBgAAAA==.Gezebel:BAAANQADCggIDwAAAA==.',
Gh='Ghiberti:BAAANQAECgEIAQAAAA==.Ghouldamn:BAAANQADCgcIDAAAAA==.Ghðst:BAAANQADCggIDgAAAA==.',
Gl='Glarghal:BAAANQAECgYICAAAAA==.Glasscanon:BAAANQADCggICQAAAA==.',
Gn='Gnomagi:BAAANQADCgMIAwAAAA==.',
Go='Gokuu:BAAANQAECgIIAgAAAA==.Golnada:BAAANQAECgQICAAAAA==.Goosily:BAAANQABCgIIAgAAAA==.',
Gr='Grapebevrage:BAAANQADCgYIBwAAAA==.Greentouch:BAAANQADCgQIBAAAAA==.Grewt:BAAANQAECgUIBgAAAA==.Grögin:BAAANQAECgEIAQAAAA==.',
Gw='Gwashington:BAAANQADCgcICwAAAA==.',
['Gò']='Gòòse:BAAANQAECgMIBAAAAA==.',
Ha='Halestormdh:BAAANQAECgQIBAAAAA==.Hate:BAAANQADCgYICwAAAA==.Hathaw:BAAANQADCgUIBQAAAA==.Hayhay:BAAANQADCggIDwAAAA==.',
He='Herja:BAAANQADCgUIBwAAAA==.Hey:BAAANQADCgYIBgAAAA==.',
Hi='Hidebound:BAAANQAECgIIAgAAAA==.',
Ho='Hobgoblinn:BAAANQAECgcIDAAAAA==.Hodordog:BAAANQADCgYIBgAAAA==.Holydiver:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Honeydutchtv:BAAANQAECgcIDQAAAA==.Hopezbanyruu:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.Hopezblinky:BAAANQADCgIIAgABNQAECgYIBwABAAAAAA==.Hopezherbz:BAAANQAECgYIBwAAAA==.Hordecore:BAAANQADCgQIBQAAAA==.',
Hu='Hugedonut:BAAANQAECgIIAgAAAA==.',
Hy='Hypojin:BAAANQAECgIIAgAAAA==.',
Ic='Iceaged:BAAANQAECgMIBAAAAA==.',
Il='Illos:BAAANQADCggIDgAAAA==.',
Im='Imheated:BAAANQADCgYIBgAAAA==.',
It='Itadori:BAAANQADCgUIBwABNQAECgIIAgABAAAAAA==.Itheron:BAAANQADCgUIBQAAAA==.',
Jb='Jbandzz:BAAANQADCgIIAgAAAA==.',
Je='Jessbae:BAAANQADCggIDwAAAA==.Jessibelle:BAAANQAECgEIAQAAAA==.Jez:BAAANQADCgIIAwAAAA==.',
Ji='Jimmypage:BAAANQAECgQIBQAAAA==.',
Ju='Juicedmoose:BAAANQADCggIDwAAAA==.Junundu:BAAANQAECgQIBAAAAA==.',
Ka='Kaelissa:BAAANQADCgQIBAAAAA==.Kaelstrada:BAAANQAECgEIAQAAAA==.Kaendndeydra:BAAANQADCgQIBgAAAA==.Kaennä:BAAANQADCgcIDQAAAA==.Kailash:BAAANQADCgUIBgAAAA==.Kallivan:BAAANQADCgUICQABNQAECgQIBQABAAAAAA==.Karmasuture:BAAANQAECgMIAwAAAA==.Karmasuturè:BAAANQADCgcIBwAAAA==.Karmasuturé:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kattah:BAAANQADCgcIDAAAAA==.Kavikk:BAAANQAECgQIBAAAAA==.',
Ke='Keymaster:BAAANQADCgYIBgAAAA==.',
Kh='Kharmod:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Ki='Kindrella:BAAANQAECgIIAgAAAA==.',
Kn='Knoctürnal:BAAANQAECgUIBgAAAA==.',
Ko='Kootiekween:BAAANQADCgYIBwAAAA==.Kotetsu:BAAANQAECgEIAQAAAA==.Koufax:BAAANQAECgcIAwAAAA==.Kozzy:BAAANQAECgIIAgAAAA==.',
Ky='Kylisse:BAAANQADCgUICAAAAA==.',
La='Labrys:BAAANQADCgcIBwAAAA==.Lasagna:BAAANQADCgYICAAAAA==.Lastina:BAAANQADCgcIBwAAAA==.Lazypos:BAAANQADCgQIBAAAAA==.',
Le='Leecy:BAAANQAECgIIAgAAAA==.',
Li='Limpytof:BAAANQADCgEIAQAAAA==.Litehand:BAAANQADCgcIDAAAAA==.Lizbeth:BAAANQABCgMIAwAAAA==.',
Ll='Lliana:BAAANQABCgIIBAAAAA==.',
Lo='Lockrian:BAAANQAECgQICAAAAA==.Locose:BAAANQAECgYICwAAAA==.Lolrush:BAAANQAECgYICQAAAA==.Longstrongg:BAAANQADCgQIBQAAAA==.Lovetea:BAAANQAECgEIAgAAAA==.Loxier:BAAANQAECgIIAgAAAA==.',
Lu='Lugosh:BAAANQADCgQIBwAAAA==.Lumendevout:BAAANQADCgUIBQAAAA==.Lumenshift:BAAANQAECgEIAQAAAA==.Lunaumbra:BAAANQADCgUIBQAAAA==.',
Ly='Lyall:BAAANQADCggICQAAAA==.Lyrnn:BAAANQAECgIIAgAAAA==.',
['Lø']='Løveshøck:BAAANQADCgYICAABNQAECgEIAgABAAAAAA==.',
Ma='Madheallz:BAAANQADCgMIAwAAAA==.Madsand:BAAANQADCgIIAwAAAA==.Magecook:BAAANQADCgcICgABNQADCggIEAABAAAAAA==.Mainmoon:BAAANQAECgIIAgAAAA==.Majinmuu:BAAANQAECgIIAgAAAA==.Malchor:BAAANQAECgIIAgAAAA==.Manyas:BAAANQADCgUIBQAAAA==.Maolin:BAAANQADCggIDQAAAA==.',
Me='Megabonk:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Megthepriest:BAAANQAECgEIAQAAAA==.Menotorp:BAAANQADCgIIAgAAAA==.Mercifer:BAAANQADCgIIAgAAAA==.',
Mi='Micha:BAAANQAECgIIAQABNQAECgYICgABAAAAAA==.Mightduy:BAAANQAECgIIAwAAAA==.',
Mo='Monkheals:BAAANQAECgEIAQAAAA==.Moontzu:BAAANQADCgYICgAAAA==.Morik:BAAANQADCgUICQAAAA==.Morph:BAAANQADCggICAAAAA==.',
Mu='Muscles:BAAANQAECgIIAwAAAA==.Muspel:BAAANQADCgMIAwAAAA==.',
['Mò']='Mòon:BAAANQAECgUIBgAAAA==.',
Na='Narios:BAAANQAECgEIAgAAAA==.',
Ne='Nephthys:BAAANQAECgcICwAAAA==.Nerubus:BAAANQADCggIDgAAAA==.Neso:BAAANQADCgYICgAAAA==.Nexkaa:BAAANQAECgcIDQAAAA==.',
Ni='Nimbus:BAAANQADCggICAAAAA==.Nimi:BAEANQAECgIIAgAAAA==.Nindara:BAAANQADCggIDgAAAA==.',
No='Nokonda:BAAANQADCgMIAwAAAA==.Nonhealer:BAAANQADCggICwAAAA==.Novå:BAAANQAECgQIBAAAAA==.',
Og='Ogopogo:BAAANQADCgUIBQAAAA==.',
Ol='Olcadan:BAAANQADCgMIAwAAAA==.Oliandia:BAAANQADCgcIDQAAAA==.',
On='Onlydans:BAAANQAECgIIAgAAAA==.Onlyslams:BAAANQAECgQIBAAAAA==.',
Or='Ordani:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Orm:BAAANQAECgIIAgAAAA==.',
Ou='Ouilyjambon:BAAANQAECgIIAgABNQAECggIDgABAAAAAA==.',
Ov='Overlordzor:BAAANQADCgQIBQAAAA==.',
Pa='Palanth:BAAANQADCgYICgAAAA==.Panorama:BAAANQAECgIIAgAAAA==.Patrik:BAAANQADCgUICQAAAA==.',
Pe='Pearlzinha:BAAANQAECgEIAQAAAA==.Peonanoob:BAAANQADCgYIBgAAAA==.',
Ph='Phuga:BAAANQADCggIDgAAAA==.',
Po='Poets:BAAANQADCggICAAAAA==.Ponix:BAAANQADCgMIBAAAAA==.',
Pr='Preservasian:BAAANQADCgcICgAAAA==.Prettyfrosty:BAAANQADCgcICQAAAA==.',
Pu='Puffsummons:BAAANQADCggIDwAAAA==.Purify:BAAANQAECgIIAgAAAA==.Puxxyslayer:BAAANQADCgYIBgAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Py='Pyrannor:BAAANQADCgcICQAAAA==.',
Qu='Quinifer:BAAANQAECgUIBgAAAA==.Quintera:BAAANQADCgYIBgAAAA==.',
Ra='Radamantys:BAAANQAECgMIBQAAAA==.Ravensword:BAAANQAECgEIAQAAAA==.Razdurin:BAAANQADCgUICQAAAA==.Razenseth:BAAANQAECgUIBgAAAA==.',
Re='Relanne:BAAANQADCgIIAgAAAA==.Restorasian:BAAANQAECgIIBAAAAA==.Retnewb:BAAANQAECgEIAQAAAA==.Revecca:BAAANQADCgQIBAAAAA==.',
Ro='Rokrin:BAAANQAECgEIAQAAAA==.Roleplay:BAAANQAECgEIAQAAAA==.Rorindar:BAAANQADCgMIAwAAAA==.Rose:BAAANQAECgMIBAAAAA==.Rowsdower:BAAANQADCggIDQAAAA==.',
Ru='Rubez:BAAANQAECgEIAQAAAA==.Rulia:BAAANQADCggICwAAAA==.',
['Rí']='Rínzler:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.',
Sa='Saerah:BAAANQADCgcIDAAAAA==.Sandya:BAAANQADCgYIBgAAAA==.Sans:BAAANQAECgQIBgAAAA==.Saphea:BAAANQAECgQIBAAAAA==.Sathrenus:BAAANQADCgYICgAAAA==.',
Sc='Scarletraven:BAAANQADCggIDgAAAA==.',
Se='Seifer:BAAANQADCgcIDAAAAA==.Selistras:BAAANQADCgcIDAAAAA==.',
Sh='Shammÿ:BAAANQAECgYICAAAAA==.Shedim:BAAANQABCgIIBAAAAA==.Shocktea:BAAANQADCgUIBQAAAA==.Shovelhead:BAAANQADCgUIBwAAAA==.Shunt:BAAANQADCgEIAQAAAA==.Shylachase:BAAANQADCgMIAwAAAA==.Shyllamae:BAAANQADCgYIBgAAAA==.',
Si='Sinisterion:BAAANQADCgcIBwABNQAECgUIBgABAAAAAA==.',
Sk='Skybreaker:BAAANQADCgUIBQABNQAECgYICQABAAAAAA==.Skylane:BAAANQADCgcICAAAAA==.',
Sn='Snanth:BAAANQAECgQIBAAAAA==.Sniperq:BAAANQAECgEIAgAAAA==.Snowcreeks:BAAANQADCgcIDAAAAA==.Snurbin:BAAANQADCgEIAQAAAA==.Snuudle:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.',
Sp='Spalling:BAAANQADCgcIBwAAAA==.Spleenless:BAAANQADCgYIBgAAAA==.Spoon:BAEANQADCggICQAAAA==.',
St='Starcommand:BAAANQADCggIDgAAAA==.Steelhide:BAAANQADCggIDgAAAA==.Stoopedholy:BAAANQADCggIDQABNQAECggIDgABAAAAAA==.Stubborn:BAAANQAECgMIAwAAAA==.',
Su='Sumata:BAAANQAECgEIAQAAAA==.Sumato:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Sy='Syllata:BAAANQAECgUIBgAAAA==.Sylvianna:BAAANQAECgIIAgAAAA==.',
Ta='Tadra:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Taladen:BAAANQADCgcIBwAAAA==.Tanwynn:BAAANQADCgIIAgAAAA==.Tayswiftie:BAAANQADCggIAgAAAA==.',
Te='Tenneland:BAAANQADCgUIBQAAAA==.Teppic:BAAANQAECgIIAgAAAA==.Terawar:BAAANQAECgIIAgAAAA==.Tetadesanti:BAAANQADCgcIDgAAAA==.',
Th='Thebadthing:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Thenazalth:BAAANQADCgEIAQAAAA==.Therealmundy:BAAANQADCgUIBQAAAA==.Thundron:BAAANQAECgQIBQAAAA==.',
Ti='Tiandrel:BAAANQADCgMIAwAAAA==.Tiny:BAAANQAECgEIAQAAAA==.Tizzt:BAAANQABCgQIBAAAAA==.',
To='Toper:BAAANQADCgQIBAAAAA==.Torrak:BAAANQADCgMIAwAAAA==.Totenschein:BAAANQADCgcIBwABNQADCgYIBgABAAAAAA==.',
Tr='Travisaur:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Trixibell:BAAANQAECgEIAQAAAA==.',
Ty='Tylethian:BAAANQADCgUIBQAAAA==.',
Un='Uninterested:BAAANQAECgEIAQAAAA==.',
Ur='Urudeathcow:BAAANQADCgUIBQAAAA==.Urver:BAAANQAECgMIAwAAAA==.',
Us='Username:BAAANQADCgcICAAAAA==.',
Va='Vaelendrii:BAAANQADCgQIBQAAAA==.',
Ve='Veeronica:BAAANQADCgIIAwAAAA==.',
Vh='Vhx:BAAANQADCggIDgAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Vixelle:BAAANQADCgUIBQAAAA==.',
Vl='Vladski:BAAANQADCgcICwAAAA==.',
Vo='Voidspauun:BAAANQADCgcIDQAAAA==.Vortsex:BAAANQADCgcICgAAAA==.',
['Vï']='Vïxenô:BAAANQAECgYICAAAAA==.',
Wa='Warxiez:BAAANQADCgUIBQAAAA==.',
Wh='Whirt:BAAANQAECgIIAgAAAA==.',
Wi='Widowmaker:BAAANQAECgQIBgAAAA==.Wigglez:BAAANQADCgQIBQAAAA==.Williece:BAAANQABCgQIBgAAAA==.Wishes:BAAANQABCgQIAgAAAA==.',
Xa='Xandine:BAAANQABCgIIBAAAAA==.Xavilic:BAAANQAECgEIAQAAAA==.',
Yo='Yonbon:BAAANQADCgUICAAAAA==.',
Za='Zahlxr:BAAANQAECgEIAQAAAA==.Zappyboy:BAAANQAECgMIAwAAAA==.',
Ze='Zeero:BAAANQADCgcIDAAAAA==.Zeraphole:BAAANQADCggIDgAAAA==.Zergturts:BAAANQAECgEIAQAAAA==.Zethryx:BAAANQADCggIDQAAAA==.',
Zi='Zif:BAAANQAECgEIAQAAAA==.',
Zm='Zmamaz:BAAANQADCggICgAAAA==.',
Zo='Zoidbergmd:BAAANQAECgQIBAAAAA==.Zomat:BAAANQADCgYIBgAAAA==.Zoob:BAAANQADCgYIBgABNQABCgQIBAABAAAAAA==.Zorbrix:BAAANQAECgIIAgAAAA==.',
Zu='Zulgeteb:BAAANQADCgcICwAAAA==.',
Zy='Zy:BAAANQAECgQICAABNQAFFAIIAwABAAAAAA==.Zynner:BAAANQAECgcICwAAAA==.',
Zz='Zztank:BAAANQADCgcIDgAAAA==.',
['Zí']='Zí:BAAANQADCgcICAAAAA==.',
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
