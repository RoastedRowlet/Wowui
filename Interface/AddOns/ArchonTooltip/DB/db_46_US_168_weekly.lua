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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Paladin-Protection','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Warrior-Fury','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Shaman-Elemental','Priest-Discipline','Unknown-Unknown','DemonHunter-Havoc','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Shaman-Enhancement','Paladin-Holy','Hunter-Survival',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AlKMADMAAABAAQJ+AlKMADMAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAAALgAECgYJDgAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.',
Ar='Arana:BAAALgAECgMJAwAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIEAAkJlQogHAApAQAEAAkJlQogHAApAQAAAA==.Arkadias:BAAALgADCgEJAgAAAA==.Arthea:BAAALgAECgcJEAAAAA==.',
As='Asmmina:BAABLgAECn8kAAIFAAgJdQrSYwBwAQAFAAgJdQrSYwBwAQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8iAAIGAAgJcgqykABFAQAGAAgJcgqykABFAQAAAA==.',
Az='Azalan:BAAALgAECgEJAQAAAA==.Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgMJAwAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIHAAkJghKAHgDBAQAHAAkJghKAHgDBAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAIIAAkJcSJFCAApAwAIAAkJcSJFCAApAwABLgAFFAYJEAAJAD0hAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJBAABLgAFFAQJCAAKADcQAA==.',
Be='Beatrixx:BAAALgAECggJDQAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAACLgAFFH8LAAIGAAMJNR8uVQDyAAAGAAMJNR8uVQDyAAAuAAQKfxcAAgYACQluIeMqAEsCAAYACQluIeMqAEsCAAAA.Bllacktotem:BAAALgAFFAIJAgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8iAAILAAkJuhx7CACFAgALAAkJuhx7CACFAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRrSDgBQAgACAAkJsRrSDgBQAgAMAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAIAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgEJAQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMNAAkJeRaoFgDZAQANAAkJeRaoFgDZAQAOAAIJdQupHQA/AAABLgAFFAMJBQAFAOEOAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAABLgAECn8XAAIPAAkJMAr+UQBcAQAPAAkJMAr+UQBcAQAAAA==.Cheese:BAABLgAECn8XAAMCAAcJIBmMHAC9AQACAAcJIBmMHAC9AQABAAQJPxLwYADWAAAAAA==.Cheesemix:BAABLgAECn8bAAIPAAYJXg2RaAASAQAPAAYJXg2RaAASAQABLgAECgkJRgAPAMYhAA==.Chesleigh:BAAALgAECgQJDAAAAA==.',
Ci='Cinderlight:BAABLgAECn8tAAIGAAkJ8BFcUgDHAQAGAAkJ8BFcUgDHAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAFFAMJBgAJABESAA==.Crilynn:BAACLgAFFH8TAAIJAAUJERJtVwAvAQAJAAUJERJtVwAvAQAuAAQKfyQAAgkACQlOGIEzAEQCAAkACQlOGIEzAEQCAAAA.Crispycrittr:BAABLgAECn8eAAMQAAgJiAdbJQBMAQAQAAgJiAdbJQBMAQARAAEJwwIGKQAiAAAAAA==.Crotchcriter:BAAALgAECgEJAQAAAA==.Cryhavoc:BAABLgAECn8kAAISAAgJLBPBCwCNAQASAAgJLBPBCwCNAQAAAA==.',
Cy='Cyssor:BAAALgAECgQJCQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAAALgAECgQJDAAAAA==.Dathdeath:BAABLgAECn8iAAITAAcJPg/vFAAlAQATAAcJPg/vFAAlAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.',
Di='Dillapuss:BAAALgADCgEJAQAAAA==.Dimitri:BAAALgAECgEJAQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIIAAMJ7g1bLADqAAAIAAMJ7g1bLADqAAAuAAQKfygAAggACAm8IugYAOcCAAgACAm8IugYAOcCAAAA.',
Do='Docken:BAAALgAECgcJCwABLgAFFAMJBgAJABESAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJAgAAAA==.Dotdotded:BAAALgAECgcJBgAAAA==.Dotsomahan:BAABLgAECn8YAAIUAAkJWA82WQCNAQAUAAkJWA82WQCNAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIVAAkJSRYfCQDaAQAVAAkJSRYfCQDaAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAABLgAECn8gAAIWAAcJlghjSwAPAQAWAAcJlghjSwAPAQAAAA==.Druidfaime:BAAALgAECgUJDgAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAQAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgAECgEJAQAAAA==.',
El='Elise:BAABLgAECn8WAAIXAAYJUB++HwC8AQAXAAYJUB++HwC8AQAAAA==.Ellzik:BAABLgAECn8UAAMYAAcJ5wsmLwDbAAAYAAcJ5wsmLwDbAAAXAAQJxAMYZgB0AAAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgUJCgABLgAFFAQJCAAKADcQAA==.',
Fa='Falorien:BAABLgAECn8kAAIJAAgJwBIQagChAQAJAAgJwBIQagChAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8nAAIZAAkJ6BSLRQCqAQAZAAkJ6BSLRQCqAQAAAA==.',
Fl='Flamingpax:BAAALgAECgIJBAAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBgABLgAFFAQJDAAJAKMNAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAABLgAECn8pAAIIAAgJHCDwJwBaAgAIAAgJHCDwJwBaAgAAAA==.Fluffinhigh:BAABLgAECn8iAAUYAAgJkhrjCwATAgAYAAgJkhrjCwATAgAXAAYJqRe0MQBHAQAaAAMJ9RU4fwCyAAAbAAIJZQtuRABCAAABLgAECggJKQAIABwgAA==.Fluffybúnny:BAAALgAECgQJDAAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJNwAEAJUKAA==.Freakadeek:BAAALgAECgUJBQAAAA==.',
Fu='Furrious:BAAALgAECgQJBAAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8gAAIUAAgJJg0oegBAAQAUAAgJJg0oegBAAQAAAA==.',
Gi='Giorgina:BAACLgAFFH8HAAIcAAMJPQ+CLwDDAAAcAAMJPQ+CLwDDAAAuAAQKfycAAhwACAnXFw8lALIBABwACAnXFw8lALIBAAAA.',
Gl='Glasc:BAABLgAECn8eAAMdAAcJDQ4ZMQBKAQAdAAcJDQ4ZMQBKAQAKAAYJ7Q1hQAAGAQAAAA==.',
Gn='Gnowances:BAAALgADCgkJCwAAAA==.',
Go='Goobynuk:BAABLgAECn8gAAIJAAkJKhm6MwBDAgAJAAkJKhm6MwBDAgAAAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAMJBQAFAOEOAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMNAAcJ1x2XGQA3AgANAAcJ3RyXGQA3AgAOAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAECgcJCQABLgAFFAUJGgAFAFcSAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAeAAAAAA==.',
It='Itzli:BAACLgAFFH8HAAIVAAMJqCM5EQA6AQAVAAMJqCM5EQA6AQAuAAQKfygAAhUACQnzIWgDAI4CABUACQnzIWgDAI4CAAEuAAUUBAkIAAoANxAA.',
Iv='Ivee:BAAALgAECgcJCAABLgAFFAQJCAAKADcQAA==.',
Ix='Ixtli:BAAALgAECgYJCAABLgAFFAQJCAAKADcQAA==.',
Ja='Janner:BAAALgAECgMJAwAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgIJBwAAAA==.Jesdei:BAAALgAECgUJDwAAAA==.',
Jg='Jgwentworth:BAAALgAECgcJBwABLgAFFAUJDQACAAAJAA==.',
Jo='Jojen:BAABLgAECn8pAAMHAAkJuhi9GwDbAQAHAAkJuhi9GwDbAQAKAAQJ+Ar/XQCRAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAgAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgQJBwAAAA==.Kavix:BAABLgAECn8mAAIaAAkJSxaUIgArAgAaAAkJSxaUIgArAgAAAA==.Kayos:BAACLgAFFH8MAAIZAAQJ+wsbSgD9AAAZAAQJ+wsbSgD9AAAuAAQKfygAAxkACQn8FPk5ANMBABkACQktFPk5ANMBAB8ABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAQJDAAZAPsLAA==.Kelzexx:BAABLgAECn8nAAIKAAkJ4hHeHQDOAQAKAAkJ4hHeHQDOAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAILAAkJrwoqIwAuAQALAAkJrwoqIwAuAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAFFAIJAwABLgAFFAQJCAAKADcQAA==.Kimed:BAAALgAECgYJBwAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krillian:BAAALgAECgEJBAAAAA==.',
Ku='Kula:BAABLgAECn8hAAIFAAgJkQ7bWgCIAQAFAAgJkQ7bWgCIAQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgQJDAAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAFFAMJBgAJABESAA==.',
La='Latro:BAACLgAFFH8aAAIFAAUJVxKLNwAzAQAFAAUJVxKLNwAzAQAuAAQKfysAAwUACQlrHJslAD8CAAUACQlrHJslAD8CABUAAQkIBcqSACcAAAAA.',
Le='Leenex:BAAALgAECgYJEwAAAA==.Leginer:BAABLgAECn8YAAIZAAYJXA68jAD5AAAZAAYJXA68jAD5AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Lemiranas:BAAALgAECgYJBwAAAA==.Lepo:BAABLgAECn8hAAMNAAkJ4AtCHQCfAQANAAkJ4AtCHQCfAQAgAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8dAAIaAAUJ1hXEHQBbAQAaAAUJ1hXEHQBbAQAuAAQKfykAAxoABwn/Gq06AKEBABoABwn/Gq06AKEBABcAAQmNFbmAADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8KAAIDAAQJ8AqXMgDuAAADAAQJ8AqXMgDuAAAuAAQKf0IAAwMACQn6HCoNAIQCAAMACQn1HCoNAIQCABEACAmZEgYNAAoCAAAA.',
Lu='Lunden:BAABLgAECn81AAQXAAkJmRlGEABRAgAXAAkJnBhGEABRAgAYAAgJ7BEhJQAWAQAbAAUJzw+oJQDKAAAAAA==.Luvalee:BAAALgAECgQJBAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgUJEQAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgIJAgABLgAFFAQJCAAKADcQAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn8xAAIEAAkJDgm/GgA1AQAEAAkJDgm/GgA1AQAAAA==.Maldus:BAACLgAFFH8IAAIKAAQJNxAMFwAcAQAKAAQJNxAMFwAcAQAuAAQKfyoAAgoACQnyHpAKAKACAAoACQnyHpAKAKACAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8JAAIhAAMJpxwFFADxAAAhAAMJpxwFFADxAAAuAAQKfx4AAiEACQngIFIEANcCACEACQngIFIEANcCAAAA.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQANANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAECgkJKwAMAM8VAA==.Marloak:BAABLgAECn8UAAMaAAYJeg8KWAAnAQAaAAYJeg8KWAAnAQAXAAIJhwZ4fgA/AAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAAALgAECgYJEgAAAA==.',
Mc='Mcbain:BAAALgADCgcJDAAAAA==.',
Me='Metaocalypse:BAAALgAECgcJBwAAAA==.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.Morrok:BAAALgAECgEJAQAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAeAAAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAgAAAA==.Nathali:BAAALgAECgYJCQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIEAAkJIBM+EQCkAQAEAAkJIBM+EQCkAQAAAA==.Nightshadye:BAACLgAFFH8WAAILAAQJJBAsHQDqAAALAAQJJBAsHQDqAAAuAAQKfyMAAgsACQl7Dx0dAGEBAAsACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAECgkJJwAZAOgUAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIXAAYJIA4RTADNAAAXAAYJIA4RTADNAAAAAA==.Notmonk:BAAALgAFFAMJBAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8ZAAIJAAUJRBkzRwBMAQAJAAUJRBkzRwBMAQAuAAQKfyAAAgkACAmxId0bAAcDAAkACAmxId0bAAcDAAAA.',
Om='Ombos:BAACLgAFFH8HAAMQAAMJehawGwDMAAAQAAMJehawGwDMAAADAAIJoAQyVABrAAAuAAQKf0QAAxAACQl7ISgDABYDABAACQl7ISgDABYDAAMABwm5FiYrAIkBAAAA.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn8fAAICAAgJaglbNgAdAQACAAgJaglbNgAdAQAAAA==.',
Pa='Palapinga:BAAALgAECgEJAgAAAA==.Pallypocket:BAAALgAFFAMJAwAAAA==.Pandacakes:BAAALgAECgYJCAAAAA==.Pandahalf:BAAALgAECgQJBAAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8ZAAIXAAcJkQ/HMwA8AQAXAAcJkQ/HMwA8AQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAeAAAAAA==.Pheldorai:BAABLgAECn8bAAMUAAkJBBEmOwDpAQAUAAkJBBEmOwDpAQAiAAEJdQQJNgAtAAABLgABCgMJAQAeAAAAAA==.Pheldrid:BAABLgAECn8eAAMHAAkJiCCXBgD+AgAHAAkJiCCXBgD+AgAKAAEJfwd6hQAtAAABLgABCgMJAQAeAAAAAA==.Phàntoms:BAABLgAECn8ZAAITAAYJoxeoFgAUAQATAAYJoxeoFgAUAQAAAA==.',
Pr='Protector:BAAALgAECgYJEwABLgAFFAUJGgAFAFcSAA==.',
Pu='Puma:BAABLgAECn8lAAIYAAgJZQ9hJAAbAQAYAAgJZQ9hJAAbAQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIbAAcJrw1RHAAUAQAbAAcJrw1RHAAUAQAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgcJHgAdAA0OAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSERBwDhAgADAAkJxSERBwDhAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8QAAIHAAQJkgxHGQDcAAAHAAQJkgxHGQDcAAAuAAQKfx0AAgcACQmEDdk4AFgBAAcACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn8yAAIBAAkJWx/ABwATAwABAAkJWx/ABwATAwAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAABLgAECn8ZAAIaAAcJ/R0VHwBEAgAaAAcJ/R0VHwBEAgAAAA==.Razelda:BAAALgAECgYJEgAAAA==.Razelka:BAABLgAECn8gAAIWAAkJmhHzIQDbAQAWAAkJmhHzIQDbAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIJAAkJQRNOTgDqAQAJAAkJQRNOTgDqAQAAAA==.Repunzel:BAABLgAECn8fAAIGAAgJBAhXrgAWAQAGAAgJBAhXrgAWAQAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8MAAIJAAQJow3ZXAAmAQAJAAQJow3ZXAAmAQAuAAQKfy8AAgkACQnuFQFLAPQBAAkACQnuFQFLAPQBAAAA.Rozco:BAAALgAECgUJCwAAAA==.',
Ru='Rubmywolf:BAABLgAECn8kAAIFAAgJjxnKNgD3AQAFAAgJjxnKNgD3AQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAQJDAAYABwSAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8qAAIFAAkJlBajIgBPAgAFAAkJlBajIgBPAgAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shadowmisty:BAAALgADCgcJCQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAABLgAECggJDQAeAAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgkJNwAEAJUKAA==.Shevah:BAABLgAECn8XAAIbAAkJghEgFQBgAQAbAAkJghEgFQBgAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgcJDwAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgQJBgAeAAAAAA==.',
Si='Sid:BAACLgAFFH8QAAIJAAYJPSEcEwCAAQAJAAYJPSEcEwCAAQAuAAQKfzAAAgkACQm9JOgLABUDAAkACQm9JOgLABUDAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgAECgEJAQAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAACLgAFFH8GAAIJAAMJERI8cgDtAAAJAAMJERI8cgDtAAAuAAQKfzcAAgkACQlZHUQsAGICAAkACQlZHUQsAGICAAAA.',
So='Sophié:BAAALgAECgYJCQABLgAFFAQJCAAKADcQAA==.Souxie:BAAALgAECgQJDAAAAA==.',
Sp='Sprout:BAAALgAECgEJAQAAAA==.',
St='Starnova:BAAALgAECgYJEQAAAA==.Stãr:BAABLgAECn8XAAIBAAYJLAMhgQB8AAABAAYJLAMhgQB8AAAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8iAAIUAAcJFgUzrADlAAAUAAcJFgUzrADlAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Synapse:BAABLgAECn8XAAICAAYJ1g24PgD3AAACAAYJ1g24PgD3AAAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAIIAAkJ8xYUKgBQAgAIAAkJ8xYUKgBQAgAAAA==.',
Ta='Taali:BAABLgAECn8lAAIGAAgJZgy/jgBJAQAGAAgJZgy/jgBJAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn80AAIgAAkJQwuSCQCFAQAgAAkJQwuSCQCFAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIVAAgJax3KBwD7AQAVAAgJax3KBwD7AQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8nAAIcAAkJDBsvFAA8AgAcAAkJDBsvFAA8AgAAAA==.Thomasten:BAACLgAFFH8WAAMfAAUJ3yTqBgB+AQAfAAQJ3yTqBgB+AQAZAAUJUxPsRwADAQAuAAQKfyUABB8ACAk+Iz8TADwCAB8ACAm0ID8TADwCABIABQnrIXUNAGwBABkAAQmDATEwAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAYJFgAfAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECggJDQAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAUJGgAFAFcSAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8MAAIYAAQJHBJOEQDiAAAYAAQJHBJOEQDiAAAuAAQKfy8AAhgACQkfIDYEAM0CABgACQkfIDYEAM0CAAAA.Tricksibobby:BAABLgAECn8kAAQXAAgJ3SGJFAAiAgAXAAcJGSGJFAAiAgAaAAcJdRfWNwCuAQAbAAIJOBvYLACfAAAAAA==.Tricksï:BAAALgAECgEJAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAeAAAAAA==.Tylèr:BAACLgAFFH8VAAMfAAUJmRuCCQBVAQAfAAUJDRuCCQBVAQASAAEJ+AitEAAzAAAuAAQKf0YABB8ACQmhH/0GALcCAB8ACQmhH/0GALcCABIAAQl4FDkvADoAABkAAQk2DbvcADUAAAAA.',
Uj='Ujak:BAABLgAECn8tAAIjAAkJgBO3CgD+AQAjAAkJgBO3CgD+AQAAAA==.',
Um='Umami:BAABLgAECn8mAAIPAAkJgRWSLwDpAQAPAAkJgRWSLwDpAQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJDAAAAA==.',
Va='Vaelion:BAAALgAECgYJEgAAAA==.Vanillacream:BAABLgAECn80AAIFAAkJZRUFMQANAgAFAAkJZRUFMQANAgAAAA==.',
Ve='Vermithrax:BAAALgAECgYJBgABLgAECgkJJwAZAOgUAA==.',
Vi='Viddar:BAABLgAECn8jAAISAAkJYx1nBABtAgASAAkJYx1nBABtAgAAAA==.Viroqua:BAACLgAFFH8VAAIKAAYJ9BCSDgBoAQAKAAYJ9BCSDgBoAQAuAAQKfzIAAgoACAkDGRAQAIUCAAoACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAEJAQABLgAECgkJGQAkAHoIAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgQJAQABLgAECgkJJwAZAOgUAA==.Winkelsmom:BAABLgAECn8qAAQXAAkJwxLbHADUAQAXAAkJwxLbHADUAQAaAAYJ3QolcQDXAAAbAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8gAAMjAAcJJBrIDwCnAQAjAAcJJBrIDwCnAQAPAAYJvRLfVgBKAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn81AAIPAAkJXRmNGwBiAgAPAAkJXRmNGwBiAgAAAA==.',
Yo='Yogisa:BAABLgAECn9FAAMBAAkJcxUJHgAVAgABAAkJcxUJHgAVAgAMAAEJAAA7qgAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAIIAAcJ+RjLVAC+AQAIAAcJ+RjLVAC+AQAAAA==.',
Za='Zariganja:BAAALgADCgIJAgAAAA==.Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zendiesel:BAAALgAECgYJBwABLgAECggJMwAVAGsdAA==.Zenogias:BAABLgAECn8fAAIJAAYJWxVzmABDAQAJAAYJWxVzmABDAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zote:BAAALgADCgkJDwAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn9AAAIkAAkJcyFKBgAfAwAkAAkJcyFKBgAfAwAAAA==.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAMJBQAFAOEOAA==.',
['ßú']='ßúg:BAABLgAFFH8FAAMFAAMJ4Q7dXADWAAAFAAMJ1gzdXADWAAAlAAEJOxd5LABSAAAAAA==.',
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
