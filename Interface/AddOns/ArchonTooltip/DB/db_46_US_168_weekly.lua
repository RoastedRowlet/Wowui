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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Protection','Unknown-Unknown','Mage-Frost','Mage-Arcane','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','Monk-Brewmaster','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Warlock-Demonology','Hunter-Marksmanship','Warrior-Fury','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Shaman-Elemental','DemonHunter-Havoc','Hunter-Survival','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Warlock-Destruction','Mage-Fire','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AnWOADDAAABAAQJ+AnWOADDAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgAECgEJAQAAAA==.',
Al='Alerra:BAAALgAECgEJAgAAAA==.Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAABLgAECn8aAAIEAAkJGhxvEABhAQAEAAkJGhxvEABhAQAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.Antiosto:BAEALgAECgEJAQAAAA==.',
Ar='Arana:BAAALgAECgUJCAAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIFAAkJlQq7HQAnAQAFAAkJlQq7HQAnAQABLgAECgEJAQAGAAAAAA==.Arkadias:BAAALgAECgEJAwAAAA==.Arrakai:BAAALgAECgEJAgAAAA==.Arthea:BAABLgAECn8YAAMHAAkJjQeFxAADAQAHAAkJnQaFxAADAQAIAAUJ0QWdEQCpAAAAAA==.',
As='Asmmina:BAABLgAECn8lAAIEAAkJDgthUACxAQAEAAkJDgthUACxAQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8pAAIJAAkJxg/lFAAqAQAJAAkJxg/lFAAqAQAAAA==.',
Az='Azalan:BAAALgAECgEJAQAAAA==.Azarit:BAAALgAECgUJCgAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgQJBAAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIKAAkJghJPIADAAQAKAAkJghJPIADAAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAILAAkJcSJrCQAkAwALAAkJcSJrCQAkAwAAAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJBAABLgAFFAQJDQAMAIkcAA==.Bastiecats:BAAALgADCgcJBwAAAA==.',
Be='Beatrixx:BAAALgAECgkJDwAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bi='Bitterman:BAAALgAECgUJBQABLgAFFAYJIQANAFAZAA==.',
Bl='Bllackout:BAACLgAFFH8OAAIJAAQJhRtYMgDHAAAJAAQJhRtYMgDHAAAuAAQKfxcAAgkACQluIWouAEcCAAkACQluIWouAEcCAAAA.Bllacktotem:BAAALgAFFAIJAgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8nAAIOAAkJvR7/BgCtAgAOAAkJvR7/BgCtAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bloodwynn:BAAALgAECgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRoREABLAgACAAkJsRoREABLAgAPAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQALAIUcAA==.Bowdinn:BAAALgAECgEJAQABLgAECggJKQAQAGsWAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgMJBQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMRAAkJeRY+GADYAQARAAkJeRY+GADYAQASAAIJdQupHQA/AAABLgAFFAMJBQAEAOEOAA==.',
Ca='Capnburr:BAAALgAECgQJBAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAACLgAFFH8FAAITAAIJQQ4lPwBWAAATAAIJQQ4lPwBWAAAuAAQKfxgAAhMACQnrCqRWAFwBABMACQnrCqRWAFwBAAAA.Cheese:BAABLgAECn8eAAMCAAcJvxtTGgDeAQACAAcJvxtTGgDeAQABAAQJPxI+agDYAAAAAA==.Cheesemix:BAABLgAECn8bAAITAAYJXg1SbgARAQATAAYJXg1SbgARAQABLgAECgkJRgATAMYhAA==.Chesleigh:BAABLgAECn8YAAIHAAQJ8AwhJgC4AAAHAAQJ8AwhJgC4AAAAAA==.Chickenchokr:BAAALgAECgEJAwAAAA==.',
Ci='Cinderlight:BAABLgAECn8wAAIJAAkJ8BElWADDAQAJAAkJ8BElWADDAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Cortock:BAAALgAECggJDQABLgAFFAYJIQAHAHEOAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozychai:BAAALgADCgIJAgAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAFFAQJEAAHAD8SAA==.Crilynn:BAACLgAFFH8TAAIHAAUJERL4YAAfAQAHAAUJERL4YAAfAQAuAAQKfyQAAgcACQlOGKA2AD4CAAcACQlOGKA2AD4CAAAA.Crispycrittr:BAABLgAECn8eAAMUAAgJiAdbJQBMAQAUAAgJiAdbJQBMAQAVAAEJwwL6KgAiAAAAAA==.Crotchcriter:BAAALgAECgEJAgAAAA==.Cryhavoc:BAABLgAECn8mAAIWAAkJQBSMDACMAQAWAAkJQBSMDACMAQAAAA==.',
Cy='Cyssor:BAAALgAECgQJDQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAABLgAECn8bAAIEAAYJ5ArKHwDZAAAEAAYJ5ArKHwDZAAAAAA==.Dathdeath:BAABLgAECn8kAAIXAAgJXA0nFwAeAQAXAAgJXA0nFwAeAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.Dezzii:BAAALgAECggJEQAAAA==.',
Di='Diddel:BAAALgADCgEJAQAAAA==.Dillapuss:BAAALgADCgMJBAAAAA==.Dimitri:BAAALgAECgEJAgAAAA==.Dirtnappzz:BAAALgAFFAEJAQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAILAAMJ7g1bLADqAAALAAMJ7g1bLADqAAAuAAQKfygAAgsACAm8IugYAOcCAAsACAm8IugYAOcCAAAA.',
Do='Docken:BAABLgAECn8WAAIYAAgJmhzDAQCgAgAYAAgJmhzDAQCgAgABLgAFFAQJEAAHAD8SAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJBAAAAA==.Dotdotded:BAAALgAECgkJDAAAAA==.Dotsomahan:BAABLgAECn8YAAIZAAkJWA/IXgCDAQAZAAkJWA/IXgCDAQAAAA==.Dottin:BAAALgADCgEJAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIaAAkJSRbmCQDVAQAaAAkJSRbmCQDVAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Draik:BAAALgAECgYJEAABLgAECggJKQAQAGsWAA==.Drandzug:BAABLgAECn8jAAIbAAgJ0ggGUQAFAQAbAAgJ0ggGUQAFAQAAAA==.Drift:BAAALgAFFAEJAQABLgAFFAQJEAAHAD8SAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAgAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgAECgEJAQAAAA==.',
El='Elementalhro:BAAALgAECgEJAQAAAA==.Elise:BAABLgAECn8ZAAIcAAcJGB83FwATAgAcAAcJGB83FwATAgAAAA==.Ellzik:BAABLgAECn8UAAMNAAcJ5wt/MwDbAAANAAcJ5wt/MwDbAAAcAAQJxAOUawBzAAAAAA==.Elosonia:BAAALgAECgEJAQAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgUJCgABLgAFFAQJDQAMAIkcAA==.',
Fa='Falorien:BAABLgAECn8pAAIHAAkJPhI7cACZAQAHAAkJPhI7cACZAQAAAA==.Fatherzombie:BAAALgAECgIJBAABLgAFFAYJIQANAFAZAA==.Fauxi:BAAALgAECgEJAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAACLgAFFH8GAAIdAAIJYQxQgAB+AAAdAAIJYQxQgAB+AAAuAAQKfycAAh0ACQnoFNpIAKwBAB0ACQnoFNpIAKwBAAAA.',
Fl='Flamingpax:BAABLgAECn8pAAQQAAgJaxaPAgClAQAQAAgJaxaPAgClAQAcAAIJ/A9EGQBeAAAeAAEJ+AWQJwAeAAAAAA==.Flamish:BAAALgADCgUJBQAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBwABLgAFFAYJIQAHAHEOAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbaked:BAAALgAECgQJBAABLgAFFAMJBgALAPMcAA==.Fluffinbunz:BAACLgAFFH8GAAILAAMJ8xwXgQAFAQALAAMJ8xwXgQAFAQAuAAQKfzUAAgsACQkxIvsPAOwCAAsACQkxIvsPAOwCAAAA.Fluffinhigh:BAABLgAECn8uAAUNAAkJbhs1CQBYAgANAAkJNho1CQBYAgAcAAcJYxl1NABHAQAeAAMJ9RXBggCzAAAQAAQJZxJyMACfAAABLgAFFAMJBgALAPMcAA==.Fluffinkai:BAAALgAECgQJCgABLgAFFAMJBgALAPMcAA==.Fluffybúnny:BAABLgAECn8bAAIWAAQJEBF5BQDBAAAWAAQJEBF5BQDBAAAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgEJAQAGAAAAAA==.Freakadeek:BAAALgAECgUJBQAAAA==.Fresnel:BAAALgAECgUJBgAAAA==.Fruitloopes:BAABLgAECn8dAAIHAAcJ1weYIADTAAAHAAcJ1weYIADTAAAAAA==.',
Fu='Furmir:BAAALgADCgQJBAABLgAFFAIJBgAdAGEMAA==.Furrious:BAAALgAECgQJBAAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAACLgAFFH8FAAIZAAIJ5AOtTwBhAAAZAAIJ5AOtTwBhAAAuAAQKfyAAAhkACAkmDWmBADYBABkACAkmDWmBADYBAAAA.',
Gi='Gillgallad:BAAALgAECgQJCQAAAA==.Gillneddra:BAAALgAECgIJAgAAAA==.Giorgina:BAACLgAFFH8KAAIfAAMJ5Q8SNQC6AAAfAAMJ5Q8SNQC6AAAuAAQKfycAAh8ACAnXF5knALABAB8ACAnXF5knALABAAAA.',
Gl='Glasc:BAABLgAECn8fAAMYAAgJCA7zNABCAQAYAAgJCA7zNABCAQAMAAYJ7Q2tRAD8AAAAAA==.',
Gn='Gnowances:BAAALgADCgkJEgAAAA==.',
Go='Goobynuk:BAACLgAFFH8PAAIHAAMJrQzFPwDHAAAHAAMJrQzFPwDHAAAuAAQKfyAAAgcACQkqGcc2AD0CAAcACQkqGcc2AD0CAAAA.Gornade:BAAALgAECgEJAQABLgAFFAYJIQANAFAZAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAMJBQAEAOEOAA==.Grevane:BAAALgAECgEJAgAAAA==.Grigorii:BAAALgAECgEJAgAAAA==.Grimli:BAAALgADCgYJBgAAAA==.Grimstone:BAABLgAECn8ZAAMRAAcJ1x2XGQA3AgARAAcJ3RyXGQA3AgASAAYJQhhNCwB3AQAAAA==.Groggu:BAAALgADCgYJBgAAAA==.',
Gu='Gutsdk:BAAALgAECgQJBAAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAFFAEJAgABLgAFFAYJKgAEALYSAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAGAAAAAA==.Invidia:BAAALgAECgEJAgAAAA==.',
It='Itzli:BAACLgAFFH8MAAIaAAQJmCCmDgB0AQAaAAQJmCCmDgB0AQAuAAQKfysAAhoACQnzIb8DAIoCABoACQnzIb8DAIoCAAEuAAUUBAkNAAwAiRwA.',
Iv='Ivee:BAABLgAFFH8FAAILAAMJWgigUAC2AAALAAMJWgigUAC2AAABLgAFFAQJDQAMAIkcAA==.',
Ix='Ixtli:BAAALgAECgYJCAABLgAFFAQJDQAMAIkcAA==.',
Ja='Janner:BAAALgAECgUJDAAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellibean:BAAALgAECgMJAgAAAA==.Jellybeane:BAAALgAECgQJEwAAAA==.Jesdei:BAABLgAECn8WAAIZAAgJ2wGEJQFDAAAZAAgJ2wGEJQFDAAAAAA==.',
Jg='Jgwentworth:BAABLgAFFH8FAAIJAAQJUw1KIwD+AAAJAAQJUw1KIwD+AAABLgAFFAUJDQACAAAJAA==.',
Jo='Jojen:BAABLgAECn8pAAMKAAkJuhivHQDXAQAKAAkJuhivHQDXAQAMAAQJ+AreZACIAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAwAAAA==.Kalaruun:BAAALgAECgEJAgAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgQJEwAAAA==.Kavix:BAABLgAECn8mAAIeAAkJSxbdIwAsAgAeAAkJSxbdIwAsAgAAAA==.Kayos:BAACLgAFFH8hAAIdAAYJXw0VKwDPAAAdAAYJXw0VKwDPAAAuAAQKfy8AAx0ACQm3GpEDABwCAB0ACQlUGpEDABwCACAABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAYJIQAdAF8NAA==.Kelwynd:BAAALgAECgEJAQAAAA==.Kelz:BAAALgAECgIJAgAAAA==.Kelzexx:BAABLgAECn8qAAIMAAkJ4hFEIADEAQAMAAkJ4hFEIADEAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAIOAAkJrwpJJgAhAQAOAAkJrwpJJgAhAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAABLgAFFH8GAAIHAAMJjQyKiQDGAAAHAAMJjQyKiQDGAAABLgAFFAQJDQAMAIkcAA==.Kimed:BAABLgAECn8cAAMHAAkJPQzdEQBGAQAHAAkJ+gvdEQBGAQAIAAMJjQ7gCQBbAAAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Kolcon:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krica:BAAALgADCgYJBgAAAA==.Krillian:BAAALgAECgEJBAAAAA==.',
Ku='Kula:BAABLgAECn8oAAIEAAkJHxBkEwA+AQAEAAkJHxBkEwA+AQAAAA==.Kungmoo:BAAALgAECgQJBAAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.Kuwata:BAAALgADCgcJBwAAAA==.',
Kv='Kvnknight:BAAALgAECgQJDwAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kyraes:BAAALgAECgMJAwABLgABCgMJAQAGAAAAAA==.Kytes:BAAALgADCgUJBQABLgAFFAQJEAAHAD8SAA==.',
La='Lajoie:BAAALgAECgQJBAABLgAFFAYJKgAEALYSAA==.Largetha:BAAALgAECgQJBQABLgAFFAQJDQAMAIkcAA==.Latro:BAACLgAFFH8qAAMEAAYJthLtHwAoAQAEAAYJthLtHwAoAQAhAAIJOgSkEwBuAAAuAAQKfysAAwQACQlrHHEpADgCAAQACQlrHHEpADgCABoAAQkIBcqSACcAAAAA.',
Le='Leenex:BAABLgAECn8YAAIZAAYJFQdFyQC+AAAZAAYJFQdFyQC+AAAAAA==.Leginer:BAABLgAECn8dAAIdAAYJ2hT1EAD8AAAdAAYJ2hT1EAD8AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Leguku:BAAALgAECgEJAQAAAA==.Lemiranas:BAAALgAECggJCwAAAA==.Lepo:BAABLgAECn8hAAMRAAkJ4AspHwCdAQARAAkJ4AspHwCdAQAiAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8dAAIeAAUJ1hV5IQBMAQAeAAUJ1hV5IQBMAQAuAAQKfykAAx4ABwn/GqQ8AKEBAB4ABwn/GqQ8AKEBABwAAQmNFb6HADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8SAAIDAAQJkQwJNwDoAAADAAQJkQwJNwDoAAAuAAQKf0UAAwMACQn6HMMNAIMCAAMACQn1HMMNAIMCABUACAmZEgYNAAoCAAAA.Lothoria:BAAALgADCggJCAAAAA==.',
Lu='Lucifersazz:BAAALgAECgQJBAAAAA==.Lulu:BAAALgAECgYJEgAAAA==.Lunden:BAABLgAECn86AAQcAAkJRByKDwBnAgAcAAkJRxuKDwBnAgANAAgJ7BExKAAWAQAQAAUJzw+WKADLAAAAAA==.Luvalee:BAAALgAECgQJCwAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCggJGwAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgUJBQABLgAFFAQJDQAMAIkcAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn82AAMFAAkJkgsUHAA2AQAFAAkJRQkUHAA2AQAJAAIJnAuhPgBgAAAAAA==.Maladroit:BAAALgAECgcJDQABLgAFFAQJDQAMAIkcAA==.Maldus:BAACLgAFFH8NAAIMAAQJiRyNEgBTAQAMAAQJiRyNEgBTAQAuAAQKfyoAAgwACQnyHk8LAJsCAAwACQnyHk8LAJsCAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8RAAIjAAQJRx3wDgBBAQAjAAQJRx3wDgBBAQAuAAQKfyEAAiMACQngILoEANQCACMACQngILoEANQCAAAA.Malyxia:BAAALgADCgYJBgAAAA==.Mam:BAAALgADCgcJBwAAAA==.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQARANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAFFAMJEgAPALgIAA==.Marloak:BAABLgAECn8cAAMeAAgJqRDOTwBPAQAeAAgJqRDOTwBPAQAcAAIJhwbChQA+AAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAABLgAECn8UAAIfAAYJpQQ+bQChAAAfAAYJpQQ+bQChAAAAAA==.',
Mc='Mcbain:BAAALgADCgcJEwAAAA==.Mccormick:BAAALgAECgYJBgABLgAFFAQJDQAMAIkcAA==.',
Me='Merethyl:BAAALgAECgMJAwABLgAFFAUJEwAHABESAA==.Merrymanalow:BAAALgAECgQJBQAAAA==.Metaocalypse:BAACLgAFFH8MAAILAAMJzBIGQQDYAAALAAMJzBIGQQDYAAAuAAQKfxoAAwsACQlpFyIOAEgBAAsABwlhGyIOAEgBAA4AAgmDC/sQAGIAAAAA.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milambra:BAAALgAECgMJAwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mirrah:BAAALgAECgEJAQAAAA==.Missuswor:BAAALgAECgEJAQAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mistyfisty:BAAALgAECgEJAQAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJEgAAAA==.Morrok:BAAALgAECgEJAwAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Muteknight:BAAALgAECgUJBQAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAwAAAA==.Nathali:BAAALgAECgYJCQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nessy:BAAALgAFFAMJAwABLgAFFAQJEgADAJEMAA==.Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIFAAkJIBNXEgChAQAFAAkJIBNXEgChAQAAAA==.Nightshadye:BAACLgAFFH8pAAIOAAYJLhEWEADpAAAOAAYJLhEWEADpAAAuAAQKfyMAAg4ACQl7Dx0dAGEBAA4ACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAFFAIJBgAdAGEMAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIcAAYJIA5bUADMAAAcAAYJIA5bUADMAAAAAA==.Notmonk:BAABLgAFFH8FAAIBAAMJ9xFaOgC8AAABAAMJ9xFaOgC8AAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8nAAIHAAgJxiD7BwCQAgAHAAgJxiD7BwCQAgAuAAQKfyAAAgcACAmxId0bAAcDAAcACAmxId0bAAcDAAAA.',
Od='Odiana:BAAALgAECgEJAgAAAA==.',
Om='Ombos:BAACLgAFFH8SAAMUAAQJxx/5CQASAQAUAAQJxx/5CQASAQADAAQJ5QSeTgCUAAAuAAQKf0QAAxQACQl7IV8DABMDABQACQl7IV8DABMDAAMABwm5FiktAIcBAAAA.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn9HAAICAAkJDgzQBgAdAQACAAkJDgzQBgAdAQAAAA==.',
Oz='Ozrog:BAAALgAECgIJBQABLgAFFAYJIQAdAF8NAA==.',
Pa='Palapinga:BAAALgAECgEJAgABLgAECgcJDAAGAAAAAA==.Pallypocket:BAAALgAFFAMJAwAAAA==.Pandacakes:BAAALgAFFAEJAgAAAA==.Pandahalf:BAABLgAECn8VAAIBAAYJmQUpIQCAAAABAAYJmQUpIQCAAAAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8aAAIcAAcJtA+7NgA7AQAcAAcJtA+7NgA7AQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAGAAAAAA==.Pheldorai:BAABLgAECn8kAAMZAAkJHxXcBQDSAQAZAAkJHxXcBQDSAQAkAAEJdQQJNgAtAAABLgABCgMJAQAGAAAAAA==.Pheldrid:BAABLgAECn8eAAMKAAkJiCBUBwD6AgAKAAkJiCBUBwD6AgAMAAEJfweOjQAtAAABLgABCgMJAQAGAAAAAA==.Phàntoms:BAABLgAECn8ZAAIXAAYJoxfCGAAOAQAXAAYJoxfCGAAOAQAAAA==.',
Pi='Pitufa:BAAALgADCgEJAQAAAA==.',
Pr='Protector:BAAALgAECgYJEwABLgAFFAYJKgAEALYSAA==.',
Pu='Puma:BAABLgAECn8sAAINAAkJxBFMBgA7AQANAAkJxBFMBgA7AQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIQAAcJrw1SHwANAQAQAAcJrw1SHwANAQAAAA==.',
Qu='Quayle:BAAALgAECgUJBgABLgAECggJHwAYAAgOAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSGFBwDgAgADAAkJxSGFBwDgAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8RAAIKAAUJOgtOFQAXAQAKAAUJOgtOFQAXAQAuAAQKfx0AAgoACQmEDdk4AFgBAAoACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn83AAIBAAkJxx+DCAATAwABAAkJxx+DCAATAwAAAA==.Rajun:BAAALgAECgEJBAAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAACLgAFFH8GAAIeAAIJ6QxfJgBUAAAeAAIJ6QxfJgBUAAAuAAQKfyEAAx4ACQnfHS4eAFQCAB4ACQnfHS4eAFQCABAAAglrFLsTAD0AAAAA.Razelda:BAABLgAECn8UAAIlAAcJYwlyHQC8AAAlAAcJYwlyHQC8AAAAAA==.Razelka:BAABLgAECn8hAAIbAAkJbxJ2JADRAQAbAAkJbxJ2JADRAQAAAA==.',
Re='Reclaimer:BAAALgAECgEJAQABLgAFFAYJKgAEALYSAA==.Redearslider:BAAALgAFFAEJAQAAAA==.Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIHAAkJQRPyVADeAQAHAAkJQRPyVADeAQAAAA==.Repunzel:BAABLgAECn9HAAIJAAkJfg3gDwBgAQAJAAkJfg3gDwBgAQAAAA==.',
Ri='Rightmeow:BAAALgADCgYJBgABLgAFFAIJBgAdAGEMAA==.Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8hAAMHAAYJcQ5YMAAIAQAHAAYJcQ5YMAAIAQAmAAEJAABkCAAAAAAuAAQKfy8AAgcACQnuFU9PAO4BAAcACQnuFU9PAO4BAAAA.Rozco:BAAALgAECgcJEgAAAA==.',
Ru='Rubmywolf:BAABLgAECn8rAAIEAAkJfRrpDgB3AQAEAAkJfRrpDgB3AQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAYJIQANAFAZAA==.',
Sa='Sakarii:BAAALgAECgEJAgAAAA==.Sanlord:BAAALgAECgEJAQAAAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Seagram:BAAALgADCgEJAQAAAA==.Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8uAAIEAAkJsBdzJgBHAgAEAAkJsBdzJgBHAgAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwABLgAECgQJBAAGAAAAAA==.Shadowmisty:BAAALgAECgEJAQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAABLgAECggJEQAGAAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgEJAQAGAAAAAA==.Shaure:BAAALgAECgEJAQAAAA==.Shevah:BAABLgAECn8XAAIQAAkJghGlFgBiAQAQAAkJghGlFgBiAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgcJDwAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgcJFQAMAGgHAA==.',
Si='Sid:BAECLgAFFH8fAAIHAAcJwSKoFQDHAQAHAAcJwSKoFQDHAQAuAAQKfzAAAgcACQm9JG8NAA4DAAcACQm9JG8NAA4DAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgAECgEJAgAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAACLgAFFH8QAAIHAAQJPxLKLwAKAQAHAAQJPxLKLwAKAQAuAAQKfzoAAgcACQmHHcAoAHcCAAcACQmHHcAoAHcCAAAA.',
So='Solvdod:BAAALgAECgMJAwAAAA==.Sophié:BAAALgAECgYJEgABLgAFFAQJDQAMAIkcAA==.Souxie:BAABLgAECn8XAAMCAAYJ/BEZBgA0AQACAAUJzRQZBgA0AQABAAQJ7go2kAB5AAAAAA==.',
Sp='Sprout:BAAALgAECgEJAgAAAA==.Spánk:BAAALgAECgEJAQAAAA==.',
St='Starlost:BAAALgAECgkJCwAAAA==.Starnova:BAAALgAECgYJEQAAAA==.Starwìsh:BAAALgAECggJCQAAAA==.Stonetotem:BAAALgAECgQJBAAAAA==.Stormcreaux:BAAALgAECgEJAQAAAA==.Stãr:BAABLgAECn8XAAIBAAYJLQPTjgB8AAABAAYJLQPTjgB8AAAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8kAAIZAAgJ1wTNsgDgAAAZAAgJ1wTNsgDgAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Sylvas:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.Synapse:BAABLgAECn8fAAICAAgJLxBDPQALAQACAAgJLxBDPQALAQAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAILAAkJ8xYqLQBLAgALAAkJ8xYqLQBLAgAAAA==.',
Ta='Taali:BAABLgAECn8nAAIJAAkJ6gurmABEAQAJAAkJ6gurmABEAQAAAA==.Taasali:BAAALgAECgQJBAAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn85AAIiAAkJPA3qCQCHAQAiAAkJPA3qCQCHAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIaAAgJax1XCAD5AQAaAAgJax1XCAD5AQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.Termtu:BAAALgAECgEJAQABLgAECggJIQAnANUaAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Theokoles:BAAALgADCgQJBAABLgAFFAIJBgAoAIoXAA==.Thjazi:BAABLgAECn8nAAIfAAkJDBurFQA6AgAfAAkJDBurFQA6AgAAAA==.Thomasten:BAACLgAFFH8jAAMgAAUJ9SSqCQBuAQAdAAUJ7yAYFAB+AQAgAAQJ3ySqCQBuAQAuAAQKfyUABCAACAk+Iz8TADwCACAACAm0ID8TADwCABYABQnrIV0OAGsBAB0AAQmDARpCAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAgJIwAgAPUkAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
Tj='Tjorvi:BAEALgAECgMJAwABLgAECgkJQQAMAPUYAA==.',
To='Touching:BAAALgAECggJEQAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAYJKgAEALYSAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8hAAINAAYJUBllBgA4AQANAAYJUBllBgA4AQAuAAQKfzMAAg0ACQmGIKMEAMwCAA0ACQmGIKMEAMwCAAAA.Tricksibobby:BAABLgAECn8rAAQeAAkJlhnJOQCuAQAeAAkJlhnJOQCuAQAcAAcJbCJABQCUAQAQAAIJOBuhMACfAAAAAA==.Tricksï:BAAALgAECgEJAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAGAAAAAA==.Tylèr:BAACLgAFFH8aAAMgAAUJmRujDABGAQAgAAUJDRujDABGAQAWAAEJ+AjjEgAzAAAuAAQKf0YABCAACQmhH9MHALICACAACQmhH9MHALICABYAAQl4FFUyADoAAB0AAQk2DbvcADUAAAAA.',
Uj='Ujak:BAACLgAFFH8HAAInAAMJlgjyCwCWAAAnAAMJlgjyCwCWAAAuAAQKfzEAAicACQkeFWAKABMCACcACQkeFWAKABMCAAAA.',
Um='Umami:BAABLgAECn8mAAITAAkJgRVeMgDqAQATAAkJgRVeMgDqAQAAAA==.',
Un='Unavailable:BAAALgAECgQJCAABLgAECgkJSAALAFMZAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJDQAAAA==.',
Va='Valerie:BAAALgAECgEJAQAAAA==.Valsondria:BAAALgADCgUJBQABLgAECgcJFAAlAGMJAA==.Vanillacream:BAABLgAECn83AAIEAAkJohbhNAAJAgAEAAkJohbhNAAJAgAAAA==.',
Ve='Vellisara:BAAALgAECgIJAgABLgAFFAUJEwAHABESAA==.Vermithrax:BAAALgAECgYJCgABLgAFFAIJBgAdAGEMAA==.',
Vi='Viddar:BAABLgAECn8jAAIWAAkJYx3CBABsAgAWAAkJYx3CBABsAgAAAA==.Viroqua:BAACLgAFFH8XAAIMAAgJRg++EABkAQAMAAgJRg++EABkAQAuAAQKfzIAAgwACAkDGRAQAIUCAAwACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAIJAwABLgAECgkJGgAoAIIJAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgYJBgABLgAFFAIJBgAdAGEMAA==.Winkelsmom:BAABLgAECn8vAAUcAAkJkhPlHgDRAQAcAAkJwxLlHgDRAQAeAAYJ3QpodADYAAANAAIJ3RMhEQBxAAAQAAIJJQUJLwBPAAAAAA==.',
Wo='Woralaz:BAAALgADCgEJAQABLgAECggJIQAnANUaAA==.Woru:BAABLgAECn8hAAMnAAgJ1RoBEQCjAQAnAAgJ1RoBEQCjAQATAAYJvRLNWwBKAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn86AAITAAkJtRlcHQBiAgATAAkJtRlcHQBiAgAAAA==.',
Yo='Yogisa:BAABLgAECn9HAAMBAAkJ4RW7HgAkAgABAAkJ4RW7HgAkAgAPAAEJAACqsAAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAILAAcJ+RhrWAC8AQALAAcJ+RhrWAC8AQAAAA==.',
Za='Zarhanna:BAAALgADCgIJAgAAAA==.Zariganja:BAAALgADCgIJAgAAAA==.Zarkanna:BAAALgAECgUJDgAAAA==.',
Ze='Zendarel:BAAALgAECgEJAwAAAA==.Zendiesel:BAAALgAECgYJBwABLgAECggJMwAaAGsdAA==.Zenogias:BAABLgAECn8kAAIHAAgJxxUFfACAAQAHAAgJxxUFfACAAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zombieshaman:BAAALgAECgEJAQABLgAFFAYJIQANAFAZAA==.Zote:BAAALgADCgkJDwAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAACLgAFFH8GAAIoAAIJihd0OACKAAAoAAIJihd0OACKAAAuAAQKf0AAAigACQlzIfgGABwDACgACQlzIfgGABwDAAAA.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAMJBQAEAOEOAA==.',
['ßú']='ßúg:BAABLgAFFH8FAAMEAAMJ4Q7jaQDRAAAEAAMJ1gzjaQDRAAAhAAEJOxdOMABSAAAAAA==.',
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
