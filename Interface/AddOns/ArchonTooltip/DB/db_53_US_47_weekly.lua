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

local lookup = {'Unknown-Unknown','Warlock-Demonology','DemonHunter-Havoc','Paladin-Retribution','Warlock-Destruction','Rogue-Assassination','Druid-Balance','Druid-Restoration','DeathKnight-Blood','Warlock-Affliction','Priest-Shadow','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Priest-Holy','Priest-Discipline','Evoker-Devastation','Druid-Guardian','Monk-Windwalker','Mage-Arcane','Warrior-Protection','Mage-Frost',}
local provider = {region='US',realm='BurningLegion',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aalfie:BAAANQADCgcIEgABNQAECgUICQABAAAAAA==.',
Ad='Aderren:BAAANQAECgUIBwAAAA==.',
Ae='Aeir:BAAANQAECgQICAAAAA==.Aether:BAAANQADCgcIBwAAAA==.Aevella:BAAANQAFFAIIAgAAAA==.',
Ag='Agarn:BAAANQAECgQIBAABNQADCggIDgABAAAAAA==.Aghanaar:BAAANQAECgIIAgAAAA==.Agidan:BAAANQAECgcICwAAAA==.Aguthus:BAAANQADCgYICgAAAA==.',
Ak='Akaibara:BAAANQADCgUIBgAAAA==.',
Al='Alizar:BAAANQAECgcIEQAAAA==.Alleriá:BAAANQAECgQIBwAAAA==.Almaholzhert:BAAANQAECgEIAQAAAA==.Alor:BAAANQAECgQICAAAAA==.Alundareth:BAAANQAECgYIBgAAAA==.Alynnis:BAAANQADCgUIBQAAAA==.Alysanne:BAAANQADCgIIAgAAAA==.',
Am='Amelie:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
An='Angryart:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Anniellusion:BAAANQAECgQIBgAAAA==.Anthreax:BAAANQAECgYIBgAAAA==.',
Ap='Applepie:BAAANQAECgQIBQAAAA==.Apretzel:BAAANQADCgIIAQAAAA==.',
Ar='Armous:BAAANQAECgEIAQAAAA==.Arms:BAAANQAFFAEIAQAAAA==.Arrano:BAAANQAECgEIAQAAAA==.',
As='Astrada:BAAANQADCggICgAAAA==.',
Ay='Ayangat:BAAANQAFFAIIAgAAAA==.Aycekween:BAAANQADCggICwAAAA==.',
Az='Azgar:BAAANQAECgQIBAAAAA==.Azusa:BAAANQAECgcIDAAAAA==.Azzulaa:BAAANQAECgIIAgAAAA==.',
Ba='Baconarrow:BAAANQADCggICAAAAA==.Baggedmilk:BAAANQADCggIGAAAAA==.',
Be='Belgarrion:BAAANQADCgYIAQAAAA==.Belladonna:BAAANQAECggIEwABNQAFFAQICAACAN4QAA==.Bezirk:BAAANQAECgcICAAAAA==.',
Bh='Bhaal:BAAANQAECgYICgAAAA==.',
Bi='Bigboyfriend:BAAANQADCggICAAAAA==.Bighunters:BAAANQAECgEIAQAAAA==.Bigitaly:BAAANQAECgEIAQAAAA==.Bitemarkstwo:BAAANQABCgQIBAAAAA==.',
Bj='Bjardle:BAAANQAECgMIAwAAAA==.',
Bl='Blast:BAAANQAECgYICAAAAA==.Bleedlife:BAAANQAECgUIBwAAAA==.Blindguard:BAAANQAECgcIEwAAAA==.Blinksoncd:BAAANQAECgcIDQAAAA==.Bloodrainer:BAAANQAECgQICAAAAA==.Blutregen:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Blutzappel:BAAANQADCgIIAgABNQAECgUIBgABAAAAAA==.',
Bo='Boot:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.Bootkin:BAAANQAECgcICwAAAA==.Borgorn:BAAANQAECgcICgAAAA==.Bownes:BAAANQAECgMIBQAAAA==.',
Br='Brewbott:BAAANQAECgcICAAAAA==.Brickp:BAAANQAECgYICQAAAA==.Brimscythe:BAAANQADCgYIBgAAAA==.',
Bu='Bulinlok:BAAANQADCgMIAwAAAA==.Buluc:BAAANQAECgQIBgAAAA==.Buroode:BAAANQAECgUIBgAAAA==.Busselton:BAAANQAECgcIDQAAAA==.',
Bv='Bvngly:BAAANQAFFAEIAQAAAA==.',
['Bè']='Bèat:BAAANQADCgcIBwAAAA==.',
Ca='Cakeshifter:BAAANQADCgcIBwAAAA==.Callister:BAAANQAECgQIBQAAAA==.Campanda:BAAANQAECgEIAQAAAA==.Carble:BAAANQADCggICAAAAA==.Cashgrabber:BAAANQADCgQIBgAAAA==.',
Ch='Champthyr:BAAANQAFFAEIAQAAAA==.Chaosblt:BAAANQAECgUIBQAAAA==.Cherwòòd:BAAANQABCgIIAgAAAA==.',
Cl='Claudia:BAAANQADCgIIAgAAAA==.Clobberela:BAAANQADCggICAAAAA==.Clouds:BAAANQAECgEIAQAAAA==.',
Co='Coachkreeton:BAAANQAECgcIDwAAAA==.Cologa:BAAANQADCggIDgAAAA==.Confess:BAAANQAECgYICAAAAA==.Coola:BAAANQAECgMIAwAAAA==.Coollá:BAAANQADCgUICgABNQAECgMIAwABAAAAAA==.Coot:BAAANQAECgEIAgAAAA==.Copmage:BAAANQAECgQIBQAAAA==.Cosines:BAAANQAECgcICwAAAA==.Cowculated:BAAANQAECgUIBwAAAA==.Cowsrule:BAAANQAECgQIBwAAAA==.',
Cr='Crestfallen:BAAANQADCgEIAgAAAA==.Cryokaren:BAAANQADCgQIBQAAAA==.',
Da='Daarfsad:BAAANQADCgYIBgAAAA==.Daeio:BAAANQADCgUIBgAAAA==.Darkaunnas:BAAANQAECgEIAQAAAA==.Darth:BAAANQAECgUIBgAAAA==.',
De='Deified:BAAANQADCgIIAgAAAA==.Deldor:BAAANQAECgEIAQAAAA==.Deli:BAAANQADCggIDQAAAA==.Demonetizer:BAABNQAECoEXAAIDAAkJJyPiAgBfAwADAAkJJyPiAgBfAwAAAA==.Demonicart:BAAANQADCgUIBQAAAA==.Demyxx:BAAANQAECgUICQAAAA==.Denniecrane:BAEANQAECggIEAAAAA==.',
Dh='Dhjochann:BAAANQAECgIIAgAAAA==.',
Di='Dirtywork:BAAANQAECgYIBwAAAA==.',
Do='Domiknight:BAAANQADCggIEAAAAA==.Dominic:BAAANQADCgMIAwAAAA==.Donttrustme:BAAANQAECgEIAQAAAA==.',
Dr='Drae:BAAANQAECgEIAQAAAA==.Dragunass:BAAANQAECgIIAgAAAA==.Drama:BAAANQABCgMIAgAAAA==.Drayu:BAAANQADCgYIEgAAAA==.',
Du='Duggin:BAAANQAECgYICgAAAA==.',
Ei='Eilesa:BAAANQADCgcIDQAAAA==.',
El='Eldarin:BAAANQAECgMIAwAAAA==.Eliardis:BAAANQADCgcIDgAAAA==.Ellwine:BAAANQADCgUIBQAAAA==.Elystravia:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Em='Emrys:BAAANQAECgQIBAAAAA==.',
En='Enigmazz:BAAANQAECgIIAgAAAA==.',
Ep='Epictitus:BAAANQADCgQIBAAAAA==.',
Es='Escaflowne:BAABNQAECoEYAAIEAAkJviMIAwCnAwAEAAkJviMIAwCnAwAAAA==.',
Et='Ethaee:BAAANQADCgUIBgAAAA==.',
Eu='Eurydices:BAAANQADCgYIBgAAAA==.',
Ev='Evangelión:BAAANQADCgUICgAAAA==.',
Ex='Exit:BAAANQAECgMIAwAAAA==.',
Ey='Eyks:BAAANQAECgEIAQAAAA==.',
Fa='Faelithndrel:BAAANQAECgUICgAAAA==.Farmette:BAAANQAECgIIAgAAAA==.',
Fe='Felbeard:BAACNQAFFIEIAAMCAAQJ3hCZAgALAQACAAMJsxWZAgALAQAFAAIJFwfbAwCoAAA1AAQKgR4AAwIACQmnI6YDADsDAAIACAmGI6YDADsDAAUABwlUFWMJACwCAAAA.Feleâ:BAAANQADCgYIDQAAAA==.Ferreday:BAAANQAECgIIAgAAAA==.',
Fi='Firemystic:BAAANQADCgUIBQAAAA==.',
Fl='Flamereaper:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Fleakertwo:BAABNQAECoEYAAIGAAkJXQzsCAA8AgAGAAkJXQzsCAA8AgAAAA==.Floopzii:BAAANQAECgQIBwAAAA==.Flói:BAAANQADCggIDwAAAA==.',
Fr='Friedrib:BAABNQAECoEXAAMHAAkJGx6nDQDGAgAHAAgJHh6nDQDGAgAIAAMJ3hJQHwDZAAAAAA==.',
Fu='Fulldipey:BAAANQAECgUIBgAAAA==.Furrythot:BAABNQAECoEYAAIJAAkJIx+dBQA5AwAJAAkJIx+dBQA5AwAAAA==.Fuzeewuzee:BAEANQADCgIIAgABNQAECggIEAABAAAAAA==.',
Ga='Galise:BAAANQADCggIDgAAAA==.Galynnia:BAAANQADCgYIBgAAAA==.Gangstafrost:BAAANQADCgMIBQAAAA==.',
Gd='Gduff:BAAANQAECgEIAQAAAA==.',
Ge='Genaveive:BAAANQAECgcIEAAAAA==.',
Gg='Ggodetan:BAAANQADCgYIBgAAAA==.',
Gi='Gigglespit:BAAANQAECgQIBAAAAA==.Gildeath:BAAANQAECgcICAAAAA==.Gimlie:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.Gimmix:BAAANQAECgYICwAAAA==.',
Gl='Glindora:BAAANQADCgcIDwAAAA==.',
Go='Gobbylynn:BAAANQAECggIEwABNQAFFAIIAgABAAAAAA==.Gooptoob:BAAANQAECgQIBAAAAA==.Goosetits:BAAANQABCgIIAgAAAA==.',
Gr='Grogosh:BAAANQADCgYIBgAAAA==.',
Gu='Guaplord:BAAANQADCgMIAwAAAA==.',
Ha='Hagran:BAAANQADCgMIAwAAAA==.Haint:BAAANQAECgQIBwAAAA==.Halzak:BAAANQAECgEIAQAAAA==.Harambeisbae:BAAANQAECgMIAgAAAA==.Hawdazz:BAAANQADCgQIBAABNQADCgQIBgABAAAAAA==.',
He='Healah:BAAANQADCgcIBwABNQAECgYIDQABAAAAAA==.Hegotthedrip:BAABNQAECoEVAAQFAAkJ4RvCBgBnAgAFAAcJrx3CBgBnAgACAAQJtRjdRAA5AQAKAAEJXwcEEgBMAAAAAA==.Helios:BAAANQAECggIDAABNQABCgYIBgABAAAAAA==.Hellaquin:BAABNQAECoEXAAILAAkJPR8cAwBsAwALAAkJPR8cAwBsAwAAAA==.Hellomotojr:BAAANQAECgQIBQAAAA==.',
Hi='Hijackx:BAAANQAECgcIDAAAAQ==.Hinotama:BAAANQADCgYIBgAAAA==.',
Ho='Holdne:BAAANQAECgYIBgAAAA==.Holycoward:BAAANQADCgYIDAAAAA==.Holynova:BAAANQAECgMIAwAAAA==.Holypoker:BAAANQADCggICAAAAA==.Holysuave:BAAANQADCggICgAAAA==.Horu:BAAANQADCggIFAAAAA==.Horux:BAAANQADCgUIBQAAAA==.',
Hr='Hrothgar:BAAANQAECggIBgAAAA==.',
Hy='Hyhu:BAAANQAECgcIDAAAAA==.Hymlok:BAAANQAECgQIBwAAAA==.Hyperion:BAAANQAECgcICwAAAA==.Hyuga:BAAANQADCggIFQAAAA==.',
Ic='Iccarium:BAAANQAECgYIBgAAAA==.Icexjh:BAAANQAECgIIAgAAAA==.Icritmypañts:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.',
Ig='Ignatowski:BAAANQADCgYIBgAAAA==.Igorongon:BAAANQAECgYICwAAAA==.',
Ii='Iindulgelag:BAAANQADCgcIBwAAAA==.',
Ik='Ikhawe:BAAANQADCgYICAAAAA==.',
In='Inebrious:BAAANQADCggIEwAAAA==.',
Io='Ionna:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
Ir='Ironmann:BAAANQAECgUICQAAAA==.',
It='Itsmäam:BAAANQAECgUIBwAAAA==.',
Ja='Jabamental:BAABNQAECoEXAAIMAAgJaCR0BABLAwAMAAgJaCR0BABLAwAAAA==.Jaded:BAAANQADCggIEgAAAA==.Jadefonda:BAAANQADCgcIFQAAAA==.Jamx:BAAANQAECgYICgABNQAECgkJGQANAJEgAA==.Jamy:BAABNQAECoEZAAMNAAkJkSDICwDcAgANAAgJbCPICwDcAgAOAAYJrBRpGgCWAQAAAA==.Jandria:BAAANQAECgYICAAAAA==.Janos:BAAANQAECggIDgAAAA==.Jashin:BAAANQAECgcIDAAAAA==.Jawbreaker:BAAANQADCgQIBQAAAA==.Jaycifer:BAAANQAECgcIEwAAAA==.',
Je='Jerm:BAAANQAECgMIAwAAAA==.Jerzyp:BAAANQADCgEIAQAAAA==.Jessia:BAAANQAECgMIAwAAAA==.',
Jo='Joobi:BAAANQAECgQIBQAAAA==.Jorrethoi:BAAANQAECgIIAgAAAA==.',
Ju='Jurble:BAAANQAECgcIDAAAAA==.Juurou:BAAANQADCggIEQAAAA==.',
['Jä']='Jäydedfäith:BAAANQADCgYIDAAAAA==.',
Ka='Kabbu:BAAANQAECggICAAAAA==.Kaimed:BAAANQAECgYICwAAAA==.Kamton:BAAANQADCgUIBQAAAA==.Kardrig:BAAANQADCgcIEwAAAA==.Katwoman:BAAANQAECgYICgAAAA==.Kaylana:BAAANQADCgYIDgAAAA==.',
Kd='Kdzee:BAAANQADCggIDgAAAA==.',
Kh='Khalezzi:BAAANQAFFAEIAQAAAA==.Khonos:BAAANQAECgUIBgAAAA==.',
Ki='Killercold:BAAANQADCgUIBQAAAA==.Kimoora:BAAANQADCgQIBQAAAA==.Kirarawr:BAAANQABCgIIAgAAAA==.Kisstrosity:BAABNQAECoEaAAINAAkJlyEKBQBEAwANAAkJlyEKBQBEAwAAAA==.',
Kl='Kloosterhuis:BAAANQAECgQIBwAAAA==.',
Ko='Kodoseeker:BAAANQAECgYICgAAAA==.Kovos:BAAANQADCgQIBQAAAA==.',
Kr='Krean:BAAANQAECgQIBAAAAA==.Krisali:BAAANQADCgIIAgAAAA==.',
Ku='Kunardh:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Kunarr:BAAANQAECgYICwAAAA==.',
Ky='Kylerichards:BAAANQAECgIIAgAAAA==.Kyohunt:BAAANQAECgcIDAAAAA==.Kyoshock:BAAANQAECgYICAABNQAECgcIDAABAAAAAA==.',
La='Ladonda:BAAANQADCgYICAAAAA==.Lanius:BAAANQABCgQIBQAAAA==.Lanyx:BAAANQADCgUIBgAAAA==.Lareina:BAABNQAECoEYAAIPAAkJVhYSEgCfAgAPAAkJVhYSEgCfAgAAAA==.Larinara:BAAANQADCgEIAQAAAA==.Laziness:BAAANQAECgYIBgABNQADCgIIAwABAAAAAA==.',
Le='Lemonhope:BAAANQAECgIIBQAAAA==.',
Li='Lilmerlin:BAAANQADCgQIBAAAAA==.Linchknight:BAAANQADCggIFQAAAA==.Littlefudger:BAAANQABCgIIAgAAAA==.Livola:BAAANQAECgQIBgAAAA==.',
Lo='Locknik:BAAANQADCgYIDwAAAA==.Lokkahn:BAAANQADCggIFQAAAA==.',
Lu='Lunarsol:BAAANQAECgYICgAAAA==.',
Ly='Lyanna:BAAANQADCgcICQABNQAECgYICwABAAAAAA==.',
['Lä']='Lätêx:BAAANQAECggIEwAAAA==.',
Ma='Magicmeatxxl:BAAANQAECgUIBwAAAA==.Magusgobrr:BAAANQAECgcIDAAAAA==.Mahawker:BAAANQADCgYIBwAAAA==.Mahfaty:BAAANQADCgYIBgAAAA==.Malüs:BAAANQADCgUIBQAAAA==.Marideous:BAAANQADCgYICwAAAA==.Mark:BAAANQAECgEIAQABNQAECgcICgABAAAAAA==.Marth:BAAANQAECgQIBAAAAA==.Mashem:BAAANQAECgcIDwAAAA==.Mathias:BAAANQADCgcIDAAAAA==.Mattpriest:BAABNQAECoEYAAMQAAkJwSCFBAA5AwAQAAkJTCCFBAA5AwARAAQJVRmlCQD+AAAAAA==.Maxverclappn:BAAANQADCgcIDAAAAA==.Maxvertrappn:BAAANQAECgYICwAAAA==.',
Mc='Mcsloppy:BAAANQADCggICAAAAA==.',
Me='Meshkuhrib:BAAANQADCgUIBQABNQAECgkJFwAHABseAA==.Methicillin:BAAANQADCgYIBgAAAA==.Methir:BAAANQADCgUICQAAAA==.',
Mi='Mightythor:BAAANQADCggIDgAAAA==.Milkedmoose:BAAANQAECgMIAwAAAA==.Milkers:BAAANQAECggIEgAAAA==.Minimoose:BAAANQAECgMIAwAAAA==.Misclick:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Mo='Moona:BAAANQAECgQIBQAAAA==.Moonberry:BAAANQAECgcIDwAAAA==.Moonlock:BAAANQADCgUIBgAAAA==.Motomotoo:BAAANQAECgEIAQAAAA==.',
Mu='Muffinfeliz:BAAANQAECgIIAgAAAA==.',
My='Myriad:BAAANQAECgQIBAABNQAFFAQIBQASAI4bAA==.Mythundreran:BAAANQADCgcIDwAAAA==.',
Na='Namdari:BAAANQAECgMIAwAAAA==.Nanasquirts:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Nazzan:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.',
Ni='Nightmàre:BAAANQAECgEIAQAAAA==.Nightshade:BAAANQADCgUIBQABNQAECgkJFwALAD0fAA==.Nightstride:BAAANQADCgMIAQAAAA==.Nikkô:BAAANQABCgQICAAAAA==.Nirra:BAAANQADCggIEwAAAA==.Niso:BAAANQADCgQIBAAAAA==.',
No='Noatt:BAAANQADCgMIAwAAAA==.Nokona:BAAANQADCgEIAQAAAA==.Novapal:BAAANQAECgMIBQAAAA==.Novura:BAAANQADCgYIBgAAAA==.',
Nu='Numnumzz:BAAANQABCgQIBgAAAA==.',
Oc='Ochnauq:BAAANQAECgUICgABNQAECgkJGAATAP4MAA==.',
Om='Omarid:BAAANQADCgIIBAAAAA==.Omfgpie:BAAANQAECgYICQAAAA==.',
Oo='Ooiskan:BAAANQADCgIIAgAAAA==.',
Or='Orcall:BAAANQAECgUIBgAAAA==.',
Ov='Overcharged:BAAANQADCgQIBAAAAA==.',
Ow='Owencaddell:BAAANQADCgYICwAAAA==.',
Pa='Pada:BAAANQAECgUIBgAAAA==.Pakku:BAABNQAECoEYAAIUAAkJ8x77AwAiAwAUAAkJ8x77AwAiAwAAAA==.Paladaine:BAAANQADCgUICgAAAA==.Pallix:BAAANQAECgYICwABNQAECgcIEwABAAAAAA==.Palpacino:BAAANQADCggIDQABNQAECgUIBwABAAAAAA==.Palytivecare:BAAANQADCgIIAwAAAA==.Papajaja:BAAANQAECgYICAAAAA==.Papal:BAAANQADCgEIAQAAAA==.Paramôre:BAAANQAECggIAwAAAA==.',
Pe='Peace:BAAANQAECgcICgAAAA==.Peachpanther:BAAANQADCgcIBgAAAA==.Pegmianis:BAAANQAECgEIAQAAAA==.',
Ph='Phatsword:BAAANQAECgIIAgAAAA==.Phigon:BAAANQAECgMIAwAAAA==.',
Pi='Pixelbaddy:BAAANQADCgcIDwAAAA==.',
Pl='Plumbus:BAAANQADCgUIBQAAAA==.',
Po='Polygrip:BAAANQAECgIIAgAAAA==.Popechaz:BAAANQADCgYIDAAAAA==.',
Pr='Praxtintar:BAAANQAECgUIBQAAAA==.',
Ps='Psychonaut:BAAANQAECgUIBQABNQAECgUIBwABAAAAAA==.',
Pu='Pure:BAAANQAECgYIDQAAAA==.Purman:BAAANQADCgIIAgAAAA==.',
Py='Pyrine:BAAANQAECgEIAQAAAA==.',
Qu='Quancho:BAABNQAECoEYAAITAAkJ/gxvBQDqAQATAAkJ/gxvBQDqAQAAAA==.',
Qw='Qwade:BAAANQAECgEIAQAAAA==.',
Ra='Ragran:BAAANQADCggICwAAAA==.Rakaman:BAAANQAECgQIBAAAAA==.Ramza:BAABNQAECoEXAAIEAAkJ5CUoAQDfAwAEAAkJ5CUoAQDfAwAAAA==.Ranbou:BAABNQAECoEYAAIVAAkJyxuEHgDfAgAVAAkJyxuEHgDfAgAAAA==.Randor:BAAANQABCgQIBgAAAA==.Rashka:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Ratatasquer:BAAANQAECgMIAwAAAA==.Rattleballs:BAAANQAECgQIBAABNQAECgIIBQABAAAAAA==.',
Re='Reegss:BAAANQADCgEIAQAAAA==.Regsia:BAAANQAECgEIAQAAAA==.Repens:BAAANQAECgMIAwAAAA==.Restosterone:BAAANQAECgMIAwAAAA==.Ret:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Retbeanznrce:BAAANQADCgIIAgAAAA==.Retful:BAAANQADCgUIBQABNQAECgkJFwADACcjAA==.Revo:BAAANQADCgYIBgABNQAECggIEQABAAAAAA==.',
Rh='Rhaid:BAAANQAECgQIBwAAAA==.Rhordrick:BAAANQAECgIIAwAAAA==.',
Ri='Rizzgrizzly:BAAANQADCgIIAgAAAA==.Rizzurrect:BAAANQADCgIIAgAAAA==.',
Rn='Rng:BAAANQADCgIIAgAAAA==.',
Ro='Roquefort:BAAANQADCgUIBgAAAA==.Roscoedshamn:BAAANQADCgYICQAAAA==.Rowdi:BAAANQADCggIDAAAAA==.',
Ru='Rukarm:BAAANQADCgcIFQAAAA==.Runawaynow:BAACNQAFFIEIAAIMAAYJZQ2wAAD+AQAMAAYJZQ2wAAD+AQA1AAQKgRoAAgwACQn1H0AFADkDAAwACQn1H0AFADkDAAAA.Runelife:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.',
Sa='Saelaissamlt:BAAANQADCgQIBAAAAA==.Samdeathfoot:BAAANQAECgIIAgAAAA==.Samsara:BAAANQABCgMIAwAAAA==.Sartok:BAAANQADCgcIEQAAAA==.',
Sc='Scottnails:BAAANQADCgIIAgAAAA==.',
Se='Seyuri:BAAANQAECgcIDAAAAA==.Seán:BAAANQAECgMIAwAAAA==.',
Sh='Shadowar:BAAANQADCggIFQAAAA==.Shadowbell:BAAANQAECgQIBwAAAA==.Shadowgale:BAAANQADCggIFQAAAA==.Shamanramen:BAAANQABCgQIBAAAAA==.Shantari:BAAANQADCgQIBQAAAA==.Shayrpd:BAAANQADCggICQAAAA==.Shøckybalboa:BAAANQAECgMIBAAAAA==.',
Si='Sinnmage:BAAANQABCgMIAwAAAA==.Sinnshifts:BAAANQADCggIFAAAAA==.',
Sk='Skhorn:BAAANQAECgQIBwAAAA==.Skuûub:BAAANQADCgUIBQAAAA==.',
Sl='Slowone:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Slãyer:BAAANQAECgIIAgAAAA==.',
Sm='Smokedrib:BAAANQADCgMIAwABNQAECgkJFwAHABseAA==.',
So='Sometymz:BAAANQAECgYICQAAAA==.',
Sp='Spareathot:BAAANQAECgYIDgAAAA==.Speedspanker:BAAANQAECgMIAwAAAA==.Spirulina:BAAANQADCgIIAgAAAA==.Splashsplash:BAAANQADCgQIBQAAAA==.',
St='Staar:BAAANQAECgIIAwAAAA==.Starflames:BAAANQADCgQIBAAAAA==.Stellarèé:BAABNQAECoEYAAMCAAkJbSLkDACoAgACAAcJxSHkDACoAgAFAAYJMR6UCwAFAgAAAA==.Stiliar:BAAANQAECgIIAgAAAA==.Strongdroid:BAAANQADCgcICgAAAA==.Strángè:BAAANQAECgMIBwAAAA==.Stêlla:BAAANQADCgQIBAAAAA==.',
Su='Substrate:BAAANQAECgMIAwAAAA==.Sugarteets:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Suramo:BAAANQAECgYICgAAAA==.',
Sv='Svaval:BAAANQAECgcIDgAAAA==.',
Sy='Syles:BAAANQADCgUIBgABNQAECgMIAwABAAAAAA==.Syphon:BAAANQAECgYICgAAAA==.',
Ta='Tamedurmom:BAAANQAECgUIBwAAAA==.Tarekk:BAAANQAECgUIBwAAAA==.Tarewreck:BAAANQADCgUIBQAAAA==.Tariqpapi:BAAANQAECgYICwAAAA==.',
Te='Tehcountess:BAAANQAECgcIDAAAAA==.',
Th='Tharos:BAAANQADCggIFQAAAA==.Thebeerwiz:BAAANQADCgQIBgAAAA==.Thecarebear:BAAANQAECgQIBAAAAA==.Thelianne:BAAANQAECgIIAgAAAA==.Thelmina:BAAANQADCgQICAAAAA==.Thermidor:BAAANQAECgMIAwAAAA==.Thorps:BAAANQAECgcICQAAAA==.Thragg:BAAANQADCgEIAQAAAA==.Thurstee:BAAANQAECgYICAAAAA==.',
Ti='Tibian:BAAANQAECgcIDAAAAA==.Tigerpalm:BAAANQAECgIIAwAAAA==.Tilexer:BAAANQADCgMIAwAAAA==.Tinypreest:BAAANQADCgYIBgAAAA==.Tinyshocker:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
To='Totemlyfoxy:BAAANQAECgEIAQAAAA==.Touchedd:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.',
Tr='Treesdk:BAAANQAECgYICwAAAA==.Trugs:BAAANQAECgUIBgAAAA==.',
Tu='Tulsmi:BAAANQADCgcIBwAAAA==.Tuntunvergun:BAAANQAECgcIDwAAAA==.',
Tw='Twelvetacos:BAAANQAECgcIDwAAAA==.',
Ty='Tyralde:BAAANQAECgQICAAAAA==.',
Ud='Udenlo:BAAANQADCggIFAAAAA==.',
Um='Umbraheart:BAAANQADCgYIEAAAAA==.',
Un='Unsub:BAAANQADCgEIAQABNQAECggIEgABAAAAAA==.',
Us='Usui:BAAANQADCgEIAQAAAA==.',
Va='Valei:BAAANQAECgQIBAAAAA==.Valvadime:BAAANQAECgEIAgAAAA==.Vantoes:BAAANQAECgMIBQAAAA==.',
Ve='Vecidus:BAAANQAECgEIAQAAAA==.Velassi:BAAANQAECgUICQAAAA==.Veldora:BAAANQADCgUIBQAAAA==.Velouriuum:BAAANQADCgQIBAAAAA==.Vetrandus:BAAANQADCgYIBgAAAA==.',
Vh='Vhioth:BAAANQADCgQIBgAAAA==.',
Vi='Vielli:BAAANQAECgMIAwAAAA==.Vintari:BAAANQAECgEIAQAAAA==.Vivvyquinn:BAAANQADCgMIAwAAAA==.',
Vo='Volorren:BAAANQAECgEIAQAAAA==.Volzu:BAAANQAECgYICgAAAA==.',
Wa='Walon:BAAANQADCgMIAwAAAA==.Warwickdavis:BAAANQADCgYIBgABNQADCgYIDgABAAAAAA==.Wazerk:BAAANQADCgcIBwAAAA==.',
We='Weirdchampx:BAAANQAECgEIAQABNQAECgMIBQABAAAAAA==.',
Wh='Whely:BAEBNQAECoEXAAIWAAkJdyKUAACXAwAWAAkJdyKUAACXAwAAAA==.Whitegoodman:BAAANQADCggICAAAAA==.Whitegrlswag:BAAANQAECgIIAgAAAA==.',
Wi='Wilcoxx:BAAANQAECggIEwAAAA==.Wilcozz:BAAANQADCgQIBAABNQAECggIEwABAAAAAA==.Wipeout:BAAANQADCgYIEwAAAA==.Wirecutter:BAAANQADCgcICwAAAA==.Wixjones:BAAANQADCgUIBQABNQAECgkJGQANAJEgAA==.Wizurd:BAAANQAECgYICgAAAA==.',
Wo='Wolfcult:BAAANQAECgYICgAAAA==.Wompstomper:BAAANQADCgEIAQAAAA==.Worcklock:BAAANQAFFAEIAQABNQAFFAQICAACAN4QAA==.',
Wr='Wrapwrap:BAAANQAECgQIBwAAAA==.Wratheon:BAAANQADCgEIAQAAAA==.',
['Wì']='Wìxÿ:BAAANQADCgcIBwAAAA==.',
['Wî']='Wîxx:BAAANQAECggIEAAAAA==.Wîxÿ:BAAANQAECgUIBgAAAA==.',
Xe='Xestsalb:BAEANQAECggIAQAAAA==.',
Yo='Yourlock:BAAANQAECgUIBQAAAA==.',
Yu='Yuseolha:BAAANQADCggIDwAAAA==.',
Za='Zac:BAAANQADCggIFAAAAA==.Zacheeus:BAAANQAECgYICwAAAA==.Zaco:BAAANQADCgYIDAABNQADCggIFAABAAAAAA==.Zagran:BAAANQADCgQIBQAAAA==.Zak:BAAANQADCggIDwABNQADCggIFAABAAAAAA==.Zantidious:BAAANQADCgcIDgAAAA==.Zardragon:BAABNQAECoEYAAISAAkJkyVTAADmAwASAAkJkyVTAADmAwAAAA==.',
Ze='Zelenä:BAAANQAECgQIBAAAAA==.Zelethor:BAABNQAECoEXAAMXAAkJ6CGbAAA0AwAXAAgJjiSbAAA0AwAVAAEJtww97gBIAAAAAA==.Zelithor:BAAANQAECgYICwAAAA==.Zeryn:BAAANQABCgIIAgAAAA==.',
Zy='Zynalia:BAAANQADCgIIAgAAAA==.',
['Àr']='Àrcaneheart:BAAANQAECgQIBQAAAA==.',
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
