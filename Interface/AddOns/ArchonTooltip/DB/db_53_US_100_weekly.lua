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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Unknown-Unknown','Evoker-Preservation','DeathKnight-Unholy','Shaman-Elemental','Mage-Arcane','Hunter-Survival','DeathKnight-Blood','Priest-Holy','Evoker-Devastation','Shaman-Enhancement','Druid-Balance','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Protection','Paladin-Holy','Monk-Windwalker','Warlock-Demonology','Shaman-Restoration','Warlock-Affliction','Druid-Feral','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aamodar:BAAANQAECgIJBAAAAA==.',
Ab='Abadon:BAAANQAECgYIBwAAAA==.',
Ad='Adino:BAAANQAECgUJCQAAAA==.Adorabell:BAAANQADCggICAABNQAFFAMIBQABAMoTAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAAANQAECgUJCQAAAA==.Aeryn:BAABNQAECoEiAAICAAkK7SHiDQBlAwACAAkK7SHiDQBlAwAAAA==.Aerís:BAAANQAECgEJAQAAAA==.',
Ag='Agrolazor:BAABNQAECoEZAAIDAAgK4RSOFABYAgADAAgK4RSOFABYAgAAAA==.',
Ah='Ahtee:BAAANQAECgUICgAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Albarino:BAAANQADCgYJBgAAAA==.Alseena:BAAANQAECgMIBAAAAA==.',
Am='Amun:BAAANQADCgIJAgAAAA==.',
An='Anaru:BAAANQADCgUIBAAAAA==.Anvar:BAABNQAECoEbAAMBAAgKex5IHQDLAgABAAgKex5IHQDLAgAEAAUKmggwNwDxAAAAAA==.',
Ar='Arathion:BAAANQAECgYICgAAAA==.Arcanemommy:BAAANQAECggJAQAAAA==.Arianrhod:BAAANQAECgYICQAAAA==.Arx:BAAANQAECgcIEQAAAA==.',
As='Ashaldrin:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgEIAQAAAA==.',
At='Atrumdeus:BAABNQAECoEhAAICAAgKMhjWPQBbAgACAAgKMhjWPQBbAgAAAA==.',
Au='Audiamer:BAAANQAECgYJCgAAAA==.Aufsela:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.',
Ba='Babydragon:BAABNQAECoEYAAIGAAgK6BL3FAABAgAGAAgK6BL3FAABAgAAAA==.Babysaja:BAAANQAECgEIAQAAAA==.Bangerz:BAAANQAECgUJBQAAAA==.Bannann:BAAANQAECgYJDAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECoEWAAIHAAkKnyCnCABYAwAHAAkKnyCnCABYAwAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgUJCQAAAA==.Belldia:BAACNQAFFIEFAAIBAAMKyhMwCAANAQABAAMKyhMwCAANAQA1AAQKgR4AAgEACQokG+IWAPECAAEACQokG+IWAPECAAAA.Belphaegor:BAAANQAECgQJBwAAAA==.Beni:BAAANQADCgEIAQAAAA==.Beniaru:BAAANQAECgUIDQAAAA==.Bennyflipz:BAAANQAECgEIAQAAAA==.',
Bi='Bigmuzz:BAAANQADCgUJBwAAAA==.Bigsneaki:BAAANQADCgUJBQAAAA==.',
Bl='Blightedmilk:BAAANQAECgIIAgABNQAECgcJEQAFAAAAAA==.Bloopmasta:BAAANQADCggICgAAAA==.Blufox:BAAANQAECggJDQAAAA==.',
Bo='Bobfresh:BAABNQAECoEeAAIIAAkKliEUCgBuAwAIAAkKliEUCgBuAwAAAA==.Bootwitdafur:BAAANQADCggICAAAAA==.',
Br='Broherum:BAAANQADCgQJBAAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYJCwAAAA==.Buckbeak:BAAANQADCggICAABNQAECgkJFgAHAJ8gAA==.Busting:BAAANQAECggIEAAAAA==.',
['Bà']='Bàhamut:BAAANQADCgUJBwAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQADCgYJBgABNQAECgUICQAFAAAAAA==.Captchaos:BAAANQADCgYIBQAAAA==.Carritha:BAAANQADCgYJCQABNQAECgMJBwAFAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAAANQAECgYIDwAAAA==.',
Ch='Chimneybones:BAAANQAECgYJCgAAAA==.Chizz:BAABNQAECoEcAAIJAAkKHQwigwAPAgAJAAkKHQwigwAPAgAAAA==.Chriswong:BAAANQAECgEIAQAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chá:BAAANQADCggIEAABNQAECgkJHAAHAOsfAA==.',
Cl='Clairebenet:BAABNQAECoEZAAMBAAgK8RtJJwCZAgABAAgK8RtJJwCZAgAKAAEKMhbxDABBAAAAAA==.Cleph:BAAANQABCggJDgAAAA==.Clumzylock:BAAANQAECgQIBgABNQAECgcIJAALAMATAA==.Clumzyninja:BAABNQAECoEkAAILAAcKwBOoNwC5AQALAAcKwBOoNwC5AQAAAA==.',
Co='Code:BAAANQADCggICAABNQAFFAUJCgAIALIWAA==.Coolbreez:BAAANQADCgYICQAAAA==.Coolynn:BAAANQAECgMJBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Crew:BAAANQADCggICgAAAA==.',
Cu='Cumb:BAAANQADCggICgABNQAECgkJHgAIAJYhAA==.',
['Cä']='Cäldius:BAAANQADCgMIAwAAAA==.',
Da='Daioh:BAAANQADCgYICwAAAA==.Damacraze:BAAANQAECgUJCwAAAA==.Danielwu:BAAANQAECgcICgAAAA==.Dawigrund:BAAANQAECgUJBwAAAA==.',
De='Deadroar:BAABNQAECoEXAAILAAgKcRbZLwDnAQALAAgKcRbZLwDnAQABNQAFFAEIAQAFAAAAAA==.Deadtomato:BAAANQAECgMIAwAAAA==.Deadwill:BAAANQAECgQJCQAAAA==.Deadzug:BAAANQAECgUIBQABNQAECggJGwABAHseAA==.Deaminase:BAAANQAECgUIBQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECoEcAAIMAAgKEBlPLgA/AgAMAAgKEBlPLgA/AgAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAAANQAECgIJAgAAAA==.Demidru:BAAANQAECgIJBAAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMJBgAFAAAAAA==.Deshojo:BAAANQAECgUIBQAAAA==.Desrook:BAAANQAECgIIAgAAAA==.',
Dh='Dhqt:BAAANQAECgEJAQABNQADCgcICQAFAAAAAA==.',
Di='Divinèhero:BAAANQAECgEJAQAAAA==.',
Do='Doomgirl:BAAANQADCggJEAAAAA==.Double:BAAANQAECgIIAgAAAA==.Doublelift:BAABNQAECoEbAAMDAAgK9h6aEgB3AgADAAcKfB6aEgB3AgAMAAQKbxJtdgD+AAAAAA==.',
Dr='Dragondeznut:BAAANQADCggJDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgEJAQAFAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAAANQAECgQJBwAAAA==.Drpumper:BAAANQAECgIIAgAAAA==.Dröbi:BAABNQAECoEeAAINAAkKRx/5BAAaAwANAAkKRx/5BAAaAwAAAA==.',
Du='Dundundun:BAAANQAECgYICwAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
Eg='Eggdrop:BAAANQAECgQJBAAAAA==.Egufro:BAAANQAECgEIAQABNQAECgkJIQAOAEcQAA==.',
Eh='Ehgu:BAABNQAECoEhAAIOAAkKRxCnCQCBAgAOAAkKRxCnCQCBAgAAAA==.',
El='Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAAANQAECgMJAwAAAA==.Elynnah:BAAANQAECgEIAQAAAA==.',
Em='Emidget:BAAANQAECgEJAQAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMJBwAFAAAAAA==.',
Er='Erhmer:BAAANQAECggIAgAAAA==.',
Et='Etom:BAAANQAECggIBAAAAA==.',
Ev='Eviae:BAAANQADCgQIBAAAAA==.',
Fa='Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQADCgQIBAABNQADCgcICQAFAAAAAA==.Fatfatfat:BAAANQAECgEIAQABNQAFFAEIAQAFAAAAAA==.Fañgrat:BAAANQAECgQJBAABNQADCgcICQAFAAAAAA==.',
Fe='Femboyluvr:BAAANQAECgEJAQAAAA==.',
Fi='Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flandia:BAAANQAECgYICgAAAA==.Floppiterry:BAAANQAECgUJCQAAAA==.Floppyterry:BAAANQADCgUIBQAAAA==.Flow:BAAANQAECgYJDwAAAA==.',
Fo='Fowl:BAAANQAECgUIDAAAAA==.',
Fr='Fricher:BAAANQAECgYICgAAAA==.Froznrage:BAABNQAECoEkAAIOAAkKEh7AAgBYAwAOAAkKEh7AAgBYAwAAAA==.',
Fy='Fylerianprie:BAAANQAECgMIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQABCgYIBgAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgEIAQABNQAECgkJFgAHAJ8gAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghettomike:BAAANQADCgQJBAAAAA==.',
Gi='Giny:BAAANQAECgUJCgAAAA==.',
Go='Gobbledeez:BAAANQAECgYICgAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Govinniuur:BAAANQAECgIJAgAAAA==.',
Gr='Grasfedjones:BAAANQAECgIJAgAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAAANQAECgYICwAAAA==.Grue:BAAANQADCggIEAAAAA==.',
Gw='Gwendilyn:BAAANQADCggJEAAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIBgAAAA==.',
Ha='Hafadude:BAAANQADCggIBQAAAA==.Hahgottum:BAAANQAECgQJAgAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAAANQAECgQJBgAAAA==.',
Ho='Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgEJAQABNQAECgEJAQAFAAAAAA==.Holyyshift:BAAANQAECgEJAQAAAA==.Horhel:BAAANQAECgEJAQAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.',
Hy='Hyperiann:BAAANQADCgQIBAAAAA==.',
Ia='Iamfried:BAABNQAECoEYAAIPAAgKAhrXIABnAgAPAAgKAhrXIABnAgAAAA==.',
Ic='Iceyrot:BAAANQADCgcIBwAAAA==.',
Ig='Igran:BAAANQAECgEIAQAAAA==.',
Ih='Ihatemodels:BAAANQADCgIIAgAAAA==.',
Il='Illidigle:BAAANQADCggIDAAAAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECoEZAAMQAAgKbRk+FQBzAgAQAAgKbRk+FQBzAgARAAEKjAjtXABDAAAAAA==.Innarius:BAAANQADCgMIAwAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECgQIBwAAAA==.',
Ir='Ironheãrt:BAABNQAECoEZAAISAAgKjhu5CwBqAgASAAgKjhu5CwBqAgAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAAANQAECggIDgAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAgAAAA==.',
It='Itai:BAABNQAECoEcAAIHAAkK6x/iCgA3AwAHAAkK6x/iCgA3AwAAAA==.',
Iv='Iverson:BAAANQABCgYICgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgYJEQAFAAAAAA==.',
Ja='Jackk:BAACNQAFFIEMAAITAAUKiBhtBAC0AQATAAUKiBhtBAC0AQA1AAQKgSAAAxMACQoUJDwEAI8DABMACQoUJDwEAI8DAAIAAgplCZv+AF0AAAAA.Jackks:BAAANQAECgQIBgABNQAFFAUJDAATAIgYAA==.Jaddix:BAAANQADCgYICwAAAA==.Jasmonk:BAAANQAECgYICgAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAAANQADCgQIAwAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgIIAgABNQAECggIBAAFAAAAAA==.Jinkz:BAAANQADCggJGwAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggJDgAAAA==.',
Ju='Judgevis:BAAANQAECgYJDAAAAA==.Jumbles:BAAANQADCggJEAAAAA==.',
Jy='Jynxy:BAAANQADCggJDQAAAA==.',
['Jø']='Jøshu:BAAANQADCgYJBgABNQAECgEIAQAFAAAAAA==.',
Ka='Kaeliis:BAAANQAECgMIBQAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAAANQAECgEIAQAAAA==.',
Kb='Kbeckinsale:BAAANQAECgYICgABNQAECggIFgAJAC8RAA==.',
Ke='Keladun:BAAANQADCgUJDwAAAA==.',
Kh='Kharga:BAAANQAECgQICgAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAUICAAJAEUXAA==.',
Ki='Kidgroove:BAAANQADCgEIAQAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Ko='Konamy:BAAANQAECgUJBgAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAAANQAECgcIDwAAAA==.',
Kr='Kriss:BAAANQADCggJCQAAAA==.Kristeena:BAAANQADCggIEAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAAANQAECgIIAgAAAA==.Kröw:BAAANQAECgcJDgAAAA==.',
Ku='Kudrix:BAAANQAECgQJBwAAAA==.Kurø:BAAANQADCggJEAAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgIIAgAAAA==.Laurijaydn:BAAANQAECgYIBgAAAA==.Laurynn:BAAANQADCggJDQAAAA==.',
Le='Legionremix:BAAANQADCggJCQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQADCgMIAwAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHAAMABUSAA==.Littlestarz:BAAANQAECgUICAAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgcIGAABAKgRAA==.',
Ll='Llazz:BAAANQAECgcIBwAAAA==.Llemons:BAAANQAECgQIBAABNQAECggICQAFAAAAAA==.',
Lo='Locknlizzie:BAEBNQAECoEYAAIBAAcKqBEgWgDgAQABAAcKqBEgWgDgAQAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggJEQAAAA==.',
Lu='Luke:BAAANQAECgQIBQAAAA==.Luminali:BAAANQAECgQIBgABNQAECgYJBgAFAAAAAA==.Luminari:BAAANQAECgYJBgAAAA==.Lunadari:BAAANQAECgIJAwAAAA==.Lunareva:BAAANQAECgUICQAAAA==.',
Ly='Lyxon:BAAANQADCggIFQAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lí']='Lílîth:BAAANQAECgEIAQAAAA==.',
Ma='Mael:BAAANQADCgQJBAAAAA==.Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAAANQAFFAEJAQAAAA==.Magicalama:BAABNQAECoEeAAIJAAgK7RdzbQBKAgAJAAgK7RdzbQBKAgAAAA==.Magiplex:BAAANQADCggJCAAAAA==.Magnanimity:BAEANQAECgEIAQABNQAECgQICQAFAAAAAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAAANQAECggICQAAAA==.Makto:BAAANQADCgYICAAAAA==.Malia:BAAANQADCggJFwAAAA==.Maliciouso:BAAANQAECgcIDgAAAA==.Malédiction:BAAANQAECgQIBAAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQADCgcIBwAAAA==.Marley:BAAANQAECgYIDAAAAA==.Matua:BAAANQADCgYICwAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.',
Me='Meepz:BAAANQABCggIDAAAAA==.Megamacdin:BAAANQAECggIEgAAAA==.Mendietta:BAAANQAECgcIBwAAAA==.',
Mi='Miistral:BAAANQAECgUICAAAAA==.Mimie:BAAANQAECgUJDAAAAA==.Mistyeva:BAAANQAECgEJAQABNQAECgUICQAFAAAAAA==.Miyamoto:BAAANQADCgEIAQAAAA==.',
Mo='Moistooltip:BAABNQAECoEZAAIUAAkKXR6ABwAaAwAUAAkKXR6ABwAaAwAAAA==.Mokotrize:BAAANQAECgYICgAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAAANQAECgQJBQAAAA==.Mordred:BAAANQADCgYJGwAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Mu='Mud:BAAANQAECgQJBQAAAA==.Mudslinger:BAAANQADCgQIBAAAAA==.Munchies:BAAANQADCggJFAAAAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAFAAAAAA==.Myrrha:BAAANQADCggJEAAAAA==.',
['Mø']='Møønwuu:BAAANQADCgUJBAAAAA==.',
Na='Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUJDAAFAAAAAA==.',
Ne='Neckslice:BAACNQAFFIEKAAIIAAUKshZ6BAClAQAIAAUKshZ6BAClAQA1AAQKgRoAAggACQpSIM0TABADAAgACQpSIM0TABADAAAA.Nemophilist:BAAANQABCgIIAgAAAA==.Neuro:BAAANQAECgYJEQAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBAAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nirri:BAAANQADCggJGAAAAA==.Nitefall:BAAANQAECgMJBgAAAA==.',
No='Nocando:BAABNQAECoEcAAIMAAkKFRL1MQAsAgAMAAkKFRL1MQAsAgAAAA==.Notadk:BAAANQADCgUIBQAAAA==.Nott:BAAANQAECgEJAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgcIJAALAMATAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Ol='Oline:BAABNQAECoEVAAIVAAkKsyJjCQBFAwAVAAkKsyJjCQBFAwAAAA==.',
Oo='Oonaki:BAAANQAECgYIDgAAAA==.',
Or='Orchideva:BAAANQADCgcJBwABNQAECgUICQAFAAAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAAANQAECgUJBQAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAAANQAECgcJEwAAAA==.',
Ph='Phelefica:BAAANQAECgMIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAAANQAECgQJCwAAAA==.',
Pm='Pmac:BAAANQAECgMIAgABNQAECggIEgAFAAAAAA==.',
Po='Pointybrows:BAAANQAECgQIBAAAAA==.',
Pr='Pryona:BAAANQADCggICAAAAA==.',
Pu='Putrescence:BAAANQADCgkJEAAAAA==.',
Pw='Pwnhubb:BAAANQADCgQIBAAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quelestraza:BAAANQAECgQJBwAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Raewyck:BAAANQAECgcJCQAAAA==.Raginbull:BAAANQAECgYJDAAAAA==.Ragingmaze:BAABNQAECoEYAAMLAAgKNRGmNQDDAQALAAgKNRGmNQDDAQAHAAcK2wMkVAArAQAAAA==.Rainburrow:BAAANQADCggIEwAAAA==.Raptormortis:BAAANQADCgYICwABNQADCggICAAFAAAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Restingbface:BAAANQADCggICAAAAA==.Resurrection:BAAANQADCgYIDAAAAA==.Retana:BAABNQAECoEeAAICAAgKJxuvNQB+AgACAAgKJxuvNQB+AgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAAANQAECgIJBAAAAA==.',
Ri='Rickypeepee:BAAANQAECgcIDAAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQABCgYJBQAAAA==.',
Ro='Roastedz:BAAANQADCggJEwAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgEIAQAAAA==.Rorthu:BAAANQADCggJEAAAAA==.',
Ru='Rukélie:BAAANQADCggJEAAAAA==.',
Ry='Ry:BAAANQAECggIBgAAAA==.Ryanna:BAAANQAECgEIAQAAAA==.',
Sa='Saevio:BAAANQAECgQJBwAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAAANQAECgIIBQAAAA==.Sashimi:BAAANQAECgcICwAAAA==.Satharis:BAAANQADCgYIBgAAAA==.',
Sc='Scarlet:BAAANQAECgQJBAAAAA==.Scarllett:BAAANQAECgUJDAAAAA==.Scrytearia:BAAANQABCgIJAgAAAA==.',
Se='Selfward:BAAANQAECgEJAgAAAA==.Seran:BAAANQADCggJCAAAAA==.Serenade:BAAANQADCggJEAAAAA==.Seviana:BAAANQAECgcIDAABNQAFFAMICgAGAKwkAA==.Sevie:BAACNQAFFIEKAAIGAAMKrCQCBwBFAQAGAAMKrCQCBwBFAQA1AAQKgSkAAgYACQpqJQ8BALMDAAYACQpqJQ8BALMDAAAA.',
Sh='Shabbyy:BAAANQADCgUICwABNQAECgQIBwAFAAAAAA==.Shadowpump:BAAANQAECgQIDwAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAAANQAECgQJBAAAAA==.Shellack:BAAANQABCgIJAgAAAA==.Shinnz:BAAANQAECgcIEQAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQADCgcIBwABNQAECgkJGQAUAF0eAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQAECgQIBAABNQADCgcICQAFAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAAANQAECgcICQAAAA==.Simmara:BAAANQAECgMJBwAAAA==.Sip:BAAANQADCggICAAAAA==.',
Sk='Skipper:BAAANQABCgYIBgAAAA==.Skylinelol:BAAANQAECggIBwAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgAFAAAAAA==.',
Sm='Smallcurse:BAAANQADCgYIBgAAAA==.Smallighting:BAABNQAECoEYAAMWAAkKnRCvNQAdAgAWAAkKnRCvNQAdAgAIAAIKKRLXtACDAAAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAAANQAECgQIBQAAAA==.',
Sp='Spiritualone:BAAANQAECgUJCAAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAAANQAECgIJBAAAAA==.Stonystark:BAAANQADCgcIEwAAAA==.Straam:BAABNQAECoElAAMWAAkKORauIQCLAgAWAAkKORauIQCLAgAIAAMKcQuCqwCiAAAAAA==.Strizzle:BAEANQAECgYJEAAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgQJBAAAAA==.',
Su='Subatronic:BAACNQAFFIEMAAILAAUKjiNwAgACAgALAAUKjiNwAgACAgA1AAQKgSIAAgsACQrNJmgAAPcDAAsACQrNJmgAAPcDAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAUJDAALAI4jAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAAANQAECgQIBQAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAAANQAECgMIAwAAAA==.Takki:BAAANQAECgQJAwAAAA==.Talethia:BAAANQAECgEJAQAAAA==.Tamsîn:BAABNQAECoEcAAIXAAgKjhXnAwA9AgAXAAgKjhXnAwA9AgAAAA==.',
Te='Teinuya:BAAANQAECgcJEQAAAA==.Tenderfiddle:BAAANQADCgEJAQAAAA==.Tenochitilan:BAAANQAECgUJBwAAAA==.',
Th='Theocracy:BAAANQAECgMJBQAAAA==.Thoorz:BAAANQADCggIDQAAAA==.Thorimeir:BAAANQADCgIIAgAAAA==.Thorzy:BAAANQAECgIIAgABNQADCggIDQAFAAAAAA==.Thraxacious:BAABNQAECoEYAAIYAAgKzBetBgBlAgAYAAgKzBetBgBlAgAAAA==.Thulsadoomm:BAAANQAECgEJAQAAAA==.Thundermay:BAAANQAECgEJAQAAAA==.',
Ti='Tiduss:BAAANQADCgYIGAAAAA==.Tigó:BAAANQAECgUIBgAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAAANQAECgIJBAAAAA==.Tinkerbel:BAAANQAECgcICwAAAA==.Tinkerbella:BAAANQAECgMIBAAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAMIBQABAMoTAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgIJAwAAAA==.Torsin:BAAANQADCgIIAgAAAA==.',
Tr='Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQADCgQIBwAAAA==.Try:BAAANQAECgYIBAABNQAECggIBgAFAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAAANQAECgYICgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tyylerdurden:BAAANQABCgIJAgAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgQICQAFAAAAAA==.Uddertrouble:BAEANQAECgQICQAAAA==.',
Un='Unholytiran:BAAANQAECgQIBAAAAA==.',
Ur='Urmada:BAAANQAECgYICgAAAA==.Urmami:BAAANQAECgQJBQAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQADCgYIEgAAAA==.Vampire:BAAANQAECgYIDAAAAA==.Vampyre:BAAANQAECggIEwAAAA==.Vanadie:BAAANQADCgcIBwAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Vargmal:BAAANQADCgYIBQAAAA==.',
Vi='Virala:BAAANQADCgcICQAAAQ==.Visenya:BAAANQAECgMJAwAAAA==.Visquake:BAAANQAECgEJAQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECgUIBQAFAAAAAA==.Vitaminn:BAAANQAECgUIBQAAAA==.',
Vl='Vlaen:BAAANQADCggICAAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQADCgYICQAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQADCggJDQAAAA==.',
Wh='Whisa:BAAANQADCggICAAAAA==.White:BAAANQADCggICAABNQAFFAUJCgAIALIWAA==.',
Wi='Wildwolff:BAAANQADCgYJBQAAAA==.Wilhedin:BAABNQAECoEdAAIZAAgK8iNYFgAyAwAZAAgK8iNYFgAyAwAAAA==.',
Wo='Wolfblade:BAAANQADCgQJBQAAAA==.Worm:BAACNQAFFIEHAAIZAAUK9BkdBgC8AQAZAAUK9BkdBgC8AQA1AAQKgSIAAhkACQqOHtkfAPoCABkACQqOHtkfAPoCAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCAAAAA==.',
Wy='Wyon:BAAANQAECgQJBgAAAQ==.',
Ya='Yasnah:BAAANQADCggJEgAAAA==.',
Yu='Yunahpabo:BAABNQAECoEYAAIZAAgKxxj2PQBvAgAZAAgKxxj2PQBvAgAAAA==.Yurna:BAAANQADCgMJAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQADCgMIAwAAAA==.Zanikan:BAAANQAECggJCAAAAA==.Zathara:BAABNQAECoEdAAIYAAgKegtDCwDGAQAYAAgKegtDCwDGAQAAAA==.',
Zo='Zodiac:BAAANQAECgUICQAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQADCgMIAwAAAA==.Zuluk:BAAANQAECgYIDgAAAA==.',
['Zö']='Zörö:BAABNQAECoEUAAMHAAYKZw8MRgB1AQAHAAYKZw8MRgB1AQALAAUKkAUCbAC/AAAAAA==.',
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
