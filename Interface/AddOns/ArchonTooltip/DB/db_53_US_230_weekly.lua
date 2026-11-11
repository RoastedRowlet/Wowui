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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Paladin-Protection','Unknown-Unknown','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Paladin-Retribution','Hunter-BeastMastery','Monk-Windwalker','Warrior-Arms','Druid-Feral','Warlock-Affliction','Druid-Restoration','Shaman-Restoration','DeathKnight-Blood','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','Priest-Holy','Priest-Shadow','Mage-Fire','Monk-Mistweaver','Druid-Balance','Priest-Discipline','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','Warrior-Protection',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abaddon:BAABNQAECn8bAAMBAAYKyiP/OgA2AgABAAYKyiP/OgA2AgACAAUKIxXqWQBCAQAAAA==.',
Ac='Ackris:BAABNQAECn9ZAAMDAAoKHyXsBABJAwADAAoKHyXsBABJAwAEAAEKmRDUdwA2AAAAAA==.',
Ag='Agolan:BAABNQAECn8ZAAIFAAkK+xAXTQCMAQAFAAkK+xAXTQCMAQAAAA==.',
Al='Aldric:BAEANQAECgcIDQABNQAFFAgIFwAGABsbAA==.Alkaios:BAAANQAECgQIBgABNQAECgkJOAAGADgZAA==.Alucarddalv:BAAANQAECgQICgAAAA==.Alynthea:BAEANQADCggIEAABNQAECgMIBgAHAAAAAA==.',
Am='Amaimon:BAAANQAECggIDgABNQAFFAYIEAAFAFcOAA==.Amalthaea:BAAANQAECgIIAwABNQAECgoKNAAIAMYWAA==.Amnoon:BAABNQAECn80AAIIAAoKxhaGOwAXAgAIAAoKxhaGOwAXAgAAAA==.Amri:BAABNQAECn8iAAMJAAgKXBkLEADvAQAJAAgKXBkLEADvAQAKAAMKmQ70GwCIAAABNQAECgoKSgALADwcAA==.',
An='Andarnáurram:BAAANQAECgYICAABNQAECgoKFgAMABENAA==.Angelfox:BAAANQAECgQIBAABNQAECggIKAANAGQJAA==.Angron:BAAANQAECgEIAQAAAA==.Annor:BAEANQADCgYIBgABNQAECgMIBgAHAAAAAA==.',
Ap='Apoly:BAAANQADCgUIBQAAAA==.',
Aq='Aquas:BAAANQADCgEIAQAAAA==.',
Ar='Ardrhys:BAAANQAECgMIBAABNQAECgoKIgAOAB4UAA==.Arknem:BAAANQABCgQIBQAAAA==.Artikin:BAAANQAFFAEIAQABNQAFFAYICQAPAM4LAA==.',
As='Assasinateu:BAAANQADCgIIAgAAAA==.Asûná:BAABNQAECn8pAAIQAAoKgBdBEQCSAQAQAAoKgBdBEQCSAQAAAA==.',
At='Atlas:BAABNQAECn8yAAQEAAoKSyD8BwA8AQADAAgK/R0qWwCvAQAEAAYKxh78BwA8AQARAAIKbhEGKABBAAAAAA==.',
Au='Auroxa:BAABNQAECn8mAAQRAAcKiRjaCQDgAQARAAYKkBraCQDgAQADAAMKMBLgCwG0AAAEAAIKvAuYIQBmAAAAAA==.Automagic:BAAANQAECgIIBQAAAA==.',
Av='Avondwella:BAABNQAECn86AAIPAAoKxxooMgBpAgAPAAoKxxooMgBpAgAAAA==.',
Az='Azorah:BAAANQADCggIEQAAAA==.',
Ba='Bacevicius:BAAANQAECggIDQAAAA==.Baku:BAAANQAECgQIBAABNQAFFAYICQAPAM4LAA==.Baldyguy:BAAANQAECgQIDAAAAA==.Balm:BAABNQAECn8fAAISAAkK2Q73JgCbAQASAAkK2Q73JgCbAQAAAA==.',
Be='Beastlybull:BAAANQAECgcIDgABNQAFFAkJHQATAPUaAA==.Behindyou:BAAANQAECggIEAABNQAECgoKLwAMACkLAA==.',
Bi='Biblepimp:BAABNQAECn8cAAMIAAoKAxLDYAD2AQAIAAoKAxLDYAD2AQAMAAcKchSIzwB8AQAAAA==.Bigfries:BAAANQAECgEIAQAAAA==.Bigsneak:BAAANQAECgIJBgAAAA==.Birdlaw:BAAANQAECgMIAwAAAA==.',
Bl='Blackmarker:BAABNQAECn8fAAMCAAoKYBUWMADUAQACAAkKGA4WMADUAQABAAgK5haPVgC3AQAAAA==.Blemish:BAAANQADCgEIAQABNQAECgkJHwASANkOAA==.Bloodpac:BAAANQADCgEIAQAAAA==.',
Bo='Boadica:BAAANQADCgIIAgAAAA==.Bobsuruncle:BAAANQAECgIICwAAAA==.Bodyguardwyn:BAAANQAECgIIBQAAAA==.Bolvar:BAABNQAECn80AAIMAAoKYxWGdQBCAgAMAAoKYxWGdQBCAgAAAA==.Bonedjovi:BAABNQAECn8pAAIUAAgKZA8KSAAPAQAUAAgKZA8KSAAPAQABNQAECgoKNAAIAMYWAA==.Bonedmuch:BAAANQAECgIIBAABNQAECgoKNAAIAMYWAA==.Boondiggles:BAAANQAECgUIDAAAAA==.',
Br='Brathelore:BAAANQADCggICgAAAA==.Bremitox:BAAANQAECgMIAwABNQAECgkJOAAGADgZAA==.Brimscythe:BAAANQADCgIIAQAAAA==.Brud:BAAANQAECgUIEwAAAA==.',
By='Byakugan:BAACNQAFFH8QAAIFAAYKVw7PDQCSAQAFAAYKVw7PDQCSAQA1AAQKfyUAAwUACgo2HC9BAHECAAUACQq8Hi9BAHECABUAAQqRCoA0AD8AAAAA.',
['Bø']='Bønitalèè:BAAANQAECgcIDQAAAA==.',
Ca='Cain:BAAANQADCgYICQAAAA==.Calvisi:BAAANQAECgUICAAAAA==.Calvisichaos:BAABNQAECn8eAAIEAAgKeAoVHgB+AQAEAAgKeAoVHgB+AQAAAA==.Canthen:BAAANQAECggIAwAAAA==.',
Cc='Cc:BAABNQAECn8jAAMUAAgKGQbYagCWAAACAAgKbwVAgwChAAAUAAcKdQXYagCWAAAAAA==.',
Ch='Chaoticbacon:BAAANQADCgYIBgABNQAECgEIBQAHAAAAAA==.',
Co='Conky:BAAANQAECgcIEgAAAA==.Cosmicsage:BAAANQAECggIDQAAAA==.Cosmicspark:BAABNQAECn87AAIMAAoKhAsSmwCBAQAMAAoKhAsSmwCBAQAAAA==.',
Cr='Crentist:BAAANQAFFAIIAgAAAA==.Crohunter:BAAANQAECgUIBQABNQAECgoKLwAMACkLAA==.Cropala:BAABNQAECn8vAAIMAAoKKQvriAClAQAMAAoKKQvriAClAQAAAA==.',
Cy='Cynle:BAEANQAECgMIBgAAAA==.',
Da='Darkraider:BAAANQAECggIDQAAAA==.Darkwingduck:BAAANQAECgQIBAABNQAECgoKIgAOAB4UAA==.Darkøne:BAAANQABCgMIAwAAAA==.Davros:BAAANQAECgUIBQAAAA==.',
De='Dellandre:BAABNQAECn8WAAIUAAYK5Q52ggDyAAAUAAYK5Q52ggDyAAABNQAECggIKQAGAEMQAA==.Delta:BAABNQAECn8iAAIWAAkKJhHqNgBUAQAWAAkKJhHqNgBUAQAAAA==.Delti:BAAANQADCggICAABNQAECggILQAXAJIaAA==.Destrõ:BAAANQAECgIIAwAAAA==.',
Di='Diabolist:BAABNQAECn8vAAIDAAoK6g4aTQDaAQADAAoK6g4aTQDaAQAAAA==.Dielma:BAAANQAECgUICQABNQAFFAUICAAEAL8VAA==.Dirtygiri:BAABNQAECn8WAAIMAAoKEQ1FfQC+AQAMAAoKEQ1FfQC+AQAAAA==.',
Dk='Dkdozer:BAAANQAECgUICQAAAA==.',
Do='Doktaga:BAABNQAECn8eAAIDAAcKbxLCdABoAQADAAcKbxLCdABoAQAAAA==.',
Dr='Draetanìa:BAAANQADCgYIDAAAAA==.Drakonna:BAAANQADCgUIBQAAAA==.Drarken:BAACNQAFFH8JAAIJAAMKDRMjDgDfAAAJAAMKDRMjDgDfAAA1AAQKfyUAAgkACQrtGUUUAGoCAAkACQrtGUUUAGoCAAAA.Dropshot:BAAANQADCgYIBgAAAA==.Drtapo:BAAANQAECgIIBQAAAA==.Drustdar:BAAANQADCgEIAQAAAA==.',
Du='Durendin:BAAANQAECgUIBQABNQAFFAYICQAPAM4LAA==.',
El='Elderr:BAAANQAECgcIEwABNQAECgkJHgAOAFMXAA==.Eldhe:BAAANQADCgQIBgAAAA==.Elistrae:BAABNQAECn8jAAINAAkKrSHmKQDxAgANAAkKrSHmKQDxAgAAAA==.',
En='Enazen:BAAANQAECggIEgAAAA==.Endlol:BAAANQAECgcICQABNQAECgkJLQAIADwUAA==.',
Er='Ereshkigal:BAAANQADCgYICQAAAA==.Ergo:BAACNQAFFH8aAAMYAAgKugo7IQB+AQAYAAYKwQk7IQB+AQAZAAMKQwxTCACXAAA1AAQKfzsAAxgACgrQHm1DADUCABgACgrQHm1DADUCABkAAgr+HPAiALAAAAAA.',
Ev='Evelake:BAAANQAECgUIEAAAAA==.',
Ex='Exodiagold:BAAANQADCggICAAAAA==.Exon:BAAANQAECgYIDQAAAA==.',
Fa='Faded:BAAANQAECgEIAQABNQAECgkJKAABAG0MAA==.Fadednight:BAABNQAECn8oAAMBAAkKbQwMKwB5AQABAAkKbQwMKwB5AQACAAEKpwQ0uAAeAAAAAA==.Fallingmoon:BAAANQAECgEIAQAAAA==.',
Fe='Femcel:BAABNQAECn8XAAMaAAgKuhllOwB8AgAaAAgKuhllOwB8AgAbAAIKbhRhYACAAAAAAA==.Femcelibate:BAAANQAECgQIBwAAAA==.',
Fi='Fivebones:BAAANQAECgMIAwABNQAECgoKUgANAHAjAA==.',
Fl='Flacidheals:BAAANQAECgEIAQAAAA==.',
Fr='Freecookies:BAAANQAECgUIBgAAAA==.Frostytotems:BAAANQADCgQIBwAAAA==.Fróstblight:BAAANQAECggIAQAAAA==.',
Fu='Furryiosa:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAABNQAECn8pAAQZAAkKWhMbDwCCAQAZAAgKJRQbDwCCAQAYAAcKVgzoOAEuAQAcAAMKzw0iDAA3AAAAAA==.',
Ge='Gerbert:BAAANQABCgIIAgAAAA==.',
Gh='Ghostë:BAABNQAECn8eAAIdAAoKzAu+HgCfAQAdAAoKzAu+HgCfAQAAAA==.',
Gi='Gishmou:BAABNQAECn8pAAITAAcKzx4GRwBGAgATAAcKzx4GRwBGAgAAAA==.',
Go='Gogreenrangr:BAAANQAECgcICgABNQAECgoKFgAMABENAA==.Goodlight:BAAANQAECgEIAQAAAA==.',
Gu='Guerrero:BAAANQAECgMIAwAAAA==.Gutted:BAACNQAFFH8aAAIUAAgK0CXEAQCfAgAUAAgK0CXEAQCfAgA1AAQKfzMAAxQACgqsJm0CAMwDABQACgqsJm0CAMwDAAEAAQriD5p7AD8AAAAA.',
Ha='Hanna:BAABNQAECn8VAAQLAAkKuiMXBwAYAwALAAgK1SQXBwAYAwAeAAcKAhaNKQCdAQASAAQK1BpDNAA3AQABNQAFFAgIGgAUANAlAA==.',
He='Hellmaw:BAAANQAECgUICAAAAA==.',
Hi='Highly:BAAANQAECgQIBAAAAA==.',
Ho='Hollowheart:BAABNQAECn8XAAITAAkKTh82HgC0AgATAAkKTh82HgC0AgAAAA==.Holycourtney:BAAANQADCgQIBAAAAA==.Holyfur:BAABNQAECn8wAAMaAAkKpREeRgAKAgAaAAkKpREeRgAKAgAfAAEKixHLKAAzAAAAAA==.',
Hy='Hylanna:BAAANQAECgUICgAAAA==.',
Ic='Ici:BAABNQAECn8rAAMMAAkK0ghNpQBtAQAMAAkK0ghNpQBtAQAIAAEKHwJSNgEhAAAAAA==.',
Id='Idobutidont:BAAANQADCgIIAgAAAA==.',
If='Iffybacon:BAAANQAECgEIAwABNQAECgEIBQAHAAAAAA==.',
Im='Imlerith:BAAANQAECgEIAQAAAA==.',
In='Intensifies:BAABNQAECn8nAAIFAAcKYhM7dQDCAQAFAAcKYhM7dQDCAQAAAA==.',
Is='Iskothar:BAABNQAECn8yAAIGAAgKcRddHAB3AQAGAAgKcRddHAB3AQAAAA==.',
Iv='Ivarboneless:BAABNQAECn8dAAIIAAoKBRiDTQA0AgAIAAoKBRiDTQA0AgAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jackz:BAAANQADCggIEgAAAA==.Jackzdk:BAAANQADCggIAgAAAA==.Jackzlock:BAAANQAECgUICQAAAA==.Jak:BAACNQAFFH8KAAMNAAQKbA4PGgDrAAANAAMK2hMPGgDrAAAgAAMKLwMIIABxAAA1AAQKfy4AAw0ACgr8HREuAOMCAA0ACgr8HREuAOMCACAABgrRCglGACoBAAAA.Jambii:BAABNQAECn8aAAINAAYKhhZ7qAC0AQANAAYKhhZ7qAC0AQAAAA==.Jattsz:BAEANQADCggICAAAAA==.Jayreezy:BAAANQAECgYICAAAAA==.',
Je='Jerawokee:BAACNQAFFH8GAAMZAAMKzhQQDgBUAAAYAAIKSAnbOQB6AAAZAAIKQRgQDgBUAAA1AAQKfyYAAxkABwo7IeEMAKwBABgABwrZHY+1ABgCABkABwqgHuEMAKwBAAAA.',
Ji='Jirachii:BAAANQAECgYIDQABNQAFFAMICAAeACENAA==.',
Jo='Jonah:BAABNQAECn8iAAIEAAoKnRtrBADlAgAEAAoKnRtrBADlAgAAAA==.Joshcalcjr:BAACNQAFFH8HAAIeAAYKQQMqEwA4AQAeAAYKQQMqEwA4AQA1AAQKfykABB4ACgpmGKUeAPcBAB4ACgpmGKUeAPcBAAsABgr5DWguACcBABIAAwqrC0puAEwAAAAA.',
Ka='Kaelthàs:BAAANQADCgcIBwAAAA==.Kaessatha:BAEANQADCgIIAgABNQAECgMIBgAHAAAAAA==.Kalika:BAAANQADCgIIAgAAAA==.Karhael:BAAANQAECgEIAQAAAA==.',
Ke='Ketesh:BAABNQAECn9KAAMLAAoKPBygCwBwAgALAAkKPBygCwBwAgAQAAEKAAA0PABIAAAAAA==.Kezanplague:BAABNQAECn81AAMhAAoKbRs3BACqAgAhAAkKmxk3BACqAgANAAkKHBo+ZQBKAgAAAA==.Kezansdoom:BAAANQAECgcIDwAAAA==.',
Ko='Kodeack:BAAANQADCgIIAgAAAA==.Kortona:BAAANQAECgIIBAAAAA==.',
Kr='Krej:BAAANQAFFAEIAQABNQAFFAYICQAPAM4LAA==.',
['Kø']='Købioshi:BAAANQADCggICwAAAA==.',
La='Landrey:BAAANQADCggIIAAAAA==.Laoghaire:BAAANQADCggIGAAAAA==.Laszarei:BAABNQAECn8sAAIFAAkKHQdlYQBLAQAFAAkKHQdlYQBLAQAAAA==.',
Le='Leonz:BAACNQAFFH8bAAIiAAgKpxlCAAA5AgAiAAgKpxlCAAA5AgA1AAQKf1EAAiIACgoLJn8AANgDACIACgoLJn8AANgDAAAA.Lethadestro:BAEANQAECgQIBQABNQAECgYIGgACAC4ZAA==.Letharanos:BAEBNQAECn8aAAMCAAYKLhn+SQCTAQACAAYKLhn+SQCTAQAUAAQK1whknwCaAAAAAA==.',
Li='Linastina:BAAANQAECgUIBQABNQAECgoKIwAGAMUVAA==.Liraffemynn:BAAANQAECgYICwAAAA==.',
Lo='Lohfall:BAAANQADCgUIBgABNQAECgoKPAABAHwaAA==.Lolend:BAABNQAECn8aAAMLAAkKqh+EBgDdAgALAAkKqh+EBgDdAgAQAAQKSgrsKQCeAAAAAA==.Lonranir:BAAANQADCggIEQAAAA==.',
Lu='Luckylucy:BAAANQADCgUIBgAAAA==.Lunoria:BAABNQAECn8kAAIDAAoKcSQRBwCVAwADAAoKcSQRBwCVAwAAAA==.',
Ma='Madarauchiha:BAABNQAECn8eAAMCAAoKGRydEgD5AgACAAoKChydEgD5AgABAAUK5xbrdwA6AQAAAA==.Madeirà:BAAANQADCgQJBAAAAA==.Magus:BAAANQAECgQIBAABNQAECgUIBQAHAAAAAA==.Maldran:BAABNQAECn8ZAAITAAgKWRGhZABxAQATAAgKWRGhZABxAQAAAA==.Manderpants:BAAANQADCgQIBAAAAA==.Marien:BAABNQAECn8XAAIUAAkKcRXVPgAFAgAUAAkKcRXVPgAFAgAAAA==.Mavo:BAABNQAFFH8GAAIFAAYKLx7hBQCEAQAFAAYKLx7hBQCEAQAAAA==.Maxus:BAABNQAECn8VAAMMAAoK6wgmzwAjAQAMAAkKAAcmzwAjAQAIAAIKOQWl3QBMAAAAAA==.',
Mb='Mbbin:BAABNQAECn9OAAMYAAoKuiWvAwBmAwAYAAoKuiWvAwBmAwAZAAIKaRTINgBhAAAAAA==.',
Me='Meems:BAAANQAECgEIAgAAAA==.Mehuman:BAABNQAECn8eAAIMAAkKJhWNpgDTAQAMAAkKJhWNpgDTAQAAAA==.Mehumanhuntr:BAAANQAECgIIAgAAAA==.Mehumanlock:BAABNQAECn82AAIEAAkKwRUQAwAHAgAEAAkKwRUQAwAHAgAAAA==.Melgibson:BAABNQAECn8WAAIGAAkKihoAFwBEAgAGAAkKihoAFwBEAgAAAA==.Meworgendk:BAAANQADCgcICQAAAA==.',
Mf='Mfbeòtch:BAAANQABCgUIBQAAAA==.',
Mi='Miranueta:BAAANQAECgIIAgAAAA==.Miräj:BAAANQAECgMJBAAAAA==.Mistyblue:BAAANQAECgEIBAAAAA==.Miya:BAAANQAECgEIAQAAAA==.',
Mo='Mojomugambe:BAAANQAECgcIEAAAAA==.Moodacritz:BAAANQADCgYIBgAAAA==.Moonscale:BAAANQAECgUIBgAAAA==.Morel:BAAANQADCgQIBAAAAA==.Mortstan:BAACNQAFFH8IAAIUAAMKDhjeEQDSAAAUAAMKDhjeEQDSAAA1AAQKfz0AAhQACgr3ITwHAIYDABQACgr3ITwHAIYDAAAA.',
Mu='Mutegen:BAAANQADCgYIBgAAAA==.',
Na='Nailz:BAABNQAECn8tAAMXAAgKkhpFDwA7AQAjAAgKkhmQJwAIAgAXAAcKYBhFDwA7AQAAAA==.',
Ne='Neloangelo:BAABNQAECn8XAAMBAAcKHAhmRQDjAAABAAcKVQZmRQDjAAAUAAIKnAg9wABIAAAAAA==.',
Ni='Nightflame:BAAANQADCgYIBgAAAA==.Nightlion:BAABNQAECn8lAAMLAAoK3RjqEwAlAgALAAkKwBnqEwAlAgAQAAkKFgxGFABnAQAAAA==.',
No='Noahpal:BAAANQAECgUIBgABNQAECgUICgAHAAAAAA==.Noahshaman:BAACNQAFFH8YAAIFAAgKShYABwAKAgAFAAgKShYABwAKAgA1AAQKf08AAwUACgoSJN4GAEADAAUACgoSJN4GAEADABMACAojIIEjANkCAAE1AAQKBQgKAAcAAAAA.Noahwarlock:BAAANQAECgUICgAAAA==.Nonsensical:BAAANQADCgQIBQABNQADCgcIGwAHAAAAAA==.Notbacon:BAAANQAECgEIAQABNQAECgEIBQAHAAAAAA==.Noxander:BAAANQADCgMJAwAAAA==.',
Nu='Nuanakk:BAAANQAECggIAQAAAA==.',
Oa='Oaths:BAABNQAECn8WAAQMAAcKQwqcQgG2AAAMAAYKIwOcQgG2AAAIAAUKuwKGwQCDAAAGAAQK5gUnVQBNAAAAAA==.',
Oh='Ohmylanta:BAAANQAECgUICAAAAA==.Ohmylänta:BAACNQAFFH8HAAINAAIK7wPLJAB2AAANAAIK7wPLJAB2AAA1AAQKfy8AAw0ACQqeGJpFAJsCAA0ACQqeGJpFAJsCACEAAQqpAJ0VABQAAAAA.',
Or='Orandrok:BAAANQAECgIIAgAAAA==.Ormond:BAABNQAECn8YAAMIAAgKTxxVNgAwAgAIAAgKTxxVNgAwAgAMAAYKvwMaEgG5AAAAAA==.',
['Oâ']='Oâth:BAABNQAECn8iAAMXAAoKwQtFFgBIAQAXAAoKwQtFFgBIAQAjAAIKUgLpdQAiAAAAAA==.',
Pa='Paldozer:BAAANQAECgEIAQABNQAECgUICQAHAAAAAA==.Paleo:BAAANQAECgEIAQAAAA==.Pallyman:BAAANQADCgUIBQAAAA==.Pallywacker:BAABNQAECn8pAAIGAAYKDRekKwCAAQAGAAYKDRekKwCAAQAAAA==.Panzerkìn:BAAANQAECgEIAQAAAA==.',
Pe='Peythilly:BAAANQADCggJDAAAAA==.',
Pi='Pigishdog:BAABNQAECn9LAAIDAAoKrRkhNwAkAgADAAoKrRkhNwAkAgAAAA==.',
Po='Poob:BAAANQADCgcJEwAAAA==.',
Qu='Quinn:BAABNQAECn8dAAMeAAcKuQhBTwDPAAAeAAcKuQhBTwDPAAAQAAEK5wNuTAAgAAAAAA==.',
Ra='Raedon:BAAANQADCgQIBAAAAA==.Ragerunner:BAAANQADCgQIBAAAAA==.',
Re='Redthing:BAAANQADCgYICwAAAA==.Retributíon:BAAANQAECgUICQABNQAECgoKVAAWAKIlAA==.',
Ri='Rixas:BAABNQAECn8wAAIMAAoKMCHsIABAAwAMAAoKMCHsIABAAwABNQAECgoKWQADAB8lAA==.Rixis:BAAANQADCgQIBAAAAA==.',
Ro='Rockafella:BAAANQADCgYICgAAAA==.Rodeo:BAAANQAECgIIAgAAAA==.Roguehiro:BAABNQAECn8oAAIGAAoKnB9TBwDKAgAGAAoKnB9TBwDKAgAAAA==.Rooter:BAACNQAFFH8cAAIJAAgKRhkCAwBuAgAJAAgKRhkCAwBuAgA1AAQKf0IAAwkACgo9JHYDAIADAAkACgo9JHYDAIADACQAAwqVE8IVAMgAAAAA.Rozetta:BAAANQADCgQIBAAAAA==.',
Ru='Ruto:BAAANQADCgIIAgAAAA==.',
Sa='Saelis:BAAANQAECgIIAgABNQAFFAMICQAJAA0TAA==.Samshara:BAAANQAECgYICwABNQAECgoKOgANAAQcAA==.Saptapper:BAAANQAECgUIDgABNQAECgoKFgAMABENAA==.',
Sc='Scrawni:BAABNQAECn8pAAILAAoKuh2OCwCyAgALAAoKuh2OCwCyAgABNQAFFAYICQAPAM4LAA==.',
Se='Selyane:BAAANQAECgEIBAAAAA==.Seongpal:BAECNQAFFH8XAAIGAAgKGxsHAQCHAgAGAAgKGxsHAQCHAgA1AAQKfzMAAgYACgoWI3sDAIkDAAYACgoWI3sDAIkDAAAA.Seraphinà:BAAANQAECgEIAgABNQAECgkJHwALAOUMAA==.Serbingium:BAAANQAECgEIAwABNQAFFAUICAAEAL8VAA==.',
Sh='Shadowfur:BAAANQADCgIIAgABNQAECgkJMAAaAKURAA==.Shadowlight:BAAANQAECgIJAgABNQAECgIJBgAHAAAAAA==.Shamany:BAAANQAECggICwAAAA==.Shamygravy:BAAANQAECgIIAgAAAA==.Shamynna:BAAANQADCgIIAgAAAA==.Sharreth:BAAANQAECgEIAQAAAA==.Shimera:BAABNQAECn8oAAINAAgKZAk1sACkAQANAAgKZAk1sACkAQAAAA==.Shodam:BAAANQAECgIIAgAAAA==.Shootrmcgavn:BAACNQAFFH8OAAMNAAYK3xkrDAAaAQANAAYKjhIrDAAaAQAgAAMKwxcgFQDtAAA1AAQKf0kAAyAACgpfJX0FAHkDACAACgo4JH0FAHkDAA0ACgrvIx0fABsDAAAA.',
Si='Sidenan:BAAANQADCgUIBQAAAA==.Sittingmoose:BAAANQAECgYICwAAAA==.',
Sk='Sklormp:BAACNQAFFH8IAAMEAAUKvxVDDQCdAAAEAAIKrBFDDQCdAAADAAQKcRa0LgCcAAA1AAQKfykABAMACgqVIXQwAMUCAAMACgqVIXQwAMUCAAQAAwpdGy01AO4AABEAAwr1DxchAHAAAAAA.Skrungus:BAAANQADCgEIAQAAAA==.Skubasteve:BAAANQAECgEIBAAAAA==.',
Sl='Slootar:BAAANQAECgEIAQABNQAECgYIGgANAIYWAA==.Slugs:BAAANQAECgEIAQAAAA==.',
Sm='Smoruk:BAAANQAECgEIAQAAAA==.',
So='Somerled:BAABNQAECn86AAMNAAoKBBw6LACCAgANAAoKBBw6LACCAgAhAAEKPgtBEwA2AAAAAA==.',
Sq='Squatreign:BAABNQAECn8sAAMMAAkKrQvWogByAQAMAAkKrQvWogByAQAIAAcKyAa6oABDAQAAAA==.',
Sr='Srgtpeppers:BAAANQAECgQIBwAAAA==.',
Su='Sulyvahn:BAEANQAECggIEwABNQAFFAgIFwAGABsbAA==.Sunstrike:BAAANQADCgYIBgAAAA==.',
Sy='Sylvara:BAAANQAECgUIBQAAAA==.',
Ta='Takka:BAAANQAECgcIDgAAAA==.Talcron:BAAANQAECgEIAQAAAA==.Talkamar:BAABNQAECn8iAAIOAAoKHhSGGADXAQAOAAoKHhSGGADXAQAAAA==.Tarell:BAAANQAECgEIAQAAAA==.Taylorswift:BAABNQAECn8vAAMZAAoK+haUDQDXAQAZAAYKrByUDQDXAQAYAAkKcBKhigB/AQAAAA==.',
Te='Tehharlequin:BAAANQAECgEIAQAAAA==.',
Th='Thekourge:BAABNQAECn8pAAIGAAgKQxBILgBrAQAGAAgKQxBILgBrAQAAAA==.Thenard:BAABNQAECn8gAAINAAYK4Qv+0gBaAQANAAYK4Qv+0gBaAQAAAA==.Therealcafna:BAAANQADCgUIBwAAAA==.Thewhole:BAAANQADCgYIBgAAAA==.Thisle:BAAANQAECgEIAQAAAA==.Thukunamage:BAACNQAFFH8HAAIYAAMKwB/TLgCmAAAYAAMKwB/TLgCmAAA1AAQKf0kAAxgACgqBJdcJADIDABgACgqBJdcJADIDABwABQo8HPwDADwBAAAA.Thukunawar:BAAANQADCgIIAgABNQAFFAMIBwAYAMAfAA==.',
Ti='Tigerlord:BAAANQADCggIFQAAAA==.Tili:BAAANQADCggIJQAAAA==.',
To='Tomislav:BAABNQAECn81AAMDAAoK8RNhPgALAgADAAoKiRNhPgALAgAEAAIKcQ9nWwBvAAAAAA==.Toqur:BAAANQADCggICgAAAA==.Touritos:BAABNQAECn8pAAIFAAoKrBGkQAC7AQAFAAoKrBGkQAC7AQAAAA==.',
Tr='Trimblestein:BAABNQAECn8eAAIPAAgKEiNwSwCnAgAPAAgKEiNwSwCnAgAAAA==.Trohas:BAAANQADCggICAAAAA==.',
Tu='Tuskerdu:BAABNQAECn80AAIeAAoKhwycLgB5AQAeAAoKhwycLgB5AQAAAA==.',
Tw='Twiggyss:BAAANQAECggICgAAAA==.Twohoofy:BAAANQADCgYIDQAAAA==.',
Ud='Uddermilk:BAAANQAECgYIDwAAAA==.',
Un='Untempered:BAABNQAECn8tAAMIAAkKPBSSVACwAQAIAAkKPBSSVACwAQAMAAgK/A6jwQA6AQAAAA==.',
Va='Valandrian:BAAANQADCgYICQAAAA==.Valeka:BAABNQAECn8oAAMTAAkKThs8JwDHAgATAAkKThs8JwDHAgAFAAEKAAAWFgEAAAAAAA==.Valissar:BAAANQAECgEIAwAAAA==.Valr:BAABNQAECn84AAIGAAkKOBnTDwAXAgAGAAkKOBnTDwAXAgAAAA==.Vandreu:BAAANQAECgQIBwAAAA==.',
Vi='Viðrir:BAAANQADCgEIAQAAAA==.',
Vs='Vse:BAACNQAFFH8PAAIZAAMKjxYxAwDvAAAZAAMKjxYxAwDvAAA1AAQKf00AAhkACgq6In4BAHwDABkACgq6In4BAHwDAAAA.Vsesosorry:BAACNQAFFH8GAAIFAAMKpBXcGACZAAAFAAMKpBXcGACZAAA1AAQKfysAAgUACgpYHNwVAK8CAAUACgpYHNwVAK8CAAE1AAUUAwgPABkAjxYA.',
Vy='Vyne:BAAANQADCgIIAgABNQADCggIDQAHAAAAAA==.',
Wa='Wangateur:BAAANQAECgUIBAABNQAECgoKLwADAOoOAA==.',
We='Weierstrass:BAAANQAECggIDQABNQAFFAgIGgAUANAlAA==.Weiyan:BAAANQADCgcIBwAAAA==.',
Wi='Winklebottom:BAAANQADCgcIEwAAAA==.',
Wo='Worgenkrantz:BAABNQAECn8fAAILAAkK5Qy8JgA6AQALAAkK5Qy8JgA6AQAAAA==.Worthybacon:BAAANQAECgEIBQAAAA==.',
Wr='Wrathlor:BAAANQADCgQIBAAAAA==.Wrenlyn:BAACNQAFFH8JAAMWAAUK4gV7EgCSAAAWAAQKSQZ7EgCSAAAjAAEKRAQOFQBHAAA1AAQKfz8ABBYACgolHyoNAMQCABYACgokHyoNAMQCACMACAr8EP40AJsBABcACQqSFkcOAEwBAAE1AAUUBggJAA8AzgsA.',
Wu='Wukain:BAABNQAECn8mAAIFAAoK9wsHdwC8AQAFAAoK9wsHdwC8AQAAAA==.',
Xa='Xalatoth:BAAANQADCgYIBgAAAA==.Xanatas:BAAANQAECgQIBQABNQAECggIMgAGAHEXAA==.Xarapxeh:BAAANQAECgEIAQAAAA==.',
Xo='Xolòtl:BAACNQAFFH8JAAIPAAYKzgugHgAXAQAPAAYKzgugHgAXAQA1AAQKfzUAAw8ACgo8GTBPAJwCAA8ACgpYFzBPAJwCACUABwrZEzocAHkBAAAA.',
Xy='Xymos:BAECNQAFFH8VAAQEAAgKDhwOBQDJAAADAAUK6h2NCgDBAQAEAAMKHyEOBQDJAAARAAEK1Qx9EABUAAA1AAQKfzMAAwQACgpuJQsBAJgDAAQACQoOJQsBAJgDAAMABwqaJOxhAJwBAAAA.',
Ya='Yakul:BAABNQAECn8eAAMlAAcKVRvBFgC+AQAlAAcKVRvBFgC+AQAPAAcK9APy0AC+AAAAAA==.',
Za='Zalyia:BAAANQADCgQIBAAAAA==.',
Zd='Zdk:BAAANQADCgEIAQAAAA==.',
Ze='Zeroveth:BAABNQAECn8WAAIYAAgKmBRXywDvAQAYAAgKmBRXywDvAQAAAA==.Zexpert:BAAANQAECgIIAgABNQAECgcIJgARAIkYAA==.',
Zu='Zugg:BAAANQAECgUICQAAAA==.Zulcow:BAAANQAECggIDAAAAA==.',
['Âr']='Ârtemis:BAAANQAECgcIEgAAAA==.',
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
