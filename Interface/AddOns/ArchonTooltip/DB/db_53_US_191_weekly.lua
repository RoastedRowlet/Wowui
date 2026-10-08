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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Evoker-Preservation','Warrior-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Affliction','Warrior-Arms','Paladin-Retribution','Hunter-Survival','Paladin-Holy','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Druid-Balance','DemonHunter-Vengeance','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Priest-Shadow','Warrior-Fury','DeathKnight-Frost',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acaciastrain:BAAANQADCggIDwAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aerebos:BAAANQAECgEIAQABNQAECggIKgABADUhAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAAANQAECgUIDwABNQAECggIKgABADUhAA==.Aeón:BAAANQADCgMIAwABNQAECgQICAACAAAAAA==.',
Ag='Agua:BAAANQAECgQIBAAAAA==.',
Ak='Akashá:BAAANQADCgEIAQAAAA==.',
Al='Aladrius:BAEANQAECgQIBwAAAA==.Alexanderath:BAAANQAECgQIAwAAAA==.Alkatractite:BAAANQAECgQICQAAAA==.Allenwalker:BAAANQAECgQIBQAAAA==.Allison:BAAANQADCgUIBQABNQAECggIIwADANITAA==.',
Am='Amey:BAAANQAECgIIAgAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJIgAEAAENAA==.',
Ao='Aoeslave:BAABNQAECoEhAAMFAAgK1xTyeADOAQAFAAcKExTyeADOAQAGAAMKDRAlQwCtAAAAAA==.',
Ap='Apk:BAAANQADCggIDwAAAA==.',
Ar='Arrisia:BAAANQAECgQIBQAAAA==.Arthedain:BAAANQAECgYIDgAAAA==.Arthedaine:BAAANQAFFAIIAgABNQAECgYIDgACAAAAAA==.',
As='Assano:BAAANQAECgQIDQABNQAECggIJAAHAF4ZAA==.',
Au='Auvry:BAABNQAECoEjAAIIAAkKrQ/5FgAxAgAIAAkKrQ/5FgAxAgAAAA==.',
Az='Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAAANQAECgQICwAAAA==.Bakala:BAAANQAECgQIBwAAAA==.Barath:BAAANQAECgQIBwAAAA==.',
Be='Belegaer:BAAANQAECgYIEQAAAA==.Belenos:BAAANQADCgYIFAABNQADCgYIFAACAAAAAA==.Benmaverick:BAAANQAECgYIDQAAAA==.Bervin:BAAANQAECgQICAAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAAANQAECgQIDQAAAA==.',
Bo='Bobe:BAABNQAECoElAAIJAAgKlh5cCACkAgAJAAgKlh5cCACkAgAAAA==.Bobedruid:BAAANQADCggIHgAAAA==.Bordok:BAAANQAECgQIBwAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Broot:BAAANQADCgMIAwAAAA==.Brunco:BAABNQAECoEdAAMKAAgKTBdXUABWAgAKAAgKTBdXUABWAgALAAEK0QrjeAA3AAAAAA==.',
Ca='Captplanet:BAABNQAECoEnAAMMAAkKTRg+EgCfAgAMAAkKTRg+EgCfAgANAAYKFxcQEgCqAQAAAA==.',
Ce='Ceindra:BAABNQAECoEdAAIOAAgKFxt/CwCiAgAOAAgKFxt/CwCiAgAAAA==.Celestria:BAAANQAECgMIBQAAAA==.Celiñ:BAAANQAECgEIAQAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Colbalt:BAAANQADCggIBwAAAA==.Constantinez:BAAANQAECggIDgAAAA==.Cor:BAAANQAECgEIAgAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECoEqAAIPAAkKhxizXwCsAgAPAAkKhxizXwCsAgAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFIEJAAIQAAQK+xM2CABHAQAQAAQK+xM2CABHAQA1AAQKgTIAAxAACQqJH+cKACADABAACQqJH+cKACADABEAAQqWEVaBADcAAAAA.David:BAAANQAECggIEgAAAA==.',
De='Deadlyglow:BAAANQAECgUIBwAAAA==.Demiurgos:BAAANQAECgYIDAAAAA==.Denji:BAAANQABCgEIAQAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAABNQAECoEXAAQSAAcKISISCwCVAQAFAAYK4h1oZwAAAgASAAUKuBoSCwCVAQAGAAIK9RyWRgChAAAAAA==.',
Dh='Dhiying:BAAANQADCgcIBwAAAA==.',
Di='Dirtface:BAABNQAECoEbAAITAAgKfQe1qQCIAQATAAgKfQe1qQCIAQAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECoEgAAIUAAkK/hLjagAvAgAUAAkK/hLjagAvAgAAAA==.',
Do='Dolemen:BAAANQAECgQICwAAAA==.Domaon:BAABNQAECoEhAAIRAAgK9RwUGwCdAgARAAgK9RwUGwCdAgAAAA==.Domshammy:BAAANQADCggICAABNQAECggIIQARAPUcAA==.Doubt:BAAANQAECgQIBwAAAA==.Dozy:BAABNQAECoEgAAIUAAgKdSIYJwAOAwAUAAgKdSIYJwAOAwAAAA==.',
Dr='Druidheelzz:BAAANQAECgIIAgAAAA==.Druissh:BAAANQAECgEIAgABNQAECggIJAAHAF4ZAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dunigan:BAAANQAECgUIEAAAAA==.Dunigen:BAAANQAECgEIAQAAAA==.',
Eb='Ebeast:BAABNQAECoEdAAIVAAgKbRGeBQAyAgAVAAgKbRGeBQAyAgAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Facade:BAAANQAECgcIDgAAAA==.Facepalm:BAAANQAECgYIEwAAAA==.Falyy:BAAANQADCgMIAwAAAA==.Farmergeorge:BAAANQAECgQJCAAAAA==.',
Fe='Fentak:BAAANQADCgcIEwAAAA==.',
Fi='Fierytotes:BAAANQADCgQIBgABNQAECggIIgAUAE4ZAA==.',
Fo='Forbidenelf:BAABNQAECoEgAAIUAAgKpB2DSQCSAgAUAAgKpB2DSQCSAgAAAA==.Forging:BAAANQADCgQIBAAAAA==.Forgotmymeds:BAAANQAECgMIBAAAAA==.Foxmccloud:BAAANQAECgQIBwAAAA==.',
Fr='Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAABNQAECoEZAAIPAAcKvBJHxgDUAQAPAAcKvBJHxgDUAQAAAA==.',
Fu='Funkybooty:BAAANQABCgIIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAAANQAECgUIEgAAAA==.Gellywoo:BAAANQAECgQICQAAAA==.Gemmarolizzy:BAAANQAECgMIBAAAAA==.',
Go='Golaoth:BAAANQAECgQICwAAAA==.Gooftroupe:BAABNQAECoEYAAIWAAcKwB9QLQCWAgAWAAcKwB9QLQCWAgAAAA==.',
Gr='Grandmaster:BAAANQAECgYIDQABNQAECgEIAQACAAAAAA==.Grawn:BAAANQADCgMIAwAAAA==.Greymoon:BAAANQAECgQIBgAAAA==.Grimaced:BAAANQADCgUIBQABNQAECggIHgAUAOwiAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Ha='Haezi:BAAANQAECgMIAwABNQAECgcIGAAXAKUXAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgQIBgAAAA==.',
He='Helbafx:BAAANQADCggILgAAAA==.',
Hi='Hino:BAAANQAECgYIDgAAAA==.',
Ho='Homewrecker:BAAANQAECgQIBwAAAA==.Horuid:BAAANQADCgEIAQAAAA==.',
Ic='Icemàn:BAAANQADCgYICQAAAA==.',
Id='Idrazil:BAAANQAECgcIEAAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBAAAAA==.',
In='Infectz:BAAANQAECggJAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAACNQAFFIEIAAIDAAQKJxM+DgA6AQADAAQKJxM+DgA6AQA1AAQKgTsAAgMACQqwIOMNAD0DAAMACQqwIOMNAD0DAAAA.Jakik:BAAANQADCgUIBQAAAA==.Jarlaxl:BAAANQADCgQIBAAAAA==.Jawn:BAAANQAECgQICwAAAA==.',
Je='Jessuss:BAAANQAECgQIBwAAAA==.',
Jh='Jha:BAAANQAECgYIEAAAAA==.',
Ju='Jude:BAAANQAECgcIEAAAAA==.Junipermoon:BAAANQADCgYIFAAAAA==.',
Ka='Kabub:BAAANQAECgYIEQAAAA==.Kalahandra:BAABNQAECoEbAAIMAAgKkxHwIQDqAQAMAAgKkxHwIQDqAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQAAAA==.Katotan:BAABNQAECoEcAAIMAAcK/xQsJwC3AQAMAAcK/xQsJwC3AQAAAA==.',
Ke='Kealestra:BAAANQAECgQICwAAAA==.Keyboärd:BAAANQAECgQIBwAAAA==.',
Ki='Kimochi:BAAANQAECgQIBAAAAA==.Kippo:BAEANQADCgcIBwABNQAECgcICAACAAAAAA==.Kittylover:BAAANQADCggIEwAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQADCgUICwAAAA==.Kossnen:BAAANQAECgQICQAAAA==.',
Kr='Krestisnack:BAAANQAECgQICgAAAA==.',
Ku='Kuda:BAAANQAECgQIBwAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgUICgAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECgQICAACAAAAAA==.',
['Kó']='Kóñä:BAAANQAECgQICAAAAA==.',
La='Larke:BAAANQADCgYIBgAAAA==.Lasa:BAAANQAECgEIAQAAAA==.Lasloo:BAABNQAECoEcAAIUAAcKWQwnvQBpAQAUAAcKWQwnvQBpAQAAAA==.Laylani:BAABNQAECoEoAAIEAAgKWxAHIwCcAQAEAAgKWxAHIwCcAQAAAA==.',
Le='Lebronjames:BAAANQAECgQIBAAAAA==.Leynreite:BAAANQAECgMIBAAAAA==.',
Li='Lisan:BAAANQAECgYIEgAAAA==.Littledicey:BAABNQAECoEgAAIYAAgKZgp+NQDGAQAYAAgKZgp+NQDGAQAAAA==.',
Lu='Luciä:BAAANQAECgQICwAAAA==.Lucymoon:BAAANQAECgYIBgAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Ly='Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Machoman:BAAANQAECgQIBAAAAA==.Madness:BAAANQAECgYIDwAAAA==.Maerion:BAAANQAECgQIDQAAAA==.Magdeth:BAAANQAECgUIBQAAAA==.Marabelle:BAAANQAECgYIDwAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQICAAAAA==.Marixia:BAAANQAECgUICgAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAABNQAECoEbAAIXAAcK4hBwEwCNAQAXAAcK4hBwEwCNAQAAAA==.Mawgwa:BAAANQAECgMIAwAAAA==.',
Mc='Mcwrath:BAAANQADCgUIBQABNQAECgkJIgAEAAENAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECgcIGAAXAKUXAA==.Mero:BAABNQAECoEhAAMFAAkKRR5fKwC/AgAFAAgKqh1fKwC/AgAGAAIKHRmuRwCeAAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Moobear:BAAANQADCgUIBQAAAA==.Mosimo:BAAANQABCgIIAgAAAA==.Moushuhan:BAABNQAECoEZAAMZAAgKcREBFwAXAgAZAAgKcREBFwAXAgAYAAEKUgwsiQA2AAAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAAANQAECgcIDAAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAQAAAA==.Netherrogue:BAACNQAFFIEIAAMaAAQKKBWCAQD/AAAaAAMKIxiCAQD/AAAYAAEKNgyLFgBWAAA1AAQKgSAAAxoACQpWJGQDAOQCABoABwrvJGQDAOQCABgAAwpbIktRACsBAAAA.',
No='Noesis:BAAANQADCgQJBAAAAA==.',
Nu='Nuke:BAAANQAECgQIBgABNQAECgYIEgACAAAAAA==.',
Ny='Nytehuntrix:BAAANQAFFAEIAgAAAA==.Nytemayer:BAABNQAECoEgAAMFAAkKHRxxRQBlAgAFAAgKfxxxRQBlAgAGAAMKtRMfQAC4AAABNQAFFAEIAgACAAAAAA==.',
Ob='Obmakare:BAAANQAECgQIBwAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAAANQAECgQIBQAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgQIBgAAAA==.',
Op='Opiiknight:BAAANQAECgQIBAAAAA==.Opiishift:BAABNQAECoEXAAIbAAcKORCESQCWAQAbAAcKORCESQCWAQAAAA==.Opiishots:BAAANQAECgQIBQAAAA==.',
Or='Orcc:BAAANQADCgcICwAAAA==.Orcloc:BAAANQAECgUIBgABNQAECgEIAQACAAAAAA==.',
Pa='Paley:BAAANQAECgQICAAAAA==.',
Pd='Pdgrimm:BAAANQADCgQIBAAAAA==.',
Pe='Performance:BAABNQAECoErAAIcAAkK6h7SAgAmAwAcAAkK6h7SAgAmAwAAAA==.Peterturbo:BAAANQAECgQICAABNQABCgIIAgACAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQADCgYICAAAAA==.Poîsonivy:BAAANQAECgQICwAAAA==.',
Ps='Psyrine:BAAANQADCgYIFQAAAA==.',
Qu='Qu:BAABNQAECoErAAITAAkKDBpMOwDCAgATAAkKDBpMOwDCAgAAAA==.',
Ra='Rattlesnake:BAAANQADCggIIQAAAA==.Raymonnd:BAAANQADCgYIBgAAAA==.',
Re='Renägäde:BAAANQAECgYICgAAAA==.Retiredfurry:BAABNQAECoEeAAMdAAcKNiNtCwCwAgAdAAcKNiNtCwCwAgABAAIKUCM6SwCYAAAAAA==.',
Ri='Ricodadawg:BAABNQAECoExAAIPAAkKpiGlKAA2AwAPAAkKpiGlKAA2AwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQADCgYIDQAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgYICwABNQAECgcIEwACAAAAAA==.Runningshama:BAAANQAECgcIEwAAAA==.Rurahk:BAAANQAECgYIDwAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAAANQAECgQIBwAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saeriin:BAAANQADCgYIBgAAAA==.Saintsnyder:BAABNQAECoEiAAQEAAkKAQ12NQAPAQAEAAUKQBV2NQAPAQAUAAgKzAXK9gD3AAAWAAEKGgFxIAEPAAAAAA==.Saithis:BAAANQAECgEIAgAAAA==.Sanorasong:BAAANQAECgQICgAAAA==.Saphirra:BAAANQADCggJEQAAAA==.Sarylin:BAAANQAECgQIBQAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathona:BAAANQADCgcIBwAAAA==.Sathpriest:BAABNQAECoEbAAQeAAkKeiOfCgBbAwAeAAgK4CSfCgBbAwAfAAIKyRx+FgCrAAAgAAEKrgz0cwAoAAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAAANQAECgQIBAAAAA==.',
Se='Severussnape:BAABNQAECoEbAAMGAAcKMQVDSQCZAAAFAAcK4QRCtgAzAQAGAAQKbQNDSQCZAAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.She:BAABNQAECoEcAAIZAAkKdA78EwA4AgAZAAkKdA78EwA4AgAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAgAAAA==.Shortstack:BAAANQAECgYIDAAAAA==.',
Si='Sinensis:BAAANQAECgQIBAAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAQICQAQAPsTAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAAANQAECgQICQAAAA==.',
Sl='Slaycie:BAAANQAECgQIBwAAAA==.',
Sn='Sneek:BAAANQAECgQICAAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAAANQAECgUIBwAAAA==.',
Sp='Spaghett:BAABNQAECoEYAAMXAAcKpRfpDgDiAQAXAAcKpRfpDgDiAQABAAUK1wVISwCYAAAAAA==.',
St='Stanger:BAAANQAECgcICgAAAA==.Starlight:BAAANQAECgQIBgABNQAECggIHwAUAGolAA==.',
Sy='Syrden:BAABNQAECoElAAIMAAkKKwxYJADUAQAMAAkKKwxYJADUAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAABNQAECoEaAAIhAAcK6x7pBgBrAgAhAAcK6x7pBgBrAgAAAA==.Tangylizard:BAAANQAECgcIEAAAAA==.Tawainai:BAABNQAECoEdAAIPAAcKVBEr0wC6AQAPAAcKVBEr0wC6AQAAAA==.',
Te='Tessla:BAABNQAECoEkAAMHAAgKXhl9PwBNAgAHAAgKXhl9PwBNAgADAAIKtQFx/QA9AAAAAA==.Tetragram:BAABNQAECoEqAAIBAAgKNSEWDQDvAgABAAgKNSEWDQDvAgAAAA==.',
Th='Thelarï:BAABNQAECoEbAAIKAAcK+wc0qQB/AQAKAAcK+wc0qQB/AQAAAA==.Thors:BAABNQAECoEeAAIUAAgK7CIqHwAwAwAUAAgK7CIqHwAwAwAAAA==.Thundertoes:BAABNQAECoEbAAMDAAcKaBT8awCZAQADAAcKaBT8awCZAQAHAAIKAA/N8QBuAAAAAA==.',
Ti='Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAAANQAECgQIBwAAAA==.Titåx:BAAANQADCgYIBgAAAA==.',
To='Tonik:BAAANQAECgUIEQAAAA==.Torgoth:BAAANQAECgQICwAAAA==.Toshido:BAAANQAECgQICAAAAA==.Totemtroll:BAAANQAECgEIAQAAAA==.Toy:BAAANQADCggICAAAAA==.',
Tr='Trevize:BAAANQADCgcIEwAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAQAAAA==.',
Ub='Ubully:BAAANQADCgMIAwAAAA==.',
Ul='Ultane:BAAANQAECgMIBAAAAA==.',
Un='Unholypally:BAAANQADCggICgAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECoErAAMUAAkKQx3ULgDvAgAUAAkKQx3ULgDvAgAWAAcKOQSPmAAtAQAAAA==.Valiantaint:BAAANQAECgcIEAABNQAECgkJKwAUAEMdAA==.Valiantroar:BAAANQAECgYIBgABNQAECgkJKwAUAEMdAA==.Vashon:BAAANQADCgQIBgAAAA==.',
Ve='Velherun:BAABNQAECoEZAAIUAAcKhhXflwC9AQAUAAcKhhXflwC9AQAAAA==.Vendel:BAABNQAECoEpAAIHAAkKcSRvBgCsAwAHAAkKcSRvBgCsAwAAAA==.Vexxaa:BAAANQAECgQICwAAAA==.',
Vi='Virajr:BAAANQAECgIIAgAAAA==.Vissiction:BAABNQAECoEYAAIQAAcKvBNYKgDPAQAQAAcKvBNYKgDPAQAAAA==.Vistine:BAAANQAECgQICwABNQAECggIJAAHAF4ZAA==.Vitez:BAAANQAECgYIEgAAAA==.',
Wa='Waterslide:BAAANQADCgMIAwAAAA==.',
We='Wendy:BAABNQAECoEjAAIDAAgK0hPCUwDqAQADAAgK0hPCUwDqAQAAAA==.',
Wh='Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAAANQAECgYIEgAAAA==.Winkster:BAAANQAECgUIBQAAAA==.',
Xa='Xanadu:BAABNQAECoEhAAMfAAgKjh0HAwC5AgAfAAgKjh0HAwC5AgAeAAEKUxKl3wA3AAAAAA==.Xarinia:BAAANQADCggIEwABNQAECggIJwAiAPoMAA==.',
Xb='Xbear:BAAANQAECgQICwABNQAFFAQICAAZACIWAA==.',
Xd='Xdynasty:BAACNQAFFIEIAAMZAAQKIhbaCQAMAQAZAAMKEBXaCQAMAQAYAAEKWBnhFwBSAAA1AAQKgTIAAxkACQoWIbIGAAwDABkACQrYHLIGAAwDABgABAq+HeNIAFgBAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIDgABNQAECgQIBQACAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAECgYIEgACAAAAAA==.',
Za='Zabazz:BAAANQAECgUIDgAAAA==.Zabenir:BAAANQAECgQIBwAAAA==.Zalrote:BAAANQADCggICAABNQAECggIJwAiAPoMAA==.Zaraina:BAAANQAECgQICwABNQAFFAQICQAQAPsTAA==.',
Ze='Zerototem:BAABNQAECoEhAAMDAAgKyBc6QAA1AgADAAgKyBc6QAA1AgAHAAIKGAn68QBtAAAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAFFAQICQAQAPsTAA==.',
['Çu']='Çuddleybunny:BAAANQADCgUIBQAAAA==.',
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
