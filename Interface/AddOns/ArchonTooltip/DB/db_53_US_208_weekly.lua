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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Augmentation','Druid-Balance','DeathKnight-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','DeathKnight-Blood','Warrior-Arms',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abor:BAAANQADCgQICgAAAA==.Abuela:BAAANQAECggIBAAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ae='Aegla:BAAANQAECgQIBAAAAA==.Aegrus:BAAANQADCgUIBwAAAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQADCggICAAAAA==.Alcmeneinen:BAAANQAECgcIEQAAAA==.Alerath:BAAANQADCgYICQAAAA==.Alliar:BAAANQAECgQIBgAAAA==.Allynstraza:BAAANQADCgcIEwAAAA==.',
Am='Amgems:BAAANQAECgQIBAAAAA==.Amordred:BAAANQAECgIIAgAAAA==.',
An='Anasterion:BAAANQAECgcIDwAAAA==.Ankles:BAAANQAECgQICAAAAA==.Ansley:BAAANQADCgUICAABNQADCggIDwABAAAAAA==.',
As='Ashli:BAAANQADCggIDwAAAA==.',
At='Atlasdark:BAAANQADCggIFQABNQADCgYIDwABAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.',
Ba='Balrock:BAAANQADCgYIBgAAAA==.Balthromaw:BAAANQADCggIFQAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardwaffle:BAAANQAECgEIAQAAAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgQIBwAAAA==.Belstab:BAAANQAECgYIEQAAAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIDQAAAA==.',
Bg='Bgbalkoth:BAAANQADCgQIBAAAAA==.',
Bi='Bifurthegrey:BAAANQADCgUIDQAAAA==.Bigblammy:BAAANQADCggICAABNQAECggIDwABAAAAAA==.Biophage:BAAANQAECgQIBAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blaxdevoured:BAAANQADCgQIBAAAAA==.Bloodavenger:BAAANQAECgYIBQAAAA==.Bloodemongar:BAAANQADCggIFQAAAA==.Bloodhoundss:BAAANQAECgIIAgAAAA==.Blössöm:BAAANQAECgIIAgAAAA==.',
Bo='Bobdk:BAABNQAECoEXAAICAAkJyR3pBwAnAwACAAkJyR3pBwAnAwAAAA==.Bomboklaat:BAAANQABCgYIBgAAAA==.Boomshield:BAAANQAECgQIAgAAAA==.Boxbeater:BAAANQAECgQIBgAAAA==.',
Br='Braegen:BAAANQADCgIIAgABNQAECgYIDAABAAAAAA==.Brewslee:BAAANQADCggICAAAAA==.Bruceleett:BAAANQAECgIIAgABNQADCgcIBwABAAAAAA==.',
Bu='Buffmeister:BAAANQADCgUICQAAAA==.Bullioss:BAAANQABCgQIBgABNQAECgcIDQABAAAAAA==.',
['Bè']='Bètrayèr:BAAANQABCgIIAgAAAA==.',
['Bö']='Böbbyboucher:BAAANQAECgEIAQAAAA==.',
Ca='Cainn:BAAANQADCgYICwABNQAECgUICAABAAAAAA==.Calfurion:BAAANQAECgYICQAAAA==.Capncrunch:BAAANQADCgUIBQAAAA==.Cazleah:BAAANQAECgUICQAAAA==.',
Ce='Cessatio:BAAANQAECgQIBgAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAAANQAECgMIAwABNQAECgUICwABAAAAAA==.Chrisbrewn:BAAANQAECgQIBgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clevelandoe:BAABNQAECoEZAAMDAAkJ4BshBwABAwADAAkJvxshBwABAwAEAAMJLQwabgDMAAAAAA==.',
Co='Coeurdeleon:BAAANQAECgUIBwAAAA==.Condemnation:BAAANQAECgQIBwAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQABAAAAAA==.',
Cr='Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbstomped:BAAANQAECgQIBAAAAA==.',
Cy='Cyllex:BAAANQAECgEIAQAAAA==.',
Da='Darbins:BAAANQAECgIIAQABNQAECgkJGAAFANUjAA==.Darkvizzy:BAAANQAECgYICgAAAA==.Daymån:BAAANQADCggICQAAAA==.',
De='Deathreaper:BAAANQADCggIDwAAAA==.Delix:BAAANQADCggIDQAAAA==.Demiplo:BAAANQAECgYIBwAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.',
Di='Discipline:BAAANQAECgIIAgAAAA==.',
Dr='Dratr:BAAANQAECgIIAgAAAA==.Draxyl:BAAANQAECgUICwAAAA==.Drham:BAAANQAECgQIBgAAAA==.Drokos:BAAANQABCgQIBwABNQAECgcIDQABAAAAAA==.Drtree:BAAANQADCgcIBwAAAA==.',
Du='Dunhambones:BAAANQAECgIIAgAAAA==.Duo:BAAANQAECgEIAQABNQADCgQICgABAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Electora:BAAANQAECgYIBgAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAAANQAECgYICwAAAA==.',
En='Enyô:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Er='Erada:BAAANQAECgQIBQAAAA==.',
Ev='Evoklando:BAAANQADCgUICgABNQAECgkJGQADAOAbAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Fe='Felad:BAAANQAECgEIAgABNQADCggICAABAAAAAA==.',
Fi='Fireblast:BAAANQADCggIEAAAAA==.',
Fl='Flamingfists:BAAANQAECgQIDAAAAA==.Flapp:BAAANQAECgEIAQABNQABCgQIBAABAAAAAA==.Flowdinstuna:BAAANQADCgYIBgAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAAANQAECgUIBwAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.',
Fu='Furrybait:BAEANQADCgIIAgABNQADCgQIBgABAAAAAA==.Furyiosa:BAAANQAECgMIAwAAAA==.',
Ga='Gaiseric:BAAANQAECgcIDQAAAA==.',
Ge='Geraniho:BAAANQAECggIEwAAAA==.',
Gn='Gnarlak:BAAANQABCgIIAgAAAA==.',
Go='Gotfleas:BAAANQAECgYICgAAAA==.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAAANQAECgUIBwAAAA==.Grimthruul:BAAANQAECgQIBgAAAA==.Grommkar:BAAANQAECgEIAQAAAA==.',
Ha='Halucination:BAAANQAECgQIBgAAAA==.Harthan:BAAANQADCggIEwAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwABAAAAAA==.Henchman:BAAANQABCgQIBgABNQAECgcIDQABAAAAAA==.Hetzák:BAAANQAECgUIBwAAAA==.',
Hi='Hintolisu:BAAANQAECgUICgAAAA==.',
Ho='Hobbess:BAAANQAECgcIDQABNQAFFAUIBgAGAKgbAA==.Holybaloney:BAAANQAECgQIBAAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Hongis:BAAANQADCgUIBQAAAA==.Hoofinit:BAAANQADCggIDQAAAA==.',
Hu='Huatarm:BAAANQAECgUIBwAAAA==.',
Ia='Iadygaga:BAAANQAECgMIAwAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICAAAAA==.',
Im='Immunè:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Ir='Ironspin:BAAANQAECgEIAQAAAA==.',
Ja='Jaark:BAAANQAECgQIBQAAAA==.Jabalru:BAAANQADCgMIAwAAAA==.Jake:BAAANQAECgQIBwAAAA==.Jasparr:BAAANQABCgQIBAAAAA==.',
Je='Jen:BAAANQAECgUICgAAAA==.',
Jo='Jocon:BAAANQADCgcIDAAAAA==.',
Ju='Jugulator:BAAANQADCgIIAgAAAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kanami:BAAANQADCgcIEwAAAA==.Kaynyx:BAAANQAECgUICAAAAA==.Kazimer:BAAANQADCgcIBwAAAA==.',
Ke='Kedrik:BAAANQAECgUICAAAAA==.Kerb:BAAANQADCggIEgAAAA==.Kery:BAAANQADCgMIAwAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAAANQAECgcIDgAAAA==.',
Ki='Killinflak:BAAANQADCgMIAwAAAA==.Kissyboots:BAAANQAECgQIBAAAAA==.Kiyo:BAAANQAECgMIAwABNQAECgcIDwABAAAAAA==.',
Ko='Konjur:BAAANQAECggIDwAAAA==.',
Kr='Krymzendeath:BAAANQADCgYICAABNQAECgUIBgABAAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgUIBAAAAA==.',
['Kä']='Kämo:BAAANQAECgEIAQABNQAECgUIBAABAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQABCgMIAwABNQAECggIDgABAAAAAA==.Lakeyy:BAAANQAECggIDgAAAA==.Lakeyys:BAAANQADCgcICQABNQAECggIDgABAAAAAA==.Lanuor:BAAANQADCgEIAQAAAA==.Lavagobrr:BAAANQAECgQIBAAAAA==.Lawrence:BAAANQAECgcIDgAAAA==.',
Le='Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQADCgIIAgAAAA==.Lilikoii:BAAANQADCgIIAgABNQAECggIDgABAAAAAA==.Lilslaver:BAAANQADCggIEQAAAA==.Lisex:BAABNQAECoEYAAIHAAkJex/FAgA1AwAHAAkJex/FAgA1AwAAAA==.Lithe:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.',
Lo='Locklear:BAAANQAECgQIBAAAAA==.Logic:BAABNQAECoEYAAIIAAkJER3tFQAVAwAIAAkJER3tFQAVAwAAAA==.',
Lu='Lunaria:BAAANQAECgEIAQABNQAECggIDgABAAAAAA==.',
Ma='Macediin:BAAANQAECgMIAwAAAA==.Madderhunter:BAAANQAECggIEQAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Magnolìa:BAAANQADCgUIBQAAAA==.Malthael:BAAANQAECgIIAgAAAA==.Mamageek:BAAANQAECgQIBAAAAA==.Mami:BAAANQAECgEIAQAAAA==.Manhorde:BAAANQADCgcICAABNQADCggIFAABAAAAAA==.Manix:BAAANQAECgEIAgAAAA==.Mareo:BAAANQADCgUIBQAAAA==.Marksterique:BAAANQAECgQIBgAAAA==.',
Me='Meeko:BAABNQAECoEaAAIJAAkJGSFQAgBLAwAJAAkJGSFQAgBLAwAAAA==.Meliadus:BAAANQADCgcIBwAAAA==.Mereoleona:BAAANQADCgMIAwAAAA==.Metalbound:BAAANQAECgIIAgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAAANQAECgMIAwAAAA==.Misslobster:BAAANQADCgcIEgAAAA==.',
Mo='Mokoko:BAABNQAECoEZAAIKAAkJNRg+BQDSAgAKAAkJNRg+BQDSAgAAAA==.Mokolock:BAAANQADCgYIDAABNQAECgkJGQAKADUYAA==.Moomoo:BAAANQAECgQIBwAAAA==.Moorlin:BAAANQADCggICAAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgkJGQAKADUYAA==.',
My='Myyst:BAAANQADCgMIAwAAAA==.',
Ne='Necro:BAAANQAECgQIBgAAAA==.Neuron:BAAANQAECggIDAAAAA==.Nexxos:BAAANQAECgEIAQAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAAANQAECgQIBAAAAA==.Nightflame:BAAANQADCggIFQAAAA==.Ninjavc:BAAANQADCggIEQAAAA==.',
No='Noelle:BAAANQAECgQIBgAAAA==.Notham:BAAANQAECgQIBgAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Oldungeonguy:BAAANQADCgUIBQAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgIIAgAAAA==.Oreyn:BAAANQADCggICAAAAA==.',
Pa='Paladín:BAAANQAECgIIAwAAAA==.Palazar:BAAANQAECgUICgAAAA==.Paoka:BAAANQADCgQIBwAAAA==.Pargonz:BAAANQAECgUICwAAAA==.Patoko:BAAANQAECgMIBAAAAA==.Payn:BAAANQADCggICAAAAA==.Paypay:BAAANQAECgYICgAAAA==.',
Ph='Phalannx:BAAANQADCgEIAQAAAA==.Philipx:BAAANQAECgEIAQAAAA==.',
Pi='Piglittle:BAAANQAECgEIAQAAAA==.Pindad:BAAANQAECgYICAABNQAECgcIDQABAAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAAANQAECgEIAQAAAA==.',
Pr='Proshvam:BAAANQADCgcIBwAAAA==.',
Ra='Ragingmonkx:BAAANQAECgUIBwAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQADCgEIAQABNQADCgcIBgABAAAAAA==.Raventer:BAAANQADCggIFQAAAA==.Razpuutinn:BAAANQABCgUICQAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYICQAAAA==.',
Ri='Riggamortie:BAAANQAECgQIBAAAAA==.',
Ro='Rollos:BAAANQAECgQICAAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinsimp:BAABNQAECoEYAAMFAAkJ1SP2AAA2AwAKAAkJ+CE1AgBdAwAFAAgJmiP2AAA2AwAAAA==.',
['Rä']='Rävylock:BAAANQABCgIIAgAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.Saintnick:BAAANQADCgUIBQAAAA==.Samtarkras:BAAANQAECgQIBgAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAABNQAECoE+AAQLAAkJwhwQAQCZAgALAAcJ4h4QAQCZAgAMAAcJIhjjGAA3AgANAAQJ/BdLHABDAQAAAA==.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAECgkJGQADAOAbAA==.Shareholder:BAEANQAECgQIBAABNQAECgkJFQAIAAcjAA==.Shiivera:BAAANQAECgUIBQAAAA==.Shimada:BAAANQAECgQIBgAAAA==.Shotsyll:BAAANQAECgMIAwAAAA==.',
Sk='Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAAANQADCgUIBQAAAA==.Skynomad:BAAANQAECgUIBgAAAA==.',
Sl='Slyde:BAAANQAECgMIAwAAAA==.',
Sm='Smalldk:BAAANQAECgQICAABNQAECgkJFwAOAKkcAA==.Smallrichard:BAAANQABCgUIBQABNQAECgQIBwABAAAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAAANQADCgcIDAAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgQIBAABAAAAAA==.',
Sn='Snek:BAAANQAECgEIAQAAAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Solborne:BAAANQABCgIIAgAAAA==.Solfreid:BAAANQADCgYIEAAAAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAPAHkmAA==.Soulfang:BAAANQAECgIIAgAAAA==.Soullost:BAAANQAECgQIBgAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.',
Sq='Squidmonk:BAAANQAECgYIDAAAAA==.',
St='Stardrive:BAAANQAECgcIDQAAAA==.Steelwhacka:BAAANQAECgIIAgAAAA==.Steven:BAAANQAECggIEwAAAA==.Stormstyle:BAAANQAECgIIBAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAAANQADCggIDQAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgIIAgAAAA==.Surtur:BAAANQAECgYICQAAAA==.Sus:BAAANQADCgYICQAAAA==.',
Sy='Sygismund:BAAANQADCggIEQAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAAANQAECgUICgAAAA==.Taotien:BAAANQADCgcIDQAAAA==.',
Tc='Tchaik:BAAANQAECgUIBwAAAA==.',
Te='Terrance:BAAANQADCgYIBgAAAA==.',
Th='Thanah:BAAANQAECgEIAQAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQADCggICAAAAA==.Thickthang:BAAANQAECgYIDgAAAA==.',
Ti='Tigerugly:BAAANQAECgYICgAAAA==.Tinytea:BAAANQAECgYICgAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Tolivan:BAAANQAECgYICgAAAA==.Tonali:BAAANQAECgIIAwAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgAAAA==.',
Tr='Trusinner:BAABNQAECoEQAAIQAAcJZRdIMgAUAgAQAAcJZRdIMgAUAgAAAA==.',
Ts='Tsusha:BAEANQAECgEIAgAAAA==.',
Tu='Turkeyleg:BAAANQADCggIFAAAAA==.',
Tw='Twippy:BAAANQAECgYICwAAAA==.Twobeers:BAAANQADCgUIBQAAAA==.',
Ty='Tyanis:BAAANQADCgUIBQABNQADCgUIDQABAAAAAA==.Tyriam:BAAANQAECgUIBwAAAA==.',
Va='Valikbagul:BAAANQADCggIDAAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.',
Ve='Vectore:BAAANQAECgQIBQAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAAANQAECgcIDgAAAA==.Verso:BAAANQAECgIIAQAAAA==.',
Vi='Vitalithry:BAAANQADCggIFQAAAA==.Vivii:BAAANQAECgEIAQAAAA==.Vizzysmash:BAAANQADCggICAABNQAECgYICgABAAAAAA==.',
Vo='Volle:BAAANQADCgEIAQAAAA==.',
Wa='Warchicken:BAAANQAECgQIBgAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAAANQAECgYICgAAAA==.',
Wh='Whatchawant:BAAANQADCgcICAAAAA==.Whiskeybeer:BAAANQADCggIFAAAAA==.',
Wi='Wiiska:BAAANQAECgcIEQAAAA==.Windoelicker:BAAANQADCgcIBwAAAA==.',
Wo='Worgya:BAAANQADCgUIBQAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.Wrlccywhefr:BAAANQAECgcIDQAAAA==.',
Wu='Wuggles:BAAANQAECgcIDQAAAA==.',
Xa='Xalatoes:BAAANQADCggIDgAAAA==.Xalbedo:BAAANQABCgYIBgAAAA==.',
Xb='Xbalanque:BAAANQAECgQIBAAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECgcIEAAQAGUXAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQADCgIIAgAAAA==.',
Ye='Yetil:BAAANQAECgIIAgAAAA==.',
Yn='Ynotraw:BAAANQAECgcIDQAAAA==.',
Yo='Yourephired:BAAANQAECgIIAgAAAA==.',
Za='Zaycursed:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.Zaydream:BAAANQADCgcIBwABNQAECgYICQABAAAAAA==.Zaylight:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Zayseer:BAAANQAECgYICQAAAA==.',
Ze='Zello:BAAANQAECgIIAgAAAA==.',
Zi='Ziggybeast:BAAANQAECgQICwAAAA==.Zignag:BAAANQADCgYIBgAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgQIBAAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECgYICQABAAAAAA==.',
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
