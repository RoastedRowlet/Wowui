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

local lookup = {'Unknown-Unknown','Druid-Balance','Shaman-Enhancement','DemonHunter-Devourer','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Druid-Guardian','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Priest-Discipline','Warrior-Fury','DemonHunter-Havoc','DeathKnight-Blood','Mage-Arcane','Warlock-Affliction','Hunter-Marksmanship',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abrakådabruh:BAAANQAECgQIBAAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAAANQAECgUICgAAAA==.',
Ai='Ainjel:BAAANQADCgUICQAAAA==.Ainz:BAAANQADCgMIBAAAAA==.',
Ak='Akaitsuki:BAAANQAECgMIBAAAAA==.',
Al='Alex:BAAANQADCggICAAAAA==.Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwABAAAAAA==.',
Am='Amarantus:BAAANQADCgIIAgABNQAECggIGQACAOESAA==.Ammerie:BAAANQADCgUIBQAAAA==.',
An='Anmodru:BAAANQADCgUIBQABNQAECgkJHAADALEfAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAAANQAECgYIEAAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgEIAQAAAA==.Arradrius:BAAANQAECgQIBAAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAAANQADCgcIFAAAAA==.',
At='Athená:BAAANQAECgMIBAAAAA==.Athenä:BAAANQAECgYICgAAAA==.',
Au='Aubrii:BAAANQADCgYIDQAAAA==.Aukatsang:BAAANQAECgYIBgAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQADCggIDQAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAAANQAECgMIBAAAAA==.Banaritaz:BAAANQAECgUIBgABNQAECgUICAABAAAAAA==.Barbaricboss:BAAANQAECgEIAQAAAA==.Barrak:BAAANQAECgQIBwABNQAECgUICgABAAAAAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAAANQAECgUICAAAAA==.Beersnob:BAAANQAECgUIBwAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigmikeyg:BAAANQAECgMIAwAAAA==.Bigsteve:BAAANQAECgMIBAAAAA==.',
Bl='Blanket:BAAANQAECgcIEQAAAA==.Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Boomchickun:BAAANQABCgIIAgABNQAECgkJHwAEAL0aAA==.',
Br='Brickley:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAAANQAECgUIBQAAAA==.',
['Bø']='Bønd:BAAANQAECgEIAQAAAA==.',
Ca='Caicos:BAEANQAECgcIEgAAAA==.Calizon:BAAANQAECgQIBAAAAA==.Canowhoopass:BAAANQAECgIIAgAAAA==.',
Ce='Cell:BAABNQAECoEYAAIFAAkJcxr8JAC5AgAFAAkJcxr8JAC5AgAAAA==.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAABNQAECoEfAAIEAAkJvRpFCgD5AgAEAAkJvRpFCgD5AgAAAA==.Cereas:BAAANQAECgMIBAAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgUIBQAAAA==.Choofz:BAAANQADCggIEAAAAA==.Chulk:BAAANQADCgcIDAAAAA==.',
Cl='Cloud:BAAANQAECgYICgAAAA==.Clukdogg:BAAANQAECgcIEgAAAA==.',
Co='Combination:BAABNQAECoEgAAMGAAkJQBmnAwDaAgAGAAkJQBmnAwDaAgAHAAcJSg7mQQDEAQAAAA==.Corvenall:BAAANQAECgIIAwAAAA==.',
Cr='Crashpad:BAAANQAECgEIAQAAAA==.Crossbow:BAAANQAECgYIEwAAAA==.',
Da='Daggers:BAAANQADCgEIAQAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danidani:BAAANQAECgQIDAAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davinah:BAAANQAECgMIBQAAAA==.Dayje:BAAANQADCgIIAgAAAA==.',
De='Deathation:BAAANQADCgUICAAAAA==.Deathbcmesyu:BAAANQAECgIIAwAAAA==.Demonovest:BAAANQAECgMIBAAAAA==.',
Di='Diehappy:BAAANQADCgYIDwAAAA==.Dishonor:BAAANQADCgMIAwAAAA==.',
Do='Dommage:BAAANQAECgUIBQABNQAECgkJHAAIAColAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAAANQAECgUIBwAAAA==.Drywar:BAABNQAECoEVAAIFAAgJUSCQIADTAgAFAAgJUSCQIADTAgAAAA==.Dràgonkíng:BAAANQADCgYIFQAAAA==.',
Dt='Dtinnel:BAAANQAECgUIBQABNQAECggIHQAJALMhAA==.',
['Dà']='Dànger:BAAANQAECgIIAgAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAAANQAECgYICgAAAA==.',
Ei='Eisla:BAAANQAECgQIBwAAAA==.',
Em='Emmone:BAAANQADCgMIAwAAAA==.',
Ex='Exacerbator:BAAANQADCgYIEgAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgQIAwAAAA==.Faunna:BAABNQAECoEZAAICAAgJ4RKUJAAJAgACAAgJ4RKUJAAJAgAAAA==.',
Fe='Fearbomb:BAAANQADCgQIBAAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAAANQAECgMIAwAAAA==.Felaz:BAAANQAECgUICgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.',
Fi='Fingerguns:BAAANQAECgcIEQAAAA==.',
Fl='Floortank:BAAANQAECgEIAQAAAA==.',
Fr='Friday:BAAANQAECgIIAgAAAA==.Frikilatar:BAAANQABCgQICAAAAA==.Frrank:BAABNQAECoEYAAIFAAkJ6CXKAQDiAwAFAAkJ6CXKAQDiAwAAAA==.',
Ga='Galcain:BAAANQAECgcICwAAAA==.',
Go='Googleyes:BAAANQADCgUICQAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQADCgEIAgAAAA==.Greybull:BAAANQAECgQIBwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAAANQAECgMIBAABNQAECgkJIAAGAEAZAA==.Growlyr:BAAANQAECgYIDgAAAA==.Grumandel:BAAANQAECgMIBAAAAA==.',
Ha='Hakur:BAAANQAECgUICgAAAA==.Hammertóe:BAAANQADCggIFgAAAA==.Hanma:BAAANQAECgQICgAAAA==.Harribel:BAAANQAECgMIBAAAAA==.',
He='Heiferina:BAAANQAECgIIAgAAAA==.Helixra:BAAANQAECgMIBgAAAA==.',
Hi='Hitachitotem:BAABNQAECoEXAAIKAAkJ+h6wCwA7AwAKAAkJ+h6wCwA7AwAAAA==.Hizzon:BAAANQADCgMIBQAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAAANQAECgQICgAAAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgYIEAABAAAAAA==.',
Jc='Jclif:BAAANQAECgUICAAAAA==.',
Je='Jehannum:BAAANQAECgMIBAAAAA==.Jessira:BAAANQAECgUICgAAAA==.',
Jo='Jonahheal:BAAANQAECgQIBAABNQAECgkJGwALALokAA==.Josen:BAAANQAECgYIBwAAAA==.',
Ka='Kach:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgQICQAAAA==.Kainiy:BAAANQADCgUIDgAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAAANQAECgUICQAAAA==.Katarena:BAAANQAECgEIAgAAAA==.Kathyra:BAEANQAECgMIBAABNQAECgcIEgABAAAAAA==.Kavax:BAAANQAECgMIAwAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keleris:BAAANQADCgUIBQAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQADCgUIBQAAAA==.',
Ki='Kinký:BAAANQAECgUICwAAAA==.Kiraelis:BAAANQAECgIIAgAAAA==.',
Ko='Korvoh:BAAANQAECgMIBAAAAA==.',
Kr='Kredriel:BAAANQADCggIDwAAAA==.Krinmate:BAABNQAECoEeAAMMAAkJwhDsKQAMAgAMAAkJchDsKQAMAgANAAUJUwekDADqAAAAAA==.Krystn:BAAANQADCgYIDQAAAA==.',
Ku='Kuurome:BAAANQADCgMIAwABNQAECggIHQAJALMhAA==.',
Kw='Kwinny:BAAANQAECgMIBAAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynthria:BAAANQAECgYIDgAAAA==.',
['Kä']='Kämik:BAAANQAECgEIAQAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAAANQAECgQIBwAAAA==.Lasstchance:BAAANQADCgYIDwAAAA==.Latinamaddog:BAAANQAECgQIBwAAAA==.',
Le='Leijona:BAAANQADCgUICAAAAA==.Lenard:BAAANQADCgYIFAAAAA==.',
Li='Likeatrain:BAAANQAECgMIBAAAAA==.Linds:BAAANQAECgUICgAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.',
Lt='Ltdanslegs:BAAANQAECgYICgAAAA==.',
Lu='Luxu:BAAANQAECgYIEwAAAA==.Luxzy:BAAANQADCgYIEQAAAA==.',
Ma='Magicbarbee:BAAANQADCgYIBgAAAA==.Makarich:BAAANQAECgQICAAAAA==.Malachron:BAAANQAECgMIAwAAAA==.Manbearcat:BAAANQAECgMIAwAAAA==.Marbleous:BAAANQAECgcIEQAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgMIAwABAAAAAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgUICAABAAAAAA==.Melancholic:BAAANQADCggICQABNQAECgQICAABAAAAAA==.Memisstotem:BAAANQAECgQIBQAAAA==.Merle:BAABNQAECoEeAAMFAAkJjR7MFgASAwAFAAkJjR7MFgASAwAOAAUJZxmsCgBEAQAAAA==.',
Mi='Minaxy:BAAANQAECgcIEgAAAA==.Mistborn:BAAANQAECgUICAAAAA==.Mistsofpoly:BAAANQADCgYIDwABNQAECgkJGgALAJ4bAA==.',
Mo='Momoku:BAAANQAECgMIAwAAAA==.Moolimbo:BAAANQADCggICAABNQAECgUICAABAAAAAA==.Mootalstrike:BAAANQAECgUICgAAAA==.Moshworm:BAAANQAECgQIBgAAAA==.',
Mv='Mvp:BAAANQADCgYICQAAAA==.',
Ne='Nelaphim:BAAANQAECgYICgAAAA==.Nexassin:BAAANQAECgEIAQAAAA==.',
Ni='Nico:BAAANQAECgQIBAAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAAANQAECgUICAAAAA==.',
No='Noctrine:BAAANQABCgYICQAAAA==.Noxxidari:BAAANQAECgUIDAAAAA==.Noxxus:BAAANQAECgQIBgAAAA==.',
Ny='Nymphis:BAAANQADCgMIAwAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.',
Ob='Oblivia:BAAANQADCgQIBAAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgQIDQABAAAAAA==.Onepunch:BAAANQADCgcIBwAAAA==.',
Or='Orchist:BAAANQAECgMIAwAAAA==.Orimbo:BAAANQAECgUICAAAAA==.',
Pa='Paidu:BAABNQAECoEWAAMEAAkJ1w+gIADMAQAEAAgJ8QmgIADMAQAPAAUJlBKQKgBGAQAAAA==.Palaritaz:BAAANQAECgIIBAABNQAECgUICAABAAAAAA==.',
Pe='Pestilancé:BAAANQAECgMIBAAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Pitchblende:BAAANQAECgUICAAAAA==.',
Po='Portiaa:BAAANQADCgMIAwAAAA==.',
Pr='Prangkim:BAAANQADCgMIBAAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgEIAQAAAA==.',
Qu='Quillz:BAAANQADCgYIBgAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAABNQAECoEbAAIQAAkJuSHeBgBNAwAQAAkJuSHeBgBNAwAAAA==.',
Re='Redine:BAAANQADCgYICQAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQADCgYIDwAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAAANQAECgMIBAAAAA==.',
Ru='Ruukia:BAABNQAECoEdAAIJAAgJsyEEDAAOAwAJAAgJsyEEDAAOAwAAAA==.',
Sa='Saboo:BAAANQAECgUIBQAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAAANQAECgMIBAABNQAECgYICgABAAAAAA==.Sapientia:BAAANQAECgQIBQAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAUIBwARACcSAA==.',
Se='Seasnan:BAAANQAECgEIAQAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgYIBgAAAA==.Senlock:BAAANQABCgIIAgABNQAECgMIBgABAAAAAA==.',
Sh='Shadowdeath:BAAANQAECgQIBwAAAA==.Shadowheàrt:BAAANQADCgcIDwAAAA==.Shadowshifty:BAAANQADCgcIBwAAAA==.Shadowtotem:BAAANQADCggIEwAAAA==.Shamdü:BAAANQAECgcIEgAAAA==.Shanson:BAAANQAECgIIAgAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQADCgEIAQABNQAECggIHQAJALMhAA==.Shockybalboa:BAAANQADCggICAAAAA==.Showerthots:BAAANQADCgYIEQAAAA==.',
Si='Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAAANQAECgYIDAAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAAANQAECgUICAAAAA==.Skyknight:BAAANQAECgUIBwAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQADCgYIDQAAAA==.',
So='Solcon:BAAANQAECgMIBAAAAA==.Solence:BAAANQADCgIIAgAAAA==.Somebodie:BAAANQAECgEIAQAAAA==.',
Sp='Spaazz:BAAANQAECgQIBwAAAA==.Sparkwire:BAAANQADCggICAAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Starweaver:BAAANQAECgQIBgAAAA==.Stormrender:BAAANQAECgUICAAAAA==.Stormsong:BAAANQAECggIEQAAAA==.Strangecandy:BAAANQAECgEIAQAAAA==.Strángeland:BAAANQADCgEIAQAAAA==.Störmrender:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.',
Su='Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAAANQAECgIIAgAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgABAAAAAA==.',
Sy='Sycla:BAAANQAECgQICwAAAA==.Sylas:BAAANQAECgIIAgAAAA==.',
Ta='Taloriesh:BAAANQAECgQIBwAAAA==.Tanazir:BAEANQAECgEIAQAAAA==.Tarok:BAAANQADCgUIBgAAAA==.Tashien:BAAANQAECgEIAQAAAA==.',
Te='Tealzin:BAAANQABCgQIBAAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgMIBQAAAA==.Terenii:BAAANQADCggIBwAAAA==.',
Ti='Tilamano:BAAANQAECgYIDgAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgYIDgABAAAAAA==.',
To='Tohrnarc:BAAANQAECgUIDAAAAA==.Tookkiiee:BAAANQAECgEIAQAAAA==.Totem:BAAANQAECgIIAwAAAA==.Totemwebz:BAAANQAECgMIAwAAAA==.',
Tr='Trenve:BAAANQAECgQIBwAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAAANQAECgUICAAAAA==.',
Ty='Tyrethia:BAAANQADCgcICAAAAA==.',
['Té']='Téchymoon:BAABNQAECoEWAAIGAAkJsg30CABFAgAGAAkJsg30CABFAgAAAA==.',
Ug='Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAAANQAECgcIEgAAAA==.',
Un='Undertaker:BAAANQABCggIDAAAAA==.',
Va='Valcristo:BAAANQAECgUICgAAAA==.Valdun:BAAANQADCgYIDwAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.Vargrim:BAAANQAECgQICAAAAA==.',
Ve='Venous:BAAANQAECgUICgAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAAANQAECggIEwAAAA==.Victhyr:BAAANQAECgQIBAAAAA==.Vidette:BAAANQADCgUIBQAAAA==.Viduus:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.Viv:BAAANQAECgUIBwAAAA==.',
Vo='Vodmor:BAAANQAECgMIBAAAAA==.Voldermort:BAAANQADCgcIDQAAAA==.',
Wa='Warrendemon:BAABNQAECoEPAAIEAAgJVCF8DwCiAgAEAAgJVCF8DwCiAgAAAA==.',
Wh='Whims:BAAANQAECgEIAQAAAA==.',
Wo='Woregontail:BAAANQADCgYIDAAAAA==.Wowbelly:BAAANQADCgUIBwAAAA==.',
Xa='Xandros:BAAANQAECgYIBwAAAA==.',
Xo='Xonk:BAABNQAECoEVAAISAAgJfBr8AgAtAgASAAgJfBr8AgAtAgAAAA==.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcICwAAAA==.',
Za='Zalagrimbor:BAAANQAECgYIEAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAAANQAECgUICAAAAA==.Zarev:BAABNQAECoEeAAITAAkJECFsBgAvAwATAAkJECFsBgAvAwAAAA==.',
Ze='Zegrath:BAAANQADCgYIBgAAAA==.Zelie:BAAANQAECgUICgAAAA==.Zenreto:BAAANQAECgMIBAAAAA==.',
Zo='Zoeri:BAAANQADCgYIBAAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAABNQAECoEcAAIDAAkJsR+tAgA+AwADAAkJsR+tAgA+AwAAAA==.',
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
