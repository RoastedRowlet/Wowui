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

local lookup = {'Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Assassination','Druid-Guardian','Mage-Arcane','Mage-Frost','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','DeathKnight-Unholy','Paladin-Holy','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Priest-Discipline','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','Hunter-Survival','Shaman-Restoration','Shaman-Elemental',}
local provider = {region='US',realm="Dath'Remar",name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaronius:BAAANQADCggIDwAAAA==.',
Ab='Abduhl:BAAANQABCgEIAQAAAA==.',
Ad='Ade:BAAANQAECgUIBgAAAA==.Adezardre:BAAANQAECgEIAQAAAA==.Admetriell:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Advosary:BAAANQADCgcIDwAAAA==.',
Af='Afflictid:BAAANQABCgIIAgAAAA==.',
Ai='Aigmokthar:BAAANQAECgYIDwAAAA==.',
Ak='Akiriah:BAAANQADCggICAAAAA==.Akirial:BAAANQAECgUIBQABNQAECgUIBgABAAAAAA==.Aklo:BAAANQADCggIGgAAAA==.',
Al='Alamysia:BAAANQADCgYICwAAAA==.Albertfist:BAAANQADCgMIAwAAAA==.Aletech:BAAANQAECgMIAwAAAA==.Ali:BAAANQAECgIIBAAAAA==.Aliesá:BAAANQADCggIFwAAAA==.Alilea:BAAANQADCgYIBgAAAA==.Alimagus:BAAANQAECgUIBQABNQAECgkJHgACAAcfAA==.Alisandrah:BAABNQAECoEgAAQDAAkJkSDmDgDqAgADAAgJgh/mDgDqAgAEAAcJwR5+BwBnAgAFAAEJwxnVFgBMAAAAAA==.Alison:BAAANQADCgYIEgAAAA==.Allakeer:BAABNQAECoEaAAIGAAkJPB4oBAA0AwAGAAkJPB4oBAA0AwAAAA==.Altarios:BAAANQADCggIHAAAAA==.Alyyix:BAAANQADCgYIFQAAAA==.',
Am='Amber:BAAANQAECgIIAgAAAA==.Amberlicious:BAAANQABCggIFQABNQAECgIIAgABAAAAAA==.Amberlily:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Ambertastic:BAAANQADCgcIFQABNQAECgIIAgABAAAAAA==.Amilandris:BAAANQAECgcIEwAAAA==.Amitié:BAAANQADCgYIBgAAAA==.',
An='Analalea:BAAANQADCgcIDgAAAA==.Analdrainal:BAAANQAECgcIDQAAAA==.Annaris:BAAANQADCggICgAAAA==.',
Ap='Apophani:BAAANQADCggIFwAAAA==.Appolo:BAAANQAECgQICAAAAA==.',
Ar='Arcaidion:BAAANQAECggICAAAAA==.Arcanegasm:BAAANQAECgcIEgAAAA==.Archii:BAAANQADCgcIBwABNQAECgQIDwABAAAAAA==.Archslayer:BAAANQAECgEIAgAAAA==.Aresdeekx:BAAANQAECgUIBgABNQAECgYIDQABAAAAAA==.Arneus:BAAANQADCgcIDAAAAA==.Arnir:BAAANQAECgIIBAAAAA==.Arriving:BAAANQAECgYIDAAAAA==.Artaq:BAAANQADCgYIGgAAAA==.Artoriöus:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Arvanon:BAAANQAECgUICwAAAA==.',
As='Ashanar:BAAANQAECgEIAQAAAA==.Asharla:BAAANQAECgIIAgAAAA==.Ashbringa:BAAANQAECgEIAgAAAA==.Ashhman:BAAANQADCggIDgAAAA==.Ashhunt:BAAANQAECgYIEAAAAA==.Ashmend:BAAANQAECgEIAQAAAA==.Asorrow:BAAANQAECgQICAABNQAECggIEAABAAAAAA==.Assatur:BAAANQADCgYIBgAAAA==.Astarna:BAAANQAECgIIAwAAAA==.Asteríx:BAAANQADCgUICQAAAA==.',
At='Atiatal:BAAANQAECgEIAQAAAA==.Atlasursidae:BAAANQAECgMIBgAAAA==.Atoniah:BAAANQAECgQIBAAAAA==.',
Au='Auraz:BAAANQAECgYIBwAAAA==.',
Av='Avelinna:BAAANQAECgIIAwAAAA==.',
Aw='Awan:BAAANQADCgYICwAAAA==.',
Az='Aztrayel:BAAANQADCggIGgAAAA==.',
Ba='Baalial:BAAANQAECgIIAgAAAA==.Baboya:BAAANQAECggIAQAAAA==.Baelgrim:BAAANQADCgcIGAAAAA==.Baly:BAAANQADCgYIDAABNQAECgcIEgABAAAAAA==.Bangbangbro:BAAANQAECgIIAgAAAA==.Barium:BAAANQADCgUIBgAAAA==.',
Be='Belfrostbolt:BAAANQADCgcIEAAAAA==.Bentt:BAAANQABCgcICgAAAA==.Bettÿ:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Bi='Bigjawden:BAAANQADCggIFwAAAA==.Billbee:BAAANQADCgcIDAAAAA==.Bimbohaggins:BAAANQAECgMIBAABNQAECgQICwABAAAAAA==.Bimbò:BAAANQAECgIIBAAAAA==.Binchicken:BAAANQAECgQIBgAAAA==.Bingler:BAAANQABCgMIAwAAAA==.',
Bj='Bjornhammerz:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Bjornshockz:BAAANQAECgQIBAAAAA==.',
Bl='Blaz:BAAANQAECgQIDAAAAA==.Blockz:BAAANQADCggIDwAAAA==.Bloodboi:BAAANQADCgcIDwAAAA==.Bloodyeddy:BAAANQAECgEIAQAAAA==.Bluecups:BAAANQAECgQIBAAAAA==.Bluey:BAAANQADCgcIEgAAAA==.',
Bo='Bobbyboom:BAAANQAECgQIBQAAAA==.Bonedecays:BAAANQADCgMIBAAAAA==.Bontoad:BAAANQAECgIIAgAAAA==.',
Br='Brewaresx:BAAANQAECgYIDQAAAA==.Broxaschor:BAAANQABCgQIAwAAAA==.Brutus:BAAANQAECgYIDAAAAA==.',
Bu='Bubbleduck:BAAANQADCgIIAgAAAA==.Buggzz:BAAANQAECgYIEQAAAA==.',
Bz='Bzlthazyr:BAAANQAECggIEwAAAA==.',
Ca='Cahtbl:BAAANQADCgcIEQAAAA==.Callin:BAAANQADCggIGAAAAA==.Calyx:BAAANQADCgYICQAAAA==.Cartier:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Casay:BAAANQAECgEIAgAAAA==.Casbot:BAAANQAECgcIEAAAAA==.Cashmere:BAAANQAECgQIBgAAAA==.Castalight:BAAANQAECgIIAgAAAA==.Castlebravo:BAAANQADCgYIBgAAAA==.',
Ch='Changes:BAAANQADCgUIBQAAAA==.Charlee:BAAANQADCgUIEAAAAA==.Chirran:BAABNQAECoEcAAIHAAYJtCBXBgAzAgAHAAYJtCBXBgAzAgAAAA==.Chxdzilla:BAABNQAECoEcAAICAAkJ7xBlOwBKAgACAAkJ7xBlOwBKAgAAAA==.',
Ci='Cinnamõn:BAAANQABCgYICQAAAA==.Citryn:BAAANQAECgEIAQABNQAECgcIEwABAAAAAA==.',
Co='Corldrin:BAAANQAECgEIAQAAAA==.Coronis:BAAANQAECgEIAgAAAA==.Corriana:BAAANQADCgcIFQABNQAECgIIAwABAAAAAA==.Corwin:BAAANQADCgYIFQAAAA==.',
Cr='Crazee:BAABNQAECoEaAAMIAAkJjh5mGwArAwAIAAkJjh5mGwArAwAJAAEJhSICHABnAAAAAA==.Cruz:BAAANQAECgQICgAAAA==.Crystalflame:BAAANQAECgQIBQAAAA==.Crìsp:BAAANQADCgYICwABNQADCggICwABAAAAAA==.',
Ct='Ctshammy:BAAANQAECgQICAAAAA==.',
Cu='Cultistt:BAAANQAECgYIEAAAAA==.Cursedyou:BAAANQAECgQIBAAAAA==.Curserot:BAAANQAECgQIBQAAAA==.Cuteselenes:BAAANQADCgIIAgAAAA==.',
Cy='Cynal:BAAANQAECgYIDQAAAA==.',
Da='Daddyy:BAAANQADCggICAABNQAECgkJGgAIAI4eAA==.Dammo:BAAANQADCggIFwAAAA==.Dantallion:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Darkholme:BAAANQAECgMIBAAAAA==.Darkk:BAAANQADCgEIAQAAAA==.Darthdraik:BAAANQAECgMIAwAAAA==.',
Dc='Dcver:BAABNQAECoEfAAIDAAcJzxz9JQBOAgADAAcJzxz9JQBOAgAAAA==.',
Dd='Ddraigfach:BAAANQABCgMIAwAAAA==.',
De='Deademeat:BAAANQADCgMIAwAAAA==.Deadlynewbz:BAABNQAECoEYAAMGAAgJ/CQWAwBWAwAGAAgJ/CQWAwBWAwAKAAMJth9dJgAQAQAAAA==.Deathboom:BAAANQADCgUIBQABNQAECggIFwALADkRAA==.Deathbow:BAAANQADCgcIBwAAAA==.Deathbyshoe:BAAANQAECgEIAQAAAA==.Deathivy:BAAANQADCgcIDgAAAA==.Deathjam:BAAANQAECgIIAwAAAA==.Deathmore:BAAANQAECgEIAgAAAA==.Deathshrine:BAAANQADCggIDQAAAA==.Decypha:BAAANQAECgYIDAAAAA==.Deidius:BAAANQADCgUIBQAAAA==.Deiwos:BAAANQAECgQIBgAAAA==.Delichtable:BAAANQADCgcIFQABNQAECgIIAgABAAAAAA==.Deltora:BAAANQAECgEIAQABNQAECgYIBgABAAAAAA==.Demodog:BAAANQAECgQICwAAAA==.Demonicnight:BAAANQAECgYICAAAAA==.Derryth:BAAANQAECgQIBgAAAA==.Devpro:BAAANQAECgUICQAAAA==.Deweysan:BAAANQAECgQIBgAAAA==.Dexillo:BAABNQAECoEgAAMMAAkJ5hhJCwDZAgAMAAkJ5hhJCwDZAgALAAgJ8A42HQDwAQAAAA==.',
Dh='Dhaveira:BAAANQAECgcIDwAAAA==.',
Di='Diggyhole:BAAANQADCgIIAgAAAA==.Divinegirly:BAAANQAECgIIAwAAAA==.',
Do='Dodgeanaxe:BAABNQAECoEpAAICAAkJGhv0HADpAgACAAkJGhv0HADpAgAAAA==.Dojoe:BAAANQAECgIIBgABNQAECgYIDAABAAAAAA==.Dorá:BAAANQAECgEIAQAAAA==.',
Dr='Dracnock:BAAANQAECgYIEAAAAA==.Drinian:BAAANQADCggIDwAAAA==.',
Du='Ducker:BAABNQAECoEcAAINAAkJQSZfAADuAwANAAkJQSZfAADuAwAAAA==.Dustangel:BAAANQADCggICAAAAA==.',
Dy='Dylexd:BAAANQAECgYIBwAAAA==.',
Ea='Eatmybolts:BAAANQAECgYIBgAAAA==.',
Ec='Eccentricity:BAAANQAECgIIAgAAAA==.',
El='Eldarion:BAAANQAECgMIAwAAAA==.Electricmon:BAAANQAECgUICwABNQAECgkJKQACABobAA==.Elementi:BAAANQADCgIIAgAAAA==.Elfy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Eliasidris:BAAANQAECgQIBQAAAA==.Elmaco:BAAANQAECgUICAAAAA==.Elphkilla:BAAANQADCggICAAAAA==.Elroth:BAAANQADCgYICgAAAA==.Elseapi:BAAANQAECgEIAQAAAA==.Elyssae:BAAANQAECgYIDQAAAA==.',
En='Endarios:BAAANQAECgIIAgAAAA==.Endsplit:BAAANQAECgIIAwAAAA==.',
Er='Erzalockhart:BAAANQADCgcICAAAAA==.',
Es='Esmaralda:BAAANQADCgYIDQAAAA==.',
Ev='Everleaf:BAAANQADCgQIBgAAAA==.Eviion:BAAANQAECgYICgAAAA==.',
Ez='Ezoth:BAAANQAECgEIAQAAAA==.',
Fa='Fallendivine:BAAANQAECgYIDQAAAA==.',
Fe='Feetenjoyer:BAAANQADCgMIAwAAAA==.Feipo:BAABNQAECoEZAAIIAAkJpxuXKADvAgAIAAkJpxuXKADvAgAAAA==.Felissa:BAAANQADCgQIBAABNQADCgcIDwABAAAAAA==.Fensmage:BAAANQADCggIDwAAAA==.Feralbuffkty:BAABNQAECoEYAAIOAAkJcx07DAALAwAOAAkJcx07DAALAwAAAA==.Fere:BAAANQAECgYICwAAAA==.Feurekt:BAABNQAECoEaAAICAAcJoRp/QgAqAgACAAcJoRp/QgAqAgAAAA==.',
Fi='Finitaur:BAAANQADCgQIBwAAAA==.Fiz:BAAANQADCggICAABNQAECgkJGwAFADQVAA==.',
Fl='Flashinlight:BAAANQAECgEIAgAAAA==.Flashstép:BAAANQAECgUICAAAAA==.Flipside:BAAANQAECgUIBwAAAA==.',
Fo='Fomor:BAAANQAECgMIBQAAAA==.Forbs:BAAANQADCgMIAwAAAA==.Foreignerr:BAABNQAECoEeAAICAAkJBx9FDwBNAwACAAkJBx9FDwBNAwAAAA==.',
Fr='Franziscka:BAAANQADCggIEwAAAA==.',
Fu='Furbold:BAAANQAECgYIDwAAAA==.',
['Fí']='Fíredup:BAAANQADCggIFAABNQAECgUICQABAAAAAA==.',
Ga='Galeira:BAAANQAECgIIAgAAAA==.Gallene:BAABNQAECoE1AAICAAkJ8iR/AgDXAwACAAkJ8iR/AgDXAwAAAA==.Gandallf:BAAANQADCgUICgABNQAECgEIAQABAAAAAA==.Garakarak:BAAANQAECgMIAwAAAA==.Garthinian:BAAANQADCgYICQAAAA==.Garthpally:BAAANQADCgUIBQAAAA==.',
Ge='Genimaculata:BAAANQAECgYIDAAAAA==.Germ:BAAANQADCgIIAgAAAA==.Gerothos:BAAANQADCgQIBAAAAA==.Geîsha:BAAANQADCgMIAwAAAA==.',
Gh='Ghislaine:BAAANQADCggIDQAAAA==.Ghöst:BAAANQAECgQIBAAAAA==.',
Gl='Gladios:BAAANQADCgMIAwAAAA==.Glarry:BAAANQADCggICAABNQAECgkJHAAPAC8eAA==.Glidelicator:BAAANQAECgYICgAAAA==.',
Go='Goodasnew:BAAANQADCggIFAAAAA==.Gooditoshoes:BAAANQAECgEIAQAAAA==.Gortopia:BAAANQADCgYIDwAAAA==.Gosublood:BAAANQAECgYIDAAAAA==.Gosupriest:BAAANQAECgMIBAABNQAECgYIDAABAAAAAA==.',
Gr='Graggy:BAABNQAECoEcAAIPAAkJLx4SCAA/AwAPAAkJLx4SCAA/AwAAAA==.Grapejelly:BAAANQAECgYIDgAAAA==.Grashk:BAAANQAECgIIAwAAAA==.Grimbel:BAAANQAECgIIAwAAAA==.',
['Gø']='Gødspeed:BAAANQADCgYIBgAAAA==.',
Ha='Hadeshunt:BAAANQAECgEIAwAAAA==.Hadessham:BAAANQADCggICAAAAA==.Halzarius:BAAANQAECgIIAwAAAA==.Handyshammy:BAAANQAECgQIBAABNQAECgcIGgACAEwYAA==.Handywar:BAABNQAECoEaAAICAAcJTBiESAASAgACAAcJTBiESAASAgAAAA==.Hans:BAAANQAECgEIAQAAAA==.Harleybear:BAAANQADCgUIEgAAAA==.',
Ho='Holymender:BAAANQADCggIDgAAAA==.',
Hu='Hulkamania:BAAANQADCgUICAAAAA==.Humble:BAAANQAECgYIDgAAAA==.',
Hy='Hydromender:BAAANQAECgQICQAAAA==.Hyperactiv:BAAANQADCgYIBgABNQADCgcIDwABAAAAAA==.Hypothermia:BAAANQAECgMIAwAAAA==.',
['Hø']='Høpeless:BAAANQAECgYIEAAAAA==.',
Ic='Icycookiex:BAAANQADCggIDgABNQAECgQICQABAAAAAA==.Icymilkyx:BAAANQAECgQICQAAAA==.',
Ig='Igneel:BAAANQADCgYIDAAAAA==.',
Il='Illigniteyou:BAABNQAECoEbAAIIAAcJrh4uRgB8AgAIAAcJrh4uRgB8AgAAAA==.',
In='Inosolan:BAAANQAECgEIAQAAAA==.Inurfacevegi:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.',
Io='Iolololol:BAAANQADCgYIBgABNQAECggIGAAOAMMXAA==.Iozt:BAAANQAFFAEIAQAAAA==.',
Ir='Irralis:BAAANQAECgUIBQABNQAECgkJHgAIANAlAA==.Irritable:BAAANQAECgQIBQAAAA==.Irvina:BAABNQAECoEXAAIQAAcJphJKPAAHAgAQAAcJphJKPAAHAgAAAA==.Irvinebrown:BAAANQADCgIIBAABNQAECgcIFwAQAKYSAA==.Irvinia:BAAANQADCggIHAABNQAECgcIFwAQAKYSAA==.',
Is='Iskarius:BAAANQAECgQIBgAAAA==.Istenn:BAAANQAECgIIAwAAAA==.',
It='Ithyl:BAAANQADCggIGgAAAA==.Itzshammy:BAAANQAECgYIDQAAAA==.',
Iv='Ivanoviaa:BAAANQADCgMIAwAAAA==.',
Ja='Jabmojorjo:BAAANQADCgMIAwAAAA==.Jackdaw:BAAANQABCgIIAgAAAA==.Janinda:BAAANQAECgcIEgAAAA==.Jastina:BAAANQAECgIIAwAAAA==.Jaszz:BAAANQAECgYIEAAAAA==.',
Jb='Jb:BAAANQADCggICwAAAA==.',
Je='Jelly:BAAANQADCgcIDAAAAA==.Jengil:BAAANQAECgQIBAAAAA==.Jengol:BAAANQADCgcIBwAAAA==.Jesto:BAABNQAECoEcAAIRAAcJAx6zBQBiAgARAAcJAx6zBQBiAgAAAA==.',
Jh='Jhonn:BAAANQAECgIIAgAAAA==.',
Jo='Jodiefroster:BAAANQAECgEIAQAAAA==.Joeseppe:BAAANQAECgYIDAAAAA==.Joshst:BAAANQADCgcIFgAAAA==.Josta:BAAANQADCgQICAABNQAECgcIHAARAAMeAA==.Josto:BAAANQADCgcIEQABNQAECgcIHAARAAMeAA==.Jovyll:BAAANQAECgIIAwAAAA==.Joyboyluffy:BAAANQADCgUIBQAAAA==.',
Ju='Jurodice:BAAANQAECgcIEAAAAA==.',
['Jå']='Jårko:BAAANQADCgYICQAAAA==.',
Ka='Kaelinth:BAAANQADCgYIBgAAAA==.Kaelyth:BAAANQAECgEIAQAAAA==.Kamakazie:BAAANQADCgYIBgAAAA==.Kamelle:BAAANQADCggICAAAAA==.Karmerre:BAAANQADCggIEQAAAA==.Karramerre:BAAANQADCgUIBQABNQADCggIEQABAAAAAA==.Kaydeebug:BAAANQAECgQIDwAAAA==.Kayna:BAABNQAECoEXAAINAAcJOQydGgCHAQANAAcJOQydGgCHAQAAAA==.',
Ke='Kellanis:BAAANQAECgUIBwAAAA==.Kelugar:BAAANQADCgIIAgAAAA==.Kerenarye:BAAANQAFFAEIAQAAAA==.',
Kh='Khaladore:BAAANQAECgUICAAAAA==.Kharazhan:BAAANQAECgQIBQAAAA==.',
Ki='Kiilbill:BAAANQADCgcICwABNQAECgQICAABAAAAAA==.Killshotbob:BAAANQADCgcIEQAAAA==.Kinkyheaven:BAAANQAECgQIBgAAAA==.Kinnigit:BAAANQAECgYIDwAAAA==.Kinstalz:BAAANQAECgMIBAAAAA==.Kiotia:BAAANQADCgYIDQAAAA==.Kipp:BAAANQAECgMIBAAAAA==.Kiril:BAAANQADCgUIBQAAAA==.Kirky:BAAANQADCgUICgAAAA==.Kithraah:BAABNQAECoEaAAMSAAgJZRBmFwDhAQASAAgJ1w5mFwDhAQAOAAcJywxmNgCcAQAAAA==.Kithrah:BAAANQAECgEIAQABNQAECggIGgASAGUQAA==.',
Kn='Knifeparty:BAAANQADCgcIDQAAAA==.',
Ko='Kolugar:BAABNQAECoEXAAITAAkJrCMiAwCdAwATAAkJrCMiAwCdAwAAAA==.Konkar:BAAANQAECgQICQAAAA==.',
Kr='Kradon:BAAANQAECgIIAwAAAA==.Kruphix:BAAANQAECgUIBwAAAA==.Krysania:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.',
Ku='Kudreanne:BAAANQADCgYIFQAAAA==.Kuri:BAAANQADCggICAAAAA==.Kuzzo:BAAANQAECgIIAQAAAA==.',
La='Laiceeshay:BAAANQAECgcIDAAAAA==.Lars:BAAANQAECgQICgAAAA==.Larxe:BAAANQAECgUIBQAAAA==.',
Le='Legendaïry:BAAANQAECgEIAQAAAA==.Letmedie:BAAANQAECgQICQAAAA==.Lexillo:BAAANQAECgUICAAAAA==.',
Li='Liaravara:BAAANQAECgEIAQAAAA==.Lightmender:BAAANQADCgQIBAAAAA==.Lilhunty:BAAANQADCgMIAwAAAA==.Lilldemon:BAAANQADCgcIDgAAAA==.Lizzo:BAAANQAECgYIEQAAAA==.',
Lo='Lorieyxo:BAAANQADCggIGgAAAA==.Lorrim:BAAANQAECgEIAQAAAA==.Louron:BAAANQADCgYIBgAAAA==.',
Lu='Luena:BAAANQADCgMIAwAAAA==.Lunabi:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.Lute:BAAANQADCgYIBgAAAA==.Luxdae:BAAANQADCgEIAQAAAA==.',
Ly='Lyrannia:BAAANQAECgUICwAAAA==.Lyth:BAAANQAECgYIDAAAAA==.',
['Lá']='Láiken:BAAANQADCgYIFwAAAA==.',
Ma='Madmoxxie:BAAANQADCgUIBQAAAA==.Mageapayne:BAAANQADCgYIBgAAAA==.Magetom:BAAANQAECgEIAQAAAA==.Maghan:BAAANQADCgQICAAAAA==.Magicus:BAAANQAECgIIAgAAAA==.Magikaze:BAAANQAECgUIBgAAAA==.Mahgo:BAAANQAECgYICgAAAA==.Maikara:BAAANQAECgEIAQAAAA==.Malfalcator:BAAANQADCgMIAwAAAA==.Marieh:BAAANQADCgcICAAAAA==.Martha:BAAANQABCgcICAAAAA==.Masscarnage:BAAANQAECgUIEQAAAA==.Maywina:BAAANQAECgYIDwABNQAECgcIEwABAAAAAA==.Mazhun:BAAANQAECgQIBQAAAA==.',
Me='Meaculpa:BAAANQAECgUICwAAAA==.Mediqua:BAAANQADCgQIAQAAAA==.Megaflame:BAAANQADCgYIEgAAAA==.Mekkii:BAAANQADCgIIAgABNQAECggIGAAOAMMXAA==.Mekky:BAABNQAECoEYAAIOAAgJwxcoGgBwAgAOAAgJwxcoGgBwAgAAAA==.Melonheadx:BAAANQADCgIIAgAAAA==.Meltharion:BAAANQADCgcIDgAAAA==.Mercerful:BAAANQADCgMIAwAAAA==.Mereaux:BAAANQADCgMIAwAAAA==.Methex:BAAANQAECgYICwAAAA==.Metzger:BAAANQADCgQICgAAAA==.',
Mi='Mingi:BAAANQADCggICQABNQAECgYIDwABAAAAAA==.Minigore:BAAANQAECgYIEgAAAA==.Mirya:BAAANQADCggIGgAAAA==.Mishamigo:BAAANQAECgQIBQAAAA==.Missharmony:BAAANQAECgQIBQAAAA==.Misstickles:BAAANQAECgQIBgAAAA==.',
Mo='Moistfisting:BAAANQADCggICAABNQAECgkJHQAUAGQkAA==.Moistpawjob:BAABNQAECoEdAAMUAAkJZCSdBQCAAwAUAAkJZCSdBQCAAwAVAAIJDhuSMACdAAAAAA==.Moistpole:BAAANQADCgcICwAAAA==.Mojostormale:BAAANQADCgEIAQAAAA==.Monanarr:BAAANQADCgEIAgABNQAECgEIAQABAAAAAA==.Monmonk:BAAANQAECgEIAQAAAA==.Moograin:BAAANQABCgQIBAAAAA==.Moonalisa:BAAANQADCgYIFAAAAA==.Moondropz:BAAANQADCgcIBwAAAA==.Moonsblood:BAAANQAECgIIAwAAAA==.Moontara:BAAANQAECgMICAAAAA==.Moopsy:BAAANQAECgEIAgAAAA==.Mops:BAAANQAECgIIAwAAAA==.',
Mu='Muldoom:BAAANQABCgQIAgAAAA==.Mur:BAAANQAECgIIAwAAAA==.Murdertoys:BAAANQADCgcIBwAAAA==.',
My='Mycotoxin:BAAANQAECgEIAQAAAA==.Myrrdan:BAAANQAECgQIBQAAAA==.Myrrh:BAAANQADCgEIAQAAAA==.Mysst:BAAANQADCggIJQAAAA==.Mysteerie:BAAANQAECgQIBQAAAA==.Mythlogic:BAAANQAECgIIAwAAAA==.Mythsham:BAAANQADCgUIEgAAAA==.',
['Má']='Mángo:BAAANQAECgYIEAAAAA==.',
['Mù']='Mùshu:BAAANQADCgYIBgAAAA==.',
Na='Nardaran:BAAANQAECgcICwAAAA==.Natsumi:BAAANQADCggIDAAAAA==.',
Ne='Needcoffee:BAAANQADCgcIEgAAAA==.Neemixa:BAAANQADCggIFQAAAA==.Neonh:BAAANQADCggIFwAAAA==.',
Ni='Nightwissh:BAAANQAECgEIAQAAAA==.Nitestar:BAAANQADCgUIEAAAAA==.Nitevoker:BAAANQAECgMIBgAAAA==.',
No='Nocturnus:BAAANQADCgQICAAAAA==.Nordvoker:BAAANQAECgYIDAAAAA==.Nospheratu:BAABNQAECoEpAAIIAAgJAhuqRACCAgAIAAgJAhuqRACCAgABNQADCgYIBgABAAAAAA==.',
Nu='Nubu:BAAANQADCgYIDQAAAA==.',
Ny='Nycepala:BAAANQADCggIFwAAAA==.Nylaith:BAAANQADCgUIBQAAAA==.Nyni:BAABNQAECoEgAAITAAkJWRSQHAA7AgATAAkJWRSQHAA7AgAAAA==.Nythshade:BAAANQADCgYIBgAAAA==.Nyxe:BAAANQAECgEIAQABNQAECgkJIAATAFkUAA==.',
['Nü']='Nümnüts:BAAANQAECgIIAwAAAA==.',
Of='Offworlder:BAAANQADCggIFAAAAA==.',
Ol='Olokun:BAAANQABCgUIBQAAAA==.',
On='Onlyhoofs:BAEANQAECgYIEgAAAA==.',
Oo='Oofm:BAAANQAECgUIEQAAAA==.Oospider:BAAANQADCggIIAAAAA==.',
Op='Ophearia:BAAANQADCgYIEwAAAA==.Optimiss:BAAANQAECgIIAgAAAA==.',
Or='Orcboy:BAAANQAECgUICgAAAA==.Orken:BAAANQADCgEIAQAAAA==.Orthanu:BAAANQADCgUIBQAAAA==.',
Os='Osamul:BAAANQADCgYIBgAAAA==.',
Pa='Paieth:BAAANQAECgQIBwAAAA==.Paladerp:BAAANQAECgQIDwAAAA==.Palaresx:BAAANQAECgQIBwABNQAECgYIDQABAAAAAA==.Palean:BAAANQABCgQIAgAAAA==.Pallyshunter:BAAANQAECgUICwAAAA==.Pancake:BAAANQAECgQIBAAAAA==.Panchamp:BAAANQADCgcIDgAAAA==.Pandamourne:BAAANQADCgcICQAAAA==.Pandori:BAAANQAECgYIDAAAAA==.Panetar:BAAANQABCggICAAAAA==.Parchmentham:BAAANQAECgcIEQAAAA==.Paryniux:BAAANQAECgMIAwAAAA==.Patience:BAAANQADCgMIAwAAAA==.',
Pi='Pinchiy:BAAANQADCgQIBAAAAA==.Pinkpanthir:BAAANQAECgUICQAAAA==.',
Pj='Pjay:BAAANQAECgEIAQAAAA==.',
Pl='Plisky:BAAANQADCggIEQAAAA==.',
Po='Pollywaffle:BAAANQADCggIDAAAAA==.Portals:BAAANQADCggIEAAAAA==.Poùnd:BAAANQADCgYIDAABNQAECgUICQABAAAAAA==.',
Pr='Praiseme:BAAANQADCgYIEwAAAA==.Predz:BAAANQAECgQIBQAAAA==.Predzious:BAAANQABCgYICgABNQAECgQIBQABAAAAAA==.Prepaired:BAAANQADCggICAABNQAFFAUIEAAFAGcYAA==.Pretzelmix:BAAANQADCgYIBgAAAA==.Priestiitute:BAAANQADCgUIBQAAAA==.',
Ps='Psyreq:BAAANQAECgQIBQAAAA==.',
Pu='Punkey:BAAANQAECgQIBgAAAA==.',
Qu='Quartquartma:BAAANQAECgEIAgAAAA==.',
Ra='Raedia:BAAANQADCgMIAwAAAA==.Raft:BAAANQADCggICAAAAA==.Rahll:BAAANQABCggIDgAAAA==.Raindrops:BAAANQADCggICAAAAA==.Ravachiar:BAAANQAECgUICgAAAA==.Ravenathas:BAAANQADCgUIEgABNQADCgcIEQABAAAAAA==.Ravenimus:BAAANQADCgcIEQAAAA==.Ravic:BAAANQAECgIIAgAAAA==.Razeld:BAAANQADCggIFwAAAA==.Razhun:BAAANQADCggIJQAAAA==.Razia:BAAANQAECgIIAgAAAA==.Razzax:BAAANQADCgUIBQAAAA==.Razzmata:BAAANQAECgYICAAAAA==.',
Re='Reckendorf:BAAANQAECgEIAgAAAA==.Redefine:BAAANQAECgQIAwAAAA==.Reflet:BAAANQAECgIIAgAAAA==.Rell:BAAANQAECgYIBwAAAA==.Rentress:BAAANQADCgYIFQAAAA==.Resolution:BAAANQADCggICAAAAA==.Restik:BAAANQADCggIFgAAAA==.Revyre:BAAANQADCgQIBQAAAA==.Rexxnaar:BAAANQADCggIDAAAAA==.Rexy:BAAANQAECgYICgAAAA==.',
Rh='Rhiotannis:BAAANQAECgYIBgAAAA==.Rhombus:BAAANQADCgYIBgAAAA==.Rhots:BAAANQAECgYICgAAAA==.',
Ri='Ricketyrekt:BAAANQADCgcIBwAAAA==.Rimara:BAAANQAECgIIAwAAAA==.Rishari:BAAANQADCggIEQAAAA==.',
Ro='Rocadin:BAAANQAECgQIBAAAAA==.Rocmon:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Rorisala:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Rottlee:BAAANQADCgcICwAAAA==.Rowshamboe:BAAANQADCgYIFQAAAA==.Rozabella:BAAANQAECgYIDAAAAA==.',
Ru='Rune:BAAANQAECgIIAgABNQAECggIFgALAMEWAA==.',
['Rê']='Rêdylive:BAAANQAECgIIAgAAAA==.',
['Rï']='Rïkku:BAAANQAECgYIBgAAAA==.',
Sa='Saelska:BAAANQAECgEIAQAAAA==.Sahven:BAAANQADCgYICQAAAA==.Sakuraharu:BAAANQAECgYIDgAAAA==.Sakuraharune:BAAANQAECgEIAgAAAA==.Sakuraharuno:BAAANQAECgYIDgAAAA==.Sakuura:BAAANQAECgQIBAAAAA==.Sarang:BAAANQAECgUICwAAAA==.Sassystrasza:BAAANQADCgQIBAAAAA==.Savagepaw:BAAANQAECgYIDAAAAA==.',
Sc='Scarbz:BAAANQAECgQIBQAAAA==.Scrtchnsniff:BAAANQABCgEIAQAAAA==.',
Se='Sehun:BAAANQADCgcIBwABNQAECgYIDwABAAAAAA==.Selennys:BAAANQAECgEIAQAAAA==.Selest:BAAANQAECgQIBAAAAA==.',
Sh='Shadowkain:BAAANQAECgIIAwAAAA==.Shadøws:BAAANQAECgUICgAAAA==.Shagz:BAAANQADCgYIEgAAAA==.Shallios:BAAANQADCgYIEAAAAA==.Shamajov:BAAANQADCgYICgABNQAECgIIAwABAAAAAA==.Shamankiing:BAAANQADCgYIBgAAAA==.Shamannigans:BAAANQAECgEIAQAAAA==.Shammyhagar:BAAANQADCggICQAAAA==.Shamnow:BAAANQADCgEIAQAAAA==.Shaytan:BAAANQAECgEIAQAAAA==.Sheogorath:BAAANQAECgcIEQAAAA==.Shocksocks:BAAANQAECgQIBQAAAA==.Shoujian:BAAANQADCgcIDQAAAA==.',
Si='Sianien:BAAANQAECgEIAQAAAA==.Sickology:BAAANQAECgYIEAAAAA==.Siinatra:BAAANQAECggIEAABNQAFFAEIAQABAAAAAA==.Siinatrah:BAAANQAFFAEIAQAAAA==.Silverstarr:BAAANQADCgYICAAAAA==.Sinnafein:BAAANQADCgcIBwAAAA==.Siohban:BAAANQAECgQIBQAAAA==.Sionel:BAAANQADCgUIBQAAAA==.Siphirahah:BAAANQAECgIIAwAAAA==.',
Sk='Skürge:BAAANQAECgMIBAAAAA==.',
Sl='Slapntits:BAAANQABCgcIDQAAAA==.Slimreaper:BAAANQAECgcIBgAAAA==.Slothination:BAAANQAECgcIDAABNQAECgkJGAAOAHMdAA==.Slurrydots:BAAANQAECgcIEwAAAA==.',
Sn='Snaglvr:BAAANQADCgIIAgAAAA==.Snappyb:BAAANQADCgIIAgAAAA==.Snowtownz:BAAANQAECgcIDwAAAA==.Snörichäun:BAAANQADCgcIEAAAAA==.',
So='Soiboii:BAAANQADCgQIBAAAAA==.Sokraxx:BAABNQAECoEaAAIRAAkJQSVUAADfAwARAAkJQSVUAADfAwAAAA==.Sonozap:BAAANQAECgcIDQAAAA==.Sonyc:BAAANQADCgQIBAAAAA==.Soothlocked:BAAANQAECgEIAQAAAA==.Soraflash:BAAANQADCggICAAAAA==.Soulreaperau:BAAANQAECgEIAQAAAA==.',
Sp='Spearzy:BAAANQADCggICQABNQAECgUICQABAAAAAA==.Spicedgoat:BAAANQADCggIGAAAAA==.Spinandwin:BAAANQAECgYIEQAAAA==.Springroll:BAAANQAECgYIDgAAAA==.',
Sq='Squishikayla:BAAANQADCgEIAQAAAA==.Squishyman:BAAANQAECgcIEAAAAA==.',
Sr='Sram:BAABNQAECoEXAAISAAkJRSFqAwBmAwASAAkJRSFqAwBmAwAAAA==.Srbenda:BAAANQADCgUICgAAAA==.',
Ss='Sstormmy:BAAANQAECgQIDwAAAA==.',
St='Stabit:BAAANQADCggIDAAAAA==.Starless:BAAANQAECgQIBQAAAA==.Starmyst:BAAANQADCgYIBgAAAA==.Steelbull:BAAANQAECgQICAABNQAECgUICgABAAAAAA==.Steelmyth:BAAANQAECgUICQAAAA==.Steeven:BAAANQADCgIIAgAAAA==.Strìder:BAAANQAECgEIAQAAAA==.Strîder:BAAANQAECgEIBAAAAA==.',
Su='Summerskye:BAAANQAECgUICQAAAA==.',
Sy='Sy:BAAANQAECgUIEAABNQAECggIEwABAAAAAA==.Sycamore:BAAANQADCgYICQAAAA==.Sydor:BAAANQADCggIHwAAAA==.Sylennia:BAAANQAECgEIAQAAAA==.Sylvatrix:BAAANQAECgQIBAAAAA==.Symbiont:BAAANQADCgcIEgAAAA==.',
Sz='Szarni:BAAANQAECgEIAQAAAA==.',
Ta='Tabitrisao:BAAANQAECgEIAQAAAA==.Tamarin:BAAANQABCgIIAgAAAA==.Taridalas:BAAANQAECgIIAgAAAA==.Taucetid:BAAANQAECgIIAgAAAA==.Tazington:BAAANQAECgQICAAAAA==.Tazuki:BAAANQABCgIIAgAAAA==.',
Te='Tehsharp:BAAANQAECgYIDwAAAA==.Tehwarrior:BAAANQABCgcIBwAAAA==.Telraena:BAAANQAECgIIAgAAAA==.Terokkar:BAAANQAECgEIAQAAAA==.Tesalach:BAAANQADCgUIBgAAAA==.Teul:BAAANQAECgUICAABNQAECgcIEwABAAAAAA==.',
Th='Thalorian:BAAANQAECgMIAwAAAA==.Thananerion:BAAANQADCgMIAwAAAA==.Thealiaa:BAAANQADCgIIAgAAAA==.Thehexorcist:BAAANQADCggICAAAAA==.Thiea:BAAANQAECgYIDAAAAA==.Thorel:BAAANQADCgcICAABNQAECgYICgABAAAAAA==.Thorrimar:BAAANQADCgUIBQAAAA==.Thorsake:BAAANQAECgYIEAAAAA==.Thromgorr:BAAANQAECgYIDQAAAA==.Thundercant:BAAANQAECggIDwABNQAFFAUICAAWAJ0TAA==.Thunderpog:BAACNQAFFIEIAAIWAAUJnRNGAADTAQAWAAUJnRNGAADTAQA1AAQKgRsABBcACQntHKYLAMICABcACAlNHaYLAMICABgABgkBGO9FAG0BABYABAkUHUcJAEABAAAA.',
Ti='Tillicity:BAAANQAECgcIEgAAAA==.Tilzabeth:BAAANQADCgQICgABNQAECgcIEgABAAAAAA==.Timewarp:BAAANQADCggIBQAAAA==.Tinhu:BAAANQADCgcIBwAAAA==.Tinypi:BAAANQAECgQIBQAAAA==.',
To='Tomahawk:BAAANQADCgEIAQAAAA==.Toosuss:BAAANQADCgYICgAAAA==.Topshot:BAAANQAECgYICQAAAA==.Torags:BAAANQADCgQIBAAAAA==.',
Tr='Trazendeath:BAAANQADCgMIAwAAAA==.Treesome:BAAANQAECgMIBQABNQAECgQIBgABAAAAAA==.Treesource:BAAANQAECgQIBAAAAA==.Trigaa:BAAANQADCggIDAAAAA==.Trojans:BAAANQAECgEIAQAAAA==.',
Ts='Tsaiko:BAAANQADCgcIGAAAAA==.',
Tw='Twirls:BAAANQAECgUICQAAAA==.Twirlshair:BAAANQADCgUIBQAAAA==.',
Ty='Tynzel:BAAANQAECgEIAQAAAA==.Tyvaria:BAAANQADCgYIDQAAAA==.',
['Tà']='Tàkhisis:BAAANQAECgEIAQAAAA==.',
Ul='Ullbenxt:BAAANQAECgIIAgAAAA==.',
Um='Umf:BAAANQADCggIEQABNQAECgcIEQABAAAAAA==.',
Un='Underwhelmed:BAAANQAECgIIAgAAAA==.Unitofglory:BAAANQADCgIIAgABNQAECgQIDwABAAAAAA==.Unitoflife:BAAANQAECgQIDwAAAA==.Unitofshapes:BAAANQAECgQIBQABNQAECgQIDwABAAAAAA==.',
Va='Valanar:BAAANQADCgMIAwAAAA==.Valdormu:BAAANQAECgQICAAAAA==.Vanador:BAAANQAECgQIBQAAAA==.Vanarel:BAAANQADCgYIDgAAAA==.Vanel:BAAANQADCgYIBgAAAA==.Vannbeef:BAAANQAECgIIAwAAAA==.Varthlight:BAAANQAECgIIAwAAAA==.',
Ve='Veinytotem:BAAANQADCgUIBQAAAA==.Veloran:BAABNQAECoEzAAQQAAkJhBYRGAC6AgAQAAkJ9BURGAC6AgAZAAgJIg+kHQC9AQAaAAIJ5AvKCQBrAAAAAA==.Venomsspawn:BAAANQAECgQICAAAAA==.Vernonia:BAAANQADCgEIAQAAAA==.Vexahlia:BAAANQADCgMIBAAAAA==.Veyrathor:BAAANQADCgIIAgAAAA==.',
Vi='Vio:BAACNQAFFIEMAAIbAAYJ9xjQAAA6AgAbAAYJ9xjQAAA6AgA1AAQKgSEAAhsACQmsJMcBALADABsACQmsJMcBALADAAAA.Virtues:BAAANQADCgMIAwAAAA==.Virtus:BAAANQADCgYIBwAAAA==.Viserys:BAAANQAECgQIBAAAAA==.',
Vo='Voidtouched:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Vows:BAAANQADCggICAAAAA==.',
Vu='Vuruul:BAAANQADCgYIDAAAAA==.',
Vy='Vypërz:BAAANQAECgcIEQAAAA==.Vyral:BAAANQAECgQIDwAAAA==.',
Wa='Wabssevo:BAAANQAECgQIBAABNQAECgkJFgAPANYXAA==.Wabssjnr:BAABNQAECoEWAAIPAAkJ1hemEgDMAgAPAAkJ1hemEgDMAgAAAA==.Wararesx:BAAANQADCgUIBwABNQAECgYIDQABAAAAAA==.Warizard:BAAANQAECgQIDAAAAA==.Wattanuhbii:BAAANQADCgQIBAAAAA==.Wayz:BAAANQADCgMIAwAAAA==.Wayzpala:BAAANQADCggIDAAAAA==.',
We='Weyoun:BAAANQAECgEIAQAAAA==.',
Wh='Wheetie:BAAANQAECgQIBwAAAA==.',
Wi='Williwaw:BAAANQAECgEIAQAAAA==.Winterstormm:BAAANQAECgIIAwAAAA==.',
Wn='Wno:BAAANQADCgcIBwAAAA==.',
Wo='Wobbuffet:BAABNQAECoEYAAIcAAkJqCNaAwC1AwAcAAkJqCNaAwC1AwAAAA==.Wolfen:BAAANQADCgcIDgAAAA==.',
Wy='Wyrnn:BAAANQAECgYIDQAAAA==.',
Xa='Xaniran:BAAANQADCgYICAAAAA==.Xaye:BAAANQADCgcIBwAAAA==.',
Xe='Xelbino:BAAANQADCgEIAQAAAA==.',
Xi='Xiaobi:BAAANQAECgcIEwAAAA==.Xintar:BAAANQADCggIEAAAAA==.Xiomana:BAAANQAECgEIAQAAAA==.Xion:BAAANQAECgYIDwAAAA==.',
Xy='Xyluna:BAAANQADCgYIBgABNQAECggIFwAWAEMbAA==.',
Ye='Yebanned:BAAANQADCggICAABNQAFFAUIDAAQAK8OAA==.Yellowajah:BAAANQAECgQICwAAAA==.',
Yi='Yify:BAAANQADCgUIBQABNQADCgcIEQABAAAAAA==.',
Yn='Yneva:BAAANQAECgEIAgAAAA==.',
Yw='Ywrensire:BAAANQADCgQIBAAAAA==.',
Za='Zaabra:BAAANQAECgEIAQAAAA==.Zaion:BAAANQAECgMIBgAAAA==.',
Ze='Zealis:BAAANQAECgUICAAAAA==.Zebby:BAAANQAECgUIBQAAAA==.Zedar:BAAANQAECgEIAQABNQAECgcIHwADAM8cAA==.Zerull:BAAANQADCgYIBgAAAA==.',
Zh='Zhi:BAAANQAECgIIAwAAAA==.',
Zi='Zilin:BAAANQAECgQIBQAAAA==.',
Zo='Zolce:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.',
Zu='Zurbi:BAAANQAECgEIAQABNQAECgcIEwABAAAAAA==.Zuularok:BAAANQADCgUIBQAAAA==.',
Zy='Zybaxos:BAAANQAECgcIEQAAAA==.',
Zz='Zzro:BAAANQADCgcICQAAAA==.',
['Ãr']='Ãrçâñîst:BAAANQADCgcIBwAAAA==.',
['År']='Årchon:BAAANQAECgQIBAAAAA==.Årtix:BAAANQADCgYIBgABNQADCgYICgABAAAAAA==.',
['Îs']='Îssy:BAAANQAECgIIAwAAAA==.',
['Ôr']='Ôrkásh:BAAANQADCgcIDgAAAA==.',
['Öm']='Ömegoss:BAAANQAECgEIAgAAAA==.',
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
