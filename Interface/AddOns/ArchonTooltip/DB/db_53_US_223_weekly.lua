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

local lookup = {'Unknown-Unknown','Druid-Feral','Druid-Guardian','Hunter-BeastMastery','Monk-Windwalker','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Frost','Mage-Arcane','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Shaman-Enhancement','Priest-Holy','Priest-Discipline','Warlock-Demonology','Shaman-Elemental','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Paladin-Protection','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='TolBarad',name='US',type='weekly',zone=53,date='2026-10-20',data={Ai='Airfryer:BAAANQADCggIEAABNQAECgQICgABAAAAAA==.',
Aj='Ajudando:BAABNQAECn8jAAMCAAgKXB/7CAC+AgACAAgK/h77CAC+AgADAAMK0BoPKgBkAAAAAA==.',
An='Anardil:BAAANQADCgUIBQAAAA==.Anneliese:BAAANQADCgIIAgAAAA==.',
Ar='Arcane:BAAANQADCgUIBQABNQAECgkJHgAEAJQfAA==.Artesuda:BAAANQAECgQIBQAAAA==.',
At='Atomos:BAAANQAECgQIBAAAAA==.',
Au='Aurelya:BAAANQAECgEIAQAAAA==.',
Az='Aznat:BAABNQAECn8bAAIFAAYK1QrnOwA2AQAFAAYK1QrnOwA2AQABNQADCgYIBgABAAAAAA==.',
Ba='Bachir:BAAANQAECgEIAgAAAA==.Balmhung:BAAANQABCgIIAgAAAA==.',
Be='Behelfslösun:BAAANQADCgMIAwABNQAECggIJQAGAG8kAA==.Bellatryx:BAAANQAECgEJAQAAAA==.',
Bi='Bianca:BAAANQAECgQIAwAAAA==.',
Bu='Burkiel:BAAANQAECgcIBwABNQAECgkJLAAEABwgAA==.',
Ca='Calangosauro:BAABNQAECn8eAAQHAAkKshWsHAAAAgAHAAgK8RWsHAAAAgAIAAYK/xOzCADhAAAJAAEKUhiRDABJAAAAAA==.Caoss:BAABNQAECn8lAAIKAAoKUhqfLQCsAgAKAAoKUhqfLQCsAgAAAA==.',
Ch='Chinchanchen:BAAANQADCgYICQAAAA==.Chronicles:BAABNQAECn8iAAMLAAkKEhfKNAAHAgALAAgK2BfKNAAHAgAMAAgKPxFOMgCvAQAAAA==.',
Cr='Cremador:BAAANQAECgEIAgAAAA==.',
Ct='Cthylla:BAAANQADCggICAAAAA==.',
Da='Dabura:BAAANQAECgYIDwAAAA==.',
De='Devilton:BAABNQAECn8gAAILAAgKZg19RwCNAQALAAgKZg19RwCNAQAAAA==.',
Do='Dohade:BAAANQADCgYICgAAAA==.Donapala:BAAANQADCggICAAAAA==.Donnus:BAABNQAECn8fAAMNAAgKdB99BwB4AgAOAAgKtRtlgAB+AgANAAcKCR99BwB4AgAAAA==.',
Dr='Dragolancer:BAAANQADCgYIBgAAAA==.Drakonvolk:BAAANQADCgUIBQABNQAECgkJGAAEAJobAA==.Draven:BAAANQADCggIGQAAAA==.Drystan:BAAANQAECgQICAAAAA==.',
['Dá']='Dárkangel:BAAANQADCgQIBAAAAA==.',
Ed='Edy:BAABNQAECn8eAAIEAAoKdyE/DQB1AwAEAAoKdyE/DQB1AwAAAA==.',
Ei='Einheriar:BAAANQADCgQIBAAAAA==.',
El='Elanna:BAAANQADCgYIBgAAAA==.Elanya:BAAANQAECgQIAwAAAA==.Elidaryel:BAAANQAECgEIAQAAAA==.',
Em='Emie:BAAANQADCgMIAwAAAA==.',
En='Enrique:BAAANQADCgUIBgAAAA==.',
Eq='Equilibrium:BAAANQADCggICgAAAA==.',
Er='Eryeth:BAABNQAECn8qAAIPAAkKWhdCFQC2AgAPAAkKWhdCFQC2AgABNQADCgYIBgABAAAAAA==.',
Ex='Excloud:BAAANQADCgYIDAAAAA==.',
Fa='Farator:BAAANQAECgQIBAAAAA==.',
Fi='Fire:BAABNQAECn8VAAMQAAoK0woMawBmAQAQAAkKKQoMawBmAQARAAIKGBRpsgBlAAAAAA==.Firedofogo:BAAANQAECgEIAgAAAA==.',
Fo='Fongsayuk:BAAANQAECgYIBgAAAA==.',
['Fê']='Fênrir:BAAANQAECgIIAwAAAA==.',
Ga='Gablle:BAABNQAECn8gAAMSAAgKOQlAGQBPAQASAAgKAQdAGQBPAQAFAAEKPhkDawA0AAAAAA==.Gabtvshami:BAAANQADCgMIAwAAAA==.',
Ge='Genyun:BAAANQAECgYICQAAAA==.',
Gr='Grongos:BAAANQAECgcIAQAAAA==.',
Ha='Hakoda:BAAANQADCgYIGAAAAA==.',
He='Hergor:BAAANQAECggICwAAAA==.',
Ja='Jaïnä:BAAANQABCgQIBAAAAA==.',
Ka='Kaelson:BAAANQAECgEIAQAAAA==.Kams:BAAANQAECgYIEQAAAA==.Karynna:BAAANQAECgUIBQABNQAECgcIFgARAOsRAA==.',
Kh='Khaty:BAAANQADCgIIAwABNQAECgQIBQABAAAAAA==.',
Ki='Kilaraus:BAAANQADCgMIAwAAAA==.',
Kr='Krzero:BAABNQAECn8YAAIEAAkKmhugWwBiAgAEAAkKmhugWwBiAgAAAA==.',
['Kã']='Kãrlã:BAAANQADCgYIBgAAAA==.',
La='Lalalana:BAAANQADCgYICwAAAA==.Laylavolk:BAAANQAECgYIDgABNQAECgkJGAAEAJobAA==.',
Lc='Lcabronehboy:BAAANQADCggIFwAAAA==.',
Le='Lexan:BAABNQAECn8fAAMTAAcK9BUIGgDDAQATAAcK9BUIGgDDAQAKAAEKSgJENQEbAAAAAA==.',
Li='Linso:BAABNQAECn8fAAQPAAkKpRUfIgAkAgAPAAcKvBkfIgAkAgAUAAQKNRZeuwDnAAAVAAEKLgfFKwAtAAAAAA==.Lissão:BAAANQAECgQJBAAAAA==.',
Lo='Lowstheby:BAAANQAECgQIEAABNQAECgcIHwAWAFkcAA==.',
Lu='Lucians:BAACNQAFFH8NAAIKAAQK4xJHEgAsAQAKAAQK4xJHEgAsAQA1AAQKfz4AAwoACgomIpEQAEADAAoACgomIpEQAEADABcABAp1GU++ABYBAAAA.',
Ly='Lylithe:BAAANQADCgQIBAAAAA==.Lynn:BAAANQADCgIIAgAAAA==.',
Ma='Madafaka:BAAANQADCgIIAgAAAA==.Madarame:BAAANQAECggIDwABNQADCgYIBgABAAAAAA==.Madow:BAABNQAECn8fAAIWAAcKWRyrZAAsAgAWAAcKWRyrZAAsAgAAAA==.Magmafire:BAABNQAECn81AAIOAAkKOCIxEQCNAwAOAAkKOCIxEQCNAwAAAA==.Malakain:BAAANQADCgYIBwAAAA==.Maressa:BAABNQAECn8eAAIYAAkKARrYVQCUAgAYAAkKARrYVQCUAgAAAA==.Maverine:BAAANQADCggIEAAAAA==.',
Me='Melleron:BAAANQAECgIIAgAAAA==.Merlym:BAAANQADCgYIBgAAAA==.Merüem:BAABNQAECn8XAAIZAAgK2xUxEwB7AQAZAAgK2xUxEwB7AQAAAA==.',
Mi='Mitsy:BAAANQADCgYIBgAAAA==.',
Mo='Moffzkun:BAAANQAECgEIAQAAAA==.Moraxes:BAAANQADCggICQAAAA==.Morion:BAAANQADCgMIAwAAAA==.Morterubra:BAAANQAECgQICgAAAA==.Mozart:BAAANQAECggIEgABNQAFFAEIAQABAAAAAA==.Mozârt:BAAANQAFFAEIAQABNQAFFAEIAQABAAAAAA==.',
Mu='Musphelheim:BAAANQADCgYJDAAAAA==.',
['Më']='Mëlisandre:BAAANQAECgQIBAABNQAECgkJKgAEAFQUAA==.',
['Mø']='Mørrighan:BAAANQAECgEIAgAAAA==.Møzartt:BAAANQAFFAEIAQAAAA==.Møzârtt:BAAANQAECggIEgABNQAFFAEIAQABAAAAAA==.',
Na='Naivor:BAAANQADCgUIBQAAAA==.',
Ne='Necrolórd:BAAANQADCgQIBAAAAA==.',
Nu='Nucked:BAAANQADCgcIDQAAAA==.',
Ny='Nyssara:BAAANQADCgUIBgAAAA==.',
On='Onövis:BAAANQADCggICAAAAA==.',
Os='Osiresdr:BAABNQAECn8aAAIaAAgKaBBkIQB9AQAaAAgKaBBkIQB9AQAAAA==.Osíris:BAAANQAECgEIAQAAAA==.',
Pa='Panchorf:BAABNQAECn8gAAIbAAgKiAaCPQAJAQAbAAgKiAaCPQAJAQAAAA==.',
Pe='Peixonalta:BAAANQABCgMIAwAAAA==.',
Pr='Prihunter:BAABNQAECn8gAAIEAAgKAwSi2ABPAQAEAAgKAwSi2ABPAQAAAA==.Primanocte:BAAANQABCggICwAAAA==.',
Pu='Pudincessa:BAAANQAECgQIBAAAAA==.',
Re='Rellana:BAAANQADCgcIDwABNQAECgQICgABAAAAAA==.',
Ri='Rizúl:BAAANQAECgYIEQAAAA==.',
Rl='Rldsbvb:BAAANQADCgYIBgAAAA==.',
Ro='Rosemyne:BAABNQAECn8XAAIWAAYKJgd19wDcAAAWAAYKJgd19wDcAAAAAA==.',
['Rö']='Röku:BAAANQADCgcIDgABNQAECgQICgABAAAAAA==.',
Sa='Sabedetudo:BAAANQAECgMIAgAAAA==.Sadomie:BAAANQAECggIEQAAAA==.',
Sc='Scarxantalaz:BAAANQADCgQIBAAAAA==.Schnaider:BAAANQABCgIIAgAAAA==.',
Sh='Shaddow:BAAANQADCgQIBAAAAA==.Sheeny:BAAANQADCgQIBAAAAA==.',
Si='Sinco:BAAANQAECgYIDAAAAA==.Sixx:BAAANQAECgUICAAAAA==.',
Su='Suoling:BAAANQAECgEJAQAAAA==.',
Sw='Sweej:BAABNQAECn8uAAIDAAkK4hmBDQCOAgADAAkK4hmBDQCOAgAAAA==.',
Sy='Syegfryed:BAAANQAECgYIBgAAAA==.',
Ta='Tahir:BAAANQAECgEIAwAAAA==.',
Te='Tekuleo:BAAANQADCggIJwAAAA==.Temptation:BAAANQADCgYIBgAAAA==.',
Th='Thrain:BAACNQAFFH8GAAIcAAMKdRfFAQCxAAAcAAMKdRfFAQCxAAA1AAQKfyEAAxwACgpTGpwEAIsBAB0ACAr3F1qWAOQBABwABAqKH5wEAIsBAAAA.',
Ty='Tyozaum:BAAANQADCgIIAgAAAA==.',
Va='Valdor:BAAANQADCgYIDgAAAA==.',
Ve='Veltharys:BAAANQAECgQIBwAAAA==.Ventania:BAAANQADCggIFwAAAA==.',
Vi='Vizeke:BAAANQABCgYICwAAAA==.',
Wa='Warmask:BAAANQAECgEIAQAAAA==.Watislock:BAAANQAECgcICwAAAA==.',
Wo='Wonderkast:BAAANQAECgMIBgABNQAFFAgIHQAPAGghAA==.',
Wu='Wurdulak:BAAANQADCggIEgAAAA==.',
Xa='Xamelo:BAABNQAECn8cAAIKAAcKnyJnKwC1AgAKAAcKnyJnKwC1AgAAAA==.',
Yo='Yona:BAAANQADCgYIGwABNQADCggIEAABAAAAAA==.',
Za='Zadockn:BAAANQAECgEIAgAAAA==.',
Ze='Zelena:BAAANQAECgEIAQAAAA==.',
Zu='Zughy:BAAANQAECgMICQABNQAFFAgIHQAPAGghAA==.',
['Zé']='Zédaplanta:BAAANQAECgQIBAAAAA==.',
['Är']='Ärkin:BAAANQADCggIFQABNQAECgQICgABAAAAAA==.',
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
