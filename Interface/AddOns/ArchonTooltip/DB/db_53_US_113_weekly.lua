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

local lookup = {'Shaman-Enhancement','Unknown-Unknown','Evoker-Preservation','DeathKnight-Unholy','Shaman-Restoration','DeathKnight-Frost','Evoker-Devastation','Paladin-Protection','Hunter-BeastMastery','Shaman-Elemental','Mage-Arcane','Mage-Frost','Druid-Balance','Paladin-Holy','Paladin-Retribution','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Addely:BAAANQAECgYJDwAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgQJCAAAAA==.',
Ae='Aellyndsonis:BAAANQAECgEJAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.',
Al='Alaralia:BAAANQAECgcICwABNQAFFAQIBgABAM8bAA==.Alarathel:BAAANQADCggICAABNQAFFAQIBgABAM8bAA==.Alyssandra:BAAANQAECgMIAwAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCgcJDwAAAA==.Ammalane:BAAANQADCgEJAQABNQADCgcJDwACAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.',
Ap='Apollyon:BAAANQAECggICAAAAA==.',
Ar='Arangarr:BAAANQAECgYIEQAAAA==.Aresiuz:BAAANQAECgcJDAAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQADCggIHgAAAA==.Arrietty:BAAANQAECgEJAQAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAAANQADCgUIBQAAAA==.',
As='Asmodea:BAAANQADCgYICwAAAA==.',
At='Atlasfall:BAAANQADCggIGgAAAA==.',
Az='Az:BAAANQAECgIIAQAAAA==.Azeriall:BAAANQAECgYIEwAAAA==.',
Ba='Bacnfen:BAAANQAECgMJBQAAAA==.Baconhammr:BAAANQADCggIDgAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAACAAAAAA==.Banshiï:BAAANQAECgEIAQAAAA==.Baratheøn:BAAANQAECgIJBQAAAA==.',
Be='Beeftard:BAAANQAECgUJDgAAAA==.',
Bi='Bifficus:BAAANQADCgUICQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQAECgEJAQAAAA==.',
Bl='Blackfyre:BAAANQADCggIEQAAAA==.Blackscorn:BAAANQADCgUJBQAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgEIAQAAAA==.',
Bo='Bollace:BAAANQADCgUIBQABNQADCgcIBwACAAAAAA==.',
By='Byzantium:BAAANQAECgMJBQAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYJCAAAAA==.',
Ca='Caluu:BAAANQADCgUJEwAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgIJAgABNQAFFAQICAADAHQRAA==.',
Ch='Chromatic:BAAANQADCgcJBwAAAA==.',
Co='Coffeeblak:BAAANQADCgIIAgAAAA==.Coldstorm:BAAANQAECgYIEQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAAANQAECgEIAQAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAAANQAECgYIEwAAAA==.',
Da='Daddyelessar:BAAANQADCgQJBgAAAA==.Dafattyup:BAAANQAECgQIDQAAAA==.Dagon:BAAANQAECgEIAQAAAA==.Dagreenmeany:BAAANQADCgkJKQAAAA==.Darruin:BAABNQAECoEiAAIEAAkKzSSsAgDAAwAEAAkKzSSsAgDAAwABNQAFFAIIAgACAAAAAA==.Dawncrow:BAAANQADCggIEgAAAA==.',
De='Deathblitz:BAAANQAECgIIAgABNQAECggICAACAAAAAA==.Deathwange:BAAANQADCgcIBwAAAA==.Deavaos:BAAANQAECgQJBAAAAA==.Deeanndra:BAAANQAECgUJBgAAAA==.Demiz:BAABNQAECoEYAAIFAAgKrxUHOAASAgAFAAgKrxUHOAASAgAAAA==.Deredris:BAAANQAECgEJAQABNQAECgIIAgACAAAAAA==.',
Di='Discodruid:BAAANQAECgMJBAAAAA==.Discover:BAAANQADCgUIDAAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMJBAAAAA==.Dommy:BAAANQADCggIFgAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFIEHAAMGAAUKtQ+1AwBDAQAGAAQK4Q+1AwBDAQAEAAEKBA/ZDgBPAAA1AAQKgRYAAwQACApvIfQgAFwCAAQABwpAIPQgAFwCAAYAAgqeIqNJAMcAAAAA.Dorkimedes:BAAANQAECgUIBgAAAA==.Dottie:BAAANQAECgYIDAAAAA==.',
Dr='Draelesh:BAAANQAECgIJBAAAAA==.',
Du='Durenn:BAAANQAFFAIIAgAAAA==.Duskmane:BAAANQABCgIIAgAAAA==.',
Dw='Dwadler:BAAANQAECgMIBAAAAA==.',
Dy='Dyrkazen:BAAANQAECgQJBAAAAA==.',
Ec='Eclipses:BAAANQADCgYIDgAAAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECgcJEwACAAAAAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECoEaAAMDAAgK8wuNGQC0AQADAAgK8wuNGQC0AQAHAAUKUxKoGgA+AQAAAA==.',
Er='Erébus:BAAANQADCgIIAgABNQAECgYJEAACAAAAAA==.',
Ev='Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQAECgMJAwAAAA==.',
Fa='Faevelia:BAAANQADCgUJEQAAAA==.Fanshen:BAAANQADCgcIDwAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQADCggIFgAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAQIBgABAM8bAA==.',
Fi='Fishtank:BAAANQAECgQJBAABNQAECgYJEQACAAAAAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgEJAQACAAAAAA==.Fizehtotems:BAEANQAECgEJAQAAAA==.',
Fo='Foragarn:BAAANQADCgYIBAAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgQIBgAAAA==.Froznfate:BAAANQAECgIIAgAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYJBgAAAA==.',
Fw='Fwibble:BAAANQADCgkJCAAAAA==.',
Fy='Fyrelady:BAAANQADCgcIDwAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCgcIDwACAAAAAA==.',
Ga='Gaboldor:BAAANQADCgUIBQAAAA==.Garagon:BAAANQAECgIIBAAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAAANQADCggIDQABNQADCgkJCAACAAAAAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAAANQAECgIIBAAAAA==.',
Gh='Ghorfindor:BAAANQADCggJIQAAAA==.Ghostems:BAAANQAECgcICwABNQAFFAMIBgAIAPofAA==.',
Gi='Gilas:BAAANQAECgMJBQAAAA==.',
Gl='Glaedr:BAAANQAECgYICwABNQADCggIFgACAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAAANQAECgQJBgAAAA==.',
Gn='Gnikole:BAAANQAECgMIBQAAAA==.',
Go='Goswin:BAAANQAECgQJBgAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQADCgMIAwABNQADCgYJBQACAAAAAA==.Greenfelpowa:BAAANQAECgUIBgAAAA==.Gruuven:BAAANQAECgcJDAAAAA==.',
Gu='Gutmtmon:BAAANQADCggIBQAAAA==.',
Gw='Gwenivive:BAAANQAECgYICwAAAA==.',
['Gí']='Gízmo:BAABNQAECoEXAAIJAAgKtxIJRAApAgAJAAgKtxIJRAApAgAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAAANQAECgQICQAAAA==.Happyness:BAAANQADCgYJBgAAAA==.',
He='Hellzknîght:BAAANQAECgQIBwAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgEIAQAAAA==.',
Ho='Holek:BAABNQAECoEbAAIJAAkKbBe7HgDDAgAJAAkKbBe7HgDDAgAAAA==.Holgo:BAAANQAECggIDAAAAA==.Holstop:BAAANQAECgYICwABNQAFFAUJCAADAOUgAA==.Holykimoly:BAAANQADCgYJBgABNQAECgcJEgACAAAAAA==.Honzz:BAAANQADCgYICgAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAACAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgUJCgAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAAANQAECgYIDgAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAAANQAECgYJCgAAAA==.Isevio:BAAANQADCgYIDQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQADCgQIBAAAAA==.Jaade:BAAANQADCgYIDgAAAA==.Jaiswizzle:BAAANQADCggICQAAAA==.Jamien:BAAANQAECgQICAAAAA==.Jasnos:BAAANQAECgEJAQAAAA==.Jayy:BAAANQADCggJCAAAAA==.',
Je='Jean:BAAANQAECgUICQAAAA==.',
Ka='Kaathe:BAAANQAECgIJBQAAAA==.Kaidiis:BAAANQAECgIJAgAAAA==.Karbonn:BAAANQADCggJEQAAAA==.Katrina:BAAANQADCgIJAgAAAA==.',
Ke='Kegbreaker:BAAANQAECgUJDwAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQADCggIFQAAAA==.',
Ki='Kikieo:BAAANQADCgQJBAAAAA==.Kimbliddan:BAAANQAECgcJEgAAAA==.Kimbustible:BAAANQAECgMJAwABNQAECgcJEgACAAAAAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.',
Ko='Komodostyle:BAAANQAECgUJCwAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAAANQAECgQICwAAAA==.',
Kr='Krisarugala:BAAANQAECgQJBAAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAAANQAECgEIAQAAAA==.Kurogami:BAAANQADCgEJAQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAAANQAECgYIDwAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCgYICgAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAABNQAECoEXAAIKAAgKwBALOwAOAgAKAAgKwBALOwAOAgAAAA==.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFIEIAAMLAAQKQBjIDgBvAQALAAQKFRbIDgBvAQAMAAEKNBxnBQBcAAA1AAQKgSEAAwsACQp3I2sZAFIDAAsACQp3I2sZAFIDAAwAAQqWE2YuADsAAAAA.Lazerturkey:BAAANQAECgUJDQAAAA==.Laërtes:BAAANQAECgEIAQAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIDwAAAA==.',
Li='Lightbill:BAAANQAECgUIDwAAAA==.Lightbàne:BAAANQADCgYIBgAAAA==.Lilriotz:BAAANQADCgUIBwAAAA==.Lilriotzz:BAABNQAECoEaAAIFAAkKfRV2IACRAgAFAAkKfRV2IACRAgAAAA==.Lilxblitzx:BAAANQAECgQJBwAAAA==.Lilzdrlockz:BAAANQADCgMIAwAAAA==.Lilzriotz:BAAANQAECgEJAQAAAA==.',
Lu='Lucyvar:BAAANQADCgkJHgAAAA==.Luma:BAAANQAECgIJAgAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAAANQAECgUIDgAAAA==.Marotal:BAABNQAECoEaAAILAAgKbRGLfwAZAgALAAgKbRGLfwAZAgAAAA==.Martysparty:BAAANQAECgEIAQAAAA==.Mavaena:BAAANQADCgUIBQAAAA==.Maxlife:BAAANQAECggIBgAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAAANQAECgIJBAAAAA==.Megafire:BAAANQADCgUJCQAAAA==.Megahertz:BAAANQADCgYIDgAAAA==.',
Mh='Mhael:BAAANQADCgQIBAAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggJCAAAAA==.Minsofar:BAAANQADCgYJCgAAAA==.Mistilinn:BAAANQAECgUJCwAAAA==.Miyri:BAAANQAECgEIAQABNQAECgQIEAACAAAAAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFIEIAAINAAUK4xQlBQCyAQANAAUK4xQlBQCyAQA1AAQKgV4AAg0ACQq2JiMAAA4EAA0ACQq2JiMAAA4EAAAA.Moxsdeaths:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggICAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAAANQAECgYIEgAAAA==.',
My='Mylinkah:BAAANQAECgEIAQAAAA==.Mynamefizz:BAEANQAECgIIAgABNQAECgEJAQACAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Mé']='Méasha:BAAANQAECgIJAgAAAA==.',
Ni='Nicola:BAAANQAECgQIBgAAAA==.Nightxwish:BAAANQAECgEJAQAAAA==.',
No='Nocko:BAAANQADCggIFwAAAA==.Norellia:BAAANQAECgEJAQAAAA==.Northspirit:BAAANQADCgYIGQAAAA==.',
Nu='Nuit:BAAANQAECgIIAgAAAA==.',
Ny='Nyarlothep:BAAANQADCgUICgAAAA==.Nyx:BAAANQADCgIIAgABNQAECgQICAACAAAAAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgIIAgABNQAECgcJCQACAAAAAA==.Odins:BAAANQAECgcJCQAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgEJAQABNQADCgYICQACAAAAAA==.Ohyikers:BAABNQAECoEtAAINAAkK6SULAQDkAwANAAkK6SULAQDkAwAAAA==.',
Ok='Oken:BAAANQAECgEJAQAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECggIMAAOAE4mAA==.',
Ot='Otso:BAAANQAECgYJEAAAAA==.',
Pa='Paco:BAAANQADCgYIBgAAAA==.Paladime:BAAANQAECgQJBwAAAA==.Pallek:BAAANQADCgcIDgABNQAECgkJGwAJAGwXAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgQIBAAAAA==.Pasta:BAAANQAECgIJAwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Perph:BAAANQADCgUIBQAAAA==.',
Ph='Phantomarrow:BAAANQADCgYIBgAAAA==.Phantomcat:BAAANQADCggIEQAAAA==.Pharasan:BAAANQAECgQICAAAAA==.Phatcow:BAAANQAECgYIEAAAAA==.Phude:BAABNQAECoEZAAIPAAcKdRNqZwDHAQAPAAcKdRNqZwDHAQAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Pu='Pukefeast:BAAANQAECgEJAgAAAA==.',
Py='Pyramys:BAAANQAECgQIBwAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Razgrizz:BAAANQADCgcIDwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAACAAAAAA==.Rivër:BAAANQADCgQJBAAAAA==.',
Ro='Ronmaclean:BAAANQADCgUIBQABNQAECgYIEQACAAAAAA==.Roozer:BAAANQADCgcIDwAAAA==.',
Sa='Sabadahoo:BAAANQADCgIIAgABNQAECgQICgACAAAAAA==.Sad:BAAANQAECgQICAAAAA==.Saelyria:BAAANQAECgQIBAABNQAECgQIEAACAAAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Sainthymn:BAAANQAECggICQAAAA==.Salv:BAAANQAECgMIBAAAAA==.',
Sc='Scoreboard:BAACNQAFFIEHAAIQAAUKdh4wAAAIAgAQAAUKdh4wAAAIAgA1AAQKgR0AAhAACArQJr0AAJcDABAACArQJr0AAJcDAAAA.Scupper:BAAANQAECgUJDwAAAA==.',
Se='Sedric:BAAANQADCgQIBAAAAA==.Selline:BAAANQADCgYJDAAAAA==.Selsonblue:BAAANQADCgYICQAAAA==.Sesskaa:BAAANQAECgMJBQAAAA==.',
Sh='Sharhox:BAAANQAECgQJBgAAAA==.Shishkbob:BAAANQADCgcJBwAAAA==.Shätterz:BAAANQADCgUJBQABNQADCggJEgACAAAAAA==.Shèllz:BAAANQADCgYJBgAAAA==.',
Si='Sigewulf:BAAANQAECgQICAAAAA==.',
Sk='Skaro:BAAANQAECgEIAQAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Skarosham:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Sketch:BAABNQAECoEeAAIRAAkKQAyOGQAhAgARAAkKQAyOGQAhAgAAAA==.',
Sl='Slambulance:BAABNQAECoEdAAIIAAkK0B6hBQAQAwAIAAkK0B6hBQAQAwAAAA==.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokiebear:BAAANQAECggICAAAAA==.',
So='Solomun:BAABNQAECoEYAAIOAAgKGxCQQQDuAQAOAAgKGxCQQQDuAQAAAA==.Songa:BAAANQADCgEIAQABNQAECgIJAgACAAAAAA==.',
Sp='Spinky:BAAANQADCgUIBQAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCgYJEAAAAA==.Stinko:BAAANQADCgQIBAAAAA==.Stormlock:BAAANQAECgQJDAAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAAANQAECgIJBAAAAA==.Stwampadin:BAAANQAECgQIBwAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIBwACAAAAAA==.',
Su='Surloyn:BAAANQADCggICAAAAA==.',
Sw='Swampert:BAABNQAECoEhAAISAAkKCRyDIQDxAgASAAkKCRyDIQDxAgAAAA==.Swamperting:BAAANQAECgMIBAABNQAECgkJIQASAAkcAA==.Swayaos:BAAANQAECgYIDQAAAA==.Swaye:BAAANQAECgcJEQAAAA==.Swifte:BAAANQABCgIIAgAAAA==.Swimchick:BAAANQAECgEIAQAAAA==.Swizzle:BAAANQAECgYJDgAAAA==.',
Sy='Syllena:BAAANQAECgYIEAABNQAECgQIEAACAAAAAA==.Syraelia:BAAANQABCgIIAgABNQAECgQIEAACAAAAAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggJEwAAAA==.',
Ta='Tagmoo:BAAANQAECgUJDwAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Talion:BAAANQADCgEIAQABNQAECgUICQACAAAAAA==.Taloon:BAAANQAECgUJBQAAAA==.Taltost:BAAANQAECgMJBQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.',
Te='Teksuo:BAABNQAECoEYAAITAAcK6RJ4HQC0AQATAAcK6RJ4HQC0AQAAAA==.Telamontgrim:BAAANQAECgIIAwAAAA==.Tenithon:BAABNQAECoEwAAIOAAgKTiYKBQCEAwAOAAgKTiYKBQCEAwAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEJBAAAAA==.Tholaren:BAAANQAECgIJBAAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Tinkerspell:BAAANQADCggJEwAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Touchit:BAAANQADCgcIBwAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAAANQAECgEJAQAAAA==.Trikshawt:BAAANQAECgIIAgAAAA==.Trillion:BAAANQAECgIJAwAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQADCgYICQAAAA==.',
Ty='Tyfa:BAAANQADCgYJBgAAAA==.',
Ud='Udari:BAAANQAECgIIBAAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.',
Us='Usednabused:BAAANQAECgIJAgAAAA==.',
Uz='Uzume:BAAANQADCgIIAgAAAA==.',
Va='Varithal:BAABNQAECoEYAAIDAAcKdxQ2GADJAQADAAcKdxQ2GADJAQABNQABCgEIAQACAAAAAA==.Vastectomy:BAAANQAECgIIAgAAAA==.',
Ve='Venawyn:BAAANQAECgMIBQAAAA==.',
Vi='Viard:BAABNQAECoESAAMUAAgKSBegMgBUAgAUAAgKGxegMgBUAgAVAAQKXgvSMADeAAAAAA==.Vicious:BAABNQAECoEbAAIFAAkKIB6tDwALAwAFAAkKIB6tDwALAwAAAA==.Vixin:BAAANQAECgMIAwAAAA==.',
Vo='Voidsaack:BAAANQAECgUJCgAAAA==.Vortan:BAAANQAECgUIDwAAAA==.',
Vr='Vreya:BAAANQADCgEJAQABNQADCgcIDwACAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAgAAAA==.Vynthus:BAAANQAECgQJBAAAAA==.',
Wa='Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgMIAwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAAANQAECgQICQAAAA==.Wazzmage:BAAANQADCgYICgAAAA==.',
Wh='Whatmyname:BAAANQAECgIJBAAAAA==.Whispp:BAAANQAECgQJBwAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgEJAQACAAAAAA==.',
Wi='Willough:BAAANQADCgYJDAAAAA==.',
Wy='Wymstar:BAAANQADCggJEgAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggJEgACAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggJEgACAAAAAA==.',
Xu='Xuny:BAAANQADCggJGgAAAA==.',
Yo='Yordi:BAAANQAECgEIAQAAAA==.Yoyopapa:BAAANQADCgIIAgAAAA==.',
Yu='Yuzuriha:BAABNQAECoEWAAIJAAcKoCFyLgB5AgAJAAcKoCFyLgB5AgAAAA==.',
Za='Zamaze:BAAANQADCggIFQAAAA==.',
Ze='Zeekielle:BAEBNQAECoEXAAIWAAgKpAtQJwDUAQAWAAgKpAtQJwDUAQAAAA==.',
Zi='Zipy:BAAANQAECgIJBAAAAA==.',
Zy='Zyllo:BAAANQADCgYJBwAAAA==.',
['Zæ']='Zæ:BAAANQADCgQIBAAAAA==.',
['Ål']='Ålïce:BAAANQAECgUJDAAAAA==.',
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
