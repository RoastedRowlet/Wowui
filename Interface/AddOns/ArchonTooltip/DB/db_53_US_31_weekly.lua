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

local lookup = {'Unknown-Unknown','Mage-Frost','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Warrior-Protection','Shaman-Elemental','Paladin-Retribution','Mage-Arcane','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarkan:BAAANQAECgMIBAAAAA==.',
Ac='Acanialyn:BAAANQADCgYICwAAAA==.',
Ad='Adea:BAAANQAECgUICQAAAA==.',
Ae='Aeiro:BAAANQAECgQIBgAAAA==.Aetheriel:BAAANQADCggIFAAAAA==.',
Ai='Aireez:BAAANQADCgUIBQAAAA==.Airrin:BAAANQADCgcIEAAAAA==.',
Aj='Ajoseywales:BAAANQAECgUICAAAAA==.',
Ak='Akatala:BAAANQAECgYIBwAAAA==.Akunda:BAAANQAECgIIAgAAAA==.',
Al='Alamaania:BAAANQAECgEIAQAAAA==.Alaterial:BAAANQADCgUIBQAAAA==.Aloha:BAAANQAFFAEIAQAAAA==.Aluriel:BAAANQAECgYICAAAAA==.',
Am='Ambellína:BAAANQADCgcIBwAAAA==.Amenrah:BAAANQADCgQIBAAAAA==.',
An='Androse:BAAANQAECgYICwAAAA==.',
Ap='Apollon:BAAANQAECgQIBAAAAA==.',
Ar='Arclîght:BAAANQAECgMIAwAAAA==.Argyle:BAAANQAECgEIAQAAAA==.Arilu:BAAANQAECgEIAgAAAA==.Arkerite:BAAANQADCggIDwAAAA==.Aruj:BAAANQADCggIFAAAAA==.',
As='Ashkari:BAAANQAECgQIBgAAAA==.Astrea:BAAANQADCgEIAQAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Auphelia:BAAANQADCgQIBQAAAA==.',
Av='Aviendho:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Ay='Ayhanu:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Ayllata:BAAANQADCggICAAAAA==.',
Az='Azmythr:BAAANQAFFAEIAQAAAA==.Azzaerial:BAAANQADCgIIAgAAAA==.Azzrael:BAAANQADCgEIAQAAAA==.',
Ba='Barto:BAAANQADCggICAAAAA==.Baxterpala:BAAANQADCgUIBQAAAA==.',
Be='Benosh:BAAANQADCgcIBwAAAA==.Betræÿer:BAAANQADCgUIBQAAAA==.Beyondthedk:BAAANQAECgEIAQAAAA==.',
Bi='Bigkahunas:BAAANQAECgYIEQAAAA==.Bigman:BAAANQADCgQIBAAAAA==.Bignut:BAAANQADCgYICwABNQAECgUICgABAAAAAA==.Bigzacky:BAAANQAECgUICAAAAA==.Bilcaster:BAAANQAECgMIAwAAAA==.',
Bj='Björntorock:BAAANQADCggICAAAAA==.',
Bl='Bladlast:BAAANQAECgIIAgAAAA==.Blankee:BAABNQAECoEXAAICAAkJriUOAADeAwACAAkJriUOAADeAwAAAA==.Blankey:BAAANQAECgYICQAAAA==.Bloodraven:BAAANQAECgIIBAAAAA==.Bloomthetank:BAAANQADCgQIBAAAAA==.',
Bo='Bombisevil:BAAANQAFFAEIAQAAAA==.Booz:BAAANQADCgEIAQABNQABCgQIBAABAAAAAA==.Booze:BAAANQAECgcIEQABNQABCgQIBAABAAAAAA==.Bophades:BAAANQADCgYICwAAAA==.Borgîr:BAAANQAECgUIBwAAAA==.Bossee:BAAANQAECgQIBQABNQAECgkJFwACAK4lAA==.Bowfdeez:BAAANQADCggICQAAAA==.',
Br='Bracven:BAAANQADCgYICgAAAA==.Bradadin:BAAANQADCgcIEQAAAA==.Bralex:BAAANQABCgIIAgAAAA==.Braydor:BAAANQADCgQIBAAAAA==.Broggzal:BAAANQADCgYICwAAAA==.Bruisy:BAAANQAECgMIAwABNQABCgQIBAABAAAAAA==.Brusque:BAAANQADCgYICwAAAA==.',
Bu='Bubblerus:BAAANQAECgQIAwAAAA==.Bubbleturts:BAAANQAECgQIBAAAAA==.Bullpal:BAAANQADCgUIBQAAAA==.Buzzlightwgt:BAAANQABCgIIBAAAAA==.',
Bw='Bwomdalah:BAAANQADCgQIBAAAAA==.Bwonurmomdi:BAAANQADCgYICAAAAA==.',
Ca='Caffeineboy:BAAANQABCgIIBAAAAA==.Caitastrophe:BAAANQAECgMIBAAAAA==.Calyssta:BAAANQAECgQICAAAAA==.Cantbeatcook:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Cantou:BAAANQAECgUIBgAAAA==.Captcosmo:BAAANQAECgEIAQAAAA==.',
Ch='Chaosbrand:BAAANQAECgYIDgAAAA==.Chickenfried:BAAANQADCgcICgAAAA==.Chico:BAAANQAECgQIBAAAAA==.Chillax:BAAANQAECgEIAQAAAA==.Chithris:BAAANQADCgcIEQAAAA==.Chodoge:BAAANQAECgcIDgAAAA==.Chopsooey:BAAANQADCgUIDQAAAA==.Chrisdk:BAAANQADCgcIDQAAAA==.Chungi:BAAANQADCgYICgAAAA==.',
Ci='Ciimagi:BAAANQAECgUICQAAAA==.Cirno:BAAANQAECgIIBAAAAA==.',
Cl='Clamcast:BAAANQABCgQIBAAAAA==.Clawsome:BAAANQADCgUIBQAAAA==.Cleetarus:BAAANQAECgYICgAAAA==.Clíché:BAAANQADCgcIEgAAAA==.',
Co='Cocodiablo:BAAANQAECgYICQAAAA==.Consecrasian:BAAANQADCgcIBwAAAA==.Constantino:BAAANQAECgEIAQAAAA==.Copenshock:BAAANQAECgIIAgAAAA==.Coraa:BAAANQAECgMIAwAAAA==.',
Cr='Creammachine:BAAANQADCgQIBgABNQAECgUICgABAAAAAA==.Creepsly:BAAANQADCgMIAwAAAA==.',
Cu='Curseddemon:BAAANQADCgYIBgAAAA==.Cursedpsyko:BAAANQABCgEIAQAAAA==.',
Da='Daddee:BAEANQADCgMIAwABNQAECgQIBQABAAAAAA==.Dagobert:BAAANQAECgIIAgAAAA==.Damien:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.Daolin:BAAANQADCgQIBAAAAA==.Darkian:BAAANQAECgQIBAAAAA==.Dasani:BAAANQAECgUIBgAAAA==.Davinia:BAAANQAECgEIAQAAAA==.',
De='Dean:BAAANQAECgIIBAAAAA==.Deathsidhe:BAAANQAECggIBgAAAA==.Decidurus:BAAANQADCgIIAgAAAA==.Deithknight:BAAANQADCggICgAAAA==.Demonchainz:BAAANQADCggIDAAAAA==.Demoncook:BAAANQAECgEIAQAAAA==.Demono:BAAANQADCggIDgAAAA==.Demons:BAAANQADCgYIBwAAAA==.Denishath:BAAANQABCgEIAQAAAA==.Depression:BAAANQAECgEIAQABNQAECgkJGgADAF0jAA==.Desalination:BAAANQADCggICQABNQAFFAEIAQABAAAAAA==.Desiusrye:BAAANQAECgIIAgAAAA==.Deusvûlt:BAAANQAECggIAQAAAA==.Deyjavaknadi:BAAANQADCgQIBwAAAA==.',
Di='Digitalis:BAAANQADCgEIAQAAAA==.Dikaiosýni:BAAANQADCgEIAQABNQAECgMIBAABAAAAAA==.Diona:BAAANQADCggIDQAAAA==.Disco:BAABNQAECoEXAAMEAAkJliWmAADAAwAEAAkJECWmAADAAwAFAAgJTR1+AQC+AgAAAA==.Divinesmite:BAAANQAECgMIAwAAAA==.',
Dk='Dkandy:BAAANQAECgQIBgAAAA==.Dkykin:BAAANQAECgcIDgAAAA==.',
Do='Dotsrus:BAAANQAECgQICAAAAA==.Downfawl:BAAANQAECgQIBgABNQAECgcIDQABAAAAAA==.',
Dr='Dracculus:BAAANQAECgEIAQAAAA==.Draginballz:BAAANQAECgEIAQAAAA==.Drakthor:BAAANQAECgQIBwAAAA==.Draxus:BAAANQADCggICAAAAA==.Dregar:BAAANQAECgUIBQAAAA==.Drogamel:BAAANQADCgEIAQAAAA==.Drstab:BAAANQADCgcIEQAAAA==.Drágám:BAAANQADCggICAAAAA==.',
Du='Duck:BAAANQADCgYICwAAAA==.Dundrin:BAAANQADCgIIAgAAAA==.Durf:BAAANQAECgEIAQAAAA==.Duska:BAAANQAECgEIAQAAAA==.',
Dy='Dyondra:BAAANQADCggIFQAAAA==.Dyspare:BAAANQAECgEIAQAAAA==.',
['Dî']='Dîmmu:BAAANQADCgYICAAAAA==.',
Ea='Eatchikn:BAAANQAECgQIBQAAAA==.',
Ed='Edah:BAAANQADCggIDwAAAA==.',
Ee='Eevah:BAAANQAECgMIBAAAAA==.',
El='Elementsmash:BAAANQADCgYIBgAAAA==.Elepanda:BAAANQAECgMIBQAAAA==.Eleventeen:BAAANQAECgIIBAAAAA==.Elosai:BAAANQADCggIDgAAAA==.',
Em='Emesis:BAAANQADCgUIBQAAAA==.',
Es='Eseri:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Esreaver:BAAANQADCggIEgAAAA==.',
Fa='Failing:BAAANQADCgEIAQABNQADCgcIEgABAAAAAA==.Fangaxe:BAABNQAECoEYAAIGAAkJUyDWAABxAwAGAAkJUyDWAABxAwAAAA==.',
Fe='Felaequitas:BAAANQAECgQIBgAAAA==.Feltaco:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Fentastic:BAAANQAECgEIAQAAAA==.Fentrock:BAAANQAECgYICAAAAA==.',
Fi='Fisticuffs:BAAANQAECgQIBQAAAA==.',
Fl='Flameburg:BAAANQADCgQIBAAAAA==.Floshotmoo:BAAANQAECgIIAgAAAA==.',
Fr='Fragii:BAAANQAECgUICQAAAA==.',
Ga='Galaxum:BAAANQADCgEIAQAAAA==.Garana:BAAANQAECgEIAQABNQADCgYIDAABAAAAAA==.Garzha:BAAANQADCgYIDAAAAA==.',
Ge='Gehenna:BAAANQADCgYICAAAAA==.Gelado:BAAANQADCgUIBQAAAA==.Gershas:BAAANQAECgcIDQAAAA==.Gezebel:BAAANQADCggIFwAAAA==.',
Gh='Ghiberti:BAAANQAECgQIBAAAAA==.Ghouldamn:BAAANQADCggIFAAAAA==.Ghðst:BAAANQAECgIIAgAAAA==.',
Gl='Glarghal:BAAANQAECgcIDwAAAA==.Glasscanon:BAAANQADCggIEgAAAA==.',
Gn='Gnomagi:BAAANQADCgMIAwAAAA==.',
Go='Gokuu:BAAANQAECgQIBQAAAA==.Golnada:BAAANQAECgQIDgAAAA==.Goodmamita:BAAANQADCgQIBAAAAA==.Gooseymane:BAAANQADCgcIBwAAAA==.Goosily:BAAANQADCgEIAQAAAA==.',
Gr='Grapebevrage:BAAANQAECgIIAgAAAA==.Greentouch:BAAANQADCgQIBAAAAA==.Grewt:BAAANQAECgcIDQAAAA==.Grögin:BAAANQAECgMIBAAAAA==.',
Gu='Gulunga:BAAANQADCgEIAQAAAA==.',
Gw='Gwashington:BAAANQAECgEIAQAAAA==.',
['Gò']='Gòòse:BAAANQAECgMIBAAAAA==.',
Ha='Halestormdh:BAAANQAECgYICgAAAA==.Hate:BAAANQADCggIEwAAAA==.Hathaw:BAAANQADCgYICwAAAA==.Hayhay:BAAANQADCggIFwAAAA==.',
He='Herja:BAAANQADCgcICgAAAA==.Hey:BAAANQADCgYIBgAAAA==.',
Hi='Hidebound:BAAANQAECgIIAgAAAA==.Hisouka:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.',
Ho='Hobgoblinn:BAABNQAECoEWAAIHAAkJYBgpDgDTAgAHAAkJYBgpDgDTAgAAAA==.Hodordog:BAAANQAECgEIAQAAAA==.Holybel:BAAANQADCgQIBAAAAA==.Holydiver:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Honeydutchtv:BAABNQAECoEYAAIIAAkJSh9TCQAqAwAIAAkJSh9TCQAqAwAAAA==.Hopezbanyruu:BAAANQAECgYIBgABNQAECgYICAABAAAAAA==.Hopezblinky:BAAANQAECgQIBAABNQAECgYICAABAAAAAA==.Hopezherbz:BAAANQAECgYICAAAAA==.Hordecore:BAAANQADCgYICwAAAA==.',
Hu='Hugedonut:BAAANQAECgYICAAAAA==.',
Hy='Hypojin:BAAANQAECgMIBQAAAA==.',
Ic='Iceaged:BAAANQAECgQICwAAAA==.',
Il='Illos:BAAANQAECgQIBAAAAA==.',
Im='Imheated:BAAANQAECgcIBwAAAA==.',
It='Itadori:BAAANQAECgIIAgABNQAECgUIBgABAAAAAA==.Itheron:BAAANQADCgUIBQAAAA==.',
Ja='Jacknsally:BAAANQAECgIIAgAAAA==.',
Jb='Jbandzz:BAAANQADCgYICAAAAA==.Jbruner:BAAANQADCgIIAQAAAA==.',
Je='Jessbae:BAAANQAECgIIAgAAAA==.Jessibelle:BAAANQAECgQIBQAAAA==.Jez:BAAANQADCgQIBwAAAA==.Jezeel:BAAANQAECggIBgAAAA==.',
Ji='Jimmypage:BAAANQAECgUICgAAAA==.',
Ju='Juicedmoose:BAAANQAECgIIAgAAAA==.Junundu:BAAANQAECgQIBAAAAA==.',
Ka='Kaelissa:BAAANQADCgQIBAAAAA==.Kaelisse:BAAANQADCgQIBAAAAA==.Kaelstrada:BAAANQAECgMIBAAAAA==.Kaendndeydra:BAAANQADCgQIBgAAAA==.Kaennä:BAAANQAECgIIAgAAAA==.Kailash:BAAANQADCgUIBgAAAA==.Kaldorlon:BAAANQADCgcIBwAAAA==.Kallivan:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Kandakai:BAAANQADCgIIAgAAAA==.Karmageddon:BAAANQADCgcIBwAAAA==.Karmasuture:BAAANQAECgMIAwAAAA==.Karmasuturè:BAAANQAECggIBwAAAA==.Karmasuturé:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kasha:BAAANQADCgEIAQAAAA==.Kattah:BAAANQADCggIFAAAAA==.Kavikk:BAAANQAECgQIBwAAAA==.',
Ke='Keestermon:BAAANQADCgQIBAAAAA==.Kenbo:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Keymaster:BAAANQAECgEIAQAAAA==.',
Kh='Kharmod:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Ki='Kindrella:BAAANQAECgYICAAAAA==.',
Kn='Knoctürnal:BAAANQAECgcIDwAAAA==.',
Ko='Kootiekween:BAAANQADCgcICQAAAA==.Kotetsu:BAAANQAECgQIBQAAAA==.Koufax:BAAANQAECgcIAwAAAA==.Kozzmo:BAAANQADCgMIAwAAAA==.Kozzy:BAAANQAECgIIBAAAAA==.',
Kr='Krellian:BAAANQAECgIIAgAAAA==.',
Ky='Kylene:BAAANQADCgMIAwAAAA==.Kylisse:BAAANQADCgcIDwAAAA==.Kyma:BAAANQAECgIIAgAAAA==.',
La='Labrys:BAAANQAECgEIAQAAAA==.Laolin:BAAANQADCgYIBgAAAA==.Lasagna:BAAANQAECgIIAgAAAA==.Lastina:BAAANQAECgEIAQAAAA==.Lazypos:BAAANQADCgYICQAAAA==.',
Le='Leecy:BAAANQAECgUICAAAAA==.Lelianne:BAAANQADCgUIBQAAAA==.Lewa:BAAANQADCgYICAAAAA==.',
Li='Limpytof:BAAANQADCgEIAQAAAA==.Linzalina:BAAANQAECgQIBAAAAA==.Litehand:BAAANQADCggIDgAAAA==.Lixandrya:BAAANQADCgQIBAAAAA==.Lizbeth:BAAANQABCgYICQAAAA==.',
Ll='Lliana:BAAANQABCgIIBAAAAA==.',
Lo='Lockrian:BAAANQAECgQICgAAAA==.Locktober:BAAANQADCgUIBQAAAA==.Locose:BAAANQAFFAEIAQAAAA==.Lolrush:BAAANQAFFAEIAQAAAA==.Longstrongg:BAAANQADCgUIBgAAAA==.Lostdragon:BAAANQADCgEIAQAAAA==.Lovetea:BAAANQAECgUIBwAAAA==.Loxier:BAAANQAECgUIBwAAAA==.',
Lu='Lugosh:BAAANQADCgQICgAAAA==.Lumendevout:BAAANQADCgUIBQAAAA==.Lumenshift:BAAANQAECgMIBAAAAA==.Lunaumbra:BAAANQADCgcIBwAAAA==.',
Ly='Lyall:BAAANQAECgQIBAAAAA==.Lyrnn:BAAANQAECgQIBgAAAA==.',
['Lé']='Léx:BAAANQAECgIIAgAAAA==.',
['Lø']='Løveshøck:BAAANQADCggIEAABNQAECgUIBwABAAAAAA==.',
Ma='Maddman:BAAANQADCgIIAgAAAA==.Madheallz:BAAANQADCgQIBAAAAA==.Madsand:BAAANQADCgQIBwAAAA==.Magecook:BAAANQADCgcICwABNQAECgEIAQABAAAAAA==.Mainmoon:BAAANQAECgYICAAAAA==.Majinmuu:BAAANQAECgIIBAAAAA==.Malchor:BAAANQAECgQIBgAAAA==.Manyas:BAAANQADCgUICAAAAA==.Maolin:BAAANQADCggIEwAAAA==.',
Me='Megabonk:BAAANQAECgQIBwAAAA==.Megthepriest:BAAANQAECgMIBAAAAA==.Menge:BAAANQADCgUIBQAAAA==.Menotorp:BAAANQADCgIIAgAAAA==.Mercifer:BAAANQADCgUIBgAAAA==.',
Mi='Micha:BAAANQAECgEIAgABNQAECgcIEQABAAAAAA==.Mightduy:BAAANQAECgQIBwAAAA==.',
Mo='Moistbimbo:BAAANQABCgYIBQAAAA==.Monkheals:BAAANQAECgEIAQAAAA==.Moontzu:BAAANQADCgYIEAAAAA==.Morik:BAAANQADCgUIDQAAAA==.Morph:BAAANQAECgMIAwAAAA==.Mosha:BAAANQADCgQIBAAAAA==.',
Mu='Muscles:BAAANQAECgIIBQAAAA==.Muspel:BAAANQADCgMIAwAAAA==.',
['Mò']='Mòon:BAAANQAECgcICwAAAA==.',
Na='Narios:BAAANQAECgEIAgAAAA==.Nate:BAAANQAFFAEIAQAAAA==.',
Ne='Nephthys:BAAANQAECggIEAAAAA==.Nerubus:BAAANQAECgQIBAAAAA==.Neso:BAAANQADCgcIEQAAAA==.Nexkaa:BAABNQAECoEYAAIJAAkJJCGcCgBoAwAJAAkJJCGcCgBoAwAAAA==.',
Ni='Niissia:BAAANQADCggICAAAAA==.Nimbus:BAAANQAECgIIAgABNQAECgkJTAAHAE4kAA==.Nimi:BAEANQAECgQIBgAAAA==.Nindara:BAAANQAECgEIAQAAAA==.',
No='Nokonda:BAAANQADCgMIAwAAAA==.Nonhealer:BAAANQAECgIIAgAAAA==.Norisse:BAAANQADCgYIBgAAAA==.Novå:BAAANQAECgQIBAAAAA==.',
Og='Ogopogo:BAAANQADCgUIBQAAAA==.',
Ol='Olcadan:BAAANQADCgYICQAAAA==.Oliandia:BAAANQADCgcIDQABNQAECgMIBAABAAAAAA==.',
On='Onlydans:BAAANQAECgQIBgAAAA==.Onlyslams:BAAANQAECgQIBQABNQAECgQIBwABAAAAAA==.',
Or='Ordani:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Orm:BAAANQAECgQIBgAAAA==.',
Ou='Ouilyjambon:BAAANQAECgIIAwABNQAECgkJGAAKAPAgAA==.',
Ov='Overlordzor:BAAANQADCgQIBQAAAA==.',
Pa='Palanth:BAAANQADCgYIDgAAAA==.Panorama:BAAANQAECgQIBgAAAA==.Patrik:BAAANQAECgIIAgAAAA==.',
Pe='Pearlzinha:BAAANQAECgEIAQAAAA==.Peonanoob:BAAANQADCgYIBgAAAA==.',
Ph='Phuga:BAAANQADCggIDgAAAA==.',
Po='Poets:BAAANQAECgYIBgAAAA==.Ponix:BAAANQADCgMIBAAAAA==.',
Pr='Preservasian:BAAANQADCgcIDQAAAA==.Prettyfrosty:BAAANQAECgEIAQAAAA==.',
Ps='Psykolight:BAAANQABCgQIBQAAAA==.',
Pu='Puffsummons:BAAANQAECgIIAgAAAA==.Purify:BAAANQAECgIIBAAAAA==.Puxxyslayer:BAAANQADCgYIDAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Py='Pyrannor:BAAANQADCggIEQAAAA==.Pyx:BAAANQADCggICAAAAA==.',
Qu='Quinifer:BAAANQAECgcIDQAAAA==.Quintera:BAAANQADCgYIBgAAAA==.',
Ra='Raau:BAAANQADCgQIBgABNQAECgYICgABAAAAAA==.Radamantys:BAAANQAECgYICwAAAA==.Ravensword:BAAANQAECgEIAQAAAA==.Razdurin:BAAANQADCgcIEQAAAA==.Razenseth:BAAANQAECgcIDQAAAA==.',
Re='Regenerate:BAAANQAECgUIBQAAAA==.Relanne:BAAANQADCgYICAAAAA==.Restorasian:BAAANQAECgYICgAAAA==.Retnewb:BAAANQAECgQIBQAAAA==.Revecca:BAAANQADCgQIBAAAAA==.',
Rh='Rhaskos:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.',
Ro='Robeartoe:BAAANQADCgYIBgAAAA==.Rokrin:BAAANQAECgQIBQAAAA==.Roleplay:BAAANQAECgMIAwAAAA==.Rorindar:BAAANQAECgIIAgAAAA==.Rose:BAAANQAECgQICAAAAA==.Rowsdower:BAAANQAECgIIAgAAAA==.',
Ru='Rubez:BAAANQAECgQIBQAAAA==.Rulia:BAAANQADCggICwAAAA==.',
['Rí']='Rínzler:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.',
Sa='Saerah:BAAANQADCgcIEwAAAA==.Sandya:BAAANQADCgYIDAAAAA==.Sans:BAAANQAECgYICwAAAA==.Saphea:BAAANQAECgUICQAAAA==.Sathrenus:BAAANQADCgYICgAAAA==.',
Sc='Scarletraven:BAAANQAECgIIAgAAAA==.',
Se='Seifer:BAAANQAECgEIAQAAAA==.Selistras:BAAANQAECgEIAQAAAA==.Selri:BAAANQADCgQIBAAAAA==.',
Sh='Shadø:BAAANQADCgMIAwAAAA==.Shammÿ:BAAANQAECgYIDgAAAA==.Shedim:BAAANQABCgIIBAAAAA==.Shiftinman:BAAANQADCgYIBgAAAA==.Shocktea:BAAANQADCgYICwAAAA==.Shovelhead:BAAANQADCgUICQAAAA==.Shunt:BAAANQADCgIIAgAAAA==.Shylachase:BAAANQADCgMIAwAAAA==.Shyllamae:BAAANQADCggIDgAAAA==.',
Si='Sinisterion:BAAANQADCgcIDgABNQAECgcIDwABAAAAAA==.',
Sk='Skybreaker:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.Skylane:BAAANQADCggIEAAAAA==.',
Sn='Snacck:BAAANQADCgcIBwAAAA==.Snanth:BAAANQAECgYICgAAAA==.Sniperq:BAAANQAECgEIAgAAAA==.Snowcreeks:BAAANQADCggIFAAAAA==.Snurbin:BAAANQADCgEIAQAAAA==.Snuudle:BAAANQAECggICQAAAA==.',
So='Sonniy:BAAANQADCgEIAQAAAA==.',
Sp='Spalling:BAAANQADCggIDQAAAA==.Spleenless:BAAANQADCgYIBgAAAA==.Spoon:BAEANQAECgQIBQAAAA==.',
St='Starcommand:BAAANQADCggIFQAAAA==.Steelhide:BAAANQAECgEIAQAAAA==.Stoopedholy:BAAANQAECgEIAQABNQAECgkJFwALAHQdAA==.Stubborn:BAAANQAECgUICAAAAA==.Stubborndk:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.',
Su='Sumata:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Sumato:BAAANQAECgMIBAAAAA==.',
Sy='Syllata:BAAANQAECgcIDQAAAA==.Sylvianna:BAAANQAECgYICAAAAA==.',
Ta='Tadra:BAAANQADCgYICgABNQAECgcICwABAAAAAA==.Taladen:BAAANQADCggICQAAAA==.Tanwynn:BAAANQADCgcICQAAAA==.Tayswiftie:BAAANQADCggIAgAAAA==.',
Te='Tenebrion:BAAANQADCgcIBwAAAA==.Tenneland:BAAANQADCgUIBQAAAA==.Teppic:BAAANQAECgYICAAAAA==.Terawar:BAAANQAECgQIBAAAAA==.Terrorîst:BAAANQABCgYIDAABNQADCgcIEgABAAAAAA==.Tetadesanti:BAAANQAECgEIAQAAAA==.',
Th='Thebadthing:BAAANQADCgUICQABNQAECgYICAABAAAAAA==.Thenazalth:BAAANQAECgEIAQAAAA==.Therealmundy:BAAANQADCgUIBQAAAA==.Therla:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.Thuggish:BAAANQADCgYIBgAAAA==.Thunderbum:BAAANQADCgUIBQAAAA==.Thundron:BAAANQAECgYICwAAAA==.',
Ti='Tiandrel:BAAANQADCgMIAwAAAA==.Tiny:BAAANQAECgMIAwAAAA==.Tinydingo:BAAANQADCgYIBgAAAA==.Tinysham:BAAANQADCggICAAAAA==.Tizzt:BAAANQABCgQICAABNQAECgEIAQABAAAAAA==.',
To='Tooktalligo:BAAANQADCgEIAQAAAA==.Toper:BAAANQADCgQIBAAAAA==.Torrak:BAAANQADCgMIAwAAAA==.Totenschein:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.',
Tr='Travisaur:BAAANQADCgIIAgABNQAECgYICAABAAAAAA==.Trixibell:BAAANQAECgIIAwAAAA==.',
Ty='Tylethian:BAAANQADCgUIBQAAAA==.',
Un='Uninterested:BAAANQAECgYIBwAAAA==.',
Ur='Urudeathcow:BAAANQADCgYICwAAAA==.Urver:BAAANQAECgUIBgAAAA==.',
Us='Username:BAAANQAECgEIAgAAAA==.',
Va='Vaelendrii:BAAANQADCgUICgAAAA==.',
Ve='Veeronica:BAAANQADCgMIBAAAAA==.Venomlock:BAAANQADCgUIBQAAAA==.',
Vh='Vhx:BAAANQADCggIDgAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Vixelle:BAAANQADCgYICwAAAA==.',
Vl='Vladski:BAAANQAECgEIAQAAAA==.',
Vo='Voidspauun:BAAANQAECgMIAwAAAA==.Vortsex:BAAANQAECgEIAQAAAA==.',
['Vï']='Vïxenô:BAAANQAECgYIDgAAAA==.',
Wa='Warxiez:BAAANQADCgUIBQAAAA==.Washiki:BAAANQADCgcIBwAAAA==.',
Wh='Whirt:BAAANQAECgQIBgAAAA==.',
Wi='Widowmaker:BAAANQAECgQICgAAAA==.Wigglez:BAAANQADCgYICwAAAA==.Williece:BAAANQABCgQICAAAAA==.Wishes:BAAANQABCgUICQAAAA==.',
Wo='Wocalax:BAAANQADCgQIBAAAAA==.',
Xa='Xandine:BAAANQABCgIIBAAAAA==.Xavilic:BAAANQAECgMIBAAAAA==.',
Xm='Xmaxpower:BAAANQADCgcICAAAAA==.',
Yo='Yonbon:BAAANQADCgYIDgAAAA==.',
Za='Zahlxr:BAAANQAECgMIBAAAAA==.Zappyboy:BAAANQAECgYICAAAAA==.Zapraz:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.',
Ze='Zeero:BAAANQAECgYIBgAAAA==.Zeraphole:BAAANQADCggIDgAAAA==.Zergturts:BAAANQAECgUIBgAAAA==.Zerolith:BAAANQADCggICAAAAA==.Zethryx:BAAANQADCggIDQAAAA==.',
Zi='Zif:BAAANQAECgQIBQAAAA==.',
Zm='Zmamaz:BAAANQAECgMIAwAAAA==.',
Zo='Zoidbergmd:BAAANQAECgcIEQAAAA==.Zomat:BAAANQADCgYIBgAAAA==.Zoob:BAAANQADCgYIBgABNQABCgQIBAABAAAAAA==.Zorbrix:BAAANQAECgQIBgAAAA==.',
Zr='Zrre:BAAANQABCgIIAgAAAA==.',
Zu='Zulgeteb:BAAANQADCggIEwAAAA==.',
Zy='Zy:BAAANQAECgQICAABNQAFFAUICAAMAAIYAA==.Zynner:BAAANQAECgcIEgABNQABCgQIAwABAAAAAA==.',
Zz='Zztank:BAAANQAECgIIAgAAAA==.',
['Zí']='Zí:BAAANQADCgcIDwAAAA==.',
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
