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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Evoker-Preservation','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Devastation','Druid-Guardian','Paladin-Protection','DemonHunter-Havoc','Priest-Holy','Mage-Frost','Paladin-Retribution','Monk-Mistweaver','Druid-Balance','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Addely:BAABNQAECoEWAAIBAAcK5g3rwgCuAQABAAcK5g3rwgCuAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgUIDQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgEJAQAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.',
Al='Alaralia:BAAANQAECggIEAABNQAFFAQICgACAD8fAA==.Alarathel:BAAANQADCggICAABNQAFFAQICgACAD8fAA==.Alyssandra:BAAANQAECgUICAAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCgcIEAAAAA==.Ammalane:BAAANQADCgEJAQABNQADCgcIEAADAAAAAA==.',
An='Anabelli:BAAANQADCgEIAQAAAA==.',
Ap='Apollyon:BAAANQAECggICAAAAA==.',
Ar='Arangarr:BAABNQAECoEcAAIEAAgKgx9aDADQAgAEAAgKgx9aDADQAgAAAA==.Aresiuz:BAAANQAECggIEgABNQAFFAUICQAFAB8NAA==.Areyana:BAAANQADCgYIBgAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQADCggIJgAAAA==.Arrietty:BAAANQAECgIIAwAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAAANQADCgUIBQAAAA==.',
As='Asmodea:BAAANQADCgYICwAAAA==.',
At='Atlasfall:BAAANQAECgEIAQAAAA==.',
Az='Az:BAAANQAECgMIAwAAAA==.Azeriall:BAABNQAECoEfAAIGAAgKkRcCOABQAgAGAAgKkRcCOABQAgAAAA==.',
Ba='Bacnfen:BAAANQAECgQICQAAAA==.Baconhammr:BAAANQADCggIFAAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAADAAAAAA==.Banshiï:BAAANQAECgQIBQAAAA==.Baratheøn:BAAANQAECgMICAAAAA==.',
Be='Beeftard:BAABNQAECoEVAAIHAAcKCx19MgBfAgAHAAcKCx19MgBfAgAAAA==.',
Bi='Bifficus:BAAANQADCgUICQAAAA==.Bippity:BAAANQAECgQICAAAAA==.Bivon:BAAANQAECgEIAQAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgQIBQAAAA==.',
Bo='Bollace:BAAANQADCgUIBQABNQADCgcIBwADAAAAAA==.',
By='Byzantium:BAAANQAECgQICQAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICAAAAA==.',
Ca='Caluu:BAAANQAECgEIAQAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAQICgAIAHQRAA==.',
Ch='Chromatic:BAAANQADCgcIBwAAAA==.',
Co='Coffeeblak:BAAANQADCgIIAgAAAA==.Coldstorm:BAAANQAECgYIEQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAAANQAECgIIAwAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECoEfAAIJAAgKbhh4RQBRAgAJAAgKbhh4RQBRAgAAAA==.',
Da='Daddyelessar:BAAANQADCgUICwAAAA==.Dafattyup:BAAANQAECgUIDgAAAA==.Dagon:BAAANQAECgEIAQAAAA==.Dagreenmeany:BAAANQADCggIMQAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Darruin:BAACNQAFFIEIAAIKAAQKfSQzBACOAQAKAAQKfSQzBACOAQA1AAQKgSQAAgoACQobJd0FAIADAAoACQobJd0FAIADAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQABCgIIAwAAAA==.Deathblitz:BAAANQAECgIIAgABNQAECggICAADAAAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAAANQAECgUICQAAAA==.Deeanndra:BAAANQAECgYICgAAAA==.Demiz:BAABNQAECoEgAAIFAAgKTRaWRgD5AQAFAAgKTRaWRgD5AQAAAA==.Demonicus:BAAANQAECgEIAQAAAA==.Deredris:BAAANQAECgQIBQAAAA==.',
Di='Discodruid:BAAANQAECgQIBgAAAA==.Discover:BAAANQADCgYIEgAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQADCgMJBAAAAA==.Domittila:BAAANQAECgQIBQABNQAFFAUICQAFAB8NAA==.Dommy:BAAANQADCggIFgAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFIELAAMLAAUKBROzBQA4AQALAAQKgxKzBQA4AQAKAAIKfxP5DgCSAAA1AAQKgRgAAwoACAoXIucpADsCAAoABwq/IecpADsCAAsAAgqeIn5cALcAAAAA.Dorkimedes:BAAANQAECgUIBgAAAA==.Dottie:BAAANQAECgcIEwAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Durenn:BAAANQAFFAIIAgABNQAFFAQICAAKAH0kAA==.Duskmane:BAAANQABCgIIAgAAAA==.',
Dw='Dwadler:BAAANQAECgQICAAAAA==.',
Dy='Dyrkazen:BAAANQAECgUICQAAAA==.',
Ec='Eclipses:BAAANQADCgcIDwAAAA==.',
Ed='Edris:BAAANQAECgEIAQABNQAFFAUICQAFAB8NAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECggIHgAKACgUAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECoEhAAMIAAkKKwsbGgDjAQAIAAkKKwsbGgDjAQAMAAUKxhYOGgBrAQAAAA==.',
Er='Erébus:BAAANQADCgIIAgABNQAECgcIFgANAOodAA==.',
Ev='Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQAECgMIBgAAAA==.',
Ew='Ewanar:BAABNQAFFIEJAAMFAAUKHw0dDAAjAQAFAAQK9AYdDAAjAQAGAAEKEQToJABBAAAAAA==.',
Fa='Faevelia:BAAANQADCgUIFgAAAA==.Fanshen:BAAANQADCgcIDwAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQAECgIIAgAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAQICgACAD8fAA==.',
Fi='Fishtank:BAAANQAECgQJBAABNQAECggIGgAJAMAQAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQIBQADAAAAAA==.Fizehtotems:BAEANQAECgQIBQAAAA==.',
Fo='Foragarn:BAAANQADCgYIBAAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQADCgYIBwAAAA==.Froznfate:BAAANQAECgQIBgAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYIBwAAAA==.',
Fw='Fwibble:BAAANQADCggICAABNQAECgIIAgADAAAAAA==.',
Fy='Fyrelady:BAAANQADCgcIEAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCgcIEAADAAAAAA==.',
Ga='Gaboldor:BAAANQADCgUIBQAAAA==.Garagon:BAAANQAECgUICQAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAAANQAECgIIAgAAAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAAANQAECgMIBwAAAA==.',
Gh='Ghorfindor:BAAANQAECgEIAQAAAA==.Ghostems:BAAANQAFFAIIAgABNQAFFAMIBgAOAPofAA==.',
Gi='Gilas:BAAANQAECgQICQAAAA==.',
Gl='Glaedr:BAAANQAECgYICwABNQADCggIFgADAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAAANQAECgUICwAAAA==.',
Gn='Gnikole:BAAANQAECgUICgAAAA==.',
Go='Goswin:BAAANQAECgUICwAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQADCgMIAwABNQAECgEIAQADAAAAAA==.Greenfelpowa:BAAANQAECgYIDAAAAA==.Gruuven:BAAANQAECgcJDAAAAA==.',
Gu='Gutmtmon:BAAANQADCggIBQAAAA==.',
Gw='Gwenivive:BAAANQAECgcIEQAAAA==.',
['Gí']='Gízmo:BAABNQAECoEYAAIJAAgKtxJHWgATAgAJAAgKtxJHWgATAgAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAAANQAECgYIEQAAAA==.Happyness:BAAANQADCgYJBgAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzknîght:BAAANQAECgQICwAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgIIAwAAAA==.',
Ho='Holek:BAABNQAECoEhAAIJAAkKIxhiKwCuAgAJAAkKIxhiKwCuAgAAAA==.Holgo:BAAANQAFFAMIAwAAAA==.Holstop:BAAANQAECgYIDwABNQAFFAUIDAAIACwmAA==.Holykimoly:BAAANQAECgMIAwABNQAECggIEwADAAAAAA==.Honsz:BAAANQADCgEIAQAAAA==.Honzz:BAAANQADCgYICgAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAADAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEAAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAAANQAECgYIEwAAAA==.Icicle:BAAANQAECgMIAwAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAAANQAECgcIEAAAAA==.Isevio:BAAANQADCgYIDQAAAA==.',
It='Ithorus:BAAANQADCggICAAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQADCgQIBAAAAA==.Jaade:BAAANQADCgYIDgAAAA==.Jaiswizzle:BAAANQAECgcICAAAAA==.Jamien:BAAANQAECgYIDQAAAA==.Jasnos:BAAANQAECgIIAwAAAA==.Jayy:BAAANQADCggJCAAAAA==.',
Je='Jean:BAAANQAECgcIEAAAAA==.',
Ka='Kaathe:BAAANQAECgMIBwAAAA==.Kaidiis:BAAANQAECgQIBgAAAA==.Karbonn:BAAANQADCggIFwAAAA==.Katrina:BAAANQADCgIJAgABNQAECgkJKAAPALkPAA==.',
Ke='Kegbreaker:BAABNQAECoEYAAIQAAcKhxIIVwDAAQAQAAcKhxIIVwDAAQAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQADCggIGwAAAA==.',
Ki='Kikieo:BAAANQADCgQJBAAAAA==.Kimbliddan:BAAANQAECggIEwAAAA==.Kimbustible:BAAANQAECgMIBAABNQAECggIEwADAAAAAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.',
Ko='Komodostyle:BAAANQAECgUIEAAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAAANQAECgYIEQAAAA==.',
Kr='Krisarugala:BAAANQAECgUICAAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAAANQAECgEIAQAAAA==.Kurogami:BAAANQADCgEJAQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAAANQAECgYIDwAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCgYICgAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAABNQAECoEmAAIGAAkKTRbyKwCQAgAGAAkKTRbyKwCQAgAAAA==.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFIENAAMRAAUKuiBGAADRAQARAAUKwhtGAADRAQABAAQKFRaZFgBhAQA1AAQKgSMAAwEACQp3I/ImAC0DAAEACQp3I/ImAC0DABEAAwqxHjsWAAoBAAAA.Lazerturkey:BAAANQAECgYIEwAAAA==.Laërtes:BAAANQAECgQIBQAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIEAAAAA==.',
Li='Lightbill:BAABNQAECoEYAAMHAAcKMxlhQgAbAgAHAAcKMxlhQgAbAgASAAIK0gxAIQFrAAAAAA==.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQADCgUIBwAAAA==.Lilriotzz:BAABNQAECoEfAAIFAAkKBhYSJwCMAgAFAAkKBhYSJwCMAgAAAA==.Lilxblitzx:BAAANQAECgQICwAAAA==.Lilzdrlockz:BAAANQADCgMIAwAAAA==.Lilzriotz:BAAANQAECgEIAgAAAA==.Lilzzriotz:BAAANQADCgYIBgAAAA==.',
Lu='Lucyvar:BAAANQAECggIBwAAAA==.Luma:BAAANQAECgQIBQAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAAANQAECgUIDgAAAA==.Marlow:BAAANQADCgcICAAAAA==.Marotal:BAABNQAECoEaAAIBAAgKbRF4nAACAgABAAgKbRF4nAACAgAAAA==.Martysparty:BAAANQAECgIIAwAAAA==.Mavaena:BAAANQADCgYICwAAAA==.Maxlife:BAAANQAECggIBgAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAAANQAECgUICQAAAA==.Megafire:BAAANQADCgUIDgAAAA==.Megahertz:BAAANQAECgEIAQAAAA==.',
Mh='Mhael:BAAANQAECgQIBAAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minphoria:BAAANQABCgIIAgAAAA==.Minsofar:BAAANQADCggIEgAAAA==.Mistilinn:BAAANQAECgYIEQAAAA==.Miyri:BAAANQAECgEIAQABNQAECgcIIAATALglAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFIEKAAIUAAUK7xbLBwCkAQAUAAUK7xbLBwCkAQA1AAQKgW8AAhQACQrRJicAAA8EABQACQrRJicAAA8EAAAA.Morpheus:BAAANQADCgQIBAAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECoEeAAMRAAcK8ReDFQATAQABAAcK8Rd2mgAHAgARAAUKlRWDFQATAQAAAA==.',
My='Mylinkah:BAAANQAECgEIAQAAAA==.Mynamefizz:BAEANQAECgQIBgABNQAECgQIBQADAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Mé']='Méasha:BAAANQAECgIJAgAAAA==.',
Ni='Nicola:BAAANQAECgUICwAAAA==.Nightxwish:BAAANQAECgIIAwAAAA==.',
No='Nocko:BAAANQADCggIFwAAAA==.Norellia:BAAANQAECgEIAQAAAA==.Northspirit:BAAANQADCgYIHwAAAA==.',
Nu='Nuit:BAAANQAECgIIAgAAAA==.',
Ny='Nyarlothep:BAAANQADCgYIEAAAAA==.Nyx:BAAANQADCgIIAgABNQAECgYIDQADAAAAAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgUIBQABNQAECggIDgADAAAAAA==.Odins:BAAANQAECggIDgAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgEJAQABNQADCgYICQADAAAAAA==.Ohyikers:BAACNQAFFIEJAAIUAAQKkx3FCQB5AQAUAAQKkx3FCQB5AQA1AAQKgTwAAhQACQoZJvcAAOoDABQACQoZJvcAAOoDAAAA.',
Ok='Oken:BAAANQAECgIIAwAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECgkJQgAHAIskAA==.',
Ot='Otso:BAABNQAECoEWAAINAAcK6h2yCgBQAgANAAcK6h2yCgBQAgAAAA==.',
Pa='Paco:BAAANQADCgYIBgAAAA==.Paladime:BAAANQAECgUIDAAAAA==.Pallek:BAAANQADCggIFgABNQAECgkJIQAJACMYAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgQIBAAAAA==.Pasta:BAAANQAECgIIAwAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQADCggIDQAAAA==.',
Ph='Phantomarrow:BAAANQADCgYIBgAAAA==.Phantomcat:BAAANQAECgUIBQAAAA==.Phantomlock:BAAANQAECggIEwAAAA==.Pharasan:BAAANQAECgUIDQAAAA==.Phatcow:BAABNQAECoEaAAIFAAgKMxzsKQB9AgAFAAgKMxzsKQB9AgAAAA==.Pheral:BAEANQADCgIIAgABNQAECggIHwAPAOMNAA==.Phude:BAABNQAECoEjAAISAAgKYxQgaQAGAgASAAgKYxQgaQAGAgAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIAgAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Pu='Pukefeast:BAAANQAECgEIAgAAAA==.',
Py='Pyramys:BAAANQAECgUIDAAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQABCgYIBQAAAA==.Razgrizz:BAAANQADCgcIDwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAADAAAAAA==.Rivër:BAAANQAECgUIBQAAAA==.',
Ro='Ronmaclean:BAAANQADCgUIBQABNQAECgYIEQADAAAAAA==.Roozer:BAAANQADCgcIDwAAAA==.',
Sa='Sabadahoo:BAAANQADCgIIAgABNQAECgQIDwADAAAAAA==.Sad:BAAANQAECgUIDQAAAA==.Saelyria:BAAANQAECgQIBAABNQAECgcIIAATALglAA==.Sagepower:BAAANQADCgIIAgAAAA==.Sainthymn:BAAANQAECggICQAAAA==.Salv:BAAANQAECgMIBAAAAA==.Sandiera:BAAANQAECgUIBQAAAA==.',
Sc='Scoreboard:BAACNQAFFIEHAAIVAAUKdh5XAAD1AQAVAAUKdh5XAAD1AQA1AAQKgS0AAhUACAr6JqkAAKkDABUACAr6JqkAAKkDAAAA.Scupper:BAABNQAECoEYAAIVAAcKGhZICADwAQAVAAcKGhZICADwAQAAAA==.',
Se='Sedric:BAAANQADCgQIBAAAAA==.Selline:BAAANQADCgYIEQAAAA==.Selsonblue:BAAANQADCgYICQAAAA==.Sesskaa:BAAANQAECgQICQAAAA==.',
Sh='Sharhox:BAAANQAECgUICwAAAA==.Shishkbob:BAAANQAECgEIAQAAAA==.Shätterz:BAAANQADCgUJBQABNQADCggIEgADAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAAANQAECgQICAAAAA==.',
Sk='Skaro:BAAANQAECgUIBgAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgUIBgADAAAAAA==.Skarosham:BAAANQADCggICAABNQAECgUIBgADAAAAAA==.Sketch:BAABNQAECoEfAAIWAAkKcwxiIwAKAgAWAAkKcwxiIwAKAgAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAABNQAECoEmAAIOAAkKmyC4BQAlAwAOAAkKmyC4BQAlAwAAAA==.Sleepinslime:BAAANQAECgEIAQAAAA==.',
Sm='Smokedamage:BAAANQABCgUICQAAAA==.Smokiebear:BAAANQAECggICAAAAA==.',
So='Solomun:BAABNQAECoEgAAIHAAkKqxTUKwB/AgAHAAkKqxTUKwB/AgAAAA==.Songa:BAAANQADCgEIAQABNQAECgIJAgADAAAAAA==.',
Sp='Spinky:BAAANQADCgUIBQAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCgYIEAAAAA==.Stinko:BAAANQAECgEIAQAAAA==.Stormlock:BAAANQAECgYIEgAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAAANQAECgMIBwAAAA==.Stwampadin:BAAANQAECgQICwAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQICwADAAAAAA==.',
Su='Surloyn:BAAANQADCggICAAAAA==.',
Sw='Swampert:BAABNQAECoEpAAIXAAkKNR1aJQD9AgAXAAkKNR1aJQD9AgAAAA==.Swamperting:BAAANQAECgMIBAABNQAECgkJKQAXADUdAA==.Swayaos:BAAANQAECgYIEwAAAA==.Swaye:BAABNQAECoEcAAIYAAgKihO4HQAGAgAYAAgKihO4HQAGAgAAAA==.Swifte:BAAANQABCgIIAgAAAA==.Swimchick:BAAANQAECgQIBQAAAA==.Swizzle:BAABNQAECoEZAAMZAAcKdBN6EQCKAQAZAAcKdBN6EQCKAQAaAAUKyg77MQAXAQAAAA==.',
Sy='Syllena:BAABNQAECoEgAAITAAcKuCVwBwDwAgATAAcKuCVwBwDwAgABNQAECgcIIAATALglAA==.Syraelia:BAAANQABCgIIAgABNQAECgcIIAATALglAA==.Sythia:BAAANQADCgEIAQABNQAECgkJIAAMAIAUAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggIFAAAAA==.',
Ta='Tagmoo:BAABNQAECoEYAAIXAAcKdiARRgB8AgAXAAcKdiARRgB8AgAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Talion:BAAANQADCgEIAQABNQAECgYIDgADAAAAAA==.Taloon:BAAANQAECgUICAAAAA==.Taltost:BAAANQAECgQICQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAAANQAECgUIBQAAAA==.',
Te='Teksuo:BAABNQAECoEfAAIaAAcKARNVJACiAQAaAAcKARNVJACiAQAAAA==.Telamontgrim:BAAANQAECgQIAwAAAA==.Tenithon:BAABNQAECoFCAAIHAAkKiySWAQDNAwAHAAkKiySWAQDNAwAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEJBAAAAA==.Tholaren:BAAANQAECgUICQAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQADCggIEwAAAA==.',
Ti='Ti:BAAANQAECgIIAgAAAA==.Tinkerspell:BAAANQAECgMIAwAAAA==.Tinny:BAAANQABCgIIAgAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Touchit:BAAANQADCggIDwAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAAANQAECgIIAwAAAA==.Trikshawt:BAAANQAECgIIAgABNQAECgQIBQADAAAAAA==.Trillion:BAAANQAECgIIBQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBAAAAA==.',
Ty='Tyfa:BAAANQADCgYJBgAAAA==.',
Ud='Udari:BAAANQAECgQIBwAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.',
Us='Usednabused:BAAANQAECgIIAgAAAA==.',
Uz='Uzume:BAAANQADCgIIAgAAAA==.',
Va='Varithal:BAABNQAECoEgAAIIAAgKNRkwEgBbAgAIAAgKNRkwEgBbAgABNQABCgEIAQADAAAAAA==.Vastectomy:BAAANQAECgUIBwAAAA==.',
Ve='Venawyn:BAAANQAECgQICQAAAA==.',
Vi='Vicious:BAABNQAECoEeAAIFAAkKJR5GFwDoAgAFAAkKJR5GFwDoAgAAAA==.Vixin:BAAANQAECgMIBQAAAA==.',
Vo='Voidsaack:BAAANQAECgUIDwAAAA==.Vortan:BAABNQAECoEZAAIbAAcKQB0JBABrAgAbAAcKQB0JBABrAgAAAA==.',
Vr='Vreya:BAAANQADCgEJAQABNQADCgcIDwADAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAgAAAA==.Vynthus:BAAANQAECgUICQAAAA==.',
Wa='Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQIBwAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAAANQAECgUIDgAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAAANQAECgUICQAAAA==.Whispp:BAAANQAECgQJBwAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQIBQADAAAAAA==.',
Wi='Willough:BAAANQADCgYIDAAAAA==.',
Wy='Wymstar:BAAANQADCggIEgAAAA==.Wyvoker:BAAANQADCgMIAgABNQADCggIEgADAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQADCggIEgADAAAAAA==.',
Xu='Xuny:BAAANQADCggIIgAAAA==.',
Yo='Yordi:BAAANQAECgQIBQAAAA==.Yoyopapa:BAAANQADCgIIAgAAAA==.',
Yu='Yuzuriha:BAABNQAECoEdAAIJAAcKoCGQPgBnAgAJAAcKoCGQPgBnAgAAAA==.',
Za='Zamaze:BAAANQADCggIFQAAAA==.',
Ze='Zeekielle:BAEBNQAECoEfAAIPAAgK4w3oLQDbAQAPAAgK4w3oLQDbAQAAAA==.',
Zi='Zipy:BAAANQAECgUICQAAAA==.',
Zy='Zyllo:BAAANQADCgYICAAAAA==.',
['Zæ']='Zæ:BAAANQADCgQIBAAAAA==.',
['Ål']='Ålïce:BAAANQAECgYIEgAAAA==.',
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
