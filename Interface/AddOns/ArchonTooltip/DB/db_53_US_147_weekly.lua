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

local lookup = {'Warrior-Arms','Priest-Holy','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Warlock-Demonology','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Rogue-Outlaw','Rogue-Subtlety','Monk-Windwalker','Priest-Shadow','Druid-Guardian','Shaman-Elemental','Hunter-Survival','Priest-Discipline','Paladin-Protection','Druid-Feral','Hunter-BeastMastery','Mage-Arcane','Unknown-Unknown','Warrior-Fury','Hunter-Marksmanship','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absydion:BAAANQAECggICwAAAA==.',
Ae='Aelion:BAAANQAECgIIAwABNQAECgkJGgABALAcAA==.',
An='Anegos:BAAANQADCggIDwABNQAFFAUIBwACACUMAA==.Anyliea:BAAANQAECgIIAgAAAA==.',
Ar='Arwenah:BAABNQAECn8bAAIDAAcK8xGZLAAvAQADAAcK8xGZLAAvAQAAAA==.',
As='Asahhealer:BAABNQAECn8tAAIDAAkKHxfrPQBoAgADAAkKHxfrPQBoAgAAAA==.Astridd:BAACNQAFFH8GAAIEAAMKJx+KBAAhAQAEAAMKJx+KBAAhAQA1AAQKfyEAAgQACgo5IUkMAFADAAQACgo5IUkMAFADAAAA.Aszcuul:BAAANQADCgEIAQABNQAECgoKJwAFAEoaAA==.',
Au='Aurorabelli:BAAANQAECgYIDAAAAA==.Auróra:BAABNQAECn8nAAIGAAoK6iAcCQAUAgAGAAoK6iAcCQAUAgAAAA==.',
Av='Averlence:BAAANQAECgQICwAAAA==.',
Aw='Awriya:BAAANQABCgIIAgAAAA==.',
Ba='Bahumn:BAAANQAECgQIBQABNQAECgoKHAAHAK0VAA==.Batteryacid:BAAANQAECgIIAQAAAA==.',
Be='Bergles:BAABNQAECn8zAAMIAAoKrxd2PwBnAgAIAAoKrxd2PwBnAgAJAAgKhRsiawBcAgAAAA==.',
Bi='Bigtee:BAAANQADCgIJAgAAAA==.',
Bo='Bonitoflakes:BAAANQADCgQIBAAAAA==.Bonnieblüe:BAAANQAFFAEIAQAAAA==.Bopeep:BAAANQADCgcICAAAAA==.',
Br='Brekta:BAAANQADCggIEAAAAA==.Brewwizard:BAAANQAECgUIBQABNQAECgkJKAAFADIPAA==.',
Bu='Bullshiza:BAAANQABCgUIBwAAAA==.Burningfel:BAABNQAECn8wAAQKAAkKbhXYBwAZAgAKAAgKRRTYBwAZAgALAAgKLhSuEwDTAQAGAAIKhAsVKQFsAAAAAA==.',
Ca='Calihye:BAAANQAECgEIAQABNQAFFAcIFwAFAEEgAA==.Camel:BAABNQAECn8iAAMJAAcKugr6SgAvAQAJAAcKugr6SgAvAQAIAAMKPwNWAQF3AAAAAA==.Cattlestance:BAABNQAECn8qAAIMAAoKpRI9EgACAgAMAAoKpRI9EgACAgAAAA==.',
Ce='Ceriebrium:BAAANQAECgMIAwAAAA==.',
Ch='Chichi:BAAANQABCggICgAAAA==.',
Co='Coldphyre:BAAANQAECgIIAwAAAA==.',
Da='Dakka:BAAANQADCgcICwAAAA==.Damnedsuen:BAAANQAECgQIDQAAAA==.Dashdashdash:BAAANQAECgUIEwAAAA==.',
De='Deceiverdave:BAAANQAECgEIAQAAAA==.Derazen:BAAANQADCgYIBgAAAA==.Destyne:BAAANQAECgUIBwAAAA==.',
Di='Dixonfire:BAAANQADCgEIAQAAAA==.',
Dj='Dj:BAABNQAECn8qAAMNAAkKaRkJAQCoAQAOAAgK8xf5FgAoAgANAAkKxhYJAQCoAQABNQAFFAQICwAPAD0YAA==.',
Do='Dodgydave:BAAANQAECgQIBQAAAA==.Doomzeer:BAABNQAECn8bAAIQAAoK8RrwEgDTAgAQAAoK8RrwEgDTAgAAAA==.',
Dr='Drakarys:BAAANQAECgUIBQAAAA==.Drezlek:BAAANQADCgcICwAAAA==.Drezz:BAAANQADCggIFgAAAA==.Dràgøn:BAAANQAECggIAgAAAA==.',
Du='Durkanis:BAABNQAECn8tAAIRAAoK6B74BABRAwARAAoK6B74BABRAwAAAA==.',
El='Eleesa:BAAANQAECgUICwAAAA==.Element:BAABNQAECn8WAAISAAcKLxFWigCKAQASAAcKLxFWigCKAQAAAA==.',
Em='Emi:BAACNQAFFH8LAAIDAAQKICBpBACCAQADAAQKICBpBACCAQA1AAQKfyMAAwMACgrKIHYjANkCAAMACgrKIHYjANkCABIABArwErXZAOEAAAAA.',
Ex='Exury:BAACNQAFFH8GAAISAAIKgBhGHwC5AAASAAIKgBhGHwC5AAA1AAQKfxoAAhIACQq5HlsqANcCABIACQq5HlsqANcCAAAA.',
Fa='Faelin:BAAANQADCgYIBAAAAA==.',
Fe='Felenus:BAAANQAECgEJAQAAAA==.Fenrir:BAAANQAECgQICQAAAA==.',
Fi='Fir:BAABNQAECn8qAAIDAAkKyR4WHgDzAgADAAkKyR4WHgDzAgAAAA==.',
Fl='Floknidemon:BAABNQAECn8wAAIDAAkKMw/rMQAbAQADAAkKMw/rMQAbAQAAAA==.',
Fo='Forthrich:BAABNQAECn8sAAIJAAkKSAy6KwB8AQAJAAkKSAy6KwB8AQAAAA==.Fozuul:BAAANQAECggICwABNQAECgoKJwAFAEoaAA==.',
Fr='Fredò:BAABNQAECn8sAAIPAAoKVR5LEQDWAgAPAAoKVR5LEQDWAgAAAA==.Frozono:BAAANQAECgUIBgAAAA==.Frâust:BAAANQAECgYIEAAAAA==.',
Ga='Galadril:BAAANQAECgEIAQAAAA==.Gandulf:BAAANQADCgUIBQAAAA==.Gawkin:BAABNQAECn8uAAMIAAoKBiSUCQB8AwAIAAoKBiSUCQB8AwAJAAEKmh/ffwFaAAAAAA==.',
Ge='Geodude:BAAANQADCgUIBQAAAA==.',
Go='Goaty:BAAANQAECgUIBgAAAA==.',
Gr='Grimspear:BAABNQAECn8uAAITAAoKgx15AgATAwATAAoKgx15AgATAwAAAA==.',
Gu='Gumbercules:BAAANQAECgQICgAAAA==.Gurnsey:BAAANQADCgQIBAAAAA==.',
['Gæ']='Gæa:BAAANQAECgYIBwAAAA==.',
Ha='Halogirl:BAABNQAECn8bAAMUAAgKGhx6AABIAgAUAAgKGhx6AABIAgAQAAUKUgcdSQD3AAAAAA==.Haters:BAAANQAECgEIAQAAAA==.',
He='Heelorestus:BAABNQAECn8jAAMQAAgKBRTVJwDsAQAQAAgKBRTVJwDsAQACAAQKJAWU2ACeAAAAAA==.Hellbreed:BAAANQADCgIIAgAAAA==.',
Ho='Holix:BAAANQADCgEIAQAAAA==.Holyfrog:BAABNQAECn82AAIIAAoKbRUIHAB+AQAIAAoKbRUIHAB+AQAAAA==.Holythis:BAABNQAECn82AAIVAAoKTRxdEACYAgAVAAoKTRxdEACYAgAAAA==.',
If='Ifrit:BAAANQAECgcIBQAAAA==.',
Ig='Ignis:BAABNQAECn8tAAMWAAkK5Q2WFwB/AQAWAAcKLA6WFwB/AQARAAkK1QtGJgBjAQAAAA==.',
In='Infiltrata:BAABNQAECn84AAIOAAoKxhpbAgBfAgAOAAoKxhpbAgBfAgAAAA==.Injunjoe:BAAANQAECgQIBAAAAA==.',
Io='Io:BAABNQAECn8hAAIEAAoKDyFlDABPAwAEAAoKDyFlDABPAwAAAA==.',
Is='Ishida:BAAANQAECgEIAQAAAA==.',
Ja='Janelik:BAAANQAECgYIEAAAAA==.',
Ji='Jimihendrix:BAAANQAECgYIBgAAAA==.',
Jo='Jofixit:BAABNQAECn8xAAIXAAkKTBpuFwC9AQAXAAkKTBpuFwC9AQAAAA==.',
Ju='Judgemedaddy:BAAANQAECgEIAQAAAA==.',
Ka='Kanda:BAACNQAFFH8FAAIXAAMKTgqHCADhAAAXAAMKTgqHCADhAAA1AAQKfxcAAhcACgpsGmouAOICABcACgpsGmouAOICAAAA.Kasunas:BAABNQAECn8uAAIJAAoKsBnkKQCCAQAJAAoKsBnkKQCCAQAAAA==.Kaynub:BAAANQAECgEIAQABNQAECgoKNQAYAIkeAA==.',
Ke='Kealthas:BAAANQAECgYIDgAAAA==.Kedri:BAABNQAECn9EAAIXAAoKQBZbBgBlAgAXAAoKQBZbBgBlAgAAAA==.Keihas:BAAANQAECgcIEQAAAA==.Kermitt:BAAANQAECgMIAwAAAA==.',
Ki='Kikko:BAACNQAFFH8IAAISAAMKixxjFwAJAQASAAMKixxjFwAJAQA1AAQKfyYAAhIACQppJNIcAB0DABIACQppJNIcAB0DAAAA.Kikkomouse:BAAANQAECgUICAABNQAFFAMICAASAIscAA==.',
Ko='Kobane:BAAANQAECgEIAQAAAA==.Konkine:BAAANQABCgEIAQAAAA==.',
Ku='Kujara:BAAANQADCgMIAwAAAA==.Kurando:BAAANQAECggICAABNQAECgoKLgAJALAZAA==.Kurrindor:BAABNQAECn8gAAMVAAgK6B+0EACTAgAVAAgK6B+0EACTAgAJAAEKIR5/gwFVAAAAAA==.',
Ly='Lylith:BAAANQADCggIFAAAAA==.',
Ma='Macheon:BAAANQAECgEIAQAAAA==.Madashell:BAAANQADCgcIDAAAAA==.Maerwyn:BAAANQADCggJDQAAAA==.Magenub:BAABNQAECn81AAIYAAoKiR66NAAgAwAYAAoKiR66NAAgAwAAAA==.Malexling:BAABNQAECn8hAAIJAAcKFBYLJACTAQAJAAcKFBYLJACTAQAAAA==.Masa:BAACNQAFFH8GAAIMAAMK3RkvAgCPAAAMAAMK3RkvAgCPAAA1AAQKfyUAAgwACgq3HvQGAPECAAwACgq3HvQGAPECAAAA.Matt:BAAANQAECgEIAQAAAA==.Mawe:BAAANQAECgEJAgAAAA==.',
Mi='Mistie:BAAANQABCgIIAgABNQAECgUJDAAZAAAAAA==.Mistlee:BAAANQAECgEIAgAAAA==.Mitternacht:BAABNQAECn9FAAISAAoKpRwbBQAlAgASAAoKpRwbBQAlAgAAAA==.',
Mo='Moggo:BAAANQADCgQIBwAAAA==.Moodew:BAABNQAECn8lAAIDAAgKxRZ0EADUAQADAAgKxRZ0EADUAQAAAA==.',
Ms='Msdeath:BAABNQAECn8iAAIRAAcKch/cAgAVAgARAAcKch/cAgAVAgAAAA==.',
My='Mya:BAAANQABCgQIBwAAAA==.Mykeroni:BAAANQADCgMIAwAAAA==.Myraku:BAAANQADCggIDAABNQAECgUIEgAZAAAAAA==.',
Na='Nachiko:BAAANQADCgMIAwAAAA==.Naois:BAAANQAECgQICQABNQAECgoKLgAJALAZAA==.Nashalion:BAABNQAECn8cAAMHAAoKrRUtDACmAQAHAAoKrRUtDACmAQAEAAEK8gGc5QAZAAAAAA==.',
Ni='Nickchurch:BAAANQAECgIIAgAAAA==.Nidorhina:BAAANQABCgQIAwAAAA==.',
No='Nodarf:BAABNQAECn8rAAIaAAkKZQ7KBABiAQAaAAkKZQ7KBABiAQAAAA==.Norielin:BAAANQADCgQIBwAAAA==.',
Ok='Okayheals:BAABNQAECn8wAAIDAAkKwQoLPwDuAAADAAkKwQoLPwDuAAAAAA==.',
Ol='Olumine:BAAANQAECgEIAQAAAA==.',
Or='Orin:BAAANQADCgUIBgAAAA==.',
Pa='Panda:BAACNQAFFH8YAAQXAAcKch32DgBoAQATAAQKLR3TAAB6AQAXAAQKkRr2DgBoAQAbAAMKOA3RFgDUAAA1AAQKfzYABBsACgq7Je0ZAIcCABMACAoKJYYEAJkCABsACAqHIe0ZAIcCABcACQq6IMJOAIICAAAA.',
Pi='Picolás:BAABNQAECn8cAAIYAAYKHBiIegDKAAAYAAYKHBiIegDKAAAAAA==.',
Pr='Preacharound:BAAANQABCgMIAwAAAA==.Primrose:BAABNQAECn8fAAICAAoKthqaOACGAgACAAoKthqaOACGAgAAAA==.Probono:BAABNQAECn8UAAIQAAcKHghMFADoAAAQAAcKHghMFADoAAAAAA==.',
Qu='Quarian:BAAANQADCggICAAAAA==.',
Qw='Qwing:BAAANQAECgUIBgABNQAECgoKHAAHAK0VAA==.',
Ra='Rainee:BAAANQADCgQIAwAAAA==.Raxefal:BAABNQAECn8iAAQGAAgKEA4cTADvAAAGAAYKyAwcTADvAAALAAMKjgn7RwCoAAAKAAMKfw3SCQCGAAAAAA==.',
Re='Reptar:BAAANQAECgYICgABNQAFFAYIGQAcABQcAA==.Restdrag:BAAANQADCgYIBgAAAA==.Rezø:BAABNQAECn8vAAMCAAoK3RqHBADQAgACAAoK3RqHBADQAgAQAAcKgxWGKgDTAQAAAA==.',
Ro='Roadkilldk:BAABNQAECn8WAAMHAAcKSQxlUwBiAQAHAAcKSQxlUwBiAQAEAAEKxwJ04gAcAAAAAA==.',
['Rä']='Rägæ:BAAANQADCgYICAAAAA==.',
Sa='Sableye:BAABNQAECn8sAAIdAAoKfRewFQC2AgAdAAoKfRewFQC2AgAAAA==.Saguero:BAEBNQAECn8tAAMDAAoK8xY7PQBrAgADAAkKyxg7PQBrAgASAAkKog7gaADmAQAAAA==.Satmorii:BAAANQABCggIEQAAAA==.',
Sc='Schatten:BAAANQAECgUIBQABNQAECggIGAAMAP8YAA==.Schithappens:BAAANQABCgMIAwAAAA==.Scruffy:BAAANQAECgEIAQAAAA==.',
Se='Selina:BAAANQAECgcIDQAAAA==.Senortickle:BAAANQAECggIDQAAAA==.',
Sh='Shaunara:BAAANQAECgEIAQABNQAFFAMIBgAEACcfAA==.Shinoitamis:BAAANQAECggICgABNQAECgkJQQAJAIUfAA==.Shinotenshi:BAABNQAECn9BAAIJAAkKhR9QJAA0AwAJAAkKhR9QJAA0AwAAAA==.Shìva:BAAANQADCggICAAAAA==.Shînon:BAAANQAECgMIAwABNQAECgoKLwACAN0aAA==.',
Si='Siphin:BAAANQAECggICQAAAA==.',
So='Solàire:BAABNQAECn8rAAMIAAkKHwoRfwCcAQAIAAkKHwoRfwCcAQAJAAUKcAlefADRAAAAAA==.Sonicice:BAAANQADCgQIAQAAAA==.',
Sp='Spacewafflez:BAAANQAECgIIAgAAAA==.',
St='Starburnz:BAAANQADCgMIAwABNQAECgoKJwAFAEoaAA==.Stimutax:BAAANQAECgIIAwAAAA==.',
Ta='Tamborine:BAAANQADCgIIAgAAAA==.Taurenvar:BAABNQAECn80AAIeAAoKeiA+AgCKAwAeAAoKeiA+AgCKAwAAAA==.',
Te='Teddyhappy:BAAANQAECgEIAQAAAA==.',
Th='Thekeres:BAAANQAECgQIBAAAAA==.',
To='Tora:BAAANQAECgYJBgAAAA==.',
Tr='Trollbrudda:BAABNQAECn9BAAMcAAoKLCAfBAAiAgAcAAoKLCAfBAAiAgARAAMKuBeHPwC9AAAAAA==.',
Um='Umgross:BAAANQADCgYIBgAAAA==.',
Un='Unholygrudge:BAAANQADCgIIAgAAAA==.',
Ve='Velenus:BAAANQAFFAEIAQAAAA==.Vesperion:BAAANQADCgQICgAAAA==.',
Vi='Vilehatred:BAAANQAECgIIAwAAAA==.',
Vo='Voltz:BAAANQADCggIEAAAAA==.',
Wa='Wallis:BAAANQAECgYIDQAAAA==.Warmoz:BAABNQAECn8YAAIMAAgK/xgAEAApAgAMAAgK/xgAEAApAgAAAA==.',
Wu='Wunhunglo:BAAANQABCgQIBAAAAA==.',
Xe='Xergiator:BAABNQAECn8lAAIXAAgKIwh7uwCMAQAXAAgKIwh7uwCMAQAAAA==.',
Za='Zaligator:BAABNQAECn8iAAQfAAcKUxXBDACGAQAgAAcKGRSAGADAAQAfAAcKvBHBDACGAQAhAAEK8ggUJQAqAAAAAA==.Zarideyne:BAAANQAECgEIAQAAAA==.',
Zo='Zombinized:BAAANQADCgUIBQAAAA==.',
Zu='Zuulian:BAABNQAECn8nAAQFAAoKShoQBADXAQAFAAoKShoQBADXAQAPAAEKAAD9dAAkAAAiAAEKAAD8NAAjAAAAAA==.',
Zy='Zylph:BAAANQAECgUIEgAAAA==.',
['Ín']='Ínnothule:BAAANQAECgMIAwAAAA==.',
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
