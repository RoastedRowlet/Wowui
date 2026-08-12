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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Protection','Unknown-Unknown','Mage-Frost','Mage-Arcane','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','Monk-Brewmaster','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Warrior-Fury','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Warlock-Demonology','Hunter-Marksmanship','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Shaman-Elemental','DemonHunter-Havoc','Hunter-Survival','Rogue-Outlaw','Warlock-Affliction','Warlock-Destruction','Mage-Fire','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AnWOADDAAABAAQJ+AnWOADDAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgAECgEJAQAAAA==.',
Al='Alerra:BAAALgAECgEJAgAAAA==.Allunnadora:BAAALgADCgcJCgAAAA==.Alone:BAAALgAECgQJBAABLgAFFAYJKgAEALYSAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAABLgAECn8aAAIEAAkJGhyWEQBgAQAEAAkJGhyWEQBgAQAAAA==.',
An='Anarcky:BAAALgADCgEJAQAAAA==.Anga:BAAALgADCggJFAAAAA==.Antiosto:BAEALgAECgEJAQAAAA==.',
Ar='Arana:BAAALgAECgUJCAAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIFAAkJlQq7HQAnAQAFAAkJlQq7HQAnAQABLgAECgEJAQAGAAAAAA==.Arkadias:BAAALgAECgEJAwAAAA==.Arrakai:BAAALgAECgEJAgAAAA==.Arthea:BAABLgAECn8YAAMHAAkJjQeFxAADAQAHAAkJnQaFxAADAQAIAAUJ0QWdEQCpAAAAAA==.',
As='Asmmina:BAABLgAECn8lAAIEAAkJDgthUACxAQAEAAkJDgthUACxAQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8pAAIJAAkJxg94FgApAQAJAAkJxg94FgApAQAAAA==.',
Az='Azalan:BAAALgAECgEJAQAAAA==.Azarit:BAAALgAECgUJCgAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgQJBAAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIKAAkJghJPIADAAQAKAAkJghJPIADAAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAILAAkJcSJrCQAkAwALAAkJcSJrCQAkAwAAAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJBAABLgAFFAQJDQAMAIkcAA==.Bastiecats:BAAALgADCgcJBwAAAA==.',
Be='Beatrixx:BAAALgAECgkJDwAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bi='Bitterman:BAAALgAECgUJBQABLgAFFAYJIQANAFAZAA==.',
Bl='Bllackout:BAACLgAFFH8OAAIJAAQJhRt8MwDDAAAJAAQJhRt8MwDDAAAuAAQKfxcAAgkACQluIWouAEcCAAkACQluIWouAEcCAAAA.Bllacktotem:BAAALgAFFAIJAgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8nAAIOAAkJvR7/BgCtAgAOAAkJvR7/BgCtAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bloodwynn:BAAALgAECgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRoREABLAgACAAkJsRoREABLAgAPAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQALAIUcAA==.Bowdinn:BAAALgAECgYJBwABLgAECggJKwAQAGsWAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgMJBQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMRAAkJeRY+GADYAQARAAkJeRY+GADYAQASAAIJdQupHQA/AAABLgAFFAMJBQAEAOEOAA==.',
Ca='Capnburr:BAAALgAECgQJBAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAACLgAFFH8FAAITAAIJQQ6zQABVAAATAAIJQQ6zQABVAAAuAAQKfxgAAhMACQnrCqRWAFwBABMACQnrCqRWAFwBAAAA.Cheese:BAABLgAECn8eAAMCAAcJvxtTGgDeAQACAAcJvxtTGgDeAQABAAQJPxI+agDYAAAAAA==.Cheesemix:BAABLgAECn8bAAITAAYJXg1SbgARAQATAAYJXg1SbgARAQABLgAECgkJRgATAMYhAA==.Chesleigh:BAABLgAECn8aAAIHAAYJ7QkaJgDAAAAHAAYJ7QkaJgDAAAAAAA==.Chickenchokr:BAAALgAECgEJAwAAAA==.',
Ci='Cinderlight:BAABLgAECn8wAAIJAAkJ8BElWADDAQAJAAkJ8BElWADDAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Cortock:BAABLgAECn8UAAQUAAkJIhvyAQDtAQAUAAcJBxzyAQDtAQAVAAcJ9BuyAgDeAQAWAAYJ5BLoCQAvAQABLgAFFAYJIQAHAHEOAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozychai:BAAALgADCgIJAgAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAFFAQJEAAHAD8SAA==.Crilynn:BAACLgAFFH8TAAIHAAUJERL4YAAfAQAHAAUJERL4YAAfAQAuAAQKfyQAAgcACQlOGKA2AD4CAAcACQlOGKA2AD4CAAAA.Crispycrittr:BAABLgAECn8eAAMXAAgJiAdbJQBMAQAXAAgJiAdbJQBMAQAYAAEJwwL6KgAiAAAAAA==.Crotchcriter:BAAALgAECgEJAgAAAA==.Cryhavoc:BAABLgAECn8mAAIZAAkJQBSMDACMAQAZAAkJQBSMDACMAQAAAA==.',
Cy='Cyssor:BAAALgAECgYJDwAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAABLgAECn8bAAIEAAYJ5ArRIQDYAAAEAAYJ5ArRIQDYAAAAAA==.Dathdeath:BAABLgAECn8kAAIaAAgJXA0nFwAeAQAaAAgJXA0nFwAeAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.Dezzii:BAAALgAECggJEQAAAA==.',
Di='Diddel:BAAALgADCgEJAQAAAA==.Dillapuss:BAAALgADCgMJBAAAAA==.Dimitri:BAAALgAECgEJAgAAAA==.Dirtnappzz:BAAALgAFFAEJAQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAILAAMJ7g1bLADqAAALAAMJ7g1bLADqAAAuAAQKfygAAgsACAm8IugYAOcCAAsACAm8IugYAOcCAAAA.',
Do='Docken:BAABLgAECn8WAAIbAAgJmhzuAQCeAgAbAAgJmhzuAQCeAgABLgAFFAQJEAAHAD8SAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJBAAAAA==.Dotdotded:BAAALgAECgkJDAAAAA==.Dotsomahan:BAABLgAECn8YAAIcAAkJWA/IXgCDAQAcAAkJWA/IXgCDAQAAAA==.Dottin:BAAALgADCgEJAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIdAAkJSRbmCQDVAQAdAAkJSRbmCQDVAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Draik:BAAALgAECgYJEAABLgAECggJKwAQAGsWAA==.Drandzug:BAABLgAECn8jAAIWAAgJ0ggGUQAFAQAWAAgJ0ggGUQAFAQAAAA==.Drift:BAAALgAFFAEJAQABLgAFFAQJEAAHAD8SAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAgAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgAECgEJAQAAAA==.',
El='Elementalhro:BAAALgAECgEJAQAAAA==.Elise:BAABLgAECn8ZAAIeAAcJGB83FwATAgAeAAcJGB83FwATAgAAAA==.Ellzik:BAABLgAECn8UAAMNAAcJ5wt/MwDbAAANAAcJ5wt/MwDbAAAeAAQJxAOUawBzAAAAAA==.Elosonia:BAAALgAECgEJAQAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgUJCgABLgAFFAQJDQAMAIkcAA==.',
Fa='Falorien:BAABLgAECn8pAAIHAAkJPhI7cACZAQAHAAkJPhI7cACZAQAAAA==.Fatherzombie:BAAALgAECgIJBAABLgAFFAYJIQANAFAZAA==.Fauxi:BAAALgAECgEJAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAACLgAFFH8GAAIfAAIJYQxQgAB+AAAfAAIJYQxQgAB+AAAuAAQKfycAAh8ACQnoFNpIAKwBAB8ACQnoFNpIAKwBAAAA.',
Fl='Flamingpax:BAABLgAECn8rAAQQAAgJaxa/AgCjAQAQAAgJaxa/AgCjAQAeAAIJ/A9+GwBcAAAgAAEJ+AViKQAeAAAAAA==.Flamish:BAAALgADCgUJBQAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBwABLgAFFAYJIQAHAHEOAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbaked:BAAALgAECgQJBAABLgAFFAMJBgALAPMcAA==.Fluffinbunz:BAACLgAFFH8GAAILAAMJ8xwXgQAFAQALAAMJ8xwXgQAFAQAuAAQKfzUAAgsACQkxIvsPAOwCAAsACQkxIvsPAOwCAAAA.Fluffinhigh:BAABLgAECn8uAAUNAAkJbhs1CQBYAgANAAkJNho1CQBYAgAeAAcJYxl1NABHAQAgAAMJ9RXBggCzAAAQAAQJZxJyMACfAAABLgAFFAMJBgALAPMcAA==.Fluffinkai:BAAALgAECgQJCgABLgAFFAMJBgALAPMcAA==.Fluffybúnny:BAABLgAECn8eAAIZAAcJ3Am4BQDDAAAZAAcJ3Am4BQDDAAAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgEJAQAGAAAAAA==.Freakadeek:BAAALgAECgUJBQAAAA==.Fresnel:BAAALgAECgUJBgAAAA==.Fruitloopes:BAABLgAECn8dAAIHAAcJ1wd7IwDNAAAHAAcJ1wd7IwDNAAAAAA==.',
Fu='Furmir:BAAALgADCgQJBAABLgAFFAIJBgAfAGEMAA==.Furrious:BAAALgAECgQJBAAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAACLgAFFH8FAAIcAAIJ5AO1VQBUAAAcAAIJ5AO1VQBUAAAuAAQKfyAAAhwACAkmDWmBADYBABwACAkmDWmBADYBAAAA.',
Gi='Gillgallad:BAAALgAECgQJCQAAAA==.Gillneddra:BAAALgAECgIJAgAAAA==.Giorgina:BAACLgAFFH8KAAIhAAMJ5Q8SNQC6AAAhAAMJ5Q8SNQC6AAAuAAQKfycAAiEACAnXF5knALABACEACAnXF5knALABAAAA.',
Gl='Glasc:BAABLgAECn8fAAMbAAgJCA7zNABCAQAbAAgJCA7zNABCAQAMAAYJ7Q2tRAD8AAAAAA==.',
Gn='Gnowances:BAAALgADCgkJEgAAAA==.',
Go='Goobynuk:BAACLgAFFH8PAAIHAAMJrQwgQADHAAAHAAMJrQwgQADHAAAuAAQKfyAAAgcACQkqGcc2AD0CAAcACQkqGcc2AD0CAAAA.Gornade:BAAALgAECgEJAQABLgAFFAYJIQANAFAZAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAMJBQAEAOEOAA==.Grevane:BAAALgAECgEJAgAAAA==.Grigorii:BAAALgAECgEJAgAAAA==.Grimli:BAAALgADCgYJBgAAAA==.Grimstone:BAABLgAECn8ZAAMRAAcJ1x2XGQA3AgARAAcJ3RyXGQA3AgASAAYJQhhNCwB3AQAAAA==.Groggu:BAAALgADCgYJCQAAAA==.',
Gu='Gutsdk:BAAALgAECgQJBAAAAA==.',
He='Herlings:BAAALgADCgQJBAAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAFFAEJAgABLgAFFAYJKgAEALYSAA==.Huurs:BAAALgAECgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAGAAAAAA==.Invidia:BAAALgAECgEJAgAAAA==.',
It='Itzli:BAACLgAFFH8MAAIdAAQJmCCmDgB0AQAdAAQJmCCmDgB0AQAuAAQKfysAAh0ACQnzIb8DAIoCAB0ACQnzIb8DAIoCAAEuAAUUBAkNAAwAiRwA.',
Iv='Ivee:BAABLgAFFH8FAAILAAMJWgh8UwCzAAALAAMJWgh8UwCzAAABLgAFFAQJDQAMAIkcAA==.',
Ix='Ixtli:BAAALgAECgYJCAABLgAFFAQJDQAMAIkcAA==.',
Ja='Janner:BAAALgAECgUJDAAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellibean:BAAALgAECgMJAgAAAA==.Jellybeane:BAABLgAECn8VAAIMAAYJDQaGFwB6AAAMAAYJDQaGFwB6AAAAAA==.Jesdei:BAABLgAECn8WAAIcAAgJ2wGEJQFDAAAcAAgJ2wGEJQFDAAAAAA==.',
Jg='Jgwentworth:BAABLgAFFH8FAAIJAAQJUw03JQD1AAAJAAQJUw03JQD1AAABLgAFFAUJDQACAAAJAA==.',
Jo='Jojen:BAABLgAECn8pAAMKAAkJuhivHQDXAQAKAAkJuhivHQDXAQAMAAQJ+AreZACIAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAwAAAA==.Kalaruun:BAAALgAECgEJAgAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAABLgAECn8VAAIgAAYJRQzsDADcAAAgAAYJRQzsDADcAAAAAA==.Kavix:BAABLgAECn8mAAIgAAkJSxbdIwAsAgAgAAkJSxbdIwAsAgAAAA==.Kayos:BAACLgAFFH8hAAIfAAYJXw2LTAAFAQAfAAYJXw2LTAAFAQAuAAQKfy8AAx8ACQm3GtkDABoCAB8ACQlUGtkDABoCACIABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgAECgYJBgABLgAFFAYJIQAfAF8NAA==.Kelwynd:BAAALgAECgEJAQAAAA==.Kelz:BAAALgAECgIJAgAAAA==.Kelzexx:BAABLgAECn8qAAIMAAkJ4hFEIADEAQAMAAkJ4hFEIADEAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAIOAAkJrwpJJgAhAQAOAAkJrwpJJgAhAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAABLgAFFH8GAAIHAAMJjQyKiQDGAAAHAAMJjQyKiQDGAAABLgAFFAQJDQAMAIkcAA==.Kimed:BAABLgAECn8cAAMHAAkJPQxXEwBBAQAHAAkJ+gtXEwBBAQAIAAMJjQ5FCwBdAAAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Kolcon:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krica:BAAALgADCgYJBgAAAA==.Krillian:BAAALgAECgEJBAAAAA==.',
Ku='Kula:BAABLgAECn8oAAIEAAkJHxClFAA+AQAEAAkJHxClFAA+AQAAAA==.Kungmoo:BAAALgAECgQJBAAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.Kuwata:BAAALgADCgcJBwAAAA==.',
Kv='Kvnknight:BAAALgAECgQJDwAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kyraes:BAAALgAECgMJAwABLgABCgMJAQAGAAAAAA==.Kytes:BAAALgADCgUJBQABLgAFFAQJEAAHAD8SAA==.',
La='Lajoie:BAAALgAECgQJBAABLgAFFAYJKgAEALYSAA==.Largetha:BAAALgAECgQJBQABLgAFFAQJDQAMAIkcAA==.Latro:BAACLgAFFH8qAAMEAAYJthIZIQAmAQAEAAYJthIZIQAmAQAjAAIJOgRIFABsAAAuAAQKfysAAwQACQlrHHEpADgCAAQACQlrHHEpADgCAB0AAQkIBcqSACcAAAAA.',
Le='Leenex:BAABLgAECn8YAAIcAAYJFQdFyQC+AAAcAAYJFQdFyQC+AAAAAA==.Leginer:BAABLgAECn8dAAIfAAYJ2hQPEgD5AAAfAAYJ2hQPEgD5AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Leguku:BAAALgAECgEJAQAAAA==.Lemiranas:BAAALgAECggJCwAAAA==.Lepo:BAABLgAECn8hAAMRAAkJ4AspHwCdAQARAAkJ4AspHwCdAQAkAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8dAAIgAAUJ1hV5IQBMAQAgAAUJ1hV5IQBMAQAuAAQKfykAAyAABwn/GqQ8AKEBACAABwn/GqQ8AKEBAB4AAQmNFb6HADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8SAAIDAAQJkQwJNwDoAAADAAQJkQwJNwDoAAAuAAQKf0UAAwMACQn6HMMNAIMCAAMACQn1HMMNAIMCABgACAmZEgYNAAoCAAAA.Lothoria:BAAALgADCggJCAAAAA==.',
Lu='Lucifersazz:BAAALgAECgQJBAAAAA==.Lulu:BAAALgAECgYJEgAAAA==.Lunden:BAABLgAECn86AAQeAAkJRByKDwBnAgAeAAkJRxuKDwBnAgANAAgJ7BExKAAWAQAQAAUJzw+WKADLAAAAAA==.Luvalee:BAAALgAECgQJCwAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCggJGwAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgUJBQABLgAFFAQJDQAMAIkcAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn82AAMFAAkJkgsUHAA2AQAFAAkJRQkUHAA2AQAJAAIJnAtUQwBfAAAAAA==.Maladroit:BAAALgAECgcJDQABLgAFFAQJDQAMAIkcAA==.Maldus:BAACLgAFFH8NAAIMAAQJiRyNEgBTAQAMAAQJiRyNEgBTAQAuAAQKfyoAAgwACQnyHk8LAJsCAAwACQnyHk8LAJsCAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8RAAIVAAQJRx3wDgBBAQAVAAQJRx3wDgBBAQAuAAQKfyEAAhUACQngILoEANQCABUACQngILoEANQCAAAA.Malyxia:BAAALgADCgYJCwAAAA==.Mam:BAAALgADCgcJBwAAAA==.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQARANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAFFAMJEgAPALgIAA==.Marloak:BAABLgAECn8dAAMgAAkJohBvDADlAAAgAAkJohBvDADlAAAeAAIJhwbChQA+AAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAABLgAECn8UAAIhAAYJpQQ+bQChAAAhAAYJpQQ+bQChAAAAAA==.',
Mc='Mcbain:BAAALgADCgcJEwAAAA==.Mccormick:BAAALgAECgYJBgABLgAFFAQJDQAMAIkcAA==.',
Me='Merethyl:BAAALgAECgMJAwABLgAFFAUJEwAHABESAA==.Merrymanalow:BAAALgAECgQJBQAAAA==.Metaocalypse:BAACLgAFFH8MAAILAAMJzBJ5QgDYAAALAAMJzBJ5QgDYAAAuAAQKfxoAAwsACQlpFwYPAEgBAAsABwlhGwYPAEgBAA4AAgmDC3gSAGIAAAAA.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milambra:BAAALgAECgMJAwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mirrah:BAAALgAECgEJAQAAAA==.Missuswor:BAAALgAECgEJAQAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mistyfisty:BAAALgAECgEJAQAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJEgAAAA==.Morrok:BAAALgAECgEJAwAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Muteknight:BAAALgAECgUJBQAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAwAAAA==.Nathali:BAAALgAECgYJCQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nessy:BAAALgAFFAMJAwABLgAFFAQJEgADAJEMAA==.Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIFAAkJIBNXEgChAQAFAAkJIBNXEgChAQAAAA==.Nightshadye:BAACLgAFFH8pAAIOAAYJLhHCEADpAAAOAAYJLhHCEADpAAAuAAQKfyMAAg4ACQl7Dx0dAGEBAA4ACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAFFAIJBgAfAGEMAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIeAAYJIA5bUADMAAAeAAYJIA5bUADMAAAAAA==.Notmonk:BAABLgAFFH8FAAIBAAMJ9xFaOgC8AAABAAMJ9xFaOgC8AAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8qAAIHAAgJxiCqBwCXAgAHAAgJxiCqBwCXAgAuAAQKfyAAAgcACAmxId0bAAcDAAcACAmxId0bAAcDAAAA.',
Od='Odiana:BAAALgAECgEJAgAAAA==.',
Om='Ombos:BAACLgAFFH8SAAMXAAQJxx9ZCgARAQAXAAQJxx9ZCgARAQADAAQJ5QSeTgCUAAAuAAQKf0QAAxcACQl7IV8DABMDABcACQl7IV8DABMDAAMABwm5FiktAIcBAAAA.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn9HAAICAAkJDgxjBwAcAQACAAkJDgxjBwAcAQAAAA==.',
Oz='Ozrog:BAAALgAECgIJBQABLgAFFAYJIQAfAF8NAA==.',
Pa='Palapinga:BAAALgAECgEJAgABLgAECgcJDAAGAAAAAA==.Pallypocket:BAAALgAFFAMJAwAAAA==.Pandacakes:BAAALgAFFAEJAgAAAA==.Pandahalf:BAABLgAECn8VAAIBAAYJmQVqIgB/AAABAAYJmQVqIgB/AAAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8aAAIeAAcJtA+7NgA7AQAeAAcJtA+7NgA7AQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAGAAAAAA==.Pheldorai:BAABLgAECn8kAAMcAAkJHxVOBgDOAQAcAAkJHxVOBgDOAQAlAAEJdQQJNgAtAAABLgABCgMJAQAGAAAAAA==.Pheldrid:BAABLgAECn8eAAMKAAkJiCBUBwD6AgAKAAkJiCBUBwD6AgAMAAEJfweOjQAtAAABLgABCgMJAQAGAAAAAA==.Phàntoms:BAABLgAECn8ZAAIaAAYJoxfCGAAOAQAaAAYJoxfCGAAOAQAAAA==.',
Pi='Pitufa:BAAALgADCgEJAQAAAA==.',
Pr='Property:BAAALgAECgMJAwABLgAFFAUJDQAUALMkAA==.Protector:BAAALgAECgYJEwABLgAFFAYJKgAEALYSAA==.',
Pu='Puma:BAABLgAECn8sAAINAAkJxBGsBgA5AQANAAkJxBGsBgA5AQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIQAAcJrw1SHwANAQAQAAcJrw1SHwANAQAAAA==.',
Qu='Quayle:BAAALgAECgUJBgABLgAECggJHwAbAAgOAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSGFBwDgAgADAAkJxSGFBwDgAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8RAAIKAAUJOgtOFQAXAQAKAAUJOgtOFQAXAQAuAAQKfx0AAgoACQmEDdk4AFgBAAoACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn83AAIBAAkJxx+DCAATAwABAAkJxx+DCAATAwAAAA==.Rajun:BAAALgAECgEJBAAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAACLgAFFH8GAAIgAAIJ6QwrJwBUAAAgAAIJ6QwrJwBUAAAuAAQKfyEAAyAACQnfHS4eAFQCACAACQnfHS4eAFQCABAAAglrFOMUAD0AAAAA.Razelda:BAABLgAECn8UAAImAAcJYwlyHQC8AAAmAAcJYwlyHQC8AAAAAA==.Razelka:BAABLgAECn8hAAIWAAkJbxJ2JADRAQAWAAkJbxJ2JADRAQAAAA==.',
Re='Reclaimer:BAAALgAECgEJAQABLgAFFAYJKgAEALYSAA==.Redearslider:BAAALgAFFAEJAQAAAA==.Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIHAAkJQRPyVADeAQAHAAkJQRPyVADeAQAAAA==.Repunzel:BAABLgAECn9HAAIJAAkJfg0ZEQBgAQAJAAkJfg0ZEQBgAQAAAA==.',
Ri='Rightmeow:BAAALgADCgYJBgABLgAFFAIJBgAfAGEMAA==.Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8hAAMHAAYJcQ7BMAAIAQAHAAYJcQ7BMAAIAQAnAAEJAADLCAAAAAAuAAQKfy8AAgcACQnuFU9PAO4BAAcACQnuFU9PAO4BAAAA.Rozco:BAAALgAECgcJEgAAAA==.',
Ru='Rubmywolf:BAABLgAECn8rAAIEAAkJfRr1DwB1AQAEAAkJfRr1DwB1AQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAYJIQANAFAZAA==.',
Sa='Sakarii:BAAALgAECgEJAgAAAA==.Sanlord:BAAALgAECgEJAQAAAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Seagram:BAAALgADCgEJAQAAAA==.Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8uAAIEAAkJsBdzJgBHAgAEAAkJsBdzJgBHAgAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwABLgAECgQJBAAGAAAAAA==.Shadowmisty:BAAALgAECgEJAQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAABLgAECggJEQAGAAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgEJAQAGAAAAAA==.Shaure:BAAALgAECgEJAQAAAA==.Shevah:BAABLgAECn8XAAIQAAkJghGlFgBiAQAQAAkJghGlFgBiAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgcJDwAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECggJFgAMAJ8HAA==.',
Si='Sid:BAECLgAFFH8fAAIHAAcJwSJcFgDFAQAHAAcJwSJcFgDFAQAuAAQKfzAAAgcACQm9JG8NAA4DAAcACQm9JG8NAA4DAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgAECgEJAgAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAACLgAFFH8QAAIHAAQJPxLkMQACAQAHAAQJPxLkMQACAQAuAAQKfzoAAgcACQmHHcAoAHcCAAcACQmHHcAoAHcCAAAA.',
So='Solvdod:BAAALgAECgMJAwAAAA==.Sophié:BAAALgAECgYJEgABLgAFFAQJDQAMAIkcAA==.Souxie:BAABLgAECn8XAAMCAAYJ/BGfBgAzAQACAAUJzRSfBgAzAQABAAQJ7go2kAB5AAAAAA==.',
Sp='Sprout:BAAALgAECgEJAgAAAA==.Spánk:BAAALgAECgEJAQAAAA==.',
St='Starislost:BAAALgAECgkJCwAAAA==.Starnova:BAAALgAECgYJEQAAAA==.Starwìsh:BAAALgAECggJCQAAAA==.Stonetotem:BAAALgAECgQJBAAAAA==.Stormcreaux:BAAALgAECgEJAQAAAA==.Stãr:BAABLgAECn8XAAIBAAYJLQPTjgB8AAABAAYJLQPTjgB8AAAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8kAAIcAAgJ1wTNsgDgAAAcAAgJ1wTNsgDgAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Sylvas:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.Synapse:BAABLgAECn8gAAICAAkJPg9oDAC7AAACAAkJPg9oDAC7AAAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAILAAkJ8xYqLQBLAgALAAkJ8xYqLQBLAgAAAA==.',
Ta='Taali:BAABLgAECn8nAAIJAAkJ6gurmABEAQAJAAkJ6gurmABEAQAAAA==.Taasali:BAAALgAECgQJBAAAAA==.Taraniss:BAAALgADCgMJAwAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn85AAIkAAkJPA3qCQCHAQAkAAkJPA3qCQCHAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIdAAgJax1XCAD5AQAdAAgJax1XCAD5AQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.Termtu:BAAALgAECgEJAQABLgAECggJIQAoANUaAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Theokoles:BAAALgADCgQJBAABLgAFFAIJBgApAIoXAA==.Thjazi:BAABLgAECn8nAAIhAAkJDBurFQA6AgAhAAkJDBurFQA6AgAAAA==.Thomasten:BAACLgAFFH8kAAMiAAUJ9SSqCQBuAQAfAAUJ7yAUFQB4AQAiAAQJ3ySqCQBuAQAuAAQKfyUABCIACAk+Iz8TADwCACIACAm0ID8TADwCABkABQnrIV0OAGsBAB8AAQmDARpCAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAgJJAAiAPUkAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
Tj='Tjorvi:BAEALgAECgMJAwABLgAECgkJQQAMAPUYAA==.',
To='Touching:BAAALgAECggJEQAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAYJKgAEALYSAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8hAAINAAYJUBmeBgA2AQANAAYJUBmeBgA2AQAuAAQKfzMAAg0ACQmGIKMEAMwCAA0ACQmGIKMEAMwCAAAA.Tricksibobby:BAABLgAECn8rAAQgAAkJlhnJOQCuAQAgAAkJlhnJOQCuAQAeAAcJbCLABQCQAQAQAAIJOBuhMACfAAAAAA==.Tricksï:BAAALgAECgEJAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAGAAAAAA==.',
Uj='Ujak:BAACLgAFFH8HAAIoAAMJlghZDACWAAAoAAMJlghZDACWAAAuAAQKfzEAAigACQkeFWAKABMCACgACQkeFWAKABMCAAAA.',
Um='Umami:BAABLgAECn8mAAITAAkJgRVeMgDqAQATAAkJgRVeMgDqAQAAAA==.',
Un='Unavailable:BAAALgAECgQJCAABLgAECgkJSAALAFMZAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJDQAAAA==.',
Va='Valerie:BAAALgAECgEJAQAAAA==.Valsondria:BAAALgADCgUJBQABLgAECgcJFAAmAGMJAA==.Vanillacream:BAABLgAECn83AAIEAAkJohbhNAAJAgAEAAkJohbhNAAJAgAAAA==.',
Ve='Vellisara:BAAALgAECgcJCQABLgAFFAUJEwAHABESAA==.Vermithrax:BAAALgAECgYJCgABLgAFFAIJBgAfAGEMAA==.',
Vi='Viddar:BAABLgAECn8jAAIZAAkJYx3CBABsAgAZAAkJYx3CBABsAgAAAA==.Viroqua:BAACLgAFFH8XAAIMAAgJRg++EABkAQAMAAgJRg++EABkAQAuAAQKfzIAAgwACAkDGRAQAIUCAAwACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAIJAwABLgAECgkJGgApAIIJAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgYJBgABLgAFFAIJBgAfAGEMAA==.Winkelsmom:BAABLgAECn8vAAUeAAkJkhPlHgDRAQAeAAkJwxLlHgDRAQAgAAYJ3QpodADYAAANAAIJ3RMIEgBwAAAQAAIJJQUJLwBPAAAAAA==.',
Wo='Woralaz:BAAALgADCgEJAQABLgAECggJIQAoANUaAA==.Woru:BAABLgAECn8hAAMoAAgJ1RoBEQCjAQAoAAgJ1RoBEQCjAQATAAYJvRLNWwBKAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn86AAITAAkJtRlcHQBiAgATAAkJtRlcHQBiAgAAAA==.',
Ye='Yeetmachine:BAAALgAFFAEJAQABLgAFFAYJIQANAFAZAA==.',
Yo='Yogisa:BAABLgAECn9HAAMBAAkJ4RW7HgAkAgABAAkJ4RW7HgAkAgAPAAEJAACqsAAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAILAAcJ+RhrWAC8AQALAAcJ+RhrWAC8AQAAAA==.',
Za='Zarhanna:BAAALgADCgIJAgAAAA==.Zariganja:BAAALgADCgIJAgAAAA==.Zarkanna:BAAALgAECgUJDgAAAA==.',
Ze='Zendarel:BAAALgAECgEJAwAAAA==.Zendiesel:BAAALgAECgYJBwABLgAECggJMwAdAGsdAA==.Zenogias:BAABLgAECn8kAAIHAAgJxxUFfACAAQAHAAgJxxUFfACAAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zombieshaman:BAAALgAECgEJAQABLgAFFAYJIQANAFAZAA==.Zote:BAAALgADCgkJDwAAAA==.',
Zv='Zvvyt:BAACLgAFFH8aAAMiAAUJmRujDABGAQAiAAUJDRujDABGAQAZAAEJ+AjjEgAzAAAuAAQKf0YABCIACQmhH9MHALICACIACQmhH9MHALICABkAAQl4FFUyADoAAB8AAQk2DbvcADUAAAAA.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAACLgAFFH8GAAIpAAIJihd0OACKAAApAAIJihd0OACKAAAuAAQKf0AAAikACQlzIfgGABwDACkACQlzIfgGABwDAAAA.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAMJBQAEAOEOAA==.',
['ßú']='ßúg:BAABLgAFFH8FAAMEAAMJ4Q7jaQDRAAAEAAMJ1gzjaQDRAAAjAAEJOxdOMABSAAAAAA==.',
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
