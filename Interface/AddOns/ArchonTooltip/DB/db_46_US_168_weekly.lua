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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Paladin-Protection','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Warrior-Fury','Druid-Balance','DemonHunter-Devourer','Druid-Guardian','Druid-Restoration','Druid-Feral','Shaman-Elemental','Priest-Discipline','DemonHunter-Havoc','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AmeKQDSAAABAAQJ+AmeKQDSAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAAALgAECgQJCAAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.',
Ar='Arana:BAAALgAECgIJAgAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIEAAkJlQphGgAsAQAEAAkJlQphGgAsAQAAAA==.Arkadias:BAAALgADCgEJAgAAAA==.Arthea:BAAALgAECgcJEAAAAA==.',
As='Asmmina:BAABLgAECn8jAAIFAAgJdQpOXQB1AQAFAAgJdQpOXQB1AQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8gAAIGAAgJRwpOjQA7AQAGAAgJRwpOjQA7AQAAAA==.',
Az='Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgMJAwAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIHAAkJghL/GwDPAQAHAAkJghL/GwDPAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAIIAAkJcSJWBwAsAwAIAAkJcSJWBwAsAwABLgAFFAYJEAAJAD0hAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJAwABLgAFFAMJBQAKAHgNAA==.',
Be='Beatrixx:BAAALgAECgEJAQAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAACLgAFFH8LAAIGAAMJNR+jSwD5AAAGAAMJNR+jSwD5AAAuAAQKfxUAAgYACAkWIbFDAOMBAAYACAkWIbFDAOMBAAAA.Bllacktotem:BAAALgAECgEJAQAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8aAAILAAkJiBdNDgAKAgALAAkJiBdNDgAKAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRqoDQBWAgACAAkJsRqoDQBWAgAMAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAIAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgEJAQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMNAAkJeRYAFQDfAQANAAkJeRYAFQDfAQAOAAIJdQupHQA/AAABLgAFFAIJAwAPAAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAABLgAECn8XAAIQAAkJMApSTQBeAQAQAAkJMApSTQBeAQAAAA==.Cheese:BAAALgAECgYJEQAAAA==.Cheesemix:BAABLgAECn8bAAIQAAYJXg1NYwASAQAQAAYJXg1NYwASAQABLgAECgkJRQAQAMYhAA==.Chesleigh:BAAALgAECgMJCAAAAA==.',
Ci='Cinderlight:BAABLgAECn8oAAIGAAkJ8BG6TADIAQAGAAkJ8BG6TADIAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAECgkJNAAJAL0YAA==.Crilynn:BAACLgAFFH8OAAIJAAQJSQ5MXgAUAQAJAAQJSQ5MXgAUAQAuAAQKfyQAAgkACQlOGBEwAEECAAkACQlOGBEwAEECAAAA.Crispycrittr:BAABLgAECn8eAAMRAAgJiAdbJQBMAQARAAgJiAdbJQBMAQASAAEJwwL/JgAjAAAAAA==.Cryhavoc:BAABLgAECn8jAAITAAgJLBMpCwCPAQATAAgJLBMpCwCPAQAAAA==.',
Cy='Cyssor:BAAALgAECgMJCAAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAAALgAECgMJCAAAAA==.Dathdeath:BAABLgAECn8hAAIUAAcJPg+gEwAUAQAUAAcJPg+gEwAUAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.',
Di='Dillapuss:BAAALgADCgEJAQAAAA==.Dimitri:BAAALgAECgEJAQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIIAAMJ7g1bLADqAAAIAAMJ7g1bLADqAAAuAAQKfygAAggACAm8IugYAOcCAAgACAm8IugYAOcCAAAA.',
Do='Docken:BAAALgAECgcJCwABLgAECgkJNAAJAL0YAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJAgAAAA==.Dotdotded:BAAALgAECgQJAwAAAA==.Dotsomahan:BAABLgAECn8YAAIVAAkJWA8AVACUAQAVAAkJWA8AVACUAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIWAAkJSRZ6CADhAQAWAAkJSRZ6CADhAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAABLgAECn8fAAIXAAcJlgigRwAPAQAXAAcJlgigRwAPAQAAAA==.Druidfaime:BAAALgAECgQJCgAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAQAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgADCgEJAQAAAA==.',
El='Elise:BAABLgAECn8WAAIYAAYJUB8vHgC9AQAYAAYJUB8vHgC9AQAAAA==.Ellzik:BAAALgAECgcJEgAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgMJBQABLgAFFAMJBQAKAHgNAA==.',
Fa='Falorien:BAABLgAECn8iAAIJAAcJHBPqewBlAQAJAAcJHBPqewBlAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8lAAIZAAgJXBRHWwBdAQAZAAgJXBRHWwBdAQAAAA==.',
Fl='Flamingpax:BAAALgAECgIJAwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBgABLgAFFAMJCAAJABQPAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAABLgAECn8pAAIIAAgJHCAcJQBcAgAIAAgJHCAcJQBcAgAAAA==.Fluffinhigh:BAABLgAECn8gAAUaAAgJ9BkZDAAAAgAaAAgJkxkZDAAAAgAYAAYJqRc9LwBIAQAbAAMJ9RX6ewCzAAAcAAIJZQuKPgBDAAABLgAECggJKQAIABwgAA==.Fluffybúnny:BAAALgAECgMJCAABLgAECgQJCAAPAAAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJNwAEAJUKAA==.Freakadeek:BAAALgAECgUJBQAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8gAAIVAAgJJg1LdQBEAQAVAAgJJg1LdQBEAQAAAA==.',
Gi='Giorgina:BAABLgAECn8mAAIdAAgJYBa4KACQAQAdAAgJYBa4KACQAQAAAA==.',
Gl='Glasc:BAABLgAECn8eAAMeAAcJDQ5bLgBDAQAeAAcJDQ5bLgBDAQAKAAYJ7Q3jPQD1AAAAAA==.',
Gn='Gnowances:BAAALgADCgkJCwAAAA==.',
Go='Goobynuk:BAABLgAECn8gAAIJAAkJKhmbMAA/AgAJAAkJKhmbMAA/AgAAAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAIJAwAPAAAAAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMNAAcJ1x2XGQA3AgANAAcJ3RyXGQA3AgAOAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAECgYJCAABLgAFFAQJFgAFAJ4RAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAPAAAAAA==.',
It='Itzli:BAABLgAECn8mAAIWAAkJ8yE4AwCPAgAWAAkJ8yE4AwCPAgABLgAFFAMJBQAKAHgNAA==.',
Iv='Ivee:BAAALgAECgcJCAABLgAFFAMJBQAKAHgNAA==.',
Ix='Ixtli:BAAALgAECgYJBwABLgAFFAMJBQAKAHgNAA==.',
Ja='Janner:BAAALgADCgkJEQAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgIJBQAAAA==.Jesdei:BAAALgAECgQJDQAAAA==.',
Jo='Jojen:BAABLgAECn8pAAMHAAkJuhj5GQDjAQAHAAkJuhj5GQDjAQAKAAQJ+AolXAB3AAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAQAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgIJAwAAAA==.Kavix:BAABLgAECn8mAAIbAAkJSxYeIQAsAgAbAAkJSxYeIQAsAgAAAA==.Kayos:BAACLgAFFH8IAAIZAAMJrQtUWADEAAAZAAMJrQtUWADEAAAuAAQKfygAAxkACQn8FIc2ANUBABkACQktFIc2ANUBAB8ABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAMJCAAZAK0LAA==.Kelzexx:BAABLgAECn8fAAIKAAkJOxHrHgCvAQAKAAkJOxHrHgCvAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAILAAkJrwocIQAwAQALAAkJrwocIQAwAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAFFAEJAQABLgAFFAMJBQAKAHgNAA==.Kimed:BAAALgAECgEJAQAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krillian:BAAALgAECgEJAwAAAA==.',
Ku='Kula:BAABLgAECn8fAAIFAAgJeg7kVACMAQAFAAgJeg7kVACMAQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgMJCAAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAECgkJNAAJAL0YAA==.',
La='Latro:BAACLgAFFH8WAAIFAAQJnhEwMgAxAQAFAAQJnhEwMgAxAQAuAAQKfysAAwUACQlrHGciAEQCAAUACQlrHGciAEQCABYAAQkIBcqSACcAAAAA.',
Le='Leenex:BAAALgAECgYJDgAAAA==.Leginer:BAABLgAECn8YAAIZAAYJXA4EhgD2AAAZAAYJXA4EhgD2AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Lemiranas:BAAALgAECgEJAQAAAA==.Lepo:BAABLgAECn8hAAMNAAkJ4AtrGwCjAQANAAkJ4AtrGwCjAQAgAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8ZAAIbAAUJdRS9GwBbAQAbAAUJdRS9GwBbAQAuAAQKfykAAxsABwn/GoY4AKIBABsABwn/GoY4AKIBABgAAQmNFVp6ADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8HAAIDAAMJggy4OgC6AAADAAMJggy4OgC6AAAuAAQKfz8AAwMACQn6HJ8MAHkCAAMACQn1HJ8MAHkCABIACAmZEgYNAAoCAAAA.',
Lu='Lunden:BAABLgAECn8tAAQYAAkJZBVrHQDDAQAYAAkJKRJrHQDDAQAaAAgJ7BEAIgAZAQAcAAUJzw/eIgDLAAAAAA==.Luvalee:BAAALgAECgQJBAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgMJDAAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgEJAQABLgAFFAMJBQAKAHgNAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn8pAAIEAAkJ+AhnGQA0AQAEAAkJ+AhnGQA0AQAAAA==.Maldus:BAACLgAFFH8FAAIKAAMJeA0uIADNAAAKAAMJeA0uIADNAAAuAAQKfyoAAgoACQnyHpUJAJsCAAoACQnyHpUJAJsCAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8GAAIhAAIJbB9BGQC0AAAhAAIJbB9BGQC0AAAuAAQKfxwAAiEACAn3IXcGAJECACEACAn3IXcGAJECAAAA.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQANANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAECgkJJAACANYQAA==.Marloak:BAAALgAECgYJEAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAAALgAECgYJEgAAAA==.',
Mc='Mcbain:BAAALgADCgcJDAAAAA==.',
Me='Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.Morrok:BAAALgAECgEJAQAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAgAAAA==.Nathali:BAAALgAECgYJCAAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIEAAkJIBM5EACmAQAEAAkJIBM5EACmAQAAAA==.Nightshadye:BAACLgAFFH8SAAILAAQJJBCRGQDvAAALAAQJJBCRGQDvAAAuAAQKfyMAAgsACQl7Dx0dAGEBAAsACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAECggJJQAZAFwUAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIYAAYJIA5hSADOAAAYAAYJIA5hSADOAAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8WAAIJAAUJvRheRwA/AQAJAAUJvRheRwA/AQAuAAQKfyAAAgkACAmxId0bAAcDAAkACAmxId0bAAcDAAAA.',
Om='Ombos:BAABLgAECn9CAAMRAAkJeyEIAwAVAwARAAkJeyEIAwAVAwADAAYJmxWNNgA0AQAAAA==.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn8eAAICAAgJvghhNAAcAQACAAgJvghhNAAcAQAAAA==.',
Pa='Palapinga:BAAALgAECgEJAgAAAA==.Pallypocket:BAAALgAECgYJCAAAAA==.Pandacakes:BAAALgAECgYJCAAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8UAAIYAAcJ2QpJOwAIAQAYAAcJ2QpJOwAIAQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAPAAAAAA==.Pheldorai:BAABLgAECn8VAAMVAAkJ/wyTSgCvAQAVAAkJ/wyTSgCvAQAiAAEJdQQJNgAtAAABLgABCgMJAQAPAAAAAA==.Pheldrid:BAABLgAECn8eAAMHAAkJiCD4BQAGAwAHAAkJiCD4BQAGAwAKAAEJfwfKfAAtAAABLgABCgMJAQAPAAAAAA==.Phàntoms:BAABLgAECn8ZAAIUAAYJoxdsFQABAQAUAAYJoxdsFQABAQAAAA==.',
Pr='Protector:BAAALgAECgYJEwABLgAFFAQJFgAFAJ4RAA==.',
Pu='Puma:BAABLgAECn8jAAIaAAgJEw+tIQAbAQAaAAgJEw+tIQAbAQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIcAAcJrw0iGgAWAQAcAAcJrw0iGgAWAQAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgcJHgAeAA0OAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSGKBgDbAgADAAkJxSGKBgDbAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8PAAIHAAQJkgxIFgDqAAAHAAQJkgxIFgDqAAAuAAQKfx0AAgcACQmEDdk4AFgBAAcACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn8qAAIBAAkJNR9XBwAMAwABAAkJNR9XBwAMAwAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAABLgAECn8ZAAIbAAcJ/R2VHQBGAgAbAAcJ/R2VHQBGAgAAAA==.Razelda:BAAALgAECgYJEAAAAA==.Razelka:BAABLgAECn8gAAIXAAkJmhHgHwDcAQAXAAkJmhHgHwDcAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIJAAkJQRNnTADfAQAJAAkJQRNnTADfAQAAAA==.Repunzel:BAABLgAECn8eAAIGAAgJBAjvpwAPAQAGAAgJBAjvpwAPAQAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8IAAIJAAMJFA9kcADhAAAJAAMJFA9kcADhAAAuAAQKfy8AAgkACQnuFSFHAO8BAAkACQnuFSFHAO8BAAAA.Rozco:BAAALgAECgUJCwAAAA==.',
Ru='Rubmywolf:BAABLgAECn8jAAIFAAgJjxmuMQD+AQAFAAgJjxmuMQD+AQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAMJCAAaANARAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8iAAIFAAkJ5BH/MgD6AQAFAAkJ5BH/MgD6AQAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shadowmisty:BAAALgADCgcJCQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgkJNwAEAJUKAA==.Shevah:BAABLgAECn8XAAIcAAkJghF2EwBiAQAcAAkJghF2EwBiAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgYJDgAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgQJBgAPAAAAAA==.',
Si='Sid:BAACLgAFFH8QAAIJAAYJPSEcEwCAAQAJAAYJPSEcEwCAAQAuAAQKfy8AAgkACQm9JF4VACgDAAkACQm9JF4VACgDAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgADCgEJAQAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAABLgAECn80AAIJAAkJvRhsPgALAgAJAAkJvRhsPgALAgAAAA==.',
So='Sophié:BAAALgAECgYJCQABLgAFFAMJBQAKAHgNAA==.Souxie:BAAALgAECgMJCAAAAA==.',
St='Starnova:BAAALgAECgYJDwAAAA==.Stãr:BAAALgAECgYJDwAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8hAAIVAAcJFgXZpQDqAAAVAAcJFgXZpQDqAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Synapse:BAABLgAECn8VAAICAAYJbAmdRgDOAAACAAYJbAmdRgDOAAAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAIIAAkJ8xYbJwBSAgAIAAkJ8xYbJwBSAgAAAA==.',
Ta='Taali:BAABLgAECn8jAAIGAAgJKgsflwArAQAGAAgJKgsflwArAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn8sAAIgAAkJOgrICQB1AQAgAAkJOgrICQB1AQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIWAAgJax0zBwABAgAWAAgJax0zBwABAgAAAA==.Tellera:BAAALgAECgEJAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8nAAIdAAkJDBu/EgBAAgAdAAkJDBu/EgBAAgAAAA==.Thomasten:BAACLgAFFH8WAAMfAAUJ3yQcBQCKAQAfAAQJ3yQcBQCKAQAZAAUJUxNXPwAPAQAuAAQKfyUABB8ACAk+Iz8TADwCAB8ACAm0ID8TADwCABMABQnrIdkMAG4BABkAAQmDAVUiAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAYJFgAfAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECgUJBgABLgAECgYJDAAPAAAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAQJFgAFAJ4RAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8IAAIaAAMJ0BEzFgCuAAAaAAMJ0BEzFgCuAAAuAAQKfy8AAhoACQkfIMEDANECABoACQkfIMEDANECAAAA.Tricksibobby:BAABLgAECn8jAAQYAAgJ6yBYFQAPAgAYAAcJ/x9YFQAPAgAbAAcJdRfsNQCuAQAcAAIJOBubKQCgAAAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAPAAAAAA==.Tylèr:BAACLgAFFH8SAAMfAAQJchu9BwBbAQAfAAQJ5xq9BwBbAQATAAEJ+AjODgA1AAAuAAQKf0YABB8ACQmhHx0GAL0CAB8ACQmhHx0GAL0CABMAAQl4FH8sADsAABkAAQk2DbvcADUAAAAA.',
Uj='Ujak:BAABLgAECn8pAAIjAAgJpxKBDgCrAQAjAAgJpxKBDgCrAQAAAA==.',
Um='Umami:BAABLgAECn8mAAIQAAkJgRXDLADrAQAQAAkJgRXDLADrAQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJCgAAAA==.',
Va='Vaelion:BAAALgAECgYJEgAAAA==.Vanillacream:BAABLgAECn8sAAIFAAkJ+hSbMQD/AQAFAAkJ+hSbMQD/AQAAAA==.',
Vi='Viddar:BAABLgAECn8jAAITAAkJYx3/AwBzAgATAAkJYx3/AwBzAgAAAA==.Viroqua:BAACLgAFFH8VAAIKAAYJ9BA6DAB5AQAKAAYJ9BA6DAB5AQAuAAQKfzIAAgoACAkDGRAQAIUCAAoACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAEJAQABLgAECgkJGQAkAHoIAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgQJAQABLgAECggJJQAZAFwUAA==.Winkelsmom:BAABLgAECn8iAAQYAAkJIhIpHQDGAQAYAAkJIhIpHQDGAQAbAAUJtwshigCQAAAcAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8fAAMjAAcJTBkfDwCgAQAjAAcJTBkfDwCgAQAQAAYJvRJTUgBLAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn8tAAIQAAkJdBcHHwA8AgAQAAkJdBcHHwA8AgAAAA==.',
Yo='Yogisa:BAABLgAECn88AAMBAAkJOhXCGwATAgABAAkJOhXCGwATAgAMAAEJAAB1pAAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAIIAAcJ+RgAUADAAQAIAAcJ+RgAUADAAQAAAA==.',
Za='Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zendiesel:BAAALgAECgYJBwABLgAECggJMwAWAGsdAA==.Zenogias:BAABLgAECn8fAAIJAAYJWxWZkAA8AQAJAAYJWxWZkAA8AQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zote:BAAALgADCgkJCQAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn84AAIkAAgJlCN4DACzAgAkAAgJlCN4DACzAgAAAA==.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAIJAwAPAAAAAA==.',
['ßú']='ßúg:BAAALgAFFAIJAwAAAA==.',
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
