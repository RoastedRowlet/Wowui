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

local lookup = {'DemonHunter-Devourer','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Druid-Feral','Priest-Holy','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','Warrior-Arms','Monk-Mistweaver','Paladin-Retribution','Druid-Balance','Druid-Restoration','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Paladin-Protection','Mage-Frost','DeathKnight-Blood','Monk-Brewmaster','Warrior-Protection','Priest-Discipline','Priest-Shadow','Druid-Guardian',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abysslicker:BAAANQADCggIFAAAAA==.',
Ac='Achooe:BAAANQAECgUICQAAAA==.',
Ad='Ado:BAAANQAECgIIAwAAAA==.Adversity:BAAANQAFFAIIAwAAAA==.',
Ae='Aegeus:BAAANQADCggICQAAAA==.Aenil:BAAANQADCgMIAwAAAA==.',
Ai='Aiolii:BAAANQAECgMIBgAAAA==.',
Ak='Akiras:BAAANQABCgQICAAAAA==.',
Al='Alcestis:BAAANQADCgIIAgAAAA==.Alyndrya:BAABNQAECoEdAAIBAAgKtg11JADoAQABAAgKtg11JADoAQAAAA==.',
Am='Amithralia:BAAANQAECgYIEQAAAA==.',
An='Anejo:BAAANQADCgYIBgAAAA==.Ankari:BAAANQADCgEIAQAAAA==.Ansdusk:BAAANQADCgcIEgABNQADCggIGQACAAAAAA==.Anzarna:BAAANQADCggIGwABNQADCggIHwACAAAAAA==.',
Ao='Aohikari:BAAANQAECgIIAwABNQAFFAYIEwADAMIXAA==.',
Ap='Aprigity:BAAANQAECgIJAwAAAA==.',
Aq='Aquaten:BAAANQAECgMIBgAAAA==.',
Ar='Arashinigon:BAAANQAECgYIEAAAAA==.Arceus:BAAANQAECgIJAgAAAA==.Arick:BAAANQAECgUICwAAAA==.Ark:BAABNQAECoEtAAMDAAkK+yYFAAAKBAADAAkK+yYFAAAKBAAEAAEKHCSA4ABgAAAAAA==.',
At='Atanker:BAAANQADCgMIAwAAAA==.',
Au='Aunn:BAAANQAECgYICgAAAA==.Aureia:BAAANQAECgMIBQAAAA==.',
Ax='Axon:BAAANQAECgUIDgAAAA==.',
Ba='Baaku:BAAANQAECgQIBgAAAA==.Baelhay:BAAANQAECgMIBgAAAA==.Ballard:BAAANQADCgMIAwAAAA==.Bashon:BAABNQAECoEZAAMDAAcKhhVQVADDAQADAAcKhhVQVADDAQAEAAEK7AG/FwEiAAAAAA==.Battlebot:BAAANQAECgQIBgAAAA==.',
Be='Beet:BAAANQAECgcIEQAAAA==.Belgaron:BAAANQABCgEIAQABNQAECgcIGAAFAIAWAA==.Belitha:BAABNQAECoEYAAIBAAgK9x+qDgDdAgABAAgK9x+qDgDdAgAAAA==.Belmaris:BAAANQAECgYICgAAAA==.Benevolence:BAAANQADCgIIAgAAAA==.Betëlgeuse:BAAANQADCgUICQAAAA==.',
Bi='Bigcupcakes:BAAANQAECgEIAQAAAA==.Bigdruid:BAAANQAECgIIAwABNQAECgQIBAACAAAAAA==.Bimbosuzi:BAAANQAECgUIDAAAAA==.Bingbing:BAAANQADCgQIBAAAAA==.Binghealing:BAAANQADCgEIAQAAAA==.',
Bl='Blasteyes:BAAANQAECgYIEQAAAA==.Bluegrass:BAABNQAECoEYAAIGAAgK6xqLBwCCAgAGAAgK6xqLBwCCAgAAAA==.',
Bo='Borc:BAAANQADCgcIGwAAAA==.Borik:BAAANQAECgYIEgAAAA==.Borknagar:BAAANQADCgcIFAAAAA==.',
Br='Brat:BAAANQADCgcIBwABNQAFFAYIEAAHABoVAA==.Brighteye:BAAANQAECgQIBAAAAA==.Brindis:BAAANQAECgEIAQAAAA==.Brisket:BAAANQADCggIGwAAAA==.Brutalicious:BAAANQADCgIIAgAAAA==.',
Bu='Bubblebut:BAAANQAECgQIBgAAAA==.Bubbs:BAAANQADCgQIBAABNQAECggIFQAFAJkgAA==.Buckme:BAABNQAECoEbAAIIAAgKIBkQOAB+AgAIAAgKIBkQOAB+AgAAAA==.Bunnygirl:BAAANQAECgIIAgABNQAFFAcIEwAJAL4iAA==.Busen:BAAANQADCgYJDgAAAA==.',
By='Byungsoon:BAAANQADCgQIBAAAAA==.',
['Bà']='Bàal:BAABNQAECoEWAAMJAAcKMhADbADDAQAJAAcKMhADbADDAQAKAAEKNxGTZwA9AAAAAA==.',
Ca='Caiphage:BAAANQADCgcIBwAAAA==.Caladelm:BAAANQAECgIIAgAAAA==.Caralhan:BAAANQAECgQIBAAAAA==.Castelo:BAAANQADCggICAAAAA==.',
Ce='Cedra:BAABNQAECoEuAAILAAkKJSJNFQBuAwALAAkKJSJNFQBuAwAAAA==.Cegeo:BAABNQAECoEXAAIKAAcK8RTkEADjAQAKAAcK8RTkEADjAQAAAA==.Celari:BAAANQAECgEIAQAAAA==.',
Ch='Cheepdeeps:BAABNQAECoEXAAIMAAcKGxigbAD/AQAMAAcKGxigbAD/AQAAAA==.Chelea:BAAANQABCggIFgAAAA==.Chidora:BAAANQADCgcIBwAAAA==.Chocoworm:BAAANQADCgIIAgAAAA==.Chìpotle:BAAANQADCgYICgAAAA==.',
Ci='Ciennajewel:BAAANQAECgQIBAAAAA==.Cirdle:BAAANQAECgUIDgAAAA==.',
Co='Cobalt:BAEBNQAECoEaAAIJAAkKPh2rGwDnAgAJAAkKPh2rGwDnAgAAAA==.Coolkid:BAAANQAECgMJBAAAAA==.Corntard:BAAANQADCggIGAAAAA==.',
Cr='Crazynlazy:BAAANQAECgUIDgAAAA==.Crucifixea:BAAANQAECgcIDQAAAA==.Cruxsader:BAAANQADCgMIAwAAAA==.Crystyl:BAAANQAECgQIBAAAAA==.',
Cu='Cuddly:BAAANQAECgcIBwABNQAFFAIIAgACAAAAAA==.',
Cy='Cymoril:BAABNQAECoEYAAIMAAgKvxWAYwAbAgAMAAgKvxWAYwAbAgAAAA==.',
Da='Daddy:BAABNQAECoE1AAINAAkK1CYOAAAJBAANAAkK1CYOAAAJBAAAAA==.Dagyrr:BAAANQADCgEIAQAAAA==.Dalman:BAAANQAECgQIBgAAAA==.Dalmin:BAAANQADCggICAAAAA==.Dalov:BAAANQAECgUICQAAAA==.Darkcarnival:BAAANQAECgUICQAAAA==.Darkkill:BAAANQADCgMIAwABNQAECggIGwADAKEkAA==.Dasnotgood:BAAANQADCgcIGAAAAA==.',
De='Deemon:BAAANQAECgQICQAAAA==.Delathatha:BAAANQADCgcICwAAAA==.Demiish:BAAANQADCgEIAQAAAA==.Denard:BAAANQADCgUICQABNQADCggIGwACAAAAAA==.Denarias:BAAANQADCgUJBQABNQADCggIHwACAAAAAA==.Denevien:BAAANQAECgEIAgAAAA==.Desdemona:BAAANQAECgQIBAAAAA==.Dethiaris:BAAANQAECgQIBgAAAA==.',
Di='Diablojr:BAAANQAECgUIDAAAAA==.Dianimal:BAAANQAECgMIAwAAAA==.Distroya:BAAANQAECgQIBAAAAA==.',
Dk='Dkaiseremp:BAAANQAECgQIBwABNQAECgUICgACAAAAAA==.',
Do='Dobutsu:BAAANQAECgcICwAAAA==.Doomace:BAABNQAECoEeAAIOAAgKXRILbwD1AQAOAAgKXRILbwD1AQAAAA==.',
Dr='Draaka:BAAANQADCgYICAAAAA==.Dragee:BAAANQAECgQIBAABNQAECgQICQACAAAAAA==.Dragon:BAAANQAECgcIBwAAAA==.Driftyshaman:BAAANQADCggIGAAAAA==.Dræghoule:BAAANQAECgMIAwAAAA==.',
Du='Durnik:BAAANQAECgYICwABNQAECgcIGAAFAIAWAA==.',
Dw='Dworflundgrn:BAAANQAECgUJCQAAAA==.',
Dy='Dyamí:BAAANQAECgUICgAAAA==.',
['Dá']='Dánte:BAAANQAECgIIAgAAAA==.',
Eg='Eglosira:BAAANQADCgMIBQAAAA==.',
El='Elbuhero:BAABNQAECoEeAAMPAAgKKBQPTgBXAQAPAAUKKxcPTgBXAQAQAAcKcwUULwA8AQAAAA==.Eldiablo:BAAANQAECgMIBAAAAA==.Electric:BAAANQAECgMIBQAAAA==.Elementstone:BAAANQAECgIIAgAAAA==.Elendish:BAAANQADCgIIAgAAAA==.Eleven:BAABNQAECoEWAAILAAcKmAVz+QBHAQALAAcKmAVz+QBHAQAAAA==.Elrythe:BAABNQAECoEhAAIIAAkK+xtDHgDoAgAIAAkK+xtDHgDoAgAAAA==.',
Er='Eraleth:BAAANQAECgUIBQABNQAECggIGAABAPcfAA==.',
Fa='Faced:BAAANQAECgUICwAAAA==.Fatalii:BAAANQADCgQIBAAAAA==.',
Fe='Felebash:BAAANQAECgEIAQAAAA==.Felfireflux:BAAANQADCgYIDAAAAA==.Fellirane:BAAANQADCgUIBQAAAA==.',
Fi='Fistdaddy:BAAANQADCgYJDwAAAA==.',
Fl='Floofies:BAABNQAECoEgAAIRAAkKmiHaAgBjAwARAAkKmiHaAgBjAwAAAA==.Floofthulu:BAAANQADCggICAAAAA==.Fluffalo:BAAANQAECgYIEAABNQAECgkJIAARAJohAA==.',
Fo='Foxypocket:BAAANQAECgMIBgAAAA==.',
Fr='Fredrickk:BAAANQAECgQIBAAAAA==.',
Fu='Furcas:BAAANQADCgMIAwAAAA==.Furrglur:BAAANQAECgIIAgABNQAECgkJIAARAJohAA==.Furrylight:BAAANQAECgEIAQABNQAECgkJGQADALQcAA==.Furryphase:BAABNQAECoEZAAMDAAkKtByEGwDOAgADAAkKtByEGwDOAgAEAAEKeAKCFgEjAAAAAA==.Fuzzington:BAAANQADCgcIBwABNQAECgkJIAARAJohAA==.',
Ga='Galnier:BAAANQAECgIJBQAAAA==.Gandoomi:BAAANQABCgIIAgAAAA==.',
Gh='Ghosted:BAAANQAECgMIBQAAAA==.',
Gl='Glaur:BAAANQAECgYICwAAAA==.',
Gr='Gripisrdy:BAAANQAECgUICQAAAA==.',
Gu='Gunslingr:BAABNQAECoEZAAISAAcK9SEsBAClAgASAAcK9SEsBAClAgAAAA==.',
Gw='Gweetow:BAAANQAECgEIAQAAAA==.',
Gy='Gymsharklyfe:BAAANQAECggIBgAAAA==.',
Ha='Hairyjolene:BAAANQADCggIEgAAAA==.Handsome:BAAANQAECgYICAAAAA==.',
He='Headpats:BAAANQAFFAIIAgAAAA==.Hearthisrdy:BAAANQADCggIDgAAAA==.Hexwhisper:BAAANQAECgMIAwAAAA==.Heycarlos:BAABNQAECoEiAAMTAAkK4R93CwANAwATAAkK4R93CwANAwAUAAIKTAfvnwBTAAAAAA==.',
Hi='Hikaripala:BAAANQADCgYIBgABNQAFFAYIEwADAMIXAA==.Hikarishaman:BAACNQAFFIETAAMDAAYKwhfxCQBQAQADAAQKRBTxCQBQAQAEAAMK+heJDgAIAQA1AAQKgSUAAwQACQrJG9c0AGACAAQACAppGtc0AGACAAMACQqiG7s3ADoCAAAA.Hime:BAAANQAECgIIBgAAAA==.',
Ho='Holyblimblam:BAAANQAECgMIBwAAAA==.Honeypieheal:BAAANQAECgMIAwAAAA==.Horabad:BAAANQAECgEIAQAAAA==.Hosemachine:BAAANQAECgYIDAAAAA==.',
Hu='Humper:BAAANQADCgEIAQAAAA==.',
['Hè']='Hèri:BAAANQADCggIFAAAAA==.Hèrifire:BAAANQAECgIIAgAAAA==.',
Ic='Icyshadow:BAAANQAECgMIBQAAAA==.',
Ih='Ihalo:BAAANQAECgYICgAAAA==.',
Il='Illinesh:BAAANQADCgYICgAAAA==.',
Ir='Ironpaw:BAAANQAECgUJDAAAAA==.',
It='Ithildur:BAAANQADCgQIBAAAAA==.',
Ja='Jadde:BAAANQADCgYIBgAAAA==.Jadienne:BAAANQAECgQIDAAAAA==.Jameson:BAAANQAECgUICAAAAA==.Jasmind:BAAANQAECgEIAQAAAA==.',
Ji='Jiwà:BAABNQAECoEiAAMDAAkKoRLSPgAaAgADAAkKoRLSPgAaAgAEAAUKrwHaxQCkAAAAAA==.',
Jo='Joshjb:BAAANQAECgIIAgAAAA==.Joss:BAAANQADCgIIAgAAAA==.',
Ka='Kaguro:BAAANQAECgQICQAAAA==.Kahless:BAAANQADCgcIDgAAAA==.Kaibab:BAAANQABCggIEQAAAA==.Kakwaa:BAAANQAECgIJAwAAAA==.Kaliyah:BAAANQAECgMICQAAAA==.Kayleebear:BAAANQADCgQIBAAAAA==.',
Ke='Kerplaa:BAAANQADCgMIAwAAAA==.Keyadistor:BAAANQAECgYIDQAAAA==.',
Kh='Khazabrew:BAAANQAECgYIEQAAAA==.',
Ki='Kiamara:BAAANQAECgQIBAAAAA==.Kinderlin:BAAANQAECgcIEgAAAA==.Kirbun:BAAANQAECgcIEwAAAA==.Kizchaos:BAAANQAECgEJAQAAAA==.',
Ko='Komurash:BAAANQAECgUICQAAAA==.Korstruck:BAAANQAECgUIBQAAAA==.Kotys:BAAANQADCgUIBQAAAA==.',
Ku='Kungbrew:BAAANQAECgEIAQABNQAECgMIBQACAAAAAA==.',
La='Lancaban:BAAANQADCgcIGAAAAQ==.',
Le='Lethalarrow:BAAANQAECgMIAwAAAA==.Lewismr:BAAANQADCgUIBQABNQADCggIIgACAAAAAA==.Lewisr:BAAANQAECgUIDAAAAA==.',
Li='Ligahoo:BAAANQADCggJDwAAAA==.Lilysweets:BAAANQADCgMIAwAAAA==.',
Lo='Lorianne:BAAANQAECgEIAQAAAA==.Lorryanne:BAABNQAECoEdAAIVAAgKqQonXgCxAQAVAAgKqQonXgCxAQAAAA==.',
Lu='Lucianas:BAAANQAECgQIAgAAAA==.Lunacat:BAAANQAECgIIAgABNQADCgYJDwACAAAAAA==.',
Ly='Lysi:BAAANQAECgMIAwAAAA==.',
Ma='Madaea:BAABNQAECoEbAAINAAcKnRzGDwA2AgANAAcKnRzGDwA2AgAAAA==.Madameuyen:BAAANQADCggIEwAAAA==.Madlyn:BAAANQADCgcIEgAAAA==.Magepuppy:BAAANQAECgYIEAABNQAECgkJJwAWAJQdAA==.Makavalii:BAABNQAECoE1AAMVAAgKURNoSAADAgAVAAgKURNoSAADAgAOAAcKHxXudADlAQAAAA==.Malanimus:BAAANQAECgQJBwAAAA==.Malevola:BAAANQAECgEIAQAAAA==.Malholis:BAAANQAECgIIAgAAAA==.Matagi:BAAANQAECggIEAAAAA==.Mate:BAAANQADCgUIBQABNQADCggIGwACAAAAAA==.',
Me='Meatloaf:BAAANQADCgQIBAAAAA==.Meeseks:BAABNQAECoEZAAIUAAgKyxj9LAAmAgAUAAgKyxj9LAAmAgAAAA==.Megabyte:BAAANQAECgQJBAAAAA==.Melbeast:BAAANQAECgIIAgAAAA==.Melorea:BAAANQADCgIIAgAAAA==.Merdin:BAAANQAECgUIDgAAAA==.Methmartion:BAAANQAECgMIBgAAAA==.',
Mi='Mish:BAAANQAECgQIBAAAAA==.Missiah:BAAANQAECgUJCwAAAA==.',
Mo='Molfise:BAAANQADCgYIBQAAAA==.Monna:BAAANQABCgIJAgAAAA==.Moonfell:BAAANQAECgYIDgAAAA==.Moonlilly:BAAANQAECgQIBAAAAA==.Mopp:BAAANQADCgcIBwAAAA==.Morganthe:BAAANQADCggIEAAAAA==.Mornîngstar:BAAANQAECgMIAwAAAA==.',
Mx='Mxtemlen:BAAANQAECgQIBAABNQAECgUIFgAVAIESAA==.',
My='Mylilhunter:BAAANQAECgUIBQAAAA==.Myrtheli:BAAANQADCggICAAAAA==.Mysticx:BAAANQAECggICAAAAA==.',
Na='Nachtelf:BAABNQAECoEbAAIIAAgKTRkPPgBpAgAIAAgKTRkPPgBpAgAAAA==.Nagan:BAAANQAECgYICwAAAA==.Natadawn:BAAANQADCgYIBgAAAA==.Natalone:BAABNQAECoEbAAIXAAgKlCUrAQBwAwAXAAgKlCUrAQBwAwAAAA==.Nathel:BAAANQAECgMIBgAAAA==.',
Ni='Nirra:BAAANQADCgYJBgAAAA==.',
No='Noctis:BAAANQAECgUICgAAAA==.Notoriginal:BAAANQAECgcIBwAAAA==.Novatron:BAAANQAECgIIAwAAAA==.',
Nu='Nuked:BAAANQAECgUIEQAAAA==.',
['Né']='Néith:BAAANQADCgQIBAAAAA==.',
Od='Odor:BAAANQABCggIEAAAAA==.',
Og='Ograskygazer:BAAANQAECgMIAwAAAA==.',
Om='Omee:BAAANQAECgQIBQAAAA==.Omegaone:BAAANQADCgcIBwAAAA==.',
On='Oneil:BAAANQADCgMJAwAAAA==.Onlyshrimps:BAAANQAECgYIBgAAAA==.',
Or='Oralena:BAAANQAECgMIBgAAAA==.Orioncheats:BAABNQAECoEZAAMUAAcK1RUyRgCZAQAUAAcKFhUyRgCZAQAYAAEK6hsznwBQAAAAAA==.',
Ow='Owo:BAAANQAECgEIAQAAAA==.',
Ox='Oxygën:BAAANQAECgIIAgAAAA==.',
Pa='Palomita:BAAANQADCgIIAgAAAA==.',
Pe='Ped:BAAANQAECgEIAQABNQAECgYIEwACAAAAAA==.Pedarias:BAAANQAECgYIEwAAAA==.Peon:BAAANQAECgUIBQAAAA==.Perstephanie:BAAANQADCgQIBAAAAA==.',
Ph='Pharune:BAAANQAECgUICQAAAA==.Phredrick:BAAANQAECgEIAQAAAA==.',
Pi='Picklebosh:BAABNQAECoEoAAIEAAkKqSVeAgDYAwAEAAkKqSVeAgDYAwAAAA==.Piemanninty:BAAANQAECgIJBQAAAA==.',
Pl='Plandemic:BAAANQADCgcIBwAAAA==.',
Po='Pockithealz:BAAANQADCgQIBAABNQADCgQIBAACAAAAAA==.Pokerface:BAAANQAECgQIBAAAAA==.Pounces:BAAANQAECgcIBwABNQAFFAIIAgACAAAAAA==.',
Pr='Precious:BAAANQAECgEIAQABNQAFFAYIEAAHABoVAA==.',
Pu='Puppet:BAAANQAECgcICAABNQAFFAYIEAAHABoVAA==.',
Py='Pymura:BAAANQADCgQIBAAAAA==.',
['Pí']='Píongá:BAAANQADCgEIAQAAAA==.',
Qe='Qee:BAAANQAECgEIAQABNQAECgQICQACAAAAAA==.',
Qu='Quattro:BAAANQAECgcIDQAAAA==.',
Ra='Racecar:BAAANQAECgIIAwAAAA==.Raezil:BAAANQAECgQICQABNQAECgcIFgAJADIQAA==.Raivyn:BAABNQAECoEYAAIFAAcKgBY4HwDdAQAFAAcKgBY4HwDdAQAAAA==.Rathmora:BAAANQABCggIFwAAAA==.Raylaira:BAAANQADCggIHwAAAA==.Raziel:BAAANQADCgYJBgAAAA==.',
Re='Remnants:BAAANQADCggIEwAAAA==.Renard:BAABNQAECoEbAAIQAAgK8B/MCgDoAgAQAAgK8B/MCgDoAgAAAA==.Reposado:BAAANQADCgcICAAAAA==.Revelare:BAAANQAECgUICQAAAA==.Rexbie:BAAANQAECgcICwAAAA==.',
Rh='Rhylee:BAAANQAECgEIAQAAAA==.',
Ri='Rianne:BAAANQADCgUIBQAAAA==.Riptidepod:BAAANQAECgYIBwAAAA==.',
Ro='Robberttrest:BAAANQAECgQICgAAAA==.Rockyhunterr:BAABNQAECoEcAAIYAAgK0R/bFgDHAgAYAAgK0R/bFgDHAgAAAA==.Rockymage:BAAANQADCgYIBgAAAA==.Rockywarlock:BAAANQAECgEIAQAAAA==.Rockywarrior:BAAANQADCgYICgABNQAECggIHAAYANEfAA==.Rooth:BAAANQAECgEIAQAAAA==.Roryn:BAABNQAECoEgAAIOAAkKPyLVEABnAwAOAAkKPyLVEABnAwAAAA==.',
Ru='Rubï:BAAANQAECgYIBgAAAA==.Rugiaas:BAACNQAFFIEPAAIVAAUKiSTwAgAdAgAVAAUKiSTwAgAdAgA1AAQKgS8AAxUACQpBJV8CAL0DABUACQpBJV8CAL0DAA4ABAo2GSm2AD8BAAAA.Rugian:BAAANQAECgQIBAABNQAFFAUIDwAVAIkkAA==.',
Ry='Ryuka:BAAANQAECgUJCgAAAA==.',
['Râ']='Râezil:BAAANQADCgIIAgABNQAECgcIFgAJADIQAA==.',
Sa='Sabriiel:BAAANQADCgIIAwABNQAECgQIBgACAAAAAA==.Samyria:BAAANQAECgIIAgAAAA==.Satyaru:BAABNQAECoEWAAQZAAcKkwdLFgAyAQAZAAcKkwdLFgAyAQANAAQKkgj/LwCZAAAFAAEKAQa/VgArAAAAAA==.Saucy:BAAANQAECgMIBQAAAA==.',
Se='Sedona:BAAANQAECgQIBAAAAA==.Selarra:BAAANQAECgYIDwAAAA==.Seric:BAABNQAECoEYAAMaAAcKig6mFgBhAQAaAAcKig6mFgBhAQAMAAMK+wH7FAE5AAAAAA==.Sethuriel:BAAANQAECgUIDAAAAA==.',
Sh='Shadowdancèr:BAAANQADCgEJAQAAAA==.Shalzith:BAAANQAECgEIAQAAAA==.Shenandoah:BAAANQADCgYJBgAAAA==.Shockadelica:BAAANQADCgYIBgAAAA==.',
Sk='Skoto:BAAANQAECgQIBAAAAA==.',
Sm='Smartfood:BAAANQADCggIHQAAAA==.Smoochybooty:BAAANQAECgEIAQAAAA==.',
So='Solnar:BAABNQAECoEWAAMVAAUKgRLSnAD5AAAVAAUKgRLSnAD5AAAOAAQK7wpz+gC2AAAAAA==.',
Sp='Splashdaddy:BAACNQAFFIEJAAIDAAUKEA4cCACDAQADAAUKEA4cCACDAQA1AAQKgSgAAgMACQpCHy8QABoDAAMACQpCHy8QABoDAAE1AAMKBgkPAAIAAAAA.Spoiled:BAAANQADCggICAABNQAFFAYIEAAHABoVAA==.',
Sr='Srìracha:BAAANQADCggICAAAAA==.',
St='Staks:BAAANQADCgcIFAAAAA==.Starii:BAAANQAECgQIBAAAAA==.Stormieskye:BAAANQAECgYIEgAAAA==.Striga:BAAANQADCgcIBwAAAA==.',
Su='Suzume:BAAANQAECgQIBAABNQAFFAYIEwADAMIXAA==.',
Sw='Sweetshot:BAAANQADCgEIAQAAAA==.',
Sy='Sylvancura:BAAANQADCgQIBAAAAA==.Synestra:BAAANQAECgIIAgAAAA==.',
Ta='Taea:BAAANQAECgEIAQAAAA==.Taeus:BAAANQAECgUIEAAAAA==.Talagark:BAAANQADCgYIBgAAAA==.Talanat:BAAANQADCgIIAgAAAA==.Taurenator:BAABNQAECoEcAAIaAAgKhSK9AwAdAwAaAAgKhSK9AwAdAwAAAA==.',
Te='Teheez:BAAANQADCgIIAgAAAA==.Tenthrol:BAAANQABCgMIBQAAAA==.Teranidas:BAAANQADCgUJBQABNQADCggIHwACAAAAAA==.Teratrendera:BAAANQAECgMIBgAAAA==.Teron:BAAANQAECgMJBAAAAA==.Tesx:BAAANQAECgEIAQAAAA==.',
Th='Thavis:BAAANQAECgYICwAAAA==.Thetimelord:BAAANQAECgMIBQAAAA==.Thewarrior:BAAANQAECgQIBAAAAA==.Thrask:BAAANQADCgQIBAAAAA==.',
Ti='Ticktac:BAAANQAECgYJBgAAAA==.Tik:BAAANQADCggIDgAAAA==.Tilted:BAAANQAECggIEAAAAA==.Tinkr:BAAANQAECggIEAAAAA==.',
To='Tobi:BAAANQADCgYIBgAAAA==.Toewzix:BAAANQADCgQIBAAAAA==.Tom:BAAANQAECgUIBwABNQAECgcIFgAJADIQAA==.Torrey:BAAANQAECgYIDAAAAA==.Totemsareus:BAABNQAECoEbAAMDAAgKoSQ1DQAzAwADAAgKoSQ1DQAzAwAEAAEKiwP0BgEtAAAAAA==.Toxx:BAAANQAECgEJAQAAAA==.',
Tr='Tradd:BAABNQAECoEhAAQHAAkK3xwgFwDtAgAHAAgKbR4gFwDtAgAbAAcKww6UCQCHAQAcAAMK1QleSACgAAAAAA==.Trallor:BAAANQAECgUIDQAAAA==.Trhall:BAAANQADCggIEwAAAA==.Tristyana:BAABNQAECoEXAAIIAAcKrAvJeQC8AQAIAAcKrAvJeQC8AQAAAA==.',
Ts='Tsiddahn:BAABNQAECoEZAAIHAAkKfxgYHQDIAgAHAAkKfxgYHQDIAgAAAA==.Tsunâde:BAABNQAECoEVAAMFAAgKmSDjCwDqAgAFAAgKmSDjCwDqAgANAAQK9w6BKQDPAAAAAA==.',
Ty='Tylurien:BAAANQAECgUICQAAAA==.Tyrael:BAAANQAECgIIAgABNQADCgMJAwACAAAAAA==.',
Uk='Ukon:BAAANQADCgYIBgAAAA==.',
Ul='Ulangi:BAAANQADCgYICgAAAA==.',
Un='Un:BAAANQADCgcIAQAAAA==.',
Ur='Urbanprey:BAAANQAECgYIDwAAAA==.',
Va='Valenhi:BAAANQADCgQICgAAAA==.Valkoinen:BAAANQADCgMJAwAAAA==.Valora:BAABNQAECoEWAAIHAAcKtxlBQAAfAgAHAAcKtxlBQAAfAgAAAA==.Valoria:BAAANQAECgEIAQAAAA==.Vanille:BAAANQAECgMIBQAAAA==.Vargen:BAAANQAECgIIAgAAAA==.Varonika:BAAANQAECgIIAgAAAA==.Vayla:BAABNQAECoEYAAIaAAcKohyUCgBGAgAaAAcKohyUCgBGAgAAAA==.',
Vb='Vbv:BAAANQAECgMIAwAAAA==.',
Ve='Vedik:BAAANQADCggIDwAAAA==.Vegasducks:BAAANQAECgUIDQAAAA==.Velara:BAAANQADCgUICAAAAA==.Veld:BAAANQAECgUIBAAAAA==.Velithara:BAAANQADCgYJBgAAAA==.',
Vi='Violet:BAAANQAECgMIBQAAAA==.',
Vy='Vyla:BAAANQABCgYICAAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUIBQAAAA==.',
Wa='Wardancer:BAAANQADCgQIBAAAAA==.Warfise:BAAANQAECgIIAgAAAA==.Warspriest:BAAANQAECgUICAAAAA==.Warwizard:BAABNQAECoEjAAIVAAgKDyUxCQBjAwAVAAgKDyUxCQBjAwAAAA==.',
Wd='Wdemperor:BAAANQAECgQIBwABNQAECgUICgACAAAAAA==.',
We='Webin:BAAANQAECgEIAQAAAA==.',
Wh='Whispaknight:BAAANQAECgEJAQABNQAECgEIAQACAAAAAA==.Whisperwiind:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Whisperz:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Wi='Wickedywaque:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQAECgQJBwAAAA==.Wiisper:BAAANQAECgEIAQAAAA==.Wilshammy:BAAANQADCgUIDQAAAA==.Winterhunter:BAAANQADCgEIAQAAAA==.',
Wo='Wonkyponky:BAABNQAECoEgAAIVAAgKERnwLAB6AgAVAAgKERnwLAB6AgAAAA==.',
Wr='Wrathbarrage:BAAANQADCggJCAABNQAECgYIEgACAAAAAA==.Wrathchoi:BAAANQADCgIIAQAAAA==.Wrathstorm:BAAANQAECgYIEgAAAA==.',
Ya='Yazahk:BAAANQADCggJFgABNQADCgYIBAACAAAAAA==.Yazjani:BAAANQADCgIIAgAAAA==.Yazoth:BAAANQADCgEIAQAAAA==.Yazoura:BAAANQADCggICgAAAA==.Yazwynn:BAAANQADCgcIDgAAAA==.',
Ye='Yezgraine:BAACNQAFFIESAAIYAAYKSSB0AgA3AgAYAAYKSSB0AgA3AgA1AAQKgR4AAhgACQoGIl0NACMDABgACQoGIl0NACMDAAAA.',
Yo='Yookock:BAAANQADCggIDgAAAA==.',
Yz='Yzaak:BAAANQADCgYIBAAAAA==.',
Za='Zagyg:BAAANQADCgQIBAAAAA==.',
Ze='Zeddiccus:BAAANQAECgIJBgAAAA==.Zeva:BAAANQAECgIIAgAAAA==.',
Zo='Zonzmik:BAAANQABCgYIBAAAAA==.Zorrokiller:BAAANQADCgQIBAAAAA==.Zorvoth:BAAANQADCgMIAgABNQADCggIHwACAAAAAA==.',
Zu='Zurazaee:BAAANQAECgMIBgAAAA==.',
['Él']='Élle:BAAANQADCgcICAAAAA==.',
['Ér']='Éric:BAABNQAECoEXAAIdAAcKBgduIAAMAQAdAAcKBgduIAAMAQAAAA==.',
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
