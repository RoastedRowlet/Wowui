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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Warlock-Demonology','Mage-Arcane','Monk-Mistweaver','Paladin-Retribution','Druid-Balance','Druid-Restoration','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Paladin-Holy','DeathKnight-Blood','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAAANQAECgIIBAAAAA==.',
Ad='Ado:BAAANQAECgIIAwAAAA==.Adversity:BAAANQAFFAEIAQAAAA==.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.',
Ai='Aiolii:BAAANQAECgMIBAAAAA==.',
Ak='Akiras:BAAANQABCgQJBwAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Alyndrya:BAAANQAECgYIEAAAAA==.',
Am='Amithralia:BAAANQAECgUJCwAAAA==.',
An='Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQADCgcIDQAAAA==.Anzarna:BAAANQADCgcIGAAAAA==.',
Ao='Aohikari:BAAANQAECgIIAwABNQAFFAUIDQABAJ4bAA==.',
Ap='Aprigity:BAAANQAECgIJAwAAAA==.',
Aq='Aquaten:BAAANQAECgMIBAAAAA==.',
Ar='Arashinigon:BAAANQAECgYIDQAAAA==.Arceus:BAAANQAECgIJAgAAAA==.Arick:BAAANQAECgUICAAAAA==.Ark:BAABNQAECoEjAAMBAAkK+yYDAAAWBAABAAkK+yYDAAAWBAACAAEKHCRCwgBhAAAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAAANQAECgEIAgAAAA==.',
Ax='Axon:BAAANQAECgQICQAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAAANQAECgMIBAAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAAANQAECgUIDgAAAA==.Battlebot:BAAANQAECgEIAgAAAA==.',
Be='Beet:BAAANQAECgYJCgAAAA==.Belgaron:BAAANQABCgEIAQABNQAECgYIEQADAAAAAA==.Belitha:BAAANQAECgcJDgAAAA==.Belmaris:BAAANQAECgIIBAAAAA==.Benevolence:BAAANQADCgIIAgAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQADCgcIEAAAAA==.Bigdruid:BAAANQAECgIIAwAAAA==.Bimbosuzi:BAAANQAECgUJDAAAAA==.Bingbing:BAAANQADCgQIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAAANQAECgUICwAAAA==.Bluegrass:BAAANQAECgYIEAAAAA==.',
Bo='Borc:BAAANQADCgYIFQAAAA==.Borik:BAAANQAECgYIDQAAAA==.Borknagar:BAAANQADCgUIBgAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAECgIIAgADAAAAAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brisket:BAAANQADCggIFgAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAAANQAECgQIBgAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgYJDQADAAAAAA==.Buckme:BAAANQAECgcIEgAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAYIDgAEADMiAA==.Busen:BAAANQADCgYJDgAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAAANQAECgUIDwAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQADCggIGgAAAA==.Caralhan:BAAANQAECgEIAQAAAA==.Castelo:BAAANQADCggICAAAAA==.',
Ce='Cedra:BAABNQAECoEfAAIFAAkKeCBAHQBCAwAFAAkKeCBAHQBCAwAAAA==.Cegeo:BAAANQAECgYIDgAAAA==.Celari:BAAANQAECgEIAQAAAA==.',
Ch='Cheepdeeps:BAAANQAECgYJEAAAAA==.Chelea:BAAANQABCggJDwAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgIIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAAANQAECgEIAQAAAA==.Cirdle:BAAANQAECgUJCQAAAA==.',
Co='Cobalt:BAABNQAECoEYAAIEAAgK+R4AGgDMAgAEAAgK+R4AGgDMAgAAAA==.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAAANQAECgUJCwAAAA==.Crucifixea:BAAANQAECgUIBQAAAA==.Crystyl:BAAANQAECgEIAQAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAECggJEAADAAAAAA==.',
Cy='Cymoril:BAAANQAECggJEAAAAA==.',
Da='Daddy:BAABNQAECoEYAAIGAAkKEyDNAgBeAwAGAAkKEyDNAgBeAwAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAAANQAECgQIBAAAAA==.Darkcarnival:BAAANQAECgIJBAAAAA==.Dasnotgood:BAAANQADCgcIEgAAAA==.',
De='Deemon:BAAANQAECgIJBQAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEJAQAAAA==.Denard:BAAANQADCgUICQABNQADCggIFgADAAAAAA==.Denarias:BAAANQADCgUJBQABNQADCgcIGAADAAAAAA==.Denevien:BAAANQAECgEIAgAAAA==.Desdemona:BAAANQAECgEIAQAAAA==.Dethiaris:BAAANQAECgQIBgAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgEIAQAAAA==.',
Dk='Dkaiseremp:BAAANQAECgQIBgAAAA==.',
Do='Dobutsu:BAAANQAECgcICwAAAA==.Doomace:BAABNQAECoEZAAIHAAgKXRIiUwAKAgAHAAgKXRIiUwAKAgAAAA==.',
Dr='Draaka:BAAANQADCgYICAAAAA==.Dragon:BAAANQAECgcIBwAAAA==.Driftyshaman:BAAANQADCgYIEAAAAA==.Dræghoule:BAAANQADCggIFAAAAA==.',
Du='Durnik:BAAANQAECgYIBwABNQAECgYIEQADAAAAAA==.',
Dw='Dworflundgrn:BAAANQAECgUJCQAAAA==.',
Dy='Dyamí:BAAANQAECgIIBQAAAA==.',
['Dá']='Dánte:BAAANQADCgcJFQAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECoEVAAMIAAcK6RHARgBOAQAIAAUKcRXARgBOAQAJAAQKVALDOQCnAAAAAA==.Eldiablo:BAAANQAECgMIAwAAAA==.Electric:BAAANQAECgIJAgAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAAANQAECgYJDwAAAA==.Elrythe:BAAANQAECggJEwAAAA==.',
Er='Eraleth:BAAANQAECgUIBQABNQAECgcJDgADAAAAAA==.',
Fa='Faced:BAAANQAECgQIBAAAAA==.Fatalii:BAAANQADCgQIBAAAAA==.',
Fe='Felebash:BAAANQADCggJHQAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECoEaAAIKAAgKMCPeBAAPAwAKAAgKMCPeBAAPAwAAAA==.Floofthulu:BAAANQADCggICAAAAA==.Fluffalo:BAAANQAECgYICgABNQAECggIGgAKADAjAA==.',
Fo='Foxypocket:BAAANQAECgMIBAAAAA==.',
Fr='Fredrickk:BAAANQADCggJCAAAAA==.',
Fu='Furcas:BAAANQADCgMIAwAAAA==.Furrglur:BAAANQAECgEIAQABNQAECggIGgAKADAjAA==.Furrylight:BAAANQAECgEIAQABNQAECgkJGAABALQcAA==.Furryphase:BAABNQAECoEYAAMBAAkKtBztEgDuAgABAAkKtBztEgDuAgACAAEKeAK/8wAkAAAAAA==.',
Ga='Galnier:BAAANQAECgIJBQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBAAAAA==.',
Gl='Glaur:BAAANQAECgQIBQAAAA==.',
Gr='Gripisrdy:BAAANQAECgIIBAAAAA==.',
Gu='Gunslingr:BAABNQAECoEXAAILAAcKjiE7BACHAgALAAcKjiE7BACHAgAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAAANQAECgIJAgAAAA==.',
He='Headpats:BAAANQAECggJEAAAAA==.Hearthisrdy:BAAANQADCggIDgAAAA==.Hexwhisper:BAAANQADCgYICgAAAA==.Heycarlos:BAABNQAECoEaAAMMAAgK3B8ICwD4AgAMAAgK3B8ICwD4AgANAAIKTAfcgQBjAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAUIDQABAJ4bAA==.Hikarishaman:BAACNQAFFIENAAMBAAUKnhuOCQACAQABAAMKiBmOCQACAQACAAMKeBSQCgD7AAA1AAQKgSMAAwEACQqiGyYqAFkCAAEACQqiGyYqAFkCAAIABwpsGWI6ABICAAAA.Hime:BAAANQAECgIIBAAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBAAAAA==.Honeypieheal:BAAANQADCgEIAQAAAA==.Horabad:BAAANQAECgEIAQAAAA==.Hosemachine:BAAANQAECgYIDAAAAA==.',
Hu='Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQADCggIFAAAAA==.Hèrifire:BAAANQADCgcIEgAAAA==.',
Ic='Icyshadow:BAAANQAECgMIAwAAAA==.',
Ih='Ihalo:BAAANQAECgQIBAAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgMJAwAAAA==.Jasmind:BAAANQADCggJDQAAAA==.',
Ji='Jiwà:BAABNQAECoEfAAMBAAkK6Q+xPQD4AQABAAkK6Q+xPQD4AQACAAUKrwEiqQCqAAAAAA==.',
Jo='Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAAANQAECgQJBQAAAA==.Kahless:BAAANQADCgcJDAAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kaliyah:BAAANQAECgIJBgAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAAANQAECgYICwAAAA==.',
Kh='Khazabrew:BAAANQAECgUICwAAAA==.',
Ki='Kiamara:BAAANQAECgEIAQAAAA==.Kinderlin:BAAANQAECgUICwAAAA==.Kirbun:BAAANQAECgcIEgAAAA==.Kizchaos:BAAANQAECgEJAQAAAA==.',
Ko='Komurash:BAAANQAECgQIBgAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.',
La='Lancaban:BAAANQADCgcIGAAAAQ==.',
Le='Lethalarrow:BAAANQAECgMIAwAAAA==.Lewisr:BAAANQAECgUICAAAAA==.',
Li='Ligahoo:BAAANQADCggJDwAAAA==.Lilysweets:BAAANQADCgMIAwAAAA==.',
Lo='Lorryanne:BAAANQAECgYIEgAAAA==.',
Lu='Lucianas:BAAANQAECgIIAgAAAA==.Lunacat:BAAANQADCggJCAABNQADCgYJDwADAAAAAA==.',
Ly='Lysi:BAAANQAECgMIAwAAAA==.',
Ma='Madaea:BAAANQAECgYIEgAAAA==.Madameuyen:BAAANQADCgcICwAAAA==.Madlyn:BAAANQADCgcIBwAAAA==.Magepuppy:BAAANQAECgUICgABNQAECggJHgAOABwZAA==.Makavalii:BAABNQAECoEmAAMPAAcKNBJkTQC8AQAPAAcKNBJkTQC8AQAHAAUK0g8TngAxAQAAAA==.Malanimus:BAAANQAECgQJBwAAAA==.Malholis:BAAANQADCggJIwAAAA==.Matagi:BAAANQAECgcICgAAAA==.Mate:BAAANQADCgUIBQABNQADCggIFgADAAAAAA==.',
Me='Meeseks:BAAANQAECgYJDwAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAAANQAECgEIAQAAAA==.Melorea:BAAANQADCgIJAgAAAA==.Merdin:BAAANQAECgUICwAAAA==.Methmartion:BAAANQAECgMIBAAAAA==.',
Mi='Mish:BAAANQAECgQIBAAAAA==.Missiah:BAAANQAECgUJCwAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIJAgAAAA==.Moonfell:BAAANQAECgUJCAAAAA==.Moonlilly:BAAANQAECgEIAQAAAA==.Mopp:BAAANQADCgYJBgAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgMJAwAAAA==.',
Mx='Mxtemlen:BAAANQADCgUJCgABNQAECgQIDQADAAAAAA==.',
My='Mylilhunter:BAAANQAECgIIAgAAAA==.Myrtheli:BAAANQADCggICAAAAA==.Mysticx:BAAANQADCggICAAAAA==.',
Na='Nachtelf:BAAANQAECgYIEAAAAA==.Nagan:BAAANQAECgYIBgAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAAANQAECgYJEAAAAA==.Nathel:BAAANQAECgMIBAAAAA==.',
Ni='Nirra:BAAANQADCgYJBgAAAA==.',
No='Noctis:BAAANQAECgUJCgAAAA==.Notoriginal:BAAANQADCgcIBwAAAA==.Novatron:BAAANQAECgEJAQAAAA==.',
Nu='Nuked:BAAANQAECgUJEQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQABCggIDwAAAA==.',
Og='Ograskygazer:BAAANQAECgMIAwAAAA==.',
Om='Omee:BAAANQAECgEIAgAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQAECgMIBAAAAA==.Orioncheats:BAAANQAECgUIDgAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAAANQAECgEIAQAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQAAAA==.Pedarias:BAAANQAECgUIDQAAAA==.Peon:BAAANQAECgUIBQAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAAANQAECgIIBAAAAA==.Phredrick:BAAANQAECgEJAQAAAA==.',
Pi='Picklebosh:BAABNQAECoEiAAICAAkK9CQDAwDIAwACAAkK9CQDAwDIAwAAAA==.Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQADCgcIBwAAAA==.',
Po='Pockithealz:BAAANQADCgQJBAABNQADCgQIBAADAAAAAA==.Pokerface:BAAANQADCgUJBQAAAA==.',
Pr='Precious:BAAANQADCggIDwABNQAECgIIAgADAAAAAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qu='Quattro:BAAANQAECgUJBgAAAA==.',
Ra='Racecar:BAAANQAECgEIAQAAAA==.Raezil:BAAANQAECgQICQABNQAECgUIDwADAAAAAA==.Raivyn:BAAANQAECgYIEQAAAA==.Rathmora:BAAANQABCggJDwAAAA==.Raylaira:BAAANQADCgcIFwABNQADCgcIGAADAAAAAA==.Raziel:BAAANQADCgYJBgAAAA==.',
Re='Remnants:BAAANQADCggIEwAAAA==.Renard:BAAANQAECgYIDwAAAA==.Reposado:BAAANQADCgYIBgAAAA==.Revelare:BAAANQAECgIIBAAAAA==.Rexbie:BAAANQAECgcJCwAAAA==.',
Rh='Rhylee:BAAANQADCgYIDAAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAAANQAECgUIBgAAAA==.',
Ro='Robberttrest:BAAANQAECgMIBgAAAA==.Rockyhunterr:BAABNQAECoEYAAIQAAgK0R8/EQDdAgAQAAgK0R8/EQDdAgAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockywarlock:BAAANQAECgEIAQAAAA==.Rockywarrior:BAAANQADCgYICgAAAA==.Rooth:BAAANQADCggJFwAAAA==.Roryn:BAABNQAECoEZAAIHAAkKXSCoFAAzAwAHAAkKXSCoFAAzAwAAAA==.',
Ru='Rubï:BAAANQAECgUIAwAAAA==.Rugiaas:BAACNQAFFIEKAAIPAAUKDiKCAgADAgAPAAUKDiKCAgADAgA1AAQKgSoAAw8ACQo7JaUBAMUDAA8ACQo7JaUBAMUDAAcAAQqFIWb+AF0AAAAA.Rugian:BAAANQADCgQIBAABNQAFFAUICgAPAA4iAA==.',
Ry='Ryuka:BAAANQAECgUJCgAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgUIDwADAAAAAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgADAAAAAA==.Samyria:BAAANQADCgQJBAAAAA==.Satyaru:BAAANQAECgYJDgAAAA==.Saucy:BAAANQAECgMIAwAAAA==.',
Se='Sedona:BAAANQAECgEIAQAAAA==.Selarra:BAAANQAECgUJCQAAAA==.Seric:BAAANQAECgUJDQAAAA==.Sethuriel:BAAANQAECgUIDAAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shenandoah:BAAANQADCgYJBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Sm='Smartfood:BAAANQADCggIHQAAAA==.Smoochybooty:BAAANQAECgEIAQAAAA==.',
So='Solnar:BAAANQAECgQIDQAAAA==.',
Sp='Splashdaddy:BAACNQAFFIEHAAIBAAQKQg2NBwA5AQABAAQKQg2NBwA5AQA1AAQKgSIAAgEACQodHyENACIDAAEACQodHyENACIDAAE1AAMKBgkPAAMAAAAA.Spoiled:BAAANQADCggICAABNQAECgIIAgADAAAAAA==.',
Sr='Srìracha:BAAANQADCggICAAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQAECgEIAQAAAA==.Stormieskye:BAAANQAECgUJDQAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Suzume:BAAANQAECgQIBAABNQAFFAUIDQABAJ4bAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQADCggJIwAAAA==.',
Ta='Taea:BAAANQADCggIGgAAAA==.Taeus:BAAANQAECgUICwAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAAANQAECgYJEgAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQADCgUJBQABNQADCgcIGAADAAAAAA==.Teratrendera:BAAANQAECgMIBAAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgEIAQAAAA==.',
Th='Thavis:BAAANQAECgYIBwAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAAANQAECgEIAQAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgYJBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAAANQAECgcJCwAAAA==.Tinkr:BAAANQAECgUICgAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Tom:BAAANQAECgUIBgABNQAECgUIDwADAAAAAA==.Torrey:BAAANQAECgQIBgAAAA==.Totemsareus:BAAANQAECgcIEgAAAA==.Toxx:BAAANQAECgEJAQAAAA==.',
Tr='Tradd:BAABNQAECoEbAAMRAAkKWRwVEQD2AgARAAgK1x0VEQD2AgASAAcKww7NBwCWAQAAAA==.Trallor:BAAANQAECgQJCAAAAA==.Trhall:BAAANQADCgcICwAAAA==.Tristyana:BAAANQAECgYJEAAAAA==.',
Ts='Tsiddahn:BAAANQAECggIEQAAAA==.Tsunâde:BAAANQAECgYJDQAAAA==.',
Ty='Tylurien:BAAANQAECgIIBAAAAA==.Tyrael:BAAANQAECgEIAQABNQADCgMJAwADAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQADCgYICgAAAA==.',
Ur='Urbanprey:BAAANQAECgUICQAAAA==.',
Va='Valenhi:BAAANQADCgQJCgAAAA==.Valkoinen:BAAANQADCgMJAwAAAA==.Valora:BAAANQAECgYJDgAAAA==.Valoria:BAAANQADCgYIBgAAAA==.Vanille:BAAANQAECgMIAwAAAA==.Vargen:BAAANQAECgEIAQAAAA==.Varonika:BAAANQAECgIIAgAAAA==.Vayla:BAAANQAECgYIEQAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQADCggIDwAAAA==.Vegasducks:BAAANQAECgUICAAAAA==.Velara:BAAANQADCgQIAwAAAA==.Veld:BAAANQAECgQIBAAAAA==.Velithara:BAAANQADCgYJBgAAAA==.',
Vi='Violet:BAAANQAECgIJAgAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Warfise:BAAANQADCggJFQAAAA==.Warspriest:BAAANQAECgIIAwAAAA==.Warwizard:BAABNQAECoEcAAIPAAgKIyNgCwA4AwAPAAgKIyNgCwA4AwAAAA==.',
Wd='Wdemperor:BAAANQAECgMJAwABNQAECgQIBgADAAAAAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEJAQABNQAECgEIAQADAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQADCgUIDQAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECoEXAAIPAAcKzxahQADzAQAPAAcKzxahQADzAQAAAA==.',
Wr='Wrathbarrage:BAAANQADCggJCAABNQAECgYIEAADAAAAAA==.Wrathchoi:BAAANQADCgIIAQAAAA==.Wrathstorm:BAAANQAECgYIEAAAAA==.',
Ya='Yazahk:BAAANQADCggJFgABNQADCgYIBAADAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggJCAAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFIEMAAIQAAUKrh4rBAC6AQAQAAUKrh4rBAC6AQA1AAQKgR0AAhAACQqdIZ8KAC4DABAACQqdIZ8KAC4DAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQADCgYIBAAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgIJBgAAAA==.Zeva:BAAANQADCggJIwAAAA==.',
Zo='Zonzmik:BAAANQABCgYIBAAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgIIAgABNQADCgcIGAADAAAAAA==.',
Zu='Zurazaee:BAAANQAECgMIBAAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAAANQAECgYJEAAAAA==.',
['Ïr']='Ïridescent:BAAANQAECgIIAgAAAA==.',
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
