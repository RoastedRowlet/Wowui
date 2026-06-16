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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Mage-Frost','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Warrior-Fury','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Shaman-Elemental','Priest-Discipline','Unknown-Unknown','DemonHunter-Havoc','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Shaman-Enhancement','Paladin-Holy','Hunter-Survival',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AkkNgDEAAABAAQJ+AkkNgDEAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAABLgAECn8UAAIEAAYJexpWYACCAQAEAAYJexpWYACCAQAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.',
Ar='Arana:BAAALgAECgUJBgAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIFAAkJlQpSHQAnAQAFAAkJlQpSHQAnAQAAAA==.Arkadias:BAAALgAECgEJAQAAAA==.Arthea:BAAALgAECgcJEAAAAA==.',
As='Asmmina:BAABLgAECn8lAAIEAAkJDgvQTgCxAQAEAAkJDgvQTgCxAQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8iAAIGAAgJcgoLlwBDAQAGAAgJcgoLlwBDAQAAAA==.',
Az='Azalan:BAAALgAECgEJAQAAAA==.Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgQJBAAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIHAAkJghK8HwDAAQAHAAkJghK8HwDAAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAIIAAkJcSIaCQAmAwAIAAkJcSIaCQAmAwAAAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJBAABLgAFFAQJDAAJAIkcAA==.',
Be='Beatrixx:BAAALgAECggJDQAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAACLgAFFH8LAAIGAAMJNR+uXQDtAAAGAAMJNR+uXQDtAAAuAAQKfxcAAgYACQluIYMtAEgCAAYACQluIYMtAEgCAAAA.Bllacktotem:BAAALgAFFAIJAgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8jAAIKAAkJvR7JBgCwAgAKAAkJvR7JBgCwAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRrQDwBMAgACAAkJsRrQDwBMAgALAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAIAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgMJBQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMMAAkJeRazFwDZAQAMAAkJeRazFwDZAQANAAIJdQupHQA/AAABLgAFFAMJBQAEAOEOAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAABLgAECn8XAAIOAAkJMAo4VQBcAQAOAAkJMAo4VQBcAQAAAA==.Cheese:BAABLgAECn8cAAMCAAcJLRvFGQDfAQACAAcJLRvFGQDfAQABAAQJPxJiZwDXAAAAAA==.Cheesemix:BAABLgAECn8bAAIOAAYJXg1/bAARAQAOAAYJXg1/bAARAQABLgAECgkJRgAOAMYhAA==.Chesleigh:BAAALgAECgQJDgAAAA==.',
Ci='Cinderlight:BAABLgAECn8uAAIGAAkJ8BH/VQDGAQAGAAkJ8BH/VQDGAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAFFAQJCQAPAKIRAA==.Crilynn:BAACLgAFFH8TAAIPAAUJERIRXgAvAQAPAAUJERIRXgAvAQAuAAQKfyQAAg8ACQlOGK41AD8CAA8ACQlOGK41AD8CAAAA.Crispycrittr:BAABLgAECn8eAAMQAAgJiAdbJQBMAQAQAAgJiAdbJQBMAQARAAEJwwJIKgAiAAAAAA==.Crotchcriter:BAAALgAECgEJAgAAAA==.Cryhavoc:BAABLgAECn8kAAISAAgJLBNWDACMAQASAAgJLBNWDACMAQAAAA==.',
Cy='Cyssor:BAAALgAECgQJCQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAAALgAECgQJDAAAAA==.Dathdeath:BAABLgAECn8iAAITAAcJPg9hFgAiAQATAAcJPg9hFgAiAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.Dezzii:BAAALgADCgcJBwAAAA==.',
Di='Diddel:BAAALgADCgEJAQAAAA==.Dillapuss:BAAALgADCgMJBAAAAA==.Dimitri:BAAALgAECgEJAQAAAA==.Dirtnappzz:BAAALgAECgUJBQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIIAAMJ7g1bLADqAAAIAAMJ7g1bLADqAAAuAAQKfygAAggACAm8IugYAOcCAAgACAm8IugYAOcCAAAA.',
Do='Docken:BAAALgAECgcJCwABLgAFFAQJCQAPAKIRAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJAwAAAA==.Dotdotded:BAAALgAECgkJCwAAAA==.Dotsomahan:BAABLgAECn8YAAIUAAkJWA/FXACHAQAUAAkJWA/FXACHAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIVAAkJSRatCQDWAQAVAAkJSRatCQDWAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAABLgAECn8gAAIWAAcJlgjdTgALAQAWAAcJlgjdTgALAQAAAA==.Druidfaime:BAAALgAECgYJEAAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAQAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgAECgEJAQAAAA==.',
El='Elise:BAABLgAECn8WAAIXAAYJUB80IQC7AQAXAAYJUB80IQC7AQAAAA==.Ellzik:BAABLgAECn8UAAMYAAcJ5wsZMgDbAAAYAAcJ5wsZMgDbAAAXAAQJxAPaaQBzAAAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgUJCgABLgAFFAQJDAAJAIkcAA==.',
Fa='Falorien:BAABLgAECn8kAAIPAAgJwBJ7bgCaAQAPAAgJwBJ7bgCaAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8nAAIZAAkJ6BTdRwCrAQAZAAkJ6BTdRwCrAQAAAA==.',
Fl='Flamingpax:BAAALgAECgcJCwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBgABLgAFFAQJEAAPAH8PAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAACLgAFFH8FAAIIAAMJ8xygfQAIAQAIAAMJ8xygfQAIAQAuAAQKfzAAAggACQkLIZgPAO4CAAgACQkLIZgPAO4CAAAA.Fluffinhigh:BAABLgAECn8mAAUYAAkJNhoFCQBYAgAYAAkJNhoFCQBYAgAXAAYJqRe6MwBGAQAaAAMJ9RXagQCzAAAbAAMJZQtsSQBCAAABLgAFFAMJBQAIAPMcAA==.Fluffinkai:BAAALgAECgMJAwABLgAFFAMJBQAIAPMcAA==.Fluffybúnny:BAAALgAECgQJDgAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJNwAFAJUKAA==.Freakadeek:BAAALgAECgUJBQAAAA==.',
Fu='Furrious:BAAALgAECgQJBAAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8gAAIUAAgJJg3rfgA6AQAUAAgJJg3rfgA6AQAAAA==.',
Gi='Giorgina:BAACLgAFFH8KAAIcAAMJ5Q9DMwC7AAAcAAMJ5Q9DMwC7AAAuAAQKfycAAhwACAnXF9smALEBABwACAnXF9smALEBAAAA.',
Gl='Glasc:BAABLgAECn8eAAMdAAcJDQ6kMwBHAQAdAAcJDQ6kMwBHAQAJAAYJ7Q1qQwD/AAAAAA==.',
Gn='Gnowances:BAAALgADCgkJCwAAAA==.',
Go='Goobynuk:BAACLgAFFH8FAAIPAAIJ3Ap7nwCRAAAPAAIJ3Ap7nwCRAAAuAAQKfyAAAg8ACQkqGRI2AD4CAA8ACQkqGRI2AD4CAAAA.Gornade:BAAALgAECgEJAQABLgAFFAQJEAAYAB4SAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAMJBQAEAOEOAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMMAAcJ1x2XGQA3AgAMAAcJ3RyXGQA3AgANAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAECgcJCQABLgAFFAUJHwAEAFcSAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAeAAAAAA==.',
It='Itzli:BAACLgAFFH8LAAIVAAQJmCDsDQB8AQAVAAQJmCDsDQB8AQAuAAQKfykAAhUACQnzIaMDAIsCABUACQnzIaMDAIsCAAEuAAUUBAkMAAkAiRwA.',
Iv='Ivee:BAAALgAECgcJCAABLgAFFAQJDAAJAIkcAA==.',
Ix='Ixtli:BAAALgAECgYJCAABLgAFFAQJDAAJAIkcAA==.',
Ja='Janner:BAAALgAECgQJBwAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgIJCQAAAA==.Jesdei:BAAALgAECgYJEQAAAA==.',
Jg='Jgwentworth:BAAALgAECgcJBwABLgAFFAUJDQACAAAJAA==.',
Jo='Jojen:BAABLgAECn8pAAMHAAkJuhgjHQDXAQAHAAkJuhgjHQDXAQAJAAQJ+AqmYgCLAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAgAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgQJCQAAAA==.Kavix:BAABLgAECn8mAAIaAAkJSxaOIwAsAgAaAAkJSxaOIwAsAgAAAA==.Kayos:BAACLgAFFH8QAAIZAAQJ3A9ESgAFAQAZAAQJ3A9ESgAFAQAuAAQKfygAAxkACQn8FO87ANQBABkACQktFO87ANQBAB8ABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAQJEAAZANwPAA==.Kelzexx:BAABLgAECn8oAAIJAAkJ4hFJHwDKAQAJAAkJ4hFJHwDKAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAIKAAkJrwouJQAnAQAKAAkJrwouJQAnAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAFFAMJBAABLgAFFAQJDAAJAIkcAA==.Kimed:BAAALgAECgYJBwAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krillian:BAAALgAECgEJBAAAAA==.',
Ku='Kula:BAABLgAECn8hAAIEAAgJkQ60YACBAQAEAAgJkQ60YACBAQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgQJDAAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAFFAQJCQAPAKIRAA==.',
La='Largetha:BAAALgAECgMJAwABLgAFFAQJDAAJAIkcAA==.Latro:BAACLgAFFH8fAAIEAAUJVxInPQAtAQAEAAUJVxInPQAtAQAuAAQKfysAAwQACQlrHHEoADkCAAQACQlrHHEoADkCABUAAQkIBcqSACcAAAAA.',
Le='Leenex:BAABLgAECn8UAAIUAAYJhgU0xwDAAAAUAAYJhgU0xwDAAAAAAA==.Leginer:BAABLgAECn8XAAIZAAYJXA51kQD5AAAZAAYJXA51kQD5AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Leguku:BAAALgAECgEJAQAAAA==.Lemiranas:BAAALgAECgYJBwAAAA==.Lepo:BAABLgAECn8hAAMMAAkJ4At6HgCfAQAMAAkJ4At6HgCfAQAgAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8dAAIaAAUJ1hVVIABNAQAaAAUJ1hVVIABNAQAuAAQKfykAAxoABwn/Gh88AKEBABoABwn/Gh88AKEBABcAAQmNFXKFADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8OAAIDAAQJkQzfNADuAAADAAQJkQzfNADuAAAuAAQKf0UAAwMACQn6HJwNAIQCAAMACQn1HJwNAIQCABEACAmZEgYNAAoCAAAA.',
Lu='Lunden:BAABLgAECn82AAQXAAkJ5xpgDwBnAgAXAAkJ6hlgDwBnAgAYAAgJ7BE4JwAXAQAbAAUJzw/HJwDKAAAAAA==.Luvalee:BAAALgAECgQJBAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgcJEwAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgIJAgABLgAFFAQJDAAJAIkcAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn8yAAIFAAkJRQmrGwA2AQAFAAkJRQmrGwA2AQAAAA==.Maladroit:BAAALgAECgUJBQABLgAFFAQJDAAJAIkcAA==.Maldus:BAACLgAFFH8MAAIJAAQJiRyzEQBVAQAJAAQJiRyzEQBVAQAuAAQKfyoAAgkACQnyHhoLAJ0CAAkACQnyHhoLAJ0CAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8NAAIhAAQJRx0LDgBEAQAhAAQJRx0LDgBEAQAuAAQKfyEAAiEACQngIKEEANYCACEACQngIKEEANYCAAAA.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQAMANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAFFAIJBQALACQKAA==.Marloak:BAABLgAECn8UAAMaAAYJeg8CWgAnAQAaAAYJeg8CWgAnAQAXAAIJhwZ2gwA+AAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAABLgAECn8UAAIcAAYJpQRUawCiAAAcAAYJpQRUawCiAAAAAA==.',
Mc='Mcbain:BAAALgADCgcJDAAAAA==.Mccormick:BAAALgAECgMJAwABLgAFFAQJDAAJAIkcAA==.',
Me='Merethyl:BAAALgAECgMJAwABLgAFFAUJEwAPABESAA==.Metaocalypse:BAAALgAECgcJDwAAAA==.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Missuswor:BAAALgAECgEJAQAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.Morrok:BAAALgAECgEJAgAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAeAAAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAwAAAA==.Nathali:BAAALgAECgYJCQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIFAAkJIBMPEgChAQAFAAkJIBMPEgChAQAAAA==.Nightshadye:BAACLgAFFH8aAAIKAAQJJBDWHwDlAAAKAAQJJBDWHwDlAAAuAAQKfyMAAgoACQl7Dx0dAGEBAAoACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAECgkJJwAZAOgUAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIXAAYJIA4BTwDMAAAXAAYJIA4BTwDMAAAAAA==.Notmonk:BAABLgAFFH8FAAIBAAMJ9xGxNwC9AAABAAMJ9xGxNwC9AAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8aAAIPAAUJRBm7TgBIAQAPAAUJRBm7TgBIAQAuAAQKfyAAAg8ACAmxId0bAAcDAA8ACAmxId0bAAcDAAAA.',
Om='Ombos:BAACLgAFFH8LAAMQAAQJUhmzGQDyAAAQAAMJfhuzGQDyAAADAAMJHQU3TACXAAAuAAQKf0QAAxAACQl7IVEDABMDABAACQl7IVEDABMDAAMABwm5FpwsAIgBAAAA.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn8fAAICAAgJaglXOQAZAQACAAgJaglXOQAZAQAAAA==.',
Oz='Ozrog:BAAALgAECgIJAgABLgAFFAQJEAAZANwPAA==.',
Pa='Palapinga:BAAALgAECgEJAgAAAA==.Pallypocket:BAAALgAFFAMJAwAAAA==.Pandacakes:BAAALgAECgYJCAAAAA==.Pandahalf:BAAALgAECgQJBgAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8ZAAIXAAcJkQ/5NQA6AQAXAAcJkQ/5NQA6AQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAeAAAAAA==.Pheldorai:BAABLgAECn8bAAMUAAkJBBHWPQDjAQAUAAkJBBHWPQDjAQAiAAEJdQQJNgAtAAABLgABCgMJAQAeAAAAAA==.Pheldrid:BAABLgAECn8eAAMHAAkJiCAoBwD7AgAHAAkJiCAoBwD7AgAJAAEJfwcViwAtAAABLgABCgMJAQAeAAAAAA==.Phàntoms:BAABLgAECn8ZAAITAAYJoxcqGAARAQATAAYJoxcqGAARAQAAAA==.',
Pr='Protector:BAAALgAECgYJEwABLgAFFAUJHwAEAFcSAA==.',
Pu='Puma:BAABLgAECn8lAAIYAAgJZQ+aJgAbAQAYAAgJZQ+aJgAbAQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIbAAcJrw2XHgANAQAbAAcJrw2XHgANAQAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgcJHgAdAA0OAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSFeBwDgAgADAAkJxSFeBwDgAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8RAAIHAAUJOgubFAAZAQAHAAUJOgubFAAZAQAuAAQKfx0AAgcACQmEDdk4AFgBAAcACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn8zAAIBAAkJWx9XCAATAwABAAkJWx9XCAATAwAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAABLgAECn8ZAAIaAAcJ/R0BIABEAgAaAAcJ/R0BIABEAgAAAA==.Razelda:BAAALgAECgYJEwAAAA==.Razelka:BAABLgAECn8gAAIWAAkJmhFSIwDXAQAWAAkJmhFSIwDXAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIPAAkJQROWUwDeAQAPAAkJQROWUwDeAQAAAA==.Repunzel:BAABLgAECn8fAAIGAAgJBAi8tQAUAQAGAAgJBAi8tQAUAQAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8QAAIPAAQJfw9YXwAsAQAPAAQJfw9YXwAsAQAuAAQKfy8AAg8ACQnuFelNAO4BAA8ACQnuFelNAO4BAAAA.Rozco:BAAALgAECgYJEQAAAA==.',
Ru='Rubmywolf:BAABLgAECn8kAAIEAAgJjxlfOgDxAQAEAAgJjxlfOgDxAQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAQJEAAYAB4SAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8qAAIEAAkJlBZyJQBIAgAEAAkJlBZyJQBIAgAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shadowmisty:BAAALgADCgcJCQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAABLgAECggJDQAeAAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgkJNwAFAJUKAA==.Shevah:BAABLgAECn8XAAIbAAkJghFAFgBgAQAbAAkJghFAFgBgAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgcJDwAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgQJCQAeAAAAAA==.',
Si='Sid:BAACLgAFFH8UAAIPAAcJkB8cEwCAAQAPAAcJkB8cEwCAAQAuAAQKfzAAAg8ACQm9JPcMAA8DAA8ACQm9JPcMAA8DAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgAECgEJAQAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAACLgAFFH8JAAIPAAQJohGlWwAyAQAPAAQJohGlWwAyAQAuAAQKfzoAAg8ACQmHHdgnAHkCAA8ACQmHHdgnAHkCAAAA.',
So='Sophié:BAAALgAECgYJDgABLgAFFAQJDAAJAIkcAA==.Souxie:BAAALgAECgQJDgAAAA==.',
Sp='Sprout:BAAALgAECgEJAQAAAA==.',
St='Starlost:BAAALgAECgkJBgAAAA==.Starnova:BAAALgAECgYJEQAAAA==.Stãr:BAABLgAECn8XAAIBAAYJLQNIigB8AAABAAYJLQNIigB8AAAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8iAAIUAAcJFgWusADjAAAUAAcJFgWusADjAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Sylvas:BAAALgAECgEJAQAAAA==.Synapse:BAABLgAECn8XAAICAAYJ1g0vQQD3AAACAAYJ1g0vQQD3AAAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAIIAAkJ8xZDLABNAgAIAAkJ8xZDLABNAgAAAA==.',
Ta='Taali:BAABLgAECn8lAAIGAAgJZgwelQBHAQAGAAgJZgwelQBHAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn81AAIgAAkJ8gutCQCMAQAgAAkJ8gutCQCMAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIVAAgJax0kCAD5AQAVAAgJax0kCAD5AQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8nAAIcAAkJDBtaFQA6AgAcAAkJDBtaFQA6AgAAAA==.Thomasten:BAACLgAFFH8WAAMfAAUJ3ySbCAB2AQAfAAQJ3ySbCAB2AQAZAAUJUxOXTQD9AAAuAAQKfyUABB8ACAk+Iz8TADwCAB8ACAm0ID8TADwCABIABQnrIRsOAGsBABkAAQmDAWA8AREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAcJFgAfAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECggJDQAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAUJHwAEAFcSAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8QAAIYAAQJHhKMEwDhAAAYAAQJHhKMEwDhAAAuAAQKfy8AAhgACQkfIH8EAMwCABgACQkfIH8EAMwCAAAA.Tricksibobby:BAABLgAECn8kAAQXAAgJ3SGFFQAhAgAXAAcJGSGFFQAhAgAaAAcJdRdQOQCuAQAbAAIJOBt3LwCeAAAAAA==.Tricksï:BAAALgAECgEJAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAeAAAAAA==.Tylèr:BAACLgAFFH8XAAMfAAUJmRuOCwBNAQAfAAUJDRuOCwBNAQASAAEJ+Ag6EgAzAAAuAAQKf0YABB8ACQmhH6AHALMCAB8ACQmhH6AHALMCABIAAQl4FHsxADoAABkAAQk2DbvcADUAAAAA.',
Uj='Ujak:BAABLgAECn8tAAIjAAkJgBNXCwD8AQAjAAkJgBNXCwD8AQAAAA==.',
Um='Umami:BAABLgAECn8mAAIOAAkJgRWWMQDpAQAOAAkJgRWWMQDpAQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJDQAAAA==.',
Va='Vaelion:BAAALgAECgYJEgAAAA==.Vanillacream:BAABLgAECn81AAIEAAkJZRWqMwAKAgAEAAkJZRWqMwAKAgAAAA==.',
Ve='Vermithrax:BAAALgAECgYJCgABLgAECgkJJwAZAOgUAA==.',
Vi='Viddar:BAABLgAECn8jAAISAAkJYx2oBABsAgASAAkJYx2oBABsAgAAAA==.Viroqua:BAACLgAFFH8VAAIJAAYJ9BD8DwBmAQAJAAYJ9BD8DwBmAQAuAAQKfzIAAgkACAkDGRAQAIUCAAkACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAEJAQABLgAECgkJGQAkAHoIAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgYJBgABLgAECgkJJwAZAOgUAA==.Winkelsmom:BAABLgAECn8rAAQXAAkJwxIiHgDTAQAXAAkJwxIiHgDTAQAaAAYJ3QqNcwDYAAAbAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8gAAMjAAcJJBqiEACkAQAjAAcJJBqiEACkAQAOAAYJvRJAWgBKAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn82AAIOAAkJXRnSHABiAgAOAAkJXRnSHABiAgAAAA==.',
Yo='Yogisa:BAABLgAECn9HAAMBAAkJ4RUTHgAiAgABAAkJ4RUTHgAiAgALAAEJAAC5rgAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAIIAAcJ+RhLVwC9AQAIAAcJ+RhLVwC9AQAAAA==.',
Za='Zariganja:BAAALgADCgIJAgAAAA==.Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zendiesel:BAAALgAECgYJBwABLgAECggJMwAVAGsdAA==.Zenogias:BAABLgAECn8gAAIPAAcJmxMVhABsAQAPAAcJmxMVhABsAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zombieshaman:BAAALgAECgEJAQABLgAFFAQJEAAYAB4SAA==.Zote:BAAALgADCgkJDwAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn9AAAIkAAkJcyHJBgAdAwAkAAkJcyHJBgAdAwAAAA==.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAMJBQAEAOEOAA==.',
['ßú']='ßúg:BAABLgAFFH8FAAMEAAMJ4Q6cZQDRAAAEAAMJ1gycZQDRAAAlAAEJOxcmLwBSAAAAAA==.',
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
