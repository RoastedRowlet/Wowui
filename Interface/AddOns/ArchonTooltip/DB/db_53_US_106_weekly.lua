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

local lookup = {'DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Monk-Brewmaster','Unknown-Unknown','Rogue-Assassination','Evoker-Preservation','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Warrior-Arms','Warrior-Fury','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Subtlety','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Shaman-Enhancement','Warrior-Protection','Hunter-Survival','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','Priest-Shadow',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=53,date='2026-09-15',data={Af='Aft:BAABNQAECoEaAAIBAAkJ8SOdAgCsAwABAAkJ8SOdAgCsAwAAAA==.',
Ai='Aislin:BAAANQADCgYIBgAAAQ==.',
Ak='Akumu:BAAANQAECgYICwAAAA==.',
Al='Alarkin:BAABNQAECoEfAAMCAAkJ4R3+HwCKAgACAAcJYSD+HwCKAgADAAgJLRQRGAANAgAAAA==.Alasmira:BAAANQADCggIEAAAAA==.Alcarde:BAAANQAECgcIDQAAAA==.Aldoan:BAAANQADCggIFwAAAA==.Aleza:BAAANQADCgEIAQAAAA==.Alialeman:BAAANQADCgIIAgAAAA==.Alistiri:BAAANQAECgQIBgAAAA==.Alix:BAAANQADCgcIFQAAAA==.Allforge:BAAANQAECgIIBAAAAA==.Almina:BAAANQAECgQIBQAAAA==.Alpal:BAABNQAECoEgAAIEAAkJ5xrCDAAGAwAEAAkJ5xrCDAAGAwAAAA==.',
Am='Ambs:BAAANQAECgQIBgAAAA==.',
An='Analyse:BAAANQABCgIIAgAAAA==.Andalya:BAAANQAECgIIAgAAAA==.Andaria:BAAANQADCgUIAgAAAA==.Angharrad:BAAANQADCgIIAgAAAA==.',
Ao='Aonani:BAAANQADCgcIBwAAAA==.',
Ap='Aprix:BAAANQAECgYICwAAAA==.',
Ar='Aralyn:BAAANQADCgYIBgAAAA==.Arejay:BAAANQAECgEIAQAAAA==.Argeth:BAAANQAECgEIAQAAAA==.Arshika:BAAANQAECgUICQAAAA==.Artek:BAAANQADCgMIAwAAAA==.Arthan:BAAANQADCgYIBwAAAA==.Arthonix:BAAANQAECgQIBAAAAA==.Arthurleywin:BAAANQAECgQICgAAAA==.Arvis:BAAANQADCgcIFAAAAA==.',
As='Asamia:BAACNQAFFIEFAAIFAAMJpQ/3AQDWAAAFAAMJpQ/3AQDWAAA1AAQKgRwAAgUACQmsIfABAE8DAAUACQmsIfABAE8DAAAA.Ashaki:BAAANQAECgMIBQAAAA==.Astå:BAAANQADCggICAAAAA==.',
At='Athyná:BAAANQADCgIIAgAAAA==.',
Au='Auroramoon:BAAANQAECgEIAQAAAA==.',
Av='Avana:BAAANQADCgIIAgAAAA==.',
Aw='Awake:BAAANQAECgYIDAAAAA==.',
Ax='Axionar:BAAANQAECgMIBAAAAA==.',
Az='Azshauria:BAAANQABCgYICAAAAA==.Azurend:BAAANQAECgIIAwAAAA==.Azázél:BAAANQAECgEIAQAAAA==.',
Ba='Badtimeboy:BAAANQAECgEIAQAAAA==.Baffle:BAAANQADCggIGQABNQAECgYICwAGAAAAAA==.Bahula:BAAANQAECgMIBgAAAA==.Bainehuln:BAAANQAECgQIBAAAAA==.Bastianos:BAAANQAECgQIBQAAAA==.Batsom:BAAANQABCgEIAQAAAA==.',
Be='Bellapearl:BAAANQAECgEIAQAAAA==.Bellmont:BAAANQADCggIFAAAAA==.Belron:BAAANQAECgEIAQABNQAECgYIDQAGAAAAAA==.Bernes:BAAANQAECgcIEQAAAA==.',
Bi='Bigteef:BAAANQADCgUICQAAAA==.Birdhouse:BAAANQAECgQIBAAAAA==.',
Bl='Blackthornn:BAABNQAECoEgAAIHAAkJ8R8xBAAyAwAHAAkJ8R8xBAAyAwAAAA==.Blastin:BAAANQADCggICgAAAA==.Blastofel:BAAANQADCgUIBQAAAA==.Bloodorphan:BAAANQADCgIIAgABNQAECgcIEAAGAAAAAA==.Bloodreign:BAAANQADCgYIBgAAAA==.Blottzilla:BAABNQAECoEgAAIIAAkJyBemCQCiAgAIAAkJyBemCQCiAgAAAA==.Bluestreak:BAAANQADCgYICgAAAA==.',
Bo='Bobbyray:BAAANQADCggIDAAAAA==.Bobertbigg:BAAANQAECgYIDgAAAA==.Bowbuttkick:BAABNQAECoEZAAMCAAkJtSKQBQB2AwACAAkJtSKQBQB2AwADAAIJBxSjPgB3AAAAAA==.Boxiebrown:BAABNQAECoEdAAICAAkJ4hHXIgB7AgACAAkJ4hHXIgB7AgAAAA==.',
Br='Bralae:BAAANQAECgMIAwAAAA==.Breaya:BAAANQADCgIIAgAAAA==.Brewskiez:BAAANQADCggIDQAAAA==.Bricktop:BAAANQADCgIIAgAAAA==.Brokuo:BAABNQAECoEfAAMJAAkJDiQlBwBaAwAJAAkJxiMlBwBaAwAKAAgJJx52CADfAgAAAA==.Broon:BAAANQADCgYIDQAAAA==.Brucellosis:BAAANQAECgUICQAAAA==.',
Bu='Bubbawoodkin:BAAANQADCgcIBwAAAA==.Buffpres:BAAANQADCgUIBQABNQAECgQIBgAGAAAAAA==.Buzzlez:BAABNQAECoEgAAILAAkJsBhhEgC1AgALAAkJsBhhEgC1AgAAAA==.',
Ca='Candyquartz:BAAANQADCgMIAwAAAA==.Carkleaschah:BAAANQADCgYICwABNQAECgQIBAAGAAAAAA==.Cat:BAAANQABCgIIAgAAAA==.',
Ch='Chaddrique:BAAANQABCgQIBgAAAA==.Chadgolas:BAAANQADCgIIAgAAAA==.Chadimir:BAAANQAECgQIBQAAAA==.Chahae:BAABNQAECoElAAIJAAkJvyUuAQDeAwAJAAkJvyUuAQDeAwAAAA==.Channintotem:BAEANQAECgEIAQABNQAECgYICgAGAAAAAA==.Cheerwine:BAAANQAECgYIDQAAAA==.Cheezits:BAAANQADCgUIBQAAAA==.',
Cl='Clapdo:BAEBNQAECoEfAAMMAAkJoSQPBgCmAwAMAAkJoSQPBgCmAwANAAEJNRt0GQBGAAAAAA==.Clinician:BAAANQADCggIFwAAAA==.',
Co='Commandor:BAAANQADCgEIAQAAAA==.Congolense:BAAANQAECgYICwAAAA==.Corbzz:BAAANQADCgMIAwAAAA==.Cowacusrex:BAAANQADCgUIBQAAAA==.',
Cp='Cptrisky:BAAANQABCgIIAgAAAA==.',
Cr='Crazzenburns:BAAANQAECgQIBQABNQAECgcIEgAGAAAAAA==.Creamer:BAAANQAECgUICgAAAA==.Crunchin:BAABNQAECoEdAAMEAAkJ5ANUPADEAQAEAAkJ5ANUPADEAQAOAAcJigy1XACJAQAAAA==.',
Cu='Cutedwarfxd:BAABNQAECoEfAAIBAAkJ4SU2AQDYAwABAAkJ4SU2AQDYAwAAAA==.',
Da='Dakkadakka:BAAANQADCggIDQAAAA==.Danìel:BAABNQAECoEgAAMPAAkJzBthCgDqAgAPAAkJqRphCgDqAgAQAAgJvRWXGAAjAgAAAA==.Darkarts:BAAANQADCgIIAgAAAA==.Dartwo:BAAANQAECgEIAQAAAA==.',
De='Deathspoons:BAACNQAFFIEGAAIBAAQJdxRYBQAwAQABAAQJdxRYBQAwAQA1AAQKgSEAAgEACQmcIGMGAFYDAAEACQmcIGMGAFYDAAAA.Delecto:BAAANQAECgMIAwAAAA==.Delushoni:BAAANQADCgUIBQAAAA==.Dendalaus:BAABNQAECoEeAAMRAAkJqyQKCADDAgARAAcJ1CMKCADDAgAHAAQJ3iLBHACSAQAAAA==.Derkamental:BAAANQAECgIIAgAAAA==.',
Di='Digallo:BAAANQADCggICwAAAA==.Dimsumbun:BAAANQAECgMIAwAAAA==.Dingledorf:BAAANQAECgYICgAAAA==.Dinoxeye:BAAANQAECgQIBwAAAA==.',
Do='Donut:BAAANQADCgMIAwAAAA==.',
Dr='Dragonpandas:BAAANQADCggICAABNQAECggIHQAJANIfAA==.Dramonk:BAABNQAECoEeAAISAAkJ1iHxAwBWAwASAAkJ1iHxAwBWAwAAAA==.Dro:BAAANQABCgIIAgAAAA==.Druinlock:BAAANQADCgUIBQAAAA==.',
Du='Dustydrewid:BAAANQADCgEIAQAAAA==.',
Dy='Dyre:BAAANQAECggIBAAAAA==.',
Ei='Eir:BAAANQAECgUICAAAAA==.',
El='Ellsnarl:BAAANQADCgYIBgAAAA==.',
Em='Emeraldjin:BAAANQAECgEIAQAAAA==.',
En='Ensera:BAAANQADCggIGwAAAA==.',
Er='Eraesong:BAAANQADCgMIAwAAAA==.Erielyn:BAAANQAECgIIBAAAAA==.Ernet:BAAANQAECgUICQAAAA==.',
Ex='Extraho:BAAANQAECgUICgAAAA==.',
Fa='Fabled:BAABNQAECoEfAAMTAAkJ+SLeAgD9AgATAAgJfCDeAgD9AgAUAAQJeCN8SwCdAQAAAA==.Faeyice:BAAANQAECgQIBQAAAA==.',
Fe='Fearmachine:BAAANQADCggIDgABNQAECgMIBAAGAAAAAA==.Feyden:BAAANQAECgQIBAAAAA==.',
Ff='Ffxivcatgirl:BAAANQADCgQIBAABNQAECgkJHwABAOElAA==.',
Fi='Fielton:BAAANQADCgEIAQABNQAECgYIBwAGAAAAAA==.Fiiryazell:BAAANQAECgEIAQAAAA==.Fijaswarerth:BAAANQAECgMIBAAAAA==.Fijaswitcher:BAAANQAECgMIAwAAAA==.Fimbulvargr:BAAANQAECgQIBQAAAA==.Finiith:BAAANQAECgUIBQABNQAECgkJHwACAOEdAA==.Firedragön:BAAANQAECgEIAQAAAA==.',
Fl='Flogdanoggin:BAAANQADCgUIBQAAAA==.Flogurnoggin:BAAANQADCggIAQAAAA==.Fluffyokami:BAAANQAECgQIBwAAAA==.Flyingrodent:BAAANQAECgQICwAAAA==.',
Fo='Foneer:BAAANQAECgUICAAAAA==.Forestsky:BAAANQAECgQIBQAAAA==.',
Fr='Freezepop:BAAANQAECgYICgAAAA==.Frenchieboi:BAAANQADCgcIDQABNQAECgUICQAGAAAAAA==.Frenchielock:BAAANQAECgUICQAAAA==.Frenchthyr:BAAANQAECgUICAABNQAECgUICQAGAAAAAA==.Frostbeast:BAAANQADCgEIAQAAAA==.',
Ga='Galdiian:BAAANQADCgYIEwAAAA==.Gawdspet:BAABNQAECoEdAAMUAAkJKh3RKAA+AgAUAAcJIRzRKAA+AgATAAQJGRdLIAA3AQAAAA==.',
Gh='Ghosi:BAAANQAECgcIEQAAAA==.',
Gl='Glaivier:BAAANQAECgIIAgAAAA==.',
Go='Goodtimeboy:BAAANQADCgYIBwAAAA==.Goregrind:BAAANQAECgcIEwAAAA==.Gorgeous:BAAANQADCgIIAgAAAA==.Gorius:BAAANQADCgcIDwAAAA==.',
Gr='Grampman:BAAANQADCgMIAwAAAA==.Gremory:BAAANQAECgIIAwAAAA==.Grimholt:BAAANQADCgIIAgAAAA==.',
Gu='Guldank:BAAANQAECgIIAgAAAA==.Guretta:BAAANQAECgQIBQAAAA==.',
Gw='Gwynhwyvar:BAAANQAECgIIAgAAAA==.',
Ha='Haeneros:BAAANQAECgQIBQAAAA==.Handmemytank:BAAANQAECgIIAwABNQAECgcIEQAGAAAAAA==.Harumi:BAAANQAECgUICgAAAA==.',
He='Hearo:BAAANQAECgEIAQAAAA==.Heavyhead:BAAANQADCggIGQAAAA==.Hedgehog:BAAANQAECgYIDwAAAA==.Heightning:BAAANQAECgQIBgAAAA==.Heisenberf:BAABNQAECoEgAAIVAAkJ6RzGJgD3AgAVAAkJ6RzGJgD3AgAAAA==.Hextrathicc:BAAANQAECgcIEgAAAA==.',
Ho='Holybuttkick:BAAANQAECgQICQABNQAECgkJGQACALUiAA==.Hoozurdaddy:BAAANQAECgYICwAAAA==.',
Ic='Icê:BAAANQAECgQIBQAAAA==.',
Ig='Igamm:BAAANQADCgMIAwAAAA==.Ignatius:BAAANQAECgIIAgAAAA==.Igniting:BAAANQAECgcIEAABNQAECgIIAgAGAAAAAA==.',
Ik='Ikillyoutoo:BAAANQAECgUIBgAAAA==.',
Im='Impenetrable:BAAANQADCgcIBwAAAA==.Impression:BAABNQAECoEXAAIEAAkJkyYjAAD+AwAEAAkJkyYjAAD+AwAAAA==.Imprison:BAAANQAECgEIAQABNQAECgkJFwAEAJMmAA==.',
In='Incarnated:BAAANQAECgYIDQAAAA==.Incursion:BAAANQAECgMIBAAAAA==.Insayn:BAAANQADCgIIAgABNQAECgcIDwAGAAAAAA==.Inviçtus:BAAANQAECgQIBAAAAA==.',
Ir='Ironwolf:BAAANQAECgYIDwAAAA==.',
Ja='Jademoot:BAAANQAECgQIBgAAAA==.Jadis:BAAANQADCgUIBQAAAA==.Jaeaoria:BAAANQABCgIIAQAAAA==.Jaxblack:BAAANQADCggIEAAAAA==.Jaxurbate:BAAANQAECgIIAgAAAA==.Jayvlyn:BAAANQAECgEIAQAAAA==.',
Jj='Jjman:BAAANQAECgYIBwAAAA==.Jjuicyfruit:BAAANQADCgYIEQAAAA==.',
Jo='Joftokal:BAAANQAECgMIBQAAAA==.Jokesonme:BAAANQADCgYICgAAAA==.Jonebonejovi:BAAANQADCgIIAgAAAA==.Jorabna:BAAANQADCgYICgAAAA==.Joyboy:BAAANQAECgYIEQAAAA==.',
Ka='Kakiso:BAAANQAECgUICAAAAA==.Kalanash:BAAANQADCgUIBQAAAA==.Kalim:BAAANQADCgIIAgAAAA==.Kaloneras:BAAANQADCgYICAAAAA==.Kattle:BAABNQAECoEgAAIWAAkJXSJDAQCSAwAWAAkJXSJDAQCSAwAAAA==.',
Ke='Kellistus:BAAANQADCgUICQAAAA==.Keyrasky:BAAANQADCgYICQAAAA==.',
Kh='Khailyn:BAAANQADCgEIAQAAAA==.',
Ki='Kikuu:BAAANQAECgQIBgAAAA==.Kin:BAAANQADCgUIBQAAAA==.Kiradanna:BAAANQAECgYIEgAAAA==.Kiroa:BAAANQAECgIIAgAAAA==.Kitå:BAEANQAECgQIBwAAAA==.Kiyoshiru:BAAANQADCgUIBQAAAA==.',
Kn='Knoks:BAAANQAECgYIDwAAAA==.',
Ko='Koff:BAAANQAFFAIIAgAAAA==.Koino:BAAANQADCggICAAAAA==.Koreshei:BAAANQADCgYIFwAAAA==.',
Kr='Krixxus:BAAANQAECgIIAwAAAA==.',
Ku='Kuni:BAAANQAECgQIBQAAAQ==.Kurius:BAAANQABCgIIAgAAAA==.',
Ky='Kylian:BAAANQAECgQIBAABNQAECgYIEgAGAAAAAA==.',
La='Lamynx:BAAANQAECgQICQAAAA==.Larinstore:BAAANQADCggIEwAAAA==.Lazydragon:BAAANQAECgMIBQAAAA==.',
Le='Lelouch:BAAANQABCgEIAQAAAA==.Leone:BAAANQAECgQIBAABNQAECgYICwAGAAAAAA==.',
Li='Liberation:BAAANQAECgYIDAAAAA==.Lilgirlblue:BAAANQAECgYIBgAAAA==.Lilreggie:BAAANQADCggIFAAAAA==.Lilvoids:BAABNQAECoEcAAMTAAcJ0AkCIgAoAQATAAYJkAcCIgAoAQAUAAQJbAhLgwDnAAAAAA==.Lineste:BAAANQAECgIIAwAAAA==.Lion:BAAANQAECgUICAAAAA==.',
Ll='Llyolis:BAAANQADCgcICAABNQAECgIIAwAGAAAAAA==.',
Lo='Loldie:BAAANQAECgIIAwAAAA==.Lonepanda:BAABNQAECoEgAAIXAAkJqyP2AACdAwAXAAkJqyP2AACdAwAAAA==.Lorwynx:BAABNQAECoEYAAIVAAgJoRy1OQCrAgAVAAgJoRy1OQCrAgAAAA==.',
Lu='Luciliv:BAAANQADCgYIBgABNQAECgcIDwAGAAAAAA==.Lunado:BAAANQADCgUIBwAAAA==.Lupinaea:BAAANQADCggIGgAAAA==.',
Lv='Lvcifur:BAAANQABCgQIBAAAAA==.',
Ma='Mabellah:BAAANQADCggIKgAAAA==.Maemikyu:BAABNQAECoEWAAILAAYJZh50LwDqAQALAAYJZh50LwDqAQAAAA==.Magusultimis:BAAANQAECgEIAQAAAA==.Mahöshöjo:BAAANQADCgcIEQAAAA==.Maintank:BAAANQAECgQICQAAAA==.Makepoop:BAAANQAECgYIDAAAAA==.Maloa:BAAANQADCgYIBgAAAA==.Manbomanbo:BAAANQAECgQIBAABNQAECggIBAAGAAAAAA==.Marianita:BAAANQAECgcIDAAAAA==.Maureen:BAAANQADCgUIBQAAAA==.',
Me='Mediarahan:BAAANQADCgcIEQAAAA==.Melfist:BAAANQADCggIGwAAAA==.Melysse:BAAANQAECgQICAAAAA==.Mendocino:BAAANQADCgcIEAAAAA==.',
Mi='Mikiko:BAAANQAECgQICQAAAA==.Millcreek:BAAANQAECgIIAwAAAA==.Milliananeko:BAAANQADCgUICQABNQAECgIIAwAGAAAAAA==.Miracat:BAAANQAECgIIAgAAAA==.Missindragon:BAAANQAECgMIBQAAAA==.',
Mo='Moomoohead:BAAANQADCgMIBAAAAA==.Morberto:BAAANQABCggICgAAAA==.Morianne:BAAANQADCgQIBAAAAA==.Mormel:BAAANQAECgQIBQAAAA==.Morticus:BAAANQADCgQIBQAAAA==.',
Ms='Msthea:BAAANQAECgEIAQAAAA==.',
['Mä']='Mälina:BAAANQADCgcIEQAAAA==.',
Na='Narial:BAAANQADCgIIAQAAAA==.Narru:BAABNQAECoEeAAQCAAkJviIIBACSAwACAAkJviIIBACSAwADAAUJ6gqqKwALAQAYAAQJ4QoPCADMAAAAAA==.',
Ne='Nebyula:BAAANQAECgIIAgAAAA==.',
Ni='Nizuno:BAAANQADCgYIBgAAAA==.',
No='Norieka:BAAANQAECgEIAQAAAA==.Norvasc:BAAANQADCgEIAQAAAA==.Noskillidan:BAAANQADCgYIBgABNQAECgkJIAAVAOkcAA==.Notknoks:BAAANQADCggICAAAAA==.',
Nu='Numinous:BAAANQADCgUIBgABNQAECgYIDAAGAAAAAA==.',
Ny='Nykoleus:BAAANQAECgYICQAAAA==.Nylokar:BAAANQABCgIIAgAAAA==.',
Og='Oggoat:BAAANQAECgIIAgAAAA==.',
Pa='Painindaazz:BAAANQADCgYIEgAAAA==.Pallygranny:BAEANQAECgYICgAAAA==.Pawptart:BAAANQABCgQIBAAAAA==.',
Ph='Phyntom:BAAANQAECgEIAQAAAA==.',
Pi='Pibbs:BAABNQAECoEXAAIVAAkJxR8IIAAVAwAVAAkJxR8IIAAVAwAAAA==.',
Pl='Plaguepanda:BAABNQAECoEdAAQJAAgJ0h9rEgC+AgAJAAcJDSJrEgC+AgAKAAQJBRaTMQDXAAABAAEJFRp5fQA+AAAAAA==.Platinumcas:BAAANQADCgcIDgAAAA==.',
Po='Poohonroids:BAAANQAECgQICgAAAA==.Poppatroll:BAAANQADCggIEgAAAA==.',
Pr='Protagoras:BAAANQAECgEIAQAAAA==.',
['Pä']='Pänz:BAAANQAECgEIAQAAAA==.',
Ra='Rafig:BAABNQAECoEgAAIVAAkJgiVPAwDJAwAVAAkJgiVPAwDJAwAAAA==.Ragefyre:BAAANQADCggIEAAAAA==.Ralii:BAAANQADCgUIBQAAAA==.Ralobii:BAAANQAECgQIBgABNQADCgUIBQAGAAAAAA==.Ramellis:BAAANQADCgMIAwAAAA==.Ramses:BAABNQAECoEfAAMZAAkJfw+4KgAYAgAZAAkJfw+4KgAYAgAaAAUJ5A/3WwA8AQAAAA==.Ratbasterd:BAAANQADCgQIBAAAAA==.Rats:BAAANQAECgIIAgAAAA==.Rayy:BAAANQAECgMIBgAAAA==.',
Re='Reinerbraun:BAAANQADCgcICAAAAA==.Renade:BAAANQAECgMIBAAAAA==.Rexx:BAAANQADCgMIAwAAAA==.',
Ri='Rigidsxz:BAAANQADCgUIBQAAAA==.Riskymonk:BAAANQADCgIIAgAAAA==.Riskyshammy:BAAANQAECgYIEgAAAA==.Riteaid:BAAANQAECgEIAgAAAA==.',
Ro='Robe:BAAANQAECgEIAQABNQAECgIIAwAGAAAAAA==.Rolexor:BAAANQADCgEIAQAAAA==.Ronok:BAAANQAECgUIBQAAAA==.Rorthach:BAAANQADCggIDgAAAA==.Roru:BAABNQAECoEfAAMUAAgJfRHKLwAZAgAUAAgJfRHKLwAZAgATAAQJ6wIuPgCQAAAAAA==.Roseire:BAAANQAECgIIAwAAAA==.Rosethebrute:BAAANQAECgYIEQAAAA==.Rosetheholy:BAAANQAECgQICQABNQAECgYIEQAGAAAAAA==.Rougeloving:BAABNQAECoEYAAIRAAkJSBndBwDHAgARAAkJSBndBwDHAgAAAA==.',
Ru='Ruler:BAAANQAECgEIAQAAAA==.Ruli:BAABNQAECoEYAAICAAgJYBzEFQDKAgACAAgJYBzEFQDKAgAAAA==.Rusticdiino:BAAANQADCgEIAQABNQAECgYIDQAGAAAAAA==.',
Ry='Ryshin:BAABNQAECoEaAAMHAAgJTBW7EAAxAgAHAAgJTBW7EAAxAgARAAUJ7wddIwAzAQAAAA==.',
['Rø']='Rørs:BAAANQADCgcIBwAAAA==.',
Sa='Sabeck:BAAANQAECgUICAABNQAECgYIBwAGAAAAAA==.Safi:BAAANQADCggICAAAAA==.Saltine:BAEANQAECgEIAQABNQAECgQIBwAGAAAAAA==.Sanctano:BAAANQAECgMIAwAAAA==.Saneras:BAAANQADCgQIBQAAAA==.Sarshia:BAAANQADCgYICAAAAA==.Sayn:BAAANQAECgcIDwAAAA==.',
Sc='Schultzies:BAAANQAECgQIBAAAAA==.',
Sd='Sdog:BAAANQADCgUIBwAAAA==.',
Se='Seanboyymage:BAABNQAECoEYAAIVAAgJhhd0UgBUAgAVAAgJhhd0UgBUAgAAAA==.Seina:BAAANQAECgQIBQAAAA==.Sensei:BAAANQAECgEIAQAAAA==.Sephirofl:BAAANQAECgIIAwAAAA==.Seulrene:BAAANQAECgUICwAAAA==.',
Sh='Shamlaw:BAAANQAECgQIBQAAAA==.Shammydavis:BAAANQAECgIIAgAAAA==.Shampayn:BAAANQADCgUIBwAAAA==.Shankiee:BAAANQABCgIIAgAAAA==.Shanti:BAAANQAECgQIBAAAAA==.Shhuffle:BAAANQAECgYICwAAAA==.Shiv:BAAANQADCgQIBAAAAA==.Shupasins:BAAANQAECgYIDgAAAA==.Shyamablue:BAAANQAECgEIAQAAAA==.',
Si='Silvercas:BAAANQAECgUICAAAAA==.Simpleyfire:BAAANQAECgYIDQAAAA==.',
Sk='Skullet:BAAANQAECgQIBgAAAA==.',
Sl='Slimshadyy:BAAANQADCgQIBQAAAA==.Slurpee:BAAANQAECgQICAAAAA==.',
Sm='Smooth:BAAANQAECgcIDwAAAA==.',
Sn='Snaphance:BAAANQAECgEIAQAAAA==.Sneekypete:BAAANQADCgYIBgAAAA==.Sniffer:BAAANQAECgYICgAAAA==.Snipercat:BAAANQAECgQICAAAAA==.Snuffles:BAAANQAECgMIBAAAAA==.Snøkie:BAAANQADCgcIDQAAAA==.',
So='Solitude:BAABNQAECoEcAAIbAAkJeiLKAAB4AwAbAAkJeiLKAAB4AwAAAA==.Sorscha:BAAANQADCggIDwAAAA==.',
Sp='Spammy:BAABNQAECoEYAAIEAAkJwhQJGwCIAgAEAAkJwhQJGwCIAgAAAA==.Sparlyy:BAABNQAECoEgAAMcAAkJUCVSAQDBAwAcAAkJUCVSAQDBAwALAAEJXQt2igA1AAAAAA==.Spectrality:BAAANQADCggIDQABNQAECgIIAwAGAAAAAA==.',
Ss='Sswordy:BAABNQAECoEhAAICAAkJkR5NDgAHAwACAAkJkR5NDgAHAwAAAA==.Sswordyvani:BAAANQADCgYIDAABNQAECgkJIQACAJEeAA==.',
St='Stimulus:BAAANQAECgUIBQAAAA==.Stinkynuuts:BAAANQADCggIFAAAAA==.Stormcloak:BAAANQADCggIDgAAAA==.Stormfang:BAAANQAECgEIAQAAAA==.',
Su='Sunkist:BAAANQAECgQIBQAAAA==.Sunwing:BAAANQADCgUIBQAAAA==.Surlym:BAAANQAECgUICgAAAA==.',
Sw='Switchglaive:BAAANQAECgYIDQAAAA==.',
Sy='Sylphie:BAAANQADCggIGgAAAA==.Symphemon:BAABNQAECoEfAAMQAAkJkw5IFgBCAgAQAAkJkw5IFgBCAgAPAAMJ0wb0QQCGAAAAAA==.Symphoid:BAAANQAECgMIAwAAAA==.Syseloris:BAAANQAECgYICgAAAA==.Sythion:BAAANQAECgcIEwAAAA==.',
['Së']='Sëphy:BAAANQADCgYICAAAAA==.',
Ta='Taliiha:BAAANQAECgEIAQAAAA==.Tanao:BAAANQADCggIHgAAAA==.',
Te='Tengenuzui:BAAANQADCgEIAQAAAA==.Tenshi:BAAANQAECgcIDAAAAA==.Terravesh:BAAANQADCgIIAgAAAA==.',
Th='Thopegor:BAAANQADCgQIBAAAAA==.Thundergunt:BAAANQAECgEIAQABNQAECgYIDgAGAAAAAA==.',
Ti='Tianjin:BAAANQADCggIGgAAAA==.Tintaglia:BAAANQAECgIIAwAAAA==.Tiqtaqto:BAAANQADCgIIAgAAAA==.Tivali:BAAANQADCgIIAgAAAA==.',
To='Toaster:BAAANQAECgEIAgAAAA==.Tober:BAAANQADCgcIFQAAAA==.Toni:BAAANQADCgcIDwAAAA==.Toodles:BAAANQADCgUIBQAAAA==.',
Tr='Trust:BAAANQAECgMIBQAAAA==.',
Tu='Tunawhale:BAAANQADCgcIEAAAAA==.',
Ty='Tyloriavis:BAAANQADCggIEAAAAA==.',
Ul='Ulfberht:BAAANQADCgIIAgAAAA==.Ulfin:BAAANQADCgUIBQABNQAECgMIAwAGAAAAAA==.Ultramind:BAAANQADCgUIBQAAAA==.',
Um='Umbras:BAAANQADCgIIAgAAAA==.',
Un='Uncletouchie:BAAANQADCgIIAgAAAA==.',
Va='Vaeliir:BAAANQADCgUICQAAAA==.Valára:BAAANQABCgQIBAAAAA==.',
Ve='Vesani:BAAANQADCgQIBAAAAA==.',
Vi='Vinfuriating:BAAANQAECgEIAQAAAA==.Violentjudge:BAAANQAECgMIBQAAAA==.Violla:BAAANQAECgEIAQAAAA==.Virgocelest:BAAANQAECgIIAwAAAA==.Viridion:BAAANQAECgQIBgAAAA==.Vivax:BAAANQAECgUICAAAAA==.',
Vo='Vorlos:BAAANQAECgUIBQAAAA==.',
Vr='Vreeg:BAAANQAECgIIAwAAAA==.',
Wh='Whiteflag:BAABNQAECoEeAAIOAAkJ9iXdAgDLAwAOAAkJ9iXdAgDLAwAAAA==.Whoopington:BAAANQADCgYIEQAAAA==.Whyamialive:BAABNQAECoEgAAIBAAkJtCY9AAABBAABAAkJtCY9AAABBAAAAA==.',
Wi='Willowes:BAEANQADCggICAABNQAECgkJHwALAOocAA==.Willowest:BAEANQADCgYIBgABNQAECgkJHwALAOocAA==.Willowing:BAEANQAECgcICgABNQAECgkJHwALAOocAA==.Willowish:BAEBNQAECoEfAAILAAkJ6hxKEQC+AgALAAkJ6hxKEQC+AgAAAA==.Winterz:BAAANQAECgQIEQAAAA==.Wiskii:BAAANQAECgIIAwAAAA==.',
Wo='Worio:BAAANQADCgYIDwAAAA==.',
Wy='Wytenha:BAAANQAECgEIAQABNQAECgkJHwASAAEYAA==.Wytnarthom:BAAANQADCggICAABNQAECgkJHwASAAEYAA==.Wytohne:BAABNQAECoEfAAISAAkJARjgCwCMAgASAAkJARjgCwCMAgAAAA==.',
Xa='Xaree:BAAANQAECgIIAwAAAA==.Xariá:BAAANQADCgQIBAABNQADCggIGwAGAAAAAA==.',
Xc='Xcat:BAABNQAECoEcAAIOAAkJnxNeMwA4AgAOAAkJnxNeMwA4AgAAAA==.',
Xy='Xymer:BAAANQADCgcIDgAAAA==.',
Yi='Yim:BAAANQAECggIDgAAAA==.Yismypetdead:BAAANQADCggIDQABNQAECgIIAwAGAAAAAA==.',
Yo='Yorshka:BAAANQAECgcIEQAAAA==.',
['Yú']='Yúno:BAAANQAECgYIDQAAAA==.',
Za='Zaffhavoc:BAAANQADCgYIBgABNQADCggIDAAGAAAAAA==.Zaffylizen:BAAANQADCgYIBgABNQADCggIDAAGAAAAAA==.Zako:BAAANQADCgMIAwABNQAECgIIAwAGAAAAAA==.Zalliea:BAAANQADCggIGwAAAA==.',
Ze='Zeff:BAAANQADCgcIEQAAAA==.',
Zo='Zompt:BAAANQAECgEIAQAAAA==.Zorndk:BAAANQAECgQIBQAAAA==.',
Zy='Zymar:BAAANQADCgMIAwABNQADCgcIDgAGAAAAAA==.',
['Ðë']='Ðëxx:BAAANQADCgQIBAAAAA==.',
['Ön']='Öni:BAABNQAECoEbAAIXAAkJTiPoAACkAwAXAAkJTiPoAACkAwAAAA==.',
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
