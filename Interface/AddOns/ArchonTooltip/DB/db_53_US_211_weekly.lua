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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Warlock-Destruction','Shaman-Elemental','Paladin-Holy','DeathKnight-Blood',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abysslicker:BAAANQADCgcIDAAAAA==.',
Ac='Achooe:BAAANQAECgEIAQAAAA==.',
Ad='Ado:BAAANQAECgEIAQAAAA==.Adversity:BAAANQAECgEIAQAAAA==.',
Ae='Aegeus:BAAANQADCggICQAAAA==.',
Ai='Aiolii:BAAANQADCgUIBwAAAA==.',
Ak='Akiras:BAAANQABCgMIAwAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Alyndrya:BAAANQAECgQIBQAAAA==.',
Am='Amithralia:BAAANQAECgIIAgAAAA==.',
An='Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQADCgYIBgAAAA==.Anzarna:BAAANQADCgYICwABNQADCgYICwABAAAAAA==.',
Ao='Aohikari:BAAANQAECgIIAgABNQAECgkJHQACAKIbAA==.',
Ap='Aprigity:BAAANQAECgEIAQAAAA==.',
Aq='Aquaten:BAAANQADCggIEgAAAA==.',
Ar='Arashinigon:BAAANQAECgMIAwAAAA==.Arceus:BAAANQADCgYICQAAAA==.Ark:BAAANQAFFAEIAQAAAA==.',
Au='Aunn:BAAANQAECgYIBgAAAA==.Aureia:BAAANQADCgcIDQAAAA==.',
Ax='Axon:BAAANQAECgMIAwAAAA==.',
Ba='Baaku:BAAANQAECgIIAgAAAA==.Baelhay:BAAANQADCggIEgAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAAANQAECgQIBgAAAA==.Battlebot:BAAANQADCggICAAAAA==.',
Be='Beet:BAAANQADCgcIEgAAAA==.Belgaron:BAAANQABCgEIAQABNQAECgQIBQABAAAAAA==.Belitha:BAAANQAECgQIBgAAAA==.Belmaris:BAAANQAECgEIAQAAAA==.Benevolence:BAAANQADCgIIAgAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQADCgcIEAAAAA==.Bigdruid:BAAANQAECgEIAQAAAA==.Bimbosuzi:BAAANQAECgIIAgAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAAANQAECgIIAgAAAA==.Bluegrass:BAAANQAECgQIBAAAAA==.',
Bo='Borc:BAAANQADCgUICwAAAA==.Borik:BAAANQAECgMIAwAAAA==.Borknagar:BAAANQADCgQIBAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.Brighteye:BAAANQADCggICgAAAA==.Brisket:BAAANQADCgcIEgAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAAANQADCgYICwAAAA==.Bubbs:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Buckme:BAAANQAECgUIBgAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAUIBwADAFEeAA==.Busen:BAAANQADCgMIAwAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAAANQADCggIDgABNQAECgUIBQABAAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQADCgcIEgAAAA==.Caralhan:BAAANQADCgcIEAAAAA==.',
Ce='Cedra:BAAANQAECgYIDwAAAA==.Cegeo:BAAANQAECgQIBAAAAA==.Celari:BAAANQAECgEIAQAAAA==.',
Ch='Cheepdeeps:BAAANQAECgQIBAAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Cirdle:BAAANQAECgEIAQAAAA==.',
Co='Cobalt:BAAANQAECgYICgAAAA==.Coolkid:BAAANQAECgEIAQAAAA==.Corntard:BAAANQADCgcIEAAAAA==.',
Cr='Crazynlazy:BAAANQAECgIIAgAAAA==.Crucifixea:BAAANQADCgYIDAAAAA==.Crystyl:BAAANQADCgcIEgAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwAAAA==.',
Cy='Cymoril:BAAANQAECgYIBAAAAA==.',
Da='Daddy:BAAANQAECgEIAgAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBQAAAA==.Dalmin:BAAANQADCggICAAAAA==.Darkcarnival:BAAANQAECgEIAQAAAA==.Dasnotgood:BAAANQADCgcIDQAAAA==.',
De='Deemon:BAAANQAECgEIAQAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Denard:BAAANQADCgQIBAABNQADCgcIEgABAAAAAA==.Denevien:BAAANQADCgYIDwAAAA==.Desdemona:BAAANQADCgcIEgAAAA==.Dethiaris:BAAANQAECgIIAgAAAA==.',
Di='Diablojr:BAAANQAECgUICAAAAA==.Dianimal:BAAANQADCggIFAAAAA==.Distroya:BAAANQADCgcIEgAAAA==.',
Do='Doomace:BAAANQAECgYIBwAAAA==.',
Dr='Draaka:BAAANQADCgQIBAAAAA==.Dragon:BAAANQADCggIDAAAAA==.Driftyshaman:BAAANQADCgYICgAAAA==.Dræghoule:BAAANQADCgcIDAAAAA==.',
Du='Durnik:BAAANQADCgcIEgABNQAECgQIBQABAAAAAA==.',
Dw='Dworflundgrn:BAAANQADCgcIDQAAAA==.',
Dy='Dyamí:BAAANQAECgEIAgAAAA==.',
['Dá']='Dánte:BAAANQADCgcIDQAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAAANQAECgUICAAAAA==.Eldiablo:BAAANQADCgMIAwAAAA==.Electric:BAAANQADCgIIAgAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAAANQAECgQIBAAAAA==.Elrythe:BAAANQAECgYIBgAAAA==.',
Fe='Felebash:BAAANQADCgcIDQAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.',
Fi='Fistdaddy:BAAANQADCgYIDwAAAA==.',
Fl='Floofies:BAAANQAECgYIDAAAAA==.Floofthulu:BAAANQADCggICAAAAA==.Fluffalo:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.',
Fu='Furcas:BAAANQADCgMIAwAAAA==.Furrglur:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Furrylight:BAAANQAECgEIAQABNQAECgcICgABAAAAAA==.Furryphase:BAAANQAECgcICgAAAA==.',
Ga='Galnier:BAAANQAECgEIAQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQADCggIEQAAAA==.',
Gl='Glaur:BAAANQAECgQIBAAAAA==.',
Gr='Gripisrdy:BAAANQAECgEIAQAAAA==.',
Gu='Gunslingr:BAAANQAECgUIBQAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAAANQAECgIIAgAAAA==.',
He='Headpats:BAAANQAECgcIBgABNQAECgcIBwABAAAAAA==.Hearthisrdy:BAAANQADCggIDgAAAA==.Hexwhisper:BAAANQADCgUIBQAAAA==.Heycarlos:BAAANQAECgUICgAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAECgkJHQACAKIbAA==.Hikarishaman:BAABNQAECoEdAAMCAAkJohtdDwCfAgACAAkJohtdDwCfAgAEAAcJbBlIGwA6AgAAAA==.Hime:BAAANQAECgEIAQAAAA==.',
Ho='Holyblimblam:BAAANQAECgEIAQAAAA==.Honeypieheal:BAAANQADCgEIAQAAAA==.Horabad:BAAANQAECgEIAQAAAA==.Hosemachine:BAAANQAECgUIBQAAAA==.',
Hu='Hulksmasher:BAAANQADCgcIEgAAAA==.Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQADCgcIDAAAAA==.Hèrifire:BAAANQADCgcICwAAAA==.',
Ih='Ihalo:BAAANQADCggIEwAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgMIAwAAAA==.',
Ja='Jadde:BAAANQABCgMIAwAAAA==.Jadienne:BAAANQAECgQIBAAAAA==.Jameson:BAAANQADCggIDAAAAA==.Jasmind:BAAANQADCgcIBQAAAA==.',
Ji='Jiwà:BAAANQAECgcIEAAAAA==.',
Jo='Joshjb:BAAANQADCgcICQAAAA==.',
Ka='Kaguro:BAAANQADCggIDAAAAA==.Kahless:BAAANQADCgEIAQAAAA==.Kakwaa:BAAANQADCggIDQAAAA==.Kaliyah:BAAANQAECgIIAgAAAA==.',
Ke='Keyadistor:BAAANQAECgMIAwAAAA==.',
Kh='Khazabrew:BAAANQAECgEIAgAAAA==.',
Ki='Kiamara:BAAANQADCgcIEgAAAA==.Kinderlin:BAAANQAECgQIBAAAAA==.Kirbun:BAAANQAECgUIBwAAAA==.Kizchaos:BAAANQADCgQIBAAAAA==.',
Ko='Komurash:BAAANQADCggIFAAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Ku='Kungbrew:BAAANQADCggIEgAAAA==.',
La='Lancaban:BAAANQADCgYICwAAAQ==.',
Li='Ligahoo:BAAANQADCgcICwAAAA==.',
Lo='Lorryanne:BAAANQAECgYIDAAAAA==.',
Lu='Lucianas:BAAANQADCgUIBQAAAA==.',
Ly='Lysi:BAAANQADCggIEgAAAA==.',
Ma='Madaea:BAAANQAECgQIBgAAAA==.Madameuyen:BAAANQADCgUIBwAAAA==.Magepuppy:BAAANQAECgQIBQABNQAECgYICwABAAAAAA==.Makavalii:BAAANQAECgQIBgAAAA==.Malanimus:BAAANQADCggICAAAAA==.Malholis:BAAANQADCgcIEwAAAA==.Matagi:BAAANQAECgEIAgAAAA==.',
Me='Meeseks:BAAANQAECgMIBAAAAA==.Megabyte:BAAANQAECgQIBAAAAA==.Melbeast:BAAANQADCgcIEQAAAA==.Melorea:BAAANQADCgIIAgAAAA==.Merdin:BAAANQAECgMIAwAAAA==.Methmartion:BAAANQADCggIEgAAAA==.',
Mi='Mish:BAAANQADCgUIBQAAAA==.Missiah:BAAANQAECgIIAgAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAAANQADCggIDAAAAA==.Moonlilly:BAAANQADCgcIEgAAAA==.Mopp:BAAANQADCgYIBgAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgMIAwAAAA==.',
Mu='Mugatoo:BAAANQADCggICAAAAA==.',
Mx='Mxtemlen:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
My='Mylilhunter:BAAANQADCggICAAAAA==.Mysticx:BAAANQADCggICAAAAA==.',
Na='Nachtelf:BAAANQAECgQIBAAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAAANQAECgQIBAAAAA==.Nathel:BAAANQADCggIEgAAAA==.Naughty:BAAANQADCggICAAAAA==.',
Ni='Nirra:BAAANQADCgQIBAAAAA==.',
No='Noctis:BAAANQAECgEIAQAAAA==.Notoriginal:BAAANQADCgcIBwAAAA==.Novatron:BAAANQADCggIDgAAAA==.',
Nu='Nuked:BAAANQAECgUICAAAAA==.',
Od='Odor:BAAANQABCgMIAwAAAA==.',
Og='Ograskygazer:BAAANQADCggIEgAAAA==.',
Om='Omee:BAAANQADCgcIEgAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQADCggIEgAAAA==.Orioncheats:BAAANQAECgQIBQAAAA==.',
Ow='Owo:BAAANQADCggICAAAAA==.',
Ox='Oxygën:BAAANQADCggIDwAAAA==.',
Pa='Paciemac:BAAANQAECgQIBAAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Peon:BAAANQADCgYIDQAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAAANQAECgEIAQAAAA==.Phredrick:BAAANQAECgEIAQAAAA==.',
Pi='Picklebosh:BAAANQAECgYIDAAAAA==.Piemanninty:BAAANQAECgIIAgAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAAAAA==.Pokerface:BAAANQABCgYICAAAAA==.',
Pr='Precious:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qu='Quattro:BAAANQAECgEIAQAAAA==.',
Ra='Raezil:BAAANQAECgQICAABNQAECgUIBQABAAAAAA==.Raivyn:BAAANQAECgQIBQAAAA==.Raylaira:BAAANQADCgYICwAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Remnants:BAAANQADCgcICwAAAA==.Renard:BAAANQAECgQIBQAAAA==.Reposado:BAAANQADCgYIBgAAAA==.Revelare:BAAANQAECgEIAQAAAA==.Rexbie:BAAANQAECgUICAAAAA==.',
Rh='Rhylee:BAAANQADCgYIBwAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAAANQAECgEIAQAAAA==.',
Ro='Robberttrest:BAAANQAECgIIAgAAAA==.Rockyhunterr:BAAANQAECgUICQAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockywarrior:BAAANQADCgYIBgAAAA==.Rooth:BAAANQADCgcICAAAAA==.Roryn:BAAANQAECggICgAAAA==.',
Ru='Rubï:BAAANQAECgEIAQAAAA==.Rugiaas:BAABNQAECoEYAAIFAAkJjiJEAQCuAwAFAAkJjiJEAQCuAwAAAA==.',
Ry='Ryuka:BAAANQAECgEIAQAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgIIAgABAAAAAA==.Samyria:BAAANQADCgQIBAAAAA==.Satyaru:BAAANQAECgMIBAAAAA==.Saucy:BAAANQADCggICAAAAA==.',
Se='Sedona:BAAANQADCgMIBAAAAA==.Selarra:BAAANQAECgEIAQAAAA==.Seric:BAAANQAECgIIAgAAAA==.Sethuriel:BAAANQAECgIIAgAAAA==.',
Sh='Shockadelica:BAAANQADCgYIBgAAAA==.',
Sm='Smartfood:BAAANQADCggIDQAAAA==.Smoochybooty:BAAANQAECgEIAQAAAA==.',
So='Solnar:BAAANQAECgQIBQAAAA==.',
Sp='Splashdaddy:BAABNQAECoEWAAICAAkJlx2+BgAbAwACAAkJlx2+BgAbAwABNQADCgYIDwABAAAAAA==.Spoiled:BAAANQADCggICAABNQADCggICAABAAAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQADCgcIEgAAAA==.Stormieskye:BAAANQAECgMIBAAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Suzume:BAAANQADCgUIBQABNQAECgkJHQACAKIbAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQADCgcIEwAAAA==.',
Ta='Taea:BAAANQADCgcIEgAAAA==.Taeus:BAAANQAECgEIAgAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAAANQAECgUIBgAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Teratrendera:BAAANQADCgcIEAAAAA==.Teron:BAAANQAECgIIAgAAAA==.Tesx:BAAANQADCgEIAQAAAA==.',
Th='Thetimelord:BAAANQAECgIIAgAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQADCgYIBgAAAA==.Tik:BAAANQADCgYIBgAAAA==.Tilted:BAAANQAECgIIAgAAAA==.Tinkr:BAAANQAECgMIAwAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Tom:BAAANQAECgUIBQAAAA==.Torrey:BAAANQAECgQIBQAAAA==.Totemsareus:BAAANQAECgUIBgAAAA==.Toxx:BAAANQADCgYIBgAAAA==.',
Tr='Tradd:BAAANQAECgYICwAAAA==.Trallor:BAAANQAECgEIAQAAAA==.Trhall:BAAANQADCgUIBwAAAA==.Tristyana:BAAANQAECgQIBAAAAA==.',
Ts='Tsiddahn:BAAANQAECgMIBAAAAA==.Tsunâde:BAAANQAECgEIAQAAAA==.',
Ty='Tylurien:BAAANQAECgEIAQAAAA==.Tyrael:BAAANQADCggIDgAAAA==.',
Ul='Ulangi:BAAANQADCgYIBgAAAA==.',
Ur='Urbanprey:BAAANQAECgIIAgAAAA==.',
Va='Valenhi:BAAANQADCgMIBgAAAA==.Valora:BAAANQAECgQIBAAAAA==.Valoria:BAAANQADCgYIBgAAAA==.Vanille:BAAANQADCggIDwAAAA==.Vargen:BAAANQADCgcIBwAAAA==.Varonika:BAAANQABCgEIAQAAAA==.Vayla:BAAANQAECgQIBQAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQADCgUIBwAAAA==.Vegasducks:BAAANQADCgcIDwAAAA==.Velara:BAAANQADCgMIAgAAAA==.Velithara:BAAANQADCgYIBgAAAA==.',
Vi='Violet:BAAANQADCgcIEQAAAA==.',
Wa='Warfise:BAAANQADCgcIDQAAAA==.Warspriest:BAAANQAECgEIAQAAAA==.Warwizard:BAAANQAFFAEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Wi='Wickerchickn:BAAANQADCggIDQAAAA==.Wilshammy:BAAANQADCgQIBAAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAAANQAECgUICAAAAA==.',
Wr='Wrathchoi:BAAANQADCgIIAQAAAA==.Wrathstorm:BAAANQAECgQIBQAAAA==.',
Ya='Yazahk:BAAANQADCggIEQABNQADCgYIBAABAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazwynn:BAAANQADCgcICAAAAA==.',
Ye='Yezgraine:BAABNQAECoEXAAIGAAkJihphCgDUAgAGAAkJihphCgDUAgAAAA==.',
Yo='Yookock:BAAANQADCggICAAAAA==.',
Yz='Yzaak:BAAANQADCgYIBAAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgEIAgAAAA==.Zeva:BAAANQADCgcIEwAAAA==.',
Zo='Zonzmik:BAAANQABCgMIAQAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.',
Zu='Zurazaee:BAAANQADCggIEgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAAANQAECgQIBAAAAA==.',
['Ïr']='Ïridescent:BAAANQADCggIFQAAAA==.',
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
