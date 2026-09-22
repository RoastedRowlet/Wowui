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

local lookup = {'Paladin-Holy','Hunter-BeastMastery','Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Assassination','Druid-Balance','Mage-Arcane','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','Rogue-Subtlety','Druid-Guardian','Mage-Frost','Priest-Shadow','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Feral','Paladin-Retribution','Shaman-Restoration','Warrior-Protection','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Blood','Evoker-Preservation','Evoker-Devastation','Druid-Restoration','Priest-Holy','Paladin-Protection','Priest-Discipline','Shaman-Elemental','Hunter-Survival',}
local provider = {region='US',realm="Dath'Remar",name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaronius:BAAANQADCggJEgAAAA==.',
Ab='Abduhl:BAAANQABCgEIAQAAAA==.',
Ad='Ade:BAAANQAECgYJDAAAAA==.Adezardre:BAAANQAECgEJAgAAAA==.Admetriell:BAAANQAECgIIAgABNQAECggIGwABAE0JAA==.Advosary:BAAANQADCggIEAAAAA==.',
Af='Affection:BAAANQADCgMJAwAAAA==.Afflictid:BAAANQABCgIIAgAAAA==.Afterburn:BAAANQAECgQIBAAAAA==.',
Ai='Aigmokthar:BAABNQAECoEaAAICAAgKjxfJLACAAgACAAgKjxfJLACAAgAAAA==.',
Ak='Akiriah:BAAANQADCggICAAAAA==.Akirial:BAAANQAECgYJCwABNQAECgYJDAADAAAAAA==.Aklo:BAAANQADCggJIgAAAA==.',
Al='Alamysia:BAAANQADCgYICwAAAA==.Albertfist:BAAANQADCgMIAwAAAA==.Aletech:BAAANQAECgMIAwAAAA==.Ali:BAAANQAECgQJDAAAAA==.Aliesá:BAAANQAECgEJAQAAAA==.Alilea:BAAANQADCgYIBgAAAA==.Alimagus:BAAANQAECgYICgABNQAECgkJIQAEAEQfAA==.Alisandrah:BAACNQAFFIEIAAMFAAUKixHbCAAuAQAFAAQK5Q7bCAAuAQAGAAEKJBw7DQBfAAA1AAQKgSMABAYACQpgIp4IAFcCAAUACAqjIUETAPYCAAYABwrBHp4IAFcCAAcAAQrDGUYcAEkAAAAA.Alison:BAAANQADCgYIGAAAAA==.Allakeer:BAABNQAECoEdAAIIAAkK8x5dEwBkAgAIAAkK8x5dEwBkAgAAAA==.Altarios:BAAANQADCggIHAAAAA==.Alyyix:BAAANQADCgYIGgAAAA==.',
Am='Amber:BAAANQAECgMJBQAAAA==.Amberlicious:BAAANQABCggIFQABNQAECgMJBQADAAAAAA==.Amberlily:BAAANQADCggIDgABNQAECgMJBQADAAAAAA==.Ambertastic:BAAANQADCgcIGwABNQAECgMJBQADAAAAAA==.Amilandris:BAABNQAECoErAAIJAAkKYiDpCgBLAwAJAAkKYiDpCgBLAwAAAA==.Amitié:BAAANQADCgYIBgAAAA==.',
An='Analalea:BAAANQADCgcIEAAAAA==.Analdrainal:BAABNQAECoEXAAIEAAgKxCLfFwApAwAEAAgKxCLfFwApAwAAAA==.Anghellic:BAAANQADCgYJBgAAAA==.Annaris:BAAANQADCggIEQAAAA==.',
Ap='Apophani:BAAANQADCggIGgAAAA==.Appolo:BAAANQAECgYJDgAAAA==.',
Ar='Arcaidion:BAAANQAECggICAAAAA==.Arcanegasm:BAABNQAECoEVAAIKAAgK4x6dSwCoAgAKAAgK4x6dSwCoAgAAAA==.Archii:BAAANQADCgcIBwABNQAECgcJGgAKAJ0YAA==.Archslayer:BAAANQAECgMJBQAAAA==.Aresdeekx:BAAANQAECgUIBwABNQAECgcIFAALAIgbAA==.Arneus:BAAANQAECgIJAgAAAA==.Arnir:BAAANQAECgQJDAAAAA==.Arriving:BAAANQAECgcJEwAAAA==.Artaq:BAAANQAECgEJAgAAAA==.Artoriöus:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.Arvanon:BAAANQAECgUIEwAAAA==.',
As='Ashanar:BAAANQAECgMJCAAAAA==.Asharla:BAAANQAECgQJBgAAAA==.Ashbringa:BAAANQAECgMJBQAAAA==.Ashhman:BAAANQAECgUJBQAAAA==.Ashhunt:BAABNQAECoEdAAICAAgKxhqfJQChAgACAAgKxhqfJQChAgAAAA==.Ashmend:BAAANQAECgEJAgAAAA==.Asorrow:BAAANQAECgQICAABNQAFFAIJAgADAAAAAA==.Assatur:BAAANQADCgYIBgAAAA==.Astarna:BAAANQAECgQJBwAAAA==.Asteríx:BAAANQADCgUICQAAAA==.Astier:BAAANQADCgEIAQAAAA==.',
At='Atiatal:BAAANQAECgEJAQAAAA==.Atlasursidae:BAAANQAECgMIBgAAAA==.Atoniah:BAAANQAECgQJCAAAAA==.',
Au='Auraz:BAAANQAECggJDQAAAA==.',
Av='Avelinna:BAAANQAECgMJBgAAAA==.',
Aw='Awan:BAAANQADCgYIEgAAAA==.',
Az='Aztrayel:BAAANQAECgEJAQAAAA==.',
Ba='Baalial:BAAANQAECgQJBwAAAA==.Baboya:BAAANQAECggIAQAAAA==.Baelgrim:BAAANQAECgIJAgAAAA==.Baly:BAAANQADCgYIDAABNQAECgkJGwAFAOsWAA==.Bangbangbro:BAAANQAECgMJCAAAAA==.Barium:BAAANQADCgYIDAAAAA==.',
Be='Belfrostbolt:BAAANQAECgEJAQAAAA==.Bentt:BAAANQABCgcICgAAAA==.Bettÿ:BAAANQADCgYIBgABNQAECgMJBAADAAAAAA==.',
Bi='Bigjawden:BAAANQADCggIGAAAAA==.Billbee:BAAANQAECgIJAgAAAA==.Bimbohaggins:BAAANQAECgMIBAABNQAECgQJEAADAAAAAA==.Bimbò:BAAANQAECgQJDAAAAA==.Binchicken:BAAANQAECgQIBgAAAA==.Bingler:BAAANQABCgMIAwAAAA==.',
Bj='Bjornhammerz:BAAANQADCgYJBgABNQAECgYICgADAAAAAA==.Bjornshockz:BAAANQAECgYICgAAAA==.',
Bl='Blaz:BAAANQAECgQIDAAAAA==.Blockz:BAAANQADCggIDwAAAA==.Bloodboi:BAAANQADCgcIDwABNQAECgQJBAADAAAAAA==.Bloodyeddy:BAAANQAECgEIAQAAAA==.Bluecups:BAAANQAECgUJCQAAAA==.Bluey:BAAANQADCgcIEgAAAA==.',
Bo='Bobbyboom:BAAANQAECgQIBgAAAA==.Bonedecays:BAAANQADCgMIBAAAAA==.Bontoad:BAAANQAECgMIBQAAAA==.',
Br='Brewaresx:BAABNQAECoEUAAMLAAcKiBu9CQASAgALAAcKiBu9CQASAgAMAAYKUwJUNwClAAAAAA==.Broxaschor:BAAANQABCgQIAwAAAA==.Brutus:BAAANQAECgcJEwAAAA==.',
Bu='Bubbleduck:BAAANQAECgIJAgAAAA==.Buggzz:BAABNQAECoEYAAICAAcKuCQFHADSAgACAAcKuCQFHADSAgAAAA==.',
Bz='Bzlthazyr:BAABNQAECoEYAAINAAkKPxh8GgCTAgANAAkKPxh8GgCTAgAAAA==.',
Ca='Cahtbl:BAAANQAECgIJAgAAAA==.Calasandria:BAAANQAECgIJAgABNQAECgUIDQADAAAAAA==.Callin:BAAANQAECgEJAQAAAA==.Calyx:BAAANQADCgYICQAAAA==.Cartier:BAAANQAECgIIAgABNQAECgYJDwADAAAAAA==.Casay:BAAANQAECgUJBwAAAA==.Casbot:BAABNQAECoEcAAMOAAkKExhSCADPAgAOAAkKExhSCADPAgAIAAIKLgY2VgBeAAAAAA==.Cashmere:BAAANQAECgQICgABNQAECgYJDwADAAAAAA==.Castalight:BAAANQAECgQJBgAAAA==.Castlebravo:BAAANQADCgYIBgAAAA==.',
Ch='Changes:BAAANQADCgcJDAAAAA==.Charish:BAAANQADCgEIAQAAAA==.Charlee:BAAANQADCgUIEAAAAA==.Chirran:BAABNQAECoEoAAIPAAcKkx/MBgB4AgAPAAcKkx/MBgB4AgAAAA==.Chxdzilla:BAACNQAFFIEFAAIEAAMKYgNeEwC7AAAEAAMKYgNeEwC7AAA1AAQKgSQAAgQACQqQFgU6AH4CAAQACQqQFgU6AH4CAAAA.',
Ci='Cinnamõn:BAAANQABCgYICQAAAA==.Citryn:BAAANQAECgEIAQABNQAECgkJHQAMAKoeAA==.',
Co='Codexo:BAAANQADCggICAAAAA==.Colpamia:BAAANQABCgIJAgAAAA==.Corldrin:BAAANQAECgEIAQAAAA==.Coronis:BAAANQAECgIJBAAAAA==.Corriana:BAAANQADCgcIFQABNQAECgMJBgADAAAAAA==.Corwin:BAAANQADCgYIGgAAAA==.',
Cr='Crazee:BAABNQAECoEjAAMKAAkKjCKEDwCAAwAKAAkKjCKEDwCAAwAQAAEKhSLSIwBiAAAAAA==.Cruz:BAAANQAECgQICgAAAA==.Crystalflame:BAAANQAECgQJCgAAAA==.Crìsp:BAAANQADCgYICwABNQADCggICwADAAAAAA==.',
Ct='Ctshammy:BAAANQAECgUIDQAAAA==.',
Cu='Cultistt:BAABNQAECoEbAAIRAAgKtghwIwCXAQARAAgKtghwIwCXAQAAAA==.Cursedyou:BAAANQAECgUICQAAAA==.Curserot:BAAANQAECgUICgAAAA==.Cuteselenes:BAAANQADCgIIAgAAAA==.',
Cy='Cynal:BAABNQAECoEWAAICAAgK0gs+UQD9AQACAAgK0gs+UQD9AQAAAA==.',
Da='Daddyy:BAAANQAECgIIBAABNQAECgkJIwAKAIwiAA==.Dammo:BAAANQADCggIGgAAAA==.Dantallion:BAAANQADCgUICAABNQAECgEJAgADAAAAAA==.Dardroc:BAAANQADCgMIAwAAAA==.Darkholme:BAAANQAECgUJCwAAAA==.Darkk:BAAANQADCgUJBgAAAA==.Darthdraik:BAAANQAECgMJBQAAAA==.',
Dc='Dcver:BAABNQAECoEvAAIFAAgK0B4cGwDFAgAFAAgK0B4cGwDFAgAAAA==.',
Dd='Ddraigfach:BAAANQABCgMIAwAAAA==.',
De='Deademeat:BAAANQADCgMIAwAAAA==.Deadlynewbz:BAABNQAECoEcAAMIAAkKCCVeAQC1AwAIAAkKCCVeAQC1AwAOAAMKth+zKwAFAQAAAA==.Deathboom:BAAANQADCgUIBQABNQAECgkJIAASAOoXAA==.Deathbow:BAAANQADCgcIBwAAAA==.Deathbyshoe:BAAANQAECgIJBgAAAA==.Deathivy:BAAANQADCgcJHAAAAA==.Deathjam:BAAANQAECgQICwAAAA==.Deathmore:BAAANQAECgIIBAAAAA==.Deathshrine:BAAANQADCggIDQAAAA==.Decypha:BAAANQAECgcJEwAAAA==.Deidius:BAAANQADCgUIBQAAAA==.Deiwos:BAAANQAECgQICgAAAA==.Delichtable:BAAANQADCgcIGwABNQAECgMJBQADAAAAAA==.Deltora:BAAANQAECgEIAQABNQAECgYJCgADAAAAAA==.Demodog:BAAANQAECgQJEAAAAA==.Demonicnight:BAAANQAECgcJCQAAAA==.Derryth:BAAANQAECgYIDAAAAA==.Devpro:BAAANQAECgUJDAAAAA==.Devrothas:BAAANQADCgIJAgABNQAECgUJDAADAAAAAA==.Deweysan:BAAANQAECgcIDAAAAA==.Dexillo:BAABNQAECoEjAAMTAAkKHRqJEQC6AgATAAkKHRqJEQC6AgASAAgK8A6dIgDfAQAAAA==.',
Dh='Dhaveira:BAAANQAECgcIEAAAAA==.',
Di='Diggyhole:BAAANQADCgIIAgAAAA==.Divinegirly:BAAANQAECgQJBwAAAA==.',
Do='Dodgeanaxe:BAACNQAFFIEFAAIEAAIKFRC+GQCNAAAEAAIKFRC+GQCNAAA1AAQKgTkAAgQACQpSIf4NAGoDAAQACQpSIf4NAGoDAAAA.Dojoe:BAAANQAECgIIBgABNQAECgcJDgADAAAAAA==.Dorá:BAAANQAECgEJAQAAAA==.',
Dr='Dracnock:BAAANQAECgcJEgAAAA==.Drinian:BAAANQAECgMJBgAAAA==.',
Du='Ducker:BAACNQAFFIEFAAIMAAMKKCUUBABOAQAMAAMKKCUUBABOAQA1AAQKgR8AAgwACQpUJqMAAOUDAAwACQpUJqMAAOUDAAAA.',
Dy='Dylexd:BAAANQAECgYJDAAAAA==.',
Ea='Eatmybolts:BAAANQAECgYIBgAAAA==.',
Ec='Eccentricity:BAAANQAECgQICgAAAA==.',
El='Eldarion:BAAANQAECgMJAwAAAA==.Electricmon:BAAANQAECgUICwABNQAFFAIIBQAEABUQAA==.Elementi:BAAANQADCgIIAgAAAA==.Elfy:BAAANQADCgQIBAABNQAECgIJAgADAAAAAA==.Eliasidris:BAAANQAECgUICgABNQAECggIFwAUAH8KAA==.Elmaco:BAAANQAECgYJDgAAAA==.Elphkilla:BAAANQADCggICAAAAA==.Elroth:BAAANQADCgYICgAAAA==.Elseapi:BAAANQAECgMJCAAAAA==.Elyssae:BAABNQAECoEWAAIKAAgKwR4AQwDCAgAKAAgKwR4AQwDCAgAAAA==.',
En='Endarios:BAAANQAECgMJBAAAAA==.Endsplit:BAAANQAECgUJCAAAAA==.Ent:BAAANQAECgIJBAAAAA==.',
Er='Erzalockhart:BAAANQAECgEIAQAAAA==.',
Es='Esmaralda:BAAANQADCgcJFAAAAA==.',
Ev='Everleaf:BAAANQADCgQIBgAAAA==.Eviion:BAAANQAECgcIEAABNQAECggIFwAUAH8KAA==.',
Ez='Ezoth:BAAANQAECgEJAgAAAA==.',
Fa='Fallendivine:BAABNQAECoEWAAIKAAgKEQwHmADcAQAKAAgKEQwHmADcAQAAAA==.',
Fe='Feetenjoyer:BAAANQADCgMJAwAAAA==.Feipo:BAABNQAECoEdAAIKAAkKpxuzmQDYAQAKAAkKpxuzmQDYAQAAAA==.Felissa:BAAANQAECgIIAgABNQAECgQJBAADAAAAAA==.Fensmage:BAAANQAECgEJAQAAAA==.Feralbuffkty:BAABNQAECoEYAAINAAkKcx1lEQDtAgANAAkKcx1lEQDtAgABNQAECggIFAAVAEsfAA==.Fere:BAAANQAECgcJEgAAAA==.Feurekt:BAABNQAECoEoAAIEAAcKyR8UPgBuAgAEAAcKyR8UPgBuAgAAAA==.',
Fi='Finitaur:BAAANQADCgQIBwAAAA==.Fiz:BAAANQADCggICAABNQAFFAIIBQAHAHQRAA==.',
Fl='Flashinlight:BAAANQAECgMJBQAAAA==.Flashstép:BAAANQAECgUIDQAAAA==.Flipside:BAAANQAECgYJDAAAAA==.',
Fo='Fomor:BAAANQAECgUJCgAAAA==.Forbs:BAAANQAECgIJAQAAAA==.Foreignerr:BAABNQAECoEhAAIEAAkKRB99GAAlAwAEAAkKRB99GAAlAwAAAA==.',
Fr='Franziscka:BAAANQADCggIEwAAAA==.Friggincute:BAAANQADCgEIAQAAAA==.',
Fu='Furbold:BAAANQAECgYIDwABNQAECggIBQADAAAAAA==.',
['Fí']='Fíredup:BAAANQAECgEIAQABNQAECgYJDwADAAAAAA==.',
Ga='Galeira:BAAANQAECgMIBQAAAA==.Gallene:BAACNQAFFIEHAAIEAAMKPxvYDgD8AAAEAAMKPxvYDgD8AAA1AAQKgUUAAgQACQr8JPoDAMUDAAQACQr8JPoDAMUDAAAA.Gandallf:BAAANQADCgUIDgABNQAECgIIAwADAAAAAA==.Garakarak:BAAANQAECgUJCAAAAA==.Garthinian:BAAANQADCgYICQAAAA==.Garthpally:BAAANQADCgUIBQAAAA==.',
Ge='Genimaculata:BAAANQAECgcJEwAAAA==.Germ:BAAANQADCgIIAgAAAA==.Gerothos:BAAANQADCgQIBAAAAA==.Geîsha:BAAANQADCgMIAwAAAA==.',
Gh='Ghislaine:BAAANQADCggIDQAAAA==.Ghöst:BAAANQAECgQIBAAAAA==.',
Gl='Gladios:BAAANQAECgEJAQAAAA==.Glarry:BAAANQADCggICAABNQAECgkJHgABAC8eAA==.Glidelicator:BAAANQAECgcIEQAAAA==.',
Go='Goodasnew:BAAANQADCggJGwAAAA==.Gooditoshoes:BAAANQAECgEJAQAAAA==.Gortopia:BAAANQADCgYIDwAAAA==.Goshin:BAAANQADCgMJAwAAAA==.Gosublood:BAAANQAECgYIDQAAAA==.Gosupriest:BAAANQAECgUJCQABNQAECgYIDQADAAAAAA==.',
Gr='Graggy:BAABNQAECoEeAAMBAAkKLx4eDAAwAwABAAkKLx4eDAAwAwAWAAEKmwsNGAE5AAAAAA==.Grapejelly:BAABNQAECoEZAAISAAcKVRz2FgBfAgASAAcKVRz2FgBfAgAAAA==.Grashk:BAAANQAECgUJCAAAAA==.Grimbel:BAAANQAECgUJCAAAAA==.',
['Gø']='Gødspeed:BAAANQAECgIJAgAAAA==.',
Ha='Hadeshunt:BAAANQAECgQICwAAAA==.Halibelle:BAAANQADCgYJBgAAAA==.Halzarius:BAAANQAECgQJCwAAAA==.Handyshammy:BAAANQAECgYJEAABNQAECgcIGgAEAEwYAA==.Handywar:BAABNQAECoEaAAIEAAcKTBg5YgDqAQAEAAcKTBg5YgDqAQAAAA==.Hans:BAAANQAECgMJCAAAAA==.Harleybear:BAAANQADCgUJEgAAAA==.',
Hi='Hitamnya:BAAANQABCgQIBgABNQAECggIFwAUAH8KAA==.',
Ho='Holyknox:BAAANQAECggIBQAAAA==.Holymender:BAAANQADCggJDgAAAA==.Holymick:BAAANQAECggJCAAAAA==.',
Hu='Hulkamania:BAAANQADCgUICAAAAA==.Humble:BAAANQAECgcJDwAAAA==.',
Hy='Hydromender:BAAANQAECgYJDwAAAA==.Hyperactiv:BAAANQAECgQJBAAAAA==.Hypothermia:BAAANQAECgMIAwAAAA==.',
['Hø']='Høpeless:BAAANQAECgcJEQAAAA==.',
Ic='Icyblast:BAAANQADCgIIBAAAAA==.Icycookiex:BAAANQADCggJDgABNQAECgUIDgADAAAAAA==.Icymilkyx:BAAANQAECgUIDgAAAA==.',
Ig='Igneel:BAAANQADCgYIDAAAAA==.',
Il='Illigniteyou:BAABNQAECoErAAIKAAgKySBGMgD3AgAKAAgKySBGMgD3AgAAAA==.Illiranii:BAAANQADCgYIBgABNQAECgMJBgADAAAAAA==.Illumine:BAAANQAECgEIAQAAAA==.',
In='Inosolan:BAAANQAECgMJBAAAAA==.Inurfacevegi:BAAANQAECgIJAgAAAA==.',
Io='Iolololol:BAAANQAECgEIAgABNQAECgkJIQANALoXAA==.Iozt:BAAANQAFFAEIAQAAAA==.',
Ir='Irralis:BAAANQAECgUIBQAAAA==.Irritable:BAAANQAECgQJCQAAAA==.Irvina:BAABNQAECoElAAICAAcKgBtgPgA9AgACAAcKgBtgPgA9AgAAAA==.Irvinebrown:BAAANQADCgIIBAABNQAECgcIJQACAIAbAA==.Irvinia:BAAANQADCggIHAABNQAECgcIJQACAIAbAA==.',
Is='Iskarius:BAAANQAECgUJCAAAAA==.Istenn:BAAANQAECgMJBAAAAA==.',
It='Ithyl:BAAANQAECgEJAQAAAA==.Itzshammy:BAABNQAECoEWAAIXAAgKqh51HACrAgAXAAgKqh51HACrAgAAAA==.',
Iv='Ivanoviaa:BAAANQADCgMIAwAAAA==.',
Ja='Jabmojorjo:BAAANQADCgMIAwAAAA==.Jackdaw:BAAANQABCgIIAgAAAA==.Janinda:BAABNQAECoEVAAIWAAgKzCJbLgCgAgAWAAgKzCJbLgCgAgAAAA==.Jastina:BAAANQAECgQICwAAAA==.Jaszz:BAAANQAECgcJEQAAAA==.',
Jb='Jb:BAAANQADCggICwAAAA==.',
Je='Jelly:BAAANQADCggIFAAAAA==.Jengil:BAAANQAECgQIBgAAAA==.Jengol:BAAANQADCgcIBwAAAA==.Jesto:BAABNQAECoEpAAIYAAgK5R85BADiAgAYAAgK5R85BADiAgAAAA==.',
Jh='Jhonn:BAAANQAECgMIBQAAAA==.',
Jo='Jodiefroster:BAAANQAECgEIAQAAAA==.Joeseppe:BAAANQAECgYIDAABNQAECgcJDgADAAAAAA==.Joeslildk:BAAANQAECgcJDgAAAA==.Joshst:BAAANQADCgcIHQAAAA==.Josta:BAAANQAECgMIAwABNQAECggJKQAYAOUfAA==.Josto:BAAANQADCgcIEQABNQAECggJKQAYAOUfAA==.Jovyll:BAAANQAECgMIBgAAAA==.Joyboyluffy:BAAANQAECgEJAQAAAA==.',
Ju='Jurodice:BAABNQAECoEbAAIBAAgKTQloUgCoAQABAAgKTQloUgCoAQAAAA==.',
['Jå']='Jårko:BAAANQADCgYJCwAAAA==.',
Ka='Kaahla:BAAANQADCgEIAQAAAA==.Kaelinth:BAAANQADCgcJCgAAAA==.Kaelyth:BAAANQAECgMJCAAAAA==.Kamakazie:BAAANQAECgQICAAAAA==.Kamelle:BAAANQADCggJDgAAAA==.Karmerre:BAAANQAECgEJAQAAAA==.Karramerre:BAAANQADCgUIBQABNQAECgEJAQADAAAAAA==.Kaydeebug:BAAANQAECgQIDwAAAA==.Kayna:BAABNQAECoEkAAIMAAcKdA67IACKAQAMAAcKdA67IACKAQAAAA==.',
Ke='Kellanis:BAAANQAECgcJDAAAAA==.Kelugar:BAAANQADCgIIAgAAAA==.Kerenarye:BAABNQAECoESAAMZAAkKcR8eAgALAwAZAAgKwiEeAgALAwASAAcKCgptLACCAQAAAA==.Keyez:BAAANQADCgEIAQABNQAECggJGwARAEMLAA==.',
Kh='Khaladore:BAAANQAECgYJDgAAAA==.Kharazhan:BAAANQAECgQJCQAAAA==.',
Ki='Kiilbill:BAAANQADCgcICwABNQAECgQJEAADAAAAAA==.Killshotbob:BAAANQAECgIJAgAAAA==.Kinkyheaven:BAAANQAECgQIBgAAAA==.Kinnigit:BAABNQAECoEXAAIaAAcKtwc1NwA7AQAaAAcKtwc1NwA7AQAAAA==.Kinstalz:BAAANQAECgUJCAAAAA==.Kiotia:BAAANQADCgYJEQAAAA==.Kipp:BAAANQAECgYJCgAAAA==.Kiril:BAAANQADCgUIBQAAAA==.Kirky:BAAANQADCgUJCgAAAA==.Kithraah:BAABNQAECoEaAAMaAAgKZRCpJADQAQAaAAgK1w6pJADQAQANAAcKywyiQQCNAQAAAA==.Kithrah:BAAANQAECgcICAABNQAECggIGgAaAGUQAA==.Kithrâh:BAAANQAECgEIAQABNQAECggIGgAaAGUQAA==.',
Kn='Knifeparty:BAAANQAECgUIBQAAAA==.',
Ko='Kolugar:BAABNQAECoEfAAIbAAkKEST0AwCXAwAbAAkKEST0AwCXAwAAAA==.Konkar:BAAANQAECgQJDAAAAA==.',
Kr='Kradon:BAAANQAECgQJBwAAAA==.Kreedan:BAAANQADCgcJBwABNQAECgUIDwADAAAAAA==.Kruphix:BAAANQAECgYIDQAAAA==.Krysania:BAAANQADCgQIBAABNQAECgYJDgADAAAAAA==.',
Ku='Kudreanne:BAAANQADCgYIGgAAAA==.Kuri:BAAANQADCggICAAAAA==.Kuzzo:BAAANQAECgIJAgAAAA==.',
La='Laiceeshay:BAAANQAECgcJEwAAAA==.Lars:BAAANQAECgYJEAAAAA==.Larxe:BAAANQAECgUIBQAAAA==.',
Le='Legendaïry:BAAANQAECgEJAgAAAA==.Letmedie:BAAANQAECgUIDgAAAA==.Lexillo:BAAANQAECgUICAAAAA==.',
Li='Liaravara:BAAANQAECgEIAQABNQAECgIJAgADAAAAAA==.Lightmender:BAAANQADCgQIBAAAAA==.Lightschamp:BAAANQADCgQIBAABNQAECgIJAwADAAAAAA==.Lilhunty:BAAANQADCgMIAwAAAA==.Lilldemon:BAAANQADCgcIDgAAAA==.Lizzo:BAABNQAECoEaAAMcAAcKrRq0EgApAgAcAAcKrRq0EgApAgAdAAIKmAjBKABmAAAAAA==.',
Lo='Lorieyxo:BAAANQAECgEJAQAAAA==.Lorrim:BAAANQAECgMJBAAAAA==.Louron:BAAANQADCgYIBgAAAA==.',
Lu='Luena:BAAANQADCgMIAwAAAA==.Lunabi:BAAANQAECgQJBQABNQAECgkJHQAMAKoeAA==.Lute:BAAANQADCgYIBgAAAA==.Luxdae:BAAANQADCgEIAQAAAA==.',
Ly='Lyrannia:BAAANQAECgYJEwAAAA==.Lyrindanna:BAAANQADCgEIAQAAAA==.Lyth:BAAANQAECgcJEwAAAA==.',
['Lá']='Láiken:BAAANQADCgYJGwAAAA==.',
Ma='Madmoxxie:BAAANQADCgUIBQAAAA==.Mageapayne:BAAANQADCgYJBgAAAA==.Magetom:BAAANQAECgEIAQAAAA==.Maghan:BAAANQADCgQICAAAAA==.Magicus:BAAANQAECgMJBAAAAA==.Magikaze:BAAANQAECgYJDAAAAA==.Mahgo:BAAANQAECgYICgAAAA==.Maidenkio:BAAANQADCgEIAQAAAA==.Maikara:BAAANQAECgIJAwAAAA==.Majinoodle:BAAANQADCgcIBwAAAA==.Malfalcator:BAAANQADCgMIAwAAAA==.Mantori:BAAANQADCgEIAQAAAA==.Marieh:BAAANQAECgEJAQAAAA==.Martha:BAAANQABCgcICAAAAA==.Masscarnage:BAABNQAECoEaAAIFAAgK9hgDJgCMAgAFAAgK9hgDJgCMAgAAAA==.Maywina:BAAANQAECggIEQABNQAECgkJKwAJAGIgAA==.Mazhun:BAAANQAECgUJCgAAAA==.',
Me='Meaculpa:BAABNQAECoEYAAMWAAcK+Q5gegCPAQAWAAcK+Q5gegCPAQABAAQK7gNDqQCpAAAAAA==.Mediqua:BAAANQADCgQIAQAAAA==.Megaflame:BAAANQADCgYIFwAAAA==.Mekkii:BAAANQADCgIIAgABNQAECgkJIQANALoXAA==.Mekky:BAABNQAECoEhAAINAAkKuhfeFwCrAgANAAkKuhfeFwCrAgAAAA==.Melonheadx:BAAANQADCgIIAgAAAA==.Meltharion:BAAANQAECgEJAgAAAA==.Mercerful:BAAANQADCgQIBwAAAA==.Mereaux:BAAANQADCggICwAAAA==.Methex:BAAANQAECgcJDAAAAA==.Metzger:BAAANQAECgIJAgAAAA==.',
Mi='Mingi:BAAANQADCggJDwABNQAECgYIFQAGAP0YAA==.Minigore:BAABNQAECoEnAAICAAgKtR81MQBuAgACAAgKtR81MQBuAgAAAA==.Mirya:BAAANQAECgEJAQAAAA==.Mishamigo:BAAANQAECgUICgAAAA==.Missharmony:BAAANQAECgUJCgAAAA==.Misstickles:BAAANQAECgQIBgAAAA==.',
Mo='Moistfisting:BAAANQADCggICAABNQAFFAIJBQAJAIgTAA==.Moistpawjob:BAACNQAFFIEFAAIJAAIKiBPqEACnAAAJAAIKiBPqEACnAAA1AAQKgSAAAwkACQqhJPkHAG4DAAkACQqhJPkHAG4DAB4AAgoOG0Q8AJYAAAAA.Moistpole:BAAANQADCgcJDAAAAA==.Mojostormale:BAAANQADCgEIAQAAAA==.Monanarr:BAAANQADCgEIAgABNQAECgIJBgADAAAAAA==.Monmonk:BAAANQAECgIJBgAAAA==.Moograin:BAAANQABCgQIBAAAAA==.Moonalisa:BAAANQADCgYJGQAAAA==.Moondropz:BAAANQAECgEIAQAAAA==.Moonsblood:BAAANQAECgQJBwAAAA==.Moontara:BAAANQAECgYIDgAAAA==.Moopsy:BAAANQAECgQJCgAAAA==.Mops:BAAANQAECgIIBQAAAA==.',
Mu='Muldoom:BAAANQABCgQIAgAAAA==.Mur:BAAANQAECgUJCAAAAA==.Murdertoys:BAAANQADCgcIBwAAAA==.',
My='Mycotoxin:BAAANQAECgMIBAAAAA==.Myrrdan:BAAANQAECgYICgAAAA==.Myrrh:BAAANQADCgEIAQAAAA==.Mysst:BAAANQAECgMJBgAAAA==.Mysteerie:BAAANQAECgUJCgAAAA==.Mythlogic:BAAANQAECgQJCwAAAA==.Mythsham:BAAANQADCgUIEgAAAA==.',
['Má']='Mángo:BAABNQAECoEbAAMFAAgKYhDoTADrAQAFAAgKcw7oTADrAQAGAAUKFwu/JwATAQAAAA==.',
['Mí']='Místress:BAAANQAECgEJAQAAAA==.',
['Mù']='Mùshu:BAAANQADCgYIBgAAAA==.',
Na='Nardaran:BAAANQAECggIDAAAAA==.Natsumi:BAAANQAECgMJAwAAAA==.',
Ne='Needcoffee:BAAANQADCgcIFAAAAA==.Neemixa:BAAANQAECgEJAQAAAA==.Neonh:BAAANQADCggIGgAAAA==.',
Ni='Nicksshaman:BAAANQADCgEIAQAAAA==.Nightwissh:BAAANQAECgMICAAAAA==.Nitestar:BAAANQADCgUIEAAAAA==.Nitevoker:BAAANQAECgMIBgAAAA==.',
No='Nocturnus:BAAANQADCgQJDAAAAA==.Nordvoker:BAAANQAECgcJEwAAAA==.Nospheratu:BAABNQAECoEpAAIKAAgKAht7XgByAgAKAAgKAht7XgByAgABNQADCgYIBgADAAAAAA==.',
Nu='Nubu:BAAANQADCgcJFAAAAA==.Nukin:BAAANQABCgIJAgAAAA==.',
Ny='Nycepala:BAAANQADCggIGgAAAA==.Nylaith:BAAANQADCgUIBQAAAA==.Nyni:BAACNQAFFIEIAAIbAAUKjgo2CQAcAQAbAAUKjgo2CQAcAQA1AAQKgSQAAhsACQogGHYcAHMCABsACQogGHYcAHMCAAAA.Nythshade:BAAANQADCgcIDAAAAA==.Nyxe:BAAANQAECgEIAQABNQAFFAUICAAbAI4KAA==.',
['Nü']='Nümnüts:BAAANQAECgIIBAAAAA==.',
Of='Offworlder:BAAANQADCggIFwAAAA==.',
Ol='Olokun:BAAANQABCgYJBwAAAA==.',
On='Onlyhoofs:BAEBNQAECoEcAAIXAAkKkBsRFQDeAgAXAAkKkBsRFQDeAgAAAA==.',
Oo='Oofm:BAABNQAECoEgAAMLAAcKugt4FgDxAAALAAYKMwd4FgDxAAAMAAMKsg9fMwDJAAAAAA==.Oospider:BAAANQAECgEJAgAAAA==.',
Op='Ophearia:BAAANQADCgYIEwAAAA==.Optimiss:BAAANQAECgUIBwAAAA==.',
Or='Orcboy:BAAANQAECgUIDwAAAA==.Orken:BAAANQADCgEIAQAAAA==.Orthanu:BAAANQADCgUIBQAAAA==.',
Os='Osamul:BAAANQADCgYIBgAAAA==.',
Oz='Ozxenia:BAAANQAECgEJAQAAAA==.',
Pa='Paieth:BAAANQAECgUIDAAAAA==.Paladerp:BAABNQAECoEaAAIBAAcKAifOCwA0AwABAAcKAifOCwA0AwAAAA==.Palaresx:BAAANQAECgQIBwABNQAECgcIFAALAIgbAA==.Palean:BAAANQABCgQIAgAAAA==.Pallyshunter:BAAANQAECgYJEwAAAA==.Pancake:BAAANQAECgQIBAAAAA==.Panchamp:BAAANQADCgcJDgAAAA==.Pandamourne:BAAANQADCgcICQAAAA==.Pandori:BAAANQAECgcJEwAAAA==.Panetar:BAAANQABCggICAAAAA==.Parchmentham:BAABNQAECoEdAAMfAAgKnRuZJABzAgAfAAgKnRuZJABzAgARAAEKnhBPVQAyAAAAAA==.Paryniux:BAAANQAECgMIAwAAAA==.Patience:BAAANQADCgMIAwAAAA==.',
Pe='Peridrax:BAAANQADCggJCAAAAA==.',
Pi='Pinchiy:BAAANQADCgQIBAAAAA==.Pinkpanthir:BAAANQAECgUIDQAAAA==.',
Pj='Pjay:BAAANQAECgEJAgAAAA==.',
Pl='Plisky:BAAANQAECgEJAQAAAA==.',
Po='Pollywaffle:BAAANQADCggIDAAAAA==.Portals:BAAANQADCggIEAAAAA==.Poùnd:BAAANQADCgYJDAABNQAECgYJDwADAAAAAA==.',
Pr='Praiseme:BAAANQADCgYIEwAAAA==.Predz:BAAANQAECgUJCgAAAA==.Predzious:BAAANQAECgEJAQABNQAECgUJCgADAAAAAA==.Prepaired:BAAANQADCggICAABNQAFFAYIGgAHACgZAA==.Pretzelmix:BAAANQADCgYIBgAAAA==.Priestiitute:BAAANQADCgUIBQAAAA==.',
Ps='Psyreq:BAAANQAECgUIBwAAAA==.',
Pu='Punkey:BAAANQAECgYIDgAAAA==.Purplemad:BAAANQADCgEIAQAAAA==.',
Qu='Quartquartma:BAAANQAECgMJBQAAAA==.',
Ra='Raedia:BAAANQADCgMIAwAAAA==.Raft:BAAANQADCggICAAAAA==.Rahll:BAAANQABCggIDgAAAA==.Raindrops:BAAANQADCggICAAAAA==.Ravachiar:BAABNQAECoEUAAISAAYKNBLyKQCYAQASAAYKNBLyKQCYAQAAAA==.Ravenathas:BAAANQADCgUIEgABNQAECgIIAgADAAAAAA==.Ravenimus:BAAANQAECgIIAgAAAA==.Ravic:BAAANQAECgIIAgAAAA==.Razeld:BAAANQADCggIGgAAAA==.Razhun:BAAANQAECgMJBgAAAA==.Razia:BAAANQAECgIJAgAAAA==.Razzax:BAAANQADCgUIBQAAAA==.Razzmata:BAAANQAECgcIDwAAAA==.',
Re='Reckendorf:BAAANQAECgEIAgAAAA==.Redefine:BAAANQAECgQJBwAAAA==.Reflet:BAAANQAECgUJBgAAAA==.Rell:BAAANQAECgYIBwAAAA==.Rentress:BAAANQADCgYIFwAAAA==.Resolution:BAAANQADCggICAAAAA==.Restik:BAAANQADCggIFgAAAA==.Revyre:BAAANQAECgQJBAAAAA==.Rexxnaar:BAAANQAECgQIBAAAAA==.Rexy:BAAANQAECgcIEQAAAA==.',
Rh='Rhiotannis:BAAANQAECgYJDAAAAA==.Rhombus:BAAANQADCgYIBgAAAA==.Rhots:BAAANQAECgYJEAAAAA==.',
Ri='Ricketyrekt:BAAANQADCgcIBwAAAA==.Rimara:BAAANQAECgQJCwAAAA==.Rishari:BAAANQADCggJFAAAAA==.',
Ro='Rocadin:BAAANQAECgYJCgAAAA==.Rocmon:BAAANQADCgYIBgABNQAECgYJCgADAAAAAA==.Rorisala:BAAANQADCgYICwABNQAECgQJBgADAAAAAA==.Rottlee:BAAANQADCgcIEQAAAA==.Rowshamboe:BAAANQADCgYIGgAAAA==.Rozabella:BAAANQAECgcJEwAAAA==.',
Ru='Rune:BAAANQAECgIIAgABNQAECggIFgASAMEWAA==.',
['Rê']='Rêdemption:BAAANQADCgEIAQAAAA==.Rêdylive:BAAANQAECgMIBQAAAA==.',
['Rï']='Rïkku:BAAANQAECgYJCgAAAA==.',
Sa='Saelska:BAAANQAECgEIAQAAAA==.Sahven:BAAANQADCgYICQAAAA==.Sakuraharu:BAABNQAECoEaAAIKAAcKzA99nQDOAQAKAAcKzA99nQDOAQAAAA==.Sakuraharune:BAAANQAECgYJCAAAAA==.Sakuraharuno:BAABNQAECoEZAAIOAAgKYB2TCQC2AgAOAAgKYB2TCQC2AgAAAA==.Sakuura:BAAANQAECgUICQAAAA==.Sarang:BAAANQAECgYJEQAAAA==.Sassystrasza:BAAANQADCgQIBAAAAA==.Savagepaw:BAAANQAECgcIEQAAAA==.',
Sc='Scarbi:BAAANQAECgEJAQAAAA==.Scarbz:BAAANQAECgUICgAAAA==.Scrtchnsniff:BAAANQABCgEIAQAAAA==.',
Se='Sehun:BAAANQADCgcIBwABNQAECgYIFQAGAP0YAA==.Selennys:BAAANQAECgIJAwAAAA==.Selest:BAAANQAECgQJBAAAAA==.',
Sh='Shadowkain:BAAANQAECgQJBwAAAA==.Shadowtrix:BAAANQADCggICAAAAA==.Shadøws:BAAANQAECgYIEQAAAA==.Shagz:BAAANQADCgYIFwAAAA==.Shallios:BAAANQADCgYIEAAAAA==.Shamajov:BAAANQADCgYIDgABNQAECgMIBgADAAAAAA==.Shamankiing:BAAANQADCgYIDAAAAA==.Shamannigans:BAAANQAECgIJAwAAAA==.Shammyhagar:BAAANQAECgEJAQAAAA==.Shamnow:BAAANQADCgEIAQAAAA==.Shaytan:BAAANQAECgMJCAAAAA==.Sheogorath:BAABNQAECoEcAAIgAAgKAR8zCADAAgAgAAgKAR8zCADAAgAAAA==.Shocksocks:BAAANQAECgYJCwAAAA==.Shoujian:BAAANQAECgQJCAAAAA==.',
Si='Sianien:BAAANQAECgIIAgAAAA==.Sickology:BAABNQAECoEcAAIWAAgKYhMSVgAAAgAWAAgKYhMSVgAAAgAAAA==.Siinatra:BAAANQAECggIEQABNQAFFAEJAQADAAAAAA==.Siinatrah:BAAANQAFFAEJAQAAAA==.Silverstarr:BAAANQADCgYICAAAAA==.Sinnafein:BAAANQADCgcIBwAAAA==.Siohban:BAAANQAECgUJCgAAAA==.Sionel:BAAANQADCgUIBQABNQADCgYICQADAAAAAA==.Siphirahah:BAAANQAECgIIBQAAAA==.',
Sk='Skürge:BAAANQAECgMJBQAAAA==.',
Sl='Slapntits:BAAANQABCgcIDQAAAA==.Slimreaper:BAAANQAECgcICgAAAA==.Slothination:BAABNQAECoEUAAIVAAgKSx+yAwDzAgAVAAgKSx+yAwDzAgAAAA==.Slurrydots:BAABNQAECoEeAAMfAAgKOR4IFQDYAgAfAAgKOR4IFQDYAgARAAMKVgeeQwB9AAAAAA==.',
Sm='Smellymango:BAAANQAECgMJAwAAAA==.',
Sn='Snaglvr:BAAANQADCgQJBQAAAA==.Snappyb:BAAANQADCgIIAgAAAA==.Snowtownz:BAAANQAECgcIDwAAAA==.Snörichäun:BAAANQADCgcIEAAAAA==.Snöríchäûn:BAAANQAECgIIAgAAAA==.',
So='Soiboii:BAAANQADCgQJBAAAAA==.Sokraxx:BAABNQAECoEdAAIYAAkKgyVkBgCLAgAYAAkKgyVkBgCLAgAAAA==.Sonozap:BAAANQAECgcIDQAAAA==.Sonyc:BAAANQADCgQIBAAAAA==.Soothlocked:BAAANQAECgIJAwAAAA==.Soraflash:BAAANQADCggICAAAAA==.Soulreaperau:BAAANQAECgEJAQAAAA==.',
Sp='Spearzy:BAAANQAECgEJAQABNQAECgYJDwADAAAAAA==.Spicedgoat:BAAANQADCggJGAAAAA==.Spinandwin:BAABNQAECoEaAAIEAAcKJyFGNgCOAgAEAAcKJyFGNgCOAgAAAA==.Springroll:BAABNQAECoEZAAIMAAcKoh5qEQBgAgAMAAcKoh5qEQBgAgAAAA==.',
Sq='Squishikayla:BAAANQADCgMJAwAAAA==.Squishyman:BAABNQAECoEbAAIKAAgKvBNldAA2AgAKAAgKvBNldAA2AgAAAA==.',
Sr='Sram:BAABNQAECoEdAAIaAAkKjCHBBQBWAwAaAAkKjCHBBQBWAwAAAA==.Srbenda:BAAANQADCgUJDgAAAA==.',
Ss='Sstormmy:BAABNQAECoEaAAICAAcK2w6SXgDSAQACAAcK2w6SXgDSAQAAAA==.',
St='Stabit:BAAANQAECgMJAwAAAA==.Starless:BAAANQAECgQJBQAAAA==.Starmyst:BAAANQADCgYIBgAAAA==.Steelbull:BAAANQAECgYJDgABNQAECgYJFAASADQSAA==.Steelmyth:BAAANQAECgYJDwAAAA==.Steeven:BAAANQADCgIIAgAAAA==.Strìder:BAAANQAECgEJAQAAAA==.Strîder:BAAANQAECgQJDAAAAA==.',
Su='Summerskye:BAAANQAECgYIDwAAAA==.',
Sy='Sy:BAABNQAECoEZAAMRAAcKPhymFABXAgARAAcKPhymFABXAgAfAAIKsBG4nQBiAAABNQAECgkJGAANAD8YAA==.Sycamore:BAAANQAECgEIAQAAAA==.Sydor:BAAANQADCggJLwAAAA==.Sylennia:BAAANQAECgEJAgAAAA==.Sylvatrix:BAAANQAECgQIBwAAAA==.Symbiont:BAAANQADCgcIEgAAAA==.',
Sz='Szarni:BAAANQAECgMJCAAAAA==.',
Ta='Tabitrisao:BAAANQAECgEIAQAAAA==.Talastor:BAAANQADCgMJAwAAAA==.Tamarin:BAAANQABCgIIAgAAAA==.Taridalas:BAAANQAECgQJBgAAAA==.Taucetid:BAAANQAECgMIBQAAAA==.Tazington:BAAANQAECgYJDgAAAA==.Tazmage:BAAANQADCgcIBwAAAA==.Tazuki:BAAANQABCgIIAgAAAA==.',
Te='Tehsharp:BAABNQAECoEWAAMCAAcKcR9zMQBtAgACAAcKcR9zMQBtAgAUAAEKIwixXgA0AAAAAA==.Tehwarrior:BAAANQABCgcIBwAAAA==.Telraena:BAAANQAECgMJBQAAAA==.Terokkar:BAAANQAECgMJCAAAAA==.Tesalach:BAAANQAECgMIAwAAAA==.Teul:BAAANQAECgYIDgABNQAECggJHwAXANETAA==.',
Th='Thalorian:BAAANQAECgUJCAAAAA==.Thananerion:BAAANQADCgMIAwAAAA==.Thealiaa:BAAANQADCgIIAgAAAA==.Thehexorcist:BAAANQADCggIDQAAAA==.Thiea:BAAANQAECgcJEwAAAA==.Thorel:BAAANQADCgcICAABNQAECggIFwAUAH8KAA==.Thorrimar:BAAANQADCgUIBQAAAA==.Thorsake:BAAANQAECgYIEAAAAA==.Thromgorr:BAABNQAECoEXAAIXAAgKRx8LFADlAgAXAAgKRx8LFADlAgAAAA==.Thundercant:BAAANQAECggIDwABNQAFFAUICQAhAO4UAA==.Thunderpog:BAACNQAFFIEJAAIhAAUK7hRoAADGAQAhAAUK7hRoAADGAQA1AAQKgRsABBEACQrbHGoPAKkCABEACApNHWoPAKkCAB8ABgoBGMVcAGUBACEABAoUHeoKADkBAAAA.',
Ti='Tillicity:BAABNQAECoEgAAMXAAgKwRtoKwBSAgAXAAgKwRtoKwBSAgAiAAIKbxsLqwCkAAAAAA==.Tilzabeth:BAAANQADCgQICgABNQAECggJIAAXAMEbAA==.Timewarp:BAAANQADCggIBQAAAA==.Tinhu:BAAANQAECgEIAQAAAA==.Tinypi:BAAANQAECgQICQAAAA==.Tivarah:BAAANQADCgcJBwAAAA==.',
To='Tomahawk:BAAANQADCgEIAQAAAA==.Toosuss:BAAANQADCgcIEQAAAA==.Topshot:BAAANQAECgcIEAAAAA==.Torags:BAAANQADCgQIBAAAAA==.Totemorlusta:BAAANQADCgMJAwABNQADCgMIBAADAAAAAA==.',
Tr='Trazendeath:BAAANQADCgMIAwAAAA==.Treesome:BAAANQAECgYJDwAAAA==.Treesource:BAAANQAECgQIBQAAAA==.Trigaa:BAAANQADCggIDAAAAA==.Trojans:BAAANQAECgEIAQAAAA==.',
Ts='Tsaiko:BAAANQAECgIJAgAAAA==.',
Tw='Twirls:BAAANQAECgYJDwAAAA==.Twirlshair:BAAANQADCgUIBQAAAA==.',
Ty='Tynzel:BAAANQAECgQJBAAAAA==.Tyvaria:BAAANQADCgYIDQAAAA==.',
['Tà']='Tàkhisis:BAAANQAECgIJAwAAAA==.',
Ul='Ullbenxt:BAAANQAECgIIAgAAAA==.',
Um='Umf:BAAANQADCggJEQABNQAECggIHQAfAJ0bAA==.',
Un='Underwhelmed:BAAANQAECgMJBAAAAA==.Unitofglory:BAAANQADCgIIAgABNQAECgcJGwAfAFcmAA==.Unitoflife:BAABNQAECoEbAAIfAAcKVyaADQAUAwAfAAcKVyaADQAUAwAAAA==.Unitofshapes:BAAANQAECgUJCQABNQAECgcJGwAfAFcmAA==.',
Va='Valanar:BAAANQADCgMIAwAAAA==.Valdormu:BAAANQAECgYJDgAAAA==.Vanador:BAAANQAECgQIBQAAAA==.Vanarel:BAAANQADCgYIDgAAAA==.Vanel:BAAANQADCgYIBgAAAA==.Vannbeef:BAAANQAECgQICwAAAA==.Varthlight:BAAANQAECgIIBQAAAA==.',
Ve='Veinytotem:BAAANQADCgUIBQAAAA==.Veloran:BAACNQAFFIEGAAMCAAIKqAxzHABTAAACAAEKwhFzHABTAAAUAAEKjwcdFgBFAAA1AAQKgTkABAIACQr/Ge4dAMcCAAIACQpvGe4dAMcCABQACAoiD/MkAKkBACMAAgrkC50LAGsAAAAA.Venomsspawn:BAAANQAECgUIDQAAAA==.Vernonia:BAAANQADCgYJBwAAAA==.Vexahlia:BAAANQADCgQJBgAAAA==.Veyrathor:BAAANQADCgIIAgAAAA==.',
Vi='Vio:BAACNQAFFIESAAIXAAYKHhnUAQAeAgAXAAYKHhnUAQAeAgA1AAQKgSoAAxcACQrTJPwCAKIDABcACQrTJPwCAKIDACIABArYF9h5ACgBAAAA.Virtues:BAAANQADCgMIAwAAAA==.Virtus:BAAANQADCgYIBwAAAA==.Viserys:BAAANQAECgQIBwAAAA==.',
Vo='Voidtouched:BAAANQADCgYIBgABNQAECgYJDwADAAAAAA==.Vows:BAAANQAECgQIBAAAAA==.',
Vu='Vuruul:BAAANQADCgYIDAAAAA==.',
Vy='Vypërz:BAABNQAECoEaAAMXAAgKKCU4CABUAwAXAAgKKCU4CABUAwAiAAEKOggG2gA1AAAAAA==.Vyral:BAABNQAECoEaAAIbAAcKQwnzUAA4AQAbAAcKQwnzUAA4AQAAAA==.',
Wa='Wabssevo:BAAANQAECgQIBAABNQAFFAUICAABAAENAA==.Wabssjnr:BAACNQAFFIEIAAIBAAUKAQ2dBQCTAQABAAUKAQ2dBQCTAQA1AAQKgRkAAgEACQpVHE0UAOoCAAEACQpVHE0UAOoCAAAA.Wararesx:BAAANQADCgUIBwABNQAECgcIFAALAIgbAA==.Warizard:BAAANQAECgUJDgAAAA==.Wattanuhbii:BAAANQADCgQJBAAAAA==.Wayz:BAAANQADCgMIAwAAAA==.Wayzpala:BAAANQADCggIDAAAAA==.',
We='Weyoun:BAAANQAECgMJBAAAAA==.',
Wh='Wheetie:BAAANQAECgQJCwAAAA==.',
Wi='Williwaw:BAAANQAECgEJAQAAAA==.Winterstormm:BAAANQAECgUJCAAAAA==.',
Wn='Wno:BAAANQADCgcIBwAAAA==.',
Wo='Wobbuffet:BAACNQAFFIEFAAIiAAMKmSRwBwBFAQAiAAMKmSRwBwBFAQA1AAQKgRoAAiIACQp5JKwDAL4DACIACQp5JKwDAL4DAAAA.Wolfen:BAAANQADCgcIDgAAAA==.',
Wy='Wyrnn:BAABNQAECoEVAAIaAAgKIiFvDQDUAgAaAAgKIiFvDQDUAgAAAA==.',
Xa='Xaniran:BAAANQADCgYICAAAAA==.Xaye:BAAANQAECgEJAQAAAA==.',
Xe='Xelbino:BAAANQADCgEIAQAAAA==.',
Xi='Xiaobi:BAABNQAECoEdAAMMAAkKqh76BgAlAwAMAAkKqh76BgAlAwALAAYKrhAsEgBNAQAAAA==.Xintar:BAAANQADCggIEAAAAA==.Xiomana:BAAANQAECgIIAwAAAA==.Xion:BAABNQAECoEVAAMGAAYK/RiCGACPAQAGAAUKohqCGACPAQAFAAYKXg/ncQBtAQAAAA==.',
Xy='Xyluna:BAAANQADCgYIBgABNQAECggJHgAhAIocAA==.',
Ye='Yebanned:BAAANQADCggICAABNQAFFAUIFQACAJYUAA==.Yellowajah:BAAANQAECgQJDwAAAA==.',
Yi='Yify:BAAANQADCgUIBQABNQAECgIIAgADAAAAAA==.',
Yn='Yneva:BAAANQAECgEIAgAAAA==.',
Yw='Ywrensire:BAAANQADCgQJBAAAAA==.',
Za='Zaabra:BAAANQAECgIIAwAAAA==.Zaion:BAAANQAECgMJBgAAAA==.',
Ze='Zealis:BAAANQAECgUICAAAAA==.Zebby:BAAANQAECgYJCwAAAA==.Zedar:BAAANQAECgUJBQABNQAECggJLwAFANAeAA==.Zerull:BAAANQADCgYIBgAAAA==.',
Zh='Zhi:BAAANQAECgQJBwAAAA==.',
Zi='Zilin:BAAANQAECgQJCQAAAA==.',
Zo='Zolce:BAAANQAECgIIAgABNQAECgYJDwADAAAAAA==.',
Zu='Zurbi:BAAANQAECgEIAQABNQAECgkJHQAMAKoeAA==.Zuularok:BAAANQADCgUIBQAAAA==.',
Zy='Zybaxos:BAABNQAECoEcAAIJAAgKHB4MGQCvAgAJAAgKHB4MGQCvAgAAAA==.Zyth:BAAANQAECgIJAgAAAA==.',
Zz='Zzro:BAAANQADCgcICQAAAA==.',
['Ãr']='Ãrçâñîst:BAAANQAECgEJAQAAAA==.',
['År']='Årchon:BAAANQAECgQIBAABNQAECgUJCgADAAAAAA==.Årtix:BAAANQADCgYIBgABNQADCgYICgADAAAAAA==.',
['Îs']='Îssy:BAAANQAECgIIAwAAAA==.',
['Ôr']='Ôrkásh:BAAANQADCgcIDgAAAA==.',
['Öm']='Ömegoss:BAAANQAECgQJCgAAAA==.',
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
