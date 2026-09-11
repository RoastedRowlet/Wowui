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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Mage-Frost','DeathKnight-Unholy',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Accoli:BAAANQAECgQIBAAAAA==.Acslater:BAAANQADCgQIBAAAAA==.',
Al='Aliasx:BAAANQADCgUICQAAAA==.Allarus:BAAANQADCgcIBwAAAA==.Alotofsin:BAAANQADCgYIBgAAAA==.Alphadog:BAAANQAECgQICAAAAA==.Alwaysunny:BAAANQADCgUIBgAAAA==.',
Am='Amahlfarouk:BAAANQAECgIIAgAAAA==.Aminatou:BAAANQAECgIIAgAAAA==.',
Ar='Ariaddne:BAAANQAECgQIBAAAAA==.Artemîs:BAAANQADCgQIBQAAAA==.',
As='Ashaelra:BAAANQADCgUICQAAAA==.',
Au='Augonly:BAAANQAECgUICwAAAA==.Augy:BAAANQAECgUIBgAAAA==.',
Ba='Barhead:BAAANQADCgQIBwAAAA==.',
Bb='Bbldrizzy:BAAANQAFFAEIAgAAAA==.',
Be='Beastlieduke:BAAANQADCgYIDAABNQAECgYICwABAAAAAA==.Beastlièduke:BAAANQADCgIIAgABNQAECgYICwABAAAAAA==.',
Bi='Binggus:BAAANQAECgQIBAAAAA==.',
Bl='Blabbybootze:BAAANQADCgQIBAAAAA==.Bladelight:BAAANQADCgcIDAAAAA==.Blightfangs:BAAANQAECgEIAQAAAA==.',
Bo='Bodakye:BAAANQAECgMIAwAAAA==.Boow:BAAANQADCgYIBgAAAA==.',
Br='Bracalina:BAAANQADCgUIBQAAAA==.Broggy:BAAANQADCgEIAQABNQADCggIFwABAAAAAA==.Brorgy:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Brovahkin:BAAANQABCgUICAAAAA==.',
Bu='Bubbapal:BAAANQADCgUIBwAAAA==.Buzzbuzz:BAAANQAECgEIAQAAAA==.',
Ca='Caeruleus:BAAANQABCgYIBgAAAA==.Captyn:BAAANQABCgQIAwAAAA==.Catbum:BAAANQADCgIIAwAAAA==.Caylea:BAAANQADCggICAAAAA==.',
Ch='Chaosraven:BAAANQAECgMIAwAAAA==.Chapelgnome:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Charlyne:BAAANQABCgMIAwAAAA==.Chewthymight:BAAANQAECgIIAwAAAA==.Chickenslop:BAAANQADCggIFQAAAA==.Chiptime:BAAANQAECgQIBAAAAA==.Chri:BAAANQADCgcICQAAAA==.Chzburger:BAAANQABCgIIBAAAAA==.',
Co='Cocoon:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.Cormogh:BAAANQADCggICwAAAA==.Cowhealer:BAAANQAECgcIDwAAAA==.',
Cr='Craeftig:BAAANQAECgEIAQAAAA==.Craeftigdk:BAAANQADCggIGwABNQAECgEIAQABAAAAAA==.Crepitus:BAAANQAECgEIAQAAAA==.Crusabull:BAAANQADCgUIBQAAAA==.Cræftig:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Cu='Cuddlseraph:BAAANQAECgIIAgAAAA==.',
Cy='Cynnithice:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.',
Da='Dafirenze:BAAANQADCggIDAAAAA==.Daftxshade:BAAANQADCgcICAAAAA==.Darkbeef:BAAANQAECgIIAgAAAA==.',
De='Deadergriff:BAAANQAECgIIAgAAAA==.Deadicated:BAAANQADCgYIDQAAAA==.Delan:BAAANQAECgYIBQAAAA==.Demolishonn:BAAANQADCggIDQAAAA==.Desunaito:BAABNQAECoEYAAICAAkJaiLvAQBjAwACAAkJaiLvAQBjAwAAAA==.Dexter:BAAANQAECgIIAgAAAA==.',
Dh='Dhzilong:BAAANQAECggIBAABNQAFFAMIAwABAAAAAA==.',
Di='Dioji:BAAANQAECggIBgAAAA==.',
Dm='Dmeo:BAAANQADCgMIAwAAAA==.',
Do='Docarcanis:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.Docwyle:BAAANQAECgYIDAAAAA==.',
Dr='Dracnogard:BAAANQADCgYIDgAAAA==.Dracowulf:BAAANQAECgEIAQAAAA==.Dragonx:BAAANQADCggIFQAAAA==.Drakowolf:BAAANQAECgEIAQAAAA==.Dreadful:BAAANQAECgYICwAAAA==.Dreorge:BAAANQAECgYIBgAAAA==.Drewceratops:BAAANQAECgQIBgAAAA==.Drimchi:BAAANQAECgEIAQAAAA==.Drimveil:BAAANQAECgYIBgAAAA==.Drogô:BAAANQADCgUIBQAAAA==.Dromgar:BAAANQAECgcIAgAAAA==.Dromkyr:BAAANQAECgMIAwAAAA==.Drossiechan:BAAANQAECgcICAAAAA==.',
Du='Duellipa:BAAANQAECgQIBQAAAA==.',
Dy='Dysian:BAAANQADCgQIBQAAAA==.',
Ef='Effloria:BAAANQAECgMIAwAAAA==.',
Ek='Ekim:BAAANQADCgQIAwAAAA==.',
El='Elauvia:BAAANQADCgUIBQAAAA==.Elegia:BAAANQAECggIDgAAAA==.',
En='Enash:BAAANQADCgQIBAAAAA==.Encoredk:BAAANQADCgIIAgAAAA==.Encoree:BAAANQADCgcIBwAAAA==.Enris:BAAANQADCgUICAAAAA==.',
Ev='Eviscerated:BAAANQADCgUIBQAAAA==.',
Fa='Fail:BAAANQADCgYICwAAAA==.Falker:BAAANQADCgYIBgAAAA==.Fallen:BAAANQADCggICAAAAA==.Fancyfeet:BAAANQADCgIIAwABNQAECgYIBgABAAAAAA==.Fatchungus:BAAANQAECgQIBQABNQAECgYIBgABAAAAAA==.Fateesia:BAAANQAECgEIAQAAAA==.',
Fi='Finaliter:BAAANQAECgUICwAAAA==.',
Fl='Flamingdrago:BAAANQADCgMIAwAAAA==.Flirtyflurry:BAAANQAECgMIBAAAAA==.',
Fo='Fox:BAAANQAFFAEIAQAAAA==.',
Fr='Fremder:BAAANQAECgUIBgAAAA==.Froggy:BAAANQAECgUICAAAAA==.Frogred:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.',
Fu='Funeral:BAACNQAFFIEHAAMDAAUJQBHLAAAVAQADAAMJWBbLAAAVAQAEAAMJsQqTAwDmAAA1AAQKgRkABAMACQkXJV0AAL8DAAMACQnpJF0AAL8DAAQABgksIi4VAFcCAAUAAQnPDDsXADYAAAAA.Furiousmoon:BAAANQADCggICAAAAA==.Futuresailor:BAAANQADCgEIAQAAAA==.',
Fy='Fyjhrt:BAAANQADCggIDwAAAA==.',
Ga='Gallory:BAAANQAECgYIBgAAAA==.Gayanall:BAAANQADCgMIAwAAAA==.',
Gd='Gdk:BAAANQADCgYIBwABNQAECgMIAwABAAAAAA==.Gdkmage:BAAANQADCgYIDAABNQAECgMIAwABAAAAAA==.Gdkman:BAAANQAECgMIAwAAAA==.Gdknotlock:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Ge='Geoprince:BAAANQADCgYIBgAAAA==.Gerbon:BAAANQADCgMICAAAAA==.',
Gh='Ghoulfriend:BAAANQADCgEIAQAAAA==.',
Gi='Gigitty:BAAANQADCgYIBgAAAA==.Gimmedatneck:BAAANQADCgEIAQABNQAFFAEIAgABAAAAAA==.Githrogathan:BAAANQAECgIIAgAAAA==.',
Go='Gokudin:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.Goldenrager:BAAANQADCgQIBAAAAA==.Gooseandmav:BAAANQADCgEIAQAAAA==.',
Gr='Grabetta:BAAANQADCgEIAQAAAA==.',
['Gâ']='Gârrosh:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.',
Ha='Haeha:BAAANQADCgQIBAAAAA==.Hargrumn:BAAANQABCgMIAgAAAA==.Hasaro:BAAANQAECgcIDAAAAA==.Hatcho:BAAANQADCgUICAAAAA==.Havokvacano:BAAANQADCgYIFgAAAA==.Havøckblaze:BAAANQADCgIIAgAAAA==.',
He='Healmachine:BAAANQADCgYIDgAAAA==.Hellbrringer:BAAANQAECgEIAQAAAA==.',
Ho='Holyfarts:BAAANQAECggIDAAAAA==.Hornedraven:BAAANQADCgEIAQAAAA==.',
Hu='Hunbroll:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.Hungshaman:BAAANQABCgIIAgAAAA==.Hunterkiller:BAAANQADCgUIDAAAAA==.',
Hx='Hx:BAAANQADCgYIBgAAAA==.',
Hy='Hypnoticpal:BAAANQAECggIBgAAAA==.',
['Hõ']='Hõnor:BAAANQAECgcIDgAAAA==.',
Ig='Igriss:BAAANQAECgMIAwAAAA==.',
Il='Illidanx:BAAANQADCgQIBAAAAA==.',
Im='Imonthegcd:BAAANQAECgYIBgABNQAECgcIDgABAAAAAA==.',
In='Infinitepain:BAAANQAECgYICgAAAA==.',
Ir='Iridellis:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Irsberry:BAAANQAECgIIAgAAAA==.',
Is='Ispankutank:BAAANQADCgEIAQAAAA==.',
Ja='Jahjahblinks:BAAANQADCgYICgABNQAECgYICgABAAAAAA==.Jave:BAAANQABCgQIBQAAAA==.Jaycers:BAAANQAECgQIBgAAAA==.Jayclark:BAAANQADCgEIAQAAAA==.',
Ji='Jimmypal:BAAANQADCgYICwAAAA==.',
Jo='Joemomma:BAAANQADCgMIAwAAAA==.Johnnyboi:BAAANQADCgEIAQAAAA==.Jokestarfist:BAAANQAECgIIBAAAAA==.',
Ka='Kaelar:BAAANQADCgMIAwABNQAECgcIDQABAAAAAA==.Kaitokit:BAAANQAECgcIEQAAAA==.Kalyth:BAAANQAECgEIAQAAAA==.Kamera:BAAANQAECgQIBQAAAA==.Kandessa:BAAANQADCgEIAQAAAA==.Kaylah:BAAANQAECgQIBQAAAA==.Kayllina:BAAANQADCggIFAAAAA==.Kayotic:BAAANQADCgUIBQAAAA==.',
Ke='Kelmorphic:BAAANQAECgMIAwAAAA==.',
Ki='Killcommand:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.',
Ko='Kosmas:BAAANQADCgQIBAAAAA==.',
Kr='Krombear:BAAANQADCgIIAgAAAA==.',
Ku='Kudai:BAAANQAECgQIBAAAAA==.Kungpowchikn:BAAANQADCgIIAgAAAA==.Kurookami:BAAANQADCgEIAQAAAA==.Kuukwa:BAAANQADCgEIAQAAAA==.',
['Kí']='Kíller:BAAANQAECgEIAQAAAA==.',
Ld='Ldg:BAAANQADCgQIBAAAAA==.',
Li='Lightingbolt:BAAANQADCgUICwAAAA==.Lightshields:BAAANQADCgIIAgAAAA==.Lilymei:BAAANQADCgEIAQAAAA==.Linissa:BAAANQAECgMIAwAAAA==.Littlemorsel:BAAANQAECgMIAwAAAA==.',
Lo='Lockenload:BAAANQAECgIIAgAAAA==.Lohhar:BAAANQADCggIDgAAAA==.Loser:BAAANQABCgQIBQAAAA==.',
Ls='Lselec:BAAANQADCgYIBgAAAA==.',
Lu='Lucens:BAAANQADCgQIBQAAAA==.Lurchdh:BAEANQADCgQIBAABNQAECggIFQAGAIoPAA==.Lurchmage:BAEANQAECgYICQABNQAECggIFQAGAIoPAA==.Lurchn:BAEBNQAECoEVAAIGAAgJig9aBQCxAQAGAAgJig9aBQCxAQAAAA==.',
Ly='Lyricai:BAAANQAECgEIAQAAAA==.',
['Lï']='Lïght:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.',
Ma='Madjake:BAAANQADCgYIBgAAAA==.Matas:BAAANQAECgEIAQAAAA==.Maylinfenora:BAAANQAECgEIAQAAAA==.',
Me='Merdazin:BAAANQAECgQIDAAAAA==.Metalhedface:BAAANQAECgUIBQAAAA==.',
Mo='Mogyar:BAAANQAECgYIDgAAAA==.Monkeli:BAAANQAECgEIAQAAAA==.Moonsiand:BAAANQAECgQIBAABNQAECgQICAABAAAAAA==.Moreldwiddle:BAAANQADCgYIHgAAAA==.Morgaia:BAAANQADCggIDQAAAA==.Morrigån:BAAANQADCgMIAwAAAA==.Motgus:BAAANQADCgcIDAAAAA==.Mozzsticks:BAAANQADCgUIBQAAAA==.',
My='Mystrialia:BAAANQABCgYIBgAAAA==.Mythlock:BAAANQADCgYIBgAAAA==.',
['Mó']='Mócha:BAAANQADCggIFQAAAA==.',
Na='Nardrian:BAAANQAECgQIBQAAAA==.',
Ne='Nellaa:BAAANQADCggIFwAAAA==.Nestaria:BAAANQADCggICAAAAA==.Netalanot:BAAANQADCgYIBgAAAA==.Neverborn:BAAANQAECgIIAgAAAA==.',
Ni='Nightrage:BAAANQADCgYIDwAAAA==.',
No='Nomadic:BAAANQADCgIIAgAAAA==.',
Nu='Nutellaqq:BAAANQAECgQIBwAAAA==.',
Ob='Obeseotter:BAAANQAECgUIBQAAAA==.',
Od='Od:BAAANQADCgQIBQAAAA==.',
Ol='Oliviabenson:BAAANQADCgUIBQAAAA==.',
Pa='Paldi:BAAANQAECgQIBAABNQAECgYIBgABAAAAAA==.Paliboos:BAAANQADCgYIBgAAAA==.Palulu:BAEANQAECgUIDAABNQAECgYICAABAAAAAA==.Pariss:BAAANQADCgUIBQABNQAECggIBgABAAAAAA==.Paws:BAAANQAECgEIAQAAAA==.',
Pe='Peaky:BAAANQAECgMIBgAAAA==.Perelia:BAAANQAECgEIAQAAAA==.',
Pl='Plondor:BAAANQABCgEIAQAAAA==.',
Po='Polarity:BAAANQABCgYIBAAAAA==.Pooche:BAAANQABCgMIAwAAAA==.',
Pp='Ppc:BAAANQADCggIDQABNQAECgcIEAABAAAAAA==.',
Pr='Prezu:BAEANQAECgYICAAAAA==.Prophofdoom:BAAANQAECgQIBAAAAA==.Prõc:BAAANQADCgYIBgAAAA==.',
Pv='Pvc:BAAANQAECgcIEAAAAA==.',
Ra='Ratsmasher:BAAANQADCggIEwAAAA==.Razed:BAAANQADCgYICwAAAA==.',
Re='Retrobution:BAAANQAECgQICAAAAA==.Rezz:BAAANQAECgcIDAAAAA==.',
Rh='Rhohir:BAAANQABCgIIAgAAAA==.',
Ri='Riru:BAAANQAECgQIBAAAAA==.',
Ry='Rynzu:BAAANQADCgYICwAAAA==.Ryzen:BAAANQAECgIIAgAAAA==.',
Sa='Sabelwin:BAAANQADCgEIAQAAAA==.Sanasrindis:BAAANQADCgQIAgAAAA==.Saninar:BAAANQAECgIIAwAAAA==.Sanshift:BAAANQADCgIIAgAAAA==.Satansimp:BAAANQADCggIEAAAAA==.',
Sc='Schadnfreude:BAAANQAECgcICwAAAA==.Schezmu:BAAANQADCgUIBQAAAA==.',
Se='Sean:BAAANQADCgQIBAAAAA==.Setazen:BAAANQADCgYIBgAAAA==.',
Sh='Shadowjoker:BAAANQAECgEIAQAAAA==.Shamans:BAAANQADCgYICwAAAA==.Shaokhan:BAAANQADCgYIBgAAAA==.Shasta:BAAANQAECgcIDQAAAA==.Shihthead:BAAANQADCgUIBQAAAA==.Shisuiuchiha:BAAANQADCgIIAgAAAA==.Shmorg:BAAANQADCgEIAQAAAA==.Shootumup:BAAANQAECgYICwAAAA==.Shyx:BAAANQAECgEIAQAAAA==.',
Si='Simplèjack:BAAANQAECgIIAgAAAA==.Sinamon:BAAANQABCgIIAgAAAA==.',
Sj='Sjdh:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Sk='Skar:BAAANQADCgUIBgAAAA==.Skronker:BAAANQADCggIDQAAAA==.',
Sl='Slammydooker:BAAANQAECgMIAwAAAA==.',
Sm='Smirksfotm:BAAANQAECgQIBAABNQAECggICAABAAAAAA==.',
Sn='Sneakmanman:BAAANQADCgYICQAAAA==.',
So='Somberdh:BAAANQADCggICwAAAA==.Sorni:BAAANQAECgQIBQAAAA==.Soulglo:BAAANQADCgcIDQAAAA==.',
Sp='Sprayandpray:BAAANQAECgMIAwAAAA==.Spritey:BAAANQABCgIIAgAAAA==.',
St='Stareless:BAAANQADCgYIBgAAAA==.Statik:BAAANQADCgIIAgAAAA==.',
Su='Summondemons:BAAANQAECgIIBQAAAA==.Sunpali:BAAANQADCggIDwAAAA==.Susanno:BAAANQADCgEIAQAAAA==.',
Sy='Sylauda:BAAANQADCgYICgAAAA==.Sylvians:BAAANQADCggICAAAAA==.',
Ta='Tacutacudark:BAAANQADCgYIFAAAAA==.Taintedbeef:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Talonflame:BAAANQAECgQIBgAAAA==.Talonted:BAAANQADCgIIAgAAAA==.Taupo:BAAANQADCgYICgAAAA==.Taxidermy:BAAANQADCgYIBgAAAA==.',
Te='Telarinda:BAAANQADCgUIBQAAAA==.',
Th='Thicclich:BAAANQADCggIEQAAAA==.Thicktotem:BAAANQAECgEIAQAAAA==.Thickumz:BAAANQADCgQIBAAAAA==.Thisismeta:BAAANQAECgUICAAAAA==.Thorynwar:BAAANQAECgcIDgAAAA==.Thorýn:BAABNQAECoEZAAIHAAkJ8STlAADZAwAHAAkJ8STlAADZAwAAAA==.Thórin:BAAANQAECgIIAwAAAA==.',
Ti='Tierax:BAAANQAECgYIBwAAAA==.Tipsy:BAAANQAECgMIAwAAAA==.',
To='Tojì:BAAANQAECggICAAAAA==.Tomfoolary:BAAANQABCgYIBgAAAA==.Tonathul:BAAANQADCggIEAAAAA==.Torrk:BAAANQADCgUICwAAAA==.Tot:BAAANQAECgQIBAAAAA==.',
Tr='Tralleth:BAAANQADCggIFAAAAA==.Traumatized:BAAANQADCgIIAgAAAA==.Truska:BAAANQABCgEIAQAAAA==.',
Tw='Twinklord:BAAANQAECgEIAQAAAA==.',
Ty='Tylopally:BAAANQAECgQIBQAAAA==.Tyloremixdd:BAAANQADCgYIBwAAAA==.Tylototem:BAAANQAECgQIBAAAAA==.',
['Tö']='Tötem:BAAANQADCgMIAwABNQAECgcIDgABAAAAAA==.',
Uj='Ujcpet:BAAANQADCgYIBgAAAA==.',
Un='Uncookedham:BAAANQADCgUICgAAAA==.Underhorn:BAAANQADCgYIBgAAAA==.',
Va='Vaas:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Vaeelrundor:BAAANQAECgEIAgAAAA==.Valyr:BAAANQABCgYIBwAAAA==.Vampslayer:BAAANQADCgYIBgAAAA==.Vanillaface:BAAANQADCgYIBwAAAA==.Vañillaface:BAAANQABCgQIBgAAAA==.',
Ve='Vedexd:BAAANQAECgUIDgAAAA==.Velarael:BAAANQADCgcIEwAAAA==.Velexi:BAAANQADCgQIBwAAAA==.',
Vl='Vlidya:BAAANQADCgEIAQAAAA==.',
Vo='Voidberg:BAAANQADCgYIBgAAAA==.',
Vs='Vs:BAAANQAECgcICgAAAA==.',
Wa='Wachonaso:BAAANQAECgcIEAAAAA==.Wastedsage:BAAANQADCggIEAAAAA==.',
Wh='Whatuphuz:BAAANQADCgQICQAAAA==.Wheresmyjaw:BAAANQAECgUICAAAAA==.',
Wi='Wildthree:BAAANQADCgcIDQAAAA==.Willenda:BAAANQADCgQIBgAAAA==.',
Wu='Wuinn:BAAANQAECggIDgAAAA==.',
Xa='Xakutioner:BAAANQAECgMIAwAAAA==.Xaldiir:BAAANQADCggICAAAAA==.',
Xe='Xerexia:BAAANQAECgUICAAAAA==.',
Xw='Xwoo:BAAANQAECgIIAgAAAA==.',
Ya='Yahro:BAAANQAECgcIEQAAAA==.',
Ye='Yellowranger:BAAANQAECgMIBgAAAA==.',
Yo='Yongyong:BAAANQADCgYIDwAAAA==.Yotoymuerto:BAAANQAECgEIAQAAAA==.',
Yu='Yunara:BAAANQAECgYIBgAAAA==.Yustayoke:BAAANQAECgMIAwAAAA==.',
Za='Zalvianna:BAAANQADCggIDwAAAA==.Zarshx:BAAANQADCgQICAABNQAECgYIBgABAAAAAA==.',
Zi='Zilongwar:BAAANQAFFAMIAwAAAA==.',
Zo='Zonedk:BAAANQAECgIIAgAAAA==.',
['Ør']='Ørsted:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.',
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
