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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Evoker-Preservation','Paladin-Retribution','Mage-Arcane','Warrior-Arms','DeathKnight-Blood','Druid-Restoration','Warlock-Demonology','DeathKnight-Unholy','Priest-Discipline','Priest-Holy','Priest-Shadow','Shaman-Elemental','Monk-Mistweaver',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAAANQAECgYICgAAAA==.',
Ac='Acceb:BAAANQADCgQIBAAAAA==.',
Ad='Adventureux:BAAANQAECgcIDwAAAA==.',
Ae='Aedx:BAAANQAECggIDAAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAAANQAECgcIDwABNQABCgYIBgABAAAAAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alucard:BAAANQAECgMIAwAAAA==.Alunadoom:BAAANQAECgIIAgAAAA==.Alvera:BAAANQAECgcIEwAAAA==.',
Am='Ambellìna:BAAANQADCgIIAgAAAA==.',
An='Ancestor:BAAANQAECgUICgAAAA==.Angechi:BAEANQADCgIIAgABNQAECgcIEgABAAAAAA==.Angrydk:BAAANQADCgcIFgAAAA==.Antisocial:BAAANQAFFAEIAQABNQAECgkJHwACAE4hAA==.',
Ar='Arm:BAAANQAECgcIEgAAAA==.Armee:BAAANQAECgYIDQAAAA==.',
As='Astrael:BAAANQAECgYICwAAAA==.Aszea:BAAANQADCgcIFgAAAA==.',
Ax='Axra:BAAANQAECgUIBwAAAA==.',
Az='Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAAANQAECgQIBgAAAA==.',
Ba='Balsin:BAAANQAECgUICQAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgMIAwABNQAFFAYIBwADAMcQAA==.Barlaf:BAAANQAECgYIEAABNQADCgUIBgABAAAAAA==.Batou:BAAANQAECgMIAwAAAA==.',
Be='Beeski:BAAANQADCgQICgAAAA==.Beeto:BAABNQAECoEaAAIEAAgJABR1OAAdAgAEAAgJABR1OAAdAgAAAA==.Belyndris:BAAANQADCggICAAAAA==.Benlian:BAEANQAECgcIEgAAAA==.',
Bl='Blâze:BAABNQAECoEYAAIFAAgJ6xrwRACAAgAFAAgJ6xrwRACAAgAAAA==.',
Bo='Bonknsmash:BAABNQAECoEZAAIGAAgJNxCTRgAZAgAGAAgJNxCTRgAZAgAAAA==.Boof:BAAANQAECgYIDAAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAAANQAECgYIDAAAAA==.',
Bu='Bubbleoshift:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgABAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgUIBQABAAAAAA==.',
['Bó']='Bóba:BAACNQAFFIELAAIDAAUJyCCcAQD+AQADAAUJyCCcAQD+AQA1AAQKgR8AAgMACQmSI6ACAGEDAAMACQmSI6ACAGEDAAAA.',
['Bö']='Böba:BAAANQAFFAEIAgABNQAFFAUICwADAMggAA==.',
Ca='Cadiva:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.Cadroyd:BAAANQAECgEIAQAAAA==.Caelin:BAAANQAECgcIEAAAAA==.Cailand:BAAANQAECgMIAwAAAA==.Caishana:BAAANQAECgYIDgAAAA==.Cambium:BAAANQAECgIIAgAAAA==.Camerbunne:BAAANQADCgYIDwAAAA==.Catdude:BAAANQAECgQIBAAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.',
Ch='Chaddingus:BAAANQADCgYIBwAAAA==.Chopadk:BAABNQAECoEgAAIHAAkJ6Q4nJQDyAQAHAAkJ6Q4nJQDyAQAAAA==.Chumlëy:BAAANQADCgUIBQAAAA==.',
Cl='Clash:BAAANQADCgUICAAAAA==.Clique:BAAANQAECgMIAwAAAA==.',
Co='Coldbreeze:BAAANQAECgQICQAAAA==.Collateral:BAAANQADCgcIBwAAAA==.Colomel:BAAANQAECgMIAwAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Conqbine:BAAANQADCgYIBgAAAA==.Countchocula:BAAANQAECgQICAAAAA==.',
Cr='Crimmi:BAAANQAECgQIBAAAAA==.Critzilla:BAAANQADCgYIDAAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Cyndle:BAAANQAECgcIEAAAAA==.',
Da='Daddythicc:BAAANQAECgYIDQAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQADCgcICwAAAA==.Deadillusion:BAAANQADCgUIBQABNQADCggIDwABAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAAANQAECgQIBQAAAA==.',
Di='Diante:BAAANQABCgIIAgABNQADCgcIEgABAAAAAA==.Dirtmonkgirt:BAAANQAECgQIBQAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAAANQAECgYICwAAAA==.',
Dr='Dracara:BAAANQAECgQIBQAAAA==.Dracia:BAAANQAECgYICgAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Dreadz:BAAANQAECgUICwAAAA==.Drewish:BAAANQAECgYIDwAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Drizzle:BAAANQAECgYIEgAAAA==.Drktotem:BAAANQAECgYIDAAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFIEKAAIIAAUJhCJ5AAAIAgAIAAUJhCJ5AAAIAgA1AAQKgSEAAggACQk/IpACAGEDAAgACQk/IpACAGEDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAAANQAECgQIBwAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgEIAQAAAA==.',
Ec='Echeyaket:BAAANQAECgQIBwAAAA==.',
Ed='Edonsian:BAAANQAECgYIDwAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgQICAABAAAAAA==.Elelusion:BAAANQADCggIDwAAAA==.Elliekins:BAAANQADCgUICgAAAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
En='Enoka:BAAANQAECgcIDwAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAAANQAECgMIBAAAAA==.',
Eu='Euclid:BAAANQAECgMIAwAAAA==.',
Ev='Evilguard:BAAANQAECgYIEAAAAA==.',
Ex='Excessive:BAAANQADCggICwAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAAANQADCggIFgAAAA==.Fariebubbles:BAAANQADCgYIFQAAAA==.',
Fe='Felene:BAAANQAECgcIDAAAAA==.',
Fr='Frailey:BAAANQAECgUICAAAAA==.Frankiejr:BAAANQADCgYIFQABNQAECgIIAwABAAAAAA==.Fraubles:BAAANQAECgEIAQAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQADCggICQAAAA==.Frostnite:BAAANQAECgQIBgAAAA==.Frostpoptart:BAAANQAECgMIBQAAAA==.Frozenblade:BAAANQAECgYIDQAAAA==.',
Fu='Furball:BAAANQADCgYIBgABNQAECggIFQAJAN8fAA==.Furiousgeorg:BAAANQAECgUICwAAAA==.',
Ga='Gagabooney:BAAANQAECgQIBAABNQAECggIGAAHAN4fAA==.Gazze:BAAANQAECgQIBwAAAA==.',
Ge='Gennissa:BAAANQAECgMIBAAAAA==.Gethsemane:BAAANQAECgUIDQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcICQAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIEgAAAA==.Goonielama:BAABNQAECoEYAAIHAAgJ3h/PDADvAgAHAAgJ3h/PDADvAgAAAA==.Goonietai:BAAANQADCgUIBQABNQAECggIGAAFAHIcAA==.',
Gr='Griitz:BAAANQAECgEIAQAAAA==.Grimmsheeper:BAABNQAECoEfAAIFAAkJ6xxoJwD0AgAFAAkJ6xxoJwD0AgAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFIEIAAMKAAUJCRYPAgBcAQAKAAQJdhMPAgBcAQAHAAEJVSBKDwBfAAA1AAQKgRoAAgoACQlLJesBAMcDAAoACQlLJesBAMcDAAAA.',
Gy='Gyat:BAAANQADCgMIAwAAAA==.',
Ha='Hairynujabes:BAAANQAECggIDgAAAA==.Hanyuu:BAAANQAECgYIDgAAAA==.',
He='Heiter:BAAANQAECgYIEAAAAA==.Hellbound:BAAANQAECgQICgAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Honk:BAAANQAECgUIBQAAAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgQIBQABAAAAAA==.',
Ic='Icefrosting:BAAANQAECgQIBwAAAA==.',
Id='Idistroya:BAAANQAECgMIAwABNQAECgUIDgABAAAAAA==.',
Ig='Iggnogg:BAAANQADCgYIEAAAAA==.',
Ik='Ikura:BAABNQAECoEbAAQLAAkJHBLYBgCXAQAMAAgJzg2JNgDAAQALAAcJMg3YBgCXAQANAAEJlQhVTAAqAAAAAA==.',
Il='Ilithiya:BAAANQAECgYICQAAAA==.Ilk:BAAANQADCgUIBQAAAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAAANQAECgUICQAAAA==.Ishton:BAAANQAECgYICQAAAA==.Istompgnomes:BAAANQAECgYIDQAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jasøn:BAAANQADCgcIDgABNQAECgMIBAABAAAAAA==.',
Je='Jecthyr:BAAANQAECgQICAAAAA==.Jefeson:BAAANQAECgMIAwAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAAANQADCggIDgAAAA==.',
Js='Jsdruid:BAAANQADCgcIDAAAAA==.',
Ka='Kaelosu:BAABNQAECoEcAAIJAAkJrBkDEQDXAgAJAAkJrBkDEQDXAgAAAA==.Kakum:BAAANQADCgYIFQAAAA==.Kaldrogo:BAAANQADCgYIBgAAAA==.Kalnuggets:BAAANQADCggIFwAAAA==.Kalrathen:BAABNQAECoEXAAMMAAkJlBBtIgA7AgAMAAkJlBBtIgA7AgANAAEJewEgUwAcAAAAAA==.Kanda:BAAANQAECgcIEgAAAA==.Karsh:BAAANQAECgQIBwAAAA==.Kazadax:BAAANQAECgQIBwAAAA==.',
Ke='Keuaakepo:BAAANQAECgUIDgAAAA==.',
Ki='Kienne:BAAANQAECgQIBgAAAA==.Kiljaedra:BAAANQADCgQIBAAAAA==.Kitenna:BAAANQAECgMIAwAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAAANQAECgQIBAAAAA==.Korogar:BAAANQADCggICwAAAA==.',
Kp='Kpes:BAAANQADCgUIBQAAAA==.',
Kr='Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAECgkJHQAKAMkjAA==.Kronknar:BAAANQABCgQIBAABNQAECgYIDgABAAAAAA==.',
Ky='Kymira:BAAANQAECgcIEgAAAA==.',
La='Lace:BAAANQAECgcIEgAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAAANQAECgYIEQAAAA==.Lazarou:BAAANQADCgUIBQAAAA==.',
Le='Legsday:BAAANQADCgIIAgAAAA==.Lementz:BAACNQAFFIEIAAIOAAQJVQ8TBABPAQAOAAQJVQ8TBABPAQA1AAQKgR0AAg4ACQlYH/oLADcDAA4ACQlYH/oLADcDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIEgAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAAANQAECgQIBwAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAAANQAECggICAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECgcIDgABAAAAAA==.',
Lu='Lumpia:BAAANQAECgYICgAAAA==.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
Ma='Maey:BAAANQAECgcIEgAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAAANQAECgYIDgAAAA==.Malpractice:BAAANQABCgQIBAABNQAECgUICQABAAAAAA==.Maybesinged:BAAANQAECgYIDQAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAAANQAECgcIEgAAAA==.',
Mi='Midgetninja:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.Miltank:BAAANQAECgYIEgAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAAANQAECgcIDgAAAA==.Mionn:BAAANQAECgQICAAAAA==.',
Ml='Mlleena:BAAANQAECgQIBwAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQADCggIFAAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Moofi:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Mooncake:BAAANQAECgYICwAAAA==.Moosiah:BAAANQADCgcIBwAAAA==.Motoko:BAAANQAECgUIDQAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møøfi:BAAANQAECgEIAQAAAA==.',
Na='Naianasha:BAAANQAECgEIAQAAAA==.Nameless:BAAANQAECgYIDgAAAA==.Narc:BAAANQADCgYIFgAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAAANQAECgMIBgAAAA==.',
No='Nokzash:BAAANQAECgEIAwAAAA==.Noova:BAAANQAECgcIEgAAAA==.',
Ny='Nyang:BAAANQAECgYICwAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
Ok='Okiedokie:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.',
Oo='Oongaboonga:BAAANQAECgYIDgAAAA==.',
Or='Orcaneblast:BAABNQAECoEYAAIFAAgJchy9OQCqAgAFAAgJchy9OQCqAgAAAA==.Orcsoup:BAAANQAECgYICgAAAA==.',
Pa='Paranoià:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.',
Pi='Pivnert:BAAANQAECgQIBgAAAA==.',
Pl='Platinum:BAAANQADCggIBAAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgQIBQAAAA==.',
['Pü']='Pünish:BAABNQAECoEeAAIKAAgJ1SG2DAAFAwAKAAgJ1SG2DAAFAwAAAA==.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAAANQAFFAMIAwABNQAFFAYIDgAFAHcMAA==.Ragingiscool:BAAANQADCggIDQAAAA==.Rail:BAAANQADCggIBwAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAAANQAECgQICgAAAA==.Ranuggul:BAAANQAECgEIAQAAAA==.Raza:BAAANQADCgcIDwABNQAECggIHgAKANUhAA==.',
Re='Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAAANQADCgcIBwAAAA==.',
Ri='Riken:BAAANQAECgUICAAAAA==.',
Ro='Roadi:BAAANQAECgMIAwABNQAECgYIDgABAAAAAA==.Roxer:BAAANQAECgUIBQAAAA==.',
Ru='Rummyy:BAAANQAECggIAQAAAA==.',
Ry='Rycken:BAAANQAECgQIBQAAAA==.',
Sa='Saeylva:BAAANQADCgcIDgAAAA==.Saosis:BAAANQADCgYICgAAAA==.Savage:BAAANQADCgIIAgAAAA==.',
Sc='Scribble:BAAANQAECgIIAgAAAA==.Sculper:BAAANQAECgQIBgAAAA==.',
Se='Seriphina:BAAANQADCggICAAAAA==.',
Sh='Shabbarankzz:BAAANQAECgUICwAAAA==.Shadetotem:BAAANQAECgIIAwAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIDgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQADCgcIEwAAAA==.Shradehn:BAAANQAECgYICwAAAA==.Shutitdown:BAAANQADCggIFQAAAA==.',
Si='Sisterswede:BAAANQAECgcIDwAAAA==.Sizzle:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.',
Sm='Smokeahontas:BAAANQAECgQIBAAAAA==.Smokindots:BAAANQADCgYICwABNQAFFAEIAQABAAAAAA==.Smokingreen:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Smokinmyrrh:BAAANQADCggIDgABNQAFFAEIAQABAAAAAA==.Smokintotem:BAAANQAFFAEIAQAAAA==.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQAECgIIAgABNQAECgkJGwAGAAkYAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAAANQAECgYICQAAAA==.Steveirwin:BAAANQADCggICAAAAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAAANQAECgQIBAAAAA==.Stormz:BAAANQAECgYICgAAAA==.',
Su='Sunblade:BAAANQADCggICQABNQAECgYIDgABAAAAAA==.Sundowning:BAAANQAECgUIBQAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swiftdragon:BAAANQAECgUICQAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgYICgABAAAAAA==.Tackyh:BAAANQAECgQICgAAAA==.Takamatsu:BAAANQAECgUICQAAAA==.Taku:BAAANQADCggIFwAAAA==.Tar:BAAANQAECgMIBAAAAA==.Taxii:BAAANQAECgUICQAAAA==.',
Te='Tealnujabes:BAAANQAECgYIBgAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQADCggICAAAAA==.Thedeus:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAAANQAECggIEQAAAA==.Threebeans:BAAANQAECgUIBQABNQAECgYICgABAAAAAA==.Thromir:BAAANQAECggIEgAAAA==.Thyrn:BAAANQAECgUIDAAAAA==.',
Ti='Tirare:BAAANQAECgQIBQAAAA==.',
Tr='Tri:BAAANQAECgIIAwAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAAANQAECgMIBQAAAA==.Turgrok:BAAANQAECgQIBAAAAA==.',
Tw='Twothang:BAAANQAECgQIBwAAAA==.',
Ty='Tyllan:BAAANQAECgUIBwAAAA==.',
Va='Vainhellsing:BAAANQADCggIEwAAAA==.Vanzier:BAAANQAECgQICQAAAA==.Vaxis:BAAANQAECgYICQAAAA==.',
Vi='Vid:BAABNQAECoEbAAIPAAkJzx/LAgBCAwAPAAkJzx/LAgBCAwAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAECgcIEgABAAAAAA==.Wernov:BAAANQAECgYICwABNQAECgYIEAABAAAAAA==.',
Wh='Whitetail:BAAANQADCgEIAQAAAA==.',
Wi='Wichan:BAAANQAECgQICQAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.Wiziviji:BAAANQAECgMIAwAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECgMIAwAAAA==.',
Xr='Xray:BAAANQAECgUIDAAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Ya='Yaphetkotto:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.',
Yu='Yunsky:BAAANQADCgYIFAAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAAANQAECgYIDQAAAA==.Zanosuke:BAAANQAECgUICwAAAA==.Zaria:BAAANQAECgUICwAAAA==.Zaryor:BAAANQAECgUICQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerika:BAAANQAECgYIDgAAAA==.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIAgAAAA==.Zionna:BAAANQAECgUICQABNQAECgUICQABAAAAAA==.',
Zo='Zomgqq:BAAANQAECgcIDAAAAA==.',
Zy='Zydis:BAAANQADCggIEgAAAA==.Zyggy:BAAANQADCggIEgAAAA==.',
['Än']='Ännihilation:BAAANQADCgYIDAAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.',
['És']='Éstéla:BAAANQAECgYIDQAAAA==.',
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
