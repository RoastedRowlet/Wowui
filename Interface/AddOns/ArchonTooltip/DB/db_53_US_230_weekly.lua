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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Paladin-Protection','DeathKnight-Blood','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Unknown-Unknown','Monk-Windwalker','Warrior-Arms','Druid-Feral','Warlock-Affliction','Druid-Restoration','Shaman-Restoration','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Arcane','Mage-Frost','Mage-Fire','Monk-Mistweaver','Druid-Balance','Priest-Holy','Priest-Discipline','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','Warrior-Protection',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abaddon:BAAANQAECgUIEQAAAA==.',
Ac='Ackris:BAABNQAECn9HAAMBAAoKgSTUBwCOAwABAAoKgSTUBwCOAwACAAEKmRDUdwA2AAAAAA==.',
Ag='Agolan:BAABNQAECn8YAAIDAAkK+xBmMQCTAQADAAkK+xBmMQCTAQAAAA==.',
Al='Aldric:BAEANQAECgcIDAABNQAFFAcIFQAEACAeAA==.Alkaios:BAAANQAECgIIAgABNQAECgkJMAAEABsWAA==.Alucarddalv:BAAANQAECgQICgAAAA==.Alynthea:BAEANQADCggIEAAAAA==.',
Am='Amaimon:BAAANQAECgUIBQABNQAFFAYIEAADAFcOAA==.Amalthaea:BAAANQAECgIIAgABNQAECggIJgAFAEAOAA==.Amnoon:BAABNQAECn8wAAIGAAoKxhaMIgA0AgAGAAoKxhaMIgA0AgAAAA==.Amri:BAABNQAECn8cAAMHAAgKQBaZHwDbAQAHAAgKQBaZHwDbAQAIAAMKmQ70GwCIAAABNQAECgoKOgAJADQbAA==.',
An='Andarnáurram:BAAANQADCggICAABNQAECgcIBwAKAAAAAA==.Angron:BAAANQADCggICgAAAA==.Annor:BAEANQADCgYIBgABNQADCggIEAAKAAAAAA==.',
Ap='Apoly:BAAANQADCgUIBQAAAA==.',
Aq='Aquas:BAAANQADCgEIAQAAAA==.',
Ar='Ardrhys:BAAANQAECgIIAgABNQAECgkJGgALALcTAA==.Arknem:BAAANQABCgQIBQAAAA==.Artikin:BAAANQAFFAEIAQABNQAFFAUICAAMAC8MAA==.',
As='Assasinateu:BAAANQADCgIIAgAAAA==.Asûná:BAABNQAECn8hAAINAAgKiBbkEgDQAQANAAgKiBbkEgDQAQAAAA==.',
At='Atlas:BAABNQAECn8oAAQCAAkKqB19CQDaAAABAAcKdxrbaAAuAQACAAUK8h19CQDaAAAOAAEKAABKIQAAAAAAAA==.',
Au='Auroxa:BAABNQAECn8mAAQOAAcKiRjaCQDgAQAOAAYKkBraCQDgAQABAAMKMBLgCwG0AAACAAIKvAuUFwBqAAAAAA==.',
Av='Avondwella:BAABNQAECn8sAAIMAAkK2BbQOwDiAQAMAAkK2BbQOwDiAQAAAA==.',
Az='Azorah:BAAANQADCggIEQAAAA==.',
Ba='Bacevicius:BAAANQAECggIDQAAAA==.Baldyguy:BAAANQAECgQICgAAAA==.Balm:BAABNQAECn8cAAIPAAkK2Q7IGACqAQAPAAkK2Q7IGACqAQAAAA==.',
Be='Beastlybull:BAAANQAECgcIDAABNQAFFAgIHAAQADQbAA==.Behindyou:BAAANQAECgQIBAABNQAECgoKIAARAJIJAA==.',
Bi='Biblepimp:BAABNQAECn8YAAMGAAoKng/DYAD2AQAGAAoKng/DYAD2AQARAAYKrBWIzwB8AQAAAA==.Bigfries:BAAANQADCgQIBgAAAA==.Bigsneak:BAAANQAECgIJAwAAAA==.Birdlaw:BAAANQAECgIIAgAAAA==.',
Bl='Blackmarker:BAABNQAECn8bAAMSAAkKpBUKJwBCAQASAAgK5hYKJwBCAQATAAUKTw4kSAD2AAAAAA==.Blemish:BAAANQADCgEIAQABNQAECgkJHAAPANkOAA==.Bloodpac:BAAANQADCgEIAQAAAA==.',
Bo='Boadica:BAAANQADCgIIAgAAAA==.Bobsuruncle:BAAANQAECgIIBwAAAA==.Bodyguardwyn:BAAANQAECgIIBQAAAA==.Bolvar:BAABNQAECn8kAAIRAAkKjhSGdQBCAgARAAkKjhSGdQBCAgAAAA==.Bonedjovi:BAABNQAECn8mAAIFAAgKQA6NNgALAQAFAAgKQA6NNgALAQAAAA==.Bonedmuch:BAAANQAECgIIAwABNQAECggIJgAFAEAOAA==.Boondiggles:BAAANQAECgUIDAAAAA==.',
Br='Brathelore:BAAANQADCggICgAAAA==.Bremitox:BAAANQAECgMIAwABNQAECgkJMAAEABsWAA==.Brimscythe:BAAANQADCgIIAQAAAA==.Brud:BAAANQAECgUIEwAAAA==.',
By='Byakugan:BAACNQAFFH8QAAIDAAYKVw7PDQCSAQADAAYKVw7PDQCSAQA1AAQKfyQAAwMACgo2HC9BAHECAAMACQq8Hi9BAHECABQAAQqRCoA0AD8AAAAA.',
['Bø']='Bønitalèè:BAAANQAECgYICQAAAA==.',
Ca='Cain:BAAANQADCgQIBAAAAA==.Calvisi:BAAANQAECgUIBwAAAA==.Calvisichaos:BAABNQAECn8ZAAICAAgKGgoVHgB+AQACAAgKGgoVHgB+AQAAAA==.Canthen:BAAANQAECggIAgAAAA==.',
Cc='Cc:BAABNQAECn8bAAMTAAgK6gRAgwChAAATAAgK1wNAgwChAAAFAAUKywMUtQBeAAAAAA==.',
Ch='Chaoticbacon:BAAANQADCgYIBgABNQAECgEIAgAKAAAAAA==.',
Co='Conky:BAAANQAECgYIBQAAAA==.Cosmicsage:BAAANQADCgYIBgAAAA==.Cosmicspark:BAABNQAECn8oAAIRAAgKMwsR0AB7AQARAAgKMwsR0AB7AQAAAA==.',
Cr='Crentist:BAAANQAFFAIIAgAAAA==.Cropala:BAABNQAECn8gAAIRAAoKkgmvZgCKAQARAAoKkgmvZgCKAQAAAA==.',
Cy='Cynle:BAEANQADCggICAABNQADCggIEAAKAAAAAA==.',
Da='Darkraider:BAAANQAECgYIBgAAAA==.Darkwingduck:BAAANQADCgQJBAABNQAECgkJGgALALcTAA==.Darkøne:BAAANQABCgMIAwAAAA==.Davros:BAAANQADCgYIDAABNQAECgQIBAAKAAAAAA==.',
De='Dellandre:BAAANQAECgYIDgABNQAECggIJwAEACgQAA==.Delta:BAABNQAECn8bAAIVAAkKjg9JJwBdAQAVAAkKjg9JJwBdAQAAAA==.Delti:BAAANQADCggICAABNQAECggIKgAWAJIaAA==.Destrõ:BAAANQAECgIIAgAAAA==.',
Di='Diabolist:BAABNQAECn8fAAIBAAkK+wtZhwDUAQABAAkK+wtZhwDUAQAAAA==.Dielma:BAAANQAECgUICQABNQAFFAUICAACAL8VAA==.Dirtygiri:BAAANQAECgcIBwAAAA==.',
Dk='Dkdozer:BAAANQAECgQIBAAAAA==.',
Do='Doktaga:BAABNQAECn8aAAIBAAcKbxLFUABxAQABAAcKbxLFUABxAQAAAA==.',
Dr='Draetanìa:BAAANQADCgYIBgAAAA==.Drakonna:BAAANQADCgUIBQAAAA==.Drarken:BAABNQAECn8kAAIHAAkKuhlFFABqAgAHAAkKuhlFFABqAgAAAA==.Drtapo:BAAANQAECgIIAwAAAA==.Drustdar:BAAANQADCgEIAQAAAA==.',
El='Elderr:BAAANQAECgcIEQABNQAECgkJGgALAIQSAA==.Eldhe:BAAANQADCgIIAgAAAA==.Elistrae:BAABNQAECn8gAAIXAAgKECPmKQDxAgAXAAgKECPmKQDxAgAAAA==.',
En='Enazen:BAAANQAECgcIDwAAAA==.Endlol:BAAANQAECgEIAQABNQAECgkJJQAGADwUAA==.',
Er='Ereshkigal:BAAANQADCgYICQAAAA==.Ergo:BAACNQAFFH8YAAMYAAcKdww7IQB+AQAYAAUKUww7IQB+AQAZAAMKQwxTCACXAAA1AAQKfzIAAxgACgqIHBY1AB0CABgACgqIHBY1AB0CABkAAQo9GmUlAFMAAAAA.',
Ev='Evelake:BAAANQAECgUICgAAAA==.',
Ex='Exodiagold:BAAANQADCggICAAAAA==.Exon:BAAANQAECgYICwAAAA==.',
Fa='Faded:BAAANQAECgEIAQABNQAECggIIQASAEQMAA==.Fadednight:BAABNQAECn8hAAMSAAgKRAwOIwBcAQASAAgKRAwOIwBcAQATAAEKpwQdlAAfAAAAAA==.',
Fe='Femcel:BAAANQAECgcIEgAAAA==.Femcelibate:BAAANQAECgQIBgAAAA==.',
Fi='Fivebones:BAAANQAECgMIAwAAAA==.',
Fl='Flacidheals:BAAANQABCgEIAQAAAA==.',
Fr='Freecookies:BAAANQAECgUIBgAAAA==.Frostytotems:BAAANQADCgQIBwAAAA==.',
Fu='Furryiosa:BAAANQADCgYIBgAAAA==.',
Ga='Gabagool:BAABNQAECn8fAAQZAAcKBxADGQAvAQAZAAYKwBIDGQAvAQAYAAYKdAzoOAEuAQAaAAEKkxB/DQA3AAAAAA==.',
Ge='Gerbert:BAAANQABCgIIAgAAAA==.',
Gh='Ghostë:BAABNQAECn8cAAIbAAoKiwq+HgCfAQAbAAoKiwq+HgCfAQAAAA==.',
Gi='Gishmou:BAABNQAECn8mAAIQAAcKVR4GRwBGAgAQAAcKVR4GRwBGAgAAAA==.',
Go='Goodlight:BAAANQAECgEIAQAAAA==.',
Gu='Guerrero:BAAANQAECgMIAwAAAA==.Gutted:BAACNQAFFH8YAAIFAAcKuiXEAQCfAgAFAAcKuiXEAQCfAgA1AAQKfzEAAgUACgrsJW0CAMwDAAUACgrsJW0CAMwDAAAA.',
Ha='Hanna:BAABNQAECn8UAAQJAAgK1SQXBwAYAwAJAAgK1SQXBwAYAwAcAAcKAhY/GwCzAQAPAAMKAh1LLAAAAQABNQAFFAcIGAAFALolAA==.',
He='Hellmaw:BAAANQAECgQIBwAAAA==.',
Hi='Highly:BAAANQAECgQIBAAAAA==.',
Ho='Hollowheart:BAABNQAECn8VAAIQAAcKAiBGJQAiAgAQAAcKAiBGJQAiAgAAAA==.Holycourtney:BAAANQADCgQIBAAAAA==.Holyfur:BAABNQAECn8iAAMdAAcKzBCSUgBoAQAdAAcKQRCSUgBoAQAeAAEKixHLKAAzAAAAAA==.',
Hy='Hylanna:BAAANQAECgUIBQAAAA==.',
Ic='Ici:BAABNQAECn8jAAMRAAgKHQgqiABAAQARAAgKHQgqiABAAQAGAAEKHwJSNgEhAAAAAA==.',
Id='Idobutidont:BAAANQADCgIIAgAAAA==.',
If='Iffybacon:BAAANQAECgEIAQABNQAECgEIAgAKAAAAAA==.',
In='Intensifies:BAABNQAECn8nAAIDAAcKYhM7dQDCAQADAAcKYhM7dQDCAQAAAA==.',
Is='Iskothar:BAABNQAECn8kAAIEAAcK0RenIADfAQAEAAcK0RenIADfAQAAAA==.',
Iv='Ivarboneless:BAAANQAECgcIDwAAAA==.',
Ja='Jace:BAAANQADCgYIBgAAAA==.Jackz:BAAANQADCggIEgAAAA==.Jackzlock:BAAANQAECgUICQAAAA==.Jak:BAACNQAFFH8JAAMXAAMK2hMPGgDrAAAXAAMK2hMPGgDrAAAfAAIK0AIIIABxAAA1AAQKfy0AAxcACgr8HREuAOMCABcACgr8HREuAOMCAB8ABgrRCglGACoBAAAA.Jambii:BAABNQAECn8aAAIXAAYKhhZ7qAC0AQAXAAYKhhZ7qAC0AQAAAA==.Jattsz:BAEANQADCggICAAAAA==.Jayreezy:BAAANQAECgYICAAAAA==.',
Je='Jerawokee:BAABNQAECn8eAAMZAAcK2R0qCwBWAQAYAAcK2R2PtQAYAgAZAAYKFxYqCwBWAQAAAA==.',
Ji='Jirachii:BAAANQAECgQIBQABNQAFFAMICAAcACENAA==.',
Jo='Jonah:BAABNQAECn8iAAICAAoKnRtrBADlAgACAAoKnRtrBADlAgAAAA==.Joshcalcjr:BAACNQAFFH8FAAIcAAUK+gMqEwA4AQAcAAUK+gMqEwA4AQA1AAQKfycABBwACgpmGD8UAAsCABwACgpmGD8UAAsCAAkABgr5DWguACcBAA8AAwqrCxtTAEIAAAAA.',
Ka='Kaelthàs:BAAANQADCgcIBwAAAA==.Kaessatha:BAEANQADCgIIAgABNQADCggIEAAKAAAAAA==.Kalika:BAAANQADCgIIAgAAAA==.',
Ke='Ketesh:BAABNQAECn86AAMJAAoKNBsPCgAnAgAJAAkKNBsPCgAnAgANAAEKAAA0PABIAAAAAA==.Kezanplague:BAABNQAECn81AAMgAAoKbRs3BACqAgAgAAkKmxk3BACqAgAXAAkKHBoiSADGAQAAAA==.Kezansdoom:BAAANQAECgcICAAAAA==.',
Ko='Kodeack:BAAANQADCgIIAgAAAA==.Kortona:BAAANQAECgIIAwAAAA==.',
Kr='Krej:BAAANQAFFAEIAQABNQAFFAUICAAMAC8MAA==.',
['Kø']='Købioshi:BAAANQADCggICwAAAA==.',
La='Landrey:BAAANQADCgYIHgAAAA==.Laoghaire:BAAANQADCggIGAAAAA==.Laszarei:BAABNQAECn8lAAIDAAgKAgc/SwAsAQADAAgKAgc/SwAsAQAAAA==.',
Le='Leonz:BAACNQAFFH8ZAAIhAAcKIBpCAAA5AgAhAAcKIBpCAAA5AgA1AAQKf0QAAiEACgosJX8AANgDACEACgosJX8AANgDAAAA.Lethadestro:BAEANQAECgEIAQABNQAECgYIGgATAC4ZAA==.Letharanos:BAEBNQAECn8aAAMTAAYKLhn+SQCTAQATAAYKLhn+SQCTAQAFAAQK1whknwCaAAAAAA==.',
Li='Liraffemynn:BAAANQAECgYICgAAAA==.',
Lo='Lohfall:BAAANQADCgUIBgABNQAECgoKMAASAI8WAA==.Lolend:BAAANQAECggICQAAAA==.Lonranir:BAAANQADCggIEQAAAA==.',
Lu='Luckylucy:BAAANQADCgUIBgAAAA==.Lunoria:BAABNQAECn8kAAIBAAoKcSQRBwCVAwABAAoKcSQRBwCVAwAAAA==.',
Ma='Madarauchiha:BAABNQAECn8dAAMTAAoKvBudEgD5AgATAAoKrhudEgD5AgASAAUK5xbrdwA6AQAAAA==.Madeirà:BAAANQADCgQJBAAAAA==.Magus:BAAANQAECgQIBAAAAA==.Maldran:BAABNQAECn8XAAIQAAgKXRBlRgB7AQAQAAgKXRBlRgB7AQAAAA==.Manderpants:BAAANQADCgQIBAAAAA==.Marien:BAABNQAECn8WAAIFAAgKGRbVPgAFAgAFAAgKGRbVPgAFAgAAAA==.Mavo:BAABNQAFFH8FAAIDAAUKACXvBABDAQADAAUKACXvBABDAQAAAA==.Maxus:BAAANQAECgcIDAAAAA==.',
Mb='Mbbin:BAABNQAECn87AAMYAAoKEiULEACSAwAYAAoKEiULEACSAwAZAAIKaRTINgBhAAAAAA==.',
Me='Meems:BAAANQABCgQIBAAAAA==.Mehuman:BAABNQAECn8eAAIRAAkKJhWNpgDTAQARAAkKJhWNpgDTAQAAAA==.Mehumanhuntr:BAAANQAECgIIAgAAAA==.Mehumanlock:BAABNQAECn8uAAICAAgKFhXFAgC2AQACAAgKFhXFAgC2AQAAAA==.Melgibson:BAABNQAECn8VAAIEAAgK9BoAFwBEAgAEAAgK9BoAFwBEAgAAAA==.Meworgendk:BAAANQADCgcICQAAAA==.',
Mi='Miräj:BAAANQAECgMJBAAAAA==.Mistyblue:BAAANQAECgEIAQAAAA==.Miya:BAAANQADCgUIBQAAAA==.',
Mo='Mojomugambe:BAAANQAECgcIDwAAAA==.Moodacritz:BAAANQADCgYIBgAAAA==.Moonscale:BAAANQAECgEIAQAAAA==.Morel:BAAANQADCgQIBAAAAA==.Mortstan:BAABNQAECn88AAIFAAoK9yE8BwCGAwAFAAoK9yE8BwCGAwAAAA==.',
Mu='Mutegen:BAAANQADCgYIBgAAAA==.',
Na='Nailz:BAABNQAECn8qAAMWAAgKkhrgCQBJAQAiAAgKkhmQJwAIAgAWAAcKYBjgCQBJAQAAAA==.',
Ne='Neloangelo:BAAANQAECgYIDgAAAA==.',
Ni='Nightflame:BAAANQADCgYIBgAAAA==.Nightlion:BAABNQAECn8cAAIJAAkKwBnqEwAlAgAJAAkKwBnqEwAlAgAAAA==.',
No='Noahpal:BAAANQAECgUIBQABNQAECgUICgAKAAAAAA==.Noahshaman:BAACNQAFFH8WAAIDAAcKKxkABwAKAgADAAcKKxkABwAKAgA1AAQKf0YAAwMACgoEI1YHAAwDAAMACgoEI1YHAAwDABAACAojIIEjANkCAAE1AAQKBQgKAAoAAAAA.Noahwarlock:BAAANQAECgUICgAAAA==.Nonsensical:BAAANQADCgQIBQABNQADCgcIFwAKAAAAAA==.Notbacon:BAAANQAECgEIAQABNQAECgEIAgAKAAAAAA==.Noxander:BAAANQADCgMJAwAAAA==.',
Nu='Nuanakk:BAAANQAECgcIAQAAAA==.',
Oa='Oaths:BAAANQAECgUICgAAAA==.',
Oh='Ohmylanta:BAAANQAECgEIAQAAAA==.Ohmylänta:BAABNQAECn8vAAMXAAkKnhiaRQCbAgAXAAkKnhiaRQCbAgAgAAEKqQCdFQAUAAAAAA==.',
Or='Orandrok:BAAANQAECgEIAQAAAA==.Ormond:BAAANQAECgUIBwAAAA==.',
['Oâ']='Oâth:BAABNQAECn8fAAMWAAoKAwtFFgBIAQAWAAoKAwtFFgBIAQAiAAEK3QPpdQAiAAAAAA==.',
Pa='Paldozer:BAAANQAECgEIAQABNQAECgQIBAAKAAAAAA==.Pallyman:BAAANQADCgUIBQAAAA==.Pallywacker:BAABNQAECn8lAAIEAAYKDRekKwCAAQAEAAYKDRekKwCAAQAAAA==.Panzerkìn:BAAANQADCgUIBQAAAA==.',
Pe='Peythilly:BAAANQADCggJDAAAAA==.',
Pi='Pigishdog:BAABNQAECn87AAIBAAoKERYDMQDpAQABAAoKERYDMQDpAQAAAA==.',
Po='Poob:BAAANQADCgcJEwAAAA==.',
Qu='Quinn:BAABNQAECn8cAAMcAAYK0AlQaAArAQAcAAYK0AlQaAArAQANAAEK5wNuTAAgAAAAAA==.',
Ra='Raedon:BAAANQADCgQIBAAAAA==.Ragerunner:BAAANQADCgQIBAAAAA==.',
Re='Redthing:BAAANQADCgYICwAAAA==.Retributíon:BAAANQAECgUIBgABNQAECgoKSQAVAOkkAA==.',
Ri='Rixas:BAABNQAECn8iAAIRAAoKTSDsIABAAwARAAoKTSDsIABAAwABNQAECgoKRwABAIEkAA==.Rixis:BAAANQADCgQIBAAAAA==.',
Ro='Rockafella:BAAANQADCgYICgAAAA==.Rodeo:BAAANQADCgIIAgAAAA==.Roguehiro:BAABNQAECn8ZAAIEAAoKOR5cBQCwAgAEAAoKOR5cBQCwAgAAAA==.Rooter:BAACNQAFFH8TAAIHAAcKxBsCAwBuAgAHAAcKxBsCAwBuAgA1AAQKfzYAAwcACgoOJHYDAIADAAcACgoOJHYDAIADACMAAwqVE0oQAM0AAAAA.Rozetta:BAAANQADCgQIBAAAAA==.',
Ru='Ruto:BAAANQADCgIIAgAAAA==.',
Sa='Saelis:BAAANQAECgIIAgABNQAECgkJJAAHALoZAA==.Samshara:BAAANQADCgIIAgABNQAECgkJKQAXAOAbAA==.Saptapper:BAAANQAECgQIBAABNQAECgcIBwAKAAAAAA==.',
Sc='Scrawni:BAABNQAECn8nAAIJAAoKdR2OCwCyAgAJAAoKdR2OCwCyAgABNQAFFAUICAAMAC8MAA==.',
Se='Selyane:BAAANQABCgcIEgAAAA==.Seongpal:BAECNQAFFH8VAAIEAAcKIB4HAQCHAgAEAAcKIB4HAQCHAgA1AAQKfzMAAgQACgoWIxcCADQDAAQACgoWIxcCADQDAAAA.Seraphinà:BAAANQADCggIGwABNQAECgcIFwAJAIoLAA==.Serbingium:BAAANQAECgEIAQABNQAFFAUICAACAL8VAA==.',
Sh='Shadowfur:BAAANQADCgIIAgABNQAECgcIIgAdAMwQAA==.Shadowlight:BAAANQAECgIJAgABNQAECgIJAwAKAAAAAA==.Shamany:BAAANQAECgEIAgAAAA==.Shamygravy:BAAANQAECgIIAgAAAA==.Shamynna:BAAANQADCgIIAgAAAA==.Sharreth:BAAANQAECgEIAQAAAA==.Shimera:BAABNQAECn8lAAIXAAgKDQmgfgA2AQAXAAgKDQmgfgA2AQAAAA==.Shodam:BAAANQAECgIIAgAAAA==.Shootrmcgavn:BAACNQAFFH8NAAMXAAUKnhZEEQC9AAAfAAMKwxcgFQDtAAAXAAUK3AxEEQC9AAA1AAQKfzkAAx8ACgpIJX0FAHkDAB8ACgqoI30FAHkDABcACgrvIx0fABsDAAAA.',
Si='Sittingmoose:BAAANQAECgYICgAAAA==.',
Sk='Sklormp:BAACNQAFFH8IAAMCAAUKvxVDDQCdAAACAAIKrBFDDQCdAAABAAQKcRa0LgCcAAA1AAQKfyEABAEACgo5HXQwAMUCAAEACQpMHnQwAMUCAAIAAwpdGy01AO4AAA4AAwr1DxchAHAAAAAA.Skrungus:BAAANQADCgEIAQAAAA==.Skubasteve:BAAANQADCggICAAAAA==.',
Sl='Slootar:BAAANQADCggIDwABNQAECgYIGgAXAIYWAA==.Slugs:BAAANQAECgEIAQAAAA==.',
Sm='Smoruk:BAAANQADCgUIBQAAAA==.',
So='Somerled:BAABNQAECn8pAAMXAAkK4BvSLAAtAgAXAAkK4BvSLAAtAgAgAAEKPgtBEwA2AAAAAA==.',
Sq='Squatreign:BAABNQAECn8qAAMRAAkKogvLawB9AQARAAkKogvLawB9AQAGAAcKyAa6oABDAQAAAA==.',
Sr='Srgtpeppers:BAAANQAECgIIAwAAAA==.',
Su='Sulyvahn:BAEANQAECgUICgABNQAFFAcIFQAEACAeAA==.Sunstrike:BAAANQADCgYIBgAAAA==.',
Sy='Sylvara:BAAANQADCgYIEQAAAA==.',
Ta='Takka:BAAANQAECgcIDAAAAA==.Talkamar:BAABNQAECn8aAAILAAkKtxO4FQCRAQALAAkKtxO4FQCRAQAAAA==.Tarell:BAAANQABCgMIAwAAAA==.Taylorswift:BAABNQAECn8mAAMZAAoKnRWUDQDXAQAZAAYKrByUDQDXAQAYAAkK4RAVewBNAQAAAA==.',
Te='Tehharlequin:BAAANQAECgEIAQAAAA==.',
Th='Thekourge:BAABNQAECn8nAAIEAAgKKBD3HAAUAQAEAAgKKBD3HAAUAQAAAA==.Thenard:BAABNQAECn8cAAIXAAYK4QtAoADuAAAXAAYK4QtAoADuAAAAAA==.Therealcafna:BAAANQADCgUIBwAAAA==.Thisle:BAAANQADCgcIKAAAAA==.Thukunamage:BAACNQAFFH8FAAIYAAMKwB9JIACyAAAYAAMKwB9JIACyAAA1AAQKfz0AAhgACgqBJRIFAD4DABgACgqBJRIFAD4DAAAA.Thukunawar:BAAANQADCgIIAgABNQAFFAMIBQAYAMAfAA==.',
Ti='Tigerlord:BAAANQADCggIFQAAAA==.Tili:BAAANQADCgYIIwAAAA==.',
To='Tomislav:BAABNQAECn8cAAMBAAoK2RCsMADrAQABAAoKVhCsMADrAQACAAIKcQ9nWwBvAAAAAA==.Touritos:BAABNQAECn8jAAIDAAgK/hKFQABSAQADAAgK/hKFQABSAQAAAA==.',
Tr='Trimblestein:BAABNQAECn8eAAIMAAgKEiNwSwCnAgAMAAgKEiNwSwCnAgAAAA==.Trohas:BAAANQADCggICAAAAA==.',
Tu='Tuskerdu:BAABNQAECn8rAAIcAAgKBQxiUgCSAQAcAAgKBQxiUgCSAQAAAA==.',
Tw='Twiggyss:BAAANQAECggICgAAAA==.Twohoofy:BAAANQADCgYIDQAAAA==.',
Ud='Uddermilk:BAAANQAECgYIDQAAAA==.',
Un='Untempered:BAABNQAECn8lAAMGAAkKPBS5NwC+AQAGAAkKPBS5NwC+AQARAAcKbQvXuADoAAAAAA==.',
Va='Valandrian:BAAANQADCgYICQAAAA==.Valeka:BAABNQAECn8kAAMQAAkKThs8JwDHAgAQAAkKThs8JwDHAgADAAEKAAC64AAAAAAAAA==.Valissar:BAAANQABCgcICAAAAA==.Valr:BAABNQAECn8wAAIEAAkKGxaaCwD0AQAEAAkKGxaaCwD0AQAAAA==.Vandreu:BAAANQAECgQIBgAAAA==.',
Vi='Viðrir:BAAANQADCgEIAQAAAA==.',
Vs='Vse:BAACNQAFFH8MAAIZAAMKjxYxAwDvAAAZAAMKjxYxAwDvAAA1AAQKfzoAAhkACgq6In4BAHwDABkACgq6In4BAHwDAAAA.Vsesosorry:BAABNQAECn8YAAIDAAoKYRUzHwADAgADAAoKYRUzHwADAgABNQAFFAMIDAAZAI8WAA==.',
Vy='Vyne:BAAANQADCgIIAgABNQADCggIDQAKAAAAAA==.',
We='Weierstrass:BAAANQAECgEIBAABNQAFFAcIGAAFALolAA==.Weiyan:BAAANQADCgcIBwAAAA==.',
Wi='Winklebottom:BAAANQADCgcIEwAAAA==.',
Wo='Worgenkrantz:BAABNQAECn8XAAIJAAcKigvDJQDeAAAJAAcKigvDJQDeAAAAAA==.Worthybacon:BAAANQAECgEIAgAAAA==.',
Wr='Wrathlor:BAAANQADCgQIBAAAAA==.Wrenlyn:BAACNQAFFH8HAAMVAAMKNwcbGQB2AAAVAAIKsQgbGQB2AAAiAAEKRAQOFQBHAAA1AAQKfzUABBUACgodHvEVAP0BABUACgpGGvEVAP0BACIACAr8EP40AJsBABYACQqSFhEJAFwBAAE1AAUUBQgIAAwALwwA.',
Wu='Wukain:BAABNQAECn8mAAIDAAoK9wsHdwC8AQADAAoK9wsHdwC8AQAAAA==.',
Xa='Xalatoth:BAAANQADCgYIBgAAAA==.Xanatas:BAAANQAECgMIAwABNQAECgcIJAAEANEXAA==.Xarapxeh:BAAANQADCgUICAAAAA==.',
Xo='Xolòtl:BAACNQAFFH8IAAIMAAUKLwygHgAXAQAMAAUKLwygHgAXAQA1AAQKfzQAAwwACgo8GTBPAJwCAAwACgpYFzBPAJwCACQABwrZE+URAB0BAAAA.',
Xy='Xymos:BAECNQAFFH8TAAMCAAcKGh8OBQDJAAABAAUK6h2NCgDBAQACAAMKHyEOBQDJAAA1AAQKfy8AAwIACgplJQsBAJgDAAIACQoOJQsBAJgDAAEABwqLJI9CAKABAAAA.',
Ya='Yakul:BAABNQAECn8YAAMkAAcKVRt1EAAwAQAkAAcKVRt1EAAwAQAMAAEKAAB2XgEoAAAAAA==.',
Za='Zalyia:BAAANQADCgQIBAAAAA==.',
Zd='Zdk:BAAANQADCgEIAQAAAA==.',
Ze='Zeroveth:BAABNQAECn8UAAIYAAcKUBhXywDvAQAYAAcKUBhXywDvAQABNQAECggICQAKAAAAAA==.Zexpert:BAAANQAECgIIAgABNQAECgcIJgAOAIkYAA==.',
Zu='Zugg:BAAANQADCggIDAAAAA==.Zulcow:BAAANQAECggIDAAAAA==.',
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
