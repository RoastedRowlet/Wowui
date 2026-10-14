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

local lookup = {'Hunter-BeastMastery','Monk-Brewmaster','DeathKnight-Blood','Paladin-Holy','Warlock-Demonology','Priest-Holy','Priest-Shadow','Unknown-Unknown','DeathKnight-Unholy','Warlock-Destruction','Mage-Arcane','Mage-Fire','Warrior-Protection','Monk-Mistweaver','Hunter-Survival','Shaman-Restoration','Warrior-Arms','Priest-Discipline','Shaman-Elemental','Shaman-Enhancement','Paladin-Retribution','Warrior-Fury','Mage-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=53,date='2026-10-13',data={Al='Althenara:BAAANQAECgUICgAAAA==.Alysard:BAAANQAECggIEQAAAA==.',
Am='Amaurine:BAAANQAECgIIBAAAAA==.',
An='Anoras:BAAANQADCgcIEAAAAA==.',
Ar='Aratfu:BAAANQAECgUIDAABNQAECggIIAABAN4VAA==.Araycadia:BAAANQAECggICAAAAA==.Archivus:BAAANQADCgYIBgAAAA==.Arteymis:BAAANQAECgEIAQABNQAECggIIgACAIghAA==.Arui:BAAANQAECgUIEgAAAA==.',
At='Athania:BAAANQAECgYICwABNQAECggIFAADALANAA==.Athornia:BAAANQADCgUIBQAAAA==.',
Au='Aumery:BAABNQAECn8mAAIDAAcKShQ/VACgAQADAAcKShQ/VACgAQAAAA==.Autoflick:BAAANQADCgYJBgAAAA==.',
Aw='Awwee:BAAANQAECgEIAQAAAA==.',
Az='Azinozl:BAAANQAECgYIBQABNQAECgkJFwAEAMAZAA==.Azipaly:BAABNQAECn8XAAIEAAkKwBmVJADXAgAEAAkKwBmVJADXAgAAAA==.Azurite:BAABNQAECn8WAAIFAAgKlAp3mgCfAQAFAAgKlAp3mgCfAQAAAA==.',
Ba='Baelthos:BAAANQAECgUIEgAAAA==.Barebut:BAAANQADCgEIAQAAAA==.',
Be='Bermon:BAAANQADCgYIDAABNQAECgcIJgADAEoUAA==.Berrypunch:BAAANQADCgcIEAAAAA==.',
Bi='Bingo:BAAANQAECgQICAAAAA==.',
Bl='Bluebyyou:BAAANQAECgYIEQAAAA==.',
Bo='Borgor:BAAANQADCgEIAQAAAA==.',
Bu='Bubblé:BAABNQAECn8XAAMGAAgKmRWhSQBFAgAGAAgKmRWhSQBFAgAHAAUKZwv4RgD/AAAAAA==.Bustei:BAAANQAECgEIAQAAAA==.',
Ca='Caelion:BAABNQAECn8cAAIEAAgKPiJ5GAAWAwAEAAgKPiJ5GAAWAwAAAA==.Cannex:BAAANQAECgUIEAAAAA==.',
Ce='Celestia:BAAANQAECgYIDQAAAA==.',
Cl='Clarinet:BAAANQAECgEIAQABNQAECgQIBQAIAAAAAA==.Clarinetbdk:BAAANQAECgQIBQAAAA==.',
Co='Coomerlord:BAAANQAECgEIAQAAAA==.',
Da='Daki:BAAANQADCgUICgABNQAECggIHQAJAMoLAA==.',
De='Deathhunter:BAAANQABCgQIBAAAAA==.Deekon:BAABNQAECn8cAAMFAAcKmRnfdAD+AQAFAAcKmRnfdAD+AQAKAAEKugYZfwAsAAAAAA==.Delryn:BAAANQAECgQIBgAAAA==.Deshand:BAAANQABCgEIAQAAAA==.Deyvian:BAAANQADCgQIBAAAAA==.',
Do='Dooplikit:BAAANQADCgYIBwAAAA==.',
Dp='Dpn:BAABNQAECn8nAAMLAAkKwyFFHQBiAwALAAkKwyFFHQBiAwAMAAEK1As9DAA/AAABNQAECgQICQAIAAAAAA==.',
Dr='Draxil:BAAANQAECgEIAQAAAA==.Druish:BAAANQAECgEIAQAAAA==.',
Du='Durpp:BAAANQAECgUIEgAAAA==.Dusyk:BAAANQAECgIIAwAAAA==.',
['Dä']='Däisymäy:BAAANQADCgEIAQABNQAECgcIGwABAGYdAA==.',
Eg='Egud:BAABNQAECn8eAAINAAcKmxk+EAAhAgANAAcKmxk+EAAhAgAAAA==.',
El='Elipse:BAAANQADCgUIBgAAAA==.Elipsis:BAAANQAECgEIAgAAAA==.Eliri:BAABNQAECn8WAAIOAAgKexvbEQBbAgAOAAgKexvbEQBbAgABNQAFFAIIAgAIAAAAAA==.Ellenad:BAAANQAECgIIAwAAAA==.',
En='Enemy:BAAANQAECgUICwABNQAECggIFAAPAA8TAA==.',
Es='Estia:BAAANQABCgEIAQAAAA==.',
Ev='Everflux:BAABNQAECn8eAAIGAAcKIx/fQABkAgAGAAcKIx/fQABkAgAAAA==.Everhunt:BAAANQAECgEIAQAAAA==.Evo:BAABNQAECn8UAAIPAAgKDxPbBQBNAgAPAAgKDxPbBQBNAgAAAA==.',
Ey='Ey:BAAANQAECgIIAgAAAA==.',
Fa='Farisu:BAACNQAFFH8MAAMJAAYK2Q62CQB2AQAJAAUK2Q62CQB2AQADAAEKAADDLAA+AAA1AAQKfx8AAwkACQq/HA0zAFwCAAkACQqsHA0zAFwCAAMABArPGWGAAPYAAAAA.',
Fe='Feoran:BAAANQADCgIIAgAAAA==.',
Fj='Fjara:BAAANQADCgYIBgAAAA==.',
Fl='Flick:BAAANQAECgQIBAAAAA==.',
Fr='Frontallover:BAAANQADCgEIAQABNQAFFAIIAgAIAAAAAA==.',
Ge='Georish:BAAANQAECgUIBwAAAA==.',
Gi='Gilgamësh:BAAANQADCgIIAgAAAA==.Ginseng:BAABNQAECn8aAAIQAAgKkBQaUwAXAgAQAAgKkBQaUwAXAgAAAA==.Giritos:BAAANQADCgYIBgAAAA==.Girthquake:BAABNQAECn8gAAIQAAgKzSRvEABAAwAQAAgKzSRvEABAAwAAAA==.',
Go='Gorg:BAAANQADCgMIAwAAAA==.',
['Gé']='Gémini:BAAANQAECgUICAAAAA==.',
Ha='Haavoc:BAAANQAECgEIAQABNQAECggIIgARAO8HAA==.Hagul:BAAANQAECgIIAgAAAA==.Hakuad:BAAANQADCgIIAgAAAA==.Halanhar:BAAANQADCgcICgAAAA==.Hashi:BAAANQAECgEIAQAAAA==.',
He='Hellrocker:BAAANQAECgQICwAAAA==.Hermione:BAAANQAECgUICQABNQAECgIIAwAIAAAAAA==.Hestia:BAAANQABCgQIBAAAAA==.',
Ho='Holyvader:BAAANQADCggICAAAAA==.',
Hu='Hukhan:BAAANQAECgEIAQAAAA==.Huraaki:BAAANQAECgIIAgAAAA==.',
In='Innis:BAABNQAECn8aAAMGAAgKNRu4RQBTAgAGAAgKNRu4RQBTAgASAAEKVwd7LAAqAAAAAA==.',
Ir='Irine:BAAANQAECgUIDQAAAA==.Irore:BAAANQAECgQIDQAAAA==.',
It='Itszoi:BAAANQADCgIIAgAAAA==.',
Je='Jenjyandi:BAAANQADCgYIBgABNQAECgUIEgAIAAAAAA==.Jetahnna:BAAANQAECgUIDgAAAA==.',
Ji='Jibbs:BAAANQAECgEIAQAAAA==.',
Jo='Jozlinn:BAABNQAECn8oAAIHAAcK3gShQgAaAQAHAAcK3gShQgAaAQAAAA==.',
Ka='Kaeldar:BAAANQAECgIIBQAAAA==.Kajadin:BAAANQAECgUIEgAAAA==.Karatedonkey:BAAANQAECgUIEQAAAA==.Kardai:BAEANQAECgUIEgAAAA==.Katreia:BAAANQAFFAEIAQABNQAFFAYIGAADAAEZAA==.Kazimas:BAAANQADCgcJFQAAAA==.',
Kh='Khalcite:BAAANQAECgUIEgAAAA==.',
Ki='Kittyshaman:BAABNQAECn8fAAITAAgKywXklQBpAQATAAgKywXklQBpAQAAAA==.',
Kr='Kristyleigh:BAAANQABCgQIBAAAAA==.',
Ku='Kurono:BAAANQAECgUIEgAAAA==.Kuross:BAAANQAECgQICwAAAA==.',
La='Laermeluion:BAAANQAECggIEAABNQAFFAYIGAADAAEZAA==.Larra:BAABNQAECn8bAAIBAAcKZh1maQA+AgABAAcKZh1maQA+AgAAAA==.',
Le='Leen:BAAANQAECgEIAgAAAA==.Lefthian:BAAANQAECgQIDwAAAA==.Leonidas:BAAANQADCggICAAAAA==.',
Lf='Lftwentyones:BAAANQADCgYICwABNQAFFAIIAgAIAAAAAA==.',
Li='Limptriscuit:BAAANQADCgYIBgAAAA==.',
Lo='Loshing:BAAANQAECgIIBwAAAA==.',
Lu='Lunakae:BAAANQADCgIIAgAAAA==.',
Ma='Macumba:BAAANQADCggIDwAAAA==.Madeline:BAABNQAECn8aAAIHAAgKMSDJFgCiAgAHAAgKMSDJFgCiAgAAAA==.Malafar:BAAANQAECgcICwAAAA==.Maranwae:BAABNQAECn8fAAMQAAcKDBlWYADqAQAQAAcKDBlWYADqAQATAAIKpAigDwFmAAAAAA==.Masochist:BAAANQAECgYIEgABNQAECgIIAwAIAAAAAA==.',
Me='Melokoi:BAAANQAECgEIAwAAAA==.Merlose:BAAANQAECgIJBAAAAA==.',
Mi='Mieditos:BAAANQAECgMIBwAAAA==.Minirocks:BAABNQAECn8iAAMUAAgK5RSZEgA8AgAUAAgK5RSZEgA8AgAQAAcKPBWGcwCtAQAAAA==.',
Mo='Moondivine:BAAANQAECgEIAgABNQAECgcICQAIAAAAAA==.Moonfaith:BAAANQAECgcICQAAAA==.Moosader:BAAANQAECgEIAQAAAA==.',
Na='Naleana:BAAANQADCgcIHQAAAA==.Narzwaz:BAAANQAECgUIEgAAAA==.Nataly:BAABNQAECn8YAAIGAAYKyCCbTwAyAgAGAAYKyCCbTwAyAgAAAA==.',
Ne='Neytri:BAABNQAECn8eAAIBAAcK0gysoQC/AQABAAcK0gysoQC/AQAAAA==.',
Ni='Nightmoon:BAAANQADCgYIBQAAAA==.',
No='Nommo:BAAANQAECgUICgABNQAECgYIEQAIAAAAAA==.Nophica:BAAANQAECgcIEQAAAA==.Novaxian:BAAANQAECgQIBgAAAA==.Noxicous:BAAANQADCggIEAAAAA==.',
Nz='Nzoth:BAAANQAECgcIDgAAAA==.',
On='Oneeyedwilly:BAAANQADCgcIBwAAAA==.',
Os='Osaka:BAAANQAECgUIEgAAAA==.',
Pa='Patches:BAAANQAECgUIEQAAAA==.',
Pe='Peänuts:BAAANQAECgEIAgAAAA==.',
Pl='Plagos:BAAANQAECgEIAQAAAA==.',
Po='Pouncival:BAAANQADCgEIAQAAAA==.',
Pr='Prahumn:BAABNQAECn8qAAMGAAkKAB/MGAARAwAGAAkKAB/MGAARAwAHAAEKAACEiQAfAAAAAA==.',
Pu='Purplicious:BAAANQAECgIIAgAAAA==.',
Py='Pymilocs:BAABNQAECn8fAAITAAgKdyAzKQDaAgATAAgKdyAzKQDaAgAAAA==.',
Qi='Qixx:BAAANQAECgUIEQAAAA==.',
Qu='Quint:BAAANQADCgYIDgAAAA==.',
Ra='Rabore:BAAANQAECgMIAwAAAA==.Raktal:BAAANQABCgIIAgAAAA==.Ralee:BAABNQAECn8dAAIJAAgKygt4YgCCAQAJAAgKygt4YgCCAQAAAA==.Ralienne:BAAANQAECgIIBAABNQAECggIHQAJAMoLAA==.Ravinia:BAAANQAECgEIAQABNQAECgEIAQAIAAAAAA==.',
Re='Rennai:BAAANQAECgYICgAAAA==.',
Ri='Richter:BAAANQADCggIIAAAAA==.Rigoletta:BAAANQAECgEIAQAAAA==.Rin:BAEBNQAECn8XAAIOAAcK4BqSFgAQAgAOAAcK4BqSFgAQAgAAAA==.',
Ro='Rogelink:BAAANQADCgYIBgAAAA==.Rosan:BAAANQAECgMIBQAAAA==.Royakan:BAAANQAECgEIAQAAAA==.',
Ru='Rumtumtugger:BAAANQADCgUIBQAAAA==.',
Sa='Samoset:BAAANQAECgUIDgAAAA==.Sasten:BAAANQADCgMIAwAAAA==.',
Se='Serosion:BAAANQADCgcIBwAAAA==.',
Sh='Shaile:BAABNQAECn8UAAIDAAgKsA1PWQCLAQADAAgKsA1PWQCLAQAAAA==.Shalu:BAAANQAECgEIAgAAAA==.Shammysham:BAAANQAECgEIBAAAAA==.Shaymis:BAAANQABCggICwAAAA==.Shifthappons:BAAANQADCgUIBQAAAA==.Shockisha:BAAANQAECgQIBAAAAA==.Shogoth:BAAANQADCgEIAQAAAA==.',
Si='Sightseer:BAABNQAECn8YAAIBAAgK4gbaqACvAQABAAgK4gbaqACvAQAAAA==.Silverthorn:BAABNQAECn8VAAIVAAgKzwrGuQCjAQAVAAgKzwrGuQCjAQAAAA==.',
Sk='Skrom:BAAANQADCgIIAgAAAA==.',
Sn='Sney:BAAANQADCgUICgABNQAECggIHQAJAMoLAA==.',
Su='Suotokahn:BAAANQADCgUIBQAAAA==.',
Sw='Sweetti:BAAANQADCgcIBwABNQAECgcIGwABAGYdAA==.',
Sy='Sybbil:BAAANQADCgQIBAAAAA==.',
Ta='Tad:BAAANQAECgUIEAAAAA==.Taeltaa:BAAANQAECgUIBQAAAA==.Takara:BAAANQABCggIGwAAAA==.Taken:BAAANQAECgUIEAAAAA==.Tazra:BAABNQAECn8tAAIVAAkKmiDhJwAkAwAVAAkKmiDhJwAkAwAAAA==.',
Th='Theshammslam:BAAANQADCgMIAwAAAA==.Thomaz:BAABNQAECn8hAAMWAAkKMgp2GQAIAQARAAgK1wnisQCbAQAWAAYK2Qh2GQAIAQAAAA==.Thx:BAAANQAECgIIAgAAAA==.',
Ti='Tiarini:BAAANQADCggIKAAAAA==.Tilee:BAAANQADCgUICQAAAA==.',
To='Tondri:BAABNQAECn8qAAIEAAgKrxZAUQAkAgAEAAgKrxZAUQAkAgAAAA==.Tonkatruck:BAAANQAECgQICQAAAA==.',
Tr='Traice:BAAANQABCgYICQAAAA==.',
Tu='Tuyenlotus:BAABNQAECn8hAAIUAAkK6RqcDgB/AgAUAAkK6RqcDgB/AgAAAA==.',
['Tò']='Tòkkí:BAAANQAECgUIBwAAAA==.',
Va='Vahnya:BAABNQAECn8eAAITAAgKYRNJXQAHAgATAAgKYRNJXQAHAgAAAA==.',
Ve='Venekor:BAAANQADCggICQAAAA==.',
Vi='Vicarrion:BAAANQAECgcIEwAAAA==.Viscera:BAAANQADCgIIAwAAAA==.Vitesse:BAAANQADCgcIBwAAAA==.',
Vl='Vlane:BAAANQADCgEIAQAAAA==.',
Vr='Vrat:BAABNQAECn8gAAIBAAgK3hU6bgAzAgABAAgK3hU6bgAzAgAAAA==.',
['Ví']='Ví:BAAANQAECgQIBwAAAA==.',
Wa='Warfare:BAABNQAECn8iAAIRAAgK7weXvACAAQARAAgK7weXvACAAQAAAA==.Warxie:BAAANQADCggIDgABNQAECgYIDQAIAAAAAA==.',
We='Wendrix:BAAANQADCggICAAAAA==.',
Wi='Winxie:BAAANQAECgEIAQABNQAECgYIDQAIAAAAAA==.',
Wt='Wtfoxtrot:BAAANQADCggICAAAAA==.',
Yo='Yourmageisty:BAABNQAECn8fAAMLAAgKexgPjwBhAgALAAgKLhgPjwBhAgAXAAMKVhn+IQDYAAAAAA==.',
Yu='Yulíana:BAAANQAECgcIEgAAAA==.',
Za='Zanot:BAAANQADCgQIBAAAAA==.',
Zc='Zcart:BAABNQAECn8fAAMBAAgKyQ4jfgAOAgABAAgKyQ4jfgAOAgAYAAIKAADGegBSAAAAAA==.',
Ze='Zelara:BAAANQAECgYIBgAAAA==.Zeluxum:BAAANQAECgEJAgABNQAECgUIEAAIAAAAAA==.Zerkio:BAABNQAECn8eAAIQAAkKpxMyRABNAgAQAAkKpxMyRABNAgAAAA==.Zertloc:BAABNQAECn84AAMTAAkKCyGFEgBbAwATAAkKCyGFEgBbAwAQAAEK9gToGQEzAAAAAA==.',
Zi='Zieda:BAAANQAECgcIDgAAAA==.',
Zo='Zoids:BAAANQADCgEIAQAAAA==.',
Zu='Zulix:BAAANQAECgEIAQAAAA==.Zulixx:BAAANQADCgQIBAAAAA==.',
Zy='Zyriatchi:BAAANQAECgMIBAAAAA==.',
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
