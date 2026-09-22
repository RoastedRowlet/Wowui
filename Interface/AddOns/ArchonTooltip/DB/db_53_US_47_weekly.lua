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

local lookup = {'Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Warrior-Arms','Shaman-Restoration','Monk-Mistweaver','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','Hunter-Marksmanship','Warrior-Protection','Mage-Frost','Monk-Brewmaster','Paladin-Holy','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Priest-Holy','Shaman-Elemental','Warrior-Fury','DemonHunter-Havoc','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Priest-Shadow','Hunter-BeastMastery','Monk-Windwalker','Priest-Discipline','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='BurningLegion',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aalfie:BAAANQAECgEIAQABNQAECggJGgABABQNAA==.',
Ad='Adaric:BAAANQADCgUIBQAAAA==.Aderren:BAAANQAECgYIEgAAAA==.',
Ae='Aeir:BAAANQAECgQJCAAAAA==.Aether:BAAANQADCgcIBwAAAA==.Aevella:BAACNQAFFIENAAMCAAYKfRahAQDEAQADAAUKfBb4AgDLAQACAAUKGBGhAQDEAQA1AAQKgSAAAwMACQrNIwEEAEIDAAMACApDJAEEAEIDAAIABwoXIk0OAKgCAAAA.',
Ag='Agarn:BAAANQAECggIDAABNQAECgUJBQAEAAAAAA==.Aghanaar:BAAANQAECgQIBwAAAA==.Agidan:BAABNQAECoEYAAIFAAgKTAv7WADAAQAFAAgKTAv7WADAAQAAAA==.Aguthus:BAAANQADCgYICgAAAA==.',
Ai='Airryon:BAAANQADCgMIAwAAAA==.Aitch:BAAANQADCgcJBwAAAA==.',
Ak='Akaibara:BAAANQADCggIFAAAAA==.',
Al='Alcazor:BAAANQADCgUIBQAAAA==.Alizar:BAAANQAECgcIEQAAAA==.Alleriá:BAAANQAECgYJEwAAAA==.Almaholzhert:BAAANQAECgEJAQAAAA==.Alor:BAAANQAECgYIDgAAAA==.Alundareth:BAAANQAECgcIDgAAAA==.Alynnis:BAAANQADCgUIBQAAAA==.Alysanne:BAAANQADCgIIAgAAAA==.',
Am='Amelie:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.',
An='Anaphora:BAAANQABCgQIBAAAAA==.Angelmoon:BAAANQADCggIDgAAAA==.Angryart:BAAANQADCggIEgABNQAECgYJEAAEAAAAAA==.Anguissette:BAAANQAECgQIBAAAAA==.Anklehumper:BAAANQABCgEIAQABNQAECgQICAAEAAAAAA==.Anniellusion:BAAANQAECgYJDgAAAA==.Anthreax:BAABNQAECoEUAAIGAAcKnCNjEwDIAgAGAAcKnCNjEwDIAgAAAA==.',
Ap='Applepie:BAAANQAECgcIDgAAAA==.Apretzel:BAAANQAECgIIAgAAAA==.',
Ar='Aredstrasza:BAAANQABCgIJAgAAAA==.Ares:BAAANQADCgUIBQABNQABCgYIBgAEAAAAAA==.Armous:BAAANQAECgUICwAAAA==.Arms:BAACNQAFFIEHAAIHAAQKCRAaDAA0AQAHAAQKCRAaDAA0AQA1AAQKgR4AAgcACQqlHRItALYCAAcACQqlHRItALYCAAAA.Arrano:BAAANQAECgEIAQAAAA==.Arterios:BAAANQADCgQJBAAAAA==.',
As='Astrada:BAAANQAECgIJAgAAAA==.',
Ay='Ayangat:BAABNQAECoEYAAIIAAkKmRx6GgC4AgAIAAkKmRx6GgC4AgABNQAECgkJGQAJAEYfAA==.Aycekween:BAAANQAECgEIAQAAAA==.',
Az='Azgar:BAAANQAECgQIBAAAAA==.Azusa:BAABNQAECoEbAAIKAAgKQhPbeQAnAgAKAAgKQhPbeQAnAgAAAA==.Azzulaa:BAAANQAECgUJCQAAAA==.',
Ba='Baconarrow:BAAANQADCggICAAAAA==.Baggedmilk:BAAANQADCggIGAAAAA==.',
Be='Belgarrion:BAAANQADCgYIAQAAAA==.Belladonna:BAABNQAECoEgAAMFAAkK5yC6HwCsAgAFAAgKuiC6HwCsAgALAAYKsRvWEQDNAQABNQAFFAcIFAAFAK8UAA==.Bezirk:BAAANQAFFAEJAQAAAA==.',
Bh='Bhaal:BAABNQAECoEcAAIMAAgKgxwqGwCOAgAMAAgKgxwqGwCOAgAAAA==.',
Bi='Bidoof:BAAANQAECgIIAgAAAA==.Bigboyfriend:BAAANQADCggICAAAAA==.Bighunters:BAAANQAECgEIAQAAAA==.Bigitaly:BAAANQAECgQJBwAAAA==.Bitemarkstwo:BAAANQADCgQJBgAAAA==.',
Bj='Bjardle:BAAANQAECgMIAwAAAA==.',
Bl='Blast:BAABNQAECoEYAAINAAgKpANILABbAQANAAgKpANILABbAQAAAA==.Bleedlife:BAAANQAECgUIEAABNQAECgcJEgAEAAAAAA==.Blindguard:BAABNQAECoEjAAIOAAgKORRqCgAOAgAOAAgKORRqCgAOAgAAAA==.Blinksoncd:BAABNQAECoEZAAIPAAkKKx+5AQAWAwAPAAkKKx+5AQAWAwAAAA==.Bloodrainer:BAAANQAECgcIEwAAAA==.Blutregen:BAAANQADCgMIBQABNQAECgUJDAAEAAAAAA==.Blutzappel:BAAANQADCgIIAgABNQAECgUJDAAEAAAAAA==.',
Bo='Bobfriskit:BAAANQADCgYIBgABNQAECggJHAAQABoaAA==.Bonehoof:BAAANQADCgQIBAAAAA==.Bookko:BAAANQAECgQJBAABNQAECgkJGgARACQgAA==.Boot:BAAANQAECgIIAgABNQAECggIFwASAHgHAA==.Bootkin:BAABNQAECoEXAAISAAgKeAcYPACSAQASAAgKeAcYPACSAQAAAA==.Borgorn:BAAANQAECgcIEgAAAA==.Bownes:BAAANQAECgUICQAAAA==.',
Br='Brambless:BAAANQADCgUIBQAAAA==.Breakfast:BAABNQAECoEcAAICAAgKiyNVBABUAwACAAgKiyNVBABUAwAAAA==.Brewbott:BAAANQAFFAIJAgAAAA==.Brewhal:BAAANQADCgcJBwAAAA==.Brickp:BAAANQAECgcIEgAAAA==.Brimscythe:BAAANQADCgYIBgAAAA==.',
Bu='Bulinlok:BAAANQADCgMIAwAAAA==.Buluc:BAAANQAECgQIDAAAAA==.Buroode:BAAANQAECgUJDAAAAA==.Busselton:BAAANQAECggIEAAAAA==.',
Bv='Bvngly:BAABNQAECoEmAAITAAkKsSG6BAB0AwATAAkKsSG6BAB0AwAAAA==.',
['Bè']='Bèat:BAAANQAECgcJCwAAAA==.',
['Bø']='Børedom:BAAANQABCgIJAgAAAA==.',
Ca='Cakeshifter:BAAANQAECgcICAAAAA==.Callister:BAABNQAECoEgAAIHAAcKTQSingAmAQAHAAcKTQSingAmAQAAAA==.Campanda:BAAANQAECgEIAQAAAA==.Carble:BAAANQADCggICAAAAA==.Cashgrabber:BAAANQADCgQIBgAAAA==.',
Ce='Cellwynn:BAAANQADCgQIBAAAAA==.',
Ch='Champthyr:BAABNQAECoElAAMUAAkKNBQKBQAqAgAUAAgKFRQKBQAqAgAVAAkKawzoDgAXAgAAAA==.Chaosblt:BAAANQAECggJDgAAAA==.Charmander:BAAANQADCgMIAwAAAA==.Cherwòòd:BAAANQABCgIIAgAAAA==.',
Cl='Claudia:BAAANQADCgIIAgAAAA==.Clobberela:BAAANQADCggIEAAAAA==.Clouds:BAAANQAECgUICAAAAA==.',
Co='Coachkreeton:BAABNQAECoEjAAMHAAkKuB0fLwCuAgAHAAkK/hofLwCuAgAOAAYKzxvqCwDoAQAAAA==.Cocopie:BAAANQADCgMIBAAAAA==.Cologa:BAAANQAECgUJBQAAAA==.Confess:BAABNQAECoEYAAIWAAgKPRKHPgDuAQAWAAgKPRKHPgDuAQAAAA==.Coola:BAAANQAECgUJCQAAAA==.Coollá:BAAANQADCggIEgABNQAECgUJCQAEAAAAAA==.Coot:BAAANQAECgEIAgAAAA==.Copmage:BAAANQAFFAEJAQAAAA==.Cosines:BAABNQAECoEaAAMXAAgKJhtxLQBYAgAXAAgKJhtxLQBYAgAIAAcKqRlwNQAeAgAAAA==.Cowculated:BAABNQAECoEYAAMYAAgKZRsPBgApAgAYAAYK+h8PBgApAgAHAAYKiw72iABsAQAAAA==.Cowsrule:BAAANQAECgQJCwAAAA==.',
Cr='Crestfallen:BAAANQADCgUICAAAAA==.',
Da='Daarfsad:BAAANQADCgYIBgAAAA==.Daeio:BAAANQAECgUICAAAAA==.Darkaunnas:BAAANQAECgYJDQAAAA==.Darth:BAAANQAECgcJEwAAAA==.Darwinism:BAAANQADCggJCgAAAA==.Daydayy:BAAANQAECggICAAAAA==.',
De='Deathnought:BAAANQADCgYJBgAAAA==.Deified:BAAANQADCgIIAgAAAA==.Deldor:BAAANQAECgEJAQAAAA==.Deli:BAAANQADCggIDQAAAA==.Demonetizer:BAABNQAECoEoAAIZAAkKaiUOAQDiAwAZAAkKaiUOAQDiAwAAAA==.Demonicart:BAAANQADCgUIBQABNQAECgYJEAAEAAAAAA==.Demyxx:BAAANQAECgQJCgAAAA==.Denniecrane:BAEBNQAECoEZAAIIAAkK1BgkJwBqAgAIAAkK1BgkJwBqAgAAAA==.',
Dh='Dhjochann:BAAANQAECgIIAgAAAA==.',
Di='Dirtywork:BAABNQAECoEVAAIHAAcKCxy7UAAoAgAHAAcKCxy7UAAoAgAAAA==.',
Dm='Dmnikki:BAAANQADCgUJCQAAAA==.',
Do='Dockside:BAAANQADCgMJAwAAAA==.Domiknight:BAAANQADCggIEAAAAA==.Dominic:BAAANQADCgQIBwAAAA==.Donttrustme:BAAANQAECgUJCwAAAA==.',
Dr='Drae:BAAANQAECgQICQAAAA==.Dragunass:BAAANQAECgIIAgAAAA==.Drama:BAAANQABCgMIBAAAAA==.Drayu:BAAANQAECgEIAQAAAA==.Drexl:BAAANQAECgYJBgABNQAFFAUJDQAOACIPAA==.',
Ei='Eilesa:BAAANQADCgcIDQAAAA==.',
El='Eldarin:BAAANQAECgUJDQAAAA==.Eliardis:BAAANQADCgcIFAAAAA==.Elizabetta:BAAANQAECgMJAwAAAA==.Ellwine:BAAANQADCgYIBgAAAA==.Elystravia:BAAANQADCgcIBwABNQAECgUJCwAEAAAAAA==.',
Em='Emmahotson:BAAANQAECgcJAQAAAA==.Emrys:BAAANQAECggJEgAAAA==.',
En='Enigmazz:BAAANQAECgIJAwAAAA==.',
Ep='Epictitus:BAAANQAECgIIAgAAAA==.',
Es='Escaflowne:BAACNQAFFIEIAAMaAAQKoxcsCAAGAQAaAAMKHRssCAAGAQAbAAIKbgs+BgB/AAA1AAQKgSoAAhoACQoqJokBAO4DABoACQoqJokBAO4DAAAA.Escanór:BAAANQADCgQJBAAAAA==.',
Et='Ethaee:BAAANQADCgYIDAAAAA==.',
Eu='Euli:BAAANQAECgUICAABNQAFFAYJDgAGAPATAA==.Eurydices:BAAANQADCgYIBgAAAA==.',
Ev='Evangelión:BAAANQADCgUIDwAAAA==.',
Ex='Exit:BAAANQAECgUJDQAAAA==.Extermine:BAAANQAECgEJAQAAAA==.',
Ey='Eyks:BAAANQAECgEIAQAAAA==.',
Fa='Faelithndrel:BAAANQAECgUIDwAAAA==.Farmette:BAAANQAECgUJCgAAAA==.Fatherfloop:BAAANQAECgEIAQAAAA==.',
Fe='Felbeard:BAACNQAFFIEUAAMFAAcKrxQ/AQAjAgAFAAYKnBY/AQAjAgALAAIKeArxCQCiAAA1AAQKgSYAAwUACQoBJuIFAG4DAAUACAorJuIFAG4DAAsABwpUFR4NAAYCAAAA.Feleâ:BAAANQAECgQICAAAAA==.Ferreday:BAAANQAECgUICwAAAA==.Fewix:BAAANQABCgIIAgAAAA==.',
Fi='Fingoflin:BAAANQADCggICAAAAA==.Firechicken:BAAANQAECgIJAgAAAA==.Firemystic:BAAANQADCggJDQAAAA==.',
Fl='Flamereaper:BAAANQADCgYIBgABNQAECgcIGQAKAGoXAA==.Fleakertwo:BAABNQAECoEqAAICAAkK4xOeDwCWAgACAAkK4xOeDwCWAgAAAA==.Floopzii:BAAANQAECgYJEwAAAA==.Flói:BAAANQADCggIGgAAAA==.',
Fr='Friedrib:BAACNQAFFIEFAAISAAMKZAhGDQDfAAASAAMKZAhGDQDfAAA1AAQKgSkAAxIACQpeH3kMADoDABIACQpeH3kMADoDABwAAwreEqg0AMoAAAAA.Frostlas:BAAANQABCgQJBgAAAA==.',
Fu='Fulldipey:BAAANQAECgcJEwAAAA==.Furrythot:BAACNQAFFIEFAAIGAAIKZSDDDQC6AAAGAAIKZSDDDQC6AAA1AAQKgSoAAgYACQpVJLUCALMDAAYACQpVJLUCALMDAAAA.Fuzeewuzee:BAEANQAECgUIBQABNQAECgkJGQAIANQYAA==.',
Ga='Galise:BAAANQAECgQJBgAAAA==.Galynnia:BAAANQADCgYIBgAAAA==.Gangstafrost:BAAANQADCgMIBQAAAA==.',
Gd='Gduff:BAAANQAECgEIAQAAAA==.',
Ge='Genaveive:BAABNQAECoEgAAINAAkKLxOvGQAwAgANAAkKLxOvGQAwAgAAAA==.',
Gg='Ggodetan:BAAANQADCgYIBgAAAA==.',
Gi='Gigglespit:BAAANQAECgQICAAAAA==.Gildeath:BAAANQAFFAIJAgAAAA==.Gimlie:BAAANQAECgYIDwABNQAECgYIEQAEAAAAAA==.Gimmix:BAAANQAECgYIEQAAAA==.',
Go='Gobbylynn:BAABNQAECoElAAMdAAkKriM+BAB9AwAdAAkKriM+BAB9AwAWAAEK5xj1ogBMAAABNQAFFAYIDQACAH0WAA==.Gooptoob:BAAANQAECgUICQAAAA==.Goosetits:BAAANQAECggICAAAAA==.',
Gr='Grider:BAAANQADCgYIBgAAAA==.Grogosh:BAAANQADCgYIBgAAAA==.',
Gu='Guaplord:BAAANQADCgMIAwAAAA==.Gulog:BAAANQADCgMIAwAAAA==.Guzzlord:BAAANQADCgYIBgAAAA==.',
Ha='Hagran:BAAANQADCgQJBgAAAA==.Haint:BAAANQAECgcJEgAAAA==.Halzak:BAAANQAECgEJAgAAAA==.Harambeisbae:BAAANQAECgcIDgAAAA==.Harmön:BAAANQAECgMIBQAAAA==.Hawdazz:BAAANQADCgQIBAABNQADCggIBgAEAAAAAA==.',
He='Healah:BAAANQADCgcIBwAAAA==.Hegotthedrip:BAACNQAFFIEIAAMLAAQKxguqCACrAAALAAIK2Q6qCACrAAAFAAIKswioGwCJAAA1AAQKgRkABAsACQpGHqgJAEECAAsABwqvHagJAEECAAUABAoZHiqGADIBAAEAAQpfB54dAEMAAAAA.Helios:BAABNQAECoEbAAMaAAkKfyFzGAAZAwAaAAkK2SBzGAAZAwAbAAUKzxv/GACbAQABNQABCgYIBgAEAAAAAA==.Hellaquin:BAACNQAFFIEFAAIdAAIKtSB8CADQAAAdAAIKtSB8CADQAAA1AAQKgSgAAh0ACQoJJVMBAMkDAB0ACQoJJVMBAMkDAAAA.Hellomotojr:BAAANQAECgYIEgAAAA==.',
Hi='Hijackx:BAAANQAECgcIEgAAAQ==.Hinotama:BAAANQADCggICgAAAA==.',
Ho='Holdne:BAAANQAECgcIEwAAAA==.Holycoward:BAAANQAECgYJBgAAAA==.Holynova:BAAANQAECgUJDQAAAA==.Holypoker:BAAANQAECgUIBgAAAA==.Holysuave:BAAANQADCggICgAAAA==.Horu:BAAANQAECgQIBwAAAA==.Horux:BAAANQADCggJFQAAAA==.',
Hr='Hrothgar:BAAANQAECggICAAAAA==.',
Hu='Humanpaladin:BAEANQAECgEIAQABNQAFFAUICwAHAFIOAA==.',
Hy='Hyhu:BAABNQAECoEbAAINAAgKBhcOGwAfAgANAAgKBhcOGwAfAgAAAA==.Hymlok:BAAANQAECgYJEwAAAA==.Hymnsorrow:BAAANQADCgYIBgABNQAECgcIEgAEAAAAAA==.Hyperion:BAABNQAECoEWAAIaAAkKUghWbwCvAQAaAAkKUghWbwCvAQAAAA==.Hyuga:BAAANQAECgUJBwAAAA==.',
Ic='Iccarium:BAAANQAFFAEIAQAAAA==.Icexjh:BAAANQAECgMJCQAAAA==.Icritmypañts:BAAANQAECgcIBwABNQAECggJFgAIAEMgAA==.',
Ig='Ignatowski:BAAANQAECgIIAgAAAA==.Igorongon:BAABNQAECoEYAAIMAAcKBw9eOQC5AQAMAAcKBw9eOQC5AQAAAA==.',
Ii='Iindulgelag:BAAANQAECgQIBAAAAA==.',
Ik='Ikhawe:BAAANQADCgYICAAAAA==.',
In='Inebrious:BAAANQAECgQJBgAAAA==.',
Io='Ionna:BAAANQADCggICgABNQAECgUJDQAEAAAAAA==.',
Ir='Ironmann:BAAANQAECgUJEQAAAA==.',
It='Itsmäam:BAABNQAECoEWAAIIAAgKQyDaEgDvAgAIAAgKQyDaEgDvAgAAAA==.',
Iv='Ivandar:BAAANQABCgUIBQAAAA==.',
Iw='Iwixl:BAAANQADCgEIAQAAAA==.',
Ja='Jabadin:BAAANQAECgQJBAAAAA==.Jabamental:BAABNQAECoEkAAIIAAkKqCQyAwCeAwAIAAkKqCQyAwCeAwAAAA==.Jaded:BAAANQAECgIIAgAAAA==.Jadefonda:BAAANQAECgYJCQABNQAECgcJAQAEAAAAAA==.Jamx:BAAANQAECgcIEgABNQAECgkJJgAeABQhAA==.Jamy:BAABNQAECoEmAAMeAAkKFCFIIQC2AgAeAAgKpSNIIQC2AgANAAgKWBemGwAZAgAAAA==.Jandria:BAABNQAECoEYAAIWAAgKTB4eHACoAgAWAAgKTB4eHACoAgAAAA==.Janos:BAABNQAFFIEHAAIfAAQKxRYnBABLAQAfAAQKxRYnBABLAQAAAA==.Jashin:BAABNQAECoEcAAMeAAkKuyO8AgC9AwAeAAkKuyO8AgC9AwANAAEKpR/pUgBSAAAAAA==.Jawbreaker:BAAANQADCgQIBQAAAA==.Jaycifer:BAABNQAECoEfAAQFAAkKrB02KgB5AgAFAAkKchg2KgB5AgALAAUKHxyFGgB+AQABAAMK3iFVDgDnAAAAAA==.',
Je='Jerm:BAAANQAECgQJBQAAAA==.Jerzyp:BAAANQADCgEIAQAAAA==.Jessia:BAAANQAECgYIDwAAAA==.',
Jo='Joobi:BAAANQAECgQIDgAAAA==.Jorrethoi:BAAANQAECgUJCgAAAA==.',
Ju='Jurble:BAABNQAECoEbAAICAAgKDyAXCwDYAgACAAgKDyAXCwDYAgAAAA==.Juurou:BAAANQADCggJGQAAAA==.',
Jy='Jynn:BAAANQAECgQJBwAAAA==.',
['Jä']='Jäydedfäith:BAAANQAECgQJBAAAAA==.',
Ka='Kabbu:BAABNQAECoEZAAISAAkKACE5CwBHAwASAAkKACE5CwBHAwAAAA==.Kaila:BAAANQADCgEIAQAAAA==.Kaimed:BAABNQAECoEjAAIKAAkKjh3ALgACAwAKAAkKjh3ALgACAwAAAA==.Kaizer:BAEANQAFFAIIBAAAAA==.Kalrakin:BAAANQADCgMIAwABNQAECggKHAACAIsjAA==.Kamton:BAAANQADCgUIBQAAAA==.Kardrig:BAAANQADCggJIwAAAA==.Katwoman:BAABNQAECoEcAAIcAAgKNB2uDQCNAgAcAAgKNB2uDQCNAgAAAA==.Kaylana:BAAANQADCggIHAAAAA==.',
Kd='Kdzee:BAAANQADCggJEwAAAA==.',
Ke='Keicus:BAAANQABCgUIAwABNQAECgEJAQAEAAAAAA==.',
Kh='Khalezzi:BAAANQAFFAIJAwAAAA==.Khonos:BAAANQAECgcJEwAAAA==.Khrônic:BAAANQADCgYIBgAAAA==.',
Ki='Killercold:BAAANQAECgUICAAAAA==.Kimoora:BAAANQADCgQIBQAAAA==.Kirarawr:BAAANQABCgIIAgAAAA==.Kisstrosity:BAACNQAFFIELAAIeAAUKlRcKAgDSAQAeAAUKlRcKAgDSAQA1AAQKgSAAAh4ACQreIrURABUDAB4ACQreIrURABUDAAAA.',
Kl='Kloosterhuis:BAABNQAECoEcAAIaAAcK6x1zPgBZAgAaAAcK6x1zPgBZAgAAAA==.',
Ko='Kodoseeker:BAABNQAECoEcAAIcAAgKlBNaFgAKAgAcAAgKlBNaFgAKAgAAAA==.Kovos:BAAANQADCgcJCgAAAA==.Kovä:BAAANQADCgcIBwAAAA==.',
Kr='Krean:BAAANQAECgcIEgAAAA==.Krisali:BAAANQADCgIIAgAAAA==.',
Ku='Kunardh:BAAANQAECgQIBgABNQAECggIHAAQADUhAA==.Kunarr:BAABNQAECoEcAAIQAAgKNSEEBADvAgAQAAgKNSEEBADvAgAAAA==.',
Kw='Kwyte:BAAANQAECgUIBQAAAA==.',
Ky='Kylerichards:BAAANQAECgUIBwAAAA==.Kyohunt:BAABNQAECoEcAAMNAAkK0B0KEgCPAgANAAgKwhsKEgCPAgAeAAUKbyLLaQCwAQAAAA==.Kyoshock:BAAANQAECgYJDAABNQAECgkJHAANANAdAA==.',
La='Ladonda:BAAANQADCgYICAAAAA==.Lanius:BAAANQADCgYIBgAAAA==.Lanyx:BAAANQADCgYIDAAAAA==.Lareina:BAABNQAECoEqAAIXAAkK6hxKFAAMAwAXAAkK6hxKFAAMAwAAAA==.Larinara:BAAANQADCgEIAQAAAA==.Laziness:BAAANQAFFAEIAQABNQAECgIIAgAEAAAAAA==.',
Le='Lemonhope:BAAANQAECgIIBwAAAA==.',
Li='Lightnights:BAAANQADCgYIBgAAAA==.Lilmerlin:BAAANQADCggIDwAAAA==.Linchknight:BAAANQAECgUJCQAAAA==.Littlefudger:BAAANQABCgIIAgAAAA==.Livola:BAAANQAECgYJEAAAAA==.',
Lo='Locknik:BAAANQADCgYIDwAAAA==.Lokkahn:BAAANQADCggIGwAAAA==.',
Lu='Lunarsol:BAABNQAECoEbAAISAAgKNhcJJgA5AgASAAgKNhcJJgA5AgAAAA==.',
Ly='Lyanna:BAAANQAECgEIAQABNQAECgYIEQAEAAAAAA==.',
['Lä']='Lätêx:BAABNQAECoEjAAIaAAkKtiYvAQDzAwAaAAkKtiYvAQDzAwAAAA==.',
Ma='Magicmeatxxl:BAAANQAECgUIBwAAAA==.Magusgobrr:BAABNQAECoEaAAIKAAcK6SWtLwAAAwAKAAcK6SWtLwAAAwAAAA==.Mahawker:BAAANQAECgQIBwAAAA==.Mahfaty:BAAANQADCgYIBgAAAA==.Marcus:BAAANQAECgIJAgABNQAECggJDgAEAAAAAA==.Marideous:BAAANQADCggJFAAAAA==.Mark:BAAANQAECgEIAQABNQAECggJDgAEAAAAAA==.Marth:BAAANQAECgYJCwAAAA==.Mashem:BAABNQAECoEdAAMKAAkKQhuHRwC0AgAKAAkKRRqHRwC0AgAPAAEKxx1TJgBVAAAAAA==.Mathias:BAAANQAECgQIBgAAAA==.Mattpriest:BAACNQAFFIEHAAIWAAQKQR6WBwCNAQAWAAQKQR6WBwCNAQA1AAQKgSoABBYACQrcInkQAPoCABYACQrcInkQAPoCACAABApVGdINAPEAAB0AAgp8HbM9AKsAAAAA.Maxverclappn:BAAANQAECgQIBAAAAA==.Maxvertrappn:BAABNQAECoEiAAIeAAkKqSOCAgDBAwAeAAkKqSOCAgDBAwAAAA==.',
Mc='Mcsloppy:BAAANQAECgYJBgAAAA==.',
Me='Meshkuhrib:BAAANQADCgUIBQABNQAFFAMIBQASAGQIAA==.Methicillin:BAAANQADCggICgAAAA==.Methir:BAAANQADCgUICQAAAA==.',
Mi='Mightythor:BAAANQAECgUJCQAAAA==.Milkedmoose:BAAANQAECgYJDQAAAA==.Milkers:BAACNQAFFIEFAAIKAAMKnh1PFQAYAQAKAAMKnh1PFQAYAQA1AAQKgR8AAgoACQp7IU8jACsDAAoACQp7IU8jACsDAAAA.Minimoose:BAAANQAECgUJDQAAAA==.Misclick:BAAANQADCgQICAABNQAECggJGgABABQNAA==.',
Mo='Moistymonk:BAAANQADCgEIAQAAAA==.Moona:BAAANQAECgcJEgAAAA==.Moonberry:BAAANQAECggIEAAAAA==.Moonlock:BAAANQADCggIFAAAAA==.Morissa:BAAANQADCgQJBQAAAA==.Motomotoo:BAAANQAECgQIBQAAAA==.',
Mu='Muffinfeliz:BAAANQAECgQICQAAAA==.',
My='Myriad:BAAANQAECgYIBwABNQAFFAYJDAAVAFAbAA==.Mythundreran:BAAANQAECgQJCAAAAA==.',
['Mà']='Màyhém:BAAANQAECgUJBQAAAA==.',
Na='Namdari:BAAANQAECgUJDQAAAA==.Nanahammer:BAAANQADCgEIAQAAAA==.Nanasquirts:BAAANQADCgEIAQABNQAFFAEJAQAEAAAAAA==.Nazzan:BAAANQAECgEIAgABNQAECgkJIQAXAEsdAA==.',
Ni='Nightmàre:BAAANQAECgEIAQAAAA==.Nightshade:BAAANQAECgYICgABNQAFFAIJBQAdALUgAA==.Nightstride:BAAANQADCgQJAQAAAA==.Nikkô:BAAANQABCgQJCAAAAA==.Niksi:BAAANQADCgEIAQAAAA==.Nirra:BAAANQAECgUJCQAAAA==.Niso:BAAANQAECgEIAgAAAA==.',
No='Noatt:BAAANQADCgMIAwAAAA==.Nokona:BAAANQADCgEJAQAAAA==.Novapal:BAAANQAECgYJDwAAAA==.Novura:BAAANQADCgYIBgAAAA==.',
Nu='Numnumzz:BAAANQABCgQIBgAAAA==.',
Oc='Ochnauq:BAABNQAECoEbAAIGAAgKgg8kOQCxAQAGAAgKgg8kOQCxAQABNQAECgkJKAAhAF8VAA==.',
Om='Omarid:BAAANQADCgIIBAAAAA==.Omfgpie:BAABNQAECoEbAAIXAAgKoRyjIQCkAgAXAAgKoRyjIQCkAgAAAA==.',
Oo='Ooiskan:BAAANQADCgIIAgAAAA==.',
Or='Orcall:BAAANQAECgUIBgAAAA==.Orindier:BAAANQADCgYIBgAAAA==.',
Ov='Overcharged:BAAANQADCggIDAAAAA==.',
Ow='Owencaddell:BAAANQADCgYJFgAAAA==.',
Pa='Pada:BAAANQAECgcJEwAAAA==.Pakku:BAABNQAECoEqAAIfAAkK0CHjAwBzAwAfAAkK0CHjAwBzAwAAAA==.Paladaine:BAAANQADCggIEgAAAA==.Pallix:BAAANQAECgYIDwABNQAECgkJHwAFAKwdAA==.Palpacino:BAAANQAECgYJBgABNQAECggIEwAEAAAAAA==.Palytivecare:BAAANQAECgIIAgAAAA==.Papajaja:BAABNQAECoEWAAMFAAcKoxz1LQBoAgAFAAcKoxz1LQBoAgALAAMKyxOqMwDQAAAAAA==.Papal:BAAANQADCggJCQAAAA==.Paramôre:BAAANQAECggIAwAAAA==.',
Pe='Peace:BAAANQAECggJDgAAAA==.Peachpanther:BAAANQADCgYIBgAAAA==.Pegmianis:BAAANQAECgUICgAAAA==.Percivál:BAAANQAECggIBAABNQAECgkJIgAeAKkjAA==.',
Ph='Phatsword:BAAANQAECgIIAgAAAA==.Phigon:BAAANQAECgQIBwAAAA==.',
Pi='Pinknmoist:BAAANQAECgQIBAAAAA==.Pixelbaddy:BAAANQADCggIGAAAAA==.',
Pl='Plumbus:BAAANQADCggIDQAAAA==.',
Po='Polygrip:BAAANQAECgQICQAAAA==.Popechaz:BAAANQADCgYIDAAAAA==.',
Pr='Praxtintar:BAAANQAECgYJCwAAAA==.Providencia:BAAANQAECgUIBQAAAA==.Pru:BAAANQABCgIIAgAAAA==.Prutank:BAAANQABCgEIAQAAAA==.',
Ps='Psychonaut:BAAANQAECgUIBQABNQAECgUIBwAEAAAAAA==.',
Pu='Pure:BAABNQAECoEaAAIRAAkKnx8tCABaAwARAAkKnx8tCABaAwAAAA==.Purman:BAAANQADCgYICQAAAA==.',
Py='Pyrine:BAAANQAECgUJBwAAAA==.',
Qu='Quanchnauq:BAAANQAECgUJBQABNQAECgkJKAAhAF8VAA==.Quancho:BAABNQAECoEoAAIhAAkKXxV2CABAAgAhAAkKXxV2CABAAgAAAA==.',
Qw='Qwade:BAAANQAECgEJAQAAAA==.',
Ra='Ragran:BAAANQADCggJGgAAAA==.Rakaman:BAAANQAECgYJDwAAAA==.Ramza:BAACNQAFFIENAAIaAAYKkSGCAAByAgAaAAYKkSGCAAByAgA1AAQKgSQAAhoACQp1JrcBAOoDABoACQp1JrcBAOoDAAAA.Ranbou:BAABNQAECoElAAMKAAkKjh4fMQD7AgAKAAkKjh4fMQD7AgAiAAQKHxToAwAcAQAAAA==.Randor:BAAANQABCgQIBgAAAA==.Rashka:BAAANQADCgYIBgABNQAECgQIBAAEAAAAAA==.Ratatasquer:BAAANQAECgUJDQAAAA==.Rattleballs:BAAANQAECgQICAABNQAECgIIBwAEAAAAAA==.',
Re='Reegss:BAAANQADCgEIAQAAAA==.Regsia:BAAANQAECgEIAQAAAA==.Repens:BAAANQAECgUJDQAAAA==.Restosterone:BAAANQAECggIEwAAAA==.Ret:BAAANQAECgQIBwABNQAFFAQIBwAHAAkQAA==.Retbeanznrce:BAAANQAECgIIAgAAAA==.Retful:BAAANQADCgUIBQABNQAECgkJKAAZAGolAA==.Revo:BAAANQADCgYIBgABNQAECgkJGgARACQgAA==.',
Rh='Rhaid:BAAANQAECgYJEwAAAA==.Rhordrick:BAAANQAECgQICgAAAA==.',
Ri='Rizzgrizzly:BAAANQADCgIIAgAAAA==.Rizzurrect:BAAANQADCgIIAgAAAA==.',
Rn='Rng:BAAANQADCgIIAgAAAA==.',
Ro='Roquefort:BAAANQADCggIFAAAAA==.Roscoedshamn:BAAANQADCgYICQAAAA==.Roughstuff:BAAANQADCgEJAQAAAA==.Rowdi:BAAANQADCggIDAAAAA==.',
Ru='Rukarm:BAAANQADCgcIHAAAAA==.Runawaynow:BAACNQAFFIETAAIIAAYKVhbEAQAkAgAIAAYKVhbEAQAkAgA1AAQKgSAAAggACQp8IcQOABIDAAgACQp8IcQOABIDAAAA.Runelife:BAAANQAECgcJEgAAAA==.',
Sa='Saelaissamlt:BAAANQADCgQIBAAAAA==.Samdeathfoot:BAAANQAECgUICgAAAA==.Samsara:BAAANQAECgIJAgAAAA==.Saori:BAAANQADCggJCAABNQAECgkJHAAeALsjAA==.Sartok:BAAANQAECgIIAgAAAA==.',
Sc='Scottnails:BAAANQAFFAIJAgAAAA==.',
Se='Semanin:BAAANQADCgEJAQAAAA==.Seyuri:BAABNQAECoEcAAIeAAkKvxraGQDfAgAeAAkKvxraGQDfAgAAAA==.Seán:BAAANQAECgUJDQAAAA==.',
Sh='Shadowar:BAAANQAECgUJCQAAAA==.Shadowbell:BAAANQAECgYIEwAAAA==.Shadowgale:BAAANQAECgUJCQAAAA==.Shamanramen:BAAANQABCgQIBAAAAA==.Shantari:BAAANQAECgIIAgAAAA==.Shayrpd:BAAANQAECgUIBQAAAA==.Shoobìes:BAAANQABCgUICQAAAA==.Shøckybalboa:BAAANQAECgMIBAAAAA==.',
Si='Sinnmage:BAAANQABCgMIAwAAAA==.Sinnshifts:BAAANQAECgQIBwAAAA==.',
Sk='Skhorn:BAAANQAECgYJEwAAAA==.Skuûub:BAAANQAECgEJAQAAAA==.',
Sl='Slowone:BAAANQADCgUIBgABNQAECgUJCQAEAAAAAA==.Slãyer:BAAANQAECgUJCgAAAA==.',
Sm='Smallblessin:BAAANQADCgMJAwAAAA==.Smokedrib:BAAANQAECgQIBgABNQAFFAMIBQASAGQIAA==.',
Sn='Snorlock:BAAANQAECgQJBQAAAA==.',
So='Sometymz:BAABNQAECoEZAAIJAAgKJQ8SEwDFAQAJAAgKJQ8SEwDFAQAAAA==.',
Sp='Spareathot:BAABNQAECoEZAAMVAAkKYRECDQBCAgAVAAkKYRECDQBCAgAUAAIKzwSlFQBKAAAAAA==.Speedspanker:BAAANQAECgUIDQAAAA==.Spirulina:BAAANQADCgIIAgAAAA==.Splashsplash:BAAANQADCgQIBQAAAA==.',
St='Staar:BAAANQAECgIIAwAAAA==.Starboy:BAAANQADCgYIBgAAAA==.Starflames:BAAANQADCgQIBAAAAA==.Stellarèé:BAACNQAFFIEIAAMLAAQKRRmFBADAAAALAAIK8ByFBADAAAAFAAIKmxU7FQCoAAA1AAQKgSoAAwUACQoYJRAIAFQDAAUACArTJBAIAFQDAAsABgrcHkcMABMCAAAA.Stiliar:BAAANQAECgQIBwAAAA==.Strongdroid:BAAANQADCgcICgAAAA==.Strángè:BAAANQAECgYIEgAAAA==.Stríve:BAAANQAECgEIAgAAAA==.Stêlla:BAAANQADCgQIBAAAAA==.',
Su='Substrate:BAAANQAECgUJCQAAAA==.Sugarteets:BAAANQAECgQIBAABNQAECggJFgAIAEMgAA==.Sunderthighs:BAAANQABCgQJBAAAAA==.Suramo:BAABNQAECoEbAAIRAAgKJyBbEgD4AgARAAgKJyBbEgD4AgAAAA==.',
Sv='Svaval:BAABNQAECoEcAAIGAAkKlSOaBQB5AwAGAAkKlSOaBQB5AwAAAA==.',
Sy='Syles:BAAANQADCggIFAABNQAECgYJDgAEAAAAAA==.Syphon:BAABNQAECoEYAAIFAAgKVR+WGwDCAgAFAAgKVR+WGwDCAgAAAA==.',
Ta='Tamedurmom:BAAANQAECggIEwAAAA==.Tarekk:BAAANQAECgYJEgAAAA==.Tarewreck:BAAANQADCgcIDAAAAA==.Tariqpapi:BAABNQAECoEcAAQSAAgKxiBDFADhAgASAAgKxiBDFADhAgAcAAEKwCDPSABGAAAhAAEKwQjRNgAlAAAAAA==.Taxes:BAAANQAECgEJAQAAAA==.',
Te='Tehcountess:BAABNQAECoEbAAIGAAgKqRWHLgDvAQAGAAgKqRWHLgDvAQAAAA==.',
Th='Tharos:BAAANQAECgUIDAAAAA==.Thebeerwiz:BAAANQADCggIBgAAAA==.Thecarebear:BAAANQAECgQIBAAAAA==.Thelianne:BAAANQAECgUJCgAAAA==.Thelmina:BAAANQAECgQJBAAAAA==.Thepot:BAAANQAECgcIBwABNQAECgcIEgAEAAAAAQ==.Thermidor:BAAANQAECgUJCgAAAA==.Thorps:BAABNQAECoEXAAQRAAgKbg79RQDcAQARAAgKbg79RQDcAQAaAAYKWhY5dQCeAQAbAAEKZBa2TAAtAAAAAA==.Thragg:BAAANQADCgQIBAAAAA==.Thundarr:BAAANQABCgYIBgAAAA==.Thurstee:BAAANQAECgcJDwAAAA==.',
Ti='Tibian:BAABNQAECoEbAAIcAAgKsRX1EwAtAgAcAAgKsRX1EwAtAgAAAA==.Tigerpalm:BAAANQAECgYJDAAAAA==.Tilexer:BAAANQADCgMIAwAAAA==.Tinypreest:BAAANQADCgYIBgAAAA==.Tinyshocker:BAAANQADCgUIBQABNQAECgUJDQAEAAAAAA==.',
To='Totemlyfoxy:BAAANQAECgIJAwAAAA==.Touchedd:BAAANQADCgIIAgABNQADCgQIBAAEAAAAAA==.',
Tr='Trackker:BAAANQADCgQIBAAAAA==.Trapshotumad:BAAANQAECggJDAAAAA==.Treesdk:BAAANQAECgcJEQAAAA==.Trugs:BAAANQAECgcJDQAAAA==.',
Tu='Tulsmi:BAAANQAECgIIAQAAAA==.Tuntunvergun:BAABNQAECoEdAAISAAkK2hoEFQDYAgASAAkK2hoEFQDYAgAAAA==.',
Tw='Twelvetacos:BAABNQAECoEhAAIIAAkKaR+pDwALAwAIAAkKaR+pDwALAwAAAA==.',
Ty='Tyoka:BAAANQAECgUIBQAAAA==.Tyralde:BAAANQAECgcIEgAAAA==.',
Ud='Udenlo:BAAANQAECgQJBwAAAA==.',
Um='Umbraheart:BAAANQADCgYIEAAAAA==.',
Un='Unclepumper:BAAANQAECgIJAgAAAA==.Unsub:BAAANQADCgEIAQABNQAFFAMIBQAKAJ4dAA==.',
Us='Usui:BAAANQADCgUIAQAAAA==.',
Va='Vaalkad:BAAANQADCggICAAAAA==.Vaellian:BAAANQADCgUJCgAAAA==.Valei:BAAANQAECgcJDgAAAA==.Valvadime:BAAANQAECgMJBgAAAA==.Vanstian:BAAANQAECgUJBgABNQABCgIJAgAEAAAAAA==.Vantoes:BAAANQAECgcIEwAAAA==.',
Ve='Vecidus:BAAANQAECgIIAgAAAA==.Velassi:BAABNQAECoEaAAIBAAgKFA35BQDcAQABAAgKFA35BQDcAQAAAA==.Veldora:BAAANQAECgEIAQAAAA==.Velouriuum:BAAANQADCgYJDwAAAA==.Vetrandus:BAAANQADCgYIBgAAAA==.',
Vh='Vhioth:BAAANQADCgQIBgAAAA==.',
Vi='Vielli:BAAANQAECgUJDQAAAA==.Vintari:BAAANQAECgEIAQAAAA==.Vivvyquinn:BAAANQADCgMIAwAAAA==.',
Vo='Volorren:BAAANQAECgUICgAAAA==.Volzu:BAABNQAECoEZAAIXAAgKAB9FHQDDAgAXAAgKAB9FHQDDAgAAAA==.',
Wa='Walon:BAAANQADCgMIAwAAAA==.Warwickdavis:BAAANQADCgYIEgABNQADCggIHAAEAAAAAA==.Wazerk:BAAANQADCgcIBwAAAA==.',
We='Weirdchampx:BAAANQAECgEIAQABNQAECgcIEwAEAAAAAA==.',
Wh='Whely:BAEBNQAECoEpAAIOAAkKFCZWAADkAwAOAAkKFCZWAADkAwAAAA==.Whitegoodman:BAAANQADCggICAABNQAECggIHAAKADgfAA==.Whitegrlswag:BAAANQAECgIIAgAAAA==.',
Wi='Wilcoxx:BAABNQAECoEoAAMFAAkKdB+/GwDCAgAFAAgKyx6/GwDCAgALAAcKeBcxDQAFAgAAAA==.Wilcozz:BAAANQAECgIIAwABNQAECgkJKAAFAHQfAA==.Wildtree:BAAANQABCgYIBAAAAA==.Wipeout:BAAANQAECgEJAQAAAA==.Wipetime:BAAANQADCgUIBQABNQAECgEJAQAEAAAAAA==.Wirecutter:BAAANQAECgcICAAAAA==.Wixjones:BAAANQADCgUIBQABNQAECgkJJgAeABQhAA==.Wizurd:BAABNQAECoEcAAIKAAgKdgtSkADuAQAKAAgKdgtSkADuAQAAAA==.',
Wo='Wolfcult:BAABNQAECoEcAAIQAAgKGhpSBwBjAgAQAAgKGhpSBwBjAgAAAA==.Wompstomper:BAAANQADCgEJAQAAAA==.Worcklock:BAABNQAECoEWAAMFAAkKjR+aFADuAgAFAAgKtB+aFADuAgALAAEKWB5HVgBXAAABNQAFFAcIFAAFAK8UAA==.',
Wr='Wrapwrap:BAAANQAECgYIEwAAAA==.Wratheon:BAAANQADCgEIAQAAAA==.',
['Wì']='Wìxÿ:BAAANQADCgcIBwAAAA==.',
['Wî']='Wîxx:BAABNQAECoEbAAIcAAkKmR2cCADoAgAcAAkKmR2cCADoAgAAAA==.Wîxÿ:BAAANQAECgUIBgAAAA==.',
Xe='Xestsalb:BAEANQAECggICAAAAA==.',
Ya='Yayaoshi:BAAANQADCggICAAAAA==.',
Yo='Yourlock:BAAANQAECggJDgAAAA==.',
Yr='Yrel:BAAANQAECgIIAgAAAA==.',
Yu='Yuseolha:BAAANQADCggJDwAAAA==.',
Za='Zac:BAAANQADCggIFAABNQAECgcIBwAEAAAAAA==.Zacheeus:BAAANQAFFAIIAgAAAA==.Zaco:BAAANQAECgcIBwAAAA==.Zagran:BAAANQADCgUICgAAAA==.Zak:BAAANQAECgUICQABNQAECgcIBwAEAAAAAA==.Zalmo:BAAANQADCgIJAgABNQAECgUJCQAEAAAAAA==.Zantidious:BAAANQAECgQIBwAAAA==.Zaox:BAAANQADCggICAAAAA==.Zardragon:BAABNQAECoElAAIVAAkKpiXeAADBAwAVAAkKpiXeAADBAwAAAA==.',
Ze='Zelenä:BAAANQAECgQIBAAAAA==.Zelethor:BAABNQAECoEkAAMPAAkK/yH+AABnAwAPAAkKyiH+AABnAwAKAAMKbRJAJQHHAAAAAA==.Zelithor:BAABNQAECoEVAAMPAAgKQBitCQCuAQAPAAYKSRqtCQCuAQAKAAQKdhME+gAUAQAAAA==.Zephiatan:BAAANQAECgEIAgAAAA==.Zeryn:BAAANQABCgIJBAAAAA==.',
Zy='Zynalia:BAAANQADCgIIAgAAAA==.',
['Àr']='Àrcaneheart:BAAANQAECgUIEwAAAA==.',
['Íg']='Ígris:BAAANQAECgIIAgAAAA==.',
['Ði']='Ðiscoßunny:BAAANQADCgMJAwAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgcJBwAAAA==.',
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
