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

local lookup = {'Druid-Feral','Druid-Balance','Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Warlock-Demonology','Monk-Brewmaster','Paladin-Retribution','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Warrior-Arms','Mage-Frost','DeathKnight-Frost','Warlock-Destruction','Shaman-Elemental','Druid-Restoration','DeathKnight-Blood',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Adorabull:BAABNQAECoEbAAMBAAkJ1iHwAQAyAwABAAgJFiPwAQAyAwACAAYJdxprMwCNAQAAAA==.',
Ae='Aemun:BAAANQADCggICwAAAA==.',
Ag='Aggfu:BAAANQADCgcIBwABNQAECgQIBQADAAAAAA==.',
Ak='Akelita:BAAANQAECgcIDgAAAA==.',
Al='Alailea:BAAANQAECgQIBgAAAA==.Aloepaw:BAAANQADCgQIBQAAAA==.Alwysafkable:BAAANQAECgIIAgAAAA==.',
An='Anastasía:BAAANQAECgQIBgAAAA==.Anzul:BAAANQADCgYICgAAAA==.',
As='Asure:BAAANQAECgQIBgAAAA==.',
Ay='Ayesu:BAAANQAECgIIAgAAAA==.',
Az='Azerith:BAAANQADCgYIDgAAAA==.',
Bl='Bloodfish:BAAANQAECgQIBAAAAA==.',
Bo='Bomber:BAAANQADCgQIBAAAAA==.Bombs:BAAANQABCgMIAwABNQAECgkJHAAEACcbAA==.Bonesy:BAAANQAECgIIAwAAAA==.',
Bu='Burdomew:BAAANQADCggIFgAAAA==.',
['Bà']='Bàwitdàbà:BAAANQAECgIIAwAAAA==.',
['Bö']='Börs:BAAANQADCgEIAQAAAA==.',
Ca='Cadbringer:BAAANQADCggICAAAAA==.Cadbury:BAAANQAECgEIAQAAAA==.Cananojii:BAAANQADCgQIBgAAAA==.Casmina:BAAANQAECgQIBQAAAA==.',
Ce='Ceola:BAAANQAECgIIAwAAAA==.',
Ch='Chamming:BAAANQAECgIIAgAAAA==.Chaw:BAABNQAECoEcAAIFAAkJSCGjCQA7AwAFAAkJSCGjCQA7AwAAAA==.Chawdan:BAAANQADCgcIBwAAAA==.Chenkenichi:BAAANQAECgQIBgAAAA==.Chillout:BAAANQAECgUICQAAAA==.',
Ci='Cinny:BAAANQAECgcIEQAAAA==.Cityairlines:BAAANQAECgQICQAAAA==.',
Cm='Cmoneyy:BAAANQADCgQIBAAAAA==.',
Co='Cooldukenuke:BAAANQAECgYIDwAAAA==.',
Cs='Csorpa:BAAANQAECgEIAQAAAA==.',
Cu='Cultist:BAAANQAECgQIAwAAAA==.Cupcakes:BAAANQAECgcIEQAAAA==.',
De='Deadbrum:BAAANQADCgYIBgABNQAECgcIEQADAAAAAA==.Deagua:BAAANQADCgYIBgABNQAECgkJHAAGALYaAA==.Dejavu:BAABNQAECoEeAAIHAAkJKxqzBACZAgAHAAkJKxqzBACZAgAAAA==.',
Dr='Dracz:BAAANQAECgEIAQAAAA==.',
Du='Duplexity:BAAANQAECgYIDgAAAA==.',
Dv='Dvxmatt:BAAANQAECgQIBAAAAA==.',
Dw='Dwalin:BAAANQAECgQIBgAAAA==.',
Eg='Egohakai:BAABNQAECoEcAAIIAAkJ3RrRGwDDAgAIAAkJ3RrRGwDDAgAAAA==.',
Em='Emieretta:BAAANQAECgUICAAAAA==.',
Er='Errekt:BAAANQAECgEIAgAAAA==.Erret:BAABNQAECoEcAAIJAAkJ9BZVOACwAgAJAAkJ9BZVOACwAgAAAA==.',
Et='Ethaka:BAAANQAECgQIBAAAAA==.',
Fa='Faemos:BAAANQAECgYICwAAAA==.Faience:BAAANQAECgEIAQAAAA==.Falorina:BAAANQAECggIDwAAAA==.',
Fe='Feldra:BAAANQAECgYICwAAAA==.',
Fi='Finnin:BAAANQAECgQIBQAAAA==.',
Fo='Food:BAAANQAECgQIBQAAAA==.',
Fr='Frozenfaith:BAAANQAECgQIBQAAAA==.',
Fu='Furba:BAAANQAECgYIDgAAAA==.Furiouswind:BAAANQAECgQICQAAAA==.Furyvolt:BAAANQAECgMIAwAAAA==.',
Gh='Ghettomike:BAAANQAECgQICQAAAA==.Ghold:BAAANQAECgcICwAAAA==.',
Gi='Giranimo:BAAANQADCggIDgAAAA==.',
Gl='Glabados:BAAANQADCgcICAABNQAECgQICQADAAAAAA==.Glossy:BAABNQAECoEaAAMKAAgJhCQSDgBNAgAKAAYJjSQSDgBNAgALAAQJbiPMGgCnAQAAAA==.Glossyrage:BAAANQADCgcIBwAAAA==.',
Go='Gors:BAAANQAECgQIBQAAAA==.',
Gr='Gratiaplena:BAAANQABCgQIBwAAAA==.',
Ha='Halîk:BAAANQAECgYICQAAAA==.Hardheaded:BAAANQADCggICAAAAA==.Hathina:BAABNQAECoEXAAMMAAkJYiIOAQAsAwAMAAgJlCIOAQAsAwANAAEJyyD/xQBcAAAAAA==.',
He='Hedetet:BAAANQABCgEIAQABNQAECgQICQADAAAAAA==.Herath:BAAANQABCggIDwAAAA==.',
Hi='Hill:BAAANQAECgQICQAAAA==.Hive:BAABNQAECoEXAAINAAgJDQryVwDSAQANAAgJDQryVwDSAQAAAA==.',
Hu='Husentar:BAAANQADCgYICwAAAA==.',
Ic='Icaron:BAAANQADCggIAQAAAA==.',
Ig='Igni:BAAANQABCgMIBAAAAA==.',
Il='Illuminottey:BAAANQADCgEIAQAAAA==.',
In='Inferium:BAAANQADCgcIBwAAAA==.Insatiabull:BAAANQADCgYIBgABNQAECgkJGwABANYhAA==.',
Ir='Iriaena:BAAANQADCgYIDwAAAA==.',
Is='Ishaa:BAAANQADCgEIAQAAAA==.',
Ja='Jackstands:BAABNQAECoEXAAIEAAgJ+xeiJwAqAgAEAAgJ+xeiJwAqAgAAAA==.Jagerin:BAAANQAECgEIAQABNQAECgQICQADAAAAAA==.January:BAAANQAECgcIEwAAAA==.Jaquesita:BAAANQAECgIIAgAAAA==.Jarry:BAAANQADCggIDAAAAA==.',
Je='Jeannine:BAAANQADCgUIBQAAAA==.',
Ju='Junn:BAAANQAECgQICQAAAA==.',
['Já']='Jánuary:BAAANQADCgYIBgAAAA==.',
Ka='Kahayman:BAABNQAECoEaAAMJAAkJUw4IUQBYAgAJAAkJUw4IUQBYAgAOAAQJagSQFQCmAAAAAA==.Kaimari:BAAANQAECgQIBwAAAA==.Kazuya:BAAANQAECgEIAQAAAA==.',
Ke='Kennyboi:BAAANQADCgIIAgAAAA==.',
Kh='Khaibit:BAABNQAECoEWAAIPAAgJnB4HCwCnAgAPAAgJnB4HCwCnAgAAAA==.Khathani:BAAANQADCgQIBwAAAA==.',
Ki='Kissofdeath:BAAANQAECgQIBgAAAA==.',
Ko='Komojo:BAAANQADCggIEQAAAA==.Koriggan:BAAANQADCggIEwAAAA==.',
Kr='Krea:BAAANQADCggIEAAAAA==.Kroval:BAAANQADCggIFwAAAA==.Krystagosa:BAAANQAECgQIBQAAAA==.',
Ku='Kuriuh:BAAANQAECgQICQAAAA==.',
Ky='Kybo:BAAANQABCgMIAwABNQAECgkJGQACACYgAA==.Kyo:BAAANQADCgUIBQAAAA==.',
La='Lang:BAAANQAECgQIBgAAAA==.',
Li='Lightdogg:BAAANQAECgUIBgAAAA==.Limaia:BAAANQAECgIIAgAAAA==.Linia:BAAANQAECgEIAQAAAA==.',
Lu='Luceriss:BAAANQAECgcIDgAAAA==.Lulilaj:BAAANQAECgUICgAAAA==.',
Ma='Maike:BAAANQAECgMIAwAAAA==.Marothius:BAABNQAECoEcAAMGAAkJtho+IgBjAgAGAAgJihg+IgBjAgAQAAUJsBqlFgCTAQAAAA==.Marrius:BAAANQADCgYIBwAAAA==.Martaug:BAABNQAECoEVAAIEAAgJ0yCnDAAAAwAEAAgJ0yCnDAAAAwAAAA==.Marune:BAAANQAECgQICQAAAA==.Maverage:BAAANQAECgQIBAAAAA==.Mayfair:BAAANQABCgQICAAAAA==.',
Me='Melee:BAABNQAECoEUAAIIAAgJYRyrKwBhAgAIAAgJYRyrKwBhAgAAAA==.Metal:BAAANQADCgcIEwAAAA==.',
Mi='Minimee:BAAANQAECgEIAQAAAA==.Miquella:BAAANQAECgQICAAAAA==.',
Mo='Mollymauk:BAAANQADCgQIBAABNQAECgcICwADAAAAAA==.Monkstrosity:BAAANQAECgYIEAAAAA==.Mookks:BAAANQADCgUIBQAAAA==.Moonn:BAAANQABCggICAAAAA==.Moor:BAAANQAECgEIAQAAAA==.Mordakka:BAAANQAECgcIDQAAAA==.Morior:BAAANQAECgcIEQAAAA==.',
Mu='Mulletmaster:BAAANQAECgQIBAAAAA==.Murrda:BAAANQAECggIDgAAAA==.',
My='Myrokos:BAABNQAECoEXAAIIAAgJ0R0EIgCaAgAIAAgJ0R0EIgCaAgAAAA==.',
['Mö']='Möokss:BAAANQAECgUICQAAAA==.',
Na='Nailo:BAAANQADCggICAAAAA==.Nasperus:BAAANQABCgIIAgAAAA==.',
Ni='Niddy:BAAANQAECgUICgAAAA==.',
No='Nobudee:BAAANQADCgcIBwABNQAECgkJGwARAPccAA==.Nocandles:BAAANQAECgMIAwAAAA==.Noebuddie:BAABNQAECoEbAAIRAAkJ9xy9DQAiAwARAAkJ9xy9DQAiAwAAAA==.Noel:BAAANQAECgEIAQAAAA==.Nonospot:BAAANQAECgMIAwAAAA==.Noraboo:BAAANQADCggIHQABNQAECgIIAgADAAAAAA==.Norganon:BAAANQAECgEIAQAAAA==.',
Nv='Nvied:BAAANQAECgUICAAAAA==.',
Ny='Nyctt:BAAANQAECgcIEwAAAA==.Nyzstra:BAAANQAECgYICwAAAA==.',
['Nê']='Nêwt:BAABNQAECoEVAAIJAAgJjAzZcQDxAQAJAAgJjAzZcQDxAQAAAA==.',
On='Onlybeams:BAAANQAECgQICQAAAA==.',
Or='Oreo:BAAANQADCgcIEQAAAA==.Orphu:BAAANQADCgQIBwAAAA==.',
Pa='Palmiste:BAAANQADCgYICQAAAA==.Pandoora:BAAANQADCgYIEAAAAA==.Parahsalin:BAAANQAECgMIBAAAAA==.Pastryblust:BAABNQAECoEbAAIRAAkJRh0cDQApAwARAAkJRh0cDQApAwAAAA==.',
Pi='Pistachio:BAAANQADCgcIFQAAAA==.Pitviper:BAAANQAECgQICQAAAA==.',
Po='Pogaca:BAAANQADCggIEwAAAA==.Portabull:BAAANQADCgcIBwABNQAECgkJGwABANYhAA==.',
Pr='Precogvendor:BAAANQADCgcIDQAAAA==.',
Ra='Rai:BAAANQAECgQIBgAAAA==.Ramens:BAAANQADCgIIAgAAAA==.Rapha:BAAANQAECgQICQAAAA==.Rayyzor:BAAANQAECgQICQAAAA==.',
Re='Reality:BAAANQADCgQICAAAAA==.Realtree:BAAANQADCgQIBwAAAA==.',
Ri='Riddles:BAAANQAECgQIBAAAAA==.',
Ro='Rot:BAAANQAECgQICQAAAA==.',
Sa='Santino:BAAANQADCgcICAABNQAECgkJGgAJAFMOAA==.Saphlocket:BAAANQAECgEIAgAAAA==.Saphmage:BAAANQAECgEIAQAAAA==.Sathin:BAAANQAECgQIBgAAAA==.',
Sc='Scher:BAAANQADCgYIBgAAAA==.Scufalufagus:BAAANQADCgUIBQABNQAECgkJHAAGALYaAA==.',
Se='September:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.',
Sf='Sfcwarner:BAAANQADCgYICwAAAA==.',
Sh='Shampooyou:BAAANQADCggIGAAAAA==.',
Si='Silentkit:BAAANQAECgQIBgAAAA==.',
St='Stardel:BAAANQAECgQIBAABNQAECgkJHAAKADgjAA==.Stormclaw:BAAANQAECgUIDAAAAA==.Stregglebus:BAAANQADCggIFAABNQAECgkJHAAGALYaAA==.Stroggosh:BAAANQADCggIEgABNQAECgkJHAAGALYaAA==.',
Su='Suhfering:BAAANQADCgcIBwABNQAECgQICQADAAAAAA==.Sunshot:BAAANQAECgEIAQAAAA==.',
Ta='Takrusani:BAAANQADCgIIAgAAAA==.Tallron:BAABNQAECoEcAAISAAkJCxrBBwDNAgASAAkJCxrBBwDNAgAAAA==.Tamedsloth:BAAANQADCgcIDQAAAA==.Tanerella:BAAANQADCgcIBwAAAA==.',
Th='Thrustruggle:BAAANQAECgQIBAAAAA==.',
Ti='Timir:BAABNQAECoEcAAIIAAkJaBcZLABfAgAIAAkJaBcZLABfAgAAAA==.',
To='Tojikitoushi:BAAANQAECgcIEwAAAA==.Totenhammer:BAAANQADCgYIBwAAAA==.Touche:BAAANQAECgQIBAAAAA==.',
Tr='Tribulate:BAAANQADCggIDAAAAA==.Trollyroller:BAAANQADCggIFAAAAA==.',
Tw='Twistedfrost:BAAANQADCgUIBQAAAA==.',
Ul='Ulrein:BAAANQADCggIHgAAAA==.',
Ve='Vextt:BAAANQAECgUICgABNQAECgcICwADAAAAAA==.Veylira:BAAANQAECgUICwABNQAECgkJIAANAIwWAA==.',
Vi='Vitner:BAAANQAECggICAAAAA==.',
Vo='Voidra:BAAANQADCgYIBgAAAA==.Volight:BAAANQAECgQIBgAAAA==.Volke:BAAANQAECgQICQAAAA==.Voltarix:BAAANQADCgEIAQAAAA==.Voyria:BAAANQAECgQIBgAAAA==.',
Wa='Warm:BAAANQAECgQICAAAAA==.',
We='Weeziveli:BAAANQADCgYIBgAAAA==.Weledish:BAABNQAECoEcAAMJAAkJexz/WAA+AgAJAAkJexz/WAA+AgAOAAIJbg5yGQB4AAAAAA==.Weleron:BAAANQADCgIIAgAAAA==.',
Wi='Widdles:BAAANQAECgMIAwAAAA==.',
Yi='Yinyangfaith:BAAANQADCgEIAQABNQAECgQIBQADAAAAAA==.',
Zo='Zomgdk:BAABNQAECoEXAAITAAgJdR1pEgCmAgATAAgJdR1pEgCmAgAAAA==.',
Zy='Zynthia:BAAANQADCgQIBAAAAA==.',
['Äm']='Ämäteräsu:BAAANQAECggIAQAAAA==.',
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
