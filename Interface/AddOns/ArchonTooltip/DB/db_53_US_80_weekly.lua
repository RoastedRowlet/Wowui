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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','Mage-Frost','Druid-Balance','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Feral','Druid-Restoration','Paladin-Retribution','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Evoker-Devastation','Evoker-Preservation','Hunter-Survival','Paladin-Holy',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=53,date='2026-09-29',data={Al='Aletalle:BAAANQAECgQIBAAAAA==.Allice:BAAANQAECgYIEQAAAA==.Alsheyra:BAAANQADCgYICgAAAA==.Alterion:BAAANQABCgQICgAAAA==.',
An='Anxious:BAAANQADCgYIEAAAAA==.',
As='Ashwalker:BAAANQADCggIEAAAAA==.',
Au='Aughyst:BAAANQAECgMJBwAAAA==.Augnyxia:BAAANQAECgQICgAAAA==.Augtysm:BAAANQADCggICAAAAA==.',
Ba='Bandobras:BAAANQADCgcIDgAAAA==.',
Bh='Bhorg:BAAANQADCgMIAwAAAA==.',
Bl='Blackdust:BAAANQADCggIDQAAAA==.Blasters:BAAANQADCgcIEgAAAA==.Bloodjury:BAAANQAECgQIBgAAAA==.Blossom:BAAANQABCgIIAgABNQABCgYICwABAAAAAA==.',
Bo='Borellus:BAAANQABCgUICQAAAA==.',
Br='Broken:BAAANQABCgYIBgAAAA==.',
Bu='Bunga:BAAANQAECgEIAQAAAA==.Bungis:BAAANQAECgYICAAAAA==.Bushetti:BAAANQAFFAEIAQAAAA==.',
Ca='Casperface:BAABNQAECoEZAAMCAAgKgA2+WQDEAQACAAgKgA2+WQDEAQADAAEKqQ8N8QAsAAAAAA==.Cazisham:BAAANQAECgMIBwAAAA==.',
Ce='Cestus:BAAANQAECgcJDQAAAA==.Cevianne:BAAANQAECgIIAgAAAA==.',
Ci='Ciaphis:BAAANQAECgEIAgAAAA==.Cinnabuns:BAAANQADCgQIAwAAAA==.',
Co='Coal:BAAANQAECgYIDgAAAA==.Coltonater:BAACNQAFFIEHAAIEAAUKThIREQCgAQAEAAUKThIREQCgAQA1AAQKgSsAAgQACQqcIk8PAIgDAAQACQqcIk8PAIgDAAAA.',
['Cá']='Cáséy:BAABNQAECoEeAAIFAAkKVB8oAgAhAwAFAAkKVB8oAgAhAwAAAA==.',
['Cä']='Cäsey:BAAANQADCgMIAwABNQAECgkJHgAFAFQfAA==.',
Da='Darkshroud:BAAANQADCgYICAAAAA==.Datbi:BAABNQAECoEcAAIGAAgKBRIvMgAKAgAGAAgKBRIvMgAKAgAAAA==.Daugi:BAAANQAECgYIBwAAAA==.',
De='Deathangel:BAAANQAECgMIAwAAAA==.Deathdeamon:BAAANQADCgMIAwAAAA==.Deathdylan:BAABNQAECoEhAAIHAAkKWh4wEAAGAwAHAAkKWh4wEAAGAwAAAA==.Delice:BAAANQAECgEIAQAAAA==.Demonikal:BAAANQAECgQIBAAAAA==.Demítríus:BAAANQAECgIIAgAAAA==.Dethh:BAAANQAECgUIDAAAAA==.',
Di='Didona:BAAANQADCgYIBgAAAA==.Distortion:BAAANQADCggIDwAAAA==.Divineflava:BAAANQADCgEIAQABNQAECgkJLQAEADEiAA==.',
Do='Dobby:BAAANQADCggICgAAAA==.',
Dr='Drakeo:BAAANQAECgUICAAAAA==.Draximus:BAAANQAECgMIBQAAAA==.Drougenin:BAAANQADCgMIAwABNQAECgYIDgABAAAAAA==.Drpumper:BAAANQAECgUIDAAAAA==.Druqz:BAABNQAECoEcAAIFAAkKGhKkBwAlAgAFAAkKGhKkBwAlAgAAAA==.Druski:BAAANQABCgQJBAAAAA==.Drævn:BAAANQAECgUIEgAAAA==.',
Du='Dum:BAACNQAFFIEIAAQIAAMKQxfaAgCLAAAJAAIKFBjdDgCZAAAIAAIKjhXaAgCLAAAKAAEKrhpRDwBOAAA1AAQKgSMABAoACQoGIwIOAOcCAAoACAqbIAIOAOcCAAgABwovGrQIAAsCAAkAAwpBIhZFACkBAAAA.Duragon:BAAANQAECgUIEAAAAA==.Durkagon:BAAANQAECgQIBwAAAA==.',
Dw='Dwimbear:BAAANQABCgIIAgAAAA==.Dwimhoof:BAAANQADCgMIAwAAAA==.Dwinnet:BAAANQABCgQICQAAAA==.',
El='Eldin:BAABNQAECoEbAAMLAAkKyCEAAQBEAwALAAgK1SMAAQBEAwAMAAEKXBEBwABLAAAAAA==.',
En='Enro:BAABNQAECoEcAAIJAAkKjxfdGQCGAgAJAAkKjxfdGQCGAgAAAA==.',
Er='Erovia:BAABNQAECoEfAAINAAgKDRGcWQAVAgANAAgKDRGcWQAVAgAAAA==.',
Es='Esclipse:BAAANQADCgYIBgAAAA==.',
Et='Etclock:BAAANQADCgYIBgAAAA==.',
Fa='Farruq:BAAANQAECgUJCwAAAA==.Fathermoo:BAAANQADCgEIAQAAAA==.',
Fe='Feelsbadmang:BAAANQADCgQIBAABNQAECgcICgABAAAAAA==.Fellz:BAAANQADCgIIAgAAAA==.Ferer:BAEANQADCgYIBgABNQAECggIHQAOAAAaAA==.Ferian:BAAANQAECgQIDQAAAA==.',
Fl='Flavaflare:BAABNQAECoEtAAIEAAkKMSLnEgB4AwAEAAkKMSLnEgB4AwAAAA==.',
Fo='Foodex:BAAANQAECgUIEAAAAA==.Fourleaf:BAABNQAECoEcAAIOAAkKCRrFEAC7AgAOAAkKCRrFEAC7AgAAAA==.',
Fu='Furlock:BAAANQAECgIIAwAAAA==.Furral:BAABNQAECoEaAAIPAAkKNxl4BgCrAgAPAAkKNxl4BgCrAgAAAA==.Furretc:BAAANQADCgEIAQAAAA==.',
Ga='Gaeth:BAABNQAECoEZAAIQAAgKNxTLGwADAgAQAAgKNxTLGwADAgAAAA==.',
Gl='Gleg:BAACNQAFFIEIAAMDAAMKrBmrDgDzAAADAAMKrBmrDgDzAAACAAIKuggNGwCPAAA1AAQKgSIAAwMACQoTImcNADIDAAMACQoTImcNADIDAAIAAQpzFtryADwAAAAA.',
Go='Goodside:BAAANQADCgYIDAAAAA==.',
Gr='Grimthebrave:BAAANQAECgcIDAAAAA==.Grimthecruel:BAAANQAECggIEwAAAA==.Gripless:BAAANQADCgQIBAAAAA==.Griselden:BAABNQAECoEcAAIKAAgKaR3BEgCqAgAKAAgKaR3BEgCqAgAAAA==.Grizzlyras:BAAANQADCggICAAAAA==.',
Gu='Gub:BAAANQAECgQJCwAAAA==.',
Ha='Hannsollo:BAAANQADCgMIAwAAAA==.',
Ho='Holyshock:BAAANQABCgYIEAAAAA==.',
['Hâ']='Hâmburger:BAAANQADCgIIAgAAAA==.',
Ir='Iridessa:BAAANQADCgcIEgAAAA==.',
Is='Ishpoo:BAABNQAECoEjAAIRAAgKgRbQVwA8AgARAAgKgRbQVwA8AgAAAA==.',
Ja='Jangarinna:BAAANQADCgQIBAAAAA==.',
Ji='Jip:BAAANQAECgQIBAAAAA==.',
Jl='Jlawq:BAAANQADCgUJBQAAAA==.Jlawzzs:BAAANQAECgYIEgAAAA==.',
Jo='Job:BAABNQAECoEwAAIJAAkK2CV4AgDCAwAJAAkK2CV4AgDCAwAAAA==.',
Ju='Judgim:BAAANQADCgQIBAAAAA==.Judoriel:BAAANQADCgcIBwAAAA==.Junkyard:BAAANQADCgcIBwAAAA==.',
Ka='Kaimin:BAABNQAECoEbAAISAAcKmSGpGwCkAgASAAcKmSGpGwCkAgAAAA==.Karuun:BAAANQADCgYIEAABNQAECgQICAABAAAAAA==.',
Ke='Kezeshi:BAAANQAECgcIEQAAAA==.',
Kh='Khaidralulz:BAABNQAECoEjAAIDAAgKvQ/8VADAAQADAAgKvQ/8VADAAQAAAA==.Khonsu:BAAANQAECgIIAgAAAA==.',
Ki='Kiba:BAAANQAECgQICwAAAA==.',
Kr='Kraegen:BAAANQAECgcIDQAAAA==.',
Ky='Kyofu:BAABNQAECoEnAAMTAAgKNhaZEgAAAgATAAgKNhaZEgAAAgAUAAMKIAreRQB/AAAAAA==.',
La='Larenta:BAAANQAECgcIEgAAAA==.Larethiana:BAABNQAECoEdAAIQAAkKPyLPCAAJAwAQAAkKPyLPCAAJAwABNQAECggIDAABAAAAAA==.Laria:BAAANQAECggIDAAAAA==.',
Le='Leafmochi:BAAANQAECgQIBQAAAA==.Letloose:BAAANQADCgEIAQAAAA==.',
Li='Lightbright:BAABNQAECoEdAAIRAAkK6yKTEwBYAwARAAkK6yKTEwBYAwAAAA==.Lildab:BAAANQAECgYIEwAAAA==.Linashia:BAABNQAECoEhAAIMAAkKMRM8MgBcAgAMAAkKMRM8MgBcAgAAAA==.',
Lo='Lostwanderer:BAAANQADCggIDgAAAA==.',
Lu='Luhen:BAAANQADCgYIBgAAAA==.',
Ma='Magicology:BAABNQAECoFHAAIEAAkKAybrAAD4AwAEAAkKAybrAAD4AwAAAA==.Malacoda:BAABNQAECoEjAAIJAAgKxBveGACQAgAJAAgKxBveGACQAgAAAA==.Manamommy:BAAANQAECgcIEAAAAA==.Marble:BAAANQADCgYIBwAAAA==.',
Me='Merlx:BAAANQADCggIEQAAAA==.',
Mi='Miladee:BAAANQADCgYIBgAAAA==.Mindra:BAAANQAECgcIEQAAAA==.',
Mo='Moatie:BAAANQADCgQIBQAAAA==.Moobundo:BAAANQAECgcICwAAAA==.Moonmama:BAAANQABCgQIBAAAAA==.Moonwren:BAAANQAECggIEQAAAA==.Morgrin:BAAANQAECgYIDwAAAA==.',
Ne='Nezroz:BAAANQAECgEIAQABNQAECgUIDAABAAAAAA==.',
Ni='Nicotine:BAAANQAECgYICwAAAA==.Nike:BAAANQAECgcICgAAAA==.Nipsey:BAAANQADCgYIBgAAAA==.Nitwp:BAABNQAECoEjAAMVAAkK1xkxCQC5AgAVAAkK1xkxCQC5AgAWAAEK7ARgRAArAAAAAA==.Nizo:BAAANQAECgUIDwAAAA==.',
Nj='Njal:BAAANQADCgUJBQAAAA==.',
No='Novastrike:BAABNQAECoEgAAMCAAkK7BhYKwCTAgACAAkK7BhYKwCTAgADAAIKHQPo1gBeAAAAAA==.',
Ny='Nymphia:BAAANQAECgUIBQAAAA==.Nyrif:BAABNQAECoEbAAIHAAkK9BktHwCEAgAHAAkK9BktHwCEAgAAAA==.',
Oj='Ojoon:BAAANQAECgYICQAAAA==.',
Om='Omnisllash:BAAANQAECgUIBgAAAA==.',
Pa='Pallamb:BAAANQADCgUIBQAAAA==.',
Ph='Phyter:BAAANQAECgQIBwAAAA==.',
Pi='Pillin:BAAANQAECgQIBQAAAA==.',
Po='Polyestr:BAAANQADCgQIBAAAAA==.Porkchowmein:BAAANQAECgMIAwAAAA==.',
Ps='Psylence:BAAANQAECgIIAwAAAA==.Psyrge:BAAANQAECgIIAgAAAA==.',
Qu='Queue:BAAANQAECgQICAAAAA==.',
Re='Redle:BAAANQADCggICgAAAA==.',
Rh='Rhordric:BAEBNQAECoEdAAQOAAgKABrBKQCtAQAOAAcKQRLBKQCtAQANAAYKkxT3igCRAQAXAAEKKwe9EAAqAAAAAA==.',
Ro='Roku:BAAANQADCgUIBQAAAA==.Rottenbeef:BAAANQAECgUIBQAAAA==.',
Ru='Runicmommy:BAAANQADCgUIBQAAAA==.',
Sa='Saintbull:BAAANQABCgYIBwAAAA==.Samwinchestr:BAAANQADCgIIAgAAAA==.Sanyoalt:BAAANQADCgEIAQAAAA==.',
Sc='Scemo:BAAANQADCgUIBQAAAA==.',
Se='Sea:BAACNQAFFIEQAAIDAAYKkRtqAgA5AgADAAYKkRtqAgA5AgA1AAQKgScAAgMACQrGJP4DAJYDAAMACQrGJP4DAJYDAAAA.Serendipity:BAAANQAECgQIBwAAAA==.',
Sh='Shadowaurora:BAAANQADCggJCAAAAA==.Shadowrose:BAAANQAECgQICQAAAA==.Shamano:BAAANQAECgIIAwABNQAECgQIDgABAAAAAA==.Shanogadin:BAAANQADCggJHgAAAA==.Shiemi:BAAANQAECgUJBQAAAA==.',
Sq='Squeaky:BAAANQAECgQIAgAAAA==.',
Su='Sungodess:BAAANQADCgcJDgAAAA==.',
Sy='Syrupp:BAAANQAECgYIDAAAAA==.',
Ta='Tayn:BAAANQADCgcJDAAAAA==.',
Th='Thackery:BAAANQADCggICwAAAA==.',
Tr='Trenetalan:BAAANQADCgIJAgABNQADCggIEAABAAAAAA==.',
Ts='Tsavø:BAAANQAECgQJBAAAAA==.',
Tw='Twinkle:BAAANQAECggIDAAAAA==.',
Un='Unholysage:BAAANQAECgUICwAAAA==.Untouchable:BAAANQADCgEIAQAAAA==.',
Va='Valenîx:BAAANQADCgEIAQABNQAECggIEgABAAAAAA==.',
Ve='Venetrazat:BAABNQAECoEkAAIVAAcKQhSwEwDRAQAVAAcKQhSwEwDRAQAAAA==.',
Vo='Vo:BAAANQADCgYIDQAAAA==.Vol:BAAANQADCgUIBQAAAA==.',
['Vâ']='Vâlenix:BAAANQAECggIEgAAAA==.',
['Vä']='Välenix:BAAANQAECgIIAgABNQAECggIEgABAAAAAA==.',
Wa='Warder:BAAANQAECgUICwAAAA==.',
We='Wewaskangz:BAAANQAECgIIAwAAAA==.',
Wi='Wincks:BAAANQAECgQIDgAAAA==.',
Xh='Xhosar:BAABNQAECoEgAAIXAAgKtBUSBABmAgAXAAgKtBUSBABmAgAAAA==.',
Za='Zachthemage:BAAANQAECgYIEgAAAA==.Zackman:BAABNQAECoElAAIYAAkK1giFUwDZAQAYAAkK1giFUwDZAQAAAA==.',
Zi='Zinatrax:BAAANQADCgYIDAAAAA==.',
Zo='Zombie:BAABNQAECoEiAAISAAgKsBwLKwA0AgASAAgKsBwLKwA0AgAAAA==.',
Zu='Zuldrakar:BAAANQADCgUICQAAAA==.Zulrea:BAABNQAECoEiAAIGAAgKURg4JwBeAgAGAAgKURg4JwBeAgAAAA==.',
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
