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

local lookup = {'Unknown-Unknown','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Mage-Frost','Hunter-Survival','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Warrior-Protection','Shaman-Elemental','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Mage-Arcane','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Warlock-Destruction','DemonHunter-Devourer',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aarkan:BAAANQAECgQICAAAAA==.',
Ac='Acaelis:BAAANQADCgIIAgAAAA==.Acanialyn:BAAANQADCgYICwAAAA==.',
Ad='Adamastora:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Adea:BAAANQAECgUIDgAAAA==.',
Ae='Aeiro:BAAANQAECgQICgAAAA==.Aetheriel:BAAANQAECgEIAQAAAA==.',
Ai='Aireez:BAAANQADCgUIBQAAAA==.Airrin:BAAANQADCggIFwAAAA==.',
Aj='Ajoseywales:BAAANQAECgcIDwAAAA==.',
Ak='Akatala:BAAANQAECgYICQAAAA==.Akunda:BAAANQAECgIIAgAAAA==.',
Al='Alamaania:BAAANQAECgMIBAAAAA==.Alaterial:BAAANQADCgUIBQAAAA==.Alexz:BAAANQADCgEIAQAAAA==.Aloha:BAABNQAECoEdAAMCAAkJKSFQCABWAwACAAkJKSFQCABWAwADAAMJ7wzNMACbAAAAAA==.Aluriel:BAAANQAECgYIDgAAAA==.',
Am='Ambellína:BAAANQADCgcIBwAAAA==.Amenrah:BAAANQADCgQIBAAAAA==.',
An='Androse:BAAANQAECgcIEgAAAA==.',
Ap='Apollon:BAAANQAECgQIBAAAAA==.',
Ar='Arclîght:BAAANQAECgQIBwAAAA==.Argyle:BAAANQAECgEIAQAAAA==.Arilu:BAAANQAECgIIBAAAAA==.Arkerite:BAAANQADCggIDwAAAA==.Aruj:BAAANQAECgEIAQAAAA==.Aruz:BAAANQAECggICAAAAA==.',
As='Ashkari:BAAANQAECgQICgAAAA==.Astrea:BAAANQADCgEIAQAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Auphelia:BAAANQADCgQIBQAAAA==.',
Av='Aviendho:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Ay='Ayhanu:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.Ayllata:BAAANQAECgQICAAAAA==.',
Az='Azmythr:BAAANQAFFAMIBAAAAA==.Azzaerial:BAAANQADCgIIAgAAAA==.Azzrael:BAAANQADCgEIAQAAAA==.',
Ba='Barek:BAAANQAECgQICAAAAA==.Bartahk:BAAANQAECgcICAAAAA==.Barto:BAAANQADCggICAAAAA==.Baxtercham:BAAANQADCgUIBQABNQADCgQIBAABAAAAAA==.Baxterpala:BAAANQAECgIIAgAAAA==.',
Be='Belenn:BAAANQADCgIIAgAAAA==.Benosh:BAAANQADCgcICgAAAA==.Betræÿer:BAAANQAECgEIAQAAAA==.Beyondthedk:BAAANQAECgEIAQAAAA==.',
Bi='Bigkahunas:BAABNQAECoEbAAIEAAgJrxdsJQBtAgAEAAgJrxdsJQBtAgAAAA==.Bigman:BAAANQADCgQIBAAAAA==.Bignut:BAAANQADCgYICwABNQAECgYIEAABAAAAAA==.Bigzacky:BAAANQAECgYIDgAAAA==.Bilcaster:BAAANQAECgQIBwAAAA==.',
Bj='Björntorock:BAAANQADCggICAAAAA==.',
Bl='Bladlast:BAAANQAECgQIBgAAAA==.Blankee:BAABNQAECoEcAAIFAAkJsSUqAADJAwAFAAkJsSUqAADJAwAAAA==.Blankey:BAAANQAECgcIDAAAAA==.Blargo:BAAANQADCggICAAAAA==.Bloodraven:BAAANQAECgQICAAAAA==.Bloomthetank:BAAANQADCgQIBAAAAA==.',
Bo='Bombisevil:BAABNQAECoEbAAQEAAkJwB8NFwDBAgAEAAcJISINFwDBAgAGAAUJGh7bBQBYAQAHAAQJRg9LLAAEAQAAAA==.Booz:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.Booze:BAAANQAECggIEgABNQADCggICAABAAAAAA==.Bophades:BAAANQADCgYICwAAAA==.Borbadin:BAAANQAECgYIAgAAAA==.Borgîr:BAAANQAECgcIDgAAAA==.Bossee:BAAANQAECgYIBwABNQAECgkJHAAFALElAA==.Bowfdeez:BAAANQADCggICQAAAA==.',
Br='Bracven:BAAANQADCgYICgAAAA==.Bradadin:BAAANQAECgMIBgAAAA==.Bradmage:BAAANQADCgEIAQABNQAECgMIBgABAAAAAA==.Bralex:BAAANQABCgIIAgAAAA==.Braydor:BAAANQADCgQIBAAAAA==.Broggzal:BAAANQAECgMIAwAAAA==.Bruisy:BAAANQAECgMIAwABNQADCggICAABAAAAAA==.Brusque:BAAANQADCggIDQAAAA==.',
Bu='Bubblerus:BAAANQAECgQIBAAAAA==.Bubbleturts:BAAANQAECgQIBAAAAA==.Bullpal:BAAANQADCgUIBQAAAA==.Buzzlightwgt:BAAANQABCgIIBAAAAA==.',
Bw='Bwomdalah:BAAANQAECgEIAQAAAA==.Bwonurmomdi:BAAANQADCgYICAAAAA==.',
Ca='Caffeineboy:BAAANQABCgQIBgAAAA==.Caitastrophe:BAAANQAECgQICAAAAA==.Calyssta:BAAANQAECgQIDAAAAA==.Cantbeatcook:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.Cantou:BAAANQAECgYIDAAAAA==.Captcosmo:BAAANQAECgEIAQAAAA==.',
Ch='Chaosbrand:BAAANQAECgYIDgAAAA==.Chickenfried:BAAANQAECgEIAQAAAA==.Chico:BAAANQAECgQIBAAAAA==.Chillax:BAAANQAECgEIAQAAAA==.Chithris:BAAANQADCgcIEQAAAA==.Chodoge:BAABNQAECoEZAAMIAAgJHBs1CACUAgAIAAgJHBs1CACUAgAJAAQJCBJeIQD0AAAAAA==.Chopsooey:BAAANQADCgYIDgAAAA==.Chrisdk:BAAANQAECgIIAgAAAA==.Chungi:BAAANQADCgYICgAAAA==.',
Ci='Ciilokkar:BAAANQAECgMIAwABNQAECgYIDQABAAAAAA==.Ciimagi:BAAANQAECgYIDQAAAA==.Cirno:BAAANQAECgQICAAAAA==.',
Cl='Clamcast:BAAANQAECgYIBgAAAA==.Clawsome:BAAANQADCgUIBQAAAA==.Cleetarus:BAAANQAECgYIEwAAAA==.Clíché:BAAANQADCggIEwAAAA==.',
Co='Cocodiablo:BAAANQAECgYIDwAAAA==.Consecrasian:BAAANQADCgcIBwAAAA==.Constantino:BAAANQAECgIIAwAAAA==.Copenfist:BAAANQAECggICAAAAA==.Copenshock:BAAANQAECgQIBgABNQAECggICAABAAAAAA==.Coraa:BAAANQAECgQIBwAAAA==.',
Cr='Creammachine:BAAANQAECgQIBAABNQAECgYIEAABAAAAAA==.Creepsly:BAAANQADCgMIAwAAAA==.',
Cu='Curseddemon:BAAANQADCgYIBgAAAA==.Cursedpsyko:BAAANQABCgEIAQAAAA==.',
Cw='Cwem:BAAANQADCgUIBQAAAA==.',
Da='Daddee:BAEANQADCgMIAwABNQAECgUIDgABAAAAAA==.Dagobert:BAAANQAECgQIBwAAAA==.Damien:BAAANQADCggIDgABNQAECgQIBgABAAAAAA==.Daolin:BAAANQADCgQIBAAAAA==.Darkian:BAAANQAECgQIBAAAAA==.Dasani:BAAANQAECgUIBgAAAA==.Davinia:BAAANQAECgIIAwAAAA==.',
De='Dean:BAAANQAECgYICgAAAA==.Deathsidhe:BAAANQAECggIBgAAAA==.Decidurus:BAAANQADCgIIAgAAAA==.Deithknight:BAAANQADCggICgAAAA==.Demonchainz:BAAANQADCggIFAAAAA==.Demoncook:BAAANQAECgIIAwABNQAECgQIBAABAAAAAA==.Demono:BAAANQAECgQIBAAAAA==.Demons:BAAANQAECgEIAQAAAA==.Denishath:BAAANQABCgEIAQAAAA==.Depression:BAAANQAECgcICAABNQAFFAQIBwAKAJgUAA==.Desalination:BAAANQADCggICQABNQAECgkJHQACACkhAA==.Desiusrye:BAAANQAECgQIBgAAAA==.Deusvûlt:BAAANQAECggIAQAAAA==.Deyjavaknadi:BAAANQADCgQICwAAAA==.Deûsvûlt:BAAANQAECggIAgAAAA==.',
Di='Digitalis:BAAANQADCgcICAAAAA==.Dikaiosýni:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.Diona:BAAANQADCggIDQAAAA==.Disco:BAABNQAECoEcAAMLAAkJliVTAgCQAwALAAkJVyVTAgCQAwAMAAgJTR0EAgCzAgAAAA==.Divinesmite:BAAANQAECgQICAAAAA==.',
Dk='Dkandy:BAAANQAECgYIDAAAAA==.Dkykin:BAABNQAECoEZAAICAAkJJiD5CwAjAwACAAkJJiD5CwAjAwAAAA==.',
Do='Dotsrus:BAAANQAECgQIDAAAAA==.Downfawl:BAAANQAECgUICwABNQAECggIFgACADAdAA==.',
Dr='Dracculus:BAAANQAECgIIAwAAAA==.Draginballz:BAAANQAECgQIBQAAAA==.Drakthor:BAAANQAECgQIBwAAAA==.Draxus:BAAANQADCggICAAAAA==.Dregar:BAAANQAECgYICwAAAA==.Drogamel:BAAANQADCgEIAQAAAA==.Drstab:BAAANQAECgMIAwAAAA==.Drágám:BAAANQADCggICAAAAA==.',
Du='Duck:BAAANQADCgcIEgAAAA==.Dundrin:BAAANQADCgIIAgAAAA==.Durf:BAAANQAECgEIAQAAAA==.Duska:BAAANQAECgMIBAAAAA==.',
Dy='Dyondra:BAAANQAECgIIAgAAAA==.Dyspare:BAAANQAECgEIAQAAAA==.',
['Dî']='Dîmmu:BAAANQADCggIEAAAAA==.',
Ea='Eatchikn:BAAANQAECgUICgAAAA==.',
Ed='Edah:BAAANQADCggIDwAAAA==.',
Ee='Eeblez:BAAANQADCgEIAQAAAA==.Eevah:BAAANQAECgQICAAAAA==.',
El='Elementsmash:BAAANQAECgIIAgAAAA==.Elepanda:BAAANQAECgMIBgAAAA==.Eleventeen:BAAANQAECgYICgAAAA==.Ellipsisfear:BAAANQADCgUIBQAAAA==.Elosai:BAAANQADCggIDgAAAA==.',
Em='Emesis:BAAANQADCgUIBQAAAA==.',
Es='Eseri:BAAANQAECgQIBQABNQAECgcICgABAAAAAA==.Esreaver:BAAANQADCggIEgAAAA==.',
Fa='Failing:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Fangaxe:BAABNQAECoEaAAINAAkJXyCSAQBgAwANAAkJXyCSAQBgAwAAAA==.Fangbane:BAAANQAECgUIBQAAAA==.',
Fe='Felaequitas:BAAANQAECgYICgAAAA==.Feltaco:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Fentastic:BAAANQAECgEIAQAAAA==.Fentrock:BAAANQAECgYICAAAAA==.',
Fi='Fisticuffs:BAAANQAECgUICgAAAA==.',
Fl='Flameburg:BAAANQADCgQIBAAAAA==.Floshotmoo:BAAANQAECgQIBgAAAA==.',
Fo='Foxytotem:BAAANQADCggIBQAAAA==.',
Fr='Fragii:BAAANQAECgYIDwAAAA==.Frierenn:BAAANQADCgYIBgAAAA==.Friggi:BAAANQADCggICAAAAA==.',
Ga='Galakrond:BAAANQADCgIIAgAAAA==.Galaxum:BAAANQADCgEIAQAAAA==.Galford:BAAANQADCgMIAwAAAA==.Garana:BAAANQAECgEIAQABNQADCgYIDAABAAAAAA==.Garzha:BAAANQADCgYIDAAAAA==.Gaypoc:BAAANQADCggICAAAAA==.',
Ge='Gehenna:BAAANQAECgQIBAAAAA==.Gelado:BAAANQADCgYIBgAAAA==.Gershas:BAAANQAECgcIDwAAAA==.Gezebel:BAAANQADCggIFwAAAA==.',
Gh='Ghiberti:BAAANQAECgQIBAAAAA==.Ghouldamn:BAAANQADCggIHAAAAA==.Ghðst:BAAANQAECgQIBgAAAA==.',
Gl='Glarghal:BAABNQAECoEZAAILAAgJlh5fFACjAgALAAgJlh5fFACjAgAAAA==.Glasscanon:BAAANQADCggIGAAAAA==.',
Gn='Gnomagi:BAAANQADCgMIAwAAAA==.',
Go='Gokuu:BAAANQAECgQIBQAAAA==.Golnada:BAAANQAECgUIEwAAAA==.Goodmamita:BAAANQADCgQIBAAAAA==.Gooseymane:BAAANQADCgcIBwAAAA==.Goosily:BAAANQADCgEIAQAAAA==.',
Gr='Grapebevrage:BAAANQAECgQIBgAAAA==.Greentouch:BAAANQADCgQIBAAAAA==.Grewt:BAABNQAECoEWAAICAAgJMB0IFgClAgACAAgJMB0IFgClAgAAAA==.Grögin:BAAANQAECgQICAAAAA==.',
Gu='Gulunga:BAAANQAECgMIAwAAAA==.',
Gw='Gwashington:BAAANQAECgQIBQAAAA==.',
Ha='Halestormdh:BAAANQAECgcIEQAAAA==.Hate:BAAANQADCggIGQAAAA==.Hathaw:BAAANQADCggIDQAAAA==.Hayhay:BAAANQADCggIFwAAAA==.',
He='Herja:BAAANQADCgcICgAAAA==.Hey:BAAANQADCgYIBgAAAA==.',
Hi='Hidebound:BAAANQAECgQIBgAAAA==.Hisouka:BAAANQAECgQIBwABNQAECgYIEQABAAAAAA==.',
Ho='Hobgoblinn:BAABNQAECoEeAAIOAAkJRhoCFADdAgAOAAkJRhoCFADdAgAAAA==.Hodordog:BAAANQAECgMIBAAAAA==.Holybel:BAAANQADCgQIBAAAAA==.Holydiver:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.Holydragon:BAAANQABCgYIBwAAAA==.Honeydutchtv:BAABNQAECoEaAAIPAAkJICHBEgAKAwAPAAkJICHBEgAKAwAAAA==.Hopezbanyruu:BAAANQAECgYIBgABNQAECgYICAABAAAAAA==.Hopezblinky:BAAANQAECgQIBgABNQAECgYICAABAAAAAA==.Hopezherbz:BAAANQAECgYICAAAAA==.Hordecore:BAAANQADCgYIEQAAAA==.Horsebananas:BAAANQADCgcIBgABNQAECgQIBAABAAAAAA==.',
Hu='Hugedonut:BAAANQAECgYIDgAAAA==.',
Hy='Hypojin:BAAANQAECgQICQAAAA==.',
Ic='Iceaged:BAAANQAECgQIDwAAAA==.',
Il='Illos:BAAANQAECgUICQAAAA==.',
Im='Imheated:BAAANQAECggICgAAAA==.',
In='Integra:BAAANQAECgQIBAAAAA==.',
It='Itadori:BAAANQAECgIIAgABNQAECgUIBgABAAAAAA==.Itheron:BAAANQADCgUIBQAAAA==.',
Ja='Jacknsally:BAAANQAECgIIAgAAAA==.',
Jb='Jbandzz:BAAANQADCgYICAAAAA==.Jbruner:BAAANQADCgcICAAAAA==.',
Je='Jessbae:BAAANQAECgQIBgAAAA==.Jessibelle:BAAANQAECgUICgAAAA==.Jez:BAAANQADCgQICwAAAA==.Jezeel:BAAANQAECggIDgAAAA==.',
Ji='Jimmypage:BAAANQAECgYIEAAAAA==.',
Jo='Jonesstorm:BAAANQADCgMIAwAAAA==.',
Ju='Juicedmoose:BAAANQAECgQIBgAAAA==.Junundu:BAAANQAECggIBAAAAA==.',
Jv='Jvmec:BAAANQADCgEIAQAAAA==.',
Ka='Kaelissa:BAAANQADCgQIBAAAAA==.Kaelisse:BAAANQADCgQIBAAAAA==.Kaelstrada:BAAANQAECgQICAAAAA==.Kaendndeydra:BAAANQADCgQIBgAAAA==.Kaennä:BAAANQAECgQIBAAAAA==.Kailash:BAAANQAECgMIAwAAAA==.Kaldorlon:BAAANQADCgcIBwAAAA==.Kaldresden:BAAANQADCgUIBQAAAA==.Kallivan:BAAANQAECgQICAABNQAECgcIDAABAAAAAA==.Kandakai:BAAANQADCgIIAgAAAA==.Karmageddon:BAAANQADCgcIBwAAAA==.Karmasuture:BAAANQAECgMIAwAAAA==.Karmasuturè:BAAANQAECggIDgAAAA==.Karmasuturé:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kasha:BAAANQADCgEIAQAAAA==.Kattah:BAAANQAECgEIAQAAAA==.Kavikk:BAAANQAECgUICgAAAA==.',
Ke='Keestermon:BAAANQADCgQIBAAAAA==.Kenbo:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.Keymaster:BAAANQAECgIIAwAAAA==.',
Kh='Kharmod:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Ki='Kindrella:BAAANQAECgYICAAAAA==.Kirbe:BAAANQAECgQIBAAAAA==.',
Kn='Knoctürnal:BAABNQAECoEaAAMQAAgJGyBjCADgAgAQAAgJGyBjCADgAgARAAIJxgJrdgBSAAAAAA==.',
Ko='Kootiekween:BAAANQADCgcICwAAAA==.Kopaka:BAAANQADCgUIBQAAAA==.Kotetsu:BAAANQAECgYICwAAAA==.Koufax:BAAANQAECgcIAwAAAA==.Kozzmo:BAAANQADCgUICAAAAA==.Kozzy:BAAANQAECgQICAAAAA==.',
Kr='Krellian:BAAANQAECgIIAgAAAA==.',
Ky='Kylene:BAAANQADCgMIAwAAAA==.Kylisse:BAAANQADCgcIFQAAAA==.Kyma:BAAANQAECgQIBgAAAA==.',
La='Labrys:BAAANQAECgIIAwAAAA==.Laolin:BAAANQADCgYIBgAAAA==.Lasagna:BAAANQAECgQIBgAAAA==.Lastina:BAAANQAECgIIAwAAAA==.Lazypos:BAAANQADCgYIDwAAAA==.',
Le='Leecy:BAAANQAECgUIDgAAAA==.Lelianne:BAAANQADCgUIBQAAAA==.Lewa:BAAANQAECgUIBQAAAA==.',
Li='Limpytof:BAAANQADCgEIAQAAAA==.Linzalina:BAAANQAECgQICAAAAA==.Litehand:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.Lixandrya:BAAANQADCgcIBAAAAA==.Lizbeth:BAAANQABCgYIDQAAAA==.',
Ll='Lliana:BAAANQABCgIIBAAAAA==.',
Lo='Lockrian:BAAANQAECgQIDwAAAA==.Locktober:BAAANQADCgUIBQAAAA==.Locose:BAABNQAECoEbAAICAAkJPiJ3DAAbAwACAAkJPiJ3DAAbAwAAAA==.Lolrush:BAABNQAECoEYAAISAAkJ2QsEBgDVAQASAAkJ2QsEBgDVAQAAAA==.Longstrongg:BAAANQADCgUIBgAAAA==.Lostdragon:BAAANQAECgMIAwAAAA==.Lovetea:BAAANQAECgcIDgAAAA==.Loxier:BAAANQAECgYIDQAAAA==.',
Lu='Lugosh:BAAANQADCgQICgAAAA==.Lumendevout:BAAANQADCgUIBQAAAA==.Lumenshift:BAAANQAECgQICAAAAA==.Lunaumbra:BAAANQADCgcIBwAAAA==.',
Ly='Lyall:BAAANQAECgUICQAAAA==.Lyrnn:BAAANQAECgUICwAAAA==.',
['Lé']='Léx:BAAANQAECgIIAgAAAA==.',
['Lø']='Løveshøck:BAAANQADCggIGAABNQAECgcIDgABAAAAAA==.',
Ma='Maddman:BAAANQADCgIIAgAAAA==.Madheallz:BAAANQAECgEIAQAAAA==.Madsand:BAAANQADCgQICwAAAA==.Magecook:BAAANQAECgQIBAAAAA==.Mainmoon:BAAANQAECgYIDgAAAA==.Majinmuu:BAAANQAECgQICAAAAA==.Malchor:BAAANQAECgQICgAAAA==.Manyas:BAAANQADCgUIDAAAAA==.Maolin:BAAANQADCggIEwAAAA==.',
Me='Megabonk:BAAANQAECgQICQAAAA==.Megthepriest:BAAANQAECgQICAAAAA==.Menge:BAAANQADCgYIBgAAAA==.Menotorp:BAAANQADCgIIAgAAAA==.Mercifer:BAAANQADCgUIBgAAAA==.',
Mi='Micha:BAAANQAFFAEIAQAAAA==.Mightduy:BAAANQAECggIEAAAAA==.',
Mo='Moistbimbo:BAAANQABCgYIBgAAAA==.Monava:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Monkheals:BAAANQAECgEIAQAAAA==.Moontzu:BAAANQADCgYIFgAAAA==.Morik:BAAANQADCgUIDQABNQAECgQIBQABAAAAAA==.Morph:BAAANQAECgQIBwAAAA==.Mosha:BAAANQAECgIIAgAAAA==.',
Mu='Muscles:BAAANQAECgUICgAAAA==.Muspel:BAAANQADCgYICQAAAA==.',
My='Myrciless:BAAANQADCggIBwAAAA==.',
['Mò']='Mòon:BAAANQAECgcIEQAAAA==.',
Na='Narios:BAAANQAECgEIAgAAAA==.Nate:BAABNQAECoEcAAITAAkJkhqpLQDaAgATAAkJkhqpLQDaAgAAAA==.',
Ne='Nephthys:BAABNQAECoEaAAMHAAkJMB5WCAAKAwAHAAkJMB5WCAAKAwAGAAEJuArsCwA1AAAAAA==.Nerubus:BAAANQAECgUICQAAAA==.Neso:BAAANQAECgMIAwAAAA==.Nexkaa:BAABNQAECoEhAAITAAkJwyIYCQCVAwATAAkJwyIYCQCVAwAAAA==.',
Ni='Niissia:BAAANQADCggICAAAAA==.Nimbus:BAAANQAECggIDQABNQAECgkJTwAOAJckAA==.Nimi:BAEANQAECgQICgAAAA==.Nindara:BAAANQAECgQIBQAAAA==.',
No='Nokonda:BAAANQADCgMIAwAAAA==.Nonhealer:BAAANQAECgUIBwAAAA==.Norisse:BAAANQADCgYIDwAAAA==.Novå:BAAANQAECgQIBgAAAA==.',
Ob='Oballi:BAAANQADCggICAAAAA==.',
Og='Ogopogo:BAAANQADCgUIBQAAAA==.',
Ol='Olcadan:BAAANQADCgYICQAAAA==.Oliandia:BAAANQADCgcIDQABNQAECgQICAABAAAAAA==.',
On='Onlydans:BAAANQAECgQICgAAAA==.Onlyslams:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.',
Or='Ordani:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Orm:BAAANQAECgQICgAAAA==.',
Ou='Ouilyjambon:BAAANQAECgIIAwABNQAECgkJHwAUABcjAA==.',
Ov='Overlooker:BAAANQAECgEIAQAAAA==.Overlordzor:BAAANQADCgQIBQAAAA==.',
Pa='Palanth:BAAANQADCgYIDgAAAA==.Pannfried:BAAANQADCgEIAQAAAA==.Panorama:BAAANQAECgQIDQAAAA==.Pastor:BAAANQAECgIIAQABNQAFFAEIAQABAAAAAA==.Patrik:BAAANQAECgQIBgAAAA==.',
Pe='Pearlzinha:BAAANQAECgEIAQAAAA==.Peonanoob:BAAANQADCgYIBgAAAA==.',
Ph='Phrost:BAAANQABCgMIAwAAAA==.Phuga:BAAANQADCggIDgAAAA==.',
Po='Poets:BAAANQAECgcICAAAAA==.Ponix:BAAANQADCgMIBAAAAA==.',
Pr='Preservasian:BAAANQADCgcIDQAAAA==.Prettyfrosty:BAAANQAECgIIAwAAAA==.',
Ps='Psykolight:BAAANQABCgQIBQAAAA==.',
Pu='Puffsummons:BAAANQAECgQIBgAAAA==.Purify:BAAANQAECgQICAAAAA==.Puxxyslayer:BAAANQAECgIIAgAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Py='Pyrannor:BAAANQAECgIIAgAAAA==.Pyx:BAAANQADCggICAAAAA==.',
Qu='Quinifer:BAABNQAECoEYAAIRAAgJ0BmLGwBjAgARAAgJ0BmLGwBjAgAAAA==.Quintera:BAAANQADCgYIBgAAAA==.',
Ra='Raau:BAAANQADCgQIBgABNQAECgcIEQABAAAAAA==.Radamantys:BAAANQAECgYIEQAAAA==.Ravensword:BAAANQAECgEIAQAAAA==.Razdurin:BAAANQAECgMIAwAAAA==.Razenseth:BAABNQAECoEYAAIJAAgJjBx8CQCmAgAJAAgJjBx8CQCmAgAAAA==.',
Re='Regenerate:BAAANQAECgYICwAAAA==.Relanne:BAAANQAECgQIBAAAAA==.Restorasian:BAAANQAECgYIEAAAAA==.Retnewb:BAAANQAECgQICQAAAA==.Retpetition:BAAANQADCgIIAgAAAA==.Revecca:BAAANQADCgQIBAAAAA==.',
Rh='Rhaskos:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.',
Ri='Rikez:BAAANQAECgMIAwAAAA==.',
Ro='Robeartoe:BAAANQADCgYIBgAAAA==.Rokrin:BAAANQAECgYICwAAAA==.Roleplay:BAAANQAECgQIBgAAAA==.Rorindar:BAAANQAECgIIAgAAAA==.Rose:BAAANQAECgQICAAAAA==.Rowsdower:BAAANQAECgQIBgAAAA==.',
Ru='Rubez:BAAANQAECgUICgAAAA==.Rulia:BAAANQADCggICwAAAA==.',
['Rí']='Rínzler:BAAANQADCgYIDgABNQAECgEIAQABAAAAAA==.',
Sa='Saerah:BAAANQAECgQIBAAAAA==.Sandya:BAAANQADCgYIDAAAAA==.Sans:BAAANQAECgcIEAAAAA==.Saphea:BAAANQAECgYIDwAAAA==.Sathrenus:BAAANQADCgYIDgAAAA==.',
Sc='Scarletraven:BAAANQAECgQIBgAAAA==.',
Se='Seifer:BAAANQAECgEIAQAAAA==.Selistras:BAAANQAECgQIBAAAAA==.Selri:BAAANQADCgQICAAAAA==.',
Sh='Shadø:BAAANQADCgQIBwAAAA==.Shammÿ:BAABNQAECoEYAAIOAAgJaBs3GgCiAgAOAAgJaBs3GgCiAgAAAA==.Shedim:BAAANQABCgIIBAAAAA==.Shiftinman:BAAANQADCgYIBgAAAA==.Shocktea:BAAANQADCggIDQAAAA==.Shovelhead:BAAANQADCgUICQAAAA==.Shunt:BAAANQADCgIIAgAAAA==.Shylachase:BAAANQADCgMIAwAAAA==.Shyllamae:BAAANQADCggIFgAAAA==.',
Si='Sinisterion:BAAANQAECgEIAQABNQAECggIGgAQABsgAA==.',
Sk='Skybreaker:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.Skylane:BAAANQAECgEIAQAAAA==.',
Sn='Snacck:BAAANQAECgEIAQAAAA==.Snanth:BAAANQAECgYIEAAAAA==.Sniperq:BAAANQAECgEIAgAAAA==.Snowcreeks:BAAANQAECgEIAQAAAA==.Snurbin:BAAANQADCgEIAQAAAA==.Snuudle:BAAANQAECggIEQAAAA==.',
So='Sonniy:BAAANQADCgIIAgAAAA==.',
Sp='Spalling:BAAANQAECgIIAgAAAA==.Spleenless:BAAANQADCgcIBwAAAA==.Spoon:BAEANQAECgUIDgAAAA==.',
St='Starcommand:BAAANQADCggIHQAAAA==.Steelhide:BAAANQAECgIIAwAAAA==.Stoopedholy:BAAANQAECgQIBgABNQAFFAQICAAVAA0HAA==.Stubborn:BAAANQAECgYIDgAAAA==.Stubborndk:BAAANQAECgMIAwABNQAECgYIDgABAAAAAA==.',
Su='Sumata:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Sumato:BAAANQAECgQICAAAAA==.',
Sy='Syllata:BAABNQAECoEYAAIDAAgJtiHrBAASAwADAAgJtiHrBAASAwAAAA==.Sylvianna:BAAANQAECgYICAAAAA==.',
Ta='Tadra:BAAANQADCgYICgABNQAECgcIEQABAAAAAA==.Taladen:BAAANQADCggICQAAAA==.Talahon:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Tanwynn:BAAANQADCgcICQAAAA==.Tayswiftie:BAAANQADCggIAgAAAA==.',
Te='Tenebrion:BAAANQADCgcIBwAAAA==.Tenneland:BAAANQADCgUIBQAAAA==.Teppic:BAAANQAECgYIDgAAAA==.Terawar:BAAANQAECgQICAAAAA==.Terrorîst:BAAANQABCggIDgABNQAECgMIAwABAAAAAA==.Tetadesanti:BAAANQAECgQIBQAAAA==.',
Th='Thebadthing:BAAANQADCgUICQABNQAECgcIDwABAAAAAA==.Thenazalth:BAAANQAECgEIAQAAAA==.Therealmundy:BAAANQADCgUIBQAAAA==.Therla:BAAANQAECgIIAgAAAA==.Thuggish:BAAANQADCgYIBgAAAA==.Thunderbum:BAAANQADCgUIBQAAAA==.Thundron:BAAANQAECgcIDAAAAA==.',
Ti='Tiandrel:BAAANQADCgMIBAAAAA==.Tiny:BAAANQAECgMIAwAAAA==.Tinydingo:BAAANQAECgEIAQAAAA==.Tinysham:BAAANQADCggIEAAAAA==.Titamao:BAAANQADCgQIBAAAAA==.Tizzt:BAAANQABCgQICAABNQAECgEIAQABAAAAAA==.',
To='Tooktalligo:BAAANQADCgEIAQAAAA==.Toper:BAAANQADCgQIBAAAAA==.Torrak:BAAANQADCgMIAwAAAA==.Totenschein:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.',
Tr='Travisaur:BAAANQADCgQIBQABNQAECgcIDwABAAAAAA==.Trixibell:BAAANQAECgIIAwAAAA==.',
Ty='Tylethian:BAAANQADCgUIBQAAAA==.',
Un='Uninterested:BAAANQAECgYICQAAAA==.',
Ur='Urudeathcow:BAAANQADCggIDQAAAA==.Urupally:BAAANQADCgEIAQAAAA==.Urver:BAAANQAECgYIDAAAAA==.',
Us='Username:BAAANQAECgIIBAAAAA==.',
Va='Vaelendrii:BAAANQADCgUICgAAAA==.',
Ve='Veeronica:BAAANQADCgQIBQAAAA==.Venomlock:BAAANQADCgYICwAAAA==.Verst:BAAANQADCgcIBwAAAA==.',
Vh='Vhx:BAAANQADCggIDgAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Vixelle:BAAANQADCggIDQAAAA==.',
Vl='Vladski:BAAANQAECgQIBQAAAA==.',
Vo='Voidspauun:BAAANQAECgQIBwAAAA==.Vortsex:BAAANQAECgIIAwAAAA==.',
['Vï']='Vïxenô:BAABNQAECoEYAAIWAAgJjhqsHQBtAgAWAAgJjhqsHQBtAgAAAA==.',
Wa='Warxiez:BAAANQADCgUIBQAAAA==.Washiki:BAAANQADCgcIBwAAAA==.',
Wh='Whirt:BAAANQAECgQICgAAAA==.',
Wi='Widowmaker:BAAANQAECgYIEAAAAA==.Wigglez:BAAANQADCgYIEAAAAA==.Williece:BAAANQABCgQICAAAAA==.Wishes:BAAANQAECgMIAwAAAA==.',
Wo='Wocalax:BAAANQAECgIIAgAAAA==.',
Xa='Xandine:BAAANQABCgIIBAAAAA==.Xavilic:BAAANQAECgMIBAAAAA==.',
Xm='Xmaxpower:BAAANQAECgQIBAAAAA==.',
Yo='Yohei:BAAANQAECgEIAQAAAA==.Yonbon:BAAANQADCggIEAAAAA==.',
Za='Zahlxr:BAAANQAECgQICAAAAA==.Zappyboy:BAAANQAECgcIDwAAAA==.Zapraz:BAAANQAECgEIAQABNQAECgUICgABAAAAAA==.',
Ze='Zeero:BAAANQAECgYICQAAAA==.Zeraphole:BAAANQADCggIDgAAAA==.Zergturts:BAAANQAECgUICgAAAA==.Zerolith:BAAANQADCggICAAAAA==.Zethryx:BAAANQADCggIDQAAAA==.',
Zi='Zif:BAAANQAECgcIDAAAAA==.Zify:BAAANQADCgQIBAAAAA==.Zitalan:BAAANQADCggICAAAAA==.',
Zm='Zmamaz:BAAANQAECgQIBwAAAA==.',
Zo='Zoidbergmd:BAABNQAECoEjAAQVAAgJdxdPBwBYAQAUAAUJChYRVwBwAQAVAAUJHxRPBwBYAQAXAAIJbQ5dRgB2AAAAAA==.Zomat:BAAANQAECgEIAQAAAA==.Zoob:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Zorbrix:BAAANQAECgQICgAAAA==.',
Zr='Zrre:BAAANQADCggICAAAAA==.',
Zu='Zulgeteb:BAAANQAECgMIAwAAAA==.',
Zy='Zy:BAAANQAECgQICAABNQAFFAUICwAYAHEcAA==.Zynner:BAABNQAECoEcAAIHAAkJSB8bBwAhAwAHAAkJSB8bBwAhAwABNQABCgQIAwABAAAAAA==.',
Zz='Zztank:BAAANQAECgQIBgAAAA==.',
['Zí']='Zí:BAAANQAECgIIAgAAAA==.',
['Ça']='Çarnage:BAAANQADCgIIAgAAAA==.',
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
