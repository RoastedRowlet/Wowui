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

local lookup = {'Shaman-Enhancement','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Hunter-BeastMastery','DemonHunter-Devourer','Mage-Arcane','Mage-Frost','Druid-Balance','Paladin-Holy','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','Warlock-Demonology','Warlock-Destruction',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Addely:BAAANQAECgYICgAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcIBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgQIBQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgEIAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.',
Al='Alaralia:BAAANQAECgQIBAABNQAFFAMIBQABAIMgAA==.Alarathel:BAAANQADCggICAABNQAFFAMIBQABAIMgAA==.Alyssandra:BAAANQAECgMIAwAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCgYIDgAAAA==.Ammalane:BAAANQABCgYIDQABNQADCgYIDgACAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.',
Ap='Apollyon:BAAANQAECggICAAAAA==.',
Ar='Arangarr:BAAANQAECgUIDAAAAA==.Aresiuz:BAAANQAECgcICgAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQADCgcIFgAAAA==.Arrietty:BAAANQADCggIGQAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAAANQADCgUIBQAAAA==.',
As='Asmodea:BAAANQADCgYICwAAAA==.',
At='Atlasfall:BAAANQADCggIFwAAAA==.',
Az='Az:BAAANQADCggIFgAAAA==.Azeriall:BAAANQAECgYIDQAAAA==.',
Ba='Baconhammr:BAAANQADCggIDgAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAACAAAAAA==.Banshiï:BAAANQAECgEIAQAAAA==.Baratheøn:BAAANQAECgIIAwAAAA==.',
Be='Beefcrits:BAAANQAECgEIAQAAAA==.Beeftard:BAAANQAECgQICQAAAA==.',
Bi='Bifficus:BAAANQADCgUICQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQADCggIEAAAAA==.',
Bl='Blackfyre:BAAANQADCggIEQAAAA==.Blackscorn:BAAANQADCgQIBAAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQADCggIFgAAAA==.',
Bo='Bollace:BAAANQADCgUIBQABNQADCgcIBwACAAAAAA==.',
By='Byzantium:BAAANQAECgIIAgAAAA==.',
['Bô']='Bônebeard:BAAANQAECgIIAgAAAA==.',
Ca='Caluu:BAAANQADCgUIDgAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Co='Coldstorm:BAAANQAECgYICwAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cy='Cynderleena:BAAANQADCgYIEgAAAA==.Cynfully:BAAANQABCgIIAgAAAA==.Cynyia:BAAANQAECgYIDQAAAA==.',
Da='Daddyelessar:BAAANQADCgQIBQAAAA==.Dafattyup:BAAANQAECgQIDQAAAA==.Dagon:BAAANQAECgEIAQAAAA==.Dagreenmeany:BAAANQADCggIJQAAAA==.Darruin:BAABNQAECoEdAAIDAAkJoSRAAgC/AwADAAkJoSRAAgC/AwAAAA==.Dawncrow:BAAANQADCggIEgAAAA==.',
De='Deathwange:BAAANQADCgcIBwAAAA==.Deavaos:BAAANQADCggIFgAAAA==.Deeanndra:BAAANQAECgQIAwAAAA==.Demiz:BAAANQAECgYIDQAAAA==.Deredris:BAAANQADCgYIDAABNQAECgIIAgACAAAAAA==.',
Di='Discodruid:BAAANQAECgEIAQAAAA==.Discover:BAAANQADCgUIDAAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMIBAAAAA==.Dommy:BAAANQADCggIEwAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAABNQAECoEUAAMDAAgJtyCBGgBsAgADAAcJFx+BGgBsAgAEAAIJvR9PNQC/AAAAAA==.Dorkimedes:BAAANQAECgEIAQAAAA==.Dottie:BAAANQAECgYIBgAAAA==.',
Dr='Draelesh:BAAANQAECgIIAgAAAA==.',
Du='Durenn:BAAANQAECgYICwAAAA==.Duskmane:BAAANQABCgIIAgAAAA==.',
Dw='Dwadler:BAAANQAECgEIAQAAAA==.',
Dy='Dyrkazen:BAAANQADCggIFgAAAA==.',
Ec='Eclipses:BAAANQADCgYIDgAAAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECgUIDAACAAAAAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAAANQAECgcIEQAAAA==.',
Ev='Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQADCggIFAAAAA==.',
Fa='Faevelia:BAAANQADCgQIDAAAAA==.Fanshen:BAAANQADCgYIDgAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQADCggIFgAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Fenfen:BAAANQAECgIIAgAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAMIBQABAIMgAA==.',
Fi='Fishtank:BAAANQAECgEIAQABNQAECgYICwACAAAAAA==.Fizehbubbleh:BAEANQADCgYIBgABNQADCgcICgACAAAAAA==.Fizehtotems:BAEANQADCgcICgAAAA==.',
Fo='Foragarn:BAAANQADCgYIBAAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgQIBgAAAA==.Froznfate:BAAANQAECgIIAgAAAA==.',
Fw='Fwibble:BAAANQABCgIIAgABNQADCgUIBQACAAAAAA==.',
Fy='Fyrelady:BAAANQADCgYIDgAAAA==.',
Ga='Gaboldor:BAAANQADCgUIBQAAAA==.Garagon:BAAANQAECgIIAgAAAA==.Garlicbread:BAAANQAECgQIBAAAAA==.Gauss:BAAANQADCgUIBQAAAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAAANQAECgIIAgAAAA==.',
Gh='Ghorfindor:BAAANQADCggIGQAAAA==.Ghostems:BAAANQAECgQIBAABNQAECgkJGQAFADgkAA==.',
Gi='Gilas:BAAANQAECgIIAgAAAA==.',
Gl='Glaedr:BAAANQAECgQIBQABNQADCggIFgACAAAAAA==.Globeasaure:BAAANQAECgIIAgAAAA==.',
Gn='Gnikole:BAAANQAECgIIAgAAAA==.',
Go='Goswin:BAAANQAECgIIAgAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQADCgMIAwAAAA==.Greenfelpowa:BAAANQAECgUIBgAAAA==.Gruuven:BAAANQAECgcICwAAAA==.',
Gu='Gutmtmon:BAAANQADCggIBQAAAA==.',
Gw='Gwenivive:BAAANQAECgQIBQAAAA==.',
['Gí']='Gízmo:BAABNQAECoEXAAIGAAgJtxKDLQBGAgAGAAgJtxKDLQBGAgAAAA==.',
['Gû']='Gûnter:BAAANQADCgMIBQAAAA==.',
Ha='Hakaii:BAAANQAECgMIBQAAAA==.Happyness:BAAANQADCgYIBgAAAA==.',
He='Hellzknîght:BAAANQADCggIGwAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgEIAQAAAA==.',
Ho='Holek:BAAANQAECgUICwAAAA==.Holgo:BAAANQAECggICAAAAA==.Holstop:BAAANQAECgYIBwABNQAFFAIIAwACAAAAAA==.Honzz:BAAANQADCgMIBAAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAACAAAAAA==.',
Hu='Hugecowballs:BAAANQADCgIIAgAAAA==.Huntaholic:BAAANQAECgQIBQAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAAANQAECgQICAAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAAANQAECgUIBgAAAA==.Isevio:BAAANQADCgYIDQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQADCgQIBAAAAA==.Jaade:BAAANQADCgYIDgAAAA==.Jaiswizzle:BAAANQADCgEIAQAAAA==.Jamien:BAAANQAECgQIBgAAAA==.Jasnos:BAAANQADCggIGQAAAA==.Jayy:BAAANQADCgUIBQAAAA==.',
Je='Jean:BAAANQAECgQIBAAAAA==.',
Ka='Kaathe:BAAANQAECgEIAwAAAA==.Kaidiis:BAAANQAECgIIAgAAAA==.Karbonn:BAAANQADCggIEQAAAA==.Katrina:BAAANQADCgIIAgABNQAECgcIFgAHAHkRAA==.',
Ke='Kegbreaker:BAAANQAECgUICgAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQADCgUIDQAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAAANQAECgYICwAAAA==.Kimbustible:BAAANQAECgMIAwABNQAECgYICwACAAAAAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.',
Ko='Komodostyle:BAAANQAECgQIBgAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAAANQAECgQICwAAAA==.',
Kr='Krisarugala:BAAANQADCggIFQAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAAANQADCggICQAAAA==.Kurogen:BAAANQADCgYIDQAAAA==.',
['Kë']='Këy:BAAANQAECgQICQAAAA==.',
['Kö']='Köloth:BAAANQADCgMIAwAAAA==.',
La='Lanasia:BAAANQADCgYICgAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAAANQAECgcIEQAAAA==.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAABNQAECoEfAAMIAAkJjyINEgBdAwAIAAkJjyINEgBdAwAJAAEJlhMFJQA+AAAAAA==.Lazerturkey:BAAANQAECgQICQAAAA==.Laërtes:BAAANQADCgYIEQAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgYIDgAAAA==.',
Li='Lightbill:BAAANQAECgUICgAAAA==.Lightbàne:BAAANQADCgYIBgAAAA==.Lilriotz:BAAANQADCgUIBwAAAA==.Lilriotzz:BAAANQAECggIEAAAAA==.Lilxblitzx:BAAANQAECgQIBAAAAA==.Lilzdrlockz:BAAANQADCgMIAwAAAA==.',
Lu='Lucyvar:BAAANQADCgcIGgAAAA==.',
['Lü']='Lüma:BAAANQADCgQIBAAAAA==.',
Ma='Marhukai:BAAANQAECgUICgAAAA==.Marotal:BAABNQAECoEaAAIIAAgJbRFfXgAsAgAIAAgJbRFfXgAsAgAAAA==.Martysparty:BAAANQAECgEIAQAAAA==.Mavaena:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAAANQAECgIIAgAAAA==.Megafire:BAAANQADCgUIBQAAAA==.Megahertz:BAAANQADCgYICgAAAA==.',
Mh='Mhael:BAAANQADCgQIBAAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minsofar:BAAANQADCgYICgAAAA==.Mistilinn:BAAANQAECgUIBgAAAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAABNQAECoFFAAIKAAkJHCbFAADrAwAKAAkJHCbFAADrAwAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggICAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAAANQAECgYIEQAAAA==.',
My='Mylinkah:BAAANQAECgEIAQAAAA==.Mynamefizz:BAEANQAECgIIAgABNQADCgcICgACAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Mé']='Méasha:BAAANQADCggICAAAAA==.',
Ni='Nicola:BAAANQAECgMIBAAAAA==.Nightxwish:BAAANQADCggIGQAAAA==.',
No='Nocko:BAAANQADCggIFAAAAA==.Noisemarine:BAAANQADCgUICQAAAA==.Norellia:BAAANQADCgQIBAAAAA==.Northspirit:BAAANQADCgYIFAAAAA==.',
Nu='Nuit:BAAANQAECgIIAgAAAA==.',
Ny='Nyarlothep:BAAANQADCgUIBQAAAA==.Nyx:BAAANQADCgIIAgABNQAECgQIBgACAAAAAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgIIAgABNQAECgcIBwACAAAAAA==.Odins:BAAANQAECgcIBwAAAA==.',
Oh='Ohyikers:BAABNQAECoEgAAIKAAkJuyXMAADpAwAKAAkJuyXMAADpAwAAAA==.',
Ok='Oken:BAAANQADCggIGQAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECggIIwALADAiAA==.',
Ot='Otso:BAAANQAECgUICgAAAA==.',
Pa='Paco:BAAANQADCgYIBgAAAA==.Paladime:BAAANQAECgMIAwAAAA==.Pallek:BAAANQADCgcIDgABNQAECgUICwACAAAAAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgQIBAAAAA==.Pasta:BAAANQAECgIIAwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Perph:BAAANQADCgUIBQAAAA==.',
Ph='Phantomarrow:BAAANQADCgYIBgAAAA==.Phantomcat:BAAANQADCggIEQAAAA==.Pharasan:BAAANQAECgQIBAAAAA==.Phatcow:BAAANQAECgcIDQAAAA==.Phude:BAAANQAECgYIDgAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Pu='Pukefeast:BAAANQAECgEIAQAAAA==.',
Py='Pyramys:BAAANQAECgMIAwAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Razgrizz:BAAANQADCgYIDgAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAACAAAAAA==.',
Ro='Ronmaclean:BAAANQADCgUIBQABNQAECgYICwACAAAAAA==.Roozer:BAAANQADCgYIDgAAAA==.',
Sa='Sad:BAAANQAECgQICAAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Sainthymn:BAAANQAECggIBwAAAA==.Salv:BAAANQADCggICAAAAA==.',
Sc='Scoreboard:BAACNQAFFIEGAAIMAAUJdh4aAAATAgAMAAUJdh4aAAATAgA1AAQKgRsAAgwACAnQJoUAAKUDAAwACAnQJoUAAKUDAAAA.Scupper:BAAANQAECgUICgAAAA==.',
Se='Selline:BAAANQADCgYIDAAAAA==.Selsonblue:BAAANQADCgUICAAAAA==.Sesskaa:BAAANQAECgIIAgAAAA==.',
Sh='Sharhox:BAAANQAECgIIAgAAAA==.Shishkbob:BAAANQABCgIIAgAAAA==.',
Si='Sigewulf:BAAANQAECgQIBQAAAA==.',
Sk='Skaro:BAAANQAECgEIAQAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Skarosham:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Sketch:BAABNQAECoEVAAINAAgJCgxAFAD7AQANAAgJCgxAFAD7AQAAAA==.',
Sl='Slambulance:BAAANQAECgcIEgAAAA==.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokiebear:BAAANQAECggICAAAAA==.',
So='Solomun:BAAANQAECgQIDQAAAA==.Songa:BAAANQADCgEIAQABNQADCgQIBAACAAAAAA==.',
Sp='Spinky:BAAANQADCgUIBQAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCgYICwAAAA==.Stinko:BAAANQADCgQIBAAAAA==.Stormlock:BAAANQAECgQICAAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAAANQAECgIIAgAAAA==.Stwampadin:BAAANQAECgQIBwAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIBwACAAAAAA==.',
Su='Surloyn:BAAANQADCggICAAAAA==.',
Sw='Swampert:BAABNQAECoEYAAIOAAgJyBe6NQBjAgAOAAgJyBe6NQBjAgAAAA==.Swamperting:BAAANQAECgMIBAABNQAECggIGAAOAMgXAA==.Swayaos:BAAANQAECgUICgAAAA==.Swaye:BAAANQAECgUICgAAAA==.Swifte:BAAANQABCgIIAgAAAA==.Swimchick:BAAANQADCgYIEQAAAA==.Swizzle:BAAANQAECgUICAAAAA==.',
Sy='Syllena:BAAANQAECgQICgABNQAECgQICgACAAAAAA==.Syraelia:BAAANQABCgIIAgABNQAECgQICgACAAAAAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCgcIEQAAAA==.',
Ta='Tagmoo:BAAANQAECgUICgAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Taloon:BAAANQAECgEIAQAAAA==.Taltost:BAAANQAECgIIAgAAAA==.Talzith:BAAANQADCgYIBgAAAA==.Tarv:BAAANQADCggIDgAAAA==.',
Te='Teksuo:BAAANQAECgYIDgAAAA==.Telamontgrim:BAAANQAECgEIAQAAAA==.Tenithon:BAABNQAECoEjAAILAAgJMCLtCgAcAwALAAgJMCLtCgAcAwAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIAgAAAA==.Tholaren:BAAANQAECgIIAgAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Tinkerspell:BAAANQADCggIDAAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAAANQADCggIFwAAAA==.Trikshawt:BAAANQAECgIIAgAAAA==.Trillion:BAAANQAECgEIAQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQADCgYICQAAAA==.',
Ud='Udari:BAAANQAECgIIAgAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.',
Us='Usednabused:BAAANQAECgIIAgAAAA==.',
Uz='Uzume:BAAANQADCgIIAgAAAA==.',
Va='Varithal:BAAANQAECgYIDgABNQABCgEIAQACAAAAAA==.Vastectomy:BAAANQAECgIIAgAAAA==.',
Ve='Venawyn:BAAANQAECgIIAgAAAA==.Verso:BAAANQADCgMIAwAAAA==.',
Vi='Viard:BAABNQAECoELAAMPAAcJUhaMSwCcAQAPAAYJ4hSMSwCcAQAQAAQJXguMKwDnAAAAAA==.Vicious:BAAANQAECggIDgAAAA==.Vixin:BAAANQADCggIFwAAAA==.',
Vo='Voidsaack:BAAANQAECgQIBQAAAA==.Vortan:BAAANQAECgQICgAAAA==.',
Vr='Vreya:BAAANQABCgEIAQABNQADCgYIDgACAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIIAgAAAA==.Vynthus:BAAANQADCggIFQAAAA==.',
Wa='Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgMIAwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQADCgcIBwAAAA==.Wazzle:BAAANQAECgMIBQAAAA==.Wazzmage:BAAANQADCgYIBgAAAA==.',
Wh='Whatmyname:BAAANQAECgIIAgAAAA==.Whispp:BAAANQAECgIIAgAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQADCgcICgACAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.',
Wy='Wymstar:BAAANQADCggIDwAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIDwACAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggIDwACAAAAAA==.',
Xu='Xuny:BAAANQADCgcIEgAAAA==.',
Yo='Yordi:BAAANQAECgEIAQAAAA==.Yoyopapa:BAAANQADCgIIAgAAAA==.',
Yu='Yuzuriha:BAAANQAECgYIDgAAAA==.',
Za='Zamaze:BAAANQADCgcIEgAAAA==.',
Ze='Zeekielle:BAEANQAECgYIDwABNQAECggICwACAAAAAA==.',
Zi='Zipy:BAAANQAECgIIAgAAAA==.',
Zy='Zyllo:BAAANQADCgUIBQAAAA==.',
['Zæ']='Zæ:BAAANQADCgQIBAAAAA==.',
['Ål']='Ålïce:BAAANQAECgQIBwAAAA==.',
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
