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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Druid-Guardian','Druid-Balance','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Protection','Paladin-Holy','DeathKnight-Frost','Warlock-Demonology','Warlock-Affliction',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aastrid:BAAANQABCggIDgAAAA==.',
Ad='Adorabúll:BAAANQADCgEIAQAAAA==.',
Ae='Aevriia:BAAANQADCgIIAgAAAA==.',
Al='Aldric:BAAANQADCgIIAgAAAA==.Althenzdormu:BAAANQAECgMJBgAAAA==.Altruist:BAAANQAECgMJBQABNQAECgUJCgABAAAAAA==.',
Am='Amaethon:BAAANQAECgQJBAAAAA==.',
An='Ancaera:BAAANQADCggIDQAAAA==.Andalikus:BAAANQAECgUJCwAAAA==.Andorra:BAAANQADCgMJBQAAAA==.Anrien:BAAANQAECgQICQAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQIBgAAAA==.',
At='Atriste:BAAANQAECgUJCgAAAA==.',
Au='Aunyx:BAAANQAECgUJCQAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYJBgABNQAECgUJCgABAAAAAA==.',
Be='Beej:BAAANQAECgYIDQAAAA==.',
Bi='Biggooch:BAAANQAECgQIBAAAAA==.Bison:BAAANQADCgcJBwAAAA==.',
Bl='Blackrose:BAAANQADCgUIBwABNQAECgMIBQABAAAAAA==.Blightbeard:BAAANQAECgMIAwAAAA==.Blîss:BAAANQAECgIJAgAAAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAAANQAECgQIBwABNQAECgcJEAABAAAAAA==.',
Bu='Bumpy:BAAANQADCggICAAAAA==.Bustus:BAAANQAECgUJCQAAAA==.',
Ca='Calinia:BAAANQABCgMIAwAAAA==.Carole:BAABNQAECoEXAAMCAAcKix2fIABfAgACAAcKix2fIABfAgADAAQKYRTyZADbAAAAAA==.Caroll:BAAANQAECgcJEAAAAA==.Carsomavra:BAAANQADCgIJBAAAAA==.Cathercy:BAAANQAECgQJBQAAAA==.',
Ch='Cherub:BAAANQADCggICAAAAA==.Chrollo:BAAANQAECgMJBgAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgAAAA==.',
Co='Corannis:BAAANQAECgUJCgAAAA==.Corax:BAAANQADCgQIBgAAAA==.',
Cr='Cranberries:BAAANQAECgEIAQABNQAECgkJHQAEAGkJAA==.Cravedog:BAABNQAECoEkAAMFAAcKgiOvBADNAgAFAAcKgiOvBADNAgAGAAMK9Qu9aACZAAAAAA==.Creepi:BAAANQAECgQJBQAAAA==.Cromgabhar:BAAANQADCgYJBgABNQAECgQJBQABAAAAAA==.',
Cu='Cupcáke:BAAANQAECgQIBgAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Damaso:BAAANQADCgcIBwAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darku:BAAANQAECgUJCQAAAA==.Darlàrk:BAAANQAECgMIAwAAAA==.',
De='Delderach:BAAANQAECgQJBQAAAA==.Denin:BAAANQAECgQJBQAAAA==.',
Di='Dirkette:BAAANQAECgUJBwAAAA==.',
Dk='Dkxsmurfx:BAAANQADCgYICAAAAA==.',
Do='Dokai:BAAANQAECgUJCgAAAA==.',
Dr='Dracmiz:BAAANQADCgcJCAAAAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBAAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgcJEAABAAAAAA==.',
El='Elaenei:BAAANQADCgYJBgAAAA==.Eliance:BAAANQAECgQJBQAAAA==.Elienn:BAAANQADCgQJCwAAAA==.',
Er='Errius:BAAANQAECgUJCgAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECgYJCwABAAAAAA==.',
Eu='Eunja:BAEANQADCgcIDAAAAQ==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.',
Fi='Filharmonic:BAAANQADCgUJEQAAAA==.',
Fo='Foid:BAABNQAFFIEGAAMHAAMKCBqDAAAlAQAHAAMKCBqDAAAlAQAIAAEKWA12JABEAAABNQAFFAMKBgAHAAgaAA==.',
Fu='Furiah:BAAANQADCgYJCwAAAA==.Fusaa:BAAANQAECgYIEgAAAA==.',
Ga='Gahzoo:BAAANQADCgYJCQAAAA==.Garretjax:BAAANQADCgYJDQAAAA==.Garuda:BAAANQAECgQJBAAAAA==.',
Ge='Gelst:BAAANQADCgQJCwAAAA==.Gerbzarrion:BAAANQAECgQJBQAAAA==.Getherdone:BAAANQADCgIIAwAAAA==.',
Gi='Gilgador:BAAANQAECgUJBgABNQAECgYICwABAAAAAA==.',
Gr='Grassfed:BAAANQADCgcJBgAAAA==.',
Ha='Hawknnib:BAAANQAECgQJBQAAAA==.',
Ho='Hothala:BAAANQADCgYIDwAAAA==.',
Hu='Hunterpulled:BAABNQAECoEpAAIJAAgKBBJxRgAhAgAJAAgKBBJxRgAhAgAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAAANQAECgIIAgAAAA==.',
Ip='Ipwnallnoobs:BAAANQAECgQICAAAAA==.',
Ir='Irisila:BAAANQADCggIEwABNQAECgEIAgABAAAAAA==.',
Ja='Jaskilz:BAAANQADCgQJBgAAAA==.Jaypharyn:BAAANQAECgMJBQAAAA==.Jazel:BAAANQADCgQJBQAAAA==.',
Jo='Johalea:BAAANQADCgQJCwAAAA==.',
Ju='Juliå:BAAANQADCgQJBwAAAA==.',
['Jå']='Jåsper:BAAANQAECgMJBgAAAA==.',
Ka='Kaileena:BAAANQAECgQJCgAAAA==.Kandistars:BAAANQAECgUICgAAAA==.Kasia:BAAANQAECgMJBgAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJGgAKACIeAA==.',
Ki='Kieler:BAAANQAECgEJAQAAAA==.Kierrings:BAAANQAECgQJAwAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAAANQAECgUJCgAAAA==.',
Kl='Klauss:BAAANQAECgUJDAAAAA==.Klax:BAAANQADCgYJBgAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgEIAQABAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAAANQAECgUJDAAAAA==.',
Le='Legenddairy:BAABNQAECoEXAAIFAAcK7hU4DQDFAQAFAAcK7hU4DQDFAQAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAAANQAECgYJDwAAAA==.',
Lo='Lochramae:BAAANQAECgQJBQAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAABNQAECoEfAAMLAAgKOxvQEwCFAgALAAgKNhrQEwCFAgAMAAQKGR6TMwBjAQAAAA==.',
['Lâ']='Lâriel:BAAANQAECgQJBQAAAA==.',
Ma='Madmartigan:BAAANQAECgQJBQAAAA==.Mamimisan:BAAANQAECgEJAwAAAA==.',
Me='Mechadockie:BAAANQAECgMIAwAAAA==.',
Mi='Mirah:BAAANQADCgMIAwAAAA==.Mistazee:BAAANQAECgEJAQAAAA==.Mizan:BAAANQAECgYIBwAAAA==.Mizeroni:BAABNQAECoEaAAMNAAkKUBlDCQClAgANAAkKUBlDCQClAgAOAAEKjARM0gA2AAAAAA==.Mizkat:BAAANQADCgcIAQABNQAECgkJGgANAFAZAA==.Mizky:BAAANQADCgQJBAAAAA==.',
Mo='Mormra:BAAANQADCgcIGAAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgAAAA==.',
['Më']='Mërcy:BAAANQADCgQJBwAAAA==.',
Na='Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAAANQAECgYICwAAAA==.Neropoison:BAAANQADCgIIAwAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgMJAwAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.',
On='Onomirigaru:BAAANQAECgUJDAAAAA==.',
Ox='Oxygentank:BAAANQADCggICgAAAA==.',
Pi='Pips:BAAANQADCgYIBgABNQAECgUJDwABAAAAAA==.',
Pl='Platura:BAAANQAECgUJCgAAAA==.',
Pv='Pvp:BAAANQADCgMJAwAAAA==.',
Ra='Raezune:BAAANQABCgYICwAAAA==.Rajia:BAAANQAECgUJCgAAAA==.Ranron:BAAANQAECgEJAQAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECgIJAgABAAAAAA==.',
Re='Reapin:BAAANQAECgMJBgAAAA==.Rezeldâ:BAAANQADCgUJCgAAAA==.',
Rh='Rhaegalsh:BAAANQAECgYJCgAAAA==.',
Ri='Rionach:BAAANQAECgUJCgAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ru='Runeneya:BAAANQAECggJBwAAAA==.',
Sa='Sangle:BAAANQADCgEIAQAAAA==.',
Sc='Schtzngigllz:BAAANQADCgQIBAABNQADCgcIGAABAAAAAA==.Scoop:BAAANQAECgUICAAAAA==.',
Se='Seanan:BAAANQAECgYIEgAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECoEXAAIOAAgKBgZ2XwB4AQAOAAgKBgZ2XwB4AQAAAA==.',
Sh='Shammwow:BAAANQAECgEIAgAAAA==.Shamoo:BAAANQAECgYIBgAAAA==.Shaudis:BAAANQAECgYJCwAAAA==.Shiftyshape:BAAANQAECgEJAQAAAA==.Shigurexx:BAAANQAECgUICgAAAA==.Shoe:BAAANQAECgYIEAAAAA==.Shootup:BAAANQADCgQJCQAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAAANQAECgUICgAAAA==.Sonashee:BAAANQAECgcIDQAAAA==.Sorender:BAAANQADCgUIBQAAAA==.',
St='Steelbutt:BAAANQADCgcJDwAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDQABAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAAANQAECgMJBgAAAA==.Tappy:BAAANQAECgYJEAAAAA==.',
Te='Terkarakk:BAABNQAECoEbAAIFAAgK+iNzAgBGAwAFAAgK+iNzAgBGAwAAAA==.',
Th='Thirryn:BAAANQAECgUICQAAAA==.Thorybos:BAAANQAECgQIBwAAAA==.',
Ti='Tippy:BAAANQAECgEIAQAAAA==.',
To='Toom:BAAANQAECgQJBQAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAAANQAECgUICgAAAA==.',
Tu='Tuknark:BAAANQADCgQJCwAAAA==.',
Ty='Tyeren:BAAANQAECgUJBgAAAA==.Tyeriel:BAABNQAECoEhAAMPAAkK/hl9GABIAgAPAAgKxBl9GABIAgACAAMKrRRFawDCAAAAAA==.',
Tz='Tzuriel:BAEANQAECgUICwAAAA==.',
Va='Valkyriewing:BAAANQAECgQJBQAAAA==.Valvet:BAAANQADCggIEwAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAAANQAECgUJCwAAAA==.Vincenzo:BAAANQADCgMIBQAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vy='Vylus:BAAANQAECgYJEAAAAA==.',
['Vá']='Vásh:BAAANQAECgUJCgAAAA==.',
We='Webjibaro:BAAANQADCgUJCgAAAA==.Weeblewobble:BAAANQADCgQJCwAAAA==.Weili:BAAANQAECgIJBAAAAA==.',
Wh='Whiney:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAAANQAECgMIAwAAAA==.Windee:BAAANQADCgYICgAAAA==.',
Wr='Wrast:BAAANQAECgUJBAAAAA==.Wravyn:BAAANQAECgUJCgAAAA==.',
Xa='Xalted:BAAANQADCgUJCQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xaylios:BAAANQAECgYJBgAAAA==.',
Xy='Xyara:BAABNQAECoEdAAQKAAkKQQ87IwAyAQAKAAUK/Q47IwAyAQAQAAUKUgzmjAAgAQARAAMKLA+mDwDOAAAAAA==.',
Yo='Yoghurt:BAAANQAECgYJDwAAAA==.',
Yu='Yunlan:BAAANQAECgEIAQAAAA==.',
Za='Zalidus:BAAANQAECgIJAgAAAA==.Zanthor:BAAANQADCggJDQABNQAECggIEwABAAAAAA==.',
Ze='Zehnia:BAAANQABCgcIDAAAAA==.',
Zi='Zibzab:BAAANQAECgQJBQAAAA==.',
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
