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

local lookup = {'Shaman-Elemental','Unknown-Unknown','Mage-Arcane','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Warrior-Arms','Rogue-Outlaw','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Druid-Feral','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Paladin-Retribution','Mage-Fire','Hunter-BeastMastery','Evoker-Preservation',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Accoli:BAAANQAECgUIBQAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Al='Aliasx:BAAANQADCgUICQAAAA==.Allarus:BAAANQADCgcICQAAAA==.Alotofsin:BAAANQADCgYIBgAAAA==.Alphadog:BAAANQAFFAEIAQAAAA==.Alwaysunny:BAAANQADCgYIDAAAAA==.',
Am='Amahlfarouk:BAAANQAECgIIAgAAAA==.Aminatou:BAAANQAECgQIBgAAAA==.',
Ar='Ariaddne:BAAANQAECgQICAAAAA==.Artemîs:BAAANQADCgUICgAAAA==.',
As='Ashaelra:BAAANQAECgUIBQAAAA==.Asolitha:BAAANQADCgUIBQAAAA==.',
Au='Augonly:BAAANQAECgcIDQAAAA==.Augy:BAAANQAECgYIDAAAAA==.',
Ba='Barhead:BAAANQADCgQIBwAAAA==.',
Bb='Bbldrizzy:BAABNQAECoEeAAIBAAkJayQSBACqAwABAAkJayQSBACqAwAAAA==.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECgcIEgACAAAAAA==.Beastlièduke:BAAANQADCgIIAgABNQAECgcIEgACAAAAAA==.Belinda:BAAANQADCgIIAgAAAA==.',
Bi='Bighunt:BAAANQADCggICAAAAA==.Bijju:BAAANQAECggIBgAAAA==.Binggus:BAAANQAECgcIDAAAAA==.',
Bl='Blabbybootze:BAAANQAECgQIBAAAAA==.Bladelight:BAAANQADCgcIDAAAAA==.Blightfangs:BAAANQAECgEIAQAAAA==.',
Bo='Bodakye:BAAANQAECgQIBwAAAA==.Boneplague:BAAANQADCgQIBAAAAA==.Boow:BAAANQADCgYIEgAAAA==.',
Br='Bracalina:BAAANQADCgcICQAAAA==.Broggy:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Brorgy:BAAANQAECgUICQAAAA==.Brovahkin:BAAANQABCgUICAAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Buzzbuzz:BAAANQAECgMIAwAAAA==.',
Ca='Caeruleus:BAAANQABCgYIBgAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAAANQAECgYICQAAAA==.Chapelgnome:BAAANQADCgUIBQABNQAECgUICQACAAAAAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAAANQAECgMIBgAAAA==.Chickenslop:BAAANQADCggIFQAAAA==.Chiptime:BAAANQAECgQICAAAAA==.Chri:BAAANQAECgQIBAAAAA==.Chzburger:BAAANQABCgIIBAAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAECgkJFwADAPYfAA==.Cormogh:BAAANQADCggICwAAAA==.Cowhealer:BAABNQAECoEZAAMEAAkJYh56FgCgAgAEAAgJdB16FgCgAgAFAAMJGAoDLgCyAAAAAA==.',
Cr='Craeftig:BAAANQAECgQIBQAAAA==.Craeftigdk:BAAANQAECgMIAwABNQAECgQIBQACAAAAAA==.Craeftigtwo:BAAANQADCggICAABNQAECgQIBQACAAAAAA==.Crepitus:BAAANQAECgQIBwAAAA==.Crusabull:BAAANQADCgUIBQAAAA==.Cræftig:BAAANQADCgQIBAABNQAECgQIBQACAAAAAA==.',
Cu='Cuddlseraph:BAAANQAECgQIBgAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQADCgcICQACAAAAAA==.',
Da='Dafirenze:BAAANQADCggIDwAAAA==.Daftxshade:BAAANQADCgcICAAAAA==.Darkbeef:BAAANQAECgQIBgAAAA==.Darthsyde:BAAANQABCgQIBAAAAA==.',
De='Deadergriff:BAAANQAECgQIBgAAAA==.Deadicated:BAAANQAECgEIAQAAAA==.Deadinsíde:BAAANQAECggICAAAAA==.Deeznutzs:BAAANQADCgEIAQAAAA==.Delan:BAAANQAECgYIBwAAAA==.Demolishonn:BAAANQADCggIDQAAAA==.Desunaito:BAABNQAECoEfAAIGAAkJzSJOAwBqAwAGAAkJzSJOAwBqAwAAAA==.Dexter:BAAANQAECgQIBQAAAA==.',
Dh='Dhzilong:BAAANQAECggIBAABNQAFFAMIBQAHAEEQAA==.',
Di='Diddlefiddle:BAAANQADCgIIAgAAAA==.Dioji:BAAANQAECggIBgAAAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docadoodle:BAAANQADCgcIBwABNQAECgcIEwACAAAAAA==.Docarcanis:BAAANQADCgcIBwABNQAECgcIEwACAAAAAA==.Docwyle:BAAANQAECgcIEwAAAA==.Doozey:BAAANQABCgYIBgAAAA==.',
Dr='Dracmary:BAAANQADCgUIBQAAAA==.Dracnogard:BAAANQADCgYICwAAAA==.Dracowulf:BAAANQAECgIIAgAAAA==.Dragonx:BAAANQAECgQIBwAAAA==.Drakowolf:BAAANQAECgEIAQAAAA==.Dreadful:BAAANQAECgYIEQAAAA==.Dreorge:BAAANQAECggIDQAAAA==.Drewceratops:BAAANQAECgUICwAAAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAAANQAECgcICwAAAA==.Drogô:BAAANQADCgYICgAAAA==.Dromgar:BAAANQAECgcIAgAAAA==.Dromkyr:BAAANQAECgYICQAAAA==.Drossiechan:BAAANQAECgcIDgAAAA==.',
Du='Duellipa:BAAANQAECgQICQABNQAECgUICQACAAAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.Dywanw:BAAANQABCgYIBgAAAA==.',
Ed='Edward:BAAANQAECggIBwAAAA==.',
Ef='Effloria:BAAANQAECgYICQAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.',
El='Elauvia:BAAANQADCgUIBQAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredh:BAAANQADCgQIBAAAAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwAAAA==.Encorep:BAAANQAECgQIBAAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Ev='Eviscerated:BAAANQAECgQIBAAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQADCgYIBgAAAA==.Fallen:BAAANQAECgIIAgAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgACAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgACAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fi='Finaliter:BAAANQAECgYIEQAAAA==.',
Fl='Flamingdrago:BAAANQADCgQIBAAAAA==.Flirtyflurry:BAAANQAECgQIBgAAAA==.',
Fo='Fox:BAABNQAECoEfAAIIAAkJYSHhAABrAwAIAAkJYSHhAABrAwAAAA==.',
Fr='Fremder:BAAANQAECgUIBgAAAA==.Froggy:BAAANQAECgUICAAAAA==.Frogred:BAAANQADCgQIBAABNQAECgUICAACAAAAAA==.',
Fu='Funeral:BAACNQAFFIELAAMJAAUJexUrAQAQAQAJAAMJQRgrAQAQAQAKAAMJ1A9VCADqAAA1AAQKgR0ABAkACQnnJaQAAKoDAAkACQnpJKQAAKoDAAoABglPJLEgAGsCAAsAAQnPDLsdADUAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQADCgEIAQAAAA==.',
Fy='Fyjhrt:BAAANQAECgYIBgAAAA==.',
Ga='Gallory:BAAANQAECggIBgAAAA==.Gayanall:BAAANQADCgMIAwAAAA==.',
Gd='Gdk:BAAANQADCgcICAABNQAECgYIDAACAAAAAA==.Gdkmage:BAAANQAECgQIBQABNQAECgYIDAACAAAAAA==.Gdkman:BAAANQAECgYIDAAAAA==.Gdknotlock:BAAANQADCgQIBgABNQAECgYIDAACAAAAAA==.',
Ge='Geoprince:BAAANQADCgYIDAAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghaldrin:BAAANQABCggIDAAAAA==.Ghoulfriend:BAAANQADCgUIBgAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAAANQAECgUIBQABNQAECgkJHgABAGskAA==.Githrogathan:BAAANQAECgQIBgAAAA==.',
Go='Gokudin:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgcIEQACAAAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Haraldsson:BAAANQADCggICAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Hasaro:BAAANQAECgcIEwAAAA==.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAAANQAECgIIAgAAAA==.Havøckblaze:BAAANQADCgIIAgAAAA==.',
He='Healmachine:BAAANQADCggIFgAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.',
Ho='Holyfarts:BAAANQAECggIEwAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Humanform:BAAANQADCgUIBQAAAA==.Hunbroll:BAAANQADCgYIBgABNQAECgkJHgADADceAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCgYIEgAAAA==.',
Hx='Hx:BAAANQADCgYIDAAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIDAAAAA==.',
['Hõ']='Hõnor:BAABNQAECoEaAAMHAAkJHyDrEgAwAwAHAAkJPB/rEgAwAwAMAAUJsx8SCgDSAQAAAA==.',
Ig='Igriss:BAAANQAECgUICAAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.',
Im='Imonthegcd:BAAANQAECgYIBgABNQAECgkJGgAHAB8gAA==.',
In='Infinitepain:BAAANQAECgcIEQAAAA==.Innodk:BAAANQADCgUIBQAAAA==.',
Ir='Iridellis:BAAANQADCgcIBwABNQAECgYIEQACAAAAAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
Ja='Jahjahblinks:BAAANQADCgYIDgABNQAECgcIEQACAAAAAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAAANQAECgcIDQAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQAECgEIAQAAAA==.',
Jo='Joedingle:BAAANQAECgIIBAAAAA==.Joemomma:BAAANQADCgUIBQAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAAANQAECgYICgAAAA==.',
Jr='Jr:BAAANQADCggICAAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECggIFgANALcgAA==.Kaitokit:BAABNQAECoEaAAMOAAgJag2xMgCyAQAOAAcJWQ2xMgCyAQAPAAEJ4g3GhQAsAAAAAA==.Kalia:BAAANQADCgIIAgAAAA==.Kalyth:BAAANQAECgYIBwAAAA==.Kamera:BAAANQAECgYIDAAAAA==.Kandessa:BAAANQADCgEIAQAAAA==.Kaylah:BAAANQAECgQICQAAAA==.Kayllina:BAAANQAECgMIAwAAAA==.Kayotic:BAAANQADCgUIBQAAAA==.',
Ke='Kelmorphic:BAAANQAECgYICQAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAECgkJFwADAPYfAA==.',
Ko='Kosmas:BAAANQADCgQIBgAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgQIBAAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQADCgYIBgAAAA==.',
Ky='Kyarina:BAAANQABCggIDwAAAA==.',
['Kí']='Kíller:BAAANQAECgEIAQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Li='Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilymei:BAAANQADCgcICAAAAA==.Linissa:BAAANQAECgQIBgAAAA==.Littledude:BAAANQADCgYIBgAAAA==.Littlemorsel:BAAANQAECgYICQAAAA==.Livalifa:BAAANQAECgEIAQAAAA==.',
Lo='Lockenload:BAAANQAECgUIBwAAAA==.Lohhar:BAAANQADCggIDgAAAA==.Loser:BAAANQABCgQIBQAAAA==.',
Ls='Lselec:BAAANQAECgMIAwAAAA==.',
Lu='Lucens:BAAANQAECgUIBAAAAA==.Lurchdh:BAEANQADCgQIBAABNQAECgkJHQAQANoNAA==.Lurchmage:BAEANQAECggIDQABNQAECgkJHQAQANoNAA==.Lurchn:BAEBNQAECoEdAAMQAAkJ2g0YCACUAQAQAAgJig8YCACUAQADAAgJhAOxxQAtAQAAAA==.',
Ly='Lyricai:BAAANQAECgIIAgAAAA==.',
['Lï']='Lïght:BAAANQAECggICAABNQAECgkJGgAHAB8gAA==.',
Ma='Madjake:BAAANQADCggICAAAAA==.Maemae:BAAANQADCgYIBgAAAA==.Magallanes:BAAANQABCgIIAgAAAA==.Matas:BAAANQAECgEIAQAAAA==.Maylinfenora:BAAANQAECgQIBQAAAA==.Mazzikane:BAAANQADCgYIBgAAAA==.',
Me='Meowizenith:BAAANQADCgUIBQAAAA==.Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAAANQAECgcIDAAAAA==.',
Mi='Mikecoxwall:BAAANQADCgEIAQAAAA==.Misary:BAAANQADCgcIBwAAAA==.Mistake:BAAANQAECgMIAwAAAA==.',
Mo='Mogyar:BAABNQAECoEUAAIRAAcJtRJATQDBAQARAAcJtRJATQDBAQAAAA==.Moistybush:BAAANQAECgEIAQAAAA==.Moltalgol:BAAANQADCgYIBgAAAA==.Monkeli:BAAANQAECgQICAAAAA==.Moonsiand:BAAANQAECgQICQABNQAFFAEIAQACAAAAAA==.Moreldwiddle:BAAANQAECgIIAgAAAA==.Morgaia:BAAANQADCggIFQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAAANQADCgcIDAAAAA==.Mozzsticks:BAAANQADCgYICwAAAA==.',
Mx='Mx:BAAANQADCgYIBgAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgYIDAAAAA==.',
['Mó']='Mócha:BAAANQAECgIIAgAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.',
Ne='Nellaa:BAAANQAECgEIAQAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Neverborn:BAAANQAECgUIBwAAAA==.',
Ni='Nightrage:BAAANQADCgYIFQAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.Notmypally:BAAANQADCgQIBAABNQAECgUIEgACAAAAAA==.',
Nu='Nutellaqq:BAAANQAECgYIDQAAAA==.',
Ob='Obeseotter:BAAANQAECgYIEQAAAA==.',
Od='Od:BAAANQADCgUICgAAAA==.',
Ol='Oliviabenson:BAAANQAECgQIBAAAAA==.',
Ox='Oxsidius:BAAANQADCggICQAAAA==.',
Pa='Paldi:BAAANQAECgQIBAABNQAECgYIBgACAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Palulu:BAEANQAECgUIDAABNQAECgcIDwACAAAAAA==.Pariss:BAAANQADCgUIBQABNQAECggIBgACAAAAAA==.Paws:BAAANQAECgEIAQAAAA==.',
Pe='Peaky:BAAANQAECgQICwAAAA==.Perelia:BAAANQAECgEIAgAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAAANQABCgYIBAAAAA==.Pooche:BAAANQAECgIIAwAAAA==.',
Pp='Ppc:BAAANQAECgEIAQABNQAECgkJFwADAPYfAA==.',
Pr='Prezu:BAEANQAECgcIDwAAAA==.Prophofdoom:BAAANQAECgQICAAAAA==.Prõc:BAAANQADCggICAAAAA==.',
Pv='Pvc:BAABNQAECoEXAAMDAAkJ9h8hGwAsAwADAAkJ9h8hGwAsAwASAAEJmgCsBwArAAAAAA==.',
Ra='Raisedead:BAAANQADCgIIAgABNQADCggIDAACAAAAAA==.Rancord:BAAANQADCggICAAAAA==.Ratsmasher:BAAANQAECgIIAgAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Retrobution:BAAANQAECgQICAAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBwAAAA==.',
Ro='Roopall:BAAANQAECgYIBgAAAA==.',
Ry='Rynzu:BAAANQAECgIIAgAAAA==.Ryzen:BAAANQAECgYIBwAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAAANQAECgQIBwAAAA==.Sanshift:BAAANQADCgIIAgAAAA==.Satansimp:BAAANQADCggILQAAAA==.',
Sc='Schadnfreude:BAAANQAECgcIEgAAAA==.Schezmu:BAAANQADCgUIBQAAAA==.',
Se='Sean:BAAANQADCgQIBgAAAA==.Senorfiesta:BAAANQAECgMIAwAAAA==.Setazen:BAAANQADCgYIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shaee:BAAANQAECgQIBAAAAA==.Shamans:BAAANQADCgYICwAAAA==.Shaokhan:BAAANQADCgYIBgAAAA==.Shasta:BAAANQAECgcIEwAAAA==.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAAANQAECgcIEwAAAA==.Shyx:BAAANQAECgQIBQAAAA==.',
Si='Simplèjack:BAAANQAECgUIBwAAAA==.Sinamon:BAAANQADCgYIBgAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgUIDAACAAAAAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAAANQAECgMIBQAAAA==.',
Sm='Smirksfotm:BAAANQAECgUIBwABNQAECggICAACAAAAAA==.',
Sn='Snail:BAAANQAECgYIBgAAAA==.Sneakmanman:BAAANQADCgYICQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAAANQAECgQICQAAAA==.Soulglo:BAAANQADCgcIDQAAAA==.',
Sp='Sprayandpray:BAAANQAECgMIBAAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQADCgIIAgAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sunpali:BAAANQADCggIFwAAAA==.Susanno:BAAANQADCgUIBgAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQAECgEIAQAAAA==.',
Ta='Tacutacudark:BAAANQADCgYIFAAAAA==.Taintedbeef:BAAANQADCgEIAQABNQADCgUIBQACAAAAAA==.Talonflame:BAAANQAECgYIDAAAAA==.Talonted:BAAANQADCgIIAgAAAA==.Tansu:BAAANQADCgYICAAAAA==.Taupo:BAAANQADCgYIEAAAAA==.Taxidermy:BAAANQADCgYIBgAAAA==.',
Te='Telarinda:BAAANQADCgUIBQAAAA==.',
Th='Thicclich:BAAANQADCggIGQAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thisismeta:BAAANQAECgUICQAAAA==.Thorynwar:BAAANQAFFAEIAQABNQAECgkJHAAOAEwmAA==.Thorýn:BAABNQAECoEcAAIOAAkJTCYAAQDmAwAOAAkJTCYAAQDmAwAAAA==.Thórin:BAAANQAECgQIBwAAAA==.',
Ti='Tierax:BAAANQAECgcIDgAAAA==.Tipsy:BAAANQAECgYICQAAAA==.',
To='Tojì:BAAANQAECggICAABNQAECggICAACAAAAAA==.Tomfoolary:BAAANQABCgYIBgAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQADCgUICwAAAA==.Tot:BAAANQAECgYICgAAAA==.',
Tr='Tralleth:BAAANQAECgMIAwAAAA==.Traumatized:BAAANQADCgIIAgAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECgIIAwAAAA==.Twostroke:BAAANQAECgQIBAAAAA==.',
Ty='Tylopally:BAAANQAECgQICgAAAA==.Tyloremixdd:BAAANQADCgYIBwAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAECgkJGgAHAB8gAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgYIEAAAAA==.Underhorn:BAAANQADCgYIBgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgcIDQACAAAAAA==.Vaeelrundor:BAAANQAECgIIBAAAAA==.Valyr:BAAANQABCgYIBwAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQADCgYIBwAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedebone:BAAANQADCgYIBwAAAA==.Vedexd:BAABNQAECoEWAAITAAYJnQ50YQB5AQATAAYJnQ50YQB5AQAAAA==.Velarael:BAAANQAECgEIAQAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQADCgYIBgAAAA==.',
Vs='Vs:BAAANQAECggIDgAAAA==.',
Wa='Wachonaso:BAAANQAECggIEgAAAA==.Wastedsage:BAAANQAECgEIAQAAAA==.',
Wh='Whatuphuz:BAAANQADCgQICQAAAA==.Wheresmyjaw:BAAANQAECgcIDwAAAA==.',
Wi='Wildthree:BAAANQAECgIIAgAAAA==.Wilkieswar:BAAANQADCggICAABNQAECgQIDAACAAAAAA==.Willenda:BAAANQADCgYIDAAAAA==.',
Wu='Wuinn:BAABNQAECoEWAAIUAAkJvxP5CgCFAgAUAAkJvxP5CgCFAgAAAA==.',
Xa='Xakutioner:BAAANQAECgYICgAAAA==.Xaldiir:BAAANQAECgEIAQAAAA==.',
Xe='Xerexia:BAAANQAECgcIEQAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAAANQAECgUICwAAAA==.',
Yo='Yongyong:BAAANQAECgIIAgAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAAANQAECgUICAAAAA==.',
Za='Zalvianna:BAAANQADCggIFgAAAA==.Zarathoz:BAAANQABCgYIBgAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgACAAAAAA==.',
Ze='Zeonz:BAAANQAECgEIAQAAAA==.',
Zi='Zilongmage:BAAANQAECgUIBQABNQAFFAMIBQAHAEEQAA==.Zilongwar:BAACNQAFFIEFAAIHAAMJQRBNCgD2AAAHAAMJQRBNCgD2AAA1AAQKgRYAAgcACQnYH2MbAPMCAAcACQnYH2MbAPMCAAAA.',
Zo='Zonecw:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Zonedk:BAAANQAECgQIBgAAAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQADCgYIEAACAAAAAA==.',
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
