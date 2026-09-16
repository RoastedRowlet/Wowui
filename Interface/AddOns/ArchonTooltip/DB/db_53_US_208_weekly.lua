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

local lookup = {'Evoker-Preservation','Unknown-Unknown','Hunter-Marksmanship','Rogue-Subtlety','DeathKnight-Unholy','Hunter-BeastMastery','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Mage-Arcane','Evoker-Devastation','Paladin-Retribution','DeathKnight-Blood','Monk-Mistweaver','Warrior-Arms','Monk-Windwalker','Shaman-Enhancement','Shaman-Elemental','Priest-Shadow','Priest-Holy','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abor:BAAANQADCgcIDQAAAA==.Abuela:BAAANQAECggICgAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ae='Aegla:BAAANQAECgcICwAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ak='Akiko:BAAANQAECgYIBgAAAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAABNQAECoEcAAIBAAkJ7xdhCwB9AgABAAkJ7xdhCwB9AgAAAA==.Alerath:BAAANQADCgYICQAAAA==.Alliar:BAAANQAECgYIDAAAAA==.Allynstraza:BAAANQAECgEIAQAAAA==.',
Am='Amgems:BAAANQAECgQIBAAAAA==.Amordred:BAAANQAECgIIAgAAAA==.',
An='Anasterion:BAAANQAECgcIEQAAAA==.Andarus:BAAANQADCgUIBQABNQAECgYIEQACAAAAAA==.Ankles:BAAANQAECgYIDgAAAA==.Ansley:BAAANQADCgUICAABNQAECgIIAgACAAAAAA==.',
Ar='Arnaldo:BAAANQADCgcICAAAAA==.',
As='Ashli:BAAANQAECgIIAgAAAA==.',
At='Atlasbär:BAAANQADCggICAABNQADCgYIDwACAAAAAA==.Atlasdark:BAAANQAECgEIAQABNQADCgYIDwACAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.',
Ba='Balrock:BAAANQADCgYIBgAAAA==.Balthromaw:BAAANQAECgMIAwAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardwaffle:BAAANQAECgIIAwAAAA==.Bearlando:BAAANQAECgQIBAABNQAECgkJHAADAOgcAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDQAAAA==.Belstab:BAABNQAECoEaAAIEAAgJoguKEgAKAgAEAAgJoguKEgAKAgAAAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIDwAAAA==.',
Bg='Bgbalkoth:BAAANQADCgQIBAAAAA==.',
Bi='Bigblammy:BAAANQADCggICAABNQAFFAIIAgACAAAAAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Bloodavenger:BAAANQAECggIDgAAAA==.Bloodemongar:BAAANQAECgUIBQAAAA==.Bloodhoundss:BAAANQAECgIIAgAAAA==.Blössöm:BAAANQAECgQICgAAAA==.',
Bo='Bobdk:BAABNQAECoEfAAIFAAkJ9yGyBQB2AwAFAAkJ9yGyBQB2AwAAAA==.Bomboklaat:BAAANQABCgYIBgAAAA==.Boomfrin:BAAANQADCgYIBgAAAA==.Boomshield:BAAANQAECgUIAwAAAA==.Boxbeater:BAAANQAECgYIDAAAAA==.',
Br='Braegen:BAAANQADCgQIBgABNQAECgYIEQACAAAAAA==.Brewslee:BAAANQADCggICAAAAA==.Bruceleett:BAAANQAECgYICQABNQADCgcIBwACAAAAAA==.',
Bu='Buffmeister:BAAANQADCgUICQAAAA==.Bullioss:BAAANQABCgQIBgABNQAECgcIDwACAAAAAA==.',
['Bè']='Bètrayèr:BAAANQABCgIIAgAAAA==.',
['Bö']='Böbbyboucher:BAAANQAECgIIAwAAAA==.',
Ca='Cainn:BAAANQADCgYICwABNQAECgYIDgACAAAAAA==.Calfurion:BAAANQAECgcIEAAAAA==.Capncrunch:BAAANQADCgUIBQAAAA==.Cazleah:BAAANQAECgYIDwAAAA==.',
Ce='Cessatio:BAAANQAECgQICgAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAAANQAECgUICAABNQAECgYIEQACAAAAAA==.Chrisbrewn:BAAANQAECgYIDAAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clevelandoe:BAABNQAECoEcAAMDAAkJ6ByECwDTAgADAAkJxhyECwDTAgAGAAMJLQxMnQDGAAAAAA==.',
Co='Cocobear:BAAANQADCgIIAgAAAA==.Coeurdeleon:BAAANQAECgYICgAAAA==.Condemnation:BAAANQAECgUIDAAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgQIBAABNQADCggIDQACAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQACAAAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbstomped:BAAANQAECgUICQAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgIIAgABNQAFFAQIBwAHAGIVAA==.Darkvizzy:BAAANQAECgYIEAAAAA==.Daymån:BAAANQADCggICQAAAA==.',
De='Deathreaper:BAAANQADCggIFwAAAA==.Delix:BAAANQAECgEIAQAAAA==.Demiplo:BAAANQAECgYIBwAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgIIAwACAAAAAA==.',
Di='Discipline:BAAANQAECgQIBgAAAA==.',
Dr='Dratr:BAAANQAECgQIBgAAAA==.Draxyl:BAAANQAECgYIEQAAAA==.Drekhan:BAAANQADCgMIAwABNQAECgYIEQACAAAAAA==.Drham:BAAANQAECgYIDAAAAA==.Drokos:BAAANQABCgQIBwABNQAECgcIDwACAAAAAA==.Drtree:BAAANQADCgcIBwAAAA==.',
Du='Dunhambones:BAAANQAECgUIBwAAAA==.Duo:BAAANQAECgQIBQABNQADCgcIDQACAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Electora:BAAANQAECgYIBgAAAA==.Eleidon:BAAANQADCgYIBgAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAAANQAECgcIEgAAAA==.',
En='Enyô:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.',
Er='Erada:BAAANQAECgQIBgAAAA==.',
Ev='Evoklando:BAAANQADCgUICgABNQAECgkJHAADAOgcAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgUIBQAAAA==.Expectpriest:BAAANQABCgQIBAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Fe='Felad:BAAANQAECgQIBgABNQAECgQIBAACAAAAAA==.Felwen:BAAANQADCgEIAQAAAA==.',
Fh='Fhalanx:BAAANQABCgIIAgAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECgEIAgABNQABCgQIBAACAAAAAA==.Flowdinstuna:BAAANQADCgcIDQAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAAANQAECgYIDQAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.',
Fu='Furrybait:BAEANQADCgIIAgABNQADCgQIBgACAAAAAA==.Furyiosa:BAAANQAECgcICgAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQIBgACAAAAAA==.Gaiseric:BAABNQAECoEVAAIFAAgJHxKdJgAFAgAFAAgJHxKdJgAFAgAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECoEaAAQIAAkJtR/dJABVAgAIAAcJ2BzdJABVAgAJAAQJCh+IHABYAQAKAAEJtCTWFgBMAAAAAA==.',
Gi='Girltank:BAAANQAECgIIAgAAAA==.',
Gn='Gnarlak:BAAANQABCgIIAgAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gotfleas:BAAANQAECgcIEQAAAA==.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAAANQAECgUICwAAAA==.Grimthruul:BAAANQAECgUICgAAAA==.Grommkar:BAAANQAECgYIBwAAAA==.',
Ha='Halucination:BAAANQAECgQICgAAAA==.Harthan:BAAANQAECgEIAQAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwACAAAAAA==.Henchman:BAAANQABCgQICAABNQAECgcIDwACAAAAAA==.Hetzák:BAAANQAECgYIDQAAAA==.',
Hi='Hintolisu:BAAANQAECgcIEQAAAA==.',
Ho='Hobbess:BAAANQAECgcIEAABNQAFFAYIDAALAP4eAA==.Holybaloney:BAAANQAECgYICgAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Hongis:BAAANQADCgUIBQAAAA==.Hoofinit:BAAANQAECgQIBAAAAA==.',
Hu='Huatarm:BAAANQAECgUIDAAAAA==.',
Ia='Iadygaga:BAAANQAECgUIBQAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQADCgYICwABNQAECgcICwACAAAAAA==.',
Ir='Ironspin:BAAANQAECgEIAQAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Ja='Jaark:BAAANQAFFAEIAQAAAA==.Jabalru:BAAANQADCgMIAwAAAA==.Jake:BAAANQAECgYIDQAAAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jen:BAAANQAECgcIEQAAAA==.',
Jo='Jocon:BAAANQADCgcIEwAAAA==.',
Ju='Jugulator:BAAANQADCgIIAgAAAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAAANQAECgUIBQABNQAECgUIBAACAAAAAA==.Kanami:BAAANQAECgEIAQAAAA==.Kaynyx:BAAANQAECgYIDgAAAA==.Kazimer:BAAANQADCgcIBwAAAA==.',
Ke='Kedrik:BAAANQAECgYIDgAAAA==.Kerb:BAAANQAECgEIAQAAAA==.Kery:BAAANQADCgMIAwAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAAANQAECgcIEgAAAA==.',
Ki='Killinflak:BAAANQADCgMIAwAAAA==.Kissyboots:BAAANQAECgQICAAAAA==.Kiyo:BAAANQAECgQIBwABNQAECgcIEQACAAAAAA==.',
Ko='Konjur:BAAANQAFFAIIAgAAAA==.',
Kr='Krelock:BAAANQAECgYIBgAAAA==.Krymzendeath:BAAANQADCgYICAABNQAECgYIDgACAAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgUIBAAAAA==.',
['Kä']='Kämo:BAAANQAECgEIAQABNQAECgUIBAACAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgQIBAABNQAECggIGQAMABUlAA==.Lakeyy:BAABNQAECoEZAAIMAAgJFSW5AgBbAwAMAAgJFSW5AgBbAwAAAA==.Lakeyys:BAAANQADCgcICQABNQAECggIGQAMABUlAA==.Lanuor:BAAANQADCgEIAQAAAA==.Lavagobrr:BAAANQAECgQIBAAAAA==.Lawrence:BAAANQAECgcIDgAAAA==.',
Le='Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQADCggICgAAAA==.Lilikoii:BAAANQADCgMIBAABNQAECggIGQAMABUlAA==.Lilslaver:BAAANQADCggIGQAAAA==.Lisex:BAABNQAECoEdAAINAAkJXiH/AwBUAwANAAkJXiH/AwBUAwAAAA==.Lithe:BAAANQAECgcIDAAAAA==.',
Lo='Locklear:BAAANQAECgYICgAAAA==.Logic:BAABNQAECoEgAAIOAAkJ+R9sIQAPAwAOAAkJ+R9sIQAPAwAAAA==.',
Lu='Lunaria:BAAANQAECgEIAQABNQAECggIGQAMABUlAA==.Luxe:BAAANQAECgEIAQABNQAECggIGQAMABUlAA==.',
Ma='Macediin:BAAANQAECgMIAwAAAA==.Mackenna:BAAANQADCgEIAQAAAA==.Madderhunter:BAAANQAECggIEwAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgYIDAACAAAAAA==.Magnolìa:BAAANQADCgYICwAAAA==.Malthael:BAAANQAECgQIBgAAAA==.Mamageek:BAAANQAECgYICgAAAA==.Mami:BAAANQAECgEIAQAAAA==.Manhorde:BAAANQAECgQIBAABNQAECgQIBAACAAAAAA==.Manix:BAAANQAECgIIBAAAAA==.Mareo:BAAANQADCgUIBQAAAA==.Marksterique:BAAANQAECgYIDAAAAA==.',
Me='Meeko:BAACNQAFFIEJAAIBAAUJVhhdAgDFAQABAAUJVhhdAgDFAQA1AAQKgSMAAgEACQm3IW0DAEYDAAEACQm3IW0DAEYDAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQADCgMIAwAAAA==.Metalbound:BAAANQAECgQICgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAAANQAECgcICQAAAA==.Misslobster:BAAANQAECgIIAgAAAA==.',
Mo='Mokoko:BAABNQAECoEiAAIPAAkJvhqpBQDnAgAPAAkJvhqpBQDnAgAAAA==.Mokolock:BAAANQAECgMIAwABNQAECgkJIgAPAL4aAA==.Moomoo:BAAANQAECgYIDQAAAA==.Moorlin:BAAANQADCggICAAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgkJIgAPAL4aAA==.',
My='Mysticphatty:BAAANQADCggICAABNQAECgIIAgACAAAAAA==.Myyst:BAAANQADCgMIAwAAAA==.',
Ne='Necro:BAAANQAECgUICwAAAA==.Necrota:BAAANQAECgcIBwABNQAFFAIIAgACAAAAAA==.Nekronomicon:BAAANQADCgcIBwABNQAECgUIDAACAAAAAA==.Neuron:BAABNQAECoEXAAMMAAkJkBZNCgCRAgAMAAkJkBZNCgCRAgALAAUJeA/AOwBQAQAAAA==.Nexborn:BAAANQABCggICAAAAA==.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAAANQAECgYICgAAAA==.Nightflame:BAAANQAECgQIBAAAAA==.Ninjavc:BAAANQADCggIGQAAAA==.',
No='Noelle:BAAANQAECgQIBgAAAA==.Notham:BAAANQAECgQIBgAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Oldungeonguy:BAAANQADCgUICgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgQICgAAAA==.Oreyn:BAAANQAECgQIBQAAAA==.',
Pa='Paladín:BAAANQAECgUICAAAAA==.Palazar:BAAANQAECgcIEQAAAA==.Paoka:BAAANQADCgQIBwABNQADCgUICQACAAAAAA==.Pargonz:BAAANQAECgYIEQAAAA==.Patoko:BAAANQAECgcICwAAAA==.Payn:BAAANQAECgQIBAAAAA==.Paypay:BAAANQAECgcIEQAAAA==.',
Ph='Phalannx:BAAANQADCgEIAQAAAA==.Philipx:BAAANQAECgEIAQAAAA==.',
Pi='Piglittle:BAAANQAECgEIAQAAAA==.Pindad:BAAANQAECgYICAABNQAECgcIDwACAAAAAA==.',
Pl='Plzdispelme:BAAANQAECgEIAQAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAAANQAECgQIBQAAAA==.',
Pr='Proshvam:BAAANQAECgEIAQAAAA==.',
Ra='Ragingmonkx:BAAANQAECgYIDgAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgMIAwAAAA==.Raventer:BAAANQADCggIFQAAAA==.Razlock:BAAANQADCgIIAgAAAA==.Razorclaws:BAAANQADCggICAAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYICQAAAA==.',
Ri='Riggamortie:BAAANQAECgUICgAAAA==.',
Ro='Rollos:BAAANQAECgUIDQAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinsimp:BAACNQAFFIEHAAIHAAQJYhVZAQBdAQAHAAQJYhVZAQBdAQA1AAQKgSAAAwcACQmkJGwBAC0DAA8ACQn4IbIDAC4DAAcACAmEJGwBAC0DAAAA.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQADCggIFQACAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQADCgUIBQABNQAFFAEIAQACAAAAAA==.Saintnick:BAAANQADCgUIBQAAAA==.Samtarkras:BAAANQAECgUICwAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAABNQAECoFvAAQKAAkJ3h/4AAACAwAKAAcJgCT4AAACAwAIAAgJlxw+EADeAgAJAAUJOR8qDQD7AQAAAA==.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAECgkJHAADAOgcAA==.Shangzha:BAAANQAECgYICQAAAA==.Shareholder:BAEANQAECgQIBAABNQAECgkJHQAOAP0kAA==.Shiivera:BAAANQAECgYICwAAAA==.Shimada:BAAANQAECgYICwAAAA==.Shotsyll:BAAANQAECgQIBAAAAA==.',
Sk='Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAAANQAECgYIBwAAAA==.Skynomad:BAAANQAECgUICgAAAA==.',
Sl='Slyde:BAAANQAECgQIBgAAAA==.',
Sm='Smalldk:BAAANQAECgcIDgABNQAFFAMIBQAQAP4HAA==.Smallrichard:BAAANQABCgUIBQABNQAECgQICgACAAAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAAANQAECgIIAgAAAA==.Smiteytash:BAAANQADCgUICAABNQAECgUICQACAAAAAA==.',
Sn='Snek:BAAANQAECgEIAgAAAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Solborne:BAAANQABCgIIAgAAAA==.Solfreid:BAAANQAECgMIAwABNQAECgUIBQACAAAAAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwARAHkmAA==.Soulfang:BAAANQAECgIIBAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgUIBQAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAAANQADCgUIBQABNQAECgcIEAACAAAAAA==.Sprocketrot:BAAANQADCgIIAgAAAA==.',
Sq='Squidmonk:BAABNQAECoEYAAISAAkJqA22DAAJAgASAAkJqA22DAAJAgAAAA==.',
St='Stardrive:BAABNQAECoEVAAITAAgJJw3tTQD8AQATAAgJJw3tTQD8AQAAAA==.Steelwhacka:BAAANQAECgQIBgAAAA==.Steven:BAABNQAECoEYAAIUAAkJCR3gCgChAgAUAAkJCR3gCgChAgAAAA==.Stormstyle:BAAANQAECgIIBAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAAANQAECgIIAgAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQADCgcIBwABNQAECgUICgACAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgQICgAAAA==.Surtur:BAAANQAECgcIEAAAAA==.Sus:BAAANQAECgYIBgAAAA==.',
Sy='Sygismund:BAAANQADCggIGAAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAAANQAECgcIEQAAAA==.Taotien:BAAANQAECgMIAwAAAA==.',
Tc='Tchaik:BAAANQAECgYIDQAAAA==.',
Te='Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgEIAQAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQADCggICAAAAA==.Thickthang:BAABNQAECoEZAAMVAAgJgyQPAgBfAwAVAAgJgyQPAgBfAwAWAAQJAhVKdQDvAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAAANQAECgcIEQAAAA==.Tinytea:BAAANQAECgcIEQAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Tolivan:BAAANQAECgYICgAAAA==.Tonali:BAAANQAECgQIBwAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgMIAwACAAAAAA==.',
Tr='Trusinner:BAABNQAECoEbAAITAAgJ/BrTJgCuAgATAAgJ/BrTJgCuAgAAAA==.',
Ts='Tsusha:BAEANQAECgQIBgAAAA==.',
Tu='Turkeyleg:BAAANQADCggIGQAAAA==.',
Tw='Twippy:BAAANQAECggIEwAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgYICwAAAA==.Tyriam:BAAANQAECgYIDQAAAA==.',
Va='Valess:BAAANQAECgEIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.',
Ve='Vectore:BAAANQAECgQIBwAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAABNQAECoEZAAIPAAgJzR7rBgDAAgAPAAgJzR7rBgDAAgAAAA==.Verso:BAAANQAECgQIBQAAAA==.',
Vi='Vitalithry:BAAANQAECgUIBQAAAA==.Vivii:BAAANQAECgQIBQAAAA==.Vizzysmash:BAAANQADCggICAABNQAECgYIEAACAAAAAA==.',
Vo='Volle:BAAANQADCgEIAQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBgAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAAANQAECgYIDwAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAAANQAECgQIBAAAAA==.',
Wi='Wiiska:BAABNQAECoEdAAMXAAkJ3hy9DACsAgAXAAgJwxu9DACsAgAYAAIJQgIFggBUAAAAAA==.Windoelicker:BAAANQADCgcIBwAAAA==.',
Wo='Worgya:BAAANQADCgUIBQAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgcIDwACAAAAAA==.Wrlccywhefr:BAABNQAECoEYAAQZAAkJdh4tBQAnAgAZAAYJkx0tBQAnAgAaAAYJcRRGGgCtAQAEAAIJZB3fLQC2AAAAAA==.',
Wu='Wuggles:BAABNQAECoEXAAIMAAgJEBbODQBLAgAMAAgJEBbODQBLAgAAAA==.',
Xa='Xalatoes:BAAANQADCggIFgAAAA==.',
Xb='Xbalanque:BAAANQAECgQICAAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwATAPwaAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQAECgEIAQAAAA==.',
Ye='Yetil:BAAANQAECgIIAgAAAA==.',
Yn='Ynotraw:BAAANQAECgcIEgAAAA==.',
Yo='Yourephired:BAAANQAECgQIBAAAAA==.',
Za='Zaycursed:BAAANQAECgQICgABNQAECgcIEAACAAAAAA==.Zaydream:BAAANQADCgcIBwABNQAECgcIEAACAAAAAA==.Zaylight:BAAANQADCggICAABNQAECgcIEAACAAAAAA==.Zayseer:BAAANQAECgcIEAAAAA==.',
Ze='Zello:BAAANQAECgQIBQAAAA==.',
Zh='Zhengy:BAAANQADCgUIBQABNQAECgYIEQACAAAAAA==.',
Zi='Ziggybeast:BAAANQAECggIEgAAAA==.Zignag:BAAANQADCgYIBgAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgQIBQAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECgcIEAACAAAAAA==.',
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
