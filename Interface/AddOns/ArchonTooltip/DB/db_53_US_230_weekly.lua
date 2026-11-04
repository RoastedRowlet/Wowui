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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Paladin-Protection','Unknown-Unknown','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Monk-Windwalker','Warrior-Arms','Druid-Feral','Warlock-Affliction','Druid-Restoration','Shaman-Restoration','Paladin-Retribution','DeathKnight-Blood','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Arcane','Mage-Frost','Mage-Fire','Monk-Mistweaver','Druid-Balance','Priest-Holy','Priest-Discipline','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','Warrior-Protection',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abaddon:BAABNQAECn8WAAMBAAYKyiP/OgA2AgABAAYKyiP/OgA2AgACAAUKIxXqWQBCAQAAAA==.',
Ac='Ackris:BAABNQAECn9RAAMDAAoKGSX0BAA6AwADAAoKGSX0BAA6AwAEAAEKmRDUdwA2AAAAAA==.',
Ag='Agolan:BAABNQAECn8ZAAIFAAkK+xBQQwCNAQAFAAkK+xBQQwCNAQAAAA==.',
Al='Aldric:BAEANQAECgcIDAABNQAFFAcIFQAGACAeAA==.Alkaios:BAAANQAECgQIBgABNQAECgkJNAAGAHIXAA==.Alucarddalv:BAAANQAECgQICgAAAA==.Alynthea:BAEANQADCggIEAABNQAECgMIBgAHAAAAAA==.',
Am='Amaimon:BAAANQAECggIDQABNQAFFAYIEAAFAFcOAA==.Amalthaea:BAAANQAECgIIAgABNQAECgoKMQAIAMYWAA==.Amnoon:BAABNQAECn8xAAIIAAoKxhZjMgAiAgAIAAoKxhZjMgAiAgAAAA==.Amri:BAABNQAECn8cAAMJAAgKQBaZHwDbAQAJAAgKQBaZHwDbAQAKAAMKmQ70GwCIAAABNQAECgoKQQALAJcbAA==.',
An='Andarnáurram:BAAANQAECgUIBQABNQAECggIDwAHAAAAAA==.Angron:BAAANQAECgEIAQAAAA==.Annor:BAEANQADCgYIBgABNQAECgMIBgAHAAAAAA==.',
Ap='Apoly:BAAANQADCgUIBQAAAA==.',
Aq='Aquas:BAAANQADCgEIAQAAAA==.',
Ar='Ardrhys:BAAANQAECgIIAgABNQAECgoKHgAMALYTAA==.Arknem:BAAANQABCgQIBQAAAA==.Artikin:BAAANQAFFAEIAQABNQAFFAYICQANAM4LAA==.',
As='Assasinateu:BAAANQADCgIIAgAAAA==.Asûná:BAABNQAECn8lAAIOAAkKYBjkEgDQAQAOAAkKYBjkEgDQAQAAAA==.',
At='Atlas:BAABNQAECn8sAAQEAAoKhh5MBwAyAQAEAAYKcR5MBwAyAQADAAcKTRsDfQAwAQAPAAIKbhHEIgBBAAAAAA==.',
Au='Auroxa:BAABNQAECn8mAAQPAAcKiRjaCQDgAQAPAAYKkBraCQDgAQADAAMKMBLgCwG0AAAEAAIKvAsXHgBnAAAAAA==.Automagic:BAAANQAECgIIAQAAAA==.',
Av='Avondwella:BAABNQAECn81AAINAAoKIxlWMgBOAgANAAoKIxlWMgBOAgAAAA==.',
Az='Azorah:BAAANQADCggIEQAAAA==.',
Ba='Bacevicius:BAAANQAECggIDQAAAA==.Baku:BAAANQAECgQIBAABNQAFFAYICQANAM4LAA==.Baldyguy:BAAANQAECgQICgAAAA==.Balm:BAABNQAECn8fAAIQAAkK2Q4sIgCXAQAQAAkK2Q4sIgCXAQAAAA==.',
Be='Beastlybull:BAAANQAECgcIDAABNQAFFAgIHAARADQbAA==.Behindyou:BAAANQAECggIDAABNQAECgoKLQASAKgKAA==.',
Bi='Biblepimp:BAABNQAECn8aAAMIAAoKQRHDYAD2AQAIAAoKQRHDYAD2AQASAAYKrBWIzwB8AQAAAA==.Bigfries:BAAANQAECgEIAQAAAA==.Bigsneak:BAAANQAECgIJAwAAAA==.Birdlaw:BAAANQAECgIIAgAAAA==.',
Bl='Blackmarker:BAABNQAECn8cAAMBAAkKpBX3MAA2AQABAAgK5hb3MAA2AQACAAYK7QwWTgAeAQAAAA==.Blemish:BAAANQADCgEIAQABNQAECgkJHwAQANkOAA==.Bloodpac:BAAANQADCgEIAQAAAA==.',
Bo='Boadica:BAAANQADCgIIAgAAAA==.Bobsuruncle:BAAANQAECgIIBwAAAA==.Bodyguardwyn:BAAANQAECgIIBQAAAA==.Bolvar:BAABNQAECn8rAAISAAoK1xOGdQBCAgASAAoK1xOGdQBCAgAAAA==.Bonedjovi:BAABNQAECn8oAAITAAgK/A5xQgALAQATAAgK/A5xQgALAQABNQAECgoKMQAIAMYWAA==.Bonedmuch:BAAANQAECgIIAwABNQAECgoKMQAIAMYWAA==.Boondiggles:BAAANQAECgUIDAAAAA==.',
Br='Brathelore:BAAANQADCggICgAAAA==.Bremitox:BAAANQAECgMIAwABNQAECgkJNAAGAHIXAA==.Brimscythe:BAAANQADCgIIAQAAAA==.Brud:BAAANQAECgUIEwAAAA==.',
By='Byakugan:BAACNQAFFH8QAAIFAAYKVw7PDQCSAQAFAAYKVw7PDQCSAQA1AAQKfyUAAwUACgo2HC9BAHECAAUACQq8Hi9BAHECABQAAQqRCoA0AD8AAAAA.',
['Bø']='Bønitalèè:BAAANQAECgcICQAAAA==.',
Ca='Cain:BAAANQADCgYICQAAAA==.Calvisi:BAAANQAECgUIBwAAAA==.Calvisichaos:BAABNQAECn8ZAAIEAAgKGgoVHgB+AQAEAAgKGgoVHgB+AQAAAA==.Canthen:BAAANQAECggIAgAAAA==.',
Cc='Cc:BAABNQAECn8fAAMCAAgKEAZAgwChAAACAAgKbwVAgwChAAATAAUKQwSHhABJAAAAAA==.',
Ch='Chaoticbacon:BAAANQADCgYIBgABNQAECgEIAgAHAAAAAA==.',
Co='Conky:BAAANQAECgcICwAAAA==.Cosmicsage:BAAANQAECgQIBAAAAA==.Cosmicspark:BAABNQAECn8wAAISAAkK5QpOqgA6AQASAAkK5QpOqgA6AQAAAA==.',
Cr='Crentist:BAAANQAFFAIIAgAAAA==.Crohunter:BAAANQAECgUIBQABNQAECgoKLQASAKgKAA==.Cropala:BAABNQAECn8tAAISAAoKqAotfgCQAQASAAoKqAotfgCQAQAAAA==.',
Cy='Cynle:BAEANQAECgMIBgAAAA==.',
Da='Darkraider:BAAANQAECggIDQAAAA==.Darkwingduck:BAAANQAECgQIBAABNQAECgoKHgAMALYTAA==.Darkøne:BAAANQABCgMIAwAAAA==.Davros:BAAANQAECgUIBQAAAA==.',
De='Dellandre:BAAANQAECgUIDgABNQAECggIJwAGACgQAA==.Delta:BAABNQAECn8gAAIVAAkKJhHbMQBNAQAVAAkKJhHbMQBNAQAAAA==.Delti:BAAANQADCggICAABNQAECggILQAWAJIaAA==.Destrõ:BAAANQAECgIIAgAAAA==.',
Di='Diabolist:BAABNQAECn8oAAIDAAoKmA15UwChAQADAAoKmA15UwChAQAAAA==.Dielma:BAAANQAECgUICQABNQAFFAUICAAEAL8VAA==.Dirtygiri:BAAANQAECggIDwAAAA==.',
Dk='Dkdozer:BAAANQAECgUICQAAAA==.',
Do='Doktaga:BAABNQAECn8eAAIDAAcKbxKDZABuAQADAAcKbxKDZABuAQAAAA==.',
Dr='Draetanìa:BAAANQADCgYIDAAAAA==.Drakonna:BAAANQADCgUIBQAAAA==.Drarken:BAACNQAFFH8HAAIJAAMKDRMbDADgAAAJAAMKDRMbDADgAAA1AAQKfyUAAgkACQrtGUUUAGoCAAkACQrtGUUUAGoCAAAA.Drtapo:BAAANQAECgIIAwAAAA==.Drustdar:BAAANQADCgEIAQAAAA==.',
El='Elderr:BAAANQAECggIEwAAAA==.Eldhe:BAAANQADCgQIBgAAAA==.Elistrae:BAABNQAECn8hAAIXAAkKrSHmKQDxAgAXAAkKrSHmKQDxAgAAAA==.',
En='Enazen:BAAANQAECggIEAAAAA==.Endlol:BAAANQAECgEIAgABNQAECgkJKwAIADwUAA==.',
Er='Ereshkigal:BAAANQADCgYICQAAAA==.Ergo:BAACNQAFFH8YAAMYAAcKdww7IQB+AQAYAAUKUww7IQB+AQAZAAMKQwxTCACXAAA1AAQKfzsAAxgACgrQHq83AEUCABgACgrQHq83AEUCABkAAgr+HG0eALIAAAAA.',
Ev='Evelake:BAAANQAECgUIDgAAAA==.',
Ex='Exon:BAAANQAECgYICwAAAA==.',
Fa='Faded:BAAANQAECgEIAQABNQAECgkJJQABAGgMAA==.Fadednight:BAABNQAECn8lAAMBAAkKaAxMJgB9AQABAAkKaAxMJgB9AQACAAEKpwQEqgAfAAAAAA==.',
Fe='Femcel:BAAANQAECgcIEgAAAA==.Femcelibate:BAAANQAECgQIBgAAAA==.',
Fi='Fivebones:BAAANQAECgMIAwABNQAECgoKUgAXAHAjAA==.',
Fl='Flacidheals:BAAANQABCgEIAQAAAA==.',
Fr='Freecookies:BAAANQAECgUIBgAAAA==.Frostytotems:BAAANQADCgQIBwAAAA==.',
Fu='Furryiosa:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAABNQAECn8kAAQZAAgKmhTlDACAAQAZAAgKJRTlDACAAQAYAAYKdAzoOAEuAQAaAAEKkxB/DQA3AAAAAA==.',
Ge='Gerbert:BAAANQABCgIIAgAAAA==.',
Gh='Ghostë:BAABNQAECn8dAAIbAAoKbAu+HgCfAQAbAAoKbAu+HgCfAQAAAA==.',
Gi='Gishmou:BAABNQAECn8mAAIRAAcKVR4GRwBGAgARAAcKVR4GRwBGAgAAAA==.',
Go='Gogreenrangr:BAAANQAECgcIBwABNQAECggIDwAHAAAAAA==.Goodlight:BAAANQAECgEIAQAAAA==.',
Gu='Guerrero:BAAANQAECgMIAwAAAA==.Gutted:BAACNQAFFH8YAAITAAcKuiXEAQCfAgATAAcKuiXEAQCfAgA1AAQKfzIAAhMACgqsJm0CAMwDABMACgqsJm0CAMwDAAAA.',
Ha='Hanna:BAABNQAECn8UAAQLAAgK1SQXBwAYAwALAAgK1SQXBwAYAwAcAAcKAhaJJAChAQAQAAMKAh15NwD6AAABNQAFFAcIGAATALolAA==.',
He='Hellmaw:BAAANQAECgUIBwAAAA==.',
Hi='Highly:BAAANQAECgQIBAAAAA==.',
Ho='Hollowheart:BAABNQAECn8VAAIRAAcKAiBGNQAVAgARAAcKAiBGNQAVAgAAAA==.Holycourtney:BAAANQADCgQIBAAAAA==.Holyfur:BAABNQAECn8qAAMdAAkKzQ45TwDDAQAdAAkKYQ45TwDDAQAeAAEKixHLKAAzAAAAAA==.',
Hy='Hylanna:BAAANQAECgUICgAAAA==.',
Ic='Ici:BAABNQAECn8nAAMSAAkKtAiflwBdAQASAAkKtAiflwBdAQAIAAEKHwJSNgEhAAAAAA==.',
Id='Idobutidont:BAAANQADCgIIAgAAAA==.',
If='Iffybacon:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.',
In='Intensifies:BAABNQAECn8nAAIFAAcKYhM7dQDCAQAFAAcKYhM7dQDCAQAAAA==.',
Is='Iskothar:BAABNQAECn8rAAIGAAcKDhinIADfAQAGAAcKDhinIADfAQAAAA==.',
Iv='Ivarboneless:BAAANQAECgcIDwAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jackz:BAAANQADCggIEgAAAA==.Jackzdk:BAAANQADCggIAgAAAA==.Jackzlock:BAAANQAECgUICQAAAA==.Jak:BAACNQAFFH8KAAMXAAQKbA4PGgDrAAAXAAMK2hMPGgDrAAAfAAMKLwMIIABxAAA1AAQKfy4AAxcACgr8HREuAOMCABcACgr8HREuAOMCAB8ABgrRCglGACoBAAAA.Jambii:BAABNQAECn8aAAIXAAYKhhZ7qAC0AQAXAAYKhhZ7qAC0AQAAAA==.Jattsz:BAEANQADCggICAAAAA==.Jayreezy:BAAANQAECgYICAAAAA==.',
Je='Jerawokee:BAACNQAFFH8FAAMYAAMKSAnGMwB8AAAYAAIKSAnGMwB8AAAZAAEKAACjFAAAAAA1AAQKfyMAAxkABwoXHwAMAJMBABgABwrZHY+1ABgCABkABgp4HAAMAJMBAAAA.',
Ji='Jirachii:BAAANQAECggICAABNQAFFAMICAAcACENAA==.',
Jo='Jonah:BAABNQAECn8iAAIEAAoKnRtrBADlAgAEAAoKnRtrBADlAgAAAA==.Joshcalcjr:BAACNQAFFH8FAAIcAAUK+gMqEwA4AQAcAAUK+gMqEwA4AQA1AAQKfygABBwACgpmGBcbAPoBABwACgpmGBcbAPoBAAsABgr5DWguACcBABAAAwqrC0puAEwAAAAA.',
Ka='Kaelthàs:BAAANQADCgcIBwAAAA==.Kaessatha:BAEANQADCgIIAgABNQAECgMIBgAHAAAAAA==.Kalika:BAAANQADCgIIAgAAAA==.',
Ke='Ketesh:BAABNQAECn9BAAMLAAoKlxs2DABCAgALAAkKlxs2DABCAgAOAAEKAAA0PABIAAAAAA==.Kezanplague:BAABNQAECn81AAMgAAoKbRs3BACqAgAgAAkKmxk3BACqAgAXAAkKHBo+ZQBKAgAAAA==.Kezansdoom:BAAANQAECggIDQAAAA==.',
Ko='Kodeack:BAAANQADCgIIAgAAAA==.Kortona:BAAANQAECgIIAwAAAA==.',
Kr='Krej:BAAANQAFFAEIAQABNQAFFAYICQANAM4LAA==.',
['Kø']='Købioshi:BAAANQADCggICwAAAA==.',
La='Landrey:BAAANQADCggIIAAAAA==.Laoghaire:BAAANQADCggIGAAAAA==.Laszarei:BAABNQAECn8oAAIFAAgKDAe0YAApAQAFAAgKDAe0YAApAQAAAA==.',
Le='Leonz:BAACNQAFFH8ZAAIhAAcKIBpCAAA5AgAhAAcKIBpCAAA5AgA1AAQKf04AAiEACgoUJn8AANgDACEACgoUJn8AANgDAAAA.Lethadestro:BAEANQAECgQIBAABNQAECgYIGgACAC4ZAA==.Letharanos:BAEBNQAECn8aAAMCAAYKLhn+SQCTAQACAAYKLhn+SQCTAQATAAQK1whknwCaAAAAAA==.',
Li='Linastina:BAAANQAECgUIBQABNQAECgoKIwAGAMUVAA==.Liraffemynn:BAAANQAECgYICgAAAA==.',
Lo='Lohfall:BAAANQADCgUIBgABNQAECgoKNgABANsYAA==.Lolend:BAAANQAECggIDwAAAA==.Lonranir:BAAANQADCggIEQAAAA==.',
Lu='Luckylucy:BAAANQADCgUIBgAAAA==.Lunoria:BAABNQAECn8kAAIDAAoKcSQRBwCVAwADAAoKcSQRBwCVAwAAAA==.',
Ma='Madarauchiha:BAABNQAECn8dAAMCAAoKsxudEgD5AgACAAoKpBudEgD5AgABAAUK5xbrdwA6AQAAAA==.Madeirà:BAAANQADCgQJBAAAAA==.Magus:BAAANQAECgQIBAABNQAECgUIBQAHAAAAAA==.Maldran:BAABNQAECn8XAAIRAAgKXRChWwB0AQARAAgKXRChWwB0AQAAAA==.Manderpants:BAAANQADCgQIBAAAAA==.Marien:BAABNQAECn8XAAITAAkKcRXVPgAFAgATAAkKcRXVPgAFAgAAAA==.Mavo:BAABNQAFFH8FAAIFAAUKACVGBwA7AQAFAAUKACVGBwA7AQAAAA==.Maxus:BAAANQAECggIDwAAAA==.',
Mb='Mbbin:BAABNQAECn9FAAMYAAoKeCVUAwBkAwAYAAoKeCVUAwBkAwAZAAIKaRTINgBhAAAAAA==.',
Me='Mehuman:BAABNQAECn8eAAISAAkKJhWNpgDTAQASAAkKJhWNpgDTAQAAAA==.Mehumanhuntr:BAAANQAECgIIAgAAAA==.Mehumanlock:BAABNQAECn8yAAIEAAkKRRWcAgAFAgAEAAkKRRWcAgAFAgAAAA==.Melgibson:BAABNQAECn8WAAIGAAkKihoAFwBEAgAGAAkKihoAFwBEAgAAAA==.Meworgendk:BAAANQADCgcICQAAAA==.',
Mf='Mfbeòtch:BAAANQABCgUIBQAAAA==.',
Mi='Miranueta:BAAANQAECgIIAgAAAA==.Miräj:BAAANQAECgMJBAAAAA==.Mistyblue:BAAANQAECgEIAQAAAA==.Miya:BAAANQADCgUIBQAAAA==.',
Mo='Mojomugambe:BAAANQAECgcIDwAAAA==.Moodacritz:BAAANQADCgYIBgAAAA==.Moonscale:BAAANQAECgUIBgAAAA==.Morel:BAAANQADCgQIBAAAAA==.Mortstan:BAACNQAFFH8HAAITAAMKlRadDwDMAAATAAMKlRadDwDMAAA1AAQKfz0AAhMACgr3ITwHAIYDABMACgr3ITwHAIYDAAAA.',
Mu='Mutegen:BAAANQADCgYIBgAAAA==.',
Na='Nailz:BAABNQAECn8tAAMWAAgKkhpdDQA/AQAiAAgKkhmQJwAIAgAWAAcKYBhdDQA/AQAAAA==.',
Ne='Neloangelo:BAAANQAECgUIEQAAAA==.',
Ni='Nightflame:BAAANQADCgYIBgAAAA==.Nightlion:BAABNQAECn8cAAILAAkKwBnqEwAlAgALAAkKwBnqEwAlAgAAAA==.',
No='Noahpal:BAAANQAECgUIBQABNQAECgUICgAHAAAAAA==.Noahshaman:BAACNQAFFH8WAAIFAAcKKxkABwAKAgAFAAcKKxkABwAKAgA1AAQKf08AAwUACgoSJK8FAEQDAAUACgoSJK8FAEQDABEACAojIIEjANkCAAE1AAQKBQgKAAcAAAAA.Noahwarlock:BAAANQAECgUICgAAAA==.Nonsensical:BAAANQADCgQIBQABNQADCgcIGwAHAAAAAA==.Notbacon:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.Noxander:BAAANQADCgMJAwAAAA==.',
Nu='Nuanakk:BAAANQAECggIAQAAAA==.',
Oa='Oaths:BAAANQAECgYIDwAAAA==.',
Oh='Ohmylanta:BAAANQAECgUICAAAAA==.Ohmylänta:BAACNQAFFH8FAAIXAAIK6wPqIAB3AAAXAAIK6wPqIAB3AAA1AAQKfy8AAxcACQqeGJpFAJsCABcACQqeGJpFAJsCACAAAQqpAJ0VABQAAAAA.',
Or='Orandrok:BAAANQAECgEIAQAAAA==.Ormond:BAAANQAECgYIDQAAAA==.',
['Oâ']='Oâth:BAABNQAECn8hAAMWAAoKwQtFFgBIAQAWAAoKwQtFFgBIAQAiAAEK3QPpdQAiAAAAAA==.',
Pa='Paldozer:BAAANQAECgEIAQABNQAECgUICQAHAAAAAA==.Pallyman:BAAANQADCgUIBQAAAA==.Pallywacker:BAABNQAECn8lAAIGAAYKDRekKwCAAQAGAAYKDRekKwCAAQAAAA==.Panzerkìn:BAAANQADCgUIBQAAAA==.',
Pe='Peythilly:BAAANQADCggJDAAAAA==.',
Pi='Pigishdog:BAABNQAECn9CAAIDAAoKUhltOQD7AQADAAoKUhltOQD7AQAAAA==.',
Po='Poob:BAAANQADCgcJEwAAAA==.',
Qu='Quinn:BAABNQAECn8cAAMcAAYK0AlQaAArAQAcAAYK0AlQaAArAQAOAAEK5wNuTAAgAAAAAA==.',
Ra='Raedon:BAAANQADCgQIBAAAAA==.Ragerunner:BAAANQADCgQIBAAAAA==.',
Re='Redthing:BAAANQADCgYICwAAAA==.Retributíon:BAAANQAECgUIBgABNQAECgoKSwAVAOkkAA==.',
Ri='Rixas:BAABNQAECn8qAAISAAoKHyHsIABAAwASAAoKHyHsIABAAwABNQAECgoKUQADABklAA==.Rixis:BAAANQADCgQIBAAAAA==.',
Ro='Rockafella:BAAANQADCgYICgAAAA==.Rodeo:BAAANQADCgIIAgAAAA==.Roguehiro:BAABNQAECn8kAAIGAAoKkB9VBgDOAgAGAAoKkB9VBgDOAgAAAA==.Rooter:BAACNQAFFH8UAAIJAAcKxBsCAwBuAgAJAAcKxBsCAwBuAgA1AAQKfzwAAwkACgoOJHYDAIADAAkACgoOJHYDAIADACMAAwqVE9sTAMkAAAAA.Rozetta:BAAANQADCgQIBAAAAA==.',
Ru='Ruto:BAAANQADCgIIAgAAAA==.',
Sa='Saelis:BAAANQAECgIIAgABNQAFFAMIBwAJAA0TAA==.Samshara:BAAANQAECgUIBQABNQAECgoKMwAXAIoaAA==.Saptapper:BAAANQAECgUICQABNQAECggIDwAHAAAAAA==.',
Sc='Scrawni:BAABNQAECn8pAAILAAoKuh2OCwCyAgALAAoKuh2OCwCyAgABNQAFFAYICQANAM4LAA==.',
Se='Selyane:BAAANQABCgcIEgAAAA==.Seongpal:BAECNQAFFH8VAAIGAAcKIB4HAQCHAgAGAAcKIB4HAQCHAgA1AAQKfzMAAgYACgoWI3sDAIkDAAYACgoWI3sDAIkDAAAA.Seraphinà:BAAANQADCggIIgABNQAECgcIHQALAJwMAA==.Serbingium:BAAANQAECgEIAQABNQAFFAUICAAEAL8VAA==.',
Sh='Shadowfur:BAAANQADCgIIAgABNQAECgkJKgAdAM0OAA==.Shadowlight:BAAANQAECgIJAgABNQAECgIJAwAHAAAAAA==.Shamany:BAAANQAECgIIBAAAAA==.Shamygravy:BAAANQAECgIIAgAAAA==.Shamynna:BAAANQADCgIIAgAAAA==.Sharreth:BAAANQAECgEIAQAAAA==.Shimera:BAABNQAECn8mAAIXAAgKDQk1sACkAQAXAAgKDQk1sACkAQAAAA==.Shodam:BAAANQAECgIIAgAAAA==.Shootrmcgavn:BAACNQAFFH8OAAMXAAYK3xnTCQAhAQAXAAYKjhLTCQAhAQAfAAMKwxcgFQDtAAA1AAQKf0AAAx8ACgpcJX0FAHkDAB8ACgoKJH0FAHkDABcACgrvIx0fABsDAAAA.',
Si='Sidenan:BAAANQADCgUIBQAAAA==.Sittingmoose:BAAANQAECgYICgAAAA==.',
Sk='Sklormp:BAACNQAFFH8IAAMEAAUKvxVDDQCdAAAEAAIKrBFDDQCdAAADAAQKcRa0LgCcAAA1AAQKfyQABAMACgo5HXQwAMUCAAMACgo1G3QwAMUCAAQAAwpdGy01AO4AAA8AAwr1DxchAHAAAAAA.Skrungus:BAAANQADCgEIAQAAAA==.Skubasteve:BAAANQADCggICAAAAA==.',
Sl='Slootar:BAAANQADCggIDwABNQAECgYIGgAXAIYWAA==.Slugs:BAAANQAECgEIAQAAAA==.',
Sm='Smoruk:BAAANQAECgEIAQAAAA==.',
So='Somerled:BAABNQAECn8zAAMXAAoKihprKwBmAgAXAAoKihprKwBmAgAgAAEKPgtBEwA2AAAAAA==.',
Sq='Squatreign:BAABNQAECn8sAAMSAAkKrQspkwBlAQASAAkKrQspkwBlAQAIAAcKyAa6oABDAQAAAA==.',
Sr='Srgtpeppers:BAAANQAECgQIBwAAAA==.',
Su='Sulyvahn:BAEANQAECggIEgABNQAFFAcIFQAGACAeAA==.Sunstrike:BAAANQADCgYIBgAAAA==.',
Sy='Sylvara:BAAANQAECgUIBQAAAA==.',
Ta='Takka:BAAANQAECgcIDAAAAA==.Talkamar:BAABNQAECn8eAAIMAAoKthPLFgDKAQAMAAoKthPLFgDKAQAAAA==.Tarell:BAAANQABCgMIAwAAAA==.Taylorswift:BAABNQAECn8pAAMZAAoKnRWUDQDXAQAZAAYKrByUDQDXAQAYAAkK4RB9mgBDAQAAAA==.',
Te='Tehharlequin:BAAANQAECgEIAQAAAA==.',
Th='Thekourge:BAABNQAECn8nAAIGAAgKKBB2JQAQAQAGAAgKKBB2JQAQAQAAAA==.Thenard:BAABNQAECn8cAAIXAAYK4Qv+0gBaAQAXAAYK4Qv+0gBaAQAAAA==.Therealcafna:BAAANQADCgUIBwAAAA==.Thewhole:BAAANQADCgYIBgAAAA==.Thisle:BAAANQADCgcIKAAAAA==.Thukunamage:BAACNQAFFH8HAAIYAAMKwB9gKACtAAAYAAMKwB9gKACtAAA1AAQKf0gAAxgACgqBJUYHADwDABgACgqBJUYHADwDABoABQo8HFYDAEABAAAA.Thukunawar:BAAANQADCgIIAgABNQAFFAMIBwAYAMAfAA==.',
Ti='Tigerlord:BAAANQADCggIFQAAAA==.Tili:BAAANQADCggIJQAAAA==.',
To='Tomislav:BAABNQAECn8vAAMDAAoKNRLKPgDnAQADAAoKshHKPgDnAQAEAAIKcQ9nWwBvAAAAAA==.Toqur:BAAANQADCggICgAAAA==.Touritos:BAABNQAECn8oAAIFAAkKPRLaRACHAQAFAAkKPRLaRACHAQAAAA==.',
Tr='Trimblestein:BAABNQAECn8eAAINAAgKEiNwSwCnAgANAAgKEiNwSwCnAgAAAA==.Trohas:BAAANQADCggICAAAAA==.',
Tu='Tuskerdu:BAABNQAECn8xAAIcAAgKFAxiUgCSAQAcAAgKFAxiUgCSAQAAAA==.',
Tw='Twiggyss:BAAANQAECggICgAAAA==.Twohoofy:BAAANQADCgYIDQAAAA==.',
Ud='Uddermilk:BAAANQAECgYIDQAAAA==.',
Un='Untempered:BAABNQAECn8rAAMIAAkKPBR/SgC3AQAIAAkKPBR/SgC3AQASAAcKOQ3I8QA5AQAAAA==.',
Va='Valandrian:BAAANQADCgYICQAAAA==.Valeka:BAABNQAECn8oAAMRAAkKThs8JwDHAgARAAkKThs8JwDHAgAFAAEKAADtAgEAAAAAAA==.Valissar:BAAANQABCgcICAAAAA==.Valr:BAABNQAECn80AAIGAAkKcheDDwD3AQAGAAkKcheDDwD3AQAAAA==.Vandreu:BAAANQAECgQIBgAAAA==.',
Vi='Viðrir:BAAANQADCgEIAQAAAA==.',
Vs='Vse:BAACNQAFFH8OAAIZAAMKjxYxAwDvAAAZAAMKjxYxAwDvAAA1AAQKf0UAAhkACgq6In4BAHwDABkACgq6In4BAHwDAAAA.Vsesosorry:BAABNQAECn8hAAIFAAoKURfuIwApAgAFAAoKURfuIwApAgABNQAFFAMIDgAZAI8WAA==.',
Vy='Vyne:BAAANQADCgIIAgABNQADCggIDQAHAAAAAA==.',
Wa='Wangateur:BAAANQADCggICAABNQAECgoKKAADAJgNAA==.',
We='Weierstrass:BAAANQAECggIDQABNQAFFAcIGAATALolAA==.Weiyan:BAAANQADCgcIBwAAAA==.',
Wi='Winklebottom:BAAANQADCgcIEwAAAA==.',
Wo='Worgenkrantz:BAABNQAECn8dAAILAAcKnAz1LQDmAAALAAcKnAz1LQDmAAAAAA==.Worthybacon:BAAANQAECgEIAgAAAA==.',
Wr='Wrathlor:BAAANQADCgQIBAAAAA==.Wrenlyn:BAACNQAFFH8IAAMVAAQKnAYbGQB2AAAVAAMKZQcbGQB2AAAiAAEKRAQOFQBHAAA1AAQKfz4ABBUACgolHzYLAMsCABUACgokHzYLAMsCACIACAr8EP40AJsBABYACQqSFmYMAFABAAE1AAUUBggJAA0AzgsA.',
Wu='Wukain:BAABNQAECn8mAAIFAAoK9wsHdwC8AQAFAAoK9wsHdwC8AQAAAA==.',
Xa='Xalatoth:BAAANQADCgYIBgAAAA==.Xanatas:BAAANQAECgQIBQABNQAECgcIKwAGAA4YAA==.Xarapxeh:BAAANQADCgUICAAAAA==.',
Xo='Xolòtl:BAACNQAFFH8JAAINAAYKzgugHgAXAQANAAYKzgugHgAXAQA1AAQKfzUAAw0ACgo8GTBPAJwCAA0ACgpYFzBPAJwCACQABwrZE+MXABQBAAAA.',
Xy='Xymos:BAECNQAFFH8TAAMEAAcKGh8OBQDJAAADAAUK6h2NCgDBAQAEAAMKHyEOBQDJAAA1AAQKfzMAAwQACgpuJQsBAJgDAAQACQoOJQsBAJgDAAMABwqaJFRUAJ4BAAAA.',
Ya='Yakul:BAABNQAECn8eAAMkAAcKVRvBFgC+AQAkAAcKVRvBFgC+AQANAAcK9AMdwQC/AAAAAA==.',
Za='Zalyia:BAAANQADCgQIBAAAAA==.',
Zd='Zdk:BAAANQADCgEIAQAAAA==.',
Ze='Zeroveth:BAABNQAECn8UAAIYAAcKUBhXywDvAQAYAAcKUBhXywDvAQABNQAECggIEQAHAAAAAA==.Zexpert:BAAANQAECgIIAgABNQAECgcIJgAPAIkYAA==.',
Zu='Zugg:BAAANQAECgUICQAAAA==.Zulcow:BAAANQAECggIDAAAAA==.',
['Âr']='Ârtemis:BAAANQAECgcIDwAAAA==.',
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
