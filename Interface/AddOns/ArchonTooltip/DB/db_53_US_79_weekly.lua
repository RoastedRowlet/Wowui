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

local lookup = {'Druid-Balance','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Shaman-Elemental','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Shaman-Restoration','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Devastation','Unknown-Unknown','Druid-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Windwalker','Warrior-Protection','Druid-Feral','Priest-Holy','Druid-Guardian','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaronius:BAAANQAECgUIDAAAAA==.',
Ac='Acceptance:BAAANQADCgYICAAAAA==.',
Ad='Adoe:BAAANQAECgUICwAAAA==.Adora:BAAANQAECgMJBQAAAA==.',
Ae='Aeveen:BAAANQADCgUIBwAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQADCgYJDQAAAA==.',
Ai='Aidenator:BAAANQAECgUICwAAAA==.',
Al='Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQADCgEIAQAAAA==.Andretta:BAAANQADCggIDgAAAA==.Angelneko:BAABNQAECoEZAAIBAAYK0wWZaQD6AAABAAYK0wWZaQD6AAAAAA==.',
Ar='Arinthian:BAAANQAECgQIBAAAAA==.Artrian:BAAANQAECgUICQAAAA==.',
At='Atetoomuch:BAAANQABCgYIBgAAAA==.Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAAANQAECgQICwAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECoEjAAICAAcKdA7K1QC1AQACAAcKdA7K1QC1AQAAAA==.Aztrik:BAAANQAECgUIEQAAAA==.',
Ba='Bajapanti:BAAANQAECgYIEQAAAA==.Ballyhøø:BAAANQAFFAEIAQAAAA==.Bandaron:BAAANQADCgQIBAAAAA==.Baxstab:BAABNQAECoEbAAMDAAcKYxRfMADnAQADAAcKYxRfMADnAQAEAAIK1Qj2QgBwAAAAAA==.',
Be='Belladeon:BAABNQAECoEZAAMFAAgKiBAhHQDcAAACAAgKZwi21wCxAQAFAAMKuhkhHQDcAAAAAA==.',
Bh='Bhagee:BAAANQADCgUICgAAAA==.',
Bl='Blackpatch:BAAANQAECgcIEwAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAABNQAECoEXAAIGAAcKoQ18eACIAQAGAAcKoQ18eACIAQAAAA==.Blargg:BAAANQAECgIIAgAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAABNQAECoEaAAIHAAcK9xqTSQAiAgAHAAcK9xqTSQAiAgAAAA==.',
Bo='Booneboy:BAAANQAECgQICwAAAA==.Botemedel:BAABNQAECoEUAAIIAAcKaRntGQD4AQAIAAcKaRntGQD4AQAAAA==.',
Br='Brennor:BAABNQAECoEbAAIJAAcKPwZa1QA2AQAJAAcKPwZa1QA2AQAAAA==.Brewslunt:BAABNQAECoEaAAIKAAkKCBl+DACbAgAKAAkKCBl+DACbAgABNQAFFAUIDgALAAoVAA==.Bronamaly:BAAANQADCgYICAAAAA==.',
Ca='Cabbagehunt:BAAANQADCgYJBgAAAA==.Caeden:BAABNQAECoEYAAILAAgKkgwpcgCFAQALAAgKkgwpcgCFAQAAAA==.Cairyan:BAABNQAECoEZAAIMAAgKyxVACgAJAgAMAAgKyxVACgAJAgAAAA==.Cassin:BAAANQADCgIIAwAAAA==.Castalia:BAAANQAECgQICwAAAA==.Cattilina:BAAANQADCggIEAAAAA==.',
Ce='Celenara:BAABNQAECoElAAMCAAkKaR3OVwC/AgACAAkKaR3OVwC/AgAFAAIKIA5FMQBeAAAAAA==.Celendil:BAAANQADCgUIBQABNQAECgkJJQACAGkdAA==.Celinne:BAAANQADCgUIBQAAAA==.Celithe:BAAANQAECgIIBAAAAA==.',
Ch='Charmcaster:BAAANQAECgYIEwAAAA==.Charmstrike:BAAANQAECgIIAgAAAA==.Chedissa:BAAANQADCgQIBAAAAA==.Chleo:BAAANQAECgQICwAAAA==.Choco:BAACNQAFFIEXAAINAAcK3h6HAQCUAgANAAcK3h6HAQCUAgA1AAQKgSkAAw0ACQrOIVcIABADAA0ACQrOIVcIABADAA4AAgobFokuAIAAAAAA.Chocolat:BAAANQADCggICAABNQAFFAcIFwANAN4eAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Co='Coggler:BAAANQAECgQIBwAAAA==.Conqueror:BAAANQAECgMIAwABNQAECgcIDAAPAAAAAA==.',
Cr='Creatlach:BAAANQAECgIIAgABNQAFFAUIDgALAAoVAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAAANQAECgcIEgAAAA==.',
Cu='Cuppajoe:BAAANQADCgMIAwAAAA==.Cupper:BAAANQABCgcJCQABNQAECgQIBwAPAAAAAA==.Curmudge:BAABNQAECoEjAAIQAAgK/xX9HQAUAgAQAAgK/xX9HQAUAgAAAA==.',
Da='Dabtoomuch:BAAANQABCgIIAgAAAA==.Dalectra:BAAANQAECgQICAAAAA==.Darachane:BAAANQADCgcILQAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgYIHAARAHIfAA==.Darthnater:BAAANQAECggIDQAAAA==.Dauglow:BAABNQAECoEbAAMSAAcK0RBlnACbAQASAAYKCBJlnACbAQATAAEKhwmkdQA7AAAAAA==.',
De='Deathstars:BAAANQADCgYIBgAAAA==.Deboss:BAAANQADCggJDwAAAA==.Dellianne:BAAANQABCgEIAQAAAA==.Delritha:BAAANQAECgQICAAAAA==.Deltithrax:BAABNQAECoEZAAMUAAYKrRH2DABVAQAUAAYKrRH2DABVAQAOAAIK1w4XMQBnAAAAAA==.Demonagent:BAAANQAECgQIBwABNQAECgUIBQAPAAAAAA==.Desdh:BAACNQAFFIEFAAIVAAIKqBL9EgCPAAAVAAIKqBL9EgCPAAA1AAQKgSUAAhUACAq9IRkXAMMCABUACAq9IRkXAMMCAAAA.Devious:BAAANQAECgEIAQABNQAECgcIGgAHAPcaAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECgQIDwAPAAAAAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAAANQAECgQIEgAAAA==.Dohane:BAAANQADCgQIBAABNQAECgUICAAPAAAAAA==.Domrogue:BAAANQAECgIIAgAAAA==.Dornoch:BAAANQADCgYJDQAAAA==.',
Dr='Dramine:BAAANQADCgQJBwAAAA==.Draone:BAAANQAECgYIEgAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECoEgAAMVAAkKWA+qNADVAQAVAAgKwA+qNADVAQAWAAgK5weDMQCRAQAAAA==.Drhkillinger:BAAANQAECgUIBQAAAA==.Drspades:BAAANQAECgEIAQAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAABNQAECoEWAAQXAAgKUhiVXgBvAQAXAAYKeheVXgBvAQAYAAYKMBEnTAA9AQARAAEKpx4uqQBZAAAAAA==.',
El='Elessaria:BAAANQAECgQICwAAAA==.Elfatheàrt:BAAANQADCgYJDQAAAA==.Elidrus:BAAANQADCgYICgABNQAECgQICgAPAAAAAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAABNQAECoEfAAIZAAcKqhujHQAvAgAZAAcKqhujHQAvAgAAAA==.',
Es='Estherras:BAAANQAECgUIDAAAAA==.',
Fe='Feardotrun:BAAANQAECgUIEQAAAA==.Felicious:BAAANQADCgYJDQAAAA==.',
Fi='Finally:BAAANQADCgYJDQAAAA==.Firemage:BAABNQAECoEbAAMaAAgKByPvSgBUAgAaAAYKJCPvSgBUAgAbAAQKiR4YIQBeAQAAAA==.Fizzanelf:BAAANQADCgYICwAAAA==.',
Fl='Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECgcIDgAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Friendo:BAAANQAECggIEAAAAA==.Frostbight:BAABNQAECoEfAAICAAcKsxXKvADnAQACAAcKsxXKvADnAQAAAA==.Frostied:BAAANQAECgYIDgAAAA==.',
Fu='Futnuraz:BAAANQADCgYJDQAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgABNQAECggIBQAPAAAAAA==.Fyriat:BAAANQAECgUIDAAAAA==.',
Ga='Galathel:BAABNQAECoEaAAIIAAcK3BArKQBnAQAIAAcK3BArKQBnAQAAAA==.Gazardiel:BAAANQAECgQIDQAAAA==.',
Ge='Gelinia:BAAANQAECgUIDAAAAA==.Gerrald:BAAANQADCgQIBAABNQAECgQIDwAPAAAAAA==.Getafix:BAAANQADCggJCAABNQAECgcIGgAIANwQAA==.',
Gi='Girthquakes:BAAANQAECgEIAQAAAA==.',
Gl='Glorbo:BAAANQAECgUIDAAAAA==.',
Go='Goldstorm:BAAANQADCggIDgAAAA==.Goliath:BAABNQAECoEXAAMLAAYKtRVVeQBxAQALAAYKtRVVeQBxAQAGAAUKBBCFngApAQAAAA==.',
Gr='Gregoron:BAAANQABCgYIBgAAAA==.Grimfelborn:BAABNQAECoElAAMaAAkKZBpmOwCFAgAaAAkKZBpmOwCFAgAcAAEK9B28IgBQAAAAAA==.Grimosh:BAAANQAECgEIAQAAAA==.Grondosh:BAAANQAECgMIBAAAAA==.Gryphindor:BAAANQAECgYIEAAAAA==.',
['Gì']='Gìorgìa:BAAANQABCgIIAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECgQICgAPAAAAAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAAANQAECgQIBwAAAA==.Hapsburg:BAABNQAECoEbAAMKAAcKfA7FHwBlAQAKAAcKfA7FHwBlAQAdAAYKaQgzOwACAQAAAA==.Havince:BAAANQAECgYIEwAAAA==.Hawktuah:BAAANQAECgEIAQAAAA==.Haylee:BAAANQABCgIIAgAAAA==.',
He='Helle:BAAANQADCgUICAAAAA==.Hercboyy:BAABNQAECoEhAAMHAAgKZCM3FgATAwAHAAcKgSY3FgATAwAIAAEKwR+gVgBXAAAAAA==.',
Hi='Higgs:BAAANQADCggICQABNQAECgYIEQAPAAAAAA==.Higgspally:BAAANQAECgYIEQAAAA==.',
Ho='Holyball:BAAANQAECgYIEQAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECgYIEwAPAAAAAA==.Huuken:BAAANQADCgUIBQAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggJCAAAAA==.Ilyndra:BAABNQAECoEZAAIeAAYKISXTCQB/AgAeAAYKISXTCQB/AgAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgQIBwAAAA==.',
Is='Iselilja:BAAANQAECgUIDAAAAA==.',
It='Ithea:BAABNQAECoEgAAICAAkKCxZleAB3AgACAAkKCxZleAB3AgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEANQAECgUICAAAAA==.Jakaro:BAACNQAFFIEGAAMbAAMK7QY/EACHAAAbAAIKmQM/EACHAAAaAAEKlg2kNgBLAAA1AAQKgRoAAxsACArsE3MoACkBABoABgrPFMCRAIsBABsABQqDEXMoACkBAAAA.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECggIBQAPAAAAAA==.Jeefrenzy:BAAANQAECggIBQAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAgABNQAECggIBQAPAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAABNQAECoEZAAMSAAYKlRtudQD3AQASAAYKlRtudQD3AQATAAUKtw2ERAABAQAAAA==.',
Jo='Joap:BAAANQADCgcIBwAAAA==.Joejr:BAAANQAECgYIEgAAAA==.Jonald:BAABNQAECoEYAAIWAAgK8wzVKwDBAQAWAAgK8wzVKwDBAQAAAA==.',
Jt='Jtizlfrizl:BAAANQAECgQICwAAAA==.',
Ju='Juniperz:BAAANQAECgUIDAAAAA==.',
Jw='Jwise:BAAANQADCgQIBAAAAA==.',
Ka='Kaaydenn:BAAANQAECgQIDgAAAA==.Kaghro:BAAANQADCgcIBwAAAA==.Kalaziel:BAAANQAECgYIBgAAAA==.Kalierix:BAAANQAECgYICAAAAA==.Kamus:BAAANQADCgcIDAAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICAAPAAAAAA==.Katrichi:BAAANQAECgEIAQAAAA==.Katrishy:BAACNQAFFIEFAAIZAAIKIxeKDgCmAAAZAAIKIxeKDgCmAAA1AAQKgSUAAhkACQpkHsgPAOACABkACQpkHsgPAOACAAAA.Kayde:BAAANQAECgQIBAAAAA==.',
Ke='Keedrid:BAAANQAECgYIDgAAAA==.Kelaeno:BAAANQAECgYIEAAAAA==.Kev:BAACNQAFFIEIAAIHAAMKBBfZEgDxAAAHAAMKBBfZEgDxAAA1AAQKgSMAAgcACQqqJHUDALMDAAcACQqqJHUDALMDAAAA.',
Ki='Kirima:BAAANQADCggICAAAAA==.Kirmit:BAAANQAECgMIAwAAAA==.',
Kn='Knoll:BAAANQAECgIIAgAAAA==.',
Kr='Kreeona:BAAANQAECgYIEAABNQAECgcIGgAIANwQAA==.Kruàlty:BAABNQAECoEdAAMfAAgKFhfnCgBOAgAfAAgKFhfnCgBOAgABAAMK9QoqhACRAAAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQADCgYJDQAAAA==.',
Li='Liare:BAACNQAFFIEQAAQcAAYK7R/5AgCxAAAaAAIKQSTlHgDSAAAbAAIKsSBVBwC0AAAcAAIK1Rr5AgCxAAA1AAQKgSsABBoACQqjJacGAIoDABoACQrwJKcGAIoDABsABgrKG1MVALsBABwAAgopJmwUANcAAAAA.Liasong:BAAANQADCgUJDgAAAA==.Litheliice:BAABNQAECoEbAAIgAAcKSRcvWgDjAQAgAAcKSRcvWgDjAQAAAA==.',
Lo='Lodur:BAAANQAECgUICwAAAA==.Lonen:BAAANQAECgMIBgAAAA==.Losat:BAAANQAECgYIEAAAAA==.',
Lu='Lukeluke:BAAANQADCgQIBAAAAA==.',
['Lî']='Lîîght:BAAANQADCggIHgAAAA==.',
Ma='Machiato:BAAANQADCgYJCAAAAA==.Mackkie:BAAANQAECgUIEgAAAA==.Madonkadonk:BAAANQAECgYIEwAAAA==.Maedai:BAAANQAECgUIDgAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAAANQAECgYIDQAAAA==.Maligasia:BAAANQADCgIJAwAAAA==.Mallicia:BAABNQAECoEkAAIgAAgKKCI3GQD5AgAgAAgKKCI3GQD5AgAAAA==.Mallika:BAAANQAECgEIAQABNQAECggIJAAgACgiAA==.Mallistra:BAAANQAECgYIEgABNQAECggIJAAgACgiAA==.Mallwizard:BAAANQAECgUJCgAAAA==.Martris:BAAANQAECgQIBwAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Mashma:BAAANQADCggICAAAAA==.Massoflice:BAAANQAECgYIDwAAAA==.Maxblaide:BAAANQADCggIGAAAAA==.Maxentia:BAAANQADCgYIBgAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAcIFgAOAHcZAA==.Milah:BAAANQABCgIIAgAAAA==.Missile:BAAANQAECgMIAwAAAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAAANQAECgYIEgAAAA==.Monikal:BAAANQAECgIIAgAAAA==.',
Mu='Musashi:BAABNQAECoEmAAISAAgK3yQCFwAnAwASAAgK3yQCFwAnAwABNQAECgkJGwASAFUmAA==.Muskeg:BAABNQAECoEaAAIRAAcK3BA9VwB0AQARAAcK3BA9VwB0AQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQABCggIFAAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAAANQAECgQICgAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAABNQAECoEcAAICAAgK5hjwgABkAgACAAgK5hjwgABkAgAAAA==.',
Ni='Nightstew:BAAANQADCgcICgAAAA==.Nikra:BAAANQADCgYIBgAAAA==.Nishal:BAAANQADCggIGwAAAA==.',
Ny='Nyxaries:BAAANQAECgIIAgAAAA==.',
['Né']='Néwby:BAABNQAECoEhAAIhAAgKux8MCADMAgAhAAgKux8MCADMAgAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAcIFwANAN4eAA==.',
Pa='Pablo:BAAANQAECggIEAAAAA==.Patriot:BAAANQADCgUICAAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgUIBAAAAA==.',
Ph='Phane:BAAANQAECgQIBwAAAA==.',
Po='Pocketheals:BAAANQAECgMIAwAAAA==.',
Pu='Puffer:BAAANQAECgQICQAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQADCgYIBgAAAA==.Raito:BAAANQAECgQIBgAAAA==.Rakshasa:BAABNQAECoEnAAMaAAkKySDmDABTAwAaAAkKySDmDABTAwAbAAMK3w8sQwCtAAAAAA==.Rano:BAAANQAECgEIAQAAAA==.Rasetsungo:BAAANQAECgYIEAAAAA==.Raura:BAAANQADCgYJDQAAAA==.Rayala:BAAANQAECggIAQAAAA==.',
Re='Redblueblurr:BAAANQAECgUICAAAAA==.Remi:BAAANQAECgYIEQAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.',
Ri='Rise:BAAANQAECgcIBwAAAA==.',
Ro='Rolan:BAABNQAECoElAAQXAAgKyCUdGgDVAgAXAAgKLyQdGgDVAgAYAAYKESUsHwBpAgARAAQKVCRMUgCKAQAAAA==.Rosalian:BAAANQAECgUIDAAAAA==.Rotiko:BAAANQAECgYIDgAAAA==.Roweene:BAABNQAECoEZAAIiAAYKbQN+EQDdAAAiAAYKbQN+EQDdAAAAAA==.',
['Rá']='Rágnar:BAAANQAECgQIEAAAAA==.',
Sa='Sabiel:BAAANQAECgQICwAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJHwALAOcdAA==.',
Se='Serenatee:BAAANQAECgYIEgAAAA==.',
Sh='Shaedai:BAAANQAECgYIBwAAAA==.Shagohod:BAAANQADCgQIBAAAAA==.Shakked:BAAANQAECgEIAgAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEgAAAA==.',
So='Solphera:BAAANQADCgQICAAAAA==.Sonknight:BAAANQADCggIKgAAAA==.',
Sp='Speedshot:BAAANQADCgUIBgAAAA==.Spitefulcrow:BAABNQAECoEZAAIjAAgKqwlWBwDVAQAjAAgKqwlWBwDVAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Stealsoul:BAAANQADCgQIBAABNQADCgQIBAAPAAAAAA==.Sto:BAAANQAECgEIAgAAAA==.Stratof:BAAANQADCgcIBwAAAA==.',
Su='Sufferding:BAAANQAECggIEwAAAA==.Suria:BAAANQAECgYIEgAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAAANQAECgUICAAAAA==.Taytorchips:BAAANQAECgYIEAAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQIBwAAAA==.Thedoc:BAAANQAECgUICQAAAA==.Theefjeef:BAAANQAECgQIBQABNQAECggIBQAPAAAAAA==.Thorloim:BAABNQAECoEZAAILAAYKCiBHUAD3AQALAAYKCiBHUAD3AQAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Throwaway:BAAANQAECgYIBgAAAA==.Thundercups:BAAANQAECgYIEgAAAA==.',
Ti='Tigerstarr:BAABNQAECoEWAAMYAAkK7g9TLgD3AQAYAAkK7g9TLgD3AQAXAAQKZAphlQC0AAAAAA==.Tinyshieva:BAAANQADCgQIBAAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAECgkJMgAKAN8gAA==.',
Tr='Treborlock:BAAANQAECgYIDwAAAA==.Triplock:BAAANQAECgEJAQAAAA==.Trolcain:BAABNQAECoEYAAIXAAkKTxtsKgBsAgAXAAkKTxtsKgBsAgAAAA==.',
Tw='Twistedspork:BAAANQADCggIGQAAAA==.',
Un='Unbuffed:BAAANQADCgIIAgABNQAECgYIEQAPAAAAAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQIDwAAAA==.Valha:BAAANQAECgYIEQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varlashard:BAAANQADCgEIAQAAAA==.Varteras:BAABNQAECoEaAAMcAAcKLRadBwD7AQAcAAcKFxWdBwD7AQAaAAUKoAkf1QDyAAAAAA==.',
Ve='Vellron:BAAANQAECgYIEgAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Vø']='Vødøu:BAAANQAECgYIEAAAAA==.',
Wa='Wafflelegend:BAABNQAECoEjAAIVAAgKCiSgCgBJAwAVAAgKCiSgCgBJAwAAAA==.Wardkbriggle:BAABNQAECoEXAAMYAAkKGxyvKQAYAgAYAAkKgBmvKQAYAgAXAAgK6xgnTAC8AQAAAA==.Warint:BAAANQAECgQIBgAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAAANQAECgYIEAAAAA==.',
Wo='Wolfdude:BAAANQAECggICQAAAA==.',
Wy='Wydge:BAABNQAECoEYAAICAAYKxg5F/ABuAQACAAYKxg5F/ABuAQAAAA==.Wyven:BAABNQAECoEhAAIXAAgK+SNmFAD/AgAXAAgK+SNmFAD/AgABNQADCgcICgAPAAAAAA==.',
Xa='Xanddoria:BAAANQAECgYIEQAAAA==.Xaoc:BAAANQAECgYIDwAAAA==.',
Xh='Xhared:BAABNQAECoEcAAIRAAYKch9zMgAmAgARAAYKch9zMgAmAgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Ze='Zephy:BAAANQAECgQICwAAAA==.',
['Åe']='Åeon:BAAANQAECgQIBQAAAA==.',
['Ðr']='Ðráco:BAAANQADCgYIBgAAAA==.',
['ßu']='ßullzeye:BAAANQADCgcIBwAAAA==.',
['Ÿu']='Ÿunalessca:BAAANQAECgYICwAAAA==.',
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
