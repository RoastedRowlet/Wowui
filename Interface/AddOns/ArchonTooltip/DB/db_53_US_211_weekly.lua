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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abysslicker:BAAANQADCgcIDAAAAA==.',
Ac='Achooe:BAAANQADCggIDgAAAA==.',
Ad='Ado:BAAANQADCgcIDQAAAA==.Adversity:BAAANQAECgEIAQAAAA==.',
Ae='Aegeus:BAAANQADCggICAAAAA==.',
Ai='Aiolii:BAAANQADCgUIBwAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Alyndrya:BAAANQAECgEIAQAAAA==.',
Am='Amithralia:BAAANQADCggIDgAAAA==.',
An='Ankari:BAAANQADCgEIAQAAAA==.Anzarna:BAAANQADCgQIBQABNQADCgQIBQABAAAAAA==.',
Ao='Aohikari:BAAANQADCgUIBQABNQAECggIEAABAAAAAA==.',
Ap='Aprigity:BAAANQADCgcIDQAAAA==.',
Aq='Aquaten:BAAANQADCgYICgAAAA==.',
Ar='Arashinigon:BAAANQADCggIDgAAAA==.Arceus:BAAANQADCgYICQAAAA==.Ark:BAAANQAECgMIBAAAAA==.',
Au='Aunn:BAAANQADCgYIBQAAAA==.Aureia:BAAANQADCgYIBwAAAA==.',
Ax='Axon:BAAANQADCggIDQAAAA==.',
Ba='Baaku:BAAANQADCgYIDAAAAA==.Baelhay:BAAANQADCgYICgAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAAANQAECgIIAgAAAA==.Battlebot:BAAANQABCgIIAgAAAA==.',
Be='Beet:BAAANQADCgYICwAAAA==.Belgaron:BAAANQABCgEIAQABNQAECgEIAQABAAAAAA==.Belitha:BAAANQAECgIIAgAAAA==.Belmaris:BAAANQADCggIDgAAAA==.Benevolence:BAAANQADCgIIAgAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQADCgYICQAAAA==.Bigdruid:BAAANQADCgcIBwAAAA==.Bimbosuzi:BAAANQADCgcIDQAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAAANQADCggIDgAAAA==.Bluegrass:BAAANQADCgcIDgAAAA==.',
Bo='Borc:BAAANQADCgUIBgAAAA==.Borik:BAAANQADCggICAAAAA==.Borknagar:BAAANQADCgQIBAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.Brighteye:BAAANQADCgMIAwAAAA==.Brisket:BAAANQADCgYICwAAAA==.',
Bu='Bubblebut:BAAANQADCgYICwAAAA==.Buckme:BAAANQAECgEIAQAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAIIAgABAAAAAA==.Busen:BAAANQADCgQIAwAAAA==.',
['Bà']='Bàal:BAAANQADCgYIBwABNQAECgMIBAABAAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQADCgcICwAAAA==.Caralhan:BAAANQADCgYICQAAAA==.',
Ce='Cedra:BAAANQAECgYICwAAAA==.Cegeo:BAAANQADCgcIDgAAAA==.',
Ch='Cheepdeeps:BAAANQADCgcIDgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Cirdle:BAAANQADCgcIDAAAAA==.',
Co='Cobalt:BAAANQAECgQIBAAAAA==.Coolkid:BAAANQAECgEIAQAAAA==.Corntard:BAAANQADCgcICgAAAA==.',
Cr='Crazynlazy:BAAANQADCggIDgAAAA==.Crucifixea:BAAANQADCgcIBgAAAA==.Crystyl:BAAANQADCgYICwAAAA==.',
Cy='Cymoril:BAAANQADCgcIBwAAAA==.',
Da='Daddy:BAAANQAECgEIAQAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgEIAQAAAA==.Dalmin:BAAANQADCggICAAAAA==.Darkcarnival:BAAANQADCggIDgAAAA==.Dasnotgood:BAAANQADCgcICwAAAA==.',
De='Deemon:BAAANQADCgcIBwAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Denevien:BAAANQADCgYICQAAAA==.Desdemona:BAAANQADCgYICwAAAA==.Dethiaris:BAAANQADCggICAAAAA==.',
Di='Diablojr:BAAANQAECgIIAwAAAA==.Dianimal:BAAANQADCggIDgAAAA==.Distroya:BAAANQADCgYICwAAAA==.',
Do='Doomace:BAAANQAECgEIAQAAAA==.',
Dr='Draaka:BAAANQADCgQIBAAAAA==.Dragon:BAAANQADCggIDAAAAA==.Driftyshaman:BAAANQADCgQIBAAAAA==.Dræghoule:BAAANQADCgYIBQAAAA==.',
Du='Durnik:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.',
Dw='Dworflundgrn:BAAANQADCgcIDQAAAA==.',
Dy='Dyamí:BAAANQAECgEIAQAAAA==.',
['Dá']='Dánte:BAAANQADCgcIDQAAAA==.',
Eg='Eglosira:BAAANQADCgIIAgAAAA==.',
El='Elbuhero:BAAANQAECgMIAwAAAA==.Electric:BAAANQABCgMIAgAAAA==.Elementstone:BAAANQADCgQICAAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAAANQADCggICQAAAA==.Elrythe:BAAANQAECgQIBAAAAA==.',
Fe='Felebash:BAAANQADCgYIBgAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.',
Fi='Fistdaddy:BAAANQADCgYICwAAAA==.',
Fl='Floofies:BAAANQAECgUIBgAAAA==.',
Fu='Furcas:BAAANQADCgMIAwAAAA==.Furrglur:BAAANQADCgIIAgABNQAECgUIBgABAAAAAA==.Furrylight:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Furryphase:BAAANQAECgQIBQAAAA==.',
Ga='Galnier:BAAANQADCgcIDQAAAA==.',
Gh='Ghosted:BAAANQADCggIDAAAAA==.',
Gl='Glaur:BAAANQADCggIDwAAAA==.',
Gu='Gunslingr:BAAANQADCgcIBwAAAA==.',
Ha='Hairyjolene:BAAANQADCgYICgAAAA==.Handsome:BAAANQADCgYIBgAAAA==.',
He='Headpats:BAAANQADCgUIBQAAAA==.Hearthisrdy:BAAANQADCggIDgAAAA==.Helmshammer:BAAANQADCggIAQAAAA==.Hexwhisper:BAAANQADCgUIBQAAAA==.Heycarlos:BAAANQAECgQIBQAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAECggIEAABAAAAAA==.Hikarishaman:BAAANQAECggIEAAAAA==.Hime:BAAANQADCggIDgAAAA==.',
Ho='Holyblimblam:BAAANQADCgcIDQAAAA==.Honeypieheal:BAAANQADCgEIAQAAAA==.Horabad:BAAANQAECgEIAQAAAA==.Hosemachine:BAAANQADCgUIBwAAAA==.',
Hu='Hulksmasher:BAAANQADCgcICwAAAA==.Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQADCgcIDAAAAA==.Hèrifire:BAAANQADCgQIBAAAAA==.',
Ih='Ihalo:BAAANQADCgYICgAAAA==.',
Il='Illinesh:BAAANQADCgYICAAAAA==.',
Ja='Jadienne:BAAANQADCgcIBwAAAA==.Jameson:BAAANQADCgYICQAAAA==.Jasmind:BAAANQADCgQIAQAAAA==.',
Ji='Jiwà:BAAANQAECgYICQAAAA==.',
Jo='Joshjb:BAAANQADCgcICQAAAA==.',
Ka='Kaguro:BAAANQADCgQIBAAAAA==.Kakwaa:BAAANQADCggIDQAAAA==.Kaliyah:BAAANQADCggICAAAAA==.',
Ke='Keyadistor:BAAANQADCggICAAAAA==.',
Kh='Khazabrew:BAAANQAECgEIAQAAAA==.',
Ki='Kiamara:BAAANQADCgYICwAAAA==.Kinderlin:BAAANQADCgYIDgAAAA==.Kirbun:BAAANQAECgEIAgAAAA==.Kizchaos:BAAANQADCgMIAwAAAA==.',
Ko='Komurash:BAAANQADCgcICwAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Ku='Kungbrew:BAAANQADCgYICgAAAA==.',
La='Lancaban:BAAANQADCgQIBQAAAQ==.',
Li='Ligahoo:BAAANQADCgYICQAAAA==.',
Lo='Lorryanne:BAAANQAECgQIBgAAAA==.',
Lu='Lucianas:BAAANQADCgQIBQAAAA==.',
Ly='Lysi:BAAANQADCgYICgAAAA==.',
Ma='Madaea:BAAANQAECgIIAgAAAA==.Madameuyen:BAAANQADCgUIBwAAAA==.Magepuppy:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Makavalii:BAAANQADCggIFQAAAA==.Malholis:BAAANQADCgcIDAAAAA==.Matagi:BAAANQAECgEIAQAAAA==.',
Me='Meeseks:BAAANQAECgEIAQAAAA==.Megabyte:BAAANQADCgYIBQAAAA==.Melbeast:BAAANQADCgYICgAAAA==.Melorea:BAAANQADCgEIAQAAAA==.Merdin:BAAANQADCgYIBgAAAA==.Methmartion:BAAANQADCgYICgAAAA==.',
Mi='Missiah:BAAANQADCgcIBgAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIIAgAAAA==.Moonfell:BAAANQADCggICQAAAA==.Moonlilly:BAAANQADCgYICwAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQADCgYIBgAAAA==.',
Mx='Mxtemlen:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
My='Mysticx:BAAANQABCgQIBAAAAA==.',
Na='Nachtelf:BAAANQADCgcIDgAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAAANQADCgcIDgAAAA==.Nathel:BAAANQADCgYICgAAAA==.Naughty:BAAANQADCggICAAAAA==.',
Ni='Nirra:BAAANQADCgQIBAAAAA==.',
No='Notoriginal:BAAANQADCgcIBwAAAA==.Novatron:BAAANQADCgYIBgAAAA==.',
Nu='Nuked:BAAANQAECgMIAwAAAA==.',
Og='Ograskygazer:BAAANQADCgYICgAAAA==.',
Om='Omee:BAAANQADCgYICwAAAA==.',
On='Onlyshrimps:BAAANQADCgUIBQAAAA==.',
Or='Oralena:BAAANQADCgYICgAAAA==.Orioncheats:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAAANQADCgcIDQAAAA==.',
Pe='Ped:BAAANQAECgEIAQAAAA==.Peon:BAAANQADCgYICQAAAA==.Perstephanie:BAAANQABCgIIAgAAAA==.',
Ph='Pharune:BAAANQADCggIDgAAAA==.Phredrick:BAAANQAECgEIAQAAAA==.',
Pi='Picklebosh:BAAANQAECgMIBgAAAA==.Piemanninty:BAAANQAECgIIAgAAAA==.',
Po='Pokerface:BAAANQABCgIIBAAAAA==.',
Pr='Precious:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
Qu='Quattro:BAAANQADCgcIDQAAAA==.',
Ra='Raezil:BAAANQAECgMIBAAAAA==.Raivyn:BAAANQAECgEIAQAAAA==.Raylaira:BAAANQADCgQIBQAAAA==.',
Re='Remnants:BAAANQADCgcIBwAAAA==.Renard:BAAANQAECgEIAQAAAA==.Revelare:BAAANQADCgcIDAAAAA==.Rexbie:BAAANQAECgIIAgAAAA==.',
Rh='Rhylee:BAAANQADCgUIBQAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAAANQADCgcIDQAAAA==.',
Ro='Robberttrest:BAAANQAECgEIAQAAAA==.Rockyhunterr:BAAANQAECgQIBAAAAA==.Rooth:BAAANQADCgEIAQAAAA==.Roryn:BAAANQAECgIIAgAAAA==.',
Ru='Rubï:BAAANQADCgIIAgAAAA==.Rugiaas:BAAANQAECgcIDQAAAA==.',
Ry='Ryuka:BAAANQADCgcIDAAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQADCgYIDAABAAAAAA==.Samyria:BAAANQABCgIIAwAAAA==.Satyaru:BAAANQAECgEIAQAAAA==.',
Se='Sedona:BAAANQADCgMIBAAAAA==.Selarra:BAAANQADCggIEAAAAA==.Seric:BAAANQADCggIDAAAAA==.Sethuriel:BAAANQADCgYIDgAAAA==.',
Sh='Shockadelica:BAAANQADCgYIBgAAAA==.',
Sm='Smartfood:BAAANQADCgUIBQAAAA==.Smoochybooty:BAAANQAECgEIAQAAAA==.',
So='Solnar:BAAANQAECgEIAQAAAA==.',
Sp='Splashdaddy:BAAANQAECgcIDQABNQADCgYICwABAAAAAA==.Spoiled:BAAANQADCggICAABNQADCggICAABAAAAAA==.',
St='Staks:BAAANQADCgcIDgAAAA==.Starii:BAAANQADCgYICwAAAA==.Stormieskye:BAAANQAECgEIAQAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQADCgcIDAAAAA==.',
Ta='Taea:BAAANQADCgcIDAAAAA==.Taeus:BAAANQAECgEIAQAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAAANQAECgEIAQAAAA==.',
Te='Teratrendera:BAAANQADCgUICQAAAA==.Teron:BAAANQADCggICQAAAA==.',
Th='Thetimelord:BAAANQADCgYIBgAAAA==.',
Ti='Tinkr:BAAANQADCggIDgAAAA==.',
To='Torrey:BAAANQAECgEIAQAAAA==.Totemsareus:BAAANQAECgEIAQAAAA==.',
Tr='Tradd:BAAANQAECgQIBQAAAA==.Trallor:BAAANQADCgcICgAAAA==.Trhall:BAAANQADCgUIBwAAAA==.Tristyana:BAAANQADCgcIDgAAAA==.',
Ts='Tsiddahn:BAAANQAECgIIAgAAAA==.Tsunâde:BAAANQADCgcIDgAAAA==.',
Ty='Tylurien:BAAANQADCggIDgAAAA==.Tyrael:BAAANQADCgcIDQAAAA==.',
Ur='Urbanprey:BAAANQADCggICAAAAA==.',
Va='Valenhi:BAAANQADCgIIAgAAAA==.Valora:BAAANQADCgcIDgAAAA==.Vanille:BAAANQADCgYICgAAAA==.Vayla:BAAANQAECgEIAQAAAA==.',
Ve='Vedik:BAAANQADCgUIBQAAAA==.Vegasducks:BAAANQADCgYICAAAAA==.Velara:BAAANQADCgMIAgAAAA==.Velithara:BAAANQADCgYIBgAAAA==.',
Vi='Violet:BAAANQADCgYICgAAAA==.',
Wa='Warfise:BAAANQADCgYIBgAAAA==.Warspriest:BAAANQADCggIDgAAAA==.Warwizard:BAAANQAFFAEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEIAQAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Wi='Wickerchickn:BAAANQADCggIDQAAAA==.',
Wo='Wonkyponky:BAAANQAECgMIAwAAAA==.',
Wr='Wrathchoi:BAAANQADCgIIAQAAAA==.Wrathstorm:BAAANQAECgEIAQAAAA==.',
Ya='Yazahk:BAAANQADCggIDwABNQADCgQIBAABAAAAAA==.Yazjani:BAAANQABCgIIAQAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.',
Ye='Yezgraine:BAAANQAECggIDAAAAA==.',
Yz='Yzaak:BAAANQADCgQIBAAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgEIAQAAAA==.Zeva:BAAANQADCgcIDAAAAA==.',
Zo='Zorrokiller:BAAANQADCgQIBAAAAA==.',
Zu='Zurazaee:BAAANQADCgYICgAAAA==.',
['Él']='Élle:BAAANQADCgYIBwAAAA==.',
['Ér']='Éric:BAAANQADCgcIDgAAAA==.',
['Ïr']='Ïridescent:BAAANQADCggIDgAAAA==.',
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
