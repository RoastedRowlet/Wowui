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

local lookup = {'Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Devourer','Unknown-Unknown','Evoker-Devastation','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','Mage-Arcane','Priest-Holy','Monk-Mistweaver','Paladin-Retribution','DeathKnight-Blood','Druid-Guardian','Druid-Restoration','Druid-Balance','Priest-Shadow',}
local provider = {region='US',realm='Sentinels',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Absqwas:BAAANQADCgUICAAAAA==.',
Ac='Actaeon:BAAANQABCgEIAQAAAA==.',
Ad='Adaina:BAAANQAECgUJCQAAAA==.',
Ae='Aetherstrike:BAAANQADCgYIBwAAAA==.',
Ah='Aheeaheehahe:BAABNQAECoEXAAIBAAgK6Q7xRQAjAgABAAgK6Q7xRQAjAgAAAA==.',
Ai='Ailanissa:BAAANQAECgUJCAAAAA==.Ailasaa:BAABNQAECoEhAAMCAAkKqCPgAACJAwACAAgKPybgAACJAwADAAYKQRdOKwCMAQAAAA==.',
Al='Alynddra:BAAANQAECgQICAAAAA==.',
An='Anbraxas:BAAANQADCggJDwAAAA==.Antonson:BAAANQAECgYJBwAAAA==.',
Ao='Ao:BAAANQAECgQIBAABNQAECgYJCwAEAAAAAA==.',
As='Astovidatu:BAAANQAECgIIAgAAAA==.',
At='Atanukki:BAAANQAECgUICgABNQAECggIDAAEAAAAAA==.',
Au='Auroranova:BAAANQAECgUICgAAAA==.',
Ax='Axél:BAAANQADCgcIDwAAAA==.',
Ay='Ayblinkin:BAAANQADCgYJBgABNQAECgkJGgAFAKMSAA==.',
Ba='Balthazaar:BAAANQAECgEIAQAAAA==.',
Bl='Bluedreamm:BAAANQADCggIFwAAAA==.',
Br='Braei:BAAANQADCggJDwAAAA==.Brilleleante:BAAANQADCgQICQAAAA==.',
Ca='Canimai:BAAANQAECgEIAQAAAA==.',
Co='Cojul:BAAANQAECgUIBwAAAA==.',
Cr='Crazynaga:BAAANQADCggIDgAAAA==.Crisspy:BAABNQAECoEZAAMGAAgK8whZZQBlAQAGAAcKzAdZZQBlAQAHAAcK6wTubQA/AQAAAA==.',
Cu='Cubes:BAACNQAFFIEHAAIIAAYK2iAHAQBeAgAIAAYK2iAHAQBeAgA1AAQKgR4AAwgACQo9JmQDAIIDAAgACQo9JmQDAIIDAAkABgqkG+EMAL4BAAAA.',
De='Deadlylight:BAAANQAECgEIAQAAAA==.Deathcrocker:BAEANQAECgcICwABNQAFFAcIDgAKAHQiAA==.Denounce:BAABNQAECoEeAAILAAkKPyVFAQDPAwALAAkKPyVFAQDPAwAAAA==.',
Di='Diddlerprime:BAAANQADCgcIDQAAAA==.',
Do='Domar:BAAANQADCggIDwAAAA==.Doomslayer:BAABNQAECoEWAAIMAAcKThhpKgAVAgAMAAcKThhpKgAVAgAAAA==.Dothippo:BAAANQAECgUJCgAAAA==.',
Dr='Drachunter:BAAANQADCgMIAwAAAA==.',
Ea='Easy:BAAANQADCgYIBgABNQAECgcJDwAEAAAAAA==.',
Eh='Ehrathorn:BAAANQADCgYIBgAAAA==.',
El='Elennoxx:BAAANQADCggJCAAAAA==.',
Et='Etta:BAAANQADCgMJAwAAAA==.',
Ex='Exarchstrike:BAAANQADCgYJCQAAAA==.',
Fa='Fayce:BAAANQABCgYICgAAAA==.',
Fe='Feledara:BAAANQAECgEJAQAAAA==.Feylen:BAAANQAECgEJAQAAAA==.',
Fl='Floof:BAAANQADCgMIAwAAAA==.',
Fr='Frieren:BAACNQAFFIELAAINAAUK5RtoCADPAQANAAUK5RtoCADPAQA1AAQKgSQAAg0ACQqUJG0HALEDAA0ACQqUJG0HALEDAAAA.',
Ge='Gencrocker:BAEBNQAFFIEOAAIKAAcKdCIhAADSAgAKAAcKdCIhAADSAgAAAA==.Getoffenris:BAAANQADCggJDwAAAA==.',
Gl='Gloryhammer:BAAANQADCgIIAgAAAA==.',
Go='Gobbs:BAAANQAECgYJDAAAAA==.',
Gr='Gratagnan:BAAANQABCgEJAQAAAA==.Grimmi:BAAANQADCgEIAQAAAA==.Grosh:BAAANQADCgYJBgAAAA==.',
Ha='Haldrian:BAAANQADCggJEAAAAA==.',
Ho='Hollydaye:BAAANQADCggIHAAAAA==.Holyhota:BAABNQAECoEXAAIOAAkKeBztEQDwAgAOAAkKeBztEQDwAgAAAA==.Holymolly:BAAANQADCgYIBgAAAA==.Holystrike:BAAANQADCgUIEAAAAA==.Hop:BAAANQAECgYJDwAAAA==.',
Ir='Iraedies:BAAANQABCgIIAgAAAA==.',
Iv='Ivakor:BAAANQAECgEIAgAAAA==.',
Ja='Jaes:BAAANQADCgEJAQAAAA==.Jaszuny:BAAANQAECgUJDQAAAA==.',
Je='Jeeyell:BAAANQAECgcIEwAAAA==.Jezlyn:BAAANQADCgMIAwAAAA==.',
Jo='Johnnyblaze:BAAANQADCgEIAQAAAA==.Johyah:BAACNQAFFIEKAAIPAAYKsRD2AADzAQAPAAYKsRD2AADzAQA1AAQKgSIAAg8ACQpDHbIGAOQCAA8ACQpDHbIGAOQCAAAA.',
Ka='Katsumotosan:BAAANQADCgQIBAAAAA==.',
Ke='Kemstrio:BAAANQAECgUICQABNQAECgkJGgACAAciAA==.Kev:BAAANQAECgUJCgAAAA==.',
Ko='Kombatgodess:BAAANQADCgYICQAAAA==.Kordraan:BAAANQADCgQIBAAAAA==.',
Kr='Krael:BAAANQAECggIBgAAAA==.',
Ks='Kspboop:BAEANQAECgcIBAAAAA==.',
Ku='Kurag:BAAANQADCggIFgAAAA==.Kurvios:BAAANQAECgMIBgABNQAECgYIEQAEAAAAAA==.Kuurgan:BAAANQADCggJCAAAAA==.',
Kv='Kvasir:BAAANQAECgIJAwABNQAECgUIBwAEAAAAAA==.',
Li='Lichkingstoy:BAABNQAECoEmAAIQAAkKMx6hHgDzAgAQAAkKMx6hHgDzAgAAAA==.Light:BAAANQAECgMIAwABNQAECgcJDwAEAAAAAA==.Lizardboi:BAAANQAECgUICQAAAA==.',
Ma='Magicstrike:BAAANQADCgYJCwAAAA==.Manta:BAAANQAECgQIBAAAAA==.',
Mi='Miracle:BAAANQADCggJDwAAAA==.',
Mo='Morelinne:BAAANQADCgUICAAAAA==.',
My='Mykehoochie:BAAANQADCgQIAwAAAA==.',
Na='Nabarke:BAAANQADCgcIBwAAAA==.Nathanos:BAAANQAECgEIAQABNQAECgYIEQAEAAAAAA==.Naturestrike:BAAANQADCgYJEgAAAA==.',
Ni='Nier:BAAANQAECgEJAQAAAA==.',
No='Noisemarine:BAAANQAECgcIEQAAAA==.Nooxi:BAAANQADCgUIBQABNQADCgUICAAEAAAAAA==.Nospheratus:BAAANQAECgUICQABNQAECgkJJwARAIMZAA==.Noub:BAAANQADCgYJBgAAAA==.',
Ny='Nylianna:BAABNQAECoEZAAIQAAkKTyJTGAAaAwAQAAkKTyJTGAAaAwAAAA==.',
Ob='Obilesk:BAAANQADCgYIBgAAAA==.',
Og='Ogganborn:BAAANQADCggICAAAAA==.',
Ph='Phoenïx:BAAANQABCgMIAwAAAA==.',
Pi='Pikal:BAAANQAECgUJBwAAAA==.',
Pr='Priestaline:BAAANQAECgcJDQAAAA==.Priestigory:BAAANQAECgUJCgAAAA==.Prosper:BAAANQAECgEIAQAAAA==.',
Pv='Pvtcrocker:BAEBNQAFFIEIAAISAAUKExWtAACVAQASAAUKExWtAACVAQABNQAFFAcIDgAKAHQiAA==.',
Qu='Quintus:BAAANQAECggICgAAAA==.',
Ra='Railiana:BAAANQADCgQIBAAAAA==.Ravelin:BAAANQADCgYIDAAAAA==.',
Re='Regrowth:BAAANQADCggIEwAAAA==.Remaxed:BAAANQAECgIIAgAAAA==.',
Ri='Riqis:BAAANQABCgIIAgAAAA==.',
Ru='Rummornia:BAAANQAECgUIBQAAAA==.',
Se='Sephiran:BAAANQAECgYIEQAAAA==.Seppuku:BAAANQAECgYICwAAAA==.',
Sh='Shaami:BAACNQAFFIEIAAITAAUK2BCwAgCMAQATAAUK2BCwAgCMAQA1AAQKgSMAAxMACQr9GvYPAGoCABMACQr9GvYPAGoCABQABgr3Hg4tAP4BAAAA.Shaomei:BAAANQAECgcIDwAAAA==.',
Sk='Skye:BAAANQAECgIIAgABNQAFFAcJGwAVAEshAA==.',
Sp='Splittheg:BAAANQAECggIBQAAAA==.',
St='Stdot:BAAANQAECgMIBAAAAA==.Stephirollsa:BAAANQADCgYICQAAAA==.Stormstrike:BAAANQADCgYIGwAAAA==.Stothyr:BAAANQAECgEJAgABNQAECgkJIQACAKgjAA==.',
Sw='Sway:BAAANQAECgEIAQABNQAECgcJDwAEAAAAAA==.',
Sy='Symwarrior:BAAANQADCgQIBAAAAA==.',
Ta='Taluria:BAAANQADCggJDwAAAA==.',
Ti='Tikimon:BAAANQADCgUIDgAAAA==.Tinkernine:BAAANQAECgUICQAAAA==.',
To='Tobofrog:BAAANQAECggIBgAAAA==.',
Tu='Turaht:BAAANQAECgYJDgAAAA==.',
Ty='Tyrgrim:BAAANQADCggJDwAAAA==.Tyronius:BAAANQADCgUIBQAAAA==.',
Uk='Ukio:BAAANQAECgUJCwAAAA==.',
Ul='Uldyssian:BAAANQAECgYJEQABNQAECgkJGQAQAE8iAA==.',
Uw='Uwuforyou:BAAANQADCggIDAAAAA==.',
Uz='Uzumaki:BAAANQADCgQIBAAAAA==.',
Ve='Velawynn:BAACNQAFFIEJAAIOAAYKnA59AwD/AQAOAAYKnA59AwD/AQA1AAQKgSEAAg4ACQq2HCkPAAUDAA4ACQq2HCkPAAUDAAAA.',
Vo='Voidâge:BAABNQAECoEYAAINAAkKIx1zPgDQAgANAAkKIx1zPgDQAgAAAA==.',
Xe='Xenu:BAAANQAECgYIDQAAAA==.',
Zu='Zubang:BAAANQAECggIBQAAAA==.',
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
