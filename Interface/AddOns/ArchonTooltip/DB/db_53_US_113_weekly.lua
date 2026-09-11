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

local lookup = {'Shaman-Enhancement','Unknown-Unknown','DeathKnight-Unholy','Paladin-Protection','Mage-Arcane','Mage-Frost','Druid-Balance','Paladin-Holy',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Addely:BAAANQAECgMIBAAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQADCgcIBwAAAA==.',
Ae='Aellyndsonis:BAAANQADCgYIBgAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.',
Al='Alaralia:BAAANQADCggIEQABNQAECgkJFwABAFcmAA==.Alyssandra:BAAANQADCgcIDAAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCgUICAAAAA==.Ammalane:BAAANQABCgQICAABNQADCgUICAACAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.',
Ap='Apollyon:BAAANQADCggIAQAAAA==.',
Ar='Arangarr:BAAANQAECgUIBwAAAA==.Aresiuz:BAAANQAECgYIBgAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQADCgYIDwAAAA==.Arrietty:BAAANQADCgcIEQAAAA==.Arthâs:BAAANQADCgUIBQAAAA==.Arumathe:BAAANQADCgUIBQAAAA==.',
As='Asmodea:BAAANQADCgYICwAAAA==.',
At='Atlasfall:BAAANQADCggIEgAAAA==.',
Az='Az:BAAANQADCgcIDgAAAA==.Azeriall:BAAANQAECgQIBwAAAA==.',
Ba='Baconhammr:BAAANQADCggIDgAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIDwACAAAAAA==.Banshiï:BAAANQADCggIEwAAAA==.Baratheøn:BAAANQAECgIIAgAAAA==.',
Be='Beefcrits:BAAANQADCggIDgAAAA==.Beeftard:BAAANQAECgQIBQAAAA==.',
Bi='Bifficus:BAAANQADCgUICQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQADCggICAAAAA==.',
Bl='Blackfyre:BAAANQADCgYICQAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQADCgcIDgAAAA==.',
Bo='Bollace:BAAANQADCgUIBQABNQADCgcIBwACAAAAAA==.',
By='Byzantium:BAAANQADCggIDgAAAA==.',
['Bô']='Bônebeard:BAAANQADCgcIDAAAAA==.',
Ca='Caluu:BAAANQADCgUIDgAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Co='Coldstorm:BAAANQAECgMIBQAAAA==.',
Cy='Cynderleena:BAAANQADCgUIDAAAAA==.Cynfully:BAAANQABCgIIAgAAAA==.Cynyia:BAAANQAECgQIBwAAAA==.',
Da='Daddyelessar:BAAANQADCgQIBQAAAA==.Dafattyup:BAAANQAECgQICAAAAA==.Dagon:BAAANQADCggIDgAAAA==.Dagreenmeany:BAAANQADCggIHQAAAA==.Darruin:BAABNQAECoEXAAIDAAkJASQPAgCvAwADAAkJASQPAgCvAwAAAA==.Dawncrow:BAAANQADCggIDgAAAA==.',
De='Deathwange:BAAANQADCgcIBwAAAA==.Deavaos:BAAANQADCggIDgAAAA==.Deeanndra:BAAANQAECgIIAQAAAA==.Demiz:BAAANQAECgMIBwAAAA==.',
Di='Discodruid:BAAANQADCggIEgAAAA==.Discover:BAAANQADCgUIDAAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMIBAAAAA==.Dommy:BAAANQADCggIEwAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAAANQAECggIEgAAAA==.Dorkimedes:BAAANQADCggIDgAAAA==.Dottie:BAAANQADCgYICQAAAA==.',
Dr='Draelesh:BAAANQADCggIEAAAAA==.',
Du='Durenn:BAAANQAECgQIBQAAAA==.Duskmane:BAAANQABCgIIAgAAAA==.',
Dw='Dwadler:BAAANQAECgEIAQAAAA==.',
Dy='Dyrkazen:BAAANQADCggIDgAAAA==.',
Ec='Eclipses:BAAANQADCgUIDQAAAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECgQIBwACAAAAAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAAANQAECgYIDAAAAA==.',
Ev='Evlpotato:BAAANQADCggIDwAAAA==.Evojak:BAAANQADCggIDgAAAA==.',
Fa='Faevelia:BAAANQADCgMICAAAAA==.Fanshen:BAAANQADCgUICAAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQADCgcIDgAAAA==.',
Fe='Feldo:BAAANQADCgYIDAAAAA==.Fenfen:BAAANQADCgQIBAAAAA==.Feralarak:BAAANQADCgUIBQABNQAECgkJFwABAFcmAA==.',
Fi='Fishtank:BAAANQAECgEIAQABNQAECgQIBQACAAAAAA==.Fizehbubbleh:BAEANQADCgYIBgABNQADCgcICgACAAAAAA==.Fizehtotems:BAEANQADCgcICgAAAA==.',
Fo='Foragarn:BAAANQADCgYIBAAAAA==.',
Fr='Frankkastle:BAAANQADCgcIDwAAAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgMIAwAAAA==.Froznfate:BAAANQADCggIEwAAAA==.',
Fw='Fwibble:BAAANQABCgIIAgAAAA==.',
Fy='Fyrelady:BAAANQADCgUICAAAAA==.',
Ga='Gaboldor:BAAANQADCgUIBQAAAA==.Garagon:BAAANQADCggIEAAAAA==.Garlicbread:BAAANQAECgQIBAAAAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAAANQADCggIEAAAAA==.',
Gh='Ghorfindor:BAAANQADCgcIEQAAAA==.Ghostems:BAAANQAECgQIBAABNQAECgkJFwAEAHUjAA==.',
Gi='Gilas:BAAANQADCggIDgAAAA==.',
Gl='Glaedr:BAAANQAECgQIBAABNQADCggIDgACAAAAAA==.',
Gn='Gnikole:BAAANQADCgcIEAAAAA==.',
Go='Goswin:BAAANQADCgcIEAAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQADCgMIAwAAAA==.Greenfelpowa:BAAANQAECgEIAQAAAA==.Gruuven:BAAANQAECgQIBQAAAA==.',
Gu='Gutmtmon:BAAANQADCgUIBQAAAA==.',
Gw='Gwenivive:BAAANQAECgEIAQAAAA==.',
['Gí']='Gízmo:BAAANQAECgYIDQAAAA==.',
['Gû']='Gûnter:BAAANQADCgMIAwAAAA==.',
Ha='Hakaii:BAAANQAECgIIAgAAAA==.Happyness:BAAANQADCgYIBgAAAA==.',
He='Hellzknîght:BAAANQADCgcIEwAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQADCgYICwAAAA==.',
Ho='Holek:BAAANQAECgUIBQAAAA==.Holstop:BAAANQADCgUIBQABNQAFFAEIAQACAAAAAA==.Honzz:BAAANQADCgEIAQAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAACAAAAAA==.',
Hu='Huntaholic:BAAANQAECgEIAQAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAAANQAECgQIBAAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAAANQAECgIIAwAAAA==.Isevio:BAAANQADCgUIBwAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQADCgQIBAAAAA==.Jaade:BAAANQADCgYIDgAAAA==.Jaiswizzle:BAAANQADCgEIAQAAAA==.Jamien:BAAANQAECgMIBAAAAA==.Jasnos:BAAANQADCgcIEQAAAA==.Jayy:BAAANQADCgUIBQAAAA==.',
Je='Jean:BAAANQADCggIDQAAAA==.',
Ka='Kaathe:BAAANQAECgEIAgAAAA==.Kaidiis:BAAANQADCggIFAAAAA==.Karbonn:BAAANQADCgUICQAAAA==.',
Ke='Kegbreaker:BAAANQAECgQIBQAAAA==.Keleden:BAAANQABCgQIBAAAAA==.',
Kh='Khanas:BAAANQADCgUICQAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAAANQAECgMIBQAAAA==.Kimbustible:BAAANQADCgYIBgABNQAECgMIBQACAAAAAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.',
Ko='Komodostyle:BAAANQAECgIIAgAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAAANQAECgQIBwAAAA==.',
Kr='Krisarugala:BAAANQADCggIDwAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgYICwAAAA==.Kunuku:BAAANQADCgEIAQAAAA==.Kurogen:BAAANQADCgUIBwAAAA==.',
['Kë']='Këy:BAAANQAECgQIBwAAAA==.',
La='Lanasia:BAAANQADCgYICgAAAA==.Lancashire:BAAANQABCgYICQAAAA==.Larchel:BAAANQAECgYICgAAAA==.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAABNQAECoEXAAMFAAkJOCD5EQAvAwAFAAkJOCD5EQAvAwAGAAEJlhO6GgBBAAAAAA==.Lazerturkey:BAAANQAECgQIBQAAAA==.Laërtes:BAAANQADCgYIDQAAAA==.',
Le='Leviscus:BAAANQADCgUICAAAAA==.',
Li='Lightbill:BAAANQAECgQIBQAAAA==.Lilriotz:BAAANQADCgUIBwAAAA==.Lilriotzz:BAAANQAECgcICAAAAA==.Lilxblitzx:BAAANQADCgYIDAAAAA==.Lilzdrlockz:BAAANQADCgMIAwAAAA==.Lilzriotz:BAAANQADCgYIBwAAAA==.',
Lu='Lucyvar:BAAANQADCgYIEwAAAA==.',
Ma='Marhukai:BAAANQAECgQIBQAAAA==.Marotal:BAAANQAECggIEQAAAA==.Martysparty:BAAANQADCgYIDAAAAA==.Mavaena:BAAANQADCgMIAwAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAAANQADCggIEAAAAA==.Megahertz:BAAANQADCgQIBAAAAA==.',
Mh='Mhael:BAAANQADCgQIBAAAAA==.',
Mi='Milkboi:BAAANQAECgQICQAAAA==.Minogon:BAAANQADCgEIAQAAAA==.Minsofar:BAAANQADCgUIBQAAAA==.Mistilinn:BAAANQAECgEIAQAAAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAABNQAECoFDAAIHAAkJHCY2AAD9AwAHAAkJHCY2AAD9AwAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.',
Mu='Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAAANQAECgQICgAAAA==.',
My='Mynamefizz:BAEANQADCggIGwABNQADCgcICgACAAAAAA==.',
Ni='Nicola:BAAANQAECgMIAwAAAA==.Nightxwish:BAAANQADCgcIEQAAAA==.',
No='Nocko:BAAANQADCggIEwAAAA==.Noisemarine:BAAANQADCgUICQAAAA==.Norellia:BAAANQADCgQIBAAAAA==.Northspirit:BAAANQADCgYIDgAAAA==.',
Ny='Nyx:BAAANQADCgIIAgABNQAECgMIBAACAAAAAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odins:BAAANQADCgYIBgAAAA==.',
Oh='Ohyikers:BAAANQAECggIEwAAAA==.',
Ok='Oken:BAAANQADCgcIEQAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECggIFQAIAMIhAA==.',
Ot='Otso:BAAANQAECgQIBQAAAA==.',
Pa='Paco:BAAANQADCgYIBgAAAA==.Paladime:BAAANQADCgIIAgAAAA==.Pallek:BAAANQADCgUIBQABNQAECgUIBQACAAAAAA==.Palli:BAAANQADCggIDQAAAA==.Pangodlin:BAAANQADCgQIBAAAAA==.Pasta:BAAANQAECgEIAQAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Perph:BAAANQADCgUIBQAAAA==.',
Ph='Phantomarrow:BAAANQADCgYIBgAAAA==.Phantomcat:BAAANQADCggIEQAAAA==.Pharasan:BAAANQAECgQIBAAAAA==.Phatcow:BAAANQAECgUIBwAAAA==.Phude:BAAANQAECgUICAAAAA==.',
Po='Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Pu='Pukefeast:BAAANQADCggIDgAAAA==.',
Py='Pyramys:BAAANQADCggIEwAAAA==.',
['Pè']='Pèrce:BAAANQADCgUIBQAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.',
Ra='Razgrizz:BAAANQADCgUICAAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQADCggIFgABNQABCgYICgACAAAAAA==.',
Ro='Ronmaclean:BAAANQADCgUIBQABNQAECgMIBQACAAAAAA==.Roozer:BAAANQADCgUICAAAAA==.',
Sa='Sad:BAAANQAECgMIBAAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Sainthymn:BAAANQAECggIAQAAAA==.Salv:BAAANQADCggICAAAAA==.',
Sc='Scoreboard:BAAANQAFFAQIBAAAAA==.Scupper:BAAANQAECgQIBQAAAA==.',
Se='Selline:BAAANQADCgYIDAAAAA==.Selsonblue:BAAANQADCgUICAAAAA==.Sesskaa:BAAANQADCggIDgAAAA==.',
Sh='Sharhox:BAAANQADCgcIEAAAAA==.Shishkbob:BAAANQABCgIIAgAAAA==.',
Si='Sigewulf:BAAANQAECgEIAQAAAA==.',
Sk='Skaro:BAAANQAECgEIAQAAAA==.Skarofox:BAAANQADCgIIAgAAAA==.Skarosham:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Sketch:BAAANQAECgcIDQAAAA==.',
Sl='Slambulance:BAAANQAECgYICwAAAA==.Sleepinslime:BAAANQADCggIDwAAAA==.',
Sm='Smokiebear:BAAANQAECggICAAAAA==.',
So='Songa:BAAANQADCgEIAQABNQADCgQIBAACAAAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCgYICwAAAA==.Stinko:BAAANQADCgQIBAAAAA==.Stormlock:BAAANQAECgQIBAAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAAANQADCggIEAAAAA==.Stwampadin:BAAANQAECgMIBAAAAA==.Stwiest:BAAANQADCgcIDAABNQAECgMIBAACAAAAAA==.',
Sw='Swampert:BAAANQAECgcIEQAAAA==.Swamperting:BAAANQAECgMIBAABNQAECgcIEQACAAAAAA==.Swayaos:BAAANQAECgQIBQAAAA==.Swaye:BAAANQAECgQIBQAAAA==.Swifte:BAAANQABCgIIAgAAAA==.Swimchick:BAAANQADCgYIDQAAAA==.Swizzle:BAAANQAECgMIAwAAAA==.',
Sy='Syraelia:BAAANQABCgIIAgABNQAECgQIBgACAAAAAA==.',
Sz='Szeto:BAAANQADCgMIAwAAAA==.',
['Sî']='Sîrprîse:BAAANQADCgYICwAAAA==.',
Ta='Tagmoo:BAAANQAECgQIBQAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Taloon:BAAANQADCgEIAQAAAA==.Taltost:BAAANQADCggIDgAAAA==.Tarv:BAAANQADCgYICwAAAA==.',
Te='Teksuo:BAAANQAECgUICAAAAA==.Telamontgrim:BAAANQADCggIDQAAAA==.Tenithon:BAABNQAECoEVAAIIAAgJwiEGBwAbAwAIAAgJwiEGBwAbAwAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQADCgYIDgAAAA==.Tholaren:BAAANQADCggIEAAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Tinkerspell:BAAANQADCggIDAAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAAANQADCgcIDwAAAA==.Trillion:BAAANQADCgYIDAAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQADCgYICQAAAA==.',
Ud='Udari:BAAANQADCgcIDgAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.',
Va='Varithal:BAAANQAECgUICAAAAA==.Vastectomy:BAAANQADCgcIEAAAAA==.',
Ve='Venawyn:BAAANQADCggIDgAAAA==.Verso:BAAANQADCgMIAwAAAA==.',
Vi='Viard:BAAANQAECgQIBAAAAA==.Vicious:BAAANQAECgQIBgAAAA==.Vixin:BAAANQADCgYIDwAAAA==.',
Vo='Voidsaack:BAAANQAECgEIAQAAAA==.Vortan:BAAANQAECgMIBgAAAA==.',
Vr='Vreya:BAAANQABCgEIAQABNQADCgUICAACAAAAAA==.',
Vy='Vyndrae:BAAANQADCgcIDgAAAA==.Vynthus:BAAANQADCggIDgAAAA==.',
Wa='Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQADCgcIBwAAAA==.Wazzle:BAAANQAECgIIAgAAAA==.',
Wh='Whatmyname:BAAANQADCggIGAAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQADCgcICgACAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.',
Wy='Wymstar:BAAANQADCggIDwAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIDwACAAAAAA==.',
Xu='Xuny:BAAANQADCgYICwAAAA==.',
Yo='Yordi:BAAANQAECgEIAQAAAA==.Yoyopapa:BAAANQADCgIIAgAAAA==.',
Yu='Yuzuriha:BAAANQAECgUICAAAAA==.',
Za='Zamaze:BAAANQADCgcIDQAAAA==.',
Ze='Zeekielle:BAEANQAECgYICQAAAA==.',
Zi='Zipy:BAAANQADCggIEAAAAA==.',
Zy='Zyllo:BAAANQADCgUIBQAAAA==.',
['Ål']='Ålïce:BAAANQAECgIIAwAAAA==.',
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
