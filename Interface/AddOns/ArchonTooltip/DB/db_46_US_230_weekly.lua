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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Elemental','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','DeathKnight-Blood','Monk-Windwalker','Druid-Balance','Druid-Guardian','Druid-Feral','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abaddon:BAABLgAECn8qAAMBAAgJ/B3LBQAWAgABAAgJQRzLBQAWAgACAAcJbRsoXACSAQAAAA==.Abessedge:BAAALgAECgEJAQAAAA==.',
Ac='Acidtears:BAAALgAECgEJAQAAAA==.Ackris:BAABLgAECn8uAAIDAAkJ/BwHCgAuAwADAAkJ/BwHCgAuAwAAAA==.Ackrisa:BAAALgAECgUJCAAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJLgADAPwcAA==.',
Ae='Aedimus:BAAALgADCgcJCQAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alistan:BAAALgAECgEJAQAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgIJAwABLgAECggJKQAFACcQAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMGAAgJDhVcSACNAQAGAAgJDhVcSACNAQAHAAEJawwQWQAxAAABLgAFFAcJGAAIAD0TAA==.Amalthaea:BAAALgAECgUJBwABLgAECgkJLgAJAGMWAA==.Amnoon:BAABLgAECn8uAAIKAAkJjhdEEgBfAgAKAAkJjhdEEgBfAgAAAA==.Amri:BAACLgAFFH8RAAMLAAQJCw6FJgAGAQALAAQJCw6FJgAGAQAMAAEJYAJFJgA5AAAuAAQKfxsAAwsACAlxFqAVAC0CAAsACAlxFqAVAC0CAAwAAwkMBco8AIQAAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.Angelfox:BAAALgAECgIJAQAAAA==.',
Aq='Aquas:BAAALgAECgQJBwAAAA==.',
Ar='Ardrhys:BAAALgAECgYJDQAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECggJCQABLgAFFAUJEAAHAOUVAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECgQJCAAAAA==.',
At='Atreus:BAABLgAECn8lAAIHAAkJ7BxxCgBSAgAHAAkJ7BxxCgBSAgAAAA==.Atzalan:BAABLgAECn8UAAINAAYJpwnpcwD7AAANAAYJpwnpcwD7AAAAAA==.',
Au='Autism:BAEALgAECgcJBwABLgAFFAMJBQACAIEjAA==.Automagic:BAAALgAECgEJAgAAAA==.',
Av='Avondwella:BAABLgAECn8rAAMOAAkJZw/YFwBcAQAOAAkJZw/YFwBcAQAPAAEJ+wnERAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baku:BAAALgAECgMJAwABLgAFFAUJEAAHAOUVAA==.Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8vAAINAAkJdhgIJQADAgANAAkJdhgIJQADAgAAAA==.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Beastcloud:BAAALgAECgIJAgABLgAECgkJJQAHAOwcAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAABLgAECn8cAAICAAgJ/BTDTwCzAQACAAgJ/BTDTwCzAQAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIQAAcJZSB1SAAJAgAQAAcJZSB1SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMQAAIJOQybewB/AAAQAAIJUAWbewB/AAARAAIJOQwOCAA2AAAuAAQKfy0AAxEACQnYI78BAAsDABEACQnYI78BAAsDABAAAgkMHInnAK8AAAAA.Bonedmuch:BAAALgADCgUJCgABLgAECgkJLgAJAGMWAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAABLgAECn8YAAISAAcJ3wa6EADRAAASAAcJ3wa6EADRAAAAAA==.Breadria:BAAALgADCgMJAwABLgAFFAMJBwATAH0FAA==.Bremitin:BAAALgADCggJCAABLgAECgkJMQARAJ8PAA==.Bremitus:BAAALgADCgkJCQABLgAECgkJMQARAJ8PAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewey:BAAALgAFFAEJAQAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8ZAAIGAAgJ5B+wNwAXAgAGAAgJ5B+wNwAXAgAAAA==.Brud:BAAALgAECgMJCQAAAA==.Brunstan:BAACLgAFFH8RAAIUAAQJfh+fCgBxAQAUAAQJfh+fCgBxAQAuAAQKfxcAAhQACQnSHm8DAHYCABQACQnSHm8DAHYCAAAA.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8YAAMIAAcJPRN1BQCDAQAIAAUJaxN1BQCDAQAFAAIJfQygRQCiAAAuAAQKfyAABAgACQktH5oPAK8CAAgACQktH5oPAK8CABUAAQm+F78pAEEAAAUAAQkHAQWpACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8gAAIWAAcJYghQpAAcAQAWAAcJYghQpAAcAQAAAA==.',
Ca='Cain:BAAALgADCgMJCAAAAA==.Calvisi:BAAALgAECgYJDgAAAA==.Calvisichaos:BAABLgAECn8tAAIXAAkJPhMLBgDXAQAXAAkJPhMLBgDXAQAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECggJDwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgQJBAAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAAALgAECgYJDQAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Critoliz:BAAALgAFFAIJAQAAAA==.Cropala:BAABLgAECn8gAAIQAAkJVBLYPADzAQAQAAkJVBLYPADzAQAAAA==.Cruelcodex:BAAALgAECgEJAQAAAA==.',
['Cà']='Càtfish:BAAALgADCgEJAQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkrequiem:BAAALgADCgIJAgAAAA==.Darkwingduck:BAAALgADCgEJAQAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJBwAAAA==.',
De='Decapitator:BAAALgAECgMJAwAAAA==.Deleto:BAABLgAECn8iAAMBAAgJVxQiCwCHAQABAAgJlhAiCwCHAQACAAYJYBjkfwBBAQAAAA==.Dellandre:BAAALgAECgYJEQABLgAECgkJLgARACcKAA==.Delta:BAABLgAECn8SAAIGAAgJHQfqtACRAAAGAAgJHQfqtACRAAAAAA==.Delti:BAAALgAECgUJBgABLgAECggJHgAGACAXAA==.Demondozer:BAAALgAECgMJAwABLgAECgUJCQAEAAAAAA==.Demony:BAAALgAECgEJAQABLgAFFAEJAQAEAAAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAABLgAECn8YAAIDAAkJYAiXWQB+AQADAAkJYAiXWQB+AQAAAA==.Digichowder:BAACLgAFFH8IAAIYAAMJnBcDJADxAAAYAAMJnBcDJADxAAAuAAQKfyQAAw8ACQluI9ACAO8CAA8ACAkOIdACAO8CABgABQk6GXA8AC8BAAAA.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgYJDgAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
['Dä']='Därkrävèn:BAAALgAECgYJBgAAAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn8zAAMXAAkJsSAIAQDYAgAXAAkJsSAIAQDYAgADAAUJ+hGgewAvAQAAAA==.Eldhe:BAAALgAECgQJBQAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAABLgAECn8WAAMUAAgJjhU0MwCgAQAUAAcJARc0MwCgAQAZAAQJVw7nMgDzAAAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAABLgAECn8dAAIMAAgJ+BqkBgB4AgAMAAgJ+BqkBgB4AgAAAA==.Endlol:BAABLgAECn8vAAMaAAkJFyEeBgDWAgAaAAkJFyEeBgDWAgAbAAEJUh8TVwBVAAABLgAFFAIJAwAEAAAAAA==.',
Er='Eredaria:BAAALgAECgUJCQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8UAAIWAAcJxhFNDwCeAQAWAAcJxhFNDwCeAQAuAAQKfyQAAhYACQk+IBsjAOYCABYACQk+IBsjAOYCAAAA.Eronel:BAABLgAECn8eAAICAAcJ7RowWQCaAQACAAcJ7RowWQCaAQAAAA==.',
Es='Esv:BAAALgAFFAEJAQABLgAFFAQJEgAWABwQAA==.',
Ex='Excido:BAAALgAECgEJAQAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgIJAwAAAA==.Fadedheart:BAAALgAECgQJBwABLgAECgkJMgACAPIfAA==.Fadedmystic:BAAALgAECgQJBAAAAA==.Fadednight:BAABLgAECn8yAAMCAAkJ8h+DEgC9AgACAAkJ8h+DEgC9AgAcAAEJ1QHrWwARAAAAAA==.Faeyir:BAACLgAFFH8MAAIWAAQJKQwvUQApAQAWAAQJKQwvUQApAQAuAAQKfyAAAhYACQmnGz9QAEYCABYACQmnGz9QAEYCAAAA.Fallingmoon:BAABLgAECn8nAAMTAAkJqCD7CQDmAgATAAkJqCD7CQDmAgAUAAEJKRDmigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIWAAMJwBieZQDtAAAWAAMJwBieZQDtAAAuAAQKfysAAhYACQmUITQWALsCABYACQmUITQWALsCAAAA.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgcJDwAAAA==.Fernfondler:BAAALgAFFAIJAwAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoffin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgEJAgABLgAECgMJAwAEAAAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.Frostydh:BAAALgAECgMJAwAAAA==.Frostytotems:BAAALgAECgEJAgAAAA==.Fróstblight:BAAALgAECgkJCAAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgYJCgAAAA==.',
Gi='Gilberticus:BAAALgAECgYJEAABLgAECgkJQQAdACciAA==.Gishmou:BAABLgAECn8eAAIFAAgJKhugJAAHAgAFAAgJKhugJAAHAgAAAA==.',
Go='Goldblade:BAABLgAECn8gAAIQAAgJWhdHQgDjAQAQAAgJWhdHQgDjAQAAAA==.',
Gr='Grayhair:BAAALgAECgQJBAAAAA==.Greyoll:BAAALgAECgYJCAAAAA==.Grimling:BAAALgAECgQJBAABLgAFFAUJEAAHAOUVAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8bAAIcAAcJtSTbAAAmAgAcAAcJtSTbAAAmAgAuAAQKfxsAAhwACQmsJb0BAGcDABwACQmsJb0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAFFAEJAQABLgAFFAcJGwAcALUkAA==.Harleyswar:BAAALgADCgEJAQAAAA==.',
He='Hellmaw:BAAALgAECgYJCwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Holianna:BAAALgAECgIJAgAAAA==.Hollowheart:BAABLgAECn8nAAIFAAkJIBh/HAA+AgAFAAkJIBh/HAA+AgAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Holyknight:BAAALgADCgEJAQAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hy='Hylanna:BAAALgAECgYJCgAAAA==.Hyorinmaru:BAAALgAFFAEJAQAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECgkJMQARAJ8PAA==.',
Ic='Ici:BAABLgAECn8uAAMQAAkJdgdMcwBpAQAQAAkJdgdMcwBpAQAKAAQJuA6YUgDFAAAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Ik='Ikilledkeny:BAAALgAFFAIJAQAAAA==.',
Im='Imlerith:BAAALgADCgQJBgAAAA==.',
In='Intensifies:BAAALgAECgcJDgAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Isabellà:BAAALgAECgUJBQABLgAECgkJIwAeAKELAA==.Iskothar:BAABLgAECn8kAAIRAAgJ9R2IBgBVAgARAAgJ9R2IBgBVAgAAAA==.',
Iv='Ivarboneless:BAAALgAECgYJEwAAAA==.',
Ja='Jackz:BAAALgAECgkJCQAAAA==.Jackzlock:BAAALgAECgkJAQAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.Jankball:BAAALgAFFAIJAQAAAA==.',
Je='Jefftrep:BAAALgAECgQJAwAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAAALgAECgkJEgAAAA==.',
Ke='Ketesh:BAABLgAECn80AAIfAAkJ2h6OAwDHAgAfAAkJ2h6OAwDHAgABLgAFFAQJEQALAAsOAA==.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgADCgkJGQABLgAECggJJAARAPUdAA==.',
Kl='Kleanse:BAAALgAFFAIJAQAAAA==.',
Kn='Knastey:BAABLgAECn8VAAQeAAYJ4Be/LQA/AQAeAAYJ4Be/LQA/AQANAAYJZAqbcQABAQAgAAEJWxKCMgA3AAAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAABLgAECn8VAAILAAYJIAVPVwCtAAALAAYJIAVPVwCtAAAAAA==.',
Kr='Krej:BAABLgAECn8UAAIcAAkJOxpRDgD3AQAcAAkJOxpRDgD3AQABLgAFFAUJEAAHAOUVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
Ky='Kyronix:BAAALgAECgMJBwAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJDgAAAA==.',
La='Langarde:BAABLgAECn8dAAIOAAgJBQ+JGABVAQAOAAgJBQ+JGABVAQAAAA==.Laoghaire:BAABLgAECn8YAAIHAAcJ+ANRNQCzAAAHAAcJ+ANRNQCzAAAAAA==.',
Le='Leonz:BAACLgAFFH8WAAIYAAcJRR6ZAgABAgAYAAcJRR6ZAgABAgAuAAQKfywAAhgACQnLIvMDAA4DABgACQnLIvMDAA4DAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAEBLgAECn8mAAICAAkJdBlUNwACAgACAAkJdBlUNwACAgAAAA==.',
Li='Liraffemynn:BAACLgAFFH8KAAIhAAMJxRxgIgDoAAAhAAMJxRxgIgDoAAAuAAQKfzwAAiEACQk2I98CAHUDACEACQk2I98CAHUDAAAA.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lonranir:BAAALgAECgMJAwAAAA==.Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Lucii:BAAALgADCgEJAQABLgAFFAcJGwAcALUkAA==.Luckylucy:BAABLgAECn8XAAIbAAYJhhaYJwBoAQAbAAYJhhaYJwBoAQAAAA==.',
Ma='Madarauchiha:BAABLgAECn8VAAICAAYJxxVwggB+AQACAAYJxxVwggB+AQAAAA==.Magus:BAAALgADCgkJEQABLgAECgMJBwAEAAAAAA==.Maldran:BAABLgAECn8XAAIFAAcJjh1pIgAWAgAFAAcJjh1pIgAWAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAABLgAECn8UAAITAAcJOQjSeQAgAQATAAcJOQjSeQAgAQAAAA==.Marien:BAABLgAECn8dAAIcAAgJ8BnmDQD+AQAcAAgJ8BnmDQD+AQAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAACLgAFFH8HAAIWAAIJKSR8dADKAAAWAAIJKSR8dADKAAAuAAQKfycAAhYACQmmIVYYAK8CABYACQmmIVYYAK8CAAAA.',
Me='Mehuman:BAAALgAECgUJEAAAAA==.Mehumanhuntr:BAAALgAECgQJBAAAAA==.Mehumanlock:BAABLgAECn8jAAIXAAkJ+xEoBwC3AQAXAAkJ+xEoBwC3AQAAAA==.Merlinn:BAAALgADCgkJCQAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgYJCgAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgAECgYJCgAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Moonscale:BAAALgADCgYJBgAAAA==.Mordaci:BAAALgADCgQJBQABLgAECggJDAAEAAAAAA==.Mortstan:BAAALgAECgcJDQAAAA==.',
['Må']='Månni:BAAALgADCgEJAQAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgUJCQAAAA==.Nailz:BAABLgAECn8eAAIGAAgJIBdLTQDAAQAGAAgJIBdLTQDAAQAAAA==.Nakama:BAAALgADCgYJBgABLgAECggJKQAFACcQAA==.Narie:BAAALgAECgMJAwAAAA==.Nasaug:BAAALgAECgUJBwABLgAECgkJMQARAJ8PAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECggJEwAAAA==.',
Ni='Nightlion:BAAALgAECgYJEwAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAcJGAADADkZAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAcJGAADADkZAA==.Noahvoker:BAAALgAECggJEQABLgAFFAcJGAADADkZAA==.Noahwarlock:BAACLgAFFH8YAAQDAAcJORlVDwBkAQADAAUJuR9VDwBkAQAXAAMJXxEGBwDyAAAiAAEJkSPIEwBUAAAuAAQKfy8ABAMACQn+IzIEAD4DAAMACAnkIzIEAD4DABcABAl0IkEaAHsBACIAAwmsI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQABLgAECgUJEwAEAAAAAA==.Nook:BAAALgADCgUJBgAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJDwAAAA==.',
Oh='Ohmylantä:BAABLgAECn8dAAIWAAgJPg3ZdQByAQAWAAgJPg3ZdQByAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8XAAIQAAkJcRqbJgBKAgAQAAkJcRqbJgBKAgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orator:BAAALgAFFAIJAQAAAA==.Orbeck:BAAALgAECggJCAABLgAFFAcJGwAJAFMeAA==.Ormond:BAAALgAECgYJDAAAAA==.Orochinchin:BAAALgAECgMJAwABLgAFFAcJGwAcALUkAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgcJEwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8iAAMjAAkJCwtwDgA+AQAjAAkJCwtwDgA+AQAHAAMJRgbPTwBGAAAAAA==.',
Pa='Pachane:BAAALgAECgQJCwAAAA==.Paldozer:BAAALgAECgUJCQABLgAECgUJCQAEAAAAAA==.Pallywacker:BAABLgAECn8qAAIRAAgJ1RGyEgBzAQARAAgJ1RGyEgBzAQAAAA==.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.Panzerkìn:BAAALgAECgcJCAAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.',
Pi='Pigishdog:BAABLgAECn9CAAIDAAkJ4xtSGAB8AgADAAkJ4xtSGAB8AgAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethedruid:BAAALgAECgEJAQABLgAECgEJBwAEAAAAAA==.Pokethemonk:BAAALgAECgEJBwAAAA==.Poshingtang:BAABLgAECn8pAAQFAAkJqQxIOQCdAQAFAAkJqQxIOQCdAQAIAAgJHhG8NgB4AQAVAAMJSwP+JQB3AAAAAA==.',
Pu='Pulsar:BAAALgADCggJDQAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn8pAAMFAAgJJxCJQgB3AQAFAAgJJxCJQgB3AQAIAAEJnxD5iQAxAAAAAA==.Quintessence:BAAALgAECgMJAwAAAA==.',
Ra='Rabidbutt:BAAALgAFFAIJAwABLgAFFAUJEAAMALEkAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8ZAAICAAUJDBg8sADuAAACAAUJDBg8sADuAAAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8ZAAIKAAYJygJPVQC4AAAKAAYJygJPVQC4AAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rikku:BAAALgAECggJCAABLgAFFAcJGAAIAD0TAA==.Ripndip:BAAALgAFFAIJAQAAAA==.Riprock:BAAALgAECgIJAQABLgAFFAIJAQAEAAAAAA==.Rixas:BAAALgAECgEJAQABLgAECgkJLgADAPwcAA==.',
Rn='Rn:BAACLgAFFH8FAAIPAAQJShgJDwApAQAPAAQJShgJDwApAQAuAAQKfx4AAw8ACQklIkEBAEYDAA8ACQkIIkEBAEYDABgABwkvIyQpABcCAAEuAAUUCAkiAA8AgyQA.',
Ro='Roguehiro:BAABLgAECn8gAAIRAAgJZSE1BwBuAgARAAgJZSE1BwBuAgAAAA==.Rooter:BAACLgAFFH8QAAIMAAUJsST6BgADAgAMAAUJsST6BgADAgAuAAQKfzsAAwwACAmPJUMDAP8CAAwACAmPJUMDAP8CAAsABwnsGdcfALkBAAAA.Rosalynñ:BAABLgAECn8mAAIXAAgJDwomEAAWAQAXAAgJDwomEAAWAQAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAECgEJAQABLgAFFAIJAQAEAAAAAA==.',
Sa='Saelis:BAACLgAFFH8TAAINAAQJOhjTIAAkAQANAAQJOhjTIAAkAQAuAAQKfx0AAw0ACQnAHhwWAIUCAA0ACQnAHhwWAIUCACAABgnwGaQPAIkBAAAA.Salen:BAAALgADCgIJAgAAAA==.Samshara:BAAALgADCgcJDAABLgAECggJMQAZAKIaAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECggJCgAAAA==.Scrawni:BAAALgAECgQJBAABLgAFFAUJEAAHAOUVAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Senia:BAAALgAECgkJEQAAAA==.Seong:BAACLgAFFH8bAAIJAAcJUx6MBAD/AQAJAAcJUx6MBAD/AQAuAAQKfyEAAgkACQmAIgUFADkDAAkACQmAIgUFADkDAAAA.Seongdh:BAAALgAECggJDQABLgAFFAcJGwAJAFMeAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgUJBwABLgAECgkJIwAeAKELAA==.',
Sh='Shadowdooms:BAABLgAECn8WAAMCAAgJFBkfYQDQAQACAAgJFBkfYQDQAQABAAEJSxf2FABFAAAAAA==.Shadowfur:BAAALgADCgkJCQABLgAECggJMgAKADAfAA==.Shamynna:BAAALgAECgIJAwAAAA==.Sharreth:BAAALgAECgIJAgAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8uAAITAAkJAxMmMQDuAQATAAkJAxMmMQDuAQAAAA==.Shish:BAAALgAECggJCwAAAA==.Shockawar:BAACLgAFFH8WAAIYAAUJeRwxAwDEAQAYAAUJeRwxAwDEAQAuAAQKfxQAAhgACQmrHmYYAIgCABgACQmrHmYYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8YAAQZAAUJxyGZBgB8AQAZAAQJRSGZBgB8AQAUAAMJIiDGEAAqAQATAAQJfRswRADmAAAuAAQKfxsABBMACAk8IdMVAIkCABMABwnxIdMVAIkCABQABwlKIcoaAFMCABkAAwm3IVQrACcBAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECggJCwAEAAAAAA==.',
Si='Silverwolf:BAAALgADCgEJAQAAAA==.Sinestra:BAAALgAECgEJAQAAAA==.',
Sl='Slagscar:BAAALgAFFAIJAQAAAA==.Slaughterhse:BAABLgAECn8UAAIWAAYJ5gMF3QC/AAAWAAYJ5gMF3QC/AAAAAA==.Slootar:BAABLgAECn8UAAQNAAcJ5xuIJAAoAgANAAcJ5xuIJAAoAgAeAAIJuxBfbABuAAAgAAIJMAaQQAAuAAAAAA==.Slugs:BAAALgAECgUJCAAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIhAAgJ7xb8FQAUAgAhAAgJ7xb8FQAUAgAAAA==.',
So='Solareth:BAAALgAECgEJAQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn8xAAIZAAgJohpgEQAIAgAZAAgJohpgEQAIAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sunstrike:BAAALgAECgEJAgAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Tabul:BAAALgADCgUJBAAAAA==.Takka:BAABLgAECn8aAAIFAAgJHR1rEgCQAgAFAAgJHR1rEgCQAgAAAA==.Talden:BAABLgAECn86AAMQAAkJMhwQFwCcAgAQAAkJMhwQFwCcAgARAAEJ/AW7RAAsAAAAAA==.Talkamar:BAABLgAECn8iAAIdAAkJ6RCgGgCyAQAdAAkJ6RCgGgCyAQAAAA==.Taylorswift:BAABLgAECn8uAAIWAAkJ3hcmKgBWAgAWAAkJ3hcmKgBWAgAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn8uAAIRAAkJJwoYFwA8AQARAAkJJwoYFwA8AQAAAA==.Thenard:BAABLgAECn8iAAITAAgJPBORRACqAQATAAgJPBORRACqAQAAAA==.Thukunaenhan:BAAALgAECgQJBAABLgAFFAMJCQAWAJ8UAA==.Thukunamage:BAACLgAFFH8JAAIWAAMJnxSvXwD8AAAWAAMJnxSvXwD8AAAuAAQKfykAAhYACQmMICEcAJkCABYACQmMICEcAJkCAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tili:BAAALgADCgUJBAAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAABLgAECn8dAAQDAAkJTBHkSQCoAQADAAcJNxHkSQCoAQAXAAMJRBVMTwCAAAAiAAEJlA40LwA7AAAAAA==.Touritos:BAABLgAECn8bAAIIAAgJQRGeLQBjAQAIAAgJQRGeLQBjAQAAAA==.',
Tr='Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgADCgcJBwAAAA==.Tulirenpo:BAAALgAECgUJBQAAAA==.Tunk:BAAALgAFFAIJAQAAAA==.Tuskal:BAAALgAECgIJAwAAAA==.',
Tw='Twogora:BAAALgAECgYJCQAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMkAAgJ6RbMEwB4AgAkAAgJ6RbMEwB4AgAlAAEJtgtBHQBBAAAAAA==.Tydru:BAAALgAFFAIJAQAAAA==.Tyler:BAACLgAFFH8LAAIGAAQJfhXYDwBPAQAGAAQJfhXYDwBPAQAuAAQKfxsAAgYACAkOHTgcAKkCAAYACAkOHTgcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAAALgAECgYJEAAAAA==.',
Um='Umariel:BAAALgAFFAIJAQAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgMJBAAAAA==.Valr:BAABLgAECn8xAAIRAAkJnw8REwBtAQARAAkJnw8REwBtAQAAAA==.Vancliffe:BAAALgAECgQJBAABLgAFFAUJEAAHAOUVAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8SAAIWAAQJHBCPSAA5AQAWAAQJHBCPSAA5AQAuAAQKfy4AAhYACAl8G0k8AA8CABYACAl8G0k8AA8CAAAA.Vsesosorry:BAABLgAFFH8LAAIFAAQJnQj8NQDaAAAFAAQJnQj8NQDaAAABLgAFFAQJEgAWABwQAA==.Vsè:BAAALgADCgUJBQABLgAFFAQJEgAWABwQAA==.',
Vy='Vyke:BAAALgAECgYJCQABLgAFFAcJGwAJAFMeAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgUJCQAAAA==.Warlockedin:BAAALgAECgYJDQAAAA==.',
We='Weierstrass:BAAALgAFFAEJAQABLgAFFAcJGwAcALUkAA==.',
Wo='Worgenkrantz:BAABLgAECn8jAAMeAAkJoQtiJQB1AQAeAAkJoQtiJQB1AQANAAcJeAJQkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8QAAIHAAUJ5RVfCgA0AQAHAAUJ5RVfCgA0AQAuAAQKfzAAAwcACAlsI/MKAEgCAAcACAntH/MKAEgCACMAAglCE0sfAHYAAAAA.',
Xo='Xolòtl:BAABLgAECn8fAAIOAAgJhhYZFADLAQAOAAgJhhYZFADLAQABLgAFFAUJEAAHAOUVAA==.Xoss:BAAALgAFFAIJAQAAAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAIJBQAWAJIaAA==.',
Yi='Yin:BAAALgAECgcJCAAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zakuso:BAAALgAECgQJCQAAAA==.Zalyia:BAABLgAECn8uAAIaAAkJlA18HgCsAQAaAAkJlA18HgCsAQAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIWAAgJcBVpaQADAgAWAAgJcBVpaQADAgAAAA==.Zexpert:BAABLgAECn8cAAQmAAgJSReiDQAAAgAmAAcJIhiiDQAAAgALAAcJnhUvKAB8AQAMAAQJfgwFNADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgIJBAABLgAECggJHAAmAEkXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIGAAgJORqFMAA5AgAGAAgJORqFMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQQAAUJQBbzrAADAQAQAAQJxhjzrAADAQAKAAMJyRCQcgCxAAARAAQJ+QiuMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECgUJCAAAAA==.',
['Àn']='Àngron:BAAALgADCgYJDAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgYJCwAAAA==.',
['Èo']='Èomer:BAAALgAECgEJAQAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgIJAgAAAA==.',
['ßa']='ßaroness:BAAALgADCgUJCQAAAA==.',
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
