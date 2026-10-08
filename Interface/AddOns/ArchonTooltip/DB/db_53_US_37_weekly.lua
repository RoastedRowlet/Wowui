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

local lookup = {'Monk-Brewmaster','Druid-Balance','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Protection','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','DeathKnight-Blood','Paladin-Protection','Unknown-Unknown','Warrior-Fury','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Rogue-Outlaw','Priest-Shadow','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Subtlety','DemonHunter-Devourer',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Aconite:BAAANQAECgEIAQAAAA==.',
Ad='Adelyne:BAAANQADCggICwAAAA==.Adrianmonk:BAABNQAECoEkAAIBAAgK2iWPAgBtAwABAAgK2iWPAgBtAwAAAA==.',
Ae='Aezu:BAACNQAFFIENAAICAAUKAxeDCQCtAQACAAUKAxeDCQCtAQA1AAQKgSUAAwIACQpmIQcTABoDAAIACQpmIQcTABoDAAMAAwpfEZZLALAAAAAA.',
Ai='Ailuria:BAAANQAECgYIEwAAAA==.Aitharen:BAAANQAECgIIAgAAAA==.',
Al='Alikith:BAAANQAECgYIEwAAAA==.Altheyra:BAAANQADCgYIEAAAAA==.Alyas:BAAANQAECgIIAgAAAA==.Alynia:BAAANQADCggICAAAAA==.',
Am='Ambrìel:BAABNQAECoEcAAMEAAcK7w62IwCuAAAFAAcKNQph6wCNAQAEAAMKrxi2IwCuAAAAAA==.Amelía:BAABNQAECoEZAAMGAAkKCBUCXADNAQAGAAgK/hICXADNAQAHAAQK2BC0xgDXAAAAAA==.Amitre:BAAANQAECgMIAwAAAA==.Amorillas:BAAANQABCgIIAgAAAA==.Amulet:BAAANQABCgUICQAAAA==.Amèlia:BAAANQADCgUIBQABNQAECgkJGQAGAAgVAA==.',
An='Angando:BAABNQAECoEYAAMIAAcKGgugswBtAQAIAAcKzwmgswBtAQAJAAEKywzpOgA0AAAAAA==.Anklèbiter:BAAANQADCgQIBAAAAA==.Anoxen:BAAANQADCgEIAQAAAA==.',
Ap='Aperfecttool:BAAANQAECgIIAgAAAA==.',
Aq='Aquaregia:BAAANQADCgQIBQAAAA==.',
Ar='Arcanos:BAAANQADCgEIAQAAAA==.Arcuthyr:BAAANQABCgQIBwAAAA==.Arnarn:BAAANQAECgYICAAAAA==.Artemidoros:BAAANQAECgYIEwAAAA==.',
As='Asuná:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAABNQAECoEfAAMKAAkKPQuNFQDSAQAKAAkKRAqNFQDSAQALAAMKKQYEGQCBAAAAAA==.',
Av='Avataroffire:BAAANQAECgUIDQAAAA==.',
Aw='Awakened:BAAANQADCgcJAwAAAA==.',
Ax='Axid:BAAANQAECgEIAQAAAA==.',
Ba='Barathor:BAAANQADCgYIBgAAAA==.',
Bd='Bdil:BAACNQAFFIEMAAIEAAUK4wzgAABtAQAEAAUK4wzgAABtAQA1AAQKgSIAAgQACQoKGrEGAGUCAAQACQoKGrEGAGUCAAAA.',
Be='Beefbrownie:BAAANQAECgYIEwAAAA==.Bellezora:BAABNQAECoEZAAIMAAcKuR9nNgBsAgAMAAcKuR9nNgBsAgAAAA==.Bellwynn:BAAANQAECgcIEwAAAA==.Berzerked:BAABNQAECoE7AAIIAAkKdSWVBgC6AwAIAAkKdSWVBgC6AwAAAA==.',
Bi='Biggmean:BAAANQADCggICAAAAA==.',
Bl='Bloodmonks:BAAANQADCgEIAQAAAA==.Bloodynutz:BAABNQAECoEoAAINAAkK3xztFgDfAgANAAkK3xztFgDfAgAAAA==.',
Bo='Boneyt:BAAANQADCgEIAQAAAA==.Borghild:BAAANQABCgYIBgAAAA==.',
Br='Bradigan:BAAANQAECgEIAQAAAA==.Brick:BAABNQAECoEgAAIBAAgKSBwuCgBXAgABAAgKSBwuCgBXAgAAAA==.',
Bu='Buckett:BAAANQAECgEIAwAAAA==.Burrana:BAAANQADCgMIAwAAAA==.Bus:BAABNQAECoEXAAIBAAkK5yYGAAAdBAABAAkK5yYGAAAdBAABNQAFFAYIFQAOAKYhAA==.',
Ca='Camholy:BAAANQAECgYIEwAAAA==.',
Ce='Celtykun:BAAANQAECgIIAgAAAA==.',
Ch='Chiron:BAAANQADCggIFwABNQAECgYICwAPAAAAAA==.',
Co='Connie:BAAANQAECgUIBwAAAA==.',
Da='Daemon:BAAANQADCgYJCwAAAA==.Daemos:BAAANQAECgEIAQAAAA==.Dapur:BAAANQADCgMIBAAAAA==.Darksteldt:BAAANQAECgMIBAAAAA==.',
De='Deathangus:BAAANQADCgYIBgAAAA==.Deimös:BAAANQADCgUIBgAAAA==.Dejuvalla:BAAANQAECgQIBAAAAA==.Derekrules:BAAANQADCgUIBQAAAA==.',
Dh='Dhing:BAAANQAECgYIDAAAAA==.',
Di='Dillexis:BAABNQAECoEoAAMIAAkKqRjjTgCCAgAIAAkKQhjjTgCCAgAQAAQK5RTJFgAOAQAAAA==.Dismagey:BAAANQAECgYICAAAAA==.',
Do='Donald:BAABNQAECoEgAAICAAgKShQ5OAADAgACAAgKShQ5OAADAgAAAA==.Doomslash:BAABNQAECoEZAAIIAAgKYQ24jQDTAQAIAAgKYQ24jQDTAQAAAA==.Doublea:BAAANQAECgYICwAAAA==.',
Dr='Dragem:BAAANQADCggIGAABNQAECgYIEwAPAAAAAA==.Dragonchest:BAAANQAECgcIEgAAAA==.Dragonswolf:BAAANQAECgYICgABNQAECgcIEgAPAAAAAA==.Dragonwing:BAAANQAECgMIAwABNQAECgcIEgAPAAAAAA==.Drbubblesmd:BAAANQAECgQIBwAAAA==.Dregon:BAACNQAFFIENAAIRAAUK1iPkAQAFAgARAAUK1iPkAQAFAgA1AAQKgSUAAhEACQqqJqUAANUDABEACQqqJqUAANUDAAAA.Dreinara:BAAANQAECgEIAQAAAA==.',
Du='Dummysezwhut:BAAANQAECgIIAgAAAA==.',
Ea='Eastofeden:BAAANQAECgUIBwAAAA==.',
Ec='Echinopsis:BAAANQAECgMIBwAAAA==.',
Ei='Eiduartkay:BAAANQAECgYICgAAAA==.Eight:BAAANQADCggICgAAAA==.Eilyn:BAAANQAECgYIEwAAAA==.',
El='Elffaba:BAAANQADCgIIBAAAAA==.Elystraeya:BAAANQAECggICAAAAA==.',
En='Enyoa:BAAANQABCgIIAgAAAA==.',
Fa='Faelirra:BAAANQAECgYIDQAAAA==.Fangmage:BAAANQADCgUJBwAAAA==.Fazlain:BAAANQAECgQICwAAAA==.',
Fe='Fellchinator:BAAANQAECgEIAgAAAA==.Felnir:BAAANQAECgEIAQABNQAECgYICwAPAAAAAA==.Fenria:BAAANQABCgQIAgAAAA==.',
Fu='Furryem:BAAANQAECgYIEwAAAA==.',
['Fô']='Fôxx:BAAANQAECgMIAwAAAA==.',
Ga='Galvvatron:BAAANQADCgEIAQAAAA==.Gatelina:BAABNQAECoEjAAMSAAgKJxW9gAD2AQASAAgKJxW9gAD2AQATAAIKbQN39QBYAAAAAA==.Gatelinka:BAAANQADCgUJBQABNQAECgcIFQAGABchAA==.Gateto:BAABNQAECoEVAAMGAAcKFyFDLwCAAgAGAAcKFyFDLwCAAgAHAAQKzwiiyQDRAAAAAA==.',
Ge='Genfindel:BAAANQADCgIIAgABNQAECgYIDwAPAAAAAA==.',
Gl='Glynistann:BAAANQAECgIIAgAAAA==.',
Gu='Gundox:BAAANQAECgIIAgAAAA==.',
Ha='Hakki:BAAANQADCgUIBQAAAA==.Hamishtok:BAAANQABCggIEAAAAA==.Hanoa:BAAANQAECgUIBwAAAA==.Hartley:BAAANQADCgEIAQAAAA==.',
He='Heelznsolez:BAAANQAECgQIBAAAAA==.Hellravage:BAAANQAECgYIDgAAAA==.',
Hu='Huntinbub:BAABNQAECoEcAAIUAAcK2xMfegDrAQAUAAcK2xMfegDrAQAAAA==.',
Hy='Hyacaina:BAAANQABCgUICQAAAA==.',
Ik='Ikickgnômes:BAAANQAECgYIBQAAAA==.',
In='Infanteater:BAAANQADCgQIBAABNQAECgkJJwAFAKweAA==.Ingrown:BAAANQABCgIIAgAAAA==.',
Ir='Irim:BAABNQAECoEdAAQVAAkKoCGJBADSAgAVAAcKbCOJBADSAgAWAAUKjRcimQB3AQAXAAEK/xQYKgA5AAAAAA==.',
Iv='Ivon:BAAANQADCgYIDAABNQAECgkJKAAIAKkYAA==.',
Ja='Jacks:BAAANQAECgIIAgAAAA==.',
Je='Jeopardytime:BAACNQAFFIEKAAMYAAQKaBVOCgAIAQAYAAMKXxlOCgAIAQAZAAIKaA8/AgChAAA1AAQKgSEAAxgACQriHtAVAKgCABgACApVHtAVAKgCABkACQo+HOcEAJgCAAAA.',
Ji='Jickle:BAAANQADCggJEwAAAA==.',
Jo='Joppa:BAAANQADCgMIBAABNQAFFAYIFQAaAJUVAA==.Joyvimon:BAAANQADCggICAAAAA==.',
Ka='Kaylib:BAAANQAECgQIBAAAAA==.',
Ke='Keý:BAACNQAFFIENAAIIAAUK1hhyDAC3AQAIAAUK1hhyDAC3AQA1AAQKgSIAAggACQrjIc4pAAIDAAgACQrjIc4pAAIDAAAA.',
Kh='Khadgarjr:BAAANQADCgYICQAAAA==.Khänvict:BAAANQAECgQIBwAAAA==.',
Ki='Kickstarter:BAAANQAECgUICQAAAA==.Killakhan:BAAANQAECgIJAgAAAA==.Kim:BAAANQADCgQIBAAAAA==.Kiy:BAAANQAECgYIEAAAAA==.',
Kn='Knìghtmare:BAAANQADCgYICwAAAA==.',
Kr='Krakenlock:BAAANQAECgYIEQAAAA==.Krenin:BAAANQADCgEIAQAAAA==.Kronas:BAAANQADCgYIEAAAAA==.',
Ku='Kumojoru:BAACNQAFFIENAAIbAAUKmRhxAQCRAQAbAAUKmRhxAQCRAQA1AAQKgSUAAhsACQp9I7kCAIIDABsACQp9I7kCAIIDAAAA.',
Ky='Kyranos:BAAANQADCggIFQAAAA==.',
La='Lazyheal:BAAANQADCgQIBAABNQAECgkJIgAGAOYcAA==.',
Le='Leigor:BAACNQAFFIENAAIMAAUK9hfUCgC0AQAMAAUK9hfUCgC0AQA1AAQKgSUAAgwACQpBIUIaAPMCAAwACQpBIUIaAPMCAAAA.',
Li='Lightwork:BAAANQADCgQIBAAAAA==.Linthsong:BAAANQAECgQICQABNQAECgcIHAAMAHQQAA==.Lionature:BAAANQADCgcIFQAAAA==.Lionknite:BAABNQAECoEiAAMcAAgKAxrqNwAhAgAcAAgKAxrqNwAhAgAdAAEKBwv1lwAuAAAAAA==.Liteshocklet:BAABNQAECoEiAAIGAAkK5hzcIADHAgAGAAkK5hzcIADHAgAAAA==.Littledung:BAAANQADCgEIAQAAAA==.',
Lo='Loisterly:BAAANQADCgYIBgAAAA==.Lostthegame:BAAANQAECgYIBgAAAA==.Loving:BAAANQAECgIIBgAAAA==.',
Lu='Lumiann:BAABNQAECoEfAAIIAAgK9SDiKQACAwAIAAgK9SDiKQACAwAAAA==.',
['Lã']='Lãdyrift:BAABNQAECoEaAAMDAAgK6g6zKACoAQADAAgK6g6zKACoAQACAAYKgwJmegC4AAAAAA==.',
Ma='Madeawarrior:BAAANQAECgQIBAAAAA==.Magictoke:BAAANQAECgYJEAAAAA==.Malokai:BAAANQADCgUIBQAAAA==.Malvina:BAAANQADCgcIBwAAAA==.Marohen:BAAANQADCgYIBgAAAA==.Maronie:BAABNQAECoEWAAMRAAcKshz4FwDOAQARAAYKyBv4FwDOAQAeAAIK/AmOWgBDAAAAAA==.Martinia:BAAANQABCgQIBgAAAA==.Mauzer:BAAANQADCggIFAABNQAECgYIDgAPAAAAAA==.Mauzii:BAAANQADCgMIBAABNQAECgYIDgAPAAAAAA==.Mazìkeen:BAAANQADCgMIAwAAAA==.',
Mc='Mcksquizy:BAABNQAECoEbAAIcAAgKACFwHgC3AgAcAAgKACFwHgC3AgAAAA==.',
Me='Melliah:BAAANQAECgIIAgAAAA==.Mes:BAAANQAECgYIEgAAAA==.Metatrøn:BAAANQADCgcIBwAAAA==.',
Mi='Mimmi:BAAANQAECgUICwABNQAECgYIDgAPAAAAAA==.Misaligned:BAAANQAECgUIBwAAAA==.Misidian:BAAANQADCgQJBAAAAA==.',
Mo='Monbonestorm:BAAANQADCgIIAgABNQAECgkJGgAFACkVAA==.Moonsorrow:BAAANQAECgYIBwAAAA==.Moritura:BAAANQAECgYIDgAAAA==.',
My='Mywifesaidno:BAAANQADCgYIBgAAAA==.',
Na='Naklek:BAAANQAECgUJBwAAAA==.',
Ne='Nemistrasza:BAAANQADCggICwABNQAECgYIEwAPAAAAAA==.',
Ni='Nilanza:BAAANQADCgcIBwABNQAECggIHwAIAPUgAA==.Niraleth:BAAANQADCgMIAwAAAA==.',
No='Nodejs:BAAANQADCggIDAAAAA==.Nolan:BAAANQAECgEIAQABNQAECgQJBAAPAAAAAA==.Nottreebeard:BAAANQAECgIIAgABNQAECggIGwAYAKETAA==.',
Ob='Obergefel:BAAANQAECgEIAQAAAA==.',
Ol='Ollie:BAAANQABCgYIDAAAAA==.',
Op='Ophiuchus:BAAANQAECgYICwAAAA==.',
Or='Orcdung:BAAANQABCgUIDAAAAA==.',
Os='Ostpeppar:BAAANQADCgUIBwAAAA==.',
Pa='Paldente:BAAANQAECgYIBwAAAA==.Pamelina:BAAANQABCgEIAQAAAA==.Pandaexpress:BAAANQADCgUIBQABNQAECgkJKAAIAKkYAA==.Pangando:BAAANQAECgEIAQAAAA==.Panzerfäust:BAAANQAECgYIDQAAAA==.Pastareefa:BAAANQADCgQIBAAAAA==.',
Pe='Peacebeme:BAAANQADCggIGQAAAA==.Pernicious:BAAANQAECgQIBwAAAA==.',
Ph='Phillis:BAAANQADCgUIBQAAAA==.Philster:BAAANQADCgUICQAAAA==.Physics:BAEANQAFFAIIAgAAAA==.',
Pi='Pilfering:BAAANQAECgQICwAAAA==.Pinkiemena:BAAANQAFFAEIAQAAAA==.',
Po='Potent:BAAANQABCgMIAwAAAA==.',
Pu='Punchykicky:BAAANQAECgQIBwABNQAECgcIIAAOAPccAA==.',
Py='Pyria:BAAANQADCgUIBwAAAA==.',
['Pé']='Pérrywinklé:BAAANQAECgcIDwAAAA==.',
Ra='Rathus:BAAANQAECgMIBAAAAA==.',
Re='Rebeka:BAAANQAECgYIDgAAAA==.Reginnx:BAAANQAECgUIBQAAAA==.Reniel:BAAANQABCgIIAQABNQAECgYIEwAPAAAAAA==.Reverendlion:BAAANQAECgUICQAAAA==.',
Rh='Rhattice:BAAANQABCgYICAAAAA==.',
Ro='Rogosh:BAAANQAECgYIDQAAAA==.Rosencrant:BAAANQAECgUICwAAAA==.',
Ru='Rule:BAAANQAECgIIAgAAAA==.',
Ry='Ryblade:BAAANQAECgMIAwABNQAECgkJIgASAOAXAA==.',
['Rè']='Règekt:BAAANQAECggICAAAAA==.',
Sa='Saiko:BAABNQAECoEjAAIfAAgKFhrWBwBUAgAfAAgKFhrWBwBUAgAAAA==.Sainthealz:BAAANQABCgQIBgAAAA==.Sampal:BAABNQAECoEgAAIOAAcK9xx1FQAuAgAOAAcK9xx1FQAuAgAAAA==.Samwield:BAEBNQAECoEsAAMgAAkKEBzECgC6AgAgAAgKeR3ECgC6AgAYAAMKThPYZADPAAAAAA==.Sanjana:BAAANQADCgQJBAAAAA==.',
Se='Seirei:BAAANQADCgQIBAAAAA==.Seireitei:BAAANQAECgYIEwAAAA==.Selaheal:BAABNQAECoEeAAIaAAcKmA2zLgCHAQAaAAcKmA2zLgCHAQAAAA==.',
Sh='Shadowskull:BAAANQADCgMIAwAAAA==.Shadowsun:BAAANQADCgYIBgAAAA==.Shadwkllr:BAAANQADCgYIBgAAAA==.Shinobu:BAAANQADCgYICgABNQAECgcIEwAPAAAAAA==.Shnood:BAAANQAECgYIDgAAAA==.Shnordora:BAAANQADCgIIAgAAAA==.Shrapnell:BAAANQABCgIIAgAAAA==.Shwager:BAAANQADCgcICAAAAA==.',
Si='Sinedariliel:BAAANQADCgUIBQAAAA==.Sinister:BAABNQAECoEqAAMhAAkKKB76CwATAwAhAAkKKB76CwATAwAfAAEKAgHZMgAUAAAAAA==.',
Sk='Skies:BAAANQADCgYIBgABNQAFFAMIBQAZAPEMAA==.',
Sr='Srprotozoic:BAAANQADCgMIAwAAAA==.',
Ss='Ssteroidss:BAAANQAECgEIAQAAAA==.',
St='Stabbem:BAAANQADCggIDwABNQAECgYIEwAPAAAAAA==.Stersèbuk:BAAANQADCgIIAgABNQAECgkJIAAHAPEaAA==.Sterïzard:BAAANQADCgEIAQABNQAECgkJIAAHAPEaAA==.Stupid:BAABNQAECoElAAITAAkK5h6rFQAWAwATAAkK5h6rFQAWAwAAAA==.Stærk:BAABNQAECoEgAAIHAAkK8RrBJADTAgAHAAkK8RrBJADTAgAAAA==.',
Su='Subwai:BAAANQAECggIDQAAAA==.Sukunå:BAAANQADCgMIBAABNQAECgkJJwAFAKweAA==.Sunpally:BAABNQAECoEfAAITAAcKBhLDbQCnAQATAAcKBhLDbQCnAQAAAA==.Suvulaan:BAAANQAECgUICwAAAA==.',
Sw='Swisscheese:BAAANQADCgUIBQAAAA==.',
Ta='Tamarlane:BAAANQABCgIIAgAAAA==.Tancacy:BAAANQADCgcICwAAAA==.Tatoo:BAABNQAECoEpAAIUAAgKcSFFGwASAwAUAAgKcSFFGwASAwAAAA==.',
Te='Teeice:BAABNQAECoEkAAIYAAkKixcdGQCLAgAYAAkKixcdGQCLAgAAAA==.Teo:BAABNQAECoEZAAIaAAcKZg/ALACXAQAaAAcKZg/ALACXAQAAAA==.',
Th='Thekan:BAAANQAECgYIDwAAAA==.Theriot:BAABNQAECoEeAAMOAAgKJx7fDwB5AgAOAAgKJx7fDwB5AgASAAIKNhgCQQF0AAAAAA==.Thianá:BAAANQAECgEIAQAAAA==.',
Ti='Tinkerspell:BAAANQADCgUIBQABNQAECgcIGQAMALkfAA==.',
Tl='Tlitlitzin:BAAANQAECgMICgAAAA==.',
To='Toosus:BAACNQAFFIENAAINAAUKTRo7CQCcAQANAAUKTRo7CQCcAQA1AAQKgScAAg0ACQrMI4QIAGoDAA0ACQrMI4QIAGoDAAAA.Totemsnhoes:BAAANQAECgEIAQAAAA==.',
Tr='Tralanoth:BAAANQADCgEIAQAAAA==.Treskel:BAAANQAECgEJAQAAAA==.Trolldung:BAAANQADCgQIBwAAAA==.',
Tt='Tturtle:BAABNQAECoElAAISAAkKWBvfUQB3AgASAAkKWBvfUQB3AgAAAA==.',
Tw='Twoblock:BAAANQADCgcIBgAAAA==.',
Um='Umisle:BAAANQAECgEIAQAAAA==.',
Un='Unclebuck:BAAANQABCgYIDgAAAA==.Unholysam:BAEANQAECgEIAQABNQAECgkJLAAgABAcAA==.',
Va='Vallo:BAAANQADCgEIAQAAAA==.',
Ve='Velata:BAABNQAECoEjAAIEAAgKnhHnCgDjAQAEAAgKnhHnCgDjAQAAAA==.Vesselette:BAAANQADCggICAAAAA==.',
Vi='Victory:BAAANQAECgEIAgAAAA==.Violencê:BAABNQAECoEaAAIQAAcKyhl7CQAXAgAQAAcKyhl7CQAXAgAAAA==.Virus:BAAANQADCgcIBwAAAA==.',
Vo='Voidedge:BAAANQAECgMIAwAAAA==.',
Vy='Vynivar:BAAANQAECgIIAgAAAA==.',
We='Wes:BAABNQAECoEWAAIYAAYKtxAEQACJAQAYAAYKtxAEQACJAQAAAA==.',
Wi='Wildlettuce:BAAANQADCgEIAQAAAA==.Willowthorn:BAABNQAECoEfAAIUAAgKQhvFQgB+AgAUAAgKQhvFQgB+AgAAAA==.Willybcastin:BAABNQAECoEUAAIFAAkKvxytWgC4AgAFAAkKvxytWgC4AgABNQAFFAYIEAAcAHUfAA==.Willybwankin:BAACNQAFFIEQAAIcAAYKdR+7AQAhAgAcAAYKdR+7AQAhAgA1AAQKgSsAAhwACQrVJtYCAL8DABwACQrVJtYCAL8DAAAA.',
Wo='Wowgazm:BAAANQAECgYIEAAAAA==.',
Wr='Wrongchat:BAAANQADCgcIBwAAAA==.',
Wy='Wyvern:BAAANQAECgYIEAAAAA==.',
Xa='Xanstar:BAAANQADCgQIBAAAAA==.',
Xe='Xerath:BAAANQAECgEIAQAAAA==.',
Yo='Yogami:BAAANQABCgIIAgAAAA==.',
Za='Zacarly:BAAANQAECgEIAQAAAA==.Zalarian:BAABNQAECoEiAAISAAkKgCFNFwBUAwASAAkKgCFNFwBUAwAAAA==.',
Ze='Zemos:BAAANQADCgYIDQAAAA==.Zeseroth:BAAANQADCgYICQAAAA==.Zeserotho:BAACNQAFFIENAAIeAAUKJByPBAC8AQAeAAUKJByPBAC8AQA1AAQKgSQAAh4ACQqZIFEPANICAB4ACQqZIFEPANICAAAA.',
Zh='Zhaelynne:BAAANQADCggICAAAAA==.',
Zu='Zugg:BAABNQAECoEoAAMOAAkKJxlUFgAjAgAOAAgKkRlUFgAjAgATAAUKvhPmiABXAQABNQAECgkJKgAhACgeAA==.',
['Éi']='Éireann:BAAANQAECgEIAQAAAA==.',
['Ðu']='Ðumpy:BAAANQAECgYIDwAAAA==.',
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
