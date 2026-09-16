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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Mage-Frost','DemonHunter-Devourer','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Paladin-Retribution','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Hunter-Marksmanship','Priest-Shadow','Warlock-Affliction','Paladin-Protection','Hunter-BeastMastery','Shaman-Elemental','Mage-Arcane','Priest-Holy','Priest-Discipline','Druid-Guardian','Monk-Windwalker','Mage-Fire','Paladin-Holy',}
local provider = {region='US',realm='BurningLegion',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aalfie:BAAANQADCggIGgABNQAECgYIDwABAAAAAA==.',
Ad='Adaric:BAAANQADCgUIBQAAAA==.Aderren:BAAANQAECgYIDQAAAA==.',
Ae='Aeir:BAAANQAECgQICAAAAA==.Aether:BAAANQADCgcIBwAAAA==.Aevella:BAACNQAFFIEHAAMCAAQJCxv0AwAjAQACAAMJbxr0AwAjAQADAAEJ3RxHBwBiAAA1AAQKgR0AAwIACQmjI8wCAF0DAAIACAlDJMwCAF0DAAMABwmNIFcLAI0CAAAA.',
Ag='Agarn:BAAANQAECgQIBAABNQADCggIDgABAAAAAA==.Aghanaar:BAAANQAECgMIAwAAAA==.Agidan:BAAANQAECgcIEgAAAA==.Aguthus:BAAANQADCgYICgAAAA==.',
Ai='Airryon:BAAANQADCgMIAwAAAA==.',
Ak='Akaibara:BAAANQADCgYIDAAAAA==.',
Al='Alizar:BAAANQAECgcIEQAAAA==.Alleriá:BAAANQAECgYIDQAAAA==.Almaholzhert:BAAANQAECgEIAQAAAA==.Alor:BAAANQAECgYIDgAAAA==.Alundareth:BAAANQAECgYICAAAAA==.Alynnis:BAAANQADCgUIBQAAAA==.Alysanne:BAAANQADCgIIAgAAAA==.',
Am='Amelie:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
An='Anaphora:BAAANQABCgQIBAAAAA==.Angelmoon:BAAANQADCggICAAAAA==.Angryart:BAAANQADCgcICgABNQAECgUICgABAAAAAA==.Anklehumper:BAAANQABCgEIAQABNQAECgQIBwABAAAAAA==.Anniellusion:BAAANQAECgYICAAAAA==.Anthreax:BAAANQAECgcIDQAAAA==.',
Ap='Applepie:BAAANQAECgcIDAAAAA==.Apretzel:BAAANQAECgIIAgAAAA==.',
Ar='Aredstrasza:BAAANQABCgIIAgAAAA==.Armous:BAAANQAECgUIBgAAAA==.Arms:BAABNQAECoEaAAIEAAkJEx0AHwDcAgAEAAkJEx0AHwDcAgAAAA==.Arrano:BAAANQAECgEIAQAAAA==.',
As='Astrada:BAAANQADCggIEQAAAA==.',
Ay='Ayangat:BAABNQAECoEYAAIFAAkJmRzwEADSAgAFAAkJmRzwEADSAgAAAA==.Aycekween:BAAANQADCggICwAAAA==.',
Az='Azgar:BAAANQAECgQIBAAAAA==.Azusa:BAAANQAECgcIEwAAAA==.Azzulaa:BAAANQAECgIIBAAAAA==.',
Ba='Baconarrow:BAAANQADCggICAAAAA==.Baggedmilk:BAAANQADCggIGAAAAA==.',
Be='Belgarrion:BAAANQADCgYIAQAAAA==.Belladonna:BAABNQAECoEaAAMGAAkJsB7sGACeAgAGAAgJPR7sGACeAgAHAAYJsRv9DwDXAQABNQAFFAUIDQAGAPkSAA==.Bezirk:BAAANQAECggICgAAAA==.',
Bh='Bhaal:BAAANQAECgYIEAAAAA==.',
Bi='Bigboyfriend:BAAANQADCggICAAAAA==.Bighunters:BAAANQAECgEIAQAAAA==.Bigitaly:BAAANQAECgIIAwAAAA==.Bitemarkstwo:BAAANQADCgQIBAAAAA==.',
Bj='Bjardle:BAAANQAECgMIAwAAAA==.',
Bl='Blast:BAAANQAECgYIDgAAAA==.Bleedlife:BAAANQAECgUICwABNQAECgYIBwABAAAAAA==.Blindguard:BAABNQAECoEiAAIIAAgJORRABwArAgAIAAgJORRABwArAgAAAA==.Blinksoncd:BAABNQAECoEXAAIJAAgJyyCzAQDkAgAJAAgJyyCzAQDkAgAAAA==.Bloodrainer:BAAANQAECgYIDgAAAA==.Blutregen:BAAANQADCgMIBQABNQAECgUIDAABAAAAAA==.Blutzappel:BAAANQADCgIIAgABNQAECgUIDAABAAAAAA==.',
Bo='Bobfriskit:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.Bonehoof:BAAANQADCgQIBAAAAA==.Boot:BAAANQAECgIIAgABNQAECgcIEgABAAAAAA==.Bootkin:BAAANQAECgcIEgAAAA==.Borgorn:BAAANQAECgcIEgAAAA==.Bownes:BAAANQAECgUICQAAAA==.',
Br='Brambless:BAAANQADCgUIBQAAAA==.Breakfast:BAAANQAECgYIEAAAAA==.Brewbott:BAAANQAECggICgAAAA==.Brickp:BAAANQAECgcIDAAAAA==.Brimscythe:BAAANQADCgYIBgAAAA==.',
Bu='Bulinlok:BAAANQADCgMIAwAAAA==.Buluc:BAAANQAECgQICgAAAA==.Buroode:BAAANQAECgUIDAAAAA==.Busselton:BAAANQAECggIEAAAAA==.',
Bv='Bvngly:BAABNQAECoEdAAIKAAkJZx11CQAIAwAKAAkJZx11CQAIAwAAAA==.',
['Bè']='Bèat:BAAANQAECgQIBAAAAA==.',
Ca='Cakeshifter:BAAANQAECgcIBwAAAA==.Callister:BAAANQAECgUIDwAAAA==.Campanda:BAAANQAECgEIAQAAAA==.Carble:BAAANQADCggICAAAAA==.Cashgrabber:BAAANQADCgQIBgAAAA==.',
Ch='Champthyr:BAABNQAECoEcAAMLAAkJwREHDAArAgALAAkJawwHDAArAgAMAAYJehQFBwByAQAAAA==.Chaosblt:BAAANQAECgYICwAAAA==.Charmander:BAAANQADCgMIAwAAAA==.Cherwòòd:BAAANQABCgIIAgAAAA==.',
Cl='Claudia:BAAANQADCgIIAgAAAA==.Clobberela:BAAANQADCggIEAAAAA==.Clouds:BAAANQAECgIIAwAAAA==.',
Co='Coachkreeton:BAABNQAECoEcAAMEAAkJ/xhLIQDOAgAEAAkJ/xhLIQDOAgAIAAQJKBU1FAABAQAAAA==.Cologa:BAAANQADCggIDgAAAA==.Confess:BAAANQAECgYIDgAAAA==.Coola:BAAANQAECgQIBwAAAA==.Coollá:BAAANQADCggIEgABNQAECgQIBwABAAAAAA==.Coot:BAAANQAECgEIAgAAAA==.Copmage:BAAANQAFFAEIAQAAAA==.Cosines:BAAANQAECgcIEgAAAA==.Cowculated:BAAANQAECgUIDAAAAA==.Cowsrule:BAAANQAECgQICwAAAA==.',
Cr='Crestfallen:BAAANQADCgUICAAAAA==.',
Da='Daarfsad:BAAANQADCgYIBgAAAA==.Daeio:BAAANQAECgIIAwAAAA==.Darkaunnas:BAAANQAECgQIBQAAAA==.Darth:BAAANQAECgYIDAAAAA==.Darwinism:BAAANQADCggICAAAAA==.Daydayy:BAAANQAECggICAAAAA==.',
De='Deified:BAAANQADCgIIAgAAAA==.Deldor:BAAANQAECgEIAQAAAA==.Deli:BAAANQADCggIDQAAAA==.Demonetizer:BAABNQAECoEfAAINAAkJzCMkAwCPAwANAAkJzCMkAwCPAwAAAA==.Demonicart:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Demyxx:BAAANQAECgQIDQAAAA==.Denniecrane:BAEANQAECggIEwAAAA==.',
Dh='Dhjochann:BAAANQAECgIIAgAAAA==.',
Di='Dirtywork:BAAANQAECgcIDgAAAA==.',
Dm='Dmnikki:BAAANQADCgUIBgAAAA==.',
Do='Domiknight:BAAANQADCggIEAAAAA==.Dominic:BAAANQADCgQIBwAAAA==.Donttrustme:BAAANQAECgUIBgAAAA==.',
Dr='Drae:BAAANQAECgQIBQAAAA==.Dragunass:BAAANQAECgIIAgAAAA==.Drama:BAAANQABCgMIBAAAAA==.Drayu:BAAANQAECgEIAQAAAA==.',
Ei='Eilesa:BAAANQADCgcIDQAAAA==.',
El='Eldarin:BAAANQAECgUICAAAAA==.Eliardis:BAAANQADCgcIFAAAAA==.Ellwine:BAAANQADCgYIBgAAAA==.Elystravia:BAAANQADCgcIBwABNQAECgUIBgABAAAAAA==.',
Em='Emmahotson:BAAANQADCggIBQABNQAECgMIAwABAAAAAA==.Emrys:BAAANQAECggIDAAAAA==.',
En='Enigmazz:BAAANQAECgIIAwAAAA==.',
Ep='Epictitus:BAAANQAECgIIAgAAAA==.',
Es='Escaflowne:BAABNQAECoEhAAIOAAkJACYuAQDuAwAOAAkJACYuAQDuAwAAAA==.',
Et='Ethaee:BAAANQADCgYIDAAAAA==.',
Eu='Euli:BAAANQADCgYIBwABNQAFFAUICAAPAEwVAA==.Eurydices:BAAANQADCgYIBgAAAA==.',
Ev='Evangelión:BAAANQADCgUIDwAAAA==.',
Ex='Exit:BAAANQAECgUICAAAAA==.Extermine:BAAANQADCggICAAAAA==.',
Ey='Eyks:BAAANQAECgEIAQAAAA==.',
Fa='Faelithndrel:BAAANQAECgUIDwAAAA==.Farmette:BAAANQAECgMIBQAAAA==.',
Fe='Felbeard:BAACNQAFFIENAAMGAAUJ+RKGAwBWAQAGAAQJbhWGAwBWAQAHAAIJeAq5BgCnAAA1AAQKgSMAAwYACQmrJKoFAFIDAAYACAmrJKoFAFIDAAcABwlUFVELABkCAAAA.Feleâ:BAAANQAECgEIAQAAAA==.Ferreday:BAAANQAECgQIBgAAAA==.Fewix:BAAANQABCgIIAgAAAA==.',
Fi='Fingoflin:BAAANQADCggICAAAAA==.Firechicken:BAAANQAECgEIAQAAAA==.Firemystic:BAAANQADCgcICwAAAA==.',
Fl='Flamereaper:BAAANQADCgYIBgABNQAECgYIEgABAAAAAA==.Fleakertwo:BAABNQAECoEhAAIDAAkJ+g5SDgBYAgADAAkJ+g5SDgBYAgAAAA==.Floopzii:BAAANQAECgYIDQAAAA==.Flói:BAAANQADCggIFQAAAA==.',
Fr='Friedrib:BAABNQAECoEgAAMQAAkJTB+rCQBCAwAQAAkJTB+rCQBCAwARAAMJ3hL3KQDRAAAAAA==.Frostlas:BAAANQABCgMIBQAAAA==.',
Fu='Fulldipey:BAAANQAECgYIDAAAAA==.Furrythot:BAABNQAECoEhAAIPAAkJdiIeBACFAwAPAAkJdiIeBACFAwAAAA==.Fuzeewuzee:BAEANQAECgUIBQABNQAECggIEwABAAAAAA==.',
Ga='Galise:BAAANQAECgIIAgAAAA==.Galynnia:BAAANQADCgYIBgAAAA==.Gangstafrost:BAAANQADCgMIBQAAAA==.',
Gd='Gduff:BAAANQAECgEIAQAAAA==.',
Ge='Genaveive:BAABNQAECoEcAAISAAkJFhNrEwBRAgASAAkJFhNrEwBRAgAAAA==.',
Gg='Ggodetan:BAAANQADCgYIBgAAAA==.',
Gi='Gigglespit:BAAANQAECgQIBwAAAA==.Gildeath:BAAANQAECggIDAAAAA==.Gimlie:BAAANQAECgUICQABNQAECgYIEQABAAAAAA==.Gimmix:BAAANQAECgYIEQAAAA==.',
Go='Gobbylynn:BAABNQAECoEgAAITAAkJwSKfAwB9AwATAAkJwSKfAwB9AwABNQAFFAQIBwACAAsbAA==.Gooptoob:BAAANQAECgQIBAAAAA==.Goosetits:BAAANQABCgIIAgAAAA==.',
Gr='Grogosh:BAAANQADCgYIBgAAAA==.',
Gu='Guaplord:BAAANQADCgMIAwAAAA==.Gulog:BAAANQADCgMIAwAAAA==.Guzzlord:BAAANQADCgYIBgAAAA==.',
Ha='Hagran:BAAANQADCgMIAwAAAA==.Haint:BAAANQAECgQICwAAAA==.Halzak:BAAANQAECgEIAgAAAA==.Harambeisbae:BAAANQAECgYICAAAAA==.Harmön:BAAANQAECgIIAwAAAA==.Hawdazz:BAAANQADCgQIBAABNQADCgQIBgABAAAAAA==.',
He='Healah:BAAANQADCgcIBwABNQAECgYIFwANAGodAA==.Hegotthedrip:BAABNQAECoEXAAQHAAkJRB0vCABUAgAHAAcJrx0vCABUAgAGAAQJ1RvKZgA5AQAUAAEJXwcbGQBDAAAAAA==.Helios:BAABNQAECoEXAAMOAAkJHR5YGgDPAgAOAAkJIh1YGgDPAgAVAAUJzxvLEQCrAQABNQABCgYIBgABAAAAAA==.Hellaquin:BAABNQAECoEfAAITAAkJ8yKlAgCYAwATAAkJ8yKlAgCYAwAAAA==.Hellomotojr:BAAANQAECgYICwAAAA==.',
Hi='Hijackx:BAAANQAECgcIEgAAAQ==.Hinotama:BAAANQADCggICgAAAA==.',
Ho='Holdne:BAAANQAECgYIDAAAAA==.Holynova:BAAANQAECgUICAAAAA==.Holypoker:BAAANQAECgEIAQAAAA==.Holysuave:BAAANQADCggICgAAAA==.Horu:BAAANQAECgMIAwAAAA==.Horux:BAAANQADCggIDQAAAA==.',
Hr='Hrothgar:BAAANQAECggICAAAAA==.',
Hy='Hyhu:BAAANQAECgcIEwAAAA==.Hymlok:BAAANQAECgYIDQAAAA==.Hymnsorrow:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Hyperion:BAAANQAECgcIEgAAAA==.Hyuga:BAAANQAECgQIBAAAAA==.',
Ic='Iccarium:BAAANQAECgYICAAAAA==.Icexjh:BAAANQAECgMIBQAAAA==.Icritmypañts:BAAANQAECgcIBwAAAA==.',
Ig='Ignatowski:BAAANQAECgIIAgAAAA==.Igorongon:BAAANQAECgcIEQAAAA==.',
Ii='Iindulgelag:BAAANQADCgcIBwAAAA==.',
Ik='Ikhawe:BAAANQADCgYICAAAAA==.',
In='Inebrious:BAAANQAECgIIAgAAAA==.',
Io='Ionna:BAAANQADCggICgABNQAECgUICAABAAAAAA==.',
Ir='Ironmann:BAAANQAECgUIDQAAAA==.',
It='Itsmäam:BAAANQAECgYIDQABNQAECgcIBwABAAAAAA==.',
Iv='Ivandar:BAAANQABCgUIBQAAAA==.',
Iw='Iwixl:BAAANQADCgEIAQAAAA==.',
Ja='Jabamental:BAABNQAECoEgAAIFAAkJiyTbAQCuAwAFAAkJiyTbAQCuAwAAAA==.Jaded:BAAANQADCggIGgAAAA==.Jadefonda:BAAANQAECgMIAwAAAA==.Jamx:BAAANQAECgYICgABNQAECgkJIgAWAMQgAA==.Jamy:BAABNQAECoEiAAMWAAkJxCC9EwDZAgAWAAgJpSO9EwDZAgASAAgJHBVEFwAZAgAAAA==.Jandria:BAAANQAECgYIDgAAAA==.Janos:BAAANQAFFAIIAgAAAA==.Jashin:BAAANQAECgcIEwAAAA==.Jawbreaker:BAAANQADCgQIBQAAAA==.Jaycifer:BAABNQAECoEfAAQGAAkJrB01GQCcAgAGAAkJchg1GQCcAgAHAAUJHxwVGACFAQAUAAMJ3iHFCgDvAAAAAA==.',
Je='Jerm:BAAANQAECgQIBQAAAA==.Jerzyp:BAAANQADCgEIAQAAAA==.Jessia:BAAANQAECgYICQAAAA==.',
Jo='Joobi:BAAANQAECgQICgAAAA==.Jorrethoi:BAAANQAECgMIBQAAAA==.',
Ju='Jurble:BAAANQAECggIEwAAAA==.Juurou:BAAANQADCggIEgAAAA==.',
Jy='Jynn:BAAANQAECgMIAwAAAA==.',
['Jä']='Jäydedfäith:BAAANQADCgYIDAAAAA==.',
Ka='Kabbu:BAAANQAECggIEAAAAA==.Kaimed:BAAANQAECgcIEwAAAA==.Kaizer:BAEANQAFFAEIAgAAAA==.Kalrakin:BAAANQADCgMIAwAAAA==.Kamton:BAAANQADCgUIBQAAAA==.Kardrig:BAAANQADCggIGwAAAA==.Katwoman:BAAANQAECgcIEQAAAA==.Kaylana:BAAANQADCgYIFAAAAA==.',
Kd='Kdzee:BAAANQADCggIEwAAAA==.',
Ke='Keicus:BAAANQABCgUIAwABNQAECgEIAQABAAAAAA==.',
Kh='Khalezzi:BAAANQAFFAEIAgAAAA==.Khonos:BAAANQAECgYIDAAAAA==.',
Ki='Killercold:BAAANQAECgIIAgAAAA==.Kimoora:BAAANQADCgQIBQAAAA==.Kirarawr:BAAANQABCgIIAgAAAA==.Kisstrosity:BAACNQAFFIEHAAIWAAUJhxQgAQCzAQAWAAUJhxQgAQCzAQA1AAQKgR0AAhYACQlFIvMJADcDABYACQlFIvMJADcDAAAA.',
Kl='Kloosterhuis:BAAANQAECgYIDAAAAA==.',
Ko='Kodoseeker:BAAANQAECgYIEAAAAA==.Kovos:BAAANQADCgYIBwAAAA==.Kovä:BAAANQADCgcIBwAAAA==.',
Kr='Krean:BAAANQAECgUICQAAAA==.Krisali:BAAANQADCgIIAgAAAA==.',
Ku='Kunardh:BAAANQAECgIIAgABNQAECgcIEgABAAAAAA==.Kunarr:BAAANQAECgcIEgAAAA==.',
Ky='Kylerichards:BAAANQAECgUIBwAAAA==.Kyohunt:BAAANQAECgcIEwAAAA==.Kyoshock:BAAANQAECgYICAABNQAECgcIEwABAAAAAA==.',
La='Ladonda:BAAANQADCgYICAAAAA==.Lanius:BAAANQABCggIDQAAAA==.Lanyx:BAAANQADCgYIDAAAAA==.Lareina:BAABNQAECoEhAAIXAAkJwxmTFADXAgAXAAkJwxmTFADXAgAAAA==.Larinara:BAAANQADCgEIAQAAAA==.Laziness:BAAANQAFFAEIAQABNQAECgIIAgABAAAAAA==.',
Le='Lemonhope:BAAANQAECgIIBQAAAA==.',
Li='Lightnights:BAAANQADCgYIBgAAAA==.Lilmerlin:BAAANQADCgYICgAAAA==.Linchknight:BAAANQAECgQIBAAAAA==.Littlefudger:BAAANQABCgIIAgAAAA==.Livola:BAAANQAECgQICgAAAA==.',
Lo='Locknik:BAAANQADCgYIDwAAAA==.Lokkahn:BAAANQADCggIGwAAAA==.',
Lu='Lunarsol:BAAANQAECgYIEAAAAA==.',
Ly='Lyanna:BAAANQAECgEIAQABNQAECgYIEQABAAAAAA==.',
['Lä']='Lätêx:BAABNQAECoEfAAIOAAkJoia2AAD6AwAOAAkJoia2AAD6AwAAAA==.',
Ma='Magicmeatxxl:BAAANQAECgUIBwAAAA==.Magusgobrr:BAAANQAECgcIEwAAAA==.Mahawker:BAAANQAECgQIBAAAAA==.Mahfaty:BAAANQADCgYIBgAAAA==.Malüs:BAAANQADCggIBQAAAA==.Marcus:BAAANQAECgIIAgABNQAECggIDQABAAAAAA==.Marideous:BAAANQADCgcIDAAAAA==.Mark:BAAANQAECgEIAQABNQAECggIDQABAAAAAA==.Marth:BAAANQAECgUIBQAAAA==.Mashem:BAABNQAECoEaAAIYAAkJSBdFOQCsAgAYAAkJSBdFOQCsAgAAAA==.Mathias:BAAANQAECgIIAgAAAA==.Mattpriest:BAABNQAECoEhAAMZAAkJ3CK/CQAPAwAZAAkJ3CK/CQAPAwAaAAQJVRnwCwD7AAAAAA==.Maxverclappn:BAAANQAECgQIBAAAAA==.Maxvertrappn:BAAANQAECggIEwAAAA==.',
Mc='Mcsloppy:BAAANQAECgUIBQAAAA==.',
Me='Meshkuhrib:BAAANQADCgUIBQABNQAECgkJIAAQAEwfAA==.Methicillin:BAAANQADCggICgAAAA==.Methir:BAAANQADCgUICQAAAA==.',
Mi='Mightythor:BAAANQAECgQIBAAAAA==.Milkedmoose:BAAANQAECgQIBwAAAA==.Milkers:BAABNQAECoEdAAIYAAkJ5CDQGAA4AwAYAAkJ5CDQGAA4AwAAAA==.Minimoose:BAAANQAECgUICAAAAA==.Misclick:BAAANQADCgQICAABNQAECgYIDwABAAAAAA==.',
Mo='Moistymonk:BAAANQADCgEIAQAAAA==.Moona:BAAANQAECgYICwAAAA==.Moonberry:BAAANQAECggIEAAAAA==.Moonlock:BAAANQADCgYIDAAAAA==.Morissa:BAAANQADCgMIAwAAAA==.Motomotoo:BAAANQAECgEIAQAAAA==.',
Mu='Muffinfeliz:BAAANQAECgQIBgAAAA==.',
My='Myriad:BAAANQAECgYIBwABNQAFFAUICAALACUYAA==.Mythundreran:BAAANQAECgQIBAAAAA==.',
Na='Namdari:BAAANQAECgUICAAAAA==.Nanahammer:BAAANQADCgEIAQAAAA==.Nanasquirts:BAAANQADCgEIAQABNQAFFAEIAQABAAAAAA==.Nazzan:BAAANQAECgEIAgABNQAECggIGAAXAB8cAA==.',
Ni='Nightmàre:BAAANQAECgEIAQAAAA==.Nightshade:BAAANQAECgQIBAABNQAECgkJHwATAPMiAA==.Nightstride:BAAANQADCgMIAQAAAA==.Nikkô:BAAANQABCgQICAAAAA==.Nirra:BAAANQAECgQIBAAAAA==.Niso:BAAANQAECgEIAQAAAA==.',
No='Noatt:BAAANQADCgMIAwAAAA==.Nokona:BAAANQADCgEIAQAAAA==.Novapal:BAAANQAECgQICQAAAA==.Novura:BAAANQADCgYIBgAAAA==.',
Nu='Numnumzz:BAAANQABCgQIBgAAAA==.',
Oc='Ochnauq:BAAANQAECgYIEAABNQAECgkJIQAbAF4TAA==.',
Om='Omarid:BAAANQADCgIIBAAAAA==.Omfgpie:BAAANQAECgcIEAAAAA==.',
Oo='Ooiskan:BAAANQADCgIIAgAAAA==.',
Or='Orcall:BAAANQAECgUIBgAAAA==.',
Ov='Overcharged:BAAANQADCgYICgAAAA==.',
Ow='Owencaddell:BAAANQADCgYIEAAAAA==.',
Pa='Pada:BAAANQAECgYIDAAAAA==.Pakku:BAABNQAECoEhAAIcAAkJdSCXBABBAwAcAAkJdSCXBABBAwAAAA==.Paladaine:BAAANQADCggIEgAAAA==.Pallix:BAAANQAECgYIDwABNQAECgkJHwAGAKwdAA==.Palpacino:BAAANQADCggIEgABNQAECgYIDQABAAAAAA==.Palytivecare:BAAANQAECgIIAgAAAA==.Papajaja:BAAANQAECgcIDwAAAA==.Papal:BAAANQADCgcIBwAAAA==.Paramôre:BAAANQAECggIAwAAAA==.',
Pe='Peace:BAAANQAECggIDQAAAA==.Peachpanther:BAAANQADCgYIBgAAAA==.Pegmianis:BAAANQAECgQIBQAAAA==.',
Ph='Phatsword:BAAANQAECgIIAgAAAA==.Phigon:BAAANQAECgQIBwAAAA==.',
Pi='Pinknmoist:BAAANQAECgQIBAAAAA==.Pixelbaddy:BAAANQADCggIEQAAAA==.',
Pl='Plumbus:BAAANQADCggIDQAAAA==.',
Po='Polygrip:BAAANQAECgMIBQAAAA==.Popechaz:BAAANQADCgYIDAAAAA==.',
Pr='Praxtintar:BAAANQAECgUIBQAAAA==.Pru:BAAANQABCgIIAgAAAA==.Prutank:BAAANQABCgEIAQAAAA==.',
Ps='Psychonaut:BAAANQAECgUIBQABNQAECgUIBwABAAAAAA==.',
Pu='Pure:BAAANQAFFAIIAgAAAA==.Purman:BAAANQADCgYICQAAAA==.',
Py='Pyrine:BAAANQAECgIIAgAAAA==.',
Qu='Quancho:BAABNQAECoEhAAIbAAkJXhPyBQBFAgAbAAkJXhPyBQBFAgAAAA==.',
Qw='Qwade:BAAANQAECgEIAQAAAA==.',
Ra='Ragran:BAAANQADCggIEgAAAA==.Rakaman:BAAANQAECgUICQAAAA==.Ramza:BAACNQAFFIEIAAIOAAUJKB/hAAD6AQAOAAUJKB/hAAD6AQA1AAQKgSEAAg4ACQlsJssAAPgDAA4ACQlsJssAAPgDAAAA.Ranbou:BAABNQAECoEhAAMYAAkJ+RwYLgDYAgAYAAkJ+RwYLgDYAgAdAAQJHxTsAgAmAQAAAA==.Randor:BAAANQABCgQIBgAAAA==.Rashka:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Ratatasquer:BAAANQAECgUICAAAAA==.Rattleballs:BAAANQAECgQIBAABNQAECgIIBQABAAAAAA==.',
Re='Reegss:BAAANQADCgEIAQAAAA==.Regsia:BAAANQAECgEIAQAAAA==.Repens:BAAANQAECgUICAAAAA==.Restosterone:BAAANQAECggICgAAAA==.Ret:BAAANQAECgQIBAABNQAECgkJGgAEABMdAA==.Retbeanznrce:BAAANQADCggICgAAAA==.Retful:BAAANQADCgUIBQABNQAECgkJHwANAMwjAA==.Revo:BAAANQADCgYIBgAAAA==.',
Rh='Rhaid:BAAANQAECgYIDQAAAA==.Rhordrick:BAAANQAECgQIBwAAAA==.',
Ri='Rizzgrizzly:BAAANQADCgIIAgAAAA==.Rizzurrect:BAAANQADCgIIAgAAAA==.',
Rn='Rng:BAAANQADCgIIAgAAAA==.',
Ro='Roquefort:BAAANQADCgcIDAAAAA==.Roscoedshamn:BAAANQADCgYICQAAAA==.Rowdi:BAAANQADCggIDAAAAA==.',
Ru='Rukarm:BAAANQADCgcIHAAAAA==.Runawaynow:BAACNQAFFIENAAIFAAYJWBE5AQAOAgAFAAYJWBE5AQAOAgA1AAQKgR0AAgUACQkeId8JAB8DAAUACQkeId8JAB8DAAAA.Runelife:BAAANQAECgYIBwAAAA==.',
Sa='Saelaissamlt:BAAANQADCgQIBAAAAA==.Samdeathfoot:BAAANQAECgMIBQAAAA==.Samsara:BAAANQABCgMIAwAAAA==.Sartok:BAAANQAECgIIAgAAAA==.',
Sc='Scottnails:BAAANQAECgcIBwAAAA==.',
Se='Seyuri:BAAANQAECgcIEwAAAA==.Seán:BAAANQAECgUICAAAAA==.',
Sh='Shadowar:BAAANQAECgQIBAAAAA==.Shadowbell:BAAANQAECgYIDQAAAA==.Shadowgale:BAAANQAECgQIBAAAAA==.Shamanramen:BAAANQABCgQIBAAAAA==.Shantari:BAAANQADCgQIBQAAAA==.Shayrpd:BAAANQADCggIEQAAAA==.Shoobìes:BAAANQABCgUICQAAAA==.Shøckybalboa:BAAANQAECgMIBAAAAA==.',
Si='Sinnmage:BAAANQABCgMIAwAAAA==.Sinnshifts:BAAANQAECgQIBAAAAA==.',
Sk='Skhorn:BAAANQAECgYIDQAAAA==.Skuûub:BAAANQADCgYICQAAAA==.',
Sl='Slowone:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Slãyer:BAAANQAECgMIBQAAAA==.',
Sm='Smallblessin:BAAANQADCgMIAwAAAA==.Smokedrib:BAAANQAECgQIBAABNQAECgkJIAAQAEwfAA==.',
Sn='Snorlock:BAAANQAECgEIAQAAAA==.',
So='Sometymz:BAAANQAECgcIEAAAAA==.',
Sp='Spareathot:BAABNQAECoEXAAMLAAgJMBP6CwAsAgALAAgJMBP6CwAsAgAMAAIJzwTNEQBLAAAAAA==.Speedspanker:BAAANQAECgUICAAAAA==.Spirulina:BAAANQADCgIIAgAAAA==.Splashsplash:BAAANQADCgQIBQAAAA==.',
St='Staar:BAAANQAECgIIAwAAAA==.Starflames:BAAANQADCgQIBAAAAA==.Stellarèé:BAABNQAECoEhAAMGAAkJKCTzBgA9AwAGAAgJ7yPzBgA9AwAHAAYJcx5PDAAIAgAAAA==.Stiliar:BAAANQAECgMIBQAAAA==.Strongdroid:BAAANQADCgcICgAAAA==.Strángè:BAAANQAECgUIDAAAAA==.Stríve:BAAANQAECgEIAgAAAA==.Stêlla:BAAANQADCgQIBAAAAA==.',
Su='Substrate:BAAANQAECgMIBAAAAA==.Sugarteets:BAAANQADCgYIBgABNQAECgcIBwABAAAAAA==.Suramo:BAAANQAECgYIEAAAAA==.',
Sv='Svaval:BAABNQAECoEZAAIPAAkJbSKzBAB5AwAPAAkJbSKzBAB5AwAAAA==.',
Sy='Syles:BAAANQADCgYIDAABNQAECgUICwABAAAAAA==.Syphon:BAAANQAECgcIEAAAAA==.',
Ta='Tamedurmom:BAAANQAECgYIDQAAAA==.Tarekk:BAAANQAECgUIDAAAAA==.Tarewreck:BAAANQADCgcIDAAAAA==.Tariqpapi:BAAANQAECgcIEgAAAA==.Taxes:BAAANQAECgEIAQAAAA==.',
Te='Tehcountess:BAAANQAECgcIEwAAAA==.',
Th='Tharos:BAAANQAECgMIAwAAAA==.Thebeerwiz:BAAANQADCgQIBgAAAA==.Thecarebear:BAAANQAECgQIBAAAAA==.Thelianne:BAAANQAECgMIBQAAAA==.Thelmina:BAAANQAECgQIBAAAAA==.Thermidor:BAAANQAECgUICAAAAA==.Thorps:BAAANQAECgcIDwAAAA==.Thragg:BAAANQADCgQIBAAAAA==.Thundarr:BAAANQABCgYIBgAAAA==.Thurstee:BAAANQAECgYICAAAAA==.',
Ti='Tibian:BAAANQAECgcIEwAAAA==.Tigerpalm:BAAANQAECgMIBgAAAA==.Tilexer:BAAANQADCgMIAwAAAA==.Tinypreest:BAAANQADCgYIBgAAAA==.Tinyshocker:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.',
To='Totemlyfoxy:BAAANQAECgEIAQAAAA==.Touchedd:BAAANQADCgIIAgABNQAECgkJHwAeACAdAA==.',
Tr='Trackker:BAAANQADCgQIBAAAAA==.Trapshotumad:BAAANQAECgQIBAAAAA==.Treesdk:BAAANQAECgcIEQAAAA==.Trugs:BAAANQAECgUIBgAAAA==.',
Tu='Tuntunvergun:BAABNQAECoEZAAIQAAkJtRceFAC6AgAQAAkJtRceFAC6AgAAAA==.',
Tw='Twelvetacos:BAABNQAECoEbAAIFAAkJ2h3KCgAVAwAFAAkJ2h3KCgAVAwAAAA==.',
Ty='Tyralde:BAAANQAECgQICwAAAA==.',
Ud='Udenlo:BAAANQAECgMIAwAAAA==.',
Um='Umbraheart:BAAANQADCgYIEAAAAA==.',
Un='Unclepumper:BAAANQADCgQIBAAAAA==.Unsub:BAAANQADCgEIAQABNQAECgkJHQAYAOQgAA==.',
Us='Usui:BAAANQADCgEIAQAAAA==.',
Va='Vaellian:BAAANQADCgUIBQAAAA==.Valei:BAAANQAECgcICgAAAA==.Valvadime:BAAANQAECgEIAwAAAA==.Vanstian:BAAANQAECgEIAQAAAA==.Vantoes:BAAANQAECgcIDgAAAA==.',
Ve='Vecidus:BAAANQAECgIIAgAAAA==.Velassi:BAAANQAECgYIDwAAAA==.Veldora:BAAANQADCgYICwAAAA==.Velouriuum:BAAANQADCgUICQAAAA==.Vetrandus:BAAANQADCgYIBgAAAA==.',
Vh='Vhioth:BAAANQADCgQIBgAAAA==.',
Vi='Vielli:BAAANQAECgUICAAAAA==.Vintari:BAAANQAECgEIAQAAAA==.Vivvyquinn:BAAANQADCgMIAwAAAA==.',
Vo='Volorren:BAAANQAECgQIBQAAAA==.Volzu:BAAANQAECgcIEQAAAA==.',
Wa='Walon:BAAANQADCgMIAwAAAA==.Warwickdavis:BAAANQADCgYIDAABNQADCgYIFAABAAAAAA==.Wazerk:BAAANQADCgcIBwAAAA==.',
We='Weirdchampx:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.',
Wh='Whely:BAEBNQAECoEgAAIIAAkJZSVeAADZAwAIAAkJZSVeAADZAwAAAA==.Whitegoodman:BAAANQADCggICAABNQAECggIFQAYABgcAA==.Whitegrlswag:BAAANQAECgIIAgAAAA==.',
Wi='Wilcoxx:BAABNQAECoEfAAMHAAkJdh0XDQD8AQAGAAcJ2hxXIgBiAgAHAAcJdxYXDQD8AQAAAA==.Wilcozz:BAAANQAECgEIAQABNQAECgkJHwAHAHYdAA==.Wildtree:BAAANQABCgYIBAAAAA==.Wipeout:BAAANQADCgcIGgAAAA==.Wirecutter:BAAANQAECgcIBwAAAA==.Wixjones:BAAANQADCgUIBQABNQAECgkJIgAWAMQgAA==.Wizurd:BAAANQAECgYIEAAAAA==.',
Wo='Wolfcult:BAAANQAECgYIEAAAAA==.Wompstomper:BAAANQADCgEIAQAAAA==.Worcklock:BAAANQAFFAIIAwABNQAFFAUIDQAGAPkSAA==.',
Wr='Wrapwrap:BAAANQAECgYIDQAAAA==.Wratheon:BAAANQADCgEIAQAAAA==.',
['Wì']='Wìxÿ:BAAANQADCgcIBwAAAA==.',
['Wî']='Wîxx:BAABNQAECoEbAAIRAAkJmR16BQADAwARAAkJmR16BQADAwAAAA==.Wîxÿ:BAAANQAECgUIBgAAAA==.',
Xe='Xestsalb:BAEANQAECggIAwAAAA==.',
Yo='Yourlock:BAAANQAECgcIDAAAAA==.',
Yu='Yuseolha:BAAANQADCggIDwAAAA==.',
Za='Zac:BAAANQADCggIFAABNQAECgQIBAABAAAAAA==.Zacheeus:BAAANQAECgYICwAAAA==.Zaco:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Zagran:BAAANQADCgUIBgAAAA==.Zak:BAAANQAECgQIBAAAAA==.Zantidious:BAAANQAECgMIAwAAAA==.Zaox:BAAANQADCggICAAAAA==.Zardragon:BAABNQAECoEhAAILAAkJmCWNAADRAwALAAkJmCWNAADRAwAAAA==.',
Ze='Zelenä:BAAANQAECgQIBAAAAA==.Zelethor:BAABNQAECoEgAAMJAAkJ/CGJAAB9AwAJAAkJyiGJAAB9AwAYAAMJZRIm+ADMAAAAAA==.Zelithor:BAAANQAECgYIDQAAAA==.Zeryn:BAAANQABCgIIBAAAAA==.',
Zy='Zynalia:BAAANQADCgIIAgAAAA==.',
['Àr']='Àrcaneheart:BAAANQAECgUIDwAAAA==.',
['Íg']='Ígris:BAAANQAECgIIAgAAAA==.',
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
