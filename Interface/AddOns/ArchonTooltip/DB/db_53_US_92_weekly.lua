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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Warlock-Destruction','Warrior-Arms','Shaman-Restoration','Warrior-Fury','DemonHunter-Havoc','Mage-Arcane','Warlock-Affliction',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abrakådabruh:BAAANQAECgEIAQAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAAANQAECgUIBQAAAA==.',
Ai='Ainjel:BAAANQADCgUICQAAAA==.Ainz:BAAANQADCgMIBAAAAA==.',
Ak='Akaitsuki:BAAANQAECgEIAQAAAA==.',
Al='Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwABAAAAAA==.',
Am='Amarantus:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Ammerie:BAAANQADCgUIBQAAAA==.',
An='Anmodru:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAAANQAECgYICwAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Ardênt:BAAANQADCgEIAQAAAA==.Aridhol:BAAANQAECgEIAQAAAA==.Arradrius:BAAANQAECgQIBAAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAAANQADCgYIDQAAAA==.',
At='Athená:BAAANQAECgEIAQAAAA==.Athenä:BAAANQAECgYICgAAAA==.',
Au='Aubrii:BAAANQADCgUIBwAAAA==.',
Az='Azeloth:BAAANQADCgUIBgAAAA==.',
Ba='Baladeva:BAAANQAECgEIAQAAAA==.Banaritaz:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Barbaricboss:BAAANQADCgcIBwAAAA==.Barrak:BAAANQAECgQIBgABNQAECgUIBQABAAAAAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAAANQAECgMIAwAAAA==.Beersnob:BAAANQAECgIIAgAAAA==.',
Bh='Bhis:BAAANQADCgMIAwAAAA==.',
Bi='Bigmikeyg:BAAANQADCggIFQAAAA==.Bigsteve:BAAANQAECgEIAQAAAA==.',
Bl='Blanket:BAAANQAECgYICwAAAA==.Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Boomchickun:BAAANQABCgIIAgABNQAECggIFgACAOkaAA==.',
Br='Brickley:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAAANQADCggIFwAAAA==.',
['Bø']='Bønd:BAAANQADCgYIBgAAAA==.',
Ca='Caicos:BAEANQAECgYICwAAAA==.Calizon:BAAANQADCggIFQAAAA==.Canowhoopass:BAAANQAECgEIAQAAAA==.',
Ce='Cell:BAAANQAFFAIIAgAAAA==.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAABNQAECoEWAAICAAgJ6RotCwDAAgACAAgJ6RotCwDAAgAAAA==.Cereas:BAAANQAECgEIAQAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Choofz:BAAANQADCggIEAAAAA==.Chulk:BAAANQADCgcIDAAAAA==.',
Cl='Cloud:BAAANQAECgUIBgAAAA==.Clukdogg:BAAANQAECggIEAAAAA==.',
Co='Combination:BAABNQAECoEXAAIDAAkJQBn+AgDqAgADAAkJQBn+AgDqAgAAAA==.Corvenall:BAAANQAECgIIAwAAAA==.',
Cr='Crashpad:BAAANQADCgcIBgAAAA==.Crossbow:BAAANQAECgYIDQAAAA==.',
Da='Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danidani:BAAANQAECgQICAAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICAAAAA==.Davinah:BAAANQAECgQIAwAAAA==.Dayje:BAAANQADCgIIAgAAAA==.',
De='Deathation:BAAANQADCgUIBQAAAA==.Deathbcmesyu:BAAANQAECgEIAQAAAA==.Demonovest:BAAANQAECgEIAQAAAA==.',
Di='Diehappy:BAAANQADCgUICQAAAA==.Dishonor:BAAANQADCgMIAwAAAA==.',
Do='Dommage:BAAANQAECgQIBAABNQAECgcIEQABAAAAAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAAANQAECgIIAgAAAA==.Drywar:BAABNQAECoEQAAIEAAgJUSAwEwDwAgAEAAgJUSAwEwDwAgAAAA==.Dràgonkíng:BAAANQADCgYIDwAAAA==.',
Dt='Dtinnel:BAAANQADCgMIAwABNQAECgcIDgABAAAAAA==.',
['Dà']='Dànger:BAAANQAECgIIAgAAAA==.',
Eg='Ego:BAAANQAECgMIBAAAAA==.',
Ei='Eisla:BAAANQAECgIIAwAAAA==.',
Em='Emmone:BAAANQADCgMIAwAAAA==.',
Ex='Exacerbator:BAAANQADCgYIDAAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Faunna:BAAANQAFFAEIAQAAAA==.',
Fe='Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAAANQADCggIEAAAAA==.Felaz:BAAANQAECgQIBQAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.',
Fi='Fingerguns:BAAANQAECgUICgAAAA==.',
Fl='Floortank:BAAANQADCggIFAAAAA==.',
Fr='Friday:BAAANQAECgIIAgAAAA==.Frikilatar:BAAANQABCgQICAAAAA==.Frrank:BAABNQAECoEQAAIEAAgJIiYCBwB6AwAEAAgJIiYCBwB6AwAAAA==.',
Ga='Galcain:BAAANQAECgYIBgAAAA==.',
Go='Googleyes:BAAANQADCgMIBAAAAA==.Goss:BAAANQADCgIIAgAAAA==.',
Gr='Graphene:BAAANQADCgEIAgAAAA==.Greybull:BAAANQAECgQIBAAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAAANQAECgEIAQABNQAECgkJFwADAEAZAA==.Growlyr:BAAANQAECgYICAAAAA==.Grumandel:BAAANQAECgEIAQAAAA==.',
Ha='Hakur:BAAANQAECgQIBQAAAA==.Hammertóe:BAAANQADCggIEwAAAA==.Hanma:BAAANQAECgQICgAAAA==.Harribel:BAAANQAECgEIAQAAAA==.',
He='Heiferina:BAAANQADCgMIAwAAAA==.Helixra:BAAANQAECgIIAgAAAA==.',
Hi='Hitachitotem:BAAANQAFFAMIAgAAAA==.',
Hy='Hyperíon:BAAANQADCgYICwAAAA==.',
Ic='Icies:BAAANQAECgQIBgAAAA==.',
Is='Ishamaël:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.',
Jc='Jclif:BAAANQAECgMIAwAAAA==.',
Je='Jehannum:BAAANQAECgEIAQAAAA==.Jessira:BAAANQAECgQIBwAAAA==.',
Jo='Jonahheal:BAAANQADCgcIBwABNQAECgkJGAAFALokAA==.Josen:BAAANQAECgEIAQAAAA==.',
Ka='Kaimi:BAAANQADCgQICQAAAA==.Kainiy:BAAANQADCgUICwAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAAANQAECgQIBAAAAA==.Katarena:BAAANQAECgEIAgAAAA==.Kathyra:BAEANQAECgMIAwABNQAECgYICwABAAAAAA==.Kavax:BAAANQADCggIFAAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgEIAQAAAA==.Keleris:BAAANQADCgUIBQAAAA==.Kentyr:BAAANQADCgEIAQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQADCgUIBQAAAA==.',
Ki='Kinký:BAAANQAECgQIBgAAAA==.Kiraelis:BAAANQAECgIIAgAAAA==.',
Ko='Korvoh:BAAANQAECgEIAQAAAA==.',
Kr='Kredriel:BAAANQADCgcICgAAAA==.Krinmate:BAAANQAECggIEgAAAA==.Krystn:BAAANQADCgQIBwAAAA==.',
Ku='Kuurome:BAAANQADCgMIAwABNQAECgcIDgABAAAAAA==.',
Kw='Kwinny:BAAANQAECgEIAQAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynthria:BAAANQAECgYIDQAAAA==.',
['Kä']='Kämik:BAAANQAECgEIAQAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAAANQAECgMIAwAAAA==.Lasstchance:BAAANQADCgUICQAAAA==.Latinamaddog:BAAANQAECgMIAwAAAA==.',
Le='Leijona:BAAANQADCgUICAAAAA==.Lenard:BAAANQADCgYIFAAAAA==.',
Li='Likeatrain:BAAANQAECgEIAQAAAA==.Linds:BAAANQAECgUIBQAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.',
Lt='Ltdanslegs:BAAANQAECgYICgAAAA==.',
Lu='Luxu:BAAANQAECgYICAAAAA==.Luxzy:BAAANQADCgYICwAAAA==.',
Ma='Makarich:BAAANQAECgQIBAAAAA==.Malachron:BAAANQAECgEIAQAAAA==.Manbearcat:BAAANQADCggIEwAAAA==.Marbleous:BAAANQAECgUICAAAAA==.',
Mc='Mcpink:BAAANQADCgUIBAABNQADCggIEwABAAAAAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Melancholic:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Memisstotem:BAAANQAECgEIAQAAAA==.Merle:BAABNQAECoEXAAMEAAgJCBdYJgBcAgAEAAgJMRZYJgBcAgAGAAUJZxkPBwBjAQAAAA==.',
Mi='Minaxy:BAAANQAECgYICwAAAA==.Mistborn:BAAANQAECgUIBgAAAA==.Mistsofpoly:BAAANQADCgUICQABNQAECgcIDwABAAAAAA==.',
Mo='Momoku:BAAANQADCggIEQAAAA==.Moolimbo:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Mootalstrike:BAAANQAECgUIBQAAAA==.Moshworm:BAAANQAECgQIBgAAAA==.',
Mv='Mvp:BAAANQADCgUIBQAAAA==.',
Ne='Nelaphim:BAAANQAECgUIBQAAAA==.Nexassin:BAAANQAECgEIAQAAAA==.',
Ni='Nico:BAAANQADCggIFQAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAAANQAECgMIAwAAAA==.',
No='Noctrine:BAAANQABCgYICQAAAA==.Noxxidari:BAAANQAECgQIBwAAAA==.Noxxus:BAAANQAECgIIAgAAAA==.',
Ny='Nymphis:BAAANQADCgMIAwAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.',
Ob='Oblivia:BAAANQADCgQIBAAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.',
Or='Orchist:BAAANQADCggIFAAAAA==.Orimbo:BAAANQAECgMIAwAAAA==.',
Pa='Paidu:BAABNQAECoETAAMCAAgJ8QsZGgDfAQACAAgJ8QkZGgDfAQAHAAMJNA6hKQClAAAAAA==.Palaritaz:BAAANQAECgIIAwABNQAECgUIBgABAAAAAA==.',
Pe='Pestilancé:BAAANQAECgEIAQAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQABCgYIBgAAAA==.Pitchblende:BAAANQAECgMIAwAAAA==.',
Pr='Prangkim:BAAANQADCgMIBAAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQADCgYIBgAAAA==.',
Qu='Quillz:BAAANQADCgYIBgAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAAANQAECggIEQAAAA==.',
Re='Redine:BAAANQADCgQIBQAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQADCgUICQAAAA==.Rendis:BAAANQAECgEIAQAAAA==.',
Rh='Rhayge:BAAANQAECgEIAQAAAA==.',
Ru='Ruukia:BAAANQAECgcIDgAAAA==.',
Sa='Saboo:BAAANQADCggIEAAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Sapientia:BAAANQAECgIIAQAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAECgkJGQAIADAfAA==.',
Se='Seasnan:BAAANQADCgYIDAAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgEIAQAAAA==.Senlock:BAAANQABCgIIAgABNQAECgMIAwABAAAAAA==.',
Sh='Shadowdeath:BAAANQAECgIIAwAAAA==.Shadowheàrt:BAAANQADCgcIDwAAAA==.Shadowshifty:BAAANQADCgcIBwAAAA==.Shadowtotem:BAAANQADCgcICwAAAA==.Shamdü:BAAANQAECgcIDAAAAA==.Shanson:BAAANQAECgIIAgAAAA==.Sharroz:BAAANQAECgEIAgAAAA==.Shizuuku:BAAANQADCgEIAQABNQAECgcIDgABAAAAAA==.Shockybalboa:BAAANQADCggICAAAAA==.Showerthots:BAAANQADCgYICwAAAA==.',
Si='Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAAANQAECgUIBgAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAAANQAECgMIAwAAAA==.Skyknight:BAAANQAECgIIAgAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQADCgYIDQAAAA==.',
So='Solcon:BAAANQAECgEIAQAAAA==.Solence:BAAANQADCgEIAQAAAA==.Somebodie:BAAANQADCgQIBQAAAA==.',
Sp='Spaazz:BAAANQAECgIIAwAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Starweaver:BAAANQAECgIIAgAAAA==.Stormrender:BAAANQAECgMIAwAAAA==.Stormsong:BAAANQAECggIDgAAAA==.Strangecandy:BAAANQAECgEIAQAAAA==.Strángeland:BAAANQADCgEIAQAAAA==.Störmrender:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.',
Su='Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAAANQAECgIIAgAAAA==.Superpull:BAAANQAECgUIBQABNQABCgIIAgABAAAAAA==.',
Sy='Sycla:BAAANQAECgQIBwAAAA==.Sylas:BAAANQADCggIEAAAAA==.',
Ta='Taloriesh:BAAANQAECgIIAwAAAA==.Tanazir:BAEANQAECgEIAQAAAA==.Tarok:BAAANQADCgEIAQAAAA==.Tashien:BAAANQADCgUIBAAAAA==.',
Te='Tealzin:BAAANQABCgQIBAAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgMIBQAAAA==.Terenii:BAAANQADCggIBwAAAA==.',
Ti='Tilamano:BAAANQAECgYICQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgYICQABAAAAAA==.',
To='Tohrnarc:BAAANQAECgUIBwAAAA==.Tookkiiee:BAAANQADCggICAAAAA==.Totem:BAAANQAECgIIAgAAAA==.Totemwebz:BAAANQADCgcIDAAAAA==.',
Tr='Trenve:BAAANQAECgMIAwAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAAANQAECgMIAwAAAA==.',
['Té']='Téchymoon:BAABNQAECoENAAIDAAgJWg0WDAD9AQADAAgJWg0WDAD9AQAAAA==.',
Ug='Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAAANQAECgYICwAAAA==.',
Un='Undertaker:BAAANQABCgUICAAAAA==.',
Va='Valcristo:BAAANQAECgUIBQAAAA==.Valdun:BAAANQADCgUICQAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.Vargrim:BAAANQAECgMIBAAAAA==.',
Ve='Venous:BAAANQAECgUIBQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAAANQAECggIDgAAAA==.Viduus:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Viv:BAAANQAECgIIAgAAAA==.',
Vo='Vodmor:BAAANQAECgEIAQAAAA==.Voldermort:BAAANQADCgYIDAAAAA==.',
Wa='Warrendemon:BAABNQAECoENAAICAAgJVCH8CgDEAgACAAgJVCH8CgDEAgAAAA==.',
Wh='Whims:BAAANQADCgUIBQAAAA==.',
Wo='Woregontail:BAAANQADCgQIBgAAAA==.Wowbelly:BAAANQADCgQIBQAAAA==.',
Xa='Xandros:BAAANQAECgEIAQAAAA==.',
Xo='Xonk:BAABNQAECoETAAIJAAgJUxhLAQB2AgAJAAgJUxhLAQB2AgAAAA==.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgYICgAAAA==.',
Za='Zalagrimbor:BAAANQAECgYICwAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAAANQAECgMIAwAAAA==.Zarev:BAAANQAECggIEwAAAA==.',
Ze='Zelie:BAAANQAECgUIBQAAAA==.Zenreto:BAAANQAECgEIAQAAAA==.',
Zo='Zoeri:BAAANQABCgIIAgAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAAANQAECgcIEgAAAA==.',
['Ïn']='Ïnsane:BAAANQAECgIIAgAAAA==.',
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
