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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Unknown-Unknown','Evoker-Preservation','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Affliction','Shaman-Elemental','Mage-Arcane','Hunter-Survival','DeathKnight-Blood','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','Monk-Brewmaster','DemonHunter-Havoc','Druid-Balance','DemonHunter-Devourer','Paladin-Protection','Paladin-Holy','Monk-Windwalker','Mage-Frost','Warlock-Demonology','Priest-Discipline','Shaman-Restoration','Warlock-Destruction','Druid-Feral','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aamodar:BAAANQAECgMIBwAAAA==.',
Ab='Abadon:BAAANQAECgYIBwAAAA==.',
Ad='Adino:BAAANQAECgcIEAAAAA==.Adorabell:BAAANQADCggIDwABNQAFFAUICgABAOQNAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAAANQAECgcIEAAAAA==.Aeryn:BAABNQAECoEpAAICAAkKJSNLDQB/AwACAAkKJSNLDQB/AwAAAA==.Aerís:BAAANQAECgQIBQAAAA==.',
Ag='Agrolazor:BAABNQAECoEdAAIDAAgKQRayGQA4AgADAAgKQRayGQA4AgAAAA==.',
Ah='Ahote:BAAANQAECggIAgAAAA==.Ahtee:BAAANQAECgYIDwAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Albarino:BAAANQADCgYJBgAAAA==.Algodon:BAAANQAECgYIBgABNQAECgkJJgABACQiAA==.Alseena:BAAANQAECgMIBQAAAA==.',
Am='Amun:BAAANQADCgIJAgAAAA==.',
An='Anvar:BAABNQAECoEiAAMBAAgKxh7HKQC1AgABAAgKxh7HKQC1AgAEAAYKLQrmOAAkAQAAAA==.',
Ar='Arathion:BAAANQAECgcIEQAAAA==.Arcanemommy:BAAANQAECggIAgAAAA==.Arianrhod:BAAANQAECgcIEAAAAA==.Arx:BAAANQAECgcIEwAAAA==.',
As='Ashaldrin:BAAANQAECgEIAgAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgEIAQAAAA==.',
At='Atrumdeus:BAABNQAECoEoAAICAAkK4xccQwCBAgACAAkK4xccQwCBAgAAAA==.',
Au='Audiamer:BAAANQAECgYIDQAAAA==.Aufsela:BAAANQAECgEIAQABNQAECgIIAgAFAAAAAA==.',
Ba='Babydragon:BAABNQAECoEfAAIGAAgKdRRJFwANAgAGAAgKdRRJFwANAgAAAA==.Babysaja:BAAANQAECgIIAwAAAA==.Bangerz:BAAANQAECgUJBQAAAA==.Bannann:BAAANQAECgYIEgAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECoEfAAMHAAkKviEtEAAHAwAHAAkKnyAtEAAHAwAIAAQKgyQTMgCuAQAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgUJCQAAAA==.Belldia:BAACNQAFFIEKAAIBAAUK5A2vBgCEAQABAAUK5A2vBgCEAQA1AAQKgSMAAgEACQorGykiANYCAAEACQorGykiANYCAAAA.Belphaegor:BAAANQAECgUIDAAAAA==.Beni:BAAANQAECgcICAAAAA==.Beniaru:BAAANQAECgYIEAAAAA==.Bennyflipz:BAAANQAECgEIAQAAAA==.',
Bi='Bigmuzz:BAAANQADCgYICAAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAAANQAECgIIAgABNQAECggIHQAJALseAA==.Bloopmasta:BAAANQADCggIDwAAAA==.Blufox:BAAANQAECggIEQAAAA==.',
Bo='Bobfresh:BAABNQAECoEmAAIKAAkKGyNpCQCJAwAKAAkKGyNpCQCJAwAAAA==.Bootwitdafur:BAAANQADCggIDwAAAA==.',
Br='Broherum:BAAANQADCgQJBAAAAA==.Bronzetusk:BAAANQABCgIIAgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYJCwAAAA==.Buckbeak:BAAANQADCggICAABNQAECgkJHwAHAL4hAA==.Busting:BAABNQAECoEVAAILAAkKsRnLQwDbAgALAAkKsRnLQwDbAgAAAA==.',
['Bà']='Bàhamut:BAAANQAECgQIBAAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQADCgYJBgABNQAECgcIEAAFAAAAAA==.Captchaos:BAAANQADCgYIBQAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMIBwAFAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAAANQAECgYIEwAAAA==.',
Ch='Chimneybones:BAAANQAECgYIDAAAAA==.Chizz:BAABNQAECoEfAAILAAkKHQxAoQD3AQALAAkKHQxAoQD3AQAAAA==.Chriswong:BAAANQAECgEIAQAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chá:BAAANQADCggIEAABNQAECgkJHwAHAA4iAA==.',
Cl='Clairebenet:BAABNQAECoEhAAMBAAgKsx2xLwCdAgABAAgKyByxLwCdAgAMAAQKZhcgCQBDAQAAAA==.Cleph:BAAANQAECgIIAgAAAA==.Clumzylock:BAAANQAECgUIBwABNQAECggIMwANAIIYAA==.Clumzyninja:BAABNQAECoEzAAINAAgKghhxJQBYAgANAAgKghhxJQBYAgAAAA==.',
Co='Code:BAAANQADCggICAABNQAFFAUJCgAKALIWAA==.Coolbreez:BAAANQADCgYICQAAAA==.Coolynn:BAAANQAECgMJBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Crew:BAAANQADCggICgAAAA==.',
Cu='Cumb:BAAANQADCggICgABNQAECgkJJgAKABsjAA==.',
['Cä']='Cäldius:BAAANQADCgMIAwAAAA==.',
Da='Daioh:BAAANQAECgEIAQAAAA==.Damacraze:BAAANQAECgUIEAAAAA==.Danielwu:BAAANQAECgcIDAAAAA==.Dawigrund:BAAANQAECgUIDAAAAA==.',
De='Deadroar:BAABNQAECoEXAAINAAgKcRa2OwDTAQANAAgKcRa2OwDTAQABNQAFFAEIAQAFAAAAAA==.Deadtomato:BAAANQAECgUICAAAAA==.Deadwill:BAAANQAECgQIDAAAAA==.Deadzug:BAAANQAECgUIBQABNQAECggIIgABAMYeAA==.Deaminase:BAAANQAECgYICwAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECoEdAAIOAAkKvxc2LQB0AgAOAAkKvxc2LQB0AgAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAAANQAECgMIBQAAAA==.Demidru:BAAANQAECgMIBgAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMJBgAFAAAAAA==.Deshojo:BAAANQAECgUICQAAAA==.Desrook:BAAANQAECgQIBAAAAA==.',
Dh='Dhqt:BAAANQAECgEIAQABNQAECgIIAgAFAAAAAA==.',
Di='Divinèhero:BAAANQAECgEIAQAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgIIAgAAAA==.Doublelift:BAABNQAECoEjAAMDAAkK2SAnDQDrAgADAAgKqiAnDQDrAgAOAAQKyxbIgQAhAQAAAA==.',
Dr='Dragondeznut:BAAANQADCggJDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgEIAQAFAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAAANQAECgQICwAAAA==.Drpumper:BAAANQAECgIIAgAAAA==.Dröbi:BAACNQAFFIEKAAMPAAUK2BKPBABHAQAPAAQKVxWPBABHAQAQAAEK2wgDCABMAAA1AAQKgSIAAw8ACQqrIT4FAB8DAA8ACQrjID4FAB8DABAAAQqVI2QXAGoAAAAA.',
Du='Dundundun:BAAANQAECgYICwAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
Eg='Eggdrop:BAAANQAECgUIBAAAAA==.Egufro:BAAANQAECgYIBwABNQAECgkJKQARAGYUAA==.',
Eh='Ehgu:BAABNQAECoEpAAIRAAkKZhReDQBYAgARAAkKZhReDQBYAgAAAA==.',
El='Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAAANQAECgUICAAAAA==.Elynnah:BAAANQAECgEIAQAAAA==.',
Em='Emidget:BAAANQAECgEIAQAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIBwAFAAAAAA==.',
Er='Erhmer:BAAANQAECggIBAAAAA==.',
Et='Etom:BAAANQAECggIBAAAAA==.',
Ev='Eviae:BAAANQADCgQIBAAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQADCggIDQABNQAECgIIAgAFAAAAAA==.Fatfatfat:BAAANQAECgEIAQABNQAFFAEIAQAFAAAAAA==.Fañgrat:BAAANQAECgYIDAABNQAECgIIAgAFAAAAAA==.',
Fe='Femboyluvr:BAAANQAECgEIAgAAAA==.',
Fi='Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flandia:BAAANQAECgcIEQAAAA==.Floppiterry:BAAANQAECgUIDgAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQADCgUIBQAAAA==.Flow:BAABNQAECoEaAAISAAgKyhjoCQA9AgASAAgKyhjoCQA9AgAAAA==.',
Fo='Fowl:BAAANQAECgcIEwAAAA==.',
Fr='Fricher:BAAANQAECgcIEAAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQABCgYIBgAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgEIAQABNQAECgkJHwAHAL4hAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghettomike:BAAANQADCgQJBAAAAA==.',
Gi='Giny:BAAANQAECgcIEQAAAA==.',
Gl='Glowfungus:BAAANQABCgIIAgAAAA==.',
Go='Gobbledeez:BAAANQAECgYIDAAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Govinniuur:BAAANQAECgIJAgAAAA==.',
Gr='Grasfedjones:BAAANQAECgIJAgAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECoEXAAITAAkKvhu5EADlAgATAAkKvhu5EADlAgAAAA==.Grue:BAAANQADCggIEAAAAA==.',
Gw='Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIBgAAAA==.',
Ha='Hafadude:BAAANQADCggIBQAAAA==.Hahgottum:BAAANQAECgQIAgAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAAANQAECgQICgAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Ho='Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgIIBAAAAA==.Holyyshift:BAAANQAECgEJAQABNQAECgIIBAAFAAAAAA==.Horhel:BAAANQAECgEIAQAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.',
Hy='Hyperiann:BAAANQADCgQIBAAAAA==.',
Ia='Iamfried:BAABNQAECoEfAAIUAAgKhhuoIgCCAgAUAAgKhhuoIgCCAgAAAA==.',
Ic='Iceyrot:BAAANQADCgcIBwAAAA==.',
Ig='Igran:BAAANQAECgIIAgAAAA==.',
Il='Illidigle:BAAANQADCggIDAABNQAECgkJHwAOAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECoEcAAMVAAgKpRv/GQBUAgAVAAgKbRn/GQBUAgATAAMKaRwRTQDxAAAAAA==.Innarius:BAAANQADCgMIAwAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECgUICAAAAA==.',
Ir='Ironheãrt:BAABNQAECoEhAAIWAAgKlx48CwCmAgAWAAgKlx48CwCmAgAAAA==.Ironjaws:BAAANQAECgUIBQAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAAANQAECggICwAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAgAAAA==.',
It='Itai:BAABNQAECoEfAAIHAAkKDiJfDwAQAwAHAAkKDiJfDwAQAwAAAA==.',
Iv='Iverson:BAAANQABCgYICgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECggIGgALABAgAA==.',
Ja='Jackk:BAACNQAFFIERAAIXAAYKaRk7AwAQAgAXAAYKaRk7AwAQAgA1AAQKgSIAAxcACQoUJDkGAIQDABcACQoUJDkGAIQDAAIAAgplCUsvAVQAAAAA.Jackks:BAAANQAECgYICgABNQAFFAYIEQAXAGkZAA==.Jaddix:BAAANQADCgYICwAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAAANQAECgYIEAAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAAANQAECgEIAQAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgIIAgABNQAECggIBAAFAAAAAA==.Jinkz:BAAANQAECgMIAwAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggJDgAAAA==.',
Ju='Judgevis:BAAANQAECgYJDAAAAA==.Jumbles:BAAANQAECgIIAgAAAA==.',
Jy='Jynxy:BAAANQADCggIEQAAAA==.',
['Jø']='Jøshu:BAAANQADCgYJBgABNQAECgIIAgAFAAAAAA==.',
Ka='Kaeliis:BAAANQAECgMIBgAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAAANQAECgEIAgAAAA==.',
Kb='Kbeckinsale:BAAANQAECggIEQAAAA==.',
Ke='Keladun:BAAANQADCgUJDwAAAA==.',
Kh='Khallessi:BAAANQADCgUIBQAAAA==.Kharga:BAAANQAECgQICgAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAYICgALAJ4aAA==.',
Ki='Kidgroove:BAAANQADCgEIAQAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Ko='Konamy:BAAANQAECgUICwAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAAANQAECgcIEQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kriss:BAAANQADCggJCQAAAA==.Kristeena:BAAANQADCggIFQAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAAANQAECgUIBwAAAA==.Kröw:BAABNQAECoEXAAIRAAgKyAlHEgDzAQARAAgKyAlHEgDzAQAAAA==.',
Ku='Kudrix:BAAANQAECgUIDAAAAA==.Kurø:BAAANQAECgIIAgAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgIIAgAAAA==.Laurijaydn:BAAANQAECgcIDQAAAA==.Laurynn:BAAANQADCggJDQAAAA==.',
Le='Legionremix:BAAANQADCggJCQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQADCgMIAwAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAOAKgUAA==.Littlestarz:BAAANQAECgcIDgAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgcIHAABACcVAA==.',
Ll='Llazz:BAAANQAFFAIIAgAAAA==.Llemons:BAAANQAECggIBwABNQAECggIEAAFAAAAAA==.',
Lo='Locknlizzie:BAEBNQAECoEcAAIBAAcKJxXoYwD3AQABAAcKJxXoYwD3AQAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQABCgMIAwAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggJEQAAAA==.',
Lu='Luke:BAAANQAECggICgAAAA==.Luminali:BAAANQAECgUICQABNQAECggIBwAFAAAAAA==.Luminari:BAAANQAECggIBwAAAA==.Lunadari:BAAANQAECgIJAwAAAA==.Lunareva:BAAANQAECgcIEAAAAA==.',
Ly='Lyxon:BAAANQAECgUIBwAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lí']='Lílîth:BAAANQAECgEIAQAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgQIBwABNQADCggICAAFAAAAAA==.Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAAANQAFFAEIAgAAAA==.Magicalama:BAABNQAECoEkAAILAAkK+RcOWwCeAgALAAkK+RcOWwCeAgAAAA==.Magiplex:BAAANQADCggIDgAAAA==.Magnanimity:BAEANQAECgEIAQABNQAECgUIDgAFAAAAAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAAANQAECggIEAAAAA==.Makto:BAAANQADCgYICAAAAA==.Malia:BAAANQADCggIGgAAAA==.Maliciouso:BAAANQAECgcIDwAAAA==.Malédiction:BAAANQAECgQIBAAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQADCgcIBwAAAA==.Marley:BAAANQAECgYIEQAAAA==.Matua:BAAANQAECgIIAgAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.',
Me='Meepz:BAAANQABCggIDAAAAA==.Megamacdin:BAAANQAECggIDAAAAA==.Mendietta:BAAANQAECgcIDgAAAA==.Meridian:BAAANQADCgcIBwAAAA==.',
Mi='Miistral:BAAANQAECgYIDgAAAA==.Mimie:BAAANQAECgUJDAAAAA==.Mistyeva:BAAANQAECgEJAQABNQAECgcIEAAFAAAAAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQADCgQIBAAAAA==.',
Mo='Moistooltip:BAABNQAECoEdAAIYAAkKDiByBwA1AwAYAAkKDiByBwA1AwAAAA==.Mokotrize:BAAANQAECgcIEQAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAAANQAECgUIDgAAAA==.Mordred:BAAANQAECgUIBQAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Mu='Mud:BAAANQAECggIDAAAAA==.Mudslinger:BAAANQAECgYIBgAAAA==.Munchies:BAAANQAECgIIAgAAAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAFAAAAAA==.Myrrha:BAAANQAECgEIAQAAAA==.',
['Mø']='Møønwuu:BAAANQAECgEIAQAAAA==.',
Na='Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUJDAAFAAAAAA==.',
Ne='Neckslice:BAACNQAFFIEKAAIKAAUKshZLBwCgAQAKAAUKshZLBwCgAQA1AAQKgRoAAgoACQpSIMEbAPUCAAoACQpSIMEbAPUCAAAA.Nemophilist:BAAANQABCgIIAgAAAA==.Neuro:BAABNQAECoEaAAMLAAgKECCCSwDFAgALAAgKECCCSwDFAgAZAAEKFhhfMQBIAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBAAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nirri:BAAANQAECgIIAgAAAA==.Nitefall:BAAANQAECgQICQAAAA==.',
No='Nocando:BAABNQAECoEfAAIOAAkKqBT/MQBdAgAOAAkKqBT/MQBdAgAAAA==.Notadk:BAAANQAECgEIAQAAAA==.Nott:BAAANQAECgEJAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECggIMwANAIIYAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgMIAwABNQAECggIHQAJALseAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Ol='Oline:BAABNQAECoEVAAIaAAkKsyJOEAAoAwAaAAkKsyJOEAAoAwAAAA==.',
Oo='Oonaki:BAAANQAECgYIDgAAAA==.',
Or='Orchideva:BAAANQADCgcJBwABNQAECgcIEAAFAAAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAAANQAECgUIBwAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAAANQAECgcJEwAAAA==.',
Ph='Phelefica:BAAANQAECgMIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAAANQAECgYIEQAAAA==.',
Pm='Pmac:BAAANQAECgUIBgABNQAECggIDAAFAAAAAA==.',
Po='Pogrin:BAAANQADCgUIBQAAAA==.Pointybrows:BAAANQAECgQIBAAAAA==.',
Pr='Pryona:BAAANQADCggICAABNQAECgEIAQAFAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgQIBAAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quelestraza:BAAANQAECgUIDAAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAAANQAECgcIDwAAAA==.Raginbull:BAAANQAECgYIEQAAAA==.Ragingmaze:BAABNQAECoEgAAQNAAgKNRHaQQCyAQANAAgKNRHaQQCyAQAHAAgKdASkYAAmAQAIAAIKQAXmdABbAAAAAA==.Rainburrow:BAAANQAECgMIAwAAAA==.Raptormortis:BAAANQAECgEIAQAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Restingbface:BAEANQADCggICAAAAA==.Resurrection:BAAANQADCgYIDAAAAA==.Retana:BAABNQAECoEgAAICAAgKbxucRgB1AgACAAgKbxucRgB1AgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAAANQAECgMIBwAAAA==.',
Ri='Rickypeepee:BAAANQAECgcIDAAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQAECgIIAgAAAA==.',
Ro='Roastedz:BAAANQAECgIIAgAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgQIBQAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggICAAAAA==.Ryanna:BAAANQAECgMIBAAAAA==.',
Sa='Saevio:BAAANQAECgQICwAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAAANQAECgUICgAAAA==.Sashimi:BAABNQAECoEaAAMIAAgKyBkRHQBWAgAIAAgKyBkRHQBWAgAHAAIKjRCUlgBpAAAAAA==.Satharis:BAAANQADCgYIBgAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgAAAA==.Scarllett:BAAANQAECgUIEAAAAA==.Scrytearia:BAAANQABCgIJAgAAAA==.',
Se='Selfward:BAAANQAECgQIBgAAAA==.Seran:BAAANQADCggJCAAAAA==.Serenade:BAAANQAECgIIAgAAAA==.Seviana:BAAANQAECgcIEAABNQAFFAUIDgAGAOAlAA==.Sevie:BAACNQAFFIEOAAIGAAUK4CXQAgAzAgAGAAUK4CXQAgAzAgA1AAQKgSwAAgYACQpxJUoBALMDAAYACQpxJUoBALMDAAAA.',
Sh='Shabbyy:BAAANQADCgUICwABNQAECgQIBwAFAAAAAA==.Shadowpump:BAABNQAECoEYAAQOAAYK8heScgBWAQAOAAUKvhaScgBWAQADAAQKIBJgOgD/AAAbAAEKzQtnIgAzAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAAANQAECgUICQAAAA==.Shellack:BAAANQABCgIJAgAAAA==.Shinnz:BAABNQAECoEWAAMCAAgKSxABlwCIAQACAAgKSxABlwCIAQAXAAMK8QAE6gA8AAAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQAECgMIAwABNQAECgkJHQAYAA4gAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQAECgQICAABNQAECgIIAgAFAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAAANQAECggIEAAAAA==.Simmara:BAAANQAECgMIBwAAAA==.Sip:BAAANQADCggICAAAAA==.',
Sk='Skapelijones:BAAANQADCgIIAgAAAA==.Skipper:BAAANQABCgYIBgAAAA==.Skylinelol:BAAANQAECggIBwAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgAFAAAAAA==.',
Sm='Smallcurse:BAAANQADCgYIBgAAAA==.Smallighting:BAABNQAECoEcAAMcAAkKOBEFRQAAAgAcAAkKOBEFRQAAAgAKAAIKKRJr0gB/AAAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAAANQAECgQIBwAAAA==.',
Sp='Spiritualone:BAAANQAECgUIDQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAAANQAECgMIBwAAAA==.Stonystark:BAAANQADCgcIEwAAAA==.Straam:BAABNQAECoEuAAMcAAkKTBYaLQBtAgAcAAkKTBYaLQBtAgAKAAYK3gurggBGAQAAAA==.Strizzle:BAEBNQAECoEZAAIKAAcKwgaLfQBUAQAKAAcKwgaLfQBUAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgQJBAAAAA==.',
Su='Subatronic:BAACNQAFFIERAAINAAUKjiMOBAD7AQANAAUKjiMOBAD7AQA1AAQKgSQAAg0ACQrNJrEAAO0DAA0ACQrNJrEAAO0DAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAUIEQANAI4jAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAAANQAECggICAAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAAANQAECgcICgAAAA==.Takki:BAAANQAECgcICAAAAA==.Talethia:BAAANQAECgEIAQAAAA==.Tamsîn:BAABNQAECoEeAAIJAAgKLBbfBABAAgAJAAgKLBbfBABAAgAAAA==.',
Te='Teech:BAAANQADCggICAAAAA==.Teinuya:BAABNQAECoEdAAMJAAgKux4nBwDmAQAJAAYKIRonBwDmAQAdAAQKmR+wHAB5AQAAAA==.Tenderfiddle:BAAANQADCgEJAQAAAA==.Tenochitilan:BAAANQAECgYIDQAAAA==.',
Th='Theocracy:BAAANQAECgQICQAAAA==.Thoorz:BAAANQAECgEIAQAAAA==.Thorimeir:BAAANQADCgIIAgAAAA==.Thorzy:BAAANQAECgQIBAABNQAECgEIAQAFAAAAAA==.Thraxacious:BAABNQAECoEhAAIeAAkKfhr/BADlAgAeAAkKfhr/BADlAgAAAA==.Thulsadoomm:BAAANQAECgEIAQAAAA==.Thundermay:BAAANQAECgEIAQAAAA==.',
Ti='Tiduss:BAAANQAECgQIBQAAAA==.Tigó:BAAANQAECgYIBgAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAAANQAECgMIBwAAAA==.Timorrow:BAAANQADCgEIAQAAAA==.Tinkerbel:BAAANQAECgcIEwAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAUICgABAOQNAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.',
Tr='Trafalgor:BAAANQAECgQIBAAAAA==.Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQADCgQIBwAAAA==.Try:BAAANQAECggIBAABNQAECggICAAFAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAAANQAECgcIEQAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIAQAAAA==.Tyylerdurden:BAAANQABCgIIAgAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgUIDgAFAAAAAA==.Uddertrouble:BAEANQAECgUIDgAAAA==.',
Un='Unholytiran:BAAANQAECgQIBAAAAA==.',
Ur='Urmada:BAAANQAECgYIDwAAAA==.Urmami:BAAANQAECgUICgAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQADCgYIEgAAAA==.Vampire:BAAANQAECgcIEwAAAA==.Vampyre:BAAANQAECggIEwAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Vargmal:BAAANQADCgYIBQAAAA==.',
Vi='Virala:BAAANQAECgIIAgAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgEJAQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECgcIDAAFAAAAAA==.Vitaminn:BAAANQAECgcIDAAAAA==.',
Vl='Vlaen:BAAANQADCggICAAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAQAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQADCggJDQAAAA==.',
Wh='Whisa:BAAANQAECgQIBAAAAA==.White:BAAANQADCggICAABNQAFFAUJCgAKALIWAA==.',
Wi='Wildwolff:BAAANQADCgUIBQAAAA==.Wilhedin:BAABNQAECoEjAAIfAAgK8iPdHwAVAwAfAAgK8iPdHwAVAwAAAA==.Wing:BAEANQAECggIBwAAAA==.',
Wo='Wolfblade:BAAANQADCgQJBQAAAA==.Worm:BAACNQAFFIEMAAIfAAYKaBfGBQAMAgAfAAYKaBfGBQAMAgA1AAQKgSUAAh8ACQp4ID0mAPkCAB8ACQp4ID0mAPkCAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCAAAAA==.',
Ww='Wwoman:BAAANQADCggICAAAAA==.',
Wy='Wyon:BAAANQAECgQICgAAAQ==.',
Ya='Yasnah:BAAANQADCggJEgAAAA==.',
Yu='Yunahpabo:BAABNQAECoEeAAIfAAgKtxlTSgBtAgAfAAgKtxlTSgBtAgAAAA==.Yurna:BAAANQADCgMJAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQADCgMIAwAAAA==.Zanikan:BAAANQAECggICAAAAA==.Zankuza:BAAANQAECggIAQAAAA==.Zathara:BAABNQAECoElAAIeAAkKtQ+OCgAiAgAeAAkKtQ+OCgAiAgAAAA==.',
Zo='Zodiac:BAAANQAECgcIEAAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgIIAgAAAA==.Zuluk:BAAANQAECgcIDwAAAA==.',
['Zö']='Zörö:BAABNQAECoEfAAMHAAcKLxX3RQCbAQAHAAYKhBf3RQCbAQANAAcK1QZAYwAbAQAAAA==.',
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
