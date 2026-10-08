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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Restoration','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Evoker-Preservation','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Evoker-Devastation','Druid-Guardian','DemonHunter-Havoc','Warrior-Arms','DemonHunter-Vengeance','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Warlock-Destruction','Rogue-Outlaw','Rogue-Assassination','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Aberration:BAAANQADCgEIAQAAAA==.',
Ad='Addely:BAABNQAECoEWAAIBAAcK5g183gClAQABAAcK5g183gClAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgYIEQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgEJAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.',
Al='Alaralia:BAAANQAECggIEgABNQAFFAUIDAACAHchAA==.Alarathel:BAAANQADCggICAABNQAFFAUIDAACAHchAA==.Alyssandra:BAAANQAECgYIDgAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCgcIEAAAAA==.Ammalane:BAAANQADCgQIBQABNQADCgcIEAADAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.',
Ap='Apollyon:BAAANQAECggICAAAAA==.',
Ar='Arangarr:BAABNQAECoEkAAIEAAgKpiCeDADnAgAEAAgKpiCeDADnAgAAAA==.Aresiuz:BAABNQAECoEUAAIFAAgKyhCoWgDiAQAFAAgKyhCoWgDiAQABNQAFFAUICwAGAB8NAA==.Areyana:BAAANQAECgMIAwAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQAECgEIAQAAAA==.Arrietty:BAAANQAECgMIBgAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAAANQAECgUIBQAAAA==.',
At='Atlasfall:BAAANQAECgIIAgAAAA==.',
Az='Az:BAAANQAECgUIBwAAAA==.Azeriall:BAABNQAECoEnAAIHAAgKMBkAPQBZAgAHAAgKMBkAPQBZAgAAAA==.Azerodru:BAAANQADCgEIAQAAAA==.',
Ba='Bacnfen:BAAANQAECgQIDQAAAA==.Baconhammr:BAAANQADCggIFAAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAADAAAAAA==.Banshiï:BAAANQAECgUICQAAAA==.Baratheøn:BAAANQAECgUIDQAAAA==.',
Be='Beeftard:BAABNQAECoEYAAIIAAgKuxrCLQCUAgAIAAgKuxrCLQCUAgAAAA==.',
Bi='Bifficus:BAAANQAECgEIAQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQAECgEIAgAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgUICgAAAA==.',
Bo='Bollace:BAAANQADCgUIBQABNQADCgcIBwADAAAAAA==.',
By='Byzantium:BAAANQAECgQIDQAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICAAAAA==.',
Ca='Caluu:BAAANQAECgEIAQAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAYIDwAJAK4SAA==.',
Ch='Chromatic:BAAANQAECgMIAwAAAA==.',
Co='Coffeeblak:BAAANQADCgIIAgAAAA==.Coldstorm:BAABNQAECoEeAAIKAAkKCQ8ZCgD5AQAKAAkKCQ8ZCgD5AQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAAANQAECgUICAAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECoEnAAILAAgKvhpwPgCLAgALAAgKvhpwPgCLAgAAAA==.',
Da='Daddyelessar:BAAANQADCgUICwAAAA==.Daemonfyre:BAAANQADCgEIAQAAAA==.Dafattyup:BAAANQAECgUIDwAAAA==.Dagon:BAAANQAECgEIAgAAAA==.Dagreenmeany:BAAANQADCggINQAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Darruin:BAACNQAFFIEMAAIMAAQKfSQQBwCJAQAMAAQKfSQQBwCJAQA1AAQKgScAAgwACQqYJaAHAHUDAAwACQqYJaAHAHUDAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQABCgIIAwAAAA==.Deathblitz:BAAANQAECgIIAgABNQAECggICAADAAAAAA==.Deathlydruid:BAAANQADCgEIAQAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAAANQAECgUICQAAAA==.Deeanndra:BAAANQAECgYIDQAAAA==.Demiz:BAABNQAECoEkAAIGAAgKTRaMUgDvAQAGAAgKTRaMUgDvAQAAAA==.Demonicus:BAAANQAECgQIBQAAAA==.Deredris:BAAANQAECgQIBQABNQAECgUIBgADAAAAAA==.',
Di='Discodruid:BAAANQAECgQICAAAAA==.Discover:BAAANQADCgYIEgAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMJBAAAAA==.Domittila:BAAANQAECgQIBwABNQAFFAUICwAGAB8NAA==.Dommy:BAAANQADCggIFgAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFIEPAAMMAAYKjhgHCQBeAQAMAAQKyRsHCQBeAQANAAQKgxKrBwAsAQA1AAQKgRsAAwwACApaImggAKkCAAwACAoQImggAKkCAA0AAgqeIsRqAK8AAAAA.Dorkimedes:BAAANQAECgUIBgAAAA==.Dottie:BAABNQAECoEeAAIOAAgK7AsxewDHAQAOAAgK7AsxewDHAQAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Durenn:BAABNQAECoEdAAIHAAkKlCO/CACWAwAHAAkKlCO/CACWAwABNQAFFAQIDAAMAH0kAA==.Duskmane:BAAANQABCgIIAgAAAA==.Dux:BAAANQADCgEIAQAAAA==.',
Dw='Dwadler:BAAANQAECgQICgAAAA==.',
Dy='Dyrkazen:BAAANQAECgUICQAAAA==.',
Ec='Eclipses:BAAANQADCgcIEAAAAA==.',
Ed='Edris:BAAANQAECgIIAwABNQAFFAUICwAGAB8NAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECggIIAAMACgUAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECoElAAMJAAkKBgxiHADnAQAJAAkKBgxiHADnAQAPAAUKxhbqHABjAQAAAA==.',
Er='Erébus:BAAANQAECgQIBAABNQAECgcIHQAQAMAeAA==.',
Ev='Evergreene:BAAANQADCgEIAQABNQADCgcIEAADAAAAAA==.Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQAECgQICgAAAA==.',
Ew='Ewanar:BAABNQAFFIELAAMGAAUKHw0uEAAaAQAGAAQK9AYuEAAaAQAHAAEKEQQoLABBAAAAAA==.',
Fa='Faevelia:BAAANQADCgYIFwAAAA==.Fanshen:BAAANQADCgcIDwAAAA==.Fatasspos:BAAANQAECgQIBAAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQAECgMIBQAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAUIDAACAHchAA==.',
Fi='Fishtank:BAAANQAECgQJBAABNQAECggIIQALAFYRAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQIBQADAAAAAA==.Fizehtotems:BAEANQAECgQIBQAAAA==.',
Fo='Foragarn:BAAANQADCgYIBAAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgYIBwAAAA==.Froznfate:BAAANQAECgUICgAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYICQAAAA==.',
Fw='Fwibble:BAAANQAECgUIBAAAAA==.',
Fy='Fyrelady:BAAANQADCgcIFAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCgcIFAADAAAAAA==.',
Ga='Gabbey:BAEANQAECgQIBAABNQAECgkJJwARAM4RAA==.Gaboldor:BAAANQADCgUIBQAAAA==.Garagon:BAAANQAECgUIDgAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAAANQAECgIIAgABNQAECgUIBAADAAAAAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAAANQAECgUICwAAAA==.',
Gh='Ghorfindor:BAAANQAECgQIBQAAAA==.Ghostems:BAABNQAFFIEHAAIBAAQKqw2+IgAxAQABAAQKqw2+IgAxAQAAAA==.',
Gi='Gilas:BAAANQAECgQIDQAAAA==.',
Gl='Glaedr:BAAANQAECgYICwABNQADCggIFgADAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAAANQAECgUIDwAAAA==.',
Gn='Gnikole:BAAANQAECgUICgAAAA==.',
Go='Goswin:BAAANQAECgUICwAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQADCgMIAwABNQAECgEIAQADAAAAAA==.Greenfelpowa:BAAANQAECgYIDAAAAA==.Gruuven:BAAANQAECgcJDAAAAA==.',
Gu='Gutmtmon:BAAANQADCggIBQAAAA==.',
Gw='Gwenivive:BAAANQAECgcIEwAAAA==.',
['Gí']='Gízmo:BAABNQAECoEYAAILAAgKtxJGbgAJAgALAAgKtxJGbgAJAgAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAAANQAECgYIEwAAAA==.Happyness:BAAANQADCgYJBgAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzhûnter:BAAANQADCggICAAAAA==.Hellzknîght:BAAANQAECgUIEAAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgMIAwAAAA==.',
Ho='Holek:BAABNQAECoEoAAILAAkK+Ri8MQC1AgALAAkK+Ri8MQC1AgAAAA==.Holgo:BAABNQAECoEWAAISAAkKvBV+SQCTAgASAAkKvBV+SQCTAgAAAA==.Holstop:BAAANQAECgcIEwABNQAFFAUIEQAJACwmAA==.Holykimoly:BAAANQAECgMIBAABNQAECgkJIAATAGEcAA==.Honzz:BAAANQAECgEIAQAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAADAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEAAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAABNQAECoEeAAMFAAcKRSAROABmAgAFAAcKRSAROABmAgAUAAEKNgmsdwAlAAAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAABNQAECoEYAAIKAAgKmhUCCQAYAgAKAAgKmhUCCQAYAgAAAA==.Isevio:BAAANQADCgYIDQAAAA==.',
It='Ithorus:BAAANQADCggICAAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQAECgIIAgAAAA==.Jaade:BAAANQAECgIIAgAAAA==.Jaiswizzle:BAAANQAECgcIDwAAAA==.Jamien:BAAANQAECgYIEgAAAA==.Jasnos:BAAANQAECgMIBgAAAA==.Jayy:BAAANQADCggJCAAAAA==.',
Je='Jean:BAAANQAECgcIEAAAAA==.',
Ka='Kaathe:BAAANQAECgMICAAAAA==.Kaidiis:BAAANQAECgUICwAAAA==.Karbonn:BAAANQAECgMIAwAAAA==.Katiwompus:BAAANQAECgIIAgAAAA==.Katrina:BAAANQADCgIJAgABNQAECgkJKAARALkPAA==.',
Ke='Kegbreaker:BAABNQAECoEgAAIFAAgKfhH9VgDvAQAFAAgKfhH9VgDvAQAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQAECgMIAwAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAABNQAECoEgAAITAAkKYRxDBADeAgATAAkKYRxDBADeAgAAAA==.Kimbustible:BAAANQAECgQIBQABNQAECgkJIAATAGEcAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.',
Ko='Komodostyle:BAABNQAECoEYAAIJAAcKowOrLQAQAQAJAAcKowOrLQAQAQAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAABNQAECoEYAAIBAAcKEQZT/ABuAQABAAcKEQZT/ABuAQAAAA==.',
Kr='Krisarugala:BAAANQAECgYICwAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAAANQAECgEIAQAAAA==.Kurogami:BAAANQADCgEJAQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAAANQAECgYIDwAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCggICwAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAACNQAFFIEFAAMHAAIKhAk9IQCNAAAHAAIKhAk9IQCNAAAGAAIKhwJWIAB4AAA1AAQKgSkAAgcACQq8Frc0AH8CAAcACQq8Frc0AH8CAAAA.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFIEQAAMKAAYKLyEvAABFAgAKAAYKjiAvAABFAgABAAQKFRbSHgBOAQA1AAQKgSUAAwEACQp3I5kyABoDAAEACQp3I5kyABoDAAoAAwqxHtcZAP4AAAAA.Lazerturkey:BAABNQAECoEYAAIQAAgKPRVvEwDoAQAQAAgKPRVvEwDoAQAAAA==.Laërtes:BAAANQAECgQIBwAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIFAAAAA==.',
Li='Lightbill:BAABNQAECoEgAAMIAAgKgRoQNwBsAgAIAAgKgRoQNwBsAgAVAAIK0gwQSAFpAAAAAA==.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQAECgMIAwAAAA==.Lilriotzz:BAABNQAECoEpAAIGAAkKvhiqKACfAgAGAAkKvhiqKACfAgAAAA==.Lilxblitzx:BAAANQAECgUIEAAAAA==.Lilzdrlockz:BAAANQADCgMIAwAAAA==.Lilzriotz:BAAANQAECgEIAgAAAA==.Lilzzriotz:BAAANQADCgYICwAAAA==.',
Lu='Lucyvar:BAAANQAECggIDwAAAA==.Luma:BAAANQAECgQIBQAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAABNQAECoEYAAMVAAgKcRS3gQD0AQAVAAgKFRO3gQD0AQAWAAQK6RS3QgDAAAAAAA==.Marlow:BAAANQAECgYIBgAAAA==.Marotal:BAABNQAECoEgAAIBAAgK8xIVogAdAgABAAgK8xIVogAdAgAAAA==.Martysparty:BAAANQAECgIIBQAAAA==.Mavaena:BAAANQADCgYICwAAAA==.Maxlife:BAAANQAECggIBgAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAAANQAECgUIDgAAAA==.Megafire:BAAANQADCgUIDgAAAA==.Megahertz:BAAANQAECgEIAQAAAA==.',
Mh='Mhael:BAAANQAECgUICAAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minphoria:BAAANQABCgIIAgAAAA==.Minsofar:BAAANQADCggIEgAAAA==.Mistilinn:BAABNQAECoEaAAIXAAcKXQKBSQDgAAAXAAcKXQKBSQDgAAAAAA==.Miyri:BAAANQAECgEIAQABNQAECggIJgAYADwlAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFIEPAAIZAAYKBRqwBQAOAgAZAAYKBRqwBQAOAgA1AAQKgY0AAhkACQrVJjEAAA4EABkACQrVJjEAAA4EAAAA.Morpheus:BAAANQAECgIIAgAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.Moxshunter:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECoEjAAMKAAcK8RcGGgD8AAABAAcK8RdssAAAAgAKAAUKlRUGGgD8AAAAAA==.',
My='Mylinkah:BAAANQAECgEIAQAAAA==.Mynamefizz:BAEANQAECgQIBgABNQAECgQIBQADAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Má']='Mára:BAAANQADCgYIBgAAAA==.',
['Mé']='Méasha:BAAANQAECgIJAgAAAA==.',
Ni='Nicola:BAAANQAECgYIDgAAAA==.Nightxwish:BAAANQAECgMIBgAAAA==.',
No='Nocko:BAAANQADCggIFwAAAA==.Norellia:BAAANQAECgQIBAAAAA==.Northspirit:BAAANQADCgYIHwAAAA==.',
Nu='Nuit:BAAANQAECgIIAgAAAA==.',
Ny='Nyarlothep:BAAANQADCgYIEwAAAA==.Nymh:BAAANQADCgIIAgAAAA==.Nyx:BAAANQADCgIIAgABNQAECgYIEgADAAAAAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgYIBwABNQAECggIEwADAAAAAA==.Odins:BAAANQAECggIEwAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgIIAgABNQADCgYIDQADAAAAAA==.Ohyikers:BAACNQAFFIEOAAIZAAUKnh4bBwDnAQAZAAUKnh4bBwDnAQA1AAQKgUIAAhkACQovJrYAAPYDABkACQovJrYAAPYDAAAA.',
Ok='Oken:BAAANQAECgMIBgAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECgkJRwAIAKIlAA==.',
Ot='Otso:BAABNQAECoEdAAIQAAcKwB7FDABdAgAQAAcKwB7FDABdAgAAAA==.',
Pa='Paco:BAAANQADCgYIBgAAAA==.Paladime:BAAANQAECgYIDQAAAA==.Pallek:BAAANQADCggIFgABNQAECgkJKAALAPkYAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgYIBQAAAA==.Pasta:BAAANQAECgIIAwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQADCggIDQAAAA==.',
Ph='Phantomarrow:BAAANQADCgYIBgAAAA==.Phantomcat:BAAANQAECgUIBgAAAA==.Phantomlock:BAABNQAECoEXAAMOAAkK9BWiRwBeAgAOAAkKyxWiRwBeAgAaAAQKXguYOQDQAAAAAA==.Pharasan:BAAANQAECgUIDgAAAA==.Phatcow:BAABNQAECoEhAAIGAAgKMxzpMgBuAgAGAAgKMxzpMgBuAgAAAA==.Pheral:BAEANQADCgIIAgABNQAECgkJJwARAM4RAA==.Phude:BAABNQAECoEtAAIVAAgKgxd2ZQA9AgAVAAgKgxd2ZQA9AgAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Pu='Pukefeast:BAAANQAECgEIAwAAAA==.Pupcup:BAAANQADCgYIBgAAAA==.',
Py='Pyramys:BAAANQAECgYIEgAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQABCgYIBQAAAA==.Razgrizz:BAAANQADCgcIEwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAADAAAAAA==.Rivër:BAAANQAECgUIBQAAAA==.',
Ro='Rolls:BAAANQAECgIIAgAAAA==.Ronmaclean:BAAANQADCgUIBQABNQAECgkJHgAKAAkPAA==.Rootoo:BAAANQADCgEIAQAAAA==.Roozer:BAAANQADCgcIEwAAAA==.',
Sa='Sabadahoo:BAAANQADCgIIAgABNQAECgUIGQAPAGcYAA==.Sad:BAAANQAECgYIEwAAAA==.Saelina:BAAANQADCgYIBgABNQAECggIJgAYADwlAA==.Saelyria:BAAANQAECgQIBAABNQAECggIJgAYADwlAA==.Sagepower:BAAANQADCgIIAgAAAA==.Saintfail:BAAANQAECggICAABNQAECggIEQADAAAAAA==.Sainthymn:BAAANQAECggIEQAAAA==.Salv:BAAANQAECgMIBAAAAA==.Sandiera:BAAANQAECgYIDgAAAA==.',
Sc='Scoreboard:BAACNQAFFIEQAAIbAAkKTxWIAADwAQAbAAkKTxWIAADwAQA1AAQKgTEAAxsACQroJsUAAKIDABsACAr6JsUAAKIDABwAAQpYJmN5AHEAAAAA.Scupper:BAABNQAECoEgAAIbAAgKFBncBQBqAgAbAAgKFBncBQBqAgAAAA==.',
Se='Sedric:BAAANQADCgQIBAAAAA==.Selline:BAAANQADCgYIEQAAAA==.Selsonblue:BAAANQADCgYIDQAAAA==.Sesskaa:BAAANQAECgQIDQAAAA==.',
Sh='Shaqiri:BAAANQADCgYIBgAAAA==.Sharhox:BAAANQAECgUICwAAAA==.Shishkbob:BAAANQAECgEIAQAAAA==.Shätterz:BAAANQADCgUJBQABNQADCggIEgADAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAAANQAECgUIDQAAAA==.',
Sk='Skaro:BAAANQAECgUICQAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgUICQADAAAAAA==.Skarosham:BAAANQAECgQIBAABNQAECgUICQADAAAAAA==.Sketch:BAABNQAECoEfAAIcAAkKcwwULQD9AQAcAAkKcwwULQD9AQAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAABNQAECoEqAAIWAAkKmyCmBwAOAwAWAAkKmyCmBwAOAwAAAA==.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokedamage:BAAANQABCgUICwAAAA==.Smokiebear:BAAANQAECggICAAAAA==.',
So='Sobekk:BAAANQAECggICAAAAA==.Solomun:BAABNQAECoEpAAIIAAkKYBhLIADXAgAIAAkKYBhLIADXAgAAAA==.Songa:BAAANQADCgEIAQABNQAECgIJAgADAAAAAA==.',
Sp='Spinky:BAAANQADCgUIBQAAAA==.Sploosh:BAAANQAECgUIAwAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCgcIFwAAAA==.Stinko:BAAANQAECgIIAwAAAA==.Stoopin:BAAANQAECgEIAQAAAA==.Stormlock:BAAANQAECgYIEwAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAAANQAECgQICAAAAA==.Stwampadin:BAAANQAECgQIDQAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIDQADAAAAAA==.',
Su='Surloyn:BAAANQADCggICAAAAA==.',
Sw='Swampert:BAACNQAFFIEFAAISAAMKvw4bHgDaAAASAAMKvw4bHgDaAAA1AAQKgSsAAhIACQrBHaAoAAcDABIACQrBHaAoAAcDAAAA.Swamperting:BAAANQAECgMIBAABNQAFFAMIBQASAL8OAA==.Swayaos:BAABNQAECoEcAAIOAAgKBRJ9aQD6AQAOAAgKBRJ9aQD6AQAAAA==.Swaye:BAABNQAECoEiAAIUAAgKZxSQIAAOAgAUAAgKZxSQIAAOAgAAAA==.Swifte:BAAANQABCgIIAgAAAA==.Swimchick:BAAANQAECgQIBwAAAA==.Swizzle:BAABNQAECoEZAAMdAAcKdBMCFACEAQAdAAcKdBMCFACEAQAeAAUKyg7vOQAMAQAAAA==.',
Sy='Syfa:BAAANQAECgMIAwAAAA==.Syllena:BAABNQAECoEmAAMYAAgKPCV7BABKAwAYAAgKPCV7BABKAwAeAAQKYQ5aQQDVAAABNQAECggIJgAYADwlAA==.Syndicalism:BAAANQADCgEIAQABNQADCgYIBgADAAAAAA==.Syraelia:BAAANQABCgIIAgABNQAECggIJgAYADwlAA==.Sythia:BAAANQADCgEIAQABNQAFFAMIBQAPABkMAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggIGQAAAA==.',
Ta='Tagmoo:BAABNQAECoEgAAISAAgKcyAkMgDjAgASAAgKcyAkMgDjAgAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Talion:BAAANQADCgEIAQABNQAECgYIEwADAAAAAA==.Taloon:BAAANQAECgUICAAAAA==.Taltost:BAAANQAECgQIDQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAAANQAECgUICgAAAA==.',
Te='Teksuo:BAABNQAECoEnAAIeAAgK7xRIIAD/AQAeAAgK7xRIIAD/AQAAAA==.Telamontgrim:BAAANQAECgQIAwAAAA==.Tenithon:BAABNQAECoFHAAIIAAkKoiUpAQDdAwAIAAkKoiUpAQDdAwAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIBAAAAA==.Tholaren:BAAANQAECgUIDgAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Ti:BAAANQAECgIIAgAAAA==.Tinkerspell:BAAANQAECgQIBwAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Touchit:BAAANQAECgMIAwAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAAANQAECgMIBgAAAA==.Trevally:BAAANQADCgQIBAAAAA==.Trikshawt:BAAANQAECgUIBgAAAA==.Trillion:BAAANQAECgIIBQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBAAAAA==.',
Ty='Tyfa:BAAANQAECgEIAQAAAA==.',
Ud='Udari:BAAANQAECgYIDAAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.',
Us='Usednabused:BAAANQAECgIIAgAAAA==.',
Uz='Uzume:BAAANQADCgIIAgAAAA==.',
Va='Varithal:BAABNQAECoEoAAIJAAgK7BrKEgBrAgAJAAgK7BrKEgBrAgABNQABCgEIAQADAAAAAA==.Vastectomy:BAAANQAECgUIBwAAAA==.',
Ve='Veleria:BAAANQADCgMIAQAAAA==.Venawyn:BAAANQAECgQIDQAAAA==.',
Vi='Vicious:BAABNQAECoEkAAIGAAkKJR6oHQDYAgAGAAkKJR6oHQDYAgAAAA==.Vixin:BAAANQAECgMIBQAAAA==.',
Vo='Voidsaack:BAABNQAECoEXAAMaAAYKlgYqPADGAAAOAAUK1QTP6QDHAAAaAAUK/AQqPADGAAAAAA==.Vortan:BAABNQAECoEgAAIfAAcKPB9SBAB+AgAfAAcKPB9SBAB+AgAAAA==.',
Vr='Vreya:BAAANQADCgIIAgABNQADCgcIEwADAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAgAAAA==.Vynthus:BAAANQAECgUICQAAAA==.',
Wa='Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQIBwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAAANQAECgYIEQAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAAANQAECgUIDgAAAA==.Whispp:BAAANQAECgQIBwAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQIBQADAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.',
Wy='Wymstar:BAAANQADCggIEgAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIEgADAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggIEgADAAAAAA==.',
Xu='Xuny:BAAANQAECgEIAQAAAA==.',
Yo='Yordi:BAAANQAECgQIBwAAAA==.Yoyopapa:BAAANQADCgIIAgAAAA==.',
Yu='Yuzuriha:BAABNQAECoElAAILAAgK/SLuGQAYAwALAAgK/SLuGQAYAwAAAA==.',
Za='Zaiden:BAAANQADCgYIBgAAAA==.Zamaze:BAAANQADCggIFQAAAA==.',
Ze='Zeekielle:BAEBNQAECoEnAAIRAAkKzhEWJwA7AgARAAkKzhEWJwA7AgAAAA==.',
Zi='Zipy:BAAANQAECgUIDgAAAA==.',
Zy='Zyllo:BAAANQADCgYIDAAAAA==.',
['Zæ']='Zæ:BAAANQADCgQIBAAAAA==.',
['Ål']='Ålïce:BAABNQAECoEfAAIVAAgKDxpMZABBAgAVAAgKDxpMZABBAgAAAA==.',
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
