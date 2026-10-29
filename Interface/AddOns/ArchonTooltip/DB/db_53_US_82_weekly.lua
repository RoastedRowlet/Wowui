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

local lookup = {'Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Evoker-Augmentation','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Druid-Guardian','Druid-Feral','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Warrior-Fury','DemonHunter-Havoc','Rogue-Outlaw','Priest-Discipline','Paladin-Protection','Warrior-Protection','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acanthel:BAAANQADCgMJAgAAAA==.',
Ad='Adhira:BAAANQADCgcIEgAAAA==.',
Ae='Aegennai:BAABNQAECn8nAAIBAAgKUAW0FwAVAQABAAgKUAW0FwAVAQAAAA==.Aegondk:BAABNQAFFH8GAAICAAMK0xlqDgD0AAACAAMK0xlqDgD0AAAAAA==.Aelias:BAAANQAECgUICAAAAA==.Aevaela:BAABNQAECn8wAAIDAAkKjhveEABxAgADAAkKjhveEABxAgAAAA==.',
Ag='Agilaz:BAABNQAECn8rAAMEAAoKWRMQMgC9AQAEAAgKwRIQMgC9AQAFAAUKBhQzwACxAAAAAA==.',
Ak='Akey:BAAANQAECggIGwAAAQ==.Akhae:BAABNQAECn8qAAMGAAkKaxRkYwDjAQAGAAkKaxRkYwDjAQAHAAEKtwHeUQElAAAAAA==.',
Al='Albinism:BAAANQAECgUIDQAAAA==.Alcadeias:BAAANQAECgQIBAAAAA==.Alethiah:BAAANQAECgIIAgAAAA==.Allastor:BAAANQADCgQIBgAAAA==.',
Am='Amarrah:BAAANQAECgEIAQAAAA==.Amuria:BAAANQAECgQICgAAAA==.',
An='Anaeda:BAABNQAECn8cAAIIAAgKrwxtvACkAQAIAAgKrwxtvACkAQAAAA==.Anastrianna:BAAANQADCgcICgAAAA==.Andrömëdä:BAAANQAECgIIAQABNQAECgQIDQAJAAAAAA==.Angryjim:BAAANQADCgUJBQAAAA==.Anubisre:BAAANQAECgEIBAAAAA==.Anzulay:BAAANQADCgMIAwAAAA==.',
Aq='Aquindra:BAAANQADCgYIEQAAAA==.',
Ar='Aralleda:BAAANQABCgIIAgAAAA==.Arccane:BAABNQAECn8XAAIKAAcKZBWK2ADWAQAKAAcKZBWK2ADWAQAAAA==.Arthar:BAABNQAECn9DAAILAAoKbx/1OQDeAgALAAoKbx/1OQDeAgAAAA==.',
As='Ashvyth:BAABNQAECn8mAAMMAAkK/x0SBQDZAQAMAAgKrB8SBQDZAQANAAEKKAUXNAAmAAAAAA==.',
Av='Avious:BAAANQAECgYIBwAAAA==.',
Aw='Awwyeah:BAAANQADCgIIAgABNQAECgkJHgAOAOUbAA==.',
Az='Azuredeath:BAAANQABCgQIBAAAAA==.Azurehope:BAAANQABCgUIBQAAAA==.Azurelive:BAAANQAECgEIAQAAAA==.',
Ba='Babalou:BAAANQADCgcIAwAAAA==.Baconpancake:BAAANQAECgQIDQAAAA==.Baldpunch:BAAANQAECgEIAQAAAA==.Balinor:BAAANQAECgQIDAAAAA==.Ballz:BAAANQAECgEIAQAAAA==.Balom:BAAANQAECgYIEAAAAA==.Balomdruid:BAAANQADCgUIBQABNQAECgYIEAAJAAAAAA==.Barnabus:BAAANQAECgIIBwAAAA==.',
Be='Beachbecrazy:BAABNQAECn8ZAAIPAAgKthNZWgCmAQAPAAgKthNZWgCmAQAAAA==.Beaj:BAAANQAECgQIEQAAAA==.Beastlypläyä:BAAANQADCgIJAgAAAA==.Bessarion:BAAANQADCgcICQAAAA==.',
Bi='Bigandbeefy:BAABNQAECn8nAAMQAAgKICDuFQC1AgAQAAgKICDuFQC1AgARAAIKkA7sYwBwAAAAAA==.Bigblingaxe:BAAANQADCggICgAAAA==.Bilac:BAAANQADCgEIAQABNQAECgoKMgASALwQAA==.',
Bl='Blacksabbth:BAAANQABCgIIAgAAAA==.Blusoleil:BAAANQAECgYIEAAAAA==.',
Bo='Bonerblast:BAAANQADCggICgAAAA==.Boston:BAABNQAECn8uAAQCAAkK+RymMgAVAgACAAkKSRqmMgAVAgAPAAUKFhykXQCZAQATAAMKsRAInQCgAAAAAA==.',
Br='Branches:BAABNQAECn8xAAMUAAgKKg1uNwBhAQAUAAcKpw1uNwBhAQAVAAgKBw9yKgA2AQAAAA==.Branden:BAAANQADCgcIBwABNQAECgEIAgAJAAAAAA==.Breadglaive:BAAANQAECggICAAAAA==.Brewtholomew:BAABNQAECn8VAAIFAAgKKQc8xwBzAQAFAAgKKQc8xwBzAQAAAA==.Briggsey:BAABNQAECn8mAAIWAAgKvwnragApAQAWAAgKvwnragApAQAAAA==.Briznot:BAABNQAECn8VAAMXAAkKiBKBDQCyAAAWAAYKxRHAegACAQAXAAMKjBOBDQCyAAAAAA==.Bruh:BAAANQAECgQIBAAAAA==.Brunna:BAAANQADCgQIBgAAAA==.Bryce:BAAANQAECgEIAgAAAA==.Brèanna:BAAANQADCggIFQAAAA==.',
Bu='Bubbadubya:BAAANQADCggIJAAAAA==.Bump:BAAANQABCgUIBQAAAA==.Bunnyfu:BAAANQAECgUIBwABNQAECgoKMgASALwQAA==.Burningwolf:BAABNQAECn8fAAIGAAkKfB8sEgC8AgAGAAkKfB8sEgC8AgAAAA==.',
['Bó']='Bórs:BAABNQAECn8UAAIYAAUKixczlgBeAQAYAAUKixczlgBeAQAAAA==.',
Ca='Caiden:BAAANQAECgQIBgAAAA==.Caitlyn:BAAANQADCgEIAQAAAA==.Caleesia:BAAANQAECgEIAQAAAA==.Calesona:BAAANQAECgQIDQAAAA==.Carnìfex:BAAANQAECgUICgAAAA==.Caskaerta:BAAANQAECgEIAQAAAA==.Catbrin:BAABNQAECn8ZAAQZAAkK7xvoDQDQAQAZAAgKwxroDQDQAQAaAAMKPR7dLACrAAAVAAEKrRA2sgAyAAAAAA==.',
Ce='Cerà:BAABNQAECn8cAAIUAAcKURQeGACxAQAUAAcKURQeGACxAQAAAA==.',
Ch='Chapslop:BAAANQADCgcIDAAAAA==.Cheetah:BAAANQADCgYIDQAAAA==.',
Cl='Cleetus:BAAANQAECgUIBQAAAA==.Clizee:BAABNQAECn8XAAIKAAgKUgcwmQASAQAKAAgKUgcwmQASAQAAAA==.Clobberben:BAAANQADCgQIBAAAAA==.Cloudbreaker:BAABNQAECn8YAAMVAAgKRhEJTwCjAQAVAAcKRhEJTwCjAQAZAAQKfg9XQAC5AAAAAA==.Cloudkeg:BAAANQAECgEIAgAAAA==.',
Co='Cobramage:BAAANQAECgQICgAAAA==.Coldtex:BAAANQAECggIAwAAAA==.Constellate:BAABNQAECn8VAAIYAAcKCBHYfQCgAQAYAAcKCBHYfQCgAQAAAA==.Cotterpins:BAABNQAECn8aAAIIAAkKzxK5TgDKAQAIAAkKzxK5TgDKAQAAAA==.Couldbeworse:BAAANQADCgMIAwAAAA==.',
Cr='Cruicible:BAAANQADCgcIDAAAAA==.Crunchyjim:BAAANQAECgMIBAAAAA==.',
Cy='Cybrkatz:BAAANQADCgIIAgAAAA==.Cyndlia:BAAANQADCgIIAgAAAA==.',
Cz='Cztalone:BAAANQADCgQIBAAAAA==.',
['Cè']='Cèlane:BAABNQAECn83AAMHAAoKFhf+MQCyAgAHAAoKFhf+MQCyAgAGAAQK1wuVqQBmAAAAAA==.',
Da='Damitsu:BAEANQADCggIHQABNQAECgYIGgADAPEQAA==.Damnitsu:BAEBNQAECn8aAAMDAAYK8RBxKACBAQADAAYK8A9xKACBAQAbAAUKBgtBZwAVAQAAAA==.Darckside:BAAANQAECgMIBQAAAA==.Dazen:BAAANQADCggIFQAAAA==.',
De='Deadflexy:BAABNQAECn8YAAITAAkKoBjOGgC+AQATAAkKoBjOGgC+AQAAAA==.Deathberry:BAABNQAECn8jAAIWAAgKPRuXUABjAgAWAAgKPRuXUABjAgAAAA==.Deathdoodles:BAABNQAECn8VAAMPAAcKxA5FNgDnAAAPAAcKog5FNgDnAAACAAIKswkolwBmAAABNQAECgkJNwAQAFQYAA==.Deathsveil:BAAANQADCgcIBwAAAA==.Deathvoker:BAAANQADCgYICwAAAA==.Deekan:BAAANQAECgcIDgAAAA==.Dejavù:BAAANQAFFAIIAgAAAA==.Demonblood:BAABNQAECn8gAAMTAAoKdRE6TgC9AQATAAkKsBI6TgC9AQAPAAEK2ghzbQA1AAAAAA==.Demonicmac:BAAANQADCgMIAwABNQAECgQICgAJAAAAAA==.Deräth:BAABNQAECn8ZAAIRAAcKiwdFOwBPAQARAAcKiwdFOwBPAQAAAA==.Devlik:BAAANQAECgMIAgAAAA==.Dew:BAAANQADCgYIBgABNQADCgYICgAJAAAAAA==.Dezlover:BAAANQADCgQIBAAAAA==.',
Dh='Dhdawg:BAAANQAECgIIAgAAAA==.',
Di='Dimensius:BAAANQAECgQIBQAAAA==.Dinkalopogis:BAAANQADCgYIEAAAAA==.Dionne:BAAANQAECgYICAAAAA==.Dippindots:BAAANQAECgEIAQABNQAECgoKMAAKAO0bAA==.Ditsie:BAAANQAECgEIAQAAAA==.',
Dm='Dmega:BAABNQAECn8fAAIFAAgKFwvebABeAQAFAAgKFwvebABeAQAAAA==.',
Do='Dodgeramthis:BAAANQADCgEIAQAAAA==.Dogfunk:BAAANQABCgcICgAAAA==.Dorne:BAAANQADCgIIAgAAAA==.',
Dr='Dragea:BAAANQAECgYIDwAAAA==.Dragondude:BAABNQAECn8fAAQcAAgKZB08FABrAgAcAAgKZB08FABrAgAdAAUKNgjlEADEAAASAAIKhQsXEQBoAAAAAA==.Dragonsgrasp:BAAANQADCgUIBAAAAA==.Drakoswrath:BAACNQAFFH8RAAITAAYKdRO5DQB4AQATAAYKdRO5DQB4AQA1AAQKfzEAAhMACgp5JNkHANUCABMACgp5JNkHANUCAAAA.Drizzít:BAAANQAECgUIBQAAAA==.',
Du='Durango:BAABNQAECn8XAAILAAgKExqRPQDaAQALAAgKExqRPQDaAQAAAA==.',
Dy='Dyelin:BAABNQAECn8lAAIWAAkKURnDKAAQAgAWAAkKURnDKAAQAgAAAA==.',
Ek='Ekocteid:BAAANQABCgIIAgAAAA==.',
El='Elylle:BAAANQAECgIIAgAAAA==.Elyron:BAABNQAECn8nAAIKAAkKABViTQDHAQAKAAkKABViTQDHAQAAAA==.',
En='Endofall:BAAANQAECgEIAgAAAA==.',
Ep='Epiczimbabue:BAAANQADCgEIAQAAAA==.',
Es='Esrahaddon:BAABNQAECn84AAMKAAoKIh7SHQCFAgAKAAoKKh3SHQCFAgAOAAcKOR09CwAQAgAAAA==.Estella:BAAANQADCgYIDgAAAA==.',
Et='Et:BAAANQAECgEIAQAAAA==.Etheri:BAAANQAECgUICwAAAA==.',
Eu='Euandros:BAAANQAECggIEAAAAA==.',
Ez='Ezhra:BAAANQABCgEIAQABNQAECgEIAQAJAAAAAA==.Ezind:BAAANQAECgUIEQAAAA==.',
Fa='Fakename:BAAANQAECgcIDwAAAA==.Fakesaint:BAABNQAECn8yAAIGAAoKTiR/FQAjAwAGAAoKTiR/FQAjAwAAAA==.Fangstorm:BAABNQAECn8lAAIaAAgKpw+6DQBSAQAaAAgKpw+6DQBSAQAAAA==.Farorê:BAAANQADCgYJDAAAAA==.Fazz:BAAANQAECgUIDAAAAA==.',
Fe='Feldruid:BAAANQAECgQIDQAAAA==.Felup:BAABNQAECn86AAQWAAkKnyEuHwAHAwAWAAkKnyEuHwAHAwAXAAIK+xEqVgB8AAAeAAEK5BvQKgBCAAAAAA==.',
Fl='Flåsh:BAAANQAECgEIAQAAAA==.',
Fo='Folstagg:BAAANQADCgcIDAAAAA==.Foreverem:BAABNQAECn8vAAMYAAoKZxmzEQDAAgAYAAoKZxmzEQDAAgAIAAEKDAJayQEjAAAAAA==.',
Fr='Frostynewf:BAAANQADCgYIBgAAAA==.',
Fu='Fujitora:BAABNQAECn8tAAIfAAkKRw80CgBjAQAfAAkKRw80CgBjAQAAAA==.Fusepins:BAAANQADCgcIAwAAAA==.Fuzzwig:BAAANQADCgcIDQAAAA==.',
Ga='Gaska:BAAANQAECgYICwABNQAECgUIDAAJAAAAAA==.',
Ge='Geralan:BAAANQAECgEIAQAAAA==.',
Gh='Ghösty:BAAANQADCgMIAwABNQAECggIAwAJAAAAAA==.',
Gi='Gideòn:BAAANQADCgQJBAAAAA==.',
Gl='Glenys:BAAANQADCgEIAQAAAA==.',
Go='Gopao:BAAANQADCgcIBQABNQAECgkJFwARAGcaAA==.',
Gr='Gracela:BAAANQADCgEIAQAAAA==.Graxus:BAAANQAECgUICwAAAA==.Greth:BAAANQADCggIJQAAAA==.Grimlin:BAAANQAECgEJAQAAAA==.Grumpy:BAAANQADCgcIAwABNQAECgkJGAATAKAYAA==.',
Gu='Gudge:BAABNQAECn8yAAMSAAoKvBAyCAAYAgASAAoKvBAyCAAYAgAcAAMK7gHvLgAvAAAAAA==.Gummypenguin:BAABNQAECn8mAAIFAAoK4SIzCQAMAwAFAAoK4SIzCQAMAwABNQAFFAUIFwAFAGckAA==.',
Ha='Hadhox:BAAANQAECgMIBgABNQAECgoKMAAFAMQPAA==.Halforcked:BAAANQADCgUIBQAAAA==.Hathdox:BAABNQAECn8wAAIFAAoKxA+eNgAFAgAFAAoKxA+eNgAFAgAAAA==.Hawkulees:BAAANQADCggIHgAAAA==.Hazelnoot:BAABNQAECn87AAMIAAoKMSQGEACKAwAIAAoKMSQGEACKAwAYAAMKUgpEmQCKAAAAAA==.',
He='Healzofdeath:BAAANQADCgcJEAAAAA==.Hegaphie:BAAANQAECgYIDAAAAA==.Hercluvscake:BAAANQADCgcICwAAAA==.Hexcist:BAABNQAECn8gAAIgAAgKqQxZMQAcAQAgAAgKqQxZMQAcAQAAAA==.',
Hi='Hitsuryu:BAABNQAECn8XAAISAAYK7wJKGAC0AAASAAYK7wJKGAC0AAAAAA==.',
Ho='Hochma:BAAANQADCgEIAQAAAA==.Hokogo:BAAANQADCgEIAQAAAA==.Holdon:BAABNQAECn8fAAMbAAoKYQyyPgDTAQAbAAkKYQyyPgDTAQAhAAYK3gTmEQDtAAAAAA==.Holehbones:BAAANQADCgYIBgAAAA==.Hollyanne:BAAANQAECgMJBQAAAA==.Holylion:BAAANQAECgEIAQAAAA==.Hoonicorn:BAAANQADCgEIAQABNQADCgIJAgAJAAAAAA==.Hornsharp:BAAANQAECgUICAAAAA==.',
Hu='Hunalli:BAAANQADCgUIBwABNQAECgoKMgASALwQAA==.Hunilla:BAABNQAECn8XAAQRAAYKLgxRPABIAQARAAYKLgxRPABIAQAQAAUK+gZxvADkAAAiAAEK6gGeFAAgAAABNQAECgoKMgASALwQAA==.',
Ia='Iamu:BAAANQADCgYIGQAAAA==.',
Ib='Ibris:BAAANQADCggIFQAAAA==.',
Ic='Iconius:BAAANQADCggIFQAAAA==.',
Ie='Ieatwetsocks:BAACNQAFFH8GAAIGAAMKBQpZEgC8AAAGAAMKBQpZEgC8AAA1AAQKfyMAAwYACgo4FctXAAoCAAYACgo4FctXAAoCAAcAAgpbBO0hAU0AAAAA.',
Ig='Ignivar:BAAANQADCggIFgAAAA==.',
In='Indra:BAAANQAECgYIDAAAAA==.Innexshaman:BAABNQAECn8iAAIHAAkKKBrOQwBnAgAHAAkKKBrOQwBnAgAAAA==.Insaint:BAACNQAFFH8HAAIIAAMKhgc6HADGAAAIAAMKhgc6HADGAAA1AAQKfzUAAggACgpHFl9KANgBAAgACgpHFl9KANgBAAAA.',
Ir='Ironfield:BAABNQAECn8YAAMGAAgKYxoJWQAGAgAGAAgKYxoJWQAGAgAHAAMKFQNFCgF3AAABNQADCgUIBQAJAAAAAA==.Ironsanta:BAAANQADCgIJAgAAAA==.Irony:BAAANQAECgMIAwAAAA==.Irtank:BAAANQADCgEIAQAAAA==.',
Is='Isabellë:BAABNQAECn8ZAAIRAAYKIwbuSwDmAAARAAYKIwbuSwDmAAAAAA==.',
Je='Jessamine:BAABNQAECn89AAIKAAoKSxSZOQAMAgAKAAoKSxSZOQAMAgAAAA==.Jetta:BAAANQAECgUIDQAAAA==.Jezzak:BAABNQAECn8mAAIFAAkK/hAOdwAhAgAFAAkK/hAOdwAhAgABNQAECgoKKAAFAMwWAA==.',
Jo='John:BAABNQAECn9OAAIhAAoKMSOVAAC3AwAhAAoKMSOVAAC3AwAAAA==.Jorien:BAABNQAECn8wAAIFAAoKuxnfQwCfAgAFAAoKuxnfQwCfAgAAAA==.',
Jp='Jp:BAAANQAECgUIDAAAAA==.Jpb:BAAANQAECgIIAQABNQAECgUIDAAJAAAAAA==.Jpd:BAAANQAECgQIBAABNQAECgUIDAAJAAAAAA==.Jps:BAAANQAECgIIAgABNQAECgUIDAAJAAAAAA==.',
Ju='Justadwarf:BAAANQAECgYICgAAAA==.Justatsuj:BAAANQAECgQIBQAAAA==.Juston:BAABNQAECn8cAAMHAAoKGg+QJQDWAQAHAAkKGg+QJQDWAQAGAAYKRAacywDQAAAAAA==.',
Ka='Kaboonsky:BAABNQAECn8ZAAMQAAkKHRp8NgDfAQAQAAkKHRp8NgDfAQARAAYKMg8OOQBdAQAAAA==.Kaeamani:BAAANQADCgYIBwAAAA==.Kaenaya:BAAANQADCgIIAgAAAA==.Kamikori:BAABNQAECn8XAAIfAAYK1BazEQCJAQAfAAYK1BazEQCJAQAAAA==.Kardell:BAAANQADCgYIDAAAAA==.Kardels:BAAANQADCgQIBAABNQADCgYIDAAJAAAAAA==.Karnadaz:BAABNQAECn8hAAILAAkKRhoNYwBlAgALAAkKRhoNYwBlAgAAAA==.Karnkarn:BAAANQAECgYIDwAAAA==.Karnn:BAAANQADCggIDgAAAA==.Katalight:BAAANQADCgEIAQABNQAECgUIDgAJAAAAAA==.',
Ke='Keho:BAAANQAFFAEIAQAAAA==.',
Ki='Kiascendance:BAABNQAECn8XAAIGAAcKRCPWMwCQAgAGAAcKRCPWMwCQAgAAAA==.',
Ko='Kolosho:BAAANQAECgYIBgAAAA==.Korxana:BAABNQAECn8iAAIjAAgKlw8LGgAuAQAjAAgKlw8LGgAuAQAAAA==.Korxon:BAABNQAECn80AAIQAAoK9hiyNgCNAgAQAAoK9hiyNgCNAgAAAA==.Kotus:BAABNQAECn8VAAMkAAkKQw+wHwBTAQAkAAYKfxWwHwBTAQALAAkKNgbnbQA+AQAAAA==.',
Ks='Ksyusha:BAABNQAECn8YAAIIAAgK1wYtqQAEAQAIAAgK1wYtqQAEAQAAAA==.',
Ky='Kyfess:BAAANQAECgYIDAAAAA==.',
['Kä']='Kämi:BAAANQAECgEIAQABNQAECgUIDwAJAAAAAA==.',
La='Ladgertha:BAAANQADCgYIBgAAAA==.Lambent:BAAANQADCgQIBAAAAA==.Landon:BAAANQAECgEIAQAAAA==.Lanuadra:BAABNQAECn8nAAIDAAkKpheaDwCCAgADAAkKpheaDwCCAgAAAA==.Lawry:BAAANQAECgYIEAAAAA==.Layhee:BAABNQAFFH8FAAIgAAQKAgLhDACQAAAgAAQKAgLhDACQAAAAAA==.',
Le='Leasidhe:BAAANQADCgcIDgABNQADCgQIBAAJAAAAAA==.Lethalbimbo:BAAANQADCggIHwAAAA==.',
Lg='Lghtninstorm:BAAANQADCgIIAgAAAA==.',
Li='Liesel:BAAANQADCggICAAAAA==.Likhan:BAAANQAECgEIAQAAAA==.Lillié:BAAANQABCgIIAQAAAA==.Lilysham:BAACNQAFFH8VAAIGAAYKEhn9CQCvAQAGAAYKEhn9CQCvAQA1AAQKfz4AAwYACgopIQMsALICAAYACgopIQMsALICAAcACgrVFgodABMCAAAA.Lindar:BAAANQABCgMIBAAAAA==.Linddrel:BAAANQAECgYICQAAAA==.',
Lo='Lomea:BAAANQADCgYICQABNQAECgIIAgAJAAAAAA==.Lonarius:BAAANQABCgQIBwAAAA==.',
Lu='Lunasblood:BAAANQADCgYIBgAAAA==.',
['Lá']='Ládylumps:BAAANQADCgcIBwABNQAECggIGQAPALYTAA==.',
['Lø']='Løllîe:BAAANQAECgcIEgAAAA==.',
Ma='Macarius:BAABNQAECn8dAAINAAkKlBryBgCBAgANAAkKlBryBgCBAgAAAA==.Macdee:BAAANQADCgMIAwABNQAECgQICgAJAAAAAA==.Magatai:BAAANQAECgYICQAAAA==.Mageless:BAAANQADCgIIAgAAAA==.Magicjim:BAAANQADCgIJAgAAAA==.Magpie:BAAANQADCgYIDAAAAA==.Maimed:BAAANQAECgIIAwAAAA==.Malotan:BAAANQABCgEIAQABNQABCggICAAJAAAAAA==.Manaster:BAAANQAECgQIEQAAAA==.Manpriest:BAAANQADCgEIAQAAAA==.Maravanna:BAAANQADCgEIAQAAAA==.Martlok:BAAANQAECgUICwAAAA==.Mathas:BAAANQAECgEIAwAAAA==.Mathius:BAAANQAECgEIAgAAAA==.Maynis:BAAANQABCgQIBgAAAA==.Maysaveyou:BAAANQAECgQIBAAAAA==.',
Mc='Mcbrynhammer:BAAANQAECgEIAwAAAA==.',
Me='Meanwhile:BAAANQADCgcIBQAAAA==.Meowmixx:BAAANQAECgEIAQAAAA==.Merkii:BAAANQADCgYIBgABNQAECgoKJAAbADkaAA==.',
Mi='Micflinigan:BAABNQAECn8lAAMfAAgKGxbICgAaAgAfAAgKGxbICgAaAgALAAMKJg8vGgGoAAAAAA==.Midnightmare:BAAANQAECgEIAQAAAA==.Milkymoomoo:BAAANQADCgQICAAAAA==.Minarii:BAAANQAECgUIDwAAAA==.Ming:BAAANQADCgQIBAABNQAECgoKMwANAHUgAA==.Minilove:BAAANQADCgUICgAAAA==.Mirix:BAAANQAECgMIAwAAAA==.Misha:BAAANQAECgEIAQAAAA==.Mishelö:BAAANQAECgUIDQAAAA==.Misla:BAAANQAECgEIAQAAAA==.Missfiré:BAAANQADCggIDAAAAA==.',
Mo='Mochimochi:BAAANQADCgQIBAAAAA==.Mommieuppies:BAAANQADCgcJCAAAAA==.Momomochi:BAAANQAECgUICAAAAA==.Moonshae:BAABNQAECn80AAMNAAoKcBN1DQCzAQANAAoKcBN1DQCzAQAlAAcK6hP8OABMAQAAAA==.Moothrnature:BAAANQABCgQIBAAAAA==.Mortalbion:BAAANQAECgMIBAAAAA==.',
Mu='Murciélago:BAAANQAECgQIBQAAAA==.Mustevistust:BAAANQADCgQIBAABNQAECgUICwAJAAAAAA==.',
My='Mystiquè:BAAANQADCgcIHwAAAA==.',
['Mö']='Mö:BAAANQAECgEIAQAAAA==.',
Na='Nahmbra:BAAANQAECgUICgAAAA==.Naithin:BAAANQAECgEIAQAAAA==.Nalarah:BAAANQAECgMIAwAAAA==.Nastybeef:BAAANQAECgEIAQAAAA==.Naviriel:BAAANQAECgYIBgABNQAECggIEgAJAAAAAA==.',
Ne='Nerrf:BAAANQAECgEIAQAAAA==.',
Ni='Nightray:BAAANQAECgQICgABNQAECgoKQwALAG8fAA==.',
No='Nofoxgìven:BAAANQAECgIIAwAAAA==.Noknik:BAAANQABCggICAAAAA==.Nonsocial:BAACNQAFFH8JAAIjAAcKGg2EAwDIAQAjAAcKGg2EAwDIAQA1AAQKfxgAAiMACQoTJFcEAHMDACMACQoTJFcEAHMDAAAA.Norgaladwen:BAAANQADCggICgABNQAECgoKHwAUALkiAA==.Noriisa:BAABNQAECn8oAAIFAAoKzBaxXABfAgAFAAoKzBaxXABfAgAAAA==.Notamathguy:BAAANQAECgEIAgAAAA==.Noudders:BAABNQAECn8nAAIGAAkKZB5/DQDxAgAGAAkKZB5/DQDxAgAAAA==.',
Ny='Nyvak:BAAANQAECgYIDAAAAA==.',
Od='Odinhand:BAABNQAECn85AAIVAAkKfQyXHgCUAQAVAAkKfQyXHgCUAQAAAA==.',
Oh='Ohgreatdink:BAAANQADCgYICwAAAA==.',
Ol='Oliissa:BAAANQADCggIJAAAAA==.',
Oz='Ozwäld:BAABNQAECn8WAAIKAAcK5Q8/AAGNAQAKAAcK5Q8/AAGNAQABNQAECgoKOQABAK4gAA==.Ozwäldo:BAABNQAECn85AAIBAAoKriCQBgAcAwABAAoKriCQBgAcAwAAAA==.',
Pa='Pandapí:BAAANQADCgYIBgAAAA==.Panduh:BAABNQAECn8wAAMKAAoK7Rs6IAB5AgAKAAoK7Rs6IAB5AgAOAAIKVRLiMgBvAAAAAA==.Pandóra:BAAANQAECgIIAwAAAA==.Pariousa:BAABNQAECn8oAAMbAAoKaCPTDQAVAwAbAAoKzyLTDQAVAwADAAQKBB0qRwBCAQAAAA==.',
Pe='Peppermintxo:BAAANQAECgUIBQABNQADCgIJAgAJAAAAAA==.Peärl:BAAANQABCgIIAgAAAA==.',
Ph='Phaite:BAAANQAECggJAQAAAA==.Phalock:BAAANQAECgIIAwAAAA==.Phylinx:BAAANQADCgIIAgAAAA==.',
Pi='Pinkeepink:BAAANQAECgYIDwAAAA==.',
Po='Popacooldown:BAAANQAECgEIAQAAAA==.Potangwang:BAAANQAECgIIBQAAAA==.',
Pr='Pres:BAAANQAECgIIAwAAAA==.Prild:BAAANQAECgEIBAAAAA==.',
Pu='Puhk:BAAANQADCgcICQAAAA==.Pumpernickle:BAAANQAECgQIBAAAAA==.',
Ra='Rahzon:BAABNQAECn8VAAIFAAcKVwtUgwAsAQAFAAcKVwtUgwAsAQAAAA==.Raijù:BAAANQAECgEIAgAAAA==.Ralganor:BAABNQAECn89AAITAAoKqiE7BwDiAgATAAoKqiE7BwDiAgAAAA==.Ralzin:BAAANQADCgUIDQAAAA==.Ramanash:BAAANQADCgQICAAAAA==.Randron:BAAANQAECggIDQAAAA==.Ravilan:BAAANQAECgMIBgAAAA==.Raynlight:BAABNQAECn8XAAMRAAgK4hTPPABEAQARAAYK4Q3PPABEAQAQAAcKSAaYcQACAQAAAA==.',
Re='Ren:BAAANQADCgUIBwAAAA==.Retacus:BAAANQAECgEIAQAAAA==.Retaeytoob:BAAANQAFFAEIAQAAAA==.',
Ri='Rina:BAABNQAECn8UAAMmAAgK1BTJJwAGAgAmAAgKbxTJJwAGAgAnAAEKoQlZNAAqAAAAAA==.Rineli:BAAANQADCgcICgABNQAECgUIDwAJAAAAAA==.Ringadingg:BAABNQAECn8pAAMPAAoKrx+QBwC0AgAPAAoKrx+QBwC0AgACAAEKSCDfmgBdAAAAAA==.',
Ro='Rosequartz:BAAANQAECgQIBAAAAA==.',
Ry='Rydia:BAAANQAECgYIEAAAAA==.',
Sa='Saladin:BAAANQAECgEIBAAAAA==.Sankatlantis:BAAANQADCgYICgAAAA==.Sanurá:BAAANQAECgMIBQAAAA==.Sarka:BAAANQADCgcIBwABNQAECgEIAQAJAAAAAA==.Sasquatch:BAABNQAECn8XAAMGAAkKXQ/6owAsAQAGAAgKfwz6owAsAQABAAUKiwdQHADTAAAAAA==.Satuno:BAAANQAECgEIAQABNQAECggIHwAmAJ8UAA==.Saunkae:BAAANQAECgQICQAAAA==.',
Sc='Scony:BAAANQAECgYIDQAAAA==.Scribs:BAAANQAECgYIDQAAAA==.Scyphen:BAAANQADCgYICQAAAA==.',
Se='Seegon:BAAANQABCgYIBQAAAA==.Seismic:BAAANQAECggIEQAAAA==.Seniko:BAAANQABCgIIAgAAAA==.Senseii:BAAANQADCgMIAQAAAA==.Sephirain:BAAANQADCgMIAwAAAA==.Sevelement:BAABNQAECn8eAAMHAAkK3RtTfQCsAQAHAAYKZhpTfQCsAQAGAAYK5wlUmACNAAABNQAECgkJKAAnAJkYAA==.Severalforms:BAABNQAECn8hAAMZAAkKnh72BgB7AgAZAAkKcx72BgB7AgAaAAIK0hdVMACPAAABNQAECgkJKAAnAJkYAA==.Severànce:BAABNQAECn8oAAQnAAkKmRgDDgDcAQAnAAgK8RUDDgDcAQAgAAUK1BRmTwBcAQAmAAQKvBGVTwDiAAAAAA==.Sevivify:BAAANQADCgIIAwABNQAECgkJKAAnAJkYAA==.',
Sh='Shablammy:BAABNQAECn8ZAAMGAAcKJyGrLAD0AQAGAAcKJyGrLAD0AQAHAAEKAADTIQFOAAAAAA==.Shadowginni:BAAANQAECgIIAwAAAA==.Shadownome:BAAANQADCggIFQAAAA==.Shadowolves:BAAANQAECgEIAgAAAA==.Shadowson:BAAANQAECgEIAQAAAA==.Shammygand:BAAANQAECgEIAQABNQAECgoKIgAdAMwaAA==.Shanker:BAAANQADCgMIAwAAAA==.Sheephappéns:BAAANQAECggIDAABNQAECgkJKAAnAJkYAA==.Shefu:BAAANQAECgMIBQAAAA==.Shfifty:BAABNQAECn83AAMQAAkKVBh+MACmAgAQAAkKVBh+MACmAgARAAIKGQOXSgAvAAAAAA==.Shikoba:BAAANQABCgIIAgAAAA==.Shutupbird:BAABNQAECn86AAIZAAoKux1RDQCRAgAZAAoKux1RDQCRAgAAAA==.',
Si='Sihtric:BAAANQADCggICAAAAA==.Silris:BAAANQADCgYIDAAAAA==.',
Sk='Skendr:BAAANQADCgEIAQABNQADCggIFgAJAAAAAA==.Skydragon:BAAANQADCggIHwAAAA==.',
Sl='Slack:BAAANQADCgQIBAAAAA==.Slay:BAAANQAECgEIAQABNQAECgoKMAATALkbAA==.Slayful:BAAANQAECgEIAQAAAA==.Sleepydwarf:BAAANQAECgEIAQAAAA==.Slonk:BAAANQAECgQJBgAAAA==.',
So='Sofia:BAABNQAECn8XAAMRAAkKZxpmDgDwAQARAAkKZxpmDgDwAQAQAAEKrAj++AA7AAAAAA==.',
Sp='Sparrtacus:BAAANQABCgYICgAAAA==.Spiritly:BAAANQAECgMIBQAAAA==.Sploof:BAABNQAECn8fAAIUAAoKuSL5AgCFAwAUAAoKuSL5AgCFAwAAAA==.Sprynt:BAAANQAECgUIDAAAAA==.',
St='Staples:BAAANQADCggIDgABNQAECgkJGgAIAM8SAA==.Starlighter:BAAANQADCgYICQAAAA==.Starmist:BAAANQADCggIIQAAAA==.Stendo:BAAANQAECgUIBQABNQAFFAIICQAgAH8eAA==.Strongbad:BAAANQAECgMIBQAAAA==.Stubly:BAAANQADCgUICQAAAA==.',
Su='Sunfyrie:BAABNQAECn8fAAIQAAcKjhfGQACwAQAQAAcKjhfGQACwAQAAAA==.',
Sw='Sweèt:BAAANQAECgIIBQAAAA==.Swiftyretpal:BAAANQAECggIAwAAAA==.',
Ta='Tagrit:BAAANQADCgUIBQAAAA==.Taldieth:BAAANQAECgQIEQAAAA==.Tannas:BAAANQAECgMIBAAAAA==.Tarouhorn:BAAANQAECgEIAQAAAA==.Taurdk:BAAANQAECgYIDwAAAA==.Taylorshift:BAABNQAECn8rAAIVAAoKpB/7FwAIAwAVAAoKpB/7FwAIAwAAAA==.Tazranir:BAAANQADCggICwAAAA==.',
Te='Teaar:BAAANQADCgUIBQABNQAECgoKMAATALkbAA==.Teetau:BAABNQAECn8lAAIZAAgKEgS/LQCwAAAZAAgKEgS/LQCwAAAAAA==.Texlandar:BAAANQADCgMIAwAAAA==.',
Th='Thadregosa:BAABNQAECn8iAAIdAAgKdhNBCQBmAQAdAAgKdhNBCQBmAQAAAA==.Thalsan:BAAANQABCgIIAgAAAA==.Thander:BAAANQAECgEIAQABNQAECgEIAgAJAAAAAA==.Thedarkskull:BAAANQAECgEIAQAAAA==.Therlisa:BAAANQAECgEIAQAAAA==.Thordar:BAAANQABCggICwAAAA==.',
Ti='Tibbotanical:BAAANQADCgUIBQAAAA==.Tiberius:BAAANQABCgIIAQAAAA==.Tiffy:BAAANQAECgEIAQAAAA==.Timoleon:BAAANQAECgQIBQAAAA==.Tirna:BAAANQAECgUIBwAAAA==.Tirnotham:BAABNQAECn8bAAMlAAgKVw5kHABJAQAlAAgKVw5kHABJAQANAAIK7QIEMAA0AAAAAA==.',
Tm='Tmtglizzy:BAABNQAECn8tAAMGAAkKUR4gEwCzAgAGAAkKUR4gEwCzAgAHAAQK7xX/uAAgAQAAAA==.',
To='Tokalu:BAAANQAECggIEgAAAA==.Tonjudsonson:BAACNQAFFH8OAAIZAAUKBRKZAwAjAQAZAAUKBRKZAwAjAQA1AAQKfzwABBkACgpZIkkDAIYDABkACgpZIkkDAIYDABQABwqZIs0IAMACABoAAQoAAM09AAAAAAAA.Torath:BAAANQADCgYICwABNQAECgEIAgAJAAAAAA==.',
Tr='Trickc:BAAANQAECgMIAwAAAA==.',
Tu='Turdimer:BAAANQADCgYIHgAAAA==.',
Tw='Twiki:BAABNQAECn8iAAIXAAcKiwTTEACVAAAXAAcKiwTTEACVAAAAAA==.Twobricks:BAABNQAECn85AAIUAAkK7hVtEQAPAgAUAAkK7hVtEQAPAgAAAA==.',
Ty='Tyrielas:BAAANQAECgEIAgAAAA==.Tyrssana:BAABNQAECn8ZAAMmAAgKmgvKHQA+AQAmAAgKmgvKHQA+AQAnAAUKggYLFgCJAAABNQAFFAUICAAcAEcKAA==.',
['Tö']='Töketsu:BAAANQADCgYIDAAAAA==.',
Uh='Uhmerica:BAABNQAECn85AAIjAAkKzh/jBQCbAgAjAAkKzh/jBQCbAgABNQABCgYICAAJAAAAAA==.',
Ur='Urdeadtoo:BAABNQAECn8ZAAMYAAYKAyDOTwAsAgAYAAYKAyDOTwAsAgAIAAYKPw6m/wAgAQAAAA==.Urlacher:BAAANQAECgQIBgAAAA==.Urthkwayk:BAAANQADCgYIBgAAAA==.',
Va='Vacay:BAAANQAECggICAAAAA==.Vaedryn:BAAANQADCgUIBQAAAA==.Vaterunser:BAABNQAECn8bAAIIAAgKBgowlQAoAQAIAAgKBgowlQAoAQAAAA==.Vayikra:BAAANQADCgMIAwABNQAECgkJJAAHAH8MAA==.Vazoom:BAAANQAECgIIAwAAAA==.',
Ve='Velskud:BAAANQADCggIIgAAAA==.Verlynna:BAAANQADCgEIAQAAAA==.Vertexx:BAAANQAECgEIAgAAAA==.',
Vi='Vicky:BAAANQADCgQIBAABNQAECgkJFQAXAIgSAA==.Vierth:BAAANQADCgMIAwABNQAECgIIAgAJAAAAAA==.Vinhar:BAAANQADCgUICAAAAA==.Vinsteam:BAAANQAECgEIAQAAAA==.Visea:BAAANQADCgIIAgABNQAECgIIAgAJAAAAAA==.',
Vo='Voidsavage:BAAANQADCggIHwAAAA==.Voidwing:BAAANQAECgQIBAAAAA==.Volic:BAAANQAECggIJwAAAQ==.Vollken:BAAANQADCgYICAAAAA==.Voznje:BAAANQAECgEIBQAAAA==.',
Wa='Warkistla:BAAANQADCggICAABNQAECggIEgAJAAAAAA==.Watevr:BAEANQAECgEIAQABNQAECgYIGgADAPEQAA==.',
We='Weemer:BAAANQADCgcIDQAAAA==.Wesleypipes:BAABNQAECn8cAAIGAAkKMRQUcwCyAQAGAAkKMRQUcwCyAQAAAA==.',
Wh='Whisteria:BAAANQADCgYIBgAAAA==.',
Wi='Wizalf:BAABNQAECn8cAAIKAAgKuxNhZwB6AQAKAAgKuxNhZwB6AQAAAA==.',
Wm='Wmrx:BAAANQADCgYIBgAAAA==.',
Wo='Wodalpally:BAABNQAECn8oAAIYAAoKFBWJNwCGAgAYAAoKFBWJNwCGAgAAAA==.Wolfmato:BAABNQAECn8sAAIGAAoK8R25JwDFAgAGAAoK8R25JwDFAgAAAA==.',
Wy='Wynne:BAAANQAECgEIAQAAAA==.',
Xa='Xalabro:BAABNQAECn8XAAIjAAYKJxQGOAArAQAjAAYKJxQGOAArAQAAAA==.',
Xe='Xeros:BAAANQADCggICAAAAA==.Xerxeis:BAAANQABCgYICAABNQAECgYIBgAJAAAAAA==.',
Xo='Xousa:BAAANQADCgQIBgABNQAECgoKKAAbAGgjAA==.',
Yh='Yhorn:BAAANQADCgcIBwABNQAFFAYIFQAGABIZAA==.',
Ys='Yssuplef:BAABNQAECn8bAAQXAAkKDQzwDAC3AAAWAAcKqgo2cQAZAQAXAAcKCwrwDAC3AAAeAAMKqgh+HACbAAAAAA==.',
Yu='Yuefei:BAAANQADCgYICgAAAA==.Yunjin:BAAANQADCgMIAwAAAA==.',
Za='Zaiyra:BAAANQAECgUIBgAAAA==.Zakoor:BAAANQADCgcIGwAAAA==.Zambreth:BAAANQADCgUICAAAAA==.Zareena:BAAANQADCgcIHQAAAA==.Zarnia:BAAANQADCgMIAwAAAA==.Zarrock:BAAANQADCgIJAgAAAA==.Zaurra:BAAANQAECgIIAgAAAA==.Zavatan:BAAANQADCgQIBwAAAA==.',
Ze='Zebbyzebzeb:BAAANQADCgcIIAAAAA==.Zekia:BAABNQAECn8sAAIFAAgKGxocVwBtAgAFAAgKGxocVwBtAgAAAA==.Zepirra:BAAANQABCgcIDgAAAA==.Zergdemon:BAAANQAECgEIAQAAAA==.Zergul:BAAANQAECgEIAQAAAA==.Zerm:BAABNQAECn8xAAIIAAkKmxfqRADqAQAIAAkKmxfqRADqAQAAAA==.Zermonk:BAAANQAECgEIAgAAAA==.Zerodeath:BAAANQADCgYJBgAAAA==.',
Zi='Zinnkura:BAABNQAECn8WAAIGAAgKYQstXAAqAQAGAAgKYQstXAAqAQAAAA==.',
Zo='Zorsa:BAAANQAECgYIDwAAAA==.',
Zu='Zuljawn:BAABNQAECn8lAAIEAAgKYw0QGgA0AQAEAAgKYw0QGgA0AQAAAA==.',
Zy='Zyphos:BAAANQADCgIIAgAAAA==.',
['Ñô']='Ñôg:BAAANQADCggICQAAAA==.',
['Ød']='Ødis:BAAANQADCggIKAAAAA==.',
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
