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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Evoker-Preservation','DeathKnight-Blood','Druid-Restoration','Shaman-Elemental','DeathKnight-Unholy','Mage-Arcane',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAAANQAECgQIBAAAAA==.',
Ac='Acceb:BAAANQADCgQIBAAAAA==.',
Ad='Adventureux:BAAANQAECgYICQAAAA==.',
Ae='Aedx:BAAANQAECgcIBgAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAAANQAECgYICQABNQABCgYIBgABAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alucard:BAAANQAECgIIAgAAAA==.Alunadoom:BAAANQADCggIFQAAAA==.Alvera:BAAANQAECgYIDAAAAA==.',
Am='Ambellìna:BAAANQADCgIIAgAAAA==.',
An='Ancestor:BAAANQAECgQIBQAAAA==.Angechi:BAEANQADCgIIAgABNQAECgYICwABAAAAAA==.Angrydk:BAAANQADCgYIDwAAAA==.Antisocial:BAAANQAECgcICQABNQAECgkJGQACAL0gAA==.',
Ar='Arm:BAAANQAECgcICwAAAA==.Armee:BAAANQAECgQIBwAAAA==.',
As='Astrael:BAAANQAECgUIBQAAAA==.Aszea:BAAANQADCgYIDwAAAA==.',
Ax='Axra:BAAANQAECgIIAgAAAA==.',
Az='Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAAANQAECgIIAgAAAA==.',
Ba='Balsin:BAAANQAECgQIBAAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Barlaf:BAAANQAECgUICgABNQADCgQIBAABAAAAAA==.Batou:BAAANQADCgUIBQAAAA==.',
Be='Beeski:BAAANQADCgQIBgAAAA==.Beeto:BAAANQAECgcIDwAAAA==.Belyndris:BAAANQABCgIIAgAAAA==.Benlian:BAEANQAECgYICwAAAA==.',
Bl='Blâze:BAAANQAECgcIEAAAAA==.',
Bo='Bonknsmash:BAAANQAECgcIEQAAAA==.Boof:BAAANQAECgQIBgAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAAANQAECgQIBgAAAA==.',
Bu='Bushgarden:BAAANQADCgYIBgABNQADCgYICgABAAAAAA==.Buzsmash:BAAANQAECgYIBQAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgQIBAABAAAAAA==.',
['Bó']='Bóba:BAACNQAFFIEGAAIDAAUJLB0cAQDdAQADAAUJLB0cAQDdAQA1AAQKgRoAAgMACQmSI1wBAH0DAAMACQmSI1wBAH0DAAAA.',
['Bö']='Böba:BAAANQAFFAEIAQABNQAFFAUIBgADACwdAA==.',
Ca='Caelin:BAAANQAECgUICQAAAA==.Cailand:BAAANQADCggIDQAAAA==.Caishana:BAAANQAECgUICAAAAA==.Cambium:BAAANQADCggIFgAAAA==.Camerbunne:BAAANQADCgYIDwAAAA==.',
Ch='Chaddingus:BAAANQADCgYIBwAAAA==.Chopadk:BAABNQAECoEXAAIEAAkJ9AzEGgD2AQAEAAkJ9AzEGgD2AQAAAA==.Chumlëy:BAAANQADCgUIBQAAAA==.',
Cl='Clash:BAAANQADCgUICAAAAA==.Clique:BAAANQADCggIDgAAAA==.',
Co='Coldbreeze:BAAANQAECgQIBQAAAA==.Colomel:BAAANQABCgQIBgABNQADCgcICQABAAAAAA==.Comegetsum:BAAANQADCgYICwAAAA==.Conqbine:BAAANQADCgYIBgAAAA==.Countchocula:BAAANQAECgQIBAAAAA==.',
Cr='Crimmi:BAAANQADCggICAAAAA==.Critzilla:BAAANQADCgYIBwAAAA==.',
Cu='Cuddy:BAAANQADCgYIBgAAAA==.',
Cy='Cyndle:BAAANQAECgYICQAAAA==.',
Da='Daddythicc:BAAANQAECgQIBwAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQADCgQIBAAAAA==.Deadillusion:BAAANQADCgUIBQABNQADCggIDwABAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAAANQAECgEIAQAAAA==.',
Di='Dirtmonkgirt:BAAANQAECgEIAQAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAAANQAECgUIBQAAAA==.',
Dr='Dracara:BAAANQAECgEIAQAAAA==.Dracia:BAAANQAECgIIBAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Dreadz:BAAANQAECgQIBgAAAA==.Drewish:BAAANQAECgQICQAAAA==.Drg:BAAANQADCgMIAwAAAA==.Drizzle:BAAANQAECgYIDAAAAA==.Drktotem:BAAANQAECgMIBgAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dumbdog:BAABNQAECoEZAAIFAAkJ6x+/AgAlAwAFAAkJ6x+/AgAlAwAAAA==.Dusan:BAAANQAECgMIAwAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ec='Echeyaket:BAAANQAECgMIAwAAAA==.',
Ed='Edonsian:BAAANQAECgUICAAAAA==.',
Eg='Egmont:BAAANQADCgIIAgAAAA==.',
El='Elektabuzz:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Elelusion:BAAANQADCggIDwAAAA==.Elliekins:BAAANQADCgUIBQAAAA==.Elçhapo:BAAANQAECgIIAgAAAA==.',
En='Enoka:BAAANQAECgYICgAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAAANQAECgMIAwAAAA==.',
Eu='Euclid:BAAANQADCggICAAAAA==.',
Ev='Evilguard:BAAANQAECgQICAAAAA==.',
Ex='Excessive:BAAANQADCgYIBQAAAA==.Exroastbeef:BAAANQADCgYIBgAAAA==.',
Fa='Falador:BAAANQADCggIEwAAAA==.Fariebubbles:BAAANQADCgYIDwAAAA==.',
Fe='Felene:BAAANQAECgYICQAAAA==.',
Fr='Frailey:BAAANQAECgMIAwAAAA==.Frankiejr:BAAANQADCgYIDwABNQAECgEIAQABAAAAAA==.Fraubles:BAAANQAECgEIAQAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQADCggICAAAAA==.Frostnite:BAAANQAECgQIBAAAAA==.Frostpoptart:BAAANQAECgMIBAAAAA==.Frozenblade:BAAANQAECgYIBwAAAA==.',
Fu='Furiousgeorg:BAAANQAECgQIBwAAAA==.',
Ga='Gazze:BAAANQAECgMIAwAAAA==.',
Ge='Gennissa:BAAANQAECgEIAQAAAA==.Gethsemane:BAAANQAECgQICAAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcICQAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIEgAAAA==.Goonielama:BAAANQAECgcIDQAAAA==.',
Gr='Griitz:BAAANQAECgEIAQAAAA==.Grimmsheeper:BAAANQAECggIEwAAAA==.',
Gu='Guess:BAAANQADCgYICwAAAA==.Gurtdk:BAAANQAFFAIIAgAAAA==.',
Gy='Gyat:BAAANQADCgMIAwAAAA==.',
Ha='Hairynujabes:BAAANQAECggICAAAAA==.Hanyuu:BAAANQAECgUICAAAAA==.',
He='Heiter:BAAANQAECgYICgAAAA==.Hellbound:BAAANQAECgQIBgAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.',
Ic='Icefrosting:BAAANQAECgIIAwAAAA==.',
Id='Idistroya:BAAANQAECgMIAwABNQAECgUIDAABAAAAAA==.',
Ig='Iggnogg:BAAANQADCgUICgAAAA==.',
Ik='Ikura:BAAANQAECggIEwAAAA==.',
Il='Ilithiya:BAAANQAECgQIBAAAAA==.Ilk:BAAANQADCgUIBQAAAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAAANQAECgQIBAAAAA==.Ishton:BAAANQAECgUIBgAAAA==.Istompgnomes:BAAANQAECgYICAAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jasøn:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.',
Je='Jecthyr:BAAANQAECgMIBAAAAA==.Jefeson:BAAANQAECgMIAwAAAA==.',
Ji='Jinnasaiquoi:BAAANQADCgcIDAAAAA==.',
Js='Jsdruid:BAAANQADCgUIBQAAAA==.',
Ka='Kaelosu:BAAANQAECgcIEQAAAA==.Kakum:BAAANQADCgYIDgAAAA==.Kaldrogo:BAAANQADCgYIBgAAAA==.Kalnuggets:BAAANQADCggIEgAAAA==.Kalrathen:BAAANQAECgcIDgAAAA==.Kanda:BAAANQAECgYICwAAAA==.Karsh:BAAANQAECgMIAwAAAA==.Kazadax:BAAANQAECgMIAwAAAA==.',
Ke='Keuaakepo:BAAANQAECgUIDAAAAA==.',
Ki='Kienne:BAAANQAECgEIAgAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAAANQADCggIDAAAAA==.Korogar:BAAANQADCgUIBQAAAA==.',
Kp='Kpes:BAAANQADCgUIBQAAAA==.',
Kr='Krizzl:BAAANQADCgUIBQAAAA==.Kronknar:BAAANQABCgQIBAABNQAECgUICAABAAAAAA==.',
Ky='Kymira:BAAANQAECgYICwAAAA==.',
La='Lace:BAAANQAECgYICQAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAAANQAECgYIDAAAAA==.',
Le='Lementz:BAABNQAECoEZAAIGAAkJkR0dCAAyAwAGAAkJkR0dCAAyAwAAAA==.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgYIDgAAAA==.Libellule:BAAANQABCgMIAwAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAAANQAECgMIAwAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAAANQADCgIIAgAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECgQIBwABAAAAAA==.',
Lu='Lumpia:BAAANQAECgUIBQAAAA==.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
Ma='Maey:BAAANQAECgYICwAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAAANQAECgUICAAAAA==.Malpractice:BAAANQABCgQIBAABNQAECgQIBAABAAAAAA==.Maybesinged:BAAANQAECgQIBwAAAA==.',
Me='Meanboy:BAAANQADCgcIBwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAAANQAECgYICwAAAA==.',
Mi='Miltank:BAAANQAECgYIDAAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAAANQAECgYICAAAAA==.Mionn:BAAANQAECgQIBAAAAA==.',
Ml='Mlleena:BAAANQAECgMIAwAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQADCggIDgAAAA==.Moghoul:BAAANQAECgEIAQAAAA==.Moofi:BAAANQADCgYIBgABNQADCgYIDQABAAAAAA==.Mooncake:BAAANQAECgQIBQAAAA==.Motoko:BAAANQAECgQICAAAAA==.',
['Mø']='Møøfi:BAAANQADCgYIDQAAAA==.',
Na='Naianasha:BAAANQADCggIEwAAAA==.Nameless:BAAANQAECgUICAAAAA==.Narc:BAAANQADCgYIEAAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAAANQAECgMIAwAAAA==.',
No='Nokzash:BAAANQAECgEIAgAAAA==.Noova:BAAANQAECgQICwAAAA==.',
Ny='Nyang:BAAANQAECgYIBgAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Oo='Oongaboonga:BAAANQAECgQICAAAAA==.',
Or='Orcaneblast:BAAANQAECgYIDgAAAA==.Orcsoup:BAAANQAECgMIBAABNQAECgUIBQABAAAAAA==.',
Pa='Paranoià:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.',
Pi='Pivnert:BAAANQAECgIIAgAAAA==.',
Pl='Platinum:BAAANQADCggIBAAAAA==.',
Po='Popdkook:BAAANQADCgUIDAAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgQIBQAAAA==.',
['Pü']='Pünish:BAABNQAECoEWAAIHAAgJPR4PDADgAgAHAAgJPR4PDADgAgAAAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAAANQAECggIDgABNQAFFAUICgAIAFkNAA==.Ragingiscool:BAAANQADCggIDQAAAA==.Rail:BAAANQABCgIIAgAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAAANQAECgQIBgAAAA==.Ranuggul:BAAANQADCgYICwAAAA==.Raza:BAAANQADCgIIAgABNQAECggIFgAHAD0eAA==.',
Re='Remeras:BAAANQADCgcIBwAAAA==.',
Ri='Riken:BAAANQAECgMIAwAAAA==.',
Ro='Roadi:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Roxer:BAAANQADCggICAAAAA==.',
Ru='Rummyy:BAAANQADCgMIAwAAAA==.',
Ry='Rycken:BAAANQAECgEIAQAAAA==.',
Sa='Saeylva:BAAANQADCgcIDQAAAA==.Saosis:BAAANQADCgYICgAAAA==.Savage:BAAANQADCgIIAgAAAA==.',
Sc='Scribble:BAAANQAECgIIAgAAAA==.Sculper:BAAANQAECgIIAgAAAA==.',
Se='Seriphina:BAAANQADCggICAAAAA==.',
Sh='Shabbarankzz:BAAANQAECgQIBgAAAA==.Shadetotem:BAAANQAECgEIAQAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCgYIBgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQADCgcIDQAAAA==.Shradehn:BAAANQAECgMIBQAAAA==.Shutitdown:BAAANQADCggIFQAAAA==.',
Si='Sisterswede:BAAANQAECgcIBwAAAA==.Sizzle:BAAANQAECgQIBAAAAA==.',
Sm='Smokindots:BAAANQADCgYICwABNQAECgYICwABAAAAAA==.Smokinmyrrh:BAAANQADCggIDgABNQAECgYICwABAAAAAA==.Smokintotem:BAAANQAECgYICwAAAA==.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQADCgYIBgABNQAFFAIIAgABAAAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
St='Steadyrock:BAAANQAECgMIAwAAAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormz:BAAANQAECgQIBAAAAA==.',
Su='Sunblade:BAAANQADCggICQABNQAECgUICAABAAAAAA==.Sundowning:BAAANQAECgUIBQAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQADCggIDgAAAA==.',
Sw='Swiftdragon:BAAANQAECgQIBAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Tackyh:BAAANQAECgQIBAAAAA==.Takamatsu:BAAANQAECgQIBAAAAA==.Taku:BAAANQADCggIDgAAAA==.Tar:BAAANQAECgMIAwAAAA==.Taxii:BAAANQAECgIIBAAAAA==.',
Te='Tealnujabes:BAAANQADCggICAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQADCggICAAAAA==.Thedeus:BAAANQADCgUICwABNQAECgQIBwABAAAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAAANQAECgcIDAAAAA==.Threebeans:BAAANQAECgUIBQAAAA==.Thromir:BAAANQAECggIDAAAAA==.Thyrn:BAAANQAECgUIBwAAAA==.',
Ti='Tirare:BAAANQAECgEIAQAAAA==.',
Tr='Tri:BAAANQAECgEIAQAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAAANQAECgEIAQAAAA==.Turgrok:BAAANQADCgcIBwAAAA==.',
Tw='Twothang:BAAANQAECgMIAwAAAA==.',
Ty='Tyllan:BAAANQAECgQIBAAAAA==.',
Va='Vainhellsing:BAAANQADCggIEwAAAA==.Vanzier:BAAANQAECgQIBgAAAA==.Vaxis:BAAANQAECgMIAwAAAA==.',
Vi='Vid:BAAANQAECggIEgAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAECgYICQABAAAAAA==.Wernov:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.',
Wi='Wichan:BAAANQAECgQIBgAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQADCgYIBgAAAA==.',
Xr='Xray:BAAANQAECgUIBwAAAA==.',
Xt='Xtreme:BAAANQADCggIDQAAAA==.',
Yu='Yunsky:BAAANQADCgYIDgAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAAANQAECgUIBwAAAA==.Zanosuke:BAAANQAECgQIBgAAAA==.Zaria:BAAANQAECgUIBgAAAA==.Zaryor:BAAANQAECgQIBAAAAA==.',
Ze='Zentul:BAAANQAECgEIAQAAAA==.Zerika:BAAANQAECgUICAAAAA==.',
Zi='Zigzwag:BAAANQADCgYICgAAAA==.Zionna:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.',
Zo='Zomgqq:BAAANQAECgYIBgAAAA==.',
Zy='Zydis:BAAANQADCggIEgAAAA==.Zyggy:BAAANQADCggIEgAAAA==.',
['Än']='Ännihilation:BAAANQADCgYIBgAAAA==.',
['És']='Éstéla:BAAANQAECgYIBwAAAA==.',
['Ío']='Ío:BAAANQADCgYICQAAAA==.',
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
