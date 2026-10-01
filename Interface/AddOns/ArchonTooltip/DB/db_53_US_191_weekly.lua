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

local lookup = {'DeathKnight-Blood','Monk-Windwalker','Shaman-Restoration','Paladin-Protection','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Shaman-Elemental','Evoker-Preservation','Warrior-Protection','Hunter-BeastMastery','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Vengeance','Warrior-Arms','Paladin-Holy','Priest-Holy','Priest-Discipline','Priest-Shadow','Rogue-Subtlety',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acaciastrain:BAAANQADCgcJDQAAAA==.Acedk:BAABNQAECoEdAAIBAAkK9hsKHACbAgABAAkK9hsKHACbAgAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aerebos:BAAANQAECgEIAQABNQAECggIIgACAIMeAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAAANQAECgUICQABNQAECggIIgACAIMeAA==.',
Ag='Agua:BAAANQAECgQIBAAAAA==.',
Ak='Akashá:BAAANQADCgEIAQAAAA==.',
Al='Aladrius:BAEANQAECgIJAwAAAA==.Alexanderath:BAAANQAECgQIAwAAAA==.Alkatractite:BAAANQAECgQIBQAAAA==.Allenwalker:BAAANQAECgEIAQAAAA==.Allison:BAAANQADCgUIBQABNQAECggIGwADAKUOAA==.',
Am='Amey:BAAANQADCgUIBQAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJHAAEAJIMAA==.',
Ao='Aoeslave:BAABNQAECoEaAAMFAAcK+xV9PwCvAAAGAAYKSBVNtgD9AAAFAAMKDRB9PwCvAAAAAA==.',
Ap='Apk:BAAANQADCggIDwAAAA==.',
Ar='Arrisia:BAAANQAECgEIAQAAAA==.Arthedain:BAAANQAECgUICQAAAA==.Arthedaine:BAAANQAECgUIBQABNQAECgUICQAHAAAAAA==.',
As='Assano:BAAANQAECgQIBgABNQAECgcIHAAIAFgYAA==.',
Au='Auvry:BAABNQAECoEgAAIJAAkKdw+JFAA3AgAJAAkKdw+JFAA3AgAAAA==.',
Az='Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAAANQAECgQIBwAAAA==.Bakala:BAAANQAECgMIAwAAAA==.Barath:BAAANQAECgQIBwAAAA==.',
Be='Belegaer:BAAANQAECgYICwAAAA==.Belenos:BAAANQADCgYIDgABNQADCgYIDgAHAAAAAA==.Benmaverick:BAAANQAECgUIBwAAAA==.Bervin:BAAANQAECgQIBAAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAAANQAECgQICAAAAA==.',
Bo='Bobe:BAABNQAECoEdAAIKAAcKFh+qCQBcAgAKAAcKFh+qCQBcAgAAAA==.Bobedruid:BAAANQADCggIHgAAAA==.Bordok:BAAANQAECgIJAwAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Brunco:BAABNQAECoEWAAILAAcKXxfvXwADAgALAAcKXxfvXwADAgAAAA==.',
Ca='Captplanet:BAABNQAECoEgAAMMAAgKThcqFQBVAgAMAAgKThcqFQBVAgANAAYKFxfADgCzAQAAAA==.',
Ce='Ceindra:BAABNQAECoEZAAIOAAgKFxv+CAC2AgAOAAgKFxv+CAC2AgAAAA==.Celestria:BAAANQAECgMIBQAAAA==.Celiñ:BAAANQAECgEIAQAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Colbalt:BAAANQADCggIBwAAAA==.Constantinez:BAAANQAECggICAAAAA==.Cor:BAAANQAECgEIAQAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECoEkAAIPAAkKmhbAXgCUAgAPAAkKmhbAXgCUAgAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFIEFAAIQAAIK0xc9CwChAAAQAAIK0xc9CwChAAA1AAQKgS8AAxAACQp3HmsJACcDABAACQp3HmsJACcDABEAAQqWEQdxADoAAAAA.David:BAAANQAECggIDAAAAA==.',
De='Deadlyglow:BAAANQAECgQIBgAAAA==.Demiurgos:BAAANQAECgYICAAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAAANQAECgYIDwAAAA==.',
Dh='Dhiying:BAAANQADCgcIBwAAAA==.',
Di='Dirtface:BAAANQAECgYIEAAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECoEcAAISAAgK+xBSggC+AQASAAgK+xBSggC+AQAAAA==.',
Do='Dolemen:BAAANQAECgMIBwAAAA==.Domaon:BAABNQAECoEZAAIRAAcKWxlEKgD5AQARAAcKWxlEKgD5AQAAAA==.Domshammy:BAAANQADCggICAABNQAECgcIGQARAFsZAA==.Doubt:BAAANQAECgMIAwAAAA==.Dozy:BAABNQAECoEYAAISAAgKbR99NAC4AgASAAgKbR99NAC4AgAAAA==.',
Dr='Druidheelzz:BAAANQAECgIJAgAAAA==.Druissh:BAAANQAECgEIAQABNQAECgcIHAAIAFgYAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dunigan:BAAANQAECgQJBgAAAA==.Dunigen:BAAANQAECgEIAQAAAA==.',
Eb='Ebeast:BAAANQAECggIEwAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Facade:BAAANQAECgYIDQAAAA==.Facepalm:BAAANQAECgYIDQAAAA==.Falyy:BAAANQADCgMIAwAAAA==.Farmergeorge:BAAANQAECgQJCAAAAA==.',
Fe='Fentak:BAAANQADCgcIEwAAAA==.',
Fi='Fierytotes:BAAANQADCgQIBAABNQAECggIFAASAJcVAA==.',
Fo='Forbidenelf:BAABNQAECoEaAAISAAgKOh3BOQCjAgASAAgKOh3BOQCjAgAAAA==.Forgotmymeds:BAAANQAECgMIBAAAAA==.Foxmccloud:BAAANQAECgMIAwAAAA==.',
Fr='Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAAANQAECgYIEAAAAA==.',
Fu='Funkybooty:BAAANQABCgIIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAAANQAECgQIDQAAAA==.Gellywoo:BAAANQAECgMIBQAAAA==.Gemmarolizzy:BAAANQAECgEIAgAAAA==.',
Go='Golaoth:BAAANQAECgQIBwAAAA==.Gooftroupe:BAAANQAECgUIEAAAAA==.',
Gr='Grandmaster:BAAANQAECgYIDQABNQAECgEIAQAHAAAAAA==.Greymoon:BAAANQAECgIIAgAAAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Gu='Guayuelf:BAAANQAECgUIDAAAAA==.',
Ha='Haezi:BAAANQAECgMIAwABNQAECgUIEQAHAAAAAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgMIBAAAAA==.',
He='Helbafx:BAAANQADCggIKgAAAA==.',
Hi='Hino:BAAANQAECgQICAAAAA==.',
Ho='Homewrecker:BAAANQAECgMIAwAAAA==.Horuid:BAAANQADCgEIAQAAAA==.',
Ic='Icemàn:BAAANQADCgMIAwAAAA==.',
Id='Idrazil:BAAANQAECgcIEAAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBAAAAA==.',
In='Infectz:BAAANQAECggJAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAABNQAECoE0AAIDAAkKsCDSCQBSAwADAAkKsCDSCQBSAwAAAA==.Jakik:BAAANQADCgUIBQAAAA==.Jawn:BAAANQAECgQICwAAAA==.',
Je='Jessuss:BAAANQAECgIIAwAAAA==.',
Jh='Jha:BAAANQAECgUIDAAAAA==.',
Ju='Jude:BAAANQAECgYIDwAAAA==.Junipermoon:BAAANQADCgYIDgAAAA==.',
Ka='Kabub:BAAANQAECgUIDAAAAA==.Kalahandra:BAABNQAECoEYAAIMAAcKLhH3IgCuAQAMAAcKLhH3IgCuAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQABNQAECgkJHAAGAL0eAA==.Katotan:BAABNQAECoEWAAIMAAcK/hEaJQCYAQAMAAcK/hEaJQCYAQAAAA==.',
Ke='Kealestra:BAAANQAECgQIBwAAAA==.Keyboärd:BAAANQAECgMIAwAAAA==.',
Ki='Kippo:BAEANQADCgcIBwABNQAECgcICAAHAAAAAA==.Kittylover:BAAANQADCggIEAAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQADCgUIBgAAAA==.Kossnen:BAAANQAECgQIBQAAAA==.',
Kr='Krestisnack:BAAANQAECgQIBgAAAA==.',
Ku='Kuda:BAAANQAECgQIBwAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgMIBgAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECgQIBAAHAAAAAA==.',
['Kó']='Kóñä:BAAANQAECgQIBAAAAA==.',
La='Larke:BAAANQADCgYIBgAAAA==.Lasa:BAAANQAECgEIAQAAAA==.Lasloo:BAAANQAECgUIEwAAAA==.Laylani:BAABNQAECoEcAAIEAAcKyAcCLwANAQAEAAcKyAcCLwANAQAAAA==.',
Le='Lebronjames:BAAANQADCgQIBAAAAA==.Leynreite:BAAANQAECgEIAQAAAA==.',
Li='Lisan:BAAANQAECgUIDAAAAA==.Littledicey:BAABNQAECoEYAAITAAcK5Qg1NQCHAQATAAcK5Qg1NQCHAQAAAA==.',
Lu='Luciä:BAAANQAECgQIBwAAAA==.Lucymoon:BAAANQAECgYIBgAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Ly='Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Madness:BAAANQAECgUICQAAAA==.Maerion:BAAANQAECgQICQAAAA==.Magdeth:BAAANQADCgYIBgAAAA==.Marabelle:BAAANQAECgUICQAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQIBAAAAA==.Marixia:BAAANQAECgUICgAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAAANQAECgYIEAAAAA==.Mawgwa:BAAANQAECgMIAwAAAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECgUIEQAHAAAAAA==.Mero:BAABNQAECoEaAAMGAAgK/RooSQA0AgAGAAcKLRsoSQA0AgAFAAIKZRQVTACFAAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Moobear:BAAANQADCgUIBQAAAA==.Mosimo:BAAANQABCgIIAgAAAA==.Moushuhan:BAAANQAECgYIEQAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAAANQAECgYIBgAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAQAAAA==.Netherrogue:BAABNQAECoEZAAMUAAkKAiKLBACPAgAUAAcKkyKLBACPAgATAAIKByBFWAC9AAAAAA==.',
No='Noesis:BAAANQADCgQJBAAAAA==.',
Nu='Nuke:BAAANQAECgIIAgABNQAECgYIDAAHAAAAAA==.',
Ny='Nytehuntrix:BAAANQAFFAEIAQAAAA==.Nytemayer:BAABNQAECoEgAAMGAAkKHRyFNAB9AgAGAAgKfxyFNAB9AgAFAAMKtRNuOwC/AAABNQAFFAEIAQAHAAAAAA==.',
Ob='Obmakare:BAAANQAECgMIAwAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAAANQAECgEIAQAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgQIBgAAAA==.',
Op='Opiiknight:BAAANQAECgEIAQAAAA==.Opiishift:BAAANQAECgYIEwAAAA==.Opiishots:BAAANQAECgQIBAAAAA==.',
Or='Orcc:BAAANQADCgQIBQAAAA==.Orcloc:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.',
Pa='Paley:BAAANQAECgQIBAAAAA==.',
Pd='Pdgrimm:BAAANQADCgQIBAAAAA==.',
Pe='Performance:BAABNQAECoEkAAIVAAkKLRgtBQCSAgAVAAkKLRgtBQCSAgAAAA==.Peterturbo:BAAANQAECgQICAABNQABCgIIAgAHAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQADCgYIBgAAAA==.Poîsonivy:BAAANQAECgQIBwAAAA==.',
Ps='Psyrine:BAAANQADCgYIFQAAAA==.',
Qu='Qu:BAABNQAECoEkAAIWAAkKnxSaUgBRAgAWAAkKnxSaUgBRAgAAAA==.',
Ra='Rattlesnake:BAAANQADCggIGgAAAA==.Raymonnd:BAAANQADCgYIBgAAAA==.',
Re='Renägäde:BAAANQAECgYICgAAAA==.Retiredfurry:BAAANQAECgYIEgAAAA==.',
Ri='Ricodadawg:BAABNQAECoEnAAIPAAkKZCBqIgA9AwAPAAkKZCBqIgA9AwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQADCgYIDQAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgUIBQABNQAECgYIEgAHAAAAAA==.Runningshama:BAAANQAECgYIEgAAAA==.Rurahk:BAAANQAECgYIDwAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAAANQAECgMIAwAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saintsnyder:BAABNQAECoEcAAQEAAkKkgznLwAGAQAEAAUKdxTnLwAGAQASAAgKzAXg1AD9AAAXAAEKGgENBgEPAAAAAA==.Saithis:BAAANQAECgEIAgAAAA==.Sanorasong:BAAANQAECgQIBwAAAA==.Saphirra:BAAANQADCggJEQAAAA==.Sarylin:BAAANQAECgMIBAAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathpriest:BAABNQAECoEXAAQYAAkKLyGmCQBTAwAYAAgKYCSmCQBTAwAZAAEKpAeGIwAwAAAaAAEKrgwFZwAoAAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAAANQAECgMIAwAAAA==.',
Se='Severussnape:BAAANQAECgYIEAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.She:BAABNQAECoEXAAIbAAgKZgw9GwDWAQAbAAgKZgw9GwDWAQAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAgAAAA==.Shortstack:BAAANQAECgYIDAAAAA==.',
Si='Sinensis:BAAANQAECgQIBAAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAIIBQAQANMXAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAAANQAECgQIBQAAAA==.',
Sl='Slaycie:BAAANQAECgMIAwAAAA==.',
Sn='Sneek:BAAANQAECgQIBAAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAAANQAECgIIAgAAAA==.',
Sp='Spaghett:BAAANQAECgUIEQAAAA==.',
St='Stanger:BAAANQAECgQIBAABNQAECgUIEQAHAAAAAA==.Starlight:BAAANQAECgQIBQABNQAECgcIGAASAJElAA==.',
Sy='Syrden:BAABNQAECoEfAAIMAAgKMwu9JACbAQAMAAgKMwu9JACbAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAAANQAECgUIEgAAAA==.Tangylizard:BAAANQAECgYICQAAAA==.Tawainai:BAABNQAECoEXAAIPAAcKXxDZwQCxAQAPAAcKXxDZwQCxAQAAAA==.',
Te='Tessla:BAABNQAECoEcAAMIAAcKWBikSQABAgAIAAcKWBikSQABAgADAAIKtQHQ5gA9AAAAAA==.Tetragram:BAABNQAECoEiAAICAAgKgx7SDwCrAgACAAgKgx7SDwCrAgAAAA==.',
Th='Thelarï:BAAANQAECgYIEAAAAA==.Thors:BAAANQAECgcIDAAAAA==.Thundertoes:BAAANQAECgYIEAAAAA==.',
Ti='Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAAANQAECgMIAwAAAA==.Titåx:BAAANQADCgIIAgAAAA==.',
To='Tonik:BAAANQAECgUIDAAAAA==.Torgoth:BAAANQAECgQIBwAAAA==.Toshido:BAAANQAECgQIBQAAAA==.Totemtroll:BAAANQAECgEIAQAAAA==.Toy:BAAANQADCggICAAAAA==.',
Tr='Trevize:BAAANQADCgcIEwAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAQAAAA==.',
Ul='Ultane:BAAANQAECgEJAQAAAA==.',
Un='Unholypally:BAAANQADCggICgAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECoEkAAMSAAkKqxxlSgBoAgASAAgKYBtlSgBoAgAXAAcKOQR4hgA0AQAAAA==.Valiantaint:BAAANQAECgYICgABNQAECgkJJAASAKscAA==.Valiantroar:BAAANQAECgYIBgABNQAECgkJJAASAKscAA==.Vashon:BAAANQADCgQIBgAAAA==.',
Ve='Velherun:BAAANQAECgYIDwAAAA==.Vendel:BAABNQAECoEkAAIIAAkKoiMgBwCfAwAIAAkKoiMgBwCfAwAAAA==.Vexxaa:BAAANQAECgQIBwAAAA==.',
Vi='Virajr:BAAANQAECgIIAgAAAA==.Vissiction:BAAANQAECgYIDgAAAA==.Vistine:BAAANQAECgQIBwABNQAECgcIHAAIAFgYAA==.Vitez:BAAANQAECgUIDAAAAA==.',
Wa='Waterslide:BAAANQADCgMIAwAAAA==.',
We='Wendy:BAABNQAECoEbAAIDAAgKpQ7PXwCYAQADAAgKpQ7PXwCYAQAAAA==.',
Wh='Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAAANQAECgYIDAAAAA==.Winkster:BAAANQAECgEIAQAAAA==.',
Xa='Xanadu:BAABNQAECoEZAAMZAAcKdB4JBABiAgAZAAcKdB4JBABiAgAYAAEKUxKOxgA3AAAAAA==.Xarinia:BAAANQADCgcICwAAAA==.',
Xb='Xbear:BAAANQAECgQIBwABNQAFFAIIBQATABoVAA==.',
Xd='Xdynasty:BAACNQAFFIEFAAMTAAIKGhUbEgBVAAATAAEKWBkbEgBVAAAbAAEK3BAUDwBSAAA1AAQKgS8AAxsACQocIEUGAAoDABsACQouHEUGAAoDABMABAoKHbA9AFABAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYICAABNQAECgEIAQAHAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAECgYIDAAHAAAAAA==.',
Za='Zabazz:BAAANQAECgUIDgAAAA==.Zabenir:BAAANQAECgIJAwAAAA==.Zaraina:BAAANQAECgQIBwABNQAFFAIIBQAQANMXAA==.',
Ze='Zerototem:BAABNQAECoEaAAIDAAgK2RCOXwCZAQADAAgK2RCOXwCZAQAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAFFAIIBQAQANMXAA==.',
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
