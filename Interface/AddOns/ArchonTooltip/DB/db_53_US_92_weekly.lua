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

local lookup = {'Unknown-Unknown','Druid-Balance','Shaman-Enhancement','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination','DemonHunter-Devourer','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Druid-Guardian','DeathKnight-Unholy','Priest-Holy','Priest-Discipline','Shaman-Restoration','DeathKnight-Blood','Warrior-Fury','Paladin-Retribution','DemonHunter-Havoc','Mage-Arcane','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Priest-Shadow','Hunter-Marksmanship',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abrakådabruh:BAAANQAECgUICQAAAA==.',
Ac='Acnologia:BAAANQADCgEIAQAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAAANQAECgUJDAAAAA==.',
Ai='Ainjel:BAAANQADCgUICQAAAA==.Ainz:BAAANQADCgMIBAAAAA==.',
Ak='Akaitsuki:BAAANQAECgUJCQAAAA==.',
Al='Alex:BAAANQADCggICAAAAA==.Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwABAAAAAA==.Alisson:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.',
Am='Amarantus:BAAANQADCgIIAgABNQAECgkJIQACAPwVAA==.Ammerie:BAAANQADCgUJBQAAAA==.',
An='Anmoa:BAAANQADCgMIAwABNQAECgkJJwADAAolAA==.Anmodru:BAAANQADCgUIBQABNQAECgkJJwADAAolAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAABNQAECoEaAAIEAAgK6SBLAgD8AgAEAAgK6SBLAgD8AgAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgEJAQAAAA==.Arradrius:BAAANQAECgUIBgAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAAANQAECgEJAQAAAA==.',
At='Athená:BAAANQAECgUICQAAAA==.Athenä:BAAANQAECgcIEQAAAA==.',
Au='Aubrii:BAAANQADCgcIDgAAAA==.Aukatsang:BAAANQAECgYJCwAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYJCgAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAAANQAECgUIBgAAAA==.Banaritaz:BAAANQAECgYJDAAAAA==.Barbaricboss:BAAANQAECgQIBQAAAA==.Barrak:BAAANQAECgQIBwABNQAECgUJDAABAAAAAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAAANQAECgYIDgAAAA==.Beersnob:BAAANQAECgYIDQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFIEIAAIFAAMK8wxODADjAAAFAAMK8wxODADjAAA1AAQKgR4AAgUACQpyIk4JAHYDAAUACQpyIk4JAHYDAAAA.Bigmikeyg:BAAANQAECgUICAAAAA==.Bigsteve:BAAANQAECgUICQAAAA==.',
Bl='Blanket:BAABNQAECoEVAAIGAAYKBB6QHAAAAgAGAAYKBB6QHAAAAgAAAA==.Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Boomchickun:BAAANQABCgIIAgABNQAECgkJIwAHAC4bAA==.',
Br='Brickley:BAAANQADCgYIBgABNQAECggIGgAEAOkgAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAAANQAECgUJCgAAAA==.',
['Bø']='Bønd:BAAANQAECgEJAQAAAA==.',
Ca='Caicos:BAEBNQAECoEdAAMIAAgKSQ/YDwACAgAIAAgKSQ/YDwACAgAJAAEKVwGGGwAbAAAAAA==.Calizon:BAAANQAECgYICgAAAA==.Canowhoopass:BAAANQAECgQJBgAAAA==.Caser:BAAANQADCgMJAwAAAA==.Catharsis:BAAANQABCggIDAAAAA==.',
Ce='Cell:BAACNQAFFIEGAAIKAAIK0wq+GwCFAAAKAAIK0wq+GwCFAAA1AAQKgSAAAgoACQqVHj4bABUDAAoACQqVHj4bABUDAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAABNQAECoEjAAIHAAkKLhv4DADkAgAHAAkKLhv4DADkAgAAAA==.Cereas:BAAANQAECgUICQAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgUIBQAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Cloud:BAAANQAECggJEAAAAA==.Clukdogg:BAAANQAECgcIEgAAAA==.',
Co='Combination:BAABNQAECoEjAAMLAAkKRht2BADEAgALAAkKQBl2BADEAgAMAAcKqxGjVADPAQAAAA==.Corvenall:BAAANQAECgUICAAAAA==.',
Cr='Crashpad:BAAANQAECgEJAQAAAA==.Crossbow:BAABNQAECoEgAAINAAgK8BluLACCAgANAAgK8BluLACCAgAAAA==.',
Da='Daggers:BAAANQADCgMIAwAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danidani:BAAANQAECgUJEQAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davinah:BAAANQAECgMIBQAAAA==.Dayje:BAAANQADCgIIAwAAAA==.',
De='Deathation:BAAANQADCgUICAAAAA==.Deathbcmesyu:BAAANQAECgUICAAAAA==.Demonovest:BAAANQAECgUICQAAAA==.',
Di='Diehappy:BAAANQADCgYIDwAAAA==.Dishonor:BAAANQADCgMIBQAAAA==.',
Do='Dommage:BAAANQAECgUIBQABNQAECgkJHwAOAF8lAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAAANQAECgUIBwAAAA==.Drywar:BAABNQAECoEYAAIKAAkK3iCkGQAeAwAKAAkK3iCkGQAeAwAAAA==.Dràgonkíng:BAAANQADCgcJGwAAAA==.',
Dt='Dtinnel:BAAANQAECgYICwABNQAECggIKwAPAHskAA==.',
['Dà']='Dànger:BAAANQAECgIIAwAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAAANQAECgcJEQAAAA==.',
Ei='Eisla:BAAANQAECgUJDAAAAA==.',
Em='Emmone:BAAANQAECgQIBAAAAA==.',
Ex='Exacerbator:BAAANQADCgYIGAAAAA==.',
Fa='Falcon:BAAANQABCgQJBQAAAA==.Fargecia:BAAANQAECgQIAwAAAA==.Faunna:BAABNQAECoEhAAICAAkK/BXnHwBvAgACAAkK/BXnHwBvAgAAAA==.',
Fe='Fearbomb:BAAANQADCgQIBAAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAAANQAECgYJCQAAAA==.Felaz:BAAANQAECgYIEAAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.',
Fi='Fingerguns:BAABNQAECoEeAAMQAAkKBh6TCABHAwAQAAkKBh6TCABHAwARAAUK2wZLDgDmAAAAAA==.',
Fl='Floortank:BAAANQAECgEJAgAAAA==.',
Fr='Friday:BAAANQAECgIIAgAAAA==.Frikilatar:BAAANQABCgQICAAAAA==.Frrank:BAABNQAECoEhAAIKAAkKnib6AAD3AwAKAAkKnib6AAD3AwAAAA==.',
Ga='Galcain:BAAANQAECgcIEgAAAA==.',
Go='Googleyes:BAAANQADCgUJCQAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQADCgMJBQAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAAANQAECgUICQABNQAECgkJIwALAEYbAA==.Growlyr:BAABNQAECoEXAAIPAAgKwBtvGgCUAgAPAAgKwBtvGgCUAgAAAA==.Grumandel:BAAANQAECgMJBwAAAA==.',
Ha='Hakur:BAAANQAECgYJEAAAAA==.Hammertóe:BAAANQADCggJFwAAAA==.Hanma:BAAANQAECgQICgAAAA==.Harribel:BAAANQAECgUICQAAAA==.',
He='Heiferina:BAAANQAECgYJCAAAAA==.Helixra:BAAANQAECgQJCAAAAA==.Hellcroh:BAAANQAECgMJAwAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hizzon:BAAANQADCgUJBwAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAAANQAECgQIDgAAAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECggIGQAFABoWAA==.',
Ja='Jawny:BAAANQADCgUJBQAAAA==.',
Jc='Jclif:BAAANQAECgYIDgAAAA==.',
Je='Jehannum:BAAANQAECgMJBgAAAA==.Jessira:BAAANQAECgUJDwAAAA==.',
Jo='Jonahheal:BAAANQAECgYICgABNQAFFAUICQASAL0dAA==.Josen:BAAANQAECgYIDQAAAA==.',
Ka='Kach:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgQICwAAAA==.Kainiy:BAAANQADCgUIDwAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAAANQAECgYJDwAAAA==.Katarena:BAAANQAECgUJBwAAAA==.Kathyra:BAEANQAECgQIDAABNQAECggIHQAIAEkPAA==.Kavax:BAAANQAECgQIBwAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQADCgUJBwAAAA==.',
Ki='Kinký:BAAANQAECgYJEQABNQADCgcJBwABAAAAAA==.Kiraelis:BAAANQAECgYJCAAAAA==.',
Ko='Korvoh:BAAANQAECgUICQAAAA==.',
Kr='Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAABNQAECoEhAAMQAAkK0xAPOQAJAgAQAAkKgxAPOQAJAgARAAUKUwd7DgDjAAAAAA==.Krystn:BAAANQADCgcIDgAAAA==.',
Ku='Kumaro:BAAANQABCgQJBAAAAA==.Kuurome:BAAANQADCgMIAwABNQAECggIKwAPAHskAA==.',
Kw='Kwinny:BAAANQAECgUICQAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynthria:BAAANQAECgYIDwAAAA==.',
['Kä']='Kämik:BAAANQAECgUIBgAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAAANQAECgUIDAAAAA==.Lasstchance:BAAANQADCgYIDwAAAA==.Latinamaddog:BAAANQAECgUJDAAAAA==.',
Le='Leijona:BAAANQADCgUICAAAAA==.Lelathon:BAAANQAECggJCAAAAA==.Lenard:BAAANQADCgYIFAAAAA==.Leröth:BAAANQAECgQJBAAAAA==.',
Li='Likeatrain:BAAANQAECgQJCAAAAA==.Linds:BAAANQAECgUICgAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Lokki:BAAANQADCgYJBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.',
Lt='Ltdanslegs:BAAANQAECgcIEQAAAA==.',
Lu='Luxu:BAABNQAECoEdAAITAAgKjyH/DQACAwATAAgKjyH/DQACAwAAAA==.Luxzy:BAAANQAECgEJAQAAAA==.',
Ma='Magicbarbee:BAAANQADCgYJDAAAAA==.Makarich:BAAANQAECgQICAAAAA==.Malachron:BAAANQAECgUICAAAAA==.Manbearcat:BAAANQAECgQIBwAAAA==.Marbleous:BAABNQAECoEYAAIKAAcKGx/SQwBYAgAKAAcKGx/SQwBYAgAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgQIBwABAAAAAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgYIBgABAAAAAA==.Melancholic:BAAANQADCggICQABNQAECgQICAABAAAAAA==.Memisstotem:BAAANQAECgYICgAAAA==.Merle:BAABNQAECoEeAAMKAAkKjR67IgDqAgAKAAkKjR67IgDqAgAUAAUKZxkqDgBAAQAAAA==.',
Mi='Minaxy:BAABNQAECoEdAAIVAAgKDR28LACoAgAVAAgKDR28LACoAgAAAA==.Mistborn:BAAANQAECgUICgABNQAECgYJDAABAAAAAA==.Mistsofpoly:BAAANQADCgYJDwABNQAECgkJIAASADceAA==.',
Mo='Momoku:BAAANQAECgUICAAAAA==.Moolimbo:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.Mootalstrike:BAAANQAECgUICgAAAA==.Moshworm:BAAANQAECgQICgAAAA==.',
Mv='Mvp:BAAANQADCgYJCgAAAA==.',
Na='Namis:BAAANQADCgMJAwAAAA==.',
Ne='Nelaphim:BAAANQAECgcIEAAAAA==.Nexassin:BAAANQAECgEIAQAAAA==.',
Ni='Nico:BAAANQAECgYICgAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAAANQAECgUICAABNQAECgYIBgABAAAAAA==.',
No='Noctrine:BAAANQABCgYICQAAAA==.Noxxidari:BAAANQAECgUJDgAAAA==.Noxxus:BAAANQAECgYIDAAAAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.',
Ob='Oblivia:BAAANQADCgQIBAAAAA==.Obsidiansoul:BAAANQADCgcJBwAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECggIGAAKAA4cAA==.Onepunch:BAAANQADCgcIBwAAAA==.',
Or='Orchist:BAAANQAECgQIBwAAAA==.Orimbo:BAAANQAECgYIDgAAAA==.',
Pa='Paidu:BAABNQAECoEaAAMWAAkKChVlLQCaAQAHAAgK8QlIJgC7AQAWAAUKsxxlLQCaAQAAAA==.Palaritaz:BAAANQAECgIIBAABNQAECgYJDAABAAAAAA==.',
Pe='Pestilancé:BAAANQAECgUICQAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Pitchblende:BAAANQAECgYIDgAAAA==.',
Po='Polylock:BAAANQAECgIIAgAAAA==.Portiaa:BAAANQAECgEIAQAAAA==.',
Pr='Prangkim:BAAANQADCgMIBAAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgEIAQAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAAANQAECgQIBgAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAABNQAECoElAAITAAkKoyM7BQB+AwATAAkKoyM7BQB+AwAAAA==.',
Re='Redine:BAAANQADCgYICQAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQADCgYIDwAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAAANQAECgUICQAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAABNQAECoErAAIPAAgKeySFCQBKAwAPAAgKeySFCQBKAwAAAA==.',
Sa='Saboo:BAAANQAECgYICwAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAAANQAECgUICQABNQAECgcIEQABAAAAAA==.Sapientia:BAAANQAECgUJBgAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAUJCwAXAK4UAA==.',
Se='Seasnan:BAAANQAECgEIAQAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgYJCwAAAA==.Senlock:BAAANQABCgIIAgABNQAECgUICAABAAAAAA==.',
Sh='Shadizzon:BAAANQABCgQJBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAAANQAECgUIDAAAAA==.Shadowheàrt:BAAANQAECgEJAQAAAA==.Shadowshifty:BAAANQADCgcJBwAAAA==.Shadowtotem:BAAANQADCggJFgAAAA==.Shamdü:BAABNQAECoEbAAIKAAkKcxmrNwCIAgAKAAkKcxmrNwCIAgAAAA==.Shanson:BAAANQAECgUJBwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQADCgEIAQABNQAECggIKwAPAHskAA==.Shockybalboa:BAAANQAECgQJBAAAAA==.Showerthots:BAAANQADCgcIGAAAAA==.',
Si='Silvver:BAAANQADCgcJBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAAANQAECgcIEwAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAAANQAECgYIDgAAAA==.Skyknight:BAAANQAECgUIBwAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.',
So='Solcon:BAAANQAECgUICAAAAA==.Solence:BAAANQADCgIIAgAAAA==.Somebodie:BAAANQAECgIJAgAAAA==.',
Sp='Spaazz:BAAANQAECgUJDAAAAA==.Sparkwire:BAAANQADCggICAAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgUICwABAAAAAA==.Starweaver:BAAANQAECgUICwAAAA==.Stormrender:BAAANQAECgYIDgAAAA==.Stormsong:BAABNQAECoEWAAMFAAkKShrHHgC4AgAFAAkKShrHHgC4AgASAAMK8grMpgCcAAAAAA==.Strangecandy:BAAANQAECgEJAQAAAA==.Strángeland:BAAANQADCgMJBAAAAA==.Störmrender:BAAANQADCgcJCAABNQAECgYIDgABAAAAAA==.',
Su='Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAAANQAECgIJAgAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgABAAAAAA==.',
Sy='Sycla:BAAANQAECgYJEAAAAA==.Sylas:BAAANQAECgMJBAAAAA==.',
Ta='Taloriesh:BAAANQAECgQICwAAAA==.Tanazir:BAEANQAECgEJAQAAAA==.Tarok:BAAANQADCgUICQAAAA==.Tashien:BAAANQAECgEJAQAAAA==.',
Te='Tealzin:BAAANQABCgQIBAAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgMIBQAAAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECoEWAAQLAAcK5yN1DQABAgALAAUKWSN1DQABAgAMAAUKoSTMRwD+AQAYAAUKECGNBgDDAQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgcIFgALAOcjAA==.',
To='Tohrnarc:BAAANQAECgYIEgAAAA==.Tookkiiee:BAAANQAECgcICAAAAA==.Totem:BAAANQAECgIIAwAAAA==.Totemwebz:BAAANQAECgQIBwAAAA==.',
Tr='Trenve:BAAANQAECgUIDAAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAAANQAECgYIDgAAAA==.',
Ty='Tyrethia:BAAANQADCgcJDAAAAA==.',
['Té']='Téchymoon:BAABNQAECoEgAAILAAkKaRJoBwByAgALAAkKaRJoBwByAgAAAA==.',
Ug='Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAABNQAECoEcAAQGAAgKcxp8EACKAgAGAAgKKRl8EACKAgAZAAcKLxo/EwAaAgAaAAEKMA87FgA0AAAAAA==.',
Un='Undertaker:BAAANQABCggIDAAAAA==.',
Va='Valcristo:BAAANQAECgYIEAAAAA==.Valdun:BAAANQADCgYIDwAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.Vargrim:BAAANQAECgQIDAAAAA==.',
Ve='Venous:BAAANQAECgYIEAAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAABNQAECoEfAAQbAAkKECCuEACVAgAbAAcKFh6uEACVAgAQAAgKyxb4QgDZAQARAAIKjyWuDgDeAAAAAA==.Victhyr:BAAANQAECgQIBAAAAA==.Vidette:BAAANQADCgYJBgAAAA==.Viduus:BAAANQAECgYIBgAAAA==.Viv:BAAANQAECgUJCgAAAA==.',
Vo='Vodmor:BAAANQAECgQJCAAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.',
Wa='Warrendemon:BAABNQAECoEPAAIHAAgKVCHFEwCFAgAHAAgKVCHFEwCFAgAAAA==.',
Wh='Whims:BAAANQAECgEIAQAAAA==.',
Wi='Wildheart:BAAANQAECgEJAQAAAA==.',
Wo='Woregontail:BAAANQADCgcJEwAAAA==.Wowbelly:BAAANQAECgIIAgAAAA==.',
Xa='Xandros:BAAANQAECgYJCgAAAA==.',
Xo='Xonk:BAABNQAECoEdAAIYAAkK+BgXAwBwAgAYAAkK+BgXAwBwAgAAAA==.',
Yg='Ygcamel:BAAANQADCggJEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcICwAAAA==.',
Za='Zaklu:BAAANQAECgIJAwAAAA==.Zalagrimbor:BAABNQAECoEZAAMFAAgKGhY7MQBCAgAFAAgKGhY7MQBCAgASAAMKgAVkuABuAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAAANQAECgYIDgAAAA==.Zarev:BAACNQAFFIEGAAIcAAQKABMhCABDAQAcAAQKABMhCABDAQA1AAQKgSAAAhwACQrSIScIACQDABwACQrSIScIACQDAAAA.',
Ze='Zeenab:BAAANQADCgIJAgAAAA==.Zegrath:BAAANQADCgcJDAAAAA==.Zelie:BAAANQAECgYIEAAAAA==.Zenreto:BAAANQAECgUICQAAAA==.',
Zo='Zoeri:BAAANQAECgEIAQAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAABNQAECoEnAAIDAAkKCiVmAADfAwADAAkKCiVmAADfAwAAAA==.',
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
