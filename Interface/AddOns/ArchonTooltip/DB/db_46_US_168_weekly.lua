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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Protection','Unknown-Unknown','Mage-Frost','Mage-Arcane','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Warlock-Demonology','Hunter-Marksmanship','Druid-Feral','Warrior-Fury','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Shaman-Elemental','DemonHunter-Havoc','Hunter-Survival','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Warlock-Destruction','Mage-Fire','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AnWOADDAAABAAQJ+AnWOADDAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Alerra:BAAALgAECgEJAQAAAA==.Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAABLgAECn8aAAIEAAkJGhz4DABtAQAEAAkJGhz4DABtAQAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.Antiosto:BAEALgAECgEJAQAAAA==.',
Ar='Arana:BAAALgAECgUJCAAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIFAAkJlQq7HQAnAQAFAAkJlQq7HQAnAQABLgAECgEJAQAGAAAAAA==.Arkadias:BAAALgAECgEJAwAAAA==.Arthea:BAABLgAECn8YAAMHAAkJjQeFxAADAQAHAAkJnQaFxAADAQAIAAUJ0QWdEQCpAAAAAA==.',
As='Asmmina:BAABLgAECn8lAAIEAAkJDgthUACxAQAEAAkJDgthUACxAQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8pAAIJAAkJxg9uEAAwAQAJAAkJxg9uEAAwAQAAAA==.',
Az='Azalan:BAAALgAECgEJAQAAAA==.Azarit:BAAALgAECgUJCgAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgQJBAAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIKAAkJghJPIADAAQAKAAkJghJPIADAAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAILAAkJcSJrCQAkAwALAAkJcSJrCQAkAwAAAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJBAABLgAFFAQJDQAMAIkcAA==.Bastiecats:BAAALgADCgcJBwAAAA==.',
Be='Beatrixx:BAAALgAECgkJDwAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bi='Bitterman:BAAALgAECgUJBQABLgAFFAUJIAANAG8bAA==.',
Bl='Bllackout:BAACLgAFFH8OAAIJAAQJhRu+LADHAAAJAAQJhRu+LADHAAAuAAQKfxcAAgkACQluIWouAEcCAAkACQluIWouAEcCAAAA.Bllacktotem:BAAALgAFFAIJAgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8nAAIOAAkJvR7/BgCtAgAOAAkJvR7/BgCtAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRoREABLAgACAAkJsRoREABLAgAPAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQALAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgMJBQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMQAAkJeRY+GADYAQAQAAkJeRY+GADYAQARAAIJdQupHQA/AAABLgAFFAMJBQAEAOEOAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAACLgAFFH8FAAISAAIJQQ4aNwBfAAASAAIJQQ4aNwBfAAAuAAQKfxgAAhIACQnrCqRWAFwBABIACQnrCqRWAFwBAAAA.Cheese:BAABLgAECn8eAAMCAAcJvxtTGgDeAQACAAcJvxtTGgDeAQABAAQJPxI+agDYAAAAAA==.Cheesemix:BAABLgAECn8bAAISAAYJXg1SbgARAQASAAYJXg1SbgARAQABLgAECgkJRgASAMYhAA==.Chesleigh:BAABLgAECn8UAAIHAAQJMgoxKACGAAAHAAQJMgoxKACGAAAAAA==.Chickenchokr:BAAALgAECgEJAwAAAA==.',
Ci='Cinderlight:BAABLgAECn8wAAIJAAkJ8BElWADDAQAJAAkJ8BElWADDAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Cortock:BAAALgAECgcJDAABLgAFFAUJIAAHAJMRAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozychai:BAAALgADCgIJAgAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAFFAQJEAAHAD8SAA==.Crilynn:BAACLgAFFH8TAAIHAAUJERL4YAAfAQAHAAUJERL4YAAfAQAuAAQKfyQAAgcACQlOGKA2AD4CAAcACQlOGKA2AD4CAAAA.Crispycrittr:BAABLgAECn8eAAMTAAgJiAdbJQBMAQATAAgJiAdbJQBMAQAUAAEJwwL6KgAiAAAAAA==.Crotchcriter:BAAALgAECgEJAgAAAA==.Cryhavoc:BAABLgAECn8mAAIVAAkJQBSMDACMAQAVAAkJQBSMDACMAQAAAA==.',
Cy='Cyssor:BAAALgAECgQJDAAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAABLgAECn8VAAIEAAQJ7wr0JQCYAAAEAAQJ7wr0JQCYAAAAAA==.Dathdeath:BAABLgAECn8jAAIWAAgJXA0nFwAeAQAWAAgJXA0nFwAeAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deadquick:BAAALgAECgcJAwAAAA==.Deaviad:BAAALgADCgYJBgAAAA==.Dezzii:BAAALgAECggJDgAAAA==.',
Di='Diddel:BAAALgADCgEJAQAAAA==.Dillapuss:BAAALgADCgMJBAAAAA==.Dimitri:BAAALgAECgEJAgAAAA==.Dirtnappzz:BAAALgAFFAEJAQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAILAAMJ7g1bLADqAAALAAMJ7g1bLADqAAAuAAQKfygAAgsACAm8IugYAOcCAAsACAm8IugYAOcCAAAA.',
Do='Docken:BAABLgAECn8WAAIXAAgJmhxnAQCgAgAXAAgJmhxnAQCgAgABLgAFFAQJEAAHAD8SAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJBAAAAA==.Dotdotded:BAAALgAECgkJDAAAAA==.Dotsomahan:BAABLgAECn8YAAIYAAkJWA/IXgCDAQAYAAkJWA/IXgCDAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIZAAkJSRbmCQDVAQAZAAkJSRbmCQDVAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Draik:BAAALgAECgYJDwABLgAECggJHgAaAG0UAA==.Drandzug:BAABLgAECn8jAAIbAAgJ0ggGUQAFAQAbAAgJ0ggGUQAFAQAAAA==.Drift:BAAALgAFFAEJAQABLgAFFAQJEAAHAD8SAA==.Druidfaime:BAABLgAECn8XAAIHAAcJrwVTJgCQAAAHAAcJrwVTJgCQAAAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAgAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgAECgEJAQAAAA==.',
El='Elementalhro:BAAALgAECgEJAQAAAA==.Elise:BAABLgAECn8ZAAIcAAcJGB83FwATAgAcAAcJGB83FwATAgAAAA==.Ellzik:BAABLgAECn8UAAMNAAcJ5wt/MwDbAAANAAcJ5wt/MwDbAAAcAAQJxAOUawBzAAAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgUJCgABLgAFFAQJDQAMAIkcAA==.',
Fa='Falorien:BAABLgAECn8pAAIHAAkJPhI7cACZAQAHAAkJPhI7cACZAQAAAA==.Fatherzombie:BAAALgAECgIJBAABLgAFFAUJIAANAG8bAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAACLgAFFH8GAAIdAAIJYQxQgAB+AAAdAAIJYQxQgAB+AAAuAAQKfycAAh0ACQnoFNpIAKwBAB0ACQnoFNpIAKwBAAAA.',
Fl='Flamingpax:BAABLgAECn8eAAQaAAgJbRRVAgCDAQAaAAgJbRRVAgCDAQAcAAIJrAo6HAAwAAAeAAEJ+AXNIQAfAAAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBwABLgAFFAUJIAAHAJMRAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAACLgAFFH8GAAILAAMJ8xwXgQAFAQALAAMJ8xwXgQAFAQAuAAQKfzMAAgsACQkxIvsPAOwCAAsACQkxIvsPAOwCAAAA.Fluffinhigh:BAABLgAECn8sAAUNAAkJ8xo1CQBYAgANAAkJNho1CQBYAgAcAAYJqRd1NABHAQAeAAMJ9RXBggCzAAAaAAQJZxJyMACfAAABLgAFFAMJBgALAPMcAA==.Fluffinkai:BAAALgAECgQJCgABLgAFFAMJBgALAPMcAA==.Fluffybúnny:BAABLgAECn8XAAIVAAQJRA/YBQCHAAAVAAQJRA/YBQCHAAAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgEJAQAGAAAAAA==.Freakadeek:BAAALgAECgUJBQAAAA==.',
Fu='Furrious:BAAALgAECgQJBAAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAACLgAFFH8FAAIYAAIJ5AMoSABjAAAYAAIJ5AMoSABjAAAuAAQKfyAAAhgACAkmDWmBADYBABgACAkmDWmBADYBAAAA.',
Gi='Gillgallad:BAAALgAECgQJBAAAAA==.Gillneddra:BAAALgAECgIJAgAAAA==.Giorgina:BAACLgAFFH8KAAIfAAMJ5Q8SNQC6AAAfAAMJ5Q8SNQC6AAAuAAQKfycAAh8ACAnXF5knALABAB8ACAnXF5knALABAAAA.',
Gl='Glasc:BAABLgAECn8fAAMXAAgJCA7zNABCAQAXAAgJCA7zNABCAQAMAAYJ7Q2tRAD8AAAAAA==.',
Gn='Gnowances:BAAALgADCgkJEgAAAA==.',
Go='Goobynuk:BAACLgAFFH8PAAIHAAMJrQzROADKAAAHAAMJrQzROADKAAAuAAQKfyAAAgcACQkqGcc2AD0CAAcACQkqGcc2AD0CAAAA.Gornade:BAAALgAECgEJAQABLgAFFAUJIAANAG8bAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAMJBQAEAOEOAA==.Grevane:BAAALgAECgEJAgAAAA==.Grigorii:BAAALgAECgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMQAAcJ1x2XGQA3AgAQAAcJ3RyXGQA3AgARAAYJQhhNCwB3AQAAAA==.',
Gu='Gutsdk:BAAALgAECgQJBAAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAFFAEJAgABLgAFFAUJKAAEAOESAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAGAAAAAA==.Invidia:BAAALgAECgEJAgAAAA==.',
It='Itzli:BAACLgAFFH8MAAIZAAQJmCCmDgB0AQAZAAQJmCCmDgB0AQAuAAQKfysAAhkACQnzIb8DAIoCABkACQnzIb8DAIoCAAEuAAUUBAkNAAwAiRwA.',
Iv='Ivee:BAABLgAFFH8FAAILAAMJWgiJRQDFAAALAAMJWgiJRQDFAAABLgAFFAQJDQAMAIkcAA==.',
Ix='Ixtli:BAAALgAECgYJCAABLgAFFAQJDQAMAIkcAA==.',
Ja='Janner:BAAALgAECgUJDAAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellibean:BAAALgAECgMJAgAAAA==.Jellybeane:BAAALgAECgMJDwAAAA==.Jesdei:BAABLgAECn8WAAIYAAgJ2wGEJQFDAAAYAAgJ2wGEJQFDAAAAAA==.',
Jg='Jgwentworth:BAABLgAFFH8FAAIJAAQJUw3xHQADAQAJAAQJUw3xHQADAQABLgAFFAUJDQACAAAJAA==.',
Jo='Jojen:BAABLgAECn8pAAMKAAkJuhivHQDXAQAKAAkJuhivHQDXAQAMAAQJ+AreZACIAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAwAAAA==.Kalaruun:BAAALgAECgEJAgAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgQJDwAAAA==.Kavix:BAABLgAECn8mAAIeAAkJSxbdIwAsAgAeAAkJSxbdIwAsAgAAAA==.Kayos:BAACLgAFFH8gAAIdAAUJ3A+LTAAFAQAdAAUJ3A+LTAAFAQAuAAQKfy8AAx0ACQm3GsQCACECAB0ACQlUGsQCACECACAABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAUJIAAdANwPAA==.Kelwynd:BAAALgAECgEJAQAAAA==.Kelz:BAAALgAECgIJAgAAAA==.Kelzexx:BAABLgAECn8qAAIMAAkJ4hFEIADEAQAMAAkJ4hFEIADEAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAIOAAkJrwpJJgAhAQAOAAkJrwpJJgAhAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAABLgAFFH8GAAIHAAMJjQyKiQDGAAAHAAMJjQyKiQDGAAABLgAFFAQJDQAMAIkcAA==.Kimed:BAAALgAECgkJEgAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Kolcon:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krillian:BAAALgAECgEJBAAAAA==.',
Ku='Kula:BAABLgAECn8nAAIEAAkJpA5FEgArAQAEAAkJpA5FEgArAQAAAA==.Kungmoo:BAAALgAECgQJBAAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgQJDwAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kyraes:BAAALgAECgMJAwABLgABCgMJAQAGAAAAAA==.Kytes:BAAALgADCgUJBQABLgAFFAQJEAAHAD8SAA==.',
La='Lajoie:BAAALgAECgQJBAABLgAFFAUJKAAEAOESAA==.Largetha:BAAALgAECgQJBQABLgAFFAQJDQAMAIkcAA==.Latro:BAACLgAFFH8oAAMEAAUJ4RI1QAAtAQAEAAUJ4RI1QAAtAQAhAAIJOgS0EQBuAAAuAAQKfysAAwQACQlrHHEpADgCAAQACQlrHHEpADgCABkAAQkIBcqSACcAAAAA.',
Le='Leenex:BAABLgAECn8YAAIYAAYJFQdFyQC+AAAYAAYJFQdFyQC+AAAAAA==.Leginer:BAABLgAECn8bAAIdAAYJUxPADwDpAAAdAAYJUxPADwDpAAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Leguku:BAAALgAECgEJAQAAAA==.Lemiranas:BAAALgAECggJCwAAAA==.Lepo:BAABLgAECn8hAAMQAAkJ4AspHwCdAQAQAAkJ4AspHwCdAQAiAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8dAAIeAAUJ1hV5IQBMAQAeAAUJ1hV5IQBMAQAuAAQKfykAAx4ABwn/GqQ8AKEBAB4ABwn/GqQ8AKEBABwAAQmNFb6HADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8SAAIDAAQJkQz8GgDDAAADAAQJkQz8GgDDAAAuAAQKf0UAAwMACQn6HMMNAIMCAAMACQn1HMMNAIMCABQACAmZEgYNAAoCAAAA.Lothoria:BAAALgADCggJCAAAAA==.',
Lu='Lulu:BAAALgAECgYJEgAAAA==.Lunden:BAABLgAECn86AAQcAAkJRByKDwBnAgAcAAkJRxuKDwBnAgANAAgJ7BExKAAWAQAaAAUJzw+WKADLAAAAAA==.Luvalee:BAAALgAECgQJBgAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCggJGwAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgUJBQABLgAFFAQJDQAMAIkcAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn82AAMFAAkJkgsUHAA2AQAFAAkJRQkUHAA2AQAJAAIJnAsuMgBmAAAAAA==.Maladroit:BAAALgAECgcJDQABLgAFFAQJDQAMAIkcAA==.Maldus:BAACLgAFFH8NAAIMAAQJiRyNEgBTAQAMAAQJiRyNEgBTAQAuAAQKfyoAAgwACQnyHk8LAJsCAAwACQnyHk8LAJsCAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8RAAIjAAQJRx3wDgBBAQAjAAQJRx3wDgBBAQAuAAQKfyEAAiMACQngILoEANQCACMACQngILoEANQCAAAA.Mam:BAAALgADCgcJBwAAAA==.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQAQANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAFFAMJDwACALsHAA==.Marloak:BAABLgAECn8cAAMeAAgJqRDOTwBPAQAeAAgJqRDOTwBPAQAcAAIJhwbChQA+AAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAABLgAECn8UAAIfAAYJpQQ+bQChAAAfAAYJpQQ+bQChAAAAAA==.',
Mc='Mcbain:BAAALgADCgcJEwAAAA==.Mccormick:BAAALgAECgYJBgABLgAFFAQJDQAMAIkcAA==.',
Me='Merethyl:BAAALgAECgMJAwABLgAFFAUJEwAHABESAA==.Merrymanalow:BAAALgAECgEJAQAAAA==.Metaocalypse:BAACLgAFFH8MAAILAAMJzBKyNwDpAAALAAMJzBKyNwDpAAAuAAQKfxoAAwsACQlpF1wLAEwBAAsABwlhG1wLAEwBAA4AAgmDC6kNAGUAAAAA.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milambra:BAAALgAECgMJAwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mirrah:BAAALgAECgEJAQAAAA==.Missuswor:BAAALgAECgEJAQAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mistyfisty:BAAALgAECgEJAQAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJEgAAAA==.Morrok:BAAALgAECgEJAwAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Muteknight:BAAALgAECgUJBQAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAwAAAA==.Nathali:BAAALgAECgYJCQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nessy:BAAALgAFFAMJAwABLgAFFAQJEgADAJEMAA==.Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIFAAkJIBNXEgChAQAFAAkJIBNXEgChAQAAAA==.Nightshadye:BAACLgAFFH8pAAIOAAYJLhHrDAD7AAAOAAYJLhHrDAD7AAAuAAQKfyMAAg4ACQl7Dx0dAGEBAA4ACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAFFAIJBgAdAGEMAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIcAAYJIA5bUADMAAAcAAYJIA5bUADMAAAAAA==.Notmonk:BAABLgAFFH8FAAIBAAMJ9xFaOgC8AAABAAMJ9xFaOgC8AAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8hAAIHAAcJyR0HLgC2AQAHAAcJyR0HLgC2AQAuAAQKfyAAAgcACAmxId0bAAcDAAcACAmxId0bAAcDAAAA.',
Od='Odiana:BAAALgAECgEJAQAAAA==.',
Om='Ombos:BAACLgAFFH8SAAMTAAQJxx+lCAAYAQATAAQJxx+lCAAYAQADAAQJ5QSeTgCUAAAuAAQKf0QAAxMACQl7IV8DABMDABMACQl7IV8DABMDAAMABwm5FiktAIcBAAAA.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn8/AAICAAkJDgxjBQAnAQACAAkJDgxjBQAnAQAAAA==.',
Oz='Ozrog:BAAALgAECgIJBQABLgAFFAUJIAAdANwPAA==.',
Pa='Palapinga:BAAALgAECgEJAgABLgAECgcJDAAGAAAAAA==.Pallypocket:BAAALgAFFAMJAwAAAA==.Pandacakes:BAAALgAFFAEJAgAAAA==.Pandahalf:BAAALgAECgQJDwAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8aAAIcAAcJtA+7NgA7AQAcAAcJtA+7NgA7AQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAGAAAAAA==.Pheldorai:BAABLgAECn8kAAMYAAkJHxW3BADVAQAYAAkJHxW3BADVAQAkAAEJdQQJNgAtAAABLgABCgMJAQAGAAAAAA==.Pheldrid:BAABLgAECn8eAAMKAAkJiCBUBwD6AgAKAAkJiCBUBwD6AgAMAAEJfweOjQAtAAABLgABCgMJAQAGAAAAAA==.Phàntoms:BAABLgAECn8ZAAIWAAYJoxfCGAAOAQAWAAYJoxfCGAAOAQAAAA==.',
Pi='Pitufa:BAAALgADCgEJAQAAAA==.',
Pr='Protector:BAAALgAECgYJEwABLgAFFAUJKAAEAOESAA==.',
Pu='Puma:BAABLgAECn8rAAINAAkJEBE3BgAbAQANAAkJEBE3BgAbAQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIaAAcJrw1SHwANAQAaAAcJrw1SHwANAQAAAA==.',
Qu='Quayle:BAAALgAECgUJBgABLgAECggJHwAXAAgOAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSGFBwDgAgADAAkJxSGFBwDgAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8RAAIKAAUJOgtOFQAXAQAKAAUJOgtOFQAXAQAuAAQKfx0AAgoACQmEDdk4AFgBAAoACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn83AAIBAAkJxx+DCAATAwABAAkJxx+DCAATAwAAAA==.Rajun:BAAALgAECgEJBAAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAACLgAFFH8GAAIeAAIJ6Qz5IQBaAAAeAAIJ6Qz5IQBaAAAuAAQKfyEAAx4ACQnfHS4eAFQCAB4ACQnfHS4eAFQCABoAAglrFKMQAD8AAAAA.Razelda:BAABLgAECn8UAAIlAAcJYwlyHQC8AAAlAAcJYwlyHQC8AAAAAA==.Razelka:BAABLgAECn8hAAIbAAkJbxJ2JADRAQAbAAkJbxJ2JADRAQAAAA==.',
Re='Redearslider:BAAALgAECgUJBQAAAA==.Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIHAAkJQRPyVADeAQAHAAkJQRPyVADeAQAAAA==.Repunzel:BAABLgAECn8/AAIJAAkJrAzdDABdAQAJAAkJrAzdDABdAQAAAA==.',
Ri='Rightmeow:BAAALgADCgYJBgABLgAFFAIJBgAdAGEMAA==.Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8gAAMHAAUJkxHvMgDhAAAHAAUJkxHvMgDhAAAmAAEJAAAoBwAAAAAuAAQKfy8AAgcACQnuFU9PAO4BAAcACQnuFU9PAO4BAAAA.Rozco:BAAALgAECgcJEgAAAA==.',
Ru='Rubmywolf:BAABLgAECn8qAAIEAAkJfRoeDAB6AQAEAAkJfRoeDAB6AQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAUJIAANAG8bAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Seagram:BAAALgADCgEJAQAAAA==.Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8uAAIEAAkJsBdzJgBHAgAEAAkJsBdzJgBHAgAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwABLgAECgQJBAAGAAAAAA==.Shadowmisty:BAAALgAECgEJAQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAABLgAECggJEQAGAAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgEJAQAGAAAAAA==.Shaure:BAAALgAECgEJAQAAAA==.Shevah:BAABLgAECn8XAAIaAAkJghGlFgBiAQAaAAkJghGlFgBiAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgcJDwAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgcJEgAGAAAAAA==.',
Si='Sid:BAECLgAFFH8eAAIHAAcJwSL6EADYAQAHAAcJwSL6EADYAQAuAAQKfzAAAgcACQm9JG8NAA4DAAcACQm9JG8NAA4DAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgAECgEJAgAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAACLgAFFH8QAAIHAAQJPxIlKgAOAQAHAAQJPxIlKgAOAQAuAAQKfzoAAgcACQmHHcAoAHcCAAcACQmHHcAoAHcCAAAA.',
So='Solvdod:BAAALgAECgMJAwAAAA==.Sophié:BAAALgAECgYJEgABLgAFFAQJDQAMAIkcAA==.Souxie:BAAALgAECgQJEQAAAA==.',
Sp='Sprout:BAAALgAECgEJAQAAAA==.',
St='Starlost:BAAALgAECgkJBgAAAA==.Starnova:BAAALgAECgYJEQAAAA==.Starwìsh:BAAALgAECgcJBwAAAA==.Stonetotem:BAAALgAECgQJBAAAAA==.Stãr:BAABLgAECn8XAAIBAAYJLQPTjgB8AAABAAYJLQPTjgB8AAAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8jAAIYAAgJygTNsgDgAAAYAAgJygTNsgDgAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Sylvas:BAAALgAECgEJAQABLgAECgQJCQAGAAAAAA==.Synapse:BAABLgAECn8fAAICAAgJLxBDPQALAQACAAgJLxBDPQALAQAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAILAAkJ8xYqLQBLAgALAAkJ8xYqLQBLAgAAAA==.',
Ta='Taali:BAABLgAECn8nAAIJAAkJ6gurmABEAQAJAAkJ6gurmABEAQAAAA==.Taasali:BAAALgAECgQJBAAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn85AAIiAAkJPA3qCQCHAQAiAAkJPA3qCQCHAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIZAAgJax1XCAD5AQAZAAgJax1XCAD5AQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8nAAIfAAkJDBurFQA6AgAfAAkJDBurFQA6AgAAAA==.Thomasten:BAACLgAFFH8hAAMgAAUJ3ySqCQBuAQAdAAUJwSCgEQB+AQAgAAQJ3ySqCQBuAQAuAAQKfyUABCAACAk+Iz8TADwCACAACAm0ID8TADwCABUABQnrIV0OAGsBAB0AAQmDARpCAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAcJIQAgAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
Tj='Tjorvi:BAEALgAECgMJAwABLgAECgkJQQAMAPUYAA==.',
To='Touching:BAAALgAECggJEQAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAUJKAAEAOESAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8gAAINAAUJbxv6BwACAQANAAUJbxv6BwACAQAuAAQKfzIAAg0ACQkfIKMEAMwCAA0ACQkfIKMEAMwCAAAA.Tricksibobby:BAABLgAECn8qAAQeAAkJ6hjJOQCuAQAeAAkJ6hjJOQCuAQAcAAcJbCLlAwCaAQAaAAIJOBuhMACfAAAAAA==.Tricksï:BAAALgAECgEJAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAGAAAAAA==.Tylèr:BAACLgAFFH8aAAMgAAUJmRujDABGAQAgAAUJDRujDABGAQAVAAEJ+AjjEgAzAAAuAAQKf0YABCAACQmhH9MHALICACAACQmhH9MHALICABUAAQl4FFUyADoAAB0AAQk2DbvcADUAAAAA.',
Uj='Ujak:BAACLgAFFH8HAAInAAMJlggYCgCbAAAnAAMJlggYCgCbAAAuAAQKfzEAAicACQkeFWAKABMCACcACQkeFWAKABMCAAAA.',
Um='Umami:BAABLgAECn8mAAISAAkJgRVeMgDqAQASAAkJgRVeMgDqAQAAAA==.',
Un='Unavailable:BAAALgAECgQJBAABLgAECgkJOwAOAE4YAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJDQAAAA==.',
Va='Valsondria:BAAALgADCgUJBQABLgAECgcJFAAlAGMJAA==.Vanillacream:BAABLgAECn83AAIEAAkJohbhNAAJAgAEAAkJohbhNAAJAgAAAA==.',
Ve='Vellisara:BAAALgAECgIJAgABLgAFFAUJEwAHABESAA==.Vermithrax:BAAALgAECgYJCgABLgAFFAIJBgAdAGEMAA==.',
Vi='Viddar:BAABLgAECn8jAAIVAAkJYx3CBABsAgAVAAkJYx3CBABsAgAAAA==.Viroqua:BAACLgAFFH8XAAIMAAgJRg++EABkAQAMAAgJRg++EABkAQAuAAQKfzIAAgwACAkDGRAQAIUCAAwACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAIJAwABLgAECgkJGQAoAHoIAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgYJBgABLgAFFAIJBgAdAGEMAA==.Winkelsmom:BAABLgAECn8vAAUcAAkJkhPlHgDRAQAcAAkJwxLlHgDRAQAeAAYJ3QpodADYAAANAAIJ3ROoDgByAAAaAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8hAAMnAAgJ1RoBEQCjAQAnAAgJ1RoBEQCjAQASAAYJvRLNWwBKAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn86AAISAAkJtRlcHQBiAgASAAkJtRlcHQBiAgAAAA==.',
Yo='Yogisa:BAABLgAECn9HAAMBAAkJ4RW7HgAkAgABAAkJ4RW7HgAkAgAPAAEJAACqsAAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAILAAcJ+RhrWAC8AQALAAcJ+RhrWAC8AQAAAA==.',
Za='Zarhanna:BAAALgADCgIJAgAAAA==.Zariganja:BAAALgADCgIJAgAAAA==.Zarkanna:BAAALgAECgUJDgAAAA==.',
Ze='Zendarel:BAAALgAECgEJAwAAAA==.Zendiesel:BAAALgAECgYJBwABLgAECggJMwAZAGsdAA==.Zenogias:BAABLgAECn8kAAIHAAgJxxUFfACAAQAHAAgJxxUFfACAAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zombieshaman:BAAALgAECgEJAQABLgAFFAUJIAANAG8bAA==.Zote:BAAALgADCgkJDwAAAA==.',
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
