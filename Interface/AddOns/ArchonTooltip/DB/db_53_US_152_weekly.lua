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

local lookup = {'DemonHunter-Havoc','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Priest-Shadow','Priest-Holy','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Shaman-Enhancement','Hunter-Marksmanship','Mage-Frost','Warrior-Protection','Paladin-Protection','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Rogue-Assassination','Druid-Guardian','DemonHunter-Devourer','Priest-Discipline','Druid-Balance','Evoker-Devastation','Warlock-Affliction','Druid-Feral','Druid-Restoration','Hunter-Survival',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaylasecura:BAABNQAECoEqAAIBAAkKuR6vDgAYAwABAAkKuR6vDgAYAwAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAgIGgACAM0aAA==.Absinth:BAABNQAECoEYAAMDAAgKLAwbVwB1AQADAAgKyQsbVwB1AQAEAAEKpgVSnQAmAAAAAA==.',
Ai='Aidaric:BAAANQADCgUJBQAAAA==.Airfriend:BAABNQAECoEuAAMFAAkK+xFPSgANAgAFAAkK+xFPSgANAgAGAAUKXhuyhABoAQAAAA==.',
Al='Alder:BAAANQAECgUICwAAAA==.Alphard:BAABNQAECoEhAAIHAAgKOB57CwCuAgAHAAgKOB57CwCuAgAAAA==.',
An='Anelowyn:BAABNQAECoEhAAMIAAgKaxL2IQD/AQAIAAgKaxL2IQD/AQAJAAcKtwZShABQAQAAAA==.Angrychicken:BAAANQADCgQICQAAAA==.',
Ap='Apocal:BAACNQAFFIEJAAIKAAYKWRS1AADGAQAKAAYKWRS1AADGAQA1AAQKgSQAAgoACQqfIs4BAGgDAAoACQqfIs4BAGgDAAAA.',
Ar='Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAAANQAECgYICQAAAA==.Asmozaps:BAABNQAECoEaAAIGAAkKwA5HUgACAgAGAAkKwA5HUgACAgAAAA==.',
At='Ataraxya:BAAANQADCgYIBgAAAA==.',
Az='Aziel:BAABNQAECoEWAAMLAAkKkgqtjgDQAQALAAkK8AmtjgDQAQAMAAEKcw2LKgBAAAAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAABNQAECoEVAAIGAAcK/A9LagCxAQAGAAcK/A9LagCxAQAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQAECgIIAgAAAA==.Bih:BAAANQADCgMIAwAAAA==.Bikerm:BAAANQAECgEIAQABNQAFFAYIGAAKAHkgAA==.Billiards:BAAANQADCggICAABNQAECggIIAANAF0WAA==.Birgetta:BAAANQADCggICAABNQAECggIGwABANcFAA==.',
Bl='Blitzkrieged:BAAANQAECggICAAAAA==.Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECoElAAIOAAgKLB10SgCOAgAOAAgKLB10SgCOAgAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAABNQAECoEjAAIPAAkKAA2EEADAAQAPAAkKAA2EEADAAQAAAA==.Bownir:BAAANQAECgYIEAAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAABNQAECoEhAAMQAAkKeBOSHQAcAgAQAAkKeBOSHQAcAgARAAMKKBBuMgCuAAAAAA==.',
Bu='Bubonic:BAAANQAECgUIDgAAAA==.Buenasalud:BAAANQAECgYIDgAAAA==.',
Ca='Catopriest:BAAANQAECgYICAAAAA==.Caylea:BAACNQAFFIENAAILAAUKexGhDgCZAQALAAUKexGhDgCZAQA1AAQKgSUAAgsACQquH4IpAAMDAAsACQquH4IpAAMDAAAA.',
Ch='Chalis:BAABNQAECoEZAAMCAAcKqR9WFgCyAQACAAQK7iRWFgCyAQASAAUKtBsXkACPAQAAAA==.',
Cl='Clamsquirter:BAABNQAECoEWAAMFAAgKhxsLMgByAgAFAAgKhxsLMgByAgATAAIKtQk/KgB0AAAAAA==.Clanis:BAAANQAECgMIAwABNQAFFAUIDQAUAEscAA==.',
Co='Coldhwip:BAABNQAECoEmAAMVAAgKnBhlDQCrAQANAAcKChhDtwDyAQAVAAYKNhZlDQCrAQAAAA==.',
Cr='Crash:BAACNQAFFIEGAAILAAQKgwg4GAAZAQALAAQKgwg4GAAZAQA1AAQKgSYAAgsACQrcHDhDAKcCAAsACQrcHDhDAKcCAAAA.Crtaker:BAAANQAECgcICAAAAA==.Crushfoot:BAAANQADCgUIBQAAAA==.Crysis:BAABNQAECoEmAAIWAAgKrhshCgB4AgAWAAgKrhshCgB4AgAAAA==.',
Cu='Cuahtemoc:BAAANQADCgYIDQAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAABNQAECoEhAAMOAAgKWh9/PwCxAgAOAAgKWh9/PwCxAgAXAAQKWA4MSQCeAAAAAA==.Dagda:BAAANQAECgIIAgAAAA==.Danye:BAAANQAECgMIBgAAAA==.Darknasti:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.',
De='Decease:BAAANQAECgQIBAABNQAECgkJIwASAHojAA==.Delium:BAACNQAFFIEQAAINAAUK/BOLFgCbAQANAAUK/BOLFgCbAQA1AAQKgSMAAg0ACQozIoAzABcDAA0ACQozIoAzABcDAAAA.Demonmommy:BAAANQAECgUICgAAAA==.Deäthrose:BAABNQAECoEnAAMGAAkKpRFmWgDlAQAGAAgK8BBmWgDlAQAFAAgKCAk9fgBjAQAAAA==.',
Di='Die:BAAANQAECgYICgAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQADCgQIBgAAAA==.',
Do='Doadin:BAABNQAECoElAAIYAAgKJhgiOwBbAgAYAAgKJhgiOwBbAgAAAA==.Dolphus:BAAANQAECggICAAAAA==.Doominatrix:BAABNQAECoElAAISAAkKvRHQVgAwAgASAAkKvRHQVgAwAgAAAA==.Dotem:BAAANQAECgIIAgAAAA==.',
Dr='Draggum:BAAANQADCggIDQABNQAECggIJQAOAPgeAA==.Dreadlocky:BAABNQAECoEZAAMCAAcKBxQwEgDaAQACAAcKBxQwEgDaAQASAAIKcQTHGgFFAAAAAA==.Dreadmagey:BAAANQADCggICQABNQADCgYIDAAZAAAAAA==.Dreadraven:BAAANQADCgYIDAAAAA==.Dreven:BAAANQADCggICAABNQAECgYIDwAZAAAAAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAAANQAFFAEIAQAAAA==.',
Du='Dunktars:BAABNQAECoEgAAILAAkKox1zNwDPAgALAAkKox1zNwDPAgAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQADCggIFgABNQAECggIIAANAF0WAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAZAAAAAA==.Elisha:BAABNQAECoFLAAIOAAgKmhLWhQDpAQAOAAgKmhLWhQDpAQAAAA==.',
Er='Erebostro:BAABNQAECoEhAAIaAAgKlhoRPQCPAgAaAAgKlhoRPQCPAgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgQICQAAAA==.Fathercow:BAAANQAECgMIAwAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAABNQAECoEoAAITAAkKmB+RBABBAwATAAkKmB+RBABBAwAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferdinand:BAAANQADCgcIBwABNQAECgcIEAAZAAAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECoEuAAMSAAkK7yIhKwC/AgASAAcKNyMhKwC/AgACAAIK9SFpPgC+AAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAFFAIIAgAZAAAAAA==.',
Fu='Furina:BAAANQAECgIIAgAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
Ga='Galaxsea:BAABNQAECoEaAAIQAAgKix3VEgCjAgAQAAgKix3VEgCjAgAAAA==.Gale:BAAANQADCgYIBwABNQAECgYIEwAZAAAAAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAAANQAECgcIDwAAAA==.',
Gh='Ghostfreak:BAABNQAECoEaAAIbAAgK3xX2JgAmAgAbAAgK3xX2JgAmAgAAAA==.',
Gi='Giren:BAAANQAECggIBwABNQAFFAYIFgAOAFkiAA==.',
Go='Gobø:BAAANQADCgEIAQAAAA==.Gooby:BAAANQAECgYIDwAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAAANQAECgUIDgAAAA==.Haranjer:BAABNQAECoEeAAIQAAgK9BpjFQCBAgAQAAgK9BpjFQCBAgAAAA==.',
He='Hefferhumper:BAABNQAECoEWAAIcAAYKNxLiHwBXAQAcAAYKNxLiHwBXAQAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAYIFQANANceAA==.Homslam:BAABNQAECoEQAAMLAAgKMBzjdAAVAgALAAcKwxfjdAAVAgAWAAQKpRp/IQASAQABNQAFFAYIFQANANceAA==.Homsorc:BAACNQAFFIEVAAMNAAYK1x5SBgA3AgANAAYKeB5SBgA3AgAVAAEKDSBKCQBeAAA1AAQKgSYAAg0ACQo1JvQCAN8DAA0ACQo1JvQCAN8DAAAA.Homstab:BAABNQAECoEeAAMHAAkKih+JEABjAgAHAAcK/B2JEABjAgAbAAIK+SSSYgDZAAABNQAFFAYIFQANANceAA==.Homtard:BAAANQAECgQIBQABNQAFFAYIFQANANceAA==.Homtotem:BAAANQADCggICAABNQAFFAYIFQANANceAA==.Homwiz:BAAANQAECgQIBgAAAA==.Hope:BAABNQAECoEfAAIYAAgK4BKUVQD4AQAYAAgK4BKUVQD4AQAAAA==.',
Ic='Iced:BAAANQADCgIIAgABNQAECggIFgAIAIMZAA==.Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAUIDQAUAEscAA==.',
Il='Illiandray:BAABNQAECoEeAAICAAgKUBoPBwCMAgACAAgKUBoPBwCMAgAAAA==.',
In='Insomniac:BAABNQAECoEgAAIdAAgKJCOCCQA0AwAdAAgKJCOCCQA0AwAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUICwAAAA==.Jake:BAAANQAECgQICAAAAA==.Jangaballs:BAAANQAECgUICwAAAA==.Jawndie:BAABNQAECoEhAAMRAAgKRBqKEABMAgARAAgKRBqKEABMAgAPAAEKOQkQMAAjAAAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAAANQAECgEJAQABNQAECggIIwAeAEAgAA==.',
Ka='Kaalg:BAAANQADCgYIBgAAAA==.Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECoErAAIEAAkKtiI7BgBtAwAEAAkKtiI7BgBtAwAAAA==.Kassa:BAAANQADCggIEQAAAA==.',
Ke='Keeah:BAAANQAECgUIEAAAAA==.Kestra:BAABNQAECoEmAAIRAAgK5wePIQBQAQARAAgK5wePIQBQAQAAAA==.',
Ki='Kittysprigg:BAAANQAECgcIEgAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFIENAAIUAAUKSxwRBwC1AQAUAAUKSxwRBwC1AQA1AAQKgSIAAhQACArhIbsWAI4CABQACArhIbsWAI4CAAAA.',
Ku='Kurty:BAAANQADCgUIBQAAAA==.',
Kw='Kwickin:BAAANQAECgQIBQABNQAECggIJQAOAPgeAA==.',
Ky='Kyreen:BAAANQAECgUIEAAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECggIGgAQAIsdAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAABNQAECoEoAAINAAkKRBYFfwBoAgANAAkKRBYFfwBoAgAAAA==.',
Lu='Lukafox:BAAANQAECgUIDAAAAA==.Lunastarvale:BAABNQAECoEXAAIaAAgKdBA/awAQAgAaAAgKdBA/awAQAgAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAABNQAECoEmAAMFAAgK6iNADwA0AwAFAAgK6iNADwA0AwAGAAYK0AZrqQASAQAAAA==.Madith:BAAANQAECgQICgAAAA==.Maintarget:BAABNQAECoEWAAIIAAgKgxkfGQBlAgAIAAgKgxkfGQBlAgAAAA==.Malefisico:BAAANQAECgcIEAAAAA==.Mardríft:BAABNQAECoEkAAIfAAkK/ByzGQDgAgAfAAkK/ByzGQDgAgAAAA==.Marero:BAAANQADCgYICgAAAA==.Martyr:BAABNQAECoEdAAIgAAgK9A7TFADgAQAgAAgK9A7TFADgAQAAAA==.Mazga:BAABNQAECoEfAAIFAAgKQQ86aAClAQAFAAgKQQ86aAClAQAAAA==.',
Mc='Mcflury:BAAANQADCgYICwAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECoEqAAIRAAgKExMAFgDtAQARAAgKExMAFgDtAQAAAA==.Monstermayi:BAABNQAECoEkAAMMAAgKvxW2CAAsAgAMAAgKvxW2CAAsAgALAAIK8gsuFwFwAAAAAA==.Mooknight:BAABNQAECoEhAAIDAAgK/ArDVAB/AQADAAgK/ArDVAB/AQAAAA==.Morgoth:BAAANQAECgQIEgAAAA==.Morteesha:BAAANQAECgEIAQABNQAECggIIQARAEQaAA==.',
Mu='Muggy:BAABNQAECoEhAAIbAAgKtRHFKQATAgAbAAgKtRHFKQATAgAAAA==.',
My='Myrothar:BAAANQADCggICAAAAA==.Mytastical:BAAANQAECgMIBgAAAA==.',
['Må']='Måzikeen:BAAANQADCgMIAwABNQAECggIJgAFAOojAA==.',
Na='Najwah:BAABNQAECoEYAAMJAAkKQB2wEQAmAwAJAAkKQB2wEQAmAwAIAAIKBhO4VwB6AAAAAA==.Namalis:BAABNQAECoEjAAMSAAkKeiNVFwAWAwASAAgKzyNVFwAWAwACAAMKyRbAOgDLAAAAAA==.Nanielito:BAABNQAECoEbAAINAAkKuxgBbACRAgANAAkKuxgBbACRAgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDgAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECggIIAANAF0WAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAABNQAECoEXAAIaAAgKoRQlVQBJAgAaAAgKoRQlVQBJAgAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAABNQAECoEXAAIhAAcKEhrZBQA4AgAhAAcKEhrZBQA4AgABNQAECgkJKwAJABgWAA==.Nosliw:BAAANQAECggICAAAAA==.Noxilis:BAAANQAECgQICAABNQAECgkJLAALACkPAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgcIDQAAAA==.',
Om='Omegá:BAAANQAECggIEQABNQAECggIGAADACwMAA==.',
Op='Optìmusprìme:BAABNQAECoEdAAIWAAgKSBgxDgAeAgAWAAgKSBgxDgAeAgAAAA==.',
Or='Ordovic:BAAANQADCgUIBQAAAA==.',
Pa='Pandemic:BAABNQAECoEWAAIaAAgKug91jADAAQAaAAgKug91jADAAQAAAA==.Papa:BAABNQAECoEmAAQhAAkKHRVjDwAwAQAhAAUK0A5jDwAwAQACAAQKshaAKgAdAQASAAQKmxR9yAALAQAAAA==.Pawfu:BAABNQAECoEhAAQQAAgKVBb0HgANAgAQAAgKVBb0HgANAgARAAYK3QvZJgAVAQAPAAIKmAn8JgBoAAAAAA==.',
Pe='Penywize:BAAANQAECgYIEQAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgEIBAAAAA==.',
Po='Pockets:BAABNQAECoEgAAINAAgKXRYelAA7AgANAAgKXRYelAA7AgAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECoEjAAIeAAgKQCAfAgD2AgAeAAgKQCAfAgD2AgAAAA==.',
Pu='Purge:BAAANQAECgIIBAAAAA==.',
Qr='Qrazi:BAABNQAECoEaAAIGAAgKjBINVQD4AQAGAAgKjBINVQD4AQAAAA==.',
Qu='Quick:BAAANQAECgQICQABNQAECggIJQAOAPgeAA==.',
Ra='Ratha:BAABNQAECoEoAAIXAAkKyyGNBQA/AwAXAAkKyyGNBQA/AwAAAA==.Ravincible:BAAANQADCggIFgAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFIEWAAMHAAcK2SCQAwD0AQAHAAUK0h+QAwD0AQAbAAMKtyHCCQAVAQA1AAQKgScAAwcACQr9JecFAB4DAAcACAr6JecFAB4DABsABwokI3EUALUCAAAA.Rokkgar:BAAANQAECgcIEwAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAAANQAECggIEQAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAABNQAECoEYAAIJAAcKNRm2VgDwAQAJAAcKNRm2VgDwAQAAAA==.',
Sc='Scared:BAACNQAFFIEKAAIJAAUK0QkbDwB5AQAJAAUK0QkbDwB5AQA1AAQKgTwAAgkACQrwITIJAGgDAAkACQrwITIJAGgDAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECoEeAAQiAAcKQRu4DQAGAgAiAAYKKR64DQAGAgAjAAcKQBWwJgC8AQAcAAIKHQt3RQBOAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgIIBAABNQAECgMIAwAZAAAAAA==.Shmadu:BAABNQAECoEbAAIaAAkKVCQzAwDKAwAaAAkKVCQzAwDKAwAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.Shockk:BAAANQAECgQIBQAAAA==.',
So='Soola:BAAANQADCggICAABNQAECgkJKAAXAMshAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stonedpriest:BAAANQAECgQIBgAAAA==.',
Su='Surrëal:BAABNQAECoEbAAIBAAgK1wWGUgAOAQABAAgK1wWGUgAOAQAAAA==.',
Sw='Sweetmask:BAAANQAECgMIAwAAAA==.',
Sy='Sybela:BAAANQABCgYIDAABNQAECgkJIwAJAAgcAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAABNQAECoEhAAIVAAgKFx4wBQCeAgAVAAgKFx4wBQCeAgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgkJKAAGAKQeAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgkJKAAGAKQeAA==.Tanidgetotem:BAABNQAECoEoAAIGAAkKpB6WGgASAwAGAAkKpB6WGgASAwAAAA==.',
Te='Teias:BAABNQAECoErAAMJAAkKGBbjQABCAgAJAAkKGBbjQABCAgAIAAMKnxdQSQDNAAAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgUIBgABNQAECgkJKwAJABgWAA==.',
To='Torvald:BAAANQADCggICAABNQAECggICAAZAAAAAA==.',
Tr='Tricko:BAABNQAECoEfAAIaAAgK/h4NKgDQAgAaAAgK/h4NKgDQAgAAAA==.Trickshots:BAAANQADCgMIAwABNQAECggIIAANAF0WAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAABNQAECoEeAAINAAcKqxeXsgD7AQANAAcKqxeXsgD7AQAAAA==.Trollzy:BAABNQAECoEhAAMTAAgKXhYkDwBdAgATAAgKXhYkDwBdAgAFAAIKIAPv9ABOAAAAAA==.Trunkmonkey:BAABNQAECoEZAAISAAcK+BYlbADyAQASAAcK+BYlbADyAQAAAA==.Trunky:BAAANQADCgMJBgAAAA==.',
Ts='Tsaagan:BAABNQAECoElAAISAAkKrB83HgD2AgASAAkKrB83HgD2AgAAAA==.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECggIJgAWAK4bAA==.',
Ur='Urthalos:BAAANQAECgYIBgAAAA==.',
Va='Valica:BAAANQADCgUIBQAAAA==.Valiithria:BAAANQAECgEIAQAAAA==.Valkyruid:BAAANQAFFAEIAgAAAA==.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.',
Vu='Vulgan:BAAANQADCgcICAAAAA==.',
Wa='Warriorchin:BAAANQAECgQIBAABNQAFFAcIFgAHANkgAA==.Waywatcher:BAAANQAECgQICAAAAA==.',
Wh='Whiilow:BAAANQAECgcIEAAAAA==.',
Wu='Wullgan:BAABNQAECoEXAAIJAAcKKRoKSgAgAgAJAAcKKRoKSgAgAgAAAA==.',
Xe='Xencure:BAAANQAFFAEIAQAAAA==.Xerk:BAAANQAECgcIBwABNQAECgcIDQAZAAAAAA==.',
Xy='Xyrna:BAABNQAECoEeAAIkAAgKoB0wAwDFAgAkAAgKoB0wAwDFAgABNQAECgkJKAAXAMshAA==.',
Ya='Yareli:BAABNQAECoEeAAIKAAgKDwa6FAAuAQAKAAgKDwa6FAAuAQAAAA==.',
Yo='Youngdoug:BAAANQADCgUIBQAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAAANQAECgYIDwAAAA==.',
Ze='Zeleck:BAAANQAECgYIDwAAAA==.Zeno:BAACNQAFFIEWAAIOAAYKWSK3AQBqAgAOAAYKWSK3AQBqAgA1AAQKgSgAAg4ACQqwJQoPAIIDAA4ACQqwJQoPAIIDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAAANQAECgcIEwABNQAECgcIEwAZAAAAAA==.',
Zi='Zinbar:BAAANQAECgYIDQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECgkJKAANAEQWAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAAANQAECgYIEwAAAA==.',
['Çl']='Çloud:BAAANQAECgIIAwAAAA==.',
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
