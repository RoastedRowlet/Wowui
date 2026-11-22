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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Paladin-Protection','Unknown-Unknown','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Paladin-Retribution','Hunter-BeastMastery','Monk-Windwalker','Warrior-Arms','Druid-Feral','Warlock-Affliction','Druid-Restoration','Shaman-Restoration','DeathKnight-Blood','Shaman-Enhancement','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Arcane','Mage-Frost','Mage-Fire','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','Warrior-Protection',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaranum:BAAANQAECgMIAwAAAA==.',
Ab='Abaddon:BAABNQAECn8cAAMBAAcKux//OgA2AgABAAcKux//OgA2AgACAAUKIxXqWQBCAQAAAA==.',
Ac='Ackris:BAABNQAECn9aAAMDAAoKHyXbBQBEAwADAAoKHyXbBQBEAwAEAAEKmRDUdwA2AAAAAA==.',
Ag='Agolan:BAABNQAECn8ZAAIFAAkK+xD4UwCMAQAFAAkK+xD4UwCMAQAAAA==.',
Al='Aldric:BAEANQAECgcIDAABNQAFFAgIFwAGABsbAA==.Alkaios:BAAANQAECgQIBgABNQAECgkJOAAGADgZAA==.Alucarddalv:BAAANQAECgQICgAAAA==.Alynthea:BAEANQADCggIEAABNQAECgMIBgAHAAAAAA==.',
Am='Amaimon:BAAANQAECggIDQABNQAFFAYIEAAFAFcOAA==.Amalthaea:BAAANQAECgIIAgABNQAECgoKNwAIAA4XAA==.Amnoon:BAABNQAECn83AAIIAAoKDhcXQQAQAgAIAAoKDhcXQQAQAgAAAA==.Amri:BAABNQAECn8jAAMJAAgKXBlAEQDvAQAJAAgKXBlAEQDvAQAKAAQKMA/0GwCIAAABNQAECgoKUgALABYeAA==.',
An='Andarnáurram:BAAANQAECgYICAABNQAECgoKFwAMACYPAA==.Angelfox:BAAANQAECgQIBAABNQAECgkJLQANAKAJAA==.Angron:BAAANQAECgEIAQAAAA==.Annor:BAEANQADCgYIBgABNQAECgMIBgAHAAAAAA==.',
Ap='Apoly:BAAANQADCgUIBQAAAA==.',
Aq='Aquas:BAAANQADCgEIAQAAAA==.',
Ar='Ardrhys:BAAANQAECgMIBAABNQAECgoKJQAOAMYUAA==.Arknem:BAAANQABCgQIBQAAAA==.Artikin:BAAANQAFFAEIAQABNQAFFAYICQAPAM4LAA==.',
As='Assasinateu:BAAANQADCgIIAgAAAA==.Asûná:BAABNQAECn8pAAIQAAoKgBfKEwCOAQAQAAoKgBfKEwCOAQAAAA==.',
At='Atlas:BAABNQAECn82AAQEAAoKEiF2BADMAQAEAAcKBCB2BADMAQADAAgK/R3+YwCqAQARAAIKbhHOKwA+AAAAAA==.',
Au='Auroxa:BAABNQAECn8mAAQRAAcKiRjaCQDgAQARAAYKkBraCQDgAQADAAMKMBLgCwG0AAAEAAIKvAvLIwBlAAAAAA==.Automagic:BAAANQAECgIIAQAAAA==.',
Av='Avondwella:BAABNQAECn9AAAIPAAoKahuGMwBxAgAPAAoKahuGMwBxAgAAAA==.',
Az='Azorah:BAAANQADCggIEQAAAA==.',
Ba='Bacevicius:BAAANQAECggIDQAAAA==.Baku:BAAANQAECgcICgABNQAFFAYICQAPAM4LAA==.Baldyguy:BAAANQAECgQICgAAAA==.Balm:BAABNQAECn8fAAISAAkK2Q66KgCZAQASAAkK2Q66KgCZAQAAAA==.',
Be='Beastlybull:BAAANQAECgcIDAABNQAFFAkJHQATAPUaAA==.Behindyou:BAAANQAECggIEwABNQAECgoKMwAMACkLAA==.',
Bi='Biblepimp:BAABNQAECn8dAAMIAAoK5hLDYAD2AQAIAAoK5hLDYAD2AQAMAAcKchSIzwB8AQAAAA==.Bigfries:BAAANQAECgEIAQAAAA==.Bigsneak:BAAANQAECgIJAwAAAA==.Birdlaw:BAAANQAECgMIAwAAAA==.',
Bl='Blackmarker:BAABNQAECn8iAAMCAAoK3BVsMwDYAQACAAkKpA5sMwDYAQABAAgK5haPVgC3AQAAAA==.Blemish:BAAANQADCgEIAQABNQAECgkJHwASANkOAA==.Bloodpac:BAAANQADCgEIAQAAAA==.',
Bo='Boadica:BAAANQADCgIIAgAAAA==.Bobsuruncle:BAAANQAECgIIBwAAAA==.Bodyguardwyn:BAAANQAECgIIBQAAAA==.Bolvar:BAABNQAECn81AAIMAAoKYxWGdQBCAgAMAAoKYxWGdQBCAgAAAA==.Bonedjovi:BAABNQAECn8rAAIUAAkKhxBXPABPAQAUAAkKhxBXPABPAQABNQAECgoKNwAIAA4XAA==.Bonedmuch:BAAANQAECgIIBQABNQAECgoKNwAIAA4XAA==.Boondiggles:BAAANQAECgUIDAAAAA==.',
Br='Brathelore:BAAANQADCggICgAAAA==.Bremitox:BAAANQAECgMIAwABNQAECgkJOAAGADgZAA==.Brimscythe:BAAANQADCgIIAQAAAA==.Brud:BAAANQAECgUIEwAAAA==.',
By='Byakugan:BAACNQAFFH8QAAIFAAYKVw7PDQCSAQAFAAYKVw7PDQCSAQA1AAQKfyUAAwUACgo2HC9BAHECAAUACQq8Hi9BAHECABUAAQqRCoA0AD8AAAAA.',
['Bø']='Bønitalèè:BAAANQAECgcICQAAAA==.',
Ca='Cain:BAAANQADCgYICQAAAA==.Calvisi:BAAANQAECgUIDAAAAA==.Calvisichaos:BAABNQAECn8hAAIEAAkKEgwVHgB+AQAEAAkKEgwVHgB+AQAAAA==.Canthen:BAAANQAECggIAgAAAA==.',
Cc='Cc:BAABNQAECn8pAAMCAAgKCwySVQA/AQACAAgKkAuSVQA/AQAUAAcKdQXObwCTAAAAAA==.',
Ch='Chaoticbacon:BAAANQADCgYIBgABNQAECgEIAgAHAAAAAA==.',
Ci='Cissoid:BAAANQAECgEIAQABNQAFFAgIGgAUANAlAA==.',
Co='Conky:BAABNQAECn8bAAMSAAkKWxLRKgCYAQASAAgK6BDRKgCYAQAWAAgKmAwQNABtAQAAAA==.Cosmicsage:BAAANQAECggIEQAAAA==.Cosmicspark:BAABNQAECn8+AAIMAAoKkAvQpwB/AQAMAAoKkAvQpwB/AQAAAA==.',
Cr='Crentist:BAAANQAFFAIIAgAAAA==.Crohunter:BAAANQAECgUIBQABNQAECgoKMwAMACkLAA==.Cropala:BAABNQAECn8zAAIMAAoKKQvSlQChAQAMAAoKKQvSlQChAQAAAA==.',
Cy='Cynle:BAEANQAECgMIBgAAAA==.',
Da='Darkraider:BAAANQAECggIDQAAAA==.Darkwingduck:BAAANQAECgQIBAABNQAECgoKJQAOAMYUAA==.Darkøne:BAAANQABCgMIAwAAAA==.Davros:BAAANQAECgUIBQAAAA==.',
De='Dellandre:BAABNQAECn8bAAIUAAYK5Q6RZgCwAAAUAAYK5Q6RZgCwAAABNQAECgkJLAAGALMQAA==.Delta:BAABNQAECn8jAAIXAAkKJhF1OwBSAQAXAAkKJhF1OwBSAQAAAA==.Delti:BAAANQADCggICAABNQAECgoKMAAYAE8XAA==.Destrõ:BAAANQAECgIIAgAAAA==.',
Di='Diabolist:BAABNQAECn84AAIDAAoK+A/OTADtAQADAAoK+A/OTADtAQAAAA==.Dielma:BAAANQAECgUICQABNQAFFAUICAAEAL8VAA==.Dirtygiri:BAABNQAECn8XAAIMAAoKJg9nfgDQAQAMAAoKJg9nfgDQAQAAAA==.',
Dk='Dkdozer:BAAANQAECgUICQAAAA==.',
Do='Doktaga:BAABNQAECn8eAAIDAAcKbxLqfQBmAQADAAcKbxLqfQBmAQAAAA==.',
Dr='Draetanìa:BAAANQADCgYIDAAAAA==.Drakonna:BAAANQADCgUIBQAAAA==.Drarken:BAACNQAFFH8KAAIJAAMKDRPpDwDbAAAJAAMKDRPpDwDbAAA1AAQKfyUAAgkACQrtGUUUAGoCAAkACQrtGUUUAGoCAAAA.Dropshot:BAAANQADCgYIBgAAAA==.Drtapo:BAAANQAECgIIAwAAAA==.Drustdar:BAAANQADCgEIAQAAAA==.',
Du='Durendin:BAAANQAECgYIBgABNQAFFAYICQAPAM4LAA==.',
El='Elderr:BAAANQAECgcIEwABNQAECgkJHwAOAHAXAA==.Eldhe:BAAANQADCgQIBgAAAA==.Elistrae:BAABNQAECn8jAAINAAkKrSHmKQDxAgANAAkKrSHmKQDxAgAAAA==.',
En='Enazen:BAAANQAECggIEAAAAA==.Endlol:BAAANQAECggIDgABNQAECgkJMAAIADwUAA==.',
Er='Ereshkigal:BAAANQADCgYICQAAAA==.Ergo:BAACNQAFFH8aAAMZAAgKugo7IQB+AQAZAAYKwQk7IQB+AQAaAAMKQwxTCACXAAA1AAQKfzsAAxkACgrQHmtfAMACABkACgrQHmtfAMACABoAAgr+HFwmAKwAAAAA.',
Ev='Evelake:BAAANQAECgUIEAAAAA==.',
Ex='Exodiagold:BAAANQADCggICAAAAA==.Exon:BAAANQAECgYICwAAAA==.',
Fa='Faded:BAAANQAECgEIAQABNQAECgkJKAABAG0MAA==.Fadednight:BAABNQAECn8oAAMBAAkKbQwsLgB5AQABAAkKbQwsLgB5AQACAAEKpwTjwQAeAAAAAA==.Fallingmoon:BAAANQAECgEIAQAAAA==.',
Fe='Femcel:BAAANQAECgcIEgAAAA==.Femcelibate:BAAANQAECgQIBgAAAA==.',
Fi='Fivebones:BAAANQAECgMIAwABNQAECgoKUgANAHAjAA==.',
Fl='Flacidheals:BAAANQABCgEIAQAAAA==.',
Fr='Freecookies:BAAANQAECgUIBgAAAA==.Frostytotems:BAAANQADCgQIBwAAAA==.',
Fu='Furryiosa:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAABNQAECn8pAAQaAAkKWhMEEQB/AQAaAAgKJRQEEQB/AQAZAAcKVgzoOAEuAQAbAAMKzw2BDQA3AAAAAA==.',
Ge='Gerbert:BAAANQABCgIIAgAAAA==.',
Gh='Ghostë:BAABNQAECn8eAAIcAAoKzAu+HgCfAQAcAAoKzAu+HgCfAQAAAA==.',
Gi='Gishmou:BAABNQAECn8sAAITAAkK9Bv7MABbAgATAAkK9Bv7MABbAgAAAA==.',
Go='Gogreenrangr:BAAANQAECgcICgABNQAECgoKFwAMACYPAA==.Goodlight:BAAANQAECgEIAQAAAA==.',
Gu='Guerrero:BAAANQAECgMIAwAAAA==.Gutted:BAACNQAFFH8aAAIUAAgK0CXEAQCfAgAUAAgK0CXEAQCfAgA1AAQKfzMAAxQACgqsJm0CAMwDABQACgqsJm0CAMwDAAEAAQriDwKBAD8AAAAA.',
Ha='Hanna:BAABNQAECn8XAAQLAAkKliIXBwAYAwALAAgK1SQXBwAYAwAWAAgKkBWTJADYAQASAAQK1BpLOAA4AQABNQAFFAgIGgAUANAlAA==.',
He='Hellmaw:BAAANQAECgUIBwAAAA==.',
Hi='Highly:BAAANQAECgQIBAAAAA==.',
Ho='Hollowheart:BAABNQAECn8dAAITAAkKyh/eHADSAgATAAkKyh/eHADSAgAAAA==.Holycourtney:BAAANQADCgQIBAAAAA==.Holyfur:BAABNQAECn8xAAMdAAoK/BHYPQBDAgAdAAoK/BHYPQBDAgAeAAEKixHLKAAzAAAAAA==.',
Hy='Hylanna:BAAANQAECgUICgAAAA==.',
Ic='Ici:BAABNQAECn8rAAMMAAkK0gioswBpAQAMAAkK0gioswBpAQAIAAEKHwJSNgEhAAAAAA==.',
Id='Idobutidont:BAAANQADCgIIAgAAAA==.',
If='Iffybacon:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.',
In='Intensifies:BAABNQAECn8nAAIFAAcKYhM7dQDCAQAFAAcKYhM7dQDCAQAAAA==.',
Is='Iskothar:BAABNQAECn83AAIGAAkKfhfxFQDRAQAGAAkKfhfxFQDRAQAAAA==.',
Iv='Ivarboneless:BAABNQAECn8dAAIIAAoKBRiDTQA0AgAIAAoKBRiDTQA0AgAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jackz:BAAANQADCggIEgAAAA==.Jackzdk:BAAANQAECggICAAAAA==.Jackzlock:BAAANQAECgUICQAAAA==.Jak:BAACNQAFFH8KAAMNAAQKbA4PGgDrAAANAAMK2hMPGgDrAAAfAAMKLwMIIABxAAA1AAQKfy4AAw0ACgr8HREuAOMCAA0ACgr8HREuAOMCAB8ABgrRCglGACoBAAAA.Jambii:BAABNQAECn8aAAINAAYKhhZ7qAC0AQANAAYKhhZ7qAC0AQAAAA==.Jattsz:BAEANQADCggICAAAAA==.Jayreezy:BAAANQAECgYICAAAAA==.',
Je='Jerawokee:BAACNQAFFH8HAAMaAAMKzhSoDwBUAAAZAAIKSAkKPwB2AAAaAAIKQRioDwBUAAA1AAQKfyoAAxoABwoFIpUOAKkBABkABwrZHY+1ABgCABoABwqgIJUOAKkBAAAA.',
Ji='Jirachii:BAAANQAECgYICwABNQAFFAMICAAWACENAA==.',
Jo='Jonah:BAABNQAECn8iAAIEAAoKnRtrBADlAgAEAAoKnRtrBADlAgAAAA==.Joshcalcjr:BAACNQAFFH8HAAIWAAYKQQMqEwA4AQAWAAYKQQMqEwA4AQA1AAQKfykABBYACgpmGPIgAPcBABYACgpmGPIgAPcBAAsABgr5DWguACcBABIAAwqrC0puAEwAAAAA.',
Ka='Kaelthàs:BAAANQADCgcIBwAAAA==.Kaessatha:BAEANQADCgIIAgABNQAECgMIBgAHAAAAAA==.Kalika:BAAANQADCgIIAgAAAA==.',
Ke='Ketesh:BAABNQAECn9SAAMLAAoKFh54CQCoAgALAAkKFh54CQCoAgAQAAEKAAA0PABIAAAAAA==.Kezanplague:BAABNQAECn81AAMgAAoKbRs3BACqAgAgAAkKmxk3BACqAgANAAkKHBo+ZQBKAgAAAA==.Kezansdoom:BAAANQAECgcIDwAAAA==.',
Ko='Kodeack:BAAANQADCgIIAgAAAA==.Kortona:BAAANQAECgIIAwAAAA==.',
Kr='Krej:BAAANQAFFAEIAQABNQAFFAYICQAPAM4LAA==.',
['Kø']='Købioshi:BAAANQADCggICwAAAA==.',
La='Landrey:BAAANQADCggIIAAAAA==.Laoghaire:BAAANQADCggIGAAAAA==.Laszarei:BAABNQAECn8sAAIFAAkKHQevaQBKAQAFAAkKHQevaQBKAQAAAA==.',
Le='Leonz:BAACNQAFFH8bAAIhAAgKpxlCAAA5AgAhAAgKpxlCAAA5AgA1AAQKf1cAAiEACgoLJn8AANgDACEACgoLJn8AANgDAAAA.Lethadestro:BAEANQAECgYICAABNQAECgYIGgACAC4ZAA==.Letharanos:BAEBNQAECn8aAAMCAAYKLhn+SQCTAQACAAYKLhn+SQCTAQAUAAQK1whknwCaAAAAAA==.',
Li='Linastina:BAAANQAECgUIBQABNQAECgoKIwAGAMUVAA==.Liraffemynn:BAAANQAECgYICgAAAA==.',
Lo='Lohfall:BAAANQADCgUIBgABNQAECgoKQgABAIQaAA==.Lolend:BAABNQAECn8jAAMLAAkKxCL3AwArAwALAAkKxCL3AwArAwAQAAQKSgp+LgCcAAAAAA==.Lonranir:BAAANQADCggIEQAAAA==.',
Lu='Luckylucy:BAAANQADCgUIBgAAAA==.Lunoria:BAABNQAECn8kAAIDAAoKcSQRBwCVAwADAAoKcSQRBwCVAwAAAA==.',
Ma='Madarauchiha:BAABNQAECn8fAAMCAAoKOhydEgD5AgACAAoKLBydEgD5AgABAAUK5xbrdwA6AQAAAA==.Madeirà:BAAANQADCgQJBAAAAA==.Magus:BAAANQAECgQIBAABNQAECgUIBQAHAAAAAA==.Maldran:BAABNQAECn8cAAITAAkKERKnWgCrAQATAAkKERKnWgCrAQAAAA==.Malkaios:BAAANQADCgYIBgABNQAECgkJOAAGADgZAA==.Manderpants:BAAANQADCgQIBAAAAA==.Marien:BAABNQAECn8XAAIUAAkKcRXVPgAFAgAUAAkKcRXVPgAFAgAAAA==.Mavo:BAABNQAFFH8GAAIFAAYKLx5yBwB8AQAFAAYKLx5yBwB8AQAAAA==.Maxus:BAABNQAECn8XAAMMAAoK2wZLxABMAQAMAAoK2wZLxABMAQAIAAIKOQWV6QBGAAAAAA==.',
Mb='Mbbin:BAABNQAECn9RAAMZAAoKuiW+AwBoAwAZAAoKuiW+AwBoAwAaAAIKaRTINgBhAAAAAA==.',
Me='Mehuman:BAABNQAECn8eAAIMAAkKJhWNpgDTAQAMAAkKJhWNpgDTAQAAAA==.Mehumanhuntr:BAAANQAECgIIAgAAAA==.Mehumanlock:BAABNQAECn82AAIEAAkKwRWGAwAFAgAEAAkKwRWGAwAFAgAAAA==.Melgibson:BAABNQAECn8WAAIGAAkKihoAFwBEAgAGAAkKihoAFwBEAgAAAA==.Meworgendk:BAAANQADCgcICQAAAA==.',
Mf='Mfbeòtch:BAAANQABCgUIBQAAAA==.',
Mi='Miranueta:BAAANQAECgIIAgAAAA==.Miräj:BAAANQAECgMJBAAAAA==.Mistyblue:BAAANQAECgEIAQAAAA==.Miya:BAAANQADCgUIBQAAAA==.',
Mo='Mojomugambe:BAAANQAECgcIDwAAAA==.Moodacritz:BAAANQADCgYIBgAAAA==.Moonscale:BAAANQAECgUIBgAAAA==.Morel:BAAANQADCgQIBAAAAA==.Mortstan:BAACNQAFFH8JAAIUAAMKDhibFADMAAAUAAMKDhibFADMAAA1AAQKfz0AAhQACgr3ITwHAIYDABQACgr3ITwHAIYDAAAA.',
Mu='Mutegen:BAAANQADCgYIBgAAAA==.',
Na='Nailz:BAABNQAECn8wAAMYAAoKTxfjEAA5AQAiAAoKjxaQJwAIAgAYAAcKYBjjEAA5AQAAAA==.',
Ne='Neloangelo:BAABNQAECn8XAAMBAAcKHAgBSQDiAAABAAcKVQYBSQDiAAAUAAIKnAg9wABIAAAAAA==.',
Ni='Nightflame:BAAANQADCgYIBgAAAA==.Nightlion:BAABNQAECn8lAAMLAAoK3RjqEwAlAgALAAkKwBnqEwAlAgAQAAkKFgwFFwBlAQAAAA==.',
No='Noahpal:BAAANQAECgUIBQABNQAECgUICgAHAAAAAA==.Noahshaman:BAACNQAFFH8YAAIFAAgKShYABwAKAgAFAAgKShYABwAKAgA1AAQKf08AAwUACgoSJJ4HAD4DAAUACgoSJJ4HAD4DABMACAojIIEjANkCAAE1AAQKBQgKAAcAAAAA.Noahwarlock:BAAANQAECgUICgAAAA==.Nonsensical:BAAANQADCgQIBQABNQADCgcIGwAHAAAAAA==.Notbacon:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.Noxander:BAAANQADCgMIAwAAAA==.',
Nu='Nuanakk:BAAANQAECggIAQAAAA==.',
Oa='Oaths:BAABNQAECn8WAAQMAAcKQwqcQgG2AAAMAAYKIwOcQgG2AAAIAAUKuwLdywB/AAAGAAQK5gUtWgBNAAAAAA==.',
Oh='Ohmylanta:BAAANQAECgUICAAAAA==.Ohmylänta:BAACNQAFFH8LAAINAAQKDAQMGwC7AAANAAQKDAQMGwC7AAA1AAQKfzIAAw0ACQqeGJpFAJsCAA0ACQqeGJpFAJsCACAAAQqpAJ0VABQAAAAA.',
Or='Orandrok:BAAANQAECgIIAQAAAA==.Ormond:BAABNQAECn8gAAMIAAgKTxzhOwAoAgAIAAgKTxzhOwAoAgAMAAgKMgZ97AAJAQAAAA==.',
['Oâ']='Oâth:BAABNQAECn8jAAMYAAoKwQtFFgBIAQAYAAoKwQtFFgBIAQAiAAMK4gMVWwApAAAAAA==.',
Pa='Paldozer:BAAANQAECgEIAQABNQAECgUICQAHAAAAAA==.Pallyman:BAAANQADCgUIBQAAAA==.Pallywacker:BAABNQAECn8vAAIGAAcKCxXtJwAyAQAGAAcKCxXtJwAyAQAAAA==.Panzerkìn:BAAANQADCgUIBQAAAA==.',
Pe='Peythilly:BAAANQADCggJDAAAAA==.',
Pi='Pigishdog:BAABNQAECn9TAAIDAAoKyhrIMQBIAgADAAoKyhrIMQBIAgAAAA==.',
Po='Poob:BAAANQADCgcJEwAAAA==.',
Qu='Quinn:BAABNQAECn8dAAMWAAcKuQgWVADOAAAWAAcKuQgWVADOAAAQAAEK5wNuTAAgAAAAAA==.',
Ra='Raedon:BAAANQAECgEIAQAAAA==.Ragerunner:BAAANQADCgQIBAAAAA==.',
Re='Redthing:BAAANQADCgYICwAAAA==.Retributíon:BAAANQAECgUICAABNQAECgoKXQAXAKUlAA==.',
Ri='Rixas:BAABNQAECn84AAIMAAoKFiMPEAArAwAMAAoKFiMPEAArAwABNQAECgoKWgADAB8lAA==.Rixis:BAAANQADCgQIBAAAAA==.',
Ro='Rockafella:BAAANQADCgYICgAAAA==.Rodeo:BAAANQAECgIIAgAAAA==.Roguehiro:BAABNQAECn8qAAIGAAoKrB8ICADJAgAGAAoKrB8ICADJAgAAAA==.Rooter:BAACNQAFFH8cAAIJAAgKRhkCAwBuAgAJAAgKRhkCAwBuAgA1AAQKf0IAAwkACgo9JHYDAIADAAkACgo9JHYDAIADACMAAwqVE/MWAMgAAAAA.Rozetta:BAAANQADCgQIBAAAAA==.',
Ru='Ruto:BAAANQADCgIIAgAAAA==.',
Sa='Saelis:BAAANQAECgIIAgABNQAFFAMICgAJAA0TAA==.Samshara:BAAANQAECgcIEAABNQAECgoKQgANAM8cAA==.Saptapper:BAAANQAECgUIDgABNQAECgoKFwAMACYPAA==.',
Sc='Scrawni:BAABNQAECn8rAAILAAoKuh2OCwCyAgALAAoKuh2OCwCyAgABNQAFFAYICQAPAM4LAA==.',
Se='Selyane:BAAANQABCgcIEgAAAA==.Seongpal:BAECNQAFFH8XAAIGAAgKGxsHAQCHAgAGAAgKGxsHAQCHAgA1AAQKfzMAAgYACgoWI3sDAIkDAAYACgoWI3sDAIkDAAAA.Seraphinà:BAAANQADCggIKgABNQAECgkJJQALAOUMAA==.Serbingium:BAAANQAECgEIAQABNQAFFAUICAAEAL8VAA==.',
Sh='Shadowfur:BAAANQADCgIIAgABNQAECgoKMQAdAPwRAA==.Shadowlight:BAAANQAECgIJAgABNQAECgIJAwAHAAAAAA==.Shamany:BAAANQAECggIDgAAAA==.Shamygravy:BAAANQAECgIIAgAAAA==.Shamynna:BAAANQADCgIIAgAAAA==.Sharreth:BAAANQAECgEIAQAAAA==.Shimera:BAABNQAECn8tAAINAAkKoAmnngB2AQANAAkKoAmnngB2AQAAAA==.Shodam:BAAANQAECgIIAgAAAA==.Shootrmcgavn:BAACNQAFFH8OAAMNAAYK3xl7DgAWAQANAAYKjhJ7DgAWAQAfAAMKwxcgFQDtAAA1AAQKf0kAAx8ACgpfJX0FAHkDAB8ACgo4JH0FAHkDAA0ACgrvIx0fABsDAAAA.',
Si='Sidenan:BAAANQADCgUIBQAAAA==.Sittingmoose:BAAANQAECgYICgAAAA==.',
Sk='Sklormp:BAACNQAFFH8IAAMEAAUKvxVDDQCdAAAEAAIKrBFDDQCdAAADAAQKcRa0LgCcAAA1AAQKfykABAMACgqVIXQwAMUCAAMACgqVIXQwAMUCAAQAAwpdGy01AO4AABEAAwr1DxchAHAAAAAA.Skrungus:BAAANQADCgEIAQAAAA==.Skubasteve:BAAANQADCggICAAAAA==.',
Sl='Slootar:BAAANQADCggIDwABNQAECgYIGgANAIYWAA==.Slugs:BAAANQAECgEIAQAAAA==.',
Sm='Smoruk:BAAANQAECgEIAQAAAA==.',
So='Somerled:BAABNQAECn9CAAMNAAoKzxy8JgCkAgANAAoKzxy8JgCkAgAgAAEKPgtBEwA2AAAAAA==.',
Sq='Squatreign:BAABNQAECn8sAAMMAAkKrQvssABuAQAMAAkKrQvssABuAQAIAAcKyAa6oABDAQAAAA==.',
Sr='Srgtpeppers:BAAANQAECgQIBwAAAA==.',
Su='Sulyvahn:BAEANQAECggIEgABNQAFFAgIFwAGABsbAA==.Sunstrike:BAAANQADCgYIBgAAAA==.',
Sy='Sylvara:BAAANQAECgUIBQAAAA==.',
Ta='Takka:BAAANQAECgcIDAAAAA==.Talkamar:BAABNQAECn8lAAIOAAoKxhTPGQDgAQAOAAoKxhTPGQDgAQAAAA==.Tarell:BAAANQABCgMIAwAAAA==.Taylorswift:BAABNQAECn8yAAMaAAoKWheUDQDXAQAaAAYKrByUDQDXAQAZAAkK3RKhkgCAAQAAAA==.',
Te='Tehharlequin:BAAANQAECgEIAQAAAA==.',
Th='Thekourge:BAABNQAECn8sAAIGAAkKsxCCJQBDAQAGAAkKsxCCJQBDAQAAAA==.Thenard:BAABNQAECn8mAAINAAcKCg1ovAA5AQANAAcKCg1ovAA5AQAAAA==.Therealcafna:BAAANQADCgUIBwAAAA==.Thewhole:BAAANQADCgYIBgAAAA==.Thisle:BAAANQADCgcIKAAAAA==.Thukunamage:BAACNQAFFH8IAAIZAAQKxBnyIAD4AAAZAAQKxBnyIAD4AAA1AAQKf08AAxkACgqBJTULAC4DABkACgqBJTULAC4DABsABQo8HF0EAEUBAAAA.Thukunawar:BAAANQADCgIIAgABNQAFFAQICAAZAMQZAA==.',
Ti='Tigerlord:BAAANQADCggIFQAAAA==.Tili:BAAANQADCggIJQAAAA==.',
To='Tomislav:BAABNQAECn84AAMDAAoKPhSlQgAOAgADAAoK1ROlQgAOAgAEAAIKcQ9nWwBvAAAAAA==.Toqur:BAAANQAECgUIBQAAAA==.Touritos:BAABNQAECn8pAAIFAAoKrBGtRgC6AQAFAAoKrBGtRgC6AQAAAA==.',
Tr='Trimblestein:BAABNQAECn8eAAIPAAgKEiNwSwCnAgAPAAgKEiNwSwCnAgAAAA==.Trohas:BAAANQADCggICAAAAA==.',
Tu='Tuskerdu:BAABNQAECn80AAIWAAoKhwxOMgB4AQAWAAoKhwxOMgB4AQAAAA==.',
Tw='Twiggyss:BAAANQAECggICgAAAA==.Twohoofy:BAAANQADCgYIDQAAAA==.',
Ud='Uddermilk:BAAANQAECgUIEAAAAA==.',
Un='Untempered:BAABNQAECn8wAAMIAAkKPBRRXACnAQAIAAkKPBRRXACnAQAMAAgK/A5V0AA3AQAAAA==.',
Va='Valandrian:BAAANQADCgYICQAAAA==.Valeka:BAABNQAECn8oAAMTAAkKThs8JwDHAgATAAkKThs8JwDHAgAFAAEKAACzIgEAAAAAAA==.Valissar:BAAANQABCgcICAAAAA==.Valr:BAABNQAECn84AAIGAAkKOBmlEQARAgAGAAkKOBmlEQARAgAAAA==.Vandreu:BAAANQAECgQIBgAAAA==.',
Vi='Viðrir:BAAANQADCgEIAQAAAA==.',
Vs='Vse:BAACNQAFFH8PAAIaAAMKjxYxAwDvAAAaAAMKjxYxAwDvAAA1AAQKf00AAhoACgq6In4BAHwDABoACgq6In4BAHwDAAAA.Vsesosorry:BAACNQAFFH8GAAIFAAMKpBVVGwCYAAAFAAMKpBVVGwCYAAA1AAQKfysAAgUACgpYHCcYAKkCAAUACgpYHCcYAKkCAAE1AAUUAwgPABoAjxYA.',
Vy='Vyne:BAAANQADCgIIAgABNQADCggIDQAHAAAAAA==.',
Wa='Wangateur:BAAANQAECgcIDAABNQAECgoKOAADAPgPAA==.',
We='Weierstrass:BAAANQAECggIDQABNQAFFAgIGgAUANAlAA==.Weiyan:BAAANQADCgcIBwAAAA==.',
Wi='Winklebottom:BAAANQADCgcIEwAAAA==.',
Wo='Worgenkrantz:BAABNQAECn8lAAILAAkK5QxoKgA3AQALAAkK5QxoKgA3AQAAAA==.Worthybacon:BAAANQAECgEIAgAAAA==.',
Wr='Wrathlor:BAAANQADCgQIBAAAAA==.Wrenlyn:BAACNQAFFH8JAAMXAAUK4gUtFQCNAAAXAAQKSQYtFQCNAAAiAAEKRAQOFQBHAAA1AAQKfz8ABBcACgolH6AOAMACABcACgokH6AOAMACACIACAr8EP40AJsBABgACQqSFsIPAEoBAAE1AAUUBggJAA8AzgsA.',
Wu='Wukain:BAABNQAECn8mAAIFAAoK9wsHdwC8AQAFAAoK9wsHdwC8AQAAAA==.',
Xa='Xalatoth:BAAANQADCgYIBgAAAA==.Xanatas:BAAANQAECgUIBwABNQAECgkJNwAGAH4XAA==.Xarapxeh:BAAANQADCgUICAAAAA==.',
Xo='Xolòtl:BAACNQAFFH8JAAIPAAYKzgugHgAXAQAPAAYKzgugHgAXAQA1AAQKfzUAAw8ACgo8GTBPAJwCAA8ACgpYFzBPAJwCACQABwrZEzocAHkBAAAA.',
Xy='Xymos:BAECNQAFFH8VAAQEAAgKDhwOBQDJAAADAAUK6h2NCgDBAQAEAAMKHyEOBQDJAAARAAEK1QyaFABRAAA1AAQKfzMAAwQACgpuJQsBAJgDAAQACQoOJQsBAJgDAAMABwqaJHRqAJkBAAAA.',
Ya='Yakul:BAABNQAECn8eAAMkAAcKVRvBFgC+AQAkAAcKVRvBFgC+AQAPAAcK9ANB2wC9AAAAAA==.',
Za='Zalyia:BAAANQADCgQIBAAAAA==.',
Zd='Zdk:BAAANQADCgEIAQAAAA==.',
Ze='Zeroveth:BAABNQAECn8ZAAIZAAkKNBRXywDvAQAZAAkKNBRXywDvAQAAAA==.Zexpert:BAAANQAECgIIAgABNQAECgcIJgARAIkYAA==.',
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
