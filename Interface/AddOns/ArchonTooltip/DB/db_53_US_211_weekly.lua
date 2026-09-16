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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Warlock-Destruction','Mage-Arcane','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAAANQAECgIIAwAAAA==.',
Ad='Ado:BAAANQAECgIIAwAAAA==.Adversity:BAAANQAECgMIBAAAAA==.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.',
Ai='Aiolii:BAAANQAECgEIAQAAAA==.',
Ak='Akiras:BAAANQABCgQIBQAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Alyndrya:BAAANQAECgQICQAAAA==.',
Am='Amithralia:BAAANQAECgQIBgAAAA==.',
An='Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQADCgcIDQAAAA==.Anzarna:BAAANQADCgYIEQAAAA==.',
Ao='Aohikari:BAAANQAECgIIAwABNQAFFAUICAABAJ4bAA==.',
Ap='Aprigity:BAAANQAECgEIAQAAAA==.',
Aq='Aquaten:BAAANQAECgEIAQAAAA==.',
Ar='Arashinigon:BAAANQAECgQIBwAAAA==.Arceus:BAAANQADCgYICQAAAA==.Arick:BAAANQAECgMIAwAAAA==.Ark:BAABNQAECoEZAAMBAAkJuSYHAAARBAABAAkJuSYHAAARBAACAAEJHCTToABjAAAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYIBwAAAA==.Aureia:BAAANQAECgEIAQAAAA==.',
Ax='Axon:BAAANQAECgQIBgAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAAANQAECgEIAQAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAAANQAECgQICQAAAA==.Battlebot:BAAANQAECgEIAQAAAA==.',
Be='Beet:BAAANQAECgQIBAAAAA==.Belgaron:BAAANQABCgEIAQABNQAECgYICwADAAAAAA==.Belitha:BAAANQAECgYIDAAAAA==.Belmaris:BAAANQAECgIIAwAAAA==.Benevolence:BAAANQADCgIIAgAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQADCgcIEAAAAA==.Bigdruid:BAAANQAECgIIAwAAAA==.Bimbosuzi:BAAANQAECgUIBwAAAA==.Bingbing:BAAANQADCgQIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAAANQAECgQIBgAAAA==.Bluegrass:BAAANQAECgYICgAAAA==.',
Bo='Borc:BAAANQADCgYIEAAAAA==.Borik:BAAANQAECgQIBwAAAA==.Borknagar:BAAANQADCgQIBAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAQIBAADAAAAAA==.Brighteye:BAAANQADCggICgAAAA==.Brisket:BAAANQADCggIFgAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAAANQAECgIIAgAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgYIBwADAAAAAA==.Buckme:BAAANQAECgUICwAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAYIDAAEACkdAA==.Busen:BAAANQADCgUICAAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAAANQAECgUICwAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQADCggIGgAAAA==.Caralhan:BAAANQADCggIGAAAAA==.Castelo:BAAANQADCggICAAAAA==.',
Ce='Cedra:BAABNQAECoEXAAIFAAgJuB2gPQCbAgAFAAgJuB2gPQCbAgAAAA==.Cegeo:BAAANQAECgQICAAAAA==.Celari:BAAANQAECgEIAQAAAA==.',
Ch='Cheepdeeps:BAAANQAECgYICgAAAA==.Chelea:BAAANQABCggIDQAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAAANQADCggICAAAAA==.Cirdle:BAAANQAECgMIBAAAAA==.',
Co='Cobalt:BAAANQAECgcIEQAAAA==.Coolkid:BAAANQAECgMIAwAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAAANQAECgQIBgAAAA==.Crucifixea:BAAANQADCggIFAAAAA==.Crystyl:BAAANQADCggIGgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAECggIDgADAAAAAA==.',
Cy='Cymoril:BAAANQAECggICgAAAA==.',
Da='Daddy:BAAANQAECgcIDwAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAAANQADCgMIAwAAAA==.Darkcarnival:BAAANQAECgIIAwAAAA==.Dasnotgood:BAAANQADCgcIDQAAAA==.',
De='Deemon:BAAANQAECgIIAwAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Denard:BAAANQADCgQIBAABNQADCggIFgADAAAAAA==.Denevien:BAAANQAECgEIAQAAAA==.Desdemona:BAAANQADCggIGgAAAA==.Dethiaris:BAAANQAECgQIBgAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQADCggIGgAAAA==.',
Dk='Dkaiseremp:BAAANQADCggICAABNQAECgQIBAADAAAAAA==.',
Do='Dobutsu:BAAANQAECgQIBAAAAA==.Doomace:BAAANQAECgcIDgAAAA==.',
Dr='Draaka:BAAANQADCgYICAAAAA==.Dragon:BAAANQADCggIDAAAAA==.Driftyshaman:BAAANQADCgYIEAAAAA==.Dræghoule:BAAANQADCggIFAAAAA==.',
Du='Durnik:BAAANQADCggIGgABNQAECgYICwADAAAAAA==.',
Dw='Dworflundgrn:BAAANQAECgQIBAAAAA==.',
Dy='Dyamí:BAAANQAECgIIBAAAAA==.',
['Dá']='Dánte:BAAANQADCgcIDwAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAAANQAECgUIDQAAAA==.Eldiablo:BAAANQADCgQIBAAAAA==.Electric:BAAANQADCgQIBgAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAAANQAECgUICQAAAA==.Elrythe:BAAANQAECgYICwAAAA==.',
Er='Eraleth:BAAANQADCggICAABNQAECgYIDAADAAAAAA==.',
Fa='Fatalii:BAAANQADCgQIBAAAAA==.',
Fe='Felebash:BAAANQADCggIFQAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.',
Fi='Fistdaddy:BAAANQADCgYIDwAAAA==.',
Fl='Floofies:BAAANQAECgcIEQAAAA==.Floofthulu:BAAANQADCggICAAAAA==.Fluffalo:BAAANQAECgQIBAABNQAECgcIEQADAAAAAA==.',
Fo='Foxypocket:BAAANQAECgEIAQAAAA==.',
Fu='Furcas:BAAANQADCgMIAwAAAA==.Furrglur:BAAANQAECgEIAQABNQAECgcIEQADAAAAAA==.Furrylight:BAAANQAECgEIAQABNQAECgkJFgABALQcAA==.Furryphase:BAABNQAECoEWAAMBAAkJtByZCwAMAwABAAkJtByZCwAMAwACAAEJeAJZzQAkAAAAAA==.',
Ga='Galnier:BAAANQAECgIIAwAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQADCggIEgAAAA==.',
Gl='Glaur:BAAANQAECgQIBQAAAA==.',
Gr='Gripisrdy:BAAANQAECgIIAwAAAA==.',
Gu='Gunslingr:BAAANQAECgYIDAAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAAANQAECgIIAgAAAA==.',
He='Headpats:BAAANQAECggIDgAAAA==.Hearthisrdy:BAAANQADCggIDgAAAA==.Hexwhisper:BAAANQADCgUICQAAAA==.Heycarlos:BAAANQAECgYIEAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAUICAABAJ4bAA==.Hikarishaman:BAACNQAFFIEIAAMBAAUJnhtQBQAWAQABAAMJiBlQBQAWAQACAAMJkgsHBwDwAAA1AAQKgSAAAwEACQmiG/UbAHkCAAEACQmiG/UbAHkCAAIABwlsGaEqACYCAAAA.Hime:BAAANQAECgIIAwAAAA==.',
Ho='Holyblimblam:BAAANQAECgEIAQAAAA==.Honeypieheal:BAAANQADCgEIAQAAAA==.Horabad:BAAANQAECgEIAQAAAA==.Hosemachine:BAAANQAECgYICgAAAA==.',
Hu='Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQADCggIFAAAAA==.Hèrifire:BAAANQADCgcICwAAAA==.',
Ih='Ihalo:BAAANQADCggIGwAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgQIBwAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQICAAAAA==.Jameson:BAAANQADCggIDAAAAA==.Jasmind:BAAANQADCggIDQAAAA==.',
Ji='Jiwà:BAABNQAECoEcAAMBAAkJ6Q7XLAAMAgABAAkJ6Q7XLAAMAgACAAUJrwGwiQCuAAAAAA==.',
Jo='Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAAANQAECgEIAQAAAA==.Kahless:BAAANQADCgcICQAAAA==.Kakwaa:BAAANQADCggIFQAAAA==.Kaliyah:BAAANQAECgIIBAAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAAANQAECgQIBQAAAA==.',
Kh='Khazabrew:BAAANQAECgQIBgAAAA==.',
Ki='Kiamara:BAAANQADCggIGgAAAA==.Kinderlin:BAAANQAECgUICQAAAA==.Kirbun:BAAANQAECgYIDQAAAA==.Kizchaos:BAAANQADCgQIBAAAAA==.',
Ko='Komurash:BAAANQAECgIIAgAAAA==.Korstruck:BAAANQAECgEIAQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQAAAA==.',
La='Lancaban:BAAANQADCgYIEQAAAQ==.',
Le='Lethalarrow:BAAANQADCgUIBQAAAA==.Lewisr:BAAANQAECgMIAwAAAA==.',
Li='Ligahoo:BAAANQADCggIDwAAAA==.',
Lo='Lorryanne:BAAANQAECgYIEgAAAA==.',
Lu='Lucianas:BAAANQADCgYIBgAAAA==.',
Ly='Lysi:BAAANQADCggIGgAAAA==.',
Ma='Madaea:BAAANQAECgYIDAAAAA==.Madameuyen:BAAANQADCgUIBwAAAA==.Magepuppy:BAAANQAECgQIBQABNQAECgcIEgADAAAAAA==.Makavalii:BAAANQAECgYIEgAAAA==.Malanimus:BAAANQAECgMIAwAAAA==.Malholis:BAAANQADCggIGwAAAA==.Matagi:BAAANQAECgMIBQAAAA==.Mate:BAAANQADCgUIBQABNQADCggIFgADAAAAAA==.',
Me='Meeseks:BAAANQAECgUICQAAAA==.Megabyte:BAAANQAECgQIBAAAAA==.Melbeast:BAAANQADCggIGQAAAA==.Melorea:BAAANQADCgIIAgAAAA==.Merdin:BAAANQAECgMIBgAAAA==.Methmartion:BAAANQAECgEIAQAAAA==.',
Mi='Mish:BAAANQADCgUIBQAAAA==.Missiah:BAAANQAECgQIBgAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAAANQAECgMIAwAAAA==.Moonlilly:BAAANQADCggIGgAAAA==.Mopp:BAAANQADCgYIBgAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgMIAwAAAA==.',
Mu='Mugatoo:BAAANQADCggIDgAAAA==.',
Mx='Mxtemlen:BAAANQADCgUICgABNQAECgQICQADAAAAAA==.',
My='Mylilhunter:BAAANQAECgIIAgAAAA==.Myrtheli:BAAANQADCggICAAAAA==.Mysticx:BAAANQADCggICAAAAA==.',
Na='Nachtelf:BAAANQAECgYICgAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAAANQAECgYICgAAAA==.Nathel:BAAANQAECgEIAQAAAA==.',
Ni='Nirra:BAAANQADCgQIBAAAAA==.',
No='Noctis:BAAANQAECgQIBQAAAA==.Notoriginal:BAAANQADCgcIBwAAAA==.Novatron:BAAANQADCggIDgAAAA==.',
Nu='Nuked:BAAANQAECgUIDAAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQABCgcIBwAAAA==.',
Og='Ograskygazer:BAAANQADCggIGgAAAA==.',
Om='Omee:BAAANQADCggIGgAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQAECgEIAQAAAA==.Orioncheats:BAAANQAECgQICQAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAAANQADCggIFwAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQAAAA==.Pedarias:BAAANQAECgQICAAAAA==.Peon:BAAANQADCgcIDgAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAAANQAECgIIAwAAAA==.Phredrick:BAAANQAECgEIAQAAAA==.',
Pi='Picklebosh:BAABNQAECoEYAAICAAkJbSFCBwB3AwACAAkJbSFCBwB3AwAAAA==.Piemanninty:BAAANQAECgIIAwAAAA==.',
Pl='Plandemic:BAAANQADCgcIBwAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQADCgQIBAADAAAAAA==.Pokerface:BAAANQABCgYICAAAAA==.',
Pr='Precious:BAAANQADCggIDwABNQAFFAQIBAADAAAAAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qu='Quattro:BAAANQAECgEIAQAAAA==.',
Ra='Racecar:BAAANQAECgEIAQAAAA==.Raezil:BAAANQAECgQICQABNQAECgUICwADAAAAAA==.Raivyn:BAAANQAECgYICwAAAA==.Rathmora:BAAANQABCggICwAAAA==.Raylaira:BAAANQADCgYIEAABNQADCgYIEQADAAAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Remnants:BAAANQADCggIEwAAAA==.Renard:BAAANQAECgQICQAAAA==.Reposado:BAAANQADCgYIBgAAAA==.Revelare:BAAANQAECgIIAwAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQADCgYIDAAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAAANQAECgIIAwAAAA==.',
Ro='Robberttrest:BAAANQAECgMIBQAAAA==.Rockyhunterr:BAAANQAECgYIDwAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockywarrior:BAAANQADCgYICgAAAA==.Rooth:BAAANQADCggIEAAAAA==.Roryn:BAAANQAECggIEgAAAA==.',
Ru='Rubï:BAAANQAECgMIAwAAAA==.Rugiaas:BAABNQAECoEhAAMGAAkJ+SQdAQDGAwAGAAkJ+SQdAQDGAwAHAAEJhSEsywBhAAAAAA==.Rugian:BAAANQADCgQIBAABNQAECgkJIQAGAPkkAA==.',
Ry='Ryuka:BAAANQAECgQIBQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgUICwADAAAAAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgADAAAAAA==.Samyria:BAAANQADCgQIBAAAAA==.Satyaru:BAAANQAECgQICAAAAA==.Saucy:BAAANQADCggIEAAAAA==.',
Se='Sedona:BAAANQADCggIDAAAAA==.Selarra:BAAANQAECgMIBAAAAA==.Seric:BAAANQAECgQIBwAAAA==.Sethuriel:BAAANQAECgQIBwAAAA==.',
Sh='Shockadelica:BAAANQADCgYIBgAAAA==.',
Sm='Smartfood:BAAANQADCggIFQAAAA==.Smoochybooty:BAAANQAECgEIAQAAAA==.',
So='Solnar:BAAANQAECgQICQAAAA==.',
Sp='Splashdaddy:BAABNQAECoEcAAIBAAkJvB6UCAAwAwABAAkJvB6UCAAwAwABNQADCgYIDwADAAAAAA==.Spoiled:BAAANQADCggICAABNQAFFAQIBAADAAAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQADCggIGgAAAA==.Stormieskye:BAAANQAECgQICAAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Suzume:BAAANQAECgQIBAABNQAFFAUICAABAJ4bAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQADCggIGwAAAA==.',
Ta='Taea:BAAANQADCggIGgAAAA==.Taeus:BAAANQAECgQIBgAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAAANQAECgYIDAAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Teratrendera:BAAANQAECgEIAQAAAA==.Teron:BAAANQAECgIIAgAAAA==.Tesx:BAAANQADCgYICQAAAA==.',
Th='Thavis:BAAANQAECgIIAgAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAAANQADCggICAAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgYIBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAAANQAECgQIBgAAAA==.Tinkr:BAAANQAECgUIBgAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Tom:BAAANQAECgUIBgABNQAECgUICwADAAAAAA==.Torrey:BAAANQAECgQIBgAAAA==.Totemsareus:BAAANQAECgUICwAAAA==.Toxx:BAAANQADCgYIBgAAAA==.',
Tr='Tradd:BAAANQAECgcIEgAAAA==.Trallor:BAAANQAECgMIBAAAAA==.Trhall:BAAANQADCgUIBwAAAA==.Tristyana:BAAANQAECgYICgAAAA==.',
Ts='Tsiddahn:BAAANQAECgYICgAAAA==.Tsunâde:BAAANQAECgYIBwAAAA==.',
Ty='Tylurien:BAAANQAECgIIAwAAAA==.Tyrael:BAAANQADCggIFgAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQADCgYICgAAAA==.',
Ur='Urbanprey:BAAANQAECgIIBAAAAA==.',
Va='Valenhi:BAAANQADCgQICgAAAA==.Valora:BAAANQAECgYICgAAAA==.Valoria:BAAANQADCgYIBgAAAA==.Vanille:BAAANQADCggIEAAAAA==.Vargen:BAAANQADCggIDwAAAA==.Varonika:BAAANQADCgcIBwAAAA==.Vayla:BAAANQAECgYICwAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQADCgUIBwAAAA==.Vegasducks:BAAANQAECgEIAQAAAA==.Velara:BAAANQADCgQIAwAAAA==.Velithara:BAAANQADCgYIBgAAAA==.',
Vi='Violet:BAAANQADCggIFAAAAA==.',
Wa='Warfise:BAAANQADCgcIDQAAAA==.Warspriest:BAAANQAECgIIAwAAAA==.Warwizard:BAABNQAECoEUAAIGAAgJcx2READfAgAGAAgJcx2READfAgAAAA==.',
Wd='Wdemperor:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Wi='Wickerchickn:BAAANQAECgMIAwAAAA==.Wilshammy:BAAANQADCgQICAAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAAANQAECgYIDgAAAA==.',
Wr='Wrathchoi:BAAANQADCgIIAQAAAA==.Wrathstorm:BAAANQAECgUICgAAAA==.',
Ya='Yazahk:BAAANQADCggIFQABNQADCgYIBAADAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFIEHAAIIAAUJjB2ZAgC8AQAIAAUJjB2ZAgC8AQA1AAQKgRoAAggACQnwIFIIADQDAAgACQnwIFIIADQDAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQADCgYIBAAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgIIBAAAAA==.Zeva:BAAANQADCggIGwAAAA==.',
Zo='Zonzmik:BAAANQABCgYIBAAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgIIAgABNQADCgYIEQADAAAAAA==.',
Zu='Zurazaee:BAAANQAECgEIAQAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAAANQAECgYICgAAAA==.',
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
