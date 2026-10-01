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

local lookup = {'Monk-Brewmaster','Druid-Balance','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Warrior-Arms','DeathKnight-Blood','Paladin-Protection','Unknown-Unknown','Warrior-Fury','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Rogue-Assassination','Rogue-Outlaw','Priest-Shadow','Druid-Guardian','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Subtlety','DemonHunter-Devourer','Hunter-BeastMastery',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQADCgEIAQAAAA==.Adrianmonk:BAABNQAECoEcAAIBAAgKwyU3AgBvAwABAAgKwyU3AgBvAwAAAA==.',
Ae='Aezu:BAACNQAFFIEIAAICAAQK5xKhCwBQAQACAAQK5xKhCwBQAQA1AAQKgSMAAwIACQovIQMQACgDAAIACQovIQMQACgDAAMAAwpfEetBALMAAAAA.',
Ai='Ailuria:BAAANQAECgUIDQAAAA==.Aitharen:BAAANQAECgIIAgAAAA==.',
Al='Alikith:BAAANQAECgUIDQAAAA==.Altheyra:BAAANQADCgYIEAAAAA==.Alyas:BAAANQADCgQIBwAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAAANQAECgYIEAAAAA==.Amelía:BAABNQAECoEWAAMEAAgKqRZSXQChAQAEAAcKkBRSXQChAQAFAAQK2BBXsADbAAAAAA==.Amitre:BAAANQADCgcICQAAAA==.Amorillas:BAAANQABCgIIAgAAAA==.Amèlia:BAAANQADCgUIBQABNQAECggIFgAEAKkWAA==.',
An='Angando:BAAANQAECgYIEQAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQADCgQIBwAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arnarn:BAAANQAECgYIBgAAAA==.Artemidoros:BAAANQAECgUIDQAAAA==.',
As='Asuná:BAAANQAECgQICgAAAA==.',
Au='Augtism:BAABNQAECoEcAAMGAAgK/gqsFgCdAQAGAAgK5wmsFgCdAQAHAAMKKQa7FQCBAAAAAA==.',
Av='Avataroffire:BAAANQAECgUICAAAAA==.',
Aw='Awakened:BAAANQADCgcJAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFIEIAAIIAAQKeg7QAAAyAQAIAAQKeg7QAAAyAQA1AAQKgSAAAggACQpdGe0EAIwCAAgACQpdGe0EAIwCAAAA.',
Be='Beefbrownie:BAAANQAECgUIDQAAAA==.Bellezora:BAAANQAECgYIEgAAAA==.Bellwynn:BAAANQAECgcIEgAAAA==.Berzerked:BAABNQAECoEzAAIJAAkKdSUYBADLAwAJAAkKdSUYBADLAwAAAA==.',
Bi='Biggmean:BAAANQADCggICAAAAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECoEiAAIKAAgK/R07GwCiAgAKAAgK/R07GwCiAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECgEJAQAAAA==.Brick:BAABNQAECoEgAAIBAAgKSBxwCABoAgABAAgKSBxwCABoAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Bus:BAAANQAECgcIDQABNQAFFAYIEwALAE8hAA==.',
Ca='Camholy:BAAANQAECgUIDQAAAA==.',
Ce='Celtykun:BAAANQAECgIIAgAAAA==.',
Ch='Chiron:BAAANQADCgcIEgABNQAECgUIBQAMAAAAAA==.',
Co='Connie:BAAANQAECgUIBwAAAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAAANQAECgEIAQAAAA==.Dapur:BAAANQADCgMIBAAAAA==.Darksteldt:BAAANQAECgIIAgAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deimös:BAAANQADCgUIBgAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.',
Dh='Dhing:BAAANQAECgYIBgAAAA==.',
Di='Dillexis:BAABNQAECoEhAAMJAAgKVxcfZAAZAgAJAAgKNBYfZAAZAgANAAEKXxW+JQA9AAAAAA==.Dismagey:BAAANQAECgYICAAAAA==.',
Do='Donald:BAABNQAECoEgAAICAAgKShS7MAAVAgACAAgKShS7MAAVAgAAAA==.Doomslash:BAABNQAECoEYAAIJAAcKuQ3hjwCYAQAJAAcKuQ3hjwCYAQAAAA==.Doublea:BAAANQAECgYICgAAAA==.',
Dr='Dragem:BAAANQADCggIGAABNQAECgUIDQAMAAAAAA==.Dragonchest:BAAANQAECgUICwABNQAECgYICgAMAAAAAA==.Dragonswolf:BAAANQAECgYICgAAAA==.Dragonwing:BAAANQAECgMIAwABNQAECgYICgAMAAAAAA==.Drbubblesmd:BAAANQAECgQIBgAAAA==.Dregon:BAACNQAFFIEIAAIOAAQKryRxAgCvAQAOAAQKryRxAgCvAQA1AAQKgSMAAg4ACQqqJmMAAOEDAA4ACQqqJmMAAOEDAAAA.Dreinara:BAAANQAECgEIAQAAAA==.',
Du='Dummysezwhut:BAAANQAECgIJAgAAAA==.',
Ea='Eastofeden:BAAANQAECgMIAwAAAA==.',
Ec='Echinopsis:BAAANQAECgEIAQAAAA==.',
Ei='Eiduartkay:BAAANQAECgYICgAAAA==.Eight:BAAANQADCgUICQAAAA==.Eilyn:BAAANQAECgYIDQAAAA==.',
El='Elffaba:BAAANQADCgIIBAAAAA==.Elystraeya:BAAANQADCggICAAAAA==.',
En='Enyoa:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAAANQAECgUIBwAAAA==.Fangmage:BAAANQADCgUJBwAAAA==.Fazlain:BAAANQAECgQIBwAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgEIAQABNQAECgUIBQAMAAAAAA==.Fenria:BAAANQABCgQIAgAAAA==.',
Fu='Furryem:BAAANQAECgUIDQAAAA==.',
['Fô']='Fôxx:BAAANQADCgQIBwAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECoEbAAMPAAcKoRM5iQCrAQAPAAcKoRM5iQCrAQAQAAIKbQMv3ABcAAAAAA==.Gatelinka:BAAANQADCgUJBQABNQAECgYIEgAMAAAAAA==.Gateto:BAAANQAECgYIEgAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwAMAAAAAA==.',
Gl='Glynistann:BAAANQADCgQIBwAAAA==.',
Gu='Gundox:BAAANQADCgQIBwAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hamishtok:BAAANQABCggIEAAAAA==.Hanoa:BAAANQAECgUIBwAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAAANQAECgUICAAAAA==.',
Hu='Huntinbub:BAAANQAECgYIDwAAAA==.',
Hy='Hyacaina:BAAANQABCgUICQAAAA==.',
Ik='Ikickgnômes:BAAANQADCgUIBQAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECggIIQARAGoeAA==.Ingrown:BAAANQABCgIIAgAAAA==.',
Ir='Irim:BAAANQAECgYIEgAAAA==.',
Iv='Ivon:BAAANQADCgYJDAABNQAECggIIQAJAFcXAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFIEGAAMSAAMKSxnYBgATAQASAAMKSxnYBgATAQATAAEKTBWvAgBRAAA1AAQKgSEAAxIACQriHnIPAMYCABIACApVHnIPAMYCABMACQo+HP8DAKwCAAAA.',
Ji='Jickle:BAAANQADCggJEwAAAA==.',
Jo='Joppa:BAAANQADCgMIBAABNQAFFAYIEAAUAM8RAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQADCgYIBgAAAA==.',
Ke='Keý:BAACNQAFFIEIAAIJAAQKcQt0EgAiAQAJAAQKcQt0EgAiAQA1AAQKgSAAAgkACQpPIWojAAUDAAkACQpPIWojAAUDAAAA.',
Kh='Khadgarjr:BAAANQADCgYICQAAAA==.Khänvict:BAAANQAECgQIBwAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIJAgAAAA==.Kim:BAAANQADCgQIBAAAAA==.Kiy:BAAANQAECgUICgAAAA==.',
Kn='Knìghtmare:BAAANQADCgYICwAAAA==.',
Kr='Krakenlock:BAAANQAECgYICwAAAA==.Kronas:BAAANQADCgQIDQAAAA==.',
Ku='Kumojoru:BAACNQAFFIEIAAIVAAQKtRTBAQArAQAVAAQKtRTBAQArAQA1AAQKgSMAAhUACQo/IxcCAIUDABUACQo/IxcCAIUDAAAA.',
Ky='Kyranos:BAAANQADCggIFQAAAA==.',
La='Lazyheal:BAAANQADCgQIBAABNQAECggIHwAEALccAA==.',
Le='Leigor:BAACNQAFFIEIAAIWAAQKwRlPDABuAQAWAAQKwRlPDABuAQA1AAQKgSMAAhYACQrrHxoXAO0CABYACQrrHxoXAO0CAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Linthsong:BAAANQAECgQICQABNQAECgcIFwAWADkQAA==.Lionature:BAAANQADCgcIFQAAAA==.Lionknite:BAABNQAECoEaAAMXAAcKXhkdOADkAQAXAAcKXhkdOADkAQAYAAEKBwuNhwAuAAAAAA==.Liteshocklet:BAABNQAECoEfAAIEAAgKtxwAKwB4AgAEAAgKtxwAKwB4AgAAAA==.Littledung:BAAANQADCgEIAQAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
Lu='Lumiann:BAABNQAECoEYAAIJAAgKnRsOSAB1AgAJAAgKnRsOSAB1AgAAAA==.',
['Lã']='Lãdyrift:BAAANQAECgYIEAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malokai:BAAANQADCgQJBAAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECoEWAAMOAAcKshxHFADiAQAOAAYKyBtHFADiAQAZAAIK/AkiTgBLAAAAAA==.Martinia:BAAANQABCgQIBgAAAA==.Mauzer:BAAANQADCggIFAABNQAECgUICQAMAAAAAA==.Mauzii:BAAANQADCgMIBAABNQAECgUICQAMAAAAAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAAANQAECgcIEQAAAA==.',
Me='Melliah:BAAANQADCgQIBwAAAA==.Mes:BAAANQAECgYIDAAAAA==.',
Mi='Mimmi:BAAANQAECgUICQAAAA==.Misaligned:BAAANQAECgUIBwAAAA==.Misidian:BAAANQADCgQJBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgcIFwARAK4WAA==.Moonsorrow:BAAANQAECgMIAwAAAA==.Moritura:BAAANQAECgMICAABNQAECgUICQAMAAAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Nemistrasza:BAAANQADCggICwABNQAECgUIDQAMAAAAAA==.',
Ni='Nilanza:BAAANQADCgcIBwABNQAECggIGAAJAJ0bAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nolan:BAAANQAECgEJAQABNQAECgQJBAAMAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECggIGQASAKETAA==.',
Ol='Ollie:BAAANQABCgYIDAAAAA==.',
Op='Ophiuchus:BAAANQAECgUIBQAAAA==.',
Os='Ostpeppar:BAAANQADCgMIAwAAAA==.',
Pa='Paldente:BAAANQAECgEIAQABNQAECgYIEQAMAAAAAA==.Pamelina:BAAANQABCgEIAQAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECggIIQAJAFcXAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAAANQAECgQIBwAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggIEwAAAA==.Pernicious:BAAANQAECgMIAwAAAA==.',
Ph='Phillis:BAAANQADCgUIBQAAAA==.Philster:BAAANQADCgMIBgAAAA==.Physics:BAEANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAAANQAECgQIBwAAAA==.Pinkiemena:BAAANQAECggICAAAAA==.',
Po='Potent:BAAANQABCgIIAgAAAA==.',
Pu='Punchykicky:BAAANQAECgQIBwABNQAECgYIEgAMAAAAAA==.',
Py='Pyria:BAAANQADCgMIAwAAAA==.',
['Pé']='Pérrywinklé:BAAANQAECgcIDQAAAA==.',
Ra='Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAAANQAECgUICAAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reniel:BAAANQABCgIIAQABNQAECgUIDQAMAAAAAA==.Reverendlion:BAAANQAECgQIBAAAAA==.',
Rh='Rhattice:BAAANQABCgYICAAAAA==.',
Ro='Rogosh:BAAANQAECgYIBgAAAA==.Rosencrant:BAAANQAECgUICwAAAA==.',
Ru='Rule:BAAANQADCgQIBwAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgkJHwAPAK4XAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.',
Sa='Saiko:BAABNQAECoEdAAIaAAcKEhyQBwAyAgAaAAcKEhyQBwAyAgAAAA==.Sainthealz:BAAANQABCgQIBgAAAA==.Sampal:BAAANQAECgYIEgAAAA==.Samwield:BAEBNQAECoEkAAMbAAgKpxrUDgBtAgAbAAgKARrUDgBtAgASAAIK6RTjXgCaAAAAAA==.Sanjana:BAAANQADCgQJBAAAAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAAANQAECgYIEgAAAA==.Selaheal:BAAANQAECgYIEgAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shinobu:BAAANQADCgYICgABNQAECgcIEgAMAAAAAA==.Shnood:BAAANQAECgYIDQAAAA==.Shnordora:BAAANQADCgIJAgAAAA==.Shrapnell:BAAANQABCgIIAgAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECoEhAAMcAAgK7h6IEADGAgAcAAgK7h6IEADGAgAaAAEKAgGAKwAXAAABNQAECgkJIgALANgXAA==.',
Sk='Skies:BAAANQADCgYIBgABNQAECgkJJAATAOQcAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECgUIDQAMAAAAAA==.Stersèbuk:BAAANQADCgIIAgABNQAECggIFwAFAO0XAA==.Sterïzard:BAAANQADCgEIAQABNQAECggIFwAFAO0XAA==.Stupid:BAABNQAECoEiAAIQAAkK5BzIFgD3AgAQAAkK5BzIFgD3AgAAAA==.Stærk:BAABNQAECoEXAAIFAAgK7RdBOgBEAgAFAAgK7RdBOgBEAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECggIIQARAGoeAA==.Sunpally:BAABNQAECoEZAAIQAAcKWxHXXwCrAQAQAAcKWxHXXwCrAQAAAA==.Suvulaan:BAAANQAECgMIBgAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQABCgIIAgAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tatoo:BAABNQAECoEhAAIdAAgKISDfHQDqAgAdAAgKISDfHQDqAgAAAA==.',
Te='Teeice:BAABNQAECoEhAAISAAgKERklGABqAgASAAgKERklGABqAgAAAA==.Teo:BAAANQAECgYIEgAAAA==.',
Th='Thekan:BAAANQAECgQICQAAAA==.Theriot:BAABNQAECoEeAAMLAAgKJx4FDACWAgALAAgKJx4FDACWAgAPAAIKNhiHGgF3AAAAAA==.Thianá:BAAANQAECgEIAQAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECgYIEgAMAAAAAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Toosus:BAACNQAFFIEIAAIKAAQKwB69CQBlAQAKAAQKwB69CQBlAQA1AAQKgSQAAgoACQrMI2gGAHoDAAoACQrMI2gGAHoDAAAA.Totemsnhoes:BAAANQADCgUIDAAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trolldung:BAAANQADCgQIBwAAAA==.',
Tt='Tturtle:BAABNQAECoEjAAIPAAkKIxsdQgCEAgAPAAkKIxsdQgCEAgAAAA==.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAAANQAECgEIAQAAAA==.',
Un='Unclebuck:BAAANQABCgYIDgAAAA==.Unholysam:BAEANQADCgUIBQABNQAECggIJAAbAKcaAA==.',
Va='Vallo:BAAANQADCgEIAQAAAA==.',
Ve='Velata:BAABNQAECoEXAAIIAAgKPRCVCQDmAQAIAAgKPRCVCQDmAQAAAA==.Vesselette:BAAANQADCggICAAAAA==.',
Vi='Victory:BAAANQAECgEIAgAAAA==.Violencê:BAAANQAECgYIEQAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vy='Vynivar:BAAANQAECgEIAQAAAA==.',
We='Wes:BAAANQAECgYIEAAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECoEXAAIdAAgKQhsGMgCVAgAdAAgKQhsGMgCVAgAAAA==.Willybcastin:BAABNQAECoEUAAIRAAkKvxz1RgDSAgARAAkKvxz1RgDSAgABNQAFFAUIDAAXAP0gAA==.Willybwankin:BAACNQAFFIEMAAIXAAUK/SAIAgDfAQAXAAUK/SAIAgDfAQA1AAQKgScAAhcACQrVJl4BANsDABcACQrVJl4BANsDAAAA.',
Wo='Wowgazm:BAAANQAECgUICwAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAAANQAECgUIDQAAAA==.',
Xe='Xerath:BAAANQAECgEIAQAAAA==.',
Yo='Yogami:BAAANQABCgIIAgAAAA==.',
Za='Zacarly:BAAANQAECgEIAQAAAA==.Zalarian:BAABNQAECoEaAAIPAAkK8xx2MADJAgAPAAkK8xx2MADJAgAAAA==.',
Ze='Zemos:BAAANQADCgYIBwAAAA==.Zeseroth:BAAANQADCgYICQAAAA==.Zeserotho:BAACNQAFFIEIAAIZAAQKwhieBQBcAQAZAAQKwhieBQBcAQA1AAQKgSIAAhkACQqZIOILAOoCABkACQqZIOILAOoCAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECoEiAAMLAAkK2Bf3EgAjAgALAAgKGBj3EgAjAgAQAAMKlQmawACpAAAAAA==.',
['Éi']='Éireann:BAAANQAECgEIAQAAAA==.',
['Ðu']='Ðumpy:BAAANQAECgUICQAAAA==.',
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
