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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Restoration','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Evoker-Preservation','Paladin-Retribution','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Evoker-Devastation','Druid-Guardian','DemonHunter-Havoc','Warrior-Arms','DemonHunter-Vengeance','Priest-Shadow','Paladin-Protection','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Druid-Feral','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Aberration:BAAANQADCgUIBQAAAA==.',
Ad='Addely:BAABNQAECn8WAAIBAAcKrg5Q+QCXAQABAAcKrg5Q+QCXAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgYIEQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgEJAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.',
Al='Alaralia:BAAANQAECggIEgABNQAFFAYIEQACAKwjAA==.Alarathel:BAAANQADCggICAABNQAFFAYIEQACAKwjAA==.Alyssandra:BAAANQAECgYIDgAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCggIEQAAAA==.Ammalane:BAAANQADCgQIBQABNQADCggIEQADAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.',
Ap='Apollyon:BAAANQAECggIDAAAAA==.',
Ar='Arangarr:BAABNQAECn8rAAIEAAkK8h2iCgAbAwAEAAkK8h2iCgAbAwAAAA==.Arcanu:BAAANQAECgEIAQAAAA==.Aresiuz:BAABNQAECn8XAAIFAAgK+hGWZgDnAQAFAAgK+hGWZgDnAQABNQAFFAYIEQAGAK0KAA==.Areyana:BAAANQAECgMIAwAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQAECgIIAwAAAA==.Arrietty:BAAANQAECgMICAAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAAANQAECgUICgAAAA==.',
At='Atlasfall:BAAANQAECgUIBgAAAA==.',
Az='Az:BAAANQAECgcIDAAAAA==.Azeriall:BAABNQAECn8tAAIHAAkK9BflOACQAgAHAAkK9BflOACQAgAAAA==.Azerodru:BAAANQADCgEIAQAAAA==.',
Ba='Bacnfen:BAAANQAECgYIDwAAAA==.Baconhammr:BAAANQADCggIFAAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAADAAAAAA==.Banshiï:BAAANQAECgYIDwAAAA==.Baratheøn:BAAANQAECgYIDgAAAA==.',
Be='Beeftard:BAABNQAECn8bAAIIAAgKmBuFNQCMAgAIAAgKmBuFNQCMAgAAAA==.',
Bi='Bifficus:BAAANQAECgEIAQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQAECgEIAwAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgUICgAAAA==.',
Bo='Bobbyg:BAAANQABCgYICwAAAA==.Bollace:BAAANQADCgUIBQABNQADCgcIBwADAAAAAA==.',
By='Byzantium:BAAANQAECgUIEgAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICAAAAA==.',
Ca='Caluu:BAAANQAECgIIBAAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAYIDwAJAK4SAA==.',
Ch='Chromatic:BAAANQAECgMIAwAAAA==.Chronic:BAAANQAECgIIAgABNQAECgkJIwAKAGYVAA==.',
Ci='Cinderflamez:BAAANQABCgMIAQAAAA==.',
Co='Coffeeblak:BAAANQADCgYICAAAAA==.Coldstorm:BAABNQAECn8gAAILAAkK4A4UDAD4AQALAAkK4A4UDAD4AQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAAANQAECgUIDQAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECn8tAAIMAAkKYxoUNgDGAgAMAAkKYxoUNgDGAgAAAA==.',
Da='Daddyelessar:BAAANQADCgYIDAAAAA==.Daemonfyre:BAAANQADCgEIAQAAAA==.Dafattyup:BAAANQAECgYIEQAAAA==.Dagon:BAAANQAECgEIAwAAAA==.Dagreenmeany:BAAANQADCggIOwAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Darruin:BAACNQAFFH8QAAINAAQKDiSfBwCeAQANAAQKDiSfBwCeAQA1AAQKfyoAAg0ACQqRJQoKAGsDAA0ACQqRJQoKAGsDAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQABCgIIAwAAAA==.Deathblitz:BAAANQAECgMIBQABNQAECggIDAADAAAAAA==.Deathlydruid:BAAANQADCgEIAQAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAAANQAECgUIDgAAAA==.Deeanndra:BAAANQAECgcIEgAAAA==.Demiz:BAABNQAECn8rAAIGAAgKthYMXgDxAQAGAAgKthYMXgDxAQAAAA==.Demonicus:BAAANQAECgYICgAAAA==.Deredris:BAAANQAECgQICQABNQAECgUIBgADAAAAAA==.',
Di='Discodruid:BAAANQAECgQICAAAAA==.Discover:BAAANQADCgYIEgAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMJBAAAAA==.Domittila:BAAANQAECgQIBwABNQAFFAYIEQAGAK0KAA==.Dommy:BAAANQADCggIFgAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFH8WAAQOAAcKcRuqBQClAQAOAAUKhhmqBQClAQANAAQK0R3kCgBeAQAPAAIKHSMoGwC6AAA1AAQKfx4AAw0ACAqaIwMmAKMCAA0ACApGIwMmAKMCAA4AAgqeItN+AKYAAAAA.Dorkimedes:BAAANQAECgUIBgAAAA==.Dottie:BAABNQAECn8kAAIQAAkKQgtafgDmAQAQAAkKQgtafgDmAQAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Durenn:BAABNQAECn8kAAIHAAkKICMECQCeAwAHAAkKICMECQCeAwABNQAFFAQIEAANAA4kAA==.Duskmane:BAAANQABCgIIAgAAAA==.Dux:BAAANQADCgEIAQAAAA==.',
Dw='Dwadler:BAAANQAECgQIDAAAAA==.',
Dy='Dyrkazen:BAAANQAECgUIDgAAAA==.',
Ec='Eclipses:BAAANQADCgcIEAAAAA==.',
Ed='Edris:BAAANQAECgIIBAABNQAFFAYIEQAGAK0KAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECgkJIgANAHEXAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECn8oAAMJAAkKOQ1uHQD1AQAJAAkKOQ1uHQD1AQARAAUK+ReoHwBYAQAAAA==.',
Er='Erébus:BAAANQAECgcICwABNQAECgcIHQASAIgeAA==.',
Ev='Evergreene:BAAANQADCgQIBAABNQADCggIEQADAAAAAA==.Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQAECgQICgAAAA==.',
Ew='Ewanar:BAABNQAFFH8RAAMGAAYKrQo0CgCnAQAGAAYKrQo0CgCnAQAHAAEKAAA7MwBBAAAAAA==.',
Fa='Faevelia:BAAANQADCgcIGAAAAA==.Fanshen:BAAANQADCggIEwAAAA==.Fatasspos:BAAANQAECgQIBgAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQAECgUICgAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAYIEQACAKwjAA==.Ferndugen:BAAANQAECgIIAgAAAA==.',
Fi='Fishtank:BAAANQAECgQJBAABNQAECgkJKQAMAA0WAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQIBQADAAAAAA==.Fizehtotems:BAEANQAECgQIBQAAAA==.',
Fo='Foragarn:BAAANQADCgYIBAAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Fribble:BAAANQAECgQIBAABNQAECgQIBQADAAAAAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgYIBwAAAA==.Froznfate:BAAANQAECgYIEAAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYIEAAAAA==.',
Fw='Fwibble:BAAANQAECgQIBQAAAA==.',
Fy='Fyrelady:BAAANQADCggIGAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCggIGAADAAAAAA==.',
Ga='Gabbey:BAEANQAECgUICAABNQAECgkJMAATAHcUAA==.Gaboldor:BAAANQADCgUIBQAAAA==.Gamman:BAAANQAECgYIBgAAAA==.Garagon:BAAANQAECgUIEwAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAAANQAECgIIAwABNQAECgQIBQADAAAAAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAAANQAECgUIEAAAAA==.',
Gh='Ghorfindor:BAAANQAECgQIBQAAAA==.Ghostems:BAACNQAFFH8JAAIBAAYK8w1nFwC3AQABAAYK8w1nFwC3AQA1AAQKfxUAAgEACAqMEwe2ABYCAAEACAqMEwe2ABYCAAAA.',
Gi='Gilas:BAAANQAECgUIEgAAAA==.',
Gl='Glaedr:BAAANQAECgYICwABNQADCggIFgADAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAAANQAECgUIEwAAAA==.',
Gn='Gnikole:BAAANQAECgUIDAAAAA==.',
Go='Goswin:BAAANQAECgUIDQAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQADCgMIAwABNQAECgEIAQADAAAAAA==.Greenfelpowa:BAAANQAECgYIDAAAAA==.Gruuven:BAAANQAECgcJDAAAAA==.',
Gu='Gutmtmon:BAAANQADCggIBQAAAA==.',
Gw='Gwenivive:BAABNQAECn8ZAAIMAAgKphZDWgBjAgAMAAgKphZDWgBjAgAAAA==.',
['Gí']='Gízmo:BAABNQAECn8YAAIMAAgKzQ/6gwAAAgAMAAgKzQ/6gwAAAgAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAABNQAECn8bAAMOAAcKPwlEYwANAQAOAAcKYAREYwANAQAPAAQKHRD+lACyAAAAAA==.Happyness:BAAANQADCgYJBgAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzhûnter:BAAANQADCggICAAAAA==.Hellzknîght:BAABNQAECn8ZAAMOAAYK7w0EWQA/AQAOAAYKUQ0EWQA/AQANAAUKrgkvjwDmAAAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgQIBwAAAA==.',
Ho='Holek:BAABNQAECn81AAIMAAkKKh87FQBGAwAMAAkKKh87FQBGAwAAAA==.Holgo:BAABNQAECn8WAAIUAAkKmBbcWQB7AgAUAAkKmBbcWQB7AgAAAA==.Holstop:BAABNQAECn8cAAIUAAgKfhzySgClAgAUAAgKfhzySgClAgABNQAFFAYIFwAJAL4mAA==.Holykimoly:BAAANQAECgMIBwABNQAECgkJJAAVAHIeAA==.Honzz:BAAANQAECgEIAQAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAADAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEAAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAABNQAECn8mAAMFAAgK1x4sJgDQAgAFAAgK1x4sJgDQAgAWAAEKAAB1hQAiAAAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAABNQAECn8fAAILAAgKXxUaCgAnAgALAAgKXxUaCgAnAgAAAA==.Isevio:BAAANQADCggIEQAAAA==.',
It='Ithorus:BAAANQAECgEIAQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQAECgIIAgAAAA==.Jaade:BAAANQAECgIIAgAAAA==.Jaadi:BAAANQADCgYIBgAAAA==.Jaiswizzle:BAABNQAECn8bAAMPAAgKUB+cHwCzAgAPAAgKUB+cHwCzAgANAAEKMAa/5wArAAAAAA==.Jamien:BAABNQAECn8ZAAMKAAcKgxMlxwCHAQAKAAYKoRYlxwCHAQAIAAMKWAY0+QCFAAAAAA==.Jasnos:BAAANQAECgMIBgAAAA==.Jayy:BAAANQAECgMIAwAAAA==.',
Je='Jean:BAAANQAECgcIEAAAAA==.',
Ka='Kaathe:BAAANQAECgMICQAAAA==.Kaidiis:BAAANQAECgYIEQAAAA==.Karbonn:BAAANQAECgMIAwAAAA==.Katiwompus:BAAANQAECgIIAgAAAA==.Katrina:BAAANQADCgIIAgABNQAECgkJLgATAGIRAA==.',
Ke='Kegbreaker:BAABNQAECn8oAAIFAAgKThdwRwBNAgAFAAgKThdwRwBNAgAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQAECgMIAwAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAABNQAECn8kAAIVAAkKch52BAD8AgAVAAkKch52BAD8AgAAAA==.Kimbustible:BAAANQAECgUIBwABNQAECgkJJAAVAHIeAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.Knova:BAAANQAECgQIBAAAAA==.',
Ko='Komodostyle:BAABNQAECn8eAAIJAAcK6gZZLgAqAQAJAAcK6gZZLgAqAQAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAABNQAECn8fAAIBAAcKhQdrDwFvAQABAAcKhQdrDwFvAQAAAA==.',
Kr='Krisarugala:BAAANQAECgYIEQAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAAANQAECgIIAgAAAA==.Kurogami:BAAANQADCgEIAQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAAANQAECgYIEwAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCggICwAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAACNQAFFH8HAAMHAAIKPwvRJQCSAAAHAAIKPwvRJQCSAAAGAAIKhwJlJgBrAAA1AAQKfysAAgcACQqgF5A9AH0CAAcACQqgF5A9AH0CAAAA.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFH8RAAMLAAYKvCFOAAAzAgALAAYKyiBOAAAzAgABAAQKuhu/JQBRAQA1AAQKfyUAAwEACQpHJEhBAAIDAAEACQpHJEhBAAIDAAsAAwo/JPcdAPkAAAAA.Lazerturkey:BAABNQAECn8bAAISAAgK3RSfFgD6AQASAAgK3RSfFgD6AQAAAA==.Laërtes:BAAANQAECgQICwAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIFwAAAA==.',
Li='Lightbill:BAABNQAECn8hAAMIAAgKpRp4PwBkAgAIAAgKpRp4PwBkAgAKAAIKSQnFbgFpAAAAAA==.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQAECgMIAwAAAA==.Lilriotzz:BAABNQAECn8sAAIGAAkKNxoiKADBAgAGAAkKNxoiKADBAgAAAA==.Lilxblitzx:BAAANQAECgUIEQAAAA==.Lilzdrlockz:BAAANQADCgMIAwAAAA==.Lilzriotz:BAAANQAECgEIAgAAAA==.Lilzzriotz:BAAANQADCgYICwAAAA==.',
Lo='Lovecraft:BAAANQADCgQIBAAAAA==.',
Lu='Lucyvar:BAAANQAECggIEwAAAA==.Luma:BAAANQAECgQIBQAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAABNQAECn8fAAMKAAgKlhiLYwBsAgAKAAgKlhiLYwBsAgAXAAQKsBY6TAC0AAAAAA==.Marlow:BAAANQAECgcIDAAAAA==.Marotal:BAABNQAECn8gAAIBAAgKRBHytwASAgABAAgKRBHytwASAgAAAA==.Martysparty:BAAANQAECgIIBQAAAA==.Mavaena:BAAANQADCgYICwAAAA==.Maxlife:BAAANQAECggIBgAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAAANQAECgUIEwAAAA==.Megafire:BAAANQADCgcIFQAAAA==.Megahertz:BAAANQAECgEIAQAAAA==.',
Mh='Mhael:BAAANQAECgQICgAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minsofar:BAAANQADCggIEgAAAA==.Mistilinn:BAABNQAECn8hAAIYAAcKEwOCSgAIAQAYAAcKEwOCSgAIAQAAAA==.Miyri:BAAANQAECgEIAQABNQAECggIKQAZAFYlAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFH8UAAIaAAYKBR4dBQBPAgAaAAYKBR4dBQBPAgA1AAQKf5gAAhoACQrmJkMAAAwEABoACQrmJkMAAAwEAAAA.Morpheus:BAAANQAECgMIBQAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.Moxshunter:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECn8mAAMLAAcKmxYgHgD3AAABAAcKmxY0yQDxAQALAAUKMBggHgD3AAAAAA==.',
My='Mylinkah:BAAANQAECgUIBQAAAA==.Mynamefizz:BAEANQAECgQIBgABNQAECgQIBQADAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Má']='Mára:BAAANQADCgYIBgAAAA==.',
['Mé']='Méasha:BAAANQAECgIJAgAAAA==.',
Ni='Nicola:BAAANQAECgcIDwAAAA==.Nightxwish:BAAANQAECgMICAAAAA==.Nik:BAAANQAECgUIBQAAAA==.',
No='Nocko:BAAANQADCggIFwAAAA==.Noisemarine:BAAANQAECgIIAQAAAA==.Norellia:BAAANQAECgQIBAAAAA==.Northspirit:BAAANQAECgUIBQAAAA==.',
Nu='Nuit:BAAANQAECgIIAgAAAA==.',
Ny='Nyarlothep:BAAANQADCgcIFAAAAA==.Nymh:BAAANQAECgQIBAAAAA==.Nyx:BAAANQADCgIIAgABNQAECgcIGQAKAIMTAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgYIBwABNQAECgkJGwACACoeAA==.Odins:BAABNQAECn8bAAMCAAkKKh6/BgAWAwACAAkKGh6/BgAWAwAHAAgKixvPQgBnAgAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgIIAgABNQADCggIEQADAAAAAA==.Ohyikers:BAACNQAFFH8SAAIaAAUKoiX0BgAbAgAaAAUKoiX0BgAbAgA1AAQKf0kAAxoACQoQJu8AAPUDABoACQoQJu8AAPUDABsAAQp8Gl85AE8AAAAA.',
Ok='Oken:BAAANQAECgMICAAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECgkJTwAIAKIlAA==.',
Ot='Otso:BAABNQAECn8dAAISAAcKiB7FEABOAgASAAcKiB7FEABOAgAAAA==.',
Pa='Paco:BAAANQADCgYIBgAAAA==.Paladime:BAAANQAECgYIEwAAAA==.Pallek:BAAANQAECgYIBwABNQAECgkJNQAMACofAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgYIBQAAAA==.Pasta:BAAANQAECgIIAwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQADCggIDQAAAA==.',
Ph='Phantomarrow:BAAANQAECgEIAQAAAA==.Phantomcat:BAAANQAECgUIBgAAAA==.Phantomlock:BAABNQAECn8aAAMQAAkK1RThVgBOAgAQAAkKoRThVgBOAgAcAAQKDg7NPADNAAAAAA==.Pharasan:BAAANQAECgYIEAAAAA==.Phatcow:BAABNQAECn8mAAIGAAkK0xsOJgDLAgAGAAkK0xsOJgDLAgAAAA==.Pheral:BAEANQADCgIIAgABNQAECgkJMAATAHcUAA==.Phude:BAABNQAECn8xAAIKAAkKZBjfXQB7AgAKAAkKZBjfXQB7AgAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Pu='Pukefeast:BAAANQAECgEIBAAAAA==.Pupcup:BAAANQADCgYIBgAAAA==.',
Py='Pyramys:BAABNQAECn8aAAMdAAcKfyA+DgCRAgAdAAcKUyA+DgCRAgAeAAUKIhyiTwB6AQAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQABCgYIBQAAAA==.Razgrizz:BAAANQADCggIFwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAADAAAAAA==.Rivër:BAAANQAECgUIBQAAAA==.',
Ro='Rolls:BAAANQAECgMIAwAAAA==.Ronmaclean:BAAANQADCgUIBQABNQAECgkJIAALAOAOAA==.Rootoo:BAAANQADCgEIAQAAAA==.Roozer:BAAANQADCggIFwAAAA==.',
Sa='Sabadahoo:BAAANQAECgEIAQABNQAECgUIHAAJABsZAA==.Sad:BAABNQAECn8bAAIBAAgKTRwReACNAgABAAgKTRwReACNAgAAAA==.Saelina:BAAANQAECgUIBwABNQAECggIKQAZAFYlAA==.Saelyria:BAAANQAECgQIBAABNQAECggIKQAZAFYlAA==.Sageofdeath:BAAANQADCgIIAgAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Saintfail:BAAANQAECggIDwABNQAECggIEQADAAAAAA==.Sainthymn:BAAANQAECggIEQAAAA==.Sainttide:BAAANQAECggIDQABNQAECggIEQADAAAAAA==.Salv:BAAANQAECgMIBAAAAA==.Sandiera:BAABNQAECn8VAAIBAAcKEgj3GAFeAQABAAcKEgj3GAFeAQAAAA==.Savallyne:BAAANQAECgEIAQABNQAECggIKQAZAFYlAA==.',
Sc='Scoreboard:BAACNQAFFH8RAAIfAAkKqhG9AADaAQAfAAkKqhG9AADaAQA1AAQKfzEAAx8ACQruJuAAAJwDAB8ACAoHJ+AAAJwDAB4AAQpYJmCNAHEAAAAA.Scupper:BAABNQAECn8oAAIfAAgKjxtMBQCcAgAfAAgKjxtMBQCcAgAAAA==.',
Se='Sedric:BAAANQADCgcICgAAAA==.Selline:BAAANQAECgEIAQAAAA==.Selsonblue:BAAANQADCggIEQAAAA==.Sesskaa:BAAANQAECgYIEwAAAA==.',
Sh='Shaqiri:BAAANQADCgYIBgAAAA==.Sharhox:BAAANQAECgUICwAAAA==.Shishkbob:BAAANQAECgEIAQAAAA==.Shätterz:BAAANQADCgUJBQABNQADCggIEgADAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAAANQAECgYIDwAAAA==.',
Sk='Skaro:BAAANQAECgYIDQAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgYIDQADAAAAAA==.Skarosham:BAAANQAECgQIBAABNQAECgYIDQADAAAAAA==.Sketch:BAABNQAECn8gAAIeAAkKtgsIOADwAQAeAAkKtgsIOADwAQAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAACNQAFFH8FAAIXAAIKEhLmCwCAAAAXAAIKEhLmCwCAAAA1AAQKfy4AAhcACQpQIHQJAAUDABcACQpQIHQJAAUDAAAA.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokiebear:BAAANQAECggICAAAAA==.',
So='Sobekk:BAAANQAECggICAAAAA==.Solomun:BAABNQAECn8wAAIIAAkKkBkfIwDdAgAIAAkKkBkfIwDdAgAAAA==.Songa:BAAANQADCgEIAQABNQAECgMIBQADAAAAAA==.',
Sp='Spinky:BAAANQADCgUIBQAAAA==.Sploosh:BAAANQAECgUIBQAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCggIHwAAAA==.Stinko:BAAANQAECgQIBwAAAA==.Stoopin:BAAANQAECgEIAQAAAA==.Stormlock:BAAANQAECgYIEwAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAAANQAECgUIDQAAAA==.Stwampadin:BAAANQAECgQIDQAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIDQADAAAAAA==.',
Su='Surloyn:BAAANQADCggICAABNQAECggIGwAPAFAfAA==.',
Sw='Swampert:BAACNQAFFH8GAAIUAAMKLBJ4IgDlAAAUAAMKLBJ4IgDlAAA1AAQKfy0AAhQACQrfHUswAPsCABQACQrfHUswAPsCAAAA.Swamperting:BAAANQAECgMIBAABNQAFFAMIBgAUACwSAA==.Swayaos:BAABNQAECn8hAAIQAAgKfxEedAAAAgAQAAgKfxEedAAAAgABNQAECggIKgAWABwVAA==.Swaye:BAABNQAECn8qAAIWAAgKHBVKIwAVAgAWAAgKHBVKIwAVAgAAAA==.Swifte:BAAANQABCgIIAgAAAA==.Swimchick:BAAANQAECgQICwAAAA==.Swizzle:BAABNQAECn8ZAAMgAAcKOxNYFgB6AQAgAAcKOxNYFgB6AQAhAAUKNRC0QQAEAQABNQAECggIGwAPAFAfAA==.',
Sy='Syfa:BAAANQAECgMIAwAAAA==.Syllena:BAABNQAECn8pAAMZAAgKViWZBQBDAwAZAAgKViWZBQBDAwAhAAQKsBC4SQDRAAABNQAECggIKQAZAFYlAA==.Syndicalism:BAAANQADCgEIAQABNQADCgYIBgADAAAAAA==.Syraelia:BAAANQABCgIIAgABNQAECggIKQAZAFYlAA==.Sythia:BAAANQADCgEIAQABNQAFFAQIBgARABkMAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggIHQAAAA==.',
Ta='Tagmoo:BAABNQAECn8oAAIUAAgKCyJwKgAPAwAUAAgKCyJwKgAPAwAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Talion:BAAANQADCgEIAQABNQAECggIGgASABsSAA==.Taloon:BAAANQAECgUICwAAAA==.Taltost:BAAANQAECgUIEgAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAAANQAECgUIDwAAAA==.Tarvält:BAAANQAECgMIAwAAAA==.',
Te='Teksuo:BAABNQAECn8tAAIhAAkKKBStIAAjAgAhAAkKKBStIAAjAgAAAA==.Telamontgrim:BAAANQAECgQIAwAAAA==.Tenithon:BAABNQAECn9PAAIIAAkKoiWgAQDXAwAIAAkKoiWgAQDXAwAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIBAAAAA==.Tholaren:BAAANQAECgUIEwAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Ti:BAAANQAECgIIAgAAAA==.Tinkerspell:BAAANQAECgUIDAAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Touchit:BAAANQAECgMIBQAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAAANQAECgMICAAAAA==.Trevally:BAAANQADCgQIBAAAAA==.Trikshawt:BAAANQAECgUIBgAAAA==.Trillion:BAAANQAECgIIBQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBAAAAA==.',
Ty='Tyfa:BAAANQAECgEIAgAAAA==.',
Ud='Udari:BAAANQAECgYIEQAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.Underdose:BAAANQADCgEIAQABNQADCgYIBgADAAAAAA==.',
Us='Usednabused:BAAANQAECgIIAgAAAA==.',
Uz='Uzume:BAAANQADCgIIAgAAAA==.',
Va='Varithal:BAABNQAECn8uAAIJAAkKYRmAEAChAgAJAAkKYRmAEAChAgABNQABCgEIAQADAAAAAA==.Vastectomy:BAAANQAECgUICQAAAA==.',
Ve='Veleria:BAAANQADCgMIAQAAAA==.Venawyn:BAAANQAECgYIEgAAAA==.',
Vi='Vicious:BAABNQAECn8nAAIGAAkKJR4xJQDPAgAGAAkKJR4xJQDPAgAAAA==.Vixin:BAAANQAECgUICgAAAA==.',
Vo='Voidsaack:BAABNQAECn8cAAMcAAYKrwVbPwDDAAAQAAUKHQVj+wDPAAAcAAUKwANbPwDDAAAAAA==.Vortan:BAABNQAECn8oAAIiAAgKZR19AwDTAgAiAAgKZR19AwDTAgAAAA==.',
Vr='Vreya:BAAANQADCgIIAgABNQADCggIFwADAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAgAAAA==.Vynthus:BAAANQAECgUIDgAAAA==.',
Wa='Warhundin:BAEANQAECgcIBAABNQAECgkJMAATAHcUAA==.Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQIBwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAAANQAECgYIEQAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAAANQAECgUIEwAAAA==.Whispp:BAAANQAECgQIBwAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQIBQADAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.',
Wy='Wymstar:BAAANQADCggIEgAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIEgADAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggIEgADAAAAAA==.',
Xu='Xuny:BAAANQAECgIIAwAAAA==.',
Ya='Yahzway:BAAANQAECgEIAQAAAA==.',
Yo='Yordi:BAAANQAECgUIDAAAAA==.Yoyopapa:BAAANQADCgcIBwAAAA==.',
Yu='Yuzuriha:BAABNQAECn8qAAIMAAkKXCGREwBQAwAMAAkKXCGREwBQAwAAAA==.',
Za='Zaiden:BAAANQADCgYIBgAAAA==.Zamaze:BAAANQADCggIFQAAAA==.',
Ze='Zeekielle:BAEBNQAECn8wAAITAAkKdxSEKQBQAgATAAkKdxSEKQBQAgAAAA==.',
Zi='Zipy:BAAANQAECgUIEwAAAA==.',
Zy='Zyllo:BAAANQADCggIEgAAAA==.',
['Zæ']='Zæ:BAAANQADCgQIBAAAAA==.',
['Ål']='Ålïce:BAABNQAECn8nAAIKAAgK7hgXfAAuAgAKAAgK7hgXfAAuAgAAAA==.',
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
