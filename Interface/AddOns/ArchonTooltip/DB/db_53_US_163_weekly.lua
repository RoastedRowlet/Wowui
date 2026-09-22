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

local lookup = {'Druid-Feral','Druid-Balance','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Warlock-Demonology','Monk-Brewmaster','Warrior-Protection','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Warrior-Arms','Priest-Shadow','Mage-Frost','DeathKnight-Frost','Warlock-Destruction','Shaman-Elemental','Druid-Restoration','Shaman-Enhancement','DeathKnight-Blood',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Adorabull:BAABNQAECoEeAAMBAAkKeiKKAgA4AwABAAgKziOKAgA4AwACAAYKdxp3PwB6AQAAAA==.',
Ae='Aemun:BAAANQADCggICwAAAA==.',
Ag='Aggfu:BAAANQADCgcIBwABNQAECgYIDAADAAAAAA==.',
Ak='Akelita:BAABNQAECoEUAAMEAAcKDxcPIwD9AQAEAAcKDxcPIwD9AQAFAAIKCQYySwBhAAAAAA==.',
Al='Alailea:BAAANQAECgUJCwAAAA==.Aloepaw:BAAANQADCgQJBQAAAA==.Alwysafkable:BAAANQAECgYIBwAAAA==.',
An='Anastasía:BAAANQAECgUJCwAAAA==.Anzul:BAAANQADCgYICgAAAA==.',
As='Asure:BAAANQAECgQIBgAAAA==.',
Ay='Ayesu:BAAANQAECgMIBQABNQAECgQIBAADAAAAAA==.',
Az='Azerith:BAAANQADCgYIDgAAAA==.',
Bl='Bloodfish:BAAANQAECgcJCwAAAA==.',
Bo='Bomber:BAAANQADCgQIBAAAAA==.Bombs:BAAANQAECgYIBgAAAA==.Bonesy:BAAANQAECgQIBwAAAA==.',
Bu='Burdomew:BAAANQADCggIFgAAAA==.',
['Bà']='Bàwitdàbà:BAAANQAECgUJCAAAAA==.',
['Bö']='Börs:BAAANQADCgEIAQAAAA==.',
Ca='Cadbringer:BAAANQADCggJCAAAAA==.Cadbury:BAAANQAECgMIBAAAAA==.Cananojii:BAAANQADCgQIBgAAAA==.Cantona:BAAANQAECgEIAQAAAA==.Casmina:BAAANQAECgUJBgAAAA==.',
Ce='Ceola:BAAANQAECgUICAAAAA==.',
Ch='Chamming:BAAANQAECgIIAgAAAA==.Chaw:BAABNQAECoEfAAIGAAkKziG9DABAAwAGAAkKziG9DABAAwAAAA==.Chawdan:BAAANQADCgcIBwAAAA==.Chenkenichi:BAAANQAECgYJDAAAAA==.Chillout:BAAANQAECgUICQAAAA==.',
Ci='Cinny:BAABNQAECoEZAAIGAAgK7BBdSQAYAgAGAAgK7BBdSQAYAgAAAA==.Cityairlines:BAAANQAECgYJDwAAAA==.',
Cm='Cmoneyy:BAAANQADCgQIBAAAAA==.',
Co='Cooldukenuke:BAABNQAECoEZAAIHAAcKghxzJwBtAgAHAAcKghxzJwBtAgAAAA==.',
Cr='Criticize:BAAANQAECgQIBAAAAA==.',
Cs='Csorpa:BAAANQAECgEIAQAAAA==.',
Cu='Cultist:BAAANQAECgYJCQAAAA==.Cupcakes:BAABNQAECoEdAAQIAAgKGx76KQC2AgAIAAgK0x36KQC2AgAJAAQKwhetKAAGAQAHAAIKtxaGrACfAAABNQAFFAEIAQADAAAAAA==.',
De='Deadbrum:BAAANQADCgYIBgABNQAECggIHAAKANkfAA==.Deagua:BAAANQADCggIDwABNQAFFAMIBQALACoKAA==.Dejavu:BAABNQAECoEgAAIMAAkKzBtgBQCqAgAMAAkKzBtgBQCqAgAAAA==.Desdemona:BAAANQADCgEJAQAAAA==.',
Do='Doodoopoopoo:BAAANQAECggIAQAAAA==.',
Dr='Dracz:BAAANQAECgYIBwAAAA==.',
Du='Duplexity:BAABNQAECoEYAAINAAgKuCOGAgA5AwANAAgKuCOGAgA5AwAAAA==.',
Dv='Dvxmatt:BAAANQAECgQIBAAAAA==.',
Dw='Dwalin:BAAANQAECgUICwAAAA==.',
Eg='Egohakai:BAACNQAFFIEFAAIIAAMK8RgKCAAKAQAIAAMK8RgKCAAKAQA1AAQKgR8AAggACQoLHoshAOMCAAgACQoLHoshAOMCAAAA.',
El='Elfy:BAAANQADCgUIBQAAAA==.',
Em='Emieretta:BAAANQAECgUJDAAAAA==.',
Er='Errekt:BAAANQAECgEIAgAAAA==.Erret:BAABNQAECoEhAAIOAAkKYRkeSgCtAgAOAAkKYRkeSgCtAgAAAA==.',
Et='Ethaka:BAAANQAECgYICgAAAA==.',
Fa='Faemos:BAAANQAECgYICwAAAA==.Faience:BAAANQAECgIIAwAAAA==.Falorina:BAABNQAECoEVAAIEAAgKoxuxFQCIAgAEAAgKoxuxFQCIAgAAAA==.Fathernature:BAAANQAECgcIBwAAAA==.',
Fe='Feldra:BAAANQAECgcJEgAAAA==.',
Fi='Finnin:BAAANQAECgYJCwAAAA==.',
Fo='Food:BAAANQAECgYJCwAAAA==.',
Fr='Frozenfaith:BAAANQAECgYJCwAAAA==.',
Fu='Furba:BAAANQAECgcIEgAAAA==.Furiouswind:BAAANQAECgYJDwAAAA==.Furyvolt:BAAANQAECgMIBgAAAA==.',
Gh='Ghettomike:BAAANQAECgYJDwAAAA==.Ghold:BAAANQAECgcIEAAAAA==.',
Gi='Giranimo:BAAANQAECgQIBAAAAA==.',
Gl='Glabados:BAAANQADCgcICAABNQAECgYJDwADAAAAAA==.Glossy:BAACNQAFFIEFAAMPAAMKrxvEBwC8AAAPAAIKURbEBwC8AAAQAAEKayb7CQB0AAA1AAQKgR0AAw8ACAqqJWoQAEICAA8ABgqNJGoQAEICABAABAq6JbkjALsBAAAA.Glossyrage:BAAANQADCgcIBwAAAA==.',
Go='Gorkus:BAAANQADCgMIAwAAAA==.Gors:BAAANQAECgQIBQAAAA==.',
Gr='Gratiaplena:BAAANQABCgQIBwAAAA==.',
Ha='Halîk:BAAANQAECgYIDwAAAA==.Hardheaded:BAAANQADCggICAAAAA==.Hathina:BAABNQAECoEXAAMRAAkKYiLBAQAZAwARAAgKlCLBAQAZAwASAAEKyyD76QBYAAAAAA==.',
He='Hedetet:BAAANQABCgEIAQABNQAECgYIDwADAAAAAA==.Herath:BAAANQABCggIDwAAAA==.',
Hi='Hill:BAAANQAECgUIDgAAAA==.Hive:BAABNQAECoEfAAISAAgKdA7MZgDaAQASAAgKdA7MZgDaAQAAAA==.',
Hu='Husentar:BAAANQADCgYICwAAAA==.',
Ic='Icaron:BAAANQADCggIAQAAAA==.',
Ig='Igni:BAAANQABCgMIBAAAAA==.',
Il='Illuminottey:BAAANQADCgEIAQAAAA==.',
Im='Impériavil:BAAANQAECgIIAgAAAA==.',
In='Inferium:BAAANQADCgcIBwAAAA==.Insatiabull:BAAANQAECgYIBgABNQAECgkJHgABAHoiAA==.',
Ir='Iriaena:BAAANQADCgYIDwAAAA==.',
Is='Ishaa:BAAANQADCgEIAQAAAA==.',
Ja='Jackstands:BAABNQAECoEfAAIKAAgK4iI4DgAXAwAKAAgK4iI4DgAXAwAAAA==.Jagerin:BAAANQAECgEIAQABNQAECgYJDwADAAAAAA==.January:BAABNQAECoEWAAITAAgKMgh9IgChAQATAAgKMgh9IgChAQAAAA==.Jarry:BAAANQAECgIIAgAAAA==.',
Je='Jeannine:BAAANQADCgUJBwAAAA==.',
Ju='Junn:BAAANQAECgYJDwAAAA==.',
['Já']='Jánuary:BAAANQADCggICgAAAA==.',
Ka='Kahayman:BAABNQAECoEhAAMOAAkKRg8iaABYAgAOAAkKRg8iaABYAgAUAAQKagSEGwCjAAAAAA==.Kaimari:BAAANQAECgYJDQAAAA==.Kazuya:BAAANQAECgEIAQAAAA==.',
Ke='Kennyboi:BAAANQADCgIIAgAAAA==.',
Kh='Khaibit:BAABNQAECoEeAAIVAAgKpB/gDgC/AgAVAAgKpB/gDgC/AgAAAA==.Khathani:BAAANQADCggIDwAAAA==.',
Ki='Kissofdeath:BAAANQAECgUJCwAAAA==.',
Ko='Komojo:BAAANQAECgEJAQAAAA==.Koriggan:BAAANQAECgQJBAAAAA==.',
Kr='Krea:BAAANQAECgQJBAAAAA==.Kroval:BAAANQAECgQJBAAAAA==.Krystagosa:BAAANQAECgQIBQAAAA==.',
Ku='Kuriuh:BAAANQAECgYJDwAAAA==.',
Ky='Kybo:BAAANQABCgMIAwABNQAECgkJHgACAIogAA==.Kyo:BAAANQADCgUIBQAAAA==.',
La='Lang:BAAANQAECgUJCwAAAA==.',
Li='Lightdogg:BAAANQAECgUJBgAAAA==.Limaia:BAAANQAECgUJBwAAAA==.Linia:BAAANQAECgEIAQAAAA==.',
Lo='Loopey:BAAANQAECgEIAQABNQAECgkJIAAMAMwbAA==.',
Lu='Luceriss:BAAANQAECgcIDgAAAA==.Lulilaj:BAAANQAECgYJEAAAAA==.',
Ma='Maike:BAAANQAECgQIBwAAAA==.Marothius:BAACNQAFFIEFAAMLAAMKKgoVGQCZAAALAAIKIAsVGQCZAAAWAAEKPwgOEgBUAAA1AAQKgR8AAwsACQriHGouAGYCAAsACApGG2ouAGYCABYABQqwGjwZAIgBAAAA.Marrius:BAAANQADCgYIBwAAAA==.Martaug:BAABNQAECoEcAAIKAAgKDCEYEwDtAgAKAAgKDCEYEwDtAgAAAA==.Marune:BAAANQAECgUJCgAAAA==.Maverage:BAAANQAECgQIBAAAAA==.Mayfair:BAAANQABCgQJCAAAAA==.',
Me='Melee:BAABNQAECoEWAAIIAAgKXRwnKwCwAgAIAAgKXRwnKwCwAgAAAA==.Metal:BAAANQADCgcIEwAAAA==.',
Mi='Minimee:BAAANQAECgEIAQAAAA==.Miquella:BAAANQAECgQJCgAAAA==.',
Mo='Mollymauk:BAAANQADCgQIBAABNQAECgcIEAADAAAAAA==.Monkstrosity:BAAANQAECgYIEAAAAA==.Mookks:BAAANQADCgUIBQAAAA==.Moonn:BAAANQAECgUIBQAAAA==.Moor:BAAANQAECgQIBQAAAA==.Mordakka:BAAANQAECgcIEwAAAA==.Morior:BAABNQAECoEaAAMLAAgKpRD9WwC2AQALAAcK3Q/9WwC2AQAWAAEKIBauWwBHAAAAAA==.',
Mu='Mulletmaster:BAAANQAECgUJCQAAAA==.Murrda:BAAANQAECggJEwAAAA==.',
My='Myrokos:BAABNQAECoEfAAIIAAgK7R0xNQCBAgAIAAgK7R0xNQCBAgAAAA==.',
['Mö']='Möokss:BAAANQAECgYIDwAAAA==.',
Na='Nailo:BAAANQADCggICAAAAA==.Nasperus:BAAANQABCgIIAgAAAA==.',
Ni='Niddy:BAAANQAECgYJEAAAAA==.',
No='Nobudee:BAAANQADCgcIBwABNQAFFAMIBQAXAMgNAA==.Nocandles:BAAANQAECgUICAAAAA==.Noebuddie:BAACNQAFFIEFAAIXAAMKyA2aCwDsAAAXAAMKyA2aCwDsAAA1AAQKgR4AAhcACQr3HMAUAAgDABcACQr3HMAUAAgDAAAA.Noel:BAAANQAECgIIAwAAAA==.Nonospot:BAAANQAECgQJBgAAAA==.Noraboo:BAAANQAECgQIBAAAAA==.Norganon:BAAANQAECgEIAgAAAA==.',
Nv='Nvied:BAAANQAECgUICAAAAA==.',
Ny='Nyctt:BAABNQAECoEeAAIPAAgKlxIVEQA5AgAPAAgKlxIVEQA5AgAAAA==.Nyzstra:BAAANQAECgcJEgAAAA==.',
['Nê']='Nêwt:BAABNQAECoEdAAIOAAgKSBLcdwAtAgAOAAgKSBLcdwAtAgAAAA==.',
On='Onlybeams:BAAANQAECgYIDwAAAA==.',
Or='Orcs:BAAANQADCgUIBQAAAA==.Oreo:BAAANQADCgcIEQAAAA==.Orphu:BAAANQADCgQIBwAAAA==.',
Pa='Palmiste:BAAANQAECgQIBAAAAA==.Pandoora:BAAANQADCgYIEAAAAA==.Pangoplexity:BAAANQABCgMJAwAAAA==.Parahsalin:BAAANQAECgUICQAAAA==.Pastryblust:BAABNQAECoEjAAIXAAkKsx56DgBCAwAXAAkKsx56DgBCAwAAAA==.',
Pi='Pistachio:BAAANQADCgcJFQAAAA==.Pitviper:BAAANQAECgYJDwAAAA==.',
Po='Pogaca:BAAANQADCggIEwAAAA==.Portabull:BAAANQADCgcIBwABNQAECgkJHgABAHoiAA==.',
Pr='Precogvendor:BAAANQAECgIIAwAAAA==.',
Ra='Rai:BAAANQAECgUJCwAAAA==.Ramens:BAAANQAECgIIAgAAAA==.Rapha:BAAANQAECgYJDwAAAA==.Rayyzor:BAAANQAECgUJDQAAAA==.',
Re='Reality:BAAANQADCgQICAAAAA==.Realtree:BAAANQADCgQIBwAAAA==.',
Ri='Riddles:BAAANQAECgcJCwAAAA==.',
Ro='Rot:BAAANQAECgYJDwAAAA==.',
Sa='Santino:BAAANQADCgcICAABNQAECgkJIQAOAEYPAA==.Saphlocket:BAAANQAECgEJAwAAAA==.Saphmage:BAAANQAECgEIAQAAAA==.Sathin:BAAANQAECgUJCwAAAA==.',
Sc='Scher:BAAANQAECgMIAwAAAA==.Scufalufagus:BAAANQADCgUIBQABNQAFFAMIBQALACoKAA==.',
Se='September:BAAANQADCgYJBgABNQAECggJFgATADIIAA==.Seqsy:BAAANQADCgQIBAAAAA==.',
Sf='Sfcwarner:BAAANQADCgYJDQAAAA==.',
Sg='Sgtwarner:BAAANQADCgQIBAAAAA==.',
Sh='Shampooyou:BAAANQAECgQJBAAAAA==.',
Si='Silentkit:BAAANQAECgUJCwAAAA==.',
St='Stardel:BAAANQAECgQIBAABNQAFFAMIBgAQABYeAA==.Stormclaw:BAAANQAECgYJEgAAAA==.Stregglebus:BAAANQAECgQJBAABNQAFFAMIBQALACoKAA==.Stroggosh:BAAANQADCggIEgABNQAFFAMIBQALACoKAA==.',
Su='Suhfering:BAAANQADCgcIBwABNQAECgYIDwADAAAAAA==.Sunshot:BAAANQAECgEIAQAAAA==.',
Ta='Takrusani:BAAANQADCgIIAgAAAA==.Tallron:BAACNQAFFIEFAAIYAAMKPA49BQDxAAAYAAMKPA49BQDxAAA1AAQKgR8AAhgACQpAGmULALUCABgACQpAGmULALUCAAAA.Tamedsloth:BAAANQAECgMIBAAAAA==.Tanerella:BAAANQADCggIDwAAAA==.',
Th='Thrustruggle:BAAANQAECgUIBwAAAA==.',
Ti='Timir:BAABNQAECoEfAAIIAAkKrBdSQQBNAgAIAAkKrBdSQQBNAgAAAA==.',
To='Tojikitoushi:BAABNQAECoEeAAIZAAgKRRIwDABBAgAZAAgKRRIwDABBAgAAAA==.Tombs:BAAANQAECgEIAQABNQAECgcIEAADAAAAAA==.Totenhammer:BAAANQADCgYIBwAAAA==.Touche:BAAANQAECgYICgAAAA==.',
Tr='Tribulate:BAAANQADCggIDAAAAA==.Trollyroller:BAAANQADCggIFAAAAA==.',
Tw='Twistedfrost:BAAANQADCgUJBQAAAA==.',
Ul='Ulrein:BAAANQAECgEJAQAAAA==.',
Ve='Vextt:BAAANQAECgcIDwABNQAECgcIEAADAAAAAA==.Veylira:BAAANQAECgUIDgABNQAECgkJIwASABYXAA==.',
Vi='Vitner:BAAANQAECggIDwAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.Volight:BAAANQAECgQIBgAAAA==.Volke:BAAANQAECgYJDwAAAA==.Voltarix:BAAANQADCgEIAQAAAA==.Voyria:BAAANQAECgUJCwAAAA==.',
Wa='Warm:BAAANQAECgQICAAAAA==.',
We='Weeziveli:BAAANQADCgYIBgAAAA==.Weledish:BAABNQAECoEjAAMOAAkK8R2AKwAOAwAOAAkK8R2AKwAOAwAUAAIKbg5+IAB0AAAAAA==.Weleron:BAAANQADCgIIAgAAAA==.',
Wi='Widdles:BAAANQAECgMIAwAAAA==.',
Yi='Yinyangfaith:BAAANQADCgEIAQABNQAECgYJCwADAAAAAA==.',
Zo='Zomgdk:BAABNQAECoEfAAIaAAgKzh71FQCtAgAaAAgKzh71FQCtAgAAAA==.',
Zy='Zynthia:BAAANQADCgQIBAAAAA==.',
['Äm']='Ämäteräsu:BAAANQAECggJAgAAAA==.',
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
