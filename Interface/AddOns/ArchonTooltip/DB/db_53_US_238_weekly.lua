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

local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aayrawn:BAAANQAECgEIAQAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAAAAA==.Aceshaman:BAAANQAECgMIBAAAAA==.',
Ai='Airone:BAAANQADCgQIBAAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECgQIBQABAAAAAA==.',
Am='Amaranthe:BAAANQADCggIDAAAAA==.Amrax:BAAANQADCggIFgAAAA==.',
Aq='Aquabat:BAAANQAECgYICgAAAA==.',
As='Ashbringer:BAAANQAECgUIBgAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAAANQAECgEIAQAAAA==.',
Ba='Baladoria:BAAANQAECgYICAAAAA==.Bananabowman:BAAANQADCggICQAAAA==.Banditos:BAAANQADCgQIBAAAAA==.Bartab:BAAANQAECgEIAQABNQADCggIFAABAAAAAA==.',
Be='Bearemy:BAAANQAECgEIAQAAAA==.Beastling:BAAANQAECgEIAQAAAA==.Beau:BAABNQAECoEYAAICAAkJtCGNAgBtAwACAAkJtCGNAgBtAwAAAA==.Beauwi:BAAANQADCgcIDwABNQAECgkJGAACALQhAA==.',
Bi='Bigchungusyo:BAAANQADCgEIAQAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.',
Bo='Bombur:BAAANQAECgEIAQAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.',
Br='Brokenbubble:BAAANQADCgcIBwABNQAECgcIEQABAAAAAA==.Brozown:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.',
Bu='Buzzkill:BAAANQADCggIEwAAAA==.',
Ca='Calinash:BAAANQAECgEIAQAAAA==.Calzraxx:BAAANQAECgQICgAAAA==.Cartons:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.',
Cc='Ccaan:BAAANQAECgIIAgAAAA==.',
Ce='Celinn:BAAANQAECgQIBAAAAA==.',
Ch='Charliek:BAAANQADCggIFQAAAA==.Chimalma:BAAANQAECgQIBQAAAA==.Chorr:BAAANQABCgMIAwABNQAECgUIBQABAAAAAA==.',
Co='Cobygo:BAAANQADCgcIBwAAAA==.Coffins:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Cr='Crates:BAAANQAECgUIBgAAAA==.Cringely:BAAANQAECgUIBQAAAA==.Croakam:BAAANQADCgIIAgABNQAECggIEAABAAAAAA==.Crosswalkk:BAAANQADCgUIBQAAAA==.Cryface:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Da='Darknyss:BAAANQADCgEIAQAAAA==.Darkozygo:BAAANQADCggIEQAAAA==.',
De='Deathfortres:BAAANQADCggIEgAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAAANQAECggIDwAAAA==.Demolish:BAAANQADCggIDgAAAA==.Demongrass:BAAANQAECgcICwAAAA==.Devit:BAAANQAECgEIAQAAAA==.',
Di='Dimka:BAAANQADCggIDwAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAAANQAECgEIAQAAAA==.Diviñehymn:BAAANQADCgYICQAAAA==.',
Do='Doodaad:BAAANQADCgQIBAAAAA==.Doublerack:BAAANQAECgMIAwAAAA==.',
Dr='Dragondznuts:BAAANQAECgcIEQAAAA==.',
Ei='Eilerra:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Er='Erre:BAAANQAECgMIBAAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fo='Foxoffire:BAAANQADCgUICAAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.',
Fr='Fritark:BAAANQAECgMIBAAAAA==.',
Ge='Gena:BAAANQADCgYIEQAAAA==.Geörge:BAABNQAECoEXAAIDAAkJhxshBgANAwADAAkJhxshBgANAwAAAA==.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAAANQADCggIFAAAAA==.',
Gr='Gremfrost:BAAANQAECgYIDQAAAA==.Grotelek:BAAANQAECgMIBAAAAA==.Grumpywaltz:BAAANQAECgEIAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.',
Ha='Haedrath:BAAANQAECgEIAQAAAA==.Hahafunny:BAAANQADCgEIAQAAAA==.Halcotsu:BAAANQAECgQICQAAAA==.Halleko:BAAANQADCggICAABNQAECgkJGQAEAJghAA==.Hammerfoot:BAAANQAECgIIAgAAAA==.Harkknight:BAAANQAECgIIAgAAAA==.Haurtrue:BAAANQAECgEIAgAAAA==.Hawgbawl:BAAANQAECgIIAgAAAA==.Hawgdream:BAAANQAECgIIAQAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAABNQAECoEZAAMEAAkJmCHWAQBQAwAEAAkJ9B7WAQBQAwAFAAYJ2R/lDgAUAgAAAA==.Heyyitzrichh:BAAANQAECgYIDQAAAA==.',
Ho='Hollinar:BAAANQAECgQIBQAAAA==.',
Ih='Ihavecookies:BAAANQADCgUICQAAAA==.',
In='Invaled:BAAANQAECgMIAwAAAA==.',
Ir='Irateknight:BAAANQADCgUIBQAAAA==.',
It='Itzrich:BAAANQAECgQIBAAAAA==.',
Ja='Jakelong:BAAANQAECgQIBgABNQAECgcIEAABAAAAAA==.Jasmirangel:BAAANQAECgcICQAAAA==.',
Je='Jezus:BAAANQABCgYICQAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQAAAA==.',
Ka='Kalzifer:BAAANQAECgQIBQABNQAECgcIDgABAAAAAA==.Kankaladin:BAAANQAECgcIEAAAAA==.Kanky:BAAANQAECgUIBQABNQAECgcIEAABAAAAAA==.Kano:BAAANQAECgYIDwAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kawada:BAAANQADCgcIEgAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAAANQAECgEIAQAAAA==.Kennëdi:BAAANQADCggIHQAAAA==.',
Kh='Khory:BAAANQAECgUIBQAAAA==.',
Ki='Kichirõ:BAAANQAECgQIBQAAAA==.',
Km='Kmt:BAAANQADCggIDgAAAA==.',
Ko='Koffee:BAAANQADCgYICgABNQAECgcIEAABAAAAAA==.Korgigor:BAAANQADCgEIAQAAAA==.',
Kt='Kt:BAAANQADCgcIBwABNQADCggIDgABAAAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
La='Ladezar:BAAANQADCgYIBgAAAA==.Laissen:BAAANQADCgYIDgAAAA==.Lattemocha:BAAANQAECgIIAgAAAA==.',
Le='Leprechauñ:BAAANQAECgQIBwAAAA==.Leprecháun:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAECggIDwABAAAAAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBAAAAA==.Lishalle:BAAANQADCgUIBQAAAA==.',
Lo='Loutone:BAAANQADCgQIBQAAAA==.',
Lu='Ludlow:BAAANQADCggICwAAAA==.Lunatonne:BAAANQAECgEIAQAAAA==.Luneztoprime:BAAANQADCggIEAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIDAAAAA==.',
Ma='Mafi:BAAANQADCgMIAwAAAA==.Mallypally:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Matt:BAAANQAECgcIEgAAAA==.Matte:BAAANQAECgQIBAABNQAECgcIEgABAAAAAA==.Mazza:BAAANQAECgIIAgAAAA==.',
Me='Mewtwô:BAAANQAECgEIAQAAAA==.',
Mi='Miedillø:BAAANQADCgYIBgABNQAFFAMIAwABAAAAAA==.Mikeoxmall:BAAANQAECgYIDgAAAA==.',
Mo='Monstermime:BAAANQAECgEIAQAAAA==.Moosetrax:BAAANQAECgMIBAAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.',
My='Myserie:BAAANQAECgYICAAAAA==.',
Na='Nazara:BAAANQAECgcIEQABNQAECgUIBQABAAAAAA==.',
Ne='Neuro:BAAANQAECgYIEgAAAA==.',
Ni='Nikodemos:BAAANQAFFAIIAgAAAQ==.',
Nk='Nkáujhmóob:BAAANQADCgIIAgAAAA==.',
Oo='Oopsifer:BAAANQAECgIIAwAAAA==.',
Op='Optimum:BAAANQADCgQICwAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pe='Persimmon:BAAANQAECgUICAAAAA==.Peyton:BAAANQADCgQIBAAAAA==.',
Pi='Piecemaker:BAAANQAECgcIEQAAAA==.',
Pl='Plaguepapi:BAAANQADCgIIAgAAAA==.',
Pu='Pufdaddy:BAAANQABCgIIAgAAAA==.Puppetslayer:BAAANQADCggIDAAAAA==.',
Py='Pyrrah:BAAANQAECgMIBAAAAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAAANQAECgYIDAAAAA==.Quezera:BAAANQABCgQIBAAAAA==.',
Ra='Rabuf:BAAANQAECgIIAgAAAA==.Radha:BAAANQAECgUIBQABNQAECggIEgABAAAAAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redizle:BAAANQADCggICAABNQAECgkJGwAGAOwbAA==.Resonance:BAAANQAECgEIAQAAAA==.',
Rh='Rhaenyr:BAAANQADCgYIDwAAAA==.',
Ri='Ridizle:BAABNQAECoEbAAIGAAkJ7BsbBwAaAwAGAAkJ7BsbBwAaAwAAAA==.',
Ro='Rohdoog:BAAANQAECgQIBAAAAA==.',
Ru='Runedyu:BAAANQAECgQICQAAAA==.',
Ry='Ryanno:BAAANQAECggIAgAAAA==.Ryannoo:BAAANQADCgEIAQAAAA==.',
Sa='Sahomi:BAAANQAECgYIDQAAAA==.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQADCgQIBAAAAA==.Sarcini:BAAANQAECgIIAgAAAA==.Sarcisse:BAAANQAECgUIBgAAAA==.Satrina:BAAANQAECgYICQAAAA==.Savvy:BAAANQAECgEIAQAAAA==.',
Se='Senaren:BAAANQADCgUIBQAAAA==.',
Sh='Shagore:BAAANQADCgUICQABNQAECgMIAwABAAAAAA==.Shamander:BAAANQADCggIDgAAAA==.Shameonyou:BAAANQAECgMIBAAAAA==.',
Si='Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgMIAwAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAAANQAECgYIDAAAAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spamnrice:BAAANQAECgQIBAAAAA==.',
Su='Sugars:BAAANQADCgcIDAAAAA==.',
Ta='Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAAANQAECggIEAAAAA==.',
Te='Teostra:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.',
Th='Thedarkduke:BAAANQADCggIEAAAAA==.Thedarkkness:BAAANQADCgYIBgAAAA==.Thorin:BAAANQAECgQIBQAAAA==.Thud:BAAANQAECgYIBwAAAA==.',
Ti='Tidalwave:BAAANQAECgQIBAAAAA==.Timmeh:BAAANQADCggIDwAAAA==.Tindra:BAAANQAECgEIAQAAAA==.Tissue:BAAANQAECgIIAgAAAA==.',
To='Tobibi:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Tolip:BAAANQAECgIIAgAAAA==.Tolipally:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Tolipicious:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Tr='Trevórg:BAAANQAECgQIBAAAAA==.',
Ts='Tsarrubus:BAAANQAECgMIBAAAAA==.',
Tu='Tusck:BAAANQADCgYIDgAAAA==.',
Ul='Ulg:BAAANQAECgYICgAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.',
Ve='Velvet:BAAANQAECgIIAwAAAA==.Vengeanze:BAAANQADCggIDAAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAAANQAECgMIBAAAAA==.',
Wi='Wino:BAAANQADCggIEwAAAA==.Wiqui:BAAANQADCgYIBgAAAA==.',
Wo='Wolfonk:BAAANQAECgcIEQAAAA==.',
Wu='Wuhshake:BAAANQAECgMIAwAAAA==.',
['Wë']='Wërrcs:BAAANQADCgQIBAAAAA==.',
Xe='Xemo:BAAANQAECgMIBQAAAA==.Xenophics:BAAANQAECgcIEQAAAA==.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIBgAAAA==.Zall:BAAANQAECgYICwAAAA==.Zamos:BAAANQAECgEIAQAAAA==.',
Ze='Zenshin:BAAANQADCgYIBwAAAA==.Zentaur:BAAANQAECgEIAQAAAA==.',
Zi='Zitfrlt:BAAANQAECgQIBAABNQAECgcIDgABAAAAAA==.',
Zo='Zontar:BAAANQAECgEIAQAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
['Ål']='Ålucard:BAAANQAECgIIAgAAAA==.',
['ße']='ßeta:BAAANQAECggIBgABNQAECggIDwABAAAAAA==.',
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
